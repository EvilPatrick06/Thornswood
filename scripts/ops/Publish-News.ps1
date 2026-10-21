<#
  Publish-News.ps1

  Copies the launcher's news feed onto the docs site, so the News page there is
  the same list of changes people see in the launcher rather than a second one
  written by hand that immediately falls behind.

  version.json is not sent as it stands, because it also carries the update
  repository and the pack list. Only the news entries and the version number
  go, into data/news.json. (The server password used to ride in it too;
  Publish-Update.ps1 takes it out of version.json now.)

    .\Publish-News.ps1
    .\Publish-News.ps1 -OutFile news.json    writes the page here, sends nothing

  Called by Ship.ps1 at the end of every release, so it is usually not run on
  its own.

  It goes over as a FILE, not as a command. The feed is the best part of a
  hundred kilobytes and Windows will not take a command line longer than 32767
  characters, which is what two earlier versions of this script kept walking
  into from different directions.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '',
  [string]$User = '',
  [string]$Root = 'C:/Thornswood-Docs',
  # Short on purpose. A public news page is the last handful of releases, not
  # an archive of every build.
  [int]$Keep    = 12,
  # Where the LIVE version.json is. Releases moved into their own public repo,
  # and the copy still sitting in this repo stopped being updated the day that
  # happened. Reading the stale one is why a run right after shipping 1.0.198
  # announced launcher 1.0.196 to the world. Since #907 it is this machine's
  # working copy of the live feed, which the Ship that runs this has just
  # received from the VPS and sent back (Feed-Store.ps1).
  [string]$ReleaseDir = (& (Join-Path $PSScriptRoot '..\release\Where.ps1') Releases),
  # Everything before this date is development history and stays off the site.
  # Read from scripts\ops\news-from.txt when not given, so it is one line to change.
  [string]$From,
  # Writes the page to this file and sends nothing. The filters below are the
  # whole point of this script, and until this there was no way to read what
  # they leave without publishing it to the site.
  [string]$OutFile,
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'   # before any file loads, so one that is missing stops here (#3006)
. (Join-Path $PSScriptRoot '..\release\Read-JsonFile.ps1')   # ConvertFrom-ThornswoodJson: a bad JSON file named

# ConvertFrom-Json gives back an object with only the properties the file
# actually had. Reaching for one that is not there throws under strict mode,
# which is what quietly stopped the whole hand written history from ever
# reaching the site: news-public.json has date, title and details, and no
# body, so the first entry killed the loop and the catch swallowed it.
# These two read a property that may simply not exist.
function Prop($obj, $name) {
  if ($null -eq $obj) { return '' }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return '' }
  return [string]$p.Value
}
# PowerShell unrolls a collection on the way out of a function, so a one item
# list came back from PropList as a bare string. ConvertTo-Json then wrote it as
# a string, the site called .map on it, and the whole news page said it could
# not load. Every call site wraps this in @() for that reason. Do not take them
# off.
function PropList($obj, $name) {
  if ($null -eq $obj) { return @() }
  $p = $obj.PSObject.Properties[$name]
  if ($null -eq $p) { return @() }
  return @($p.Value)
}
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=yes')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
if (-not $User) { $User = Get-ThornswoodVpsUser }
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }

if (-not $From) {
  $cut = Join-Path $Here 'news-from.txt'
  # "$()": an empty file reads as $null (even through [string](...)), and a method on $null throws.
  if (Test-Path -LiteralPath $cut) { $From = ("$(Get-Content $cut -Raw)").Trim() }
}

# The live feed only. This repository's own version.json was a copy left from
# before releases had a repository of their own, frozen at launcher 1.0.196,
# and it was deleted on 25 September rather than fallen back to.
$vf = Join-Path $ReleaseDir 'version.json'
if (-not (Test-Path -LiteralPath $vf)) {
  throw "No version.json in $ReleaseDir. A Ship or feed edit on this machine receives the live feed there; or pass -ReleaseDir."
}

# A byte order mark is not JSON. ConvertFrom-Json stops on the first character
# and says something unhelpful about an unexpected token.
$v = ConvertFrom-ThornswoodJson (Get-Content $vf -Raw) $vf
# Every note, wherever the feed keeps them: "news", and the news file it names
# once every launcher it lets in reads one (Feed-News.ps1, #1050), read from the
# site and checked against its sha256. $env:THORNSWOOD_TEST_SITE_DIR stands in
# for the site in the tests.
. (Join-Path $PSScriptRoot '..\release\Feed-News.ps1')
$all = @(Get-FeedNewsList $v $env:THORNSWOOD_TEST_SITE_DIR)

