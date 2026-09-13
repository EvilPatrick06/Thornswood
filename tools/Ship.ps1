<#
  Ship.ps1

  One command. Bumps the launcher version, builds it, and publishes everything
  that changed - launcher and mods both, in a single release.

      .\tools\Ship.ps1 "Fixed the map marker"

  Options:
      -NoBump          keep the current version number
      -Version 1.2.0   set it explicitly
      -ModsOnly        skip the launcher, publish only changed mod files
      -DryRun          build and diff, but upload nothing
      -Package         also rebuild the two installer files for new people

  The installer package is the one thing publishing does not touch. Someone
  installing from a stale one downloads every update since, on first launch,
  before they can play. So every run says how far behind it is.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Notes,
    [string]$Version,
    [switch]$NoBump,
    [switch]$ModsOnly,
    [switch]$DryRun,
    [switch]$Package,
    [string]$Root = 'C:\Thornswood'
    ,[switch]$MoveServer
    # So this can be chained after something else without stopping to wait for
    # a keypress nobody is there to give.
    ,[switch]$NoPause
)


# The launcher was SkyrimTogether.exe and is Thornswood.exe now. It replaces
# itself in place when it updates rather than being reinstalled, so an install
# made before the rename still carries the old name and both have to be looked
# for, newest first.
function Get-LauncherExe([string]$dir) {
    foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Join-Path $dir 'Thornswood.exe')
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent $Here

Write-Host ''
Write-Host '  SHIP' -ForegroundColor White
Write-Host "  $Notes" -ForegroundColor DarkGray

# ------------------------------------------------------------ version
$updaterCs = Join-Path $Here 'app\Updater.cs'
if (-not (Test-Path $updaterCs)) { Die "Could not find $updaterCs" }

$src = Get-Content $updaterCs -Raw
$m = [regex]::Match($src, 'Version\s*=\s*"([^"]+)"')
if (-not $m.Success) { Die 'Could not read the version out of app\Updater.cs' }
$current = $m.Groups[1].Value

if ($ModsOnly) {
    $target = $current
}
elseif ($Version) {
    $target = $Version
}
elseif ($NoBump) {
    $target = $current
}
else {
    $parts = $current.Split('.')
    if ($parts.Count -lt 3) { Die "Version '$current' is not in x.y.z form" }
    $parts[2] = [string]([int]$parts[2] + 1)
    $target = $parts -join '.'
}

if ($target -ne $current) {
    Head 'Version'
    Say "  $current  ->  $target" 'Green'
    $src = $src -replace 'Version\s*=\s*"[^"]+"', ('Version = "' + $target + '"')
    Set-Content $updaterCs $src -Encoding UTF8 -NoNewline
}
else {
    Head 'Version'
    Say "  staying on $current" 'DarkGray'
}

# The new version goes into Updater.cs before anything is built, because the
# exe has to carry it. Anything that stops the release after that point has to
# put it back, or a failed run burns a number and the launcher people are
# running claims a version that was never published.
function Unbump([string]$why) {
    if ($target -eq $current) { return }
    $back = Get-Content $updaterCs -Raw
    $back = $back -replace 'Version\s*=\s*"[^"]+"', ('Version = "' + $current + '"')
    Set-Content $updaterCs $back -Encoding UTF8 -NoNewline
    Head 'Version'
    Say "  put back to $current, $why" 'Yellow'
}

# ------------------------------------------------------------ build
if (-not $ModsOnly) {
    Head 'Building the launcher'
    # Resolved twice on purpose. The build writes Thornswood.exe and removes a
    # SkyrimTogether.exe left over from before the rename, so the path that
    # existed going in is not necessarily the path that exists coming out.
    # Holding on to the first answer makes a build that worked look like a
    # build that produced nothing.
    $launchDir = Join-Path $Root 'Launcher'
    $before = [datetime]::MinValue
    foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
        $p = Join-Path $launchDir $n
        if (Test-Path -LiteralPath $p) {
            $t = (Get-Item -LiteralPath $p).LastWriteTimeUtc
            if ($t -gt $before) { $before = $t }
        }
    }

    & (Join-Path $Here 'Build-Launcher.ps1') -Root $Root -NoPause

    $exe = Get-LauncherExe $launchDir
    $built = Test-Path -LiteralPath $exe
    if ($built) { $built = ((Get-Item -LiteralPath $exe).LastWriteTimeUtc -gt $before) }
    if (-not $built) {
        Unbump 'nothing was built'
        Die 'The launcher did not build. Look at the errors above.'
    }
    Say ("  built, {0:n0} KB" -f ((Get-Item $exe).Length / 1KB)) 'Green'
}

