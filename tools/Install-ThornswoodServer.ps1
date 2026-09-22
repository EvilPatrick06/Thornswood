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
<#
  Two things survive a reinstall, not one.

  world is the obvious one: it holds every character on the server.

  data is the one that was being quietly thrown away. The gamemode writes
  private\characters.json while people are online, and that file is where the
  launcher gets the race, the sex and the name to put on a character card. It
  is written by playing, not by building, so nothing in the payload can put it
  back. Every publish was wiping it and taking the details off everybody's
  cards until each person next logged in.

  The two are restored differently and the difference matters. world is copied
  back over the top, because the payload has no world and whatever was here is
  the truth. data does have shipped contents, so only files the fresh unpack
  did NOT provide are put back: runtime state returns, and anything that came
  with the build stays at the version that was just installed.
#>
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$world = Join-Path $Root 'world'
$worldBak = $null
if (Test-Path -LiteralPath $world) {
    $worldBak = Join-Path $env:TEMP ("world-" + $stamp)
    Copy-Item -LiteralPath $world -Destination $worldBak -Recurse -Force
    Write-Host "existing world set aside at $worldBak" -ForegroundColor Yellow
}

$dataDir = Join-Path $Root 'data'
$dataBak = $null
if (Test-Path -LiteralPath $dataDir) {
    $dataBak = Join-Path $env:TEMP ("serverdata-" + $stamp)
    Copy-Item -LiteralPath $dataDir -Destination $dataBak -Recurse -Force
    Write-Host "existing data set aside at $dataBak" -ForegroundColor Yellow
}

<#
  AND THE PRIVATE FOLDER, WHICH IS WHERE THE ROSTER LIVES.

  This set aside the world and the data folder and not this one, so every
  install since there has been a private folder has deleted it: door.json,
  allowed.json and characters.json, gone, on a script that reports nothing but
  success.

  gamemode.js already wrote down what that costs, on 20 September, when the
  whole folder went: "the character register silently stops being saved, the
  door silently never fetches a roster, and /tp silently refuses everybody
  because the list it reads was never written. That is three separate reports
  with one cause and no log line between them." It was read as a one off. It
  is this script, every time.

  Patrick, 21 September, from the dev server: "Dev has no playtetser list so I
  can't tp like I can on main."

  Restored whole rather than file by file, unlike data. Nothing in a build
  ships into private, so there is no shipped file here for a new build to be
  entitled to replace, and merging would only risk half a roster.
#>
$privDir = Join-Path $Root 'private'
$privBak = $null
if (Test-Path -LiteralPath $privDir) {
    $privBak = Join-Path $env:TEMP ("serverprivate-" + $stamp)
    Copy-Item -LiteralPath $privDir -Destination $privBak -Recurse -Force
    Write-Host "existing roster set aside at $privBak" -ForegroundColor Yellow
}

<#
  THE OLD SERVER LETTING GO, WHICH IT DOES NOT ALWAYS DO ON ITS OWN.

  21 September, on a dev publish that had just said "stopped":

    Remove-Item : Cannot remove item
    C:\Thornswood-Server-Dev\data\api\servers\thornswood\plugins\10.bin:
    Access to the path '10.bin' is denied.
    STOP. the installer on the VPS exited with 1.

  Stopping a scheduled task asks the process to end. It does not wait for it,
  and node does not drop its file handles the instant it is asked: the
  resources server under data\api holds the plugin files it is serving. So the
  delete raced the process, hit one locked file, and took the whole install
  down after the payload had already been copied up.

  Three things, in the order that costs least.

  ONE, ask anything still running under this root to stop, by command line
  rather than by name, because the live server and the dev server are both node
  and killing by name would take the other one down. That is the same rule
  Publish-Server settled on 21 September after a dev publish stopped live.

  TWO, wait for the handles. A few short goes rather than one long sleep, so
  the ordinary case where it is already gone costs nothing.

  THREE, say which file it was if it still will not go, because "access to the
  path is denied" without a process name is the start of a long evening.
#>
if (Test-Path -LiteralPath $Root) {
    $rootMatch = $Root.TrimEnd('\') + '\*'
    try {
        foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -EA SilentlyContinue)) {
            if ($p.CommandLine -and $p.CommandLine -like $rootMatch) {
                Write-Host ("asking node {0} under this root to stop" -f $p.ProcessId) -ForegroundColor Yellow
                Stop-Process -Id $p.ProcessId -Force -EA SilentlyContinue
            }
        }
    } catch { }

    $gone = $false
    for ($i = 1; $i -le 10; $i++) {
        try {
            Remove-Item -LiteralPath $Root -Recurse -Force -EA Stop
            $gone = $true
            break
        } catch {
            if ($i -eq 1) {
                Write-Host 'the old server is still holding a file, waiting for it' -ForegroundColor Yellow
            }
            Start-Sleep -Milliseconds 700
        }
    }

    if (-not $gone) {
        # Name what is still open, then stop rather than half installing.
        $stuck = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -EA SilentlyContinue |
                   Where-Object {
                       try { $h = [IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None'); $h.Close(); $false }
                       catch { $true }
                   } | Select-Object -First 5)
        foreach ($f in $stuck) { Write-Host ("still open: {0}" -f $f.FullName) -ForegroundColor Red }
        throw ("could not clear $Root after ten tries. Something outside this " +
               "script is holding those files; the world, the data folder and " +
               "the roster are all still set aside in $env:TEMP.")
    }
}
New-Item -ItemType Directory -Path $Root -Force | Out-Null
Expand-Archive -LiteralPath $Zip -DestinationPath $Root -Force
Write-Host "unpacked to $Root" -ForegroundColor Cyan

if ($worldBak) {
    Copy-Item -LiteralPath $worldBak -Destination $world -Recurse -Force
    Write-Host 'world restored' -ForegroundColor Cyan
}

# See the note above. Whole, because nothing in a build ships into private.
if ($privBak) {
    Copy-Item -LiteralPath $privBak -Destination $privDir -Recurse -Force
    $n = @(Get-ChildItem -LiteralPath $privDir -Recurse -File -Force -EA SilentlyContinue).Count
    Write-Host "roster restored, $n file(s) including door.json and allowed.json" -ForegroundColor Cyan
} elseif (-not (Test-Path -LiteralPath $privDir)) {
    <#
      A root that has never had one. The door writes allowed.json itself once
      it has fetched, and the register writes characters.json, but neither can
      write into a folder that is not there: gamemode.js does one mkdir at load
      for exactly that reason. Saying so here is the difference between "this
      server has no roster yet" and the silence that cost three reports.
    #>
    New-Item -ItemType Directory -Path $privDir -Force | Out-Null
    Write-Host 'no roster to restore: this root has never had a private folder.' -ForegroundColor Yellow
    Write-Host '  /tp will refuse everybody until door.json is put there.' -ForegroundColor Yellow
}

if ($dataBak) {
    $kept = 0
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    foreach ($f in @(Get-ChildItem -LiteralPath $dataBak -Recurse -File -Force -EA SilentlyContinue)) {
        $rel = $f.FullName.Substring($dataBak.Length).TrimStart('\')
        $to = Join-Path $dataDir $rel
        # Only what the build did not bring. A shipped file that also exists in
        # the backup is a file the new build is entitled to replace.
        if (Test-Path -LiteralPath $to) { continue }
        New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $to -Force
        $kept++
    }
    if ($kept -gt 0) {
        Write-Host "kept $kept runtime file$(if ($kept -eq 1) { '' } else { 's' }) in data, including the character book" -ForegroundColor Cyan
    }
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
