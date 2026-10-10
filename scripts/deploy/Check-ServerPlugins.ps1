<#
.SYNOPSIS
  Read-only: does every collection plugin on a server match
  records\collection-plugins.json?

.DESCRIPTION
  Asks the box once for name|bytes|sha256 of every load-order plugin the
  record names. Prints CLEAN when they match, or the mismatch lines.
  Sends nothing, stops nothing and writes nothing (issue #2019).

  Exit 0 CLEAN, 1 a mismatch, 2 the record or the box could not be read.

.PARAMETER Server
  live or dev.

.PARAMETER CollectionRecord
  The record. Default records\collection-plugins.json.

.PARAMETER Prev
  When set, hash the newest .prev folder's plugins instead of the live
  ones, so a -PutBack refusal can be shown without putting anything back.

.EXAMPLE
  .\scripts\deploy\Check-ServerPlugins.ps1 -Server live
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet('live', 'dev')][string]$Server,
  [string]$CollectionRecord,
  [switch]$Prev
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\vps\Send-Script.ps1')
. (Join-Path $Here 'CollectionPlugins.ps1')

if (-not $CollectionRecord) { $CollectionRecord = Join-Path $Here '..\..\records\collection-plugins.json' }

$rec = $null
try { $rec = Read-CollectionPluginsRecord $CollectionRecord } catch {
  Write-Host $_.Exception.Message -ForegroundColor Red
  exit 2
}

$User = Get-ThornswoodVpsUser
$Vps = Get-ThornswoodVpsAddress
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
$Root = if ($Server -eq 'dev') { 'C:/Thornswood-Server-Dev' } else { 'C:/Thornswood-Server' }
$rootWin = $Root.Replace('/', '\')

$q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
$names = @($rec.Plugins.Keys)
$nameLines = @($names | ForEach-Object { '  ' + (& $q $_) }) -join "`r`n"
$pickPrev = @'
$last = @(Get-ChildItem -LiteralPath $root -Directory -Force -EA SilentlyContinue |
          Where-Object { $_.Name -like '.prev-*' } | Sort-Object Name -Descending | Select-Object -First 1)
if (-not $last.Count) { 'NOPREV'; exit 2 }
$dir = Join-Path $last[0].FullName 'plugins'
'PREV ' + $last[0].Name
'@
if (-not $Prev) { $pickPrev = '' }
$script = (
  '$ProgressPreference = ''SilentlyContinue''' + "`r`n" +
  ('$root = ' + (& $q $rootWin) + "`r`n") +
  '$dir = Join-Path $root ''plugins''' + "`r`n" +
  $pickPrev + "`r`n" +
  '$want = @(' + "`r`n" + $nameLines + "`r`n" + ')' + "`r`n" +
  @'
foreach ($n in $want) {
  $p = Join-Path $dir $n
  if (-not (Test-Path -LiteralPath $p)) { $n + '|missing|'; continue }
  $i = Get-Item -LiteralPath $p
  $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
  $i.Name + '|' + $i.Length + '|' + $h
}
'@
)

$said = @()
try {
  $said = @(Invoke-ThornswoodRemote -Target "$User@$Vps" -SshArgs $ssh -Script $script | ForEach-Object { "$_".Trim() })
} catch {
  Write-Host ("could not read {0}: {1}" -f $Server, $_.Exception.Message) -ForegroundColor Red
  exit 2
}

if ($said -contains 'NOPREV') {
  Write-Host ("no .prev folder on {0}, so there is nothing to hash" -f $Server) -ForegroundColor Red
  exit 2
}

$bad = New-Object System.Collections.Generic.List[string]
$ok = 0
$seen = @{}
foreach ($line in $said) {
  if ($line -like 'PREV *') { Write-Host ('  ' + $line) -ForegroundColor DarkGray; continue }
  $bits = $line -split '\|'
  if ($bits.Count -lt 3) { continue }
  $name = $bits[0]
  $hit = Get-CollectionRecordPlugin $rec.Plugins $name
  if (-not $hit) { continue }
  $seen[$name] = $true
  if ($bits[1] -eq 'missing') {
    [void]$bad.Add(('{0} from {1}: missing, the collection''s ({2} rev {3}) is {4} ({5:N0} bytes)' -f $name, $Server, $rec.Collection, $rec.Revision, $hit.Sha256, $hit.Bytes))
    continue
  }
  $gotSha = $bits[2].ToLowerInvariant()
  $gotBytes = 0L
  [void][int64]::TryParse($bits[1], [ref]$gotBytes)
  if ($gotSha -ne $hit.Sha256) {
    [void]$bad.Add(('{0} from {1}: sha256 {2} ({3:N0} bytes), the collection''s ({4} rev {5}) is {6} ({7:N0} bytes)' -f `
      $name, $Server, $gotSha, $gotBytes, $rec.Collection, $rec.Revision, $hit.Sha256, $hit.Bytes))
  } else { $ok++ }
}
foreach ($k in @($rec.Plugins.Keys)) {
  if (-not $seen.ContainsKey($k)) {
    $found = $false
    foreach ($s in @($seen.Keys)) { if ([string]::Equals($s, $k, [StringComparison]::OrdinalIgnoreCase)) { $found = $true; break } }
    if (-not $found) {
      [void]$bad.Add(('{0} from {1}: missing, the collection''s ({2} rev {3}) is {4} ({5:N0} bytes)' -f $k, $Server, $rec.Collection, $rec.Revision, $rec.Plugins[$k].Sha256, $rec.Plugins[$k].Bytes))
    }
  }
}

if ($bad.Count) {
  foreach ($b in $bad) { Write-Host $b -ForegroundColor Red }
  exit 1
}
Write-Host ('CLEAN: {0} collection plugins match {1} rev {2}' -f $ok, $rec.Collection, $rec.Revision) -ForegroundColor Green
exit 0
