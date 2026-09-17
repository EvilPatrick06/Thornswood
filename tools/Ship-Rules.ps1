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
      Test-ShipOtherServer $rel    another server's or somebody's sign in; never shipped, never removed

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
    'Data\SkyrimTogetherReborn\cache\',
    'Data\SkyrimTogetherReborn\logs\',
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
    # The launcher and the voice plugin talk through these three.
    'Data\Platform\voice-port.txt',
    'Data\Platform\voice-status.txt',
    'Data\Platform\voice-ptt.txt',
    # Written by the game on this machine every session.
    'Data\Platform\thornswood-loadorder.txt',
    # The launcher's note to the plugins that this is our session. See Keep.cs.
    'Data\Platform\thornswood-session.txt',
    'Data\Platform\menu-music-duck.txt',
    'Data\SKSE\Plugins\po3_Tweaks.ini',
    'Data\SKSE\Plugins\CrashLogger.ini'
)

function Test-ShipRuntime([string]$rel) {
    foreach ($d in $ShipRuntimeDirs) {
        if ($rel.StartsWith($d, 'OrdinalIgnoreCase')) { return $true }
    }
    return $false
}

# Another SkyMP server's files, and anybody's sign in. Keizaal Online and
# Daedric Online write into the same Data\Platform as us: their plugins beside
# ours, .bak copies of files they replace, their Vite built menu. Keep parks
# their plugins while Thornswood runs and puts them back after, so they are
# always in the folder when it is scanned. Ours are thornswood-*.js and the
# patched skymp5-client.js; anything else in Plugins is theirs.
#
# PluginsNoLoad is where the SkyMP client keeps its saved sign in
# (auth-data-no-load.js, a token). It is one person's login to whichever
# master issued it and has no place in a pack or an installer, and it is not
# ours to delete off a machine either: on a machine that plays Keizaal it is
# that person's own login.
function Test-ShipOtherServer([string]$rel) {
    if (-not $rel.StartsWith('Data\Platform\', 'OrdinalIgnoreCase')) { return $false }
    $leaf = Split-Path $rel -Leaf
    if ($rel.StartsWith('Data\Platform\PluginsNoLoad\', 'OrdinalIgnoreCase')) { return $true }
    if ($leaf -like '*.bak') { return $true }
    if ($rel -like 'Data\Platform\Plugins\*.js') {
        if ($leaf -like 'thornswood-*.js') { return $false }
        if ($leaf -eq 'skymp5-client.js') { return $false }
        return $true
    }
    # Keizaal's menu is a Vite build: app.js, vite.svg, an assets folder and
    # its own art. Ours is flat under UI (build.js and hashed files beside it)
    # and never has an assets folder, so these can only be theirs.
    if ($rel -like 'Data\Platform\UI\*') {
        if ($rel -like 'Data\Platform\UI\assets\*') { return $true }
        if ($leaf -in 'app.js', 'vite.svg') { return $true }
        if ($leaf -match 'keizaal|daedric|mereth') { return $true }
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
