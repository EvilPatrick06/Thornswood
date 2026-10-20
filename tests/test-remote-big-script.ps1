<#
  test-remote-big-script.ps1

  A 10 KB script is sent whole and runs to its last line, from every helper
  that sends one to the VPS.

  WHY THIS EXISTS. On the VPS a long command line arrives cut short, and the
  far end complains about a brace in a script nobody can see. Base64 of
  UTF-16 is about 2.7 times the script, so it takes only a few KB.
  Deploy-Docs.ps1 hit it on 17 September and Deploy-DevGamemode.ps1 on 20
  September, and sixteen scripts were given a guard that night that sends a
  long script as a file instead. Entry 197 on the To Do List asks for "the
  remote helper survives a 10 KB script".

  test-remote-length.ps1 reads the scripts and measures their blocks. This
  one sends. Each Remote function is lifted out of its script by text and
  called with a 10 KB script, and Remote.ps1, the helper that takes any
  script at all, is run whole with one.

  THE STAND-INS ARE A SMALL SSHD ON THIS MACHINE, NOT THE VPS. scp puts the
  file in a scratch folder that stands for C:/Windows/Temp, and ssh hands the
  command to this machine's cmd.exe with that folder in place of the far one.
  The -File line is then run again under a Windows PowerShell outer shell.
  Windows sshd uses cmd.exe unless it is set to another shell, and Windows
  PowerShell is the usual other one. Which of the two the VPS uses has not
  been measured. So what is proved is the helpers' mechanics: the
  script is copied up once and whole, runs to its last line, what it printed
  comes back, it is tidied away, and the exit code survives the tidy up. What
  the VPS itself does is not proved here.

  What the two shells showed on this machine on 24 September: the path bare
  runs under both. The path in single quotes, which every helper sent until
  then, fails under cmd.exe ("The given path's format is not supported") and
  runs under Windows PowerShell. It also ran on the VPS: Deploy-DevGamemode
  printed its settings step's own line from a file sent that way on 20 and 21
  September. And the 17 September error in Remote.ps1's header, "a
  positional parameter cannot be found that accepts argument 'Voice'", is
  what this machine gives for that line under Windows PowerShell, and not
  under cmd.exe. Both fit a VPS whose sshd hands commands to Windows
  PowerShell, but nobody has read the setting off the box. A helper here
  passes only with a line that runs under both shells until somebody does.

  It runs only what this harness sent, in the exact shapes the helpers send:
  its own two scripts inline, or a file it copied into the scratch folder,
  run or tidied away. Anything else is written down and not run, and fails
  the check that expected it to.

  NEVER CONNECTS. It checks that ssh and scp resolve to the stand-ins before
  anything is sent, and stops if they do not. Every host it names ends in
  .invalid, which no resolver answers, so even a stand-in that failed to take
  would reach nothing.
