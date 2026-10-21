<#
  Setup-CloudSsh.ps1

  Sets up ssh to the box from a cloud Claude thread (#2753). Run once at the start of
  a cloud session that needs the box; after it, every script here that talks
  to the box (Remote.ps1, Get-Logs.ps1, the Deploy-* and Install-* scripts)
  works from the cloud the way it does from One, because they all run ssh
  and scp at the box's address and this points that address through the
  bridge.

      pwsh scripts/vps/Setup-CloudSsh.ps1          set it up and prove it
      pwsh scripts/vps/Setup-CloudSsh.ps1 -Test    only check, change nothing

  WHY A BRIDGE. A cloud thread's only way out is an HTTPS proxy, which never
  carries port 22, and port 22 on the box takes no outside address anyway
  (#2891). So ssh goes inside a WebSocket on 443 instead:
  connect.js, as ssh's ProxyCommand, opens wss://thornswood.net/box/, Caddy
  hands it to bridge.js on the box, and bridge.js joins it to the box's own
  sshd on 127.0.0.1. Decided by Patrick on 19 Oct 2026 (#2750, C): cloud
  threads get an ssh key to the box.

  WHAT IT READS, from the cloud environment's settings
  (Grant-BoxAccess.ps1 -Name cloud -MakeKey on One makes both and says where
  they go):
    THORNSWOOD_BOX_KEY_B64  the cloud key's private half, base64. The box
                            takes it only from 127.0.0.1, so only through the
                            bridge (the from= on its line).
    THORNSWOOD_BOX_TOKEN    the cloud's own token. Left out when the environment
                            holds it as a network secret for thornswood.net,
                            which the proxy adds to the request itself.
  Neither is printed, by this or by connect.js.

  WHAT IT WRITES, in this container only:
    ~/.ssh/thornswood_cloud_ed25519   the key, readable by this user only
    ~/.ssh/thornswood-bridge          the bridge client
    ~/.ssh/config                     a Host block for the box's address with
                                      the key, the ProxyCommand and
                                      StrictHostKeyChecking yes, between two
                                      marker lines so a second run replaces it
                                      (Set-ThornswoodBridgeSsh, Vps.ps1)
    ~/.ssh/known_hosts                the box's host key, and only one that
                                      scripts/vps/vps.json pins
                                      (Add-ThornswoodKnownHostThroughBridge)

  THE BOX'S OWN KEY. ssh-keyscan cannot run a ProxyCommand, so it asks
  through bridge/listen.js, a port on this container's loopback that carries
  each connection to the box the same way, and what it is shown goes through
  the same pin as every other key. Nothing that is not pinned reaches
  known_hosts, and ssh itself never adds a key: it runs with
  StrictHostKeyChecking yes from the first connection.

  openssh-client is installed with apt-get when ssh is not there.
#>
[CmdletBinding()]
param(
    [string]$VpsHost = '',
    [string]$VpsUser = '',
    [string]$KeyPath = '',
    [switch]$Test
)

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Vps.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

$target = "$VpsUser@$VpsHost"
$sshDir = Join-Path $HOME '.ssh'
if (-not $KeyPath) { $KeyPath = Join-Path $sshDir 'thornswood_cloud_ed25519' }
$cfg = Join-Path $sshDir 'config'
$connect = Join-Path (Join-Path $Here 'bridge') 'connect.js'
$begin = '# >>> thornswood cloud (Setup-CloudSsh.ps1)'

if ($IsWindows) { Die 'this is for a cloud thread. On a Windows machine, Setup-SshKey.ps1 sets ssh up.' }
if (-not (Test-Path -LiteralPath $connect)) { Die "not found: $connect" }

function Works {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = @(Invoke-ThornswoodNative { & ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=20 $target 'echo THORNSWOOD_OK' } 2>&1 | ForEach-Object { "$_" })
    $ErrorActionPreference = $old
    return [pscustomobject]@{ Ok = (($out -join '') -match 'THORNSWOOD_OK'); Out = $out }
}

Write-Host ''
Write-Host '  THORNSWOOD  -  ssh to the box from the cloud' -ForegroundColor White
Say "  $target through $(if ($env:THORNSWOOD_BOX_URL) { $env:THORNSWOOD_BOX_URL } else { 'wss://thornswood.net/box/' })" 'DarkGray'

# ------------------------------------------------------------- settings ----
Head 'What the environment holds'
$keyB64 = [string]$env:THORNSWOOD_BOX_KEY_B64
if (-not $keyB64) {
    Die ('THORNSWOOD_BOX_KEY_B64 is not set in this environment, so there is no key to log in with. ' +
         'It goes in the cloud environment''s variables; Grant-BoxAccess.ps1 -Name cloud -MakeKey on One makes it. A new session picks it up.')
}
$keyText = ''
try { $keyText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($keyB64 -replace '\s', ''))) }
catch { Die 'THORNSWOOD_BOX_KEY_B64 is not base64. Make it again with Grant-BoxAccess.ps1 -Name cloud -MakeKey on One.' }
# Whether it is a key at all is ssh-keygen's to say, below, once it is written.
if (-not $keyText.Trim()) {
    Die 'THORNSWOOD_BOX_KEY_B64 decodes to nothing. Make it again with Grant-BoxAccess.ps1 -Name cloud -MakeKey on One.'
}
Say '  THORNSWOOD_BOX_KEY_B64 is set' 'Green'
if ($env:THORNSWOOD_BOX_TOKEN) { Say '  THORNSWOOD_BOX_TOKEN is set' 'Green' }
else { Say '  THORNSWOOD_BOX_TOKEN is not set, so the bridge token has to come from a network secret for thornswood.net' 'Yellow' }

# ------------------------------------------------------------------ ssh ----
if (-not (Get-Command ssh -ErrorAction SilentlyContinue) -or -not (Get-Command ssh-keygen -ErrorAction SilentlyContinue) -or -not (Get-Command ssh-keyscan -ErrorAction SilentlyContinue)) {
    if ($Test) { Die 'ssh is not installed in this container. Run this without -Test to install it.' }
    Head 'Installing ssh'
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = @(& apt-get install -y openssh-client 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { $out = @(& apt-get update 2>&1) + @(& apt-get install -y openssh-client 2>&1 | ForEach-Object { "$_" }) }
    $ErrorActionPreference = $old
    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) { Die ('apt-get could not install openssh-client: ' + (($out | Select-Object -Last 3) -join ' ')) }
    Say '  installed openssh-client' 'Green'
}
$node = (Get-Command node -ErrorAction SilentlyContinue)
if (-not $node) { Die 'node is not on PATH, and the bridge client is node.' }

if ($Test) {
    Head 'Checking'
    $hk = Test-ThornswoodKnownHost -Address $VpsHost
    Say ("  known_hosts: " + $hk.Status) $(if ($hk.Status -eq 'trusted') { 'Green' } else { 'Yellow' })
    $haveCfg = (Test-Path -LiteralPath $cfg) -and ([IO.File]::ReadAllText($cfg).Contains($begin))
    Say ("  ssh config block: " + $(if ($haveCfg) { 'there' } else { 'not there' })) $(if ($haveCfg) { 'Green' } else { 'Yellow' })
    $w = Works
    if ($w.Ok) { Say '  ssh to the box works' 'Green'; exit 0 }
    Say '  ssh to the box does not work yet:' 'Yellow'
    $w.Out | Select-Object -Last 5 | ForEach-Object { Say "    $_" 'DarkGray' }
    exit 1
}

# ------------------------------------------------------------------ key ----
Head 'The key'
if (-not (Test-Path -LiteralPath $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
& chmod 700 $sshDir
# Written with nobody else able to read it from the first byte: an empty file
# made 600, then filled.
[IO.File]::WriteAllText($KeyPath, '')
& chmod 600 $KeyPath
[IO.File]::WriteAllText($KeyPath, ($keyText.Replace("`r`n", "`n").TrimEnd() + "`n"), (New-Object Text.UTF8Encoding($false)))
$keyText = $null
$old = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$pub = @(Invoke-ThornswoodNative { & ssh-keygen -y -P '' -f $KeyPath } 2>$null)
$ErrorActionPreference = $old
if ($LASTEXITCODE -ne 0 -or -not ($pub -join '').StartsWith('ssh-')) {
    Remove-Item -LiteralPath $KeyPath -Force -ErrorAction SilentlyContinue
    Die 'the key in THORNSWOOD_BOX_KEY_B64 does not open without a passphrase, or is not whole. Make it again with Grant-BoxAccess.ps1 -Name cloud -MakeKey on One.'
}
Say "  $KeyPath" 'Green'

# ------------------------------------------------------------- config ------
Head 'Pointing ssh at the bridge'
# ssh runs the ProxyCommand through the shell with this environment, so the
# proxy, its authority bundle and the token reach connect.js as they are.
try {
    $client = Install-ThornswoodBridgeClient (Join-Path $Here 'bridge')
    $null = Set-ThornswoodBridgeSsh -Address $VpsHost -User $VpsUser -KeyPath $KeyPath -Node $node.Source -Connect (Join-Path $client 'connect.js') -Begin $begin -End '# <<< thornswood cloud'
} catch { Die $_.Exception.Message }
Say "  $cfg" 'Green'

# ----------------------------------------------------------- host key ------
Head "The box's own key"
try { $n = Add-ThornswoodKnownHostThroughBridge -Address $VpsHost -Node $node.Source -Listen (Join-Path $client 'listen.js') }
catch { Die $_.Exception.Message }
if ($n) { Say "  added $n pinned key line(s) to known_hosts" 'Green' }
else { Say '  known_hosts holds the pinned key' 'Green' }

# ---------------------------------------------------------------- proof ----
Head 'Logging in'
$w = Works
if (-not $w.Ok) {
    $w.Out | Select-Object -Last 5 | ForEach-Object { Say "  $_" 'DarkGray' }
    Die 'ssh to the box did not get in. The lines above say why: a "box bridge:" line is the bridge or the token, "Permission denied" is the key.'
}
Say "  ssh $target works. Remote.ps1 and the rest now reach the box from here." 'Green'
exit 0
