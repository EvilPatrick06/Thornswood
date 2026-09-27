<#
  Deploy-Server.ps1

  Sends the built server up to the VPS and restarts it.

  Warns first, but does not evict anybody.

  Stopping and starting the server reads from a chair as a freeze and then
  everything carrying on, because the client holds its session across it. So
  the default is a short notice saying a push is coming and not to be mid
  fight, then the push. Throwing people out for that would be a bigger
  interruption than the thing being warned about.

  Use -Mode restart when the server really is going down for a while. That one
  counts down properly and clears the room before touching anything.


  A server that is not listening has nobody on it, whatever online.json says.
  And the stop removes any restart.json the old process never read, so the
  next one does not find it and count down on its own.
  The load order goes up with its paths rewritten to the VPS plugin folder,
  and any plugin it names that the box does not have goes up with it. The
  file in the build keeps this machine's paths; only the copy sent changes.

  Copy to a stage, check it there, and only then stop. scam_native.node is a
  loaded image while node is running and Windows will not let you overwrite a
  mapped file, so a copy over a live server fails halfway and leaves a server
  that starts against a file which is half old and half new. That was why
  this used to stop first and copy after, which kept the server down for the
  whole copy and started it against whatever had arrived. Now everything goes
  into $Root\.stage-<stamp> while the server runs, the box checks it there,
  and the stop is only as long as a few renames on one volume and a start.
  If the new server does not answer, the old files go back and this exits 1.

    .\Deploy-Server.ps1                  1 minute of notice, nobody kicked
    .\Deploy-Server.ps1 -Minutes 3
    .\Deploy-Server.ps1 -Mode restart    counts down and empties the room
    .\Deploy-Server.ps1 -Now             no warning at all
#>
[CmdletBinding()]
param(
  [string]$Dist    = (& (Join-Path $PSScriptRoot '..\release\Where.ps1') ServerDist),
  [string]$Vps     = '192.135.112.23',
  [string]$User    = 'Administrator',
  [string]$Root    = 'C:/Thornswood-Server',
  [string]$Task    = 'Thornswood Server',
  [double]$Minutes = 1,
  [ValidateSet('notice','restart')]
  [string]$Mode    = 'notice',
  [switch]$Now,
  [string]$Why     = 'a server update',
  # Where the plugin files the load order names are read from, for the ones the
  # VPS turns out not to have yet. This is the live Steam game, the same place
  # Deploy-Gamemode -Vortex built the list from.
  [string]$Data    = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data',
  # How long the new server has to answer on its game port and its resources
  # port before the old files go back. Waiting longer costs nothing when it
  # comes up, because the check returns the moment both answer.
  [int]$Wait       = 60
)

$ErrorActionPreference = 'Stop'
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=accept-new')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

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

