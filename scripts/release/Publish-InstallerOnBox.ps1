<#
  Publish-InstallerOnBox.ps1

  The deploy gate's Publish-Installer verb (#5109, #2841): the site's
  installer rebuilt for main's newest release and put on the Downloads page,
  run on the box itself from main as the gate reads it, so a cloud session
  does it with no key to the box.

      pwsh scripts/vps/Box-Run.ps1 -Line 'Publish-Installer'

  WHY. A main Ship refuses while the site's installer is more than a release
  behind, and a Ship from the gate whose installer step stopped (31 Oct 2026:
  installer.yml was refused the release environment, fixed in #5105) leaves
  it behind. Publish-InstallerFromGitHub.ps1 rebuilds it from any machine,
  but its last step, Publish-Installer.ps1, reaches the site's files over
  ssh, and a cloud session's way in is the box bridge, which lets nobody in
  without a box token (measured 31 Oct: "no token was sent, and the bridge
  lets nobody in without one (401)"). Here it runs on the box, and
  Publish-Installer.ps1 reaches the site over loopback with the gate's own
  key, the way a Ship from the gate's box steps do (Ship-OnBox.ps1).

  WHAT IT RUNS. Publish-InstallerFromGitHub.ps1 as it is: installer.yml on
  main builds and signs the installer from main's feed and a second GitHub
  runner checks it; the installer and its note come from that run's own
  files; the release it carries has to be the one main's feed names now; and
  Publish-Installer.ps1 holds it to the publish gate on this machine before
  it replaces the one people download. It reaches GitHub through gh with the
  box admin App's token for this run alone (ShipAccess.ps1: Actions write,
  Contents read), in GH_TOKEN and removed after. The checkout is put on the
  branch main at origin/main first, the branch Publish-Installer.ps1's
  fresh-checkout rule asks of a live release, as Ship-OnBox.ps1 does for a
  main Ship.

  EXITS. 0 when the installer is on the site; 1 with STOP and why otherwise.
  tests\test-2841-deploy-gate.ps1 holds the verb and this script;
  tests\test-3412-installer-on-github.ps1 holds taking the run's files.
#>
[CmdletBinding()]
param(
    # Bounds the wait for the installer.yml run, in seconds, inside the
    # verb's own timeout.
    [int]$WaitSeconds = 1800,
    # Where the App's key and id are, for a harness.
    [string]$AdminState = 'C:\Thornswood-Admin\state'
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = (Resolve-Path -LiteralPath (Join-Path $Here '..\..')).ProviderPath
function Die($m) { Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

# The branch main, level with origin/main: the gate checks main out detached.
$was = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$o = @(& git -C $repo checkout --quiet -B main refs/remotes/origin/main 2>&1 | ForEach-Object { "$_" })
$ErrorActionPreference = $was
if ($LASTEXITCODE -ne 0) { Die ('the checkout could not be put on main at origin/main: ' + ($o -join ' ') + ' Nothing was published.') }

. (Join-Path $repo 'scripts\vps\admin\ShipAccess.ps1')
try { $token = Get-ThornswoodShipAccess -Repo $repo -AdminState $AdminState }
catch { Die ('the box admin App gave no token for the installer: ' + $_.Exception.Message + ' Nothing was published.') }

$env:GH_TOKEN = $token
$token = $null
$code = 0
try {
    & (Join-Path $Here 'Publish-InstallerFromGitHub.ps1') -WaitSeconds $WaitSeconds
}
catch {
    Write-Host ('STOP. ' + $_.Exception.Message) -ForegroundColor Red
    $code = 1
}
finally { Remove-Item -LiteralPath Env:\GH_TOKEN -ErrorAction SilentlyContinue }
exit $code
