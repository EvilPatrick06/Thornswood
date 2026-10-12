<#
.SYNOPSIS
  Records the VPS disk free space over time and forecasts when it reaches the watchdog's DISK LOW and DISK CRITICAL lines, refusing to forecast from too few samples.

.DESCRIPTION
  Issue #2178. Watch-Services.ps1 already says DISK LOW under 20% free and
  DISK CRITICAL under 10%, but only once the disk is already there. This
  keeps a history of samples (one JSON line each: time, drive, total and
  free bytes) and fits a straight line through the free bytes to say how
  many days are left before each of those two lines is crossed.

  The issue warns against judging capacity from one snapshot, so the
  forecast refuses to project (verdict 'not-enough-data', exit 0) until the
  history holds at least -MinSamples samples spread over at least
  -MinSpanDays days. A disk that is flat or gaining free space gets
  'no-growth'.

  ASSUMPTIONS, said in every report: growth is linear over the window
  read (the last -WindowDays days), nothing is deleted or rotated in bulk
  during the horizon, and the drive size does not change.

  THRESHOLDS AND OWNERS
    ok        exit 0  DISK CRITICAL (10%) is more than -WarnDays (30) days out.
    warning   exit 1  10% is reached within 30 days, or 20% within 7.
                      Owner: Installer lane. Action: plan cleanup or retention
                      for logs, uploads, payloads and backups this week.
    critical  exit 2  10% is reached within -CriticalDays (7) days, or the
                      disk is already under 10%. Owner: whoever is on staff.
                      Action: clear old logs, uploads or payloads today.
  Exit 3 means the history could not be read.

  Reads the disk and appends one line to the history with -Record. Never
  deletes anything, never touches a service. -FreeBytes/-TotalBytes and
  -Now stand in for a real reading so tests\test-storage-forecast.ps1 can
  run it offline.

.EXAMPLE
  .\scripts\vps\Forecast-Storage.ps1 -Record -History C:\Thornswood\watch\disk-history.jsonl
#>
[CmdletBinding()]
param(
  [string]$History = (Join-Path $PSScriptRoot 'disk-history.jsonl'),
  [switch]$Record,
  [string]$Drive = 'C',
  [double]$FreeBytes = -1,
  [double]$TotalBytes = -1,
  [string]$Now = '',
  [int]$MinSamples = 14,
  [double]$MinSpanDays = 7,
  [double]$WindowDays = 30,
  [double]$WarnDays = 30,
  [double]$CriticalDays = 7,
  [double]$LowPct = 20,
  [double]$CriticalPct = 10
)
$ErrorActionPreference = 'Stop'
$at = if ($Now) { [datetime]::Parse($Now, [Globalization.CultureInfo]::InvariantCulture).ToUniversalTime() } else { [datetime]::UtcNow }

if ($Record) {
  if ($FreeBytes -lt 0 -or $TotalBytes -le 0) {
    $d = Get-PSDrive -Name $Drive -PSProvider FileSystem
    $FreeBytes = [double]$d.Free; $TotalBytes = [double]$d.Used + [double]$d.Free
  }
  $dir = Split-Path -Parent $History
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $line = [ordered]@{ t = $at.ToString('o'); drive = $Drive; total = $TotalBytes; free = $FreeBytes } | ConvertTo-Json -Compress
  Add-Content -LiteralPath $History -Value $line -Encoding utf8
}

$samples = @()
if (Test-Path -LiteralPath $History) {
  try {
    foreach ($l in Get-Content -LiteralPath $History) {
      if (-not $l.Trim()) { continue }
      $o = $l | ConvertFrom-Json
      if ($o.drive -ne $Drive) { continue }
      $samples += [pscustomobject]@{ t = ([datetime]$o.t).ToUniversalTime(); total = [double]$o.total; free = [double]$o.free }
    }
  } catch { Write-Output ('history unreadable: ' + $History + ': ' + $_.Exception.Message); exit 3 }
}
$samples = @($samples | Where-Object { $_.t -ge $at.AddDays(-$WindowDays) -and $_.t -le $at } | Sort-Object t)

function Say([string]$verdict, [string]$why, $daysLow, $daysCrit) {
  Write-Output ('verdict   ' + $verdict)
  Write-Output ('why       ' + $why)
  Write-Output ('samples   ' + $samples.Count + ' in the last ' + $WindowDays + ' days (need ' + $MinSamples + ' over ' + $MinSpanDays + ' days)')
  if ($null -ne $daysLow) { Write-Output ('to ' + $LowPct + '%    ' + $daysLow + ' days') }
  if ($null -ne $daysCrit) { Write-Output ('to ' + $CriticalPct + '%    ' + $daysCrit + ' days') }
  Write-Output ('assumes   linear growth over the window, no bulk deletes, same drive size; horizon ' + $WarnDays + ' days')
}

if ($samples.Count -eq 0) { Say 'not-enough-data' 'no samples yet' $null $null; exit 0 }
$last = $samples[-1]
$pct = 100.0 * $last.free / $last.total
if ($pct -lt $CriticalPct) { Say 'critical' ('already ' + [math]::Round($pct, 1) + '% free, under ' + $CriticalPct + '%') $null 0; exit 2 }
$span = ($last.t - $samples[0].t).TotalDays
if ($samples.Count -lt $MinSamples -or $span -lt $MinSpanDays) {
  Say 'not-enough-data' ('one snapshot is not a forecast; now ' + [math]::Round($pct, 1) + '% free over ' + [math]::Round($span, 1) + ' days of samples') $null $null; exit 0
}

# Least squares: free bytes against days.
$n = $samples.Count; $sx = 0.0; $sy = 0.0; $sxx = 0.0; $sxy = 0.0
foreach ($s in $samples) { $x = ($s.t - $samples[0].t).TotalDays; $sx += $x; $sy += $s.free; $sxx += $x * $x; $sxy += $x * $s.free }
$den = $n * $sxx - $sx * $sx
$slope = if ($den -ne 0) { ($n * $sxy - $sx * $sy) / $den } else { 0 }
if ($slope -ge 0) { Say 'no-growth' ('free space is flat or rising; now ' + [math]::Round($pct, 1) + '% free') $null $null; exit 0 }

$burn = -$slope
$dLow = [math]::Max(0, [math]::Round(($last.free - $last.total * $LowPct / 100) / $burn, 1))
$dCrit = [math]::Round(($last.free - $last.total * $CriticalPct / 100) / $burn, 1)
$why = 'now ' + [math]::Round($pct, 1) + '% free, losing ' + [math]::Round($burn / 1GB, 2) + ' GB a day'
if ($dCrit -le $CriticalDays) { Say 'critical' ($why + '. Staff: clear old logs, uploads or payloads today.') $dLow $dCrit; exit 2 }
if ($dCrit -le $WarnDays -or $dLow -le $CriticalDays) { Say 'warning' ($why + '. Installer lane: plan cleanup or retention this week.') $dLow $dCrit; exit 1 }
Say 'ok' $why $dLow $dCrit; exit 0
