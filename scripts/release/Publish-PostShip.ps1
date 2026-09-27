<#
.SYNOPSIS
  Runs what follows a published tip, the host feed remirror and the VirusTotal
  upload for the installer the Downloads page offers, and says plainly when one
  of them did not happen.

.DESCRIPTION
  WHAT A TIP IS. The tip customers get is `version.json`, written and pushed by
  Publish-Update.ps1. Launchers poll the feed url in it, which is the site host
  feed (`docs\FEED.md`, and `Get-HostFeedVersionUrl` in `Feed-Rules.ps1`:
  https://thornswood.net/feed/version.json live, /feed-dev for dev). So once the
  publisher has written that file, two things are left before the tip is the one
  the world reads, and neither used to be part of shipping.

  THE TWO CALLS, EXACTLY AS THEIR LANES PINNED THEM. Both paths are relative to
  this script, which sits in scripts\release beside Ship.ps1, so they are the
  same two lines either would run:

      & (Join-Path $Here '..\deploy\Remirror-Site-Feed.ps1') -Dev:$Dev
      & (Join-Path $Here 'Publish-VirusTotal.ps1') -Path <file> -Sha256 <hex>

  The remirror is the website lane's (pull request #730). Default is main, to
  /feed; -Dev is the dev channel, to /feed-dev. It has -Check for a dry run,
  -Verify to rehash what is up there, and optional -FeedDir and -AssetDir, and
  nothing here passes those: it works the clone out from the channel itself.

  The upload is the installer lane's (pull request #734). It reads the key from
  the environment variable VT_API_KEY and nowhere else, and a missing key or an
  answer it cannot use is one line and exit 0. There is no upload written here
  to fall back on, by their lane's decision and this one's.

  NOTHING HERE FAILS A RELEASE. The tip is on the feed before any of this runs.
  A script that is not on this machine yet is a line naming it. A remirror that
  exits 1 has refused to publish a feed naming bytes the site does not hold,
  which leaves the site one release behind rather than pointing launchers at a
  404, and that is a line too. Both are said in full, with the command that puts
  them right, and the release stays out and stays announced. Asked for by the
  website lane on 27 September: "Exit 1 = refused publish (do not fail the
  release)", the same spirit as Ship's own try/catch around Publish-News.

  THERE IS NO THIRD STEP FOR THE LAUNCHER, and that is the launcher lane's
  answer rather than an omission. A launcher polls the feed and updates itself,
  so the remirror IS the launcher update reaching people. Ship's mid-release
  Install-Launcher.ps1 refreshes the install on the machine that shipped
  (C:\Thornswood for main, C:\Thornswood-DevBuild for dev) and nothing else, so
  re-running it after the tip would refresh that one install again.

  IT RUNS ON EVERY RELEASE, DEV AND MAIN, and no switch turns either half off.
  Everything goes to dev first (CONTRIBUTING.md, decided 23 September), so the
  dev channel is where this is exercised several times a week rather than once a
  fortnight. -Only is how Ship takes one half at a time and how a person runs one
  by hand; it is not an escape hatch for a release.

  Both halves ask before they act: the remirror sends only what the site does not
  already hold, and the upload asks VirusTotal whether it has the hash before it
  sends a byte. So running this again after a bad run does nothing the first run
  already did.

    .\scripts\release\Publish-PostShip.ps1                     after a main release
    .\scripts\release\Publish-PostShip.ps1 -Channel dev        after a dev release
    .\scripts\release\Publish-PostShip.ps1 -Only Remirror      the feed, nothing else

.PARAMETER Channel
  main or dev. main remirrors the Thornswood-Releases tip to
  https://thornswood.net/feed/; dev passes -Dev, which takes the
  Thornswood-Releases-dev tip to https://thornswood.net/feed-dev/.

.PARAMETER Root
  The install the release was built from. Its staging folder is where the
  installer is looked for, and its Launcher folder is where -AlsoLauncher reads
  the shipped exe.

.PARAMETER DistRoot
  Where releases are staged, so the installer is found in the same place
  Package-Thornswood.ps1 built it and Publish-Installer.ps1 published it from.

.PARAMETER Installer
  The file to send instead of the Thornswood-Setup.exe in the staging folder.
  That exe is what the Downloads page offers, so its hash is the one the page
  prints a VirusTotal link for.

