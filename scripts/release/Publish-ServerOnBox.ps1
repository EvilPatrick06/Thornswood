<#
  Publish-ServerOnBox.ps1

  The deploy gate's Publish-Server and Publish-Server-Main verbs (#2841): the
  pin's server build published from the box's store, run on the box itself
  from main as the gate reads it.

      pwsh scripts/vps/Box-Run.ps1 -Line 'Publish-Server'
      pwsh scripts/vps/Box-Run.ps1 -Line 'Publish-Server-Main -Build <main''s full commit>'

  WHY. A pin move needs the new server build in the store before -FromStore
  can publish it (engine\README.md, step 5), and on One the first publish of
  a pin sends it there: Publish-Server.ps1 fetches CI's engine build of the
  pin and sends its server zip first, but only on a machine that records CI's
  build as its own and only when -FromStore was not given ($CiFromStore).
  The gate fixed -FromStore, so on 31 Oct 2026 a cloud publish of 09a4b398 to
  dev would have stopped with the store not holding it. This does what that
  first publish does, with nothing of One's: Get-EngineArtifact.ps1 fetches
  CI's build of the pin held to the records, and Publish-Server.ps1
  -FromStore -ServerBuild sends its zip to the store, held to the record
  again, before it publishes. When the store already holds the zip, the send
  is the same bytes.

  Get-EngineArtifact.ps1 reads the engine fork's artifacts through gh, with
  the box admin App's token for this run alone (ShipAccess.ps1), in GH_TOKEN
  and removed after.

  -PutBack and -TaskOnly publish no build, so they go to Publish-Server.ps1
  as they are, with nothing fetched and no -FromStore, which it refuses with
  them.
#>
[CmdletBinding()]
param(
    [ValidateSet('dev', 'main')]
    [string]$Channel = 'dev',
    [ValidateSet('', 'on', 'off')][string]$RequirePass = '',
    [int]$Wait = 0,
    [switch]$PutBack,
    [switch]$TaskOnly,
    # Where the App's key and id are, for a harness.
    [string]$AdminState = 'C:\Thornswood-Admin\state'
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = (Resolve-Path -LiteralPath (Join-Path $Here '..\..')).ProviderPath
function Die($m) { Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }
. (Join-Path $Here 'Read-JsonFile.ps1')

$pub = @{ Channel = $Channel; NoPause = $true }
if ($RequirePass) { $pub['RequirePass'] = $RequirePass }
if ($Wait) { $pub['Wait'] = $Wait }
if ($PutBack) { $pub['PutBack'] = $true }
if ($TaskOnly) { $pub['TaskOnly'] = $true }

if (-not $PutBack -and -not $TaskOnly) {
    . (Join-Path $repo 'scripts\vps\admin\ShipAccess.ps1')
    try { $token = Get-ThornswoodShipAccess -Repo $repo -AdminState $AdminState }
    catch { Die ('the box admin App gave no token to fetch CI''s engine build with: ' + $_.Exception.Message + ' Nothing was sent.') }
    $env:GH_TOKEN = $token
    $token = $null
    try {
        $global:LASTEXITCODE = 0
        & (Join-Path $Here 'Get-EngineArtifact.ps1') -NoPause
        $got = $LASTEXITCODE
    }
    finally { Remove-Item -LiteralPath Env:\GH_TOKEN -ErrorAction SilentlyContinue }
    if ($got -ne 0) { Die "Get-EngineArtifact.ps1 could not fetch CI's engine build of the pin (exit $got); its lines above say why. Nothing was sent." }

    # The zip, as Publish-Server.ps1 finds it on a machine that takes CI's build.
    $ciDir = & (Join-Path $Here 'Where.ps1') EngineArtifact
    $ciStamp = Join-Path $ciDir 'engine-artifact.json'
    $ciInfo = ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText($ciStamp)) $ciStamp
    $ciZipName = if ($ciInfo.PSObject.Properties['serverZip']) { [string]$ciInfo.serverZip } else { '' }
    $ciZip = Join-Path (Join-Path (Join-Path $ciDir 'artifact') 'server') $ciZipName
    if (-not $ciZipName -or -not (Test-Path -LiteralPath $ciZip -PathType Leaf)) {
        Die ("$ciStamp names " + $(if ($ciZipName) { $ciZipName } else { 'no server zip' }) + ", and there is none at $ciZip, so CI's server build is not here to send. Nothing was sent.")
    }
    $pub['FromStore'] = $true
    $pub['ServerBuild'] = $ciZip
}

& (Join-Path $Here 'Publish-Server.ps1') @pub
exit $LASTEXITCODE
