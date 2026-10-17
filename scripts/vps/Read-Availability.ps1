<#
  Read-Availability.ps1

      .\scripts\vps\Read-Availability.ps1                     reads C:\Thornswood-Watch\alerts.jsonl, the last 28 days
      .\scripts\vps\Read-Availability.ps1 -Path x.jsonl       reads a copy brought down from the box instead
      .\scripts\vps\Read-Availability.ps1 -Days 7             a shorter window, ending now
      .\scripts\vps\Read-Availability.ps1 -From 2026-10-01 -To 2026-10-29   a window of its own

  Says how many minutes each service was down over a window, and what share
  of the window it was up, from the down and back lines the watchdog writes
  into alerts.jsonl. Issue #2183.

  WHY THIS EXISTS. docs\SERVICE-OBJECTIVES.md proposes 99% a month for the
  site and has no baseline, because nothing turned the outbox into a figure.
  The data was already there: Watch-Services.ps1 writes one JSON line each
  time a thing goes down and one when it is back (id, at, service, kind,
  text, with at in Unix seconds), and Watch-Outside.ps1 appends lines of the
  same shape for what it sees from outside, as "outside <name>". This pairs
  them.

  HOW IT COUNTS. Only lines whose kind is down or back are read; everything
  else in the file (the disk forecast, test messages, a line that is not
  JSON) is skipped and counted. The lines are sorted by time, and for each
  service:
    - a down starts an outage; a second down before a back changes nothing
    - a back ends the outage that is open
    - a back with no down before it in the file is an outage that began
      before the file did, counted from the window's start
    - an outage still open at the end is counted to the window's end
  Every outage is cut to the window. A service with no down or back line in
  the window is not listed: no line is no recorded outage, which is not the
  same as proof it was up. Outside lines reach the box's file only when One
  could reach the box over ssh; when it could not, they went into One's own
  copy of alerts.jsonl instead.

  LIMITATIONS. Both are said in every report this prints, and on the page.
    1. The times are the watchdog run that decided, not the moment a thing
       failed or came back. A down line is written only after the check's
       window has passed (one run for a port, two runs in a row for a health
       check, five minutes a run), so down time is undercounted by up to that
       window. A back line is written after two good runs, so the end of an
       outage is late by up to a run.
    2. Nothing is counted while the watchdog itself is off: a box that is
       down, or a task that is not running, writes no down line, and that
       time reads as up.

  It does not judge anything against a target. Whether a service met its
  objective is for the page, once a baseline has been read.

  Reads only. Opens the one file named, writes nothing, connects to nothing.
