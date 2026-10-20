<#
  test-2863-board-status.ps1

  A board: label sets the issue's Status on the board, an order: label its
  Order, and the label comes off.

  WHY THIS EXISTS. Issue #2863. A cloud Claude thread is refused GraphQL, and
  the board's fields change only through GraphQL, so until this only "Releases
  and deploys" on One could move a card. A cloud thread can add a label over
  REST, and .github\workflows\board-status.yml carries the label out (Patrick,
  19 Oct 2026: "we need to make it so it works in the cloud").

  What it checks:
    1. the workflow is there, runs when an issue gets a label and on nothing
       else, only for a label that begins "board:" or "order:", with a token that can only
       edit issues, the board token from the "board" environment, one run per
       issue at a time with none cancelled while it runs (a queue on the job, so
       a run for another label never joins it), on the VPS runners
       the other workflows use (#437), with a timeout;
    2. it checks out nothing and runs no action, and the label and issue reach
       the script through the environment: no ${{ }} inside the script;
    3. the script itself, lifted out of the workflow and run in a child
       PowerShell with a stand-in Invoke-RestMethod that answers as GitHub
       would and writes down each call instead of making it: the Status named
       on the label is set on the issue's card, whatever its case, spaces or
       hyphens; every board: label on the issue comes off and no other label
       is touched; an order: label sets the Order number, and every order:
       label on the issue is deleted from the repository; something that is
       not a number, or a board with no Order field, fails the run; a Status the board does not have, a missing token, an error
       from the board and a refused label removal each fail the run, and the
       ones that fail before the Status is set touch no label.

  It never reaches GitHub. Read only apart from files under its own temp
  folder.
#>
[CmdletBinding()]
param([string]$Workflow)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $Workflow) { $Workflow = Join-Path $Repo '.github\workflows\board-status.yml' }

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

# ---- 1. the workflow --------------------------------------------------------
Yes '.github\workflows\board-status.yml is there' (Test-Path -LiteralPath $Workflow)
if (-not (Test-Path -LiteralPath $Workflow)) { Done }
$text = [IO.File]::ReadAllText($Workflow) -replace "`r`n", "`n"

$on = [regex]::Match($text, '(?ms)^on:\n(.*?)^\S').Groups[1].Value
Yes 'it runs when an issue gets a label' ($on -match '(?m)^\s+issues:\s*$' -and $on -match 'types:\s*\[\s*labeled\s*\]')
Yes '  and on nothing else' (@([regex]::Matches($on, '(?m)^  [a-z_]+:')).Count -eq 1)
Yes '  and only for a label that begins "board:" or "order:", so every other label takes no runner' (
    $text -match [regex]::Escape("if: `${{ startsWith(github.event.label.name, 'board:') || startsWith(github.event.label.name, 'order:') }}"))

$perm = [regex]::Match($text, '(?ms)^permissions:\n(.*?)^\S').Groups[1].Value
$grants = @([regex]::Matches($perm, '(?m)^\s+([a-z-]+):\s*(\S+)') | ForEach-Object { $_.Groups[1].Value + ': ' + $_.Groups[2].Value })
Yes ("its own token can edit issues and nothing else ({0})" -f ($grants -join ', ')) ($grants.Count -eq 1 -and $grants[0] -eq 'issues: write')
Yes '  and no job widens it' (@([regex]::Matches($text, '(?m)^\s+permissions:')).Count -eq 0)
Yes 'the board token comes from the "board" environment, which only main may use' (
    $text -match '(?m)^\s+environment:\s*board\s*$' -and $text -match [regex]::Escape('BOARD_TOKEN: ${{ secrets.BOARD_TOKEN }}'))

Yes 'the queue is on the job, so a run for another label never joins it' ($text -notmatch '(?m)^concurrency:')
$conc = [regex]::Match($text, '(?ms)^    concurrency:\n(.*?)^    \S').Groups[1].Value
Yes 'runs for one issue go one at a time' ($conc -match [regex]::Escape('group: board-status-${{ github.event.issue.number }}'))
Yes '  and a running one is never cancelled' ($conc -match '(?m)^\s+cancel-in-progress:\s*false\s*$')

