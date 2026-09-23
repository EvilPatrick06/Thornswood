<#
  Add-NoticeBoards.ps1

  Installs Missives into the isolated build, so the boards in and around
  towns stop being scenery. Missives hands out its own contracts, generated
  fresh, and every person pulls their own off the board, which is what makes
  it work in co-op instead of five people fighting over one quest.

  It reads the archives straight out of Downloads. Nothing touches Vortex or
  your Steam copy, and it publishes when it is done, so this is the only
  command you run.

      .\tools\Add-NoticeBoards.ps1
      .\tools\Add-NoticeBoards.ps1 -NoShip

  Options:
      -Notes "..."     what the News page says about this release
      -NoShip          install only, publish nothing
#>
[CmdletBinding()]
param(
    [string]$Root      = 'C:\Thornswood',
    [string]$Downloads = "$env:USERPROFILE\Downloads",
    [string]$Notes = 'The notice boards work now. Missives puts real contracts on the boards in and around every town, generated fresh, and each of you takes your own off the board rather than sharing one.',
    [switch]$NoShip,
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

$Data    = Join-Path $Root 'Game\Data'
$Golden  = Join-Path $Root 'Profile\Default'
$LocalAD = Join-Path $Root 'Profile\LocalAppData'

if (-not (Test-Path $Data)) { Die "No build at $Data." }

Head 'Making room'
if (Test-GameRunning -Root $Root) { Die 'Skyrim is running. Quit the game first, so this does not write underneath it.' }
$null = Stop-Launcher -Root $Root

# ---- the archives ---------------------------------------------------------
Head 'Finding the downloads'
# Every match, not just the newest. Worldspace Additions and the main file
# both start with "Missives", and whichever downloaded last would otherwise
# be the only one considered and then filtered straight back out.
function AllMatching($pattern) {
    return @(Get-ChildItem -LiteralPath $Downloads -Filter $pattern -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending)
}

$all   = @(AllMatching 'Missives*')
$extra = @($all | Where-Object { $_.Name -match 'Worldspace' })
$main  = @($all | Where-Object { $_.Name -notmatch 'Worldspace' })

if (-not $main.Count) { Die "Could not find a 'Missives*' archive in $Downloads." }
$mainZip  = $main[0]
$extraZip = if ($extra.Count) { $extra[0] } else { $null }

Say "  $($mainZip.Name)" 'Green'
if ($extraZip) { Say "  $($extraZip.Name)" 'Green' }
else { Say '  no Worldspace Additions archive, the smaller settlements will not get boards' 'Yellow' }

$7z = @(
    "$env:ProgramFiles\7-Zip\7z.exe"
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $7z) { Die '7-Zip is not installed.' }

$work = Join-Path $env:TEMP 'Missives-install'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path "$work\main", "$work\extra"

Head 'Unpacking'
function Unzip($archive, $dest) {
    # A native tool writing one line to stderr kills the script while
    # ErrorActionPreference is Stop, so 7-Zip runs with it relaxed.
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $7z x -y "-o$dest" $archive | Out-Null; return $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
}
if ((Unzip $mainZip.FullName "$work\main") -gt 1) { Die 'Could not unpack the Missives archive.' }
if ($extraZip -and (Unzip $extraZip.FullName "$work\extra") -gt 1) { Die 'Could not unpack the Worldspace Additions archive.' }

# ---- what goes in ---------------------------------------------------------
# Archives from Nexus are sometimes wrapped in one folder and sometimes not,
# so the plugin is found rather than assumed, and Data is rebuilt from where
# it actually sits.
function RootOf($dir, $plugin) {
    $hit = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter $plugin -ErrorAction SilentlyContinue |
             Sort-Object { $_.FullName.Length } | Select-Object -First 1)
    if (-not $hit.Count) { return $null }
    return (Split-Path -Parent $hit[0].FullName)
}

Head 'Installing'
$sources = @()

$mainRoot = RootOf "$work\main" 'Missives.esp'
if (-not $mainRoot) { Die "The Missives archive did not contain Missives.esp. Did a different file get downloaded?" }
$sources += $mainRoot

