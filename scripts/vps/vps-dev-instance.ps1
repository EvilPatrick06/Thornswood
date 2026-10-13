# vps-dev-instance.ps1
#
# Runs ON the VPS. Makes the dev game server and the dev voice server beside
# the live ones, from copies of the live installs, on their own ports, with
# their own scheduled tasks and firewall rules. Nothing about the live
# instances is touched. Safe to run again: every step checks before it acts.
# The watchdog's dev checks come with Watch-Services.ps1 -Install, not from
# here.
#
#   live game server   C:\Thornswood-Server       UDP/TCP 7777, resources TCP 3000
#   dev game server    C:\Thornswood-Server-Dev   UDP/TCP 7787, resources TCP 7788 (the server picks port+1 itself)
#   live voice         C:\Thornswood-Voice        TCP 7778
#   dev voice          C:\Thornswood-Voice-Dev    TCP 7789, loopback only, behind Caddy's /voice-dev
#
# The dev world starts empty: characters and the world state are not copied,
# because a dev server is for breaking things.
#
# NOTHING PRIVATE OF LIVE'S COMES ACROSS (issues #1082 and #1083).
#   The game server's private folder holds live's door.json (the live site's
#   address and the key the site trusts), allowed.json and characters.json.
#   It is never copied, nor data's copies of the door or the list: dev's
#   private starts with an empty characters.json and nothing else, and
#   Publish-Server.ps1 -Channel dev writes dev's own door.json, asking the dev
#   list, on its first run (#964).
#   Voice is copied by name, the program (voice-server.js and headlines.js,
#   which it requires) and the log roller, and nothing else: never live's
#   chat logs, token-key.txt (dev voice makes its own), turn-key.txt or the
#   old secret.txt.
#   Dev voice starts with auth on and bound to 127.0.0.1, the way live runs,
#   never with the service's own fallback of letting unproven joins in on
#   every address, and its port is not opened in the firewall: Caddy carries
#   /voice-dev to it over loopback.
#   Both dev folders take nothing from C:\, whose rule lets every service
#   account on the box read them (#1105): SYSTEM and Administrators only.
#   Deploy-Docs.ps1 gives the site its read on dev's server.log and chat.
#
#   -FilesOnly   the copies, the folders' rules and the run file, and no task,
#                firewall rule or watchdog line. tests\test-dev-instance.ps1
#                runs it against scratch folders.
param(
    [switch]$Start,
    [string]$Live      = 'C:\Thornswood-Server',
    [string]$Dev       = 'C:\Thornswood-Server-Dev',
    [string]$LiveVoice = 'C:\Thornswood-Voice',
    [string]$DevVoice  = 'C:\Thornswood-Voice-Dev',
    [switch]$FilesOnly
)
$ErrorActionPreference = 'Stop'
function Say($m) { Write-Output $m }

