<#
  Setup-Thornswood.ps1

  Builds a standalone Thornswood install at C:\Thornswood.

  Your own Steam copy of Skyrim is only ever READ. Nothing in it is changed,
  renamed or deleted, so whatever you already play - Keizaal Online included -
  keeps working exactly as it does now.
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Thornswood',
    [string]$SteamGamePath,
    [switch]$SkipDowngrade,
    [switch]$MovePayload
)


# The launcher was SkyrimTogether.exe and is Thornswood.exe now. It replaces
# itself in place when it updates rather than being reinstalled, so an install
# made before the rename still carries the old name and both have to be looked
# for, newest first.
function Get-LauncherExe([string]$dir) {
    foreach ($n in 'Thornswood.exe', 'SkyrimTogether.exe') {
        $p = Join-Path $dir $n
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return (Join-Path $dir 'Thornswood.exe')
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TARGET_EXE_BYTES = 37157144          # 1.6.1170
$AppId  = '489830'
$Depots = [ordered]@{
    '489831' = '8442952117333549665'
    '489832' = '8042843504692938467'
    '489833' = '1914580699073641964'
}

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; [void](Read-Host 'Enter to exit'); exit 1 }

$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload = Join-Path $Here 'payload'
$GameDir    = Join-Path $Root 'Game'
$ProfileDir = Join-Path $Root 'Profile'
$LaunchDir  = Join-Path $Root 'Launcher'

Write-Host ''
Write-Host '  SKYRIM TOGETHER' -ForegroundColor White
Write-Host '  Standalone installer' -ForegroundColor DarkGray

if (-not (Test-Path $Payload)) { Die "The 'payload' folder is missing. If you extracted this by hand, extract the whole archive and run Install.bat from the extracted folder." }

# ------------------------------------------------------------- find steam
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
function Get-Libraries($steam) {
    $r = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($l in Get-Content -LiteralPath $vdf) {
            if ($l -match '^\s*"path"\s+"(.+)"') { $p = $Matches[1] -replace '\\\\', '\'; if (Test-Path $p) { $r += $p } }
        }
    }
    $r | Select-Object -Unique
}

Head 'Finding Skyrim'
$steamRoot = Get-SteamRoot
if (-not $steamRoot) { Die 'Steam is not installed on this PC.' }
$libs = @(Get-Libraries $steamRoot)

if (-not $SteamGamePath) {
    foreach ($l in $libs) {
        $g = Join-Path $l 'steamapps\common\Skyrim Special Edition'
        if (Test-Path (Join-Path $g 'SkyrimSE.exe')) { $SteamGamePath = $g; break }
    }
}
if (-not $SteamGamePath) { Die 'Skyrim Special Edition was not found in any Steam library. Install it first.' }
$SteamGamePath = (Resolve-Path $SteamGamePath).Path
Say "  $SteamGamePath" 'Green'
Say '  This folder will be read from only.' 'DarkGray'

# Skyrim does not always let go. A crash, an Alt-F4, or one of the multiplayer
# client's browser helpers leaves a process behind with no window on screen,
# so telling someone to close a game they cannot see is a dead end. Close it
# here instead. This runs standalone inside the payload, so it does not share
# the repo's Close-Launcher.ps1 and carries its own copy.
function Stop-AnySkyrim {
    $found = @()
    foreach ($n in 'SkyrimSE', 'skse64_loader', 'SkyrimTogether') {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) { $found += $p }
    }
    if ($found.Count -eq 0) { return $true }

    $names = ($found | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
    Say "  Skyrim is still open ($names). Closing it." 'Yellow'
    foreach ($p in $found) { try { $null = $p.CloseMainWindow() } catch { } }
    for ($i = 0; $i -lt 24; $i++) {
        Start-Sleep -Milliseconds 250
        if (-not ($found | Where-Object { -not $_.HasExited })) { break }
    }
    foreach ($p in $found) { try { if (-not $p.HasExited) { $p.Kill() } } catch { } }

    # A killed process can sit in the table for a moment after it is gone, so
    # this waits rather than giving up on the first look.
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Milliseconds 250
        $left = @()
        foreach ($n in 'SkyrimSE', 'skse64_loader', 'SkyrimTogether') {
            foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) { $left += $p }
        }
        if ($left.Count -eq 0) { Say '  Closed.' 'Green'; return $true }
    }
    return $false
}

if (-not (Stop-AnySkyrim)) {
    Die 'Skyrim would not close. Restart your PC, then run this again.'
}