$plugins = @('Missives.esp')

if ($extraZip) {
    $extraRoot = RootOf "$work\extra" 'Missives - Worldspace Additions.esp'
    if ($extraRoot) { $sources += $extraRoot; $plugins += 'Missives - Worldspace Additions.esp' }
    else { Say '  Worldspace Additions archive had no plugin in it, skipping' 'Yellow' }
}

$copied = 0
foreach ($from in $sources) {
    foreach ($f in @(Get-ChildItem -LiteralPath $from -Recurse -File -Force)) {
        $rel = $f.FullName.Substring($from.Length).TrimStart('\')
        # Scripts\Source and Source\Scripts are for people compiling papyrus.
        if ($rel -match '(^|\\)[Ss]ource\\') { continue }
        # Nexus archives carry readmes and fomod trees that Skyrim never reads.
        if ($rel -match '(^|\\)fomod\\') { continue }
        if ($rel -match '\.(txt|md|pdf|jpg|png|html)$' -and $rel -notmatch '\\') { continue }
        $dest = Join-Path $Data $rel
        $dir  = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        $copied++
    }
}
Say ("  {0:n0} files into Game\Data" -f $copied) 'Green'

# ---- the load order -------------------------------------------------------
# Missives places its boards in the worldspace, so it goes after the city
# overhauls that move the ground it stands on, and before Skyrim Unbound,
# which stays last because it owns the opening.
Head 'Load order'
$plug = Join-Path $Golden 'plugins.txt'
$lo   = Join-Path $Golden 'loadorder.txt'
if (-not (Test-Path $plug)) { Die "No reference plugin list at $plug." }

$plugLines = @(Get-Content $plug)
$loLines   = @(Get-Content $lo)

function InsertBeforeUnbound($lines, $entry) {
    $out = @()
    $placed = $false
    foreach ($line in $lines) {
        if (-not $placed -and $line -match '^\*?Skyrim Unbound') { $out += $entry; $placed = $true }
        $out += $line
    }
    if (-not $placed) { $out += $entry }
    return $out
}

foreach ($name in $plugins) {
    if (-not (Test-Path -LiteralPath (Join-Path $Data $name))) { Die "$name did not land in Data." }
    if ($plugLines -notcontains "*$name" -and $plugLines -notcontains $name) {
        $plugLines = @(InsertBeforeUnbound $plugLines "*$name")
    }
    if ($loLines -notcontains $name) {
        $loLines = @(InsertBeforeUnbound $loLines $name)
    }
    Say "  + $name" 'Green'
}

# No byte order mark. Skyrim reads the first line of plugins.txt verbatim, so
# three stray bytes in front of it become part of a plugin name that does not
# exist.
[IO.File]::WriteAllLines($plug, [string[]]$plugLines, (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllLines($lo,   [string[]]$loLines,   (New-Object Text.UTF8Encoding($false)))

# The live pair is what Skyrim and the server actually read. Copying the
# reference over them is exactly what the launcher's Fix button does.
if (-not (Test-Path $LocalAD)) { $null = New-Item -ItemType Directory -Force -Path $LocalAD }
Copy-Item $plug (Join-Path $LocalAD 'plugins.txt') -Force
Copy-Item $lo   (Join-Path $LocalAD 'loadorder.txt') -Force
Say '  reference and live lists are back in step' 'DarkGray'

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Say "  $($plugLines.Count) lines in plugins.txt, $($loLines.Count) in loadorder.txt" 'DarkGray'

# ---- publish --------------------------------------------------------------
if ($NoShip) {
    Head 'Done'
    Say 'Installed. Nothing published, you asked for -NoShip.' 'Green'
    Write-Host ''
    Say 'When you are ready:  .\tools\Ship.ps1 "what changed"' 'Gray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

Head 'Handing over to Ship'
Say '  builds the launcher, then publishes the launcher and the changed mod files together' 'DarkGray'
& (Join-Path $Here 'Ship.ps1') -Notes $Notes -Root $Root