$runsOn = [regex]::Match($text, '(?m)^\s*runs-on:\s*(.+)$').Groups[1].Value.Trim()
$drop = [IO.File]::ReadAllText((Join-Path $Repo '.github\workflows\drop-claims.yml'))
$dropRunsOn = [regex]::Match($drop, '(?m)^\s*runs-on:\s*(.+)$').Groups[1].Value.Trim()
Yes ("it runs on the VPS runners drop-claims uses ({0})" -f $runsOn) ($runsOn -eq '[self-hosted, Windows, thornswood-vps]' -and $runsOn -eq $dropRunsOn)
Yes '  with a timeout' ($text -match '(?m)^\s+timeout-minutes:\s*\d+\s*$')

# ---- 2. nothing from the repository, nothing pasted into the script ---------
Yes 'it checks out nothing and runs no action' ($text -notmatch '(?m)^\s*(-\s+)?uses:')
$run = [regex]::Match($text, '(?ms)^(\s+)run: \|\n(.*)$')
Yes 'it has one script' ($run.Success -and @([regex]::Matches($text, '(?m)^\s+run:')).Count -eq 1)
$script = ''
if ($run.Success) {
    $lines = $run.Groups[2].Value -split "`n"
    $indent = [regex]::Match($lines[0], '^\s*').Value
    $body = @()
    foreach ($l in $lines) {
        if ($l.Trim().Length -and -not $l.StartsWith($indent)) { break }
        $body += $(if ($l.Length -ge $indent.Length) { $l.Substring($indent.Length) } else { '' })
    }
    $script = ($body -join "`n").TrimEnd() + "`n"
}
Yes 'the script has no ${{ }} in it: the label and issue come in through the environment' ($script.Length -gt 0 -and $script -notmatch '\$\{\{')
Yes '  as LABEL, ISSUE and ISSUE_NODE out of the event' (
    $text -match [regex]::Escape('LABEL: ${{ github.event.label.name }}') -and
    $text -match [regex]::Escape('ISSUE: ${{ github.event.issue.number }}') -and
    $text -match [regex]::Escape('ISSUE_NODE: ${{ github.event.issue.node_id }}'))
Yes '  with the run''s own token beside them for the labels' ($text -match [regex]::Escape('GH_TOKEN: ${{ github.token }}'))
Yes 'the script runs under pwsh' ($text -match '(?m)^\s+shell:\s*pwsh\s*$')

# ---- 3. the script, run against a stand-in for GitHub -----------------------
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)
Yes 'pwsh is on this machine to run the script with' ($null -ne $pwsh)
if (-not $pwsh -or -not $script) { Done }

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-board-status-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$calls = Join-Path $work 'calls.txt'
# Defined before the script, so the script's Invoke-RestMethod is this one.
# It writes down each call, one line of JSON, and answers as GitHub would: the
# board with the options in TS_OPTIONS, the issue's labels from TS_LABELS, an
# error from the board when TS_BOARD_ERROR is set, and a 500 for the removal
# of the label named in TS_BROKEN.
$standIn = @'
function Invoke-RestMethod {
    param([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Body)
    $rec = [ordered]@{ method = $Method; uri = $Uri; auth = $Headers['Authorization'] }
    if ($Body) { $rec.body = $Body | ConvertFrom-Json }
    [IO.File]::AppendAllText($env:TS_CALLS, ($rec | ConvertTo-Json -Depth 8 -Compress) + "`n")
    if ($Uri -eq 'https://api.github.com/graphql') {
        if ($env:TS_BOARD_ERROR) { return [pscustomobject]@{ data = $null; errors = @([pscustomobject]@{ message = $env:TS_BOARD_ERROR }) } }
        $q = ($Body | ConvertFrom-Json).query
        if ($q -match '^query') {
            $opts = @($env:TS_OPTIONS -split '\|' | ForEach-Object { [pscustomobject]@{ id = 'opt-' + ($_ -replace ' ', '_'); name = $_ } })
            $order = if ($env:TS_NO_ORDER) { $null } else { [pscustomobject]@{ id = 'PVTF_order'; dataType = 'NUMBER' } }
            return [pscustomobject]@{ data = [pscustomobject]@{ user = [pscustomobject]@{ projectV2 = [pscustomobject]@{ id = 'PVT_board'; status = [pscustomobject]@{ id = 'PVTSSF_status'; options = $opts }; order = $order } } } }
        }
        if ($q -match 'addProjectV2ItemById') { return [pscustomobject]@{ data = [pscustomobject]@{ addProjectV2ItemById = [pscustomobject]@{ item = [pscustomobject]@{ id = 'PVTI_card' } } } } }
        if ($q -match 'updateProjectV2ItemFieldValue') { return [pscustomobject]@{ data = [pscustomobject]@{ updateProjectV2ItemFieldValue = [pscustomobject]@{ projectV2Item = [pscustomobject]@{ id = 'PVTI_card' } } } } }
        throw "stand-in: unexpected query $q"
    }
    if ($Method -eq 'Get') { return @(($env:TS_LABELS | ConvertFrom-Json) | ForEach-Object { [pscustomobject]@{ name = $_ } }) }
    $name = [Uri]::UnescapeDataString(($Uri -split '/labels/')[1])
    if ($env:TS_BROKEN -and $name -eq $env:TS_BROKEN) {
        $res = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]'InternalServerError')
        throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success.', $res)
    }
    if ($env:TS_GONE -and $name -eq $env:TS_GONE) {
        $res = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]'NotFound')
        throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success.', $res)
    }
    return [pscustomobject]@{}
}

