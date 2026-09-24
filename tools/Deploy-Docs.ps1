<#
  Deploy-Docs.ps1

  Puts the Thornswood docs site on the VPS and keeps it running.

  The site is a small node server holding six markdown documents and whatever
  is in its files folder. Patrick and the testers edit the documents in the
  browser, Claude edits the same files over ssh, and the installer is published
  into it by Publish-Installer.ps1.

  Run once to install, and again whenever the site itself changes. The
  documents are NOT overwritten by a redeploy: only the app is. Anything typed
  into the site survives.

    .\Deploy-Docs.ps1          the app only, documents untouched
    .\Deploy-Docs.ps1 -Site    also the public pages, which nobody edits in
                               the browser, so this is safe
    .\Deploy-Docs.ps1 -Boards  also board.json, which DOES overwrite anything
                               typed into a board on the site
    .\Deploy-Docs.ps1 -SeedDocs
                               flattens every document with the repo copy.
                               First install only. Takes a .bak of each first.
    .\Deploy-Docs.ps1 -Docs help,known
                               replaces just the named documents with the
                               repo copy, .bak first. For a page rewritten
                               here on purpose, when -SeedDocs is too much.

  The password crosses the wire in clear, because this is plain HTTP on an IP.
  Do not reuse one that matters. That improves the day a real domain and a
  certificate go on it.
#>
[CmdletBinding()]
param(
  [string]$Vps      = '192.135.112.23',
  [string]$User     = 'Administrator',
  [string]$Root     = 'C:/Thornswood-Docs',
  [string]$Task     = 'Thornswood Docs',
  [int]$Port        = 3001,
  [string]$Password,
  # Flattens EVERY document on the VPS with the repo copy, including the ones
  # people have been typing into on the site. It is for a first install and for
  # nothing else. It now takes a backup and says what it stood on.
  [switch]$SeedDocs,
  # Just the boards. -SeedDocs would also flatten every markdown document up
  # there, which is too big a hammer when only the runbook moved.
  [switch]$Boards,
  # Just the public pages under data\site. Those are not editable in the
  # browser, so pushing them overwrites nobody's work. This is what you want
  # nine times out of ten when the wording on the public site changed.
  [switch]$Site,
  # Named documents under data, by name with or without .md: help, known.
  # Only those are replaced, each after a .bak of the live copy, so a page
  # rewritten in the repo can go up without -SeedDocs flattening the rest.
  [string[]]$Docs
)

$ErrorActionPreference = 'Stop'
$ssh  = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$App  = Join-Path $Here 'docs-app'

if (-not (Test-Path -LiteralPath $App)) { throw "not found: $App" }

# -Docs names have to be documents this repo actually has, or a typo would
# quietly send nothing and report nothing.
$docNames = @()
foreach ($d in @($Docs)) {
  if (-not $d) { continue }
  $n = if ($d -match '[.](md|json)$') { $d } else { "$d.md" }
  if (-not (Test-Path -LiteralPath (Join-Path $App "data/$n"))) { throw "no such document in the repo: data/$n" }
  $docNames += $n
}

# Runs a command up there and hands back what it said.
#
# 2>&1 means anything ssh writes to stderr comes back in the same stream as the
# output, as an ErrorRecord rather than a string. Callers that only print are
# fine with that. Callers that treat the result as text are not: OpenSSH now
# warns about post-quantum key exchange on every connection, that warning
# arrived among the filenames, and $_.Trim() stopped the deploy with "does not
# contain a method named 'Trim'" after the files had already gone up. The two
# places that build a list from this take only the strings.
function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  $cmd = "powershell -NoProfile -EncodedCommand $e"

  # A long script does not fit on a command line, and nothing says so.
  #
  # sshd on Windows hands the command to cmd.exe, which stops at 8,191
  # characters. Base64 of UTF-16 is about 2.7 times the script, so the block
  # that opens the port and registers the scheduled task came to 9,610 and
  # arrived cut in half. PowerShell then said "Missing closing '}' in statement
  # block" about a script nobody could see, every single deploy, and the site
  # came up anyway because it was already running. Measured on 17 Sep.
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
    # And bare, with no quotes round it. sshd hands this line to cmd.exe,
    # which passes single quotes on to Windows PowerShell as part of the
    # path, and -File refuses it: "The given path's format is not supported".
    # Measured 24 September. The path above is ours and has no spaces.
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}

