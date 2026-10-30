<#
  test-shortcut-icons.ps1

      powershell -NoProfile -File .\tests\test-shortcut-icons.ps1

  Issue #887: the desktop and Start menu shortcuts lost their icons after a
  rebuild into the install folder, a Ship, and some self-updates, and only
  Settings, refresh icons brought them back.

  Two things caused it. Install-Launcher.ps1 named the icon file after the
  repository's app.ico and deleted every other icon-*.ico, while the launcher
  names it after the art inside the exe (app-dev.ico in the dev build, and
  whatever art the CI-built exe of a main Ship carries). So an install deleted
  the file the Start menu and pinned shortcuts name, and Windows drew them
  blank. The launcher then wrote the file back, but those shortcuts' IconLocation
  still read right, so Icons.Ensure changed nothing and never told Explorer;
  the only forced redraw (#816) keyed on Thornswood.exe.old, which a rebuild or
  a Ship never leaves.

  Part 1 compiles the real Icons.cs with the compiler the launcher is built
  with (tests\Launcher-Csc.ps1) against stand-ins for Paths, Art and Swallow,
  and drives its Due / Remember / IconFile through reflection in a scratch
  folder. Ensure itself is never called: it walks the real Desktop and Start
  menu and talks to Explorer.

  Part 2 runs the real Install-Launcher.ps1 on a scratch root (which touches
  nothing outside its own folder, no Desktop, no Explorer) with an exe whose
  app.ico is not the repository's, and checks the icon file is named after the
  exe's art.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
. (Join-Path $PSScriptRoot 'Windows.ps1')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 } else { exit 0 }
}
function Hash8([byte[]]$b) {
    $sha = [Security.Cryptography.SHA256]::Create()
    ([BitConverter]::ToString($sha.ComputeHash($b), 0, 4)).Replace('-', '').ToLower()
}

if (-not $OnWindows) { Write-Host 'SKIP  the launcher''s code, compiled and run: its compiler is the Roslyn csc that comes with Visual Studio''s Build Tools, which only Windows has'; Done }
Yes 'the compiler the build runs is on this machine (the Roslyn csc beside MSBuild)' (Test-Path -LiteralPath $LauncherCsc)
if (-not (Test-Path -LiteralPath $LauncherCsc)) { Done }

$appIco = Join-Path $Repo 'launcher\app.ico'
$devIco = Join-Path $Repo 'launcher\app-dev.ico'
$iconsCs = Join-Path $Repo 'launcher\app\Icons.cs'
$mainHash = Hash8 ([IO.File]::ReadAllBytes($appIco))
$devHash = Hash8 ([IO.File]::ReadAllBytes($devIco))
Yes 'the two artworks hash to different names (otherwise part 2 proves nothing)' ($mainHash -ne $devHash)

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-icons-887-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    # ---- 1. the real Icons.cs ----------------------------------------------------
    $stub = @'
