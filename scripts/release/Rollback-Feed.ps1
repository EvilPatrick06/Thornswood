<#
  Rollback-Feed.ps1

  Puts a channel's feed back to an earlier release, so every launcher on that
  channel moves its game files back to what that release installed, with no
  hand editing of version.json (#442).

      .\scripts\release\Rollback-Feed.ps1 -Channel dev -List          what it can go back to
      .\scripts\release\Rollback-Feed.ps1 -Channel dev -Back 1        the release before this one
      .\scripts\release\Rollback-Feed.ps1 -Channel dev -To 20260929-1200-dev
      .\scripts\release\Rollback-Feed.ps1 -Channel dev -Back 1 -DryRun   build it, send nothing

  WHY IT EXISTS. The feed is a chain of deltas: a launcher applies every pack
  whose id is not in its applied.txt, in order, and never takes one back. So
  the only way back from a bad release was to ship another one by hand that
  put the old files back, which is what 1.1.77 did for 1.1.76 on 21 September.
  Since #441 every release publishes the record of what it left installed
  (every file of ours by size and sha256), and since this change the feed keeps
  the last thirty of those records as "releases". The difference between two
  records is exactly what a rollback has to send.

  WHAT IT DOES. It reads the record of the release the feed is on now and the
  record of the one asked for, and builds ONE ordinary pack out of the
  difference: every file whose bytes differ goes in at the older release's
  bytes, every file the later releases added goes in delete.txt, and the plugin
  list goes in as that release shipped it. The pack goes on the end of the feed
  like any other, so every launcher already installed takes it the way it
  takes every update: nothing in the launcher changes, and a launcher that is
  several releases behind applies them and then this, and lands on the same
  files. Putting the channel forward again is the same command pointed at the
  later release.

  Each file is taken from the packs already on the site, found by its size and
  sha256, and checked again when it is read. A file no pack ever carried (it
  came with the installer and nothing changed it before the release being
  undone) is not on the site; the rollback stops and names it, and -FilesFrom
  points at a folder holding the right bytes, which are checked the same way.

  WHAT STAYS. The launcher, its version and minLauncher: a launcher never moves
  to a lower number, signed launchers refuse an update not signed by us, and
  the site refuses a join pass above the feed's launcherVersion, so taking the
  number down would lock out everybody already on it. The six client runtime
  files stay with the launcher, because the launcher carries the record of
  which client belongs beside it and puts back any other. The server is not
  part of the feed: if the release being undone changed the gamemode or the
  plugins the server loads, put the server back too.

  The pack and the record go to the site before version.json names them, and
  the feed and the store's baseline go back through Feed-Store.ps1 in one send,
  which replaces nothing if another Ship or feed edit went out meanwhile.

  -SiteDir <folder> stands in for C:\Thornswood-Docs and nothing connects
  anywhere; tests\test-feed-rollback.ps1 drives it that way.
#>
[CmdletBinding()]
param(
    # main or dev. No default: which feed goes back is always said.
    [Parameter(Mandatory = $true)][ValidateSet('main', 'dev')][string]$Channel,
    # The id of the release to go back (or forward) to, as -List shows it.
    [string]$To,
    # Or how many releases back from the one the feed is on: 1 is the one before.
    [int]$Back = 0,
    # Lists the releases the feed names and stops.
    [switch]$List,
    # The release note, in Ship's shape: a title, then "- " lines. Left out, it
    # says which release the files went back to.
    [string]$Notes = '',
    # Folders holding files no pack on the site carries, at the path they have
    # under the game folder. Only a file of the right size and sha256 is taken.
    [string[]]$FilesFrom = @(),
    # Builds the pack and says what it would do. Sends nothing.
    [switch]$DryRun,
    [switch]$NoPause,
    # Where the pack is built. Left out, rollback-<channel> beside Ship's own
    # staging folder.
    [string]$WorkDir,
    # This machine's working folder for the channel's feed (Feed-Store.ps1).
    [string]$ReleaseDir,
    # The id of the pack this makes. Left out, the time now, like a Ship.
    [string]$Id,
    [string]$SiteUrl = 'https://thornswood.net',
    # A folder standing in for C:\Thornswood-Docs. Tests only.
    [string]$SiteDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

. (Join-Path $Here 'Feed-Store.ps1')
. (Join-Path $Here 'Release-Baseline.ps1')
. (Join-Path $Here 'Feed-Rules.ps1')
. (Join-Path $Here 'Note-Rules.ps1')
. (Join-Path $Here 'Source-Notice.ps1')
Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

$Dev = ($Channel -eq 'dev')
$sd = Get-FeedStoreSiteDir $SiteDir
if (-not $ReleaseDir) { $ReleaseDir = Get-FeedStoreDir $Channel }
if (-not $WorkDir) { $WorkDir = Join-Path (& (Join-Path $Here 'Where.ps1') Dist) ('rollback-' + $Channel) }
New-Item -ItemType Directory -Force -Path $ReleaseDir, $WorkDir | Out-Null
$clientRecord = Join-Path $Here '..\..\records\client-build.json'
$licences = Join-Path $Here '..\..\installer\licences'

function Get-Prop($o, [string]$k) {
    if ($null -ne $o -and $o.PSObject.Properties[$k]) { return [string]$o.$k }
    return ''
}

# "20260928-1630-dev" as "28 Sep at 16:30", for the note.
function Get-ReleaseWhen([string]$rid) {
    $m = [regex]::Match($rid, '^(\d{8})-(\d{4})')
    if ($m.Success) {
        try {
            $t = [datetime]::ParseExact($m.Groups[1].Value + $m.Groups[2].Value, 'yyyyMMddHHmm', [Globalization.CultureInfo]::InvariantCulture)
            return $t.ToString('d MMM', [Globalization.CultureInfo]::InvariantCulture) + ' at ' + $t.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        } catch { }
    }
    return $rid
}

# ------------------------------------------------------------ the feed
Head "The $Channel feed"
try { [void](Receive-FeedStore $Channel $ReleaseDir -SiteDir $SiteDir) }
catch { Die ("Could not receive the $Channel feed from the VPS, so nothing was changed: " + $_.Exception.Message) }
$VersionFile = Join-Path $ReleaseDir 'version.json'
$StateFile = Join-Path $ReleaseDir 'published.json'
if (-not (Test-Path -LiteralPath $VersionFile)) { Die "The VPS has no version.json for the $Channel channel." }
$doc = (([IO.File]::ReadAllText($VersionFile)) -replace '^\uFEFF', '') | ConvertFrom-Json
$cur = $null
try { $cur = Get-FeedBaselinePointer $doc } catch { Die $_.Exception.Message }
$releases = @(Get-FeedReleases $doc)

# Where the release the feed is on sits in the list. A Ship from a branch
# without the release list moves "baseline" and not the list, so the feed can
# be on a release the list does not name; everything is then counted from the
# top of the list.
$curAt = -1
if ($null -ne $cur) {
    for ($i = 0; $i -lt $releases.Count; $i++) {
        if ([string]$releases[$i].sha256 -eq ([string]$cur.sha256).ToLowerInvariant() -and [string]$releases[$i].id -eq [string]$cur.id) { $curAt = $i; break }
    }
}

if ($List -or (-not $To -and $Back -le 0)) {
    if (-not $releases.Count) { Say '  the feed names no releases to go back to yet; every Ship from now on adds one' 'Yellow' }
    for ($i = 0; $i -lt $releases.Count; $i++) {
        $r = $releases[$i]
        $mark = if ($i -eq $curAt) { '  <- the feed is on this one' } else { '' }
        $to = Get-Prop $r 'to'
        $what = if ($to) { " (put back to $to)" } else { '' }
        Say ("  {0,-22} {1}{2}{3}" -f [string]$r.id, (Get-ReleaseWhen ([string]$r.id)), $what, $mark) $(if ($i -eq $curAt) { 'Green' } else { 'Gray' })
    }
    if ($null -ne $cur -and $curAt -lt 0) { Say ("  the feed is on {0}, which the list does not name" -f [string]$cur.id) 'Yellow' }
    if (-not $List) { Say ''; Say 'Name one with -To <id>, or -Back 1 for the one before.' 'Yellow' }
    Write-Host ''
    exit 0
}
if ($To -and $Back -gt 0) { Die 'Say -To or -Back, not both.' }
if ($null -eq $cur) {
    Die ("The $Channel feed names no record of what its last release installed, so nothing can be worked out from it. " +
         'Every release sent to the site names one; ship once, then this works.')
}

$tgt = $null
if ($To) {
    foreach ($r in $releases) { if ([string]$r.id -eq $To) { $tgt = $r; break } }
    if ($null -eq $tgt) { Die ("The $Channel feed names no release $To. Run with -List to see the ones it names.") }
} else {
    $at = $(if ($curAt -ge 0) { $curAt } else { -1 }) + $Back
    if ($at -ge $releases.Count) {
        Die ("The $Channel feed names $($releases.Count) release(s), so there is nothing $Back back. Run with -List to see them.")
    }
    $tgt = $releases[$at]
}
$tgtId = [string]$tgt.id
if (([string]$tgt.sha256) -eq ([string]$cur.sha256).ToLowerInvariant()) {
    Die ("The $Channel feed already has what $tgtId installed. Nothing to do.")
}
Say ("  the feed is on {0}, going to {1} ({2})" -f [string]$cur.id, $tgtId, (Get-ReleaseWhen $tgtId)) 'Green'

# ------------------------------------------------------------ the two records
# The store's copy when it is the record the feed names, otherwise the one on
# the site, checked by its sha256 either way.
function Get-Record($ptr) {
    $want = ([string]$ptr.sha256).ToLowerInvariant()
    if ((Get-BaselineFileSha $StateFile) -eq $want) { return (Read-BaselineFile $StateFile) }
    $f = Join-Path $WorkDir ('baseline-' + $want + '.json')
    [void](Get-FeedAssetFile ([string]$ptr.url) $want $f $sd $SiteUrl)
    $map = Read-BaselineFile $f
    Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    return $map
}
try { $curMap = Get-Record $cur } catch { Die ("The record of what the feed has now could not be read: " + $_.Exception.Message) }
try { $tgtMap = Get-Record $tgt } catch { Die ("The record of what $tgtId installed could not be read: " + $_.Exception.Message) }
foreach ($pair in @(@('now', $curMap), @($tgtId, $tgtMap))) {
    foreach ($k in @($pair[1].Keys)) {
        if (-not $k.StartsWith(':') -and [string]$pair[1][$k] -notmatch '^\d+:[0-9a-f]{64}$') {
            Die ("The record for $($pair[0]) has $k as '$([string]$pair[1][$k])', not a size and a sha256, so which bytes it means is not known.")
        }
    }
}

# The six client runtime files stay with the launcher, and so does its source
# record (:src:), because the launcher is not rolled back.
$clientKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $clientRecord) {
    $cb = ((Get-Content -LiteralPath $clientRecord -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json
    foreach ($n in @($cb.files.PSObject.Properties.Name)) { [void]$clientKeys.Add($n) }
}
function Test-StaysWithLauncher([string]$k) { return ($k.StartsWith(':src:') -or $clientKeys.Contains($k)) }

$newMap = @{}
foreach ($k in @($tgtMap.Keys)) { if (-not (Test-StaysWithLauncher $k)) { $newMap[$k] = [string]$tgtMap[$k] } }
foreach ($k in @($curMap.Keys)) { if (Test-StaysWithLauncher $k) { $newMap[$k] = [string]$curMap[$k] } }

$write = @(@($newMap.Keys | Where-Object { -not $_.StartsWith(':') -and (-not $curMap.ContainsKey($_) -or [string]$curMap[$_] -ne [string]$newMap[$_]) }) | Sort-Object)
$delete = @(@($curMap.Keys | Where-Object { -not $_.StartsWith(':') -and -not $newMap.ContainsKey($_) }) | Sort-Object)
$listMoved = @(@($newMap.Keys) + @($curMap.Keys) | Where-Object { $_ -like ':profile:*' -or $_ -like ':order:*' } | Sort-Object -Unique |
               Where-Object { [string]$newMap[$_] -ne [string]$curMap[$_] }).Count -gt 0
$keptClient = @($tgtMap.Keys | Where-Object { $clientKeys.Contains($_) -and [string]$tgtMap[$_] -ne [string]$curMap[$_] }).Count
if (-not $write.Count -and -not $delete.Count -and -not $listMoved) {
    Die ("$tgtId left the same game files and plugin list as the feed has now" +
         $(if ($keptClient) { ', apart from the client runtime, which stays with the launcher' } else { '' }) + '. Nothing to send.')
}
$writeBytes = [int64]0
foreach ($k in $write) { $writeBytes += [int64](([string]$newMap[$k]).Split(':')[0]) }
Say ("  {0:n0} file(s) go back to how {1} had them ({2:n1} MB)" -f $write.Count, $tgtId, ($writeBytes / 1MB)) $(if ($write.Count) { 'Green' } else { 'DarkGray' })
Say ("  {0:n0} file(s) the later releases added are taken out" -f $delete.Count) $(if ($delete.Count) { 'Yellow' } else { 'DarkGray' })
if ($listMoved) { Say '  the plugin list goes back too' 'Yellow' }
if ($keptClient) { Say '  the client runtime stays with the launcher, which is not rolled back' 'DarkGray' }

# ------------------------------------------------------------ the bytes
Head 'Finding the files'
$stamp = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$stage = Join-Path $WorkDir ('stage-' + $stamp)
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'game'), (Join-Path $stage 'profile') | Out-Null
# What is still wanted: entry ('<bytes>:<sha256>') to the paths wanting it.
$need = @{}
foreach ($k in $write) {
    $e = [string]$newMap[$k]
    if (-not $need.ContainsKey($e)) { $need[$e] = New-Object System.Collections.Generic.List[string] }
    $need[$e].Add($k)
}
$sizes = New-Object 'System.Collections.Generic.HashSet[int64]'
foreach ($e in @($need.Keys)) { [void]$sizes.Add([int64]($e.Split(':')[0])) }

# Writes the bytes for one entry to every path wanting them, checks each one
# against the record, and takes the entry off what is wanted. $writeTo is handed
# the path to write.
function Put-Staged([string]$want, [scriptblock]$writeTo) {
    foreach ($rel in @($need[$want])) {
        $dest = Join-Path (Join-Path $stage 'game') $rel
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        & $writeTo $dest
        if ((Get-BaselineEntry $dest) -ne $want) { throw "$rel did not come out as the bytes the record names." }
    }
    $need.Remove($want)
}
function Get-WantedCount { $n = 0; foreach ($v in @($need.Values)) { $n += $v.Count }; return $n }

foreach ($from in @($FilesFrom)) {
    if (-not $from -or -not (Test-Path -LiteralPath $from)) { continue }
    foreach ($e in @($need.Keys)) {
        foreach ($rel in @($need[$e])) {
            $f = Join-Path $from $rel
            if ((Test-Path -LiteralPath $f -PathType Leaf) -and (Get-BaselineEntry $f) -eq $e) {
                $src = $f
                Put-Staged $e { param($d) Copy-Item -LiteralPath $src -Destination $d -Force }
                Say "  $rel from $from" 'DarkGray'
                break
            }
        }
    }
}

# The pack the target release ended on holds its plugin list; after it, every
# pack on the feed, newest first, until nothing is wanted.
$packs = @()
if ($doc.PSObject.Properties['packs'] -and $doc.packs) { $packs = @($doc.packs | Where-Object { $null -ne $_ -and (Get-Prop $_ 'id') }) }
$lastPack = Get-Prop $tgt 'lastPack'
$order = @()
if ($lastPack) {
    $lp = @($packs | Where-Object { (Get-Prop $_ 'id') -eq $lastPack })
    if (-not $lp.Count) { Die ("$tgtId ended on pack $lastPack, which the feed no longer lists, so its plugin list cannot be read.") }
    $order += $lp[0]
}
for ($i = $packs.Count - 1; $i -ge 0; $i--) { if ((Get-Prop $packs[$i] 'id') -ne $lastPack) { $order += $packs[$i] } }
$profileFound = @()
foreach ($p in $order) {
    $isLast = ($lastPack -and (Get-Prop $p 'id') -eq $lastPack)
    if (-not $need.Count -and -not $isLast) { break }
    $sha = (Get-Prop $p 'sha256').ToLowerInvariant()
    $zipPath = Join-Path $WorkDir ('look-' + $sha + '.zip')
    try { [void](Get-FeedAssetFile (Get-Prop $p 'url') $sha $zipPath $sd $SiteUrl) }
    catch {
        if ($isLast) { Die ("The pack $lastPack could not be read, so the plugin list of $tgtId is not known: " + $_.Exception.Message) }
        Say ("  {0}: {1}" -f (Get-Prop $p 'id'), $_.Exception.Message) 'Yellow'
        continue
    }
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        if ($isLast) {
            foreach ($n in 'plugins.txt', 'loadorder.txt') {
                $pe = $zip.GetEntry('profile/' + $n)
                if ($null -ne $pe) {
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($pe, (Join-Path (Join-Path $stage 'profile') $n), $true)
                    $profileFound += $n
                }
            }
        }
        foreach ($en in @($zip.Entries)) {
            if (-not $need.Count) { break }
            if (-not $en.FullName.StartsWith('game/') -or $en.FullName.EndsWith('/')) { continue }
            if (-not $sizes.Contains([int64]$en.Length)) { continue }
            $s = $en.Open()
            try { $key = ('{0}:{1}' -f $en.Length, (Get-BaselineStreamSha $s)) } finally { $s.Dispose() }
            if (-not $need.ContainsKey($key)) { continue }
            $zipEntry = $en
            Put-Staged $key { param($d) [IO.Compression.ZipFileExtensions]::ExtractToFile($zipEntry, $d, $true) }
        }
    } finally { $zip.Dispose() }
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Say ("  looked in {0}, {1} file(s) still wanted" -f (Get-Prop $p 'id'), (Get-WantedCount)) 'DarkGray'
}
if ($need.Count) {
    $missing = @($need.Values | ForEach-Object { $_ } | Sort-Object)
    Say ("  {0} file(s) of {1} are in no pack on the site:" -f $missing.Count, $tgtId) 'Red'
    foreach ($m in @($missing | Select-Object -First 12)) { Say "    $m" 'Red' }
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    Die ('They came with the installer and no update ever carried them, so the site does not hold their old bytes. ' +
         'Nothing was sent. Point -FilesFrom at a folder holding them (a game folder from before the release being undone), and run it again.')
}
if ($listMoved -and $profileFound -notcontains 'plugins.txt') {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    Die ("The plugin list differs between the feed now and $tgtId, and the pack $tgtId ended on carries none. Nothing was sent.")
}

# ------------------------------------------------------------ the pack
Head 'Building the pack'
if (-not $Id) { $Id = (Get-Date -Format 'yyyyMMdd-HHmm') + $(if ($Dev) { '-dev' } else { '' }) }
if (@($packs | Where-Object { (Get-Prop $_ 'id') -eq $Id }).Count) {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    Die "The feed already lists a pack $Id. Run it again in a minute."
}
$zipPath = Join-Path $WorkDir ("pack-$Id.zip")
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    # Removals first, the way Publish-Update puts them in the first part.
    if ($delete.Count) {
        $w = New-Object IO.StreamWriter ($zip.CreateEntry('delete.txt').Open())
        foreach ($d in $delete) { $w.WriteLine(($d -replace '\\', '/')) }
        $w.Dispose()
    }
    foreach ($rel in $write) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path (Join-Path $stage 'game') $rel), ('game/' + ($rel -replace '\\', '/')), 'Optimal')
    }
    Add-SourceNoticeToZip $zip (Get-SourceNoticeEntries $clientRecord $write 'pack' $licences)
    foreach ($n in $profileFound) {
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path (Join-Path $stage 'profile') $n), "profile/$n", 'Optimal')
    }
} finally { $zip.Dispose() }
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
$zipSha = Get-BaselineFileSha $zipPath
Say ("  pack-{0}.zip, {1:n1} MB" -f $Id, ((Get-Item -LiteralPath $zipPath).Length / 1MB)) 'Green'

