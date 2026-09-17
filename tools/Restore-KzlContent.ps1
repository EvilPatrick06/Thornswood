<#
  Restore-KzlContent.ps1

  Puts back the crafting and gathering assets that Thornswood-Content.esp
  needs and that Clean-Keizaal moved aside by mistake.

  Thornswood-Content.esp carries 33 Kzl records: KzlChop, the charcoal kilns
  and their markers, the salt mine furniture, the beehive, the chopping block,
  the alchemy and mining manuals. Its own description says the content was
  salvaged from Keizaal Online, so the assets are named after it, and a sweep
  that matched on the name took them out.

  They were published, so every pack that ever carried them is still a release
  asset on GitHub. This walks the releases oldest first, opens each pack, and
  pulls out only these exact paths:

      Data\meshes\Keizaal\
      Data\meshes\kzlcustommeshs\
      Data\meshes\weapons\kzl\
      Data\textures\Keizaal\
      Data\Scripts\KzlChop.pex

  It never overwrites a file that is already there, and it deletes nothing.

  Needs the gh command line, which Ship already uses, so it is installed and
  signed in. Run in PowerShell as Administrator, because the game lives under
  Program Files.
#>
[CmdletBinding()]
param(
    [string]$Repo = 'EvilPatrick06/Thornswood-Releases',
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition',
    # Somewhere to put the packs while they are being read. Not the game folder.
    [string]$Work = (Join-Path $env:TEMP 'thornswood-restore')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

Head 'Restoring the Kzl crafting assets'
Say ("game : " + $Game)
Say ("repo : " + $Repo)
Say 'Nothing is deleted, and nothing already on disk is overwritten.'

$admin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Say ''
    Say 'NOT RUNNING AS ADMINISTRATOR. Writing into Program Files will fail.' 'Red'
    Say 'Close this, right click PowerShell, Run as administrator, run it again.' 'Red'
    return
}
if (-not (Test-Path (Join-Path $Game 'SkyrimSE.exe'))) {
    Say ''
    Say ("No SkyrimSE.exe at " + $Game) 'Red'
    return
}
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    Say ''
    Say 'The gh command is not on the path. Ship uses it, so it is installed' 'Red'
    Say 'somewhere. Open the shell you run Ship from and try again there.' 'Red'
    return
}

# What we are looking for, as they appear inside a pack. Publish-Update stores
# every file as game/<relative path with forward slashes>.
$wantPrefix = @(
    'game/Data/meshes/Keizaal/',
    'game/Data/meshes/kzlcustommeshs/',
    'game/Data/meshes/weapons/kzl/',
    'game/Data/textures/Keizaal/'
)
$wantExact = @(
    'game/Data/Scripts/KzlChop.pex'
)

function Wanted([string]$entry) {
    foreach ($e in $wantExact)  { if ($entry -ieq $e) { return $true } }
    foreach ($p in $wantPrefix) { if ($entry.ToLower().StartsWith($p.ToLower())) { return $true } }
    return $false
}

# ----------------------------------------------------------------- releases
Head 'Releases'

$tags = @()
try {
    $raw = & gh release list --repo $Repo --limit 300 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($raw -join "`n") }
    foreach ($line in $raw) {
        $cols = ($line -split "`t")
        foreach ($c in $cols) {
            if ($c -match '^\s*(\d{8}-\d{4})\s*$') { $tags += $Matches[1]; break }
        }
    }
} catch {
    Say ("Could not list releases: " + $_) 'Red'
    return
}
$tags = @($tags | Sort-Object -Unique)
if ($tags.Count -eq 0) { Say 'No releases found.' 'Red'; return }
Say ("{0} releases, oldest {1}, newest {2}" -f $tags.Count, $tags[0], $tags[-1])
Say 'Walking them oldest first, because these files were added once and never changed.'

# ----------------------------------------------------------------- the walk
Head 'Looking'

if (-not (Test-Path $Work)) { New-Item -ItemType Directory -Path $Work -Force | Out-Null }
Add-Type -AssemblyName System.IO.Compression.FileSystem

$restored = 0
$skipped  = 0
$fromPack = @{}
$done     = $false

foreach ($tag in $tags) {
    if ($done) { break }
    $dir = Join-Path $Work $tag
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $out = & gh release download $tag --repo $Repo --pattern 'pack-*.zip' --dir $dir 2>&1
    if ($LASTEXITCODE -ne 0) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue; continue }

    foreach ($zipFile in (Get-ChildItem $dir -Filter 'pack-*.zip' -File)) {
        $zip = $null
        try { $zip = [IO.Compression.ZipFile]::OpenRead($zipFile.FullName) } catch { continue }
        try {
            $hits = @($zip.Entries | Where-Object { $_.FullName -and (Wanted $_.FullName) })
            if ($hits.Count -eq 0) { continue }

            Say ''
            Say ("$tag / $($zipFile.Name)  holds $($hits.Count) of them") 'Green'

            foreach ($e in $hits) {
                $rel = $e.FullName.Substring('game/'.Length) -replace '/', '\'
                $dst = Join-Path $Game $rel
                if (Test-Path -LiteralPath $dst) { $skipped++; continue }
                $dstDir = Split-Path $dst -Parent
                if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
                try {
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dst, $false)
                    $restored++
                    $fromPack[$rel] = $tag
                    Say ("    put back  " + $rel)
                } catch {
                    Say ("    FAILED    " + $rel + "   " + $_.Exception.Message) 'Red'
                }
            }
        } finally { if ($zip) { $zip.Dispose() } }
    }

    Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue

    # The scripts folder entry is the last of the set to appear, so once the
    # chop script is back and something was restored, there is nothing else in
    # later packs worth downloading.
    if ($restored -gt 0 -and (Test-Path (Join-Path $Game 'Data\Scripts\KzlChop.pex'))) { $done = $true }
}

# ----------------------------------------------------------------- the state
Head 'Where it stands'
Say ""
Say ("put back : " + $restored)
Say ("already there, left alone : " + $skipped)

$check = @(
    'Data\Scripts\KzlChop.pex',
    'Data\meshes\Keizaal',
    'Data\meshes\kzlcustommeshs',
    'Data\meshes\weapons\kzl',
    'Data\textures\Keizaal'
)
Say ''
foreach ($c in $check) {
    $p = Join-Path $Game $c
    if (Test-Path $p) {
        if ((Get-Item $p) -is [IO.DirectoryInfo]) {
            $n = @(Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue).Count
            Say ("  present  " + $c + "   (" + $n + " files)") 'Green'
        } else {
            Say ("  present  " + $c) 'Green'
        }
    } else {
        Say ("  MISSING  " + $c) 'Red'
    }
}

Say ''
if ($restored -gt 0) {
    Say 'These are back in the game but not in the publish baseline, so the next' 'Gray'
    Say 'Ship sees them as added and republishes them. Nothing has to be edited' 'Gray'
    Say 'by hand, and the next installer build picks them up from the game.' 'Gray'
} else {
    Say 'Nothing was put back. If everything above says present, they were already' 'Gray'
    Say 'there. If anything says MISSING, tell Gavin which one and from which pack' 'Gray'
    Say 'the rest came.' 'Gray'
}
Write-Host ''
