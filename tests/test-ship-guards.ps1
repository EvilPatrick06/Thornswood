<#
  test-ship-guards.ps1

  The two Ship.ps1 guards that came out of 17 September, run for real.

  WHY THIS EXISTS. Two of that night's incidents were Ship's own, and nothing
  had ever run the code that answers them. Entry 197 on the To Do List asks
  for "a dry run leaves version.json and the baseline byte-identical by
  fingerprint".

  THE DRY RUN. -DryRun passes -NoUpload and -NoPush to the publisher, which
  stop a release leaving the machine and do not stop the publisher writing
  version.json and its baseline. So a dry run recorded the source as
  published, and the real Ship that followed found nothing changed and
  shipped nothing. Twice on 17 September, and the second time it looked
  exactly like a broken release. On 21 September the same fault turned up in
  the third file, Updater.cs: a dry run went 1.1.67 to 1.1.68 and left it
  there. Ship now keeps copies and puts all three back. Here the feed and the
  baseline are fingerprinted with SHA256 before and after, and the version is
  read back.

  THE PLUGINS. Ship never copied the in game plugins from the repo into the
  game folder, so on 17 September a dev build went out with day old plugins
  from a machine where the source had changed and nobody had run Go.ps1. Ship
  now compares every plugin in game\plugins with the copy in the game
  folder and stops the release on any difference. Here a day old copy, a
  missing one and an empty source folder each have to stop it.

  Both are lifted out of the shipped Ship.ps1 by the parser, the way
  test-dev-version.ps1 lifts its version block, so this drives the real code
  and not a copy of it. If a block moves, this says so rather than quietly
  testing nothing.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)

$ErrorActionPreference = 'Stop'
$RepoHere = $PSScriptRoot
if (-not $RepoHere) { $RepoHere = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$RepoHere = Split-Path -Parent $RepoHere
if (-not $ShipPath) { $ShipPath = Join-Path $RepoHere 'scripts\release\Ship.ps1' }

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

# ---- lift the blocks ------------------------------------------------------------
#
# By the parser rather than by counting braces, because Ship.ps1's comments
# quote error messages with braces in them.
$src = Get-Content -LiteralPath $ShipPath -Raw
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$tokens, [ref]$errors)
$ifs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] }, $true) |
         Sort-Object { $_.Extent.StartOffset })

# The first if on $condition that starts after $after and carries $mark: each
# block is looked for after the line that leads into it, so another if on the
# same condition elsewhere in the file is never taken for it.
function Find-If([string]$condition, [int]$after, [string]$mark) {
    if ($after -lt 0) { return '' }
    foreach ($n in $ifs) {
        if ($n.Extent.StartOffset -lt $after) { continue }
        if ($n.Clauses[0].Item1.Extent.Text -ne $condition) { continue }
        if (-not $n.Extent.Text.Contains($mark)) { continue }
        return $n.Extent.Text
    }
    return ''
}

$script:dryBefore = Find-If '$DryRun' $src.IndexOf('$dryKeep = @()') '$dryKeep +='
$script:dryAfter  = Find-If '$DryRun' $src.IndexOf("& (Join-Path `$Here 'Publish-Update.ps1') @pubArgs") 'foreach ($k in $dryKeep)'
$script:guard     = Find-If '$GameDir' 0 "Join-Path `$Here '..\..\game\plugins'"
$unbump = ''
$writeUpdater = ''   # Unbump writes Updater.cs through Write-UpdaterCs (#2035)
foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($fn.Name -eq 'Unbump') { $unbump = $fn.Extent.Text }
    if ($fn.Name -eq 'Write-UpdaterCs') { $writeUpdater = $fn.Extent.Text }
}

Yes 'the dry run keeps its copies before the publisher runs' ($script:dryBefore -ne '')
Yes 'and puts them back after it' ($script:dryAfter -ne '')
Yes 'Ship.ps1 has Unbump' ($unbump -ne '')
Yes 'and the Write-UpdaterCs it writes with' ($writeUpdater -ne '')
Yes 'the plugin check is in Ship.ps1' ($script:guard -ne '')
if (-not ($script:dryBefore -and $script:dryAfter -and $unbump -and $writeUpdater -and $script:guard)) { Done }

