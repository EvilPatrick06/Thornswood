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
    .\Deploy-Server.ps1 -PutBack         the files the last deploy replaced go
                                         back in, checked the same way
    .\Deploy-Server.ps1 -RequirePass on  the same deploy, and the live join
                                         pass hold set on (off lets a session
                                         act until its pass arrives)
    .\Deploy-Server.ps1 -Devs 123,456 -Playtesters 789
                                         the same deploy, and the live
                                         server's written role lists set
    .\Deploy-Server.ps1 -GamemodeOnly    the committed gamemode alone, from
                                         any machine, with no server build
                                         here (see GAMEMODE ONLY below)

  GAMEMODE ONLY (#1089). Every run above needs this machine's fork build: the
  server files, the build's settings and the load order are all read from
  -Dist. A gamemode is not part of that build. It is a versioned artifact
  any machine makes byte for byte from a commit (#459). -GamemodeOnly sends
  that, from any machine, and reads nothing out of -Dist:
    - gamemode.js from the gamemode artifact, the build stamp made from that
      artifact (channel main), and Thornswood-Content.esp into plugins when
      its size is not the box's copy's (the rule the full deploy uses);
    - server-settings.json made on the box: the running server's own file,
      copied into the stage unchanged, and the swap reads it back with no key
      allowed to move.
  Before anything is sent it asks the box which server build it runs, and
  refuses unless the box's server-build.json is the record the commit holds
  (ServerBuild.ps1 says how the two are compared), so the gamemode comes from
  a commit whose recorded server build is the one running. A gamemode that
  needs a newer server build goes the full way, from a machine with the
  build. It sets no setting, so it takes none of -RequirePass, -Devs and
  -Playtesters, and a change to what Deploy-Gamemode.ps1 writes for live (the
  load order, the NPC, gear, reloot and damage settings, ServerSettings.ps1
  names them) goes the full way too. The notice, the stage, the check, the
  swap and -PutBack are the same as every other run. Patrick, 5 Oct: any
  machine may do it.

  THE LIVE SERVER KEEPS ITS OWN SETTINGS (#1221, #1222). A build whose
  server-settings.json is not the live server's (port 7777, not the dev voice
  port or name, not thornswoodServer dev, no npcSettings "default" key) is
  refused before anything is sent. The one that goes up is carried on the box
  into the running server's own, taking from the build only what
  Deploy-Gamemode.ps1 writes for live on purpose (ServerSettings.ps1 says
  which and why), and the swap reads it back before the start: any other key
  that is not what the server had puts the old files back.

  THE JOIN PASS AND THE ROLE LISTS CHANGE ONLY WHEN THIS RUN SAYS SO (#1223).
  thornswoodRequirePass, thornswoodDevs and thornswoodPlaytesters are never
  taken from the build, which kept whatever one machine was once given and
  sent it again on every deploy from there. -RequirePass on|off, -Devs and
  -Playtesters set them on the box, in the carry, the way
  Deploy-DevGamemode.ps1 -RequirePass sets dev's; without them the live
  server keeps its own. A live server whose join pass switch is neither true
  nor false is refused until -RequirePass says which (#1319).

  EVERY SERVER FILE GOES, AND ONLY THE RECORDED BUILD (#1214). The binary,
  the JavaScript half the server runs and the rest the fork builds
  (ServerBuild.ps1) go up together with records\server-build.json, each held
  to it here and again in the stage on the box. One that is not the recorded
  build, or a server file the record does not list, stops the deploy before
  anything is sent. Until then only the binary went, so the box could run a
  binary of one build beside the JavaScript half of another.

  The files a deploy replaced stay in $Root\.prev-<stamp>, the newest two.
  -PutBack is the one command that puts the newest back: the same stop, renames,
  start and check, and if the old files do not answer either, what was running
  goes back in again. What it took out is kept in $Root\.undone-<stamp>.
  Swap.ps1 holds the blocks that do all of it on the box (issue #446).
#>
[CmdletBinding()]
param(
  [string]$Dist    = (& (Join-Path $PSScriptRoot '..\release\Where.ps1') ServerDist),
  [string]$Vps     = '',
  [string]$User    = '',
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
  [int]$Wait       = 60,
  # Put the files the last deploy replaced back in, and nothing else. Needs no
  # build on this machine. See the header.
  [switch]$PutBack,
  # thornswoodRequirePass on the live server (#937, #410, #1223): on holds a
  # session until its join pass arrives, off lets it act meanwhile, and a
  # session with no pass is ended at three minutes either way. Set on the box
  # in this run only; left off, the live server keeps its own, and one with
  # neither true nor false is refused, because the gamemode reads that as on
  # (#1319). Live goes on only when Patrick says Main.
  [ValidateSet('', 'on', 'off')]
  [string]$RequirePass = '',
  <#
    Who may run /tp, /goto, /restart and the rest, written down. Each
    replaces that list on the live box in this run; left off, the live server
    keeps its own (#1223). Until then these were Deploy-Gamemode.ps1's, written
    into the build.

    Patrick, 21 September, on the dev server: "Dev has no playtetser list so
    I can't tp like I can on main", and after the roster copy went in, "still
    can't tp says no list".

    THERE ARE TWO ROLE SOURCES AND THE WRITTEN ONE WINS FIRST. rolelist reads
    thornswoodDevs and thornswoodPlaytesters straight out of
    server-settings.json, and only if neither names anybody does it fall
    through to the Discord roster in private\door.json. The roster is the
    better source, because a playtester added in Discord is a playtester
    without anybody editing a file. It is also the one that depends on a
    folder existing on the VPS, on the door having fetched, and on an install
    not having deleted it, and every one of those has failed.

    So the owner gets a written line that depends on none of it. The refusal
    itself prints the number to put here: "Ask Patrick to add profile
    <id>". Neither list is a secret and neither has a default, so a server
    told nobody still has nobody.

      -Devs 123456789
      -Devs 123456789,987654321 -Playtesters 555,666
  #>
  [long[]]$Devs        = @(),
  [long[]]$Playtesters = @(),
  # The committed gamemode alone, with no server build on this machine
  # (#1089). See GAMEMODE ONLY in the header.
  [switch]$GamemodeOnly
)

$ErrorActionPreference = 'Stop'
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=yes')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\vps\Send-Script.ps1')
if (-not $User) { $User = Get-ThornswoodVpsUser }
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
. (Join-Path $Here 'Swap.ps1')
. (Join-Path $Here 'Artifact.ps1')
. (Join-Path $Here 'ServerSettings.ps1')
. (Join-Path $Here 'ServerBuild.ps1')

function Remote($script) {
  # Send-Script.ps1 (issue #1070): a long script goes as a file of its own
  # name, removed after, and the far side's exit code comes back.
  return Invoke-ThornswoodRemote -Target "$User@$Vps" -SshArgs $ssh -Script $script
}

function Get-StageDirectories([string]$stageRoot, [string[]]$relativePaths) {
  $stagePath = [IO.Path]::GetFullPath($stageRoot).TrimEnd('\')
  $prefix = $stagePath + '\'
  $parents = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach ($relative in $relativePaths) {
    if (-not $relative -or [IO.Path]::IsPathRooted($relative) -or $relative.Contains(':')) {
      throw "Invalid stage destination: $relative"
    }
    $target = [IO.Path]::GetFullPath([IO.Path]::Combine($stagePath, $relative.Replace('/', '\')))
    if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Stage destination escapes its directory: $relative"
    }
    $null = $parents.Add([IO.Path]::GetDirectoryName($target))
  }
  return @($parents | Sort-Object)
}

# ==== thornswood live deploy warning ====
# Shared with tests\test-deploy-gamemode-warning.ps1 and the OnlineNow harness.
# Deploy-Gamemode.ps1 builds locally and never stops the live server; this is
# the live half of issue #520. The names come from private\online-names.json,
# which the gamemode keeps beside online.json but outside the served folder.
function Read-LiveOnline($lines) {
  # Online stays a courtesy count: unreadable or missing is nobody, not a gate.
  # Data is where restart.json must land so the gamemode sees it.
  $room = @{ Data = ''; Online = 0; Up = $null; Names = @(); Said = @($lines) }
  foreach ($line in @($lines)) {
    $t = "$line".Trim()
    if ($t -match '^DATA (.+)$') { $room.Data = $Matches[1].Trim() }
    elseif ($t -match '^NAME (.+)$') { $room.Names += $Matches[1].Trim() }
    elseif ($t -match '^ONLINE (\d+)$') { $room.Online = [int]$Matches[1] }
    elseif ($t -match '^UP (yes|no)$') { $room.Up = ($Matches[1] -eq 'yes') }
  }
  # Nothing on the game port is nobody on, whatever online.json still says.
  if ($room.Up -eq $false) { $room.Online = 0; $room.Names = @() }
  if (-not $room.Data) {
    $room.Data = (($Root -replace '\\', '/').TrimEnd('/') + '/data')
  }
  return $room
}

function Get-LiveOnline {
  Read-LiveOnline (Remote @"
`$root = '$Root'.Replace('/','\')
`$port = 0
`$d = 'data'
`$p = 'private'
try {
  `$s = Get-Content (Join-Path `$root 'server-settings.json') -Raw -EA Stop | ConvertFrom-Json
  `$port = [int]`$s.port
  if (`$s.dataDir) { `$d = [string]`$s.dataDir }
  if (`$s.privDir) { `$p = [string]`$s.privDir }
} catch { }
`$dataPath = [IO.Path]::Combine(`$root, `$d)
'DATA ' + `$dataPath.Replace('\', '/')
`$up = `$true
if (`$port -gt 0) {
  try {
    `$u = @(Get-NetUDPEndpoint -EA Stop | Where-Object { `$_.LocalPort -eq `$port })
    `$up = (`$u.Count -gt 0)
    if (`$up) { 'UP yes' } else { 'UP no' }
  } catch { }
}
if (-not `$up) { 'ONLINE 0' }
else {
  try {
    `$j = Get-Content (Join-Path `$dataPath 'online.json') -Raw -EA Stop | ConvertFrom-Json
    if (`$null -eq `$j -or `$null -eq `$j.now) { throw 'no count' }
    'ONLINE ' + [int]`$j.now
  } catch { 'ONLINE 0' }
  try {
    `$n = Get-Content ([IO.Path]::Combine(`$root, `$p, 'online-names.json')) -Raw -EA Stop | ConvertFrom-Json
    foreach (`$x in @(`$n.names)) { if (`$x) { 'NAME ' + `$x } }
  } catch { }
}
"@)
}

function Format-Names($names) {
  # Who, for the person running the deploy. A gamemode older than the names
  # file writes none, and then the count is all there is to say.
  $n = @($names | Where-Object { $_ })
  if (-not $n.Count) { return '' }
  return ': ' + ($n -join ', ')
}

function OnlineNow {
  # Kept as a number for callers and for tests\test-deploy-server-online.ps1.
  return (Get-LiveOnline).Online
}

function Warn-LiveRoom {
  # Same switches Deploy-DevGamemode documents: -Now, -Minutes, -Mode, -Why.
  # Refuses to stop when people are on and the warning cannot go out, unless
  # -Now was passed. Does not refuse merely because somebody is online: it
  # warns them first, then the stop below runs.
  Write-Host ''
  $room = Get-LiveOnline
  $on = [int]$room.Online
  $who = Format-Names $room.Names

  if ($Now) {
    if ($on -gt 0) {
      Write-Host ("  -Now: {0} online{1}, not warned. They respawn when it comes back." -f $on, $who) -ForegroundColor Yellow
    } else {
      Write-Host '  -Now: nobody is online'
    }
    return
  }

  if ($on -le 0) {
    if ($room.Up -eq $false) {
      Write-Host '  the live server is not listening, so nobody is on it'
    } else {
      Write-Host '  nobody is online, going straight down'
    }
    return
  }

  Write-Host ("  $on online$who, $Mode, giving them $Minutes " +
              $(if ($Minutes -eq 1) { 'minute' } else { 'minutes' }))
  $ask = Join-Path $Here '..\vps\Request-Restart.ps1'
  if (-not (Test-Path -LiteralPath $ask)) {
    Write-Host ''
    Write-Host "  THE WARNING DID NOT GO OUT. Request-Restart.ps1 is missing." -ForegroundColor Red
    Write-Host "  $on people are in the world and the restart below would drop them with no" -ForegroundColor Red
    Write-Host '  notice. Nothing has been swapped in and the server is still running exactly' -ForegroundColor Red
    Write-Host '  as it was. Put Request-Restart.ps1 back, or pass -Now if you mean to take' -ForegroundColor Red
    Write-Host '  it down without telling anybody.' -ForegroundColor Red
    Remote "Remove-Item -LiteralPath '$rootWin\$stageName' -Recurse -Force -EA SilentlyContinue" | Out-Null
    exit 1
  }

  # -RestartFollows because this script stops and starts the task a few
  # lines below. Request-Restart refuses a kicking mode without it, and
  # that refusal is the point: a kick with no restart behind it is what
  # leaves people in an empty world.
  # Data comes from the box's own server-settings.json (via Get-LiveOnline),
  # not a hardcoded $Root/data, so restart.json lands where the gamemode looks.
  & $ask -Minutes $Minutes -Mode $Mode -Why $Why -Vps $Vps -User $User `
         -Data $room.Data -RestartFollows

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
# ==== end thornswood live deploy warning ====

# The two halves that run on the box, the stage check and the swap, are in
# Swap.ps1 beside this script, loaded at the top: $checkBlock, $swapBlock,
# SwapVars and $putBackPick. Deploy-DevGamemode.ps1 uses the same ones.

# ------------------------------------------------------------- -PutBack
# The newest .prev folder back in, through the same swap as a deploy, after
# the same warning. Nothing here needs the build, so it runs before the
# checks that do, and sends no gamemode, so it has none to check.
function Invoke-PutBack {
  $script:rootWin   = $Root.Replace('/', '\')
  # Warn-LiveRoom clears a stage by this name when the warning does not go
  # out. A put-back has none, so it names one that is never there.
  $script:stageName = '.stage-none'
  Write-Host ''
  Write-Host "Putting back the newest .prev folder in $rootWin..."
  Warn-LiveRoom
  $eap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $backOut = @(Remote ((SwapVars $Root $Task '.stage-none' '.undone-none' $Wait ([ordered]@{})) + $putBackPick + $swapBlock) |
                 ForEach-Object { Write-Host ('  ' + $_); "$_".Trim() })
  } finally { $ErrorActionPreference = $eap }
  if (-not (Show-SwapResult $backOut "$rootWin\.undone-<stamp>")) { exit 1 }
  # The record that came back with the files is what the box says it runs.
  Restore-SwapRecord "$User@$Vps" $ssh $Root $backOut "$Root/data/thornswood-deploy.json" 'gamemode'
  Write-Host ''
  Write-Host '  PASS. The previous files are back and the server is answering.' -ForegroundColor Green
  exit 0
}
# What this run asks the live server's settings to become, set on the box in
# the carry (#1223). A put-back sends no settings and carries none, so asking
# with it would be a switch that does nothing; it is refused instead.
$asked = New-ThornswoodAsked $RequirePass $Devs $Playtesters
if ($PutBack -and $asked.Count) {
  Write-Host ''
  Write-Host '  -PutBack sets no setting: it puts the previous files back with the live server''s own settings.' -ForegroundColor Red
  Write-Host '  Run it without -RequirePass, -Devs and -Playtesters, then a deploy with them.' -ForegroundColor Yellow
  throw '-PutBack was given -RequirePass, -Devs or -Playtesters. Nothing was sent and the server was not touched.'
}
# A gamemode-only deploy lets no setting move (#1089), so the switches that set
# one are a full deploy's. And -PutBack puts back whatever the last deploy
# replaced, a gamemode-only one or a full one, so it takes no -GamemodeOnly to
# say which.
if ($GamemodeOnly -and $PutBack) {
  throw '-PutBack puts back what the last deploy replaced, whichever kind it was. Run it without -GamemodeOnly. Nothing was sent and the server was not touched.'
}
if ($GamemodeOnly -and $asked.Count) {
  Write-Host ''
  Write-Host '  -GamemodeOnly sets no setting: the live server keeps its own, and no key may move.' -ForegroundColor Red
  Write-Host '  -RequirePass, -Devs and -Playtesters go with a full deploy, from a machine with the server build.' -ForegroundColor Yellow
  throw '-GamemodeOnly was given -RequirePass, -Devs or -Playtesters. Nothing was sent and the server was not touched.'
}
if ($PutBack) { Invoke-PutBack }

# game\gamemode.js is the source. The build output has a copy of it that cmake
# writes during configure, and that copy is stale the moment the source is
# edited without a reconfigure. Deploying the stale one is how a change gets
# written, committed, shipped, and then quietly not happen.
# The same prerequisite as Deploy-Gamemode, and the same message, because a
# machine without the fork built hits this one first if it skips that step.
# Unlike that script this one DOES reach the VPS, so it stops before anything
# leaves the machine rather than part way through a copy.
#
# -GamemodeOnly reads nothing out of -Dist (#1089), so it does not ask for it.
if (-not $GamemodeOnly -and -not (Test-Path -LiteralPath $Dist)) {
  throw (
    "No skymp server build at $Dist, so there is nothing to send." + [Environment]::NewLine +
    [Environment]::NewLine +
    "This script copies a LOCAL build of the server to the VPS. Without the build there is" + [Environment]::NewLine +
    "nothing to copy, and nothing has been sent." + [Environment]::NewLine +
    [Environment]::NewLine +
    "If you have the fork built somewhere else, point at it:" + [Environment]::NewLine +
    "    .\scripts\deploy\Deploy-Server.ps1 -Dist <path to skymp\build\dist\server>" + [Environment]::NewLine +
    [Environment]::NewLine +
    "If only the gamemode changed, this machine needs no build: the committed gamemode goes" + [Environment]::NewLine +
    "live on its own, onto the server build that is running, with" + [Environment]::NewLine +
    "    .\scripts\deploy\Deploy-Server.ps1 -GamemodeOnly" + [Environment]::NewLine +
    [Environment]::NewLine +
    "A new server build needs the fork built. .\scripts\release\Build-Engine.ps1 builds it, and" + [Environment]::NewLine +
    ".\scripts\release\Check-ShipReady.ps1 says what this machine is missing."
  )
}

# And it goes up as the gamemode artifact (issue #459, Artifact.ps1):
# game\gamemode.js as the commit holds it, in one zip named by commit and hash,
# sent to the box's store before the stage. The copy in the build is made the
# artifact's whenever the two differ, by hash and not by size as it was, since
# an edit that kept the size used to stay behind.
# Refused before the box is touched when gamemode.js, or anything else this
# sends out of the repository (our plugin, the server build's record), has
# uncommitted changes (#1121).
. (Join-Path $Here 'Artifact.ps1')
$artifact = New-ThornswoodArtifact -Component gamemode -RepoDir (Join-Path $Here '..\..') -Paths 'game/gamemode.js' `
  -AlsoSends 'game/content/Thornswood-Content.esp', 'records/server-build.json'
'{0,-22} {1}' -f 'artifact', (Format-ThornswoodArtifact $artifact) | Write-Host
$src = Join-Path $artifact.Folder 'game\gamemode.js'
# -GamemodeOnly has no build to copy it into, and sends the artifact's own.
$built = $src
if (-not $GamemodeOnly) {
  $built = Join-Path $Dist 'gamemode.js'
  if (-not (Test-Path -LiteralPath $built) -or
      (Get-FileHash -LiteralPath $src).Hash -ne (Get-FileHash -LiteralPath $built).Hash) {
    Copy-Item -LiteralPath $src -Destination $built -Force
    Write-Host ("  gamemode.js taken from the artifact ({0:N0} bytes)" -f (Get-Item -LiteralPath $built).Length) -ForegroundColor DarkGray
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

if (-not $GamemodeOnly) {
  foreach ($f in 'gamemode.js', 'server-settings.json') {
    if (-not (Test-Path -LiteralPath (Join-Path $Dist $f))) { throw "not built: $(Join-Path $Dist $f)" }
  }

  # THE BUILD'S SETTINGS ARE THE LIVE SERVER'S, OR NOTHING GOES (#1221). This
  # sends server-settings.json from the build, and on 29 Sep the shared clone's
  # build held the dev server's (port 7787, the name Thornswood Dev), left by an
  # older dev publish. Sent, live would have come up where no launcher looks for
  # it. The same test Export-ServerPayload.ps1 makes for a live payload, and an
  # npcSettings "default" key, which refuses every NPC. Before the stamp is
  # written, the box is asked anything or the artifact is sent.
  $buildSettings = Get-Content -LiteralPath (Join-Path $Dist 'server-settings.json') -Raw | ConvertFrom-Json
  $notLive = @(Get-ThornswoodServerSettingsProblems $buildSettings 'main')
  if ($notLive.Count) {
    Write-Host ''
    Write-Host ("  server-settings.json in $Dist is not the live server's:") -ForegroundColor Red
    foreach ($w in $notLive) { Write-Host ('    ' + $w) -ForegroundColor Red }
    Write-Host '  Run .\scripts\deploy\Deploy-Gamemode.ps1, which writes the live ones, then deploy again.' -ForegroundColor Yellow
    throw "server-settings.json in $Dist is not the live server's. Nothing was sent and the server was not touched."
  }
}

# The build stamp Deploy-Gamemode.ps1 left beside gamemode.js goes up with it,
# so the box can say which gamemode it runs. It is made again here when it does
# not describe the gamemode about to be sent, which is what happens when the
# copy above came from the artifact's game\gamemode.js ($src), because a
# stamp naming a different gamemode is worse than none. When it is the same
# file, use it so git can say whether the commit holds it. See BuildStamp.ps1.
. (Join-Path $Here '..\release\BuildStamp.ps1')
$stampPath = Join-Path $Dist 'thornswood-build.json'
if ($GamemodeOnly) {
  # No build to leave one in, so it is made every run from the artifact,
  # beside the artifact's zip, and never taken from an earlier run (#1089).
  $stampPath = [IO.Path]::ChangeExtension($artifact.Zip, '.main-build.json')
  Remove-Item -LiteralPath $stampPath -Force -ErrorAction SilentlyContinue
}
if (-not (Test-ThornswoodBuildStamp -Path $stampPath -Gamemode $built)) {
  $stampFrom = $built
  if ((Test-Path -LiteralPath $src) -and
      (Get-FileHash -LiteralPath $src).Hash -eq (Get-FileHash -LiteralPath $built).Hash) { $stampFrom = $src }
  $null = Save-ThornswoodBuildStamp -Gamemode $stampFrom -Channel main -RepoDir (Split-Path -Parent (Split-Path -Parent $Here)) -Path $stampPath -Artifact $artifact
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
# records\server-build.json is that proof: the hash of every server file the
# fork builds (the binary, the JavaScript half the server runs, and the rest
# ServerBuild.ps1 names) and the one commit they came from. Regenerate it with
# scripts\release\New-ServerBuildRecord.ps1 after every rebuild.
#
# Every one of them goes up together, so the box never runs a binary of one
# build beside the JavaScript half of another, and any of them that is not the
# recorded build, or a server file the record does not list, stops the deploy
# before anything is sent (#1214). Until then only the binary went and only
# the binary was held, and a build with no record went with a warning.
$recordPath = Join-Path $Here '..\..\records\server-build.json'
if (-not (Test-Path -LiteralPath $recordPath)) {
  throw 'there is no records\server-build.json, so nothing says which build these server files are. Nothing was sent and the server was not touched.'
}
$rec = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
$serverFiles = @()
if ($GamemodeOnly) {
  # No server file goes, so there is none here to hold to the record. The
  # record is held to the box instead, below, before anything is sent: the
  # server running there must be the build this commit records (#1089).
  $recordSum = Get-ThornswoodRecordSum ([IO.File]::ReadAllBytes($recordPath))
} else {
  $notBuild = @(Get-ThornswoodServerBuildProblems $rec (Get-ThornswoodServerFolderSums $Dist) $Dist 'records\server-build.json')
  if ($notBuild.Count) {
    Write-Host ''
    Write-Host '  The server files are not the build this release recorded:' -ForegroundColor Red
    foreach ($w in $notBuild) { Write-Host ('    ' + $w) -ForegroundColor Red }
    Write-Host ("    recorded build came from commit {0}" -f $rec.source.commit) -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  If you rebuilt on purpose, record the new build and deploy again:' -ForegroundColor Yellow
    Write-Host '    .\scripts\release\New-ServerBuildRecord.ps1' -ForegroundColor Yellow
    Write-Host '  If you did not, find out what changed before this reaches the VPS.' -ForegroundColor Yellow
    throw 'server files do not match records\server-build.json'
  }
  $serverFiles = @((Get-ThornswoodServerRecordFiles $rec).Keys)
  Write-Host ('{0,-22} every server file is the recorded build, commit {1}' -f 'build', $rec.source.commit.Substring(0, 8)) -ForegroundColor DarkGray
}

$files = @($serverFiles) + @('gamemode.js', 'server-settings.json')
# -GamemodeOnly's settings are the box's own, made there (#1089).
if ($GamemodeOnly) { $files = @('gamemode.js') }
foreach ($f in $files) {
  $p = Join-Path $Dist ($f -replace '/', '\')
  if ($f -eq 'gamemode.js') { $p = $built }
  if (-not (Test-Path -LiteralPath $p)) { throw "not built: $p" }
  '{0,-22} {1:N0} bytes' -f $f, (Get-Item $p).Length | Write-Host
}

if ($GamemodeOnly) {
  # ------------------------------------------ which build the live server runs
  #
  # -GamemodeOnly (#1089). Asked of the box before anything is sent, and only
  # asked: this writes nothing there, and it is short enough to go on the
  # command line, so not even a script file goes up before every answer is in.
  # The box says its port, whether its join pass switch is true or false, the
  # record of the server build it runs, and the size of its
  # Thornswood-Content.esp. No load order is read, here or there: the box
  # keeps its own settings, and the stage check holds its own load order to
  # the plugins on its disk, as it does for every deploy.
  $boxRead = @'
$s = $null
try { $s = [IO.File]::ReadAllText((Join-Path $root 'server-settings.json')) | ConvertFrom-Json } catch { }
if ($null -eq $s) { 'SETTINGS unreadable' }
else {
  'PORT ' + [int]$s.port
  if (@($s.PSObject.Properties | ForEach-Object { $_.Name }) -notcontains 'thornswoodRequirePass') { 'PASS missing' }
  elseif ($s.thornswoodRequirePass -is [bool]) { 'PASS set' }
  else { 'PASS neither' }
}
$rp = Join-Path $root 'server-build.json'
if (Test-Path -LiteralPath $rp) {
  'RECORD ' + (Get-ThornswoodRecordSum ([IO.File]::ReadAllBytes($rp)))
  try { 'RECORDCOMMIT ' + [string](([IO.File]::ReadAllText($rp) | ConvertFrom-Json).source.commit) } catch { }
} else { 'RECORD none' }
$ep = Join-Path $root 'plugins\Thornswood-Content.esp'
if (Test-Path -LiteralPath $ep) { 'ESP ' + (Get-Item -LiteralPath $ep).Length } else { 'ESP none' }
'@
  $boxSaid = @(Remote ($ThornswoodRecordSumText + "`r`n`$root = '" + $Root.Replace('/', '\').Replace("'", "''") + "'`r`n" + $boxRead) |
               ForEach-Object { "$_".Trim() })
  $livePort = 0
  $boxPass = ''
  $boxRecord = ''
  $boxRecordCommit = ''
  $boxEsp = ''
  foreach ($l in $boxSaid) {
    if ($l -match '^PORT (\d+)$') { $livePort = [int]$Matches[1] }
    elseif ($l -match '^PASS (set|missing|neither)$') { $boxPass = $Matches[1] }
    elseif ($l -match '^RECORD ([0-9a-f]{64}|none)$') { $boxRecord = $Matches[1] }
    elseif ($l -match '^RECORDCOMMIT ([0-9a-f]*)$') { $boxRecordCommit = $Matches[1] }
    elseif ($l -match '^ESP (\d+|none)$') { $boxEsp = $Matches[1] }
  }
  $refusals = @()
  if (-not $boxRecord -or -not $boxEsp -or ($boxSaid -notcontains 'SETTINGS unreadable' -and -not $boxPass)) {
    $refusals += ('the box did not answer what it runs: ' + (($boxSaid | Where-Object { $_ }) -join ' | '))
  } else {
    if ($boxSaid -contains 'SETTINGS unreadable') { $refusals += ('the settings in ' + $Root + ' cannot be read, so there is no telling which process is this server') }
    elseif ($livePort -le 0) { $refusals += 'the live server''s settings name no port' }
    # The join pass hold fails closed (#1319): a switch that is neither true
    # nor false holds, and would start doing so the moment this gamemode
    # reached it, with nobody having asked. The full deploy refuses it in
    # the carry; this run sets no setting, so it refuses it here.
    if ($boxPass -eq 'missing') { $refusals += (Get-ThornswoodPassSwitchProblem ([pscustomobject]@{})) }
    elseif ($boxPass -eq 'neither') { $refusals += (Get-ThornswoodPassSwitchProblem ([pscustomobject]@{ thornswoodRequirePass = $null })) }
    $ours8 = ([string]$rec.source.commit)
    if ($ours8.Length -gt 8) { $ours8 = $ours8.Substring(0, 8) }
    if ($boxRecord -eq 'none') {
      $refusals += 'the live server has no server-build.json, so nothing says which server build it runs. A full deploy, from a machine with the build, puts one there.'
    } elseif ($boxRecord -ne $recordSum) {
      $theirs8 = 'an unreadable one'
      if ($boxRecordCommit) { $theirs8 = 'commit ' + $boxRecordCommit.Substring(0, [Math]::Min(8, $boxRecordCommit.Length)) }
      $refusals += ('the live server runs another server build (' + $theirs8 + ') than the one records\server-build.json holds at this commit (commit ' +
               $ours8 + '). A gamemode goes live onto the server build its commit records; one that needs another goes the full way, from a machine with the build.')
    }
  }
  if ($refusals.Count) {
    Write-Host ''
    Write-Host '  -GamemodeOnly is refused:' -ForegroundColor Red
    foreach ($w in $refusals) { Write-Host ('    ' + $w) -ForegroundColor Red }
    throw '-GamemodeOnly was refused. Nothing was sent and the server was not touched.'
  }
  Write-Host ('{0,-22} the live server runs the build this commit records, commit {1}, so only the gamemode goes' -f 'build', $ours8) -ForegroundColor DarkGray

  # OUR PLUGIN GOES WITH IT WHEN IT CHANGED. Patrick, 5 Oct: a gamemode change
  # often calls for new records in it. It comes from the repository, not the
  # build (OUR OWN PLUGIN below says why), and by the rule the full deploy
  # uses: sent when the box has none, or one of another size.
  $ours = Join-Path $Here '..\..\game\content\Thornswood-Content.esp'
  $sendPlugins = @()
  $changed = @()
  if (Test-Path -LiteralPath $ours) {
    $ourLen = (Get-Item -LiteralPath $ours).Length
    if ($boxEsp -eq 'none') {
      $sendPlugins += $ours
      $changed += ('Thornswood-Content.esp  not on the box -> {0:N0} bytes' -f $ourLen)
    } elseif ([int64]$boxEsp -ne $ourLen) {
      $sendPlugins += $ours
      $changed += ('Thornswood-Content.esp  {0:N0} -> {1:N0} bytes' -f [int64]$boxEsp, $ourLen)
    }
  }
  Write-Host ''
  if ($sendPlugins.Count) {
    Write-Host '  Thornswood-Content.esp will go up before the restart:' -ForegroundColor Yellow
    foreach ($c in $changed) { Write-Host ('    changed: ' + $c) -ForegroundColor Yellow }
  } else {
    Write-Host '  Thornswood-Content.esp is on the VPS at the same size' -ForegroundColor DarkGray
  }
} else {
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
  $src = Join-Path $Dist ($f -replace '/', '\')
  if ($f -eq 'gamemode.js') { $src = $built }
  if ($f -eq 'server-settings.json') { $src = $settingsForVps }
  $send[$f] = $src
}
# The record goes up with the server files, so the box itself answers what it
# is running, and the stage is held to it there before anything stops: every
# file it lists, by hash (ServerBuild.ps1, part of Swap.ps1's check). The
# two halves of the question, what source and what files, both have an answer
# on the machine serving people rather than only on a developer's disk.
# -GamemodeOnly sends no server file, so the box keeps the record it has,
# which is this commit's (#1089).
if (-not $GamemodeOnly) { $send['server-build.json'] = $recordPath }
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
Write-Host 'The gamemode artifact, to the store on the box...'
Send-ThornswoodArtifact -Artifact $artifact -Target "$User@$Vps" -SshArgs $ssh

Write-Host ''
Write-Host "Staging in $rootWin\$stageName..."
# A stage left by a run that died part way is cleared first. It was never
# swapped in, so nothing is lost with it.
# ==== thornswood staged directories ====
$stageParents = @(Get-StageDirectories "$rootWin\$stageName" @($send.Keys))
$parentLiterals = ($stageParents | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ','
Remote @"
Get-ChildItem -LiteralPath '$rootWin' -Directory -Force -EA SilentlyContinue |
  Where-Object { `$_.Name -like '.stage-*' } |
  ForEach-Object { Remove-Item -LiteralPath `$_.FullName -Recurse -Force -EA SilentlyContinue }
New-Item -ItemType Directory -Path '$rootWin\$stageName\plugins' -Force | Out-Null
foreach (`$parent in @($parentLiterals)) {
  New-Item -ItemType Directory -Path `$parent -Force | Out-Null
}
"@ | Out-Null
# ==== end thornswood staged directories ====
foreach ($rel in $send.Keys) {
  Invoke-ThornswoodNative { & scp @ssh $send[$rel] "$User@${Vps}:$stageFar/$rel" }
  if ($LASTEXITCODE -ne 0) { throw "scp failed for $rel. The server has not been touched." }
  Write-Host "  $rel"
}

# The running server's own settings, carried into the staged file on the box,
# with only the keys Deploy-Gamemode writes for live taken from the build
# (#1222, ServerSettings.ps1), and what this run asked for set over them
# (#1223). The file this rewrites is hashed there, so the check below holds
# the stage to it like every file sent from here. The swap's read-back lets
# exactly those keys differ from what the server had.
Write-Host ''
Write-Host 'Keeping the live server''s own settings...'
if ($GamemodeOnly) {
  # The running server's own file, copied into the stage unchanged, after the
  # box's record and join pass switch are read again; no key may move at the
  # swap (#1089, ServerSettings.ps1's $settingsKeepBlock).
  $liveKeys = @()
  $carryScript = [IO.File]::ReadAllText((Join-Path $Here 'ServerSettings.ps1')) + "`r`n" + $ThornswoodRecordSumText + "`r`n" +
                 (SwapVars $Root $Task $stageName $prevName $Wait $hashes $liveKeys) + ('$WantRecord = ''' + $recordSum + '''' + "`r`n") + $settingsKeepBlock
} else {
  $liveKeys = @($ThornswoodGamemodeKeys + @($asked.Keys))
  $carryScript = [IO.File]::ReadAllText((Join-Path $Here 'ServerSettings.ps1')) + "`r`n" +
                 (SwapVars $Root $Task $stageName $prevName $Wait $hashes $liveKeys) + (Get-ThornswoodAskedLine $asked) + $settingsCarryBlock
}
$carryOut = @(Remote $carryScript | ForEach-Object { Write-Host ('  ' + $_); "$_".Trim() })
$carried = @($carryOut | Where-Object { $_ -match '^CARRIED [0-9a-f]{64}$' })
if (-not $carried.Count) {
  Write-Host ''
  Write-Host '  THE SETTINGS COULD NOT BE CARRIED ACROSS, so nothing was stopped and nobody was warned.' -ForegroundColor Red
  Write-Host '  The server is still running exactly as it was. The lines above say why.' -ForegroundColor Red
  exit 1
}
$hashes['server-settings.json'] = $carried[0].Substring(8)

$checkOut = @(Remote ((SwapVars $Root $Task $stageName $prevName $Wait $hashes $liveKeys) + $checkBlock) |
              ForEach-Object { Write-Host ('  ' + $_); "$_".Trim() })
if ($checkOut -notcontains 'STAGE OK') {
  Write-Host ''
  Write-Host '  THE STAGE DID NOT CHECK OUT, so nothing was stopped and nobody was warned.' -ForegroundColor Red
  Write-Host '  The server is still running exactly as it was. The lines above say why.' -ForegroundColor Red
  exit 1
}

# ------------------------------------------------------------- the warning
# People on live are counted and warned here. Deploy-Gamemode.ps1 has no stop.
Warn-LiveRoom

Write-Host ''
Write-Host 'Stopping, swapping in and starting...'
# A stray line on stderr must not stop this side reading while the far side
# is half way through a swap. Under Windows PowerShell 5.1 with 'Stop', one
# line on stderr through 2>&1 throws, and the swap would carry on unwatched.
$eap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  $swapOut = @(Remote ((SwapVars $Root $Task $stageName $prevName $Wait $hashes $liveKeys) + $swapBlock) |
               ForEach-Object { Write-Host ('  ' + $_); "$_".Trim() })
} finally { $ErrorActionPreference = $eap }

if ($swapOut -notcontains 'SWAP OK') {
  Write-Host ''
  if ($swapOut -contains 'SWAP ROLLED BACK') {
    Write-Host '  FAIL. The new server did not answer, or its settings did not read back as the' -ForegroundColor Red
    Write-Host '  server''s own, so the old files were put back and it was started again. The' -ForegroundColor Red
    Write-Host '  lines above say which, and whether it answered.' -ForegroundColor Red
  } elseif ($swapOut -contains 'SWAP REFUSED') {
    Write-Host '  FAIL. Nothing was swapped. The lines above say why.' -ForegroundColor Red
  } else {
    Write-Host '  FAIL, AND THE BOX MAY NOT BE AS IT WAS. Look at it before anything else.' -ForegroundColor Red
    Write-Host "  The files the swap replaced are in $rootWin\$prevName and anything it could" -ForegroundColor Red
    Write-Host "  not take back out is in $rootWin\$stageName." -ForegroundColor Red
  }
  exit 1
}

# Swapped in and answering on the box: it records that the live server runs
# this gamemode artifact, and serves the record from its data folder, so
# http://<box>:3000/thornswood-deploy.json says which commit is live.
Save-SwapPreviousRecord "$User@$Vps" $ssh $Root $prevName "$Root/data/thornswood-deploy.json"
$null = Set-ThornswoodArtifactCurrent -Artifact $artifact -Target "$User@$Vps" -SshArgs $ssh -Root $Root -Beside "$Root/data/thornswood-deploy.json"

# And from here, the shape Publish-Server.ps1 uses. The box answering itself
# on 127.0.0.1 is not the same as it answering the rest of the world; this is
# the one a firewall rule shows up in.
$port = if ($GamemodeOnly) { $livePort } else { [int]$settings.port }
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
