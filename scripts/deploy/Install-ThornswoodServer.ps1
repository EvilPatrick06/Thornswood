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

  A LOAD ORDER THAT DROPS WHAT THE SERVER LOADS IS REFUSED (#2320). On
  5 Oct at 9:56 PM a dev publish of a fresh engine build carried the engine's
  own order, the five base masters, and this took it over the 48 plugins the
  dev server ran, because every plugin it named was there. In step 1 the
  stage's order is held to the running server's: one that leaves out any
  plugin the running order has is refused, unless -DropPlugins names each
  one (Publish-Server.ps1 -DropPlugins passes it; ServerSettings.ps1,
  Test-ThornswoodLoadOrderDrop, says why). A first install has no running
  order and a put-back brings an order that ran, so neither is held to it.

  The newest two .prev folders are kept, and the last .failed one to read.
  -PutBack puts the newest .prev folder back the same way, keeping what it
  took out as <root>.undone-<stamp>. The renames keep every path the task and
  server-settings.json name the same, so nothing has to be rewritten.

  -FromStore TAKES THE SERVER BUILD OUT OF THE BOX'S STORE (#459). The
  payload Publish-Server.ps1 -FromStore sends carries no server build and no
  plugins: the gamemode and its stamp, server-build.json (the record the
  commit holds), the settings a release sets (how many it holds, and the
  port, read only) and any plugin of ours the running order names. In step 1
  the record's build is taken out of the store (-Store, C:\Thornswood-Deploys
  \server) into the stage, held to the record exactly as a payload's own
  files are (Expand-ThornswoodStoredServerBuild, ServerBuild.ps1), and every
  plugin the running server's load order names under its plugins folder that
  the payload did not bring is copied from the running root. The running
  server keeps its own load order and start point, so it goes onto a running
  server only, never a first install; an engine that reads light plugins
  another way than the running one would move every form id in that order
  (ServerOrder.ps1, #1715), so that is refused too; and a plugin of ours the
  order does not name is refused, because changing the order is a full
  publish's. Everything after is the same stage, swap and way back.

  -TaskOnly REGISTERS THE TASK AGAIN AND NOTHING ELSE (#2491). No zip, no
  stage, no swap, no setting: the server already in -Root is stopped, the
  task is registered with this installer's action and settings, with the
  log writer that action runs (server-log.js, #2349) put in the root beside
  it, and the server is started through it and given -Wait seconds to
  answer on both ports. If it does not answer, the task it had goes back, exactly as it was
  exported, and is started again: INSTALL ROLLED BACK. It is how a box takes a
  change to the task itself (its priority, #2491) without a release.
  Publish-Server.ps1 -TaskOnly sends this and runs it.
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
    # The plugins this install may leave out of the running server's load
    # order (#2320), as base64 of the names one to a line, because a name with
    # a space does not survive the ssh command line Publish-Server.ps1 runs
    # this on. Publish-Server.ps1 -DropPlugins writes it. Left off, an order
    # that drops any plugin the running server loads is refused.
    [string]$DropPlugins = '',
    # How many <root>.prev-<stamp> folders to keep.
    [int]$Keep = 2,
    # Register the task again for the server already in -Root, stop it and
    # start it through the new task, and touch no file (#2491, the header).
    [switch]$TaskOnly,
    # Take the server build out of the box's store instead of the payload, and
    # the plugins from the running root (#459, the header). Publish-Server.ps1
    # -FromStore passes it.
    [switch]$FromStore,
    # The store's server folder, for -FromStore.
    [string]$Store = 'C:\Thornswood-Deploys\server',
    # Register the task as SYSTEM, Highest, the way it was before #2578, and
    # grant nothing. The way back if the server will not run as LOCAL SERVICE
    # (ServiceAccount.ps1 says what it is given).
    [switch]$AsSystem,
    # Lets tests\test-install-server.ps1 run this on a machine with the game on
    # it, against a scratch root. Nothing else passes it.
    [switch]$AllowGamingPc
)

$ErrorActionPreference = 'Stop'

if (-not $AllowGamingPc -and (Test-Path 'C:\Thornswood\Game\SkyrimSE.exe')) {
    throw "SkyrimSE.exe is present, so this looks like the gaming PC, not the VPS. Nothing was changed."
}
if (-not $PutBack -and -not $TaskOnly -and -not (Test-Path -LiteralPath $Zip)) { throw "not found: $Zip" }

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
$dropNames = @()
try { $dropNames = @(ConvertFrom-ThornswoodNamesArg $DropPlugins) }
catch { Say "-DropPlugins does not read as the names Publish-Server.ps1 sends: $($_.Exception.Message). Nothing was changed." 'Red'; Finish 'INSTALL REFUSED' 1 }
if ($PutBack -and $dropNames.Count) {
    Say '-PutBack brings back an order the server ran and drops nothing on purpose, so it does not take -DropPlugins. Nothing was changed.' 'Red'
    Finish 'INSTALL REFUSED' 1
}
if ($PutBack -and $askedKeys.Count) {
    Say '-PutBack sets no setting: it puts the previous folder back with the running server''s own settings. Run it without -RequirePass. Nothing was changed.' 'Red'
    Finish 'INSTALL REFUSED' 1
}
# -FromStore installs a build onto a running server (#459); a put-back and
# -TaskOnly install none.
if ($FromStore -and ($PutBack -or $TaskOnly)) {
    Say '-FromStore installs a server build out of the store, and -PutBack and -TaskOnly install none. Nothing was changed.' 'Red'
    Finish 'INSTALL REFUSED' 1
}
# -TaskOnly touches the task and nothing else (#2491), so a switch that
# changes a folder, a setting or the world would do nothing, and is refused.
if ($TaskOnly) {
    $with = @()
    if ($PutBack) { $with += '-PutBack' }
    if ($NoTask) { $with += '-NoTask' }
    if ($FreshWorld) { $with += '-FreshWorld' }
    if ($askedKeys.Count) { $with += '-RequirePass' }
    if ($dropNames.Count) { $with += '-DropPlugins' }
    if ($with.Count) {
        Say ('-TaskOnly registers the task again and changes no file or setting, so it does not take ' + ($with -join ', ') + '. Nothing was changed.') 'Red'
        Finish 'INSTALL REFUSED' 1
    }
    if (-not $StartNow) {
        Say '-TaskOnly stops the server to register its task again, so it takes -StartNow to start it again. Nothing was changed.' 'Red'
        Finish 'INSTALL REFUSED' 1
    }
}
# Which server files the record holds, and holding them (#1214): beside this
# script too, sent with it.
$buildLib = Join-Path $here 'ServerBuild.ps1'
if (-not (Test-Path -LiteralPath $buildLib)) {
    Say "ServerBuild.ps1 is not beside this installer, so the payload's server files could not be held to their record. Nothing was changed." 'Red'
    Finish 'INSTALL REFUSED' 1
}
. $buildLib
# The record contracts (#2180, slice 4): beside this script too, sent with it
# (Read-JsonFile.ps1 and RecordShape.ps1), or in scripts\release when it runs
# from a checkout. Without them a broken settings file or record would be read
# as whatever ConvertFrom-Json made of it, so nothing runs.
$shapeDir = $here
if (-not (Test-Path -LiteralPath (Join-Path $here 'RecordShape.ps1'))) { $shapeDir = Join-Path $here '..\release' }
foreach ($lib in 'Read-JsonFile.ps1', 'RecordShape.ps1') {
    if (-not (Test-Path -LiteralPath (Join-Path $shapeDir $lib))) {
        Say "$lib is not beside this installer, so the payload's settings and record could not be held to their shape. Nothing was changed." 'Red'
        Finish 'INSTALL REFUSED' 1
    }
}
. (Join-Path $shapeDir 'Read-JsonFile.ps1')
. (Join-Path $shapeDir 'RecordShape.ps1')
# How long a start may take to answer on both ports (#1938): beside this
# script too, sent with it. Without it there is no ceiling, so nothing runs.
$waitLib = Join-Path $here 'ServerReadyWait.ps1'
if (-not (Test-Path -LiteralPath $waitLib)) {
    Say "ServerReadyWait.ps1 is not beside this installer, so how long a start may take to answer has no source. Nothing was changed." 'Red'
    Finish 'INSTALL REFUSED' 1
}
. $waitLib
# The account the task runs as and what it may reach (#2578). A copy of the
# functions in ServiceAccount.ps1, kept here rather than sent beside this
# installer, because every file Publish-Server.ps1 sends is a call in
# records\remote-commands.json. tests\test-2578-service-principals.ps1 fails
# when this copy and ServiceAccount.ps1 differ.
# ---- ServiceAccount.ps1 (copy) ----
function New-ThornswoodServicePrincipal {
    param([switch]$AsSystem)
    if ($AsSystem) {
        return New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    }
    return New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\LOCAL SERVICE' -LogonType ServiceAccount -RunLevel Limited `
        -RequiredPrivilege 'SeChangeNotifyPrivilege' -ProcessTokenSidType Unrestricted
}
function Get-ThornswoodTaskSid {
    param([string]$TaskName)
    try {
        return (New-Object Security.Principal.NTAccount('NT TASK', $TaskName)).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch { return '' }
}
function Get-ThornswoodServiceNeverReach {
    param([string]$Own = '')
    $own = $Own.TrimEnd('\')
    $list = @('C:\Thornswood-Backup', 'C:\Thornswood-Deploys', 'C:\Thornswood-Watch', 'C:\Thornswood-Maint')
    foreach ($r in 'C:\Thornswood-Server', 'C:\Thornswood-Server-Dev') {
        if ($r -ine $own) { $list += (Join-Path $r 'private') }
    }
    foreach ($r in 'C:\Thornswood-Voice', 'C:\Thornswood-Voice-Dev') {
        if ($r -ine $own) { $list += (Join-Path $r 'token-key.txt') }
    }
    return $list
}
function Test-ThornswoodServiceCannotReach {
    param([string[]]$Paths, [string[]]$Sids = @())
    $who = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-19') + @($Sids | Where-Object { $_ })
    # ReadData (ListDirectory on a folder), GENERIC_READ and GENERIC_ALL.
    $read = [long]0x90000001
    $problems = @()
    foreach ($p in @($Paths)) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        try { $acl = Get-Acl -LiteralPath $p }
        catch { $problems += ($p + ': its rules could not be read (' + $_.Exception.Message + ')'); continue }
        foreach ($r in @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))) {
            if ([string]$r.AccessControlType -ne 'Allow') { continue }
            if ($who -notcontains $r.IdentityReference.Value) { continue }
            if (([long][int]$r.FileSystemRights -band $read) -eq 0) { continue }
            $problems += ($p + ': ' + $r.IdentityReference.Value + ' may read it (' + $r.FileSystemRights + ')')
        }
    }
    # Unrolled: callers wrap it in @(), so none is a count of 0.
    return $problems
}
function Set-ThornswoodServiceAcl {
    param([string]$Path, $Acl)
    $item = Get-Item -LiteralPath $Path -Force
    if ($PSVersionTable.PSEdition -eq 'Core') {
        if ($item -is [IO.DirectoryInfo]) { [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]$item, [Security.AccessControl.DirectorySecurity]$Acl) }
        else { [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]$item, [Security.AccessControl.FileSecurity]$Acl) }
    } else { $item.SetAccessControl($Acl) }
}
function Grant-ThornswoodServiceFolder {
    param([string]$Root, [string]$Sid, [string[]]$Writable = @(), [string[]]$Files = @())
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { throw ('not here: ' + $Root) }
    if (-not $Sid) { throw 'no SID to grant to' }
    $fsr  = [Security.AccessControl.FileSystemRights]
    $inh  = [Security.AccessControl.InheritanceFlags]
    $prop = [Security.AccessControl.PropagationFlags]
    $tree = $inh::ContainerInherit -bor $inh::ObjectInherit
    $who  = New-Object Security.Principal.SecurityIdentifier($Sid)
    $made = New-Object Security.Principal.SecurityIdentifier('S-1-3-0')
    $said = @()

    $acl = Get-Acl -LiteralPath $Root
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($who, $fsr::ReadAndExecute, $tree, $prop::None, 'Allow')))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($who, ($fsr::CreateFiles -bor $fsr::CreateDirectories), $inh::None, $prop::None, 'Allow')))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($made, $fsr::Modify, $tree, $prop::InheritOnly, 'Allow')))
    Set-ThornswoodServiceAcl $Root $acl
    $said += ('read and run in ' + $Root + ', make files there, change only what it made')

    foreach ($w in @($Writable | Where-Object { $_ })) {
        $d = Join-Path $Root $w
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $a = Get-Acl -LiteralPath $d
        $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($who, $fsr::Modify, $tree, $prop::None, 'Allow')))
        Set-ThornswoodServiceAcl $d $a
        $said += ('change ' + $d)
    }
    foreach ($pat in @($Files | Where-Object { $_ })) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Root -File -Force -Filter $pat -ErrorAction SilentlyContinue)) {
            $a = Get-Acl -LiteralPath $f.FullName
            $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($who, $fsr::Modify, 'Allow')))
            Set-ThornswoodServiceAcl $f.FullName $a
            $said += ('change ' + $f.FullName)
        }
    }
    return $said
}
# ---- end ServiceAccount.ps1 ----
# The fail-safe (#2578), before anything is stopped or changed: the server
# goes onto LOCAL SERVICE only where LOCAL SERVICE can read none of what no
# service may.
if (-not $AsSystem -and -not $NoTask) {
    $cannot = @(Test-ThornswoodServiceCannotReach (Get-ThornswoodServiceNeverReach -Own $Root))
    if ($cannot.Count) {
        Say 'LOCAL SERVICE could read what no service may, so the server is not moved onto it:' 'Red'
        foreach ($c in $cannot) { Say ('  ' + $c) 'Red' }
        Say 'Lock those (scripts\vps\Lock-VpsFolders.ps1), or pass -AsSystem. Nothing was changed.' 'Red'
        Finish 'INSTALL REFUSED' 1
    }
}
# The log writer the task runs the server under (#2349): beside this script,
# sent with it, or in scripts\vps from a checkout. Without it the task could
# not start the server, so nothing runs.
if (-not (Test-Path -LiteralPath (Join-Path $here 'Server-Log.js')) -and
    -not (Test-Path -LiteralPath (Join-Path $here '..\vps\Server-Log.js'))) {
    Say "Server-Log.js is not beside this installer, and the server's task runs the server under it. Nothing was changed." 'Red'
    Finish 'INSTALL REFUSED' 1
}
if (-not $PSBoundParameters.ContainsKey('Wait')) {
    $Wait = Get-ThornswoodServerReadyWait
}
$script:running = $null

