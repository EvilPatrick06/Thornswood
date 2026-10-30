<#
  test-3534-order-on-filing.ps1

      pwsh -NoProfile -File .\tests\test-3534-order-on-filing.ps1

  WHY THIS EXISTS. Issue #3534. Patrick chose on 27 Oct 2026 that every open
  issue carries an Order and that a new issue gets one when it is filed.
  .github\workflows\order-on-filing.yml does that: 10000 plus the issue's
  number, set on the board with the board token.

  What it checks:
    1. the workflow: started only by a new issue, the run's token given
       nothing, the board token from the board environment, on a VPS runner
       with a timeout, no checkout and no action, and nothing from the event
       pasted into the script;
    2. its step, run in a child pwsh against a stand-in for GitHub's GraphQL:
       a new card gets Order 10000 plus the number; a card that already has an
       Order keeps it and nothing is set; a board with no Order field, a board
       error, no token and no issue number each stop it, and none of them
       sets anything.

  Nothing connects anywhere. Everything it writes is in its own temp folder.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here

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

$wf = Join-Path $repo '.github/workflows/order-on-filing.yml'
Yes 'order-on-filing.yml is there' (Test-Path -LiteralPath $wf)
if (-not (Test-Path -LiteralPath $wf)) { Done }

# ---- 1. the workflow -----------------------------------------------------------
Write-Host ''; Write-Host 'the workflow'
$y = [IO.File]::ReadAllText($wf) -replace "`r`n", "`n"
$code = (@($y -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
$on = [regex]::Match($code, '(?ms)^on:\n(.*?)^\S').Groups[1].Value
Yes 'started only by a new issue' ($on -match '(?m)^  issues:\n    types: \[opened\]\s*$' -and @([regex]::Matches($on, '(?m)^  \S')).Count -eq 1)
Yes 'the run''s token is given nothing' ($code -match '(?m)^permissions:\s*\{\}\s*$' -and $code -notmatch '(?m)^\s+permissions:' -and $code -notmatch 'github\.token')
Yes 'the board token, from the board environment' ($code -match '(?m)^    environment: board$' -and $code.Contains('BOARD_TOKEN: ${{ secrets.BOARD_TOKEN }}') -and @([regex]::Matches($code, 'secrets\.')).Count -eq 1)
Yes 'on any VPS runner, with a timeout' ($code -match '(?m)^    runs-on: \[self-hosted, Windows, thornswood-vps\]$' -and $code -match '(?m)^    timeout-minutes: \d+$')
Yes 'no checkout and no action' ($code -notmatch 'uses:')
Yes 'the issue comes in through the environment' ($code.Contains('ISSUE: ${{ github.event.issue.number }}') -and $code.Contains('ISSUE_NODE: ${{ github.event.issue.node_id }}'))
$step = [regex]::Match($code, '(?ms)- name: Set the card''s Order to 10000 plus the issue''s number\n.*?run: \|\n(.*)$').Groups[1].Value
Yes '  and nothing is pasted into the script' ($step.Length -gt 0 -and $step -notmatch '\$\{\{')
$stepScript = (@($step -split "`n" | ForEach-Object { $_ -replace '^          ', '' }) -join "`n")

# ---- 2. the step ---------------------------------------------------------------
Write-Host ''; Write-Host 'the step'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-3534o-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
# The stand-in answers GraphQL as the board would, by SCENARIO, and writes
# every call it is given to calls.jsonl.
$standIn = @'
function Invoke-RestMethod {
    param([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Body)
    $q = $Body | ConvertFrom-Json
    Add-Content -LiteralPath $env:CALLS -Value (@{ uri = $Uri; auth = $Headers.Authorization; query = $q.query; vars = $q.variables } | ConvertTo-Json -Depth 8 -Compress)
    $s = $env:SCENARIO
    if ($q.query -like 'query*') {
        if ($s -eq 'error') { return [pscustomobject]@{ errors = @([pscustomobject]@{ message = 'Something went wrong' }) } }
        $field = if ($s -eq 'no field') { $null } else { [pscustomobject]@{ id = 'F_order'; dataType = 'NUMBER' } }
        return [pscustomobject]@{ data = [pscustomobject]@{ user = [pscustomobject]@{ projectV2 = [pscustomobject]@{ id = 'P_1'; order = $field } } } }
    }
    if ($q.query -like '*addProjectV2ItemById*') {
        $had = if ($s -eq 'has order') { [pscustomobject]@{ number = 24.5 } } else { $null }
        return [pscustomobject]@{ data = [pscustomobject]@{ addProjectV2ItemById = [pscustomobject]@{ item = [pscustomobject]@{ id = 'I_7'; fieldValueByName = $had } } } }
    }
    if ($q.query -like '*updateProjectV2ItemFieldValue*') { return [pscustomobject]@{ data = [pscustomobject]@{ updateProjectV2ItemFieldValue = [pscustomobject]@{ projectV2Item = [pscustomobject]@{ id = 'I_7' } } } } }
    throw "the stand-in was asked something it does not know: $($q.query)"
}
'@
$child = Join-Path $tmp 'step.ps1'
[IO.File]::WriteAllText($child, $standIn + "`n" + $stepScript)
$pw = (Get-Process -Id $PID).Path
function Step([string]$scenario, [string]$issue = '4321', [string]$token = 'board-token-here') {
    $calls = Join-Path $tmp ($scenario.Replace(' ', '-') + '-' + [guid]::NewGuid().ToString('N') + '.jsonl')
    $names = 'SCENARIO', 'CALLS', 'BOARD_TOKEN', 'BOARD_OWNER', 'BOARD_NUMBER', 'ISSUE', 'ISSUE_NODE'
    $was = @{}; foreach ($n in $names) { $was[$n] = [Environment]::GetEnvironmentVariable($n) }
    try {
        $env:SCENARIO = $scenario; $env:CALLS = $calls; $env:BOARD_TOKEN = $token; $env:BOARD_OWNER = 'EvilPatrick06'
        $env:BOARD_NUMBER = '1'; $env:ISSUE = $issue; $env:ISSUE_NODE = 'I_kwNode'
        $o = @(& $pw -NoProfile -File $child 2>&1 | ForEach-Object { "$_" })
        $rc = $LASTEXITCODE
    } finally { foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $was[$n]) } }
    $c = @(); if (Test-Path -LiteralPath $calls) { $c = @(Get-Content -LiteralPath $calls | ForEach-Object { $_ | ConvertFrom-Json }) }
    return [pscustomobject]@{ Code = $rc; Out = ($o -join "`n"); Calls = $c; Sets = @($c | Where-Object { $_.query -like '*updateProjectV2ItemFieldValue*' }) }
}

try {
    $r = Step 'new'
    Yes ("a new card: exit 0 ($($r.Code))") ($r.Code -eq 0 -and $r.Out -match '#4321: Order set to 14321')
    Yes '  Order set once, to 10000 plus the number, on the card the board gave back' ($r.Sets.Count -eq 1 -and [double]$r.Sets[0].vars.v.number -eq 14321 -and $r.Sets[0].vars.i -eq 'I_7' -and $r.Sets[0].vars.f -eq 'F_order' -and $r.Sets[0].vars.p -eq 'P_1')
    Yes '  the issue added by its node, with the board token, to GitHub''s GraphQL only' (@($r.Calls | Where-Object { $_.query -like '*addProjectV2ItemById*' -and $_.vars.c -eq 'I_kwNode' }).Count -eq 1 -and @($r.Calls | Where-Object { $_.auth -ne 'Bearer board-token-here' -or $_.uri -ne 'https://api.github.com/graphql' }).Count -eq 0)

    $r = Step 'has order'
    Yes ("a card that has an Order keeps it: exit 0, nothing set ($($r.Code))") ($r.Code -eq 0 -and $r.Sets.Count -eq 0 -and $r.Out -match 'already has Order 24\.5; it keeps it')

    foreach ($case in @(
            @{ s = 'no field'; why = 'no number field named Order' },
            @{ s = 'error'; why = 'the board answered: Something went wrong' })) {
        $r = Step $case.s
        Yes ("$($case.s): it stops and sets nothing ($($r.Code))") ($r.Code -ne 0 -and $r.Sets.Count -eq 0 -and $r.Out -match [regex]::Escape($case.why))
    }
    $r = Step 'new' '4321' ''
    Yes ("no token: it stops before any call ($($r.Code))") ($r.Code -ne 0 -and $r.Calls.Count -eq 0 -and $r.Out -match 'BOARD_TOKEN is not set')
    $r = Step 'new' 'x'
    Yes ("no issue number: it stops before any call ($($r.Code))") ($r.Code -ne 0 -and $r.Calls.Count -eq 0 -and $r.Out -match 'named no issue number')
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
