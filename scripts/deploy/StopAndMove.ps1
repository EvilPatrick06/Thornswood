<#
  StopAndMove.ps1

  Stopping what runs from a folder, and then moving its files, on the box:
  each process waited for until it has exited, and each move tried once.

  Its text goes in front of what runs on the box: Swap.ps1 puts it in front of
  both swap blocks (Deploy-Server, Deploy-DevGamemode, Deploy-Docs,
  Install-Voice, Install-Bot), Install-Bot in front of Bot-Service.ps1
  wherever it sends that, and Install-Bridge in front of its swap.
  Install-ThornswoodServer.ps1 loads it from beside itself, where
  Publish-Server.ps1 sends it. Keep it ASCII: Windows PowerShell 5.1 on the box
  reads a file with no byte order mark as ANSI.

  WHY, issue #2928. Until 20 Oct 2026 every swap stopped what was running and
  then renamed its files in a loop: ten tries half a second apart in Swap.ps1,
  0.7 s apart in Install-ThornswoodServer.ps1, a second apart for the bot's
  service program, "because a process that has just been told to stop does
  not always let go of its files the same instant", after waiting for its
  port to close and, for the game servers, two seconds more. Measured on the
  box that day, in a folder Windows Defender scans:

    - a node holding a file in a folder, ended with Stop-Process -Force, and
      the folder renamed at once: refused (Windows error 5) 15 times in 15,
      for 8 to 403 ms each time, with the Restart Manager naming nothing that
      held it, because the process was still exiting;
    - the same, renamed once that process had exited: refused 0 times in 15,
      and the log it had been writing up to the end, renamed on its own,
      0 times in 10;
    - a folder of files written that instant (twenty small scripts and a
      fresh executable), renamed at once: refused 0 times in 30, and 110 such
      files renamed one by one, 0 times.

  Stop-Process, Stop-ScheduledTask and Stop-Service return once Windows has
  been asked to end a process, not once it has ended, and a process's files
  stay open until it has. That is the refusal the loops were covering. A
  scanner opening new files (#2888, on One) is not what these swaps meet: the
  box did not show it, and every swap here moves its stage only after its
  checks have read it back, seconds after it was written.

  So: each process is opened before anything is asked to stop, so the wait is
  on that process and never on whatever Windows gives its id to next; then
  whatever is still running is ended, and each is waited for until it has
  exited. Then each move is tried once. A move that is refused says the
  Windows error and what the Restart Manager says has a file under it open at
  that moment, and the caller refuses or rolls back as it always has. Nothing
  is tried again.
#>

# How long a process that has been ended may take to exit before its caller
# is told it has not. Measured on the box: 8 to 403 ms (#2928). One still there
# after this is stuck in the kernel, and moving its files would be refused.
$ThornswoodExitSeconds = 30

# The processes with these ids that are running, each with its handle open,
# so that Stop-ThornswoodProcessHeld waits on that process and no other.
# Opened before anything is asked to stop; the caller takes them with @().
# An id with nothing running is left out: there is nothing to wait for. One
# that is running and cannot be opened goes in $ThornswoodNotHeld, a line
# each, for the caller to say and to move nothing it holds.
$ThornswoodNotHeld = @()
function Get-ThornswoodProcessHeld([int[]]$Ids) {
  $script:ThornswoodNotHeld = @()
  foreach ($id in @($Ids | Where-Object { $_ -gt 0 -and $_ -ne $PID } | Sort-Object -Unique)) {
    $p = Get-Process -Id $id -EA SilentlyContinue
    if (-not $p) { continue }
    $name = $p.ProcessName
    try { $null = $p.Handle; $p }
    catch {
      if (Get-Process -Id $id -EA SilentlyContinue) {
        $script:ThornswoodNotHeld += ('COULD NOT OPEN pid ' + $id + ' (' + $name + ') to wait for it to exit: ' + $_.Exception.Message)
      }
    }
  }
}

# Ends each process Get-ThornswoodProcessHeld opened that is still running,
# and returns once every one has exited. Says nothing for one that exits,
# because each caller says what it stopped in its own words; says each one
# that had not exited after $ThornswoodExitSeconds, and leaves its id in
# $ThornswoodStillRunning, so the caller moves nothing it holds.
$ThornswoodStillRunning = @()
function Stop-ThornswoodProcessHeld($Held) {
  $script:ThornswoodStillRunning = @()
  $why = @{}
  $names = @{}
  foreach ($p in @($Held | Where-Object { $_ })) {
    if ($p.HasExited) { continue }
    $names[$p.Id] = $p.ProcessName
    # Refused when it is already on its way out, which the wait below sees.
    try { $p.Kill() } catch { $why[$p.Id] = $_.Exception.Message }
  }
  $until = (Get-Date).AddSeconds($ThornswoodExitSeconds)
  foreach ($p in @($Held | Where-Object { $_ })) {
    $left = [int][Math]::Max(0, ($until - (Get-Date)).TotalMilliseconds)
    if ($p.WaitForExit($left)) { continue }
    $script:ThornswoodStillRunning += $p.Id
    $line = 'pid ' + $p.Id + ' (' + $names[$p.Id] + ') was ended and had not exited after ' + $ThornswoodExitSeconds + ' seconds'
    if ($why.ContainsKey($p.Id)) { $line += '; ending it said: ' + $why[$p.Id] }
    $line
  }
}

# What has $Path or anything under it open right now: what the Restart
# Manager says, then every handle on the box that names it. Both, because the
# Restart Manager is asked about files only. A process whose current
# directory is in the folder, or that has a folder in it open, holds a handle
# on a folder, which it cannot see; that is the sharing violation (0x80070020)
# a dev publish was refused with on 21 Oct 2026 while it named nothing (#3131).
function Get-ThornswoodPathHolders([string]$Path) {
  return (Get-ThornswoodFileHolders $Path) + '; handles: ' + (Get-ThornswoodPathHandles $Path)
}

# What the Restart Manager says has a file at or under $Path open right now,
# as "pid name" pairs, or why it could not be asked.
function Get-ThornswoodFileHolders([string]$Path) {
  if (-not ('ThornswoodRestartManager' -as [type])) {
    try {
      Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ThornswoodRestartManager {
  [StructLayout(LayoutKind.Sequential)] struct FILETIME { public uint Low; public uint High; }
  [StructLayout(LayoutKind.Sequential)] struct RM_UNIQUE_PROCESS { public int Pid; public FILETIME Start; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct RM_PROCESS_INFO {
    public RM_UNIQUE_PROCESS Process;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string AppName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string ServiceShortName;
    public int AppType; public uint AppStatus; public uint TSSessionId;
    [MarshalAs(UnmanagedType.Bool)] public bool Restartable;
  }
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmStartSession(out uint session, int flags, string key);
  [DllImport("rstrtmgr.dll")] static extern int RmEndSession(uint session);
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)] static extern int RmRegisterResources(uint session, uint files, string[] names, uint apps, IntPtr unique, uint services, string[] serviceNames);
  [DllImport("rstrtmgr.dll")] static extern int RmGetList(uint session, out uint needed, ref uint count, [In, Out] RM_PROCESS_INFO[] info, ref uint reasons);
  public static string Holders(string[] files) {
    uint session;
    int r = RmStartSession(out session, 0, Guid.NewGuid().ToString());
    if (r != 0) return "the Restart Manager would not start (" + r + ")";
    try {
      r = RmRegisterResources(session, (uint)files.Length, files, 0, IntPtr.Zero, 0, null);
      if (r != 0) return "the Restart Manager would not take the files (" + r + ")";
      uint needed = 0, count = 0, reasons = 0;
      r = RmGetList(session, out needed, ref count, null, ref reasons);
      if (r == 0) return "";
      if (r != 234) return "the Restart Manager would not list them (" + r + ")";
      RM_PROCESS_INFO[] info = new RM_PROCESS_INFO[needed];
      count = needed;
      r = RmGetList(session, out needed, ref count, info, ref reasons);
      if (r != 0) return "the Restart Manager would not list them (" + r + ")";
      List<string> said = new List<string>();
      for (int i = 0; i < count; i++) said.Add("pid " + info[i].Process.Pid + " " + info[i].AppName);
      return string.Join(", ", said.ToArray());
    } finally { RmEndSession(session); }
  }
}
'@
    } catch { return 'the Restart Manager could not be asked: ' + $_.Exception.Message }
  }
  $files = @($Path)
  if (Test-Path -LiteralPath $Path -PathType Container) {
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -EA SilentlyContinue | ForEach-Object { $_.FullName })
    if (-not $files.Count) { return 'the folder holds no files for the Restart Manager to ask about' }
  }
  $who = [ThornswoodRestartManager]::Holders([string[]]$files)
  if (-not $who) { return 'no process the Restart Manager can see' }
  return $who
}

