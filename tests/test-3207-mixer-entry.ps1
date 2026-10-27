<#
  test-3207-mixer-entry.ps1

      pwsh -NoProfile -File .\tests\test-3207-mixer-entry.ps1

  Issue #3207: the launcher's menu theme must show in the Windows Volume Mixer
  as the launcher's own entry, under this build's name, not as Microsoft Edge
  WebView2. The mixer lists audio sessions: one per process and output, with
  the name and icon the session was given, or the exe's description when it
  was given none. So this asks Windows the question the mixer asks.

  It compiles launcher\app\MenuMusic.cs with the compiler the build runs,
  plays the real theme through it at volume 0 (nothing is heard), and once
  MenuMusic says the theme is on, reads every audio session on the default
  output through Core Audio, the API the mixer itself reads:

    1. a session belongs to this process, the one that played the theme;
    2. it is active, so it is the theme's sound and not an empty session;
    3. its name is the name MenuMusic was given, as the dev build gives
       "Thornswood Dev";
    4. no msedgewebview2.exe was started for it (the theme makes no browser);
    5. Close ends the sound: the session is no longer active afterwards.

  A machine with no sound output (the VPS runners: Windows Server with no
  audio device) cannot open one, and MenuMusic logs that; this says SKIP with
  the line it logged rather than passing on nothing. Off Windows it says
  SKIP: waveOut and Core Audio are Windows.

  Never starts the launcher or the game. Writes nothing outside a temp folder.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
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
function Done {
    Write-Host ''
    Write-Host "$($script:pass) passed, $($script:fail) failed"
    if ($script:fail) { exit 1 }
    exit 0
}

. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')

$theme = Join-Path $repo 'game\ui\thornswood-theme.mp3'
$nlayer = @($LauncherLib | Where-Object { [IO.Path]::GetFileName($_) -eq 'NLayer.dll' })
Yes 'the theme is in the repository (game\ui\thornswood-theme.mp3)' (Test-Path -LiteralPath $theme)
Yes 'Thornswood.csproj references NLayer.dll from launcher\lib' ($nlayer.Count -eq 1 -and (Test-Path -LiteralPath $nlayer[0]))

if (-not $OnWindows) {
    Write-Host 'SKIP  1 to 5, the theme played and the mixer asked: waveOut and Core Audio are Windows, and so is the compiler the build runs'
    Done
}
Yes 'the compiler the build runs is on this machine' (Test-Path -LiteralPath $LauncherCsc)
if (-not (Test-Path -LiteralPath $LauncherCsc) -or $nlayer.Count -ne 1) { Done }

# What MenuMusic.cs needs of the rest of the launcher: Swallow, which needs
# Paths.LogFile. A null log file makes Swallow write nothing.
$paths = 'namespace Thornswood { static class Paths { public static string LogFile = null; } }'
$swallow = [IO.File]::ReadAllText((Join-Path $repo 'launcher\app\Swallow.cs'))
$music = [IO.File]::ReadAllText((Join-Path $repo 'launcher\app\MenuMusic.cs'))

# The harness's side: what MenuMusic logs, and the mixer's view of this
# process, read the way the mixer reads it.
$probe = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

namespace Thornswood
{
    public static class Probe3207
    {
        public static readonly List<string> Lines = new List<string>();
        public static readonly ManualResetEvent On = new ManualResetEvent(false);
        public static readonly ManualResetEvent Failed = new ManualResetEvent(false);

        static void Log(string m)
        {
            lock (Lines) Lines.Add(m);
            if (m.StartsWith("Menu music: the theme is on", StringComparison.Ordinal)) On.Set();
            else if (m.StartsWith("Menu music:", StringComparison.Ordinal) && m.IndexOf("mixer entry", StringComparison.Ordinal) < 0) Failed.Set();
        }

        /// <summary>
        /// The decoder from its file. The compiled library carries no
        /// resource for MenuMusic's own resolver to hand out, so this one
        /// answers first; it is C#, because the playback thread is where the
        /// CLR asks, and a PowerShell script block cannot run there.
        /// </summary>
        public static string UseDecoder(string path)
        {
            var a = System.Reflection.Assembly.LoadFrom(path);
            AppDomain.CurrentDomain.AssemblyResolve += delegate (object s, ResolveEventArgs e)
            {
                return new System.Reflection.AssemblyName(e.Name).Name == "NLayer" ? a : null;
            };
            return a.FullName;
        }

        public static void Play(string track, string name)
        {
            MenuMusic.Start(track, 0.0, name, null, Log);
            MenuMusic.Decide(true, 0.0);
        }

        public static void Close() { MenuMusic.Close(); }

        public static string[] Said() { lock (Lines) return Lines.ToArray(); }