.PARAMETER AlsoLauncher
  Sends the shipped launcher exe as well. Off, because the Downloads page lists
  the installer and not the launcher, so no link on it is waiting on a launcher
  report and version.json needs nothing from VirusTotal either. On for the day
  the page offers the launcher on its own.

.PARAMETER Only
  Remirror or VirusTotal, to run that half and not the other. Ship uses it to run
  the two in order with its own headings; a person uses it to redo one half. Left
  out, both run, the feed first.

.PARAMETER NoPause
  Exits without waiting for Enter, so Ship can call this without stopping for a
  keypress nobody is there to give.

.EXAMPLE
  .\scripts\release\Publish-PostShip.ps1 -Channel dev

  Puts the dev tip on thornswood.net/feed-dev and sends the installer this
  machine holds to VirusTotal.

.NOTES
  Exit codes: 0 when the halves asked for are done, or are waiting on a script
  another lane has not landed, and 1 when a half that is here stopped. Ship reads
  that code to say on its last screen which line to run again, and does not fail
  the release over it: a release that is out on the feed, in #news and on the
  server is out.
#>
[CmdletBinding()]
param(
    [ValidateSet('main', 'dev')][string]$Channel = 'main',
    [string]$Root = 'C:\Thornswood',
    [string]$DistRoot = (& (Join-Path $PSScriptRoot 'Where.ps1') Dist),
    [string]$Installer,
    [switch]$AlsoLauncher,
    [ValidateSet('Both', 'Remirror', 'VirusTotal')][string]$Only = 'Both',
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
$trouble = New-Object System.Collections.ArrayList

Write-Host ''
$half = switch ($Only) {
    'Remirror'   { 'THE HOST FEED' }
    'VirusTotal' { 'VIRUSTOTAL' }
    default      { 'THE HOST FEED AND VIRUSTOTAL' }
}
Write-Host "  AFTER THE TIP, $Channel : $half" -ForegroundColor White

# ------------------------------------------------------------ the host feed
if ($Only -eq 'VirusTotal') {
    Say '  the host feed was the call before this one, before anybody was told' 'DarkGray'
}
else {
    Head 'The host feed'
    $remirror = Join-Path $Here '..\deploy\Remirror-Site-Feed.ps1'
    if (-not (Test-Path -LiteralPath $remirror)) {
        # The website lane's script, and nothing here can mirror a feed without
        # it. Said with the path it looked for, so their pull request lands
        # beside this one rather than into a rename.
        Say '  scripts\deploy\Remirror-Site-Feed.ps1 is not on this machine, so the site goes on' 'Yellow'
        Say '  serving the feed it had, and anybody reading it is offered that release.' 'Yellow'
        Say '  It is the website lane''s script, from pull request #730. The release is fine.' 'DarkGray'
        [void]$trouble.Add([pscustomobject]@{
            What     = 'The host feed was not remirrored'
            PutRight = ".\scripts\deploy\Remirror-Site-Feed.ps1$devArg"
        })
    }
    else {
        $where = if ($Dev) { 'https://thornswood.net/feed-dev/' } else { 'https://thornswood.net/feed/' }
        Say "  the $Channel tip to $where" 'DarkGray'
        # The line the website lane asked for, in a try/catch like Ship's own
        # around Publish-News. -Dev:$Dev rather than a switch built up by hand,
        # so main says -Dev:$false and there is one call site rather than two.
        $global:LASTEXITCODE = 0
        $why = ''
        try { & $remirror -Dev:$Dev }
        catch { $why = $_.Exception.Message }
        if ($why) {
            Say "  the remirror stopped: $why" 'Red'
            [void]$trouble.Add([pscustomobject]@{
                What     = 'The host feed was not remirrored'
                PutRight = ".\scripts\deploy\Remirror-Site-Feed.ps1$devArg"
            })
        }
        elseif ($LASTEXITCODE -ne 0) {
            # Its own meaning for a non-zero code: it refused to publish a feed
            # naming bytes the site does not hold. So the site is one release
            # behind, which is what launchers were already reading, rather than
            # pointing at a 404. A line, never a failed release.
            Say "  the remirror refused to publish the feed (exit $LASTEXITCODE). The lines above say which asset." 'Red'
            Say '  The site is one release behind, which is what launchers were already reading.' 'Yellow'
            [void]$trouble.Add([pscustomobject]@{
                What     = 'The host feed was not remirrored'
                PutRight = ".\scripts\deploy\Remirror-Site-Feed.ps1$devArg   and .\scripts\deploy\Remirror-Site-Feed.ps1$devArg -Check to see what it wants first"
            })
        }
    }
}

# ------------------------------------------------------------ VirusTotal
#
# The installer is what the Downloads page offers and the hash it prints a
# VirusTotal link for, so the exe in the staging folder is the file to send.
# Publish-Installer.ps1 calls the same script after it hashes and sends a new
# installer, so this is for every release that did not rebuild one, where what
# the page offers may still have no report. It asks VirusTotal before it sends
# anything, which is why running it on every release, dev included, costs one
# read.
if ($Only -eq 'Remirror') {
    Say '  VirusTotal is the call after this one' 'DarkGray'
}
else {
    Head 'VirusTotal'
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
    $send = @()
    if ($Installer) { $send += $Installer }
    if ($AlsoLauncher) {
        foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
            $p = Join-Path (Join-Path $Root 'Launcher') $n
            if (Test-Path -LiteralPath $p) { $send += $p; break }
        }
    }
    $upload = Join-Path $Here 'Publish-VirusTotal.ps1'
    if (-not $send.Count) {
        Say '  there is no Thornswood-Setup.exe on this machine, so there is nothing to send.' 'Yellow'
        Say '  Whoever built the installer the site is serving runs the upload there:' 'DarkGray'
        Say '  .\scripts\release\Publish-VirusTotal.ps1 -Path <the installer exe>' 'DarkGray'
    }
    elseif (-not (Test-Path -LiteralPath $upload)) {
        Say '  scripts\release\Publish-VirusTotal.ps1 is not on this machine, so the link the' 'Yellow'
        Say '  Downloads page prints stays item-not-found for a file nobody has sent.' 'Yellow'
        Say '  It is the installer lane''s script, from pull request #734. The release is fine.' 'DarkGray'
        [void]$trouble.Add([pscustomobject]@{
            What     = 'VirusTotal was not asked about the installer'
            PutRight = ".\scripts\release\Publish-VirusTotal.ps1 -Path `"$($send[0])`""
        })
    }
    else {
        if ($Dev) { Say '  a dev release did not rebuild the installer, so this is the one on disk' 'DarkGray' }
        foreach ($file in $send) {
            Say "  $file" 'DarkGray'
            # The hash goes with the file. That script measures it itself and
            # says so when the two disagree, which is the check that the file it
            # read is the file this picked and nothing rewrote it in between.
            $sha = ''
            try { $sha = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() } catch { $sha = '' }
            $global:LASTEXITCODE = 0
            $why = ''
            try {
                if ($sha) { & $upload -Path $file -Sha256 $sha }
                else { & $upload -Path $file }
            }
            catch { $why = $_.Exception.Message }
            if ($why) {
                Say "  the upload stopped: $why" 'Red'
                [void]$trouble.Add([pscustomobject]@{
                    What     = 'VirusTotal was not asked about ' + (Split-Path -Leaf $file)
                    PutRight = ".\scripts\release\Publish-VirusTotal.ps1 -Path `"$file`""
                })
            }
            elseif ($LASTEXITCODE -ne 0) {
                # It is written to exit 0 whatever happens, missing key included,
                # so a non-zero code here is something nobody expected.
                Say "  the upload handed back exit $LASTEXITCODE, which it is not written to do." 'Red'
                [void]$trouble.Add([pscustomobject]@{
                    What     = 'VirusTotal was not asked about ' + (Split-Path -Leaf $file)
                    PutRight = ".\scripts\release\Publish-VirusTotal.ps1 -Path `"$file`""
                })
            }
        }
    }
}

Head 'Done'
if (-not $trouble.Count) {
    if ($Only -eq 'Both') { Say "Everything that follows the $Channel tip is done." 'Green' }
    else { Say "This half of what follows the $Channel tip is done." 'Green' }
}
else {
    Say 'The release is out and stays out. What did not happen after it:' 'Yellow'
    foreach ($t in $trouble) {
        Say ("  $($t.What)") 'Red'
        Say ("    $($t.PutRight)") 'Yellow'
    }
    Say '  Each line above asks before it acts, so running it changes nothing else.' 'DarkGray'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
# Said out loud for Ship, which repeats it on its last screen. It is not a failed
# release: a release that is on the feed, in #news and on the server is out.
if ($trouble.Count) { exit 1 }
exit 0
