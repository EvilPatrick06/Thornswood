<#
  Install-Bot.ps1

  Puts the Thornswood bot on the VPS and keeps it running. This is the one that
  stays up, unlike Setup-Discord.ps1 which builds the server once and exits.

      .\Install-Bot.ps1

  What it does:

    1. Checks Python is on the VPS, and says how to get it if not.
    2. Copies bot.py, card.py and the card artwork up.
    3. Installs discord.py and Pillow there.
    4. Asks for the bot token at a prompt, never on a command line.
    5. Makes a shared key, gives it to both the bot and the site, so the site
       knows a ticket really came from the bot.
    6. Registers a scheduled task that starts it at boot and restarts it if it
       falls over, then starts it now.

  Run it again any time to push a change. It stops the old one first.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Root = 'C:/Thornswood-Bot',
  [string]$DocsRoot = 'C:/Thornswood-Docs',
  [string]$Task = 'Thornswood Bot',
  # The channel the ticket panel lives in. More than one name is allowed and
  # the first that exists wins, so renaming the channel in Discord stops being
  # able to take tickets down with it.
  [string]$TicketChannel = 'tickets-and-applications,applications',
  # Staff only, and a different channel: posting closed applications where
  # people apply puts one person's answers in front of the next, and buries
  # the panel. The bot makes it if it is not there.
  [string]$TicketLog     = 'tickets,ticket-log',
  # Where join cards go. The channel called general was renamed, and the bot
  # said so in its log for a day before anybody read it.
  [string]$JoinChannel   = 'welcome-travelers',
  # Pulled into every ticket thread.
  [string]$StaffRoles    = 'Owner,Gamemaster,Dev,Loremaster,Moderator',
  # Pulled into applications to join them and nothing else. Content Creator is
  # social media rather than staff, so it has no business reading a report
  # about somebody or another person's playtest application.
  [string]$CreatorRoles  = 'Content Creator',
  # Every run used to mint a new shared key, which meant every run also
  # silently stopped tickets reaching the site inbox until Deploy-Docs was run
  # again. The key is kept unless you ask for a new one.
  [switch]$RotateKey,
  [switch]$NoToken,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$rootWin = $Root.Replace('/','\')
$docsWin = $DocsRoot.Replace('/','\')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }
function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  & ssh @ssh "$User@$Vps" "powershell -NoProfile -EncodedCommand $e" 2>&1
}

Write-Host ''
Write-Host '  THORNSWOOD  -  the bot' -ForegroundColor White

# ------------------------------------------------------------- python ---
Head 'Python on the VPS'
$py = Remote @"
# sshd was started before Python was ever installed, so every session it hands
# out carries the PATH from back then. Without this the check says MISSING on a
# box that has had Python on it for weeks, and the whole installer runs again.
`$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
`$p = Get-Command python -EA SilentlyContinue
if (`$p) { 'FOUND ' + (& `$p.Source --version 2>&1) + ' at ' + `$p.Source }
else { 'MISSING' }
"@
$py | ForEach-Object { Say "  $_" }
if ("$py" -match 'MISSING') {
  # Windows Server usually has no winget and no store, so this fetches the
  # official installer and runs it quietly rather than telling you to go and
  # click through a wizard over RDP.
  Say '  not there, installing it' 'Yellow'
  Head 'Installing Python 3.12 on the VPS'
  Remote @"
`$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
`$url = 'https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe'
`$exe = Join-Path `$env:TEMP 'python-3.12.8-amd64.exe'
'downloading ' + `$url
try { Invoke-WebRequest -Uri `$url -OutFile `$exe -UseBasicParsing -TimeoutSec 300 }
catch { 'DOWNLOAD FAILED: ' + `$_.Exception.Message; exit }
'running the installer, quietly, for all users'
`$p = Start-Process `$exe -ArgumentList '/quiet','InstallAllUsers=1','PrependPath=1','Include_pip=1','Include_test=0' -Wait -PassThru
'installer exit code ' + `$p.ExitCode
Remove-Item `$exe -Force -EA SilentlyContinue
# PrependPath only touches the machine PATH, and this session started before
# it did, so read it back rather than trusting `$env:PATH.
`$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
`$c = Get-Command python -EA SilentlyContinue
if (`$c) { 'FOUND ' + (& `$c.Source --version 2>&1) } else { 'STILL MISSING' }
"@ | ForEach-Object { Say "  $_" }

  $py = Remote @"
`$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
`$p = Get-Command python -EA SilentlyContinue
if (`$p) { 'FOUND ' + (& `$p.Source --version 2>&1) } else { 'MISSING' }
"@
  $py | ForEach-Object { Say "  $_" }
  if ("$py" -match 'MISSING') {
    Write-Host ''
    Say 'That did not take. Do it by hand over RDP or ssh:' 'Yellow'
    Say '  https://www.python.org/downloads/windows/' 'DarkGray'
    Say '  Tick Add Python to PATH, then run this again.' 'DarkGray'
    Die 'Nothing was copied.'
  }
}

