<#
  Setup-Thornswood.ps1

  Puts Thornswood on this machine. It does not put the game folder Thornswood
  plays out of on it. That is Root\Game, and the launcher builds it itself the
  first time it opens, out of the Steam copy of Skyrim and what Vortex has
  deployed into it, most of it as hard links so the collection is not on the
  disk twice (launcher\app\OwnGame.cs).

  Two shapes, decided by a collection.txt the build leaves in the payload.
  With it, this script lays the launcher down under -Root and makes no copy of
  the base game: the payload is built with the collection's files left out,
  and Bethesda's archives are already on the disk. Where Thornswood's own
  content goes is the person's choice in the setup window (#1226, Patrick,
  29 Sep):
    - Thornswood's own folder chosen (-MakeOwnGame): into Root\Profile\Payload.
      Nothing at all is written into the Steam copy; the launcher makes
      Root\Game from the Steam copy's game, what Vortex deployed and Payload,
      and removes Payload.
    - Not chosen: where Vortex deploys the collection, which is the Steam
      copy, with a list of what it wrote there so an uninstall, or turning the
      own folder on later, can take it back out again.
  Without collection.txt, the old behaviour: a standalone copy under -Root
  built out of the Steam one, which is then only ever read.

  A second run over a folder the launcher already made (Root\Game, with
  Profile\OwnGame\files.txt beside it) does not park that folder. It writes
  Thornswood's own files into it. A file there that is a hard link loses
  that name first, so the write does not go through to the other name.

  Bethesda's own files are never renamed or deleted either way.
#>
[CmdletBinding()]
param(
    [string]$Root = 'C:\Thornswood',
    [string]$SteamGamePath,
    [switch]$SkipDowngrade,
    [switch]$MovePayload,
    # Finishes without opening the launcher. For testing the install itself.
    [switch]$NoOpen,
    # Run by the setup window (Bootstrap.cs) with no console of its own
    # (issue #889). Nothing waits on Enter; a stop exits 1 and the window shows
    # it; the one question left, the Steam depots, goes to the window as an
    # ASK line and the answer comes back on standard input.
    [switch]$NonInteractive,
    # The setup window's own folder card (issue #906). Ticked, the launcher
    # makes Thornswood's own Skyrim folder without asking once Vortex has
    # deployed: MakeOwnGame in config.json. Left out, the launcher asks, as it
    # always has. Only a collection install has a folder to make.
    [switch]$MakeOwnGame,
    # Choose Vortex's folder, from the same card: saved as VortexGame in
    # config.json, as the launcher's Settings button saves it.
    [string]$VortexGame
)


# The launcher, Thornswood.exe in the launcher folder.
function Get-LauncherExe([string]$dir) {
    return (Join-Path $dir 'Thornswood.exe')
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TARGET_EXE_BYTES = 37157144          # 1.6.1170

# Out here rather than beside the downgrade step. A function declared
# inside an if branch only exists when that branch runs, and a collection
# install skips that whole half while the checks at the end still call it.
# $ExeDir is the game the build is read from: the game folder, except with
# Thornswood's own folder chosen, where the payload goes to Profile\Payload
# and the game it will be made from is the Steam copy (#1226).
function Get-ExeBytes { $p = Join-Path $ExeDir 'SkyrimSE.exe'; if (Test-Path $p) { (Get-Item $p).Length } else { 0 } }
$AppId  = '489830'
$Depots = [ordered]@{
    '489831' = '8442952117333549665'
    '489832' = '8042843504692938467'
    '489833' = '1914580699073641964'
}

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

# Every robocopy in this script goes through here (#2201). Robocopy's exit
# code is a set of flags, not a plain error: 0 to 7 mean it copied, skipped or
# found extras, and 8 or more mean some file or folder could not be copied.
# Ignoring that left a half copied game folder that looked finished. 0 to 7
# carry on and the code comes back; 8 and above stop, naming both folders.
function Invoke-CheckedRobocopy([string]$From, [string]$To, [string[]]$Flags) {
    & robocopy $From $To @Flags | Out-Null
    $code = $LASTEXITCODE
    if ($code -ge 8) {
        Die ("robocopy could not copy " + $From + " to " + $To + " (robocopy code " + $code + "). " +
             "Check the disk has room and nothing has those files open, then run this again.")
    }
    return $code
}

# Robocopy run with its mouth shut, and one line of our own that counts.
#
# It used to run with the file list on, deliberately, so somebody could see it
# working. With /MT:16 that is sixteen threads writing to one console at once,
# so what a person actually saw was thousands of half overwritten paths and
# *EXTRA File with byte counts wrapped through each other. On an unsigned
# installer that Windows has already warned about, a wall of scrolling paths
# is what malware looks like, and it is the last thing somebody sees before
# deciding whether to trust this.
function Copy-Quietly($from, $to, $label, [switch]$Move) {
    # The call operator rather than Start-Process, because these paths contain
    # "Program Files (x86)" and quoting an argument array through Start-Process
    # is the kind of thing that works on one machine and not the next.
    $flags = @('/E', '/R:1', '/W:1', '/MT:16',
               '/NFL', '/NDL', '/NC', '/NS', '/NP', '/NJH', '/NJS')
    if ($Move) { $flags += '/MOVE' }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $code = Invoke-CheckedRobocopy $from $to $flags
    Write-Host ("  {0}, {1:mm\:ss}" -f $label, $clock.Elapsed) -ForegroundColor DarkGray
    return $code
}
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; if (-not $NonInteractive) { [void](Read-Host 'Enter to exit') }; exit 1 }

# A question for whoever is at the screen. From the setup window there is no
# console to type into, so the question goes out as one ASK line, the window
# puts it up as an OK or Cancel box and writes ok or no back. True means go on.
function Ask($m) {
    Write-Host ('THORNSWOOD-ASK ' + $m)
    # Letters only: whatever writes the answer may put a byte order mark or a
    # carriage return round it. No answer at all, the input shut, is a no.
    $answer = [Console]::In.ReadLine()
    return (("$answer" -replace '[^a-z]', '') -eq 'ok')
}
if ($NonInteractive) {
    # Anything else that ever reads the keyboard stops with a reason, rather
    # than waiting on a console nobody can see.
    function Read-Host { Die ('Setup stopped at a question the setup window cannot ask: ' + ($args -join ' ') + '. Run Install.bat in ' + $Here + ' to answer it there.') }
}

