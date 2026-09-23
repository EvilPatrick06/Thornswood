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
      Get-ShipOwnGameCollection    the collection's files in a Game folder the launcher made; never shipped
      Get-ShipLoadOrderDir         where the reference plugins.txt and loadorder.txt are read from

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
    # Data\SkyrimTogetherReborn\ WAS HERE, cache and logs, until 23
    # September. It is another server's folder and it belongs in
    # Test-ShipOtherServer below, by prefix, which is where it is now.
    # The difference is not cosmetic: a runtime path has its files listed
    # as removed and swept off every install that has them, and this is
    # somebody else's install being swept. Two named subfolders were
    # listed and the rest of the folder was in no list at all, so a pack
    # could carry the parts that were not named.
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
    # The main menu character choice, 20 September: the launcher writes the
    # list before Play and the plugin writes the pick. Both are one machine's,
    # and the list is every profile id the install owns.
    'Data\Platform\thornswood-characters.json',
    'Data\Platform\thornswood-choice.txt',
    'Data\Platform\thornswood-forget.txt',
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
# client-build.json are ours by recorded hash: the bundle, MpClientPlugin.dll,
# both SkyrimPlatform DLLs, the CEF host and TESModPlatform.pex, built from the
# fork. Until 20 September the copies in every game folder were another
# launcher's builds, told apart from ours by nothing but a comment we had
# written into them. A path in that record is ours whatever else this says.
#
# PluginsNoLoad is where the SkyMP client keeps its saved sign in
# (auth-data-no-load.js, a token). It is one person's login to whichever
# master issued it and has no place in a pack or an installer, and it is not
# ours to delete off a machine either.
$ShipClientFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
try {
    $clientRecord = Join-Path $PSScriptRoot 'client-build.json'
    if (Test-Path -LiteralPath $clientRecord) {
        $rec = Get-Content -LiteralPath $clientRecord -Raw | ConvertFrom-Json
        foreach ($p in $rec.files.PSObject.Properties.Name) { [void]$ShipClientFiles.Add($p) }
    }
} catch { }

function Test-ShipOtherServer([string]$rel) {
    # Ours by record, before anything else is asked.
    if ($ShipClientFiles.Contains($rel)) { return $false }
    # NirnLab UI Platform. SkyrimPlatform will not start on its own browser
    # while this is in the game folder, and it is what brings CEFSubprocess.exe,
    # the second program Windows Firewall asks about. Package-Thornswood has
    # kept it out of the installer all along; nothing kept it out of a pack.
    if ($rel -match '^Data\\NirnLabUIPlatform($|\\)') { return $true }
    if ((Split-Path $rel -Leaf) -ieq 'NirnLabUIPlugin.dll') { return $true }
    # Skyrim Together Reborn's whole folder, wherever it came from. Its
    # cache and its logs used to be in the runtime list above, which meant
    # a release listed them as removed and every launcher took them off
    # somebody's other install. Nothing here supports another server any
    # more, so the rule is the one this list exists for: never shipped,
    # never removed. Anchored and with a boundary, so a sibling folder
    # whose name merely starts the same way is not matched.
    # OwnGame.Foreign carries the same rule; change the two together.
    if ($rel -match '^Data\\SkyrimTogetherReborn($|\\)') { return $true }
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
    if (-not $rel.StartsWith('Data\Platform\', 'OrdinalIgnoreCase')) { return $false }
    $leaf = Split-Path $rel -Leaf
    if ($rel.StartsWith('Data\Platform\PluginsNoLoad\', 'OrdinalIgnoreCase')) { return $true }
    if ($leaf -like '*.bak') { return $true }
    # In Plugins only our overlays belong. The bundle is ours by record above.
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

# One machine's own, never shipped and never listed as removed. Other servers'
# files count as the machine's here, so a release never strips another
# server's install off a tester.
function Test-ShipMachine([string]$rel) {
    if (Test-ShipOtherServer $rel) { return $true }
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

# Where this build's reference plugins.txt and loadorder.txt are read from.
#   no Root\Game         the Steam copy: Vortex writes them into AppData
#   an own folder        Profile\OwnGame: the Vortex profile's lists as of the
#                        folder's last update, which is the collection's order
#   an older Root\Game   Profile\Default. AppData is only this build's while
#                        the game runs, so reading it with the game closed
#                        shipped the ordinary Skyrim's list.
function Get-ShipLoadOrderDir([string]$Root, [string]$ProfileDir) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'Game'))) {
        return (Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition')
    }
    $own = Join-Path $ProfileDir 'OwnGame'
    if (Test-Path -LiteralPath (Join-Path $own 'plugins.txt')) { return $own }
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
    'Data\Platform\voice-token.txt'
)

function Get-ShipDeleteAlways { return $ShipDeleteAlways }
