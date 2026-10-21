<#
  Package-Thornswood.ps1
  Turns the built install at C:\Thornswood into the single file your friends run.

  Only your mod content goes in. Every Bethesda file is left out, because the
  installer rebuilds those from each friend's own Steam copy and their own
  Steam depots.
#>
[CmdletBinding()]
param(
    [string]$Root    = (& (Join-Path $PSScriptRoot 'Where.ps1') Install),
    # Out of the play install since 22 September. Staging a 508 MB installer
    # and its 956 MB stage folder inside the folder people play from put 10.9
    # GB on the game drive over five days. Ship passes this explicitly; the
    # default matches what Ship and Publish-Update work out for themselves.
    [string]$OutDir  = (& (Join-Path $PSScriptRoot 'Where.ps1') Package),
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
    [switch]$OneFile,
    # The folder holding the live feed. Its version.json is how this build
    # knows which packs it already has (applied.txt, further down). Left empty
    # it is this machine's working copy of the live feed,
    # %LOCALAPPDATA%\Thornswood\feed\main, which every Ship and feed edit
    # receives from the VPS (Feed-Store.ps1, #907); until #907 it was the
    # Thornswood-Releases clone beside this repo. It was once a path into one
    # home folder, so only one machine could build an installer that knew its
    # own packs.
    # Last in the list so no existing positional argument moves.
    [string]$ReleaseDir = '',
    # The setup program to build the installer around, instead of the one
    # the last Build-Launcher left in out\. A main Ship passes the one CI
    # built for the tag it ships (issue #932); nothing else needs it.
    [string]$Stub = '',
    # Go ahead from a checkout that is not exactly origin/main and clean (#2118). Loud.
    [switch]$AllowStaleCheckout
)

$ErrorActionPreference = 'Stop'   # before any file loads, so one that is missing stops here (#3006)
# A stale or dirty checkout sends old or unlanded code; refuse it (#2118).
# The installer is a live release, so the branch rule is Ship's for a main
# release, Test-FreshAnyBranch -Channel main (#2436): main, or a clean
# hotfix/ branch that matches its own origin branch. Publish-Installer, which
# this calls at the end, asks the same and is handed -AllowStaleCheckout.
. (Join-Path $PSScriptRoot '..\deploy\Fresh-Checkout.ps1')
$freshRepo = Join-Path $PSScriptRoot '..\..'
Assert-FreshCheckout -RepoDir $freshRepo -What 'Package-Thornswood' -AnyBranch:(Test-FreshAnyBranch -RepoDir $freshRepo -Channel main) -AllowStale:$AllowStaleCheckout


# The launcher, Thornswood.exe in the launcher folder.
function Get-LauncherExe([string]$dir) {
    return (Join-Path $dir 'Thornswood.exe')
}

