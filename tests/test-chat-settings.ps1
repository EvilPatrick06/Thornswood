<#
  test-chat-settings.ps1

      pwsh -NoProfile -File .\tests\test-chat-settings.ps1

  The launcher's Chat and needs settings write Thornswood.ini the way the game
  plugin reads it: ChatFade=5, 15, 20 or 0 (10 is the default and is not
  written), and NeedsBars=0 when the bars are off (on is no line at all).

  Patrick, 24 September: "add an option in the launcher settings to make it
  5, 10, 15, 20 or permeant", and "add an option in settings to hide the needs
  menu on the screen so it doesnt show and they can do /needs to find it all".

  HOW. The real ChatFade and NeedsBars classes are lifted out of
  launcher\app\Display.cs by brace match and compiled with the compiler the
  launcher builds with (tests\Launcher-Csc.ps1), beside a Paths that points at
  a temp folder and a Swallow that records. tests\test-chat-fade.js checks the other half, that
  the plugin reads these lines. Read only apart from its own temp folder.
#>
[CmdletBinding()]
param([string]$AppPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $AppPath) { $AppPath = Join-Path $Here 'launcher\app' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail -gt 0) { exit 1 }
    exit 0
}

$text = [IO.File]::ReadAllText((Join-Path $AppPath 'Display.cs'))

# From the start of the line the signature is on to the brace that closes it,
# stepping over strings, characters and comments.
function Get-Member([string]$all, [string]$signature) {
    $at = $all.IndexOf($signature)
    if ($at -lt 0) { return $null }
    $lineStart = $all.LastIndexOf("`n", $at) + 1
    $open = $all.IndexOf('{', $at + $signature.Length)
    if ($open -lt 0) { return $null }
    $depth = 0
    $i = $open
    while ($i -lt $all.Length) {
        $c = $all[$i]
        if ($c -eq '@' -and $i + 1 -lt $all.Length -and $all[$i + 1] -eq '"') {
            $i += 2
            while ($i -lt $all.Length) {
                if ($all[$i] -eq '"') { if ($i + 1 -lt $all.Length -and $all[$i + 1] -eq '"') { $i += 2; continue }; break }
                $i++
            }
        }
        elseif ($c -eq '"' -or $c -eq "'") {
            $q = $c; $i++
            while ($i -lt $all.Length -and $all[$i] -ne $q) { if ($all[$i] -eq '\') { $i++ }; $i++ }
        }
        elseif ($c -eq '/' -and $i + 1 -lt $all.Length -and $all[$i + 1] -eq '/') {
            $i = $all.IndexOf("`n", $i); if ($i -lt 0) { return $null }
        }
        elseif ($c -eq '/' -and $i + 1 -lt $all.Length -and $all[$i + 1] -eq '*') {
            $i = $all.IndexOf('*/', $i + 2); if ($i -lt 0) { return $null }; $i++
        }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return $all.Substring($lineStart, $i + 1 - $lineStart) }
        }
        $i++
    }
    return $null
}

$chat = Get-Member $text 'static class ChatFade'
$needs = Get-Member $text 'static class NeedsBars'
Yes 'Display.cs has ChatFade' ($null -ne $chat)
Yes 'Display.cs has NeedsBars' ($null -ne $needs)
if ($null -eq $chat -or $null -eq $needs) { Done }

$probe = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;

namespace Probe
{
    public static class Paths { public static string Game = ""; }
    public static class Swallow
    {
        public static int Count;
        public static void Note(string where, Exception e) { Count++; }
    }
__LIFTED__
    public static class Drive
    {
        public static int Get() { return ChatFade.Get(); }
        public static bool Set(int s) { return ChatFade.Set(s); }
        public static bool Shown() { return NeedsBars.Shown(); }
        public static bool SetShown(bool b) { return NeedsBars.Set(b); }
        public static int[] Choices() { return ChatFade.Choices; }
        public static void Game(string g) { Paths.Game = g; }
    }
}
'@
$probe = $probe.Replace('__LIFTED__', $chat + "`n" + $needs)

