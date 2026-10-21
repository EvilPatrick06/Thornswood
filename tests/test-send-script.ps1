<#
  test-send-script.ps1

  Send-Script.ps1, the one helper every script here runs PowerShell on the VPS
  with (issue #1070), against a fake ssh and scp.

      pwsh -NoProfile -File .\tests\test-send-script.ps1

  WHY THIS EXISTS. Seventeen scripts carried their own copy of Remote(), and
  four more a copy under another name. Over 6,000 characters each sent the
  script as a file to one fixed path on the VPS
  (C:/Windows/Temp/thornswood-remote.ps1 in seventeen of them), so two runs at
  once could run or delete each other's script, and each handed back the exit
  code of the tidy up rather than of the script. This proves the helper that
  replaced them does not:

    - a short script goes on the command line, once, and its exit code comes
      back;
    - a long one goes up as C:/Windows/Temp/thornswood-remote-<guid>.ps1, a
      new name each run, is run from there by that name, bare, and removed,
      and the local copy is removed too;
    - the exit code is the far side's, not the tidy up's;
    - the file is removed even when the run fails, and nothing is run or
      removed when the copy up fails;
    - host key checking is always on, and a caller's weaker setting is
      refused before anything is sent;
    - standard input reaches the far side both ways (Send-Secret.ps1 uses it);
    - two runs at once, in two processes, each run their own script, get
      their own exit code and leave nothing behind. The old fixed name,
      run the same way, is shown to collide, so the check is known to catch
      it.

  And, reading the scripts: no script sends to a fixed file name in the VPS
  temp folder any more, and every script that had a copy uses the helper.

  THE FAR SIDE IS THIS MACHINE. The fake ssh runs what it is handed in Windows
  PowerShell here (pwsh where there is none), with a scratch folder standing
  for C:/Windows/Temp. Every host it names ends in .invalid. Never connects.
#>
[CmdletBinding()]
param()
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
$sendScript = Join-Path $repo 'scripts\vps\Send-Script.ps1'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Remove-Item -Path function:global:ssh, function:global:scp -ErrorAction SilentlyContinue
    if ($script:work -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

Yes 'scripts\vps\Send-Script.ps1 is there' (Test-Path -LiteralPath $sendScript)
if ($script:fail) { Done }
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($sendScript, [ref]$null, [ref]$errs)
Yes 'Send-Script.ps1 parses' (@($errs).Count -eq 0)
. $sendScript

. (Join-Path $PSScriptRoot 'Windows.ps1')
if ($OnWindows) { $farShell = Get-WindowsPowerShell }
else {
    $farShell = (Get-Process -Id $PID).Path
    Write-Host 'NOTE  the far side runs in this shell, not in Windows PowerShell 5.1 as on the box: this is not Windows'
}

$script:work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-send-script-' + [Guid]::NewGuid().ToString('N'))
$far = Join-Path $script:work 'far'
New-Item -ItemType Directory -Path $far -Force | Out-Null

# ---- the fakes, as text, so the two processes of the at-once case load the
# same ones. $global:TsSs is their state: the far folder, every call, how long
# a -File run waits before it starts, and what should fail.
$fakes = @'
function global:ssh {
    $a = @($args | ForEach-Object { [string]$_ })
    $cmd = $a[-1]
    $in = @($input)
    [void]$global:TsSs.Calls.Add([pscustomobject]@{ Tool = 'ssh'; Args = $a; Command = $cmd })
    $temp = 'C:/Windows/Temp/'
    $m = [regex]::Match($cmd, '^powershell -NoProfile (-ExecutionPolicy Bypass )?-EncodedCommand ([A-Za-z0-9+/=]+)$')
    if ($m.Success) {
        if ($in.Count) { $in | & $global:TsSs.Shell -NoProfile -NonInteractive -EncodedCommand $m.Groups[2].Value 2>&1 }
        else { & $global:TsSs.Shell -NoProfile -NonInteractive -EncodedCommand $m.Groups[2].Value 2>&1 }
        return
    }
    $m = [regex]::Match($cmd, '^powershell -NoProfile -ExecutionPolicy Bypass -File (C:/Windows/Temp/[A-Za-z0-9._-]+)$')
    if ($m.Success) {
        if ($global:TsSs.RunThrows) { throw 'the run broke on the way' }
        if ($global:TsSs.RunDelayMs) { Start-Sleep -Milliseconds $global:TsSs.RunDelayMs }
        $here = Join-Path $global:TsSs.Far $m.Groups[1].Value.Substring($temp.Length)
        if (-not (Test-Path -LiteralPath $here)) { 'THE FILE WAS NOT THERE'; $global:LASTEXITCODE = 1; return }
        if ($in.Count) { $in | & $global:TsSs.Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $here 2>&1 }
        else { & $global:TsSs.Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $here 2>&1 }
        return
    }
    $m = [regex]::Match($cmd, '^powershell -NoProfile -Command Remove-Item -LiteralPath ''(C:/Windows/Temp/[A-Za-z0-9._-]+)'' -Force$')
    if ($m.Success) {
        Remove-Item -LiteralPath (Join-Path $global:TsSs.Far $m.Groups[1].Value.Substring($temp.Length)) -Force -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0
        return
    }
    'THE FAKE SSH DID NOT RUN THIS: ' + $cmd
    $global:LASTEXITCODE = 255
}
function global:scp {
    $a = @($args | ForEach-Object { [string]$_ })
    $src = $a[-2]; $dst = $a[-1]
    [void]$global:TsSs.Calls.Add([pscustomobject]@{ Tool = 'scp'; Args = $a; Command = $dst; Src = $src; Sent = [IO.File]::ReadAllText($src) })
    if ($global:TsSs.ScpFails) { $global:LASTEXITCODE = 1; return }
    $m = [regex]::Match($dst, '^[^@\s]+@[^:\s]+:C:/Windows/Temp/([A-Za-z0-9._-]+)$')
    if (-not $m.Success) { $global:LASTEXITCODE = 1; return }
    Copy-Item -LiteralPath $src -Destination (Join-Path $global:TsSs.Far $m.Groups[1].Value) -Force
    $global:LASTEXITCODE = 0
}
'@
function New-FakeState([string]$farDir, [string]$shell) {
    return @{ Far = $farDir; Shell = $shell; Calls = (New-Object System.Collections.ArrayList); RunDelayMs = 0; RunThrows = $false; ScpFails = $false }
}
$global:TsSs = New-FakeState $far $farShell
. ([scriptblock]::Create($fakes))
Yes 'ssh and scp are the fakes here, so nothing can reach a server' ((Get-Command ssh).CommandType -eq 'Function' -and (Get-Command scp).CommandType -eq 'Function')

$target = 'tester@box.invalid'
$sshArgs = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=1')

# A script long enough to go by file, printing a marker and exiting with a
# code of its own.
function Long([string]$marker, [int]$code) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Write-Output 'MARK $marker'")
    $n = 0
    while (($lines -join "`r`n").Length -lt 4000) { $n++; $lines.Add(('$null = {0} # filler so the script is too long for one command line' -f $n)) }
    $lines.Add("exit $code")
    return ($lines -join "`r`n")
}
# Callers wrap it in @(): one call comes back a lone PSCustomObject, which has no .Count on 5.1 (#2226).
function Calls([string]$tool) { return @($global:TsSs.Calls | Where-Object { $_.Tool -eq $tool }) }
function Reset { $global:TsSs.Calls.Clear(); $global:TsSs.RunThrows = $false; $global:TsSs.ScpFails = $false; $global:TsSs.RunDelayMs = 0 }
function Left { return @(Get-ChildItem -LiteralPath $far -File).Count }
$nameShape = '^C:/Windows/Temp/thornswood-remote-[0-9a-f]{32}\.ps1$'

# ---- 1. short: on the command line --------------------------------------------
Reset
$out = @(Invoke-ThornswoodRemote -Target $target -SshArgs $sshArgs -Script "Write-Output 'short'; exit 3" | ForEach-Object { "$_" })
$rc = $LASTEXITCODE
Yes 'short: one ssh call and no scp' (@(Calls 'ssh').Count -eq 1 -and @(Calls 'scp').Count -eq 0)
Yes 'short: what it printed comes back' ($out -contains 'short')
Yes 'short: the far side''s exit code comes back (3)' ($rc -eq 3)

# ---- 2. long: a file of its own name, run, removed ------------------------------
Reset
$out = @(Invoke-ThornswoodRemote -Target $target -SshArgs $sshArgs -Script (Long 'one' 7) | ForEach-Object { "$_" })
$rc = $LASTEXITCODE
$sc = @(Calls 'scp')
$dest = ''
if ($sc.Count) { $dest = $sc[0].Command.Substring($sc[0].Command.IndexOf(':') + 1) }
Yes 'long: copied up once' ($sc.Count -eq 1)
Yes ('long: to a name of its own, thornswood-remote-<guid>.ps1 (' + $dest + ')') ($dest -match $nameShape)
Yes 'long: never to the old shared name' ($dest -ne 'C:/Windows/Temp/thornswood-remote.ps1')
Yes 'long: the file holds the whole script, with a byte order mark' ($sc.Count -eq 1 -and $sc[0].Sent.Contains((Long 'one' 7)))
$runs = @(Calls 'ssh' | Where-Object { $_.Command -like '*-File *' })
Yes 'long: run once, by that same name, bare' ($runs.Count -eq 1 -and $runs[0].Command -eq ('powershell -NoProfile -ExecutionPolicy Bypass -File ' + $dest))
$tidy = @(Calls 'ssh' | Where-Object { $_.Command -like '*Remove-Item*' })
Yes 'long: removed afterwards, by that same name' ($tidy.Count -eq 1 -and $tidy[0].Command.Contains("'" + $dest + "'"))
Yes 'long: nothing is left in the far temp folder' ((Left) -eq 0)
Yes 'long: the local copy is gone too' ($sc.Count -eq 1 -and -not (Test-Path -LiteralPath $sc[0].Src))
Yes 'long: what it printed comes back' ($out -contains 'MARK one')
Yes 'long: the far side''s exit code comes back (7), not the tidy up''s (0)' ($rc -eq 7)
$first = $dest

Reset
$out = @(Invoke-ThornswoodRemote -Target $target -SshArgs $sshArgs -Script (Long 'two' 0) | ForEach-Object { "$_" })
$rc = $LASTEXITCODE
$sc = @(Calls 'scp')
$second = ''
if ($sc.Count) { $second = $sc[0].Command.Substring($sc[0].Command.IndexOf(':') + 1) }
Yes 'long again: a different name from the run before' ($second -match $nameShape -and $second -ne $first)
Yes 'long again: a script that exits 0 hands back 0' ($rc -eq 0 -and ($out -contains 'MARK two'))

# ---- 3. when something fails -----------------------------------------------------
Reset
$global:TsSs.RunThrows = $true
$threw = $null
try { Invoke-ThornswoodRemote -Target $target -SshArgs $sshArgs -Script (Long 'three' 0) | Out-Null } catch { $threw = $_ }
$rc = $LASTEXITCODE
$sc = @(Calls 'scp')
Yes 'a run that breaks: the error reaches the caller' ($null -ne $threw)
Yes '  the file is still removed from the far side' (@(Calls 'ssh' | Where-Object { $_.Command -like '*Remove-Item*' }).Count -eq 1 -and (Left) -eq 0)
Yes '  and the local copy' ($sc.Count -eq 1 -and -not (Test-Path -LiteralPath $sc[0].Src))
Yes '  and the exit code says it failed' ($rc -ne 0)

Reset
$global:TsSs.ScpFails = $true
$threw = $null
try { Invoke-ThornswoodRemote -Target $target -SshArgs $sshArgs -Script (Long 'four' 0) | Out-Null } catch { $threw = $_ }
$rc = $LASTEXITCODE
Yes 'a copy up that fails: it stops and says nothing was run' ($null -ne $threw -and "$threw" -match 'Nothing was run')
Yes '  nothing is run and nothing removed' (@(Calls 'ssh').Count -eq 0)
Yes '  and the exit code says it failed' ($rc -ne 0)

# ---- 4. host key checking ---------------------------------------------------------
Reset
$threw = $null
try { Invoke-ThornswoodRemote -Target $target -SshArgs @('-o', 'StrictHostKeyChecking=no') -Script "'x'" | Out-Null } catch { $threw = $_ }
Yes 'StrictHostKeyChecking=no from a caller is refused' ($null -ne $threw)
$threw = $null
try { Invoke-ThornswoodRemote -Target $target -SshArgs @('-o', 'StrictHostKeyChecking=accept-new') -Script (Long 'five' 0) | Out-Null } catch { $threw = $_ }
Yes 'and so is accept-new' ($null -ne $threw)
Yes '  before anything was sent' ($global:TsSs.Calls.Count -eq 0)
Reset
Invoke-ThornswoodRemote -Target $target -SshArgs $sshArgs -Script (Long 'six' 0) | Out-Null
Invoke-ThornswoodRemote -Target $target -Script "'y'" | Out-Null
$weak = @($global:TsSs.Calls | Where-Object { ($_.Args -join ' ') -notmatch 'StrictHostKeyChecking=yes' })
Yes ('every ssh and scp call carries StrictHostKeyChecking=yes, with or without the caller''s options (' + $global:TsSs.Calls.Count + ' calls)') ($global:TsSs.Calls.Count -ge 4 -and $weak.Count -eq 0)
Yes 'the caller''s own options are passed on' (@($global:TsSs.Calls | Where-Object { ($_.Args -join ' ') -match 'ConnectTimeout=1' }).Count -ge 3)

# ---- 5. standard input and -Bypass -------------------------------------------------
Reset
$reader = "`$l = [Console]::In.ReadLine(); Write-Output ('GOT ' + `$l)"
$out = @(Invoke-ThornswoodRemote -Target $target -SshArgs $sshArgs -Script $reader -Stdin 'line-on-stdin' | ForEach-Object { "$_" })
Yes '-Stdin: a short script reads the line' ($out -contains 'GOT line-on-stdin')
Reset
$out = @(Invoke-ThornswoodRemote -Target $target -SshArgs $sshArgs -Script ($reader + "`r`n" + (Long 'seven' 0)) -Stdin 'line-on-stdin' | ForEach-Object { "$_" })
Yes '-Stdin: a long one, run from its file, reads it too' ($out -contains 'GOT line-on-stdin' -and @(Calls 'scp').Count -eq 1)
Yes '-Stdin: the line is in no command line and no file sent' (-not (($global:TsSs.Calls | ForEach-Object { ($_.Args -join ' ') + [string]$_.Sent }) -join "`n").Contains('line-on-stdin'))
Reset
Invoke-ThornswoodRemote -Target $target -SshArgs $sshArgs -Script "'z'" -Bypass | Out-Null
Yes '-Bypass: the command line says -ExecutionPolicy Bypass' (@(Calls 'ssh').Count -eq 1 -and @(Calls 'ssh')[0].Command -like 'powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand *')

# ---- 6. two runs at once ------------------------------------------------------------
#
# Two processes, one far folder. Each waits for the same go file, copies its
# script up, then waits two seconds before its run starts, which is when the
# other one's copy lands. With one shared name the second copy replaces the
# first, and the first runs the wrong script or finds it gone.
$oldCopy = @'
function Invoke-OldRemote([string]$Target, [string[]]$SshArgs, [string]$Script) {
  $far = 'C:/Windows/Temp/thornswood-remote.ps1'
  $tmp = [IO.Path]::GetTempFileName()
  try {
    Set-Content -LiteralPath $tmp -Value $Script -Encoding UTF8
    & scp @SshArgs $tmp "${Target}:$far" 2>&1 | Out-Null
    & ssh @SshArgs $Target "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
    & ssh @SshArgs $Target "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}
'@
function Start-AtOnce([string]$how) {
    $farDir = Join-Path $script:work ('far-' + $how)
    New-Item -ItemType Directory -Path $farDir -Force | Out-Null
    $go = Join-Path $script:work ('go-' + $how)
    $jobs = @()
    foreach ($pair in @(@('A', 5), @('B', 6))) {
        $jobs += Start-Job -ScriptBlock {
            param($fakes, $oldCopy, $sendScript, $farDir, $shell, $go, $how, $marker, $code, $target, $script)
            $global:TsSs = @{ Far = $farDir; Shell = $shell; Calls = (New-Object System.Collections.ArrayList); RunDelayMs = 2000; RunThrows = $false; ScpFails = $false }
            . ([scriptblock]::Create($fakes))
            . $sendScript
            . ([scriptblock]::Create($oldCopy))
            [IO.File]::WriteAllText(($go + '.' + $marker), 'ready')
            while (-not (Test-Path -LiteralPath $go)) { Start-Sleep -Milliseconds 50 }
            $global:LASTEXITCODE = 0
            if ($how -eq 'new') { $out = @(Invoke-ThornswoodRemote -Target $target -Script $script 2>&1 | ForEach-Object { "$_" }) }
            else { $out = @(Invoke-OldRemote -Target $target -SshArgs @() -Script $script 2>&1 | ForEach-Object { "$_" }) }
            $rc = $LASTEXITCODE
            $names = @($global:TsSs.Calls | Where-Object { $_.Tool -eq 'scp' } | ForEach-Object { $_.Command.Substring($_.Command.IndexOf(':') + 1) })
            [pscustomobject]@{ Marker = $marker; Out = $out; Code = $rc; Names = $names }
        } -ArgumentList $fakes, $oldCopy, $sendScript, $farDir, $farShell, $go, $how, $pair[0], $pair[1], $target, (Long $pair[0] $pair[1])
    }
    $until = (Get-Date).AddSeconds(90)
    while (((Get-ChildItem -LiteralPath $script:work -Filter ('go-' + $how + '.*')).Count -lt 2) -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 100 }
    [IO.File]::WriteAllText($go, 'go')
    $res = @($jobs | Wait-Job -Timeout 120 | Receive-Job)
    $jobs | Remove-Job -Force
    return [pscustomobject]@{ Results = $res; Left = @(Get-ChildItem -LiteralPath $farDir -File).Count }
}

$new = Start-AtOnce 'new'
$a = @($new.Results | Where-Object { $_.Marker -eq 'A' }) | Select-Object -First 1
$b = @($new.Results | Where-Object { $_.Marker -eq 'B' }) | Select-Object -First 1
Yes 'at once: both runs finished' ($a -and $b)
if ($a -and $b) {
    Yes ('at once: each copied to a name of its own (' + ($a.Names -join ',') + ' and ' + ($b.Names -join ',') + ')') (
        $a.Names.Count -eq 1 -and $b.Names.Count -eq 1 -and $a.Names[0] -match $nameShape -and $b.Names[0] -match $nameShape -and $a.Names[0] -ne $b.Names[0])
    Yes 'at once: each ran its own script and not the other''s' (($a.Out -contains 'MARK A') -and -not ($a.Out -contains 'MARK B') -and ($b.Out -contains 'MARK B') -and -not ($b.Out -contains 'MARK A'))
    Yes ('at once: each got its own exit code (' + $a.Code + ' and ' + $b.Code + ')') ($a.Code -eq 5 -and $b.Code -eq 6)
    Yes 'at once: nothing is left in the far temp folder' ($new.Left -eq 0)
}

$old = Start-AtOnce 'old'
$oa = @($old.Results | Where-Object { $_.Marker -eq 'A' }) | Select-Object -First 1
$ob = @($old.Results | Where-Object { $_.Marker -eq 'B' }) | Select-Object -First 1
$collided = $false
if ($oa -and $ob) {
    $collided = (-not ($oa.Out -contains 'MARK A')) -or (-not ($ob.Out -contains 'MARK B')) -or ($oa.Out -contains 'MARK B') -or ($ob.Out -contains 'MARK A')
}
Yes 'the old copy, run the same way, collides: one run did not run its own script (so the check above can fail)' $collided

# ---- 7. the scripts -----------------------------------------------------------------
$skip = '(?i)[\\/](tests|engine|node_modules|\.git|local|out)[\\/]'
$files = @(Get-ChildItem -LiteralPath $repo -Recurse -File -Filter *.ps1 -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName.Substring($repo.Length) -notmatch $skip })
Yes ('scripts found to read: ' + $files.Count) ($files.Count -gt 100)

# A whole file name in the VPS temp folder written as one literal is a name
# every run shares. A name with a guid added at run time is not one literal.
$fixed = @()
foreach ($f in $files) {
    $tokens = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$e)
    foreach ($s in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] }, $true))) {
        if ($s.Value -match '(?i)^C:[\\/]+Windows[\\/]+Temp[\\/]+[A-Za-z0-9._-]+\.[A-Za-z0-9]+$') { $fixed += ('{0}:{1}  {2}' -f $f.Name, $s.Extent.StartLineNumber, $s.Value) }
    }
}
foreach ($x in $fixed) { Write-Host "      $x" }
Yes ('no script sends to a fixed file name in the VPS temp folder (' + $fixed.Count + ' found)') ($fixed.Count -eq 0)

