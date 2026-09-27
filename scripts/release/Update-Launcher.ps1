<#
.SYNOPSIS
  Checks that the launcher update a release just published is one every
  launcher can actually take, and puts the shipped exe in place on this machine
  when it is not already there.

.DESCRIPTION
  WHAT THIS IS AND WHAT IT IS NOT. Build-Launcher.ps1 compiles the launcher.
  Install-Launcher.ps1 puts a built one into an install, with the shortcut and
  the icon. Neither of them knows whether the release that just went out will
  reach anybody, and that is the half this covers, after the tip is published:

    - the feed a launcher really reads, not the copy in the releases clone on
      this disk, names the version that was just published;
    - launcherUrl is set and answers, and launcherSha256 is a sha256, because
      an empty url offers no update at all and a missing hash refuses the
      download (Updater.cs, and docs\FEED.md under Checks on every download);
    - the install on this machine is running the exe that was shipped, so the
      person who shipped is testing what everybody else has.

  A launcher replaces itself from the feed, so the install here being a build
  behind is a note rather than a refusal: it catches up on its next start. The
  feed not offering the update is a refusal, because then nobody catches up.

  WHY IT IS ITS OWN SCRIPT. Ship.ps1 calls it as one of the three things that
  follow a tip, beside the site mirror and the VirusTotal submission, and it is
  the Launcher half of that: Launcher owns this file. It calls
  Install-Launcher.ps1 rather than copying an exe itself.

    .\scripts\release\Update-Launcher.ps1                    the live channel
    .\scripts\release\Update-Launcher.ps1 -Channel dev       the dev channel
    .\scripts\release\Update-Launcher.ps1 -NoInstall         reads, installs nothing

.PARAMETER Channel
  main or dev, which decides both the releases clone read by default and the
  feed url a launcher on that channel asks first.

.PARAMETER ReleaseDir
  The releases clone whose version.json is the tip. Left out, it is
  Thornswood-Releases beside this repository, or Thornswood-Releases-dev on the
  dev channel, the same pair Ship.ps1 and Publish-Update.ps1 use.

.PARAMETER Root
  The install to check and, when it is behind, to install into.

.PARAMETER From
  The folder the shipped Thornswood.exe came from, which is Ship's build output
  (for a live release, the exe CI built and Ship verified). Passed straight to
  Install-Launcher.ps1. Left out, nothing is installed and a stale install is
  only reported.

.PARAMETER FeedUrl
  The version.json a launcher on this channel reads. Left out, it is the feed's
  own updateFeedUrl, and the site url for the channel when the feed does not
  name one (Feed-Rules.ps1, Get-HostFeedVersionUrl).

.PARAMETER NoInstall
  Reads and reports, and puts nothing in place, whatever -From says.

.PARAMETER NoVerify
  Skips the https reads, so nothing talks to the site or to GitHub. Then this
  only compares the install with the feed on this disk.

.PARAMETER NoPause
  Exits without waiting for Enter, so Ship can call this without stopping for a
  keypress nobody is there to give.

.EXAMPLE
  .\scripts\release\Update-Launcher.ps1 -Channel dev

  Says whether the dev feed offers the launcher it just published, and whether
  the dev install on this machine is running it.

.NOTES
  Exit codes: 0 the update is offered and downloadable, 1 something would stop
  a launcher taking it and the message says what. Ship.ps1 reads that code.

  A rate limited answer from GitHub (403 or 429) is reported and not treated as
  a fault: the feed's fallback urls are release assets on the public releases
  repository and sixty unauthenticated reads an hour is the documented limit,
  not a broken release.
#>
[CmdletBinding()]
param(
    [ValidateSet('main', 'dev')][string]$Channel = 'main',
    [string]$ReleaseDir,
    [string]$Root = 'C:\Thornswood',
    [string]$From,
    [string]$FeedUrl,
    [switch]$NoInstall,
    [switch]$NoVerify,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Feed-Rules.ps1')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) {
    Write-Host ''
    Write-Host "STOP. $m" -ForegroundColor Red
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
    exit 1
}

# Both names, newest first: an install made before the rename still carries
# SkyrimTogether.exe, because the launcher replaces itself in place.
function Get-LauncherExe([string]$dir) {
    foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return ''
}

$Dev = ($Channel -eq 'dev')

Head 'Thornswood - the launcher update'

