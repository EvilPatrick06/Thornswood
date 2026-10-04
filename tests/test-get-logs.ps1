<#
  test-get-logs.ps1

      pwsh -NoProfile -File .\tests\test-get-logs.ps1
      powershell -NoProfile -File .\tests\test-get-logs.ps1

  Get-Logs.ps1 structure for issue #453 leftover: rolled generations .1
  through .5 come down with the current file for every log that rolls.
  door.log does not roll, so it stays current-only.

  And the pull itself (#1605). On 4 Oct every pull under PowerShell 7.6.6
  printed a MetadataError for every log, said "1 lines" for each, and wrote a
  rolled generation the box does not have as a file holding the MISSING line:
  the script kept what ssh answered in $lines, which is the [int]$Lines
  parameter, because PowerShell names ignore case. So this runs the real
  script against a stand-in ssh and health check and looks at what it says
  and what it leaves in the folder.

  No ssh and no VPS. Parses the script, checks the fetch list shape, and runs
  the pull against stand-ins.
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

# ---- the pull, against a stand-in ssh (#1605) --------------------------------
# The script keeps what ssh answered under a name of its own. Any assignment
# to $lines, in any case, is the [int]$Lines parameter.
$assigns = @([regex]::Matches($text, '(?im)^(?!\s*\[int\]).*\$lines\s*=(?!=)'))
Yes 'nothing assigns to $Lines, the parameter, under any spelling' ($assigns.Count -eq 0)

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-get-logs-' + [Guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
# The script names the box's folders as C:\...; off Windows there is no C:
# drive for Join-Path to accept, so one is lent for the run.
$lentC = $false
if (-not (Get-PSDrive -Name C -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name C -PSProvider FileSystem -Root $work -Scope Global | Out-Null
    $lentC = $true
}
# What the box has: every current log, and server.log.1 of the rolled ones.
function global:ssh {
    $b64 = ([string]$args[-1] -split ' ')[-1]
    $remote = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($b64))
    $path = [regex]::Match($remote, "Test-Path -LiteralPath '([^']+)'").Groups[1].Value
    $global:LASTEXITCODE = 0
    if ($path -match '\.\d$' -and $path -notmatch 'server\.log\.1$') { return "MISSING: $path" }
    $n = 7
    $t = [regex]::Match($remote, '-Tail (\d+)')
    if ($t.Success) { $n = [int]$t.Groups[1].Value }
    1..$n | ForEach-Object { "line $_ of $path" }
}
function global:Invoke-RestMethod { [pscustomobject]@{ ok = $true; build = 'stand-in'; bind = '127.0.0.1'; auth = 'on' } }
try {
    # What an earlier pull of the broken script left: a rolled generation the
    # box does not have, written down as the MISSING line.
    Set-Content -LiteralPath (Join-Path $work 'thornswood.log.3') -Value 'MISSING: C:\Thornswood-Server-Dev\thornswood.log.3'
    # Run as a person runs it, where an error is printed and the pull goes on,
    # so every error it says is counted rather than the first one stopping this.
    $getLogs = Join-Path $repo 'scripts\vps\Get-Logs.ps1'
    $said = @(& {
        $ErrorActionPreference = 'Continue'
        try { & $getLogs -Vps 203.0.113.9 -User tester -Out $work -Lines 3 -Dev -NoPause *>&1 }
        catch { $_ }
    })
    $errors = @($said | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
    foreach ($e in $errors) { Write-Host ('  said: ' + $e) }
    Yes 'the pull says no error' ($errors.Count -eq 0)
    $words = ($said | ForEach-Object { "$_" }) -join "`n"
    Yes 'it counts the lines ssh answered: server.log, 3 lines' ($words -match '(?m)^\s*server\.log\s+3 lines')
    $server = Join-Path $work 'server.log'
    Yes 'server.log comes down with the 3 lines asked for' ((Test-Path -LiteralPath $server) -and @(Get-Content -LiteralPath $server).Count -eq 3)
    Yes 'a rolled generation the box has comes down: server.log.1' (Test-Path -LiteralPath (Join-Path $work 'server.log.1'))
    Yes 'a rolled generation the box does not have is said as MISSING' ($words -match '(?m)^\s*server\.log\.2\s+MISSING')
    Yes 'and no file is written for it' (-not (Test-Path -LiteralPath (Join-Path $work 'server.log.2')))
    Yes 'a copy an earlier pull left of a generation the box no longer has is removed' (-not (Test-Path -LiteralPath (Join-Path $work 'thornswood.log.3')))
    Yes 'door.log, which does not roll, comes down' (Test-Path -LiteralPath (Join-Path $work 'door.log'))
    $leftMissing = @(Get-ChildItem -LiteralPath $work -File | Where-Object { (Get-Content -LiteralPath $_.FullName -TotalCount 1) -like 'MISSING:*' })
    Yes 'nothing in the folder is a MISSING line written down as a log' ($leftMissing.Count -eq 0)
} finally {
    Remove-Item -Path function:global:ssh -ErrorAction SilentlyContinue
    Remove-Item -Path function:global:Invoke-RestMethod -ErrorAction SilentlyContinue
    if ($lentC) { Remove-PSDrive -Name C -Scope Global -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
