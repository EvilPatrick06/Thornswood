<#
  test-2661-keep-feed-launcher.ps1

  A main Ship with -Package that keeps the feed's launcher packs the launcher
  the feed offers. Issue #2661.

  Package-Thornswood.ps1 packs <root>\Launcher\Thornswood.exe as it finds it.
  A Ship that builds a launcher installs it there first. One that keeps the
  feed's (Test-KeepFeedLauncher, #921, or -ModsOnly) set $ModsOnly, which also
  skipped the only code that put an exe in the root. That held while main's
  root was Patrick's own install, whose launcher updated itself to the feed's;
  main's ship root local\release-main (#2448, #2603) is never started, so
  -Package packed whatever exe the folder held, or stopped at "MISSING the
  launcher" after the release was already out (#2243).

  Ship.ps1 now has Get-FeedLauncher (download the feed's launcherUrl, check it
  against launcherSha256 and the signature) and Install-FeedLauncher (leave a
  folder already holding it alone, else put the checked exe in place with
  Install-Launcher.ps1 -From and read it back), run before anything is built
  or published on a main Ship with -Package that keeps the feed's launcher.

  This lifts both out of the shipped Ship.ps1 by the parser, the way
  test-ship-ci-sign.ps1 lifts Set-ReleaseLauncherSignature, and drives them
  against a file:// feed, a stand-in Get-PublishSignRefusal and stand-in
  installers, so no network, certificate or signtool is needed:
    1. a root with no Launcher folder ends with the feed's exe in it;
    2. a root holding another exe ends with the feed's exe in it;
    3. a root already holding the feed's exe is left alone;
    4. a download that is not the feed's sha256, one signed by somebody else,
       a feed naming no whole launcher and a URL that does not answer each
       stop with a reason, and leave nothing half written and the root as it
       was;
    5. an installer that fails, or that puts nothing in place, stops too.
  It also checks the order in Ship.ps1: after the keep decision and the
  generated files and node checks (#1692), on main with -Package and not on
  a dry run, before Publish-Update and Package-Thornswood, and that a reason
  stops the Ship. If a name moves, this says so rather than
  quietly testing nothing.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ShipPath) { $ShipPath = Join-Path (Split-Path -Parent $Here) 'scripts/release/Ship.ps1' }
$InstallPath = Join-Path (Split-Path -Parent $ShipPath) 'Install-Launcher.ps1'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

# ---- lift the functions -----------------------------------------------------
# Line ends as LF, so a checkout with CRLF reads the same.
$src = [IO.File]::ReadAllText($ShipPath) -replace "`r`n", "`n"
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$t, [ref]$e)
Yes 'Ship.ps1 parses' (@($e).Count -eq 0)

$FnAst = [System.Management.Automation.Language.FunctionDefinitionAst]
$fns = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is $FnAst }, $true)) { $fns[$f.Name] = $f.Extent.Text }
foreach ($n in 'Get-FeedLauncher', 'Install-FeedLauncher') {
    Yes "Ship.ps1 has $n" ($fns.ContainsKey($n))
    if (-not $fns.ContainsKey($n)) { Done }
    Invoke-Expression $fns[$n]
}

