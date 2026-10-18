<#
  Where.ps1

      & (Join-Path $PSScriptRoot 'Where.ps1') ServerDist

  Says where the engine fork and the build output are, so every script asks
  one place instead of carrying its own copy of a path.

  WHY IT EXISTS. Until 25 September the fork, its build and everything a release
  is built into sat outside the repository, in a folder on Patrick's machine
  that about thirty scripts named by hand. Nothing in it was on GitHub but the
  fork's source, and Djinn's machine had none of it. Patrick asked for it all
  to live in the repository ("so I dont have all these extra folder and so it
  is backed up by github and my other devs can do more stuff"), and Djinn
  agreed:

      engine\skymp   the fork, a git submodule of this repository, pinned to the
                     commit the build records name
      out            the build output: dist (packs, the launcher, the
                     installer), _payload and thornswood-server.zip. Ignored
                     by git; a release is what keeps them

  NO OLD PLACES. Until 28 September this also answered with the old folder
  while a machine still had it, and with the old tools\ paths from before the
  reorganisation (issue #440). No machine has either any more, so both went:
  the answer is always the place in the repository, whether or not it exists
  yet (an engine not fetched is an empty engine\skymp, and a script that needs
  it says so).

  LAYOUT. layout.json at the repository root holds the places; where.js
  beside this reads the same file.

  LOCAL AND BACKUPS, 5 October. Local is the repository's local folder,
  ignored by git, the settled design's home for anything a machine keeps that
  never goes to GitHub. Backups is local\backups, where Backup-Server.ps1 and
  Fetch-Backups.ps1 put what they bring off the VPS and Clean-Everything.ps1
  looks for old ones. Patrick's rule that day: Thornswood work on One lives
  only in the repository, the vault and C:\ThornswoodTemps&Worktrees, and the
  backups were the last of it in Downloads\Thornswood-Backups. A worktree has
  a local folder of its own that goes with it, so the scripts that write
  backups stop when this answer is inside a worktree rather than leave the
  only copy there.

  THE FOLDER A RELEASE IS BUILT FROM, issue #1692. ShipRoot and ShipRootDev
  are the Thornswood install a main and a dev release are built from on this
  machine, which Ship.ps1, Check-ShipReady.ps1, Setup-ShipMachine.ps1 and
  Build-Generated.ps1 each worked out for themselves until 5 October, by the
  same rule copied four times: the launcher install (C:\Thornswood, or
  Thornswood on the first other fixed drive with Launcher\Thornswood.exe in
  it), and for dev that with -DevBuild on the end, where the main launcher's
  Settings page installs the dev build. A machine where Vortex deploys into
  that dev folder (docs\COLLECTION-REVISION-2.md step 8) builds its dev
  release in another one, and nothing knew which: on 4 October a dev Ship
  from a clean worktree took Vortex's folder, built and installed the
  launcher there and then stopped at its generated files. ShipRoots is the
  file in this machine's own data (not in the repository, so every clone and
  worktree reads it) that names the folder for a channel, as
  {"dev": "C:\\Users\\you\\Downloads\\Thornswood-Repo\\local\\release-devbuild"}
  on One since 5 October; Setup-ShipMachine.ps1 -Root writes it. A channel
  it does not name is the rule above. These three are this machine's, and
  only the PowerShell release scripts ask, so where.js does not answer them.

  WHO NAMED THE FOLDER, issue #2662. ShipRootNamed and ShipRootNamedDev
  answer only what ShipRoots names for the channel, and '' when it names
  none, so a script can tell a recorded folder from the install rule's
  answer, which ShipRoot and ShipRootDev give as one string. A dev Ship asks:
  the install rule's <install>-DevBuild with no Launcher folder means the
  main launcher never installed the dev build there, and Ship refuses it; a
  recorded folder is made by Update-ShipRoot.ps1, which writes no Launcher
  folder, and the Ship's own launcher step makes one, so it is not refused.

  THE ENGINE BUILD, issue #2019. engine\README.md "One engine": there is one
  engine, and an engine change is built in a worktree of the fork
  (Build-Engine.ps1 -Fork, Build-Server.ps1 -Fork), not in a checkout's
  engine\skymp. Until 16 October ServerDist, ClientDist, ServerSettings and
  ChangeForms were always under the checkout's own engine\skymp\build, so
  each clone and worktree read whatever its own folder last built: on
  15 October a dev Ship from a worktree read that worktree's 12 October
  client and refused against the 0714e444 record, and the dev deploys needed
  -Dist pointed at the right folder by hand (#2309). EngineBuild is the fork
  folder this machine records as its engine build, in the file EngineBuilds
  names ({"fork": "<folder>"}, this machine's own data like ShipRoots,
  written by Setup-ShipMachine.ps1 -EngineBuild), and those four places are
  under it. A machine that records none builds in its checkout
  (engine\README.md "Building it on your machine"), and EngineBuild is then
  Engine. A record naming a folder with no build in it stops with a sentence
  and never falls back to another folder. where.js answers EngineBuild the
  same way, so both read one engine build.

  Read only. It creates nothing and prints nothing but the one path.

.PARAMETER What
  Which place: Repo, Engine, EngineBuild, EngineBuilds, ServerDist,
  ClientDist, ServerSettings, ChangeForms, Out, Dist, Package, Payload,
  ServerZip, Local, Backups, Releases, ReleasesDev, ShipRoot, ShipRootDev,
  ShipRoots, ShipRootNamed or ShipRootNamedDev; or a top folder
  from layout.json (docs, bot, voice, site, tests, game, launcher,
  installer, records, scripts).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$What
)

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent (Split-Path -Parent $here)

$layoutPath = Join-Path $repo 'layout.json'
if (-not (Test-Path -LiteralPath $layoutPath)) {
    throw "layout.json is not at $layoutPath. It is in the repository, so the path is wrong."
}
$layoutText = "$(Get-Content -LiteralPath $layoutPath -Raw -Encoding UTF8)"
if (-not $layoutText.Trim([char]0xFEFF, ' ', [char]9, [char]13, [char]10)) { throw "layout.json at $layoutPath is empty." }
try { $layout = $layoutText.TrimStart([char]0xFEFF) | ConvertFrom-Json } catch { throw ("layout.json at $layoutPath is not valid JSON: " + $_.Exception.Message) }

function Join-Under([string]$root, [string]$rel) {
    if (-not $rel) { return $root }
    $parts = $rel -split '[\\/]+' | Where-Object { $_ -and $_ -ne '.' }
    $p = $root
    foreach ($part in $parts) { $p = Join-Path $p $part }
    return $p
}

# Looked up by name rather than read as $layout.places.$name. Ship.ps1 runs
# with Set-StrictMode -Version Latest, and a script it calls runs under it too,
# where reading a property an object does not have throws. Every Ship once
# stopped at Sync-Client on "The property 'ClientDist' cannot be found on this
# object" that way.
function Get-Named($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $prop = $obj.PSObject.Properties[$name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

# The launcher install: C:\Thornswood, or Thornswood on the first other fixed
# drive that has Launcher\Thornswood.exe in it, else C:\Thornswood. The first
# is asked as a plain string, so a machine with no C: drive (a harness off
# Windows) gets an answer rather than an error from Join-Path.
function Find-InstallRoot {
    $first = 'C:\Thornswood'
    if (Test-Path -LiteralPath ($first + '\Launcher\Thornswood.exe')) { return $first }
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
        $cand = Join-Path $d.Root 'Thornswood'
        if (Test-Path -LiteralPath (Join-Path $cand 'Launcher\Thornswood.exe')) { return $cand }
    }
    return $first
}

# The folder ShipRoots names for $channel, or '' when it names none (#2662,
# see the header): what Setup-ShipMachine.ps1 -Root recorded, and nothing
# the install rule would answer. Get-ShipRoot asks this first.
function Get-NamedShipRoot([string]$channel) {
    $file = Get-Place 'ShipRoots'
    if (-not (Test-Path -LiteralPath $file)) { return '' }
    $rec = $null
    try { $rec = [IO.File]::ReadAllText($file) | ConvertFrom-Json }
    catch { throw "$file does not read as JSON, so which folder a release is built from here is not known. Fix it, or write it again with .\scripts\release\Setup-ShipMachine.ps1 -Channel $channel -Root <folder>." }
    return [string](Get-Named $rec $channel)
}

# The folder a release on $channel is built from on this machine (#1692, see
# the header): what ShipRoots names for it, or the install rule.
function Get-ShipRoot([string]$channel) {
    $named = Get-NamedShipRoot $channel
    if ($named) { return $named }
    $root = Find-InstallRoot
    if ($channel -eq 'dev') { return ($root + '-DevBuild') }
    return $root
}

# The fork folder whose build\dist is this machine's engine build (#2019, see
# the header): what EngineBuilds records, or the checkout's own engine.
function Get-EngineBuild {
    $file = Get-Place 'EngineBuilds'
    if (-not (Test-Path -LiteralPath $file)) { return (Get-Place 'Engine') }
    $rec = $null
    try { $rec = [IO.File]::ReadAllText($file) | ConvertFrom-Json }
    catch { throw "$file does not read as JSON, so which engine build this machine uses is not known. Write it again with .\scripts\release\Setup-ShipMachine.ps1 -EngineBuild <the fork folder>." }
    $fork = [string](Get-Named $rec 'fork')
    if (-not $fork) { throw "$file names no fork folder. Write it again with .\scripts\release\Setup-ShipMachine.ps1 -EngineBuild <the fork folder>." }
    if (-not (Test-Path -LiteralPath (Join-Path $fork 'build\dist'))) {
        throw ("$file names $fork as this machine's engine build, and there is no build\dist in it, so there is no engine build to read. " +
               "Build it there (engine\README.md, One engine), or record the fork folder that has it: .\scripts\release\Setup-ShipMachine.ps1 -EngineBuild <the fork folder>.")
    }
    return $fork
}

function Get-Place([string]$name) {
    switch ($name) {
        'Repo'   { return $repo }
        # This machine's working copies of the feeds (Feed-Store.ps1, #907),
        # not clones of Thornswood-Releases beside the repository any more.
        'Releases'    { return Join-Path $env:LOCALAPPDATA 'Thornswood\feed\main' }
        'ReleasesDev' { return Join-Path $env:LOCALAPPDATA 'Thornswood\feed\dev' }
        # The folder a release is built from here, and the file that names it (#1692).
        'ShipRoots'   { return Join-Path $env:LOCALAPPDATA 'Thornswood\ship-roots.json' }
        'ShipRoot'    { return Get-ShipRoot 'main' }
        'ShipRootDev' { return Get-ShipRoot 'dev' }
        # Only what ShipRoots names, '' for the install rule (#2662).
        'ShipRootNamed'    { return Get-NamedShipRoot 'main' }
        'ShipRootNamedDev' { return Get-NamedShipRoot 'dev' }
        # This machine's engine build, and the file that names it (#2019).
        'EngineBuilds' { return Join-Path $env:LOCALAPPDATA 'Thornswood\engine-build.json' }
        'EngineBuild'  { return Get-EngineBuild }
    }
    $place = Get-Named $layout.places $name
    if ($null -ne $place) { return Join-Under $repo ([string]$place) }
    $der = Get-Named $layout.derived $name
    if ($null -ne $der) {
        $base = Get-Place ([string]$der.from)
        return Join-Under $base ([string]$der.join)
    }
    return $null
}

$placeNames = @('Repo', 'Engine', 'EngineBuild', 'EngineBuilds', 'ServerDist', 'ClientDist', 'ServerSettings', 'ChangeForms',
                'Out', 'Dist', 'Package', 'Payload', 'ServerZip', 'Local', 'Backups', 'Releases', 'ReleasesDev',
                'ShipRoot', 'ShipRootDev', 'ShipRoots', 'ShipRootNamed', 'ShipRootNamedDev')
$folderNames = @($layout.folders.PSObject.Properties.Name)

if ($placeNames -contains $What) {
    Get-Place $What
}
elseif ($folderNames -contains $What) {
    Join-Under $repo ([string](Get-Named $layout.folders $What))
}
else {
    $known = ($placeNames + $folderNames) -join ', '
    throw "Where.ps1 does not know '$What'. Known: $known"
}
