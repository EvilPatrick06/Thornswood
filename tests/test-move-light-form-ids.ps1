<#
  test-move-light-form-ids.ps1

      pwsh -NoProfile -File .\tests\test-move-light-form-ids.ps1

  #1715. scripts\oneoff\Move-LightFormIds.ps1 moves the light plugin form ids
  a world stored under one light order to the server's light order, once.
  Measured on 5 Oct: 2 such ids on live and 5 on dev, every one a head part
  in a character's appearance (docs\LIGHT-ORDER-DRIFT.md). Dev's were stored
  on 24 and 25 Sep under a light order that gave HammerHair.esp light index
  0x1C and KhisartinBeards.esp 0x20; the last dev order of 5 Oct gives them
  0x1B and 0x27.

  The records here are made up in the shape the engine writes them
  (MpChangeForm::ToJson in the fork: compact, appearanceDump with raceId,
  headpartIds and headTextureSetId), carrying the ids measured on dev, and
  they are copies in a scratch folder, never a server's own. It holds that:
    - a dry run writes nothing and says each id it would move, by plugin
    - -Write moves exactly those ids, keeps every other byte of the record
      (a name that holds the same digits included), and first keeps the
      record as it was in the backup folder
    - an id already the server's is left as it is, and a second run moves
      nothing and writes no backup
    - a light id outside the appearance, a record the plan has no order for,
      and a plugin the server's order does not have are each said, and that
      record is left as it is
    - a folder under a Thornswood-Server root is refused

  -Repo points it at another checkout, which is how it was shown to fail
  before the script existed. Nothing leaves this machine.
#>
[CmdletBinding()]
param([string]$Repo)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Repo) { $Repo = Split-Path -Parent $Here }
$script = Join-Path $Repo 'scripts\oneoff\Move-LightFormIds.ps1'

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}
$utf8 = New-Object Text.UTF8Encoding($false)
$shell = (Get-Process -Id $PID).Path
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-move-light-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $T | Out-Null
function Put([string]$file, [string]$text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
    [IO.File]::WriteAllText($file, $text, $utf8)
}

# A character's change form, compact, in the engine's key order.
function Record([int]$slot, [long[]]$headparts, [string]$name, [string]$inv = '') {
    $hp = ($headparts | ForEach-Object { [string]$_ }) -join ','
    return '{"recType":1,"formDesc":"ff00000' + $slot + '","baseDesc":"7:Skyrim.esm","position":[3755.699951171875,-495.70001220703125,-207.6999969482422],' +
           '"angle":[0.0,0.0,180.0],"worldOrCellDesc":"19bad4:Skyrim Unbound.esp","inv":{"entries":[' + $inv + ']},"isHarvested":false,"isOpen":false,' +
           '"baseContainerAdded":false,"nextRelootDatetime":0,"isDisabled":false,"profileId":' + (1000 + $slot) + ',"isDeleted":false,"count":1,' +
           '"isRaceMenuOpen":false,"dynamicFields":{},"appearanceDump":{"isFemale":false,"raceId":79686,"weight":0.5,"skinColor":-1,"hairColor":-8355712,' +
           '"headpartIds":[' + $hp + '],"headTextureSetId":0,"options":[0.0,1e-05,-0.25],"presets":[],"tints":[],"name":"' + $name + '"},' +
           '"equipmentDump":{"inv":{"entries":[]},"numChanges":0},"learnedSpells":[],"healthPercentage":1.0}'
}

