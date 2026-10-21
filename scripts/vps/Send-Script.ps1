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
  round trip. Over it, the script goes on ssh's standard input, also one round
  trip: the command line holds only a short reader, which takes the first
  line of its standard input, base64 of the script's UTF-8, and runs it.
  $LASTEXITCODE afterwards is the far side's.

  Why not the command line: sshd on Windows hands the command to cmd.exe,
  which stops at 8,191 characters and says nothing, and base64 of UTF-16 is
  about 2.7 times the script. On 17 and 20 September a long block arrived cut
  in half and the far side complained about a brace in a script nobody could
  see. Standard input has no such limit.

  Why not a file (issue #3027). Until 21 Oct 2026 a long script went up as a
  file of its own name (thornswood-remote-<guid>.ps1 in C:\Windows\Temp), was
  run with a second ssh call and removed with a third. A run cut before the
  third (a bridge reset, the machine running it going away) left the file on
  the box, and nothing there ever removed it. Sent on standard input, the
  script is never written on the box, so there is nothing to remove and no
  call left to miss. The reader runs it the way -File ran the file: an exit
  inside it is the far side's exit code, an error that stops it is 1, and
  otherwise 0.

  The reader strips anything that is not base64 from the line before it
  decodes it (a byte order mark, a stray CR), the same as Send-Secret.ps1's
  prelude, so whichever PowerShell sends it, the box reads the same script.

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

# What a long script runs under on the box: the first line of standard input,
# anything that is not base64 dropped, decoded as UTF-8 and run in the
# reader's own scope, as -Command would run it. Kept apart so the harnesses
# know it when they see it (tests\test-remote-big-script.ps1).
function Get-ThornswoodStdinReader {
    return ". ([scriptblock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((('' + [Console]::In.ReadLine()) -replace '[^A-Za-z0-9+/=]', '')))))"
}

# Runs $Script on the VPS and hands back what the far side printed (2>&1, the
# same as every Remote here).
#   -Target   user@host
#   -SshArgs  the caller's ssh options (@ssh)
#   -Bypass   -ExecutionPolicy Bypass on the command line as well, for a
#             script that dot-sources a file (a long script always has it,
#             as the file it once went as did)
#   -Limit    the longest command line sent; over it the script goes on
#             standard input
#   -Stdin    one line for the far side's standard input (Send-Secret.ps1).
#             For a long script it is the line after the script's own, so
#             the script reads it as its first
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

    # Over the limit: the reader on the command line, the script on standard
    # input, and the caller's line after it. Plain ASCII on the pipe, so no
    # byte order mark goes in front of the script's line.
    $OutputEncoding = New-Object Text.ASCIIEncoding
    $wire = @([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script)))
    if ($piped) { $wire += $Stdin }
    $run = 'powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-ThornswoodStdinReader)))
    return ($wire | Invoke-ThornswoodNative { $input | & ssh @ssh $Target $run } 2>&1)
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
