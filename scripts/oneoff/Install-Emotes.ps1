<#
  Install-Emotes.ps1

  Lays down the emote wheel: a SkyrimPlatform plugin and the page it draws.

  It is a plugin rather than part of the SkyMP client because it does not have to
  be. An animation name triggered on your own character reaches everybody else
  already: the client hooks sendAnimationEvent and forwards whatever string comes
  through, the server stores it without validating, and the receiving clients
  play it with no whitelist. So a keybind and a page are the whole feature.

  The browser is free on this setup. SkyMP's own UI is skymp5-front, which is
  BUILD_FRONT=OFF here, so nothing has claimed the CEF overlay and there is no
  text chat competing for it.

  Everybody who wants to see the emotes needs the plugin, but only the person
  performing one needs it to play. Somebody without it still sees yours.
#>
param(
    [string]$From,
    [string]$Game = 'C:\Thornswood\Game'
)


# Resolved from where this script is rather than from a fixed path under
# Downloads. The repo folder gets renamed and moved, and a default that names it
# turns every one of these into a broken command the first time it does.
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $From) { $From = Join-Path $Here 'emotes' }

$plugin  = Join-Path $From 'thornswood-emotes.js'
$page    = Join-Path $From 'thornswood-emotes.html'
$ini     = Join-Path $From 'Thornswood.ini'
foreach ($f in @($plugin, $page, $ini)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "not found: $f" }
}

$pluginDir = Join-Path $Game 'Data\Platform\Plugins'
$uiDir     = Join-Path $Game 'Data\Platform\UI'

if (-not (Test-Path -LiteralPath $pluginDir)) {
    throw "not found: $pluginDir. Is this the right game folder?"
}
if (-not (Test-Path -LiteralPath $uiDir)) {
    New-Item -ItemType Directory -Path $uiDir -Force | Out-Null
    Write-Host "created $uiDir" -ForegroundColor DarkGray
}

Copy-Item -LiteralPath $plugin  -Destination (Join-Path $pluginDir 'thornswood-emotes.js')  -Force
Copy-Item -LiteralPath $page    -Destination (Join-Path $uiDir 'thornswood-emotes.html')    -Force

# SkyrimPlatform watches its plugin folders and reloads every plugin whenever
# anything in one changes. Anything in here that is not a plugin is therefore a
# tripwire: a log file written next to the plugins made the game reload them
# 2,250 times in four minutes, which looks like a frozen game with a dead
# keyboard rather than like a mistake. Old ones get cleared out here so a
# machine that already has one is fixed by reinstalling.
$strays = @(Get-ChildItem -LiteralPath $pluginDir -File -EA SilentlyContinue |
            Where-Object { $_.Extension -notin '.js', '.txt', '.json' })
foreach ($f in $strays) {
    try {
        Remove-Item -LiteralPath $f.FullName -Force
        Write-Host ("  removed {0}, it was making SkyrimPlatform reload every plugin" -f $f.Name) -ForegroundColor Yellow
    } catch {
        Write-Host ("  could not remove {0}, delete it by hand or the game will stutter" -f $f.Name) -ForegroundColor Red
    }
}

# The keys live in an ini so Settings in the game can read and rebind them
# (#3126). Never overwrite one that is already there: that is somebody's rebind.
$iniDest = Join-Path $Game 'Data\SKSE\Plugins\Thornswood.ini'
if (Test-Path -LiteralPath $iniDest) {
    Write-Host '  keys             already set, left alone' -ForegroundColor DarkGray
} else {
    Copy-Item -LiteralPath $ini -Destination $iniDest -Force
}
Write-Host 'client plugins installed' -ForegroundColor Cyan
Write-Host ("  emote wheel      {0}" -f (Join-Path $pluginDir 'thornswood-emotes.js')) -ForegroundColor DarkGray
Write-Host ("  wheel page       {0}" -f (Join-Path $uiDir 'thornswood-emotes.html')) -ForegroundColor DarkGray

# The browser has to be on, or loadUrl throws and the plugin logs and gives up.
$ini = Join-Path $Game 'Data\SKSE\Plugins\SkyrimPlatform.ini'
if (Test-Path -LiteralPath $ini) {
    $backend = (Get-Content -LiteralPath $ini | Where-Object { $_ -match '^\s*BackendName\s*=' } |
                Select-Object -First 1) -replace '^\s*BackendName\s*=\s*', ''
    $backend = $backend.Trim()
    if ($backend -eq 'off') {
        Write-Host ''
        Write-Host "SkyrimPlatform.ini has [Browser] BackendName = off. The wheel cannot draw." -ForegroundColor Red
        Write-Host "Set it to auto and start the game again." -ForegroundColor Red
    } else {
        Write-Host ("  backend {0}" -f $(if ($backend) { $backend } else { 'auto (default)' })) -ForegroundColor DarkGray
    }
}

Write-Host ''
# The keys are on Settings in the game, read out of the same ini this just
# wrote. Printing them here as well is a second copy that goes stale.
