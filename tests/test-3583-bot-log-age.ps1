<#
  test-3583-bot-log-age.ps1

      pwsh -NoProfile -File .\tests\test-3583-bot-log-age.ps1

  Every copy of bot.log goes by age, whatever it is called and wherever the
  install found it.

  Issue #3583. The privacy page says no line of bot.log is kept past 90 days.
  The service's hourly pass (BotService.cs, RollingLog.Age) deleted by age
  only bot.log.1 to bot.log.<keep>, the copies its own roll makes. A copy
  somebody renamed by hand to keep, such as bot.log.20260916-1535.old, which
  sat on the box from September (#1184), was moved into data by the install
  and then kept for ever. And when data already held a copy by the same name,
  the install left the one beside the code, where the service cannot delete,
  and nothing aged it either. The two rules, "a log is never removed" (#1184)
  and "no bot.log line past 90 days" (#2166), were never put together.

  What this holds the files to:
    1. Move-ThornswoodBotRecords (Bot-Service.ps1), run on a scratch bot
       folder: a log beside the code whose name data already holds goes into
       data as <name>.beside-code, then .beside-code-2, with its last write
       kept, so nothing of the bot's log is left beside the code;
    2. RollingLog.Age, compiled with the .NET Framework compiler the box
       builds the service with and run on a scratch data folder: a renamed
       copy and a numbered copy past copySeconds both go, a newer renamed copy
       and a newer numbered one stay, the live bot.log stays, a file whose
       name only starts like the log's (bot.logger.txt) is not touched, and
       bot.log says how many went. Off Windows that part says SKIP: the
       compiler is a part of Windows;
    3. the text: Age reads every copy through Copies(), not only the
       numbered ones.

  It fails on the code before #3583: part 1 finds the copy still beside the
  code, part 2 finds the renamed copy kept, part 3 finds the numbered loop.
  Everything it makes is under a scratch folder it removes.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
. (Join-Path $PSScriptRoot 'Windows.ps1')

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$svcLib = Join-Path $repo 'scripts\vps\Bot-Service.ps1'
$svcSrc = Join-Path $repo 'scripts\vps\BotService.cs'
. $svcLib

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-3583-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $tmp
try {
    # ---- 1. the install moves every log of the bot's into data --------------
    $root = Join-Path $tmp 'bot'
    $data = Join-Path $root 'data'
    $null = New-Item -ItemType Directory -Force -Path $data
    $old = [DateTime]::UtcNow.AddDays(-40)
    foreach ($n in 'bot.log.1', 'bot.log.20260916-1535.old') {
        [IO.File]::WriteAllText((Join-Path $root $n), 'beside the code ' + $n)
        [IO.File]::SetLastWriteTimeUtc((Join-Path $root $n), $old)
        [IO.File]::WriteAllText((Join-Path $data $n), 'in data ' + $n)
    }
    # The first name is taken twice over, so the second free name is used.
    [IO.File]::WriteAllText((Join-Path $data 'bot.log.1.beside-code'), 'an earlier move')
    $said = @(Move-ThornswoodBotRecords $root)
    Yes 'no log of the bot''s is left beside the code, where the service cannot delete it' (
        -not (Test-Path -LiteralPath (Join-Path $root 'bot.log.1')) -and -not (Test-Path -LiteralPath (Join-Path $root 'bot.log.20260916-1535.old')))
    $moved = Join-Path $data 'bot.log.20260916-1535.old.beside-code'
    Yes 'a renamed log whose name data holds goes into data as <name>.beside-code' (
        (Test-Path -LiteralPath $moved) -and ([IO.File]::ReadAllText($moved) -eq 'beside the code bot.log.20260916-1535.old'))
    Yes '  keeping its last write, so the service ages it from when it stopped being written' (
        (Test-Path -LiteralPath $moved) -and [Math]::Abs(([IO.File]::GetLastWriteTimeUtc($moved) - $old).TotalSeconds) -lt 2)
    Yes '  and when that name is taken too, <name>.beside-code-2' (
        (Test-Path -LiteralPath (Join-Path $data 'bot.log.1.beside-code-2')) -and
        ([IO.File]::ReadAllText((Join-Path $data 'bot.log.1.beside-code')) -eq 'an earlier move'))
    Yes '  and data''s own copies are untouched' (
        ([IO.File]::ReadAllText((Join-Path $data 'bot.log.1')) -eq 'in data bot.log.1') -and
        ([IO.File]::ReadAllText((Join-Path $data 'bot.log.20260916-1535.old')) -eq 'in data bot.log.20260916-1535.old'))
    Yes '  and it says where each went' ((($said -join "`n") -match 'moved bot\.log\.1 into .* as bot\.log\.1\.beside-code-2: data already has its own bot\.log\.1') -and
        -not (($said -join "`n") -match '(?m)^left '))

    # ---- 2. the service's age pass reads every copy ------------------------
    if (-not $OnWindows) {
        Write-Host 'SKIP  2. RollingLog.Age compiled and run: the .NET Framework compiler the box builds the service with is a part of Windows'
    }
    else {
        $csc = Get-WindowsPath 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        if (-not (Test-Path -LiteralPath $csc)) { $csc = Get-WindowsPath 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
        $driver = Join-Path $tmp 'AgeDriver.cs'
        [IO.File]::WriteAllText($driver, @'
public static class AgeDriver
{
    // args: the log's path, copySeconds. Opens the log as the service does,
    // runs the age pass once, and closes it.
    public static int Main(string[] args)
    {
        Thornswood.RollingLog log = new Thornswood.RollingLog(args[0], 4L * 1024 * 1024, 5, 30);
        log.AgeBy(0, double.Parse(args[1], System.Globalization.CultureInfo.InvariantCulture), 3600);
        log.Dispose();
        return 0;
    }
}
'@)
        $exe = Join-Path $tmp 'AgeDriver.exe'
        $old2 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $out = @(& $csc /nologo /target:exe /main:AgeDriver ('/out:' + $exe) /r:System.ServiceProcess.dll /r:System.Web.Extensions.dll $svcSrc $driver 2>&1 | ForEach-Object { "$_" })
        $ErrorActionPreference = $old2
        Yes ('BotService.cs and the driver build with the .NET Framework compiler' + $(if ($LASTEXITCODE -ne 0) { ': ' + ($out -join ' | ') } else { '' })) ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $exe))
        if (Test-Path -LiteralPath $exe) {
            $logDir = Join-Path $tmp 'data'
            $null = New-Item -ItemType Directory -Force -Path $logDir
            $log = Join-Path $logDir 'bot.log'
            $files = [ordered]@{
                'bot.log'                            = 0
                'bot.log.2'                          = -2
                'bot.log.3'                          = 0
                'bot.log.20260916-1535.old'          = -2
                'bot.log.20260916-1535.old.beside-code' = -2
                'bot.log.kept-by-hand'               = 0
                'bot.logger.txt'                     = -2
            }
            foreach ($k in $files.Keys) {
                $p = Join-Path $logDir $k
                [IO.File]::WriteAllText($p, $k)
                [IO.File]::SetLastWriteTimeUtc($p, [DateTime]::UtcNow.AddHours($files[$k]))
            }
            $old2 = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            $null = & $exe $log 3600 2>&1
            $code = $LASTEXITCODE
            $ErrorActionPreference = $old2
            Yes ('the age pass ran (exit {0})' -f $code) ($code -eq 0)
            $there = { param($n) Test-Path -LiteralPath (Join-Path $logDir $n) }
            Yes 'a copy renamed by hand, past copySeconds, is deleted (#3583)' (-not (& $there 'bot.log.20260916-1535.old'))
            Yes '  and so is one the install moved in as .beside-code' (-not (& $there 'bot.log.20260916-1535.old.beside-code'))
            Yes '  and a numbered copy past it, as before (#2166)' (-not (& $there 'bot.log.2'))
            Yes 'a newer numbered copy and a newer renamed one stay' ((& $there 'bot.log.3') -and (& $there 'bot.log.kept-by-hand'))
            Yes 'the live bot.log stays' (& $there 'bot.log')
            Yes 'a file whose name only starts like the log''s is not the log''s, and stays' (& $there 'bot.logger.txt')
            Yes 'bot.log says three copies went' ([IO.File]::ReadAllText($log) -match '\[run\] by age: 3 bot\.log copies past ')
        }
    }

    # ---- 3. the text ---------------------------------------------------------
    $cs = [IO.File]::ReadAllText($svcSrc)
    $age = [regex]::Match($cs, '(?s)public void Age\(\)\s*\{.*?\n        \}')
    Yes 'Age reads every copy through Copies(), not only the numbered ones' (
        $age.Success -and $age.Value.Contains('foreach (string f in Copies())') -and -not $age.Value.Contains('path + "." + i'))
    $lib = [IO.File]::ReadAllText($svcLib)
    Yes 'Bot-Service.ps1 says every copy goes once its last write is 59 days old, and no longer that a log is never removed' (
        $lib.Contains('there the service deletes every bot.log copy, whatever its name, once') -and -not $lib.Contains('# bot.log.<anything> somebody renamed by hand to keep it. A log is never'))
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
