<#
.SYNOPSIS
  Moves a checkout that sits detached at origin/main, the shared clone on One, to the newest origin/main with engine\skymp at the commit it pins, or says why it cannot and moves nothing.

.DESCRIPTION
  Issue #2981. The shared clone on One (C:\Thornswood-Repo) sits detached at
  origin/main because the lanes build from it, and until this script nothing
  said how it got there: the step was the words "stays detached at
  origin/main", done by hand or by a lane with git checkout --detach
  origin/main. That never touches a submodule. So each time main's pin of
  engine\skymp moved, the clone kept the commit it had, git status showed a
  tracked change nobody made, and on 20 Oct the dev Ship refused it: the
  submodule was at ea523711 through three pin moves (#2866, #2881, #2925),
  while main pinned bf2b3b40. git pull on a branch does the same.

  So this is the move, and it does four things, refusing at the first that
  fails with one sentence and nothing moved:

    1. Fetches origin/main, and refuses when anything here would be left
       behind or carried along: a tracked change that is not a submodule
       behind its pin, a commit HEAD is on that no branch here or on GitHub
       holds, a submodule with uncommitted changes of its own, or a
       submodule at a commit no branch of the fork holds. Each of those
       would be in the reflog only, or land on the new commit unasked.
    2. Detaches at origin/main. On a branch it does not move, because git
       pull moves a branch; it only does the next step for that branch.
    3. Brings every submodule this checkout has fetched to the commit the
       checkout pins (git submodule update --checkout, which fetches the
       commit when it is not here and never overwrites a change). One that
       was never fetched, as in a new worktree, stays as it is: git status
       does not count it and Ship does not need it.
    4. Sets submodule.recurse in the clone's own config, so a git checkout,
       switch or pull by hand or by a lane takes the submodules along too.
       Worktrees share that config.

  Then it asks what Ship asks (Fresh-Checkout.ps1) and prints the answer.

  It never deletes, resets, stashes or forces anything, and changes nothing
  outside the checkout and its submodules.

.PARAMETER RepoDir
  The checkout. The one this script is in unless said otherwise.

.PARAMETER Check
  Changes nothing: says where the checkout and its submodules are, and what
  a run would move. Exits 0 when there is nothing to move, 2 when a run would
  move something, 1 when a run would refuse.

.PARAMETER NoPause
  Exits without waiting for Enter.

.EXAMPLE
  .\scripts\release\Update-Checkout.ps1
  Moves the shared clone to the newest origin/main, engine\skymp with it.

.EXAMPLE
  .\scripts\release\Update-Checkout.ps1 -Check
  Says what that would move, and moves nothing.
#>
[CmdletBinding()]
param(
    [string]$RepoDir,
    [switch]$Check,
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\deploy\Fresh-Checkout.ps1')
if (-not $RepoDir) { $RepoDir = Split-Path -Parent (Split-Path -Parent $Here) }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Done([int]$code) { if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit $code }
function Die($m) { Write-Host ''; Write-Host "STOP. $m Nothing was moved." -ForegroundColor Red; Write-Host ''; Done 1 }

# git with what it said kept, for the sentence a refusal prints. Under Stop,
# Windows PowerShell 5.1 turns a line git writes to stderr into a halt, so
# each call runs under Continue for itself only, judged by its exit code.
function Invoke-Git([string]$Dir, [string[]]$GitArgs) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $Dir @GitArgs 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Code = $code; Out = @($out | Where-Object { $_ }) }
}
function First($r) { if ($r.Out.Count) { return ([string]$r.Out[0]).Trim() } return '' }

# Whether any branch or remote branch holds the commit, so moving off it
# leaves nothing that is in the reflog only.
function Test-Held([string]$Dir, [string]$Sha) {
    $r = Invoke-Git $Dir @('for-each-ref', '--count=1', '--format=%(refname)', '--contains', $Sha, 'refs/heads', 'refs/remotes')
    return ($r.Code -eq 0 -and $r.Out.Count -gt 0)
}

