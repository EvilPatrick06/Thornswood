<#
  test-roll-log.ps1

  Roll-Log.ps1, and every command line that runs it, driven for real in a temp
  folder. Entry 220: "Nothing rotates, so last night's crash is at the end of
  a file that grows forever."

  WHY THE COMMAND LINES ARE RUN AND NOT JUST READ. server.log, voice.log and
  bot.log are written by cmd's >> from a scheduled task, and on Windows a file
  held that way cannot be renamed or truncated while the service runs. So the
  roll has to happen in front of the service, inside the same cmd line, and a
  quoting mistake in that line is a game server that does not start. Each line
  is lifted out of the installer that registers it, filled in with this
  machine's node and a temp folder, and handed to cmd.exe exactly as Task
  Scheduler hands it: the arguments string, verbatim, with a stand-in for the
  service that writes to stdout and stderr.

  What it proves:
    the roller: under 4 MB left alone, at 4 MB rolled, five kept and the
      oldest the only thing that goes, -Force, empty and missing files, and a
      file cmd still holds left exactly as it is, older ones included
    the game server's task line (Install-ThornswoodServer.ps1): rolls, then
      the server writes both streams to a fresh server.log, and it still
      starts when the roller is missing
    the voice task line (Install-Voice.ps1): the same, and the environment it
      sets still reaches node
    the dev voice run file (vps-dev-instance.ps1): the same
    the bot's run.ps1 loop (Install-Bot.ps1): rolls before python, carries on
      when the roller is missing, and the read-back of what the bot said
      still finds this start's lines after a roll made the file shorter
    the server installer keeps the logs across the folder it deletes, and
      each installer sends the roller up

  Nothing here reaches the VPS or any service. Everything it writes is under
  its own temp folder.
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

$roller = Join-Path $ToolsPath 'Roll-Log.ps1'
$winps  = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
$node   = $null
$nc = Get-Command node -ErrorAction SilentlyContinue
if ($nc) { $node = $nc.Source }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-rolllog-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Put([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text) }
function Get([string]$path) {
    if (Test-Path -LiteralPath $path) { return [IO.File]::ReadAllText($path) }
    return $null
}
function Fill([string]$path, [long]$bytes) {
    [IO.File]::WriteAllBytes($path, [Text.Encoding]::ASCII.GetBytes(('x' * $bytes)))
}
function Size([string]$path) {
    if (Test-Path -LiteralPath $path) { return (Get-Item -LiteralPath $path).Length }
    return -1
}
function Count([string]$text, [string]$what) {
    if ($null -eq $text) { return 0 }
    return ([regex]::Matches($text, [regex]::Escape($what))).Count
}

# The roller the way the task and run.ps1 run it: Windows PowerShell, in a
# process of its own.
function Roll([string]$path, [string[]]$more) {
    $ErrorActionPreference = 'Continue'
    if (-not $more) { $more = @() }
    $out = & $winps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $roller -Path $path @more 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = ((@($out) | ForEach-Object { "$_" }) -join "`n") }
}

# cmd.exe with an arguments string passed through untouched, which is what a
# scheduled task's action does with its Arguments.
function RunCmd([string]$arguments, [string]$dir, [int]$waitMs = 60000) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $cmdExe
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    if ($waitMs -gt 0) { [void]$p.WaitForExit($waitMs) }
    return $p
}

# Fills a format string lifted out of an installer, by the names of the
# variables it is given there, so the order they appear in does not matter.
function FillLine([string]$format, [string]$names, [hashtable]$values) {
    $vals = @()
    foreach ($n in ($names -split ',')) {
        $k = $n.Trim().Replace('`', '')
        if (-not $values.ContainsKey($k)) { return $null }
        $vals += $values[$k]
    }
    return ($format -f $vals)
}

function Get-BlockText([string]$text, [string]$start) {
    $at = $text.IndexOf($start)
    if ($at -lt 0) { return $null }
    $b = $text.IndexOf('{', $at)
    if ($b -lt 0) { return $null }
    $depth = 0
    for ($i = $b; $i -lt $text.Length; $i++) {
        $c = $text[$i]
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($at, $i - $at + 1) } }
    }
    return $null
}

