<#
.SYNOPSIS
  Fetches CI's engine build of the pin (engine.yml's artifact), holds every
  file in it to records\client-build.json and records\server-build.json, and
  makes it this machine's engine build.

.DESCRIPTION
  Issue #3047. A rebuild is never the same bytes (engine\README.md,
  "Rebuilding the same commit"), so the only client and server that match a
  record CI made are the ones in CI's artifact, engine-<fork commit 12>. This
  takes that artifact for the commit this checkout pins and puts it, held to
  the records, at Where.ps1 EngineArtifact, a folder of this machine's own
  data named for the commit. A machine that records {"ci": true} as its
  engine build (Setup-ShipMachine.ps1 -EngineBuild ci) reads ClientDist and
  ServerDist there, so a pin move needs a fetch here and no engine build.
  EngineArtifact.ps1 says which artifact is taken and what is held.

  Sync-Client.ps1 runs this when it needs the client from that folder and the
  folder is not there yet, so a Ship and Go do not need it run by hand.

  It reads GitHub through gh, signed in as somebody who can read this
  repository's Actions, and writes nothing but the folder and its own scratch
  under the repository's temp folder, which it removes. It sends nothing,
  starts nothing and never builds the engine.

  Exit 0: CI's build of the pin is this machine's EngineArtifact (it was
  there, or it is now). 2: -Check, and it is on GitHub to fetch. 1: it is not
  there and cannot be, and the last line says why.

.PARAMETER Check
  Says whether the folder is there and whether GitHub keeps the artifact.
  Nothing is fetched or written.

.PARAMETER Gh
  The gh to run, for a harness. gh on the path otherwise.

.PARAMETER NoPause
  Exits without waiting for Enter.

.EXAMPLE
  .\scripts\release\Get-EngineArtifact.ps1
  Fetches engine-<pin 12> and makes it this machine's CI engine build.

.EXAMPLE
  .\scripts\release\Get-EngineArtifact.ps1 -Check
  Says whether it is here already, or on GitHub to fetch.
#>
[CmdletBinding()]
param(
  [switch]$Check,
  [string]$Gh = 'gh',
  [switch]$NoPause
)
$ErrorActionPreference = 'Stop'   # before any file loads, so one that is missing stops here (#3006)
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'EngineArtifact.ps1')
$RepoDir = Split-Path -Parent (Split-Path -Parent $Here)

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Stop-Here($m) {
  Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}

try { $commit = Get-EngineArtifactPin $RepoDir } catch { Stop-Here $_.Exception.Message }
$name = Get-EngineArtifactName $commit
$into = [string](& (Join-Path $PSScriptRoot 'Where.ps1') EngineArtifact)
Say ("CI's engine build of {0} ({1}), for {2}" -f $commit.Substring(0, 12), $name, $into) 'Cyan'

if (Test-Path -LiteralPath $into) {
  $why = @(Get-EngineArtifactFolderProblems $into $RepoDir)
  if ($why.Count) { Stop-Here ("$into is there and is not CI's build of what this checkout records: " + ($why -join '; ') + ". Nothing else writes into it, so somebody did: remove the folder, then run this again.") }
  $stamp = [IO.File]::ReadAllText((Join-Path $into 'engine-artifact.json')) | ConvertFrom-Json
  Say ("  here already, from {0} (run {1}), every client file as recorded" -f $stamp.artifact, $stamp.runId) 'Green'
  exit 0
}

# gh api through the gh this was given. Its error is the answer, not "none".
if (-not (Get-Command $Gh -ErrorAction SilentlyContinue)) { Stop-Here "gh is not here. winget install --id GitHub.cli -e, then gh auth login (an account that is a collaborator on $EngineArtifactRepo)." }
function Invoke-Gh([string[]]$GhArgs) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = @(& $Gh @GhArgs 2>&1); $code = $LASTEXITCODE } finally { $ErrorActionPreference = $old }
  $text = ($out | ForEach-Object { [string]$_ }) -join "`n"
  if ($code -ne 0) { throw ("gh " + ($GhArgs -join ' ') + " exited $code" + $(if ($text) { ': ' + $text } else { '' })) }
  return $text
}
$get = { param($path) (Invoke-Gh @('api', $path)) | ConvertFrom-Json }
try { $f = Find-EngineArtifact $commit $get } catch { Stop-Here ('GitHub could not be asked which artifact engine.yml keeps: ' + $_.Exception.Message) }
Say ('  ' + $f.Why) $(if ($f.State -eq 'found') { 'Gray' } else { 'Yellow' })
if ($f.State -ne 'found') { Stop-Here $f.Why }
if ($Check) {
  Say ("  not here yet; {0} fetches it ({1:N0} bytes)" -f 'Get-EngineArtifact.ps1', [long]$f.Artifact.size_in_bytes) 'Yellow'
  exit 2
}

$scratch = [string](& (Join-Path $PSScriptRoot 'Get-ScratchDir.ps1') ('Thornswood-engine-artifact-' + [Guid]::NewGuid().ToString('N')))
try {
  $null = New-Item -ItemType Directory -Force -Path $scratch
  $dl = Join-Path $scratch $name
  try { $null = Invoke-Gh @('run', 'download', [string]$f.Run.id, '--name', $name, '--dir', $dl, '--repo', $EngineArtifactRepo) }
  catch { Stop-Here ("$name could not be fetched: " + $_.Exception.Message) }
  try { $stamp = Install-EngineArtifact -From $dl -Repo $RepoDir -Into $into -Run $f.Run -Artifact $f.Artifact }
  catch { Stop-Here $_.Exception.Message }
} finally {
  if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
}
Say ("  every file held to the records; {0} is this checkout's CI engine build (server {1})" -f $into, $stamp.serverZip) 'Green'
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
exit 0
