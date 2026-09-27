<#
.SYNOPSIS
  Runs what follows a published tip, the host feed remirror and the VirusTotal
  report for what the Downloads page offers, and says which of them did not
  complete.

.DESCRIPTION
  WHAT A TIP IS. The tip customers get is `version.json`, written and pushed by
  Publish-Update.ps1. Launchers poll the feed url in it, which is the site host
  feed (`docs\FEED.md`, and `Get-HostFeedVersionUrl` in `Feed-Rules.ps1`:
  https://thornswood.net/feed/version.json live, /feed-dev for dev). So once the
  publisher has written that file, two things are left before the tip is the one
  the world reads, and neither used to be part of shipping:

    the remirror   thornswood.net/feed, from the Thornswood-Releases tip, or
                   /feed-dev from the Thornswood-Releases-dev tip, gets that
                   version.json and the assets it names.
                   scripts\deploy\Remirror-Site-Feed.ps1 does it, and that
                   script is Website's.
    VirusTotal     the installer the Downloads page offers has a report, so the
                   link the page prints beside its SHA-256 is not
                   item-not-found. scripts\release\Publish-VirusTotal.ps1 does
                   it, and that script is the installer lane's.

  THIS SCRIPT IMPLEMENTS NEITHER OF THEM. It is the one place that knows a
  release has two things after it, in what order, with which channel, and what
  to say when one did not happen. The two scripts it calls are owned by the
  lanes whose work they are, and Remirror-Site-Feed.ps1 asked for exactly this
  call in its own header: "After the release is published and before the news
  step, one line."

  THERE IS NO THIRD STEP FOR THE LAUNCHER, and that is the Launcher lane's
  answer rather than an omission. A launcher polls the feed and updates itself,
  so the remirror IS the launcher update reaching people. Ship's mid-release
  Install-Launcher.ps1 refreshes the install on the machine that shipped
  (C:\Thornswood for main, C:\Thornswood-DevBuild for dev) and nothing else, so
  re-running it after the tip would refresh that one install again.

  WHAT IT DOES ON A DEV RELEASE. The remirror goes to /feed-dev. VirusTotal is
  left alone, because a dev release does not touch the installer and so does not
  change what the Downloads page offers.

  WHAT A FAILURE MEANS. The tip is published by the time this starts, and
  nothing here can unpublish it. The remirror refuses rather than publish a feed
  naming bytes the site does not hold, which leaves the site one release behind
  instead of pointing launchers at a 404, and it exits 1 when it refuses. That
  code comes back out of this script, so Ship can say on its last screen that
  what follows the tip did not complete while still telling the site, the
  Discord and the server. The VirusTotal half exits 0 whatever happens, by its
  own lane's decision that a missing report may never fail a release; its line
  on screen is the record.

  Both halves ask before they act, so running this again after a failure does
  nothing the first run already did.

    .\scripts\release\Publish-PostShip.ps1                     after a main release
    .\scripts\release\Publish-PostShip.ps1 -Channel dev        after a dev release
    .\scripts\release\Publish-PostShip.ps1 -SkipVirusTotal     the remirror only

.PARAMETER Channel
  main or dev. main remirrors to thornswood.net/feed from the
  Thornswood-Releases tip and asks about the installer; dev remirrors to
  thornswood.net/feed-dev from the Thornswood-Releases-dev tip and leaves the
  installer alone.

.PARAMETER ReleaseDir
  The clone or worktree holding the version.json that was just published,
  passed to the remirror as its -FeedDir. Left out, that script works it out
  from the channel, the same way Publish-Update.ps1 does.

.PARAMETER Root
  The install the release was built from. Only used to find the installer for
  the VirusTotal half, in the staging folder for that root.

.PARAMETER DistRoot
  Where releases are staged, so the installer is looked for in the same place
  Package-Thornswood.ps1 built it and Publish-Installer.ps1 published it from.

.PARAMETER Installer
  The file to ask VirusTotal about, when it is not the Thornswood-Setup.exe in
  the staging folder. That exe is what the Downloads page offers, so it is the
  hash the page prints a VirusTotal link for.

.PARAMETER SkipRemirror
  Leaves the site serving the feed it already had. A launcher falls back to the
  GitHub feed only when the site feed does not answer at all, so an unmirrored
  feed offers people the release it last held rather than this one.

.PARAMETER SkipVirusTotal
  Leaves the report the Downloads page links as whatever it was, for when a tip
  is wanted now and nobody wants to wait on an upload of most of a gigabyte.

.PARAMETER NoPause
  Exits without waiting for Enter, so Ship can call this without stopping for a
  keypress nobody is there to give.

.EXAMPLE
  .\scripts\release\Publish-PostShip.ps1 -Channel dev

  Puts the dev tip on thornswood.net/feed-dev and leaves the installer alone.

.NOTES
  Exit codes: 0 both halves are done or were skipped on purpose, 1 one of them
  did not complete. Ship.ps1 reads that code, still tells the site, the Discord
  and the server, and says on its last screen which line to run again.
#>
[CmdletBinding()]
param(
    [ValidateSet('main', 'dev')][string]$Channel = 'main',
    [string]$ReleaseDir,
    [string]$Root = 'C:\Thornswood',
    [string]$DistRoot = (& (Join-Path $PSScriptRoot 'Where.ps1') Dist),
    [string]$Installer,
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
$devArg = if ($Dev) { ' -Dev' } else { '' }
$failed = New-Object System.Collections.ArrayList

# One half, and what its exit code meant. Reading that code is the whole point
# of this script: entry 118 on the To Do List is Ship calling something and
# never looking at what it said, and a half that stopped has to be a line
# somebody sees rather than a silence.
function Invoke-Half([string]$what, [string]$path, [hashtable]$withArgs, [string]$putRight, [string]$fromWhere) {
    Head $what
    if (-not (Test-Path -LiteralPath $path)) {
        Say "  $path is not here, so $what did NOT happen." 'Red'
        if ($fromWhere) { Say "  $fromWhere" 'Yellow' }
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

# ------------------------------------------------------------ the remirror
if ($SkipRemirror) {
    Head 'The host feed'
    Say '  -SkipRemirror, so the site goes on serving the feed it had, and anybody' 'Yellow'
    Say '  reading it is offered that release rather than this one.' 'Yellow'
    Say ("  .\scripts\deploy\Remirror-Site-Feed.ps1$devArg   mirrors it") 'DarkGray'
} else {
    $mirror = Join-Path $Here '..\deploy\Remirror-Site-Feed.ps1'
    $mirrorArgs = @{ Dev = $Dev }
    # Its own name for the same thing: the clone or worktree holding the
    # version.json that was just published.
    if ($ReleaseDir) { $mirrorArgs['FeedDir'] = $ReleaseDir }
    Invoke-Half 'The host feed remirror' $mirror $mirrorArgs `
        ".\scripts\deploy\Remirror-Site-Feed.ps1$devArg" `
        'It is the website lane''s script, from pull request #730. Until it is on this branch there is nothing here that can mirror the feed.'
}

# ------------------------------------------------------------ VirusTotal
#
# The installer is what the Downloads page offers and the hash it prints a
# VirusTotal link for, so the exe in the staging folder is the file to ask
# about. Publish-Installer.ps1 already asks when it publishes a new one, so this
# is for every release that did not rebuild the installer, where the one on the
# site may still have no report.
if ($SkipVirusTotal) {
    Head 'VirusTotal'
    Say '  -SkipVirusTotal, so the report the Downloads page links is whatever it was.' 'Yellow'
    Say '  .\scripts\release\Publish-VirusTotal.ps1 -Path <the installer exe>   sends it' 'DarkGray'
}
elseif ($Dev) {
    Head 'VirusTotal'
    Say '  a dev release does not touch the installer, so what the Downloads page offers' 'DarkGray'
    Say '  did not change and nothing was asked.' 'DarkGray'
}
else {
    if (-not $Installer) {
        # The same two places Ship.ps1 measures the installer in: the staging
        # folder for this root, and the old spot under the play install for a
        # machine that has not published since that moved.
        foreach ($candidate in @(
            (Join-Path (Join-Path (Join-Path $DistRoot (Split-Path -Leaf $Root.TrimEnd('\'))) '_dist') 'Thornswood-Setup.exe'),
            (Join-Path $Root '_dist\Thornswood-Setup.exe')
        )) {
            if (Test-Path -LiteralPath $candidate) { $Installer = $candidate; break }
        }
    }
    if (-not $Installer) {
        Head 'VirusTotal'
        Say '  there is no Thornswood-Setup.exe on this machine, so there is nothing to send.' 'Yellow'
        Say '  Whoever built the installer the site is serving runs this on their machine:' 'DarkGray'
        Say '  .\scripts\release\Publish-VirusTotal.ps1 -Path <the installer exe>' 'DarkGray'
    } else {
        Invoke-Half 'The VirusTotal report' (Join-Path $Here 'Publish-VirusTotal.ps1') `
            @{ Path = $Installer } `
            ".\scripts\release\Publish-VirusTotal.ps1 -Path `"$Installer`"" `
            'It is the installer lane''s script, from pull request #734. Until it is on this branch nothing here can send the file.'
    }
}

Head 'Done'
if (-not $failed.Count) {
    Say "Everything that follows the $Channel tip is done." 'Green'
} else {
    Say "The tip is published and stays published, but $($failed.Count) of what follows it did NOT complete:" 'Red'
    foreach ($f in $failed) {
        Say ("  $($f.What)") 'Red'
        Say ("    $($f.PutRight)") 'Yellow'
    }
    Say '  Each line above asks before it acts, so running it changes nothing else.' 'DarkGray'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
# Said out loud, because the halves leave their own exit codes behind and
# Ship.ps1 reads this one.
if ($failed.Count) { exit 1 }
exit 0
