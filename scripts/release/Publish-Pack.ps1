<#
  Publish-Pack.ps1

  Builds the optional packs listed in optional-packs.txt, uploads them as
  release assets, and adds them to version.json so the Add-ons tab in every
  launcher offers them.

      .\scripts\release\Publish-Pack.ps1
      .\scripts\release\Publish-Pack.ps1 -Only hd-textures
      .\scripts\release\Publish-Pack.ps1 -DryRun        build and check, upload nothing

  These are the files Package-Thornswood.ps1 deliberately left out of the
  installer. Both scripts read optional-packs.txt, so what comes out of one is
  exactly what goes into the other, and there is no way to ship an installer
  missing something nobody can download.

  THE ONE RULE, and it is checked rather than trusted: a pack may not contain a
  plugin. The server compares every enabled plugin by name, size and crc32, so
  one person with an extra esp is one person who cannot connect. Textures,
  meshes, sounds, weather and shaders are invisible to that check and are why
  this is safe at all. A pack with a plugin in it is refused and nothing is
  uploaded.
#>
[CmdletBinding()]
param(
    [string]$Only,
    [switch]$DryRun,
    [string]$Root = 'C:\Thornswood',
    # The clone of the public releases repo that holds version.json. Empty means
    # look beside this repository for Thornswood-Releases (same guess as
    # Set-Collection / Publish-News), so a second machine is not stuck on
    # Patrick's Downloads path.
    [string]$ReleaseDir,
    [string]$Repo = 'EvilPatrick06/Thornswood-Releases',
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent (Split-Path -Parent $Here)
if (-not $ReleaseDir) {
    $guess = Join-Path (Split-Path -Parent $RepoDir) 'Thornswood-Releases'
    if (-not (Test-Path (Join-Path $guess '.git'))) {
        throw "No Thornswood-Releases clone at $guess. Clone it there (git clone https://github.com/EvilPatrick06/Thornswood-Releases), or pass -ReleaseDir."
    }
    $ReleaseDir = $guess
}

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

Write-Host ''
Write-Host '  THORNSWOOD  -  optional packs' -ForegroundColor White

# ------------------------------------------------------------ the list ---
$listFile = Join-Path $Here 'optional-packs.txt'
if (-not (Test-Path -LiteralPath $listFile)) { Die "No optional-packs.txt next to this script." }

$packs = @{}
$order = @()
foreach ($line in (Get-Content -LiteralPath $listFile)) {
    $t = $line.Trim()
    if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
    $parts = $t -split '\|'
    if ($parts.Count -lt 3) { Say "  ignored, needs id | name | path:  $t" 'Yellow'; continue }
    $id = $parts[0].Trim()
    if (-not $packs.ContainsKey($id)) {
        $packs[$id] = [pscustomobject]@{ Id = $id; Name = $parts[1].Trim(); Paths = @() }
        $order += $id
    }
    $packs[$id].Paths += $parts[2].Trim().TrimStart('\')
}

if ($order.Count -eq 0) {
    Head 'Nothing to do'
    Say '  optional-packs.txt lists no packs, so the installer still carries everything.' 'Yellow'
    Write-Host ''
    Say '  Add a line to take something out of it:' 'DarkGray'
    Say '      hd-textures | High resolution textures | Data\textures\' 'Green'
    Write-Host ''
    Say '  Then Package-Thornswood.ps1 leaves that path out and this puts it up.' 'DarkGray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

if ($Only) {
    if (-not $packs.ContainsKey($Only)) { Die "No pack called '$Only' in optional-packs.txt." }
    $order = @($Only)
}

$GameDir = Join-Path $Root 'Game'
if (-not (Test-Path -LiteralPath $GameDir)) { Die "No build at $GameDir." }

$work = Join-Path $env:TEMP 'thornswood-packs'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $work

# ------------------------------------------------------------ building ---
$built = @()
foreach ($id in $order) {
    $p = $packs[$id]
    Head ("Building " + $p.Name)

    $stage = Join-Path $work $id
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $stage 'game')

    $count = 0; $bytes = 0; $plugins = @()
    foreach ($rel in $p.Paths) {
        $src = Join-Path $GameDir $rel
        if (-not (Test-Path -LiteralPath $src)) { Say "  not in the build, skipped:  $rel" 'Yellow'; continue }

        $files = @(Get-ChildItem -LiteralPath $src -Recurse -File -Force)
        $prefix = (Join-Path $GameDir '').TrimEnd('\') + '\'
        foreach ($f in $files) {
            $r = $f.FullName.Substring($prefix.Length)
            $ext = $f.Extension.ToLowerInvariant()
            if ($ext -in '.esp', '.esm', '.esl', '.bsa') { $plugins += $r; continue }
            $dest = Join-Path (Join-Path $stage 'game') $r
            $dir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
            $count++; $bytes += $f.Length
        }
        Say ("  {0}  {1:n0} files" -f $rel, $files.Count)
    }

    # This is the check the whole design rests on. A plugin in a pack means
    # some people have an esp others do not, and the server turns them away
    # with a load order mismatch that looks like a launcher bug.
    if ($plugins.Count) {
        Write-Host ''
        Say "  $($p.Name) contains $($plugins.Count) plugin or archive file(s):" 'Red'
        $plugins | Select-Object -First 12 | ForEach-Object { Say "    $_" 'Red' }
        if ($plugins.Count -gt 12) { Say ("    and " + ($plugins.Count - 12) + " more") 'Red' }
        Write-Host ''
        Say '  A pack cannot contain a plugin or a bsa. The server compares plugin' 'Yellow'
        Say '  lists, so anybody who installs this could not connect, and a bsa is' 'Yellow'
        Say '  loaded by a plugin, so taking one optional shows as purple textures.' 'Yellow'
        Say '  Narrow the path in optional-packs.txt to a folder without them.' 'Yellow'
        Die 'Nothing was built and nothing was uploaded.'
    }

    if ($count -eq 0) { Say '  nothing to pack, skipped' 'Yellow'; continue }

    $zip = Join-Path $work ($id + '.zip')
    Say ("  {0:n0} files, {1:n1} MB, compressing..." -f $count, ($bytes / 1MB))
    Compress-Archive -Path (Join-Path $stage 'game') -DestinationPath $zip -CompressionLevel Optimal -Force
    $zipItem = Get-Item -LiteralPath $zip
    $sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
    Say ("  {0:n1} MB zipped" -f ($zipItem.Length / 1MB)) 'Green'

    $built += [pscustomobject]@{
        Id = $id; Name = $p.Name; Zip = $zip
        Bytes = $zipItem.Length; Sha = $sha; Files = $count; Raw = $bytes
    }
}

if ($built.Count -eq 0) { Die 'Nothing was built.' }

if ($DryRun) {
    Head 'Dry run'
    foreach ($b in $built) { Say ("  {0,-24} {1:n1} MB  {2}" -f $b.Id, ($b.Bytes / 1MB), $b.Sha.Substring(0, 12)) }
    Write-Host ''
    Say '  Nothing was uploaded. Run it again without -DryRun.' 'Yellow'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ----------------------------------------------------------- uploading ---
Head 'Uploading'
$token = $env:GITHUB_TOKEN
if (-not $token) {
    $gh = Get-Command gh -EA SilentlyContinue
    if ($gh) { $token = (& gh auth token 2>$null) }
}
if (-not $token) {
    Die ("No GitHub token. Either set GITHUB_TOKEN for this window, or sign in once with:" +
         [Environment]::NewLine + "    gh auth login")
}

$tag = 'packs-' + (Get-Date -Format 'yyyyMMdd-HHmm')
$hdr = @{ Authorization = "Bearer $token"; 'User-Agent' = 'thornswood'; Accept = 'application/vnd.github+json' }

$rel = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Repo/releases" -Headers $hdr -Body (@{
    tag_name = $tag; name = $tag; body = 'Optional packs'; draft = $false; prerelease = $false
} | ConvertTo-Json) -ContentType 'application/json'

$upload = $rel.upload_url -replace '\{.*$', ''
foreach ($b in $built) {
    Say ("  {0}..." -f $b.Id)
    $a = Invoke-RestMethod -Method Post -Uri ($upload + '?name=' + [Uri]::EscapeDataString($b.Id + '.zip')) `
         -Headers $hdr -InFile $b.Zip -ContentType 'application/zip'
    $b | Add-Member -NotePropertyName Url -NotePropertyValue $a.browser_download_url
    Say ("    " + $a.browser_download_url) 'Green'
}

# --------------------------------------------------------- version.json ---
Head 'version.json'
$vf = Join-Path $ReleaseDir 'version.json'
if (-not (Test-Path -LiteralPath $vf)) { Die "No version.json in $ReleaseDir." }

$raw = [IO.File]::ReadAllText($vf) -replace '^\uFEFF', ''
$doc = $raw | ConvertFrom-Json

$optional = @()
if ($doc.PSObject.Properties['optional'] -and $doc.optional) { $optional = @($doc.optional) }

foreach ($b in $built) {
    # Replace the entry rather than adding a second one, so republishing a pack
    # does not leave two rows with the same name and different checksums.
    $optional = @($optional | Where-Object { $_.id -ne $b.Id })
    $optional += [pscustomobject]@{
        id = $b.Id; name = $b.Name; url = $b.Url; sha256 = $b.Sha
        bytes = $b.Bytes
        notes = ('{0:n0} files' -f $b.Files)
    }
    Say ("  {0,-24} {1:n1} MB" -f $b.Id, ($b.Bytes / 1MB))
}

if ($doc.PSObject.Properties['optional']) { $doc.optional = $optional }
else { $doc | Add-Member -NotePropertyName optional -NotePropertyValue $optional }

[IO.File]::WriteAllText($vf, ($doc | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))

Head 'Pushing'
Push-Location $ReleaseDir
try {
    $who = (& git config user.email 2>$null)
    if (-not $who) {
        Pop-Location
        Die ("This clone has no git identity, so the push would fail after the upload." +
             [Environment]::NewLine + "    git -C `"$ReleaseDir`" config user.email you@example.com" +
             [Environment]::NewLine + "    git -C `"$ReleaseDir`" config user.name 'Your Name'")
    }
    & git add version.json
    & git commit -m ("Optional packs " + $tag) | ForEach-Object { Say "  $_" }
    & git push | ForEach-Object { Say "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        Die 'version.json did not push. The zips are up but nobody will be offered them.'
    }
} finally { if ((Get-Location).Path -eq $ReleaseDir) { Pop-Location } }

Remove-Item $work -Recurse -Force -EA SilentlyContinue

Head 'Done'
Say ("  " + $built.Count + " pack(s) live. They show on the Add-ons tab of the Mods page.") 'Green'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
