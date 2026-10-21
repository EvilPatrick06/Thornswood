<#
  test-mustcopy-distribution.ps1

      pwsh -NoProfile -File .\tests\test-mustcopy-distribution.ps1

  OwnGame.MustCopy hard-links Vortex's Data\Platform\Distribution redistributables
  (the 67 CEF, Node and shader compiler files the collection's Client Runtime
  1.0.1 carries) and keeps copying the two
  recorded client-build files under that folder, and everything else under
  Data\Platform. Issue #392 / rules 6.

  WHAT IT CHECKS.
    1. Rules is 6 and the history comment names Distribution redistributables,
       so every folder made under 5 refreshes once.
    2. MustCopy, ClientFile, ClientFiles, CopyTypes, Masters and Generated,
       lifted from launcher\app\OwnGame.cs and compiled with the compiler the
       build runs (Add-LauncherType, tests\Launcher-Csc.ps1, #2821), over
       files.txt-shaped
       inputs: the 67 Distribution rows marked V come out linked; the two
       recorded Distribution paths come out copied whether or not they are in
       the deployed set; other Data\Platform paths stay copied.
    3. On this machine, where Profile\OwnGame\files.txt exists, the real
       Distribution V rows are asked the same way, and there are as many as
       THIRD-PARTY.md's Client Runtime section says the mod has.

  Read only apart from the compiled dll, under the temp folder and removed
  once loaded. Off Windows, 2 and 3 say SKIP: the build's compiler is only
  there.
#>
[CmdletBinding()]
param(
    [string]$FilesList = 'C:\Thornswood\Profile\OwnGame\files.txt',
    [string]$AppPath
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $AppPath) { $AppPath = Join-Path $Repo 'launcher\app' }
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#2821)

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail -gt 0) { exit 1 }
    exit 0
}

$ogPath = Join-Path $AppPath 'OwnGame.cs'
Yes 'launcher\app\OwnGame.cs is there' (Test-Path -LiteralPath $ogPath)
if (-not (Test-Path -LiteralPath $ogPath)) { Done }
$og = [IO.File]::ReadAllText($ogPath)

$rulesNum = [regex]::Match($og, '(?m)^\s*const int Rules = (\d+);')
$rulesDoc = [regex]::Match($og, '(?m)^\s*/// (\d+): Vortex''s Data\\Platform\\Distribution redistributables')
# At least 6, not equal to it: rules 7 (Start On Save left out, #394) moved it
# on past this change on purpose.
Yes 'OwnGame.Rules is at least 6 for the Distribution hard-link change' (
    $rulesNum.Success -and [int]$rulesNum.Groups[1].Value -ge 6)
Yes 'and the history comment names Distribution redistributables under that number' (
    $rulesDoc.Success -and $rulesDoc.Groups[1].Value -eq '6')

# Refresh used to re-link every !MustCopy Vortex file with Links<=1, which undid
# Fix's light-flag Separates on plugins (CBBE.esp). Relink is Distribution only.
# Since #2210 it is a one-time move, made only in a folder older than rule 6.
Yes 'Refresh re-link of Vortex copies is scoped to Data\Platform\Distribution, once (rule 6)' (
    $og.Contains("bool relink = rule6 && !must && origin == 'V'") -and
    $og.Contains('else if (relink && names <= 1)') -and
    $og.Contains('f.Rel.StartsWith("Data\\Platform\\Distribution\\"') -and
    $og.Contains('Only Distribution: a broader !MustCopy re-link also') -and
    $og.Contains('CBBE.esp'))
# Refresh no-op when deployment stamp and rules already match: skip WhyNot/Gather/Links.
Yes 'Refresh returns already-matches before WhyNot when stamp and rules match' (
    $og.Contains('DeploymentStamp(src) == Recorded("deployment")') -and
    $og.Contains('Recorded("rules") == Rules') -and
    $og.Contains('Recorded("deployment") != 0') -and
    $og.IndexOf('DeploymentStamp(src) == Recorded("deployment")') -lt $og.IndexOf('string why = WhyNot(cfg, src);', $og.IndexOf('public static string Refresh')))

