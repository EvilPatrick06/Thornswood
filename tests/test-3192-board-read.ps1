<#
  test-3192-board-read.ps1

  The board-read workflow reads every card's Status and Order into board.json
  and keeps it as the run's artifact, changing nothing on the board, and
  scripts\ops\Read-Board.ps1 starts it and fetches that file.

  WHY THIS EXISTS. Issue #3192. A cloud Claude thread is refused GraphQL, and
  the board is read only through GraphQL, so a cloud thread could move a card
  (board-status.yml, #2863) but never see which column one was in. On 22 Oct
  2026 only 2 of 242 open issues carried a board: label. Patrick asked for the
  whole board to be reviewed from the cloud: "we make it so the cloud can".

  What it checks:
    1. the workflow is there, starts only by hand (workflow_dispatch, which
       is how Read-Board.ps1 starts it), gives its own token no permissions,
       takes the board token from the "board" environment, runs on the VPS
       runners board-status.yml uses, with a timeout, and keeps board.json as
       an artifact named board for a few days, then removes it from the
       runner however the run ended;
    2. the read script has no ${{ }} in it, and every call it can make to the
       board is a query: no mutation anywhere in the workflow;
    3. the read script, lifted out of the workflow and run in a child
       PowerShell with a stand-in Invoke-RestMethod that answers as GitHub
       would: it reads every page of cards, not only the first; it writes one
       entry per card with its repository, number, kind, title, state, Status,
       Order and archived flag, and null for a missing Status, Order or
       number (a draft card); it writes the Status options and the board's
       workflows; a missing token, an error from the board and a board with no
       Status field each fail the run and write no file;
    4. Read-Board.ps1 parses, starts board-read.yml on main and reads the
       artifact named board.

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
if (-not $Workflow) { $Workflow = Join-Path $Repo '.github\workflows\board-read.yml' }
$Reader = Join-Path $Repo 'scripts\ops\Read-Board.ps1'

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
Yes '.github\workflows\board-read.yml is there' (Test-Path -LiteralPath $Workflow)
if (-not (Test-Path -LiteralPath $Workflow)) { Done }
$text = [IO.File]::ReadAllText($Workflow) -replace "`r`n", "`n"

$on = [regex]::Match($text, '(?ms)^on:\n(.*?)^\S').Groups[1].Value
Yes 'it starts by hand (workflow_dispatch) and on nothing else' ($on -match '(?m)^\s+workflow_dispatch:\s*$' -and @([regex]::Matches($on, '(?m)^  [a-z_]+:')).Count -eq 1)
Yes 'its own token is given no permissions' ($text -match '(?m)^permissions:\s*\{\}\s*$' -and @([regex]::Matches($text, '(?m)^\s+permissions:')).Count -eq 0)
Yes 'the board token comes from the "board" environment, which only main may use' (
    $text -match '(?m)^\s+environment:\s*board\s*$' -and $text -match [regex]::Escape('BOARD_TOKEN: ${{ secrets.BOARD_TOKEN }}'))

$runsOn = [regex]::Match($text, '(?m)^\s*runs-on:\s*(.+)$').Groups[1].Value.Trim()
$status = [IO.File]::ReadAllText((Join-Path $Repo '.github\workflows\board-status.yml'))
$statusRunsOn = [regex]::Match($status, '(?m)^\s*runs-on:\s*(.+)$').Groups[1].Value.Trim()
Yes ("it runs on the VPS runners board-status uses ({0})" -f $runsOn) ($runsOn -eq '[self-hosted, Windows, thornswood-vps]' -and $runsOn -eq $statusRunsOn)
Yes '  with a timeout' ($text -match '(?m)^\s+timeout-minutes:\s*\d+\s*$')

$upload = [regex]::Match($text, '(?ms)uses: actions/upload-artifact@[0-9a-f]{40} # v\d+\n(.*?)\n\n')
Yes 'board.json is kept with upload-artifact, pinned' ($upload.Success)
Yes '  as the artifact named board' ($upload.Groups[1].Value -match '(?m)^\s+name:\s*board\s*$')
Yes '  from the folder the read step names' ($upload.Groups[1].Value -match [regex]::Escape('path: ${{ steps.read.outputs.dir }}'))
Yes '  failing when the file is not there' ($upload.Groups[1].Value -match '(?m)^\s+if-no-files-found:\s*error\s*$')
Yes '  for a few days, not the 90 GitHub keeps by default' ($upload.Groups[1].Value -match '(?m)^\s+retention-days:\s*[1-7]\s*$')
Yes 'the runner''s copy is removed however the run ended' ($text -match '(?ms)- name: Remove board\.json from the runner\n\s+if: always\(\)')

# ---- 2. nothing pasted into the script, nothing written to the board --------
$m = [regex]::Match($text, '(?ms)^\s+id: read\n.*?^(\s+)run: \|\n(.*)$')
$script = ''
if ($m.Success) {
    $lines = $m.Groups[2].Value -split "`n"
    $indent = [regex]::Match($lines[0], '^\s*').Value
    $body = @()
    foreach ($l in $lines) {
        if ($l.Trim().Length -and -not $l.StartsWith($indent)) { break }
        $body += $(if ($l.Length -ge $indent.Length) { $l.Substring($indent.Length) } else { '' })
    }
    $script = ($body -join "`n").TrimEnd() + "`n"
}
Yes 'the read step has a script' ($script.Length -gt 0)
Yes '  with no ${{ }} in it: the board''s owner and number come in through the environment' ($script -notmatch '\$\{\{')
Yes 'nothing in the workflow writes to the board: no mutation' ($text -notmatch 'mutation')
Yes '  and every call to the board is a query' (@([regex]::Matches($script, "Board '([a-z]+)")).Count -ge 2 -and @([regex]::Matches($script, "Board '([a-z]+)") | Where-Object { $_.Groups[1].Value -ne 'query' }).Count -eq 0)
Yes 'the script runs under pwsh' ($text -match '(?m)^\s+shell:\s*pwsh\s*$')

# ---- 3. the script, run against a stand-in for GitHub -----------------------
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)
Yes 'pwsh is on this machine to run the script with' ($null -ne $pwsh)
if (-not $pwsh -or -not $script) { Done }

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-board-read-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$calls = Join-Path $work 'calls.txt'
# Answers as GitHub would: the board, then its cards in two pages of
# TS_PAGE cards each (the page after names the cursor the first gave), an
# error when TS_BOARD_ERROR is set, and no Status field when TS_NO_STATUS is.
$standIn = @'
function Invoke-RestMethod {
    param([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Body)
    $b = $Body | ConvertFrom-Json
    $rec = [ordered]@{ method = $Method; uri = $Uri; auth = $Headers['Authorization']; body = $b }
    [IO.File]::AppendAllText($env:TS_CALLS, ($rec | ConvertTo-Json -Depth 8 -Compress) + "`n")
    if ($env:TS_BOARD_ERROR) { return [pscustomobject]@{ data = $null; errors = @([pscustomobject]@{ message = $env:TS_BOARD_ERROR }) } }
    if ($b.query -notmatch 'items\(') {
        $status = if ($env:TS_NO_STATUS) { $null } else { [pscustomobject]@{ options = @([pscustomobject]@{ name = 'Todo' }, [pscustomobject]@{ name = 'In Progress' }, [pscustomobject]@{ name = 'Done' }) } }
        $flows = [pscustomobject]@{ nodes = @([pscustomobject]@{ name = 'Item closed'; enabled = $true }, [pscustomobject]@{ name = 'Auto-close issue'; enabled = $false }) }
        return [pscustomobject]@{ data = [pscustomobject]@{ user = [pscustomobject]@{ projectV2 = [pscustomobject]@{ title = 'Thornswood To Do'; url = 'https://github.com/users/EvilPatrick06/projects/1'; status = $status; workflows = $flows } } } }
    }
    $repo = [pscustomobject]@{ nameWithOwner = 'EvilPatrick06/Thornswood' }
    if (-not $b.variables.c) {
        $nodes = @(
            [pscustomobject]@{ isArchived = $false; status = [pscustomobject]@{ name = 'In Progress' }; order = [pscustomobject]@{ number = 52.5 }; content = [pscustomobject]@{ __typename = 'Issue'; number = 3192; title = 'Review the board'; state = 'OPEN'; repository = $repo } }
            [pscustomobject]@{ isArchived = $false; status = $null; order = $null; content = [pscustomobject]@{ __typename = 'PullRequest'; number = 3121; title = 'SYN gate'; state = 'MERGED'; repository = $repo } })
        return [pscustomobject]@{ data = [pscustomobject]@{ user = [pscustomobject]@{ projectV2 = [pscustomobject]@{ items = [pscustomobject]@{ pageInfo = [pscustomobject]@{ hasNextPage = $true; endCursor = 'cursor-1' }; nodes = $nodes } } } } }
    }
    if ($b.variables.c -ne 'cursor-1') { throw "stand-in: unexpected cursor $($b.variables.c)" }
    $nodes = @(
        [pscustomobject]@{ isArchived = $true; status = [pscustomobject]@{ name = 'Done' }; order = [pscustomobject]@{}; content = [pscustomobject]@{ __typename = 'Issue'; number = 2863; title = 'Board labels'; state = 'CLOSED'; repository = $repo } }
        [pscustomobject]@{ isArchived = $false; status = [pscustomobject]@{ name = 'Todo' }; order = $null; content = [pscustomobject]@{ __typename = 'DraftIssue'; title = 'A draft' } })
    return [pscustomobject]@{ data = [pscustomobject]@{ user = [pscustomobject]@{ projectV2 = [pscustomobject]@{ items = [pscustomobject]@{ pageInfo = [pscustomobject]@{ hasNextPage = $false; endCursor = 'cursor-2' }; nodes = $nodes } } } } }
}

'@
$runner = Join-Path $work 'read.ps1'
[IO.File]::WriteAllText($runner, $standIn + $script)

$names = 'BOARD_TOKEN', 'BOARD_OWNER', 'BOARD_NUMBER', 'RUNNER_TEMP', 'GITHUB_RUN_ID', 'GITHUB_OUTPUT', 'TS_CALLS', 'TS_BOARD_ERROR', 'TS_NO_STATUS'
function Invoke-Read([hashtable]$extra = @{}) {
    foreach ($f in $calls, (Join-Path $work 'out.txt')) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    $temp = Join-Path $work 'runner-temp'
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $temp | Out-Null
    $keep = @{}
    foreach ($k in $names) { $keep[$k] = [Environment]::GetEnvironmentVariable($k) }
    try {
        $env:BOARD_TOKEN = 'stand-in-board-token'
        $env:BOARD_OWNER = 'EvilPatrick06'
        $env:BOARD_NUMBER = '1'
        $env:RUNNER_TEMP = $temp
        $env:GITHUB_RUN_ID = '42'
        $env:GITHUB_OUTPUT = Join-Path $work 'out.txt'
        $env:TS_CALLS = $calls
        $env:TS_BOARD_ERROR = ''
        $env:TS_NO_STATUS = ''
        foreach ($k in $extra.Keys) { [Environment]::SetEnvironmentVariable($k, $extra[$k]) }
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { $out = & $pwsh.Source -NoProfile -NonInteractive -File $runner 2>&1 | Out-String; $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $old }
    } finally {
        foreach ($k in $keep.Keys) { [Environment]::SetEnvironmentVariable($k, $keep[$k]) }
    }
    $made = @()
    if (Test-Path -LiteralPath $calls) { $made = @(Get-Content -LiteralPath $calls | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }) }
    $file = Join-Path (Join-Path $temp 'board-read-42') 'board.json'
    $board = if (Test-Path -LiteralPath $file) { [IO.File]::ReadAllText($file) | ConvertFrom-Json } else { $null }
    $said = if (Test-Path -LiteralPath (Join-Path $work 'out.txt')) { [IO.File]::ReadAllText((Join-Path $work 'out.txt')) } else { '' }
    return [pscustomobject]@{ Code = $code; Out = $out; Calls = $made; Board = $board; Output = $said; Dir = (Join-Path $temp 'board-read-42') }
}