# --------------------------------------------------------------- files ---
Head 'Copying it up'
$null = Remote "New-Item -ItemType Directory -Force -Path '$rootWin','$rootWin\assets' | Out-Null; 'ready'"
foreach ($f in 'bot.py', 'card.py') {
  $src = Join-Path $Here "discord\$f"
  if (-not (Test-Path $src)) { Die "missing: $src" }
  & scp @ssh $src "${User}@${Vps}:$Root/$f" | Out-Null
  Say "  $f" 'Green'
}
$art = Join-Path $Here 'discord\assets\join-card.png'
if (Test-Path $art) {
  & scp @ssh $art "${User}@${Vps}:$Root/assets/join-card.png" | Out-Null
  Say '  assets\join-card.png' 'Green'
} else {
  Say '  no join-card.png, cards will fall back to a plain background' 'Yellow'
}

# ---------------------------------------------------------------- deps ---
Head 'Its two libraries'
Remote @"
`$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
Set-Location '$rootWin'
# certifi as well as the other two. Windows Server ships with an empty root
# certificate store and Automatic Root Certificates Update switched off by
# policy, so Python cannot verify discord.com and aiohttp fails the handshake
# with "unable to get local issuer certificate". Carrying the roots in a file
# sidesteps the whole thing.
& python -m pip install --quiet --disable-pip-version-check discord.py pillow certifi 2>&1 | Out-Null
if (`$LASTEXITCODE -eq 0) { 'discord.py, pillow and certifi ready' } else { 'PIP FAILED with ' + `$LASTEXITCODE }
`$ca = (& python -c "import certifi; print(certifi.where())" 2>&1 | Select-Object -Last 1)
if (`$ca -and (Test-Path `$ca)) { 'root certificates at ' + `$ca } else { 'COULD NOT FIND certifi, TLS will fail' }
"@ | ForEach-Object { Say "  $_" }

# --------------------------------------------------------------- token ---
$token = ''
if (-not $NoToken) {
  Head 'The bot token'
  Say '  Same one Setup-Discord.ps1 wants. Leave blank to keep what is up there.' 'DarkGray'
  $ss = Read-Host '  Paste it' -AsSecureString
  if ($ss -and $ss.Length -gt 0) {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)).Trim()
  }
}

# A key the site can check, so /api/ticket is not open to whoever finds it.
function NewKey([int]$n) {
  $out = ''
  while ($out.Length -lt $n) {
    $b = New-Object byte[] 48
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    $out += ([Convert]::ToBase64String($b) -replace '[^A-Za-z0-9]','')
  }
  return $out.Substring(0, $n)
}
$botKey = NewKey 32
$KeyMode = if ($RotateKey) { 'new' } else { 'keep' }

$payload = @{ token = $token; key = $botKey } | ConvertTo-Json -Compress
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
$token = $null; $payload = $null

Head 'Settings, and the key the site will check'
$settings = Remote @"
`$ErrorActionPreference = 'Stop'
`$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
`$p = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')) | ConvertFrom-Json

# The bot's own env file. Kept out of the repo and readable by this account only.
`$f = '$rootWin\bot.env.json'
`$env2 = @{}
if (Test-Path `$f) {
  try { (Get-Content `$f -Raw | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { `$env2[`$_.Name] = `$_.Value } } catch { }
}
if (`$p.token) { `$env2['DISCORD_TOKEN'] = `$p.token }
`$env2['THORNSWOOD_SITE'] = 'https://thornswood.net'
`$changed = `$false
if ('$KeyMode' -eq 'new' -or -not `$env2['THORNSWOOD_KEY']) {
  `$env2['THORNSWOOD_KEY'] = `$p.key
  `$changed = `$true
}
`$env2['JOIN_CHANNEL']    = '$JoinChannel'
`$env2['TICKET_CHANNEL']  = '$TicketChannel'
`$env2['TICKET_LOG']      = '$TicketLog'
`$env2['STAFF_ROLES']     = '$StaffRoles'
`$env2['CREATOR_ROLES']   = '$CreatorRoles'
# Piped, Python writes in the machine's ANSI codepage and PowerShell reads the
# pipe as OEM. Anything outside plain ASCII, a role name or a channel name with
# an accent in it, came out of that as a screenful of question marks. Both ends
# are told UTF-8 instead, here and at the top of run.ps1.
`$env2['PYTHONIOENCODING'] = 'utf-8'

