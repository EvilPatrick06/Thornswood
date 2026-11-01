<#
  New-SignedManifest.ps1

  Writes the manifest a Release for the box deploy agent carries (#5180), and
  the catalog over it that Sign-OnRunner.ps1 then signs. The agent reads both
  (tools/DeployAgent/ReleaseFetch.cs):

      manifest.json   { schema: 1, repo, commit, tag, version, made,
                        parts: { <part>: [ { name, sha256, size } ] } }
      manifest.cat    a catalog over manifest.json alone (New-FileCatalog,
                      version 2, SHA256), the shape release.cat has over
                      release.json (Release-Manifest.ps1)

      pwsh -File scripts/release/New-SignedManifest.ps1 -Out <folder> -Tag <tag>
           -Commit <40 hex> -Part gamemode -Files <path>,<path> [-Version a.b.c]
           [-ServerZip <server-<commit>-<sum>.zip>]

  -ServerZip adds a second part, server: the server build's zip as
  ServerArtifact.ps1 makes it (Get-EngineArtifact.ps1 puts CI's build of the
  pin there), and the record it carries, server-build.json, beside it, so the
  agent can tell from the record alone whether dev runs that build already
  and fetch the zip only when it does not (#5219).

  It writes <Out>\files\manifest.json, <Out>\manifest.cat, and copies each
  file into <Out>\assets beside the manifest and the catalog, so the folder
  is the Release's files. The catalog covers the manifest, and the manifest's
  sha256 covers every other file, so one signature holds the whole Release.
  New-FileCatalog is Windows only, so this runs on a Windows runner.

  Keep it ASCII.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Out,
  [Parameter(Mandatory = $true)][string]$Tag,
  [Parameter(Mandatory = $true)][string]$Commit,
  [Parameter(Mandatory = $true)][ValidateSet('gamemode', 'agent')][string]$Part,
  [Parameter(Mandatory = $true)][string[]]$Files,
  [string]$Version = '',
  [string]$ServerZip = '',
  [string]$Repo = $env:GITHUB_REPOSITORY,
  [switch]$NoCatalog
)

$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = 'ThornswoodRP/Thornswood' }
if ($Commit -notmatch '^[0-9a-f]{40}$') { throw "commit $Commit is not 40 hex" }
if ($Tag -notmatch '^(build-[A-Za-z0-9._-]{1,80}|agent-v\d+\.\d+\.\d+)$') { throw "tag $Tag is neither build-<...> nor agent-v<a.b.c>" }
if ($Part -eq 'agent' -and $Tag -ne ('agent-v' + $Version)) { throw "an agent Release's tag is agent-v<version>, and $Tag does not say $Version" }

if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
$filesDir = Join-Path $Out 'files'
$assets = Join-Path $Out 'assets'
New-Item -ItemType Directory -Force -Path $filesDir, $assets | Out-Null

$list = @()
foreach ($f in $Files) {
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "there is no file at $f" }
  $name = Split-Path -Leaf $f
  if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$' -or $name -in 'manifest.json', 'manifest.cat') { throw "$name is not a file name the agent takes" }
  Copy-Item -LiteralPath $f -Destination (Join-Path $assets $name) -Force
  $item = Get-Item -LiteralPath (Join-Path $assets $name)
  $list += [ordered]@{ name = $name; sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); size = $item.Length }
}

$parts = [ordered]@{ $Part = @($list) }
if ($ServerZip) {
  if ($Part -ne 'gamemode') { throw "a server build goes on a build Release beside the gamemode, not on an $Part Release" }
  if (-not (Test-Path -LiteralPath $ServerZip -PathType Leaf)) { throw "there is no server zip at $ServerZip" }
  $zipName = Split-Path -Leaf $ServerZip
  if ($zipName -notmatch '^server-[0-9a-f]{12}-[0-9a-f]{16}\.zip$') { throw "$zipName is not a server build zip as ServerArtifact.ps1 names one" }
  Copy-Item -LiteralPath $ServerZip -Destination (Join-Path $assets $zipName) -Force
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $za = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ServerZip).ProviderPath)
  try {
    $ze = $za.Entries | Where-Object { $_.FullName -eq 'server-build.json' } | Select-Object -First 1
    if (-not $ze) { throw "$zipName carries no server-build.json" }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($ze, (Join-Path $assets 'server-build.json'), $true)
  } finally { $za.Dispose() }
  $server = @()
  foreach ($n in 'server-build.json', $zipName) {
    $item = Get-Item -LiteralPath (Join-Path $assets $n)
    $server += [ordered]@{ name = $n; sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); size = $item.Length }
  }
  $parts['server'] = @($server)
}

$m = [ordered]@{
  schema  = 1
  repo    = $Repo
  commit  = $Commit
  tag     = $Tag
  version = $Version
  made    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  parts   = $parts
}
$json = Join-Path $filesDir 'manifest.json'
[IO.File]::WriteAllText($json, ($m | ConvertTo-Json -Depth 6 -Compress), (New-Object Text.UTF8Encoding($false)))
Copy-Item -LiteralPath $json -Destination (Join-Path $assets 'manifest.json') -Force
Write-Host ("manifest.json for {0}: {1} file(s) of {2}, commit {3}" -f $Tag, $list.Count, $Part, $Commit)
if ($ServerZip) { Write-Host ("  and the server build {0} with its record" -f (Split-Path -Leaf $ServerZip)) }
if ($NoCatalog) { exit 0 }

$cat = Join-Path $Out 'manifest.cat'
New-FileCatalog -Path $filesDir -CatalogFilePath $cat -CatalogVersion 2.0 | Out-Null
if (-not (Test-Path -LiteralPath $cat -PathType Leaf)) { throw "New-FileCatalog wrote no catalog at $cat" }
Write-Host "manifest.cat written over manifest.json; Sign-OnRunner.ps1 signs it, then it goes into assets"
exit 0
