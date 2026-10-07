<#
  test-feed-rules.ps1

  No pack goes onto the update feed that a launcher cannot download, and the
  ones already there can be taken off.

  WHY THIS EXISTS. On 24 September 164 of the 227 packs on the live feed
  pointed at the private source repository, EvilPatrick06/Thornswood, which
  has no releases left: every one of them answers 404 to a launcher, with or
  without a token. Fresh installs only survive it because the installer seeds
  applied.txt. Entry 198 on the To Do List. Feed-Rules.ps1 holds the rule.

  Five things are checked, all against scratch files:
    the rule itself, in Feed-Rules.ps1;
    the block of Publish-Update.ps1 that adds packs to the feed, run on its own
      between its markers, so a pack uploaded anywhere else is refused and the
      feed is left as it was;
    that Publish-Update refuses the wrong repository before it uploads;
    Repair-Manifest.ps1 end to end, in a child PowerShell, on a scratch feed
      and a scratch applied.txt;
    and where Repair-Manifest looks for applied.txt when it is not given one,
      which is the install Publish-Update.ps1's Find-Root finds rather than
      C:\Thornswood every time.
  When the releases clone is on this machine, a COPY of its version.json is
  repaired too, to measure what the repair would do to the live feed. The
  clone and the live applied.txt are never written.

  Never connects to anything.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$here = Split-Path -Parent $here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

$rules = Join-Path $here 'scripts\release\Feed-Rules.ps1'
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
Yes 'a feed that names no repository has none: Thornswood-Releases is no default any more (#907)' ((Get-FeedRepo ([pscustomobject]@{ packs = @() })) -eq '')
Yes 'nonsense in updateRepo is not taken for a repository' ((Get-FeedRepo ([pscustomobject]@{ updateRepo = 'nope' })) -eq '')
Yes 'no feed at all has none either' ((Get-FeedRepo $null) -eq '')

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

$pubSrc = Get-Content -LiteralPath (Join-Path $here 'scripts\release\Publish-Update.ps1') -Raw
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
Yes 'a feed that names no updateRepo refuses a GitHub pack, since #907' (($r -like 'DIE *') -and -not $doc.PSObject.Properties['packs'])
$doc = [pscustomobject]@{ launcherVersion = '1.1.99' }
$r = Run-Append $doc @((Chunk 'N1' ('https://thornswood.net/feed/assets/' + ('1' * 64)))) $false
Yes 'and takes a pack on the site' (($r -eq 'ok') -and ((Ids $doc.packs) -eq 'N1'))

$doc = Feed
$r = Run-Append $doc @() $false
Yes 'a release with no packs still warns and adds nothing' (($r -eq 'ok') -and ((Ids $doc.packs) -eq 'old1,old2,new1') -and (($script:said -join "`n") -like '*2 pack(s)*'))

# ------------------------------------------------------------ GitHub browser addresses
# A feed that still names updateRepo (main until its next Ship after #907)
# keeps its browser download addresses legal until then.
function Dl([string]$repo, [string]$tag, [string]$name) { return "https://github.com/$repo/releases/download/$tag/$name" }
$dlPack = Dl $pub '20260927-0508' 'pack-N1.zip'
Yes 'a browser download address is one a launcher may download, while the feed names that repository' (Test-FeedPackUrl $dlPack $pub)
Yes 'and one in another repository still is not' (-not (Test-FeedPackUrl (Dl $priv '20260927-0508' 'pack-N1.zip') $pub))
Yes 'and on a feed that names no repository, no GitHub address is' (-not (Test-FeedPackUrl $dlPack (Get-FeedRepo ([pscustomobject]@{ packs = @() }))))

# ------------------------------------------------------------ Publish-Update, nothing to GitHub
Write-Host ''
Write-Host 'Publish-Update uploads nothing to GitHub (#907)'
$dot    = $pubSrc.IndexOf(". (Join-Path `$Here 'Feed-Rules.ps1')")
Yes 'Publish-Update dot-sources Feed-Rules.ps1' ($dot -ge 0)
Yes 'and has no GitHub release upload, no -AssetHost and no -Repo' (
    -not $pubSrc.Contains('gh release') -and -not $pubSrc.Contains('$AssetHost') -and ($pubSrc -notmatch '\[string\]\$Repo\b'))