Set-StrictMode -Version Latest

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
    # Either key may be missing (Steam writes one or the other), so each is
    # tested for, and a key without SteamPath names nothing.
    foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\Wow6432Node\Valve\Steam')) {
        if (-not (Test-Path -LiteralPath $k)) { continue }
        $kp = Get-ItemProperty -LiteralPath $k
        if ($kp.PSObject.Properties['SteamPath'] -and $kp.SteamPath) { $roots += ([string]$kp.SteamPath -replace '/', '\') }
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
    # Build-Thornswood.ps1 used to be named here. It is deleted: run today it
    # produced a broken folder pointed at a server address that no longer
    # exists, and there is one build path now.
    Die "No build at $GameDir, and no Steam copy of Skyrim either. Deploy the collection in Vortex, then run .\scripts\release\Ship.ps1, which builds the game folder."
}

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

# ==== thornswood release feed ====
# Found and checked before anything is staged or any game is closed, because
# without it the build cannot write applied.txt and there is no point spending
# twenty minutes on an installer that is wrong.
#
# It used to fall back to this repo's own version.json when the home folder
# path was missing. MEASURED 24 SEPTEMBER: the feed lists 227 packs and the
# repo's copy lists 164, so on any machine but Patrick's the installer marked
# 63 packs as missing from a build that had them, and a fresh install fetched
# them all again. With neither file there it shipped no applied.txt at all:
# every one of the 227 packs pending on first launch, and 164 of them point at
# the private repository. So it stops and says where it looked.
if (-not $ReleaseDir) { $ReleaseDir = & (Join-Path $Here 'Where.ps1') Releases }
$vLive = Join-Path $ReleaseDir 'version.json'
if (-not (Test-Path -LiteralPath $vLive)) {
    Die ("No version.json in $ReleaseDir, so this installer cannot say which packs it already has, " +
         "and everybody who installs from it would be offered every pack ever published. " +
         "Any Ship or feed edit on this machine receives the live feed there; or save " +
         "https://thornswood.net/feed/version.json into a folder and pass -ReleaseDir with it.")
}
# ==== end thornswood release feed ====

# ==== thornswood setup stub ====
# The setup program is compiled by Build-Launcher.ps1 into out\setup-stub.exe,
# which git ignores, and this only copies it (Building the installer, below).
# So it is as new as the last Build-Launcher on this machine, whatever
# setup\Bootstrap.cs now says. On 25 September the installer went on the site
# straight after the pull that brought #340, the fix for old zips in the
# Downloads folder, with no Build-Launcher between them, and nothing here could
# say which Bootstrap.cs the stub it shipped was built from. A stub older than
# its source is refused here, before anything is staged or any game is closed.
# No stub at all is left to the stop further down, which already says so.
function Get-StubRefusal([string]$stub, [string]$src) {
    if (-not (Test-Path -LiteralPath $src)) { return '' }
    if (-not $stub -or -not (Test-Path -LiteralPath $stub)) { return '' }
    $built = (Get-Item -LiteralPath $stub).LastWriteTimeUtc
    $changed = (Get-Item -LiteralPath $src).LastWriteTimeUtc
    if ($built -ge $changed) { return '' }
    return ('The setup program, ' + $stub + ', was compiled ' +
            $built.ToLocalTime().ToString('d MMM HH:mm') + ', before the last change to ' + $src +
            ' (' + $changed.ToLocalTime().ToString('d MMM HH:mm') + '), so the installer would carry ' +
            'the old one. Build-Launcher.ps1 compiles it, into a scratch root so the launcher you play ' +
            'with is left alone. From PowerShell 7 in the repo folder, the way Ship runs it: ' +
            '.\scripts\release\Build-Launcher.ps1 -Root "$env:TEMP\ts-build" -NoPause and then run this again.')
}
# Given one (-Stub, a main Ship's from CI, issue #932), that one and no other:
# a file that is not there stops the build here rather than packing a
# different stub found in out\.
if ($Stub) {
    if (-not (Test-Path -LiteralPath $Stub)) { Die ('The setup program given with -Stub is not there: ' + $Stub + '. Nothing was built.') }
    $stubNow = (Resolve-Path -LiteralPath $Stub).Path
} else {
    $stubNow = @((Join-Path (& (Join-Path $Here 'Where.ps1') Out) 'setup-stub.exe'), (Join-Path $OutDir 'setup-stub.exe')) |
               Where-Object { Test-Path $_ } | Select-Object -First 1
}
$stubWhy = Get-StubRefusal $stubNow (Join-Path $Here '..\..\installer\setup\Bootstrap.cs')
if ($stubWhy) { Die $stubWhy }
# ==== end thornswood setup stub ====

. (Join-Path $Here '..\dev\Close-Launcher.ps1')

Head 'Packaging'

# A live game rewrites files under Game and Profile while this is listing and
# hashing them, which is how a package ends up half one version.
$null = Stop-Game -Root $Root

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
# Bethesda's own files, and other people's frameworks and modding tools. The
# lists were here, and a shorter copy of them in Publish-Update.ps1, until
# 24 September, when packs were found carrying 90 files this left out. They
# are one list in Ship-Rules.ps1 now.
function Test-Vanilla([string]$rel) { return ((Test-ShipVanilla $rel) -or (Test-ShipForeignFramework $rel)) }
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

# ---- the client runtime always ships, whatever anything else says ---------
#
# THE SIX FILES IN client-build.json ARE THE ONE THING A TESTER CANNOT GET ANY
# OTHER WAY, and on 22 September one of them found that out.
#
# They are built from the fork and put into the game folder by Sync-Client.ps1,
# which runs on Patrick's machine. OwnGame.WhyLeft refuses to take them from
# the Steam copy, deliberately, because until 20 September the copies sitting
# there were another launcher's builds. So for somebody who is not Patrick
# there are exactly two routes: this installer, and a pack.
#
# Ship-Rules.ps1 has read the checkout record for packs all along, and
# Test-ShipOtherServer calls a path in it ours when the file there is the
# recorded build, so a pack carries all six. Nothing here did the same until
# the listing below, and a brand new install arrived with "skymp5-client.js
# is missing" and a Play button that would not press.
#
# WHICH RECORD (#1243). This used to pin those six files to
# records\client-build.json in the checkout. Between main Ships that file
# moves ahead of the launcher this installer packs. The installed launcher
# carries its own client-build.json, embedded when it was built, and that is
# the client it checks and, when they differ, the client it puts back
# (ClientRuntime.Heal). Pinning the installer to the checkout then either
# refuses the main play folder, whose client still matches that launcher, or
# ships a client the launcher replaces on first launch.
#
# So there is one record: the one that launcher was built with. It is read
# out of the exe being packed. When that exe has none, it is the main feed's
# clientRuntime, the zip beside that feed when it is there, or the checkout
# record only while its fork commit is still the one the feed names. The
# checkout file on its own is not a record this installer is held to.
#
# This is a KEEP list, not a leave-out list: whatever the Vortex record or the
# vanilla patterns in Ship-Rules.ps1 decide, the recorded build at a path in
# the record ships. Anything else at one of those paths stops the build; see
# the note over $clientWrong below. Apply-PackageClientRecord replaces the
# hashes Ship-Rules just loaded from the checkout, so Test-ShipClientRecorded
# answers the packed launcher's record and not the checkout's.
. (Join-Path $Here 'Package-ClientRecord.ps1')
$checkoutClientRecord = Join-Path $PSScriptRoot '..\..\records\client-build.json'
$resolvedClient = Resolve-PackageClientRecord -LauncherExe (Get-LauncherExe $LaunchDir) -FeedVersion $vLive -CheckoutRecord $checkoutClientRecord
if (-not $resolvedClient) {
    Die ('The client runtime this installer carries is the one the launcher it packs was built with, ' +
         'read from that launcher, or the main feed''s clientRuntime when the launcher has no record. ' +
         'Neither could be read, and records\client-build.json in this checkout is not that client, so nothing was packaged.')
}
Apply-PackageClientRecord $resolvedClient.Record
$clientRecordPath = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-package-client-' + [Guid]::NewGuid().ToString('N') + '.json')
Save-PackageClientRecord $resolvedClient $clientRecordPath
$clientFork = [string]$resolvedClient.Record.forkCommit
if ($resolvedClient.Source -eq 'launcher') {
    Say ("  {0} client runtime file(s) held to the record embedded in the launcher this installer packs ({1})" -f $shipClientFiles.Count, $clientFork) 'Green'
} else {
    Say ("  {0} client runtime file(s) held to the main feed's clientRuntime ({1})" -f $shipClientFiles.Count, $clientFork) 'Green'
}
if ($resolvedClient.FeedFork -and $resolvedClient.FeedFork -ne $clientFork) {
    Say ("  the main feed's clientRuntime is {0}; this installer follows the launcher it packs ({1})" -f $resolvedClient.FeedFork, $clientFork) 'Yellow'
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
            # A record that is there but unreadable used to warn and carry on,
            # which builds the old standalone payload with no collection.txt: the
            # shape whose installer copies mid-download after an early Enter and
            # gives testers the wrong files (issue #369 F2). Refuse it, the same
            # as an empty own-game record above; -NoVortex is the way to ship
            # everything on purpose.
            Die ("The Vortex record at $VortexManifest is there but could not be read, so the collection files cannot be left out and this installer would carry every mod file: " +
                 $_.Exception.Message + " Fix the record, or pass -NoVortex to ship everything on purpose.")
        }
    }
    else {
        # No record and no -NoVortex used to warn and build a full standalone
        # payload without collection.txt, which is the dangerous installer shape
        # (issue #369 F2). Refuse rather than warn.
        Die ("No Vortex record found at $VortexManifest, so the collection files cannot be left out and this installer would carry every mod file and build the old standalone shape (no collection.txt). Deploy once in Vortex so the record appears, or pass -NoVortex to ship everything on purpose.")
    }
}

