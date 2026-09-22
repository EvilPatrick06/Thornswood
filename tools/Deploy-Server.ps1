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

  The load order goes up with its paths rewritten to the VPS plugin folder,
  and any plugin it names that the box does not have goes up with it. The
  file in the build keeps this machine's paths; only the copy sent changes.

  Stop before copy, always. scam_native.node is a loaded image while node is
  running and Windows will not let you overwrite a mapped file, so a copy over
  a live server fails halfway and leaves a server that starts against a file
  which is half old and half new.

    .\Deploy-Server.ps1                  1 minute of notice, nobody kicked
    .\Deploy-Server.ps1 -Minutes 3
    .\Deploy-Server.ps1 -Mode restart    counts down and empties the room
    .\Deploy-Server.ps1 -Now             no warning at all
#>
[CmdletBinding()]
param(
  [string]$Dist    = 'C:\Thornswood-Dev\skymp\build\dist\server',
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
  [string]$Data    = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition\Data'
)

$ErrorActionPreference = 'Stop'
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')
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
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File '$far'" 2>&1
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}

function OnlineNow {
  # The gamemode rewrites online.json whenever the number moves. No file, or an
  # unreadable one, is treated as nobody home rather than as a reason to stop:
  # this is a courtesy check, not a gate.
  $out = Remote @"
try {
  `$j = Get-Content '$Root/data/online.json'.Replace('/','\') -Raw -EA Stop | ConvertFrom-Json
  `$j.now
} catch { 0 }
"@
  $n = 0
  foreach ($line in $out) {
    if ("$line".Trim() -match '^\d+$') { $n = [int]$Matches[0]; break }
  }
  return $n
}

# tools\gamemode.js is the source. The build output has a copy of it that cmake
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
    "    .\tools\Deploy-Server.ps1 -Dist <path to skymp\build\dist\server>" + [Environment]::NewLine +
    [Environment]::NewLine +
    "If you have not built the fork, this deploy is not yours to run. The build tree lives on" + [Environment]::NewLine +
    "Patrick's machine, and .\tools\Check-ShipReady.ps1 says what this machine is missing."
  )
}

