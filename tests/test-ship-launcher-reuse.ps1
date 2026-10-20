<#
  test-ship-launcher-reuse.ps1

  A Ship keeps the launcher already on the feed when nothing it is compiled
  from changed, so it is not rebuilt and signed again for every pack. Issue
  #921. Patrick, 28 Sep: "it should be signed only when a new installer goes
  up on the website so we aren't signing for every single update".

  Every signed launcher refuses an unsigned update, so the answer is not to
  skip signing a new launcher but to stop making a new one when nothing
  changed. The feed records launcherInputs, a sha256 of what the exe is built
  from; Ship compares it with the tree and, when they match, goes on as
  -ModsOnly: no version bump, no build, no signing call, the feed keeps its
  launcher url and sha256.

  This lifts Get-LauncherInputHash, Get-PublishedLauncher and
  Test-LauncherUnchanged out of the shipped Ship.ps1 by the parser and drives
  them against a scratch tree and a stand-in for the site feed, then checks the
  wiring in Ship.ps1 and Publish-Update.ps1 by text. If a name moves, this says
  so rather than quietly testing nothing. Read only apart from its temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath, [string]$PublishPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
if (-not $ShipPath) { $ShipPath = Join-Path $repo 'scripts/release/Ship.ps1' }
if (-not $PublishPath) { $PublishPath = Join-Path $repo 'scripts/release/Publish-Update.ps1' }

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
$src = [IO.File]::ReadAllText($ShipPath)
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$t, [ref]$e)
Yes 'Ship.ps1 parses' (@($e).Count -eq 0)
$FnAst = [System.Management.Automation.Language.FunctionDefinitionAst]
$fns = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is $FnAst }, $false)) { $fns[$f.Name] = $f.Extent.Text }
$want = 'Get-LauncherInputHash', 'Get-PublishedLauncher', 'Test-LauncherUnchanged', 'Test-KeepFeedLauncher'
foreach ($n in $want) { Yes "Ship.ps1 has $n" ($fns.ContainsKey($n)) }
foreach ($n in $want) { if (-not $fns.ContainsKey($n)) { Done } }
foreach ($n in $want) { Invoke-Expression $fns[$n] }
# The fingerprint reads each file as it ships (#2903).
. (Join-Path $repo 'scripts\release\ShippedBytes.ps1')

