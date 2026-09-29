<#
  Set-Door.ps1

  Turns the game server's door on, off, or tells you what it has been seeing.

      .\scripts\ops\Set-Door.ps1              what the door is doing right now
      .\scripts\ops\Set-Door.ps1 -Connect     point it at the site and start refreshing
      .\scripts\ops\Set-Door.ps1 -Enforce     start actually turning people away
      .\scripts\ops\Set-Door.ps1 -Watch       go back to watching only
      .\scripts\ops\Set-Door.ps1 -Log 40      the last 40 lines it wrote

  Why this exists: the server has had no access control at all. Anyone who knows
  the live address:port can connect, and that address is on a public website.

  How the door works:

    The site knows who is in the Discord and what roles they have. The launcher
    sends the profile id it is about to play as when it checks in, so the site
    can tie a Discord account to a profile number. The game server pulls that
    list every five minutes and keeps it in data\allowed.json. Its door reads
    that list and, when enforcing, turns away anybody not on it.

  -Connect also copies the site's join pass key (passKey in the site's
  config.json, which the site makes itself) into door.json, so the gamemode
  can check the join pass a launcher hands the game (#937). The key is read and
  written on the VPS and never crosses this machine or its screen.

  The safe order is -Connect, then leave it watching for a day, then read the
  log, then -Enforce. Turning it on before the list has filled up would turn
  away people who have simply not pressed Play since the launcher started
  sending their profile id.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '',
  [string]$User = 'Administrator',
  [string]$Site = 'https://thornswood.net',
  [string]$DocsRoot = 'C:/Thornswood-Docs',
  # Which server. Empty finds the live one itself. Give it
  # C:\Thornswood-Server-Dev to point at the dev instance, which is the
  # only way to refresh the dev door after the site key is rotated.
  [string]$Root,
  [switch]$Connect,
  [switch]$Enforce,
  [switch]$Watch,
  [int]$Log = 0,
  [switch]$NoPause
)


$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=yes')
$docsWin = $DocsRoot.Replace('/','\')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

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

if ($Enforce -and $Watch) { Die 'Pick one of -Enforce or -Watch, not both.' }

Write-Host ''
Write-Host '  THORNSWOOD  -  the door on the game server' -ForegroundColor White

Head 'Finding the server'
if ($Root) {
  $root = $Root.TrimEnd('\', '/')
} else {
  $found = Remote @"
`$ErrorActionPreference = 'Continue'
foreach (`$d in (Get-ChildItem 'C:\' -Directory -EA SilentlyContinue)) {
  if (Test-Path (Join-Path `$d.FullName 'server-settings.json')) { 'ROOT ' + `$d.FullName }
}
"@
  $root = (@($found) | Where-Object { $_ -match '^ROOT ' } | Select-Object -First 1) -replace '^ROOT ', ''
  $root = "$root".Trim()
}
if (-not $root) { Die 'No server-settings.json anywhere on C: of the VPS.' }
Say "  $root"
# The dev server's door asks the dev list, /dev/api/allowed, which is only the
# people the dev build is for (docs\SYSTEM.md, "The door"). Without -Site this
# wrote the live address into the dev door and it fetched the live list (#964).
if ($root -match '-Dev$' -and -not $PSBoundParameters.ContainsKey('Site')) {
  $Site = $Site.TrimEnd('/') + '/dev'
}

# ------------------------------------------------------------- connecting ---
if ($Connect) {
  Head 'Pointing the door at the site'
  # The key is already on the VPS in the site's own config. Reading it there
  # rather than asking for it keeps it off the command line and out of your
  # PowerShell history, and means there is only one copy to rotate.
  $out = Remote @"
`$ErrorActionPreference = 'Continue'
`$root = '$root'
`$privDir = 'private'
try {
  `$s = Get-Content (Join-Path `$root 'server-settings.json') -Raw | ConvertFrom-Json
  if (`$s.privDir) { `$privDir = [string]`$s.privDir }
} catch { }
`$priv = Join-Path `$root `$privDir

`$key = ''
`$pass = ''
try {
  `$c = Get-Content '$docsWin\config.json' -Raw | ConvertFrom-Json
  `$key = [string]`$c.botKey
  `$pass = [string]`$c.passKey
} catch { }
if (-not `$key) { 'NO BOT KEY in $docsWin\config.json. Run Install-Bot.ps1 first.'; exit }

`$doc = @{ site = '$Site'; key = `$key }
if (`$pass) { `$doc.passKey = `$pass }
`$doc = `$doc | ConvertTo-Json
if (-not (Test-Path `$priv)) { New-Item -ItemType Directory -Path `$priv -Force | Out-Null }
[IO.File]::WriteAllText((Join-Path `$priv 'door.json'), `$doc, (New-Object Text.UTF8Encoding(`$false)))
'door.json written, pointing at $Site'
if (`$pass) { 'with the join pass key, so this server can check join passes' }
else { 'WITHOUT a join pass key: the site has not made one yet. Deploy-Docs.ps1, then -Connect again.' }
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
`$privDir = 'private'
try {
  `$s = Get-Content (Join-Path `$root 'server-settings.json') -Raw | ConvertFrom-Json
  if (`$s.privDir) { `$privDir = [string]`$s.privDir }
} catch { }
`$f = Join-Path (Join-Path `$root `$privDir) 'allowed.json'
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
`$privDir = 'private'
try {
  `$s = Get-Content (Join-Path `$root 'server-settings.json') -Raw | ConvertFrom-Json
  if (`$s.privDir) { `$privDir = [string]`$s.privDir }
} catch { }
`$priv = Join-Path `$root `$privDir

`$f = Join-Path `$priv 'allowed.json'
if (-not (Test-Path `$f)) {
  'NO allowed.json. The door is OFF and anybody can connect.'
} else {
  `$d = Get-Content `$f -Raw | ConvertFrom-Json
  'mode      ' + `$(if (`$d.enforce) { 'ENFORCING, people not on the list are turned away' } else { 'watching only, nobody is turned away' })
  'profiles  ' + @(`$d.profiles).Count
  'updated   ' + `$(if (`$d.at) { `$d.at } else { 'never, this list was written by hand' })
  foreach (`$p in @(`$d.people)) { '  ' + `$p.name + '  ' + (@(`$p.profiles) -join ', ') }
}
`$j = Join-Path `$priv 'door.json'
'refreshing ' + `$(if (Test-Path `$j) { 'yes, from the site' } else { 'NO. Run -Connect, or the list never updates.' })
`$pk = `$false
try { `$pk = [bool]([string](Get-Content `$j -Raw | ConvertFrom-Json).passKey) } catch { }
'join pass key ' + `$(if (`$pk) { 'yes' } else { 'NO. Run -Connect once the site has made one (#937).' })
"@
$out | ForEach-Object { Say "  $_" }

if ($Log -gt 0) {
  Head "The last $Log lines the door wrote"
  Remote @"
`$ErrorActionPreference = 'Continue'
`$root = '$root'
`$privDir = 'private'
try {
  `$s = Get-Content (Join-Path `$root 'server-settings.json') -Raw | ConvertFrom-Json
  if (`$s.privDir) { `$privDir = [string]`$s.privDir }
} catch { }
`$l = Join-Path (Join-Path `$root `$privDir) 'door.log'
if (Test-Path `$l) { Get-Content `$l -Tail $Log } else { 'nothing logged yet' }
"@ | ForEach-Object { Say "  $_" }
}

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
