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
      Test-ShipBethesda $rel       Bethesda's by any of the three rules above (vanilla, Creation Kit, left alone); never packed, recorded or on the site
      Test-ShipOneMachine $rel     one machine's own by kind (runtime state, logs, session and token files, backups, face exports,
                                   Vortex's records, window layouts, settings saved from a mod's menu, saves); never packed, recorded or on the site
      Get-ShipOwnGameCollection    the collection's files in a Game folder the launcher made; never shipped
      Get-ShipGeneratedFiles       what Build-Generated.ps1 made in that folder; shipped, even where Vortex deploys the same path
      Get-ShipLooseArt $files      loose textures and meshes an installer carries that are not ours, by folder
      Test-ShipNotOurs $rel        another author's loose file (outside Data\Platform, not named ours); never packed, recorded or listed as removed
      Test-ShipOurs $rel           ours outside Data\Platform: the named files, the client runtime, required data, the menu, Nemesis's output, the BodySlide builds until #1259
      Test-ShipHeld $rel           a loose file that ships until the collection revision that carries its mod
      Get-ShipCollectionRevision   the revision a release is built against, for $ShipCollectionRevision
      Get-ShipLoadOrderDir         where the reference plugins.txt and loadorder.txt are read from
      Get-ShipRequiredDataRoot     game\required-data in the repo
      Ensure-ShipRequiredData      place those files into Data\ before a pack or installer scan
      Get-ShipSymbolDir            where this machine keeps launcher/setup .pdb per version (#462)
      Save-ShipSymbols             copy .pdb from a build folder into Get-ShipSymbolDir
      Get-ShipUiHashedAssets       hashed asset names parsed from Data\Platform\UI\build.js
      Save-ShipUiHashedAssets      parse, refuse a bad front, write thornswood-ui-assets.txt

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
    # The game asking the launcher for a join token, "<profile id> <time>"
    # (#1322). One person's profile id, so never in a pack.
    'Data\Platform\voice-token-ask.txt',
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

# ANOTHER SERVER'S MENU UNDER Data\Platform\UI, issue #1318.
#
# 37 files from Daedric Online's menu (11 jpg, 22 png, 3 EB Garamond ttf,
# menu_theme.mp3) sat on the shipping machine and went out in every installer
# and pack with no licence. Nothing in this repository names them: build.js
# names none, and nothing else under Data\Platform does. Djinn, 9 Oct: remove
# them for good. They never ship, and every pack deletes them from installs.
# Matched by sha256 as well as by name, so a renamed copy still counts.
#
# The 41 unused skymp5-front svgs and bg.png beside them (the old "42 more
# files" row in THIRD-PARTY.md) are dead weight too: build.js names none of
# them. They stop shipping and every pack deletes them from installs as well.
#
# WHAT IS OURS UNDER UI. Only index.html, build.js, thornswood-* files, and
# the hashed assets build.js actually names. That last list is parsed from
# build.js at ship time, never kept by hand. OwnGame.Foreign reads the list
# Ship wrote into the pack rather than parsing build.js itself.
$ShipUiAssetsRel = 'Data\Platform\UI\thornswood-ui-assets.txt'
$ShipUiHashedPattern = '^[0-9a-f]{8,32}\.(ttf|woff2?|eot|otf|svg|png|jpe?g|gif|wav|mp3|ogg|webp)$'
$ShipDaedricMenu = [ordered]@{
    '0d38fd98ca293be5d0c8270fef9dedef.jpg' = 'db23cb612c7f5d8f00b8a6858028363604630c6c7c20ee80aa1e37ab8b1a47de'
    '4ea8bf5739be06e0e5fd161f6adf5850.jpg' = '9d45803fd5fecc6c14a40858c556ee5f968835132bb78f87578ae7aab4e96d8d'
    '543e3fee1044af120d75105ac3090557.jpg' = 'e001643d7f536072979a3bc67401986dcbda83d03339e859fb782a5862769e82'
    '81ee50861a303d1214780abc71e65f36.jpg' = '0b527774e24ebeb7ed3de3ef50d09bea7f7a1b8d639fb6f18faa84a769d274b1'
    '882dbfc52ca85fc4c1486db71e04d6fa.jpg' = '9b9eb591a53fade9cb073a0a7238f84fb9053cac5a127712a58c2b1371214b90'
    '9edb4981b4e1caf812b103f6b18fe36b.jpg' = '18d66277cc8461873974097a78903de69626c418dda1cf150ea4f8e20a6b6240'
    '9f0ea8f110dda78dbd424958dba41499.jpg' = 'c647b33bde2288793eab104dd3752da369ec7b6c9dc608b059616b30ede66e5d'
    'b0b5cadd68447e59256eca2044991ec3.jpg' = 'c7314f95cc9250753e0e2c6490509f127ffe63f563d7b03d8de959807050ebd8'
    'c2553ded19b6fb3ac56596fe739d612b.jpg' = 'ec612213dd938977b28044687392a5be48c8cda33f895179bee1233557ab5966'
    'd17e16ae17f0fe4dd33cf43287b68abb.jpg' = 'bf53662fa447171fe9b8dd3f1c0d858efabb96c694949c9af9f1962daf58b92f'
    'e51c5bdb8dcc1edee4cbb35900069a03.jpg' = '00a0e140bef06fe7d2b66b0e4038df2c47b5483e93ca83649fee6c54887e3752'
    '03cc9ca1acc21fa6f1c6ad5101cb255b.png' = 'd0bf7e48a1dc87b87bf964ff12c54d373b15d5ce68fa2c110d8f1d382a9aff49'
    '0dfec5cc5038b6094389cef8a50a200e.png' = 'f93ebd4a38b4cee40875a611586d4e0bc6f684a63fe61bb6924a54ec7521dcf4'
    '299434de78bbe21ea23041b1be92c39c.png' = '91bc44651e620258cb4b260d2ee7d718489c7508cb3dd234e2969c369632e1c8'
    '3004f7ad71899c0c42f508d4a4d9df7b.png' = '24bc277750c76a9da9ae038f243910b3eb03712529f77e1218930affdfddb0f0'
    '3b1d9dfd8b928e7bb7893bb6a2439afd.png' = '48d86b3fd3e28ec7b2fb28eecb8710efa39374ffa95dffdcbb6dab1757e7e435'
    '531ab2fd197a8b7acf53b5594b5e3223.png' = '7810d7763757cb4b27b35113e101cf925c11a1dec8fbc0cc8cb5a3a5f4c9e9cd'
    '55dfe7f22c8cab4da857e10ea3820725.png' = '1da66efd2a41475496a1f77a40326e184717ea3f396db934498e8f775d1b4dda'
    '5b5bd6bfddd68f3d5fb254fff3ecefef.png' = '3aacd4c089e7f1d036fb2ee0f98a237f4a367392c73819fdd49bf4905695ff15'
    '664fcb4f7edc8048f19d08b72f6c7c6d.png' = '566cfbbfb305b3c264a3cab42c8a7a547a9eeaafc7ccc417d98a0c41e7cbb44d'
    '68f6bf41b5670b32dae78a7e644964e7.png' = '3027e506327e23f583dd9657e3cd23fbc3878384c76cb123e54876e052f1ab86'
    '8ec57d93ee70da82e4128e716bddba0c.png' = '3ae73232f1013f3e612281c44c1d11e503ec644c4b8bff2a8a4392def4cfbe6f'
    '98fcc009b62a2e309130443063d085bf.png' = 'b5ed1d771d1a1029413f1b1c9ab8d7877e0c380b095a6ca6ac4b5fe685df88f2'
    'a1d63d44016df48a54babe9b0329da61.png' = '0ac842420b623b9a95abfeb3658b9779256dd5df8f390c69c14fcba0265e35e1'
    'a793e924a98f7a40a7113d3e1d481c9c.png' = '8dcaca85e00028ba5a6306e6cdf9d4106ecb7279a6005f29c28314a1bcda7798'
    'b5016b511dd0fb0aaecd2255c5e15379.png' = '624d1cec7aed10aa4b28d7161ef603bf813a00b4730950adc61c9b13cead1b51'
    'b8d955f710cb2ae0d86a37cc8563066f.png' = 'adda08dd375ebc21b5be6fc88f22634935a60457dea49046b6b24300d1a6e525'
    'c26ab06b79e8861ebaff50361d502013.png' = '6058166128889ca66c8b872f8d874ace0c81a4b17352ab39aeb220f76b853192'
    'c608839467d2011b9dc04e5a9ffd8782.png' = '7cfb96be3427eb70ac225fa573ff738adf5f0022f1d5da51b24f39d911d4f596'
    'dd0aadf615113abf5856ed58cd528087.png' = '7466023e1baa4e37f8d628d3086068e966e55319636f79fadf1805e3f08729ad'
    'e0ca10b6276b6f88d5dcf37c0de4cddf.png' = '8647239617c0a9aad2d11213e2723e7a55a0a7f15dc7ad250e9bee0e77c098af'
    'e737d42dda1e949d34fc0514a0db3b5d.png' = 'e79311c0af2a03423b0216a272096f6fd97c786838a0a28a032c6b3bafc05225'
    'f314576d391b3aca3bb958d74b09f4c8.png' = 'd6e5e584d56c6325db8b41d6b14f96e20ecd2ea046052f15c8df3203d148c126'
    '02732f42edb584062268.ttf' = '934aa932b4bc1a75d883f7c3d4d5bbc8278e5e7fcc96d5440bbffd61050cf958'
    '0418ecf95d39d9473390.ttf' = 'b536adfa0f5746cfbd148d8a1a669540366edef2c85c4b49450798a037bd928c'
    'ef857eb378108590f849.ttf' = '9d2ca86044b885d085059c7e3bed21d6e31456a81a47761e7ade8cd390ebe71d'
    'menu_theme.mp3' = 'eda338afc99c53926ecd3a1479127689928ff734b96f6a24bd53649b587bd3f4'
}
$ShipDaedricMenuHashes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($h in $ShipDaedricMenu.Values) { [void]$ShipDaedricMenuHashes.Add($h) }
$ShipUnusedFrontAssets = @(
    '012ba60b5cafa40f9e478f978761f33d.svg'
    '05bc1c771a7f9d9fa958eab5889558f7.svg'
    '06a298c40e1d6dc99a81d63276ee6161.svg'
    '07863f7f6cd3e41d2d4dd98555709017.svg'
    '0acb800c49cbe871dacdb686546aa5de.svg'
    '1f08438ecd0badfb463bbfa1b6a00b70.svg'
    '29359f1c6135098e82121dce53128a35.svg'
    '293db3d76ab19fe8228fec890f8054c0.svg'
    '2d45d5f75c74bbf47f231dd420bb50e4.svg'
    '34d7c23d97684ec11c66319566850bee.svg'
    '4240b22a3e4ea3d863083d8cc66dc9d2.svg'
    '434474aac1ca25361cc7f9fadc87043a.svg'
    '45255c99ec0c0f37fbadb45928198869.svg'
    '46e7c235111fa294ae294e52361b1a64.svg'
    '5183d83cbcb7262bc8ce4325c6b83ab1.svg'
    '51d5d9ae7e81b615957cd01b3775d915.svg'
    '5c2874217cce8f12078a4c478c7760a8.svg'
    '615881216ef2ce0dd5609a3cd7f32a26.svg'
    '70828fb0d81d34baf7216b141e84512a.svg'
    '7368c872f5c628c86f6a52fbd83e5e36.svg'
    '76cbeb799fc98908a589dfcf1b0df4c6.svg'
    '79a2d684ce0ce231b4fc4ae00462abbd.svg'
    '8725285acc017513ed15441d664312d7.svg'
    '95ef521334d6e74aca76d7ef28fd11a7.svg'
    '9c26de6addf1f2d8b12b6002ae854b95.svg'
    '9daf4db75b4c8a2bb5a817f052e4d7a9.svg'
    'a13807eed63afde04cb7be12e93604c6.svg'
    'a72e8754c0389c9050a7ff03a97c8913.svg'
    'ad1f817dd17374e2bd7486b3a5ac47a8.svg'
    'b2422b6faed4209b53b16946877b5d52.svg'
    'b504fd8bc5ee0f86635573d4a74b9778.svg'
    'ba7f86afe59d769feb36fbaa88a5faca.svg'
    'c3f0ce7307ae5d17c8a0a6faedb739fe.svg'
    'c5ce282718fc847f993170a705c22125.svg'
    'c607cf803e8ca2a885e1bd6141999c6d.svg'
    'c97f9a61534aa6adb5ce52e0a909f328.svg'
    'cb339e63ba0a96c297fad9db03e15565.svg'
    'cf57e7f8f09ad647e4cd6be3c8b70ebe.svg'
    'd016f173d0d647e6cbe4c46ee74abb05.svg'
    'ef92c2ecafd152e547c2f9296ce6956a.svg'
    'fb344395b65fad4dc9b2b4dbecaaf9ae.svg'
    'bg.png'
)
$ShipUiGoneLeaves = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($n in $ShipDaedricMenu.Keys) { [void]$ShipUiGoneLeaves.Add($n) }
foreach ($n in $ShipUnusedFrontAssets) { [void]$ShipUiGoneLeaves.Add($n) }

function Get-ShipFileSha256([string]$full) {
    if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { return '' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fs = New-Object IO.FileStream($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { return ([BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-', '').ToLowerInvariant() }
        finally { $fs.Dispose() }
    }
    finally { $sha.Dispose() }
}

# Quoted strings in build.js that name a file with an asset extension. Bare
# hashed names are kept. Anything with a slash, '..', or a rooted/drive path
# refuses the ship, naming the entry. Other quoted strings are ignored.
function Read-ShipUiHashedAssetsFromText([string]$text) {
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $assetExt = '\.(?:ttf|woff2?|eot|otf|svg|png|jpe?g|gif|wav|mp3|ogg|webp)(?:\?[^"]*)?$'
    foreach ($m in [regex]::Matches($text, '"((?:[^"\\]|\\.)*)"')) {
        $s = $m.Groups[1].Value.Replace('\/', '/').Replace('\\', '\')
        if ($s -notmatch $assetExt) { continue }
        $q = $s.IndexOf('?')
        if ($q -ge 0) { $s = $s.Substring(0, $q) }
        $rooted = $s.StartsWith('/') -or $s.StartsWith('\') -or ($s.Length -ge 2 -and $s[1] -eq [char]':')
        $dots = $s -match '(^|[\\/])\.\.($|[\\/])'
        if ($rooted -or $dots -or $s.Contains('/') -or $s.Contains('\')) {
            throw ("build.js names '{0}', which is not a bare hashed asset (slash, '..', or a rooted path). Nothing was packed." -f $s)
        }
        if ($s -notmatch $ShipUiHashedPattern) { continue }
        [void]$names.Add($s)
    }
    return $names
}

$script:ShipUiHashedCacheKey = ''
$script:ShipUiHashedCache = $null
$script:ShipUiHashedGameDir = $null
$script:ShipUiHashedWritten = @()

function Get-ShipUiBuildJsPath {
    $game = $script:ShipUiHashedGameDir
    if (-not $game) {
        $game = Get-Variable -Name GameDir -ValueOnly -ErrorAction SilentlyContinue
    }
    if (-not $game) { return '' }
    return Join-Path ([string]$game) 'Data\Platform\UI\build.js'
}

# The hashed asset names build.js names, parsed at ship time. Empty when there
# is no GameDir or no build.js, so a unit test that only asks a path still
# runs. A bad path in build.js throws, which is how a ship is refused.
function Get-ShipUiHashedAssets {
    $build = Get-ShipUiBuildJsPath
    if (-not $build -or -not (Test-Path -LiteralPath $build -PathType Leaf)) {
        return @()
    }
    $item = Get-Item -LiteralPath $build
    $key = '{0}|{1}|{2}' -f $item.FullName, $item.Length, $item.LastWriteTimeUtc.Ticks
    if ($script:ShipUiHashedCacheKey -eq $key -and $null -ne $script:ShipUiHashedCache) {
        return $script:ShipUiHashedCache
    }
    $set = Read-ShipUiHashedAssetsFromText ([IO.File]::ReadAllText($build))
    $script:ShipUiHashedCache = @($set)
    $script:ShipUiHashedCacheKey = $key
    return $script:ShipUiHashedCache
}

function Test-ShipUiHashedAssetName([string]$leaf) {
    return [bool]($leaf -and ($leaf -match $ShipUiHashedPattern))
}

# Ours under Data\Platform\UI: index.html, build.js, thornswood-* files, and
# hashed assets build.js named. Everything else flat or nested is not ours.
function Test-ShipUiOurs([string]$rel, [string]$leaf) {
    if ($leaf -ieq 'index.html' -or $leaf -ieq 'build.js') { return $true }
    if ($leaf -like 'thornswood-*') { return $true }
    if (Test-ShipUiHashedAssetName $leaf) {
        foreach ($n in @(Get-ShipUiHashedAssets)) { if ($n -ieq $leaf) { return $true } }
    }
    return $false
}

function Test-ShipUiGoneByHash([string]$rel) {
    $game = Get-Variable -Name GameDir -ValueOnly -ErrorAction SilentlyContinue
    if (-not $game) { return $false }
    $full = Join-Path ([string]$game) $rel
    $have = Get-ShipFileSha256 $full
    if (-not $have) { return $false }
    return $ShipDaedricMenuHashes.Contains($have)
}

# Ship-time guard: parse build.js, refuse on zero names, refuse if a named
# file is missing, refuse a bad path (Read-ShipUiHashedAssetsFromText throws).
# Writes the parsed names into Data\Platform\UI\thornswood-ui-assets.txt so
# the pack carries them and OwnGame.Foreign can read them.
function Save-ShipUiHashedAssets([string]$GameFolder) {
    if (-not $GameFolder) { throw 'Save-ShipUiHashedAssets needs the game folder.' }
    $savedParse = $script:ShipUiHashedGameDir
    $script:ShipUiHashedGameDir = $GameFolder
    $savedGame = Get-Variable -Name GameDir -ValueOnly -ErrorAction SilentlyContinue
    $GameDir = $GameFolder
    try {
        $build = Join-Path $GameFolder 'Data\Platform\UI\build.js'
        if (-not (Test-Path -LiteralPath $build -PathType Leaf)) {
            throw 'Data\Platform\UI\build.js is missing, so the front''s hashed assets cannot be derived. Nothing was packed.'
        }
        $script:ShipUiHashedCacheKey = ''
        $script:ShipUiHashedCache = $null
        $names = @(Get-ShipUiHashedAssets)
        if ($names.Count -eq 0) {
            throw 'build.js named no hashed assets, so the parse is wrong or the front is empty. Nothing was packed.'
        }
        $ui = Join-Path $GameFolder 'Data\Platform\UI'
        foreach ($n in $names) {
            $at = Join-Path $ui $n
            if (-not (Test-Path -LiteralPath $at -PathType Leaf)) {
                throw ("build.js names '{0}', which is not in Data\Platform\UI. Nothing was packed." -f $n)
            }
        }
        $sorted = @($names | Sort-Object { $_.ToLowerInvariant() })
        $lines = New-Object 'System.Collections.Generic.List[string]'
        [void]$lines.Add('# Hashed assets Data\Platform\UI\build.js named. Written by Ship at pack time (#1318).')
        [void]$lines.Add('# One bare file name per line. OwnGame.Foreign reads this rather than parsing build.js.')
        foreach ($n in $sorted) { [void]$lines.Add($n) }
        $out = Join-Path $GameFolder $ShipUiAssetsRel
        [IO.File]::WriteAllLines($out, $lines)
        $script:ShipUiHashedWritten = $sorted
        return $sorted
    }
    finally {
        $script:ShipUiHashedGameDir = $savedParse
        if ($null -ne $savedGame) { $GameDir = $savedGame }
        else { Remove-Variable -Name GameDir -ErrorAction SilentlyContinue }
    }
}

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
    # Elysium Estate 4.3.5's plugin, issue #690: the servers load the
    # collection's ElysiumEstate.esp since 29 September, and every pack deletes
    # this name (see $ShipDeleteAlways). OwnGame.Foreign carries the same rule;
    # change the two together.
    if ($rel -ieq 'Data\ElysiumEstateSSE.esp') { return $true }
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
    # Under UI, ours is only index.html, build.js, thornswood-* files, and
    # the hashed assets build.js names (parsed at ship time, #1318). Nested
    # paths, another menu's Vite files, the Daedric set, the unused fork
    # svgs and bg.png, and any unnamed flat file are not ours. A renamed
    # copy of the Daedric set still counts, by sha256. The first version of
    # this rule on 20 September whitelisted three names and called the
    # front's own hashed files foreign; the 13:02 dev Ship left them out.
    # The next version treated every flat file as ours, which is how the 37
    # slipped through.
    if ($rel -like 'Data\Platform\UI\*') {
        $rest = $rel.Substring('Data\Platform\UI\'.Length)
        if ($rest.Contains('\') -or $rest.Contains('/')) { return $true }
        if ($leaf -ieq 'app.js' -or $leaf -ieq 'vite.svg') { return $true }
        if ($ShipUiGoneLeaves.Contains($leaf)) { return $true }
        if (Test-ShipUiGoneByHash $rel) { return $true }
        if (Test-ShipUiOurs $rel $leaf) { return $false }
        return $true
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
# on its own it is 356 MB. Nemesis, FNIS, BodySlide, xEdit and Pandora (the
# behavior engine from collection revision 2, #1247, in the folder of its own
# the collection gives it and its Pandora_Engine patch folder) are tools that
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
    'Pandora Behaviour Engine', 'Pandora_Engine',
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

# BETHESDA'S, ASKED ONE WAY EVERYWHERE (#1229). The game and its archives
# (Test-ShipVanilla), the Creation Kit, its script sources and copies of the
# game's programs (Test-ShipBethesdaTool), and Bethesda's files a pack once
# carried (Test-ShipBethesdaLeftAlone, MarketplaceTextures.bsa). Check-Secrets
# asked all three; the record guard in Publish-Update and the rollback filter in
# Rollback-Feed asked only the first two, so a record naming
# MarketplaceTextures.bsa, as a file or as gone, went through both. Every place
# that asks whether a path is Bethesda's asks this, so they cannot drift again;
# Scrub-Feed.ps1 takes exactly these out of what is already on the site.
# The launcher's own folder is the other side of it and keeps
# MarketplaceTextures.bsa: SkyrimSE.exe opens it by name (two references in the
# 1.6.1170 exe, read 29 September), so there it is the game's own file, like
# Skyrim.esm, and never one of the Creation Kit's that OwnGame.BethesdaTool
# drops. Measured the same day, no pack, record or loose file on the site names
# it.
function Test-ShipBethesda([string]$rel) {
    return ((Test-ShipBethesdaTool $rel) -or (Test-ShipVanilla $rel) -or (Test-ShipBethesdaLeftAlone $rel))
}

# ---------------------------------------------------------------------------
# ONE MACHINE'S OWN FILES, BY KIND (#1239).
#
# A file of the build is the same bytes on every install: a mod's plugin, its
# meshes, our overlays, the client. A file of one machine is whatever the game,
# a mod, the launcher, Vortex or a session wrote on the machine that ships,
# about that machine: who is signed in, what it last played, its screen, its
# key binds, where its windows sat, what its Vortex deployed. Handed to
# everybody it is at best dead weight and at worst one person's token or
# settings on every install.
#
# Until this rule the question was a list of names ($ShipMachineFiles), and a
# name nobody had added went out. MEASURED 29 September over HTTPS, every pack
# and record both feeds name: the join pass the launcher writes for the game
# server (Data\Platform\thornswood-pass.txt, #937) was in dev packs
# 20260928-2131-dev and 20260929-122410-dev and in four dev records, because it
# arrived after the list did; Data\MCM\Settings\Precision.ini,
# TrueDirectionalMovement.ini and TrueHUD.ini (the values a person saved in
# those mods' menus, two of them another server's) were in all five dev
# records, so a launcher that syncs to the record fetched them; and so were
# CommunityShaders\SettingsUser.json, two window layout files, the spot
# marker's output and a hang report. So it is asked by KIND now, and a new
# file of one of these kinds is caught the day it appears:
#
#   - Written at runtime into a folder of its own (Test-ShipRuntime above):
#     Claude outputs, _to_delete, RaceMenu's face exports and face tints,
#     .sentry-native.
#   - The named files in $ShipMachineFiles above: SkyrimPlatform.ini, the
#     launcher's Thornswood.ini, the display, crash and animation settings the
#     launcher or the mod writes back.
#   - Anything straight in Data\Platform. That is where the launcher and the
#     plugins talk to each other while the game runs: the session note, the
#     join pass, the voice port, status and token, the character list and the
#     pick, the load order the game saw, the spots file, the plugins' logs.
#     Every file the build ships under Data\Platform is in a folder (Plugins,
#     UI, Modules, Distribution, Fonts, Images); nothing ships straight in it.
#   - The SkyMP client's saved sign in, Data\Platform\PluginsNoLoad.
#   - Logs and crash dumps (*.log, *.dmp), anywhere.
#   - Backups (Test-ShipBackup, *.bak) and Vortex's own records: its
#     deployment manifests, the *.vortex_backup files it moved aside and the
#     __folder_managed_by_vortex markers. They describe THIS Skyrim, and
#     handing them to somebody else's Vortex is how it loses track of its own
#     deployment; pack-20260916-1217 carried a 6 MB vortex.deployment.json.
#   - Window layouts Dear ImGui writes on exit, imgui.ini and <mod>_ImGui.ini:
#     where each window sat on that screen.
#   - What a person saved from a mod's own menu: Data\MCM\Settings (MCM Helper
#     writes a mod's ini there the first time somebody changes a value; the
#     mod's own defaults are in Data\MCM\Config and ship), and Community
#     Shaders' SettingsUser.json and SettingsTest.json (its defaults,
#     SettingsDefault.json, are the same on every install and stay).
#     CHECKED 29 September that none of the ones the site carried is a setting
#     Thornswood chose. Nothing in the repository writes, holds or names them
#     (no file under game\, no script, no launcher Enforce rule, no decision on
#     an issue). Precision.ini and TrueDirectionalMovement.ini open with "Daedric
#     Online, enforced ..." and were written into the Steam copy on 14 September
#     at 15:00 and 14:56, TrueHUD.ini at 14:43 in the same session, all before
#     Thornswood's first pack (15 September); they were never in a pack, and
#     reached people through the installer and the dev records. The launcher
#     takes what the dev records handed out back out of Thornswood's own
#     folder while it is still those bytes (Leaks.cs, #1252). Community
#     Shaders' SettingsUser.json was written on 19 September at the end of its
#     first time setup on one machine (FirstTimeSetupCompleted, one effect off
#     at boot, beside a window layout for a 2560x1440 screen), rode in one dev
#     pack (20260928-1733-dev), and Community Shaders is in neither the
#     repository nor the shipping machine's game today. A setting Thornswood
#     wants everybody to have is Thornswood's own file (the Thornswood Content
#     mod, or a launcher Enforce rule), never one machine's saved menu file.
#   - Saves and profiles: a Saves folder, *.ess and *.skse, and a Profile or
#     My Games folder at the top of the game folder.
#   - ShaderCache, anywhere: rebuilt by the game on first launch for that GPU.
#
# NOT one machine's, and never caught here: the six client files in
# client-build.json (ours by recorded bytes), SkyHUD's skyhud.txt (its own
# config), SkyUI's config.shipped.txt (the launcher's copy of the settings the
# build ships), and TrueHUD\RP_Bosses.ini, which is another server's file
# ("Daedric Online boss health bars", written with the two above) and so a
# question of whose it is, not of which machine (#1253).
#
# Never packed, never in a record (as a file or as gone), and never on the site:
# Publish-Update's scan and the installer's leave them out through
# Test-ShipMachine, which asks this; Publish-Update's record guard and
# Rollback-Feed's filter refuse them; Check-Secrets fails a pack or a stage that
# carries one; Scrub-Feed.ps1 takes them out of what is already published.
#
# NEVER LISTED AS REMOVED, except the runtime folders, which Publish-Update lists
# as removed when a baseline once had them (see $ShipRuntimeDirs), and the
# paths on $ShipDeleteAlways below, which every pack deletes on purpose. A
# delete reaches every install, and every one of these is that person's own file
# on theirs: their key binds, their Vortex, their face.
$ShipOneMachineFiles = @(
    'Data\SKSE\Plugins\CommunityShaders\SettingsUser.json',
    'Data\SKSE\Plugins\CommunityShaders\SettingsTest.json'
)

function Test-ShipOneMachine([string]$rel) {
    if (-not $rel) { return $false }
    if ($ShipClientFiles.Contains($rel)) { return $false }
    if (Test-ShipRuntime $rel) { return $true }
    foreach ($f in $ShipMachineFiles) { if ($rel -ieq $f) { return $true } }
    foreach ($f in $ShipOneMachineFiles) { if ($rel -ieq $f) { return $true } }
    $parts = $rel -split '\\'
    $leaf = $parts[$parts.Count - 1]
    if ($parts.Count -eq 3 -and $parts[0] -ieq 'Data' -and $parts[1] -ieq 'Platform' -and $leaf) { return $true }
    if ($rel.StartsWith('Data\Platform\PluginsNoLoad\', 'OrdinalIgnoreCase')) { return $true }
    if ($leaf -match '\.(log|dmp)$') { return $true }
    if (Test-ShipBackup $rel) { return $true }
    if ($leaf -ieq 'vortex.deployment.json' -or $leaf -like 'vortex.deployment.*.json') { return $true }
    if ($leaf -ieq '__folder_managed_by_vortex') { return $true }
    if ($leaf -like '*.vortex_backup') { return $true }
    if ($leaf -ieq 'imgui.ini' -or $leaf -like '*_ImGui.ini') { return $true }
    if ($rel.StartsWith('Data\MCM\Settings\', 'OrdinalIgnoreCase')) { return $true }
    if ($leaf -match '\.(ess|skse)$') { return $true }
    if ($rel -match '(^|\\)(Saves|ShaderCache)\\') { return $true }
    if ($rel -match '^(Profile|My Games)\\') { return $true }
    return $false
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
    # One machine's own by kind (#1239), the named files and Vortex's records
    # among them. The runtime folders are the one kind left to Test-ShipRuntime,
    # which lists them as removed when a baseline once had them.
    if ((Test-ShipOneMachine $rel) -and -not (Test-ShipRuntime $rel)) { return $true }
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
# Except what scripts\mods\Build-Generated.ps1 built in the folder (#1247):
# the behavior files Pandora makes and the BodySlide bodies are Thornswood's and
# ship, though several sit where Vortex deploys a file of the same name
# (Vortex's 3BA body, a mod's own behavior file), and files.txt goes on
# saying V for those paths. Get-ShipGeneratedFiles reads its record.
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
    foreach ($rel in (Get-ShipGeneratedFiles $ProfileDir)) { [void]$set.Remove($rel) }
    return ,$set
}

# The files Build-Generated.ps1 made in Thornswood's own folder, by its record
# Profile\OwnGame\generated.txt ("file <sha256> <path>" lines; the rest of the
# record is scripts\mods\Generated.ps1's). None when it has never run here.
function Get-ShipGeneratedFiles([string]$ProfileDir) {
    $record = Join-Path $ProfileDir 'OwnGame\generated.txt'
    $l = New-Object 'System.Collections.Generic.List[string]'
    if (-not (Test-Path -LiteralPath $record)) { return ,$l }
    foreach ($line in [IO.File]::ReadLines($record)) {
        $m = [regex]::Match($line, '^file [0-9a-f]{64} (.+)$')
        if ($m.Success) { $l.Add($m.Groups[1].Value.Replace('/', '\')) }
    }
    return ,$l
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
# Since #1178 (29 September) Test-ShipNotOurs below keeps unaccounted-for files
# out of packs, records and the installer, so this report should name nothing.
# It stays as the alarm: a row here means a file reached what is about to ship
# that the rule did not stop. Generated behavior files and BodySlide bodies
# are Thornswood's by their generated record (#1247), rather than loose art.
#
# Ours is the main menu backdrop: the three files Go.ps1 writes from
# game\menu ($menuPairs there; change the two together).
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
    $rows = @{}
    foreach ($f in @($files)) {
        if ($null -eq $f) { continue }
        $rel = [string]$f.Rel
        if (Test-ShipOurs $rel) { continue }
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

# ---------------------------------------------------------------------------
# OTHER PEOPLE'S LOOSE FILES NEVER SHIP. Issue #1178.
#
# Outside Data\Platform a file of the game folder is ours only when this list
# names it. Everything else that Vortex did not deploy is somebody else's mod
# file, and handing it out is not ours to do: never packed, never in the
# installer, never in a release record, and never listed as removed.
# Data\Platform is Test-ShipOtherServer's, which already names what is ours
# there; the collection's files are left out by Get-ShipOwnGameCollection.
#
# MEASURED 29 September over the installer's payload (C:\Thornswood\Game), the
# dev build's (C:\Thornswood-DevBuild\Game), the dev record 20260929-140118-dev
# and the last main record (20260928-1630): 424 loose files of other people's
# mods outside Data\Platform, 124.7 MB (the installer 409 of them, 116.9 MB).
# 181 (75.1 MB) leave now, 103 (8.4 MB) wait for revision 2 and 140 (41.2 MB)
# BodySlide builds ship as ours for now until #1259 (both below). All
# were in Profile\OwnGame\files.txt with origin O (taken from the Steam copy,
# never deployed by Vortex), most put there by the old installer
# (Profile\installed-into-game.txt), so the old rules called them ours. Each
# was matched by path and sha256 against every
# mod in this machine's Vortex staging, loose and inside its archives, and
# against the game's own archives. What they were, by group
# (docs\COLLECTION-REVISION-2.md has the table):
#   - RaceMenu's interface and translations (21 files), byte for byte the
#     files inside the collection's RaceMenu.bsa; 30 of the travel clothes, the
#     Skyrim Sewers countess and an Elysium Estate texture, the same inside
#     their mods' archives. The collection installs all of them.
#   - 26 of Bethesda's own files, byte for byte the ones in the game's archives
#     (draugr, vampire lord, werewolf and Soul Cairn meshes, notes, a Creation
#     Club script), and the Creation Kit's face tint export for
#     FishingInSkyrim.esp.
#   - BodySlide output built on some other machine, for a body and preset
#     nothing records: Immersive Armours' Bosmer armour, the travel clothes
#     (Common Clothes and Armors 3BA), More Craftable Equipment's executioner,
#     Capital Windhelm's and Crossed Daggers' outfits. Generated output is ours
#     only when we generate it from the collection, as Nemesis's is below.
#     The first three ship as ours for now, until Thornswood builds them
#     itself (#1259, $ShipBuiltUntil1259); the refits of the last two leave.
#   - Files of Nexus mods the collection does not have yet: male face and
#     beard morphs, fitted vanilla hoods and robes, children's clothes, a mesh
#     fix. Held below until revision 2 carries them.
#   - Leftovers of mods nothing loads: Mage Clothing Expansion, Common
#     Clothing Expansion, Armory of the Dragon Cult, Armors of the Velothi,
#     NordwarUA's armour, Capital Whiterun's outfits, IED's script without IED,
#     Unofficial Patch and interior mods' scripts without their plugins, old
#     MCM Helper scripts that override the collection's newer ones, and
#     retextures with no mod found.
#   - Another server's files: Keizaal's kzl_haybale.nif, Daedric Online's
#     TrueHUD boss list (RP_Bosses.ini, "Daedric Online boss health bars" by
#     its first line; Patrick, 29 September, #1253: it goes).
#   - Settings a mod or the launcher writes on each machine: ImGui window state,
#     Community Shaders' settings, SkyUI's config copy the launcher keeps.
#
# WHY A LIST OF OURS AND NOT A LIST OF THEIRS. Every rule above that names
# another author's file was written after that file had shipped. A list of
# theirs is one incident behind for ever; a list of ours is right the day it
# is written, and a new file of ours is one line here in the pull request that
# adds it (tests\test-not-ours.ps1 holds the list to the files that ship).
#
# NEVER LISTED AS REMOVED, ON PURPOSE (Test-ShipMachine asks this). A pack's
# delete.txt reaches every launcher, and on an install with no game folder of
# its own it deletes from the Steam copy, where the same path may be the
# person's own Vortex deployment. Installs that already took one of these keep
# it until Patrick decides otherwise; published packs are scrubbed apart
# (Scrub-Feed.ps1).
$ShipOursFiles = @(
    # Our completed plugin ships on both channels beyond the collection base.
    'Data\Thornswood-Content.esp',
    # The SkyMP client's compiled script, from the engine fork.
    'Data\Scripts\MpClientPlugin.pex',
    # Our main menu: no Bethesda logo and no button list, an empty loading
    # spinner (Checks.cs, since 16 September), and the menu music's silent
    # stand in for the game's theme. Go.ps1 writes these four from
    # game\ours ($oursMenuFiles there; change the two together).
    'Data\Interface\startmenu.swf',
    'Data\Interface\loadwaitspinner.swf',
    'Data\music\special\mus_maintheme.xwm',
    # SkyHUD's settings as Thornswood set them (16 September, after the first
    # pack; no other server's header). The MCM Helper menu files beside it
    # were Daedric Online's by their own first lines and are one machine's
    # (#1239); TrueHUD\RP_Bosses.ini is Daedric Online's boss list (#1253), so
    # neither is named here.
    'Data\Interface\skyhud\skyhud.txt'
)

# NEMESIS'S OUTPUT IS OURS, because we generate it from the collection.
# Measured 29 September in Data\Nemesis_Engine\cache\mod settings: the patches
# chosen are Precision (Nexus 72347) and True Directional Movement's 360 Horse
# Archery, Procedural Leaning and Headtracking (Nexus 51614), all three mods in
# the collection, run by Nemesis 0.84 (Nexus 60033), also in it. Its last run,
# 10 September 19:36 (PatchLog.txt), wrote exactly the behaviour graphs, the
# two animation data files, the two character files and FNIS.pex below. No
# collection can run a generator, so nobody gets these but from us. A file at
# one of these paths from anywhere else would be Vortex's (the collection's) and
# is left out before this is asked.
$ShipGeneratedBodyFiles = @(
    # Exact body outputs from the committed covered-body recipe.
    'Data\meshes\actors\character\character assets\femalebody_0.nif',
    'Data\meshes\actors\character\character assets\femalebody_1.nif',
    'Data\meshes\actors\character\character assets\femalebodyastrid_0.nif',
    'Data\meshes\actors\character\character assets\femalebodyastrid_1.nif',
    'Data\meshes\actors\character\character assets\malebody_0.nif',
    'Data\meshes\actors\character\character assets\malebody_1.nif'
)
$ShipGeneratedPatterns = $ShipGeneratedBodyFiles + @(
    'Data\meshes\animationdatasinglefile.txt',
    'Data\meshes\animationsetdatasinglefile.txt',
    'Data\meshes\actors\*\behaviors\*.hkx',
    'Data\meshes\actors\*\characters\*.hkx',
    'Data\meshes\actors\*\characters female\*.hkx',
    'Data\Scripts\FNIS.pex'
)

# HELD UNTIL THE COLLECTION CARRIES THEM. A loose file whose mod is on Nexus
# and not yet in the collection still ships until the collection revision a
# release is built against reaches the one that adds the mod
# (docs\COLLECTION-REVISION-2.md, "Mods revision 2 adds"). Then it leaves by
# itself, the same release that tells every launcher on the older revision to
# update the collection. Path ends in \ for a folder.
#
# Traced 29 September by path against each mod's own file list on Nexus (the
# archives themselves were not downloaded, so these are matched by path, not by
# bytes). Revision 2 adds each mod (Claude Cowork's checklist says how, and
# stops if one brings a plugin, which would move the load order), and a person
# checks in game that nothing looks different.
function New-ShipHeld([string]$Path, [string]$Mod) {
    return [pscustomobject]@{ Path = $Path; Revision = 2; Mod = $Mod }
}
$ShipHeldForCollection = @(
    # Male faces' expressions and beards: Expressive Facial Animation - Male
    # Edition (Nexus 19532), 1.21. Expressive Facegen Morphs, in the
    # collection, carries only the chargen and race morphs beside these.
    (New-ShipHeld 'Data\meshes\actors\character\character assets\MaleHead.tri' 'Expressive Facial Animation - Male Edition (19532)'),
    (New-ShipHeld 'Data\meshes\actors\character\character assets\EyesMale.tri' 'Expressive Facial Animation - Male Edition (19532)'),
    (New-ShipHeld 'Data\meshes\actors\character\character assets\faceparts\' 'Expressive Facial Animation - Male Edition (19532)'),
    (New-ShipHeld 'Data\meshes\actors\character\character assets\mouth\' 'Expressive Facial Animation - Male Edition (19532)'),
    (New-ShipHeld 'Data\meshes\actors\character\character assets\beards\' 'Expressive Facial Animation - Male Edition (19532)'),
    # Vanilla women's hoods and the Creation Club fishing and apprentice robes
    # fitted to the body: CBBE 3BA Vanilla Outfits Redone (Nexus 109194), its
    # prebuilt meshes files.
    (New-ShipHeld 'Data\meshes\clothes\robemythicdawn\' 'CBBE 3BA Vanilla Outfits Redone (109194)'),
    (New-ShipHeld 'Data\meshes\clothes\thalmor\' 'CBBE 3BA Vanilla Outfits Redone (109194)'),
    (New-ShipHeld 'Data\meshes\creationclub\bgssse001\clothes\' 'CBBE 3BA Vanilla Outfits Redone (109194)'),
    # Children's clothes: Styles of Skyrim Mashups - Children Clothes
    # Variations and Mesh Fixes (Nexus 154063), Vanilla Mesh Fixes Standalone.
    (New-ShipHeld 'Data\meshes\clothes\childrenclothes\' 'Styles of Skyrim Mashups - Children Clothes Variations and Mesh Fixes (154063)'),
    (New-ShipHeld 'Data\meshes\_byoh\clothes\childrenclothesvariants\' 'Styles of Skyrim Mashups - Children Clothes Variations and Mesh Fixes (154063)'),
    # A noble end table's mesh fix: Assorted Mesh Fixes (Nexus 32117).
    (New-ShipHeld 'Data\meshes\furniture\noble\nobleendtable04.nif' 'Assorted Mesh Fixes (32117)'),
    # The message board Thornswood-Content.esp itself places, from the other
    # server's kzolivar records Patrick kept. Dev packs carry it (main never
    # has) and no mod in the collection has it at this path; a board of the
    # same name is in Missives - Unique Missive Boards (Nexus 111375, a quest
    # mod with a plugin of its own) at meshes\clutter\missives. Revision 2's
    # rebuilt Thornswood Content has to point its board at a mesh the
    # collection installs before this may leave.
    (New-ShipHeld 'Data\meshes\olivar-messageboard\missiveboardcotnd.nif' 'none yet: Thornswood Content must point its board at a mesh the collection installs')
)

# The collection revision this release is built against: what the feed's
# collectionRevision says. Publish-Update and Package-Thornswood set it
# (Get-ShipCollectionRevision); 0 when it is not known, and then everything held
# above still ships, so nothing leaves before the collection carries it.
$ShipCollectionRevision = 0

# The revision of the collection config.json names (or the one the launcher
# ships with), as this machine's Vortex has it installed. Needs LoadOrder.ps1,
# which the callers dot-source; 0 without it.
function Get-ShipCollectionRevision([string]$Root) {
    if (-not (Get-Command Get-CollectionRevision -ErrorAction SilentlyContinue)) { return 0 }
    $url = ''
    try { $url = [string](Get-Content -LiteralPath (Join-Path $Root 'config.json') -Raw | ConvertFrom-Json).CollectionUrl } catch { }
    if (-not $url) { $url = 'https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf' }
    return [int](Get-CollectionRevision (Get-CollectionSlug $url))
}

# Plugins game\required-data puts in Data\ before a scan (Ensure-ShipRequiredData).
# Worked out in a child scope: this file is dot-sourced into its callers, and
# a name set here would overwrite one of theirs.
$ShipRequiredDataFiles = @(& {
    try {
        $dir = Join-Path $PSScriptRoot '..\..\game\required-data'
        if (Test-Path -LiteralPath $dir) {
            Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -ne 'README.md' } | ForEach-Object { 'Data\' + $_.Name }
        }
    } catch { }
})

# OURS FOR NOW, UNTIL #1259: 140 outfit meshes built in BodySlide on some other
# machine (Common Clothes' travel clothes, Immersive Armours' Bosmer armour,
# More Craftable Equipment's executioner). Patrick, 29 September: Thornswood
# builds the outfits itself from the collection's BodySlide projects, and until
# that build replaces these they keep shipping so nothing looks broken. Exact
# paths, in built-until-1259.txt beside this file; the build that closes #1259
# names its own output here and deletes that file in the same pull request.
# Scrub-Feed leaves them on the site, since they are ours while listed.
# In a child scope, for the reason given over $ShipRequiredDataFiles.
$ShipBuiltUntil1259 = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($ShipBuiltLine in @(& {
    try {
        $list = Join-Path $PSScriptRoot 'built-until-1259.txt'
        if (Test-Path -LiteralPath $list) {
            foreach ($line in [IO.File]::ReadAllLines($list)) {
                $one = $line.Trim()
                if ($one -and -not $one.StartsWith('#')) { $one }
            }
        }
    } catch { }
})) { [void]$ShipBuiltUntil1259.Add($ShipBuiltLine) }

function Test-ShipGenerated([string]$rel) {
    foreach ($p in $ShipGeneratedPatterns) { if ($rel -like $p) { return $true } }
    return $false
}

# Both entry points can be called without Ship, so check the actual body
# bytes here too. A partial receipt must not turn loose defaults into ours.
function Assert-ShipGeneratedBodies([string]$GameDir, [string]$ProfileDir) {
    Assert-ShipGeneratedBodyFiles $GameDir $ProfileDir
    $root = Split-Path -Parent $ProfileDir
    $expectedGame = [IO.Path]::GetFullPath((Join-Path $root 'Game')).TrimEnd('\')
    if ([IO.Path]::GetFullPath($GameDir).TrimEnd('\') -ine $expectedGame) { throw 'Publish the generated bodies from their own game folder, rather than a Steam or Vortex fallback.' }
    $gameRows = @([IO.File]::ReadLines((Join-Path $ProfileDir 'OwnGame\generated.txt')) | Where-Object { $_ -match '^game (.+)$' })
    if ($gameRows.Count -ne 1) { throw 'The generated receipt must name exactly one source game folder.' }
    $recordedGame = [IO.Path]::GetFullPath($gameRows[0].Substring(5)).TrimEnd('\')
    if ($recordedGame -ine $expectedGame) { throw 'The generated receipt names a different source game folder.' }
    $state = & {
        . (Join-Path $PSScriptRoot '..\mods\Generated.ps1')
        Get-GeneratedState $root (Join-Path $PSScriptRoot '..\..\records\generated.json')
    }
    if (-not $state.Current) { throw ('Generated files are stale: ' + ($state.Why -join '; ')) }
}

function Assert-ShipGeneratedBodyFiles([string]$GameDir, [string]$ProfileDir) {
    $record = Join-Path $ProfileDir 'OwnGame\generated.txt'
    if (-not (Test-Path -LiteralPath $record)) { throw 'The generated body record is missing. Build the covered bodies before publishing.' }
    $rows = @([IO.File]::ReadLines($record) | ForEach-Object {
        if ($_ -match '^file ([0-9a-f]{64}) (.+)$') {
            [pscustomobject]@{ Sha=$matches[1]; Rel=$matches[2].Replace('/', '\'); Destination=[IO.Path]::GetFullPath((Join-Path $GameDir $matches[2])) }
        }
    })
    foreach ($rel in $ShipGeneratedBodyFiles) {
        $file = Join-Path $GameDir $rel
        $destination = [IO.Path]::GetFullPath($file)
        $matching = @($rows | Where-Object { $_.Destination -ieq $destination })
        if ($matching.Count -ne 1) { throw "The generated body record must list exactly one build of $rel." }
        if ($matching[0].Rel -ine $rel) { throw "The generated body path must use its canonical destination: $rel." }
        $sha = $matching[0].Sha
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "The generated body is missing: $rel." }
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $sha) { throw "The generated body is not as built: $rel. Rebuild before publishing." }
    }
}

# Whether a loose file waits for the collection, at this revision.
function Test-ShipHeld([string]$rel, [int]$Revision = $ShipCollectionRevision) {
    foreach ($h in $ShipHeldForCollection) {
        $p = [string]$h.Path
        $hit = if ($p.EndsWith('\')) { $rel.StartsWith($p, 'OrdinalIgnoreCase') } else { $rel -ieq $p }
        if ($hit -and $Revision -lt [int]$h.Revision) { return $true }
    }
    return $false
}

# Ours outside Data\Platform: the list, the client runtime's recorded paths
# (Test-ShipOtherServer asks their bytes), required data, the menu backdrop and
# the generator's output. Inside Data\Platform this answers yes; that folder is
# Test-ShipOtherServer's to decide.
function Test-ShipOurs([string]$rel) {
    if ($rel.StartsWith('Data\Platform\', 'OrdinalIgnoreCase')) { return $true }
    if ($ShipClientFiles.Contains($rel)) { return $true }
    foreach ($o in $ShipOursFiles) { if ($rel -ieq $o) { return $true } }
    foreach ($o in $ShipOwnArt) { if ($rel -ieq $o) { return $true } }
    foreach ($o in $ShipRequiredDataFiles) { if ($rel -ieq $o) { return $true } }
    if ($ShipBuiltUntil1259.Contains($rel)) { return $true }
    return (Test-ShipGenerated $rel)
}

# Somebody else's loose file, which never ships: not ours, and not held for the
# collection at this revision.
function Test-ShipNotOurs([string]$rel, [int]$Revision = $ShipCollectionRevision) {
    if (Test-ShipOurs $rel) { return $false }
    return (-not (Test-ShipHeld $rel $Revision))
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
    # THE PUBLISHED PACKS NO LONGER CARRY THEM (#1239). This note used to say
    # the nine packs were left alone because rewriting one changes its sha256.
    # That stopped being a reason once Scrub-Feed.ps1 rewrote a pack and its
    # feed entry together: a launcher matches packs by id in applied.txt and
    # never fetches one it applied again, and one replaying every pack reads
    # the new sha256 from the same feed. Scrub-Feed takes every file
    # Test-ShipOneMachine names out of the packs and records on the site, the
    # tokens with them, and keeps this line in every delete list.
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
    'Data\Platform\Plugins\thornswood-chargen.js',

    # ELYSIUM ESTATE'S OLD PLUGIN, issue #690. Packs carried it from
    # game\required-data from 27 September, while the servers loaded 4.3.5.
    # On 29 September the servers moved to the collection's 5.0.1, whose
    # plugin is ElysiumEstate.esp, so this name is nobody's any more: no mod in
    # the collection has it, and a copy left switched on would take a place
    # the server does not have. Every install that took one of those packs
    # loses it.
    'Data\ElysiumEstateSSE.esp'
)
# SkyUI 5.2's loose scripts, issue #960: dev packs carried them, so leaving
# them out of new packs would do nothing for the machines showing the SkyUI
# error box. The collection's SkyUI keeps its scripts inside SkyUI_SE.bsa, so
# nothing it installs is lost. See $ShipOldSkyUIScripts above.
$ShipDeleteAlways += $ShipOldSkyUIScripts
# The Daedric menu set and the unused fork svgs plus bg.png, issue #1318:
# leaving them out of new packs does nothing for the machines that already
# have them. Every pack deletes these names. Get-ShipDeleteAlways also adds
# a renamed copy whose bytes still match a Daedric sha256.
$ShipUiGonePaths = @($ShipDaedricMenu.Keys | ForEach-Object { 'Data\Platform\UI\' + $_ })
$ShipUiGonePaths += @($ShipUnusedFrontAssets | ForEach-Object { 'Data\Platform\UI\' + $_ })
$ShipDeleteAlways += $ShipUiGonePaths

function Get-ShipDeleteAlways {
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $ShipDeleteAlways) { $list.Add($p) }
    $game = Get-Variable -Name GameDir -ValueOnly -ErrorAction SilentlyContinue
    if ($game) {
        $ui = Join-Path ([string]$game) 'Data\Platform\UI'
        if (Test-Path -LiteralPath $ui -PathType Container) {
            $have = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($p in $list) { [void]$have.Add($p) }
            foreach ($f in @(Get-ChildItem -LiteralPath $ui -File)) {
                $rel = 'Data\Platform\UI\' + $f.Name
                if ($have.Contains($rel)) { continue }
                $h = Get-ShipFileSha256 $f.FullName
                if ($h -and $ShipDaedricMenuHashes.Contains($h)) {
                    $list.Add($rel)
                    [void]$have.Add($rel)
                }
            }
        }
    }
    return @($list)
}

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
# game\required-data holds plugins that plugins.txt and the server enable by
# exact filename while Vortex deploys a different name. OwnGame links only what
# Vortex deployed, so such a file is on one machine only unless a pack carries
# it. It is empty today: ElysiumEstateSSE.esp was here from 27 to 29 September,
# until the servers moved to the collection's ElysiumEstate.esp (#690).
#
# Go.ps1, Publish-Update and Package-Thornswood call Ensure-ShipRequiredData so
# each file here lands at Data\<name> before the pack / installer scan. They are
# not origin V in files.txt, so packs carry them. Take a file out of
# game\required-data when the collection deploys that same Data\ path.
function Get-ShipRequiredDataRoot([string]$RepoDir) {
    return (Join-Path $RepoDir 'game\required-data')
}

# Places every file under game\required-data (except README.md) at Data\<name>
# in $GameDir when that path is missing or the bytes differ. A file the game
# folder already holds, same bytes, is left where it is and is not returned:
# callers print this list, and an empty list must stay empty (#1119). Breaks
# an existing hard link before replacing different bytes, so a write never
# goes through into Vortex staging. Throws when the folder is missing, or
# when copy fails.
function Ensure-ShipRequiredData([string]$GameDir, [string]$RepoDir) {
    $srcRoot = Get-ShipRequiredDataRoot $RepoDir
    if (-not (Test-Path -LiteralPath $srcRoot)) {
        throw "game\required-data is missing under $RepoDir"
    }
    $placed = New-Object System.Collections.Generic.List[string]
    $sources = @(Get-ChildItem -LiteralPath $srcRoot -File -EA Stop)
    # Content is Thornswood's own plugin. A completed release can update it
    # beyond the published collection base without changing anybody's staging
    # copy. Packs and the installer place exactly this committed source.
    $content = Join-Path $RepoDir 'game\content\Thornswood-Content.esp'
    if (Test-Path -LiteralPath $content) { $sources += Get-Item -LiteralPath $content }
    foreach ($f in $sources) {
        if ($f.Name -eq 'README.md') { continue }
        $rel = 'Data\' + $f.Name
        $dst = Join-Path $GameDir $rel
        $dir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dir)) {
            $null = New-Item -ItemType Directory -Force -Path $dir
        }
        if (Test-Path -LiteralPath $dst) {
            $same = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash -eq `
                    (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
            if ($same) { continue }
            # OwnGame.Unshare pattern: drop the name if it is a hard link so the
            # copy is this folder's own bytes, not Vortex's.
            try { Remove-Item -LiteralPath $dst -Force -EA Stop } catch {
                throw ("Could not replace $rel in the game folder (is the game open?): " + $_.Exception.Message)
            }
        }
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force -EA Stop
        $placed.Add($rel)
    }
    # No leading comma. `return ,$array` is one pipeline object, and both
    # callers wrap that in @(), so Count was always 1 and the log said
    # System.String[] whether or not a file was placed (#1119).
    return $placed.ToArray()
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
