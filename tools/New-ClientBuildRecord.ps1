<#
.SYNOPSIS
  Records what the client runtime is and which fork commit it was built from,
  into tools\client-build.json.

.DESCRIPTION
  Until 20 September the SkyMP client Thornswood shipped was whatever another
  server's launcher had last written into the Steam copy's Data folder: the
  bundle, MpClientPlugin.dll, both SkyrimPlatform DLLs, the CEF host and
  TESModPlatform.pex, all of them another launcher's builds, copied into
  Thornswood's own folder on every rebuild and then patched by text. None of it
  came from Vortex, measured against the deployment manifest, and none of it
  came from here.

  The client is built from the fork now, C:\Thornswood-Dev\skymp, with
  npx webpack in skymp5-client for the bundle and the native build for the
  rest. This records the six files that build produces which differ from
  upstream, by hash, against the fork commit they came from. Sync-Client.ps1
  reads the record and refuses to copy a file whose hash is not the recorded
  one, so a stale or unknown build cannot reach the game folder, and from there
  a pack, by accident. Ship-Rules.ps1 reads it too: a runtime file whose hash
  is in this record is ours, and one that is not is somebody else's.

  Run this after every rebuild of the client. Read only except for the one
  file it writes. It never starts anything and never talks to the VPS.

.PARAMETER Dist
  Where the client build puts its output.

.PARAMETER Clone
  The skymp clone, read for the commit the build came from.

.PARAMETER Out
  The record to write. Committed to this repo.

.EXAMPLE
  .\tools\New-ClientBuildRecord.ps1
#>
[CmdletBinding()]
param(
  [string]$Dist  = (& (Join-Path $PSScriptRoot 'Where.ps1') ClientDist),
  [string]$Clone = (& (Join-Path $PSScriptRoot 'Where.ps1') Engine),
  [string]$Out
)
$ErrorActionPreference = 'Stop'
if (-not $Out) { $Out = Join-Path $PSScriptRoot 'client-build.json' }

# The six. Everything else the build produces is byte for byte what is already
# in the game folder, measured 20 September against 91 files.
$Files = @(
  'Data\SKSE\Plugins\MpClientPlugin.dll',
  'Data\SKSE\Plugins\SkyrimPlatform.dll',
  'Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformImpl.dll',
  'Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformCEF.exe.hidden',
  'Data\Platform\Plugins\skymp5-client.js',
  'Data\Scripts\TESModPlatform.pex'
)

if (-not (Test-Path -LiteralPath $Dist)) { throw "client dist not found: $Dist" }

function Sha256([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

$rec = [ordered]@{}
$newest = [DateTime]::MinValue
foreach ($rel in $Files) {
  $p = Join-Path $Dist $rel
  if (-not (Test-Path -LiteralPath $p)) { throw "the build is missing $rel" }
  $f = Get-Item -LiteralPath $p
  if ($f.LastWriteTimeUtc -gt $newest) { $newest = $f.LastWriteTimeUtc }
  $rec[$rel] = [ordered]@{ sha256 = (Sha256 $p); bytes = $f.Length }
}

# The bundle's own markers, so a bundle from somebody else's lineage cannot be
# recorded as ours by mistake.
$bundle = Get-Content -LiteralPath (Join-Path $Dist 'Data\Platform\Plugins\skymp5-client.js') -Raw
$patchBlocks = ([regex]::Matches($bundle, 'THORNSWOOD PATCH')).Count
$otherMarkers = ([regex]::Matches($bundle, '(?i)daedric')).Count
if ($patchBlocks -lt 1) { throw 'the bundle carries no THORNSWOOD PATCH block; this is not a build from the fork' }
if ($otherMarkers -gt 0) { throw "the bundle carries $otherMarkers marker(s) from another server's lineage; refusing to record it" }

# The commit, and whether the clone is clean and the build is not older than
# the source it claims to be built from.
$commit = ''; $branch = ''; $base = ''; $dirty = $false; $stale = @()
try {
  $commit = (& git -C $Clone rev-parse --short=8 HEAD 2>$null).Trim()
  $branch = (& git -C $Clone branch --show-current 2>$null).Trim()
  $base   = (& git -C $Clone merge-base HEAD upstream/main 2>$null)
  if ($base) { $base = $base.Trim().Substring(0, 8) } else { $base = 'unknown, fetch upstream to fill this in' }
  $dirty  = [bool]((& git -C $Clone status --porcelain -- skymp5-client skymp5-server 2>$null) | Where-Object { $_ })
  foreach ($src in (Get-ChildItem -LiteralPath (Join-Path $Clone 'skymp5-client\src') -Recurse -File -Include *.ts -EA SilentlyContinue)) {
    if ($src.LastWriteTimeUtc -gt $newest) { $stale += $src.FullName.Substring($Clone.Length + 1) }
  }
} catch { }

$record = [ordered]@{
  recordedUtc          = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  builtUtc             = $newest.ToString('yyyy-MM-ddTHH:mm:ssZ')
  fork                 = 'https://github.com/EvilPatrick06/skymp'
  forkBranch           = $branch
  forkCommit           = $commit
  upstreamBase         = $base
  thornswoodPatchBlocks = $patchBlocks
  files                = $rec
}
[IO.File]::WriteAllText($Out, (($record | ConvertTo-Json -Depth 5) + "`n"), (New-Object Text.UTF8Encoding($false)))

Write-Host "recorded $($Files.Count) files from $commit on $branch -> $Out" -ForegroundColor Green
foreach ($rel in $Files) { Write-Host ("  {0,-72} {1}  {2,10:N0} b" -f $rel, $rec[$rel].sha256.Substring(0, 12), $rec[$rel].bytes) }
if ($dirty) { Write-Host '  the clone has uncommitted client or server changes; the record names a commit those are not in' -ForegroundColor Yellow }
if ($stale.Count) {
  Write-Host "  $($stale.Count) source file(s) are newer than the build; rebuild before trusting this:" -ForegroundColor Yellow
  $stale | Select-Object -First 5 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
}
