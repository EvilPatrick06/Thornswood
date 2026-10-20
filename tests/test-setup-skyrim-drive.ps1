<#
  test-setup-skyrim-drive.ps1

  The setup program starts on the drive Skyrim is on, and says so when it is
  asked for another one.

  Thornswood runs from its own game folder, built out of the Steam copy of
  Skyrim mostly as hard links, and a hard link cannot cross a drive. So an
  install on a drive other than Skyrim's is an install that cannot play:
  OwnGame.WhyNot names it and the launcher stops there. Until this, the setup
  window offered every fixed drive with nothing saying which one that was, and
  C:\Thornswood by default, so somebody who keeps games on D: found out after
  the whole install and the way out was a reinstall. Issue #473.

  What this holds Bootstrap.cs to:
    - it finds Skyrim the way the launcher does: Steam's own folder out of the
      registry, then every path in config\libraryfolders.vdf, then
      steamapps\common\Skyrim Special Edition with SkyrimSE.exe in it;
    - the same strings as launcher\app\Steam.cs, so the two stay in step;
    - the install folder starts on that drive, and C:\Thornswood is only the
      fallback when no Steam copy is found;
    - a drive that is not Skyrim's is said on screen, in the colour the window
      uses for something that will not work, and again before anything is
      written;
    - that second one asks and does not refuse. Whether the launcher may build
      the folder some other way on a second drive is Patrick and Djinn's call
      in #dev, not the installer's to take by blocking it;
    - the intro no longer describes the old shape, installing into the Steam
      copy of Skyrim in place.

  Read only.
