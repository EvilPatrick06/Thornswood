<#
  Release-Manifest.ps1

  The signed release manifest, phase B of docs\SIGNED-RELEASES.md (#2163).

      . (Join-Path $PSScriptRoot 'Release-Manifest.ps1')

  WHY IT EXISTS. The feed names every pack, the client runtime, the launcher
  and the baseline record by sha256, and the launcher refuses a file whose
  hash is not that name. But whoever can write version.json writes those names
  too, so a checksum alone never says who released a file (section 9.1). The
  manifest is a list of those hashes, with where they were built from, and a
  Windows catalog over it signed by ThornswoodRelease, the profile every
  installed launcher already trusts. A file of ours the manifest lists was put
  out by someone holding the signing right, whatever wrote the feed.

  WHAT IT LISTS. Each asset that carries code or names files: the launcher, the
  client runtime, each pack and optional pack (Get-FeedAssets in
  Feed-Rules.ps1), and the baseline record, which names every file of the
  release by its own sha256, so those files are covered through it. Not
  version.json's own bytes: Set-Server, Set-Collection, Dev-News,
  Publish-Discord, Rollback-Feed and Repair-Manifest all rewrite the feed after
  a Ship, so a signature over it would be stale by the next edit. Not the news
  file either, for the same reason (Dev-News rewrites it). What the feed says
  outside those hashes (the server address, the collection, the news) is
  therefore not covered; section 2 of the doc says so.

  THE FILES. In <dir>:
      files\release.json   the manifest, compact UTF-8 without a byte order mark
      release.cat          a catalog (New-FileCatalog, version 2, SHA256) whose
                           one member is release.json
  Both go to the site as assets, by their own sha256, and the feed names them
  as "signedManifest" (Publish-Update.ps1). Signing the catalog and checking
  that signature are Sign-ReleaseCatalog.ps1, a file of its own so a harness
  that runs the real publisher with no signing setup can stand a stub in for
  it, the way it does for Close-Launcher.ps1.

      Get-ReleaseManifestAssets $doc               what the feed names, What and Sha
      New-ReleaseManifestFiles $doc $id $channel $dir
                                                   writes both; returns Json, Catalog, Files
      Get-ReleaseManifestRefusal $files $doc       '' when the catalog holds the
                                                   manifest and the manifest lists
                                                   every asset of $doc, else why

  Needs Feed-Rules.ps1 dot-sourced first (Get-FeedAssets). Keep it ASCII and
  Windows PowerShell 5.1.
#>

# Every asset of the feed the manifest must list, in feed order, then the
# baseline record. Each is What and Sha. An asset the feed names with no sha256
# is an error, not a gap: the launcher could not check it either.
function Get-ReleaseManifestAssets($doc) {
    $out = New-Object System.Collections.ArrayList
    if ($null -eq $doc) { return @() }
    foreach ($a in @(Get-FeedAssets $doc)) {
        if (-not $a.Sha) { throw ("The feed names $($a.What) at $($a.Url) with no sha256, so the manifest cannot list it.") }
        [void]$out.Add([pscustomobject]@{ What = [string]$a.What; Sha = [string]$a.Sha })
    }
    $b = $null
    if ($doc.PSObject.Properties['baseline']) { $b = $doc.baseline }
    if ($null -ne $b -and $b.PSObject.Properties['url'] -and ([string]$b.url).Trim()) {
        $s = ''
        if ($b.PSObject.Properties['sha256']) { $s = ([string]$b.sha256).Trim().ToLowerInvariant() }
        if ($s -notmatch '^[a-f0-9]{64}$') { throw ("The feed names a baseline record at $($b.url) with no sha256, so the manifest cannot list it.") }
        $bid = if ($b.PSObject.Properties['id']) { [string]$b.id } else { '' }
        [void]$out.Add([pscustomobject]@{ What = ('baseline record ' + $bid).Trim(); Sha = $s })
    }
    return @($out.ToArray())
}

function Get-ReleaseManifestField($o, [string]$k) {
    if ($null -ne $o -and $o.PSObject.Properties[$k] -and $null -ne $o.$k) { return ([string]$o.$k).Trim() }
    return ''
}

# Writes files\release.json and release.cat under $Dir, which it empties
# first. Returns Json, Catalog and Files (the folder the catalog covers).
function New-ReleaseManifestFiles($doc, [string]$Id, [string]$Channel, [string]$Dir) {
    if (-not $Id) { throw 'New-ReleaseManifestFiles needs the release id.' }
    if (-not $Dir) { throw 'New-ReleaseManifestFiles needs a folder to write into.' }
    $assets = @(Get-ReleaseManifestAssets $doc)
    if (-not $assets.Count) { throw "The feed for $Id names no asset, so there is nothing to sign." }
    $rel = $null
    if ($doc.PSObject.Properties['release']) { $rel = $doc.release }
    $client = $null
    if ($doc.PSObject.Properties['clientRuntime']) { $client = $doc.clientRuntime }
    $m = [ordered]@{
        schema          = 1
        release         = $Id
        channel         = $Channel
        commit          = (Get-ReleaseManifestField $rel 'commit')
        branch          = (Get-ReleaseManifestField $rel 'branch')
        launcherVersion = (Get-ReleaseManifestField $doc 'launcherVersion')
        forkCommit      = (Get-ReleaseManifestField $client 'forkCommit')
        made           = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        assets          = @($assets | ForEach-Object { [ordered]@{ what = $_.What; sha256 = $_.Sha } })
    }
    if (Test-Path -LiteralPath $Dir) { Remove-Item -LiteralPath $Dir -Recurse -Force }
    $files = Join-Path $Dir 'files'
    New-Item -ItemType Directory -Force -Path $files | Out-Null
    $json = Join-Path $files 'release.json'
    [IO.File]::WriteAllText($json, ($m | ConvertTo-Json -Depth 8 -Compress), (New-Object Text.UTF8Encoding($false)))
    $cat = Join-Path $Dir 'release.cat'
    New-FileCatalog -Path $files -CatalogFilePath $cat -CatalogVersion 2.0 | Out-Null
    if (-not (Test-Path -LiteralPath $cat -PathType Leaf)) { throw "New-FileCatalog wrote no catalog at $cat." }
    return [pscustomobject]@{ Json = $json; Catalog = $cat; Files = $files }
}

# '' when the catalog still holds release.json as written, the manifest is the
# release it says, and it lists every asset $doc names; else what is wrong. The
# catalog's signature is Sign-ReleaseCatalog.ps1's to check, not this.
function Get-ReleaseManifestRefusal($Files, $doc) {
    $st = ''
    try { $st = [string](Test-FileCatalog -Path $Files.Files -CatalogFilePath $Files.Catalog) }
    catch { return ('the catalog could not be checked against release.json: ' + $_.Exception.Message) }
    if ($st -ne 'Valid') { return ("the catalog does not hold release.json as it is on disk (Test-FileCatalog said $st)") }
    $m = $null
    try { $m = [IO.File]::ReadAllText($Files.Json) | ConvertFrom-Json }
    catch { return ('release.json does not parse: ' + $_.Exception.Message) }
    $listed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($a in @($m.assets)) { if ($null -ne $a) { [void]$listed.Add(([string]$a.sha256).ToLowerInvariant()) } }
    $missing = @(@(Get-ReleaseManifestAssets $doc) | Where-Object { -not $listed.Contains($_.Sha) })
    if ($missing.Count) { return ('release.json does not list ' + (($missing | ForEach-Object { "$($_.What) ($($_.Sha))" }) -join ', ')) }
    return ''
}