# The game port a root's settings name, and the resources port that follows
# from it: skymp5-server/ts/ui.ts gives 3000 for 7777 and the game port plus
# one otherwise. Publish-Server and Deploy-Server use the same rule.
#
# No settings file, or one with no port, is the server's own default, 7777.
# One that is there and does not read stops the run: guessing 7777 for it
# would have a dev root take the live server's answer for its own (#2711).
function GamePortOf([string]$dir) {
    $sp = Join-Path $dir 'server-settings.json'
    if (-not (Test-Path -LiteralPath $sp)) { return 7777 }
    $cfg = $null
    try { $cfg = [IO.File]::ReadAllText($sp) | ConvertFrom-Json }
    catch { throw ("$sp does not read, so the port this server answers on is not known: " + $_.Exception.Message) }
    if ($null -ne $cfg -and $cfg.port) { return [int]$cfg.port }
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
  node. The task runs cmd.exe, which starts server-log.js under node with this
  root's paths on its line, and that node starts the server with a relative
  path on its command line (#2349), so cmd and the writer are found by the
  root on their lines and the server as the writer's child. The trailing backslash matters: C:\Thornswood-Server
  is a prefix of C:\Thornswood-Server-Dev.
#>
# Ours only: cmd.exe with this root's log on its line, the node it started
# (whose own line is relative), and any node with the root on its line. The
# game port alone is not proof: a scratch root holding a copy of the live
# settings names 7777, and the process there is the live server
# (docs\RESTORING.md installs into one). Each as its Win32_Process.
function ServerProcesses([string]$dir) {
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
    @($all | Where-Object { $ids -contains [int]$_.ProcessId })
}

function StopServer([string]$dir) {
    # Found before the task is stopped.
    $ids = @(ServerProcesses $dir | ForEach-Object { [int]$_.ProcessId })
    # No task yet is nothing to stop. One that is there and will not stop is
    # said: its processes are stopped by id below whatever it does.
    if (-not $NoTask -and (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
        try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop }
        catch { Say ("the task {0} would not stop ({1}); its processes are stopped by id instead" -f $TaskName, $_.Exception.Message) 'Yellow' }
    }
    foreach ($id in @($ids | Where-Object { $_ -gt 0 -and $_ -ne $PID } | Sort-Object -Unique)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
        Say ("stopped pid {0}" -f $id) 'Yellow'
    }
    # The ports let go, every one the stopped processes held. Listed whole and
    # filtered: -LocalPort with nothing on it is an error, and nothing there is
    # what this waits for. A box that cannot list them says so and goes on: the
    # processes are stopped by id above either way, and this is a rollback's
    # path as well as an install's, so it does not stop half way.
    for ($i = 0; $i -lt 20; $i++) {
        $held = @()
        try { $held = @(Get-NetUDPEndpoint -ErrorAction Stop | Where-Object { $ids -contains [int]$_.OwningProcess }) }
        catch { Say ("could not list the UDP ports to see them let go ({0}), going on without that wait" -f $_.Exception.Message) 'Yellow'; break }
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
    $why = ''
    while ($true) {
        # Listed whole and filtered, as StopServer does: nothing on the port yet
        # is what an empty list says, not an error. A list that cannot be had
        # is not answering, and is said when the wait runs out.
        $udp = $false
        try { $udp = @(Get-NetUDPEndpoint -ErrorAction Stop | Where-Object { $_.LocalPort -eq $port }).Count -gt 0 }
        catch { $why = 'the UDP ports could not be listed: ' + $_.Exception.Message }
        $tcp = $false
        if ($udp) {
            $c = New-Object Net.Sockets.TcpClient
            try {
                $null = $c.BeginConnect('127.0.0.1', $res, $null, $null).AsyncWaitHandle.WaitOne(500)
                $tcp = $c.Connected
            } catch { $why = $_.Exception.Message }
            finally { $c.Close() }
        }
        if ($tcp) { return $true }
        if ((Get-Date) -gt $until) {
            if ($why) { Say ("not answering on {0} or {1}; the last try said: {2}" -f $port, $res, $why) 'Yellow' }
            return $false
        }
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
    # A log left behind is said, never passed over (#2349): server.log and
    # its rolled copies hold the address of every connection, and the 30 days
    # are kept by server-log.js in the folder the task runs, so one left in
    # $from is outside them until somebody deletes it there. With the server
    # stopped, only another program reading it can hold it.
    $moved = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $from -File -Force -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '\.log(\.\d+)?$' })) {
        $dest = Join-Path $to $f.Name
        if (Test-Path -LiteralPath $dest) { continue }
        try { Move-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop; $moved++ }
        catch { Say ("could not carry {0} across ({1}); it stays in {2}, where nothing keeps it to 30 days, so delete it there" -f $f.Name, $_.Exception.Message, $from) 'Yellow' }
    }
    if ($moved -gt 0) { Say 'logs carried across, to be rolled rather than deleted' 'Cyan' }
}

# The newest few of each kind of folder beside the root.
function Prune([string]$kind, [int]$n) {
    Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like ($leaf + $kind) } | Sort-Object Name -Descending | Select-Object -Skip $n |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---- the task --------------------------------------------------------------
# What the task runs and how, registered over whatever task has the name.
# $writer is server-log.js in the root.
function Register-ServerTask([string]$writer) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }

    # The server runs under server-log.js, which writes its log (#2349). A
    # scheduled task throws its child's stdout and stderr away, so a server
    # that refuses to start would leave nothing behind at all: the task
    # reports it ran, the port never opens, and there is no way to find out
    # why without sitting in an ssh session running it by hand. server-log.js
    # starts the server with both streams piped to it and writes them to
    # server.log, rolled at midnight and at 4 MB, and keeps no line in it or
    # in any rolled copy for longer than 30 days (Patrick, 12 Oct 2026: the
    # engine writes every connecting address there). Until then this was
    # cmd's >> server.log 2>&1, which held the file open for as long as the
    # server ran, so it could only be rolled by size in front of a start
    # (Roll-Log.ps1) and never by age. See scripts\vps\Server-Log.js.
    #
    # It goes through cmd's start /high, for the priority (below), and
    # server-log.js gives the server its own priority as it starts it. /b
    # keeps it in cmd's console and /wait keeps cmd, and so the task, running
    # until the server ends. server-log.js ends with the server's exit code,
    # and start leaves cmd's exit code 0 whatever that was, so call exit
    # %^errorlevel% hands it back, and the task's last result says how the
    # server ended, as it did before (measured 12 Oct: 3 for a node that
    # exited 3, 0 without it). The log path is on the line, which is how
    # ServerProcesses finds this root's cmd.exe.
    #
    # --also thornswood.log (#2166): the gamemode's own log, in this same
    # folder (the task's working directory), names people too and used to
    # roll by size only. server-log.js moves it aside daily and cuts every
    # rolled copy of it to 90 days, so nothing in game\ had to change.
    $log = Join-Path $Root 'server.log'
    $cmd = ('/c "start "" /b /wait /high "{0}" "{1}" --log "{2}" --also thornswood.log dist_back/skymp5-server.js & call exit %^errorlevel%"' -f $node.Source, $writer, $log)
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" `
                                      -Argument $cmd `
                                      -WorkingDirectory $Root
    $triggers = @(New-ScheduledTaskTrigger -AtStartup)

    # High, above everything else on the box (#2491). Decided by Patrick on
    # 12 Oct 2026 at about 6:20 PM: "we need to fix it so the servers run on
    # high priority". The VPS has six cores, and the six build runners are
    # Windows services at Normal (Install-Runner.ps1), so until then a build
    # took the processor from both game servers at the same priority as them.
    # Voice runs High the same way (Install-Voice.ps1); the site, Caddy, the
    # bot and the runners stay Normal.
    #
    # It takes both halves. -Priority 1 is HIGH_PRIORITY_CLASS in Microsoft's
    # table (0 is realtime, never used here: it can hold back the box's own
    # disk and network work; 2 and 3 are above normal, 4 to 6 normal), and it
    # starts the task's cmd.exe High. But a process started from a High one
    # runs Normal unless it is asked for another class (CreateProcess hands
    # the parent's class on only for Idle and BelowNormal), so node, cmd's
    # child, still ran Normal at priority 1: measured 12 Oct on a scratch task
    # as SYSTEM, cmd High and its child Normal. start /high asks for High.
    # Measured the same way with both: node High, I/O priority 2 and memory
    # priority 5, the same I/O and memory priority it had at 4.
    #
    # Never left at Task Scheduler's default of 7, which is where this began
    # (#1931). A task registered without -Priority starts its process below
    # normal, with I/O priority 1 (low) and memory priority 2, and node,
    # started by the task's cmd.exe, inherits all three. Measured on the VPS
    # on 5 October: both game servers ran BelowNormal, I/O priority 1, memory
    # priority 2, while the build runners, the bot and lsass ran Normal, 2
    # and 5.
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
    # file. Priority 1 gives memory priority 5, so nothing else sets it.
    #
    # tests\test-server-task-priority.ps1 registers a task with these settings
    # and this command line, and measures the CPU, I/O and memory priority of
    # the program it starts.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                             -DontStopIfGoingOnBatteries `
                                             -StartWhenAvailable `
                                             -RestartCount 999 `
                                             -RestartInterval (New-TimeSpan -Minutes 1) `
                                             -ExecutionTimeLimit ([TimeSpan]::Zero) `
                                             -Priority 1
    # LOCAL SERVICE, Limited, with a SID of its own, and the grants on its
    # folder that go to that SID (#2578, ServiceAccount.ps1). -AsSystem is
    # SYSTEM, Highest, as it was. A task whose SID cannot be looked up, or
    # whose grants cannot be written, goes back on SYSTEM rather than start a
    # server that cannot write its world.
    $principal = New-ThornswoodServicePrincipal -AsSystem:$AsSystem

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers `
                           -Settings $settings -Principal $principal | Out-Null
    if (-not $AsSystem) {
        $why = ''
        $sid = Get-ThornswoodTaskSid $TaskName
        if (-not $sid) { $why = "the task's own SID, NT TASK\$TaskName, could not be looked up" }
        else {
            try {
                foreach ($l in @(Grant-ThornswoodServiceFolder -Root $Root -Sid $sid -Writable 'world', 'data', 'private', 'for-bot' -Files '*.log', '*.log.*')) { Say $l 'DarkGray' }
            } catch { $why = 'its folder could not be granted to it: ' + $_.Exception.Message }
        }
        if ($why) {
            Say ("$why, so the task goes back on SYSTEM") 'Red'
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers `
                                   -Settings $settings -Principal (New-ThornswoodServicePrincipal -AsSystem) | Out-Null
        } else { Say "the task runs as LOCAL SERVICE, Limited, as NT TASK\$TaskName" 'Cyan' }
    }
    Write-Host "scheduled task '$TaskName' registered, starts at boot, restarts every minute if it stops" -ForegroundColor Cyan
}

