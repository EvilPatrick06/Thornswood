<#
  test-2215-play-pressed-by.ps1

      pwsh -NoProfile -File .\tests\test-2215-play-pressed-by.ps1

  Issue #2215. The game has started again within three seconds of closing 17
  times since 20 September, and only the Play button reaches StartPlay from
  outside. Nothing recorded what pressed it, so this is the measurement: every
  press writes one line to launcher.log naming the input.

  WHAT IT CHECKS, in launcher\app\Shell.cs (text only):
    1. The Play button's Click handler logs PlayPressedBy() before anything else.
    2. PlayPressedBy names the mouse, the keyboard (with the last key down on
       the window) or no device, whether the window was active, and the seconds
       since the last game closed.
    3. The game's close sets gameClosedAt, and a window-level PreviewKeyDown
       keeps the last key.
#>
[CmdletBinding()]
param([string]$Repo)

$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = Split-Path -Parent $PSScriptRoot }
$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$shell = [IO.File]::ReadAllText((Join-Path $Repo 'launcher\app\Shell.cs'))

$click = [regex]::Match($shell, '(?s)btnPlay\.Click \+= delegate\s*\{(.*?)StartPlay\(\);').Groups[1].Value
Yes 'the Play button logs what pressed it before it does anything' (
    $click.Contains('LogOnly(PlayPressedBy());') -and
    $click.IndexOf('LogOnly(PlayPressedBy());') -lt $click.IndexOf('if (playing)'))

$at = $shell.IndexOf('static string PlayPressedBy()')
$fn = if ($at -ge 0) { $shell.Substring($at, [Math]::Min(2200, $shell.Length - $at)) } else { '' }
Yes 'PlayPressedBy is in Shell.cs' ($at -ge 0)
Yes 'it names the mouse, the keyboard with its last key, or no device' (
    $fn.Contains('dev is MouseDevice') -and $fn.Contains('dev is KeyboardDevice') -and
    $fn.Contains('lastKeyDown') -and $fn.Contains('no input device'))
Yes 'it says whether the window was active and how long since the game closed' (
    $fn.Contains('win.IsActive') -and $fn.Contains('gameClosedAt'))
Yes 'the game''s close sets gameClosedAt' ($shell -match 'gameClosedAt = DateTime\.Now;\s*\r?\n\s*Log\("Game closed after')
Yes 'a window-level PreviewKeyDown keeps the last key' (
    $shell.Contains('win.PreviewKeyDown += delegate (object s, KeyEventArgs e)') -and $shell.Contains('lastKeyDownAt = DateTime.Now;'))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