function Run-Git {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & git @args 2>&1 | Out-Null; return $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
}
function Put([string]$path, [string]$text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, $text)
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-launcher-reuse-' + [Guid]::NewGuid().ToString('N'))
try {
    # ---- Get-LauncherInputHash ------------------------------------------------
    $tree = Join-Path $work 'tree'
    Put (Join-Path $tree 'launcher/app/Updater.cs') 'public const string Version = "1.1.102";'
    Put (Join-Path $tree 'launcher/ui.xaml') '<Window/>'
    Put (Join-Path $tree 'launcher/art/scroll.png') 'png bytes'
    Put (Join-Path $tree 'launcher/app/ARCHITECTURE.md') 'notes'
    Put (Join-Path $tree 'records/client-build.json') '{"forkCommit":"abc"}'
    Put (Join-Path $tree 'records/ui-gone.json') '{"daedric":{},"unused":[]}'
    Put (Join-Path $tree 'scripts/release/Build-Launcher.ps1') '# build'

    $h0 = Get-LauncherInputHash $tree
    Yes "the fingerprint is a sha256: '$h0'" ($h0 -match '^[0-9a-f]{64}$')
    Yes '  and the same tree gives the same one' ((Get-LauncherInputHash $tree) -eq $h0)

    Put (Join-Path $tree 'launcher/app/ARCHITECTURE.md') 'notes, edited'
    Yes 'Markdown under launcher\ does not count' ((Get-LauncherInputHash $tree) -eq $h0)

    Put (Join-Path $tree 'launcher/app/Updater.cs') 'public const string Version = "1.1.103";'
    $h1 = Get-LauncherInputHash $tree
    Yes 'a change to the code counts' ($h1 -ne $h0)

    Put (Join-Path $tree 'launcher/art/scroll.png') 'other png bytes'
    $h2 = Get-LauncherInputHash $tree
    Yes 'a change to the art compiled in counts' ($h2 -ne $h1)

    Put (Join-Path $tree 'launcher/art/new.png') 'a new picture'
    $h3 = Get-LauncherInputHash $tree
    Yes 'a new file under launcher\ counts' ($h3 -ne $h2)

    Put (Join-Path $tree 'records/client-build.json') '{"forkCommit":"def"}'
    $h4 = Get-LauncherInputHash $tree
    Yes 'records\client-build.json counts, it is compiled in' ($h4 -ne $h3)

    Put (Join-Path $tree 'records/ui-gone.json') '{"daedric":{},"unused":["bg.png"]}'
    $hGone = Get-LauncherInputHash $tree
    Yes 'records\ui-gone.json counts, it is compiled in' ($hGone -ne $h4)

    Put (Join-Path $tree 'scripts/release/Build-Launcher.ps1') '# build, changed'
    $h5 = Get-LauncherInputHash $tree
    Yes 'Build-Launcher.ps1 counts' ($h5 -ne $hGone)

    Put (Join-Path $tree 'game/plugins/thing.js') 'a plugin'
    Put (Join-Path $tree 'site/server.js') 'the site'
    Yes 'plugins and the site do not count, they ride in packs' ((Get-LauncherInputHash $tree) -eq $h5)

    # ---- Test-LauncherUnchanged -----------------------------------------------
    $sha = ('a' * 64)
    $pub = [pscustomobject]@{ Version = '1.1.102'; Url = 'https://thornswood.net/feed/assets/x'; Sha = $sha; Inputs = $h5 }
    Yes 'same fingerprint, whole launcher on the feed: unchanged' (Test-LauncherUnchanged $pub $h5)
    # Test-KeepFeedLauncher $pub $inputs $current $dev $aligned $mainEquivalent $mainPub
    Yes 'main: identical inputs cannot retain a different version when source is aligned' (-not (Test-KeepFeedLauncher $pub $h5 '1.1.103' $false $true $false $null))
    Yes 'main: identical inputs and aligned version reuse the existing signed launcher' (Test-KeepFeedLauncher $pub $h5 '1.1.102' $false $true $false $null)
    Yes 'dev, main''s own launcher: kept only under main''s number' (-not (Test-KeepFeedLauncher $pub $h5 '1.1.103' $true $true $true $pub))
    Yes 'dev, main''s own launcher already on dev under main''s number: kept' (Test-KeepFeedLauncher $pub $h5 '1.1.102' $true $true $true $pub)
    $devPub = [pscustomobject]@{ Version = '1.1.102.4'; Url = 'u'; Sha = $sha; Inputs = $h5 }
    Yes 'a separate Dev branch retains normal fingerprint reuse of a dev number' (Test-KeepFeedLauncher $devPub $h5 '1.1.103' $true $false $false $null)
    # #2347: the dev feed's 1.2.3 of 12 Oct, built from other sources than
    # main's 1.2.3, is never kept: a dev launcher on 1.2.3 would not take it.
    $main123 = [pscustomobject]@{ Version = '1.2.3'; Url = 'u'; Sha = $sha; Inputs = ('a' * 64) }
    $dev123  = [pscustomobject]@{ Version = '1.2.3'; Url = 'u'; Sha = $sha; Inputs = $h5 }
    Yes 'dev: a launcher under main''s number from other sources is not kept (#2347)' (-not (Test-KeepFeedLauncher $dev123 $h5 '1.2.3' $true $true $false $main123))
    Yes '  nor from a branch' (-not (Test-KeepFeedLauncher $dev123 $h5 '1.2.3' $true $false $false $main123))
    Yes '  nor when main''s feed cannot be read to say it is main''s' (-not (Test-KeepFeedLauncher $dev123 $h5 '1.2.3' $true $false $false $null))
    $main122 = [pscustomobject]@{ Version = '1.2.2'; Url = 'u'; Sha = $sha; Inputs = ('a' * 64) }
    Yes '  but a three part number main has not published is kept' (Test-KeepFeedLauncher $dev123 $h5 '1.2.3' $true $false $false $main122)
    Yes 'a different fingerprint: changed' (-not (Test-LauncherUnchanged $pub $h4))
    Yes 'no feed: changed' (-not (Test-LauncherUnchanged $null $h5))
    Yes 'no fingerprint worked out: changed' (-not (Test-LauncherUnchanged $pub ''))
    $old = [pscustomobject]@{ Version = '1.1.101'; Url = 'u'; Sha = $sha; Inputs = '' }
    Yes 'a feed from before #921, no launcherInputs: changed, so it builds as before' (-not (Test-LauncherUnchanged $old $h5))
    $noUrl = [pscustomobject]@{ Version = '1.1.102'; Url = ''; Sha = $sha; Inputs = $h5 }
    Yes 'a feed with no launcher url: changed' (-not (Test-LauncherUnchanged $noUrl $h5))
    $badSha = [pscustomobject]@{ Version = '1.1.102'; Url = 'u'; Sha = 'nope'; Inputs = $h5 }
    Yes 'a feed with no real sha256: changed' (-not (Test-LauncherUnchanged $badSha $h5))

    # ---- Get-PublishedLauncher ------------------------------------------------
    $feed = [ordered]@{ launcherVersion = '1.1.102.3'; launcherUrl = 'https://thornswood.net/feed-dev/assets/y'; launcherSha256 = $sha; launcherInputs = $h5; packs = @() }
    $disk = Join-Path $work 'disk'
    Put (Join-Path $disk 'version.json') ($feed | ConvertTo-Json)
    $p = Get-PublishedLauncher $disk 'dev'
    Yes "reads the feed off disk when the folder is not a clone: '$($p.Version)'" ($p -and $p.Version -eq '1.1.102.3' -and $p.Inputs -eq $h5 -and $p.Sha -eq $sha)
    Yes 'no folder reads as no feed' ($null -eq (Get-PublishedLauncher (Join-Path $work 'nope') 'dev'))

    # The feed as the site serves it wins over the copy last received (#907):
    # Read-SiteFeed is what Ship reads first, and a stand-in for it here.
    $siteFeed = $feed
    $siteFeed['launcherVersion'] = '1.1.102.4'
    function Read-SiteFeed([string]$ch) { return ($script:siteDoc | ConvertFrom-Json) }
    $script:siteDoc = ($siteFeed | ConvertTo-Json)
    $stale = $feed; $stale['launcherVersion'] = '1.1.101.9'
    Put (Join-Path $disk 'version.json') ($stale | ConvertTo-Json)
    $p = Get-PublishedLauncher $disk 'dev'
    Yes "reads the site's feed, not the copy on disk: '$($p.Version)'" ($p -and $p.Version -eq '1.1.102.4')
    function Read-SiteFeed([string]$ch) { throw 'the site did not answer' }
    $p = Get-PublishedLauncher $disk 'dev'
    Yes "and the copy on disk when the site does not answer: '$($p.Version)'" ($p -and $p.Version -eq '1.1.101.9')
    Remove-Item Function:\Read-SiteFeed
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- the wiring ---------------------------------------------------------------
$iHash    = $src.IndexOf('$LauncherInputs = Get-LauncherInputHash $RepoDir')
$iTest    = $src.IndexOf('if (Test-KeepFeedLauncher $pubLauncher $LauncherInputs')
$iSet     = $src.IndexOf('$ModsOnly = $true', [Math]::Max(0, $iTest))
$iVersion = $src.IndexOf("if (`$ModsOnly) {`r`n    `$target = `$current")
if ($iVersion -lt 0) { $iVersion = $src.IndexOf("if (`$ModsOnly) {`n    `$target = `$current") }
$iBuild   = $src.IndexOf("Head 'Building the launcher'")
Yes 'Ship works out the fingerprint' ($iHash -ge 0)
Yes 'Ship compares it with the feed' ($iTest -gt $iHash)
Yes '  and goes on as -ModsOnly when it matches' ($iSet -gt $iTest)
Yes '  before the version is chosen, so no number is bumped' ($iVersion -gt $iSet)
Yes '  and before anything is built or signed' ($iBuild -gt $iSet)
Yes 'the check is skipped for -RebuildLauncher, -Version and -ModsOnly' ($src -match [regex]::Escape('if (-not $ModsOnly -and -not $RebuildLauncher -and -not $Version) {'))
Yes 'Ship reads the feed of its own channel' ($src -match [regex]::Escape("`$feedBranch = if (`$Dev) { 'dev' } else { 'main' }"))
Yes 'Ship has -RebuildLauncher' ($src -match '\[switch\]\$RebuildLauncher')
Yes 'Ship hands the fingerprint to Publish-Update with the launcher' ($src -match [regex]::Escape("if (-not `$ModsOnly) { `$pubArgs['Launcher'] = `$true; `$pubArgs['LauncherInputs'] = `$LauncherInputs }"))

$pub = [IO.File]::ReadAllText($PublishPath)
Yes 'Publish-Update takes -LauncherInputs' ($pub -match '\[string\]\$LauncherInputs')
$iBlock = $pub.IndexOf('if ($Launcher -and (Test-Path $exePath)) {')
$iRec   = $pub.IndexOf("Set-Prop `$doc 'launcherInputs' ([string]`$LauncherInputs)")
$iSha   = $pub.IndexOf("Set-Prop `$doc 'launcherSha256' `$nowSha")
Yes 'Publish-Update records launcherInputs beside launcherSha256' ($iRec -gt $iSha -and $iSha -gt $iBlock -and $iBlock -ge 0)

Done
