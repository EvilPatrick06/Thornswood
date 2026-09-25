<#
  Watch-Load.ps1

      .\scripts\vps\Watch-Load.ps1            bring the record down and say what it shows
      .\scripts\vps\Watch-Load.ps1 -Install   put the collector on the server
      .\scripts\vps\Watch-Load.ps1 -Remove    take it off again, leaving the record

  The website, the game server, the voice service and the bot share one five
  core box, and nothing kept a number for any of them. Check-Load.ps1 is a
  reading while you watch; Watch-Services.ps1 restarts what stops. Neither
  writes anything down, so there was no way to tell which of them a bigger box
  or a split would be for.

  -Install puts vps-load.ps1 on the box as C:\Thornswood-Watch\load.ps1 and a
  task that runs it every five minutes as SYSTEM. Each run appends one line to
  C:\Thornswood-Watch\load.csv: the box's CPU, memory, free disk and network
  bytes, the people on, and for each of the seven services the watchdog looks
  after, its processor time, memory and I/O. vps-load.ps1 says what each
  column is.

  With no switches this copies load.csv (and load.1.csv, if it has rolled)
  into logs\ here and runs Read-Load.ps1 on it, which says which service leads
  CPU, memory and I/O, and when the busiest hour was.

  Leave it a week that includes a busy evening before reading anything into
  it. What to do about the answer is for Patrick and Djinn in #staff-general.

  The collector is its own task, not part of the watchdog, so it can never get
  in the way of a restart. -Remove takes the task off and leaves the record.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Root = 'C:\Thornswood-Watch',
  [string]$Task = 'Thornswood Load',
  [string]$Out  = '',
  [switch]$Install,
  [switch]$Remove,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=accept-new')

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Out) { $Out = Join-Path (Split-Path -Parent (Split-Path -Parent $Here)) 'logs' }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) {
  Write-Host ''
  Write-Host "STOP. $m" -ForegroundColor Red
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}

function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  $cmd = "powershell -NoProfile -EncodedCommand $e"

  # A long script does not fit on a command line, and nothing says so.
  #
  # sshd on Windows hands the command to cmd.exe, which stops at 8,191
  # characters. Base64 of UTF-16 is about 2.7 times the script, so a block of
  # any size arrives cut in half and PowerShell then complains about a brace or
  # a token in a script nobody can see. Deploy-Docs.ps1 hit this on 17 Sep and
  # solved it, and this is that fix, copied across so every script that talks
  # to the VPS behaves the same way. The install below is always over the
  # line, because it carries the whole collector.
  #
  # Under the limit it goes on the command line, because that is one round
  # trip. Over it, the script is sent as a file and run from there, which has
  # no length to run into.
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
    # And bare, with no quotes round it; the path above is ours and has no
    # spaces. Measured on this machine on 24 September, not on the VPS: bare
    # runs whether cmd.exe or Windows PowerShell hands the line on, and the
    # old form, the path in single quotes, fails under cmd.exe. The old form
    # did run on the VPS on 20 and 21 September, so which shell sshd uses
    # there is not known, and bare is the form that works under either.
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}

Write-Host ''
Write-Host '  THORNSWOOD  -  what the server uses, over a week' -ForegroundColor White

