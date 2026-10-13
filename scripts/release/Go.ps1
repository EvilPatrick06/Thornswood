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

  4. Voice runs in the launcher now, in a hidden WebView2 window
     (launcher\app\Voice.cs and launcher\voice-host.html, which
     launcher\app\ARCHITECTURE.md walks through). It first ran inside the
     game, because the game's browser, served from http on a remote address,
     never exposed a microphone, and it moved out for the same reason.
#>

[CmdletBinding()]
param(
  # C:\Thornswood\Game on most machines; Find-Root below retargets when the
  # launcher is on another drive. -Game and -Vortex still win.
  [string] $Game   = 'C:\Thornswood\Game',
  [string] $Vps    = '',
  [string] $User   = '',
  [switch] $SkipServer,
  # Install into the Skyrim that Steam owns and Vortex deploys the collection
  # into, rather than into the launcher's own copy. Found the same way the
  # launcher finds it, so there is no path to type and no path to get wrong.
  [switch] $Vortex
)

# Same rule as Find-Root in Publish-Update.ps1 / Repair-Manifest.ps1. -Game and
# -Vortex still win; this only fills the default when neither was passed, so a
# machine whose launcher lives on another drive is not stuck on C:\Thornswood.
function Find-Root {
    $first = 'C:\Thornswood'
    if (Test-Path -LiteralPath (Join-Path $first 'Launcher\Thornswood.exe')) { return $first }
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
        $cand = Join-Path $d.Root 'Thornswood'
        if (Test-Path -LiteralPath (Join-Path $cand 'Launcher\Thornswood.exe')) { return $cand }
    }
    return $first
}
if (-not $Vortex -and -not $PSBoundParameters.ContainsKey('Game')) {
  $Game = Join-Path (Find-Root) 'Game'
}
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
. (Join-Path $Here '..\vps\Vps.ps1')
if (-not $User) { $User = Get-ThornswoodVpsUser }
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
$ui      = Join-Path $Game 'Data\Platform\UI'
$plugins = Join-Path $Game 'Data\Platform\Plugins'

function Head($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }
function Note($t) { Write-Host "  $t" }
function Bad($t)  { Write-Host "  $t" -ForegroundColor Yellow }
# A file this repository tracks that is not where this script looks for it.
# That is a path gone wrong, not a missing extra, so it fails the run: Go.ps1
# exits 1 and Ship stops (issue #440, phase 0). Before, it was a yellow line
# and a release without the file.
$script:gone = New-Object System.Collections.Generic.List[string]
function Gone($t) { Write-Host "  $t" -ForegroundColor Red; $script:gone.Add($t) }

<#
  THE LAUNCHER'S KEPT COPIES FOLLOW WHAT THIS PUTS IN.

  The launcher keeps a copy of every file of ours under Data\Platform, in
  Profile\Keep beside the game folder, and puts it back at every Play over
  whatever else is there (Keep.cs), which is how a tester's install survives
  another server's launcher writing over ours. A pack refreshes that copy when
  it writes the file (Updater.cs, Keep.Remember). What this script installs
  never comes in a pack on the machine that runs it, so without the same step
  the next Play put the previous copy back over what was just installed.

  Until 25 September Profile\developer.flag did that job on the machine that
  ships, by letting any game file newer than its kept copy win. It also meant
  that machine never saw the repair a tester's launcher makes, which is why it
  went (Patrick: "it will make testing easier"). So every file this run puts
  under Data\Platform becomes the kept copy, and every file it takes out loses
  its kept copy, the way a pack does. Nothing else in the game folder is
  adopted: a file another launcher wrote is still put back at Play.
#>
$script:installed = New-Object System.Collections.Generic.List[string]
$script:removed   = New-Object System.Collections.Generic.List[string]

