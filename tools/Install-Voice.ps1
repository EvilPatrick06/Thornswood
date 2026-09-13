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
#>
[CmdletBinding()]
param(
    [string]$VpsHost  = '192.135.112.23',
    [string]$VpsUser  = 'Administrator',
    [string]$Root     = 'C:\Thornswood-Voice',
    [int]$Port        = 7778,
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
if (-not (Get-NetFirewallRule -DisplayName 'Thornswood Voice' -EA SilentlyContinue)) {
    New-NetFirewallRule -DisplayName 'Thornswood Voice' -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow | Out-Null
}

`$log = Join-Path '$Root' 'voice.log'
`$cmd = ('/c ""{0}" voice-server.js >> "{1}" 2>&1"' -f `$node.Source, `$log)

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

`$killed = 0
foreach (`$p in @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -EA SilentlyContinue)) {
    if (`$p.CommandLine -and `$p.CommandLine -like '*voice-server.js*') {
        Stop-Process -Id `$p.ProcessId -Force -EA SilentlyContinue
        `$killed++
    }
}
if (`$killed) { "stopped `$killed old voice process(es)" }

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

$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))
& ssh $target "powershell -NoProfile -EncodedCommand $b64"
if ($LASTEXITCODE -ne 0) { Die "the install on the VPS exited with $LASTEXITCODE" }

# ---------------------------------------------------------------- verify ----
Head 'Checking from here'
$up = $false
for ($i = 0; $i -lt 15; $i++) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $null = $c.BeginConnect($VpsHost, $Port, $null, $null).AsyncWaitHandle.WaitOne(1000)
        $up = $c.Connected; $c.Close()
    } catch { }
    if ($up) { break }
    Start-Sleep -Seconds 1
}

Write-Host ''
if ($up) {
    Say "Voice is up at http://${VpsHost}:$Port" 'Green'
    Write-Host ''
    Say 'Next:  .\Add-VoiceFeed.ps1   then  .\Publish-Server.ps1' 'Yellow'
} else {
    Say "Installed, but nothing is answering on ${VpsHost}:$Port." 'Red'
    Say "  ssh $target `"powershell -NoProfile -Command Get-Content '$Root\voice.log' -Tail 20`"" 'DarkGray'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
