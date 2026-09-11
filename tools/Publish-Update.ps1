<#
  Publish-Update.ps1

  Diffs the current build against the last published state, packs only what
  changed, uploads it as a release asset, and updates version.json so everyone's
  launcher picks it up.

  First time:   .\Publish-Update.ps1 -Baseline
  After that:   .\Publish-Update.ps1 -Notes "Swapped the map mod"
  Launcher:     .\Publish-Update.ps1 -Launcher -Notes "New launcher"
#>
[CmdletBinding()]
param(
    [string]$Root    = 'C:\SkyrimTogether',
    [string]$RepoDir,
    [string]$Repo,
    [string]$Id,
    [string]$Notes   = '',
    [switch]$Baseline,
    [switch]$Launcher,
    [switch]$NoUpload,
    [switch]$NoPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; [void](Read-Host 'Enter to exit'); exit 1 }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RepoDir) { $RepoDir = Split-Path -Parent $Here }
if (-not (Test-Path (Join-Path $RepoDir 'version.json'))) { Die "No version.json in $RepoDir. Point -RepoDir at your clone." }

$GameDir    = Join-Path $Root 'Game'
$ProfileDir = Join-Path $Root 'Profile'
$DistDir    = Join-Path $Root '_dist'
$StateFile  = Join-Path $DistDir 'published.json'
$VersionFile = Join-Path $RepoDir 'version.json'
if (-not (Test-Path $GameDir)) { Die "No build at $GameDir." }
$null = New-Item -ItemType Directory -Force -Path $DistDir

Head 'Skyrim Together - publish'

# ------------------------------------------------------------ what is ours
$vanillaDataFiles = @('Skyrim.esm','Update.esm','Dawnguard.esm','HearthFires.esm','Dragonborn.esm','_ResourcePack.esl','_ResourcePack.bsa')
$vanillaDataPatterns = @('Skyrim - *.bsa','cc*.esm','cc*.esl','cc*.esp','cc*.bsa')
$vanillaDataDirs = @('Video','Strings')
$vanillaRootFiles = @('SkyrimSE.exe','SkyrimSELauncher.exe','steam_api64.dll','bink2w64.dll','Skyrim.ccc','installscript.vdf','Skyrim_Default.ini','High.ini','Low.ini','Medium.ini','Ultra.ini')
$vanillaRootDirs = @('_DowngraderBackups','Creations','Mods','Skyrim','src')

