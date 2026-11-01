<#
  test-5207-pin-from-index.ps1

      pwsh -NoProfile -File .\tests\test-5207-pin-from-index.ps1

  Issue #5207. scripts\release\Update-EnginePin.ps1 moves engine\skymp in the
  index (git update-index), writes the records of the new commit, and runs
  tests\test-one-engine.js before it commits. test-one-engine.js read the pin
  from HEAD, so on 1 Nov 2026 the engine pin robot's first pin stopped there
  with every record already at the new commit. It reads the index now, which
  is HEAD on a clean checkout such as the build check's.

  WHAT IT HOLDS, in a scratch git checkout planted with this tree's records,
  .gitmodules, engine\README.md, scripts\deploy\ServerBuild.ps1 and
  test-one-engine.js:
    1. HEAD and the index pinning the records' commit: it passes.
    2. HEAD pinning another commit, the index moved to the records' commit
       (Update-EnginePin's case): it passes.
    3. HEAD pinning the records' commit, the index moved to another one: it
       fails, naming the moved pin.
    4. Build-Front.ps1 reads the pin from the index too (the same reason).

  Writes only in its own scratch folder, which it removes. Needs git and node.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$env:THORNSWOOD_HARNESS = '1'
$Here = Split-Path -Parent $PSScriptRoot
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$ok) {
    if ($ok) { $script:pass++; Write-Host "PASS  $what" -ForegroundColor Green }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function G([string]$repo, [string[]]$a) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = @(& git -C $repo @a 2>&1 | ForEach-Object { "$_" }); if ($LASTEXITCODE -ne 0) { throw ('git ' + ($a -join ' ') + ': ' + ($o -join ' ')) } ; return $o }
    finally { $ErrorActionPreference = $old }
}
function Check([string]$repo) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = & node (Join-Path $repo 'tests/test-one-engine.js') 2>&1 | Out-String; return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o } }
    finally { $ErrorActionPreference = $old }
}

$recorded = ((G $Here @('ls-files', '-s', 'engine/skymp')) -join '' -split '\s+')[1]
$other = 'a' * 40

$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-5207-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $T
try {
    foreach ($rel in @('tests/test-one-engine.js', 'records/client-build.json', 'records/server-build.json', 'records/front-build.json',
                       '.gitmodules', 'engine/README.md', 'scripts/deploy/ServerBuild.ps1')) {
        $to = Join-Path $T $rel
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to)
        Copy-Item -LiteralPath (Join-Path $Here $rel) -Destination $to
    }
    $null = G $T @('init', '-q')
    $null = G $T @('-c', 'user.name=t', '-c', 'user.email=t@t', 'add', '-A')
    $null = G $T @('update-index', '--add', '--cacheinfo', "160000,$recorded,engine/skymp")
    $null = G $T @('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-m', 'the records'' commit')

    $r = Check $T
    Yes ("1. HEAD and the index pin the records' commit: it passes (exit {0})" -f $r.Code) ($r.Code -eq 0)

    $null = G $T @('update-index', '--cacheinfo', "160000,$other,engine/skymp")
    $null = G $T @('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-m', 'another pin')
    $null = G $T @('update-index', '--cacheinfo', "160000,$recorded,engine/skymp")
    $r = Check $T
    Yes ("2. HEAD pins another commit and the index the records' one, as Update-EnginePin leaves it: it passes (exit {0})" -f $r.Code) ($r.Code -eq 0 -and $r.Out -match ('the index pins engine/skymp to a commit \(' + $recorded.Substring(0, 8) + '\)'))

    $null = G $T @('-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '-m', 'back')
    $null = G $T @('update-index', '--cacheinfo', "160000,$other,engine/skymp")
    $r = Check $T
    Yes ("3. HEAD pins the records' commit and the index another: it fails, naming the moved pin (exit {0})" -f $r.Code) ($r.Code -ne 0 -and $r.Out -match ('engine/skymp is pinned to ' + $other.Substring(0, 8)))

    $bf = [IO.File]::ReadAllText((Join-Path $Here 'scripts/release/Build-Front.ps1'))
    Yes '4. Build-Front.ps1 reads the pin from the index' ($bf -match [regex]::Escape("ls-files -s engine/skymp 2>`$null) -split '\s+')[1]") -and $bf -notmatch 'ls-tree HEAD engine/skymp')
}
finally {
    if (Test-Path -LiteralPath $T) { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
