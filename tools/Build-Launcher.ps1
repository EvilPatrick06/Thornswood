<#
  Build-Launcher.ps1
  Compiles the launcher into a real SkyrimTogether.exe.

  Uses csc.exe, which is part of the .NET Framework that ships inside Windows.
  Nothing to install. Your friends never compile anything - they get the
  finished exe in the bundle.
#>
[CmdletBinding()]
param(
    [string]$Src,
    [string]$Root = 'C:\SkyrimTogether'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $MyInvocation is not usable from inside a param block, so the script folder
# is worked out here instead.
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Src)  { $Src  = Join-Path $Here 'app' }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; [void](Read-Host 'Enter to exit'); exit 1 }

Head 'Skyrim Together - launcher build'

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
    'System.IO.Compression.dll', 'System.IO.Compression.FileSystem.dll',
    'PresentationFramework.dll', 'PresentationCore.dll', 'WindowsBase.dll', 'System.Xaml.dll'
)
$refs = @()
$missing = @()
foreach ($n in $needed) {
    $p = Find-Ref $n
    if ($p) { $refs += $p } else { $missing += $n }
}
if ($missing.Count) { Die ("Could not find these assemblies: " + ($missing -join ', ')) }
Say "  $($refs.Count) references resolved" 'Green'
foreach ($r in $refs) { Say "    $r" 'DarkGray' }

# ------------------------------------------------------------ sources
$cs = @(Get-ChildItem (Join-Path $Src '*.cs') -File)
if (-not $cs.Count) { Die "No .cs files under $Src" }
$xaml = @((Join-Path $Here 'ui.xaml'), (Join-Path $Src 'ui.xaml')) | Where-Object { Test-Path $_ } | Select-Object -First 1
$icon = @((Join-Path $Here 'app.ico'), (Join-Path $Src 'app.ico')) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $xaml) { Die "ui.xaml was not found next to this script or in $Src" }
if (-not $icon) { Die "app.ico was not found next to this script or in $Src" }
Say "  $($cs.Count) source files" 'Green'

$outDir = Join-Path $Root 'Launcher'
$null = New-Item -ItemType Directory -Force -Path $outDir
$exe = Join-Path $outDir 'SkyrimTogether.exe'

if (Get-Process -Name 'SkyrimTogether' -EA SilentlyContinue) { Die 'The launcher is running. Close it and try again.' }

# ------------------------------------------------------------ compile
Head 'Compiling'
$cscArgs = @(
    '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+',
    "/out:$exe",
    "/win32icon:$((Resolve-Path $icon).Path)",
    "/resource:$((Resolve-Path $xaml).Path),ui.xaml"
)
foreach ($r in $refs) { $cscArgs += "/reference:$r" }
foreach ($f in $cs)   { $cscArgs += $f.FullName }

$old = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $csc @cscArgs
$rc = $LASTEXITCODE
$ErrorActionPreference = $old

if ($rc -ne 0 -or -not (Test-Path $exe)) { Die "csc.exe exited with $rc" }
Say ("  SkyrimTogether.exe  {0:n0} KB" -f ((Get-Item $exe).Length / 1KB)) 'Green'

# ------------------------------------------------------------ setup stub
$stubSrc = Join-Path $Here 'setup\Bootstrap.cs'
if (Test-Path $stubSrc) {
    Head 'Setup stub'
    $stub = Join-Path $Here 'setup-stub.exe'
    if (Test-Path $stub) { Remove-Item $stub -Force }
    $stubArgs = @('/nologo', '/target:winexe', '/platform:anycpu', '/optimize+',
                  "/out:$stub", "/win32icon:$((Resolve-Path $icon).Path)")
    foreach ($r in $refs) { $stubArgs += "/reference:$r" }
    $stubArgs += (Resolve-Path $stubSrc).Path

    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $csc @stubArgs
    $rc2 = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($rc2 -ne 0 -or -not (Test-Path $stub)) { Say "  csc exited with $rc2, the installer will fall back to 7-Zip" 'Yellow' }
    else { Say ("  setup-stub.exe  {0:n0} KB" -f ((Get-Item $stub).Length / 1KB)) 'Green' }
}

# ------------------------------------------------------------ shortcut
Head 'Shortcut'
$ws = New-Object -ComObject WScript.Shell
foreach ($dest in @([Environment]::GetFolderPath('Desktop'), $Root)) {
    $sc = $ws.CreateShortcut((Join-Path $dest 'Skyrim Together.lnk'))
    $sc.TargetPath       = $exe
    $sc.Arguments        = ''
    $sc.WorkingDirectory = $outDir
    $sc.IconLocation     = "$exe,0"
    $sc.Description      = 'Skyrim Together'
    $sc.Save()
}
Say '  Points at the exe now, no PowerShell in the chain' 'Green'

$stale = Join-Path $outDir 'SkyrimTogether-Launcher.ps1'
if (Test-Path $stale) { Remove-Item $stale -Force; Say '  Removed the old script launcher' 'DarkGray' }

Head 'Done'
Say $exe 'Green'
Write-Host ''
[void](Read-Host 'Enter to close')
