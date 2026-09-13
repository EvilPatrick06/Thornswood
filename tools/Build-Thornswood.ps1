<#
  Build-Thornswood.ps1
  Makes a standalone, self-contained copy of your modded Skyrim at C:\Thornswood.
  Steam's copy is only ever read from. Nothing in it is changed.

  After this runs you play from C:\Thornswood and never touch Steam again.
  Vortex keeps managing the Steam folder as your authoring copy; re-run this
  script with -Sync any time you change mods there.
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$Root = 'C:\Thornswood',
    [switch]$Sync,
    [switch]$Fresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$EXPECTED_EXE_BYTES = 37157144   # 1.6.1170
$AE_EXE_BYTES       = 37910440   # 1.7.104 - the version we never want

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; [void](Read-Host 'Enter to exit'); exit 1 }

# ---------------------------------------------------------------- locate source
function Get-SteamRoot {
    $c = @()
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        if (Test-Path $k) {
            $i = Get-ItemProperty $k
            foreach ($n in 'SteamPath', 'InstallPath') { if ($i.PSObject.Properties[$n]) { $c += $i.$n } }
        }
    }
    $c += "${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam"
    $c | Where-Object { $_ -and (Test-Path (Join-Path $_ 'steam.exe')) } | Select-Object -First 1
}

function Find-Skyrim {
    $steam = Get-SteamRoot
    if (-not $steam) { return $null }
    $libs = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($line in Get-Content -LiteralPath $vdf) {
            if ($line -match '^\s*"path"\s+"(.+)"') {
                $p = $Matches[1] -replace '\\\\', '\'
                if (Test-Path $p) { $libs += $p }
            }
        }
    }
    foreach ($l in ($libs | Select-Object -Unique)) {
        $g = Join-Path $l 'steamapps\common\Skyrim Special Edition'
        if (Test-Path (Join-Path $g 'SkyrimSE.exe')) { return (Resolve-Path $g).Path }
    }
    $null
}

Head 'Skyrim Together - build'

if (-not $Source) { $Source = Find-Skyrim }
if (-not $Source -or -not (Test-Path (Join-Path $Source 'SkyrimSE.exe'))) {
    Die "Could not find your Skyrim install. Re-run with -Source ""D:\path\to\Skyrim Special Edition"""
}
$Source = (Resolve-Path $Source).Path
Say "Source : $Source"
Say "Target : $Root"

$GameDir    = Join-Path $Root 'Game'
$ProfileDir = Join-Path $Root 'Profile'
$LaunchDir  = Join-Path $Root 'Launcher'

if ($Source -like "$Root*") { Die 'Source and target are the same folder.' }

# ---------------------------------------------------------------- preflight
Head 'Checks'

$exe = Get-Item (Join-Path $Source 'SkyrimSE.exe')
if ($exe.Length -eq $AE_EXE_BYTES) { Die 'Your Steam copy is back on 1.7.104. Downgrade to 1.6.1170 before building.' }
if ($exe.Length -ne $EXPECTED_EXE_BYTES) {
    Say "  SkyrimSE.exe is $($exe.Length) bytes, expected $EXPECTED_EXE_BYTES." 'Yellow'
    if ((Read-Host '  Continue anyway? (y/N)') -ne 'y') { exit 1 }
} else { Say "  SkyrimSE.exe 1.6.1170" 'Green' }

foreach ($n in 'SkyrimSE', 'skse64_loader', 'SkyrimTogether', 'Vortex') {
    if (Get-Process -Name $n -ErrorAction SilentlyContinue) { Die "$n is running. Close it and re-run." }
}
Say '  Nothing holding the files open' 'Green'

# size + free space
Say '  Measuring the source (this takes a minute)...'
$srcBytes = (Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -notlike '*\_DowngraderBackups\*' -and $_.FullName -notlike '*\src\*' } |
             Measure-Object -Property Length -Sum).Sum
