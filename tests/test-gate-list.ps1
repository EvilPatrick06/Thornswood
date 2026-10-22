<#
  test-gate-list.ps1

      pwsh -NoProfile -File .\tests\test-gate-list.ps1

  The gate runs what scripts\dev\Gate-Harnesses.ps1 lists, and that is every
  tests\test-*.js and tests\test-*.ps1 that tests\gate-excluded.txt does not
  name.

  WHY THIS EXISTS. Issue #1589: the gate list was one PowerShell assignment in
  build.yml spread over many lines, and a line with no comma after it ended
  the list there, so test-page-changed.js sat under it, read as part of it,
  and never ran. Issue #3009: every pull request adding a harness appended to
  the end of that list, so any two of them conflicted in build.yml and
  build-pr.yml, and a conflicted pull request gets no build. The list is now
  read from the files at run time and there is no hand-kept list to break.

  So this checks:
    1. Gate-Harnesses.ps1 over planted folders: it prints every test-*.js and
       test-*.ps1 not excluded, in name order, and nothing else; and it stops
       with exit 1 on a line with no reason, a file that is not there, a name
       twice, lines out of name order, and nothing left to run;
    2. the real repository: it lists without a fault, test-page-changed.js
       and this harness among them;
    3. build.yml's gate step and scripts\dev\Run-Gate.ps1, which it runs
       (#3114), parsed with the PowerShell parser the runner uses: the
       script calls Gate-Harnesses.ps1, stops when that fails, runs what it
       returns through Nightly-Harnesses.ps1 (all of it unless a pull
       request's map chose fewer) and fails when that does, and neither
       names a harness itself, since a name there is a second list that
       grows by appending.

  Read only, apart from the planted folders under TEMP, which it removes.
#>
[CmdletBinding()]
param([string]$Workflow)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $Workflow) { $Workflow = Join-Path (Join-Path (Join-Path $Repo '.github') 'workflows') 'build.yml' }
$Lister = Join-Path (Join-Path (Join-Path $Repo 'scripts') 'dev') 'Gate-Harnesses.ps1'

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

# Gate-Harnesses.ps1 in a process of its own, over one repository.
function Invoke-Lister([string]$root) {
    $out = @(& pwsh -NoProfile -File $Lister -Root $root 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out; Text = ($out -join "`n") }
}

# A planted repository: these files in tests, and gate-excluded.txt as given.
function New-Planted([string[]]$files, [string[]]$excluded) {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('ts-gate-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $root 'tests')
    foreach ($n in $files) { Set-Content -LiteralPath (Join-Path (Join-Path $root 'tests') $n) -Value '# stand-in' }
    if ($null -ne $excluded) { Set-Content -LiteralPath (Join-Path (Join-Path $root 'tests') 'gate-excluded.txt') -Value $excluded }
    $root
}

Yes 'scripts\dev\Gate-Harnesses.ps1 is there' (Test-Path -LiteralPath $Lister)
if (-not (Test-Path -LiteralPath $Lister)) { Done }

# --- 1. planted
$planted = @()
try {
    $files = 'test-b.ps1', 'test-a.js', 'test-c.js', 'test-off.ps1', 'test-own.js', 'test-x.py', 'helper.js', 'test-z.txt'
    $good = New-Planted $files @(
        '# comment lines are skipped',
        '',
        'test-off.ps1  needs a game install',
        'test-own.js  own step in build.yml, "Some step"')
    $planted += $good
    $r = Invoke-Lister $good
    Yes 'planted: a good list exits 0' ($r.Code -eq 0)
    Yes ('planted: it prints every test-*.js and test-*.ps1 not excluded, in name order, and nothing else (' + ($r.Out -join ', ') + ')') (
        ($r.Out -join '|') -eq 'test-a.js|test-b.ps1|test-c.js')

    $none = New-Planted $files $null
    $planted += $none
    $r = Invoke-Lister $none
    Yes 'planted: with no gate-excluded.txt every harness is on the gate' ($r.Code -eq 0 -and ($r.Out -join '|') -eq 'test-a.js|test-b.ps1|test-c.js|test-off.ps1|test-own.js')

    $cases = @(
        @{ What = 'a line with no reason'; Lines = @('test-off.ps1'); Want = 'line=1::test-off\.ps1 has no reason' },
        @{ What = 'a file that is not in tests'; Lines = @('test-gone.ps1  removed long ago'); Want = 'line=1::test-gone\.ps1 is not a file in tests' },
        @{ What = 'a name twice'; Lines = @('test-off.ps1  one', 'test-off.ps1  two'); Want = 'line=2::test-off\.ps1 is on line 1 already' },
        @{ What = 'lines out of name order'; Lines = @('test-own.js  one', 'test-off.ps1  two'); Want = 'line=2::test-off\.ps1 is out of name order, after test-own\.js' },
        @{ What = 'nothing left to run'; Lines = @('test-a.js  a', 'test-b.ps1  b', 'test-c.js  c', 'test-off.ps1  d', 'test-own.js  e'); Want = 'no harness in .* is on the gate' }
    )
    foreach ($c in $cases) {
        $root = New-Planted $files $c.Lines
        $planted += $root
        $r = Invoke-Lister $root
        $listed = @($r.Out | Where-Object { $_ -match '^test-' })
        Yes ("planted: {0} stops it with exit 1, names the fault and lists nothing" -f $c.What) (
            $r.Code -eq 1 -and $r.Text -match $c.Want -and $listed.Count -eq 0)
    }
}
finally {
    foreach ($p in $planted) { Remove-Item -LiteralPath $p -Recurse -Force -EA SilentlyContinue }
}

# --- 2. this repository
$r = Invoke-Lister $Repo
foreach ($l in @($r.Out | Where-Object { $_ -notmatch '^test-' })) { Write-Host "        $l" }
Yes 'this repository''s gate list has no fault' ($r.Code -eq 0)
Yes ('and has harnesses in it ({0})' -f $r.Out.Count) ($r.Out.Count -gt 10)
Yes 'test-page-changed.js is on the gate (#1589)' ($r.Out -contains 'test-page-changed.js')
Yes 'and so is this harness' ($r.Out -contains 'test-gate-list.ps1')

# --- 3. build.yml's gate step, and scripts\dev\Run-Gate.ps1, which it runs
# The script of the step that runs Run-Gate.ps1, as the runner gets it:
# the lines under its "run: |", with the block's indentation taken off. A YAML
# block scalar ends at the first line indented less than its first line.
function Get-GateScript([string]$yaml) {
    $lines = $yaml -split "`r?`n"
    $at = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*[^#\s].*Run-Gate\.ps1') { $at = $i; break } }
    if ($at -lt 0) { return $null }
    $run = -1
    for ($i = $at; $i -ge 0; $i--) { if ($lines[$i] -match '^\s*run:\s*\|') { $run = $i; break } }
    if ($run -lt 0) { return $null }
    $first = $run + 1
    while ($first -lt $lines.Count -and $lines[$first].Trim() -eq '') { $first++ }
    $indent = $lines[$first].Length - $lines[$first].TrimStart().Length
    $body = New-Object System.Collections.ArrayList
    for ($i = $first; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Trim() -ne '' -and ($l.Length - $l.TrimStart().Length) -lt $indent) { break }
        if ($l.Length -ge $indent) { [void]$body.Add($l.Substring($indent)) } else { [void]$body.Add('') }
    }
    return ($body -join "`n")
}
# Every string in a script that names a harness, and every word outside a
# comment or a string that does.
function Get-Named([string]$text) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errors)
    $named = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -match 'test-[\w.-]+\.(js|ps1)'
    }, $true) | ForEach-Object { $_.Value })
    $named += @($tokens | Where-Object { $_.Kind -ne 'Comment' -and $_.Text -match 'test-[\w.-]+\.(js|ps1)' -and $_.Kind -ne 'StringLiteral' -and $_.Kind -ne 'StringExpandable' } | ForEach-Object { $_.Text })
    [pscustomobject]@{ Errors = @($errors).Count; Named = $named }
}