# ---- the order in Ship.ps1 --------------------------------------------------
$iAssert  = $src.IndexOf(". (Join-Path `$Here 'Assert-PublishSigned.ps1')")
$iSeed    = $src.IndexOf("`n`$pubLauncher = `$null")
$iKeep    = $src.IndexOf('if (Test-KeepFeedLauncher $pubLauncher')
$iKept    = $src.IndexOf('$ModsOnly = $true')
$iGen     = $src.IndexOf("Head 'Generated files'")
$iNode    = $src.IndexOf("Die ('node is not on this machine")
$iWhen    = $src.IndexOf('if ($Package -and -not $Dev -and -not $DryRun -and $ModsOnly) {')
$iStep    = $src.IndexOf('$fed = Install-FeedLauncher $pubLauncher $Root $feedLauncherDir $feedSigner (Join-Path $Here ''Install-Launcher.ps1'')')
$iDie     = $src.IndexOf('if ($fed.Why) { Die $fed.Why }')
$iBuild   = $src.IndexOf("`nif (-not `$ModsOnly) {`n    # The exe's time going in")
$iPublish = $src.IndexOf("& (Join-Path `$Here 'Publish-Update.ps1') @pubArgs")
$iPackage = $src.IndexOf("& (Join-Path `$Here 'Package-Thornswood.ps1') @pkgArgs")
Yes 'Ship seeds $pubLauncher before it asks whether to keep the feed''s launcher' ($iSeed -ge 0 -and $iKeep -gt $iSeed)
Yes 'Ship still keeps the feed''s launcher when nothing it is built from changed' ($iKeep -ge 0 -and $iKept -gt $iKeep)
Yes 'Ship puts the feed''s launcher in the root on main with -Package, not on a dry run, when it keeps it' ($iWhen -ge 0)
Yes '  through Install-FeedLauncher with Install-Launcher.ps1' ($iStep -gt $iWhen)
Yes '  and a reason stops the Ship' ($iDie -gt $iStep)
Yes '  after the keep decision' ($iWhen -gt $iKept)
Yes '  after the generated files and node checks, so nothing is installed for a release that stops there (#1692)' (
    $iGen -ge 0 -and $iNode -ge 0 -and $iWhen -gt $iGen -and $iWhen -gt $iNode)
Yes '  with the sign helpers loaded before it' ($iAssert -ge 0 -and $iAssert -lt $iWhen)
$iPlugins = $src.IndexOf("Head 'The in game plugins'")
Yes '  in the launcher build block''s place, after it' ($iBuild -ge 0 -and $iWhen -gt $iBuild)
Yes '  and before the in game plugins, as the built launcher is installed' ($iPlugins -gt $iDie)
Yes '  before Publish-Update' ($iPublish -gt $iDie)
Yes '  and before Package-Thornswood packs <root>\Launcher' ($iPackage -gt $iDie)
Yes 'Get-FeedLauncher checks the signature with Get-PublishSignRefusal' ($fns['Get-FeedLauncher'] -match 'Get-PublishSignRefusal -Path \$exe -ExpectedSigner \$expectedSigner')
Yes 'Install-FeedLauncher installs with -From the checked download' ($fns['Install-FeedLauncher'] -match '& \$installer -Root \$root -From \$scratch -NoPause')

# Install-Launcher.ps1 takes what Install-FeedLauncher hands it.
$it = $null; $ie = $null
$iast = [System.Management.Automation.Language.Parser]::ParseFile($InstallPath, [ref]$it, [ref]$ie)
$pnames = @()
if ($iast.ParamBlock) { $pnames = @($iast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) }
foreach ($n in 'Root', 'From', 'NoPause') { Yes "Install-Launcher.ps1 takes -$n" ($pnames -contains $n) }