'@
$runner = Join-Path $work 'status.ps1'
[IO.File]::WriteAllText($runner, $standIn + $script)

$names = 'BOARD_TOKEN', 'GH_TOKEN', 'BOARD_OWNER', 'BOARD_NUMBER', 'ISSUE', 'ISSUE_NODE', 'LABEL', 'GITHUB_REPOSITORY', 'TS_CALLS', 'TS_OPTIONS', 'TS_LABELS', 'TS_BOARD_ERROR', 'TS_BROKEN', 'TS_GONE', 'TS_NO_ORDER'
function Invoke-Status([string]$label, [string[]]$onIssue, [hashtable]$extra = @{}) {
    if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls -Force }
    $keep = @{}
    foreach ($k in $names) { $keep[$k] = [Environment]::GetEnvironmentVariable($k) }
    try {
        $env:BOARD_TOKEN = 'stand-in-board-token'
        $env:GH_TOKEN = 'stand-in-run-token'
        $env:BOARD_OWNER = 'EvilPatrick06'
        $env:BOARD_NUMBER = '1'
        $env:ISSUE = '2863'
        $env:ISSUE_NODE = 'I_issue2863'
        $env:LABEL = $label
        $env:GITHUB_REPOSITORY = 'EvilPatrick06/Thornswood'
        $env:TS_CALLS = $calls
        $env:TS_OPTIONS = 'Todo|In Progress|Done'
        $env:TS_LABELS = ConvertTo-Json -InputObject @($onIssue) -Compress
        $env:TS_BOARD_ERROR = ''
        $env:TS_BROKEN = ''
        $env:TS_GONE = ''
        $env:TS_NO_ORDER = ''
        foreach ($k in $extra.Keys) { [Environment]::SetEnvironmentVariable($k, $extra[$k]) }
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $out = & $pwsh.Source -NoProfile -NonInteractive -File $runner 2>&1 | Out-String; $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $old }
    } finally {
        foreach ($k in $keep.Keys) { [Environment]::SetEnvironmentVariable($k, $keep[$k]) }
    }
    $made = @()
    if (Test-Path -LiteralPath $calls) { $made = @(Get-Content -LiteralPath $calls | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }) }
    $set = @($made | Where-Object { $_.PSObject.Properties['body'] -and $_.body.query -match 'updateProjectV2ItemFieldValue' })
    $dels = @($made | Where-Object { $_.method -eq 'Delete' -and $_.uri -like '*/issues/*' } | ForEach-Object { [Uri]::UnescapeDataString(($_.uri -split '/labels/')[1]) })
    $gone = @($made | Where-Object { $_.method -eq 'Delete' -and $_.uri -notlike '*/issues/*' } | ForEach-Object { [Uri]::UnescapeDataString(($_.uri -split '/labels/')[1]) })
    return [pscustomobject]@{ Code = $code; Out = $out; Calls = $made; Set = $set; Deleted = $dels; LabelGone = $gone }
}
$labelsUri = 'https://api.github.com/repos/EvilPatrick06/Thornswood/issues/2863/labels'

