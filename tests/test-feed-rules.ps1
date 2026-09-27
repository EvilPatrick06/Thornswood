<#
  test-feed-rules.ps1

  No pack goes onto the update feed that a launcher cannot download, and the
  ones already there can be taken off.

  WHY THIS EXISTS. On 24 September 164 of the 227 packs on the live feed
  pointed at the private source repository, EvilPatrick06/Thornswood, which
  has no releases left: every one of them answers 404 to a launcher, with or
  without a token. Fresh installs only survive it because the installer seeds
  applied.txt. Entry 198 on the To Do List. Feed-Rules.ps1 holds the rule.

  Four things are checked, all against scratch files:
    the rule itself, in Feed-Rules.ps1;
    the block of Publish-Update.ps1 that adds packs to the feed, run on its own
      between its markers, so a pack uploaded anywhere else is refused and the
      feed is left as it was;
    that Publish-Update refuses the wrong repository before it uploads;
    Repair-Manifest.ps1 end to end, in a child PowerShell, on a scratch feed
      and a scratch applied.txt.
  When the releases clone is on this machine, a COPY of its version.json is
  repaired too, to measure what the repair would do to the live feed. The
  clone and the live applied.txt are never written.

  Never connects to anything.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$here = Join-Path (Split-Path -Parent $here) 'tools'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

$rules = Join-Path $here '..\scripts\release\Feed-Rules.ps1'
if (-not (Test-Path -LiteralPath $rules)) {
    Write-Host 'FAIL  Feed-Rules.ps1 is not in tools' -ForegroundColor Red
    Write-Host ''
    Write-Host '0 passed, 1 failed'
    exit 1
}
. $rules

$pub  = 'EvilPatrick06/Thornswood-Releases'
$priv = 'EvilPatrick06/Thornswood'
function Api([string]$repo, [string]$n) { return "https://api.github.com/repos/$repo/releases/assets/$n" }
function P([string]$id, $url) {
    $o = [pscustomobject]@{ id = $id; sha256 = ('0' * 64); notes = "pack $id" }
    if ($null -ne $url) { $o | Add-Member -NotePropertyName url -NotePropertyValue $url }
    return $o
}
function Ids($list) { return ((@($list) | ForEach-Object { [string]$_.id }) -join ',') }

# ------------------------------------------------------------ the rule
Write-Host ''
Write-Host 'the rule'

Yes 'the feed says which repository it is read from' ((Get-FeedRepo ([pscustomobject]@{ updateRepo = $pub })) -eq $pub)
Yes 'a feed that does not say is read from the one Config.cs gives a fresh install' ((Get-FeedRepo ([pscustomobject]@{ packs = @() })) -eq $pub)
Yes 'nonsense in updateRepo is not taken for a repository' ((Get-FeedRepo ([pscustomobject]@{ updateRepo = 'nope' })) -eq $pub)
Yes 'no feed at all falls back the same way' ((Get-FeedRepo $null) -eq $pub)

Yes 'a private source asset names the source repository' ((Get-FeedPackRepo (Api $priv '556583849')) -eq $priv)
Yes 'a public asset names the public repository' ((Get-FeedPackRepo (Api $pub '585078233')) -eq $pub)
Yes 'the browser address of an asset counts too' ((Get-FeedPackRepo "https://github.com/$pub/releases/download/20260923-2137/pack-20260923-2137.zip") -eq $pub)
Yes 'an empty url names nothing' ((Get-FeedPackRepo '') -eq '')
Yes 'plain http names nothing' ((Get-FeedPackRepo ("http://api.github.com/repos/$pub/releases/assets/1")) -eq '')
Yes 'another host with the same path names nothing' ((Get-FeedPackRepo ("https://evil.example/repos/$pub/releases/assets/1")) -eq '')
Yes 'a host that only starts with api.github.com names nothing' ((Get-FeedPackRepo ("https://api.github.com.evil.example/repos/$pub/releases/assets/1")) -eq '')
Yes 'a query string cannot smuggle the right name in' ((Get-FeedPackRepo ((Api $priv '1') + "?r=/repos/$pub/releases/assets/1")) -eq '')
Yes 'the source tree of a repository is not a release asset' ((Get-FeedPackRepo "https://api.github.com/repos/$pub/contents/version.json") -eq '')

