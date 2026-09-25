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

  Read only. It creates nothing and prints nothing but the one path.

.PARAMETER What
  Which place: Repo, Engine, ServerDist, ClientDist, ServerSettings,
  ChangeForms, Out, Dist, Package, Payload or ServerZip.

.PARAMETER OldRoot
  The folder the old layout lived in. C:\Thornswood-Dev; tools\test-where.ps1
  points it somewhere else.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('Repo', 'Engine', 'ServerDist', 'ClientDist', 'ServerSettings', 'ChangeForms',
                 'Out', 'Dist', 'Package', 'Payload', 'ServerZip')]
    [string]$What,
    [string]$OldRoot = 'C:\Thornswood-Dev'
)

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here

# An uninitialised submodule is an empty folder, so the engine counts as moved
# only once the fork's own top level file is there.
function Get-Engine {
    $new = Join-Path $repo 'engine\skymp'
    $old = Join-Path $OldRoot 'skymp'
    if (Test-Path -LiteralPath (Join-Path $new 'CMakeLists.txt')) { return $new }
    if (Test-Path -LiteralPath $old) { return $old }
    return $new
}

function Get-Out {
    $new = Join-Path $repo 'out'
    if (Test-Path -LiteralPath $new) { return $new }
    if ((Test-Path -LiteralPath (Join-Path $OldRoot 'dist')) -or (Test-Path -LiteralPath (Join-Path $OldRoot '_payload'))) { return $OldRoot }
    return $new
}

switch ($What) {
    'Repo'           { $repo }
    'Engine'         { Get-Engine }
    'ServerDist'     { Join-Path (Get-Engine) 'build\dist\server' }
    'ClientDist'     { Join-Path (Get-Engine) 'build\dist\client' }
    'ServerSettings' { Join-Path (Get-Engine) 'build\dist\server\server-settings.json' }
    'ChangeForms'    { Join-Path (Get-Engine) 'build\dist\server\world\changeForms' }
    'Out'            { Get-Out }
    'Dist'           { Join-Path (Get-Out) 'dist' }
    'Package'        { Join-Path (Get-Out) 'dist\Thornswood\_dist' }
    'Payload'        { Join-Path (Get-Out) '_payload' }
    'ServerZip'      { Join-Path (Get-Out) 'thornswood-server.zip' }
}