#>
[CmdletBinding()]
param([string]$RepoPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $RepoPath) { $RepoPath = $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Remove-Item -Path function:global:ssh, function:global:scp, function:global:Invoke-TsFarEnd -ErrorAction SilentlyContinue
    if ($global:TsFar -and $global:TsFar.Disk -and (Test-Path -LiteralPath $global:TsFar.Disk)) {
        Remove-Item -LiteralPath $global:TsFar.Disk -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name TsRemoteCalls, TsFar -Scope Global -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

# What cmd.exe will carry. Where the VPS cuts a line has not been measured;
# the helpers send anything over 6,000 characters as a file.
$Limit = 8191

# What the helpers read to know where to send. None of it resolves.
$ssh = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=1')
$User = 'nobody'
$Vps = 'thornswood-test.invalid'
$VpsUser = $User
$VpsHost = $Vps
$target = "$User@$Vps"

# ---- the scripts --------------------------------------------------------------
#
# The long one ends by exiting 7, so the code a helper hands back can be told
# from the 0 its tidy up returns.
$lines = New-Object System.Collections.Generic.List[string]
$n = 0
while (($lines -join "`r`n").Length -lt 10240) {
    $n++
    $lines.Add(("Write-Output 'line {0:d4} of a script too long for one command line'" -f $n))
}
$lastLine = ("line {0:d4} of a script too long for one command line" -f $n)
$big = ($lines -join "`r`n") + "`r`nexit 7"
$short = "Write-Output 'short and sent inline'"

# ---- the far end ----------------------------------------------------------------
$disk = Join-Path ([IO.Path]::GetTempPath()) ('ts-far-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $disk -Force)
$global:TsFar = @{
    Temp    = 'C:/Windows/Temp/'
    Disk    = $disk
    Target  = $target
    Scripts = @($big, $short)
}
$global:TsRemoteCalls = New-Object System.Collections.ArrayList

# The far paths go bare, so what stands in for C:/Windows/Temp on the line has
# to be as bare as it is: a space or an & in it would fail a line for a reason
# the real path cannot have. The temp folder here may hold either (every temp
# file on the shipping machine went under C:\ThornswoodTemps&Worktrees until
# #2900, and
# cmd.exe ends a command at a bare &, issues #1042 and #1115). So the line
# names the stand-in folder as ./, and the shell runs in it: the folder's own
# path is never on a command line.
$global:TsFar.DiskFwd = './'

function global:Invoke-TsFarEnd([string]$command, [string]$shell) {
    $far = $global:TsFar
    $said = New-Object System.Collections.ArrayList

    # Only what this harness sent, in the exact shapes the helpers send, so
    # nothing can be chained on for either shell to run. A far path may be in
    # single quotes, so that the old form still reaches the shell and fails
    # there in the shell's own words, but it must name a file this harness
    # copied up.
    $ok = $false
    $at = [regex]::Escape($far.Temp) + '[A-Za-z0-9._-]+'
    # -ExecutionPolicy Bypass as well since Rotate-BotToken.ps1 (#902): its
    # inline script dot-sources a writer it copied up, and a file is what an
    # execution policy looks at.
    $m = [regex]::Match($command, '^powershell -NoProfile (-ExecutionPolicy Bypass )?-EncodedCommand ([A-Za-z0-9+/=]+)$')
    if ($m.Success) {
        $text = ''
        try { $text = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[2].Value)) } catch { }
        foreach ($s in $far.Scripts) { if ($text.EndsWith($s)) { $ok = $true } }
    }
    else {
        $m = [regex]::Match($command, '^powershell -NoProfile -ExecutionPolicy Bypass -File (''?)(' + $at + ')\1$')
        if (-not $m.Success) { $m = [regex]::Match($command, '^powershell -NoProfile -Command Remove-Item -LiteralPath (''?)(' + $at + ')\1 -Force$') }
        if ($m.Success) {
            $here = Join-Path $far.Disk ($m.Groups[2].Value.Substring($far.Temp.Length))
            if (Test-Path -LiteralPath $here) {
                $held = [IO.File]::ReadAllText($here)
                foreach ($s in $far.Scripts) { if ($held.Contains($s)) { $ok = $true } }
            }
        }
    }
    if (-not $ok) {
        [void]$said.Add('the stand-in did not run this: ' + $command)
        return [pscustomobject]@{ Out = @($said); Code = 1 }
    }

    # The line as it would arrive, the far folder swapped for ./ and the shell
    # started in the stand-in folder. Under cmd.exe, /d leaves out this machine's AutoRun, which belongs to
    # this machine and not to any server. Under Windows PowerShell the whole
    # line is its command; the shapes above hold no double quote to break the
    # one round it. Either way PSModulePath is dropped so the Windows
    # PowerShell inside builds its own, as a fresh one does, rather than
    # inheriting pwsh's.
    $line = $command.Replace($far.Temp, $far.DiskFwd)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    if ($shell -eq 'powershell') {
        $psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $psi.Arguments = '-NoProfile -NonInteractive -Command "' + $line + '"'
    }
    else {
        $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
        $psi.Arguments = '/d /c ' + $line
    }
    $psi.WorkingDirectory = $far.Disk
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($psi.EnvironmentVariables.ContainsKey('PSModulePath')) { $psi.EnvironmentVariables.Remove('PSModulePath') }
    $p = [System.Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $stdout = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $stderr = $errTask.Result
    foreach ($l in (($stdout + "`n" + $stderr) -split "`r?`n")) {
        if ($l.Trim()) { [void]$said.Add($l) }
    }
    return [pscustomobject]@{ Out = @($said); Code = $p.ExitCode }
}

function global:ssh {
    $all = @($args | ForEach-Object { [string]$_ })
    $at = [Array]::IndexOf($all, $global:TsFar.Target)
    $command = ''
    if ($at -ge 0 -and $at -lt ($all.Count - 1)) { $command = ($all[($at + 1)..($all.Count - 1)] -join ' ') }
    $ran = Invoke-TsFarEnd $command
    [void]$global:TsRemoteCalls.Add([pscustomobject]@{ Tool = 'ssh'; Line = ($all -join ' '); Command = $command; Sent = ''; Out = ($ran.Out -join "`n"); Code = $ran.Code })
    foreach ($l in $ran.Out) { $l }
    $global:LASTEXITCODE = $ran.Code
}
function global:scp {
    # The local file is the argument that exists on disk. Read now, because
    # the helper deletes it as soon as the copy returns. It lands in the
    # stand-in folder only if it was bound for C:/Windows/Temp, by a plain name.
    $all = @($args | ForEach-Object { [string]$_ })
    $src = $null
    $far = ''
    foreach ($s in $all) {
        $isFile = $false
        try { $isFile = [IO.File]::Exists($s) } catch { }
        if ($isFile) { $src = $s; continue }
        $m = [regex]::Match($s, '^[^@\s]+@[^:\s]+:(.+)$')
        if ($m.Success) { $far = $m.Groups[1].Value }
    }
    $sent = ''
    $code = 1
    if ($src) { $sent = [IO.File]::ReadAllText($src) }
    $temp = $global:TsFar.Temp
    if ($src -and $far.StartsWith($temp) -and $far.Substring($temp.Length) -match '^[A-Za-z0-9._-]+$') {
        [IO.File]::Copy($src, (Join-Path $global:TsFar.Disk $far.Substring($temp.Length)), $true)
        $code = 0
    }
    [void]$global:TsRemoteCalls.Add([pscustomobject]@{ Tool = 'scp'; Line = ($all -join ' '); Command = ''; Sent = $sent; Out = ''; Code = $code })
    $global:LASTEXITCODE = $code
}
Yes 'ssh is the stand-in here, so nothing can reach a server' ((Get-Command ssh).CommandType -eq 'Function')
Yes 'and so is scp' ((Get-Command scp).CommandType -eq 'Function')
if ($script:fail) { Done }

function Get-Encoded([string]$line) {
    $m = [regex]::Match($line, 'EncodedCommand\s+(\S+)')
    if (-not $m.Success) { return '' }
    try { return [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[1].Value)) } catch { return '' }
}

function Measure-Send([scriptblock]$send) {
    $global:TsRemoteCalls.Clear()
    Get-ChildItem -LiteralPath $global:TsFar.Disk -File | Remove-Item -Force
    $out = @()
    $stopped = ''
    $global:LASTEXITCODE = 0
    try { $out = @(& $send) } catch { $stopped = $_.Exception.Message }
    $code = $global:LASTEXITCODE
    $calls = @($global:TsRemoteCalls)
    $longest = 0
    foreach ($c in $calls) { if ($c.Line.Length -gt $longest) { $longest = $c.Line.Length } }
    return [pscustomobject]@{
        Ssh     = @($calls | Where-Object { $_.Tool -eq 'ssh' })
        Scp     = @($calls | Where-Object { $_.Tool -eq 'scp' })
        Longest = $longest
        Out     = (@($out | ForEach-Object { [string]$_ }) -join "`n")
        Code    = $code
        Stopped = $stopped
        Left    = @(Get-ChildItem -LiteralPath $global:TsFar.Disk -File).Count
    }
}

# Says what came back when a run failed, because "FAIL runs that file" alone
# sends the next person to guess.
function Show-Why($r) {
    if ($r.Stopped) { Write-Host ('      it stopped: ' + $r.Stopped) }
    foreach ($c in $r.Ssh) {
        if ($c.Code -ne 0 -and $c.Code -ne 7) {
            $first = ($c.Out -split "`n" | Where-Object { $_ -match 'fail|not|error' } | Select-Object -First 1)
            if (-not $first) { $first = ($c.Out -split "`n" | Select-Object -First 1) }
            Write-Host ('      the far end said, exit ' + $c.Code + ': ' + $first)
        }
    }
}

# The -File line a helper sent, run again under a Windows PowerShell outer
# shell, against the file as it was copied up. Its exit code is not compared:
# powershell -Command hands back 1 for any program that failed, so the 7 the
# script exits with cannot come through that way. Sixteen helpers send the
# very same line with the very same file, so that pair is run this way once
# and not again. Measured 24 September on a busy machine: run for every
# helper, it took this from 136 seconds to 213; run once a pair, from 126 to
# 152.
$script:otherShellRan = @{}
function Test-OtherShell($r) {
    $runs = @($r.Ssh | Where-Object { $_.Command -match '-File' })
    if ($runs.Count -ne 1 -or $r.Scp.Count -ne 1) { return $false }
    $key = $runs[0].Command + "`n" + $r.Scp[0].Sent
    if (-not $script:otherShellRan.ContainsKey($key)) {
        $script:otherShellRan[$key] = (Invoke-OtherShell $runs[0].Command $r.Scp[0].Sent)
    }
    return $script:otherShellRan[$key]
}
function Invoke-OtherShell([string]$command, [string]$sent) {
    $m = [regex]::Match($command, [regex]::Escape($global:TsFar.Temp) + '[A-Za-z0-9._-]+')
    if (-not $m.Success) { return $false }
    $here = Join-Path $global:TsFar.Disk ($m.Value.Substring($global:TsFar.Temp.Length))
    $ran = $null
    try {
        [IO.File]::WriteAllText($here, $sent, (New-Object Text.UTF8Encoding($true)))
        $ran = Invoke-TsFarEnd $command 'powershell'
    }
    finally { Remove-Item -LiteralPath $here -Force -ErrorAction SilentlyContinue }
    $out = ($ran.Out -join "`n")
    if ($out.Contains($lastLine)) { return $true }
    $first = ($ran.Out | Where-Object { $_ -match 'fail|not|error' } | Select-Object -First 1)
    if (-not $first) { $first = ($ran.Out | Select-Object -First 1) }
    Write-Host ('      Windows PowerShell said, exit ' + $ran.Code + ': ' + $first)
    return $false
}

function Test-Sends([string]$name, [scriptblock]$sendBig, [scriptblock]$sendShort, [bool]$handsBackCode) {
    $r = Measure-Send $sendBig
    $runs = @($r.Ssh | Where-Object { $_.Command -match '-File' })
    $ran = ($runs.Count -eq 1 -and $runs[0].Code -eq 7 -and $runs[0].Out.Contains($lastLine))
    Yes "$name sends a 10 KB script on no command line longer than cmd.exe's $Limit" ($r.Longest -gt 0 -and $r.Longest -le $Limit)
    Yes '  as a file it copies up once' ($r.Scp.Count -eq 1)
    Yes '  holding the whole script' ($r.Scp.Count -eq 1 -and $r.Scp[0].Sent.Contains($big))
    Yes '  runs that file to its last line when cmd.exe on this machine hands the line on' $ran
    Yes '  and when Windows PowerShell on this machine hands the same line on instead' (Test-OtherShell $r)
    Yes '  and what it printed comes back' ($r.Out.Contains($lastLine))
    Yes '  and removes it afterwards' (@($r.Ssh | Where-Object { $_.Command -match 'Remove-Item' }).Count -eq 1 -and $r.Left -eq 0)
    if ($handsBackCode) {
        Yes "  and hands back the script's own exit code, not the tidy up's" ($r.Code -eq 7)
    }
    if (-not $ran -or $r.Stopped) { Show-Why $r }

    $r = Measure-Send $sendShort
    Yes '  and a short one still goes inline, in one call' ($r.Scp.Count -eq 0 -and $r.Ssh.Count -eq 1)
    Yes '  whole' ($r.Ssh.Count -eq 1 -and (Get-Encoded $r.Ssh[0].Command).Contains($short))
    Yes '  and runs' ($r.Out.Contains('short and sent inline'))
    if (-not $r.Out.Contains('short and sent inline')) { Show-Why $r }
}

# ---- Send-Script.ps1, the helper every script sends through (#1070) -----------
$sendScript = Join-Path $RepoPath 'scripts\vps\Send-Script.ps1'
Yes 'Send-Script.ps1 is there' (Test-Path -LiteralPath $sendScript)
if (Test-Path -LiteralPath $sendScript) {
    . $sendScript
    Test-Sends 'Send-Script.ps1 Invoke-ThornswoodRemote' {
        Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script $big
    } {
        Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script $short
    } $true
}

# ---- Remote.ps1, which takes any script --------------------------------------
$remotePs1 = Join-Path $RepoPath 'scripts\vps\Remote.ps1'
Yes 'Remote.ps1 is there' (Test-Path -LiteralPath $remotePs1)
if (Test-Path -LiteralPath $remotePs1) {
    Test-Sends 'Remote.ps1 -Script' {
        & $remotePs1 -Script $big -VpsHost $VpsHost -VpsUser $VpsUser
    } {
        & $remotePs1 -Script $short -VpsHost $VpsHost -VpsUser $VpsUser
    } $true

    $bigFile = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-big-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    try {
        [IO.File]::WriteAllText($bigFile, $big)
        $r = Measure-Send { & $remotePs1 -File $bigFile -VpsHost $VpsHost -VpsUser $VpsUser }
        Yes "Remote.ps1 -File with a 10 KB script sends no command line longer than cmd.exe's $Limit" ($r.Longest -gt 0 -and $r.Longest -le $Limit)
        Yes '  and copies up the whole script' ($r.Scp.Count -eq 1 -and $r.Scp[0].Sent.Contains($big))
        Yes '  and runs it to its last line' ($r.Out.Contains($lastLine))
        Yes "  and hands back the script's own exit code" ($r.Code -eq 7)
        if (-not $r.Out.Contains($lastLine)) { Show-Why $r }
    }
    finally { Remove-Item -LiteralPath $bigFile -Force -ErrorAction SilentlyContinue }
}

# ---- the Remote function in every script that has one -------------------------
#
# Found by the parser, not by counting braces: two of these quote PowerShell's
# own "Missing closing '}'" in their comments, which is exactly the message
# the guard exists to prevent, and a brace counter stops there.
function Get-FunctionText([string]$path, [string]$name) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    $all = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $all) {
        if ($fn.Name -eq $name) { return $fn.Extent.Text }
    }
    return ''
}

