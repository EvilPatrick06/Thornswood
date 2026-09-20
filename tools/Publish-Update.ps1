<#
  Publish-Update.ps1

  Diffs the current build against the last published state, packs only what
  changed, uploads it as a release asset, and updates version.json so everyone's
  launcher picks it up.

  First time:   .\Publish-Update.ps1 -Baseline
  After that:   .\Publish-Update.ps1 -Notes "Swapped the map mod"
  Launcher:     .\Publish-Update.ps1 -Launcher -Notes "New launcher"
#>
[CmdletBinding()]
param(
    [string]$Root    = 'C:\Thornswood',
    # A release deleting more than this many files off everybody is treated as
    # a mistake until somebody says otherwise.
    [int]$MaxRemovals = 200,
    [switch]$AcceptRemovals,
    [string]$RepoDir,
    [string]$Repo,
    # Releases live in their own PUBLIC repository now, holding version.json
    # and the assets and nothing else. The source stays private. This is what
    # lets a shipped launcher read updates with no credential on it, which is
    # the only version of this that is not a credential handed to strangers.
    [string]$ReleaseDir,
    [string]$Id,
    [string]$Notes   = '',
    [switch]$Baseline,
    [switch]$Launcher,
    [switch]$NoUpload,
    [switch]$NoPush,
    [switch]$NoPause
    ,[switch]$MoveServer
    # main is the build everybody plays on. dev is the second launcher and
    # the dev server: its own release branch, its own baseline, its own pack
    # ids, and the dev ports in its version.json. Nothing about main moves.
    ,[ValidateSet('main', 'dev')][string]$Channel = 'main'
    # The version to record for the launcher being published, when it is not
    # the one written in app\Updater.cs. Ship uses it for dev builds, whose
    # number lives only in the exe.
    ,[string]$VersionOverride
)


# The launcher was SkyrimTogether.exe and is Thornswood.exe now. It replaces
# itself in place when it updates rather than being reinstalled, so an install
# made before the rename still carries the old name and both have to be looked
# for, newest first.
function Get-LauncherExe([string]$dir) {
    foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Join-Path $dir 'Thornswood.exe')
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RepoDir) { $RepoDir = Split-Path -Parent $Here }
$Dev = ($Channel -eq 'dev')

# ---- where the launcher is installed ----------------------------------------
#
# C:\Thornswood on most machines. A second developer may have put it on
# another drive, so when C: has no launcher every fixed drive is tried for
# <drive>:\Thornswood\Launcher\Thornswood.exe. The dev build is always the
# main root plus -DevBuild, on the same drive; that is where the main
# launcher's Settings page installs it (DevBuild.cs). -Root still wins.
function Find-Root {
    $first = 'C:\Thornswood'
    if (Test-Path -LiteralPath (Join-Path $first 'Launcher\Thornswood.exe')) { return $first }
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
        $cand = Join-Path $d.Root 'Thornswood'
        if (Test-Path -LiteralPath (Join-Path $cand 'Launcher\Thornswood.exe')) { return $cand }
    }
    return $first
}
if (-not $PSBoundParameters.ContainsKey('Root')) { $Root = Find-Root }
# The dev launcher lives beside the main one. Its config.json carries the dev
# ports and its Launcher folder holds the exe that gets uploaded.
if ($Dev -and -not $PSBoundParameters.ContainsKey('Root')) { $Root = $Root + '-DevBuild' }
if ($Dev -and -not (Test-Path (Join-Path $Root 'Launcher'))) {
    Die "No dev build at $Root. Install it from the main launcher's Settings page first."
}

# ------------------------------------------------------------ dev channel
# The dev build follows the dev branch of the releases repo. That branch is
# checked out as a git worktree beside the main clone, so both feeds sit on
# disk at once and a publish to one cannot touch the other. Made on first use,
# from main's tip, so the first dev version.json is exactly what main has.
function Ensure-DevReleases([string]$mainRel) {
    $devRel = Join-Path (Split-Path -Parent $mainRel) 'Thornswood-Releases-dev'
    if (Test-Path (Join-Path $devRel 'version.json')) { return $devRel }
    if (-not (Test-Path (Join-Path $mainRel '.git'))) {
        Die "The dev channel needs the releases clone at $mainRel first."
    }
    Write-Host "  making the dev release worktree at $devRel" -ForegroundColor DarkGray
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        & git -C $mainRel fetch origin 2>&1 | Out-Null
        $remoteDev = & git -C $mainRel ls-remote --heads origin dev 2>$null
        if ($remoteDev) {
            & git -C $mainRel worktree add $devRel dev 2>&1 | Out-Host
        } else {
            & git -C $mainRel worktree add -b dev $devRel origin/main 2>&1 | Out-Host
            & git -C $devRel push -u origin dev 2>&1 | Out-Host
        }
    } finally { $ErrorActionPreference = $old }
    if (-not (Test-Path (Join-Path $devRel 'version.json'))) { Die "Could not make the dev release worktree at $devRel." }
    return $devRel
}

if ($Dev -and -not $ReleaseDir) {
    $ReleaseDir = Ensure-DevReleases (Join-Path (Split-Path -Parent $RepoDir) 'Thornswood-Releases')
}

# Where version.json is published from. A clone of the releases repo sitting
# next to the source clone, by default. If it is not there yet, this falls back
# to the old arrangement so nothing breaks before it is set up, and says so.
if (-not $ReleaseDir) {
    $guess = Join-Path (Split-Path -Parent $RepoDir) 'Thornswood-Releases'
    if (Test-Path (Join-Path $guess '.git')) { $ReleaseDir = $guess }
    else { $ReleaseDir = $RepoDir }
}
if ($ReleaseDir -eq $RepoDir) {
    Write-Host ''
    Write-Host '  Publishing from the source repo, the old way.' -ForegroundColor Yellow
    Write-Host '  Every launcher that gets this needs a token to read it, and that token' -ForegroundColor Yellow
    Write-Host '  ships to everybody. Clone the public releases repo next to this one:' -ForegroundColor Yellow
    Write-Host ("    git clone https://github.com/EvilPatrick06/Thornswood-Releases " +
                (Join-Path (Split-Path -Parent $RepoDir) 'Thornswood-Releases')) -ForegroundColor DarkGray
    Write-Host ''
}
if (-not (Test-Path (Join-Path $ReleaseDir 'version.json'))) {
    if ($ReleaseDir -eq $RepoDir) { Die "No version.json in $RepoDir. Point -RepoDir at your clone." }
    # First publish into a fresh releases clone. Seed it from the source repo so
    # nothing about the current feed is lost.
    $seed = Join-Path $RepoDir 'version.json'
    if (Test-Path $seed) {
        Copy-Item $seed (Join-Path $ReleaseDir 'version.json') -Force
        Write-Host ''
        Write-Host "  version.json copied into $ReleaseDir for the first publish." -ForegroundColor Green
    } else {
        Die "No version.json in either $ReleaseDir or $RepoDir."
    }
}

$GameDir    = Join-Path $Root 'Game'
$ProfileDir = Join-Path $Root 'Profile'
$DistDir    = Join-Path $Root '_dist'

# This is the machine that ships, so its launcher must not put the kept copy
# of a plugin back over an edit that is about to be published. Keep reads this
# flag and adopts a newer game file instead of reverting it. See Keep.cs.
try {
    if (-not (Test-Path $ProfileDir)) { New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null }
    $devFlag = Join-Path $ProfileDir 'developer.flag'
    if (-not (Test-Path $devFlag)) { Set-Content -Path $devFlag -Value 'This machine publishes releases. Keep trusts newer files in the game folder here.' -Encoding ASCII }
} catch { }