# The submodules the checkout names in .gitmodules, and whether each is
# fetched here (a .git file or folder in it).
function Get-Submodules([string]$Top) {
    if (-not (Test-Path -LiteralPath (Join-Path $Top '.gitmodules'))) { return @() }
    $r = Invoke-Git $Top @('config', '--file', '.gitmodules', '--get-regexp', '^submodule\..*\.path$')
    $subs = @()
    foreach ($l in $r.Out) {
        $path = ($l -split '\s+', 2)[1]
        if (-not $path) { continue }
        $dir = Join-Path $Top $path
        $subs += [pscustomobject]@{ Path = $path; Dir = $dir; Fetched = (Test-Path -LiteralPath (Join-Path $dir '.git')) }
    }
    return $subs
}

$t = Invoke-Git $RepoDir @('rev-parse', '--show-toplevel')
if ($t.Code -ne 0) { Die "$RepoDir is not a git checkout." }
$Top = [IO.Path]::GetFullPath((First $t))
$branch = First (Invoke-Git $Top @('rev-parse', '--abbrev-ref', 'HEAD'))
$detached = ($branch -eq 'HEAD')
$head = First (Invoke-Git $Top @('rev-parse', 'HEAD'))

Write-Host ''
Write-Host ('  The checkout, ' + $Top) -ForegroundColor Cyan
Say ('  ' + $(if ($detached) { 'detached at ' + (Get-FreshShort $head) } else { 'on ' + $branch + ' at ' + (Get-FreshShort $head) }))

# ---- 1. what would be left behind or carried along ---------------------------
$f = Invoke-Git $Top @('fetch', '--quiet', 'origin', 'main')
if ($f.Code -ne 0) { Die ("git fetch origin main failed (exited $($f.Code)): " + ($f.Out -join ' ') + '.') }
$main = First (Invoke-Git $Top @('rev-parse', 'refs/remotes/origin/main'))

$st = Invoke-Git $Top @('status', '--porcelain', '--untracked-files=no')
if ($st.Code -ne 0) { Die ("git status failed (exited $($st.Code)): " + ($st.Out -join ' ') + '.') }
$changed = @($st.Out | Where-Object { $_.Trim() })
$drift = @(Get-FreshSubmoduleDrift -RepoDir $Top -Lines $changed)
$driftPaths = @($drift | ForEach-Object { $_.Path })
$other = @($changed | Where-Object { $driftPaths -notcontains $_.Substring(3).Trim().Trim('"') })
if ($other.Count) {
    foreach ($o in $other | Select-Object -First 10) { Say "    $o" 'Yellow' }
    Die ("$($other.Count) tracked change(s) here that are not a submodule behind its pin. A move would carry them onto the new commit, or stop half way. " +
         'Put them on a branch in a worktree through a pull request, or put them back.')
}
if ($detached -and $head -and -not (Test-Held $Top $head)) {
    Die ("HEAD is at $(Get-FreshShort $head), which no branch here or on GitHub holds, so after a move it would be in the reflog only. " +
         "git branch archive/$(Get-FreshShort $head) $head keeps it.")
}

$subs = @(Get-Submodules $Top)
foreach ($s in $subs) {
    if (-not $s.Fetched) { continue }
    $ss = Invoke-Git $s.Dir @('status', '--porcelain', '--untracked-files=no')
    if ($ss.Code -ne 0) { Die ("git status in $($s.Path) failed (exited $($ss.Code)): " + ($ss.Out -join ' ') + '.') }
    $mine = @($ss.Out | Where-Object { $_.Trim() })
    if ($mine.Count) {
        foreach ($o in $mine | Select-Object -First 10) { Say "    $($s.Path): $o" 'Yellow' }
        Die ("$($s.Path) has $($mine.Count) uncommitted change(s) of its own. Commit them in the fork through a pull request, or put them back.")
    }
    $at = First (Invoke-Git $s.Dir @('rev-parse', 'HEAD'))
    if ($at -and -not (Test-Held $s.Dir $at)) {
        Die ("$($s.Path) is at $(Get-FreshShort $at), which no branch of the fork here or on GitHub holds, so after a move it would be in the reflog only. " +
             "git -C $($s.Path) branch archive/$(Get-FreshShort $at) $at keeps it.")
    }
}

