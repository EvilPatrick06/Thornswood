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

    .\Deploy-DevGamemode.ps1        syntax check, copy, point at 7789,
                                   restart, tail the log

  A gamemode change that also changes the load order or the CHARGEN records
  needs Deploy-Gamemode.ps1 -Vortex first. Code-only changes do not.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Root = 'C:/Thornswood-Server-Dev',
  [string]$Task = 'Thornswood Dev Server',
  # The dev voice service. gamemode.js reads this out of the dev server's
  # own server-settings.json; without it the dev server talks to the live
  # voice service on 7778, pushes its positions over the live ones and
  # drains the live command and choice queues.
  [int]$VoicePort = 7789,
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
Write-Host 'Pointing the dev server at the dev voice service...'
# Deliberately not sent from here. server-settings.json on the dev box
# carries the dev port and name and must not be overwritten from a local
# build, which is the whole reason this script exists rather than
# Deploy-Server.ps1. One key is set in place instead, and the old file is
# kept beside it.
Remote @"
`$p = '$rootWin\server-settings.json'
if (-not (Test-Path `$p)) { 'NO server-settings.json AT ' + `$p; exit 0 }
`$s = Get-Content `$p -Raw | ConvertFrom-Json
`$have = 0
if (`$s.PSObject.Properties.Name -contains 'thornswoodVoicePort') { `$have = [int]`$s.thornswoodVoicePort }
# WHAT YOU ARE WEARING STAYS ON. Measured 20 September, after Patrick rejoined
# an existing character and arrived with nothing on. The server refuses an
# equipment update outright in two places and on a modded load order both fire
# constantly: the gear strip, which refuses the whole update the moment two worn
# items share one biped slot bit and then unequips every item involved, and the
# spell strip, which refuses any spell the server did not itself grant and sends
# a RemoveSpell back. Both were made switchable in our own fork and both still
# default to true in WorldState.h, so the switches were built and never thrown.
# What is worn is saved by the engine in the change form already; it only ever
# saves an update that was accepted, and these two lines are what lets one be.
`$wantEquip = `$false
foreach (`$k in 'equipmentSlotCheckEnabled','equipmentSpellCheckEnabled') {
  if (`$s.PSObject.Properties.Name -notcontains `$k) { `$wantEquip = `$true }
  elseif (`$s.`$k -ne `$false) { `$wantEquip = `$true }
}
# A byte order mark counts as needing a rewrite even when the number is
# already right. The run on 18 September set the value AND wrote a mark, so
# a second run that only compared the number would have said 'already 7789'
# and left the server unable to parse its own settings.
`$bom = `$false
try { `$bom = ([IO.File]::ReadAllBytes(`$p)[0] -eq 0xEF) } catch { }
if (`$bom) { 'the settings file starts with a byte order mark, rewriting it without one' }
if (`$have -eq $VoicePort -and -not `$bom -and -not `$wantEquip) {
  'thornswoodVoicePort is already $VoicePort, and both equipment checks are already off'
} else {
  Copy-Item `$p (`$p + '.before-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
  `$s | Add-Member -NotePropertyName thornswoodVoicePort -NotePropertyValue $VoicePort -Force
  `$s | Add-Member -NotePropertyName equipmentSlotCheckEnabled  -NotePropertyValue `$false -Force
  `$s | Add-Member -NotePropertyName equipmentSpellCheckEnabled -NotePropertyValue `$false -Force
  # NOT Set-Content -Encoding UTF8. At the far end of ssh this is Windows
  # PowerShell 5.1, where that means UTF-8 WITH a byte order mark, and the
  # server reads this file with JSON.parse, which refuses one:
  #   SyntaxError: Unexpected token 'ï»¿' is not valid JSON
  # On 18 September that took the dev server down on the first run of this
  # step. pwsh 7 writes no mark for the same flag, so it looks fine here and
  # breaks there. WriteAllText with an explicit UTF8Encoding($false) is the
  # one spelling that means the same thing in both.
  `$json = `$s | ConvertTo-Json -Depth 30
  [IO.File]::WriteAllText(`$p, `$json, (New-Object Text.UTF8Encoding `$false))
  'thornswoodVoicePort set to $VoicePort, was ' + `$have + '. Old file kept as server-settings.json.before-<stamp>'
  # Proved rather than assumed: reparse what was written, and check the
  # first byte is not a mark.
  try {
    `$back = Get-Content `$p -Raw | ConvertFrom-Json
    `$b0 = [IO.File]::ReadAllBytes(`$p)[0]
    if (`$b0 -eq 0xEF) { 'WROTE A BYTE ORDER MARK. The server will not start. Put the .before- copy back.' }
    else { 'read back fine, thornswoodVoicePort is ' + `$back.thornswoodVoicePort +
            ', gear strip ' + `$back.equipmentSlotCheckEnabled +
            ', spell strip ' + `$back.equipmentSpellCheckEnabled }
  } catch {
    'THE FILE NO LONGER PARSES: ' + `$_.Exception.Message + '. Put the .before- copy back.'
  }
}
"@ | ForEach-Object { "  $_" }

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
