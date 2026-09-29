<#
  Install-Bot.ps1

  Puts the Thornswood bot on the VPS and keeps it running. This is the one that
  stays up, unlike Setup-Discord.ps1 which builds the server once and exits.

      .\Install-Bot.ps1               all of it, asks for the token
      .\Install-Bot.ps1 -CodeOnly    just the code, then restart
      .\Install-Bot.ps1 -NoToken     everything except asking for it

  What it does:

    1. Checks Python is on the VPS, and says how to get it if not.
    2. Copies bot.py, card.py and the card artwork up.
    3. Installs discord.py and Pillow there.
    4. Asks for the bot token at a prompt, never on a command line, and puts
       it in the bot's bot.env.json and the site's config.json together
       (scripts\vps\Write-BotToken.ps1, the one writer of it).
    5. Makes a shared key, gives it to both the bot and the site, so the site
       knows a ticket really came from the bot. The site is restarted when the
       key or the token changed, since it reads its config only on starting.
    6. Registers a scheduled task that starts it at boot and restarts it if it
       falls over, then starts it now.

  Run it again any time to push a change. It stops the old one first.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '',
  [string]$User = 'Administrator',
  [string]$Root = 'C:/Thornswood-Bot',
  [string]$DocsRoot = 'C:/Thornswood-Docs',
  [string]$Task = 'Thornswood Bot',
  # The site's task, restarted when the key or the token it reads changed.
  [string]$SiteTask = 'Thornswood Docs',
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
  # Just the code. Sends bot.py, card.py and the artwork, restarts, and
  # leaves Python, the libraries, the token and the scheduled task alone.
  # This is what a change to bot.py wants, and it never asks for anything,
  # so it runs unattended.
  [switch]$CodeOnly,
  [switch]$NoToken,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=accept-new')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\vps\Send-Secret.ps1')
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
# The bot sources live at the repo root, in bot\. This script sits two levels
# down, in scripts\deploy, since #440 sorted the scripts into scripts\<area> on
# 25 September, so the repo root is two up from here. The copy loop below kept
# the old one-level ..\bot from before the move, which pointed at scripts\bot
# and found nothing on a -CodeOnly deploy. Anchoring the repo root once and
# joining bot\ to it keeps every bot path right whatever this folder's depth is,
# and test-script-paths.ps1 follows a $Repo path from the root the same way.
$Repo = Split-Path -Parent (Split-Path -Parent $Here)
$rootWin = $Root.Replace('/','\')
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
# dev-channel.txt goes up with the code, and it is not an afterthought.
#
# The site watcher reads the staff channel's id out of it, beside bot.py. It
# was not in this list on 21 September, so the first run of the watcher on the
# VPS said "in channel 0" and would have found the site down and had nowhere to
# say so. The id is not a secret and the file is tracked in git, unlike the two
# webhook files sitting next to it, which are not sent by anything and must not
# be added here.
#
# requirements.txt too, because the full run installs the libraries from it.
foreach ($f in 'bot.py', 'card.py', 'dev-channel.txt', 'requirements.txt') {
  $src = Join-Path $Repo "bot\$f"
  if (-not (Test-Path $src)) { Die "missing: $src" }
  & scp @ssh $src "${User}@${Vps}:$Root/$f" | Out-Null
  Say "  $f" 'Green'
}
# The roller run.ps1 calls before each start of the bot. See Roll-Log.ps1 for
# why a log cmd holds open can only be rolled then.
$roll = Join-Path $Here '..\vps\Roll-Log.ps1'
if (-not (Test-Path $roll)) { Die "missing: $roll" }
& scp @ssh $roll "${User}@${Vps}:$Root/roll-log.ps1" | Out-Null
Say '  roll-log.ps1' 'Green'

# staff-channel.txt the same way, when there is one. It holds the id of the
# channel a session that went wrong is announced in. Unlike the file above it
# is optional: with no id the bot falls back to the name staff-general, and
# only when exactly one channel carries that name, so a missing file leaves a
# working bot rather than a silent one. Put an id in it the moment two
# channels ever share that name, which has already happened here with news.
$staff = Join-Path $Repo 'bot\staff-channel.txt'
if (Test-Path $staff) {
  & scp @ssh $staff "${User}@${Vps}:$Root/staff-channel.txt" | Out-Null
  Say '  staff-channel.txt' 'Green'
} else {
  Say '  no staff-channel.txt, so the bot resolves staff-general by name' 'DarkGray'
}
$art = Join-Path $Repo 'bot\assets\join-card.png'
if (Test-Path $art) {
  & scp @ssh $art "${User}@${Vps}:$Root/assets/join-card.png" | Out-Null
  Say '  assets\join-card.png' 'Green'
} else {
  Say '  no join-card.png, cards will fall back to a plain background' 'Yellow'
}

# ----------------------------------------------------------- code only ---
# A change to bot.py and nothing else, which is most of them.
#
# The full run checks Python, reinstalls three libraries over the network,
# rewrites bot.env.json and re-registers the scheduled task, and none of that
# has anything to do with the code having changed. This sends the files and
# restarts, which is the whole job, and it never asks for the token, so it
# runs unattended.
if ($CodeOnly) {
    Head 'Restarting it'
    Remote @"
`$ErrorActionPreference = 'Continue'
`$log = '$rootWin\bot.log'
`$before = 0
if (Test-Path `$log) { `$before = (Get-Item `$log).Length }

