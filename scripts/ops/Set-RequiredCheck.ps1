<#
  Set-RequiredCheck.ps1

  Makes "Launcher builds" (the build check, which runs on the VPS runner) the
  required check on main, or takes it off, and leaves every other part of
  branch protection exactly as GitHub has it.

      .\scripts\ops\Set-RequiredCheck.ps1          require it
      .\scripts\ops\Set-RequiredCheck.ps1 -Off     stop requiring it

  WHY THIS EXISTS. Patrick, 25 September: "I want it set so they can
  commit+merge as long as the checks on the VPS go through so they don't
  need me". GitHub has no call that switches one part of branch protection
  back on once it was removed, only one that writes all of it, so this reads
  what is there and writes it back with the check changed. Needs gh signed in
  as an admin of the repository.
#>
[CmdletBinding()]
param(
    [switch]$Off,
    [string]$Check = 'Launcher builds',
    [string]$Repo = 'EvilPatrick06/Thornswood'
)

$ErrorActionPreference = 'Stop'
function GhRun { $ErrorActionPreference = 'Continue'; if ($MyInvocation.ExpectingInput) { $input | & gh @args 2>$null } else { & gh @args 2>$null } }

$json = (GhRun api "repos/$Repo/branches/main/protection" | Out-String)
if ($LASTEXITCODE -ne 0) { Write-Host 'STOP. gh could not read branch protection on main. Is it signed in as an admin (gh auth status)?' -ForegroundColor Red; exit 1 }
$p = $json | ConvertFrom-Json
$on = { param($x) [bool]($x -and $x.enabled) }
$reviews = $null
if ($p.required_pull_request_reviews) {
    $r = $p.required_pull_request_reviews
    $reviews = @{ required_approving_review_count = [int]$r.required_approving_review_count
                  require_code_owner_reviews = [bool]$r.require_code_owner_reviews
                  dismiss_stale_reviews = [bool]$r.dismiss_stale_reviews
                  require_last_push_approval = [bool]$r.require_last_push_approval }
}
$checks = if ($Off) { $null } else { @{ strict = $false; contexts = @($Check) } }
$body = @{
    required_status_checks = $checks
    enforce_admins = (& $on $p.enforce_admins)
    required_pull_request_reviews = $reviews
    restrictions = $null
    required_linear_history = (& $on $p.required_linear_history)
    allow_force_pushes = (& $on $p.allow_force_pushes)
    allow_deletions = (& $on $p.allow_deletions)
    block_creations = (& $on $p.block_creations)
    required_conversation_resolution = (& $on $p.required_conversation_resolution)
    lock_branch = (& $on $p.lock_branch)
    allow_fork_syncing = (& $on $p.allow_fork_syncing)
}
$body | ConvertTo-Json -Depth 5 -Compress | GhRun api -X PUT "repos/$Repo/branches/main/protection" --input - | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host 'STOP. GitHub did not take the change. Nothing else was touched.' -ForegroundColor Red; exit 1 }

$now = @(GhRun api "repos/$Repo/branches/main/protection" --jq '.required_status_checks.contexts[]?' | Where-Object { $_ })
if ($Off) {
    if ($now.Count) { Write-Host ('  still required: ' + ($now -join ', ')) -ForegroundColor Red; exit 1 }
    Write-Host '  main requires no check now' -ForegroundColor Yellow
} else {
    if ($now -notcontains $Check) { Write-Host "  GitHub does not list $Check as required. Look at Settings, Branches." -ForegroundColor Red; exit 1 }
    Write-Host "  main requires `"$Check`" now: a pull request merges once it is green on the VPS" -ForegroundColor Green
}
exit 0