# ---- the log writer (#2349) -------------------------------------------------
# Server-Log.js goes into the root as server-log.js, from beside this script
# (Publish-Server sends the two together to C:\) or, run from a checkout,
# from scripts\vps. The full path in the root, or '' when neither is there:
# the task cannot start the server without it, so the callers refuse.
function Copy-LogWriter {
    $here = $PSScriptRoot
    $src = $null
    foreach ($cand in @((Join-Path $here 'Server-Log.js'), (Join-Path $here '..\vps\Server-Log.js'))) {
        if (Test-Path -LiteralPath $cand) { $src = $cand; break }
    }
    if (-not $src) { return '' }
    $to = Join-Path $Root 'server-log.js'
    Copy-Item -LiteralPath $src -Destination $to -Force
    return $to
}

# An install's roll: today's server.log moved aside whatever its size, so the
# run this install starts has a file of its own and the tail read after it is
# only this run, and every rolled file cut to the last 30 days. Never deleted
# whole: deleting it is how the evidence for the last crash disappeared.
# thornswood.log is aged with it, to 90 days (#2166).
function Roll-ServerLog([string]$writer) {
    $log = Join-Path $Root 'server.log'
    $gm = Join-Path $Root 'thornswood.log'
    & $node.Source $writer --log $log --also $gm --roll | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) { Say ("server-log.js could not roll server.log (exit {0}); the server appends to it and rolls it at midnight" -f $LASTEXITCODE) 'Yellow' }
}

