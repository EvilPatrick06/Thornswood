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
  C:\ folder or runner registration is touched.
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
} finally {
    $env:PATH = $oldPath
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0