# ---- what a run moves -------------------------------------------------------
$moveTop = ($detached -and $head -ne $main)
$recurse = First (Invoke-Git $Top @('config', '--local', '--get', 'submodule.recurse'))
$moves = @()
if ($moveTop) { $moves += "the checkout from $(Get-FreshShort $head) to origin/main at $(Get-FreshShort $main)" }
if (-not $detached) { Say "  on $branch, so not moved: git pull moves a branch. Its submodules are brought to its own pins." 'DarkGray' }
foreach ($s in $subs) {
    if (-not $s.Fetched) { Say "  $($s.Path) is not fetched in this checkout, so it stays as it is (git submodule update --init $($s.Path) fetches it)" 'DarkGray'; continue }
    $want = First (Invoke-Git $Top @('rev-parse', "$(if ($moveTop) { $main } else { 'HEAD' }):$($s.Path)"))
    $at = First (Invoke-Git $s.Dir @('rev-parse', 'HEAD'))
    if ($want -and $at -ne $want) { $moves += "$($s.Path) from $(Get-FreshShort $at) to the $(Get-FreshShort $want) it is pinned to" }
}
if ($recurse -ne 'true') { $moves += 'submodule.recurse to true in this clone''s config' }

if ($Check) {
    if (-not $moves.Count) { Say '  Nothing to move: origin/main, and every submodule at its pin.' 'Green'; Done 0 }
    Say '  A run would move:' 'Yellow'
    foreach ($m in $moves) { Say "    $m" 'Yellow' }
    Done 2
}

# ---- 2. the checkout ----------------------------------------------------------
if ($moveTop) {
    # The submodules move in step 3, one by one with their own refusals, so
    # this checkout leaves them alone whatever the clone's config says.
    $c = Invoke-Git $Top @('-c', 'submodule.recurse=false', 'checkout', '--quiet', '--detach', $main)
    if ($c.Code -ne 0) { Die ("git checkout --detach origin/main refused (exited $($c.Code)): " + ($c.Out -join ' ') + '.') }
    Say "  moved to origin/main at $(Get-FreshShort $main)" 'Green'
}

# ---- 3. the submodules, to the commit the checkout pins ----------------------
foreach ($s in $subs) {
    if (-not $s.Fetched) { continue }
    $u = Invoke-Git $Top @('submodule', 'update', '--checkout', '--', $s.Path)
    if ($u.Code -ne 0) {
        Write-Host ''
        Write-Host ("STOP. $($s.Path) did not follow (git exited $($u.Code)): " + ($u.Out -join ' ') + '. git changed nothing in it; ' +
            $(if ($moveTop) { "the checkout itself is at origin/main $(Get-FreshShort $main)." } else { 'the checkout itself did not move.' })) -ForegroundColor Red
        Write-Host ''
        Done 1
    }
    Say ("  $($s.Path) at " + (Get-FreshShort (First (Invoke-Git $s.Dir @('rev-parse', 'HEAD')))) + ', the commit the checkout pins') 'Green'
}

# ---- 4. so a move by hand takes the submodules along too ---------------------
if ($recurse -ne 'true') {
    $g = Invoke-Git $Top @('config', '--local', 'submodule.recurse', 'true')
    if ($g.Code -ne 0) { Write-Host ("STOP. git config submodule.recurse true failed (exited $($g.Code)): " + ($g.Out -join ' ')) -ForegroundColor Red; Done 1 }
    Say '  submodule.recurse is true in this clone''s config: a git checkout, switch or pull here or in its worktrees takes the submodules along' 'Green'
}

# ---- what Ship will say ------------------------------------------------------
$fresh = Get-FreshCheckoutState -RepoDir $Top -NoFetch -AnyBranch:(-not $detached)
if (-not $fresh.Ok) { Write-Host ''; Write-Host ('STOP. Ship would still refuse: ' + $fresh.Message + '.') -ForegroundColor Red; Write-Host ''; Done 1 }
Say ('  ' + $fresh.Message + ', as Ship takes it') 'Green'
Done 0
