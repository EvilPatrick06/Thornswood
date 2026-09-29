<#
  test-no-bethesda-files.ps1

  No file of Bethesda's is ever packed, put in the installer or named in a
  release record: not the game, not its Creation Kit, not a copy of one of its
  programs. And no backup either. Issue #1152.

  WHY THIS EXISTS. On 29 September the dev record the feed named
  (20260929-0259-dev) listed 2,515 files of ours, and about 180 MB of them were
  Bethesda's: CreationKit.exe and its settings, the Tools, Papyrus Compiler and
  lex folders, flowchartx64.dll, flowchartx32.dll, p4com64.dll, 1,785 files
  under Data\DialogueViews, Data\Scripts.zip, and SkyrimSE.exe.bak-1160-for-369,
  a copy of Skyrim itself. Main pack 20260926-1603 carried the Creation Kit and
  the copy of the game. Steam puts the Creation Kit in the Steam copy, the
  launcher's own folder took it from there, and a file Vortex did not deploy
  counted as ours.

  What this holds, each against the real code:
    1. Ship-Rules: every path of that measurement is never shipped and never
       listed as removed; the game's own files too; any backup; the files of
       ours beside them still ship.
    2. The measured record itself, where this machine has it
       (%LOCALAPPDATA%\Thornswood\feed\dev\published.json): every Creation Kit
       entry in it is caught, and none of Data\Platform is.
    3. Check-Secrets, which reads every pack, the installer's stage and a first
       record before anything is sent: a pack or stage carrying any of them
       fails, by rule name.
    4. Publish-Update's record guard and Rollback-Feed's filter, each lifted out
       of the shipped script between its markers and run.
    5. The launcher: OwnGame.BethesdaTool, lifted and compiled, agrees with
       Ship-Rules on every path, finds exactly those files in a scratch folder,
       Refresh drops them, and Rules moved so every folder refreshes once.

  Read only apart from its own scratch folder. Never connects to anything.
#>
[CmdletBinding()]
param([string]$Record)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$RulesPath   = Join-Path $Repo 'scripts\release\Ship-Rules.ps1'
$PublishPath = Join-Path $Repo 'scripts\release\Publish-Update.ps1'
$RollPath    = Join-Path $Repo 'scripts\release\Rollback-Feed.ps1'
$PackagePath = Join-Path $Repo 'scripts\release\Package-Thornswood.ps1'
$SecretsPath = Join-Path $Repo 'scripts\dev\Check-Secrets.ps1'
$OwnGamePath = Join-Path $Repo 'launcher\app\OwnGame.cs'
if (-not $Record) { $Record = Join-Path $env:LOCALAPPDATA 'Thornswood\feed\dev\published.json' }

$script:pass = 0
$script:fail = 0
$script:skip = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Skip([string]$what) { $script:skip++; Write-Host "SKIP  $what" }
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed, {2} skipped" -f $script:pass, $script:fail, $script:skip)
    if ($script:fail) { exit 1 }
    exit 0
}

. $RulesPath

# ---- 1. Ship-Rules ----------------------------------------------------------
#
# One path of each kind the dev record of 29 September carried, by its own name.
$bethesda = @(
    'CreationKit.exe', 'CreationKit.ini', 'CreationKitPrefs.ini', 'CreationKitCustom.ini',
    'flowchartx64.dll', 'flowchartx32.dll', 'p4com64.dll',
    'EditorWarnings.txt', 'DataFiles.txt', 'SkyrimReservedAddOnIndexes.txt',
    'Tools\AssetWatcher\AssetWatcher.exe', 'Tools\redist\VC_redist.x64.exe', 'Tools\RoboVoicer.exe',
    'Tools\LipGen\LipGenerator\FonixData.cdf', 'Tools\HavokBehaviorPostProcess\HavokBehaviorPostProcess.exe',
    'Papyrus Compiler\PapyrusCompiler.exe', 'Papyrus Compiler\ScriptCompile.bat',
    'lex\ssceam.tlx', 'lex\User\userdic.tlx',
    'Data\DialogueViews\0001A2A8.xml', 'Data\Scripts.zip',
    'SkyrimSE.exe.bak-1160-for-369', 'SkyrimSE.exe.1170', 'SkyrimSELauncher.exe.old', 'skse64_loader.exe.bak'
)
foreach ($rel in $bethesda) {
    Yes "$rel is Bethesda's" (Test-ShipBethesdaTool $rel)
    Yes '  never shipped and never listed as removed' (Test-ShipMachine $rel)
    Yes '  never swept off anybody as a runtime file' (-not (Test-ShipRuntime $rel))
}
Yes 'none of them is on the list every pack deletes' (@($bethesda | Where-Object { @(Get-ShipDeleteAlways) -contains $_ }).Count -eq 0)
Yes 'the Creation Kit rule matches in any case' ((Test-ShipBethesdaTool 'creationkit.EXE') -and (Test-ShipBethesdaTool 'data\dialogueviews\x.xml'))

