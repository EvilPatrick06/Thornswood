<#
  Ship-Rules.ps1

  The one list of what never leaves a machine inside a Thornswood pack or
  installer. Publish-Update.ps1 (packs) and Package-Thornswood.ps1 (the
  installer) both dot-source this file, so the two can never disagree about
  which files are the build's and which are one machine's, another server's,
  or somebody's sign in.

  It had to become one file the night the installer turned out to carry
  Data\Platform\PluginsNoLoad\auth-data-no-load.js, the SkyMP client's saved
  sign in token from the machine it was built on. Publish-Update had grown a
  careful list of what to leave out; Package-Thornswood had its own, shorter
  one, and the token file fell through the gap. Every rule lives here now.

      . (Join-Path $PSScriptRoot 'Ship-Rules.ps1')
      Test-ShipRuntime $rel        written by the game or a tool at runtime; never shipped, listed as removed when it goes
      Test-ShipMachine $rel        one machine's own; never shipped, never removed
      Test-ShipOtherServer $rel    not one of ours, or somebody's sign in; never shipped, never removed
      Test-ShipClientRecorded $rel [$full]
                                   one of the six client runtime files, and byte for byte the recorded build
      Test-ShipVanilla $rel        Bethesda's own files; never shipped, never removed
      Test-ShipForeignFramework $rel
                                   somebody else's framework or modding tool under Data; never shipped, never removed
      Test-ShipBethesdaLeftAlone   Bethesda's, and a pack once carried it; never shipped, never removed
      Test-ShipRetired $rel        a mod Thornswood took out; never shipped, never removed (the launcher drops it)
      Test-ShipBethesdaTool $rel   the Creation Kit, its script sources, or a copy of one of the game's programs; never shipped, never recorded, never removed (the launcher drops it)
      Test-ShipBackup $rel         any *.bak; never shipped, never removed
      Get-ShipOwnGameCollection    the collection's files in a Game folder the launcher made; never shipped
      Get-ShipLooseArt $files      loose textures and meshes an installer carries that are not ours, by folder
      Get-ShipLoadOrderDir         where the reference plugins.txt and loadorder.txt are read from
      Get-ShipRequiredDataRoot     game\required-data in the repo
      Ensure-ShipRequiredData      place those files into Data\ before a pack or installer scan
      Get-ShipSymbolDir            where this machine keeps launcher/setup .pdb per version (#462)
      Save-ShipSymbols             copy .pdb from a build folder into Get-ShipSymbolDir

  Paths are relative to the game folder, with backslashes.
#>

# Written at runtime, by the game, a tool or a session. Leaving a folder out
# here makes the next release list its files as removed, and the launcher
# takes them back off every install. So this is also the list of things that
# get cleaned off everybody when they have slipped into a pack once.
$ShipRuntimeDirs = @(
    # Where the Claude desktop app drops files it hands over in chat. It chose
    # the game folder for that once, and a report, a script and a png rode
    # along in packs 20260916-0130 to 0937.
    'Claude outputs\',
    # Where files are parked on a machine when a session cannot delete them.
    '_to_delete\',
    # RaceMenu writes a face export here when somebody saves one in game.
    'Data\SKSE\Plugins\CharGen\Exported\',
    # And its face tint beside it. The dev record of 29 September carried one
    # person's, Data\textures\CharGen\Exported\Adventurer3424.dds (#1152).
    'Data\textures\CharGen\Exported\',
    # Another server's folder must never be listed here: a runtime path has
    # its files listed as removed and swept off every install that has them,
    # which is somebody else's install being swept. Those go in
    # Test-ShipOtherServer below.
    '.sentry-native\'
)

# Settings that belong to the machine rather than to the build. SSE Display
# Tweaks holds the screen resolution, so publishing it stamped one person's
# monitor onto everyone. The client settings file carries one person's
# character slot. The logs and the voice files are live state.
$ShipMachineFiles = @(
    'Data\SKSE\Plugins\SSEDisplayTweaks.ini',
    'Data\Platform\Plugins\skymp5-client-settings.txt',
    'Data\Platform\overlay-boot.count',
    'Data\Platform\thornswood-dress.log',
    'Data\Platform\thornswood-emotes.log',
    'Data\Platform\thornswood-front.log',
    'Data\Platform\thornswood-voice.log',
    # Open Animation Replacer writes this back with its own values on every
    # exit. The two values this build cares about are held by the launcher's
    # Enforce table on every Play instead.
    'Data\SKSE\Plugins\OpenAnimationReplacer.ini',
    # SkyrimPlatform.ini is four machine settings in one file and none of
    # them belong to the build. It holds the log level, whether a console
    # window opens and how big it is, the plugin folder list, and the
    # BackendName line the launcher writes on every Play from what that
    # machine has on disk. Publishing it hands one person's trace logging
    # and console window to everybody, and pins them all to whichever
    # browser backend the machine that built the pack happened to have.
    # No pack has carried it yet, and that was luck rather than a rule.
    'Data\SKSE\Plugins\SkyrimPlatform.ini',
    # The launcher and the voice plugin talk through these three.
    'Data\Platform\voice-port.txt',
    'Data\Platform\voice-status.txt',
    'Data\Platform\voice-ptt.txt',
    # One person's signed join token for the voice room, written by the
    # launcher (Voice.cs) beside the three above. Never listed here until 20
    # September, which meant a pack built on a machine that had played would
    # carry it. Sixty minute life, so a stale one opens nothing, but a token is
    # a token.
    'Data\Platform\voice-token.txt',
    # Who this person has muted in voice, by profile id, written by the voice
    # plugin for the launcher (entry 151). One person's list, so never in a pack.
    'Data\Platform\voice-muted.txt',
    # The main menu character choice, 20 September: the launcher writes the
    # list before Play and the plugin writes the pick. Both are one machine's,
    # and the list is every profile id the install owns.
    'Data\Platform\thornswood-characters.json',
    'Data\Platform\thornswood-choice.txt',
    'Data\Platform\thornswood-forget.txt',
    # Whether this person turned the scroll in front of the choice off.
    'Data\Platform\thornswood-intro.txt',
    # The same list as a script beside the page (Chars.WriteCharacters), so
    # the choice draws before any plugin runs. Every profile id the install
    # owns, so never in a pack.
    'Data\Platform\UI\thornswood-characters.js',
    # Written by the game on this machine every session. The second is the
    # light half of the same list, kept apart because the server's own list
    # drops light plugins and the first file has to match it positionally.
    'Data\Platform\thornswood-loadorder.txt',
    'Data\Platform\thornswood-plugins-light.txt',
    # The launcher's note to the plugins that this is our session. See Keep.cs.
    'Data\Platform\thornswood-session.txt',
    'Data\Platform\menu-music-duck.txt',
    'Data\SKSE\Plugins\po3_Tweaks.ini',
    # One machine's key binds, microphone name and field of view. Every
    # launcher writes it, and the three packs of 16 and 17 Sep carried the
    # publishing machine's copy, which put its Fov=120 and its binds on
    # everyone. A machine without one gets the template from the launcher
    # (ThornIni.Ensure), so it never needs to travel.
    'Data\SKSE\Plugins\Thornswood.ini',
    'Data\SKSE\Plugins\CrashLogger.ini'
)

# Dev only. A path here rides in dev packs and never in a main pack or the
# installer, whatever else goes to main.
#
# EMPTY SINCE 22 SEPTEMBER, and the list stays because the reason for it will
# come round again. Its one entry was thornswood-dev-theme.mp3, the test track
# for the launcher, the main menu and the loading screen. It was held on dev
# from 20 September because the artist had not signed it off, and holding it
# was the whole point of this list. Patrick supplied the final version on
# 22 September and said it goes to main, so the track is now
# Data\Platform\UI\thornswood-theme.mp3, it ships everywhere, and the dev-only
# name went with the dev-only rule.
#
# Put a path back here the next moment something is playable on dev but not
# ours to give out yet. Do not take one out without the owner's word.
$ShipDevOnlyFiles = @(
)

function Test-ShipDevOnly([string]$rel) {
    foreach ($f in $ShipDevOnlyFiles) {
        if ($rel -eq $f) { return $true }
    }
    return $false
}

function Test-ShipRuntime([string]$rel) {
    foreach ($d in $ShipRuntimeDirs) {
        if ($rel.StartsWith($d, 'OrdinalIgnoreCase')) { return $true }
    }
    # The Claude desktop app has dropped its folder deeper than the game root
    # as well: Data\Platform\Claude outputs held three scripts on 16 Sep, one
    # of them written after that machine's baseline.
    if ($rel -match '(^|\\)Claude outputs\\') { return $true }
    return $false
}

# Not one of ours, and anybody's sign in. Decided by what belongs in the
# places another launcher could write to, never by whose a file is: this list
# named two other servers' files until 20 September, and the name of the
# thing to keep out is not the point, the thing to keep in is.
#
# OwnGame.Foreign in the launcher is the same list for Thornswood's own game
# folder; change the two together.
#
# The client runtime is the exception in the other direction. The six files in
# client-build.json are the bundle, MpClientPlugin.dll, both SkyrimPlatform
# DLLs, the CEF host and TESModPlatform.pex, built from the fork. Until 20
# September the copies in every game folder were another launcher's builds,
# told apart from ours by nothing but a comment we had written into them.
#
# One of them is ours when its bytes are the recorded build, and then it ships
# whatever else this says. Until 24 September this note said "ours by recorded
# hash" while the rule never opened the file: a path in the record was ours
# whatever sat there, so a bundle with one byte changed, or another launcher's
# bundle at the same path, went into a pack as ours (To Do entry 128, "a test
# that passes because of something we did to the file is not a test").
# Test-ShipClientRecorded below hashes the file against the record, the same
# sha256 Sync-Client.ps1 and the launcher's ClientRuntime compare. Anything
# else at one of those six paths, and a file that is not there at all, counts
# as not ours: never shipped, and never listed as removed, so no release
# deletes the client off a tester.
#
# PluginsNoLoad is where the SkyMP client keeps its saved sign in
# (auth-data-no-load.js, a token). It is one person's login to whichever
# master issued it and has no place in a pack or an installer, and it is not
# ours to delete off a machine either.
$ShipClientFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$ShipClientHashes = @{}
try {
    $clientRecord = Join-Path $PSScriptRoot '..\..\records\client-build.json'
    if (Test-Path -LiteralPath $clientRecord) {
        $rec = Get-Content -LiteralPath $clientRecord -Raw | ConvertFrom-Json
        foreach ($p in $rec.files.PSObject.Properties.Name) {
            [void]$ShipClientFiles.Add($p)
            $ShipClientHashes[$p] = ([string]$rec.files.$p.sha256).ToLowerInvariant()
        }
    }
} catch { }

# Whether the file at one of the six recorded paths is the recorded build, byte
# for byte. $full is the file when the caller has it. Without it the file is
# $rel under $GameDir: Publish-Update and Package-Thornswood both name the
# folder they scan $GameDir, and dot-sourcing this puts these functions in their
# scope, so their existing calls, which pass only the path, are answered by the
# bytes on disk. With no file and no $GameDir there is nothing to hash, and the
# answer is no.
#
# Hashed with .NET rather than Get-FileHash, for the reason Package-Thornswood
# gives over its own Get-Sha256: a script started with -NoProfile can find
# itself without the module Get-FileHash lives in.
function Test-ShipClientRecorded([string]$rel, [string]$full = '') {
    if (-not $ShipClientHashes.ContainsKey($rel)) { return $false }
    if (-not $full) {
        $game = Get-Variable -Name GameDir -ValueOnly -ErrorAction SilentlyContinue
        if (-not $game) { return $false }
        # Not Join-Path, which throws on a drive that is not there rather than
        # answering that the file is not.
        $full = [IO.Path]::Combine([string]$game, $rel)
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        # ReadWrite, the way ClientRuntime.Sha256Of opens it: SkyrimPlatform
        # holds these open while the game runs.
        $fs = New-Object IO.FileStream($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { $have = ([BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-', '').ToLowerInvariant() }
        finally { $fs.Dispose() }
    }
    finally { $sha.Dispose() }
    return ($have -eq $ShipClientHashes[$rel])
}

# SKYUI 5.2'S OWN SCRIPTS, LOOSE IN Data\Scripts. Issue #960, 28 September: on
# dev, "SKYUI ERROR CODE 6", menu file version mismatch for magicmenu.swf,
# skyui/itemcard.swf, skyui/bottombar.swf, map.swf and more, "required 5.2 SE,
# detected 6.11 SE".
#
# MEASURED on the shipping machine. The collection's SkyUI (Nexus 12604, in
# Vortex as SkyUI-12604-6-8) is one archive, SkyUI_SE.bsa: its menus say 6.11
# SE, and its own ski_main.pex (compiled 6 April 2026) no longer compares menu
# versions at all. But the ten names below sit loose in the Steam copy's
# Data\Scripts: SkyUI 5.2 SE's scripts, compiled 3 October 2017, whose
# ski_main.pex checks every menu for 5.2 SE. Loose beats an archive, so the old
# script runs against the new menus and puts up the error box. Vortex's record
# does not list them and no mod in its mods folder has them; the collection
# installer put them there (Profile\installed-into-game.txt lists all ten), the
# launcher linked them into Thornswood's folder, and the dev feed's baseline
# lists all ten, so dev packs have been handing them to everybody.
#
# Only these ten. SKI_ConfigBase.pex and SKI_ConfigManager.pex are loose too,
# but they are MCM Recorder's, deployed by Vortex, and stay.
# scripts\mods\Check-SkyUIMenus.js is the check Ship runs against this.
$ShipOldSkyUIScripts = @(
    'Data\Scripts\ski_activeeffectswidget.pex',
    'Data\Scripts\ski_configmenu.pex',
    'Data\Scripts\ski_favoritesmanager.pex',
    'Data\Scripts\ski_main.pex',
    'Data\Scripts\ski_playerloadgamealias.pex',
    'Data\Scripts\ski_qf_configmanagerinstance.pex',
    'Data\Scripts\ski_questbase.pex',
    'Data\Scripts\ski_settingsmanager.pex',
    'Data\Scripts\ski_widgetbase.pex',
    'Data\Scripts\ski_widgetmanager.pex'
)

function Test-ShipOtherServer([string]$rel) {
    # The client runtime, before anything else is asked: ours when it is the
    # recorded build, and not ours when it is anything else or is not there.
    if ($ShipClientFiles.Contains($rel)) { return (-not (Test-ShipClientRecorded $rel)) }
    # NirnLab UI Platform. SkyrimPlatform will not start on its own browser
    # while this is in the game folder, and it is what brings CEFSubprocess.exe,
    # the second program Windows Firewall asks about. Package-Thornswood has
    # kept it out of the installer all along; nothing kept it out of a pack.
    if ($rel -match '^Data\\NirnLabUIPlatform($|\\)') { return $true }
    if ((Split-Path $rel -Leaf) -ieq 'NirnLabUIPlugin.dll') { return $true }
    # Other launchers' parking folders inside our own game folder, Djinn, 25
    # September. Keizaal's launcher moves the Creation Club archives it turns
    # off into Data\_disabledByKzl and keeps its own backup and plugin list
    # beside the game; the Daedric server's launcher keeps DaedricData. They
    # came back after a Play and put 2.4 GB of somebody else's files into a dev
    # release. Never shipped, never removed. Anchored, with a boundary.
    if ($rel -match '^Data\\_disabledByKzl($|\\)') { return $true }
    if ($rel -match '^(_keizaal-plugins-off|DaedricData|keizaal-backup-[^\\]+)($|\\)') { return $true }
    # See $ShipDeleteAlways below for why this one also has to be DELETED from
    # machines that already have it, and not merely left out of new packs.
    # A loose map.swf. Somebody else left it in the Steam copy, it overrides
    # SkyUI's own copy inside SkyUI_SE.bsa because loose beats an archive, and
    # SkyUI answers with a full screen "ERROR CODE 5, Incompatible menu file
    # (map.swf)" on the way in. Vortex's deployment record does not list it and
    # A Quality World Map ships no Interface file at all, so nothing in the
    # collection wants it and taking it out keeps the good map.
    # OwnGame.Foreign carries the same rule; change the two together.
    if ($rel -ieq 'Data\Interface\map.swf') { return $true }
    # SkyUI 5.2's own scripts, loose, issue #960. See $ShipOldSkyUIScripts.
    # OwnGame.Foreign carries the same rule; change the two together.
    if ($ShipOldSkyUIScripts -contains $rel) { return $true }
    if (-not $rel.StartsWith('Data\Platform\', 'OrdinalIgnoreCase')) { return $false }
    $leaf = Split-Path $rel -Leaf
    if ($rel.StartsWith('Data\Platform\PluginsNoLoad\', 'OrdinalIgnoreCase')) { return $true }
    if ($leaf -like '*.bak') { return $true }
    # The retired dresser, To Do List entry 127. It is deleted from the repo
    # and never ships again, and it is on $ShipDeleteAlways below so every
    # pack takes it off the machines that have it. OwnGame.Foreign carries the
    # same rule; change the two together.
    if ($rel -ieq 'Data\Platform\Plugins\thornswood-chargen.js') { return $true }
    # In Plugins only our overlays belong. The bundle was decided by its hash above.
    if ($rel -like 'Data\Platform\Plugins\*.js') {
        if ($leaf -like 'thornswood-*.js') { return $false }
        return $true
    }
    # Under UI, ours is flat: index.html, build.js, our thornswood-*.js
    # overlays, and the front's own hashed fonts, icons and sounds beside
    # build.js (a .ttf, .svg, .png, .wav or .mp3 named by its hash, and
    # menu_theme.mp3). Somebody else's menu is a Vite build, which has an
    # assets folder, an app.js and a vite.svg. The first version of this rule
    # on 20 September whitelisted three names and called the front's own 147
    # asset files foreign, which the dev Ship of 13:02 duly left out of the
    # pack; a fresh installer would have shipped a front with no fonts.
    if ($rel -like 'Data\Platform\UI\*') {
        if ($rel -like 'Data\Platform\UI\assets\*') { return $true }
        if ($leaf -ieq 'app.js' -or $leaf -ieq 'vite.svg') { return $true }
        return $false
    }
    return $false
}

# ---------------------------------------------------------------------------
# BETHESDA'S OWN FILES, AND OTHER PEOPLE'S FRAMEWORKS AND TOOLS.
#
# Never shipped, and never listed as removed. Until 24 September these were
# two lists, one inside Publish-Update.ps1 and a longer one inside
# Package-Thornswood.ps1, which is exactly what the header of this file says
# must not happen, and they had drifted.
#
# MEASURED 24 SEPTEMBER over all 30,697 files in C:\Thornswood\Game on the
# machine that ships: packs carried 90 files (55.5 MB) that the installer
# deliberately left out, and all 90 were in both publish baselines. 82 were
# Nemesis's cache, logs and temporary behaviour files under
# Data\Nemesis_Engine, six were the Bethesda launcher's own state under
# BStarData (that machine's load order, plugin list and Skyrim.ini backups
# among them), and the last two were imgui.ini and steam_appid.txt. None of
# them came from Vortex: the launcher's record has every one as taken from the
# Steam copy. The lists below are the union of the two, so packs now leave out
# what the installer always did, and the installer leaves out what it always
# did.
#
# NEVER REMOVED, ON PURPOSE. A file the pack stops carrying looks gone from
# the build to Publish-Update, and a file gone from the build becomes a line
# in delete.txt unless Test-ShipMachine claims it. So Test-ShipMachine asks
# both tests below. Without that, the first pack after the lists became one
# would have deleted all 90 from every tester, steam_appid.txt with them. They
# stay on every machine that has them; packs simply stop carrying them.

# The five masters every copy of the game has, and the resource pack Steam
# installs beside them.
$ShipVanillaDataFiles = @(
    'Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm',
    '_ResourcePack.esl', '_ResourcePack.bsa'
)
# The game's own archives, and Creation Club content by its cc prefix. Steam
# installs some Creation Club plugins with the game, the rest is Bethesda's
# paid content, and none of it is ours to hand out. OwnGame.UnwantedCreation
# in the launcher counts on packs never carrying a cc plugin.
$ShipVanillaDataPatterns = @('Skyrim - *.bsa', 'cc*.esm', 'cc*.esl', 'cc*.esp', 'cc*.bsa')
# Bethesda's intro videos and the game's translated strings.
$ShipVanillaDataDirs     = @('Video', 'Strings')

# Other people's frameworks and modding tools, by their folder under Data.
#
# Vortex's manifest answers "did Vortex put this here", which is not the same
# question as "does Thornswood need this". These folders answered no to the
# first and were shipped to everybody as though they were ours.
#
# NirnLabUIPlatform is another roleplay server's user interface framework and
# on its own it is 356 MB. Nemesis, FNIS, BodySlide and xEdit are tools that
# belong on the machine of somebody who builds mods, not in a folder handed to
# somebody who plays. The rest is documentation, installer leftovers and a
# shader cache that rebuilds itself on first launch. Data\Source, Papyrus script
# sources, was on this list until #1227 moved it to the Creation Kit's rule
# (Test-ShipBethesdaTool) with Data\Scripts\Source, which this list never had.
#
# All of them stay where they are on every machine. This only decides what
# goes into a pack or the installer.
#
# Only the installer had this list until 24 September. Packs kept NirnLab out
# anyway, through Test-ShipOtherServer above; the 82 Nemesis files were what
# they carried from it.
#
# NirnLab is still an open question for Patrick and Djinn, and merging the
# lists does not answer it. The note over Checks.ForeignNames in the launcher
# says NirnLabUIPlugin.dll is this build's own browser and must never be
# treated as foreign. This file, the installer and OwnGame.Foreign
# all treat it as foreign. What this machine runs on, read
# 24 September: SkyrimPlatform.ini says BackendName = tilted, the plugin log of
# the 10:20 session on 23 September says "browser backend: tilted", and there
# is no Data\NirnLabUIPlatform in C:\Thornswood\Game.
$ShipForeignDataDirs = @(
    'NirnLabUIPlatform',
    'Nemesis_Engine', 'FNIS Behavior SE 7.6', 'CalienteTools', 'tools',
    'ModderResource', 'FOMod',
    'Docs', 'Docs and Screenshots', 'readmes',
    'ShaderCache'
)

$ShipVanillaRootFiles = @(
    # The game, its launcher, Steam's library and the video codec. The
    # installer fingerprints three of them into vanilla.json so it can tell a
    # clean Steam copy from a patched one; it never carries them.
    'SkyrimSE.exe', 'SkyrimSELauncher.exe', 'steam_api64.dll', 'bink2w64.dll',
    # The game's Creation Club list, Steam's install script, and the settings
    # presets Bethesda's launcher picks from.
    'Skyrim.ccc', 'installscript.vdf', 'Skyrim_Default.ini',
    'High.ini', 'Low.ini', 'Medium.ini', 'Ultra.ini',

    # Only on the installer's list until 24 September.
    #
    # The script extender is not ours to hand out and it is in the collection
    # now, so shipping it again would be redistributing somebody's mod and
    # doing it twice. VERSION and steam_appid.txt belong to Steam and the
    # downgrader. imgui.ini and the d3dx9 log are written at runtime by
    # whatever was last run against this install.
    #
    # The installer said these were only ever seen when building out of the
    # Steam copy. Not so: the launcher copies steam_appid.txt and imgui.ini
    # from the Steam copy into Thornswood's own folder, and packs carried both.
    'skse64_loader.exe', 'skse64_1_6_1170.dll',
    'skse64_readme.txt', 'skse64_whatsnew.txt',
    'VERSION', 'steam_appid.txt', 'imgui.ini', 'd3dx9_42.log'
)
$ShipVanillaRootDirs = @(
    # The downgrader's backups of the files it replaced: the game's own
    # programs and Creation Club archives, 46 files on the machine that ships.
    '_DowngraderBackups',
    # Two folders beside the game that are empty on the machine that ships,
    # and Skyrim\, which holds only SkyrimPrefs.ini.
    'Creations', 'Mods', 'Skyrim',
    # The script extender's source code, which comes with it.
    'src',
    # Bethesda's launcher keeps its own folder. Not ours, not in an installer,
    # and not in a pack either: six of its files rode in packs until
    # 24 September.
    'BStarData'
)

function Test-ShipVanilla([string]$rel) {
    $parts = $rel -split '\\'
    $top   = $parts[0]
    if ($ShipVanillaRootDirs -contains $top) { return $true }
    if ($parts.Count -eq 1) { return ($ShipVanillaRootFiles -contains $top) }
    if ($top -ne 'Data') { return $false }
    if ($parts.Count -ge 3 -and ($ShipVanillaDataDirs -contains $parts[1])) { return $true }
    if ($parts.Count -eq 2) {
        $leaf = $parts[1]
        if ($ShipVanillaDataFiles -contains $leaf) { return $true }
        foreach ($p in $ShipVanillaDataPatterns) { if ($leaf -like $p) { return $true } }
    }
    return $false
}

function Test-ShipForeignFramework([string]$rel) {
    $parts = $rel -split '\\'
    if ($parts[0] -ne 'Data') { return $false }
    return ($parts.Count -ge 2 -and ($ShipForeignDataDirs -contains $parts[1]))
}

# Bethesda's own files that packs have already carried. Never shipped again,
# and never listed as removed.
#
# Data\MarketplaceTextures.bsa is Bethesda's archive for the in-game Creations
# menu: 121 files, every one under interface\marketplace (buttons for pc and
# xbox, and the stars). 2.8 MB, dated 10 September 11:08:10, five seconds
# after _ResourcePack.bsa, and _DowngraderBackups holds a 3.2 MB copy of it
# beside the rest of Bethesda's files. No plugin loads it by name and Vortex
# does not provide it, so it was in neither vanilla list and in no record,
# and every pack and the installer carried it.
#
# WHY IT WAS NOT PUT WITH SKYRIM.ESM IN THE VANILLA LISTS. Measured 24
# September: both pack baselines, published.json and published-dev.json, list
# Data\MarketplaceTextures.bsa. Publish-Update lists as removed anything the
# last pack had that this scan does not, and the only thing that stops that is
# Test-ShipMachine. When this list was made the vanilla lists were not asked
# there, so a vanilla rule would have left it out of the scan, the next pack
# would have put it in delete.txt, and every launcher that took the pack would
# have deleted a Bethesda file off a tester who has every right to it. Asked
# here, through Test-ShipMachine, it leaves packs and the installer and
# nobody's copy is touched. The launcher builds Thornswood's game folder out
# of the tester's own Steam copy, which is where this machine's came from:
# Profile\OwnGame\files.txt has it as linked in from the Steam copy (L), and
# not deployed by Vortex (O).
#
# The same day the vanilla lists moved into this file and Test-ShipMachine
# started asking them as well (the note over $ShipVanillaDataFiles), so a
# vanilla rule is now just as safe. This list stays because it is the record
# of which Bethesda files a pack has already carried, each with its
# measurement. Put a Bethesda file here whenever a pack has already carried
# it, so that record stays whole.
$ShipBethesdaLeftAlone = @(
    'Data\MarketplaceTextures.bsa'
)

function Test-ShipBethesdaLeftAlone([string]$rel) {
    foreach ($f in $ShipBethesdaLeftAlone) {
        if ($rel -ieq $f) { return $true }
    }
    return $false
}

# A mod Thornswood has taken out. Never shipped, and never listed as removed:
# the launcher takes these out of its own game folder itself (OwnGame.Retired,
# rules 7), so a pack has nothing to delete and no Vortex file in the Steam
# copy is touched. Change the two lists together.
#
# Start On Save (po3, Nexus 50054), issue #394. Under SkyMP it only ever
# started a second load on top of the server's, which crashed the game about
# thirty seconds in, and the launcher held it still by rewriting its settings
# file on every Play. That rewrite is gone, so neither file may reach a build:
# the DLL with an untouched settings file is the crash again.
$ShipRetiredFiles = @(
    'Data\SKSE\Plugins\po3_StartOnSave.dll',
    'Data\SKSE\Plugins\po3_StartOnSave.ini'
)

function Test-ShipRetired([string]$rel) {
    foreach ($f in $ShipRetiredFiles) {
        if ($rel -ieq $f) { return $true }
    }
    return $false
}

# Body shape sliders and jiggle, issue #993. Patrick, 28 September: no jiggle
# physics and nothing in creation that changes breasts, seat, genitals or
# nipples, for men and women alike; height and weight stay. CBPC's cbp.dll is
# all of the jiggle, and the three scripts are RaceMenu's body slider pages.
# The launcher leaves them out of its own game folder (OwnGame.BodyShape,
# rules 9), so, like the retired files above, a pack never carries them and
# never lists them as removed. Change the two lists together.
$ShipBodyShapeFiles = @(
    'Data\SKSE\Plugins\cbp.dll',
    'Data\Scripts\RaceMenuMorphsCBBE.pex',
    'Data\Scripts\_RaceMenuMorphsHIMBO.pex',
    'Data\Scripts\RaceMenuPluginSoS.pex'
)

function Test-ShipBodyShape([string]$rel) {
    foreach ($f in $ShipBodyShapeFiles) {
        if ($rel -ieq $f) { return $true }
    }
    return $false
}

# BETHESDA'S CREATION KIT, AND COPIES OF THE GAME'S OWN PROGRAMS. Issue #1152.
#
# Never shipped, never in a release record, and never listed as removed.
# Thornswood never hands out Bethesda's files: the installer fingerprints the
# game (vanilla.json) and never carries it.
#
# MEASURED 29 September on the dev record the feed named that day
# (20260929-0259-dev): of its 2,515 files of ours, about 180 MB were Bethesda's.
# CreationKit.exe (46.4 MB) with CreationKit.ini and CreationKitPrefs.ini; the
# Tools folder (86.8 MB: AssetWatcher, the Havok, lip sync and audio tools,
# Microsoft's redistributables); Papyrus Compiler; lex; flowchartx64.dll,
# flowchartx32.dll and p4com64.dll; EditorWarnings.txt, DataFiles.txt and
# SkyrimReservedAddOnIndexes.txt; Data\Scripts.zip, the game's script sources
# (13.6 MB); 1,785 files under Data\DialogueViews (55.4 MB); and
# SkyrimSE.exe.bak-1160-for-369 (35.4 MB), a copy of Skyrim itself. Main pack
# 20260926-1603 carried the Creation Kit and the copy of the game, and the dev
# packs 20260927-0059 and 0250 the rest.
#
# How they got in: Steam installs the Creation Kit into the Steam copy, the
# launcher's own folder takes what the Steam copy has, and a file Vortex did
# not deploy counted as ours. The vanilla lists above name SkyrimSE.exe, not a
# copy of it under another name.
#
# NOT LISTED AS REMOVED, ON PURPOSE. A pack's delete.txt reaches every
# launcher, old ones too, and an install with no game folder of its own
# applies it to the Steam copy, where a Creation Kit is the person's own. So
# the launcher takes these out of its own game folder itself
# (OwnGame.BethesdaTool, rules 10) and nothing touches a Steam copy. Change the
# two together.
#
# THE CREATION KIT'S SCRIPT SOURCES (#1227). The Creation Kit unpacks
# Data\Scripts.zip into Data\Source\Scripts the first time it runs: on the
# shipping machine that was 14,298 .psc files (15.9 MB), which Thornswood's own
# folder took from the Steam copy as its own. Packs had left Data\Source out
# since 24 September, through the foreign frameworks list, but the launcher
# did not. Data\Scripts\Source, the same folder under the name the first
# Creation Kit and SKSE use, was on no list at all. Measured over HTTPS on
# 29 September: all five dev records the feed lists (20260928-2324-dev to
# 20260929-140118-dev) name Data\Scripts\Source\IED.psc, which was sent to the
# site loose, and main packs 20260915-2018, 20260915-2104 and 20260915-2144
# each carried the script extender's 62 sources there (SKSE.psc, Actor.psc and
# the rest). No record or pack names anything under Data\Source.
#
# Both folders are the Creation Kit's alone: the game reads the compiled
# scripts in Data\Scripts and never a source. So the whole of both folders
# never ships, whoever put a file there: Bethesda's sources, and the sources
# mod authors put beside them, which are the collection's to hand out.
# Thornswood has no Papyrus sources in a game folder. Ours are the engine
# fork's (engine\skymp: MpClientPlugin.psc and the Skyrim Platform ones), and
# they stay in the repository; only their compiled scripts reach a game.
#
# Measured the same day on the Steam copy's Creation Kit install list (its two
# Steam depots, 56 files): every file it installs is named here. The Creation
# Kit then writes CreationKitPrefs.ini, EditorWarnings.txt, DataFiles.txt,
# Data\DialogueViews and these sources as it runs; those are named here too.
$ShipBethesdaToolRootDirs  = @('Tools', 'Papyrus Compiler', 'lex')
$ShipBethesdaToolDataDirs  = @('Data\DialogueViews', 'Data\Source', 'Data\Scripts\Source')
$ShipBethesdaToolRootFiles = @(
    'flowchartx64.dll', 'flowchartx32.dll', 'p4com64.dll',
    'EditorWarnings.txt', 'DataFiles.txt', 'SkyrimReservedAddOnIndexes.txt'
)

function Test-ShipBethesdaTool([string]$rel) {
    $parts = $rel -split '\\'
    if ($parts.Count -gt 1 -and ($ShipBethesdaToolRootDirs -contains $parts[0])) { return $true }
    if ($parts.Count -eq 1) {
        $leaf = $parts[0]
        # CreationKit.exe, its settings files and anything else it names so.
        if ($leaf -like 'CreationKit*') { return $true }
        if ($ShipBethesdaToolRootFiles -contains $leaf) { return $true }
        # A copy of one of the game's programs under another name, such as
        # SkyrimSE.exe.bak-1160-for-369. The programs themselves are vanilla.
        if ($leaf -match '^(SkyrimSE|SkyrimSELauncher|skse64_loader)\.exe.') { return $true }
        return $false
    }
    if ($rel -ieq 'Data\Scripts.zip') { return $true }
    foreach ($d in $ShipBethesdaToolDataDirs) {
        if ($rel.StartsWith($d + '\', 'OrdinalIgnoreCase')) { return $true }
    }
    return $false
}

# A BACKUP IS NEVER A FILE OF THE BUILD, wherever it is. The rule in
# Test-ShipOtherServer only looked in Data\Platform, so the same dev record
# carried Data\SKSE\Plugins\SkyrimPlatform.ini.bak and
# SkyrimPlatform.ini.2026-09-19T20-17-00-253Z.bak (one machine's settings, see
# $ShipMachineFiles) and VERSION.bak beside the game (#1152). A name with .bak
# at its end, or followed by a dash or a dot. Never shipped, never removed.
function Test-ShipBackup([string]$rel) {
    return ((Split-Path $rel -Leaf) -match '\.bak($|[-.])')
}

# One machine's own, never shipped and never listed as removed. Other servers'
# files count as the machine's here, so a release never strips another
# server's install off a tester.
function Test-ShipMachine([string]$rel) {
    if (Test-ShipOtherServer $rel) { return $true }
    if (Test-ShipRetired $rel) { return $true }
    if (Test-ShipBodyShape $rel) { return $true }
    if (Test-ShipBethesdaTool $rel) { return $true }
    if (Test-ShipBackup $rel) { return $true }
    # So do Bethesda's files and other people's frameworks and tools, for the
    # same reason. See the note over $ShipVanillaDataFiles for the 90 files
    # that needed it on 24 September, and the one over $ShipBethesdaLeftAlone
    # for MarketplaceTextures.bsa.
    if (Test-ShipVanilla $rel) { return $true }
    if (Test-ShipForeignFramework $rel) { return $true }
    if (Test-ShipBethesdaLeftAlone $rel) { return $true }
    foreach ($f in $ShipMachineFiles) {
        if ($rel -eq $f) { return $true }
    }
    # Vortex's own bookkeeping. The deployment manifests record what Vortex
    # put into THIS Skyrim, the .vortex_backup files are what it moved aside
    # here, and the __folder_managed_by_vortex markers are its claim on a
    # folder. Handing somebody else's copy to their Vortex is how it loses
    # track of its own deployment; pack-20260916-1217 carried a 6 MB
    # vortex.deployment.json for exactly that reason.
    $leaf = Split-Path $rel -Leaf
    if ($leaf -eq 'vortex.deployment.json') { return $true }
    if ($leaf -eq 'vortex.deployment.dinput.json') { return $true }
    if ($leaf -eq '__folder_managed_by_vortex') { return $true }
    if ($leaf -like '*.vortex_backup') { return $true }
    return $false
}

# Thornswood's own game folder (Root\Game, made by the launcher out of what
# Vortex deployed into the Steam copy, OwnGame.cs). Most of it is the
# collection, linked in, and it carries no Vortex record of its own, because
# those describe the Steam copy and are left there. The launcher's record,
# Profile\OwnGame\files.txt, has one line per file brought in:
# kind|origin|size|ticks|path, with origin V for what Vortex deployed. Those
# are the collection's files and stay out of packs and installers, the same way
# the Vortex record keeps them out when the game is the Steam copy.
#
# Returns the set of paths, or $null when this build has no such record (the
# game is the Steam copy, or Root\Game came from an installer before 1.1).
function Get-ShipOwnGameCollection([string]$ProfileDir) {
    $record = Join-Path $ProfileDir 'OwnGame\files.txt'
    if (-not (Test-Path -LiteralPath $record)) { return $null }
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in [IO.File]::ReadLines($record)) {
        $p = $line.Split([char[]]'|', 5)
        if ($p.Count -eq 5 -and $p[1] -eq 'V') { [void]$set.Add($p[4]) }
    }
    return ,$set
}

# LOOSE ART NOBODY HAS ACCOUNTED FOR, named so a build says what it carries.
#
# Measured from Profile\OwnGame\files.txt on 24 September: 563 files and 539
# MB under Data\textures and Data\meshes, the menu backdrop not counted, that
# Vortex never deployed, dropped into the Steam copy by hand. Lost Ark armour
# ports, somebody's custom weapons, BodySlide output built for one person's
# body, Nemesis output, and leftovers of mods no longer installed. The
# installer leaves out what the collection provides and nothing else, so every
# one of them went to everybody who installed, and nothing on screen said so.
#
# This reports and does not refuse. Which of these may ship at all (BodySlide
# output, the Nemesis output in meshes\actors) is Patrick's to decide, and a
# refusal would stop every installer build until the folders are gone.
#
# Ours is the main menu backdrop: the three files Go.ps1 writes from
# game\menu ($menuPairs there; change the two together). Anything else
# here is somebody else's until it is traced to a mod page and put in the
# collection, or moved into the Thornswood Content mod, and either way it then
# leaves the installer by itself.
$ShipOwnArt = @(
    'Data\meshes\interface\logo\logo.nif',
    'Data\meshes\interface\logo\logo01ae.nif',
    'Data\textures\interface\objects\Mainmenuwallpaper.dds'
)

# $files is what is about to ship: anything with a Rel (the path under the game
# folder) and a Len (its bytes). Returns one row per first folder under
# Data\textures or Data\meshes, biggest first, as Folder, Files and Bytes.
# Files straight under Data\textures or Data\meshes are a row of their own.
function Get-ShipLooseArt($files) {
    $own = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($o in $ShipOwnArt) { [void]$own.Add($o) }
    $rows = @{}
    foreach ($f in @($files)) {
        if ($null -eq $f) { continue }
        $rel = [string]$f.Rel
        if ($own.Contains($rel)) { continue }
        $parts = $rel -split '\\'
        if ($parts.Count -lt 3 -or $parts[0] -ne 'Data') { continue }
        if ($parts[1] -ne 'textures' -and $parts[1] -ne 'meshes') { continue }
        if ($parts.Count -eq 3) { $folder = $parts[0] + '\' + $parts[1] }
        else { $folder = $parts[0] + '\' + $parts[1] + '\' + $parts[2] }
        $key = $folder.ToLowerInvariant()
        if (-not $rows.ContainsKey($key)) {
            $rows[$key] = [pscustomobject]@{ Folder = $folder; Files = 0; Bytes = [long]0 }
        }
        $rows[$key].Files++
        $rows[$key].Bytes += [long]$f.Len
    }
    return ,@($rows.Values | Sort-Object -Property @{ Expression = 'Bytes'; Descending = $true }, 'Folder')
}

# Where this build's reference plugins.txt and loadorder.txt are read from.
#   no Root\Game         the Steam copy: Vortex writes them into AppData
#   an own folder        Profile\OwnGame: the Vortex profile's lists as of the
#                        folder's last update, which is the collection's order
#   an older Root\Game   Profile\Default. AppData is only this build's while
#                        the game runs, so reading it with the game closed
#                        shipped the ordinary Skyrim's list.
function Get-ShipLoadOrderDir([string]$Root, [string]$ProfileDir) {
    $own = Join-Path $ProfileDir 'OwnGame'
    if (Test-Path -LiteralPath (Join-Path $own 'plugins.txt')) { return $own }
    # Named Thornswood Vortex profile over Windows' live list (#557).
    if (Get-Command Get-VortexProfileDir -ErrorAction SilentlyContinue) {
        $tw = Get-VortexProfileDir 'Thornswood'
        if ($tw -and (Test-Path -LiteralPath (Join-Path $tw 'plugins.txt'))) { return $tw }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'Game'))) {
        return (Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition')
    }
    return (Join-Path $ProfileDir 'Default')
}

# ---------------------------------------------------------------------------
# FILES EVERY PACK DELETES, WHETHER THIS MACHINE HAS THEM OR NOT.
#
# Leaving a file out of a pack stops it reaching NEW machines. It does nothing
# at all for the ones that already have it, and those are the machines the
# problem is on.
#
# 22 September, map.swf. It was excluded from shipping by the rule above, the
# release went out, and the pack carried no delete.txt: every tester who
# already had the game kept the broken file and kept the SkyUI error box.
# Excluding it had only helped people who did not have the problem.
#
# WHY IT WAS NOT CAUGHT BY THE ORDINARY REMOVAL DIFF. A file that leaves the
# game folder is normally a removal, but removals are filtered through
# Test-FromCollection first, and the launcher's own record of what Vortex
# provides lists map.swf even though Vortex's deployment manifest does not. So
# it was read as a collection file and dropped from the removal list. That
# guard is RIGHT and stays: the first release after the move to the Steam copy
# carried 28,833 removals and had to be pulled out of version.json by hand.
#
# So this is the deliberate override, and it is a list of paths somebody has
# decided must not exist, not a diff. Deleting a file that is not there is a
# no-op in Updater.Install, so carrying these in every pack costs nothing and
# is what makes the fix reach the machines that need it.
#
# KEEP IT SHORT. Every entry here is deleted from everybody's game on every
# update, for ever. Nothing belongs here that the collection might one day
# legitimately provide.
$ShipDeleteAlways = @(
    # SkyUI refuses a map.swf it does not recognise and puts a full screen
    # ERROR CODE 5 over the loading screen. Vortex deploys no map.swf, SkyUI
    # ships its own inside SkyUI_SE.bsa, and A Quality World Map ships no
    # Interface file at all, so nothing in the collection wants a loose one.
    'Data\Interface\map.swf',

    # ONE PERSON'S VOICE JOIN TOKEN, WHICH NINE PUBLISHED PACKS CARRIED.
    #
    # MEASURED 23 SEPTEMBER, which is what entry 81 asked for and what nobody
    # had done. The token file first existed on 18 September (b2a9f9d) and the
    # packing rule that excludes it landed on 20 September (15c472a). Thirteen
    # packs were published inside that window. Nine of them carry
    # game/Data/Platform/voice-token.txt: 20260918-1615, 20260918-2340,
    # 20260919-1416, 20260919-1546, 20260919-1944, 20260919-2010,
    # 20260919-2044, 20260920-1103 and 20260920-1124. Counted by listing the
    # names inside each zip; no token was opened or printed, per that entry.
    #
    # WHAT IT IS AND IS NOT. The token is a signed join token that proves one
    # profile id to the voice service and lives sixty minutes, so every one of
    # these expired in September 2026 and opens nothing now. The fault was the
    # rule, not the damage.
    #
    # LEAVING IT OUT OF NEW PACKS DOES NOTHING FOR THE MACHINES THAT HAVE ONE,
    # which is the whole reason this list exists: map.swf taught that on 22
    # September. So the next release deletes it from every install that took
    # one of those nine. Harmless to a working machine, because the launcher
    # writes a fresh token at Play and the update is applied before that.
    #
    # THE PUBLISHED PACKS ARE DELIBERATELY LEFT ALONE. Rewriting a release
    # asset changes its sha256, and version.json records that hash for every
    # pack: a launcher that took the old one would fail its checksum and stop.
    # Breaking the feed to remove an expired token is a worse trade than
    # leaving nine dead tokens in nine old zips.
    'Data\Platform\voice-token.txt',

    # THE RETIRED DRESSER, To Do List entry 127. It put the best armour it
    # could find into every empty slot, which is Patrick's "it is auto
    # equipping things sometimes, like a hat", and it is deleted from the repo.
    #
    # Test-ShipOtherServer above calls it not ours, which keeps it out of
    # packs and the installer and, on its own, out of the removal diff as well.
    # So it goes here, the way map.swf did, and every pack deletes it whether
    # or not this machine's baseline still carries it.
    #
    # The launcher's own folder is why that is not enough by itself. A Steam
    # copy that took packs before its machine had a folder of its own still
    # has the old dresser (11,654 bytes, 16 Sep, on Patrick's machine), and a
    # refresh copies whatever the Steam copy has and the folder lacks straight
    # back in. OwnGame.Foreign refuses it, which is what makes the deletion
    # stick. The name is never used again, so nothing legitimate is lost.
    'Data\Platform\Plugins\thornswood-chargen.js'
)
# SkyUI 5.2's loose scripts, issue #960: dev packs carried them, so leaving
# them out of new packs would do nothing for the machines showing the SkyUI
# error box. The collection's SkyUI keeps its scripts inside SkyUI_SE.bsa, so
# nothing it installs is lost. See $ShipOldSkyUIScripts above.
$ShipDeleteAlways += $ShipOldSkyUIScripts

function Get-ShipDeleteAlways { return $ShipDeleteAlways }

# FILES THAT TRAVEL WITH A PAGE, issue #883.
#
# A pack is a diff against the baseline, so a file the baseline already lists
# is never packed again, whether or not any launcher ever received it. The
# sealed scroll's two pictures were written into this machine's game folder on
# 25 September (17:54 UTC) and recorded by Main update 20260925-1654, which was
# pulled from version.json four minutes later. The baseline kept them. Not one
# of the 75 packs on the Main feed carries either picture (every zip listed,
# 28 September), so an install that has only ever taken packs has the page
# and not its art, and thornswood-select.js answers a missing picture with
# "a scroll picture is missing, straight to the slots". That is the start
# screen that skipped the scroll after the update, on the Main launcher.
#
# So when a pack carries the key, it carries these beside it, changed or not:
# 47 KB, only in a pack that already changes the page. The next pack with the
# page in it puts the pictures on every install that is missing them.
# tests\test-start-screen-art.ps1 holds this list to the pictures the page names.
$ShipTravelsWith = @{
    'Data\Platform\UI\thornswood-select.js' = @(
        'Data\Platform\UI\thornswood-scroll.webp',
        'Data\Platform\UI\thornswood-scroll-open.webp'
    )
}

# The companions of every changed path that are not already in the list.
function Get-ShipTravelsWith([string[]]$changed) {
    $out = @()
    foreach ($c in @($changed)) {
        foreach ($k in $ShipTravelsWith.Keys) {
            if ($c -ieq $k) {
                foreach ($w in $ShipTravelsWith[$k]) {
                    if (@($changed) -notcontains $w -and $out -notcontains $w) { $out += $w }
                }
            }
        }
    }
    return $out
}

# REQUIRED DATA THE COLLECTION DOES NOT YET DEPLOY UNDER THE LOAD ORDER NAME.
#
# game\required-data holds plugins (today: ElysiumEstateSSE.esp) that plugins.txt
# and the server enable by exact filename, while Vortex still deploys a different
# name (ElysiumEstate.esp 4.3.5). OwnGame links only what Vortex deployed, so the
# SSE file was only on one machine until it was copied by hand, and every other
# player hit the same missing-plugin warning.
#
# Go.ps1, Publish-Update and Package-Thornswood call Ensure-ShipRequiredData so
# each file here lands at Data\<name> before the pack / installer scan. They are
# not origin V in files.txt, so packs carry them. Take a file out of
# game\required-data when the collection deploys that same Data\ path.
function Get-ShipRequiredDataRoot([string]$RepoDir) {
    return (Join-Path $RepoDir 'game\required-data')
}

# Places every file under game\required-data (except README.md) at Data\<name>
# in $GameDir. Breaks an existing hard link first so a write never goes through
# into Vortex staging. Returns the relative paths placed. Throws when the
# folder is missing a file that was expected to be tracked, or when copy fails.
function Ensure-ShipRequiredData([string]$GameDir, [string]$RepoDir) {
    $srcRoot = Get-ShipRequiredDataRoot $RepoDir
    if (-not (Test-Path -LiteralPath $srcRoot)) {
        throw "game\required-data is missing under $RepoDir"
    }
    $placed = New-Object System.Collections.Generic.List[string]
    foreach ($f in @(Get-ChildItem -LiteralPath $srcRoot -File -EA Stop)) {
        if ($f.Name -eq 'README.md') { continue }
        $rel = 'Data\' + $f.Name
        $dst = Join-Path $GameDir $rel
        $dir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Force -Path $dir
        }
        # OwnGame.Unshare pattern: drop the name if it is a hard link so the
        # copy is this folder's own bytes, not Vortex's.
        if (Test-Path -LiteralPath $dst) {
            try { Remove-Item -LiteralPath $dst -Force -EA Stop } catch {
                throw ("Could not replace $rel in the game folder (is the game open?): " + $_.Exception.Message)
            }
        }
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force -EA Stop
        $placed.Add($rel)
    }
    return ,$placed.ToArray()
}

# ------------------------------------------------------------ launcher symbols
#
# Issue #462. /debug:pdbonly makes Thornswood.pdb (and setup-stub.pdb) beside
# the built exes. Those files carry absolute source paths from the build
# machine and method names. They NEVER leave this machine inside a pack, the
# installer, or a public release asset. Package-Thornswood.ps1 and
# Publish-Update.ps1 already skip any *.pdb under the game folder; this names
# the same rule for the launcher and the setup stub.
#
# Kept per version under Get-ShipSymbolDir so a customer's launcher.log IL
# offsets (Shell.cs fault handler) can be mapped to a line later. Shipping the
# pdb to customers as a second launcher asset needs a #dev decision first.

function Get-ShipSymbolDir([string]$Version) {
    $root = Join-Path $env:LOCALAPPDATA 'Thornswood\symbols'
    if ([string]::IsNullOrWhiteSpace($Version)) { return $root }
    return (Join-Path $root $Version)
}

# Copies every .pdb found in $FromDir into Get-ShipSymbolDir $Version.
# Returns the paths written. Missing pdbs are fine (older CI builds, or a
# main Ship that took the verified exe and never compiled here).
function Save-ShipSymbols([string]$FromDir, [string]$Version) {
    if ([string]::IsNullOrWhiteSpace($FromDir) -or -not (Test-Path -LiteralPath $FromDir)) {
        return ,@()
    }
    $dest = Get-ShipSymbolDir $Version
    if (-not (Test-Path -LiteralPath $dest)) {
        $null = New-Item -ItemType Directory -Force -Path $dest
    }
    $written = New-Object System.Collections.Generic.List[string]
    foreach ($pdb in @(Get-ChildItem -LiteralPath $FromDir -Filter '*.pdb' -File -EA SilentlyContinue)) {
        $to = Join-Path $dest $pdb.Name
        Copy-Item -LiteralPath $pdb.FullName -Destination $to -Force
        $written.Add($to)
    }
    return ,$written.ToArray()
}