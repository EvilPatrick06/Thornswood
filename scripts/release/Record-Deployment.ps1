<#
  Record-Deployment.ps1

  Records a release that is live on its channel as a GitHub Deployment of
  this repository, to the Main or the Dev environment, so the repository's
  front page and its Deployments list say which release each server's
  people get, from which commit, and when it went out (Patrick, 30 Oct 2026:
  once the repository is public, use GitHub's Releases, Deployments and
  Packages).

      pwsh scripts/release/Record-Deployment.ps1 -Tag release/main/20261030-133616
      pwsh scripts/release/Record-Deployment.ps1 -Tag release/dev/20261030-180337-dev

  Run by .github/workflows/release-files.yml, job "deployment", with the
  run's own token in GH_TOKEN (deployments: write); it needs nothing else and
  no secret.

  WHAT COUNTS AS LIVE. The channel's feed on the site, read the way a
  launcher reads it: version.json, and since the split feed (#1050) the
  settings asset it names, whose release.tag is the release launchers on
  that channel take. A Ship pushes its release tag only after it published
  the feed (Ship.ps1, "thornswood release tag"), so the tag a push starts
  this for is the live one. A tag the feed does not name (an older release,
  run by hand) is not recorded: the Deployment would say it is live when it
  is not.

  WHAT IT WRITES. One Deployment per release: ref the tag, environment Main
  or Dev (Main as the production environment), and one status, success, with
  the site as its address and this run as its log. auto_inactive marks the
  release before it on that environment inactive, so the newest is the one
  shown. Run again for a release already recorded, it says so and writes
  nothing.

  WHAT IT REFUSES.
    - A private repository: it says so and exits 0, writing nothing.
    - A tag that is not release/main/<id> or release/dev/<id>.
    - A tag that is not an annotated release tag.

  EXITS. 0 recorded, already recorded, not live, or private. 1 refused or
  failed, with why. tests\test-deployments.ps1 drives it against a stand-in
  GitHub and site.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Repo = $env:GITHUB_REPOSITORY,
    [string]$Site = 'https://thornswood.net',
    # The run that recorded it, which the workflow passes; the status's log.
    [string]$LogUrl = ''
)

$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = 'EvilPatrick06/Thornswood' }
$script:Api = 'https://api.github.com/repos/' + $Repo

# Every call to GitHub and the site goes through these two, so the harness
# can stand in for both.
function Invoke-GitHub([string]$Method, [string]$Uri, $Body = $null) {
    $h = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    if ($env:GH_TOKEN) { $h.Authorization = 'Bearer ' + $env:GH_TOKEN }
    $a = @{ Method = $Method; Uri = $Uri; Headers = $h }
    if ($null -ne $Body) { $a.Body = ($Body | ConvertTo-Json -Depth 6 -Compress); $a.ContentType = 'application/json' }
    return Invoke-RestMethod @a
}
function Get-SiteText([string]$Uri) {
    # An asset sent as application/octet-stream comes back as bytes.
    $c = (Invoke-WebRequest -Uri $Uri -MaximumRedirection 5).Content
    if ($c -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($c) }
    return [string]$c
}

function Stop-Run([string]$Why) { Write-Host "::error title=Deployment::$Why"; Write-Host "STOPPED  $Why"; exit 1 }

if ($Tag -notmatch '^release/(main|dev)/(\d{8}-\d{4,6}(-dev)?)$') { Stop-Run "'$Tag' is not release/main/<id> or release/dev/<id>; nothing was recorded" }
$channel = $Matches[1]
$id = $Matches[2]
$environment = if ($channel -eq 'main') { 'Main' } else { 'Dev' }
$feedDir = if ($channel -eq 'dev') { 'feed-dev' } else { 'feed' }

$r = Invoke-GitHub GET $script:Api
if ($r.private) {
    Write-Host "PRIVATE  $Repo is private, so nothing is recorded: a Deployment would go public with the repository."
    exit 0
}

# ---- the release the channel's feed names -----------------------------------
$doc = (Get-SiteText "$Site/$feedDir/version.json").TrimStart([char]0xFEFF) | ConvertFrom-Json
if ($doc.PSObject.Properties['settings'] -and [string]$doc.settings.sha256 -match '^[0-9a-f]{64}$') {
    $rest = Get-SiteText "$Site/$feedDir/assets/$($doc.settings.sha256)" | ConvertFrom-Json
    foreach ($p in $rest.PSObject.Properties) { if (-not $doc.PSObject.Properties[$p.Name]) { $doc | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value } }
}
$live = if ($doc.PSObject.Properties['release'] -and $doc.release) { [string]$doc.release.tag } else { '' }
if ($live -ne $Tag) {
    Write-Host "NOT LIVE  the $channel feed names '$live', not $Tag, so nothing was recorded"
    exit 0
}

# ---- the commit the tag is on ----------------------------------------------------
$ref = Invoke-GitHub GET ($script:Api + '/git/ref/tags/' + $Tag)
if ([string]$ref.object.type -ne 'tag') { Stop-Run "$Tag is not an annotated release tag; nothing was recorded" }
$commit = [string](Invoke-GitHub GET ($script:Api + '/git/tags/' + $ref.object.sha)).object.sha
if ($commit -notmatch '^[0-9a-f]{40}$') { Stop-Run "$Tag names no commit; nothing was recorded" }

# ---- found, or made ---------------------------------------------------------------
# GitHub's answer comes back as one object holding the JSON array, so it is
# spread through ForEach-Object before it is counted (#3686).
$dep = @(Invoke-GitHub GET ($script:Api + '/deployments?environment=' + $environment + '&sha=' + $commit + '&per_page=100') | ForEach-Object { $_ }) |
    Where-Object { [string]$_.ref -eq $Tag } | Select-Object -First 1
if ($dep) {
    $last = @(Invoke-GitHub GET ($script:Api + '/deployments/' + $dep.id + '/statuses?per_page=1') | ForEach-Object { $_ }) | Select-Object -First 1
    if ($last -and [string]$last.state -eq 'success') {
        Write-Host "ALREADY  $Tag is recorded as deployed to $environment"
        exit 0
    }
} else {
    $dep = Invoke-GitHub POST ($script:Api + '/deployments') @{
        ref = $Tag; environment = $environment; auto_merge = $false; required_contexts = @()
        production_environment = ($channel -eq 'main'); transient_environment = $false
        description = "Thornswood $channel release $id"
    }
    if (-not $dep.id) { Stop-Run "GitHub made no Deployment for $Tag" }
}
$status = @{ state = 'success'; environment_url = $Site; auto_inactive = $true; description = "Live on the $channel feed" }
if ($LogUrl) { $status.log_url = $LogUrl }
Invoke-GitHub POST ($script:Api + '/deployments/' + $dep.id + '/statuses') $status | Out-Null
Write-Host "RECORDED  $Tag ($($commit.Substring(0, 12))) as deployed to $environment"
exit 0
