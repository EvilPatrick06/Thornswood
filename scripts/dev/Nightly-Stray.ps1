<#
  Nightly-Stray.ps1

  Names every pull request open more than two days and every branch other than
  main with no open pull request, reading every page GitHub has. A pull
  request labelled held is listed as held and does not count (#1273). Run by
  .github/workflows/nightly.yml in its step "Stray pull requests and
  branches", with GH_TOKEN and REPO set:

      .\scripts\dev\Nightly-Stray.ps1 -Run

  Exits 1 when it names anything, so the night is red and Nightly-Issue.ps1
  puts it on the board.

  WHY (issue #1201). The step this replaces read branches?per_page=100 and
  pulls?state=open&per_page=100 once each and never asked for page 2. With
  more than a hundred branches, which a day of claude/ and lane branches
  passes, a branch past the first page was never checked, and a branch whose
  open pull request was past the first page of pulls was called stray when it
  was not. This reads page by page until a page comes back short, the same
  way Nightly-Issue.ps1 reads the open issues.

  The token is the workflow's own GITHUB_TOKEN (pull-requests: read, contents:
  read). Nothing here prints it.

  tests\test-nightly-stray.ps1 runs this against a stand-in GitHub.
#>
[CmdletBinding()]
param(
    # Read GitHub and say what is stray. Without it the script only defines
    # its functions, which is how the harness loads it.
    [switch]$Run
)

$ErrorActionPreference = 'Stop'

# One call to the GitHub API. The tests replace Invoke-RestMethod under it.
function Invoke-StrayApi {
    param([string]$Path)
    $h = @{ Authorization = "Bearer $env:GH_TOKEN"; 'User-Agent' = 'thornswood-nightly'; Accept = 'application/vnd.github+json' }
    # Into a variable first: Invoke-RestMethod hands a JSON array down the pipe
    # as one object, and returning the variable hands on its items.
    $r = Invoke-RestMethod -Method GET -Headers $h -Uri "https://api.github.com/repos/$env:REPO/$Path"
    return $r
}

# Every item of a list GitHub pages, 100 to a page, until a page comes back
# short. $Path may carry a query of its own; the page is added to it.
function Get-StrayPages {
    param([string]$Path)
    $join = if ($Path.Contains('?')) { '&' } else { '?' }
    $all = @()
    $page = 1
    while ($true) {
        $batch = @(Invoke-StrayApi ($Path + $join + 'per_page=100&page=' + $page))
        $all += $batch
        if ($batch.Count -lt 100) { break }
        $page++
        if ($page -gt 50) { throw ('More than 5,000 in ' + $Path + ': stopped reading pages.') }
    }
    return $all
}

# The label a pull request held back on purpose carries (#1273): one marker
# read exactly, where held work had four spellings in titles and none at all
# in others. A held pull request is listed every night and does not turn it
# red; the label comes off when it is let go.
$HeldLabel = 'held'

# The pull requests open more than $Days days, apart from the held ones, and
# the branches other than main that no open pull request is made from.
function Find-Stray {
    param([int]$Days = 2, [DateTime]$Now = [DateTime]::UtcNow)
    $old = $Now.AddDays(-$Days)
    $pulls = @(Get-StrayPages 'pulls?state=open')
    $aged = @($pulls | Where-Object { ([DateTime]$_.created_at).ToUniversalTime() -lt $old })
    $isHeld = { param($p) @($p.labels | ForEach-Object { [string]$_.name }) -contains $HeldLabel }
    $held = @($aged | Where-Object { & $isHeld $_ })
    $prs = @($aged | Where-Object { -not (& $isHeld $_) })
    $open = @($pulls | ForEach-Object { [string]$_.head.ref })
    $branches = @(Get-StrayPages 'branches' | ForEach-Object { [string]$_.name } | Where-Object { $_ -ne 'main' })
    $stray = @($branches | Where-Object { $open -notcontains $_ })
    return [pscustomobject]@{ OldPulls = $prs; HeldPulls = $held; Stray = $stray; Branches = $branches.Count; Pulls = $pulls.Count }
}

if ($Run) {
    $found = Find-Stray
    foreach ($p in $found.HeldPulls) { Write-Host ("::notice::pull request #{0} is held ({1}), open since {2}: {3}" -f $p.number, $HeldLabel, $p.created_at, $p.title) }
    foreach ($p in $found.OldPulls) { Write-Host ("::error::pull request #{0} has been open since {1}: {2}" -f $p.number, $p.created_at, $p.title) }
    foreach ($b in $found.Stray) { Write-Host ("::error::branch {0} has no open pull request" -f $b) }
    Write-Host ("read {0} branch(es) other than main and {1} open pull request(s), {2} of them old and held" -f $found.Branches, $found.Pulls, $found.HeldPulls.Count)
    if ($found.OldPulls.Count -or $found.Stray.Count) {
        Write-Host ("{0} old pull request(s), {1} stray branch(es)" -f $found.OldPulls.Count, $found.Stray.Count)
        exit 1
    }
    Write-Host 'no stray pull requests or branches'
    exit 0
}