# SettleSettings on Refresh must not overwrite Live plugins.txt with Golden.
Yes 'SettleSettings copies Golden plugins.txt only when the Profile list is missing' (
    $og.Contains('if (!File.Exists(dest)) File.Copy(shipped, dest, true);') -and
    -not $og.Contains('if (first || !File.Exists(dest))') -and
    $og.Contains('Thornswood-Content'))

$shellOwn = [IO.File]::ReadAllText((Join-Path $AppPath 'ShellOwnGame.cs'))
Yes 'Bring it up to date applies PutInServerOrder after FlagLight' (
    $shellOwn.Contains('Verify.PutInServerOrder(c, say)') -and
    $shellOwn.Contains('Checks.FlagLight(Verify.MustBeLight(c), say)') -and
    $shellOwn.IndexOf('FlagLight(Verify.MustBeLight') -lt $shellOwn.IndexOf('PutInServerOrder(c, say)'))
Yes 'Bring it up to date skips Bytes CRC when Refresh already matched' (
    $shellOwn.Contains('Verify.Run(c, !already)') -and
    $shellOwn.Contains('already matches what Vortex has deployed'))

$verify = [IO.File]::ReadAllText((Join-Path $AppPath 'Verify.cs'))
Yes 'Verify.Run accepts checkBytes and PutInServerOrder is public for ShellOwnGame' (
    $verify.Contains('public static List<Issue> Run(Config cfg, bool checkBytes)') -and
    $verify.Contains('public static int PutInServerOrder(Config cfg, Action<string> say)') -and
    $verify.Contains('if (checkBytes)'))