$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload = Join-Path $Here 'payload'
$GameDir    = Join-Path $Root 'Game'
$ProfileDir = Join-Path $Root 'Profile'
$LaunchDir  = Join-Path $Root 'Launcher'

Write-Host ''
Write-Host '  THORNSWOOD' -ForegroundColor White
Write-Host '  Setup' -ForegroundColor DarkGray

if (-not (Test-Path $Payload)) { Die "The 'payload' folder is missing. If you extracted this by hand, extract the whole archive and run Install.bat from the extracted folder." }

# ------------------------------------------------------------- agreements
# The setup window locks Install until the age box and the three agreement
# boxes are ticked, and writes Profile\accepted.json before it starts this
# script (issue #1009). Setup.bat and Install.bat run this script by hand from
# an unpacked payload, and until #1018 that installed with none of the four
# asked. So:
#   - from the setup window (-NonInteractive) the note must already be there,
#     or nothing is installed: a setup program that did not ask is an old one;
#   - by hand, the same four questions are asked here, all four must be yes,
#     and the same Profile\accepted.json is written.
# Before anything is written anywhere else. tests\test-setup-by-hand-agreements.ps1
# holds it; the wording is the window's (installer\setup\Bootstrap.cs).
$AcceptedFile = Join-Path $ProfileDir 'accepted.json'
$AgreePages = [ordered]@{
    terms   = 'I have read and accept the Terms and Conditions'
    privacy = 'I have read and accept the Privacy Policy'
    rules   = 'I have read and agree to the Rules'
}
if ($NonInteractive) {
    if (-not (Test-Path -LiteralPath $AcceptedFile)) {
        Die ('Setup found no note that you accepted the terms, the privacy policy and the rules, so nothing was installed. ' +
             'Download the setup again from https://thornswood.net and run it, or run Install.bat in ' + $Here + ' to answer them there.')
    }
} else {
    Head 'Before it installs'
    Say '  Setup needs a yes to each of these four. Type yes and press Enter for each.'
    $asks = @(@{ Say = 'I am 18 or over. Thornswood is an adult server.'; Page = '' })
    foreach ($p in $AgreePages.Keys) { $asks += @{ Say = $AgreePages[$p]; Page = "https://thornswood.net/$p" } }
    foreach ($a in $asks) {
        Write-Host ''
        Say ('  ' + $a.Say) 'White'
        if ($a.Page) { Say ('  Read it at ' + $a.Page) 'DarkGray' }
        $answer = Read-Host '  yes or no'
        # Letters only, as Ask does: a byte order mark or a stray space round
        # the answer is not a no.
        if (("$answer" -replace '[^A-Za-z]', '') -notmatch '^(?i)(y|yes)$') {
            Die 'Setup installs only once all four are a yes. Nothing was installed.'
        }
    }

    # The same record the setup window writes: when, which pages, and a
    # SHA-256 of each page's text as https://thornswood.net/api/page/<name>
    # serves it now, empty when the site does not answer. Nothing about the
    # person or the machine. A note that cannot be written stops the install,
    # because an install with no note is the thing this section closes.
    $shas = @{}
    foreach ($p in $AgreePages.Keys) {
        $shas[$p] = ''
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]3072
            $wc = New-Object Net.WebClient
            $wc.Encoding = New-Object Text.UTF8Encoding($false)
            $wc.Headers['User-Agent'] = 'ThornswoodSetup'
            $md = ($wc.DownloadString("https://thornswood.net/api/page/$p") | ConvertFrom-Json).md
            if ($null -ne $md) {
                $h = [Security.Cryptography.SHA256]::Create()
                $shas[$p] = -join ($h.ComputeHash((New-Object Text.UTF8Encoding($false)).GetBytes([string]$md)) | ForEach-Object { $_.ToString('x2') })
            }
        } catch { $shas[$p] = '' }
    }
    $pages = [ordered]@{}
    foreach ($p in $AgreePages.Keys) { $pages[$p] = [ordered]@{ url = "https://thornswood.net/$p"; sha256 = $shas[$p] } }
    $note = [ordered]@{
        accepted = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
        pages    = $pages
        about    = 'Answered yes in Setup-Thornswood.ps1, run by hand, before Install. sha256 is of each page''s text as ' +
                   'https://thornswood.net/api/page/<name> served it then, and is empty when the site did not answer.'
    }
    try {
        $null = New-Item -ItemType Directory -Force -Path $ProfileDir
        [IO.File]::WriteAllText($AcceptedFile, ($note | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    } catch {
        Die ('Could not note what you accepted in ' + $AcceptedFile + ': ' + $_.Exception.Message)
    }
    Say '  Noted.' 'Green'
}

# ------------------------------------------------------------- find steam
function Get-SteamRoot {
    $c = @()
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        if (Test-Path $k) {
            $i = Get-ItemProperty $k
            foreach ($n in 'SteamPath', 'InstallPath') { if ($i.PSObject.Properties[$n]) { $c += $i.$n } }
        }
    }
    $c += "${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam"
    $c | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ 'steam.exe')) } | Select-Object -First 1
}
function Get-Libraries($steam) {
    $r = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        foreach ($l in Get-Content -LiteralPath $vdf) {
            if ($l -match '^\s*"path"\s+"(.+)"') { $p = $Matches[1] -replace '\\\\', '\'; if (Test-Path -LiteralPath $p) { $r += $p } }
        }
    }
    $r | Select-Object -Unique
}

Head 'Finding Skyrim'
$steamRoot = Get-SteamRoot
# Steam's own folder is what finds Skyrim when nobody named it, and what the
# depot download needs; a Skyrim named with -SteamGamePath is found already.
if (-not $steamRoot -and -not $SteamGamePath) { Die 'Steam is not installed on this PC.' }
$libs = @(if ($steamRoot) { Get-Libraries $steamRoot })