try {
    $r = Invoke-Read
    Yes ("a board of two pages: the run passes (exit {0})" -f $r.Code) ($r.Code -eq 0)
    Yes ("  three calls to the board, each with the board token ({0})" -f $r.Calls.Count) ($r.Calls.Count -eq 3 -and @($r.Calls | Where-Object { $_.auth -ne 'Bearer stand-in-board-token' -or $_.uri -ne 'https://api.github.com/graphql' }).Count -eq 0)
    Yes '  it reads board 1 of EvilPatrick06' ($r.Calls[0].body.variables.o -eq 'EvilPatrick06' -and $r.Calls[0].body.variables.n -eq 1)
    Yes '  the first page asks from the start, the second from the cursor the first gave' ($null -eq $r.Calls[1].body.variables.c -and $r.Calls[2].body.variables.c -eq 'cursor-1')
    Yes '  board.json is written, and the step names its folder' ($null -ne $r.Board -and $r.Output -match ('dir=' + [regex]::Escape($r.Dir)))
    if ($r.Board) {
        $b = $r.Board
        Yes '  with when it was read and the board it is' ($b.read_at -and $b.board.url -eq 'https://github.com/users/EvilPatrick06/projects/1' -and $b.board.title -eq 'Thornswood To Do' -and $b.board.number -eq 1)
        Yes '  the Status options in board order' ((@($b.statuses) -join '|') -eq 'Todo|In Progress|Done')
        Yes '  and the board''s workflows, on or off' (@($b.workflows).Count -eq 2 -and @($b.workflows | Where-Object { $_.name -eq 'Auto-close issue' -and -not $_.enabled }).Count -eq 1)
        $items = @($b.items)
        Yes ("  one entry for every card on both pages ({0})" -f $items.Count) ($items.Count -eq 4)
        $i = @($items | Where-Object { $_.number -eq 3192 })
        Yes '  an issue card has its repository, number, kind, title, state, Status and Order' (
            $i.Count -eq 1 -and $i[0].repo -eq 'EvilPatrick06/Thornswood' -and $i[0].kind -eq 'Issue' -and $i[0].title -eq 'Review the board' -and $i[0].state -eq 'OPEN' -and $i[0].status -eq 'In Progress' -and $i[0].order -eq 52.5 -and $i[0].archived -eq $false)
        $p = @($items | Where-Object { $_.number -eq 3121 })
        Yes '  a pull request card with no Status or Order has null for both' ($p.Count -eq 1 -and $p[0].kind -eq 'PullRequest' -and $p[0].state -eq 'MERGED' -and $null -eq $p[0].status -and $null -eq $p[0].order)
        $a = @($items | Where-Object { $_.number -eq 2863 })
        Yes '  an archived card says so, and an empty Order is null' ($a.Count -eq 1 -and $a[0].archived -eq $true -and $a[0].status -eq 'Done' -and $null -eq $a[0].order)
        $d = @($items | Where-Object { $_.kind -eq 'DraftIssue' })
        Yes '  a draft card has its title and null for repository and number' ($d.Count -eq 1 -and $d[0].title -eq 'A draft' -and $null -eq $d[0].repo -and $null -eq $d[0].number)
    }
    Yes '  the log says how many cards and how many in each Status' ($r.Out -match 'read 4 cards from https://github.com/users/EvilPatrick06/projects/1' -and $r.Out -match '\(no Status\): 1' -and $r.Out -match 'In Progress: 1')

    $r = Invoke-Read @{ BOARD_TOKEN = '' }
    Yes ("no board token fails the run, says so, makes no call and writes no file (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Out -match 'BOARD_TOKEN is not set' -and $r.Calls.Count -eq 0 -and $null -eq $r.Board)

    $r = Invoke-Read @{ TS_BOARD_ERROR = 'Your token has not been granted the required scopes' }
    Yes ("an error from the board fails the run, says it, and writes no file (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Out -match 'the board answered: Your token has not been granted' -and $null -eq $r.Board)

    $r = Invoke-Read @{ TS_NO_STATUS = '1' }
    Yes ("a board with no Status field fails the run and writes no file (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Out -match 'no single-select field named Status' -and $null -eq $r.Board)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 4. Read-Board.ps1 ------------------------------------------------------
Yes 'scripts\ops\Read-Board.ps1 is there' (Test-Path -LiteralPath $Reader)
if (Test-Path -LiteralPath $Reader) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($Reader, [ref]$null, [ref]$errs)
    Yes '  it parses' (@($errs).Count -eq 0)
    $rt = [IO.File]::ReadAllText($Reader)
    Yes '  it starts board-read.yml on main' ($rt -match [regex]::Escape("`$workflow = 'board-read.yml'") -and $rt -match [regex]::Escape("ref = 'main'") -and $rt -match [regex]::Escape('actions/workflows/$workflow/dispatches'))
    Yes '  and reads the artifact named board' ($rt -match [regex]::Escape("`$_.name -eq 'board'"))
    Yes '  writing the zip through a file, not a PowerShell pipe, which would change its bytes' ($rt -match '-RedirectStandardOutput \$zip')
}

Done
