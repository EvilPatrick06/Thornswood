<#
  Check-ShipReady.ps1

  Whether THIS machine can run a release, and what is missing if it cannot.

      .\tools\Check-ShipReady.ps1              the main channel
      .\tools\Check-ShipReady.ps1 -Channel dev the dev channel
      .\tools\Check-ShipReady.ps1 -NoVps       skip the two checks that ask the VPS

  WHY IT EXISTS. Ship.ps1 has fourteen ways to refuse, and every one of them is
  found by running Ship and being stopped, usually after the launcher has
  already been compiled and the version already bumped. That is fine on the one
  machine where everything has been in place for months. It is the whole
  problem on a second machine, where the answer to "can I ship" was: try it and
  read whichever refusal comes first, fix that, try again. Djinn has never
  shipped, and nothing written down says what he would need.

  This asks every question Ship asks, before Ship does, and changes nothing.
  Each gap prints the exact command that closes it. It does not ship, publish,
  deploy, push or write anything outside its own output.

  It is deliberately not part of Ship. Ship's refusals stay where they are:
  they are the gate, and a gate that can be satisfied by a different script is
  not a gate. This is the map, not the key.
#>
[CmdletBinding()]
param(
  [ValidateSet('main','dev')]
  [string]$Channel = 'main',
  [switch]$NoVps,
  [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent $Here
$Dev = ($Channel -eq 'dev')

$script:gaps = New-Object Collections.Generic.List[object]
$script:ok = 0

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

# $fix is the command that closes the gap, or $null when it is somebody's
# decision rather than a command. $who is who runs it.
function Ready([string]$what, [bool]$cond, [string]$detail, [string]$fix, [string]$who = 'either') {
  if ($cond) {
    $script:ok++
    Say ("  yes   " + $what + $(if ($detail) { "  ($detail)" } else { '' })) 'Green'
  } else {
    Say ("  NO    " + $what + $(if ($detail) { "  ($detail)" } else { '' })) 'Red'
    $script:gaps.Add([pscustomobject]@{ What = $what; Fix = $fix; Who = $who })
  }
}

Write-Host ''
Write-Host ("  THORNSWOOD  -  can this machine ship? (" + $Channel + " channel)") -ForegroundColor White

# ---------------------------------------------------------------- the repo --
Head 'This repository'
$isClone = Test-Path (Join-Path $RepoDir '.git')
Ready 'this is a git clone' $isClone $RepoDir 'git clone https://github.com/EvilPatrick06/Thornswood.git'

if ($isClone) {
  $branch = (& git -C $RepoDir rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim()
  $dirty  = @(& git -C $RepoDir status --porcelain --untracked-files=no 2>$null | Where-Object { $_ })
  & git -C $RepoDir fetch --quiet origin 2>$null | Out-Null
  $behind = 0
  try { $behind = [int]((& git -C $RepoDir rev-list --count "HEAD..origin/$branch" 2>$null | Out-String).Trim()) } catch { $behind = 0 }

  if ($Dev) {
    Say ("  note  a dev release may ship from any branch. This is " + $branch + ".") 'DarkGray'
    $script:ok++
  } else {
    Ready 'on main' ($branch -eq 'main') ("on " + $branch) 'git checkout main' 'either'
    Ready 'not behind origin/main' ($behind -eq 0) ("$behind behind") 'git pull' 'either'
  }
  if ($dirty.Count) {
    Say ("  note  " + $dirty.Count + " uncommitted change(s). A main Ship builds from them and commits them when it is out.") 'DarkGray'
  }
}

# ------------------------------------------------------------ the releases --
Head 'The releases repository'
$ReleaseDir = Join-Path (Split-Path -Parent $RepoDir) 'Thornswood-Releases'
$hasRel = Test-Path (Join-Path $ReleaseDir 'version.json')
Ready 'Thornswood-Releases is cloned beside this repo' $hasRel $ReleaseDir `
  ("git clone https://github.com/EvilPatrick06/Thornswood-Releases.git " + $ReleaseDir)

if ($Dev) {
  $devRel = Join-Path (Split-Path -Parent $RepoDir) 'Thornswood-Releases-dev'
  $hasDev = Test-Path (Join-Path $devRel 'version.json')
  Ready 'the dev release worktree exists' $hasDev $devRel `
    'Ship.ps1 -Channel dev makes it on first use; nothing to do by hand'
}

# GitHub itself, because a release is pushed there and a clone proves nothing
# about whether this account may push.
$ghOk = $false
$ghWho = ''
try {
  $st = & gh auth status 2>&1 | Out-String
  $ghOk = ($LASTEXITCODE -eq 0)
  $m = [regex]::Match($st, 'account\s+(\S+)')
  if ($m.Success) { $ghWho = $m.Groups[1].Value }
} catch { $ghOk = $false }
Ready 'signed in to GitHub' $ghOk $ghWho 'gh auth login'

if ($ghOk) {
  $canPush = $false
  try {
    $p = & gh api repos/EvilPatrick06/Thornswood-Releases --jq '.permissions.push' 2>$null
    $canPush = ("$p".Trim() -eq 'true')
  } catch { $canPush = $false }
  Ready 'this account may push to Thornswood-Releases' $canPush $ghWho `
    'Patrick adds the account under Settings, Collaborators on the Thornswood-Releases repository' 'patrick'
}

# --------------------------------------------------------- the install root --
Head 'The launcher install'
function Find-Root {
  $first = 'C:\Thornswood'
  if (Test-Path -LiteralPath (Join-Path $first 'Launcher\Thornswood.exe')) { return $first }
  foreach ($d in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
    $cand = Join-Path $d.Root 'Thornswood'
    if (Test-Path -LiteralPath (Join-Path $cand 'Launcher\Thornswood.exe')) { return $cand }
  }
  return $first
}
$PlayRoot = Find-Root
$Root = if ($Dev) { $PlayRoot + '-DevBuild' } else { $PlayRoot }
Ready 'a launcher is installed' (Test-Path (Join-Path $Root 'Launcher\Thornswood.exe')) $Root `
  $(if ($Dev) { 'In the main launcher: Settings, The dev build, Install it' } else { 'Install Thornswood from thornswood.net' })

$GameDir = Join-Path $Root 'Game'
$hasGame = Test-Path $GameDir

# The collection this machine would build a release from.
#
# Asked here because this is the question that went unasked for a week: the
# server's load order and the reference plugin list are both derived from
# what Vortex has deployed here, and nothing checked whether that deployment
# was current. Vortex knew all along and wrote it in its own state.
try {
    . (Join-Path $Here 'LoadOrder.ps1')
    $colUrl = ''
    try { $colUrl = [string](Get-Content -LiteralPath (Join-Path $Root 'config.json') -Raw | ConvertFrom-Json).CollectionUrl } catch { }
    $cs = Get-CollectionState $colUrl
    if ($cs.Known) {
        Ready 'the collection here is the newest Vortex knows of' (-not $cs.Behind) `
            ("revision {0}, newest {1}" -f $cs.Have, $cs.Newest) `
            'Update the collection in Vortex, let it deploy, then Deploy-Gamemode and ship. A release built from a stale collection turns away everybody who installed the current one.' 'patrick'
    } else {
        Say '  note  could not read the collection revision from Vortex, so it was not checked' 'DarkGray'
    }
} catch { Say '  note  the collection revision check did not run' 'DarkGray' }
Ready 'it has its own game folder' $hasGame $GameDir `
  'Open the launcher and press Play once; it builds the folder from what Vortex has deployed'

if ($hasGame) {
  $record = Join-Path $Root 'Profile\OwnGame\files.txt'
  $recLines = 0
  if (Test-Path -LiteralPath $record) { $recLines = @(Get-Content -LiteralPath $record).Count }
  Ready 'the record of what came from Vortex exists' ($recLines -gt 0) ("$recLines lines") `
    'In the launcher: Settings, Maintenance, Bring it up to date from Vortex'
}

# ------------------------------------------------------------- the compiler --
Head 'The build'
$csc = @(
  "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
  "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
Ready 'the .NET Framework 4 compiler is here' ($null -ne $csc) $csc `
  'Install the .NET Framework 4, which is unusual to be missing on Windows 10 or 11'

$node = $null
try { $node = (Get-Command node -EA Stop).Source } catch { }
Ready 'node is on the path' ($null -ne $node) $(if ($node) { (& node --version 2>$null) } else { '' }) `
  'Install Node from nodejs.org; the gamemode and the site are checked with it'

# ------------------------------------------------------------- the plugins --
Head 'The game plugins'
if ($hasGame) {
  $plugSrc = Join-Path $Here 'ts-plugins'
  $plugDst = Join-Path $GameDir 'Data\Platform\Plugins'
  $seen = 0; $stale = @()
  foreach ($f in @(Get-ChildItem -LiteralPath $plugSrc -Filter '*.js' -File -EA SilentlyContinue)) {
    $seen++
    $dst = Join-Path $plugDst $f.Name
    if (-not (Test-Path -LiteralPath $dst)) { $stale += ($f.Name + ' never arrived'); continue }
    $a = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    $b = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash
    if ($a -ne $b) { $stale += ($f.Name + ' in the game folder is not this source') }
  }
  Ready 'tools\ts-plugins has plugins to ship' ($seen -gt 0) "$seen file(s)" 'Nothing to do; the repo is missing its plugins'
  Ready 'the game folder holds this source' ($stale.Count -eq 0) $(if ($stale.Count) { $stale[0] } else { "$seen match" }) `
    '.\tools\Go.ps1     copies the repo''s plugins into the game folder'
} else {
  Say '  skip  no own game folder, so there is nothing to compare the plugins against' 'DarkGray'
}

# -------------------------------------------------------- the client build --
Head 'The client runtime'
$rec = Join-Path $Here 'client-build.json'
Ready 'the client build record is in the repo' (Test-Path $rec) 'tools\client-build.json' `
  'It is tracked in git, so git pull brings it'

$fork = (& (Join-Path $PSScriptRoot 'Where.ps1') Engine)
$hasFork = Test-Path (Join-Path $fork '.git')
$forkBranch = ''
if ($hasFork) { $forkBranch = (& git -C $fork rev-parse --abbrev-ref HEAD 2>$null | Out-String).Trim() }
Ready 'the skymp fork is cloned' $hasFork $fork `
  ('git clone -b thornswood/engine-changes https://github.com/EvilPatrick06/skymp.git ' + $fork)
if ($hasFork) {
  Ready 'the fork is on thornswood/engine-changes' ($forkBranch -eq 'thornswood/engine-changes') $forkBranch `
    ('git -C ' + $fork + ' checkout thornswood/engine-changes')
}

if ($hasGame -and (Test-Path $rec)) {
  # global:, never a bare assignment, and 6>&1 as well as 2>&1: Sync-Client
  # reports with Write-Host, which is the information stream, so a plain
  # 2>&1 | Out-Null leaves its whole six line listing in the middle of this
  # report. The same LASTEXITCODE trap Ship.ps1 records applies here: a child
  # script's exit lands in the global one.
  $global:LASTEXITCODE = 0
  & (Join-Path $Here 'Sync-Client.ps1') -Check -NoPause -Game $GameDir 6>&1 2>&1 | Out-Null
  $code = $LASTEXITCODE
  Ready 'the game folder holds the recorded client' ($code -eq 0) ("Sync-Client -Check exit $code") `
    $(if ($code -eq 2) { '.\tools\Sync-Client.ps1' } else { 'Rebuild the client, then .\tools\New-ClientBuildRecord.ps1' })
}

# -------------------------------------------------------- the server build --
Head 'The server binary'
$srec = Join-Path $Here 'server-build.json'
Ready 'the server build record is in the repo' (Test-Path $srec) 'tools\server-build.json' 'git pull brings it'
if ((Test-Path $srec) -and $hasFork) {
  $bin = Join-Path $fork 'build\dist\server\scam_native.node'
  if (Test-Path -LiteralPath $bin) {
    $want = (Get-Content $srec -Raw | ConvertFrom-Json).sha256
    $got = (Get-FileHash -LiteralPath $bin -Algorithm SHA256).Hash.ToLowerInvariant()
    Ready 'the built binary matches the record' ($got -eq $want) $got '.\tools\New-ClientBuildRecord.ps1 after a rebuild'
  } else {
    Ready 'the server binary is built' $false $bin `
      'Build the fork. Deploy-Server needs it; a Ship does not.'
  }
}

# ---------------------------------------------------------------- the VPS ---
Head 'The VPS'
if ($NoVps) {
  Say '  skip  -NoVps was given' 'DarkGray'
} else {
  $sshOk = $false
  try {
    $out = & ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 Administrator@192.135.112.23 'echo THORNSWOOD_OK' 2>&1 | Out-String
    $sshOk = ($out -match 'THORNSWOOD_OK')
  } catch { $sshOk = $false }
  Ready 'ssh to the VPS works without a password' $sshOk '192.135.112.23' `
    '.\tools\Setup-SshKey.ps1        then Patrick runs .\tools\Add-VpsKey.ps1 to put the public half on the box' 'either'
  Say '  note  ssh is needed by Deploy-*, Publish-Server and the Check scripts that ask the box. A Ship itself does not use it.' 'DarkGray'
}

# --------------------------------------------------------------- the verdict --
Write-Host ''
Write-Host ('  ' + ('=' * 68)) -ForegroundColor DarkGray
if ($script:gaps.Count -eq 0) {
  Say ("  READY. {0} checks passed. This machine can run a {1} release." -f $script:ok, $Channel) 'Green'
  Write-Host ''
  if ($Dev) {
    Say '      .\tools\Ship.ps1 -Channel dev "what changed"' 'White'
    Say '  Say in #dev when you take the dev feed: there is one, and the last dev Ship wins.' 'DarkGray'
  } else {
    Say '      .\tools\Ship.ps1 "what changed"' 'White'
    Say '  That publishes to everybody. Only run it from main, with the pull done.' 'DarkGray'
  }
} else {
  Say ("  NOT READY. {0} passed, {1} in the way." -f $script:ok, $script:gaps.Count) 'Red'
  Write-Host ''
  $i = 0
  foreach ($g in $script:gaps) {
    $i++
    Say ("  {0}. {1}" -f $i, $g.What) 'Yellow'
    if ($g.Fix) {
      $tag = if ($g.Who -eq 'patrick') { '   (Patrick runs this one)' } else { '' }
      Say ("       " + $g.Fix + $tag) 'White'
    }
  }
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
if ($script:gaps.Count) { exit 1 }