if (-not $SteamGamePath) {
    foreach ($l in $libs) {
        $g = Join-Path $l 'steamapps\common\Skyrim Special Edition'
        if (Test-Path -LiteralPath (Join-Path $g 'SkyrimSE.exe')) { $SteamGamePath = $g; break }
    }
}
if (-not $SteamGamePath) { Die 'Skyrim Special Edition was not found in any Steam library. Install it first.' }
$SteamGamePath = (Resolve-Path -LiteralPath $SteamGamePath).Path
Say "  $SteamGamePath" 'Green'

# ---- which shape of install this is --------------------------------------
#
# A payload built with the collection's files left out cannot stand up its own
# Skyrim, because most of that Skyrim is what was left out. It goes into the
# Steam copy instead, which is where Vortex deploys the collection.
#
# The launcher settles this the same way and has to agree: Paths.Collection is
# true only when Root\Game does not exist. Build one here and the launcher
# reads its own empty profile, counts zero plugins, and reports a broken
# install over a collection that installed perfectly.
$Collection = Test-Path -LiteralPath (Join-Path $Here 'collection.txt')
# Thornswood's own folder, chosen in the setup window (#1226). Its files go to
# Profile\Payload and the Steam copy is only read. The launcher tells this
# shape by that folder (Paths.OwnFirst) and makes Root\Game from it.
#
# A folder the launcher has already made is not that first install (#1233).
# Root\Game with Profile\OwnGame\files.txt beside it is the working folder.
# Parking it as Game-old-<date> threw it aside and left the launcher to build
# another one, and the parked one stayed on the disk. This run writes the
# payload into the folder that is already there.
$madeRecord = Join-Path $ProfileDir 'OwnGame\files.txt'
$MadeOwn = $Collection -and (Test-Path -LiteralPath (Join-Path $Root 'Game')) -and (Test-Path -LiteralPath $madeRecord)
$OwnFirst = $Collection -and $MakeOwnGame -and -not $MadeOwn
$ExeDir = $GameDir

if ($Collection) {
    if ($MadeOwn) {
        $GameDir = Join-Path $Root 'Game'
        $ExeDir = $GameDir
        Say '  Thornswood''s own Skyrim folder is already here.' 'DarkGray'
        Say '  This updates Thornswood''s own files in it and does not move it.' 'DarkGray'
        Say '  Your Steam copy stays yours.' 'DarkGray'
    } elseif ($OwnFirst) {
        $GameDir = Join-Path $ProfileDir 'Payload'
        $ExeDir = $SteamGamePath
        Say '  Thornswood''s own Skyrim folder is chosen, so nothing is written into' 'DarkGray'
        Say '  this copy. The launcher makes the folder from it and from what Vortex' 'DarkGray'
        Say '  deploys into it, and your Steam copy stays yours.' 'DarkGray'
    } else {
        $GameDir = $SteamGamePath
        $ExeDir = $GameDir
        Say '  Thornswood installs into this copy. The mods come from the collection' 'DarkGray'
        Say '  in Vortex, which deploys into it too.' 'DarkGray'
    }

    # A Game folder left over from an older install is not harmless. The
    # launcher decides which Skyrim it is looking at by whether that folder
    # exists, so one sitting there sends it back to a build that now has no
    # mods in it, and the collection you just installed is never counted.
    #
    # Moved rather than deleted. It is twenty gigabytes of somebody's disk and
    # not this script's to throw away, and a rename is undone in a second if
    # any of this turns out to be wrong.
    #
    # Not a folder the launcher made. That one has Profile\OwnGame\files.txt
    # and $MadeOwn above leaves it where it is (#1233).
    if (-not $MadeOwn) {
    $oldGame = Join-Path $Root 'Game'
    if (Test-Path -LiteralPath $oldGame) {
        $parked = Join-Path $Root ('Game-old-' + (Get-Date).ToString('yyyyMMdd-HHmm'))
        Write-Host ''
        Say '  There is an old Game folder here from a previous install.' 'Yellow'
        Say '  The launcher reads that one instead of your Steam copy, so it has to' 'Yellow'
        Say '  move out of the way. Nothing is deleted.' 'Yellow'
        try {
            Move-Item -LiteralPath $oldGame -Destination $parked -Force -ErrorAction Stop
            Say "  moved to $parked" 'Green'
            Say '  Delete that yourself once Thornswood starts properly.' 'DarkGray'
        } catch {
            Write-Host ''
            Say "  It would not move: $($_.Exception.Message)" 'Red'
            Say '  Close Skyrim, Vortex and the launcher, then run this again.' 'Red'
            Die 'The old Game folder is in the way and the launcher will read it instead.'
        }
        Write-Host ''
    }
    }

    # No downgrade in this shape: the exe belongs to Steam and is not ours to
    # replace, and the launcher never replaces it either (#1218). Say so now
    # rather than at the end, after twenty minutes.
    $exeNow = Join-Path $SteamGamePath 'SkyrimSE.exe'
    $bytesNow = if (Test-Path $exeNow) { (Get-Item $exeNow).Length } else { 0 }
    if ($bytesNow -ne $TARGET_EXE_BYTES) {
        Write-Host ''
        Say '  This Skyrim is not build 1.6.1170, which is the one the server runs.' 'Yellow'
        Say '  Thornswood installs anyway. Open the launcher and press Downgrade:' 'Yellow'
        Say '  Steam downloads 1.6.1170''s files and Thornswood makes its own game' 'Yellow'
        Say '  folder from them. Your Steam copy stays on the build it is on.' 'Yellow'
        Write-Host ''
    }
} else {
    Say '  This folder will be read from only.' 'DarkGray'
}

