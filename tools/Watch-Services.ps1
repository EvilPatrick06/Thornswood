<#
  Watch-Services.ps1

      .\tools\Watch-Services.ps1            what the watcher has seen lately
      .\tools\Watch-Services.ps1 -Install   put the watcher on the server
      .\tools\Watch-Services.ps1 -Remove    take it off again

  Everything runs on one box now. The website, the game, the bot and the voice
  server are four things that can stop on their own, and nothing up there
  notices when one does. Somebody turns up, cannot get in, and the first you
  hear about it is a message in Discord hours later.

  This puts a small watcher on the server that looks at all of them every
  five minutes and starts back up whatever is not answering.

  It will not fight a service that is properly broken. Three restarts of the
  same thing inside an hour and it stops trying and writes that it needs a
  look, because a thing that crashes on startup restarted forever is a thing
  nobody ever finds out about.

  Somebody is told. The bot on the same box reads watch.log every minute and
  says each "needs a look", "could not be started" and "did not come back" in
  the staff channel, once per outage, and "needs a look" again every hour the
  service stays down (watch_services in tools\discord\bot.py). An outage is
  over when this writes "is back", or when one of its runs finds the service
  answering and so writes nothing about it, which is the only sign a fix made
  by hand ever leaves. The hourly repeat covers a fix that falls over again
  before the next run. tools\discord\test-watch-services.py renders the Note()
  lines below and checks the bot still recognises them, so change the words
  and that fails.

  What it checks:
    caddy     https://thornswood.net answers, which is the only one of these
              a visitor actually touches. Asked over the public name and the
              certificate on purpose: on 21 September Caddy was stopped for
              hours while node sat there answering 3001 perfectly, and a
              check of 3001 says everything is fine right through that.
    website   answers on 3001, which is what Caddy puts on 443
    game      answers on 3000, which is the resources the client pulls
    voice     answers on 7778
    bot       a python process is alive with the bot script in its command line
    dev game  answers on 7788, the dev server's resources port
    dev voice answers on 7789
    disk      free space on C:, which every one of the above shares. Under
              twenty percent it writes DISK LOW, under ten DISK CRITICAL,
              once when the line is crossed and once when it comes back. It
              restarts nothing for it, because a restart frees nothing.

  The two dev ones are here because the box has been watching them since 16
  September and this file did not know. vps-dev-instance.ps1, which runs ON
  the VPS, appends them to the installed watch.ps1 in place. So the copy up
  there watched six things, the copy here watched four, and -Install would
  have written the shorter list over the longer one and taken the dev server
  and dev voice off the watchdog with nothing said. That script checks for
  'Thornswood Dev Server' before it patches, so with them here it now finds
  its work already done and says so.

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
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=accept-new')

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
  $cmd = "powershell -NoProfile -EncodedCommand $e"

  # A long script does not fit on a command line, and nothing says so.
  #
  # sshd on Windows hands the command to cmd.exe, which stops at 8,191
  # characters. Base64 of UTF-16 is about 2.7 times the script, so a block of
  # any size arrives cut in half and PowerShell then complains about a brace or
  # a token in a script nobody can see. Deploy-Docs.ps1 hit this on 17 Sep and
  # solved it; every other script here carried the short version that cannot,
  # and on 20 Sep this one truncated at 10,252 characters and reported
  # "Unexpected token '$?'" about a line fifteen above the one that was cut.
  # This is that fix, copied across so the sixteen scripts that talk to the VPS
  # all behave the same way.
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
    # And bare, with no quotes round it; the path above is ours and has no
    # spaces. Measured on this machine on 24 September, not on the VPS: bare
    # runs whether cmd.exe or Windows PowerShell hands the line on, and the
    # old form, the path in single quotes, fails under cmd.exe. The old form
    # did run on the VPS on 20 and 21 September, so which shell sshd uses
    # there is not known, and bare is the form that works under either.
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}

Write-Host ''
Write-Host '  THORNSWOOD  -  keep the services up' -ForegroundColor White

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