function Get-CsMember([string]$text, [string]$declaration) {
    $at = $text.IndexOf($declaration, [StringComparison]::Ordinal)
    if ($at -lt 0) { return $null }
    $i = $text.IndexOf('{', $at + $declaration.Length)
    if ($i -lt 0) { return $null }
    $depth = 0
    while ($i -lt $text.Length) {
        $c = $text[$i]
        $n = if ($i + 1 -lt $text.Length) { $text[$i + 1] } else { [char]0 }
        if ($c -eq '/' -and $n -eq '/') { $i = $text.IndexOf("`n", $i); if ($i -lt 0) { return $null }; continue }
        if ($c -eq '/' -and $n -eq '*') { $i = $text.IndexOf('*/', $i + 2); if ($i -lt 0) { return $null }; $i += 2; continue }
        if ($c -eq '@' -and $n -eq '"') {
            $i += 2
            while ($i -lt $text.Length) {
                if ($text[$i] -eq '"') { if ($i + 1 -lt $text.Length -and $text[$i + 1] -eq '"') { $i += 2; continue }; break }
                $i++
            }
            $i++; continue
        }
        if ($c -eq '"' -or $c -eq "'") {
            $q = $c; $i++
            while ($i -lt $text.Length -and $text[$i] -ne $q) { if ($text[$i] -eq '\') { $i++ }; $i++ }
            $i++; continue
        }
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { return $text.Substring($at, $i + 1 - $at) }
        }
        $i++
    }
    return $null
}

$clientFiles = Get-CsMember $og 'public static readonly string[] ClientFiles ='
if ($clientFiles -and -not $clientFiles.TrimEnd().EndsWith(';')) { $clientFiles = $clientFiles.TrimEnd() + ';' }
$lifted = [ordered]@{
    'ClientFiles' = $clientFiles
    'ClientFile'  = Get-CsMember $og 'public static bool ClientFile(string rel)'
    'CopyTypes'   = ((Get-CsMember $og 'static readonly string[] CopyTypes =') + ';')
    'Masters'     = ((Get-CsMember $og 'static readonly string[] Masters =') + ';')
    'Generated'   = Get-CsMember $og 'static bool Generated(string rel)'
    'MustCopy'    = Get-CsMember $og 'public static bool MustCopy(string rel, HashSet<string> deployed)'
}
# MustCopy asks OwnGameShare.cs whether a file is one of Skyrim's archives
# since #1218; taken from there where that file exists.
$sharePath = Join-Path $AppPath 'OwnGameShare.cs'
if (Test-Path -LiteralPath $sharePath) {
    $lifted['IsArchive'] = Get-CsMember ([IO.File]::ReadAllText($sharePath)) 'public static bool IsArchive(string rel)'
}
foreach ($k in @($lifted.Keys)) {
    Yes "lifted $k from OwnGame.cs" ([bool]$lifted[$k])
}
if (@($lifted.Values | Where-Object { -not $_ }).Count -gt 0) { Done }
if (-not $OnWindows) {
    Write-Host 'SKIP  2 and 3, MustCopy and its helpers compiled and asked: its compiler is the Roslyn csc that comes with Visual Studio''s Build Tools, which only Windows has'
    Done
}

$ns = 'MustCopyDist_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$cs = @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
namespace $ns {
    public static class OwnGame {
        $($lifted['ClientFiles'])
        $($lifted['ClientFile'])
        $($lifted['CopyTypes'])
        $($lifted['Masters'])
        $($lifted['Generated'])
        $($lifted['MustCopy'])
        $($lifted['IsArchive'])
    }
}
"@
$compiled = $true
try { $null = Add-LauncherType -Source $cs }
catch {
    $compiled = $false
    Write-Host ('      ' + $_.Exception.Message)
}
Yes 'MustCopy and its helpers compile as lifted, with the compiler the build runs' $compiled
if (-not $compiled) { Done }

$T = [type]("$ns.OwnGame")
$impl = 'Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformImpl.dll'
$cef  = 'Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformCEF.exe.hidden'

# Synthetic files.txt-shaped set: 67 redistributables + 2 recorded + other Platform.
$redis = @(
    'Data\Platform\Distribution\RuntimeDependencies\chrome_elf.dll',
    'Data\Platform\Distribution\RuntimeDependencies\d3dcompiler_47.dll',
    'Data\Platform\Distribution\RuntimeDependencies\icudtl.dat',
    'Data\Platform\Distribution\RuntimeDependencies\libcef.dll',
    'Data\Platform\Distribution\RuntimeDependencies\libEGL.dll',
    'Data\Platform\Distribution\RuntimeDependencies\libGLESv2.dll',
    'Data\Platform\Distribution\RuntimeDependencies\libnode.dll',
    'Data\Platform\Distribution\RuntimeDependencies\snapshot_blob.bin',
    'Data\Platform\Distribution\RuntimeDependencies\v8_context_snapshot.bin'
)
# Pad to 67 with distinct fake names under Distribution so the count is the mod's.
while ($redis.Count -lt 67) {
    $redis += ('Data\Platform\Distribution\RuntimeDependencies\pad{0:d2}.dll' -f $redis.Count)
}
$otherPlatform = @(
    'Data\Platform\Plugins\skymp5-client.js',
    'Data\Platform\UI\index.html',
    'Data\Platform\overlay-boot.count',
    'Data\Platform\Modules\skyrimPlatform.ts'
)

$deployed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($r in $redis) { [void]$deployed.Add($r) }

$linked = @($redis | Where-Object { -not $T::MustCopy($_, $deployed) })
Yes ("the 67 Distribution redistributables from Vortex are linked ({0} of 67)" -f $linked.Count) ($linked.Count -eq 67)

Yes 'SkyrimPlatformImpl.dll is copied when not in the deployed set' ($T::MustCopy($impl, $deployed))
Yes 'SkyrimPlatformCEF.exe.hidden is copied when not in the deployed set' ($T::MustCopy($cef, $deployed))

# Even if Vortex somehow listed them, ClientFile keeps them copied.
$withRec = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($r in $redis) { [void]$withRec.Add($r) }
[void]$withRec.Add($impl); [void]$withRec.Add($cef)
Yes 'SkyrimPlatformImpl.dll stays copied even if Vortex listed it' ($T::MustCopy($impl, $withRec))
Yes 'SkyrimPlatformCEF.exe.hidden stays copied even if Vortex listed it' ($T::MustCopy($cef, $withRec))

$otherStay = @($otherPlatform | Where-Object { $T::MustCopy($_, $deployed) })
Yes ("everything else under Data\Platform stays copied ({0} of {1})" -f $otherStay.Count, $otherPlatform.Count) (
    $otherStay.Count -eq $otherPlatform.Count)

# #1218: whatever Vortex did not deploy is the game's own and is copied, so
# nothing done to the Steam copy reaches it; Skyrim's archives are the one
# exception, linked only through Share (test-own-folder-alone.ps1).
if ($lifted.Contains('IsArchive')) {
    Yes 'a game file Vortex did not deploy is copied (#1218)' ($T::MustCopy('Data\meshes\clutter\bucket.nif', $deployed))
    Yes 'the same file deployed by Vortex is linked' (-not $T::MustCopy('Data\meshes\clutter\bucket.nif', (New-Object 'System.Collections.Generic.HashSet[string]' (,[string[]]@('Data\meshes\clutter\bucket.nif')))))
    Yes 'one of Skyrim''s archives is not copied: Share decides' (-not $T::MustCopy('Data\Skyrim - Textures0.bsa', $deployed))
}

# Real files.txt when present.
if (Test-Path -LiteralPath $FilesList) {
    $rows = @(Get-Content -LiteralPath $FilesList | ForEach-Object {
        $p = $_ -split '\|', 5
        if ($p.Count -eq 5) {
            [pscustomobject]@{ Kind = $p[0]; Origin = $p[1]; Rel = $p[4] }
        }
    })
    $realDist = @($rows | Where-Object { $_.Rel -like 'Data\Platform\Distribution\*' -and $_.Origin -eq 'V' })
    # As many as the Client Runtime the collection installs has, which
    # THIRD-PARTY.md gives (tests\test-third-party.js holds it to the mod).
    $notices = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\THIRD-PARTY.md'))
    $modCount = if ($notices -match '(?s)## Thornswood Client Runtime.*?It is the largest thing somebody else wrote that Thornswood hands out: (\d+)\s+files,') { [int]$Matches[1] } else { -1 }
    Yes ("this machine's files.txt has the Client Runtime's {0} Distribution rows from Vortex (has {1})" -f $modCount, $realDist.Count) ($modCount -gt 0 -and $realDist.Count -eq $modCount)
    if ($realDist.Count -gt 0) {
        $realDeployed = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($r in $realDist) { [void]$realDeployed.Add($r.Rel) }
        $realLinked = @($realDist | Where-Object { -not $T::MustCopy($_.Rel, $realDeployed) })
        Yes ("and MustCopy links all {0} of them" -f $realDist.Count) ($realLinked.Count -eq $realDist.Count)
        $realOther = @($rows | Where-Object {
            $_.Rel -like 'Data\Platform\*' -and $_.Rel -notlike 'Data\Platform\Distribution\*'
        } | Select-Object -First 20)
        if ($realOther.Count -gt 0) {
            $realOtherCopy = @($realOther | Where-Object { $T::MustCopy($_.Rel, $realDeployed) })
            Yes ("and other Data\Platform rows on this machine stay copied ({0} of {1})" -f $realOtherCopy.Count, $realOther.Count) (
                $realOtherCopy.Count -eq $realOther.Count)
        }
    }
} else {
    Write-Host "SKIP  no files.txt at $FilesList (synthetic 67 still checked)"
}

Done
