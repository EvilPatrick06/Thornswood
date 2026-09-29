<#
  Export-ServerPayload.ps1

  Packages everything the VPS needs into one zip. Run on the build machine.

  The VPS has Node but no build toolchain, so nothing is compiled there. What
  goes across is the built server plus the plugin files its load order names,
  with the absolute paths rewritten for where they will live on the VPS.

  Deliberately left out:
    scam_native.pdb        73 MB of debug symbols, useless on the VPS
    world/                 the save. The VPS starts with a fresh world; copying
                           a local one across would import a character nobody
                           on that server made.
    *.bsa                  the server reads plugin records, not archives. If a
                           Papyrus script turns out to be missing, that is the
                           thing to revisit.

  Kept despite its size: skymp5-server.js.map, 10 MB. Without it every stack
  trace from the server points at minified bundle offsets.
#>
[CmdletBinding()]
param(
    [string]$Dist    = (& (Join-Path $PSScriptRoot 'Where.ps1') ServerDist),
    [string]$OutDir  = (& (Join-Path $PSScriptRoot 'Where.ps1') Payload),
    [string]$VpsRoot = 'C:\Thornswood-Server',
    [string]$Zip     = (& (Join-Path $PSScriptRoot 'Where.ps1') ServerZip),
    # Which server the payload is for (#1114). Dev's ports and name go into the
    # staged settings only; the build's own server-settings.json is never
    # written, so what a dev publish leaves behind is the live file it found.
    [ValidateSet('main', 'dev')][string]$Channel = 'main',
    # The build record the binary is held to and that goes into the payload as
    # server-build.json, so the installer on the box holds it too (#1214).
    [string]$Record = (Join-Path $PSScriptRoot '..\..\records\server-build.json')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Dist)) { throw "server dist not found: $Dist" }
. (Join-Path $PSScriptRoot '..\deploy\ServerSettings.ps1')

# ---- settings no server should get, and the dev ones for live ----------------
# Until #1114 a dev Publish-Server rewrote the build's own settings to port
# 7787, voice 7789 and the name Thornswood Dev and never put them back, so the
# next live publish packed them and live came up on the dev port. Nothing
# writes dev settings into the build now, but a build left that way by an
# older run, or by Deploy-DevGamemode pointed at the wrong folder, still stops
# here, before anything is copied or zipped. So does an npcSettings "default"
# key on either channel, which refuses every NPC (#1222): the installer keeps
# the running server's own npcSettings, but a first install has none to keep.
$liveWhy = @(Get-ThornswoodServerSettingsProblems (Get-Content -LiteralPath (Join-Path $Dist 'server-settings.json') -Raw | ConvertFrom-Json) $Channel)
if ($liveWhy.Count) {
    $whose = if ($Channel -eq 'main') { "is not the live server's" } else { 'is not fit for any server' }
    throw ("server-settings.json in $Dist $($whose): " + ($liveWhy -join '; ') +
           '. Run .\scripts\deploy\Deploy-Gamemode.ps1, which writes the live ones, then publish again. Nothing was packed.')
}

# ---- the binary is the recorded build (#1214) -------------------------------
# Deploy-Server refused a scam_native.node that is not the one
# records\server-build.json names, and the installer on the box refused one
# that is not its payload's record, but a payload carried no record, so a
# publish sent whatever binary sat in the build. Held here, before anything is
# copied, and the record goes into the payload.
if (-not (Test-Path -LiteralPath $Record)) { throw "there is no build record at $Record, so nothing says which build this binary is. Nothing was packed." }
$recWant = ''
try { $recWant = ([string]([IO.File]::ReadAllText($Record) | ConvertFrom-Json).sha256).ToLowerInvariant() } catch { throw "$Record does not parse: $($_.Exception.Message). Nothing was packed." }
if (-not $recWant) { throw "$Record names no sha256. Nothing was packed." }
$binPath = Join-Path $Dist 'scam_native.node'
if (-not (Test-Path -LiteralPath $binPath)) { throw "not built: $binPath. Nothing was packed." }
$binHave = (Get-FileHash -LiteralPath $binPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($binHave -ne $recWant) {
    throw ("scam_native.node in $Dist is not the build $Record names (it is $binHave, the record says $recWant). " +
           'If it was rebuilt on purpose, record it with .\scripts\release\New-ServerBuildRecord.ps1 and commit that; if not, find out what changed. Nothing was packed.')
}
Write-Host ('scam_native.node is the recorded build, ' + $recWant.Substring(0, 12)) -ForegroundColor Cyan

if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutDir 'plugins') -Force | Out-Null