try {
    $r = Invoke-Status 'board: In Progress' @('board: In Progress', 'area: GitHub & CI', 'claimed: Claude')
    Yes ("board: In Progress: the run passes (exit {0})" -f $r.Code) ($r.Code -eq 0)
    $q = @($r.Calls | Where-Object { $_.uri -eq 'https://api.github.com/graphql' })
    Yes ("  three calls to the board, each with the board token ({0})" -f $q.Count) ($q.Count -eq 3 -and @($q | Where-Object { $_.auth -ne 'Bearer stand-in-board-token' }).Count -eq 0)
    Yes '  it reads board 1 of EvilPatrick06' ($q[0].body.variables.o -eq 'EvilPatrick06' -and $q[0].body.variables.n -eq 1 -and $q[0].body.query -match 'field\(name:"Status"\)')
    Yes '  it finds the card by adding the issue it was given' ($q[1].body.query -match 'addProjectV2ItemById' -and $q[1].body.variables.p -eq 'PVT_board' -and $q[1].body.variables.c -eq 'I_issue2863')
    Yes '  and sets that card''s Status field to In Progress' (
        $r.Set.Count -eq 1 -and $r.Set[0].body.variables.i -eq 'PVTI_card' -and $r.Set[0].body.variables.f -eq 'PVTSSF_status' -and $r.Set[0].body.variables.v.singleSelectOptionId -eq 'opt-In_Progress')
    Yes '  and says so' ($r.Out -match '#2863: Status set to In Progress')
    $rest = @($r.Calls | Where-Object { $_.uri -like "$labelsUri*" })
    Yes '  the label calls use the run''s own token' ($rest.Count -ge 1 -and @($rest | Where-Object { $_.auth -ne 'Bearer stand-in-run-token' }).Count -eq 0)
    Yes ("  the board label comes off, and no other ({0})" -f ($r.Deleted -join ', ')) ($r.Deleted.Count -eq 1 -and $r.Deleted[0] -eq 'board: In Progress')
    Yes '  its name escaped into the address' (@($r.Calls | Where-Object { $_.method -eq 'Delete' -and $_.uri -eq "$labelsUri/board%3A%20In%20Progress" }).Count -eq 1)

    foreach ($spelling in 'board: in-progress', 'board:IN PROGRESS', 'Board: In  Progress ') {
        $r = Invoke-Status $spelling @($spelling)
        Yes ("'{0}' is In Progress too (exit {1})" -f $spelling, $r.Code) ($r.Code -eq 0 -and $r.Set.Count -eq 1 -and $r.Set[0].body.variables.v.singleSelectOptionId -eq 'opt-In_Progress')
    }

    $r = Invoke-Status 'board: Done' @('board: Done')
    Yes ("board: Done sets Done (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Set[0].body.variables.v.singleSelectOptionId -eq 'opt-Done')

    $r = Invoke-Status 'board: Done' @('board: In Progress', 'board: Done', 'wave: 2 This week')
    Yes ("an older board label waiting on the issue comes off with this one, and the card takes this one (exit {0})" -f $r.Code) (
        $r.Code -eq 0 -and $r.Set[0].body.variables.v.singleSelectOptionId -eq 'opt-Done' -and $r.Deleted.Count -eq 2 -and ($r.Deleted -contains 'board: In Progress') -and ($r.Deleted -contains 'board: Done'))

    $r = Invoke-Status 'board: Done' @()
    Yes ("a run whose label an earlier run already took off still sets the Status and removes nothing (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Set.Count -eq 1 -and $r.Deleted.Count -eq 0)

    $r = Invoke-Status 'board: Done' @('board: Done') @{ TS_GONE = 'board: Done' }
    Yes ("a label gone between the read and the removal (404) is said and passed over (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Out -match 'board: Done was already off #2863')

    # The board has Todo, In Progress and Done. "Completed" was Patrick's word
    # for Done (19 Oct), and a label naming it must not pass for anything.
    $r = Invoke-Status 'board: Completed' @('board: Completed')
    Yes ("a Status the board does not have fails the run (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Set.Count -eq 0)
    Yes '  says which ones it has' ($r.Out -match "no Status 'Completed'; it has: Todo, In Progress, Done")
    Yes '  and leaves the label on, so it shows it was not carried out' ($r.Deleted.Count -eq 0)

    $r = Invoke-Status 'board: ' @('board: ')
    Yes ("a label with no Status after the colon fails the run and touches nothing (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Calls.Count -eq 0)

    $r = Invoke-Status 'board: In Progress' @('board: In Progress') @{ BOARD_TOKEN = '' }
    Yes ("no board token fails the run, says so, and makes no call (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Out -match 'BOARD_TOKEN is not set' -and $r.Calls.Count -eq 0)

    $r = Invoke-Status 'board: In Progress' @('board: In Progress') @{ TS_BOARD_ERROR = 'Your token has not been granted the required scopes' }
    Yes ("an error from the board fails the run, says it, and touches no label (exit {0})" -f $r.Code) (
        $r.Code -ne 0 -and $r.Out -match 'the board answered: Your token has not been granted' -and $r.Deleted.Count -eq 0 -and $r.Set.Count -eq 0)

    # ---- order: ------------------------------------------------------------
    $r = Invoke-Status 'order: 52.5' @('order: 52.5', 'board: Done', 'area: Gamemode')
    Yes ("order: 52.5: the run passes (exit {0})" -f $r.Code) ($r.Code -eq 0)
    Yes '  and sets the card''s Order field to 52.5, a number' (
        $r.Set.Count -eq 1 -and $r.Set[0].body.variables.f -eq 'PVTF_order' -and $r.Set[0].body.variables.v.number -eq 52.5 -and @($r.Set[0].body.variables.v.PSObject.Properties).Count -eq 1)
    Yes '  and says so' ($r.Out -match '#2863: Order set to 52.5')
    Yes ("  the order label is deleted from the repository, which takes it off the issue ({0})" -f ($r.LabelGone -join ', ')) ($r.LabelGone.Count -eq 1 -and $r.LabelGone[0] -eq 'order: 52.5')
    Yes '  its name escaped into the address' (@($r.Calls | Where-Object { $_.method -eq 'Delete' -and $_.uri -eq 'https://api.github.com/repos/EvilPatrick06/Thornswood/labels/order%3A%2052.5' }).Count -eq 1)
    Yes '  and the board label and every other label are left alone' ($r.Deleted.Count -eq 0)

    $r = Invoke-Status 'Order:7' @('Order:7')
    Yes ("'Order:7' sets 7 (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Set[0].body.variables.v.number -eq 7)

    $r = Invoke-Status 'order: 3' @('order: 9', 'order: 3')
    Yes ("an older order label waiting on the issue is deleted with this one, and the card takes this one (exit {0})" -f $r.Code) (
        $r.Code -eq 0 -and $r.Set[0].body.variables.v.number -eq 3 -and $r.LabelGone.Count -eq 2 -and ($r.LabelGone -contains 'order: 9') -and ($r.LabelGone -contains 'order: 3'))

    $r = Invoke-Status 'order: 12' @() @{ TS_GONE = 'order: 12' }
    Yes ("a run whose label an earlier run already deleted still sets the Order, and GitHub's 404 for the label is said and passed over (exit {0})" -f $r.Code) (
        $r.Code -eq 0 -and $r.Set.Count -eq 1 -and $r.LabelGone.Count -eq 1 -and $r.Out -match 'the label order: 12 was already deleted')

    foreach ($bad in 'order: soon', 'order: 1,5', 'order: NaN', 'order: Infinity') {
        $r = Invoke-Status $bad @($bad)
        Yes ("'{0}' is not an Order: the run fails and touches nothing on the board or the labels (exit {1})" -f $bad, $r.Code) ($r.Code -ne 0 -and $r.Set.Count -eq 0 -and $r.LabelGone.Count -eq 0 -and $r.Deleted.Count -eq 0)
    }

    $r = Invoke-Status 'order: 4' @('order: 4') @{ TS_NO_ORDER = '1' }
    Yes ("a board with no number field named Order fails the run and says so (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Out -match 'no number field named Order' -and $r.Set.Count -eq 0)

    $r = Invoke-Status 'order: 4' @('order: 4') @{ TS_BROKEN = 'order: 4' }
    Yes ("a refused label deletion fails the run (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Out -notmatch 'deleted the label order: 4')

    $r = Invoke-Status 'board: In Progress' @('board: In Progress') @{ TS_BROKEN = 'board: In Progress' }
    Yes ("a refused label removal fails the run (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Out -notmatch 'took board: In Progress off')
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Done
