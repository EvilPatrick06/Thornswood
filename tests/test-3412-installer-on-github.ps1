<#
  test-3412-installer-on-github.ps1

      pwsh -NoProfile -File .\tests\test-3412-installer-on-github.ps1

  Issue #3412. Every main Ship needed One for its installer: it was built from
  One's game folder and signed there. installer.yml builds it from main's feed
  (Package-Thornswood -FromFeed) and signs it on GitHub's runner, or on the
  box's runner 3, with the identity release.yml signs the launcher with.

  What it checks:
    1. installer.yml: started by hand only, on nothing a pull request can
       reach; the signing identity only on a v tag, through the "release"
       environment, for the two build jobs alone; the fallback on runner 3
       (thornswood-sign) with the hosted job's own steps; the check on a build
       runner with no id-token; no secret, and no ${{ }} inside a script; the
       signing setup and the build taken off the runner whatever happened;
       Package run with -FromFeed -OneFile -NoPublish.
    2. Sign-Artifact.ps1's token from GitHub, lifted and run with a stand-in
       GitHub: none asked for when a token file is named or the job may not
       ask; a refusal without the Azure ids; otherwise one token, masked,
       written to a file of its own. And the call site removes the file and
       the variable once signtool is done.
    3. Installer-OnGitHub.ps1 against a stand-in GitHub: the launcher's tag
       from main's feed; the setup program held to SHA256SUMS; the installer
       put on a draft, replacing what an earlier run put there, and never on
       a published release or with a note that describes another exe; the
       second machine's check, which reads the note before the signature.

  It never reaches GitHub or the site. Read only apart from files under its
  own temp folder.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$env:THORNSWOOD_HARNESS = '1'
. (Join-Path $PSScriptRoot 'Windows.ps1')

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

# ---- 1. the workflow -----------------------------------------------------------
$wfPath = Join-Path $Repo '.github\workflows\installer.yml'
Yes 'installer.yml is there' (Test-Path -LiteralPath $wfPath)
if (-not (Test-Path -LiteralPath $wfPath)) { Done }
$wf = [IO.File]::ReadAllText($wfPath) -replace "`r`n", "`n"

