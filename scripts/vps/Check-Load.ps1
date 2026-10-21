<#
  Check-Load.ps1

      .\scripts\vps\Check-Load.ps1            what the VPS has and what it is using
      .\scripts\vps\Check-Load.ps1 -Watch 10  sample every 10 seconds until you stop it

  Answers the only question worth asking before paying for a bigger server:
  what is this one actually running out of.

  Run the plain version now for a baseline, then run -Watch while people are on
  and playing. A server that idles at 8% and peaks at 30% with six people needs
  nothing. One that sits at 70% with two people needs help today.

  Reads only. Changes nothing.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '',
  [string]$User = '',
  [int]$Watch   = 0,
  [switch]$NoPause
)


$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$ErrorActionPreference = 'Stop'   # before any file loads, so one that is missing stops here (#3006)
. (Join-Path $Here 'Vps.ps1')
. (Join-Path $Here 'Send-Script.ps1')
if (-not $User) { $User = Get-ThornswoodVpsUser }
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=yes')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

function Remote($script) {
  # Send-Script.ps1 (issue #1070): a long script goes on ssh's standard input
  # (nothing of it is left on the box), and the far side's exit code comes back.
  return Invoke-ThornswoodRemote -Target "$User@$Vps" -SshArgs $ssh -Script $script
}

Write-Host ''
Write-Host '  THORNSWOOD  -  what the server has, and what it is using' -ForegroundColor White

Head 'The machine'
Remote @"
`$ErrorActionPreference = 'Continue'
`$cs = Get-CimInstance Win32_ComputerSystem
`$os = Get-CimInstance Win32_OperatingSystem
`$cpu = @(Get-CimInstance Win32_Processor)
'cpu       ' + `$cpu[0].Name.Trim()
'cores     ' + (`$cpu | Measure-Object -Property NumberOfCores -Sum).Sum + ' physical, ' + `$cs.NumberOfLogicalProcessors + ' logical'
'memory    ' + [math]::Round(`$cs.TotalPhysicalMemory / 1GB, 1) + ' GB total, ' + [math]::Round(`$os.FreePhysicalMemory / 1MB, 1) + ' GB free'
'windows   ' + `$os.Caption
'up since  ' + `$os.LastBootUpTime
foreach (`$d in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
  'disk ' + `$d.DeviceID + '   ' + [math]::Round(`$d.Size / 1GB, 1) + ' GB total, ' +
    [math]::Round(`$d.FreeSpace / 1GB, 1) + ' GB free  (' +
    [math]::Round(100 * `$d.FreeSpace / `$d.Size, 0) + '% free)'
}
"@ | ForEach-Object { Say "  $_" }

Head 'What Thornswood is using right now'
$sample = @"
`$ErrorActionPreference = 'Continue'
`$os = Get-CimInstance Win32_OperatingSystem
`$freeMb = [math]::Round(`$os.FreePhysicalMemory / 1KB, 0)
`$totMb  = [math]::Round(`$os.TotalVisibleMemorySize / 1KB, 0)

# One second apart, because a single reading of processor time is meaningless.
`$c1 = (Get-Counter '\Processor(_Total)\% Processor Time' -EA SilentlyContinue).CounterSamples[0].CookedValue
Start-Sleep -Seconds 1
`$c2 = (Get-Counter '\Processor(_Total)\% Processor Time' -EA SilentlyContinue).CounterSamples[0].CookedValue
`$cpu = [math]::Round(((`$c1 + `$c2) / 2), 0)

'cpu       ' + `$cpu + '%   memory  ' + (`$totMb - `$freeMb) + ' / ' + `$totMb + ' MB used'

`$want = 'skymp','SkyrimSE','node','python','nginx','caddy'
foreach (`$p in (Get-Process -EA SilentlyContinue | Where-Object { `$want -contains `$_.ProcessName })) {
  '  ' + `$p.ProcessName.PadRight(12) + [math]::Round(`$p.WorkingSet64 / 1MB, 0).ToString().PadLeft(6) + ' MB   pid ' + `$p.Id
}

# Who is actually on. The gamemode publishes this every few seconds.
# It writes {"now":3,...}. This read .count, which it has never written, and
# fell back to counting the object itself, so it said 1 whoever was on. The
# folder is named because the live and dev servers each have one.
foreach (`$d in (Get-ChildItem 'C:\' -Directory -EA SilentlyContinue)) {
  `$f = Join-Path `$d.FullName 'data\online.json'
  if (Test-Path `$f) {
    try {
      `$o = Get-Content `$f -Raw | ConvertFrom-Json
      'online    ' + `$(if (`$null -ne `$o.now) { `$o.now } else { '?' }) + ' on ' + `$d.Name
    } catch { }
  }
}
"@

if ($Watch -gt 0) {
  Say "  sampling every $Watch seconds. Ctrl+C to stop." 'DarkGray'
  Write-Host ''
  while ($true) {
    $t = (Get-Date).ToString('HH:mm:ss')
    Remote $sample | ForEach-Object { Say ("  $t  " + $_) }
    Start-Sleep -Seconds $Watch
  }
} else {
  Remote $sample | ForEach-Object { Say "  $_" }
}

Head 'What to make of it'
Say '  Upgrade if any of these is true:' 'DarkGray'
Say '    memory total is under 4 GB' 'DarkGray'
Say '    cpu sits above 60% with only a handful of people on' 'DarkGray'
Say '    the disk with the installer on it is under 20% free' 'DarkGray'
Say '  Otherwise get people on and run -Watch before spending anything.' 'DarkGray'

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
