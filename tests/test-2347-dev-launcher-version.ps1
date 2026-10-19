<#
  test-2347-dev-launcher-version.ps1

  A dev launcher carries main's number only when it is main's launcher.

  MEASURED 12 OCTOBER. Dev Ship 20261012-004958-dev ran from a clean checkout
  of origin/main, 9ec48194. Main had published 1.2.3 from 7cece557, and the
  main feed recorded that launcher's fingerprint as launcherInputs a5035b57...
  #2343 had changed launcher\app\OwnGame.cs since, so the fingerprint of
  9ec48194 is 0b5ba66b... (both worked out with Ship's own
  Get-LauncherInputHash over checkouts of the two commits). Ship took main's
  number anyway, because a clean checkout of origin/main always did, built and
  signed the new launcher and sent it to the dev feed as 1.2.3. Every dev
  launcher already on 1.2.3 was never offered it, and Publish-Update said so
  only afterwards, in a WARNING.

  This lifts the whole of Ship's launcher and version choice, from where it
  works out whether this is main's own launcher to the line that writes the
  number, out of the shipped Ship.ps1, and drives it against feeds on disk the
  way the real Feed-Store.ps1 reads them (THORNSWOOD_TEST_SITE_DIR):
    <site>\feed\version\00000001.json     what main offers now (the feed's
                                          newest generation, #2727)
    <site>\feed-dev\version\00000001.json what dev offers now
    <site>\feed-dev\launchers.txt    every dev number ever published
  It carries the launcher's own IsNewer, so "offered" means what a launcher
  would do. Each run answers the number Ship chose and whether it builds a
  launcher at all, or the sentence it stopped with. A stop here is before
  anything is built, signed or sent: the cut ends before the version is
  written into Updater.cs.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
if (-not $ShipPath) { $ShipPath = Join-Path $repo 'scripts\release\Ship.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host "$script:pass passed, $script:fail failed"
    exit $(if ($script:fail) { 1 } else { 0 })
}

# ---- lift the choice out of the shipped script --------------------------------
$src = [IO.File]::ReadAllText($ShipPath)
$t = $null; $e = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($src, [ref]$t, [ref]$e)
Yes 'Ship.ps1 parses' (@($e).Count -eq 0)
$fns = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)) { $fns[$f.Name] = $f.Extent.Text }
$want = 'Get-PublishedLauncher', 'Test-LauncherUnchanged', 'Get-DevLauncherLine', 'Test-KeepFeedLauncher', 'Assert-DevVersionSelection', 'Get-LauncherInputHash'
foreach ($n in $want) { Yes "Ship.ps1 has $n" ($fns.ContainsKey($n)) }
foreach ($n in $want) { if (-not $fns.ContainsKey($n)) { Done } }

$from = $src.IndexOf('$MainEquivalent = $false')
$to = if ($from -ge 0) { $src.IndexOf('if ($target -ne $current) {', $from) } else { -1 }
Yes 'the launcher and version choice is in Ship.ps1, main''s own launcher first' ($from -ge 0 -and $to -gt $from)
if ($from -lt 0 -or $to -lt 0) { Done }
$region = $src.Substring($from, $to - $from)
$iHash = $src.IndexOf('$LauncherInputs = Get-LauncherInputHash $RepoDir')
Yes '  worked out after the fingerprint' ($iHash -ge 0 -and $iHash -lt $from)
$iBuild = $src.IndexOf("Head 'Building the launcher'")
Yes '  and before the launcher is built' ($iBuild -gt $to)
Yes '  a dev Ship asks Get-DevLauncherLine and stops on its refusal' ($region.Contains('if ($devLine.Refuse) { Die $devLine.Refuse }'))
Yes '  the dev number gives way to main''s only for main''s own launcher' ($region.Contains("if (`$MainEquivalent) {") -and -not $region.Contains("if (`$MainSourceAligned) {"))
Yes '  and the history check is told the fingerprint and both feeds'' launchers' ($region.Contains('Assert-DevVersionSelection $target $current $MainEquivalent $publishedVersions $liveLaunchers $LauncherInputs'))