using System;
namespace Thornswood
{
    public static class Paths { public static string Root, LauncherDir, ProfileDir; }
    public static class Art { public static bool Dev; }
    public static class Swallow { public static void Note(string where, Exception ex) { } }
}
'@
    $stubCs = Join-Path $work 'Stubs.cs'
    Set-Content -LiteralPath $stubCs -Value $stub -Encoding ASCII
    $dll = Join-Path $work 'IconsUnderTest.dll'
    $out = & $LauncherCsc /nologo /target:library "/langversion:$LauncherLangVersion" "/out:$dll" "/resource:$appIco,app.ico" "/resource:$devIco,app-dev.ico" $iconsCs $stubCs 2>&1
    Yes 'Icons.cs compiles with the launcher''s compiler' ($LASTEXITCODE -eq 0)
    if ($LASTEXITCODE -ne 0) { $out | ForEach-Object { Write-Host "  $_" }; Done }

    $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
    $icons = $asm.GetType('Thornswood.Icons')
    $paths = $asm.GetType('Thornswood.Paths')
    $art = $asm.GetType('Thornswood.Art')
    $nps = [Reflection.BindingFlags]'NonPublic, Static'
    $due = $icons.GetMethod('Due', $nps)
    $remember = $icons.GetMethod('Remember', $nps)
    $iconFile = $icons.GetMethod('IconFile', $nps)
    $wroteField = $icons.GetField('iconWritten', $nps)
    Yes 'Icons has Due, Remember, IconFile and iconWritten' ($due -and $remember -and $iconFile -and $wroteField)
    if (-not ($due -and $remember -and $iconFile -and $wroteField)) { Done }

    $root = Join-Path $work 'root'
    $launcherDir = Join-Path $root 'Launcher'
    $profileDir = Join-Path $root 'Profile'
    New-Item -ItemType Directory -Force -Path $launcherDir, $profileDir | Out-Null
    $paths.GetField('Root').SetValue($null, $root)
    $paths.GetField('LauncherDir').SetValue($null, $launcherDir)
    $paths.GetField('ProfileDir').SetValue($null, $profileDir)

    function IconNow { $wroteField.SetValue($null, $false); $p = $iconFile.Invoke($null, @()); @{ Path = $p; Wrote = [bool]$wroteField.GetValue($null) } }

    # The icon file: written when missing, and says so.
    $r = IconNow
    Yes "IconFile writes icon-$mainHash.ico for the main build" ($r.Path -and (Split-Path -Leaf $r.Path) -eq "icon-$mainHash.ico" -and (Test-Path -LiteralPath $r.Path))
    Yes 'and reports it had to write it' $r.Wrote
    $r = IconNow
    Yes 'an ordinary start finds it in place and writes nothing' (-not $r.Wrote)
    Remove-Item -LiteralPath $r.Path -Force   # what Install-Launcher's sweep used to do
    $r = IconNow
    Yes 'a start after an install deleted it writes it back before any shortcut is touched' ((Test-Path -LiteralPath $r.Path) -and $r.Wrote)

    # #2627: what Ensure would change, said and not done, for Scan. Before any
    # launcher exe is in the scratch install, so no shortcut anywhere names it
    # and none is missing for it; only the icon file and the stamp count.
    $outOfDate = $icons.GetMethod('OutOfDate', [Reflection.BindingFlags]'Public, Static')
    Yes 'Icons has OutOfDate, what Ensure would change, for Scan (#2627)' ([bool]$outOfDate)
    if ($outOfDate) {
        $iconNow = [string]$r.Path
        Remove-Item -LiteralPath $iconNow -Force
        $seen = { @(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { $_.FullName + '|' + $_.Length + '|' + $_.LastWriteTimeUtc.Ticks }) -join "`n" }
        $before = & $seen
        $l = @($outOfDate.Invoke($null, @()))
        Yes 'with the icon file gone, OutOfDate says so' (@($l | Where-Object { "$_" -like '*icon file*' }).Count -eq 1)
        Yes 'and writes nothing: the icon file is still gone, and no stamp or shortcut appeared' (((& $seen) -eq $before) -and -not (Test-Path -LiteralPath $iconNow))
        $r = IconNow
        [string]$noExe = Join-Path $launcherDir 'Thornswood.exe'
        $remember.Invoke($null, @($noExe, ([string]$r.Path + ',0'))) | Out-Null
        $l = @($outOfDate.Invoke($null, @()))
        Yes ('with the icon written and the shortcuts redrawn for this launcher, nothing is out of date' + $(if ($l.Count) { ' (' + ($l -join '; ') + ')' } else { '' })) ($l.Count -eq 0)
        Remove-Item -LiteralPath (Join-Path $profileDir 'icons.stamp') -Force
    }
    $want = [string]$r.Path + ',0'

    # The stamp: a rebuild-style change with no .old.
    [string]$exe = Join-Path $launcherDir 'Thornswood.exe'
    [IO.File]::WriteAllBytes($exe, [byte[]](1..200))
    (Get-Item -LiteralPath $exe).LastWriteTimeUtc = [datetime]::new(2026, 9, 27, 16, 33, 32, [DateTimeKind]::Utc)
    $stamp = Join-Path $profileDir 'icons.stamp'
    Yes 'the first start with no stamp redraws' ([bool]$due.Invoke($null, @($exe, $want, $false)))
    $remember.Invoke($null, @($exe, $want)) | Out-Null
    Yes 'Remember writes Profile\icons.stamp' (Test-Path -LiteralPath $stamp)
    Yes 'an unchanged start does not redraw' (-not [bool]$due.Invoke($null, @($exe, $want, $false)))
    Yes 'and again, still quiet' (-not [bool]$due.Invoke($null, @($exe, $want, $false)))

    # Rebuild into the install folder: copied over in place, no .old left.
    [IO.File]::WriteAllBytes($exe, [byte[]](1..250))
    (Get-Item -LiteralPath $exe).LastWriteTimeUtc = [datetime]::new(2026, 9, 28, 1, 22, 53, [DateTimeKind]::Utc)
    Yes 'the rebuild left no Thornswood.exe.old, so the #816 path would not run' (-not (Test-Path -LiteralPath ($exe + '.old')))
    Yes 'a rebuild copied over the exe with no .old redraws' ([bool]$due.Invoke($null, @($exe, $want, $false)))
    $remember.Invoke($null, @($exe, $want)) | Out-Null
    Yes 'and the start after it is quiet again' (-not [bool]$due.Invoke($null, @($exe, $want, $false)))

    # Same size, new build time (a rebuild of the same source).
    (Get-Item -LiteralPath $exe).LastWriteTimeUtc = [datetime]::new(2026, 9, 28, 12, 0, 0, [DateTimeKind]::Utc)
    Yes 'a same-size exe with a new write time redraws' ([bool]$due.Invoke($null, @($exe, $want, $false)))
    $remember.Invoke($null, @($exe, $want)) | Out-Null

    # The icon file had to be written back: redraw even with the exe unchanged.
    Yes 'an icon file written back forces a redraw on an otherwise unchanged start' ([bool]$due.Invoke($null, @($exe, $want, $true)))
    # New artwork, new name.
    Yes 'a different icon file redraws' ([bool]$due.Invoke($null, @($exe, ($launcherDir + '\icon-00000000.ico,0'), $false)))

    # Main and Dev keep their own stamp: each install has its own Profile.
    $devRoot = Join-Path $work 'root-DevBuild'
    New-Item -ItemType Directory -Force -Path (Join-Path $devRoot 'Launcher'), (Join-Path $devRoot 'Profile') | Out-Null
    $paths.GetField('LauncherDir').SetValue($null, (Join-Path $devRoot 'Launcher'))
    $paths.GetField('ProfileDir').SetValue($null, (Join-Path $devRoot 'Profile'))
    $art.GetField('Dev').SetValue($null, $true)
    $r = IconNow
    Yes "the dev build's IconFile is icon-$devHash.ico (app-dev.ico)" ($r.Path -and (Split-Path -Leaf $r.Path) -eq "icon-$devHash.ico")
    Yes 'the dev install does not read the main install''s stamp' ([bool]$due.Invoke($null, @($exe, $want, $false)))
    $art.GetField('Dev').SetValue($null, $false)

    # #3205: removal finds shortcuts by what they run, not by name. A pin left
    # behind under Thornswood.lnk made the next pin "Thornswood (2)".
    $to = $icons.GetMethod('ShortcutsTo', [Reflection.BindingFlags]'Public, Static')
    $drop = $icons.GetMethod('Drop', [Reflection.BindingFlags]'Public, Static')
    Yes 'Icons has ShortcutsTo and Drop (#3205)' ($to -and $drop)
    if ($to -and $drop) {
        $ws = New-Object -ComObject WScript.Shell
        function Link([string]$name, [string]$target) {
            $p = Join-Path $root $name
            $sc = $ws.CreateShortcut($p); $sc.TargetPath = $target; $sc.Save()
            $p
        }
        [string]$devExe = Join-Path $devRoot 'Launcher\Thornswood.exe'
        $numbered = Link 'Thornswood (2).lnk' $exe
        $other = Link 'Thornswood.lnk' 'C:\Gone\Launcher\Other.exe'
        $devLnk = Link 'Thornswood Dev.lnk' $devExe
        $found = @($to.Invoke($null, @($exe)))
        Yes 'ShortcutsTo finds the shortcut that runs this exe under a name that is not its own' ($found -contains $numbered)
        Yes 'and not one called Thornswood.lnk that runs something else, nor the dev build''s' (-not ($found -contains $other) -and -not ($found -contains $devLnk))
        $gone = [int]$drop.Invoke($null, @($exe))
        Yes "Drop deletes just that one (said $gone)" ($gone -eq 1 -and -not (Test-Path -LiteralPath $numbered) -and (Test-Path -LiteralPath $other) -and (Test-Path -LiteralPath $devLnk))
        Remove-Item -LiteralPath $other, $devLnk -Force
    }
    $src0 = Get-Content -LiteralPath $iconsCs -Raw
    $toAt = $src0.IndexOf('public static List<string> ShortcutsTo(string exe)')
    Yes 'ShortcutsTo walks the same places as Ensure, the pinned taskbar folder among them' ($toAt -ge 0 -and $src0.IndexOf('foreach (Place spot in Places())', $toAt) -gt $toAt -and $src0.Contains('User Pinned\\TaskBar'))

    # Ensure wires it in before the walk, and remembers after it.
    $src = Get-Content -LiteralPath $iconsCs -Raw
    $ensureAt = $src.IndexOf('public static int Ensure(bool force)')
    $dueAt = $src.IndexOf('Due(exe, want, iconWritten)', $ensureAt)
    $walkAt = $src.IndexOf('foreach (Place spot in Places())', $ensureAt)
    $rememberAt = $src.IndexOf('Remember(exe, want)', $ensureAt)
    Yes 'Ensure asks Due before it walks the shortcuts' ($ensureAt -ge 0 -and $dueAt -gt $ensureAt -and $dueAt -lt $walkAt)
    Yes 'and remembers after the walk' ($rememberAt -gt $walkAt)
    Yes 'IconFile is called before Due, so the file the shortcuts name exists first' ($src.IndexOf('string icon = IconFile();', $ensureAt) -lt $dueAt)
    Yes 'ordinary starts never kill Explorer: taskkill is only in Repair' ($src.IndexOf('taskkill') -gt $src.IndexOf('public static string Repair()'))

    # ---- 2. Install-Launcher.ps1 names the file after the exe's art -------------
    $stage = Join-Path $work 'stage'
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    $prog = Join-Path $work 'Program.cs'
    Set-Content -LiteralPath $prog -Value 'static class Program { static void Main() { } }' -Encoding ASCII
    # An exe whose app.ico is the dev art: what a CI-built exe with art other
    # than the checkout's looks like to the install.
    $out = & $LauncherCsc /nologo /target:winexe "/out:$(Join-Path $stage 'Thornswood.exe')" "/resource:$devIco,app.ico" $prog 2>&1
    Yes 'a stand-in exe carrying other art compiles' ($LASTEXITCODE -eq 0)
    $sroot = Join-Path $work 'scratchroot'
    $ps = Get-WindowsPowerShell
    $inst = Join-Path $Repo 'scripts\release\Install-Launcher.ps1'
    $sLauncher = Join-Path $sroot 'Launcher'
    New-Item -ItemType Directory -Force -Path $sLauncher | Out-Null
    # The file a shortcut named before this install, same art as the exe.
    [IO.File]::WriteAllBytes((Join-Path $sLauncher "icon-$devHash.ico"), [IO.File]::ReadAllBytes($devIco))
    # Continue, so a line on the child's stderr is read as output rather than
    # stopping this script before the checks say what happened.
    $ErrorActionPreference = 'Continue'
    $iout = & $ps -NoProfile -ExecutionPolicy Bypass -File $inst -Root $sroot -From $stage -NoClose -NoPause 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    Yes "the scratch install passes (exit $code)" ($code -eq 0)
    if ($code -ne 0) { Write-Host $iout }
    Yes "the install keeps icon-$devHash.ico, the art the exe carries" (Test-Path -LiteralPath (Join-Path $sLauncher "icon-$devHash.ico"))
    Yes "and does not write icon-$mainHash.ico from the repository's app.ico" (-not (Test-Path -LiteralPath (Join-Path $sLauncher "icon-$mainHash.ico")))
    $lnk = Join-Path $sroot 'Thornswood.lnk'
    $loc = ''
    if (Test-Path -LiteralPath $lnk) { $loc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk).IconLocation }
    Yes 'the scratch shortcut names that same file' ($loc -like "*\icon-$devHash.ico,0")
    Yes 'a scratch install asks nothing of Explorer' ($iout -notmatch 'Explorer told to redraw' -and $iout -notmatch 'Explorer restarted')
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Done
