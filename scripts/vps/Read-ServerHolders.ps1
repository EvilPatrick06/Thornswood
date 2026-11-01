<#
  Read-ServerHolders.ps1

      pwsh scripts/vps/Box-Run.ps1 -Line 'Read-ServerHolders'                     from any session with gh, a cloud thread included
      pwsh scripts/vps/Box-Run.ps1 -Line 'Read-ServerHolders -Server dev'
      pwsh scripts/vps/Box-Run.ps1 -Line 'Read-ServerHolders -DefenderFrom 2026-11-01T00:59 -DefenderMinutes 3'
      .\scripts\vps\Read-ServerHolders.ps1                                         on the box, as an administrator

  Says what has a game server's folder open right now, while the server
  runs, and every process of that server's task with it, so that what an
  install has to stop before it moves the folder aside is a measurement and
  not a guess. Issue #5211.

  WHY THIS EXISTS. On 31 Oct 2026 at 7:00 PM box time, Publish-Server-Main
  stopped the live server (the writer node, the server node and cmd, each
  waited for until it had exited) and then could not open C:\Thornswood-Server
  to rename it: Windows error 32, a sharing violation. That step is refused
  only when something has the folder itself open without delete sharing, a
  process's current directory the usual one (StopAndMove.ps1, #3262). The
  look taken the instant after the refusal found nothing holding it: no
  process but the installer itself had the folder open, no handle under it in
  any process it could look into. So whatever held it had let go within
  milliseconds, and no gate verb could look at the running server to find
  out what that was. The same refusal, naming nothing, stopped a dev publish
  on 22 Oct (#3262).

  It prints, for -Server live (C:\Thornswood-Server, the task "Thornswood
  Server") or dev (C:\Thornswood-Server-Dev, "Thornswood Dev Server"):
    1. which processes have the folder itself open, from Windows's own list
       for that folder (FileProcessIdsUsingFileInformation), which names
       protected processes such as Windows Defender too;
    2. every handle on the box on the folder or under it, from the processes
       it can look into, with each handle's access;
    3. the server's processes as the installer finds them (cmd.exe and
       node.exe with the folder on their command line, and node children),
       every process above them up to the task's start, and every process
       below any of them, conhost.exe included; each with its parent, when
       it started, its command line, whether the installer's StopServer
       stops it, and whether it has the folder itself open;
    4. whether Windows Defender scans the folder: its real-time protection
       and its excluded paths, as Defender itself reports them;
    5. with -DefenderFrom, the lines of Defender's own log (MPLog, in
       C:\ProgramData\Microsoft\Windows Defender\Support) from that minute
       for -DefenderMinutes minutes, the lines naming the folder first. The
       time is UTC, written yyyy-MM-ddTHH:mm. A log line with a Z is read as
       UTC, and one without as the box's own time, which it prints.

  Reads only: it opens the folder to ask who holds it, copies each handle it
  looks at into itself to read its path and closes the copy, and reads
  Defender's settings and log. It stops nothing, changes nothing and sends
  nothing anywhere. Windows PowerShell 5.1 and pwsh, on the box as SYSTEM
  through the gate, or as an administrator.

  Ends 0 when every part could be asked, 1 when a part could not.
