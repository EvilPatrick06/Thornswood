<#
  test-app-manifest.ps1

  Issue #463. Both exes a stranger runs, the launcher (Thornswood.exe) and the
  setup program (Thornswood-Setup.exe, built as out\setup-stub.exe), carry
  an application manifest of our own:
    - dpiAwareness PerMonitorV2, and the legacy dpiAware "true" (system aware,
      never the per-monitor legacy form, which older Framework WPF sizes wrong);
    - supportedOS for Windows 10 and 11, 8.1, 8, 7 and Vista;
    - requestedExecutionLevel asInvoker with uiAccess false, so neither ever
      asks for administrator;
    - an assemblyIdentity (Thornswood.Launcher.Thornswood and
      Thornswood.Installer.Setup) whose version is the launcher's own, the
      Version in launcher\app\Updater.cs in four parts. The manifest files in
      the repository hold a placeholder and the project files stamp a copy,
      so the identity cannot drift the way a kept 1.1.101.0 did.
  Until then the launcher's identity sat at 1.1.101.0 while the launcher was
  1.1.102, and the setup program carried csc's default manifest, named
  MyApplication.app 1.0.0.0 with no DPI awareness at all, so Windows stretched
  its window blurry at any scale above 100 percent.

  What it checks:
    1. the two manifest files and the build wiring, as text;
    2. the manifest really embedded in each built exe, read back through the
       Windows resource API (RT_MANIFEST, id 1), not by what the build says;
    3. the window fit (launcher\app\WindowFit.cs, shared with the setup
       program), compiled with the build's compiler and run for both windows'
       own sizes on 1366x768, 1920x1080, 2560x1440 and 3840x2160 screens at
       100, 125, 150, 175 and 200 percent, and moving from a 200 percent
       screen back to a 100 percent one: never bigger than the screen, never
       smaller than it has to be, and the full size wherever it fits.
  What a person still checks: a real mixed-DPI desktop, window sharp on both
  monitors, and the Downgrade click still landing in Steam's console.

  Usage:
    pwsh -File tests\test-app-manifest.ps1 -Exe <Thornswood.exe> [-Stub <setup-stub.exe>]
    pwsh -File tests\test-app-manifest.ps1 -Root <scratch folder>    builds there first
  With neither, on the build runner it reads the exe the build step made
  ($env:RUNNER_TEMP\Thornswood\Launcher\Thornswood.exe). -Stub defaults to
  out\setup-stub.exe, which Build-Launcher.ps1 writes.
  Read only, apart from -Root's build and a scratch folder for step 3.
#>
[CmdletBinding()]
param(
    [string]$Exe,
    [string]$Stub,
    [string]$Root,
    [string]$Scratch
)

Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$updater = [IO.File]::ReadAllText((Join-Path $repo 'launcher\app\Updater.cs'))
$m = [regex]::Match($updater, 'Version\s*=\s*"([0-9.]+)"')
Yes 'Updater.cs names the launcher version' $m.Success
$ver4 = $m.Groups[1].Value
while (($ver4 -split '\.').Count -lt 4) { $ver4 = "$ver4.0" }
Write-Host "      launcher version $ver4"

$win10 = '{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}'
$allOs = @($win10, '{1f676c76-80e1-4239-95bb-83d0f6d0da78}', '{4a2f28e3-53b9-4441-ba9c-d69d4a4a6e38}',
           '{35138b9a-5d96-4fbd-8e2d-a2440225f93a}', '{e2011457-1546-43c5-a5fe-008deee3d3f0}')

