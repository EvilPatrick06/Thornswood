<#
  Wipe-Saves.ps1

      .\tools\Wipe-Saves.ps1

  Empties the server's character storage, so everybody starts again.

  It does NOT delete anything. It stops the server, renames the storage out of
  the way with today's date on it, and starts the server again on an empty one.
  The old storage sits beside the new one until you decide it can go, which
  means a wipe you regret at midnight is a rename away from being undone
  instead of gone.

  Why a wipe is on the table at all: taking a plugin out of the middle of the
  load order shifts the index of every plugin below it, and SkyMP turns a form
  id into a plugin by that index. Stored character references made under the
  old numbering then point at the wrong plugin. A wipe is the version of that
  problem with no half broken characters in it.

  Stop before you run this if people are on. It puts them out.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Task = 'Thornswood Server',
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')

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

$stamp = (Get-Date).ToString('yyyyMMdd-HHmm')

Write-Host ''
Write-Host '  THORNSWOOD  -  wipe the characters' -ForegroundColor White
Say "  on $Vps" 'DarkGray'

# ------------------------------------------------------------ what is there ---
Head 'What would go'
$lines = Remote @"
`$ErrorActionPreference = 'Continue'
`$roots = @()
foreach (`$d in (Get-ChildItem 'C:\' -Directory -EA SilentlyContinue)) {
  if (Test-Path (Join-Path `$d.FullName 'server-settings.json')) { `$roots += `$d.FullName }
}
if (`$roots.Count -eq 0) { 'NOROOT'; exit }
foreach (`$r in `$roots) {
  'ROOT|' + `$r
  foreach (`$n in @('world', 'private\characters.json')) {
    `$p = Join-Path `$r `$n
    if (-not (Test-Path `$p)) { 'NONE|' + `$n; continue }
    `$b = 0; `$c = 0
    if ((Get-Item `$p).PSIsContainer) {
      foreach (`$f in (Get-ChildItem `$p -Recurse -File -EA SilentlyContinue)) { `$b += `$f.Length; `$c++ }
    } else {
      `$b = (Get-Item `$p).Length; `$c = 1
      try {
        `$j = Get-Content `$p -Raw | ConvertFrom-Json
        'CHARS|' + @(`$j).Count
      } catch { }
    }
    'ITEM|' + `$p + '|' + `$b + '|' + `$c
  }
}
"@

$root = $null
$items = @()
foreach ($l in $lines) {
  $s = "$l"
  if ($s -eq 'NOROOT') { Die 'No server-settings.json anywhere under C:\ on that machine, so there is no server to wipe.' }
  $bits = $s -split '\|'
  switch ($bits[0]) {
    'ROOT'  { $root = $bits[1]; Say "  server at $root" 'DarkGray' }
    'ITEM'  { $items += $bits[1]; Say ("  {0,8:n1} MB  {1}   ({2} file(s))" -f ([int64]$bits[2] / 1MB), $bits[1], $bits[3]) 'Yellow' }
    'CHARS' { Say ("  {0} character record(s) in characters.json" -f $bits[1]) 'Yellow' }
    'NONE'  { Say ("  not there: {0}" -f $bits[1]) 'DarkGray' }
  }
}
if ($items.Count -eq 0) { Die 'Nothing to wipe. Either it is already empty or the paths moved.' }

# ------------------------------------------------------------------- ask it ---
Write-Host ''
Say '  Every character anybody has made on this server goes back to nothing.' 'Red'
Say '  They are renamed rather than deleted, so this is undoable today, but' 'DarkGray'
Say '  anybody who logs in after it starts over and that part is not.' 'DarkGray'
Write-Host ''
$typed = Read-Host '  Type WIPE to go ahead'
if ($typed -cne 'WIPE') { Die 'Left alone.' }

# ------------------------------------------------------------------- do it ---
Head 'Stopping the server'
$out = Remote @"
`$ErrorActionPreference = 'Continue'
`$null = & schtasks /end /tn '$Task' 2>&1
Start-Sleep -Seconds 3
foreach (`$p in (Get-Process -Name 'skymp*','node' -EA SilentlyContinue)) {
  if ("`$(`$p.Path)" -like '*Thornswood-Server*') { 'still running: ' + `$p.ProcessName + ' ' + `$p.Id }
}
'stopped'
"@
foreach ($l in $out) { Say "  $l" }

Head 'Moving the old storage aside'
$moved = Remote @"
`$ErrorActionPreference = 'Continue'
`$r = '$root'
foreach (`$n in @('world', 'private\characters.json')) {
  `$p = Join-Path `$r `$n
  if (-not (Test-Path `$p)) { continue }
  `$leaf = Split-Path -Leaf `$p
  `$dir  = Split-Path -Parent `$p
  if (`$leaf -like '*.json') { `$to = Join-Path `$dir ('characters-before-$stamp.json') }
  else { `$to = Join-Path `$dir ('world-before-$stamp') }
  try { Move-Item -LiteralPath `$p -Destination `$to -Force -EA Stop; 'moved  ' + `$p + '  ->  ' + `$to }
  catch { 'FAILED ' + `$p + '  ' + `$_.Exception.Message }
}
"@
$bad = $false
foreach ($l in $moved) {
  if ("$l" -match '^FAILED') { $bad = $true; Say "  $l" 'Red' } else { Say "  $l" 'Green' }
}
if ($bad) {
  Say '  The server is stopped. Start it again from the panel or re-run once' 'Yellow'
  Say '  whatever is holding those files has let go.' 'Yellow'
}

Head 'Starting it again'
$out = Remote @"
`$ErrorActionPreference = 'Continue'
`$null = & schtasks /run /tn '$Task' 2>&1
Start-Sleep -Seconds 12
`$r = '$root'
`$lg = Join-Path `$r 'server.log'
if (Test-Path `$lg) { Get-Content `$lg -Tail 6 | ForEach-Object { 'log  ' + `$_ } }
`$cf = Join-Path `$r 'private\characters.json'
if (Test-Path `$cf) {
  try { `$j = Get-Content `$cf -Raw | ConvertFrom-Json; 'now  ' + @(`$j).Count + ' character record(s)' } catch { 'now  characters.json is there but unreadable yet' }
} else { 'now  no characters.json yet, which is what empty looks like' }
"@
foreach ($l in $out) { Say "  $l" 'DarkGray' }

Head 'Done'
Say '  The old storage is beside the new one with today''s date on it.' 'Green'
Say '  Leave it a week. Clean-Everything.ps1 will offer it once you are sure.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