#>
[CmdletBinding()]
param(
    [ValidateSet('live', 'dev')]
    [string]$Server = 'live',
    # The first minute of Defender's log to show, UTC, yyyy-MM-ddTHH:mm.
    [string]$DefenderFrom = '',
    # How many minutes of it, from -DefenderFrom.
    [ValidateRange(1, 60)]
    [int]$DefenderMinutes = 3
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\deploy\StopAndMove.ps1')

$Root = if ($Server -eq 'dev') { 'C:\Thornswood-Server-Dev' } else { 'C:\Thornswood-Server' }
$TaskName = if ($Server -eq 'dev') { 'Thornswood Dev Server' } else { 'Thornswood Server' }
$script:problems = 0
function Say([string]$text) { Write-Output $text }
function Bad([string]$text) { $script:problems++; Write-Output ('  COULD NOT ASK: ' + $text) }

$from = $null
if ($DefenderFrom) {
    $parsed = [DateTime]::MinValue
    $ok = [DateTime]::TryParseExact($DefenderFrom, 'yyyy-MM-ddTHH:mm', [Globalization.CultureInfo]::InvariantCulture,
        ([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal), [ref]$parsed)
    if (-not $ok) { Write-Output ('-DefenderFrom is not yyyy-MM-ddTHH:mm: ' + $DefenderFrom + '. Nothing was read.'); exit 1 }
    $from = $parsed
}

$now = Get-Date
Say ('{0} server, {1}, task "{2}", at {3} box time ({4} UTC)' -f $Server, $Root, $TaskName, $now.ToString('yyyy-MM-dd h:mm:ss tt'), $now.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))
if (-not (Test-Path -LiteralPath $Root -PathType Container)) { Say ('  ' + $Root + ' is not on this machine. Nothing was read.'); exit 1 }
if ($ThornswoodTypesWhy) { Say ('  ' + $ThornswoodTypesWhy + '. Nothing was read.'); exit 1 }

# ---- 1 and 2. who has the folder open, and every handle on it or under it ---
$snap = Get-ThornswoodPathOpeners $Root
$openers = @()
foreach ($m in [regex]::Matches($snap.Said, 'pid (\d+) ')) { $openers += [int]$m.Groups[1].Value }
Say ''
Say '1. The folder itself is open in (what a rename of it has to wait for):'
Say ('  ' + $snap.Said)
foreach ($id in $openers) { Say ('  pid ' + $id + ' ' + (Get-ThornswoodProcessWords $snap.Procs $id)) }
if (-not $snap.Procs.Count) { Bad 'the processes running could not be listed' }
Say ''
Say '2. Handles on the folder or under it, in the processes this could look into:'
$handles = Get-ThornswoodPathHandles $Root
Say ('  ' + $handles)
if ($handles -like 'the handle*could not*' -or $handles -like '*did not finish*') { Bad 'the handles' }

# ---- 3. the server task's processes, above and below ------------------------
Say ''
Say ('3. The processes of the server in ' + $Root + ':')
$all = @()
try { $all = @(Get-CimInstance Win32_Process -ErrorAction Stop) } catch { Bad ('the processes and their command lines: ' + $_.Exception.Message) }
$byId = @{}
foreach ($p in $all) { $byId[[int]$p.ProcessId] = $p }
# What StopServer in Install-ThornswoodServer.ps1 finds and stops, by the
# same rule (ServerProcesses there): cmd.exe and node.exe with the root and a
# backslash on their line, and node children of those.
$mark = $Root + '\'
$stops = @()
foreach ($p in $all) {
    if (($p.Name -eq 'node.exe' -or $p.Name -eq 'cmd.exe') -and $p.CommandLine -and
        $p.CommandLine.IndexOf($mark, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $stops += [int]$p.ProcessId }
}
foreach ($p in $all) {
    if ($p.Name -eq 'node.exe' -and $stops -contains [int]$p.ParentProcessId) { $stops += [int]$p.ProcessId }
}
$stops = @($stops | Sort-Object -Unique)
if (-not $stops.Count) { Say '  none: the installer would find no process of this server to stop (is it running?)' }
# Up from each to the process the task started, stopping at the Task
# Scheduler's service host or at a parent that has gone; then every process
# below any of those.
$tree = @{}
foreach ($id in $stops) {
    $at = $id
    $guard = 0
    while ($byId.ContainsKey($at) -and $guard -lt 16) {
        $p = $byId[$at]
        if ($p.Name -eq 'svchost.exe' -or $p.Name -eq 'services.exe' -or $p.Name -eq 'wininit.exe') { break }
        # A parent id Windows has given to a later process is not this one's parent.
        $parent = [int]$p.ParentProcessId
        if ($byId.ContainsKey($parent) -and $byId[$parent].CreationDate -and $p.CreationDate -and $byId[$parent].CreationDate -gt $p.CreationDate) { $tree[$at] = $true; break }
        $tree[$at] = $true
        $at = $parent
        $guard++
    }
}
$added = $true
while ($added) {
    $added = $false
    foreach ($p in $all) {
        $id = [int]$p.ProcessId
        $parent = [int]$p.ParentProcessId
        if ($tree.ContainsKey($id) -or -not $tree.ContainsKey($parent)) { continue }
        if ($byId[$parent].CreationDate -and $p.CreationDate -and $byId[$parent].CreationDate -gt $p.CreationDate) { continue }
        $tree[$id] = $true
        $added = $true
    }
}
foreach ($id in @($tree.Keys | Sort-Object { $byId[$_].CreationDate }, { $_ })) {
    $p = $byId[$id]
    $started = if ($p.CreationDate) { ([DateTime]$p.CreationDate).ToString('yyyy-MM-dd h:mm:ss tt') } else { 'start not given' }
    $parentName = if ($byId.ContainsKey([int]$p.ParentProcessId)) { $byId[[int]$p.ParentProcessId].Name } else { '(not running)' }
    $stopped = if ($stops -contains $id) { 'StopServer stops and waits for it' } else { 'StopServer does NOT stop or wait for it' }
    $holds = if ($openers -contains $id) { 'HAS THE FOLDER ITSELF OPEN' } else { 'does not have the folder itself open' }
    Say ('  pid {0} {1} (parent {2} {3}, started {4}): {5}; {6}' -f $id, $p.Name, $p.ParentProcessId, $parentName, $started, $stopped, $holds)
    Say ('    command line: ' + $(if ($p.CommandLine) { $p.CommandLine } else { '(none given)' }))
}
$outside = @($openers | Where-Object { -not $tree.ContainsKey($_) })
if ($outside.Count) { Say ('  holding the folder and not of the server: ' + (($outside | ForEach-Object { 'pid ' + $_ + ' ' + (Get-ThornswoodProcessWords $snap.Procs $_) }) -join '; ')) }

# ---- 4. Defender's settings for the folder ----------------------------------
Say ''
Say '4. Windows Defender and this folder:'
try {
    $st = Get-MpComputerStatus -ErrorAction Stop
    Say ('  real-time protection on: ' + $st.RealTimeProtectionEnabled + '; on-access scan on: ' + $st.OnAccessProtectionEnabled + '; antivirus on: ' + $st.AntivirusEnabled)
} catch { Bad ('Defender''s status: ' + $_.Exception.Message) }
try {
    $pref = Get-MpPreference -ErrorAction Stop
    $ex = @($pref.ExclusionPath | Where-Object { $_ })
    $covers = @($ex | Where-Object { $Root.StartsWith($_.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) -and ($Root.Length -eq $_.TrimEnd('\').Length -or $Root[$_.TrimEnd('\').Length] -eq '\') })
    Say ('  excluded paths: ' + $(if ($ex.Count) { $ex -join ', ' } else { 'none' }))
    Say ('  ' + $Root + ' is ' + $(if ($covers.Count) { 'excluded (by ' + ($covers -join ', ') + ')' } else { 'scanned: no excluded path covers it' }))
    $exP = @($pref.ExclusionProcess | Where-Object { $_ })
    Say ('  excluded processes: ' + $(if ($exP.Count) { $exP -join ', ' } else { 'none' }))
} catch { Bad ('Defender''s settings: ' + $_.Exception.Message) }

# ---- 5. Defender's own log for a window --------------------------------------
if ($from) {
    $to = $from.AddMinutes($DefenderMinutes)
    $offset = [TimeZoneInfo]::Local.GetUtcOffset($from)
    Say ''
    Say ('5. Defender''s log (MPLog) from {0} to {1} UTC; a line without a Z is read as box time, UTC{2}{3}:' -f $from.ToString('yyyy-MM-dd HH:mm'), $to.ToString('HH:mm'), $(if ($offset -lt [TimeSpan]::Zero) { '-' } else { '+' }), $offset.Duration().ToString('hh\:mm'))
    $dir = Join-Path $env:ProgramData 'Microsoft\Windows Defender\Support'
    $logs = @(Get-ChildItem -LiteralPath $dir -Filter 'MPLog-*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    if (-not $logs.Count) { Bad ('no MPLog-*.log in ' + $dir) }
    $naming = @()
    $other = @()
    $leaf = Split-Path -Leaf $Root
    foreach ($f in $logs) {
        $first = $null
        $last = $null
        try {
            $fs = New-Object IO.FileStream($f.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            # UTF-16 when it starts with that byte order mark, else UTF-8.
            $b0 = $fs.ReadByte(); $b1 = $fs.ReadByte(); $null = $fs.Seek(0, [IO.SeekOrigin]::Begin)
            $enc = if ($b0 -eq 0xFF -and $b1 -eq 0xFE) { [Text.Encoding]::Unicode } else { [Text.Encoding]::UTF8 }
            $rd = New-Object IO.StreamReader($fs, $enc, $true)
            try {
                while ($null -ne ($line = $rd.ReadLine())) {
                    $m = [regex]::Match($line, '^\s*(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(\.\d+)?(Z)?')
                    if (-not $m.Success) { continue }
                    $t = [DateTime]::ParseExact($m.Groups[1].Value, 'yyyy-MM-ddTHH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
                    $utc = if ($m.Groups[3].Success) { [DateTime]::SpecifyKind($t, 'Utc') } else { [DateTime]::SpecifyKind($t, 'Local').ToUniversalTime() }
                    if (-not $first) { $first = $utc }
                    $last = $utc
                    if ($utc -lt $from -or $utc -ge $to) { continue }
                    if ($line.IndexOf($leaf, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $naming += ($f.Name + ': ' + $line.Trim()) } else { $other += ($f.Name + ': ' + $line.Trim()) }
                }
            } finally { $rd.Dispose(); $fs.Dispose() }
            Say ('  {0}: {1} bytes, its lines from {2} to {3} UTC' -f $f.Name, $f.Length, $(if ($first) { $first.ToString('yyyy-MM-dd HH:mm:ss') } else { '?' }), $(if ($last) { $last.ToString('yyyy-MM-dd HH:mm:ss') } else { '?' }))
        } catch { Bad ($f.Name + ': ' + $_.Exception.Message) }
    }
    Say ('  lines in the window naming ' + $leaf + ': ' + $naming.Count)
    foreach ($l in @($naming | Select-Object -First 200)) { Say ('    ' + $l) }
    if ($naming.Count -gt 200) { Say ('    and ' + ($naming.Count - 200) + ' more') }
    Say ('  other lines in the window: ' + $other.Count)
    foreach ($l in @($other | Select-Object -First 150)) { Say ('    ' + $l) }
    if ($other.Count -gt 150) { Say ('    and ' + ($other.Count - 150) + ' more') }
}

Say ''
if ($problems) { Say ('ENDED 1: ' + $problems + ' part(s) could not be asked, said above'); exit 1 }
Say 'ENDED 0'
exit 0
