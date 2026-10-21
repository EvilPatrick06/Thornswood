<#
  test-installer-behind-gate.ps1

  A main release refuses to go out while the public installer is behind, or
  while how far behind it is cannot be told, and a dev release still only
  warns.

  WHY THIS EXISTS. The second half of issue #422. The first half baked the
  releases feed path into Package-Thornswood so a rebuilt installer is seeded
  from the right feed (PR #228). This half is the gate: the installer falls
  one release further behind on every main Ship, because Ship does not rebuild
  the installer with the release, and the only sign was a yellow line on the
  closing screen nobody rereads. So an installer drifted release after release
  until a new person sat through the whole pile on first launch.

  Now a main Ship works out how far behind the installer is BEFORE it
  publishes, and refuses if it is behind and nothing here was going to rebuild
  it. -Package is the way through, because it rebuilds the installer after the
  release, so the two go out together. A dev release never refuses: it does
  not touch the installer. Nor does a hotfix: it is the live build plus one
  urgent fix, and holding it for a twenty-minute rebuild is the opposite of
  what a hotfix is for.

  THE INSTALLER ON THE SITE, NOT A ZIP ON THIS DISK (#3043). Until 21 October
  the gate timed a Thornswood-Setup.zip on the shipping machine's own disk, so
  with no zip there (Clean-Everything -Installers, a new machine, another
  install root) it let a main release through however far behind the published
  installer was. Now Package-Thornswood names the release the installer is
  level with in a note beside the exe, Publish-Installer writes it into the
  exe's entry in the site's files.json, and the gate counts the feed's releases
  after that one, refusing when it cannot read it. Part N drives the note,
  part M and GATE drive Measure-Installer and the gate with no zip anywhere.

  It lifts Measure-Installer and the gate out of the shipped Ship.ps1 by the
  parser, the way test-ship-gate.ps1 lifts the Git gate, and drives them
  against a throwaway site folder (THORNSWOOD_TEST_SITE_DIR, the way
  Feed-Store.ps1's Read-SiteFeed is driven) and releases feed, so nothing here
  touches this repository, the network or any launcher. Read only apart from
  files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $ShipPath) { $ShipPath = Join-Path $Repo 'scripts\release\Ship.ps1' }
$Rel = Join-Path $Repo 'scripts\release'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    exit $(if ($script:fail) { 1 } else { 0 })
}

$src = [IO.File]::ReadAllText($ShipPath)
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$tokens, [ref]$errs)
Yes 'Ship.ps1 parses' (@($errs).Count -eq 0)

# ---- lift the function and the gate out of the shipped script ------------------
$FnAst = [System.Management.Automation.Language.FunctionDefinitionAst]
$IfAst = [System.Management.Automation.Language.IfStatementAst]

$measure = ''
foreach ($fn in $ast.FindAll({ param($n) $n -is $FnAst }, $true)) {
    if ($fn.Name -eq 'Measure-Installer') { $measure = $fn.Extent.Text; break }
}
Yes 'Ship.ps1 has Measure-Installer' ($measure -ne '')

# The gate is the if that carries the whole rule: it reads Measure-Installer and
# stops with Die. Found by both so another if never stands in.
$gate = ''
foreach ($n in $ast.FindAll({ param($x) $x -is $IfAst }, $true)) {
    $text = $n.Extent.Text
    if ($text.Contains('$ins = Measure-Installer') -and $text.Contains('Die') -and $text.Contains('-not $Package')) {
        $gate = $text; break
    }
}
Yes 'Ship.ps1 has the installer gate' ($gate -ne '')

# The gate refuses on the main channel and lets a dev release, a hotfix, a dry
# run and a -Package release through, read off the condition itself so a change
# to it is caught here rather than shipped.
Yes 'the gate is off for a dev release'   ($gate -match '-not \$Dev\b')
Yes 'the gate is off for a hotfix'        ($gate -match '-not \$hotfix\b')
Yes 'the gate is off for a dry run'       ($gate -match '-not \$DryRun\b')
Yes 'the gate is off when -Package is set' ($gate -match '-not \$Package\b')

# The gate must sit before the publish, or a refusal leaves a release half out.
$gateAt = $src.IndexOf($gate)
$publishAt = $src.IndexOf("Head 'Publishing'")
Yes 'the gate runs before the publish' ($gateAt -ge 0 -and $publishAt -gt $gateAt)

# Nothing on this machine's disk stands in for the published installer (#3043):
# no zip is looked for, and the old $Root\_dist fallback is gone.
Yes 'Measure-Installer reads no Thornswood-Setup.zip' ($measure -and -not $measure.Contains('Thornswood-Setup.zip'))
Yes 'Measure-Installer has no $Root\_dist fallback' ($measure -and $measure -notmatch '\$Root\s*[''"]?\s*_dist|Join-Path \$Root')
Yes 'Measure-Installer reads the site''s list of downloads' ($measure -match 'Read-SiteDownloads')

