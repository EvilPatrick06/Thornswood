<#
  test-2599-whole-swaps.ps1

      pwsh -NoProfile -File .\tests\test-2599-whole-swaps.ps1

  Issue #2599. Four places in the launcher replaced a file in Thornswood's
  game folder in two steps, the old name off (File.Delete or DropName) and
  then the new file moved in (File.Move), so a launcher stopped between the
  two left the file missing: Enforce.MakeItOurs, OwnGame.Separate, and the
  share step and TakeBack in OwnGameShare. #2591 measured the pattern: 30 of
  150 kills left the file missing; one MoveFileEx rename over it, none.

  WHAT IT HOLDS THEM TO.
    1. None of the four deletes and then moves; each calls OwnGame.SwapIn.
    2. SwapIn, lifted out of OwnGame.cs with the MoveFileEx it calls and
       compiled with the launcher's compiler: it replaces a file and leaves
       nothing beside it; it puts a file in place where there was none; on a
       read only file it clears the mark and replaces it only when told to,
       and otherwise throws and leaves the file as it was; and over one name
       of a hard linked file it replaces that name and the other name keeps
       its own bytes.
    3. Killed while it swaps: a child swaps a 17 KB file over and over through
       SwapIn and is killed 50 times; the file is there and whole every time.
       The same child swapping by delete then move, the old way, is killed
       the same way 200 times and loses the file at least once, so the test can see the
       fault it guards against.

  Nothing outside its own scratch folder is read or written, besides the
  repository's own sources.
#>
[CmdletBinding()]
param([string]$Scratch)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
$Repo = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Repo 'launcher\app'
if (-not $Scratch) { $Scratch = [IO.Path]::GetTempPath() }

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
function Src([string]$name) { return ([IO.File]::ReadAllText((Join-Path $App $name)) -replace "`r`n", "`n") }

# ---- 1: the four places -----------------------------------------------------------
$enforce = Src 'Enforce.cs'
$og = Src 'OwnGame.cs'
$share = Src 'OwnGameShare.cs'
function Body([string]$src, [string]$head) {
    $m = [regex]::Match($src, '(?s)' + $head + '.*?\n        \}\n')
    if ($m.Success) { return $m.Value } else { return '' }
}
$make = Body $enforce 'static void MakeItOurs\(string file\)'
$sep = Body $og 'public static void Separate\(string path\)'
$take = Body $share 'static bool TakeBack\('
Yes 'Enforce.MakeItOurs, OwnGame.Separate and OwnGameShare.TakeBack are found' ($make -and $sep -and $take)
Yes 'MakeItOurs renames its copy over the file with SwapIn, and deletes nothing first' ($make -match 'OwnGame\.SwapIn\(tmp, file, false\)' -and $make -notmatch 'File\.Delete\(file\)' -and $make -notmatch 'File\.Move\(')
Yes 'Separate renames its copy over the file with SwapIn, and deletes nothing first' ($sep -match 'SwapIn\(own, path, false\)' -and $sep -notmatch 'File\.Delete\(path\)' -and $sep -notmatch 'File\.Move\(')
Yes 'TakeBack renames the Steam copy''s link over the file with SwapIn, and drops no name first' ($take -match 'SwapIn\(next, own, true\)' -and $take -notmatch 'DropName\(own\)' -and $take -notmatch 'File\.Move\(')
Yes 'the share step does the same' ($share -match 'CreateHardLink\(next, theirs, IntPtr\.Zero\)\) continue;\s*\n\s*SwapIn\(next, own, true\);')
Yes 'no File.Move is left in OwnGameShare.cs' ($share -notmatch 'File\.Move\(')

# ---- 2 and 3: SwapIn itself, compiled ----------------------------------------------
$m = [regex]::Match($og, '(?s)\n(        internal static void SwapIn\(string next, string path, bool clearReadOnly\)\n        \{\n.*?\n        \}\n.*?static extern bool MoveFileEx\([^)]*\);\n)')
Yes 'OwnGame.SwapIn is in OwnGame.cs, with the MoveFileEx it calls' $m.Success
Yes '...one MoveFileEx over the name, replacing it, and no delete or File.Replace' ($m.Success -and $m.Groups[1].Value -match 'MoveFileEx\(next, path, MoveReplaceExisting \| MoveWriteThrough\)' -and
    $m.Groups[1].Value -notmatch 'File\.Delete\(' -and $m.Groups[1].Value -notmatch 'File\.Replace\(')
if (-not $m.Success) { Done }