Yes 'the compiler the build runs is on this machine (the Roslyn csc beside MSBuild)' (Test-Path -LiteralPath $LauncherCsc)
if (-not (Test-Path -LiteralPath $LauncherCsc)) { Done }

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-chat-settings-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $work
try {
    $cs = Join-Path $work 'Probe.cs'
    [IO.File]::WriteAllText($cs, $probe)
    $dll = Join-Path $work 'Probe.dll'
    $out = & $LauncherCsc /nologo /target:library "/out:$dll" $cs 2>&1
    $built = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $dll)
    Yes 'ChatFade and NeedsBars compile with the compiler the build runs' $built
    if (-not $built) { $out | ForEach-Object { Write-Host "      $_" }; Done }

    $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
    $D = $asm.GetType('Probe.Drive', $true)
    # PowerShell wraps paths in a PSObject; the compiled side wants what is inside.
    function Call([string]$name, [object[]]$argv) {
        $plain = New-Object 'object[]' $argv.Count
        for ($k = 0; $k -lt $argv.Count; $k++) {
            $a = $argv[$k]
            if ($a -is [Management.Automation.PSObject]) { $a = $a.PSObject.BaseObject }
            $plain[$k] = $a
        }
        return $D.GetMethod($name).Invoke($null, $plain)
    }

    $game = Join-Path $work 'Game'
    $null = New-Item -ItemType Directory -Force -Path $game
    Call 'Game' @($game) | Out-Null
    $ini = Join-Path $game 'Data\SKSE\Plugins\Thornswood.ini'
    function IniText { if (Test-Path -LiteralPath $ini) { return [IO.File]::ReadAllText($ini) } ; return $null }

    Yes 'the choices are 5, 10, 15, 20 and Never, in that order' (((Call 'Choices' @()) -join ',') -eq '5,10,15,20,0')
    Yes 'no Thornswood.ini: ten seconds' ((Call 'Get' @()) -eq 10)
    Yes 'no Thornswood.ini: the bars are shown' ([bool](Call 'Shown' @()))
    Yes 'choosing ten with no file writes nothing' ([bool](Call 'Set' @(10)) -and $null -eq (IniText))
    Yes 'showing the bars with no file writes nothing' ([bool](Call 'SetShown' @($true)) -and $null -eq (IniText))

    Yes 'choosing Never with no file makes the file' ([bool](Call 'Set' @(0)) -and (IniText) -match '(?m)^ChatFade=0\r?$')
    Yes 'and it reads back as Never' ((Call 'Get' @()) -eq 0)

    [IO.File]::WriteAllText($ini, "PushToTalk=47`r`nFov=90`r`nChatFade=0`r`n")
    Yes 'choosing 15 replaces the line and keeps the rest' ([bool](Call 'Set' @(15)) -and (IniText) -match 'PushToTalk=47' -and (IniText) -match 'Fov=90' -and ([regex]::Matches((IniText), 'ChatFade=').Count -eq 1) -and (IniText) -match 'ChatFade=15')
    Yes 'and reads back as 15' ((Call 'Get' @()) -eq 15)
    Yes 'choosing ten takes the line out' ([bool](Call 'Set' @(10)) -and (IniText) -notmatch 'ChatFade' -and (IniText) -match 'PushToTalk=47')
    Yes 'a number that is not a choice is refused and changes nothing' (-not [bool](Call 'Set' @(7)) -and (IniText) -notmatch 'ChatFade')
    [IO.File]::WriteAllText($ini, "ChatFade=7`r`n")
    Yes 'a hand-edited 7 reads as ten' ((Call 'Get' @()) -eq 10)
    [IO.File]::WriteAllText($ini, "chatfade = 20`r`n")
    Yes 'the key reads in any case, with spaces' ((Call 'Get' @()) -eq 20)

    [IO.File]::WriteAllText($ini, "PushToTalk=47`r`n")
    Yes 'hiding the bars writes NeedsBars=0 and keeps the rest' ([bool](Call 'SetShown' @($false)) -and (IniText) -match '(?m)^NeedsBars=0\r?$' -and (IniText) -match 'PushToTalk=47')
    Yes 'and they read back as hidden' (-not [bool](Call 'Shown' @()))
    Yes 'showing them takes the line out' ([bool](Call 'SetShown' @($true)) -and (IniText) -notmatch 'NeedsBars' -and [bool](Call 'Shown' @()))
    [IO.File]::WriteAllText($ini, "NeedsBars=1`r`n")
    Yes 'NeedsBars=1 reads as shown' ([bool](Call 'Shown' @()))
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Done
