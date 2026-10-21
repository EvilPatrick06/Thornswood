<#
  Send-Script.ps1

  The one way a script here runs PowerShell on the VPS. Dot-source it beside
  Vps.ps1:

      . (Join-Path $Here '..\vps\Send-Script.ps1')
      function Remote($script) { Invoke-ThornswoodRemote -Target "$User@$Vps" -SshArgs $ssh -Script $script }

  WHY THIS EXISTS (issue #1070). Seventeen scripts carried their own copy of
  Remote($script), and four more a copy of their own under another name.
  Over 6,000 characters each copy sent the script as a file to one fixed path
  on the VPS (C:/Windows/Temp/thornswood-remote.ps1 in seventeen of them), so
  two runs at once, from two machines or a lane and a person, could run or
  delete each other's script. And each copy ran the file, then removed it,
  and the removal's exit code was the last one the caller saw, so a script
  that failed on the far side looked like one that worked.

  WHAT IT DOES. Under the limit the script goes on the command line, one
  round trip. Over it, the script goes up as a file of its own name
  (thornswood-remote-<guid>.ps1), is run from there, and is removed whether
  the run worked or not. $LASTEXITCODE afterwards is the far side's, never the
  tidy up's.

  Why a file at all: sshd on Windows hands the command to cmd.exe, which stops
  at 8,191 characters and says nothing, and base64 of UTF-16 is about 2.7
  times the script. On 17 and 20 September a long block arrived cut in half
  and the far side complained about a brace in a script nobody could see.

  The path goes bare, with no quotes round it: it is ours and has no spaces.
  Measured on this machine on 24 September, not on the VPS: bare runs whether
  cmd.exe or Windows PowerShell hands the line on, and the path in single
  quotes fails under cmd.exe (tests\test-remote-big-script.ps1).

  The file is written UTF-8 with a byte order mark, so Windows PowerShell on
  the box reads it as UTF-8 whichever PowerShell sent it.

  Host key checking is always on (issues #450 and #1078): a caller's own
  weaker StrictHostKeyChecking is refused before anything is sent, because
  ssh takes the first value it is given for an option and a weaker one would
  win over the one added here.

  A secret never goes through here as part of the script: Send-Secret.ps1
  puts it on standard input, and uses this for the rest.

  A warning ssh prints on stderr is not a failure (issue #941): ssh and scp
  run inside Invoke-ThornswoodNative (Vps.ps1), so the OpenSSH post-quantum
  warning does not stop a Windows PowerShell 5.1 caller, and whether the far
  side ran is ssh's exit code, the same under PowerShell 7.
#>

. (Join-Path $PSScriptRoot 'Vps.ps1')

# Runs $Script on the VPS and hands back what the far side printed (2>&1, the
# same as every Remote here).
#   -Target   user@host
#   -SshArgs  the caller's ssh options (@ssh), used for ssh and scp alike
#   -Bypass   -ExecutionPolicy Bypass on the command line as well, for a
#             script that dot-sources a file (the file form always has it)
#   -Limit    the longest command line sent; over it the script goes by file
#   -Stdin    one line for the far side's standard input (Send-Secret.ps1)
function Invoke-ThornswoodRemote {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [string[]]$SshArgs = @(),
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Script,
        [switch]$Bypass,
        [int]$Limit = 6000,
        [AllowEmptyString()][string]$Stdin
    )
    $weak = @($SshArgs | Where-Object { $_ -match '(?i)StrictHostKeyChecking\s*=\s*(?!yes\b)' })
    if ($weak.Count) { throw ('ssh options with host key checking turned down (' + ($weak -join ', ') + '). Only the box whose key is pinned is talked to. Nothing was sent.') }
    $ssh = @(@($SshArgs | Where-Object { $_ }) + @('-o', 'StrictHostKeyChecking=yes'))
    $piped = $PSBoundParameters.ContainsKey('Stdin')
    if ($piped) {
        # Plain ASCII on the pipe whichever PowerShell runs this, so no byte
        # order mark goes in front of the line.
        $OutputEncoding = New-Object Text.ASCIIEncoding
    }

    $policy = ''
    if ($Bypass) { $policy = ' -ExecutionPolicy Bypass' }
    $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    $cmd = 'powershell -NoProfile' + $policy + ' -EncodedCommand ' + $e
    if ($cmd.Length -le $Limit) {
        if ($piped) { return ($Stdin | Invoke-ThornswoodNative { $input | & ssh @ssh $Target $cmd } 2>&1) }
        return (Invoke-ThornswoodNative { & ssh @ssh $Target $cmd } 2>&1)
    }

    $far = 'C:/Windows/Temp/thornswood-remote-' + [Guid]::NewGuid().ToString('N') + '.ps1'
    $tmp = [IO.Path]::GetTempFileName()
    $sent = $false
    $rc = 1
    try {
        [IO.File]::WriteAllText($tmp, $Script, (New-Object Text.UTF8Encoding($true)))
        Invoke-ThornswoodNative { & scp @ssh $tmp "${Target}:$far" } 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "could not send a script to $Target. Nothing was run." }
        $sent = $true
        $run = "powershell -NoProfile -ExecutionPolicy Bypass -File $far"
        if ($piped) { $Stdin | Invoke-ThornswoodNative { $input | & ssh @ssh $Target $run } 2>&1 }
        else { Invoke-ThornswoodNative { & ssh @ssh $Target $run } 2>&1 }
        $rc = $LASTEXITCODE
    }
    finally {
        # Removed whether the run worked or not, and before anything else can
        # stop this: a script left there is one the next run could trip on.
        if ($sent) { Invoke-ThornswoodNative { & ssh @ssh $Target "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" } 2>&1 | Out-Null }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        # The far side's exit code, not the tidy up's.
        $global:LASTEXITCODE = $rc
    }
}

# Starts $Script on the VPS and leaves it running, for a far side whose life
# is the session's own (Run-OnBox.ps1's run folder, issue #2999). The far
# side reads its standard input to the end: closing it here is how it is told
# to finish, and a session that drops closes it too. Returns the ssh process,
# its standard input and output redirected; what ssh itself says on standard
# error goes to this console as it would for any ssh.
#
# Only the command line form. The file form sends the script up first and
# removes it with a call of its own afterwards, and a session cut between the
# two leaves the file behind, which is what this is for avoiding. A script
# over the limit is refused, before anything is sent.
function Start-ThornswoodRemote {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [string[]]$SshArgs = @(),
        [Parameter(Mandatory = $true)][string]$Script,
        [int]$Limit = 6000
    )
    $weak = @($SshArgs | Where-Object { $_ -match '(?i)StrictHostKeyChecking\s*=\s*(?!yes\b)' })
    if ($weak.Count) { throw ('ssh options with host key checking turned down (' + ($weak -join ', ') + '). Only the box whose key is pinned is talked to. Nothing was sent.') }
    $cmd = 'powershell -NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    if ($cmd.Length -gt $Limit) { throw ('a held script goes on the command line, and this one is ' + $cmd.Length + ' characters there, over ' + $Limit + '. Nothing was sent.') }
    $words = @(@($SshArgs | Where-Object { $_ }) + @('-o', 'StrictHostKeyChecking=yes', $Target, $cmd))
    $bad = @($words | Where-Object { $_ -match '["\r\n]' })
    if ($bad.Count) { throw ('an ssh word holds a double quote or a line break: ' + ($bad -join ' ') + '. Nothing was sent.') }
    # Arguments as one string, which Windows PowerShell 5.1's .NET takes as
    # well as 7's (Add-ThornswoodKnownHostThroughBridge, Vps.ps1).
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'ssh'
    $psi.Arguments = (@($words | ForEach-Object { '"' + $_ + '"' }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    return [Diagnostics.Process]::Start($psi)
}
