<#
  test-release-workflow.ps1

      pwsh -NoProfile -File .\tests\test-release-workflow.ps1

  The shape of .github\workflows\release.yml after #2163 and #498: where the
  release launcher is built, who may sign it, and the VPS fallback.

  WHY. Patrick's decisions of 12 Oct on #2163: release.yml builds on GitHub's
  hosted Windows runner, with #498's MSBuild switch in the same change, and
  signs there through a federated Azure identity limited to v tags. The VPS
  stays the backup for every GitHub runner build, the same way build.yml has
  it. Each of those is one line of YAML that a later edit could drop without
  any other check going red, and the cost of losing one is a release built on
  the wrong machine, or an id-token handed to a run that is not a release.

  Read only. Parses the YAML text by indentation, no module needed, so it runs
  on the VPS, the hosted runner and anywhere pwsh runs.
#>
[CmdletBinding()]
param([string]$WorkflowPath)
$env:THORNSWOOD_HARNESS = '1'
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $WorkflowPath) { $WorkflowPath = Join-Path (Split-Path -Parent $Here) '.github/workflows/release.yml' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$wf = [IO.File]::ReadAllText($WorkflowPath).Replace("`r`n", "`n")
$lines = $wf -split "`n"

# The text of one job: from "  <name>:" to the next line indented two spaces.
function Get-Job([string]$name) {
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq "  ${name}:") { $start = $i; break } }
    if ($start -lt 0) { return '' }
    $end = $lines.Count
    for ($j = $start + 1; $j -lt $lines.Count; $j++) { if ($lines[$j] -match '^  \S') { $end = $j; break } }
    return (($lines[$start..($end - 1)]) -join "`n")
}
# The text before "jobs:", the workflow-level settings.
$top = $wf.Substring(0, [Math]::Max(0, $wf.IndexOf("`njobs:`n")))

