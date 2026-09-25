<#
  Move-TodoToIssues.ps1

      gh auth refresh -s project
      .\scripts\oneoff\Move-TodoToIssues.ps1 -DryRun
      .\scripts\oneoff\Move-TodoToIssues.ps1

  Moves the open entries of the Thornswood To Do List into GitHub Issues on
  this repository, and puts every one of them on a Project board called
  "Thornswood To Do" with an Order field that keeps the list's do-order.

  WHY. Decided by Patrick on 25 September and approved in #dev: the To Do List
  was a claude.ai page, which a developer without Claude could not open or
  edit. The team is three now and more are planned. Issues and a Project
  board are something everybody on the repository can read and change.

  WHAT IT READS. todo-open-2026-09-25.json beside this script: the 169 open
  entries as they stood on 25 September, each already written out as an issue
  (title, labels, who, and a body with where it lives, what is known, the
  steps as a checklist, the commands, done when and traps). The finished
  entries are not made into issues; docs\archive\todo-list-2026-09-25.md is
  the record of every entry, finished or not.

  WHAT IT DOES, in order: makes the labels (wave: and area: from the list, and
  needs: for the live server or Patrick), finds or makes the Project and links
  it to this repository, finds or makes its Order field, then makes one issue
  per entry in do-order and puts it on the board with its Order number.

  SAFE TO RUN AGAIN. Every issue it makes is written to
  local\todo-issues.json (ignored by git) as it goes, so a run that stops
  half way, or hits GitHub's limit on how fast issues can be made, carries on
  from the next entry rather than making doubles. It waits a second between
  issues for the same reason.

  It needs the gh command signed in as somebody who can write to the
  repository, with the project scope: gh auth refresh -s project.
  Everything except -DryRun changes GitHub.

  Run once. When the board is checked, the claude.ai page is deleted and this
  script and its data file can go.
#>
[CmdletBinding()]
param(
    [string]$Repo = 'EvilPatrick06/Thornswood',
    [string]$Owner = 'EvilPatrick06',
    [string]$Title = 'Thornswood To Do',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent (Split-Path -Parent $Here)
$data = Join-Path $Here 'todo-open-2026-09-25.json'
if (-not (Test-Path -LiteralPath $data)) { throw "not found: $data" }
$list = [IO.File]::ReadAllText($data, [Text.Encoding]::UTF8) | ConvertFrom-Json
$issues = @($list.issues | Sort-Object { [int]$_.order })
Write-Host ("{0} open entries to move, from the list as it stood on {1}." -f $issues.Count, $list.taken)

$doneFile = Join-Path $RepoDir 'local\todo-issues.json'
$done = @{}
if (Test-Path -LiteralPath $doneFile) {
    $prev = [IO.File]::ReadAllText($doneFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in $prev.PSObject.Properties) { $done[$p.Name] = $p.Value }
    Write-Host ("{0} already made by an earlier run, skipped." -f $done.Count)
}
function Save-Done {
    $dir = Split-Path -Parent $doneFile
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($doneFile, ($done | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
}
function Gh {
    $out = & gh @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("gh " + ($args -join ' ') + " failed: " + ($out | Out-String).Trim()) }
    return $out
}

if (-not $DryRun) {
    & gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'gh is not signed in. Run gh auth login first.' }
}

# ---- labels ---------------------------------------------------------------
$labels = @($issues | ForEach-Object { $_.labels } | Sort-Object -Unique)
Write-Host ''
Write-Host ("Labels: {0}" -f $labels.Count)
foreach ($l in $labels) {
    $color = 'c5def5'
    if ($l -like 'wave:*') { $color = 'fbca04' }
    elseif ($l -like 'needs:*') { $color = 'd93f0b' }
    elseif ($l -eq 'anyone can start') { $color = '0e8a16' }
    if ($DryRun) { Write-Host "  would make: $l" } else { Gh label create $l -R $Repo --color $color --force | Out-Null }
}

# ---- the board --------------------------------------------------------------
$number = $null; $projectId = $null; $fieldId = $null
if (-not $DryRun) {
    $projects = (Gh project list --owner $Owner --format json --limit 100 | Out-String) | ConvertFrom-Json
    $p = @($projects.projects | Where-Object { $_.title -eq $Title }) | Select-Object -First 1
    if (-not $p) {
        $p = (Gh project create --owner $Owner --title $Title --format json | Out-String) | ConvertFrom-Json
        Write-Host "Made the Project: $Title"
    } else { Write-Host "Found the Project: $Title" }
    $number = $p.number; $projectId = $p.id
    & gh project link $number --owner $Owner --repo $Repo 2>&1 | Out-Null
    $fields = (Gh project field-list $number --owner $Owner --format json --limit 100 | Out-String) | ConvertFrom-Json
    $f = @($fields.fields | Where-Object { $_.name -eq 'Order' }) | Select-Object -First 1
    if (-not $f) { $f = (Gh project field-create $number --owner $Owner --name Order --data-type NUMBER --format json | Out-String) | ConvertFrom-Json }
    $fieldId = $f.id
} else {
    Write-Host "  would find or make the Project '$Title', link it to $Repo, and give it a number field Order"
}

# ---- the issues -----------------------------------------------------------------
Write-Host ''
$made = 0
$tmp = [IO.Path]::GetTempFileName()
try {
    foreach ($i in $issues) {
        $key = [string]$i.order
        if ($done.ContainsKey($key)) { continue }
        if ($DryRun) {
            Write-Host ("  would make #{0}: {1} [{2}]{3}" -f $i.order, $i.title, ($i.labels -join ', '), $(if ($i.assignee) { ' for ' + $i.assignee } else { '' }))
            continue
        }
        [IO.File]::WriteAllText($tmp, [string]$i.body, (New-Object Text.UTF8Encoding($false)))
        $a = @('issue', 'create', '-R', $Repo, '--title', [string]$i.title, '--body-file', $tmp, '--label', ($i.labels -join ','))
        if ($i.assignee) { $a += @('--assignee', [string]$i.assignee) }
        $url = ((Gh @a) | Select-Object -Last 1).ToString().Trim()
        $item = (Gh project item-add $number --owner $Owner --url $url --format json | Out-String) | ConvertFrom-Json
        Gh project item-edit --id $item.id --project-id $projectId --field-id $fieldId --number ([int]$i.order) | Out-Null
        $done[$key] = $url
        Save-Done
        $made++
        Write-Host ("  {0,3}  {1}" -f $i.order, $url)
        Start-Sleep -Seconds 1
    }
}
finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }

Write-Host ''
if ($DryRun) { Write-Host 'Dry run: nothing was made.' }
else {
    Write-Host ("Made {0} issue(s); {1} of {2} are on the board." -f $made, $done.Count, $issues.Count) -ForegroundColor Green
    Write-Host "On the board, sort the view by Order (the view menu, Sort by, Order), so it reads in do-order."
}