# One manifest's contents, held to the rules above. $wantVersion is the
# placeholder for the repository files and the launcher version for the exes.
function Check-Manifest([string]$label, [string]$text, [string]$wantName, [string]$wantVersion) {
    $x = $null
    try { $x = [xml]$text } catch { $x = $null }
    Yes "$label parses as XML" ($null -ne $x)
    if ($null -eq $x) { return }
    $ns = New-Object Xml.XmlNamespaceManager($x.NameTable)
    $ns.AddNamespace('a1', 'urn:schemas-microsoft-com:asm.v1')
    $ns.AddNamespace('a3', 'urn:schemas-microsoft-com:asm.v3')
    $ns.AddNamespace('c', 'urn:schemas-microsoft-com:compatibility.v1')
    $ns.AddNamespace('w16', 'http://schemas.microsoft.com/SMI/2016/WindowsSettings')
    $ns.AddNamespace('w05', 'http://schemas.microsoft.com/SMI/2005/WindowsSettings')
    $id = $x.SelectSingleNode('/a1:assembly/a1:assemblyIdentity', $ns)
    Yes "$label has an assemblyIdentity" ($null -ne $id)
    if ($id) {
        Yes "$label identity is type win32" ($id.GetAttribute('type') -eq 'win32')
        Yes "$label identity name is $wantName" ($id.GetAttribute('name') -eq $wantName)
        Yes "$label identity version is $wantVersion (it says $($id.GetAttribute('version')))" ($id.GetAttribute('version') -eq $wantVersion)
    }
    $lvl = $x.SelectSingleNode('//a3:requestedExecutionLevel', $ns)
    Yes "$label asks for asInvoker, so no administrator prompt" ($lvl -and $lvl.GetAttribute('level') -eq 'asInvoker')
    Yes "$label has uiAccess false" ($lvl -and $lvl.GetAttribute('uiAccess') -eq 'false')
    Yes "$label asks for nothing above asInvoker anywhere" ($text -notmatch 'requireAdministrator|highestAvailable')
    $os = @($x.SelectNodes('//c:supportedOS', $ns) | ForEach-Object { $_.GetAttribute('Id').ToLowerInvariant() })
    Yes "$label declares Windows 10 and 11" ($os -contains $win10)
    Yes "$label declares all five supportedOS entries" (@($allOs | Where-Object { $os -notcontains $_ }).Count -eq 0)
    $pm = $x.SelectSingleNode('//w16:dpiAwareness', $ns)
    Yes "$label is PerMonitorV2" ($pm -and $pm.InnerText.Trim() -eq 'PerMonitorV2')
    $legacy = $x.SelectSingleNode('//w05:dpiAware', $ns)
    Yes "$label legacy dpiAware is true (system aware), not true/pm" ($legacy -and $legacy.InnerText.Trim() -eq 'true')
}

# ---- 1. the files and the build wiring ---------------------------------------
$tplApp = Join-Path $repo 'launcher\app\Thornswood.manifest'
$tplSetup = Join-Path $repo 'installer\setup\Setup.manifest'
Yes 'launcher\app\Thornswood.manifest is there' (Test-Path -LiteralPath $tplApp)
Yes 'installer\setup\Setup.manifest is there' (Test-Path -LiteralPath $tplSetup)
if (Test-Path -LiteralPath $tplApp) { Check-Manifest 'the launcher manifest file' ([IO.File]::ReadAllText($tplApp)) 'Thornswood.Launcher.Thornswood' '0.0.0.0' }
if (Test-Path -LiteralPath $tplSetup) { Check-Manifest 'the setup manifest file' ([IO.File]::ReadAllText($tplSetup)) 'Thornswood.Installer.Setup' '0.0.0.0' }

# Since #498's switch the project files stamp and embed the manifests, and
# Build-Launcher.ps1 signs only after MSBuild has built the exe.
$appProjText = [IO.File]::ReadAllText((Join-Path $repo 'launcher\app\Thornswood.csproj'))
$setupProjText = [IO.File]::ReadAllText((Join-Path $repo 'installer\setup\Setup.csproj'))
$poke = 'Query="/asm:assembly/asm:assemblyIdentity/@version" Value="$(ThornswoodVersionFour)"'
Yes 'the launcher project stamps Thornswood.manifest with the four part version' ($appProjText.Contains('SourceFiles="$(MSBuildThisFileDirectory)Thornswood.manifest"') -and $appProjText.Contains($poke))
Yes 'and embeds that copy as the application manifest' ($appProjText.Contains('<ApplicationManifest>$(BaseIntermediateOutputPath)Thornswood.stamped.manifest</ApplicationManifest>'))
Yes 'the setup project stamps Setup.manifest with the four part version' ($setupProjText.Contains('SourceFiles="$(MSBuildThisFileDirectory)Setup.manifest"') -and $setupProjText.Contains($poke))
Yes 'and embeds it in the setup program' ($setupProjText.Contains('<ApplicationManifest>$(BaseIntermediateOutputPath)ThornswoodSetup.stamped.manifest</ApplicationManifest>'))
Yes 'the setup program is compiled with WindowFit.cs' ($setupProjText.Contains('<Compile Include="..\..\launcher\app\WindowFit.cs">'))
Yes 'no Win32Resource, which would fight the application manifest' ($appProjText -notmatch '<Win32Resource>' -and $setupProjText -notmatch '<Win32Resource>')
$bl = [IO.File]::ReadAllText((Join-Path $repo 'scripts\release\Build-Launcher.ps1'))
$buildAt = $bl.IndexOf('& $found.MSBuild (Resolve-Path -LiteralPath $proj).Path')
$signAt = $bl.IndexOf('& $signer -Path $exe')
Yes 'the manifest is embedded by the build before the launcher is signed' ($buildAt -gt 0 -and $signAt -gt $buildAt)

