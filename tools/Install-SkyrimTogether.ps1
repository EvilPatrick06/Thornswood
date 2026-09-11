<#
  Install-SkyrimTogether.ps1

  Builds a standalone Skyrim Together install at C:\SkyrimTogether.

  Your own Steam copy of Skyrim is only ever READ. Nothing in it is changed,
  renamed or deleted, so whatever you already play - Keizaal Online included -
  keeps working exactly as it does now.
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\SkyrimTogether',
    [string]$SteamGamePath,
    [switch]$SkipDowngrade,
    [switch]$MovePayload
)

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

foreach ($n in 'SkyrimSE', 'skse64_loader', 'SkyrimTogether') {
    if (Get-Process -Name $n -EA SilentlyContinue) { Die "$n is running. Close it and run this again." }
}

# ------------------------------------------------------------- space
$needGB = 22
$dl = (Split-Path -Qualifier $Root) -replace ':', ''
$freeGB = [math]::Round((Get-PSDrive $dl).Free / 1GB, 1)
Say "  $freeGB GB free on $dl`:"
if ($freeGB -lt $needGB) { Die "You need about $needGB GB free on $dl`:. Free some space, or run this with -Root ""D:\SkyrimTogether""." }

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

if ((Get-ExeBytes) -ne $TARGET_EXE_BYTES -and -not $SkipDowngrade) {
    Head 'Setting the copy to 1.6.1170'
    Say '  Your Steam copy is a newer build. The server runs 1.6.1170, so this copy has to match.'
    Say '  Steam downloads the older files under your own account. Your installed game is not touched.' 'DarkGray'

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

    if ((Get-ExeBytes) -ne $TARGET_EXE_BYTES) { Die "The copy is still not 1.6.1170 (SkyrimSE.exe is $(Get-ExeBytes) bytes)." }
    Say '  1.6.1170' 'Green'
} else {
    Say "  Already 1.6.1170" 'Green'
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

foreach ($f in 'SkyrimTogether.exe', 'config.json') {
    $s = Join-Path $Here $f
    if (Test-Path $s) { Copy-Item $s $(if ($f -eq 'config.json') { $Root } else { $LaunchDir }) -Force }
}

$lexe = Join-Path $LaunchDir 'SkyrimTogether.exe'
if (Test-Path $lexe) {
    $ws = New-Object -ComObject WScript.Shell
    foreach ($dest in @([Environment]::GetFolderPath('Desktop'), $Root)) {
        $sc = $ws.CreateShortcut((Join-Path $dest 'Skyrim Together.lnk'))
        $sc.TargetPath       = $lexe
        $sc.WorkingDirectory = $LaunchDir
        $sc.IconLocation     = ($lexe + ',0')
        $sc.Description      = 'Skyrim Together'
        $sc.Save()
    }
    Say '  Shortcut on your desktop' 'Green'
} else {
    Say '  SkyrimTogether.exe was not in the package.' 'Yellow'
}

# ------------------------------------------------------------- verify
Head 'Checking'
$checks = [ordered]@{
    'Game 1.6.1170'    = ((Get-ExeBytes) -eq $TARGET_EXE_BYTES)
    'Script Extender'  = (Test-Path (Join-Path $GameDir 'skse64_1_6_1170.dll'))
    'Skyrim Together'  = (Test-Path (Join-Path $GameDir 'Data\SkyrimTogetherReborn\SkyrimTogether.exe'))
    'Address library'  = (Test-Path (Join-Path $GameDir 'Data\SKSE\Plugins\versionlib-1-6-1170-0.bin'))
    'Load order'       = (Test-Path (Join-Path $pLocalAD 'plugins.txt'))
    'Launcher'         = (Test-Path (Join-Path $LaunchDir 'SkyrimTogether.exe'))
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
    Say 'Open "Skyrim Together" on your desktop and press PLAY.' 'White'
    Say 'Make a character named after yourself, save once, then connect.' 'Gray'
    Write-Host ''
    Say 'Your Steam copy of Skyrim was not modified.' 'DarkGray'
}
Write-Host ''
[void](Read-Host 'Enter to close')
