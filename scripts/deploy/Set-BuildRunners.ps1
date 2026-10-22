<#
  Set-BuildRunners.ps1

  Makes the build label on GitHub's VPS runners match records\build-runners.json,
  so no more builds run on the box at once than that file lists runners.

      .\scripts\deploy\Set-BuildRunners.ps1           put the label on the listed runners, take it off the rest
      .\scripts\deploy\Set-BuildRunners.ps1 -Check    change nothing; exit 1 when GitHub differs from the record

  WHY (#2994). The VPS has six cores and, since 20 October, eight runners
  (#2929). Every heavy job asked for thornswood-vps, which all eight carry,
  so on the night of 20 to 21 October seven builds ran at once, each one's
  harness step stretched from about 15 minutes to 34 to 39, and the job's
  40-minute limit cancelled three pull requests' builds that were passing.
  Measured over 558 box jobs: past four at once the box finishes no more
  builds an hour (11.1 at four, 11.6 at seven), each one only takes longer.
  So the heavy jobs (the build fallbacks in build.yml and build-pr.yml, the
  engine fallback, the nightly checks) ask for the build label as well, and
  only the runners records\build-runners.json lists carry it. The light
  jobs (board cards, dropped claims, the release jobs) still run on any VPS
  runner, so they never wait behind a build. The cap is the number of
  runners in that list; changing it is a pull request to that file, then
  this script.

  It talks to GitHub only, never to the box: a runner's labels live on
  GitHub (POST and DELETE repos/<repo>/actions/runners/<id>/labels), and a
  job already running is not touched. A runner the record lists is named
  thornswood-vps (1) or thornswood-vps-<n>; an off-box runner
  (thornswood-pr-*) never gets the label. It needs gh signed in as somebody
  who administers the repository, the same as Install-Runner.ps1.

  It refuses to leave GitHub with no registered runner carrying the label,
  because every heavy job would then wait for a runner that never comes.

  #2161 (one runner at a time). The outbound rules go on one runner and a
  build through it proves them. The runners the record lists carry the
  label (1 and 2 since 22 Oct 2026, #3114), so their builds prove them. A runner outside the list runs only the
  light jobs; to prove one, add its number to the record in the same pull
  request that moves the rollout to it, and run this.

  -DryRunFrom <file> reads the runner list from that file (GitHub's answer
  to repos/<repo>/actions/runners, as JSON) instead of asking GitHub, and
  changes nothing: tests\test-2994-build-runners.ps1 runs it that way.
#>
[CmdletBinding()]
param(
  [string]$Repo = 'EvilPatrick06/Thornswood',
  # Change nothing; say what differs and exit 1 when anything does.
  [switch]$Check,
  # The record. records\build-runners.json unless a test points it at a copy.
  [string]$Record = '',
  # Read the runners from this file instead of GitHub and change nothing.
  [string]$DryRunFrom = ''
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Record) { $Record = Join-Path $Here '..\..\records\build-runners.json' }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host "STOP. $m" -ForegroundColor Red; exit 1 }

# ---- the record --------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Record)) { Die "there is no record at $Record." }
$rec = Get-Content -LiteralPath $Record -Raw | ConvertFrom-Json
$label = "$($rec.label)".Trim()
$want = @($rec.runners | ForEach-Object { [int]$_ })
if (-not $label -or $label -eq 'thornswood-vps' -or $label -match '[,\s]') { Die "the record's label ('$label') must be one word and not thornswood-vps, which every VPS runner carries." }
if (-not $want.Count) { Die 'the record lists no runners, so no heavy job could ever run. Nothing was changed.' }
if (@($want | Where-Object { $_ -lt 1 }).Count) { Die 'the record lists a runner number below 1. Nothing was changed.' }

# ---- what GitHub has -----------------------------------------------------------
function Invoke-Gh {
  # Windows PowerShell and pwsh both turn a line gh writes to stderr into an
  # error record under Stop; gh is judged by its exit code instead.
  $ErrorActionPreference = 'Continue'
  $out = & gh @args 2>$null
  if ($LASTEXITCODE -ne 0) { throw ('gh ' + ($args -join ' ') + ' failed') }
  return $out
}
if ($DryRunFrom) {
  $answer = Get-Content -LiteralPath $DryRunFrom -Raw
} else {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Die 'gh is not on PATH. Install GitHub CLI from https://cli.github.com and run gh auth login.' }
  try { $answer = Invoke-Gh api "repos/$Repo/actions/runners?per_page=100" | Out-String }
  catch { Die "GitHub would not list the runners. gh has to be signed in as somebody who administers $Repo." }
}
$runners = @(($answer | ConvertFrom-Json).runners)

# A VPS runner's number from its name: thornswood-vps is 1, thornswood-vps-<n> is n.
function Get-RunnerNumber([string]$name) {
  if ($name -eq 'thornswood-vps') { return 1 }
  $m = [regex]::Match($name, '^thornswood-vps-(\d+)$')
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return 0
}

$plan = @()
$carry = @()
foreach ($r in $runners) {
  $n = Get-RunnerNumber "$($r.name)"
  $has = @($r.labels | ForEach-Object { "$($_.name)" }) -contains $label
  $should = ($n -gt 0) -and ($want -contains $n)
  if ($should) { $carry += $r }
  if ($has -and -not $should) { $plan += [pscustomobject]@{ Do = 'take off'; Runner = $r } }
  elseif ($should -and -not $has) { $plan += [pscustomobject]@{ Do = 'put on'; Runner = $r } }
  else { Say ("  {0}: {1}" -f $r.name, $(if ($has) { "carries $label, as the record says" } else { 'no build label, as the record says' })) }
}
foreach ($n in $want) {
  if (-not @($runners | Where-Object { (Get-RunnerNumber "$($_.name)") -eq $n }).Count) { Say ("  runner {0} is in the record but not registered on GitHub" -f $n) 'Yellow' }
}
if (-not $carry.Count) { Die "no runner the record lists is registered on GitHub, so every heavy job would wait for a runner that never comes. Nothing was changed." }
$online = @($carry | Where-Object { "$($_.status)" -eq 'online' })
if (-not $online.Count) { Say "  none of the runners carrying $label is online now; heavy jobs wait until one is" 'Yellow' }

foreach ($p in $plan) { Say ("  {0}: {1} {2}" -f $p.Runner.name, $p.Do, $label) 'Cyan' }
if (-not $plan.Count) { Say ("GitHub matches the record: {0} runner(s) carry {1}, so at most that many heavy jobs run on the box at once." -f $carry.Count, $label) 'Green'; exit 0 }
if ($Check) { Say ("GitHub differs from the record in {0} place(s), above. .\scripts\deploy\Set-BuildRunners.ps1 puts it right." -f $plan.Count) 'Yellow'; exit 1 }
if ($DryRunFrom) { Say ("dry run: {0} change(s) above, none made." -f $plan.Count); exit 0 }

foreach ($p in $plan) {
  $id = $p.Runner.id
  if ($p.Do -eq 'put on') { Invoke-Gh api -X POST "repos/$Repo/actions/runners/$id/labels" -f "labels[]=$label" | Out-Null }
  else { Invoke-Gh api -X DELETE "repos/$Repo/actions/runners/$id/labels/$label" | Out-Null }
  Say ("  {0}: done" -f $p.Runner.name) 'Green'
}

# Read it back rather than trust the calls.
$after = @(((Invoke-Gh api "repos/$Repo/actions/runners?per_page=100" | Out-String) | ConvertFrom-Json).runners)
$wrong = @($after | Where-Object {
  $n = Get-RunnerNumber "$($_.name)"
  $has = @($_.labels | ForEach-Object { "$($_.name)" }) -contains $label
  $has -ne (($n -gt 0) -and ($want -contains $n))
})
if ($wrong.Count) { Die ("GitHub still differs for " + (($wrong | ForEach-Object { $_.name }) -join ', ') + '. The lines above say what was asked.') }
Say ("GitHub matches the record: {0} runner(s) carry {1}." -f @($after | Where-Object { @($_.labels | ForEach-Object { "$($_.name)" }) -contains $label }).Count, $label) 'Green'
exit 0