# The switch that lets Framework WPF rescale on a change of monitor scale is
# read once and kept, so it has to be the first thing each Main does.
$shell = [IO.File]::ReadAllText((Join-Path $repo 'launcher\app\Shell.cs'))
$boot = [IO.File]::ReadAllText((Join-Path $repo 'installer\setup\Bootstrap.cs'))
$sw = 'AppContext.SetSwitch("Switch.System.Windows.DoNotScaleForDpiChanges", false);'
$mainAt = $shell.IndexOf('static void Main(string[] args)')
Yes 'the launcher sets the DPI switch in Main, before its mutex and message boxes' (
    $mainAt -gt 0 -and $shell.IndexOf($sw) -gt $mainAt -and $shell.IndexOf($sw) -lt $shell.IndexOf('new Mutex(', $mainAt))
Yes 'and only there' (([regex]::Matches($shell, [regex]::Escape($sw))).Count -eq 1)
$bMain = $boot.IndexOf('static void Main()')
Yes 'the setup program sets it in Main, before Run' ($bMain -gt 0 -and $boot.IndexOf($sw) -gt $bMain -and $boot.IndexOf($sw) -lt $boot.IndexOf('try { Run(); }', $bMain))
Yes 'the launcher fits its window before centring it' ($shell.IndexOf('WindowFit.Keep(win)') -gt 0 -and $shell.IndexOf('WindowFit.Keep(win)') -lt $shell.IndexOf('CentreOnMainScreen();'))
Yes 'the setup program fits its window before centring it' ($boot.IndexOf('Thornswood.WindowFit.Keep(win)') -gt 0 -and $boot.IndexOf('Thornswood.WindowFit.Keep(win)') -lt $boot.IndexOf('win.Left = work.Left'))
Yes 'the maximized frame is measured at the monitor''s own scale' ($shell.Contains('WindowFit.FramePixels(scale)') -and $shell -notmatch 'GetSystemMetrics\(32\)')

# ---- 2. the manifest inside the built exes --------------------------------------
# With no -Exe and no -Root: the build step's exe on the runner when there is
# one, and otherwise a build of its own in the temp folder. The nightly runs
# every harness before its build step, and a person runs this bare, so until
# then both ended red on an exe that had not been built yet (issue #1120).
$ownRoot = $null
if (-not $Exe -and -not $Root) {
    $runnerExe = if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'Thornswood\Launcher\Thornswood.exe' } else { '' }
    if ($runnerExe -and (Test-Path -LiteralPath $runnerExe)) { $Exe = $runnerExe }
    else {
        $ownRoot = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-test-app-manifest-build-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Force -Path (Join-Path $ownRoot 'Launcher')
        $Root = $ownRoot
    }
}
if (-not $Exe -and $Root) {
    Write-Host "      building into $Root"
    & pwsh -NoProfile -File (Join-Path $repo 'scripts\release\Build-Launcher.ps1') -Root $Root -NoPause | Out-Null
    Yes 'Build-Launcher built' ($LASTEXITCODE -eq 0)
    $Exe = Join-Path $Root 'Launcher\Thornswood.exe'
}
if (-not $Exe -and $env:RUNNER_TEMP) { $Exe = Join-Path $env:RUNNER_TEMP 'Thornswood\Launcher\Thornswood.exe' }
if (-not $Stub) { $Stub = Join-Path $repo 'out\setup-stub.exe' }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ManifestProbe
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibraryEx(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr FindResource(IntPtr h, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll")] static extern uint SizeofResource(IntPtr h, IntPtr res);
    [DllImport("kernel32.dll")] static extern IntPtr LoadResource(IntPtr h, IntPtr res);
    [DllImport("kernel32.dll")] static extern IntPtr LockResource(IntPtr data);
    // RT_MANIFEST (24), id 1: the one Windows reads for an exe.
    public static string Read(string path, int id)
    {
        IntPtr h = LoadLibraryEx(path, IntPtr.Zero, 0x2 | 0x20); // AS_DATAFILE | AS_IMAGE_RESOURCE
        if (h == IntPtr.Zero) return null;
        try
        {
            IntPtr r = FindResource(h, (IntPtr)id, (IntPtr)24);
            if (r == IntPtr.Zero) return null;
            uint n = SizeofResource(h, r);
            IntPtr p = LockResource(LoadResource(h, r));
            if (p == IntPtr.Zero || n == 0) return null;
            byte[] b = new byte[n];
            Marshal.Copy(p, b, 0, (int)n);
            return Encoding.UTF8.GetString(b).TrimStart('﻿').TrimEnd('\0', ' ', '\r', '\n');
        }
        finally { FreeLibrary(h); }
    }
}
'@

foreach ($pair in @(@('the built launcher', $Exe, 'Thornswood.Launcher.Thornswood'), @('the built setup program', $Stub, 'Thornswood.Installer.Setup'))) {
    $label = $pair[0]; $path = $pair[1]; $name = $pair[2]
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        Yes "$label is at $path (pass -Exe/-Stub, or -Root to build)" $false
        continue
    }
    $full = (Resolve-Path -LiteralPath $path).Path
    $text = [ManifestProbe]::Read($full, 1)
    Yes "$label has an embedded manifest (RT_MANIFEST 1)" ($null -ne $text)
    if ($null -eq $text) { continue }
    Yes "$label does not carry csc's default manifest" ($text -notmatch 'name="MyApplication\.app"')
    Check-Manifest $label $text $name $ver4
    Yes "$label has only the one manifest (no RT_MANIFEST 2)" ($null -eq [ManifestProbe]::Read($full, 2))
    $fv = [Diagnostics.FileVersionInfo]::GetVersionInfo($full).FileVersion
    Yes "$label file version ($fv) is the same number as its identity" ($fv -eq $ver4)
}

