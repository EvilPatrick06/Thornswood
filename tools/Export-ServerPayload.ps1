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
    [string]$Dist    = 'C:\Thornswood-Dev\skymp\build\dist\server',
    [string]$OutDir  = 'C:\Thornswood-Dev\_payload',
    [string]$VpsRoot = 'C:\Thornswood-Server',
    [string]$Zip     = 'C:\Thornswood-Dev\thornswood-server.zip'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Dist)) { throw "server dist not found: $Dist" }

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