# Keep.cs UnderPlatform: any file under Data\Platform\UI, and a script under
# Data\Platform\Plugins. Nothing else has a kept copy.
function Test-KeptPath([string]$rel) {
  if (-not $rel -or $rel.Contains('..')) { return $false }
  $ui = 'Data\Platform\UI\'
  if ($rel.StartsWith($ui, [StringComparison]::OrdinalIgnoreCase)) { return $rel.Length -gt $ui.Length }
  if ($rel.StartsWith('Data\Platform\Plugins\', [StringComparison]::OrdinalIgnoreCase)) {
    return $rel.EndsWith('.js', [StringComparison]::OrdinalIgnoreCase)
  }
  return $false
}

# Copies each installed file under Data\Platform into Profile\Keep and drops
# the kept copy of each removed one. Returns how many were copied, or -1 when
# there is no Profile beside the game folder, which is the Steam copy (-Vortex)
# or a folder no launcher looks after.
function Update-KeptCopies([string]$GameDir, [string[]]$Installed, [string[]]$Removed) {
  $g = ($GameDir -replace '/', '\').TrimEnd('\')
  $prof = Join-Path (Split-Path -Parent $g) 'Profile'
  if (-not (Test-Path -LiteralPath $prof)) { return -1 }
  $keepDir = Join-Path $prof 'Keep'
  $g = $g + '\'
  $n = 0
  foreach ($p in @($Installed)) {
    if (-not $p) { continue }
    $q = $p -replace '/', '\'
    if (-not $q.StartsWith($g, [StringComparison]::OrdinalIgnoreCase)) { continue }
    $rel = $q.Substring($g.Length)
    if (-not (Test-KeptPath $rel)) { continue }
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    $dst = Join-Path $keepDir $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item -LiteralPath $p -Destination $dst -Force
    $n++
  }
  foreach ($p in @($Removed)) {
    if (-not $p) { continue }
    $q = $p -replace '/', '\'
    if (-not $q.StartsWith($g, [StringComparison]::OrdinalIgnoreCase)) { continue }
    $rel = $q.Substring($g.Length)
    if (-not (Test-KeptPath $rel)) { continue }
    $kept = Join-Path $keepDir $rel
    if (Test-Path -LiteralPath $kept -PathType Leaf) { Remove-Item -LiteralPath $kept -Force }
  }
  return $n
}

# ------------------------------------------------------------------- front --
Head 'Front'
# The front build, made outside the repository and kept in local\, which git
# ignores (in tools\ until 29 September, issue #440 phase 10).
$zip = Join-Path $Here '..\..\local\thornswood-front.zip'
if (-not (Test-Path -LiteralPath $zip)) {
  Bad 'thornswood-front.zip is not in local\ in the repository folder'
} else {
  New-Item -ItemType Directory -Force -Path $ui | Out-Null
  Expand-Archive -LiteralPath $zip -DestinationPath $ui -Force
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try { foreach ($e in $z.Entries) { if ($e.Name) { $script:installed.Add((Join-Path $ui ($e.FullName -replace '/', '\'))) } } }
    finally { $z.Dispose() }
  } catch { Bad ('could not read what the front zip holds, so its kept copies were not refreshed: ' + $_.Exception.Message) }
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
  $script:removed.Add($oldWheel)
  Note 'removed the old wheel page'
}

# ---------------------------------------------------------------- overlays --
Head 'Overlays'
$uiSrc = Join-Path $Here '..\..\game\ui'
if (Test-Path -LiteralPath $uiSrc) {
  foreach ($f in Get-ChildItem -LiteralPath $uiSrc -Filter *.js) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $ui $f.Name) -Force
    $script:installed.Add((Join-Path $ui $f.Name))
    Note $f.Name
  }
  # The page itself. The front's zip above carries the plain one; ours is
  # the same page plus the two lines that draw the character choice before
  # any plugin runs, and it has to land after the zip or the zip's copy wins.
  # Until 20 September it never landed at all: the overlays loop took *.js
  # and the page sat in the repo with nothing carrying it.
  $page = Join-Path $uiSrc 'index.html'
  if (Test-Path -LiteralPath $page) {
    Copy-Item -LiteralPath $page -Destination (Join-Path $ui 'index.html') -Force
    $script:installed.Add((Join-Path $ui 'index.html'))
    Note 'index.html (ours, over the front''s)'
  } else {
    Gone 'game\ui\index.html is missing, so the menu choice cannot draw before the plugin runs'
  }
  # The dev test track lives beside the overlays. It goes into the game
  # folder like them; whether it leaves the machine is Ship-Rules' call, and
  # a main pack never carries it.
  foreach ($f in Get-ChildItem -LiteralPath $uiSrc -Filter *.mp3) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $ui $f.Name) -Force
    $script:installed.Add((Join-Path $ui $f.Name))
    Note $f.Name
  }
  # The two pictures of the scroll in front of the character choice.
  foreach ($f in Get-ChildItem -LiteralPath $uiSrc -Filter *.webp) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $ui $f.Name) -Force
    $script:installed.Add((Join-Path $ui $f.Name))
    Note $f.Name
  }
  # The painting behind the main menu's character choice: the site's own
  # banner, the loop and its first frame, copied under the page's names so
  # the one file in the repo is the site's. Ours, flat under UI, so it ships.
  $siteArt = Join-Path $Here '..\..\site\public'
  foreach ($pair in @(@('banner.webm', 'thornswood-menu.webm'), @('banner.mp4', 'thornswood-menu.mp4'), @('banner.jpg', 'thornswood-menu.jpg'))) {
    $src = Join-Path $siteArt $pair[0]
    if (Test-Path -LiteralPath $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $ui $pair[1]) -Force
      $script:installed.Add((Join-Path $ui $pair[1]))
      Note ($pair[1] + ' (from the site''s ' + $pair[0] + ')')
    } else {
      Gone ('the site''s ' + $pair[0] + ' is not in site\public, so the menu has no painting')
    }
  }
} else {
  Gone 'game\ui is not beside tools'
}

