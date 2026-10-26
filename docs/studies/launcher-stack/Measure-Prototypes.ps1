<#
.SYNOPSIS
  Builds every prototype of the launcher stack study (#3209) on this Windows
  machine and measures what a person would notice: how big each one is, how
  long its window takes to show, how much memory it holds, and what the
  Windows Volume Mixer shows for its sound.

.DESCRIPTION
  Every toolchain it needs goes under -Work, nothing is installed for the
  machine and nothing outside -Work is written, apart from the web view data
  folders the web view stacks make for themselves under %LOCALAPPDATA% (the
  script names and removes them at the end). Visual Studio's C++ build tools
  must already be there (One has them for the engine); the script stops and
  says so when they are not.

  For each prototype it then runs the exe -Runs times. A run waits for the
  prototype to write its ready file (README.md, "The contract"), which it does
  once its first frame with the art is on screen, and takes that wait as the
  start time. Three seconds later it reads the memory of the prototype and
  every process under it (idle). The prototype starts its music and a
  stand-in for Play at four seconds; at eight seconds the memory is read again
  (active) together with every Windows audio session that belongs to the
  prototype's processes, which is what the Volume Mixer lists. Then the
  process tree is closed. The first run of each prototype is reported on its
  own (the first start after a build), the rest as a median.

  The music is a quiet hiss a few steps above silence, so a run makes an
  audio session without being heard.

  It writes results.json and results.md into -Work. results.md is what goes
  on the issue.

.PARAMETER Work
  Where the toolchains, builds and results go. Removed by -Clean.

.PARAMETER Only
  Build and measure only these prototypes (names as in the table of
  README.md, for example tauri, wpf-net10).

.PARAMETER Runs
  Runs per prototype, the first included. Five by default.

.PARAMETER MeasureOnly
  Measure the builds already in -Work without building again.

.PARAMETER Clean
  Remove -Work and the web view data folders, and do nothing else.

.EXAMPLE
  pwsh -File docs\studies\launcher-stack\Measure-Prototypes.ps1
#>
[CmdletBinding()]
param(
    [string]$Work = 'C:\ThornswoodTemps&Worktrees\temp\3209-launcher-stack',
    [string[]]$Only,
    [int]$Runs = 5,
    [switch]$MeasureOnly,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Study = $PSScriptRoot
$Proto = Join-Path $Study 'prototypes'
$Repo = (Resolve-Path (Join-Path $Study '..\..\..')).Path
$Tools = Join-Path $Work 'tools'
$Out = Join-Path $Work 'out'
$Art = Join-Path $Repo 'launcher\art\thornswood-art-1536.png'

# The web view data folders the web view prototypes make for themselves, by
# the identifier or exe name each one runs under.
$WebViewData = @(
    (Join-Path $env:LOCALAPPDATA 'net.thornswood.proto.tauri'),
    (Join-Path $env:LOCALAPPDATA 'proto-wails.exe'),
    (Join-Path $env:APPDATA 'proto-electron'),
    (Join-Path $env:TEMP 'proto-wpf-net481-webview2-webview'),
    (Join-Path $env:TEMP 'proto-wpf-net10-webview2-webview')
)

if ($Clean) {
    foreach ($p in @($Work) + $WebViewData) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force; Write-Host "removed $p" }
    }
    return
}

function Say([string]$text) { Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $text) }

function Invoke-Checked([string]$what, [scriptblock]$block) {
    Say $what
    & $block
    if ($LASTEXITCODE -ne 0) { throw "$what failed with exit code $LASTEXITCODE" }
}

function Get-File([string]$url, [string]$to) {
    if (Test-Path -LiteralPath $to) { return }
    Say "download $url"
    Invoke-WebRequest -Uri $url -OutFile "$to.part" -UseBasicParsing
    Move-Item -LiteralPath "$to.part" -Destination $to
}

# --- Toolchains -------------------------------------------------------------

