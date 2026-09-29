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
    [ValidateSet('main', 'dev')][string]$Channel = 'main'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Dist)) { throw "server dist not found: $Dist" }

# ---- the live payload carries the live server's settings, or nothing -------
# Until #1114 a dev Publish-Server rewrote the build's own settings to port
# 7787, voice 7789 and the name Thornswood Dev and never put them back, so the
# next live publish packed them and live came up on the dev port. Nothing
# writes dev settings into the build now, but a build left that way by an
# older run, or by Deploy-DevGamemode pointed at the wrong folder, still stops
# here, before anything is copied or zipped.
$liveWhy = @()
if ($Channel -eq 'main') {
    $chk = Get-Content -LiteralPath (Join-Path $Dist 'server-settings.json') -Raw | ConvertFrom-Json
    $chkPort = if ($chk.PSObject.Properties['port']) { [string]$chk.port } else { 'none' }
    if ($chkPort -ne '7777') { $liveWhy += "port $chkPort, not 7777" }
    if ($chk.PSObject.Properties['thornswoodVoicePort'] -and [string]$chk.thornswoodVoicePort -eq '7789') {
        $liveWhy += 'the dev voice port 7789'
    }
    if ($chk.PSObject.Properties['name'] -and [string]$chk.name -eq 'Thornswood Dev') { $liveWhy += 'the name Thornswood Dev' }
}
if ($liveWhy.Count) {
    throw ("server-settings.json in $Dist is not the live server's: " + ($liveWhy -join '; ') +
           '. Run .\scripts\deploy\Deploy-Gamemode.ps1, which writes the live ones, then publish again. Nothing was packed.')
}

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
Write-Host "server files copied" -ForegroundColor Cyan

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
# A dev payload: the dev server's port, voice port and name, into this staged
# copy only (#1114). vps-dev-instance.ps1 is where the numbers come from, the
# same ones Deploy-DevGamemode.ps1 checks for. The build's live file unpacked
# into the dev root unchanged would bring dev up on the live port.
if ($Channel -eq 'dev') {
    $s | Add-Member -NotePropertyName port -NotePropertyValue 7787 -Force
    if ($s.PSObject.Properties['name']) { $s.name = 'Thornswood Dev' }
    $s | Add-Member -NotePropertyName thornswoodVoicePort -NotePropertyValue 7789 -Force
    Write-Host 'dev channel: port 7787, voice 7789, name Thornswood Dev, in the payload only' -ForegroundColor Cyan
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