# ------------------------------------------------------------- space
# The setup program unpacks onto this same drive so the final step is a move
# rather than another copy, which makes the peak the unpacked mods plus the
# copy of Skyrim, both at once.
$needGB = 32
$dl = (Split-Path -Qualifier $Root) -replace ':', ''
$freeGB = [math]::Round((Get-PSDrive $dl).Free / 1GB, 1)
Say "  Installing to $Root"
Say "  $freeGB GB free on $dl`:"
if ($freeGB -lt $needGB) { Die "You need about $needGB GB free on $dl`:. Close this, run the setup program again and pick a different drive." }

# ------------------------------------------------------------- vanilla copy
Head 'Copying the base game'
$null = New-Item -ItemType Directory -Force -Path $GameDir, (Join-Path $GameDir 'Data'), $ProfileDir, $LaunchDir

$rootFiles = @('SkyrimSE.exe', 'SkyrimSELauncher.exe', 'steam_api64.dll', 'bink2w64.dll',
               'Skyrim_Default.ini', 'High.ini', 'Low.ini', 'Medium.ini', 'Ultra.ini',
               'Skyrim.ccc', 'installscript.vdf')
foreach ($f in $rootFiles) {
    $s = Join-Path $SteamGamePath $f
    if (Test-Path $s) { Copy-Item $s $GameDir -Force }
}
Set-Content (Join-Path $GameDir 'steam_appid.txt') $AppId -NoNewline -Encoding ASCII

$dataSrc = Join-Path $SteamGamePath 'Data'
$dataDst = Join-Path $GameDir 'Data'
$want = @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm', '_ResourcePack.esl', '_ResourcePack.bsa')
foreach ($f in $want) {
    $s = Join-Path $dataSrc $f
    if (Test-Path $s) { Copy-Item $s $dataDst -Force; Say "  $f" 'DarkGray' }
}
Say '  Archives. This is the slow part, about 15 GB.'
& robocopy $dataSrc $dataDst 'Skyrim - *.bsa' /R:1 /W:1 /MT:8 /NDL /NP /NJH /NJS
if (Test-Path (Join-Path $dataSrc 'Video')) {
    & robocopy (Join-Path $dataSrc 'Video') (Join-Path $dataDst 'Video') /E /R:1 /W:1 /NFL /NDL /NP /NJH /NJS | Out-Null
}
$bsaCount = @(Get-ChildItem $dataDst -Filter '*.bsa' -File -EA SilentlyContinue).Count
if ($bsaCount -lt 15) { Die "Only $bsaCount archives copied. Your Steam copy looks incomplete - verify it in Steam first, then run this again." }
Say "  $bsaCount archives, 5 masters" 'Green'

# ------------------------------------------------------------- downgrade
function Get-ExeBytes { $p = Join-Path $GameDir 'SkyrimSE.exe'; if (Test-Path $p) { (Get-Item $p).Length } else { 0 } }

# Steam hands over the 1.6.1170 files under the player's own account and writes
# them into Steam's download folder, so the game they have installed is left
# alone. It is the fix for a copy that is too new and for one that another mod
# setup has patched, so it lives in a function and gets called for both.
function Invoke-DepotRepair($reason) {
    Head 'Getting clean 1.6.1170 files from Steam'
    Say "  $reason"
    Say '  Steam downloads them under your own account. Your installed game is not touched.' 'DarkGray'

    $content = Join-Path $steamRoot 'steamapps\content'
    function Resolve-Depot($id) {
        foreach ($c in @((Join-Path $content "app_$AppId\depot_$id"), (Join-Path $content "$AppId\$id"),
                         (Join-Path $content "depot_$id"), (Join-Path $content $id))) {
            if (Test-Path $c) { return $c }
        }
        $null
    }

    $missing = @($Depots.Keys | Where-Object { -not (Resolve-Depot $_) })
    if ($missing.Count) {
        $cmds = ($Depots.GetEnumerator() | ForEach-Object { "download_depot $AppId $($_.Key) $($_.Value)" }) -join "`r`n"
        Write-Host ''
        Say '  Run these three in the Steam console, ONE AT A TIME, waiting for each to say Done:' 'Yellow'
        Write-Host ''
        $Depots.GetEnumerator() | ForEach-Object { Write-Host "    download_depot $AppId $($_.Key) $($_.Value)" -ForegroundColor White }
        Write-Host ''
        try { Set-Clipboard $cmds; Say '  All three are on your clipboard.' 'DarkGray' } catch { }
        Say '  There is no progress bar. It just prints Done when it finishes.' 'DarkGray'
        Start-Process 'steam://open/console'
        Say '  If no console tab opens, press Win+R and run:  steam://open/console' 'DarkGray'
        Write-Host ''
        [void](Read-Host '  Press Enter here once all three have finished')
        $missing = @($Depots.Keys | Where-Object { -not (Resolve-Depot $_) })
        if ($missing.Count) { Die ("These depots still are not downloaded: " + ($missing -join ', ')) }
    }

    foreach ($id in $Depots.Keys) {
        $d = Resolve-Depot $id
        Say "  Applying depot $id..."
        & robocopy $d $GameDir /E /R:1 /W:1 /MT:8 /NFL /NDL /NP /NJH /NJS | Out-Null
    }

    Say '  Applied' 'Green'
}

