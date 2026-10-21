<#
  test-setup-domain-taskonly.ps1

      pwsh -NoProfile -File .\tests\test-setup-domain-taskonly.ps1

  Setup-Domain.ps1 -TaskOnly reaches the box and sends only the Caddy task.

  WHY. -TaskOnly (#1968) skips the one time setup, and the shared Remote and
  the box's address and account were loaded inside that setup, so on 5 Oct
  the first run of it stopped at "Invoke-ThornswoodRemote is not recognized"
  with nothing sent, and the site's server kept its old priority.

  HOW. Runs the script with -TaskOnly against a made-up box (-Vps 192.0.2.1,
  a documentation address, and -User tester), with ssh and scp replaced by
  functions that record what they are asked and answer as the box would.
  Nothing leaves this machine. -SetupDomain runs another copy, so the same
  test runs on the one from before this change:

      git show origin/main:scripts/deploy/Setup-Domain.ps1 > $env:TEMP\domain-before.ps1
      pwsh -NoProfile -File .\tests\test-setup-domain-taskonly.ps1 -SetupDomain $env:TEMP\domain-before.ps1

  A copy outside scripts\deploy needs its neighbours, so the copy is put in a
  scratch scripts\deploy beside a copy of scripts\vps.
#>
[CmdletBinding()]
param([string]$SetupDomain)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Repo = Split-Path -Parent $Here
if (-not $SetupDomain) { $SetupDomain = [IO.Path]::Combine($Repo, 'scripts', 'deploy', 'Setup-Domain.ps1') }

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

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-domain-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$global:TsDomainCalls = New-Object System.Collections.ArrayList
try {
    $deploy = Join-Path $scratch 'scripts\deploy'
    New-Item -ItemType Directory -Force -Path $deploy | Out-Null
    Copy-Item -LiteralPath ([IO.Path]::Combine($Repo, 'scripts', 'vps')) -Destination (Join-Path $scratch 'scripts\vps') -Recurse
    Copy-Item -LiteralPath $SetupDomain -Destination (Join-Path $deploy 'Setup-Domain.ps1')
    Copy-Item -LiteralPath ([IO.Path]::Combine($Repo, 'scripts', 'deploy', 'Caddyfile')) -Destination (Join-Path $deploy 'Caddyfile')
    # Setup-Domain.ps1 dot-sources the service account functions (#2578).
    Copy-Item -LiteralPath ([IO.Path]::Combine($Repo, 'scripts', 'deploy', 'ServiceAccount.ps1')) -Destination (Join-Path $deploy 'ServiceAccount.ps1')

    # The box, as far as the script can tell: ssh runs what it is given and
    # says it went well, scp takes the file. A long script comes on standard
    # input under a short reader (Send-Script.ps1, #3027), and is read here.
    function global:ssh {
        $in = @($input | ForEach-Object { [string]$_ })
        $text = ($args | ForEach-Object { "$_" }) -join ' '
        $sent = ''
        if ($in.Count) { try { $sent = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($in[0])) } catch { } }
        [void]$global:TsDomainCalls.Add([pscustomobject]@{ Tool = 'ssh'; Text = $text; Sent = $sent })
        $global:LASTEXITCODE = 0
        'caddy up, pid 1'
    }
    function global:scp {
        $sent = ''
        foreach ($a in $args) { if (Test-Path -LiteralPath "$a" -PathType Leaf -ErrorAction SilentlyContinue) { $sent = [IO.File]::ReadAllText("$a") } }
        [void]$global:TsDomainCalls.Add([pscustomobject]@{ Tool = 'scp'; Text = (($args | ForEach-Object { "$_" }) -join ' '); Sent = $sent })
        $global:LASTEXITCODE = 0
    }

    $out = @()
    $err = $null
    try {
        $out = @(& (Join-Path $deploy 'Setup-Domain.ps1') -TaskOnly -Vps '192.0.2.1' -User 'tester' 6>&1 2>&1 | ForEach-Object { "$_" })
    } catch { $err = $_.Exception.Message }
    $out | ForEach-Object { Write-Host ('      ' + $_) }
    if ($err) { Write-Host ('      threw: ' + $err) }

    Yes '-TaskOnly runs to the end' (-not $err)
    $calls = @($global:TsDomainCalls)
    Yes ('  it talks to the box it was given, tester@192.0.2.1 (' + $calls.Count + ' call(s))') (
        $calls.Count -gt 0 -and @($calls | Where-Object { $_.Text -match 'tester@192\.0\.2\.1' }).Count -eq $calls.Count)
    $all = (@($calls | ForEach-Object { $_.Text; $_.Sent }) -join "`n")
    Yes '  what it sends registers the Caddy task' ($all -match "Thornswood Web" -and $all -match 'New-ScheduledTaskSettingsSet')
    Yes '  and sends no Caddyfile and opens no port, the one time setup it skips' ($all -notmatch 'New-NetFirewallRule' -and $all -notmatch 'caddy_[0-9.]+_windows')
}
finally {
    Remove-Item function:\global:ssh -ErrorAction SilentlyContinue
    Remove-Item function:\global:scp -ErrorAction SilentlyContinue
    Remove-Variable -Name TsDomainCalls -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# A full run compares where the name points with the box's address, so the
# address is read from vps.json before that check. On 19 Oct it was read after,
# and a full run without -Vps stopped on "resolves to <the box> and not .".
$text = [IO.File]::ReadAllText($SetupDomain)
$loads = $text.IndexOf('if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }')
$dns = $text.IndexOf('Write-Host "Checking where $Domain points..."')
Yes 'the box''s address is read from vps.json before the DNS check that compares with it' ($loads -ge 0 -and $dns -ge 0 -and $loads -lt $dns)
Done
