<#
  Bump-Version.ps1

  Moves the launcher's version number, commits that one file, and stops.

      .\scripts\release\Bump-Version.ps1                 1.1.79 -> 1.1.80
      .\scripts\release\Bump-Version.ps1 -To 1.2.0       straight to a number
      .\scripts\release\Bump-Version.ps1 -WhatIf         say what it would do

  WHY THIS EXISTS AS ITS OWN STEP.

  Ship used to bump the version itself and then, after publishing, `git add -A`
  and push the result straight to main. That is why enforce_admins has to stay
  off in branch protection: turning it on refuses that push, and the release
  would go out to every launcher while the source commit never landed, leaving
  the repo saying something different from what shipped. The worst possible
  half-state, on every release.

  So the bump comes first and on its own, as an ordinary commit that goes
  through whatever the branch rules are, and Ship becomes a thing that only
  READS the repository. Nothing it does needs write access to main any more,
  which is what lets the rules apply to everybody including the owner.

  It touches ONE file, launcher\app\Updater.cs, and commits only that file. Not
  `git add -A`: sweeping the whole working tree into a release commit is its
  own entry on the list, and this is the commit that used to do it.
#>
[CmdletBinding()]
param(
  [string]$To,
  [switch]$WhatIf,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent (Split-Path -Parent $Here)

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 1 }

$updaterCs = Join-Path $Here '..\..\launcher\app\Updater.cs'
if (-not (Test-Path -LiteralPath $updaterCs)) { Die "Could not find $updaterCs" }

$src = [IO.File]::ReadAllText($updaterCs)
$m = [regex]::Match($src, 'Version\s*=\s*"([^"]+)"')
if (-not $m.Success) { Die 'Could not read the version out of app\Updater.cs' }
$current = $m.Groups[1].Value

Write-Host ''
Write-Host '  THORNSWOOD  -  the launcher version' -ForegroundColor White

# The next one, or the one asked for.
if ($To) {
  if ($To -notmatch '^\d+\.\d+\.\d+$') { Die "A version is x.y.z. '$To' is not." }
  $target = $To
} else {
  $parts = $current -split '\.'
  if ($parts.Count -lt 3) { Die "The version in Updater.cs is '$current', which is not x.y.z." }
  $target = '{0}.{1}.{2}' -f $parts[0], $parts[1], ([int]$parts[2] + 1)
}

