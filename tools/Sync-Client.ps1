<#
.SYNOPSIS
  Puts the client runtime built from the fork into the game folder, and
  refuses any file that is not the recorded build.

.DESCRIPTION
  The six files in tools\client-build.json are the SkyMP client Thornswood
  ships: the bundle, MpClientPlugin.dll, both SkyrimPlatform DLLs, the CEF host
  and TESModPlatform.pex. New-ClientBuildRecord.ps1 writes that record after a
  rebuild; this copies the files it names from the fork's build output into
  the game folder, from where the next Ship packs them and the next
  Package-Thornswood puts them in the installer.

  Every file is hashed before it is copied and compared against the record.
  A mismatch stops the whole run with both hashes printed, because a runtime
  that is not the recorded one is either stale, or somebody else's, and until
  20 September it was the second: another server's launcher had written its
  own client into the Steam copy and the folder build copied it across.

  Nothing here talks to the VPS, starts anything, or touches the Steam copy.

.PARAMETER Check
  Compare and report only. Nothing is copied.

.PARAMETER Game
  The game folder. Defaults to Thornswood's own.

.EXAMPLE
  .\tools\Sync-Client.ps1 -Check
  Says which of the six are already in place, which differ, and whether the
  build matches the record.

.EXAMPLE
  .\tools\Sync-Client.ps1
  Copies the recorded build in. Go.ps1 runs this.
#>
[CmdletBinding()]
param(
  [string]$Dist = 'C:\Thornswood-Dev\skymp\build\dist\client',
  [string]$Game = 'C:\Thornswood\Game',
  [string]$Record,
  [switch]$Check,
  [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
if (-not $Record) { $Record = Join-Path $PSScriptRoot 'client-build.json' }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Stop-Here($m) {
  Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}
function Sha256([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

if (-not (Test-Path -LiteralPath $Record)) { Stop-Here "no record at $Record. Run .\tools\New-ClientBuildRecord.ps1 after building the client." }
if (-not (Test-Path -LiteralPath $Dist))   { Stop-Here "client build not found: $Dist" }
if (-not (Test-Path -LiteralPath $Game))   { Stop-Here "game folder not found: $Game" }

$rec = Get-Content -LiteralPath $Record -Raw | ConvertFrom-Json
$files = @($rec.files.PSObject.Properties.Name)
if (-not $files.Count) { Stop-Here 'the record names no files' }

Say ("client build {0} on {1}, recorded {2}" -f $rec.forkCommit, $rec.forkBranch, $rec.recordedUtc) 'Cyan'

# First pass: every file in the build must be the recorded one. Nothing is
# copied until all six pass, so a half synced folder is not a state this can
# leave behind.
$plan = @()
foreach ($rel in $files) {
  $want = $rec.files.$rel.sha256
  $src = Join-Path $Dist $rel
  if (-not (Test-Path -LiteralPath $src)) { Stop-Here "the build is missing $rel" }
  $have = Sha256 $src
  if ($have -ne $want) {
    Say "  $rel" 'Yellow'
    Say "    build    $have" 'Yellow'
    Say "    recorded $want" 'Yellow'
    Stop-Here 'the build is not the recorded one. Rebuild, then run .\tools\New-ClientBuildRecord.ps1, then this again.'
  }
  $dst = Join-Path $Game $rel
  $state = if (-not (Test-Path -LiteralPath $dst)) { 'absent' }
           elseif ((Sha256 $dst) -eq $want) { 'in place' }
           else { 'differs' }
  $plan += [pscustomobject]@{ Rel = $rel; Src = $src; Dst = $dst; State = $state; Bytes = (Get-Item -LiteralPath $src).Length }
}

$todo = @($plan | Where-Object { $_.State -ne 'in place' })
foreach ($p in $plan) {
  $c = if ($p.State -eq 'in place') { 'Green' } else { 'Yellow' }
  Say ("  {0,-9} {1,10:N0} b  {2}" -f $p.State, $p.Bytes, $p.Rel) $c
}

if (-not $todo.Count) {
  Say 'every recorded file is already in the game folder' 'Green'
  exit 0
}
if ($Check) {
  Say ("{0} of {1} would be copied. Run without -Check to do it." -f $todo.Count, $plan.Count) 'Yellow'
  exit 2
}

foreach ($p in $todo) {
  $dir = Split-Path $p.Dst -Parent
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Copy-Item -LiteralPath $p.Src -Destination $p.Dst -Force
  if ((Sha256 $p.Dst) -ne $rec.files.($p.Rel).sha256) { Stop-Here "copy of $($p.Rel) does not hash as the record; the folder may be in use" }
  Say "  copied $($p.Rel)" 'Green'
}
Say ("{0} file(s) in place. The next Ship packs them; Package-Thornswood puts them in the installer." -f $todo.Count) 'Green'