# ------------------------------------------------------------------ off ---
if ($Remove) {
  Head 'Taking it off'
  $out = Remote @"
`$ErrorActionPreference = 'Continue'
`$null = & schtasks /delete /tn '$Task' /f 2>&1
if (`$LASTEXITCODE -eq 0) { 'the task is gone' } else { 'there was no task called $Task' }
'the record is still at $Root\load.csv'
"@
  foreach ($l in $out) { Say "  $l" }
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

# ------------------------------------------------------------------- on ---
if ($Install) {
  $collector = Join-Path $Here 'vps-load.ps1'
  if (-not (Test-Path -LiteralPath $collector)) { Die 'There is no vps-load.ps1 next to this script.' }

  Head 'Checking it parses before sending it'
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($collector, [ref]$null, [ref]$errs)
  if ($errs -and $errs.Count) {
    $errs | Select-Object -First 5 | ForEach-Object { Say ('  ' + $_.Message) 'Red' }
    Die 'vps-load.ps1 does not parse. Nothing was sent.'
  }
  Say '  vps-load.ps1 parses' 'Green'

  Head 'Putting it on the server'
  # Sent as base64 and written out there byte for byte, which keeps every
  # quote and backslash exactly as it is in the repo.
  $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($collector))

  $out = Remote @"
`$ErrorActionPreference = 'Continue'
if (-not (Test-Path '$Root')) { `$null = New-Item -ItemType Directory -Path '$Root' -Force }
[IO.File]::WriteAllBytes('$Root\load.ps1', [Convert]::FromBase64String('$b64'))
'wrote     $Root\load.ps1  ' + (Get-Item '$Root\load.ps1').Length + ' bytes'

# Every five minutes, as SYSTEM, so it keeps going when nobody is logged in.
# Its own task rather than a line in the watchdog, so nothing it does can hold
# up or break a restart.
`$null = & schtasks /create /tn '$Task' /sc minute /mo 5 /ru SYSTEM /rl HIGHEST /f /tr 'powershell -NoProfile -ExecutionPolicy Bypass -File $Root\load.ps1' 2>&1
if (`$LASTEXITCODE -eq 0) { 'made      the task, every five minutes' } else { 'FAILED    schtasks exited with ' + `$LASTEXITCODE }

# Once now, so any problem shows here rather than in a week.
`$null = & schtasks /run /tn '$Task' 2>&1
Start-Sleep -Seconds 12
if (Test-Path '$Root\load.csv') {
  `$all = @(Get-Content '$Root\load.csv')
  'first run: ' + (`$all.Count - 1) + ' line(s) in $Root\load.csv'
  `$all | Select-Object -Last 1 | ForEach-Object { '  ' + `$_ }
} else { 'FAILED    the first run wrote no load.csv yet' }
if (Test-Path '$Root\load.log') { Get-Content '$Root\load.log' -Tail 5 | ForEach-Object { 'load.log  ' + `$_ } }
"@

  foreach ($l in $out) {
    $c = 'Gray'
    if ("$l" -match '^FAILED') { $c = 'Red' }
    if ("$l" -match '^(wrote|made)') { $c = 'Green' }
    Say "  $l" $c
  }

  Head 'From now on'
  Say '  A line every five minutes. Leave it a week that includes a busy evening,' 'DarkGray'
  Say '  then run this with no switches to bring it down and read it.' 'DarkGray'
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

# -------------------------------------------------------------- report ---
Head 'The collector'
$out = Remote @"
`$ErrorActionPreference = 'Continue'
`$t = Get-ScheduledTask -TaskName '$Task' -EA SilentlyContinue
if (`$t) {
  `$i = Get-ScheduledTaskInfo -TaskName '$Task'
  'task      ' + `$t.State + ', last ran ' + `$i.LastRunTime + ', result ' + `$i.LastTaskResult
} else { 'task      NOT installed. Run this with -Install' }
if (Test-Path '$Root\load.csv') {
  'record    ' + [math]::Round((Get-Item '$Root\load.csv').Length / 1KB, 0) + ' KB'
} else { 'record    none yet' }
if (Test-Path '$Root\load.log') { Get-Content '$Root\load.log' -Tail 5 | ForEach-Object { 'load.log  ' + `$_ } }
"@
foreach ($l in $out) {
  $c = 'Gray'
  if ("$l" -match 'NOT installed|none yet') { $c = 'Red' }
  Say "  $l" $c
}

Head 'Bringing it down'
if (-not (Test-Path -LiteralPath $Out)) { $null = New-Item -ItemType Directory -Path $Out -Force }
$got = @()
foreach ($n in @('load.1.csv', 'load.csv')) {
  $dest = Join-Path $Out $n
  # Read on the far side and carried back as text, as Get-Logs.ps1 does. Only
  # lines that are the header or a reading are kept, so a warning ssh prints
  # on the way cannot end up in the middle of the record.
  $text = Remote "if (Test-Path -LiteralPath '$Root\$n') { Get-Content -LiteralPath '$Root\$n' }"
  $lines = @($text | ForEach-Object { "$_" } | Where-Object { $_ -match '^(time,|\d{4}-\d\d-\d\dT)' })
  if ($lines.Count -eq 0) {
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
    continue
  }
  Set-Content -LiteralPath $dest -Value $lines -Encoding ASCII
  $got += $dest
  Say ('  {0,-11} {1,6} lines   {2}' -f $n, ($lines.Count - 1), $dest)
}
if ($got.Count -eq 0) { Die 'There is no record on the box yet. Run this with -Install first.' }

& (Join-Path $Here 'Read-Load.ps1') -Path $got -NoPause:$NoPause
exit $LASTEXITCODE