# ==== thornswood live version ====
# THE NUMBER LIVE LAUNCHERS ALREADY HAVE, from the feed Ship publishes to:
# https://thornswood.net/feed/version.json, the feed every live launcher reads
# (until #907 it was read from the Thornswood-Releases clone beside this repo).
# A hotfix moves that number on its own branch and main never hears of it. On
# 25 September main said 1.1.92 while 1.1.94 was live, so the plain bump here
# would have made 1.1.93. The updater takes a launcher only when its number is
# higher, so nobody on 1.1.94 would ever have been given it, and nobody on dev
# either, because a main release resets dev to match main. So the next number
# is one above whichever is higher, and a -To at or below the live one is
# refused. When the live feed cannot be read it says so and goes on.
# $env:THORNSWOOD_TEST_SITE_DIR names a folder standing in for the site's root
# (Feed-Store.ps1); the tests use it, so nothing is fetched.
function Compare-Ver([string]$a, [string]$b) {
  $x = @($a -split '\.' | ForEach-Object { [int]$_ })
  $y = @($b -split '\.' | ForEach-Object { [int]$_ })
  for ($i = 0; $i -lt [Math]::Max($x.Count, $y.Count); $i++) {
    $u = if ($i -lt $x.Count) { $x[$i] } else { 0 }
    $v = if ($i -lt $y.Count) { $y[$i] } else { 0 }
    if ($u -ne $v) { return $(if ($u -gt $v) { 1 } else { -1 }) }
  }
  return 0
}
function Get-LiveLauncher([string]$repoDir) {
  $v = ''
  $from = 'https://thornswood.net/feed/version.json'
  try {
    if ($env:THORNSWOOD_TEST_SITE_DIR) {
      # The newest of the feed's generations (Feed-Store.ps1, #2727).
      $gens = Join-Path $env:THORNSWOOD_TEST_SITE_DIR 'feed\version'
      if (-not (Test-Path -LiteralPath $gens)) { return $null }
      $gen = @(Get-ChildItem -LiteralPath $gens -File | Where-Object { $_.Name -match '^\d{8}\.json$' } | Sort-Object Name | Select-Object -Last 1)
      if (-not $gen.Count) { return $null }
      $from = $gen[0].FullName
      $json = [IO.File]::ReadAllText($from)
    } else {
      [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
      $wc = New-Object Net.WebClient
      $wc.Headers['User-Agent'] = 'Thornswood-Bump'
      try { $json = [Text.Encoding]::UTF8.GetString($wc.DownloadData($from)) } finally { $wc.Dispose() }
    }
    $v = [string]((($json -replace '^\uFEFF', '') | ConvertFrom-Json).launcherVersion)
  } catch { return $null }
  if ($v -notmatch '^(\d+\.\d+\.\d+)') { return $null }
  return @{ Version = $Matches[1]; From = $from }
}
$live = Get-LiveLauncher $RepoDir
if ($live) {
  if ((Compare-Ver $target $live.Version) -le 0) {
    if ($To) {
      Die ("Live launchers already have " + $live.Version + " (" + $live.From + "), and the updater only takes a " +
           "higher number, so " + $target + " would reach nobody. Give -To a number above " + $live.Version + ".")
    }
    $lp = $live.Version -split '\.'
    $was = $target
    $target = '{0}.{1}.{2}' -f $lp[0], $lp[1], ([int]$lp[2] + 1)
    Write-Host ''
    Say ("  Updater.cs says $current, so the next would be $was, but live launchers already have " +
         $live.Version + ", and a launcher only takes a higher number. So it is $target.") 'Yellow'
    Say ("  Read from " + $live.From + ", the feed live launchers read.") 'DarkGray'
  }
} else {
  Write-Host ''
  Say ('  The live feed could not be read, so this number is not checked against ' +
       'what live launchers have. Ship reads the same feed.') 'Yellow'
}
# ==== end thornswood live version ====

Head 'The number'
Say ("  {0}  ->  {1}" -f $current, $target)

if ($current -eq $target) { Die "It already says $target." }

# Nothing else may be sitting in the way, because this commits one file and a
# dirty tree means the release that follows is built from something the commit
# does not describe.
Head 'The repository'
$branch = (& git -C $RepoDir rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
$dirty = @(& git -C $RepoDir status --porcelain --untracked-files=no 2>$null | Where-Object { $_ })
Say ("  branch {0}, {1} uncommitted change(s)" -f $branch, $dirty.Count) 'DarkGray'
if ($dirty.Count) {
  foreach ($d in $dirty | Select-Object -First 10) { Say "    $d" 'Yellow' }
  Die ("There are uncommitted changes. Commit or put them back first, so the version commit is " +
       "only the version and the release is built from what is written down.")
}

if ($WhatIf) {
  Write-Host ''
  Say "  -WhatIf, so nothing was changed. It would write $target and commit launcher\app\Updater.cs." 'Yellow'
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

# One line, in place, keeping the file's own bytes otherwise.
$next = $src.Substring(0, $m.Groups[1].Index) + $target +
        $src.Substring($m.Groups[1].Index + $m.Groups[1].Length)
[IO.File]::WriteAllText($updaterCs, $next)
Say "  launcher\app\Updater.cs now says $target" 'Green'

Head 'The commit'
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
try {
  & git -C $RepoDir add -- 'launcher/app/Updater.cs' 2>&1 | Out-Null
  & git -C $RepoDir commit -q -m "Launcher $target" 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { Say '  nothing was committed' 'Yellow' }
  else { Say "  committed as Launcher $target, one file" 'Green' }
} finally { $ErrorActionPreference = $old }

Write-Host ''
Write-Host ('  ' + ('=' * 68)) -ForegroundColor DarkGray
Say '  Next, in this order:' 'White'
Write-Host ''
if ($branch -eq 'main') {
  # Whether a push to main is possible at all depends on enforce_admins in
  # branch protection, which was turned on on 22 September. With it on, NOBODY
  # pushes to main, owner included, and this commit has to go through a pull
  # request like any other. Asked rather than assumed, because the setting can
  # be changed at any time and a wrong instruction here sends somebody into a
  # refused push with a release half prepared.
  # Three answers, not two: GitHub says on, GitHub says off, or GitHub could
  # not be asked (no gh, no sign in, no network). The third used to read as
  # off and printed a direct push as allowed. It now takes the branch, which
  # works whichever way the setting is.
  $enforced = ''
  $askWhy = ''
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    $askWhy = 'gh is not on the path'
  } else {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
      $said = @(& gh api repos/EvilPatrick06/Thornswood/branches/main/protection --jq '.enforce_admins.enabled' 2>&1)
      $rc = $LASTEXITCODE
    } finally { $ErrorActionPreference = $old }
    $text = (($said | ForEach-Object { [string]$_ }) -join ' ').Trim()
    if ($rc -ne 0) { $askWhy = 'gh api answered exit ' + $rc + $(if ($text) { ': ' + $text } else { '' }) }
    elseif ($text -eq 'true' -or $text -eq 'false') { $enforced = $text }
    else { $askWhy = 'GitHub answered "' + $text + '", not true or false' }
  }
  if ($askWhy -or $enforced -eq 'true') {
    if ($askWhy) {
      Say ('  Could not ask GitHub whether main is protected against everybody (' + $askWhy + ').') 'Yellow'
      Say '  The branch below works whichever way that setting is:' 'Yellow'
    } else {
      Say '  main is protected against everybody, including you, so this cannot be' 'Yellow'
      Say '  pushed straight there. Put it on a branch:' 'Yellow'
    }
    Write-Host ''
    Say ("      git branch -f patrick/launcher-$target; git reset --hard HEAD~1; git checkout patrick/launcher-$target") 'White'
    Say '  Moves the commit you just made onto a branch and takes main back.' 'DarkGray'
    Write-Host ''
    Say ("      git push -u origin patrick/launcher-$target") 'White'
    Say '      gh pr create --fill' 'White'
    Say '  LEAVE THIS MACHINE. Merge it, then git checkout main and git pull.' 'DarkGray'
  } else {
    Say '      git push' 'White'
    Say '  LEAVES THIS MACHINE. Sends the version commit.' 'DarkGray'
    Say '  (enforce_admins is off, so a direct push to main is still allowed.)' 'DarkGray'
  }
} else {
  Say ("      git push -u origin $branch") 'White'
  Say ("      gh pr create --fill") 'White'
  Say '  LEAVE THIS MACHINE. The version lands on main through the pull request.' 'DarkGray'
}
Write-Host ''
Say ('      .\scripts\release\Ship.ps1 "what changed"') 'White'
Say '  Only once the commit above is on origin/main. Ship reads the version and' 'DarkGray'
Say '  no longer writes anything back, so it will refuse until then.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