# The game itself was never shipped, and still is not.
foreach ($rel in @('SkyrimSE.exe', 'SkyrimSELauncher.exe', 'steam_api64.dll', 'Data\Skyrim.esm', 'Data\Update.esm',
                   'Data\Skyrim - Textures0.bsa', 'Data\ccBGSSSE001-Fish.esm', 'Data\MarketplaceTextures.bsa',
                   'Data\Strings\skyrim_english.strings', '_DowngraderBackups\SkyrimSE.exe')) {
    Yes "$rel, the game's own, is never shipped" (Test-ShipMachine $rel)
}

# Any backup, anywhere, never ships and is never removed.
foreach ($rel in @('VERSION.bak', 'Data\SKSE\Plugins\SkyrimPlatform.ini.bak',
                   'Data\SKSE\Plugins\SkyrimPlatform.ini.2026-09-19T20-17-00-253Z.bak',
                   'plugins.txt.bak-elysium-20260927-000739', 'Data\textures\x.dds.bak.1')) {
    Yes "$rel is a backup, never shipped and never removed" ((Test-ShipBackup $rel) -and (Test-ShipMachine $rel) -and -not (Test-ShipRuntime $rel))
}

# One person's face tint, which the same record carried, is runtime.
Yes 'a face tint RaceMenu exported is written at runtime and never shipped' (Test-ShipRuntime 'Data\textures\CharGen\Exported\Adventurer3424.dds')

# The files of ours beside them still ship: the rules are anchored.
foreach ($rel in @('Data\Thornswood-Content.esp', 'Data\Platform\UI\index.html', 'Data\Platform\Plugins\thornswood-front.js',
                   'Data\Platform\UI\thornswood-bake.js', 'Data\meshes\interface\logo\logo.nif',
                   'Data\textures\interface\objects\Mainmenuwallpaper.dds', 'Data\music\special\mus_maintheme.xwm',
                   'Data\meshes\tools\hammer.nif', 'Data\DialogueViewsExtra\x.xml', 'Data\textures\CreationKitLogo.dds',
                   'Data\Scripts\bakery.pex', 'Data\SKSE\Plugins\Tools.ini')) {
    Yes "$rel is not taken for Bethesda's or a backup" (-not (Test-ShipBethesdaTool $rel) -and -not (Test-ShipBackup $rel) -and -not (Test-ShipMachine $rel))
}

