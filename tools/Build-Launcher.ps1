<#
  Build-Launcher.ps1
  Compiles the launcher into a real Thornswood.exe.

  Uses csc.exe, which is part of the .NET Framework that ships inside Windows.
  Nothing to install. Your friends never compile anything - they get the
  finished exe in the bundle.
#>
[CmdletBinding()]
param(
    [string]$Src,
    [string]$Root = 'C:\Thornswood',
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $MyInvocation is not usable from inside a param block, so the script folder
# is worked out here instead.
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Src)  { $Src  = Join-Path $Here 'app' }
. (Join-Path $Here 'Close-Launcher.ps1')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

Head 'Thornswood - launcher build'

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
$wv2Dir = Join-Path $Here 'lib\webview2'
$wv2Managed = @('Microsoft.Web.WebView2.Core.dll', 'Microsoft.Web.WebView2.Wpf.dll')
$wv2Loader  = 'WebView2Loader.dll'
$wv2Missing = @()
foreach ($n in ($wv2Managed + $wv2Loader)) {
    if (-not (Test-Path -LiteralPath (Join-Path $wv2Dir $n))) { $wv2Missing += $n }
}
if ($wv2Missing.Count) {
    Die ("WebView2 files are missing from tools\lib\webview2: " + ($wv2Missing -join ', '))
}
foreach ($n in $wv2Managed) { $refs += (Join-Path $wv2Dir $n) }

Say "  $($refs.Count) references resolved" 'Green'
foreach ($r in $refs) { Say "    $r" 'DarkGray' }

# ------------------------------------------------------------ sources
$cs = @(Get-ChildItem (Join-Path $Src '*.cs') -File)
if (-not $cs.Count) { Die "No .cs files under $Src" }
$xaml = @((Join-Path $Here 'ui.xaml'), (Join-Path $Src 'ui.xaml')) | Where-Object { Test-Path $_ } | Select-Object -First 1
$icon = @((Join-Path $Here 'app.ico'), (Join-Path $Src 'app.ico')) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $xaml) { Die "ui.xaml was not found next to this script or in $Src" }
if (-not $icon) { Die "app.ico was not found next to this script or in $Src" }

# The emblem is compiled in rather than shipped beside the exe, so the update
# that replaces the launcher brings its own artwork and there is no second file
# to go missing. Both are optional: without them the launcher falls back to the
# game's own icon and simply does not draw an emblem.
$logo    = Join-Path $Here 'logo.png'
$logoSml = Join-Path $Here 'logo-192.png'
if (-not (Test-Path $logo))    { Say '  logo.png is missing, the launcher will run without its emblem' 'Yellow' }
if (-not (Test-Path $logoSml)) { $logoSml = $logo }
Say "  $($cs.Count) source files" 'Green'

$outDir = Join-Path $Root 'Launcher'
$null = New-Item -ItemType Directory -Force -Path $outDir
# Thornswood.exe since the move off Skyrim Together. An install made before the
# rename still has the old name, because the launcher replaces itself in place
# when it updates rather than being reinstalled, so the old one is cleared out
# here to stop two launchers sitting in the same folder.
$exe = Join-Path $outDir 'Thornswood.exe'
$oldExe = Join-Path $outDir 'SkyrimTogether.exe'

# Shared with the other scripts that write into the build. Both match on the
# full path, because the multiplayer client carries the same file name as the
# launcher and killing by name would take the game down with it.
$null = Stop-Game -Root $Root
$null = Stop-Launcher -Root $Root

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

