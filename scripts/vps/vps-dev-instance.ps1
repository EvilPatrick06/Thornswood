# vps-dev-instance.ps1
#
# Runs ON the VPS. Makes the dev game server and the dev voice server beside
# the live ones, from copies of the live installs, on their own ports, with
# their own scheduled tasks, firewall rules and watchdog entries. Nothing
# about the live instances is touched. Safe to run again: every step checks
# before it acts.
#
#   live game server   C:\Thornswood-Server       UDP/TCP 7777, resources TCP 3000
#   dev game server    C:\Thornswood-Server-Dev   UDP/TCP 7787, resources TCP 7788 (the server picks port+1 itself)
#   live voice         C:\Thornswood-Voice        TCP 7778
#   dev voice          C:\Thornswood-Voice-Dev    TCP 7789
#
# The dev world starts empty: characters and the world state are not copied,
# because a dev server is for breaking things.
param(
    [switch]$Start
)
$ErrorActionPreference = 'Stop'
function Say($m) { Write-Output $m }

$live = 'C:\Thornswood-Server';  $dev = 'C:\Thornswood-Server-Dev'
$liveVoice = 'C:\Thornswood-Voice'; $devVoice = 'C:\Thornswood-Voice-Dev'
$devPort = 7787; $devVoicePort = 7789
$node = 'C:\Program Files\nodejs\node.exe'

# ------------------------------------------------------------- game server
if (-not (Test-Path $dev)) { New-Item -ItemType Directory -Path $dev | Out-Null }
# Program files and plugins, not the world, not the data, not the logs. The
# rolled ones too, server.log.1 and the rest, or dev starts with live's.
& robocopy $live $dev /E /XD data world "world-before-*" /XF *.log *.log.* /NFL /NDL /NJH /NJS /NP | Out-Null
Say ("  server files copied (robocopy code {0})" -f $LASTEXITCODE)

# Data: the door, the allowed list, the manifest and the scripts and api
# folders come across. characters.json does not: the dev world is its own.
$dd = Join-Path $dev 'data'
$pd = Join-Path $dev 'private'
if (-not (Test-Path $dd)) { New-Item -ItemType Directory -Path $dd | Out-Null }
if (-not (Test-Path $pd)) { New-Item -ItemType Directory -Path $pd | Out-Null }

foreach ($n in 'door.json', 'allowed.json', 'manifest.json') {
    $src = Join-Path $live "data\$n"
    if ((Test-Path $src) -and -not (Test-Path (Join-Path $dd $n))) { Copy-Item $src (Join-Path $dd $n) }
}
foreach ($d in 'scripts', 'api') {
    $src = Join-Path $live "data\$d"
    if ((Test-Path $src) -and -not (Test-Path (Join-Path $dd $d))) { Copy-Item $src (Join-Path $dd $d) -Recurse }
}

if (-not (Test-Path (Join-Path $pd 'characters.json'))) { Set-Content (Join-Path $pd 'characters.json') '[]' -Encoding ASCII }
Say '  data and private folders ready (fresh characters.json)'

