<#
  Installer-OnGitHub.ps1

  What .github\workflows\installer.yml does with GitHub's releases, as
  functions a harness can drive with a stand-in GitHub (#3412). Dot-sourced;
  defines functions and nothing else.

      . .\scripts\release\Installer-OnGitHub.ps1
      $api  = New-InstallerGitHubApi $env:GH_TOKEN
      $tag  = Get-InstallerLauncherTag                         v<the launcher main's feed offers>
      $stub = Save-InstallerStub $api $repo $tag $into         the setup program, checked against SHA256SUMS
      $id   = Send-InstallerToRelease $api $repo $tag $outDir  the signed installer on that tag's draft
      $why  = Get-InstallerDraftRefusal $api $repo $id $into $repoDir   '' when a second machine accepts it

  WHY. Every main Ship needed One for its installer: Package-Thornswood.ps1
  built it from One's game folder and signed it there. Package-Thornswood
  -FromFeed builds it from main's feed on any machine, and installer.yml
  builds and signs it on GitHub's runner, with the same federated identity
  release.yml signs the launcher with. No secret is stored anywhere.

  WHERE IT GOES. The draft release of the launcher main's feed offers, the
  same draft release.yml put that launcher and its setup program on, so the
  installer sits beside the setup program it was built around. A draft is
  seen by nobody without push access, and a release asset takes none of the
  repository's 500 MB artifact storage (#3410). A published release's files
  are never replaced (docs\SIGNED-RELEASES.md section 6), so a published one
  is refused. Beside the exe goes Thornswood-Setup.release.json, the note
  Package wrote: the release the installer carries and the signed exe's
  sha256, which Publish-Installer reads into the site's files.json.

  THROWS, saying why, wherever installer.yml has to stop; the workflow prints
  the message as its error.

  Keep it ASCII and Windows PowerShell 5.1.
#>

. (Join-Path $PSScriptRoot 'Feed-Store.ps1')
. (Join-Path $PSScriptRoot 'Release-Name.ps1')
. (Join-Path $PSScriptRoot 'Assert-PublishSigned.ps1')

$InstallerAssetNames = @('Thornswood-Setup.exe', 'Thornswood-Setup.release.json')

# GitHub's REST API with the job's token, as one scriptblock a harness can
# replace: & $api <Method> <Uri> [-Body <json>] [-InFile <path>] [-OutFile <path>].
# A download is by asset id, as bytes: the octet-stream answer is a redirect
# to the file, which needs no token.
function New-InstallerGitHubApi([string]$Token) {
    if (-not $Token) { throw 'there is no GitHub token (GH_TOKEN) to read the releases with' }
    $t = $Token
    return {
        param([string]$Method, [string]$Uri, [string]$Body = '', [string]$InFile = '', [string]$OutFile = '')
        $h = @{ Authorization = ('Bearer ' + $t); 'X-GitHub-Api-Version' = '2022-11-28' }
        $ProgressPreference = 'SilentlyContinue'
        if ($OutFile) {
            $h['Accept'] = 'application/octet-stream'
            Invoke-WebRequest -Uri $Uri -Headers $h -OutFile $OutFile -UseBasicParsing -ErrorAction Stop | Out-Null
            return $null
        }
        $h['Accept'] = 'application/vnd.github+json'
        if ($InFile) { return (Invoke-RestMethod -Method $Method -Uri $Uri -Headers $h -ContentType 'application/octet-stream' -InFile $InFile -ErrorAction Stop) }
        if ($Body) { return (Invoke-RestMethod -Method $Method -Uri $Uri -Headers $h -ContentType 'application/json' -Body $Body -ErrorAction Stop) }
        return (Invoke-RestMethod -Method $Method -Uri $Uri -Headers $h -ErrorAction Stop)
    }.GetNewClosure()
}

function Get-InstallerApiBase([string]$Repo) { return ('https://api.github.com/repos/' + $Repo) }

# The tag of the launcher main's feed offers: the installer carries that
# launcher (Package-Thornswood -FromFeed), so it is built around the setup
# program release.yml built beside it. Main's tags have three numbers.
function Get-InstallerLauncherTag {
    $doc = Read-SiteFeed 'main'
    if ($null -eq $doc) { throw 'main''s feed (thornswood.net/feed/version.json) could not be read, so which launcher the installer carries is not known' }
    $v = ''
    if ($doc.PSObject.Properties['launcherVersion']) { $v = [string]$doc.launcherVersion }
    if ($v -notmatch '^\d+\.\d+\.\d+$') { throw ("main's feed names launcher '" + $v + "', which is not a main version (a.b.c)") }
    return ('v' + $v)
}

# The one release a tag has, draft or not; $null when it has none. The list,
# not /releases/tags/<tag>, because only the list holds drafts (release.yml,
# ONE DRAFT PER TAG).
function Find-InstallerRelease($Api, [string]$Repo, [string]$Tag) {
    $base = Get-InstallerApiBase $Repo
    $same = @()
    for ($page = 1; $page -le 50; $page++) {
        $batch = @(& $Api 'Get' ($base + '/releases?per_page=100&page=' + $page) | ForEach-Object { $_ })
        $same += @($batch | Where-Object { [string]$_.tag_name -eq $Tag })
        if ($batch.Count -lt 100) { break }
    }
    if ($same.Count -gt 1) {
        throw ("tag $Tag has {0} releases ({1}); the one that is not wanted goes first" -f $same.Count, (($same | ForEach-Object { [string]$_.id }) -join ', '))
    }
    if ($same.Count -eq 0) { return $null }
    return $same[0]
}

function Save-InstallerAsset($Api, [string]$Repo, $Release, [string]$Name, [string]$Into) {
    $a = @($Release.assets | Where-Object { [string]$_.name -eq $Name })
    if ($a.Count -ne 1) { throw ("the release for {0} ({1}) has {2} files named {3}" -f $Release.tag_name, $Release.id, $a.Count, $Name) }
    $path = Join-Path $Into $Name
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    $null = & $Api 'Get' ((Get-InstallerApiBase $Repo) + '/releases/assets/' + $a[0].id) -OutFile $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "$Name did not download from the release for $($Release.tag_name)" }
    return $path
}