function New-Info([string]$path, [string]$title, [string]$desc, [string]$v4, [string]$v) {
    $body = @"
using System.Reflection;
using System.Runtime.InteropServices;

// Written by Build-Launcher.ps1 on every build. Editing it does nothing.
[assembly: AssemblyTitle("$title")]
[assembly: AssemblyDescription("$desc")]
[assembly: AssemblyProduct("Thornswood")]
[assembly: AssemblyCompany("Thornswood")]
[assembly: AssemblyCopyright("Thornswood")]
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

# ------------------------------------------------------------ compile
Head 'Compiling'
$cscArgs = @(
    '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+',
    "/out:$exe",
    "/win32icon:$((Resolve-Path $icon).Path)",
    "/resource:$((Resolve-Path $xaml).Path),ui.xaml"
)
if (Test-Path $logo) { $cscArgs += "/resource:$((Resolve-Path $logo).Path),logo.png" }
# The artwork goes in as a resource as well as a win32 icon, because the
# launcher writes it back out beside itself under a name derived from its own
# contents. That is what stops Windows showing a remembered picture of the old
# one, and it has to travel with the update rather than sit loose in a folder.
$cscArgs += "/resource:$((Resolve-Path $icon).Path),app.ico"

# WebView2 travels inside the exe. Voice.cs hands the two managed ones back to
# the CLR from an AssemblyResolve handler, and writes the native loader out
# beside the exe on startup, because a native DLL cannot be loaded from memory.
foreach ($n in ($wv2Managed + $wv2Loader)) {
    $cscArgs += "/resource:$((Resolve-Path (Join-Path $wv2Dir $n)).Path),$n"
}

# The voice page rides along too, for the same reason: one published asset.
$voicePage = Join-Path $Here 'launcher\voice-host.html'
if (-not (Test-Path -LiteralPath $voicePage)) { Die "Missing tools\launcher\voice-host.html" }
$cscArgs += "/resource:$((Resolve-Path $voicePage).Path),voice-host.html"

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
if (Test-Path -LiteralPath $oldExe) {
    try {
        Remove-Item -LiteralPath $oldExe -Force
        Say '  removed the old SkyrimTogether.exe' 'DarkGray'
    } catch {
        Say '  could not remove the old SkyrimTogether.exe, it is probably still running' 'Yellow'
    }
}

# ------------------------------------------------------------ setup stub
$stubSrc = Join-Path $Here 'setup\Bootstrap.cs'
if (Test-Path $stubSrc) {
    Head 'Setup stub'
    # Built to a scratch name first. Deleting the old one up front meant a
    # failed compile left no installer at all, and the only sign of it was a
    # yellow line an hour before anyone noticed the package had no exe in it.
    $stub = Join-Path $Here 'setup-stub.exe'
    $stubNew = Join-Path $Here 'setup-stub.new.exe'
    if (Test-Path $stubNew) { Remove-Item $stubNew -Force }
    $stubArgs = @('/nologo', '/target:winexe', '/platform:anycpu', '/optimize+',
                  "/out:$stubNew", "/win32icon:$((Resolve-Path $icon).Path)")
    if (Test-Path $logoSml) { $stubArgs += "/resource:$((Resolve-Path $logoSml).Path),logo.png" }
    foreach ($r in $refs) { $stubArgs += "/reference:$r" }
    $stubInfo = $null
    if ((Get-Content $stubSrc -Raw) -notmatch '(?m)^\s*\[assembly:') {
        $stubInfo = Join-Path $env:TEMP 'ThornswoodSetupInfo.cs'
        New-Info $stubInfo 'Thornswood Setup' 'Thornswood setup' $verFour $ver
    }
    $stubArgs += (Resolve-Path $stubSrc).Path
    if ($stubInfo) { $stubArgs += $stubInfo }

    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $csc @stubArgs
    $rc2 = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($rc2 -ne 0 -or -not (Test-Path $stubNew)) {
        Remove-Item $stubNew -Force -EA SilentlyContinue
        Write-Host ''
        Say "  csc exited with $rc2. The installer program did NOT build." 'Red'
        if (Test-Path $stub) {
            Say '  The last working setup-stub.exe is still here, so packaging carries on with that one.' 'Yellow'
        } else {
            Say '  There is no setup-stub.exe at all. A package built now would have no installer in it.' 'Red'
        }
        Write-Host ''
    }
    else {
        if (Test-Path $stub) { Remove-Item $stub -Force }
        Move-Item $stubNew $stub
        Say ("  setup-stub.exe  {0:n0} KB" -f ((Get-Item $stub).Length / 1KB)) 'Green'
    }
}

# ------------------------------------------------------------ shortcut
Head 'Shortcut'

# Windows caches the bitmap it once drew for an icon against the path it came
# from. Point every build at one fixed "exe,0" and that cache key never
# changes, so a new icon inside the exe can go on being ignored for days, and
# a reboot does not clear it. Giving the icon its own file, named after its
# own contents, changes the key the moment the artwork changes and leaves it
# alone when it has not.
$iconHash = (Get-FileHash -Path $icon -Algorithm SHA256).Hash.Substring(0, 8).ToLower()
$iconFile = Join-Path $outDir ("icon-$iconHash.ico")
if (-not (Test-Path $iconFile)) { Copy-Item $icon $iconFile -Force }
foreach ($old in @(Get-ChildItem $outDir -Filter 'icon-*.ico' -ErrorAction SilentlyContinue)) {
    if ($old.Name -ne "icon-$iconHash.ico") { Remove-Item $old.FullName -Force -ErrorAction SilentlyContinue }
}
Say ("  icon-$iconHash.ico") 'DarkGray'

$ws = New-Object -ComObject WScript.Shell
foreach ($dest in @([Environment]::GetFolderPath('Desktop'), $Root)) {
    # The old name, tidied away so nobody ends up with two shortcuts to the
    # same launcher after the rename.
    $was = Join-Path $dest 'Skyrim Together.lnk'
    if (Test-Path $was) { Remove-Item $was -Force -ErrorAction SilentlyContinue }

    $sc = $ws.CreateShortcut((Join-Path $dest 'Thornswood.lnk'))
    $sc.TargetPath       = $exe
    $sc.Arguments        = ''
    $sc.WorkingDirectory = $outDir
    $sc.IconLocation     = "$iconFile,0"
    $sc.Description      = 'Thornswood'
    $sc.Save()
}
Say '  Points at the exe now, no PowerShell in the chain' 'Green'

# Telling the shell an association changed is what actually makes Explorer
# redraw, and unlike clearing the cache it costs nothing and interrupts
# nobody. ie4uinit stays as a second opinion.
try {
    if (-not ([System.Management.Automation.PSTypeName]'Thornswood.Shell32').Type) {
        Add-Type -Namespace Thornswood -Name Shell32 -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Auto)]
public static extern void SHChangeNotify(int eventId, uint flags, System.IntPtr item1, System.IntPtr item2);
'@
    }
    [Thornswood.Shell32]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)
    Say '  Explorer told to redraw' 'DarkGray'
} catch { }

