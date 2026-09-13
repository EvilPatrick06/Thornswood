<#
  Install-ThornswoodServer.ps1

  Run this ON THE VPS, after Bootstrap-VPS.ps1, as Administrator.

  Unpacks the payload, checks the load order actually resolves, and registers a
  scheduled task so the server comes back after a reboot.

  Why a scheduled task rather than a real service: node.exe is not a service
  binary, so New-Service cannot drive it, and NSSM is not installed. A task with
  an "at startup" trigger and "run whether logged on or not" is built into
  Windows and does the same job. The cost is that it does not restart on crash
  by itself, which is what -RestartOnFailure adds via a second repeating trigger.
#>
[CmdletBinding()]
param(
    [string]$Zip      = 'C:\thornswood-server.zip',
    [string]$Root     = 'C:\Thornswood-Server',
    [string]$TaskName = 'Thornswood Server',
    [switch]$NoTask,          # unpack only, start it by hand
    [switch]$StartNow
)

$ErrorActionPreference = 'Stop'

if (Test-Path 'C:\Thornswood\Game\SkyrimSE.exe') {
    throw "SkyrimSE.exe is present, so this looks like the gaming PC, not the VPS. Nothing was changed."
}
if (-not (Test-Path -LiteralPath $Zip)) { throw "not found: $Zip" }

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

# ---- unpack ----------------------------------------------------------------
# The world folder is the one thing worth preserving across reinstalls: it holds
# every character on the server.
$world = Join-Path $Root 'world'
$worldBak = $null
if (Test-Path -LiteralPath $world) {
    $worldBak = Join-Path $env:TEMP ("world-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item -LiteralPath $world -Destination $worldBak -Recurse -Force
    Write-Host "existing world set aside at $worldBak" -ForegroundColor Yellow
}

if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force }
New-Item -ItemType Directory -Path $Root -Force | Out-Null
Expand-Archive -LiteralPath $Zip -DestinationPath $Root -Force
Write-Host "unpacked to $Root" -ForegroundColor Cyan

if ($worldBak) {
    Copy-Item -LiteralPath $worldBak -Destination $world -Recurse -Force
    Write-Host 'world restored' -ForegroundColor Cyan
}

# ---- check the load order resolves before trusting it ----------------------
# A byte order mark on this file is fatal and says nothing useful when it
# happens: node stops on the first character with "Unexpected token" and the
# stack points into skymp's settings loader, not at whatever wrote the file.
# PowerShell 5.1 puts one there when 7 does not, so a payload built on one
# machine can start fine and the same payload built on another cannot. Taken
# off here as well as fixed at the source, because payloads built before that
# fix are still sitting in people's folders.
$settingsPath = Join-Path $Root 'server-settings.json'
$bytes = [IO.File]::ReadAllBytes($settingsPath)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    [IO.File]::WriteAllBytes($settingsPath, $bytes[3..($bytes.Length - 1)])
    Write-Host 'took a byte order mark off server-settings.json, node cannot parse one' -ForegroundColor Yellow
}

$s = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$bad = @()
foreach ($p in $s.loadOrder) {
    if (-not (Test-Path -LiteralPath ($p -replace '/', '\'))) { $bad += $p }
}
if ($bad) {
    Write-Host ''
    Write-Host ("{0} plugin(s) in the load order are not on disk:" -f $bad.Count) -ForegroundColor Red
    foreach ($b in $bad) { Write-Host "    $b" -ForegroundColor Red }
    throw 'load order does not resolve. The server would refuse to start, and a shortened load order would shift every index after the gap.'
}
Write-Host ("load order: all {0} plugins present" -f $s.loadOrder.Count) -ForegroundColor Green

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
    $log = Join-Path $Root 'server.log'
    $cmd = ('/c ""{0}" dist_back/skymp5-server.js >> "{1}" 2>&1"' -f $node.Source, $log)
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" `
                                      -Argument $cmd `
                                      -WorkingDirectory $Root
    $triggers = @(New-ScheduledTaskTrigger -AtStartup)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                             -DontStopIfGoingOnBatteries `
                                             -StartWhenAvailable `
                                             -RestartCount 999 `
                                             -RestartInterval (New-TimeSpan -Minutes 1) `
                                             -ExecutionTimeLimit ([TimeSpan]::Zero)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers `
                           -Settings $settings -Principal $principal | Out-Null
    Write-Host "scheduled task '$TaskName' registered, starts at boot, restarts every minute if it stops" -ForegroundColor Cyan
}

if ($StartNow -and -not $NoTask) {
    $log = Join-Path $Root 'server.log'
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue }

    Start-ScheduledTask -TaskName $TaskName

    # Wait for the resources port rather than a fixed few seconds, and when it
    # never opens, print the log instead of leaving the caller to guess.
    $up = $false
    for ($i = 0; $i -lt 30; $i++) {
        try {
            $c = New-Object Net.Sockets.TcpClient
            $null = $c.BeginConnect('127.0.0.1', 3000, $null, $null).AsyncWaitHandle.WaitOne(500)
            $up = $c.Connected
            $c.Close()
        } catch { }
        if ($up) { break }
        Start-Sleep -Seconds 1
    }

    $t = Get-ScheduledTask -TaskName $TaskName
    Write-Host ("task state: {0}" -f $t.State) -ForegroundColor DarkGray

    if ($up) {
        Write-Host 'the server is answering on 3000' -ForegroundColor Green
    }
    else {
        Write-Host ''
        Write-Host 'the server did not come up. Its log says:' -ForegroundColor Red
        if (Test-Path -LiteralPath $log) {
            Get-Content -LiteralPath $log -Tail 30 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        }
        else {
            Write-Host '    nothing was written, so node never started. Check that node is on the machine PATH.' -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host ''
Write-Host ("the task appends everything it prints to {0}\server.log" -f $Root) -ForegroundColor DarkGray
