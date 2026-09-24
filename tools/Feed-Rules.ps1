<#
  Feed-Rules.ps1

  Which packs on the update feed a launcher can actually download.
  Publish-Update.ps1 dot-sources this and refuses to add a pack that breaks the
  rule; Repair-Manifest.ps1 dot-sources it and takes the ones already on the
  feed back out. One rule, so the two can never disagree about it.

  THE RULE. A launcher reads version.json from the repository the feed names as
  updateRepo, with no token on it, and downloads every pack from the url the
  feed gives. So a pack has to be a release asset in that same repository.
  Anything else answers 404 to a launcher, and a pack that will not download
  stops the update, and Play stays off (Shell.cs skips a pack with NO url, but
  one whose url answers 404 fails the whole update).

  WHY IT EXISTS. Read off the releases clone on 24 September: 227 packs on the
  live feed, 164 of them (20260910-2345 to 20260914-1917) under
  /repos/EvilPatrick06/Thornswood/, the source repository, and 63 under
  Thornswood-Releases. The source repository is private and has no releases
  left at all: gh api answers 0 releases, and asset 556583849, the first of
  them, answers 404 even with Patrick's token. They were published there before
  releases moved to the public repository on 15 September, and the new feed was
  seeded from the old one with all 164 still on it. Fresh installs never notice
  because Package-Thornswood.ps1 seeds applied.txt with every id on the feed.
  A machine that loses applied.txt, or anything that replays the history, asks
  for all 164, the first one fails, and Play stays off.

  Only GitHub release assets pass. A pack served from anywhere else, even a
  host Updater.cs allows, fails on purpose: whoever moves packs off GitHub
  changes this rule in the same commit.

      . (Join-Path $PSScriptRoot 'Feed-Rules.ps1')
      Get-FeedRepo $doc              owner/name launchers read this feed from
      Get-FeedPackRepo $url          owner/name a pack url downloads from, or ''
      Test-FeedPackUrl $url $repo    true when a launcher can download it
      Split-FeedPacks $packs $repo   .Keep and .Drop, in feed order, each drop with .Why
#>

# The repository every launcher reads this feed from. The feed names it as
# updateRepo (Publish-Update.ps1 writes that from config.json); a feed too old
# to name one is read from the repository Config.cs gives a fresh install.
function Get-FeedRepo($doc) {
    if ($null -ne $doc -and $doc.PSObject.Properties['updateRepo']) {
        $r = ([string]$doc.updateRepo).Trim()
        if ($r -match '^[^/\s]+/[^/\s]+$') { return $r }
    }
    return 'EvilPatrick06/Thornswood-Releases'
}

# The repository a pack url downloads from, as owner/name, or '' when the url
# is not a GitHub release asset at all. Two shapes are: the API address
# Publish-Update writes, and the browser address GitHub serves the same asset
# from. Anchored at both ends, so a longer name that starts the same, or a
# query string that mentions the right one, does not pass.
function Get-FeedPackRepo([string]$url) {
    if (-not $url) { return '' }
    $u = $url.Trim()
    $m = [regex]::Match($u, '^https://api\.github\.com/repos/([^/?#\s]+/[^/?#\s]+)/releases/assets/\d+$', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    $m = [regex]::Match($u, '^https://github\.com/([^/?#\s]+/[^/?#\s]+)/releases/download/[^/?#\s]+/[^/?#\s]+$', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

# GitHub names are not case sensitive, so neither is this.
function Test-FeedPackUrl([string]$url, [string]$repo) {
    $r = Get-FeedPackRepo $url
    if (-not $r -or -not $repo) { return $false }
    return [string]::Equals($r, $repo.Trim(), [StringComparison]::OrdinalIgnoreCase)
}

# Every pack on a feed, split into the ones a launcher can download and the
# ones it cannot. Feed order is kept on both sides, because the launcher
# applies packs in the order the feed lists them. Each dropped one says why.
# A null entry is on neither side: there is nothing to download and nothing to
# name.
function Split-FeedPacks($packs, [string]$repo) {
    $keep = New-Object System.Collections.ArrayList
    $drop = New-Object System.Collections.ArrayList
    foreach ($p in @($packs)) {
        if ($null -eq $p) { continue }
        $url = ''
        if ($p.PSObject.Properties['url'] -and $p.url) { $url = ([string]$p.url).Trim() }
        if (-not $url) {
            [void]$drop.Add([pscustomobject]@{ Pack = $p; Repo = ''; Why = 'published with no url' })
            continue
        }
        if (Test-FeedPackUrl $url $repo) { [void]$keep.Add($p); continue }
        $r = Get-FeedPackRepo $url
        $why = if ($r) { "held in $r, not in $repo where launchers read this feed" }
               else    { 'not a release asset in any GitHub repository' }
        [void]$drop.Add([pscustomobject]@{ Pack = $p; Repo = $r; Why = $why })
    }
    return [pscustomobject]@{ Keep = @($keep.ToArray()); Drop = @($drop.ToArray()) }
}