#>
[CmdletBinding()]
param(
  # The watchdog's outbox, or a copy of it.
  [string]$Path = 'C:\Thornswood-Watch\alerts.jsonl',
  # How long the window is, ending at -To. Ignored when -From is given.
  [int]$Days = 28,
  # The window's start and end, as dates or ISO times. -To is now when left out.
  [string]$From,
  [string]$To,
  # Only these services, by the name in the file ('game', 'outside site').
  [string[]]$Service,
  # Hand back the numbers instead of printing them. The harness uses this.
  [switch]$PassThru,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$inv = [Globalization.CultureInfo]::InvariantCulture

$Limits = @(
  "A down line is written only after the check's window has passed (one run for a port, two in a row for a health check, five minutes a run), so down time is undercounted by up to that window, and a back line comes after two good runs, so an outage's end is late by up to a run.",
  'Nothing is counted while the watchdog itself is off: a box that is down, or a task that is not running, writes no down line, and that time reads as up.'
)

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Done([int]$code) {
  Write-Host ''
  if (-not $NoPause -and -not $PassThru) { [void](Read-Host 'Enter to close') }
  exit $code
}
function Shown([DateTimeOffset]$t) { return $t.ToLocalTime().ToString('yyyy-MM-dd HH:mm zzz', $inv) }
function Num([double]$x, [string]$f) { return $x.ToString($f, $inv) }

# A time from the command line: a date, or an ISO time. A date or time with
# no offset is this machine's local time.
function When([string]$s, [string]$what) {
  $t = [DateTimeOffset]::MinValue
  $style = [Globalization.DateTimeStyles]::AssumeLocal
  if ([DateTimeOffset]::TryParse($s, $inv, $style, [ref]$t)) { return $t }
  throw ($what + ' "' + $s + '" is not a date or time')
}

# Every down and back line in the file, in time order, and what was skipped.
function Read-Alerts([string]$file) {
  $rows = New-Object System.Collections.ArrayList
  $skipped = 0; $other = 0; $n = 0; $order = 0
  foreach ($line in [IO.File]::ReadAllLines($file)) {
    if (-not $line.Trim()) { continue }
    $n++
    $o = $null
    try { $o = $line | ConvertFrom-Json } catch { $o = $null }
    if ($null -eq $o -or $null -eq $o.at -or -not "$($o.service)" -or -not "$($o.kind)") { $skipped++; continue }
    $at = 0L
    if (-not [long]::TryParse("$($o.at)", [Globalization.NumberStyles]::Integer, $inv, [ref]$at)) { $skipped++; continue }
    $kind = "$($o.kind)".ToLowerInvariant()
    if ($kind -ne 'down' -and $kind -ne 'back') { $other++; continue }
    $order++
    [void]$rows.Add([pscustomobject]@{ At = $at; Service = "$($o.service)"; Kind = $kind; Order = $order })
  }
  $sorted = @($rows | Sort-Object At, Order)
  return [pscustomobject]@{ Rows = $sorted; Lines = $n; Skipped = $skipped; Other = $other }
}

# The outages of each service as [start, end] in Unix seconds, before they
# are cut to the window. $null for a start is "before the file began", and
# $null for an end is "still down".
function Get-Outages($rows) {
  $by = [ordered]@{}
  foreach ($r in $rows) {
    if (-not $by.Contains($r.Service)) { $by[$r.Service] = @{ Open = $null; Seen = $false; List = (New-Object System.Collections.ArrayList); Extra = 0 } }
    $s = $by[$r.Service]
    if ($r.Kind -eq 'down') {
      if ($null -eq $s.Open) { $s.Open = $r.At } else { $s.Extra++ }
    } else {
      if ($null -ne $s.Open) {
        [void]$s.List.Add(@{ Start = $s.Open; End = $r.At })
        $s.Open = $null
      } elseif (-not $s.Seen) {
        [void]$s.List.Add(@{ Start = $null; End = $r.At })
      }
    }
    $s.Seen = $true
  }
  foreach ($k in @($by.Keys)) {
    $s = $by[$k]
    if ($null -ne $s.Open) { [void]$s.List.Add(@{ Start = $s.Open; End = $null }) }
  }
  return $by
}

# ------------------------------------------------------------ the window
try {
  if ($To) { $end = When $To '-To' } else { $end = [DateTimeOffset]::Now }
  if ($From) { $start = When $From '-From' }
  else {
    if ($Days -lt 1) { throw '-Days has to be 1 or more' }
    $start = $end.AddDays(-$Days)
  }
} catch {
  Say ('REFUSED  ' + $_.Exception.Message) Red
  if ($PassThru) { throw }
  Done 2
}
$s0 = $start.ToUnixTimeSeconds()
$s1 = $end.ToUnixTimeSeconds()
if ($s1 -le $s0) {
  Say ('REFUSED  the window ends (' + (Shown $end) + ') before it starts (' + (Shown $start) + ')') Red
  if ($PassThru) { throw 'the window ends before it starts' }
  Done 2
}
$span = [double]($s1 - $s0)

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
  Say ('NO FILE  ' + $Path + ' is not there. On One, bring a copy down from the box and pass it with -Path.') Red
  if ($PassThru) { throw ($Path + ' is not there') }
  Done 1
}

