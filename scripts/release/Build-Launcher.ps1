<#
  Build-Launcher.ps1
  Compiles the launcher into a real Thornswood.exe.

  Uses csc.exe, which is part of the .NET Framework that ships inside Windows.
  Nothing to install. Your friends never compile anything - they get the
  finished exe in the bundle.

  It builds into the DEV install by default, not the one you play on. Running
  this by hand used to overwrite C:\Thornswood\Launcher, so a build nobody had
  tried yet became the launcher in front of you, and on 17 Sep one did exactly
  that and wrote a broken setting into the game folder on the next Play. A
  build you ran to see whether it compiles should never be able to do that.

  Ship.ps1 passes -Root itself, so a real release still builds where it should.
  Pass -Root 'C:\Thornswood' if you genuinely mean the one you play on.

  IT BUILDS AND DOES NOTHING ELSE. It writes Thornswood.exe into -OutDir, which
  is <Root>\Launcher unless told otherwise, and the setup stub beside this
  script. It closes no game and no launcher, and it does not touch the Desktop,
  the icon cache or Explorer. Those are Install-Launcher.ps1, which Ship.ps1
  runs after a build that worked. Until 24 September this script did both, so
  every compile check and every hand build closed whatever Skyrim was running
  on the machine, matched by name whichever folder it ran from, before csc had
  even started. That was To Do List entry 243: "A build produces files in an
  output folder and does not kill processes or write to the Desktop."

  TWO WAYS TO BUILD, UNTIL THE SWITCH (issue #498, Patrick's option C,
  11 Oct). -With csc, the default, is the in-box compiler as above. -With
  msbuild builds launcher\app\Thornswood.csproj and installer\setup\Setup.csproj
  with the MSBuild of Visual Studio 2022 or its Build Tools
  (Find-MSBuild.ps1 says whether this machine has it). Both make the same two
  exes, with the same checks before and the same signing after;
  tests\test-498-msbuild.ps1 builds both ways and compares them. The switch
  makes msbuild the only way, once every machine that builds the launcher has
  MSBuild; #498 says which still do not.
#>
[CmdletBinding()]
param(
    [string]$Src,
    [string]$Root = 'C:\Thornswood-DevBuild',
    # Where Thornswood.exe goes. Ship builds into a folder of its own and lets
    # Install-Launcher put the exe in place, so csc never meets a launcher that
    # is still running from the install.
    [string]$OutDir,
    [switch]$NoPause,
    # csc (the in-box compiler, the default) or msbuild (the two project files).
    [ValidateSet('csc', 'msbuild')]
    [string]$With = 'csc',
    # Where the setup program goes, out\setup-stub.exe unless told otherwise.
    # tests\test-498-msbuild.ps1 builds into scratch so a comparison never
    # replaces the stub a clone's packaging copies from.
    [string]$StubOut,
    # Leaves both exes unsigned even on a machine with records\signing\signing.json.
    # For a comparison build that never ships, so it spends no signing; Ship
    # never passes it, and Ship and Publish-Installer refuse an unsigned exe.
    [switch]$NoSign
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $MyInvocation is not usable from inside a param block, so the script folder
# is worked out here instead.
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Src)  { $Src  = Join-Path $Here '..\..\launcher\app' }
if (-not $OutDir) { $OutDir = Join-Path $Root 'Launcher' }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

Head 'Thornswood - launcher build'
Say ("  building into $OutDir") 'DarkGray'
if ($Root.TrimEnd('\\') -ieq 'C:\Thornswood') {
    Say '  this is the install you play on, not the dev one' 'Yellow'
}

# ------------------------------------------------------------ compiler
$csc = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $csc) { Die 'csc.exe was not found. That means the .NET Framework 4 is missing, which is unusual on Windows 10 or 11.' }
Say "  $csc" 'DarkGray'

# ------------------------------------------------------------ references
$refDirs = @(
    "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8"
    "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.7.2"
    "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.6.1"
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\WPF"
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\WPF"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319"
) | Where-Object { Test-Path $_ }