function Get-InstallerSha256([string]$Path) {
    $h = [Security.Cryptography.SHA256]::Create()
    $s = [IO.File]::OpenRead($Path)
    try { return (-join ($h.ComputeHash($s) | ForEach-Object { $_.ToString('x2') })) }
    finally { $s.Dispose(); $h.Dispose() }
}

# The setup program release.yml built for $Tag, into $Into, held to the
# SHA256SUMS beside it the way Ship.ps1 Get-ReleaseStub holds it. Its path.
function Save-InstallerStub($Api, [string]$Repo, [string]$Tag, [string]$Into) {
    $rel = Find-InstallerRelease $Api $Repo $Tag
    if ($null -eq $rel) { throw "there is no release for $Tag, so there is no setup program to build the installer around. Build it: gh workflow run release.yml --ref $Tag -f tag=$Tag" }
    $null = New-Item -ItemType Directory -Force -Path $Into
    $stub = Save-InstallerAsset $Api $Repo $rel 'setup-stub.exe' $Into
    $sums = Save-InstallerAsset $Api $Repo $rel 'SHA256SUMS' $Into
    $want = ''
    foreach ($line in [IO.File]::ReadAllLines($sums)) {
        $m = [regex]::Match($line, '(?i)^\s*([0-9a-f]{64})\s+\*?setup-stub\.exe\s*$')
        if ($m.Success) { $want = $m.Groups[1].Value.ToLower(); break }
    }
    if (-not $want) { throw "SHA256SUMS on the release for $Tag has no line for setup-stub.exe, so the setup program cannot be checked" }
    $got = Get-InstallerSha256 $stub
    if ($got -ne $want) { throw "setup-stub.exe from the release for $Tag is not the one its SHA256SUMS names (wanted $want, got $got)" }
    return $stub
}

# The installer Package built into $OutDir, onto $Tag's draft, replacing an
# installer an earlier run put there. Only when the note beside it describes
# this very exe. The release's id.
function Send-InstallerToRelease($Api, [string]$Repo, [string]$Tag, [string]$OutDir) {
    $exe = Join-Path $OutDir 'Thornswood-Setup.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "there is no $exe to put on the release" }
    $carries = Read-InstallerReleaseNote $OutDir (Get-InstallerSha256 $exe)
    $rel = Find-InstallerRelease $Api $Repo $Tag
    if ($null -eq $rel) { throw "there is no release for $Tag to put the installer on" }
    if (-not $rel.draft) {
        throw ("the release for $Tag ($($rel.id)) is published, and a published release's files are never replaced " +
               '(docs\SIGNED-RELEASES.md section 6). The installer was built and signed, and was not put anywhere.')
    }
    $base = Get-InstallerApiBase $Repo
    foreach ($name in $InstallerAssetNames) {
        foreach ($old in @($rel.assets | Where-Object { [string]$_.name -eq $name })) {
            $null = & $Api 'Delete' ($base + '/releases/assets/' + $old.id)
        }
        $up = 'https://uploads.github.com/repos/' + $Repo + '/releases/' + $rel.id + '/assets?name=' + [Uri]::EscapeDataString($name)
        $null = & $Api 'Post' $up -InFile (Join-Path $OutDir $name)
    }
    Write-Host ("the installer for release {0} is on the draft {1} for {2}" -f $carries, $rel.id, $Tag)
    return [string]$rel.id
}

