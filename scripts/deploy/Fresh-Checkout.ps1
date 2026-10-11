# Fresh-Checkout.ps1
#
# Deploy and ship scripts refuse a stale or dirty checkout (#2118).
#
# WHY. Two machines and several worktrees deploy from this repo. A deploy from
# a clone that is behind main sends yesterday's code to the VPS, and quietly
# takes back whatever the last push fixed. A deploy from a clone with changes
# nobody committed sends code that exists on one disk only. Both have happened.
#
# WHAT. Assert-FreshCheckout fetches origin, then refuses unless HEAD is
# exactly origin/main (or origin/<branch> with -AnyBranch, for the dev paths
# that may run off a branch) and nothing tracked is changed. Each refusal says
# which of the four it is: behind, ahead, diverged or dirty, and what to run.
#
# THE ONE WAY PAST IT is -AllowStale, which each caller exposes as
# -AllowStaleCheckout. It prints a banner nobody can miss and carries on.
#
# ONCE PER RUN. A script that calls another (Ship calling Publish-Server)
# would fetch twice. The first pass writes the commit it passed in
# THORNSWOOD_FRESH_CHECKED, and a later call at the same commit in the same
# process skips the fetch.
#
# GIT IS JUDGED BY ITS EXIT CODE. Under Stop, Windows PowerShell 5.1 turns a
# line git writes to stderr into a NativeCommandError even through 2>$null,
# so every git call here runs under Continue for itself only.
#
# THE HARNESS STAND-IN, and nothing else, is let through without a check:
# the tests run these scripts whole against stand-in ssh and scp and a
# pretend box on this machine, from a checkout that is a pull request's head
# and so never origin/main. A run counts as the stand-in only when BOTH are
# true: THORNSWOOD_HARNESS is 1, AND the box it would send to (the -Vps it
# was handed, or THORNSWOOD_VPS when it takes none) is one that can never be
# a real server: harness.invalid (.invalid is reserved by RFC 2606 and never
# resolves) or this machine's own loopback, 127.0.0.1, ::1 or localhost,
# which the harnesses' pretend boxes listen on. tests\test-fresh-checkout.ps1
# fails if the live or dev host, or any host a script names, is ever one.
$script:FreshHarnessHosts = @('harness.invalid', '127.0.0.1', '::1', 'localhost')

function Test-FreshHarnessStandIn {
    param([string]$Target)
    if ($env:THORNSWOOD_HARNESS -ne '1') { return $false }
    $t = if ($Target) { $Target } else { [string]$env:THORNSWOOD_VPS }
    return ($script:FreshHarnessHosts -contains $t.Trim().ToLowerInvariant())
}
# Not a git clone at all (a copy of the scripts on some other box): refused
# too, since there is nothing to say what it was built from, unless
# -AllowStale.

function Invoke-FreshGit {
    param([string]$RepoDir, [string[]]$GitArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & git -C $RepoDir @GitArgs 2>$null
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Code = $code; Out = @($out | Where-Object { $null -ne $_ } | ForEach-Object { "$_" }) }
}

