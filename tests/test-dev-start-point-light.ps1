<#
  test-dev-start-point-light.ps1

  Deploy-DevGamemode.ps1 puts the start point's file index at Skyrim
  Unbound.esp's place among the FULL plugins, not its place in the list
  (#2011).

  WHY. With an engine that loads light plugins (#1715) the dev loadOrder holds
  48 full and 54 light plugins, and a form id's top byte counts full plugins
  only. The block counted the list, so the dev deploy of 5 Oct 10:01 PM moved
  the start point to 0x5E19BAD4 (Unbound 94th in the list, 45th among full
  plugins), and at 11:00 PM a new character died at login with
    Error: FromFormId failed due to invalid file index 94 (5e19bad4)

  HOW. The same as test-dev-deploy-pass.ps1: the settings block is lifted out
  of the script, expanded here with the values the script would have (its
  counting function from ServerOrder.ps1, a light table and whether the record says the engine loads light plugins),
  and run in Windows PowerShell, what sshd runs on the box, against a
  server-settings.json in a temp folder. Nothing connects to anything.

  The last case is the measured one, and runs where this machine has the build
  the dev server runs (THORNSWOOD_DEV_SETTINGS, or the fork build under
  C:\ThornswoodTemps&Worktrees\worktrees\claude-1005-skymp) and the game folder
  whose headers say which plugins are light (C:\Thornswood\Game\Data);
  elsewhere it says SKIP.
#>
[CmdletBinding()]
param()
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$script = Join-Path $repo 'scripts\deploy\Deploy-DevGamemode.ps1'
. (Join-Path $repo 'scripts\deploy\ServerOrder.ps1')
$script:fullIndexDef = 'function Get-ThornswoodFullIndex {' + "`n" + (Get-Command Get-ThornswoodFullIndex).Definition + "`n}"

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

$text = [IO.File]::ReadAllText($script)
$start = $text.IndexOf("Write-Host 'Pointing the dev server at the dev voice service...'")
$open = $text.IndexOf('Remote @"', $start)
$close = $text.IndexOf('"@ | ForEach-Object', $open)
Yes 'the settings block is where it was' ($start -ge 0 -and $open -gt $start -and $close -gt $open)
$body = $text.Substring($open + 'Remote @"'.Length, $close - $open - 'Remote @"'.Length).Trim("`r", "`n")
Yes 'the block counts with Get-ThornswoodFullIndex, sent up with it' ($body.Contains('$fullIndexDef') -and $body.Contains("Get-ThornswoodFullIndex ([string[]]``"))
Yes 'and the script builds the light table with Test-ThornswoodPluginLight, the shared rule' ($text.Contains('Test-ThornswoodPluginLight $f.FullName'))

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-dev-start-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

# $light maps a plugin name to whether it is light; $loads is whether the
# engine loads light plugins, which the block takes from the record this
# commit holds (the check before anything is sent holds the box's to it).
function Run-Block($settings, [hashtable]$light, $loads) {
    $p = Join-Path $tmp 'server-settings.json'
    [IO.File]::WriteAllText($p, ($settings | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))
    $rootWin = $tmp
    $farOrder = ''
    $remotePlugins = 'C:/nowhere'
    $fullIndexDef = $script:fullIndexDef
    $lightTable = ((@($light.Keys) | ForEach-Object { "'{0}' = {1}" -f $_.ToLowerInvariant().Replace("'", "''"), $(if ($light[$_]) { '$true' } else { '$false' }) }) -join '; ')
    $devRecordLight = [bool]$loads
    $VoicePort = 7789
    $maxOnline = 0
    $seats = 0
    $LoadOrderRefuse = ''
    $RequirePass = ''
    $Npcs = ''
    $expanded = $ExecutionContext.InvokeCommand.ExpandString($body)
    $file = Join-Path $tmp 'block.ps1'
    [IO.File]::WriteAllText($file, $expanded, (New-Object Text.UTF8Encoding $true))
    $said = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file 2>&1 | ForEach-Object { "$_" }
    $after = Get-Content $p -Raw | ConvertFrom-Json
    return @{ said = ($said -join "`n"); start = [string]@($after.startPoints)[0].worldOrCell }
}
function Settings([string[]]$names, [string]$startAt) {
    return [ordered]@{
        port = 7787; thornswoodVoicePort = 7789; thornswoodServer = 'dev'; thornswoodRequirePass = $true
        equipmentSlotCheckEnabled = $false; equipmentSpellCheckEnabled = $false; equipmentInventoryCheckEnabled = $false
        npcAllowCrimeFaction = $true; npcAllowEssential = $true
        loadOrder = @($names | ForEach-Object { 'C:/Thornswood-Server-Dev/plugins/' + $_ })
        startPoints = @([ordered]@{ pos = @(1.0, 2.0, 3.0); worldOrCell = $startAt; angleZ = 90 })
    }
}

$order = @('Skyrim.esm', '_ResourcePack.esl', 'Full One.esp', 'Light One.esp', 'Skyrim Unbound.esp', 'Full Two.esp')
$light = @{ 'Skyrim.esm' = $false; 'Full One.esp' = $false; 'Light One.esp' = $true; 'Skyrim Unbound.esp' = $false; 'Full Two.esp' = $false }

try {
    # Unbound is fifth in the list (index 4), third among the full plugins (index 2).
    $r = Run-Block (Settings $order '0x0419BAD4') $light $true
    Yes 'with light plugins, a start point at the list position moves to the full index: 0x0219BAD4' ($r.start -eq '0x0219BAD4')
    Yes '  and says Unbound is full plugin 2' ($r.said -match 'Skyrim Unbound\.esp is full plugin 2' -and $r.said -match 'start point moved to 0x0219BAD4, index 2')

    $before = @(Get-ChildItem $tmp -Filter 'server-settings.json.before-*').Count
    $r = Run-Block (Settings $order '0x0219BAD4') $light $true
    Yes 'a start point already at the full index is left as it is' ($r.start -eq '0x0219BAD4' -and $r.said -notmatch 'start point moved')

    $r = Run-Block (Settings $order '0x0219BAD4') $light $false
    Yes 'on a box whose engine does not load light plugins every entry counts: 0x0419BAD4' ($r.start -eq '0x0419BAD4')
    # #2711: the block read the box's record itself, in a try with an empty
    # catch, so a record that did not read counted as no light plugins.
    Yes '  and the block reads no record on the box, so there is none to misread' ($body -notmatch 'server-build\.json' -and $body.Contains('$loadsLight = `$$devRecordLight'))

    $odd = @('Skyrim.esm', 'Mystery.esp', 'Skyrim Unbound.esp')
    $r = Run-Block (Settings $odd '0x0919BAD4') $light $true
    Yes 'a plugin this machine cannot read leaves the start point alone' ($r.start -eq '0x0919BAD4')
    Yes '  and says which' ($r.said -match 'cannot tell whether mystery\.esp is light, so the start point is left alone')

    # The measured case: the order the dev server runs, its headers from the game folder.
    $devSettings = $env:THORNSWOOD_DEV_SETTINGS
    if (-not $devSettings) { $devSettings = 'C:\ThornswoodTemps&Worktrees\worktrees\claude-1005-skymp\build\dist\server\server-settings.json' }
    $data = 'C:\Thornswood\Game\Data'
    if ((Test-Path -LiteralPath $devSettings) -and (Test-Path -LiteralPath $data)) {
        $names = @((Get-Content -LiteralPath $devSettings -Raw | ConvertFrom-Json).loadOrder | ForEach-Object { [IO.Path]::GetFileName(([string]$_).Replace('/', '\')) })
        $real = @{}
        foreach ($n in $names) { $f = Join-Path $data $n; if (Test-Path -LiteralPath $f) { $real[$n] = Test-ThornswoodPluginLight $f } }
        $listAt = [Array]::IndexOf([string[]]$names, 'Skyrim Unbound.esp')
        Write-Host ("      the dev order: {0} plugins, {1} light, Unbound {2} in the list" -f $names.Count, @($real.Values | Where-Object { $_ }).Count, $listAt)
        $r = Run-Block (Settings $names '0x5E19BAD4') $real $true
        Yes ('the dev server''s own order: 0x5E19BAD4, as the 10:01 PM deploy wrote it, moves to 0x2D19BAD4 (' + $r.start + ')') ($r.start -eq '0x2D19BAD4')
    } else {
        Write-Host 'SKIP  the dev server''s own order: no build or game folder here'
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
