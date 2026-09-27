<#
.SYNOPSIS
  Runs the two things that follow a published tip, the host feed remirror and
  the VirusTotal report for what the Downloads page offers, and says which of
  them did not complete.

.DESCRIPTION
  WHAT A TIP IS. The tip customers get is `version.json`, written and pushed by
  Publish-Update.ps1. Launchers poll `UpdateFeedUrl`, which is the site host
  feed (`docs\FEED.md`, `Feed-Rules.ps1` `Get-HostFeedVersionUrl`). So once the
  publisher has written the feed, two things and only two things are left
  before that tip is the one the world reads:

    the remirror     thornswood.net/feed for main, /feed-dev for dev, gets the
                     tip's version.json and the assets it names. Website owns
                     it; Publish-SiteFeed.ps1 is the script.
    VirusTotal       every download the Downloads page offers has a report, so
                     the link the page prints beside its SHA-256 is not
                     item-not-found. Installer and Website own it;
                     Publish-VirusTotal.ps1 is the script.

  THERE IS NO THIRD STEP FOR THE LAUNCHER, and that is the Launcher lane's
  answer rather than an omission. A launcher updates itself from the feed it
  polls, so the remirror IS the launcher update reaching people. Ship's
  mid-release Install-Launcher.ps1 refreshes the install on the machine that
  shipped and nothing else, and re-running it after the tip would refresh the
  same one install again.

  WHY ONE SCRIPT RATHER THAN TWO CALLS FROM SHIP. Ship calls this once, keyed
  off its own -Channel, and reads one exit code. Website and Installer get one
  command to run by hand after a release, or to re-run when one half failed:
  both halves ask before they act, so running it twice does nothing the first
  run already did.

    .\scripts\release\Publish-PostShip.ps1                     after a main release
    .\scripts\release\Publish-PostShip.ps1 -Channel dev        after a dev release
    .\scripts\release\Publish-PostShip.ps1 -SkipVirusTotal     the mirror only

.PARAMETER Channel
  main or dev. main mirrors to thornswood.net/feed from the Thornswood-Releases
  tip; dev mirrors to thornswood.net/feed-dev from the Thornswood-Releases-dev
  tip. Passed straight through to both halves.

.PARAMETER ReleaseDir
  The releases clone whose version.json is the tip. Left out, each half works
  it out from the channel: Thornswood-Releases beside this repository, or the
  Thornswood-Releases-dev worktree.

.PARAMETER Root
  The install the release was built from. The mirror reads the shipped launcher
  exe from it when the feed names that exe as a site asset.

.PARAMETER DistRoot
  Where releases are staged, so both halves find the pack zips and the
  installer in the same place Publish-Update.ps1 and Package-Thornswood.ps1
  wrote them.

.PARAMETER SkipRemirror
  Leaves the site serving the feed it already had. A launcher falls back to the
  GitHub feed only when the site feed does not answer at all, so an unmirrored
  feed offers people the release it last held rather than this one.

.PARAMETER SkipVirusTotal
  Leaves the report the Downloads page links as whatever it was, for when a tip
  is wanted now and nobody wants to wait on an upload.

.PARAMETER NoPause
  Exits without waiting for Enter, so Ship can call this without stopping for a
  keypress nobody is there to give.

.EXAMPLE
  .\scripts\release\Publish-PostShip.ps1 -Channel dev

  Mirrors the dev tip onto thornswood.net/feed-dev and makes sure what the
  Downloads page offers has a VirusTotal report.

.NOTES
  Exit codes: 0 both halves are done or were skipped on purpose, 1 one of them
  did not complete. Ship.ps1 reads that code, still tells the site, the Discord
  and the server, and says on its last screen which half to run again: the tip
  is published by the time this starts and nothing here can unpublish it.
