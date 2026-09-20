<#
  Go.ps1 - installs the front, the overlays and the plugins, then reports what
  the server is doing.

  What changed and why, so none of this looks arbitrary later:

  1. There is one browser and three things wanted it. The emote wheel called
     loadUrl on a page of its own, which replaced the chat and the names above
     heads. Last caller wins, and the wheel always called last. So one plugin,
     thornswood-front.js, loads one page, and the wheel and voice mount into it
     as overlays. Nothing else calls loadUrl.

  2. SkyrimPlatform's default page address is the bare string
     file:///Data/Platform/UI/index.html, which CEF reads from the filesystem
     root: C:\Data\Platform\UI, which exists on nobody's machine. The front has
     therefore never once loaded. It is loaded by absolute path now.

  3. Plugins share one global scope. A top level `function log()` becomes a
     property of that shared object, so the last plugin loaded silently replaced
     every other plugin's log: chargen's lines were being written into the
     probe's file under the probe's prefix. Every plugin is wrapped now.

  4. Voice runs inside the game. It cannot run in a window beside it: served
     from http on a remote address, Chromium does not expose a microphone at
     all, whatever flags it is given. That is an origin rule, not a permission.
#>

[CmdletBinding()]
param(
  [string] $Game   = 'C:\Thornswood\Game',
  [string] $Vps    = '192.135.112.23',
  [string] $User   = 'Administrator',
  [switch] $SkipServer,
  # Install into the Skyrim that Steam owns and Vortex deploys the collection
  # into, rather than into the launcher's own copy. Found the same way the
  # launcher finds it, so there is no path to type and no path to get wrong.
  [switch] $Vortex
)

if ($Vortex) {
  $roots = @()
  foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\Wow6432Node\Valve\Steam')) {
    try { $sp = (Get-ItemProperty -Path $k -EA Stop).SteamPath; if ($sp) { $roots += ($sp -replace '/', '\') } } catch { }
  }
  foreach ($r in @($roots)) {
    $vdf = Join-Path $r 'config\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
      foreach ($line in Get-Content -LiteralPath $vdf) {
        if ($line -match '^\s*"path"\s+"(.+)"\s*$') { $roots += ($Matches[1] -replace '\\\\', '\') }
      }
    }
  }
  $found = ''
  foreach ($r in $roots) {
    $g = Join-Path $r 'steamapps\common\Skyrim Special Edition'
    if (Test-Path -LiteralPath (Join-Path $g 'SkyrimSE.exe')) { $found = $g; break }
  }
  if (-not $found) { throw 'Could not find the Steam copy of Skyrim. Pass -Game with its folder instead.' }
  $Game = $found
  Write-Host ''
  Write-Host "  installing into the Steam copy: $Game" -ForegroundColor Cyan
}

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$ui      = Join-Path $Game 'Data\Platform\UI'
$plugins = Join-Path $Game 'Data\Platform\Plugins'

function Head($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }
function Note($t) { Write-Host "  $t" }
function Bad($t)  { Write-Host "  $t" -ForegroundColor Yellow }

# ------------------------------------------------------------------- front --
Head 'Front'
$zip = Join-Path $Here 'thornswood-front.zip'
if (-not (Test-Path -LiteralPath $zip)) {
  Bad 'thornswood-front.zip is not next to this script'
} else {
  New-Item -ItemType Directory -Force -Path $ui | Out-Null
  Expand-Archive -LiteralPath $zip -DestinationPath $ui -Force
  if (Test-Path -LiteralPath (Join-Path $ui 'index.html')) {
    Note 'index.html and build.js are in place'
  } else {
    Bad 'index.html did not land'
  }
}

# The wheel is an overlay script now, not a page. Leaving the old page behind
# only invites something to load it again.
$oldWheel = Join-Path $ui 'thornswood-emotes.html'
if (Test-Path -LiteralPath $oldWheel) {
  Remove-Item -LiteralPath $oldWheel -Force
  Note 'removed the old wheel page'
}

# ---------------------------------------------------------------- overlays --
Head 'Overlays'
$uiSrc = Join-Path $Here 'ts-ui'
if (Test-Path -LiteralPath $uiSrc) {
  foreach ($f in Get-ChildItem -LiteralPath $uiSrc -Filter *.js) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $ui $f.Name) -Force
    Note $f.Name
  }
  # The dev test track lives beside the overlays. It goes into the game
  # folder like them; whether it leaves the machine is Ship-Rules' call, and
  # a main pack never carries it.
  foreach ($f in Get-ChildItem -LiteralPath $uiSrc -Filter *.mp3) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $ui $f.Name) -Force
    Note $f.Name
  }
  # The painting behind the main menu's character choice: the site's own
  # banner, the loop and its first frame, copied under the page's names so
  # the one file in the repo is the site's. Ours, flat under UI, so it ships.
  $siteArt = Join-Path $Here 'docs-app\public'
  foreach ($pair in @(@('banner.mp4', 'thornswood-menu.mp4'), @('banner.jpg', 'thornswood-menu.jpg'))) {
    $src = Join-Path $siteArt $pair[0]
    if (Test-Path -LiteralPath $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $ui $pair[1]) -Force
      Note ($pair[1] + ' (from the site''s ' + $pair[0] + ')')
    } else {
      Bad ('the site''s ' + $pair[0] + ' is not in docs-app\public, so the menu has no painting')
    }
  }
} else {
  Bad 'the ts-ui folder is not next to this script'
}

