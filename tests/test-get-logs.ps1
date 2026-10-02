<#
  test-get-logs.ps1

      pwsh -NoProfile -File .\tests\test-get-logs.ps1
      powershell -NoProfile -File .\tests\test-get-logs.ps1

  Get-Logs.ps1 structure for issue #453 leftover: rolled generations .1
  through .5 come down with the current file for every log that rolls.
  door.log does not roll, so it stays current-only.

  No ssh and no VPS. Parses the script and checks the fetch list shape.
#>
[CmdletBinding()]
param([string]$RepoPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
if ($RepoPath) { $repo = $RepoPath }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$getLogs = Join-Path $repo 'scripts\vps\Get-Logs.ps1'
Yes 'Get-Logs.ps1 is in scripts\vps' (Test-Path -LiteralPath $getLogs)

$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($getLogs, [ref]$null, [ref]$errs)
Yes 'Get-Logs.ps1 parses' (@($errs).Count -eq 0)
if (@($errs).Count -gt 0) {
    foreach ($e in $errs) { Write-Host ("  parse: {0}" -f $e) }
}

$text = [IO.File]::ReadAllText($getLogs)
Yes 'header says rolled .1 through .5 come down' ($text -match 'rolled generations \.1 through \.5')
Yes 'header says door.log does not roll' ($text -match 'door\.log does not roll')

foreach ($name in @('server.log', 'thornswood.log', 'voice.log', 'site.log', 'bot.log')) {
    $pat = "Name = '$name'[^`r`n]*Keep = 5"
    Yes ("$name sets Keep = 5") ($text -match $pat)
}

$doorLine = [regex]::Match($text, "Name = 'door\.log'[^`r`n]*")
Yes 'door.log is listed' $doorLine.Success
Yes 'door.log has no Keep' ($doorLine.Success -and $doorLine.Value -notmatch 'Keep')

Yes 'builds a fetch list from Keep' ($text -match '\$fetch = New-Object System\.Collections\.Generic\.List')
Yes 'adds Name.i for each Keep generation' (
    $text.Contains("Name = (`$base.Name + '.' + `$i)") -and
    $text.Contains("Path = (`$base.Path + '.' + `$i)"))
Yes 'rolled misses are Optional' ($text.Contains('Optional = $true'))
Yes 'missing rolled prints DarkGray MISSING' (
    $text.Contains('MISSING') -and $text.Contains('DarkGray') -and
    $text.Contains('if ($l.Optional -and $missing)'))
Yes 'optional missing continues without writing that file' (
    $text -match '(?s)if \(\$l\.Optional -and \$missing\).*?continue')

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
