<#
  Remove-FomodLeftovers.ps1

  Clears the FOMOD option folders that the body mod install left sitting in
  Game\Data.

  A FOMOD archive is a menu, not a mod. Its options live in folders like
  "21 Dcup SMP and CBPC Heavy" or "80 CBPC Breast A-D", and an installer is
  meant to copy the CONTENTS of the chosen ones into Data. Add-Bodies.ps1
  flattened the ones it was told to pick, which is why CBBE.esp, XPMSE.esp,
  TheNewGentleman.esp and cbp.dll are all in the right place, but it also
  copied every option it did not pick as a folder of its own.

  Skyrim only reads Data\meshes, Data\textures and so on. It never looks at
  Data\21 Dcup SMP and CBPC Heavy\meshes. So these folders do nothing except
  sit in the pack everyone downloads and in the installer everyone new
  downloads.

  Nothing is deleted. Each folder is moved to _dist\fomod-leftovers so you can
  put any of it back if something turns out to have been load bearing.

      .\tools\Remove-FomodLeftovers.ps1

  Options:
      -DryRun          list what would move, move nothing
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Thornswood',
    [switch]$DryRun,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Close-Launcher.ps1')

$Data = Join-Path $Root 'Game\Data'
if (-not (Test-Path $Data)) { Die "No build at $Data." }

Head 'Making room'
if (Test-GameRunning -Root $Root) { Die 'Skyrim is running. Quit the game first.' }
$null = Stop-Launcher -Root $Root

# The numbered ones are unambiguous: a folder in Data whose name starts with
# two digits and a space is a FOMOD option, never a mod. The three named ones
# were checked by hand and hold nothing but a meshes tree.
$byName = @('Main', 'HP', 'LP')

Head 'Looking for FOMOD leftovers'
$found = @()
foreach ($d in @(Get-ChildItem -LiteralPath $Data -Directory -Force)) {
    $isNumbered = $d.Name -match '^\d\d\s'
    $isNamed    = $byName -contains $d.Name
    if (-not $isNumbered -and -not $isNamed) { continue }

    # A real mod folder would carry a plugin or an archive at its top level.
    # If one of these does, something is not what I think it is, so leave it.
    $tops = @(Get-ChildItem -LiteralPath $d.FullName -File -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Extension -match '^\.(esp|esm|esl|bsa)$' })
    if ($tops.Count) {
        Say ("  skipping {0}, it has a plugin or archive at its top level" -f $d.Name) 'Yellow'
        continue
    }

    $bytes = 0
    $files = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $bytes += $f.Length; $files++
    }
    $found += [pscustomobject]@{ Name = $d.Name; Path = $d.FullName; Bytes = $bytes; Files = $files }
}

if (-not $found.Count) {
    Head 'Done'
    Say 'Nothing to clear, Data is already clean.' 'Green'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

$totalBytes = 0
$totalFiles = 0
foreach ($f in $found) { $totalBytes += $f.Bytes; $totalFiles += $f.Files }

foreach ($f in ($found | Sort-Object Bytes -Descending | Select-Object -First 12)) {
    Say ("  {0,-42} {1,8:n1} MB  {2,6:n0} files" -f $f.Name, ($f.Bytes / 1MB), $f.Files) 'Gray'
}
if ($found.Count -gt 12) { Say ("  and {0} more" -f ($found.Count - 12)) 'DarkGray' }
Write-Host ''
Say ("  {0} folders, {1:n0} files, {2:n2} GB" -f $found.Count, $totalFiles, ($totalBytes / 1GB)) 'Yellow'

if ($DryRun) {
    Head 'Done'
    Say 'Dry run. Nothing moved.' 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

$park = Join-Path $Root '_dist\fomod-leftovers'
$null = New-Item -ItemType Directory -Force -Path $park

Head 'Moving them out of the build'
$moved = 0
foreach ($f in $found) {
    $dest = Join-Path $park $f.Name
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    Move-Item -LiteralPath $f.Path -Destination $dest -Force
    $moved++
}
Say ("  {0} folders moved to {1}" -f $moved, $park) 'Green'

Head 'Checking the real install survived'
$ok = $true
foreach ($need in @(
    'CBBE.esp', 'XPMSE.esp', 'TheNewGentleman.esp', 'RaceMenuMorphsCBBE.esp',
    'SKSE\Plugins\cbp.dll', 'SKSE\Plugins\CBPConfig.txt', 'SKSE\Plugins\CBPCollisionConfig.txt',
    'meshes', 'textures'
)) {
    if (Test-Path -LiteralPath (Join-Path $Data $need)) {
        Say "  $need" 'Green'
    } else {
        Say "  $need IS MISSING" 'Red'; $ok = $false
    }
}
if (-not $ok) {
    Say ''
    Say "  Put it all back with:  Move-Item '$park\*' '$Data'" 'Yellow'
    Die 'Something that should have stayed is gone. Nothing has been published.'
}

Write-Host ''
Say '  Next: .\scripts\release\Ship.ps1 -Package "..."' 'Gray'
Say '  The publisher sees these as removals, so everyone else loses them too,' 'Gray'
Say '  and -Package rebuilds the installer without them.' 'Gray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