. (Join-Path (Split-Path -Parent $ShipPath) 'Feed-Store.ps1')
$prelude = ($want | ForEach-Object { $fns[$_] }) -join "`n"
$stubs = 'function Say($m, $c) { }; function Head($m) { }; function Die($m) { throw ("STOP. " + $m) };'
$sb = [scriptblock]::Create(
    'param($a); $Dev = $a.Dev; $ModsOnly = $a.ModsOnly; $RebuildLauncher = $a.Rebuild; $Version = $a.Version;' +
    '$current = $a.Current; $MainSourceAligned = $a.Aligned; $LauncherInputs = $a.Inputs;' +
    '$ReleaseDir = $a.ReleaseDir; $MainReleaseDir = $a.MainReleaseDir;' +
    $stubs + "`n" + $prelude + "`n" + $region +
    "`nreturn [pscustomobject]@{ Target = `$target; Builds = (-not `$ModsOnly) }")

# The launcher's own comparison, ported from Updater.cs IsNewer.
function Parts([string]$v) {
    $o = @()
    foreach ($p in (($v -replace '^[vV]', '') -split '\.')) { $k = 0; if (-not [int]::TryParse($p, [ref]$k)) { return $null }; $o += $k }
    return , $o
}
function IsNewer([string]$remote, [string]$local) {
    if (-not $remote) { return $false }
    if (-not $local) { return $true }
    if ($remote -eq $local) { return $false }
    $x = Parts $remote; $y = Parts $local
    if ($null -eq $x -or $null -eq $y) { return ($remote -ne $local) }
    for ($i = 0; $i -lt [Math]::Max($x.Count, $y.Count); $i++) {
        $u = if ($i -lt $x.Count) { $x[$i] } else { 0 }
        $v = if ($i -lt $y.Count) { $y[$i] } else { 0 }
        if ($u -ne $v) { return ($u -gt $v) }
    }
    return $false
}

# The two fingerprints measured on 12 Oct, and two more for later launchers.
$M = 'a5035b57ce77e89f0620b769e4f42841697ce3c0d382a0d20369bb37a237d306'   # main's 1.2.3, 7cece557
$D = '0b5ba66bfe0cd1545a543c9822b7749206f4f1245b8aaec42deca2eb0d142d1d'   # 9ec48194, with #2343
$E = ('e' * 64)
$G = ('6' * 64)
$sha = ('5' * 64)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts2347-' + [Guid]::NewGuid().ToString('N'))
$oldSite = $env:THORNSWOOD_TEST_SITE_DIR
$oldLocal = $env:LOCALAPPDATA
$script:runN = 0
function Put-Feed([string]$dir, [string]$version, [string]$inputs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $dir 'version') | Out-Null
    $doc = [ordered]@{ launcherVersion = $version; launcherUrl = ('https://thornswood.net/x/assets/' + $sha); launcherSha256 = $sha; launcherInputs = $inputs }
    [IO.File]::WriteAllText((Join-Path $dir 'version\00000001.json'), ($doc | ConvertTo-Json))
}
# Feeds are 'version|fingerprint', or '' for none. Returns the choice, or the
# STOP sentence as a string.
function Run([hashtable]$o) {
    $script:runN++
    $site = Join-Path $tmp ('site' + $script:runN)
    $local = Join-Path $tmp ('local' + $script:runN)
    New-Item -ItemType Directory -Force -Path (Join-Path $site 'feed'), (Join-Path $site 'feed-dev'), $local | Out-Null
    foreach ($kv in @(@('Main', 'feed'), @('DevFeed', 'feed-dev'))) {
        $v = [string]$o[$kv[0]]
        if ($v) { $p = $v.Split('|'); Put-Feed (Join-Path $site $kv[1]) $p[0] $p[1] }
    }
    if ($o.Ever) { [IO.File]::WriteAllLines((Join-Path $site 'feed-dev\launchers.txt'), [string[]]$o.Ever) }
    $env:THORNSWOOD_TEST_SITE_DIR = $site
    $env:LOCALAPPDATA = $local
    try {
        $a = @{
            Dev = $(if ($o.ContainsKey('Dev')) { [bool]$o.Dev } else { $true })
            ModsOnly = [bool]$o.ModsOnly; Rebuild = [bool]$o.Rebuild; Version = [string]$o.Version
            Current = [string]$o.Current; Aligned = [bool]$o.Aligned; Inputs = [string]$o.Inputs
        }
        $a.ReleaseDir = Get-FeedStoreDir $(if ($a.Dev) { 'dev' } else { 'main' })
        $a.MainReleaseDir = Get-FeedStoreDir 'main'
        return (& $sb $a)
    }
    catch { return [string]$_.Exception.Message }
    finally { $env:THORNSWOOD_TEST_SITE_DIR = $oldSite; $env:LOCALAPPDATA = $oldLocal }
}
function Chose($r, [string]$target, [bool]$builds) {
    return ($r -isnot [string] -and $r.Target -eq $target -and [bool]$r.Builds -eq $builds)
}
function Said($r) { if ($r -is [string]) { return $r } return ("chose {0}, builds {1}" -f $r.Target, $r.Builds) }