# ------------------------------------------------------------ publish
Head 'Publishing'
# A hashtable, not an array. Splatting an array passes everything positionally,
# so '-Notes' binds as a value rather than a parameter name.
$pubArgs = @{ Notes = $Notes; Root = $Root; RepoDir = $RepoDir; NoPause = $true }
if ($MoveServer) { $pubArgs['MoveServer'] = $true }
if (-not $ModsOnly) { $pubArgs['Launcher'] = $true }
if ($DryRun) {
    $pubArgs['NoUpload'] = $true
    $pubArgs['NoPush'] = $true
    Say '  dry run, nothing will be uploaded or pushed' 'Yellow'
}

$LASTEXITCODE = 0
& (Join-Path $Here 'Publish-Update.ps1') @pubArgs
$published = $LASTEXITCODE

# Exit code 2 means the publisher found nothing worth a release. The version
# was already bumped and written into Updater.cs before the build, so put it
# back rather than leaving a number that was never published.
if ($published -eq 2) {
    if ($target -ne $current) {
        Unbump 'nothing was published'
        Say '  Rebuild the launcher next time you do ship, so the exe matches.' 'DarkGray'
    }
    Head 'Done'
    Say 'Nothing shipped. The build already matches the last release.' 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ------------------------------------------------------------ the installer
# Publishing feeds people who already have the game. It does nothing for the
# two files a new person downloads, and those go stale quietly, which is the
# worst way for something to go wrong.
$zip = Join-Path $Root '_dist\Thornswood-Setup.zip'
$behind = 0
$haveZip = Test-Path $zip

if ($haveZip) {
    $zipTime = (Get-Item $zip).LastWriteTime
    $vf = Join-Path $RepoDir 'version.json'
    if (Test-Path $vf) {
        $doc = Get-Content $vf -Raw | ConvertFrom-Json
        if ($doc.PSObject.Properties['packs'] -and $doc.packs) {
            $seen = @{}
            foreach ($p in @($doc.packs)) {
                # ids are yyyyMMdd-HHmm, with -1 -2 -3 on the split ones, and
                # three parts of one release are still one release.
                $stamp = "$($p.id)"
                if ($stamp.Length -lt 13) { continue }
                $stamp = $stamp.Substring(0, 13)
                if ($seen.ContainsKey($stamp)) { continue }
                $seen[$stamp] = $true
                $when = [datetime]::MinValue
                if ([datetime]::TryParseExact($stamp, 'yyyyMMdd-HHmm', $null, 'None', [ref]$when)) {
                    if ($when -gt $zipTime) { $behind++ }
                }
            }
        }
    }
}

if ($Package) {
    Head 'Rebuilding the installer'
    & (Join-Path $Here 'Package-Thornswood.ps1') -Root $Root -NoPause
}
elseif (-not $haveZip) {
    Head 'The installer'
    Say '  there is no Thornswood-Setup.zip yet, so nobody new can install.' 'Yellow'
    Say '  .\tools\Ship.ps1 -Package "..."   builds it as part of a release' 'Yellow'
    Say '  .\tools\Package-Thornswood.ps1   builds it on its own' 'Yellow'
}
elseif ($behind -gt 0) {
    Head 'The installer'
    Say ("  Thornswood-Setup.zip is {0} release{1} behind, built {2:d MMM HH:mm}." -f $behind, $(if ($behind -eq 1) { '' } else { 's' }), (Get-Item $zip).LastWriteTime) 'Yellow'
    Say '  Anyone installing from it sits through all of those on first launch.' 'Yellow'
    Say '  .\tools\Package-Thornswood.ps1   to rebuild it' 'Yellow'
}
else {
    Head 'The installer'
    Say '  Thornswood-Setup.zip is current' 'Green'
}

Head 'Done'
if ($DryRun) { Say 'Dry run finished. Nothing left your machine.' 'Yellow' }
else { Say 'Everyone gets it next time they open the launcher.' 'Green' }
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }