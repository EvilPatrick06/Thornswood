<#
  Install-Voice.ps1

  Puts the proximity voice service on the VPS beside the game server and opens
  the one port it needs. Run it from this machine; it does the remote half
  over ssh.

  How the thing works, in three lines:
    the gamemode pushes everyone's position to the voice service five times a
    second, over loopback on the VPS. Everyone's browser holds a WebSocket to
    that service for positions and for WebRTC signalling. The audio itself goes
    straight between people and never touches the server.

  Positions come from the game server rather than from anybody's game, so voice
  works whichever SkyMP client somebody runs, and nobody can move their own
  voice around by editing a file on their machine.

      .\Install-Voice.ps1              install and start it
      .\Install-Voice.ps1 -Restart     just restart it
      .\Install-Voice.ps1 -Remove      take it off again
      .\Install-Voice.ps1 -Auth on     require a join to prove itself
      .\Install-Voice.ps1 -ChatRange on   typed chat reaches only the people near
#>
[CmdletBinding()]
param(
  # The site the voice server asks about character creation choices. Empty
  # turns that check off, which is how this behaved before it existed.
  [string]$Site = 'https://thornswood.net',
    [string]$VpsHost  = '192.135.112.23',
    [string]$VpsUser  = 'Administrator',
    [string]$Root     = 'C:\Thornswood-Voice',
    [int]$Port        = 7778,
    # Which addresses the service answers on. Every interface is how this
    # has always worked and is what an older launcher needs. 127.0.0.1 is
    # for when Caddy carries /voice/ and the raw port is closing: check
    # nothing is still connecting directly before using it, because a
    # launcher that cannot reach voice has the address compiled in and no
    # change here reaches it.
    [ValidateSet('0.0.0.0', '127.0.0.1')]
    [string]$Bind     = '0.0.0.0',
    # Whether a join has to prove itself. log is the shipped default: an
    # unproven join is let in as whatever profile it claims, and a line is
    # written so that can be checked before anything is actually refused.
    # on refuses it outright. off is the behaviour from before entry 6, kept
    # for working out whether a problem is the auth check or something else.
    [ValidateSet('on', 'log', 'off')]
    [string]$Auth     = 'log',
    # Who reads a typed line, entry 150. off is the shipped default and is
    # every line to everybody, as it has always been. on is the same cell
    # and 4000 units, the range /ooc uses, and turns on /me, /do, /w and /s;
    # a number is the range in units. See CHAT_RANGE in voice\voice-server.js.
    [ValidatePattern('^(off|on|\d+)$')]
    [string]$ChatRange = 'off',
    [string]$TaskName = 'Thornswood Voice',
    [switch]$Restart,
    [switch]$Remove,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$target = "$VpsUser@$VpsHost"
foreach ($t in 'ssh', 'scp') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client."
    }
}

if ($Remove) {
    Head 'Removing'
    & ssh $target "powershell -NoProfile -Command `"Stop-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue; Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false -EA SilentlyContinue; Remove-NetFirewallRule -DisplayName 'Thornswood Voice' -EA SilentlyContinue; Remove-Item -LiteralPath '$Root' -Recurse -Force -EA SilentlyContinue; 'removed'`""
    Say 'Gone. The game server is untouched.' 'Green'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

if ($Restart) {
    Head 'Restarting'
    & ssh $target "powershell -NoProfile -Command `"Stop-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue; Start-Sleep -Seconds 1; Start-ScheduledTask -TaskName '$TaskName'; 'restarted'`""
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

<#
  What is already running, so a flag left off does not quietly undo it.

  -Bind and -Auth both changed real behaviour today and both default to
  0.0.0.0 and log whatever is already live. That is right for a first
  install. Once the service is on loopback and enforcing, though, a later
  command that leaves either one off, which is the easy thing to do once this
  is routine, would silently reopen the port or drop back out of enforcing
  it. Read what is actually running first, and keep it unless the flag was
  actually passed.
#>
$bindExplicit = $PSBoundParameters.ContainsKey('Bind')
$authExplicit = $PSBoundParameters.ContainsKey('Auth')
$chatExplicit = $PSBoundParameters.ContainsKey('ChatRange')
if (-not $bindExplicit -or -not $authExplicit -or -not $chatExplicit) {
    $probe = @"
try { `$h = Invoke-RestMethod 'http://127.0.0.1:$Port/health' -TimeoutSec 5; 'bind=' + `$h.bind + ';auth=' + `$h.auth + ';chat=' + `$h.chatRange } catch { 'none' }
"@
    $current = & (Join-Path $Here 'Remote.ps1') $probe -VpsHost $VpsHost -VpsUser $VpsUser 2>$null | Select-Object -Last 1
    if ("$current" -match 'bind=([\d.]+);auth=(on|log|off)') {
        if (-not $bindExplicit) { Say "  keeping the current bind, $($Matches[1]), since -Bind was not passed" 'DarkGray'; $Bind = $Matches[1] }
        if (-not $authExplicit) { Say "  keeping the current auth, $($Matches[2]), since -Auth was not passed" 'DarkGray'; $Auth = $Matches[2] }
    }
    # A range of 0, or a service older than the setting that reports none, is
    # off, which is already the default, so only a live range is kept.
    if (-not $chatExplicit -and "$current" -match ';chat=([1-9]\d*)') {
        Say "  keeping the current chat range, $($Matches[1]), since -ChatRange was not passed" 'DarkGray'; $ChatRange = $Matches[1]
    }
}

# ---------------------------------------------------------------- files -----
$src = Join-Path $Here 'voice'
foreach ($f in 'voice-server.js', 'public\index.html', 'public\voice.js') {
    if (-not (Test-Path -LiteralPath (Join-Path $src $f))) { Die "not found: $(Join-Path $src $f)" }
}

Head 'Copying'
& ssh $target "powershell -NoProfile -Command `"New-Item -ItemType Directory -Force -Path '$Root\public' | Out-Null; 'ready'`""
if ($LASTEXITCODE -ne 0) { Die "ssh exited with $LASTEXITCODE" }

& scp (Join-Path $src 'voice-server.js') "${target}:$($Root -replace '\\','/')/voice-server.js"
if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE" }

# THE CHARACTER REGISTER IS GONE, 23 September, and so is the secret it used.
#
# The three routes it guarded, /whoami, /claim and /owners, refused every real
# caller with 403, because each one required a password the launcher
# deliberately never sent: Account.cs and CharSync.cs were written that way and
# were themselves deleted on 20 September. They are out of voice-server.js now
# along with owners.json, and tools\Characters.ps1, which existed only to read
# them, went with them.
#
# Sending a secret that nothing reads is worse than sending nothing, so this
# step is gone too. The service's own join tokens are signed with a key it
# makes for itself in token-key.txt and have nothing to do with this.

& scp (Join-Path $src 'public\index.html') "${target}:$($Root -replace '\\','/')/public/index.html"
& scp (Join-Path $src 'public\voice.js') "${target}:$($Root -replace '\\','/')/public/voice.js"
Say 'copied' 'Green'

<#
  The build string out of the file we just copied.

  Checked on the far end after the restart, because "the port answers" turned
  out to prove nothing at all. See the kill below for why.
#>
$expectBuild = ''
try {
    $m = [regex]::Match((Get-Content -LiteralPath (Join-Path $src 'voice-server.js') -Raw),
                        "const\s+BUILD\s*=\s*'([^']+)'")
    if ($m.Success) { $expectBuild = $m.Groups[1].Value }
} catch { }

# ---------------------------------------------------------------- install ---
Head 'Installing'
$remote = @"
`$ErrorActionPreference = 'Stop'
# Progress records come back as a wall of CLIXML when stdout is not a console.
`$ProgressPreference = 'SilentlyContinue'
`$node = (Get-Command node -EA SilentlyContinue)
if (-not `$node) {
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    `$node = Get-Command node -EA SilentlyContinue
}
if (-not `$node) { throw 'node is not installed on this machine' }

# The port everyone's browser connects to. The position feed is loopback only
# and needs nothing opened.
# Checked under the same name it is created under. This used to look for
# 'Thornswood Voice' and create '$TaskName', so installing dev found the live
# rule already there and never opened 7789 at all.
if (-not (Get-NetFirewallRule -DisplayName '$TaskName' -EA SilentlyContinue)) {
    New-NetFirewallRule -DisplayName '$TaskName' -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
}

`$log = Join-Path '$Root' 'voice.log'
# THORNSWOOD_SITE is what lets /choose check that a character creation choice
# actually came from the person who owns that profile. That endpoint has to be
# reachable from every person's machine, so it cannot be locked to the loopback,
# and without this it takes anybody's word for anything.
#
# set is used rather than a scheduled task environment block because a task
# action has nowhere to put one, and this is the whole command line anyway.
# THORNSWOOD_VOICE_PORT is what the service actually reads (voice-server.js:28).
# Without it on this line -Port drove the firewall rule, the is-it-free check
# and the health probe, and nothing else, so -Port 7789 opened 7789, checked
# 7789 was free, and then started a service that bound 7778 on top of live.
`$cmd = ('/c "set THORNSWOOD_SITE=$Site&& set THORNSWOOD_VOICE_PORT=$Port&& set THORNSWOOD_VOICE_BIND=$Bind&& set THORNSWOOD_VOICE_AUTH=$Auth&& set THORNSWOOD_CHAT_RANGE=$ChatRange&& "{0}" voice-server.js >> "{1}" 2>&1"' -f `$node.Source, `$log)

<#
  Stop the old service, and mean it.

  This used to be a bare Unregister-ScheduledTask. Unregistering removes the
  task definition and leaves the process it started running, so the old node
  kept the port. The new one then died on the bind, instantly, and every check
  that followed connected to the orphan and called it success: the copy said
  17 KB, the install said 'voice is up', the launcher said nothing was wrong,
  and the code running up here was still whatever was current the day the VPS
  last rebooted. Days of voice-server changes went to disk and never ran.

  So: stop the task, then kill anything still holding voice-server.js open,
  then wait for the port to actually let go before starting anything.
#>
Stop-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue
if (Get-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue) { Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false }

# Ours, and only ours.
#
# This used to kill every node running voice-server.js, whatever folder it
# ran from. There are two of these services, live and dev, so installing
# either one killed the other. On 18 September installing dev stopped live
# and the dev copy then took 7778 with dev's data on it.
#
# Two ways a process counts as ours, and it needs one of them: it was
# started from this root, which the log path in its command line shows, or
# it is sitting on the port we are about to bind, which makes it an orphan
# in our way whoever started it.
`$mine = @()
foreach (`$p in @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -EA SilentlyContinue)) {
    if (-not `$p.CommandLine) { continue }
    if (`$p.CommandLine -notlike '*voice-server.js*') { continue }
    # NOTE the backtick. $log belongs to the remote script (it is set at the
    # top of this here-string), not to this one. Written as '$log' the outer
    # PowerShell expands it, finds nothing, and the test becomes '**', which
    # matches every voice process there is. That is how this killed live
    # twice on 18 September while reporting it had stopped one 'for this root'.
    # The log path is NOT on node's own command line. The task runs
    # cmd.exe /c "set ... && node voice-server.js >> <log>", so cmd owns the
    # redirect and node's command line is bare: node.exe voice-server.js.
    # Measured on the box 18 September, where a check that read node's line
    # could not tell live from dev and answered '?'. The parent shell is what
    # carries the folder.
    if (`$p.CommandLine -like ('*' + `$log + '*')) { `$mine += `$p.ProcessId; continue }
    `$parent = Get-CimInstance Win32_Process -Filter ("ProcessId=" + `$p.ParentProcessId) -EA SilentlyContinue
    if (`$parent -and `$parent.CommandLine -like ('*' + `$log + '*')) { `$mine += `$p.ProcessId; continue }
    `$onPort = Get-NetTCPConnection -State Listen -LocalPort $Port -EA SilentlyContinue |
              Where-Object { `$_.OwningProcess -eq `$p.ProcessId }
    if (`$onPort) { `$mine += `$p.ProcessId }
}
# Going to loopback with somebody still on the raw port cuts them off in
# the middle of a word, and nothing on this box can reach them to say so.
if ('$Bind' -eq '127.0.0.1') {
    `$direct = @(Get-NetTCPConnection -LocalPort $Port -State Established -EA SilentlyContinue |
                Where-Object { `$_.RemoteAddress -notin '127.0.0.1', '::1' })
    if (`$direct.Count) {
        'REFUSING to bind to loopback: ' + `$direct.Count + ' connection(s) are still on the raw port:'
        foreach (`$d in `$direct) { '   ' + `$d.RemoteAddress + ' since ' + `$d.CreationTime }
        'Those are launchers that have not moved to the proxy. Leave the port open.'
        exit 9
    }
    'nothing is on the raw port directly, so loopback is safe'
}

`$killed = 0
foreach (`$id in (`$mine | Select-Object -Unique)) {
    # The parent shell first, so it cannot outlive the node it started.
    `$par = (Get-CimInstance Win32_Process -Filter ("ProcessId=" + `$id) -EA SilentlyContinue).ParentProcessId
    Stop-Process -Id `$id -Force -EA SilentlyContinue
    if (`$par) {
        `$pp = Get-CimInstance Win32_Process -Filter ("ProcessId=" + `$par) -EA SilentlyContinue
        if (`$pp -and `$pp.Name -eq 'cmd.exe') { Stop-Process -Id `$par -Force -EA SilentlyContinue }
    }
    `$killed++
}
if (`$killed) { "stopped `$killed old voice process(es) for this root" }
`$others = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -EA SilentlyContinue |
            Where-Object { `$_.CommandLine -like '*voice-server.js*' })
if (`$others.Count) { "left " + `$others.Count + " other voice process(es) alone" }

`$free = `$false
for (`$i = 0; `$i -lt 30; `$i++) {
    `$busy = `$false
    try {
        `$c = New-Object Net.Sockets.TcpClient
        `$null = `$c.BeginConnect('127.0.0.1', $Port, `$null, `$null).AsyncWaitHandle.WaitOne(300)
        `$busy = `$c.Connected; `$c.Close()
    } catch { }
    if (-not `$busy) { `$free = `$true; break }
    Start-Sleep -Milliseconds 500
}
if (-not `$free) { throw 'something is still holding port $Port up here and would not let go' }
`$action = New-ScheduledTaskAction -Execute "`$env:SystemRoot\System32\cmd.exe" -Argument `$cmd -WorkingDirectory '$Root'
`$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
`$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName '$TaskName' -Action `$action -Trigger (New-ScheduledTaskTrigger -AtStartup) -Settings `$settings -Principal `$principal | Out-Null

if (Test-Path -LiteralPath `$log) { Remove-Item -LiteralPath `$log -Force -EA SilentlyContinue }
Start-ScheduledTask -TaskName '$TaskName'

`$up = `$false
for (`$i = 0; `$i -lt 20; `$i++) {
    try {
        `$c = New-Object Net.Sockets.TcpClient
        `$null = `$c.BeginConnect('127.0.0.1', $Port, `$null, `$null).AsyncWaitHandle.WaitOne(500)
        `$up = `$c.Connected; `$c.Close()
    } catch { }
    if (`$up) { break }
    Start-Sleep -Seconds 1
}
if (-not `$up) {
    'voice did not come up. Its log says:'
    if (Test-Path -LiteralPath `$log) { Get-Content -LiteralPath `$log -Tail 20 } else { 'nothing was written' }
} else {
    # The port answering is not the test. Which build answers is the test.
    `$seen = ''
    for (`$i = 0; `$i -lt 20; `$i++) {
        try {
            `$h = Invoke-RestMethod -Uri 'http://127.0.0.1:$Port/health' -TimeoutSec 2
            `$seen = [string]`$h.build
        } catch { `$seen = '' }
        if (`$seen) { break }
        Start-Sleep -Seconds 1
    }
    `$want = '$expectBuild'
    if (-not `$want) { "voice is up on $Port" }
    elseif (`$seen -eq `$want) { "voice is up on $Port running `$seen" }
    else {
        "WRONG BUILD on $Port. sent `$want, running '`$seen'."
        'That means an old process is still answering. Its log says:'
        if (Test-Path -LiteralPath `$log) { Get-Content -LiteralPath `$log -Tail 20 } else { 'nothing was written' }
    }
}
"@

# THIS BLOCK HAS NEVER ARRIVED WHOLE, measured 23 September.
#
# sshd on Windows hands the command to cmd.exe, which stops at 8,191
# characters. Base64 of UTF-16 is about 2.7 times the script, and $remote is
# 9,117 characters, so what went up the wire was 24,350 characters and the far
# end saw roughly the first third of it. PowerShell then complains about a
# brace or a token in a script nobody can see, fifteen lines above the line
# that was actually cut.
#
# Deploy-Docs.ps1 found this on 17 September and sixteen scripts were given the
# fix on 20 September. This one was not among them and is the worst case in the
# repo: it is the whole install of the voice service.
#
# Under the limit it goes on the command line as before, because that is one
# round trip. Over it, the script is sent as a file and run from there, which
# has no length to run into. The exit code is kept across the tidy up, because
# the Remove-Item afterwards would otherwise be the code this reads, which is
# the fault entry 118 is about.
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))
$cmd = "powershell -NoProfile -EncodedCommand $b64"
if ($cmd.Length -le 6000) {
    & ssh $target $cmd
}
else {
    $far = 'C:/Windows/Temp/thornswood-install-voice.ps1'
    $tmp = [IO.Path]::GetTempFileName()
    try {
        Set-Content -LiteralPath $tmp -Value $remote -Encoding UTF8
        & scp $tmp "${target}:$far"
        if ($LASTEXITCODE -ne 0) { Die "could not send the install script to $VpsHost" }
        # The path goes across as it is: Windows PowerShell takes forward
        # slashes, and converting them is how a sister script once shipped
        # with the slashes stripped out entirely.
        & ssh $target "powershell -NoProfile -ExecutionPolicy Bypass -File '$far'"
        $rc = $LASTEXITCODE
        & ssh $target "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" | Out-Null
        $global:LASTEXITCODE = $rc
    }
    finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}