if (-not $srcBytes) { Die 'Could not measure the source folder.' }
$needGB = [math]::Round($srcBytes / 1GB, 1)
$drive  = (Split-Path -Qualifier $Root)
$freeGB = [math]::Round((Get-PSDrive ($drive -replace ':', '')).Free / 1GB, 1)
Say "  Need about $needGB GB, $freeGB GB free on $drive"
if ($freeGB -lt ($needGB + 5)) { Die "Not enough room on $drive. Free up space or re-run with -Root ""D:\SkyrimTogether""" }

# ---------------------------------------------------------------- copy
Head 'Copying the game'

$null = New-Item -ItemType Directory -Force -Path $GameDir, $ProfileDir, $LaunchDir

# Folders and files that are authoring clutter, not part of a playable build.
$xd = @(
    (Join-Path $Source '_DowngraderBackups')
    (Join-Path $Source 'src')
    (Join-Path $Source 'Data\Nemesis_Engine')
    (Join-Path $Source 'Data\CalienteTools')
    (Join-Path $Source 'Data\DialogueViews')
    (Join-Path $Source 'Data\Source')
    (Join-Path $Source 'Data\Docs')
    (Join-Path $Source 'Data\docs and screenshots')
)
$xf = @('*.vortex_backup', 'vortex.deployment*.json', '*.log', 'Thumbs.db', 'desktop.ini')

if ($Fresh -and (Test-Path $GameDir)) {
    Say '  -Fresh given, clearing the old build first...' 'Yellow'
    Remove-Item -LiteralPath $GameDir -Recurse -Force
    $null = New-Item -ItemType Directory -Force -Path $GameDir
}

$rcArgs = @($Source, $GameDir, '/E', '/XJ', '/R:1', '/W:1', '/MT:16', '/NDL', '/NP', '/NJH')
$rcArgs += '/XD'; $rcArgs += $xd
$rcArgs += '/XF'; $rcArgs += $xf

Say '  About 25 GB. File names scroll past so you can see it working.' 'DarkGray'
$t0 = Get-Date
& robocopy @rcArgs
$rc = $LASTEXITCODE
if ($rc -ge 8) { Die "robocopy failed with code $rc" }
Say ("  Copied in {0:n0} seconds" -f ((Get-Date) - $t0).TotalSeconds) 'Green'

# A stray copy of the address library was made while debugging. It must not
# reach the build or the friend package.
$stray = Join-Path $GameDir 'Data\SkyrimTogetherReborn\Data'
if (Test-Path $stray) { Remove-Item $stray -Recurse -Force; Say '  Removed the debug copy of the address library' 'DarkGray' }

# Nemesis output has to survive even though the engine folder does not.
$nemOut = Join-Path $Source 'Data\meshes\actors\character\behaviors'
if (Test-Path $nemOut) {
    $hk = @(Get-ChildItem -LiteralPath $nemOut -Filter '*.hkx' -File -ErrorAction SilentlyContinue)
    Say "  $($hk.Count) patched behavior files carried over" 'Green'
    if ($hk.Count -lt 3) { Say '  That looks thin. Did Nemesis finish?' 'Yellow' }
}

# ---------------------------------------------------------------- profile
Head 'Profile'

$docs     = [Environment]::GetFolderPath('MyDocuments')
$myGames  = Join-Path $docs 'My Games\Skyrim Special Edition'
$localAD  = Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition'
$pMyGames = Join-Path $ProfileDir 'MyGames'
$pLocalAD = Join-Path $ProfileDir 'LocalAppData'
$null = New-Item -ItemType Directory -Force -Path $pMyGames, $pLocalAD, (Join-Path $pMyGames 'Saves')

if (Test-Path $myGames) {
    foreach ($f in 'Skyrim.ini', 'SkyrimPrefs.ini', 'SkyrimCustom.ini') {
        $s = Join-Path $myGames $f
        if (Test-Path $s) { Copy-Item $s $pMyGames -Force; Say "  $f" 'Green' }
    }
} else { Say '  No My Games folder found. Launch the game once from Steam first.' 'Yellow' }

