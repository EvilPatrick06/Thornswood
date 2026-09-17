<#
  Watch-Services.ps1

      .\tools\Watch-Services.ps1            what the watcher has seen lately
      .\tools\Watch-Services.ps1 -Install   put the watcher on the server
      .\tools\Watch-Services.ps1 -Remove    take it off again

  Everything runs on one box now. The website, the game, the bot and the voice
  server are four things that can stop on their own, and nothing up there
  notices when one does. Somebody turns up, cannot get in, and the first you
  hear about it is a message in Discord hours later.

  This puts a small watcher on the server that looks at all four every five
  minutes and starts back up whatever is not answering.

  It will not fight a service that is properly broken. Three restarts of the
  same thing inside an hour and it stops trying and writes that it needs a
  look, because a thing that crashes on startup restarted forever is a thing
  nobody ever finds out about.

  What it checks:
    website   answers on 3001, which is what Caddy puts on 443
    game      answers on 3000, which is the resources the client pulls
    voice     answers on 7778
    bot       a python process is alive with the bot script in its command line

  The game's own traffic is UDP on 7777 and there is nothing to connect to, so
  3000 stands in for it. They are the same process, so if one is gone both are.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Root = 'C:\Thornswood-Watch',
  [string]$Task = 'Thornswood Watch',
  [int]$Lines   = 25,
  [switch]$Install,
  [switch]$Remove,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) {
  Write-Host ''
  Write-Host "STOP. $m" -ForegroundColor Red
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}

function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" 2>&1
}

Write-Host ''
Write-Host '  THORNSWOOD  -  keep the four services up' -ForegroundColor White

# The watcher itself. Single quoted, so nothing in here is touched on the way
# up. It goes to the server as base64 and is written out there as a file,
# which keeps every quote and backslash exactly as written.
$watcher = @'
$ErrorActionPreference = 'Continue'
$root = 'C:\Thornswood-Watch'
$log  = Join-Path $root 'watch.log'
$hist = Join-Path $root 'restarts.txt'
if (-not (Test-Path $root)) { $null = New-Item -ItemType Directory -Path $root -Force }

function Note($line) {
  $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Add-Content -LiteralPath $log -Value ($stamp + '  ' + $line)
}

function Answers($port) {
  try {
    $c = New-Object Net.Sockets.TcpClient
    $ok = $c.BeginConnect('127.0.0.1', $port, $null, $null).AsyncWaitHandle.WaitOne(3000)
    $up = $ok -and $c.Connected
    $c.Close()
    return $up
  } catch { return $false }
}

function BotAlive() {
  foreach ($p in (Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -EA SilentlyContinue)) {
    if ("$($p.CommandLine)" -match 'Thornswood-Bot') { return $true }
  }
  return $false
}

# How many times each service has been restarted in the last hour. A service
# that will not stay up is a service to stop restarting and start reading.
$recent = @{}
if (Test-Path $hist) {
  foreach ($line in (Get-Content -LiteralPath $hist -EA SilentlyContinue)) {
    $bits = "$line" -split '\|'
    if ($bits.Count -ne 2) { continue }
    $when = [datetime]::MinValue
    if (-not [datetime]::TryParse($bits[0], [ref]$when)) { continue }
    if (((Get-Date) - $when).TotalMinutes -gt 60) { continue }
    if (-not $recent.ContainsKey($bits[1])) { $recent[$bits[1]] = 0 }
    $recent[$bits[1]] = $recent[$bits[1]] + 1
  }
}

$checks = @(
  @{ Name = 'website'; Task = 'Thornswood Docs';   Port = 3001 },
  @{ Name = 'game';    Task = 'Thornswood Server'; Port = 3000 },
  @{ Name = 'voice';   Task = 'Thornswood Voice';  Port = 7778 },
  @{ Name = 'bot';     Task = 'Thornswood Bot';    Port = 0    }
)

$fresh = @()
foreach ($c in $checks) {
  $up = if ($c.Port -eq 0) { BotAlive } else { Answers $c.Port }
  if ($up) { continue }

  $already = 0
  if ($recent.ContainsKey($c.Name)) { $already = $recent[$c.Name] }
  if ($already -ge 3) {
    Note ($c.Name + ' is still down after ' + $already + ' restarts this hour. Leaving it. This one needs a look.')
    continue
  }

  Note ($c.Name + ' is not answering. Starting ' + $c.Task)
  $null = & schtasks /run /tn $c.Task 2>&1
  $rc = $LASTEXITCODE
  $fresh += ((Get-Date).ToString('o') + '|' + $c.Name)

  if ($rc -ne 0) {
    Note ($c.Name + ' could not be started. schtasks exited with ' + $rc + '. Is the task called ' + $c.Task + ' ?')
    continue
  }

  Start-Sleep -Seconds 25
  $up2 = if ($c.Port -eq 0) { BotAlive } else { Answers $c.Port }
  if ($up2) { Note ($c.Name + ' is back') }
  else { Note ($c.Name + ' did not come back within 25 seconds') }
}

