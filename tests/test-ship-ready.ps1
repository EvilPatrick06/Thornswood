<#
  test-ship-ready.ps1

      pwsh -NoProfile -File .\tests\test-ship-ready.ps1

  Whether Check-ShipReady.ps1 says NOT READY only for what would stop a Ship.
  Issue #946.

  WHY THIS EXISTS. On 28 Sep two dev Ships from fresh worktrees ran to the end
  and published, while Check-ShipReady -Channel dev said "NOT READY. 18 passed,
  1 in the way" for each, because engine\skymp was not a clone of the skymp
  fork. A Ship never builds the engine. What it needs of the client is the
  game folder holding the recorded build, which Sync-Client.ps1 -Check
  answers, or a build that matches the record for Go.ps1 to copy in. And
  Sync-Client itself stopped on "client build not found" before looking at the
  game folder, so a worktree with no build could not Ship even when the folder
  it packs was right.

  What it runs. The row functions out of Check-ShipReady.ps1, lifted by the
  PowerShell parser (New-Row, Get-ShipVerdict, Get-ClientRows,
  Get-MainOnlyRows), against a scratch record, game folder and build, with the
  real Sync-Client.ps1 answering:
    1. A fresh worktree: no engine\skymp at all, the recorded client in the
       game folder. READY.
    2. No matching client anywhere. NOT READY, and the fix names the build
       folder, Sync-Client -Check -Dist and Build-Engine.
    3. A matching build and a game folder that differs: READY, Ship copies it.
    4. A build that is not the recorded one: READY when the game folder holds
       the recorded client, NOT READY when it does not.
    5. The main-only rows (the setup stub, the server build, issue #932): none
       on dev, WARN on main, and never a change to the verdict.
    6. The script's own text: no row asks for the fork, stale plugins and
       required-data in the game folder are notes (Ship's Go.ps1 step copies
       them in before it checks), and the main-only rows are asked only when
       the channel is main.

  Writes only to a temp folder of its own, and removes it.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Release = Join-Path (Split-Path -Parent $Here) 'scripts\release'
$Ready = Join-Path $Release 'Check-ShipReady.ps1'
$Sync = Join-Path $Release 'Sync-Client.ps1'

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" -ForegroundColor Green }
    else       { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

# ------------------------------------------------ the functions under test --
$errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Ready, [ref]$null, [ref]$errs)
Yes 'Check-ShipReady.ps1 parses' (@($errs).Count -eq 0)
$fns = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
foreach ($name in 'New-Row', 'Get-ShipVerdict', 'Get-ClientRows', 'Get-MainOnlyRows') {
    $f = @($fns | Where-Object { $_.Name -eq $name })
    Yes "Check-ShipReady.ps1 has $name" ($f.Count -eq 1)
    if ($f.Count -eq 1) { Invoke-Expression $f[0].Extent.Text }
}
if ($script:fail) { Write-Host "$($script:pass) passed, $($script:fail) failed"; exit 1 }

function Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Put([string]$root, [string]$rel, [string]$text) {
    $p = Join-Path $root $rel
    $d = Split-Path -Parent $p
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    [IO.File]::WriteAllText($p, $text)
}
function Fresh([string]$p) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $p | Out-Null
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-ship-ready-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    # A record for two files, written from their bytes.
    $client = @{ 'Data\Platform\Plugins\skymp5-client.js' = 'the recorded bundle'; 'Data\Scripts\TESModPlatform.pex' = 'the recorded pex' }
    $proto = Join-Path $tmp 'proto'
    $files = [ordered]@{}
    foreach ($rel in $client.Keys) {
        Put $proto $rel $client[$rel]
        $files[$rel] = [ordered]@{ sha256 = (Sha (Join-Path $proto $rel)); bytes = (Get-Item -LiteralPath (Join-Path $proto $rel)).Length }
    }
    $record = Join-Path $tmp 'client-build.json'
    ([ordered]@{ forkCommit = 'abcdef12'; forkBranch = 'thornswood/engine-changes'; recordedUtc = '2026-09-28T00:00:00Z'; files = $files } |
        ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $record -Encoding UTF8

    $game = Join-Path $tmp 'Game'
    $dist = Join-Path $tmp 'worktree\engine\skymp\build\dist\client'   # never made unless a case makes it

    function Set-Game([string]$how) {
        Fresh $game
        if ($how -eq 'empty') { return }
        foreach ($rel in $client.Keys) { Put $game $rel $client[$rel] }
        if ($how -eq 'wrong') { Put $game 'Data\Platform\Plugins\skymp5-client.js' 'another launcher''s bundle' }
    }
    function Set-Dist([string]$how) {
        $top = Join-Path $tmp 'worktree\engine'
        if (Test-Path -LiteralPath $top) { Remove-Item -LiteralPath $top -Recurse -Force }
        if ($how -eq 'none') { return }
        foreach ($rel in $client.Keys) { Put $dist $rel $client[$rel] }
        if ($how -eq 'wrong') { Put $dist 'Data\Scripts\TESModPlatform.pex' 'a pex from an edited engine' }
    }
    function Client-Rows { return @(Get-ClientRows $Sync $record $game $dist) }
    function Client-Row { return @(Client-Rows | Where-Object { $_.What -like 'the recorded client*' })[0] }

    # ------------------------------------------------ 1. a fresh worktree --
    Set-Game 'recorded'; Set-Dist 'none'
    $global:LASTEXITCODE = 0
    & $Sync -Check -NoPause -Game $game -Dist $dist -Record $record 6>$null | Out-Null
    Yes '1. Sync-Client -Check answers 0 with no build, when the game folder holds the recorded client' ($LASTEXITCODE -eq 0)
    $global:LASTEXITCODE = 0
    & $Sync -NoPause -Game $game -Dist $dist -Record $record 6>$null | Out-Null
    Yes '1. Sync-Client without -Check (what Go.ps1 runs) answers 0 as well, and copies nothing' ($LASTEXITCODE -eq 0)
    $rows = Client-Rows
    Yes '1. the client rows all pass with no engine\skymp at all' (@($rows | Where-Object { -not $_.Ok }).Count -eq 0)
    Yes '1. and there are two: the record and the client' ($rows.Count -eq 2)
    $v = Get-ShipVerdict $rows
    Yes '1. the verdict is READY' ($v.Ready)
    # The script keeps its rows in a List, and @() over one threw "Argument
    # types do not match" the first time this ran for real.
    $list = New-Object Collections.Generic.List[object]
    foreach ($r in $rows) { $list.Add($r) }
    $v = $null
    try { $v = Get-ShipVerdict $list } catch { Write-Host ('      threw: ' + $_.Exception.Message) -ForegroundColor Red }
    Yes '1. and the same from the List the script keeps its rows in' ($null -ne $v -and $v.Ready -and $v.Passed -eq 2)

    # --------------------------------------------- 2. no matching client --
    Set-Game 'wrong'; Set-Dist 'none'
    $global:LASTEXITCODE = 0
    & $Sync -Check -NoPause -Game $game -Dist $dist -Record $record 6>$null | Out-Null
    Yes '2. Sync-Client -Check answers 1 with no build and a game folder that is not the recorded client' ($LASTEXITCODE -eq 1)
    $r = Client-Row
    Yes '2. the client row fails' (-not $r.Ok)
    Yes '2. and it is a need, not a warn' ($r.Level -eq 'need')
    Yes '2. it says the build was not found and the game folder is not right' ($r.Detail -match 'client build not found' -and $r.Detail -match '1 of 2 in place')
    Yes '2. the fix names the build folder' ($r.Fix.Contains($dist))
    Yes '2. the fix says how to check a candidate and how to build one' ($r.Fix -match 'Sync-Client\.ps1 -Check -Dist' -and $r.Fix -match 'Build-Engine\.ps1')
    Yes '2. the verdict is NOT READY' (-not (Get-ShipVerdict (Client-Rows)).Ready)

    Set-Game 'empty'; Set-Dist 'none'
    Yes '2. an empty game folder and no build is NOT READY too' (-not (Get-ShipVerdict (Client-Rows)).Ready)

    # ------------------------------------- 3. a build Ship copies in itself --
    Set-Game 'wrong'; Set-Dist 'recorded'
    $r = Client-Row
    Yes '3. a matching build with a game folder that differs passes (Go.ps1 copies it in)' ($r.Ok)
    Yes '3. and says Ship copies it' ($r.Detail -match 'Ship copies it in')
    Set-Game 'empty'; Set-Dist 'recorded'
    Yes '3. so does a matching build with nothing in the game folder yet' ((Client-Row).Ok)

    # ------------------------------------ 4. a build that is not recorded --
    Set-Game 'recorded'; Set-Dist 'wrong'
    Yes '4. a stale build does not matter when the game folder holds the recorded client' ((Client-Row).Ok)
    Set-Game 'wrong'; Set-Dist 'wrong'
    $r = Client-Row
    Yes '4. a stale build and a game folder that differs fail' (-not $r.Ok)
    Yes '4. saying the build is not the recorded one' ($r.Detail -match 'not the recorded one')

    # No game folder: only the record is asked, and nothing runs.
    $rows = @(Get-ClientRows $Sync $record '' $dist)
    Yes 'no game folder: only the record row' ($rows.Count -eq 1 -and $rows[0].Ok)
    $rows = @(Get-ClientRows $Sync (Join-Path $tmp 'nothing.json') $game $dist)
    Yes 'no record: the record row fails as a need' ($rows.Count -eq 1 -and -not $rows[0].Ok -and $rows[0].Level -eq 'need')

    # -------------------------------------------------- 5. main-only rows --
    $outDir = Join-Path $tmp 'out'
    $stub = Join-Path $outDir 'setup-stub.exe'
    $pkgStub = Join-Path $tmp 'out\dist\Thornswood\_dist\setup-stub.exe'
    $boot = Join-Path $tmp 'installer\setup\Bootstrap.cs'
    Put $tmp 'installer\setup\Bootstrap.cs' 'class Bootstrap {}'
    (Get-Item -LiteralPath $boot).LastWriteTimeUtc = [datetime]::UtcNow.AddHours(-2)
    $srv = Join-Path $tmp 'engine\skymp\build\dist\server'
    $payload = Join-Path $tmp 'out\_payload'
    Put $payload 'scam_native.node' 'the recorded server'
    $srvRecord = Join-Path $tmp 'server-build.json'
    (@{ binary = 'scam_native.node'; sha256 = (Sha (Join-Path $payload 'scam_native.node')) } | ConvertTo-Json) |
        Set-Content -LiteralPath $srvRecord -Encoding UTF8
    function Main-Rows([string]$chan) { return @(Get-MainOnlyRows $chan @($stub, $pkgStub) $boot $srvRecord @($srv, $payload)) }

    Yes '5. dev asks for none of the main-only rows' (@(Main-Rows 'dev').Count -eq 0)

    $m = @(Main-Rows 'main')
    Yes '5. main asks for the setup stub and the server build' ($m.Count -eq 2)
    Yes '5. both are warnings' (@($m | Where-Object { $_.Level -ne 'warn' }).Count -eq 0)
    $s = @($m | Where-Object { $_.What -like '*setup stub*' })[0]
    Yes '5. no stub: the stub row fails' (-not $s.Ok)
    Yes '5. and its fix is Build-Launcher into a scratch root' ($s.Fix -match 'Build-Launcher\.ps1 -Root')
    $b = @($m | Where-Object { $_.What -like '*server build*' })[0]
    Yes '5. the server row fails when only out\_payload matches' (-not $b.Ok)
    Yes '5. naming the folder that does match' ($b.Detail.Contains($payload + ' does'))
    Yes '5. and says to pass a scratch copy of it as -Dist' ($b.Fix -match 'scratch' -and $b.Fix -match '-Dist')

    Set-Game 'recorded'; Set-Dist 'none'
    $v = Get-ShipVerdict (@(Client-Rows) + $m)
    Yes '5. a fresh worktree on main with both warnings is still READY' ($v.Ready)
    Yes '5. and lists the two warnings' ($v.Warns.Count -eq 2)

    Put $outDir 'setup-stub.exe' 'stub'
    Put $srv 'scam_native.node' 'the recorded server'
    $m = @(Main-Rows 'main')
    Yes '5. a stub newer than Bootstrap.cs and a matching server build pass' (@($m | Where-Object { -not $_.Ok }).Count -eq 0)

    (Get-Item -LiteralPath $stub).LastWriteTimeUtc = [datetime]::UtcNow.AddHours(-3)
    $s = @(Main-Rows 'main' | Where-Object { $_.What -like '*setup stub*' })[0]
    Yes '5. a stub older than Bootstrap.cs fails, saying so' (-not $s.Ok -and $s.Detail -match 'older than')

    Remove-Item -LiteralPath $stub -Force
    Put (Split-Path -Parent $pkgStub) 'setup-stub.exe' 'stub'
    $s = @(Main-Rows 'main' | Where-Object { $_.What -like '*setup stub*' })[0]
    Yes '5. a stub beside the package output counts, as Package-Thornswood takes it from there too' ($s.Ok)

    Put $srv 'scam_native.node' 'an edited server'
    Put $payload 'scam_native.node' 'another edited server'
    $b = @(Main-Rows 'main' | Where-Object { $_.What -like '*server build*' })[0]
    Yes '5. no matching server build anywhere fails, pointing at Build-Engine' (-not $b.Ok -and $b.Fix -match 'Build-Engine')

    # ------------------------------------------------- 6. the script's text --
    $text = Get-Content -LiteralPath $Ready -Raw
    Yes '6. no row asks whether the skymp fork is cloned' ($text -notmatch "Ready\s+'the skymp fork")
    Yes '6. no row asks which branch the fork is on' ($text -notmatch "Ready\s+'the fork is on")
    # Ship runs Go.ps1 before it checks either, and Go.ps1 copies both in.
    Yes '6. stale plugins in the game folder are a note, not a gap' ($text -notmatch "Ready\s+'the game folder holds this source")
    Yes '6. stale required-data in the game folder is a note, not a gap' ($text -notmatch "Ready\s+'the game folder holds required-data")
    Yes '6. the main-only rows are asked only when the channel is not dev' ($text -match '(?s)if \(-not \$Dev\) \{\s*Head [^\n]*\n[^\n]*\n\s*foreach \(\$r in @\(Get-MainOnlyRows')
    Yes '6. the verdict is Get-ShipVerdict''s, and exit 1 follows it' ($text -match '\$verdict = Get-ShipVerdict \$script:rows' -and $text -match 'if \(-not \$verdict\.Ready\) \{ exit 1 \}')
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
exit 0
