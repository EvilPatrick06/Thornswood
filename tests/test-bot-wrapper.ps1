<#
  test-bot-wrapper.ps1

  The bot's wrapper on the VPS gives up after three quick exits in a row,
  instead of starting a bot that cannot start every fifteen seconds for ever.

  WHY THIS EXISTS. Entry 215 on the To Do List. run.ps1, which the scheduled
  task runs as SYSTEM, was a loop with no count and no ceiling:

      while ($true) { & cmd /c "python bot.py >> bot.log 2>&1"; Start-Sleep -Seconds 15 }

  bot.py raises SystemExit(1) when Discord rejects the token or refuses the
  connection because Server Members Intent is off, and both of those fail the
  same way every time. So a bot that could not start tried again four times a
  minute and nothing said a word until somebody opened bot.log.

  WHY IT CHECKS WHAT IS SENT. run.ps1 is a here-string inside a here-string.
  Install-Bot.ps1 sends the VPS a double quoted here-string, with every dollar
  sign meant for the far side escaped with a backtick, and that script writes
  run.ps1 out of a single quoted here-string inside it. A missed backtick
  parses perfectly here: the installer fills the variable in with whatever it
  holds on this machine, usually nothing, and the wrapper misbehaves on the box
  and nowhere else. So this checks, in order:

    1. the installer parses;
    2. the block that writes run.ps1 expands the installer's own two variables,
       rootWin and Task, and nothing else;
    3. that block, expanded exactly the way the installer expands it, parses;
    4. the run.ps1 inside it parses, and still runs the bot through cmd into
       bot.log;
    5. that run.ps1, run for real from a temp folder with python swapped for a
       stand-in that exits at once, stops after three fast exits, exits 0 and
       says so in bot.log in a line the installer reads back;
    6. a long run between quick ones starts the count again.

  For 5 and 6 the thirty second threshold and the fifteen second pause are
  shortened, so this takes seconds rather than minutes. Both numbers are
  checked by value first, so shortening them here cannot hide a change to
  what ships.

  Never connects to anything. Writes only under its own temp folder.
#>
[CmdletBinding()]
param([string]$InstallBotPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $InstallBotPath) { $InstallBotPath = Join-Path $Here '..\scripts\deploy\Install-Bot.ps1' }

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

# ---- 1. the installer parses ---------------------------------------------
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($InstallBotPath, [ref]$tokens, [ref]$errors)
Yes 'Install-Bot.ps1 parses' (@($errors).Count -eq 0)

# ---- 2. the block that writes run.ps1 fills in only what it should ---------
$blocks = @($ast.FindAll({ param($n)
    $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and
    $n.Extent.Text.Contains("\run.ps1'") -and $n.Extent.Text.Contains("@'")
}, $true))
Yes 'there is one block in Install-Bot.ps1 that writes run.ps1' ($blocks.Count -eq 1)
if ($blocks.Count -ne 1) { Done }
$block = $blocks[0]

$strays = @()
foreach ($x in $block.NestedExpressions) {
    $ok = ($x -is [System.Management.Automation.Language.VariableExpressionAst]) -and
          (@('rootWin', 'Task') -contains $x.VariablePath.UserPath)
    if (-not $ok) { $strays += ('line {0}: {1}' -f $x.Extent.StartLineNumber, $x.Extent.Text) }
}
Yes ("every dollar sign meant for the VPS is escaped; the installer fills in only rootWin and Task" +
     $(if ($strays.Count) { "`n      " + ($strays -join "`n      ") } else { '' })) ($strays.Count -eq 0)
# Expanding a block with anything else in it would run that on this machine,
# which is the one thing a harness that never touches anything must not do.
if ($strays.Count) { Done }