# ------------------------------------------------------ the menu backdrop --
# The two logo meshes and the wallpaper texture behind Skyrim's main menu,
# from tools\art\menu (entry 83: the second mesh used to be a copy of the
# first, so the menu drew the backdrop twice, and the texture had one mip
# level of the old art). The destination is removed before the copy: in an
# own game folder these can be hard links into the Steam copy, and writing
# through a link would change the Steam copy too.
Head 'Menu backdrop'
$menuSrc = Join-Path $Here 'art\menu'
$menuPairs = @(
  @('logo.nif',               'Data\meshes\interface\logo\logo.nif'),
  @('logo01ae.nif',           'Data\meshes\interface\logo\logo01ae.nif'),
  @('Mainmenuwallpaper.dds',  'Data\textures\interface\objects\Mainmenuwallpaper.dds')
)
foreach ($pair in $menuPairs) {
  $src = Join-Path $menuSrc $pair[0]
  $dst = Join-Path $Game $pair[1]
  if (-not (Test-Path -LiteralPath $src)) { Bad ($pair[0] + ' is not in tools\art\menu'); continue }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
  if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
  Copy-Item -LiteralPath $src -Destination $dst -Force
  Note $pair[1]
}

# ----------------------------------------------------------------- plugins --
Head 'Plugins'
$plSrc = Join-Path $Here 'ts-plugins'
New-Item -ItemType Directory -Force -Path $plugins | Out-Null
if (Test-Path -LiteralPath $plSrc) {
  foreach ($f in Get-ChildItem -LiteralPath $plSrc -Filter *.js) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $plugins $f.Name) -Force
    Note $f.Name
  }
} else {
  Bad 'the ts-plugins folder is not next to this script'
}

# ------------------------------------------------------------------ client --
# The SkyMP client runtime, built from the fork and recorded in
# client-build.json: the bundle, MpClientPlugin.dll, both SkyrimPlatform DLLs,
# the CEF host and TESModPlatform.pex. Sync-Client.ps1 copies the six from the
# fork's build output and refuses any file that is not the recorded one. This
# is the same job as the two sections above, for the part of the client that
# is compiled rather than written here. Until 20 September none of it came
# from here: the Steam copy held another server's launcher's builds and the
# folder build copied them across.
Head 'Client'
$sync = Join-Path $Here 'Sync-Client.ps1'
if (Test-Path -LiteralPath $sync) {
  & $sync -Game $Game -NoPause
  if ($LASTEXITCODE -ne 0) { Bad 'the client runtime is not the recorded build; see the lines above' }
} else {
  Bad 'Sync-Client.ps1 is not next to this script'
}

# The probe's job is done: the voice client reports the same facts, in its own
# log, and unlike the probe it does not fight the front for the browser.
$probe = Join-Path $plugins 'thornswood-probe.js'
if (Test-Path -LiteralPath $probe) {
  Remove-Item -LiteralPath $probe -Force
  Note 'removed the probe, voice reports the same things now'
}

# Anything in the plugins folder that is not a plugin makes SkyrimPlatform
# reload every plugin, repeatedly, which presents as a black screen with a dead
# keyboard rather than as an error.
#
# And anything that IS a plugin but is not ours runs on every machine that
# installs the collection. A Steam copy that had another roleplay server
# installed on it first still had that server's overlay sitting in here, which
# is how somebody ends up with two fronts fighting over the browser. So the
# list is what belongs, not what looks wrong.
# The recorded bundle and the per machine settings file. An activity plugin
# used to be kept here as well; it exists in no build of ours and in no game
# folder, so its name is gone.
$keep = @('skymp5-client.js', 'skymp5-client-settings.txt')
foreach ($f in (Get-ChildItem -LiteralPath $plSrc -File -Filter *.js -EA SilentlyContinue)) { $keep += $f.Name }

foreach ($s in (Get-ChildItem -LiteralPath $plugins -File)) {
  if ($keep -contains $s.Name) { continue }
  Bad "removing stray file from the plugins folder: $($s.Name)"
  Remove-Item -LiteralPath $s.FullName -Force
}

# -------------------------------------------------------------- load order --
Head 'Load order'