if (-not ($measure -and $gate)) { Done }

# The sections lifted below call these, which Ship.ps1 dot-sources.
. (Join-Path $Rel 'Read-JsonFile.ps1')
. (Join-Path $Rel 'Feed-Store.ps1')
. (Join-Path $Rel 'Release-Name.ps1')

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tsinst-' + [Guid]::NewGuid().ToString('N'))
$DistRoot = Join-Path $tmp 'dist'
$Root = Join-Path $tmp 'Play'
$MainReleaseDir = Join-Path $tmp 'feed-main'
$site = Join-Path $tmp 'site'
$siteFiles = Join-Path $site 'files'
$feed = Join-Path $MainReleaseDir 'version.json'
$noBom = New-Object Text.UTF8Encoding($false)

function Set-Feed([string[]]$ids, [string]$current = '') {
    $packs = ($ids | ForEach-Object { '{"id":"' + $_ + '"}' }) -join ','
    $rel = if ($current) { ',"release":{"id":"' + $current + '"}' } else { '' }
    [IO.File]::WriteAllText($feed, '{"launcherVersion":"1.1.94","packs":[' + $packs + ']' + $rel + '}', $noBom)
}
function Set-ReleaseList([string[]]$ids) {
    $f = Join-Path $MainReleaseDir 'releases.json'
    if ($null -eq $ids) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }; return }
    [IO.File]::WriteAllText($f, '[' + (($ids | ForEach-Object { '{"id":"' + $_ + '"}' }) -join ',') + ']', $noBom)
}
# The site's files.json: the installer's entry naming $release, or no release
# when it is '', or no installer at all when $null.
function Set-Site($release) {
    New-Item -ItemType Directory -Force -Path $siteFiles | Out-Null
    $all = [ordered]@{ 'Thornswood-Notes.txt' = @{ label = 'Notes' } }
    if ($null -ne $release) {
        $e = [ordered]@{ label = 'Thornswood installer'; version = '6-1-2026 12:00 PM'; sha256 = ('a' * 64) }
        if ($release) { $e['release'] = $release }
        $all['Thornswood-Setup.exe'] = $e
    }
    [IO.File]::WriteAllText((Join-Path $siteFiles 'files.json'), ($all | ConvertTo-Json -Depth 4), $noBom)
}
function Drop-Site { if (Test-Path -LiteralPath $siteFiles) { Remove-Item -LiteralPath $siteFiles -Recurse -Force } }

# Die is Ship's own exit; here it throws, so a refusal comes back as its words.
# Unbump records that it was asked, so the gate putting the version back before
# it stops is checked the way the real gate calls it.
function Say($m, $c) { }
function Head($m) { }
function Die($m) { throw ('STOP. ' + $m) }
function Unbump($why) { $global:tsUnbumped += @($why) }
. ([scriptblock]::Create($measure))
$gateSb = [scriptblock]::Create($gate)

# Not called Measure: that is an alias for Measure-Object and would win.
function Ask-Installer { return (Measure-Installer) }
# '' when the gate lets the release through, the STOP line when it does not.
function Gate([bool]$dev, [bool]$hotfix, [bool]$dry, [bool]$pkg) {
    $global:tsUnbumped = @()
    $Dev = $dev; $DryRun = $dry; $Package = $pkg
    Set-Variable -Name hotfix -Value $hotfix
    try { . $gateSb | Out-Null; return '' }
    catch { return [string]$_.Exception.Message }
}

