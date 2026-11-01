<#
  New-SignedManifest.ps1

  Writes the manifest a Release for the box deploy agent carries (#5180), and
  the catalog over it that Sign-OnRunner.ps1 then signs. The agent reads both
  (agent/internal/agent/release.go):

      manifest.json   { schema: 1, repo, commit, tag, version, made,
                        parts: { <part>: [ { name, sha256, size } ] } }
      manifest.cat    a catalog over manifest.json alone (New-FileCatalog,
                      version 2, SHA256), the shape release.cat has over
                      release.json (Release-Manifest.ps1)

      pwsh -File scripts/release/New-SignedManifest.ps1 -Out <folder> -Tag <tag>
           -Commit <40 hex> -Part gamemode -Files <path>,<path> [-Version a.b.c]
           [-BotFiles <path>,<path>]

  -BotFiles adds a second part, "bot": the bot pass a dev Deployment waits
  on (#5196, scripts\bot\Bot-Pass.js and what it needs). The agent puts
  every file of a Release in one folder, so no two files of a Release may
  have the same name.

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
  [string[]]$BotFiles = @(),
  [string]$Repo = $env:GITHUB_REPOSITORY,
  [switch]$NoCatalog
)

$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = 'EvilPatrick06/Thornswood' }
if ($Commit -notmatch '^[0-9a-f]{40}$') { throw "commit $Commit is not 40 hex" }
if ($Tag -notmatch '^(build-[A-Za-z0-9._-]{1,80}|agent-v\d+\.\d+\.\d+)$') { throw "tag $Tag is neither build-<...> nor agent-v<a.b.c>" }
if ($Part -eq 'agent' -and $Tag -ne ('agent-v' + $Version)) { throw "an agent Release's tag is agent-v<version>, and $Tag does not say $Version" }

if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
$filesDir = Join-Path $Out 'files'
$assets = Join-Path $Out 'assets'
New-Item -ItemType Directory -Force -Path $filesDir, $assets | Out-Null

$names = @{}
function Get-PartList([string[]]$paths) {
  $out = @()
  foreach ($f in $paths) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "there is no file at $f" }
    $name = Split-Path -Leaf $f
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$' -or $name -in 'manifest.json', 'manifest.cat') { throw "$name is not a file name the agent takes" }
    if ($names.ContainsKey($name)) { throw "two files are called $name, and the agent puts a Release's files in one folder" }
    $names[$name] = $true
    Copy-Item -LiteralPath $f -Destination (Join-Path $assets $name) -Force
    $item = Get-Item -LiteralPath (Join-Path $assets $name)
    $out += [ordered]@{ name = $name; sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); size = $item.Length }
  }
  return ,$out
}
$list = Get-PartList $Files
$parts = [ordered]@{ $Part = @($list) }
if (@($BotFiles).Count) {
  if ($Part -ne 'gamemode') { throw "-BotFiles goes with a gamemode Release, the one a dev Deployment applies" }
  $parts['bot'] = Get-PartList $BotFiles
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
Write-Host ("manifest.json for {0}: {1} file(s) of {2}{3}, commit {4}" -f $Tag, $list.Count, $Part, $(if ($parts.Contains('bot')) { ' and ' + @($parts['bot']).Count + ' of bot' } else { '' }), $Commit)
if ($NoCatalog) { exit 0 }

$cat = Join-Path $Out 'manifest.cat'
New-FileCatalog -Path $filesDir -CatalogFilePath $cat -CatalogVersion 2.0 | Out-Null
if (-not (Test-Path -LiteralPath $cat -PathType Leaf)) { throw "New-FileCatalog wrote no catalog at $cat" }
Write-Host "manifest.cat written over manifest.json; Sign-OnRunner.ps1 signs it, then it goes into assets"
exit 0