$shipGeneratedFiles = Get-ShipGeneratedFiles $ProfileDir
Assert-ShipGeneratedBodies $GameDir $ProfileDir
function Test-FromCollection([string]$rel) {
    if ($null -eq $vortexFiles) { return $false }
    if (Test-ThornswoodRepoPlugin $rel) { return $false }
    if ($shipGeneratedFiles -contains $rel) { return $false }
    return $vortexFiles.Contains($rel)
}

Say '  Listing the build...'
# Place plugins the load order names that Vortex does not deploy under that
# name (game\required-data). Same ensure Publish-Update runs before its scan.
$repoRoot = Join-Path $Here '..\..'
try {
    $req = @(Ensure-ShipRequiredData $GameDir $repoRoot)
    if ($req.Count) {
        Say ("  required data placed into the game folder: {0}" -f ($req -join ', ')) 'Green'
    }
} catch {
    Die ("Could not place game\required-data into $GameDir : " + $_.Exception.Message)
}

try {
    $null = Save-ShipUiHashedAssets $GameDir
    Say ("  front hashed assets named by build.js: {0}" -f @($script:ShipUiHashedWritten).Count) 'DarkGray'
} catch {
    Die $_.Exception.Message
}

# Listed from the long path. $GameDir is whatever was passed, and that is
# the short 8.3 form when the folder sits under a short TEMP. FullName is
# the long one, so cutting by $GameDir's length takes the wrong relative
# path (issue #1156).
$listedGame = (Get-Item -LiteralPath $GameDir).FullName
$all = @(Get-ChildItem -LiteralPath $listedGame -Recurse -File -Force)
# Named with \ on any machine, as every rule and record names them; off
# Windows FullName is joined with / (#2989), as Publish-Update already reads it.
$sep = [string][IO.Path]::DirectorySeparatorChar
$prefix = $listedGame.TrimEnd($sep) + $sep