$shared = @()
foreach ($f in $files) {
    $i = 0
    foreach ($l in [IO.File]::ReadAllLines($f.FullName)) { $i++; if ($l -match '(?i)thornswood-remote\.ps1' -and $l -notmatch '^\s*#' -and $f.Name -ne 'Send-Script.ps1') { $shared += ('{0}:{1}' -f $f.Name, $i) } }
}
Yes ('no script names C:/Windows/Temp/thornswood-remote.ps1 (' + ($shared -join ', ') + ')') ($shared.Count -eq 0)

# A function that copies a script up and runs it by file itself, rather than
# through Send-Script.ps1, names the file afresh each run. Harden-VPS.ps1
# does that on purpose: it sends a file of the repository with its own
# arguments, and it already used a guid before #1070. Feed-Store.ps1 used to
# be the other one; since #1167 Invoke-FeedStoreOp sends through the helper.
$own = @()
foreach ($f in $files) {
    if ($f.Name -eq 'Send-Script.ps1') { continue }
    $tokens = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$e)
    foreach ($fn in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
        $t = $fn.Extent.Text
        if ($t -match '&\s*scp\b' -and $t -match '-File\s+\$' -and $t -notmatch 'NewGuid\(\)') { $own += ('{0}:{1} {2}' -f $f.Name, $fn.Extent.StartLineNumber, $fn.Name) }
    }
}
foreach ($x in $own) { Write-Host "      $x" }
Yes ('no function copies a script up and runs it by a name it does not make afresh each run (' + $own.Count + ' found)') ($own.Count -eq 0)