# ---- triggers -----------------------------------------------------------------
Yes 'release.yml has no pull_request trigger (no PR run may reach the signing identity)' (-not ($top -match '(?m)^\s+pull_request(_target)?:'))
Yes 'a push runs it only for v* tags' ($top -match "(?m)^  push:\n    tags:\n      - 'v\*'\n" -and -not ($top -match '(?m)^    branches:'))
Yes 'a manual run can ask for the VPS (runner input: hosted or vps)' ($top.Contains('options: [hosted, vps]') -and $top.Contains('default: hosted'))
Yes 'workflow-level permissions are contents: write only, no id-token for every job' ($top -match "(?m)^permissions:\n  contents: write\n" -and -not (($top -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n").Contains('id-token'))

# ---- the hosted job -----------------------------------------------------------
$hosted = Get-Job 'launcher'
Yes 'there is a hosted job "launcher"' ($hosted -ne '')
Yes '  it runs on GitHub''s windows-latest, the image the build check proves every PR' ($hosted -match '(?m)^    runs-on: windows-latest$')
Yes '  it is skipped when BUILD_RUNNER is vps or a manual run asked for the box' ($hosted.Contains("if: `${{ vars.BUILD_RUNNER != 'vps' && inputs.runner != 'vps' }}"))
Yes '  it holds id-token: write and contents: write at job level' ($hosted -match '(?m)^    permissions:\n      contents: write\n      id-token: write$')
Yes '  the release environment only on a refs/tags/v ref' ($hosted.Contains("environment: `${{ startsWith(github.ref, 'refs/tags/v') && 'release' || '' }}"))
Yes '  its steps are the shared anchor' ($hosted -match '(?m)^    steps: &release$')

# ---- the steps ----------------------------------------------------------------
$login = [regex]::Match($wf, "(?ms)^      - name: Sign in to Azure[^\n]*\n(.*?)(?=^      - name:|\z)").Value
$sign = [regex]::Match($wf, "(?ms)^      - name: Sign the launcher[^\n]*\n(.*?)(?=^      - name:|\z)").Value
$gate = "if: `${{ runner.environment == 'github-hosted' && startsWith(github.ref, 'refs/tags/v') }}"
Yes 'azure/login is pinned to a full commit SHA' ($login -match 'uses: azure/login@[0-9a-f]{40} # v\d')
Yes '  and runs only on the hosted runner on a v tag' ($login.Contains($gate))
Yes '  with ids from repository variables, no secret, no client secret' ($login.Contains('client-id: ${{ vars.AZURE_SIGNING_CLIENT_ID }}') -and $login.Contains('tenant-id: ${{ vars.AZURE_SIGNING_TENANT_ID }}') -and $login.Contains('subscription-id: ${{ vars.AZURE_SIGNING_SUBSCRIPTION_ID }}') -and -not ($login -match 'secrets\.|client-secret|creds:'))
Yes 'the sign step has the same gate and signs -Required' ($sign.Contains($gate) -and $sign.Contains('Sign-Artifact.ps1 -Path $exe -Required'))
Yes '  it takes the signing client pin from Setup-ShipMachine.ps1, not a second copy' ($sign.Contains("'Get-SigningClientPin'") -and -not ($sign -match '[0-9a-f]{64}'))
Yes '  and does not sign setup-stub.exe (Package signs the finished Setup)' (-not ($sign -match 'setup-stub'))
Yes 'no step in release.yml reads a secret but the repository token' (-not (($wf -replace '\$\{\{ github\.token \}\}', '') -match 'secrets\.'))
$build = [regex]::Match($wf, "(?ms)^      - name: Build the launcher into RUNNER_TEMP\n(.*?)(?=^      - name:|\z)").Value
Yes 'the build uses MSBuild on GitHub''s runner, csc on the VPS (#498)' ($build.Contains("if (`$env:RUNNER_KIND -eq 'github-hosted') { `$with = 'msbuild' }") -and $build.Contains("`$with = 'csc'") -and $build.Contains('-With $with -NoSign'))
$iBuild = $wf.IndexOf('- name: Build the launcher into RUNNER_TEMP')
$iSign = $wf.IndexOf('- name: Sign the launcher')
$iSums = $wf.IndexOf('- name: Collect the exe')
$iDraft = $wf.IndexOf('- name: Draft a release')
Yes 'order: build, sign, then SHA256SUMS, then the draft (sums name the signed bytes)' ($iBuild -gt 0 -and $iBuild -lt $iSign -and $iSign -lt $iSums -and $iSums -lt $iDraft)

# ---- the VPS fallback ---------------------------------------------------------
$vps = Get-Job 'launcher-vps'
Yes 'there is a VPS fallback job "launcher-vps"' ($vps -ne '')
Yes '  it needs the hosted job' ($vps -match '(?m)^    needs: launcher$')
Yes '  it runs when the hosted job did not succeed and the run was not cancelled (!cancelled, #2422)' ($vps.Contains("if: `${{ !cancelled() && needs.launcher.result != 'success' && needs.launcher.result != 'cancelled' }}"))
Yes '  on the dedicated runners only, by their exact labels' ($vps -match '(?m)^    runs-on: \[self-hosted, Windows, X64, thornswood-vps\]$')
Yes '  without id-token' (($vps -match '(?m)^    permissions:\n      contents: write$') -and -not $vps.Contains('id-token'))
Yes '  without the release environment' (-not $vps.Contains('environment:'))
Yes '  and with the hosted job''s own steps' ($vps -match '(?m)^    steps: \*release$')

# ---- build.yml agrees ---------------------------------------------------------
$bpath = Join-Path (Split-Path -Parent $WorkflowPath) 'build.yml'
if (Test-Path -LiteralPath $bpath) {
    $b = [IO.File]::ReadAllText($bpath).Replace("`r`n", "`n")
    Yes 'build.yml uses the same switch, BUILD_RUNNER, for its fallback' ($b.Contains("vars.BUILD_RUNNER != 'vps'"))
    Yes 'build.yml''s fallback runs on the same label' ($b -match 'runs-on: \[self-hosted, Windows, (X64, )?thornswood-vps\]')
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
