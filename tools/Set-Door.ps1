<#
  Set-Door.ps1

  Turns the game server's door on, off, or tells you what it has been seeing.

      .\tools\Set-Door.ps1              what the door is doing right now
      .\tools\Set-Door.ps1 -Connect     point it at the site and start refreshing
      .\tools\Set-Door.ps1 -Enforce     start actually turning people away
      .\tools\Set-Door.ps1 -Watch       go back to watching only
      .\tools\Set-Door.ps1 -Log 40      the last 40 lines it wrote

  Why this exists: the server has had no access control at all. Anyone who knows
  192.135.112.23:7777 can connect, and that address is on a public website.

  How the door works:

    The site knows who is in the Discord and what roles they have. The launcher
    sends the profile id it is about to play as when it checks in, so the site
    can tie a Discord account to a profile number. The game server pulls that
    list every five minutes and keeps it in data\allowed.json. Its door reads
    that list and, when enforcing, turns away anybody not on it.

  The safe order is -Connect, then leave it watching for a day, then read the
  log, then -Enforce. Turning it on before the list has filled up would turn
  away people who have simply not pressed Play since the launcher started
  sending their profile id.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Site = 'https://thornswood.net',
  [string]$DocsRoot = 'C:/Thornswood-Docs',
  [switch]$Connect,
  [switch]$Enforce,
  [switch]$Watch,
  [int]$Log = 0,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')
$docsWin = $DocsRoot.Replace('/','\')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" 2>&1
}

if ($Enforce -and $Watch) { Die 'Pick one of -Enforce or -Watch, not both.' }

Write-Host ''
Write-Host '  THORNSWOOD  -  the door on the game server' -ForegroundColor White

Head 'Finding the server'
$found = Remote @"
`$ErrorActionPreference = 'Continue'
foreach (`$d in (Get-ChildItem 'C:\' -Directory -EA SilentlyContinue)) {
  if (Test-Path (Join-Path `$d.FullName 'server-settings.json')) { 'ROOT ' + `$d.FullName }
}
"@
$root = (@($found) | Where-Object { $_ -match '^ROOT ' } | Select-Object -First 1) -replace '^ROOT ', ''
$root = "$root".Trim()
if (-not $root) { Die 'No server-settings.json anywhere on C: of the VPS.' }
Say "  $root"

# ------------------------------------------------------------- connecting ---
if ($Connect) {
  Head 'Pointing the door at the site'
  # The key is already on the VPS in the site's own config. Reading it there
  # rather than asking for it keeps it off the command line and out of your
  # PowerShell history, and means there is only one copy to rotate.
  $out = Remote @"
`$ErrorActionPreference = 'Continue'
`$root = '$root'
`$dataDir = 'data'
try {
  `$s = Get-Content (Join-Path `$root 'server-settings.json') -Raw | ConvertFrom-Json
  if (`$s.dataDir) { `$dataDir = [string]`$s.dataDir }
} catch { }
`$data = Join-Path `$root `$dataDir

`$key = ''
try {
  `$c = Get-Content '$docsWin\config.json' -Raw | ConvertFrom-Json
  `$key = [string]`$c.botKey
} catch { }
if (-not `$key) { 'NO BOT KEY in $docsWin\config.json. Run Install-Bot.ps1 first.'; exit }

`$doc = @{ site = '$Site'; key = `$key } | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path `$data 'door.json'), `$doc, (New-Object Text.UTF8Encoding(`$false)))
'door.json written, pointing at $Site'
'The gamemode picks it up within five minutes, or restart the server to be sure.'
"@
  $out | ForEach-Object { Say "  $_" }
  if ("$out" -match 'NO BOT KEY') { Die 'The door cannot ask the site for the list without it.' }
}

# ---------------------------------------------------------------- flipping ---
if ($Enforce -or $Watch) {
  $want = if ($Enforce) { 'true' } else { 'false' }
  Head $(if ($Enforce) { 'Turning the door ON' } else { 'Back to watching only' })
  $out = Remote @"
`$ErrorActionPreference = 'Continue'
`$root = '$root'
`$dataDir = 'data'
try {
  `$s = Get-Content (Join-Path `$root 'server-settings.json') -Raw | ConvertFrom-Json
  if (`$s.dataDir) { `$dataDir = [string]`$s.dataDir }
} catch { }
`$f = Join-Path (Join-Path `$root `$dataDir) 'allowed.json'
if (-not (Test-Path `$f)) { 'NO LIST YET. Run -Connect first and give it five minutes.'; exit }
`$d = Get-Content `$f -Raw | ConvertFrom-Json
`$n = @(`$d.profiles).Count
if ('$want' -eq 'true' -and `$n -lt 1) {
  'THE LIST IS EMPTY. Turning the door on now would turn away everybody.'
  exit
}
`$d.enforce = ('$want' -eq 'true')
[IO.File]::WriteAllText(`$f, (`$d | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding(`$false)))
'enforce is now $want, with ' + `$n + ' profiles on the list'
"@
  $out | ForEach-Object { Say "  $_" }
  if ("$out" -match 'THE LIST IS EMPTY|NO LIST YET') {
    Die 'Nothing was changed.'
  }
}

# ----------------------------------------------------------------- reading ---
Head 'What the door has'
$out = Remote @"
`$ErrorActionPreference = 'Continue'
`$root = '$root'
`$dataDir = 'data'
try {
  `$s = Get-Content (Join-Path `$root 'server-settings.json') -Raw | ConvertFrom-Json
  if (`$s.dataDir) { `$dataDir = [string]`$s.dataDir }
} catch { }
`$data = Join-Path `$root `$dataDir

`$f = Join-Path `$data 'allowed.json'
if (-not (Test-Path `$f)) {
  'NO allowed.json. The door is OFF and anybody can connect.'
} else {
  `$d = Get-Content `$f -Raw | ConvertFrom-Json
  'mode      ' + `$(if (`$d.enforce) { 'ENFORCING, people not on the list are turned away' } else { 'watching only, nobody is turned away' })
  'profiles  ' + @(`$d.profiles).Count
  'updated   ' + `$(if (`$d.at) { `$d.at } else { 'never, this list was written by hand' })
  foreach (`$p in @(`$d.people)) { '  ' + `$p.name + '  ' + (@(`$p.profiles) -join ', ') }
}
`$j = Join-Path `$data 'door.json'
'refreshing ' + `$(if (Test-Path `$j) { 'yes, from the site' } else { 'NO. Run -Connect, or the list never updates.' })
"@
$out | ForEach-Object { Say "  $_" }

if ($Log -gt 0) {
  Head "The last $Log lines the door wrote"
  Remote @"
`$ErrorActionPreference = 'Continue'
`$root = '$root'
`$dataDir = 'data'
try {
  `$s = Get-Content (Join-Path `$root 'server-settings.json') -Raw | ConvertFrom-Json
  if (`$s.dataDir) { `$dataDir = [string]`$s.dataDir }
} catch { }
`$l = Join-Path (Join-Path `$root `$dataDir) 'door.log'
if (Test-Path `$l) { Get-Content `$l -Tail $Log } else { 'nothing logged yet' }
"@ | ForEach-Object { Say "  $_" }
}

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
