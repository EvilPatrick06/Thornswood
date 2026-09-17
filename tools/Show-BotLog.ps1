<#
  Show-BotLog.ps1

  What the bot has been saying, without redeploying it to find out.

      .\Show-BotLog.ps1            the bot's own lines, last 40
      .\Show-BotLog.ps1 -All       discord.py's websocket noise as well
      .\Show-BotLog.ps1 -Lines 200 further back

  The log on the VPS holds two things mixed together: what the bot itself
  prints, which is the part written for a person to read, and discord.py's
  own logging, which is a wall of "Can't keep up, shard ID None". The second
  one drowns the first, which is exactly how a bot that was telling you what
  was wrong went unread for a week. So the bot's lines are what this shows
  unless you ask for the rest.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Root = 'C:/Thornswood-Bot',
  [int]$Lines = 40,
  [switch]$All,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')
$rootWin = $Root.Replace('/','\')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

Write-Host ''
Write-Host '  THORNSWOOD  -  the bot log' -ForegroundColor White

$filter = if ($All) { '.' } else { '^\s*\[(thornswood-bot|run)\]' }

$script = @"
`$ErrorActionPreference = 'Continue'
`$log = '$rootWin\bot.log'
if (-not (Test-Path `$log)) { 'there is no bot.log on the VPS yet'; exit }

`$p = Get-CimInstance Win32_Process |
     Where-Object { `$_.Name -eq 'python.exe' -and `$_.CommandLine -like '*Thornswood-Bot*' }
if (`$p) { '[state] bot is running, pid ' + `$p.ProcessId }
else     { '[state] the bot is NOT running' }
`$f = Get-Item `$log
'[state] log last written ' + `$f.LastWriteTime + ', ' + [int](`$f.Length / 1KB) + ' KB'
''

# Read as UTF-8 rather than whatever the console codepage happens to be, or
# every accented character in here comes back as a question mark.
Get-Content `$log -Encoding UTF8 -Tail 3000 -EA SilentlyContinue |
  Where-Object { `$_ -match '$filter' } |
  Select-Object -Last $Lines
"@

$e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
$out = & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" 2>&1

Head 'The VPS'
foreach ($line in $out) {
  $t = "$line"
  $c = 'Gray'
  if     ($t -match 'NOT running|BOT DID NOT START|no bot.log') { $c = 'Red' }
  elseif ($t -match 'will NOT get a private thread|no role matched|does not have|there is no text channel|is not set') { $c = 'Yellow' }
  elseif ($t -match 'look fine|up as|watching \d+ server|join cards will go') { $c = 'Green' }
  Say "  $t" $c
}

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
