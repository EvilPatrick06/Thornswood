<#
  Feed-Rules.ps1

  Which packs on the update feed a launcher can actually download.
  Publish-Update.ps1 dot-sources this and refuses to add a pack that breaks the
  rule; Repair-Manifest.ps1 dot-sources it and takes the ones already on the
  feed back out. One rule, so the two can never disagree about it.

  THE RULE. A launcher reads version.json from UpdateFeedUrl when set (the site
  feed on thornswood.net), or else from the repository the feed names as
  updateRepo via the GitHub Contents API, with no token on it, and downloads
  every pack from the url the feed gives. So a pack has to be either:

    - a release asset in that same updateRepo (GitHub-hosted packs), or
    - an https asset on thornswood.net (or a subdomain), under
      /feed/assets/<sha256> or /feed-dev/assets/<sha256>

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

  HOST CUTOVER (#649). Packs may also be served from thornswood.net under the
  locked URL shape confirmed with Website:

      https://thornswood.net/feed/version.json
      https://thornswood.net/feed-dev/version.json
      https://thornswood.net/feed/assets/<sha256>
      https://thornswood.net/feed-dev/assets/<sha256>

  Private-source GitHub assets and random hosts stay refused. GitHub release
  assets in updateRepo stay legal so Thornswood-Releases remains the hot
  rollback path. Signing / ExpectedSigner is still off.

      . (Join-Path $PSScriptRoot 'Feed-Rules.ps1')
      Get-FeedRepo $doc              owner/name launchers read this feed from
      Get-FeedPackRepo $url          owner/name a pack url downloads from, or ''
      Test-HostFeedAssetUrl $url     true when url is a thornswood.net feed asset
      Get-HostFeedAssetUrl $sha $Dev build https://thornswood.net/feed[-dev]/assets/<sha>
      Test-FeedPackUrl $url $repo    true when a launcher can download it
      Split-FeedPacks $packs $repo   .Keep and .Drop, in feed order, each drop with .Why
#>

# The repository every launcher reads this feed from (GitHub Contents API
# fallback). The feed names it as updateRepo (Publish-Update.ps1 writes that
# from config.json); a feed too old to name one is read from the repository
# Config.cs gives a fresh install.
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

# True when the url is an https pack/asset on thornswood.net (or a subdomain)
# under /feed/assets/<sha256> or /feed-dev/assets/<sha256>. Sha256 is exactly
# 64 hex digits. Query strings are allowed; fragments and other paths are not.
# Hosts that only end with the letters "thornswood.net" (evil.thornswood.net.evil)
# do not pass: the host must be thornswood.net or end with .thornswood.net.
function Test-HostFeedAssetUrl([string]$url) {
    if (-not $url) { return $false }
    $u = $url.Trim()
    $m = [regex]::Match($u,
        '^https://(?i)(?:[a-z0-9-]+\.)*thornswood\.net/(?:feed|feed-dev)/assets/[a-fA-F0-9]{64}(?:\?[^#]*)?$',
        'IgnoreCase')
    return $m.Success
}

# Build a host asset url from a sha256. Dev channel uses /feed-dev/, live uses
# /feed/. Publish-Update.ps1 -HostAssetUrls rewrites uploaded pack urls here
# after the GitHub release upload, so the feed points at the site while the
# release assets stay on Thornswood-Releases for rollback.
function Get-HostFeedAssetUrl([string]$sha256, [switch]$Dev) {
    $sha = ([string]$sha256).Trim().ToLowerInvariant()
    if ($sha -notmatch '^[a-f0-9]{64}$') { return '' }
    $prefix = if ($Dev) { 'feed-dev' } else { 'feed' }
    return "https://thornswood.net/$prefix/assets/$sha"
}

# The default version.json urls on the site (#649). Main live vs dev channel.
function Get-HostFeedVersionUrl([switch]$Dev) {
    if ($Dev) { return 'https://thornswood.net/feed-dev/version.json' }
    return 'https://thornswood.net/feed/version.json'
}

# A pack url a launcher can download: either a GitHub release asset in $repo,
# or a thornswood.net feed asset under the locked path shape. Names on GitHub
# are not case sensitive, so neither is the repo match.
function Test-FeedPackUrl([string]$url, [string]$repo) {
    if (Test-HostFeedAssetUrl $url) { return $true }
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
               else    { 'not a release asset in updateRepo, and not a thornswood.net feed asset url' }
        [void]$drop.Add([pscustomobject]@{ Pack = $p; Repo = $r; Why = $why })
    }
    return [pscustomobject]@{ Keep = @($keep.ToArray()); Drop = @($drop.ToArray()) }
}
