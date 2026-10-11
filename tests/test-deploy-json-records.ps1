# test-deploy-json-records.ps1
#
#     pwsh -NoProfile -File .\tests\test-deploy-json-records.ps1
#     powershell -NoProfile -File .\tests\test-deploy-json-records.ps1
#
# The deploy scripts read their JSON records and configs on this machine
# through ConvertFrom-ThornswoodJson (scripts\release\Read-JsonFile.ps1), so
# an empty, cut-off or broken record stops the deploy naming the file, not as
# "Invalid JSON primitive" or a null further on.
#
# Read from the scripts' own syntax trees: text sent to the box (here-strings
# and the strings built for remote commands) is a string to the parser, so
# only the reads that run here are counted. Then each of those statements is
# taken out of the script as written and run against bad files in a scratch
# folder. Offline: nothing connects to anything.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\release\Read-JsonFile.ps1')

$pass = 0; $fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Tree([string]$rel) {
    $tok = $null; $err = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $rel), [ref]$tok, [ref]$err)
    return $ast
}
function Commands($ast, [string]$name) {
    return @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $name }, $true))
}

foreach ($rel in 'scripts\deploy\Deploy-Server.ps1', 'scripts\deploy\Deploy-DevGamemode.ps1', 'scripts\deploy\ServerBuild.ps1',
                 'scripts\deploy\Swap.ps1', 'scripts\vps\Send-Script.ps1', 'scripts\vps\Send-Secret.ps1') {
    $ast = Tree $rel
    $leaf = Split-Path -Leaf $rel
    Yes "$leaf runs no bare ConvertFrom-Json on this machine" ((Commands $ast 'ConvertFrom-Json').Count -eq 0)
}
foreach ($rel in 'scripts\deploy\Deploy-Server.ps1', 'scripts\deploy\Deploy-DevGamemode.ps1') {
    $ast = Tree $rel
    $leaf = Split-Path -Leaf $rel
    $text = [IO.File]::ReadAllText((Join-Path $repo $rel))
    $dot = $text.IndexOf(". (Join-Path `$Here '..\release\Read-JsonFile.ps1')")
    $first = (Commands $ast 'ConvertFrom-ThornswoodJson' | ForEach-Object { $_.Extent.StartOffset } | Measure-Object -Minimum).Minimum
    Yes "$leaf loads Read-JsonFile.ps1 before its first read" ($dot -gt 0 -and $first -gt $dot)
}

# Each read, as the script has it, against bad files.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tw-json [x] & ' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmp
try {
    $bad = [ordered]@{ empty = ''; 'cut off' = '{ "loadOrder": [ "a.esp"'; 'not JSON' = 'loadOrder = a.esp' }
    $reads = @(
        @{ File = 'scripts\deploy\Deploy-Server.ps1';      Var = 'recordPath';        Leaf = 'server-build.json' },
        @{ File = 'scripts\deploy\Deploy-Server.ps1';      Var = 'settingsSrc';       Leaf = 'server-settings.json' },
        @{ File = 'scripts\deploy\Deploy-Server.ps1';      Var = 'buildSettingsPath'; Leaf = 'server-settings.json' },
        @{ File = 'scripts\deploy\Deploy-Server.ps1';      Var = 'stampPath';         Leaf = 'thornswood-build.json' },
        @{ File = 'scripts\deploy\Deploy-DevGamemode.ps1'; Var = 'devRecordPath';     Leaf = 'server-build.json' },
        @{ File = 'scripts\deploy\Deploy-DevGamemode.ps1'; Var = 'settingsSrc';       Leaf = 'server-settings.json' })
    foreach ($r in $reads) {
        $ast = Tree $r.File
        $calls = @(Commands $ast 'ConvertFrom-ThornswoodJson' | Where-Object { $_.Extent.Text.EndsWith(' $' + $r.Var) -and $_.Extent.Text.Contains('-LiteralPath $' + $r.Var + ' ') })
        $leaf = Split-Path -Leaf $r.File
        Yes "$leaf reads `$$($r.Var) through ConvertFrom-ThornswoodJson, naming it" ($calls.Count -ge 1)
        if (-not $calls.Count) { continue }
        $expr = $calls[0].Extent.Text
        foreach ($k in $bad.Keys) {
            $p = Join-Path $tmp $r.Leaf
            [IO.File]::WriteAllText($p, $bad[$k])
            $why = ''
            try { Set-Variable -Name $r.Var -Value $p; $null = & ([scriptblock]::Create($expr)) } catch { $why = $_.Exception.Message }
            Yes "  a record that is $k stops it, naming the file" ($why.StartsWith($p) -and ($why -match 'is empty$|is not valid JSON'))
        }
        [IO.File]::WriteAllText((Join-Path $tmp $r.Leaf), "$([char]0xFEFF){ `"loadOrder`": [ `"a.esp`" ], `"source`": { `"commit`": `"abc`" } }")
        Set-Variable -Name $r.Var -Value (Join-Path $tmp $r.Leaf)
        $ok = & ([scriptblock]::Create($expr))
        Yes '  and a good one, byte order mark and all, still reads' ($ok.source.commit -eq 'abc' -and @($ok.loadOrder)[0] -eq 'a.esp')
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$pass passed, $fail failed"
if ($fail) { exit 1 }