# A second machine's check of the draft's installer, on its files alone: the
# note describes the exe, and the exe passes the publish gate (Authenticode
# Valid, the Subject naming ExpectedSigner, launcher\app\Signature.cs) with a
# timestamp. '' when it holds, otherwise why not.
function Get-InstallerDraftRefusal($Api, [string]$Repo, [string]$ReleaseId, [string]$Into, [string]$RepoDir) {
    if ($ReleaseId -notmatch '^[0-9]+$') { return 'the build job gave no release id' }
    try {
        $rel = & $Api 'Get' ((Get-InstallerApiBase $Repo) + '/releases/' + $ReleaseId)
        $null = New-Item -ItemType Directory -Force -Path $Into
        foreach ($name in $InstallerAssetNames) { $null = Save-InstallerAsset $Api $Repo $rel $name $Into }
        $exe = Join-Path $Into 'Thornswood-Setup.exe'
        $carries = Read-InstallerReleaseNote $Into (Get-InstallerSha256 $exe)
    } catch { return $_.Exception.Message }
    try { $who = Get-ExpectedSignerFragment -RepoRoot $RepoDir } catch { return ('ExpectedSigner could not be read: ' + $_.Exception.Message) }
    $why = Get-PublishSignRefusal -Path $exe -ExpectedSigner $who
    if ($why) { return $why }
    if (-not (Get-AuthenticodeSignature -LiteralPath $exe).TimeStamperCertificate) { return 'Thornswood-Setup.exe is signed with no timestamp, so its signature ends with the certificate in three days' }
    Write-Host ("the installer on draft {0} carries release {1} and passes the publish gate" -f $ReleaseId, $carries)
    return ''
}

# ---- for the Ship that publishes the release (Ship.ps1 -FromFeed -Package) ----
# These go through gh, the way Sign-OnGitHub.ps1 does (dot-source it first):
# a cloud session has gh and no token of its own. -Gh stands in for it.

# '' when installer.yml is on $Tag, so a run can be started there, else why.
# A tag made before installer.yml merged does not have it, and GitHub runs a
# workflow from the ref it is started on.
function Get-InstallerWorkflowRefusal([string]$Repo, [string]$Tag, [scriptblock]$Gh = { Invoke-SignOnGitHubGh $args }) {
    $ask = @('api', ('repos/' + $Repo + '/contents/.github/workflows/installer.yml?ref=' + $Tag))
    try { [void](& $Gh @ask) }
    catch {
        if ($_.Exception.Message -match '404|Not Found') {
            return ("$Tag was made before installer.yml merged, so the installer for a release on it cannot be built on GitHub (#3412). " +
                    'Ship this one with -Package from One; the next launcher tag carries installer.yml.')
        }
        return ("whether installer.yml is on $Tag could not be read: " + $_.Exception.Message)
    }
    return ''
}

# Starts installer.yml on $Tag and waits for its run: GitHub's runner builds
# and signs the installer from main's feed, and a second one holds it to the
# publish gate on the draft. '' once that run is green, else why.
# -WaitSeconds bounds the whole wait.
function Invoke-InstallerOnGitHub {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Tag,
        [scriptblock]$Gh = { Invoke-SignOnGitHubGh $args },
        [int]$WaitSeconds = 3600,
        [int]$Poll = 20
    )
    if ($Tag -notmatch '^v\d+\.\d+\.\d+(\.\d+)?$') { return "$Tag is not a release tag" }
    $asked = (Get-Date).ToUniversalTime().AddSeconds(-30)
    $ask = @('workflow', 'run', 'installer.yml', '-R', $Repo, '--ref', $Tag)
    try { [void](& $Gh @ask) }
    catch { return ('installer.yml could not be started on ' + $Tag + ': ' + $_.Exception.Message) }
    Write-Host ("  asked {0} to build and sign the installer from main's feed (installer.yml on {1})" -f $Repo, $Tag) -ForegroundColor DarkGray
    $until = (Get-Date).AddSeconds($WaitSeconds)
    $run = $null
    while ($true) {
        try { $run = Find-ReleaseRun $Gh $Repo 'installer.yml' $asked { param($r) [string]$r.headBranch -ceq $Tag } }
        catch { return ('the installer.yml runs could not be read: ' + $_.Exception.Message) }
        if ($null -ne $run -and [string]$run.status -eq 'completed') { break }
        if ((Get-Date) -gt $until) {
            if ($null -eq $run) { return "no installer.yml run started on $Tag in $WaitSeconds seconds" }
            return ("the installer.yml run on $Tag is still " + [string]$run.status + " after $WaitSeconds seconds: " + [string]$run.url)
        }
        Start-Sleep -Seconds $Poll
    }
    if ([string]$run.conclusion -ne 'success') {
        return ("the installer.yml run on $Tag ended " + [string]$run.conclusion + ', so there is no checked, signed installer: ' + [string]$run.url)
    }
    Write-Host ('  built, signed and checked on GitHub: ' + [string]$run.url) -ForegroundColor DarkGray
    return ''
}