Yes 'a public asset is downloadable' (Test-FeedPackUrl (Api $pub '1') $pub)
Yes 'names are not case sensitive, the way GitHub reads them' (Test-FeedPackUrl (Api 'evilpatrick06/thornswood-releases' '1') $pub)
Yes 'a private source asset is not' (-not (Test-FeedPackUrl (Api $priv '1') $pub))
Yes 'nor is a longer name that starts the same' (-not (Test-FeedPackUrl (Api "$pub-old" '1') $pub))
Yes 'nor is an empty url' (-not (Test-FeedPackUrl '' $pub))
Yes 'nor is anything when no repository is named' (-not (Test-FeedPackUrl (Api $pub '1') ''))
Yes 'but a host feed asset does not need updateRepo' (Test-FeedPackUrl ("https://thornswood.net/feed/assets/$('b'*64)") '')

$mixed = @(
    (P 'A' (Api $priv '10')),
    (P 'B' (Api $pub '11')),
    (P 'C' ''),
    (P 'D' $null),
    (P 'E' (Api $priv '12')),
    (P 'F' "https://github.com/$pub/releases/download/F/pack-F.zip"),
    $null,
    (P 'G' (Api $pub '13'))
)
$s = Split-FeedPacks $mixed $pub
Yes 'kept: the public ones, in feed order' ((Ids $s.Keep) -eq 'B,F,G')
Yes 'dropped: the rest, in feed order' ((Ids ($s.Drop | ForEach-Object { $_.Pack })) -eq 'A,C,D,E')
Yes 'a null entry is on neither side' (($s.Keep.Count + $s.Drop.Count) -eq 7)
Yes 'a private one says where it is' (($s.Drop[0].Why -like "*held in $priv*") -and ($s.Drop[0].Repo -eq $priv))
Yes 'an empty one says it had no url' ($s.Drop[1].Why -eq 'published with no url')
Yes 'and so does one with no url field at all' ($s.Drop[2].Why -eq 'published with no url')
$one = Split-FeedPacks @((P 'Z' (Api $pub '1'))) $pub
Yes 'one pack comes back as a list of one, which strict mode can count' (($one.Keep.Count -eq 1) -and ($one.Drop.Count -eq 0))
$none = Split-FeedPacks @() $pub
Yes 'an empty feed splits into two empty lists' (($none.Keep.Count -eq 0) -and ($none.Drop.Count -eq 0))


# ------------------------------------------------------------ host feed assets (#649)
Write-Host ''
Write-Host 'host feed assets'

$sha = 'a' * 64
$hostLive = "https://thornswood.net/feed/assets/$sha"
$hostDev  = "https://thornswood.net/feed-dev/assets/$sha"
$hostSub  = "https://cdn.thornswood.net/feed/assets/$sha"

Yes 'a live host feed asset is downloadable' (Test-FeedPackUrl $hostLive $pub)
Yes 'a dev host feed asset is downloadable' (Test-FeedPackUrl $hostDev $pub)
Yes 'a subdomain host feed asset is downloadable' (Test-FeedPackUrl $hostSub $pub)
Yes 'Test-HostFeedAssetUrl accepts the live shape' (Test-HostFeedAssetUrl $hostLive)
Yes 'Test-HostFeedAssetUrl accepts the dev shape' (Test-HostFeedAssetUrl $hostDev)
Yes 'Get-HostFeedAssetUrl builds the live url' ((Get-HostFeedAssetUrl $sha) -eq $hostLive)
Yes 'Get-HostFeedAssetUrl -Dev builds the dev url' ((Get-HostFeedAssetUrl $sha -Dev) -eq $hostDev)
Yes 'Get-HostFeedVersionUrl is the live version.json' ((Get-HostFeedVersionUrl) -eq 'https://thornswood.net/feed/version.json')
Yes 'Get-HostFeedVersionUrl -Dev is the dev version.json' ((Get-HostFeedVersionUrl -Dev) -eq 'https://thornswood.net/feed-dev/version.json')
Yes 'a short hash is not a host feed asset' (-not (Test-HostFeedAssetUrl "https://thornswood.net/feed/assets/abcd"))
Yes 'a wrong path on thornswood.net is not' (-not (Test-HostFeedAssetUrl "https://thornswood.net/files/$sha"))
Yes 'plain http on thornswood.net is not' (-not (Test-HostFeedAssetUrl ("http://thornswood.net/feed/assets/$sha")))
Yes 'a lookalike host is not' (-not (Test-HostFeedAssetUrl "https://thornswood.net.evil.example/feed/assets/$sha"))
Yes 'private source GitHub assets still refuse' (-not (Test-FeedPackUrl (Api $priv '1') $pub))
Yes 'random hosts still refuse' (-not (Test-FeedPackUrl "https://evil.example/feed/assets/$sha" $pub))