# Caddy holds 443 and is the only thing here a visitor touches. It is asked
# over the public name rather than over a loopback port, because the failure
# this is for looks perfect from inside: on 21 September Caddy was stopped and
# staying stopped while node answered 3001 all night.
#
# ANY HTTP ANSWER COUNTS, including a 502. A 502 is Caddy up and something
# behind it down, and what is behind it has its own check on the line below.
# Treating a 502 as Caddy being down would restart the wrong thing.
function SiteAnswers($url) {
  try {
    $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 5
    return $true
  } catch {
    try { if ($_.Exception.Response) { return $true } } catch { }
    return $false
  }
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

# Caddy first, because it is the one the outside world meets and because a
# website answering on 3001 means nothing while 443 is unserved.
$checks = @(
  @{ Name = 'caddy';   Task = 'Thornswood Web';    Port = 0; Url = 'https://thornswood.net/' },
  @{ Name = 'website'; Task = 'Thornswood Docs';   Port = 3001 },
  @{ Name = 'game';    Task = 'Thornswood Server'; Port = 3000 },
  @{ Name = 'voice';   Task = 'Thornswood Voice';  Port = 7778 },
  @{ Name = 'bot';     Task = 'Thornswood Bot';    Port = 0    },
  # The dev pair. The dev game server's own traffic is UDP on 7787 and
  # cannot be connected to, so its resources port stands in, exactly as
  # 3000 does for the live one.
  @{ Name = 'dev game';  Task = 'Thornswood Dev Server'; Port = 7788 },
  @{ Name = 'dev voice'; Task = 'Thornswood Dev Voice';  Port = 7789 }
)

# One place that knows how each of them is asked.
function IsUp($c) {
  if ($c.ContainsKey('Url')) { return (SiteAnswers $c.Url) }
  if ($c.Port -eq 0) { return (BotAlive) }
  return (Answers $c.Port)
}

$fresh = @()
foreach ($c in $checks) {
  if (IsUp $c) { continue }

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

  # Caddy's first start after a gap waits on its certificate, so it is given
  # longer before the watcher decides it did not come back.
  Start-Sleep -Seconds $(if ($c.ContainsKey('Url')) { 45 } else { 25 })
  if (IsUp $c) { Note ($c.Name + ' is back') }
  else { Note ($c.Name + ' did not come back in time') }
}

if ($fresh.Count -gt 0) { Add-Content -LiteralPath $hist -Value $fresh }

# Free space. Everything on this box shares one volume: both game servers, the
# site and its uploads, voice, the bot, every log and every payload.
# MOVING-THE-SERVER.md has it at 80 GB with 81 percent free, read off the box
# on 15 September, and all of those only grow. A full disk is not one service
# down, it is every service at once. From the To Do List: "Free space is a
# first-class alert, usually at twenty percent and again at ten, because it is
# the one resource whose exhaustion is total rather than partial."
#
# It is its own check and not a line in $checks because restarting a service
# frees nothing, so nothing here restarts anything. It is said once when a
# line is crossed and once when it comes back, not on every five minute run:
# disk.txt beside restarts.txt holds which side of the lines the last run saw.
$diskState    = Join-Path $root 'disk.txt'
$diskLow      = 20
$diskCritical = 10

# The same two numbers Get-PSDrive C shows by hand on the box, so a person
# checking reads what this read. $null when the drive cannot be read, and then
# nothing is said and nothing is remembered rather than a guess.
function DiskNow() {
  try {
    $d = Get-PSDrive -Name $root.Substring(0, 1) -PSProvider FileSystem -EA Stop
    $free = [double]$d.Free
    $size = [double]$d.Used + $free
    if ($size -le 0) { return $null }
    return @{ Free = $free; Size = $size }
  } catch { return $null }
}

# Which side of the lines a free percentage is on. On the way back up it has
# to clear a line by a whole point before it counts, so a disk sitting right
# on twenty percent, a log trimmed and then growing again, is one line in
# watch.log and not one every five minutes.
function DiskLevel($pct, $was) {
  if ($pct -lt $diskCritical) { return 'critical' }
  if ($was -eq 'critical' -and $pct -lt ($diskCritical + 1)) { return 'critical' }
  if ($pct -lt $diskLow) { return 'low' }
  if (($was -eq 'low' -or $was -eq 'critical') -and $pct -lt ($diskLow + 1)) { return 'low' }
  return 'ok'
}

function DiskCheck($free, $size) {
  $pct   = [math]::Round(100.0 * $free / $size, 1)
  $where = $root.Substring(0, 2)
  $room  = '' + [math]::Round($free / 1GB, 1) + ' GB of ' + [math]::Round($size / 1GB, 1) + ' GB'
  $was = ''
  if (Test-Path -LiteralPath $diskState) {
    $was = ('' + (Get-Content -LiteralPath $diskState -TotalCount 1 -EA SilentlyContinue)).Trim()
  }
  if (@('ok', 'low', 'critical') -notcontains $was) { $was = '' }
  $now = DiskLevel $pct $was
  if ($now -ne $was) {
    if ($now -eq 'critical') {
      Note ('DISK CRITICAL: ' + $pct + '% free on ' + $where + ', ' + $room + '. Under ' + $diskCritical + '%. When it fills, every service on this box stops at once. Clear old logs, uploads or payloads now. Nothing was restarted, because a restart frees nothing.')
    } elseif ($now -eq 'low' -and $was -eq 'critical') {
      Note ('disk up to ' + $pct + '% free on ' + $where + ', ' + $room + '. Out of critical, still under ' + $diskLow + '%.')
    } elseif ($now -eq 'low') {
      Note ('DISK LOW: ' + $pct + '% free on ' + $where + ', ' + $room + '. Under ' + $diskLow + '%. Everything on this box shares this one volume, so this is the whole box and not one service. Nothing was restarted, because a restart frees nothing.')
    } elseif ($was -ne '') {
      Note ('disk back to ' + $pct + '% free on ' + $where + ', ' + $room + '.')
    }
    Set-Content -LiteralPath $diskState -Value $now -Encoding ASCII
  }
  return ('disk      ' + $pct + '% free on ' + $where + ', ' + $room + ' (' + $now + ')')
}

# Printed, so the file run by hand on the box shows what it read.
$space = DiskNow
if ($space) { DiskCheck $space.Free $space.Size }
else { 'disk      could not be read' }

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
# Asked the way a visitor asks, for the reason in the header. Any HTTP
# answer counts, a 502 included: that is Caddy up with something behind it
# down, and the line under it says which.
function SiteAnswers(`$url) {
  try {
    `$null = Invoke-WebRequest -Uri `$url -UseBasicParsing -TimeoutSec 10 -MaximumRedirection 5
    return `$true
  } catch {
    try { if (`$_.Exception.Response) { return `$true } } catch { }
    return `$false
  }
}
`$bot = `$false
foreach (`$p in (Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -EA SilentlyContinue)) {
  if ("`$(`$p.CommandLine)" -match 'Thornswood-Bot') { `$bot = `$true }
}
'caddy     ' + `$(if (SiteAnswers 'https://thornswood.net/') { 'up' } else { 'DOWN' })
'website   ' + `$(if (Answers 3001) { 'up' } else { 'DOWN' })
'game      ' + `$(if (Answers 3000) { 'up' } else { 'DOWN' })
'voice     ' + `$(if (Answers 7778) { 'up' } else { 'DOWN' })
'bot       ' + `$(if (`$bot) { 'up' } else { 'DOWN' })
'dev game  ' + `$(if (Answers 7788) { 'up' } else { 'DOWN' })
'dev voice ' + `$(if (Answers 7789) { 'up' } else { 'DOWN' })
# Free space right now, and LOW or CRITICAL when the watcher's last run found
# it under a line. The twenty and the ten are kept in the watcher only, so
# this reads its verdict from disk.txt rather than holding a second copy.
`$d = Get-PSDrive -Name '$($Root.Substring(0, 1))' -PSProvider FileSystem -EA SilentlyContinue
`$lvl = ''
if (Test-Path '$Root\disk.txt') { `$lvl = ('' + (Get-Content '$Root\disk.txt' -TotalCount 1 -EA SilentlyContinue)).Trim() }
if (`$d -and ([double]`$d.Used + `$d.Free) -gt 0) { 'disk      ' + [math]::Round(100.0 * `$d.Free / ([double]`$d.Used + `$d.Free), 1) + '% free, ' + [math]::Round(`$d.Free / 1GB, 1) + ' GB' + `$(if (`$lvl -eq 'low' -or `$lvl -eq 'critical') { ', ' + `$lvl.ToUpper() } else { '' }) }
else { 'disk      could not be read' }
`$t = & schtasks /query /tn '$Task' /fo list 2>`$null
if (`$LASTEXITCODE -eq 0) { 'watcher   installed' } else { 'watcher   NOT installed. Run this with -Install' }
"@
foreach ($l in $out) {
  $c = 'Gray'
  if ("$l" -match 'DOWN|NOT installed|LOW$|CRITICAL$') { $c = 'Red' }
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