$ship = @(); $skipBytes = 0; $shipBytes = 0; $optionalBytes = 0; $optionalCount = 0; $machineCount = 0
$collectionBytes = 0; $collectionCount = 0
$notOursBytes = 0; $notOursCount = 0
# What waits for the collection (Ship-Rules, #1178) is asked at the revision
# this machine's Vortex has installed. LoadOrder.ps1 is loaded only in here,
# so its functions do not change anything else this script asks.
$ShipCollectionRevision = & { . (Join-Path $Here '..\mods\LoadOrder.ps1'); Get-ShipCollectionRevision $Root }
Say ("  collection revision {0}: loose files held for the collection until then still ship" -f $ShipCollectionRevision) 'DarkGray'
$clientShipped = 0
$clientWrong = @()
foreach ($f in $all) {
    $rel = $f.FullName.Substring($prefix.Length).Replace($sep, '\')
    # Ours by record, before any filter is asked. See the note over
    # $shipClientFiles: these six are the only files a tester cannot get from
    # anywhere else, and a missing one is a Play button that will not press.
    # Only the recorded build of each: anything else is named below and stops
    # the build.
    if ($shipClientFiles.Contains($rel)) {
        if (-not (Test-ShipClientRecorded $rel $f.FullName)) { $clientWrong += $rel; continue }
        $ship += [pscustomobject]@{ Rel = $rel; Full = $f.FullName; Len = $f.Length; Time = $f.LastWriteTimeUtc }
        $shipBytes += $f.Length
        $clientShipped++
        continue
    }
    if (Test-Vanilla $rel) { $skipBytes += $f.Length; continue }
    if (Test-Runtime $rel) { $skipBytes += $f.Length; continue }
    if (Test-ShipMachine $rel) { $skipBytes += $f.Length; $machineCount++; continue }
    # The installer is main. Dev only files never go in it (Ship-Rules).
    if (Test-ShipDevOnly $rel) { $skipBytes += $f.Length; continue }
    if (Test-Optional $rel) { $optionalBytes += $f.Length; $optionalCount++; continue }
    if (Test-FromCollection $rel) { $collectionBytes += $f.Length; $collectionCount++; continue }
    # Other people's loose files (#1178), after the collection's so those are
    # counted as the collection's.
    if (Test-ShipNotOurs $rel) { $skipBytes += $f.Length; $notOursBytes += $f.Length; $notOursCount++; continue }
    if ($f.Extension -in '.pdb', '.log') { $skipBytes += $f.Length; continue }
    $ship += [pscustomobject]@{ Rel = $rel; Full = $f.FullName; Len = $f.Length; Time = $f.LastWriteTimeUtc }
    $shipBytes += $f.Length
}
Say ("  {0:n0} files kept ({1:n1} GB), {2:n0} left out ({3:n1} GB of Bethesda files and debug symbols)" -f `
    $ship.Count, ($shipBytes / 1GB), ($all.Count - $ship.Count), ($skipBytes / 1GB)) 'Green'

# AND IT STOPS IF ANY OF THEM IS NOT THE RECORDED BUILD (To Do entry 128).
#
# Being at the path is not being ours. Ship refuses a release whose client is
# not the recorded build, through Sync-Client.ps1 -Check, but it checks
# Root\Game, and this can build out of the Steam copy (-Vortex, or no
# SkyrimSE.exe under Root\Game), where until 20 September another launcher's
# bundle and DLLs sat at these very paths. This loop kept whatever was there,
# by path, without a word. It asks Ship-Rules now, the same sha256 the packs
# are held to.
#
# Die rather than throw. Measured 24 September: a throw in a script Ship calls
# with & stops Ship itself, and Ship runs this after the release is already
# out, where its note says a failed installer must be reported, not fatal.
# Die exits 1, which Ship reads.
if ($clientWrong.Count) {
    Write-Host ''
    Say ("  STOP. {0} of the {1} client runtime files in {2} are not the recorded build:" -f `
        $clientWrong.Count, $shipClientFiles.Count, $GameDir) 'Red'
    foreach ($c in $clientWrong) { Say ("    " + $c) 'Red' }
    Say '  The record is the one the launcher this installer packs was built with.' 'Red'
    Say '  It is read from that launcher, or from the main feed''s clientRuntime,' 'Red'
    Say '  not from records\client-build.json in the checkout.' 'Red'
    Say '  Leave the main play folder''s client as it is. Package again from the' 'Red'
    Say '  folder whose client matches that launcher, or pack a launcher built' 'Red'
    Say '  with the client you mean to ship.' 'Red'
    Die 'the client runtime is not the recorded build, so this installer was not built'
}