$named = @(
    'scripts\deploy\Deploy-DevGamemode.ps1', 'scripts\deploy\Deploy-Docs.ps1', 'scripts\deploy\Deploy-Server.ps1',
    'scripts\deploy\Install-Bot.ps1', 'scripts\deploy\Remirror-Site-Feed.ps1', 'scripts\deploy\Rotate-ServerPassword.ps1',
    'scripts\deploy\Set-DiscordLogin.ps1', 'scripts\deploy\Setup-Domain.ps1', 'scripts\mods\Check-Manifest.ps1',
    'scripts\mods\Clean-Everything.ps1', 'scripts\ops\Set-Door.ps1', 'scripts\ops\Wipe-Saves.ps1',
    'scripts\release\Publish-Installer.ps1', 'scripts\vps\Backup-Server.ps1', 'scripts\vps\Check-Load.ps1',
    'scripts\vps\Watch-Load.ps1', 'scripts\vps\Watch-Services.ps1',
    'scripts\deploy\Install-Runner.ps1', 'scripts\deploy\Install-Voice.ps1', 'scripts\vps\Check-Site.ps1'
)
$notUsing = @()
foreach ($rel in $named) {
    $path = Join-Path $repo $rel
    $tokens = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$e)
    $fn = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Remote' }, $true))
    $text = [IO.File]::ReadAllText($path)
    $ok = ($fn.Count -eq 1 -and $fn[0].Extent.Text -match 'Invoke-ThornswoodRemote -Target' -and $text -match "Send-Script\.ps1'\)")
    if (-not $ok) { $notUsing += (Split-Path -Leaf $rel) }
}
Yes ('the ' + $named.Count + ' scripts that had a copy load Send-Script.ps1 and their Remote uses it' + $(if ($notUsing.Count) { ': not ' + ($notUsing -join ', ') } else { '' })) ($notUsing.Count -eq 0)
$remoteText = [IO.File]::ReadAllText((Join-Path $repo 'scripts\vps\Remote.ps1'))
$secretText = [IO.File]::ReadAllText((Join-Path $repo 'scripts\vps\Send-Secret.ps1'))
$artifactText = [IO.File]::ReadAllText((Join-Path $repo 'scripts\deploy\Artifact.ps1'))
Yes 'Remote.ps1, Send-Secret.ps1 and Artifact.ps1 send through it too' (
    $remoteText -match 'Invoke-ThornswoodRemote -Target' -and $secretText -match 'Invoke-ThornswoodRemote -Target' -and $artifactText -match 'Invoke-ThornswoodRemote -Target')