function Find-VcVars {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio is not installed here (no vswhere.exe); the Rust, Qt, Flutter and Avalonia AOT builds need its C++ build tools.' }
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'Visual Studio has no C++ build tools (Microsoft.VisualStudio.Component.VC.Tools.x86.x64).' }
    Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
}

# Takes the environment vcvars64.bat makes into this session, so cl, link,
# cmake and ninja from Visual Studio are on PATH for every build below.
function Use-VcVars([string]$bat) {
    $lines = cmd.exe /c "`"$bat`" >nul && set"
    if ($LASTEXITCODE -ne 0) { throw "vcvars64.bat failed: $bat" }
    foreach ($l in $lines) {
        $i = $l.IndexOf('=')
        if ($i -gt 0) { [Environment]::SetEnvironmentVariable($l.Substring(0, $i), $l.Substring($i + 1), 'Process') }
    }
}

function Install-Tools {
    New-Item -ItemType Directory -Force -Path $Tools | Out-Null

    $dotnet = Join-Path $Tools 'dotnet'
    if (-not (Test-Path -LiteralPath (Join-Path $dotnet 'dotnet.exe'))) {
        $installer = Join-Path $Tools 'dotnet-install.ps1'
        Get-File 'https://dot.net/v1/dotnet-install.ps1' $installer
        Invoke-Checked 'install the .NET 10 SDK' { & $installer -Channel 10.0 -InstallDir $dotnet -NoPath; $global:LASTEXITCODE = 0 }
    }
    $env:DOTNET_ROOT = $dotnet
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    $env:DOTNET_NOLOGO = '1'
    $env:PATH = "$dotnet;$env:PATH"

    $env:RUSTUP_HOME = Join-Path $Tools 'rustup'
    $env:CARGO_HOME = Join-Path $Tools 'cargo'
    if (-not (Test-Path -LiteralPath (Join-Path $env:CARGO_HOME 'bin\cargo.exe'))) {
        $rustup = Join-Path $Tools 'rustup-init.exe'
        Get-File 'https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe' $rustup
        Invoke-Checked 'install Rust' { & $rustup -y --no-modify-path --profile minimal --default-toolchain stable }
    }
    $env:PATH = "$(Join-Path $env:CARGO_HOME 'bin');$env:PATH"

    $go = Join-Path $Tools 'go'
    if (-not (Test-Path -LiteralPath (Join-Path $go 'bin\go.exe'))) {
        $zip = Join-Path $Tools 'go.zip'
        Get-File 'https://go.dev/dl/go1.27.3.windows-amd64.zip' $zip
        Say 'unpack Go'
        Expand-Archive -LiteralPath $zip -DestinationPath $Tools
    }
    $env:GOROOT = $go
    $env:GOPATH = Join-Path $Tools 'gopath'
    $env:GOCACHE = Join-Path $Tools 'gocache'
    $env:PATH = "$(Join-Path $go 'bin');$env:PATH"

    $node = Join-Path $Tools 'node-v22.23.4-win-x64'
    if (-not (Test-Path -LiteralPath (Join-Path $node 'node.exe'))) {
        $zip = Join-Path $Tools 'node.zip'
        Get-File 'https://nodejs.org/dist/v22.23.4/node-v22.23.4-win-x64.zip' $zip
        Say 'unpack Node'
        Expand-Archive -LiteralPath $zip -DestinationPath $Tools
    }
    $env:PATH = "$node;$env:PATH"
    $env:npm_config_cache = Join-Path $Tools 'npm-cache'

    $flutter = Join-Path $Tools 'flutter'
    if (-not (Test-Path -LiteralPath (Join-Path $flutter 'bin\flutter.bat'))) {
        $zip = Join-Path $Tools 'flutter.zip'
        Get-File 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.8-stable.zip' $zip
        Say 'unpack Flutter'
        Expand-Archive -LiteralPath $zip -DestinationPath $Tools
    }
    $env:PATH = "$(Join-Path $flutter 'bin');$env:PATH"
    $env:PUB_CACHE = Join-Path $Tools 'pub-cache'
    $env:FLUTTER_SUPPRESS_ANALYTICS = 'true'

    # Qt through aqtinstall in its own Python environment. 6.10.2 is the
    # newest whose Windows packages aqtinstall could read on 26 Oct 2026.
    $qt = Join-Path $Tools 'qt\6.10.2\msvc2022_64'
    if (-not (Test-Path -LiteralPath (Join-Path $qt 'bin\windeployqt.exe'))) {
        $venv = Join-Path $Tools 'aqt'
        if (-not (Test-Path -LiteralPath (Join-Path $venv 'Scripts\python.exe'))) {
            $py = Get-Command py, python -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $py) { throw 'No Python here for aqtinstall (the Qt build).' }
            Invoke-Checked 'make the Python environment for aqtinstall' { & $py.Source -m venv $venv }
            Invoke-Checked 'install aqtinstall' { & (Join-Path $venv 'Scripts\python.exe') -m pip install --quiet aqtinstall }
        }
        Invoke-Checked 'install Qt 6.10.2' { & (Join-Path $venv 'Scripts\aqt.exe') install-qt windows desktop 6.10.2 win64_msvc2022_64 -O (Join-Path $Tools 'qt') }
    }
    $script:QtDir = $qt
}

# --- Builds -----------------------------------------------------------------

function Write-QuietWav([string]$to) {
    # Two seconds of 44.1 kHz stereo, 16 bit, a hiss of +/- 2 steps: an audio
    # session opens and plays, and nobody in the room hears it.
    $frames = 44100 * 2
    $data = New-Object byte[] ($frames * 4)
    $rand = [System.Random]::new(3209)
    for ($i = 0; $i -lt $data.Length; $i += 2) {
        $v = [int16]$rand.Next(-2, 3)
        $b = [BitConverter]::GetBytes($v)
        $data[$i] = $b[0]; $data[$i + 1] = $b[1]
    }
    $ms = [System.IO.MemoryStream]::new()
    $w = [System.IO.BinaryWriter]::new($ms)
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $data.Length))
    $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]2)
    $w.Write([int]44100); $w.Write([int](44100 * 4)); $w.Write([int16]4); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$data.Length); $w.Write($data)
    $w.Flush()
    [IO.File]::WriteAllBytes($to, $ms.ToArray())
}

function Add-Assets([string]$dir, [switch]$Page) {
    Copy-Item -LiteralPath $Art -Destination (Join-Path $dir 'art.png') -Force
    Copy-Item -LiteralPath $script:Wav -Destination (Join-Path $dir 'loop.wav') -Force
    if ($Page) { Copy-Item -LiteralPath (Join-Path $Proto 'web\index.html') -Destination $dir -Force }
}

function Reset-Dir([string]$dir) {
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

# Each build: the folder that is run (with the art and the music beside the
# exe, or inside it for the stacks that embed their page) and, where the
# assets are built into the exe, a second build without them that is only
# weighed. Sizes never count the art, the music, or debug symbols.
$Builds = [ordered]@{
    'wpf-net481-webview2' = {
        $o = Join-Path $Out 'wpf-net481-webview2'; Reset-Dir $o
        Invoke-Checked 'build wpf-net481-webview2' { dotnet publish (Join-Path $Proto 'wpf\wpf-net481-webview2.csproj') -c Release -o $o }
        Add-Assets $o -Page
    }
    'wpf-net10' = {
        $o = Join-Path $Out 'wpf-net10'; Reset-Dir $o
        Invoke-Checked 'build wpf-net10 (needs the .NET 10 Desktop Runtime)' { dotnet publish (Join-Path $Proto 'wpf\wpf-net10.csproj') -c Release -r win-x64 --self-contained false -o $o }
        Add-Assets $o
    }
    'wpf-net10-sc' = {
        $o = Join-Path $Out 'wpf-net10-sc'; Reset-Dir $o
        Invoke-Checked 'build wpf-net10-sc (self-contained, one file)' { dotnet publish (Join-Path $Proto 'wpf\wpf-net10.csproj') -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o $o }
        Add-Assets $o
    }
    'wpf-net10-webview2-sc' = {
        $o = Join-Path $Out 'wpf-net10-webview2-sc'; Reset-Dir $o
        Invoke-Checked 'build wpf-net10-webview2-sc' { dotnet publish (Join-Path $Proto 'wpf\wpf-net10-webview2.csproj') -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o $o }
        Add-Assets $o -Page
    }
    'winui3' = {
        $o = Join-Path $Out 'winui3'; Reset-Dir $o
        Invoke-Checked 'build winui3 (unpackaged, self-contained)' { dotnet publish (Join-Path $Proto 'winui3\proto-winui3.csproj') -c Release -o $o }
        Add-Assets $o
    }
    'avalonia' = {
        $o = Join-Path $Out 'avalonia'; Reset-Dir $o
        Invoke-Checked 'build avalonia (self-contained, trimmed, one file)' { dotnet publish (Join-Path $Proto 'avalonia\proto-avalonia.csproj') -c Release -r win-x64 --self-contained true -p:PublishTrimmed=true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -o $o }
        Add-Assets $o
    }
    'avalonia-aot' = {
        $o = Join-Path $Out 'avalonia-aot'; Reset-Dir $o
        Invoke-Checked 'build avalonia-aot (native code, no JIT)' { dotnet publish (Join-Path $Proto 'avalonia\proto-avalonia.csproj') -c Release -r win-x64 -p:PublishAot=true -o $o }
        Add-Assets $o
    }
    'tauri' = {
        $src = Join-Path $Proto 'tauri'; $dist = Join-Path $src 'dist'
        $o = Join-Path $Out 'tauri'; $w = Join-Path $Out 'tauri-weigh'; Reset-Dir $o; Reset-Dir $w
        Reset-Dir $dist; Copy-Item -LiteralPath (Join-Path $Proto 'web\index.html') -Destination $dist
        Push-Location $src
        try {
            Invoke-Checked 'build tauri (weighed, page only)' { cargo build --release }
            Copy-Item -LiteralPath 'target\release\proto-tauri.exe' -Destination $w
            Add-Assets $dist
            (Get-Item 'src\main.rs').LastWriteTime = Get-Date
            Invoke-Checked 'build tauri (run, page with art and music)' { cargo build --release }
            Copy-Item -LiteralPath 'target\release\proto-tauri.exe' -Destination $o
        } finally { Pop-Location }
    }
    'slint' = {
        $o = Join-Path $Out 'slint'; Reset-Dir $o
        Push-Location (Join-Path $Proto 'slint')
        try { Invoke-Checked 'build slint' { cargo build --release }; Copy-Item -LiteralPath 'target\release\proto-slint.exe' -Destination $o } finally { Pop-Location }
        Add-Assets $o
    }
    'egui' = {
        $o = Join-Path $Out 'egui'; Reset-Dir $o
        Push-Location (Join-Path $Proto 'egui')
        try { Invoke-Checked 'build egui' { cargo build --release }; Copy-Item -LiteralPath 'target\release\proto-egui.exe' -Destination $o } finally { Pop-Location }
        Add-Assets $o
    }
    'wails' = {
        $src = Join-Path $Proto 'wails'; $front = Join-Path $src 'frontend'
        $o = Join-Path $Out 'wails'; $w = Join-Path $Out 'wails-weigh'; Reset-Dir $o; Reset-Dir $w
        Reset-Dir $front; Copy-Item -LiteralPath (Join-Path $Proto 'web\index.html') -Destination $front
        Push-Location $src
        try {
            Invoke-Checked 'build wails (weighed, page only)' { go build -tags desktop,production -ldflags '-w -s -H windowsgui' -o (Join-Path $w 'proto-wails.exe') . }
            Add-Assets $front
            Invoke-Checked 'build wails (run, page with art and music)' { go build -tags desktop,production -ldflags '-w -s -H windowsgui' -o (Join-Path $o 'proto-wails.exe') . }
        } finally { Pop-Location }
    }
    'electron' = {
        $src = Join-Path $Proto 'electron'
        $o = Join-Path $Out 'electron'; $w = Join-Path $Out 'electron-weigh'; Reset-Dir $o; Reset-Dir $w
        Push-Location $src
        try {
            Invoke-Checked 'install electron' { npm install --no-audit --no-fund }
            Remove-Item -LiteralPath 'art.png', 'loop.wav' -ErrorAction SilentlyContinue
            Copy-Item -LiteralPath (Join-Path $Proto 'web\index.html') -Destination $src -Force
            Invoke-Checked 'package electron (weighed, page only)' { npx electron-packager . proto-electron --platform=win32 --arch=x64 --out $w --overwrite --ignore='^/node_modules' }
            Add-Assets $src
            Invoke-Checked 'package electron (run, page with art and music)' { npx electron-packager . proto-electron --platform=win32 --arch=x64 --out $o --overwrite --ignore='^/node_modules' }
        } finally { Pop-Location }
    }
    'qt' = {
        $src = Join-Path $Proto 'qt'; $b = Join-Path $Work 'build-qt'
        $o = Join-Path $Out 'qt'; Reset-Dir $o; Reset-Dir $b
        Invoke-Checked 'configure qt' { cmake -S $src -B $b -G Ninja -DCMAKE_BUILD_TYPE=Release "-DCMAKE_PREFIX_PATH=$script:QtDir" }
        Invoke-Checked 'build qt' { cmake --build $b }
        Copy-Item -LiteralPath (Join-Path $b 'proto-qt.exe') -Destination $o
        Invoke-Checked 'deploy qt' { & (Join-Path $script:QtDir 'bin\windeployqt.exe') --release --qmldir $src --no-translations --no-opengl-sw (Join-Path $o 'proto-qt.exe') }
        Add-Assets $o
    }
    'flutter' = {
        $src = Join-Path $Proto 'flutter'
        $o = Join-Path $Out 'flutter'; Reset-Dir $o
        Push-Location $src
        try {
            Invoke-Checked 'make the flutter platform folder' { flutter create --platforms=windows --project-name proto_flutter . }
            Invoke-Checked 'build flutter' { flutter build windows --release }
            Copy-Item -Path 'build\windows\x64\runner\Release\*' -Destination $o -Recurse
        } finally { Pop-Location }
        Add-Assets $o
    }
}

# Which exe each build runs, inside its folder.
$Exe = @{
    'wpf-net481-webview2' = 'wpf-net481-webview2.exe'; 'wpf-net10' = 'wpf-net10.exe'; 'wpf-net10-sc' = 'wpf-net10.exe'
    'wpf-net10-webview2-sc' = 'wpf-net10-webview2.exe'; 'winui3' = 'proto-winui3.exe'; 'avalonia' = 'proto-avalonia.exe'
    'avalonia-aot' = 'proto-avalonia.exe'; 'tauri' = 'proto-tauri.exe'; 'slint' = 'proto-slint.exe'; 'egui' = 'proto-egui.exe'
    'wails' = 'proto-wails.exe'; 'electron' = 'proto-electron-win32-x64\proto-electron.exe'; 'qt' = 'proto-qt.exe'; 'flutter' = 'proto_flutter.exe'
}

# --- Measuring --------------------------------------------------------------

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

// Every audio session on the default playback device, as the Volume Mixer
// sees them: the process that owns it, the name and icon it set for itself
// (empty when it set none, and the mixer then shows the exe's description),
// and whether it is playing.
public static class ProtoAudio
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator
    {
        int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice
    {
        int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object result);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2
    {
        int GetAudioSessionControl(IntPtr groupingParam, int flags, out IntPtr control);
        int GetSimpleAudioVolume(IntPtr groupingParam, int flags, out IntPtr volume);
        int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator
    {
        int GetCount(out int count);
        int GetSession(int index, out IAudioSessionControl2 session);
    }

    [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2
    {
        int GetState(out int state);
        int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        int SetDisplayName(string name, ref Guid context);
        int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
        int SetIconPath(string path, ref Guid context);
        int GetGroupingParam(out Guid grouping);
        int SetGroupingParam(ref Guid grouping, ref Guid context);
        int RegisterAudioSessionNotification(IntPtr client);
        int UnregisterAudioSessionNotification(IntPtr client);
        int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        int GetProcessId(out uint pid);
    }

    public class Session
    {
        public uint Pid;
        public string DisplayName;
        public string IconPath;
        public int State;
    }

    public static List<Session> List()
    {
        var list = new List<Session>();
        var enumerator = (IMMDeviceEnumerator)new MMDeviceEnumerator();
        IMMDevice device;
        Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(0, 1, out device));
        Guid iid = typeof(IAudioSessionManager2).GUID;
        object o;
        Marshal.ThrowExceptionForHR(device.Activate(ref iid, 1, IntPtr.Zero, out o));
        IAudioSessionEnumerator sessions;
        Marshal.ThrowExceptionForHR(((IAudioSessionManager2)o).GetSessionEnumerator(out sessions));
        int count;
        Marshal.ThrowExceptionForHR(sessions.GetCount(out count));
        for (int i = 0; i < count; i++)
        {
            IAudioSessionControl2 s;
            Marshal.ThrowExceptionForHR(sessions.GetSession(i, out s));
            var r = new Session();
            s.GetProcessId(out r.Pid);
            s.GetDisplayName(out r.DisplayName);
            s.GetIconPath(out r.IconPath);
            s.GetState(out r.State);
            list.Add(r);
        }
        return list;
    }
}
'@

function Get-Tree([int]$root) {
    $all = Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, WorkingSetSize, PrivatePageCount, ExecutablePath
    $ids = [System.Collections.Generic.List[int]]::new(); $ids.Add($root)
    for ($i = 0; $i -lt $ids.Count; $i++) {
        foreach ($p in $all) { if ($p.ParentProcessId -eq $ids[$i] -and -not $ids.Contains([int]$p.ProcessId)) { $ids.Add([int]$p.ProcessId) } }
    }
    $all | Where-Object { $ids.Contains([int]$_.ProcessId) }
}

function Measure-Tree([int]$root) {
    $tree = @(Get-Tree $root)
    [pscustomobject]@{
        Processes = $tree.Count
        WorkingSetMB = [math]::Round((($tree | Measure-Object WorkingSetSize -Sum).Sum) / 1MB, 1)
        PrivateMB = [math]::Round((($tree | Measure-Object PrivatePageCount -Sum).Sum) / 1MB, 1)
        Tree = $tree
    }
}

# What the mixer shows for each session of the prototype's processes: the
# session's own name when it set one, otherwise the description of the exe
# that owns it, which for a web view is the web view's exe, not ours.
function Get-MixerEntries($tree, [int]$root) {
    $byPid = @{}; foreach ($p in $tree) { $byPid[[int]$p.ProcessId] = $p }
    foreach ($s in [ProtoAudio]::List()) {
        $p = $byPid[[int]$s.Pid]
        if (-not $p) { continue }
        $desc = $null
        if ($p.ExecutablePath) { $desc = (Get-Item -LiteralPath $p.ExecutablePath).VersionInfo.FileDescription }
        [pscustomobject]@{
            Process = $p.Name
            OwnProcess = ([int]$s.Pid -eq $root)
            DisplayName = $s.DisplayName
            ExeDescription = $desc
            MixerShows = $(if ($s.DisplayName -and -not $s.DisplayName.StartsWith('@')) { $s.DisplayName } elseif ($desc) { $desc } else { $p.Name })
            Playing = ($s.State -eq 1)
        }
    }
}

function Stop-Tree([int]$root) {
    $p = Get-Process -Id $root -ErrorAction SilentlyContinue
    if ($p) { [void]$p.CloseMainWindow(); [void]$p.WaitForExit(3000) }
    if (Get-Process -Id $root -ErrorAction SilentlyContinue) { & taskkill.exe /T /F /PID $root | Out-Null }
}

function Get-Size([string]$dir) {
    $files = Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object { $_.Extension -ne '.pdb' -and $_.Name -notin 'art.png', 'loop.wav' }
    $stage = Join-Path $Work ('weigh-' + [guid]::NewGuid().ToString('n'))
    foreach ($f in $files) {
        $to = Join-Path $stage $f.FullName.Substring($dir.Length).TrimStart('\')
        New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $to
    }
    $zip = "$stage.zip"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
    $r = [pscustomobject]@{
        InstallMB = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 2)
        ZipMB = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 2)
        Files = $files.Count
    }
    Remove-Item -LiteralPath $stage -Recurse -Force; Remove-Item -LiteralPath $zip -Force
    $r
}

function Measure-One([string]$name) {
    $dir = Join-Path $Out $name
    $exe = Join-Path $dir $Exe[$name]
    if (-not (Test-Path -LiteralPath $exe)) { throw "$name has no build at $exe" }
    $weigh = Join-Path $Out "$name-weigh"
    $size = Get-Size $(if (Test-Path -LiteralPath $weigh) { $weigh } else { $dir })
    $runs = @()
    for ($r = 1; $r -le $Runs; $r++) {
        $ready = Join-Path $Work "ready-$name-$r"
        Remove-Item -LiteralPath $ready, "$ready.active" -ErrorAction SilentlyContinue
        $psi = [Diagnostics.ProcessStartInfo]::new($exe)
        $psi.WorkingDirectory = Split-Path $exe
        $psi.UseShellExecute = $false
        $psi.EnvironmentVariables['PROTO_READY'] = $ready
        $psi.EnvironmentVariables['WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS'] = '--autoplay-policy=no-user-gesture-required'
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $p = [Diagnostics.Process]::Start($psi)
        while (-not (Test-Path -LiteralPath $ready) -and $clock.ElapsedMilliseconds -lt 30000 -and -not $p.HasExited) { Start-Sleep -Milliseconds 5 }
        $readyMs = if (Test-Path -LiteralPath $ready) { $clock.ElapsedMilliseconds } else { $null }
        $run = [ordered]@{ Run = $r; ReadyMs = $readyMs; Exited = $p.HasExited }
        if ($readyMs) {
            Start-Sleep -Milliseconds 3000
            $idle = Measure-Tree $p.Id
            Start-Sleep -Milliseconds 5000
            $active = Measure-Tree $p.Id
            $run.IdleWorkingSetMB = $idle.WorkingSetMB; $run.IdlePrivateMB = $idle.PrivateMB
            $run.ActiveWorkingSetMB = $active.WorkingSetMB; $run.ActivePrivateMB = $active.PrivateMB
            $run.Processes = $active.Processes
            $run.PlayStarted = (Test-Path -LiteralPath "$ready.active")
            if ($r -eq 1) { $run.Mixer = @(Get-MixerEntries $active.Tree $p.Id) }
        }
        Stop-Tree $p.Id
        Remove-Item -LiteralPath $ready, "$ready.active" -ErrorAction SilentlyContinue
        $runs += [pscustomobject]$run
        Say ("{0} run {1}: ready {2} ms" -f $name, $r, $readyMs)
        Start-Sleep -Milliseconds 1000
    }
    $warm = @($runs | Select-Object -Skip 1 | Where-Object ReadyMs)
    function Median($xs) { $s = @($xs | Sort-Object); if ($s.Count) { $s[[int][math]::Floor(($s.Count - 1) / 2)] } }
    [pscustomobject]@{
        Name = $name
        Size = $size
        FirstReadyMs = $runs[0].ReadyMs
        WarmReadyMs = Median ($warm | ForEach-Object ReadyMs)
        IdlePrivateMB = Median ($warm | ForEach-Object IdlePrivateMB)
        IdleWorkingSetMB = Median ($warm | ForEach-Object IdleWorkingSetMB)
        ActivePrivateMB = Median ($warm | ForEach-Object ActivePrivateMB)
        ActiveWorkingSetMB = Median ($warm | ForEach-Object ActiveWorkingSetMB)
        Processes = Median ($warm | ForEach-Object Processes)
        Mixer = $runs[0].Mixer
        Runs = $runs
    }
}

# --- Run --------------------------------------------------------------------

New-Item -ItemType Directory -Force -Path $Work, $Out | Out-Null
$script:Wav = Join-Path $Work 'loop.wav'
Write-QuietWav $script:Wav
$names = @($Builds.Keys | Where-Object { -not $Only -or $_ -in $Only })
$failed = [ordered]@{}

if (-not $MeasureOnly) {
    Use-VcVars (Find-VcVars)
    Install-Tools
    foreach ($n in $names) {
        try { & $Builds[$n] }
        catch { $failed[$n] = "build: $($_.Exception.Message)"; Say "BUILD FAILED $n : $($_.Exception.Message)" }
    }
}

$results = @()
foreach ($n in $names) {
    if ($failed.Contains($n)) { continue }
    try { $results += Measure-One $n }
    catch { $failed[$n] = "measure: $($_.Exception.Message)"; Say "MEASURE FAILED $n : $($_.Exception.Message)" }
}

$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
$gpu = (Get-CimInstance Win32_VideoController | ForEach-Object Name) -join ', '
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$os = (Get-CimInstance Win32_OperatingSystem)
$wv2 = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' -ErrorAction SilentlyContinue).pv
$machine = [ordered]@{
    When = (Get-Date).ToString('yyyy-MM-dd HH:mm zzz'); Os = "$($os.Caption) $($os.Version)"; Cpu = $cpu; Gpu = $gpu; RamGB = $ram
    WebView2Runtime = $wv2; Commit = (git -C $Repo rev-parse --short HEAD)
}
[ordered]@{ Machine = $machine; Results = $results; Failed = $failed } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $Work 'results.json') -Encoding utf8

$md = [System.Collections.Generic.List[string]]::new()
$md.Add("Launcher stack prototypes measured on $($machine.Os), $cpu, $gpu, $ram GB, WebView2 runtime $wv2, at $($machine.When), from $($machine.Commit). $Runs runs each: the first start after the build, then the median of the rest. Memory is the prototype and every process under it; private is what only it holds, working set what it has in memory now.")
$md.Add('')
$md.Add('| Prototype | Install MB | Zip MB | First start ms | Start ms | Idle private MB | Idle working set MB | Active private MB | Active working set MB | Processes | Volume Mixer shows |')
$md.Add('|---|---|---|---|---|---|---|---|---|---|---|')
foreach ($r in $results) {
    $mix = if ($r.Mixer) { ($r.Mixer | ForEach-Object { "$($_.MixerShows) ($($_.Process)$(if (-not $_.OwnProcess) { ', child' }))" }) -join '; ' } else { 'no session' }
    $md.Add("| $($r.Name) | $($r.Size.InstallMB) | $($r.Size.ZipMB) | $($r.FirstReadyMs) | $($r.WarmReadyMs) | $($r.IdlePrivateMB) | $($r.IdleWorkingSetMB) | $($r.ActivePrivateMB) | $($r.ActiveWorkingSetMB) | $($r.Processes) | $mix |")
}
foreach ($k in $failed.Keys) { $md.Add(''); $md.Add("$k did not finish: $($failed[$k])") }
$md | Set-Content -LiteralPath (Join-Path $Work 'results.md') -Encoding utf8
Say "wrote $(Join-Path $Work 'results.md')"
Get-Content -LiteralPath (Join-Path $Work 'results.md')
