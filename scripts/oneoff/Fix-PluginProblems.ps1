<#
  Fix-PluginProblems.ps1

  RETIRED. DO NOT RUN. Issue #1179: removed CFTO-JK-Patch.esp and RaceMenuPlugin.esp; do not run, the JK patch belongs now. The collection (or the settled load order) does this now. It refuses to run, and the rest of the file is kept for the history of how it was installed. Pattern from #405 Add-Bodies.

  What it used to do, and what is left of it:

  Removes two plugins that are actively breaking things.

  CFTO-JK-Patch.esp lists four masters: Skyrim.esm, Update.esm, CFTO.esp and
  JKs Skyrim.esp. That last one is the all in one JK's Skyrim, which is not in
  this build. We have the standalone JK's Whiterun and JK's Riverwood instead.
  Skyrim turns off any plugin whose master is missing, every single launch,
  which is the "Skyrim changed your plugin list on the way out" warning and the
  104 becoming 103. The patch cannot work without the mod it patches.

  RaceMenuPlugin.esp ships RaceMenuPluginFemales.pex and
  RaceMenuPluginWeapons.pex, both compiled in August 2018, against a RaceMenu
  from 2026. Its translation keys no longer exist, which is why character
  creation shows two tabs literally named "$Category Magic" and
  "$Category Weapons" with nothing in them.

  Nothing is deleted. Files move to _dist\removed-plugins.

      .\tools\Fix-PluginProblems.ps1
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Thornswood',
    [switch]$NoPause
)
# The refusal comes before anything else, above the strict mode line and above
# the dot source below it, so no part of the install can run by accident.
throw ('STOP. Fix-PluginProblems.ps1 is retired and installs nothing (issue #1179). ' +
       'The JK''s patch went into the collection on 15 September. Running this would take out a plugin that belongs. Do not run it. ' +
       'The file is kept for the history of how it was installed. Delete this line only if ' +
       'hand installs are meant again, and read the header first.')


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Close-Launcher.ps1')

$Data    = Join-Path $Root 'Game\Data'
$Profile = Join-Path $Root 'Profile\Default'
if (-not (Test-Path $Data)) { Die "No build at $Data." }

Head 'Making room'
if (Test-GameRunning -Root $Root) { Die 'Skyrim is running. Quit the game first.' }
$null = Stop-Launcher -Root $Root

$plugins = @('CFTO-JK-Patch.esp', 'RaceMenuPlugin.esp')
$loose   = @('Scripts\RaceMenuPluginFemales.pex', 'Scripts\RaceMenuPluginWeapons.pex')

$park = Join-Path $Root '_dist\removed-plugins'
$null = New-Item -ItemType Directory -Force -Path $park

Head 'Taking the files out of the build'
$moved = 0
foreach ($rel in ($plugins + $loose)) {
    $src = Join-Path $Data $rel
    if (-not (Test-Path -LiteralPath $src)) { Say "  $rel was already gone" 'DarkGray'; continue }
    $dest = Join-Path $park (Split-Path -Leaf $rel)
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
    Move-Item -LiteralPath $src -Destination $dest -Force
    Say "  $rel" 'Green'
    $moved++
}
Say ("  {0} moved to {1}" -f $moved, $park) 'Gray'

Head 'Taking them out of the plugin list'
foreach ($name in @('plugins.txt', 'loadorder.txt')) {
    $file = Join-Path $Profile $name
    if (-not (Test-Path $file)) { Say "  $name is missing" 'Yellow'; continue }
    $before = @(Get-Content $file)
    $after  = @($before | Where-Object {
        $bare = $_.TrimStart('*').Trim()
        -not ($plugins -contains $bare)
    })
    if ($after.Count -eq $before.Count) { Say "  $name already clean" 'DarkGray'; continue }
    # Skyrim reads these as UTF-8 with no byte order mark. Set-Content on
    # Windows PowerShell writes one, and a mark on line one is read as part of
    # the first plugin name.
    [IO.File]::WriteAllLines($file, [string[]]$after, (New-Object Text.UTF8Encoding($false)))
    Say ("  {0}: {1} -> {2} lines" -f $name, $before.Count, $after.Count) 'Green'
}

Head 'Where that leaves the list'
$pl = Join-Path $Profile 'plugins.txt'
if (Test-Path $pl) {
    $on = @(Get-Content $pl | Where-Object { $_.StartsWith('*') })
    Say ("  {0} plugins enabled" -f $on.Count) 'Green'
    Say '  Skyrim should stop rewriting this on exit now, so the launcher' 'Gray'
    Say '  should stop reporting a problem after the next session.' 'Gray'
}

Write-Host ''
Say '  Next: .\scripts\release\Ship.ps1 -Package "..."' 'Gray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
