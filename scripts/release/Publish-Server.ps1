<#
  Publish-Server.ps1

  Run this ON YOUR LAPTOP. It packs the server, sends it to the VPS, installs it
  there and checks it came up. One command instead of six, and no RDP session.


  What it does, in order:
    1. builds the payload zip from your local dist\server
    2. stops the scheduled task on the VPS so files are not in use
    3. copies the zip across
    4. unpacks it there, checks every plugin in the load order is on disk,
       registers the boot task and starts it
    5. waits for the resources port to answer, from here

  The world folder on the VPS is preserved across reinstalls by the installer,
  so characters made on the server survive an update. -FreshWorld throws it away.

  It also writes a line into the launcher's News page and pushes it.

  A server change ships nothing. The gamemode runs on the VPS, so there is no
  file for anybody to download and nothing for their launcher to notice, which
  meant every trade kit, every starting town and every fix to creation went out
  with nobody told, while a one line launcher tweak got a headline. Both show up
  in the same place now.

      .\scripts\release\Publish-Server.ps1 "Bards start with instruments"
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Notes = '',
    [string]$RepoDir,
    # A folder holding the version.json to add the News entry to. Left out,
    # the live feed is received from the VPS store and sent back (#907), the
    # same shape as Set-Server.ps1. See the News section below.
    [string]$ReleaseDir,
    <#
      Which server this goes to. 'main' is the one everybody plays on.

      WHY THIS EXISTS, 21 September. Everything else here has a dev form:
      Ship.ps1 -Channel dev, Deploy-DevGamemode.ps1. This did not, so an
      engine change had one route and that route was live. Patrick, on being
      told that: "why is there no dev version that's a bigggggg issue". He is
      right, and it was worse than missing: the CAPABILITY was always here,
      because -VpsRoot and -TaskName are parameters and the dev server is
      C:\Thornswood-Server-Dev under 'Thornswood Dev Server'. Nothing was
      stopping a dev publish except that nobody could know it without reading
      this block, so the obvious command was the live one and that is the one
      that got run.

      A dev publish also writes no news and pushes nothing, because a news
      entry saying the server changed belongs to the server everybody is on.
    #>
    [ValidateSet('main', 'dev')][string]$Channel = 'main',
    [switch]$NoNews,
    [switch]$NoPush,
    [string]$VpsHost  = '',
    [string]$VpsUser  = 'Administrator',
    [string]$Dist     = (& (Join-Path $PSScriptRoot 'Where.ps1') ServerDist),
    [string]$Zip      = (& (Join-Path $PSScriptRoot 'Where.ps1') ServerZip),
    [string]$VpsRoot,
    [string]$TaskName,
    [switch]$FreshWorld,
    [switch]$SkipBuild,
    [switch]$NoPause
)

# The two that the channel decides, unless they were given outright. An
# explicit -VpsRoot still wins, the same way Ship.ps1 lets -Root win.
$IsDev = ($Channel -eq 'dev')
if (-not $PSBoundParameters.ContainsKey('VpsRoot')) {
    $VpsRoot = if ($IsDev) { 'C:\Thornswood-Server-Dev' } else { 'C:\Thornswood-Server' }
}
if (-not $PSBoundParameters.ContainsKey('TaskName')) {
    $TaskName = if ($IsDev) { 'Thornswood Dev Server' } else { 'Thornswood Server' }
}
if ($IsDev) {
    # A dev release is not news and is not a source commit. Said out loud
    # rather than done quietly, so a dev run reads differently from a main one.
    $NoNews = $true
    $NoPush = $true
}

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }

function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$target = "$VpsUser@$VpsHost"

# ---------------------------------------------------------------- tools ------
foreach ($t in 'ssh', 'scp') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client."
    }
}