try {
    # =================================================================== the roller
    Yes 'Roll-Log.ps1 is in tools' (Test-Path -LiteralPath $roller)
    if (-not (Test-Path -LiteralPath $roller)) { throw 'no roller, nothing else can be checked' }

    $d = Join-Path $tmp 'roller'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $f = Join-Path $d 'x.log'

    Put $f 'small'
    $r = Roll $f
    Yes 'a small log is left alone' ((Get $f) -eq 'small' -and -not (Test-Path -LiteralPath ($f + '.1')))
    Yes 'and the roller exits 0' ($r.Code -eq 0)

    $r = Roll (Join-Path $d 'never-written.log')
    Yes 'a log that is not there is not an error' ($r.Code -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $d 'never-written.log.1')))

    Put $f ''
    $r = Roll $f @('-Force')
    Yes 'an empty log is not worth a place, even forced' (-not (Test-Path -LiteralPath ($f + '.1')))

    Put $f 'forced'
    $r = Roll $f @('-Force')
    Yes '-Force rolls a small log' ((Get ($f + '.1')) -eq 'forced' -and -not (Test-Path -LiteralPath $f))
    Yes 'and says so' ($r.Out -match 'rolled x\.log')
    Remove-Item -LiteralPath ($f + '.1') -Force

    # The 4 MB the task relies on, since the task passes no size.
    Fill $f (4MB - 1)
    [void](Roll $f)
    Yes 'one byte under 4 MB is left alone' ((Size $f) -eq (4MB - 1) -and -not (Test-Path -LiteralPath ($f + '.1')))
    Fill $f 4MB
    [void](Roll $f)
    Yes 'at 4 MB it rolls to .1' ((Size ($f + '.1')) -eq 4MB -and -not (Test-Path -LiteralPath $f))
    Remove-Item -LiteralPath ($f + '.1') -Force

    # Five kept, the oldest the only thing that goes, nothing overwritten.
    $words = 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE'
    for ($i = 0; $i -lt 5; $i++) { Put ($f + '.' + ($i + 1)) $words[$i] }
    Put $f 'LIVE'
    [void](Roll $f @('-MaxBytes', '2'))
    Yes 'the live log becomes .1' ((Get ($f + '.1')) -eq 'LIVE')
    Yes 'what was .1 becomes .2' ((Get ($f + '.2')) -eq 'ONE')
    Yes 'what was .4 becomes .5' ((Get ($f + '.5')) -eq 'FOUR')
    Yes 'what was .5 is the only thing that goes' (-not (Test-Path -LiteralPath ($f + '.6')) -and
        -not (@(1, 2, 3, 4, 5) | Where-Object { (Get ($f + '.' + $_)) -eq 'FIVE' }))
    Yes 'the live log is out of the way for the service to start a fresh one' (-not (Test-Path -LiteralPath $f))

    # A log cmd is still holding, the whole reason this runs at start.
    $held = Join-Path $d 'held.log'
    Put ($held + '.1') 'OLDER'
    $holder = RunCmd ('/c "ping -n 30 127.0.0.1 >> "' + $held + '""') $d 0
    for ($i = 0; $i -lt 50 -and (Size $held) -le 0; $i++) { Start-Sleep -Milliseconds 100 }
    $r = Roll $held @('-Force')
    Yes 'a log cmd holds open is refused, and the roller says so' ($r.Code -eq 0 -and $r.Out -match 'held')
    Yes 'the held log is still where it was' ((Size $held) -gt 0)
    Yes 'and the older ones were not moved around it' ((Get ($held + '.1')) -eq 'OLDER' -and -not (Test-Path -LiteralPath ($held + '.2')))
    foreach ($c in @(Get-CimInstance Win32_Process -Filter ("ParentProcessId=" + $holder.Id) -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $c.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $holder.Id -Force -ErrorAction SilentlyContinue
    [void]$holder.WaitForExit(10000)
    Start-Sleep -Milliseconds 300
    $r = Roll $held @('-Force')
    Yes 'once the holder is gone it rolls' ((Size ($held + '.1')) -gt 0 -and (Get ($held + '.1')) -ne 'OLDER' -and (Get ($held + '.2')) -eq 'OLDER')

    # ======================================================= the game server task
    $inst = Get-Content -LiteralPath (Join-Path $ToolsPath 'Install-ThornswoodServer.ps1') -Raw
    $m = [regex]::Match($inst, '\$cmd = \(''(/c [^\r\n]*?skymp5-server\.js[^\r\n]*?)'' -f ([^\r\n]+)\)')
    Yes 'the server task line is in Install-ThornswoodServer.ps1' $m.Success

    if (-not $node) {
        Write-Host 'SKIP  node is not on this machine, so the task lines cannot be run'
    } elseif ($m.Success) {
        $srv = Join-Path $tmp 'server'
        New-Item -ItemType Directory -Force -Path (Join-Path $srv 'dist_back') | Out-Null
        Put (Join-Path $srv 'dist_back\skymp5-server.js') ("console.log('stand-in server up');`nconsole.error('stand-in server on stderr');`n")
        Copy-Item -LiteralPath $roller -Destination (Join-Path $srv 'roll-log.ps1')
        $log = Join-Path $srv 'server.log'
        $line = FillLine $m.Groups[1].Value $m.Groups[2].Value @{
            '$node.Source' = $node; '$log' = $log; '$psExe' = $winps; '$roller' = (Join-Path $srv 'roll-log.ps1')
        }
        Yes 'the harness knows every value the installer puts in the server line' ($null -ne $line)
        if ($line) {
            Fill $log (4MB + 100)
            $p = RunCmd $line $srv
            Yes 'the server line runs to the end' $p.HasExited
            Yes 'a server.log past 4 MB is rolled before the server starts' ((Size ($log + '.1')) -eq (4MB + 100))
            $t = Get $log
            Yes 'the server writes its stdout to a fresh server.log' ((Count $t 'stand-in server up') -eq 1 -and (Size $log) -lt 4096)
            Yes 'and its stderr' ((Count $t 'stand-in server on stderr') -eq 1)
            Yes 'and nothing of the roller''s lands in it' ((Count $t 'rolled') -eq 0)

            [void](RunCmd $line $srv)
            Yes 'the next start appends, under 4 MB' ((Count (Get $log) 'stand-in server up') -eq 2 -and -not (Test-Path -LiteralPath ($log + '.2')))

            Remove-Item -LiteralPath (Join-Path $srv 'roll-log.ps1') -Force
            [void](RunCmd $line $srv)
            Yes 'with no roller the server still starts' ((Count (Get $log) 'stand-in server up') -eq 3)
        }
    }

    # ============================================================ the voice task
    $vtext = Get-Content -LiteralPath (Join-Path $ToolsPath 'Install-Voice.ps1') -Raw
    $m = [regex]::Match($vtext, '`\$cmd = \(''(/c "set THORNSWOOD_SITE=[^\r\n]*?)'' -f ([^\r\n]+)\)')
    Yes 'the voice task line is in Install-Voice.ps1' $m.Success
    if ($node -and $m.Success) {
        $vr = Join-Path $tmp 'voice'
        New-Item -ItemType Directory -Force -Path $vr | Out-Null
        Put (Join-Path $vr 'voice-server.js') ("console.log('stand-in voice up on ' + process.env.THORNSWOOD_VOICE_PORT + ' auth ' + process.env.THORNSWOOD_VOICE_AUTH);`n")
        Copy-Item -LiteralPath $roller -Destination (Join-Path $vr 'roll-log.ps1')
        $vlog = Join-Path $vr 'voice.log'
        # What the outer here-string fills in at install time.
        $fmt = $m.Groups[1].Value.Replace('$Site', 'https://site.invalid').Replace('$Port', '7999').Replace('$Bind', '127.0.0.1').Replace('$Auth', 'log')
        $line = FillLine $fmt $m.Groups[2].Value @{
            '$node.Source' = $node; '$log' = $vlog; '$psExe' = $winps; '$roll' = (Join-Path $vr 'roll-log.ps1')
        }
        Yes 'the harness knows every value the installer puts in the voice line' ($null -ne $line)
        if ($line) {
            Fill $vlog (4MB + 7)
            $p = RunCmd $line $vr
            Yes 'a voice.log past 4 MB is rolled before voice starts' ((Size ($vlog + '.1')) -eq (4MB + 7))
            Yes 'voice is still writing to voice.log afterwards, with its settings' ((Count (Get $vlog) 'stand-in voice up on 7999 auth log') -eq 1)
            Yes 'the command line still names the log, which is how the installer finds its own process' ($line -like ('*' + $vlog + '*'))
        }
    }
    Yes 'Install-Voice sends the roller up beside the service' ($vtext -match 'Join-Path \$Here ''Roll-Log\.ps1''' -and $vtext -match '/roll-log\.ps1"')
    Yes 'Install-Voice rolls voice.log at install rather than deleting it' (
        $vtext -notmatch 'Remove-Item -LiteralPath `\$log\b' -and $vtext -match '& `\$roll -Path `\$log -Force')

    # ============================================================ the dev voice
    $dtext = Get-Content -LiteralPath (Join-Path $ToolsPath 'vps-dev-instance.ps1') -Raw
    $lb = $dtext.IndexOf('$lines = @(')
    $le = if ($lb -ge 0) { $dtext.IndexOf("`n    )", $lb) } else { -1 }
    Yes 'the dev voice run file is in vps-dev-instance.ps1' ($lb -ge 0 -and $le -gt $lb)
    if ($node -and $lb -ge 0 -and $le -gt $lb) {
        $devVoice = Join-Path $tmp 'devvoice'
        $devVoicePort = 7989
        $psExe = $winps
        New-Item -ItemType Directory -Force -Path $devVoice | Out-Null
        Put (Join-Path $devVoice 'voice-server.js') ("console.log('stand-in dev voice up on ' + process.env.THORNSWOOD_VOICE_PORT);`n")
        Copy-Item -LiteralPath $roller -Destination (Join-Path $devVoice 'roll-log.ps1')
        $lines = $null
        . ([scriptblock]::Create($dtext.Substring($lb, $le - $lb + 6)))
        $run = Join-Path $devVoice 'run-dev-voice.cmd'
        [IO.File]::WriteAllLines($run, [string[]]$lines, (New-Object Text.ASCIIEncoding))
        $dlog = Join-Path $devVoice 'voice.log'
        Fill $dlog (4MB + 3)
        [void](RunCmd ('/c "' + $run + '"') $devVoice)
        Yes 'the dev voice run file rolls voice.log before node' ((Size ($dlog + '.1')) -eq (4MB + 3))
        Yes 'and dev voice writes to a fresh one' ((Count (Get $dlog) 'stand-in dev voice up on 7989') -eq 1)
    }
    Yes 'the dev copies leave the rolled logs of live behind' (
        ([regex]::Matches($dtext, '& robocopy [^\r\n]*/XF [^\r\n]*\*\.log\.\*')).Count -eq 2)

    # ================================================================== the bot
    $btext = Get-Content -LiteralPath (Join-Path $ToolsPath 'Install-Bot.ps1') -Raw
    $ra = $btext.IndexOf("`$run = @'")
    $rb = if ($ra -ge 0) { $btext.IndexOf("`n'@", $ra) } else { -1 }
    $runPs1 = if ($ra -ge 0 -and $rb -gt $ra) { $btext.Substring($ra, $rb - $ra) } else { '' }
    $wa = $runPs1.IndexOf('while (`$true) {')
    $wb = $runPs1.IndexOf('& cmd /c "python')
    Yes 'run.ps1 and its loop are in Install-Bot.ps1' ($wa -ge 0 -and $wb -gt $wa)
    if ($wa -ge 0 -and $wb -gt $wa) {
        $ahead = $runPs1.Substring($wa + 'while (`$true) {'.Length, $wb - $wa - 'while (`$true) {'.Length)
        Yes 'the loop rolls bot.log before it starts python' ($ahead -match 'roll-log\.ps1' -and $ahead -match 'bot\.log')

        # The lines ahead of python in the loop, as run.ps1 has them once the
        # outer here-string has been filled in, then a marker for python.
        $bot = Join-Path $tmp 'bot'
        New-Item -ItemType Directory -Force -Path $bot | Out-Null
        $pre = $ahead.Replace('$rootWin', $bot).Replace('`$', '$')
        $probe = Join-Path $bot 'probe.ps1'
        Put $probe ("`$ErrorActionPreference = 'Continue'`n" + $pre + "`n'reached python'`n")
        Copy-Item -LiteralPath $roller -Destination (Join-Path $bot 'roll-log.ps1')
        $blog = Join-Path $bot 'bot.log'
        Fill $blog (4MB + 1)
        $o = (& $winps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe 2>&1 | Out-String)
        Yes 'the loop rolls a bot.log past 4 MB' ((Size ($blog + '.1')) -eq (4MB + 1) -and -not (Test-Path -LiteralPath $blog))
        Yes 'and goes on to start python' ($o -match 'reached python')
        Remove-Item -LiteralPath (Join-Path $bot 'roll-log.ps1') -Force
        $o = (& $winps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe 2>&1 | Out-String)
        Yes 'with no roller it still starts python' ($o -match 'reached python')
    }
    Yes 'Install-Bot sends the roller up beside the bot' ($btext -match 'Join-Path \$Here ''Roll-Log\.ps1''' -and $btext -match '/roll-log\.ps1"')

    # What the bot said on the way up is read from a byte count taken before
    # the start. A roll makes the file shorter than that count, and without
    # allowing for it the installer reads nothing and says the bot has not
    # finished starting.
    $fresh = Get-BlockText $btext 'function Fresh {'
    Yes 'Fresh is in Install-Bot.ps1' ($null -ne $fresh)
    if ($fresh) {
        . ([scriptblock]::Create($fresh.Replace('`$', '$')))
        $log = Join-Path $tmp 'fresh.log'
        # Long, because a log only rolls at 4 MB, so whatever the new start
        # has written is always far shorter than the count taken before it.
        Put $log ((('old line ' + ('x' * 200)) + "`r`n") * 2)
        $before = (Get-Item -LiteralPath $log).Length
        [IO.File]::AppendAllText($log, "[thornswood-bot] watching 1 server`r`n")
        $got = @(Fresh) -join '|'
        Yes 'Fresh reads only what this start wrote' ($got -match 'watching 1 server' -and $got -notmatch 'old line')
        Put $log "[thornswood-bot] fresh after a roll`r`n"
        $got = @(Fresh) -join '|'
        Yes 'and all of a file a roll made shorter' ($got -match 'fresh after a roll')
    }
    Yes 'the code only restart reads a rolled bot.log from the start too' (
        ([regex]::Matches($btext, [regex]::Escape('if (`$fs.Length -lt `$from) { `$from = 0 }'))).Count -eq 2)

    # ===================================================== the server installer
    Yes 'Publish-Server sends the roller beside the installer' (
        (Get-Content -LiteralPath (Join-Path $ToolsPath 'Publish-Server.ps1') -Raw) -match 'scp \$rollLog "\$\{target\}:C:/Roll-Log\.ps1"')
    Yes 'the installer puts it in the server''s folder as roll-log.ps1' (
        $inst -match 'Join-Path \$here ''Roll-Log\.ps1''' -and $inst -match 'Join-Path \$Root ''roll-log\.ps1''')
    Yes 'the installer rolls server.log at install rather than deleting it' (
        $inst -notmatch 'Remove-Item -LiteralPath \$log\b' -and $inst -match '& \$roller -Path \$log -Force')

    # The folder it deletes on every publish held both logs. Run the real
    # set-aside and the real restore against a temp root.
    $aside = Get-BlockText $inst 'if (Test-Path -LiteralPath $Root) {'
    $back  = Get-BlockText $inst 'if ($logBak -and (Test-Path -LiteralPath $logBak)) {'
    Yes 'the installer sets the logs aside and puts them back' ($null -ne $aside -and $null -ne $back -and $aside -match 'logBak')
    if ($aside -and $back -and $aside -match 'logBak') {
        $Root = Join-Path $tmp 'srvroot'
        New-Item -ItemType Directory -Force -Path (Join-Path $Root 'dist_back') | Out-Null
        Put (Join-Path $Root 'server.log') 'LIVE LOG'
        Put (Join-Path $Root 'server.log.1') 'OLDER LOG'
        Put (Join-Path $Root 'thornswood.log') 'OURS'
        Put (Join-Path $Root 'thornswood.log.3') 'OURS OLDER'
        Put (Join-Path $Root 'dist_back\skymp5-server.js') 'program'
        $stamp = 'test'
        $logBak = $null
        $wasTemp = $env:TEMP
        $env:TEMP = $tmp
        try {
            . ([scriptblock]::Create($aside)) 6>$null
        } finally { $env:TEMP = $wasTemp }
        Yes 'the old folder is gone' (-not (Test-Path -LiteralPath $Root))
        Yes 'and every log went aside first' (
            (Get (Join-Path $logBak 'server.log')) -eq 'LIVE LOG' -and
            (Get (Join-Path $logBak 'server.log.1')) -eq 'OLDER LOG' -and
            (Get (Join-Path $logBak 'thornswood.log')) -eq 'OURS' -and
            (Get (Join-Path $logBak 'thornswood.log.3')) -eq 'OURS OLDER')
        Yes 'and no program file with them' (-not (Test-Path -LiteralPath (Join-Path $logBak 'skymp5-server.js')))

        # The unpack, then the restore.
        New-Item -ItemType Directory -Force -Path $Root | Out-Null
        Put (Join-Path $Root 'server-settings.json') '{}'
        . ([scriptblock]::Create($back)) 6>$null
        Yes 'the logs are back beside the new server' (
            (Get (Join-Path $Root 'server.log')) -eq 'LIVE LOG' -and
            (Get (Join-Path $Root 'server.log.1')) -eq 'OLDER LOG' -and
            (Get (Join-Path $Root 'thornswood.log')) -eq 'OURS' -and
            (Get (Join-Path $Root 'thornswood.log.3')) -eq 'OURS OLDER')
        Yes 'and the empty set-aside is tidied away' (-not (Test-Path -LiteralPath $logBak))
    }
}
catch {
    $script:fail++
    Write-Host ("FAIL  the harness stopped: {0}" -f $_.Exception.Message)
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