# ---- drive it ---------------------------------------------------------------
# The stand-in reads the signer off the exe's first line: "signed by <who>".
function Get-PublishSignRefusal {
    param([string]$Path, [string]$ExpectedSigner)
    if (-not (Test-Path -LiteralPath $Path)) { return "missing file to check for a publish signature: $Path" }
    $first = @([IO.File]::ReadAllLines($Path))[0]
    if ($first -notmatch '^signed by (.+)$') { return ((Split-Path -Leaf $Path) + ' is not Authenticode Valid (status NotSigned). Nothing was published.') }
    if ($Matches[1] -ne $ExpectedSigner) { return ((Split-Path -Leaf $Path) + ' is signed by "' + $Matches[1] + '". Nothing was published.') }
    return ''
}
function Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-2661-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $who = 'The Name On The Certificate'
    $feedDir = Join-Path $work 'feed'
    New-Item -ItemType Directory -Force -Path $feedDir | Out-Null
    $feedExe = Join-Path $feedDir 'Thornswood.exe'
    [IO.File]::WriteAllText($feedExe, "signed by $who`nthe 1.2.5 main's feed offers`n")
    $theirs = Join-Path $feedDir 'Theirs.exe'
    [IO.File]::WriteAllText($theirs, "signed by Somebody Else`nnot ours`n")
    # Absolute by name: a cast takes /tmp/... as a relative URI off Windows (#2989).
    function Url([string]$p) { return ([Uri]::new($p, [UriKind]::Absolute)).AbsoluteUri }
    function Pub([string]$url, [string]$sha) { return [pscustomobject]@{ Version = '1.2.5'; Url = $url; Sha = $sha; Inputs = 'abc' } }
    $good = Pub (Url $feedExe) (Sha $feedExe)

    $log = Join-Path $work 'installer.log'
    # An installer that does what Install-Launcher.ps1 does to the exe.
    $inst = Join-Path $work 'install.ps1'
    [IO.File]::WriteAllText($inst, @"
param([string]`$Root, [string]`$From, [switch]`$NoPause)
Add-Content -LiteralPath '$log' -Value ('installed from ' + `$From)
`$d = Join-Path `$Root 'Launcher'
New-Item -ItemType Directory -Force -Path `$d | Out-Null
Copy-Item -LiteralPath (Join-Path `$From 'Thornswood.exe') -Destination (Join-Path `$d 'Thornswood.exe') -Force
exit 0
"@)
    $broken = Join-Path $work 'broken-install.ps1'
    [IO.File]::WriteAllText($broken, @"
param([string]`$Root, [string]`$From, [switch]`$NoPause)
Add-Content -LiteralPath '$log' -Value 'failed'
exit 1
"@)
    $idle = Join-Path $work 'idle-install.ps1'
    [IO.File]::WriteAllText($idle, @"
param([string]`$Root, [string]`$From, [switch]`$NoPause)
Add-Content -LiteralPath '$log' -Value 'did nothing'
exit 0
"@)
    function Ran { if (Test-Path -LiteralPath $log) { return @([IO.File]::ReadAllLines($log)) } return @() }
    function Fresh([string]$name) {
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
        $r = Join-Path $work $name
        Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path $r | Out-Null
        return $r
    }
    function Left([string]$dir) { return @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }

    # ---- Get-FeedLauncher ---------------------------------------------------
    $into = Join-Path $work 'dl'
    $why = Get-FeedLauncher $good $into $who
    Yes "the feed's launcher downloads and checks: '$why'" ($why -eq '')
    Yes '  and is in the folder with the feed''s sha256' ((Test-Path -LiteralPath (Join-Path $into 'Thornswood.exe')) -and (Sha (Join-Path $into 'Thornswood.exe')) -eq $good.Sha)
    Yes '  with no .part left' (-not (Test-Path -LiteralPath (Join-Path $into 'Thornswood.exe.part')))
    $why = Get-FeedLauncher (Pub (Url $feedExe) ($good.Sha.ToUpperInvariant())) $into $who
    Yes "  the feed's sha256 in capitals is the same sha256: '$why'" ($why -eq '')

    $why = Get-FeedLauncher (Pub (Url $feedExe) ('0' * 64)) $into $who
    Yes "a download that is not the feed's sha256 stops: '$why'" ($why -match 'does not match the feed''s launcherSha256' -and $why -match 'Nothing was published')
    Yes '  and leaves nothing in the folder' ((Left $into).Count -eq 0)

    $why = Get-FeedLauncher (Pub (Url $theirs) (Sha $theirs)) $into $who
    Yes "a download signed by somebody else stops: '$why'" ($why -match 'is not signed by ExpectedSigner' -and $why -match 'Somebody Else')
    Yes '  and leaves nothing in the folder' ((Left $into).Count -eq 0)

    $why = Get-FeedLauncher (Pub '' $good.Sha) $into $who
    Yes "a feed with no launcherUrl stops: '$why'" ($why -match 'names no whole launcher')
    $why = Get-FeedLauncher (Pub (Url $feedExe) 'aa') $into $who
    Yes "a feed whose launcherSha256 is not 64 hex digits stops: '$why'" ($why -match 'names no whole launcher')
    $why = Get-FeedLauncher $null $into $who
    Yes "no feed at all stops: '$why'" ($why -match 'names no whole launcher')
    $why = Get-FeedLauncher $good $into ''
    Yes "an empty ExpectedSigner stops: '$why'" ($why -match 'ExpectedSigner is empty')
    $why = Get-FeedLauncher (Pub (Url (Join-Path $feedDir 'gone.exe')) $good.Sha) $into $who
    Yes "a launcherUrl that does not answer stops: '$why'" ($why -match 'could not be downloaded' -and $why -match 'Run this same Ship again')
    Yes '  and leaves nothing in the folder' ((Left $into).Count -eq 0)

    # ---- Install-FeedLauncher -----------------------------------------------
    # 1. A new ship root: Game and config.json, no Launcher folder (local\release-main on 16 Oct).
    $root = Fresh 'release-main'
    $scratch = Join-Path $work 'scratch'
    $r = Install-FeedLauncher $good $root $scratch $who $inst
    $exe = Join-Path $root 'Launcher\Thornswood.exe'
    Yes "1. a root with no Launcher folder: '$($r.Why)'" ($r.Why -eq '' -and $r.Placed)
    Yes '1.   ends with the feed''s exe in <root>\Launcher' ((Test-Path -LiteralPath $exe) -and (Sha $exe) -eq $good.Sha)
    $ran = @(Ran)
    Yes '1.   put there by the installer, from the checked download' ($ran.Count -eq 1 -and $ran[0] -eq ('installed from ' + $scratch))

    # 2. A root holding another launcher (the last one a Ship built, or a dev one).
    $root = Fresh 'release-other'
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'Launcher') | Out-Null
    $exe = Join-Path $root 'Launcher\Thornswood.exe'
    [IO.File]::WriteAllText($exe, "signed by $who`nthe 1.2.4 a Ship built here before`n")
    $r = Install-FeedLauncher $good $root $scratch $who $inst
    Yes "2. a root holding another launcher: '$($r.Why)'" ($r.Why -eq '' -and $r.Placed)
    Yes '2.   ends with the feed''s exe in its place' ((Sha $exe) -eq $good.Sha)

    # 3. A root already holding the feed's launcher is left alone.
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    $stamp = (Get-Item -LiteralPath $exe).LastWriteTimeUtc
    $r = Install-FeedLauncher $good $root $scratch $who $inst
    Yes "3. a root already holding the feed's launcher: '$($r.Why)'" ($r.Why -eq '' -and -not $r.Placed)
    Yes '3.   nothing downloaded and the installer not run' ((Ran).Count -eq 0)
    Yes '3.   the exe untouched' ((Get-Item -LiteralPath $exe).LastWriteTimeUtc -eq $stamp -and (Sha $exe) -eq $good.Sha)

    # 4. A download that fails a check never reaches the root.
    $root = Fresh 'release-bad'
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'Launcher') | Out-Null
    $exe = Join-Path $root 'Launcher\Thornswood.exe'
    [IO.File]::WriteAllText($exe, "signed by $who`nthe one that was here`n")
    $was = Sha $exe
    foreach ($case in @(
            @{ Name = 'not the feed''s sha256'; Pub = (Pub (Url $feedExe) ('0' * 64)); Says = 'does not match' },
            @{ Name = 'signed by somebody else'; Pub = (Pub (Url $theirs) (Sha $theirs)); Says = 'not signed by ExpectedSigner' },
            @{ Name = 'a feed naming no whole launcher'; Pub = (Pub '' ''); Says = 'names no whole launcher' },
            @{ Name = 'a launcherUrl that does not answer'; Pub = (Pub (Url (Join-Path $feedDir 'gone.exe')) $good.Sha); Says = 'could not be downloaded' })) {
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
        $r = Install-FeedLauncher $case.Pub $root $scratch $who $inst
        Yes "4. $($case.Name) stops: '$($r.Why)'" ($r.Why -match $case.Says -and -not $r.Placed)
        Yes '4.   the installer not run and the root as it was' ((Ran).Count -eq 0 -and (Sha $exe) -eq $was)
    }

    # 5. An installer that fails, or that puts nothing in place, stops the Ship.
    $root = Fresh 'release-broken'
    $r = Install-FeedLauncher $good $root $scratch $who $broken
    Yes "5. an installer that exits 1 stops: '$($r.Why)'" ($r.Why -match 'stopped with exit code 1' -and -not $r.Placed)
    $root = Fresh 'release-idle'
    $r = Install-FeedLauncher $good $root $scratch $who $idle
    Yes "5. an installer that puts nothing in place stops: '$($r.Why)'" ($r.Why -match 'is not in place' -and $r.Why -match 'no exe' -and -not $r.Placed)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Done