# Skyrim does not always let go. A crash, an Alt-F4, or one of the multiplayer
# client's browser helpers leaves a process behind with no window on screen,
# so telling someone to close a game they cannot see is a dead end. Close it
# here instead. This runs standalone inside the payload, so it does not share
# the repo's Close-Launcher.ps1 and carries its own copy.
function Stop-AnySkyrim {
    $found = @()
    foreach ($n in 'SkyrimSE', 'skse64_loader') {
        foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) { $found += $p }
    }
    if ($found.Count -eq 0) { return $true }

    $names = ($found | ForEach-Object { $_.ProcessName } | Sort-Object -Unique) -join ', '
    Say "  Skyrim is still open ($names). Closing it." 'Yellow'
    foreach ($p in $found) { try { $null = $p.CloseMainWindow() } catch { } }
    for ($i = 0; $i -lt 24; $i++) {
        Start-Sleep -Milliseconds 250
        if (-not ($found | Where-Object { -not $_.HasExited })) { break }
    }
    foreach ($p in $found) { try { if (-not $p.HasExited) { $p.Kill() } } catch { } }

    # A killed process can sit in the table for a moment after it is gone, so
    # this waits rather than giving up on the first look.
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Milliseconds 250
        $left = @()
        foreach ($n in 'SkyrimSE', 'skse64_loader') {
            foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) { $left += $p }
        }
        if ($left.Count -eq 0) { Say '  Closed.' 'Green'; return $true }
    }
    return $false
}

if (-not (Stop-AnySkyrim)) {
    Die 'Skyrim would not close. Restart your PC, then run this again.'
}

# ------------------------------------------------------------- space
# The setup program unpacks onto this same drive so the final step is a move
# rather than another copy, which makes the peak the unpacked mods plus the
# copy of Skyrim, both at once.
# A collection install writes the launcher, Thornswood's own content and the
# script extender, and nothing else: the fifteen gigabytes of Bethesda archives
# are already on the disk and stay where they are. Asking for 32 GB would turn
# away people who have room for everything this actually does.
$needGB = if ($Collection) { 6 } else { 32 }
$dl = (Split-Path -Qualifier $Root) -replace ':', ''
$freeGB = [math]::Round((Get-PSDrive $dl).Free / 1GB, 1)
Say "  Installing to $Root"
Say "  $freeGB GB free on $dl`:"
if ($freeGB -lt $needGB) { Die "You need about $needGB GB free on $dl`:. Close this, run the setup program again and pick a different drive." }
if ($Collection -and -not $OwnFirst -and -not $MadeOwn) {
    # The mods land on whichever drive Steam keeps Skyrim on, which is not
    # necessarily the one just checked. With the own folder chosen they land
    # under -Root, which is the drive just checked.
    $sd = (Split-Path -Qualifier $SteamGamePath) -replace ':', ''
    if ($sd -and $sd -ne $dl) {
        $sf = [math]::Round((Get-PSDrive $sd).Free / 1GB, 1)
        Say "  $sf GB free on $sd`:, where Steam keeps Skyrim"
        if ($sf -lt 3) { Die "Only $sf GB free on $sd`:, and Thornswood's own content needs about 3 GB there." }
    }
}