# --------------------------------------------------------------- cleaning --
#
# The launcher's feed is a developer's changelog and reads like one: forty
# entries of "Server updated", half of them the same sentence twice, and file
# lists full of SKSE ini paths. That is the right thing for somebody who
# already plays and the wrong thing entirely for somebody deciding whether to
# install, so the public copy is cut down on the way out.
#
# Nothing is rewritten here. Anything that needs different words needs them
# typing into Ship.ps1, because that title is what the world reads now.

# Lines that mean something to you and nothing to anyone else.
$noise = @(
  '^\s*Launcher rebuilt\s*:',          # which .cs files changed
  '^\s*Launcher \d+\.\d+',            # the version, already shown
  'files? to download',                  # the size, which the launcher shows
  '[\\/](SKSE|Data|tools)[\\/]',        # anything that is a path
  # Entry 187: the public feed showed strangers "Load order: 60 plugins server
  # side". Publish-Server wrote that and the line below into every server
  # entry. It does not any more, and these take out the ones already written.
  # Anchored at the start, so "The load order moved, so start a new character"
  # still goes out, because that one is for the person reading it.
  '^\s*Load order\s*:',
  '^\s*The gamemode was rebuilt\b'
)
$dull = @('^server updated\.?$', '^no corner box\.?$', '^fixes?\.?$', '^wip\.?$')

# Whether two titles are the same release.
#
# This was a prefix: the first 34 letters of the title with the punctuation
# taken out. Two things went wrong with that. Shipping 1.1 under the title the
# hand written entry already used put the release on the page twice, Ship's
# copy of it being a title and nothing else. And "Add-ons tab, optional packs,
# Discord sign in returns to the panel" and "Add-ons tab, optional packs, sign
# in returns to the panel" are the same release written twice in one afternoon,
# but they part company on the word Discord, in the middle, so a prefix of any
# length either catches both or neither.
#
# Counting shared words catches both shapes. Ten words out of eleven is the
# same release however they are arranged.
function Words($title) {
  $t = ([string]$title).ToLower() -replace '[^a-z0-9 ]', ' '
  return @(@($t -split '\s+') | Where-Object { $_ } | Sort-Object -Unique)
}
function SameRelease($a, $b) {
  $wa = @(Words $a); $wb = @(Words $b)
  if ($wa.Count -eq 0 -or $wb.Count -eq 0) { return $false }
  $set = @{}
  foreach ($w in $wb) { $set[$w] = $true }
  $hit = 0
  foreach ($w in $wa) { if ($set.ContainsKey($w)) { $hit++ } }
  $union = $wa.Count + $wb.Count - $hit
  if ($union -le 0) { return $false }
  return ((($hit / $union)) -ge 0.7)
}
# The index of the entry already holding this release, or -1.
function SameIndex($list, $title) {
  for ($i = 0; $i -lt @($list).Count; $i++) {
    if (SameRelease (@($list)[$i].title) $title) { return $i }
  }
  return -1
}

$news = @()
foreach ($n in $all) {
  $title = ([string]$n.title).Trim()
  if (-not $title) { continue }

  # A date before the cutoff is development history, not news.
  #
  # Parsed in a try rather than with TryParse, because TryParse wants a [ref]
  # to something already typed as a date and PowerShell will not bind one to a
  # null. An unparseable date is kept, on the grounds that dropping an entry
  # because its date was odd is worse than showing it.
  if ($From) {
    $d = $null
    try { $d = [datetime]::Parse([string]$n.date) } catch { $d = $null }
    if ($d -and $d -lt [datetime]::Parse($From)) { continue }
  }

  if ($dull | Where-Object { $title -match $_ }) { continue }

  # Six near identical titles in one afternoon is one entry to a reader. The
  # newest wins, because it is the one that actually shipped.
  if ((SameIndex $news $title) -ge 0) { continue }

  $details = @()
  foreach ($d2 in (PropList $n 'details')) {
    $line = [string]$d2
    if (-not $line.Trim()) { continue }
    if ($noise | Where-Object { $line -match $_ }) { continue }
    $details += $line
  }

  # Publish-Server filled an empty body with "The server at" its address "was
  # reinstalled and is answering", which is a note to whoever ran it and put
  # the VPS address on the public page. It does not any more; this takes out
  # the ones already in the feed.
  $body = Prop $n 'body'
  if ($body -match '^\s*The server at \S+ was reinstalled and is answering\.?\s*$') { $body = '' }

  $news += [ordered]@{
    date    = (Prop $n 'date')
    title   = $title
    body    = $body
    details = @($details)
    # The file list never goes. It is a hundred lines of paths and it is the
    # single ugliest thing that could be on a public page.
  }
  if ($news.Count -ge $Keep) { break }
}