$siteWas = $env:THORNSWOOD_TEST_SITE_DIR
try {
    $env:THORNSWOOD_TEST_SITE_DIR = $site
    New-Item -ItemType Directory -Force -Path $MainReleaseDir | Out-Null
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    # No installer zip anywhere in any of this: the whole point of #3043.
    $zipAnywhere = @(Get-ChildItem -LiteralPath $tmp -Recurse -Filter 'Thornswood-Setup.zip' -ErrorAction SilentlyContinue)
    Yes 'no Thornswood-Setup.zip exists anywhere this run looks' ($zipAnywhere.Count -eq 0)

    # ---- N. the note Package leaves beside the installer, and Publish reads ------
    $out = Join-Path $tmp 'out'
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    $sha = ('0123456789abcdef' * 4)
    Write-InstallerReleaseNote $out '20260701-100000' $sha.ToUpper()
    Yes 'N1 the note is written beside the installer' (Test-Path -LiteralPath (Join-Path $out 'Thornswood-Setup.release.json'))
    Yes 'N1 and reads back as the release, for the exe it names' ((Read-InstallerReleaseNote $out $sha) -eq '20260701-100000')
    $r = ''; try { Read-InstallerReleaseNote $out ('f' * 64) | Out-Null } catch { $r = $_.Exception.Message }
    Yes "N2 a note for another exe is refused: '$r'" ($r -match 'another Thornswood-Setup\.exe')
    Remove-Item -LiteralPath (Join-Path $out 'Thornswood-Setup.release.json') -Force
    $r = ''; try { Read-InstallerReleaseNote $out $sha | Out-Null } catch { $r = $_.Exception.Message }
    Yes "N3 no note is refused, naming Package-Thornswood: '$r'" ($r -match 'Package-Thornswood\.ps1')
    $r = ''; try { Write-InstallerReleaseNote $out 'not-an-id' $sha } catch { $r = $_.Exception.Message }
    Yes "N4 a note is never written for something that is not a release id: '$r'" ($r -match 'not a release id')

    # The newest release a feed names, and how many come after a given one.
    Set-Feed @('20260101-0900', '20260701-1000', '20260801-1100-1', '20260801-1100-2') '20260801-1100-2'
    Set-ReleaseList @('20260901-120000', '20260801-1100-2')
    $doc = ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText($feed)) $feed
    $list = Read-ReleaseListFile (Join-Path $MainReleaseDir 'releases.json')
    Yes 'N5 the newest release on the feed includes the store''s list' ((Get-NewestFeedRelease $doc $list) -eq '20260901-120000')
    Yes 'N6 the split parts of a release count once, and the store''s list counts' ((Get-ReleasesAfter '20260701-1000' $doc $list) -eq 2)
    Yes 'N7 a minute id and a second id compare by time' ((Get-ReleasesAfter '20260801-110000' $doc $list) -eq 1)
    Yes 'N8 the newest release has none after it' ((Get-ReleasesAfter '20260901-120000' $doc $list) -eq 0)
    Yes 'N9 something that is not an id is -1, never 0' ((Get-ReleasesAfter 'nonsense' $doc $list) -eq -1)
    Set-ReleaseList $null

    # Package writes the note and Publish-Installer reads it and records it,
    # read off the scripts themselves; neither can run whole here.
    $pkg = [IO.File]::ReadAllText((Join-Path $Rel 'Package-Thornswood.ps1'))
    $pub = [IO.File]::ReadAllText((Join-Path $Rel 'Publish-Installer.ps1'))
    Yes 'N10 Package-Thornswood names the newest release on the feed' ($pkg -match '\$installerRelease = Get-NewestFeedRelease')
    Yes 'N10 and stops when the feed names none' ($pkg -match 'if \(-not \$installerRelease\) \{\s*Die')
    Yes 'N10 and writes the note for the signed exe' ($pkg -match 'Write-InstallerReleaseNote \$OutDir \$installerRelease \(Get-Sha256 \$exe\)')
    $signAt = $pkg.IndexOf("Head 'Signing the installer'")
    $noteAt = $pkg.IndexOf('Write-InstallerReleaseNote $OutDir')
    Yes 'N10 after signing, so the sha256 is the one people download' ($signAt -ge 0 -and $noteAt -gt $signAt)
    Yes 'N11 Publish-Installer reads the note for the exe it publishes' ($pub -match '\$installerRelease = Read-InstallerReleaseNote \$OutDir \$exeSha')
    $readAt = $pub.IndexOf('Read-InstallerReleaseNote $OutDir')
    $sendAt = $pub.IndexOf('foreach ($pair in $send)')
    Yes 'N11 before anything is sent' ($readAt -ge 0 -and $sendAt -gt $readAt)
    Yes 'N11 and both shapes of the exe''s entry carry the release' (([regex]::Matches($pub, 'release = \$installerRelease')).Count -eq 2)

    # ---- M. Measure-Installer reads the installer on the site -------------------
    Set-Feed @('20260101-0900', '20260601-1200', '20260701-1000', '20260801-1100-1', '20260801-1100-2')
    Set-Site '20260601-1200'
    $m = Ask-Installer
    Yes 'M1 the installer on the site is read' ($m.Known -and $m.Release -eq '20260601-1200')
    Yes "M1 two releases came after it, the split one counted once: $($m.Behind)" ($m.Behind -eq 2)

    Set-Site '20260801-1100-2'
    $m = Ask-Installer
    Yes "M2 an installer level with the newest release is not behind: $($m.Behind)" ($m.Known -and $m.Behind -eq 0)

    Drop-Site
    $m = Ask-Installer
    Yes "M3 no list of downloads on the site is not known: $($m.Why)" (-not $m.Known -and $m.Why -match 'no Thornswood-Setup\.exe')

    Set-Site $null
    $m = Ask-Installer
    Yes "M4 a list with no installer in it is not known: $($m.Why)" (-not $m.Known -and $m.Why -match 'no Thornswood-Setup\.exe')

    Set-Site ''
    $m = Ask-Installer
    Yes "M5 an installer that does not say its release is not known: $($m.Why)" (-not $m.Known -and $m.Why -match 'which release')

    Set-Site 'yesterday'
    $m = Ask-Installer
    Yes "M6 a release that is not an id is not known: $($m.Why)" (-not $m.Known -and $m.Why -match 'not a release id')

    New-Item -ItemType Directory -Force -Path $siteFiles | Out-Null
    [IO.File]::WriteAllText((Join-Path $siteFiles 'files.json'), '{"Thornswood-Setup.exe": {', $noBom)
    $m = Ask-Installer
    Yes "M7 a list that does not read is not known: $($m.Why)" (-not $m.Known -and $m.Why -match 'did not read')

    Set-Site '20260601-1200'
    Remove-Item -LiteralPath $feed -Force
    $m = Ask-Installer
    Yes "M8 no main feed here is not known: $($m.Why)" (-not $m.Known -and $m.Why -match 'no main feed')

    # The site itself not answering is a throw, never an empty list.
    $env:THORNSWOOD_TEST_SITE_DIR = ''
    $r = ''; try { Read-SiteDownloads -SiteUrl 'http://127.0.0.1:9' | Out-Null } catch { $r = $_.Exception.Message }
    Yes "M9 a site that does not answer throws: '$r'" ($r -ne '')
    $env:THORNSWOOD_TEST_SITE_DIR = $site

    # The site serves files.json at /file/files.json like any other download,
    # which is where Read-SiteDownloads reads it. Read off the route in
    # site\server.js, so a change that stops serving it is caught here.
    $server = [IO.File]::ReadAllText((Join-Path $Repo 'site\server.js'))
    $route = [regex]::Match($server, 'p\.match\(/(\^\\/file\\/[^\r\n]*?\$)/\)')
    Yes 'M10 the site has its /file/ download route' ($route.Success)
    if ($route.Success) {
        $rx = $route.Groups[1].Value.Replace('\/', '/')
        Yes "M10 and it serves /file/files.json ($rx)" ('/file/files.json' -match $rx)
    }
    Yes 'M10 and Read-SiteDownloads reads it there' ((Get-Command Read-SiteDownloads).Definition -match "'/file/files\.json'")

    # ---- the gate: a main release refuses while the installer is behind ------------
    Set-Feed @('20260601-1200', '20260701-1000', '20260801-1100')
    Set-Site '20260601-1200'   # two behind

    $r = Gate $false $false $false $false
    Yes "GATE main and behind stops the release, with no zip on this disk: '$r'" ($r -like 'STOP.*')
    Yes 'GATE it says how far behind and which release the installer carries' ($r -match '\b2 releases behind' -and $r -match '20260601-1200')
    Yes 'GATE it offers -Package and Package-Thornswood.ps1' ($r -match '-Package' -and $r -match 'Package-Thornswood\.ps1')
    Yes 'GATE it puts the version back before it stops' (@($global:tsUnbumped).Count -ge 1)

    $r = Gate $false $false $false $true
    Yes "GATE main with -Package is not refused, the rebuild is coming: '$r'" ($r -eq '')

    $r = Gate $true $false $false $false
    Yes "GATE a dev release is never refused for behind: '$r'" ($r -eq '')

    $r = Gate $false $true $false $false
    Yes "GATE a hotfix is never refused for behind: '$r'" ($r -eq '')

    $r = Gate $false $false $true $false
    Yes "GATE a dry run is not refused: '$r'" ($r -eq '')

    # ---- a current installer goes through; one nobody can measure does not ---------
    Set-Site '20260801-1100'
    $r = Gate $false $false $false $false
    Yes "GATE main with a current installer goes through: '$r'" ($r -eq '')

    Set-Site ''
    $r = Gate $false $false $false $false
    Yes "GATE main with an installer that does not say its release stops: '$r'" ($r -like 'STOP.*' -and $r -match 'cannot be told')
    Yes 'GATE and puts the version back first' (@($global:tsUnbumped).Count -ge 1)
    Yes 'GATE and offers -Package' ($r -match '-Package')

    Drop-Site
    $r = Gate $false $false $false $false
    Yes "GATE main with no installer on the site stops: '$r'" ($r -like 'STOP.*' -and $r -match 'cannot be told')

    $r = Gate $false $false $false $true
    Yes "GATE but -Package, which publishes one, goes through: '$r'" ($r -eq '')
}
finally {
    $env:THORNSWOOD_TEST_SITE_DIR = $siteWas
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