# ------------------------------------------------------------- gamemode ------
# The gamemode is edited in tools\ and packaged from dist\server. Those are two
# different files, and for a whole evening every change went into the first one
# while every publish shipped the second: the race menu fix, the launcher
# choices, the removal of the books, none of it ever reached the server, and
# nothing said so because both files existed and both looked right.
#
# Copied here rather than left to a separate script somebody has to remember.
$gamemodeMoved = $false
$gmSrc = Join-Path $Here '..\..\game\gamemode.js'
$gmDst = Join-Path $Dist 'gamemode.js'
if ((Test-Path -LiteralPath $gmSrc) -and (Test-Path -LiteralPath $Dist)) {
    $srcHash = (Get-FileHash -LiteralPath $gmSrc -Algorithm SHA256).Hash
    $dstHash = if (Test-Path -LiteralPath $gmDst) {
        (Get-FileHash -LiteralPath $gmDst -Algorithm SHA256).Hash
    } else { '' }
    if ($srcHash -ne $dstHash) {
        Head 'Gamemode'
        Copy-Item -LiteralPath $gmSrc -Destination $gmDst -Force
        $gamemodeMoved = $true
        Say ("copied game\gamemode.js into the build ({0:N0} bytes)" -f (Get-Item -LiteralPath $gmDst).Length) 'Green'
    }
}

# --------------------------------------------------- where new characters go --
# The start point is a raw form id, and a raw form id rots when the load order
# moves. SkyMP resolves it as fileIdx * 0x01000000 + shortFormId, where fileIdx
# is the load order's own index, so moving one plugin above Skyrim Unbound
# points every new character at a completely different record.
#
# It has rotted before. The id said index 57 while Unbound had drifted to 59,
# so everybody spawned at whatever sat at 0x19BAD4 in a body morph plugin. The
# gamemode noticed they were not in the creation hall and teleported them, and
# from a chair that is character creation starting in a tavern and then
# dragging through a load screen into the hall. Testers reported exactly that
# on 20 September, as creation happening in the Riften inn.
#
# Deploy-Gamemode.ps1 computes this correctly. This script never checked it, so
# a publish that skipped Deploy-Gamemode shipped whatever was last written and
# nothing said a word. The gamemode logs START POINT IS WRONG on boot, to a
# file on the VPS that nobody reads.
#
# Checked rather than recomputed, on purpose. The file being read is the one
# about to be zipped, and a publish that quietly rewrites its own input is
# worse than one that stops and names the command that fixes it.
$settingsPath = Join-Path $Dist 'server-settings.json'

<#
  A DEV PUBLISH REWRITES THE PORTS BEFORE ANYTHING IS PACKED.

  The build's server-settings.json is the LIVE one: port 7777, name
  Thornswood. Unpacked into the dev root unchanged it brings the dev server up
  on the live port, which is what happened the first time this channel was
  run. vps-dev-instance.ps1 is where these two numbers come from, and they are
  the same ones Deploy-DevGamemode.ps1 checks for.

  Written into the DIST copy rather than on the box, so what is packed is what
  runs, and a publish that fails half way has not left a live port in a dev
  folder.