Yes 'and takes updateRepo out of the feed it writes' ($pubSrc.Contains("PSObject.Properties.Remove('updateRepo')"))

# ------------------------------------------------------------ Repair-Manifest
Write-Host ''
Write-Host 'Repair-Manifest'

$ps = (Get-Process -Id $PID).Path
$repair = Join-Path $here 'scripts\release\Repair-Manifest.ps1'
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
    # This machine's working copy of the live feed (Feed-Store.ps1, #907).
    $clone = ''
    $cand = Join-Path $env:LOCALAPPDATA 'Thornswood\feed\main'
    if (Test-Path -LiteralPath (Join-Path $cand 'version.json')) { $clone = $cand }
    if (-not $clone) {
        Write-Host 'SKIP  no live feed received on this machine, so it was not measured'
    } else {
        $liveDir = Join-Path $work 'live'
        New-Item -ItemType Directory -Path $liveDir -Force | Out-Null
        $cloneHash = (Get-FileHash -LiteralPath (Join-Path $clone 'version.json')).Hash
        Copy-Item -LiteralPath (Join-Path $clone 'version.json') -Destination (Join-Path $liveDir 'version.json')
        $live = Read-Feed (Join-Path $liveDir 'version.json')
        $liveRepo = Get-FeedRepo $live
        $ls = Split-FeedPacks $live.packs $liveRepo
        $total = @($live.packs).Count
        Write-Host ("      the live feed received here: {0} packs, {1} a launcher can download, {2} it cannot" -f $total, $ls.Keep.Count, $ls.Drop.Count)
        $liveApplied = Join-Path $work 'live-applied.txt'
        $r = Run-Repair @('-RepoDir', $liveDir, '-AppliedFile', $liveApplied, '-NoPush', '-NoPause')
        $fixed = Read-Feed (Join-Path $liveDir 'version.json')
        Yes ("a copy of the live feed repairs to the {0} downloadable packs" -f $ls.Keep.Count) (($r.Code -eq 0) -and (@($fixed.packs).Count -eq $ls.Keep.Count))
        Yes 'and every one left is one a launcher can download' (@($fixed.packs | Where-Object { -not (Test-FeedPackUrl $_.url $liveRepo) }).Count -eq 0)
        Yes 'the working copy itself was not written' ((Get-FileHash -LiteralPath (Join-Path $clone 'version.json')).Hash -eq $cloneHash)
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------- where applied.txt is looked for
#
# The repair settles the dead pack ids in this machine's applied.txt as well,
# or the launcher here keeps the update card up until the repaired feed comes
# back down. It used to reach for C:\Thornswood and nothing else, so on a
# machine whose launcher is on another drive it wrote nothing and said nothing.
# It now finds the install the way Publish-Update.ps1 does, and the two
# functions are held identical here rather than left to drift apart.
#
# Find-Root is lifted out of each script by the parser and driven with
# Test-Path and Get-PSDrive shadowed, so nothing is read off this machine and
# the answer does not depend on which drives it has.
Write-Host ''
Write-Host 'where applied.txt is looked for'

$pubUpd = Join-Path $here 'scripts\release\Publish-Update.ps1'
function Get-Fn([string]$path, [string]$name) {
    $t = $null; $e = $null
    $a = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $path).Path, [ref]$t, [ref]$e)
    $hit = @($a.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true))
    if ($hit.Count -ne 1) { return '' }
    return $hit[0].Extent.Text
}
function Get-Ast([string]$path) {
    $t = $null; $e = $null
    return [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $path).Path, [ref]$t, [ref]$e)
}
$repairFind = Get-Fn $repair 'Find-Root'
$publishFind = Get-Fn $pubUpd 'Find-Root'
Yes 'Repair-Manifest.ps1 has a Find-Root' ($repairFind -ne '')
Yes 'Publish-Update.ps1 still has the one it is copied from' ($publishFind -ne '')
function Flat([string]$s) { return (($s -replace '\s+', ' ').Trim()) }
Yes 'and the two are the same function, word for word' (($repairFind -ne '') -and ((Flat $repairFind) -eq (Flat $publishFind)))

