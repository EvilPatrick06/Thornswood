<#
  test-3187-backup-clear-of-nightly.ps1

      pwsh -NoProfile -File .\tests\test-3187-backup-clear-of-nightly.ps1

  Issue #3187. The nightly backup (Install-Backup.ps1 -At, 03:15 box time,
  09:15 UTC) started a quarter of an hour into the nightly checks' harness
  shares (.github\workflows\nightly.yml, cron 0 9 * * *), in the box's
  busiest hour: on 21 Oct 2026 it took 9.8 minutes beside them and 4.5 on a
  quiet night. The two were set on their own and nothing kept them apart.
  This fails on:
    1. the backup's time not said in UTC (a Z on the end), the way the cron
       is, so daylight saving would move one and not the other;
    2. the backup not ending, at 30 minutes (three times its slowest
       measured run), before a nightly cron starts;
    3. the backup starting less than 75 minutes after a nightly cron starts
       (the shares ran 34 minutes on 21 Oct and have 45 each);
    4. the time not being one Windows reads, as New-ScheduledTaskTrigger
       does on the box.
  Reads two files. Under a second.
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$ok) {
    if ($ok) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Done { Write-Host ''; Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail); exit ([int]($script:fail -gt 0)) }

$installer = [IO.Path]::Combine($Repo, 'scripts', 'deploy', 'Install-Backup.ps1')
$errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$null, [ref]$errs)
$p = $ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'At' }
Yes 'Install-Backup.ps1 has -At with a default' ($null -ne $p -and $null -ne $p.DefaultValue)
if ($script:fail) { Done }
$at = [string]$p.DefaultValue.Value
Yes ("its default, $at, is in UTC, with a Z") ($at -match '^\d{2}:\d{2}Z$')
$parsed = [datetime]::MinValue
$ok = [datetime]::TryParse($at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$parsed)
Yes '  and one Windows reads as a UTC time' ($ok -and $parsed.Kind -eq 'Utc')
if ($script:fail) { Done }
$backup = $parsed.Hour * 60 + $parsed.Minute

$yml = [IO.File]::ReadAllText([IO.Path]::Combine($Repo, '.github', 'workflows', 'nightly.yml'))
$crons = @([regex]::Matches($yml, "cron:\s*'(\d+)\s+(\d+)\s+\*\s+\*\s+\*'") | ForEach-Object { [int]$_.Groups[2].Value * 60 + [int]$_.Groups[1].Value })
Yes 'nightly.yml has a daily cron at a fixed minute and hour' ($crons.Count -ge 1)
foreach ($c in $crons) {
    $hhmm = '{0:00}:{1:00} UTC' -f [math]::Floor($c / 60), ($c % 60)
    # Minutes from the backup's start to the cron's, and from the cron's to the backup's, round the clock.
    $before = ($c - $backup + 1440) % 1440
    $after = ($backup - $c + 1440) % 1440
    Yes ("the backup ends, at 30 minutes, before the nightly checks at $hhmm start (" + $before + ' min before)') ($before -ge 30)
    Yes ("  and does not start within 75 minutes after they do (" + $after + ' min after)') ($after -ge 75)
}
Done
