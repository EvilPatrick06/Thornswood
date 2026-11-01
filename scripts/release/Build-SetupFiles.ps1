<#
.SYNOPSIS
  Builds the files the launcher's Velopack package carries beside Game for
  the install's first start, and the list of them.

.DESCRIPTION
  Velopack's Setup.exe puts the launcher and its package on the PC, and the
  launcher's first start runs the install (launcher\app\InstallSteps.cs,
  #4824). That reads, from the package's own folder, what the old setup
  payload carried beside the game files (Package-Thornswood.ps1 until #4825):

      config.json       the channel's server, voice and site, from the feed
                        (New-FeedRoot.ps1 wrote it into -GameRoot), and
                        Channel, which picks the launcher's feed and its
                        Velopack channel; the install merges it into the
                        install folder's own
      profile\          plugins.txt and loadorder.txt, the reference load
                        order the channel's last release recorded (:golden:),
                        fetched from the site by their sha256, as
                        Package-Thornswood -FromFeed took them (#3412)
      applied.txt       every pack the feed lists, so a fresh install does
                        not offer the whole history of the project as
                        pending updates (the install writes it only when the
                        install folder has none)
      SOURCE CODE.txt,  where the source of the SkyMP files in Game is, the
      GPL-3.0.txt,      GNU GPL and AGPL texts, and the licence texts of the
      AGPL-3.0.txt,     libraries inside those files (Source-Notice.ps1, kind
      licences\         setup; #421, #3099)

  merge-release.yml packs every one of them at the top of the package, beside
  Thornswood.exe and Game, and setup-files.json lists each with its size and
  sha256. That list goes into the Release's signed manifest, and the launcher
  refuses an update package holding a file beside Game that the list does
  not name with those bytes (launcher\app\VeloPackage.cs).

      setup-files.json: { schema: 1, commit, channel, from: <the record id>,
                          files: [ { path: "profile/plugins.txt", size, sha256 } ] }

  READ ME FIRST.txt is not carried: it told people which of Setup.bat and
  Install.bat to run, and both retired with #4824.

  WHAT IT REFUSES. A -GameRoot New-FeedRoot did not stage (no config.json or
  record), a feed whose record is not the one staged there (a Ship published
  between the two steps: run the workflow again), a record with no reference
  load order, and a golden list that does not hash to its name.

  Talks to the site (https) for the feed and the two lists; never to the VPS.
  Writes only under -Out.

.PARAMETER Out
  The folder: files\ holds what is packed, setup-files.json the list. Emptied
  first.

.PARAMETER GameRoot
  The folder Build-GameFiles.ps1 staged the release in (its -Root), holding
  Game, config.json and record\record.json as New-FeedRoot.ps1 left them.

.PARAMETER Channel
  The feed the release was built over, dev unless given.

.PARAMETER Commit
  The commit, 40 hex, written into the list. git rev-parse HEAD unless given.

.PARAMETER SiteDir
  A folder standing in for the site's root. Tests only.

.EXAMPLE
  pwsh -File scripts/release/Build-SetupFiles.ps1 -Out $env:RUNNER_TEMP\setup -GameRoot $env:RUNNER_TEMP\game-root
  What merge-release.yml runs.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [Parameter(Mandatory = $true)][string]$GameRoot,
    [ValidateSet('main', 'dev')][string]$Channel = 'dev',
    [string]$Commit,
    [string]$SiteUrl = 'https://thornswood.net',
    [string]$SiteDir
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Here = $PSScriptRoot
$RepoDir = (Resolve-Path (Join-Path $Here '..\..')).Path
. (Join-Path $Here 'Read-JsonFile.ps1')
. (Join-Path $Here 'Feed-Store.ps1')
. (Join-Path $Here 'Release-Baseline.ps1')
. (Join-Path $Here 'Source-Notice.ps1')
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

if (-not $Commit) { $Commit = (& git -C $RepoDir rev-parse HEAD).Trim() }
if ($Commit -notmatch '^[0-9a-f]{40}$') { throw "commit $Commit is not 40 hex" }
$cfgFrom = Join-Path $GameRoot 'config.json'
$recordFile = Join-Path (Join-Path $GameRoot 'record') 'record.json'
$gameDir = Join-Path $GameRoot 'Game'
foreach ($p in @($cfgFrom, $recordFile)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "$p is not there. Build-GameFiles.ps1 (New-FeedRoot.ps1) stages it; run that first with this -Root." }
}

if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
$files = Join-Path $Out 'files'
$null = New-Item -ItemType Directory -Force -Path (Join-Path $files 'profile')
$utf8 = New-Object Text.UTF8Encoding($false)

# ---- config.json: the feed's server, voice and site, as staged, and the
# channel. The launcher reads its feed and its Velopack channel from Channel
# (Updater.FeedUrl, Velo.ChannelFor), and New-FeedRoot writes none, so a dev
# package without it would install a launcher that reads main's feed.
$cfg = ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText($cfgFrom)) $cfgFrom
$cfgOut = [ordered]@{}
foreach ($p in $cfg.PSObject.Properties) { $cfgOut[$p.Name] = $p.Value }
$cfgOut['Channel'] = $(if ($Channel -eq 'dev') { 'dev' } else { '' })
[IO.File]::WriteAllText((Join-Path $files 'config.json'), (([pscustomobject]$cfgOut) | ConvertTo-Json), $utf8)
Say "  config.json: the $Channel feed's server, voice and site, and the $Channel channel" 'Green'

# ---- the feed, held to the record staged from it
$feed = Read-SiteFeed $Channel $SiteDir $SiteUrl
if ($null -eq $feed) { throw "The site has no $Channel feed." }
$ptr = Get-FeedBaselinePointer $feed
if ($null -eq $ptr) { throw "The $Channel feed names no record of its last release." }
$staged = (Get-FileHash -LiteralPath $recordFile -Algorithm SHA256).Hash.ToLowerInvariant()
if ($staged -ne ([string]$ptr.sha256).ToLowerInvariant()) {
    throw ("The $Channel feed names release $([string]$ptr.id) now, and the game files were built over another record ($staged). " +
           'A Ship published while this ran; run the workflow again so both are the same release.')
}
$map = Read-BaselineFile $recordFile

# ---- profile\: the reference load order the release recorded (:golden:)
$sd = Get-FeedStoreSiteDir $SiteDir
foreach ($f in 'plugins.txt', 'loadorder.txt') {
    $key = ":golden:$f"
    if (-not $map.ContainsKey($key)) { throw "Release $([string]$ptr.id) recorded no $f, so the install would carry no reference load order." }
    $sha = ([string]$map[$key]).Split(':')[-1].ToLowerInvariant()
    $url = Get-RecordFileUrl ([string]$ptr.url) $sha
    if (-not $url) { throw "The $Channel feed's record is not an asset on the site ($([string]$ptr.url)), so its $f cannot be fetched beside it." }
    [void](Get-FeedAssetFile $url $sha (Join-Path (Join-Path $files 'profile') $f) $sd $SiteUrl)
}
Say "  profile\: plugins.txt and loadorder.txt of release $([string]$ptr.id)" 'Green'

# ---- applied.txt: every pack the feed lists
$ids = @()
if ($feed.PSObject.Properties['packs']) {
    foreach ($pk in @($feed.packs)) {
        if ($pk -and $pk.PSObject.Properties['id'] -and $pk.id) { $ids += [string]$pk.id }
    }
}
$ids = @($ids | Select-Object -Unique)
if ($ids.Count -gt 0) {
    [IO.File]::WriteAllLines((Join-Path $files 'applied.txt'), [string[]]$ids, $utf8)
    Say ("  applied.txt: {0} packs the release already holds" -f $ids.Count) 'Green'
} else {
    Say '  applied.txt: the feed lists no packs, so none is written' 'DarkGray'
}

# ---- SOURCE CODE.txt, the GPL and AGPL texts and licences\
$carried = @()
if (Test-Path -LiteralPath $gameDir) {
    $carried = @(Get-ChildItem -LiteralPath $gameDir -Recurse -File -Force | ForEach-Object { [IO.Path]::GetRelativePath($gameDir, $_.FullName).Replace('/', '\') })
}
$entries = @(Get-SourceNoticeEntries (Join-Path $RepoDir 'records\client-build.json') $carried 'setup' (Join-Path $RepoDir 'installer\licences') (Join-Path $RepoDir 'records\front-build.json'))
if ($entries.Count -eq 0) { throw 'The game files carry none of the SkyMP files, so there is no source to name. That is not a release this builds.' }
Write-SourceNoticeToFolder $files $entries
Say ("  SOURCE CODE.txt, the GPL and AGPL texts and {0} library licence texts" -f (@($entries).Count - 3)) 'Green'

# ---- the list
$list = foreach ($f in @(Get-ChildItem -LiteralPath $files -Recurse -File -Force)) {
    [ordered]@{
        path   = [IO.Path]::GetRelativePath($files, $f.FullName).Replace('\', '/')
        size   = $f.Length
        sha256 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}
$sorted = [object[]]@($list)
[Array]::Sort($sorted, [Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.path, $b.path) })
$doc = [ordered]@{ schema = 1; commit = $Commit; channel = $Channel; from = [string]$ptr.id; files = $sorted }
[IO.File]::WriteAllText((Join-Path $Out 'setup-files.json'), ($doc | ConvertTo-Json -Depth 4), $utf8)
Say ("  setup-files.json lists {0} files" -f $sorted.Count) 'Green'
exit 0
