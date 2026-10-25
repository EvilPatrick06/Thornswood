<#
.SYNOPSIS
  Takes every published note off a channel: the launcher's News tab, the
  site's News page for main, and the record of the channel's Discord posts.

.DESCRIPTION
  Issue #3336. Patrick, 22 Oct 2026: "remove all the posts/messages so we can today start
  clean with all the new rules", the old notes having said things the rules
  written since do not allow. The notes are the channel's feed (Feed-News.ps1:
  "news", or the news file the feed names), so this receives the channel's
  feed from the VPS store, puts an empty list back the way the channel keeps
  its notes, and sends version.json through Feed-Store.ps1 like any other feed
  edit. Every launcher then shows its News tab empty; FeedNews.cs reads the
  new file by its new sha256, so Profile\news.json is not read again.

  For main it then runs Publish-News.ps1 against the feed it just sent, which
  writes the site's data/news.json with no notes in it. scripts\ops\
  news-public.json, the hand-written history Publish-News put under every
  release, is gone from the repository with this, so no Ship puts the old
  notes back on the site.

  The channel's announced.json keeps the lines of every Discord post
  (#3320, "posts-main" or "posts-dev") so a new note cannot say one again.
  Those posts are deleted from Discord with bot\Wipe-Channels.py, so their
  lines are taken out of the record too; the releases it says were announced
  stay, so no release is announced twice.

  It makes no release: no pack, no launcher, no Discord post, no server
  notice. Nothing is posted about it.

    .\scripts\release\Clear-News.ps1 -Channel dev -Check   says what would go, sends nothing
    .\scripts\release\Clear-News.ps1 -Channel dev          takes it off

  Exit 0 when the channel has no notes afterwards (or would, with -Check), 1
  when the feed or the record could not be read or sent.

.PARAMETER Channel
  main or dev.

.PARAMETER Check
  Says what would go and sends nothing.

.PARAMETER Dir
  This machine's working folder for the channel's feed (Feed-Store.ps1), the
  one a Ship uses, unless said otherwise.

.PARAMETER SiteDir
  A folder standing in for the site's root on the VPS, so nothing connects
  anywhere. Tests only, the same as Feed-Store.ps1's. The site's news page is
  then written to <SiteDir>\data\news.json.

.PARAMETER NoPause
  Does not wait for Enter at the end.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('main', 'dev')][string]$Channel,
    [switch]$Check,
    [string]$Dir,
    [string]$SiteUrl = 'https://thornswood.net',
    [string]$SiteDir,
    [switch]$NoPause
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Feed-Store.ps1')
. (Join-Path $Here 'Feed-News.ps1')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Finish([int]$code) {
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit $code
}

Write-Host ''
Write-Host "The $Channel notes, all taken off" -ForegroundColor Cyan
if (-not $Dir) { $Dir = Get-FeedStoreDir $Channel }
$sentFeed = $false
try {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    [void](Receive-FeedStore $Channel $Dir -SiteDir $SiteDir)
    $file = Join-Path $Dir 'version.json'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "The VPS has no version.json for the $Channel channel, so there are no notes." }
    $doc = (([IO.File]::ReadAllText($file)) -replace "^$([char]0xFEFF)", '') | ConvertFrom-Json
    $news = @(Open-FeedNewsList $doc (Get-FeedStoreSiteDir $SiteDir) $SiteUrl)
    foreach ($n in $news) { Say ("  {0} ""{1}"" ({2})" -f $(if ($Check) { 'would take off' } else { 'taking off' }), [string]$n.title, [string]$n.date) 'Yellow' }
    if (-not $news.Count) {
        Say "  the $Channel feed has no notes" 'Green'
    } elseif ($Check) {
        Say "  nothing was sent: -Check" 'DarkGray'
    } else {
        $min = if ($doc.PSObject.Properties['minLauncher'] -and [string]$doc.minLauncher) { [string]$doc.minLauncher } else { [string]$doc.launcherVersion }
        # The site folder a test stands in with, so the news file goes there too.
        [void](Set-FeedNewsList $doc @() $Channel $min (Join-Path $Dir 'news-out') (Get-FeedStoreSiteDir $SiteDir))
        Write-FeedVersionFile $file $doc
        $sent = Send-FeedStore $Channel $Dir @('version.json') -SiteDir $SiteDir
        $sentFeed = $true
        if (@($sent.Sent).Count) { Say "  the $Channel feed's version.json was sent with no notes, and the site serves it" 'Green' }
        else { Say "  the $Channel feed on the VPS already had no notes" 'DarkGray' }
    }
} catch {
    Say "  NOT cleared: $($_.Exception.Message)" 'Red'
    Say '  Nothing was sent. Run this again once that is put right.' 'Yellow'
    Finish 1
}

# The lines of the channel's Discord posts (Note-Repeats.ps1). Everything
# else announced.json holds, the releases already announced, stays.
$said = Join-Path (Split-Path -Parent $Dir) ('announced-' + $Channel)
try {
    New-Item -ItemType Directory -Force -Path $said | Out-Null
    $got = Receive-FeedStore $Channel -Dir $said -Files @('announced.json') -SiteDir $SiteDir
    $f = Join-Path $said 'announced.json'
    $key = 'posts-' + $Channel
    $raw = $null
    if ($got['announced.json'] -and (Test-Path -LiteralPath $f)) { $raw = ([IO.File]::ReadAllText($f) -replace "^$([char]0xFEFF)", '') | ConvertFrom-Json }
    $p = if ($null -ne $raw) { $raw.PSObject.Properties[$key] } else { $null }
    $count = if ($null -ne $p) { @($p.Value | Where-Object { $null -ne $_ }).Count } else { 0 }
    if (-not $count) {
        Say "  the record of the $Channel Discord posts holds no lines" 'Green'
    } elseif ($Check) {
        Say "  would take the lines of $count Discord post(s) out of the record; nothing was sent: -Check" 'Yellow'
    } else {
        $raw.PSObject.Properties.Remove($key)
        [IO.File]::WriteAllText($f, ($raw | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
        [void](Send-FeedStore $Channel -Dir $said -Files @('announced.json') -SiteDir $SiteDir)
        Say "  took the lines of $count Discord post(s) out of the record" 'Green'
    }
} catch {
    Say "  the record of the $Channel Discord posts was NOT cleared: $($_.Exception.Message)" 'Red'
    if ($sentFeed) { Say '  The notes are off the feed already; run this again for the record.' 'Yellow' }
    Finish 1
}

# The site's News page, from the main feed just sent.
if ($Channel -eq 'main' -and -not $Check) {
    $pub = Join-Path $Here '..\ops\Publish-News.ps1'
    try {
        $sd = Get-FeedStoreSiteDir $SiteDir
        if ($sd) {
            New-Item -ItemType Directory -Force -Path (Join-Path $sd 'data') | Out-Null
            & $pub -ReleaseDir $Dir -OutFile (Join-Path $sd 'data\news.json') -Quiet
        } else {
            & $pub -ReleaseDir $Dir -Quiet
        }
        Say '  the site''s News page was written from it' 'Green'
    } catch {
        Say "  the site's News page was NOT written: $($_.Exception.Message)" 'Red'
        Say '  The feed has no notes; .\scripts\ops\Publish-News.ps1 writes the page from it.' 'Yellow'
        Finish 1
    }
}
Finish 0
