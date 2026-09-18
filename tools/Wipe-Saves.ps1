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
  & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" 2>&1
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