# What the blocks call. Say and Head only print; Die stops, as it does in Ship.
function Say($m, $c = 'Gray') { }
function Head($m) { }
function Die($m) { throw ('STOP. ' + $m) }
Invoke-Expression $writeUpdater
Invoke-Expression $unbump

function Hash([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return 'absent' }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Read-Version([string]$path) {
    $m = [regex]::Match([IO.File]::ReadAllText($path), 'Version\s*=\s*"([^"]+)"')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-ship-guards-' + [Guid]::NewGuid().ToString('N'))
$oldAppData = $env:LOCALAPPDATA
try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    # This machine's working copies of the feeds (Feed-Store.ps1, #907).
    $script:rel = Join-Path $work 'appdata\Thornswood\feed\main'
    $script:relDev = Join-Path $work 'appdata\Thornswood\feed\dev'
    $state = Join-Path $work 'appdata\Thornswood'
    New-Item -ItemType Directory -Path $script:rel, $script:relDev, $state -Force | Out-Null
    # Pending notes and the working copies of the feed and baseline are all under LOCALAPPDATA.
    $env:LOCALAPPDATA = Join-Path $work 'appdata'
    [IO.File]::WriteAllText((Join-Path $script:relDev 'version.json'), '{"launcherVersion":"1.1.67","packs":[]}')

    # Updater.cs as it stands after a -Version bump, which is when there is a
    # number to put back.
    $updaterCs = Join-Path $work 'Updater.cs'
    [IO.File]::WriteAllText($updaterCs, "        public const string Version = `"1.1.68`";`r`n")
    $current = '1.1.67'
    $target = '1.1.68'

    # What the publisher does under -NoUpload -NoPush: it writes version.json
    # in the working folder and records the release in its baseline.
    $publish = {
        param([string]$name)
        $rd = if ($name -eq 'published-dev.json') { $script:relDev } else { $script:rel }
        [IO.File]::WriteAllText((Join-Path $rd 'version.json'), '{"launcherVersion":"1.1.68","packs":[{"id":"20260917-2200"}]}')
        [IO.File]::WriteAllText((Join-Path $rd 'published.json'), '{"Data\\Platform\\Plugins\\thornswood-chat.js":"123:456"}')
        $script:during = @{ feed = (Hash (Join-Path $rd 'version.json')); base = (Hash (Join-Path $rd 'published.json')) }
    }

    function Invoke-DryRun([bool]$dev, [scriptblock]$publisher, [string]$baselineName) {
        $DryRun = $true
        $Dev = $dev
        $pubArgs = @{ Notes = 'a dry run' }
        $ReleaseDir = if ($dev) { $script:relDev } else { $script:rel }
        $dryKeep = @()
        Invoke-Expression $script:dryBefore
        & $publisher $baselineName
        Invoke-Expression $script:dryAfter
        return [pscustomobject]@{ Args = $pubArgs; Keep = @($dryKeep) }
    }

    # ---- a main dry run -----------------------------------------------------------
    #
    # Bytes chosen to be easy to disturb: a byte order mark, no newline at the
    # end, and a baseline written the way Save-State writes one.
    $feed = Join-Path $script:rel 'version.json'
    $base = Join-Path $script:rel 'published.json'
    [IO.File]::WriteAllText($feed, '{"launcherVersion":"1.1.67","packs":[]}', (New-Object Text.UTF8Encoding($true)))
    [IO.File]::WriteAllText($base, '{"Data\\Platform\\Plugins\\thornswood-chat.js":"100:200"}')
    $feedWas = Hash $feed
    $baseWas = Hash $base

    $r = Invoke-DryRun $false $publish 'published.json'
    Yes 'a dry run tells the publisher not to upload' ($r.Args.ContainsKey('NoUpload') -and $r.Args['NoUpload'])
    Yes '  and not to push' ($r.Args.ContainsKey('NoPush') -and $r.Args['NoPush'])
    Yes 'the publisher did change both files, or this proves nothing' ($script:during.feed -ne $feedWas -and $script:during.base -ne $baseWas)
    Yes 'after a dry run version.json is byte for byte what it was' ((Hash $feed) -eq $feedWas)
    Yes '  and so is the baseline' ((Hash $base) -eq $baseWas)
    Yes '  and Updater.cs is back on the version it had' ((Read-Version $updaterCs) -eq $current)
    Yes '  and the copies it kept are cleaned up' (@($r.Keep | Where-Object { $_.Copy -and (Test-Path -LiteralPath $_.Copy) }).Count -eq 0)

    # ---- a dev dry run on a machine with no dev baseline yet ---------------------
    #
    # A file that was not there before must not be there after, or the next
    # real dev Ship reads a baseline nobody published.
    $devBase = Join-Path $script:relDev 'published.json'
    if (Test-Path -LiteralPath $devBase) { Remove-Item -LiteralPath $devBase -Force }
    [IO.File]::WriteAllText($updaterCs, "        public const string Version = `"1.1.68`";`r`n")
    $r = Invoke-DryRun $true $publish 'published-dev.json'
    Yes 'the publisher did make a dev baseline during the run' ($script:during.base -ne 'absent')
    Yes 'a dev dry run leaves no dev baseline where there was none' (-not (Test-Path -LiteralPath $devBase))
    Yes '  puts version.json back byte for byte' ((Hash $feed) -eq $feedWas)
    Yes '  and does not touch the main baseline' ((Hash $base) -eq $baseWas)

    # ---- the plugins in the game folder are this source, or nothing ships ---------
    function Invoke-Guard([string]$here, [string]$game) {
        $Here = $here
        $GameDir = $game
        try { Invoke-Expression $script:guard; return 'went on' }
        catch { return [string]$_.Exception.Message }
    }
    # Ship.ps1 sits in scripts\release since phase 8 of issue #440.
    $repoTools = Join-Path (Join-Path $work 'scripts') 'release'
    $plugins = Join-Path $work 'game\plugins'
    $game = Join-Path $work 'Game'
    $live = Join-Path $game 'Data\Platform\Plugins'
    New-Item -ItemType Directory -Path $plugins, $live -Force | Out-Null
    foreach ($n in 'thornswood-chat.js', 'thornswood-voice.js') {
        [IO.File]::WriteAllText((Join-Path $plugins $n), "// $n as it is in the repo today`n")
        Copy-Item -LiteralPath (Join-Path $plugins $n) -Destination $live -Force
    }

    [IO.File]::WriteAllText($updaterCs, "        public const string Version = `"1.1.68`";`r`n")
    Yes 'plugins that match the source let the release go on' ((Invoke-Guard $repoTools $game) -eq 'went on')
    Yes '  and leave the version alone' ((Read-Version $updaterCs) -eq $target)

    # 17 September: the game folder held yesterday's copy.
    [IO.File]::WriteAllText((Join-Path $live 'thornswood-chat.js'), "// thornswood-chat.js as it was yesterday`n")
    $said = Invoke-Guard $repoTools $game
    Yes 'a day old plugin in the game folder stops the release' ($said -match 'not the ones in this repo')
    Yes '  and puts the version back' ((Read-Version $updaterCs) -eq $current)
    Copy-Item -LiteralPath (Join-Path $plugins 'thornswood-chat.js') -Destination $live -Force

    [IO.File]::WriteAllText($updaterCs, "        public const string Version = `"1.1.68`";`r`n")
    Remove-Item -LiteralPath (Join-Path $live 'thornswood-voice.js') -Force
    Yes 'a plugin that never arrived stops the release' ((Invoke-Guard $repoTools $game) -match 'not the ones in this repo')
    Yes '  and puts the version back' ((Read-Version $updaterCs) -eq $current)

    Get-ChildItem -LiteralPath $plugins -Filter *.js | Remove-Item -Force
    Yes 'a source folder with no plugins in it stops the release' ((Invoke-Guard $repoTools $game) -match 'has no \.js')
}
finally {
    $env:LOCALAPPDATA = $oldAppData
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Done