function OnlineNow {
  # The gamemode rewrites online.json whenever the number moves. No file, or an
  # unreadable one, is treated as nobody home rather than as a reason to stop:
  # this is a courtesy check, not a gate.
  #
  # Nothing on the game port is nobody on, whatever online.json says. The
  # gamemode writes that file only when the count moves, so a killed or
  # crashed process leaves its last count behind. Measured in review on
  # 24 September: the live half of the same gap Deploy-DevGamemode closed.
  # When the box cannot list its ports the count is kept, which errs toward
  # a warning.
  $out = Remote @"
`$root = '$Root'.Replace('/','\')
`$port = 0
`$d = 'data'
try {
  `$s = Get-Content (Join-Path `$root 'server-settings.json') -Raw -EA Stop | ConvertFrom-Json
  `$port = [int]`$s.port
  if (`$s.dataDir) { `$d = [string]`$s.dataDir }
} catch { }
`$up = `$true
if (`$port -gt 0) {
  try {
    `$u = @(Get-NetUDPEndpoint -EA Stop | Where-Object { `$_.LocalPort -eq `$port })
    `$up = (`$u.Count -gt 0)
  } catch { }
}
if (-not `$up) { 0 }
else {
  try {
    `$j = Get-Content (Join-Path ([IO.Path]::Combine(`$root, `$d)) 'online.json') -Raw -EA Stop | ConvertFrom-Json
    if (`$null -eq `$j -or `$null -eq `$j.now) { throw 'no count' }
    `$j.now
  } catch { 0 }
}
"@
  $n = 0
  foreach ($line in $out) {
    if ("$line".Trim() -match '^\d+$') { $n = [int]$Matches[0]; break }
  }
  return $n
}

# ==== deploy-server remote blocks ====
#
# THE TWO HALVES THAT RUN ON THE BOX, KEPT HERE SO A HARNESS CAN RUN THEM TOO.
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
$rp = Join-Path $stageDir 'server-build.json'
if ($sums.ContainsKey('scam_native.node') -and (Test-Path -LiteralPath $rp)) {
  try {
    $rec = [IO.File]::ReadAllText($rp) | ConvertFrom-Json
    if ($sums['scam_native.node'] -ne ([string]$rec.sha256).ToLowerInvariant()) {
      $bad += 'scam_native.node is not the build server-build.json records'
    }
  } catch { $bad += ('server-build.json does not parse: ' + $_.Exception.Message) }
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
# native server has been built without throwing.
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

if ($moved) {
  'swapped in ' + $placed.Count + ' file(s), the ones they replaced are in ' + $prevDir
  Start-ScheduledTask -TaskName $Task -EA SilentlyContinue
  'started, giving it ' + $Wait + ' seconds to answer on UDP ' + $port + ' and on ' + $resPort
  if (Answering) {
    'PASS: the server is answering on ' + $resPort + ', game port ' + $port + ', pid ' + @(Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue)[0].OwningProcess
    Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue
    # The last three sets of replaced files stay, newest first by their stamp.
    Get-ChildItem -LiteralPath $Root -Directory -Force -EA SilentlyContinue |
      Where-Object { $_.Name -like '.prev-*' } | Sort-Object Name -Descending | Select-Object -Skip 3 |
      ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -EA SilentlyContinue }
    'SWAP OK'
    exit 0
  }
  'FAIL: nothing answered on UDP ' + $port + ' and ' + $resPort + ' within ' + $Wait + ' seconds'
  if (Test-Path -LiteralPath $log) { '--- server.log, last 30 ---'; Get-Content -LiteralPath $log -Tail 30 }
  StopOurs
}

'putting the previous files back'
PutBack
Start-ScheduledTask -TaskName $Task -EA SilentlyContinue
if (Answering) { 'the previous files are back and the server is answering on ' + $resPort + ' again' }
else { 'THE PREVIOUS FILES ARE BACK AND THE SERVER STILL IS NOT ANSWERING on ' + $resPort }
if ($clean) {
  Remove-Item -LiteralPath $stageDir -Recurse -Force -EA SilentlyContinue
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
function SwapVars([string]$farRoot, [string]$taskName, [string]$stageName, [string]$prevName, [int]$waitSeconds, $sums) {
  $q = { param($s) "'" + ([string]$s).Replace("'", "''") + "'" }
  $lines = @(
    ('$Root  = ' + (& $q $farRoot.Replace('/', '\'))),
    ('$Task  = ' + (& $q $taskName)),
    ('$Stage = ' + (& $q $stageName)),
    ('$Prev  = ' + (& $q $prevName)),
    ('$Wait  = ' + $waitSeconds),
    '$Want  = [ordered]@{}'
  )
  foreach ($k in @($sums.Keys)) { $lines += ('$Want[' + (& $q $k) + '] = ' + (& $q $sums[$k])) }
  return (($lines -join "`r`n") + "`r`n")
}
# ==== end deploy-server remote blocks ====

# game\gamemode.js is the source. The build output has a copy of it that cmake
# writes during configure, and that copy is stale the moment the source is
# edited without a reconfigure. Deploying the stale one is how a change gets
# written, committed, shipped, and then quietly not happen.
# The same prerequisite as Deploy-Gamemode, and the same message, because a
# machine without the fork built hits this one first if it skips that step.
# Unlike that script this one DOES reach the VPS, so it stops before anything
# leaves the machine rather than part way through a copy.
if (-not (Test-Path -LiteralPath $Dist)) {
  throw (
    "No skymp server build at $Dist, so there is nothing to send." + [Environment]::NewLine +
    [Environment]::NewLine +
    "This script copies a LOCAL build of the server to the VPS. Without the build there is" + [Environment]::NewLine +
    "nothing to copy, and nothing has been sent." + [Environment]::NewLine +
    [Environment]::NewLine +
    "If you have the fork built somewhere else, point at it:" + [Environment]::NewLine +
    "    .\scripts\deploy\Deploy-Server.ps1 -Dist <path to skymp\build\dist\server>" + [Environment]::NewLine +
    [Environment]::NewLine +
    "If you have not built the fork, this deploy is not yours to run. The build tree lives on" + [Environment]::NewLine +
    "Patrick's machine, and .\scripts\release\Check-ShipReady.ps1 says what this machine is missing."
  )
}

$src = Join-Path $Here '..\..\game\gamemode.js'
$built = Join-Path $Dist 'gamemode.js'
if (Test-Path -LiteralPath $src) {
  $a = (Get-Item $src).Length
  $b = if (Test-Path -LiteralPath $built) { (Get-Item $built).Length } else { -1 }
  if ($a -ne $b) {
    Copy-Item $src $built -Force
    Write-Host ("  gamemode.js taken from game ({0:N0} bytes, build had {1})" -f `
      $a, $(if ($b -lt 0) { 'none' } else { '{0:N0}' -f $b })) -ForegroundColor DarkGray
  }
}