$read = Read-Alerts $Path
$all = Get-Outages $read.Rows
$notes = New-Object System.Collections.ArrayList
$result = New-Object System.Collections.ArrayList
foreach ($name in @($all.Keys)) {
  if ($Service -and -not ($Service -contains $name)) { continue }
  $s = $all[$name]
  $down = 0.0; $count = 0; $still = $false
  foreach ($o in $s.List) {
    $a = $o.Start; $b = $o.End
    if ($null -eq $a) { $a = $s0 }
    if ($null -eq $b) { $b = $s1 }
    $a = [Math]::Max([double]$a, [double]$s0)
    $b = [Math]::Min([double]$b, [double]$s1)
    if ($b -le $a) { continue }
    $count++
    $down += ($b - $a)
    if ($null -eq $o.Start) { [void]$notes.Add($name + ': a back line with no down before it in the file, counted from the start of the window') }
    if ($null -eq $o.End) { $still = $true; [void]$notes.Add($name + ': still down at the end of the window, counted to its end') }
  }
  if ($s.Extra) { [void]$notes.Add($name + ': ' + $s.Extra + ' down line(s) while already down, which change nothing') }
  if ($count -eq 0) { continue }
  [void]$result.Add([pscustomobject]@{
    Service      = $name
    Outages      = $count
    DownSeconds  = [long][Math]::Round($down)
    DownMinutes  = [Math]::Round($down / 60, 1)
    Availability = [Math]::Round(100 * (1 - $down / $span), 3)
    StillDown    = $still
  })
}

$oldest = $null; $newest = $null
if ($read.Rows.Count) {
  $oldest = [DateTimeOffset]::FromUnixTimeSeconds($read.Rows[0].At)
  $newest = [DateTimeOffset]::FromUnixTimeSeconds($read.Rows[$read.Rows.Count - 1].At)
}
$report = [pscustomobject]@{
  Path          = $Path
  From          = $start
  To            = $end
  WindowMinutes = [Math]::Round($span / 60, 1)
  Lines         = $read.Lines
  DownOrBack    = $read.Rows.Count
  Other         = $read.Other
  Skipped       = $read.Skipped
  Oldest        = $oldest
  Newest        = $newest
  Services      = @($result | Sort-Object Service)
  Notes         = @($notes)
  Limitations   = $Limits
}
if ($PassThru) { return $report }

# ------------------------------------------------------------ the report
Head 'Availability from the watchdog''s down and back lines'
Say ('  file      ' + $Path)
Say ('  window    ' + (Shown $start) + ' to ' + (Shown $end) + ' (' + (Num ($span / 86400) '0.##') + ' days, ' + (Num ($span / 60) '0') + ' minutes)')
Say ('  lines     ' + $read.Lines + ' read: ' + $read.Rows.Count + ' down or back, ' + $read.Other + ' of other kinds, ' + $read.Skipped + ' skipped (not JSON, or no time, service or kind)')
if ($oldest) { Say ('  oldest    ' + (Shown $oldest) + '   newest ' + (Shown $newest)) }
if ($oldest -and $oldest -gt $start) { Say ('  The oldest down or back line is after the window starts. Before it the file says nothing either way.') Yellow }

Head 'Down per service'
if (-not $result.Count) {
  Say '  No outage recorded in this window.'
} else {
  Say ('  {0,-22} {1,8} {2,10} {3,13}' -f 'service', 'outages', 'down min', 'availability')
  foreach ($r in $report.Services) {
    $mark = ''
    if ($r.StillDown) { $mark = '  still down' }
    Say ('  {0,-22} {1,8} {2,10} {3,13}{4}' -f $r.Service, $r.Outages, (Num $r.DownMinutes '0.0'), ((Num $r.Availability '0.000') + '%'), $mark)
  }
}
Say '  A service with no down or back line in the window is not listed. No line is no recorded outage, not proof it was up.' DarkGray
foreach ($n in $notes) { Say ('  note: ' + $n) Yellow }

Head 'Limitations'
Say ('  1. ' + $Limits[0])
Say ('  2. ' + $Limits[1])
Say ''
Say '  This does not judge any service against a target. docs\SERVICE-OBJECTIVES.md does that once a baseline has been read.' DarkGray
Done 0