try {
    Yes 'scripts\oneoff\Move-LightFormIds.ps1 is there' (Test-Path -LiteralPath $script)
    if (-not (Test-Path -LiteralPath $script)) { throw 'no script to run' }

    # The light orders: the one dev's records were stored under, and the
    # server's. Filler names keep every other index where it would be.
    $fill = @(1..64 | ForEach-Object { 'Filler{0:D2}.esp' -f $_ })
    $old = [string[]]$fill[0..39]
    $old[0] = '_ResourcePack.esl'; $old[0x1C] = 'HammerHair.esp'; $old[0x20] = 'KhisartinBeards.esp'; $old[5] = 'Gone Light.esp'
    $new = [string[]]$fill[0..47]
    $new[0] = '_ResourcePack.esl'; $new[0x1B] = 'HammerHair.esp'; $new[0x27] = 'KhisartinBeards.esp'
    $new[0x1C] = $fill[0x1B]; $new[0x20] = $fill[0x27]
    $new[5] = $fill[47]

    $world = Join-Path $T 'copy\world\changeForms'
    $records = [ordered]@{
        # Dev's two characters, as measured: three HammerHair.esp parts at
        # light index 0x1C, two KhisartinBeards.esp parts at 0x20. The
        # second's name holds the digits of its own beard id, which is text.
        '6.json' = (Record 6 @(0x1BB2B, 0x1C0D6, 0x51621, 0x1C0E4, 0x2E46F, 4261530582, 4261530584, 4261530583) 'Six')
        '7.json' = (Record 7 @(0x51621, 0x1C0D6, 0x1BB2B, 0x1C0E4, 0x2E46F, 0x1C0F7, 0x1C107, 4261546023, 4261546040) 'Seven 4261546023')
        # Live's, stored under the order the server keeps.
        'a.json' = (Record 10 @(0x51621, 4261574695) 'Ten')
        # A world object with no light id, which is most of a world. Some
        # hold the largest float there is (3.4028234663852886e+38, a limit
        # that means none), which is no id and is too big for a decimal: the
        # dev world of 5 Oct has one, and the first run stopped on it.
        '1059ac_Skyrim.esm.json' = '{"recType":2,"formDesc":"1059ac:Skyrim.esm","position":[1.0,2.0,3.0],"appearanceDump":null,"dynamicFields":{"limit":3.4028234663852886e+38,"floor":-3.4028234663852886e+38}}'
    }
    foreach ($k in $records.Keys) { Put (Join-Path $world $k) $records[$k] }
    $planPath = Join-Path $T 'plan.json'
    Put $planPath (([ordered]@{ orders = [ordered]@{ dev0925 = $old; live1005 = $new }; records = [ordered]@{
        '6.json' = [ordered]@{ order = 'dev0925'; ids = @(4261530582, 4261530584, 4261530583) }
        '7.json' = [ordered]@{ order = 'dev0925'; ids = @(4261546023, 4261546040) }
        'a.json' = [ordered]@{ order = 'live1005'; ids = @(4261574695) }
        'b.json' = [ordered]@{ order = 'dev0925'; ids = @(4261546023) }
        'c.json' = [ordered]@{ order = 'dev0925'; ids = @(4261435431) } } }) | ConvertTo-Json -Depth 5)
    $toPath = Join-Path $T 'manifest.json'
    Put $toPath (([ordered]@{ versionMajor = 1; mods = @(@{ filename = 'Skyrim.esm'; size = 1; crc32 = 1 }); light = @($new | ForEach-Object { [ordered]@{ filename = $_; size = 1; crc32 = 1 } }) }) | ConvertTo-Json -Depth 5)
    $backup = Join-Path $T 'copy\backup'

    function Run([string]$w, [string[]]$more) {
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try {
            $o = @(& $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script -World $w -Plan $planPath -To $toPath -Backup $backup @more 2>&1 | ForEach-Object { "$_" })
            return [pscustomobject]@{ Code = $LASTEXITCODE; Text = ($o -join "`n") }
        } finally { $ErrorActionPreference = $eap }
    }
    function Same-As-Before { return @($records.Keys | Where-Object { [IO.File]::ReadAllText((Join-Path $world $_)) -cne $records[$_] }) }

    # ---- a dry run --------------------------------------------------------------
    Write-Host 'a dry run'
    $r = Run $world @()
    Write-Host (($r.Text -split "`n" | ForEach-Object { '      ' + $_ }) -join "`n")
    Yes 'it runs and says it writes nothing' ($r.Code -eq 0 -and $r.Text -match 'Dry run, nothing is written')
    Yes '  every record as it was, and no backup folder' ((Same-As-Before).Count -eq 0 -and -not (Test-Path -LiteralPath $backup))
    Yes '  HammerHair.esp stored at 0x1C would move to 0x1B, each of its three parts' (
        $r.Text -match '0xFE01CBD6\s+HammerHair\.esp BD6, moves to 0xFE01BBD6' -and $r.Text -match '0xFE01CBD8\s+HammerHair\.esp BD8, moves to 0xFE01BBD8' -and
        $r.Text -match '0xFE01CBD7\s+HammerHair\.esp BD7, moves to 0xFE01BBD7')
    Yes '  KhisartinBeards.esp stored at 0x20 would move to 0x27' ($r.Text -match '0xFE020827\s+KhisartinBeards\.esp 827, moves to 0xFE027827' -and $r.Text -match '0xFE020838\s+KhisartinBeards\.esp 838, moves to 0xFE027838')
    Yes '  a beard stored under the order the server keeps is already the server''s' ($r.Text -match '0xFE027827\s+KhisartinBeards\.esp 827, already the server''s')
    Yes '  and the count' ($r.Text -match '4 records, 3 with light ids, 6 light ids: 5 would move, 1 already the server''s; 0 record\(s\) left alone')

    # ---- -Write -------------------------------------------------------------------
    Write-Host ''
    Write-Host '-Write'
    $r = Run $world @('-Write')
    Yes 'it runs' ($r.Code -eq 0 -and $r.Text -match '5 moved, 1 already the server''s; 0 record\(s\) left alone, 2 written')
    $want6 = $records['6.json'].Replace('4261530582', '4261526486').Replace('4261530584', '4261526488').Replace('4261530583', '4261526487')
    $want7 = $records['7.json'].Replace('4261546023,4261546040]', '4261574695,4261574712]')
    Yes '  6.json is the same record, byte for byte, with the three HammerHair.esp ids at 0x1B' ([IO.File]::ReadAllText((Join-Path $world '6.json')) -ceq $want6)
    Yes '  7.json the same with the two beard ids at 0x27, and its name still holds the old digits' (
        [IO.File]::ReadAllText((Join-Path $world '7.json')) -ceq $want7 -and $want7.Contains('"name":"Seven 4261546023"'))
    Yes '  a.json and the world object untouched' ([IO.File]::ReadAllText((Join-Path $world 'a.json')) -ceq $records['a.json'] -and
        [IO.File]::ReadAllText((Join-Path $world '1059ac_Skyrim.esm.json')) -ceq $records['1059ac_Skyrim.esm.json'])
    Yes '  and the two records as they were are in the backup, and nothing else' (
        @(Get-ChildItem -LiteralPath $backup -File).Count -eq 2 -and
        [IO.File]::ReadAllText((Join-Path $backup '6.json')) -ceq $records['6.json'] -and [IO.File]::ReadAllText((Join-Path $backup '7.json')) -ceq $records['7.json'])
    $after = @{}
    foreach ($k in $records.Keys) { $after[$k] = [IO.File]::ReadAllText((Join-Path $world $k)) }
    $r2 = Run $world @('-Write')
    Yes 'run again, it moves nothing twice: the moved ids are not the ones the plan lists' (
        $r2.Code -eq 2 -and $r2.Text -match '0xFE027827 is not an id the plan lists for this record: moved already' -and $r2.Text -match ': 0 moved' -and $r2.Text -match ', 0 written')
    Yes '  and every record is as the first run left it, the backup as it was' (
        @($records.Keys | Where-Object { [IO.File]::ReadAllText((Join-Path $world $_)) -cne $after[$_] }).Count -eq 0 -and
        @(Get-ChildItem -LiteralPath $backup -File).Count -eq 2 -and [IO.File]::ReadAllText((Join-Path $backup '7.json')) -ceq $records['7.json'])

    # ---- what it leaves alone ----------------------------------------------------
    Write-Host ''
    Write-Host 'what it leaves alone'
    $odd = Join-Path $T 'odd\world\changeForms'
    # A light id in a pack, which is not where any was found.
    Put (Join-Path $odd 'b.json') (Record 11 @(4261546023) 'Eleven' '{"baseId":4261546040,"count":1}')
    # A record the plan has no order for.
    Put (Join-Path $odd 'd.json') (Record 13 @(4261546023) 'Thirteen')
    # A plugin the server's light order does not have (light index 5 there).
    Put (Join-Path $odd 'c.json') (Record 12 @(4261435431) 'Twelve')
    $oddBefore = @{}
    foreach ($f in Get-ChildItem -LiteralPath $odd -File) { $oddBefore[$f.Name] = [IO.File]::ReadAllText($f.FullName) }
    $r = Run $odd @('-Write')
    Write-Host (($r.Text -split "`n" | ForEach-Object { '      ' + $_ }) -join "`n")
    Yes 'it stops with a code that says so, having written nothing' ($r.Code -eq 2 -and
        @($oddBefore.Keys | Where-Object { [IO.File]::ReadAllText((Join-Path $odd $_)) -cne $oddBefore[$_] }).Count -eq 0)
    Yes '  a light id in the pack is named, and the record left alone' ($r.Text -match 'left alone: a light id at \.inv\.entries\[0\]\.baseId \(0xFE020838\)')
    Yes '  a record with no order in the plan is named' ($r.Text -match 'left alone: no light order for it in the plan')
    Yes '  a plugin the server''s order does not have is named' ($r.Text -match 'left alone: \.appearanceDump\.headpartIds\[0\] 0xFE005827: Gone Light\.esp is not in the server''s light order')

    # ---- never a server's own folder ---------------------------------------------
    Write-Host ''
    $srv = Join-Path $T 'Thornswood-Server-Dev\world\changeForms'
    Put (Join-Path $srv '7.json') $records['7.json']
    $r = Run $srv @()
    Yes 'a folder under a Thornswood-Server root is refused, before anything is read' ($r.Code -ne 0 -and $r.Text -match 'is a server''s own world')
}
catch {
    Yes ('the harness ran to the end without an error: ' + $_.Exception.Message) $false
}
finally {
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}
Done