# The baseline. What this machine last published, so the next run can pack the
# difference instead of everything.
#
# It used to live in _dist, which is inside the folder the uninstaller clears.
# One uninstall took it, and the next ship stopped dead with 'No baseline yet'
# on a machine that had published fine an hour earlier. It is a record about
# this computer rather than part of any install, so it lives where neither an
# uninstall nor a rebuild can reach it, and out of the repo so git never sees
# it.
$StateDir   = Join-Path $env:LOCALAPPDATA 'Thornswood'
$StateFile  = Join-Path $StateDir 'published.json'
if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }

# The dev channel keeps its own baseline. It starts as a copy of main's, so
# the first dev pack is exactly what changed since the last main release, and
# a main release copies its baseline back over this one (Ship does that), so
# dev never re-ships what main has already sent everyone.
if ($Dev) {
    $devState = Join-Path $StateDir 'published-dev.json'
    if (-not (Test-Path $devState) -and (Test-Path $StateFile)) {
        Copy-Item $StateFile $devState -Force
        Write-Host "  dev baseline started from main's" -ForegroundColor DarkGray
    }
    $StateFile = $devState
}

# Carried over from the old spot the first time this runs, so nobody has to
# re-baseline just because it moved.
$oldState = Join-Path $DistDir 'published.json'
if (-not (Test-Path $StateFile) -and (Test-Path $oldState)) {
    try {
        Move-Item $oldState $StateFile -Force
        Write-Host "  baseline moved to $StateFile, out of reach of the uninstaller" -ForegroundColor DarkGray
    } catch { }
}
$VersionFile = Join-Path $ReleaseDir 'version.json'

