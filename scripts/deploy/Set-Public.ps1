<#
  Set-Public.ps1

  The flip (#4013, #3721): makes EvilPatrick06/Thornswood public through the
  box's GitHub App, after taking off it the copies of the box's secrets that
  moved to the private ops repository with the box's workflows (#4039). From
  a cloud thread, One or a developer's PC.

      pwsh scripts/deploy/Set-Public.ps1 -Check     change nothing; say what it would take
      pwsh scripts/deploy/Set-Public.ps1            do it
      pwsh scripts/deploy/Set-Public.ps1 -Run <id>  the answer of a run that had not ended

  WHY THE APP. A cloud thread's proxy refuses the visibility switch and every
  secrets and environments path (measured 30 Oct 2026, 10:53 PM UTC: HTTP 403
  on actions/runners, actions/secrets and environments), and Patrick said
  that evening the flip is not done on One. The box's admin service holds
  the App's key (scripts\vps\admin\admin.js), so this starts github-admin.yml
  on the ops repository's main with ask = go-public, the way
  Set-BuildRunners.ps1 does, and reads its answer. What it does is fixed in
  admin.js and never comes from here, -Check aside.

  WHAT THE SERVICE DOES (admin.js, go-public). It reads first, with read-only
  tokens, and stops with nothing changed while a runner is still registered
  to the public repository (#3792), while the ops repository lacks its own
  CLOUDFLARE_TURNSTILE_TOKEN, notices NOTICE_KEY_B64 or desk DESK_KEY_B64, or
  while the App lacks the Secrets or Environments write the deletes need.
  Then it deletes the public repository's CLOUDFLARE_TURNSTILE_TOKEN, its
  desk environment's DESK_KEY_B64 and its notices environment, and only once
  those are gone switches it to public, and reads everything back. desk and
  its NEXUS_API_KEY stay, for nexus-run.yml. Run again once done, it changes
  nothing. The switch cannot be taken back.

  WHY THE RUN DOES NOT CHECK THE PUBLIC MAIN OUT. Until the switch, the ops
  repository's own token cannot read the public repository, so the go-public
  step of github-admin.yml asks the service by itself, without the checkout
  every other ask uses.

  WHAT IT SAYS AND EXITS.
    MATCHES, or CHANGED <n>          0, with the service's lines
    DIFFERS <n> (-Check)             1, with what it would take
    refused, or the service stopped  1, with why
    the run had not ended            2, after -WaitMinutes; -Run <id> reads it
#>
[CmdletBinding(DefaultParameterSetName = 'Ask')]
param(
    # Change nothing; say what it would take and exit 1 when anything is left.
    [Parameter(ParameterSetName = 'Ask')]
    [switch]$Check,
    # A github-admin run that had not ended: read its answer.
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)]
    [long]$Run,
    [int]$WaitMinutes = 15,
    # Where github-admin.yml and the VPS runners are (#4013).
    [string]$GitHubRepo = 'EvilPatrick06/Thornswood-Ops'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\ops\WorkflowRun.ps1')

$workflow = 'github-admin.yml'
$title = 'Set-Public'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Die "there is no gh here to start $workflow with. Install GitHub CLI from https://cli.github.com and run gh auth login. Nothing was changed." }
$again = 'pwsh scripts/deploy/Set-Public.ps1 -Run '

function Read-Answer([long]$id, [switch]$Started) {
    $a = Read-ThornswoodRunAnswer -Repo $GitHubRepo -Workflow $workflow -Run $id -Title $title -WaitMinutes $WaitMinutes -Started:$Started -Say { param($m) Say $m 'DarkGray' }
    switch ($a.State) {
        'answer' { return $a.Text }
        'waiting' {
            Say ("the run has not ended after $WaitMinutes minutes (it was " + $a.Text + '), so every VPS runner on the ops repository is busy or none is registered there yet. It still does it when one takes it.') 'Yellow'
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
    $inputs = [ordered]@{ check = $(if ($Check) { 'true' } else { 'false' }); ask = 'go-public' }
    try { $started = Start-ThornswoodWorkflow -Repo $GitHubRepo -Workflow $workflow -Inputs $inputs }
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
    '^MATCHES$' { Say 'EvilPatrick06/Thornswood is public and holds none of the box''s secrets.' 'Green'; exit 0 }
    '^CHANGED (\d+)$' { Say ('Done: ' + $Matches[1] + ' change(s), above. EvilPatrick06/Thornswood is public.') 'Green'; exit 0 }
    '^DIFFERS (\d+)$' { Say ($Matches[1] + ' thing(s) left, above. pwsh scripts/deploy/Set-Public.ps1 does them; the switch cannot be taken back.') 'Yellow'; exit 1 }
}
Die ("the run answered '" + $said[0] + "', which is none of the answers this knows.")
