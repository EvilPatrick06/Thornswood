<#
  Check-Load.ps1

      .\tools\Check-Load.ps1            what the VPS has and what it is using
      .\tools\Check-Load.ps1 -Watch 10  sample every 10 seconds until you stop it

  Answers the only question worth asking before paying for a bigger server:
  what is this one actually running out of.

  Run the plain version now for a baseline, then run -Watch while people are on
  and playing. A server that idles at 8% and peaks at 30% with six people needs
  nothing. One that sits at 70% with two people needs help today.

  Reads only. Changes nothing.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [int]$Watch   = 0,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  $cmd = "powershell -NoProfile -EncodedCommand $e"

  # A long script does not fit on a command line, and nothing says so.
  #
  # sshd on Windows hands the command to cmd.exe, which stops at 8,191
  # characters. Base64 of UTF-16 is about 2.7 times the script, so a block of
  # any size arrives cut in half and PowerShell then complains about a brace or
  # a token in a script nobody can see. Deploy-Docs.ps1 hit this on 17 Sep and
  # solved it; every other script here carried the short version that cannot,
  # and on 20 Sep this one truncated at 10,252 characters and reported
  # "Unexpected token '$?'" about a line fifteen above the one that was cut.
  # This is that fix, copied across so the sixteen scripts that talk to the VPS
  # all behave the same way.
  #
  # Under the limit it goes on the command line as before, because that is one
  # round trip. Over it, the script is sent as a file and run from there, which
  # has no length to run into.
  if ($cmd.Length -le 6000) {
    return & ssh @ssh "$User@$Vps" $cmd 2>&1
  }

  $far = 'C:/Windows/Temp/thornswood-remote.ps1'
  $tmp = [IO.Path]::GetTempFileName()
  try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    & scp @ssh $tmp "$User@${Vps}:$far" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not send a script to $Vps" }
    # The path goes across as it is. Windows PowerShell takes forward
    # slashes, and converting them was how this shipped with the slashes
    # stripped out of it entirely: C:WindowsTempthornswood-remote.ps1.
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File '$far'" 2>&1
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
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