function Get-FreshCheckoutState {
    param([Parameter(Mandatory)][string]$RepoDir, [switch]$AnyBranch, [switch]$NoFetch)
    $r = [ordered]@{ Ok = $false; Problem = ''; Message = ''; Branch = ''; Target = ''; Ahead = 0; Behind = 0; Dirty = 0; Head = '' }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { $r.Problem = 'nogit'; $r.Message = 'git is not on this machine, so the checkout cannot be checked'; return [pscustomobject]$r }
    $top = Invoke-FreshGit $RepoDir @('rev-parse', '--show-toplevel')
    if ($top.Code -ne 0) { $r.Problem = 'notrepo'; $r.Message = "$RepoDir is not a git checkout, so nothing says what it was built from"; return [pscustomobject]$r }
    $head = Invoke-FreshGit $RepoDir @('rev-parse', 'HEAD')
    $r.Head = if ($head.Code -eq 0 -and $head.Out.Count) { $head.Out[0].Trim() } else { '' }
    $br = Invoke-FreshGit $RepoDir @('rev-parse', '--abbrev-ref', 'HEAD')
    $r.Branch = if ($br.Code -eq 0 -and $br.Out.Count) { $br.Out[0].Trim() } else { '' }
    $want = 'main'
    if ($AnyBranch -and $r.Branch -and $r.Branch -ne 'HEAD') { $want = $r.Branch }
    $r.Target = "origin/$want"
    if (-not $NoFetch) {
        $f = Invoke-FreshGit $RepoDir @('fetch', '--quiet', 'origin', $want)
        if ($f.Code -ne 0) {
            # A branch GitHub has never heard of fails the fetch too; ls-remote exits 2 for that one.
            $lr = Invoke-FreshGit $RepoDir @('ls-remote', '--exit-code', '--heads', 'origin', $want)
            if ($lr.Code -eq 2) { $r.Problem = 'noremote'; $r.Message = "$($r.Target) does not exist. Push the branch first: git push -u origin $want"; return [pscustomobject]$r }
        }
        if ($f.Code -ne 0) { $r.Problem = 'nofetch'; $r.Message = "could not fetch $($r.Target) (git exited $($f.Code)), so there is no telling whether this checkout is current"; return [pscustomobject]$r }
    }
    $v = Invoke-FreshGit $RepoDir @('rev-parse', '--verify', '--quiet', "refs/remotes/origin/$want")
    if ($v.Code -ne 0) { $r.Problem = 'noremote'; $r.Message = "$($r.Target) does not exist. Push the branch first: git push -u origin $want"; return [pscustomobject]$r }
    $c = Invoke-FreshGit $RepoDir @('rev-list', '--left-right', '--count', "HEAD...$($r.Target)")
    if ($c.Code -ne 0 -or -not $c.Out.Count) { $r.Problem = 'nocount'; $r.Message = "could not compare HEAD with $($r.Target) (git exited $($c.Code))"; return [pscustomobject]$r }
    $bits = ($c.Out[0].Trim() -split '\s+')
    $r.Ahead = [int]$bits[0]; $r.Behind = [int]$bits[1]
    $s = Invoke-FreshGit $RepoDir @('status', '--porcelain', '--untracked-files=no')
    if ($s.Code -ne 0) { $r.Problem = 'nostatus'; $r.Message = "git status failed (exited $($s.Code))"; return [pscustomobject]$r }
    $r.Dirty = @($s.Out | Where-Object { $_.Trim() }).Count
    if ($r.Ahead -gt 0 -and $r.Behind -gt 0) {
        $r.Problem = 'diverged'; $r.Message = "checkout has diverged from $($r.Target): $($r.Ahead) commit(s) only here and $($r.Behind) only there. Rebase onto $($r.Target) and push, or start from a fresh worktree"
    } elseif ($r.Behind -gt 0) {
        $r.Problem = 'behind'; $r.Message = "checkout is behind $want by $($r.Behind) commit(s), run git pull"
    } elseif ($r.Ahead -gt 0) {
        $r.Problem = 'ahead'; $r.Message = "checkout is ahead of $want by $($r.Ahead) commit(s) that are not on GitHub. Land them through a pull request first, so what is deployed is what is on $($r.Target)"
    }
    if ($r.Dirty -gt 0) {
        $d = "checkout has $($r.Dirty) uncommitted change(s) to tracked files. Commit them through a pull request or put them back (git status shows which)"
        if ($r.Problem) { $r.Message = $r.Message + '; and ' + $d } else { $r.Problem = 'dirty'; $r.Message = $d }
    }
    if (-not $r.Problem) { $r.Ok = $true; $r.Message = "checkout is $($r.Target) at $($r.Head.Substring(0, [Math]::Min(8, $r.Head.Length))), clean" }
    return [pscustomobject]$r
}

function Assert-FreshCheckout {
    param(
        [Parameter(Mandatory)][string]$RepoDir,
        [string]$What = 'This',
        [switch]$AnyBranch,
        [switch]$AllowStale,
        [string]$Target = ''
    )
    if (Test-FreshHarnessStandIn $Target) { Write-Host '  freshness: the harness stand-in box, not checked' -ForegroundColor DarkGray; return }
    $headNow = Invoke-FreshGit $RepoDir @('rev-parse', 'HEAD')
    $key = if ($headNow.Code -eq 0 -and $headNow.Out.Count) { $headNow.Out[0].Trim() + '|' + [bool]$AnyBranch } else { '' }
    if ($key -and $env:THORNSWOOD_FRESH_CHECKED -eq $key) { return }
    $st = Get-FreshCheckoutState -RepoDir $RepoDir -AnyBranch:$AnyBranch
    if ($st.Ok) {
        Write-Host ("  " + $st.Message) -ForegroundColor DarkGray
        if ($key) { $env:THORNSWOOD_FRESH_CHECKED = $key }
        return
    }
    if ($AllowStale) {
        $bar = '!' * 78
        Write-Host $bar -ForegroundColor Red
        Write-Host '!!  -AllowStaleCheckout: GOING AHEAD FROM A CHECKOUT THAT IS NOT CURRENT' -ForegroundColor Red
        Write-Host ('!!  ' + $st.Message) -ForegroundColor Yellow
        Write-Host '!!  What goes out may undo work already on GitHub. Say so in the dev channel.' -ForegroundColor Yellow
        Write-Host $bar -ForegroundColor Red
        return
    }
    throw ("$What refused: " + $st.Message + '. Nothing was sent. (-AllowStaleCheckout overrides this, loudly.)')
}