# AND IT STOPS IF THE CLIENT RUNTIME IS NOT ALL THERE.
#
# A warning is not enough for this one. An installer missing one of these six
# builds cleanly, uploads cleanly, installs cleanly, and then every new tester
# reaches a Play button that will not press and is told to reinstall. That is
# what happened on 22 September, and nothing anywhere said a thing. Refusing
# here is the only place it can be caught before somebody downloads it.
if ($shipClientFiles.Count -gt 0) {
    if ($clientShipped -eq $shipClientFiles.Count) {
        Say ("  all {0} client runtime files are in" -f $clientShipped) 'Green'
    } else {
        $inShip = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($s in $ship) { [void]$inShip.Add($s.Rel) }
        Write-Host ''
        Say ("  STOP. {0} of the {1} client runtime files are not in this installer:" -f `
            ($shipClientFiles.Count - $clientShipped), $shipClientFiles.Count) 'Red'
        foreach ($c in $shipClientFiles) { if (-not $inShip.Contains($c)) { Say ("    " + $c) 'Red' } }
        Say '  They are not in the game folder this is being built from.' 'Red'
        Say '  The record is the one in the launcher this installer packs, not the checkout.' 'Red'
        Say '  Shipping without them gives every new tester a Play button that will not press.' 'Red'
        Write-Host ''
        Die 'the client runtime is incomplete, so this installer was not built'
    }
}
if ($machineCount) { Say ("  {0:n0} of this machine's own files, other servers' files and sign in tokens left out" -f $machineCount) 'DarkGray' }
if ($notOursCount) { Say ("  {0:n0} loose file(s) of other people's mods left out ({1:n1} MB), never ours to hand out" -f $notOursCount, ($notOursBytes / 1MB)) 'DarkGray' }
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
# Loose textures and meshes that are neither ours nor the collection's, named a
# folder at a time. The installer on the site carried them on 23 September,
# 539 MB by this machine's record the day after, and no build ever said so.
# See Get-ShipLooseArt in Ship-Rules.ps1; it reports and stops nothing.
$loose = Get-ShipLooseArt $ship
if ($loose.Count) {
    $looseFiles = 0; $looseBytes = [long]0
    foreach ($l in $loose) { $looseFiles += $l.Files; $looseBytes += $l.Bytes }
    Say ("  LOOSE ART THAT IS NOT OURS: {0:n0} file(s), {1:n1} MB, in {2} folder(s)." -f `
        $looseFiles, ($looseBytes / 1MB), $loose.Count) 'Yellow'
    Say '  Under Data\textures and Data\meshes, not from the collection, and in this' 'Yellow'
    Say '  installer for everybody. Take it out of the game folder, or put its mod in' 'Yellow'
    Say '  the collection, or, if it is ours, in the Thornswood Content mod.' 'Yellow'
    foreach ($l in $loose) {
        Say ("    {0,8:n1} MB {1,6:n0} file(s)  {2}" -f ($l.Bytes / 1MB), $l.Files, $l.Folder) 'DarkGray'
    }
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
    $listedPayload = (Get-Item -LiteralPath $payload).FullName
    foreach ($f in (Get-ChildItem -LiteralPath $listedPayload -Recurse -File -Force)) {
        $have[$f.FullName.Substring($listedPayload.TrimEnd('\').Length + 1)] = $f
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
# originals (Plugins.txt.<server>-<date>.bak and the like); those are one
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
    # In installer\ since the reorganisation's phase 7 (issue #440).
    $s = Join-Path (Join-Path $here '..\..\installer') $f
    # All four are in the repository, so a missing one is a wrong path, and an
    # installer without it is broken for everybody (issue #440, phase 0).
    if (Test-Path $s) { Copy-Item $s $stage -Force } else { Die "$f is not at $s. It is in the repository, so the path is wrong. Nothing was packaged." }
}

# ---- where the source is ---------------------------------------------------
#
# The six files in client-build.json are SkyMP, built from the fork, and so is
# the server's engine. SkyMP's folders carry the GNU GPL and AGPL version 3,
# each in its own LICENSE file, and this installer hands those files to
# people. Entry 170 on the To Do List asked for the source to be reachable
# "from the download page and from inside the installed folder", and nothing
# in the installer said where it was.
#
# So the installer carries SOURCE CODE.txt, written here from the two build
# records rather than typed, so it names the commit this payload was built
# from and no other. Setup-Thornswood.ps1 copies it into the install folder,
# because the folder the setup program unpacks into is scratch. The same facts
# are on thornswood.net/credits, and tests\test-source-offer.ps1 fails when
# the page, this note and the records disagree.
#
# Measured 24 September: git ls-remote against the public fork, with no
# credentials, answers c8832519866e for thornswood/engine-changes, the commit
# both records named that day. Both name the pinned commit since #1200, and this
# note reads them rather than repeating either. Which folder builds which file
# was read off the fork's own build files at that commit, and each licence off
# that folder's LICENSE.
#
# The six are not all the SkyMP the installer carries. The 23 September stage
# also had Data\Platform\UI\build.js (a webpack build of skymp5-front, GPL v3,
# dated 13 September, before the fork existed), Data\Platform\Modules\
# skyrimPlatform.ts (skyrim-platform's declarations, an older copy than the
# fork builds) and Data\Scripts\MpClientPlugin.pex (byte for byte the fork's
# client-deps copy, a folder with no LICENSE). Nobody built those here or
# recorded which SkyMP they came from. The first version of this note said
# "All of it is built from" the fork, which was false for build.js, so the
# note now lists whichever of them the payload holds as their own group, with
# the gap said and upstream named, rather than claiming a commit for them.
function Get-SourceNotice([string]$ClientRecord, [string]$ServerRecord, [string]$PayloadDir) {
    # A file the record gains that is not here stops the package, because a
    # person has to look at where it comes from before a notice names it.
    $from = @{
        'skymp5-client.js'             = @('skymp5-client',   'GNU GPL version 3')
        'SkyrimPlatform.dll'           = @('skyrim-platform', 'GNU GPL version 3')
        'SkyrimPlatformImpl.dll'       = @('skyrim-platform', 'GNU GPL version 3')
        'SkyrimPlatformCEF.exe.hidden' = @('skyrim-platform', 'GNU GPL version 3')
        'TESModPlatform.pex'           = @('skyrim-platform', 'GNU GPL version 3')
        'MpClientPlugin.dll'           = @('skymp5-server',   'GNU AGPL version 3')
        'scam_native.node'             = @('skymp5-server',   'GNU AGPL version 3')
    }
    foreach ($p in @($ClientRecord, $ServerRecord)) {
        if (-not (Test-Path -LiteralPath $p)) { throw "$p is missing" }
    }
    # An empty record reads as $null; say so, rather than a method call on $null.
    $cRaw = "$(Get-Content -LiteralPath $ClientRecord -Raw)"
    $sRaw = "$(Get-Content -LiteralPath $ServerRecord -Raw)"
    foreach ($x in @(@($ClientRecord, $cRaw), @($ServerRecord, $sRaw))) {
        if (-not $x[1].Trim([char]0xFEFF, ' ', [char]9, [char]13, [char]10)) { throw ($x[0] + ' is empty') }
    }
    $c = $cRaw.TrimStart([char]0xFEFF) | ConvertFrom-Json
    $s = $sRaw.TrimStart([char]0xFEFF) | ConvertFrom-Json
    $fork  = ([string]$c.fork).TrimEnd('/')
    $sRepo = ([string]$s.source.repo) -replace '\.git$', ''
    if (-not $fork -or -not $c.forkCommit) { throw 'client-build.json names no fork or no commit' }
    if (-not $sRepo -or -not $s.source.commit -or -not $s.binary) { throw 'server-build.json names no repository, commit or binary' }
    $upstream = 'https://github.com/skyrim-multiplayer/skymp'
    if ($s.source.upstream) { $upstream = ([string]$s.source.upstream) -replace '\.git$', '' }

    $table = @()
    foreach ($rel in @($c.files.PSObject.Properties.Name)) {
        $leaf = $rel.Substring($rel.LastIndexOf('\') + 1)
        if (-not $from.ContainsKey($leaf)) { throw "client-build.json lists $leaf, which has no known source folder" }
        $table += ('  {0,-34}{1,-18}{2}' -f $leaf, $from[$leaf][0], $from[$leaf][1])
    }
    $bin = [string]$s.binary
    if (-not $from.ContainsKey($bin)) { throw "server-build.json names $bin, which has no known source folder" }
    $table += ('  {0,-34}{1,-18}{2}' -f ($bin + ' (the server)'), $from[$bin][0], $from[$bin][1])

    # SkyMP files the payload carries that Thornswood did not build. Only the
    # ones actually in the payload are named, and one the client record takes
    # over later (built from the fork and recorded) moves to the table above
    # by leaving this list.
    $notBuilt = @(
        @{ Path = 'Data\Platform\UI\build.js'; Folder = 'skymp5-front'; Licence = 'GNU GPL version 3'
           Says = @('build.js is SkyMP''s in-game interface. It loads fonts, pictures and',
                    'sounds that sit beside it in Data\Platform\UI.') },
        @{ Path = 'Data\Platform\Modules\skyrimPlatform.ts'; Folder = 'skyrim-platform'; Licence = 'GNU GPL version 3'
           Says = @('skyrimPlatform.ts is Skyrim Platform''s type declarations.') },
        @{ Path = 'Data\Scripts\MpClientPlugin.pex'; Folder = 'client-deps'; Licence = 'no LICENSE file in that folder'
           Says = @('MpClientPlugin.pex is a compiled Papyrus script from SkyMP''s client-deps',
                    'folder, which keeps no source for it.') }
    )
    $recorded = @($c.files.PSObject.Properties.Name)
    $extra = @()
    $says = @()
    if ($PayloadDir) {
        foreach ($nb in $notBuilt) {
            if ($recorded -contains $nb.Path) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $PayloadDir $nb.Path))) { continue }
            $leaf = $nb.Path.Substring($nb.Path.LastIndexOf('\') + 1)
            $extra += ('  {0,-34}{1,-18}{2}' -f $leaf, $nb.Folder, $nb.Licence)
            $says += $nb.Says
        }
    }

    function Base([string]$b) {
        if ($b -match '^[0-9a-f]{7,40}$') { return ('SkyMP commit ' + $b) }
        return 'SkyMP, at a commit the build record does not name'
    }

    $lines = @(
        'THORNSWOOD: WHERE THE SOURCE CODE IS',
        '====================================',
        '',
        'SkyMP is free software, and Thornswood ships part of it. This installer put',
        'SkyMP files into your Skyrim folder, and the server you connect to runs on',
        'SkyMP as well. The files in the first list below, and the server''s engine,',
        'are built from Thornswood''s public copy of SkyMP, with Thornswood''s changes',
        'on top. Anybody can read it or download it, with no account.',
        '',
        'The files Thornswood built',
        ('  commit    ' + $c.forkCommit + ', branch ' + $c.forkBranch),
        ('  source    ' + $fork + '/tree/' + $c.forkCommit),
        ('  based on  ' + (Base ([string]$c.upstreamBase))),
        '',
        ('The server''s engine, ' + $bin),
        ('  commit    ' + $s.source.commit + ', branch ' + $s.source.branch),
        ('  source    ' + $sRepo + '/tree/' + $s.source.commit),
        ('  based on  ' + (Base ([string]$s.source.upstreamBase))),
        '',
        ('SkyMP itself is ' + $upstream),
        '',
        'Each file Thornswood built, the folder of SkyMP it is built from, and the',
        'licence in that folder''s LICENSE file:',
        ''
    ) + $table
    if ($extra.Count) {
        $lines += @(
            '',
            'SkyMP files this installer also carried that Thornswood did not build.',
            'Nobody recorded which version of SkyMP they came from, so no commit is',
            'named for them here. Their source is SkyMP''s own, at the address above.',
            'Each file, the folder of SkyMP it belongs to, and that folder''s licence:',
            ''
        ) + $extra + @('') + $says
    }
    $lines += @(
        '',
        'The full licence texts sit beside this note in the install folder:',
        '  GPL-3.0.txt             GNU GPL version 3 (skymp5-client, skyrim-platform)',
        '  AGPL-3.0.txt            GNU AGPL version 3 (MpClientPlugin.dll, the server)',
        '  WebView2-LICENSE.txt    Microsoft WebView2 SDK (inside the launcher)',
        '',
        'The launcher''s updates can bring newer builds of these files, so this note',
        'names the build this installer brought. https://thornswood.net/credits',
        'names the build in the current release.',
        ''
    )
    return ($lines -join "`r`n")
}
$srcNote = Join-Path $stage 'SOURCE CODE.txt'
try {
    $noteText = Get-SourceNotice $clientRecordPath (Join-Path $PSScriptRoot '..\..\records\server-build.json') $payloadDir
    [IO.File]::WriteAllText($srcNote, $noteText, (New-Object Text.UTF8Encoding($false)))
    Remove-Item -LiteralPath $clientRecordPath -Force -ErrorAction SilentlyContinue
    Say '  SOURCE CODE.txt names the fork commit this build came from' 'Green'
} catch {
    Die ("SOURCE CODE.txt could not be written: " + $_.Exception.Message + ". This installer carries SkyMP's GPL and AGPL files and has to say where their source is.")
}

# Full GPL / AGPL / WebView2 texts next to SOURCE CODE.txt (issue #421). Vendored
# under installer\licences from the recorded fork commit and THIRD-PARTY.md, so a
# machine without the engine submodule still ships the same bytes.
$licenceSrc = Join-Path $PSScriptRoot '..\..\installer\licences'
foreach ($lic in @('GPL-3.0.txt', 'AGPL-3.0.txt', 'WebView2-LICENSE.txt')) {
    $from = Join-Path $licenceSrc $lic
    if (-not (Test-Path -LiteralPath $from)) {
        Die ("installer\licences\$lic is missing. The installer has to hand the GPL, AGPL and WebView2 texts with the files (#421).")
    }
    Copy-Item -LiteralPath $from -Destination (Join-Path $stage $lic) -Force
}
Say '  GPL-3.0.txt, AGPL-3.0.txt and WebView2-LICENSE.txt staged beside SOURCE CODE.txt' 'Green'

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
# $vLive is the releases feed, found and checked before anything was staged.
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

# ---- nothing that must never ship ------------------------------------------
# Entry 236. This installer once carried the SkyMP client's saved sign in (see
# Ship-Rules.ps1). The stage is exactly what gets zipped, so it is read here,
# before -NoArchive hands the folder over and before the long compression: a
# credential by name or by shape, or a file Ship-Rules says never ships, stops
# the package. File, line and rule only, never the value. The stage of 23
# September, 813 files with the launcher and config.json, passes.
Head 'Checking for secrets'
& (Join-Path $here '..\dev\Check-Secrets.ps1') -Dir $stage
if ($LASTEXITCODE -ne 0) { Die 'Something that must never ship is in the staged installer. The lines above name each file and rule.' }

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
    Say '    .\scripts\release\Package-Thornswood.ps1 -ReuseStage -OutDir D:\Thornswood-dist' 'Green'
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

# The one checked above, before anything was staged.
$stub = $stubNow
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

# A signed stub cannot take the OneFile payload. Build-Launcher leaves the stub
# unsigned for that reason; strip here anyway so a hand-signed stub or an older
# out\setup-stub.exe does not break Package the way Main did on 27 September
# (signtool 0x800700C1 after attach). Sign-Artifact below signs the final Setup.
$preSig = Get-AuthenticodeSignature -LiteralPath $exe
if ($preSig -and $preSig.Status -ne 'NotSigned' -and $preSig.SignerCertificate) {
    $signtoolStrip = $null
    foreach ($kit in @(
        ${env:ProgramFiles(x86)} + '\Windows Kits\10\bin',
        ${env:ProgramFiles} + '\Windows Kits\10\bin'
    )) {
        if (-not (Test-Path -LiteralPath $kit)) { continue }
        $hit = Get-ChildItem -LiteralPath $kit -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit) { $signtoolStrip = $hit.FullName; break }
    }
    if ($signtoolStrip) {
        Say '  stub was signed; stripping so OneFile attach can be signed afterwards' 'DarkGray'
        # Its exit code decides: under Stop, 5.1 threw on signtool's stderr
        # before the Die below could say what failed.
        $was = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & $signtoolStrip remove /s $exe 2>&1 | Out-Null } finally { $ErrorActionPreference = $was }
        if ($LASTEXITCODE -ne 0) {
            Die 'could not strip the stub signature before attaching the payload'
        }
    } else {
        Die 'stub is signed and signtool was not found to strip it before OneFile attach'
    }
}

# ---- one file, payload attached -------------------------------------------
# TWSFX001, then the offset the payload starts at, then its length. Both are
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
        $bw.Write([Text.Encoding]::ASCII.GetBytes('TWSFX001'))
        $bw.Write([long]$off)
        $bw.Write([long]$len)
        $bw.Flush()
    } finally { $fsOut.Dispose() }
    Say ("  attached, offset {0:n0}, {1:n2} GB" -f $off, ($len / 1GB)) 'Green'
}

# ---- sign it, if this machine can -----------------------------------------
#
# After the payload is attached, not before. Bootstrap.cs:625-636 already
# expects this: the certificate lands on the end after the trailer, which is
# exactly why its loader scans backwards for TWSFX001 rather than reading a
# fixed offset from the end.
#
# Does nothing without records\signing\signing.json, so a machine with no certificate
# still produces a working, unsigned installer.
$signer = Join-Path $here 'Sign-Artifact.ps1'
if (Test-Path -LiteralPath $signer) {
    Head 'Signing the installer'
    & $signer -Path $exe
    if ($LASTEXITCODE -ne 0) {
        Say '  the installer could not be signed, so it is not fit to publish' 'Red'
        if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 1
    }
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
# These were still looking for the installer script and the launcher exe
# under their names from before the rename. The first of those had not
# existed for a long time, so the check failed on every run and reported a
# missing installer script while the installer itself was fine.
#
# The launcher check was worse, because it passed. Somewhere in 22 GB of
# game build there was a leftover exe of the old name, and a bare substring
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
        # -AllowStaleCheckout goes on with it (#2436): without it, a run that
        # had been let past the checkout check here was refused by the same
        # check inside Publish-Installer, after the build.
        $pubArgs = @{ OutDir = $OutDir }
        if ($OneFile) { $pubArgs['OneFile'] = $true }
        if ($AllowStaleCheckout) { $pubArgs['AllowStaleCheckout'] = $true }
        try {
            & $pub @pubArgs
        } catch {
            Say "  could not publish: $_" 'Yellow'
            Say '  The installer is still built and fine. Run' 'DarkGray'
            # The folder is named, because this line used to send somebody to
            # a bare command whose default pointed at a folder that no longer
            # exists. It reads the same -OutDir this run used, so it is right
            # even when somebody passed their own.
            Say ('  .\scripts\release\Publish-Installer.ps1 -OutDir "' + $OutDir + '"') 'DarkGray'
            Say '  when the VPS is reachable.' 'DarkGray'
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

# Said out loud rather than left to chance, the same as Build-Launcher.ps1.
#
# A PowerShell script that runs off the end does not reset $LASTEXITCODE: the
# caller sees whatever the last native command left behind, and this script
# runs 7z, winget and Publish-Installer. Ship.ps1 reads that code now to decide
# whether a release may go out, so a stray value here would either hide a
# failure or stop a good release for no reason. Every other way out of this
# script already exits deliberately.
exit 0