# No install path is written into the script any more outside that function.
# By the parser, over string literals only, so the paragraph above Find-Root
# that explains the rule in words is not mistaken for one.
if ($repairFind -ne '') {
    $rast = Get-Ast $repair
    $fn = @($rast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Find-Root' }, $true))[0]
    $roots = @($rast.FindAll({
        param($n)
        ($n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
         $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
        ($n.Value -match '(?i)^[a-z]:\\Thornswood')
    }, $true))
    $outside = @($roots | Where-Object { $_.Extent.StartOffset -lt $fn.Extent.StartOffset -or $_.Extent.EndOffset -gt $fn.Extent.EndOffset })
    Yes 'no install folder is written into the script outside Find-Root' ($outside.Count -eq 0)
    foreach ($o in $outside) { Write-Host ("      line {0}: {1}" -f $o.Extent.StartLineNumber, $o.Extent.Text) }

    $rsrc = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $repair).Path)
    $rest = $rsrc.Replace($repairFind, '')
    Yes 'the default applied.txt is built from it, plus -DevBuild on the dev channel' (
        ($rest -match '\$root = Find-Root') -and ($rest -match "'-DevBuild'") -and ($rest -match "Profile.applied\.txt"))
}

# Runs the lifted Find-Root against made up drives. Test-Path answers only for
# the paths given, so a launcher is where this says it is and nowhere else.
# Get-PSDrive gives the drives asked for, and Join-Path joins with a backslash
# whatever this machine's separator is, because Join-Path on Linux refuses a
# path on a drive called C. So the answers below are the same in the cloud and
# on the VPS, and none of them is read off the machine running this.
function Run-FindRoot([string]$text, [string[]]$has, [string[]]$roots) {
    $head = @'
param($has, $roots)
function Test-Path { param([string]$LiteralPath) return ($has -contains $LiteralPath) }
function Get-PSDrive { param([string]$PSProvider) return @($roots | ForEach-Object { [pscustomobject]@{ Root = $_ } }) }
function Join-Path { param([string]$Path, [string]$ChildPath) return ($Path.TrimEnd('\', '/') + '\' + $ChildPath) }
'@
    return [string](& ([scriptblock]::Create($head + "`n" + $text + "`nFind-Root")) $has $roots)
}
if ($repairFind -ne '') {
    $onC = 'C:\Thornswood'
    $onD = 'D:\Thornswood'
    $drives = @('C:\', 'D:\', '/')

    Yes 'the launcher on C: is found first' ((Run-FindRoot $repairFind @($onC + '\Launcher\Thornswood.exe') $drives) -eq $onC)
    Yes 'a launcher on another drive is found when C: has none' ((Run-FindRoot $repairFind @($onD + '\Launcher\Thornswood.exe') $drives) -eq $onD)
    Yes 'no launcher anywhere falls back to C:, so the message names a real place' ((Run-FindRoot $repairFind @() $drives) -eq $onC)
    Yes 'a drive whose root is not a letter is not tried' ((Run-FindRoot $repairFind @('\Thornswood\Launcher\Thornswood.exe') @('/')) -eq $onC)
    Yes 'Publish-Update answers the same, on the same drives' ((Run-FindRoot $publishFind @($onD + '\Launcher\Thornswood.exe') $drives) -eq $onD)
}


# Sync-Client, Go and Deploy-Gamemode find the install the same way now (#546).
# Their Find-Root is the Publish-Update one word for word, and each fills its
# path default from it when the caller did not pass one. No shared helper yet.
$sync = Join-Path $here 'scripts\release\Sync-Client.ps1'
$go = Join-Path $here 'scripts\release\Go.ps1'
$deploy = Join-Path $here 'scripts\deploy\Deploy-Gamemode.ps1'
$syncFind = Get-Fn $sync 'Find-Root'
$goFind = Get-Fn $go 'Find-Root'
$deployFind = Get-Fn $deploy 'Find-Root'
Yes 'Sync-Client.ps1 has a Find-Root' ($syncFind -ne '')
Yes 'Go.ps1 has a Find-Root' ($goFind -ne '')
Yes 'Deploy-Gamemode.ps1 has a Find-Root' ($deployFind -ne '')
Yes 'Sync-Client Find-Root matches Publish-Update' (($syncFind -ne '') -and ((Flat $syncFind) -eq (Flat $publishFind)))
Yes 'Go Find-Root matches Publish-Update' (($goFind -ne '') -and ((Flat $goFind) -eq (Flat $publishFind)))
Yes 'Deploy-Gamemode Find-Root matches Publish-Update' (($deployFind -ne '') -and ((Flat $deployFind) -eq (Flat $publishFind)))
$syncSrc = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $sync).Path)
$goSrc = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $go).Path)
$deploySrc = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $deploy).Path)
Yes 'Sync-Client fills -Game from Find-Root when it was not passed' (
    $syncSrc -match "ContainsKey\('Game'\)" -and $syncSrc -match 'Join-Path \(Find-Root\) ''Game''')
