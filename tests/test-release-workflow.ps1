<#
  test-release-workflow.ps1

      pwsh -NoProfile -File .\tests\test-release-workflow.ps1

  The shape of .github\workflows\release.yml after #2163 and #498: where the
  release launcher is built, who may sign it, the VPS job, the one draft per
  tag (#2462), and the second machine that checks a signed draft.

  WHY. Patrick's decisions of 12 Oct on #2163: release.yml builds on GitHub's
  hosted Windows runner, with #498's MSBuild switch in the same change, and
  signs there through a federated Azure identity limited to v tags. The VPS
  stays the backup for every GitHub runner build, the same way build.yml has
  it. Each of those is one line of YAML that a later edit could drop without
  any other check going red, and the cost of losing one is a release built on
  the wrong machine, or an id-token handed to a run that is not a release.

  BEFORE THE SWITCH-OVER. Until a hosted run has been proven (GitHub refuses
  hosted jobs on billing, #2393; the launcher itself has been built by MSBuild
  since 1.2.4.5, #498), the box still builds every release and the hosted
  job runs only on a manual run that asks for it. This checks that state.
  The switch-over changes the hosted job's "if" and the runner input's
  default (release.yml header, WHERE IT RUNS); this test's two "until the
  switch-over" checks change with it, and say what they become.

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
# One step's text, by the start of its name, up to the next step or job.
function Get-Step([string]$text, [string]$nameStart) {
    return [regex]::Match($text, ("(?ms)^      - name: " + [regex]::Escape($nameStart) + "[^\n]*\n(.*?)(?=^      - name:|^  \S|\z)")).Value
}
# The text before "jobs:", the workflow-level settings.
$top = $wf.Substring(0, [Math]::Max(0, $wf.IndexOf("`njobs:`n")))
$code = (($wf -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")

# ---- triggers -----------------------------------------------------------------
Yes 'release.yml has no pull_request trigger (no PR run may reach the signing identity)' (-not ($top -match '(?m)^\s+pull_request(_target)?:'))
Yes 'a push runs it only for v* tags' ($top -match "(?m)^  push:\n    tags:\n      - 'v\*'\n" -and -not ($top -match '(?m)^    branches:'))
Yes 'a manual run can ask for either runner (runner input: vps or hosted)' ($top.Contains('options: [vps, hosted]'))
Yes 'workflow-level permissions are contents: write only, no id-token for every job' ($top -match "(?m)^permissions:\n  contents: write\n" -and -not (($top -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n").Contains('id-token'))
Yes 'one concurrency group per tag, however the run started (v1.1.96 got two drafts when it was per ref)' ($top.Contains('group: release-${{ github.event.inputs.tag || github.ref_name }}') -and $top.Contains('cancel-in-progress: false'))

# ---- until the switch-over ----------------------------------------------------
# After it: the input's default is hosted, and the hosted job's if is
# ${{ vars.BUILD_RUNNER != 'vps' && inputs.runner != 'vps' }}.
$hosted = Get-Job 'launcher'
Yes 'until the switch-over: a manual run defaults to the box' ($top -match "(?m)^        default: vps$")
Yes 'until the switch-over: the hosted job runs only when a manual run asks for it' ($hosted.Contains("if: `${{ inputs.runner == 'hosted' }}"))

# ---- the hosted job -----------------------------------------------------------
Yes 'there is a hosted job "launcher"' ($hosted -ne '')
Yes '  it runs on GitHub''s windows-latest, the image the build check proves every PR' ($hosted -match '(?m)^    runs-on: windows-latest$')
Yes '  it holds id-token: write and contents: write at job level' ($hosted -match '(?m)^    permissions:\n      contents: write\n      id-token: write$')
Yes '  the release environment only on a refs/tags/v ref' ($hosted.Contains("environment: `${{ startsWith(github.ref, 'refs/tags/v') && 'release' || '' }}"))
Yes '  it hands the verify job the release id, the commit and whether it signed' ($hosted.Contains('release_id: ${{ steps.draft.outputs.release_id }}') -and $hosted.Contains('commit: ${{ steps.tag.outputs.commit }}') -and $hosted.Contains('signed: ${{ steps.draft.outputs.signed }}'))
Yes '  its steps are the shared anchor' ($hosted -match '(?m)^    steps: &release$')

# ---- the steps ----------------------------------------------------------------
$fetch = Get-Step $wf 'Fetch the signing client'
$login = Get-Step $wf 'Sign in to Azure'
$sign = Get-Step $wf 'Sign the launcher'
$gate = "if: `${{ runner.environment == 'github-hosted' && startsWith(github.ref, 'refs/tags/v') }}"
Yes 'azure/login is pinned to a full commit SHA' ($login -match 'uses: azure/login@[0-9a-f]{40} # v\d')
Yes '  and runs only on the hosted runner on a v tag' ($login.Contains($gate))
Yes '  with ids from repository variables, no secret, no client secret' ($login.Contains('client-id: ${{ vars.AZURE_SIGNING_CLIENT_ID }}') -and $login.Contains('tenant-id: ${{ vars.AZURE_SIGNING_TENANT_ID }}') -and $login.Contains('subscription-id: ${{ vars.AZURE_SIGNING_SUBSCRIPTION_ID }}') -and -not ($login -match 'secrets\.|client-secret|creds:'))
Yes 'the signing client is fetched under the same gate' ($fetch.Contains($gate))
Yes '  with the pin from Setup-ShipMachine.ps1, not a second copy' ($fetch.Contains("'Get-SigningClientPin'") -and -not ($fetch -match '[0-9a-f]{64}'))
Yes 'the sign step has the same gate and signs -Required' ($sign.Contains($gate) -and $sign.Contains('Sign-Artifact.ps1 -Path $exe -Required'))
Yes '  and does not sign setup-stub.exe (Package signs the finished Setup)' (-not ($sign -match 'setup-stub'))
Yes 'no step in release.yml reads a secret but the repository token' (-not (($wf -replace '\$\{\{ github\.token \}\}', '') -match 'secrets\.'))
$build = Get-Step $wf 'Build the launcher into RUNNER_TEMP'
Yes 'the build is MSBuild on either runner, with no -With (#498 switched)' ($build.Contains('Build-Launcher.ps1 -Root $root -NoSign -NoPause') -and $build -notmatch '-With\b' -and $build -notmatch "'csc'")
$iBuild = $wf.IndexOf('- name: Build the launcher into RUNNER_TEMP')
$iFetch = $wf.IndexOf('- name: Fetch the signing client')
$iLogin = $wf.IndexOf('- name: Sign in to Azure')
$iSign = $wf.IndexOf('- name: Sign the launcher')
$iSums = $wf.IndexOf('- name: Collect the exe')
$iDraft = $wf.IndexOf('- name: Draft a release')
Yes 'order: build, fetch the client, sign in, sign, SHA256SUMS, draft (sums name the signed bytes)' ($iBuild -gt 0 -and $iBuild -lt $iFetch -and $iFetch -lt $iLogin -and $iLogin -lt $iSign -and $iSign -lt $iSums -and $iSums -lt $iDraft)

# ---- one draft per tag --------------------------------------------------------
$draft = Get-Step $wf 'Draft a release'
Yes 'the draft step has an id the outputs read' ($draft -match '(?m)^        id: draft$')
Yes 'it never looks a draft up by /releases/tags/ (that endpoint never returns a draft)' (-not ($code -match 'releases/tags/'))
Yes '  it reads the releases list page by page instead' ($draft.Contains('releases?per_page=100&page=$page') -and $draft.Contains('$_.tag_name -eq $tag'))
Yes '  and stops when the tag has more than one release, naming them' ($draft.Contains('if ($same.Count -gt 1)') -and $draft.Contains('gh api -X DELETE repos/$repo/releases/<id>'))
Yes '  and never replaces the files of a published release' ($draft.Contains('if (-not $release.draft)'))
Yes '  and rewrites an existing draft''s notes with the files it uploads (a signed rebuild kept saying UNSIGNED)' ($draft.Contains('-Method Patch -Uri "$api/releases/$($release.id)"') -and $draft.Contains('@{ body = $notes }'))
Yes '  and the VPS notes name MSBuild, not the csc #498 retired' ($draft.Contains("'built on the VPS runner with MSBuild (#498)") -and -not $draft.Contains('csc'))
Yes '  and writes release_id and signed for the verify job' ($draft.Contains('"release_id=" + $release.id') -and $draft.Contains('("signed=" +'))

# ---- the VPS job --------------------------------------------------------------
$vps = Get-Job 'launcher-vps'
Yes 'there is a VPS job "launcher-vps"' ($vps -ne '')
Yes '  it needs the hosted job' ($vps -match '(?m)^    needs: launcher$')
Yes '  it runs when the hosted job did not succeed (skipped included) and the run was not cancelled (!cancelled, #2422)' ($vps.Contains("if: `${{ !cancelled() && needs.launcher.result != 'success' && needs.launcher.result != 'cancelled' }}"))
Yes '  on the dedicated runners only, by their exact labels' ($vps -match '(?m)^    runs-on: \[self-hosted, Windows, X64, thornswood-vps\]$')
Yes '  without id-token' (($vps -match '(?m)^    permissions:\n      contents: write$') -and -not $vps.Contains('id-token'))
Yes '  without the release environment' (-not $vps.Contains('environment:'))
Yes '  and with the hosted job''s own steps' ($vps -match '(?m)^    steps: \*release$')

# ---- the second machine -------------------------------------------------------
$ver = Get-Job 'verify'
Yes 'there is a "verify" job' ($ver -ne '')
Yes '  it runs only after the hosted job drafted a signed launcher' ($ver -match '(?m)^    needs: launcher$' -and $ver.Contains("if: `${{ needs.launcher.result == 'success' && needs.launcher.outputs.signed == 'true' }}"))
Yes '  on a VPS runner, which holds no signing setup' ($ver -match '(?m)^    runs-on: \[self-hosted, Windows, X64, thornswood-vps\]$')
Yes '  without id-token or the release environment' (-not $ver.Contains('id-token') -and -not $ver.Contains('environment:'))
Yes '  it checks out the commit the draft was built from' ($ver.Contains('ref: ${{ needs.launcher.outputs.commit }}'))
Yes '  downloads each file by its asset id' ($ver.Contains('releases/assets/$($a[0].id)') -and $ver.Contains("Accept = 'application/octet-stream'"))
Yes '  and runs Test-ReleaseFiles.ps1 -RequireSigned, failing on a refusal' ($ver.Contains('Test-ReleaseFiles.ps1 -Dir $dir -RequireSigned') -and $ver.Contains('if ($LASTEXITCODE -ne 0)'))
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $WorkflowPath))
Yes '  and that script is in the repository' (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts/release/Test-ReleaseFiles.ps1'))

# ---- build.yml agrees ---------------------------------------------------------
$bpath = Join-Path (Split-Path -Parent $WorkflowPath) 'build.yml'
if (Test-Path -LiteralPath $bpath) {
    $b = [IO.File]::ReadAllText($bpath).Replace("`r`n", "`n")
    Yes 'build.yml uses BUILD_RUNNER for its fallback, the switch release.yml takes at the switch-over' ($b.Contains("vars.BUILD_RUNNER != 'vps'"))
    Yes 'build.yml''s fallback runs on the same label' ($b -match 'runs-on: \[self-hosted, Windows, (X64, )?thornswood-vps\]')
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
