<#
  Package-SkyrimTogether.ps1
  Turns the built install at C:\SkyrimTogether into the single file your friends run.

  Only your mod content goes in. Every Bethesda file is left out, because the
  installer rebuilds those from each friend's own Steam copy and their own
  Steam depots.
#>
[CmdletBinding()]
param(
    [string]$Root    = 'C:\SkyrimTogether',
    [string]$OutDir  = 'C:\SkyrimTogether\_dist',
    [ValidateRange(0, 9)][int]$Level = 1,
    [switch]$NoArchive,
    [switch]$Plain7z,
    [switch]$ReuseStage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; [void](Read-Host 'Enter to exit'); exit 1 }

$GameDir    = Join-Path $Root 'Game'
$ProfileDir = Join-Path $Root 'Profile'
$LaunchDir  = Join-Path $Root 'Launcher'
$stage      = Join-Path $OutDir 'stage'

if (-not (Test-Path (Join-Path $GameDir 'SkyrimSE.exe'))) { Die "No build at $GameDir. Run Build-SkyrimTogether.ps1 first." }

Head 'Packaging'

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
if ($ReuseStage -and (Test-Path (Join-Path $stage 'payload'))) {
    Say '  Reusing the staged copy from the last run.' 'Yellow'
    $skipStage = $true
} else {
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    $skipStage = $false
}
$null = New-Item -ItemType Directory -Force -Path $stage, (Join-Path $stage 'payload'), (Join-Path $stage 'profile')