function Test-Vanilla([string]$rel) {
    $parts = $rel -split '\\'
    $top = $parts[0]
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

Say '  Scanning the build...'
$prefix = $GameDir.TrimEnd('\') + '\'
$now = @{}
foreach ($f in (Get-ChildItem -LiteralPath $GameDir -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($prefix.Length)
    if (Test-Vanilla $rel) { continue }
    if ($f.Extension -in '.pdb', '.log') { continue }
    $now[$rel] = ('{0}:{1}' -f $f.Length, $f.LastWriteTimeUtc.Ticks)
}
Say ("  {0:n0} mod files" -f $now.Count) 'Green'

$prev = @{}
if (Test-Path $StateFile) {
    $obj = Get-Content $StateFile -Raw | ConvertFrom-Json
    foreach ($p in $obj.PSObject.Properties) { $prev[$p.Name] = $p.Value }
}

function Save-State {
    $o = [ordered]@{}
    foreach ($k in ($now.Keys | Sort-Object)) { $o[$k] = $now[$k] }
    $o | ConvertTo-Json -Depth 3 -Compress | Set-Content $StateFile -Encoding UTF8
}

if ($Baseline) {
    Save-State
    Head 'Done'
    Say "Baseline recorded: $($now.Count) files." 'Green'
    Say 'Future runs will pack only what changes from here.' 'Gray'
    Write-Host ''
    [void](Read-Host 'Enter to close'); exit 0
}
if (-not $prev.Count) { Die "No baseline yet. Run this once with -Baseline first." }

# ------------------------------------------------------------ diff
Head 'Changes'
$changed = @(); $removed = @()
foreach ($k in $now.Keys) { if (-not $prev.ContainsKey($k) -or $prev[$k] -ne $now[$k]) { $changed += $k } }
foreach ($k in $prev.Keys) { if (-not $now.ContainsKey($k)) { $removed += $k } }

$changedBytes = 0
foreach ($c in $changed) { $changedBytes += [int64](($now[$c] -split ':')[0]) }
Say ("  {0:n0} added or changed ({1:n1} MB)" -f $changed.Count, ($changedBytes / 1MB)) $(if ($changed.Count) { 'Green' } else { 'DarkGray' })
Say ("  {0:n0} removed" -f $removed.Count) $(if ($removed.Count) { 'Yellow' } else { 'DarkGray' })

if (-not $changed.Count -and -not $removed.Count -and -not $Launcher) {
    Head 'Nothing to do'
    Say 'The build matches what is already published.' 'Gray'
    Write-Host ''
    [void](Read-Host 'Enter to close'); exit 0
}

if (-not $Id) { $Id = Get-Date -Format 'yyyyMMdd-HHmm' }

# ------------------------------------------------------------ pack
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = Join-Path $DistDir "pack-$Id.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

if ($changed.Count -or $removed.Count) {
    Head 'Building the pack'
    $zip = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
    try {
        $n = 0
        foreach ($rel in $changed) {
            $src = Join-Path $GameDir $rel
            if (-not (Test-Path -LiteralPath $src)) { continue }
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $src, ('game/' + ($rel -replace '\\', '/')), 'Optimal')
            $n++
            if ($n % 500 -eq 0) { Write-Host ("    {0:n0}/{1:n0}" -f $n, $changed.Count) -ForegroundColor DarkGray }
        }

        # The load order always rides along, so nobody ends up with new plugins
        # that are not enabled.
        $localAD = Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition'
        foreach ($f in 'plugins.txt', 'loadorder.txt') {
            $src = Join-Path $localAD $f
            if (-not (Test-Path $src)) { $src = Join-Path $ProfileDir "Default\$f" }
            if (Test-Path $src) { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $src, "profile/$f", 'Optimal') }
        }

        if ($removed.Count) {
            $e = $zip.CreateEntry('delete.txt')
            $sw = New-Object IO.StreamWriter ($e.Open())
            foreach ($rel in $removed) { $sw.WriteLine(($rel -replace '\\', '/')) }
            $sw.Flush(); $sw.Dispose()
        }
    } finally { $zip.Dispose() }

    $mb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Say "  pack-$Id.zip  -  $mb MB" 'Green'
}

# ------------------------------------------------------------ launcher exe
$exePath = Join-Path $Root 'Launcher\SkyrimTogether.exe'
$launcherVersion = ''
if ($Launcher) {
    if (-not (Test-Path $exePath)) { Die "No launcher at $exePath. Run Build-Launcher.ps1 first." }
    $updaterCs = Join-Path $Here 'app\Updater.cs'
    if (Test-Path $updaterCs) {
        $m = [regex]::Match((Get-Content $updaterCs -Raw), 'Version\s*=\s*"([^"]+)"')
        if ($m.Success) { $launcherVersion = $m.Groups[1].Value }
    }
    if (-not $launcherVersion) { Die 'Could not read the version out of app\Updater.cs. Bump it before publishing a launcher.' }
    Say "  launcher $launcherVersion" 'Green'
}

# ------------------------------------------------------------ upload
$doc = Get-Content $VersionFile -Raw | ConvertFrom-Json
if (-not $Repo) { $Repo = $doc.PSObject.Properties['repo'] | ForEach-Object { $_.Value } }

$gh = Get-Command gh -EA SilentlyContinue
$packUrl = ''; $exeUrl = ''

if (-not $NoUpload -and $gh) {
    Head 'Uploading'
    $assets = @()
    if (Test-Path $zipPath) { $assets += $zipPath }
    if ($Launcher) { $assets += $exePath }

    $repoArg = @(); if ($Repo) { $repoArg = @('--repo', $Repo) }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & gh release create $Id @assets @repoArg --title "Update $Id" --notes $(if ($Notes) { $Notes } else { "Update $Id" }) 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Say '  Release exists, uploading into it instead.' 'DarkGray'
        & gh release upload $Id @assets @repoArg --clobber 2>&1 | Out-Host
    }

    $json = & gh api ("repos/{0}/releases/tags/{1}" -f $Repo, $Id) 2>$null
    $ErrorActionPreference = $old
    if ($json) {
        $rel = ($json -join '') | ConvertFrom-Json
        foreach ($a in $rel.assets) {
            $u = "https://api.github.com/repos/$Repo/releases/assets/$($a.id)"
            if ($a.name -like 'pack-*.zip') { $packUrl = $u }
            if ($a.name -eq 'SkyrimTogether.exe') { $exeUrl = $u }
        }
    }
    if ($packUrl) { Say "  pack asset ready" 'Green' }
    if ($exeUrl)  { Say "  launcher asset ready" 'Green' }
} elseif (-not $NoUpload) {
    Say '  The GitHub CLI is not installed, so nothing was uploaded.' 'Yellow'
    Say '  winget install GitHub.cli   then   gh auth login' 'Yellow'
}

# ------------------------------------------------------------ version.json
Head 'version.json'
if (Test-Path $zipPath) {
    $sha = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLower()
    $packs = @()
    if ($doc.PSObject.Properties['packs'] -and $doc.packs) { $packs = @($doc.packs) }
    $packs += [pscustomobject]@{
        id     = $Id
        url    = $packUrl
        sha256 = $sha
        notes  = $Notes
    }
    $doc.packs = $packs
    Say "  pack $Id added" 'Green'
}
if ($Launcher -and (Test-Path $exePath)) {
    $doc.launcherVersion = $launcherVersion
    $doc.launcherUrl     = $exeUrl
    $doc.launcherSha256  = (Get-FileHash $exePath -Algorithm SHA256).Hash.ToLower()
    Say "  launcher $launcherVersion recorded" 'Green'
}
$doc | ConvertTo-Json -Depth 6 | Set-Content $VersionFile -Encoding UTF8

if (-not $packUrl -and (Test-Path $zipPath)) {
    Say '  url is blank because nothing was uploaded. Fill it in before pushing.' 'Yellow'
}

# ------------------------------------------------------------ push
if (-not $NoPush) {
    Head 'Pushing'
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    Push-Location $RepoDir
    try {
        & git add version.json
        & git commit -m "Update $Id$(if ($Notes) { ": $Notes" })" 2>&1 | Out-Host
        & git push 2>&1 | Out-Host
    } finally { Pop-Location; $ErrorActionPreference = $old }
}

Save-State

Head 'Done'
Say "Everyone's launcher will offer update $Id on next start." 'Green'
Write-Host ''
[void](Read-Host 'Enter to close')