function Push($local, $remote) {
  & scp @ssh $local "$User@${Vps}:$remote"
  if ($LASTEXITCODE -ne 0) { throw "scp failed: $local" }
}

Write-Host 'Making room...'
$rootWin = $Root.Replace('/','\')
Remote @"
foreach (`$d in @('$rootWin','$rootWin\public','$rootWin\data','$rootWin\files','$rootWin\uploads')) {
  if (-not (Test-Path `$d)) { New-Item -ItemType Directory -Path `$d -Force | Out-Null }
}
'ready'
"@ | ForEach-Object { "  $_" }

Write-Host ''
Write-Host 'Sending the site...'
Push (Join-Path $App 'server.js') "$Root/server.js"
Write-Host '  server.js'
# Everything in public\, by listing the folder rather than by a list kept here.
# robots.txt was added and did not go up, because this was six named files and
# a seventh is invisible to it.
$sentPublic = @()
Get-ChildItem (Join-Path $App 'public') -File -EA SilentlyContinue | ForEach-Object {
  Push $_.FullName "$Root/public/$($_.Name)"
  $sentPublic += $_.Name
}
Write-Host ('  ' + ($sentPublic -join ', '))

# The public pages are markdown like everything else, so they can be edited
# from the site rather than redeployed. Same rule: only the missing ones go.
Remote "if (-not (Test-Path '$rootWin\data\site')) { New-Item -ItemType Directory -Path '$rootWin\data\site' -Force | Out-Null }" | Out-Null
$siteThere = @((Remote "Get-ChildItem '$rootWin\data\site' -File -EA SilentlyContinue | ForEach-Object Name") |
               Where-Object { $_ -is [string] } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
Get-ChildItem (Join-Path $App 'data/site') -Filter *.md -EA SilentlyContinue | ForEach-Object {
  if ($SeedDocs -or $Site -or ($siteThere -notcontains $_.Name)) {
    Push $_.FullName "$Root/data/site/$($_.Name)"
    Write-Host "  sent site/$($_.Name)"
  }
}

# Documents are only sent on the first install, or when asked for outright.
# A redeploy that quietly overwrote them would throw away whatever anybody had
# typed since, which is the whole point of the site.
# File by file, because a new document added later still has to arrive while
# the ones people have been typing in are left exactly as they are. Only what
# is missing goes, unless -SeedDocs says to overwrite the lot.
Write-Host ''
Write-Host 'Documents...'
if ($SeedDocs -or $Boards -or $docNames.Count) {
  # Every document on the VPS goes to .bak first. Both of these have thrown
  # away an evening of edits before now: -SeedDocs flattens the lot, -Boards
  # flattens board.json, and a board is the thing most likely to have been
  # typed into five minutes ago.
  #
  # The \* matters. -Include filters only what a wildcard or -Recurse has
  # already gathered, so on the bare folder it matched nothing and this said
  # "backed up 0 document(s)" on every run: no -Docs, -Boards or -SeedDocs
  # ever left the .bak the messages below promise. Measured 24 September on
  # Windows PowerShell 5.1: 0 files without it, every .md and .json with it.
  Remote @"
`$n = 0
foreach (`$f in Get-ChildItem '$rootWin\data\*' -File -Include *.md,*.json -EA SilentlyContinue) {
  Copy-Item `$f.FullName (`$f.FullName + '.bak') -Force -EA SilentlyContinue
  `$n++
}
'backed up ' + `$n + ' document(s) to .bak before overwriting'
"@ | ForEach-Object { "  $_" }
}
$there = @((Remote "Get-ChildItem '$rootWin\data' -File -EA SilentlyContinue | ForEach-Object Name") |
           Where-Object { $_ -is [string] } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$sent = 0
Get-ChildItem (Join-Path $App 'data') | Where-Object { $_.Extension -in '.md','.json' } |
  ForEach-Object {
    $force = $SeedDocs -or ($Boards -and $_.Name -eq 'board.json') -or ($docNames -contains $_.Name)
    if ($force -or ($there -notcontains $_.Name)) {
      Push $_.FullName "$Root/data/$($_.Name)"
      Write-Host "  sent $($_.Name)"
      $sent++
    }
  }
if (-not $sent) {
  Write-Host '  all present, nothing overwritten (use -SeedDocs to replace them)'
}
if ($Boards -and -not $SeedDocs) {
  Write-Host ''
  Write-Host '  -Boards replaced board.json with the repo copy.' -ForegroundColor Yellow
  Write-Host '  Anything typed into a board on the site since the last deploy is now' -ForegroundColor Yellow
  Write-Host '  only in board.json.bak on the VPS. Plain Deploy-Docs never does this.' -ForegroundColor Yellow
}
if ($docNames.Count -and -not $SeedDocs) {
  Write-Host ''
  Write-Host "  -Docs replaced $($docNames -join ', ') with the repo copy." -ForegroundColor Yellow
  Write-Host '  Anything typed into those on the site since the last deploy is in the' -ForegroundColor Yellow
  Write-Host '  .bak file beside each on the VPS. The other documents were not touched.' -ForegroundColor Yellow
}
if ($SeedDocs -and $sent) {
  Write-Host ''
  Write-Host "  -SeedDocs overwrote $sent document(s) with the repo copy." -ForegroundColor Yellow
  Write-Host '  Anything typed into the site since the last deploy is now in the .bak' -ForegroundColor Yellow
  Write-Host '  file beside it on the VPS. Use -Site next time if you only meant the' -ForegroundColor Yellow
  Write-Host '  public pages, or -Boards if you only meant the runbook.' -ForegroundColor Yellow
}

if ($Password) {
  Write-Host ''
  Write-Host 'Setting the password...'
  # Read, set, write: only the password changes. This used to write
  # {"password": ...} over the whole of config.json, which took the Discord
  # client id and secret, the bot token, the bot key, the admins, the server
  # password and the cookie secret with it. With no client id, discordReady()
  # in server.js is false, and isMember and /api/login take the password
  # again, so a wipe reopened the door Discord had shut. Rotate-ServerPassword
  # already reads before it writes; this is the same shape.
  #
  # A file that is there and will not parse is left exactly as it is, which is
  # server.js's own rule: unreadable is not empty, and the difference is
  # somebody's client secret. Read as UTF-8 because Get-Content in Windows
  # PowerShell reads a file with no byte order mark as the local code page,
  # and node writes none. Written with no mark, because one is how the site
  # once ran for days on its defaults while looking configured.
  #
  # Base64 so quoting survives ssh, cmd and PowerShell. It still travels inside
  # the command handed to ssh, so while this runs it is on the command line of
  # ssh here and of powershell on the VPS.
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Password))
  Remote @"
`$ErrorActionPreference = 'Stop'
`$pw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'))
`$f = '$rootWin\config.json'
`$cfg = [ordered]@{}
if (Test-Path -LiteralPath `$f) {
  `$old = `$null
  try { `$old = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText(`$f, [Text.Encoding]::UTF8)) } catch { }
  if (-not (`$old -is [Management.Automation.PSCustomObject])) {
    'CONFIG.JSON IS THERE AND WILL NOT READ AS JSON. Nothing written, the password is unchanged.'
    return
  }
  foreach (`$p in `$old.PSObject.Properties) { `$cfg[`$p.Name] = `$p.Value }
}
`$cfg['password'] = `$pw
[IO.File]::WriteAllText(`$f, (ConvertTo-Json -InputObject `$cfg -Depth 6), (New-Object Text.UTF8Encoding(`$false)))
'set, ' + (`$cfg.Count - 1) + ' other setting(s) kept'
"@ | ForEach-Object { "  $_" }
}

Write-Host ''
Write-Host 'Opening the port and starting it...'
Remote @"
`$ErrorActionPreference = 'Continue'

# Once Setup-Domain has run, the site answers on loopback only and Caddy holds
# 80 and 443. Opening 3001 again would put a plain HTTP way straight past the
# certificate, so a redeploy after that must not do it, and tears the rule back
# down if a previous run left one.
`$local = [Environment]::GetEnvironmentVariable('THORNSWOOD_DOCS_LOCAL','Machine')
if (`$local -eq '1') {
  Get-NetFirewallRule -DisplayName '$Task' -EA SilentlyContinue |
    Remove-NetFirewallRule -EA SilentlyContinue
  'behind the certificate, $Port left shut'
}
elseif (-not (Get-NetFirewallRule -DisplayName '$Task' -EA SilentlyContinue)) {
  New-NetFirewallRule -DisplayName '$Task' -Direction Inbound -Protocol TCP ``
    -LocalPort $Port -Action Allow | Out-Null
  'firewall opened on $Port'
} else { 'firewall rule already there' }

Get-CimInstance Win32_Process |
  Where-Object { `$_.Name -eq 'node.exe' -and `$_.CommandLine -like '*Thornswood-Docs*' } |
  ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -EA SilentlyContinue }
# Older installs ran it as plain 'server.js', which no command line filter can
# see, so whatever is holding the port goes too.
Get-NetTCPConnection -LocalPort $Port -State Listen -EA SilentlyContinue |
  ForEach-Object { Stop-Process -Id `$_.OwningProcess -Force -EA SilentlyContinue }
Start-Sleep -Seconds 1

`$node = (Get-Command node -EA SilentlyContinue).Source
if (-not `$node) { 'NODE NOT FOUND ON THIS MACHINE'; return }

