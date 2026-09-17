<#
  Deploy-DevGamemode.ps1

  Sends tools\gamemode.js to the dev server on the VPS and restarts only that
  server. The dev server is a copy of the live install on its own ports
  (vps-dev-instance.ps1: C:\Thornswood-Server-Dev, UDP/TCP 7787, resources
  7788, task 'Thornswood Dev Server').

  Deploy-Server.ps1 is for the live server and must not be pointed at the dev
  root. It would do two wrong things there: send server-settings.json
  rewritten from the local build, which carries the live port and name and
  would start the dev server on 7777 next to the live one, and stop every node
  process whose command line contains skymp5-server, which is the live server
  too. This script sends gamemode.js alone and stops only the process that is
  listening on the dev port.

    .\Deploy-DevGamemode.ps1        syntax check, copy, restart, tail the log

  A gamemode change that also changes the load order or the CHARGEN records
  needs Deploy-Gamemode.ps1 -Vortex first. Code-only changes do not.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Root = 'C:/Thornswood-Server-Dev',
  [string]$Task = 'Thornswood Dev Server',
  [string]$Gamemode
)

$ErrorActionPreference = 'Stop'
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Gamemode) { $Gamemode = Join-Path $Here 'gamemode.js' }
if (-not (Test-Path -LiteralPath $Gamemode)) { throw "There is no gamemode at $Gamemode" }

function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" 2>&1
}

$rootWin = $Root.Replace('/', '\')

# Syntax first. A gamemode that does not parse takes the server down at start.
if (Get-Command node -ErrorAction SilentlyContinue) {
  & node --check $Gamemode
  if ($LASTEXITCODE -ne 0) { throw 'gamemode.js does not parse. Nothing was sent.' }
  Write-Host '  gamemode.js parses'
} else {
  Write-Host '  node is not on this machine, so the syntax check was skipped' -ForegroundColor Yellow
}

# The port comes from the dev server's own settings on the box, so the process
# stopped is the one on that port and nothing else. 7777 is the live server;
# refusing it here is what makes this script safe to run without thinking.
Write-Host ''
Write-Host 'Stopping the dev server...'
Remote @"
`$s = Get-Content '$rootWin\server-settings.json' -Raw | ConvertFrom-Json
`$port = [int]`$s.port
if (`$port -eq 7777) { 'REFUSING: $rootWin is on port 7777, which is the live server'; exit 9 }
'dev port ' + `$port + ', name ' + `$s.name
Stop-ScheduledTask -TaskName '$Task' -EA SilentlyContinue
`$pids = @()
`$pids += @(Get-NetUDPEndpoint -LocalPort `$port -EA SilentlyContinue | Select-Object -ExpandProperty OwningProcess)
`$pids += @(Get-NetTCPConnection -LocalPort (`$port + 1) -State Listen -EA SilentlyContinue | Select-Object -ExpandProperty OwningProcess)
foreach (`$id in (`$pids | Sort-Object -Unique)) {
  if (`$id -gt 0) { Stop-Process -Id `$id -Force -EA SilentlyContinue; 'stopped pid ' + `$id }
}
Start-Sleep -Seconds 2
if (Test-Path '$rootWin\gamemode.js') {
  Copy-Item '$rootWin\gamemode.js' ('$rootWin\gamemode.js.before-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
  'kept the old gamemode beside it as gamemode.js.before-<stamp>'
}
'stopped'
"@ | ForEach-Object { "  $_" }
if ($LASTEXITCODE -eq 9) { throw 'Refused: that root is the live server.' }

Write-Host ''
Write-Host 'Copying...'
& scp @ssh $Gamemode "$User@${Vps}:$Root/gamemode.js"
if ($LASTEXITCODE -ne 0) { throw 'scp failed for gamemode.js' }
Write-Host '  gamemode.js'

Write-Host ''
Write-Host 'Starting...'
Remote @"
Start-ScheduledTask -TaskName '$Task' -EA SilentlyContinue
Start-Sleep -Seconds 10
`$s = Get-Content '$rootWin\server-settings.json' -Raw | ConvertFrom-Json
`$port = [int]`$s.port
if (Get-NetUDPEndpoint -LocalPort `$port -EA SilentlyContinue) { 'dev server up on UDP ' + `$port } else { 'DEV SERVER IS NOT LISTENING on UDP ' + `$port }
if (Test-Path '$rootWin\server.log') {
  '--- server.log, last 15 ---'
  Get-Content '$rootWin\server.log' -Tail 15
}
"@ | ForEach-Object { "  $_" }
