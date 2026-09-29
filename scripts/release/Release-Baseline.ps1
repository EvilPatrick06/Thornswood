<#
  Release-Baseline.ps1

  What a release is diffed against, and the record each release publishes of
  what it left installed (#441).

      . (Join-Path $PSScriptRoot 'Release-Baseline.ps1')

  WHY IT EXISTS. A release is the difference between this build and the last
  one published. Until #441 "the last one published" was published.json, a map
  of every file of ours to '<bytes>:<LastWriteTimeUtc.Ticks>' as the machine
  that last shipped saw it. Since #907 that file sits on the VPS beside the
  feed, so every machine reads the same one, but what it records is still one
  machine's memory: a file time. The same bytes on another machine, after a
  reinstall, or rewritten in place with the same content (hotfix 1.1.93 sent
  21 unchanged files, 12.5 MB, for exactly that) all read as changed. And when
  the store copy was missing the only way on was -Baseline, which records this
  build as already published whatever the feed really holds.

  So:
    - An entry is '<bytes>:<sha256>' of the file's own bytes (Get-BaselineEntry).
      The same bytes give the same entry on any machine.
    - An old '<bytes>:<ticks>' entry still compares the way it always did, the
      size and the file time, so the first release after the switch does not
      send the whole build again (Test-BaselineSame). Its new entry is a hash.
    - Every release writes the whole map as a file (ConvertTo-BaselineJson:
      sorted, ASCII, one shape on Windows PowerShell and PowerShell 7, so two
      runs over the same tree give the same bytes), sends it to the site as an
      asset like a pack (/feed[-dev]/assets/<sha256>), and names it in
      version.json as "baseline": { id, sha256, url, entries }. published.json
      in the store is written from the same map, so it has the same sha256.
    - Resolve-ReleaseBaseline decides what to diff against, in this order:
        1. the feed names a baseline and the store copy has its sha256: the
           store copy.
        2. the feed names one and the store copy is missing or is not it (a
           baseline send that failed, a feed put back by hand): that file,
           fetched from the site and checked against its sha256.
        3. the feed names none yet (feeds published before #441) and the store
           has one: the store copy, as before.
        4. otherwise: rebuilt by replaying every pack the feed lists, in order,
           from the site: each game file a pack carries at the size and sha256
           it carried it, each delete.txt line taken out. A file that never
           went out in a pack is missing from that and is sent again, so it can
           only send too much, never too little.
      The feed is what launchers install, so it wins over any copy on a disk.

  Every release's record also stays named in the feed, newest first, as
  "releases" (Add-FeedRelease), so Rollback-Feed.ps1 can put a channel back to
  one of them (#442).

  -SiteDir <folder> stands in for C:\Thornswood-Docs (the folder holding feed\
  and feed-dev\): assets are read from <folder>\<feed>\assets\<sha256> and
  nothing connects anywhere. Otherwise they are fetched from -SiteUrl over
  https, which needs no ssh. tests\test-release-baseline.ps1 drives it.
#>

function Get-BaselineHex([byte[]]$bytes) {
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

function Get-BaselineStreamSha([IO.Stream]$stream) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { return (Get-BaselineHex ($h.ComputeHash($stream))) }
    finally { $h.Dispose() }
}

function Get-BaselineFileSha([string]$path) {
    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $s = [IO.File]::Open((Resolve-Path -LiteralPath $path).ProviderPath, 'Open', 'Read', 'ReadWrite')
    try { return (Get-BaselineStreamSha $s) }
    finally { $s.Dispose() }
}

# One file's entry: its length and the sha256 of its bytes.
function Get-BaselineEntry([string]$path) {
    $s = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try { return ('{0}:{1}' -f $s.Length, (Get-BaselineStreamSha $s)) }
    finally { $s.Dispose() }
}

# '<bytes>:<ticks>', what published.json held until #441.
function Test-BaselineLegacy([string]$value) {
    return ([string]$value -match '^\d+:\d+$')
}

# Whether the file behind $now is the one $prev recorded. A hash entry is
# compared as it is. An old size and time entry is compared the way it was
# written: same size and same file time. $file is the file itself.
function Test-BaselineSame([string]$prev, [string]$now, $file) {
    if ($prev -eq $now) { return $true }
    if ($null -eq $file -or -not (Test-BaselineLegacy $prev)) { return $false }
    $p = $prev.Split(':')
    return ([int64]$p[0] -eq [int64]$file.Length) -and ([int64]$p[1] -eq [int64]$file.LastWriteTimeUtc.Ticks)
}

function ConvertTo-BaselineString([string]$s) {
    $e = [regex]::Replace($s, '[\\"\x00-\x1f\x7f-\uffff]', {
        param($m)
        $c = [int][char]$m.Value
        if ($c -eq 0x5C) { return '\\' }
        if ($c -eq 0x22) { return '\"' }
        return ('\u{0:x4}' -f $c)
    })
    return ('"' + $e + '"')
}

# The map as JSON, keys in ordinal order, ASCII only, no spaces, so the same
# map is the same bytes whichever PowerShell writes it.
function ConvertTo-BaselineJson($map) {
    $keys = [string[]]@($map.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('{')
    for ($i = 0; $i -lt $keys.Length; $i++) {
        if ($i) { [void]$sb.Append(',') }
        [void]$sb.Append((ConvertTo-BaselineString $keys[$i]))
        [void]$sb.Append(':')
        [void]$sb.Append((ConvertTo-BaselineString ([string]$map[$keys[$i]])))
    }
    [void]$sb.Append('}')
    return $sb.ToString()
}

# Writes the map and hands back the sha256 of what was written.
function Write-BaselineFile($map, [string]$path) {
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($path, (ConvertTo-BaselineJson $map), (New-Object Text.ASCIIEncoding))
    return (Get-BaselineFileSha $path)
}

function Read-BaselineFile([string]$path) {
    $map = @{}
    $text = ([IO.File]::ReadAllText($path)) -replace '^\uFEFF', ''
    if (-not $text.Trim()) { return $map }
    $o = $text | ConvertFrom-Json
    if ($null -ne $o) { foreach ($p in $o.PSObject.Properties) { $map[$p.Name] = [string]$p.Value } }
    return $map
}

# The "baseline" the feed names, or $null when it names none. Throws on one
# this script did not write, rather than guessing past it.
function Get-FeedBaselinePointer($doc) {
    if ($null -eq $doc -or -not $doc.PSObject.Properties['baseline'] -or $null -eq $doc.baseline) { return $null }
    $b = $doc.baseline
    $sha = ''; $url = ''
    if ($b.PSObject.Properties['sha256']) { $sha = ([string]$b.sha256).ToLowerInvariant() }
    if ($b.PSObject.Properties['url']) { $url = [string]$b.url }
    if ($sha -notmatch '^[0-9a-f]{64}$' -or -not $url) {
        throw 'The feed names a baseline without a sha256 and a url, so what was last published cannot be read from it.'
    }
    return $b
}

function New-FeedBaselinePointer([string]$Id, [string]$Sha, [string]$Url, [int]$Entries) {
    return [pscustomobject][ordered]@{ id = $Id; sha256 = $Sha.ToLowerInvariant(); url = $Url; entries = $Entries }
}

# ---- every release's record, so a channel can be put back (#442) -------------
#
# "releases" in the feed is the record each release published, newest first,
# each with lastPack: the id of the last pack on the feed once that release was
# out, which is the pack holding the plugin list it shipped. Publish-Update adds
# one per release (the release list block); Rollback-Feed.ps1 reads them to put
# the channel back to one of them. No launcher reads it, and a launcher ignores
# a field it does not know. The newest $FeedReleasesKeep are kept: about 200
# bytes each.
$FeedReleasesKeep = 30

# The id of the last pack on the feed, or '' when it lists none.
function Get-FeedLastPackId($doc) {
    if ($null -eq $doc -or -not $doc.PSObject.Properties['packs'] -or -not $doc.packs) { return '' }
    $all = @($doc.packs)
    for ($i = $all.Count - 1; $i -ge 0; $i--) {
        $p = $all[$i]
        if ($null -ne $p -and $p.PSObject.Properties['id'] -and [string]$p.id) { return [string]$p.id }
    }
    return ''
}

# The records the feed lists, newest first. An entry without an id, a sha256
# and a url is not one this script wrote and is left out.
function Get-FeedReleases($doc) {
    $out = New-Object System.Collections.Generic.List[object]
    if ($null -eq $doc -or -not $doc.PSObject.Properties['releases'] -or $null -eq $doc.releases) { return $out.ToArray() }
    foreach ($r in @($doc.releases)) {
        if ($null -eq $r) { continue }
        $id  = if ($r.PSObject.Properties['id']) { [string]$r.id } else { '' }
        $sha = if ($r.PSObject.Properties['sha256']) { ([string]$r.sha256).ToLowerInvariant() } else { '' }
        $url = if ($r.PSObject.Properties['url']) { [string]$r.url } else { '' }
        if (-not $id -or $sha -notmatch '^[0-9a-f]{64}$' -or -not $url) { continue }
        $out.Add($r)
    }
    return $out.ToArray()
}

function New-FeedReleaseEntry($Pointer, [string]$LastPack, [string]$To) {
    $o = [ordered]@{ id = [string]$Pointer.id; sha256 = ([string]$Pointer.sha256).ToLowerInvariant(); url = [string]$Pointer.url
                     entries = [int]$Pointer.entries; lastPack = $LastPack }
    if ($To) { $o['to'] = $To }
    return [pscustomobject]$o
}

# Puts this release's record at the front of the list and keeps the newest
# $Keep. Called BEFORE the feed's "baseline" is replaced: a feed that names a
# baseline and no list yet (the first release after #442) starts the list with
# that baseline, whose release ended at $LastPackBefore, the last pack on the
# feed before this release added its own. $To names the release a rollback put
# the channel back to.
function Add-FeedRelease($doc, $Pointer, [string]$LastPack, [string]$LastPackBefore, [string]$To, [int]$Keep = $FeedReleasesKeep) {
    $list = @(Get-FeedReleases $doc)
    if (-not $list.Count) {
        $old = $null
        try { $old = Get-FeedBaselinePointer $doc } catch { $old = $null }
        if ($null -ne $old -and [string]$old.id -ne [string]$Pointer.id) { $list = @(New-FeedReleaseEntry $old $LastPackBefore '') }
    }
    $list = @(New-FeedReleaseEntry $Pointer $LastPack $To) + @($list | Where-Object { [string]$_.id -ne [string]$Pointer.id })
    if ($Keep -gt 0 -and $list.Count -gt $Keep) { $list = @($list[0..($Keep - 1)]) }
    if ($doc.PSObject.Properties['releases']) { $doc.releases = $list }
    else { $doc | Add-Member -NotePropertyName 'releases' -NotePropertyValue $list }
    return $list
}

# Fetches one asset by the url the feed gives it, from the site or from
# -SiteDir, into $Dest, and refuses bytes that are not the sha256 they are
# named by. Only /feed[-dev]/assets/<sha256> urls: that is where every asset
# the feed names has lived since #897.
function Get-FeedAssetFile([string]$Url, [string]$Sha, [string]$Dest, [string]$SiteDir, [string]$SiteUrl = 'https://thornswood.net') {
    $m = [regex]::Match([string]$Url, '/(feed|feed-dev)/assets/([0-9a-fA-F]{64})(?:[?#].*)?$')
    if (-not $m.Success) { throw "$Url is not an asset on the site, so it cannot be read back." }
    $prefix = $m.Groups[1].Value
    $name = $m.Groups[2].Value.ToLowerInvariant()
    if ($Sha -and $name -ne $Sha.ToLowerInvariant()) { throw "$Url is not the asset its sha256 names." }
    $dir = Split-Path -Parent $Dest
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $part = $Dest + '.part'
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
    if ($SiteDir) {
        $src = Join-Path (Join-Path (Join-Path $SiteDir $prefix) 'assets') $name
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "The site has no /$prefix/assets/$name." }
        Copy-Item -LiteralPath $src -Destination $part -Force
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $wc = New-Object Net.WebClient
        $wc.Headers['User-Agent'] = 'Thornswood-Publish'
        try { $wc.DownloadFile(($SiteUrl.TrimEnd('/') + '/' + $prefix + '/assets/' + $name), $part) }
        catch { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue; throw ("/$prefix/assets/$name could not be fetched from $SiteUrl" + ': ' + $_.Exception.Message) }
        finally { $wc.Dispose() }
    }
    $got = Get-BaselineFileSha $part
    if ($got -ne $name) {
        Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
        throw "/$prefix/assets/$name on the site is not the bytes its name says (they hash to $got)."
    }
    Move-Item -LiteralPath $part -Destination $Dest -Force
    return $Dest
}

# Case 4: every pack the feed lists, applied in order the way a launcher
# applies them, reduced to the entry each game file would have. Only game
# files: the plugin list and launcher source keys are left out, so the next
# release sends the plugin list again (harmless) and never says the load order
# moved when nobody knows that it did.
function Get-BaselineFromPacks($doc, [string]$WorkDir, [string]$SiteDir, [string]$SiteUrl = 'https://thornswood.net', [scriptblock]$Say) {
    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $map = @{}
    $packs = @()
    if ($doc.PSObject.Properties['packs'] -and $doc.packs) { $packs = @($doc.packs) }
    if (-not $packs.Count) { throw 'The feed lists no packs to rebuild the baseline from.' }
    if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null }
    $n = 0
    foreach ($p in $packs) {
        $n++
        $id = if ($p.PSObject.Properties['id']) { [string]$p.id } else { "#$n" }
        $sha = if ($p.PSObject.Properties['sha256']) { ([string]$p.sha256).ToLowerInvariant() } else { '' }
        $url = if ($p.PSObject.Properties['url']) { [string]$p.url } else { '' }
        if ($sha -notmatch '^[0-9a-f]{64}$') { throw "Pack $id on the feed has no sha256, so it cannot be read back." }
        $zipPath = Join-Path $WorkDir ('replay-' + $sha + '.zip')
        [void](Get-FeedAssetFile $url $sha $zipPath $SiteDir $SiteUrl)
        if ($Say) { & $Say ("    pack {0} of {1}: {2}" -f $n, $packs.Count, $id) }
        $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $del = $zip.GetEntry('delete.txt')
            if ($null -ne $del) {
                $r = New-Object IO.StreamReader ($del.Open())
                try {
                    while ($null -ne ($line = $r.ReadLine())) {
                        $rel = $line.Trim().Replace('/', '\')
                        if ($rel) { $map.Remove($rel) }
                    }
                } finally { $r.Dispose() }
            }
            foreach ($e in $zip.Entries) {
                if (-not $e.FullName.StartsWith('game/') -or $e.FullName.EndsWith('/')) { continue }
                $rel = $e.FullName.Substring(5).Replace('/', '\')
                $s = $e.Open()
                try { $map[$rel] = ('{0}:{1}' -f $e.Length, (Get-BaselineStreamSha $s)) }
                finally { $s.Dispose() }
            }
        } finally { $zip.Dispose() }
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    }
    return $map
}

# What this release is diffed against; see the top of this file for the order.
# Hands back @{ Map; From; Pointer; Lines }: From is store, feed, store-no-pointer
# or packs, and Lines what to tell the person shipping. Writes nothing but
# scratch files under $WorkDir; Save-State writes the store copy once the
# release is out.
function Resolve-ReleaseBaseline([string]$VersionFile, [string]$StateFile, [string]$WorkDir, [string]$SiteDir, [string]$SiteUrl = 'https://thornswood.net', [scriptblock]$Say) {
    $doc = (([IO.File]::ReadAllText($VersionFile)) -replace '^\uFEFF', '') | ConvertFrom-Json
    $ptr = Get-FeedBaselinePointer $doc
    $have = Get-BaselineFileSha $StateFile
    $lines = @()
    if ($null -ne $ptr) {
        $want = ([string]$ptr.sha256).ToLowerInvariant()
        $relId = if ($ptr.PSObject.Properties['id']) { [string]$ptr.id } else { '' }
        if ($have -eq $want) {
            return [pscustomobject]@{ Map = (Read-BaselineFile $StateFile); From = 'store'; Pointer = $ptr; Lines = @("  baseline: release $relId, the one the feed names") }
        }
        $lines += $(if ($have) { "  the store's baseline is not the one the feed's last release ($relId) names, so that one is read from the site" }
                    else { "  the store has no baseline, so the one the feed's last release ($relId) names is read from the site" })
        $got = Join-Path $WorkDir ('baseline-' + $want + '.json')
        try {
            [void](Get-FeedAssetFile ([string]$ptr.url) $want $got $SiteDir $SiteUrl)
            $map = Read-BaselineFile $got
            Remove-Item -LiteralPath $got -Force -ErrorAction SilentlyContinue
            $lines += ("  baseline: release $relId, {0:n0} entries, checked against its sha256" -f $map.Count)
            return [pscustomobject]@{ Map = $map; From = 'feed'; Pointer = $ptr; Lines = $lines }
        } catch {
            $lines += ('  ' + $_.Exception.Message)
            $lines += '  so it is rebuilt from the packs the feed lists instead'
        }
    } elseif ($have) {
        return [pscustomobject]@{ Map = (Read-BaselineFile $StateFile); From = 'store-no-pointer'; Pointer = $null
                                  Lines = @('  baseline: the store''s published.json (the feed names none yet; the next release does)') }
    } else {
        $lines += '  the store has no baseline and the feed names none, so it is rebuilt from the packs the feed lists'
    }
    if ($Say) { foreach ($l in $lines) { & $Say $l } }
    $map = Get-BaselineFromPacks $doc $WorkDir $SiteDir $SiteUrl $Say
    $done = ("  baseline rebuilt from {0} pack(s): {1:n0} files. Anything of ours no pack carried is sent again." -f @($doc.packs).Count, $map.Count)
    return [pscustomobject]@{ Map = $map; From = 'packs'; Pointer = $ptr; Lines = @($done) }
}
