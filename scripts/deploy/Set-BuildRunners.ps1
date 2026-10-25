<#
  Set-BuildRunners.ps1

  Makes the labels on GitHub's VPS runners match the runner records on main
  (records\<name>-runners.json): records\build-runners.json caps how many
  builds run on the box at once, records\sign-runners.json says which runner
  may sign a release launcher. From One, a developer's PC or a cloud thread.

      pwsh scripts/deploy/Set-BuildRunners.ps1            make GitHub match main's records
      pwsh scripts/deploy/Set-BuildRunners.ps1 -Check     change nothing; exit 1 when GitHub differs
      pwsh scripts/deploy/Set-BuildRunners.ps1 -Run <id>  the answer of a run that had not ended

  A record is { "label": ..., "runners": [1, 2] }: the runners it lists
  (thornswood-vps is 1, thornswood-vps-<n> is n) carry the label and no other
  runner does, an off-box runner (thornswood-pr-*) never. Changing one is a
  pull request to the record; once it merges, .github\workflows\github-admin.yml
  runs by itself and GitHub matches it a minute later. This script is for
  asking again, or for -Check.

  WHY THE BUILD LABEL (#2994). The VPS has six cores and, from 20 October,
  eight runners (#2929; three since the evening of 21 October, #3108,
  #3219). Every heavy job asked for thornswood-vps, which all eight carried,
  so on the night of 20 to 21 October seven builds ran at once, each one's
  harness step stretched from about 15 minutes to 34 to 39, and the job's
  40-minute limit cancelled three pull requests' builds that were passing.
  Measured over 558 box jobs: past four at once the box finishes no more
  builds an hour (11.1 at four, 11.6 at seven), each one only takes longer.
  So the heavy jobs (the build fallbacks in build.yml and build-pr.yml, the
  engine fallback, the nightly checks) ask for the build label as well, and
  only the runners records\build-runners.json lists carry it. The light
  jobs (board cards, dropped claims, the release jobs) still run on any VPS
  runner, so they never wait behind a build.

  HOW (#3107, Patrick's A of 22 Oct 2026). A runner's labels can be changed
  only by somebody who administers the repository, and a cloud thread's proxy
  refuses every actions/runners path, so this no longer calls GitHub's
  runner API itself. It starts github-admin.yml on main, waits, and prints
  the runner's answer, the way Set-Ref.ps1 does. That run hands GitHub's OIDC
  token for it to the box's admin service (scripts\vps\admin\admin.js,
  Install-AdminService.ps1), which holds the key of a GitHub App made for
  Thornswood and nothing else does. The service checks the token is that
  workflow on main, reads the records from main itself, and makes the labels
  match. What to change never comes from here, so nobody can label a runner
  any way main does not say. A job already running is not touched.

  The service refuses to leave GitHub with no registered runner carrying a
  record's label, because every job asking for it would then wait for a
  runner that never comes. A record that names a label every VPS runner
  carries, lists no runners, or names a label another record names, stops
  it. tests\test-3107-admin.js runs the service's rules; #2161 (one runner
  at a time): a runner outside the build list runs only the light jobs, so
  to prove one, add its number to the record in the same pull request that
  moves the rollout to it.

  WHAT IT SAYS AND EXITS.
    MATCHES, or CHANGED <n>          0, with the service's lines
    DIFFERS <n> (-Check)             1, with what differs
    refused, or the service stopped  1, with why
    the run had not ended            2, after -WaitMinutes; -Run <id> reads it
  -OnGitHub is the workflow's half; it writes the answer as an annotation
  titled Set-BuildRunners.
#>
[CmdletBinding(DefaultParameterSetName = 'Ask')]
param(
    # Change nothing; say what differs and exit 1 when anything does.
    [Parameter(ParameterSetName = 'Ask')]
    [switch]$Check,
    # A github-admin run that had not ended: read its answer.
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)]
    [long]$Run,
    # The workflow's half: asks the box's admin service with this run's
    # OIDC token. -Check comes from ADMIN_CHECK there.
    [Parameter(ParameterSetName = 'OnGitHub', Mandatory = $true)]
    [switch]$OnGitHub,
    [int]$WaitMinutes = 15,
    [string]$GitHubRepo = 'EvilPatrick06/Thornswood'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\ops\WorkflowRun.ps1')

$workflow = 'github-admin.yml'
$title = 'Set-BuildRunners'
# The audience admin.js takes, and nothing else does.
$audience = 'thornswood-admin'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-ThornswoodAnnotation 'error' $title $m; Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

