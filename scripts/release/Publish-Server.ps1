<#
  Publish-Server.ps1

  Run this ON YOUR LAPTOP. It packs the server, sends it to the VPS, installs it
  there and checks it came up. One command instead of six, and no RDP session.


  What it does, in order:
    0. refuses, naming each file, when anything it would send out of this
       repository has uncommitted changes (#1121)
    1. builds the payload zip from your local dist\server, refusing any
       server file (the binary, the JavaScript half, the rest the fork
       builds) that is not the build records\server-build.json names, and
       puts that record in the zip; the zip is read back and held the same
       way before it is sent (#1214)
    2. copies the zip across, with the server still running
    3. the installer unpacks it BESIDE the running server, gives it the
       running server's own settings with only the release's keys from the
       zip (ServerSettings.ps1, #1222), checks it there (the zip's hash, every
       plugin in the load order, gamemode.js parsing, every server file
       against its record, ServerBuild.ps1) and stops nothing if any of it
       fails
    4. only then stops the server, swaps the new folder in, registers the
       boot task and starts it; if it does not answer on its ports, the
       previous folder goes back and is started again (issue #446)
    5. waits for the resources port to answer, from here

  The world folder on the VPS is carried across reinstalls by the installer,
  so characters made on the server survive an update. -FreshWorld starts the
  server with none, and leaves the old one in the previous folder.

  The previous folder is kept beside the root, the newest two, and
      .\scripts\release\Publish-Server.ps1 -PutBack
  puts the newest back the same checked way (-Channel dev for the dev server).

  THE JOIN PASS SWITCH (#1804). The installer refuses, before anything is
  stopped, a server whose thornswoodRequirePass is neither true nor false,
  because the gamemode reads that as on (#1319), and says so. A first
  install always is such a server, since no build carries the switch (#1223).
      .\scripts\release\Publish-Server.ps1 -RequirePass on
  sets it on the server in that publish (off lets a session act until its
  pass arrives); without it the running server keeps its own.

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
    [string]$VpsUser  = '',
    [string]$Dist     = (& (Join-Path $PSScriptRoot 'Where.ps1') ServerDist),
    [string]$Zip      = (& (Join-Path $PSScriptRoot 'Where.ps1') ServerZip),
    [string]$VpsRoot,
    [string]$TaskName,
    [switch]$FreshWorld,
    [switch]$SkipBuild,
    [switch]$NoPause,
    # Put the previous server folder back instead of publishing. Builds and
    # sends nothing but the installer, and writes no news.
    [switch]$PutBack,
    # How long the new server has to answer on the box before the previous one
    # goes back.
    [int]$Wait = 60,
    # The build record the binary is held to (#1214). The repository's own,
    # which the committed check below holds to the commit.
    [string]$Record = '',
    <#
      The ports this run holds the payload and the box to, for the harnesses
      only (#1728). Left at 0, which is how a person shipping runs it, they
      are the channel's, exactly as before: the zip must start the server on
      7787 (dev) or 7777 (live), and the check after the install knocks on the
      resources port, 3000 for 7777 and the game port plus one otherwise.
      tests\test-publish-server-channel.ps1 and tests\test-install-server.ps1
      run beside other builds on the VPS, where the dev and live servers hold
      those very ports, so each takes ports from the system and passes them.
      A payload is built with the channel's port, so -GamePort only matches a
      -SkipBuild zip made for that port; any other zip is refused as before.
    #>
    [ValidateRange(0, 65535)][int]$GamePort = 0,
    [ValidateRange(0, 65535)][int]$ResourcesPort = 0,
    # thornswoodRequirePass for the server this publishes to, set there by the
    # installer (#1804, see the header). Left off, the running server keeps
    # its own, and one with neither true nor false is refused. Live goes on
    # only when Patrick says Main.
    [ValidateSet('', 'on', 'off')][string]$RequirePass = ''
)
if (-not $Record) { $Record = Join-Path $PSScriptRoot '..\..\records\server-build.json' }

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
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }

function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

# A put-back sets no setting: the installer puts the previous folder back
# with the running server's own (#1804). Refused before anything is built,
# sent or asked, the way Deploy-Server.ps1 refuses -PutBack with -RequirePass.
if ($PutBack -and $RequirePass) {
    Die '-PutBack sets no setting: it puts the previous server back with the running server''s own settings. Run it without -RequirePass, then a publish with it. Nothing was sent.'
}

$target = "$VpsUser@$VpsHost"
# Host key checking on (issue #450): ssh talks only to the box whose key
# Setup-SshKey.ps1 wrote into known_hosts, checked against vps.json.
$ssh = @('-o', 'StrictHostKeyChecking=yes')

# ---------------------------------------------------------------- tools ------
foreach ($t in 'ssh', 'scp') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client."
    }
}

# -------------------------------------------------------- committed only ----
# A publish sends a commit or nothing (Patrick, 29 Sep, #1121). The files it
# takes out of this repository are the installer and the log roller, sent
# every time, and for a publish the gamemode it copies into the build and the
# number of people records\most-online.json puts in the settings. Any of them
# with uncommitted changes, or untracked, refuses it here, naming each, before
# anything is built or the box is asked anything. There is no switch past it.
. (Join-Path $Here '..\deploy\Artifact.ps1')
$committedOnly = @('scripts/deploy/Install-ThornswoodServer.ps1', 'scripts/deploy/ServerSettings.ps1', 'scripts/deploy/ServerBuild.ps1', 'scripts/vps/Roll-Log.ps1')
if (-not $PutBack) { $committedOnly += 'game/gamemode.js', 'records/most-online.json', 'records/server-build.json' }
try { Assert-ThornswoodCommitted -RepoDir (Join-Path $Here '..\..') -Paths $committedOnly -What 'this publish' }
catch { Die $_.Exception.Message }

# ------------------------------------------------------------- installer ----
# Sent every time rather than trusting whatever copy is up there, so the VPS
# never runs a version of the installer older than the payload it is unpacking.
$installer = Join-Path $Here '..\deploy\Install-ThornswoodServer.ps1'
if (-not (Test-Path -LiteralPath $installer)) { Die "not found: $installer" }
# Beside the installer, which puts it in the server's folder for the task to
# run in front of the server. See Roll-Log.ps1 for why a log can only be
# rolled at start.
$rollLog = Join-Path $Here '..\vps\Roll-Log.ps1'
if (-not (Test-Path -LiteralPath $rollLog)) { Die "not found: $rollLog" }
# And ServerSettings.ps1 beside it, which says which settings come from the
# payload and which stay the running server's (#1222). The installer refuses
# without it rather than put the build's settings over the server's.
$settingsLib = Join-Path $Here '..\deploy\ServerSettings.ps1'
if (-not (Test-Path -LiteralPath $settingsLib)) { Die "not found: $settingsLib" }
# And ServerBuild.ps1, which says which server files the record holds and
# holds them (#1214), here to the zip and there to the stage.
$buildLib = Join-Path $Here '..\deploy\ServerBuild.ps1'
if (-not (Test-Path -LiteralPath $buildLib)) { Die "not found: $buildLib" }
. $buildLib

# What the installer said, printed as it comes, and its last line read: it
# ends with INSTALL OK, INSTALL REFUSED, INSTALL ROLLED BACK or INSTALL FAILED.
function Invoke-Installer([string]$instArgs) {
    $lines = @(Invoke-ThornswoodNative { & ssh @ssh $target "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Install-ThornswoodServer.ps1 $instArgs" } |
               ForEach-Object { Say "  $_"; "$_".Trim() })
    $code = $LASTEXITCODE
    if ($lines -contains 'INSTALL OK' -and $code -eq 0) { return }
    if ($lines -contains 'INSTALL REFUSED') {
        Die "the installer refused, so the server up there was not stopped or changed. The lines above say why."
    }
    if ($lines -contains 'INSTALL ROLLED BACK') {
        Die "the new server did not answer, or its settings did not read back as the server's own, so the installer put the previous one back. The lines above say which, and whether it answers."
    }
    Die "the installer on the VPS exited with $code and did not say it finished. THE SERVER MAY BE DOWN: look at $VpsRoot and the folders beside it before anything else."
}

# ------------------------------------------------------------- -PutBack -----
if ($PutBack) {
    Head 'Putting the previous server back'
    Invoke-ThornswoodNative { & scp @ssh $installer "${target}:C:/Install-ThornswoodServer.ps1" }
    if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE. Nothing up there was changed." }
    Invoke-ThornswoodNative { & scp @ssh $rollLog "${target}:C:/Roll-Log.ps1" }
    if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE. Nothing up there was changed." }
    Invoke-ThornswoodNative { & scp @ssh $settingsLib "${target}:C:/ServerSettings.ps1" }
    if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE. Nothing up there was changed." }
    Invoke-ThornswoodNative { & scp @ssh $buildLib "${target}:C:/ServerBuild.ps1" }
    if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE. Nothing up there was changed." }
    Invoke-Installer "-Root '$VpsRoot' -TaskName '$TaskName' -StartNow -PutBack -Wait $Wait"
    Say 'the previous server is back and answering up there' 'Green'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ------------------------------------------------------------- gamemode ------
# The gamemode is edited in game\ and packaged from dist\server. Those are two
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
  A DEV PUBLISH PACKS THE DEV PORTS, AND ONLY INTO THE PAYLOAD.

  The build's server-settings.json is the LIVE one: port 7777, name
  Thornswood. Unpacked into the dev root unchanged it brings the dev server up
  on the live port, which is what happened the first time this channel was
  run. So Export-ServerPayload.ps1 -Channel dev writes port 7787, voice 7789
  and the name Thornswood Dev into its staged copy, and the zip carries them.

  It used to write them here, into the build's own file, and never put them
  back (#1114): the next live publish packed them and live came up on 7787
  under the dev name. The build is not written for a channel any more, a live
  export refuses settings that are not the live server's, and the zip is read
  back below before it is sent.

  Over a running server none of that reaches it any more (#1222): the
  installer keeps that server's own settings, its switches, npcSettings, ports
  and name, and takes from the zip only the load order, the start point and
  how many it holds (ServerSettings.ps1). The dev values here are for a first
  install into an empty dev root.
#>
<#
  AND HOW MANY IT HOLDS AT ONCE, #481, whichever channel it goes to:
  thornswoodMostOnline for the gamemode and maxPlayers, with the staff seats
  on top, for the engine, from records\most-online.json by way of
  MaxOnline.ps1. Into the DIST copy like the ports above, so what is packed
  carries the one number, and only written when it moved.
#>
if (Test-Path -LiteralPath $settingsPath) {
    . (Join-Path $PSScriptRoot '..\deploy\MaxOnline.ps1')
    $mostOnline = Get-MostOnline
    # The two keys a publish puts over the running server's (ServerSettings.ps1,
    # #1222), so they are the record's number or the publish does not go.
    if ($mostOnline.Value -le 0) { Die ("$($mostOnline.From) gave no number ($($mostOnline.Why)), and a publish sets how many the server holds from it. Nothing was sent.") }
    try {
        $capJson = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $capWas = [string]$capJson.thornswoodMostOnline + '/' + [string]$capJson.maxPlayers
        Set-MaxPlayers $capJson $mostOnline
        if (([string]$capJson.thornswoodMostOnline + '/' + [string]$capJson.maxPlayers) -ne $capWas) {
            [IO.File]::WriteAllText($settingsPath, ($capJson | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
        }
    } catch {
        throw "Could not set how many the server holds in $settingsPath : $_"
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
    # The staging folder beside the zip (out\_payload beside
    # out\thornswood-server.zip, the same as its default).
    & $ps -NoProfile -ExecutionPolicy Bypass -File $export -Dist $Dist -Zip $Zip -VpsRoot $VpsRoot `
        -OutDir (Join-Path (Split-Path -Parent $Zip) '_payload') -Channel $Channel -Record $Record
    if ($LASTEXITCODE -ne 0) { Die "Export-ServerPayload.ps1 exited with $LASTEXITCODE. The lines above say why." }
}
if (-not (Test-Path -LiteralPath $Zip)) { Die "not found: $Zip. Run without -SkipBuild." }
Say ("payload {0:N1} MB" -f ((Get-Item -LiteralPath $Zip).Length / 1MB)) 'Green'

# The port the zip will really start on, read out of the zip (#1114), so a
# -SkipBuild zip packed for the other channel cannot go to this one either.
$wantPort = if ($GamePort -gt 0) { $GamePort } elseif ($IsDev) { 7787 } else { 7777 }
$zipPort = ''
# And every server file in it is the recorded build, with the record beside
# them for the installer (#1214), read out of the zip too, so a -SkipBuild zip
# made from another build cannot go either. The record in the zip is this
# repository's own, byte for byte.
$zipSums = @{}
$zipRecSum = ''
$zipWhy = ''
function Get-EntrySum($entry) {
    $zs = $entry.Open()
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash($zs) | ForEach-Object { $_.ToString('x2') })) } finally { $zs.Dispose(); $sha.Dispose() }
}
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $za = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($ze in $za.Entries) {
            # Compress-Archive under Windows PowerShell 5.1 writes the
            # separators as \, under 7 as /.
            $rel = ConvertTo-ThornswoodServerRel $ze.FullName
            if (-not $ze.Name) { continue }
            if ($rel -eq 'server-settings.json') {
                $zr = New-Object IO.StreamReader($ze.Open())
                try { $zj = $zr.ReadToEnd() | ConvertFrom-Json } finally { $zr.Dispose() }
                if ($zj.PSObject.Properties['port']) { $zipPort = [string]$zj.port }
            }
            elseif ($rel -eq 'server-build.json') { $zipRecSum = Get-EntrySum $ze }
            elseif (Test-ThornswoodServerForkFile $rel) { $zipSums[$rel] = Get-EntrySum $ze }
        }
    } finally { $za.Dispose() }
} catch { $zipWhy = $_.Exception.Message }
if ($zipPort -ne [string]$wantPort) {
    Die ("the payload's server-settings.json starts the server on port " + $(if ($zipPort) { $zipPort } else { 'nothing it says' }) +
         ", and the $Channel server is $wantPort. Nothing was sent. Run it again without -SkipBuild." + $(if ($zipWhy) { " ($zipWhy)" } else { '' }))
}
Say ("payload starts the $Channel server on port $wantPort") 'Green'
$recObj = $null
try { $recObj = [IO.File]::ReadAllText($Record) | ConvertFrom-Json } catch { }
if (-not $recObj -or -not $recObj.sha256) { Die "$Record cannot be read or names no sha256, so nothing says which build is to go. Nothing was sent." }
$zipBuild = @(Get-ThornswoodServerBuildProblems $recObj $zipSums 'the payload' $Record)
if ($zipBuild.Count) {
    Say 'the payload''s server files are not the recorded build:' 'Red'
    foreach ($w in $zipBuild) { Say "  $w" 'Red' }
    Die ('It is not the recorded build, so nothing was sent. Rebuild the payload from the recorded build, or record this one with .\scripts\release\New-ServerBuildRecord.ps1 and commit that.' +
         $(if ($zipWhy) { " ($zipWhy)" } else { '' }))
}
if ($zipRecSum -ne (Get-FileHash -LiteralPath $Record -Algorithm SHA256).Hash.ToLowerInvariant()) {
    Die ("the payload carries " + $(if ($zipRecSum) { "a server-build.json that is not $Record" } else { 'no server-build.json' }) +
         ", so the installer could not hold the server files to the record. Nothing was sent. Run it again without -SkipBuild.")
}
Say ("payload server files are the recorded build of " + ([string]$recObj.source.commit).Substring(0, 8) + ", " + $zipSums.Count + " files, and it carries the record") 'Green'

# ------------------------------------------------------------ no stop here ---
# This used to stop the server here, before anything was copied, so a copy
# that failed or a payload the installer refused left it down. Issue #446.
# The installer stops it now, by its own folder and port, and only once the
# new folder has checked out beside the old one.

Head 'Copying'
Say 'this is the slow part, a few minutes on a first run; the server keeps running' 'DarkGray'
Invoke-ThornswoodNative { & scp @ssh $Zip "${target}:C:/thornswood-server.zip" }
if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE. The server up there was not touched." }
Invoke-ThornswoodNative { & scp @ssh $installer "${target}:C:/Install-ThornswoodServer.ps1" }
if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE. The server up there was not touched." }
Invoke-ThornswoodNative { & scp @ssh $rollLog "${target}:C:/Roll-Log.ps1" }
if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE. The server up there was not touched." }
Invoke-ThornswoodNative { & scp @ssh $settingsLib "${target}:C:/ServerSettings.ps1" }
if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE. The server up there was not touched." }
Invoke-ThornswoodNative { & scp @ssh $buildLib "${target}:C:/ServerBuild.ps1" }
if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE. The server up there was not touched." }
Say 'copied' 'Green'

Head 'Installing'
# The zip's hash as it left here, for the installer to hold the copy up there to.
$zipSum = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash
$instArgs = "-Zip C:\thornswood-server.zip -Root '$VpsRoot' -TaskName '$TaskName' -StartNow -ZipSha256 $zipSum -Wait $Wait"
if ($RequirePass) {
    Say "the installer sets the join pass hold $RequirePass, as asked" 'Yellow'
    $instArgs += " -RequirePass $RequirePass"
}
if ($FreshWorld) {
    # Not deleted any more: the installer starts the new server with no world
    # and leaves the old one in the previous folder beside the root.
    Say 'starting with no world, as asked; the old one stays in the previous folder' 'Yellow'
    $instArgs += ' -FreshWorld'
}
Invoke-Installer $instArgs

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

  ONLY THE DOOR, AND ASKING FOR THE DEV LIST (#964). This was
  Copy-Item -LiteralPath (Join-Path $live '*'), and -LiteralPath reads the *
  as a file name, so it never copied anything: the count it printed was what
  dev already held. Copying the whole folder would have been wrong anyway. It
  holds the dev server's own door.log, characters.json, property.json,
  farm-claims.json, take-limit.json, mod-settings.json and online-names.json,
  which belong to the dev world, and a door.json with the live address, which
  gives the dev door the live list. The dev door asks
  https://thornswood.net/dev, whose list is only the people the dev build is
  for (docs\SYSTEM.md, "The door"); on 28 Sep that took the dev list from 46
  to 28, which is right.

  So now: door.json is live's key and join pass key with the address ending
  in /dev, so a rotated key still reaches dev and the list stays the dev one.
  allowed.json is copied only when dev has none, so the Owner has commands
  on a fresh dev root until its door fetches its own. Nothing else is touched.

  NOTHING TO CARRY STOPS THE PUBLISH (#1336). A live root with no private
  folder, no door.json, one that does not read, or one without the address,
  the key or the join pass key used to be a line in green and a publish that
  went on to say it was done, with the dev door still on whatever key it had
  before the live one was rotated. Now the dev door is left as it was, the
  script says which of those it was and ends DOOR NOT CARRIED, and the
  publish stops there with exit 1. The dev server it installed is up; its
  door is what was not done. Only names are said, never a value.
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
# What the dev door needs from live, each named when it is not there, and
# nothing on dev touched then (#1336). Names only: no value is printed.
$liveDoor = Join-Path $live 'door.json'
$d = $null
$why = ''
if (-not (Test-Path -LiteralPath $live)) { $why = 'the live server has no private folder' }
elseif (-not (Test-Path -LiteralPath $liveDoor)) { $why = 'the live server has no door.json' }
else {
    try { $d = Get-Content -LiteralPath $liveDoor -Raw | ConvertFrom-Json } catch { $why = 'the live door.json could not be read' }
    if (-not $why -and $null -eq $d) { $why = 'the live door.json is empty' }
    if (-not $why) {
        $lack = @()
        foreach ($k in 'site', 'key', 'passKey') { if (-not [string]$d.$k) { $lack += $k } }
        if ($lack.Count) { $why = 'the live door.json has no ' + ($lack -join ' and no ') }
    }
}
if ($why) {
    $why + ', so the dev door was left as it was'
    'DOOR NOT CARRIED'
} else {
    New-Item -ItemType Directory -Path $dev -Force | Out-Null
    $site = ([string]$d.site).TrimEnd('/')
    if ($site -notmatch '/dev$') { $site = $site + '/dev' }
    $d | Add-Member -NotePropertyName site -NotePropertyValue $site -Force
    [IO.File]::WriteAllText((Join-Path $dev 'door.json'), ($d | ConvertTo-Json),
        (New-Object Text.UTF8Encoding($false)))
    "dev door.json has the live key and join pass key and asks $site/api/allowed"
    $devList = Join-Path $dev 'allowed.json'
    if (-not (Test-Path -LiteralPath $devList) -and (Test-Path -LiteralPath (Join-Path $live 'allowed.json'))) {
        Copy-Item -LiteralPath (Join-Path $live 'allowed.json') -Destination $devList -Force
        'dev had no allowed.json, so it starts from the live one until its door fetches the dev list'
    }
    'DOOR CARRIED'
}
'@
    $seed = $seed.Replace('@@DEVROOT@@', $VpsRoot.TrimEnd('\'))
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($seed))
    $out = @(Invoke-ThornswoodNative { & ssh @ssh $target "powershell -NoProfile -EncodedCommand $enc" } | ForEach-Object { "$_".Trim() })
    $carried = $out -contains 'DOOR CARRIED'
    foreach ($line in $out) { Say "  $line" $(if ($carried) { 'Green' } else { 'Red' }) }
    if (-not $carried) {
        Die ("the dev server is installed and answering, but its door was not given the live server's keys, so a rotated key does not reach it. " +
             "The line above says what was missing on live. Put it right there (.\scripts\ops\Set-Door.ps1 -Connect writes the live door.json), then publish to dev again.")
    }
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
# down on our side of the fence. -GamePort and -ResourcesPort are the
# harnesses' (see the parameters); a person shipping passes neither.
$GamePort = $wantPort
$ResPort  = if ($ResourcesPort -gt 0) { $ResourcesPort } elseif ($GamePort -eq 7777) { 3000 } else { $GamePort + 1 }

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
    Invoke-ThornswoodNative { & ssh @ssh $target "powershell -NoProfile -Command `"if (Test-Path '$VpsRoot\server.log') { Get-Content '$VpsRoot\server.log' -Tail 40 } else { 'server.log is not there, so node never started. Check that node is on the machine PATH up there.' }`"" }

    Write-Host ''
    Say 'If that log is empty or says nothing useful, the other candidate is the' 'Yellow'
    Say 'firewall. The server can be up and still unreachable from here:' 'Yellow'
    Say "    ssh $target `"powershell -NoProfile -Command Get-NetFirewallRule -DisplayName '*Thornswood*' ^| Format-Table DisplayName,Enabled,Direction`"" 'DarkGray'
    # The box said it answers on its own ports, so the new server stays: this
    # is the network or the firewall, and the previous folder would not change it.
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
    exit 1
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