# ---- 3. what is sent parses ------------------------------------------------
$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-bot-wrapper-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $work
try {
    # The two names the block expands, set the way Install-Bot.ps1 sets them,
    # with the temp folder standing in for C:\Thornswood-Bot.
    $rootWin = $work
    $Task = 'Thornswood Bot'
    $sent = & ([scriptblock]::Create($block.Extent.Text))

    $t2 = $null; $e2 = $null
    $sentAst = [System.Management.Automation.Language.Parser]::ParseInput($sent, [ref]$t2, [ref]$e2)
    Yes 'the script Install-Bot.ps1 sends the VPS to keep the bot running parses' (@($e2).Count -eq 0)

    # ---- 4. the run.ps1 it writes parses, and runs the bot as before ---------
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
    Yes 'and writes that here-string to run.ps1' ($sent.Contains("WriteAllText('" + $work + "\run.ps1', `$run"))
    if ($null -eq $body) { Done }

    $t3 = $null; $e3 = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$t3, [ref]$e3)
    Yes 'run.ps1 parses' (@($e3).Count -eq 0)

    $botLine = '& cmd /c "python ""' + $work + '\bot.py"" >> ""' + $work + '\bot.log"" 2>&1"'
    Yes 'run.ps1 still runs python bot.py through cmd, into bot.log' ((Count $body $botLine) -eq 1)

    # The numbers that ship, by value, before they are shortened below.
    Yes 'a run under thirty seconds counts as a fast exit' ((Count $body '$fastSeconds = 30') -eq 1)
    Yes 'it still waits fifteen seconds between tries' ((Count $body 'Start-Sleep -Seconds 15') -eq 1)

    # ---- 5. run it, with a stand-in for python -------------------------------
    # A batch file, because cmd starts one in a few milliseconds and the fast
    # runs have to stay well under the shortened threshold. It counts its runs
    # in a file, prints a line into bot.log the way the bot would, and sleeps
    # for six seconds on any run that has a slow-N.txt marker beside it.
    $fake = Join-Path $work 'fake-python.cmd'
    Set-Content -LiteralPath $fake -Encoding ASCII -Value @(
        '@echo off',
        'set n=0',
        'if exist "%~dp0runs.txt" set /p n=<"%~dp0runs.txt"',
        'set /a n+=1',
        '>"%~dp0runs.txt" echo %n%',
        'echo [fake-bot] run %n%',
        'if exist "%~dp0slow-%n%.txt" ping -n 7 127.0.0.1 >nul',
        'exit /b 7'
    )
    # cmd /c is handed the stand-in unquoted, as it is handed python, so the
    # folder must not have a space in it.
    if ($work.Contains(' ')) {
        Write-Host "SKIP  the temp folder has a space in it, so the wrapper cannot be run here: $work"
        Done
    }

    $quick = $body.Replace('$fastSeconds = 30', '$fastSeconds = 3')
    $quick = $quick.Replace('Start-Sleep -Seconds 15', 'Start-Sleep -Milliseconds 100')
    $quick = $quick.Replace('"python ""', '"' + $fake + ' ""')
    Yes 'python was swapped for the stand-in' ((Count $quick $fake) -eq 1)

    # Written the way the installer writes it, UTF-8 without a mark, and run
    # the way the task runs it, by Windows PowerShell.
    [IO.File]::WriteAllText((Join-Path $work 'run.ps1'), $quick, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $work 'bot.env.json'), '{ "DISCORD_TOKEN": "not-a-real-token" }', (New-Object Text.UTF8Encoding($false)))

    function RunWrapper([int]$limit) {
        foreach ($f in @('runs.txt', 'bot.log')) {
            Remove-Item -LiteralPath (Join-Path $work $f) -Force -EA SilentlyContinue
        }
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $work 'run.ps1') + '"'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WorkingDirectory = $work
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $p = [Diagnostics.Process]::Start($psi)
        $stopped = $p.WaitForExit($limit * 1000)
        if (-not $stopped) {
            # Still looping, which is the fault this is here to catch. The
            # whole tree goes, cmd and the stand-in with it.
            $null = & taskkill /PID $p.Id /T /F 2>&1
            [void]$p.WaitForExit(10000)
        }
        $runs = 0
        $rf = Join-Path $work 'runs.txt'
        if (Test-Path -LiteralPath $rf) { [void][int]::TryParse(((Get-Content -LiteralPath $rf -Raw) + '').Trim(), [ref]$runs) }
        $log = ''
        $lf = Join-Path $work 'bot.log'
        if (Test-Path -LiteralPath $lf) { $log = [IO.File]::ReadAllText($lf) }
        $code = $null
        if ($stopped) { $code = $p.ExitCode }
        return @{ Stopped = $stopped; Code = $code; Runs = $runs; Log = $log; Seconds = [int]$clock.Elapsed.TotalSeconds }
    }

    # Three fast exits and nothing else.
    $r = RunWrapper 45
    Yes ('the wrapper stops by itself when the bot keeps exiting at once (took {0}s)' -f $r.Seconds) $r.Stopped
    Yes ('it started the bot three times and no more (it started it {0} times)' -f $r.Runs) ($r.Runs -eq 3)
    Yes ('it exits 0, which is not a failure for Task Scheduler to repeat (it exited {0})' -f $r.Code) ($r.Code -eq 0)
    Yes 'the bot''s own output still reaches bot.log' ((Count $r.Log '[fake-bot] run ') -eq 3)
    $gaveUp = @(($r.Log -split "\r?\n") | Where-Object { $_ -match 'three times running' })
    Yes 'it says in bot.log that it stopped, and with which exit code' (
        $gaveUp.Count -eq 1 -and $gaveUp[0].Contains('exit code 7'))
    # The same filter Install-Bot.ps1 uses to show what the bot said after a
    # start, so a failed install shows this line rather than going quiet.
    Yes 'the installer''s read-back after a start shows that line' (
        $gaveUp.Count -eq 1 -and $gaveUp[0] -match '^\s*\[(thornswood-bot|run)\]')

    # ---- 6. a long run starts the count again ---------------------------------
    # Fast, fast, slow, then three fast: six runs, not three.
    Set-Content -LiteralPath (Join-Path $work 'slow-3.txt') -Value 'slow' -Encoding ASCII
    $r = RunWrapper 60
    Yes 'with a long run in the middle, the wrapper still stops' $r.Stopped
    Yes ('a long run starts the count again: fast, fast, slow, fast, fast, fast is six runs (it made {0})' -f $r.Runs) ($r.Runs -eq 6)
    Yes 'and still exits 0' ($r.Code -eq 0)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}

Done
