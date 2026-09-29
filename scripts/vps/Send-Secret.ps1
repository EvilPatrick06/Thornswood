<#
  Send-Secret.ps1

  How a secret goes to the VPS: on ssh's standard input, never on a command
  line. Dot-source it beside Vps.ps1:

      . (Join-Path $Here '..\vps\Send-Secret.ps1')
      Invoke-ThornswoodSecretRemote -Target "$User@$Vps" -SshArgs $ssh -Secret $value -Script @"
      `$pw = `$ThornswoodSecret; `$ThornswoodSecret = `$null
      ...
      "@

  The script that runs on the VPS finds the value in $ThornswoodSecret. The
  script itself names no secret, so it can go the usual way.

  WHY THIS EXISTS (issue #451). Every script here that sent a secret (the
  server password, the site password, the bot token and the site's bot key,
  the Discord client secret, a webhook, the build runner's registration token)
  base64'd it into the remote script, and the remote script went to ssh as
  powershell -NoProfile -EncodedCommand <that>. So the value sat in the command
  line of ssh on this machine and of cmd.exe and powershell.exe on the VPS for
  the length of the call, where the process list, a process creation audit
  event or anything reading Win32_Process could see it. Base64 is transport
  encoding and hides nothing. Over 6,000 characters the script went as a file
  in C:\Windows\Temp instead, and then the value sat in a file on both
  machines. Comments beside two of them said the value was never on a command
  line on either machine, which was not true.

  HOW. The value is base64'd (so no quoting, code page or byte order mark can
  change it) and written to ssh's standard input. ssh carries its standard
  input to the remote command's, cmd.exe hands it on to powershell, and the
  first line of the remote script reads one line of it. Only the script goes
  on the command line, and when it is too long for that, only the script goes
  by file: the value is never in either. Watch-Services.ps1 -Webhook has sent
  the alerts webhook this way since 28 September.

  Measured on this machine on 29 September, in Windows PowerShell 5.1 and in
  PowerShell 7: a value piped into powershell -EncodedCommand this way arrives
  whole, and no process command line holds it while the script runs
  (tests\test-secret-channel.ps1 repeats that on every run).

  Never print the value, including in an error message.
#>

# The first thing the far side runs: one line of standard input, anything that
# is not base64 dropped (a byte order mark or a stray CR), decoded as UTF-8.
# Caught and never shown: an error here would print the line.
function Get-ThornswoodSecretPrelude {
    return @'
$ProgressPreference = 'SilentlyContinue'
$ThornswoodSecret = ''
try { $ThornswoodSecret = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((('' + [Console]::In.ReadLine()) -replace '[^A-Za-z0-9+/=]', ''))) } catch { }
'@
}

# What goes on standard input for a value: base64 of its UTF-8 bytes, one line.
function ConvertTo-ThornswoodSecretWire([AllowEmptyString()][string]$Secret) {
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$Secret))
}

# Runs $Script on the VPS with $Secret on standard input, and hands back what
# the far side printed (2>&1, the same as every Remote here).
#   -Target   user@host
#   -SshArgs  the script's own ssh options (@ssh), used for ssh and scp alike
#   -Bypass   -ExecutionPolicy Bypass, for a script that dot-sources a file
#   -Limit    the longest command line sent; over it the script goes by file
function Invoke-ThornswoodSecretRemote {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [string[]]$SshArgs = @(),
        [Parameter(Mandatory = $true)][string]$Script,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Secret,
        [switch]$Bypass,
        [int]$Limit = 6000
    )
    # Host key checking on (issue #450), whatever the caller passed. ssh takes
    # the first value it is given for an option, so a caller's own weaker
    # StrictHostKeyChecking would win over one added here: that is refused,
    # before the secret goes anywhere, rather than quietly overridden.
    $weak = @($SshArgs | Where-Object { $_ -match '(?i)StrictHostKeyChecking\s*=\s*(?!yes\b)' })
    if ($weak.Count) { throw ('ssh options with host key checking turned down (' + ($weak -join ', ') + '). A secret goes only to the box whose key is pinned. Nothing was sent.') }
    $SshArgs = @($SshArgs) + @('-o', 'StrictHostKeyChecking=yes')
    $full = (Get-ThornswoodSecretPrelude) + "`r`n" + $Script
    $wire = ConvertTo-ThornswoodSecretWire $Secret
    $Secret = $null
    # Plain ASCII on the pipe whichever PowerShell runs this. Base64 is ASCII,
    # and this keeps a byte order mark off the front of it.
    $OutputEncoding = New-Object Text.ASCIIEncoding
    $policy = ''
    if ($Bypass) { $policy = ' -ExecutionPolicy Bypass' }
    $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
    $cmd = 'powershell -NoProfile' + $policy + ' -EncodedCommand ' + $e
    try {
        if ($cmd.Length -le $Limit) {
            return ($wire | & ssh @SshArgs $Target $cmd 2>&1)
        }
        # Too long for one command line (cmd.exe stops at 8,191 characters and
        # says nothing). The script goes up as a file of its own name, run and
        # removed; the value still goes on standard input, never in the file.
        # The path goes bare: ours, no spaces, works under cmd.exe and
        # PowerShell alike (Remote.ps1 says how that was measured).
        $far = 'C:/Windows/Temp/thornswood-remote-' + [Guid]::NewGuid().ToString('N') + '.ps1'
        $tmp = [IO.Path]::GetTempFileName()
        try {
            [IO.File]::WriteAllText($tmp, $full, (New-Object Text.UTF8Encoding($true)))
            & scp @SshArgs $tmp "${Target}:$far" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "could not send a script to $Target. Nothing was run." }
            $wire | & ssh @SshArgs $Target "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
            $rc = $LASTEXITCODE
            & ssh @SshArgs $Target "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
            # The far end's exit code, not the tidy up's.
            $global:LASTEXITCODE = $rc
        }
        finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    finally { $wire = $null }
}
