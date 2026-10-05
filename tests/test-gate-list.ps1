<#
  test-gate-list.ps1

  Every harness named in the build's gate list is in the list, and is a file
  in tests\.

  WHY THIS EXISTS. Issue #1589. The gate step in .github\workflows\build.yml
  builds its list with one PowerShell assignment spread over many lines:

      $six = 'test-a.js', 'test-b.js',
             'test-c.js'
             'test-d.js'

  A line with no comma after it ends the assignment there, and the next name
  becomes a statement of its own that only prints itself. That is how
  test-page-changed.js sat under the list, read as part of it, and was never
  run by Launcher builds, with nothing saying so.

  So this lifts the gate step's script out of build.yml, parses it with the
  PowerShell parser (the same one the runner uses), and fails on any harness
  name written in that script that is not an element of the $six assignment,
  and on any element that is not a file in tests\. The same reader is then
  driven over a planted script with the missing comma, so a reader that finds
  nothing wrong anywhere cannot pass by accident.

  Read only.
#>
[CmdletBinding()]
param([string]$Workflow)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $Workflow) { $Workflow = Join-Path (Join-Path (Join-Path $Repo '.github') 'workflows') 'build.yml' }

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

# The script of the step that assigns $six, as the runner gets it: the lines
# under its "run: |", with the block's indentation taken off. A YAML block
# scalar ends at the first line indented less than its first line.
function Get-GateScript([string]$yaml) {
    $lines = $yaml -split "`r?`n"
    $at = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*\$six\s*=') { $at = $i; break } }
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

# What the parser makes of that script: the elements of the $six assignment,
# every harness name written anywhere in the script, and any parse error.
function Read-Gate([string]$script) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$tokens, [ref]$errors)
    $assign = $ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $n.Left.VariablePath.UserPath -eq 'six'
    }, $true)
    $inList = @()
    if ($assign) {
        $inList = @($assign.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
    }
    $named = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -match '^test-[\w.-]+\.(js|ps1)$'
    }, $true) | ForEach-Object { $_.Value })
    [pscustomobject]@{ Assigned = [bool]$assign; InList = $inList; Named = $named; Errors = @($errors) }
}

# --- the planted script: the shape #1589 found, and the same with its comma
$planted = @'
$six = 'test-a.js', 'test-b.js',
       'test-c.js'
       'test-d.js'
foreach ($n in $six) { & node $n }
'@
$p = Read-Gate $planted
$outside = @($p.Named | Where-Object { $p.InList -notcontains $_ })
Yes 'planted: a name after a line with no comma is read as outside the list' (($outside.Count -eq 1) -and ($outside[0] -eq 'test-d.js'))
$p2 = Read-Gate ($planted -replace "'test-c.js'", "'test-c.js',")
Yes 'planted: with the comma back, every name is in the list' (@($p2.Named | Where-Object { $p2.InList -notcontains $_ }).Count -eq 0 -and $p2.InList.Count -eq 4)

# --- the real build.yml
if (-not (Test-Path -LiteralPath $Workflow)) { Yes "build.yml is at $Workflow" $false; Done }
$text = [IO.File]::ReadAllText($Workflow)
$gate = Get-GateScript $text
Yes 'build.yml has a step that assigns $six' ($null -ne $gate)
if ($null -eq $gate) { Done }
$g = Read-Gate $gate
Yes 'the gate step parses' ($g.Errors.Count -eq 0)
Yes 'the parser finds the $six assignment' $g.Assigned
Yes ('the list has harnesses in it ({0})' -f $g.InList.Count) ($g.InList.Count -gt 10)
$stray = @($g.Named | Where-Object { $g.InList -notcontains $_ } | Select-Object -Unique)
Yes ('every harness named in the gate step is in the list' + $(if ($stray.Count) { ' (outside: ' + ($stray -join ', ') + ')' } else { '' })) ($stray.Count -eq 0)
$missing = @($g.InList | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Here $_)) })
Yes ('every harness in the list is a file in tests' + $(if ($missing.Count) { ' (missing: ' + ($missing -join ', ') + ')' } else { '' })) ($missing.Count -eq 0)
$twice = @($g.InList | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Yes ('no harness is in the list twice' + $(if ($twice.Count) { ' (' + ($twice -join ', ') + ')' } else { '' })) ($twice.Count -eq 0)
Yes 'test-page-changed.js is in the list (#1589)' ($g.InList -contains 'test-page-changed.js')
Yes 'this harness is in the list' ($g.InList -contains 'test-gate-list.ps1')

Done