# ------------------------------------------------------------- vanilla copy
#
# Only when Thornswood is building a Skyrim of its own. Copying Bethesda's
# files into the Steam folder they are already in would be fifteen gigabytes
# of writing a file over itself.
if ($Collection) {
    Head 'The base game'
    if ($MadeOwn) { Say '  Already made. Thornswood''s own files are updated in it.' 'DarkGray' }
    elseif ($OwnFirst) { Say '  Your Steam copy. Thornswood''s own folder is made from it by the launcher.' 'DarkGray' }
    else { Say '  Already here, this is your Steam copy.' 'DarkGray' }
    $null = New-Item -ItemType Directory -Force -Path $ProfileDir, $LaunchDir
} else {

Head 'Copying the base game'
$null = New-Item -ItemType Directory -Force -Path $GameDir, (Join-Path $GameDir 'Data'), $ProfileDir, $LaunchDir

$rootFiles = @('SkyrimSE.exe', 'SkyrimSELauncher.exe', 'steam_api64.dll', 'bink2w64.dll',
               'Skyrim_Default.ini', 'High.ini', 'Low.ini', 'Medium.ini', 'Ultra.ini',
               'Skyrim.ccc', 'installscript.vdf')
foreach ($f in $rootFiles) {
    $s = Join-Path $SteamGamePath $f
    if (Test-Path $s) { Copy-Item $s $GameDir -Force }
}
Set-Content (Join-Path $GameDir 'steam_appid.txt') $AppId -NoNewline -Encoding ASCII

$dataSrc = Join-Path $SteamGamePath 'Data'
$dataDst = Join-Path $GameDir 'Data'
$want = @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm', '_ResourcePack.esl', '_ResourcePack.bsa')
foreach ($f in $want) {
    $s = Join-Path $dataSrc $f
    if (Test-Path $s) { Copy-Item $s $dataDst -Force; Say "  $f" 'DarkGray' }
}
Say '  Archives. This is the slow part, about 15 GB.'
Say '  The window looks still while it works. That is normal.' 'DarkGray'
$rc = [Diagnostics.Stopwatch]::StartNew()
$null = Invoke-CheckedRobocopy $dataSrc $dataDst @('Skyrim - *.bsa', '/R:1', '/W:1', '/MT:8', '/NFL', '/NDL', '/NC', '/NS', '/NP', '/NJH', '/NJS')
Write-Host ("  archives copied, {0:mm\:ss}" -f $rc.Elapsed) -ForegroundColor DarkGray
if (Test-Path (Join-Path $dataSrc 'Video')) {
    $null = Invoke-CheckedRobocopy (Join-Path $dataSrc 'Video') (Join-Path $dataDst 'Video') @('/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NP', '/NJH', '/NJS')
}
$bsaCount = @(Get-ChildItem $dataDst -Filter '*.bsa' -File -EA SilentlyContinue).Count
if ($bsaCount -lt 15) { Die "Only $bsaCount archives copied. Your Steam copy looks incomplete - verify it in Steam first, then run this again." }
Say "  $bsaCount archives, 5 masters" 'Green'

# ------------------------------------------------------------- downgrade

# Steam hands over the 1.6.1170 files under the player's own account and writes
# them into Steam's download folder, so the game they have installed is left
# alone. It is the fix for a copy that is too new and for one that another mod
# setup has patched, so it lives in a function and gets called for both.
function Invoke-DepotRepair($reason) {
    if (-not $steamRoot) { Die 'Steam is not installed on this PC, so the 1.6.1170 files cannot be downloaded.' }
    Head 'Getting clean 1.6.1170 files from Steam'
    Say "  $reason"
    Say '  Steam downloads them under your own account. Your installed game is not touched.' 'DarkGray'

    $content = Join-Path $steamRoot 'steamapps\content'
    function Resolve-Depot($id) {
        foreach ($c in @((Join-Path $content "app_$AppId\depot_$id"), (Join-Path $content "$AppId\$id"),
                         (Join-Path $content "depot_$id"), (Join-Path $content $id))) {
            if (Test-Path -LiteralPath $c) { return $c }
        }
        $null
    }

    $missing = @($Depots.Keys | Where-Object { -not (Resolve-Depot $_) })
    if ($missing.Count) {
        $cmds = ($Depots.GetEnumerator() | ForEach-Object { "download_depot $AppId $($_.Key) $($_.Value)" }) -join "`r`n"
        Write-Host ''
        Say '  Run these three in the Steam console, ONE AT A TIME, waiting for each to say Done:' 'Yellow'
        Write-Host ''
        $Depots.GetEnumerator() | ForEach-Object { Write-Host "    download_depot $AppId $($_.Key) $($_.Value)" -ForegroundColor White }
        Write-Host ''
        try { Set-Clipboard $cmds; Say '  All three are on your clipboard.' 'DarkGray' } catch { }
        Say '  There is no progress bar. It just prints Done when it finishes.' 'DarkGray'
        Start-Process 'steam://open/console'
        Say '  If no console tab opens, press Win+R and run:  steam://open/console' 'DarkGray'
        Write-Host ''
        if ($NonInteractive) {
            if (-not (Ask 'Run the three download_depot lines shown in the setup window in the Steam console, one at a time, waiting for each to say Done. They are on your clipboard too. Press OK once all three have finished, or Cancel to stop.')) {
                Die 'Stopped before the Steam files were applied. Run the setup again once the three downloads have finished.'
            }
        } else {
            [void](Read-Host '  Press Enter here once all three have finished')
        }
        $missing = @($Depots.Keys | Where-Object { -not (Resolve-Depot $_) })
        if ($missing.Count) { Die ("These depots still are not downloaded: " + ($missing -join ', ')) }
    }

    foreach ($id in $Depots.Keys) {
        $d = Resolve-Depot $id
        Say "  Applying depot $id..."
        $null = Invoke-CheckedRobocopy $d $GameDir @('/E', '/R:1', '/W:1', '/MT:8', '/NFL', '/NDL', '/NP', '/NJH', '/NJS')
    }

    Say '  Applied' 'Green'
}

if ((Get-ExeBytes) -ne $TARGET_EXE_BYTES -and -not $SkipDowngrade) {
    Invoke-DepotRepair 'Your Steam copy is a newer build. The server runs 1.6.1170, so this copy has to match.'
    if ((Get-ExeBytes) -ne $TARGET_EXE_BYTES) { Die "The copy is still not 1.6.1170 (SkyrimSE.exe is $(Get-ExeBytes) bytes)." }
    Say '  1.6.1170' 'Green'
} else {
    Say "  Already 1.6.1170" 'Green'
}

# ------------------------------------------------------------- tamper check
# The size check above only proves the build number. Multiplayer setups like
# another server and another server install into the Steam folder, and a patched
# loader of exactly the right size would sail straight past it and end up in
# this copy. So the three files that get patched are matched by content against
# the ones this package was built from.
# Get-FileHash lives in a module that is not always on PSModulePath, and a
# script started with -NoProfile can find itself without it. .NET is always
# there, so the hashing goes straight to it.
function Get-Sha256([string]$path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fs = [IO.File]::OpenRead($path)
        try { return ([BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-', '').ToLower() }
        finally { $fs.Close() }
    }
    finally { $sha.Dispose() }
}

$vanillaList = Join-Path $Here 'vanilla.json'
if (Test-Path $vanillaList) {
    Head 'Checking the files that came from Steam'
    $want = Get-Content $vanillaList -Raw | ConvertFrom-Json

    function Get-Mismatched($doc) {
        $out = @()
        foreach ($prop in $doc.PSObject.Properties) {
            $f = Join-Path $GameDir $prop.Name
            if (-not (Test-Path -LiteralPath $f)) { continue }
            if ((Get-Sha256 $f) -ne ([string]$prop.Value).ToLower()) { $out += $prop.Name }
        }
        return $out
    }

    $off = @(Get-Mismatched $want)
    if ($off -contains 'SkyrimSE.exe' -and -not $SkipDowngrade) {
        Invoke-DepotRepair 'Your Steam copy of Skyrim has been modified by another mod setup, so the game itself is being replaced with clean files.'
        $off = @(Get-Mismatched $want)
    }

    if ($off -contains 'SkyrimSE.exe') {
        Die 'SkyrimSE.exe does not match a clean 1.6.1170 build even after the depot download. Send a screenshot of this to the Discord.'
    }
    if ($off.Count) {
        Say ("  " + ($off -join ', ') + " differ from the ones this package was built with.") 'Yellow'
        Say '  Those are Steam support files rather than game data, so this carries on.' 'DarkGray'
        Say '  If the game refuses to start, run Steam, verify Skyrim, and install this again.' 'DarkGray'
    } else {
        Say '  Clean' 'Green'
    }
}

# ------------------------------------------------------------- creation club
Head 'Removing Creation Club content'
$ccGone = 0
foreach ($f in (Get-ChildItem $dataDst -Filter 'cc*' -File -EA SilentlyContinue)) {
    if ($f.Extension -in '.esl', '.esm', '.esp', '.bsa') { Remove-Item $f.FullName -Force; $ccGone++ }
}
Say "  $ccGone files removed from the copy" 'Green'

} # end of the copy-and-downgrade half, skipped for a collection install

# ------------------------------------------------------------- payload
Head 'Installing the mods'
Say '  Several thousand files, a few minutes. The window looks still while it works.'

# ---- a record of what we put in somebody else's game ----------------------
#
# A collection install writes into the Steam copy of Skyrim. The uninstaller
# only ever deletes paths under Root, on purpose, because that folder is the
# person's own game and Vortex's hardlinks are in it. So without this list
# Thornswood's own content stayed behind forever and an uninstall left the
# folder bigger than it found it.
#
# Written before the copy, because -MovePayload empties the source. Not with
# Thornswood's own folder chosen: nothing goes into the Steam copy then, and a
# list an earlier install left stays as it is, because it is what the
# launcher takes back out of the Steam copy once the folder is made
# (OwnGame.CleanSteamCopy).
if ($Collection -and -not $OwnFirst -and -not $MadeOwn) {
    $listed = @()
    $pfx = $Payload.TrimEnd('\') + '\'
    foreach ($f in (Get-ChildItem -LiteralPath $Payload -Recurse -File -Force -EA SilentlyContinue)) {
        $listed += $f.FullName.Substring($pfx.Length)
    }
    if ($listed.Count) {
        $null = New-Item -ItemType Directory -Force -Path $ProfileDir
        $manifest = Join-Path $ProfileDir 'installed-into-game.txt'
        [IO.File]::WriteAllLines($manifest, $listed, (New-Object Text.UTF8Encoding($false)))
        Say ("  {0:n0} files recorded, so uninstalling can take them back out" -f $listed.Count) 'DarkGray'
    }
}
# MovePayload: unpacked into a scratch folder by the setup program. Moving
# instead of copying keeps peak disk use down and leaves nothing behind.
# The else sits on the closing brace. PowerShell ends the statement at the
# newline and then fails on a stray else.
# A hard link is one file under two names. Robocopy writes into the file it
# finds, so copying over a linked name in the made folder would change the
# Steam copy or Vortex's staging as well. The name in this folder comes off
# first. The other name keeps its bytes, and the copy that follows belongs
# here alone. The launcher does the same before it writes (OwnGame.Detach).
function Remove-SharedNames([string]$from, [string]$to) {
    if (-not ('TsLinkCount' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class TsLinkCount {
    [StructLayout(LayoutKind.Sequential)]
    struct Info {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle h, out Info info);
    public static int Count(string path) {
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
            Info info;
            if (!GetFileInformationByHandle(fs.SafeFileHandle, out info)) return 1;
            return (int)info.NumberOfLinks;
        }
    }
}
'@
    }
    # Every name the payload is about to replace comes off first. A hard link
    # would take the write through to its other name. A normal file of the
    # same size and timestamp is one robocopy would leave alone, so the old
    # bytes would stay. Either way the name is gone and the copy that follows
    # is this folder's own file.
    $pfx = $from.TrimEnd('\') + '\'
    $n = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $from -Recurse -File -Force -ErrorAction SilentlyContinue)) {
        $rel = $f.FullName.Substring($pfx.Length)
        $dest = Join-Path $to $rel
        if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) { continue }
        $linked = [TsLinkCount]::Count($dest) -gt 1
        [IO.File]::SetAttributes($dest, [IO.FileAttributes]::Normal)
        [IO.File]::Delete($dest)
        if ($linked) { $n++ }
    }
    if ($n) { Say ("  {0} linked file(s) separated, so the copy does not write through them" -f $n) 'DarkGray' }
}
if ($MadeOwn) { Remove-SharedNames $Payload $GameDir }
$code = if ($MovePayload) { Copy-Quietly $Payload $GameDir 'installing the mods' -Move } else { Copy-Quietly $Payload $GameDir 'installing the mods' }
Say '  Done' 'Green'

# ------------------------------------------------------------- profile
Head 'Settings'
$pMyGames = Join-Path $ProfileDir 'MyGames'
$pLocalAD = Join-Path $ProfileDir 'LocalAppData'
$golden   = Join-Path $ProfileDir 'Default'
$null = New-Item -ItemType Directory -Force -Path $pMyGames, $pLocalAD, $golden, (Join-Path $pMyGames 'Saves')

$src = Join-Path $Here 'profile'
if (Test-Path $src) {
    Copy-Item (Join-Path $src '*') $golden -Force
    Copy-Item (Join-Path $golden '*.ini') $pMyGames -Force -EA SilentlyContinue
    Copy-Item (Join-Path $golden '*.txt') $pLocalAD -Force -EA SilentlyContinue
    $plug = Join-Path $pLocalAD 'plugins.txt'
    $n = if (Test-Path $plug) { @(Get-Content $plug | Where-Object { $_ -match '^\*' }).Count } else { 0 }
    Say "  Load order installed, $n plugins" 'Green'
} elseif ($Collection) {
    # Expected. Vortex writes the real plugins.txt into AppData and that is
    # what the launcher reads, so there is nothing for this build to lay down.
    Say '  Load order comes from Vortex, nothing to install here.' 'DarkGray'
} else { Say '  No profile folder in the archive.' 'Yellow' }

# Every pack this build already contains, so the launcher does not offer the
# whole history of the project as a pending update the moment it opens. Only
# written when there is not one already: a reinstall over an existing profile
# has a real record and this one is a snapshot from build time.
$appliedSrc = Join-Path $Here 'applied.txt'
$appliedDst = Join-Path $ProfileDir 'applied.txt'
if ((Test-Path $appliedSrc) -and -not (Test-Path $appliedDst)) {
    Copy-Item $appliedSrc $appliedDst -Force
    $na = @(Get-Content $appliedDst | Where-Object { $_.Trim() }).Count
    Say "  $na updates marked as already in this build" 'Green'
}

# Where the source of the SkyMP files is. Package-Thornswood.ps1 writes it from
# the build records. It goes into the install folder because the folder this
# runs from is the setup program's scratch copy, which the next setup deletes,
# and entry 170 on the To Do List asked for it "from inside the installed
# folder". Uninstall.cs names it among the files it removes, or the install
# folder would never come out empty.
$srcNote = Join-Path $Here 'SOURCE CODE.txt'
if (Test-Path -LiteralPath $srcNote) { Copy-Item -LiteralPath $srcNote -Destination $Root -Force }

# Full GPL / AGPL / WebView2 texts Package staged beside SOURCE CODE.txt (#421).
foreach ($lic in @('GPL-3.0.txt', 'AGPL-3.0.txt', 'WebView2-LICENSE.txt')) {
    $from = Join-Path $Here $lic
    if (Test-Path -LiteralPath $from) { Copy-Item -LiteralPath $from -Destination $Root -Force }
}

$s = Join-Path $Here 'Thornswood.exe'
if (Test-Path $s) { Copy-Item $s $LaunchDir -Force }

# config.json is merged rather than copied over. The one in the archive is
# deliberately blank where the credentials go, so a straight copy would wipe a
# working install's password on every upgrade. Anything the archive does not
# name is left exactly as it was, and a blank field in the archive never
# overwrites a filled one on the disk.
$cfgFrom = Join-Path $Here 'config.json'
$cfgTo   = Join-Path $Root 'config.json'

# Thornswood's own Skyrim folder, as the setup window's card left it. The
# launcher makes the folder itself (OwnGame.Make) once Vortex has deployed, so
# all this does is answer its question in advance and name Vortex's folder.
# The same check as the launcher's OwnGame.PointAt: a Skyrim, with Vortex's
# record in it. Anything else is said and left out, never a stop, because the
# launcher's own Settings button can still set it.
$ownGame = [ordered]@{}
if ($MakeOwnGame -or $VortexGame) {
    Head "Thornswood's own Skyrim folder"
    if (-not $Collection) {
        Say '  This install already has a Game folder of its own, so there is nothing to make.' 'DarkGray'
    } else {
        if ($MakeOwnGame) {
            $ownGame['MakeOwnGame'] = $true
            Say '  On. The launcher makes it by itself once Vortex has deployed the Thornswood collection.' 'Green'
        }
        if ($VortexGame) {
            $vg = $VortexGame.Trim().Trim('"').Trim().TrimEnd('\')
            if (-not (Test-Path -LiteralPath (Join-Path $vg 'SkyrimSE.exe'))) {
                Say "  $vg has no SkyrimSE.exe in it, so it is not a Skyrim folder. Choose Vortex's folder in the launcher's Settings instead." 'Yellow'
            } elseif (-not (Test-Path -LiteralPath (Join-Path $vg 'Data\vortex.deployment.json'))) {
                Say "  Vortex has not deployed into $vg, so it was not saved. Choose Vortex's folder in the launcher's Settings instead." 'Yellow'
            } else {
                $ownGame['VortexGame'] = $vg
                Say "  Vortex's folder is set to $vg" 'Green'
            }
        }
    }
}

if ((Test-Path $cfgFrom) -or $ownGame.Count) {
    function Read-Json($p) {
        if (-not (Test-Path $p)) { return $null }
        try {
            $raw  = [IO.File]::ReadAllBytes($p)
            $skip = if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { 3 } else { 0 }
            return [Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip) | ConvertFrom-Json
        } catch { return $null }
    }
    $new = Read-Json $cfgFrom
    $old = Read-Json $cfgTo
    $out = [ordered]@{}
    if ($old) { $old.PSObject.Properties | ForEach-Object { $out[$_.Name] = $_.Value } }
    if ($new) {
        foreach ($pr in $new.PSObject.Properties) {
            if ("$($pr.Value)" -ne '' -or -not $out.Contains($pr.Name)) { $out[$pr.Name] = $pr.Value }
        }
    }
    # The card's answer is this run's, so it goes over whatever was there.
    foreach ($k in $ownGame.Keys) { $out[$k] = $ownGame[$k] }
    [IO.File]::WriteAllText($cfgTo, ($out | ConvertTo-Json -Depth 6),
        (New-Object Text.UTF8Encoding($false)))
    # Nobody but this account has any business reading it. It holds the server
    # password once the launcher has fetched one.
    try {
        $acl = Get-Acl $cfgTo
        $acl.SetAccessRuleProtection($true, $false)
        $acl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            [Security.Principal.WindowsIdentity]::GetCurrent().Name,
            'FullControl','Allow')))
        Set-Acl $cfgTo $acl
    } catch { }
}

