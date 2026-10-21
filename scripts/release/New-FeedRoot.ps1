<#
.SYNOPSIS
  Stages the folder a release from the feed is built from: every file the
  channel's last release left installed, from the site, by its sha256.

.DESCRIPTION
  Patrick's A on #2754 (20 Oct): dev and main Ships run without One, and carry
  the files that change only with the collection from the last release record.
  Measured on dev 20261020-111032-dev: 173 of its 288 files, 57.3 MB, are
  BodySlide outfits, Pandora behaviours, the six body meshes and old fork
  copies, which no checkout can make and which only a collection Ship on One
  changes. The other 115 the build makes from this checkout.

  So this puts the whole record into <Root>\Game, each file fetched from
  /feed[-dev]/assets/<sha256> and held to that sha256, and Ship -FromFeed then
  builds over it exactly as a Ship on One builds over its game folder: the
  front, Go.ps1's files, the plugins, the client. A file the build no longer
  makes stays as it would in One's folder, and Ship-Rules decides whether it
  ships, the same way. Nothing of the collection's is in the folder, so the
  publish carries the last release's plugin list (Publish-Update -FromFeed).

  The six client files are then held to records\client-build.json rather
  than to the last release (#2983): a file the release carried at another
  build is taken from the site by the sha256 the record names, from this
  channel's assets or else the other channel's, so main can carry the client
  a dev Ship already put on the site without an engine build here.

  It also writes <Root>\config.json from the feed's own server, voice and site
  fields, so the publish writes them back as they are: only a Ship from One
  moves a server.

  WHAT IT REFUSES
    - a feed that names no record, or a record whose files are not all on the
      site (no :record:files): a collection Ship from One sends them first;
    - any file that does not hash to the name the record gives it;
    - a recorded client file that is on neither feed's assets.
  A file already in the folder with the right bytes is not fetched again, and
  anything in Game the record does not name is removed first, so the folder
  is the record and nothing older.

  Talks to the site only (https), never to the VPS over ssh. Writes nothing
  outside -Root.

.EXAMPLE
  .\scripts\release\New-FeedRoot.ps1 -Channel dev
  Stages dev's last release into this machine's feed-root\dev folder.
#>
[CmdletBinding()]
param(
    [ValidateSet('main', 'dev')][string]$Channel = 'dev',
    # The folder to stage. Feed-Store.ps1 Get-FeedRootDir unless given.
    [string]$Root,
    [string]$SiteUrl = 'https://thornswood.net',
    # A folder standing in for the site's root on the VPS. Tests only.
    [string]$SiteDir,
    # The client record to stage. records\client-build.json unless given.
    [string]$ClientRecord
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Read-JsonFile.ps1')
. (Join-Path $PSScriptRoot 'Feed-Store.ps1')
. (Join-Path $PSScriptRoot 'Release-Baseline.ps1')
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
if (-not $Root) { $Root = Get-FeedRootDir $Channel }
$game = Join-Path $Root 'Game'
$sd = Get-FeedStoreSiteDir $SiteDir

# ---- the record the feed's last release names
$feed = Read-SiteFeed $Channel $SiteDir $SiteUrl
if ($null -eq $feed) { throw "The site has no $Channel feed, so there is nothing to stage." }
$ptr = Get-FeedBaselinePointer $feed
if ($null -eq $ptr) { throw "The $Channel feed names no record of its last release, so there is nothing to stage. A Ship from One names one." }
$work = Join-Path $Root 'record'
if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Force -Path $work | Out-Null }
$recordFile = Join-Path $work 'record.json'
[void](Get-FeedAssetFile ([string]$ptr.url) ([string]$ptr.sha256) $recordFile $sd $SiteUrl)
$map = Read-BaselineFile $recordFile
if (-not $map.ContainsKey($RecordFilesKey)) {
    throw "The $Channel feed's last release ($([string]$ptr.id)) does not have all its files on the site, so they cannot be staged from it. A Ship from One sends them."
}
$files = @($map.Keys | Where-Object { -not $_.StartsWith(':') } | Sort-Object)
Say ("{0} release {1}: {2} files" -f $Channel, [string]$ptr.id, $files.Count) 'Cyan'

# ---- the client this checkout records (#2983)
# Ship holds the six client files to records\client-build.json, which a
# rebuild on One or the box moves ahead of the channel's last release: on
# 21 Oct main's last release carried 3bdf3d3c while the record named b9e16e8b.
# A machine with no engine build cannot make them, but the dev Ship that
# first carried that client put each file on the site by its sha256. So these
# six are held to the client record, not the release's: each is taken from
# this channel's assets, else the other channel's, by the sha256 the record
# names. A client on neither feed is refused: Build-Engine on One or the box
# makes it, and the dev Ship from there puts it on the site.
$clientFile = if ($ClientRecord) { $ClientRecord } else { Join-Path $PSScriptRoot '..\..\records\client-build.json' }
$client = @{}
$clientCommit = ''
if (Test-Path -LiteralPath $clientFile -PathType Leaf) {
    $cb = ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText($clientFile)) $clientFile
    $clientCommit = [string]$cb.forkCommit
    foreach ($p in @($cb.files.PSObject.Properties)) {
        $client[$p.Name] = [pscustomobject]@{ Bytes = [int64]$p.Value.bytes; Sha = ([string]$p.Value.sha256).ToLowerInvariant() }
    }
}

