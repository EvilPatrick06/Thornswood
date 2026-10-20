<#
  test-prove-secret.ps1

  scripts\vps\Prove-SecretOffCommandLines.ps1 says NOT FOUND for a run that
  sends a secret the Send-Secret way, FOUND for one that sends it the old way,
  and never prints the value or a command line (issue #1212).

      pwsh -NoProfile -File .\tests\test-prove-secret.ps1

  HOW. The same stand-in for the VPS as tests\test-secret-channel.ps1: ssh is
  a fake that runs the command line through cmd.exe on this machine with the
  same standard input, which is what sshd on the VPS does. The watcher is
  started through a fake ssh.cmd (the script starts ssh as a process, so a
  PowerShell function cannot stand in for it); the runs being proved use a
  fake ssh function, as Send-Secret's callers would reach the real one. So the
  watcher reads this machine's real process list while the real Windows
  PowerShell 5.1 runs what would run on the VPS.

  The value is made here at run time from a fresh GUID, with quotes, a dollar,
  a backtick, an ampersand and an accent in it. Nothing prints it.

  Never connects to anything.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here

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

$prove = Join-Path $repo 'scripts\vps\Prove-SecretOffCommandLines.ps1'
$helper = Join-Path $repo 'scripts\vps\Send-Secret.ps1'
Yes 'scripts\vps\Prove-SecretOffCommandLines.ps1 is there' (Test-Path -LiteralPath $prove)
foreach ($f in @($prove, $helper)) {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$errs)
    Yes ((Split-Path -Leaf $f) + ' parses') (@($errs).Count -eq 0)
}
. $helper

if (-not (Get-Command powershell.exe -ErrorAction SilentlyContinue) -or -not (Get-Command cmd.exe -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP  the rest needs Windows PowerShell 5.1 and cmd.exe, as on the VPS'
    Done
}

# ---- the fakes -----------------------------------------------------------
$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-prove-secret-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$calls = Join-Path $work 'watcher-calls.txt'

# The watcher's ssh: keeps its whole command line, then runs the last
# argument (the remote command) with this process's standard input.
$fakeSsh = Join-Path $work 'ssh.cmd'
$cmd = @(
    '@echo off',
    ('echo %*>>"' + $calls + '"'),
    ':next',
    'if "%~2"=="" goto run',
    'shift',
    'goto next',
    ':run',
    '%~1'
) -join "`r`n"
[IO.File]::WriteAllText($fakeSsh, $cmd + "`r`n", (New-Object Text.ASCIIEncoding))
# An ssh that cannot reach the box.
$deadSsh = Join-Path $work 'dead.cmd'
[IO.File]::WriteAllText($deadSsh, "@echo off`r`nexit /b 255`r`n", (New-Object Text.ASCIIEncoding))

# The runs' ssh, as in test-secret-channel.ps1: the command line through
# cmd.exe with the same standard input. Global, because each run is a closure
# (GetNewClosure, so it carries this file's values in with it) and a closure
# finds commands from the global scope.
function global:ssh {
    $a = @($args | ForEach-Object { [string]$_ })
    $in = @($input)
    if ($in.Count) { $in | & cmd.exe /d /c $a[-1] }
    else { & cmd.exe /d /c $a[-1] }
}

$tick = [string][char]0x60
$secret = 'tw-' + [Guid]::NewGuid().ToString('N') + ' q''s "d" $x ' + $tick + 'y & | ^ % < > ' + [string][char]0x00E9
$wire = ConvertTo-ThornswoodSecretWire $secret
$wide = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($secret))
$secure = ConvertTo-SecureString $secret -AsPlainText -Force

function Leaks([string]$text) { return $text.Contains($secret) -or $text.Contains($wire) -or $text.Contains($wide) }

# Proves one run; hands back what it printed and its exit code.
function Prove([scriptblock]$run, [string[]]$sshCommand = @($fakeSsh), $value = $secure) {
    $global:LASTEXITCODE = 99
    $out = @(& $prove -Run $run -Secret $value -VpsHost 'box.invalid' -VpsUser 'tester' -MaxSeconds 120 -SshCommand $sshCommand *>&1 | ForEach-Object { "$_" })
    return [pscustomobject]@{ Out = ($out -join "`n"); Code = $LASTEXITCODE }
}