$hostMixed = @(
    (P 'H1' $hostLive),
    (P 'G1' (Api $pub '11')),
    (P 'B1' (Api $priv '10')),
    (P 'H2' $hostDev)
)
$hs = Split-FeedPacks $hostMixed $pub
Yes 'kept: host assets and public GitHub, in feed order' ((Ids $hs.Keep) -eq 'H1,G1,H2')
Yes 'dropped: private source only' ((Ids ($hs.Drop | ForEach-Object { $_.Pack })) -eq 'B1')

# ------------------------------------------------------------ Publish-Update, adding packs
Write-Host ''
Write-Host 'Publish-Update adding packs'

$pubSrc = Get-Content -LiteralPath (Join-Path $here '..\scripts\release\Publish-Update.ps1') -Raw
$a = $pubSrc.IndexOf('# ==== thornswood feed append ====')
$b = $pubSrc.IndexOf('# ==== end thornswood feed append ====')
Yes 'the feed append block is marked in Publish-Update.ps1' (($a -ge 0) -and ($b -gt $a))
$block = ''
if ($a -ge 0 -and $b -gt $a) { $block = $pubSrc.Substring($a, $b - $a) }

# The two helpers the block uses, as Publish-Update.ps1 defines them.
function Set-Prop($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}
function Val($o, [string]$k) {
    if ($null -ne $o -and $o.PSObject.Properties.Name -contains $k) { return [string]$o.$k }
    return ''
}

# Runs the block with Say collected and Die turned into an exception, which is
# what stopping the script before version.json is written amounts to here.
function Run-Append($doc, $chunks, [bool]$Dev) {
    $script:said = @()
    function Say($m, $c = 'Gray') { $script:said += [string]$m }
    function Die($m) { throw ('DIE ' + $m) }
    $Notes = 'test notes'
    if (-not $block) { return 'no block' }
    try { Invoke-Expression $block; return 'ok' }
    catch { return $_.Exception.Message }
}
function Chunk([string]$id, [string]$url) { return [pscustomobject]@{ Id = $id; Path = ''; Sha = ('1' * 64); Url = $url } }
function Feed() {
    return [pscustomobject]@{
        launcherVersion = '1.1.99'
        packs = @((P 'old1' (Api $priv '1')), (P 'old2' (Api $priv '2')), (P 'new1' (Api $pub '3')))
        updateRepo = $pub
    }
}

$doc = Feed
$r = Run-Append $doc @((Chunk 'N1' (Api $pub '900'))) $false
Yes 'a pack in the public repository is added' (($r -eq 'ok') -and ((Ids $doc.packs) -eq 'old1,old2,new1,N1'))
Yes 'and what is already on the feed is left alone' ($doc.packs[0].url -eq (Api $priv '1'))
$warn = ($script:said -join "`n")
Yes 'the packs no launcher can download are counted' ($warn -like '*2 pack(s) already on the feed cannot be downloaded*')
Yes 'with the first and last of them' ($warn -like '*old1 to old2*')
Yes 'where they are' ($warn -like "*held in $priv*")
Yes 'and what takes them out' ($warn -like '*Repair-Manifest.ps1 -DryRun*')
Yes 'the main feed is not sent to the dev repair' (-not ($warn -like '*-Channel dev*'))

$doc = Feed
$r = Run-Append $doc @((Chunk 'N1' (Api $pub '900'))) $true
Yes 'a dev publish names the dev repair' (($script:said -join "`n") -like '*Repair-Manifest.ps1 -Channel dev -DryRun*')

$doc = Feed
$r = Run-Append $doc @((Chunk 'N1' (Api $priv '900'))) $false
Yes 'a pack uploaded to the private repository is refused' ($r -like 'DIE *')
Yes 'and version.json is not added to' ((Ids $doc.packs) -eq 'old1,old2,new1')
Yes 'and the refusal says where it went' (($script:said -join "`n") -like ('*pack-N1.zip is at ' + (Api $priv '900') + '*'))

$doc = Feed
$r = Run-Append $doc @((Chunk 'N1-1' (Api $pub '901')), (Chunk 'N1-2' (Api "$pub-old" '902'))) $false
Yes 'one bad part refuses the whole release, not half of it' (($r -like 'DIE *') -and ((Ids $doc.packs) -eq 'old1,old2,new1'))