foreach ($f in 'plugins.txt', 'loadorder.txt') {
    $s = Join-Path $localAD $f
    if (Test-Path $s) {
        Copy-Item $s $pLocalAD -Force
        $n = @(Get-Content $s | Where-Object { $_ -match '^\*' }).Count
        Say ("  $f" + $(if ($n) { " - $n enabled" } else { '' })) 'Green'
    } else { Say "  $f missing" 'Yellow' }
}

# The shipped originals, so the launcher's Repair button has something to restore.
$golden = Join-Path $ProfileDir 'Default'
$null = New-Item -ItemType Directory -Force -Path $golden
Copy-Item (Join-Path $pMyGames '*.ini') $golden -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $pLocalAD '*.txt') $golden -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- config
$cfgPath = Join-Path $Root 'config.json'
if (-not (Test-Path $cfgPath)) {
    [ordered]@{
        ServerAddress    = '192.135.119.166'
        ServerPort       = '25565'
        ExpectedExeBytes = $EXPECTED_EXE_BYTES
    } | ConvertTo-Json | Set-Content $cfgPath -Encoding UTF8
    Say "  config.json written" 'Green'
}

# ---------------------------------------------------------------- launcher
Head 'Launcher'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$lsrc = Join-Path $here 'SkyrimTogether-Launcher.ps1'
if (Test-Path $lsrc) {
    Copy-Item $lsrc $LaunchDir -Force
    Say '  Installed' 'Green'
} elseif (Test-Path (Join-Path $LaunchDir 'SkyrimTogether-Launcher.ps1')) {
    Say '  Already installed' 'Green'
} else {
    Say '  SkyrimTogether-Launcher.ps1 was not next to this script. Copy it into the Launcher folder.' 'Yellow'
}

$lps = Join-Path $LaunchDir 'SkyrimTogether-Launcher.ps1'
if (Test-Path $lps) {
    $ws = New-Object -ComObject WScript.Shell
    foreach ($dest in @([Environment]::GetFolderPath('Desktop'), $Root)) {
        $sc = $ws.CreateShortcut((Join-Path $dest 'Skyrim Together.lnk'))
        $sc.TargetPath       = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$lps"""
        $sc.WorkingDirectory = $LaunchDir
        $sc.IconLocation     = (Join-Path $GameDir 'SkyrimSE.exe') + ',0'
        $sc.Description      = 'Launch the Skyrim Together build'
        $sc.Save()
    }
    Say '  Shortcut on your desktop' 'Green'
}

# ---------------------------------------------------------------- verify
Head 'Result'

$checks = [ordered]@{
    'SkyrimSE.exe'      = Join-Path $GameDir 'SkyrimSE.exe'
    'skse64_loader.exe' = Join-Path $GameDir 'skse64_loader.exe'
    'SKSE runtime dll'  = Join-Path $GameDir 'skse64_1_6_1170.dll'
    'Preloader'         = Join-Path $GameDir 'd3dx9_42.dll'
    'STR client'        = Join-Path $GameDir 'Data\SkyrimTogetherReborn\SkyrimTogether.exe'
    'SKSE plugins'      = Join-Path $GameDir 'Data\SKSE\Plugins'
    'plugins.txt'       = Join-Path $pLocalAD 'plugins.txt'
    'loadorder.txt'     = Join-Path $pLocalAD 'loadorder.txt'
}
$bad = 0
foreach ($k in $checks.Keys) {
    if (Test-Path $checks[$k]) { Say ("  [ok]   $k") 'Green' }
    else { Say ("  [MISS] $k") 'Red'; $bad++ }
}

$built = [math]::Round((Get-ChildItem -LiteralPath $GameDir -Recurse -File -Force | Measure-Object Length -Sum).Sum / 1GB, 1)
Write-Host ''
Say "Build is $built GB at $GameDir" 'Cyan'
if ($bad) { Say "$bad things missing. Tell Claude." 'Red' } else { Say 'Launch it from the Skyrim Together shortcut on your desktop.' 'Green' }
Write-Host ''
[void](Read-Host 'Enter to close')