# The file about to go up must parse, or the live server stops at start. The
# same check Deploy-DevGamemode.ps1 and Deploy-Gamemode.ps1 make, made again
# here on the copy that is actually sent, before anything leaves the machine.
if (Test-Path -LiteralPath $built) {
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'node is not on this machine, so gamemode.js cannot be checked before it goes live. Nothing was sent.' }
  & node --check $built
  if ($LASTEXITCODE -ne 0) { throw 'gamemode.js does not parse. Nothing was sent.' }
  Write-Host '  gamemode.js parses'
}

$files = 'scam_native.node', 'gamemode.js', 'server-settings.json'
foreach ($f in $files) {
  $p = Join-Path $Dist $f
  if (-not (Test-Path -LiteralPath $p)) { throw "not built: $p" }
  '{0,-22} {1:N0} bytes' -f $f, (Get-Item $p).Length | Write-Host
}

# The build stamp Deploy-Gamemode.ps1 left beside gamemode.js goes up with it,
# so the box can say which gamemode it runs. It is made again here when it does
# not describe the gamemode about to be sent, which is what happens when the
# copy above took the one in tools, because a stamp naming a different
# gamemode is worse than none. From tools when that is the same file, so git
# can say whether the commit holds it. See BuildStamp.ps1.
. (Join-Path $Here '..\release\BuildStamp.ps1')
$stampPath = Join-Path $Dist 'thornswood-build.json'
if (-not (Test-ThornswoodBuildStamp -Path $stampPath -Gamemode $built)) {
  $stampFrom = $built
  if ((Test-Path -LiteralPath $src) -and
      (Get-FileHash -LiteralPath $src).Hash -eq (Get-FileHash -LiteralPath $built).Hash) { $stampFrom = $src }
  $null = Save-ThornswoodBuildStamp -Gamemode $stampFrom -Channel main -RepoDir (Split-Path -Parent (Split-Path -Parent $Here)) -Path $stampPath
}
'{0,-22} {1}' -f 'thornswood-build.json', (Format-ThornswoodBuildStamp (Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json)) | Write-Host

