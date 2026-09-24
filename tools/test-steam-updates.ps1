<#
  test-steam-updates.ps1

      pwsh -NoProfile -File .\tools\test-steam-updates.ps1

  Steam's Updates setting for Skyrim, which nothing in the launcher read or
  set until 24 September (entry 271 on the To Do List, "Nothing stops Steam
  putting Skyrim back on the wrong build").

  WHY IT MATTERS. The downgrade puts the 1.6.1170 files in place, and Steam
  still believes the game is on the newest build. With its setting on
  "Always keep this game updated" the next Skyrim update Steam takes undoes
  the downgrade by itself. The only protection was a log line asking people
  not to start Skyrim through Steam. The setting is "AutoUpdateBehavior" in
  steamapps\appmanifest_489830.acf; 1 is "Only update this game when I launch
  it", which is what Steam's own Properties, Updates menu writes.

  MEASURED 24 SEPTEMBER on Patrick's machine, read only: that file is 1156
  bytes of Valve's KeyValues text, tabs and LF, "AutoUpdateBehavior" "0", and
  it carries the ReadOnly attribute, the only one of twenty manifests there
  that does. Steam was running.

  WHAT THIS HOLDS THE LAUNCHER TO. A broken manifest is worse than an unwanted
  update, so only the value's bytes may change, anything not shaped the way
  Steam writes it is left alone, a read-only file stays read-only, nothing is
  written while Steam runs, and nothing is written at all unless a person
  pressed Yes on a question that says what Yes does. Reading it to warn is
  fine; Play is never held on it.

  It compiles the shipped tools\app\SteamUpdates.cs with the same .NET
  Framework csc that Build-Launcher.ps1 uses, which is C# 5, and drives the
  real class. Where this machine has Steam and Skyrim, it also parses the
  real manifest, without writing to it.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$AppPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $AppPath) { $AppPath = Join-Path $Here 'app' }

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

# ---- compile the shipped class ---------------------------------------------
$src = Join-Path $AppPath 'SteamUpdates.cs'
Yes 'tools\app\SteamUpdates.cs is there' (Test-Path -LiteralPath $src)
if (-not (Test-Path -LiteralPath $src)) { Done }

$csc = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Yes 'the .NET Framework csc the launcher builds with is on this machine' ([bool]$csc)
if (-not $csc) { Done }

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-steam-updates-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $work
$dll = Join-Path $work 'SteamUpdates.dll'
$said = & $csc /nologo /target:library "/out:$dll" $src 2>&1
$built = ($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $dll)
Yes 'it compiles on its own with the C# 5 compiler' $built
if (-not $built) { $said | ForEach-Object { Write-Host "      $_" }; Done }

$asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
$T = $asm.GetType('Thornswood.SteamUpdates', $true)
$flags = [Reflection.BindingFlags]'Static, Public, NonPublic'
function Method([string]$name, [Type[]]$sig) {
    $m = $T.GetMethod($name, $flags, $null, $sig, $null)
    if (-not $m) { throw "SteamUpdates.$name is missing" }
    return $m
}
$mValue    = Method 'Value' @([string])
$mHeld     = Method 'Held' @([string])
$mManifest = Method 'ManifestFor' @([string])
$mRead     = Method 'Read' @([string])
$mReport   = Method 'Report' @([string])
$mNeeds    = Method 'NeedsHolding' @([string])
$mHold     = Method 'Hold' @([string], [bool])
function Value([string]$s)  { return $mValue.Invoke($null, [object[]]@($s)) }
function Held([string]$s)   { return $mHeld.Invoke($null, [object[]]@($s)) }
function ManifestFor([string]$s) { return $mManifest.Invoke($null, [object[]]@($s)) }
function ReadValue([string]$s) { return $mRead.Invoke($null, [object[]]@($s)) }
function Report([string]$s) { return $mReport.Invoke($null, [object[]]@($s)) }
function Needs([string]$s)  { return [bool]$mNeeds.Invoke($null, [object[]]@($s)) }
function Hold([string]$m, [bool]$running) { return $mHold.Invoke($null, [object[]]@($m, $running)) }