# ---- 2. the measured record ---------------------------------------------------
if (Test-Path -LiteralPath $Record) {
    $map = ((Get-Content -LiteralPath $Record -Raw) -replace '^﻿', '') | ConvertFrom-Json
    $keys = @($map.PSObject.Properties.Name | Where-Object { -not $_.StartsWith(':') })
    # What #1152 counted as the Creation Kit: everything at the game's root, the
    # dialogue views and the script sources archive.
    $ck = @($keys | Where-Object { $_.IndexOf('\') -lt 0 -or $_ -like 'Tools\*' -or $_ -like 'Papyrus Compiler\*' -or $_ -like 'lex\*' -or $_ -like 'Data\DialogueViews\*' -or $_ -eq 'Data\Scripts.zip' })
    $caught = @($ck | Where-Object { Test-ShipMachine $_ })
    $ckBytes = [int64]0; foreach ($k in $ck) { $ckBytes += [int64](([string]$map.$k).Split(':')[0]) }
    Write-Host ("      the record: {0:n0} files of ours, {1:n0} of them at the root or the Creation Kit's ({2:n1} MB)" -f $keys.Count, $ck.Count, ($ckBytes / 1MB))
    if ($ck.Count) {
        Yes ('every one of those {0:n0} is caught' -f $ck.Count) ($caught.Count -eq $ck.Count)
        foreach ($m in @($ck | Where-Object { -not (Test-ShipMachine $_) } | Select-Object -First 5)) { Write-Host "      not caught: $m" }
    } else { Skip 'this record has no Creation Kit files left to measure' }
    $platform = @($keys | Where-Object { $_ -like 'Data\Platform\*' })
    Yes ('and none of its {0} Data\Platform files is' -f $platform.Count) (@($platform | Where-Object { (Test-ShipBethesdaTool $_) -or (Test-ShipBackup $_) }).Count -eq 0)
} else {
    Skip "no dev record at $Record to measure against"
}

# ---- 3. Check-Secrets, over a pack and a stage ---------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-nobethesda-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function New-Zip([string]$path, [string[]]$entries) {
    $z = [IO.Compression.ZipFile]::Open($path, 'Create')
    try {
        foreach ($e in $entries) {
            $s = $z.CreateEntry($e).Open()
            try { $b = [Text.Encoding]::ASCII.GetBytes('x'); $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
        }
    } finally { $z.Dispose() }
}
$ps = (Get-Process -Id $PID).Path
function Invoke-Secrets([string[]]$argv) {
    $out = & $ps -NoProfile -File $SecretsPath @argv 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
try {
    $bad = Join-Path $tmp 'pack-bad.zip'
    New-Zip $bad @('game/CreationKit.exe', 'game/SkyrimSE.exe.bak-1160-for-369', 'game/Data/DialogueViews/0001A2A8.xml',
                   'game/Tools/RoboVoicer.exe', 'game/SkyrimSE.exe', 'game/Data/SKSE/Plugins/SkyrimPlatform.ini.bak')
    $r = Invoke-Secrets @('-Zip', $bad)
    Yes 'a pack carrying the Creation Kit or a copy of the game fails' ($r.Code -eq 1)
    Yes '  naming the Creation Kit by rule' ($r.Out.Contains('game/CreationKit.exe:0  never-ship-bethesda'))
    Yes '  and the copy of the game' ($r.Out.Contains('game/SkyrimSE.exe.bak-1160-for-369:0  never-ship-bethesda'))
    Yes '  and its dialogue views and tools' ($r.Out.Contains('game/Data/DialogueViews/0001A2A8.xml:0  never-ship-bethesda') -and $r.Out.Contains('game/Tools/RoboVoicer.exe:0  never-ship-bethesda'))
    Yes '  and the game itself' ($r.Out.Contains('game/SkyrimSE.exe:0  never-ship-bethesda'))
    Yes '  and a backup' ($r.Out.Contains('SkyrimPlatform.ini.bak:0  never-ship-backup'))

    $good = Join-Path $tmp 'pack-good.zip'
    New-Zip $good @('game/Data/Platform/Plugins/thornswood-front.js', 'game/Data/meshes/interface/logo/logo.nif')
    $r = Invoke-Secrets @('-Zip', $good)
    Yes 'a pack of ours alone passes' ($r.Code -eq 0)

    $stage = Join-Path $tmp 'stage'
    New-Item -ItemType Directory -Force -Path (Join-Path $stage 'payload\Papyrus Compiler') | Out-Null
    [IO.File]::WriteAllText((Join-Path $stage 'payload\Papyrus Compiler\PapyrusCompiler.exe'), 'x')
    $r = Invoke-Secrets @('-Dir', $stage)
    Yes 'an installer stage carrying the Papyrus compiler fails' ($r.Code -eq 1 -and $r.Out.Contains('never-ship-bethesda'))
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# The installer and the packs both leave them out by the same rule, and both
# are read by Check-Secrets before anything leaves.
$pkg = Get-Content -LiteralPath $PackagePath -Raw
Yes 'the installer''s scan asks Test-ShipMachine' ($pkg -match 'if \(Test-ShipMachine \$rel\)')
Yes '  and its stage goes through Check-Secrets' ($pkg -match "Check-Secrets\.ps1'\) -Dir \`$stage")
$pub = Get-Content -LiteralPath $PublishPath -Raw
Yes 'the packs'' scan asks Test-Machine' ($pub -match 'if \(Test-Machine \$rel\) \{ continue \}')
Yes '  and every pack goes through Check-Secrets' ($pub -match "Check-Secrets\.ps1'\) -Zip \`$scanZips")

# ---- 4. the record guard and the rollback filter ------------------------------
function Get-Block([string]$src, [string]$name) {
    $a = $src.IndexOf("# ==== thornswood $name ====")
    $b = $src.IndexOf("# ==== end thornswood $name ====")
    if ($a -lt 0 -or $b -le $a) { return $null }
    return $src.Substring($a, $b - $a)
}
$guard = Get-Block $pub 'no bethesda in the record'
Yes 'the record guard is in Publish-Update.ps1' ($null -ne $guard)
if ($guard) {
    $at = $pub.IndexOf('# ==== thornswood no bethesda in the record ====')
    Yes '  inside the record files block, before anything is sent' ($at -gt $pub.IndexOf('# ==== thornswood record files ====') -and $at -lt $pub.IndexOf('$recordFiles = @()'))
    function Die($m) { throw "STOP $m" }
    function Invoke-Guard($map) {
        $now = $map
        try { Invoke-Expression $guard; return '' } catch { return $_.Exception.Message }
    }
    $clean = @{ 'Data\Platform\UI\index.html' = '1:aa'; ':gone:Data\Interface\map.swf' = 'always'; ':order:plugins' = 'x' }
    Yes '  a record of ours alone goes through' ((Invoke-Guard $clean) -eq '')
    foreach ($k in @('CreationKit.exe', 'SkyrimSE.exe.bak-1160-for-369', 'Data\DialogueViews\1.xml', 'SkyrimSE.exe', 'VERSION.bak', ':gone:Tools\RoboVoicer.exe')) {
        $m = @{} + $clean; $m[$k] = '1:bb'
        $why = Invoke-Guard $m
        Yes "  a record naming $k stops the release" ($why -like 'STOP*Bethesda*')
    }
}
$roll = Get-Content -LiteralPath $RollPath -Raw
$filter = Get-Block $roll 'no bethesda in a rollback'
Yes 'the rollback filter is in Rollback-Feed.ps1' ($null -ne $filter)
Yes '  which reads Ship-Rules' ($roll -match "\. \(Join-Path \`$Here 'Ship-Rules\.ps1'\)")
if ($filter) {
    Yes '  and runs before the new record is worked out' ($roll.IndexOf('# ==== thornswood no bethesda in a rollback ====') -lt $roll.IndexOf('$newMap = @{}'))
    function Say($m, $c) { }
    $curMap = @{ 'Data\Platform\UI\index.html' = '1:aa'; 'CreationKit.exe' = '2:bb'; ':gone:lex\ssceam.tlx' = 'removed'; ':profile:plugins.txt' = 'x' }
    $tgtMap = @{ 'Data\Platform\UI\index.html' = '1:cc'; 'SkyrimSE.exe.bak-1160-for-369' = '3:dd'; 'Data\DialogueViews\1.xml' = '4:ee' }
    Invoke-Expression $filter
    Yes '  going back to an old record hands none of them out' (-not $tgtMap.ContainsKey('SkyrimSE.exe.bak-1160-for-369') -and -not $tgtMap.ContainsKey('Data\DialogueViews\1.xml'))
    Yes '  and going forward lists none of them as gone' (-not $curMap.ContainsKey('CreationKit.exe') -and -not $curMap.ContainsKey(':gone:lex\ssceam.tlx'))
    Yes '  while the files of ours and the plugin list stay' ($curMap.ContainsKey('Data\Platform\UI\index.html') -and $tgtMap.ContainsKey('Data\Platform\UI\index.html') -and $curMap.ContainsKey(':profile:plugins.txt'))
    Yes ('  and it says how many it left out ({0})' -f $notOurs) ($notOurs -eq 4)
}

# ---- 5. the launcher --------------------------------------------------------
$og = [IO.File]::ReadAllText($OwnGamePath)
function Get-CsMember([string]$text, [string]$signature) {
    $at = $text.IndexOf($signature)
    if ($at -lt 0) { return $null }
    $i = $text.IndexOf('{', $at)
    $depth = 0
    while ($i -lt $text.Length) {
        $c = $text[$i]
        if ($c -eq '"') { $i++; while ($i -lt $text.Length -and $text[$i] -ne '"') { if ($text[$i] -eq '\') { $i++ }; $i++ } }
        elseif ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($at, $i + 1 - $at) } }
        $i++
    }
    return $null
}
$lift = [ordered]@{
    Dirs  = Get-CsMember $og 'static readonly string[] BethesdaToolDirs ='
    Files = Get-CsMember $og 'static readonly string[] BethesdaToolFiles ='
    Test  = Get-CsMember $og 'static bool BethesdaTool(string rel)'
    In    = Get-CsMember $og 'static List<string> BethesdaToolsIn(string folder)'
}
$missing = @($lift.Keys | Where-Object { -not $lift[$_] })
Yes 'OwnGame has BethesdaTool, its two lists and BethesdaToolsIn to lift' ($missing.Count -eq 0)
if ($missing.Count) { Done }
$ns = 'TsNoBethesda' + $PID
$cs = @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
namespace $ns
{
    public static class Swallow { public static void Note(string where, Exception e) { } }
    public static class OwnGame
    {
        $($lift.Dirs);
        $($lift.Files);
        public $($lift.Test)
        public $($lift.In)
    }
}
"@
$compiled = $true
try { Add-Type -TypeDefinition $cs -Language CSharp } catch { $compiled = $false; Write-Host ('      ' + $_.Exception.Message) }
Yes 'and they compile as lifted' $compiled
if ($compiled) {
    $T = [type]($ns + '.OwnGame')
    $twins = @($bethesda) + @('SkyrimSE.exe', 'SkyrimSELauncher.exe', 'skse64_loader.exe',
        'Data\Thornswood-Content.esp', 'Data\Platform\UI\index.html', 'Data\meshes\tools\hammer.nif',
        'Data\DialogueViewsExtra\x.xml', 'Data\textures\CreationKitLogo.dds', 'Data\SKSE\Plugins\Tools.ini')
    $apart = @($twins | Where-Object { [bool]$T::BethesdaTool($_) -ne [bool](Test-ShipBethesdaTool $_) })
    Yes ('OwnGame.BethesdaTool and Test-ShipBethesdaTool agree on all {0} paths' -f $twins.Count) ($apart.Count -eq 0)
    foreach ($a in $apart) { Write-Host "      they disagree on $a" }

    $game = Join-Path ([IO.Path]::GetTempPath()) ('ts-nobethesda-game-' + $PID)
    try {
        $plant = @('CreationKit.exe', 'SkyrimSE.exe.bak-1160-for-369', 'p4com64.dll', 'Tools\Archive\Archive.exe',
                   'Papyrus Compiler\PapyrusCompiler.exe', 'lex\User\correct.tlx', 'Data\DialogueViews\0001.xml', 'Data\Scripts.zip')
        $ours = @('SkyrimSE.exe', 'Data\Thornswood-Content.esp', 'Data\Platform\UI\index.html', 'Data\meshes\tools\hammer.nif')
        foreach ($p in $plant + $ours) {
            $f = Join-Path $game $p
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f) | Out-Null
            [IO.File]::WriteAllText($f, 'x')
        }
        $found = @($T::BethesdaToolsIn($game) | ForEach-Object { $_.Substring($game.Length + 1) })
        Yes ('BethesdaToolsIn finds all {0} planted in a game folder' -f $plant.Count) (@($plant | Where-Object { $found -notcontains $_ }).Count -eq 0)
        Yes '  and nothing of ours' (@($ours | Where-Object { $found -contains $_ }).Count -eq 0)
        Yes '  each once' ($found.Count -eq $plant.Count)
    } finally {
        Remove-Item -LiteralPath $game -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$skipCs = Get-CsMember $og 'static string Skip(string rel)'
Yes 'OwnGame.Skip leaves them out of the folder' ($skipCs -match 'if \(BethesdaTool\(rel\)\) return "')
$refresh = Get-CsMember $og 'public static string Refresh(Config cfg, Action<string> say)'
Yes 'Refresh drops them from a folder that has them' ($null -ne $refresh -and $refresh -match 'foreach \(string dest in BethesdaToolsIn\(Folder\)\)\s*\{\s*try \{ if \(File\.Exists\(dest\)\) \{ DropName\(dest\); removed\+\+; \} \}')
$rulesNum = [regex]::Match($og, '(?m)^\s*const int Rules = (\d+);')
$rulesDoc = [regex]::Match($og, "(?m)^\s*/// (\d+): Bethesda's Creation Kit")
Yes 'Rules moved for it, so every folder already made refreshes once and drops them' (
    $rulesNum.Success -and $rulesDoc.Success -and [int]$rulesNum.Groups[1].Value -ge [int]$rulesDoc.Groups[1].Value)

Done