$lexe = Get-LauncherExe $LaunchDir
if (Test-Path $lexe) {
    $ws = New-Object -ComObject WScript.Shell
    foreach ($dest in @([Environment]::GetFolderPath('Desktop'), $Root)) {
        $sc = $ws.CreateShortcut((Join-Path $dest 'Thornswood.lnk'))
        $sc.TargetPath       = $lexe
        $sc.WorkingDirectory = $LaunchDir
        $sc.IconLocation     = ($lexe + ',0')
        $sc.Description      = 'ThornsWood'
        $sc.Save()
    }
    Say '  Shortcut on your desktop' 'Green'

# Windows keeps the bitmap it once drew for a shortcut and goes on showing it
# long after the icon inside the exe changed. Asking Explorer to rebuild that
# cache is the difference between a new icon and an argument about whether the
# build worked.
try {
    $ie4 = Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
    if (Test-Path $ie4) {
        & $ie4 -show 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { & $ie4 -ClearIconCache 2>&1 | Out-Null }
        Say '  Icon cache asked to refresh' 'DarkGray'
    }
} catch { }

} else {
    Say '  Thornswood.exe was not in the package.' 'Yellow'
}

# ------------------------------------------------------------- verify
Head 'Checking'
# Multiplayer used to look for the old multiplayer mod's client exe under Data.
# SkyMP has no client exe of its own and has not had one for a long time: the
# client is MpClientPlugin.dll under SKSE\Plugins, which is what the launcher
# itself checks. So this reported a missing multiplayer client on an install
# where it was sitting there correctly.
#
# Load order is the same shape of mistake. A collection install does not use
# the profile folder under Root at all, because Vortex writes the real
# plugins.txt into the person's own AppData, which is exactly what the launcher
# reads once there is no Game folder to look at instead.
$winLocalAD = Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition'
# The script extender and the address library are read where the game is:
# with the own folder chosen that is the Steam copy Vortex deploys into, and
# the multiplayer client is Thornswood's own, in Profile\Payload.
$checks = [ordered]@{
    'Game 1.6.1170'    = ((Get-ExeBytes) -eq $TARGET_EXE_BYTES)
    'Script Extender'  = (Test-Path (Join-Path $ExeDir 'skse64_1_6_1170.dll'))
    'Multiplayer'      = (Test-Path (Join-Path $GameDir 'Data\SKSE\Plugins\MpClientPlugin.dll'))
    'Address library'  = (Test-Path (Join-Path $ExeDir 'Data\SKSE\Plugins\versionlib-1-6-1170-0.bin'))
    'Load order'       = $(if ($Collection) { Test-Path (Join-Path $winLocalAD 'plugins.txt') }
                           else            { Test-Path (Join-Path $pLocalAD 'plugins.txt') })
    'Launcher'         = (Test-Path (Get-LauncherExe $LaunchDir))
}
# Two of these are not ours to install under the collection method.
#
# The script extender and the address library both come out of the collection,
# which Vortex installs in the NEXT step, after this window closes. Counting
# them as failures here tells somebody their install is broken at the exact
# moment they are doing it in the right order, and the line underneath sends
# them to staff with a screenshot of a working install. That is a support
# ticket the installer created by itself.
#
# Checked against the collection's own manifest rather than guessed: address
# library is "All in one (all game versions)", Nexus 32444, and skse is
# deployed by Vortex into the game root the same way.
$fromCollection = @('Script Extender', 'Address library')