# server.js goes in by its full path rather than by name. The path is what puts
# 'Thornswood-Docs' on the command line, and the command line is the only way
# to tell this node from any other one later.
`$a = New-ScheduledTaskAction -Execute `$node -Argument '$rootWin\server.js' -WorkingDirectory '$rootWin'
# Built once and used by both branches below.
#
# No execution time limit, because a task that is meant to run until the box
# goes down is stopped after three days by the default and nobody would
# connect the site vanishing to a deploy seventy two hours earlier.
#
# Ten restarts rather than three. Three was enough for one bored scanner to
# take the site off the internet for the rest of the day: a request for /%
# used to end the process, and once the three were spent nothing brought it
# back, which also took the launcher's login with it. The handler answers 400
# now so this should never be reached, but a service that stops trying to
# come back is not a thing to leave lying around.
`$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries ``
      -DontStopIfGoingOnBatteries -RestartCount 10 -RestartInterval (New-TimeSpan -Minutes 1) ``
      -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
if (-not (Get-ScheduledTask -TaskName '$Task' -EA SilentlyContinue)) {
  `$t = New-ScheduledTaskTrigger -AtStartup
  Register-ScheduledTask -TaskName '$Task' -Action `$a -Trigger `$t -Settings `$s ``
    -RunLevel Highest -User 'SYSTEM' | Out-Null
  'scheduled task created'
} else {
  # -Settings as well as -Action. Without it an existing task keeps whatever
  # it was first registered with, which is how the three restart cap survived
  # every deploy that was meant to change it.
  Set-ScheduledTask -TaskName '$Task' -Action `$a -Settings `$s | Out-Null
  'scheduled task updated'
}

# Read back rather than assumed. Set-ScheduledTask is quiet about settings
# it did not apply.
`$chk = (Get-ScheduledTask -TaskName '$Task' -EA SilentlyContinue).Settings
if (`$chk) {
  'task settings: restart count ' + `$chk.RestartCount +
  ', execution time limit ' + (`$(if (`$chk.ExecutionTimeLimit -eq 'PT0S') { 'none' } else { `$chk.ExecutionTimeLimit }))
}

Start-ScheduledTask -TaskName '$Task'
Start-Sleep -Seconds 4

# The port is the real answer. A process list can miss it, a listening socket
# cannot.
`$listen = Get-NetTCPConnection -LocalPort $Port -State Listen -EA SilentlyContinue
if (`$listen) {
  'docs up, pid ' + (`$listen | Select-Object -First 1).OwningProcess
} else {
  'DOCS DID NOT START. Running it by hand to see why:'
  `$o = Join-Path `$env:TEMP 'tw-docs-out.txt'
  `$e = Join-Path `$env:TEMP 'tw-docs-err.txt'
  Remove-Item `$o,`$e -Force -EA SilentlyContinue
  `$h = Start-Process -FilePath `$node -ArgumentList 'server.js' -WorkingDirectory '$rootWin' ``
        -RedirectStandardOutput `$o -RedirectStandardError `$e -PassThru -NoNewWindow
  Start-Sleep -Seconds 4
  if (`$h -and -not `$h.HasExited) {
    'it runs fine by hand, so the scheduled task is what is wrong'
    Stop-Process -Id `$h.Id -Force -EA SilentlyContinue
  }
  Get-Content `$o,`$e -EA SilentlyContinue | Select-Object -First 25
  (Get-ScheduledTask -TaskName '$Task' -EA SilentlyContinue | Get-ScheduledTaskInfo).LastTaskResult |
    ForEach-Object { 'task last result: ' + `$_ }
}
"@ | ForEach-Object { "  $_" }

Write-Host ''
Write-Host "  http://${Vps}:$Port" -ForegroundColor Green