# ------------------------------------------------------------ the tip
if (-not $ReleaseDir) {
    $repoDir = Split-Path -Parent (Split-Path -Parent $Here)
    $beside = Split-Path -Parent $repoDir
    $ReleaseDir = Join-Path $beside $(if ($Dev) { 'Thornswood-Releases-dev' } else { 'Thornswood-Releases' })
}
$versionFile = Join-Path $ReleaseDir 'version.json'
if (-not (Test-Path -LiteralPath $versionFile)) {
    Die "There is no version.json in $ReleaseDir, so there is no release to check. Point -ReleaseDir at the releases clone for this channel."
}
$doc = ((Get-Content -LiteralPath $versionFile -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json

function Val($o, [string]$k) {
    if ($null -ne $o -and $o.PSObject.Properties[$k]) { return [string]$o.$k }
    return ''
}
$tip = Val $doc 'launcherVersion'
$url = Val $doc 'launcherUrl'
$sha = (Val $doc 'launcherSha256').ToLowerInvariant()
Say "  $Channel tip: launcher $tip" 'DarkGray'

if (-not $tip) { Die "version.json in $ReleaseDir has no launcherVersion, so no launcher is offered to anybody. Nothing here can put that right." }
if (-not $url) {
    Die ("version.json names launcher $tip and has no launcherUrl, so every launcher reads the new number and is offered nothing " +
         '(Shell.cs holds the offer back without a url). Publish the launcher again.')
}
if ($sha -notmatch '^[a-f0-9]{64}$') {
    Die ("launcherSha256 is not a sha256, so every launcher refuses the download before it starts (Updater.Download). " +
         'Publish the launcher again.')
}
Say '  the feed on this disk names a launcher, a url and a sha256' 'Green'

# ------------------------------------------------- the install on this machine
Head 'This machine'
$launchDir = Join-Path $Root 'Launcher'
$exe = Get-LauncherExe $launchDir
$installed = ''
if ($exe) {
    try { $installed = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() } catch { $installed = '' }
}
if (-not $exe) {
    Say "  there is no launcher in $launchDir" 'Yellow'
} elseif ($installed -eq $sha) {
    Say "  $exe is the exe this release published" 'Green'
} else {
    Say "  $exe is not the exe this release published" 'Yellow'
    if ($NoInstall) {
        Say '  -NoInstall, so it was left alone. It updates itself from the feed on its next start.' 'DarkGray'
    } elseif (-not $From) {
        Say '  nothing was given to install (-From), so it was left alone.' 'DarkGray'
        Say '  It updates itself from the feed on its next start.' 'DarkGray'
    } else {
        $built = Join-Path $From 'Thornswood.exe'
        if (-not (Test-Path -LiteralPath $built)) {
            Say "  and there is no Thornswood.exe in $From to put there either." 'Yellow'
        } else {
            $fromSha = (Get-FileHash -LiteralPath $built -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($fromSha -ne $sha) {
                Say "  and the exe in $From is not the one on the feed either, so it was left alone." 'Yellow'
                Say '  That is normal after a dev build, whose exe carries a version the main feed never had.' 'DarkGray'
            } else {
                Say "  putting the shipped exe in place from $From" 'DarkGray'
                $global:LASTEXITCODE = 0
                & (Join-Path $Here 'Install-Launcher.ps1') -Root $Root -From $From -NoPause
                if ($LASTEXITCODE -ne 0) {
                    Die ("Install-Launcher.ps1 stopped with exit code $LASTEXITCODE, so this machine is not running what was shipped. " +
                         'The release itself is published and is fine. The errors are above.')
                }
                Say '  in place' 'Green'
            }
        }
    }
}

# --------------------------------------------- the feed a launcher really reads
if ($NoVerify) {
    Head 'Done'
    Say '-NoVerify, so nothing read the feed a launcher actually asks.' 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

Head 'The feed a launcher reads'
if (-not $FeedUrl) {
    $FeedUrl = Val $doc 'updateFeedUrl'
    if (-not $FeedUrl) { $FeedUrl = Get-HostFeedVersionUrl -Dev:$Dev }
}
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$liveTip = ''
$liveUrl = ''
try {
    $answer = Invoke-WebRequest -Uri $FeedUrl -UseBasicParsing -TimeoutSec 30
    $liveDoc = ([string]$answer.Content -replace '^\uFEFF', '') | ConvertFrom-Json
    $liveTip = Val $liveDoc 'launcherVersion'
    $liveUrl = Val $liveDoc 'launcherUrl'
} catch {
    Die ("$FeedUrl could not be read: " + $_.Exception.Message + " Until it answers, a launcher on the $Channel channel falls back to the " +
         'GitHub feed, which may be older. Mirror the feed with .\scripts\release\Publish-SiteFeed.ps1' +
         $(if ($Dev) { ' -Channel dev' } else { '' }) + ' and run this again.')
}
if ($liveTip -ne $tip) {
    Die ("$FeedUrl says launcher $liveTip, not $tip, so nobody is offered this release. The mirror is what puts that right: " +
         '.\scripts\release\Publish-SiteFeed.ps1' + $(if ($Dev) { ' -Channel dev' } else { '' }) + ', then run this again.')
}
Say "  $FeedUrl offers launcher $liveTip" 'Green'
if (-not $liveUrl) {
    Die "$FeedUrl names launcher $liveTip and no launcherUrl, so the update is read and never offered. Publish the launcher again."
}

# Does the download answer. A 403 or 429 from GitHub is its unauthenticated
# rate limit and says nothing about the asset (docs\FEED.md), so it is reported
# rather than treated as a broken release.
$code = 0
$why = ''
try {
    $head = Invoke-WebRequest -Uri $liveUrl -Method Head -UseBasicParsing -TimeoutSec 30
    $code = [int]$head.StatusCode
} catch {
    $why = $_.Exception.Message
    try { $code = [int]$_.Exception.Response.StatusCode } catch { $code = 0 }
}
if ($code -eq 200) {
    Say '  and the launcher download answers 200' 'Green'
} elseif ($code -eq 403 -or $code -eq 429) {
    Say "  the launcher download answered $code, which is GitHub's rate limit for reads with no token." 'Yellow'
    Say '  That is not this release: try it again in a few minutes if you want it proved.' 'DarkGray'
} else {
    Die ("the launcher download, $liveUrl, answered " + $(if ($code) { $code } else { 'nothing: ' + $why }) +
         '. Every launcher that takes this release would fail at the download. Publish the launcher again, or mirror the feed asset with ' +
         '.\scripts\release\Publish-SiteFeed.ps1' + $(if ($Dev) { ' -Channel dev' } else { '' }) + '.')
}

Head 'Done'
Say "Launcher $tip is offered on the $Channel channel and downloads." 'Green'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
# Said out loud: Install-Launcher.ps1 and the web reads leave their own exit
# codes behind, and Ship.ps1 reads this one.
exit 0