$helperText = [IO.File]::ReadAllText($sendScript)
Yes 'Send-Script.ps1 turns host key checking on with =yes and never anything weaker (#1078)' (
    $helperText -match "'StrictHostKeyChecking=yes'" -and $helperText -notmatch 'StrictHostKeyChecking=(no|accept-new)')

# ---- Feed-Store.ps1, through the helper, against the same stand-in (#1167) --
Reset
$feedStore = Join-Path $repo 'scripts\release\Feed-Store.ps1'
Yes 'Feed-Store.ps1 is there' (Test-Path -LiteralPath $feedStore)
. $feedStore
$feedSite = Join-Path $script:work 'feed-site'
New-Item -ItemType Directory -Path $feedSite -Force | Out-Null
$oldSite = $env:THORNSWOOD_TEST_SITE_DIR
Remove-Item Env:THORNSWOOD_TEST_SITE_DIR -ErrorAction SilentlyContinue
try {
    $feedOut = @(Invoke-FeedStoreOp 'main' 'look' @('version.json') @{} @{} '' @{ Vps = 'box.invalid'; User = 'tester'; Root = ($feedSite.Replace('\', '/')) })
} finally {
    if ($null -ne $oldSite) { $env:THORNSWOOD_TEST_SITE_DIR = $oldSite }
}
$feedRc = $LASTEXITCODE
$feedScp = @(Calls 'scp')
$feedDest = ''
if ($feedScp.Count) { $feedDest = $feedScp[0].Command.Substring($feedScp[0].Command.IndexOf(':') + 1) }
Yes 'Feed-Store Invoke-FeedStoreOp sends a long script through Invoke-ThornswoodRemote (#1167)' ($feedDest -match $nameShape)
Yes '  not under its old thornswood-feed-store name' ($feedDest -notmatch 'thornswood-feed-store')
Yes '  the stand-in ran it and it said DONE' ($feedOut -contains 'DONE')
Yes '  and NONE for a file the scratch store does not have' ($feedOut -contains 'NONE|version.json')
Yes '  the file is removed afterwards' ((Left) -eq 0)
Yes '  and the far side''s exit code comes back, not a dropped one' ($feedRc -eq 0)
$feedFn = ''
$ft = $null; $fe = $null
$fast = [System.Management.Automation.Language.Parser]::ParseFile($feedStore, [ref]$ft, [ref]$fe)
foreach ($fn in @($fast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-FeedStoreOp' }, $true))) { $feedFn = $fn.Extent.Text }
Yes '  and Invoke-FeedStoreOp no longer copies a script up itself' ($feedFn -match 'Invoke-ThornswoodRemote -Target' -and $feedFn -notmatch '&\s*scp\b')

Done
