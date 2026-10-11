<#
  test-setup-robocopy.ps1

      powershell -NoProfile -File .\tests\test-setup-robocopy.ps1

  installer\Setup-Thornswood.ps1 sends every robocopy through one checked
  helper, Invoke-CheckedRobocopy (#2201): robocopy codes 0 to 7 carry on and
  come back, 8 and above stop the setup with the source, the destination and
  the code in the message. A stand-in robocopy answers each code, so nothing
  is copied.

  HOW. The helper and Copy-Quietly are lifted out of the real script with the
  PowerShell parser, so this tests the shipped code, not a copy of it. Die is a
  stand-in that throws instead of exiting.
#>
[CmdletBinding()]
param([string]$SetupPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $SetupPath) { $SetupPath = Join-Path (Split-Path -Parent $Here) 'installer\Setup-Thornswood.ps1' }

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}

$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($SetupPath, [ref]$tokens, [ref]$errors)
Yes 'Setup-Thornswood.ps1 parses' ($errors.Count -eq 0)
$fns = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if (-not $fns.ContainsKey($f.Name)) { $fns[$f.Name] = $f }
}
foreach ($n in 'Invoke-CheckedRobocopy', 'Copy-Quietly') { Yes "the script defines $n" ($fns.ContainsKey($n)) }
if ($script:fail) { Write-Host "$($script:pass) passed, $($script:fail) failed"; exit 1 }

# Every call of robocopy in the script sits inside the helper.
$calls = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -match '^robocopy(\.exe)?$' }, $true))
$helper = $fns['Invoke-CheckedRobocopy'].Extent
$outside = @($calls | Where-Object { $_.Extent.StartOffset -lt $helper.StartOffset -or $_.Extent.EndOffset -gt $helper.EndOffset })
Yes ('every robocopy call is inside Invoke-CheckedRobocopy (' + $calls.Count + ' call(s), ' + $outside.Count + ' outside)') ($calls.Count -ge 1 -and $outside.Count -eq 0)
$users = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-CheckedRobocopy' }, $true))
Yes ('the setup copies through the helper in each place it used robocopy (' + $users.Count + ')') ($users.Count -ge 4)
Yes 'no "-ge 8" check is left beside a copy: the helper is the one place' (@([regex]::Matches([IO.File]::ReadAllText($SetupPath), '\$code -ge 8')).Count -eq 1)

# Stand-ins: robocopy answers the code asked for; Die throws.
$script:code = 0
$script:seen = @()
function robocopy { $script:seen += , @($args); $global:LASTEXITCODE = $script:code; 'stand-in robocopy output' }
function Die($m) { throw ('DIE: ' + $m) }
$NonInteractive = $true
foreach ($n in 'Invoke-CheckedRobocopy', 'Copy-Quietly') { . ([scriptblock]::Create($fns[$n].Extent.Text)) }

$from = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim [SSD]\Data'
$to = 'D:\Thornswood\Game\Data'
foreach ($c in 0, 1, 7) {
    $script:code = $c; $script:seen = @()
    $r = $null; $threw = ''
    try { $r = Invoke-CheckedRobocopy $from $to @('/E', '/R:1') } catch { $threw = $_.Exception.Message }
    Yes "robocopy code ${c}: carries on and hands the code back" (-not $threw -and $r -eq $c)
}
$script:seen = @(); $script:code = 0
$null = Invoke-CheckedRobocopy $from $to @('Skyrim - *.bsa', '/MT:8')
Yes 'the folders and flags reach robocopy as given, a space and [ ] intact' ($script:seen.Count -eq 1 -and $script:seen[0][0] -eq $from -and $script:seen[0][1] -eq $to -and $script:seen[0][2] -eq 'Skyrim - *.bsa' -and $script:seen[0][3] -eq '/MT:8')
foreach ($c in 8, 9, 16) {
    $script:code = $c
    $threw = ''
    try { $null = Invoke-CheckedRobocopy $from $to @('/E') } catch { $threw = $_.Exception.Message }
    Yes "robocopy code ${c}: stops" ($threw -like 'DIE: *')
    Yes '  naming the source, the destination and the code' ($threw.Contains($from) -and $threw.Contains($to) -and $threw.Contains("code $c"))
}
# Copy-Quietly, the mods install, goes through it too.
$script:code = 3
$r = Copy-Quietly $from $to 'installing the mods' 6>$null
Yes 'Copy-Quietly with robocopy code 3 carries on and returns 3' ($r -eq 3)
$script:code = 8; $threw = ''
try { $null = Copy-Quietly $from $to 'installing the mods' -Move 6>$null } catch { $threw = $_.Exception.Message }
Yes 'Copy-Quietly with robocopy code 8 stops, naming both folders' ($threw -like 'DIE: *' -and $threw.Contains($from) -and $threw.Contains($to))

Write-Host ''
Write-Host "$($script:pass) passed, $($script:fail) failed"
if ($script:fail -gt 0) { exit 1 }
exit 0