$helpers = 0
foreach ($f in (Get-ChildItem -Path (Join-Path $RepoPath 'scripts') -Filter *.ps1 -File -Recurse | Where-Object { $_.Name -notlike 'test-*' -and $_.FullName -notmatch '[\\/]oneoff[\\/]' } | Sort-Object Name)) {
    $fn = Get-FunctionText $f.FullName 'Remote'
    if (-not $fn) { continue }
    # Since #1070 the copies call Send-Script.ps1, loaded above, which keeps
    # the far side's exit code, so theirs is held to that as well.
    if ($fn -match 'Invoke-ThornswoodRemote') {
        $helpers++
        try { Invoke-Expression $fn } catch { Yes ("the Remote in {0} can be lifted" -f $f.Name) $false; continue }
        Test-Sends $f.Name { Remote $big } { Remote $short } $true
        continue
    }
    if ($fn -notmatch '\$cmd\.Length -(le|gt) \d+') {
        Write-Host ("SKIP  {0}: its Remote has no guard; it sends only its own blocks, which test-remote-length.ps1 measures" -f $f.Name)
        continue
    }
    $helpers++
    try { Invoke-Expression $fn } catch { Yes ("the Remote in {0} can be lifted" -f $f.Name) $false; continue }
    # A guard that refuses instead of sending a file. Rotate-BotToken.ps1
    # (#902) does that on purpose: what it sends carries the bot token, and a
    # script sent as a temp file would put the token on the disk at both
    # ends, so its remote scripts are kept short and a long one is an error.
    # Held to that instead: a 10 KB script stops before anything is sent, and
    # a short one goes inline, whole, and runs.
    if ($fn -match '\$cmd\.Length -gt \d+\)\s*\{\s*throw\b') {
        $r = Measure-Send { Remote $big }
        Yes ("{0} refuses a 10 KB script rather than send it, since its scripts carry the token" -f $f.Name) ($r.Stopped -ne '')
        Yes '  and nothing went to the far end, by ssh or scp' ($r.Ssh.Count -eq 0 -and $r.Scp.Count -eq 0)
        $r = Measure-Send { Remote $short }
        Yes '  and a short one goes inline, in one call' ($r.Scp.Count -eq 0 -and $r.Ssh.Count -eq 1)
        Yes '  whole' ($r.Ssh.Count -eq 1 -and (Get-Encoded $r.Ssh[0].Command).Contains($short))
        Yes '  and runs' ($r.Out.Contains('short and sent inline'))
        if (-not $r.Out.Contains('short and sent inline')) { Show-Why $r }
        continue
    }
    Test-Sends $f.Name { Remote $big } { Remote $short } $false
}
Yes 'the guarded helpers were found and sent to' ($helpers -ge 10)

