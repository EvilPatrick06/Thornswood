<#
  test-ship-rules.ps1

  Every file that has ever leaked in a pack or an installer stays out.

  WHY THIS EXISTS. Ship-Rules.ps1 is the one list of what never leaves a
  machine, and nearly every line in it is there because something already got
  out: the SkyMP sign in token inside the installer, one machine's
  Thornswood.ini with Fov=120 in the three packs of 16 and 17 September,
  a 6 MB vortex.deployment.json in pack-20260916-1217, the voice join token in
  nine packs from 18 to 20 September, a report and a script from the Claude
  desktop app in packs 20260916-0130 to 0937, and the front's own 147 fonts
  and sounds wrongly left out by the dev Ship of 20 September at 13:02. Entry
  197 on the To Do List: "Ship-Rules is the highest-yield unit test in the
  repo, seven incidents have already happened inside it". Until this file
  nothing ran it.

  So each case below is the exact relative path its own comment in
  Ship-Rules.ps1 names, asked of the real functions, dot-sourced. A rule that
  is edited away, or a rewrite that turns one list into another, turns a line
  here red before a pack carries the file again.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$RulesPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RulesPath) { $RulesPath = Join-Path $Here 'Ship-Rules.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

. $RulesPath

# The record of our own client build sits beside the rules, and the rules read
# it from there. Read here too, so the six files are asked about by name.
$record = Join-Path (Split-Path -Parent $RulesPath) 'client-build.json'
$clientFiles = @()
if (Test-Path -LiteralPath $record) {
    $clientFiles = @((Get-Content -LiteralPath $record -Raw | ConvertFrom-Json).files.PSObject.Properties.Name)
}

# ---- somebody's sign in, which the installer carried -------------------------
#
# The night Ship-Rules became one file: Package-Thornswood kept its own
# shorter list and the SkyMP client's saved sign in token from the build
# machine rode inside the installer.
$token = 'Data\Platform\PluginsNoLoad\auth-data-no-load.js'
Yes "$token is never shipped" (Test-ShipOtherServer $token)
Yes '  and never removed from anybody either' (Test-ShipMachine $token)
Yes '  and never swept as a runtime file' (-not (Test-ShipRuntime $token))
Yes 'anything else in PluginsNoLoad is kept out the same way' (Test-ShipOtherServer 'Data\Platform\PluginsNoLoad\other.js')

# ---- one machine's settings, which three packs carried -----------------------
#
# 16 and 17 September: the publishing machine's Thornswood.ini went out and put
# its Fov=120 and its key binds on everyone.
foreach ($rel in @(
    'Data\SKSE\Plugins\Thornswood.ini',
    # SSE Display Tweaks holds the screen resolution; publishing it stamped
    # one person's monitor onto everyone.
    'Data\SKSE\Plugins\SSEDisplayTweaks.ini',
    # One person's character slot.
    'Data\Platform\Plugins\skymp5-client-settings.txt',
    'Data\SKSE\Plugins\OpenAnimationReplacer.ini',
    'Data\SKSE\Plugins\SkyrimPlatform.ini',
    'Data\SKSE\Plugins\po3_Tweaks.ini',
    'Data\SKSE\Plugins\CrashLogger.ini',
    # The launcher and the voice plugin talk through these.
    'Data\Platform\voice-port.txt',
    'Data\Platform\voice-status.txt',
    'Data\Platform\voice-ptt.txt',
    # Every profile id the install owns.
    'Data\Platform\thornswood-characters.json',
    'Data\Platform\thornswood-choice.txt',
    'Data\Platform\thornswood-forget.txt',
    'Data\Platform\UI\thornswood-characters.js',
    'Data\Platform\thornswood-loadorder.txt',
    'Data\Platform\thornswood-plugins-light.txt',
    'Data\Platform\thornswood-session.txt',
    'Data\Platform\menu-music-duck.txt',
    'Data\Platform\overlay-boot.count',
    'Data\Platform\thornswood-voice.log'
)) {
    Yes "$rel is one machine's own" (Test-ShipMachine $rel)
    # A runtime path is listed as removed and taken off every install, which
    # for somebody's own settings would be worse than shipping them.
    Yes '  and is never swept off anybody as a runtime file' (-not (Test-ShipRuntime $rel))
}
# Matched exactly, so a file of ours that merely sits beside one is not caught.
Yes 'a different ini in the same folder still ships' (-not (Test-ShipMachine 'Data\SKSE\Plugins\ThornswoodExtra.ini'))

# ---- the voice join token, which nine packs carried --------------------------
#
# 18 to 20 September, packs 20260918-1615 to 20260920-1124. Kept out of new
# packs, and deleted from the installs that took one of those nine.
$voice = 'Data\Platform\voice-token.txt'
Yes "$voice is never shipped" (Test-ShipMachine $voice)
$always = @(Get-ShipDeleteAlways)
Yes '  and every pack deletes it from every install' ($always -contains $voice)

# ---- Vortex's own bookkeeping, which pack-20260916-1217 carried --------------
foreach ($rel in @(
    'Data\vortex.deployment.json',
    'Data\vortex.deployment.dinput.json',
    'Data\meshes\__folder_managed_by_vortex',
    'Data\textures\armor\iron.dds.vortex_backup'
)) {
    Yes "$rel is Vortex's own and never shipped" (Test-ShipMachine $rel)
}

# ---- what the Claude desktop app dropped into the game folder ----------------
#
# A report, a script and a png rode along in packs 20260916-0130 to 0937, and
# Data\Platform\Claude outputs held three scripts on 16 September.
foreach ($rel in @(
    'Claude outputs\report.md',
    'Data\Platform\Claude outputs\fix.ps1',
    '_to_delete\old.dll',
    'Data\SKSE\Plugins\CharGen\Exported\face.jslot',
    '.sentry-native\last_crash'
)) {
    Yes "$rel is written at runtime and never shipped" (Test-ShipRuntime $rel)
}
Yes 'a folder whose name only ends the same way is not taken for it' (-not (Test-ShipRuntime 'Data\NotClaude outputs\x.txt'))

# ---- another server's folders ------------------------------------------------
#
# Skyrim Together Reborn's folder moved out of the runtime list on 23
# September. A runtime path is swept off every install that has it, and this
# is somebody else's install; the rule is never shipped, never removed.
$str = 'Data\SkyrimTogetherReborn\logs\client.log'
Yes "$str is another server's" (Test-ShipOtherServer $str)
Yes '  and is not swept off anybody as a runtime file' (-not (Test-ShipRuntime $str))
Yes '  and the folder itself counts' (Test-ShipOtherServer 'Data\SkyrimTogetherReborn')
Yes 'a sibling folder whose name only starts the same way is not caught' (-not (Test-ShipOtherServer 'Data\SkyrimTogetherRebornExtras\x.esp'))
Yes 'NirnLab UI Platform is kept out' (Test-ShipOtherServer 'Data\NirnLabUIPlatform\CEFSubprocess.exe')
Yes '  and its plugin' (Test-ShipOtherServer 'Data\SKSE\Plugins\NirnLabUIPlugin.dll')

# ---- the loose map.swf and SkyUI's ERROR CODE 5 --------------------------------
#
# 22 September: excluded from packs, but the machines that already had it kept
# it, so every pack deletes it as well.
$map = 'Data\Interface\map.swf'
Yes "$map is never shipped" (Test-ShipOtherServer $map)
Yes '  whatever case it is written in' (Test-ShipOtherServer 'Data\Interface\MAP.SWF')
Yes '  and every pack deletes it from every install' ($always -contains $map)
Yes 'the other Interface files still ship' (-not (Test-ShipOtherServer 'Data\Interface\quest_journal.swf'))

# ---- Data\Platform: ours is what we name --------------------------------------
Yes 'our overlays in Plugins ship' (-not (Test-ShipOtherServer 'Data\Platform\Plugins\thornswood-chat.js'))
Yes 'anybody else''s plugin script in Plugins does not' (Test-ShipOtherServer 'Data\Platform\Plugins\other-server-chat.js')
Yes 'a backup file in Data\Platform does not' (Test-ShipOtherServer 'Data\Platform\Plugins\thornswood-chat.js.bak')
# Somebody else's menu is a Vite build: an assets folder, app.js, vite.svg.
Yes 'another menu''s assets folder does not ship' (Test-ShipOtherServer 'Data\Platform\UI\assets\index-4f2a.js')
Yes '  nor its app.js' (Test-ShipOtherServer 'Data\Platform\UI\app.js')
Yes '  nor its vite.svg' (Test-ShipOtherServer 'Data\Platform\UI\vite.svg')
# 20 September, 13:02: the first version of the UI rule called the front's own
# 147 hashed fonts, icons and sounds foreign and the dev Ship left them out.
foreach ($rel in @(
    'Data\Platform\UI\index.html',
    'Data\Platform\UI\build.js',
    'Data\Platform\UI\thornswood-bridge.js',
    'Data\Platform\UI\3f9c2a71d0.ttf',
    'Data\Platform\UI\a81be0c4.svg',
    'Data\Platform\UI\5d1e77aa.wav',
    'Data\Platform\UI\menu_theme.mp3',
    'Data\Platform\UI\thornswood-theme.mp3'
)) {
    Yes "$rel is the front's own and ships" (-not (Test-ShipOtherServer $rel) -and -not (Test-ShipMachine $rel) -and -not (Test-ShipRuntime $rel))
}
# Held on dev until 22 September, then given to main by Patrick.
Yes 'the theme is not held back from main any more' (-not (Test-ShipDevOnly 'Data\Platform\UI\thornswood-theme.mp3'))

# ---- our own client, by record -------------------------------------------------
#
# Until 20 September the copies in every game folder were another launcher's
# builds. The six files in client-build.json are ours by hash, and
# skymp5-client.js in particular would read as somebody else's plugin script
# by the name rule above.
Yes 'client-build.json names the six client files' ($clientFiles.Count -eq 6)
foreach ($rel in $clientFiles) {
    Yes "$rel is ours by record and ships" (-not (Test-ShipOtherServer $rel) -and -not (Test-ShipMachine $rel) -and -not (Test-ShipRuntime $rel))
}

# ---- nothing is both shipped and deleted ---------------------------------------
#
# A path on the delete-always list that a pack could also carry would arrive
# and be deleted in the same update.
foreach ($rel in $always) {
    Yes "$rel, deleted by every pack, is never carried by one" ((Test-ShipOtherServer $rel) -or (Test-ShipMachine $rel))
}

# ---- the record that keeps the collection out ---------------------------------
#
# 17 September: Profile went, Profile\OwnGame\files.txt with it, and a release
# counted 29,063 files and 11,368.1 MB of the collection as ours. Only lines
# whose origin is V are the collection's.
$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-ship-rules-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $work 'Profile\OwnGame') -Force | Out-Null
try {
    $profileDir = Join-Path $work 'Profile'
    Yes 'no record answers nothing, so the publisher can refuse' ($null -eq (Get-ShipOwnGameCollection $profileDir))

    $lines = @(
        'F|V|1024|638000000000000000|Data\SkyUI_SE.esp',
        'F|V|2048|638000000000000000|Data\textures\sky\clouds.dds',
        'F|O|4096|638000000000000000|Data\Platform\Plugins\thornswood-chat.js',
        'not a record line'
    )
    [IO.File]::WriteAllLines((Join-Path $profileDir 'OwnGame\files.txt'), $lines)
    $set = Get-ShipOwnGameCollection $profileDir
    Yes 'the record reads back as a set' ($null -ne $set)
    Yes '  holding the two lines Vortex deployed' ($null -ne $set -and $set.Count -eq 2)
    Yes '  matched without regard to case' ($null -ne $set -and $set.Contains('data\skyui_se.esp'))
    Yes '  and not the file of ours beside them' ($null -ne $set -and -not $set.Contains('Data\Platform\Plugins\thornswood-chat.js'))

    # Where the reference plugin list comes from, which shipped the ordinary
    # Skyrim's list once when it was read from AppData with the game closed.
    $root = Join-Path $work 'Root'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    Yes 'no Game folder reads the list Vortex writes into AppData' (
        (Get-ShipLoadOrderDir $root $profileDir) -eq (Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition'))
    New-Item -ItemType Directory -Path (Join-Path $root 'Game') -Force | Out-Null
    Yes 'an older Game folder reads Profile\Default' ((Get-ShipLoadOrderDir $root $profileDir) -eq (Join-Path $profileDir 'Default'))
    [IO.File]::WriteAllText((Join-Path $profileDir 'OwnGame\plugins.txt'), "*SkyUI_SE.esp`r`n")
    Yes 'a folder made from Vortex reads Profile\OwnGame' ((Get-ShipLoadOrderDir $root $profileDir) -eq (Join-Path $profileDir 'OwnGame'))
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
