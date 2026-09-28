<#
  Where.ps1

      & (Join-Path $PSScriptRoot 'Where.ps1') ServerDist

  Says where the engine fork and the build output are on this machine, so every
  script asks one place instead of carrying its own copy of a path.

  WHY IT EXISTS. Until 25 September the fork, its build and everything a release
  is built into sat outside the repository, in C:\Thornswood-Dev on Patrick's
  machine, and about thirty scripts named that folder by hand. Nothing in it was
  on GitHub but the fork's source, and Djinn's machine had none of it. Patrick
  asked for it all to live in the repository ("so I dont have all these extra
  folder and so it is backed up by github and my other devs can do more
  stuff"), and Djinn agreed:

      engine\skymp   the fork, a git submodule of this repository, pinned to the
                     commit the build records name
      out            the build output: dist (packs, the launcher, the
                     installer), _payload and thornswood-server.zip. Ignored
                     by git; a release is what keeps them

  THE OLD PLACE STILL WORKS, for as long as a machine has it, so a script never
  points at a folder that is not there halfway through the move. The engine is
  read from engine\skymp once the submodule has files in it, and from
  C:\Thornswood-Dev\skymp until then. The output goes to out once that folder
  exists, to C:\Thornswood-Dev while its dist or _payload does, and to out
  otherwise. A machine that never had C:\Thornswood-Dev, Djinn's, gets the new
  places from the start.

  LAYOUT. layout.json at the repository root holds the new and old places, and
  the map of old tools\ paths to the folders after the reorganisation (issue
  #440, phase 0). This script and where.js beside it both read that file and
  prefer the new place when it is present. A Move name (bot, voice, site, ...)
  resolves the same way: new folder first, then the old tools\ path.

  Read only. It creates nothing and prints nothing but the one path.

.PARAMETER What
  Which place: Repo, Engine, ServerDist, ClientDist, ServerSettings,
  ChangeForms, Out, Dist, Package, Payload, ServerZip, Releases or ReleasesDev;
  or a move name from layout.json (docs, bot, voice, site, tests, game,
  launcher, installer, records, scripts).

.PARAMETER OldRoot
  The folder the old layout lived in. C:\Thornswood-Dev; tests\test-where.ps1
  points it somewhere else.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$What,
    [string]$OldRoot = ''
)

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent (Split-Path -Parent $here)

$layoutPath = Join-Path $repo 'layout.json'
if (-not (Test-Path -LiteralPath $layoutPath)) {
    throw "layout.json is not at $layoutPath. It is in the repository, so the path is wrong."
}
$layout = Get-Content -LiteralPath $layoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $OldRoot) { $OldRoot = [string]$layout.oldRootDefault }
if (-not $OldRoot) { $OldRoot = 'C:\Thornswood-Dev' }

function Join-Repo([string]$rel) {
    if (-not $rel) { return $repo }
    $parts = $rel -split '[\\/]+' | Where-Object { $_ -and $_ -ne '.' }
    $p = $repo
    foreach ($part in $parts) { $p = Join-Path $p $part }
    return $p
}

function Join-Under([string]$root, [string]$rel) {
    if (-not $rel) { return $root }
    $parts = $rel -split '[\\/]+' | Where-Object { $_ -and $_ -ne '.' }
    $p = $root
    foreach ($part in $parts) { $p = Join-Path $p $part }
    return $p
}

# An uninitialised submodule is an empty folder, so the engine counts as moved
# only once the fork's own top level file is there.
function Get-Engine {
    $spec = $layout.places.Engine
    $new = Join-Repo ([string]$spec.new)
    $old = Join-Under $OldRoot ([string]$spec.oldUnderRoot)
    $probe = [string]$spec.presentWhen
    if ($probe -and (Test-Path -LiteralPath (Join-Path $new $probe))) { return $new }
    if (Test-Path -LiteralPath $old) { return $old }
    return $new
}

function Get-Out {
    $spec = $layout.places.Out
    $new = Join-Repo ([string]$spec.new)
    if (Test-Path -LiteralPath $new) { return $new }
    $any = @($spec.oldPresentWhenAny)
    foreach ($name in $any) {
        if (Test-Path -LiteralPath (Join-Path $OldRoot $name)) { return $OldRoot }
    }
    return $new
}

function Get-Place([string]$name) {
    switch ($name) {
        'Repo'   { return $repo }
        'Engine' { return Get-Engine }
        'Out'    { return Get-Out }
    }
    # Looked up by name rather than read as $layout.siblings.$name. Ship.ps1
    # runs with Set-StrictMode -Version Latest, and a script it calls runs
    # under it too, where reading a property an object does not have throws.
    # ClientDist is not a sibling, so every Ship stopped at Sync-Client on
    # "The property 'ClientDist' cannot be found on this object".
    $sib = $layout.siblings.PSObject.Properties[$name]
    if ($null -ne $sib) {
        return Join-Path (Split-Path -Parent $repo) ([string]$sib.Value)
    }
    $der = $layout.derived.PSObject.Properties[$name]
    if ($null -ne $der) {
        $base = Get-Place ([string]$der.Value.from)
        return Join-Under $base ([string]$der.Value.join)
    }
    return $null
}

function Get-Move([string]$name) {
    $m = $layout.moves.$name
    if ($null -eq $m) { return $null }
    $new = Join-Repo ([string]$m.new)
    $old = Join-Repo ([string]$m.old)
    if (Test-Path -LiteralPath $new) { return $new }
    if (Test-Path -LiteralPath $old) { return $old }
    return $new
}

$placeNames = @('Repo', 'Engine', 'ServerDist', 'ClientDist', 'ServerSettings', 'ChangeForms',
                'Out', 'Dist', 'Package', 'Payload', 'ServerZip', 'Releases', 'ReleasesDev')
$moveNames = @($layout.moves.PSObject.Properties.Name)

if ($placeNames -contains $What) {
    Get-Place $What
}
elseif ($moveNames -contains $What) {
    Get-Move $What
}
else {
    $known = ($placeNames + $moveNames) -join ', '
    throw "Where.ps1 does not know '$What'. Known: $known"
}