$Latin = [Text.Encoding]::GetEncoding(28591)

# ---- a manifest shaped the way Steam writes one ------------------------------
#
# Line for line the shape of the real file, less the owner's account id.
# <T> is a tab and <AUTO> is where Steam puts AutoUpdateBehavior.
$Template = @'
"AppState"
{
<T>"appid"<T><T>"489830"
<T>"universe"<T><T>"1"
<T>"LauncherPath"<T><T>"C:\\Program Files (x86)\\Steam\\steam.exe"
<T>"name"<T><T>"The Elder Scrolls V: Skyrim Special Edition"
<T>"StateFlags"<T><T>"4"
<T>"installdir"<T><T>"Skyrim Special Edition"
<T>"lastupdated"<T><T>"1789059989"
<T>"SizeOnDisk"<T><T>"16092533099"
<T>"buildid"<T><T>"24914197"
<T>"TargetBuildID"<T><T>"24914197"
<AUTO>
<T>"AllowOtherDownloadsWhileRunning"<T><T>"0"
<T>"ScheduledAutoUpdate"<T><T>"0"
<T>"InstalledDepots"
<T>{
<T><T>"489831"
<T><T>{
<T><T><T>"manifest"<T><T>"4940892828028256588"
<T><T><T>"size"<T><T>"7490529657"
<T><T>}
<T>}
<T>"UserConfig"
<T>{
<T><T>"language"<T><T>"english"
<T>}
<T>"MountedConfig"
<T>{
<T><T>"language"<T><T>"english"
<T>}
}
'@

function Acf([string]$auto = 'absent', [string]$nl = "`n", [string]$extra = '') {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in (($Template -replace "`r", '') -split "`n")) {
        if ($l -eq '') { continue }
        if ($l -eq '<AUTO>') {
            if ($auto -ne 'absent') { $lines.Add('<T>"AutoUpdateBehavior"<T><T>"' + $auto + '"') }
            if ($extra) { $lines.Add($extra) }
            continue
        }
        $lines.Add($l)
    }
    return (($lines -join $nl) + $nl).Replace('<T>', "`t")
}

# Positions at which two strings of the same length differ, or -1.
function Differ([string]$a, [string]$b) {
    if ($a.Length -ne $b.Length) { return -1 }
    $n = 0
    for ($i = 0; $i -lt $a.Length; $i++) { if ([int]$a[$i] -ne [int]$b[$i]) { $n++ } }
    return $n
}
function Same([byte[]]$a, [byte[]]$b) {
    if ($a.Length -ne $b.Length) { return $false }
    for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
    return $true
}
$Line1 = "`t`"AutoUpdateBehavior`"`t`t`"1`""

