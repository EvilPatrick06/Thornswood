<#
.SYNOPSIS
  Takes out of a channel's published notes every line an older note already
  said, so the News tab and the site list each change once.

.DESCRIPTION
  Issue #3320. Ship.ps1 and Deploy-DevGamemode.ps1 refuse a note that says
  again what the channel has been told (Note-Repeats.ps1), from 22 Oct 2026.
  The notes that went out before that still carry their repeats: measured
  that day, the dev feed's 7:08 AM "A new launcher" said again two lines of
  the 6:32 AM "Clearer launcher messages and a visible axe".

  This receives the channel's feed from the VPS store, reads every note
  (Feed-News.ps1), goes through them oldest first, and takes out of each one
  the "- " lines an older note already had: the same comparison the check
  makes. A note keeps its title, and the lines the publisher writes itself
  (a launcher number, the download size, the load order warning) are facts
  about each release and stay. When something moved, the notes go back the
  way the channel keeps them and version.json is sent through Feed-Store.ps1
  like any other feed edit. It makes no release: no pack, no launcher, no
  Discord post, no server notice. Discord posts are not changed; the check
  keeps new ones from repeating.

    .\scripts\release\Clean-NewsRepeats.ps1 -Channel dev -Check   says what would go, sends nothing
    .\scripts\release\Clean-NewsRepeats.ps1 -Channel dev          takes it out

  Exit 0 when the channel's notes repeat nothing afterwards (or would, with
  -Check), 1 when the feed could not be read or sent.

.PARAMETER Channel
  main or dev.

.PARAMETER Check
  Says what would go and sends nothing.

.PARAMETER Dir
  This machine's working folder for the channel's feed (Feed-Store.ps1), the
  one a Ship uses, unless said otherwise.

.PARAMETER SiteDir
  A folder standing in for the site's root on the VPS, so nothing connects
  anywhere. Tests only, the same as Feed-Store.ps1's.

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
. (Join-Path $Here 'Note-Repeats.ps1')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Finish([int]$code) {
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit $code
}

# Every note, newest first, with the lines an older note already had taken
# out of it. Returns what went, one line each; changes the notes in place.
function Remove-NoteRepeats($News) {
    $gone = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $list = @($News)
    for ($i = $list.Count - 1; $i -ge 0; $i--) {
        $n = $list[$i]
        if ($null -eq $n -or -not $n.PSObject.Properties['details']) { continue }
        $keep = @()
        foreach ($d in @($n.details)) {
            $k = ConvertTo-NoteRepeatKey ([string]$d)
            if ($k.Length -ge 8 -and -not (Test-NoteRepeatNoise $k) -and $seen.Contains($k)) {
                $gone += ('"{0}" from "{1}" ({2})' -f [string]$d, [string]$n.title, [string]$n.date)
                continue
            }
            $keep += $d
        }
        foreach ($d in $keep) { [void]$seen.Add((ConvertTo-NoteRepeatKey ([string]$d))) }
        if (@($keep).Count -ne @($n.details).Count) { $n.details = @($keep) }
    }
    return $gone
}

Write-Host ''
Write-Host "The $Channel notes, each change said once" -ForegroundColor Cyan
if (-not $Dir) { $Dir = Get-FeedStoreDir $Channel }
try {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    [void](Receive-FeedStore $Channel $Dir -SiteDir $SiteDir)
    $file = Join-Path $Dir 'version.json'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "The VPS has no version.json for the $Channel channel, so there are no notes." }
    $doc = (([IO.File]::ReadAllText($file)) -replace '^﻿', '') | ConvertFrom-Json
    $news = @(Open-FeedNewsList $doc (Get-FeedStoreSiteDir $SiteDir) $SiteUrl)
    $gone = @(Remove-NoteRepeats $news)
    foreach ($g in $gone) { Say "  $(if ($Check) { 'would take out' } else { 'took out' }) $g" 'Yellow' }
    if (-not $gone.Count) { Say "  none of the $($news.Count) notes repeats an older one, so nothing was sent" 'Green'; Finish 0 }
    if ($Check) { Say "  nothing was sent: -Check" 'DarkGray'; Finish 0 }
    $min = if ($doc.PSObject.Properties['minLauncher'] -and [string]$doc.minLauncher) { [string]$doc.minLauncher } else { [string]$doc.launcherVersion }
    [void](Set-FeedNewsList $doc $news $Channel $min (Join-Path $Dir 'news-out') $SiteDir)
    Write-FeedVersionFile $file $doc
    $sent = Send-FeedStore $Channel $Dir @('version.json') -SiteDir $SiteDir
    if (@($sent.Sent).Count) { Say "  the $Channel feed's version.json was sent, and the site serves it" 'Green' }
    else { Say "  the $Channel feed on the VPS already had these notes" 'DarkGray' }
} catch {
    Say "  NOT cleaned: $($_.Exception.Message)" 'Red'
    Say '  Nothing was sent. Run this again once that is put right.' 'Yellow'
    Finish 1
}
Finish 0
