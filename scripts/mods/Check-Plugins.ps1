# What is enabled that should not be, and what is missing that should be there.
# Compares the live load order against the reference this install shipped with.
$live = Join-Path $env:LOCALAPPDATA (Join-Path 'Skyrim Special Edition' 'plugins.txt')

$ref = $null
foreach ($d in [IO.DriveInfo]::GetDrives()) {
  if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
  $t = Join-Path $d.RootDirectory.FullName (Join-Path 'Thornswood' (Join-Path 'Profile' (Join-Path 'Default' 'plugins.txt')))
  if (Test-Path -LiteralPath $t) { $ref = $t; break }
}

function Enabled($p) {
  if (-not $p -or -not (Test-Path -LiteralPath $p)) { return @() }
  @(Get-Content -LiteralPath $p | Where-Object { $_.StartsWith('*') } | ForEach-Object { $_.Substring(1).Trim() })
}

$have = Enabled $live
$want = Enabled $ref
Write-Host ""
Write-Host ("live      : {0}  ({1})" -f $have.Count, $live)
Write-Host ("reference : {0}  ({1})" -f $want.Count, $ref)

$extra   = @($have | Where-Object { $want -notcontains $_ })
$missing = @($want | Where-Object { $have -notcontains $_ })

Write-Host ""
Write-Host ("EXTRA, enabled but not part of the build ({0}):" -f $extra.Count) -ForegroundColor Yellow
if ($extra.Count -eq 0) { Write-Host "  none" -ForegroundColor DarkGray } else { $extra | ForEach-Object { Write-Host "  $_" } }

Write-Host ""
Write-Host ("MISSING, part of the build but not enabled ({0}):" -f $missing.Count) -ForegroundColor Yellow
if ($missing.Count -eq 0) { Write-Host "  none" -ForegroundColor DarkGray } else { $missing | ForEach-Object { Write-Host "  $_" } }
Write-Host ""