$work = Join-Path $Scratch ('thornswood-2599-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $work
try {
    $driver = @'
using System;
using System.IO;
using System.Runtime.InteropServices;

namespace Thornswood
{
    static class WholeSwapTest
    {
__SWAPIN__
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool CreateHardLink(string name, string existing, IntPtr security);

        static int Main(string[] args)
        {
            string mode = args[0], path = args[1];
            if (mode == "swap") {
                try { SwapIn(args[2], path, args[3] == "clear"); return 0; }
                catch (IOException e) { Console.WriteLine(e.Message); return 3; }
            }
            if (mode == "link") { return CreateHardLink(args[2], path, IntPtr.Zero) ? 0 : 4; }
            // Over and over until killed: a copy aside, then in its place.
            bool whole = mode == "loop";
            string next = path + ".next";
            Console.WriteLine("ready");
            Console.Out.Flush();
            for (int n = 0; ; n++)
            {
                File.WriteAllBytes(next, File.ReadAllBytes(path));
                if (whole) SwapIn(next, path, false);
                else { File.Delete(path); File.Move(next, path); }
            }
        }
    }
}
'@
    $driver = $driver.Replace('__SWAPIN__', $m.Groups[1].Value.TrimEnd())
    $src = Join-Path $work 'WholeSwapTest.cs'
    [IO.File]::WriteAllText($src, $driver, (New-Object Text.UTF8Encoding($false)))
    $exe = Join-Path $work 'whole-swap-test.exe'
    $fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
    $cscArgs = @('/noconfig', '/nologo', '/target:exe', "/langversion:$LauncherLangVersion", "/out:$exe",
                 "/reference:$(Join-Path $fw 'System.dll')", "/reference:$(Join-Path $fw 'System.Core.dll')", $src)
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $compiled = & $LauncherCsc @cscArgs 2>&1
    $ErrorActionPreference = $old
    $built = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $exe)
    Yes "SwapIn compiles with the launcher's compiler, C# $LauncherLangVersion" $built
    if (-not $built) { foreach ($l in @($compiled)) { Write-Host "      $l" }; Done }

    function Run([string[]]$a) { $null = & $exe @a; return $LASTEXITCODE }
    function Put([string]$p, [string]$t) { [IO.File]::WriteAllText($p, $t) }
    function Text([string]$p) { if (Test-Path -LiteralPath $p) { return [IO.File]::ReadAllText($p) } else { return $null } }
    function RO([string]$p) { return (([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReadOnly) -ne 0) }

    # 2: what it does.
    $f = Join-Path $work 'a.ini'; $n = Join-Path $work 'a.ini.next'
    Put $f 'old'; Put $n 'new'
    Yes 'a file is replaced by the one beside it' ((Run @('swap', $f, $n, 'keep')) -eq 0 -and (Text $f) -eq 'new')
    Yes '...and nothing is left beside it' (-not (Test-Path -LiteralPath $n))
    $g = Join-Path $work 'b.esp'; Put $n 'fresh'
    Yes 'where there was no file, it is put in place' ((Run @('swap', $g, $n, 'keep')) -eq 0 -and (Text $g) -eq 'fresh')

    $r = Join-Path $work 'r.ini'; Put $r 'old'; [IO.File]::SetAttributes($r, 'ReadOnly'); Put $n 'new'
    Yes 'a read only file, not told to clear the mark: refused, and left as it was' ((Run @('swap', $r, $n, 'keep')) -eq 3 -and (Text $r) -eq 'old' -and (RO $r) -and (Text $n) -eq 'new')
    Yes 'told to clear the mark: replaced' ((Run @('swap', $r, $n, 'clear')) -eq 0 -and (Text $r) -eq 'new' -and -not (Test-Path -LiteralPath $n))

    $vortex = Join-Path $work 'vortex.ini'; $ours = Join-Path $work 'ours.ini'
    Put $vortex 'theirs'
    $linked = (Run @('link', $vortex, $ours)) -eq 0
    Put $n 'mine'
    Yes 'over one name of a hard linked file, that name is replaced and the other keeps its own bytes' ($linked -and (Run @('swap', $ours, $n, 'keep')) -eq 0 -and (Text $ours) -eq 'mine' -and (Text $vortex) -eq 'theirs')

    # 3: killed while it swaps.
    $body = ('x' * 17000)
    function KillTest([string]$mode, [string]$path, [int]$kills) {
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)
        Put $path $body
        $whole = 0; $bad = @()
        $rand = New-Object Random 2599
        for ($i = 0; $i -lt $kills; $i++) {
            if (-not (Test-Path -LiteralPath $path)) { Put $path $body }
            $psi = New-Object Diagnostics.ProcessStartInfo($exe, ('"{0}" "{1}"' -f $mode, $path))
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $p = [Diagnostics.Process]::Start($psi)
            $null = $p.StandardOutput.ReadLine()
            Start-Sleep -Milliseconds ($rand.Next(15, 160))
            $p.Kill()
            $p.WaitForExit()
            $p.Dispose()
            if ((Text $path) -eq $body) { $whole++ } else { $bad += $(if (Test-Path -LiteralPath $path) { 'cut' } else { 'missing' }) }
        }
        return [pscustomobject]@{ Whole = $whole; Bad = $bad }
    }
    $k = KillTest 'loop' (Join-Path $work 'killed\settings.ini') 50
    Yes ('killed 50 times while SwapIn swaps: the file is there and whole every time ({0} of 50{1})' -f $k.Whole, $(if ($k.Bad) { '; ' + ($k.Bad -join ', ') })) ($k.Whole -eq 50)
    $o = KillTest 'oldway' (Join-Path $work 'oldway\settings.ini') 200
    Yes ('the old delete then move, killed the same way, loses the file at least once ({0} of 200 not whole)' -f $o.Bad.Count) ($o.Bad.Count -ge 1)
}
finally {
    Get-ChildItem -LiteralPath $work -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Attributes = 'Normal' } catch { } }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Done
