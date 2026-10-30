<#
  Publish-InstallerFromGitHub.ps1

  Puts the installer for main's newest release on the site from any machine,
  the cloud included (#3412). installer.yml builds it from main's feed and
  signs it on GitHub's runner, and a second GitHub runner checks it. This
  takes it off the launcher's draft and publishes it with Publish-Installer.ps1,
  which holds it to the publish gate again (on the box when this is not
  Windows) before it replaces the one people download.

      .\scripts\release\Publish-InstallerFromGitHub.ps1
      .\scripts\release\Publish-InstallerFromGitHub.ps1 -Tag v1.2.8   start installer.yml on this tag

  Ship.ps1 -FromFeed -Package runs it after the release is out, and its
  "did not rebuild" line names it, so the same command puts a failed one right.

  WHY A TAG. Only a run on a v tag gets the signing identity (installer.yml,
  HOW TO START IT). Without -Tag it is the tag of the launcher main's feed
  offers, the one whose draft holds the setup program. A tag made before
  installer.yml merged does not have it, and this says so before it starts
  anything.

  It talks to GitHub through gh, REST only (Ship.ps1, FOUND THROUGH REST, NOT
  GRAPHQL), with Ship.ps1's own gh helpers lifted out of it by the parser so
  they live in one place.
#>
[CmdletBinding()]
param(
    # Where the installer is put before it is sent: the folder
    # Package-Thornswood.ps1 builds into (Where.ps1 Package) unless given.
    [string]$OutDir = (& (Join-Path $PSScriptRoot 'Where.ps1') Package),
    [string]$Tag = '',
    # Bounds the wait for the installer.yml run, in seconds.
    [int]$WaitSeconds = 3600,
    # Passed on to Publish-Installer.ps1 (#2118). Loud.
    [switch]$AllowStaleCheckout
)
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent (Split-Path -Parent $Here)

. (Join-Path $Here 'Sign-OnGitHub.ps1')
. (Join-Path $Here 'Installer-OnGitHub.ps1')
. (Join-Path $Here 'Release-Baseline.ps1')

# Ship.ps1's gh helpers, by the parser (the header).
$t = $null; $e = $null
$shipAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Here 'Ship.ps1'), [ref]$t, [ref]$e)
foreach ($name in 'Get-SourceRepo', 'ConvertTo-GhArgument', 'Invoke-GhToStream') {
    $fn = $shipAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { throw "Ship.ps1 has no $name, which this reads GitHub with" }
    . ([scriptblock]::Create($fn.Extent.Text))
}

# Installer-OnGitHub.ps1's GitHub, through gh: reads, and downloads by asset
# id as bytes.
$api = {
    param([string]$Method, [string]$Uri, [string]$Body = '', [string]$InFile = '', [string]$OutFile = '')
    if ($Method -ne 'Get' -or $Body -or $InFile) { throw "only reads go to GitHub from here, not $Method $Uri" }
    $path = $Uri -replace '^https://api\.github\.com/', ''
    if ($OutFile) {
        $fs = [IO.File]::Create($OutFile)
        try { $why = Invoke-GhToStream @('api', '-H', 'Accept: application/octet-stream', $path) $fs }
        finally { $fs.Dispose() }
        if ($why) { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue; throw $why }
        return $null
    }
    $ms = New-Object IO.MemoryStream
    try {
        $why = Invoke-GhToStream @('api', '-H', 'Accept: application/vnd.github+json', $path) $ms
        $text = [Text.Encoding]::UTF8.GetString($ms.ToArray())
    } finally { $ms.Dispose() }
    if ($why) { throw $why }
    return ($text | ConvertFrom-Json)
}

$repo = Get-SourceRepo $RepoDir
$launcherTag = Get-InstallerLauncherTag
if (-not $Tag) { $Tag = $launcherTag }

$why = Get-InstallerWorkflowRefusal $repo $Tag
if ($why) { throw ($why + ' Nothing was published.') }
$why = Invoke-InstallerOnGitHub -Repo $repo -Tag $Tag -WaitSeconds $WaitSeconds
if ($why) { throw ($why + ' Nothing was published.') }

$rel = Find-InstallerRelease $api $repo $launcherTag
if ($null -eq $rel) { throw "there is no release for $launcherTag to take the installer from. Nothing was published." }
$null = New-Item -ItemType Directory -Force -Path $OutDir
foreach ($name in $InstallerAssetNames) { $null = Save-InstallerAsset $api $repo $rel $name $OutDir }
$exe = Join-Path $OutDir 'Thornswood-Setup.exe'
$carries = Read-InstallerReleaseNote $OutDir (Get-InstallerSha256 $exe)

# The release main's feed names now: one that went out while the installer
# was built is a release this one would leave out.
$ptr = Get-FeedBaselinePointer (Read-SiteFeed 'main')
$newest = $(if ($null -ne $ptr -and $ptr.PSObject.Properties['id']) { [string]$ptr.id } else { '' })
if ($newest -ne $carries) {
    throw ("the installer on the draft carries release $carries, and main's feed now names $(if ($newest) { $newest } else { 'no release' }). " +
           'Run this again, which builds it for the newest. Nothing was published.')
}
Write-Host ("  the installer for release {0}, from the draft for {1}" -f $carries, $launcherTag) -ForegroundColor Green

$pubArgs = @{ OutDir = $OutDir; OneFile = $true }
if ($AllowStaleCheckout) { $pubArgs['AllowStaleCheckout'] = $true }
& (Join-Path $Here 'Publish-Installer.ps1') @pubArgs