# ---- nothing in Game the record does not name
if (-not (Test-Path -LiteralPath $game)) { New-Item -ItemType Directory -Force -Path $game | Out-Null }
$named = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($k in $files) { [void]$named.Add($k) }
foreach ($k in $client.Keys) { [void]$named.Add($k) }
$listed = (Get-Item -LiteralPath $game).FullName
$sep = [string][IO.Path]::DirectorySeparatorChar
$prefix = $listed.TrimEnd($sep) + $sep
$dropped = 0
foreach ($f in @(Get-ChildItem -LiteralPath $listed -Recurse -File -Force)) {
    if ($named.Contains($f.FullName.Substring($prefix.Length).Replace($sep, '\'))) { continue }
    Remove-Item -LiteralPath $f.FullName -Force
    $dropped++
}
if ($dropped) { Say "  $dropped file(s) in the folder that this release does not name were removed" 'DarkGray' }

# ---- each file by its sha256
$fetched = 0; $kept = 0; $bytes = [int64]0
foreach ($k in $files) {
    if ($client.ContainsKey($k)) { continue }
    $m = [regex]::Match([string]$map[$k], '^(\d+):([0-9a-fA-F]{64})$')
    if (-not $m.Success) { throw "The record names $k as '$([string]$map[$k])', not a size and a sha256, so it cannot be fetched." }
    $sha = $m.Groups[2].Value.ToLowerInvariant()
    $dest = Join-Path $game $k
    if ((Test-Path -LiteralPath $dest -PathType Leaf) -and (Get-BaselineEntry $dest) -eq ($m.Groups[1].Value + ':' + $sha)) { $kept++; continue }
    try { [void](Get-FeedAssetFile (Get-RecordFileUrl ([string]$ptr.url) $sha) $sha $dest $sd $SiteUrl) }
    catch { throw ("$k could not be staged: " + $_.Exception.Message) }
    $fetched++
    $bytes += [int64]$m.Groups[1].Value
}
Say ("  {0} fetched ({1:N1} MB), {2} already here with the same bytes" -f $fetched, ($bytes / 1MB), $kept) 'Green'

# ---- the recorded client, from the site
if ($client.Count) {
    $prefixes = @((Get-FeedStorePrefix $Channel), (Get-FeedStorePrefix $(if ($Channel -eq 'dev') { 'main' } else { 'dev' })))
    $inPlace = 0; $taken = @()
    foreach ($k in @($client.Keys | Sort-Object)) {
        $c = $client[$k]
        $dest = Join-Path $game $k
        if ((Test-Path -LiteralPath $dest -PathType Leaf) -and (Get-BaselineEntry $dest) -eq ('{0}:{1}' -f $c.Bytes, $c.Sha)) { $inPlace++; continue }
        $why = @()
        foreach ($pre in $prefixes) {
            try {
                [void](Get-FeedAssetFile ("$SiteUrl/$pre/assets/" + $c.Sha) $c.Sha $dest $sd $SiteUrl)
                $taken += "$k from /$pre"
                $why = $null
                break
            } catch { $why += $_.Exception.Message }
        }
        if ($null -ne $why) {
            throw ("The client this checkout records ($clientCommit) has $k on neither feed, so it cannot be staged: " + ($why -join ' ') + ' Build it with Build-Engine.ps1 on One or the box, and Ship dev from there.')
        }
    }
    if ($taken.Count) {
        Say ("  client {0}: {1} already the recorded build, {2} taken from the site" -f $clientCommit, $inPlace, $taken.Count) 'Green'
        foreach ($t in $taken) { Say "    $t" 'DarkGray' }
    } else {
        Say ("  client {0}: all {1} files are the recorded build" -f $clientCommit, $inPlace) 'DarkGray'
    }
}

# ---- the feed's own server, voice and site fields, as config.json names them
$cfg = [ordered]@{}
foreach ($pair in @(@('ServerAddress', 'serverAddress'), @('ServerPort', 'serverPort'),
                    @('UpdateFeedUrl', 'updateFeedUrl'), @('VoicePort', 'voicePort'),
                    @('VoiceUrl', 'voiceUrl'), @('DiscordAppId', 'discordAppId'), @('SiteUrl', 'siteUrl'),
                    @('PresenceImage', 'presenceImage'), @('CollectionUrl', 'collectionUrl'))) {
    if ($feed.PSObject.Properties[$pair[1]]) { $cfg[$pair[0]] = [string]$feed.($pair[1]) }
}
[IO.File]::WriteAllText((Join-Path $Root 'config.json'), (([pscustomobject]$cfg) | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
Say "  config.json: the $Channel feed's server $([string]$cfg['ServerAddress']):$([string]$cfg['ServerPort'])" 'DarkGray'
Say "staged in $Root" 'Green'
