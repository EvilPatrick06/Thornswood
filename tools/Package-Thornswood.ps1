<#
  Package-Thornswood.ps1
  Turns the built install at C:\Thornswood into the single file your friends run.

  Only your mod content goes in. Every Bethesda file is left out, because the
  installer rebuilds those from each friend's own Steam copy and their own
  Steam depots.
#>
[CmdletBinding()]
param(
    [string]$Root    = 'C:\Thornswood',
    [string]$OutDir  = 'C:\Thornswood\_dist',
    [ValidateRange(0, 9)][int]$Level = 1,
    [switch]$NoArchive,
    [switch]$Plain7z,
    [switch]$ReuseStage,
    [switch]$NoPause,
    # Straight onto the docs site when it is done, so nobody has to be sent a
    # file. -NoPublish builds without touching the site.
    [switch]$NoPublish,
    # Leave out every file the Vortex collection installs, because anybody
    # following the collection already has them and shipping them again is
    # both a 14 GB download and somebody else's mod in your installer.
    #
    # The path is Vortex's own record of what it put in the game folder, so
    # this is exact rather than a guess at which folders are "mods". A file is
    # only left out if Vortex is actually providing it, which means the
    # installer shrinks as the collection fills in and never drops something
    # nobody can get back.
    [string]$VortexManifest = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data\vortex.deployment.json',
    # Ship everything, the way it was before the collection existed.
    [switch]$NoVortex,
    # Build out of the Skyrim that Steam owns and Vortex deploys into, rather
    # than out of the launcher's own copy under Root. Normally there is nothing
    # to pass: if that copy is gone this finds the Steam one by itself. The
    # switch is for forcing it while both still exist.
    [switch]$Vortex,
    # One file instead of two. The payload is appended to the setup program and
    # a 24 byte trailer on the end says where it starts, which is the shape
    # Bootstrap.cs has always been able to read. This was dropped when the
    # payload was 14 GB, because Windows would not load an executable that big.
    # It is under a gigabyte now that the mods come from the collection.
    [switch]$OneFile
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
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$GameDir    = Join-Path $Root 'Game'
$ProfileDir = Join-Path $Root 'Profile'
$LaunchDir  = Join-Path $Root 'Launcher'
$stage      = Join-Path $OutDir 'stage'

<#
  Which Skyrim this installer is built out of.

  An install made before 1.1 keeps its own copy of the game under Root, and
  that copy is what gets packaged. Once it is retired the build lives in the
  Skyrim that Steam owns, with the collection deployed into it, and the
  packager has to follow it there. It did not, and the line below is a Die, so
  the first release after that folder was renamed would have stopped dead with
  "No build" and no installer.

  Decided by looking rather than by a switch, the same way the launcher decides
  which game it is pointed at, so the two cannot end up disagreeing about it.

  Nothing about the payload changes. Bethesda's own files were already left out
  by name, and anything the collection provides is left out by reading Vortex's
  own manifest, so pointing this at a 20 GB Steam install still produces an
  installer of the launcher and our own content and nothing else.
#>
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

if ($Vortex -or -not (Test-Path (Join-Path $GameDir 'SkyrimSE.exe'))) {
    $steamGame = Get-SkyrimPath
    if ($steamGame) {
        $GameDir = $steamGame
        Write-Host ''
        Write-Host "  building out of the Steam copy: $GameDir" -ForegroundColor Cyan
    }
}

if (-not (Test-Path (Join-Path $GameDir 'SkyrimSE.exe'))) {
    Die "No build at $GameDir, and no Steam copy of Skyrim either. Run Build-Thornswood.ps1, or install the collection in Vortex."
}

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Close-Launcher.ps1')

Head 'Packaging'

# A live game rewrites files under Game and Profile while this is listing and
# hashing them, which is how a package ends up half one version.
$null = Stop-Game -Root $Root

# ---- what never ships: Bethesda's own files ------------------------------
$vanillaDataFiles = @(
    'Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm',
    '_ResourcePack.esl', '_ResourcePack.bsa'
)
$vanillaDataPatterns = @('Skyrim - *.bsa', 'cc*.esm', 'cc*.esl', 'cc*.esp', 'cc*.bsa')
$vanillaDataDirs     = @('Video', 'Strings')

# ---- what never ships: other people's frameworks and modding tools --------
#
# Vortex's manifest answers "did Vortex put this here", which is not the same
# question as "does Thornswood need this". These folders answered no to the
# first and were shipped to everybody as though they were ours.
#
# NirnLabUIPlatform is another roleplay server's user interface framework and
# on its own it is 356 MB. Nemesis, FNIS, BodySlide and xEdit are tools that
# belong on the machine of somebody who builds mods, not in a folder handed to
# somebody who plays. Source is Papyrus script sources, which the game never
# reads. The rest is documentation, installer leftovers and a shader cache
# that rebuilds itself on first launch.
#
# All of them stay where they are on this machine. This only decides what goes
# into the installer.
$foreignDataDirs = @(
    'NirnLabUIPlatform',
    'Nemesis_Engine', 'FNIS Behavior SE 7.6', 'CalienteTools', 'tools',
    'Source', 'ModderResource', 'FOMod',
    'Docs', 'Docs and Screenshots', 'readmes',
    'ShaderCache'
)

$vanillaRootFiles = @(
    'SkyrimSE.exe', 'SkyrimSELauncher.exe', 'steam_api64.dll', 'bink2w64.dll',
    'Skyrim.ccc', 'installscript.vdf', 'Skyrim_Default.ini',
    'High.ini', 'Low.ini', 'Medium.ini', 'Ultra.ini',

    # Only ever seen when this is building out of the Steam copy rather than
    # out of a game folder we built ourselves.
    #
    # The script extender is not ours to hand out and it is in the collection
    # now, so shipping it again would be redistributing somebody's mod and
    # doing it twice. VERSION and steam_appid.txt belong to Steam and the
    # downgrader. imgui.ini and the d3dx9 log are written at runtime by
    # whatever was last run against this install.
    'skse64_loader.exe', 'skse64_1_6_1170.dll',
    'skse64_readme.txt', 'skse64_whatsnew.txt',
    'VERSION', 'steam_appid.txt', 'imgui.ini', 'd3dx9_42.log'
)
$vanillaRootDirs = @(
    '_DowngraderBackups', 'Creations', 'Mods', 'Skyrim', 'src',

    # Bethesda's launcher keeps its own folder, and DaedricData is another
    # roleplay server's. Neither is ours and neither goes in an installer.
    'BStarData', 'DaedricData'
)

function Test-Vanilla([string]$rel) {
    $parts = $rel -split '\\'
    $top   = $parts[0]
    if ($vanillaRootDirs -contains $top) { return $true }
    if ($parts.Count -eq 1) { return ($vanillaRootFiles -contains $top) }
    if ($top -ne 'Data') { return $false }
    if ($parts.Count -ge 3 -and ($vanillaDataDirs -contains $parts[1])) { return $true }
    if ($parts.Count -ge 2 -and ($foreignDataDirs -contains $parts[1])) { return $true }
    if ($parts.Count -eq 2) {
        $leaf = $parts[1]
        if ($vanillaDataFiles -contains $leaf) { return $true }
        foreach ($p in $vanillaDataPatterns) { if ($leaf -like $p) { return $true } }
    }
    return $false
}

# ---- stage ----------------------------------------------------------------
# The multiplayer client's menu is a Chromium window, and it keeps a browser
# profile beside itself: caches, cookie databases, shader blobs, its own logs.
# All of it is per machine, all of it is rewritten on every launch, and it is
# locked while the client is running. Publishing it churned hundreds of files
# per release, sent one player's browser state to everyone else, and eventually
# failed outright on a file the game still had open.
# The same rules as the packs, from the same file, so the installer can never
# carry what a pack would not: runtime folders, one machine's own files,
# other servers' files, and the SkyMP client's saved sign in token, which the
# installer built on 16 Sep did carry.
. (Join-Path $Here 'Ship-Rules.ps1')
$runtimeDirs = $ShipRuntimeDirs
function Test-Runtime([string]$rel) { return (Test-ShipRuntime $rel) }

# ---- what ships separately: the optional packs ----------------------------
# Everything listed in optional-packs.txt is left out here and published as its
# own download instead. Publish-Pack.ps1 reads the same file and builds those
# zips from it, so the installer and the packs can never disagree about which
# half of the build a file belongs to.
$optionalPrefixes = @()
$optionalFile = Join-Path $Here 'optional-packs.txt'
if (Test-Path -LiteralPath $optionalFile) {
    foreach ($line in (Get-Content -LiteralPath $optionalFile)) {
        $t = $line.Trim()
        if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
        $parts = $t -split '\|'
        if ($parts.Count -lt 3) {
            Say "  optional-packs.txt line ignored, needs id | name | path:  $t" 'Yellow'
            continue
        }
        # These three lines lost their backslashes at some point. EndsWith('')
        # is true for every string, so the trailing separator was never added
        # and 'Data\textures' also matched 'Data\texturesOld\'. Publish-Pack
        # trims a leading backslash and this did not, so the two could disagree
        # about which half of the build a file belongs to, which is the one
        # thing optional-packs.txt says must never happen.
        $prefix = $parts[2].Trim().TrimStart('\')
        if ($prefix.Length -eq 0) { continue }
        if (-not $prefix.EndsWith('\')) { $prefix += '\' }
        $optionalPrefixes += [pscustomobject]@{ Id = $parts[0].Trim(); Prefix = $prefix }
    }
}
function Test-Optional([string]$rel) {
    foreach ($o in $optionalPrefixes) {
        if ($rel.StartsWith($o.Prefix, 'OrdinalIgnoreCase')) { return $true }
    }
    return $false
}
if ($optionalPrefixes.Count) {
    Say ("  {0} optional path(s) will be left out and published separately" -f $optionalPrefixes.Count) 'Green'
}

# ---- what the collection provides: also left out --------------------------
# Vortex writes a record of every file it put in the game folder. That record,
# not a guess at which folders count as "mods", is what decides this. A file is
# left out only when Vortex is actually providing it, so the installer shrinks
# as the collection fills in and can never drop a file nobody can get back.
$vortexFiles = $null
# Built out of Thornswood's own game folder (Root\Game made by the launcher,
# OwnGame.cs): the Vortex record in the Steam copy says what Vortex has
# deployed there now, which may be another server's profile. The launcher's
# own record says what in this folder is the collection.
$ownCollection = $null
if ([string]::Equals($GameDir.TrimEnd('\'), (Join-Path $Root 'Game').TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
    $ownCollection = Get-ShipOwnGameCollection $ProfileDir
}
if ($null -ne $ownCollection) {
    if ($ownCollection.Count -eq 0) {
        Die "The launcher's record of what came from Vortex (Profile\OwnGame\files.txt) lists nothing, so this installer would carry every mod file. In the launcher, Settings, Maintenance, bring the folder up to date from Vortex, then package again."
    }
    $vortexFiles = $ownCollection
    Say ("  built from Thornswood's own game folder; the collection provides {0:n0} file(s), which are left out" -f $vortexFiles.Count) 'Green'
}
elseif (-not $NoVortex) {
    if (Test-Path -LiteralPath $VortexManifest) {
        try {
            $raw = (Get-Content -LiteralPath $VortexManifest -Raw) -replace '^\uFEFF', ''
            $vdoc = $raw | ConvertFrom-Json
            $vortexFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($vf in @($vdoc.files)) {
                $r = [string]$vf.relPath
                if (-not $r) { continue }
                # Vortex records paths relative to the game's Data folder. The
                # installer walks one level higher, so they need the prefix.
                [void]$vortexFiles.Add('Data\' + $r.TrimStart('\'))
            }
            Say ("  the collection provides {0:n0} file(s), which are left out" -f $vortexFiles.Count) 'Green'
        }
        catch {
            Say '  the Vortex record is there but could not be read, so nothing is left out for it:' 'Yellow'
            Say ('    ' + $_.Exception.Message) 'Yellow'
            $vortexFiles = $null
        }
    }
    else {
        Say '  no Vortex record found, so this installer carries every mod file.' 'Yellow'
        Say "  looked for: $VortexManifest" 'DarkGray'
        Say '  Deploy once in Vortex and it appears.' 'DarkGray'
    }
}

function Test-FromCollection([string]$rel) {
    if ($null -eq $vortexFiles) { return $false }
    return $vortexFiles.Contains($rel)
}

Say '  Listing the build...'
$all = @(Get-ChildItem -LiteralPath $GameDir -Recurse -File -Force)
$prefix = $GameDir.TrimEnd('\') + '\'

$ship = @(); $skipBytes = 0; $shipBytes = 0; $optionalBytes = 0; $optionalCount = 0; $machineCount = 0
$collectionBytes = 0; $collectionCount = 0
foreach ($f in $all) {
    $rel = $f.FullName.Substring($prefix.Length)
    if (Test-Vanilla $rel) { $skipBytes += $f.Length; continue }
    if (Test-Runtime $rel) { $skipBytes += $f.Length; continue }
    if (Test-ShipMachine $rel) { $skipBytes += $f.Length; $machineCount++; continue }
    if (Test-Optional $rel) { $optionalBytes += $f.Length; $optionalCount++; continue }
    if (Test-FromCollection $rel) { $collectionBytes += $f.Length; $collectionCount++; continue }
    if ($f.Extension -in '.pdb', '.log') { $skipBytes += $f.Length; continue }
    $ship += [pscustomobject]@{ Rel = $rel; Full = $f.FullName; Len = $f.Length; Time = $f.LastWriteTimeUtc }
    $shipBytes += $f.Length
}
Say ("  {0:n0} files kept ({1:n1} GB), {2:n0} left out ({3:n1} GB of Bethesda files and debug symbols)" -f `
    $ship.Count, ($shipBytes / 1GB), ($all.Count - $ship.Count), ($skipBytes / 1GB)) 'Green'
if ($machineCount) { Say ("  {0:n0} of this machine's own files, other servers' files and sign in tokens left out" -f $machineCount) 'DarkGray' }
if ($collectionCount) {
    Say ("  {0:n0} of the left out ({1:n1} GB) are files the collection provides." -f `
        $collectionCount, ($collectionBytes / 1GB)) 'Green'
    Write-Host ''
    Say '  THIS INSTALLER NOW NEEDS THE COLLECTION.' 'Yellow'
    Say '  On its own it is a launcher and your own content. Somebody who runs it' 'Yellow'
    Say '  without following the collection has no mods and cannot connect, and the' 'Yellow'
    Say '  error they see is a load order mismatch, which reads as a broken launcher.' 'Yellow'
    Say '  The launcher has to send them to the collection before this goes on the site.' 'Yellow'
    Write-Host ''
}
if ($optionalCount) {
    Say ("  {0:n0} more ({1:n1} GB) are in optional packs and published separately." -f `
        $optionalCount, ($optionalBytes / 1GB)) 'DarkGray'
}
if ($optionalCount) {
    Say ("  {0:n0} more ({1:n1} GB) belong to optional packs and are published separately." -f `
        $optionalCount, ($optionalBytes / 1GB)) 'Green'
    Say '  Run .\Publish-Pack.ps1 after this, or nobody can get them.' 'Yellow'
}

$payload = Join-Path $stage 'payload'
$reuse = $ReuseStage -and (Test-Path $payload)
if (-not $reuse -and (Test-Path $stage)) { Remove-Item $stage -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $stage, $payload, (Join-Path $stage 'profile')

if ($reuse) {
    # -ReuseStage used to take the old folder as it stood, which quietly shipped
    # yesterday's mod list the moment anything changed. It syncs now instead:
    # same speed when nothing moved, correct when something did.
    Say '  Checking the staged copy against the build...' 'Yellow'
    $have = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $payload -Recurse -File -Force)) {
        $have[$f.FullName.Substring($payload.TrimEnd('\').Length + 1)] = $f
    }

    $new = 0; $changed = 0; $gone = 0
    foreach ($f in $ship) {
        $old = $have[$f.Rel]
        if ($old) {
            $have.Remove($f.Rel)
            # A second of slack, because copying does not preserve ticks exactly.
            if ($old.Length -eq $f.Len -and [math]::Abs(($old.LastWriteTimeUtc - $f.Time).TotalSeconds) -lt 2) { continue }
            $changed++
        } else { $new++ }

        $dest = Join-Path $payload $f.Rel
        $dir  = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
        Copy-Item -LiteralPath $f.Full -Destination $dest -Force
    }

    # Whatever is left in the table is no longer part of the build.
    foreach ($leftover in $have.Values) { Remove-Item -LiteralPath $leftover.FullName -Force -EA SilentlyContinue; $gone++ }

    if ($new -or $changed -or $gone) {
        Say ("  {0:n0} new, {1:n0} changed, {2:n0} removed" -f $new, $changed, $gone) 'Green'
    } else {
        Say '  nothing has changed since the last package' 'Green'
    }
} else {
    Say '  Copying...'
    $n = 0
    foreach ($f in $ship) {
        $dest = Join-Path $payload $f.Rel
        $dir  = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
        Copy-Item -LiteralPath $f.Full -Destination $dest -Force
        $n++
        if ($n % 2000 -eq 0) { Write-Host ("    {0:n0}/{1:n0}" -f $n, $ship.Count) -ForegroundColor DarkGray }
    }
}

$payloadDir = $payload
$shipCount = $ship.Count

# Deep mod paths plus a long staging prefix push past the old Windows path
# limit, which is what "System ERROR: The parameter is incorrect" means here.
$longest = 0
foreach ($f in (Get-ChildItem -LiteralPath $payloadDir -Recurse -File -Force)) {
    if ($f.FullName.Length -gt $longest) { $longest = $f.FullName.Length; $longestPath = $f.FullName }
}
Say "  longest path is $longest characters" $(if ($longest -gt 250) { 'Yellow' } else { 'DarkGray' })
if ($longest -gt 250) { Say "    $longestPath" 'DarkGray' }

# ---- profile + launcher + installer ---------------------------------------
#
# Where the reference load order lives depends on which kind of build this is.
# With a Game folder of our own it is Profile\Default. A collection build has
# no Game folder, the game is the Steam copy, and Vortex writes the real
# plugins.txt into AppData, so Profile\Default is empty and always will be.
#
# Shipping the empty one is what put "this build shipped without a reference
# plugin list" in the launcher's Mods tab and left the manifest claiming zero
# plugins. A Game folder the launcher made out of Vortex's deployment reads
# the Vortex profile's lists kept in Profile\OwnGame. Get-ShipLoadOrderDir
# (Ship-Rules.ps1) decides, the same for the packs.
$refProfile = Get-ShipLoadOrderDir $Root $ProfileDir
Say "  load order from $refProfile" 'DarkGray'
# Only the two lists. Other launchers leave .bak copies of them beside the
# originals (Plugins.txt.keizaal-<date>.bak and the like); those are one
# machine's history, and the 16 Sep installer carried three of them.
Get-ChildItem -LiteralPath $refProfile -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in 'plugins.txt', 'loadorder.txt' } |
    Copy-Item -Destination (Join-Path $stage 'profile') -Force -ErrorAction SilentlyContinue
$stagedPlug = Join-Path (Join-Path $stage 'profile') 'plugins.txt'
if (-not (Test-Path -LiteralPath $stagedPlug)) {
    Say '  NO plugins.txt found, so this build ships without a reference load order.' 'Red'
    Say '  The launcher cannot check anybody against the server without it.' 'Red'
    Say "  Looked in: $refProfile" 'DarkGray'
}
$lexe = Get-LauncherExe $LaunchDir
if (Test-Path $lexe) {
    Copy-Item $lexe $stage -Force
    Say '  launcher exe included' 'Green'
} else {
    Say '  Thornswood.exe is not built yet. Run Build-Launcher.ps1 first.' 'Yellow'
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($f in 'Setup-Thornswood.ps1', 'Install.bat', 'Setup.bat', 'READ ME FIRST.txt') {
    $s = Join-Path $here $f
    if (Test-Path $s) { Copy-Item $s $stage -Force } else { Say "  $f missing next to this script" 'Yellow' }
}

$cfgSrc = Join-Path $Root 'config.json'
if (Test-Path $cfgSrc) { Copy-Item $cfgSrc $stage -Force }

# ---- what this build already has ------------------------------------------
#
# The launcher works out what needs updating by taking every pack in
# version.json and subtracting the ones listed in Profile\applied.txt. On a
# machine that has been here a while that is right. On a fresh install
# applied.txt does not exist, so nothing is subtracted, and the launcher
# decides all 165 packs ever published are waiting: it says "165 mod updates",
# tries to fetch the lot, falls over, and sits on UPDATE FIRST with Play shut.
#
# This build already contains every one of them, because it was made from the
# game they were applied to. So the list ships with it and the installer lays
# it down, and a fresh install starts level with this machine instead of at
# the beginning of the project.
# ---- which shape of install this payload is for ---------------------------
#
# A payload built with the collection's files left out cannot stand up its own
# Skyrim, because most of that Skyrim is what was left out. The installer has
# to put it into the Steam copy Vortex deployed into instead, and the launcher
# only reads the Steam copy when C:\Thornswood\Game does not exist. So the
# build says which shape it is and the installer does not have to guess.
$collectionFlag = Join-Path $stage 'collection.txt'
if (Test-Path -LiteralPath $collectionFlag) { Remove-Item $collectionFlag -Force }
if ($collectionCount -gt 0) {
    [IO.File]::WriteAllText($collectionFlag,
        "This build leaves out everything the Nexus collection provides.`r`n" +
        "The installer puts Thornswood into the Steam copy rather than making`r`n" +
        "one of its own, because the collection is deployed there.`r`n",
        (New-Object Text.UTF8Encoding($false)))
    Say '  built for the collection, so the installer will use the Steam copy' 'Green'
}

$appliedOut = Join-Path $stage 'applied.txt'
$vLive = Join-Path 'C:\Users\evilp\Downloads\Thornswood-Releases' 'version.json'
if (-not (Test-Path -LiteralPath $vLive)) { $vLive = Join-Path (Split-Path -Parent $here) 'version.json' }
if (Test-Path -LiteralPath $vLive) {
    try {
        $vd = ((Get-Content $vLive -Raw) -replace '^\uFEFF', '') | ConvertFrom-Json
        $ids = @()
        foreach ($pk in @($vd.packs)) {
            if ($pk -and $pk.PSObject.Properties['id'] -and $pk.id) { $ids += [string]$pk.id }
        }
        $ids = @($ids | Select-Object -Unique)
        if ($ids.Count -gt 0) {
            [IO.File]::WriteAllLines($appliedOut, $ids, (New-Object Text.UTF8Encoding($false)))
            Say ("  {0} packs marked as already in this build" -f $ids.Count) 'Green'
        } else {
            Say '  version.json lists no packs, so nothing was marked applied.' 'DarkGray'
        }
    } catch {
        Say "  could not read the pack list: $($_.Exception.Message)" 'Yellow'
        Say '  A fresh install will think every pack is a pending update.' 'Yellow'
    }
} else {
    Say '  no version.json found, so nothing was marked applied.' 'Yellow'
    Say '  A fresh install will think every pack is a pending update.' 'Yellow'
}

$plug = Join-Path $refProfile 'plugins.txt'
$manifest = [ordered]@{
    builtAt   = (Get-Date).ToString('u')
    files     = $shipCount
    bytes     = $shipBytes
    plugins   = if (Test-Path $plug) { @(Get-Content $plug | Where-Object { $_ -match '^\*' }).Count } else { 0 }
    exeBytes  = (Get-Item (Join-Path $GameDir 'SkyrimSE.exe')).Length
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $stage 'manifest.json') -Encoding UTF8

# The three files the installer takes from the player's own Steam copy that a
# multiplayer setup might have patched. Their fingerprints ride along so the
# installer can tell a clean Steam copy from a modified one, which a size check
# cannot. Bethesda's archives and masters are left out: nothing patches those,
# and hashing 15 GB on every package would cost more than it is worth.
# Get-FileHash lives in a module that is not always on PSModulePath, and a
# script started with -NoProfile can find itself without it. .NET is always
# there, so the hashing goes straight to it.
function Get-Sha256([string]$path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fs = [IO.File]::OpenRead($path)
        try { return ([BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-', '').ToLower() }
        finally { $fs.Close() }
    }
    finally { $sha.Dispose() }
}

# Nice to have, not load bearing. If it cannot be done, the package still ships
# and the installer simply skips the check rather than losing a long build.
try {
    $fingerprints = [ordered]@{}
    foreach ($f in 'SkyrimSE.exe', 'steam_api64.dll', 'bink2w64.dll') {
        $src = Join-Path $GameDir $f
        if (Test-Path $src) { $fingerprints[$f] = Get-Sha256 $src }
        else { Say "  $f is not in the build, so the installer cannot check it" 'Yellow' }
    }
    $fingerprints | ConvertTo-Json | Set-Content (Join-Path $stage 'vanilla.json') -Encoding UTF8
    Say ("  {0} vanilla fingerprints recorded" -f $fingerprints.Count) 'DarkGray'
}
catch {
    Remove-Item (Join-Path $stage 'vanilla.json') -Force -EA SilentlyContinue
    Say "  Could not fingerprint the Steam files: $($_.Exception.Message)" 'Yellow'
    Say '  Packaging carries on. The installer will skip that check.' 'DarkGray'
}

# ---- archive ---------------------------------------------------------------
if ($NoArchive) {
    Head 'Done'
    Say "Folder ready at $stage" 'Green'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0
}

Head 'Compressing'
$7z = @(
    "$env:ProgramFiles\7-Zip\7z.exe"
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $7z) {
    Say '  7-Zip is not installed. Getting it with winget...' 'Yellow'
    & winget install --id 7zip.7zip -e --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    $7z = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $7z) { Die "Could not find or install 7-Zip. Re-run with -NoArchive and zip $stage yourself." }

$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$ver = (& $7z | Select-Object -First 2) -join ' '
$ErrorActionPreference = $old
Say "  $7z"
Say "  $ver" 'DarkGray'

$blob = Join-Path $OutDir 'payload.zip'
if (Test-Path $blob) { Remove-Item $blob -Force }

# Room to write it. The stage is already a full copy of the build, and the zip
# lands beside it, so this wants roughly the size of the build again. 7-Zip
# answers a full disk with exit code 2 and a wall of progress text, which is
# not a sentence anybody can act on.
$stageBytes = (Get-ChildItem $stage -Recurse -File -EA SilentlyContinue |
               Measure-Object -Sum Length).Sum
$drive = (Get-Item $OutDir).PSDrive
$free  = $drive.Free
$want  = [long]($stageBytes * 0.75)
Say ("  staged {0:n1} GB, {1:n1} GB free on {2}:" -f ($stageBytes/1GB), ($free/1GB), $drive.Name) 'DarkGray'
if ($free -lt $want) {
    Say ''
    Say ("There is not enough room to write the archive. It needs about {0:n0} GB free" -f ($want/1GB)) 'Red'
    Say ("and {0}: has {1:n1} GB." -f $drive.Name, ($free/1GB)) 'Red'
    Say ''
    Say 'Two ways out:' 'Yellow'
    Say ''
    Say '  Put the archive on another drive:' 'Yellow'
    Say '    .\tools\Package-Thornswood.ps1 -ReuseStage -OutDir D:\Thornswood-dist' 'Green'
    Say ''
    Say ("  Or free up space on {0}: and re-run with -ReuseStage, which skips" -f $drive.Name) 'Yellow'
    Say '  the twenty minute copy because the staged folder is already there.' 'Yellow'
    Say ''
    Die "Not enough free space on $($drive.Name):."
}

Say '  Most of this content is already compressed, so the level is deliberately low.'
Say '  Around 18 GB in. Expect ten minutes or more.' 'DarkGray'

# A native tool writing a single line to stderr is enough to kill the whole
# script while ErrorActionPreference is Stop, so 7-Zip runs with it relaxed.
# Its output is kept rather than returned: returning it alongside the exit code
# made $rc an array of every line 7-Zip printed, so the failure message read as
# a paragraph and the -le 1 test below was comparing against a list.
$script:zipSaid = @()
function Invoke-7z([string[]]$zargs) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $stage
    try {
        $script:zipSaid = @(& $7z @zargs 2>&1 | ForEach-Object { "$_" })
        return [int]$LASTEXITCODE
    }
    finally { Pop-Location; $ErrorActionPreference = $old }
}

# Zip, not 7z, because the installer unpacks it with what .NET already has and
# never needs 7-Zip present on your friends' machines.
$attempts = @(
    @('a', '-tzip', '-y', "-mx$Level", $blob, '*'),
    @('a', '-tzip', '-y', $blob, '*')
)
$rc = 99
foreach ($try in $attempts) {
    Write-Host ("  > 7z " + ($try -join ' ')) -ForegroundColor DarkGray
    $rc = Invoke-7z $try
    if ($rc -le 1 -and (Test-Path $blob)) { break }
    Say "  that attempt exited with $rc" 'Yellow'
    # The useful part of what 7-Zip said is at the end, not the start, and the
    # start is 30,000 lines of file names.
    $tail = @($script:zipSaid | Where-Object { $_ -and $_ -notmatch '^\s*\d+%' }) | Select-Object -Last 8
    foreach ($l in $tail) { Say "    $l" 'DarkGray' }
    if (Test-Path $blob) { Remove-Item $blob -Force -EA SilentlyContinue }
}
if (-not (Test-Path $blob)) {
    Say ''
    Say "The staged folder is still at $stage, so nothing is lost." 'Yellow'
    Say 'Re-run with -ReuseStage once this is sorted and it will skip the copy.' 'Yellow'
    Say ''
    Say 'Exit code 2 from 7-Zip is nearly always the disk filling up part way' 'DarkGray'
    Say 'through, or a file being held open by something. Check free space first:' 'DarkGray'
    Say '    Get-PSDrive C | Select-Object Used, Free' 'Green'
    Die '7-Zip did not produce the archive.'
}
Say ("  payload.zip is {0:n2} GB" -f ((Get-Item $blob).Length / 1GB)) 'Green'

if ($Plain7z) {
    Head 'Done'
    Say "$blob" 'Green'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0
}

# ---- two files, side by side ---------------------------------------------
# The payload used to be appended to the stub and shipped as one exe. Windows
# refuses to load an executable this size, so it now travels beside it.
Head 'Building the installer'

$exe = Join-Path $OutDir 'Thornswood-Setup.exe'
$zip = Join-Path $OutDir 'Thornswood-Setup.zip'

if (Test-Path $zip) { Remove-Item $zip -Force }
Move-Item $blob $zip

$stub = @((Join-Path $here 'setup-stub.exe'), (Join-Path $OutDir 'setup-stub.exe')) |
        Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $stub) {
    Head 'Done, but incomplete'
    Say '  setup-stub.exe is missing, so THIS PACKAGE HAS NO INSTALLER.' 'Red'
    Say '  Do not upload it. Anyone who got it would have to unzip it by hand' 'Red'
    Say '  and find Install.bat themselves.' 'Red'
    Write-Host ''
    Say "  $zip" 'DarkGray'
    Say '  Build-Launcher.ps1 compiles the stub. Look at its Setup stub section' 'Yellow'
    Say '  for the compile error, fix it, then run this again.' 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 1
}

if (Test-Path $exe) { Remove-Item $exe -Force }
Copy-Item $stub $exe -Force
Say "  stub: $stub" 'DarkGray'

# ---- one file, payload attached -------------------------------------------
# STSFX001, then the offset the payload starts at, then its length. Both are
# 64 bit and little endian, which is what BinaryReader.ReadInt64 wants on the
# other side. Written after the copy so a failure here leaves a plain stub
# rather than a half attached one.
if ($OneFile) {
    Say '  attaching the payload to the setup program' 'DarkGray'
    $fsOut = [IO.File]::Open($exe, [IO.FileMode]::Append, [IO.FileAccess]::Write)
    try {
        $off = $fsOut.Position
        $fsIn = [IO.File]::OpenRead($zip)
        try { $fsIn.CopyTo($fsOut, 4MB) } finally { $fsIn.Dispose() }
        $len = (Get-Item $zip).Length
        $bw = New-Object IO.BinaryWriter($fsOut)
        $bw.Write([Text.Encoding]::ASCII.GetBytes('STSFX001'))
        $bw.Write([long]$off)
        $bw.Write([long]$len)
        $bw.Flush()
    } finally { $fsOut.Dispose() }
    Say ("  attached, offset {0:n0}, {1:n2} GB" -f $off, ($len / 1GB)) 'Green'
}

# ---- prove it before it goes anywhere ------------------------------------
Head 'Checking the installer'
$ok = $true

$exeLen = (Get-Item $exe).Length
$fs = [IO.File]::OpenRead($exe)
try {
    $sig = New-Object byte[] 2
    [void]$fs.Read($sig, 0, 2)
    if ($sig[0] -ne 0x4D -or $sig[1] -ne 0x5A) {
        Say '  the setup program is not a Windows executable' 'Red'; $ok = $false
    } else {
        Say ("  setup program looks right, {0:n0} KB" -f ($exeLen / 1KB)) 'Green'
    }
} finally { $fs.Close() }

# Anything near the loader's limit is the bug the two file split exists to
# avoid. With the payload attached it is meant to be big, so the ceiling moves
# to the point where Windows starts refusing to load it at all.
if ($OneFile) {
    if ($exeLen -lt 64MB) {
        Say '  the setup program is too small to have the payload in it' 'Red'; $ok = $false
    } elseif ($exeLen -gt 2GB) {
        Say '  the setup program is over 2 GB, which Windows will refuse to load' 'Red'; $ok = $false
    } else {
        Say ("  payload attached, {0:n2} GB in one file" -f ($exeLen / 1GB)) 'Green'
    }
} elseif ($exeLen -gt 100MB) {
    Say '  the setup program is far bigger than it should be' 'Red'; $ok = $false
}

$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$listing = & $7z l $zip 2>&1
$ErrorActionPreference = $old
# Four names, and they are the names this build actually uses.
#
# These were still looking for Install-SkyrimTogether.ps1 and
# SkyrimTogether.exe, from before the rename. The first of those has not
# existed for a long time, so the check failed on every run and reported a
# missing installer script while the installer itself was fine.
#
# The launcher check was worse, because it passed. Somewhere in 22 GB of
# game build there is a leftover SkyrimTogether.exe, and a bare substring
# match found it and called it the launcher. A check that answers yes
# whatever happens is not a check.
#
# So each one is anchored to the end of the line and refused if anything
# path-like sits in front of it. 7-Zip prints the name last, and a file at
# the root of the archive has nothing before it, which is the question
# that was meant all along: is this file at the top of the installer.
$atRoot = {
    param($name)
    $rx = '(?<![\\/\w.-])' + [regex]::Escape($name) + '\s*$'
    $listing | Where-Object { $_ -match $rx }
}
$hasSetup    = & $atRoot 'Setup.bat'
$hasInstall  = & $atRoot 'Setup-Thornswood.ps1'
$hasLauncher = & $atRoot 'Thornswood.exe'
# The payload is a FOLDER in the archive, not a file. The staged copy is
# built at <stage>\payload and zipped with everything else beside it, so
# what is in here is a directory entry named payload plus 34,000 things
# filed under payload\. Asking for payload.zip found neither. Either shape
# counts: the directory entry on its own, or anything inside it.
$hasPayload  = $listing | Where-Object { $_ -match '(?<![\\/\w.-])payload(\\|\s*$)' }
foreach ($pair in @(@('Setup.bat', $hasSetup), @('the installer script', $hasInstall),
                    @('the launcher', $hasLauncher), @('the mod payload', $hasPayload))) {
    if ($pair[1]) { Say "  found $($pair[0])" 'Green' } else { Say "  MISSING $($pair[0])" 'Red'; $ok = $false }
}

# Being in the archive is not the same as being current. The zip is updated in
# place rather than rebuilt, so a file that failed to copy into the stage leaves
# last run's copy sitting there under the right name, and every check above
# still passes. These three are the ones that decide whether a friend ends up
# with this build or the last one, so they get pulled back out and compared
# against what went in.
if ($ok) {
    $check = Join-Path $OutDir 'verify'
    if (Test-Path $check) { Remove-Item $check -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $check

    foreach ($name in 'Setup-Thornswood.ps1', 'Setup.bat', 'Thornswood.exe') {
        $src = Join-Path $stage $name
        if (-not (Test-Path $src)) { continue }

        $old2 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $null = & $7z e "-o$check" -y $zip $name 2>&1
        $ErrorActionPreference = $old2

        $got = Join-Path $check $name
        if (-not (Test-Path $got)) {
            Say "  could not read $name back out of the zip" 'Red'; $ok = $false; continue
        }
        if ((Get-Sha256 $got) -ne (Get-Sha256 $src)) {
            Say "  $name in the zip is not the one that was just built" 'Red'
            Say '    the archive kept an older copy. Delete payload.zip and run this again.' 'Yellow'
            $ok = $false
        } else {
            Say "  $name is current" 'Green'
        }
    }
    Remove-Item $check -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $ok) { Die 'The installer did not come out right. Do not send these files.' }

$gb = [math]::Round((Get-Item $zip).Length / 1GB, 2)
Head 'Done'
if ($OneFile) {
    Say ("Thornswood-Setup.exe  -  {0:n2} GB, one file, nothing beside it" -f ($exeLen / 1GB)) 'Green'
} else {
    Say ("Thornswood-Setup.exe  -  {0:n0} KB" -f ($exeLen / 1KB)) 'Green'
    Say "Thornswood-Setup.zip  -  $gb GB" 'Green'
}
Write-Host ''

if (-not $NoPublish) {
    Head 'Publishing to the site'
    $pub = Join-Path $PSScriptRoot 'Publish-Installer.ps1'
    if (Test-Path -LiteralPath $pub) {
        try {
            if ($OneFile) { & $pub -OutDir $OutDir -OneFile } else { & $pub -OutDir $OutDir }
        } catch {
            Say "  could not publish: $_" 'Yellow'
            Say '  The installer is still built and fine. Run' 'DarkGray'
            Say '  .\tools\Publish-Installer.ps1 when the VPS is reachable.' 'DarkGray'
        }
    } else {
        Say '  Publish-Installer.ps1 is missing, nothing was published.' 'Yellow'
    }
} elseif ($OneFile) {
    Say 'One file. Upload the exe and nothing else. Whoever gets it runs it.' 'Gray'
} else {
    Say 'Upload BOTH to the same place. Your friends need both in one folder, then' 'Gray'
    Say 'they run the exe. It finds the zip on its own and does the rest.' 'Gray'
    Say 'They must not unzip it themselves.' 'DarkGray'
}

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
