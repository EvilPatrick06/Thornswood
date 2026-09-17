<#
  Publish-News.ps1

  Copies the launcher's news feed onto the docs site, so the News page there is
  the same list of changes people see in the launcher rather than a second one
  written by hand that immediately falls behind.

  version.json is not sent as it stands, because it also carries the server
  password and the update repository. Only the news entries and the version
  number go, into data/news.json.

    .\Publish-News.ps1

  Called by Ship.ps1 at the end of every release, so it is usually not run on
  its own.

  It goes over as a FILE, not as a command. The feed is the best part of a
  hundred kilobytes and Windows will not take a command line longer than 32767
  characters, which is what two earlier versions of this script kept walking
  into from different directions.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Root = 'C:/Thornswood-Docs',
  # Short on purpose. A public news page is the last handful of releases, not
  # an archive of every build.
  [int]$Keep    = 12,
  # Where the LIVE version.json is. Releases moved into their own public repo,
  # and the copy still sitting in this repo stopped being updated the day that
  # happened. Reading the stale one is why a run right after shipping 1.0.198
  # announced launcher 1.0.196 to the world.
  [string]$ReleaseDir = 'C:\Users\evilp\Downloads\Thornswood-Releases',
  # Everything before this date is development history and stays off the site.
  # Read from tools\news-from.txt when not given, so it is one line to change.
  [string]$From,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

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
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

if (-not $From) {
  $cut = Join-Path $Here 'news-from.txt'
  if (Test-Path -LiteralPath $cut) { $From = (Get-Content $cut -Raw).Trim() }
}

$repoV = Join-Path (Split-Path -Parent $Here) 'version.json'
$liveV = Join-Path $ReleaseDir 'version.json'

$vf = $null
if (Test-Path -LiteralPath $liveV) { $vf = $liveV }
elseif (Test-Path -LiteralPath $repoV) {
  $vf = $repoV
  Write-Host "  no version.json in $ReleaseDir, falling back to the copy in this repo." -ForegroundColor Yellow
  Write-Host "  That one is stale, so the version below may be wrong." -ForegroundColor Yellow
} else {
  throw "No version.json in either $ReleaseDir or $repoV."
}

# A byte order mark is not JSON. ConvertFrom-Json stops on the first character
# and says something unhelpful about an unexpected token.
$v = ((Get-Content $vf -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json
$all = @()
if ($v.news) { $all = @($v.news) }

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
  '[\\/](SKSE|Data|tools)[\\/]'         # anything that is a path
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

  $news += [ordered]@{
    date    = (Prop $n 'date')
    title   = $title
    body    = (Prop $n 'body')
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

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-news-' + [Guid]::NewGuid().ToString('N') + '.json')
try {
  # No BOM. node reads this with JSON.parse and a byte order mark makes that
  # fail on the first character for reasons nobody enjoys finding out.
  [IO.File]::WriteAllText($tmp, $payload, (New-Object Text.UTF8Encoding $false))

  & scp @ssh $tmp "$User@${Vps}:$Root/data/news.json"
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
