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
  carries port 22, and port 22 on the box answers One's address only
  (Set-SshScope.ps1). So ssh goes inside a WebSocket on 443 instead:
  connect.js, as ssh's ProxyCommand, opens wss://thornswood.net/box/, Caddy
  hands it to bridge.js on the box, and bridge.js joins it to the box's own
  sshd on 127.0.0.1. Decided by Patrick on 19 Oct 2026 (#2750, C): cloud
  threads get an ssh key to the box.

  WHAT IT READS, from the cloud environment's settings (New-CloudAccess.ps1
  on One makes both and says where they go):
    THORNSWOOD_BOX_KEY_B64  the cloud key's private half, base64. The box
                            takes it only from 127.0.0.1, so only through the
                            bridge (the from= on its line).
    THORNSWOOD_BOX_TOKEN    the bridge's token. Left out when the environment
                            holds it as a network secret for thornswood.net,
                            which the proxy adds to the request itself.
  Neither is printed, by this or by connect.js.

  WHAT IT WRITES, in this container only:
    ~/.ssh/thornswood_cloud_ed25519   the key, readable by this user only
    ~/.ssh/config                     a Host block for the box's address with
                                      the key, the ProxyCommand and
                                      StrictHostKeyChecking yes, between two
                                      marker lines so a second run replaces it
    ~/.ssh/known_hosts                the box's host key, and only one that
                                      scripts/vps/vps.json pins
                                      (Add-ThornswoodKnownHost)

  THE BOX'S OWN KEY. ssh-keyscan cannot run a ProxyCommand, so it asks
  through bridge/listen.js, a port on this container's loopback that carries
  each connection to the box the same way, and what it is shown goes through
  the same pin as Setup-SshKey.ps1's (Add-ThornswoodKnownHost -Scanned).
  Nothing that is not pinned reaches known_hosts, and ssh itself never adds
  a key: it runs with StrictHostKeyChecking yes from the first connection.

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
$end = '# <<< thornswood cloud'

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
         'It goes in the cloud environment''s variables; New-CloudAccess.ps1 on One makes it. A new session picks it up.')
}
$keyText = ''
try { $keyText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($keyB64 -replace '\s', ''))) } catch { }
if ($keyText -notmatch '-----BEGIN OPENSSH PRIVATE KEY-----') {
    Die 'THORNSWOOD_BOX_KEY_B64 does not decode to an OpenSSH private key. Make it again with New-CloudAccess.ps1 on One.'
}
Say '  THORNSWOOD_BOX_KEY_B64 is set and is an OpenSSH key' 'Green'
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
    Die 'the key in THORNSWOOD_BOX_KEY_B64 does not open without a passphrase, or is not whole. Make it again with New-CloudAccess.ps1 on One.'
}
Say "  $KeyPath" 'Green'

# ------------------------------------------------------------- config ------
Head 'Pointing ssh at the bridge'
# ssh runs the ProxyCommand through the shell with this environment, so the
# proxy, its authority bundle and the token reach connect.js as they are.
$block = @(
    $begin,
    "Host $VpsHost",
    "    User $VpsUser",
    "    IdentityFile $KeyPath",
    '    IdentitiesOnly yes',
    '    StrictHostKeyChecking yes',
    "    ProxyCommand `"$($node.Source)`" `"$connect`"",
    $end
) -join "`n"
$text = ''
if (Test-Path -LiteralPath $cfg) { $text = [IO.File]::ReadAllText($cfg) }
$text = [regex]::Replace($text, '(?s)' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end) + '\n?', '')
if ($text -match ('(?m)^[ \t]*Host[ \t]+([^\r\n]*[ \t])?' + [regex]::Escape($VpsHost) + '([ \t]|\r?$)')) {
    Die "$cfg already has a Host entry for $VpsHost that this did not write, and ssh would use that one first. Take it out, then run this again."
}
# First in the file, since ssh takes the first value it finds for each option.
$text = $block + "`n" + $(if ($text.Trim()) { "`n" + $text.TrimStart() } else { '' })
[IO.File]::WriteAllText($cfg, $text, (New-Object Text.UTF8Encoding($false)))
& chmod 600 $cfg
Say "  $cfg" 'Green'

# ----------------------------------------------------------- host key ------
Head "The box's own key"
$hk = Test-ThornswoodKnownHost -Address $VpsHost
if ($hk.Status -eq 'wrong') {
    Die ("known_hosts here holds a key for $VpsHost that scripts/vps/vps.json does not pin (" + ($hk.Wrong -join ', ') + "). ssh-keygen -R $VpsHost, then run this again.")
}
if ($hk.Status -eq 'trusted') {
    Say ('  known_hosts holds the pinned key (' + ($hk.Pinned -join ', ') + ')') 'Green'
} else {
    # listen.js prints the port it took, then carries each connection to
    # the box until its standard input closes.
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.ArgumentList.Add((Join-Path (Join-Path $Here 'bridge') 'listen.js'))
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $listener = [Diagnostics.Process]::Start($psi)
    try {
        $port = [string]$listener.StandardOutput.ReadLine()
        if ($port -notmatch '^\d+$') { Die 'the bridge listener did not start, so the box''s key could not be asked for. Nothing was written.' }
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $scan = @(Invoke-ThornswoodNative { & ssh-keyscan -T 20 -p $port 127.0.0.1 } 2>&1 | ForEach-Object { "$_" })
        $ErrorActionPreference = $old
        # Each line names [127.0.0.1]:port, the listener; the key is the box's,
        # so it is written under the box's address, after the pin has seen it.
        $lines = @($scan | Where-Object { $_ -match '^\[127\.0\.0\.1\]:\d+ ' } | ForEach-Object { $VpsHost + ' ' + ($_ -replace '^\S+\s+', '') })
        if (-not $lines.Count) {
            Die ('the box showed no host key through the bridge, so nothing was written. ssh-keyscan said: ' + (($scan | Select-Object -Last 3) -join ' '))
        }
        try { $n = Add-ThornswoodKnownHost -Address $VpsHost -Scanned $lines }
        catch { Die $_.Exception.Message }
        Say "  added $n pinned key line(s) to known_hosts" 'Green'
    }
    finally {
        try { $listener.StandardInput.Close() } catch { }
        if (-not $listener.WaitForExit(3000)) { try { $listener.Kill() } catch { } }
    }
}

# ---------------------------------------------------------------- proof ----
Head 'Logging in'
$w = Works
if (-not $w.Ok) {
    $w.Out | Select-Object -Last 5 | ForEach-Object { Say "  $_" 'DarkGray' }
    Die 'ssh to the box did not get in. The lines above say why: a "box bridge:" line is the bridge or the token, "Permission denied" is the key.'
}
Say "  ssh $target works. Remote.ps1 and the rest now reach the box from here." 'Green'
exit 0