# ---- 3. the window fit at 100 to 200 percent -------------------------------------
function Window-Size([string]$markup, [string]$label) {
    $sz = @{}
    foreach ($k in 'Width', 'Height', 'MinWidth', 'MinHeight') {
        $mm = [regex]::Match($markup, '(?<![A-Za-z])' + $k + '=""?(\d+)"')
        $sz[$k] = if ($mm.Success) { [int]$mm.Groups[1].Value } else { 0 }
    }
    Yes "$label window size read from its markup ($($sz.Width)x$($sz.Height), least $($sz.MinWidth)x$($sz.MinHeight))" (
        $sz.Width -gt 0 -and $sz.Height -gt 0 -and $sz.MinWidth -gt 0 -and $sz.MinHeight -gt 0)
    $sz
}
$uiXaml = [IO.File]::ReadAllText((Join-Path $repo 'launcher\ui.xaml'))
$uiHead = $uiXaml.Substring(0, $uiXaml.IndexOf('>', $uiXaml.IndexOf('<Window')))
$bootHead = $boot.Substring($boot.IndexOf('<Window xmlns'), 600)
$bootHead = $bootHead.Substring(0, $bootHead.IndexOf('>'))
$sizes = @(
    @('launcher', (Window-Size $uiHead 'the launcher')),
    @('setup', (Window-Size $bootHead 'the setup program'))
)