# ------------------------------------------------------ the menu backdrop --
# The two logo meshes and the wallpaper texture behind Skyrim's main menu,
# from game\menu (entry 83: the second mesh used to be a copy of the
# first, so the menu drew the backdrop twice, and the texture had one mip
# level of the old art). The destination is removed before the copy: in an
# own game folder these can be hard links into the Steam copy, and writing
# through a link would change the Steam copy too.
Head 'Menu backdrop'
$menuSrc = Join-Path $Here '..\..\game\menu'
$menuPairs = @(
  @('logo.nif',               'Data\meshes\interface\logo\logo.nif'),
  @('logo01ae.nif',           'Data\meshes\interface\logo\logo01ae.nif'),
  @('Mainmenuwallpaper.dds',  'Data\textures\interface\objects\Mainmenuwallpaper.dds')
)
foreach ($pair in $menuPairs) {
  $src = Join-Path $menuSrc $pair[0]
  $dst = Join-Path $Game $pair[1]
  if (-not (Test-Path -LiteralPath $src)) { Gone ($pair[0] + ' is not in game\menu'); continue }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
  if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
  Copy-Item -LiteralPath $src -Destination $dst -Force
  Note $pair[1]
}

# ------------------------------------------------ our own menu files --
# The main menu with no Bethesda logo, the empty loading spinner, the
# silent stand-in for the game's theme, SkyHUD's settings as Thornswood
# set them, and the notice board's and drop box's meshes. From
# game\ours, beside game\menu. Each path is
# the path in the game folder, so the destination is the name itself
# (Ship-Rules $ShipOursFiles; change the two together). The destination
# is removed before the copy: in an own game folder these can be hard
# links into the Steam copy, and writing through a link would change
# the Steam copy too.
Head 'Our menu files'
$oursSrc = Join-Path $Here '..\..\game\ours'
$oursMenuFiles = @(
  'Data\Interface\startmenu.swf',
  'Data\Interface\loadwaitspinner.swf',
  'Data\music\special\mus_maintheme.xwm',
  'Data\Interface\skyhud\skyhud.txt',
  # The notice board and the drop box of the hold beside it, the meshes
  # Thornswood builds from vanilla pieces with scripts\mods\Build-NoticeBoard.py,
  # issue 2298. The board and drop box of Thornswood-Content.esp name them.
  # No brackets and no apostrophes in these comments: test-ship-rules.ps1
  # reads this list up to the first closing bracket, quote by quote.
  'Data\meshes\thornswood\noticeboard01.nif',
  'Data\meshes\thornswood\dropbox01.nif'
)
foreach ($rel in $oursMenuFiles) {
  $src = Join-Path $oursSrc $rel
  $dst = Join-Path $Game $rel
  if (-not (Test-Path -LiteralPath $src)) { Gone ($rel + ' is not in game\ours'); continue }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
  if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
  Copy-Item -LiteralPath $src -Destination $dst -Force
  Note $rel
}

