<#
.SYNOPSIS
  Records what the server binary is and which commit it was built from, into
  tools\server-build.json.

.DESCRIPTION
  The server binaries have always been copied rather than rebuilt, and nothing
  mapped them back to source. On 2026-09-17 the only evidence that the shipped
  scam_native.node contained the committed server changes was that its file date
  was six minutes later than the last edit to ScampServer.cpp. A file date is not
  a build record.

  Run this after every rebuild of skymp. Deploy-Server.ps1 reads the result and
  refuses to ship a binary whose hash is not the recorded one, so a stale or
  unknown build cannot reach the VPS by accident.

  Read only except for the one file it writes. It never starts anything and never
  talks to the VPS.

.PARAMETER Dist
  Where the build puts the server. The same default Deploy-Server.ps1 uses.

.PARAMETER Clone
  The skymp clone, read for the commit the binary came from.

.PARAMETER Out
  The record to write. Committed to this repo, so a reader can answer what the
  live server is running without guessing from timestamps.

.EXAMPLE
  .\tools\New-ServerBuildRecord.ps1
#>
param(
  [string]$Dist  = (& (Join-Path $PSScriptRoot 'Where.ps1') ServerDist),
  [string]$Clone = (& (Join-Path $PSScriptRoot 'Where.ps1') Engine),
  [string]$Out
)

$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Out) { $Out = Join-Path $Here 'server-build.json' }

$bin = Join-Path $Dist 'scam_native.node'
if (-not (Test-Path -LiteralPath $bin)) { throw "not built: $bin" }

$item = Get-Item -LiteralPath $bin
$hash = (Get-FileHash -LiteralPath $bin -Algorithm SHA256).Hash.ToLowerInvariant()

# Named Read-Git, not Git. A function called Git wins name resolution over
# git.exe, so '& git' inside it called itself until the call stack blew.
function Read-Git([string[]]$a) {
  $o = & git.exe -C $Clone @a 2>$null
  if ($LASTEXITCODE -ne 0) { return '' }
  return ($o | Out-String).Trim()
}

# The fork is a submodule now, which checks out a commit and not a branch, and
# a fresh clone of it has no upstream remote. Both used to leave the record
# with an empty branch, or "HEAD", and no base (issue #546). These fall back
# to what the clone itself can say.
function Get-ForkBranch([string]$clone, [string]$now) {
  if ($now -and $now -ne 'HEAD') { return $now }
  $remote = @(& git -C $clone branch -r --contains HEAD 2>$null | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch '->' })
  if ($remote -contains 'origin/thornswood/engine-changes') { return 'thornswood/engine-changes' }
  if ($remote.Count) { return ($remote[0] -replace '^origin/', '') }
  # A clone fetched with one branch knows no other: the branch the repository
  # follows it on, from .gitmodules, when that is where it lives.
  $top = (& git -C $clone rev-parse --show-superproject-working-tree 2>$null | Out-String).Trim()
  if ($top) {
    $b = (& git -C $top config -f .gitmodules --get submodule.engine/skymp.branch 2>$null | Out-String).Trim()
    if ($b) { return $b }
  }
  return $now
}
function Get-UpstreamBase([string]$clone, [string]$now, [string]$recorded) {
  if ($now) { return $now }
  if ($recorded) {
    & git -C $clone merge-base --is-ancestor $recorded HEAD 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return $recorded }
  }
  return ''
}

$commit = Read-Git @('rev-parse', 'HEAD')
$branch = Get-ForkBranch $Clone (Read-Git @('rev-parse', '--abbrev-ref', 'HEAD'))
$origin = Read-Git @('remote', 'get-url', 'origin')
$upstream = Read-Git @('remote', 'get-url', 'upstream')
$recordedBase = ''
try { $recordedBase = [string]((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'server-build.json') -Raw | ConvertFrom-Json).source.upstreamBase) } catch { }
$base = Get-UpstreamBase $Clone (Read-Git @('merge-base', 'HEAD', 'upstream/main')) $recordedBase
$dirty = Read-Git @('status', '--porcelain')

if (-not $commit) { throw "cannot read a commit from $Clone. Is it a git clone?" }

if ($dirty) {
  Write-Host ''
  Write-Host '  The clone has uncommitted changes.' -ForegroundColor Yellow
  Write-Host '  The commit recorded below will not describe the binary exactly.' -ForegroundColor Yellow
  Write-Host '  Commit first, rebuild, then run this again.' -ForegroundColor Yellow
  Write-Host ''
}

# Whether the binary is at least newer than every server source. This is weak
# evidence on its own, which is the whole reason this file exists, but a binary
# OLDER than its sources is a definite problem worth stopping for.
#
# Only cpp\ and ts\, never the whole of skymp5-server: node_modules holds 7,300
# of that folder's 7,746 files and walking it turned a one second check into
# minutes. The 403 files that matter are all under these two.
$newest = $null
foreach ($sub in @('cpp', 'ts')) {
  $d = Join-Path $Clone (Join-Path 'skymp5-server' $sub)
  if (-not (Test-Path -LiteralPath $d)) { continue }
  $f = Get-ChildItem -LiteralPath $d -Recurse -File -EA SilentlyContinue |
       Where-Object { $_.Extension -in '.cpp', '.h', '.ts' -and $_.FullName -notlike '*\node_modules\*' } |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($f -and ((-not $newest) -or ($f.LastWriteTime -gt $newest.LastWriteTime))) { $newest = $f }
}
if ($newest -and $newest.LastWriteTime -gt $item.LastWriteTime) {
  Write-Host ''
  Write-Host ('  {0} is newer than the binary.' -f $newest.Name) -ForegroundColor Yellow
  Write-Host '  The build does not contain the latest source. Rebuild before recording.' -ForegroundColor Yellow
  Write-Host ''
}

$rec = [ordered]@{
  '_note'   = 'What the server binary in this release is, and the source it was built from. Deploy-Server.ps1 refuses to ship a binary whose sha256 is not this one. Regenerate with tools\New-ServerBuildRecord.ps1 after every rebuild.'
  'binary'  = 'scam_native.node'
  'sha256'  = $hash
  'bytes'   = $item.Length
  'builtUtc' = $item.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
  'source'  = [ordered]@{
    'repo'         = $origin
    'branch'       = $branch
    'commit'       = $commit
    'upstream'     = $upstream
    'upstreamBase' = $base
  }
  'recorded' = (Get-Date).ToString('yyyy-MM-dd')
}

$rec | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Out -Encoding UTF8

Write-Host 'Server build recorded'
Write-Host '---------------------'
Write-Host ('  sha256  {0}' -f $hash)
Write-Host ('  bytes   {0:N0}' -f $item.Length)
Write-Host ('  built   {0}' -f $item.LastWriteTime)
Write-Host ('  commit  {0}' -f $commit)
Write-Host ('  branch  {0}' -f $branch)
Write-Host ('  written {0}' -f $Out)
Write-Host ''
Write-Host '  Commit this file with the release it describes.' -ForegroundColor DarkGray