if ($fresh.Count -gt 0) { Add-Content -LiteralPath $hist -Value $fresh }

# Keep the two files from growing forever.
foreach ($f in @($log, $hist)) {
  if (Test-Path $f) {
    $all = @(Get-Content -LiteralPath $f -EA SilentlyContinue)
    if ($all.Count -gt 2000) {
      Set-Content -LiteralPath $f -Value ($all[-1000..-1]) -Encoding UTF8
    }
  }
}
'@

# ------------------------------------------------------------------ off ---
if ($Remove) {
  Head 'Taking it off'
  $out = Remote @"
`$ErrorActionPreference = 'Continue'
`$null = & schtasks /delete /tn '$Task' /f 2>&1
if (`$LASTEXITCODE -eq 0) { 'the task is gone' } else { 'there was no task called $Task' }
'the log is still at $Root\watch.log if you want to read it'
"@
  foreach ($l in $out) { Say "  $l" }
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

# ------------------------------------------------------------------- on ---
if ($Install) {
  Head 'Putting it on the server'

  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($watcher))

  $out = Remote @"
`$ErrorActionPreference = 'Continue'
if (-not (Test-Path '$Root')) { `$null = New-Item -ItemType Directory -Path '$Root' -Force }
[IO.File]::WriteAllBytes('$Root\watch.ps1', [Convert]::FromBase64String('$b64'))
'wrote     $Root\watch.ps1  ' + (Get-Item '$Root\watch.ps1').Length + ' bytes'

# Every five minutes, as SYSTEM, so it keeps going when nobody is logged in.
# The path has no spaces in it, so the command needs no quotes inside the
# quotes, which is the usual way this line goes wrong.
`$null = & schtasks /create /tn '$Task' /sc minute /mo 5 /ru SYSTEM /rl HIGHEST /f /tr 'powershell -NoProfile -ExecutionPolicy Bypass -File $Root\watch.ps1' 2>&1
if (`$LASTEXITCODE -eq 0) { 'made      the task, every five minutes' } else { 'FAILED    schtasks exited with ' + `$LASTEXITCODE }

# Run it once now so the log has something in it and any problem shows up
# here rather than in five minutes when nobody is watching.
`$null = & schtasks /run /tn '$Task' 2>&1
Start-Sleep -Seconds 8
if (Test-Path '$Root\watch.log') {
  'first run:'
  Get-Content '$Root\watch.log' -Tail 10 | ForEach-Object { '  ' + `$_ }
}
else { 'first run wrote nothing, which means all four were answering' }
"@

  foreach ($l in $out) {
    $c = 'Gray'
    if ("$l" -match '^FAILED') { $c = 'Red' }
    if ("$l" -match '^(wrote|made)') { $c = 'Green' }
    Say "  $l" $c
  }

  Head 'From now on'
  Say '  Anything that stops gets started again within five minutes.' 'DarkGray'
  Say '  Run this script with no switches to see what it has been doing.' 'DarkGray'
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

# -------------------------------------------------------------- report ---
Head 'Right now'
$out = Remote @"
`$ErrorActionPreference = 'Continue'
function Answers(`$port) {
  try {
    `$c = New-Object Net.Sockets.TcpClient
    `$ok = `$c.BeginConnect('127.0.0.1', `$port, `$null, `$null).AsyncWaitHandle.WaitOne(3000)
    `$up = `$ok -and `$c.Connected
    `$c.Close()
    return `$up
  } catch { return `$false }
}
`$bot = `$false
foreach (`$p in (Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -EA SilentlyContinue)) {
  if ("`$(`$p.CommandLine)" -match 'Thornswood-Bot') { `$bot = `$true }
}
'website   ' + `$(if (Answers 3001) { 'up' } else { 'DOWN' })
'game      ' + `$(if (Answers 3000) { 'up' } else { 'DOWN' })
'voice     ' + `$(if (Answers 7778) { 'up' } else { 'DOWN' })
'bot       ' + `$(if (`$bot) { 'up' } else { 'DOWN' })
`$t = & schtasks /query /tn '$Task' /fo list 2>`$null
if (`$LASTEXITCODE -eq 0) { 'watcher   installed' } else { 'watcher   NOT installed. Run this with -Install' }
"@
foreach ($l in $out) {
  $c = 'Gray'
  if ("$l" -match 'DOWN|NOT installed') { $c = 'Red' }
  if ("$l" -match '\bup$|installed$') { $c = 'Green' }
  Say "  $l" $c
}

Head "Last $Lines things the watcher saw"
$out = Remote @"
`$ErrorActionPreference = 'Continue'
if (Test-Path '$Root\watch.log') {
  `$all = @(Get-Content '$Root\watch.log' -EA SilentlyContinue)
  if (`$all.Count -eq 0) { 'nothing yet, which means nothing has gone down' }
  else { `$all | Select-Object -Last $Lines }
}
else { 'no log yet' }
"@
foreach ($l in $out) { Say "  $l" 'DarkGray' }

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
