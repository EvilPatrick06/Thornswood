<#
  test-no-machine-files.ps1

      pwsh -NoProfile -File .\tests\test-no-machine-files.ps1

  One machine's own files never leave it (#1239): Test-ShipOneMachine in
  Ship-Rules.ps1 names them by kind, and packing, the record guard in
  Publish-Update, the rollback filter in Rollback-Feed, Check-Secrets and
  Scrub-Feed all ask it.

  WHY THIS EXISTS. Read over HTTPS on 29 September, every pack and record both
  feeds name: 35 packs and all five dev records carried files of the machine
  that ships. Expired voice join tokens, the join pass the launcher writes for
  the game server, Vortex's 6 MB record of its own deployment, one person's key
  binds, crash, display and animation settings, face exports, window layouts,
  settings saved from three mods' menus (two of them another server's values),
  backups, and files a Claude session left in the game folder. The join pass
  and the mod menu settings were named by no rule at all: the list of names
  had no line for them. So the rule is by kind now, and this proves:

    1. every file of one machine's the site carried is caught, by kind
    2. every file Thornswood ships that sits beside them is not
    3. every file the launcher or a plugin of ours writes straight into
       Data\Platform, read out of their source, is caught, so the next one is
       caught the day it is added
    4. never listed as removed, except the runtime folders and what every
       release deletes on purpose
    5. the record guard and the rollback filter, each run on its own
    6. Check-Secrets fails a pack that carries one
    7. Test-ShipMachine, Check-Secrets and Scrub-Feed ask it

  Everything it writes is in its own temp folder.
#>
[CmdletBinding()]
param()
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-machine-files-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
function Done {
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}
trap { $script:fail++; Write-Host ("FAIL  stopped: " + $_.Exception.Message + ' ' + $_.InvocationInfo.PositionMessage) -ForegroundColor Red; Done }

. (Join-Path $repo 'scripts\release\Ship-Rules.ps1')

# ---- 1. what the site carried ------------------------------------------------
# Every distinct file of one machine's in a pack or record on either feed, read
# over HTTPS on 29 September, with its kind.
Write-Host 'what the site carried'
$found = [ordered]@{
    'Data\Platform\voice-token.txt'                                 = 'a voice join token, sixty minutes, nine main packs'
    'Data\Platform\thornswood-pass.txt'                             = 'the join pass for the game server, ten minutes, two dev packs and four dev records'
    'Data\Platform\thornswood-loadorder.txt'                        = 'the load order the game saw that session'
    'Data\Platform\thornswood-spots.txt'                            = 'the spot marker''s output'
    'Data\Platform\js-hang-culprit.txt'                             = 'a hang report'
    'Data\Platform\overlay-boot.count'                              = 'a counter the overlay keeps'
    'Data\Platform\Plugins\skymp5-client-settings.txt'              = 'the client''s server and character slot'
    'Data\SKSE\Plugins\Thornswood.ini'                              = 'one person''s key binds and field of view'
    'Data\SKSE\Plugins\CrashLogger.ini'                             = 'crash settings the launcher writes'
    'Data\SKSE\Plugins\OpenAnimationReplacer.ini'                   = 'written back by the mod on exit'
    'Data\SKSE\Plugins\po3_Tweaks.ini'                              = 'one machine''s tweaks'
    'Data\SKSE\Plugins\SkyrimPlatform.ini'                          = 'log level, console and browser backend'
    'Data\SKSE\Plugins\SkyrimPlatform.ini.bak'                      = 'a backup'
    'Data\SKSE\Plugins\SkyrimPlatform.ini.2026-09-19T20-17-00-253Z.bak' = 'a backup'
    'VERSION.bak'                                                   = 'a backup'
    'Data\SKSE\Plugins\OpenAnimationReplacer_ImGui.ini'             = 'a window layout'
    'Data\SKSE\Plugins\CommunityShaders_ImGui.ini'                  = 'a window layout'
    'Data\SKSE\Plugins\CommunityShaders\SettingsUser.json'          = 'graphics settings saved from the mod''s menu'
    'Data\MCM\Settings\Precision.ini'                               = 'saved from the mod''s menu, another server''s values'
    'Data\MCM\Settings\TrueDirectionalMovement.ini'                 = 'saved from the mod''s menu, another server''s values'
    'Data\MCM\Settings\TrueHUD.ini'                                 = 'saved from the mod''s menu'
    'Data\vortex.deployment.json'                                   = 'Vortex''s record of this Skyrim'
    'vortex.deployment.dinput.json'                                 = 'Vortex''s record of this Skyrim'
    'Data\SKSE\Plugins\po3_StartOnSave.ini.vortex_backup'           = 'what Vortex moved aside'
    'Data\meshes\YAbyss\Hair\DarcusHair2.nif.vortex_backup'         = 'what Vortex moved aside'
    'Data\NirnLabUIPlatform\__folder_managed_by_vortex'             = 'Vortex''s claim on a folder'
    'Data\SKSE\Plugins\CharGen\Exported\Adventurer.jslot'           = 'a face export'
    'Data\textures\CharGen\Exported\Adventurer3424.dds'             = 'a face tint'
    'Claude outputs\Overnight-Report.md'                            = 'left by a session'
    '_to_delete\zz-other-server-test.js'                            = 'left by a session'
}
foreach ($k in $found.Keys) {
    Yes ("{0} is one machine's ({1})" -f $k, $found[$k]) (Test-ShipOneMachine $k)
    Yes '  so it is never packed' ((Test-ShipMachine $k) -or (Test-ShipRuntime $k))
}
# The same kinds, named the way the next one will be.
$kinds = @('Data\Platform\thornswood-anything-new.txt', 'Data\Platform\thornswood-input.log', 'Data\SKSE\Plugins\SomeMod.log',
           'Data\SKSE\Plugins\crash-2026-09-29.dmp', 'Data\SKSE\Plugins\SomeMod_ImGui.ini', 'imgui.ini', 'Data\MCM\Settings\AnyMod.ini',
           'Data\Platform\PluginsNoLoad\auth-data-no-load.js', 'Data\SKSE\Plugins\CommunityShaders\SettingsTest.json',
           'Saves\Save1.ess', 'Data\SKSE\Plugins\x.skse', 'Profile\launcher.log', 'My Games\Skyrim.ini', 'Data\ShaderCache\a.bin',
           'Data\vortex.deployment.other.json', 'Data\textures\x.dds.vortex_backup')