if ((Get-ExeBytes) -ne $TARGET_EXE_BYTES -and -not $SkipDowngrade) {
    Invoke-DepotRepair 'Your Steam copy is a newer build. The server runs 1.6.1170, so this copy has to match.'
    if ((Get-ExeBytes) -ne $TARGET_EXE_BYTES) { Die "The copy is still not 1.6.1170 (SkyrimSE.exe is $(Get-ExeBytes) bytes)." }
    Say '  1.6.1170' 'Green'
} else {
    Say "  Already 1.6.1170" 'Green'
}

# ------------------------------------------------------------- tamper check
# The size check above only proves the build number. Multiplayer setups like
# Keizaal Online and Daedric Online install into the Steam folder, and a patched
# loader of exactly the right size would sail straight past it and end up in
# this copy. So the three files that get patched are matched by content against
# the ones this package was built from.
# Get-FileHash lives in a module that is not always on PSModulePath, and a
# script started with -NoProfile can find itself without it. .NET is always
# there, so the hashing goes straight to it.
function Get-Sha256([string]$path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fs = [IO.File]::OpenRead($path)
        try { return ([BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-', '').ToLower() }
        finally { $fs.Close() }
    }
    finally { $sha.Dispose() }
}

$vanillaList = Join-Path $Here 'vanilla.json'
if (Test-Path $vanillaList) {
    Head 'Checking the files that came from Steam'
    $want = Get-Content $vanillaList -Raw | ConvertFrom-Json

    function Get-Mismatched($doc) {
        $out = @()
        foreach ($prop in $doc.PSObject.Properties) {
            $f = Join-Path $GameDir $prop.Name
            if (-not (Test-Path $f)) { continue }
            if ((Get-Sha256 $f) -ne ([string]$prop.Value).ToLower()) { $out += $prop.Name }
        }
        return $out
    }

    $off = @(Get-Mismatched $want)
    if ($off -contains 'SkyrimSE.exe' -and -not $SkipDowngrade) {
        Invoke-DepotRepair 'Your Steam copy of Skyrim has been modified by another mod setup, so the game itself is being replaced with clean files.'
        $off = @(Get-Mismatched $want)
    }

    if ($off -contains 'SkyrimSE.exe') {
        Die 'SkyrimSE.exe does not match a clean 1.6.1170 build even after the depot download. Send Gavin a screenshot of this.'
    }
    if ($off.Count) {
        Say ("  " + ($off -join ', ') + " differ from the ones this package was built with.") 'Yellow'
        Say '  Those are Steam support files rather than game data, so this carries on.' 'DarkGray'
        Say '  If the game refuses to start, run Steam, verify Skyrim, and install this again.' 'DarkGray'
    } else {
        Say '  Clean' 'Green'
    }
}

# ------------------------------------------------------------- creation club
Head 'Removing Creation Club content'
$ccGone = 0
foreach ($f in (Get-ChildItem $dataDst -Filter 'cc*' -File -EA SilentlyContinue)) {
    if ($f.Extension -in '.esl', '.esm', '.esp', '.bsa') { Remove-Item $f.FullName -Force; $ccGone++ }
}
Say "  $ccGone files removed from the copy" 'Green'

# ------------------------------------------------------------- payload
Head 'Installing the mods'
Say '  Several thousand files. Names scroll past so you can see it working.'
if ($MovePayload) {
    # Unpacked into a scratch folder by the setup program. Moving instead of
    # copying keeps peak disk use down and leaves nothing behind.
    & robocopy $Payload $GameDir /E /MOVE /R:1 /W:1 /MT:16 /NDL /NP /NJH /NJS
} else {
    & robocopy $Payload $GameDir /E /R:1 /W:1 /MT:16 /NDL /NP /NJH /NJS
}
if ($LASTEXITCODE -ge 8) { Die "robocopy failed with code $LASTEXITCODE" }
Say '  Done' 'Green'

# ------------------------------------------------------------- profile
Head 'Settings'
$pMyGames = Join-Path $ProfileDir 'MyGames'
$pLocalAD = Join-Path $ProfileDir 'LocalAppData'
$golden   = Join-Path $ProfileDir 'Default'
$null = New-Item -ItemType Directory -Force -Path $pMyGames, $pLocalAD, $golden, (Join-Path $pMyGames 'Saves')

$src = Join-Path $Here 'profile'
if (Test-Path $src) {
    Copy-Item (Join-Path $src '*') $golden -Force
    Copy-Item (Join-Path $golden '*.ini') $pMyGames -Force -EA SilentlyContinue
    Copy-Item (Join-Path $golden '*.txt') $pLocalAD -Force -EA SilentlyContinue
    $plug = Join-Path $pLocalAD 'plugins.txt'
    $n = if (Test-Path $plug) { @(Get-Content $plug | Where-Object { $_ -match '^\*' }).Count } else { 0 }
    Say "  Load order installed, $n plugins" 'Green'
} else { Say '  No profile folder in the archive.' 'Yellow' }

foreach ($f in 'Thornswood.exe', 'SkyrimTogether.exe', 'config.json') {
    $s = Join-Path $Here $f
    if (Test-Path $s) { Copy-Item $s $(if ($f -eq 'config.json') { $Root } else { $LaunchDir }) -Force }
}

$lexe = Get-LauncherExe $LaunchDir
if (Test-Path $lexe) {
    $ws = New-Object -ComObject WScript.Shell
    foreach ($dest in @([Environment]::GetFolderPath('Desktop'), $Root)) {
        # The old name, tidied away so nobody ends up with two shortcuts to
        # the same launcher after the rename.
        $was = Join-Path $dest 'Skyrim Together.lnk'
        if (Test-Path $was) { Remove-Item $was -Force -ErrorAction SilentlyContinue }

        $sc = $ws.CreateShortcut((Join-Path $dest 'Thornswood.lnk'))
        $sc.TargetPath       = $lexe
        $sc.WorkingDirectory = $LaunchDir
        $sc.IconLocation     = ($lexe + ',0')
        $sc.Description      = 'Thornswood'
        $sc.Save()
    }
    Say '  Shortcut on your desktop' 'Green'

# Windows keeps the bitmap it once drew for a shortcut and goes on showing it
# long after the icon inside the exe changed. Asking Explorer to rebuild that
# cache is the difference between a new icon and an argument about whether the
# build worked.
try {
    $ie4 = Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
    if (Test-Path $ie4) {
        & $ie4 -show 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { & $ie4 -ClearIconCache 2>&1 | Out-Null }
        Say '  Icon cache asked to refresh' 'DarkGray'
    }
} catch { }

} else {
    Say '  Thornswood.exe was not in the package.' 'Yellow'
}

# ------------------------------------------------------------- verify
Head 'Checking'
$checks = [ordered]@{
    'Game 1.6.1170'    = ((Get-ExeBytes) -eq $TARGET_EXE_BYTES)
    'Script Extender'  = (Test-Path (Join-Path $GameDir 'skse64_1_6_1170.dll'))
    'Multiplayer'      = (Test-Path (Join-Path $GameDir 'Data\SkyrimTogetherReborn\SkyrimTogether.exe'))
    'Address library'  = (Test-Path (Join-Path $GameDir 'Data\SKSE\Plugins\versionlib-1-6-1170-0.bin'))
    'Load order'       = (Test-Path (Join-Path $pLocalAD 'plugins.txt'))
    'Launcher'         = (Test-Path (Get-LauncherExe $LaunchDir))
}
$bad = 0
foreach ($k in $checks.Keys) {
    if ($checks[$k]) { Say "  [ok]   $k" 'Green' } else { Say "  [MISS] $k" 'Red'; $bad++ }
}

Write-Host ''
if ($bad) {
    Say "$bad checks failed. Send Gavin a screenshot of this window." 'Red'
} else {
    Say 'Installed.' 'Green'
    Write-Host ''
    Say 'Open "Thornswood" on your desktop and press PLAY.' 'White'
    Say 'Make a character named after yourself, save once, then connect.' 'Gray'
    Write-Host ''
    Say 'Your Steam copy of Skyrim was not modified.' 'DarkGray'
}
Write-Host ''
[void](Read-Host 'Enter to close')
