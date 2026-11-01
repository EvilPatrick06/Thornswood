<#
  test-deployments.ps1

      pwsh -NoProfile -File .\tests\test-deployments.ps1

  scripts\release\Record-Deployment.ps1 records a release that is live on
  its channel as a GitHub Deployment, to Main or Dev (Patrick, 30 Oct 2026:
  use GitHub's Deployments once public). This runs the real script against a
  stand-in GitHub and a stand-in site: its two calls out (Invoke-GitHub,
  Get-SiteText) are replaced in a copy of it under TEMP by ones that read
  and write a JSON state file, so every Deployment and status it leaves can
  be looked at afterwards.

  It holds:
    - a private repository: nothing written, exit 0;
    - a tag that is not release/<channel>/<id>: exit 1;
    - a tag the channel's split feed does not name: nothing written, exit 0;
    - the live main release: one Deployment to Main, production, on the
      tag's commit, with one success status, the site's address, the run's
      log and auto_inactive; run again, nothing written;
    - a Deployment a stopped run left with no status: its status is written,
      no second Deployment;
    - the live dev release: Dev, not production;
    - a lightweight tag: exit 1, nothing written;
    - release-files.yml runs it in a job of its own, only while public, on
      GitHub's runner, with deployments: write.

  Read only, apart from its folder under TEMP, which it removes.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-deployments-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    $src = [IO.File]::ReadAllText((Join-Path $repo 'scripts/release/Record-Deployment.ps1'))
    $a = $src.IndexOf('function Invoke-GitHub(')
    $b = $src.IndexOf('function Stop-Run(')
    Yes 'the script sends every call out through Invoke-GitHub and Get-SiteText' ($a -gt 0 -and $b -gt $a -and
        $src.Substring($a, $b - $a) -match 'function Get-SiteText' -and ([regex]::Matches($src, 'Invoke-(RestMethod|WebRequest)')).Count -eq 2)

    # The stand-in: GitHub and the site as one state file. A list comes back
    # as one object holding the array, the way Invoke-RestMethod hands it.
    $stub = @'
function Save-Fake { [IO.File]::WriteAllText($env:TS_FAKE, ($global:Fake | ConvertTo-Json -Depth 10)) }
$global:Fake = [IO.File]::ReadAllText($env:TS_FAKE) | ConvertFrom-Json
function Invoke-GitHub([string]$Method, [string]$Uri, $Body = $null) {
    $F = $global:Fake
    $F.calls += ,"$Method $Uri"
    $path = $Uri -replace '^https://api\.github\.com/repos/[^/]+/[^/]+', ''
    try {
        if ($Method -eq 'GET' -and $path -eq '') { return [pscustomobject]@{ private = [bool]$F.private } }
        if ($Method -eq 'GET' -and $path -match '^/git/ref/tags/(.+)$') {
            $t = @($F.tags | Where-Object { $_.name -eq $Matches[1] })[0]
            if (-not $t) { throw "404 $Uri" }
            return [pscustomobject]@{ object = [pscustomobject]@{ type = $t.type; sha = $t.obj } }
        }
        if ($Method -eq 'GET' -and $path -match '^/git/tags/(.+)$') {
            $t = @($F.tags | Where-Object { $_.obj -eq $Matches[1] })[0]
            return [pscustomobject]@{ object = [pscustomobject]@{ type = 'commit'; sha = $t.commit } }
        }
        if ($Method -eq 'GET' -and $path -match '^/deployments\?environment=([^&]+)&sha=([0-9a-f]+)&per_page=100$') {
            $env0 = $Matches[1]; $sha = $Matches[2]
            return ,@($F.deployments | Where-Object { $_.environment -eq $env0 -and $_.sha -eq $sha } | ForEach-Object { [pscustomobject]@{ id = $_.id; ref = $_.ref } })
        }
        if ($Method -eq 'GET' -and $path -match '^/deployments/(\d+)/statuses\?per_page=1$') {
            $d = @($F.deployments | Where-Object { $_.id -eq [int]$Matches[1] })[0]
            return ,@(@($d.statuses) | Select-Object -Last 1)
        }
        if ($Method -eq 'POST' -and $path -eq '/deployments') {
            $t = @($F.tags | Where-Object { $_.name -eq $Body.ref })[0]
            $d = [pscustomobject]@{ id = 700 + @($F.deployments).Count; ref = $Body.ref; sha = $t.commit; environment = $Body.environment
                production = $Body.production_environment; transient = $Body.transient_environment; statuses = @() }
            $F.deployments += ,$d
            return [pscustomobject]@{ id = $d.id }
        }
        if ($Method -eq 'POST' -and $path -match '^/deployments/(\d+)/statuses$') {
            $d = @($F.deployments | Where-Object { $_.id -eq [int]$Matches[1] })[0]
            $d.statuses += ,[pscustomobject]@{ state = $Body.state; environment_url = $Body.environment_url; log_url = $Body.log_url; auto_inactive = $Body.auto_inactive }
            return $null
        }
        throw "the stand-in GitHub has no $Method $path"
    } finally { Save-Fake }
}
function Get-SiteText([string]$Uri) {
    $rel = $Uri -replace '^https://thornswood\.net/', ''
    return [IO.File]::ReadAllText((Join-Path $env:TS_SITE $rel))
}

'@
    $copy = Join-Path $work 'Record-Deployment.ps1'
    [IO.File]::WriteAllText($copy, $src.Substring(0, $a) + $stub + $src.Substring($b))

    $site = Join-Path $work 'site'
    $tagMain = 'release/main/20261030-133616'
    $tagDev = 'release/dev/20261030-180337-dev'
    function Set-Feed([string]$dir, [string]$tag) {
        $d = New-Item -ItemType Directory -Force -Path (Join-Path $site "$dir/assets")
        $settings = (@{ release = @{ tag = $tag } } | ConvertTo-Json -Depth 4)
        $sha = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($settings))) -replace '-', '').ToLowerInvariant()
        [IO.File]::WriteAllText((Join-Path $d.FullName $sha), $settings)
        [IO.File]::WriteAllText((Join-Path $site "$dir/version.json"), (@{ launcherSha256 = ('a' * 64); settings = @{ sha256 = $sha } } | ConvertTo-Json -Depth 4))
    }
    Set-Feed 'feed' $tagMain
    Set-Feed 'feed-dev' $tagDev

    $fake = Join-Path $work 'fake.json'
    function Set-Fake($o) { [IO.File]::WriteAllText($fake, ($o | ConvertTo-Json -Depth 10)) }
    function Get-Fake { return [IO.File]::ReadAllText($fake) | ConvertFrom-Json }
    function Run([string]$tag) {
        $env:TS_FAKE = $fake; $env:TS_SITE = $site
        $out = @(& pwsh -NoProfile -File $copy -Tag $tag -Repo 'ThornswoodRP/Thornswood' -LogUrl 'https://github.com/run/1' 2>&1 | ForEach-Object { [string]$_ })
        return @{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
    }
    $cMain = '1' * 40; $cDev = '2' * 40
    function New-Base {
        return [ordered]@{ private = $false; calls = @(); deployments = @(); tags = @(
            [ordered]@{ name = $tagMain; type = 'tag'; obj = 't1'; commit = $cMain },
            [ordered]@{ name = $tagDev; type = 'tag'; obj = 't2'; commit = $cDev },
            [ordered]@{ name = 'release/main/20261029-100000'; type = 'tag'; obj = 't3'; commit = ('3' * 40) },
            [ordered]@{ name = 'release/main/20261029-110000'; type = 'commit'; obj = ('4' * 40); commit = ('4' * 40) }) }
    }
    function Writes($g) { return @($g.calls | Where-Object { $_ -match '^(POST|PATCH|DELETE) ' }).Count }

    # ---- private ------------------------------------------------------------
    $p = New-Base; $p.private = $true; Set-Fake $p
    $r = Run $tagMain
    Yes 'a private repository: exit 0, and it says why nothing was recorded' ($r.Code -eq 0 -and $r.Out -match 'PRIVATE')
    Yes '  and nothing was asked of GitHub but the repository' (@((Get-Fake).calls).Count -eq 1)

    # ---- a tag of another shape ---------------------------------------------
    Set-Fake (New-Base)
    $r = Run 'v1.2.11'
    Yes 'a tag that is not release/<channel>/<id> is refused' ($r.Code -eq 1 -and $r.Out -match 'is not release/main')

    # ---- not live -------------------------------------------------------------
    Set-Fake (New-Base)
    $r = Run 'release/main/20261029-100000'
    $g = Get-Fake
    Yes 'a release the feed does not name is not recorded, exit 0' ($r.Code -eq 0 -and $r.Out -match 'NOT LIVE' -and $r.Out -match [regex]::Escape($tagMain))
    Yes '  and nothing is written' ((Writes $g) -eq 0 -and @($g.deployments).Count -eq 0)

    # ---- the live main release ------------------------------------------------
    Set-Fake (New-Base)
    $r = Run $tagMain
    $g = Get-Fake
    $d = @($g.deployments)[0]
    Yes ("the live main release is recorded ({0})" -f ($r.Out -split "`n" | Select-Object -Last 1)) ($r.Code -eq 0 -and $r.Out -match 'RECORDED' -and @($g.deployments).Count -eq 1)
    Yes '  to Main, as the production environment, never transient' ($d.environment -eq 'Main' -and $d.production -eq $true -and $d.transient -eq $false)
    Yes '  on the tag, which is on the release commit' ($d.ref -eq $tagMain -and $d.sha -eq $cMain)
    $st = @($d.statuses)
    Yes '  with one success status: the site, the run''s log, the one before marked inactive' ($st.Count -eq 1 -and $st[0].state -eq 'success' -and
        $st[0].environment_url -eq 'https://thornswood.net' -and $st[0].log_url -eq 'https://github.com/run/1' -and $st[0].auto_inactive -eq $true)
    $calls = @($g.calls).Count
    $r = Run $tagMain
    $g = Get-Fake
    Yes 'run again: it says it is already recorded' ($r.Code -eq 0 -and $r.Out -match 'ALREADY')
    Yes '  and writes nothing' (@($g.calls | Select-Object -Skip $calls | Where-Object { $_ -match '^(POST|PATCH|DELETE) ' }).Count -eq 0 -and @($g.deployments).Count -eq 1)

    # ---- a Deployment a stopped run left --------------------------------------
    $left = Get-Fake
    $left.deployments[0].statuses = @()
    $left.calls = @()
    Set-Fake $left
    $r = Run $tagMain
    $g = Get-Fake
    Yes 'a Deployment left with no status gets its status, and no second one is made' ($r.Code -eq 0 -and $r.Out -match 'RECORDED' -and
        @($g.deployments).Count -eq 1 -and @($g.deployments[0].statuses).Count -eq 1 -and @($g.calls | Where-Object { $_ -match '^POST .*/deployments$' }).Count -eq 0)

    # ---- dev --------------------------------------------------------------------
    Set-Fake (New-Base)
    $r = Run $tagDev
    $d = @((Get-Fake).deployments)[0]
    Yes 'the live dev release goes to Dev, not as production' ($r.Code -eq 0 -and $d.environment -eq 'Dev' -and $d.production -eq $false -and $d.sha -eq $cDev)

    # ---- a lightweight tag -------------------------------------------------------
    $lw = New-Base
    $lw.tags = @($lw.tags | Where-Object { $_.name -ne $tagMain }) + @([ordered]@{ name = $tagMain; type = 'commit'; obj = $cMain; commit = $cMain })
    Set-Fake $lw
    $r = Run $tagMain
    $g = Get-Fake
    Yes 'a tag that is not an annotated release tag is refused, nothing written' ($r.Code -eq 1 -and $r.Out -match 'not an annotated release tag' -and (Writes $g) -eq 0)

    # ---- the workflow ---------------------------------------------------------
    $wf = [IO.File]::ReadAllText((Join-Path $repo '.github/workflows/release-files.yml'))
    $i = $wf.IndexOf("`n  deployment:")
    $job = if ($i -ge 0) { $wf.Substring($i) } else { '' }
    Yes 'release-files.yml records the Deployment in a job of its own' ($job -match 'Record-Deployment\.ps1 -Tag \$env:RELEASE_TAG')
    Yes '  only while the repository is public' ($job -match "if: \`$\{\{ github\.event\.repository\.private == false \}\}")
    Yes '  on GitHub''s hosted runner, never the box' ($job -match 'runs-on: ubuntu-latest' -and $job -notmatch 'self-hosted')
    Yes '  with deployments: write and contents: read only' ($job -match 'deployments: write' -and $job -match 'contents: read' -and $job -notmatch 'contents: write')
    Yes '  with main''s script, and the tag passed through env' ($job -match 'ref: \$\{\{ github\.event\.repository\.default_branch \}\}' -and $job -match 'RELEASE_TAG: ')
    Yes '  and the run''s own address as the status''s log' ($job -match 'LOG_URL: \$\{\{ github\.server_url \}\}/\$\{\{ github\.repository \}\}/actions/runs/\$\{\{ github\.run_id \}\}' -and $job -match '-LogUrl \$env:LOG_URL')
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
Write-Host ''
Write-Host "$($script:pass) passed, $($script:fail) failed"
exit $(if ($script:fail) { 1 } else { 0 })
