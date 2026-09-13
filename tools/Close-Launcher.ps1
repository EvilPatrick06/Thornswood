<#
  Close-Launcher.ps1

  Shared by every script that writes into the build. Dot-source it:

      . (Join-Path $PSScriptRoot 'Close-Launcher.ps1')

  The multiplayer client has carried the same name as the launcher, so everything here
  matches on the full path. Killing by name takes the game down with it.

  Stop-Game exists because Skyrim does not always let go. A crash, an Alt-F4,
  or one of the multiplayer client's browser helpers can leave a process behind
  with no window, which looks like nothing at all to the person sitting there
  and like a running game to anything that checks. Every script that writes
  into the build closes those itself rather than telling someone to go and find
  a window that is not on screen.
#>

function Get-LauncherProcesses {
    param([Parameter(Mandatory)][string]$Root)

    # Both names: Thornswood.exe now, SkyrimTogether.exe on any install made
    # before the rename, since the launcher updates itself in place.
    $exe = Join-Path $Root 'Launcher\Thornswood.exe'
    if (-not (Test-Path -LiteralPath $exe)) { $exe = Join-Path $Root 'Launcher\SkyrimTogether.exe' }
    $mine = @(); $unknown = 0
    foreach ($p in @(Get-Process -Name 'Thornswood', 'SkyrimTogether' -ErrorAction SilentlyContinue)) {
        $path = $null
        try { $path = $p.MainModule.FileName } catch { }
        if ($path -and ($path -eq $exe)) { $mine += $p }
        elseif (-not $path) { $unknown++ }
    }
    return [pscustomobject]@{ Mine = $mine; Unknown = $unknown; Exe = $exe }
}

function Get-GameProcesses {
    param([string]$Root)

    $launcher = ''
    if ($Root) {
        $launcher = Join-Path $Root 'Launcher\Thornswood.exe'
        if (-not (Test-Path -LiteralPath $launcher)) { $launcher = Join-Path $Root 'Launcher\SkyrimTogether.exe' }
    }
    $out = @()
    foreach ($n in 'SkyrimSE', 'skse64_loader', 'Thornswood', 'SkyrimTogether') {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            $path = $null
            try { $path = $p.MainModule.FileName } catch { }
            # The launcher shares its name with the multiplayer client. Only the
            # full path tells them apart, so a path we cannot read is left alone
            # rather than guessed at.
            if ($n -eq 'Thornswood' -or $n -eq 'SkyrimTogether') {
                if (-not $path) { continue }
                if ($launcher -and ($path -eq $launcher)) { continue }
            }
            $out += $p
        }
    }
    # The caller wraps this in @() as well. A return unrolls a one element
    # array back into a bare object, and .Count on one of those is an error
    # under StrictMode, which is exactly the shape this hits most often.
    return @($out)
}

function Stop-Game {
    param([string]$Root)

    $found = @(Get-GameProcesses -Root $Root)
    if ($found.Count -eq 0) { return $false }

    $names = ($found | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
    Write-Host "  Skyrim is still open ($names), closing it" -ForegroundColor Yellow

    foreach ($p in $found) { try { $null = $p.CloseMainWindow() } catch { } }
    for ($i = 0; $i -lt 24; $i++) {
        Start-Sleep -Milliseconds 250
        if (-not ($found | Where-Object { -not $_.HasExited })) { break }
    }
    foreach ($p in $found) {
        try { if (-not $p.HasExited) { $p.Kill() } } catch { }
    }

    # A killed process can sit in the table for a moment after it is gone, so
    # this waits rather than calling it a failure on the first look.
    $left = @()
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Milliseconds 250
        $left = @(Get-GameProcesses -Root $Root)
        if ($left.Count -eq 0) { break }
    }
    if ($left.Count -gt 0) {
        Write-Host "  $($left.Count) would not close. Sign out and back in, or restart." -ForegroundColor Red
        return $false
    }
    Write-Host '  Closed' -ForegroundColor Green
    return $true
}

function Test-GameRunning {
    param([Parameter(Mandatory)][string]$Root)

    foreach ($n in 'SkyrimSE', 'skse64_loader') {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            $path = $null
            try { $path = $p.MainModule.FileName } catch { }
            # A path we cannot read is running higher than us. Assume it counts,
            # because being wrong the other way means writing into a live game.
            if (-not $path -or $path.StartsWith($Root, 'OrdinalIgnoreCase')) { return $true }
        }
    }
    return $false
}

function Stop-Launcher {
    param([Parameter(Mandatory)][string]$Root)

    $found = Get-LauncherProcesses -Root $Root
    if ($found.Mine.Count -eq 0) {
        if ($found.Unknown -gt 0) {
            Write-Host "  $($found.Unknown) launcher process(es) I cannot identify, left alone." -ForegroundColor Yellow
            Write-Host '  If this fails on a locked file, close the launcher by hand.' -ForegroundColor Yellow
        }
        return $false
    }

    Write-Host '  Launcher is open, closing it' -ForegroundColor Yellow
    # Asking first matters: on the way out the launcher puts your Windows
    # Skyrim folders back. Killing it outright leaves them pointed at the build.
    foreach ($p in $found.Mine) { try { $null = $p.CloseMainWindow() } catch { } }
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 250
        if (-not ($found.Mine | Where-Object { -not $_.HasExited })) { break }
    }
    foreach ($p in $found.Mine) {
        try { if (-not $p.HasExited) { Write-Host '    it did not close on its own, ending it' -ForegroundColor DarkGray; $p.Kill() } } catch { }
    }
    Start-Sleep -Milliseconds 500
    Write-Host '  Closed' -ForegroundColor Green
    return $true
}