$src = Join-Path $Here 'gamemode.js'
$built = Join-Path $Dist 'gamemode.js'
if (Test-Path -LiteralPath $src) {
  $a = (Get-Item $src).Length
  $b = if (Test-Path -LiteralPath $built) { (Get-Item $built).Length } else { -1 }
  if ($a -ne $b) {
    Copy-Item $src $built -Force
    Write-Host ("  gamemode.js taken from tools ({0:N0} bytes, build had {1})" -f `
      $a, $(if ($b -lt 0) { 'none' } else { '{0:N0}' -f $b })) -ForegroundColor DarkGray
  }
}

$files = 'scam_native.node', 'gamemode.js', 'server-settings.json'
foreach ($f in $files) {
  $p = Join-Path $Dist $f
  if (-not (Test-Path -LiteralPath $p)) { throw "not built: $p" }
  '{0,-22} {1:N0} bytes' -f $f, (Get-Item $p).Length | Write-Host
}

# ---------------------------------------------------------- which build is this
#
# The binaries have always been copied rather than rebuilt here, and until
# 2026-09-17 nothing mapped scam_native.node back to a commit. The only evidence
# that the shipped one carried the committed server changes was that its file
# date was six minutes later than the last edit to ScampServer.cpp, which is an
# argument rather than a proof.
#
# tools\server-build.json is that proof: the hash of the binary a release was
# tested with, and the commit it came from. Regenerate it with
# tools\New-ServerBuildRecord.ps1 after every rebuild.
#
# No record yet means carry on with a warning, so a machine that has not made one
# can still deploy. A record that disagrees is a stop: it means this binary is not
# the one the release was built and tested against, and shipping it would put an
# unknown server in front of everybody.
$recordPath = Join-Path $Here 'server-build.json'
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
    Write-Host '    .\tools\New-ServerBuildRecord.ps1' -ForegroundColor Yellow
    Write-Host '  If you did not, find out what changed before this reaches the VPS.' -ForegroundColor Yellow
    throw 'server binary does not match tools\server-build.json'
  }
  Write-Host ('{0,-22} matches the record, commit {1}' -f 'build', $rec.source.commit.Substring(0, 8)) -ForegroundColor DarkGray
}
else {
  Write-Host ''
  Write-Host '  No tools\server-build.json, so nothing says which commit this binary is.' -ForegroundColor Yellow
  Write-Host '  Make one with .\tools\New-ServerBuildRecord.ps1 and commit it.' -ForegroundColor Yellow
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
$ours = Join-Path $Here 'Thornswood-Content.esp'

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
    $ask = Join-Path $Here 'Request-Restart.ps1'
    if (Test-Path -LiteralPath $ask) {
      # -RestartFollows because this script stops and starts the task a few
      # lines below. Request-Restart refuses a kicking mode without it, and
      # that refusal is the point: a kick with no restart behind it is what
      # leaves people in an empty world.
      & $ask -Minutes $Minutes -Mode $Mode -Why $Why -Vps $Vps -User $User `
             -Data "$Root/data" -RestartFollows
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
Write-Host 'Stopping the server...'
Remote @"
Stop-ScheduledTask -TaskName '$Task' -EA SilentlyContinue
# The process on this root's own port and nothing else. Matching every
# node.exe running skymp5-server took the dev server down with the live one
# and only started the live one back up. The port comes from the settings in
# the root being deployed, the same way Deploy-DevGamemode picks its process.
`$s = Get-Content ('$Root'.Replace('/', '\') + '\server-settings.json') -Raw | ConvertFrom-Json
`$port = [int]`$s.port
'stopping whatever holds UDP ' + `$port
`$pids = @()
`$pids += @(Get-NetUDPEndpoint -LocalPort `$port -EA SilentlyContinue | Select-Object -ExpandProperty OwningProcess)
# Only the UDP port. The line that also stopped whatever listened on the TCP
# port one above it was copied from the dev script, where that port is the
# server's own HTTP and belongs to the same process. On the live root it is
# 7778, which is the voice service, a separate process that carries voice
# chat, the launcher's character choices and the chat command queue the
# lockpick fix rides on. Stopping the game server must never take that down.
foreach (`$id in (`$pids | Sort-Object -Unique)) {
  if (`$id -gt 0) { Stop-Process -Id `$id -Force -EA SilentlyContinue; 'stopped pid ' + `$id }
}
Start-Sleep -Seconds 2
'stopped'
"@ | ForEach-Object { "  $_" }

Write-Host ''
Write-Host 'Copying...'
foreach ($p in $sendPlugins) {
  $n = Split-Path $p -Leaf
  & scp @ssh $p "$User@${Vps}:$remotePlugins/$n"
  if ($LASTEXITCODE -ne 0) { throw "scp failed for plugin $n" }
  Write-Host "  plugins/$n"
}
foreach ($f in $files) {
  $src = Join-Path $Dist $f
  if ($f -eq 'server-settings.json') { $src = $settingsForVps }
  & scp @ssh $src "$User@${Vps}:$Root/$f"
  if ($LASTEXITCODE -ne 0) { throw "scp failed for $f" }
  Write-Host "  $f"
}

# The record goes up with the binary, so the box itself answers what it is
# running. Hash $Root/scam_native.node against it there and the two halves of
# the question, what source and what binary, both have an answer on the machine
# serving people rather than only on a developer's disk.
if (Test-Path -LiteralPath $recordPath) {
  & scp @ssh $recordPath "$User@${Vps}:$Root/server-build.json"
  if ($LASTEXITCODE -ne 0) { throw 'scp failed for server-build.json' }
  Write-Host '  server-build.json'
}

Write-Host ''
Write-Host 'Starting...'
Remote @"
Start-ScheduledTask -TaskName '$Task' -EA SilentlyContinue
Start-Sleep -Seconds 6
`$s = Get-Content ('$Root'.Replace('/', '\') + '\server-settings.json') -Raw | ConvertFrom-Json
`$port = [int]`$s.port
`$up = Get-NetUDPEndpoint -LocalPort `$port -EA SilentlyContinue | Select-Object -First 1
if (`$up) { 'server up on UDP ' + `$port + ', pid ' + `$up.OwningProcess } else { 'SERVER IS NOT LISTENING on UDP ' + `$port }
if (Test-Path '$Root/server.log'.Replace('/','\')) {
  '--- server.log, last 25 ---'
  Get-Content ('$Root/server.log'.Replace('/','\')) -Tail 25
}
"@ | ForEach-Object { "  $_" }
