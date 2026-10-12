<#
  Install-ThornswoodServer.ps1

  Run this ON THE VPS, after Bootstrap-VPS.ps1, as Administrator.

  Unpacks the payload beside the running server, checks it there, and only
  then stops the server, swaps the new folder in and starts it. Registers a
  scheduled task so the server comes back after a reboot.

  Why a scheduled task rather than a real service: node.exe is not a service
  binary, so New-Service cannot drive it, and NSSM is not installed. A task with
  an "at startup" trigger and "run whether logged on or not" is built into
  Windows and does the same job. The cost is that it does not restart on crash
  by itself, which is what -RestartOnFailure adds via a second repeating trigger.

  STAGED, CHECKED, THEN SWAPPED, issue #446: "A failed publish deletes the live
  server before checking the new one". Until 28 September this stopped the
  server, deleted the whole root, unpacked the payload into the empty folder,
  and only then checked the load order, so a payload naming a plugin it did
  not carry left no server at all, and Publish-Server said "Nothing local was
  changed". Now, in this order:

    1. The zip is held to the hash it left the laptop with (-ZipSha256) and
       unpacked into <root>.stage-<stamp>, beside the root. The load order is
       resolved there, with the root's own prefix mapped onto the stage,
       gamemode.js is parsed, and every server file the fork builds (the
       binary, the JavaScript half and the rest ServerBuild.ps1 names, beside
       this script) is held to server-build.json (#1214). Anything wrong
       clears the stage, says INSTALL REFUSED and exits 1, with nothing
       stopped.
    2. The server is stopped, the root is renamed to <root>.prev-<stamp> and
       the stage to the root, and the world, the roster, the runtime data and
       the logs are carried across (below).
    3. It is started, and has -Wait seconds to answer on its game port and its
       resources port (left off, the shared ceiling in ServerReadyWait.ps1,
       #1938). If it does not, it is stopped, what was carried goes
       back, the new folder is renamed <root>.failed-<stamp>, the previous one
       comes back as the root and is started again: INSTALL ROLLED BACK, exit 1.

  THE SETTINGS THE SERVER RUNS ARE ITS OWN, issue #1222. The payload's
  server-settings.json is the build's, not the server's: on 29 September a
  dev publish came up with thornswoodServer, thornswoodLoadOrderRefuse and
  thornswoodRequirePass empty and an npcSettings "default" key that refused
  every NPC. So in step 1 the stage's settings are made from the running
  server's own, with only the keys a release is meant to change taken from
  the payload (ServerSettings.ps1, beside this script, says which and why).
  After the swap in step 2 the new root's settings are read back against the
  file the old server had, and any other key that differs puts the previous
  folder back before anything is started: INSTALL ROLLED BACK. A put-back
  carries the running settings into the folder it brings back the same way.

  THE JOIN PASS SWITCH IS TRUE OR FALSE, OR NOTHING IS STOPPED (#1804). The
  gamemode holds every session until its join pass arrives unless
  thornswoodRequirePass is false, so a missing or odd value reads as on
  (#1319), and a server with such a value would start holding the moment a
  new gamemode reached it, with nobody having asked. In step 1 a stage whose
  settings hold neither true nor false is refused, a running server's and a
  first install's alike, and the reason names -RequirePass on|off, which
  Publish-Server.ps1 passes here and this sets over the running server's (or
  into the payload's, on a first install) and lets the read-back find moved.
  No build carries the switch (#1223), so a first install always needs it.
  Deploy-Server.ps1 and Deploy-DevGamemode.ps1 refuse the same way.

  The newest two .prev folders are kept, and the last .failed one to read.
  -PutBack puts the newest .prev folder back the same way, keeping what it
  took out as <root>.undone-<stamp>. The renames keep every path the task and
  server-settings.json name the same, so nothing has to be rewritten.
#>
[CmdletBinding()]
param(
    [string]$Zip      = 'C:\thornswood-server.zip',
    [string]$Root     = 'C:\Thornswood-Server',
    [string]$TaskName = 'Thornswood Server',
    [switch]$NoTask,          # unpack only, start it by hand
    [switch]$StartNow,
    # The SHA-256 of the zip as it left the laptop. Publish-Server passes it;
    # an exit code from scp says a copy ended, not what arrived.
    [string]$ZipSha256 = '',
    # Start with no world. The old one is not deleted: it stays in the .prev
    # folder the old root becomes, for as long as that is kept.
    [switch]$FreshWorld,
    # Put the newest <root>.prev-<stamp> back as the root, checked the same way.
    [switch]$PutBack,
    # How long a started server has to answer before the previous one goes back.
    # Left off, the shared ceiling in ServerReadyWait.ps1, derived from
    # measured Live and Dev starts (#1938). A start that never answers still
    # rolls back.
    [int]$Wait,
    # thornswoodRequirePass for the server this installs: on holds a session
    # until its join pass arrives, off lets it act meanwhile. Set over the
    # running server's, or into a first install's; left off, the running
    # server keeps its own, and a server with neither true nor false is
    # refused (#1804, see the header). Publish-Server.ps1 -RequirePass passes it.
    [ValidateSet('', 'on', 'off')]
    [string]$RequirePass = '',
    # How many <root>.prev-<stamp> folders to keep.
    [int]$Keep = 2,
    # Lets tests\test-install-server.ps1 run this on a machine with the game on
    # it, against a scratch root. Nothing else passes it.
    [switch]$AllowGamingPc
)

$ErrorActionPreference = 'Stop'

if (-not $AllowGamingPc -and (Test-Path 'C:\Thornswood\Game\SkyrimSE.exe')) {
    throw "SkyrimSE.exe is present, so this looks like the gaming PC, not the VPS. Nothing was changed."
}
if (-not $PutBack -and -not (Test-Path -LiteralPath $Zip)) { throw "not found: $Zip" }

# A shell started before the bootstrap installed Node carries the old PATH, and
# every SSH and RDP session inherits it, so "open a new window" is advice that
# does not survive contact with remote administration. Pick the machine and user
# PATH up from the registry instead and only complain if Node is genuinely absent.
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) { Write-Host 'picked Node up from the machine PATH' -ForegroundColor DarkGray }
}
if (-not $node) {
    throw 'node is not installed. Run Bootstrap-VPS.ps1 on this machine first.'
}
Write-Host ("node {0}  at {1}" -f (& node --version), $node.Source) -ForegroundColor DarkGray

$Root     = $Root.TrimEnd('\')
$parent   = Split-Path -Parent $Root
$leaf     = Split-Path -Leaf $Root
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$stageDir = "$Root.stage-$stamp"

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Finish([string]$marker, [int]$code) { Write-Host ''; Write-Host $marker; exit $code }

# Which settings come from the payload and which stay the server's: beside
# this script, where Publish-Server sends it and where the repository keeps it.
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$settingsLib = Join-Path $here 'ServerSettings.ps1'
if (-not (Test-Path -LiteralPath $settingsLib)) {
    Say "ServerSettings.ps1 is not beside this installer, so the running server's settings could not be carried across. Nothing was changed." 'Red'
    Finish 'INSTALL REFUSED' 1
}
. $settingsLib
# What this run asked the settings to become (#1804): the join pass switch,
# when -RequirePass was given. A put-back carries the running server's
# settings into the folder it brings back and sets nothing, so asking with
# it would be a switch that does nothing; it is refused instead.
$asked = New-Object PSObject -Property (New-ThornswoodAsked $RequirePass)
$askedKeys = @(Get-ThornswoodSettingNames $asked)
$passScript = '.\scripts\release\Publish-Server.ps1'
if ($PutBack -and $askedKeys.Count) {
    Say '-PutBack sets no setting: it puts the previous folder back with the running server''s own settings. Run it without -RequirePass. Nothing was changed.' 'Red'
    Finish 'INSTALL REFUSED' 1
}
# Which server files the record holds, and holding them (#1214): beside this
# script too, sent with it.
$buildLib = Join-Path $here 'ServerBuild.ps1'
if (-not (Test-Path -LiteralPath $buildLib)) {
    Say "ServerBuild.ps1 is not beside this installer, so the payload's server files could not be held to their record. Nothing was changed." 'Red'
    Finish 'INSTALL REFUSED' 1
}
. $buildLib
# How long a start may take to answer on both ports (#1938): beside this
# script too, sent with it. Without it there is no ceiling, so nothing runs.
$waitLib = Join-Path $here 'ServerReadyWait.ps1'
if (-not (Test-Path -LiteralPath $waitLib)) {
    Say "ServerReadyWait.ps1 is not beside this installer, so how long a start may take to answer has no source. Nothing was changed." 'Red'
    Finish 'INSTALL REFUSED' 1
}
. $waitLib
if (-not $PSBoundParameters.ContainsKey('Wait')) {
    $Wait = Get-ThornswoodServerReadyWait
}
$script:running = $null

# The game port a root's settings name, and the resources port that follows
# from it: skymp5-server/ts/ui.ts gives 3000 for 7777 and the game port plus
# one otherwise. Publish-Server and Deploy-Server use the same rule.
function GamePortOf([string]$dir) {
    try {
        $cfg = [IO.File]::ReadAllText((Join-Path $dir 'server-settings.json')) | ConvertFrom-Json
        if ($cfg.port) { return [int]$cfg.port }
    } catch { }
    return 7777
}

# A folder rename on one volume, retried, because a process that has just been
# told to stop does not always let go of its files the same instant.
function MoveDir([string]$from, [string]$to) {
    for ($i = 0; $i -lt 10; $i++) {
        try { [IO.Directory]::Move($from, $to); return $true } catch { Start-Sleep -Milliseconds 700 }
    }
    return $false
}

<#
  THE OLD SERVER LETTING GO, WHICH IT DOES NOT ALWAYS DO ON ITS OWN.

  Stopping a scheduled task asks the process to end. It does not wait for it,
  and node does not drop its file handles the instant it is asked: the
  resources server under data\api holds the plugin files it is serving. A
  folder cannot be renamed while anything in it is open, so what is still
  running under this root is stopped outright and the handles are waited for.

  By this root and nothing else, because the live and the dev server are both
  node. The task runs cmd.exe, which holds server.log open, and node under it
  with a relative path on its command line, so cmd is found by the log path on
  its line and node as cmd's child. The trailing backslash matters: C:\Thornswood-Server
  is a prefix of C:\Thornswood-Server-Dev.
#>
function StopServer([string]$dir) {
    # Ours only, found before the task is stopped: cmd.exe with this root's
    # log on its line, the node it started (whose own line is relative), and
    # any node with the root on its line. The game port alone is not proof: a
    # scratch root holding a copy of the live settings names 7777, and the
    # process there is the live server (docs\RESTORING.md installs into one).
    $mark = $dir + '\'
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine })
    $ids = @()
    foreach ($p in $all) {
        if (($p.Name -eq 'node.exe' -or $p.Name -eq 'cmd.exe') -and
            $p.CommandLine.IndexOf($mark, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $ids += [int]$p.ProcessId }
    }
    foreach ($p in $all) {
        if ($p.Name -eq 'node.exe' -and $ids -contains [int]$p.ParentProcessId) { $ids += [int]$p.ProcessId }
    }
    if (-not $NoTask) { try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { } }
    $port = GamePortOf $dir
    foreach ($id in @($ids | Where-Object { $_ -gt 0 -and $_ -ne $PID } | Sort-Object -Unique)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
        Say ("stopped pid {0}" -f $id) 'Yellow'
    }
    # The port let go, when it was ours that held it.
    for ($i = 0; $i -lt 20; $i++) {
        $held = @()
        try { $held = @(Get-NetUDPEndpoint -LocalPort $port -ErrorAction Stop | Where-Object { $ids -contains [int]$_.OwningProcess }) } catch { }
        if (-not $held.Count) { break }
        Start-Sleep -Milliseconds 500
    }
}

# Both of its ports, from the box itself, for up to -Wait seconds (the shared
# ceiling unless this run passed -Wait, ServerReadyWait.ps1, #1938). UDP alone
# is not enough: the resources port is what the launcher and the client fetch
# from, and it only opens once the native server has been built without throwing.
function Answers([string]$dir) {
    $port = GamePortOf $dir
    $res = if ($port -eq 7777) { 3000 } else { $port + 1 }
    $until = (Get-Date).AddSeconds($Wait)
    while ($true) {
        $udp = $false
        try { $udp = @(Get-NetUDPEndpoint -LocalPort $port -ErrorAction Stop).Count -gt 0 } catch { }
        $tcp = $false
        if ($udp) {
            try {
                $c = New-Object Net.Sockets.TcpClient
                $null = $c.BeginConnect('127.0.0.1', $res, $null, $null).AsyncWaitHandle.WaitOne(500)
                $tcp = $c.Connected
                $c.Close()
            } catch { }
        }
        if ($tcp) { return $true }
        if ((Get-Date) -gt $until) { return $false }
        Start-Sleep -Milliseconds 700
    }
}

function TailLog([string]$dir) {
    $log = Join-Path $dir 'server.log'
    if (Test-Path -LiteralPath $log) {
        Get-Content -LiteralPath $log -Tail 30 | ForEach-Object { Say "    $_" 'Yellow' }
    } else {
        Say '    nothing was written, so node never started. Check that node is on the machine PATH.' 'Yellow'
    }
}

<#
  WHAT SURVIVES A REINSTALL, carried from the folder going out to the one
  coming in. Moved rather than copied, so nothing is set aside in %TEMP% any
  more and never cleaned up, and so the folder going out keeps what it
  shipped with and nothing it did not.

  world holds every character on the server. private holds the roster:
  door.json, allowed.json and characters.json; gamemode.js wrote down on
  20 September what losing it costs ("the character register silently stops
  being saved, the door silently never fetches a roster, and /tp silently
  refuses everybody"), and Patrick hit it on 21 September on the dev server.
  Neither has anything a build ships, so each moves whole, and only into a
  folder that has none: -FreshWorld leaves the world where it was, and a
  put-back keeps the world the folder it brings back already has. for-bot
  moves the same way (#2321): the gamemode's staff log, moderation.log,
  which the bot reads by the rule on that folder, and the rule moves with it.

  data does have shipped contents. The gamemode writes runtime state into it
  while people are online, so every file in it that the incoming folder's
  payload did not bring is copied across: runtime state comes along, and
  anything the build ships stays at the version being installed. What a
  payload brought is listed in .payload-data.txt as it is unpacked; a folder
  from before that list existed falls back to the old rule, only what it does
  not have.

  Except data\thornswood-deploy.json (#459). It is not runtime state: it is
  the deploy record of the folder it sits in, the artifact that folder's
  gamemode came from. Carried, the new folder named the old one's gamemode
  (30 Sep: e445101a, with 32dea10d installed), and a put-back had the newer
  folder's record copied over the one that came back. So each folder keeps its
  own, Publish-Server.ps1 writes the new one once this has said INSTALL OK,
  and after a put-back the folder that came back is recorded by its own
  (Restore-ThornswoodServerRecord, Artifact.ps1).

  And the logs, entry 220: server.log and thornswood.log sat in the root and
  went with every install, taking the evidence for whatever the server did
  before it. They move across and are rolled, never deleted.
#>
function Carry([string]$from, [string]$to, [bool]$skipWorld) {
    foreach ($name in 'world', 'private', 'for-bot') {
        if ($name -eq 'world' -and $skipWorld) { Say "the world is left in $from, as -FreshWorld asked" 'Yellow'; continue }
        $a = Join-Path $from $name
        $b = Join-Path $to $name
        if (-not (Test-Path -LiteralPath $a)) { continue }
        if (Test-Path -LiteralPath $b) { Say "$b is already there, so the $name in $from is left where it is" 'Yellow'; continue }
        if (MoveDir $a $b) { Say "$name carried across" 'Cyan' }
        else { Say "COULD NOT MOVE $a TO $b" 'Red'; $script:carryFailed = $true }
    }
    $a = Join-Path $from 'data'
    $b = Join-Path $to 'data'
    if (Test-Path -LiteralPath $a) {
        $list = Join-Path $to '.payload-data.txt'
        $shipped = $null
        if (Test-Path -LiteralPath $list) {
            $shipped = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($l in [IO.File]::ReadAllLines($list)) { if ($l) { [void]$shipped.Add($l) } }
        }
        $kept = 0
        # Listed from the long path. $a follows $from, which can be a
        # short 8.3 path, and FullName is the long one (issue #1156).
        $listedA = (Get-Item -LiteralPath $a).FullName
        foreach ($f in @(Get-ChildItem -LiteralPath $listedA -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $rel = $f.FullName.Substring($listedA.Length).TrimStart('\')
            # The folder's own deploy record stays with it (#459, above).
            if ($rel -eq 'thornswood-deploy.json') { continue }
            $dest = Join-Path $b $rel
            if ($shipped) { if ($shipped.Contains($rel)) { continue } }
            elseif (Test-Path -LiteralPath $dest) { continue }
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            $kept++
        }
        if ($kept -gt 0) { Say ("kept $kept runtime file" + $(if ($kept -eq 1) { '' } else { 's' }) + ' in data, including the character book') 'Cyan' }
    }
    $moved = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $from -File -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '\.log(\.\d+)?$' })) {
        $dest = Join-Path $to $f.Name
        if (Test-Path -LiteralPath $dest) { continue }
        try { Move-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop; $moved++ } catch { }
    }
    if ($moved -gt 0) { Say 'logs carried across, to be rolled rather than deleted' 'Cyan' }
}

# The newest few of each kind of folder beside the root.
function Prune([string]$kind, [int]$n) {
    Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like ($leaf + $kind) } | Sort-Object Name -Descending | Select-Object -Skip $n |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---- the stage: nothing running is touched -----------------------------------
if (-not $PutBack) {
    $bad = @()
    function Refuse([string[]]$why) {
        Write-Host ''
        foreach ($w in $why) { Say "REFUSED: $w" 'Red' }
        Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
        Say 'the stage is cleared, and the server was not stopped or changed' 'Red'
        Finish 'INSTALL REFUSED' 1
    }
    if ($ZipSha256) {
        $have = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash
        if ($have -ne $ZipSha256.ToUpperInvariant()) { Refuse @("$Zip arrived different from what was sent") }
        Say 'the zip is what was sent' 'DarkGray'
    }
    # A stage a run that died part way left behind was never swapped in.
    Prune '.stage-*' 0
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
    Expand-Archive -LiteralPath $Zip -DestinationPath $stageDir -Force
    Say "unpacked to $stageDir" 'Cyan'
    # What this payload brought into data, for Carry to leave alone.
    $sd = Join-Path $stageDir 'data'
    $shippedData = @()
    if (Test-Path -LiteralPath $sd) {
        $listedSd = (Get-Item -LiteralPath $sd).FullName
        $shippedData = @(Get-ChildItem -LiteralPath $listedSd -Recurse -File -Force | ForEach-Object { $_.FullName.Substring($listedSd.Length).TrimStart('\') })
    }
    [IO.File]::WriteAllLines((Join-Path $stageDir '.payload-data.txt'), [string[]]$shippedData)

    # ---- check the stage before trusting it ----------------------------------
    # A byte order mark on this file is fatal and says nothing useful when it
    # happens: node stops on the first character with "Unexpected token" and the
    # stack points into skymp's settings loader, not at whatever wrote the file.
    # PowerShell 5.1 puts one there when 7 does not, so a payload built on one
    # machine can start fine and the same payload built on another cannot. Taken
    # off here as well as fixed at the source, because payloads built before that
    # fix are still sitting in people's folders.
    $settingsPath = Join-Path $stageDir 'server-settings.json'
    $s = $null
    if (-not (Test-Path -LiteralPath $settingsPath)) { Refuse @('the payload has no server-settings.json') }
    $bytes = [IO.File]::ReadAllBytes($settingsPath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        [IO.File]::WriteAllBytes($settingsPath, $bytes[3..($bytes.Length - 1)])
        Say 'took a byte order mark off server-settings.json, node cannot parse one' 'Yellow'
    }
    try { $s = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json } catch { Refuse @("server-settings.json does not parse: $($_.Exception.Message)") }

    # The running server's own settings, with only the release's keys taken
    # from the payload (#1222, see the header). Written into the stage, so
    # every check below is of the file that will run. A root with no settings
    # has no server to keep them from, and takes the payload's whole, so those
    # are held to what no server should start with.
    $runPath = Join-Path $Root 'server-settings.json'
    if (Test-Path -LiteralPath $runPath) {
        try { $script:running = [IO.File]::ReadAllText($runPath) | ConvertFrom-Json }
        catch { Refuse @("the settings $Root runs on do not parse ($($_.Exception.Message)), so they cannot be carried across") }
        $m = Join-ThornswoodServerSettings $script:running $s $ThornswoodInstallKeys $asked
        foreach ($l in $m.Said) { Say $l 'Cyan' }
        $s = $m.Settings
        # Before the file is written, so a refusal leaves only the stage to clear.
        $passWhy = Get-ThornswoodPassSwitchProblem $s $passScript
        if ($passWhy) { Refuse @($passWhy) }
        [IO.File]::WriteAllText($settingsPath, (ConvertTo-Json -InputObject $s -Depth 30), (New-Object Text.UTF8Encoding($false)))
    } else {
        foreach ($k in $askedKeys) {
            $s | Add-Member -NotePropertyName $k -NotePropertyValue $asked.$k -Force
            Say "set as this run asked: $k" 'Cyan'
        }
        $first = @(Get-ThornswoodServerSettingsProblems $s | ForEach-Object { "the payload's settings have $_, and there is no server here whose own settings would be kept instead" })
        $passWhy = Get-ThornswoodPassSwitchProblem $s $passScript
        if ($passWhy) { $first += $passWhy }
        if ($first.Count) { Refuse $first }
        if ($askedKeys.Count) { [IO.File]::WriteAllText($settingsPath, (ConvertTo-Json -InputObject $s -Depth 30), (New-Object Text.UTF8Encoding($false))) }
        Say "there are no settings in $Root yet, so the payload's are its first" 'DarkGray'
    }

    # The load order resolves, against the stage. The paths in it are written
    # out in full under the root (Export-ServerPayload writes them for the root
    # it is told), so the root's prefix is read as the stage's: the files are
    # in the stage now and will be at those paths once it is the root. A
    # shortened load order shifts every index after the gap, so a plugin that
    # is nowhere is a refusal, not a warning.
    $order = @($s.loadOrder)
    if (-not $order.Count) { $bad += 'server-settings.json has no loadOrder' }
    $missing = @()
    foreach ($p in $order) {
        $at = ([string]$p) -replace '/', '\'
        if ($at.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) { $at = $stageDir + $at.Substring($Root.Length) }
        if (-not (Test-Path -LiteralPath $at)) { $missing += $p }
    }
    if ($missing.Count) {
        Say ("{0} plugin(s) in the load order are not in the payload or on disk:" -f $missing.Count) 'Red'
        foreach ($m in $missing) { Say "    $m" 'Red' }
        $bad += 'load order does not resolve. The server would refuse to start, and a shortened load order would shift every index after the gap.'
    }
    # What the task starts.
    if (-not $NoTask -and -not (Test-Path -LiteralPath (Join-Path $stageDir 'dist_back\skymp5-server.js'))) {
        $bad += 'the payload has no dist_back\skymp5-server.js, which is what the task starts'
    }
    # The gamemode is there and parses, here, before anything is stopped. A
    # payload with none used to pass this without a word and start a server
    # with no gamemode at all: no door, no join pass (#1336).
    $gm = Join-Path $stageDir 'gamemode.js'
    if (-not (Test-Path -LiteralPath $gm)) {
        $bad += 'the payload has no gamemode.js, so the server would start with no gamemode: no door and no join pass'
    } else {
        # Continue for the call: under Stop, Windows PowerShell turns the first
        # line node writes to stderr into an error that ends this script.
        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $said = @(& $node.Source --check $gm 2>&1) } finally { $ErrorActionPreference = $eap }
        if ($LASTEXITCODE -ne 0) { $bad += ('gamemode.js does not parse: ' + ((@($said | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) | Select-Object -First 6) -join ' | ')) }
    }
    # Every server file is the build the payload's own record names: the
    # binary, the JavaScript half the task starts, and the rest the fork
    # builds, and no server file the record does not list (#1214). A payload
    # with no record is server files nobody recorded: Export-ServerPayload
    # puts records\server-build.json in every one.
    $rec = Join-Path $stageDir 'server-build.json'
    if (-not (Test-Path -LiteralPath $rec)) {
        $bad += 'the payload carries no server-build.json, so nothing says its server files are a recorded build'
    } else {
        try {
            $recObj = [IO.File]::ReadAllText($rec) | ConvertFrom-Json
            $bad += @(Get-ThornswoodServerBuildProblems $recObj (Get-ThornswoodServerFolderSums $stageDir) 'the payload' 'server-build.json')
        } catch { $bad += "server-build.json does not parse: $($_.Exception.Message)" }
    }
    if ($bad.Count) { Refuse $bad }
    Say ("load order: all {0} plugins present" -f $order.Count) 'Green'

    $candidate = $stageDir
    $aside     = "$Root.prev-$stamp"
    $failedAs  = "$Root.failed-$stamp"
} else {
    $last = @(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like ($leaf + '.prev-*') } | Sort-Object Name -Descending | Select-Object -First 1)
    if (-not $last.Count) {
        Say "there is no $leaf.prev-<stamp> beside $Root, so there is nothing to put back" 'Red'
        Finish 'INSTALL REFUSED' 1
    }
    $candidate = $last[0].FullName
    $aside     = "$Root.undone-$stamp"
    # A put-back that does not answer goes back to being the .prev it was.
    $failedAs  = $candidate
    Say "putting back $candidate" 'Cyan'
    # What it brings back is the older release, not the older settings: the
    # running server's go into it, with only the release's keys kept (#1222).
    # A running file that cannot be read does not stop a put-back, which is
    # the way out of a bad install; the folder then goes back as it was.
    $runPath = Join-Path $Root 'server-settings.json'
    $backPath = Join-Path $candidate 'server-settings.json'
    if ((Test-Path -LiteralPath $runPath) -and (Test-Path -LiteralPath $backPath)) {
        try {
            $run = [IO.File]::ReadAllText($runPath) | ConvertFrom-Json
            $back = [IO.File]::ReadAllText($backPath) | ConvertFrom-Json
            $m = Join-ThornswoodServerSettings $run $back $ThornswoodInstallKeys
            foreach ($l in $m.Said) { Say $l 'Cyan' }
            [IO.File]::WriteAllText($backPath, (ConvertTo-Json -InputObject $m.Settings -Depth 30), (New-Object Text.UTF8Encoding($false)))
            $script:running = $run
        } catch {
            Say "the settings could not be read ($($_.Exception.Message)), so $candidate goes back with its own" 'Yellow'
        }
    } else {
        # Said, the same as a file that will not read (#1336): with either
        # missing nothing is carried and nothing is read back afterwards.
        $gone = @(@($runPath, $backPath) | Where-Object { -not (Test-Path -LiteralPath $_) })
        Say ("there is no " + ($gone -join ' and no ') + ", so no settings are carried and $candidate goes back with its own") 'Yellow'
    }
}

# ---- the swap ------------------------------------------------------------------
$hadRoot = Test-Path -LiteralPath $Root
$script:carryFailed = $false
if ($hadRoot) {
    Say 'stopping the server' 'Cyan'
    StopServer $Root
    if (-not (MoveDir $Root $aside)) {
        # Name what is still open, start the old one again, and stop rather than
        # half installing. The old folder is exactly as it was.
        $stuck = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
                   Where-Object {
                       try { $h = [IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None'); $h.Close(); $false }
                       catch { $true }
                   } | Select-Object -First 5)
        foreach ($f in $stuck) { Say ("still open: {0}" -f $f.FullName) 'Red' }
        Say "could not move $Root aside after ten tries. Something outside this script is holding those files." 'Red'
        if (-not $PutBack) { Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue }
        if ($StartNow -and -not $NoTask) { Start-ScheduledTask -TaskName $TaskName; Say 'the old server was started again, as it was' 'Yellow' }
        Finish 'INSTALL REFUSED' 1
    }
}
if (-not (MoveDir $candidate $Root)) {
    Say "COULD NOT MOVE $candidate TO $Root" 'Red'
    if ($hadRoot -and (MoveDir $aside $Root)) {
        if ($StartNow -and -not $NoTask) { Start-ScheduledTask -TaskName $TaskName }
        Say 'the old server is back where it was' 'Yellow'
        Finish 'INSTALL REFUSED' 1
    }
    Finish 'INSTALL FAILED' 1
}
Say "swapped in; what it replaced is $aside" 'Cyan'
if ($hadRoot) { Carry $aside $Root ([bool]$FreshWorld) }

# The way back: what was carried goes back, the new folder is kept as
# $failedAs to read, the previous one is the root again and, when this run
# starts servers, is started and asked whether it answers.
function GoBack([string]$keptAs) {
    Say 'putting the previous server back' 'Yellow'
    StopServer $Root
    Carry $Root $aside ([bool]$FreshWorld)
    if (-not (MoveDir $Root $failedAs)) {
        Say "COULD NOT MOVE $Root ASIDE, so the previous server is still in $aside. Look at the box." 'Red'
        Finish 'INSTALL FAILED' 1
    }
    if (-not (MoveDir $aside $Root)) {
        Say "COULD NOT MOVE $aside BACK TO $Root. The new one is in $failedAs. Look at the box." 'Red'
        Finish 'INSTALL FAILED' 1
    }
    if ($StartNow -and -not $NoTask) {
        Start-ScheduledTask -TaskName $TaskName
        $gp = GamePortOf $Root
        $rp = if ($gp -eq 7777) { 3000 } else { $gp + 1 }
        if (Answers $Root) { Say ("the previous server is back and answering on {0}" -f $rp) 'Yellow' }
        else { Say "THE PREVIOUS SERVER IS BACK AND IT STILL IS NOT ANSWERING on $rp" 'Red'; TailLog $Root }
    } else {
        Say 'the previous server is back in place, not started, as this run starts nothing' 'Yellow'
    }
    if (-not $PutBack) { Say "$keptAs is kept as $failedAs to read" 'DarkGray' }
    if ($script:carryFailed) { Finish 'INSTALL FAILED' 1 }
    Finish 'INSTALL ROLLED BACK' 1
}

<#
  READ BACK, BEFORE ANYTHING STARTS (#1222). The settings now in the root
  against the file the old server had when it was stopped: every key outside
  the release's own must be the same. The stage was made from the running
  file, so a difference means it moved after that (a deploy that ran in
  between, say), or that the carry did not hold, and either way the new
  folder would start with settings nobody chose. The previous folder goes
  back instead, with what it had.
#>
if ($hadRoot -and $null -ne $script:running) {
    $was = $null
    $now = $null
    try { $was = [IO.File]::ReadAllText((Join-Path $aside 'server-settings.json')) | ConvertFrom-Json } catch { }
    try { $now = [IO.File]::ReadAllText((Join-Path $Root 'server-settings.json')) | ConvertFrom-Json } catch { }
    $moved = @('server-settings.json, which cannot be read')
    # What this run asked for (#1804) moved on purpose, as the release's keys did.
    if ($null -ne $was -and $null -ne $now) { $moved = @(Compare-ThornswoodCarried $was $now @($ThornswoodInstallKeys + $askedKeys)) }
    if ($moved.Count) {
        Say ('read back: ' + ($moved -join ', ') + ' would not be what the server had, so nothing is started and the previous folder goes back') 'Red'
        GoBack 'the folder whose settings did not read back'
    }
    Say 'read back: every setting outside this release is the one the server had' 'Green'
}

# See Carry. A root that has never had a private folder gets an empty one:
# the door writes allowed.json itself once it has fetched, and the register
# writes characters.json, but neither can write into a folder that is not
# there. Saying so here is the difference between "this server has no roster
# yet" and the silence that cost three reports.
$privDir = Join-Path $Root 'private'
if (-not (Test-Path -LiteralPath $privDir)) {
    New-Item -ItemType Directory -Path $privDir -Force | Out-Null
    Say 'no roster to restore: this root has never had a private folder.' 'Yellow'
    Say '  /tp will refuse everybody until door.json is put there.' 'Yellow'
}
# Where the gamemode writes its staff log for the bot (#2321), made here so
# the bot's rule is on the folder before the first staff action makes the
# file, which then takes it. Locked below.
$forBotDir = Join-Path $Root 'for-bot'
if (-not (Test-Path -LiteralPath $forBotDir)) { New-Item -ItemType Directory -Path $forBotDir -Force | Out-Null }

<#
  WHO MAY READ THE SERVER'S FOLDERS, issue #1105.

  A folder made under C:\ inherits Windows' rule that BUILTIN\Users may read
  it and make files in it, and every service account on the box is in Users:
  the bot's NT SERVICE\ThornswoodBot, the site's LOCAL SERVICE, the build
  runner's. So every one of them could read private\door.json, the key the
  site trusts, and the rest of this folder. The stage this install swapped in
  was made under C:\ like any other, so it is locked here, every install:

    the root and everything under it takes nothing from C:\. SYSTEM, which
      the server's task runs as, and Administrators have Full Control. The
      rules put on the folder it replaced by name are carried across: the
      site's read on the files directly in the root and in data
      (Deploy-Docs.ps1 -RunAs), and anything else set on purpose. Users,
      Everyone, Authenticated Users and CREATOR OWNER never are.
    private\ takes nothing from the root either: SYSTEM and Administrators
      only.
    for-bot\ takes nothing from the root either (#2321): SYSTEM and
      Administrators, the rules it has by name, and read for the bot's
      account, NT SERVICE\ThornswoodBot, when the bot's service is on the box,
      on the folder and so on the staff log the gamemode makes in it later.
      Install-Bot.ps1 gives the same rule; given here too, so a server that
      has had no bot install since #2321 does not start a staff log the bot
      cannot open.
    what it replaced, <root>.prev-<stamp> or .undone-<stamp>, is locked the
      same way, since it holds the old settings and data.

  tests\test-server-acl.ps1 runs this on scratch folders and reads it back.
#>
# $readers: SIDs given read on the folder and everything in it (the bot's, on for-bot).
function Lock-ServerDir([string]$dir, [string]$from, [string[]]$readers = @()) {
    $broad = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-3-0')
    $tree = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $carried = @()
    if ($from -and (Test-Path -LiteralPath $from)) {
        $carried = @((Get-Acl -LiteralPath $from).GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]) |
                     Where-Object { $broad -notcontains $_.IdentityReference.Value })
    }
    $acl = Get-Acl -LiteralPath $dir
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in @($acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))) {
        if ($broad -contains $r.IdentityReference.Value) { [void]$acl.RemoveAccessRuleSpecific($r) }
    }
    foreach ($r in $carried) { $acl.AddAccessRule($r) }
    foreach ($s in 'S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            (New-Object Security.Principal.SecurityIdentifier($s)), 'FullControl', $tree, 'None', 'Allow')))
    }
    foreach ($s in @($readers | Where-Object { $_ })) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            (New-Object Security.Principal.SecurityIdentifier($s)), 'Read', $tree, 'None', 'Allow')))
    }
    # Writes back only the access rules. Set-Acl can also try to write the audit
    # part, which needs a privilege the build runner's account does not have
    # (issue #1120, Set-ThornswoodAclAccess in Bot-Service.ps1).
    $item = Get-Item -LiteralPath $dir -Force
    if ($PSVersionTable.PSEdition -eq 'Core') {
        if ($item -is [IO.DirectoryInfo]) { [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]$item, [Security.AccessControl.DirectorySecurity]$acl) }
        else { [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]$item, [Security.AccessControl.FileSecurity]$acl) }
    } else { $item.SetAccessControl($acl) }
}
function Lock-ServerRoot([string]$dir, [string]$from, [string]$botSid = '') {
    try {
        Lock-ServerDir $dir $from
        $d = Join-Path $dir 'data'
        if (Test-Path -LiteralPath $d) { Lock-ServerDir $d $(if ($from) { Join-Path $from 'data' } else { '' }) }
        $p = Join-Path $dir 'private'
        if (Test-Path -LiteralPath $p) { Lock-ServerDir $p '' }
        $fb = Join-Path $dir 'for-bot'
        if (Test-Path -LiteralPath $fb) { Lock-ServerDir $fb '' @($botSid) }
        Say "locked $dir to SYSTEM and Administrators, with the rules it had by name; private is theirs alone" 'Cyan'
        if ((Test-Path -LiteralPath $fb) -and $botSid) { Say "the bot's account may read $fb, where the gamemode writes its staff log" 'Cyan' }
    } catch { Say "COULD NOT LOCK ${dir}: $($_.Exception.Message)" 'Red' }
}
# The bot's account, when its service is on this box, for for-bot (#2321).
$botSid = ''
if (Get-Service -Name 'ThornswoodBot' -ErrorAction SilentlyContinue) {
    try { $botSid = (New-Object Security.Principal.NTAccount('NT SERVICE\ThornswoodBot')).Translate([Security.Principal.SecurityIdentifier]).Value }
    catch { Say "the bot's service is here but its account could not be looked up ($($_.Exception.Message)), so for-bot has no rule for it: run .\scripts\deploy\Install-Bot.ps1 once" 'Yellow' }
} else { Say "no bot service on this box, so nothing reads for-bot yet" 'DarkGray' }
Lock-ServerRoot $Root $(if ($hadRoot) { $aside } else { '' }) $botSid
if ($hadRoot -and (Test-Path -LiteralPath $aside)) { Lock-ServerRoot $aside '' }
# The site reads server.log and data here (Deploy-Docs.ps1). Once the Users
# rule is gone it reads them only through its own rule, which a box whose
# site deploy came before this folder existed does not have yet.
$siteTask = Get-ScheduledTask -TaskName 'Thornswood Docs' -ErrorAction SilentlyContinue
if ($siteTask -and $siteTask.Principal.UserId -and $siteTask.Principal.UserId -notmatch '(?i)^(NT AUTHORITY\\)?SYSTEM$') {
    $siteSid = ''
    try { $siteSid = (New-Object Security.Principal.NTAccount([string]$siteTask.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value } catch { }
    $has = @((Get-Acl -LiteralPath $Root).GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq $siteSid })
    if (-not $has.Count) { Say "the site's account has no rule on $Root yet, so it cannot read server.log: run .\scripts\deploy\Deploy-Docs.ps1 once" 'Yellow' }
}

# The roller the task runs in front of the server, from beside this script:
# Publish-Server sends the two together, and run by hand from tools they are
# already side by side. Without it the server still starts, the log just is
# not rolled, so it is said here rather than stopped over.
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# Publish-Server scp's Roll-Log.ps1 to C:\ beside this installer. Repo layout
# keeps it under scripts\vps\. Prefer the same folder, then the repo path.
$rollSrc = $null
foreach ($cand in @(
    (Join-Path $here 'Roll-Log.ps1'),
    (Join-Path $here '..\vps\Roll-Log.ps1')
)) {
    if (Test-Path -LiteralPath $cand) { $rollSrc = $cand; break }
}
$roller  = Join-Path $Root 'roll-log.ps1'
if ($rollSrc) {
    Copy-Item -LiteralPath $rollSrc -Destination $roller -Force
} else {
    Write-Host "Roll-Log.ps1 is not beside this installer, so server.log will not be rolled at start." -ForegroundColor Yellow
}
# ---- end of the roller copy

# ---- scheduled task --------------------------------------------------------
if (-not $NoTask) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }

    # Through cmd rather than straight at node, purely so there is a log.
    # A scheduled task throws its child's stdout and stderr away, so a server
    # that refuses to start leaves nothing behind at all: the task reports it
    # ran, the port never opens, and there is no way to find out why without
    # sitting in an ssh session running it by hand. Redirecting is the whole
    # reason cmd is in the chain.
    #
    # roll-log.ps1 goes first, because cmd holds server.log open for as long
    # as node runs and nothing can move it until then (see Roll-Log.ps1). &
    # rather than &&, so a roll that fails, or a roller that is not there,
    # still starts the server.
    $log = Join-Path $Root 'server.log'
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $cmd = ('/c ""{2}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{3}" -Path "{1}" & "{0}" dist_back/skymp5-server.js >> "{1}" 2>&1"' -f $node.Source, $log, $psExe, $roller)
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" `
                                      -Argument $cmd `
                                      -WorkingDirectory $Root
    $triggers = @(New-ScheduledTaskTrigger -AtStartup)

    # Priority 4, normal, not Task Scheduler's default of 7. A task registered
    # without -Priority starts its process below normal, with I/O priority 1
    # (low) and memory priority 2, and node, started by the task's cmd.exe,
    # inherits all three. Measured on the VPS on 5 October: both game servers
    # ran BelowNormal, I/O priority 1, memory priority 2, while the build
    # runners, the bot and lsass ran Normal, 2 and 5.
    #
    # The low I/O priority is what the server waited on when somebody first
    # entered a cell (#1931). The kernel trace of 4 October 17:19
    # (logs\dev\stall-trace-20261004-173319) has the dev server's main thread
    # reading its own memory back from pagefile.sys: 91 reads in a login that
    # took 1.9 s, 51 in the 2.1 s after a move into WhiterunWorld. Every read
    # went out at low priority and took 24 ms on average, up to 78 ms, held
    # back in steps of the 15.6 ms clock tick, while none of the 79,000 normal
    # priority I/Os on the same disk in those 90 s took 5 ms. Windows holds
    # low priority I/O back while normal priority I/O is going, and on the VPS
    # it always is, mostly from the two servers' own saves; low priority I/O
    # waited longest in the seconds the build job did no I/O at all.
    #
    # Memory priority 2 puts the server's pages below every service's: first
    # to be trimmed from its working set, and once trimmed, first to be given
    # to other uses, after which touching them again is a read from the page
    # file. Priority 4 gives memory priority 5 too, so nothing else sets it.
    #
    # 4 to 6 is the band Microsoft's table starts as NORMAL_PRIORITY_CLASS.
    # tests\test-server-task-priority.ps1 registers a task with these settings
    # and measures the CPU, I/O and memory priority of the program its cmd.exe
    # starts.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                             -DontStopIfGoingOnBatteries `
                                             -StartWhenAvailable `
                                             -RestartCount 999 `
                                             -RestartInterval (New-TimeSpan -Minutes 1) `
                                             -ExecutionTimeLimit ([TimeSpan]::Zero) `
                                             -Priority 4
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers `
                           -Settings $settings -Principal $principal | Out-Null
    Write-Host "scheduled task '$TaskName' registered, starts at boot, restarts every minute if it stops" -ForegroundColor Cyan
}

function Tidy {
    Prune '.prev-*' $Keep
    Prune '.undone-*' 2
    Prune '.failed-*' 1
}

if (-not ($StartNow -and -not $NoTask)) {
    Tidy
    Say 'not started, so not checked. Start it and watch the resources port answer.' 'Yellow'
    Finish 'INSTALL OK' 0
}

# Rolled whatever its size rather than deleted, so the run before this
# install is server.log.1 and the tail below reads only this one.
# Deleting it is how the evidence for the last crash disappeared.
$log = Join-Path $Root 'server.log'
if (Test-Path -LiteralPath $roller) {
    try { & $roller -Path $log -Force | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray } }
    catch { Write-Host ("could not roll server.log: {0}" -f $_.Exception.Message) -ForegroundColor Yellow }
}

Start-ScheduledTask -TaskName $TaskName

<#
  THE PORT OF THE SERVER THIS SCRIPT JUST INSTALLED, NOT 3000.

  This probed 127.0.0.1:3000 whatever it had installed. 3000 is the LIVE
  server's resources port, and the live server is up, so a DEV install
  asked the live server whether dev had started and was told yes. Read out
  of the settings that were just swapped in, so it is right for any root
  without anybody passing a number.
#>
$gamePort = GamePortOf $Root
$resPort = if ($gamePort -eq 7777) { 3000 } else { $gamePort + 1 }
Say ("started, giving it {0} seconds to answer on UDP {1} and on {2}" -f $Wait, $gamePort, $resPort) 'DarkGray'
if (Answers $Root) {
    Say ("the server is answering on {0}, game port {1}" -f $resPort, $gamePort) 'Green'
    Tidy
    Say ("the task appends everything it prints to {0}\server.log, rolled at 4 MB before each start, five kept" -f $Root) 'DarkGray'
    Finish 'INSTALL OK' 0
}

Write-Host ''
Say 'the server did not come up. Its log says:' 'Red'
TailLog $Root
if (-not $hadRoot) {
    Say 'there was no server here before this one, so there is nothing to go back to.' 'Red'
    Finish 'INSTALL FAILED' 1
}

# ---- the way back ----------------------------------------------------------------
GoBack 'what did not start'