# Issue #1166: these three used to pass the block on the ssh command line.
# The loop above sends a 10 KB script through every Remote that calls
# Invoke-ThornswoodRemote, which is how they send now. Named here so a
# later edit that drops one of them out of that loop fails this file.
foreach ($rel in 'scripts\deploy\Install-Backup.ps1', 'scripts\vps\Restart-Server.ps1', 'scripts\vps\Restore-Box.ps1') {
    $fn1166 = Get-FunctionText (Join-Path $RepoPath $rel) 'Remote'
    Yes ("{0} calls Invoke-ThornswoodRemote, so a 10 KB script went through it above (#1166)" -f (Split-Path -Leaf $rel)) ($fn1166 -match 'Invoke-ThornswoodRemote -Target')
}

# ---- and the ones that are not a Remote function -------------------------------
#
# Install-Voice.ps1 sends its install inline in the script body, so nothing
# above can call it. So every script is read for the one shape of line that
# fails under cmd.exe here: ssh told to run a -File path in single quotes.
# That shape did run on the VPS on 20 and 21 September, so this is not a
# claim about the VPS. It keeps every helper on the form that runs under
# either shell while which one the VPS uses is not known.
$quoted = @()
foreach ($f in (Get-ChildItem -Path (Join-Path $RepoPath 'scripts') -Filter *.ps1 -File -Recurse | Where-Object { $_.Name -notlike 'test-*' -and $_.FullName -notmatch '[\\/]oneoff[\\/]' } | Sort-Object Name)) {
    $i = 0
    foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
        $i++
        if ($line -match '&\s*ssh\b.*-File\s+''') { $quoted += ('{0}:{1}' -f $f.Name, $i) }
    }
}
$why = ''
if ($quoted.Count) { $why = ': ' + ($quoted -join ', ') }
Yes ('no script has ssh run a -File path in single quotes, the form that fails under cmd.exe here' + $why) ($quoted.Count -eq 0)

Done