Yes 'Go fills -Game from Find-Root when neither -Game nor -Vortex was passed' (
    $goSrc.Contains('-not $Vortex -and -not $PSBoundParameters.ContainsKey') -and
    $goSrc -match 'Join-Path \(Find-Root\) ''Game''')
Yes 'Deploy-Gamemode fills -Data and -Plugins from Find-Root when not passed' (
    $deploySrc -match "ContainsKey\('Data'\)" -and $deploySrc -match "ContainsKey\('Plugins'\)" -and
    $deploySrc -match "Join-Path \(Find-Root\) 'Game\\Data'" -and
    $deploySrc -match "Join-Path \(Find-Root\) 'Profile\\Default\\plugins\.txt'")
$onD2 = 'D:\Thornswood'
$drives2 = @('C:\', 'D:\', '/')
if ($syncFind -ne '') {
    Yes 'Sync-Client Find-Root answers the same on another drive' ((Run-FindRoot $syncFind @($onD2 + '\Launcher\Thornswood.exe') $drives2) -eq $onD2)
}

# A Dev Ship reads main's feed as the site serves it before it writes
# mainVersion, so the Dev News tab cannot keep showing a stale main (1.1.37
# while main had moved on; #546). Until #907 that was main's releases clone,
# pulled first. Since 6 Oct the marks and mainVersion are written by
# Set-DevFeedMarks in Dev-News.ps1, which a dev publish calls here and a
# publish with nothing new and a main Ship reach through Update-DevFeedMarks.
$puSrc = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $pubUpd).Path)
$mainPull = [regex]::Match($puSrc, '(?s)\$mainDoc = \$null\s+try \{ \$mainDoc = Read-SiteFeed.*?Set-DevFeedMarks \$doc \$mainDoc \$RepoDir.*?\r?\n\}')
Yes 'the Dev mainVersion block is still in Publish-Update' $mainPull.Success
if ($mainPull.Success) {
    $block = $mainPull.Value
    Yes 'it reads main''s feed from the site, fresh, not a clone on this disk' (
        $block.Contains("Read-SiteFeed 'main'") -and -not $block.Contains('Thornswood-Releases''') -and -not $block.Contains('git -C'))
    Yes 'a feed that cannot be read leaves the dev marks alone rather than shipping a stale mainVersion' (
        $block -match "could not read main's feed, so the dev marks were left alone")
}
$devNewsSrc = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $pubUpd) 'Dev-News.ps1'))
$setMarks = [regex]::Match($devNewsSrc, '(?s)function Set-DevFeedMarks.*?\r?\n\}')
Yes 'Set-DevFeedMarks writes mainVersion from main''s launcherVersion' (
    $setMarks.Success -and $setMarks.Value -match [regex]::Escape("`$mainVer = Get-DevNewsVal `$mainDoc 'launcherVersion'") -and
    $setMarks.Value -match [regex]::Escape("Set-DevNewsProp `$doc 'mainVersion' `$mainVer"))
$updMarks = [regex]::Match($devNewsSrc, '(?s)function Update-DevFeedMarks.*?\r?\n\}')
Yes 'and a refresh with nothing new reads main''s feed from the site too' (
    $updMarks.Success -and $updMarks.Value.Contains("Read-SiteFeed 'main'") -and -not $updMarks.Value.Contains('git -C'))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