function Get-TopBlock([string]$text, [string]$key) {
    $m = [regex]::Match($text, '(?ms)^' + [regex]::Escape($key) + ':\s*\n(.*?)(?=^\S)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}
function Get-Jobs([string]$text) {
    $body = $text.Substring($text.IndexOf("`njobs:`n") + 7)
    $out = [ordered]@{}
    $ms = @([regex]::Matches($body, '(?m)^  ([A-Za-z0-9_-]+):\s*$'))
    for ($i = 0; $i -lt $ms.Count; $i++) {
        $end = $(if ($i + 1 -lt $ms.Count) { $ms[$i + 1].Index } else { $body.Length })
        $out[$ms[$i].Groups[1].Value] = $body.Substring($ms[$i].Index, $end - $ms[$i].Index)
    }
    return $out
}

$on = Get-TopBlock $wf 'on'
$triggers = @([regex]::Matches($on, '(?m)^  ([a-z_]+):') | ForEach-Object { $_.Groups[1].Value })
Yes ("started by hand only (" + ($triggers -join ', ') + ')') ($triggers.Count -eq 1 -and $triggers[0] -eq 'workflow_dispatch')
Yes 'the run''s token is contents: write and nothing else' ((Get-TopBlock $wf 'permissions').Trim() -eq 'contents: write')
Yes 'no secret is read anywhere' ($wf -notmatch 'secrets\.')

$jobs = Get-Jobs $wf
Yes ('three jobs: installer, installer-vps, verify (' + (@($jobs.Keys) -join ', ') + ')') ((@($jobs.Keys) -join ',') -eq 'installer,installer-vps,verify')
if (@($jobs.Keys).Count -ne 3) { Done }
$envLine = "environment: `${{ startsWith(github.ref, 'refs/tags/v') && 'release' || '' }}"
foreach ($k in 'installer', 'installer-vps') {
    $j = $jobs[$k]
    Yes "$k has the release environment only on a v tag" ($j.Contains($envLine))
    Yes "$k asks for id-token: write" ($j -match '(?m)^      id-token: write\s*$')
}
Yes 'the hosted job runs on windows-latest unless the box is asked for' ($jobs['installer'] -match '(?m)^    runs-on: windows-latest\s*$' -and
    $jobs['installer'].Contains("if: `${{ vars.BUILD_RUNNER != 'vps' && inputs.runner != 'vps' }}"))
Yes 'the fallback runs on runner 3 alone (thornswood-sign)' ($jobs['installer-vps'] -match '(?m)^    runs-on: \[self-hosted, Windows, X64, thornswood-vps, thornswood-sign\]\s*$')
Yes '  after the hosted job did not succeed, never after a cancel' ($jobs['installer-vps'].Contains("if: `${{ !cancelled() && needs.installer.result != 'success' && needs.installer.result != 'cancelled' }}"))
Yes '  with the hosted job''s own steps' ($jobs['installer'] -match '(?m)^    steps: &installer\s*$' -and $jobs['installer-vps'] -match '(?m)^    steps: \*installer\s*$')
$v = $jobs['verify']
Yes 'the check runs on a check runner, which never signs and never waits behind a build (#3956)' ($v -match '(?m)^    runs-on: \[self-hosted, Windows, thornswood-vps, thornswood-check\]\s*$')
Yes '  with no signing identity' ($v -notmatch 'id-token' -and $v -notmatch 'environment:' -and $v -notmatch 'AZURE_')
Yes '  and holds the draft to Get-InstallerDraftRefusal' ($v.Contains('Get-InstallerDraftRefusal'))

$build = $jobs['installer']
Yes 'the run has to be on a v tag on main' ($build.Contains("if (`$env:GITHUB_REF -notlike 'refs/tags/v*')") -and $build.Contains('Resolve-ThornswoodReleaseTag -Tag $env:GITHUB_REF_NAME -RepoDir . -MainRef origin/main'))
Yes '  and main is what is built' ($build.Contains('git checkout --force --detach origin/main'))
Yes 'Package is run from the feed, one file, and never publishes' ($build -match 'Package-Thornswood\.ps1 -FromFeed -OneFile -NoPublish -NoPause ')
Yes 'the signed installer is read back Valid with a timestamp' ($build.Contains("`$sig.Status -ne 'Valid'") -and $build.Contains('TimeStamperCertificate'))
Yes 'the signing setup and the build go whatever happened' ($build -match ('(?s)Take the signing setup and the build off this runner\s*\n\s*if: \$\{\{ always\(\) \}\}.*' +
    [regex]::Escape("'records\signing\signing.json', 'records\signing\client'") + '.*' + [regex]::Escape("'feed-root', 'installer'")))
Yes 'every action is pinned to a full SHA' (@([regex]::Matches($wf, '(?m)uses:\s*(\S+)') | Where-Object { $_.Groups[1].Value -notmatch '@[0-9a-f]{40}$' }).Count -eq 0)
# What GitHub writes into a script before it runs is the injection; inputs
# reach the scripts through env.
$runs = @([regex]::Matches($wf, '(?ms)^\s+run: \|\n(.*?)(?=^\s{0,6}(?:- |[a-z_-]+:)|\z)') | ForEach-Object { $_.Groups[1].Value })
Yes ("no `${{ }} inside any of the {0} scripts" -f $runs.Count) ($runs.Count -ge 8 -and @($runs | Where-Object { $_.Contains('${{') }).Count -eq 0)

# ---- 2. Sign-Artifact's token from GitHub ---------------------------------------
$saPath = Join-Path $Repo 'scripts\release\Sign-Artifact.ps1'
$t = $null; $e = $null
$sa = [System.Management.Automation.Language.Parser]::ParseFile($saPath, [ref]$t, [ref]$e)
Yes 'Sign-Artifact.ps1 parses' (@($e).Count -eq 0)
$fn = $sa.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-GitHubSigningToken' }, $true)
Yes 'it has New-GitHubSigningToken' ($null -ne $fn)
$saSrc = [IO.File]::ReadAllText($saPath)
Yes 'the token is asked for right before signtool and removed with the variable after it' (
    $saSrc -match '(?s)\$tokenFile = New-GitHubSigningToken.*\$env:AZURE_FEDERATED_TOKEN_FILE = \$tokenFile.*& \$signtool @args.*finally \{.*Remove-Item -LiteralPath \$tokenFile.*Remove-Item Env:\\AZURE_FEDERATED_TOKEN_FILE')
Yes '  only for Artifact Signing' ($saSrc -match "(?s)if \(\`$method -eq 'artifactsigning'\) \{\s*try \{ \`$tokenFile = New-GitHubSigningToken")

$Scratch = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-3412-gh-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $Scratch
$keep = @{}
foreach ($k in 'AZURE_FEDERATED_TOKEN_FILE', 'ACTIONS_ID_TOKEN_REQUEST_URL', 'ACTIONS_ID_TOKEN_REQUEST_TOKEN', 'AZURE_CLIENT_ID', 'AZURE_TENANT_ID', 'RUNNER_TEMP', 'THORNSWOOD_TEST_SITE_DIR') {
    $keep[$k] = [Environment]::GetEnvironmentVariable($k)
}
function Set-Env([hashtable]$vals) {
    foreach ($k in 'AZURE_FEDERATED_TOKEN_FILE', 'ACTIONS_ID_TOKEN_REQUEST_URL', 'ACTIONS_ID_TOKEN_REQUEST_TOKEN', 'AZURE_CLIENT_ID', 'AZURE_TENANT_ID') {
        [Environment]::SetEnvironmentVariable($k, $(if ($vals.ContainsKey($k)) { $vals[$k] } else { $null }))
    }
}
try {
    if ($fn) {
        . ([scriptblock]::Create($fn.Extent.Text))
        $script:asked = @()
        function Invoke-RestMethod {
            param([string]$Uri, $Headers, $ErrorAction)
            $script:asked += [pscustomobject]@{ Uri = $Uri; Auth = [string]$Headers['Authorization'] }
            return [pscustomobject]@{ value = 'eyJ.stand-in.token' }
        }
        $env:RUNNER_TEMP = $Scratch

        Set-Env @{}
        Yes 'not a job that may ask: no token' ((New-GitHubSigningToken) -eq '' -and $script:asked.Count -eq 0)
        Set-Env @{ AZURE_FEDERATED_TOKEN_FILE = 'C:\given'; ACTIONS_ID_TOKEN_REQUEST_URL = 'https://gh.invalid/token?x=1'; ACTIONS_ID_TOKEN_REQUEST_TOKEN = 'req'; AZURE_CLIENT_ID = 'c'; AZURE_TENANT_ID = 't' }
        Yes 'a token file named by the caller (release.yml): none asked for' ((New-GitHubSigningToken) -eq '' -and $script:asked.Count -eq 0)
        Set-Env @{ ACTIONS_ID_TOKEN_REQUEST_URL = 'https://gh.invalid/token?x=1'; ACTIONS_ID_TOKEN_REQUEST_TOKEN = 'req' }
        $why = ''
        try { $null = New-GitHubSigningToken } catch { $why = $_.Exception.Message }
        Yes 'no Azure ids: refused, saying so, before anything is asked' ($why -match 'AZURE_CLIENT_ID and AZURE_TENANT_ID' -and $script:asked.Count -eq 0)
        Set-Env @{ ACTIONS_ID_TOKEN_REQUEST_URL = 'https://gh.invalid/token?x=1'; ACTIONS_ID_TOKEN_REQUEST_TOKEN = 'req'; AZURE_CLIENT_ID = 'c'; AZURE_TENANT_ID = 't' }
        $said = @(& { New-GitHubSigningToken } 6>&1 | ForEach-Object { [string]$_ })
        $file = @($said | Where-Object { $_ -notmatch '^::add-mask::' })
        Yes 'a job that may ask: one request, for Azure''s audience, with the job''s request token' ($script:asked.Count -eq 1 -and
            $script:asked[0].Uri -eq 'https://gh.invalid/token?x=1&audience=api://AzureADTokenExchange' -and $script:asked[0].Auth -eq 'bearer req')
        Yes '  the token is masked' ($said -contains '::add-mask::eyJ.stand-in.token')
        Yes '  and written to a file of its own under RUNNER_TEMP' ($file.Count -eq 1 -and $file[0].StartsWith($Scratch) -and
            (Test-Path -LiteralPath $file[0]) -and [IO.File]::ReadAllText($file[0]) -eq 'eyJ.stand-in.token')
        Remove-Item Function:\Invoke-RestMethod
    }

    # ---- 3. Installer-OnGitHub.ps1 against a stand-in GitHub ---------------------
    . (Join-Path $Repo 'scripts\release\Installer-OnGitHub.ps1')

    # The site: main's feed naming launcher 1.2.8.
    $site = Join-Path $Scratch 'site'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $site 'feed\version')
    [IO.File]::WriteAllText((Join-Path $site 'feed\version\00000001.json'), '{"launcherVersion":"1.2.8","packs":[]}')
    $env:THORNSWOOD_TEST_SITE_DIR = $site
    Yes 'the tag is the launcher main''s feed offers' ((Get-InstallerLauncherTag) -eq 'v1.2.8')
    [IO.File]::WriteAllText((Join-Path $site 'feed\version\00000002.json'), '{"launcherVersion":"1.2.8.3","packs":[]}')
    $why = ''; try { $null = Get-InstallerLauncherTag } catch { $why = $_.Exception.Message }
    Yes '  and never a dev number' ($why -match "not a main version")

    # GitHub: releases by id, files by asset id, and what was asked.
    $gh = @{ Releases = @(); Files = @{}; Calls = New-Object System.Collections.ArrayList; NextAsset = 100 }
    function New-Rel([int]$id, [string]$tag, [bool]$draft, [hashtable]$files) {
        $assets = @()
        foreach ($n in $files.Keys) {
            $aid = $gh.NextAsset++; $gh.Files[[string]$aid] = $files[$n]
            $assets += [pscustomobject]@{ id = $aid; name = $n }
        }
        return [pscustomobject]@{ id = $id; tag_name = $tag; draft = $draft; assets = $assets }
    }
    $api = {
        param([string]$Method, [string]$Uri, [string]$Body = '', [string]$InFile = '', [string]$OutFile = '')
        [void]$gh.Calls.Add(($Method + ' ' + $Uri))
        if ($Method -eq 'Get' -and $Uri -match '/releases\?per_page=100&page=(\d+)$') {
            if ([int]$Matches[1] -gt 1) { return ,@() }
            return ,@($gh.Releases)
        }
        if ($Method -eq 'Get' -and $Uri -match '/releases/assets/(\d+)$') {
            [IO.File]::WriteAllBytes($OutFile, [byte[]]$gh.Files[$Matches[1]]); return $null
        }
        if ($Method -eq 'Get' -and $Uri -match '/releases/(\d+)$') {
            $rid = [int]$Matches[1]; return (@($gh.Releases | Where-Object { $_.id -eq $rid })[0])
        }
        if ($Method -eq 'Delete' -and $Uri -match '/releases/assets/(\d+)$') { return $null }
        if ($Method -eq 'Post' -and $Uri -match '^https://uploads\.github\.com/') { return [pscustomobject]@{ id = 1 } }
        throw ('the stand-in GitHub was asked something it does not answer: ' + $Method + ' ' + $Uri)
    }
    $stubBytes = [byte[]](0x4D, 0x5A, 1, 2, 3, 4)
    $stubSha = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($stubBytes) | ForEach-Object { $_.ToString('x2') })
    $sumsOk = [Text.Encoding]::ASCII.GetBytes("aaaa$('0' * 60)  Thornswood.exe`n$stubSha  setup-stub.exe`n")
    $repoName = 'EvilPatrick06/Thornswood'

    $gh.Releases = @((New-Rel 7 'v1.2.8' $true @{ 'setup-stub.exe' = $stubBytes; 'SHA256SUMS' = $sumsOk }), (New-Rel 6 'v1.2.7' $false @{}))
    $into = Join-Path $Scratch 'stub'
    $got = Save-InstallerStub $api $repoName 'v1.2.8' $into
    Yes 'the setup program comes from the tag''s draft' ($got -eq (Join-Path $into 'setup-stub.exe') -and (Get-InstallerSha256 $got) -eq $stubSha)

    $gh.Releases = @((New-Rel 7 'v1.2.8' $true @{ 'setup-stub.exe' = [byte[]](0x4D, 0x5A, 9); 'SHA256SUMS' = $sumsOk }))
    $why = ''; try { $null = Save-InstallerStub $api $repoName 'v1.2.8' $into } catch { $why = $_.Exception.Message }
    Yes '  one that is not what SHA256SUMS names is refused' ($why -match 'is not the one its SHA256SUMS names')
    $gh.Releases = @()
    $why = ''; try { $null = Save-InstallerStub $api $repoName 'v1.2.8' $into } catch { $why = $_.Exception.Message }
    Yes '  a tag with no release says how to build it' ($why -match 'gh workflow run release\.yml --ref v1\.2\.8')
    $gh.Releases = @((New-Rel 7 'v1.2.8' $true @{}), (New-Rel 8 'v1.2.8' $true @{}))
    $why = ''; try { $null = Save-InstallerStub $api $repoName 'v1.2.8' $into } catch { $why = $_.Exception.Message }
    Yes '  a tag with two releases is refused, naming both' ($why -match 'has 2 releases \(7, 8\)')

    # The installer Package left: the exe and the note naming it.
    $out = Join-Path $Scratch 'installer'
    $null = New-Item -ItemType Directory -Force -Path $out
    $exeBytes = [byte[]](0x4D, 0x5A, 7, 7, 7)
    [IO.File]::WriteAllBytes((Join-Path $out 'Thornswood-Setup.exe'), $exeBytes)
    Write-InstallerReleaseNote $out '20261027-120000' (Get-InstallerSha256 (Join-Path $out 'Thornswood-Setup.exe'))

    $gh.Releases = @((New-Rel 7 'v1.2.8' $true @{ 'setup-stub.exe' = $stubBytes; 'Thornswood-Setup.exe' = [byte[]](1); 'Thornswood-Setup.release.json' = [byte[]](2) }))
    $oldIds = @($gh.Releases[0].assets | Where-Object { $_.name -like 'Thornswood-Setup*' } | ForEach-Object { [string]$_.id })
    $gh.Calls.Clear()
    $id = Send-InstallerToRelease $api $repoName 'v1.2.8' $out
    $calls = @($gh.Calls)
    Yes 'the installer goes on the tag''s draft' ($id -eq '7')
    Yes '  replacing the installer and note an earlier run put there' (@($oldIds | Where-Object { $calls -notcontains ('Delete https://api.github.com/repos/' + $repoName + '/releases/assets/' + $_) }).Count -eq 0 -and $oldIds.Count -eq 2)
    Yes '  and nothing else on it' (@($calls | Where-Object { $_ -like 'Delete *' }).Count -eq 2)
    Yes '  uploading the exe and its note' ($calls -contains ('Post https://uploads.github.com/repos/' + $repoName + '/releases/7/assets?name=Thornswood-Setup.exe') -and
        $calls -contains ('Post https://uploads.github.com/repos/' + $repoName + '/releases/7/assets?name=Thornswood-Setup.release.json'))

    $gh.Releases = @((New-Rel 7 'v1.2.8' $false @{ 'setup-stub.exe' = $stubBytes }))
    $gh.Calls.Clear()
    $why = ''; try { $null = Send-InstallerToRelease $api $repoName 'v1.2.8' $out } catch { $why = $_.Exception.Message }
    Yes 'a published release is refused' ($why -match 'is published, and a published release''s files are never replaced')
    Yes '  and nothing on it is touched' (@($gh.Calls | Where-Object { $_ -notlike 'Get *' }).Count -eq 0)

    [IO.File]::WriteAllBytes((Join-Path $out 'Thornswood-Setup.exe'), [byte[]](0x4D, 0x5A, 8))
    $gh.Releases = @((New-Rel 7 'v1.2.8' $true @{}))
    $gh.Calls.Clear()
    $why = ''; try { $null = Send-InstallerToRelease $api $repoName 'v1.2.8' $out } catch { $why = $_.Exception.Message }
    Yes 'a note that describes another exe is refused before GitHub is asked anything' ($why -match 'describes another Thornswood-Setup\.exe' -and $gh.Calls.Count -eq 0)

    # The second machine: the note first, then the signature.
    $note = [Text.Encoding]::UTF8.GetBytes(('{"release":"20261027-120000","sha256":"' + (-join ([Security.Cryptography.SHA256]::Create().ComputeHash($exeBytes) | ForEach-Object { $_.ToString('x2') })) + '"}'))
    $gh.Releases = @((New-Rel 7 'v1.2.8' $true @{ 'Thornswood-Setup.exe' = $exeBytes; 'Thornswood-Setup.release.json' = $note }))
    $chk = Join-Path $Scratch 'check'
    Yes 'no release id from the build: refused' ((Get-InstallerDraftRefusal $api $repoName '' $chk $Repo) -match 'gave no release id')
    $why = Get-InstallerDraftRefusal $api $repoName '7' $chk $Repo
    if ($OnWindows) { Yes ('an unsigned stand-in installer is refused by the publish gate: ' + $why) ($why -match 'not Authenticode Valid') }
    else { Yes ('the note holds, and then the signature is the publish gate''s, which only Windows reads: ' + $why) ($why -match 'only on Windows') }
    $gh.Releases = @((New-Rel 7 'v1.2.8' $true @{ 'Thornswood-Setup.exe' = [byte[]](0x4D, 0x5A, 6); 'Thornswood-Setup.release.json' = $note }))
    $why = Get-InstallerDraftRefusal $api $repoName '7' $chk $Repo
    Yes 'an installer its note does not describe is refused' ($why -match 'describes another Thornswood-Setup\.exe')
    $gh.Releases = @((New-Rel 7 'v1.2.8' $true @{ 'Thornswood-Setup.exe' = $exeBytes }))
    $why = Get-InstallerDraftRefusal $api $repoName '7' $chk $Repo
    Yes 'a draft with no note is refused' ($why -match 'has 0 files named Thornswood-Setup\.release\.json')
}
finally {
    foreach ($k in $keep.Keys) { [Environment]::SetEnvironmentVariable($k, $keep[$k]) }
    Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Done
