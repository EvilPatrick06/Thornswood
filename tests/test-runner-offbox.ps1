<#
  test-runner-offbox.ps1

  Issue #1306. Install-Runner.ps1 -OffBox puts the pull request runner
  (label thornswood-pr) on a machine that is not the VPS. This proves what it
  would do there without doing any of it: every run here is -DryRunTo, which
  writes the scripts down and runs none, with stand-ins for gh, and a gh on
  PATH that only records being called proves GitHub is never asked. The one
  real ACL work is Close-RunnerAccount, lifted out of the script and run on
  scratch folders under TEMP for ANONYMOUS LOGON (*S-1-5-7), the same way
  tests\test-runner-lock.ps1 does. No account, service, Defender setting,
  C:\ folder or runner registration is touched. The firewall guards run
  against stand-ins for the NetSecurity cmdlets, so no real rule is read or
  made; the read guards deny ANONYMOUS LOGON on scratch folders only.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$script = Join-Path $Repo 'scripts\deploy\Install-Runner.ps1'
$ps = (Get-Process -Id $PID).Path

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-runner-offbox-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$oldPath = $env:PATH
try {
    # A gh that only says it was called.
    $fakeBin = Join-Path $work 'bin'; New-Item -ItemType Directory -Path $fakeBin | Out-Null
    $ghCalled = Join-Path $work 'gh-called.txt'
    [IO.File]::WriteAllText((Join-Path $fakeBin 'gh.cmd'), "@echo called>>`"$ghCalled`"`r`n@exit /b 1`r`n")
    $env:PATH = $fakeBin + ';' + $env:PATH

    function Dry([string[]]$more) {
        $f = Join-Path $work ('dry-' + [Guid]::NewGuid().ToString('N') + '.txt')
        $ErrorActionPreference = 'Continue'
        $said = @(& $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script @more -DryRunTo $f -NoPause 2>&1 | ForEach-Object { "$_" })
        $rc = $LASTEXITCODE
        $text = $(if (Test-Path -LiteralPath $f) { [IO.File]::ReadAllText($f) } else { '' })
        return @{ Code = $rc; Said = ($said -join "`n"); Text = $text }
    }

    $comp = $env:COMPUTERNAME.ToLower()
    $r = Dry @('-OffBox')
    Yes "-OffBox dry run ends 0 (got $($r.Code))" ($r.Code -eq 0)
    Yes '  it ran nothing: every step says DRY RUN' ($r.Said -match 'DRY RUN, nothing ran' -and $r.Said -match 'on this machine')
    Yes "  registers thornswood-pr-$comp with the label thornswood-pr" ($r.Text -match ("--name 'thornswood-pr-" + [regex]::Escape($comp) + "' --labels 'thornswood-pr'"))
    Yes '  never the VPS label' ($r.Text -notmatch "--labels 'thornswood-vps")
    Yes '  in C:\Thornswood-RunnerPR, as the account thornswood-pr' ($r.Text -match [regex]::Escape("`$root = 'C:\Thornswood-RunnerPR'") -and $r.Text -match [regex]::Escape("`$acct = 'thornswood-pr'"))
    Yes '  its own folder is still locked before config.cmd writes into it' ($r.Text -match '(?m)^Lock-RunnerRoot \$root \$acct')
    Yes '  the install shuts it out of every C:\Thornswood* folder, hyphen or not' ($r.Text -match [regex]::Escape("-Filter 'Thornswood*'"))
    Yes '  and so does the lock of every runner after' ($r.Text -match [regex]::Escape("`$liveFilter = 'Thornswood*'") -and $r.Text -match [regex]::Escape('Close-RunnerAccount $acct $root ''C:\'' $liveFilter $alsoDeny'))
    Yes '  Defender keeps scanning its folder' ($r.Text -match '(?m)^if \(\$false\) \{\s*$')
    Yes '  the stand-in registration token is in none of the scripts (it goes on standard input)' ($r.Text -notmatch 'DRY-RUN-TOKEN-NOT-REAL')
    Yes '  the install script is marked as taking a secret on standard input' ($r.Text -match 'with a secret on standard input')
    Yes '  GitHub was never asked (the gh on PATH was not called)' (-not (Test-Path -LiteralPath $ghCalled))

    $r = Dry @('-OffBox', '-DefenderSkip', '-AlsoDeny', 'D:\Somewhere Else')
    Yes '-DefenderSkip lets Defender skip it, as on the VPS' ($r.Text -match '(?m)^if \(\$true\) \{\s*$')
    Yes '-AlsoDeny is in the install''s deny list and the lock''s' (($r.Text -match [regex]::Escape("+ @('D:\Somewhere Else')")) -and ($r.Text -match [regex]::Escape("`$alsoDeny = @('D:\Somewhere Else')")))

    $r = Dry @('-OffBox', '-Number', '2')
    Yes '-OffBox -Number 2 numbers its folder, account and name' ($r.Text -match [regex]::Escape("`$root = 'C:\Thornswood-RunnerPR2'") -and $r.Text -match [regex]::Escape("`$acct = 'thornswood-pr2'") -and $r.Text -match ("--name 'thornswood-pr-" + [regex]::Escape($comp) + "-2'"))

    $r = Dry @('-OffBox', '-Label', 'thornswood-vps')
    Yes "-OffBox refuses the VPS label (exit $($r.Code))" ($r.Code -eq 1 -and $r.Said -match 'never takes the VPS label' -and -not $r.Text)

    $r = Dry @('-OffBox', '-Status')
    Yes '-OffBox -Status runs here, not over ssh' ($r.Code -eq 0 -and $r.Text -match 'runner    in C:\\Thornswood-RunnerPR')
    $r = Dry @('-OffBox', '-Remove')
    Yes '-OffBox -Remove takes its denies off every C:\Thornswood* folder' ($r.Code -eq 0 -and $r.Text -match [regex]::Escape("-Filter 'Thornswood*'") -and $r.Text -match "/remove:d 'thornswood-pr'")

    # The VPS, unchanged: what an install on the box would send.
    $r = Dry @()
    Yes "without -OffBox the dry run still ends 0 (got $($r.Code))" ($r.Code -eq 0)
    Yes '  the VPS runner keeps its label, name and folder' ($r.Text -match "--name 'thornswood-vps' --labels 'thornswood-vps'" -and $r.Text -match [regex]::Escape("`$root = 'C:\Thornswood-Runner'"))
    Yes '  and its C:\Thornswood-* filter and Defender skip' ($r.Text -match [regex]::Escape("-Filter 'Thornswood-*'") -and $r.Text -match '(?m)^if \(\$true\) \{\s*$')
    Yes '  GitHub still never asked' (-not (Test-Path -LiteralPath $ghCalled))

    # ---- Close-RunnerAccount on scratch folders, the off-box filter ---------
    $src = [IO.File]::ReadAllText($script)
    $lib = [regex]::Match($src, "(?s)\`$lockLib = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
    Yes 'the lock library is where it was' ($lib -match 'function Close-RunnerAccount')
    . ([scriptblock]::Create($lib))
    $parent = Join-Path $work 'c'
    $names = 'Thornswood-Server', 'ThornswoodTemps&Worktrees', 'Thornswood Vault', 'Thornswood-RunnerPR', 'Other'
    foreach ($n in $names) { New-Item -ItemType Directory -Path (Join-Path $parent $n) | Out-Null }
    $extra = Join-Path $work 'elsewhere'; New-Item -ItemType Directory -Path $extra | Out-Null
    $own = Join-Path $parent 'Thornswood-RunnerPR'
    $said = @(Close-RunnerAccount '*S-1-5-7' $own $parent 'Thornswood*' @($extra, (Join-Path $work 'not-there')))
    function Denied([string]$p) { return [bool]@((Get-Acl -LiteralPath $p).Access | Where-Object { "$($_.AccessControlType)" -eq 'Deny' -and $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-7' }).Count }
    Yes 'off the box it shuts the account out of Thornswood-Server' (Denied (Join-Path $parent 'Thornswood-Server'))
    Yes '  and out of ThornswoodTemps&Worktrees, which has no hyphen' (Denied (Join-Path $parent 'ThornswoodTemps&Worktrees'))
    Yes '  and out of Thornswood Vault' (Denied (Join-Path $parent 'Thornswood Vault'))
    Yes '  and out of an -AlsoDeny folder' (Denied $extra)
    Yes '  but not its own folder' (-not (Denied $own))
    Yes '  and not a folder that is not Thornswood''s' (-not (Denied (Join-Path $parent 'Other')))
    Yes '  an -AlsoDeny folder that is not there is passed over' (-not ($said -join ' ' -match 'not-there'))
    $parent2 = Join-Path $work 'c2'
    foreach ($n in 'Thornswood-Server', 'ThornswoodTemps') { New-Item -ItemType Directory -Path (Join-Path $parent2 $n) | Out-Null }
    $null = Close-RunnerAccount '*S-1-5-7' (Join-Path $parent2 'none') $parent2
    Yes 'the VPS default filter is unchanged: Thornswood-* only' ((Denied (Join-Path $parent2 'Thornswood-Server')) -and -not (Denied (Join-Path $parent2 'ThornswoodTemps')))

    # ---- the guards in the dry run (WHAT A PULL REQUEST JOB MAY REACH) -----
    $r = Dry @('-OffBox')
    $t = $r.Text
    Yes '-OffBox install puts outbound block rules on for the account alone' ($t -match [regex]::Escape('Set-RunnerFirewall $grdAcct $grdGroup $grdBlocks') -and $t -match '-Direction Outbound -Action Block' -and $t -match [regex]::Escape("-LocalUser ('D:(A;;CC;;;'"))
    Yes '  in a group named for the account' ($t -match [regex]::Escape("`$grdGroup = 'Thornswood PR runner thornswood-pr'"))
    Yes '  blocking everything outside GitHub''s published lists (stand-in meta)' ($t -match [regex]::Escape("'0.0.0.0-4.147.255.255'") -and $t -match [regex]::Escape("'4.149.0.0-126.255.255.255'") -and $t -match [regex]::Escape("'128.0.0.0-140.82.111.255'"))
    Yes '  loopback and GitHub''s ranges are not in the block list' ($t -notmatch "'127\.0\.0\.0-" -and $t -notmatch [regex]::Escape("'140.82.112.0") -and $t -notmatch [regex]::Escape("'192.30.252.0"))
    Yes '  IPv6 too: everything but ::1 and GitHub''s 2a0a:a440::/29' ($t -match [regex]::Escape("'::'") -and $t -match [regex]::Escape("'::2-2a0a:a43f:ffff:ffff:ffff:ffff:ffff:ffff'") -and $t -match [regex]::Escape("'2a0a:a448::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff'"))
    Yes '  and shuts it out of other drives, profiles and ProgramData secrets' ($t -match [regex]::Escape('Close-RunnerReads $grdAcct (Get-RunnerReadDenies $grdAcct)'))
    $iG = $t.IndexOf('Set-RunnerFirewall $grdAcct'); $iC = $t.IndexOf('.\config.cmd --unattended')
    Yes '  both before config.cmd can start the runner' ($iG -gt 0 -and $iC -gt $iG)
    Yes '  GitHub''s lists came from a stand-in: gh never called' (-not (Test-Path -LiteralPath $ghCalled))
    $r = Dry @('-OffBox', '-AllowHost', 'pypi.org')
    Yes '-AllowHost lets its address through (stand-in 203.0.113.7)' ($r.Text -match [regex]::Escape("-203.0.113.6'") -and $r.Text -match [regex]::Escape("'203.0.113.8-"))
    $r = Dry @('-OffBox', '-Lock')
    Yes "-OffBox -Lock fetches the lists again and puts the guards back (exit $($r.Code))" ($r.Code -eq 0 -and $r.Text -match [regex]::Escape('Set-RunnerFirewall $grdAcct $grdGroup $grdBlocks') -and $r.Text -match [regex]::Escape('Close-RunnerReads'))
    $r = Dry @('-OffBox', '-Remove')
    Yes '-OffBox -Remove takes the firewall rules and the read denies off' ($r.Text -match [regex]::Escape('Remove-RunnerFirewall $grdGroup') -and $r.Text -match [regex]::Escape('Open-RunnerReads $grdAcct (Get-RunnerReadDenies $grdAcct)'))
    $r = Dry @('-OffBox', '-Status')
    Yes '-OffBox -Status says what the firewall has' ($r.Text -match [regex]::Escape('Get-RunnerFirewall $grdGroup'))
    $r = Dry @('-OffBox', '-Number', '2')
    Yes '-Number 2 gets a firewall group of its own' ($r.Text -match [regex]::Escape("`$grdGroup = 'Thornswood PR runner thornswood-pr2'"))
    foreach ($m in @(@(), @('-Remove'), @('-Lock'), @('-Status'))) {
        $r = Dry $m
        Yes ("the VPS (no -OffBox) $($m -join ' ') gets no firewall rule and no read deny") ($r.Code -eq 0 -and $r.Text -notmatch 'RunnerFirewall|RunnerReads')
    }

    # ---- the range arithmetic ----------------------------------------------
    $rl = [regex]::Match($src, "(?s)\`$rangeLib = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
    Yes 'the range library is where it was' ($rl -match 'function Get-RunnerBlockRanges')
    . ([scriptblock]::Create($rl))
    $b = @(Get-RunnerBlockRanges @('10.0.0.0/8'))
    Yes 'one IPv4 range: the rest of IPv4, and all of IPv6' (($b -join ',') -eq '0.0.0.0-9.255.255.255,11.0.0.0-255.255.255.255,::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
    $b = @(Get-RunnerBlockRanges @('10.0.0.0/8', '10.1.0.0/16', '11.0.0.0/8', '13.0.0.5', '0.0.0.0/32', '::/0'))
    Yes 'overlapping and touching ranges merge; a lone address stays lone' (($b -join ',') -eq '0.0.0.1-9.255.255.255,12.0.0.0-13.0.0.4,13.0.0.6-255.255.255.255')
    $b = @(Get-RunnerBlockRanges @('10.0.0.1/8'))
    Yes 'host bits in a CIDR are ignored' ($b[0] -eq '0.0.0.0-9.255.255.255')
    Yes 'nothing to allow blocks everything' ((@(Get-RunnerBlockRanges @()) -join ',') -eq '0.0.0.0-255.255.255.255,::-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')

    # ---- the guards themselves, on stand-ins and scratch folders -----------
    $gl = [regex]::Match($src, "(?s)\`$guardLib = @'\r?\n(.*?)\r?\n'@").Groups[1].Value
    Yes 'the guard library is where it was' ($gl -match 'function Set-RunnerFirewall')
    $script:fw = New-Object Collections.ArrayList
    $script:gone = New-Object Collections.ArrayList
    # Stand-ins: functions win over the cmdlets, so no real rule is read or made.
    function New-NetFirewallRule { param($DisplayName, $Group, $Direction, $Action, $Profile, $LocalUser, $RemoteAddress, $Description, $ErrorAction) [void]$script:fw.Add(@{ Name = $DisplayName; Group = $Group; Direction = $Direction; Action = $Action; LocalUser = $LocalUser; Remote = @($RemoteAddress) }) }
    function Get-NetFirewallRule { param($Group, $ErrorAction) @($script:fw | Where-Object { $_.Group -eq $Group } | ForEach-Object { New-Object PSObject -Property @{ Name = $_.Name; Enabled = 'True' } }) }
    function Remove-NetFirewallRule { param($Name) [void]$script:gone.Add($Name); $keep = @($script:fw | Where-Object { $_.Name -ne $Name }); $script:fw.Clear(); foreach ($k in $keep) { [void]$script:fw.Add($k) } }
    . ([scriptblock]::Create($gl))
    $many = @(1..1203 | ForEach-Object { '10.0.' + [int][Math]::Floor($_ / 256) + '.' + ($_ % 256) })
    $said = Set-RunnerFirewall '*S-1-5-7' 'TS test group' $many
    Yes 'Set-RunnerFirewall: 1,203 ranges in three rules of 500' ($script:fw.Count -eq 3 -and $script:fw[2].Remote.Count -eq 203 -and $said -match '3 outbound rule')
    Yes '  every rule outbound, block, for that account''s SID only' (@($script:fw | Where-Object { $_.Direction -eq 'Outbound' -and $_.Action -eq 'Block' -and $_.LocalUser -eq 'D:(A;;CC;;;S-1-5-7)' -and $_.Group -eq 'TS test group' }).Count -eq 3)
    $null = Set-RunnerFirewall '*S-1-5-7' 'TS test group' @('1.2.3.4')
    Yes '  run again it replaces its rules, never piles them up' ($script:fw.Count -eq 1 -and $script:gone.Count -eq 3)
    Yes '  status counts them' ((Get-RunnerFirewall 'TS test group') -match '1 outbound block rule')
    $threw = $false; try { $null = Set-RunnerFirewall '*S-1-5-7' 'TS test group' @() } catch { $threw = $true }
    Yes '  an empty list changes nothing and says so' ($threw -and $script:fw.Count -eq 1)
    $null = Remove-RunnerFirewall 'TS test group'
    Yes 'Remove-RunnerFirewall takes the group off' ($script:fw.Count -eq 0 -and (Get-RunnerFirewall 'TS test group') -match 'NO RULES')

    $u = Join-Path $work 'Users'; $pd = Join-Path $work 'ProgramData'; $dv = Join-Path $work 'D-root'
    foreach ($n in 'alice', 'Public', 'Default', 'thornswood-pr', 'thornswood-pr.ONE') { New-Item -ItemType Directory -Path (Join-Path $u $n) | Out-Null }
    foreach ($n in 'ssh', 'Docker', 'chocolatey') { New-Item -ItemType Directory -Path (Join-Path $pd $n) | Out-Null }
    New-Item -ItemType Directory -Path $dv | Out-Null
    $deny = @(Get-RunnerReadDenies 'thornswood-pr' $u $pd @($dv, (Join-Path $work 'no-drive')))
    $want = @($dv, (Join-Path $u 'alice'), (Join-Path $u 'Public'), (Join-Path $pd 'ssh'), (Join-Path $pd 'Docker'))
    Yes 'the read list: other drives, other profiles and Public, ProgramData ssh and Docker' ((@($deny | Sort-Object) -join '|') -eq (@($want | Sort-Object) -join '|'))
    Yes '  not its own profile, not Default, not the rest of ProgramData' (-not ($deny -match 'thornswood-pr|Default|chocolatey'))
    $said = @(Close-RunnerReads '*S-1-5-7' $deny)
    Yes 'Close-RunnerReads denies the account each one' (@($deny | Where-Object { Denied $_ }).Count -eq $deny.Count -and -not ($said -match 'COULD NOT'))
    Yes '  and nothing else' (-not (Denied (Join-Path $u 'thornswood-pr')) -and -not (Denied (Join-Path $pd 'chocolatey')))
    $kid = Join-Path $u 'alice\Documents'; New-Item -ItemType Directory -Path $kid | Out-Null
    Yes '  the deny reaches what is inside' (Denied $kid)
    $null = Open-RunnerReads '*S-1-5-7' $deny
    Yes 'Open-RunnerReads takes every one off again' (@($deny | Where-Object { Denied $_ }).Count -eq 0 -and -not (Denied $kid))
} finally {
    $env:PATH = $oldPath
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0