$live = $Live.TrimEnd('\');  $dev = $Dev.TrimEnd('\')
$liveVoice = $LiveVoice.TrimEnd('\'); $devVoice = $DevVoice.TrimEnd('\')
$devPort = 7787; $devVoicePort = 7789
$node = 'C:\Program Files\nodejs\node.exe'

# SYSTEM, which every task here runs as, and Administrators; nothing from
# C:\ and no Users, Everyone, Authenticated Users or CREATOR OWNER rule. Any
# other rule already set on the folder by name (the site's, from
# Deploy-Docs.ps1) stays.
function Lock-Dir([string]$dir) {
    $broad = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-3-0')
    $acl = Get-Acl -LiteralPath $dir
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in @($acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))) {
        if ($broad -contains $r.IdentityReference.Value) { [void]$acl.RemoveAccessRuleSpecific($r) }
    }
    foreach ($s in 'S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            (New-Object Security.Principal.SecurityIdentifier($s)), 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
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

# ------------------------------------------------------------- game server
if (-not (Test-Path $dev)) { New-Item -ItemType Directory -Path $dev | Out-Null }
Lock-Dir $dev
Say "  $dev is SYSTEM's and Administrators' only"
# Program files and plugins, not the world, not the data, not the private
# folder, not the logs. The rolled ones too, server.log.1 and the rest, or dev
# starts with live's.
& robocopy $live $dev /E /XD data world private "world-before-*" /XF *.log *.log.* /NFL /NDL /NJH /NJS /NP | Out-Null
Say ("  server files copied (robocopy code {0})" -f $LASTEXITCODE)

# Data: the manifest and the scripts and api folders come across, and nothing
# else of live's: no door and no allowed list, which are private and live's.
$dd = Join-Path $dev 'data'
$pd = Join-Path $dev 'private'
if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Path $dd | Out-Null }
if (-not (Test-Path $pd)) { New-Item -ItemType Directory -Path $pd | Out-Null }
Lock-Dir $pd

foreach ($n in @('manifest.json')) {
    $src = Join-Path $live "data\$n"
    if ((Test-Path $src) -and -not (Test-Path (Join-Path $dd $n))) { Copy-Item $src (Join-Path $dd $n) }
}
foreach ($d in 'scripts', 'api') {
    $src = Join-Path $live "data\$d"
    if ((Test-Path $src) -and -not (Test-Path (Join-Path $dd $d))) { Copy-Item $src (Join-Path $dd $d) -Recurse }
}

if (-not (Test-Path (Join-Path $pd 'characters.json'))) { Set-Content (Join-Path $pd 'characters.json') '[]' -Encoding ASCII }
Say '  data and private folders ready (fresh characters.json, nothing of live''s private)'
if (-not (Test-Path (Join-Path $pd 'door.json'))) {
    Say '  dev has no door.json yet: .\scripts\release\Publish-Server.ps1 -Channel dev writes its own'
}

# server-settings.json: the dev port, the dev name, plugin paths under the dev folder.
$settingsFile = Join-Path $dev 'server-settings.json'
$s = Get-Content (Join-Path $live 'server-settings.json') -Raw | ConvertFrom-Json
$s.port = $devPort
$s.name = 'Thornswood Dev'
$s.loadOrder = @($s.loadOrder | ForEach-Object { $_ -replace [regex]::Escape(($live -replace '\\', '/') + '/'), (($dev -replace '\\', '/') + '/') })
[IO.File]::WriteAllText($settingsFile, ($s | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
Say ("  server-settings.json: port {0}, name Thornswood Dev, {1} plugins" -f $devPort, $s.loadOrder.Count)

# The task, the same shape as the live one (SYSTEM, at boot, restart on
# failure), with the folder swapped.
if (-not $FilesOnly) {
    $liveTask = Get-ScheduledTask -TaskName 'Thornswood Server'
    if (-not (Get-ScheduledTask -TaskName 'Thornswood Dev Server' -ErrorAction SilentlyContinue)) {
        $a = $liveTask.Actions[0]
        $args2 = $a.Arguments -replace [regex]::Escape($live), $dev
        $action = New-ScheduledTaskAction -Execute $a.Execute -Argument $args2 -WorkingDirectory $dev
        Register-ScheduledTask -TaskName 'Thornswood Dev Server' -Action $action -Trigger $liveTask.Triggers -Principal $liveTask.Principal -Settings $liveTask.Settings | Out-Null
        Say '  task Thornswood Dev Server registered'
    } else { Say '  task Thornswood Dev Server already there' }
}

# ------------------------------------------------------------------- voice
if (Test-Path $liveVoice) {
    if (-not (Test-Path $devVoice)) { New-Item -ItemType Directory -Path $devVoice | Out-Null }
    Lock-Dir $devVoice
    Say "  $devVoice is SYSTEM's and Administrators' only"
    # By name: the program, every file it requires, and the roller.
    # voice-server.js requires headlines.js at its first lines since #1406,
    # and stops there without it (#1870); tests\test-dev-instance.ps1 reads
    # the requires out of voice\voice-server.js and holds this list to them.
    # Nothing else in live's folder is dev's to have, the page live may still
    # keep in public included: the service serves none since #1822.
    & robocopy $liveVoice $devVoice voice-server.js headlines.js roll-log.ps1 /XF *.log *.log.* /NFL /NDL /NJH /NJS /NP | Out-Null
    Say ("  voice program copied (robocopy code {0})" -f $LASTEXITCODE)
    # The settings come from the environment. A run file sets them, so the
    # task command stays free of cmd's quoting rules. Auth on and loopback,
    # as live runs; Install-Voice.ps1 -Root C:\Thornswood-Voice-Dev keeps both.
    # roll-log.ps1 came across with the rest and runs before node opens
    # voice.log, the one moment nothing holds it. See Roll-Log.ps1.
    # node goes through start /high, so dev voice runs High the way
    # Install-Voice.ps1 starts it (#2491); the task's own priority, copied
    # from live voice's, makes only this cmd.exe High.
    $run = Join-Path $devVoice 'run-dev-voice.cmd'
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $lines = @(
        '@echo off',
        ('set THORNSWOOD_VOICE_PORT={0}' -f $devVoicePort),
        'set THORNSWOOD_VOICE_AUTH=on',
        'set THORNSWOOD_VOICE_BIND=127.0.0.1',
        'set THORNSWOOD_SITE=https://thornswood.net',
        ('cd /d "{0}"' -f $devVoice),
        ('"{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}\roll-log.ps1" -Path "{1}\voice.log"' -f $psExe, $devVoice),
        ('start "" /b /wait /high "{0}" voice-server.js >> "{1}\voice.log" 2>&1' -f $node, $devVoice)
    )
    [IO.File]::WriteAllLines($run, [string[]]$lines, (New-Object Text.ASCIIEncoding))
    Say '  dev voice runs with auth on, on 127.0.0.1 only'
    if (-not $FilesOnly) {
        $liveVoiceTask = Get-ScheduledTask -TaskName 'Thornswood Voice'
        if (-not (Get-ScheduledTask -TaskName 'Thornswood Dev Voice' -ErrorAction SilentlyContinue)) {
            # The run file's path in two pairs of quotes: cmd /c drops the outer
            # pair whenever the path holds an & or another of its own characters,
            # and the inner pair keeps the path whole (issues #1042, #1115).
            $taskArg = ('/c ""{0}""' -f $run)
            $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument $taskArg -WorkingDirectory $devVoice
            Register-ScheduledTask -TaskName 'Thornswood Dev Voice' -Action $action -Trigger $liveVoiceTask.Triggers -Principal $liveVoiceTask.Principal -Settings $liveVoiceTask.Settings | Out-Null
            Say '  task Thornswood Dev Voice registered'
        } else { Say '  task Thornswood Dev Voice already there' }
    }
}

if ($FilesOnly) { Say 'done, files only'; return }

# ---------------------------------------------------------------- firewall
# Not the dev voice port: it answers on loopback only, behind Caddy. A rule
# an earlier run of this left open is taken down.
$rules = @(
    @{ Name = 'Thornswood Dev game (UDP)';      Protocol = 'UDP'; Port = $devPort },
    @{ Name = 'Thornswood Dev game (TCP)';      Protocol = 'TCP'; Port = $devPort },
    @{ Name = 'Thornswood Dev resources (TCP)'; Protocol = 'TCP'; Port = ($devPort + 1) }
)
foreach ($r in $rules) {
    if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow -Protocol $r.Protocol -LocalPort $r.Port | Out-Null
        Say ("  firewall: {0} open" -f $r.Name)
    }
}
if (Get-NetFirewallRule -DisplayName 'Thornswood Dev Voice' -ErrorAction SilentlyContinue) {
    Remove-NetFirewallRule -DisplayName 'Thornswood Dev Voice'
    Say '  firewall: Thornswood Dev Voice closed, dev voice is on loopback'
}

# ---------------------------------------------------------------- watchdog
# The dev checks are in Watch-Services.ps1's own list, and its -Install is
# what puts them on the box. This only says whether the installed watcher
# has them; it writes nothing into it (issue #1106).
$watch = 'C:\Thornswood-Watch\watch.ps1'
if ((Test-Path $watch) -and ((Get-Content $watch -Raw) -match 'Thornswood Dev Server')) {
    Say '  watchdog already watches the dev server and dev voice'
} else {
    Say '  watchdog: run .\scripts\vps\Watch-Services.ps1 -Install from your machine to put the dev checks on the box'
}

if ($Start) {
    Start-ScheduledTask -TaskName 'Thornswood Dev Server'
    if (Get-ScheduledTask -TaskName 'Thornswood Dev Voice' -ErrorAction SilentlyContinue) { Start-ScheduledTask -TaskName 'Thornswood Dev Voice' }
    Start-Sleep -Seconds 20
    Get-NetUDPEndpoint | Where-Object { $_.LocalPort -eq $devPort } | ForEach-Object { Say ("  dev game server listening on UDP {0}" -f $_.LocalPort) }
    Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in ($devPort + 1), $devVoicePort } | ForEach-Object { Say ("  listening on TCP {0} ({1})" -f $_.LocalPort, $_.LocalAddress) }
    Get-Content (Join-Path $dev 'server.log') -Tail 8 -ErrorAction SilentlyContinue
    Get-Content (Join-Path $devVoice 'voice.log') -Tail 3 -ErrorAction SilentlyContinue
}
Say 'done'
