<#
  Package-Thornswood.ps1
  Turns the built install at C:\Thornswood into the single file your friends run.

  Only your mod content goes in. Every Bethesda file is left out, because the
  installer rebuilds those from each friend's own Steam copy and their own
  Steam depots.
#>
[CmdletBinding()]
param(
    [string]$Root    = 'C:\Thornswood',
    [string]$OutDir  = 'C:\Thornswood\_dist',
    [ValidateRange(0, 9)][int]$Level = 1,
    [switch]$NoArchive,
    [switch]$Plain7z,
    [switch]$ReuseStage,
    [switch]$NoPause
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

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$GameDir    = Join-Path $Root 'Game'
$ProfileDir = Join-Path $Root 'Profile'
$LaunchDir  = Join-Path $Root 'Launcher'
$stage      = Join-Path $OutDir 'stage'

if (-not (Test-Path (Join-Path $GameDir 'SkyrimSE.exe'))) { Die "No build at $GameDir. Run Build-Thornswood.ps1 first." }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Close-Launcher.ps1')

Head 'Packaging'

# A live game rewrites files under Game and Profile while this is listing and
# hashing them, which is how a package ends up half one version.
$null = Stop-Game -Root $Root

# ---- what never ships: Bethesda's own files ------------------------------
$vanillaDataFiles = @(
    'Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm',
    '_ResourcePack.esl', '_ResourcePack.bsa'
)
$vanillaDataPatterns = @('Skyrim - *.bsa', 'cc*.esm', 'cc*.esl', 'cc*.esp', 'cc*.bsa')
$vanillaDataDirs     = @('Video', 'Strings')

$vanillaRootFiles = @(
    'SkyrimSE.exe', 'SkyrimSELauncher.exe', 'steam_api64.dll', 'bink2w64.dll',
    'Skyrim.ccc', 'installscript.vdf', 'Skyrim_Default.ini',
    'High.ini', 'Low.ini', 'Medium.ini', 'Ultra.ini'
)
$vanillaRootDirs = @('_DowngraderBackups', 'Creations', 'Mods', 'Skyrim', 'src')

function Test-Vanilla([string]$rel) {
    $parts = $rel -split '\\'
    $top   = $parts[0]
    if ($vanillaRootDirs -contains $top) { return $true }
    if ($parts.Count -eq 1) { return ($vanillaRootFiles -contains $top) }
    if ($top -ne 'Data') { return $false }
    if ($parts.Count -ge 3 -and ($vanillaDataDirs -contains $parts[1])) { return $true }
    if ($parts.Count -eq 2) {
        $leaf = $parts[1]
        if ($vanillaDataFiles -contains $leaf) { return $true }
        foreach ($p in $vanillaDataPatterns) { if ($leaf -like $p) { return $true } }
    }
    return $false
}

# ---- stage ----------------------------------------------------------------
# The multiplayer client's menu is a Chromium window, and it keeps a browser
# profile beside itself: caches, cookie databases, shader blobs, its own logs.
# All of it is per machine, all of it is rewritten on every launch, and it is
# locked while the client is running. Publishing it churned hundreds of files
# per release, sent one player's browser state to everyone else, and eventually
# failed outright on a file the game still had open.
$runtimeDirs = @(
    'Data\SkyrimTogetherReborn\cache\',
    'Data\SkyrimTogetherReborn\logs\',
    '.sentry-native\'
)
function Test-Runtime([string]$rel) {
    foreach ($d in $runtimeDirs) {
        if ($rel.StartsWith($d, 'OrdinalIgnoreCase')) { return $true }
    }
    return $false
}

Say '  Listing the build...'
$all = @(Get-ChildItem -LiteralPath $GameDir -Recurse -File -Force)
$prefix = $GameDir.TrimEnd('\') + '\'

$ship = @(); $skipBytes = 0; $shipBytes = 0
foreach ($f in $all) {
    $rel = $f.FullName.Substring($prefix.Length)
    if (Test-Vanilla $rel) { $skipBytes += $f.Length; continue }
    if (Test-Runtime $rel) { $skipBytes += $f.Length; continue }
    if ($f.Extension -in '.pdb', '.log') { $skipBytes += $f.Length; continue }
    $ship += [pscustomobject]@{ Rel = $rel; Full = $f.FullName; Len = $f.Length; Time = $f.LastWriteTimeUtc }
    $shipBytes += $f.Length
}
Say ("  {0:n0} files kept ({1:n1} GB), {2:n0} left out ({3:n1} GB of Bethesda files and debug symbols)" -f `
    $ship.Count, ($shipBytes / 1GB), ($all.Count - $ship.Count), ($skipBytes / 1GB)) 'Green'

$payload = Join-Path $stage 'payload'
$reuse = $ReuseStage -and (Test-Path $payload)
if (-not $reuse -and (Test-Path $stage)) { Remove-Item $stage -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $stage, $payload, (Join-Path $stage 'profile')

if ($reuse) {
    # -ReuseStage used to take the old folder as it stood, which quietly shipped
    # yesterday's mod list the moment anything changed. It syncs now instead:
    # same speed when nothing moved, correct when something did.
    Say '  Checking the staged copy against the build...' 'Yellow'
    $have = @{}
    foreach ($f in (Get-ChildItem -LiteralPath $payload -Recurse -File -Force)) {
        $have[$f.FullName.Substring($payload.TrimEnd('\').Length + 1)] = $f
    }

    $new = 0; $changed = 0; $gone = 0
    foreach ($f in $ship) {
        $old = $have[$f.Rel]
        if ($old) {
            $have.Remove($f.Rel)
            # A second of slack, because copying does not preserve ticks exactly.
            if ($old.Length -eq $f.Len -and [math]::Abs(($old.LastWriteTimeUtc - $f.Time).TotalSeconds) -lt 2) { continue }
            $changed++
        } else { $new++ }

        $dest = Join-Path $payload $f.Rel
        $dir  = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
        Copy-Item -LiteralPath $f.Full -Destination $dest -Force
    }

    # Whatever is left in the table is no longer part of the build.
    foreach ($leftover in $have.Values) { Remove-Item -LiteralPath $leftover.FullName -Force -EA SilentlyContinue; $gone++ }

    if ($new -or $changed -or $gone) {
        Say ("  {0:n0} new, {1:n0} changed, {2:n0} removed" -f $new, $changed, $gone) 'Green'
    } else {
        Say '  nothing has changed since the last package' 'Green'
    }
} else {
    Say '  Copying...'
    $n = 0
    foreach ($f in $ship) {
        $dest = Join-Path $payload $f.Rel
        $dir  = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
        Copy-Item -LiteralPath $f.Full -Destination $dest -Force
        $n++
        if ($n % 2000 -eq 0) { Write-Host ("    {0:n0}/{1:n0}" -f $n, $ship.Count) -ForegroundColor DarkGray }
    }
}

$payloadDir = $payload
$shipCount = $ship.Count

# Deep mod paths plus a long staging prefix push past the old Windows path
# limit, which is what "System ERROR: The parameter is incorrect" means here.
$longest = 0
foreach ($f in (Get-ChildItem -LiteralPath $payloadDir -Recurse -File -Force)) {
    if ($f.FullName.Length -gt $longest) { $longest = $f.FullName.Length; $longestPath = $f.FullName }
}
Say "  longest path is $longest characters" $(if ($longest -gt 250) { 'Yellow' } else { 'DarkGray' })
if ($longest -gt 250) { Say "    $longestPath" 'DarkGray' }

# ---- profile + launcher + installer ---------------------------------------
Copy-Item (Join-Path $ProfileDir 'Default\*') (Join-Path $stage 'profile') -Force -ErrorAction SilentlyContinue
$lexe = Get-LauncherExe $LaunchDir
if (Test-Path $lexe) {
    Copy-Item $lexe $stage -Force
    Say '  launcher exe included' 'Green'
} else {
    Say '  Thornswood.exe is not built yet. Run Build-Launcher.ps1 first.' 'Yellow'
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($f in 'Setup-Thornswood.ps1', 'Install.bat', 'Setup.bat', 'READ ME FIRST.txt') {
    $s = Join-Path $here $f
    if (Test-Path $s) { Copy-Item $s $stage -Force } else { Say "  $f missing next to this script" 'Yellow' }
}

$cfgSrc = Join-Path $Root 'config.json'
if (Test-Path $cfgSrc) { Copy-Item $cfgSrc $stage -Force }

$plug = Join-Path $ProfileDir 'Default\plugins.txt'
$manifest = [ordered]@{
    builtAt   = (Get-Date).ToString('u')
    files     = $shipCount
    bytes     = $shipBytes
    plugins   = if (Test-Path $plug) { @(Get-Content $plug | Where-Object { $_ -match '^\*' }).Count } else { 0 }
    exeBytes  = (Get-Item (Join-Path $GameDir 'SkyrimSE.exe')).Length
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $stage 'manifest.json') -Encoding UTF8

# The three files the installer takes from the player's own Steam copy that a
# multiplayer setup might have patched. Their fingerprints ride along so the
# installer can tell a clean Steam copy from a modified one, which a size check
# cannot. Bethesda's archives and masters are left out: nothing patches those,
# and hashing 15 GB on every package would cost more than it is worth.
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

# Nice to have, not load bearing. If it cannot be done, the package still ships
# and the installer simply skips the check rather than losing a long build.
try {
    $fingerprints = [ordered]@{}
    foreach ($f in 'SkyrimSE.exe', 'steam_api64.dll', 'bink2w64.dll') {
        $src = Join-Path $GameDir $f
        if (Test-Path $src) { $fingerprints[$f] = Get-Sha256 $src }
        else { Say "  $f is not in the build, so the installer cannot check it" 'Yellow' }
    }
    $fingerprints | ConvertTo-Json | Set-Content (Join-Path $stage 'vanilla.json') -Encoding UTF8
    Say ("  {0} vanilla fingerprints recorded" -f $fingerprints.Count) 'DarkGray'
}
catch {
    Remove-Item (Join-Path $stage 'vanilla.json') -Force -EA SilentlyContinue
    Say "  Could not fingerprint the Steam files: $($_.Exception.Message)" 'Yellow'
    Say '  Packaging carries on. The installer will skip that check.' 'DarkGray'
}

# ---- archive ---------------------------------------------------------------
if ($NoArchive) {
    Head 'Done'
    Say "Folder ready at $stage" 'Green'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0
}

Head 'Compressing'
$7z = @(
    "$env:ProgramFiles\7-Zip\7z.exe"
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $7z) {
    Say '  7-Zip is not installed. Getting it with winget...' 'Yellow'
    & winget install --id 7zip.7zip -e --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    $7z = @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $7z) { Die "Could not find or install 7-Zip. Re-run with -NoArchive and zip $stage yourself." }

$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$ver = (& $7z | Select-Object -First 2) -join ' '
$ErrorActionPreference = $old
Say "  $7z"
Say "  $ver" 'DarkGray'

$blob = Join-Path $OutDir 'payload.zip'
if (Test-Path $blob) { Remove-Item $blob -Force }
Say '  Most of this content is already compressed, so the level is deliberately low.'
Say '  Around 18 GB in. Expect ten minutes or more.' 'DarkGray'

# A native tool writing a single line to stderr is enough to kill the whole
# script while ErrorActionPreference is Stop, so 7-Zip runs with it relaxed.
function Invoke-7z([string[]]$zargs) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $stage
    try { & $7z @zargs; return $LASTEXITCODE }
    finally { Pop-Location; $ErrorActionPreference = $old }
}

# Zip, not 7z, because the installer unpacks it with what .NET already has and
# never needs 7-Zip present on your friends' machines.
$attempts = @(
    @('a', '-tzip', '-y', "-mx$Level", $blob, '*'),
    @('a', '-tzip', '-y', $blob, '*')
)
$rc = 99
foreach ($try in $attempts) {
    Write-Host ("  > 7z " + ($try -join ' ')) -ForegroundColor DarkGray
    $rc = Invoke-7z $try
    if ($rc -le 1 -and (Test-Path $blob)) { break }
    Say "  that attempt exited with $rc" 'Yellow'
    if (Test-Path $blob) { Remove-Item $blob -Force -EA SilentlyContinue }
}
if (-not (Test-Path $blob)) {
    Say ''
    Say "The staged folder is still at $stage, so nothing is lost." 'Yellow'
    Say 'Re-run with -ReuseStage once this is sorted and it will skip the copy.' 'Yellow'
    Die '7-Zip did not produce the archive.'
}
Say ("  payload.zip is {0:n2} GB" -f ((Get-Item $blob).Length / 1GB)) 'Green'

if ($Plain7z) {
    Head 'Done'
    Say "$blob" 'Green'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 0
}

# ---- two files, side by side ---------------------------------------------
# The payload used to be appended to the stub and shipped as one exe. Windows
# refuses to load an executable this size, so it now travels beside it.
Head 'Building the installer'

$exe = Join-Path $OutDir 'Thornswood-Setup.exe'
$zip = Join-Path $OutDir 'Thornswood-Setup.zip'

if (Test-Path $zip) { Remove-Item $zip -Force }
Move-Item $blob $zip

$stub = @((Join-Path $here 'setup-stub.exe'), (Join-Path $OutDir 'setup-stub.exe')) |
        Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $stub) {
    Head 'Done, but incomplete'
    Say '  setup-stub.exe is missing, so THIS PACKAGE HAS NO INSTALLER.' 'Red'
    Say '  Do not upload it. Anyone who got it would have to unzip it by hand' 'Red'
    Say '  and find Install.bat themselves.' 'Red'
    Write-Host ''
    Say "  $zip" 'DarkGray'
    Say '  Build-Launcher.ps1 compiles the stub. Look at its Setup stub section' 'Yellow'
    Say '  for the compile error, fix it, then run this again.' 'Yellow'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 1
}

if (Test-Path $exe) { Remove-Item $exe -Force }
Copy-Item $stub $exe -Force
Say "  stub: $stub" 'DarkGray'

# ---- prove it before it goes anywhere ------------------------------------
Head 'Checking the installer'
$ok = $true

$exeLen = (Get-Item $exe).Length
$fs = [IO.File]::OpenRead($exe)
try {
    $sig = New-Object byte[] 2
    [void]$fs.Read($sig, 0, 2)
    if ($sig[0] -ne 0x4D -or $sig[1] -ne 0x5A) {
        Say '  the setup program is not a Windows executable' 'Red'; $ok = $false
    } else {
        Say ("  setup program looks right, {0:n0} KB" -f ($exeLen / 1KB)) 'Green'
    }
} finally { $fs.Close() }

# Anything near the loader's limit is the bug this split exists to avoid.
if ($exeLen -gt 100MB) { Say '  the setup program is far bigger than it should be' 'Red'; $ok = $false }

$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$listing = & $7z l $zip 2>&1
$ErrorActionPreference = $old
# Four names, and they are the names this build actually uses.
#
# These were still looking for Install-SkyrimTogether.ps1 and
# SkyrimTogether.exe, from before the rename. The first of those has not
# existed for a long time, so the check failed on every run and reported a
# missing installer script while the installer itself was fine.
#
# The launcher check was worse, because it passed. Somewhere in 22 GB of
# game build there is a leftover SkyrimTogether.exe, and a bare substring
# match found it and called it the launcher. A check that answers yes
# whatever happens is not a check.
#
# So each one is anchored to the end of the line and refused if anything
# path-like sits in front of it. 7-Zip prints the name last, and a file at
# the root of the archive has nothing before it, which is the question
# that was meant all along: is this file at the top of the installer.
$atRoot = {
    param($name)
    $rx = '(?<![\\/\w.-])' + [regex]::Escape($name) + '\s*$'
    $listing | Where-Object { $_ -match $rx }
}
$hasSetup    = & $atRoot 'Setup.bat'
$hasInstall  = & $atRoot 'Setup-Thornswood.ps1'
$hasLauncher = & $atRoot 'Thornswood.exe'
# The payload is a FOLDER in the archive, not a file. The staged copy is
# built at <stage>\payload and zipped with everything else beside it, so
# what is in here is a directory entry named payload plus 34,000 things
# filed under payload\. Asking for payload.zip found neither. Either shape
# counts: the directory entry on its own, or anything inside it.
$hasPayload  = $listing | Where-Object { $_ -match '(?<![\\/\w.-])payload(\\|\s*$)' }
foreach ($pair in @(@('Setup.bat', $hasSetup), @('the installer script', $hasInstall),
                    @('the launcher', $hasLauncher), @('the mod payload', $hasPayload))) {
    if ($pair[1]) { Say "  found $($pair[0])" 'Green' } else { Say "  MISSING $($pair[0])" 'Red'; $ok = $false }
}

# Being in the archive is not the same as being current. The zip is updated in
# place rather than rebuilt, so a file that failed to copy into the stage leaves
# last run's copy sitting there under the right name, and every check above
# still passes. These three are the ones that decide whether a friend ends up
# with this build or the last one, so they get pulled back out and compared
# against what went in.
if ($ok) {
    $check = Join-Path $OutDir 'verify'
    if (Test-Path $check) { Remove-Item $check -Recurse -Force }
    $null = New-Item -ItemType Directory -Force -Path $check

    foreach ($name in 'Setup-Thornswood.ps1', 'Setup.bat', 'Thornswood.exe') {
        $src = Join-Path $stage $name
        if (-not (Test-Path $src)) { continue }

        $old2 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $null = & $7z e "-o$check" -y $zip $name 2>&1
        $ErrorActionPreference = $old2

        $got = Join-Path $check $name
        if (-not (Test-Path $got)) {
            Say "  could not read $name back out of the zip" 'Red'; $ok = $false; continue
        }
        if ((Get-Sha256 $got) -ne (Get-Sha256 $src)) {
            Say "  $name in the zip is not the one that was just built" 'Red'
            Say '    the archive kept an older copy. Delete payload.zip and run this again.' 'Yellow'
            $ok = $false
        } else {
            Say "  $name is current" 'Green'
        }
    }
    Remove-Item $check -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not $ok) { Die 'The installer did not come out right. Do not send these files.' }

$gb = [math]::Round((Get-Item $zip).Length / 1GB, 2)
Head 'Done'
Say ("Thornswood-Setup.exe  -  {0:n0} KB" -f ($exeLen / 1KB)) 'Green'
Say "Thornswood-Setup.zip  -  $gb GB" 'Green'
Write-Host ''
Say 'Upload BOTH to the same place. Your friends need both in one folder, then' 'Gray'
Say 'they run the exe. It finds the zip on its own and does the rest.' 'Gray'
Say 'They must not unzip it themselves.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
