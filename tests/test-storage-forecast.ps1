<#
  test-storage-forecast.ps1

  Issue #2178. Holds scripts\vps\Forecast-Storage.ps1 to its promises with
  made-up histories in a temp folder: it refuses to forecast from one
  snapshot or too short a span, says no-growth on a flat disk, and gives
  ok, warning and critical at the documented lines. Nothing real is read.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot '..\scripts\vps\Forecast-Storage.ps1'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('fc-' + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
$fail = 0; $pass = 0
$total = 100GB
$t0 = [datetime]'2026-10-01T00:00:00Z'
function Hist([string]$name, [int]$count, [double]$startFree, [double]$perDay, [double]$stepDays = 1) {
  $p = Join-Path $tmp $name
  $lines = for ($i = 0; $i -lt $count; $i++) {
    [ordered]@{ t = $t0.ToUniversalTime().AddDays($i * $stepDays).ToString('o'); drive = 'C'; total = $total; free = $startFree + $perDay * $i * $stepDays } | ConvertTo-Json -Compress
  }
  Set-Content $p $lines -Encoding utf8; $p
}
function Check([string]$what, [string]$hist, [string]$now, [int]$code, [string]$verdict, [string[]]$extra = @()) {
  $out = & pwsh -NoProfile -File $script -History $hist -Now $now @extra 2>&1 | Out-String
  $got = $LASTEXITCODE
  if ($got -eq $code -and $out -match ('verdict\s+' + [regex]::Escape($verdict))) { $script:pass++; Write-Host ('PASS ' + $what) }
  else { $script:fail++; Write-Host ('FAIL ' + $what + ': exit ' + $got + "`n" + $out) }
}
$end = { param($n, $s = 1) $t0.AddDays(($n - 1) * $s).ToString('o') }
try {
  Check 'one snapshot refuses' (Hist 'one.jsonl' 1 30GB 0) (& $end 1) 0 'not-enough-data'
  Check 'many samples over too short a span refuse' (Hist 'short.jsonl' 20 50GB -2GB 0.1) (& $end 20 0.1) 0 'not-enough-data'
  Check 'no history refuses' (Join-Path $tmp 'none.jsonl') (& $end 1) 0 'not-enough-data'
  Check 'flat disk is no-growth' (Hist 'flat.jsonl' 15 60GB 0) (& $end 15) 0 'no-growth'
  Check 'slow growth is ok' (Hist 'slow.jsonl' 15 80GB (-0.5GB)) (& $end 15) 0 'ok'
  Check '10% inside 30 days warns' (Hist 'warn.jsonl' 15 60GB (-2GB)) (& $end 15) 1 'warning'
  Check '10% inside 7 days is critical' (Hist 'crit.jsonl' 15 50GB (-2.5GB)) (& $end 15) 2 'critical'
  Check 'already under 10% is critical even with one sample' (Hist 'under.jsonl' 1 5GB 0) (& $end 1) 2 'critical'
  # -Record appends a line with the stand-in reading and nothing else.
  $rec = Join-Path $tmp 'rec\h.jsonl'
  & pwsh -NoProfile -File $script -History $rec -Record -FreeBytes 40GB -TotalBytes $total -Now '2026-10-01T00:00:00Z' | Out-Null
  $lines = @(Get-Content $rec)
  if ($lines.Count -eq 1 -and ($lines[0] | ConvertFrom-Json).free -eq 40GB) { $pass++; Write-Host 'PASS -Record appends one sample' } else { $fail++; Write-Host ('FAIL -Record wrote: ' + ($lines -join ' | ')) }
} finally { Remove-Item -Recurse -Force $tmp }
Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail) { exit 1 }
