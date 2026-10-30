<#
  Ship-OnBox.ps1

  The deploy gate's Ship verbs (#2841): a Ship from the feed run on the box
  itself, from main as the gate reads it, so a cloud session ships with no key
  to the box (Patrick, 30 Oct 2026: "we arent doing this on One").

      pwsh scripts/vps/Box-Run.ps1 -Line 'Ship-Dev -Title "Market stalls take your own prices" -Detail "Claim a stall in a town market and sell at your prices"'
      pwsh scripts/vps/Box-Run.ps1 -Line 'Ship-Main -Build <main''s full commit> -Title "..." -Detail "..."'

  Ship-Dev is Ship.ps1 -Channel dev -FromFeed -ModsOnly. Ship-Main is
  Ship.ps1 -FromFeed, the main release, and the gate runs it only when main
  is at the commit -Build names (the build Patrick gave his word for); its
  -ModsOnly keeps the feed's launcher.

  WHAT IS DIFFERENT FROM ONE. Nothing in Ship.ps1. Its box steps
  (Publish-Update, Sync-Client, Publish-Installer, the feed store,
  announced.json) reach the box the way they do from One, as Administrator
  over ssh, here over loopback with the gate's own key. Two things only this
  script does:

    1. The notes. A gate line is one line of plain text, so the release note
       comes as -Title and up to three -Detail lines, which become the title
       and the "- " lines Ship.ps1 asks for.
    2. GitHub. A Ship from the feed signs its manifest in the engine fork
       (Sign-OnGitHub.ps1) and, with a new launcher, has release.yml build
       it, both through gh. The box admin App mints a token for this run
       alone (scripts\vps\admin\ship-access.js, Patrick's pick of 30 Oct:
       Actions write on the fork and Thornswood, Contents read on
       Thornswood), which goes to gh through GH_TOKEN and nowhere else, and
       GitHub ends after an hour. gh is the one Install-Gate.ps1 pinned
       beside the gate (C:\Thornswood-Gate\tools\gh).

  The release tag (release/<channel>/<id>) is pushed with git, and the gate's
  checkout reads GitHub with a read-only key, so Ship prints the tag as a
  line it could not push; the Desk puts it on with Set-Ref.ps1, as a cloud
  Ship's always has (#3314).
#>
[CmdletBinding()]
param(
    [ValidateSet('dev', 'main')]
    [string]$Channel = 'dev',
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$Detail,
    [string]$Detail2 = '',
    [string]$Detail3 = '',
    # Main only: keep the feed's launcher. A dev Ship from the gate always does.
    [switch]$ModsOnly,
    # Where the App's key and id are, for a harness.
    [string]$AdminState = 'C:\Thornswood-Admin\state'
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = (Resolve-Path -LiteralPath (Join-Path $Here '..\..')).ProviderPath
function Die($m) { Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

# The note, as Ship.ps1 reads it: the title line, then a "- " line for each detail.
$notes = (@($Title.Trim()) + @(@($Detail, $Detail2, $Detail3) | Where-Object { $_ -and $_.Trim() } | ForEach-Object { '- ' + $_.Trim() })) -join "`n"

# A main release ships from the branch main, level with origin/main: the gate
# checks main out detached, at the commit it fetched into origin/main.
if ($Channel -eq 'main') {
    $was = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = @(& git -C $repo checkout --quiet -B main refs/remotes/origin/main 2>&1 | ForEach-Object { "$_" })
    $ErrorActionPreference = $was
    if ($LASTEXITCODE -ne 0) { Die ('the checkout could not be put on main at origin/main: ' + ($o -join ' ') + ' Nothing was published.') }
}

$node = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $node) { Die 'there is no node on this machine to mint the App''s token with. Nothing was published.' }
$env:THORNSWOOD_ADMIN_STATE = $AdminState
$was = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$minted = @(& $node.Source (Join-Path $repo 'scripts\vps\admin\ship-access.js') 2>&1 | ForEach-Object { "$_" })
$ErrorActionPreference = $was
$token = @($minted | Where-Object { $_ -match '^gh[sp]_[A-Za-z0-9_]{20,}$' }) | Select-Object -First 1
if ($LASTEXITCODE -ne 0 -or -not $token) { Die ('the box admin App gave no token for the Ship: ' + ((@($minted | Where-Object { $_ -notmatch '^gh[sp]_' })) -join ' ') + ' Nothing was published.') }
$minted = $null

$ship = @{ Notes = $notes; FromFeed = $true; NoPause = $true }
if ($Channel -eq 'dev') { $ship['Channel'] = 'dev'; $ship['ModsOnly'] = $true }
elseif ($ModsOnly) { $ship['ModsOnly'] = $true }
$env:GH_TOKEN = $token
$token = $null
try {
    & (Join-Path $Here 'Ship.ps1') @ship
    $code = $LASTEXITCODE
}
finally { Remove-Item -LiteralPath Env:\GH_TOKEN -ErrorAction SilentlyContinue }
exit $code
