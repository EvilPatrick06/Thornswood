<#
  Move-Install.ps1

  Moves the build off the old name. Run it once.

      C:\SkyrimTogether            ->  C:\Thornswood
      C:\Thornswood\skymp          ->  C:\Thornswood-Dev\skymp
      C:\Thornswood\_payload       ->  C:\Thornswood-Dev\_payload
      C:\Thornswood\*-server.zip   ->  C:\Thornswood-Dev\

  The dev half moves out first, so the install root ends up holding nothing but
  the game. That matters: Uninstall deletes the install root, and a skymp
  checkout sitting inside it would go with it.

  Two things have to happen before anything moves. Skyrim's settings and saves
  folders are redirected into the build while you play, and a junction left
  pointing at a folder that is no longer there is a folder Windows will happily
  recreate as an empty real one, losing the redirect. And the game holds files
  in the build open. Both are checked.

  Nothing is deleted. Everything is moved, and -WhatIf shows the whole plan
  without touching anything.
#>
[CmdletBinding()]
param(
    [string]$OldRoot = 'C:\SkyrimTogether',
    [string]$NewRoot = 'C:\Thornswood',
    [string]$DevRoot = 'C:\Thornswood-Dev',
    [switch]$WhatIf,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Good($m) { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Plan($m) { Write-Host "  would  $m" -ForegroundColor Yellow }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

Write-Host ''
Write-Host '  THORNSWOOD  -  move the install' -ForegroundColor White
if ($WhatIf) { Say '  nothing will be changed, this is the plan only' 'Yellow' }

# ------------------------------------------------------------- nothing open --
foreach ($n in 'SkyrimSE', 'skse64_loader', 'Thornswood', 'SkyrimTogether') {
    if (Get-Process -Name $n -ErrorAction SilentlyContinue) {
        Die "$n is running. Close the game and the launcher first, or files in the build cannot be moved."
    }
}
Good 'nothing is holding the build open'

# --------------------------------------------------------- redirects first ---
# Swap points the Windows folders at the build with junctions and puts them back
# when the game exits. One left behind now would point into a folder that is
# about to stop existing.
function Is-Link([string]$p) {
    try {
        $i = Get-Item -LiteralPath $p -Force -ErrorAction Stop
        return [bool]($i.Attributes -band [IO.FileAttributes]::ReparsePoint)
    } catch { return $false }
}

# GetFolderPath comes back empty when Windows has no such folder registered,
# and Join-Path throws on an empty first argument rather than returning
# nothing, which would take the whole move down before it started.
function Under([string]$base, [string]$rest) {
    if ([string]::IsNullOrWhiteSpace($base)) { return $null }
    return (Join-Path $base $rest)
}
$winMyGames = Under ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Skyrim Special Edition'
$winLocalAD = Under $env:LOCALAPPDATA 'Skyrim Special Edition'
$links = @($winMyGames, $winLocalAD) | Where-Object { $_ -and (Is-Link $_) }

if ($links.Count) {
    Head 'Redirects left over from a session'
    foreach ($l in $links) {
        if ($WhatIf) { Plan "remove the junction at $l" ; continue }
        try {
            [IO.Directory]::Delete($l)
            Good "put back $l"
        } catch {
            Die "Could not remove the junction at $l. Open the launcher, Settings, Maintenance, Restore, close it again, and run this once more."
        }
    }
}

# ------------------------------------------------------------- the dev half --
Head 'Moving the dev files out of the way'
$devItems = @('skymp', '_payload', 'build-release.log') +
            @(Get-ChildItem -LiteralPath $NewRoot -Filter '*.zip' -File -ErrorAction SilentlyContinue |
              ForEach-Object { $_.Name })
$movedDev = 0
foreach ($name in ($devItems | Select-Object -Unique)) {
    $src = Join-Path $NewRoot $name
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dst = Join-Path $DevRoot $name
    if ($WhatIf) { Plan "$src  ->  $dst"; $movedDev++; continue }
    if (-not (Test-Path -LiteralPath $DevRoot)) { New-Item -ItemType Directory -Path $DevRoot -Force | Out-Null }
    if (Test-Path -LiteralPath $dst) { Die "$dst is already there. Move or rename it and run this again." }
    Move-Item -LiteralPath $src -Destination $dst -Force
    Good "$name  ->  $DevRoot"
    $movedDev++
}
if ($movedDev -eq 0) { Say '  nothing to move, the dev files are already out' 'DarkGray' }

# ------------------------------------------------------------- the install ---
Head 'Moving the build'
if (-not (Test-Path -LiteralPath $OldRoot)) {
    Say "  $OldRoot is not there, so the build has already moved" 'DarkGray'
}
else {
    $items = @(Get-ChildItem -LiteralPath $OldRoot -Force)
    if ($WhatIf) {
        foreach ($i in $items) { Plan "$($i.FullName)  ->  $(Join-Path $NewRoot $i.Name)" }
    }
    else {
        if (-not (Test-Path -LiteralPath $NewRoot)) { New-Item -ItemType Directory -Path $NewRoot -Force | Out-Null }
        foreach ($i in $items) {
            $dst = Join-Path $NewRoot $i.Name
            if (Test-Path -LiteralPath $dst) { Die "$dst is already there. This looks like a half finished move: sort that folder out by hand first." }
            Move-Item -LiteralPath $i.FullName -Destination $dst -Force
            Good $i.Name
        }
        # Only when it is genuinely empty. Anything still in there is something
        # this script did not expect, and deleting it unseen is not on.
        if (-not @(Get-ChildItem -LiteralPath $OldRoot -Force).Count) {
            Remove-Item -LiteralPath $OldRoot -Force
            Good "removed the empty $OldRoot"
        }
        else {
            Say "  $OldRoot still has something in it, so it was left alone" 'Yellow'
        }
    }
}

# ---------------------------------------------------------------- shortcut ---
# The launcher repoints this itself every time it starts, but not until it has
# been started, and the shortcut is how it gets started.
Head 'Shortcut'
$exe = @('Thornswood.exe', 'SkyrimTogether.exe') |
       ForEach-Object { Join-Path $NewRoot "Launcher\$_" } |
       Where-Object { Test-Path -LiteralPath $_ } |
       Select-Object -First 1

if (-not $exe) { Say '  no launcher found to point at, skipped' 'Yellow' }
else {
    $dirs = @([Environment]::GetFolderPath('Desktop'),
              (Under $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')) |
            Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($dir in $dirs) {
        foreach ($name in 'Thornswood.lnk', 'Skyrim Together.lnk') {
            $lnk = Join-Path $dir $name
            if (-not (Test-Path -LiteralPath $lnk)) { continue }
            if ($WhatIf) { Plan "point $lnk at $exe"; continue }
            try {
                $sh = New-Object -ComObject WScript.Shell
                $s = $sh.CreateShortcut($lnk)
                $s.TargetPath = $exe
                $s.WorkingDirectory = Split-Path $exe -Parent
                $s.Save()
                Good "$name now points at $exe"
            } catch { Say "  could not update $lnk" 'Yellow' }
        }
    }
}

# ----------------------------------------------------------------- finish ----
Head 'Done'
if ($WhatIf) {
    Say '  that was the plan. Run it again without -WhatIf to do it.' 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

Say "  game      $NewRoot" 'Green'
Say "  dev       $DevRoot" 'Green'
Write-Host ''
Say 'One thing left. The server load order holds absolute paths to the old' 'Yellow'
Say 'folder, so it has to be rebuilt before anyone connects:' 'Yellow'
Write-Host ''
Say '  .\Install-Thornswood.ps1 -Only gamemode,check' 'Yellow'
Write-Host ''
Say 'Then, if the server runs on the VPS, push it up again:' 'DarkGray'
Say '  .\Publish-Server.ps1' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