# server-settings.json: the dev port, the dev name, plugin paths under the dev folder.
$settingsFile = Join-Path $dev 'server-settings.json'
$s = Get-Content (Join-Path $live 'server-settings.json') -Raw | ConvertFrom-Json
$s.port = $devPort
$s.name = 'Thornswood Dev'
$s.loadOrder = @($s.loadOrder | ForEach-Object { $_ -replace [regex]::Escape('C:/Thornswood-Server/'), 'C:/Thornswood-Server-Dev/' })
[IO.File]::WriteAllText($settingsFile, ($s | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
Say ("  server-settings.json: port {0}, name Thornswood Dev, {1} plugins" -f $devPort, $s.loadOrder.Count)

# The task, the same shape as the live one (SYSTEM, at boot, restart on
# failure), with the folder swapped.
$liveTask = Get-ScheduledTask -TaskName 'Thornswood Server'
if (-not (Get-ScheduledTask -TaskName 'Thornswood Dev Server' -ErrorAction SilentlyContinue)) {
    $a = $liveTask.Actions[0]
    $args2 = $a.Arguments -replace [regex]::Escape($live), $dev
    $action = New-ScheduledTaskAction -Execute $a.Execute -Argument $args2 -WorkingDirectory $dev
    Register-ScheduledTask -TaskName 'Thornswood Dev Server' -Action $action -Trigger $liveTask.Triggers -Principal $liveTask.Principal -Settings $liveTask.Settings | Out-Null
    Say '  task Thornswood Dev Server registered'
} else { Say '  task Thornswood Dev Server already there' }

# ------------------------------------------------------------------- voice
if (Test-Path $liveVoice) {
    if (-not (Test-Path $devVoice)) { New-Item -ItemType Directory -Path $devVoice | Out-Null }
    & robocopy $liveVoice $devVoice /E /XF *.log *.log.* run-dev-voice.cmd /NFL /NDL /NJH /NJS /NP | Out-Null
    Say ("  voice files copied (robocopy code {0})" -f $LASTEXITCODE)
    # The port comes from the environment. A run file sets it, so the task
    # command stays free of cmd's quoting rules.
    # roll-log.ps1 came across with the rest and runs before node opens
    # voice.log, the one moment nothing holds it. See Roll-Log.ps1.
    $run = Join-Path $devVoice 'run-dev-voice.cmd'
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $lines = @(
        '@echo off',
        ('set THORNSWOOD_VOICE_PORT={0}' -f $devVoicePort),
        'set THORNSWOOD_SITE=https://thornswood.net',
        ('cd /d "{0}"' -f $devVoice),
        ('"{0}" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{1}\roll-log.ps1" -Path "{1}\voice.log"' -f $psExe, $devVoice),
        ('"{0}" voice-server.js >> "{1}\voice.log" 2>&1' -f $node, $devVoice)
    )
    [IO.File]::WriteAllLines($run, [string[]]$lines, (New-Object Text.ASCIIEncoding))
    $liveVoiceTask = Get-ScheduledTask -TaskName 'Thornswood Voice'
    if (-not (Get-ScheduledTask -TaskName 'Thornswood Dev Voice' -ErrorAction SilentlyContinue)) {
        $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument ('/c "{0}"' -f $run) -WorkingDirectory $devVoice
        Register-ScheduledTask -TaskName 'Thornswood Dev Voice' -Action $action -Trigger $liveVoiceTask.Triggers -Principal $liveVoiceTask.Principal -Settings $liveVoiceTask.Settings | Out-Null
        Say '  task Thornswood Dev Voice registered'
    } else { Say '  task Thornswood Dev Voice already there' }
}

# ---------------------------------------------------------------- firewall
$rules = @(
    @{ Name = 'Thornswood Dev game (UDP)';      Protocol = 'UDP'; Port = $devPort },
    @{ Name = 'Thornswood Dev game (TCP)';      Protocol = 'TCP'; Port = $devPort },
    @{ Name = 'Thornswood Dev resources (TCP)'; Protocol = 'TCP'; Port = ($devPort + 1) },
    @{ Name = 'Thornswood Dev Voice';           Protocol = 'TCP'; Port = $devVoicePort }
)
foreach ($r in $rules) {
    if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow -Protocol $r.Protocol -LocalPort $r.Port | Out-Null
        Say ("  firewall: {0} open" -f $r.Name)
    }
}

# ---------------------------------------------------------------- watchdog
$watch = 'C:\Thornswood-Watch\watch.ps1'
if (Test-Path $watch) {
    $w = Get-Content $watch -Raw
    if ($w -notmatch 'Thornswood Dev Server') {
        $anchor = "  @{ Name = 'bot';     Task = 'Thornswood Bot';    Port = 0    }"
        if ($w.Contains($anchor)) {
            $w = $w.Replace($anchor, "  @{ Name = 'bot';     Task = 'Thornswood Bot';    Port = 0    },`r`n  @{ Name = 'dev game';  Task = 'Thornswood Dev Server'; Port = $($devPort + 1) },`r`n  @{ Name = 'dev voice'; Task = 'Thornswood Dev Voice';  Port = $devVoicePort }")
            [IO.File]::WriteAllText($watch, $w, (New-Object Text.UTF8Encoding($false)))
            Say '  watchdog now watches the dev server and dev voice'
        } else { Say '  watchdog: could not find the checks list, left alone' }
    } else { Say '  watchdog already knows the dev services' }
}

if ($Start) {
    Start-ScheduledTask -TaskName 'Thornswood Dev Server'
    if (Get-ScheduledTask -TaskName 'Thornswood Dev Voice' -ErrorAction SilentlyContinue) { Start-ScheduledTask -TaskName 'Thornswood Dev Voice' }
    Start-Sleep -Seconds 20
    Get-NetUDPEndpoint | Where-Object { $_.LocalPort -eq $devPort } | ForEach-Object { Say ("  dev game server listening on UDP {0}" -f $_.LocalPort) }
    Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -in ($devPort + 1), $devVoicePort } | ForEach-Object { Say ("  listening on TCP {0}" -f $_.LocalPort) }
    Get-Content (Join-Path $dev 'server.log') -Tail 8 -ErrorAction SilentlyContinue
    Get-Content (Join-Path $devVoice 'voice.log') -Tail 3 -ErrorAction SilentlyContinue
}
Say 'done'