if ($LASTEXITCODE -ne 0) { Die "the install on the VPS exited with $LASTEXITCODE" }

# ---------------------------------------------------------------- verify ----
Head 'Checking from here'

<#
  What "working" looks like depends on the bind, and it used to not.

  This reached for the raw address and called silence a failure. Once the
  service is on loopback that silence is the entire point, so a correct install
  printed "Installed, but nothing is answering" in red. That is how somebody
  panics and reverts a change that worked, which is worse than the change
  having failed.

  So: on 0.0.0.0 the port must answer. On 127.0.0.1 it must NOT, and the
  service is reached through whatever is proxying instead.
#>
$reachable = $false
for ($i = 0; $i -lt 15; $i++) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $null = $c.BeginConnect($VpsHost, $Port, $null, $null).AsyncWaitHandle.WaitOne(1000)
        $reachable = $c.Connected; $c.Close()
    } catch { }
    if ($reachable) { break }
    # On loopback we are waiting to be sure it stays shut, not for it to open,
    # so there is nothing to keep retrying for.
    if ($Bind -eq '127.0.0.1') { break }
    Start-Sleep -Seconds 1
}

Write-Host ''
if ($Bind -eq '127.0.0.1') {
    if ($reachable) {
        Say "$VpsHost`:$Port IS STILL ANSWERING from outside, and it should not be." 'Red'
        Say '  The bind did not take, or the firewall rule is still open.' 'Red'
        Say "  ssh $target `"powershell -NoProfile -Command Get-Content '$Root\voice.log' -Tail 20`"" 'DarkGray'
    } else {
        Say "Loopback only, and ${VpsHost}:$Port is correctly shut from out here." 'Green'
        # The service is only useful if something is carrying it, so say whether
        # anything actually is rather than leaving that to be assumed.
        $via = ''
        if ($Site) { $via = $Site.TrimEnd('/') + $(if ($Port -eq 7778) { '/voice' } else { '/voice-dev' }) }
        if ($via) {
            try {
                $h = Invoke-RestMethod ($via + '/health') -TimeoutSec 10
                Say "Reached it through $via, build $($h.build), bind $($h.bind), auth $($h.auth)." 'Green'
            } catch {
                Say "But $via/health did not answer either, so nothing is carrying it." 'Red'
                Say '  Check the Caddyfile has the handle_path block for this port.' 'DarkGray'
            }
        }
    }
} elseif ($reachable) {
    Say "Voice is up at http://${VpsHost}:$Port" 'Green'
    Write-Host ''
    Say 'Next:  .\Add-VoiceFeed.ps1   then  .\Publish-Server.ps1' 'Yellow'
} else {
    Say "Installed, but nothing is answering on ${VpsHost}:$Port." 'Red'
    Say "  ssh $target `"powershell -NoProfile -Command Get-Content '$Root\voice.log' -Tail 20`"" 'DarkGray'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