# By command line rather than by task, because a bot started by hand once is
# still a bot holding the token and answering tickets.
Get-CimInstance Win32_Process |
  Where-Object { `$_.Name -like 'python*' -and `$_.CommandLine -like '*Thornswood-Bot*' } |
  ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -EA SilentlyContinue; 'stopped pid ' + `$_.ProcessId }
Start-Sleep -Seconds 2
Stop-ScheduledTask -TaskName '$Task' -EA SilentlyContinue
Start-ScheduledTask -TaskName '$Task' -EA SilentlyContinue
Start-Sleep -Seconds 12

`$p = Get-CimInstance Win32_Process |
      Where-Object { `$_.Name -like 'python*' -and `$_.CommandLine -like '*Thornswood-Bot*' }
if (`$p) { 'bot up, pid ' + (`$p | Select-Object -First 1).ProcessId } else { 'BOT DID NOT START' }

# Only what this start wrote. The file is held open by the bot, so it is read
# with FileShare ReadWrite or not at all. Shorter than before means run.ps1
# rolled it on the way up, so all of it is this start.
`$fs = `$null
try {
  `$fs = New-Object IO.FileStream(`$log, 'Open', 'Read', 'ReadWrite')
  `$from = `$before
  if (`$fs.Length -lt `$from) { `$from = 0 }
  if (`$fs.Length -gt `$from) {
    [void]`$fs.Seek(`$from, 'Begin')
    `$sr = New-Object IO.StreamReader(`$fs, [Text.Encoding]::UTF8)
    (`$sr.ReadToEnd()) -split "\r?\n" | Where-Object { `$_ } | Select-Object -Last 12
    `$sr.Close()
  } else { 'nothing new in the log yet' }
} catch { 'could not read the log: ' + `$_.Exception.Message } finally { if (`$fs) { `$fs.Dispose() } }
"@ | ForEach-Object { Say "  $_" }

    Write-Host ''
    Say '  Code only. Python, the libraries, the token and the task were left alone.' 'DarkGray'
    Say '  The ticket panel updates itself on startup, so a changed panel is already up.' 'DarkGray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
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
#
# At the exact versions in requirements.txt, which went up with the code. By
# name alone this took whatever PyPI had newest on the day, so the next fresh
# box would have taken the next major of any of the three, untried. The
# build check installs the same file before it runs the bot harnesses, so the
# versions tested are the versions run. Bump them there, on purpose.
& python -m pip install --quiet --disable-pip-version-check -r '$rootWin\requirements.txt' 2>&1 | Out-Null
if (`$LASTEXITCODE -eq 0) { 'discord.py, pillow and certifi ready, at the versions in requirements.txt' } else { 'PIP FAILED with ' + `$LASTEXITCODE }
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

# The token and the key go on ssh's standard input, never in the script or on
# a command line on either machine (Send-Secret.ps1, issue #451).
$payload = @{ token = $token; key = $botKey } | ConvertTo-Json -Compress
$token = $null

# The one writer of the token, which puts it in bot.env.json and the site's
# config.json together or in neither (issue #466). It goes up in front of the
# settings script, so both run in the same session on the VPS.
$writer = Join-Path $Here '..\vps\Write-BotToken.ps1'
if (-not (Test-Path -LiteralPath $writer)) { Die "missing: $writer" }

Head 'Settings, and the key the site will check'
$settings = Invoke-ThornswoodSecretRemote -Target "$User@$Vps" -SshArgs $ssh -Secret $payload -Script ((Get-Content -LiteralPath $writer -Raw) + "`n" + @"
`$ErrorActionPreference = 'Stop'
`$env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
`$p = `$null
try { `$p = `$ThornswoodSecret | ConvertFrom-Json } catch { }
`$ThornswoodSecret = `$null
if (-not `$p) { 'NOTHING ARRIVED on standard input. Nothing written.'; return }

# The bot's own env file. Kept out of the repo and readable by this account only.
`$f = '$rootWin\bot.env.json'
`$env2 = @{}
if (Test-Path `$f) {
  try { (Get-Content `$f -Raw | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { `$env2[`$_.Name] = `$_.Value } } catch { }
}
# The token is not written here. Write-ThornswoodBotToken writes it below,
# into this file and the site's config.json together, once both exist.
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
'panel channel: #' + (`$env2['TICKET_CHANNEL'] -replace ',', ' or #')
'closed tickets: #' + (`$env2['TICKET_LOG'] -replace ',', ' or #') + '  (staff only)'
'join cards:    #' + `$env2['JOIN_CHANNEL']
'staff:         ' + `$env2['STAFF_ROLES']
'creator only:  ' + `$env2['CREATOR_ROLES']

# The same key into the site's config, so it accepts the bot and nobody else.
# Never over a config.json that is there and does not parse: it is not empty,
# it is unreadable, and writing a fresh one over it is how the whole Discord
# setup, client secret and token included, went once already.
`$c = '$docsWin\config.json'
`$cfg = @{}
`$cfgOk = `$true
if (Test-Path `$c) {
  try { (Get-Content `$c -Raw | ConvertFrom-Json).PSObject.Properties |
        ForEach-Object { `$cfg[`$_.Name] = `$_.Value } } catch { `$cfgOk = `$false }
}
if (`$cfgOk) {
  `$cfg['botKey'] = `$env2['THORNSWOOD_KEY']
  [IO.File]::WriteAllText(`$c, (`$cfg | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding(`$false)))
} else {
  `$changed = `$false
  'SITE CONFIG DOES NOT PARSE: ' + `$c + ' was left as it is, and neither the key nor the token went into it'
}

# The token, into both files or neither. Blank at the prompt keeps what is there.
`$tokenChanged = `$false
if (`$p.token) {
  `$r = Write-ThornswoodBotToken -Token `$p.token -BotEnv `$f -SiteConfig `$c
  `$r.Lines
  `$tokenChanged = [bool]`$r.Changed
}
Get-ThornswoodBotTokenState -BotEnv `$f -SiteConfig `$c

# The site reads config.json once, when it starts, so a new key or token means
# nothing to it until it restarts.
if (`$changed -or `$tokenChanged) {
  if (`$changed) { 'site told about a NEW key' }
  Restart-ThornswoodSite -Root '$docsWin' -Task '$SiteTask'
} else { 'key and token unchanged, the site does not need restarting' }
"@)
$payload = $null; $botKey = $null
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