foreach ($k in $kinds) { Yes "$k, a file of the same kind, is caught" (Test-ShipOneMachine $k) }

# ---- 2. what Thornswood ships -------------------------------------------------
Write-Host ''; Write-Host 'what Thornswood ships'
$ours = @(
    'Data\Platform\UI\index.html', 'Data\Platform\UI\thornswood-select.js', 'Data\Platform\Plugins\thornswood-front.js',
    'Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformImpl.dll', 'Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformCEF.exe.hidden',
    'Data\Platform\Modules\skyrimPlatform.ts', 'Data\Platform\Images\lock.png', 'Data\Platform\Fonts\x.ttf',
    'Data\Interface\skyui\config.shipped.txt', 'Data\Interface\skyhud\skyhud.txt',
    'Data\SKSE\Plugins\CommunityShaders\SettingsDefault.json', 'Data\MCM\Config\TrueHUD\settings.ini', 'Data\SKSE\Plugins\ImGuiVRHelper.toml',
    'Data\Thornswood-Content.esp', 'Data\ElysiumEstateSSE.esp', 'Data\Scripts\MCM.pex', 'Data\SKSE\Plugins\ThornswoodExtra.ini',
    'Data\meshes\armor\x.nif', 'Data\textures\CharGen\ours.dds', 'Data\Interface\racemenu\bottombar.swf', 'Data\music\special\mus_maintheme.xwm')
