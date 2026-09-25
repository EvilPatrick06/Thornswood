<#
  test-release-prerelease.ps1

  A dev build goes up to GitHub marked prerelease, on every path the upload
  can take, and a main build does not.

  MEASURED 24 SEPTEMBER with gh release list on Thornswood-Releases: 156
  releases, 59 of them dev, not one marked prerelease, and Latest on the
  public releases page was 20260923-2246-dev while the newest main release
  was 20260923-2137. The page told anybody who looked that a dev build was
  the current one.

  The obvious fix, and the one the To Do List entry asked for, puts
  --prerelease on both the gh release create line and the gh release upload
  fallback. The second half breaks every fallback: gh 2.100.0 has no such
  flag on upload, and run here it answered "unknown flag: --prerelease" and
  uploaded nothing. So the upload path marks the release with gh release edit
  instead, and this harness holds both halves.

  It lifts the upload block out of the shipped Publish-Update.ps1, between its
  two markers, and drives it with a stand-in for gh that answers each call the
  way it is told to, and refuses any flag the real gh 2.100.0 does not take on
  that subcommand, from its own --help. Nothing here touches GitHub. If the
  markers move, this stops rather than quietly testing nothing.
#>
[CmdletBinding()]
param([string]$PublishPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $PublishPath) { $PublishPath = Join-Path $Here 'Publish-Update.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

# ---- lift the upload block out of the shipped script ------------------------
$src = Get-Content -LiteralPath $PublishPath -Raw
$a = $src.IndexOf('# ==== thornswood release upload ====')
$b = $src.IndexOf('# ==== end thornswood release upload ====')
Yes 'the release upload markers are in Publish-Update.ps1' ($a -ge 0 -and $b -gt $a)
if ($a -lt 0 -or $b -le $a) { Write-Host ''; Write-Host '0 passed, 1 failed'; exit 1 }
$block = $src.Substring($a, $b - $a)

# ---- the stand-ins ----------------------------------------------------------
# The flags gh 2.100.0 takes on each subcommand this block uses, read off
# gh release create --help, gh release upload --help and gh release edit
# --help. Anything else makes the real gh stop before it sends a thing.
$script:flags = @{
    create = @('--title', '--notes', '--repo', '--prerelease', '--latest')
    upload = @('--clobber', '--repo')
    edit   = @('--prerelease', '--repo', '--latest', '--title', '--notes')
}

function gh {
    $argv = @($args | ForEach-Object { [string]$_ })
    $sub = $argv[1]
    $bad = @($argv | Where-Object { $_ -like '--*' -and $script:flags[$sub] -notcontains $_ })
    $call = [pscustomobject]@{ sub = $sub; argv = $argv; rejected = ($bad.Count -gt 0) }
    $script:calls += $call
    if ($call.rejected) {
        $global:LASTEXITCODE = 1
        return ('unknown flag: ' + $bad[0])
    }
    $q = @($script:codes[$sub])
    $code = 0
    if ($q.Count) { $code = [int]$q[0]; $script:codes[$sub] = @($q | Select-Object -Skip 1) }
    $global:LASTEXITCODE = $code
}
function Say($m, $c = 'Gray') { $script:said += [string]$m }
function Start-Sleep([int]$Seconds) { $script:slept += $Seconds }

# Runs the lifted block once. $codes says what each subcommand answers, in
# order, one exit code per call; a call past the end of its list succeeds.
function Run-Upload([bool]$dev, [hashtable]$codes, [string]$repo = 'EvilPatrick06/Thornswood-Releases') {
    $script:calls = @()
    $script:said = @()
    $script:slept = 0
    $script:codes = @{ create = @(); upload = @(); edit = @() }
    foreach ($k in $codes.Keys) { $script:codes[$k] = @($codes[$k]) }

    $Dev = $dev
    $Id = '20260924-0100'; if ($dev) { $Id += '-dev' }
    $assets = @('C:\Thornswood-Dev\dist\pack-' + $Id + '.zip', 'C:\Thornswood-Dev\dist\Thornswood.exe')
    $repoArg = @(); if ($repo) { $repoArg = @('--repo', $repo) }
    $Notes = "A title for people`n- one thing they will notice"

    Invoke-Expression $block
}
# The comma keeps an empty or one item list a list on the way out, which
# strict mode would otherwise turn into a missing Count.
function Calls([string]$sub) { return , @($script:calls | Where-Object { $_.sub -eq $sub }) }
function Has($call, [string]$flag) { return (@($call.argv) -contains $flag) }
function NoneRejected { return (@($script:calls | Where-Object { $_.rejected }).Count -eq 0) }

# ---- a dev release, created first time --------------------------------------
Run-Upload $true @{}
$c = Calls 'create'
Yes 'dev: one create call' ($c.Count -eq 1)
Yes 'dev: the create carries --prerelease' ($c.Count -eq 1 -and (Has $c[0] '--prerelease'))
Yes 'dev: and the repository' ($c.Count -eq 1 -and ((@($c[0].argv) -join ' ') -match '--repo EvilPatrick06/Thornswood-Releases'))
Yes 'dev: nothing uploaded into an existing release' ((Calls 'upload').Count -eq 0)
Yes 'dev: no edit needed after a create' ((Calls 'edit').Count -eq 0)
Yes 'dev: gh took every flag' (NoneRejected)

# ---- a main release, created first time -------------------------------------
Run-Upload $false @{}
$c = Calls 'create'
Yes 'main: one create call' ($c.Count -eq 1)
Yes 'main: the create does not carry --prerelease' ($c.Count -eq 1 -and -not (Has $c[0] '--prerelease'))
Yes 'main: nothing says --prerelease anywhere' (@($script:calls | Where-Object { Has $_ '--prerelease' }).Count -eq 0)
Yes 'main: no edit' ((Calls 'edit').Count -eq 0)

# ---- a dev release that already exists: the resume path ---------------------
# Create answers 1 because the tag is taken, the upload goes in, and the
# release is marked with an edit, since upload cannot carry the flag.
Run-Upload $true @{ create = @(1) }
$u = Calls 'upload'
$e = Calls 'edit'
Yes 'dev resume: the upload went in' ($u.Count -eq 1 -and -not $u[0].rejected)
Yes 'dev resume: the upload does not carry --prerelease, which gh refuses' ($u.Count -eq 1 -and -not (Has $u[0] '--prerelease'))
Yes 'dev resume: the release is marked with one edit' ($e.Count -eq 1)
Yes 'dev resume: the edit names this release' ($e.Count -eq 1 -and $e[0].argv[2] -eq '20260924-0100-dev')
Yes 'dev resume: the edit carries --prerelease' ($e.Count -eq 1 -and (Has $e[0] '--prerelease'))
Yes 'dev resume: in the same repository' ($e.Count -eq 1 -and ((@($e[0].argv) -join ' ') -match '--repo EvilPatrick06/Thornswood-Releases'))
Yes 'dev resume: the edit comes after the upload' ($script:calls.Count -eq 3 -and $script:calls[1].sub -eq 'upload' -and $script:calls[2].sub -eq 'edit')
Yes 'dev resume: no second try' ((Calls 'create').Count -eq 1 -and $script:slept -eq 0)
Yes 'dev resume: gh took every flag' (NoneRejected)

# ---- a main release that already exists -------------------------------------
Run-Upload $false @{ create = @(1) }
Yes 'main resume: the upload went in' ((Calls 'upload').Count -eq 1)
Yes 'main resume: no edit, main is not a prerelease' ((Calls 'edit').Count -eq 0)

# ---- the edit fails: the assets are up, so the release still goes on ---------
Run-Upload $true @{ create = @(1); edit = @(1) }
Yes 'failed edit: tried once' ((Calls 'edit').Count -eq 1)
Yes 'failed edit: not retried as a failed upload' ((Calls 'create').Count -eq 1 -and (Calls 'upload').Count -eq 1 -and $script:slept -eq 0)
Yes 'failed edit: and it is said' (@($script:said | Where-Object { $_ -match 'could not be marked prerelease' }).Count -eq 1)

# ---- GitHub answers 500 once, then takes it ---------------------------------
Run-Upload $true @{ create = @(1); upload = @(1) }
$c = Calls 'create'
Yes 'retry: created on the second try' ($c.Count -eq 2)
Yes 'retry: both creates carry --prerelease' ($c.Count -eq 2 -and (Has $c[0] '--prerelease') -and (Has $c[1] '--prerelease'))
Yes 'retry: no edit after a create that worked' ((Calls 'edit').Count -eq 0)
Yes 'retry: waited once, five seconds' ($script:slept -eq 5)

# ---- GitHub takes nothing at all --------------------------------------------
Run-Upload $true @{ create = @(1, 1, 1); upload = @(1, 1, 1) }
Yes 'nothing taken: three tries' ((Calls 'create').Count -eq 3 -and (Calls 'upload').Count -eq 3)
Yes 'nothing taken: no edit of a release that is not there' ((Calls 'edit').Count -eq 0)

# ---- no -Repo given: gh works it out from the folder ------------------------
Run-Upload $true @{ create = @(1) } ''
$e = Calls 'edit'
Yes 'no repo: the edit is still made' ($e.Count -eq 1 -and (Has $e[0] '--prerelease'))
Yes 'no repo: and names no repository' ($e.Count -eq 1 -and -not (Has $e[0] '--repo'))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