try {
    # ---- reading ------------------------------------------------------------
    Yes 'the value is read: 0' ((Value (Acf '0')) -ceq '0')
    Yes 'the value is read: 1' ((Value (Acf '1')) -ceq '1')
    Yes 'no key reads as empty, which Steam takes as its default' ((Value (Acf)) -ceq '')
    Yes 'the key is matched without regard to case, as Valve reads it' ((Value ((Acf '2').Replace('AutoUpdateBehavior', 'autoupdatebehavior'))) -ceq '2')

    # ---- changing the value, and only the value ------------------------------
    $a0 = Acf '0'
    $h0 = Held $a0
    Yes '0 becomes 1' ((Value $h0) -ceq '1')
    Yes 'and exactly one character of the file changed' ((Differ $a0 $h0) -eq 1)
    Yes 'and it is the value' ($h0 -ceq $a0.Replace('"AutoUpdateBehavior"' + "`t`t" + '"0"', '"AutoUpdateBehavior"' + "`t`t" + '"1"'))
    $a2 = Acf '2'
    Yes 'High Priority (2) becomes 1 too' (((Held $a2) -ceq $a2.Replace("`t`t`"2`"`n`t`"AllowOther", "`t`t`"1`"`n`t`"AllowOther")) -and ((Differ $a2 (Held $a2)) -eq 1))
    $a1 = Acf '1'
    Yes 'already 1 comes back unchanged' ((Held $a1) -ceq $a1)

    $crlf = Acf '0' "`r`n"
    $hcrlf = Held $crlf
    Yes 'a CRLF file keeps its line endings' (((Differ $crlf $hcrlf) -eq 1) -and ((Value $hcrlf) -ceq '1'))

    # ---- no key at all ---------------------------------------------------------
    $none = Acf
    $hnone = Held $none
    $close = $none.LastIndexOf('}')
    $want = $none.Substring(0, $close) + $Line1 + "`n" + $none.Substring($close)
    Yes 'a missing key goes in on its own line above the closing brace, tab separated like the rest' ($hnone -ceq $want)
    Yes 'and reads back as 1' ((Value $hnone) -ceq '1')
    $nonecr = Acf 'absent' "`r`n"
    $closecr = $nonecr.LastIndexOf('}')
    Yes 'in a CRLF file it ends in CRLF' ((Held $nonecr) -ceq ($nonecr.Substring(0, $closecr) + $Line1 + "`r`n" + $nonecr.Substring($closecr)))

    # A key of the same name inside a block is not the setting.
    $nested = $none.Replace("`t`t`"language`"`t`t`"english`"`n`t}`n`t`"MountedConfig`"", "`t`t`"language`"`t`t`"english`"`n`t`t`"AutoUpdateBehavior`"`t`t`"0`"`n`t}`n`t`"MountedConfig`"")
    Yes 'the fixture has a nested key to ignore' ($nested -cne $none)
    Yes 'a nested key of the same name does not count as the setting' ((Value $nested) -ceq '')
    $hnested = Held $nested
    Yes 'and is left as it is while the top level one goes in' (($hnested.Contains("`t`t`"AutoUpdateBehavior`"`t`t`"0`"")) -and ((Value $hnested) -ceq '1'))

    # ---- escapes, byte order marks, other bytes --------------------------------
    $esc = (Acf '0').Replace('"The Elder Scrolls V: Skyrim Special Edition"', '"A \"quoted\" name ending in a backslash \\"')
    Yes 'escaped quotes and backslashes inside a value parse' ((Value $esc) -ceq '0')
    Yes 'and survive the change untouched' ((Differ $esc (Held $esc)) -eq 1)
    $bom = ([char]0xEF).ToString() + ([char]0xBB) + ([char]0xBF) + (Acf '0')
    Yes 'a UTF-8 byte order mark is stepped over' ((Value $bom) -ceq '0')
    Yes 'and kept' ((Held $bom).StartsWith($bom.Substring(0, 3), [StringComparison]::Ordinal))

    # ---- what is refused -------------------------------------------------------
    Yes 'an empty file is not a manifest' ($null -eq (Value ''))
    Yes 'and is not written into' ($null -eq (Held ''))
    Yes 'JSON is not a manifest' ($null -eq (Held '{"AppState": {"AutoUpdateBehavior": 0}}'))
    $cut = $a0.Substring(0, $a0.LastIndexOf('}'))
    Yes 'a file cut off before its closing brace is refused' ($null -eq (Held $cut))
    Yes 'anything after the closing brace is refused' ($null -eq (Held ($a0 + '"more"' + "`n")))
    Yes 'an unquoted word is refused rather than guessed at' ($null -eq (Held ((Acf 'absent' "`n" "`tAutoUpdateBehavior`t`t1"))))
    Yes 'a key with nothing after it is refused' ($null -eq (Held ((Acf 'absent' "`n" "`t`"AutoUpdateBehavior`""))))
    Yes 'an unterminated quote is refused' ($null -eq (Held ($a0.Replace('"buildid"', '"buildid'))))
    Yes 'another root than AppState is refused' ($null -eq (Held ($a0.Replace('"AppState"', '"UserLocalConfigStore"'))))
    $oneLine = '"AppState" { "appid" "489830" }'
    Yes 'a closing brace that is not on its own line is not written next to' ($null -eq (Held $oneLine))

    # ---- which file ------------------------------------------------------------
    Yes 'the manifest sits two folders up from the game, in that library' ((ManifestFor 'D:\SteamLibrary\steamapps\common\Skyrim Special Edition') -ceq 'D:\SteamLibrary\steamapps\appmanifest_489830.acf')
    Yes 'with or without a trailing backslash' ((ManifestFor 'D:\SteamLibrary\steamapps\common\Skyrim Special Edition\') -ceq 'D:\SteamLibrary\steamapps\appmanifest_489830.acf')
    Yes 'a folder that is not in a Steam library has no manifest' ((ManifestFor 'C:\Thornswood\Game') -ceq '')
    Yes 'nor does no folder' ((ManifestFor '') -ceq '')

    # ---- the file itself --------------------------------------------------------
    $lib = Join-Path $work 'Library'
    $game = Join-Path $lib 'steamapps\common\Skyrim Special Edition'
    $null = New-Item -ItemType Directory -Force -Path $game
    $m = Join-Path $lib 'steamapps\appmanifest_489830.acf'
    $tmp = Join-Path $lib 'steamapps\thornswood-489830.tmp'
    Yes 'the test library resolves to its own manifest' ((ManifestFor $game) -ceq $m)

    function Put([string]$text) {
        if (Test-Path -LiteralPath $m) { [IO.File]::SetAttributes($m, [IO.FileAttributes]::Normal) }
        [IO.File]::WriteAllBytes($m, $Latin.GetBytes($text))
    }

    Yes 'no file, nothing to report' ($null -eq (Report $game))
    Yes 'no file, nothing to ask' (-not (Needs $m))
    $r = Hold $m $false
    Yes 'no file: says so and makes none' (($r -like '*was not found*') -and -not (Test-Path -LiteralPath $m))

    Put (Acf '0')
    Yes 'the start line names Steam''s own words for 0' ((Report $game) -like '*"Always keep this game updated"*')
    Yes 'and says how to change it in Steam' ((Report $game) -like '*Properties, Updates*')
    Yes 'the question is asked on 0' (Needs $m)

    $was = [IO.File]::ReadAllBytes($m)
    $r = Hold $m $true
    Yes 'Steam running: nothing is written' (Same $was ([IO.File]::ReadAllBytes($m)))
    Yes 'and it says why' ($r -like '*Steam is still running*')
    Yes 'and leaves no temporary file' (-not (Test-Path -LiteralPath $tmp))

    $r = Hold $m $false
    $now = [IO.File]::ReadAllBytes($m)
    Yes 'Steam closed: the file now says 1' ((ReadValue $m) -ceq '1')
    Yes 'one byte changed and no other' (($was.Length -eq $now.Length) -and ((Differ $Latin.GetString($was) $Latin.GetString($now)) -eq 1))
    Yes 'no temporary file is left beside it' (-not (Test-Path -LiteralPath $tmp))
    Yes 'and the log line says what changed and where' (($r -like '*is now "Only update this game when I launch it"*') -and ($r -like ('*' + $m + '*')))
    Yes 'the start line then reads it back as held' ((Report $game) -like '*"Only update this game when I launch it"*')
    Yes 'and the question is not asked again' (-not (Needs $m))

    [IO.File]::SetLastWriteTimeUtc($m, [DateTime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc))
    $r = Hold $m $false
    Yes 'already 1: the file is not touched' ([IO.File]::GetLastWriteTimeUtc($m) -eq [DateTime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc))
    Yes 'and it says so' ($r -like '*already*')

    # Read-only, as it is on Patrick's machine.
    Put (Acf '0')
    [IO.File]::SetAttributes($m, [IO.FileAttributes]::ReadOnly -bor [IO.FileAttributes]::Archive)
    $r = Hold $m $false
    Yes 'a read-only file is changed' ((ReadValue $m) -ceq '1')
    Yes 'and is read-only again afterwards' (([IO.File]::GetAttributes($m) -band [IO.FileAttributes]::ReadOnly) -ne 0)
    Yes 'and the log line says so' ($r -like '*read-only again*')

    # Bytes that are not ASCII, a byte order mark, and CRLF, all kept.
    $name = 'C:\\Users\\Zo' + [char]0x00EB + '\\Steam\\steam.exe'
    $utf = [Text.Encoding]::UTF8.GetBytes((Acf 'absent' "`r`n").Replace('C:\\Program Files (x86)\\Steam\\steam.exe', $name))
    $bytes = New-Object byte[] ($utf.Length + 3)
    $bytes[0] = 0xEF; $bytes[1] = 0xBB; $bytes[2] = 0xBF
    [Array]::Copy($utf, 0, $bytes, 3, $utf.Length)
    [IO.File]::SetAttributes($m, [IO.FileAttributes]::Normal)
    [IO.File]::WriteAllBytes($m, $bytes)
    $r = Hold $m $false
    $after = [IO.File]::ReadAllBytes($m)
    $insert = [Text.Encoding]::ASCII.GetBytes($Line1 + "`r`n")
    $at = $bytes.Length - 3   # before the final "}\r\n"
    $expect = New-Object byte[] ($bytes.Length + $insert.Length)
    [Array]::Copy($bytes, 0, $expect, 0, $at)
    [Array]::Copy($insert, 0, $expect, $at, $insert.Length)
    [Array]::Copy($bytes, $at, $expect, $at + $insert.Length, 3)
    Yes 'UTF-8, a byte order mark and CRLF come back byte for byte, with one line added' (Same $expect $after)

    # Something that is not a manifest is never written.
    Put '{"AppState": {"AutoUpdateBehavior": 0}}'
    $was = [IO.File]::ReadAllBytes($m)
    $r = Hold $m $false
    Yes 'a file not shaped like Steam''s is left alone' (Same $was ([IO.File]::ReadAllBytes($m)))
    Yes 'and it says so, with the way to do it in Steam' (($r -like '*left it alone*') -and ($r -like '*Properties, Updates*'))
    Yes 'and no question is asked about it' (-not (Needs $m))
    Yes 'and no start line is made up about it' ($null -eq (Report $game))

    # What the question checks before it writes, against this machine's own list.
    $mRunning = Method 'SteamRunning' @()
    $steamUp = @(Get-Process -Name steam -ErrorAction SilentlyContinue).Count -gt 0
    Yes ('Steam is seen as ' + $(if ($steamUp) { 'running' } else { 'closed' }) + ', as the process list has it') ([bool]$mRunning.Invoke($null, @()) -eq $steamUp)

    # ---- how the launcher reaches it ---------------------------------------------
    #
    # By text, because these are WPF and cannot be driven from here. What they
    # pin: the file is only ever written from the question, the question only
    # comes after a downgrade that worked, and nothing about it touches Play.
    $shell = Get-Content -LiteralPath (Join-Path $AppPath 'Shell.cs') -Raw
    $askPath = Join-Path $AppPath 'ShellSteamUpdates.cs'
    $askSrc = if (Test-Path -LiteralPath $askPath) { Get-Content -LiteralPath $askPath -Raw } else { '' }

    function Body([string]$text, [string]$head) {
        $at = $text.IndexOf($head)
        if ($at -lt 0) { return '' }
        $b = $text.IndexOf('{', $at)
        $depth = 0
        for ($i = $b; $i -lt $text.Length; $i++) {
            if ($text[$i] -eq '{') { $depth++ }
            elseif ($text[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($at, $i - $at + 1) } }
        }
        return ''
    }

    $writers = @(Get-ChildItem -LiteralPath $AppPath -Filter *.cs -File | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'SteamUpdates\.Hold\(' })
    Yes 'exactly one launcher file writes the setting, and it is the question' (($writers.Count -eq 1) -and ($writers[0].Name -eq 'ShellSteamUpdates.cs'))
    $ask = Body $askSrc 'static void AskToHoldSteamUpdates()'
    $yesAt = $ask.IndexOf('MessageBoxResult.Yes')
    $runAt = $ask.IndexOf('SteamUpdates.SteamRunning()')
    $holdAt = $ask.IndexOf('SteamUpdates.Hold(')
    Yes 'the write comes after the person pressed Yes' (($yesAt -ge 0) -and ($holdAt -gt $yesAt))
    Yes 'and after Steam is seen to be closed' (($runAt -ge 0) -and ($holdAt -gt $runAt))
    Yes 'the question says what Yes changes' ($ask -like '*Yes changes Steam''s Updates setting for Skyrim*')
    Yes 'and No leaves it' ($ask -like '*No leaves it as it is*')
    $down = Body $shell 'static void RunDowngrade()'
    Yes 'the question comes only after a downgrade that worked' ($down -match 'if \(ok\) AskToHoldSteamUpdates\(\);')
    Yes 'the start line is read on the way in' (([regex]::Matches($shell, 'SteamUpdates\.Report\(')).Count -eq 1)
    $draw = Body $shell 'static bool DrawStatus()'
    Yes 'the Play button does not look at it' (($draw.Length -gt 0) -and ($draw -notmatch 'SteamUpdates'))
    $checks = Join-Path $AppPath 'Checks.cs'
    Yes 'nor do the checks that gate Play' ((Get-Content -LiteralPath $checks -Raw) -notmatch 'SteamUpdates')

    # ---- this machine's own manifest, read only ------------------------------------
    $libs = New-Object System.Collections.Generic.List[string]
    try {
        $sp = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath
        if ($sp) {
            $sp = $sp.Replace('/', '\')
            $libs.Add($sp)
            $vdf = Join-Path $sp 'config\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                foreach ($l in (Get-Content -LiteralPath $vdf)) {
                    if ($l -match '^\s*"path"\s+"(.*)"\s*$') { $libs.Add($Matches[1].Replace('\\', '\')) }
                }
            }
        }
    } catch { }
    $real = ''
    foreach ($l in $libs) {
        $g = Join-Path $l 'steamapps\common\Skyrim Special Edition'
        $c = ManifestFor $g
        if ($c -and (Test-Path -LiteralPath $c)) { $real = $c; break }
    }
    if (-not $real) {
        Write-Host 'SKIP  no Steam copy of Skyrim on this machine, so the real manifest is not read'
    } else {
        $text = $Latin.GetString([IO.File]::ReadAllBytes($real))
        $v = Value $text
        Yes ('this machine''s manifest parses, AutoUpdateBehavior is "' + $v + '"') ($null -ne $v)
        $h = Held $text
        $ok = $false
        if ($v -ceq '1') { $ok = ($h -ceq $text) }
        elseif ($v -ceq '') { $ok = ($h.Length -eq $text.Length + $Line1.Length + 1) -or ($h.Length -eq $text.Length + $Line1.Length + 2) }
        elseif ($v.Length -eq 1) { $ok = ((Differ $text $h) -eq 1) }
        else { $ok = ((Value $h) -ceq '1') }
        Yes 'and changing it would touch that value and nothing else (worked out in memory, not written)' $ok
    }
}
finally {
    try {
        Get-ChildItem -LiteralPath $work -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.Attributes = 'Normal' } catch { } }
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    } catch { }
}

Done
