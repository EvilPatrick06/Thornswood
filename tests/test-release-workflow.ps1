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

  SWITCHED OVER (#3312, Patrick, 22 Oct 2026: "it needs to work like the VPS
  runners where VPS is the fallback and the GitHub runner is first", and
  "for signing it will use runner 3"). GitHub's hosted runner builds and
  signs first; the box takes a release up when the hosted job is refused or
  fails, and signs it on runner 3 alone, through the same OIDC identity, with
  no Azure CLI and no sign in kept on the box. A v<a.b.c.d> tag is a dev
  number release.yml writes into Updater.cs, and release-tag.yml makes the
  tag a cloud Ship cannot push. This checks that shape, and that the runner
  that signs is never one the verify job or a build runs on.

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
Yes 'a manual run can ask for either runner (runner input: hosted or vps)' ($top.Contains('options: [hosted, vps]'))
Yes 'workflow-level permissions are contents: write only, no id-token for every job' ($top -match "(?m)^permissions:\n  contents: write\n" -and -not (($top -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n").Contains('id-token'))
Yes 'one concurrency group per tag, however the run started (v1.1.96 got two drafts when it was per ref)' ($top.Contains('group: release-${{ github.event.inputs.tag || github.ref_name }}') -and $top.Contains('cancel-in-progress: false'))

# ---- hosted first, the box as the fallback (#3312) ----------------------------
$hosted = Get-Job 'launcher'
Yes 'a manual run defaults to GitHub''s runner' ($top -match "(?m)^        default: hosted$")
Yes 'the hosted job runs unless BUILD_RUNNER or a manual run asks for the box, as build.yml''s does' ($hosted.Contains("if: `${{ vars.BUILD_RUNNER != 'vps' && inputs.runner != 'vps' }}"))

# ---- the hosted job -----------------------------------------------------------
Yes 'there is a hosted job "launcher"' ($hosted -ne '')
Yes '  it runs on GitHub''s windows-latest, the image the build check proves every PR' ($hosted -match '(?m)^    runs-on: windows-latest$')
Yes '  it holds id-token: write and contents: write at job level' ($hosted -match '(?m)^    permissions:\n      contents: write\n      id-token: write$')
Yes '  the release environment only on a refs/tags/v ref' ($hosted.Contains("environment: `${{ startsWith(github.ref, 'refs/tags/v') && 'release' || '' }}"))
Yes '  it hands the verify job the release id, the commit and whether it signed' ($hosted.Contains('release_id: ${{ steps.draft.outputs.release_id }}') -and $hosted.Contains('commit: ${{ steps.tag.outputs.commit }}') -and $hosted.Contains('signed: ${{ steps.draft.outputs.signed }}'))
Yes '  its steps are the shared anchor' ($hosted -match '(?m)^    steps: &release$')

# ---- the steps ----------------------------------------------------------------
$fetch = Get-Step $wf 'Fetch the signing client'
$sign = Get-Step $wf 'Sign the launcher'
$clean = Get-Step $wf 'Take the signing setup off'
$gate = "if: `${{ startsWith(github.ref, 'refs/tags/v') }}"
Yes 'no azure/login: the box keeps no Azure sign in after the job (#3312)' (-not ($code -match 'azure/login'))
Yes 'the signing client is fetched on a v tag ref, on either runner' ($fetch.Contains($gate))
Yes '  with the pin from Setup-ShipMachine.ps1, not a second copy' ($fetch.Contains("'Get-SigningClientPin'") -and -not ($fetch -match '[0-9a-f]{64}'))
Yes 'the sign step has the same gate and signs -Required' ($sign.Contains($gate) -and $sign.Contains('Sign-Artifact.ps1 -Path $exe -Required'))
Yes '  with the app and tenant ids from repository variables, no secret' ($sign.Contains('AZURE_CLIENT_ID: ${{ vars.AZURE_SIGNING_CLIENT_ID }}') -and $sign.Contains('AZURE_TENANT_ID: ${{ vars.AZURE_SIGNING_TENANT_ID }}') -and -not ($sign -match 'secrets\.|CLIENT_SECRET|client-secret'))
Yes '  asks GitHub for the OIDC token with the audience Azure trusts' ($sign.Contains("&audience=api://AzureADTokenExchange") -and $sign.Contains('ACTIONS_ID_TOKEN_REQUEST_TOKEN'))
Yes '  masks it and names it to the signing client as a workload identity file' ($sign.Contains("'::add-mask::' + `$answer.value") -and $sign.Contains('$env:AZURE_FEDERATED_TOKEN_FILE = $tokenFile'))
Yes '  and removes the file in a finally, whatever signtool did' ($sign -match '(?s)\} finally \{\s*Remove-Item -LiteralPath \$tokenFile')
Yes '  and reads the signature back, Valid and timestamped' ($sign.Contains("`$sig.Status -ne 'Valid'") -and $sign.Contains('TimeStamperCertificate'))
Yes '  and does not sign setup-stub.exe (Package signs the finished Setup)' (-not ($sign -match 'setup-stub'))
Yes 'the signing setup comes off the runner after every run, failed ones too' ($clean.Contains('if: ${{ always() }}') -and $clean.Contains('records\signing\signing.json') -and $clean.Contains('records\signing\client'))
Yes 'no step in release.yml reads a secret but the repository token' (-not (($wf -replace '\$\{\{ github\.token \}\}', '') -match 'secrets\.'))
$num = Get-Step $wf 'Put the tag''s number in Updater.cs'
Yes 'a v<a.b.c.d> tag writes its dev number into Updater.cs with Ship.ps1''s own replace' ($num.Contains("`$src -replace 'Version\s*=\s*`"[^`"]+`"', ('Version = `"' + `$want + '`"')"))
Yes '  a v<a.b.c> tag must be the number Updater.cs already says' ($num.Contains('if ($have -ne $want)'))
Yes '  and a dev number is never below the commit''s own' ($num.Contains('-lt [version]$have'))
$build = Get-Step $wf 'Build the launcher into RUNNER_TEMP'
Yes 'the build is MSBuild on either runner, with no -With (#498 switched)' ($build.Contains('Build-Launcher.ps1 -Root $root -NoSign -NoPause') -and $build -notmatch '-With\b' -and $build -notmatch "'csc'")
$iBuild = $wf.IndexOf('- name: Build the launcher into RUNNER_TEMP')
$iFetch = $wf.IndexOf('- name: Fetch the signing client')
$iNum = $wf.IndexOf("- name: Put the tag's number in Updater.cs")
$iClean = $wf.IndexOf('- name: Take the signing setup off')
$iSign = $wf.IndexOf('- name: Sign the launcher')
$iSums = $wf.IndexOf('- name: Collect the exe')
$iDraft = $wf.IndexOf('- name: Draft a release')
Yes 'order: number, build, fetch the client, sign, SHA256SUMS, draft, clean up (sums name the signed bytes)' ($iNum -gt 0 -and $iNum -lt $iBuild -and $iBuild -lt $iFetch -and $iFetch -lt $iSign -and $iSign -lt $iSums -and $iSums -lt $iDraft -and $iDraft -lt $iClean)

# ---- one draft per tag --------------------------------------------------------
$draft = Get-Step $wf 'Draft a release'
Yes 'the draft step has an id the outputs read' ($draft -match '(?m)^        id: draft$')
Yes 'it never looks a draft up by /releases/tags/ (that endpoint never returns a draft)' (-not ($code -match 'releases/tags/'))
Yes '  it reads the releases list page by page instead' ($draft.Contains('releases?per_page=100&page=$page') -and $draft.Contains('$_.tag_name -eq $tag'))
Yes '  and stops when the tag has more than one release, naming them' ($draft.Contains('if ($same.Count -gt 1)') -and $draft.Contains('gh api -X DELETE repos/$repo/releases/<id>'))
Yes '  and never replaces the files of a published release' ($draft.Contains('if (-not $release.draft)'))
Yes '  and rewrites an existing draft''s notes with the files it uploads (a signed rebuild kept saying UNSIGNED)' ($draft.Contains('-Method Patch -Uri "$api/releases/$($release.id)"') -and $draft.Contains('@{ body = $notes }'))
Yes '  and the VPS notes name MSBuild, not the csc #498 retired' ($draft.Contains("'built on the VPS runner with MSBuild (#498)") -and -not $draft.Contains('csc'))
Yes '  and an unsigned draft says UNSIGNED, whichever runner built it' ($draft.Contains("else { `$how += ', UNSIGNED (not a v tag ref)"))
Yes '  and writes release_id and signed for the verify job' ($draft.Contains('"release_id=" + $release.id') -and $draft.Contains('("signed=" +'))

# ---- the VPS job --------------------------------------------------------------
$vps = Get-Job 'launcher-vps'
Yes 'there is a VPS job "launcher-vps"' ($vps -ne '')
Yes '  it needs the hosted job' ($vps -match '(?m)^    needs: launcher$')
Yes '  it runs when the hosted job did not succeed (skipped included) and the run was not cancelled (!cancelled, #2422)' ($vps.Contains("if: `${{ !cancelled() && needs.launcher.result != 'success' && needs.launcher.result != 'cancelled' }}"))
Yes '  on the signing runner only, by its exact labels (thornswood-sign, runner 3)' ($vps -match '(?m)^    runs-on: \[self-hosted, Windows, X64, thornswood-vps, thornswood-sign\]$')
Yes '  with id-token: write and contents: write at job level' ($vps -match '(?m)^    permissions:\n      contents: write\n      id-token: write$')
Yes '  the release environment only on a refs/tags/v ref, as the hosted job' ($vps.Contains("environment: `${{ startsWith(github.ref, 'refs/tags/v') && 'release' || '' }}"))
Yes '  and hands the verify job the release id, the commit and whether it signed' ($vps.Contains('release_id: ${{ steps.draft.outputs.release_id }}') -and $vps.Contains('commit: ${{ steps.tag.outputs.commit }}') -and $vps.Contains('signed: ${{ steps.draft.outputs.signed }}'))
Yes '  and with the hosted job''s own steps' ($vps -match '(?m)^    steps: \*release$')

# ---- the second machine -------------------------------------------------------
$ver = Get-Job 'verify'
Yes 'there is a "verify" job' ($ver -ne '')
Yes '  it runs after whichever job drafted a signed launcher' ($ver -match '(?m)^    needs: \[launcher, launcher-vps\]$' -and $ver.Contains("(needs.launcher.result == 'success' && needs.launcher.outputs.signed == 'true') || (needs.launcher-vps.result == 'success' && needs.launcher-vps.outputs.signed == 'true')"))
Yes '  on a build runner, never the runner that signs' ($ver -match '(?m)^    runs-on: \[self-hosted, Windows, thornswood-vps, thornswood-build\]$')
Yes '  without id-token or the release environment' (-not $ver.Contains('id-token') -and -not $ver.Contains('environment:'))
Yes '  it checks out the commit the draft was built from, by the job that built it' ($ver.Contains('ref: ${{ env.DRAFT_COMMIT }}') -and $ver.Contains("DRAFT_COMMIT: `${{ needs.launcher.result == 'success' && needs.launcher.outputs.commit || needs.launcher-vps.outputs.commit }}"))
Yes '  downloads each file by its asset id' ($ver.Contains('releases/assets/$($a[0].id)') -and $ver.Contains("Accept = 'application/octet-stream'"))
Yes '  and runs Test-ReleaseFiles.ps1 -RequireSigned, failing on a refusal' ($ver.Contains('Test-ReleaseFiles.ps1 -Dir $dir -RequireSigned') -and $ver.Contains('if ($LASTEXITCODE -ne 0)'))
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $WorkflowPath))
Yes '  and that script is in the repository' (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts/release/Test-ReleaseFiles.ps1'))

# ---- the runner that signs is no other job's (#3312) --------------------------
$recDir = Join-Path $repoRoot 'records'
$signRec = Join-Path $recDir 'sign-runners.json'
$buildRec = Join-Path $recDir 'build-runners.json'
Yes 'records/sign-runners.json names the label the VPS job asks for' ((Test-Path -LiteralPath $signRec) -and ((Get-Content -LiteralPath $signRec -Raw | ConvertFrom-Json).label -eq 'thornswood-sign'))
if ((Test-Path -LiteralPath $signRec) -and (Test-Path -LiteralPath $buildRec)) {
    $signers = @((Get-Content -LiteralPath $signRec -Raw | ConvertFrom-Json).runners | ForEach-Object { [int]$_ })
    $builders = @((Get-Content -LiteralPath $buildRec -Raw | ConvertFrom-Json).runners | ForEach-Object { [int]$_ })
    Yes ("  it lists runner(s) {0}, and the build runners {1} are none of them" -f ($signers -join ', '), ($builders -join ', ')) ($signers.Count -gt 0 -and -not @($signers | Where-Object { $builders -contains $_ }).Count)
}

# ---- release-tag.yml makes the tag a cloud Ship cannot push (#3312) ------------
$tpath = Join-Path (Split-Path -Parent $WorkflowPath) 'release-tag.yml'
Yes 'release-tag.yml is there' (Test-Path -LiteralPath $tpath)
if (Test-Path -LiteralPath $tpath) {
    $t = [IO.File]::ReadAllText($tpath).Replace("`r`n", "`n")
    $tcode = (($t -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
    Yes '  workflow_dispatch only' ($tcode -match '(?m)^on:\n  workflow_dispatch:' -and -not ($tcode -match '(?m)^\s+(push|pull_request(_target)?|schedule):'))
    Yes '  from main only' ($tcode.Contains("if: `${{ github.ref == 'refs/heads/main' }}"))
    Yes '  with no id-token and no secret' (-not $tcode.Contains('id-token') -and -not (($tcode -replace '\$\{\{ github\.token \}\}', '') -match 'secrets\.'))
    Yes '  holds the tag to v<a.b.c> or v<a.b.c.d> and the commit to a full SHA' ($tcode.Contains("'^v\d+\.\d+\.\d+(\.\d+)?$'") -and $tcode.Contains("'^[0-9a-f]{40}$'"))
    Yes '  holds the commit to main through GitHub''s compare' ($tcode.Contains('compare/$commit...main') -and $tcode.Contains("-notin 'identical', 'ahead'"))
    Yes '  never moves a tag that is already on another commit' ($tcode.Contains('if ($sha -ne $commit)'))
    Yes '  and starts release.yml on the tag, with the commit as expected_sha' ($tcode.Contains('actions/workflows/release.yml/dispatches') -and $tcode.Contains('ref = $tag') -and $tcode.Contains('expected_sha = $commit'))
    Yes '  runs no repository code (no checkout)' (-not $tcode.Contains('actions/checkout'))
}

# ---- build.yml agrees ---------------------------------------------------------
$bpath = Join-Path (Split-Path -Parent $WorkflowPath) 'build.yml'
if (Test-Path -LiteralPath $bpath) {
    $b = [IO.File]::ReadAllText($bpath).Replace("`r`n", "`n")
    Yes 'build.yml uses BUILD_RUNNER for its fallback, the switch release.yml takes at the switch-over' ($b.Contains("vars.BUILD_RUNNER != 'vps'"))
    Yes 'build.yml''s fallback runs on the same label, on a build runner (#2994)' ($b -match 'runs-on: \[self-hosted, Windows, (X64, )?thornswood-vps, thornswood-build\]')
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