try {
    $ie4 = Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
    if (Test-Path $ie4) {
        $global:LASTEXITCODE = 0
        & $ie4 -show 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { & $ie4 -ClearIconCache 2>&1 | Out-Null }
        Say '  Icon cache asked to refresh' 'DarkGray'
    }
} catch { }

# The belt and braces pass, only when the artwork itself is new. Clearing the
# cache means closing Explorer for a second, which is too rude to do on every
# build but exactly right on the one build where the icon changed.
$stamp    = Join-Path $outDir '.iconstamp'
$lastIcon = ''
if (Test-Path $stamp) { $lastIcon = (Get-Content $stamp -Raw -ErrorAction SilentlyContinue).Trim() }
if ($lastIcon -ne $iconHash) {
    Say '  New artwork, clearing the cache properly' 'Yellow'
    try {
        taskkill /f /im explorer.exe 2>&1 | Out-Null
        $caches = @(
            (Join-Path $env:LocalAppData 'IconCache.db'),
            (Join-Path $env:LocalAppData 'Microsoft\Windows\Explorer\iconcache_*.db')
        )
        foreach ($c in $caches) {
            foreach ($f in @(Get-ChildItem $c -Force -ErrorAction SilentlyContinue)) {
                Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { }
    try { Start-Process explorer.exe } catch { }
    Set-Content -Path $stamp -Value $iconHash -Encoding ASCII
    Say '  Explorer restarted, icon is the new one' 'Green'
}

$stale = Join-Path $outDir 'SkyrimTogether-Launcher.ps1'
if (Test-Path $stale) { Remove-Item $stale -Force; Say '  Removed the old script launcher' 'DarkGray' }

Head 'Done'
Say $exe 'Green'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
