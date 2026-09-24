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

    .\Deploy-DevGamemode.ps1 -LoadOrder
                                   the same, and first bring the dev server's
                                   load order and plugins up to what the built
                                   server has

  A gamemode change that also changes the CHARGEN records needs
  Deploy-Gamemode.ps1 -Vortex first. Code-only changes do not.

  THE LOAD ORDER, AND WHY -LoadOrder HAD TO EXIST.

  Until 22 September nothing in this repo could move a load order onto the dev
  server. Deploy-Server.ps1 is the live half and refuses this root on purpose.
  This script sent gamemode.js alone. The only thing that ever wrote the dev
  loadOrder was vps-dev-instance.ps1, which runs ON the VPS, copies from live,
  and nothing in the normal dev flow calls it. So the dev server kept whatever
  order it was built with while live moved on, and the client compares the two
  position by position and refuses the session on any disagreement.

  Measured on 22 September. Live was handing out 57 plugins and matched the
  game exactly. The dev server was handing out 60: the order from 21 September,
  still carrying Respawn - Death Overhaul.esp, SunHelmSurvival.esp,
  SunHelmDiseases.esp, TavernGames.esp and Hothtrooper44_Armor_Ecksstra.esp,
  and missing RaceCompatibility.esm and Playable Rieklings.esp. The lists part
  company at position 7 and everything after it is out of place. Its
  Thornswood-Content.esp was 151,288 bytes, which is the stale copy named in
  Deploy-Server.ps1's own comment as the one that stopped going to live that
  same day; the repo has been on 141,234 since. Four things for the launcher to
  find, and Play refused before the game ever started.

  -LoadOrder sends the plugins the built server's load order names and rewrites
  the dev loadOrder to match, and nothing else about the dev settings is
  touched: the port, the name and the voice port stay the dev ones, which is
  the whole reason Deploy-Server.ps1 is refused here. The list goes up as a
  file rather than inside the settings block, so the dev settings file is
  edited in place the way everything else here edits it.

  Our own plugin comes from the repo and not from a game folder, for the reason
  written out at length in Deploy-Server.ps1: there have been four copies of
  Thornswood-Content.esp on this machine at three different sizes, and the game
  folder is not the one that is authoritative.
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
  [string]$Gamemode,
  # Bring the dev server's load order and plugins up to what the built server
  # has. Off by default: a code-only gamemode change does not need it, and the
  # plugin sizes are one extra call to the box.
  [switch]$LoadOrder,
  # Where Deploy-Gamemode.ps1 leaves the built server. Its server-settings.json
  # is the one authority on what the load order is and in what order.
  [string]$Dist = 'C:\Thornswood-Dev\skymp\build\dist\server',
  # Where the other plugins live on this machine. Ours is taken from the repo
  # instead; see the header.
  [string]$Data = 'C:\Thornswood\Game\Data'
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

# --------------------------------------------------------- the load order ---
#
# Worked out before anything is stopped, so a missing plugin or an unreadable
# build stops this while the dev server is still up and serving.
$remotePlugins = ($Root -replace '\\', '/') + '/plugins'
$farOrder      = ''
$pluginNames   = @()
$sendPlugins   = @()
$changed       = @()
$orderFile     = ''

