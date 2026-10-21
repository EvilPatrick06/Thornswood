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

# What the Restart Manager says has a file at or under $Path open right now,
# as "pid name" pairs, or why it could not be asked. A refusal it names
# nothing for is held by a driver or by a process that is still exiting.
function Get-ThornswoodPathHolders([string]$Path) {
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
    if (-not $files.Count) { return 'the folder holds no files, so only an open handle on a folder in it can be holding it' }
  }
  $who = [ThornswoodRestartManager]::Holders([string[]]$files)
  if (-not $who) { return 'no process the Restart Manager can see, so a driver or a process still exiting' }
  return $who
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