# The priority node runs at under this root, read back after a start (#2491).
function Show-ServerPriority([string]$dir) {
    $nodes = @(ServerProcesses $dir | Where-Object { $_.Name -eq 'node.exe' })
    if (-not $nodes.Count) { Say "no node is running under $dir, so there is no priority to read" 'Yellow'; return }
    foreach ($p in $nodes) {
        $class = 'unreadable'
        $proc = Get-Process -Id ([int]$p.ProcessId) -ErrorAction SilentlyContinue
        if (-not $proc) { Say ("node, pid {0}, has already gone" -f $p.ProcessId) 'Yellow'; continue }
        try { $class = [string]$proc.PriorityClass } catch { $class = 'unreadable (' + $_.Exception.Message + ')' }
        Say ("node, pid {0}, runs at {1} priority" -f $p.ProcessId, $class) $(if ($class -eq 'High') { 'Green' } else { 'Yellow' })
    }
}

# ---- -TaskOnly: the task again, and nothing else (#2491) -----------------------
if ($TaskOnly) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'dist_back\skymp5-server.js'))) {
        Say "there is no server in $Root (no dist_back\skymp5-server.js), so there is nothing for the task to start. Nothing was changed." 'Red'
        Finish 'INSTALL REFUSED' 1
    }
    $writer = Copy-LogWriter
    # The task as it is now, for the way back.
    $oldXml = $null
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { $oldXml = (Export-ScheduledTask -TaskName $TaskName | Out-String) }
    $gamePort = GamePortOf $Root
    $resPort = if ($gamePort -eq 7777) { 3000 } else { $gamePort + 1 }
    Say 'stopping the server' 'Cyan'
    StopServer $Root
    Register-ServerTask $writer
    Roll-ServerLog $writer
    Start-ScheduledTask -TaskName $TaskName
    Say ("started through the new task, giving it {0} seconds to answer on UDP {1} and on {2}" -f $Wait, $gamePort, $resPort) 'DarkGray'
    if (Answers $Root) {
        Say ("the server is answering on {0}, game port {1}" -f $resPort, $gamePort) 'Green'
        Show-ServerPriority $Root
        Finish 'INSTALL OK' 0
    }
    Write-Host ''
    Say 'the server did not come up under the new task. Its log says:' 'Red'
    TailLog $Root
    if (-not $oldXml) {
        Say "there was no task named $TaskName before this, so there is none to put back" 'Red'
        Finish 'INSTALL FAILED' 1
    }
    Say 'putting the task it had back' 'Yellow'
    StopServer $Root
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $TaskName -Xml $oldXml | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    if (Answers $Root) { Say ("the task it had is back and the server is answering on {0}" -f $resPort) 'Yellow' }
    else { Say "THE TASK IT HAD IS BACK AND THE SERVER STILL IS NOT ANSWERING on $resPort" 'Red'; TailLog $Root }
    Finish 'INSTALL ROLLED BACK' 1
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
    # -FromStore (#459, the header): the record's build out of the store, into
    # the stage, before what the payload brought into data is listed, so the
    # compiled Papyrus counts as shipped. Onto a running server only.
    if ($FromStore) {
        $runSettings = Join-Path $Root 'server-settings.json'
        if (-not (Test-Path -LiteralPath $runSettings)) {
            Refuse @("-FromStore keeps the running server's load order, start point and plugins, and there is no server in $Root to keep them from. A first install takes a whole payload: Publish-Server.ps1 with -Dist.")
        }
        $rp = Join-Path $stageDir 'server-build.json'
        $want = $null
        try { $want = Read-ThornswoodRecord -Path $rp -Kind server-build } catch { Refuse @("the payload's server-build.json cannot be trusted, so nothing says which build to take out of the store: $($_.Exception.Message)") }
        $got = Expand-ThornswoodStoredServerBuild -Store $Store -Record $want -RecordSum (Get-ThornswoodRecordSum ([IO.File]::ReadAllBytes($rp))) -Into $stageDir
        if ($got.Problem) { Refuse @($got.Problem) }
        foreach ($l in $got.Said) { Say $l 'Cyan' }
        # The light plugin rule of the engine the running order was written for
        # (ServerOrder.ps1, #1715), against this one's: lightPlugins true or not.
        $runRec = Join-Path $Root 'server-build.json'
        $runLight = $false
        if (Test-Path -LiteralPath $runRec) {
            try { $rl = [IO.File]::ReadAllText($runRec) | ConvertFrom-Json; $runLight = ($rl.PSObject.Properties.Name -contains 'lightPlugins' -and $rl.lightPlugins -eq $true) } catch { $runLight = $false }
        }
        $newLight = ($want.PSObject.Properties.Name -contains 'lightPlugins' -and $want.lightPlugins -eq $true)
        if ($runLight -ne $newLight) {
            Refuse @(('the running server''s load order was written for an engine that ' + $(if ($runLight) { 'loads' } else { 'does not load' }) + ' light plugins, and this build ' +
                      $(if ($newLight) { 'loads' } else { 'does not load' }) + ' them, so every form id after the first light plugin would move (ServerOrder.ps1, #1715). ' +
                      'That goes with a load order written for it: Deploy-Gamemode.ps1, then Publish-Server.ps1 with -Dist.'))
        }
    }
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
    try { $s = Read-ThornswoodRecord -Path $settingsPath -Kind server-settings } catch { Refuse @("the payload's settings cannot be trusted: $($_.Exception.Message)") }

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
        # An order that leaves out a plugin the running server loads (#2320).
        $drop = Test-ThornswoodLoadOrderDrop $script:running $s $dropNames
        foreach ($l in $drop.Said) { Say $l 'Yellow' }
        if ($drop.Problem) { Refuse @($drop.Problem) }
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

    # -FromStore (#459): the running server's plugins, by its own order, into
    # the stage where the payload did not bring one (ours), and none of ours
    # that the order does not name.
    if ($FromStore) {
        $plugDir = Join-Path $stageDir 'plugins'
        $null = [IO.Directory]::CreateDirectory($plugDir)
        $named = @{}
        $taken = 0
        foreach ($p in @($s.loadOrder)) {
            $at = ([string]$p) -replace '/', '\'
            $leaf = [IO.Path]::GetFileName($at)
            if ($leaf) { $named[$leaf.ToLowerInvariant()] = $true }
            if (-not $at.StartsWith($Root + '\plugins\', [StringComparison]::OrdinalIgnoreCase)) { continue }
            $into = Join-Path $plugDir $leaf
            if (Test-Path -LiteralPath $into) { continue }
            $from = Join-Path (Join-Path $Root 'plugins') $leaf
            if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $into -Force; $taken++ }
        }
        $brought = @(Get-ChildItem -LiteralPath $plugDir -File -Force | Where-Object { -not $named.ContainsKey($_.Name.ToLowerInvariant()) } | ForEach-Object { $_.Name })
        if ($brought.Count) {
            Refuse @(('the payload carries ' + ($brought -join ', ') + ', which the running server''s load order does not name, and -FromStore keeps that order. A change to the order goes with a full publish.'))
        }
        Say ("$taken plugin(s) the running server's load order names taken from $Root\plugins into the stage") 'Cyan'
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
            $recObj = Read-ThornswoodRecord -Path $rec -Kind server-build
            $bad += @(Get-ThornswoodServerBuildProblems $recObj (Get-ThornswoodServerFolderSums $stageDir) 'the payload' 'server-build.json')
        } catch { $bad += "the payload's server-build.json cannot be trusted: $($_.Exception.Message)" }
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
    # The task this install registered runs the server under server-log.js
    # in the root (#2349), and a folder from before it has none.
    $null = Copy-LogWriter
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
    $unread = @()
    try { $was = [IO.File]::ReadAllText((Join-Path $aside 'server-settings.json')) | ConvertFrom-Json } catch { $unread += ('the server-settings.json the server had, which cannot be read: ' + $_.Exception.Message) }
    try { $now = [IO.File]::ReadAllText((Join-Path $Root 'server-settings.json')) | ConvertFrom-Json } catch { $unread += ('the server-settings.json now in place, which cannot be read: ' + $_.Exception.Message) }
    if (-not $unread.Count -and ($null -eq $was -or $null -eq $now)) { $unread += 'server-settings.json, which is empty' }
    $moved = $unread
    # What this run asked for (#1804) moved on purpose, as the release's keys did.
    if (-not $unread.Count) { $moved = @(Compare-ThornswoodCarried $was $now @($ThornswoodInstallKeys + $askedKeys)) }
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
    try { $siteSid = (New-Object Security.Principal.NTAccount([string]$siteTask.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value }
    catch { Say ("the site's task runs as {0}, which does not translate to an account here ({1}), so whether it may read server.log is not known" -f $siteTask.Principal.UserId, $_.Exception.Message) 'Yellow' }
    if ($siteSid) {
        $has = @((Get-Acl -LiteralPath $Root).GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq $siteSid })
        if (-not $has.Count) { Say "the site's account has no rule on $Root yet, so it cannot read server.log: run .\scripts\deploy\Deploy-Docs.ps1 once" 'Yellow' }
    }
}

# The log writer the task runs the server under (#2349), into the root.
# Found before anything changed (the refusal near the top), so it is there.
$writer = Copy-LogWriter
# A box that had the old roller in its root keeps nothing that runs it.
$oldRoller = Join-Path $Root 'roll-log.ps1'
if (Test-Path -LiteralPath $oldRoller) { Remove-Item -LiteralPath $oldRoller -Force }

# ---- scheduled task --------------------------------------------------------
# Register-ServerTask, above, says what the task is and why.
if (-not $NoTask) { Register-ServerTask $writer }

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

# Rolled whatever its size rather than deleted (Roll-ServerLog), so the run
# this install starts has a file of its own and the tail below reads only it.
Roll-ServerLog $writer

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
    Show-ServerPriority $Root
    Tidy
    Say ("the task writes everything the server prints to {0}\server.log through server-log.js, rolled at midnight and at 4 MB, nothing kept past 30 days" -f $Root) 'DarkGray'
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