# ======================================================== the GitHub half ===
if ($OnGitHub) {
    $askCheck = ($env:ADMIN_CHECK -eq 'true')
    if (-not $env:ACTIONS_ID_TOKEN_REQUEST_URL -or -not $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN) {
        Die 'this run has no OIDC token to ask for: github-admin.yml has to give the job id-token: write. Nothing was changed.'
    }
    $port = if ($env:THORNSWOOD_ADMIN_PORT) { [int]$env:THORNSWOOD_ADMIN_PORT } else { 7791 }

    $sep = if ($env:ACTIONS_ID_TOKEN_REQUEST_URL.Contains('?')) { '&' } else { '?' }
    $t = Invoke-WebRequest -Uri ($env:ACTIONS_ID_TOKEN_REQUEST_URL + $sep + 'audience=' + $audience) -SkipHttpErrorCheck -TimeoutSec 60 `
        -Headers @{ Authorization = "bearer $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN" }
    $token = ''
    if ([int]$t.StatusCode -eq 200) { $token = [string](([string]$t.Content | ConvertFrom-Json).value) }
    if (-not $token) { Die ('GitHub gave this run no OIDC token (HTTP ' + $t.StatusCode + '). Nothing was changed.') }

    # The service is on this machine; nothing between here and it.
    $a = Invoke-WebRequest -Method POST -Uri "http://127.0.0.1:$port/converge" -SkipHttpErrorCheck -NoProxy -TimeoutSec 120 `
        -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json' `
        -Body (ConvertTo-Json -Compress @{ what = 'runner-labels'; check = $askCheck })
    $code = [int]$a.StatusCode
    $r = $null
    try { $r = [string]$a.Content | ConvertFrom-Json } catch { $r = $null }
    if (-not $r -or -not $r.PSObject.Properties['lines']) {
        Die ("the box's admin service on 127.0.0.1:$port did not answer as itself (HTTP $code). Install-AdminService.ps1 -Status says whether it is there. Nothing was changed.")
    }
    $lines = @($r.lines | ForEach-Object { [string]$_ })
    foreach ($l in $lines) { Say "  $l" }
    if ($code -eq 200 -and $r.ok) {
        $head = if ($askCheck -and [int]$r.differs) { 'DIFFERS ' + $r.differs } elseif ([int]$r.changed) { 'CHANGED ' + $r.changed } else { 'MATCHES' }
        Write-ThornswoodAnnotation 'notice' $title (@($head) + $lines -join "`n")
        Say $head 'Green'
        exit 0
    }
    Die ((@("the box's admin service said no (HTTP $code)") + $lines) -join "`n")
}

# ======================================================= the session half ===
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Die "there is no gh here to start $workflow with. Install GitHub CLI from https://cli.github.com and run gh auth login. Nothing was changed." }
$again = 'pwsh scripts/deploy/Set-BuildRunners.ps1 -Run '

function Read-Answer([long]$id, [switch]$Started) {
    $a = Read-ThornswoodRunAnswer -Repo $GitHubRepo -Workflow $workflow -Run $id -Title $title -WaitMinutes $WaitMinutes -Started:$Started -Say { param($m) Say $m 'DarkGray' }
    switch ($a.State) {
        'answer' { return $a.Text }
        'waiting' {
            Say ("the run has not ended after $WaitMinutes minutes (it was " + $a.Text + '), so every VPS runner is busy. It still does it when one takes it.') 'Yellow'
            Say ('  its answer then: ' + $again + $id) 'DarkGray'
            if ($a.Url) { Say ('  ' + $a.Url) 'DarkGray' }
            exit 2
        }
        'unread' {
            if (-not $Started) { Die $a.Text }
            Say ("GitHub started run $id, and the run does it. Its answer was not read here: " + $a.Text) 'Yellow'
            Say ('  its answer: ' + $again + $id) 'DarkGray'
            exit 2
        }
        'stopped' { Die ($a.Text + "`n(" + $a.Url + ')') }
        'other' { Die ($a.Text + '.') }
    }
    Die ($a.Text + ', so nothing it knows of was changed. Its log says why: ' + $a.Url)
}

if ($PSCmdlet.ParameterSetName -eq 'Run') {
    $answer = Read-Answer $Run
} else {
    try { $started = Start-ThornswoodWorkflow -Repo $GitHubRepo -Workflow $workflow -Inputs ([ordered]@{ check = $(if ($Check) { 'true' } else { 'false' }) }) }
    catch { Die ($_.Exception.Message + '. Nothing was changed.') }
    if (-not $started.Run) {
        Say ("GitHub started $workflow, but named no run" + ', so its answer cannot be read here. Its runs: ' + $started.Url) 'Yellow'
        exit 2
    }
    Say ("sent to $workflow" + ': ' + $started.Url) 'DarkGray'
    $answer = Read-Answer $started.Run -Started
}

$said = @("$answer" -split "`n")
foreach ($l in @($said | Select-Object -Skip 1)) { Say "  $l" }
switch -Regex ($said[0]) {
    '^MATCHES$' { Say 'GitHub matches main''s runner records.' 'Green'; exit 0 }
    '^CHANGED (\d+)$' { Say ('GitHub matches main''s runner records now; ' + $Matches[1] + ' label(s) changed.') 'Green'; exit 0 }
    '^DIFFERS (\d+)$' { Say ('GitHub differs from main''s runner records in ' + $Matches[1] + ' place(s), above. pwsh scripts/deploy/Set-BuildRunners.ps1 puts it right.') 'Yellow'; exit 1 }
}
Die ("the run answered '" + $said[0] + "', which is none of the answers this knows.")
