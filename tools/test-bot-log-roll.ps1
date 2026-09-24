<#
  test-bot-log-roll.ps1

  The bot's wrapper on the VPS rolls bot.log before a start once it passes
  4 MB, keeping five, and the two things that read the log back still find
  the lines they are looking for.

  WHY THIS EXISTS. Entry 249 on the To Do List: "a log that never rotates".
  run.ps1 runs the bot as

      & cmd /c "python bot.py >> bot.log 2>&1"

  and nothing ever moved or trimmed bot.log. cmd holds the file open for the
  whole run, so it cannot be rolled during one; it can between runs, which is
  when run.ps1 now does it. That cmd redirection stays exactly as it is: piping
  through PowerShell instead is what left the log unreadable past a point.

  So this checks, in order:

    1. the installer parses, and the block that writes run.ps1 fills in only
       rootWin and Task, the same check test-bot-wrapper.ps1 makes before it
       expands anything;
    2. run.ps1 still runs the bot through cmd into bot.log, and rolls at 4 MB
       keeping five, by value;
    3. run for real from a temp folder, with python swapped for a stand-in and
       the size shortened: a bot.log over the limit becomes bot.log.1, .1 to .4
       move up one, the fifth goes, and the new bot.log opens with a line the
       installer reads back;
    4. a bot.log under the limit is left where it is;
    5. a bot.log held open, the way the installer's own read-back holds it,
       is not rolled, no older log is lost however many starts that takes, and
       the bot still starts and writes;
    6. the installer's read-back after a start, in the full run and in
       -CodeOnly, shows this start when the log was rolled under it, and only
       what is past the old length when it was not;
    7. Show-BotLog.ps1 reads bot.log.1 before bot.log, so the lines just
       before a roll are not hidden by it.

  Never connects to anything. Writes only under its own temp folder.
#>
[CmdletBinding()]
param([string]$InstallBotPath, [string]$ShowBotLogPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $InstallBotPath) { $InstallBotPath = Join-Path $Here 'Install-Bot.ps1' }
if (-not $ShowBotLogPath) { $ShowBotLogPath = Join-Path $Here 'Show-BotLog.ps1' }

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
function Count([string]$text, [string]$what) {
    return ([regex]::Matches($text, [regex]::Escape($what))).Count
}
# Expanding a block runs whatever it nests, on this machine. So a block is
# expanded only when every name in it is one of the few this harness sets.
function Strays($block, [string[]]$names) {
    $out = @()
    foreach ($x in $block.NestedExpressions) {
        $ok = ($x -is [System.Management.Automation.Language.VariableExpressionAst]) -and
              ($names -contains $x.VariablePath.UserPath)
        if (-not $ok) { $out += ('line {0}: {1}' -f $x.Extent.StartLineNumber, $x.Extent.Text) }
    }
    return $out
}
function Blocks($ast, [string[]]$all) {
    return @($ast.FindAll({ param($n)
        if (-not ($n -is [System.Management.Automation.Language.ExpandableStringExpressionAst])) { return $false }
        foreach ($w in $all) { if (-not $n.Extent.Text.Contains($w)) { return $false } }
        return $true
    }.GetNewClosure(), $true))
}

# ---- 1. the installer parses, and the runner block is safe to expand -------
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($InstallBotPath, [ref]$tokens, [ref]$errors)
Yes 'Install-Bot.ps1 parses' (@($errors).Count -eq 0)

$runner = @(Blocks $ast @("\run.ps1'", "@'"))
Yes 'there is one block in Install-Bot.ps1 that writes run.ps1' ($runner.Count -eq 1)
$codeOnly = @(Blocks $ast @('Stop-ScheduledTask', 'IO.FileStream'))
Yes 'there is one -CodeOnly restart block that reads the log back' ($codeOnly.Count -eq 1)
if ($runner.Count -ne 1 -or $codeOnly.Count -ne 1) { Done }

$s1 = @(Strays $runner[0] @('rootWin', 'Task'))
$s2 = @(Strays $codeOnly[0] @('rootWin', 'Task'))
Yes ('both blocks fill in only rootWin and Task' +
     $(if ($s1.Count + $s2.Count) { "`n      " + (($s1 + $s2) -join "`n      ") } else { '' })) (($s1.Count + $s2.Count) -eq 0)