# ---- the server itself -----------------------------------------------------
$skip = 'scam_native.pdb'
foreach ($item in (Get-ChildItem -LiteralPath $Dist)) {
    if ($item.Name -eq 'world')      { continue }
    if ($skip -contains $item.Name)  { continue }
    Copy-Item -LiteralPath $item.FullName -Destination $OutDir -Recurse -Force
}
# The record the binary was just held to, for the installer to hold it again.
Copy-Item -LiteralPath $Record -Destination (Join-Path $OutDir 'server-build.json') -Force
Write-Host "server files copied, with the build record" -ForegroundColor Cyan

# ---- the plugins its load order names --------------------------------------
$settingsPath = Join-Path $Dist 'server-settings.json'
$s = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
if (-not $s.loadOrder) { throw 'server-settings.json has no loadOrder' }

$vpsPlugins = ($VpsRoot -replace '\\', '/') + '/plugins'
$newOrder = @()
$missing = @()
$bytes = 0
foreach ($p in $s.loadOrder) {
    $src = $p -replace '/', '\'
    if (-not (Test-Path -LiteralPath $src)) { $missing += $p; continue }
    $name = Split-Path $src -Leaf
    Copy-Item -LiteralPath $src -Destination (Join-Path $OutDir "plugins\$name") -Force
    $bytes += (Get-Item -LiteralPath $src).Length
    $newOrder += "$vpsPlugins/$name"
}
Write-Host ("plugins: {0} copied, {1:N0} MB" -f $newOrder.Count, ($bytes/1MB)) -ForegroundColor Cyan
if ($missing) {
    Write-Host ("  NOT FOUND, left out: {0}" -f ($missing -join ', ')) -ForegroundColor Red
}

# ---- a settings file with VPS paths ----------------------------------------
# The load order must stay in exactly this order. Its indices are what form ids
# are resolved against, and the client resolves them against its own plugins.txt
# with no translation step in between.
$s.loadOrder = $newOrder
$s | Add-Member -NotePropertyName dataDir -NotePropertyValue 'data' -Force
# A dev payload: the dev server's port, voice port, name and which server a
# join pass must name, into this staged copy only (#1114). vps-dev-instance.ps1
# is where the numbers come from, the same ones Deploy-DevGamemode.ps1 checks
# for. They matter for a first install: over a running server the installer
# keeps that server's own settings and takes only the release's keys from here
# (ServerSettings.ps1, #1222).
if ($Channel -eq 'dev') {
    $s | Add-Member -NotePropertyName port -NotePropertyValue 7787 -Force
    if ($s.PSObject.Properties['name']) { $s.name = 'Thornswood Dev' }
    $s | Add-Member -NotePropertyName thornswoodVoicePort -NotePropertyValue 7789 -Force
    $s | Add-Member -NotePropertyName thornswoodServer -NotePropertyValue 'dev' -Force
    Write-Host 'dev channel: port 7787, voice 7789, name Thornswood Dev, thornswoodServer dev, in the payload only' -ForegroundColor Cyan
}
# Set-Content -Encoding UTF8 writes a byte order mark under Windows PowerShell
# 5.1 and does not under PowerShell 7, so the same line produces a different
# file depending on which one happens to run it. A BOM is not JSON: node stops
# on the first character with "Unexpected token", the server never starts, and
# nothing about the message points at the file that was written three steps
# earlier. WriteAllText with an explicit encoding is the same in both.
[IO.File]::WriteAllText((Join-Path $OutDir 'server-settings.json'), ($s | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))

# A dump from a previous run would override the file we just wrote.
$dump = Join-Path $OutDir 'server-settings-dump.json'
if (Test-Path -LiteralPath $dump) { Remove-Item -LiteralPath $dump -Force }

# ---- zip -------------------------------------------------------------------
if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
Write-Host 'compressing, this takes a minute' -ForegroundColor DarkGray
Compress-Archive -Path (Join-Path $OutDir '*') -DestinationPath $Zip -CompressionLevel Optimal

$mb = [math]::Round((Get-Item -LiteralPath $Zip).Length / 1MB, 1)
Write-Host ''
Write-Host ("{0}  ({1} MB)" -f $Zip, $mb) -ForegroundColor Green
Write-Host ''
Write-Host 'Copy that to the VPS through the RDP session, then run Install-ThornswoodServer.ps1 there.' -ForegroundColor DarkGray
Write-Host ("It expects to land at {0}." -f $VpsRoot) -ForegroundColor DarkGray
