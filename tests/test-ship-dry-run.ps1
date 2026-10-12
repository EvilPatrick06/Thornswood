<#
  test-ship-dry-run.ps1

  A dry run publishes nothing, and a real Ship still publishes the installer.

  The entry, found on 24 September by the script index run (entry 260):
  "-DryRun -Package publishes the installer to the site." Ship called
  Package-Thornswood.ps1 the same way on a dry run as on a real one, without
  -NoPublish, and Package-Thornswood ends by handing what it built to
  Publish-Installer.ps1, which copies it to the VPS over ssh. A dry run exists
  so a person can see what a release would do without doing it; one that puts
  a new installer on the live site is the opposite.

  The same read found one more way a dry run could reach outside the machine.
  On the dev channel, with no dev release worktree on the disk and no dev
  branch that git could see on the releases repository, Ship made the branch
  and pushed it, dry run or not. Since #907 there is no releases repository:
  the feed and the baseline are on the VPS store (Feed-Store.ps1), stood in for
  here by a folder through THORNSWOOD_TEST_SITE_DIR.

  HOW. The real Ship.ps1 is copied into a temp folder shaped like this repo,
  beside a stand-in for every script it calls. Each stand-in writes down what it
  was asked and does nothing else. git, gh, ssh and scp are stand-ins too,
  first on PATH for the child, so anything that would leave the machine is
  written down instead of done. Ship then runs in a child PowerShell, start to
  finish:

    D  -DryRun -Package on main
    V  -DryRun -Package on dev
    R  a real Ship -Package on main, which builds the installer in the one
       file shape the site carries (-OneFile, #1213)
    E  -DryRun on dev, numbered from what the store says dev has published
    G  -DryRun on dev with no -Root, on a machine that recorded its dev
       release folder (Where.ps1 ShipRootDev, #1692): that folder is built,
       installed and published
    H  -Root naming a folder Vortex deploys into: refused before anything is
       built, installed or published (#1692)
    I  a folder whose generated files are out of date: refused before the
       launcher is built or installed (#1692)
    J  a game folder on a machine with no node: refused before anything is
       built, installed or published, saying why (#1913)
    K  SkyUI's menus could not be read (Check-SkyUIMenus.js exit 1): refused,
       nothing published (#1913)
    L  the same folder with a check that passes runs to the end, so J and K
       stop on node and on the check, not on the folder; and a mismatch
       (exit 2) still refuses (#960)
    M  a body mesh the covered bodies check could not read
       (Check-CoveredBodies.ps1 exit 1): refused on dev and on main, nothing
       published, the version put back (#1956); a nude body (exit 2) on dev
       still only warns and runs to the end (#405)

  R is there so D and V prove something: the same stand-ins, on a real Ship,
  do write down the installer going to the site, the feed and baseline going to
  the store, dev following main through it, the news, the Discord and the restart.
  And the release tag (#444): R pushes release/main/<id> once, after the
  publisher said it sent the feed; D, V and E make no tag at all.

  R also proves the launcher that ships is the one CI built, not one compiled
  here (issue #457). A real main Ship never calls Build-Launcher.ps1: it runs
  gh release download for the tag, checks the exe against its SHA256SUMS, and
  only then installs and packs it. The gh stand-in writes a Thornswood.exe and a
  matching SHA256SUMS on "release download", so the verification passes and the
  path is exercised. A dev build and a dry run still compile locally, which is
  why V and D call Build-Launcher and never gh release download.

  The stand-ins are only worth what the real scripts do, so two of those are
  read as well: Package-Thornswood.ps1 calls Publish-Installer.ps1 only without
  -NoPublish, and Publish-Update.ps1 has no gh or git call that reaches GitHub,
  and every send to the VPS store is behind -NoPush.

  Nothing here touches this repository, the network, a game or a launcher.
  Everything it writes is under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $ShipPath) { $ShipPath = Join-Path $Here 'scripts\release\Ship.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    # The temp folder's path is long and says nothing; the calls read better without it.
    if ($script:T) { $what = $what.Replace($script:T, '<temp>') }
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$IfAst = [System.Management.Automation.Language.IfStatementAst]
$CmdAst = [System.Management.Automation.Language.CommandAst]
$FnAst = [System.Management.Automation.Language.FunctionDefinitionAst]

function Parse([string]$path) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
    return [pscustomobject]@{ Ast = $ast; Tokens = @($t); Errors = @($e) }
}

# The condition of the clause of the nearest enclosing if, walking out from a
# node, and the name of the nearest enclosing function. The clause, not just
# the if: an elseif under "-not $NoUpload" is not the branch that uploads.
function Enclosing($node) {
    $conds = @()
    $fn = ''
    $prev = $node
    $p = $node.Parent
    while ($p) {
        if ($p -is $IfAst) {
            foreach ($c in $p.Clauses) {
                if ([object]::ReferenceEquals($c.Item2, $prev)) { $conds += $c.Item1.Extent.Text }
            }
        }
        if ($p -is $FnAst -and -not $fn) { $fn = $p.Name }
        $prev = $p
        $p = $p.Parent
    }
    return [pscustomobject]@{ Conditions = $conds; Function = $fn }
}

# ---- the real scripts the stand-ins stand for ------------------------------------
$shipSrc = [IO.File]::ReadAllText($ShipPath)
$ship = Parse $ShipPath
Yes 'Ship.ps1 parses' ($ship.Errors.Count -eq 0)

$pkg = Parse (Join-Path $Here 'scripts\release\Package-Thornswood.ps1')
$noPub = @($pkg.Ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'NoPublish' })
Yes 'Package-Thornswood.ps1 has a -NoPublish switch' ($noPub.Count -eq 1)
$pubIf = @($pkg.Ast.FindAll({ param($n) $n -is $IfAst -and $n.Clauses[0].Item1.Extent.Text -eq '-not $NoPublish' }, $true))
Yes '  and one if (-not $NoPublish)' ($pubIf.Count -eq 1)
$named = @($pkg.Tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Text -match 'Publish-Installer' })
$outside = @()
if ($pubIf.Count -eq 1) {
    $a = $pubIf[0].Extent.StartOffset; $b = $pubIf[0].Extent.EndOffset
    $outside = @($named | Where-Object { $_.Extent.StartOffset -lt $a -or $_.Extent.EndOffset -gt $b })
}
Yes ("  and Publish-Installer.ps1 is named only inside it ({0} time(s)), so without -NoPublish it publishes and with it it does not" -f $named.Count) ($named.Count -ge 1 -and $pubIf.Count -eq 1 -and $outside.Count -eq 0)

$pu = Parse (Join-Path $Here 'scripts\release\Publish-Update.ps1')
$away = @($pu.Ast.FindAll({ param($n) $n -is $CmdAst }, $true) | Where-Object {
    $name = $_.GetCommandName()
    $words = @($_.CommandElements | ForEach-Object { $_.Extent.Text })
    ($name -eq 'gh') -or ($name -eq 'git' -and @($words | Where-Object { $_ -in 'push', 'pull', 'fetch', 'ls-remote', 'clone' }).Count -gt 0)
})
Yes ('Publish-Update.ps1 has no gh or git call that reaches GitHub any more (#907)' + $(if ($away.Count) { ': ' + (($away | ForEach-Object { 'line ' + $_.Extent.StartLineNumber }) -join ', ') } else { '' })) ($away.Count -eq 0)
$sends = @($pu.Ast.FindAll({ param($n) $n -is $CmdAst -and $n.GetCommandName() -eq 'Send-FeedStore' }, $true))
$loose = @()
foreach ($c in $sends) {
    $e = Enclosing $c
    $held = @($e.Conditions | Where-Object { $_ -match '-not \$NoPush\b' }).Count -gt 0
    if (-not $held -and $e.Function -ne 'Send-Baseline') { $loose += ('line ' + $c.Extent.StartLineNumber) }
}
$sb = @($pu.Ast.FindAll({ param($n) $n -is $FnAst -and $n.Name -eq 'Send-Baseline' }, $true))
Yes ("  what it sends to the VPS goes through Send-FeedStore ({0} call(s)), so the next lines read something" -f $sends.Count) ($sends.Count -ge 2)
Yes ('  every one is behind -NoPush, or in Send-Baseline' + $(if ($loose.Count) { ': ' + ($loose -join '; ') } else { '' })) ($loose.Count -eq 0)
Yes '  and Send-Baseline sends nothing under -NoPush' ($sb.Count -eq 1 -and $sb[0].Extent.Text -match 'if \(\$NoPush\) \{ return \}')
Yes '  and Ship always gives it the working folder' ($shipSrc -match '\$pubArgs = @\{[^\r\n]*ReleaseDir = \$ReleaseDir')

# ---- a repository, a releases clone and two installs, all stand-ins --------------
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-ship-dry-' + [Guid]::NewGuid().ToString('N'))
$repo = Join-Path $T 'Thornswood'
$appdata = Join-Path $T 'appdata'
# This machine's working copies of the feeds (Feed-Store.ps1, #907), and the
# folder standing in for the VPS store beside the site's feeds.
$rel = Join-Path $appdata 'Thornswood\feed\main'
$relDev = Join-Path $appdata 'Thornswood\feed\dev'
$site = Join-Path $T 'site'
$bin = Join-Path $T 'bin'
$root = Join-Path $T 'Play'
$rootDev = Join-Path $T 'Play-DevBuild'
$dist = Join-Path $T 'dist'
$log = Join-Path $T 'calls.log'

# What every stand-in script writes down: its name and what it was given, on
# one line. A value's own line breaks are written as " / ": the notes have a
# title and a list since #586, and a break in them split one call into two
# lines of the log, so a switch after -Notes was never seen.
$noteText = @'
$line = 'NAME'
foreach ($k in @($PSBoundParameters.Keys | Sort-Object)) {
    $v = $PSBoundParameters[$k]
    if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $line += ' -' + $k } }
    else { $line += ' -' + $k + ' ' + ([string]$v -replace "\r?\n", ' / ') }
}
[IO.File]::AppendAllText($env:TS_DRY_CALLS, $line + "`r`n")
'@
function Stub([string]$name, [string]$params, [string]$body) {
    $text = "param($params)`r`n" + $noteText.Replace('NAME', $name) + "`r`n" + $body + "`r`nexit 0`r`n"
    # Each in its own area under scripts\ since phase 8 of issue #440, where Ship.ps1
    # in scripts\release calls it.
    $area = 'release'
    if ($name -in 'Publish-News', 'Publish-Discord') { $area = 'ops' }
    if ($name -eq 'Request-Restart') { $area = 'vps' }
    $dir = Join-Path $repo ('scripts\' + $area)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir ($name + '.ps1')), $text)
}

$oldPath = $env:PATH
$oldAppData = $env:LOCALAPPDATA
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$oldCalls = $env:TS_DRY_CALLS
$oldGhDl = $env:TS_GH_DL
$oldSite = $env:THORNSWOOD_TEST_SITE_DIR
$oldScratch = $env:THORNSWOOD_SCRATCH_ROOT
$ps = (Get-Process -Id $PID).Path

function Invoke-Ship([string[]]$shipArgs) {
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'scripts\release\Ship.ps1') @shipArgs 2>&1 | Out-String
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    $calls = @()
    if (Test-Path -LiteralPath $log) { $calls = @(Get-Content -LiteralPath $log | Where-Object { $_ }) }
    return [pscustomobject]@{ Code = $code; Out = $out; Calls = $calls }
}
# The comma keeps a one line answer an array: a return unrolls it otherwise,
# and [0] of a bare string is its first character.
function Called($run, [string]$name) { return ,@($run.Calls | Where-Object { $_ -eq $name -or $_.StartsWith($name + ' ') }) }
# Anything that would have left the machine, by the stand-ins on PATH. Every
# gh, ssh and scp call, and every git call but the ones that only read: since
# 25 September a dev Ship reads the version each channel has published off
# origin (git fetch, then show and log of origin/main and origin/dev), so a
# dev number never lands below one already out. Reading sends nothing of this
# release anywhere.
function Away($run) {
    return ,@($run.Calls | Where-Object {
        $_ -match '^(gh|ssh|scp)( |$)' -or
        ($_ -match '^git( |$)' -and $_ -notmatch '^git (-C \S+ )?(fetch|show|log|rev-parse|status|remote get-url|ls-remote)( |$)')
    })
}
function Hash([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return 'absent' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($path))) } finally { $sha.Dispose() }
}
function Read-Version([string]$path) {
    $m = [regex]::Match([IO.File]::ReadAllText($path), 'Version\s*=\s*"([^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

try {
    foreach ($d in @((Join-Path $repo 'launcher\app'), (Join-Path $repo 'scripts\release'), $rel, $relDev, $bin,
                     (Join-Path $root 'Launcher'), (Join-Path $rootDev 'Launcher'), $dist, (Join-Path $appdata 'Thornswood'))) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
    Copy-Item -LiteralPath $ShipPath -Destination (Join-Path $repo 'scripts\release\Ship.ps1') -Force
    # The real files Ship dot-sources, beside it, so it runs as it does for real.
    $realRel = Split-Path -Parent $ShipPath
    foreach ($n in 'Ship-Rules.ps1', 'Assert-PublishSigned.ps1', 'Feed-Store.ps1', 'Release-Name.ps1', 'Note-Rules.ps1', 'Where.ps1', 'Get-ScratchDir.ps1', 'Read-JsonFile.ps1', 'RecordShape.ps1') {
        Copy-Item -LiteralPath (Join-Path $realRel $n) -Destination (Join-Path $repo ('scripts\release\' + $n)) -Force
    }
    Copy-Item -LiteralPath (Join-Path $realRel '..\..\layout.json') -Destination (Join-Path $repo 'layout.json') -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $repo 'records') | Out-Null
    Copy-Item -LiteralPath (Join-Path $realRel '..\..\records\ui-gone.json') -Destination (Join-Path $repo 'records\ui-gone.json') -Force
    New-Item -ItemType Directory -Force -Path (Join-Path $repo 'scripts\mods') | Out-Null
    Copy-Item -LiteralPath (Join-Path $realRel '..\mods\LoadOrder.ps1') -Destination (Join-Path $repo 'scripts\mods\LoadOrder.ps1') -Force
    # What Ship.ps1 dot-sources, which a stand-in cannot write down because it
    # is not called, only read. The two rule files are the real ones: they
    # only define functions, and the notes below are held to Note-Rules the
    # way a real Ship holds them.
    $realRelease = Split-Path -Parent (Resolve-Path -LiteralPath $ShipPath).Path
    foreach ($f in 'Ship-Rules.ps1', 'Note-Rules.ps1') {
        Copy-Item -LiteralPath (Join-Path $realRelease $f) -Destination (Join-Path $repo 'scripts\release') -Force
    }
    # The publish sign gate (#826) and the load order check (#557) read this
    # machine's signing setup, its signed exe and Vortex, none of which a
    # temp folder has. Their stand-ins pass, so what is measured here is
    # still what Ship calls and what leaves the machine; the gate itself has
    # tests\test-publish-sign-gate.ps1.
    [IO.File]::WriteAllText((Join-Path $repo 'scripts\release\Assert-PublishSigned.ps1'), @'
function Get-SigningConfigRefusal { param([string]$ConfigPath, [string]$RepoRoot) return '' }
function Get-ExpectedSignerFragment { param([string]$RepoRoot) return 'CN=Thornswood' }
function Get-PublishSignRefusal { param([string]$Path, [string]$ExpectedSigner) return '' }
'@)
    New-Item -ItemType Directory -Force -Path (Join-Path $repo 'scripts\mods') | Out-Null
    [IO.File]::WriteAllText((Join-Path $repo 'scripts\mods\LoadOrder.ps1'), @'
function Assert-VortexProfile([string]$Name = 'Thornswood') { return (Join-Path $env:LOCALAPPDATA 'Vortex-Thornswood') }
function Get-LoadOrderCopyDiffs([hashtable]$Copies) { return @() }
'@)
    $updaterCs = Join-Path $repo 'launcher\app\Updater.cs'
    [IO.File]::WriteAllText($updaterCs, "        public const string Version = `"1.1.93`";`r`n")
    # Issue #1081: Ship runs scripts\dev\Check-Words.ps1 before it builds.
    # This stand-in passes. tests\test-ship-check-words.ps1 runs the real
    # script against a planted hit. A stand-in here keeps this dry run on
    # what leaves the machine.
    New-Item -ItemType Directory -Force -Path (Join-Path $repo 'scripts\dev') | Out-Null
    [IO.File]::WriteAllText((Join-Path $repo 'scripts\dev\Check-Words.ps1'), "param([string]`$Root)`r`nexit 0`r`n")
    # The VPS store (Feed-Store.ps1, #907), stood in for by a folder, and this
    # machine's working copies of it as the last run left them.
    foreach ($d in (Join-Path $site 'feed'), (Join-Path $site 'feed-dev')) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    foreach ($pair in @(@($rel, 'feed'), @($relDev, 'feed-dev'))) {
        # Main's feed offers 1.1.92: main moved to 1.1.93 with Bump-Version and has
        # not shipped it, the state a main Ship starts from. A main feed already
        # offering 1.1.93 from other launcher sources is refused before anything is
        # built (#2347, tests\test-2347-dev-launcher-version.ps1).
        $v = if ($pair[1] -eq 'feed') { '{"launcherVersion":"1.1.92","packs":[]}' } else { '{"launcherVersion":"1.1.93.2","packs":[],"serverPort":7001}' }
        $b = if ($pair[1] -eq 'feed') { '{"main":"as last published"}' } else { '{"dev":"as last published"}' }
        [IO.File]::WriteAllText((Join-Path $site ($pair[1] + '\version.json')), $v)
        [IO.File]::WriteAllText((Join-Path $site ($pair[1] + '\published.json')), $b)
        [IO.File]::WriteAllText((Join-Path $pair[0] 'version.json'), $v)
        [IO.File]::WriteAllText((Join-Path $pair[0] 'published.json'), $b)
    }
    [IO.File]::WriteAllText((Join-Path $site 'feed-dev\launchers.txt'), "1.1.93.1`r`n1.1.93.2`r`n")
    # An hour old, so the stand-in install is newer and Ship calls it built.
    foreach ($r in $root, $rootDev) {
        $exe = Join-Path $r 'Launcher\Thornswood.exe'
        [IO.File]::WriteAllText($exe, 'the launcher as installed')
        (Get-Item -LiteralPath $exe).LastWriteTimeUtc = [DateTime]::UtcNow.AddHours(-1)
    }

    Stub 'Build-Launcher' '[string]$Root, [string]$OutDir, [switch]$NoPause' ''
    Stub 'Install-Launcher' '[string]$Root, [string]$From, [switch]$NoPause' @'
[IO.File]::WriteAllText((Join-Path $Root 'Launcher\Thornswood.exe'), 'the launcher this run built')
'@
    Stub 'Go' '[switch]$SkipServer, [string]$Game, [switch]$Vortex' ''
    Stub 'Sync-Client' '[switch]$Check, [switch]$NoPause, [string]$Game' ''
    # What the real publisher does: receives the feed and baseline (from the
    # stand-in store), writes version.json and its baseline, and with no
    # -NoPush sends both back.
    Stub 'Publish-Update' ('[string]$Notes, [string]$Root, [string]$RepoDir, [string]$ReleaseDir, [string]$DistRoot, ' +
                           '[switch]$NoPause, [switch]$MoveServer, [switch]$AcceptSize, [switch]$Launcher, ' +
                           '[string]$Channel, [string]$VersionOverride, [switch]$NoUpload, [switch]$NoPush, ' +
                           # A dry run also passes these two since #494: close no game, prune no packs.
                           '[switch]$NoClose, [int]$KeepPacks = 10, ' +
                           # And the fingerprint of the launcher's sources since #921, which
                           # the feed records with the launcher (#2347 compares it).
                           '[string]$LauncherInputs') @'
# F: the send of the feed failed, the way the real one ends then (#1055).
if ($env:TS_PUB_FAIL) { Write-Host 'NOT SHIPPED. the store refused version.json'; exit 1 }
. (Join-Path $PSScriptRoot 'Feed-Store.ps1')
if (-not $NoPush) { [void](Receive-FeedStore $(if ($Channel) { $Channel } else { 'main' }) $ReleaseDir) }
$vf = Join-Path $ReleaseDir 'version.json'
$feedWas = Get-Content -LiteralPath $vf -Raw | ConvertFrom-Json
$was = [string]$feedWas.launcherVersion
# The launcher number the real one records: -VersionOverride, else with
# -Launcher the number in launcher\app\Updater.cs beside it, else the feed's
# own (a Ship that sends no launcher keeps the one the feed offers). With a
# launcher it records that launcher's fingerprint; without, the feed's stays.
$now = $was
$inputsNow = if ($feedWas.PSObject.Properties['launcherInputs']) { [string]$feedWas.launcherInputs } else { '' }
if ($Launcher) {
    $m = [regex]::Match([IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\launcher\app\Updater.cs')), 'Version\s*=\s*"([^"]+)"')
    if ($m.Success) { $now = $m.Groups[1].Value }
    $inputsNow = [string]$LauncherInputs
}
if ($VersionOverride) { $now = $VersionOverride }
# With the release record the real one writes (#444): one name, 20990101-0000,
# for the pack, the launcher it offers and the commit it was built from.
$ch = if ($Channel -eq 'dev') { 'dev' } else { 'main' }
[IO.File]::WriteAllText($vf, '{"launcherVersion":"' + $now + '","launcherInputs":"' + $inputsNow + '","packs":[{"id":"20990101-0000"}],' +
    '"release":{"id":"20990101-0000","channel":"' + $ch + '","launcherVersion":"' + $now + '","packs":["20990101-0000"],' +
    '"baseline":"","commit":"' + ('ab12' * 10) + '","branch":"main","uncommitted":0,"tag":"release/' + $ch + '/20990101-0000"}}')
[IO.File]::WriteAllText((Join-Path $ReleaseDir 'published.json'), '{"written":"by the publisher"}')
# The send the real one makes: the feed and then the baseline, through
# Feed-Store.ps1 into the stand-in for the VPS store.
if (-not $NoPush) {
    . (Join-Path $PSScriptRoot 'Feed-Store.ps1')
    $ch = if ($Channel) { $Channel } else { 'main' }
    [void](Send-FeedStore $ch $ReleaseDir @('version.json'))
    [void](Send-FeedStore $ch $ReleaseDir @('published.json'))
    # And says so, as the real one does once the feed is on the VPS.
    $global:ThornswoodPublishedRelease = '20990101-0000'
}
'@
    # The real one's last step, which the static check above holds it to.
    Stub 'Package-Thornswood' '[string]$Root, [string]$OutDir, [switch]$NoPause, [switch]$NoPublish, [string]$ReleaseDir, [string]$Stub, [switch]$OneFile' @'
if (-not $NoPublish) { & (Join-Path $PSScriptRoot 'Publish-Installer.ps1') -OutDir $OutDir }
'@
    Stub 'Publish-Installer' '[string]$OutDir, [switch]$OneFile' ''
    Stub 'Publish-News' '' ''
    Stub 'Publish-Discord' '[switch]$Dev' ''
    Stub 'Request-Restart' '[double]$Minutes, [string]$Mode, [string]$Why, [string]$Data' ''
    # What follows a tip: the host feed remirror. The real one reaches the VPS
    # and the site, so a dry run must not call it at all and a real Ship calls it
    # once. Ship reads the exit code and says at the end whether it completed,
    # so this hands back 0 like the rest.
    Stub 'Publish-PostShip' ('[string]$Channel, [string]$Root, [string]$DistRoot, [string]$Only, ' +
                             '[string]$Installer, [switch]$AlsoLauncher, [switch]$NoPause') ''
    # The stand-ins are .ps1, not .cmd (issue #1013). PowerShell finds a .ps1 on
    # PATH before an .exe further along it and runs it with every argument
    # whole. A .cmd gets its arguments through cmd.exe, which ends a command at
    # a bare &, so under C:\ThornswoodTemps&Worktrees (where every temp file on
    # the shipping machine goes) the gh download's --dir was cut in two and the
    # real main Ship case went red.
    $standIn = @'
[IO.File]::AppendAllText($env:TS_DRY_CALLS, ((@('NAME') + @($args | ForEach-Object { [string]$_ })) -join ' ') + "`r`n")
'@
    foreach ($n in 'git', 'ssh', 'scp') {
        [IO.File]::WriteAllText((Join-Path $bin ($n + '.ps1')), $standIn.Replace('NAME', $n) + "`r`nexit 0`r`n")
    }
    # gh needs one thing more than logging: on a real main Ship the launcher is
    # not compiled here, it is downloaded from the release CI built and checked
    # against SHA256SUMS (issue #457). So the gh stand-in, on "release download",
    # writes Thornswood.exe and a SHA256SUMS whose hash is that file's, into the
    # --dir it was given, the way the real gh would. It computes the hash itself,
    # so the download always verifies and the test proves the path runs, not that
    # a particular byte matches. Every other gh call still only logs. It
    # writes each asset a --pattern names, and the setup program too, since a
    # main Ship with -Package takes the one CI built (issue #932).
    $ghDl = Join-Path $bin 'gh-download.ps1'
    [IO.File]::WriteAllText($ghDl, @'
$dir = ''
$want = @()
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq '--dir') { $dir = $args[$i + 1] }
    if ($args[$i] -eq '--pattern') { $want += [string]$args[$i + 1] }
}
if ($dir) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $lines = @()
    foreach ($n in 'Thornswood.exe', 'setup-stub.exe') {
        if ($want -notcontains $n) { continue }
        $f = Join-Path $dir $n
        [IO.File]::WriteAllText($f, "the $n CI built for this tag")
        $lines += ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLower() + '  ' + $n)
    }
    Set-Content -LiteralPath (Join-Path $dir 'SHA256SUMS') -Value $lines -Encoding ascii
}
'@)
    [IO.File]::WriteAllText((Join-Path $bin 'gh.ps1'), $standIn.Replace('NAME', 'gh') + "`r`n" +
        "if (`$args.Count -ge 2 -and `$args[0] -eq 'release' -and `$args[1] -eq 'download') { & `$env:TS_GH_DL @args }`r`nexit 0`r`n")

    $env:PATH = $bin + ';' + $oldPath
    $env:LOCALAPPDATA = $appdata
    # Ship stages the launcher under Get-ScratchDir (issue #1272), not %TEMP%.
    # Point the scratch root at this run's own folder so the gh stand-in writes
    # here and nothing lands under the real temps tree. TEMP stays sandboxed
    # too for anything else that still reads it.
    $env:THORNSWOOD_SCRATCH_ROOT = Join-Path $T 'scratch'
    New-Item -ItemType Directory -Force -Path $env:THORNSWOOD_SCRATCH_ROOT | Out-Null
    $env:TEMP = Join-Path $T 'temp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
    $env:TS_DRY_CALLS = $log
    $env:TS_GH_DL = $ghDl
    $env:THORNSWOOD_TEST_SITE_DIR = $site

    $feed = Join-Path $rel 'version.json'
    $devFeed = Join-Path $relDev 'version.json'
    $base = Join-Path $rel 'published.json'
    $devBase = Join-Path $relDev 'published.json'
    $siteFeed = Join-Path $site 'feed\version.json'
    $siteBase = Join-Path $site 'feed\published.json'
    $siteDevFeed = Join-Path $site 'feed-dev\version.json'
    $siteDevBase = Join-Path $site 'feed-dev\published.json'
    $distDir = Join-Path $dist 'Play\_dist'

    # ---- D: -DryRun -Package on main ------------------------------------------------
    $was = @{ feed = (Hash $feed); dev = (Hash $devFeed); base = (Hash $base); site = (Hash $siteFeed); siteBase = (Hash $siteBase); siteDev = (Hash $siteDevFeed) }
    $d = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-DryRun', '-Package', '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("D a main -DryRun -Package runs to the end (exit {0})" -f $d.Code) ($d.Code -eq 0 -and $d.Out -match 'Dry run finished')
    $pub = Called $d 'Publish-Update'
    Yes 'D the publisher ran, told not to upload and not to push' ($pub.Count -eq 1 -and $pub[0] -match ' -NoUpload\b' -and $pub[0] -match ' -NoPush\b')
    $pk = Called $d 'Package-Thornswood'
    Yes ('D the installer is not built for the site: Package-Thornswood.ps1 is not called without -NoPublish' +
         $(if ($pk.Count) { ' (' + ($pk -join '; ') + ')' } else { '' })) (@($pk | Where-Object { $_ -notmatch ' -NoPublish\b' }).Count -eq 0)
    Yes 'D nothing goes on the site: Publish-Installer.ps1 is not called' ((Called $d 'Publish-Installer').Count -eq 0)
    foreach ($n in 'Publish-News', 'Publish-Discord', 'Request-Restart', 'Publish-PostShip') {
        Yes "D $n.ps1 is not called" ((Called $d $n).Count -eq 0)
    }
    $gone = Away $d
    Yes ('D nothing leaves the machine: no git, gh, ssh or scp' + $(if ($gone.Count) { ' (' + ($gone -join '; ') + ')' } else { '' })) ($gone.Count -eq 0)
    $go = Called $d 'Go'
    Yes 'D Go.ps1 is told to leave the server alone' ($go.Count -eq 1 -and $go[0] -match ' -SkipServer\b')
    Yes 'D it says the installer was not rebuilt' ($d.Out -match 'not rebuilt')
    Yes '  and gives the command that builds it and publishes nothing, in the one file shape the site carries (#1213)' ($d.Out -match [regex]::Escape('Package-Thornswood.ps1 -OneFile -NoPublish -OutDir "' + $distDir + '"'))
    Yes 'D version.json is byte for byte what it was' ((Hash $feed) -eq $was.feed)
    Yes '  and so is the baseline' ((Hash $base) -eq $was.base)
    Yes '  and the dev feed is not reset to match' ((Hash $devFeed) -eq $was.dev)
    Yes '  and nothing on the VPS store moved' ((Hash $siteFeed) -eq $was.site -and (Hash $siteBase) -eq $was.siteBase -and (Hash $siteDevFeed) -eq $was.siteDev)

    # ---- V: -DryRun -Package on dev -------------------------------------------------
    $was = @{ dev = (Hash $devFeed); devBase = (Hash $devBase); feed = (Hash $feed) }
    $v = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-Channel', 'dev', '-DryRun', '-Package', '-Root', $rootDev, '-DistRoot', $dist, '-NoPause')
    Yes ("V a dev -DryRun -Package runs to the end (exit {0})" -f $v.Code) ($v.Code -eq 0 -and $v.Out -match 'Dry run finished')
    $pub = Called $v 'Publish-Update'
    Yes 'V the publisher ran on dev, told not to upload and not to push' ($pub.Count -eq 1 -and $pub[0] -match ' -Channel dev\b' -and $pub[0] -match ' -NoUpload\b' -and $pub[0] -match ' -NoPush\b')
    foreach ($n in 'Package-Thornswood', 'Publish-Installer', 'Publish-News', 'Publish-Discord', 'Request-Restart',
                   'Publish-PostShip') {
        Yes "V $n.ps1 is not called" ((Called $v $n).Count -eq 0)
    }
    $gone = Away $v
    Yes ('V nothing leaves the machine: no git, gh, ssh or scp' + $(if ($gone.Count) { ' (' + ($gone -join '; ') + ')' } else { '' })) ($gone.Count -eq 0)
    Yes 'V the dev feed is byte for byte what it was' ((Hash $devFeed) -eq $was.dev)
    Yes '  and so is the dev baseline' ((Hash $devBase) -eq $was.devBase)
    Yes '  and the main feed is not touched' ((Hash $feed) -eq $was.feed)
    Yes '  and Updater.cs is on the version it had' ((Read-Version $updaterCs) -eq '1.1.93')

    # ---- R: a real Ship -Package on main ----------------------------------------------
    $devBeforeMain = Hash $siteDevFeed
    $devBaselineBeforeMain = Hash $siteDevBase
    $r = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-Package', '-Root', $root, '-DistRoot', $dist, '-NoPause')
    Yes ("R a real main Ship -Package runs to the end (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Out -match 'Everyone in the world has')
    # When it stops, what it said and what it called, so the FAIL says why.
    if ($r.Code -ne 0) { $r.Out -split "`r?`n" | Select-Object -Last 25 | ForEach-Object { Write-Host ("      " + $_) }; $r.Calls | ForEach-Object { Write-Host ("      call: " + $_) } }
    $pub = Called $r 'Publish-Update'
    Yes 'R the publisher ran, and was not told to hold anything back' ($pub.Count -eq 1 -and $pub[0] -notmatch ' -NoUpload\b' -and $pub[0] -notmatch ' -NoPush\b')
    $pk = Called $r 'Package-Thornswood'
    Yes ('R the installer is built, without -NoPublish, into the staging folder' + $(if ($pk.Count) { ' (' + ($pk -join '; ') + ')' } else { '' })) (
        $pk.Count -eq 1 -and $pk[0] -notmatch ' -NoPublish\b' -and $pk[0].Contains(' -OutDir ' + $distDir))
    Yes '  around the setup program CI built for the tag, not one from out\ (#932)' ($pk.Count -eq 1 -and $pk[0] -match ' -Stub \S*setup-stub\.exe')
    Yes '  in the one file shape the site carries, -OneFile (#1213)' ($pk.Count -eq 1 -and $pk[0] -match ' -OneFile\b')
    Yes '  and so it goes on the site: Publish-Installer.ps1 is called' ((Called $r 'Publish-Installer').Count -eq 1)
    foreach ($n in 'Publish-News', 'Publish-Discord', 'Request-Restart') {
        Yes "R $n.ps1 is called" ((Called $r $n).Count -eq 1)
    }
    # What follows the tip: one call per half, on the main channel, each with the
    # install and the staging folder, because that is where the installer is. No
    # switch can hold either half back, so nothing here says -Skip anything, and
    # no clone is passed: the remirror works its own out from the channel.
    $post = Called $r 'Publish-PostShip'
    Yes ('R what follows the tip runs once (remirror) for main, with the install and the staging folder' +
         $(if ($post.Count) { ' (' + ($post -join '; ') + ')' } else { '' })) (
        $post.Count -eq 1 -and
        @($post | Where-Object { $_ -match ' -Channel main\b' -and $_.Contains(' -Root ' + $root) -and
                                 $_.Contains(' -DistRoot ' + $dist) -and $_ -notmatch ' -Skip' -and
                                 $_ -notmatch ' -ReleaseDir' }).Count -eq 1 -and
        @($post | Where-Object { $_ -match ' -Only Remirror\b' }).Count -eq 1 -and
        @($post | Where-Object { $_ -match ' -Only VirusTotal\b' }).Count -eq 0)
    # And the only launcher install is the mid-release one, into the root this
    # release was built from, before the publisher: there is no second one after
    # the tip, because a launcher updates itself from the feed it polls.
    $inst = Called $r 'Install-Launcher'
    Yes ('R Install-Launcher.ps1 runs once, on the root that shipped' + $(if ($inst.Count) { ' (' + ($inst -join '; ') + ')' } else { '' })) (
        $inst.Count -eq 1 -and $inst[0].Contains(' -Root ' + $root))
    $gone = Away $r
    Yes 'R the shipped launcher is not compiled here: Build-Launcher.ps1 is not called' ((Called $r 'Build-Launcher').Count -eq 0)
    Yes ('R the launcher and the setup program CI built are downloaded and verified: gh release download runs for each (' + ($gone -join '; ') + ')') (
        @($gone | Where-Object { $_ -match '^gh release download .*--pattern Thornswood\.exe' }).Count -eq 1 -and
        @($gone | Where-Object { $_ -match '^gh release download .*--pattern setup-stub\.exe' }).Count -eq 1)
    Yes 'R the feed reaches the VPS store: the site serves what the publisher wrote' (
        ([IO.File]::ReadAllText($siteFeed)) -match '20990101-0000')
    # The one thing pushed is the release tag (#444), on the commit the feed
    # names, after the publisher has sent the feed.
    $pushes = @($gone | Where-Object { $_ -match '^git .*\bpush\b' })
    Yes ('R the only git push is the release tag, release/main/20990101-0000' + $(if ($pushes.Count) { ' (' + ($pushes -join '; ') + ')' } else { '' })) (
        $pushes.Count -eq 1 -and $pushes[0] -match ' push origin refs/tags/release/main/20990101-0000$')
    $tags = @($gone | Where-Object { $_ -match '^git .*\btag\b' })
    Yes ('R the tag is made once, annotated, on the commit the feed names' + $(if ($tags.Count) { ' (' + ($tags -join '; ') + ')' } else { '' })) (
        $tags.Count -eq 1 -and $tags[0] -match (' tag -a release/main/20990101-0000 ' + ('ab12' * 10) + ' -F '))
    $at = @{}
    for ($i = 0; $i -lt $r.Calls.Count; $i++) {
        foreach ($k in 'Publish-Update', 'Request-Restart') { if (-not $at.ContainsKey($k) -and $r.Calls[$i].StartsWith($k)) { $at[$k] = $i } }
        if (-not $at.ContainsKey('tag') -and $r.Calls[$i] -match '^git .*\btag -a\b') { $at['tag'] = $i }
    }
    Yes 'R and only after the publisher has sent the feed, and after the release is announced' (
        $at.ContainsKey('tag') -and $at.ContainsKey('Publish-Update') -and $at['tag'] -gt $at['Publish-Update'] -and
        $at.ContainsKey('Request-Restart') -and $at['tag'] -gt $at['Request-Restart'])
    Yes 'R and it says so' ($r.Out -match 'release/main/20990101-0000 marks ab12ab12ab12, and it is on GitHub')
    $devNow = [IO.File]::ReadAllText($siteDevFeed) | ConvertFrom-Json
    Yes 'R a main ship preserves the independently published dev feed' ((Hash $siteDevFeed) -eq $devBeforeMain)
    Yes '  and the independently published dev baseline' ((Hash $siteDevBase) -eq $devBaselineBeforeMain)

    # ---- E: a dev dry run numbers itself from the site store, not from git ------------
    # launchers.txt on the dev store says 1.1.93.2 went out, main's feed on the
    # site says 1.1.93, so the next dev number is 1.1.93.3, worked out with no
    # git, gh, ssh or scp at all (#907).
    $e = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-Channel', 'dev', '-DryRun', '-Root', $rootDev, '-DistRoot', $dist, '-NoPause')
    $pub = Called $e 'Publish-Update'
    Yes ("E a dev dry run runs to the end (exit {0})" -f $e.Code) ($e.Code -eq 0 -and $e.Out -match 'Dry run finished')
    Yes ('E it goes out as the number after every dev launcher the store lists' + $(if ($pub.Count) { ' (' + $pub[0] + ')' } else { '' })) (
        $pub.Count -eq 1 -and $pub[0] -match ' -VersionOverride 1\.1\.93\.3\b')
    $gone = Away $e
    Yes ('E and asks nothing of git, gh, ssh or scp to get it' + $(if ($gone.Count) { ' (' + ($gone -join '; ') + ')' } else { '' })) ($gone.Count -eq 0)

    # ---- F: a Ship that keeps its launcher, whose feed did not send (#1055) ------------
    # -ModsOnly publishes no launcher, so there is no version.json naming one to
    # check and the publisher's exit code is all Ship has. The publisher ends
    # NOT SHIPPED with exit 1 now; Ship must stop there and tell nobody.
    $env:TS_PUB_FAIL = '1'
    try {
        $f = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-Channel', 'dev', '-ModsOnly', '-Root', $rootDev, '-DistRoot', $dist, '-NoPause')
    } finally { $env:TS_PUB_FAIL = '' }
    Yes ("F a mods-only Ship whose feed did not send stops, NOTHING was published (exit {0})" -f $f.Code) (
        $f.Code -eq 1 -and (Called $f 'Publish-Update').Count -eq 1 -and $f.Out -match 'NOTHING was published')
    foreach ($n in 'Publish-News', 'Publish-Discord', 'Request-Restart', 'Publish-PostShip') {
        Yes "F $n.ps1 is not called" ((Called $f $n).Count -eq 0)
    }
    $pushes = @(Away $f | Where-Object { $_ -match '^git .*\b(push|tag)\b' })
    Yes ('F and no release tag is made' + $(if ($pushes.Count) { ' (' + ($pushes -join '; ') + ')' } else { '' })) ($pushes.Count -eq 0)

    # ---- G: no -Root, on a machine that recorded its dev release folder (#1692) --------
    # Setup-ShipMachine.ps1 -Root writes the file Where.ps1 ShipRoots names, in
    # this machine's own data; Ship takes the folder from it with no -Root.
    $relDevRoot = Join-Path $T 'Release-DevBuild'
    New-Item -ItemType Directory -Force -Path (Join-Path $relDevRoot 'Launcher') | Out-Null
    $relExe = Join-Path $relDevRoot 'Launcher\Thornswood.exe'
    [IO.File]::WriteAllText($relExe, 'the launcher as installed')
    (Get-Item -LiteralPath $relExe).LastWriteTimeUtc = [DateTime]::UtcNow.AddHours(-1)
    $shipRoots = Join-Path $appdata 'Thornswood\ship-roots.json'
    [IO.File]::WriteAllText($shipRoots, (ConvertTo-Json -InputObject ([ordered]@{ dev = $relDevRoot })))
    try {
        $g = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-Channel', 'dev', '-DryRun', '-DistRoot', $dist, '-NoPause')
    } finally { Remove-Item -LiteralPath $shipRoots -Force -ErrorAction SilentlyContinue }
    Yes ("G a dev dry run with no -Root runs to the end (exit {0})" -f $g.Code) ($g.Code -eq 0 -and $g.Out -match 'Dry run finished')
    $built = Called $g 'Build-Launcher'
    $inst = Called $g 'Install-Launcher'
    $pub = Called $g 'Publish-Update'
    Yes '  building, installing and publishing the folder this machine recorded for dev, not <root>-DevBuild' (
        $built.Count -eq 1 -and $built[0].Contains(' -Root ' + $relDevRoot) -and
        $inst.Count -eq 1 -and $inst[0].Contains(' -Root ' + $relDevRoot) -and
        $pub.Count -eq 1 -and $pub[0].Contains(' -Root ' + $relDevRoot))

    # ---- H: a folder Vortex deploys into (#1692) ---------------------------------------
    $vortexRoot = Join-Path $T 'Vortex-DevBuild'
    New-Item -ItemType Directory -Force -Path (Join-Path $vortexRoot 'Launcher'), (Join-Path $vortexRoot 'Game\Data') | Out-Null
    [IO.File]::WriteAllText((Join-Path $vortexRoot 'Launcher\Thornswood.exe'), 'the launcher as installed')
    [IO.File]::WriteAllText((Join-Path $vortexRoot 'Game\Data\vortex.deployment.json'), '{}')
    $h = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-Channel', 'dev', '-DryRun', '-Root', $vortexRoot, '-DistRoot', $dist, '-NoPause')
    Yes ("H a Ship from a folder Vortex deploys into is refused (exit {0})" -f $h.Code) (
        $h.Code -eq 1 -and $h.Out -match 'is a folder Vortex deploys into' -and $h.Out -match 'Nothing was built')
    Yes '  before anything is built, installed or published' (
        (Called $h 'Build-Launcher').Count -eq 0 -and (Called $h 'Install-Launcher').Count -eq 0 -and (Called $h 'Publish-Update').Count -eq 0)
    Yes '  and Updater.cs is on the version it had' ((Read-Version $updaterCs) -eq '1.1.93')

    # ---- I: generated files out of date (#1692) ------------------------------------------
    # Generated.ps1 stood in for: this folder's files are stale. The real one
    # is held to the folder by tests\test-build-generated.ps1.
    $genRoot = Join-Path $T 'Gen-DevBuild'
    New-Item -ItemType Directory -Force -Path (Join-Path $genRoot 'Launcher'), (Join-Path $genRoot 'Game') | Out-Null
    [IO.File]::WriteAllText((Join-Path $genRoot 'Launcher\Thornswood.exe'), 'the launcher as installed')
    [IO.File]::WriteAllText((Join-Path $genRoot 'Game\SkyrimSE.exe'), 'skyrim')
    [IO.File]::WriteAllText((Join-Path $repo 'scripts\mods\Generated.ps1'), @'
function Get-GeneratedState($Root, $ListPath) { return [pscustomobject]@{ Current = $false; Record = $null } }
function Get-GeneratedStaleSays($State, [string]$Channel) { return 'The generated files here are out of date (stand-in).' }
'@)
    try {
        $i = Invoke-Ship @("The map marker points at the right door`n- The marker over a house now sits on the door you walk through", '-Channel', 'dev', '-DryRun', '-Root', $genRoot, '-DistRoot', $dist, '-NoPause')
    } finally { Remove-Item -LiteralPath (Join-Path $repo 'scripts\mods\Generated.ps1') -Force -ErrorAction SilentlyContinue }
    Yes ("I a Ship whose generated files are out of date stops (exit {0})" -f $i.Code) ($i.Code -eq 1 -and $i.Out -match 'out of date \(stand-in\)')
    Yes '  before the launcher is built or installed, and before anything is published' (
        (Called $i 'Build-Launcher').Count -eq 0 -and (Called $i 'Install-Launcher').Count -eq 0 -and (Called $i 'Publish-Update').Count -eq 0)
    Yes '  and the installed launcher is the one it had' ([IO.File]::ReadAllText((Join-Path $genRoot 'Launcher\Thornswood.exe')) -eq 'the launcher as installed')

    # ---- J, K, L: SkyUI's menus need node (#1913) ---------------------------------------
    # A game folder that gets as far as the SkyUI menus step: generated files
    # current, the in game plugin in place, the bodies covered (all stood in
    # for; each has its own harness). node is a stand-in on PATH that writes
    # down what it was asked and exits with TS_NODE_EXIT, so these run the
    # same on a machine with node and on one without.
    $skyRoot = Join-Path $T 'Sky-DevBuild'
    New-Item -ItemType Directory -Force -Path (Join-Path $skyRoot 'Launcher'), (Join-Path $skyRoot 'Game\Data\Platform\Plugins'),
        (Join-Path $repo 'game\plugins') | Out-Null
    $skyExe = Join-Path $skyRoot 'Launcher\Thornswood.exe'
    [IO.File]::WriteAllText($skyExe, 'the launcher as installed')
    (Get-Item -LiteralPath $skyExe).LastWriteTimeUtc = [DateTime]::UtcNow.AddHours(-1)
    [IO.File]::WriteAllText((Join-Path $skyRoot 'Game\SkyrimSE.exe'), 'skyrim')
    foreach ($p in (Join-Path $repo 'game\plugins\stand-in.js'), (Join-Path $skyRoot 'Game\Data\Platform\Plugins\stand-in.js')) {
        [IO.File]::WriteAllText($p, '// the in game plugin, as the source has it')
    }
    [IO.File]::WriteAllText((Join-Path $repo 'scripts\mods\Generated.ps1'), @'
function Get-GeneratedState($Root, $ListPath) { return [pscustomobject]@{ Current = $true; Record = [pscustomobject]@{ Files = @('stand-in') } } }
function Get-GeneratedStaleSays($State, [string]$Channel) { return '' }
'@)
    # The covered bodies stand-in exits with TS_BODIES_EXIT, 0 when unset, for M.
    [IO.File]::WriteAllText((Join-Path $repo 'scripts\mods\Check-CoveredBodies.ps1'), "param([string]`$Game, [switch]`$Quiet)`r`nexit ([int]`$env:TS_BODIES_EXIT)`r`n")
    $nodeStandIn = Join-Path $bin 'node.ps1'
    $nodeLine = '[IO.File]::AppendAllText($env:TS_DRY_CALLS, ((@(''node'') + @($args | ForEach-Object { [string]$_ })) -join '' '') + "`r`n")'
    # PATH without any folder that holds a real node, for J.
    $noNodePath = (@($bin) + @($oldPath -split ';' | Where-Object {
        $_ -and -not (Test-Path -LiteralPath (Join-Path $_ 'node.exe')) -and -not (Test-Path -LiteralPath (Join-Path $_ 'node.cmd'))
    })) -join ';'
    $skyNote = "The map marker points at the right door`n- The marker over a house now sits on the door you walk through"
    $skyArgs = @($skyNote, '-Channel', 'dev', '-DryRun', '-Root', $skyRoot, '-DistRoot', $dist, '-NoPause')
    $oldNodeExit = $env:TS_NODE_EXIT
    $oldBodiesExit = $env:TS_BODIES_EXIT
    try {
        # J: no node at all.
        $env:PATH = $noNodePath
        $j = Invoke-Ship $skyArgs
        $env:PATH = $bin + ';' + $oldPath
        Yes ("J a Ship with a game folder and no node is refused (exit {0})" -f $j.Code) ($j.Code -eq 1 -and $j.Out -match 'STOP\. node is not on this machine')
        Yes '  and says why: SkyUI''s menus are read with it, and how to install it' (
            $j.Out -match 'Check-SkyUIMenus\.js' -and $j.Out -match 'SkyUI error box' -and $j.Out -match 'winget install --id OpenJS\.NodeJS\.LTS')
        Yes '  before anything is built, installed, copied into the game or published' (
            (Called $j 'Build-Launcher').Count -eq 0 -and (Called $j 'Install-Launcher').Count -eq 0 -and
            (Called $j 'Go').Count -eq 0 -and (Called $j 'Publish-Update').Count -eq 0)
        Yes '  and it no longer says it in yellow and carries on' ($j.Out -notmatch 'so SkyUI''s menus were not read' -and $j.Out -notmatch 'Dry run finished')
        Yes '  and Updater.cs is on the version it had' ((Read-Version $updaterCs) -eq '1.1.93')
        Yes '  and the installed launcher is the one it had' ([IO.File]::ReadAllText($skyExe) -eq 'the launcher as installed')

        [IO.File]::WriteAllText($nodeStandIn, $nodeLine + "`r`nexit ([int]`$env:TS_NODE_EXIT)`r`n")

        # K: the check could not read something.
        $env:TS_NODE_EXIT = '1'
        $k = Invoke-Ship $skyArgs
        $ran = Called $k 'node'
        Yes ("K a Ship whose SkyUI menus could not be read is refused (exit {0})" -f $k.Code) (
            $k.Code -eq 1 -and $k.Out -match 'STOP\. SkyUI''s menus could not all be read \(Check-SkyUIMenus\.js exit 1\)')
        Yes '  after the check really ran on the game folder' ($ran.Count -eq 1 -and $ran[0] -match 'Check-SkyUIMenus\.js' -and $ran[0].Contains((Join-Path $skyRoot 'Game\Data')))
        Yes '  and nothing is published' ((Called $k 'Publish-Update').Count -eq 0 -and (Away $k).Count -eq 0)
        Yes '  and Updater.cs is on the version it had' ((Read-Version $updaterCs) -eq '1.1.93')

        # L: the same folder, a check that passes, runs to the end.
        $env:TS_NODE_EXIT = '0'
        $l = Invoke-Ship $skyArgs
        Yes ("L the same folder with node and a check that passes runs to the end (exit {0})" -f $l.Code) ($l.Code -eq 0 -and $l.Out -match 'Dry run finished')
        if ($l.Code -ne 0) { $l.Out -split "`r?`n" | Select-Object -Last 15 | ForEach-Object { Write-Host ("      " + $_) } }
        Yes '  and the check ran once' ((Called $l 'node').Count -eq 1)
        Yes '  and the release was built and published, told not to upload or push' (
            (Called $l 'Build-Launcher').Count -eq 1 -and @(Called $l 'Publish-Update' | Where-Object { $_ -match ' -NoPush\b' }).Count -eq 1)

        # And a mismatch, exit 2, refuses as it did (#960).
        $env:TS_NODE_EXIT = '2'
        $m = Invoke-Ship $skyArgs
        Yes ("L a mismatch, exit 2, is still refused (exit {0})" -f $m.Code) (
            $m.Code -eq 1 -and $m.Out -match 'not the version its script wants' -and (Called $m 'Publish-Update').Count -eq 0)

        # ---- M: a body mesh the covered bodies check could not read (#1956) ----------
        # Patrick, 5 Oct: refuse, the way the SkyUI menus step does since #1913.
        # It used to print a yellow line and ship, on main as well as dev. The
        # SkyUI check passes here, so M stops on the bodies and nothing else.
        $env:TS_NODE_EXIT = '0'
        $env:TS_BODIES_EXIT = '1'
        $mainArgs = @($skyNote, '-DryRun', '-Root', $skyRoot, '-DistRoot', $dist, '-NoPause')
        foreach ($case in @(@{ Name = 'dev'; Args = $skyArgs }, @{ Name = 'main'; Args = $mainArgs })) {
            $b = Invoke-Ship $case.Args
            Yes ("M a {0} Ship whose body meshes could not all be read is refused (exit {1})" -f $case.Name, $b.Code) (
                $b.Code -eq 1 -and $b.Out -match 'STOP\. The body meshes in the game folder could not all be read \(Check-CoveredBodies\.ps1 exit 1\)')
            Yes '  and no longer says it in yellow and carries on' ($b.Out -notmatch 'the body meshes could not all be read; see above' -and $b.Out -notmatch 'Dry run finished')
            Yes '  before the SkyUI menus are read or anything is published' (
                (Called $b 'node').Count -eq 0 -and (Called $b 'Publish-Update').Count -eq 0 -and (Away $b).Count -eq 0)
            Yes '  and Updater.cs is on the version it had' ((Read-Version $updaterCs) -eq '1.1.93')
        }

        # A nude body, exit 2, on dev still only warns (#405): M changed exit 1 only.
        $env:TS_BODIES_EXIT = '2'
        $n = Invoke-Ship $skyArgs
        Yes ("M a nude body on dev still warns and runs to the end (exit {0})" -f $n.Code) (
            $n.Code -eq 0 -and $n.Out -match 'a body in the game folder is nude \(issue #405\); shipping anyway' -and $n.Out -match 'Dry run finished')
    } finally {
        $env:PATH = $bin + ';' + $oldPath
        $env:TS_NODE_EXIT = $oldNodeExit
        $env:TS_BODIES_EXIT = $oldBodiesExit
        Remove-Item -LiteralPath $nodeStandIn -Force -ErrorAction SilentlyContinue
    }
}
finally {
    $env:PATH = $oldPath
    $env:LOCALAPPDATA = $oldAppData
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
    $env:TS_DRY_CALLS = $oldCalls
    $env:TS_GH_DL = $oldGhDl
    $env:THORNSWOOD_TEST_SITE_DIR = $oldSite
    if ($null -eq $oldScratch) { Remove-Item Env:THORNSWOOD_SCRATCH_ROOT -ErrorAction SilentlyContinue } else { $env:THORNSWOOD_SCRATCH_ROOT = $oldScratch }
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}

Done
