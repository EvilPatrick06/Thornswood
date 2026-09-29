<#
  vps-freeze.ps1

  Runs ON the old VPS on the day the server moves: stops everything that writes
  what a backup takes, then takes the last backup.

  Sent there by Remote.ps1 (docs\MOVING-THE-SERVER.md), so the new box starts
  from exactly where the old one stopped and nothing anybody does afterwards
  is lost without them being told (issue #454).

      .\scripts\vps\Remote.ps1 -VpsHost <old address> -File .\scripts\vps\vps-freeze.ps1
      .\scripts\vps\Remote.ps1 -VpsHost <old address> -File .\scripts\vps\vps-freeze.ps1 -Arguments '-Undo'

  In order:
    1. says which account the site's task runs as, for Deploy-Docs.ps1 -RunAs
       on the new box
    2. disables Thornswood Watch, which would otherwise start everything
       again within five minutes
    3. stops both game servers, the site, the bot and both voice services,
       and ends whatever a stopped task leaves behind: whoever holds each game
       server's UDP port, whoever listens on the site's and the two voice
       services' TCP ports, and the bot's python and its wrapper
    4. runs the nightly backup once (C:\Thornswood-Backup\vps-nightly-backup.ps1,
       which Install-Backup.ps1 put there) and names the file it wrote
  Caddy, the nightly backup task and the build runner are left alone.

  -Undo starts the six again and turns the watchdog back on, for a move that
  is called off. -NoBackup stops without taking a backup.

  Prints FROZEN at the end only when nothing is left holding a port and a
  backup was written (or -NoBackup was passed).
#>
[CmdletBinding()]
param(
  [switch]$Undo,
  [switch]$NoBackup,
  [string]$BackupRoot = 'C:\Thornswood-Backup'
)

$ErrorActionPreference = 'Continue'
$watch = 'Thornswood Watch'
$tasks = @('Thornswood Server', 'Thornswood Dev Server', 'Thornswood Docs',
           'Thornswood Bot', 'Thornswood Voice', 'Thornswood Dev Voice')

if ($Undo) {
  foreach ($t in $tasks) {
    if (Get-ScheduledTask -TaskName $t -EA SilentlyContinue) { Start-ScheduledTask -TaskName $t; 'started   ' + $t }
  }
  if (Get-ScheduledTask -TaskName $watch -EA SilentlyContinue) {
    Enable-ScheduledTask -TaskName $watch | Out-Null
    'enabled   ' + $watch
  }
  'UNDONE: the old box serves again'
  return
}

$site = Get-ScheduledTask -TaskName 'Thornswood Docs' -EA SilentlyContinue
if ($site) { 'site      runs as ' + $site.Principal.UserId + ' (Deploy-Docs.ps1 -RunAs on the new box when this says LOCAL SERVICE)' }

if (Get-ScheduledTask -TaskName $watch -EA SilentlyContinue) {
  Disable-ScheduledTask -TaskName $watch | Out-Null
  # And a run already under way, which disabling does not end.
  Stop-ScheduledTask -TaskName $watch -EA SilentlyContinue
  'disabled  ' + $watch + ', so it starts nothing again'
} else { 'no task   ' + $watch }

foreach ($t in $tasks) {
  if (Get-ScheduledTask -TaskName $t -EA SilentlyContinue) { Stop-ScheduledTask -TaskName $t; 'stopped   ' + $t }
  else { 'no task   ' + $t }
}

# A stopped task does not always take its child with it (Deploy-Server.ps1
# StopOurs, Install-Bot.ps1): the process on each port, and the bot by its
# folder on its command line.
$udp = @()
foreach ($r in 'C:\Thornswood-Server', 'C:\Thornswood-Server-Dev') {
  try { $udp += [int]((Get-Content -LiteralPath (Join-Path $r 'server-settings.json') -Raw) -replace '^\uFEFF', '' | ConvertFrom-Json).port } catch { }
}
$tcp = @(3001, 7778, 7789)
function Holders {
  $ids = @()
  foreach ($p in $udp) { $ids += @(Get-NetUDPEndpoint -LocalPort $p -EA SilentlyContinue | ForEach-Object { $_.OwningProcess }) }
  foreach ($p in $tcp) { $ids += @(Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue | ForEach-Object { $_.OwningProcess }) }
  foreach ($p in @(Get-CimInstance Win32_Process -EA SilentlyContinue)) {
    if ($p.CommandLine -and $p.CommandLine -like '*Thornswood-Bot*' -and ($p.Name -like 'python*' -or $p.CommandLine -like '*run.ps1*')) { $ids += $p.ProcessId }
  }
  return @($ids | Where-Object { $_ -gt 0 -and $_ -ne $PID } | Sort-Object -Unique)
}
foreach ($id in (Holders)) {
  $n = (Get-Process -Id $id -EA SilentlyContinue).ProcessName
  Stop-Process -Id $id -Force -EA SilentlyContinue
  'ended     pid ' + $id + ' (' + $n + ')'
}
for ($i = 0; $i -lt 20 -and @(Holders).Count; $i++) { Start-Sleep -Milliseconds 500 }
$left = @(Holders)
foreach ($id in $left) { 'STILL RUNNING pid ' + $id + ' (' + (Get-Process -Id $id -EA SilentlyContinue).ProcessName + ')' }

$wrote = $null
if ($NoBackup) {
  'backup    not taken, -NoBackup'
} else {
  $nightly = Join-Path $BackupRoot 'vps-nightly-backup.ps1'
  if (-not (Test-Path -LiteralPath $nightly)) {
    'NO BACKUP: ' + $nightly + ' is not there. Run Install-Backup.ps1 -VpsHost <old address> from the repository, then this again.'
  } else {
    $before = Get-Date
    & $nightly | ForEach-Object { '  ' + $_ }
    $wrote = Get-ChildItem -LiteralPath $BackupRoot -File -EA SilentlyContinue |
             Where-Object { $_.Name -match '^thornswood-\d{8}-\d{6}\.zip(\.enc)?$' -and $_.LastWriteTime -ge $before } |
             Sort-Object Name -Descending | Select-Object -First 1
    if ($wrote) { 'BACKUP    ' + $wrote.Name + ', ' + [math]::Round($wrote.Length / 1MB, 1) + ' MB. Fetch-Backups.ps1 -VpsHost <old address> brings it down.' }
    else { 'NO BACKUP was written. The lines above say why.' }
  }
}

''
if (-not $left.Count -and ($NoBackup -or $wrote)) { 'FROZEN: nothing on the old box is serving the world, the site or the bot' }
else { 'NOT FROZEN: see the lines above. -Undo puts the old box back as it was.' }
