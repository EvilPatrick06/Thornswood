<#
  test-setup-in-window.ps1

      pwsh -NoProfile -File .\tests\test-setup-in-window.ps1

  The install runs inside the setup window, with no console of its own.

  Issue #889, Patrick on 28 September: "the installer fix where it doesnt do
  the separate powershell/cmd window and all actually runs in the installer
  itself". Thornswood-Setup.exe unpacked its payload and then started
  Setup.bat with the shell, which opened a black console running
  Setup-Thornswood.ps1, and that console was the install. Now Bootstrap.cs
  starts the same PowerShell on the same script with the same arguments,
  hidden, reads what it prints into its own window and a log file, answers
  the script's one question with a box of its own, and takes the exit code as
  the answer. Setup.bat and Install.bat stay in the payload for a person
  running it by hand.

  What this holds the files to:
    - Bootstrap's start info has no console window and no shell, reads the
      script's output and error, and passes what Setup.bat passes (-File the
      script, -MovePayload, -Root the folder) from the payload's folder, with
      -NonInteractive to PowerShell and to the script. Compiled out of
      Bootstrap.cs with the compiler the build runs (Add-LauncherType,
      tests\Launcher-Csc.ps1, #2821) and run, against Setup.bat run by cmd,
      on a stand-in script that writes down what it was given;
    - it picks the PowerShell Setup.bat picks;
    - Work starts no Setup.bat any more, decides on the exit code, and names
      the log file when it fails; the ASK line gets a box;
    - no Read-Host or pause in Setup-Thornswood.ps1 is reachable with
      -NonInteractive, read from the script's syntax tree, and the script
      with -NonInteractive stops by itself on a missing payload instead of
      waiting for Enter;
    - its Ask reads the answer the window writes back, and an unexpected
      Read-Host stops with a reason;
    - Setup.bat still parses and calls the script, and Install.bat still
      runs it the interactive way.

  Everything it makes is under a temp folder it removes. Off Windows it does
  not run: the build's compiler, cmd.exe, Setup.bat and Windows PowerShell
  are only there.
#>
[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Root) { $Root = Split-Path -Parent $Here }
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#2821)
if (-not $OnWindows) { Write-Host 'NOT RUN  the setup window starting PowerShell hidden happens only on Windows: Bootstrap.cs compiled with the Roslyn csc of Visual Studio''s Build Tools, Setup.bat under cmd.exe and the script under Windows PowerShell'; exit 0 }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$bsPath    = Join-Path $Root 'installer\setup\Bootstrap.cs'
$setupPath = Join-Path $Root 'installer\Setup-Thornswood.ps1'
$batPath   = Join-Path $Root 'installer\Setup.bat'
$instPath  = Join-Path $Root 'installer\Install.bat'
$bs = [IO.File]::ReadAllText($bsPath)

# A C# method by its head and a brace match that steps over strings and line
# comments, the same reader test-installer-own-payload.ps1 uses.
function Get-Method([string]$text, [string]$head) {
    $at = $text.IndexOf($head)
    if ($at -lt 0) { return '' }
    $i = $text.IndexOf('{', $at)
    if ($i -lt 0) { return '' }
    $depth = 0
    while ($i -lt $text.Length) {
        $c = $text[$i]
        if ($c -eq '"' -or $c -eq "'") {
            $q = $c
            $i++
            while ($i -lt $text.Length -and $text[$i] -ne $q) {
                if ($text[$i] -eq '\') { $i++ }
                $i++
            }
        }
        elseif ($c -eq '/' -and $i + 1 -lt $text.Length -and $text[$i + 1] -eq '/') {
            $nl = $text.IndexOf("`n", $i)
            if ($nl -lt 0) { return '' }
            $i = $nl
        }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return $text.Substring($at, $i - $at + 1) }
        }
        $i++
    }
    return ''
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-889-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# Runs a start info to the end with stdin shut, and gives back what it printed.
function Invoke-Psi($psi, [int]$secs = 90) {
    $p = [Diagnostics.Process]::Start($psi)
    if ($psi.RedirectStandardInput) { $p.StandardInput.Close() }
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    $done = $p.WaitForExit($secs * 1000)
    if (-not $done) { try { $p.Kill() } catch { } }
    return [pscustomobject]@{ Done = $done; Code = $(if ($done) { $p.ExitCode } else { -1 }); Out = $o.Result; Err = $e.Result }
}

try {
    # ---- 1. Bootstrap's start info, compiled and looked at --------------------
    $psExe = Get-Method $bs 'static string PowerShellExe('
    $start = Get-Method $bs 'static ProcessStartInfo SetupStartInfo('
    Yes 'Bootstrap has PowerShellExe and SetupStartInfo' ($psExe.Length -gt 0 -and $start.Length -gt 0)
    $null = Add-LauncherType -Source ((@'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
public static class Ts889 {
'@ + "public $psExe`npublic $start`n}"))

    $payload = Join-Path $tmp 'Thornswood-setup'
    New-Item -ItemType Directory -Force -Path $payload | Out-Null
    $script = Join-Path $payload 'Setup-Thornswood.ps1'
    $root = 'D:\Games Here\Thornswood'
    $psi = [Ts889]::SetupStartInfo('powershell.exe', $script, $root, $false, '')
    Yes 'no console window' ($psi.CreateNoWindow)
    Yes 'and no shell execute' (-not $psi.UseShellExecute)
    Yes 'its output and its errors come back to the window' ($psi.RedirectStandardOutput -and $psi.RedirectStandardError)
    Yes 'and it has an input for the answer to its question' ($psi.RedirectStandardInput)
    Yes 'it runs from the payload folder, as Setup.bat does with cd /d %~dp0' ($psi.WorkingDirectory -eq $payload)
    $a = $psi.Arguments
    Yes 'it passes Setup.bat''s -File, -MovePayload and -Root' (
        $a.Contains('-NoProfile') -and $a.Contains('-ExecutionPolicy Bypass') -and
        $a.Contains('-File "' + $script + '" -MovePayload -Root "' + $root + '"'))
    $iFile = $a.IndexOf('-File')
    Yes 'PowerShell itself is told -NonInteractive, before -File' ($a.IndexOf('-NonInteractive') -ge 0 -and $a.IndexOf('-NonInteractive') -lt $iFile)
    Yes 'and so is the script, after it' ($a.LastIndexOf('-NonInteractive') -gt $iFile)
    Yes 'a root with a trailing backslash does not escape its closing quote' (
        ([Ts889]::SetupStartInfo('powershell.exe', $script, 'E:\', $false, '')).Arguments.Contains('-Root "E:"'))

    # ---- 2. run: Setup.bat by cmd against the start info, same stand-in -------
    # A stand-in script that writes down how it was called and whether it had
    # a console window anybody could see.
    $stand = @'
param([string]$Root = '(default)', [switch]$MovePayload, [switch]$NonInteractive)
Add-Type -Name W -Namespace Ts889Probe -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
"@
$h = [Ts889Probe.W]::GetConsoleWindow()
$seen = ($h -ne [IntPtr]::Zero) -and [Ts889Probe.W]::IsWindowVisible($h)
Write-Host ('ROOT=' + $Root)
Write-Host ('MOVE=' + [bool]$MovePayload)
Write-Host ('NI=' + [bool]$NonInteractive)
Write-Host ('EDITION=' + $PSVersionTable.PSEdition)
Write-Host ('CWD=' + (Get-Location).Path)
Write-Host ('VISIBLE=' + $seen)
exit 7
'@
    [IO.File]::WriteAllText($script, $stand, (New-Object Text.UTF8Encoding($false)))
    Copy-Item -LiteralPath $batPath -Destination $payload
    function Field([string]$text, [string]$name) {
        $m = [regex]::Match($text, '(?m)^' + $name + '=(.*)$')
        if ($m.Success) { return $m.Groups[1].Value.Trim() } else { return '' }
    }

    $bat = New-Object Diagnostics.ProcessStartInfo('cmd.exe')
    $bat.Arguments = '/d /c ""' + (Join-Path $payload 'Setup.bat') + '" "' + $root + '""'
    $bat.UseShellExecute = $false; $bat.CreateNoWindow = $true
    $bat.RedirectStandardOutput = $true; $bat.RedirectStandardError = $true
    $byBat = Invoke-Psi $bat
    Yes 'Setup.bat runs to the end' ($byBat.Done)
    Yes 'Setup.bat hands the script''s exit code back' ($byBat.Code -eq 7)
    Yes 'Setup.bat passes the folder as -Root' ((Field $byBat.Out 'ROOT') -eq $root)
    Yes 'and -MovePayload' ((Field $byBat.Out 'MOVE') -eq 'True')
    Yes 'and not -NonInteractive, so by hand it still asks at the keyboard' ((Field $byBat.Out 'NI') -eq 'False')

    $bat.Arguments = '/d /c ""' + (Join-Path $payload 'Setup.bat') + '""'
    $bare = Invoke-Psi $bat
    Yes 'Setup.bat with no folder, as by hand, leaves the script''s own default' ((Field $bare.Out 'ROOT') -eq '(default)' -and (Field $bare.Out 'MOVE') -eq 'True')

    $mine = Invoke-Psi ([Ts889]::SetupStartInfo([Ts889]::PowerShellExe(), $script, $root, $false, ''))
    Yes 'Bootstrap''s start info runs to the end' ($mine.Done)
    Yes 'and the exit code comes back as the script left it' ($mine.Code -eq 7)
    Yes 'the script gets the same -Root as from Setup.bat' ((Field $mine.Out 'ROOT') -eq (Field $byBat.Out 'ROOT'))
    Yes 'and the same -MovePayload' ((Field $mine.Out 'MOVE') -eq (Field $byBat.Out 'MOVE'))
    Yes 'and -NonInteractive' ((Field $mine.Out 'NI') -eq 'True')
    Yes 'from the same folder' ((Field $mine.Out 'CWD') -eq (Field $byBat.Out 'CWD'))
    Yes ('the same PowerShell Setup.bat picks (' + (Field $byBat.Out 'EDITION') + ')') (
        (Field $mine.Out 'EDITION') -eq (Field $byBat.Out 'EDITION') -and (Field $mine.Out 'EDITION') -ne '')
    Yes 'with no console window anybody can see' ((Field $mine.Out 'VISIBLE') -eq 'False')
    Yes 'and what Write-Host prints arrives on the output Bootstrap reads' ($mine.Out -match '(?m)^ROOT=')

    # ---- 3. Work: the script, not Setup.bat, and the exit code decides --------
    $work = Get-Method $bs 'static void Work('
    Yes 'Work no longer starts Setup.bat' ($work.Length -gt 0 -and -not $work.Contains('"Setup.bat"'))
    # Except the browser on the terms, privacy or rules page (issue #1009),
    # which is the shell's job; OpenPage takes only the site's own addresses.
    $shellUse = @([regex]::Matches($bs, 'UseShellExecute = true'))
    $openPage = Get-Method $bs 'static void OpenPage('
    Yes 'nothing in Bootstrap starts anything through the shell but the site''s own pages' (
        $shellUse.Count -eq 1 -and $openPage.Contains('UseShellExecute = true') -and
        $openPage.Contains('if (!url.StartsWith(Site + "/", StringComparison.OrdinalIgnoreCase)) return;'))
    Yes 'Work runs the payload''s Setup-Thornswood.ps1 through SetupStartInfo' (
        $work.Contains('Path.Combine(temp, "Setup-Thornswood.ps1")') -and
        $work.Contains('RunSetupScript(SetupStartInfo(PowerShellExe(), script, installRoot, makeOwnGame, vortexGame)'))
    Yes 'the window closes only on exit code 0' ($work -match '(?s)if \(code == 0\)\s*\{[^}]*win\.Close\(\)')
    Yes 'otherwise it says why and where the log is' ($work.Contains('saved in " + log'))
    $run = Get-Method $bs 'static int RunSetupScript('
    Yes 'the script''s lines are read as they come' ($run.Contains('BeginOutputReadLine') -and $run.Contains('BeginErrorReadLine'))
    Yes 'and the wait has a timeout, so a launcher holding the output cannot hang it' ($run.Contains('WaitForExit(500)'))
    Yes 'and the log file is written' ($run.Contains('new StreamWriter(log'))
    $line = Get-Method $bs 'static void Line('
    Yes 'an ASK line gets a box and the answer goes back on the input' (
        $line.Contains('"THORNSWOOD-ASK "') -and $line.Contains('AskForScript(') -and $line.Contains('StandardInput.WriteLine'))
    $askBox = Get-Method $bs 'static bool AskForScript('
    Yes 'the box is asked on the window thread, and a failure to ask is Cancel' (
        $askBox.Contains('win.Dispatcher.Invoke') -and $askBox.Contains('catch { return false; }'))
    Yes 'the window cannot be closed half way through the install' ($bs -match '(?s)if \(installing\)\s*\{.{0,600}?e\.Cancel = true;')
    Yes 'the log box is in the window' ($bs.Contains('x:Name=""TxtLog""'))

    # ---- 4. Setup-Thornswood.ps1: nothing waits on a keyboard ----------------
    $tokens = $null; $errs = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($setupPath, [ref]$tokens, [ref]$errs)
    Yes 'Setup-Thornswood.ps1 parses' ($errs.Count -eq 0)
    Yes 'it takes -NonInteractive' (@($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'NonInteractive' }).Count -eq 1)

    # A Read-Host is safe when the NonInteractive run cannot get to it: inside
    # an "if (-not $NonInteractive)" clause, or in the else of an
    # "if ($NonInteractive)", or the stop inside the stand-in Read-Host itself.
    function Test-Guarded($node) {
        $child = $node
        $p = $node.Parent
        while ($p) {
            if ($p -is [Management.Automation.Language.IfStatementAst]) {
                foreach ($cl in $p.Clauses) {
                    $cond = $cl.Item1.Extent.Text.Trim()
                    if ([object]::ReferenceEquals($cl.Item2, $child) -and $cond -match '^-not \$NonInteractive$') { return $true }
                }
                if ($p.ElseClause -and [object]::ReferenceEquals($p.ElseClause, $child) -and
                    $p.Clauses[0].Item1.Extent.Text.Trim() -eq '$NonInteractive') { return $true }
            }
            $child = $p
            $p = $p.Parent
        }
        return $false
    }
    $reads = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Read-Host' }, $true))
    $open = @($reads | Where-Object { -not (Test-Guarded $_) })
    Yes ('every one of the ' + $reads.Count + ' Read-Host calls is off the -NonInteractive path') ($reads.Count -ge 4 -and $open.Count -eq 0)
    foreach ($r in $open) { Write-Host ('      open at line ' + $r.Extent.StartLineNumber + ': ' + $r.Extent.Text) }
    $pauses = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and
        @('pause', 'choice', 'timeout') -contains $n.GetCommandName() }, $true))
    Yes 'no pause, choice or timeout anywhere in it' ($pauses.Count -eq 0)
    Yes 'and no $Host.UI prompt or ReadKey' (-not ([IO.File]::ReadAllText($setupPath) -match '\$Host\.UI\.(Prompt|ReadLine)|ReadKey'))
    $shadow = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-Host' }, $true))
    Yes 'with -NonInteractive an unexpected Read-Host is replaced by a stop' ($shadow.Count -eq 1 -and $shadow[0].Body.Extent.Text.Contains('Die ('))

    # Run it. A copy with no payload beside it stops at its first check, before
    # it looks for Steam or touches anything, so this is safe on any machine.
    $bare2 = Join-Path $tmp 'bare'
    New-Item -ItemType Directory -Force -Path $bare2 | Out-Null
    Copy-Item -LiteralPath $setupPath -Destination $bare2
    $real = Invoke-Psi ([Ts889]::SetupStartInfo([Ts889]::PowerShellExe(), (Join-Path $bare2 'Setup-Thornswood.ps1'), (Join-Path $tmp 'root'), $false, '')) 60
    Yes 'the real script with -NonInteractive ends by itself on a stop' ($real.Done)
    Yes 'with exit code 1' ($real.Code -eq 1)
    Yes 'and the STOP line the window shows' ($real.Out -match "(?m)^STOP\. The 'payload' folder is missing")
    Yes 'having written nothing to the install folder' (-not (Test-Path -LiteralPath (Join-Path $tmp 'root')))

    # Ask and the stand-in Read-Host, lifted out of the script and run in a
    # PowerShell of their own with an answer on standard input.
    $fns = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and @('Die', 'Ask') -contains $n.Name }, $false))
    Yes 'Die and Ask are in the script' ($fns.Count -eq 2)
    $probe = Join-Path $tmp 'ask-probe.ps1'
    $body = '$NonInteractive = $true' + "`n" + (($fns | ForEach-Object { $_.Extent.Text }) -join "`n") + "`n" +
            $shadow[0].Extent.Text + "`n" +
            'if ($args[0] -eq ''read'') { Read-Host ''an unexpected question''; exit 0 }' + "`n" +
            'if (Ask ''Question?'') { Write-Host ''GO ON'' } else { Write-Host ''STOPPED'' }'
    [IO.File]::WriteAllText($probe, $body, (New-Object Text.UTF8Encoding($false)))
    function Invoke-Probe([string]$feed, [string]$mode = 'ask') {
        $p = New-Object Diagnostics.ProcessStartInfo('powershell.exe')
        $p.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $probe + '" ' + $mode
        $p.UseShellExecute = $false; $p.CreateNoWindow = $true
        $p.RedirectStandardInput = $true; $p.RedirectStandardOutput = $true; $p.RedirectStandardError = $true
        $proc = [Diagnostics.Process]::Start($p)
        if ($null -ne $feed) { $proc.StandardInput.WriteLine($feed) }
        $proc.StandardInput.Close()
        $o = $proc.StandardOutput.ReadToEndAsync(); $e = $proc.StandardError.ReadToEndAsync()
        $done = $proc.WaitForExit(30000)
        if (-not $done) { try { $proc.Kill() } catch { } }
        return [pscustomobject]@{ Done = $done; Code = $(if ($done) { $proc.ExitCode } else { -1 }); Out = $o.Result }
    }
    $ok = Invoke-Probe 'ok'
    Yes 'Ask prints the ASK line the window turns into a box' ($ok.Out -match '(?m)^THORNSWOOD-ASK Question\?')
    Yes 'OK written back carries on' ($ok.Out -match 'GO ON')
    Yes 'no written back stops' ((Invoke-Probe 'no').Out -match 'STOPPED')
    Yes 'nothing written back, the input shut, stops rather than waits' ((Invoke-Probe $null).Out -match 'STOPPED')
    $rh = Invoke-Probe $null 'read'
    Yes 'an unexpected Read-Host stops at once, exit 1' ($rh.Done -and $rh.Code -eq 1)
    Yes 'and says it was a question the setup window cannot ask' ($rh.Out -match 'STOP\. Setup stopped at a question the setup window cannot ask: an unexpected question')

    # ---- 5. by hand -----------------------------------------------------------
    $batText = [IO.File]::ReadAllText($batPath)
    Yes 'Setup.bat still calls the script with -MovePayload and -Root' (
        $batText.Contains('-File "%~dp0Setup-Thornswood.ps1" -MovePayload -Root "%ROOT%"'))
    $instText = [IO.File]::ReadAllText($instPath)
    Yes 'Install.bat still runs the script the interactive way and pauses on a failure' (
        $instText.Contains('-File "%~dp0Setup-Thornswood.ps1"') -and -not $instText.Contains('NonInteractive') -and
        $instText.Contains('if errorlevel 1 pause'))
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