# ---- which Skyrim this release is made out of -----------------------------
#
# There used to be only one answer: the copy under Root that the installer
# built. A collection install makes no such copy, the game is the one Steam
# owns, and this stopped dead on "No build at C:\Thornswood\Game" while the
# launcher it had just built sat there working perfectly.
#
# Same test the launcher and the packager use, so all three agree about which
# Skyrim they are looking at.
function Get-SkyrimPath {
    $roots = @()
    foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\Wow6432Node\Valve\Steam')) {
        try { $sp = (Get-ItemProperty -Path $k -EA Stop).SteamPath; if ($sp) { $roots += ($sp -replace '/', '\') } } catch { }
    }
    foreach ($r in @($roots)) {
        $vdf = Join-Path $r 'config\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf) {
                if ($line -match '^\s*"path"\s+"(.+)"\s*$') { $roots += ($Matches[1] -replace '\\\\', '\') }
            }
        }
    }
    foreach ($r in $roots) {
        $g = Join-Path $r 'steamapps\common\Skyrim Special Edition'
        if (Test-Path -LiteralPath (Join-Path $g 'SkyrimSE.exe')) { return $g }
    }
    return ''
}

# What never leaves a machine in a pack: runtime folders, one machine's own
# files, other servers' files, sign in tokens, and the collection's files in a
# Game folder the launcher made. The rules live in Ship-Rules.ps1, shared with
# Package-Thornswood.ps1, so the installer follows exactly the same rules as
# the packs (it did not, and shipped a token file).
. (Join-Path $Here 'Ship-Rules.ps1')

$IsCollection = -not (Test-Path -LiteralPath $GameDir)
# A Game folder the launcher made out of Vortex's deployment (OwnGame.cs) is
# not the old installer's copy: most of it is the collection, linked in.
$ownCollection = if ($IsCollection) { $null } else { Get-ShipOwnGameCollection $ProfileDir }

# No record, no release.
#
# Get-ShipOwnGameCollection reads Profile\OwnGameiles.txt, which is the only
# thing that knows which files in a launcher made Game folder came from Vortex
# and which are ours. Missing, it returns nothing, and every one of the
# collection's thirty thousand files then looks like ours to publish.
#
# That is not a theory. On 17 Sep an uninstall test removed Profile from the
# shipping machine, the record went with it, and the next release got as far as
# "29,063 added or changed (11,368.1 MB)" before it was stopped by hand. It
# would have pushed the entire mod collection to everybody as an update and
# overwritten mods Vortex owns.
#
# The folder can say what it is: a Game folder exists and the launcher made it,
# so the record must exist too. When it does not, something has been deleted,
# and guessing is the one thing that must not happen.
if (-not $IsCollection -and $null -eq $ownCollection) {
    Die ("$ProfileDir\OwnGameiles.txt is missing, and that is the only record of " +
         "which files in $GameDir came from Vortex." + [Environment]::NewLine + [Environment]::NewLine +
         "Without it every file the collection provides looks like one of ours and the " +
         "release would carry the whole collection." + [Environment]::NewLine + [Environment]::NewLine +
         "Open the launcher, go to Settings, Maintenance, and press Bring it up to date " +
         "from Vortex. That writes the record again. Then run this.")
}
if ($IsCollection) {
    $steamGame = Get-SkyrimPath
    if (-not $steamGame) {
        Die "There is no build at $GameDir and no Skyrim in any Steam library either. Nothing to publish out of."
    }
    $GameDir = $steamGame
    Write-Host ''
    Write-Host "  collection install, publishing out of the Steam copy:" -ForegroundColor DarkGray
    Write-Host "  $GameDir" -ForegroundColor DarkGray
}

# What the collection provides. Those files come down from Nexus through
# Vortex, so pushing our own copies of them as an update would put thirty
# thousand files nobody needs into every release and overwrite mods with
# whatever version this machine happens to hold.
$vortexFiles = $null
if ($IsCollection) {
    $vm = Join-Path $GameDir 'Data\vortex.deployment.json'
    if (Test-Path -LiteralPath $vm) {
        try {
            $vdoc = ((Get-Content -LiteralPath $vm -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json
            $vortexFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($vf in @($vdoc.files)) {
                $r = [string]$vf.relPath
                if ($r) { [void]$vortexFiles.Add('Data\' + $r.TrimStart('\')) }
            }
            Write-Host ("  the collection provides {0:n0} file(s), which are not published" -f $vortexFiles.Count) -ForegroundColor DarkGray
        } catch {
            $vortexFiles = $null
            Write-Host '  the Vortex record could not be read, so this release would carry every mod file.' -ForegroundColor Red
            Die 'Refusing to publish the whole collection as an update. Deploy once in Vortex and run this again.'
        }
    } else {
        Write-Host "  no Vortex record at $vm" -ForegroundColor Red
        Die 'Refusing to publish the whole collection as an update. Deploy once in Vortex and run this again.'
    }
}
elseif ($null -ne $ownCollection) {
    $vortexFiles = $ownCollection
    Write-Host ''
    Write-Host "  Thornswood's own game folder, made from Vortex's deployment:" -ForegroundColor DarkGray
    Write-Host "  $GameDir" -ForegroundColor DarkGray
    Write-Host ("  the collection provides {0:n0} file(s), which are not published" -f $vortexFiles.Count) -ForegroundColor DarkGray
    if ($vortexFiles.Count -eq 0) {
        Die "The launcher's record of what came from Vortex (Profile\OwnGame\files.txt) lists nothing, so this release would carry every mod file. In the launcher, Settings, Maintenance, bring the folder up to date from Vortex, then publish again."
    }
}
function Test-FromCollection([string]$rel) {
    if ($null -eq $vortexFiles) { return $false }
    return $vortexFiles.Contains($rel)
}
$null = New-Item -ItemType Directory -Force -Path $DistDir

. (Join-Path $Here 'Close-Launcher.ps1')
# Every file below gets hashed and compared against what friends already have.
# A game still running underneath would publish a file that is mid-write.
$null = Stop-Game -Root $Root

Head 'Thornswood - publish'

# ------------------------------------------------------------ what is ours
$vanillaDataFiles = @('Skyrim.esm','Update.esm','Dawnguard.esm','HearthFires.esm','Dragonborn.esm','_ResourcePack.esl','_ResourcePack.bsa')
$vanillaDataPatterns = @('Skyrim - *.bsa','cc*.esm','cc*.esl','cc*.esp','cc*.bsa')
$vanillaDataDirs = @('Video','Strings')
$vanillaRootFiles = @('SkyrimSE.exe','SkyrimSELauncher.exe','steam_api64.dll','bink2w64.dll','Skyrim.ccc','installscript.vdf','Skyrim_Default.ini','High.ini','Low.ini','Medium.ini','Ultra.ini')
$vanillaRootDirs = @('_DowngraderBackups','Creations','Mods','Skyrim','src')

function Test-Vanilla([string]$rel) {
    $parts = $rel -split '\\'
    $top = $parts[0]
    if ($vanillaRootDirs -contains $top) { return $true }
    if ($parts.Count -eq 1) { return ($vanillaRootFiles -contains $top) }
    if ($top -ne 'Data') { return $false }
    if ($parts.Count -ge 3 -and ($vanillaDataDirs -contains $parts[1])) { return $true }
    if ($parts.Count -eq 2) {
        $leaf = $parts[1]
        if ($vanillaDataFiles -contains $leaf) { return $true }
        foreach ($p in $vanillaDataPatterns) { if ($leaf -like $p) { return $true } }
    }
    return $false
}

# The rules themselves are in Ship-Rules.ps1, dot-sourced above.
$runtimeDirs = $ShipRuntimeDirs
function Test-Runtime([string]$rel) { return (Test-ShipRuntime $rel) }
function Test-OtherServer([string]$rel) { return (Test-ShipOtherServer $rel) }
function Test-Machine([string]$rel) { return (Test-ShipMachine $rel) }

# ---- another server's menu -------------------------------------------------
#
# that server's and another launchers write their own Data\Platform\UI\index.html
# over ours. On a tester's machine Keep puts ours back before Play. On the
# machine that ships, Keep adopts newer game files (developer.flag), so theirs
# would go out to everyone as Thornswood's menu and nobody's chat would load.
# Ours is the one that loads thornswood-bridge.js, and it lives in the repo,
# so it is put back here, in the game and in the kept copy, before the scan.
$menuRel  = 'Data\Platform\UI\index.html'
$menuSrc  = Join-Path $RepoDir 'tools\ts-ui\index.html'
$menuLive = Join-Path $GameDir $menuRel
if ((Test-Path -LiteralPath $menuLive) -and (Test-Path -LiteralPath $menuSrc)) {
    if (-not ([IO.File]::ReadAllText($menuLive) -like '*thornswood-bridge.js*')) {
        Copy-Item -LiteralPath $menuSrc -Destination $menuLive -Force
        $menuKept = Join-Path $ProfileDir "Keep\$menuRel"
        if (Test-Path -LiteralPath (Split-Path -Parent $menuKept)) { Copy-Item -LiteralPath $menuSrc -Destination $menuKept -Force }
        Say "  $menuRel was another server's menu. Thornswood's put back from the repo." 'Yellow'
    }
}

Say '  Scanning the build...'
$prefix = $GameDir.TrimEnd('\') + '\'
$now = @{}
foreach ($f in (Get-ChildItem -LiteralPath $GameDir -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($prefix.Length)
    if (Test-FromCollection $rel) { continue }
    if (Test-Vanilla $rel) { continue }
    if (Test-Runtime $rel) { continue }
    if (Test-Machine $rel) { continue }
    # Dev only files ride in dev packs and never in a main one (Ship-Rules).
    if (-not $Dev -and (Test-ShipDevOnly $rel)) { continue }
    if ($f.Extension -in '.pdb', '.log') { continue }
    $now[$rel] = ('{0}:{1}' -f $f.Length, $f.LastWriteTimeUtc.Ticks)
}
Say ("  {0:n0} mod files" -f $now.Count) 'Green'
$others = @(Get-ChildItem -LiteralPath (Join-Path $GameDir 'Data\Platform') -Recurse -File -Force -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName.Substring($prefix.Length) } | Where-Object { Test-OtherServer $_ })
if ($others.Count) { Say ("  {0} of another server's file(s) in Data\Platform left alone: {1}" -f $others.Count, (($others | ForEach-Object { Split-Path $_ -Leaf }) -join ', ')) 'DarkGray' }

# The reference plugin list is part of what ships, so a load order change on its
# own has to be enough to make a pack. Hashed rather than timestamped, because
# rewriting the same list is not a change worth sending anyone.
foreach ($f in 'plugins.txt', 'loadorder.txt') {
    $src = Join-Path $ProfileDir "Default\$f"
    if (Test-Path $src) { $now[":profile:$f"] = (Get-FileHash $src -Algorithm SHA256).Hash }
}

# The launcher's own source. Nothing here ships as a file, it all ends up
# compiled into one exe, which is why a release that only changed the launcher
# used to produce an empty file list and a news post that said nothing. Hashed
# so the news can at least name which parts of it moved.
$srcDir = Join-Path $RepoDir 'tools'
if (Test-Path $srcDir) {
    foreach ($f in @(Get-ChildItem -LiteralPath $srcDir -Recurse -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Extension -in '.cs', '.xaml' })) {
        $rel = $f.FullName.Substring($srcDir.Length).TrimStart('\')
        $now[":src:$rel"] = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
    }
}

$prev = @{}
if (Test-Path $StateFile) {
    $obj = Get-Content $StateFile -Raw | ConvertFrom-Json
    foreach ($p in $obj.PSObject.Properties) { $prev[$p.Name] = $p.Value }
}

function Save-State {
    $o = [ordered]@{}
    foreach ($k in ($now.Keys | Sort-Object)) { $o[$k] = $now[$k] }
    $o | ConvertTo-Json -Depth 3 -Compress | Set-Content $StateFile -Encoding UTF8
}

if ($Baseline) {
    Save-State
    Head 'Done'
    Say "Baseline recorded: $($now.Count) files." 'Green'
    Say 'Future runs will pack only what changes from here.' 'Gray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0
}
if (-not $prev.Count) { Die "No baseline yet. Run this once with -Baseline first." }

# ------------------------------------------------------------ diff
Head 'Changes'
$changed = @(); $removed = @()
foreach ($k in $now.Keys) { if (-not $prev.ContainsKey($k) -or $prev[$k] -ne $now[$k]) { $changed += $k } }
foreach ($k in $prev.Keys) { if (-not $now.ContainsKey($k)) { $removed += $k } }

$profileChanged = @($changed | Where-Object { $_ -like ':profile:*' })
$srcChanged     = @($changed | Where-Object { $_ -like ':src:*' })
$changed        = @($changed | Where-Object { $_ -notlike ':profile:*' -and $_ -notlike ':src:*' })
$removed        = @($removed | Where-Object { $_ -notlike ':profile:*' -and $_ -notlike ':src:*' -and -not (Test-Machine $_) })

# ---- what a removal is allowed to be --------------------------------------
#
# A removal becomes a line in delete.txt, and every launcher that takes the
# pack deletes that file. That is right for a mod we dropped. It is a disaster
# for a file the collection provides, because the collection lives in the same
# folder now, so deleting it takes the mod off somebody's machine while Vortex
# still believes it deployed it.
#
# Not hypothetical. The first release published after the move to the Steam
# copy carried 28,833 removals: the previous state described the old Game
# folder, the new scan excluded everything Vortex provides, and every one of
# those files therefore looked deleted. It had to be pulled back out of
# version.json by hand before anybody opened a launcher.
$collectionRemovals = @($removed | Where-Object { Test-FromCollection $_ }).Count
if ($collectionRemovals) {
    $removed = @($removed | Where-Object { -not (Test-FromCollection $_) })
}

$changedBytes = 0
foreach ($c in $changed) { $changedBytes += [int64](($now[$c] -split ':')[0]) }
if ($profileChanged.Count) { Say '  the plugin list changed' 'Green' }
Say ("  {0:n0} added or changed ({1:n1} MB)" -f $changed.Count, ($changedBytes / 1MB)) $(if ($changed.Count) { 'Green' } else { 'DarkGray' })
Say ("  {0:n0} removed" -f $removed.Count) $(if ($removed.Count) { 'Yellow' } else { 'DarkGray' })
if ($collectionRemovals) {
    Say ("  {0:n0} more were the collection's files, left alone" -f $collectionRemovals) 'DarkGray'
}

# Whatever survives that, a release does not delete hundreds of files by
# accident. If it genuinely should, -AcceptRemovals says so out loud.
if ($removed.Count -gt $MaxRemovals -and -not $AcceptRemovals) {
    Write-Host ''
    Say ("This release would delete {0:n0} files from every machine that takes it." -f $removed.Count) 'Red'
    Say 'That is almost always a baseline problem rather than a real removal:' 'Red'
    Say "$StateFile describes the last build this machine published," 'Yellow'
    Say 'and if what counts as "the build" has moved, everything outside the new' 'Yellow'
    Say 'scope looks deleted at once.' 'Yellow'
    Write-Host ''
    Say 'The first few here are:' 'DarkGray'
    foreach ($r in @($removed | Sort-Object | Select-Object -First 12)) { Say "    $r" 'DarkGray' }
    Write-Host ''
    Say 'If every one of those really should go from everybody, run this again' 'Yellow'
    Say "with -AcceptRemovals. If not, delete $StateFile to start the baseline" 'Yellow'
    Say 'again: the next release is large and deletes nothing.' 'Yellow'
    Die 'Nothing was published.'
}



if (-not $changed.Count -and -not $removed.Count -and -not $profileChanged.Count -and -not $Launcher) {
    Head 'Nothing to do'
    Say 'The build matches what is already published.' 'Gray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0
}

# Running Ship twice in a row used to cut a second release that carried
# nothing: no mod files, no removals, no launcher source, just a higher
# version number that everyone still had to download. Exit code 2 tells Ship
# that happened so it can put the version number back.
if (-not $changed.Count -and -not $removed.Count -and -not $profileChanged.Count -and -not $srcChanged.Count) {
    Head 'Nothing to do'
    Say 'No mod files changed and no launcher source changed since the last release.' 'Gray'
    Say 'Publishing now would hand everyone a new launcher that does nothing.' 'Gray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 2
}

if (-not $Id) { $Id = Get-Date -Format 'yyyyMMdd-HHmm'; if ($Dev) { $Id += '-dev' } }

# ------------------------------------------------------------ pack
# GitHub refuses a release asset over 2 GiB, and a body mod release goes well
# past that. So the pack is split into chunks that each stay under the limit,
# and version.json lists each one separately. The launcher already applies
# whatever packs it has not seen, in order, so nothing on that side had to
# change: three packs simply look like three updates that arrive together.
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Measured uncompressed. Zipping game data usually lands around 60 percent,
# but textures and meshes are often already compressed and come out near 100,
# so the cap is set where even no compression at all stays under the limit.
$ChunkCap = 1800MB

$chunks = @()
if ($changed.Count -or $removed.Count -or $profileChanged.Count) {
    Head 'Building the pack'

    # Work out the split first, so the number of parts is known before any
    # zipping starts and the progress means something.
    $groups = @()
    $current = @()
    $currentBytes = [int64]0
    foreach ($rel in $changed) {
        $size = [int64](($now[$rel] -split ':')[0])
        if ($current.Count -and ($currentBytes + $size) -gt $ChunkCap) {
            $groups += ,$current
            $current = @()
            $currentBytes = 0
        }
        $current += $rel
        $currentBytes += $size
    }
    if ($current.Count -or -not $groups.Count) { $groups += ,$current }

    if ($groups.Count -gt 1) { Say "  splitting into $($groups.Count) parts, GitHub will not take one over 2 GB" 'Yellow' }

    for ($g = 0; $g -lt $groups.Count; $g++) {
        $part   = $g + 1
        $partId = if ($groups.Count -eq 1) { $Id } else { "$Id-$part" }
        $zipPath = Join-Path $DistDir "pack-$partId.zip"
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

        $zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
        try {
            $n = 0
            foreach ($rel in $groups[$g]) {
                $src = Join-Path $GameDir $rel
                if (-not (Test-Path -LiteralPath $src)) { continue }
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $src, ('game/' + ($rel -replace '\\', '/')), 'Optimal')
                $n++
                if ($n % 500 -eq 0) { Write-Host ("    part $part  {0:n0}/{1:n0}" -f $n, $groups[$g].Count) -ForegroundColor DarkGray }
            }

            # Removals go in the first part, so nothing is deleted after the
            # files that replace it have already arrived.
            if ($part -eq 1 -and $removed.Count) {
                $e = $zip.CreateEntry('delete.txt')
                $sw = New-Object IO.StreamWriter ($e.Open())
                foreach ($rel in $removed) { $sw.WriteLine(($rel -replace '\\', '/')) }
                $sw.Flush(); $sw.Dispose()
            }

            # The load order rides in the last part. Anyone who stops halfway
            # then has the new files sitting there but not yet switched on,
            # which is the harmless way round.
            #
            # Where the reference list lives depends on which kind of build this
            # is, and it has been both.
            #
            # With a Game folder of our own, %LOCALAPPDATA%\Skyrim Special
            # Edition is only this build's folder while the game is running, so
            # publishing with the game closed shipped the ordinary Skyrim's
            # plugin list as the reference and every launcher that took the
            # update overwrote its own correct list with it. Hence Profile\Default.
            #
            # A collection build has no Game folder. The game IS the Steam copy,
            # Vortex writes the plugin list into AppData, nothing swaps it about,
            # and Profile\Default is empty and always will be. Reading it there
            # stops a release dead with "that file is this build's reference
            # plugin list", which is how 1.1.1 failed to publish.
            #
            # Same test the launcher uses to decide the same thing. A folder
            # made from Vortex keeps the Vortex profile's list as it stood when
            # the folder was last brought up to date, which is the collection's
            # order. Get-ShipLoadOrderDir (Ship-Rules.ps1) picks between the
            # three, the same for the installer.
            if ($part -eq $groups.Count) {
                $ownGame = Join-Path $Root 'Game'
                $isCollection = -not (Test-Path -LiteralPath $ownGame)
                $refDir = Get-ShipLoadOrderDir $Root $ProfileDir
                if ($isCollection) {
                    Say "  reference load order from the Vortex profile: $refDir" 'DarkGray'
                }
                elseif ($refDir -eq (Join-Path $ProfileDir 'OwnGame')) {
                    Say "  reference load order from the Vortex profile, as of the folder's last update: $refDir" 'DarkGray'
                }
                foreach ($f in 'plugins.txt', 'loadorder.txt') {
                    $src = Join-Path $refDir $f
                    if (-not (Test-Path $src)) {
                        Die ("$src is missing. That file is this build's reference plugin list." + $(if ($isCollection) {
                             " This is a collection build, so it comes from the profile Vortex deployed. Open the game once through the launcher, or switch to the Thornswood profile in Vortex and deploy, then publish again." } else { "" }))
                    }
                    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $src, "profile/$f", 'Optimal')
                }
            }
        } finally { $zip.Dispose() }

        $bytes = (Get-Item $zipPath).Length
        $mb = [math]::Round($bytes / 1MB, 1)
        if ($bytes -ge 2147483648) {
            Die "pack-$partId.zip came to $mb MB, which GitHub will refuse. Lower `$ChunkCap in this script and run again."
        }
        Say "  pack-$partId.zip  -  $mb MB" 'Green'

        $chunks += [pscustomobject]@{
            Id   = $partId
            Path = $zipPath
            Sha  = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
            Url  = ''
        }
    }
}

# ------------------------------------------------------------ launcher exe
$exePath = Get-LauncherExe (Join-Path $Root 'Launcher')
$launcherVersion = ''
if ($Launcher) {
    if (-not (Test-Path $exePath)) { Die "No launcher at $exePath. Run Build-Launcher.ps1 first." }
    $updaterCs = Join-Path $Here 'app\Updater.cs'
    if (Test-Path $updaterCs) {
        $m = [regex]::Match((Get-Content $updaterCs -Raw), 'Version\s*=\s*"([^"]+)"')
        if ($m.Success) { $launcherVersion = $m.Groups[1].Value }
    }
    if ($VersionOverride) { $launcherVersion = $VersionOverride }
    if (-not $launcherVersion) { Die 'Could not read the version out of app\Updater.cs. Bump it before publishing a launcher.' }
    Say "  launcher $launcherVersion" 'Green'
}

# ------------------------------------------------------------ upload
$doc = Get-Content $VersionFile -Raw | ConvertFrom-Json

# ConvertFrom-Json gives back an object with only the keys the file had, and
# assigning to a key that was never there throws. Anything new has to be added.
function Set-Prop($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}

# And reading one that is not there throws outright under strict mode, which is
# how a missing ServerPassword quietly took the whole server block down once.
function Val($o, [string]$k) {
    if ($null -ne $o -and $o.PSObject.Properties.Name -contains $k) { return [string]$o.$k }
    return ''
}
if (-not $Repo -and ($doc.PSObject.Properties.Name -contains 'repo')) { $Repo = $doc.repo }

# Without this the asset lookup builds a broken API path, version.json ends up
# with an empty url, and everyone's launcher downloads nothing.
if (-not $Repo) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    # The releases clone, not the source clone. Getting this wrong publishes
    # assets somewhere no launcher is looking.
    $remote = (& git -C $ReleaseDir remote get-url origin 2>$null) | Select-Object -First 1
    $ErrorActionPreference = $old
    if ($remote -and $remote -match 'github\.com[:/](.+?)(?:\.git)?\s*$') { $Repo = $Matches[1] }
}
if (-not $Repo) { Die 'Could not work out which repo to publish to. Pass -Repo owner/name.' }
Say "  repo: $Repo" 'DarkGray'

$gh = Get-Command gh -EA SilentlyContinue
$exeUrl = ''

if (-not $NoUpload -and $gh) {
    Head 'Uploading'
    $assets = @()
    foreach ($c in $chunks) { $assets += $c.Path }
    if ($Launcher) { $assets += $exePath }

    $repoArg = @(); if ($Repo) { $repoArg = @('--repo', $Repo) }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'

    # Tried three times, because GitHub answers HTTP 500 to the release call
    # often enough to be a nuisance rather than an event: it happened on 1.0.133
    # and again on 1.0.135, and both times the identical command worked on the
    # next run. There is nothing to fix at this end. What there was to fix is
    # that one 500 cost a whole Ship, a burnt version number and a rebuild, so
    # it is retried here instead of by hand.
    #
    # Creating is what fails; uploading into a release that already exists is
    # the fallback, and it gets the same treatment.
    $tries = 3
    for ($try = 1; $try -le $tries; $try++) {
        & gh release create $Id @assets @repoArg --title "Update $Id" --notes $(if ($Notes) { $Notes } else { "Update $Id" }) 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { break }

        Say '  Release exists, uploading into it instead.' 'DarkGray'
        & gh release upload $Id @assets @repoArg --clobber 2>&1 | Out-Host
        if ($LASTEXITCODE -eq 0) { break }

        if ($try -lt $tries) {
            $wait = 5 * $try
            Say ('  GitHub did not take it. Trying again in {0}s ({1} of {2}).' -f $wait, ($try + 1), $tries) 'Yellow'
            Start-Sleep -Seconds $wait
        }
    }

    $json = & gh api ("repos/{0}/releases/tags/{1}" -f $Repo, $Id) 2>$null
    $ErrorActionPreference = $old

    # Strict mode throws on a missing property rather than giving back null,
    # and a failed upload leaves exactly that, which is how one bad upload
    # used to end in an unreadable error instead of a plain one.
    $rel = $null
    if ($json) { $rel = ($json -join '') | ConvertFrom-Json }
    $relAssets = @()
    if ($rel -and $rel.PSObject.Properties['assets'] -and $rel.assets) { $relAssets = @($rel.assets) }

    foreach ($a in $relAssets) {
        $u = "https://api.github.com/repos/$Repo/releases/assets/$($a.id)"
        if ($a.name -eq 'Thornswood.exe' -or $a.name -eq 'SkyrimTogether.exe') { $exeUrl = $u; continue }
        foreach ($c in $chunks) {
            if ($a.name -eq ('pack-' + $c.Id + '.zip')) { $c.Url = $u }
        }
    }

    $missing = @($chunks | Where-Object { -not $_.Url })
    if ($missing.Count) {
        Write-Host ''
        foreach ($m in $missing) { Say "  pack-$($m.Id).zip did not upload" 'Red' }
        Die 'Some parts never reached GitHub, so version.json has not been touched. Nobody has been sent a half release.'
    }
    if ($chunks.Count) { Say "  $($chunks.Count) pack asset$(if ($chunks.Count -eq 1) { '' } else { 's' }) ready" 'Green' }

    # The same check for the launcher, which did not have one.
    #
    # The pack guard above only looks at $chunks, and a release with nothing
    # to download has no chunks at all, so a run that changed no mod files and
    # only rebuilt the exe sailed straight past it. GitHub answered HTTP 500 to
    # the release call, $exeUrl came back empty, and version.json was written
    # and pushed saying launcher 1.0.133 with no address to get it from.
    #
    # Nobody was hurt, because the launcher checks:
    #
    #     bool newLauncher = Updater.IsNewer(v.launcherVersion, Updater.Version)
    #                        && !string.IsNullOrEmpty(v.launcherUrl);
    #
    # so an empty url offers nothing rather than downloading nothing. But it
    # also means anybody on an older launcher is quietly stuck on it until the
    # next release that uploads properly, with the feed insisting there is a
    # newer one. Better to stop here, while the only copy is on this machine
    # and git has not been touched.
    if ($Launcher -and -not $exeUrl) {
        Write-Host ''
        Say '  the launcher was built but never reached GitHub.' 'Red'
        Die 'version.json has not been touched, so the feed still points at the last launcher that actually uploaded. Usually the token or a GitHub hiccup: run Ship again.'
    }
    if ($exeUrl)  { Say "  launcher asset ready" 'Green' }
} elseif (-not $NoUpload) {
    Say '  The GitHub CLI is not installed, so nothing was uploaded.' 'Yellow'
    Say '  winget install GitHub.cli   then   gh auth login' 'Yellow'
}

# ------------------------------------------------------------ version.json
# Two people can ship from two machines. The feed is pulled before it is
# edited so this release is added on top of whatever the other machine just
# published, rather than on top of a copy from yesterday. A pull that fails
# (offline, or a conflict somebody has to look at) stops here, before the
# file is touched.
if (-not $NoPush -and (Test-Path (Join-Path $ReleaseDir '.git'))) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $pulled = & git -C $ReleaseDir pull --rebase --quiet 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host ($pulled | Out-String) -ForegroundColor Red
            Die "Could not pull the release feed in $ReleaseDir. Nothing was written. Sort the clone out and run Ship again."
        }
        $doc = Get-Content $VersionFile -Raw | ConvertFrom-Json
    } finally { $ErrorActionPreference = $old }
}
Head 'version.json'
if ($chunks.Count) {
    $packs = @()
    if ($doc.PSObject.Properties['packs'] -and $doc.packs) { $packs = @($doc.packs) }
    # In order. The launcher applies whatever it has not seen, in the order it
    # finds them, so part one has to be listed before part two.
    foreach ($c in $chunks) {
        $packs += [pscustomobject]@{
            id     = $c.Id
            url    = $c.Url
            sha256 = $c.Sha
            notes  = $Notes
        }
        Say "  pack $($c.Id) added" 'Green'
    }
    Set-Prop $doc 'packs' $packs
}
if ($Launcher -and (Test-Path $exePath)) {
    $wasVersion = Val $doc 'launcherVersion'
    $wasSha     = Val $doc 'launcherSha256'
    $nowSha     = (Get-FileHash $exePath -Algorithm SHA256).Hash.ToLower()

    Set-Prop $doc 'launcherVersion' $launcherVersion
    Set-Prop $doc 'launcherUrl' $exeUrl
    Set-Prop $doc 'launcherSha256' $nowSha
    Say "  launcher $launcherVersion recorded" 'Green'

    # The updater decides by version number alone. A changed exe under an
    # unchanged version reaches nobody who already has that version, and says
    # nothing while it does not.
    if ($wasSha -and $wasSha -ne $nowSha -and $wasVersion -eq $launcherVersion) {
        Write-Host ''
        Say "  WARNING: the launcher changed but is still version $launcherVersion." 'Red'
        Say '  Anyone already on that version will never be offered this build.' 'Red'
        Say '  Re-run without -NoBump, or with -Version, to get it to them.' 'Yellow'
        Say '  If only mod files changed, -ModsOnly skips the launcher entirely.' 'DarkGray'
        Write-Host ''
    }
}

# Whatever this machine's launcher is pointed at becomes what everyone else is
# pointed at. It is how the password reaches four other people without anyone
# being told what it is, and how a server move fixes itself.
$cfgPath = Join-Path $Root 'config.json'
if (Test-Path $cfgPath) {
    try {
        $raw = [IO.File]::ReadAllBytes($cfgPath)
        $skip = if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { 3 } else { 0 }
        $cfg = [Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip) | ConvertFrom-Json
        # Everyone's launcher takes the address out of version.json and writes
        # it into their own config, so whatever is in THIS machine's config.json
        # at publish time becomes the server for all five people. A stale local
        # config quietly moves the whole group onto a box that is not running
        # anything, and the symptom lands on them rather than here. So a change
        # has to be deliberate.
        $wasAddr = Val $doc 'serverAddress'
        $wasPort = Val $doc 'serverPort'
        $nowAddr = Val $cfg 'ServerAddress'
        $nowPort = Val $cfg 'ServerPort'

        if ($wasAddr -and $nowAddr -and ("$wasAddr`:$wasPort" -ne "$nowAddr`:$nowPort") -and -not $MoveServer -and -not $Dev) {
            Write-Host ''
            Say 'The server address in version.json is about to change:' 'Red'
            Say ("    was  {0}:{1}" -f $wasAddr, $wasPort) 'Red'
            Say ("    now  {0}:{1}" -f $nowAddr, $nowPort) 'Red'
            Write-Host ''
            Say 'That comes from the config.json on this machine, and it moves everybody.' 'Yellow'
            Say 'If the server really has moved, run Ship again with -MoveServer.' 'Yellow'
            Say 'If it has not, fix the address in the launcher first, or with:' 'Yellow'
            Say '    .\tools\Set-Server.ps1 -Address <ip> -Port <port>' 'Yellow'
            Write-Host ''
            [void](Read-Host 'Enter to exit')
            exit 1
        }

        # UpdateRepo and VoicePort ride along for the same reason the address
        # does: they are facts about the server, not choices, and they used to
        # be boxes on the Settings page that nobody should have been editing.
        #
        # UpdateRepo is the one that matters. A launcher too old to know the
        # repository was renamed cannot be told, because telling it means
        # reaching it through the repository it can no longer find. Publishing
        # the new name under the OLD one, before renaming, is what lets a stale
        # copy read it once and find its way home.
        # DiscordAppId, SiteUrl and PresenceImage feed the "Playing Thornswood"
        # card in Discord and its two buttons. Facts about the project, not
        # choices, so they travel the same way.
        foreach ($pair in @(@('ServerAddress', 'serverAddress'), @('ServerPort', 'serverPort'),
                            @('UpdateRepo', 'updateRepo'), @('VoicePort', 'voicePort'),
                            @('DiscordAppId', 'discordAppId'), @('SiteUrl', 'siteUrl'),
                            @('PresenceImage', 'presenceImage'))) {
            if ($cfg.PSObject.Properties.Name -contains $pair[0]) { Set-Prop $doc $pair[1] ([string]$cfg.($pair[0])) }
        }

        # VoiceUrl travels even when it is empty, which none of the above do.
        # Empty is a real instruction here: it tells every launcher to stop
        # using the proxy and go back to the raw port, and it is the only way
        # back once they have all been pointed at Caddy. Writing it always is
        # what makes that one release rather than one per machine.
        if ($cfg.PSObject.Properties.Name -contains 'VoiceUrl') {
            Set-Prop $doc 'voiceUrl' ([string]$cfg.VoiceUrl)
        }

        # How many the room holds. A number, not a string, because the launcher
        # reads it as one and a quoted "25" comes back as zero, which reads as
        # no limit at all. It rides along for the same reason the address does:
        # raising the cap should not need everybody to reinstall.
        if ($cfg.PSObject.Properties.Name -contains 'MaxOnline') {
            $mo = 0
            [void][int]::TryParse([string]$cfg.MaxOnline, [ref]$mo)
            if ($mo -gt 0) { Set-Prop $doc 'maxOnline' $mo }
        }

        # The server password does NOT ride along, and it used to.
        #
        # version.json is published into the PUBLIC releases repository, which
        # is the whole reason a shipped launcher can read it without carrying a
        # credential. Anything written into it is readable by anybody, and the
        # password was being written into it every single publish.
        #
        # Nothing in the launcher ever read it back. Since 1.0.197 the password
        # comes from the site, handed over only after Discord has said who you
        # are, which is the entire point of the check. What was left was a
        # secret published for no reader.
        #
        # Any copy already sitting in version.json is taken out here, so a
        # publish removes it from the public repo rather than leaving it there
        # forever. That part stays, because a stale copy may still be up there.
        #
        # What used to follow it does not. Until 18 September this also copied
        # config.json's ServerPassword into server-secret.txt on every publish.
        # That field is gone from the launcher now, and the character register
        # secret is 32 random bytes written into server-secret.txt directly and
        # rotated by hand. Leaving the copy in place meant any value that found
        # its way back into config.json would silently overwrite the real
        # secret on the next publish, and the register would start refusing
        # everybody with nothing on screen to say why.
        if ($doc.PSObject.Properties.Name -contains 'serverPassword') {
            $doc.PSObject.Properties.Remove('serverPassword')
            Say '  took the server password out of version.json' 'Yellow'
        }
        Say "  server $(Val $cfg 'ServerAddress'):$(Val $cfg 'ServerPort')" 'Green'
        Say "  updates from $(Val $cfg 'UpdateRepo'), voice on $(Val $cfg 'VoicePort')" 'Green'
    } catch {
        Say "  could not read config.json, left the server details alone: $($_.Exception.Message)" 'Yellow'
    }
}

# The launcher's News page reads this. Without it the page sits empty however
# many releases go out, because the notes were only ever going into the GitHub
# release body, which nobody playing the game ever sees.
$news = @()
if ($doc.PSObject.Properties['news'] -and $doc.news) { $news = @($doc.news) }

# A note can be a headline on its own, or a headline followed by lines. Any
# line starting with - or * becomes its own bullet on the News page, which is
# the only way a launcher change gets described at all: none of it ships as a
# file, so the diff below cannot see it and only the person who made the
# change can say what it now does.
#
#     .\tools\Ship.ps1 "Quieter publish output
#     - git progress no longer prints as a red error
#     - the Recheck button checks for updates too"
#
$noteLines = @($Notes -split "`r?`n")
$title   = $noteLines[0].Trim()
$bullets = @()
$bodyBits = @()
for ($i = 1; $i -lt $noteLines.Count; $i++) {
    $line = $noteLines[$i].Trim()
    if (-not $line) { continue }
    if ($line -match '^[-*\u2022]\s*(.+)$') { $bullets += $Matches[1].Trim() }
    else { $bodyBits += $line }
}
$body = ($bodyBits -join ' ').Trim()

# One long line with no breaks still splits on its first sentence, the way it
# always did, so old habits keep working.
if ($noteLines.Count -eq 1) {
    $split = [regex]::Match($Notes, '^(.{1,70}?)(?:\.\s+)(.+)$', 'Singleline')
    if ($split.Success) {
        $title = $split.Groups[1].Value.Trim()
        $body  = $split.Groups[2].Value.Trim()
    }
}

# The note is whatever Gavin typed. These lines are what actually moved,
# worked out from the diff, so nobody has to take the note's word for it and
# nobody has to ask what a release contained.
function Listed($names, [int]$cap) {
    if ($names.Count -le $cap) { return ($names -join ', ') }
    return (($names[0..($cap - 1)]) -join ', ') + (', and {0} more' -f ($names.Count - $cap))
}
function LeafNames($paths, [string]$pattern) {
    return @($paths | Where-Object { $_ -match $pattern } |
             ForEach-Object { Split-Path $_ -Leaf } | Sort-Object -Unique)
}

$details = @()

# What Gavin wrote comes first, because it is the only part that knows why.
foreach ($bpt in $bullets) { $details += $bpt }

if ($Launcher -and $launcherVersion) { $details += "Launcher $launcherVersion" }

$newMods  = @(LeafNames $changed '\\.(esp|esm|esl)$')
$goneMods = @(LeafNames $removed '\\.(esp|esm|esl)$')
$newDlls  = @(LeafNames $changed '[\\/]SKSE[\\/]Plugins[\\/][^\\/]+\\.dll$')

if ($newMods.Count)  { $details += 'Mods added or updated: ' + (Listed $newMods 8) }
if ($goneMods.Count) { $details += 'Mods removed: ' + (Listed $goneMods 8) }
if ($newDlls.Count)  { $details += 'Under the hood: ' + (Listed $newDlls 8) }

# The list of .cs files that moved used to go in here. It meant something to
# one person and nothing to anybody else, and this feed is on a public website
# and in a public Discord now. The version number above already says the
# launcher changed.

if ($changed.Count) {
    $details += ('{0:n0} file{1} to download, {2:n1} MB' -f $changed.Count, $(if ($changed.Count -eq 1) { '' } else { 's' }), ($changedBytes / 1MB))
}
elseif (-not $srcChanged.Count) { $details += 'Nothing to download, this one is bookkeeping' }
if ($profileChanged.Count) { $details += 'The load order moved, so start a new character or expect the old save to complain' }

# The full path list. Eighty lines of SKSE ini paths is the ugliest thing that
# could sit under a release note, and this feed is public now, so it is built
# for the console while shipping and kept out of the entry itself. Anybody who
# genuinely wants it has the GitHub release.
$Cap = 80
$log = @()
foreach ($c in @($changed | Sort-Object)) { $log += $c }
foreach ($r in @($removed | Sort-Object)) { $log += '- ' + $r }
foreach ($p in @($profileChanged | Sort-Object)) { $log += ($p -replace '^:profile:', '') + '  (load order)' }
foreach ($p in @($srcChanged | Sort-Object)) { $log += 'tools\' + ($p -replace '^:src:', '') + '  (launcher)' }
if ($log.Count -gt $Cap) {
    $rest = $log.Count - $Cap
    $log  = @($log[0..($Cap - 1)]) + ('... and {0:n0} more file{1}' -f $rest, $(if ($rest -eq 1) { '' } else { 's' }))
}

$entry = [pscustomobject]@{
    # Month first, with the time on it, the same shape the site shows under
    # its download button. Entries written before this carry a bare date and
    # the launcher converts those as it reads them.
    date    = (Get-Date).ToString('M-d-yyyy h:mm tt')
    title   = $title
    body    = $body
    details = @($details)
    channel = $(if ($Dev) { 'dev' } else { '' })
}
# Shipping twice in a row with the same note is a re-publish, not two pieces
# of news. Only the first one is worth reading.
$repeat = $false
if ($news.Count -gt 0) {
    $top = $news[0]
    if ((Val $top 'title') -eq $entry.title -and (Val $top 'body') -eq $entry.body) { $repeat = $true }
}

if ($repeat) {
    Say '  same note as last time, so no new news entry' 'DarkGray'
} else {
    # Newest first, and only the last forty. It is a news feed, not a changelog.
    #
    # Twenty until one evening of fixes filled it and started pushing real
    # releases off the bottom. Publish-Server writes here too now, so the
    # feed has two sources and needs the room.
    $news = @($entry) + $news
    if ($news.Count -gt 40) { $news = $news[0..39] }
    Set-Prop $doc 'news' $news
    Say '  news entry added' 'Green'
}

# ------------------------------------------------------- dev or main
# Which of these notes the dev build has and main does not.
#
# The dev feed is a copy of main's, so it carries main's whole news list
# with the dev notes sitting on top of it. In the News tab that read as one
# list with no seam, and the seam is the part worth having: it is the
# difference between the dev build and the build everybody plays, which is
# the list of what wants testing before the two are made the same.
#
# Worked out by asking main's feed what it has rather than by remembering
# what was marked last time, so it corrects itself. A note that was dev only
# and has since gone out on main loses its mark on the next dev release, and
# nobody edits any JSON by hand. It also fixes the notes already in the feed
# the first time this runs, which is the only way the ones published before
# today ever get marked.
if ($Dev) {
    $mainVer = ''
    $mainTitles = @{}
    $mainJson = Join-Path (Join-Path (Split-Path -Parent $RepoDir) 'Thornswood-Releases') 'version.json'
    if (Test-Path -LiteralPath $mainJson) {
        try {
            $mainDoc = Get-Content -LiteralPath $mainJson -Raw | ConvertFrom-Json
            $mainVer = Val $mainDoc 'launcherVersion'
            if ($mainDoc.PSObject.Properties['news'] -and $mainDoc.news) {
                foreach ($m in @($mainDoc.news)) {
                    $k = (Val $m 'title').Trim()
                    if ($k) { $mainTitles[$k] = $true }
                }
            }
        } catch {
            Say "  could not read main's feed, so the dev marks were left alone: $($_.Exception.Message)" 'Yellow'
            $mainTitles = $null
        }
    } else {
        Say '  no main feed beside this one, so the dev marks were left alone' 'Yellow'
        $mainTitles = $null
    }

    if ($null -ne $mainTitles) {
        $marked = 0
        foreach ($n in @($news)) {
            $k = (Val $n 'title').Trim()
            $want = if ($k -and $mainTitles.ContainsKey($k)) { '' } else { 'dev' }
            Set-Prop $n 'channel' $want
            if ($want -eq 'dev') { $marked++ }
        }
        Set-Prop $doc 'news' $news
        Say ("  {0} note{1} marked dev, the ones main has not had" -f $marked, $(if ($marked -eq 1) { '' } else { 's' })) 'DarkGray'
    }

    Set-Prop $doc 'mainVersion' $mainVer
    if ($mainVer) { Say "  main is on $mainVer, this one is on $launcherVersion" 'DarkGray' }
} else {
    # A main release is the build everybody plays, so nothing in its feed is
    # dev only and nothing in it needs to know what main is on. Cleared
    # rather than assumed, in case a note ever reaches here already marked.
    foreach ($n in @($news)) {
        if ($n.PSObject.Properties.Name -contains 'channel') { $n.channel = '' }
    }
    Set-Prop $doc 'mainVersion' ''
}

# Set-Content -Encoding UTF8 writes a byte order mark on Windows PowerShell,
# and a BOM is not JSON. The launcher's reader stops on it and reports an
# unexpected character, which takes out the update check for everyone at once,
# including their route to a fix. So this file is written without one.
[IO.File]::WriteAllText($VersionFile, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))

# A pack with no url is not a warning. It is a release that switches Play off
# for every person who takes it, because their launcher tries to download from
# an empty address, fails, and treats a pack it cannot apply as one the server
# is expecting. It locks out whoever would have to publish the fix as well.
# So this stops here, before the push, while the only copy is the one on this
# machine and git has not been touched.
$blank = @($chunks | Where-Object { -not $_.Url })
if ($blank.Count) {
    Write-Host ''
    Say ("{0} pack(s) uploaded no asset, so their url is empty:" -f $blank.Count) 'Red'
    foreach ($b in $blank) { Say ("    " + $b.Id) 'Red' }
    Write-Host ''
    Say 'version.json has been written but NOT pushed. Nobody has this yet.' 'Yellow'
    Say 'The upload is what failed, usually the token or the release. Fix that and run Ship again.' 'Yellow'
    Say 'If a bad one did go out, .\tools\Repair-Manifest.ps1 takes it back out and pushes.' 'Yellow'
    Write-Host ''
    [void](Read-Host 'Enter to exit')
    exit 1
}

# ------------------------------------------------------------ the server copy
# This used to write Profile\Default\loadorder.txt out to _dist\server and tell
# the shipper to upload it to the server's Data folder. Do not put that back.
#
# It was wrong in three ways at once. The file it wrote carries EVERY entry,
# 103 of them today, while Deploy-Gamemode.ps1 deliberately drops light plugins
# from the server's list and cascades that drop to anything mastering them, so
# the two disagree by construction and uploading one over the other breaks the
# server rather than fixing it. Nothing packed _dist\server into a release, so
# the file only ever sat on the shipping machine waiting to tempt somebody. And
# the mechanism it named, ModCheck comparing against Data/loadorder.txt, exists
# nowhere else in this repo: the server's list lives in the loadOrder array of
# server-settings.json, which Deploy-Gamemode.ps1 writes.
#
# What replaces it is a check rather than a file. Nothing here can fix a stale
# server list, because computing it means the light plugin cascade and that
# logic belongs in one place. So this says whether the list the server is
# configured with is older than the one just published, which is the whole
# question, and names the two commands that settle it.
if ($profileChanged.Count) {
    Head 'The server needs this too'

    # The same default Deploy-Gamemode.ps1 carries. Absent on a machine that
    # does not build the server, which is fine: the advice still stands.
    $serverDist = 'C:\Thornswood-Dev\skymp\build\dist\server'
    $serverSettings = Join-Path $serverDist 'server-settings.json'
    $profileList = Join-Path $ProfileDir 'Default\loadorder.txt'

    Say '  The plugin list moved, so the server is now configured for the old one.' 'Yellow'

    if (Test-Path -LiteralPath $serverSettings) {
        $settingsAt = (Get-Item -LiteralPath $serverSettings).LastWriteTimeUtc
        $profileAt = if (Test-Path -LiteralPath $profileList) {
            (Get-Item -LiteralPath $profileList).LastWriteTimeUtc
        } else { [DateTime]::MinValue }

        if ($profileAt -gt $settingsAt) {
            Say ("  STALE. The server's list was written {0:yyyy-MM-dd HH:mm} and the plugin list changed {1:yyyy-MM-dd HH:mm}." -f $settingsAt, $profileAt) 'Yellow'
        } else {
            Say ("  The server's list was written {0:yyyy-MM-dd HH:mm}, after the plugin list. It may already be right." -f $settingsAt) 'Gray'
        }

        # A plugin the server still expects that is no longer in the profile is
        # a definite fault in the dangerous direction, and it needs no cascade
        # logic to spot. The other direction cannot be judged from here,
        # because a plugin missing from the server's list may have been dropped
        # on purpose for being light.
        try {
            $cfg = Get-Content -LiteralPath $serverSettings -Raw | ConvertFrom-Json
            $have = @{}
            foreach ($line in (Get-Content -LiteralPath $profileList -EA SilentlyContinue)) {
                $n = $line.Trim()
                if ($n -and -not $n.StartsWith('#')) { $have[$n.TrimStart('*')] = $true }
            }
            $gone = @()
            foreach ($entry in @($cfg.loadOrder)) {
                $leaf = [IO.Path]::GetFileName(([string]$entry).Replace('/', '\'))
                if ($leaf -and -not $have.ContainsKey($leaf)) { $gone += $leaf }
            }
            if ($gone.Count) {
                Say "  The server is configured for $($gone.Count) plugin(s) that are no longer in the list:" 'Red'
                foreach ($g in $gone | Select-Object -First 8) { Say "    $g" 'Red' }
                if ($gone.Count -gt 8) { Say "    and $($gone.Count - 8) more" 'Red' }
            }
        } catch {
            Say "  Could not read the server's list to compare: $_" 'DarkGray'
        }
    } else {
        Say "  No server build on this machine to check against ($serverDist)." 'DarkGray'
    }

    Say '  Put it right with, in this order:' 'Yellow'
    Say '      .\tools\Deploy-Gamemode.ps1' 'Yellow'
    Say '      .\tools\Publish-Server.ps1 "the load order moved"' 'Yellow'
    Say '  Deploy-Gamemode recomputes the list AND the start point new characters' 'Yellow'
    Say '  spawn at, which is a raw form id that rots whenever the order moves.' 'Yellow'
}

# ------------------------------------------------------------ push
$pushFailed = $null
if (-not $NoPush) {
    Head 'Pushing'
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    Push-Location $ReleaseDir
    try {
        # git writes its progress to stderr, and Out-Host renders anything on
        # stderr as a red error record even when the push succeeded. Flattening
        # each line to a string first keeps the output honest about what it is.
        function Relay { process { Write-Host ('  ' + $_.ToString()) -ForegroundColor DarkGray } }

        # Git refuses to commit without a name and an email, and the clone this
        # publishes from is usually a fresh one that has neither. It used to say
        # "Please tell me who you are", carry on, and finish with "everyone's
        # launcher will offer this update" while version.json sat uncommitted.
        $who = (& git config user.email) 2>$null
        if (-not $who) { $who = (& git config --global user.email) 2>$null }
        if (-not $who) {
            Write-Host ''
            Say 'This clone has no git identity, so version.json cannot be committed.' 'Red'
            Say 'The release assets ARE uploaded. Only the feed that points at them is not.' 'Yellow'
            Write-Host ''
            Say '  git config --global user.name "EvilPatrick06"' 'Green'
            Say '  git config --global user.email "EvilPatrick06@users.noreply.github.com"' 'Green'
            Write-Host ''
            Say 'Then run Ship again, or just push this by hand:' 'Yellow'
            Say ("  cd {0}" -f $ReleaseDir) 'Green'
            Say '  git add version.json; git commit -m "Update ' + $Id + '"; git push' 'Green'
            $pushFailed = 'no git identity'
        }
        else {
            & git add version.json
            & git commit -m "Update $Id$(if ($Notes) { ": $Notes" })" 2>&1 | Relay
            $rcCommit = $LASTEXITCODE
            & git push -u origin HEAD 2>&1 | Relay
            $rcPush = $LASTEXITCODE
            # A commit that found nothing to do exits 1 and is fine. A push that
            # fails is never fine, because the feed is then behind the assets.
            if ($rcPush -ne 0) { $pushFailed = "git push exited with $rcPush" }
        }
    } finally { Pop-Location; $ErrorActionPreference = $old }
}

Save-State

Head 'Done'
if ($pushFailed) {
    Say "NOT SHIPPED. $pushFailed" 'Red'
    Say 'The assets are on GitHub but version.json is not, so no launcher will' 'Red'
    Say 'see this update. Fix the line above and push, then it is live.' 'Red'
}
else {
    Say "Everyone's launcher will offer update $Id on next start." 'Green'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