if (-not $skipStage) {
Say '  Listing the build...'
$all = @(Get-ChildItem -LiteralPath $GameDir -Recurse -File -Force)
$prefix = $GameDir.TrimEnd('\') + '\'

$ship = @(); $skipBytes = 0; $shipBytes = 0
foreach ($f in $all) {
    $rel = $f.FullName.Substring($prefix.Length)
    if (Test-Vanilla $rel) { $skipBytes += $f.Length; continue }
    if ($f.Extension -in '.pdb', '.log') { $skipBytes += $f.Length; continue }
    $ship += [pscustomobject]@{ Rel = $rel; Full = $f.FullName; Len = $f.Length }
    $shipBytes += $f.Length
}
Say ("  {0:n0} files kept ({1:n1} GB), {2:n0} left out ({3:n1} GB of Bethesda files and debug symbols)" -f `
    $ship.Count, ($shipBytes / 1GB), ($all.Count - $ship.Count), ($skipBytes / 1GB)) 'Green'

Say '  Copying...'
$payload = Join-Path $stage 'payload'
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

$payloadDir = Join-Path $stage 'payload'
if ($skipStage) {
    $staged    = @(Get-ChildItem -LiteralPath $payloadDir -Recurse -File -Force)
    $shipCount = $staged.Count
    $shipBytes = ($staged | Measure-Object Length -Sum).Sum
    Say ("  {0:n0} staged files, {1:n1} GB" -f $shipCount, ($shipBytes / 1GB)) 'Green'
} else {
    $shipCount = $ship.Count
}

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
$lexe = Join-Path $LaunchDir 'SkyrimTogether.exe'
if (Test-Path $lexe) {
    Copy-Item $lexe $stage -Force
    Say '  launcher exe included' 'Green'
} else {
    Say '  SkyrimTogether.exe is not built yet. Run Build-Launcher.ps1 first.' 'Yellow'
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
foreach ($f in 'Install-SkyrimTogether.ps1', 'Install.bat', 'Setup.bat', 'READ ME FIRST.txt') {
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

# ---- archive ---------------------------------------------------------------
if ($NoArchive) {
    Head 'Done'
    Say "Folder ready at $stage" 'Green'
    [void](Read-Host 'Enter to close'); exit 0
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
    [void](Read-Host 'Enter to close'); exit 0
}

# ---- self-extracting installer -------------------------------------------
Head 'Building the installer'

$stub = @((Join-Path $here 'setup-stub.exe'), (Join-Path $OutDir 'setup-stub.exe')) |
        Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $stub) {
    Say '  setup-stub.exe was not found. Run Build-Launcher.ps1 first, it compiles it.' 'Yellow'
    $keep = Join-Path $OutDir 'SkyrimTogether-Setup.zip'
    if (Test-Path $keep) { Remove-Item $keep -Force }
    Move-Item $blob $keep
    Head 'Done'
    Say "$keep" 'Green'
    Say 'Friends extract it and run Install.bat. Re-run this once the stub exists for the one-click version.' 'Gray'
    [void](Read-Host 'Enter to close'); exit 0
}
Say "  stub: $stub" 'DarkGray'

$exe = Join-Path $OutDir 'SkyrimTogether-Setup.exe'
if (Test-Path $exe) { Remove-Item $exe -Force }

# stub, then the zip, then a 24 byte trailer saying where the zip starts.
$out = [IO.File]::Create($exe)
try {
    $stubLen = 0L
    foreach ($part in @($stub, $blob)) {
        $in = [IO.File]::OpenRead($part)
        try {
            $in.CopyTo($out, 4MB)
            if ($part -eq $stub) { $stubLen = $out.Position }
        } finally { $in.Close() }
    }
    $zipLen = $out.Position - $stubLen
    $bw = New-Object IO.BinaryWriter($out)
    $bw.Write([Text.Encoding]::ASCII.GetBytes('STSFX001'))
    $bw.Write([int64]$stubLen)
    $bw.Write([int64]$zipLen)
    $bw.Flush()
    Say ("  payload starts at {0:n0}, {1:n0} bytes" -f $stubLen, $zipLen) 'DarkGray'
} finally { $out.Close() }

Remove-Item $blob -Force -EA SilentlyContinue

# ---- prove it before it goes anywhere ------------------------------------
Head 'Checking the installer'
$ok = $true

$fs = [IO.File]::OpenRead($exe)
try {
    $fs.Position = $fs.Length - 24
    $br = New-Object IO.BinaryReader($fs)
    $magic = [Text.Encoding]::ASCII.GetString($br.ReadBytes(8))
    $off = $br.ReadInt64(); $len = $br.ReadInt64()
    if ($magic -ne 'STSFX001') { Say "  trailer magic is '$magic', expected STSFX001" 'Red'; $ok = $false }
    elseif ($off -le 0 -or $len -le 0 -or ($off + $len + 24) -ne $fs.Length) {
        Say "  trailer points at $off + $len but the file is $($fs.Length) bytes" 'Red'; $ok = $false
    } else { Say "  trailer reads back clean" 'Green' }
} finally { $fs.Close() }

# 7-Zip opens a zip that has a program stuck on the front, which is what this is.
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$listing = & $7z l $exe 2>&1
$ErrorActionPreference = $old
$hasSetup = $listing | Where-Object { $_ -match 'Setup\.bat' }
$hasInstall = $listing | Where-Object { $_ -match 'Install-SkyrimTogether\.ps1' }
$hasLauncher = $listing | Where-Object { $_ -match 'SkyrimTogether\.exe' }
$hasPayload = $listing | Where-Object { $_ -match 'payload' }
foreach ($pair in @(@('Setup.bat', $hasSetup), @('the installer script', $hasInstall),
                    @('the launcher', $hasLauncher), @('the mod payload', $hasPayload))) {
    if ($pair[1]) { Say "  found $($pair[0])" 'Green' } else { Say "  MISSING $($pair[0])" 'Red'; $ok = $false }
}

if (-not $ok) { Die 'The installer did not come out right. Do not send this file.' }

$gb = [math]::Round((Get-Item $exe).Length / 1GB, 2)
Head 'Done'
Say "SkyrimTogether-Setup.exe  -  $gb GB" 'Green'
Write-Host ''
Say 'One file. Your friends double-click it, press Install, and it does the rest.' 'Gray'
if ($gb -gt 4) { Say 'It is over 4 GB, so send it somewhere that handles large files.' 'DarkGray' }
Write-Host ''
[void](Read-Host 'Enter to close')