function Find-Ref([string]$name) {
    foreach ($d in $refDirs) {
        $p = Join-Path $d $name
        if (Test-Path $p) { return $p }
    }
    # WPF assemblies are split across the GAC by architecture. PresentationCore
    # and friends are not in GAC_MSIL.
    $stem = [IO.Path]::GetFileNameWithoutExtension($name)
    foreach ($gacRoot in 'GAC_MSIL', 'GAC_64', 'GAC_32', 'GAC') {
        $gac = Join-Path "$env:WINDIR\Microsoft.NET\assembly\$gacRoot" $stem
        if (Test-Path $gac) {
            $hit = Get-ChildItem $gac -Filter $name -Recurse -File -EA SilentlyContinue |
                   Sort-Object FullName -Descending | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    foreach ($gacRoot in 'GAC_MSIL', 'GAC_64', 'GAC_32') {
        $hit = Get-ChildItem (Join-Path "$env:WINDIR\Microsoft.NET\assembly" $gacRoot) -Filter $name -Recurse -File -EA SilentlyContinue |
               Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    $null
}

$needed = @(
    'System.dll', 'System.Core.dll', 'System.Drawing.dll',
    'System.Runtime.Serialization.dll',
    # Config reads and writes its JSON through DataContractJsonSerializer,
    # whose ReadObject and WriteObject also come in XmlReader and XmlWriter
    # shapes. csc has to see System.Xml to pick the Stream one, and with
    # /noconfig nothing adds it for us.
    'System.Xml.dll',
    # DPAPI, for the server password and the Discord ticket on disk.
    'System.Security.dll',
    'System.IO.Compression.dll', 'System.IO.Compression.FileSystem.dll',
    'PresentationFramework.dll', 'PresentationCore.dll', 'WindowsBase.dll', 'System.Xaml.dll',
    'System.Windows.Forms.dll'
)
$refs = @()
$missing = @()
foreach ($n in $needed) {
    $p = Find-Ref $n
    if ($p) { $refs += $p } else { $missing += $n }
}
if ($missing.Count) { Die ("Could not find these assemblies: " + ($missing -join ', ')) }

# ------------------------------------------------- WebView2, for voice
#
# Not a framework assembly, so the name search above cannot find it. These
# three files are Microsoft's redistributable WebView2 SDK and they are what
# gives this launcher a browser, which is what gives it a microphone and
# WebRTC. The game's own in-game browser has neither a permission prompt nor
# an autoplay policy anyone can satisfy, which is why voice never carried
# audio from in there.
#
# They are referenced for the compile AND embedded into the exe further down,
# because the update system publishes exactly one asset and SelfUpdate
# replaces exactly one file. Sidecar DLLs would need the publisher, the
# version document and the updater changed together, and would leave every
# launcher broken in between.
$wv2Dir = Join-Path $Here '..\..\launcher\lib\webview2'
$wv2Managed = @('Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.Wpf.dll')
$wv2Loader  = 'WebView2Loader.dll'
$wv2Missing = @()
foreach ($n in ($wv2Managed + $wv2Loader)) {
    if (-not (Test-Path -LiteralPath (Join-Path $wv2Dir $n))) { $wv2Missing += $n }
}
if ($wv2Missing.Count) {
    Die ("WebView2 files are missing from launcher\lib\webview2: " + ($wv2Missing -join ', '))
}
foreach ($n in $wv2Managed) { $refs += (Join-Path $wv2Dir $n) }

Say "  $($refs.Count) references resolved" 'Green'
foreach ($r in $refs) { Say "    $r" 'DarkGray' }

# ------------------------------------------------------------ sources
$cs = @(Get-ChildItem (Join-Path $Src '*.cs') -File)
if (-not $cs.Count) { Die "No .cs files under $Src" }
$xaml = @((Join-Path $Here '..\..\launcher\ui.xaml'), (Join-Path $Src 'ui.xaml')) | Where-Object { Test-Path $_ } | Select-Object -First 1
$icon = @((Join-Path $Here '..\..\launcher\app.ico'), (Join-Path $Src 'app.ico')) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $xaml) { Die "ui.xaml was not found next to this script or in $Src" }
if (-not $icon) { Die "app.ico was not found next to this script or in $Src" }

# The emblem is compiled in rather than shipped beside the exe, so the update
# that replaces the launcher brings its own artwork and there is no second file
# to go missing. Both are optional: without them the launcher falls back to the
# game's own icon and simply does not draw an emblem.
$logo    = Join-Path $Here '..\..\launcher\logo.png'
$logoSml = Join-Path $Here '..\..\launcher\logo-192.png'
# Optional to the launcher, not to the build: every one of these is tracked in
# the repository, so a missing one is a path that went wrong in a move, and a
# warning here would ship a launcher without it (issue #440, phase 0).
if (-not (Test-Path $logo))    { Die "logo.png is not at $logo. It is in the repository, so the path is wrong; the launcher would ship without its emblem." }
if (-not (Test-Path $logoSml)) { $logoSml = $logo }
# The dev build's own emblem and icon (Djinn, 25 Sep). The same exe serves both
# builds, so both go in and Art.Dev picks at run time. The exe's own file icon
# (/win32icon) stays app.ico: Windows reads that from the file, not at run time.
$logoDev = Join-Path $Here '..\..\launcher\logo-dev.png'
$iconDev = Join-Path $Here '..\..\launcher\app-dev.ico'
if (-not (Test-Path $logoDev)) { Die "logo-dev.png is not at $logoDev. It is in the repository, so the path is wrong; the dev launcher would show the main emblem." }
if (-not (Test-Path $iconDev)) { Die "app-dev.ico is not at $iconDev. It is in the repository, so the path is wrong; dev shortcuts would show the main icon." }
# The landscape behind the title on the Play page. Optional the same way:
# without it the band keeps its pattern.
$headerArt = Join-Path $Here '..\..\launcher\launcher-header.jpg'
if (-not (Test-Path $headerArt)) { Die "launcher-header.jpg is not at $headerArt. It is in the repository, so the path is wrong." }
# The same strip moving, over the picture. Optional too: without it the band
# keeps the still picture.
$headerVideo = Join-Path $Here '..\..\launcher\launcher-header.mp4'
if (-not (Test-Path $headerVideo)) { Die "launcher-header.mp4 is not at $headerVideo. It is in the repository, so the path is wrong." }
Say "  $($cs.Count) source files" 'Green'

$null = New-Item -ItemType Directory -Force -Path $outDir
$exe = Join-Path $outDir 'Thornswood.exe'

# Nothing is closed here any more; Install-Launcher.ps1 does that, after a
# build that worked. So a launcher still running from this folder holds its own
# exe and csc cannot replace it. That is said plainly here, before any work,
# rather than left to csc's CS0016 at the end of a compile.
if (Test-Path -LiteralPath $exe) {
    try { $held = [IO.File]::Open($exe, 'Open', 'ReadWrite', 'None'); $held.Close() }
    catch { Die ("$exe is in use, most likely by the launcher running from that folder. A build closes nothing. " +
                 "Close it, or build somewhere else with -OutDir. Ship builds into a folder of its own and closes it for you.") }
}

# ------------------------------------------------------- what Windows shows
# csc gives an exe no version resource at all, so Windows has nothing to read
# off it: Explorer's Description column, the hover label, Task Manager and the
# properties dialog all fall back to the file name, and the file name is
# not what this is called any more. This writes the one source file that fills
# that in. It is generated rather than kept, so the version in it cannot drift
# from the one the updater reports.
$ver = '1.0.0'
$updaterCs = Join-Path $Src 'Updater.cs'
if (Test-Path $updaterCs) {
    $m = [regex]::Match((Get-Content $updaterCs -Raw), 'Version\s*=\s*"([0-9.]+)"')
    if ($m.Success) { $ver = $m.Groups[1].Value }
}
$verFour = $ver
while (($verFour -split '\.').Count -lt 4) { $verFour = "$verFour.0" }

# The application manifests (issue #463) carry a placeholder version. The one
# csc embeds is a copy with this build's four part version in assemblyIdentity,
# so the identity cannot drift from Updater.cs the way a kept number did
# (1.1.101.0 while the launcher was 1.1.102). Written before signing, because
# csc embeds it and signing comes after the compile.
function New-StampedManifest([string]$template, [string]$v4, [string]$leaf) {
    if (-not (Test-Path -LiteralPath $template)) { Die "$([IO.Path]::GetFileName($template)) is not at $template. It is in the repository, so the path is wrong; the exe would ship without its per-monitor DPI manifest." }
    $text = [IO.File]::ReadAllText($template)
    $rx = [regex]'(<assemblyIdentity\b[^>]*?\bversion=")[0-9.]+(")'
    if ($rx.Matches($text).Count -ne 1) { Die "$template does not have exactly one assemblyIdentity version to stamp." }
    $out = Join-Path $env:TEMP $leaf
    [IO.File]::WriteAllText($out, $rx.Replace($text, ('${1}' + $v4 + '${2}'), 1), (New-Object Text.UTF8Encoding($false)))
    $out
}

# Product and company default to Thornswood, which is what the launcher wants.
# The setup stub keeps its own Title/Product/Company/Copyright in Bootstrap.cs
# and gets FileVersion/ProductVersion from a generated ThornswoodSetupVersion.cs
# (see the setup-stub block below). New-Info is for the launcher only.
function New-Info([string]$path, [string]$title, [string]$desc, [string]$v4, [string]$v,
                  [string]$product = 'Thornswood', [string]$company = 'Thornswood', [string]$copyright = 'Thornswood') {
    $body = @"
using System.Reflection;
using System.Runtime.InteropServices;

// Written by Build-Launcher.ps1 on every build. Editing it does nothing.
[assembly: AssemblyTitle("$title")]
[assembly: AssemblyDescription("$desc")]
[assembly: AssemblyProduct("$product")]
[assembly: AssemblyCompany("$company")]
[assembly: AssemblyCopyright("$copyright")]
[assembly: AssemblyVersion("$v4")]
[assembly: AssemblyFileVersion("$v4")]
[assembly: AssemblyInformationalVersion("$v")]
[assembly: ComVisible(false)]
"@
    Set-Content -Path $path -Value $body -Encoding UTF8
}

# Only if nothing in the sources already declares these, because a second copy
# of an assembly attribute is a compile error rather than a warning.
$hasInfo = $false
foreach ($f in $cs) {
    if ((Get-Content $f.FullName -Raw) -match '(?m)^\s*\[assembly:') { $hasInfo = $true; break }
}
$infoApp = $null
if (-not $hasInfo) {
    $infoApp = Join-Path $env:TEMP 'ThornswoodInfo.cs'
    New-Info $infoApp 'Thornswood' 'Thornswood launcher' $verFour $ver
    Say "  file details say Thornswood $ver" 'DarkGray'
} else {
    Say '  a source file already sets the assembly details, leaving them alone' 'DarkGray'
}

# From here to the signing is the build itself, csc's way or MSBuild's
# (-With). The csc half is left at the margin it always had, so the switch
# (#498) is the deletion of this one block and nothing else moves.
if ($With -eq 'csc') {
# ------------------------------------------------------------ compile
Head 'Compiling'
# /noconfig: csc otherwise reads its own csc.rsp and adds System, System.Core,
# System.Drawing and a dozen more by name from the framework folder. On a
# machine with the .NET reference assemblies installed (the GitHub runner, any
# machine with Visual Studio) the list above found those same assemblies under
# Reference Assemblies, and csc stopped with CS1703, one identity imported
# twice. Everything the launcher needs is in $refs by hand, so csc.rsp has
# nothing to add.
# Application manifest: PerMonitorV2 DPI, supportedOS through Win10/11, asInvoker,
# identity version stamped from Updater.cs (New-StampedManifest above).
# /win32icon can stay beside /win32manifest; /win32res would conflict (issue #463).
$manifest = New-StampedManifest (Join-Path $Src 'Thornswood.manifest') $verFour 'Thornswood.stamped.manifest'
Say "  manifest identity Thornswood.Launcher.Thornswood $verFour" 'DarkGray'
$cscArgs = @(
    '/noconfig', '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', '/debug:pdbonly',
    "/out:$exe",
    "/win32icon:$((Resolve-Path $icon).Path)",
    "/win32manifest:$((Resolve-Path $manifest).Path)",
    "/resource:$((Resolve-Path $xaml).Path),ui.xaml"
)
if (Test-Path $logo) { $cscArgs += "/resource:$((Resolve-Path $logo).Path),logo.png" }
$cscArgs += "/resource:$((Resolve-Path $logoDev).Path),logo-dev.png"
if (Test-Path $headerArt) { $cscArgs += "/resource:$((Resolve-Path $headerArt).Path),launcher-header.jpg" }
if (Test-Path $headerVideo) { $cscArgs += "/resource:$((Resolve-Path $headerVideo).Path),launcher-header.mp4" }
# The artwork goes in as a resource as well as a win32 icon, because the
# launcher writes it back out beside itself under a name derived from its own
# contents. That is what stops Windows showing a remembered picture of the old
# one, and it has to travel with the update rather than sit loose in a folder.
$cscArgs += "/resource:$((Resolve-Path $icon).Path),app.ico"
$cscArgs += "/resource:$((Resolve-Path $iconDev).Path),app-dev.ico"

# WebView2 travels inside the exe. Voice.cs hands the two managed ones back to
# the CLR from an AssemblyResolve handler, and writes the native loader out
# beside the exe on startup, because a native DLL cannot be loaded from memory.
foreach ($n in ($wv2Managed + $wv2Loader)) {
    $cscArgs += "/resource:$((Resolve-Path (Join-Path $wv2Dir $n)).Path),$n"
}

# The voice page rides along too, for the same reason: one published asset.
$voicePage = Join-Path $Here '..\..\launcher\voice-host.html'
if (-not (Test-Path -LiteralPath $voicePage)) { Die "Missing launcher\voice-host.html" }
$cscArgs += "/resource:$((Resolve-Path $voicePage).Path),voice-host.html"

# The template Thornswood.ini, for a machine that has none. The launcher
# writes it when it is missing
# (ThornIni.Ensure), so the ini never has to travel in a pack, which is how
# one machine's binds and field of view landed on everybody on 16 Sep.
$iniTemplate = Join-Path $Here '..\..\launcher\Thornswood.ini'
if (Test-Path -LiteralPath $iniTemplate) {
    $cscArgs += "/resource:$((Resolve-Path $iniTemplate).Path),Thornswood.ini"
} else {
    Die "Thornswood.ini is not at $iniTemplate. It is in the repository, so the path is wrong; a machine with no Thornswood.ini would play on the plugins' own defaults."
}

# The record of which SkyMP client runtime belongs beside this launcher.
#
# IT TRAVELS IN THE EXE AND NOT AS A FILE, on purpose. The launcher, the game
# files and the server go out as one release, so the launcher that is running
# IS the statement of which client belongs with it, and there is no second copy
# on disk to drift out of step or to be edited on somebody's machine.
#
# ClientRuntime reads it back out and checks the six files by hash. Without it
# the launcher cannot tell which build of skymp5-client.js it has, which is
# what the old text search for "THORNSWOOD PATCH" could never answer, and it
# cannot put a missing one back either. A build without it still runs and says
# so on the Play page rather than pretending the client is fine.
$clientRecord = Join-Path $Here '..\..\records\client-build.json'
if (Test-Path -LiteralPath $clientRecord) {
    $cscArgs += "/resource:$((Resolve-Path $clientRecord).Path),client-build.json"
} else {
    Die "client-build.json is not at $clientRecord. It is in the repository, so the path is wrong; the launcher could not check or repair the client runtime."
}

# Every file of the pinned Skyrim build, from the depot manifests the Downgrade
# asks Steam for (New-SkyrimFilesRecord.ps1, issue #1232). OwnGame reads it to
# tell Skyrim's own files from mods put into the Steam copy by hand, and makes
# and refreshes nothing without it.
$skyrimRecord = Join-Path $Here '..\..\records\skyrim-files.json'
# RecordShape.ps1 (#2180): the two records compiled into the launcher must be
# a version this checkout knows with every field OwnGame reads, or the build
# stops here; a launcher with a half-read list in it is worse than none.
. (Join-Path $Here 'RecordShape.ps1')
foreach ($embedded in @(@{ Path = $skyrimRecord; Kind = 'skyrim-files' }, @{ Path = (Join-Path $Here '..\..\records\ui-gone.json'); Kind = 'ui-gone' })) {
    if (Test-Path -LiteralPath $embedded.Path) {
        try { $null = Read-ThornswoodRecord -Path $embedded.Path -Kind $embedded.Kind } catch { Die ($_.Exception.Message + ' Nothing was built.') }
    }
}
if (Test-Path -LiteralPath $skyrimRecord) {
    $cscArgs += "/resource:$((Resolve-Path $skyrimRecord).Path),skyrim-files.json"
} else {
    Die "skyrim-files.json is not at $skyrimRecord. It is in the repository, so the path is wrong; the launcher could not tell Skyrim's own files from mods put into the Steam copy by hand."
}

# The Daedric menu set and unused fork assets (#1318). OwnGame.Foreign and
# Ship-Rules.ps1 both read this one file, so the two cannot drift.
$uiGoneRecord = Join-Path $Here '..\..\records\ui-gone.json'
if (Test-Path -LiteralPath $uiGoneRecord) {
    $cscArgs += "/resource:$((Resolve-Path $uiGoneRecord).Path),ui-gone.json"
} else {
    Die "ui-gone.json is not at $uiGoneRecord. It is in the repository, so the path is wrong; the launcher could not keep another server's menu files out of a refresh."
}

foreach ($r in $refs) { $cscArgs += "/reference:$r" }
foreach ($f in $cs)   { $cscArgs += $f.FullName }
if ($infoApp) { $cscArgs += $infoApp }

$old = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $csc @cscArgs
$rc = $LASTEXITCODE
$ErrorActionPreference = $old

if ($rc -ne 0 -or -not (Test-Path $exe)) { Die "csc.exe exited with $rc" }
Say ("  Thornswood.exe  {0:n0} KB" -f ((Get-Item $exe).Length / 1KB)) 'Green'
$pdb = [IO.Path]::ChangeExtension($exe, '.pdb')
if (Test-Path -LiteralPath $pdb) {
    Say ("  Thornswood.pdb  {0:n0} KB (kept beside the exe; packs and the installer leave it out)" -f ((Get-Item $pdb).Length / 1KB)) 'DarkGray'
} else {
    Say '  Thornswood.pdb did not appear beside the exe' 'Yellow'
}

# ------------------------------------------------------------ setup stub
$stubSrc = Join-Path $Here '..\..\installer\setup\Bootstrap.cs'
if (-not (Test-Path $stubSrc)) { Die "Bootstrap.cs is not at $stubSrc. It is in the repository, so the path is wrong; a package built now would have no installer in it." }
Head 'Setup stub'
# Built to a scratch name first. Deleting the old one up front meant a
# failed compile left no installer at all, and the only sign of it was a
# red STOP an hour before anyone noticed the package had no exe in it.
#
# The scratch name is the name it ships under, Thornswood-Setup.exe, not a
# setup-stub name, because csc writes the exe's OriginalFilename and
# InternalName version fields from the /out leaf. Package-Thornswood.ps1
# copies out\setup-stub.exe to Thornswood-Setup.exe without recompiling,
# so if it were built as setup-stub.exe those two fields would read a name
# nobody ever downloads. Built under the shipped name in %TEMP% and then
# moved onto out\setup-stub.exe, which is what packaging copies from. out\ is
# the build output, the folder Where.ps1 calls Out, ignored by git; until
# 29 September the stub sat in tools\ (issue #440, phase 10).
$stubDir = Join-Path $Here '..\..\out'
New-Item -ItemType Directory -Force -Path $stubDir | Out-Null
$stub = Join-Path $stubDir 'setup-stub.exe'
if ($StubOut) { $stub = $StubOut; New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stub) | Out-Null }
$stubNew = Join-Path $env:TEMP 'Thornswood-Setup.exe'
if (Test-Path $stubNew) { Remove-Item $stubNew -Force }
$stubArgs = @('/noconfig', '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+', '/debug:pdbonly',
              "/out:$stubNew", "/win32icon:$((Resolve-Path $icon).Path)")
if (Test-Path $logoSml) { $stubArgs += "/resource:$((Resolve-Path $logoSml).Path),logo.png" }
foreach ($r in $refs) { $stubArgs += "/reference:$r" }
# Bootstrap.cs keeps the stable product NAME (Title/Product/Company/
# Copyright). FileVersion and ProductVersion are stamped here from
# Updater.cs ($ver / $verFour) so the stub tracks the launcher release.
# A version-only .cs is always generated; do NOT call New-Info for the
# stub (that would duplicate Title/Product and fail csc).
$stubVerCs = Join-Path $env:TEMP 'ThornswoodSetupVersion.cs'
$stubVerBody = @"
using System.Reflection;
[assembly: AssemblyVersion("$verFour")]
[assembly: AssemblyFileVersion("$verFour")]
[assembly: AssemblyInformationalVersion("$ver")]
"@
Set-Content -Path $stubVerCs -Value $stubVerBody -Encoding ASCII
$stubArgs += (Resolve-Path $stubSrc).Path
$stubArgs += $stubVerCs
# Its own manifest (issue #463): per-monitor DPI and asInvoker, identity
# Thornswood.Installer.Setup at this version. Without it csc embedded its
# default, MyApplication.app 1.0.0.0 with no DPI awareness. And the launcher's
# WindowFit.cs, which keeps the window inside the screen at any scale; it uses
# nothing else from launcher\app.
$stubManifest = New-StampedManifest (Join-Path $Here '..\..\installer\setup\Setup.manifest') $verFour 'ThornswoodSetup.stamped.manifest'
$stubArgs += "/win32manifest:$stubManifest"
$stubArgs += (Resolve-Path (Join-Path $Src 'WindowFit.cs')).Path

$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $csc @stubArgs
$rc2 = $LASTEXITCODE
$ErrorActionPreference = $old
if ($rc2 -ne 0 -or -not (Test-Path $stubNew)) {
    Remove-Item $stubNew -Force -EA SilentlyContinue
    Write-Host ''
    Say "  csc exited with $rc2. The installer program did NOT build." 'Red'
    if (Test-Path $stub) {
        Die 'setup-stub.exe did not rebuild. The last working copy is still here, but a release must not ship on a failed stub build. Fix the compile error above and run Build-Launcher again.'
    } else {
        Die 'There is no setup-stub.exe at all. A package built now would have no installer in it. Fix the compile error above and run Build-Launcher again.'
    }
}
else {
    if (Test-Path $stub) { Remove-Item $stub -Force }
    Move-Item $stubNew $stub
    Say ("  setup-stub.exe  {0:n0} KB" -f ((Get-Item $stub).Length / 1KB)) 'Green'
    $stubPdbNew = [IO.Path]::ChangeExtension($stubNew, '.pdb')
    $stubPdb = [IO.Path]::ChangeExtension($stub, '.pdb')
    if (Test-Path -LiteralPath $stubPdbNew) {
        if (Test-Path -LiteralPath $stubPdb) { Remove-Item -LiteralPath $stubPdb -Force }
        Move-Item -LiteralPath $stubPdbNew -Destination $stubPdb
        Say ("  setup-stub.pdb  {0:n0} KB (shipping machine only)" -f ((Get-Item $stubPdb).Length / 1KB)) 'DarkGray'
    }
}
} else {
# ------------------------------------------------------------ MSBuild
# The same two exes from the two project files. What goes into each (sources,
# references, resources, icon, stamped manifest, file details) is written in
# the project files themselves, so this half is only the two build lines and
# the setup program's move onto setup-stub.exe.
Head 'Compiling with MSBuild'
. (Join-Path $Here 'Find-MSBuild.ps1') -Load
$found = Find-ThornswoodMSBuild
if (-not $found.MSBuild) { Die 'MSBuild was not found on this machine. -With msbuild needs Visual Studio 2022 or its Build Tools with the MSBuild component; Developer-Guide.md "Setting up a machine" has the install line. -With csc still builds.' }
if (-not $found.RefAssemblies) { Die 'The .NET Framework 4.8.1 reference assemblies are not on this machine. They are the Build Tools component Microsoft.Net.Component.4.8.1.TargetingPack; Developer-Guide.md "Setting up a machine" has the install line.' }
Say "  $($found.MSBuild)" 'DarkGray'
$proj = Join-Path $Src 'Thornswood.csproj'
$stubProj = Join-Path $Here '..\..\installer\setup\Setup.csproj'
foreach ($p in @($proj, $stubProj)) {
    if (-not (Test-Path -LiteralPath $p)) { Die "$([IO.Path]::GetFileName($p)) is not at $p. It is in the repository, so the path is wrong; nothing was built." }
}
# -nr:false: without it MSBuild leaves its worker processes running after the
# build, holding files under out\obj, and a runner names them as left behind.
$msbArgs = @('-nologo', '-v:minimal', '-nr:false', '-p:Configuration=Release')
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $found.MSBuild (Resolve-Path -LiteralPath $proj).Path @msbArgs ('-p:OutDir=' + $outDir.TrimEnd('\') + '\')
$rc = $LASTEXITCODE
$ErrorActionPreference = $old
if ($rc -ne 0 -or -not (Test-Path $exe)) { Die "MSBuild exited with $rc" }
Say ("  Thornswood.exe  {0:n0} KB" -f ((Get-Item $exe).Length / 1KB)) 'Green'

Head 'Setup stub'
# Built under the name it ships as (the project's AssemblyName is
# Thornswood-Setup, for OriginalFilename), into a scratch folder, then moved
# onto setup-stub.exe; a failed build leaves the last working copy, as above.
$stub = Join-Path (Join-Path $Here '..\..\out') 'setup-stub.exe'
if ($StubOut) { $stub = $StubOut }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stub) | Out-Null
$stubBuild = Join-Path $env:TEMP 'ThornswoodSetupBuild'
if (Test-Path -LiteralPath $stubBuild) { Remove-Item -LiteralPath $stubBuild -Recurse -Force }
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
& $found.MSBuild (Resolve-Path -LiteralPath $stubProj).Path @msbArgs ('-p:OutDir=' + $stubBuild + '\')
$rc2 = $LASTEXITCODE
$ErrorActionPreference = $old
$stubNew = Join-Path $stubBuild 'Thornswood-Setup.exe'
if ($rc2 -ne 0 -or -not (Test-Path -LiteralPath $stubNew)) {
    Write-Host ''
    Say "  MSBuild exited with $rc2. The installer program did NOT build." 'Red'
    if (Test-Path $stub) {
        Die 'setup-stub.exe did not rebuild. The last working copy is still here, but a release must not ship on a failed stub build. Fix the compile error above and run Build-Launcher again.'
    } else {
        Die 'There is no setup-stub.exe at all. A package built now would have no installer in it. Fix the compile error above and run Build-Launcher again.'
    }
}
if (Test-Path $stub) { Remove-Item $stub -Force }
Move-Item -LiteralPath $stubNew -Destination $stub
Say ("  setup-stub.exe  {0:n0} KB" -f ((Get-Item $stub).Length / 1KB)) 'Green'
$stubPdb = [IO.Path]::ChangeExtension($stub, '.pdb')
if (Test-Path -LiteralPath $stubPdb) { Remove-Item -LiteralPath $stubPdb -Force }
Move-Item -LiteralPath ([IO.Path]::ChangeExtension($stubNew, '.pdb')) -Destination $stubPdb
Remove-Item -LiteralPath $stubBuild -Recurse -Force
}

# ------------------------------------------------------------ signing
#
# Sign the launcher here. Do NOT sign setup-stub.exe.
#
# Package-Thornswood.ps1 -OneFile copies the stub, appends the payload and a
# trailer, then signs Thornswood-Setup.exe. Authenticode cannot survive that
# append: a pre-signed stub makes the combined file un-signable (signtool
# 0x800700C1). Measured 27 September on Main Package. The stub stays unsigned
# on disk; Package signs the final Setup after attach, and the two-file path
# signs the copied Setup the same way. A stranger still gets a signed installer
# from the site; this machine's out\setup-stub.exe is only a build input.
#
# This does nothing at all unless records\signing\signing.json exists, so Djinn's machine
# and the pull request build carry on exactly as before. See the header of
# Sign-Artifact.ps1 for what that file holds, and Bootstrap.cs:112-121 for why
# any of this matters.
$signer = Join-Path $Here 'Sign-Artifact.ps1'
if ($NoSign) {
    Say '  not signing: -NoSign, a comparison build that never ships' 'DarkGray'
} elseif (Test-Path -LiteralPath $signer) {
    Head 'Signing'
    & $signer -Path $exe
    if ($LASTEXITCODE -ne 0) { Die 'Signing failed. Nothing was published.' }
}

# The shortcut, the icon file beside the exe, Explorer's redraw and its icon
# cache used to follow here. They are Install-Launcher.ps1 now, with the
# closing of a running game and launcher, because they are what an install
# does and a build has no business doing them.

Head 'Done'
Say $exe 'Green'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }

# Said out loud rather than left to chance.
#
# A PowerShell script that runs off the end does not reset $LASTEXITCODE: the
# caller sees whatever the last native command left behind, and this script runs
# csc and signtool. Ship.ps1 reads that code to decide whether a release may go
# out, so a stray value here would either hide a failure or stop a good build
# for no reason.
exit 0