try {
    # ---- 1. the Send-Secret way: the value on standard input
    $r = Prove {
        . $helper
        $global:ranOut = Invoke-ThornswoodSecretRemote -Target 'tester@box.invalid' -SshArgs @('-o', 'BatchMode=yes') -Secret $secret -Script @'
Start-Sleep -Seconds 2
'GOT ' + ([string]$ThornswoodSecret).Length
'@
    }.GetNewClosure()
    Yes 'Send-Secret way: the run ran and its far side got a value' (@($global:ranOut | Where-Object { "$_" -like 'GOT *' -and "$_" -ne 'GOT 0' }).Count -eq 1)
    Yes 'Send-Secret way: says NOT FOUND' ($r.Out -match '(?m)^NOT FOUND ')
    Yes 'Send-Secret way: exit code 0' ($r.Code -eq 0)
    Yes 'Send-Secret way: it read some command lines' ($r.Out -match '\((\d+) process command lines read\)' -and [int]$Matches[1] -gt 0)
    Yes 'Send-Secret way: prints neither the value nor its base64' (-not (Leaks $r.Out))
    Yes 'Send-Secret way: prints no command line' ($r.Out -notmatch 'EncodedCommand|powershell -|cmd\.exe')

    # ---- 2. control, the old way: the value base64'd into the command line.
    # It must say FOUND, or the watcher is known to see nothing.
    $r = Prove {
        $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$s = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$wire'))`r`nStart-Sleep -Seconds 2"))
        $global:oldOut = @(& ssh 'tester@box.invalid' "powershell -NoProfile -EncodedCommand $e")
    }.GetNewClosure()
    Yes 'control, the old way: says FOUND' ($r.Out -match '(?m)^FOUND\s+\d+ processes')
    Yes 'control, the old way: exit code 1' ($r.Code -eq 1)
    Yes 'control, the old way: still prints neither the value nor its base64' (-not (Leaks $r.Out))
    Yes 'control, the old way: still prints no command line' ($r.Out -notmatch 'EncodedCommand|powershell -|cmd\.exe')

    # ---- 3. the watcher's own command line holds the watcher and nothing else
    $sent = [IO.File]::ReadAllText($calls)
    $decoded = New-Object Text.StringBuilder
    foreach ($m in [regex]::Matches($sent, '-EncodedCommand ([A-Za-z0-9+/=]+)')) {
        [void]$decoded.AppendLine([Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[1].Value)))
    }
    Yes 'the watcher went up twice, with host key checking on' (([regex]::Matches($sent, 'StrictHostKeyChecking=yes tester@box\.invalid')).Count -eq 2)
    Yes 'the watcher''s command line holds neither the value nor its base64, decoded or not' (-not (Leaks $sent) -and -not (Leaks $decoded.ToString()) -and $decoded.ToString().Contains('WATCHER READY'))

    # ---- 4. no value, nothing started
    $before = [IO.File]::ReadAllText($calls)
    $refused = $null
    try { Prove { throw 'must not run' } -value (New-Object Security.SecureString) | Out-Null } catch { $refused = $_ }
    Yes 'an empty value is refused before anything starts' ($null -ne $refused -and [IO.File]::ReadAllText($calls) -eq $before)

    # ---- 4b. a watcher that reads no command lines proves nothing (#1263):
    # NOT FOUND over none is not a NOT FOUND.
    $blind = Join-Path $work 'blind.cmd'
    [IO.File]::WriteAllText($blind, "@echo off`r`necho WATCHER READY`r`nmore >nul`r`necho WATCHER NOT FOUND`r`necho WATCHER READ 0`r`n", (New-Object Text.ASCIIEncoding))
    $r = Prove { 'ran' } -sshCommand @($blind)
    Yes 'a watcher that read nothing: no NOT FOUND, exit code 2' ($r.Out -notmatch '(?m)^NOT FOUND' -and $r.Out -match 'read no command lines' -and $r.Code -eq 2)

    # ---- 5. a watcher that never starts: the run is not run, exit code 2
    $global:wasRun = $false
    $r = Prove { $global:wasRun = $true } -sshCommand @($deadSsh)
    Yes 'no watcher: the run is not run' (-not $global:wasRun)
    Yes 'no watcher: says nothing is proved, exit code 2' ($r.Out -match 'did not start' -and $r.Code -eq 2)

    # ---- 6. the watcher ends with standard input still open (#451, 20 Oct).
    # The fake ssh above passes the end of standard input on; the VPS's did
    # not, and the watcher never answered. Here it runs straight in Windows
    # PowerShell 5.1 with its standard input left open: a stop line must end
    # it, and so must its time limit with no line at all.
    $ast = [Management.Automation.Language.Parser]::ParseFile($prove, [ref]$null, [ref]$null)
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ThornswoodSecretWatcher' }, $true)
    . ([scriptblock]::Create($fn.Extent.Text))
    function Watch-Open([int]$seconds, [bool]$stopLine) {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes((Get-ThornswoodSecretWatcher $seconds)))
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.CreateNoWindow = $true
        $p = [Diagnostics.Process]::Start($psi)
        $o = $p.StandardOutput.ReadToEndAsync()
        $p.StandardInput.WriteLine($wire)
        $p.StandardInput.Flush()
        if ($stopLine) { Start-Sleep -Seconds 2; $p.StandardInput.WriteLine('STOP'); $p.StandardInput.Flush() }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $ended = $p.WaitForExit(($seconds + 20) * 1000)
        if (-not $ended) { $p.Kill(); [void]$p.WaitForExit(5000) }
        return [pscustomobject]@{ Ended = $ended; Seconds = $sw.Elapsed.TotalSeconds; Out = $o.Result }
    }
    $w = Watch-Open 120 $true
    Yes 'standard input open: a stop line ends the watcher well before its limit' ($w.Ended -and $w.Seconds -lt 30)
    Yes 'standard input open: after a stop line it answers NOT FOUND over some command lines' ($w.Out -match 'WATCHER NOT FOUND' -and $w.Out -match 'WATCHER READ [1-9]')
    # And this side sends that line: a watcher that reads two lines, the value
    # and the next, and keeps the second.
    $lineFile = Join-Path $work 'second-line.txt'
    $liner = Join-Path $work 'liner.cmd'
    [IO.File]::WriteAllText($liner, ("@echo off`r`nset /p first=`r`necho WATCHER READY`r`nset /p second=`r`n>`"" + $lineFile + "`" echo [%second%]`r`necho WATCHER NOT FOUND`r`necho WATCHER READ 1`r`n"), (New-Object Text.ASCIIEncoding))
    $r = Prove { 'ran' } -sshCommand @($liner)
    Yes 'this side sends the watcher a stop line when the run is over' ((Test-Path -LiteralPath $lineFile) -and ([IO.File]::ReadAllText($lineFile).Trim() -eq '[STOP]') -and $r.Code -eq 0)
    $w = Watch-Open 3 $false
    Yes 'standard input open, no stop line: the time limit ends the watcher' $w.Ended
    Yes 'standard input open, no stop line: it still answers' ($w.Out -match 'WATCHER NOT FOUND' -and $w.Out -match 'WATCHER READ [1-9]')
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Done