#>
if ($IsDev -and (Test-Path -LiteralPath $settingsPath)) {
    try {
        $devJson = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $devJson.port = 7787
        if ($devJson.PSObject.Properties.Name -contains 'name') {
            $devJson.name = 'Thornswood Dev'
        }
        if ($devJson.PSObject.Properties.Name -contains 'thornswoodVoicePort') {
            $devJson.thornswoodVoicePort = 7789
        } else {
            $devJson | Add-Member -NotePropertyName thornswoodVoicePort -NotePropertyValue 7789
        }
        $devJson | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $settingsPath -Encoding UTF8
        Say '  dev channel: port 7787, voice 7789, name Thornswood Dev' 'Green'
    } catch {
        throw "Could not set the dev ports in $settingsPath : $_"
    }
}
if (Test-Path -LiteralPath $settingsPath) {
    Head 'Where new characters start'
    $hallPlugin = 'Skyrim Unbound.esp'
    $hallLocal = 0x19BAD4                     # SkyrimUnboundRoom01
    $gate = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json

    $order = @($gate.loadOrder)
    $hallIdx = -1
    for ($i = 0; $i -lt $order.Count; $i++) {
        $leaf = [IO.Path]::GetFileName(([string]$order[$i]).Replace('/', '\'))
        if ($leaf -ieq $hallPlugin) { $hallIdx = $i; break }
    }

    # Written as '0x3A19BAD4' by Deploy-Gamemode, but a hand edit could leave a
    # bare number or bare hex, and reading it wrong would fail this for the
    # wrong reason.
    $have = -1
    $pts = @($gate.startPoints)
    if ($pts.Count -and $null -ne $pts[0].worldOrCell) {
        $raw = ([string]$pts[0].worldOrCell).Trim()
        try {
            if ($raw -match '^0[xX][0-9a-fA-F]+$') { $have = [Convert]::ToInt64($raw.Substring(2), 16) }
            elseif ($raw -match '^[0-9]+$')        { $have = [Convert]::ToInt64($raw, 10) }
            elseif ($raw -match '^[0-9a-fA-F]+$')  { $have = [Convert]::ToInt64($raw, 16) }
        } catch { $have = -1 }
    }

    if ($hallIdx -lt 0) {
        Say "$hallPlugin is not in the load order, so the Whiterun gate fallback applies" 'Yellow'
        Say '  Creation still runs, in a less tidy place. Nothing to fix here.' 'Yellow'
    } elseif ($have -lt 0) {
        Say 'server-settings.json has no readable startPoints entry.' 'Yellow'
        Die 'Run .\scripts\deploy\Deploy-Gamemode.ps1 first, then publish again.'
    } else {
        $want = ($hallIdx * 0x01000000) + $hallLocal
        if ($have -eq $want) {
            Say ("correct: $hallPlugin at index $hallIdx, form 0x{0:X8}" -f $want) 'Green'
        } else {
            Say ("server-settings.json says 0x{0:X8}, and $hallPlugin is at index $hallIdx, which is 0x{1:X8}." -f $have, $want) 'Yellow'
            Say '  Publishing this would put every NEW character in the wrong cell. The' 'Yellow'
            Say '  gamemode would notice and teleport them, which from a chair is' 'Yellow'
            Say '  character creation starting in a tavern instead of the creation hall.' 'Yellow'
            Die 'Run .\scripts\deploy\Deploy-Gamemode.ps1 first, then publish again.'
        }
    }
}

# ---------------------------------------------------------------- build ------
if (-not $SkipBuild) {
    Head 'Packing the payload'
    $export = Join-Path $Here 'Export-ServerPayload.ps1'
    if (-not (Test-Path -LiteralPath $export)) { Die "not found: $export" }
    # The same PowerShell that is running this, not whichever one 'powershell'
    # resolves to. Handing the job to 5.1 from a 7 session changes how files
    # get written underneath it, which is how the payload picked up a byte
    # order mark that only ever showed up as a parse error on the VPS.
    $ps = (Get-Process -Id $PID).Path
    if (-not $ps) { $ps = 'powershell' }
    & $ps -NoProfile -ExecutionPolicy Bypass -File $export -Dist $Dist -Zip $Zip -VpsRoot $VpsRoot
    if ($LASTEXITCODE -ne 0) { Die "Export-ServerPayload.ps1 exited with $LASTEXITCODE" }
}
if (-not (Test-Path -LiteralPath $Zip)) { Die "not found: $Zip. Run without -SkipBuild." }
Say ("payload {0:N1} MB" -f ((Get-Item -LiteralPath $Zip).Length / 1MB)) 'Green'

# ---------------------------------------------------------------- installer --
# Sent every time rather than trusting whatever copy is up there, so the VPS
# never runs a version of the installer older than the payload it is unpacking.
$installer = Join-Path $Here '..\deploy\Install-ThornswoodServer.ps1'
if (-not (Test-Path -LiteralPath $installer)) { Die "not found: $installer" }
# Beside the installer, which puts it in the server's folder for the task to
# run in front of the server. See Roll-Log.ps1 for why a log can only be
# rolled at start.
$rollLog = Join-Path $Here '..\vps\Roll-Log.ps1'
if (-not (Test-Path -LiteralPath $rollLog)) { Die "not found: $rollLog" }

Head 'Stopping the server up there'
# Not fatal: on a first install there is no task to stop.
#
# Sent base64 encoded rather than as a quoted string. The previous version wrote
# \$_.Name, escaping with a backslash, which PowerShell does not use: the escape
# character is a backtick. So the backslash stayed literal, $_ expanded to
# nothing outside a pipeline, and the remote shell was asked to run a command
# called \.Name, once per process on the box. A hundred red errors every publish,
# none of them real, and real ones buried in the middle of them.
#
# EncodedCommand takes the script as one blob and nothing has to survive two
# layers of quoting.
$stopRemote = @'
$ProgressPreference = 'SilentlyContinue'
Stop-ScheduledTask -TaskName '@@TASK@@' -ErrorAction SilentlyContinue
<#
  BY THE FOLDER, NOT BY THE WORD skymp5-server.

  This used to match every node process carrying 'skymp5-server' on its
  command line. On the live server that is the live server and nothing else,
  so it was right for years. The moment this script gained a dev channel it
  was the thing that took the LIVE server down while publishing to dev, on
  21 September, exactly as Deploy-DevGamemode.ps1's header warns it would.

  The trailing backslash is the whole of the fix and it is not decoration:
  'C:\Thornswood-Server' is a prefix of 'C:\Thornswood-Server-Dev', so
  matching without it means a live publish also kills the dev server, and the
  bug simply changes direction.
#>
Get-CimInstance Win32_Process -EA SilentlyContinue |
  Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -like '*@@ROOT@@\*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
'stopped'
'@ -replace '@@TASK@@', $TaskName -replace '@@ROOT@@', $VpsRoot.TrimEnd('\')

$stopEnc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($stopRemote))
& ssh $target "powershell -NoProfile -EncodedCommand $stopEnc"

Head 'Copying'
Say 'this is the slow part, a few minutes on a first run' 'DarkGray'
& scp $Zip "${target}:C:/thornswood-server.zip"
if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE" }
& scp $installer "${target}:C:/Install-ThornswoodServer.ps1"
if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE" }
& scp $rollLog "${target}:C:/Roll-Log.ps1"
if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE" }
Say 'copied' 'Green'

Head 'Installing'
$instArgs = "-Zip C:\thornswood-server.zip -Root '$VpsRoot' -TaskName '$TaskName' -StartNow"
if ($FreshWorld) {
    Say 'throwing away the world on the VPS as asked' 'Yellow'
    & ssh $target "powershell -NoProfile -Command `"Remove-Item -LiteralPath '$VpsRoot\world' -Recurse -Force -ErrorAction SilentlyContinue; 'world cleared'`""
}
& ssh $target "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Install-ThornswoodServer.ps1 $instArgs"
if ($LASTEXITCODE -ne 0) { Die "the installer on the VPS exited with $LASTEXITCODE. Nothing local was changed." }

<#
  DEV CARRIES MAIN'S ROSTER.

  Patrick, 21 September, on the dev server: "Dev has no playtetser list so I
  can't tp like I can on main", and then "keep the same list on dev as main as
  so I as Owner still have commands".

  The roles come out of private\door.json and private\allowed.json, which the
  door fetches and writes beside itself in the LIVE root. A dev root has never
  had them: nothing creates that folder on a fresh install, and the door on
  dev has no reason to have fetched yet. So every tier answered no to
  everybody on dev, including the owner, and /tp refused him on his own server.

  The live root's copy is taken as the truth and put into the dev root every
  dev publish, so the two lists cannot drift and a playtester added in Discord
  reaches dev the moment live has it. One direction only: dev never writes back
  over live.

  NOTHING IS READ OUT OF THOSE FILES HERE. They are copied on the VPS, from one
  folder to another, and only the count is printed. door.json is a config file
  and its contents are not this script's business.

  Install-ThornswoodServer.ps1 now sets the folder aside and restores it, so
  after the first seeding this is keeping the two in step rather than repairing
  a wipe.
#>
if ($IsDev) {
    Head 'The roster'
    $seed = @'
# PowerShell wraps the answer in a block of CLIXML progress records without
# this, which is the trap already written down on the server build entry. It
# leaked into the roster line on the first run.
$ProgressPreference = 'SilentlyContinue'
$live = 'C:\Thornswood-Server\private'
$dev  = '@@DEVROOT@@\private'
if (-not (Test-Path -LiteralPath $live)) {
    'the live server has no private folder, so there is no roster to copy'
} else {
    New-Item -ItemType Directory -Path $dev -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $live '*') -Destination $dev -Recurse -Force
    $n = @(Get-ChildItem -LiteralPath $dev -File -Force -EA SilentlyContinue).Count
    "dev now has the same roster as main, $n file(s)"
}
'@
    $seed = $seed.Replace('@@DEVROOT@@', $VpsRoot.TrimEnd('\'))
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($seed))
    $out = & ssh $target "powershell -NoProfile -EncodedCommand $enc"
    foreach ($line in @($out)) { Say "  $line" 'Green' }
}

# ---------------------------------------------------------------- verify -----
# Game traffic is UDP and there is nothing to connect to, so the resources
# folder is what a probe from here can actually reach.
#
# THE PORTS ARE THE CHANNEL'S, AND THEY USED TO BE THE LIVE ONES EITHER WAY.
#
# 21 September, on the first dev publish of the engine changes, this printed
# "Thornswood is up at <live address:port>" at the end of a run that had
# correctly said "dev channel: port 7787" at the top. Both numbers here were
# written in, so a dev publish probed the LIVE resources port, got an answer
# from the LIVE server, and reported a healthy dev server without ever having
# asked it anything. It would have said exactly the same thing if the dev
# server had failed to start, which is the one case this block exists for.
#
# The resources port is not a setting. skymp5-server/ts/ui.ts:102 derives it:
# 3000 when the game port is 7777, and game port plus one otherwise. So dev is
# 7788 and there is no clash with live, and this is where that rule is written
# down on our side of the fence.
$GamePort = if ($IsDev) { 7787 } else { 7777 }
$ResPort  = if ($GamePort -eq 7777) { 3000 } else { $GamePort + 1 }

Head 'Checking it answers'
$up = $false
for ($i = 0; $i -lt 30; $i++) {
    try {
        $c = New-Object Net.Sockets.TcpClient
        $null = $c.BeginConnect($VpsHost, $ResPort, $null, $null).AsyncWaitHandle.WaitOne(1000)
        $up = $c.Connected
        $c.Close()
    } catch { }
    if ($up) { break }
    Start-Sleep -Seconds 2
}

Write-Host ''
if ($up) {
    Say ("{0} is up at {1}:{2}, resources on {3}" -f $(if ($IsDev) { 'The DEV server' } else { 'Thornswood' }), $VpsHost, $GamePort, $ResPort) 'Green'
    Write-Host ''
} else {
    Say "The install finished but nothing is answering on ${VpsHost}:${ResPort}." 'Red'

    # Rather than list what it might be, fetch what it actually said. The task
    # redirects everything the server prints into this file for exactly this.
    Head 'What the server printed up there'
    & ssh $target "powershell -NoProfile -Command `"if (Test-Path '$VpsRoot\server.log') { Get-Content '$VpsRoot\server.log' -Tail 40 } else { 'server.log is not there, so node never started. Check that node is on the machine PATH up there.' }`""

    Write-Host ''
    Say 'If that log is empty or says nothing useful, the other candidate is the' 'Yellow'
    Say 'firewall. The server can be up and still unreachable from here:' 'Yellow'
    Say "    ssh $target `"powershell -NoProfile -Command Get-NetFirewallRule -DisplayName '*Thornswood*' ^| Format-Table DisplayName,Enabled,Direction`"" 'DarkGray'
}

# ------------------------------------------------------------------ news ----
# The launcher reads version.json for its News page. Publish-Update writes to
# it on every mod or launcher release; this did not, so anything that lives
# only on the server went out silently.
#
# Said plainly in the entry, because it is the useful part: nobody downloads
# anything for this. Somebody reading a headline about instruments should not
# go looking for an update button that is not going to light up.
if (-not $NoNews -and $up) {
    if (-not $RepoDir) { $RepoDir = Split-Path -Parent (Split-Path -Parent $Here) }
    # THE LIVE FEED, NOT THE COPY IN THIS REPO. Until 23 September this wrote
    # into the repo's own version.json. That file is not dead, it is the
    # shipped default read as a template, and nothing publishes it: every
    # launcher reads the copy in the public releases clone. So a server change
    # was written down in a file nobody reads, which is the same as not being
    # announced at all, and the whole reason this News section exists.
    #
    # Since #907 the live feed is on the VPS store (Feed-Store.ps1): received
    # into this machine's working folder for main, the entry added, and sent
    # back. Until then it was the Thornswood-Releases clone, pushed. -ReleaseDir
    # works on a folder instead and receives nothing.
    . (Join-Path $Here 'Feed-Store.ps1')
    $receive = -not $ReleaseDir
    if (-not $ReleaseDir) { $ReleaseDir = Get-FeedStoreDir 'main' }
    if ($receive -and -not $NoPush) {
        try { [void](Receive-FeedStore 'main' $ReleaseDir) }
        catch { Say "  could not receive the live feed from the VPS: $($_.Exception.Message)" 'Yellow' }
    }
    $VersionFile = Join-Path $ReleaseDir 'version.json'

    if (-not (Test-Path -LiteralPath $VersionFile)) {
        Say "no version.json in $ReleaseDir, so nothing was added to the News page" 'Yellow'
    } else {
        Head 'News'
        try {
            $doc = Get-Content -LiteralPath $VersionFile -Raw | ConvertFrom-Json

            # What actually moved, worked out here rather than taken from the
            # note, so an entry says something even when the note is empty.
            $details = @()
            foreach ($line in @($Notes -split "`r?`n")) {
                $t = $line.Trim()
                if ($t -match '^[-*\u2022]\s*(.+)$') { $details += $Matches[1].Trim() }
            }

            # Two lines used to go in here that were for whoever ran this, not
            # for the people reading the News tab and the site: "The gamemode
            # was rebuilt: starting kits, creation and arrival points live in
            # it", untrue since the kits went on 20 September, and "Load order:
            # 60 plugins server side". Entry 187 on the To Do List: patch notes
            # people read are about what they will notice. The gamemode copy is
            # said above where it happens; the count is said here, on screen.
            try {
                $ss = Get-Content -LiteralPath (Join-Path $Dist 'server-settings.json') -Raw | ConvertFrom-Json
                if ($ss.loadOrder) { Say ('  load order: {0} plugins server side' -f @($ss.loadOrder).Count) 'DarkGray' }
            } catch { }

            if ($FreshWorld) { $details += 'The world was thrown away, so every character on the server is gone' }
            $details += 'Nothing to download for this one. It is on the server, so it is already live.'

            # A headline and the rest, the same shape Publish-Update writes, so
            # the News page does not have to know which of the two made an entry.
            $noteLines = @($Notes -split "`r?`n")
            $title = if ($noteLines[0].Trim()) { $noteLines[0].Trim() } else { 'Server updated' }
            $bodyBits = @()
            for ($i = 1; $i -lt $noteLines.Count; $i++) {
                $line = $noteLines[$i].Trim()
                if ($line -and $line -notmatch '^[-*\u2022]') { $bodyBits += $line }
            }
            # A one-line note leaves the body empty, the same as a one-line
            # Ship. It used to be filled with "The server at" and the VPS
            # address "was reinstalled and is answering", which put the address
            # on the public news page and told nobody anything they would notice.
            $body = ($bodyBits -join ' ').Trim()

            # 'kind' and 'stamp' are extra members the launcher never asked
            # for. NewsItem is read with DataContractJsonSerializer, which
            # ignores what it was not told about, so old launchers are safe.
            # They are here so this script can recognise its own entries.
            $named = [bool]$noteLines[0].Trim()
            $entry = [pscustomobject]@{
                date    = (Get-Date).ToString('d MMM yyyy')
                title   = $title
                body    = $body
                details = @($details)
                files   = @()
                kind    = 'server'
                stamp   = (Get-Date).ToString('o')
                named   = $named
            }

            $newsList = @()
            if ($doc.PSObject.Properties['news'] -and $doc.news) { $newsList = @($doc.news) }

            # Publishing the server twice over one change is normal while
            # something is being chased. That is one piece of news, not four.
            #
            # Three runs tonight put three entries at the top of a feed that
            # holds twenty, and three real releases fell off the bottom to make
            # room. An unnamed run is somebody pushing a fix, not an
            # announcement, so it stands in until there is something to say and
            # then gets written over rather than pushing history out.
            $repeat = $false
            $replaceTop = $false
            if ($newsList.Count -gt 0) {
                $top = $newsList[0]
                $topTitle = if ($top.PSObject.Properties.Name -contains 'title') { [string]$top.title } else { '' }
                $topBody  = if ($top.PSObject.Properties.Name -contains 'body')  { [string]$top.body }  else { '' }
                $topKind  = if ($top.PSObject.Properties.Name -contains 'kind')  { [string]$top.kind }  else { '' }
                $topNamed = $true
                if ($top.PSObject.Properties.Name -contains 'named') { $topNamed = [bool]$top.named }

                if ($topTitle -eq $entry.title -and $topBody -eq $entry.body) { $repeat = $true }
                elseif ($topKind -eq 'server' -and -not $topNamed) { $replaceTop = $true }
            }

            if ($repeat) {
                Say '  same note as last time, so no new entry' 'DarkGray'
            } else {
                if ($replaceTop) {
                    Say '  the entry above it had no note, so this replaces it' 'DarkGray'
                    $newsList = @($entry) + @($newsList | Select-Object -Skip 1)
                } else {
                    $newsList = @($entry) + $newsList
                }
                # Forty, not twenty. Twenty was one evening's worth.
                if ($newsList.Count -gt 40) { $newsList = $newsList[0..39] }
                if ($doc.PSObject.Properties.Name -contains 'news') { $doc.news = $newsList }
                else { $doc | Add-Member -NotePropertyName news -NotePropertyValue $newsList }

                # No byte order mark. The launcher's reader stops on one and
                # reports an unexpected character, which takes out the update
                # check for everybody at once, including their route to a fix.
                [IO.File]::WriteAllText($VersionFile, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
                Say ("  added: {0}" -f $entry.title) 'Green'

                if (-not $NoPush) {
                    # THE LIVE FEED ON THE VPS, NEVER THE SOURCE REPO.
                    #
                    # This used to Push-Location into the source repo and run a
                    # bare git push there, which pushed a file nobody reads and
                    # whatever branch the source repo had checked out, usually
                    # main. Then it pushed the Thornswood-Releases clone by -C.
                    # Since #907 the entry goes to the VPS store, where the
                    # site serves it at once; a feed that changed up there
                    # since it was received is refused, not overwritten.
                    try {
                        [void](Send-FeedStore 'main' $ReleaseDir @('version.json'))
                        Say '  sent; the News entry is on the live feed' 'DarkGray'
                    } catch {
                        Say "  the feed was not sent, so nobody has the News entry yet: $($_.Exception.Message)" 'Yellow'
                        Say '  Run this again to add it.' 'Yellow'
                    }
                }
            }
        } catch {
            Say "  could not write the News entry: $($_.Exception.Message)" 'Yellow'
            Say '  The server is up regardless. Nothing else was changed.' 'DarkGray'
        }
    }
}

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
