<#
  New-CloudAccess.ps1

  Lets cloud Claude threads reach the box over ssh (#2753): makes the cloud
  key and the bridge's token, puts both on the box, proves they get in, and
  writes the two lines the cloud environment needs into one file for the
  person who holds the environment's settings to paste there. Decided by
  Patrick on 19 Oct 2026 (#2750, C): cloud threads get an ssh key to the box.
  Run on a machine whose own key already works, after Install-Bridge.ps1.

      .\scripts\vps\New-CloudAccess.ps1           make them (a second run
                                                  replaces both, so the old
                                                  pair stops working)
      .\scripts\vps\New-CloudAccess.ps1 -Remove   take the cloud key off the
                                                  box and delete the token, so
                                                  no cloud thread gets in

  THE TWO HALVES, and why neither is any use alone:
    the cloud key   an ed25519 key with no passphrase, its public half on the
                    box with from="127.0.0.1" in front, so sshd takes it only
                    from the box itself, which means only through the bridge.
                    Port 22's own address list (Set-SshScope.ps1) is not
                    touched and never needs a cloud address.
    the token       what bridge.js asks for before it opens a WebSocket at
                    all, in token.txt in the bridge's folder, which only
                    SYSTEM, Administrators and the bridge's own task can read
                    (Install-Bridge.ps1). It is sent on ssh's standard input
                    (Send-Secret.ps1), never on a command line.
  The key's comment is thornswood-cloud, which is how a second run and
  -Remove find the old line. Nothing here touches any other key.

  THE FILE. -Out, by default cloud-access.txt in
  C:\ThornswoodTemps&Worktrees\temp\cloud-access, readable by the person
  running this only. It holds two lines, THORNSWOOD_BOX_KEY_B64=... and
  THORNSWOOD_BOX_TOKEN=..., which go into the cloud environment's variables
  as they are (the token may go under the environment's network secrets for
  thornswood.net instead, as an Authorization: Bearer header). Then the file
  is deleted. Neither value is printed by anything here, and the private key
  is written nowhere else: the copy it was made in is deleted when this ends.
  A cloud thread then runs scripts/vps/Setup-CloudSsh.ps1.
#>
[CmdletBinding()]
param(
    [string]$VpsHost = '',
    [string]$VpsUser = '',
    [string]$BridgeRoot = 'C:\Thornswood-Bridge',
    [string]$Out = 'C:\ThornswoodTemps&Worktrees\temp\cloud-access\cloud-access.txt',
    # Where the proof connects, the same address connect.js uses by default.
    [string]$BoxUrl = 'wss://thornswood.net/box/',
    [switch]$Remove,
    [switch]$NoPause
)

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Vps.ps1')
. (Join-Path $Here 'Send-Secret.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
$comment = 'thornswood-cloud'
foreach ($t in 'ssh', 'ssh-keygen') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client." }
}

# What every run does to the box's key file first: the old cloud line goes.
# Then the new one is added, when there is one.
function Get-KeyFileScript([string]$NewLine) {
    return @"
`$f = 'C:\ProgramData\ssh\administrators_authorized_keys'
`$have = @()
if (Test-Path -LiteralPath `$f) { `$have = @(Get-Content -LiteralPath `$f | Where-Object { `$_.Trim() }) }
`$after = @(`$have | Where-Object { `$_.Trim() -notmatch ' $comment$' })
`$gone = `$have.Count - `$after.Count
`$new = '$($NewLine.Replace("'", "''"))'
if (`$new) { `$after += `$new }
[IO.File]::WriteAllLines(`$f, [string[]]`$after, (New-Object Text.UTF8Encoding(`$false)))
icacls `$f /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
'cloud key line(s) taken off: ' + `$gone + ', key(s) on the box now: ' + `$after.Count
"@
}

# ------------------------------------------------------------------ remove --
if ($Remove) {
    Head 'Taking cloud access away'
    $said = @(Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script (@"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
$(Get-KeyFileScript '')
Remove-Item -LiteralPath '$BridgeRoot\token.txt' -Force -EA SilentlyContinue
if (Test-Path -LiteralPath '$BridgeRoot\token.txt') { 'TOKEN STILL THERE' } else { 'the bridge token is gone, so the bridge refuses everybody' }
'REVOKED'
"@) | ForEach-Object { Say "  $_"; "$_".Trim() })
    if ($said -notcontains 'REVOKED') { Die 'it did not finish. The lines above say how far it got.' }
    Say '  No cloud thread gets in now. Take THORNSWOOD_BOX_KEY_B64 and THORNSWOOD_BOX_TOKEN out of the cloud environment too.' 'Green'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

$node = Get-Command node -ErrorAction SilentlyContinue
$connect = Join-Path (Join-Path $Here 'bridge') 'connect.js'
if (-not $node) { Die 'node is not on PATH, and the proof at the end runs the bridge client with it. Nothing was made.' }
if (-not (Test-Path -LiteralPath $connect)) { Die "not found: $connect. Nothing was made." }

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-cloud-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    # ------------------------------------------------------------- key -----
    Head 'The cloud key'
    $key = Join-Path $work 'cloud_ed25519'
    # An empty passphrase through PowerShell: '""' in some versions and ''
    # in others (Setup-SshKey.ps1 says why), so both are tried and proved.
    $made = $false
    foreach ($empty in '""', '') {
        Remove-Item -LiteralPath $key, "$key.pub" -Force -ErrorAction SilentlyContinue
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        Invoke-ThornswoodNative { & ssh-keygen -q -t ed25519 -N $empty -C $comment -f $key } 2>&1 | Out-Null
        if (Test-Path -LiteralPath "$key.pub") {
            $null = Invoke-ThornswoodNative { & ssh-keygen -y -P '' -f $key } 2>&1
            if ($LASTEXITCODE -eq 0) { $made = $true }
        }
        $ErrorActionPreference = $old
        if ($made) { break }
    }
    if (-not $made) { Die 'could not make a key without a passphrase. Nothing was put on the box.' }
    $pub = ([IO.File]::ReadAllText("$key.pub")).Trim()
    Say ('  made, ' + (Get-ThornswoodSshFingerprint ('x ' + $pub))) 'Green'

    # ------------------------------------------------------------ token ----
    $bytes = New-Object byte[] 32
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $token = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    # ---------------------------------------------------------- the box ----
    Head 'Putting them on the box'
    $said = @(Invoke-ThornswoodSecretRemote -Target $target -SshArgs $ssh -Secret $token -Script (@"
`$tok = `$ThornswoodSecret; `$ThornswoodSecret = `$null
`$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath '$BridgeRoot\bridge.js')) { 'there is no bridge in $BridgeRoot. Run scripts\deploy\Install-Bridge.ps1 first. Nothing was changed.'; exit 1 }
if (-not `$tok -or `$tok -notmatch '^[A-Za-z0-9_-]{40,}$') { 'the token did not arrive whole. Nothing was changed.'; exit 1 }
# Into the bridge's folder, whose rules it takes: SYSTEM, Administrators and
# the bridge's own task. The bridge reads it at every upgrade.
[IO.File]::WriteAllText('$BridgeRoot\token.txt', `$tok, (New-Object Text.UTF8Encoding(`$false)))
`$tok = `$null
'the bridge token is written'
$(Get-KeyFileScript ('from="127.0.0.1" ' + $pub))
'ACCESS ON'
"@) | ForEach-Object { Say "  $_"; "$_".Trim() })
    if ($said -notcontains 'ACCESS ON') { Die 'the box did not take them. The lines above say why.' }

    # ------------------------------------------------------------ proof ----
    Head 'Proving it gets in through the bridge'
    # The same way a cloud thread goes: connect.js as the ProxyCommand with
    # the token in its environment, the cloud key, and the box's host key
    # checked as every script checks it. The token is in this process's
    # environment for the length of the call and on no command line.
    $env:THORNSWOOD_BOX_TOKEN = $token
    $env:THORNSWOOD_BOX_URL = $BoxUrl
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $proof = @(Invoke-ThornswoodNative {
        & ssh -F none -i $key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=20 `
            -o ("ProxyCommand=`"" + $node.Source + "`" `"" + $connect + "`"") $target 'echo THORNSWOOD_OK'
    } 2>&1 | ForEach-Object { "$_" })
    $ErrorActionPreference = $old
    Remove-Item Env:THORNSWOOD_BOX_TOKEN, Env:THORNSWOOD_BOX_URL -ErrorAction SilentlyContinue
    if (($proof -join '') -notmatch 'THORNSWOOD_OK') {
        $proof | Select-Object -Last 5 | ForEach-Object { Say "  $_" 'DarkGray' }
        Say '  It did not get in, so no file was written. Both are still on the box; run this again once the lines above are dealt with,' 'Red'
        Say '  or -Remove to take them off. A "box bridge:" line is the bridge or Caddy; "Permission denied" is the key.' 'Red'
        exit 1
    }
    Say '  ssh through the bridge with the cloud key got in' 'Green'

    # ------------------------------------------------------------- file ----
    Head 'The file for the cloud environment'
    $dir = Split-Path -Parent $Out
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllText($Out, '')
    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        $null = & icacls $Out /inheritance:r /grant:r ("{0}:F" -f [Security.Principal.WindowsIdentity]::GetCurrent().Name) 2>&1
    } else { & chmod 600 $Out }
    $keyB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($key))
    [IO.File]::WriteAllText($Out, ("THORNSWOOD_BOX_KEY_B64=$keyB64`nTHORNSWOOD_BOX_TOKEN=$token`n"), (New-Object Text.UTF8Encoding($false)))
    $keyB64 = $null; $token = $null
    Say "  $Out" 'Green'
    Write-Host ''
    Say '  Its two lines go into the cloud environment''s variables as they are: Project settings, Cloud environment, the gear' 'White'
    Say '  beside the environment. Then delete the file. A new cloud session picks them up and runs' 'White'
    Say '  scripts/vps/Setup-CloudSsh.ps1.' 'White'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
