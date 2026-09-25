<#
  Set-UnboundMenu.ps1

  Switches Skyrim Unbound's config menu between the locked version and the
  full one.

  The shipped build runs a patched SkyrimUnboundMCMScript.pex whose page list
  is a single entry, Starting Location. That is what stops people handing
  themselves gear during character creation. It also stops YOU setting a class
  up, because Equipment, Spells and Inventory are the pages you need to build
  a preset.

  So: unlock, build the preset in game, save it under Unbound's own preset
  menu, quit, lock again, ship. The preset survives, since it is a file in
  SKSE\Plugins\SkyrimUnbound\Presets, and the menu goes back to one page for
  everyone else.

      .\scripts\mods\Set-UnboundMenu.ps1 -Full      every page, for authoring presets
      .\scripts\mods\Set-UnboundMenu.ps1 -Locked    Starting Location only, for shipping
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Thornswood',
    [switch]$Full,
    [switch]$Locked,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\dev\Close-Launcher.ps1')

if ($Full -and $Locked) { Die 'Pick one, -Full or -Locked.' }
if (-not $Full -and -not $Locked) { Die 'Say which: -Full to author presets, -Locked to ship.' }

$live    = Join-Path $Root 'Game\Data\Scripts\SkyrimUnboundMCMScript.pex'
$stock   = Join-Path $Root '_dist\unbound-original\SkyrimUnboundMCMScript.pex'
$lockedF = Join-Path $Root '_dist\unbound-locked\SkyrimUnboundMCMScript.pex'

foreach ($f in @($live, $stock, $lockedF)) {
    if (-not (Test-Path -LiteralPath $f)) { Die "Missing $f" }
}

Head 'Making room'
if (Test-GameRunning -Root $Root) { Die 'Skyrim is running. Quit the game first.' }
$null = Stop-Launcher -Root $Root

$src  = if ($Full) { $stock } else { $lockedF }
$what = if ($Full) { 'every page' } else { 'Starting Location only' }

Copy-Item -LiteralPath $src -Destination $live -Force

function Sha($f) { return (Get-FileHash $f -Algorithm SHA256).Hash }
if ((Sha $live) -ne (Sha $src)) { Die 'The copy did not take.' }

Head 'Unbound menu'
Say "  now $what" 'Green'
Write-Host ''
if ($Full) {
    Say '  Build the class in game, then use Unbound''s own save-preset to write it out.' 'Gray'
    Say '  Do NOT ship while it is like this, or everyone gets the full menu.' 'Yellow'
    Say '  When you are done:  .\scripts\mods\Set-UnboundMenu.ps1 -Locked' 'Gray'
} else {
    Say '  Safe to ship.' 'Gray'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