$bad = 0
$later = 0
foreach ($k in $checks.Keys) {
    if ($checks[$k]) {
        Say "  [ok]   $k" 'Green'
    } elseif ($Collection -and ($fromCollection -contains $k)) {
        Say "  [next] $k  the collection installs this" 'Yellow'
        $later++
    } elseif ($Collection -and $k -eq 'Game 1.6.1170') {
        # A wrong build is not a failed install: the launcher's Downgrade
        # button fetches 1.6.1170 for Thornswood's own folder and leaves the
        # Steam copy as it is (#1218). Counting it as a miss
        # kept the window shut on a screenshot and never opened the launcher
        # that fixes it. So count it as next and let the launcher open.
        Say "  [next] $k  the launcher's Downgrade button fixes this" 'Yellow'
        $later++
    } else {
        Say "  [MISS] $k" 'Red'
        $bad++
    }
}

# ---------------------------------------------------------------- open it
# Ending an installer by telling somebody to go and find an icon is one more
# step that can be got wrong, on the one screen where somebody is least sure
# what they are doing. It opens itself instead. Started from this console it
# is allowed to take the foreground, which Windows does not grant a process
# started from the background, so this is the right place to do it from.
function Open-Launcher([string]$exe) {
    if (-not (Test-Path $exe)) {
        Say '  It is not where it should be. Open Thornswood from your desktop.' 'Yellow'
        return
    }
    try {
        $p = Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) -PassThru
    } catch {
        Say ('  Could not open it: ' + $_.Exception.Message) 'Yellow'
        Say '  Open Thornswood from your desktop instead.' 'Yellow'
        return
    }
    try {
        Add-Type -Namespace Ts -Name Fg -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
'@ -ErrorAction Stop
    } catch { }
    # A WPF process has no window for the first moment of its life, and asking
    # for the handle before it does gets a zero that never changes afterwards.
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Milliseconds 250
        try { $p.Refresh() } catch { break }
        if ($p.HasExited) { break }
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { break }
    }
    try {
        if (-not $p.HasExited -and $p.MainWindowHandle -ne [IntPtr]::Zero) {
            [void][Ts.Fg]::ShowWindow($p.MainWindowHandle, 9)   # SW_RESTORE
            [void][Ts.Fg]::SetForegroundWindow($p.MainWindowHandle)
        }
    } catch { }
}