Yes 'the compiler the build runs is on this machine (the Roslyn csc beside MSBuild)' (Test-Path -LiteralPath $LauncherCsc)
if (-not $Scratch) { $Scratch = Join-Path ([IO.Path]::GetTempPath()) 'thornswood-test-app-manifest' }
$null = New-Item -ItemType Directory -Force -Path $Scratch
$driver = Join-Path $Scratch 'FitDriver.cs'
[IO.File]::WriteAllText($driver, @'
using System;
using System.Globalization;
static class FitDriver
{
    // args: designW designH designMinW designMinH. Prints one line per case:
    // screenW screenH percent workW workH -> w h minW minH
    static int Main(string[] a)
    {
        var c = CultureInfo.InvariantCulture;
        double dw = double.Parse(a[0], c), dh = double.Parse(a[1], c), dmw = double.Parse(a[2], c), dmh = double.Parse(a[3], c);
        int[][] screens = { new[] { 1366, 768 }, new[] { 1920, 1080 }, new[] { 2560, 1440 }, new[] { 3840, 2160 } };
        int[] percents = { 100, 125, 150, 175, 200 };
        foreach (var s in screens)
            foreach (int p in percents)
            {
                double scale = p / 100.0;
                // A 48 pixel taskbar at 100 percent, scaled like everything else.
                double workW = s[0] / scale, workH = (s[1] - 48 * scale) / scale;
                double w = dw, h = dh, minW, minH;
                Thornswood.WindowFit.Clamp(workW, workH, dmw, dmh, ref w, ref h, out minW, out minH);
                Console.WriteLine(string.Format(c, "{0} {1} {2} {3:0.###} {4:0.###} {5:0.###} {6:0.###} {7:0.###} {8:0.###}",
                    s[0], s[1], p, workW, workH, w, h, minW, minH));
            }
        // Moving: a 1080 line screen at 200 percent, then a 1440 line one at 100.
        double mw = dw, mh = dh, a1, b1, a2, b2;
        Thornswood.WindowFit.Clamp(1920 / 2.0, (1080 - 96) / 2.0, dmw, dmh, ref mw, ref mh, out a1, out b1);
        Thornswood.WindowFit.Clamp(2560, 1440 - 48, dmw, dmh, ref mw, ref mh, out a2, out b2);
        Console.WriteLine(string.Format(c, "MOVE {0:0.###} {1:0.###} {2:0.###} {3:0.###} {4:0.###} {5:0.###}", a1, b1, a2, b2, mw, mh));
        return 0;
    }
}
'@)
$fitExe = Join-Path $Scratch 'FitDriver.exe'
if (Test-Path -LiteralPath $LauncherCsc) {
    # /noconfig and the reference assemblies, as the build compiles it.
    $out = & $LauncherCsc /noconfig /nologo /target:exe "/out:$fitExe" `
        ('System.dll', 'System.Xaml.dll', 'WindowsBase.dll', 'PresentationCore.dll', 'PresentationFramework.dll' |
            ForEach-Object { '/reference:' + (Join-Path $LauncherRefDir $_) }) `
        (Join-Path $repo 'launcher\app\WindowFit.cs') $driver 2>&1
    Yes 'WindowFit.cs compiles on its own, as the setup program needs' ($LASTEXITCODE -eq 0)
    if ($LASTEXITCODE -ne 0) { $out | ForEach-Object { Write-Host "      $_" } }
}
if (Test-Path -LiteralPath $fitExe) {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($pair in $sizes) {
        $who = $pair[0]; $sz = $pair[1]
        $lines = @(& $fitExe $sz.Width $sz.Height $sz.MinWidth $sz.MinHeight)
        $bad = New-Object Collections.Generic.List[string]
        $cases = 0; $shrunk = 0
        foreach ($ln in $lines) {
            $f = $ln -split ' '
            if ($f[0] -eq 'MOVE') {
                $a1 = [double]::Parse($f[1], $inv); $b1 = [double]::Parse($f[2], $inv)
                $a2 = [double]::Parse($f[3], $inv); $b2 = [double]::Parse($f[4], $inv)
                Yes "$who, moved to a 200 percent 1080 line screen: minimum drops to fit ($a1 x $b1)" ($a1 -le 960 -and $b1 -le 492)
                Yes "$who, then to a 100 percent 1440 line screen: its own minimum is back ($a2 x $b2)" ($a2 -eq $sz.MinWidth -and $b2 -eq $sz.MinHeight)
                continue
            }
            $cases++
            $sw = $f[0]; $sh = $f[1]; $pc = $f[2]
            $workW = [double]::Parse($f[3], $inv); $workH = [double]::Parse($f[4], $inv)
            $w = [double]::Parse($f[5], $inv); $h = [double]::Parse($f[6], $inv)
            $mw = [double]::Parse($f[7], $inv); $mh = [double]::Parse($f[8], $inv)
            $tag = "${sw}x${sh} at $pc percent"
            if ($w -gt $workW + 0.001 -or $h -gt $workH + 0.001) { $bad.Add("$tag is bigger than the screen ($w x $h in $workW x $workH)") }
            if ($mw -gt $workW + 0.001 -or $mh -gt $workH + 0.001) { $bad.Add("$tag has a minimum bigger than the screen") }
            if ($w -lt $mw - 0.001 -or $h -lt $mh - 0.001) { $bad.Add("$tag is smaller than its minimum") }
            # Not tiny: wherever the full size fits it is kept, and a
            # dimension is only ever cut down to the screen, not below it.
            $wantW = [Math]::Min([double]$sz.Width, $workW); $wantH = [Math]::Min([double]$sz.Height, $workH)
            if ([Math]::Abs($w - $wantW) -gt 0.001 -or [Math]::Abs($h - $wantH) -gt 0.001) { $bad.Add("$tag is $w x $h, not $wantW x $wantH") }
            if ($w -lt $sz.Width -or $h -lt $sz.Height) { $shrunk++ }
        }
        Yes "$who window fits every screen at every scale ($cases cases, $shrunk cut to the screen)" ($cases -eq 20 -and $bad.Count -eq 0)
        foreach ($b in $bad) { Write-Host "      $b" }
        Yes "$who at 100 percent on 1920x1080 keeps its full size" (@($lines | Where-Object { $_ -like "1920 1080 100 *" } | ForEach-Object {
            $f = $_ -split ' '; ([double]::Parse($f[5], $inv) -eq $sz.Width) -and ([double]::Parse($f[6], $inv) -eq $sz.Height) }) -contains $true)
    }
}

if ($ownRoot) { Remove-Item -LiteralPath $ownRoot -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