# Where Python looks for root certificates. ssl.set_default_verify_paths reads
# this, and load_default_certs calls it on every platform, so pointing it at
# certifi's bundle fixes the handshake without touching the Windows store.
try {
  `$ca = (& python -c "import certifi; print(certifi.where())" 2>&1 | Select-Object -Last 1)
  if (`$ca -and (Test-Path `$ca)) {
    `$env2['SSL_CERT_FILE']      = `$ca
    `$env2['REQUESTS_CA_BUNDLE'] = `$ca
  }
} catch { }
[IO.File]::WriteAllText(`$f, (`$env2 | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding(`$false)))
# Locked down, but not so far that the thing meant to read it cannot. The
# scheduled task runs as SYSTEM, so SYSTEM has to stay on the file. Taking it
# off is how the bot ended up starting with no token and exiting immediately.
try {
  `$acl = Get-Acl `$f
  `$acl.SetAccessRuleProtection(`$true, `$false)
  foreach (`$r in @(`$acl.Access)) { [void]`$acl.RemoveAccessRule(`$r) }
  foreach (`$sid in @('S-1-5-18', 'S-1-5-32-544')) {   # SYSTEM, Administrators
    `$who = (New-Object Security.Principal.SecurityIdentifier(`$sid)).Translate([Security.Principal.NTAccount])
    `$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
      `$who, 'FullControl', 'Allow')))
  }
  `$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
    [Security.Principal.WindowsIdentity]::GetCurrent().Name, 'FullControl', 'Allow')))
  Set-Acl `$f `$acl
} catch { 'could not tighten bot.env.json: ' + `$_.Exception.Message }
if (`$env2['DISCORD_TOKEN']) { 'token held' } else { 'NO TOKEN, the bot will not start' }
'panel channel: #' + (`$env2['TICKET_CHANNEL'] -replace ',', ' or #')
'closed tickets: #' + (`$env2['TICKET_LOG'] -replace ',', ' or #') + '  (staff only)'
'join cards:    #' + `$env2['JOIN_CHANNEL']
'staff:         ' + `$env2['STAFF_ROLES']
'creator only:  ' + `$env2['CREATOR_ROLES']

# The same key into the site's config, so it accepts the bot and nobody else.
`$c = '$docsWin\config.json'
`$cfg = @{}
if (Test-Path `$c) {
  try { (Get-Content `$c -Raw | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { `$cfg[`$_.Name] = `$_.Value } } catch { }
}
`$cfg['botKey'] = `$env2['THORNSWOOD_KEY']
[IO.File]::WriteAllText(`$c, (`$cfg | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding(`$false)))
if (`$changed) { 'site told about a NEW key, so the site needs restarting' }
else { 'key unchanged, the site does not need restarting' }
"@
$settings | ForEach-Object { Say "  $_" }

# -------------------------------------------------------------- runner ---
Head 'Keeping it running'
Remote @"
`$ErrorActionPreference = 'Stop'

# A wrapper, because the scheduled task cannot set environment variables and
# the bot wants six of them. It also restarts the bot if it exits, which is
# what a rate limit or a dropped websocket looks like from out here.
`$run = @'
`$ErrorActionPreference = 'Continue'
Set-Location '$rootWin'

[Console]::OutputEncoding = [Text.Encoding]::UTF8
`$OutputEncoding = [Text.Encoding]::UTF8

# Say so in the log rather than starting the bot with nothing and letting it
# exit with a message that looks like the token was never set.
`$envFile = '$rootWin\bot.env.json'
try {
  `$e = Get-Content `$envFile -Raw -ErrorAction Stop | ConvertFrom-Json
} catch {
  ('[run] cannot read ' + `$envFile + ': ' + `$_.Exception.Message) | Out-File '$rootWin\bot.log' -Append -Encoding utf8
  ('[run] running as ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name) | Out-File '$rootWin\bot.log' -Append -Encoding utf8
  exit 1
}
foreach (`$p in `$e.PSObject.Properties) { [Environment]::SetEnvironmentVariable(`$p.Name, `$p.Value, 'Process') }
if (-not `$env:DISCORD_TOKEN) {
  '[run] bot.env.json has no DISCORD_TOKEN in it' | Out-File '$rootWin\bot.log' -Append -Encoding utf8
  exit 1
}

# PATH came from before Python was installed on a fresh box.
`$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')

if (-not `$env:PYTHONIOENCODING) { `$env:PYTHONIOENCODING = 'utf-8' }

while (`$true) {
  # Python writes the log itself, through cmd's redirection, the same way the
  # game server and the voice server are run. Piping every line through
  # PowerShell and Out-File, which this did until 2026-09-16, re-encoded the
  # text and left the file unreadable past a point, and a slow pipeline could
  # hold the bot's own print() calls, which run on its event loop.
  & cmd /c "python ""$rootWin\bot.py"" >> ""$rootWin\bot.log"" 2>&1"
  Start-Sleep -Seconds 15
}
'@
[IO.File]::WriteAllText('$rootWin\run.ps1', `$run, (New-Object Text.UTF8Encoding(`$false)))

Get-CimInstance Win32_Process |
  Where-Object { `$_.Name -eq 'python.exe' -and `$_.CommandLine -like '*Thornswood-Bot*' } |
  ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -EA SilentlyContinue }
Get-CimInstance Win32_Process |
  Where-Object { `$_.Name -eq 'powershell.exe' -and `$_.CommandLine -like '*Thornswood-Bot\run.ps1*' } |
  ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep -Seconds 1

Unregister-ScheduledTask -TaskName '$Task' -Confirm:`$false -EA SilentlyContinue
`$a = New-ScheduledTaskAction -Execute 'powershell.exe' ``
     -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "$rootWin\run.ps1"'
`$t = New-ScheduledTaskTrigger -AtStartup
`$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries ``
     -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) ``
     -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName '$Task' -Action `$a -Trigger `$t -Settings `$s ``
  -User 'SYSTEM' -RunLevel Highest | Out-Null
# Remember how long the log is, and read back only what is written past that.
# Waiting for the words 'watching 1 server' to appear is no good on its own:
# every previous start left that line behind, so the wait was satisfied by a
# run from hours ago and this printed that run instead of the one it had just
# begun. Writing a marker line instead did not work either, because the bot
# holds bot.log open the whole time it runs and Add-Content is refused. A byte
# count needs nothing but a look at the file.
`$log = '$rootWin\bot.log'
`$before = 0
if (Test-Path `$log) { `$before = (Get-Item `$log).Length }

Start-ScheduledTask -TaskName '$Task'
Start-Sleep -Seconds 5

`$p = Get-CimInstance Win32_Process |
      Where-Object { `$_.Name -eq 'python.exe' -and `$_.CommandLine -like '*Thornswood-Bot*' }
if (`$p) { 'bot up, pid ' + `$p.ProcessId } else { 'BOT DID NOT START' }

# Opened with FileShare ReadWrite, because the bot has it open for writing and
# anything less strict than that is denied while it does.
function Fresh {
  `$out = @()
  `$fs = `$null
  try {
    `$fs = New-Object IO.FileStream(`$log, 'Open', 'Read', 'ReadWrite')
    if (`$fs.Length -gt `$before) {
      [void]`$fs.Seek(`$before, 'Begin')
      `$sr = New-Object IO.StreamReader(`$fs, [Text.Encoding]::UTF8)
      `$out = @((`$sr.ReadToEnd()) -split "\r?\n")
      `$sr.Close()
    }
  } catch { }
  if (`$fs) { `$fs.Dispose() }
  return `$out
}

# Python is up in about a second. Connecting to Discord, reading the roles and
# checking the channels takes longer, and the old eight second sleep was over
# well before any of it had happened.
`$ready = `$false
foreach (`$i in 1..30) {
  Start-Sleep -Seconds 2
  if (@(Fresh) -match 'watching \d+ server') { `$ready = `$true; break }
}
if (-not `$ready) {
  'it has not finished starting yet, so what follows may be short'
}
'--- what the bot said this time ---'
`$said = @(Fresh) | Where-Object { `$_ -match '^\s*\[(thornswood-bot|run)\]' }
if (`$said) { `$said | Select-Object -Last 25 } else { 'nothing yet' }
"@ | ForEach-Object { Say "  $_" }

Write-Host ''
if ("$settings" -match 'NEW key') {
  Say 'The site is still running with the old key, so tickets will not reach' 'Yellow'
  Say 'its inbox until it restarts:' 'Yellow'
  Say '    .\tools\Deploy-Docs.ps1' 'Green'
} else {
  Say 'The key did not change, so the site needs nothing.' 'DarkGray'
}
Write-Host ''
Say 'Then check the panel channel above, and try joining with another account.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