try {
    # ---- the fingerprint really tells the two launchers apart ---------------
    $tree = Join-Path $tmp 'tree'
    New-Item -ItemType Directory -Force -Path (Join-Path $tree 'launcher\app') | Out-Null
    [IO.File]::WriteAllText((Join-Path $tree 'launcher\app\OwnGame.cs'), 'class OwnGame { }')
    Invoke-Expression $fns['Get-LauncherInputHash']
    $before = Get-LauncherInputHash $tree
    [IO.File]::WriteAllText((Join-Path $tree 'launcher\app\OwnGame.cs'), 'class OwnGame { void Faster() { } }')
    Yes 'a launcher change since main''s release moves the fingerprint Ship compares' ((Get-LauncherInputHash $tree) -ne $before)

    # ---- 1. THE CASE THAT HAPPENED: clean main, a launcher change since -----
    # Main offers 1.2.3 (M); dev offers the 1.2.3 that went out at 1:05 AM (D).
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|$M"; DevFeed = "1.2.3|$D"; Ever = @('1.2.2.4', '1.2.3') }
    Yes ("1 clean main with #2343 since main's 1.2.3 takes 1.2.3.1 and builds it: " + (Said $r)) (Chose $r '1.2.3.1' $true)
    Yes '1 and a dev launcher on 1.2.3 is offered it' (IsNewer '1.2.3.1' '1.2.3')
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|$M"; DevFeed = "1.2.3|$D"; Ever = @('1.2.3', '1.2.3.1', '1.2.3.2') }
    Yes ("1 it climbs past every dev number already out: " + (Said $r)) (Chose $r '1.2.3.3' $true)
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|$M"; DevFeed = "1.2.3.1|$D"; Ever = @('1.2.3.1') }
    Yes ("1 once dev carries it as 1.2.3.1, the next Ship keeps it, no rebuild: " + (Said $r)) (Chose $r '1.2.3' $false)
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $E; Main = "1.2.3|$M"; DevFeed = "1.2.3.1|$D"; Ever = @('1.2.3.1') }
    Yes ("1 and a second launcher change takes 1.2.3.2: " + (Said $r)) (Chose $r '1.2.3.2' $true)
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|$M"; DevFeed = "1.2.3|$D"; Ever = @('1.2.3'); Rebuild = $true }
    Yes ("1 -RebuildLauncher takes the dev number too: " + (Said $r)) (Chose $r '1.2.3.1' $true)

    # ---- 2. clean main equal to main's published launcher -------------------
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $M; Main = "1.2.3|$M"; DevFeed = "1.2.3|$M"; Ever = @('1.2.2.4', '1.2.3') }
    Yes ("2 clean main that is main's 1.2.3, already on dev, keeps 1.2.3 with no rebuild: " + (Said $r)) (Chose $r '1.2.3' $false)
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $M; Main = "1.2.3|$M"; DevFeed = "1.2.2.4|$E"; Ever = @('1.2.2.4') }
    Yes ("2 not on dev yet, it goes to dev as 1.2.3: " + (Said $r)) (Chose $r '1.2.3' $true)
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $M; Main = "1.2.3|$M"; DevFeed = "1.2.3|$D"; Ever = @('1.2.3') }
    Yes ("2 main's launcher cannot go to dev as 1.2.3 while dev's 1.2.3 is another launcher, so it stops: " + (Said $r)) ($r -is [string] -and $r -like 'STOP.*1.2.3 is already out*Bump-Version*')
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $M; Main = "1.2.3|$M"; DevFeed = "1.2.3.1|$D"; Ever = @('1.2.3.1') }
    Yes ("2 nor below a dev number already out, which still stops as before: " + (Said $r)) ($r -is [string] -and $r -like 'STOP.*downgrade*')

    # ---- 3. a branch build, unchanged ---------------------------------------
    $r = Run @{ Aligned = $false; Current = '1.2.3'; Inputs = $E; Main = "1.2.3|$M"; DevFeed = "1.2.3.2|$D"; Ever = @('1.2.3.1', '1.2.3.2') }
    Yes ("3 a branch with its own launcher climbs as it always did: " + (Said $r)) (Chose $r '1.2.3.3' $true)
    $r = Run @{ Aligned = $false; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|$M"; DevFeed = "1.2.3.2|$D"; Ever = @('1.2.3.1', '1.2.3.2') }
    Yes ("3 a branch whose launcher dev already has keeps it: " + (Said $r)) (Chose $r '1.2.3' $false)
    $r = Run @{ Aligned = $false; Current = '1.2.3'; Inputs = $M; Main = "1.2.3|$M"; DevFeed = "1.2.3.2|$D"; Ever = @('1.2.3.1', '1.2.3.2') }
    Yes ("3 a branch with main's launcher still takes a dev number: " + (Said $r)) (Chose $r '1.2.3.3' $true)
    $r = Run @{ Aligned = $false; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|$M"; DevFeed = "1.2.3|$D"; Ever = @('1.2.3') }
    Yes ("3 a branch never keeps dev's mislabelled 1.2.3 either: " + (Said $r)) (Chose $r '1.2.3.1' $true)
    $r = Run @{ Aligned = $false; Current = '1.2.2'; Inputs = $E; Main = "1.2.3|$M"; DevFeed = "1.2.3|$D"; Ever = @('1.2.3') }
    Yes ("3 a branch behind main climbs from main's number: " + (Said $r)) (Chose $r '1.2.3.1' $true)

    # ---- 4. main moved first with Bump-Version, the main Ship not run -------
    $r = Run @{ Aligned = $true; Current = '1.2.4'; Inputs = $G; Main = "1.2.3|$M"; DevFeed = "1.2.3.2|$D"; Ever = @('1.2.3.1', '1.2.3.2') }
    Yes ("4 clean main on 1.2.4 before main ships it goes to dev as 1.2.4: " + (Said $r)) (Chose $r '1.2.4' $true)
    Yes '4 and a dev launcher on 1.2.3.2 is offered it' (IsNewer '1.2.4' '1.2.3.2')
    $r = Run @{ Aligned = $true; Current = '1.2.4'; Inputs = $G; Main = "1.2.4|$G"; DevFeed = "1.2.4|$G"; Ever = @('1.2.3.2', '1.2.4') }
    Yes ("4 once main ships that 1.2.4, dev keeps it with no rebuild: " + (Said $r)) (Chose $r '1.2.4' $false)
    $r = Run @{ Aligned = $true; Current = '1.2.4'; Inputs = $E; Main = "1.2.3|$M"; DevFeed = "1.2.4|$G"; Ever = @('1.2.3.2', '1.2.4') }
    Yes ("4 a launcher change after dev took 1.2.4 takes 1.2.4.1: " + (Said $r)) (Chose $r '1.2.4.1' $true)

    # ---- 5. main has published past this source (a hotfix) -----------------
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $E; Main = "1.2.4|$G"; DevFeed = "1.2.3.2|$D"; Ever = @('1.2.3.2') }
    Yes ("5 clean main on 1.2.3 under a published 1.2.4 climbs from main's number: " + (Said $r)) (Chose $r '1.2.4.1' $true)

    # ---- 6. main's feed cannot be read at all -------------------------------
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = ''; DevFeed = "1.2.3|$D"; Ever = @('1.2.3') }
    Yes ("6 clean main cannot tell whether it is main's launcher, so it stops before building: " + (Said $r)) ($r -is [string] -and $r -like "STOP.*main's feed could not be read*Nothing was built*")
    $r = Run @{ Aligned = $false; Current = '1.2.3'; Inputs = $E; Main = ''; DevFeed = "1.2.3.1|$D"; Ever = @('1.2.3.1') }
    # Until 19 Oct a branch went on from its own number here (#2711 decision 1 B).
    Yes ("6 a branch stops too, since its number could land below main's: " + (Said $r)) ($r -is [string] -and $r -like "STOP.*Could not read what main has published*Nothing was built*")
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = ''; DevFeed = "1.2.3|$D"; ModsOnly = $true }
    Yes ("6 -ModsOnly builds no launcher, so it needs no answer: " + (Said $r)) (Chose $r '1.2.3' $false)

    # ---- 7. -Version cannot put a launcher under a number already out -------
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|$M"; DevFeed = "1.2.3|$D"; Ever = @('1.2.3'); Version = '1.2.3' }
    Yes ("7 -Version 1.2.3 for a launcher main's 1.2.3 is not stops: " + (Said $r)) ($r -is [string] -and $r -like 'STOP.*1.2.3 is already out*without -Version*')
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|$M"; DevFeed = "1.2.3|$D"; Ever = @('1.2.3'); Version = '1.2.3.5' }
    Yes ("7 -Version 1.2.3.5 goes: " + (Said $r)) (Chose $r '1.2.3.5' $true)
    $r = Run @{ Aligned = $true; Current = '1.2.3'; Inputs = $M; Main = "1.2.3|$M"; DevFeed = "1.2.2.4|$E"; Ever = @('1.2.2.4'); Version = '1.2.3.1' }
    Yes ("7 main's own launcher still cannot take a dev number by -Version: " + (Said $r)) ($r -is [string] -and $r -like 'STOP.*Main-equivalent*')

    # ---- 8. the main Ship of the next version is not in the way -------------
    # A main Ship reads none of the dev numbers: main moves with Bump-Version
    # and ships what main says.
    $r = Run @{ Dev = $false; Aligned = $true; Current = '1.2.4'; Inputs = $G; Main = "1.2.3|$M"; DevFeed = "1.2.3.3|$D"; Ever = @('1.2.3.3') }
    Yes ("8 main ships 1.2.4 with dev on 1.2.3.3: " + (Said $r)) (Chose $r '1.2.4' $true)
    $r = Run @{ Dev = $false; Aligned = $true; Current = '1.2.3'; Inputs = $M; Main = "1.2.3|$M"; DevFeed = "1.2.3.3|$D"; Ever = @('1.2.3.3') }
    Yes ("8 a main Ship of 1.2.3 again keeps main's launcher: " + (Said $r)) (Chose $r '1.2.3' $false)
    # ---- 9. a main Ship cannot sign CI's exe again under main's own number --
    # The case Publish-Update's old WARNING was still reachable by: main's feed
    # offers 1.2.3, and a main Ship of 1.2.3 whose launcher sources are not the
    # ones it was built from would sign CI's exe again and send it as 1.2.3.
    $r = Run @{ Dev = $false; Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|$M"; DevFeed = "1.2.3.3|$D"; Ever = @('1.2.3.3') }
    Yes ("9 a main Ship of 1.2.3 from other launcher sources than main's 1.2.3 stops before the exe is fetched or signed: " + (Said $r)) ($r -is [string] -and $r -like 'STOP.*1.2.3 is already out*Bump-Version*')
    $r = Run @{ Dev = $false; Aligned = $true; Current = '1.2.3'; Inputs = $M; Main = "1.2.3|$M"; DevFeed = "1.2.3.3|$D"; Ever = @('1.2.3.3'); Rebuild = $true }
    Yes ("9 -RebuildLauncher from main's own sources goes, since it is the same launcher: " + (Said $r)) (Chose $r '1.2.3' $true)
    $r = Run @{ Dev = $false; Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|$M"; DevFeed = "1.2.3.3|$D"; Ever = @('1.2.3.3'); ModsOnly = $true }
    Yes ("9 -ModsOnly sends no launcher, so it goes: " + (Said $r)) (Chose $r '1.2.3' $false)
    $r = Run @{ Dev = $false; Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = "1.2.2|$M"; DevFeed = "1.2.2.3|$D"; Ever = @('1.2.2.3') }
    Yes ("9 main moved to 1.2.3 and not shipped yet goes: " + (Said $r)) (Chose $r '1.2.3' $true)
    $r = Run @{ Dev = $false; Aligned = $true; Current = '1.2.3'; Inputs = $D; Main = "1.2.3|"; DevFeed = "1.2.3.3|$D"; Ever = @('1.2.3.3') }
    Yes ("9 a feed launcher with no fingerprint is not known to be this one, so it stops: " + (Said $r)) ($r -is [string] -and $r -like 'STOP.*1.2.3 is already out*')
    Yes '9 the main check is in the lifted choice, after the dev one' ($region.Contains("if (-not `$Dev -and -not `$ModsOnly) {") -and $region.Contains('Assert-DevVersionSelection $target $current $true @() @($mainNow) $LauncherInputs'))
    Yes '8 main''s 1.2.4 is offered to a launcher on 1.2.3.3' (IsNewer '1.2.4' '1.2.3.3')
    Yes '8 main''s 1.2.3 is never offered over a dev 1.2.3.1' (-not (IsNewer '1.2.3' '1.2.3.1'))
    Yes '8 and a dev 1.2.3.1 is never offered over main''s 1.2.4' (-not (IsNewer '1.2.3.1' '1.2.4'))
}
finally {
    $env:THORNSWOOD_TEST_SITE_DIR = $oldSite
    $env:LOCALAPPDATA = $oldLocal
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