        /// <summary>"state|name" for each session of this process on the default output.</summary>
        public static string[] Sessions()
        {
            var found = new List<string>();
            uint me = (uint)System.Diagnostics.Process.GetCurrentProcess().Id;
            var devices = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
            IMMDevice device;
            Check(devices.GetDefaultAudioEndpoint(0, 0, out device), "GetDefaultAudioEndpoint");
            Guid iid = typeof(IAudioSessionManager2).GUID;
            object o;
            Check(device.Activate(ref iid, 0x17, IntPtr.Zero, out o), "Activate");
            var manager = (IAudioSessionManager2)o;
            IAudioSessionEnumerator list;
            Check(manager.GetSessionEnumerator(out list), "GetSessionEnumerator");
            int count;
            Check(list.GetCount(out count), "GetCount");
            for (int i = 0; i < count; i++)
            {
                IAudioSessionControl2 s;
                if (list.GetSession(i, out s) != 0 || s == null) continue;
                uint pid;
                if (s.GetProcessId(out pid) == 0 && pid == me)
                {
                    int state;
                    s.GetState(out state);
                    IntPtr p;
                    string name = "";
                    if (s.GetDisplayName(out p) == 0 && p != IntPtr.Zero) { name = Marshal.PtrToStringUni(p); Marshal.FreeCoTaskMem(p); }
                    found.Add(state + "|" + name);
                }
                Marshal.ReleaseComObject(s);
            }
            return found.ToArray();
        }

        static void Check(int hr, string what) { if (hr != 0) throw new Exception(what + " returned 0x" + hr.ToString("X8")); }

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
        class MMDeviceEnumeratorCom { }

        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDeviceEnumerator
        {
            [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
            [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
        }

        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IMMDevice
        {
            [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        }

        [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioSessionManager2
        {
            [PreserveSig] int GetAudioSessionControl(IntPtr sessionGuid, int streamFlags, out IntPtr session);
            [PreserveSig] int GetSimpleAudioVolume(IntPtr sessionGuid, int streamFlags, out IntPtr volume);
            [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator list);
        }

        [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioSessionEnumerator
        {
            [PreserveSig] int GetCount(out int count);
            [PreserveSig] int GetSession(int index, out IAudioSessionControl2 session);
        }

        [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IAudioSessionControl2
        {
            [PreserveSig] int GetState(out int state);
            [PreserveSig] int GetDisplayName(out IntPtr name);
            [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name, ref Guid eventContext);
            [PreserveSig] int GetIconPath(out IntPtr path);
            [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid eventContext);
            [PreserveSig] int GetGroupingParam(out Guid group);
            [PreserveSig] int SetGroupingParam(ref Guid group, ref Guid eventContext);
            [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
            [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
            [PreserveSig] int GetSessionIdentifier(out IntPtr id);
            [PreserveSig] int GetSessionInstanceIdentifier(out IntPtr id);
            [PreserveSig] int GetProcessId(out uint pid);
        }
    }
}
'@

$asm = Add-LauncherType -Source $paths, $swallow, $music, $probe -Reference @($LauncherLib)
$P = $asm.GetType('Thornswood.Probe3207')
Write-Host ('      decoder: ' + $P::UseDecoder($nlayer[0]))

$name = 'Thornswood Dev'
$browsersBefore = @(Get-Process -Name msedgewebview2 -ErrorAction SilentlyContinue | ForEach-Object Id)
$P::Play($theme, $name)
# What it waits on is MenuMusic's own line, written after the first buffers
# are queued; ten seconds is the most a working output takes to open, and
# running out of them is a failure that says so, not a pass.
$which = [Threading.WaitHandle]::WaitAny(@($P::On, $P::Failed), 10000)
$said = @($P::Said())
foreach ($l in $said) { Write-Host "      logged: $l" }

if ($which -eq 1 -and @($said | Where-Object { $_ -like 'Menu music: Windows would not open a sound output*' }).Count -gt 0) {
    Write-Host 'SKIP  1 to 5: this machine has no sound output to open (the line above), so there is no mixer entry to read'
    $P::Close()
    Done
}
Yes 'MenuMusic says the theme is on' ($which -eq 0)
if ($which -ne 0) { $P::Close(); Done }

$sessions = @($P::Sessions())
foreach ($s in $sessions) { Write-Host "      session of this process: $s" }
Yes '1. a session on the default output belongs to this process' ($sessions.Count -ge 1)
Yes '2. one of them is active (state 1), the theme playing' (@($sessions | Where-Object { $_ -like '1|*' }).Count -ge 1)
Yes "3. the active one is named $name, as MenuMusic was told" (@($sessions | Where-Object { $_ -eq "1|$name" }).Count -ge 1)
$browsersAfter = @(Get-Process -Name msedgewebview2 -ErrorAction SilentlyContinue | Where-Object { $browsersBefore -notcontains $_.Id })
Yes '4. no msedgewebview2.exe was started for the theme' ($browsersAfter.Count -eq 0)

$P::Close()
# Close lets the playback thread end the sound by itself; it reports nothing
# back, so this reads the session until it is no longer active, for at most
# five seconds, and a session still active after that is a failure.
$deadline = [DateTime]::UtcNow.AddSeconds(5)
do {
    $still = @(@($P::Sessions()) | Where-Object { $_ -like '1|*' })
    if ($still.Count -eq 0) { break }
    [Threading.Thread]::Sleep(100)
} while ([DateTime]::UtcNow -lt $deadline)
Yes '5. after Close no session of this process is active' ($still.Count -eq 0)
Done