# ---------------------------------------------------------- which build is this
#
# The binaries have always been copied rather than rebuilt here, and until
# 2026-09-17 nothing mapped scam_native.node back to a commit. The only evidence
# that the shipped one carried the committed server changes was that its file
# date was six minutes later than the last edit to ScampServer.cpp, which is an
# argument rather than a proof.
#
# records\server-build.json is that proof: the hash of the binary a release was
# tested with, and the commit it came from. Regenerate it with
# scripts\release\New-ServerBuildRecord.ps1 after every rebuild.
#
# No record yet means carry on with a warning, so a machine that has not made one
# can still deploy. A record that disagrees is a stop: it means this binary is not
# the one the release was built and tested against, and shipping it would put an
# unknown server in front of everybody.
$recordPath = Join-Path $Here '..\..\records\server-build.json'
$binPath = Join-Path $Dist 'scam_native.node'
if (Test-Path -LiteralPath $recordPath) {
  $rec = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
  $have = (Get-FileHash -LiteralPath $binPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $want = "$($rec.sha256)".ToLowerInvariant()
  if ($have -ne $want) {
    Write-Host ''
    Write-Host '  scam_native.node is not the build this release recorded.' -ForegroundColor Red
    Write-Host ("    on disk   {0}" -f $have) -ForegroundColor Red
    Write-Host ("    recorded  {0}" -f $want) -ForegroundColor Red
    Write-Host ("    recorded build came from commit {0}" -f $rec.source.commit) -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  If you rebuilt on purpose, record the new build and deploy again:' -ForegroundColor Yellow
    Write-Host '    .\scripts\release\New-ServerBuildRecord.ps1' -ForegroundColor Yellow
    Write-Host '  If you did not, find out what changed before this reaches the VPS.' -ForegroundColor Yellow
    throw 'server binary does not match records\server-build.json'
  }
  Write-Host ('{0,-22} matches the record, commit {1}' -f 'build', $rec.source.commit.Substring(0, 8)) -ForegroundColor DarkGray
}
else {
  Write-Host ''
  Write-Host '  No records\server-build.json, so nothing says which commit this binary is.' -ForegroundColor Yellow
  Write-Host '  Make one with .\scripts\release\New-ServerBuildRecord.ps1 and commit it.' -ForegroundColor Yellow
  Write-Host ''
}

# ------------------------------------------------------------- load order
#
# server-settings.json comes out of Deploy-Gamemode with this machine's paths in
# its loadOrder, c:/program files (x86)/steam/... The VPS keeps its plugins at
# $Root/plugins and has no Steam. Sending the file as it is took the server down
# on 2026-09-16 03:09: every plugin "not on disk", then file_size on Skyrim.esm,
# then exit. Export-ServerPayload rewrites the paths for a full install and this
# never did for an update, so it does now, into a copy, leaving the local file
# alone. The order is untouched: those indices are what form ids resolve
# against on both sides.
#
# It also asks the box what it has in $Root/plugins and sends whatever the new
# list names that is not there yet, before the restart, so a plugin added to the
# build cannot leave the server unable to start.
$settingsSrc = Join-Path $Dist 'server-settings.json'
$settings = Get-Content -LiteralPath $settingsSrc -Raw | ConvertFrom-Json
if (-not $settings.loadOrder) { throw 'server-settings.json has no loadOrder' }
$pluginNames = @($settings.loadOrder | ForEach-Object { [IO.Path]::GetFileName($_) })
$remotePlugins = ($Root -replace '\\', '/') + '/plugins'
$settings.loadOrder = @($pluginNames | ForEach-Object { "$remotePlugins/$_" })
$settingsForVps = Join-Path $env:TEMP 'thornswood-server-settings-vps.json'
# WriteAllText with an explicit encoding: Set-Content -Encoding UTF8 writes a
# byte order mark under Windows PowerShell 5.1, and a BOM is not JSON to node.
[IO.File]::WriteAllText($settingsForVps, ($settings | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))

# A PLUGIN THAT CHANGED IS A PLUGIN THAT HAS TO GO UP, AND THIS ASKED THE WRONG
# QUESTION UNTIL 21 SEPTEMBER.
#
# It compared NAMES. A plugin the VPS already had by name was never sent again,
# however much its contents had moved. Thornswood-Content.esp is on that list
# and it is the one plugin in the load order that this repo edits: on
# 21 September alone it was renamed off another server's prefix, had sixteen
# dead books taken out, and gained the handle, the deed, the key and the mold.
# None of it could reach the server, and the launcher downloads the plugins from
# the server, so none of it could reach anybody's game either. The gamemode was
# live and calling for records that were not in the file any client had.
#
# So the size is asked for as well as the name. Size and not a hash because this
# is one remote call over ssh for the whole folder either way, and a hash of 60
# plugins is 28MB of reading on a box that is also running the server; a plugin
# whose contents changed and whose size did not is a case this can live with,
# and a deploy that reads every plugin twice is not.
$thereRaw = @(Remote ("Get-ChildItem -LiteralPath '" + $remotePlugins.Replace('/','\') +
                      "' -File | ForEach-Object { `$_.Name + '|' + `$_.Length }"))
$thereSize = @{}
foreach ($row in $thereRaw) {
  $bits = "$row".Trim() -split '\|'
  if ($bits.Count -eq 2 -and $bits[0] -match '\.es[pml]$') { $thereSize[$bits[0]] = [int64]$bits[1] }
}
$there = @($thereSize.Keys)

# OUR OWN PLUGIN COMES FROM THE REPO, NOT FROM A GAME FOLDER.
#
# $Data is the Steam copy, which is right for the other 59: Vortex deploys them
# there and that is where they live. Thornswood-Content.esp is not one of those.
# It is built by scripts in this repo and installed into a game folder by
# Install-ThornswoodContent.ps1, whose default target is C:\Thornswood\Game and
# not the Steam copy at all.
#
# So on 21 September there were four copies of it on this machine at three
# different sizes, and a deploy sent whichever one the Steam folder happened to
# hold: 151,288 bytes, which was that morning's, while the repo was on 141,234
# with the deed, the key and the mold in it. Chasing that around by hand is how
# an evening goes missing, so the question is settled here instead. The repo is
# where this plugin is made and the repo is what goes up.
$ours = Join-Path $Here '..\..\game\content\Thornswood-Content.esp'

$sendPlugins = @()
$changed = @()
foreach ($n in $pluginNames) {
  $local = Join-Path $Data $n
  if ($n -eq 'Thornswood-Content.esp' -and (Test-Path -LiteralPath $ours)) { $local = $ours }
  if ($there -notcontains $n) {
    if (Test-Path -LiteralPath $local) { $sendPlugins += $local }
    else { throw "the load order names $n, the VPS does not have it, and it is not at $local either" }
    continue
  }
  # It is there. Is it the same one? A plugin this machine does not have is left
  # alone: the VPS's copy is then the only copy and overwriting it with nothing
  # is the one outcome worse than it being stale.
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
  Write-Host '  every plugin the load order names is on the VPS at the same size' -ForegroundColor DarkGray
}

# ------------------------------------------------------------- the stage
#
# Everything goes up while the server is still running, into a folder beside
# the live files rather than over them, and the box checks it before anybody
# is warned about a restart. A refusal here leaves the server exactly as it
# was, with nobody told to stop fighting for a restart that is not coming.
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$stageName = '.stage-' + $stamp
$prevName  = '.prev-' + $stamp
$rootWin   = $Root.Replace('/', '\')
$stageFar  = ($Root -replace '\\', '/') + '/' + $stageName

$send = [ordered]@{}
foreach ($p in $sendPlugins) { $send['plugins/' + (Split-Path $p -Leaf)] = $p }
foreach ($f in $files) {
  $src = Join-Path $Dist $f
  if ($f -eq 'server-settings.json') { $src = $settingsForVps }
  $send[$f] = $src
}
# The record goes up with the binary, so the box itself answers what it is
# running. Hash $Root/scam_native.node against it there and the two halves of
# the question, what source and what binary, both have an answer on the machine
# serving people rather than only on a developer's disk.
if (Test-Path -LiteralPath $recordPath) { $send['server-build.json'] = $recordPath }
# The build stamp goes up in the stage with the gamemode it describes, so it
# is hashed and checked with the rest, swapped in beside gamemode.js, and put
# back with it on a rollback. Sent on its own straight into the live folder,
# the way it went before the stage, a rollback would leave the new stamp
# describing the old gamemode. A failed send was a warning then because the
# server was already down; here it stops the run like any other file, because
# nothing has been stopped yet and nobody has been warned, so it costs a rerun.
$send['thornswood-build.json'] = $stampPath

$hashes = [ordered]@{}
foreach ($rel in $send.Keys) {
  $hashes[$rel] = (Get-FileHash -LiteralPath $send[$rel] -Algorithm SHA256).Hash.ToLowerInvariant()
}

Write-Host ''
Write-Host "Staging in $rootWin\$stageName..."
# A stage left by a run that died part way is cleared first. It was never
# swapped in, so nothing is lost with it.
Remote @"
Get-ChildItem -LiteralPath '$rootWin' -Directory -Force -EA SilentlyContinue |
  Where-Object { `$_.Name -like '.stage-*' } |
  ForEach-Object { Remove-Item -LiteralPath `$_.FullName -Recurse -Force -EA SilentlyContinue }
New-Item -ItemType Directory -Path '$rootWin\$stageName\plugins' -Force | Out-Null
"@ | Out-Null
foreach ($rel in $send.Keys) {
  & scp @ssh $send[$rel] "$User@${Vps}:$stageFar/$rel"
  if ($LASTEXITCODE -ne 0) { throw "scp failed for $rel. The server has not been touched." }
  Write-Host "  $rel"
}

$checkOut = @(Remote ((SwapVars $Root $Task $stageName $prevName $Wait $hashes) + $checkBlock) |
              ForEach-Object { Write-Host ('  ' + $_); "$_".Trim() })
if ($checkOut -notcontains 'STAGE OK') {
  Write-Host ''
  Write-Host '  THE STAGE DID NOT CHECK OUT, so nothing was stopped and nobody was warned.' -ForegroundColor Red
  Write-Host '  The server is still running exactly as it was. The lines above say why.' -ForegroundColor Red
  exit 1
}

# ------------------------------------------------------------- the warning
if (-not $Now) {
  Write-Host ''
  $on = OnlineNow
  if ($on -le 0) {
    Write-Host '  nobody is online, going straight down'
  }
  else {
    Write-Host ("  $on online, $Mode, giving them $Minutes " +
                $(if ($Minutes -eq 1) { 'minute' } else { 'minutes' }))
    $ask = Join-Path $Here '..\vps\Request-Restart.ps1'
    if (Test-Path -LiteralPath $ask) {
      # -RestartFollows because this script stops and starts the task a few
      # lines below. Request-Restart refuses a kicking mode without it, and
      # that refusal is the point: a kick with no restart behind it is what
      # leaves people in an empty world.
      & $ask -Minutes $Minutes -Mode $Mode -Why $Why -Vps $Vps -User $User `
             -Data "$Root/data" -RestartFollows

      # AND READ WHETHER THE WARNING ACTUALLY WENT OUT.
      #
      # This called it and never looked. Request-Restart exits 1 when it
      # cannot reach the server to announce anything, and the next thing this
      # script does is stop the task, so a warning that failed meant everybody
      # in the world was dropped with no notice at all while the log said the
      # countdown had been given. That is the same shape as entry 118: a step
      # printed that it had stopped and the caller carried on regardless.
      #
      # Nothing has been swapped in at this point and the task is still
      # running, so stopping here and clearing the stage leaves the server
      # exactly as it was found. -Now is the way to take it down deliberately
      # without warning anybody.
      if ($LASTEXITCODE -ne 0) {
        Write-Host ''
        Write-Host "  THE WARNING DID NOT GO OUT. Request-Restart.ps1 exited with $LASTEXITCODE." -ForegroundColor Red
        Write-Host "  $on people are in the world and the restart below would drop them with no" -ForegroundColor Red
        Write-Host '  notice. Nothing has been swapped in and the server is still running exactly' -ForegroundColor Red
        Write-Host '  as it was. Find out why it could not reach the server and run this again,' -ForegroundColor Red
        Write-Host '  or pass -Now if you mean to take it down without telling anybody.' -ForegroundColor Red
        Remote "Remove-Item -LiteralPath '$rootWin\$stageName' -Recurse -Force -EA SilentlyContinue" | Out-Null
        exit 1
      }
    } else {
      Write-Host '  Request-Restart.ps1 is missing, warning nobody' -ForegroundColor Yellow
    }

    $deadline = (Get-Date).AddMinutes($Minutes).AddSeconds(20)
    if ($Mode -eq 'notice') {
      # Nobody is being put out, so there is no room to wait for emptying.
      # Just let the notice land and give people a moment to stop swinging.
      while ((Get-Date) -lt $deadline) { Start-Sleep -Seconds 5 }
      Write-Host '  notice given, pushing'
    }
    else {
      # Stop early the moment the room is empty. The gamemode kicks everyone at
      # zero, so this normally returns a few seconds after the countdown rather
      # than sitting out the whole clock.
      while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15
        $left = OnlineNow
        if ($left -le 0) { Write-Host '  room is clear'; break }
        $mins = [Math]::Max(0, [int]([Math]::Round(($deadline - (Get-Date)).TotalMinutes)))
        Write-Host "  $left still on, $mins min left"
      }
    }
  }
}

Write-Host ''
Write-Host 'Stopping, swapping in and starting...'
# A stray line on stderr must not stop this side reading while the far side
# is half way through a swap. Under Windows PowerShell 5.1 with 'Stop', one
# line on stderr through 2>&1 throws, and the swap would carry on unwatched.
$eap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  $swapOut = @(Remote ((SwapVars $Root $Task $stageName $prevName $Wait $hashes) + $swapBlock) |
               ForEach-Object { Write-Host ('  ' + $_); "$_".Trim() })
} finally { $ErrorActionPreference = $eap }

if ($swapOut -notcontains 'SWAP OK') {
  Write-Host ''
  if ($swapOut -contains 'SWAP ROLLED BACK') {
    Write-Host '  FAIL. The new server did not answer, so the old files were put back and it' -ForegroundColor Red
    Write-Host '  was started again. The lines above say whether it answered, and server.log' -ForegroundColor Red
    Write-Host '  says why the new one did not come up.' -ForegroundColor Red
  } elseif ($swapOut -contains 'SWAP REFUSED') {
    Write-Host '  FAIL. Nothing was swapped. The lines above say why.' -ForegroundColor Red
  } else {
    Write-Host '  FAIL, AND THE BOX MAY NOT BE AS IT WAS. Look at it before anything else.' -ForegroundColor Red
    Write-Host "  The files the swap replaced are in $rootWin\$prevName and anything it could" -ForegroundColor Red
    Write-Host "  not take back out is in $rootWin\$stageName." -ForegroundColor Red
  }
  exit 1
}

# And from here, the shape Publish-Server.ps1 uses. The box answering itself
# on 127.0.0.1 is not the same as it answering the rest of the world; this is
# the one a firewall rule shows up in.
$port = [int]$settings.port
$resPort = if ($port -eq 7777) { 3000 } else { $port + 1 }
$seen = $false
for ($i = 0; $i -lt 10; $i++) {
  try {
    $c = New-Object Net.Sockets.TcpClient
    $null = $c.BeginConnect($Vps, $resPort, $null, $null).AsyncWaitHandle.WaitOne(1000)
    $seen = $c.Connected
    $c.Close()
  } catch { }
  if ($seen) { break }
  Start-Sleep -Seconds 2
}
Write-Host ''
if ($seen) {
  Write-Host ("  PASS. The server is up at {0}:{1}, resources on {2}, from here as well." -f $Vps, $port, $resPort) -ForegroundColor Green
} else {
  Write-Host ("  FAIL. The box says the server is up, and {0}:{1} does not answer from here." -f $Vps, $resPort) -ForegroundColor Red
  Write-Host '  The new files stay in place: this is the network or the firewall, and' -ForegroundColor Red
  Write-Host '  putting the old files back would not change it.' -ForegroundColor Red
  exit 1
}