#>
[CmdletBinding()]
param([string]$BootstrapPath, [string]$SteamPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# This test lives in tests\; repo root is one level up.
$repoRoot = Split-Path -Parent $Here
if (-not $BootstrapPath) { $BootstrapPath = Join-Path $repoRoot 'installer\setup\Bootstrap.cs' }
if (-not $SteamPath)     { $SteamPath     = Join-Path $repoRoot 'launcher\app\Steam.cs' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$bs = [IO.File]::ReadAllText($BootstrapPath)

# ---- 1. it looks where the launcher looks ----------------------------------
Yes 'the stub reads Steam''s own folder out of the registry' (
    $bs.Contains('using Microsoft.Win32;') -and
    $bs.Contains('Registry.CurrentUser.OpenSubKey') -and
    $bs.Contains("@""Software\Valve\Steam"""))
Yes 'and falls back to the 32 bit machine key, as the launcher does' (
    $bs.Contains("@""SOFTWARE\Wow6432Node\Valve\Steam""") -and $bs.Contains("k.GetValue(""InstallPath"")"))
Yes 'it walks every library in config\libraryfolders.vdf' (
    $bs.Contains('config\\libraryfolders.vdf') -and
    $bs.Contains('static List<string> SteamLibraries()'))
Yes 'and unescapes the separator Valve doubles in that file' ($bs.Contains('parts[1].Replace("\\\\", "\\")'))
Yes 'the game is found by its executable, not by the folder an uninstall leaves behind' (
    $bs.Contains('steamapps\\common\\Skyrim Special Edition') -and $bs.Contains('"SkyrimSE.exe"'))

# The same two strings in the launcher, so a change to one is visible as a
# difference from the other rather than as two installs that disagree.
if (Test-Path -LiteralPath $SteamPath) {
    $st = [IO.File]::ReadAllText($SteamPath)
    Yes 'the launcher looks under the same library file' ($st.Contains('config\\libraryfolders.vdf'))
    Yes 'and under the same game folder' ($st.Contains('steamapps\\common\\Skyrim Special Edition'))
} else {
    Yes 'launcher\app\Steam.cs is where this expects it' $false
}

# ---- 2. the picker starts on that drive ------------------------------------
Yes 'the install folder starts on Skyrim''s drive' (
    $bs.Contains('string sky = SkyrimDrive();') -and
    $bs.Contains('installRoot = Path.Combine(sky, "Thornswood").TrimEnd(''\\'');'))
Yes 'C:\Thornswood is only the fallback when no Steam copy is found' (
    $bs.Contains('static string installRoot = @"C:\Thornswood";'))
Yes 'and the drive button says which drive Skyrim is on' ($bs.Contains('mark.Text = "Skyrim is here";'))

# ---- 3. another drive is said, clearly, twice ------------------------------
$say = [regex]::Match($bs, '(?s)static void SaySkyrim\(string root\).*?\n        \}')
Yes 'there is a line under the drive buttons about Skyrim''s drive' ($say.Success)
if ($say.Success) {
    $body = $say.Value
    Yes 'it says Thornswood has to share Skyrim''s drive' ($body.Contains("Thornswood has to share Skyrim's drive"))
    Yes 'and why: a hard link cannot cross a drive' (
        $body.Contains('hard links') -and $body.Contains('cannot cross a drive'))
    Yes 'and what that costs: the launcher will not let you play' ($body.Contains('will not let you play'))
    Yes 'in the colour the window uses for something that will not work' ($body.Contains('B("Bad")'))
    Yes 'and it says so too when no Steam copy of Skyrim was found at all' (
        $body.Contains('was not found on this PC'))
}
Yes 'the line is drawn from the window' ($bs.Contains('SaySkyrim(root);') -and $bs.Contains('TxtSkyrim'))

# Said again on Install, before anything is written, because the line under
# the buttons can be scrolled past.
$iSky = $bs.IndexOf('if (sky.Length > 0 && !SameDrive(sky, root))')
$iPay = $bs.IndexOf('Payload check = FindPayload();')
Yes 'Install asks again when the drive is not Skyrim''s' ($iSky -gt 0)
Yes 'and asks before anything is unpacked or downloaded' ($iSky -gt 0 -and $iPay -gt $iSky)
Yes 'it asks rather than refusing, so nobody is stopped by a decision not taken yet' (
    $iSky -gt 0 -and $bs.IndexOf('MessageBoxButton.YesNo', $iSky) -gt $iSky)

# ---- 4. the intro matches the own game folder shape ------------------------
$intro = [regex]::Match($bs, 'x:Name=""TxtBody""(?s).*?/>')
Yes 'the intro text is where this expects it' ($intro.Success)
if ($intro.Success) {
    $t = $intro.Value
    Yes 'the intro says Thornswood runs from its own game folder' ($t.Contains('own game folder'))
    Yes 'and that it does not install into the Steam copy' ($t.Contains('does not install into the Skyrim you already have on Steam'))
    Yes 'and that it goes on the same drive as Skyrim' ($t.Contains('same drive as Skyrim'))
    Yes 'the old shape is gone from it' (-not $t.Contains('does not make a second copy'))
}

# ---- 5. the folder the picker says is the folder it makes (#852) -----------
# Measured under #497: an older Bootstrap told the customer a folder of the
# old name is made while Path.Combine actually made Thornswood. The
# rename on main already fixed the string; this holds the two sides together
# so they cannot drift apart again.
Yes 'the folder picker says a folder called Thornswood is made' (
    $bs.Contains('A folder called Thornswood is made inside whatever you pick.'))
Yes 'and does not still give the old name for that folder' (
    -not ($bs -match 'folder called Skyrim\s*Together'))
Yes 'drive buttons Path.Combine the chosen drive with Thornswood' (
    $bs.Contains('Path.Combine(captured.Name, "Thornswood")'))
Yes 'Browse appends Thornswood when the pick is not already that folder' (
    $bs.Contains('Path.Combine(chosen, "Thornswood")') -and
    $bs.Contains('EndsWith("Thornswood", StringComparison.OrdinalIgnoreCase)'))

# ---- 6. the house words ----------------------------------------------------
Yes 'no em dash anywhere in the setup program' ($bs.IndexOf([char]0x2014) -lt 0)
Yes 'and not the word this project does not use' ($bs -notmatch '(?i)\bplayers?\b')

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