if (-not (Test-Path -LiteralPath $Workflow)) { Yes "build.yml is at $Workflow" $false; Done }
$gate = Get-GateScript ([IO.File]::ReadAllText($Workflow))
Yes 'build.yml has a step that runs Run-Gate.ps1 (#3114)' ($null -ne $gate)
if ($null -eq $gate) { Done }
$g = Get-Named $gate
Yes 'the gate step parses' ($g.Errors -eq 0)
Yes 'it runs Run-Gate.ps1 with a throttle and a budget and fails when that does' ($gate -match "(?m)^\.\\scripts\\dev\\Run-Gate\.ps1 -Throttle [1-9]\d* -BudgetSeconds \d+\s*\r?\nexit \`$LASTEXITCODE\s*$")
Yes ('the step names no harness itself' + $(if ($g.Named.Count) { ' (' + ($g.Named -join ', ') + ')' } else { '' })) ($g.Named.Count -eq 0)

$runGate = Join-Path (Join-Path (Join-Path $Repo 'scripts') 'dev') 'Run-Gate.ps1'
$rg = [IO.File]::ReadAllText($runGate)
$r = Get-Named $rg
Yes 'Run-Gate.ps1 parses' ($r.Errors -eq 0)
Yes 'it takes its list from Gate-Harnesses.ps1' ($rg -match "(?m)^\`$gate = @\(& \(Join-Path \`$Here 'Gate-Harnesses\.ps1'\)\)\s*$")
Yes 'and stops when that fails, before running any' ($rg -match '(?m)^\$gate = @\(.*\r?\nif \(\$LASTEXITCODE -ne 0\) \{ exit 1 \}')
Yes 'its share of the cores is the cores over the build runners' ($rg -match '(?m)^\$share = .*\[Environment\]::ProcessorCount / .*\$builds' -and $rg -match "records\\build-runners\.json")
Yes 'it runs what it chose through Nightly-Harnesses.ps1, the whole gate unless a pull request''s map chose fewer (#3114)' (
    $rg -match '(?m)^\$run = \$gate\s*$' -and $rg -match "(?m)^\s+\`$with = @\{ Only = \(\`$run -join ' '\); Throttle = \`$Throttle; Share = \`$share; BudgetSeconds = \`$BudgetSeconds \}\s*$" -and
    $rg -match "(?m)^\s+& \(Join-Path \`$Here 'Nightly-Harnesses\.ps1'\) @with\s*\r?\n\s+\`$code = \`$LASTEXITCODE\s*$")
Yes '  and fails when that does' ($rg -match '(?m)^exit \$code\s*$')
Yes ('Run-Gate.ps1 names no harness either' + $(if ($r.Named.Count) { ' (' + ($r.Named -join ', ') + ')' } else { '' })) ($r.Named.Count -eq 0)

Done
