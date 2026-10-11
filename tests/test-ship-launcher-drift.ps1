<#
  test-ship-launcher-drift.ps1

  A main Ship refuses when the launcher on the branch has moved past the tag
  the shipped exe was built from. Issue #883.

  WHAT HAPPENED. A main release takes the exe CI built for v<version> (issue
  #457), and a main Ship does not move the version. 20260927-1633 was shipped
  on 1.1.101 without a bump, so it downloaded the exe CI built for v1.1.101 at
  deace6b, eleven hours and 23 launcher commits earlier: its Thornswood.exe is
  byte for byte the one 20260927-0508 published (sha256 38d4cd5d...). Main
  never got the menu music fix (#772, #779) its own notes announced, and
  launcher.log on the Main install still says "Menu music:
  EnsureCoreWebView2Async cannot be used before the application's event loop
  has started running" at every start. The record of the client build is
  compiled into the exe too, so the stale launcher called the new client in
  the same pack "not the recorded build" and put the old one back.

  This lifts Get-LauncherDrift out of the shipped Ship.ps1 by the parser, the
  way test-ship-ci-launcher.ps1 lifts its two functions, and runs it against a
  scratch git repository with a tag in it. It also checks that Ship.ps1 asks
  it on a main release before it takes the CI exe.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ShipPath) { $ShipPath = Join-Path (Split-Path -Parent $Here) 'scripts/release/Ship.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$src = [IO.File]::ReadAllText($ShipPath)
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$t, [ref]$e)
Yes 'Ship.ps1 parses' (@($e).Count -eq 0)

$FnAst = [System.Management.Automation.Language.FunctionDefinitionAst]
$fns = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is $FnAst }, $true)) { $fns[$f.Name] = $f.Extent.Text }
Yes 'Ship.ps1 has Get-LauncherDrift' ($fns.ContainsKey('Get-LauncherDrift'))
if (-not $fns.ContainsKey('Get-LauncherDrift')) { Done }
Invoke-Expression $fns['Get-LauncherDrift']

# ---- Ship asks it, on a main release, before the CI exe is taken ------------
$ask  = $src.IndexOf("Get-LauncherDrift `$RepoDir ('v' + `$target)")
$take = $src.IndexOf('Get-ReleaseLauncher $srcRepo $target $buildOut')
Yes 'Ship.ps1 asks Get-LauncherDrift for v$target' ($ask -ge 0)
Yes '  before it downloads the exe CI built' ($ask -ge 0 -and $take -gt $ask)
$guard = if ($ask -ge 0) { $src.Substring([Math]::Max(0, $ask - 400), 1400) } else { '' }
Yes '  only on a main release' ($guard -match 'if \(-not \$Dev -and')
Yes '  and stops it, not only a dry run' ($guard -match 'if \(\$DryRun\) \{ Say .+ \} else \{ Die \$why \}')
Yes '  -ModsOnly still stops on a changed client record' ($guard -match "if \(\`$ModsOnly\) \{ \`$drift = @\(\`$drift \| Where-Object \{ \`$_ -eq 'records/client-build\.json' \}\) \}")
Yes '  and the refusal says to move the version first' ($guard -match 'Bump-Version\.ps1')
Yes '  in the house words' ($guard -notmatch '(?i)player' -and $guard.IndexOf([char]0x2014) -lt 0)

if (-not (Get-Command git -EA SilentlyContinue)) {
    Write-Host 'SKIP  git is not on PATH, so Get-LauncherDrift is not run'
    Done
}

function G { $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; try { & git @args 2>&1 | Out-Null } finally { $ErrorActionPreference = $old } }
function Put([string]$repo, [string]$rel, [string]$text) {
    $p = Join-Path $repo $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
    [IO.File]::WriteAllText($p, $text)
}
function Commit([string]$repo, [string]$msg) {
    G -C $repo add -A
    G -C $repo -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false commit -q -m $msg
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-launcher-drift-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    G init -q $work
    Put $work 'launcher/app/Shell.cs' 'class Shell { }'
    Put $work 'launcher/README.md' 'the launcher'
    Put $work 'records/client-build.json' '{"forkCommit":"d0006351"}'
    Put $work 'records/ui-gone.json' '{"daedric":{},"unused":[]}'
    Put $work 'game/ui/thornswood-select.js' '1'
    Commit $work 'the tagged launcher'
    G -C $work -c tag.gpgsign=false tag v1.1.101

    Yes 'the tagged commit itself: nothing drifted' (@(Get-LauncherDrift $work 'v1.1.101').Count -eq 0)

    Put $work 'launcher/README.md' 'the launcher, described better'
    Put $work 'game/ui/thornswood-select.js' '2'
    Commit $work 'docs and the game page only'
    Yes 'a README under launcher and a game file are not the launcher' (@(Get-LauncherDrift $work 'v1.1.101').Count -eq 0)

    Put $work 'records/client-build.json' '{"forkCommit":"9732d2cc"}'
    Commit $work 'the client pin moves'
    $d = @(Get-LauncherDrift $work 'v1.1.101')
    Yes "the client record compiled into the exe counts: '$($d -join ', ')'" ($d -contains 'records/client-build.json')

    Put $work 'records/ui-gone.json' '{"daedric":{},"unused":["bg.png"]}'
    Commit $work 'the gone UI record moves'
    $d = @(Get-LauncherDrift $work 'v1.1.101')
    Yes "the ui-gone record compiled into the exe counts: '$($d -join ', ')'" ($d -contains 'records/ui-gone.json')

    Put $work 'launcher/app/Shell.cs' 'class Shell { void StartMenuMusic() { } }'
    Commit $work 'the menu music fix, as on 27 September'
    $d = @(Get-LauncherDrift $work 'v1.1.101')
    Yes "a launcher source change after the tag is named: '$($d -join ', ')'" ($d -contains 'launcher/app/Shell.cs')
    Yes '  the records and the source, and not the README' ($d.Count -eq 3 -and $d -notcontains 'launcher/README.md')

    Yes 'a tag that is not here drifts nothing (the CI step stops that Ship)' (@(Get-LauncherDrift $work 'v9.9.9').Count -eq 0)

    G -C $work -c tag.gpgsign=false tag v1.1.102
    Yes 'after Bump-Version and a new tag, nothing drifted' (@(Get-LauncherDrift $work 'v1.1.102').Count -eq 0)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Done