Write-Host ''
if ($bad) {
    Say "$bad checks failed. Send staff a screenshot of this window in the Discord." 'Red'
    Write-Host ''
    # Left open on purpose. This is the window somebody has to photograph.
    # From the setup window it is that window which stays open, on exit 1.
    if ($NonInteractive) { exit 1 } else { [void](Read-Host 'Enter to close') }
} else {
    if ($later) {
        Say "Installed. $later thing$(if ($later -eq 1) { '' } else { 's' }) still to come from the collection, which is the next step." 'Green'
    } else {
        Say 'Installed.' 'Green'
    }
    Write-Host ''
    Say 'Make a character named after yourself, save once, then connect.' 'Gray'
    Write-Host ''
    if ($Collection) {
        Say 'The launcher opens on the collection if your mods are not in yet.' 'DarkGray'
        Say 'Install it in Vortex and switch to the profile it makes. Without' 'DarkGray'
        Say 'that you have a launcher and no mods.' 'DarkGray'
        if ($ownGame.Contains('MakeOwnGame')) {
            Say "Once Vortex has deployed it, the launcher makes Thornswood's own" 'DarkGray'
            Say 'Skyrim folder by itself and restarts.' 'DarkGray'
        }
        if ($OwnFirst -or $MadeOwn) {
            Say 'Nothing was written into your Steam copy of Skyrim.' 'DarkGray'
        }
        if ($MadeOwn) {
            Say 'Thornswood''s own folder was updated in place.' 'DarkGray'
        }
    } else {
        Say 'Your Steam copy of Skyrim was not modified.' 'DarkGray'
    }
    Write-Host ''
    if ($NoOpen) {
        Say 'Open "Thornswood" on your desktop and press PLAY.' 'White'
        Write-Host ''
        if (-not $NonInteractive) { [void](Read-Host 'Enter to close') }
    } else {
        Say 'Opening Thornswood now.' 'White'
        Open-Launcher (Get-LauncherExe $LaunchDir)
    }
}
