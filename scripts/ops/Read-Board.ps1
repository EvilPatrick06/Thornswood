<#
  Read-Board.ps1

  Reads the whole board, every card's Status and Order, into board.json, from
  a machine that has gh and no board token: a cloud Claude thread (#3192).

      pwsh scripts/ops/Read-Board.ps1
      pwsh scripts/ops/Read-Board.ps1 -OutFile temp/board-review/board.json
      pwsh scripts/ops/Read-Board.ps1 -Run 39712345678

  A cloud thread is refused GraphQL, and the board is read only through
  GraphQL, so this starts .github/workflows/board-read.yml on main, which
  reads the board with the board token on a VPS runner, waits for the run to
  end, downloads the "board" artifact the run leaves and writes its
  board.json to -OutFile. The workflow's header says what the file holds.
  Nothing on the board changes.

  -Run reads the artifact of a run already started, for when the wait ran out
  before a runner took it.

  Exits:
    0  board.json written; the path and the count per Status are printed
    1  stopped, and the line before says why
    2  the run had not ended in -WaitMinutes; the line to read it later is
       printed
#>
[CmdletBinding(DefaultParameterSetName = 'Start')]
param(
    [Parameter(ParameterSetName = 'Run', Mandatory = $true)][long]$Run,
    [string]$OutFile,
    [int]$WaitMinutes = 15,
    [string]$GitHubRepo = 'EvilPatrick06/Thornswood'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$workflow = 'board-read.yml'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Die 'there is no gh here to start the board-read workflow with.' }
if (-not $OutFile) { $OutFile = Join-Path ([IO.Path]::GetTempPath()) 'thornswood-board.json' }
$OutFile = [IO.Path]::GetFullPath($OutFile)

# One GET, its answer as an object; a refusal stops the script with why.
# -NotYet: GitHub's Not Found means not served yet, and comes back as $null.
function Get-GitHub([string]$path, [switch]$NotYet) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = @(& gh api $path 2>&1 | ForEach-Object { "$_" })
    $c = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($c -ne 0) {
        if ($NotYet -and ($o -join ' ') -match '\(HTTP 404\)') { return $null }
        Die ("GitHub answered GET $path with: " + (($o | Select-Object -Last 2) -join ' '))
    }
    return (($o -join "`n") | ConvertFrom-Json)
}

if ($PSCmdlet.ParameterSetName -eq 'Run') {
    $id = $Run
    $started = $false
} else {
    $body = @{ ref = 'main'; return_run_details = $true } | ConvertTo-Json -Compress
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $o = @($body | & gh api -X POST "repos/$GitHubRepo/actions/workflows/$workflow/dispatches" --input - 2>&1 | ForEach-Object { "$_" })
    $c = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($c -ne 0) { Die ('GitHub did not start the board-read workflow: ' + (($o | Select-Object -Last 2) -join ' ')) }
    $answer = ($o -join "`n") | ConvertFrom-Json
    if (-not $answer.PSObject.Properties['workflow_run_id'] -or -not $answer.workflow_run_id) {
        Die ('GitHub started the board-read workflow but named no run, so its artifact cannot be found from here. Its runs: https://github.com/' + $GitHubRepo + '/actions/workflows/' + $workflow)
    }
    $id = [long]$answer.workflow_run_id
    $started = $true
    Say ('started the board-read workflow: ' + $answer.html_url) 'DarkGray'
}

# Waits for the run to end. A run the dispatch has just named can be Not Found
# for a few seconds while GitHub's copies catch up (Say-Staff.ps1, #3081), so
# until it is first served that is one more state of the wait, like queued.
$runPath = "repos/$GitHubRepo/actions/runs/$id"
$deadline = [DateTime]::UtcNow.AddMinutes($WaitMinutes)
$r = Get-GitHub $runPath -NotYet:$started
$told = ''
while (-not $r -or $r.status -ne 'completed') {
    $state = if ($r) { $r.status } else { 'not served by GitHub yet' }
    if ([DateTime]::UtcNow -gt $deadline) {
        Say ("the run has not ended after $WaitMinutes minutes (it was $state), so every runner is busy. It still reads the board when one takes it.") 'Yellow'
        Say ('  read it then: pwsh scripts/ops/Read-Board.ps1 -Run ' + $id) 'DarkGray'
        exit 2
    }
    if ($told -ne $state) { Say ("  waiting ($state)") 'DarkGray'; $told = $state }
    Start-Sleep -Seconds 5
    $r = Get-GitHub $runPath -NotYet:($started -and -not $r)
}
if ($r.path -notmatch ('/' + [regex]::Escape($workflow) + '$')) { Die ("run $id is not a board-read run (it is " + $r.path + ').') }
if ($r.conclusion -ne 'success') { Die ("the run ended $($r.conclusion), so there is no board.json. Its log says why: " + $r.html_url) }

$art = @((Get-GitHub "$runPath/artifacts").artifacts | Where-Object { $_.name -eq 'board' })
if ($art.Count -ne 1) { Die ('the run left no artifact named board: ' + $r.html_url) }
if ($art[0].expired) { Die ("run $id's board artifact has expired (they are kept 3 days). Read the board again: pwsh scripts/ops/Read-Board.ps1") }

# gh run download fetches and unpacks the artifact itself. Measured 22 Oct
# 2026 on the first real read: Start-Process, redirecting gh's output, reads the
# child's output as text and writes it back out, so the zip that way came out
# changed and Expand-Archive refused it ("Offset to Central Directory cannot
# be held in an Int64").
$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-board-read-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    # gh's own lines on stderr are not a failure; its exit code says.
    $ErrorActionPreference = 'Continue'
    $said = & gh run download $id -R $GitHubRepo -n board -D (Join-Path $work 'x') 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { Die ('GitHub did not hand over the board artifact: ' + ((@($said) | Out-String).Trim())) }
    $json = Join-Path (Join-Path $work 'x') 'board.json'
    if (-not (Test-Path -LiteralPath $json)) { Die ('the board artifact holds no board.json: ' + $r.html_url) }
    $board = [IO.File]::ReadAllText($json) | ConvertFrom-Json
    $dir = Split-Path -Parent $OutFile
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item -LiteralPath $json -Destination $OutFile -Force
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

$items = @($board.items)
Say ("read {0} cards from {1}, as of {2}" -f $items.Count, $board.board.url, $board.read_at) 'Green'
foreach ($g in @($items | Group-Object { if ($_.status) { $_.status } else { '(no Status)' } } | Sort-Object Name)) { Say ("  {0}: {1}" -f $g.Name, $g.Count) }
Say ("  written to $OutFile") 'DarkGray'
exit 0