$doc = Feed
$r = Run-Append $doc @((Chunk 'N1' "https://evil.example/repos/$pub/releases/assets/903")) $false
Yes 'a pack on another host is refused' ($r -like 'DIE *')

# -NoUpload, and a failed upload, leave the url empty. That is the later check's
# business, which writes the file and stops before the push; it is not moved.
$doc = Feed
$r = Run-Append $doc @((Chunk 'N1' '')) $false
Yes 'a pack with no url yet is left to the check that already stops it' (($r -eq 'ok') -and ((Ids $doc.packs) -eq 'old1,old2,new1,N1'))

$doc = [pscustomobject]@{ packs = @((P 'new1' (Api $pub '3'))); updateRepo = $pub }
$r = Run-Append $doc @((Chunk 'N1' (Api $pub '900'))) $false
Yes 'a clean feed says nothing about stale packs' (($r -eq 'ok') -and -not (($script:said -join "`n") -like '*cannot be downloaded*'))

$doc = [pscustomobject]@{ launcherVersion = '1.1.99' }
$r = Run-Append $doc @((Chunk 'N1' (Api $pub '900'))) $false
Yes 'a feed with no packs and no updateRepo takes a public pack' (($r -eq 'ok') -and ((Ids $doc.packs) -eq 'N1'))

$doc = Feed
$r = Run-Append $doc @() $false
Yes 'a release with no packs still warns and adds nothing' (($r -eq 'ok') -and ((Ids $doc.packs) -eq 'old1,old2,new1') -and (($script:said -join "`n") -like '*2 pack(s)*'))

# ------------------------------------------------------------ Publish-Update, before uploading
Write-Host ''
Write-Host 'Publish-Update before it uploads'
$dot    = $pubSrc.IndexOf(". (Join-Path `$Here 'Feed-Rules.ps1')")
$guard  = $pubSrc.IndexOf('[string]::Equals($Repo, $feedRepo')
$upload = $pubSrc.IndexOf('& gh release create')
Yes 'Publish-Update dot-sources Feed-Rules.ps1' ($dot -ge 0)
Yes 'and compares the upload repository with the feed''s' (($guard -gt $dot) -and ($dot -ge 0))
Yes 'before anything is uploaded' (($guard -ge 0) -and ($upload -gt $guard))
$tail = ''
if ($guard -ge 0) { $tail = $pubSrc.Substring($guard, [Math]::Min(400, $pubSrc.Length - $guard)) }
Yes 'and stops when they differ' ($tail -match '\bDie\b')

# ------------------------------------------------------------ Repair-Manifest
Write-Host ''
Write-Host 'Repair-Manifest'

$ps = (Get-Process -Id $PID).Path
$repair = Join-Path $here '..\scripts\release\Repair-Manifest.ps1'
function Run-Repair([string[]]$more) {
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $repair) + $more
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    # Joined line by line rather than through Out-String, which can wrap a
    # long line at the console width and split the text being looked for.
    try { $out = (@(& $ps @args2 2>&1) | ForEach-Object { [string]$_ }) -join "`n" } finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
