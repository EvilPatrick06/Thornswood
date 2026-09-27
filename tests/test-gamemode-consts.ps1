# test-gamemode-consts.ps1
# Proves const DATA, STATIONS, ITEMS and CHARGEN in game\gamemode.js match
# game\data\*.json. Run Install-GamemodeConsts.js after editing the JSON.
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Resolve-Path (Join-Path $Here '..')
Push-Location $Root
try {
    node .\scripts\dev\Install-GamemodeConsts.js --check
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}
