<#
.SYNOPSIS
  Marks the dev feed's notes DEV again against what main has published, and
  sets its mainVersion, with no release.

.DESCRIPTION
  The dev launcher's News tab marks a note DEV when the dev build has it and
  main does not. Until 6 Oct those marks moved only on a dev Ship that
  released something, so after every main release the tab showed finished
  work as DEV until somebody shipped dev again; on 5 Oct that was done with a
  dev Ship made for nothing else ("Dev and main match again"). Measured on
  6 Oct at about 11 AM: 27 of the dev feed's 40 notes marked DEV and
  mainVersion 1.1.106, with main on 1.2.0.

  This receives the dev feed from the VPS store, reads main's feed as the site
  serves it, works every note's mark out by the rule a dev publish uses
  (Update-DevNewsChannels in Dev-News.ps1), and sends version.json back
  through Feed-Store.ps1 only when a mark or mainVersion moved. It makes no
  release: no pack, no launcher, no baseline, no Discord post, no server
  notice.

  Ship runs it after every main release, and a dev publish with nothing new
  does the same work itself. Run by hand when the marks are behind for any
  other reason, from a clone that has main's release commit (git fetch first),
  because a note's mark is proved by git.

    .\scripts\release\Refresh-DevNews.ps1 -Check    says what would move, sends nothing
    .\scripts\release\Refresh-DevNews.ps1           moves it

  Exit 0 when the dev feed matches main afterwards (or would, with -Check),
  1 when nothing could be sent: the dev feed or main's feed could not be read,
  or the dev feed changed on the VPS while this ran.

.PARAMETER Check
  Works it out and says what would move. Receives the dev feed into this
  machine's working folder for dev, as a dev Ship does, and sends nothing.

.PARAMETER RepoDir
  The clone whose git history proves which notes main has. The repository this
  script is in unless said otherwise.

.PARAMETER Dir
  This machine's working folder for the dev feed. %LOCALAPPDATA%\Thornswood\feed\dev,
  the one a dev Ship uses (Feed-Store.ps1), unless said otherwise.

.PARAMETER SiteUrl
  Where main's feed is read from. https://thornswood.net unless a test says otherwise.

.PARAMETER SiteDir
  A folder standing in for the site's root on the VPS, so nothing connects
  anywhere. Tests only, the same as Feed-Store.ps1's.

.PARAMETER NoPause
  Does not wait for Enter at the end. Ship passes it.
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$RepoDir,
    [string]$Dir,
    [string]$SiteUrl = 'https://thornswood.net',
    [string]$SiteDir,
    [switch]$NoPause
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RepoDir) { $RepoDir = Split-Path -Parent (Split-Path -Parent $Here) }
. (Join-Path $Here 'Dev-News.ps1')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Finish([int]$code) {
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit $code
}

Write-Host ''
Write-Host "The dev feed's DEV marks" -ForegroundColor Cyan
if (-not $Dir) { $Dir = Get-FeedStoreDir 'dev' }
try {
    $r = Update-DevFeedMarks -SourceRepo $RepoDir -Dir $Dir -NoSend:$Check -SiteDir $SiteDir -SiteUrl $SiteUrl
} catch {
    Say "  NOT refreshed: $($_.Exception.Message)" 'Red'
    Say '  Nothing was sent. Run this again once that is put right.' 'Yellow'
    Finish 1
}
foreach ($l in @(Get-DevFeedMarksLines $r -NoSend:$Check)) { Say "  $l" $(if ($r.Changed -and -not $Check) { 'Green' } else { 'DarkGray' }) }
if (@($r.Kept).Count) { Say ("  still DEV, main does not have them: " + (@($r.Kept) -join '; ')) 'DarkGray' }
Finish 0
