<#
  Swap.ps1

  Stages a deploy beside what is running, checks it there, and only then swaps it in, keeping what it replaced for a one-command put-back.

  Dot-sourced by the scripts that change something running on the VPS:
  Deploy-Server.ps1 and Deploy-DevGamemode.ps1 (the game servers, the first
  pair of blocks below), and Deploy-Docs.ps1, Install-Voice.ps1 and
  Install-Bot.ps1 (the site, the voice service and the bot, the second pair).
  Install-ThornswoodServer.ps1 does the same for a whole server folder, on the
  box itself, with folders beside the root instead of files inside it.

  WHY, issue #446: "A failed publish deletes the live server before checking
  the new one." Measured on 28 September, every one of those scripts but
  Deploy-Server wrote over the running copy first and found out afterwards
  whether the new one worked, and none of them could put the old one back.
  The shape Deploy-Server was given for entry 209 is the one they all use now:

    1. Every new file goes up into <root>\.stage-<stamp> while the old one
       runs. A failed copy stops the run with nothing touched.
    2. The box checks the stage: every file hashed against what left this
       machine, the settings parsed, the program parsed (node --check, or
       Python's own parser). A refusal clears the stage and stops nothing.
    3. Only then the stop, one rename per file (what it replaces goes into
       <root>\.prev-<stamp>), and the same for a directory named in $Dirs,
       the start, and a check that it answers.
    4. If a rename fails, or it does not answer, the old files go back, the
       old one is started again, and the run says SWAP ROLLED BACK and exits 1.

  The newest two .prev folders are kept, and the newest two .undone ones
  (Patrick, 29 Sep, #1121: two, not three). -PutBack on each of those
  scripts puts the newest one back the same checked way, and keeps what it
  took out in <root>\.undone-<stamp>, so a put-back can itself be put back by
  hand.

  What runs on the box is kept here as single quoted text, so what goes up is
  plain PowerShell a person can read and the harnesses can run against a
  scratch folder (tests\test-deploy-server-swap.ps1, tests\test-deploy-swaps.ps1).
  Keep it ASCII: a laptop on PowerShell 7 writes the file Remote sends without
  a byte order mark, and Windows PowerShell 5.1 at the far end reads it as ANSI.

  $Wait in the swap is how long both ports may take. Left off on the caller,
  it is the shared ceiling in ServerReadyWait.ps1, derived from measured Live
  and Dev starts (#1938).
#>

. (Join-Path $PSScriptRoot 'ServerReadyWait.ps1')
# Restore-SwapRecord sends its lock for the deploy store (Lock-Folder.ps1).
. (Join-Path $PSScriptRoot '..\vps\Lock-Folder.ps1')

# ==== deploy-server remote blocks ====
#
# THE TWO HALVES THAT RUN ON THE BOX, KEPT HERE SO A HARNESS CAN RUN THEM TOO.
#
# Written for Deploy-Server.ps1 and moved here for issue #446, so the dev
# server's deploy (Deploy-DevGamemode.ps1) stages, checks and swaps with the
# same two blocks rather than a copy of them.
#
# Entry 209 on the To Do List: "Upload to a staging path, verify there, the
# shortest possible stop, an atomic rename, a real health check." And: "This
# is the script that runs most often and has the least protection." Until
# then it stopped the server, copied over the running folder, waited six
# seconds, and printed SERVER IS NOT LISTENING without exiting non-zero,
# putting anything back, asking the resources port or checking the load order
# on the box.
#
# $checkBlock runs while the server is still up and touches nothing but the
# stage. $swapBlock is the only part that stops anything, and it does the
# stop, the renames, the start, the health check and the way back in one
# script, so a connection that drops between two ssh calls cannot leave the
# server stopped with half its files moved.
#
# Both are single quoted and take their values from the lines SwapVars puts in
# front of them, so what goes to the box is plain PowerShell a person can read
# and tests\test-deploy-server-swap.ps1 can run against a scratch folder. Each
# ends with one line the caller reads: STAGE OK or STAGE REFUSED, and SWAP OK,
# SWAP ROLLED BACK, SWAP REFUSED or SWAP FAILED. A line and not an exit code,
# because Remote sends a long script as a file and the exit code left behind
# is the one from deleting that file.
#
# Keep them ASCII. A laptop on PowerShell 7 writes that file without a byte
# order mark, and Windows PowerShell 5.1 at the far end then reads it as ANSI.
#
# $checkBlock calls ServerBuild.ps1, beside this file, whose text is put in
# front of it below the end marker, so the stage's server files are held to
# the record sent with them by the same lines that hold a payload and a build
# (#1214).
$checkBlock = @'
$ProgressPreference = 'SilentlyContinue'
$stageDir = Join-Path $Root $Stage
$bad = @()
# Every file the same as the one that left the laptop, by its hash. An exit
# code from scp says a copy ended, not what arrived.
$sums = @{}
foreach ($rel in @($Want.Keys)) {
  $p = Join-Path $stageDir ($rel -replace '/', '\')
  if (-not (Test-Path -LiteralPath $p)) { $bad += ('did not arrive: ' + $rel); continue }
  $sums[$rel] = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($sums[$rel] -ne $Want[$rel]) { $bad += ('arrived different from what was sent: ' + $rel) }
}
$new = $null
$sp = Join-Path $stageDir 'server-settings.json'
if (Test-Path -LiteralPath $sp) {
  $b = [IO.File]::ReadAllBytes($sp)
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
    $bad += 'server-settings.json starts with a byte order mark, and node will not parse it'
  }
  try { $new = [IO.File]::ReadAllText($sp) | ConvertFrom-Json }
  catch { $bad += ('server-settings.json does not parse: ' + $_.Exception.Message) }
} else { $bad += 'there is no server-settings.json in the stage' }
# The port it runs on now and the port the new settings name must agree. The
# stop picks its process by that port and the health check asks it, so a file
# that moved it would stop one process and then ask about another.
$now = $null
try { $now = [IO.File]::ReadAllText((Join-Path $Root 'server-settings.json')) | ConvertFrom-Json } catch { }
if (-not $now) {
  $bad += ('the settings in ' + $Root + ' cannot be read, so there is no telling which process is this server')
} elseif ($new -and [int]$new.port -ne [int]$now.port) {
  $bad += ('the new settings put this server on port ' + [int]$new.port + ' and it is on ' + [int]$now.port + ' now')
}
# The load order resolution Install-ThornswoodServer.ps1 does, against the
# plugins already here plus the ones in the stage, because a shortened load
# order shifts every index after the gap.
$order = @()
if ($new -and $new.loadOrder) { $order = @($new.loadOrder) }
if ($new -and -not $order.Count) { $bad += 'server-settings.json has no loadOrder' }
$plugins = Join-Path $Root 'plugins'
foreach ($p in $order) {
  $at = ([string]$p) -replace '/', '\'
  if (-not $at) { $bad += 'the load order has an empty entry'; continue }
  $leaf = [IO.Path]::GetFileName($at)
  $staged = ((Split-Path -Parent $at) -eq $plugins) -and (Test-Path -LiteralPath (Join-Path $stageDir ('plugins\' + $leaf)))
  if (-not $staged -and -not (Test-Path -LiteralPath $at)) { $bad += ('the load order names a plugin that is not on disk: ' + $p) }
}
# The gamemode parses on the box too, not only where it was written. Issue
# #446: a gamemode that does not parse stops the server at start, and this is
# the last point at which that costs nothing.
$gm = Join-Path $stageDir 'gamemode.js'
if ($sums.ContainsKey('gamemode.js') -and (Test-Path -LiteralPath $gm)) {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
              [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + $env:Path
  $nd = Get-Command node -CommandType Application -EA SilentlyContinue | Select-Object -First 1
  if (-not $nd) { $bad += 'node is not on this machine, so gamemode.js could not be checked' }
  else {
    $said = @(& $nd.Source --check $gm 2>&1)
    if ($LASTEXITCODE -ne 0) {
      $bad += ('gamemode.js does not parse: ' + ((@($said | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) | Select-Object -First 6) -join ' | '))
    }
  }
}
# Every server file sent is the build the record sent with it names, every
# file the record names was sent, and a server file with no record beside it
# does not go in (#1214). Deploy-Server sends them all together, so the box
# never runs a binary of one build beside the JavaScript half of another.
$forkSent = @($sums.Keys | Where-Object { Test-ThornswoodServerForkFile $_ })
$rp = Join-Path $stageDir 'server-build.json'
if ($sums.ContainsKey('server-build.json') -and (Test-Path -LiteralPath $rp)) {
  try {
    $rec = [IO.File]::ReadAllText($rp) | ConvertFrom-Json
    $forkSums = @{}
    foreach ($k in $forkSent) { $forkSums[$k] = $sums[$k] }
    $bad += @(Get-ThornswoodServerBuildProblems $rec $forkSums 'the stage' 'server-build.json')
  } catch { $bad += ('server-build.json does not parse: ' + $_.Exception.Message) }
} elseif ($forkSent.Count) {
  $bad += ('server files came with no server-build.json to hold them to: ' + ($forkSent -join ', '))
}
if ($bad.Count) {
  foreach ($x in $bad) { 'REFUSED: ' + $x }
  Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue
  'the stage is cleared and the server was not touched'
  'STAGE REFUSED'
} else {
  'the stage checks out: {0} file(s) as sent, {1} plugins in the load order and all on disk, port {2}' -f $Want.Count, $order.Count, [int]$new.port
  'STAGE OK'
}
'@

$swapBlock = @'
$ProgressPreference = 'SilentlyContinue'
$stageDir = Join-Path $Root $Stage
$prevDir  = Join-Path $Root $Prev
$log      = Join-Path $Root 'server.log'
# The task starts the server at priority 4, normal, before every start here
# (#1931, #2015). Only the installer registered it so, and a server put up by
# Deploy-Server or Deploy-DevGamemode kept Task Scheduler's default of 7: on
# 5 Oct 11:47 PM the live server's node ran BelowNormal, with I/O priority 1
# and memory priority 2, after a deploy of the release that fixed it. Only
# the priority changes; the task keeps everything else it has.
function NormalTask {
  $t = Get-ScheduledTask -TaskName $Task -EA SilentlyContinue
  if (-not $t -or $t.Settings.Priority -eq 4) { return }
  $was = $t.Settings.Priority
  $t.Settings.Priority = 4
  try { $t | Set-ScheduledTask -EA Stop | Out-Null; 'the task starts the server at priority 4 now, not ' + $was }
  catch { 'could not set the task to priority 4: ' + $_.Exception.Message }
}
$new      = [IO.File]::ReadAllText((Join-Path $stageDir 'server-settings.json')) | ConvertFrom-Json
# The check has already refused a port that moves, so this is the port the
# running server is on and the one the new one will be on.
$port     = [int]$new.port
# skymp5-server/ts/ui.ts: 3000 when the game port is 7777, the game port plus
# one otherwise. The same rule Publish-Server and Install-ThornswoodServer use.
$resPort  = if ($port -eq 7777) { 3000 } else { $port + 1 }
$clean    = $true

function Held { @(Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue).Count -gt 0 }

function StopOurs {
  Stop-ScheduledTask -TaskName $Task -EA SilentlyContinue
  # The process on this root's own port and nothing else. Matching every
  # node.exe running skymp5-server took the dev server down with the live one
  # and only started the live one back up.
  'stopping whatever holds UDP ' + $port
  $pids = @()
  $pids += @(Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue | Select-Object -ExpandProperty OwningProcess)
  # Only the UDP port. The line that also stopped whatever listened on the TCP
  # port one above it was copied from the dev script, where that port is the
  # server's own HTTP and belongs to the same process. On the live root it is
  # 7778, which is the voice service, a separate process that carries voice
  # chat, the launcher's character choices and the chat command queue the
  # lockpick fix rides on. Stopping the game server must never take that down.
  foreach ($id in ($pids | Sort-Object -Unique)) {
    if ($id -gt 0) { Stop-Process -Id $id -Force -EA SilentlyContinue; 'stopped pid ' + $id }
  }
  for ($i = 0; $i -lt 20 -and (Held); $i++) { Start-Sleep -Milliseconds 500 }
  Start-Sleep -Seconds 2
  # Once the process is gone, so is any restart.json it never read. The
  # gamemode deletes that file when it reads it, and a process that is down,
  # or whose gamemode failed at load, never does. The next one to start then
  # finds it within a tick and a half and counts down on its own: under
  # -Mode notice a "Pushing a server update in 1 minute" with nothing behind
  # it, and under -Mode restart a kick a minute after boot with no restart
  # behind it. Same gap Deploy-DevGamemode closed on 24 September.
  $d = 'data'
  try {
    $s = [IO.File]::ReadAllText((Join-Path $Root 'server-settings.json')) | ConvertFrom-Json
    if ($s.dataDir) { $d = [string]$s.dataDir }
  } catch { }
  $rq = Join-Path ([IO.Path]::Combine($Root, $d)) 'restart.json'
  if (Test-Path -LiteralPath $rq) {
    try { Remove-Item -LiteralPath $rq -Force -EA Stop; 'removed a restart.json the old process never read' }
    catch { 'COULD NOT REMOVE ' + $rq + ', so the new process will count down on its own: ' + $_.Exception.Message }
  }
}

# Both ports, from the box itself. UDP alone is not enough: the resources port
# is what the launcher and the client fetch from, and it only opens once the
# native server has been built without throwing. $Wait is the shared ceiling
# unless the caller passed -Wait (ServerReadyWait.ps1, #1938).
function Answering {
  $until = (Get-Date).AddSeconds($Wait)
  while ($true) {
    $tcp = $false
    if (Held) {
      try {
        $c = New-Object Net.Sockets.TcpClient
        $null = $c.BeginConnect('127.0.0.1', $resPort, $null, $null).AsyncWaitHandle.WaitOne(500)
        $tcp = $c.Connected
        $c.Close()
      } catch { }
    }
    if ($tcp) { return $true }
    if ((Get-Date) -gt $until) { return $false }
    Start-Sleep -Milliseconds 700
  }
}

# A rename on one volume, retried, because a process that has just been told
# to stop does not always let go of its files the same instant.
function Shift([string]$from, [string]$to) {
  for ($i = 0; $i -lt 10; $i++) {
    try {
      $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $to))
      [IO.File]::Move($from, $to)
      return $true
    } catch { Start-Sleep -Milliseconds 500 }
  }
  return $false
}

function PutBack {
  $rels = @($Want.Keys)
  [array]::Reverse($rels)
  foreach ($rel in $rels) {
    $r = $rel -replace '/', '\'
    $at = Join-Path $Root $r
    if ($placed -contains $rel) {
      if (-not (Shift $at (Join-Path $stageDir $r))) { 'COULD NOT TAKE THE NEW ' + $rel + ' BACK OUT'; $script:clean = $false; continue }
    }
    if ($aside -contains $rel) {
      if (-not (Shift (Join-Path $prevDir $r) $at)) { 'COULD NOT PUT THE OLD ' + $rel + ' BACK'; $script:clean = $false }
    }
  }
}

if (-not $port) {
  'the staged settings name no port, so nothing was stopped'
  Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue
  'SWAP REFUSED'
  exit 1
}
StopOurs
if (Held) {
  'UDP ' + $port + ' is still held by pid ' + @(Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue)[0].OwningProcess + ' after the stop, so nothing was swapped'
  Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue
  'SWAP REFUSED'
  exit 1
}

$placed = @()
$aside = @()
$moved = $true
foreach ($rel in @($Want.Keys)) {
  $r = $rel -replace '/', '\'
  $at = Join-Path $Root $r
  if (Test-Path -LiteralPath $at) {
    if (-not (Shift $at (Join-Path $prevDir $r))) { 'could not move the old ' + $rel + ' aside'; $moved = $false; break }
    $aside += $rel
  }
  if (-not (Shift (Join-Path $stageDir $r) $at)) { 'could not move the new ' + $rel + ' into place'; $moved = $false; break }
  $placed += $rel
}

# READ BACK, BEFORE ANYTHING STARTS (#1222), when the caller named the keys its
# release is meant to change ($ReleaseKeys, Deploy-Server.ps1 from
# ServerSettings.ps1): every other key of the settings now in place must be
# the one the server had. The staged file was carried from the running one,
# so a difference means that file moved in between, and the old files go back.
if ($moved -and $null -ne $ReleaseKeys -and $placed -contains 'server-settings.json') {
  $was = $null
  $got = $null
  try { $was = [IO.File]::ReadAllText((Join-Path $prevDir 'server-settings.json')) | ConvertFrom-Json } catch { }
  try { $got = [IO.File]::ReadAllText((Join-Path $Root 'server-settings.json')) | ConvertFrom-Json } catch { }
  $drift = @()
  if ($null -eq $was -or $null -eq $got) { $drift += 'server-settings.json, which cannot be read' }
  else {
    $wn = @($was.PSObject.Properties | ForEach-Object { $_.Name })
    $gn = @($got.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($k in @($wn + $gn | Sort-Object -Unique)) {
      if ($ReleaseKeys -contains $k) { continue }
      $a = 'absent'
      $b = 'absent'
      if ($wn -contains $k) { $a = ConvertTo-Json -InputObject $was.$k -Compress -Depth 30 }
      if ($gn -contains $k) { $b = ConvertTo-Json -InputObject $got.$k -Compress -Depth 30 }
      if ($a -ne $b) { $drift += $k }
    }
  }
  if ($drift.Count) {
    'read back: ' + ($drift -join ', ') + ' would not be what the server had, so nothing is started'
    $moved = $false
  } else { 'read back: every setting outside this release is the one the server had' }
}

if ($moved) {
  'swapped in ' + $placed.Count + ' file(s), the ones they replaced are in ' + $prevDir
  NormalTask
  Start-ScheduledTask -TaskName $Task -EA SilentlyContinue
  'started, giving it ' + $Wait + ' seconds to answer on UDP ' + $port + ' and on ' + $resPort
  if (Answering) {
    'PASS: the server is answering on ' + $resPort + ', game port ' + $port + ', pid ' + @(Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue)[0].OwningProcess
    Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue
    # The last two sets of replaced files stay, newest first by their stamp,
    # and the last two a -PutBack took out.
    foreach ($kind in '.prev-*', '.undone-*') {
      Get-ChildItem -LiteralPath $Root -Directory -Force -EA SilentlyContinue |
        Where-Object { $_.Name -like $kind } | Sort-Object Name -Descending | Select-Object -Skip 2 |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -EA SilentlyContinue }
    }
    'SWAP OK'
    exit 0
  }
  'FAIL: nothing answered on UDP ' + $port + ' and ' + $resPort + ' within ' + $Wait + ' seconds'
  if (Test-Path -LiteralPath $log) { '--- server.log, last 30 ---'; Get-Content -LiteralPath $log -Tail 30 }
  StopOurs
}

'putting the previous files back'
PutBack
NormalTask
Start-ScheduledTask -TaskName $Task -EA SilentlyContinue
if (Answering) { 'the previous files are back and the server is answering on ' + $resPort + ' again' }
else { 'THE PREVIOUS FILES ARE BACK AND THE SERVER STILL IS NOT ANSWERING on ' + $resPort }
if ($clean) {
  # A put-back's stage is the .prev folder it was putting back, full again.
  if (-not $KeepStage) { Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue }
  Remove-Item -LiteralPath $prevDir -Recurse -Force -EA SilentlyContinue
  'SWAP ROLLED BACK'
} else {
  'what it replaced is still in ' + $prevDir + ' and what it could not take out is in ' + $stageDir
  'SWAP FAILED'
}
exit 1
'@

# The values the two blocks run with, as lines of PowerShell put in front of
# them. Quoted here once, doubling any single quote, because a plugin name is
# free text and one of them with an apostrophe in it would otherwise end the
# string early on the far side.
#
# $releaseKeys, when given, are the settings keys the deploy is meant to
# change: the swap then reads the settings back before it starts anything, and
# ServerSettings.ps1's $settingsCarryBlock uses them (Deploy-Server.ps1). Left
# out, $ReleaseKeys is $null and there is no read-back.
function SwapVars([string]$farRoot, [string]$taskName, [string]$stageName, [string]$prevName, [int]$waitSeconds, $sums, [string[]]$releaseKeys = $null) {
  $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
  $keysLine = '$ReleaseKeys = $null'
  if ($null -ne $releaseKeys) { $keysLine = '$ReleaseKeys = @(' + ((@($releaseKeys) | ForEach-Object { & $q $_ }) -join ', ') + ')' }
  $lines = @(
    ('$Root  = ' + (& $q $farRoot.Replace('/', '\'))),
    ('$Task  = ' + (& $q $taskName)),
    ('$Stage = ' + (& $q $stageName)),
    ('$Prev  = ' + (& $q $prevName)),
    ('$Wait  = ' + $waitSeconds),
    '$KeepStage = $false',
    $keysLine,
    '$Want  = [ordered]@{}'
  )
  foreach ($k in @($sums.Keys)) { $lines += ('$Want[' + (& $q $k) + '] = ' + (& $q $sums[$k])) }
  return (($lines -join "`r`n") + "`r`n")
}
# ==== end deploy-server remote blocks ====

# What $checkBlock calls to hold the server files to their record (#1214),
# in front of it, so the box has it. Outside the markers because it reads a
# file beside this one: tests\test-deploy-server-swap.ps1 runs the blocks out
# of the markers and puts the same text in front itself.
$checkBlock = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'ServerBuild.ps1')) + "`r`n" + $checkBlock

# ==== put-back pick ====
#
# -PutBack on Deploy-Server, Deploy-DevGamemode, Deploy-Docs, Install-Voice and
# Install-Bot. Put in front of the swap block in place of a stage: the newest
# .prev folder IS the stage, what it holds is what gets swapped back in, and
# what it replaces goes to .undone-<stamp> rather than another .prev, so a
# second -PutBack goes to the one before rather than back to what was just
# taken out. $KeepStage, because a put-back that does not answer must leave
# that .prev folder where it was, full, rather than clear it as a failed stage
# is cleared. A file the deploy added with nothing before it stays; there is
# nothing to put back for it, and nothing running reads a file the old one
# did not name.
$putBackPick = @'
$ProgressPreference = 'SilentlyContinue'
$last = @(Get-ChildItem -LiteralPath $Root -Directory -Force -EA SilentlyContinue |
          Where-Object { $_.Name -like '.prev-*' } | Sort-Object Name -Descending | Select-Object -First 1)
if (-not $last.Count) {
  'there is no .prev folder in ' + $Root + ', so there is nothing to put back'
  'SWAP REFUSED'
  exit 1
}
$Stage = $last[0].Name
$Prev = '.undone-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$KeepStage = $true
$Want = [ordered]@{}
foreach ($f in @(Get-ChildItem -LiteralPath $last[0].FullName -Recurse -File -Force -EA SilentlyContinue)) {
  $Want[$f.FullName.Substring($last[0].FullName.Length).TrimStart('\').Replace('\', '/')] = ''
}
if (-not $Want.Count) {
  $last[0].FullName + ' is empty, so there is nothing to put back'
  'SWAP REFUSED'
  exit 1
}
'putting back what ' + $last[0].FullName + ' kept: ' + (@($Want.Keys) -join ', ')

'@
# ==== end put-back pick ====

# ==== service swap blocks ====
#
# The site, the voice service and the bot. The same two halves as the game
# server's above, without what only a game server has (a load order, a port
# in its settings, a build record). What is different about each service is
# five functions the caller puts in front of the swap block:
#
#   StopIt    stops it, by its own folder or port, and says what it stopped
#   StartIt   starts it; $Rolling is true when it is the old files starting
#   Healthy   $true once it answers within $Wait seconds, and nothing else
#   Answer    one line saying what answered
#   Why       the lines that say why it did not (a log tail)
#
# and, for the check block, an optional ExtraCheck that returns reasons to
# refuse. $Parse names the files that are programs: .js ones go through
# node --check and .py ones through Python's own parser, on the box, because a
# file that does not parse is the commonest way a deploy that copied fine
# still takes the thing down.
$serviceCheckBlock = @'
$ProgressPreference = 'SilentlyContinue'
$stageDir = Join-Path $Root $Stage
$bad = @()
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + $env:Path
foreach ($rel in @($Want.Keys)) {
  $p = Join-Path $stageDir ($rel -replace '/', '\')
  if (-not (Test-Path -LiteralPath $p)) { $bad += ('did not arrive: ' + $rel); continue }
  if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $Want[$rel]) {
    $bad += ('arrived different from what was sent: ' + $rel); continue
  }
  if ($rel -like '*.json') {
    $b = [IO.File]::ReadAllBytes($p)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
      $bad += ($rel + ' starts with a byte order mark, and node will not parse it')
    } else {
      try { $null = [IO.File]::ReadAllText($p) | ConvertFrom-Json } catch { $bad += ($rel + ' does not parse: ' + $_.Exception.Message) }
    }
  }
}
foreach ($rel in @($Parse)) {
  if (-not $rel) { continue }
  $p = Join-Path $stageDir ($rel -replace '/', '\')
  if (-not (Test-Path -LiteralPath $p)) { continue }
  $isJs = ($rel -like '*.js')
  $what = 'python'
  if ($isJs) { $what = 'node' }
  $tool = Get-Command $what -CommandType Application -EA SilentlyContinue | Select-Object -First 1
  if (-not $tool) { $bad += ($what + ' is not on this machine, so ' + $rel + ' could not be checked'); continue }
  if ($isJs) { $said = @(& $tool.Source --check $p 2>&1) }
  else { $said = @(& $tool.Source -c "import ast,sys; ast.parse(open(sys.argv[1],'rb').read(), sys.argv[1])" $p 2>&1) }
  if ($LASTEXITCODE -ne 0) {
    $bad += ($rel + ' does not parse: ' + ((@($said | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) | Select-Object -First 6) -join ' | '))
  }
}
if (${function:ExtraCheck}) { $bad += @(ExtraCheck | Where-Object { $_ }) }
if ($bad.Count) {
  foreach ($x in $bad) { 'REFUSED: ' + $x }
  Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue
  'the stage is cleared and nothing running was touched'
  'STAGE REFUSED'
} else {
  $said = 'the stage checks out: ' + $Want.Count + ' file(s) as sent'
  if (@($Parse | Where-Object { $_ }).Count) { $said += ', and ' + (@($Parse | Where-Object { $_ }) -join ', ') + ' parse' }
  $said
  'STAGE OK'
}
'@

$serviceSwapBlock = @'
$ProgressPreference = 'SilentlyContinue'
$stageDir = Join-Path $Root $Stage
$prevDir  = Join-Path $Root $Prev
$clean    = $true
$Rolling  = $false

# A rename on one volume, retried, because a process that has just been told
# to stop does not always let go of its files the same instant.
function Shift([string]$from, [string]$to) {
  $dir = Test-Path -LiteralPath $from -PathType Container
  for ($i = 0; $i -lt 10; $i++) {
    try {
      $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $to))
      if ($dir) { [IO.Directory]::Move($from, $to) }
      else { [IO.File]::Move($from, $to) }
      return $true
    } catch { Start-Sleep -Milliseconds 500 }
  }
  return $false
}

function PutBack {
  $rels = @($moveRels)
  [array]::Reverse($rels)
  foreach ($rel in $rels) {
    $r = $rel -replace '/', '\'
    $at = Join-Path $Root $r
    if ($placed -contains $rel) {
      if (-not (Shift $at (Join-Path $stageDir $r))) { 'COULD NOT TAKE THE NEW ' + $rel + ' BACK OUT'; $script:clean = $false; continue }
    }
    if ($aside -contains $rel) {
      if (-not (Shift (Join-Path $prevDir $r) $at)) { 'COULD NOT PUT THE OLD ' + $rel + ' BACK'; $script:clean = $false }
    }
  }
}

# A directory named in $Dirs (the bot's py-libs) moves with the files, so the
# old one is what .prev puts back. A deploy that did not stage that directory
# leaves the one already at the root alone.
if (-not (Test-Path variable:Dirs)) { $Dirs = @() }
$moveRels = @($Want.Keys)
foreach ($rel in @($Dirs)) {
  if (-not $rel) { continue }
  $atDir = Join-Path $stageDir ($rel -replace '/', '\')
  if (Test-Path -LiteralPath $atDir -PathType Container) { $moveRels += $rel }
}

StopIt
$placed = @()
$aside = @()
$moved = $true
foreach ($rel in @($moveRels)) {
  $r = $rel -replace '/', '\'
  $at = Join-Path $Root $r
  if (Test-Path -LiteralPath $at) {
    if (-not (Shift $at (Join-Path $prevDir $r))) { 'could not move the old ' + $rel + ' aside'; $moved = $false; break }
    $aside += $rel
  }
  if (-not (Shift (Join-Path $stageDir $r) $at)) { 'could not move the new ' + $rel + ' into place'; $moved = $false; break }
  $placed += $rel
}

if ($moved) {
  'swapped in ' + $placed.Count + ' file(s), the ones they replaced are in ' + $prevDir
  StartIt
  'started, giving it ' + $Wait + ' seconds to answer'
  if (Healthy) {
    'PASS: ' + (Answer)
    Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue
    # The newest two of each, by their stamp.
    foreach ($kind in '.prev-*', '.undone-*') {
      Get-ChildItem -LiteralPath $Root -Directory -Force -EA SilentlyContinue |
        Where-Object { $_.Name -like $kind } | Sort-Object Name -Descending | Select-Object -Skip 2 |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -EA SilentlyContinue }
    }
    'SWAP OK'
    exit 0
  }
  'FAIL: it did not answer within ' + $Wait + ' seconds'
  Why
  StopIt
}

$Rolling = $true
'putting the previous files back'
PutBack
StartIt
if (Healthy) { 'the previous files are back and it is answering again: ' + (Answer) }
else { 'THE PREVIOUS FILES ARE BACK AND IT STILL IS NOT ANSWERING'; Why }
if ($clean) {
  if (-not $KeepStage) { Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue }
  Remove-Item -LiteralPath $prevDir -Recurse -Force -EA SilentlyContinue
  'SWAP ROLLED BACK'
} else {
  'what it replaced is still in ' + $prevDir + ' and what it could not take out is in ' + $stageDir
  'SWAP FAILED'
}
exit 1
'@

# The values the service blocks run with, the same way SwapVars does it for
# the game server: quoted once here, every single quote doubled.
function ServiceSwapVars([string]$farRoot, [string]$stageName, [string]$prevName, [int]$waitSeconds, $sums, [string[]]$parse) {
  $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
  $lines = @(
    ('$Root  = ' + (& $q $farRoot.Replace('/', '\'))),
    ('$Stage = ' + (& $q $stageName)),
    ('$Prev  = ' + (& $q $prevName)),
    ('$Wait  = ' + $waitSeconds),
    '$KeepStage = $false',
    '$Want  = [ordered]@{}'
  )
  foreach ($k in @($sums.Keys)) { $lines += ('$Want[' + (& $q $k) + '] = ' + (& $q $sums[$k])) }
  $lines += ('$Parse = @(' + ((@($parse | Where-Object { $_ }) | ForEach-Object { & $q $_ }) -join ', ') + ')')
  return (($lines -join "`r`n") + "`r`n")
}

# The SHA-256 of each file about to go up, by the path it will have under the
# stage, for the check block to hold the far copies to.
function Get-SwapHashes($send) {
  $h = [ordered]@{}
  foreach ($rel in @($send.Keys)) {
    $h[$rel] = (Get-FileHash -LiteralPath $send[$rel] -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  return $h
}

# What the caller does with the last line of a swap: SWAP OK is the only
# success. Said once here so every script reports a failed swap the same way.
function Show-SwapResult($lines, [string]$prevWhere) {
  $all = @($lines | ForEach-Object { "$_".Trim() })
  if ($all -contains 'SWAP OK') { return $true }
  Write-Host ''
  if ($all -contains 'SWAP ROLLED BACK') {
    Write-Host '  FAIL. The new copy did not answer, so the old files were put back and it' -ForegroundColor Red
    Write-Host '  was started again. The lines above say whether it answered, and why the' -ForegroundColor Red
    Write-Host '  new one did not.' -ForegroundColor Red
  } elseif ($all -contains 'SWAP REFUSED') {
    Write-Host '  FAIL. Nothing was swapped. The lines above say why.' -ForegroundColor Red
  } else {
    Write-Host '  FAIL, AND THE BOX MAY NOT BE AS IT WAS. Look at it before anything else.' -ForegroundColor Red
    Write-Host "  The files the swap replaced are in $prevWhere, and the lines above say" -ForegroundColor Red
    Write-Host '  what could not be moved back.' -ForegroundColor Red
  }
  return $false
}
# ==== end service swap blocks ====

# ==== deploy records ====
#
# What each part runs, as Artifact.ps1 records it (issue #459): a record
# beside what runs (thornswood-deploy.json in the root, or in data for a game
# server) and the same in the store's current\<part>.json. Artifact.ps1 writes
# a new one only after the swap has answered. These two keep the record in step
# with a put-back: the record a part had goes into the .prev folder with the
# files it describes, so -PutBack swaps it back in with them, and after a
# put-back the store is told what came back.
#
# Both need Artifact.ps1 loaded: Invoke-ThornswoodArtifactRemote,
# Get-ThornswoodArtifactPart and the store's name.

function Get-SwapRecordPlace([string]$Root, [string]$Beside) {
  $rootWin = $Root.Replace('/', '\').TrimEnd('\')
  if (-not $Beside) { $Beside = $rootWin + '\thornswood-deploy.json' }
  $bes = $Beside.Replace('/', '\')
  $rel = ''
  if ($bes.StartsWith($rootWin + '\', [StringComparison]::OrdinalIgnoreCase)) { $rel = $bes.Substring($rootWin.Length + 1) }
  return [pscustomobject]@{ Root = $rootWin; Beside = $bes; Rel = $rel }
}

# After SWAP OK and before the new record is written: the record the part had
# goes into the .prev folder this deploy made, at the same place under the root.
function Save-SwapPreviousRecord([string]$Target, [string[]]$SshArgs, [string]$Root, [string]$PrevName, [string]$Beside = '') {
  $w = Get-SwapRecordPlace $Root $Beside
  if (-not $w.Rel) { return }
  $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
  $said = @(Invoke-ThornswoodArtifactRemote $Target $SshArgs @"
`$from = $(& $q $w.Beside)
`$prev = Join-Path $(& $q $w.Root) $(& $q $PrevName)
if (-not (Test-Path -LiteralPath `$from)) { 'NO RECORD' }
elseif (-not (Test-Path -LiteralPath `$prev)) { 'NO PREV' }
else {
  `$to = Join-Path `$prev $(& $q $w.Rel)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent `$to) | Out-Null
  Copy-Item -LiteralPath `$from -Destination `$to -Force
  'KEPT'
}
"@)
  if ($said -contains 'KEPT') { Write-Host ('  the record it ran before is kept with the old files in ' + $PrevName) -ForegroundColor DarkGray }
}

# After a put-back has said SWAP OK. $lines is what the swap said: its
# 'putting back what <folder> kept: ...' line names the record when one came
# back with the files. Then the store's current record is that one. When none
# did (a .prev from before records), the record says the part runs an older
# copy nobody recorded, rather than go on naming what was taken out.
function Restore-SwapRecord([string]$Target, [string[]]$SshArgs, [string]$Root, $Lines, [string]$Beside = '', [string]$Component = '') {
  $w = Get-SwapRecordPlace $Root $Beside
  $part = Get-ThornswoodArtifactPart $Root
  $came = $false
  foreach ($l in @($Lines)) {
    $s = [string]$l
    $at = $s.IndexOf(' kept: ')
    if ($s.StartsWith('putting back what ') -and $at -gt 0) {
      $came = @($s.Substring($at + 7) -split ', ' | ForEach-Object { $_.Trim() }) -contains $w.Rel.Replace('\', '/')
    }
  }
  $store = [string]$script:ThornswoodDeployStore
  if (-not $store) { $store = 'C:/Thornswood-Deploys' }
  $storeWin = $store.Replace('/', '\').TrimEnd('\')
  $q = { param($x) "'" + ([string]$x).Replace("'", "''") + "'" }
  $said = @(Invoke-ThornswoodArtifactRemote $Target $SshArgs @"
`$beside = $(& $q $w.Beside)
`$cur = Join-Path $(& $q ($storeWin + '\current')) $(& $q ($part + '.json'))
`$when = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
$(Get-ThornswoodLockedFolderScript $storeWin)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent `$cur) | Out-Null
if ('$came' -eq 'True' -and (Test-Path -LiteralPath `$beside)) {
  Copy-Item -LiteralPath `$beside -Destination `$cur -Force
  `$name = ''
  try { `$name = [string]([IO.File]::ReadAllText(`$beside) | ConvertFrom-Json).name } catch { }
} else {
  `$name = 'an older copy kept before deploys were recorded'
  `$rec = [ordered]@{ part = $(& $q $part); component = $(& $q $Component); name = `$name; commit = ''; putBack = `$true; deployedUtc = `$when; from = `$env:COMPUTERNAME }
  `$json = ConvertTo-Json -InputObject `$rec
  [IO.File]::WriteAllText(`$cur, `$json, (New-Object Text.UTF8Encoding(`$false)))
  [IO.File]::WriteAllText(`$beside, `$json, (New-Object Text.UTF8Encoding(`$false)))
}
Add-Content -LiteralPath $(& $q ($storeWin + '\history.log')) -Value (`$when + ' ' + $(& $q $part) + ' put back to ' + `$name)
'RECORDED ' + `$name
"@)
  $r = @($said | Where-Object { "$_" -like 'RECORDED *' })
  if ($r.Count) { Write-Host ('  the box records ' + $part + ' as ' + ([string]$r[0]).Substring(9)) -ForegroundColor DarkGray }
  else { Write-Host ('  the put-back was not recorded in the store: ' + ($said -join ' ')) -ForegroundColor Yellow }
}
# ==== end deploy records ====