function Write-Feed([string]$path, $doc) {
    [IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
}
function Read-Feed([string]$path) {
    # A byte order mark is stepped over, spelt as a char so this file stays ASCII.
    return ((Get-Content -LiteralPath $path -Raw) -replace ('^' + [char]0xFEFF), '') | ConvertFrom-Json
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-feed-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    $feedFile = Join-Path $work 'version.json'
    $appliedFile = Join-Path $work 'applied.txt'
    Write-Feed $feedFile ([pscustomobject]@{
        launcherVersion = '1.1.99'
        packs = @((P 'A' (Api $priv '10')), (P 'B' (Api $pub '11')), (P 'C' ''), (P 'D' (Api $priv '12')), (P 'E' (Api $pub '13')))
        news = @([pscustomobject]@{ title = 'Kept'; details = @('one', 'two') })
        updateRepo = $pub
    })
    [IO.File]::WriteAllLines($appliedFile, [string[]]@('A', 'B'))
    $before = [IO.File]::ReadAllBytes($feedFile)

    $r = Run-Repair @('-RepoDir', $work, '-AppliedFile', $appliedFile, '-DryRun', '-NoPause')
    Yes 'a dry run finishes' ($r.Code -eq 0)
    Yes 'and says what it would do' ($r.Out -like '*would keep 2 pack(s) and drop 3*')
    Yes 'and names where the private ones are' ($r.Out -like "*2 pack(s) held in $priv*A to D*")
    Yes 'and the one with no url' ($r.Out -like '*1 pack(s) published with no url*')
    Yes 'and writes nothing' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($feedFile)) -eq [Convert]::ToBase64String($before))
    Yes 'not even applied.txt' (((Get-Content -LiteralPath $appliedFile) -join ',') -eq 'A,B')

    $r = Run-Repair @('-RepoDir', $work, '-AppliedFile', $appliedFile, '-NoPush', '-NoPause')
    Yes 'the repair finishes' ($r.Code -eq 0)
    $after = Read-Feed $feedFile
    Yes 'the feed keeps only the public packs, in order' ((Ids $after.packs) -eq 'B,E')
    Yes 'every pack left downloads from the public repository' (@($after.packs | Where-Object { -not (Test-FeedPackUrl $_.url $pub) }).Count -eq 0)
    Yes 'the rest of the feed is untouched' (($after.launcherVersion -eq '1.1.99') -and ($after.updateRepo -eq $pub) -and ($after.news[0].title -eq 'Kept') -and (@($after.news[0].details).Count -eq 2))
    $bytes = [IO.File]::ReadAllBytes($feedFile)
    Yes 'and it is written with no byte order mark' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    Yes 'the dropped ids are settled in applied.txt, once each' (((Get-Content -LiteralPath $appliedFile) -join ',') -eq 'A,B,C,D')
    Yes 'and it says it was not pushed' ($r.Out -like '*Not pushed, as asked*')

    $r = Run-Repair @('-RepoDir', $work, '-AppliedFile', $appliedFile, '-NoPush', '-NoPause')
    Yes 'run again, there is nothing to repair' (($r.Code -eq 0) -and ($r.Out -like "*every pack downloads from $pub*"))

    $r = Run-Repair @('-RepoDir', (Join-Path $work 'nowhere'), '-AppliedFile', $appliedFile, '-DryRun', '-NoPause')
    Yes 'no feed where it looks stops it, and says where it looked' (($r.Code -ne 0) -and ($r.Out -like '*nowhere*version.json*'))

    # ---- the live feed, measured on a copy
    $clone = ''
    try {
        $common = (& git -C $here rev-parse --path-format=absolute --git-common-dir 2>$null | Out-String).Trim()
        if ($common) {
            $cand = Join-Path (Split-Path -Parent (Split-Path -Parent $common)) 'Thornswood-Releases'
            if (Test-Path -LiteralPath (Join-Path $cand 'version.json')) { $clone = $cand }
        }
    } catch { $clone = '' }
    if (-not $clone) {
        Write-Host 'SKIP  no releases clone beside this repository, so the live feed was not measured'
    } else {
        $liveDir = Join-Path $work 'live'
        New-Item -ItemType Directory -Path $liveDir -Force | Out-Null
        $cloneHash = (Get-FileHash -LiteralPath (Join-Path $clone 'version.json')).Hash
        Copy-Item -LiteralPath (Join-Path $clone 'version.json') -Destination (Join-Path $liveDir 'version.json')
        $live = Read-Feed (Join-Path $liveDir 'version.json')
        $liveRepo = Get-FeedRepo $live
        $ls = Split-FeedPacks $live.packs $liveRepo
        $total = @($live.packs).Count
        Write-Host ("      the releases clone's feed: {0} packs, {1} a launcher can download from {2}, {3} it cannot" -f $total, $ls.Keep.Count, $liveRepo, $ls.Drop.Count)
        $liveApplied = Join-Path $work 'live-applied.txt'
        $r = Run-Repair @('-RepoDir', $liveDir, '-AppliedFile', $liveApplied, '-NoPush', '-NoPause')
        $fixed = Read-Feed (Join-Path $liveDir 'version.json')
        Yes ("a copy of the live feed repairs to the {0} downloadable packs" -f $ls.Keep.Count) (($r.Code -eq 0) -and (@($fixed.packs).Count -eq $ls.Keep.Count))
        Yes 'and every one left is in the repository the feed is read from' (@($fixed.packs | Where-Object { -not (Test-FeedPackUrl $_.url $liveRepo) }).Count -eq 0)
        Yes 'the clone itself was not written' ((Get-FileHash -LiteralPath (Join-Path $clone 'version.json')).Hash -eq $cloneHash)
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