# ---------------------------------------------------------- required data --
# Plugins the load order names that Vortex does not yet deploy under that
# exact filename. Ship packs and the installer also place these (Ship-Rules
# Ensure-ShipRequiredData). Take a file out of game\required-data when the
# collection deploys the same Data\ path.
Head 'Required data'
$reqSrc = Join-Path $Here '..\..\game\required-data'
if (Test-Path -LiteralPath $reqSrc) {
  foreach ($f in @(Get-ChildItem -LiteralPath $reqSrc -File -EA SilentlyContinue)) {
    if ($f.Name -eq 'README.md') { continue }
    $dst = Join-Path $Game ('Data\' + $f.Name)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
    Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
    Note ('Data\' + $f.Name)
  }
} else {
  Gone 'game\required-data is not in the repo'
}

# ----------------------------------------------------------------- plugins --
Head 'Plugins'
$plSrc = Join-Path $Here '..\..\game\plugins'
New-Item -ItemType Directory -Force -Path $plugins | Out-Null
if (Test-Path -LiteralPath $plSrc) {
  foreach ($f in Get-ChildItem -LiteralPath $plSrc -Filter *.js) {
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $plugins $f.Name) -Force
    $script:installed.Add((Join-Path $plugins $f.Name))
    Note $f.Name
  }
} else {
  Gone 'game\plugins is not beside tools'
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
  # The bundle is the one client file under Data\Platform\Plugins, so it is
  # the one with a kept copy. Only the recorded build becomes it.
  else { $script:installed.Add((Join-Path $plugins 'skymp5-client.js')) }
} else {
  Gone 'Sync-Client.ps1 is not next to this script'
}

# The probe's job is done: the voice client reports the same facts, in its own
# log, and unlike the probe it does not fight the front for the browser.
$probe = Join-Path $plugins 'thornswood-probe.js'
if (Test-Path -LiteralPath $probe) {
  Remove-Item -LiteralPath $probe -Force
  $script:removed.Add($probe)
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
  # Guarded: test-chargen-gone.ps1 lifts this loop and runs it on its own.
  if ($null -ne $script:removed) { $script:removed.Add($s.FullName) }
}

Head 'The launcher''s kept copies'
$kept = Update-KeptCopies $Game $script:installed.ToArray() $script:removed.ToArray()
if ($kept -lt 0) { Note 'no Profile folder beside this game folder, so no launcher keeps copies here' }
else { Note "$kept file(s) the launcher keeps a copy of now match what was just installed, so Play will not put an older copy back" }

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
# Derived from the game folder's install root, not a fixed C:\Thornswood, so
# the MCMHelper enable lands in the same Profile the launcher on this machine
# reads when the install is on another drive.
$installRoot = Split-Path -Parent $Game
$orderFiles = @(
  (Join-Path $installRoot 'Profile\LocalAppData\Plugins.txt'),
  (Join-Path $installRoot 'Profile\Default\plugins.txt')
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

  # Voice is asked through Caddy on the public name, never on the raw port.
  #
  # This used to open a TCP socket to 7778 on the VPS address and call it dead
  # when nothing answered. Nothing ever answers: the voice service binds
  # 127.0.0.1 and Caddy carries /voice/ to it, exactly as the docs site binds
  # 3001 behind the certificate. So this printed "voice service: NOTHING on
  # 7778" in red on every single run while voice was up and working, and on
  # 22 September that red line was read as an outage and chased.
  #
  # It is the same mistake as asking whether a process is running and calling
  # that the site being up, pointing the other way: a port being shut from
  # outside says nothing about a service that was never meant to be reachable
  # there. The health endpoint through the public name is the only question
  # that has the same answer a customer would get.
  #
  # The game server IS asked on its raw port above, and that is right: 3000
  # binds every interface because the game client connects to it directly.
  function VoiceUp($url) {
    try {
      $r = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 8
      if ($r.StatusCode -ne 200) { return $null }
      return $r.Content
    } catch { return $null }
  }
  $voiceUrl = 'https://thornswood.net/voice/health'
  $vh = VoiceUp $voiceUrl
  if ($vh) {
    $peers = ''
    try { $peers = '  ' + ([string](($vh | ConvertFrom-Json).peers)) + ' peer(s)' } catch { }
    Note ('voice service: answering at /voice/' + $peers)
  } else {
    Bad "voice service: NOTHING at $voiceUrl"
    Bad '  that is Caddy or the service itself; the raw port is shut on purpose and proves nothing'
  }

  <#
    The voice service carries text chat now as well as audio, so it has to be
    the current copy. Two things were wrong with how this did that.

    It read voice-server.js from the tools folder. The real one moved into
    voice months ago and the copy left behind at the top went stale, so
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
  $vsrc = Join-Path $Here '..\..\voice\voice-server.js'
  if (Test-Path -LiteralPath $vsrc) {
    Invoke-ThornswoodNative { & scp -o BatchMode=yes -o StrictHostKeyChecking=yes $vsrc "$User@${Vps}:C:/Thornswood-Voice/voice-server.js" } 2>&1 | Out-Null
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
      $r = Invoke-ThornswoodNative { & ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" } 2>&1
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
  $out = Invoke-ThornswoodNative { & ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$User@$Vps" "powershell -NoProfile -EncodedCommand $enc" } 2>&1
  $out | ForEach-Object { Note $_ }
}

Head 'Next'
Note 'Start the game from the launcher, play for a minute, quit, then paste:'
Note ("  Get-Content $(Join-Path $Game 'Data\Platform\thornswood-voice.log')")
Note ("  Get-Content $(Join-Path $Game 'Data\Platform\thornswood-front.log')")

if ($script:gone.Count) {
  Write-Host ''
  Write-Host ('  ' + $script:gone.Count + ' file(s) this repository has did not reach the game folder; see the red lines above.') -ForegroundColor Red
  exit 1
}
exit 0
