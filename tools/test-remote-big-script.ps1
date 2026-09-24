<#
  test-remote-big-script.ps1

  A 10 KB script reaches the VPS whole and runs there, from every helper that
  sends one.

  WHY THIS EXISTS. sshd on Windows hands the command to cmd.exe, which stops
  at 8,191 characters, and base64 of UTF-16 is about 2.7 times the script. So
  anything past about 3 KB used to arrive cut in half, and the far end
  complained about a brace in a script nobody could see. Deploy-Docs.ps1 hit
  it on 17 September; sixteen scripts were given a guard on 20 September that
  sends a long script as a file instead. Entry 197 on the To Do List asks for
  "the remote helper survives a 10 KB script".

  test-remote-length.ps1 reads the scripts and measures their blocks. This
  one sends. Each Remote function is lifted out of its script by text and
  called with a 10 KB script, and Remote.ps1, the helper that takes any
  script at all, is run whole with one.

  THE STAND-INS ARE A SMALL SSHD, not a recorder. scp puts the file in a
  scratch folder that stands for C:/Windows/Temp on the VPS, and ssh hands
  the command to cmd.exe, the way sshd on the VPS does, with that folder in
  place of the far one. So what is proved is that the line runs, not that it
  reads right. The first version of this harness only read the line, and it
  passed every helper while every helper sent -File '<path>': measured 24
  September, cmd.exe passes the single quotes on to Windows PowerShell as part
  of the path, and -File refuses it. Nothing sent as a file had ever run.

  It runs only what this harness sent: its own two scripts inline, a file it
  copied into the scratch folder, or the tidy up of one. Anything else is
  written down and not run, and fails the check that expected it to.

  NEVER CONNECTS. It checks that ssh and scp resolve to the stand-ins before
  anything is sent, and stops if they do not. Every host it names ends in
  .invalid, which no resolver answers, so even a stand-in that failed to take
  would reach nothing.
#>
[CmdletBinding()]
param([string]$ToolsPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ToolsPath) { $ToolsPath = $Here }

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

# What cmd.exe will carry.
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
    DiskFwd = $disk.Replace('\', '/') + '/'
    Target  = $target
    Scripts = @($big, $short)
}
$global:TsRemoteCalls = New-Object System.Collections.ArrayList

# The far paths go bare, so the stand-in folder has to be as bare as
# C:/Windows/Temp is, or a space in it would fail a line that works up there.
Yes 'the stand-in folder for C:/Windows/Temp has no spaces in its path, as the real one has none' (-not $disk.Contains(' '))
if ($script:fail) { Done }

function global:Invoke-TsFarEnd([string]$command) {
    $far = $global:TsFar
    $said = New-Object System.Collections.ArrayList

    # Only what this harness sent. A shape it knows, no cmd.exe operators to
    # chain anything else on, and every far path named is a file it copied up.
    $ok = $false
    if ($command -notmatch '[&|<>^]') {
        $m = [regex]::Match($command, '^powershell -NoProfile -EncodedCommand (\S+)$')
        if ($m.Success) {
            $text = ''
            try { $text = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[1].Value)) } catch { }
            foreach ($s in $far.Scripts) { if ($text.EndsWith($s)) { $ok = $true } }
        }
        elseif ($command -match '^powershell -NoProfile -(ExecutionPolicy Bypass -File|Command Remove-Item -LiteralPath) ') {
            $named = [regex]::Matches($command, [regex]::Escape($far.Temp) + '[A-Za-z0-9._-]+')
            $ok = ($named.Count -gt 0)
            foreach ($p in $named) {
                $here = Join-Path $far.Disk ($p.Value.Substring($far.Temp.Length))
                if (-not (Test-Path -LiteralPath $here)) { $ok = $false; continue }
                $held = [IO.File]::ReadAllText($here)
                $ours = $false
                foreach ($s in $far.Scripts) { if ($held.Contains($s)) { $ours = $true } }
                if (-not $ours) { $ok = $false }
            }
        }
    }
    if (-not $ok) {
        [void]$said.Add('the stand-in did not run this: ' + $command)
        return [pscustomobject]@{ Out = @($said); Code = 1 }
    }

    # cmd.exe /c with the line as it would arrive, the far folder swapped for
    # the stand-in. /d leaves out this machine's AutoRun, which the VPS does
    # not share. PSModulePath is dropped so Windows PowerShell builds its own,
    # as it does under sshd, rather than inheriting pwsh's.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $psi.Arguments = '/d /c ' + $command.Replace($far.Temp, $far.DiskFwd)
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

function Test-Sends([string]$name, [scriptblock]$sendBig, [scriptblock]$sendShort, [bool]$handsBackCode) {
    $r = Measure-Send $sendBig
    $runs = @($r.Ssh | Where-Object { $_.Command -match '-File' })
    $ran = ($runs.Count -eq 1 -and $runs[0].Code -eq 7 -and $runs[0].Out.Contains($lastLine))
    Yes "$name sends a 10 KB script on no command line longer than $Limit" ($r.Longest -gt 0 -and $r.Longest -le $Limit)
    Yes '  as a file it copies up once' ($r.Scp.Count -eq 1)
    Yes '  holding the whole script' ($r.Scp.Count -eq 1 -and $r.Scp[0].Sent.Contains($big))
    Yes '  runs that file to its last line when cmd.exe hands it to Windows PowerShell, as sshd on the VPS does' $ran
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

# ---- Remote.ps1, which takes any script --------------------------------------
$remotePs1 = Join-Path $ToolsPath 'Remote.ps1'
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
        Yes "Remote.ps1 -File with a 10 KB script sends no command line longer than $Limit" ($r.Longest -gt 0 -and $r.Longest -le $Limit)
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
foreach ($f in (Get-ChildItem -Path $ToolsPath -Filter *.ps1 -File | Where-Object { $_.Name -notlike 'test-*' } | Sort-Object Name)) {
    $fn = Get-FunctionText $f.FullName 'Remote'
    if (-not $fn) { continue }
    if ($fn -notmatch '\$cmd\.Length -(le|gt) \d+') {
        Write-Host ("SKIP  {0}: its Remote has no guard; it sends only its own blocks, which test-remote-length.ps1 measures" -f $f.Name)
        continue
    }
    $helpers++
    try { Invoke-Expression $fn } catch { Yes ("the Remote in {0} can be lifted" -f $f.Name) $false; continue }
    Test-Sends $f.Name { Remote $big } { Remote $short } $false
}
Yes 'the guarded helpers were found and sent to' ($helpers -ge 10)

# ---- and the ones that are not a Remote function -------------------------------
#
# Install-Voice.ps1 sends its install inline in the script body, so nothing
# above can call it. What failed in all of them was one shape of line, so
# every script is read for it: ssh told to run a -File path in single quotes.
$quoted = @()
foreach ($f in (Get-ChildItem -Path $ToolsPath -Filter *.ps1 -File | Where-Object { $_.Name -notlike 'test-*' } | Sort-Object Name)) {
    $i = 0
    foreach ($line in [IO.File]::ReadAllLines($f.FullName)) {
        $i++
        if ($line -match '&\s*ssh\b.*-File\s+''') { $quoted += ('{0}:{1}' -f $f.Name, $i) }
    }
}
$why = ''
if ($quoted.Count) { $why = ': ' + ($quoted -join ', ') }
Yes ('no script has ssh run a -File path in single quotes, which cmd.exe passes on as part of the path' + $why) ($quoted.Count -eq 0)

Done