# Three quick exits in a row and it stops trying.
#
# This loop used to start the bot again fifteen seconds after every exit, for
# ever. That is right for a dropped connection. It is wrong for a rejected
# token, Server Members Intent switched off, or a bot.py that fails on import:
# each of those is in bot.log within seconds and the process exits, and the
# loop tried again about four times a minute, the same way every time, until
# somebody happened to open bot.log. A run that lasts
# thirty seconds got far enough to be worth another go, so a long run starts
# the count again, and only three short ones in a row give up.
#
# It exits 0 when it gives up. The task has RestartCount 999, and whether Task
# Scheduler repeats a task that exits non-zero has not been measured on this
# box; a clean exit is not a failure either way. What starts it again is the
# watchdog, Watch-Services.ps1, which tries at most three times an hour and
# then writes that the bot needs a look. That rule is entry 99 and stays as it
# is. Install-Bot.ps1 starts the task again too, which is how a fix goes up.
`$fastSeconds = 30
`$fastRuns = 0
while (`$true) {
  # Rolled here, between runs, because this is the one moment nothing holds
  # bot.log: cmd opens it for the >> below and keeps it until python exits.
  # At 4 MB, five kept, and it never stops the bot starting. Roll-Log.ps1.
  try { & '$rootWin\roll-log.ps1' -Path '$rootWin\bot.log' | Out-Null } catch { }
  # Python writes the log itself, through cmd's redirection, the same way the
  # game server and the voice server are run. Piping every line through
  # PowerShell and Out-File, which this did until 2026-09-16, re-encoded the
  # text and left the file unreadable past a point, and a slow pipeline could
  # hold the bot's own print() calls, which run on its event loop.
  `$clock = [Diagnostics.Stopwatch]::StartNew()
  & cmd /c "python ""$rootWin\bot.py"" >> ""$rootWin\bot.log"" 2>&1"
  `$code = `$LASTEXITCODE
  if (`$clock.Elapsed.TotalSeconds -lt `$fastSeconds) { `$fastRuns++ } else { `$fastRuns = 0 }
  if (`$fastRuns -ge 3) {
    # Python has exited, so bot.log is free to append to.
    ('[run] the bot stopped within ' + `$fastSeconds + ' seconds three times running, the last time with exit code ' + `$code + '. Not starting it again. The reason is in the lines above.') | Out-File '$rootWin\bot.log' -Append -Encoding utf8
    exit 0
  }
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
# anything less strict than that is denied while it does. Shorter than before
# means run.ps1 rolled it on the way up, so all of it is this start.
function Fresh {
  `$out = @()
  `$fs = `$null
  try {
    `$fs = New-Object IO.FileStream(`$log, 'Open', 'Read', 'ReadWrite')
    `$from = `$before
    if (`$fs.Length -lt `$from) { `$from = 0 }
    if (`$fs.Length -gt `$from) {
      [void]`$fs.Seek(`$from, 'Begin')
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
if ("$settings" -match 'SITE DID NOT COME BACK|SITE CONFIG DOES NOT PARSE') {
  Say 'The site is not running with the new key or token, so tickets and role' 'Yellow'
  Say 'lookups fail until it is. Start it again with:' 'Yellow'
  Say '    .\scripts\deploy\Deploy-Docs.ps1' 'Green'
} elseif ("$settings" -match 'site restarted') {
  Say 'The site was restarted, so it has the key and the token the bot has.' 'DarkGray'
} else {
  Say 'The key and the token did not change, so the site needs nothing.' 'DarkGray'
}
if ("$settings" -match 'NEW key') {
  Say 'A NEW key: the doors need it too, or both are refused on their next fetch:' 'Yellow'
  Say '    .\scripts\ops\Set-Door.ps1 -Connect' 'Green'
  Say '    .\scripts\ops\Set-Door.ps1 -Connect -Root C:\Thornswood-Server-Dev -Site https://thornswood.net/dev' 'Green'
}
Write-Host ''
Say 'Then check the panel channel above, and try joining with another account.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