foreach ($k in $ours) { Yes "$k ships" (-not (Test-ShipOneMachine $k)) }
foreach ($k in @($ShipClientFiles)) { Yes "$k, a client file, is the build's by its recorded bytes and never one machine's" (-not (Test-ShipOneMachine $k)) }
Yes 'the Data\Platform folder itself is not a file of one machine''s' (-not (Test-ShipOneMachine 'Data\Platform\'))
# Another server's file, whose fate is a decision (#1253), not one machine's.
Yes 'TrueHUD\RP_Bosses.ini is left to #1253, not taken as one machine''s' (-not (Test-ShipOneMachine 'Data\SKSE\Plugins\TrueHUD\RP_Bosses.ini'))
# No setting Thornswood chose is in the repository as a mod menu file: the rule
# can take Data\MCM\Settings whole without taking one of ours.
$tracked = @(& git -C $repo ls-files 2>$null | Where-Object { $_ -match '(?i)MCM/Settings/|CommunityShaders/Settings(User|Test)\.json' })
Yes 'no file in the repository is a mod menu settings file the rule would take' ($tracked.Count -eq 0)

# ---- 3. what our own code writes straight into Data\Platform -------------------
Write-Host ''; Write-Host 'what the launcher and the plugins write into Data\Platform'
$src = @()
$src += @(Get-ChildItem -LiteralPath (Join-Path $repo 'launcher\app') -Filter '*.cs' -File)
$src += @(Get-ChildItem -LiteralPath (Join-Path $repo 'game\plugins') -Filter '*.js' -File)
$named = New-Object 'System.Collections.Generic.SortedSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($f in $src) {
    $text = [IO.File]::ReadAllText($f.FullName)
    foreach ($m in [regex]::Matches($text, 'Data(?:\\\\|\\|/)Platform(?:\\\\|\\|/)([A-Za-z0-9_.-]+\.[A-Za-z0-9]+)\b(?!(?:\\|/))')) { [void]$named.Add($m.Groups[1].Value) }
}
Yes ('the source names files straight in Data\Platform ({0} of them)' -f $named.Count) ($named.Count -ge 10)
Yes '  among them the join pass, which no rule named until #1239' ($named.Contains('thornswood-pass.txt'))
foreach ($n in $named) { Yes "Data\Platform\$n is one machine's" (Test-ShipOneMachine ('Data\Platform\' + $n)) }

# ---- 4. never listed as removed -----------------------------------------------
Write-Host ''; Write-Host 'never listed as removed'
foreach ($k in $found.Keys) {
    if (Test-ShipRuntime $k) { continue }
    Yes "$k is never listed as removed (Test-ShipMachine)" (Test-ShipMachine $k)
}
Yes 'the join pass is not a runtime path, which would list it as removed' (-not (Test-ShipRuntime 'Data\Platform\thornswood-pass.txt'))

# ---- 5. the record guard and the rollback filter --------------------------------
Write-Host ''; Write-Host 'the record guard and the rollback filter'
function Get-Block([string]$src, [string]$name) {
    $a = $src.IndexOf("# ==== thornswood $name ====")
    $b = $src.IndexOf("# ==== end thornswood $name ====")
    if ($a -lt 0 -or $b -le $a) { return $null }
    return $src.Substring($a, $b - $a)
}
$pub = [IO.File]::ReadAllText((Join-Path $repo 'scripts\release\Publish-Update.ps1'))
$guard = Get-Block $pub "no one machine's files in the record"
Yes 'the record guard is in Publish-Update.ps1' ($null -ne $guard)
if ($guard) {
    Yes '  before anything is sent' ($pub.IndexOf("# ==== thornswood no one machine's files in the record ====") -lt $pub.IndexOf('$recordFiles = @()'))
    function Die($m) { throw "STOP $m" }
    function Invoke-Guard($map) { $now = $map; try { Invoke-Expression $guard; return '' } catch { return $_.Exception.Message } }
    $clean = @{ 'Data\Platform\UI\index.html' = '1:aa'; ':gone:Data\Platform\voice-token.txt' = 'always'; ':gone:Data\Interface\map.swf' = 'always'; ':order:plugins' = 'x' }
    Yes '  a record of ours goes through, with the token every release deletes listed as gone' ((Invoke-Guard $clean) -eq '')
    foreach ($k in @('Data\Platform\thornswood-pass.txt', 'Data\MCM\Settings\TrueHUD.ini', 'Data\SKSE\Plugins\CommunityShaders_ImGui.ini',
                     'Data\textures\CharGen\Exported\Adventurer3424.dds', 'Data\Platform\js-hang-culprit.txt', ':gone:Data\Platform\thornswood-pass.txt',
                     ':gone:Data\SKSE\Plugins\Thornswood.ini')) {
        $m = @{} + $clean; $m[$k] = '1:bb'
        Yes "  a record naming $k stops the release" ((Invoke-Guard $m) -like "STOP*one machine's*")
    }
}
$roll = [IO.File]::ReadAllText((Join-Path $repo 'scripts\release\Rollback-Feed.ps1'))
$filter = Get-Block $roll "no one machine's files in a rollback"
Yes 'the rollback filter is in Rollback-Feed.ps1' ($null -ne $filter)
if ($filter) {
    Yes '  and runs before the new record is worked out' ($roll.IndexOf("# ==== thornswood no one machine's files in a rollback ====") -lt $roll.IndexOf('$newMap = @{}'))
    function Say($m, $c) { }
    $curMap = @{ 'Data\Platform\UI\index.html' = '1:aa'; 'Data\MCM\Settings\TrueHUD.ini' = '2:bb'; ':gone:Data\Platform\thornswood-pass.txt' = 'removed'
                 ':gone:Data\Platform\voice-token.txt' = 'always'; ':profile:plugins.txt' = 'x' }
    $tgtMap = @{ 'Data\Platform\UI\index.html' = '1:cc'; 'Data\Platform\thornswood-pass.txt' = '3:dd'; 'Data\SKSE\Plugins\CommunityShaders\SettingsUser.json' = '4:ee'
                 'VERSION.bak' = '5:ff'; 'Data\textures\CharGen\Exported\Adventurer3424.dds' = '6:aa' }
    Invoke-Expression $filter
    Yes '  going back to an old record hands none of them out' (@($tgtMap.Keys) -join ',' -eq 'Data\Platform\UI\index.html')
    Yes '  going forward lists none as gone but the token every release deletes' (-not $curMap.ContainsKey(':gone:Data\Platform\thornswood-pass.txt') -and
        $curMap[':gone:Data\Platform\voice-token.txt'] -eq 'always' -and -not $curMap.ContainsKey('Data\MCM\Settings\TrueHUD.ini'))
    Yes '  the files of ours and the plugin list stay' ($curMap.ContainsKey('Data\Platform\UI\index.html') -and $curMap.ContainsKey(':profile:plugins.txt'))
    Yes ('  and it says how many it left out ({0})' -f $notThisMachine) ($notThisMachine -eq 6)
}

# ---- 6. Check-Secrets ----------------------------------------------------------
Write-Host ''; Write-Host 'Check-Secrets'
New-Item -ItemType Directory -Force -Path $T | Out-Null
Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
$zip = Join-Path $T 'pack.zip'
$z = [IO.Compression.ZipFile]::Open($zip, 'Create')
try {
    foreach ($n in 'game/Data/Platform/thornswood-pass.txt', 'game/Data/MCM/Settings/Precision.ini', 'game/Data/SKSE/Plugins/CommunityShaders_ImGui.ini',
                   'game/Data/Platform/Plugins/thornswood-front.js') {
        $e = $z.CreateEntry($n); $s = $e.Open(); try { $b = [Text.Encoding]::ASCII.GetBytes("x`n"); $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
    }
} finally { $z.Dispose() }
$allow = Join-Path $T 'no-allow.txt'; [IO.File]::WriteAllText($allow, "# nothing allowed`n")
$global:LASTEXITCODE = 0
# Check-Secrets writes a hit as a GitHub annotation when GITHUB_ACTIONS is
# true, which it is under the nightly on the VPS, and these lines read the
# form a person sees. test-check-secrets.ps1 checks the annotation form.
$savedActions = $env:GITHUB_ACTIONS
$env:GITHUB_ACTIONS = ''
try {
    $out = (@(& (Join-Path $repo 'scripts\dev\Check-Secrets.ps1') -Zip @($zip) -Allow $allow *>&1 | ForEach-Object { [string]$_ }) -join "`n")
    $code = $LASTEXITCODE
} finally { $env:GITHUB_ACTIONS = $savedActions }
Yes 'a pack carrying the join pass, mod menu settings and a window layout fails' ($code -eq 1)
foreach ($n in 'thornswood-pass.txt', 'Precision.ini', 'CommunityShaders_ImGui.ini') { Yes "  $n by Ship-Rules" ($out.Contains("$n`:0  never-ship-machine")) }
Yes '  and our own overlay beside them is not named' (-not $out.Contains('thornswood-front.js'))

# ---- 7. one question, asked everywhere ----------------------------------------
Write-Host ''; Write-Host 'one question, asked everywhere'
$rules = [IO.File]::ReadAllText((Join-Path $repo 'scripts\release\Ship-Rules.ps1'))
$sec = [IO.File]::ReadAllText((Join-Path $repo 'scripts\dev\Check-Secrets.ps1'))
$scrub = [IO.File]::ReadAllText((Join-Path $repo 'scripts\release\Scrub-Feed.ps1'))
Yes 'Test-ShipMachine asks it, so packs and the installer leave them out' ($rules -match 'function Test-ShipMachine\([^)]*\) \{[\s\S]*?if \(\(Test-ShipOneMachine \$rel\) -and -not \(Test-ShipRuntime \$rel\)\) \{ return \$true \}')
Yes 'Publish-Update''s scan asks Test-Machine and Test-Runtime' ($pub -match 'if \(Test-Runtime \$rel\) \{ continue \}' -and $pub -match 'if \(Test-Machine \$rel\) \{ continue \}')
Yes 'Check-Secrets asks it' ($sec -match "if \(\(Test-ShipOneMachine \`$rel\) -or \(Test-ShipMachine \`$rel\)\) \{ Write-Hit")
Yes 'Scrub-Feed asks it beside Bethesda''s' ($scrub -match 'function Test-ScrubMachinePath\([^)]*\) \{\s*return \(\(Test-ShipBethesda \$rel\) -or \(Test-ShipOneMachine \$rel\)\)' -and $scrub -match 'function Test-ScrubPath\([^)]*\) \{\s*return \(\(Test-ScrubMachinePath \$rel\)')
Yes 'the record guard and the rollback filter ask it' ($null -ne $guard -and $guard -match 'Test-ShipOneMachine \$_' -and $null -ne $filter -and $filter -match 'Test-ShipOneMachine \$p')
Yes 'the note over voice-token.txt no longer says the packs are left alone' ($rules -notmatch 'THE PUBLISHED PACKS ARE DELIBERATELY LEFT ALONE')

Done
