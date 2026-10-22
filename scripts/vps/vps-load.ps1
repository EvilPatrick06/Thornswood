<#
  vps-load.ps1

  Runs ON the VPS, every five minutes, as the scheduled task that
  Watch-Load.ps1 -Install puts there. Not meant to be run from this machine,
  except by tests\test-watch-load.ps1, which runs it against a scratch folder
  to prove the line it writes.

  WHY THIS EXISTS. The website, the game server, the voice service and the bot
  all run on one five core box (MOVING-THE-SERVER.md), and until this nothing
  kept a number for any of them. Check-Load.ps1 takes a reading while somebody
  sits and watches it, and Watch-Services.ps1 knocks on seven ports and
  restarts whatever does not answer. Neither writes anything down. So the
  choice between a bigger box and splitting the services apart rested on one
  reading taken on 15 September, and in the To Do List's words "nothing today
  would tell you which one is the problem".

  Each run appends ONE line to load.csv beside the watchdog:

    time            when, with the box's own offset from UTC
    cores           logical processors. Every CPU figure is a share of these.
    idle_s          seconds the processors have sat idle since boot, all of
                    them added together. Two lines apart, that is the box's CPU.
    mem_used_mb     memory in use across the whole box, and what it has
    mem_total_mb
    disk_free_gb    free space on C:
    net_in_bytes    bytes in and out since the counters last reset, through
    net_out_bytes   the card the internet comes in on (the default route)
    online          people on the live game server and on the dev one, read
    devonline       from the online.json each gamemode writes, and only while
                    that server is up, because the file outlives the process

    and for each service, <name>_pid, <name>_cpu_s (processor seconds since
    the process started), <name>_mem_mb (working set right now) and
    <name>_io_bytes (every byte of I/O the process has issued, disk and
    network together: Windows keeps no per-process network count that is
    cheap to read, so the card's own count above is the real network figure).

  Every counter is written RAW, as a running total, and Read-Load.ps1 takes the
  difference between two lines. That keeps this stateless: it reads nothing
  back, so a crash, a reboot or a restarted service costs the one interval it
  lands in and nothing after it. A pid that changes between two lines is a
  restart, and that interval is left out for that service rather than guessed.

  HOW EACH SERVICE IS FOUND. By the port it listens on, the same thing the
  watchdog asks. Not by command line, which is what looked right at first:
  the live and dev game servers are both started as

      node.exe dist_back/skymp5-server.js

  from their own folders (Install-ThornswoodServer.ps1 writes that and
  vps-dev-instance.ps1 copies the same arguments), so the two command lines
  are identical and only the port tells them apart. Caddy is found by name and
  the bot as the python its ThornswoodBot service started (#3189), because
  neither of those has a port of its own to ask.

  CHEAP, AND NEVER LOUD. One process query, one listener query and a few small
  reads, about a second. Each part is its own try, so a part that fails leaves
  its columns empty and the line still goes in. It is its own script and its
  own task, so nothing in here can reach the watchdog's restart logic.
  Anything that goes wrong is one line in load.log.

  The file rolls to load.1.csv at 4 MB, which is about five weeks. A header
  that no longer matches, because a service was added below, rolls it too, so
  one file never carries two shapes.

  ASCII only on purpose: Windows PowerShell 5.1 reads a file with no byte
  order mark in the local code page.
#>
[CmdletBinding()]
param(
  [string]$Root        = 'C:\Thornswood-Watch',
  # name=port pairs laid over the ports below. Empty on the box. The harness
  # uses it to point one service at a port it is holding open itself.
  [string]$Ports       = '',
  [string]$GameRoot    = 'C:\Thornswood-Server',
  [string]$DevGameRoot = 'C:\Thornswood-Server-Dev',
  [long]$RollAt        = 4MB
)

$ErrorActionPreference = 'Continue'
$inv = [Globalization.CultureInfo]::InvariantCulture
$csv = Join-Path $Root 'load.csv'
$old = Join-Path $Root 'load.1.csv'
$log = Join-Path $Root 'load.log'

function Note($line) {
  try {
    if ((Test-Path -LiteralPath $log) -and ((Get-Item -LiteralPath $log).Length -gt 256KB)) {
      $keep = @(Get-Content -LiteralPath $log -Tail 500)
      Set-Content -LiteralPath $log -Value $keep -Encoding ASCII
    }
    Add-Content -LiteralPath $log -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss', $inv) + '  ' + $line) -Encoding ASCII
  } catch { }
}

# Numbers go in with a full stop for the decimal point whatever the box's
# language is, so the file reads the same on any machine.
function Num($x, [int]$digits) {
  if ($null -eq $x) { return '' }
  return ([math]::Round([double]$x, $digits)).ToString($inv)
}

# The same seven the watchdog looks after, in the same order.
$services = @(
  @{ Name = 'caddy';    Exe  = 'caddy.exe' },
  @{ Name = 'website';  Port = 3001 },
  @{ Name = 'game';     Port = 3000 },
  @{ Name = 'voice';    Port = 7778 },
  @{ Name = 'bot';      Exe  = 'python.exe'; Service = 'ThornswoodBot' },
  @{ Name = 'devgame';  Port = 7788 },
  @{ Name = 'devvoice'; Port = 7789 }
)
foreach ($pair in ($Ports -split ',')) {
  $bits = $pair -split '='
  if ($bits.Count -ne 2) { continue }
  $n = 0
  if (-not [int]::TryParse($bits[1].Trim(), [ref]$n)) { continue }
  foreach ($s in $services) {
    if ($s.Name -eq $bits[0].Trim() -and $s.ContainsKey('Port')) { $s.Port = $n }
  }
}

$cols = @('time', 'cores', 'idle_s', 'mem_used_mb', 'mem_total_mb', 'disk_free_gb',
          'net_in_bytes', 'net_out_bytes', 'online', 'devonline')
foreach ($s in $services) {
  foreach ($k in @('pid', 'cpu_s', 'mem_mb', 'io_bytes')) { $cols += ($s.Name + '_' + $k) }
}
$header = $cols -join ','

$v = @{}
foreach ($c in $cols) { $v[$c] = '' }

try {
  $v['time']  = (Get-Date).ToString("yyyy-MM-dd'T'HH:mm:sszzz", $inv)
  $v['cores'] = ([Environment]::ProcessorCount).ToString($inv)

  # ---- every process, once ------------------------------------------------
  # Without the command line, which is the slow part of this query and is
  # only wanted for the bot, so the bot's lookup asks for it on its own.
  $procs = @()
  try {
    $procs = @(Get-CimInstance Win32_Process -EA Stop -Property ProcessId, Name,
                 KernelModeTime, UserModeTime, WorkingSetSize,
                 ReadTransferCount, WriteTransferCount, OtherTransferCount)
  } catch { Note ('could not list processes: ' + $_.Exception.Message) }
  $byPid = @{}
  foreach ($p in $procs) { $byPid[[int]$p.ProcessId] = $p }

  # The System Idle Process keeps one thread per logical processor, and its
  # kernel time is the idle time of all of them added together.
  if ($byPid.ContainsKey(0) -and $null -ne $byPid[0].KernelModeTime) {
    $v['idle_s'] = Num ([double]$byPid[0].KernelModeTime / 1e7) 2
  }

  # ---- memory and disk ----------------------------------------------------
  try {
    $os = Get-CimInstance Win32_OperatingSystem -EA Stop -Property FreePhysicalMemory, TotalVisibleMemorySize
    $v['mem_total_mb'] = Num ([double]$os.TotalVisibleMemorySize / 1KB) 0
    $v['mem_used_mb']  = Num (([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) / 1KB) 0
  } catch { Note ('could not read memory: ' + $_.Exception.Message) }

  try {
    $d = Get-CimInstance Win32_LogicalDisk -EA Stop -Filter "DeviceID='C:'" -Property FreeSpace
    if ($d) { $v['disk_free_gb'] = Num ([double]$d.FreeSpace / 1GB) 2 }
  } catch { Note ('could not read C: ' + $_.Exception.Message) }

  # ---- network ------------------------------------------------------------
  # The card with a gateway is the one the internet comes through.
  #
  # Read through .NET, not Get-NetAdapterStatistics or Get-NetRoute. Measured
  # on 24 September under Windows PowerShell 5.1: loading the modules behind
  # those two cost 3.2 and 2.4 seconds on their first call, which is every
  # call for a task that starts a fresh process each time, and on that
  # machine Get-NetAdapterStatistics did not list the Ethernet card carrying
  # the default route at all. This found that card in 165 ms.
  try {
    [uint64]$in = 0
    [uint64]$out = 0
    $cards = 0
    foreach ($nic in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
      if ($nic.OperationalStatus -ne 'Up') { continue }
      if ($nic.NetworkInterfaceType -eq 'Loopback') { continue }
      $gw = @($nic.GetIPProperties().GatewayAddresses | Where-Object {
        -not $_.Address.Equals([Net.IPAddress]::Any) -and -not $_.Address.Equals([Net.IPAddress]::IPv6Any) })
      if ($gw.Count -eq 0) { continue }
      $st = $nic.GetIPStatistics()
      $in  += [uint64]$st.BytesReceived
      $out += [uint64]$st.BytesSent
      $cards++
    }
    if ($cards -gt 0) {
      $v['net_in_bytes']  = $in.ToString($inv)
      $v['net_out_bytes'] = $out.ToString($inv)
    }
  } catch { Note ('could not read the network card: ' + $_.Exception.Message) }

  # ---- who listens where --------------------------------------------------
  # netstat rather than Get-NetTCPConnection, for the same reason: 134 ms
  # against 1 to 2 seconds for the cmdlet on the same machine. A listener is
  # told by its far end being port 0, not by the word LISTENING, because that
  # word is translated on a Windows that is not in English.
  $listen = @{}
  try {
    foreach ($row in @(& netstat.exe -ano -p TCP 2>$null)) {
      $f = @("$row".Trim() -split '\s+')
      if ($f.Count -lt 5 -or $f[0] -ne 'TCP' -or $f[2] -notmatch ':0$') { continue }
      $port = 0
      $owner = 0
      if (-not [int]::TryParse($f[1].Substring($f[1].LastIndexOf(':') + 1), [ref]$port)) { continue }
      if (-not [int]::TryParse($f[$f.Count - 1], [ref]$owner)) { continue }
      if (-not $listen.ContainsKey($port)) { $listen[$port] = @() }
      if ($listen[$port] -notcontains $owner) { $listen[$port] += $owner }
    }
  } catch { Note ('could not list listening ports: ' + $_.Exception.Message) }

  # ---- each service -------------------------------------------------------
  foreach ($s in $services) {
    $ids = @()
    if ($s.ContainsKey('Port')) {
      if ($listen.ContainsKey($s.Port)) { $ids = @($listen[$s.Port]) }
    } elseif ($s.ContainsKey('Service')) {
      # The bot is the python its service started, nothing else (#3189). Any
      # python with Thornswood-Bot in its command line used to count, so a
      # harness's stand-in bot on a runner turned up as a second bot process
      # and every one was read as a restart: 48 in ten days, with none.
      try {
        $svc = Get-CimInstance Win32_Service -EA Stop -Filter ("Name='" + $s.Service + "'") -Property ProcessId
        if ($svc -and $svc.ProcessId) {
          foreach ($p in @(Get-CimInstance Win32_Process -EA Stop -Filter ("Name='" + $s.Exe + "' AND ParentProcessId=" + [int]$svc.ProcessId) -Property ProcessId)) {
            $ids += [int]$p.ProcessId
          }
        }
      } catch { Note ('could not look for ' + $s.Name + ': ' + $_.Exception.Message) }
    } else {
      foreach ($p in $procs) {
        if ("$($p.Name)" -eq $s.Exe) { $ids += [int]$p.ProcessId }
      }
    }
    $ids = @($ids | Where-Object { $byPid.ContainsKey($_) } | Sort-Object -Unique)
    if ($ids.Count -eq 0) { continue }

    $cpu = 0.0
    [uint64]$ws = 0
    [uint64]$io = 0
    foreach ($id in $ids) {
      $p = $byPid[$id]
      $cpu += ([double]$p.KernelModeTime + [double]$p.UserModeTime) / 1e7
      $ws  += [uint64]$p.WorkingSetSize
      $io  += [uint64]$p.ReadTransferCount + [uint64]$p.WriteTransferCount + [uint64]$p.OtherTransferCount
    }
    $v[$s.Name + '_pid']      = ($ids -join ' ')
    $v[$s.Name + '_cpu_s']    = Num $cpu 2
    $v[$s.Name + '_mem_mb']   = Num ([double]$ws / 1MB) 0
    $v[$s.Name + '_io_bytes'] = $io.ToString($inv)
  }

  # ---- who is on ----------------------------------------------------------
  # Only while that server is up. The gamemode rewrites online.json when the
  # number moves and nothing clears it when the process stops, so a server
  # that went down with six on would otherwise report six all night.
  foreach ($o in @(@{ Col = 'online';    Root = $GameRoot;    Pid = 'game_pid' },
                   @{ Col = 'devonline'; Root = $DevGameRoot; Pid = 'devgame_pid' })) {
    if ($v[$o.Pid] -eq '') { continue }
    try {
      $f = Join-Path $o.Root 'data\online.json'
      if (Test-Path -LiteralPath $f) {
        $j = Get-Content -LiteralPath $f -Raw -EA Stop | ConvertFrom-Json
        if ($null -ne $j.now) { $v[$o.Col] = ([int]$j.now).ToString($inv) }
      }
    } catch { }
  }
} catch { Note ('the reading stopped part way: ' + $_.Exception.Message) }

# ---- write it -------------------------------------------------------------
try {
  if (-not (Test-Path -LiteralPath $Root)) { $null = New-Item -ItemType Directory -Path $Root -Force }
  if (Test-Path -LiteralPath $csv) {
    $first = "$(Get-Content -LiteralPath $csv -TotalCount 1)"
    $size = (Get-Item -LiteralPath $csv).Length
    if ($first -ne $header -or $size -ge $RollAt) {
      if (Test-Path -LiteralPath $old) { [IO.File]::Delete($old) }
      [IO.File]::Move($csv, $old)
    }
  }
  if (-not (Test-Path -LiteralPath $csv)) {
    [IO.File]::WriteAllText($csv, $header + "`r`n", [Text.Encoding]::ASCII)
  }
  $line = (@($cols | ForEach-Object { $v[$_] })) -join ','
  [IO.File]::AppendAllText($csv, $line + "`r`n", [Text.Encoding]::ASCII)
} catch { Note ('could not write ' + $csv + ': ' + $_.Exception.Message) }

exit 0
