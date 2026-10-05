<#
  Run-Everything.ps1

  RETIRED. DO NOT RUN. Issue #1179: ran the old Add-* installers in one go and published once. The collection (or the settled load order) does this now. It refuses to run, and the rest of the file is kept for the history of how it was installed. Pattern from #405 Add-Bodies.

  What it used to do, and what is left of it:

  One run that installs everything waiting, checks each piece actually landed,
  and publishes once at the end instead of once per mod.

  Launched by Run-Everything.cmd so it can be double clicked. Every step
  runs with -NoShip, so the launcher gets built and the release goes out a
  single time, with one version bump and one news post.

  If a step fails, this stops there rather than carrying on and publishing a
  half applied build.
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Thornswood',
    [switch]$DryRun
)
# The refusal comes before anything else, above the strict mode line and above
# the dot source below it, so no part of the install can run by accident.
throw ('STOP. Run-Everything.ps1 is retired and installs nothing (issue #1179). ' +
       'The collection installs the mods now. This orchestrator only ran the old Add-* hand installers and published once. ' +
       'The file is kept for the history of how it was installed. Delete this line only if ' +
       'hand installs are meant again, and read the header first.')


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('=' * $m.Length) -ForegroundColor DarkGray }
function Good($m) { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Data = Join-Path $Root 'Game\Data'

Write-Host ''
Write-Host '  THORNSWOOD  -  everything at once' -ForegroundColor White
Write-Host '  Nothing is published until every step below has passed.' -ForegroundColor DarkGray

# Each step names files that must exist afterwards. A script that exits 0
# without leaving its files behind is a silent failure, and those are the ones
# that reach five people before anybody notices.
$steps = @(
    @{
        Name  = 'Carriages and ferries'
        Script = 'Add-CartTravel.ps1'
        Wants = @('CFTO.esp')
    },
    @{
        Name  = 'Localised combat damage'
        Script = 'Add-Accuracy.ps1'
        Wants = @('SKSE\Plugins\CoreImpactFramework.dll', 'SKSE\Plugins\Accuracy.dll')
    }
    # Bodies and physics (Add-Bodies.ps1) was a step here until issue #405
    # retired that script: it put the nude female body back over the build on
    # every run. The bodies come from the Nexus collection now.
)

$done = @()
$failed = $null
# StrictMode objects to reading this before any native command has set it.
$global:LASTEXITCODE = 0

foreach ($s in $steps) {
    Head $s.Name
    $path = Join-Path $Here $s.Script
    if (-not (Test-Path $path)) { Bad "$($s.Script) is missing"; $failed = $s.Name; break }

    if ($DryRun) { Say '  dry run, skipping' 'Yellow'; continue }

    try {
        & $path -Root $Root -NoShip -NoPause
        if ($LASTEXITCODE -gt 0) { Bad "$($s.Script) stopped with exit code $LASTEXITCODE"; $failed = $s.Name; break }
    }
    catch {
        Bad "$($s.Script) threw: $($_.Exception.Message)"
        $failed = $s.Name
        break
    }

    $missing = @($s.Wants | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Data $_)) })
    if ($missing.Count) {
        Bad "ran, but these never appeared: $($missing -join ', ')"
        $failed = $s.Name
        break
    }
    foreach ($w in $s.Wants) { Good $w }
    $done += $s.Name
}

if ($failed) {
    Head 'Stopped'
    Say "  $failed did not finish, so nothing has been published." 'Red'
    Say '  The build on this machine may be part way through that step.' 'Yellow'
    Say '  Everything before it is fine. Fix the error above and run this again,' 'Gray'
    Say '  the steps that already worked will just redo themselves harmlessly.' 'Gray'
    Write-Host ''
    [void](Read-Host 'Enter to close')
    exit 1
}

if ($DryRun) {
    Head 'Dry run finished'
    Say '  Nothing was installed and nothing was published.' 'Yellow'
    Write-Host ''
    [void](Read-Host 'Enter to close')
    exit 0
}

Head 'Publishing, once'
$notes = @"
Carriages, and damage that knows where it hit
- carriages and ferries run between the holds, as a fade rather than a scripted ride so it survives co-op
- where you hit somebody now matters, with the settings shipped identically to everyone
- three starter classes to test, Smith, Thief and Warrior
"@

& (Join-Path $Here 'Ship.ps1') -Notes $notes -Root $Root

Head 'All done'
foreach ($d in $done) { Good $d }
Write-Host ''
Say '  Everyone gets it next time they open the launcher.' 'Green'
Write-Host ''
[void](Read-Host 'Enter to close')