# Every handle on the box that names $Path or a path under it, this
# process's own among them, as "pid name: path (access 0x...)" groups, then
# the processes it could not look into
# (protected ones, Windows Defender among them, which even an administrator
# cannot open). Read only: each handle is copied into this process, its path
# read, and the copy closed. A handle whose path cannot be read without
# waiting (a pipe with a read pending) is passed over by its access mask, and
# the whole look is given 20 seconds and says so if it ran out.
function Get-ThornswoodPathHandles([string]$Path) {
  if (-not ('ThornswoodHandles' -as [type])) {
    try {
      Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class ThornswoodHandles {
  [StructLayout(LayoutKind.Sequential)] struct ENTRY { public IntPtr Object; public IntPtr Pid; public IntPtr Handle; public uint Access; public ushort Creator; public ushort Type; public uint Attr; public uint Reserved; }
  [DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int cls, IntPtr buf, int len, out int ret);
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool DuplicateHandle(IntPtr sp, IntPtr sh, IntPtr tp, out IntPtr th, uint access, bool inherit, uint opt);
  [DllImport("kernel32.dll")] static extern uint GetFileType(IntPtr h);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern uint GetFinalPathNameByHandle(IntPtr h, StringBuilder sb, uint len, uint flags);
  static string found;
  public static string Under(string path) {
    found = null;
    Thread t = new Thread(delegate() { found = Look(path); });
    t.IsBackground = true;
    t.Start();
    if (!t.Join(20000)) return "the handle list did not finish in 20 seconds";
    return found;
  }
  static string Look(string path) {
    string under = path.TrimEnd('\\');
    int len = 1 << 22, ret, st;
    IntPtr buf;
    while (true) {
      buf = Marshal.AllocHGlobal(len);
      st = NtQuerySystemInformation(64, buf, len, out ret);
      if (st == 0) break;
      Marshal.FreeHGlobal(buf);
      if (len >= (1 << 30)) return "the handles could not be listed (0x" + st.ToString("X8") + ")";
      len *= 2;
    }
    Dictionary<int, IntPtr> procs = new Dictionary<int, IntPtr>();
    Dictionary<int, List<string>> held = new Dictionary<int, List<string>>();
    List<int> unopened = new List<int>();
    try {
      long count = Marshal.ReadIntPtr(buf).ToInt64();
      int size = Marshal.SizeOf(typeof(ENTRY));
      long first = buf.ToInt64() + IntPtr.Size * 2;
      IntPtr me = GetCurrentProcess();
      for (long i = 0; i < count; i++) {
        ENTRY e = (ENTRY)Marshal.PtrToStructure(new IntPtr(first + i * size), typeof(ENTRY));
        int pid = (int)e.Pid.ToInt64();
        if (pid <= 4) continue;
        // The masks a synchronous pipe is opened with: reading its path can wait for ever.
        if (e.Access == 0x0012019F || e.Access == 0x00120189 || e.Access == 0x00100000 || e.Access == 0x0016019F) continue;
        IntPtr p;
        if (!procs.TryGetValue(pid, out p)) {
          p = OpenProcess(0x40, false, pid);
          procs[pid] = p;
          if (p == IntPtr.Zero) unopened.Add(pid);
        }
        if (p == IntPtr.Zero) continue;
        IntPtr d;
        if (!DuplicateHandle(p, e.Handle, me, out d, 0, false, 2)) continue;
        try {
          if (GetFileType(d) != 1) continue;
          StringBuilder sb = new StringBuilder(1024);
          uint n = GetFinalPathNameByHandle(d, sb, 1024, 0);
          if (n == 0 || n >= 1024) continue;
          string at = sb.ToString();
          if (at.StartsWith(@"\\?\")) at = at.Substring(4);
          if (!at.Equals(under, StringComparison.OrdinalIgnoreCase) && !at.StartsWith(under + @"\", StringComparison.OrdinalIgnoreCase)) continue;
          if (!held.ContainsKey(pid)) held[pid] = new List<string>();
          held[pid].Add(at + " (access 0x" + e.Access.ToString("X") + ")");
        } finally { CloseHandle(d); }
      }
    } finally {
      foreach (IntPtr p in procs.Values) if (p != IntPtr.Zero) CloseHandle(p);
      Marshal.FreeHGlobal(buf);
    }
    List<string> said = new List<string>();
    foreach (KeyValuePair<int, List<string>> h in held) {
      List<string> paths = h.Value;
      string more = paths.Count > 6 ? " and " + (paths.Count - 6) + " more" : "";
      if (paths.Count > 6) paths = paths.GetRange(0, 6);
      said.Add("pid " + h.Key + " " + Name(h.Key) + ": " + string.Join(", ", paths.ToArray()) + more);
    }
    string text = said.Count > 0 ? string.Join("; ", said.ToArray()) : "none in any process it could look into";
    if (unopened.Count > 0) {
      // As an administrator these are the protected few; run as anybody
      // else it is nearly every process, and the count says so.
      List<string> names = new List<string>();
      for (int i = 0; i < unopened.Count && i < 12; i++) names.Add(unopened[i] + " " + Name(unopened[i]));
      text += "; could not look into " + (unopened.Count > 12 ? unopened.Count + " processes, among them " : "") + string.Join(", ", names.ToArray());
    }
    return text;
  }
  static string Name(int pid) {
    try { return System.Diagnostics.Process.GetProcessById(pid).ProcessName; } catch { return "(exited)"; }
  }
}
'@
    } catch { return 'the handles could not be listed: ' + $_.Exception.Message }
  }
  # Without the debug privilege an administrator cannot open the services'
  # processes; a run without it says so beside what it found.
  $noDebug = ''
  try { [System.Diagnostics.Process]::EnterDebugMode() } catch { $noDebug = '; without the debug privilege (' + $_.Exception.Message + ')' }
  try { return [ThornswoodHandles]::Under([IO.Path]::GetFullPath($Path)) + $noDebug }
  catch { return 'the handles could not be listed: ' + $_.Exception.Message }
}

# Moves a file or a folder on one volume, once, making the folder it goes
# into. $false when Windows refuses, with why in $ThornswoodMoveWhy.
$ThornswoodMoveWhy = ''
function Move-ThornswoodPath([string]$From, [string]$To) {
  $script:ThornswoodMoveWhy = ''
  try {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $To))
    if (Test-Path -LiteralPath $From -PathType Container) { [IO.Directory]::Move($From, $To) }
    else { [IO.File]::Move($From, $To) }
    return $true
  } catch {
    $e = $_.Exception
    while ($e.InnerException) { $e = $e.InnerException }
    $script:ThornswoodMoveWhy = ('{0} (0x{1:X8}); open under it then: {2}' -f $e.Message.Trim(), $e.HResult, (Get-ThornswoodPathHolders $From))
    return $false
  }
}