& (Join-Path $Here '..\dev\Check-Secrets.ps1') -Zip @($zipPath)
if ($LASTEXITCODE -ne 0) { Die 'Something that must never ship is in the pack. The lines above name each file and rule. Nothing was sent.' }

$manifestPath = Join-Path $WorkDir ("manifest-$Id.json")
$manifestSha = Write-BaselineFile $newMap $manifestPath
$pointer = New-FeedBaselinePointer $Id $manifestSha (Get-HostFeedAssetUrl $manifestSha -Dev:$Dev) $newMap.Count
$packUrl = Get-HostFeedAssetUrl $zipSha -Dev:$Dev
if (-not (Test-FeedPackUrl $packUrl (Get-FeedRepo $doc))) { Die "The pack would be named at $packUrl, which a launcher cannot download. Nothing was sent." }

# ------------------------------------------------------------ the note
$when = Get-ReleaseWhen $tgtId
if (-not $Notes) {
    $Notes = ("The game files go back to the update of $when`n" +
              "- Everything the updates after it changed in the game folder is put back the way it was, and files they added are taken out.`n" +
              '- The launcher stays as it is.')
}
$noteLines = @($Notes -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$problems = @(Get-NoteProblems $Notes)
if (@($noteLines[0] -split '\s+' | Where-Object { $_ }).Count -lt 3) { $problems += 'the title needs at least three words' }
if (-not @($noteLines | Select-Object -Skip 1 | Where-Object { $_ -match '^[-*]\s*\S' }).Count) { $problems += 'the note needs at least one "- " line saying what a person will notice' }
if ($problems.Count) {
    foreach ($p in $problems) { Say "  $p" 'Red' }
    Die 'The note would go to the launcher, the site and Discord as it is. Rewrite it; nothing was sent.'
}

if ($DryRun) {
    Head 'Dry run'
    Say "  nothing was sent. The pack is $zipPath and the record $manifestPath." 'Yellow'
    Say ("  it would add pack {0} to the {1} feed and name what it installs ({2:n0} entries)." -f $Id, $Channel, $newMap.Count) 'Yellow'
    Write-Host ''
    exit 0
}

# ------------------------------------------------------------ send
Head 'Sending'
$sendArgs = @{ Dev = $Dev; Send = @($zipPath, $manifestPath); Quiet = $true }
if ($SiteDir) { $sendArgs['SiteDir'] = $SiteDir }
$global:LASTEXITCODE = 0
$why = ''
try { & (Join-Path $Here '..\deploy\Remirror-Site-Feed.ps1') @sendArgs } catch { $why = $_.Exception.Message }
if (-not $why -and $LASTEXITCODE -ne 0) { $why = "Remirror-Site-Feed.ps1 -Send exited $LASTEXITCODE" }
if ($why) { Die ("The pack or its record did not reach the site, so version.json has not been touched: $why") }
Say '  the pack and its record are on the site' 'Green'

$lastPackBefore = Get-FeedLastPackId $doc
$packs = @($packs) + [pscustomobject][ordered]@{ id = $Id; url = $packUrl; sha256 = $zipSha; notes = $Notes }
if ($doc.PSObject.Properties['packs']) { $doc.packs = $packs } else { $doc | Add-Member -NotePropertyName 'packs' -NotePropertyValue $packs }
[void](Add-FeedRelease $doc $pointer $Id $lastPackBefore $tgtId)
$doc.baseline = $pointer

$bullets = @($noteLines | Select-Object -Skip 1 | Where-Object { $_ -match '^[-*]\s*\S' } | ForEach-Object { ($_ -replace '^[-*]\s*', '').Trim() })
$body = (@($noteLines | Select-Object -Skip 1 | Where-Object { $_ -notmatch '^[-*]\s*\S' }) -join ' ').Trim()
$details = @($bullets)
if ($write.Count) { $details += ('{0:n0} file{1} to download, {2:n1} MB' -f $write.Count, $(if ($write.Count -eq 1) { '' } else { 's' }), ($writeBytes / 1MB)) }
$entry = [pscustomobject][ordered]@{ date = (Get-Date).ToString('M-d-yyyy h:mm tt', [Globalization.CultureInfo]::InvariantCulture); title = $noteLines[0]
                                     body = $body; details = $details; channel = $(if ($Dev) { 'dev' } else { '' }) }
$news = @()
if ($doc.PSObject.Properties['news'] -and $doc.news) { $news = @($doc.news) }
$news = @($entry) + $news
if ($news.Count -gt 40) { $news = @($news[0..39]) }
if ($doc.PSObject.Properties['news']) { $doc.news = $news } else { $doc | Add-Member -NotePropertyName 'news' -NotePropertyValue $news }

# No byte order mark: the launcher's reader stops on one (Publish-Update.ps1).
[IO.File]::WriteAllText($VersionFile, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
Copy-Item -LiteralPath $manifestPath -Destination $StateFile -Force
try { $sent = Send-FeedStore $Channel $ReleaseDir @('version.json', 'published.json') -SiteDir $SiteDir }
catch {
    Die ("The feed was not sent, so no launcher sees the rollback: " + $_.Exception.Message +
         ' The pack is on the site and nothing names it. Run this again; it starts from what is up there now.')
}

Head 'Done'
Say ("The {0} feed is back to {1}: every launcher on it takes pack {2} at its next check." -f $Channel, $tgtId, $Id) 'Green'
Say ("To put it forward again: .\scripts\release\Rollback-Feed.ps1 -Channel {0} -To {1}" -f $Channel, [string]$cur.id) 'Gray'
Say 'The server is not part of the feed. If the release undone changed the gamemode or the plugins the server loads, put the server back too.' 'Yellow'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
exit 0