# MCMHelper.esp is a hundred byte stub whose only job is to exist so MCM Helper
# has a plugin to hang its menus off. It is sitting in the list disabled, which
# is what breaks QuickLoot's settings quest and every other MCM Helper menu in
# the build. Turning it on cannot break anything: it has no masters and no
# records worth the name.
#
# Nothing else here gets touched. The other disabled lines are patches for mods
# that are genuinely not installed (Wyrmstooth, Mysticism, a couple of SunHelm
# patches), and enabling a plugin whose masters are missing is how you get a
# crash on load rather than a fixed menu.
$orderFiles = @(
  'C:\Thornswood\Profile\LocalAppData\Plugins.txt',
  'C:\Thornswood\Profile\Default\plugins.txt'
)
foreach ($f in $orderFiles) {
  if (-not (Test-Path -LiteralPath $f)) { continue }
  $lines = [IO.File]::ReadAllLines($f)
  $hit = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq 'MCMHelper.esp') { $lines[$i] = '*MCMHelper.esp'; $hit = $true }
  }
  if ($hit) {
    [IO.File]::WriteAllLines($f, $lines, (New-Object Text.UTF8Encoding($false)))
    Note "enabled MCMHelper.esp in $(Split-Path -Leaf $f)"
  } else {
    Note "MCMHelper.esp already enabled in $(Split-Path -Leaf $f)"
  }
}

# ------------------------------------------------------------------ server --
if (-not $SkipServer) {
  Head 'Server'

  function Port($h, $p, $ms) {
    $c = New-Object Net.Sockets.TcpClient
    try {
      $iar = $c.BeginConnect($h, $p, $null, $null)
      if ($iar.AsyncWaitHandle.WaitOne($ms, $false) -and $c.Connected) { return $true }
      return $false
    } catch { return $false } finally { $c.Close() }
  }

  if (Port $Vps 3000 2500) { Note 'game server: answering on 3000' }
  else { Bad 'game server: NOTHING on 3000' }

  if (Port $Vps 7778 2500) { Note 'voice service: answering on 7778' }
  else { Bad 'voice service: NOTHING on 7778' }

  <#
    The voice service carries text chat now as well as audio, so it has to be
    the current copy. Two things were wrong with how this did that.

    It read voice-server.js from the tools folder. The real one moved into
    tools\voice months ago and the copy left behind at the top went stale, so
    running this pushed an old build over a good one.

    And the restart below had three literal vertical tab bytes in it, where a
    backslash-v had been eaten by whatever wrote the file: the path it handed
    node was C:\Thornswood-Voice<VT>oice-server.js, which cannot exist. Since
    it killed the running service first, this did not fail to restart voice.
    It stopped voice and left it stopped.

    It now restarts the scheduled task rather than launching node loose. A
    loose node and the task's own restart timer both want port 7778, and the
    loser dies quietly while the winner keeps serving whatever it was already
    running, which is the exact failure that hid days of changes.
  #>
  $vsrc = Join-Path $Here 'voice\voice-server.js'
  if (Test-Path -LiteralPath $vsrc) {
    & scp -o BatchMode=yes -o StrictHostKeyChecking=no $vsrc "$User@${Vps}:C:/Thornswood-Voice/voice-server.js" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
      $restart = @'
$ProgressPreference = 'SilentlyContinue'
Stop-ScheduledTask -TaskName 'Thornswood Voice' -EA SilentlyContinue
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -like '*voice-server*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
for ($i = 0; $i -lt 20; $i++) {
  $busy = $false
  try {
    $c = New-Object Net.Sockets.TcpClient
    $null = $c.BeginConnect('127.0.0.1', 7778, $null, $null).AsyncWaitHandle.WaitOne(300)
    $busy = $c.Connected; $c.Close()
  } catch { }
  if (-not $busy) { break }
  Start-Sleep -Milliseconds 500
}
Start-ScheduledTask -TaskName 'Thornswood Voice' -EA SilentlyContinue
Start-Sleep -Seconds 2
try { (Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:7778/health' -TimeoutSec 5).Content }
catch { 'voice did not answer its own health check' }
'@
      $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($restart))
      $r = & ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" 2>&1
      Note ("voice: " + (($r | Where-Object { $_ }) -join ' '))
    } else {
      Bad 'could not copy the voice service to the VPS over ssh'
    }
  }

  $remote = @'
$ProgressPreference = 'SilentlyContinue'
$p = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -like '*skymp5-server*' }
if ($p) { "server process up, pid " + $p.ProcessId } else { "server process is NOT running" }
if (Test-Path 'C:\Thornswood-Server\server.log') {
  "--- server.log, last 12 ---"
  Get-Content 'C:\Thornswood-Server\server.log' -Tail 12
}
'@
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))
  $out = & ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$User@$Vps" "powershell -NoProfile -EncodedCommand $enc" 2>&1
  $out | ForEach-Object { Note $_ }
}

Head 'Next'
Note 'Start the game from the launcher, play for a minute, quit, then paste:'
Note '  Get-Content C:\Thornswood\Game\Data\Platform\thornswood-voice.log'
Note '  Get-Content C:\Thornswood\Game\Data\Platform\thornswood-front.log'