#>
[CmdletBinding()]
param(
    [ValidateSet('main', 'dev')][string]$Channel = 'main',
    [string]$ReleaseDir,
    [string]$Root = 'C:\Thornswood',
    [string]$DistRoot = (& (Join-Path $PSScriptRoot 'Where.ps1') Dist),
    [switch]$SkipRemirror,
    [switch]$SkipVirusTotal,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

$Dev = ($Channel -eq 'dev')
$chanArg = if ($Dev) { ' -Channel dev' } else { '' }
$failed = New-Object System.Collections.ArrayList

# One half. Reads its exit code rather than trusting that it ran, which is the
# fault entry 118 on the To Do List is about: a script called and never looked
# at. A half that stops is remembered and the other half still runs, because
# the tip is already published and the two are independent.
function Invoke-Half([string]$what, [string]$leaf, [hashtable]$withArgs, [string]$putRight) {
    $path = Join-Path $Here $leaf
    Head $what
    if (-not (Test-Path -LiteralPath $path)) {
        Say "  $leaf is not beside this script, so $what did NOT run." 'Red'
        [void]$failed.Add([pscustomobject]@{ What = $what; PutRight = $putRight })
        return
    }
    # global:, never a bare assignment: run from a prompt, a bare
    # $LASTEXITCODE = 0 makes a copy this script owns while the child's exit
    # lands in the global one.
    $global:LASTEXITCODE = 0
    try { & $path @withArgs }
    catch {
        Say "  $what stopped: $($_.Exception.Message)" 'Red'
        [void]$failed.Add([pscustomobject]@{ What = $what; PutRight = $putRight })
        return
    }
    if ($LASTEXITCODE -ne 0) {
        Say "  $what stopped with exit code $LASTEXITCODE. The lines above say why." 'Red'
        [void]$failed.Add([pscustomobject]@{ What = $what; PutRight = $putRight })
        return
    }
}

Write-Host ''
Write-Host "  AFTER THE TIP, $Channel" -ForegroundColor White

if ($SkipRemirror) {
    Head 'The host feed mirror'
    Say '  -SkipRemirror, so the site goes on serving the feed it had, and anybody' 'Yellow'
    Say '  reading it is offered that release rather than this one.' 'Yellow'
    Say ("  .\scripts\release\Publish-SiteFeed.ps1$chanArg   mirrors it") 'DarkGray'
} else {
    $mirrorArgs = @{ Channel = $Channel; Root = $Root; DistRoot = $DistRoot; NoPause = $true }
    if ($ReleaseDir) { $mirrorArgs['ReleaseDir'] = $ReleaseDir }
    Invoke-Half 'The host feed mirror' 'Publish-SiteFeed.ps1' $mirrorArgs ".\scripts\release\Publish-SiteFeed.ps1$chanArg"
}

if ($SkipVirusTotal) {
    Head 'VirusTotal'
    Say '  -SkipVirusTotal, so the report the Downloads page links is whatever it was.' 'Yellow'
    Say ("  .\scripts\release\Publish-VirusTotal.ps1$chanArg   sends it") 'DarkGray'
} else {
    Invoke-Half 'The VirusTotal report' 'Publish-VirusTotal.ps1' `
        @{ Channel = $Channel; Root = $Root; DistRoot = $DistRoot; NoPause = $true } `
        ".\scripts\release\Publish-VirusTotal.ps1$chanArg"
}

Head 'Done'
if (-not $failed.Count) {
    Say "Everything that follows the $Channel tip is done." 'Green'
} else {
    Say "The tip is published and stays published, but $($failed.Count) of the two things that follow it did NOT complete:" 'Red'
    foreach ($f in $failed) {
        Say ("  $($f.What)") 'Red'
        Say ("    $($f.PutRight)") 'Yellow'
    }
    Say '  Both halves ask before they act, so running the line above changes nothing else.' 'DarkGray'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
# Said out loud, because the halves leave their own exit codes behind and
# Ship.ps1 reads this one.
if ($failed.Count) { exit 1 }
exit 0