if ($s1.Count + $s2.Count) { Done }

$tokens = $null; $errors = $null
$showAst = [System.Management.Automation.Language.Parser]::ParseFile($ShowBotLogPath, [ref]$tokens, [ref]$errors)
Yes 'Show-BotLog.ps1 parses' (@($errors).Count -eq 0)
$showAssign = @($showAst.FindAll({ param($n)
    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
    $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
    $n.Left.VariablePath.UserPath -eq 'script' -and
    $n.Right.Expression -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
}, $true))
Yes 'Show-BotLog.ps1 builds one script to send' ($showAssign.Count -eq 1)
if ($showAssign.Count -ne 1) { Done }
$showBlock = $showAssign[0].Right.Expression
$s3 = @(Strays $showBlock @('rootWin', 'filter', 'Lines'))
Yes 'and it fills in only rootWin, filter and Lines' ($s3.Count -eq 0)
if ($s3.Count) { Done }

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-bot-roll-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $work
$holder = $null
try {
    # The names the blocks expand, set the way the two scripts set them, with
    # the temp folder standing in for C:\Thornswood-Bot.
    $rootWin = $work
    $Task = 'Thornswood Bot'
    $sent = & ([scriptblock]::Create($runner[0].Extent.Text))
    $sentCodeOnly = & ([scriptblock]::Create($codeOnly[0].Extent.Text))

    $t2 = $null; $e2 = $null
    $sentAst = [System.Management.Automation.Language.Parser]::ParseInput($sent, [ref]$t2, [ref]$e2)
    Yes 'the script Install-Bot.ps1 sends to keep the bot running parses' (@($e2).Count -eq 0)
    $t2 = $null; $e2 = $null
    $codeOnlyAst = [System.Management.Automation.Language.Parser]::ParseInput($sentCodeOnly, [ref]$t2, [ref]$e2)
    Yes 'the script -CodeOnly sends parses' (@($e2).Count -eq 0)

    # ---- 2. run.ps1, by text and by value ------------------------------------
    $assign = @($sentAst.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $n.Left.VariablePath.UserPath -eq 'run'
    }, $true))
    $body = $null
    if ($assign.Count -eq 1 -and $assign[0].Right.Expression -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        $body = $assign[0].Right.Expression.Value
    }
    Yes 'the script sent carries run.ps1 as a single quoted here-string' ($null -ne $body)
    if ($null -eq $body) { Done }
    $t3 = $null; $e3 = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$t3, [ref]$e3)
    Yes 'run.ps1 parses' (@($e3).Count -eq 0)

    $botLine = '& cmd /c "python ""' + $work + '\bot.py"" >> ""' + $work + '\bot.log"" 2>&1"'
    Yes 'run.ps1 still runs python bot.py through cmd, into bot.log, with no pipeline in front of it' ((Count $body $botLine) -eq 1)
    Yes 'it rolls at 4 MB' ((Count $body '$logBytes = 4MB') -eq 1)
    Yes 'and keeps five' ((Count $body '$logKeep = 5') -eq 1)

    # ---- the stand-in, and the wrapper run for real ----------------------------
    # A batch file, as in test-bot-wrapper.ps1: it counts its runs, prints a
    # line into bot.log the way the bot would, and exits at once, so the
    # wrapper gives up after three starts by itself.
    $fake = Join-Path $work 'fake-python.cmd'
    Set-Content -LiteralPath $fake -Encoding ASCII -Value @(
        '@echo off',
        'set n=0',
        'if exist "%~dp0runs.txt" set /p n=<"%~dp0runs.txt"',
        'set /a n+=1',
        '>"%~dp0runs.txt" echo %n%',
        'echo [fake-bot] run %n%',
        'exit /b 7'
    )
    if ($work.Contains(' ')) {
        Write-Host "SKIP  the temp folder has a space in it, so the wrapper cannot be run here: $work"
        Done
    }

    # Under a kilobyte instead of 4 MB, so the files stay small, and every
    # pause between starts cut to a tenth of a second. Both shipping numbers
    # were checked above, before this.
    $limit = 1000
    $quick = $body.Replace('$logBytes = 4MB', '$logBytes = ' + $limit)
    $quick = [regex]::Replace($quick, 'Start-Sleep -Seconds [^\r\n]+', 'Start-Sleep -Milliseconds 100')
    $quick = $quick.Replace('"python ""', '"' + $fake + ' ""')
    Yes 'python was swapped for the stand-in' ((Count $quick $fake) -eq 1)
    [IO.File]::WriteAllText((Join-Path $work 'run.ps1'), $quick, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $work 'bot.env.json'), '{ "DISCORD_TOKEN": "not-a-real-token" }', (New-Object Text.UTF8Encoding($false)))

    $log = Join-Path $work 'bot.log'
    function LogPath([int]$n) { if ($n -eq 0) { return $log } return ($log + '.' + $n) }
    function LogText([int]$n) {
        $p = LogPath $n
        if (-not (Test-Path -LiteralPath $p)) { return $null }
        return [IO.File]::ReadAllText($p)
    }
    function Seed([int]$n, [string]$text) {
        [IO.File]::WriteAllText((LogPath $n), $text, (New-Object Text.UTF8Encoding($false)))
    }
    function Clean {
        foreach ($n in 0..7) { Remove-Item -LiteralPath (LogPath $n) -Force -EA SilentlyContinue }
        Remove-Item -LiteralPath (Join-Path $work 'runs.txt') -Force -EA SilentlyContinue
    }
    # Run the way the task runs it, by Windows PowerShell.
    function RunWrapper([int]$seconds) {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $work 'run.ps1') + '"'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = $work
        $p = [Diagnostics.Process]::Start($psi)
        $stopped = $p.WaitForExit($seconds * 1000)
        if (-not $stopped) {
            $null = & taskkill /PID $p.Id /T /F 2>&1
            [void]$p.WaitForExit(10000)
        }
        $runs = 0
        $rf = Join-Path $work 'runs.txt'
        if (Test-Path -LiteralPath $rf) { [void][int]::TryParse(((Get-Content -LiteralPath $rf -Raw) + '').Trim(), [ref]$runs) }
        return @{ Stopped = $stopped; Runs = $runs }
    }
    $readBack = '^\s*\[(thornswood-bot|run)\]'
    $current = '[thornswood-bot] SEED-CURRENT, the run before this one' + "`r`n" + ('x' * ($limit + 200)) + "`r`n" +
               '[thornswood-bot] the reason the last run ended' + "`r`n"

    # ---- 3. over the limit, it rolls --------------------------------------------
    Clean
    Seed 0 $current
    foreach ($n in 1..5) { Seed $n ("SEED-$n`r`n") }
    $before = (New-Object IO.FileInfo($log)).Length
    $r = RunWrapper 45
    Yes 'the wrapper still stops by itself' $r.Stopped
    Yes ('and the bot started three times (it started {0})' -f $r.Runs) ($r.Runs -eq 3)
    Yes 'bot.log over the limit became bot.log.1, exactly as it was' ((LogText 1) -eq $current)
    $moved = $true
    foreach ($n in 1..4) { if ((LogText ($n + 1)) -ne "SEED-$n`r`n") { $moved = $false } }
    Yes 'bot.log.1 to .4 each moved up one' $moved
    Yes 'the fifth went, and there is no sixth' ($null -eq (LogText 6))
    $all = ''
    foreach ($n in 0..6) { $all += [string](LogText $n) }
    Yes 'nothing that was bot.log.5 is left anywhere' ((Count $all 'SEED-5') -eq 0)

    $rolled = [string](LogText 0)
    $lines = @(($rolled -replace "^\uFEFF", '') -split "\r?\n" | Where-Object { $_ })
    Yes 'the new bot.log has this start in it: three runs and the line that gave up' (
        (Count $rolled '[fake-bot] run ') -eq 3 -and (Count $rolled 'three times running') -eq 1)
    Yes 'it rolled once, not once per start' ((Count $rolled 'was rolled to bot.log.1') -eq 1)
    Yes 'its first line says it was rolled, before the bot said anything' (
        $lines.Count -gt 1 -and $lines[0].Contains('was rolled to bot.log.1') -and $lines[1].Contains('[fake-bot] run 1'))

    # ---- 6a. the installer's read-back, after that roll ---------------------------
    # Fresh from the full run, lifted out of the script it sends and called
    # with the log's length from before the start, as the installer calls it.
    $fresh = @($sentAst.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Fresh'
    }, $true))
    Yes 'the full run reads the log back through one function, Fresh' ($fresh.Count -eq 1)
    $codeOnlyRead = @($codeOnlyAst.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.TryStatementAst] -and $n.Extent.Text.Contains('IO.FileStream')
    }, $true))
    Yes '-CodeOnly reads it back in one try block' ($codeOnlyRead.Count -eq 1)
    if ($fresh.Count -ne 1 -or $codeOnlyRead.Count -ne 1) { Done }
    . ([scriptblock]::Create($fresh[0].Extent.Text))
    $readCodeOnly = [scriptblock]::Create($codeOnlyRead[0].Extent.Text)

    Yes ('the log is shorter than it was before the start ({0} bytes, was {1})' -f $rolled.Length, $before) (
        (New-Object IO.FileInfo($log)).Length -lt $before)
    $got = @(Fresh)
    Yes ('after a roll, the full run''s read-back shows this start ({0} lines)' -f $got.Count) (
        (Count ($got -join "`n") '[fake-bot] run ') -eq 3)
    Yes 'and nothing from before the roll' ((Count ($got -join "`n") 'SEED-CURRENT') -eq 0)
    # The filter the installer prints what the bot said through.
    $said = @($got | Where-Object { $_ -match $readBack })
    Yes 'and the line that says it rolled comes through the filter the installer prints with' (
        (Count ($said -join "`n") 'was rolled to bot.log.1') -eq 1)
    $got = @(& $readCodeOnly)
    Yes ('after a roll, -CodeOnly''s read-back shows this start too ({0} lines)' -f $got.Count) (
        (Count ($got -join "`n") '[fake-bot] run ') -eq 3 -and (Count ($got -join "`n") 'nothing new') -eq 0)

    # The same on its own, whatever rolled it: a log shorter than the length
    # taken before the start is all this start's. Before this change both
    # read-backs waited for it to grow past the old length, which after a roll
    # at 4 MB would be never, and said nothing had been written.
    Seed 0 ('[thornswood-bot] watching 1 server' + "`r`n")
    $before = 5000
    Yes 'the full run''s read-back reads a log shorter than it was from the start' (
        @(@(Fresh) | Where-Object { $_ -match 'watching \d+ server' }).Count -eq 1)
    Yes 'and so does -CodeOnly''s' (
        @(@(& $readCodeOnly) | Where-Object { $_ -match 'watching \d+ server' }).Count -eq 1)

    # ---- 4. under the limit, it stays -----------------------------------------------
    Clean
    $small = '[thornswood-bot] an earlier run that left a small log' + "`r`n"
    Seed 0 $small
    $before = (New-Object IO.FileInfo($log)).Length
    $r = RunWrapper 45
    Yes 'under the limit, the wrapper still runs the bot three times' ($r.Stopped -and $r.Runs -eq 3)
    Yes 'bot.log was not rolled' ($null -eq (LogText 1))
    $kept = [string](LogText 0)
    Yes 'and this start was appended to it' ($kept.StartsWith($small) -and (Count $kept '[fake-bot] run ') -eq 3)
    Yes 'with no line saying it rolled' ((Count $kept 'was rolled') -eq 0)

    # ---- 6b. the read-back when nothing rolled -----------------------------------------
    $got = @(Fresh)
    Yes 'the full run''s read-back shows this start' ((Count ($got -join "`n") '[fake-bot] run ') -eq 3)
    Yes 'and none of the earlier run in front of it' ((Count ($got -join "`n") 'an earlier run') -eq 0)
    $got = @(& $readCodeOnly)
    Yes '-CodeOnly''s read-back the same' (
        (Count ($got -join "`n") '[fake-bot] run ') -eq 3 -and (Count ($got -join "`n") 'an earlier run') -eq 0)

    # ---- 5. held open, nothing moves and nothing is lost -------------------------------
    # Held the way the installer's read-back holds it, and the way a copy of
    # the bot started by hand would still have it. Three starts, so a roll
    # that shifted the older files before finding bot.log would not move has
    # three chances to lose one.
    Clean
    Seed 0 $current
    foreach ($n in 1..5) { Seed $n ("SEED-$n`r`n") }
    $holder = New-Object IO.FileStream($log, 'Open', 'Read', 'ReadWrite')
    $r = RunWrapper 45
    $holder.Dispose(); $holder = $null
    Yes ('with bot.log held open, the bot still started three times (it started {0})' -f $r.Runs) ($r.Stopped -and $r.Runs -eq 3)
    $kept = [string](LogText 0)
    Yes 'bot.log was not rolled, and this start was appended to it' (
        $kept.StartsWith($current) -and (Count $kept '[fake-bot] run ') -eq 3)
    $same = $true
    foreach ($n in 1..5) { if ((LogText $n) -ne "SEED-$n`r`n") { $same = $false } }
    Yes 'bot.log.1 to .5 are all still there, unmoved' $same
    Yes 'and there is no sixth' ($null -eq (LogText 6))

    # ---- 7. Show-BotLog reads bot.log.1 first ----------------------------------------
    # Its script, expanded the way it expands it, run the way the VPS runs it:
    # Windows PowerShell, handed the script as an encoded command. It looks at
    # the process list, which reads and changes nothing.
    function ShowBotLog {
        $filter = $readBack
        $Lines = 40
        $s = & ([scriptblock]::Create($showBlock.Extent.Text))
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($s))
        return @(& powershell.exe -NoProfile -EncodedCommand $enc 2>&1 | ForEach-Object { "$_" })
    }
    # Up to three reads before it counts as a failure, and up to three
    # seconds for a delete. Once in about twenty runs on 24 September the
    # first read came back without bot.log.1 and the harness stopped before
    # its count, which fits the delete below being refused while something,
    # most likely a virus scanner, still had a file written a moment ago. It
    # did not happen again. Code that does not read bot.log.1 fails all three
    # reads.
    function ShowBotLogUntil([string]$want) {
        $out = @()
        foreach ($try in 1..3) {
            $out = @(ShowBotLog)
            if (@($out | Where-Object { $_.Contains($want) }).Count) { break }
            Start-Sleep -Milliseconds 300
        }
        return $out
    }
    Clean
    Seed 1 ('[thornswood-bot] the reason the last run ended' + "`r`n" + 'discord.py noise' + "`r`n")
    Seed 0 ('[run] bot.log passed its size limit and was rolled to bot.log.1, so what came before this line is in there.' + "`r`n" +
            '[thornswood-bot] up again' + "`r`n")
    $out = @(ShowBotLogUntil 'the reason the last run ended')
    $a = [array]::FindIndex([string[]]$out, [Predicate[string]]{ param($l) $l.Contains('the reason the last run ended') })
    $b = [array]::FindIndex([string[]]$out, [Predicate[string]]{ param($l) $l.Contains('up again') })
    Yes 'Show-BotLog shows the lines in bot.log.1' ($a -ge 0)
    Yes 'and the ones in bot.log, after them' ($b -gt $a -and $a -ge 0)
    Yes 'and still leaves out what the bot did not say itself' (@($out | Where-Object { $_.Contains('discord.py noise') }).Count -eq 0)
    if ($a -lt 0 -or $b -le $a) { $out | ForEach-Object { Write-Host "      $_" } }
    foreach ($try in 1..10) {
        Remove-Item -LiteralPath (LogPath 1) -Force -EA SilentlyContinue
        if (-not (Test-Path -LiteralPath (LogPath 1))) { break }
        Start-Sleep -Milliseconds 300
    }
    $out = @(ShowBotLogUntil 'up again')
    Yes 'with no bot.log.1, it shows bot.log as before' (
        @($out | Where-Object { $_.Contains('up again') }).Count -eq 1 -and
        @($out | Where-Object { $_ -match 'cannot find|does not exist' }).Count -eq 0)
}
finally {
    if ($holder) { $holder.Dispose() }
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}

Done
