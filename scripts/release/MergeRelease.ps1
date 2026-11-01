<#
  MergeRelease.ps1

  What .github/workflows/merge-release.yml works out between steps (#5179):
  the release's names, the newest Release before it, and which parts the
  merge changed. Dot-sourced; defines functions and nothing else. ASCII, and
  PowerShell 7. tests\test-5179-merge-release.ps1 drives every function.

      . ./scripts/release/MergeRelease.ps1
      New-MergeReleaseNames -Utc <DateTime> -Run <n>
          @{ Tag = 'build-20261101.7'; Velopack = '2026.1101.7' }
      Get-MergeReleasePrevious [-Repo owner/name]
          the newest published build-* Release and its manifest, or $null
      Get-MergeReleasePrint -Manifest <obj> -Part <name>
          one line that changes exactly when the part's content does
      Get-MergeReleaseChanged -Manifest <obj> [-Previous <obj>]
          the parts whose print differs from the Release before
      Test-MergeReleaseVelopack -LauncherVersion <a.b.c> -GameZipSha256 <hex>
                                [-Previous <obj>]
          whether this merge makes a Velopack package, and so builds the
          launcher with the release's Velopack version

  THE NAMES. One time and one run number give both: the tag the agent
  applies, build-<yyyyMMdd>.<run>, and the Velopack version, which must be
  SemVer and must grow with every release: <yyyy>.<M*100+d>.<run> (no
  leading zero, so 2 Jan is 102). Within a year the month and day grow, and
  the run number grows with every run of the workflow, so a later release is
  always the higher version.

  WHAT COUNTS AS A CHANGE. Every Release carries every part, so any of them
  can be put back by its tag; only a part whose content changed asks for a
  Deployment of its own, and a merge that changed none publishes nothing. A
  part's print is its files' names and sha256, sorted, with three kinds left
  out: the gamemode's stamp (thornswood-build.json names the commit, so it
  differs on every merge), the server zip (ServerArtifact.ps1 zips it on
  each run; its record, server-build.json, says which build it is) and the
  game files' list (game-files.json names the commit; game.zip is the same
  bytes for the same files, Build-GameFiles.ps1 says how). The
  velopack and main parts, dev's and main's Velopack packages, are made from
  the launcher and the game files, so neither is compared on its own.

  THE LAUNCHER'S PRINT is its source number (the manifest's launcherVersion,
  LauncherVersion.ps1), not its files (#4825). The exe carries the Velopack
  version it was packed as (-p:Version, Build-Launcher.ps1), so the same
  sources built for two packages are two different files; a launcher whose
  sources no merge touched is not a change, whatever its bytes.

  ONE NUMBER (#4825). A Velopack package is made when the launcher's sources
  or the game files changed, and the launcher in it is built for it, with
  the package's version, so the number the launcher says is the number
  Velopack installed. Otherwise no package is made and the launcher of the
  Release before is carried. Test-MergeReleaseVelopack makes that call from
  the same prints Get-MergeReleaseChanged compares, before the launcher is
  built, so the two cannot disagree.
#>

function New-MergeReleaseNames {
  param([Parameter(Mandatory = $true)][DateTime]$Utc, [Parameter(Mandatory = $true)][int]$Run)
  if ($Run -lt 1) { throw "run number $Run is not 1 or more" }
  $u = $Utc.ToUniversalTime()
  return [pscustomobject]@{
    Tag      = ('build-{0}.{1}' -f $u.ToString('yyyyMMdd'), $Run)
    Velopack = ('{0}.{1}.{2}' -f $u.Year, ($u.Month * 100 + $u.Day), $Run)
  }
}

function Get-MergeReleasePrint {
  param([Parameter(Mandatory = $true)]$Manifest, [Parameter(Mandatory = $true)][string]$Part)
  if ($null -eq $Manifest -or $null -eq $Manifest.parts) { return '' }
  $p = $Manifest.parts.PSObject.Properties[$Part]
  if ($null -eq $p) { return '' }
  if ($Part -eq 'launcher') {
    $v = $Manifest.PSObject.Properties['launcherVersion']
    return $(if ($null -eq $v) { '' } else { 'launcherVersion:' + [string]$v.Value })
  }
  $lines = foreach ($f in @($p.Value)) {
    $n = [string]$f.name
    if ($Part -eq 'gamemode' -and $n -eq 'thornswood-build.json') { continue }
    if ($Part -eq 'server' -and $n -ne 'server-build.json') { continue }
    if ($Part -eq 'game' -and $n -ne 'game.zip') { continue }
    $n + ':' + ([string]$f.sha256).ToLowerInvariant()
  }
  $arr = [string[]]@($lines)
  [Array]::Sort($arr, [StringComparer]::Ordinal)
  return ($arr -join ';')
}

function Get-MergeReleaseChanged {
  param([Parameter(Mandatory = $true)]$Manifest, $Previous = $null)
  $changed = New-Object System.Collections.Generic.List[string]
  foreach ($p in @($Manifest.parts.PSObject.Properties)) {
    if ($p.Name -in 'velopack', 'main') { continue }
    if ($null -eq $Previous -or (Get-MergeReleasePrint $Manifest $p.Name) -ne (Get-MergeReleasePrint $Previous $p.Name)) { $changed.Add($p.Name) }
  }
  # Unrolled: callers take it as @(...), which gives an empty array for none.
  return $changed.ToArray()
}

# True when the launcher's source number or the game files differ from the
# Release before, or there is none: the merge makes a Velopack package and
# builds the launcher for it (header, ONE NUMBER). The game files are given
# as game.zip's sha256, the one file of the part that is compared.
function Test-MergeReleaseVelopack {
  param([Parameter(Mandatory = $true)][string]$LauncherVersion, [Parameter(Mandatory = $true)][string]$GameZipSha256, $Previous = $null)
  $m = [pscustomobject]@{
    launcherVersion = $LauncherVersion
    parts           = [pscustomobject]@{
      launcher = @()
      game     = @([pscustomobject]@{ name = 'game.zip'; sha256 = $GameZipSha256; size = 0 })
    }
  }
  $c = @(Get-MergeReleaseChanged -Manifest $m -Previous $Previous)
  return ($c -contains 'launcher' -or $c -contains 'game')
}

# The newest published build-* Release, by GitHub's own order (newest first),
# with its manifest.json read from its assets. Drafts are skipped: a run that
# stopped part way leaves one, and it was never applied. $null when there is
# none yet. Throws when GitHub cannot be read, so a failed read is never taken
# for "no Release before".
function Get-MergeReleasePrevious {
  param([string]$Repo = $env:GITHUB_REPOSITORY, [string]$ReleasesFile = '', [string]$ManifestDir = '')
  if ($ReleasesFile) { $rels = Get-Content -LiteralPath $ReleasesFile -Raw | ConvertFrom-Json }
  else {
    $raw = gh api "repos/$Repo/releases?per_page=50"
    if ($LASTEXITCODE -ne 0) { throw "GitHub did not list the Releases of $Repo (gh exit $LASTEXITCODE)" }
    $rels = ($raw -join "`n") | ConvertFrom-Json
  }
  foreach ($r in @($rels)) {
    if ($r.draft -or [string]$r.tag_name -notmatch '^build-') { continue }
    $asset = @($r.assets | Where-Object { $_.name -eq 'manifest.json' }) | Select-Object -First 1
    if ($null -eq $asset) { continue }
    if ($ManifestDir) { $m = Get-Content -LiteralPath (Join-Path $ManifestDir ([string]$r.tag_name + '.json')) -Raw | ConvertFrom-Json }
    else {
      $mraw = gh api -H 'Accept: application/octet-stream' ("repos/$Repo/releases/assets/" + $asset.id)
      if ($LASTEXITCODE -ne 0) { throw "GitHub did not hand over manifest.json of $($r.tag_name) (gh exit $LASTEXITCODE)" }
      $m = ($mraw -join "`n") | ConvertFrom-Json
    }
    if ([string]$m.tag -ne [string]$r.tag_name) { throw "$($r.tag_name)'s manifest.json says it is $($m.tag)" }
    return [pscustomobject]@{ Tag = [string]$r.tag_name; Commit = [string]$m.commit; Id = $r.id; Manifest = $m; Assets = @($r.assets) }
  }
  return $null
}