if ($LoadOrder) {
  $settingsSrc = Join-Path $Dist 'server-settings.json'
  if (-not (Test-Path -LiteralPath $settingsSrc)) {
    throw "-LoadOrder needs the built server's settings at $settingsSrc. Run Deploy-Gamemode.ps1 -Vortex first."
  }
  $built = Get-Content -LiteralPath $settingsSrc -Raw | ConvertFrom-Json
  if (-not $built.loadOrder) { throw "$settingsSrc has no loadOrder" }
  $pluginNames = @($built.loadOrder | ForEach-Object { [IO.Path]::GetFileName($_) })
  $ours = Join-Path $Here 'Thornswood-Content.esp'

  # Name and size, the same question Deploy-Server.ps1 asks of the live box and
  # for the same reason: a plugin already there by name may not be the same
  # plugin any more. Size and not a hash, because a hash of 57 plugins is tens
  # of megabytes of reading on a box that is also running two servers.
  $thereRaw = @(Remote ("Get-ChildItem -LiteralPath '" + $remotePlugins.Replace('/','\') +
                        "' -File | ForEach-Object { `$_.Name + '|' + `$_.Length }"))
  $thereSize = @{}
  foreach ($row in $thereRaw) {
    $bits = "$row".Trim() -split '\|'
    if ($bits.Count -eq 2 -and $bits[0] -match '\.es[pml]$') { $thereSize[$bits[0]] = [int64]$bits[1] }
  }
  # An unreadable folder and an empty one look the same from here, and the
  # difference is 57 plugins going up over a slow link for no reason, or an scp
  # into a path that does not exist. Neither should happen quietly.
  if ($thereSize.Count -eq 0) {
    Write-Host ''
    Write-Host ("  Nothing readable at $remotePlugins on the dev box.") -ForegroundColor Red
    foreach ($row in $thereRaw) { Write-Host ("    " + $row) -ForegroundColor DarkGray }
    throw "could not read the dev server's plugin folder, so there is no way to tell what it already has"
  }

  foreach ($n in $pluginNames) {
    $local = Join-Path $Data $n
    if ($n -eq 'Thornswood-Content.esp' -and (Test-Path -LiteralPath $ours)) { $local = $ours }
    if (-not $thereSize.ContainsKey($n)) {
      if (Test-Path -LiteralPath $local) { $sendPlugins += $local }
      else { throw "the load order names $n, the dev server does not have it, and it is not at $local either" }
      continue
    }
    # There already. A plugin this machine does not have is left alone: the
    # box's copy is then the only copy, and overwriting it with nothing is the
    # one outcome worse than it being stale.
    if (-not (Test-Path -LiteralPath $local)) { continue }
    $localLen = (Get-Item -LiteralPath $local).Length
    if ($localLen -ne $thereSize[$n]) {
      $sendPlugins += $local
      $changed += ('{0}  {1:N0} -> {2:N0} bytes' -f $n, $thereSize[$n], $localLen)
    }
  }

  Write-Host ''
  Write-Host ('  load order: {0} plugins, paths rewritten to {1}' -f $pluginNames.Count, $remotePlugins) -ForegroundColor DarkGray
  if ($sendPlugins.Count) {
    Write-Host ('  {0} plugin(s) will go up before the restart:' -f $sendPlugins.Count) -ForegroundColor Yellow
    foreach ($p in $sendPlugins) { Write-Host ('    ' + (Split-Path $p -Leaf)) -ForegroundColor Yellow }
    foreach ($c in $changed) { Write-Host ('    changed: ' + $c) -ForegroundColor Yellow }
  } else {
    Write-Host '  every plugin the load order names is on the dev server at the same size' -ForegroundColor DarkGray
  }

  # The list goes up as a file of its own. Putting 57 paths inside the settings
  # block below would add some 4,000 characters to something that is base64 of
  # UTF-16 on a command line, which is the length problem Remote() exists to
  # work around; and the dev settings file is edited in place here rather than
  # written from a local build, which is the rule this script is built on.
  $orderFile = Join-Path $env:TEMP 'thornswood-dev-loadorder.txt'
  [IO.File]::WriteAllText($orderFile, (($pluginNames -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
  $farOrder = 'C:/Windows/Temp/thornswood-dev-loadorder.txt'
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

if ($LoadOrder) {
  foreach ($p in $sendPlugins) {
    $n = Split-Path $p -Leaf
    & scp @ssh $p "$User@${Vps}:$remotePlugins/$n"
    if ($LASTEXITCODE -ne 0) { throw "scp failed for plugin $n" }
    Write-Host "  plugins/$n"
  }
  & scp @ssh $orderFile "$User@${Vps}:$farOrder"
  if ($LASTEXITCODE -ne 0) { throw 'scp failed for the load order list' }
  Write-Host ('  the load order list, {0} plugins' -f $pluginNames.Count)
}

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
# AND THE START POINT MOVES WITH THE LOAD ORDER, added 23 September.
#
# The block below rewrites loadOrder on the dev box whenever the build's
# order differs from the one up there. startPoints sits in the same file and
# holds a form id, and a form id is fileIndex * 0x01000000 + local id, so
# moving the load order under it silently points it at a different plugin,
# or at no plugin at all.
#
# That is what happened. The dev settings were written on 22 September when
# Skyrim Unbound.esp was at index 58; the order moved and Unbound is at 54
# there now, in a list of 57. Every new character on dev died at login with
#   Error: FromFormId failed due to invalid file index 58  (spawn.ts:38)
# and the client showed its OOPS box with no way to tell what was wrong.
# Patrick hit it on 23 September at 18:30.
#
# The index is recomputed here from whatever load order this run leaves on
# the box, and only the index: the local id is kept exactly as it was, so
# this fixes a moved plugin and never decides where the creation room is.
# Deploy-Gamemode.ps1 computes the same thing the same way for the live
# server, which is why live was right and dev was not.
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
`$wantOrder = `$false
`$newOrder = @()
`$orderPath = '$farOrder'
if (`$orderPath -and (Test-Path `$orderPath)) {
  `$names = @(Get-Content `$orderPath | ForEach-Object { `$_.Trim() } | Where-Object { `$_ })
  if (`$names.Count) {
    `$newOrder = @(`$names | ForEach-Object { '$remotePlugins/' + `$_ })
    `$oldOrder = @(`$s.loadOrder)
    if ((`$oldOrder -join '|') -ne (`$newOrder -join '|')) {
      `$wantOrder = `$true
      'the load order moves from ' + `$oldOrder.Count + ' plugins to ' + `$newOrder.Count
      `$n = [Math]::Max(`$oldOrder.Count, `$newOrder.Count)
      for (`$i = 0; `$i -lt `$n; `$i++) {
        `$a = ''; `$b = ''
        if (`$i -lt `$oldOrder.Count) { `$a = Split-Path `$oldOrder[`$i] -Leaf }
        if (`$i -lt `$newOrder.Count) { `$b = Split-Path `$newOrder[`$i] -Leaf }
        if (`$a -ne `$b) { '  they first differ at position ' + `$i + ': had ' + `$a + ', now ' + `$b; break }
      }
    } else {
      'the load order is already the ' + `$newOrder.Count + ' the build names'
    }
  }
}
# The start point, against the order this run leaves behind.
`$wantStart = `$false
`$startWas = 0
`$startWant = 0
`$order2 = @(`$(if (`$wantOrder) { `$newOrder } else { @(`$s.loadOrder) }))
`$unb = -1
for (`$i = 0; `$i -lt `$order2.Count; `$i++) {
  if ((Split-Path `$order2[`$i] -Leaf) -eq 'Skyrim Unbound.esp') { `$unb = `$i; break }
}
`$pt = @(`$s.startPoints)[0]
if (`$pt -and `$unb -ge 0) {
  `$startWas = [int64]`$pt.worldOrCell
  `$startWant = (`$unb * 0x01000000) + (`$startWas -band 0x00FFFFFF)
  if (`$startWas -ne `$startWant) {
    `$wantStart = `$true
    'the start point names file index ' + [int](`$startWas -shr 24) +
      ', and Skyrim Unbound.esp is at ' + `$unb + ' in this load order. A new character cannot spawn.'
  }
} elseif (-not `$pt) { 'no startPoints in the dev settings, leaving that alone' }
elseif (`$unb -lt 0) { 'Skyrim Unbound.esp is not in this load order, leaving the start point alone' }

# A byte order mark counts as needing a rewrite even when the number is
# already right. The run on 18 September set the value AND wrote a mark, so
# a second run that only compared the number would have said 'already 7789'
# and left the server unable to parse its own settings.
`$bom = `$false
try { `$bom = ([IO.File]::ReadAllBytes(`$p)[0] -eq 0xEF) } catch { }
if (`$bom) { 'the settings file starts with a byte order mark, rewriting it without one' }
if (`$have -eq $VoicePort -and -not `$bom -and -not `$wantEquip -and -not `$wantOrder -and -not `$wantStart) {
  'thornswoodVoicePort is already $VoicePort, both equipment checks are already off, and the load order is already right'
} else {
  Copy-Item `$p (`$p + '.before-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
  if (`$wantOrder) { `$s | Add-Member -NotePropertyName loadOrder -NotePropertyValue `$newOrder -Force }
  if (`$wantStart) {
    `$pt.worldOrCell = ('0x{0:X8}' -f `$startWant)
    `$s | Add-Member -NotePropertyName startPoints -NotePropertyValue @(`$pt) -Force
    'start point moved to 0x{0:X8}, index {1}' -f `$startWant, `$unb
  }
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
            ', unknown item vetoes ' + `$back.equipmentInventoryCheckEnabled +
            ', load order ' + @(`$back.loadOrder).Count + ' plugins' +
            ', start point ' + @(`$back.startPoints)[0].worldOrCell }
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
# The manifest is what the client actually compares its game against, and the
# server writes it at startup out of the settings above. Saying the settings
# were written is not the same as saying the server agreed to them.
`$dataDir = 'data'
if (`$s.dataDir) { `$dataDir = [string]`$s.dataDir }
`$mf = Join-Path (Join-Path '$rootWin' `$dataDir) 'manifest.json'
if (Test-Path `$mf) {
  try {
    `$m = Get-Content `$mf -Raw | ConvertFrom-Json
    'manifest: ' + @(`$m.loadOrder).Count + ' plugins, written ' + (Get-Item `$mf).LastWriteTime
  } catch { 'manifest: UNREADABLE, ' + `$_.Exception.Message }
} else { 'manifest: not written yet' }
`$tmpOrder = '$farOrder'
if (`$tmpOrder -and (Test-Path `$tmpOrder)) { Remove-Item -LiteralPath `$tmpOrder -Force -EA SilentlyContinue }
if (Test-Path '$rootWin\server.log') {
  '--- server.log, last 15 ---'
  Get-Content '$rootWin\server.log' -Tail 15
}
"@ | ForEach-Object { "  $_" }
