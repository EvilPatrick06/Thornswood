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
  $cmd = "powershell -NoProfile -EncodedCommand $e"

  # A long script does not fit on a command line, and nothing says so.
  #
  # sshd on Windows hands the command to cmd.exe, which stops at 8,191
  # characters. Base64 of UTF-16 is about 2.7 times the script, so a block of
  # any size arrives cut in half and PowerShell then complains about a brace or
  # a token in a script nobody can see. On 20 Sep the settings block below went
  # to 10,252 characters and the far end reported "Unexpected token '$?'" and
  # "Missing closing '}'" about a line fifteen above the one that was actually
  # cut, which is what makes this so expensive to find. Deploy-Docs.ps1 hit the
  # same thing on 17 Sep and solved it; this is that fix, and it is now in all
  # sixteen scripts that talk to the VPS rather than in one.
  #
  # Under the limit it goes on the command line as before, because that is one
  # round trip. Over it, the script is sent as a file and run from there, which
  # has no length to run into.
  if ($cmd.Length -le 6000) {
    return & ssh @ssh "$User@$Vps" $cmd 2>&1
  }

  $far = 'C:/Windows/Temp/thornswood-remote.ps1'
  $tmp = [IO.Path]::GetTempFileName()
  try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    & scp @ssh $tmp "$User@${Vps}:$far" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not send a script to $Vps" }
    # The path goes across as it is. Windows PowerShell takes forward
    # slashes, and converting them was how this shipped with the slashes
    # stripped out of it entirely: C:WindowsTempthornswood-remote.ps1.
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File '$far'" 2>&1
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
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
# WHAT YOU ARE WEARING STAYS ON, and the three keys below are why. Measured on
# 20 September from the live server.log: 24 refused equipment updates over two
# days, every one of them 'inventory does not contain item 13790', which is
# IronWarAxe. Skyrim Unbound hands out starting gear inside the client's own
# game and the server never sees it happen, so the first equipment update a new
# character sends names an item the server has no record of, and upstream throws
# the WHOLE update away for it. The equipment record then stays empty all
# session, and on the next spawn the client empties the pack and refills it from
# that empty record, four times in a second and a half. equipmentSlotCheckEnabled
# and equipmentSpellCheckEnabled are the other two refusals, neither of which the
# log shows firing, both switchable in our fork already.
# equipmentInventoryCheckEnabled is the one that matters and it needs the server
# rebuilt from thornswood/engine-changes before it does anything; an unknown key
# is ignored until then.
#
# This comment is HERE and not inside the here-string below on purpose. Anything
# in that string is base64 encoded and sent as an ssh command line, where it
# counts double and the far end truncates at about 8191 characters. Ten lines of
# comment in there took the block from roughly 7,400 to 10,252 and the VPS
# received a script that stopped in the middle of the line that writes the file.
Remote @"
`$p = '$rootWin\server-settings.json'
if (-not (Test-Path `$p)) { 'NO server-settings.json AT ' + `$p; exit 0 }
`$s = Get-Content `$p -Raw | ConvertFrom-Json
`$have = 0
if (`$s.PSObject.Properties.Name -contains 'thornswoodVoicePort') { `$have = [int]`$s.thornswoodVoicePort }
`$wantEquip = `$false
foreach (`$k in 'equipmentSlotCheckEnabled','equipmentSpellCheckEnabled','equipmentInventoryCheckEnabled') {
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
  `$s | Add-Member -NotePropertyName equipmentInventoryCheckEnabled -NotePropertyValue `$false -Force
  # Nothing in the world comes back except FLOR and TREE, which is the hanging
  # meat, the garlic, the elves ears, every plant and every crop. The argument
  # and the census behind the exception are written out in Deploy-Gamemode.ps1;
  # dev carries the same list so that a thing tested here behaves the same live.
  `$s | Add-Member -NotePropertyName forbiddenReloot -NotePropertyValue @(
      'CONT',
      'WEAP', 'ARMO', 'AMMO', 'MISC', 'ALCH', 'INGR', 'BOOK', 'SLGM', 'SCRL',
      'LIGH', 'KEYM', 'NOTE'
  ) -Force
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
            ', spell strip ' + `$back.equipmentSpellCheckEnabled +
            ', unknown item vetoes ' + `$back.equipmentInventoryCheckEnabled }
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