# --------------------------------------------------------------- the past --
#
# Everything before the cutoff was written as a changelog for one person and
# reads like one, so filtering it was never going to work: the words needed
# changing, not choosing between. news-public.json is that history rewritten by
# hand, and it goes underneath whatever has shipped since.
$oldFile = Join-Path $Here 'news-public.json'
if (Test-Path -LiteralPath $oldFile) {
  try {
    # Same byte order mark trap as above. This is the likeliest reason this file
    # has been quietly skipped on every run: it is here, it looks fine in an
    # editor, and ConvertFrom-Json refuses the first character.
    $raw = (Get-Content $oldFile -Raw) -replace '^\uFEFF', ''
    $curated = $raw | ConvertFrom-Json
    $added = 0
    $swapped = 0
    foreach ($c in @($curated)) {
      $ct = (Prop $c 'title')
      $entry = [ordered]@{
        date    = (Prop $c 'date')
        title   = $ct
        body    = (Prop $c 'body')
        details = @(PropList $c 'details')
      }
      $i = SameIndex $news $ct
      if ($i -ge 0) {
        # Ship writes a release as a title and whatever it can work out. The
        # copy in here was written for people to read, so when they are the
        # same release the written one wins and takes its place in the order.
        if (@($entry.details).Count -gt @(@($news)[$i].details).Count) {
          $news[$i] = $entry
          $swapped++
        }
        continue
      }
      $news += $entry
      $added++
    }
    if (-not $Quiet) {
      Write-Host ("  news-public.json added $added older entr" + $(if ($added -eq 1) { 'y' } else { 'ies' })) -ForegroundColor DarkGray
      if ($swapped) {
        Write-Host ("  and replaced $swapped entr" + $(if ($swapped -eq 1) { 'y' } else { 'ies' }) + " that shipped with only a title") -ForegroundColor DarkGray
      }
    }
  } catch {
    # Saying "skipping it" and nothing else meant this went unnoticed for weeks.
    Write-Host ''
    Write-Host "  news-public.json is there but could not be read:" -ForegroundColor Red
    Write-Host ("    " + $_.Exception.Message) -ForegroundColor Red
    Write-Host "  The hand written history is NOT on the site. Fix the file and run this again." -ForegroundColor Yellow
    Write-Host ''
  }
} else {
  Write-Host "  no news-public.json next to this script, so no older history is published." -ForegroundColor DarkGray
}

# The collection address rides along because the downloads page has to link
# it and version.json is the only place it is ever set. Hardcoding it on the
# site would mean two copies and one of them going stale.
$collection = ''
try { if ($v.PSObject.Properties['collectionUrl']) { $collection = [string]$v.collectionUrl } } catch { }

$payload = [ordered]@{
  launcher   = $v.launcherVersion
  collection = $collection
  at         = (Get-Date).ToString('o')
  news       = $news
} | ConvertTo-Json -Depth 8

if ($OutFile) {
  # Resolved against where PowerShell is standing. .NET has its own current
  # folder, which is wherever the process started, and a relative name handed
  # straight to WriteAllText lands there.
  $OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
  [IO.File]::WriteAllText($OutFile, $payload, (New-Object Text.UTF8Encoding $false))
  if (-not $Quiet) { Write-Host ("  news written to {0}, {1} entries, nothing sent" -f $OutFile, @($news).Count) }
  return
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-news-' + [Guid]::NewGuid().ToString('N') + '.json')
try {
  # No BOM. node reads this with JSON.parse and a byte order mark makes that
  # fail on the first character for reasons nobody enjoys finding out.
  [IO.File]::WriteAllText($tmp, $payload, (New-Object Text.UTF8Encoding $false))

  Invoke-ThornswoodNative { & scp @ssh $tmp "$User@${Vps}:$Root/data/news.json" }
  if ($LASTEXITCODE -ne 0) { throw 'scp failed' }

  if (-not $Quiet) {
    $n = @($news).Count
    if ($n -eq 0) {
      Write-Host "  PUBLISHED AN EMPTY NEWS PAGE. Nothing survived the filters above." -ForegroundColor Red
      Write-Host "  Visitors see a blank News page until this is sorted." -ForegroundColor Yellow
    } else {
      Write-Host ("  news published, {0} entries, launcher {1}" -f $n, $v.launcherVersion)
    }
  }
} finally {
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
