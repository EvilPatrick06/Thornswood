<#
  Start-Backup.ps1

  Takes a backup now, on the box, with the nightly's own task, and waits for
  that run to end (#2862). Before a step that could lose something (a move,
  a wipe, a restore rehearsal) there was no way to take one except on One
  with Install-Backup.ps1 -RunNow. The gate verb Start-Backup runs this.

      Start-Backup.ps1           start "Thornswood Backup", wait for it, say how it ended

  It starts the task Install-Backup.ps1 registered, so the backup is made by
  the same script, account and rules as every night's, and the Thornswood
  Send Backups task then sends it off the box as it does every night's. It
  waits on the task's own state, not a clock: it reads the task until it is no
  longer running (40 minutes at most, inside the 45 the gate gives a verb;
  a night's run takes about five), then prints its result and the end of backup.log, and ends 0 only when the run ended 0.
  Windows PowerShell 5.1.
#>
[CmdletBinding()]
param(
  [string]$TaskName = 'Thornswood Backup',
  [string]$Root = 'C:\Thornswood-Backup',
  [int]$Minutes = 40,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
function Die($m) { Write-Host "STOP. $m"; exit 1 }
$t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $t) { Die "$TaskName is not registered: Install-Backup.ps1 registers it. Nothing was started." }
if ("$($t.State)" -eq 'Running') { Die "$TaskName is running already; that run is the backup. Nothing was started." }
$before = (Get-ScheduledTaskInfo -TaskName $TaskName).LastRunTime
Start-ScheduledTask -TaskName $TaskName
Write-Host "  started $TaskName"
$until = (Get-Date).AddMinutes($Minutes)
# The task's state, every two seconds, until this run has begun and ended.
while ((Get-Date) -lt $until) {
  Start-Sleep -Seconds 2
  $state = "$((Get-ScheduledTask -TaskName $TaskName).State)"
  $i = Get-ScheduledTaskInfo -TaskName $TaskName
  if ($state -ne 'Running' -and $i.LastRunTime -gt $before) { break }
}
$i = Get-ScheduledTaskInfo -TaskName $TaskName
if ("$((Get-ScheduledTask -TaskName $TaskName).State)" -eq 'Running') { Die "$TaskName was still running after $Minutes minutes; its log is $Root\backup.log." }
Write-Host ('  ended ' + $i.LastRunTime + ', result ' + $i.LastTaskResult)
Get-Content -LiteralPath (Join-Path $Root 'backup.log') -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
if ([int64]$i.LastTaskResult -ne 0) { exit 1 }
exit 0
