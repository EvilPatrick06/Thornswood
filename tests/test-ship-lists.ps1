<#
  test-ship-lists.ps1

      pwsh -NoProfile -File .\tests\test-ship-lists.ps1
      pwsh -NoProfile -File .\tests\test-ship-lists.ps1 -Before c32b820

  Whether a pack and the installer leave out the same files.

  Ship-Rules.ps1 exists so that they do, and until 24 September they did not.
  Publish-Update.ps1 (packs) and Package-Thornswood.ps1 (the installer) each
  kept their own list of Bethesda's files, and the installer's had grown a
  list of other people's frameworks and tools the packs never had. Measured
  that day over the 30,697 files in C:\Thornswood\Game: packs carried 90 files
  (55.5 MB) the installer left out, 82 under Data\Nemesis_Engine, six under
  BStarData, imgui.ini and steam_appid.txt. The lists are one list in
  Ship-Rules.ps1 now, and this checks that it stays that way.

  WHAT RUNS IS THE SCRIPTS' OWN CODE, lifted out by the PowerShell parser: from
  each script its Test-Vanilla, whatever list it still keeps for itself, its
  other small tests, and the loop that decides what goes in (Publish-Update's
  "Scanning the build", Package-Thornswood's "Listing the build"), fed made up
  files for the fixed paths and the real ones for this machine's folder. From
  Publish-Update also the one line that decides which files a release lists as
  removed. The rest of those scripts builds and uploads releases, so it never
  runs here.

  -Tools <folder> runs it against another copy of the three scripts, flat in
  that folder or under its scripts\release (a repository). Pointed
  at c32b820, main just before the lists became one, it fails 29 of its checks.
  Entry 128 added three client runtime checks that fail there as well, because
  that code called any file at those paths ours. Run on the machine that ships
  on 24 September with those three in, it failed 31: the older checks' count
  moves with this machine's publish baselines, and was 28 that day.

  Three parts.
    1. Both scripts use the one list, and nothing else keeps a copy.
    2. A fixed set of paths, each with what packs and the installer did with it
       before 24 September and what both do now. The rows whose fate changed
       are the files that should never have shipped.
    3. This machine's own game folder, when there is one. Packs and the
       installer must agree on every file in it, and nothing the installer
       leaves out as Bethesda's or somebody else's may be listed as removed
       against this machine's publish baselines. With -Before <commit>, the
       same folder also goes through the scripts as they were at that commit,
       and every file whose fate changed is listed by name.

  Read only. The game folder, the launcher's record and the baselines under
  this machine's working copies of the VPS store (%LOCALAPPDATA%\Thornswood\feed, #907) and legacy LOCALAPPDATA copies are read and never written. -Before writes the old scripts and
  client-build.json into a temp folder of its own and removes it.

  About a minute on the machine that ships, nearly all of it the installer's
  loop going through 30,000 files the way Package-Thornswood does. On a
  runner with no game folder, part 3 says SKIP and the rest takes seconds.
#>
param(
    [string]$Tools,
    [string]$Before,
    [string]$Game = 'C:\Thornswood\Game',
    [string]$ProfileDir = 'C:\Thornswood\Profile'
)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Tools) {
    # The tests are in tests\, the repository is one folder up.
    $Tools = $PSScriptRoot
    if (-not $Tools) { $Tools = Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $Tools = Split-Path -Parent $Tools
}

$pass = 0; $fail = 0
function Yes($what, $cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" -ForegroundColor Green }
    else       { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

# ---- lifting the deciding code out of a script -------------------------------

function Read-Script([string]$path) {
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tok, [ref]$err)
    if ($err.Count) { throw ("{0} does not parse: {1}" -f $path, $err[0].Message) }
    return $ast
}

# The lists a script keeps for itself: an assignment at the top of the script
# to a variable named like the old ones.
function Get-OwnLists($ast) {
    return @($ast.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $_.Left.Extent.Text -match '^\$(vanilla|foreign)'
    })
}

function Get-FunctionText($ast, [string]$name, [string]$script) {
    $defs = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true))
    if ($defs.Count -ne 1) { throw ("{0} defines {1} {2} times, expected once" -f $script, $name, $defs.Count) }
    return $defs[0].Extent.Text
}

# The scan loop: the one foreach whose body asks Test-Vanilla about $rel.
function Get-LoopBody($ast, [string]$script) {
    $loops = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.ForEachStatementAst] -and
        $n.Body.Extent.Text -match 'Test-Vanilla \$rel' }, $true))
    if ($loops.Count -ne 1) { throw ("{0} has {1} loops that ask Test-Vanilla, expected one" -f $script, $loops.Count) }
    return $loops[0].Body.Extent.Text
}

function Quote([string]$s) { return "'" + $s.Replace("'", "''") + "'" }

# One module per script, so the two scripts' old lists (which used the same
# variable names) cannot see each other. Built with PSModuleInfo rather than
# New-Module so nothing is imported into this session.
# A script by name: beside the folder given, as in a copy of the old flat
# tools\ that -Before unpacks, or in scripts\release since phase 8 of #440.
function Find-In([string]$toolsDir, [string]$name) {
    $flat = Join-Path $toolsDir $name
    if (Test-Path -LiteralPath $flat) { return $flat }
    return (Join-Path $toolsDir ('scripts\release\' + $name))
}
function New-Decider([string]$toolsDir, [string]$which) {
    $rules = Find-In $toolsDir 'Ship-Rules.ps1'
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('. ' + (Quote $rules))
    if ($which -eq 'pack') {
        $file = 'Publish-Update.ps1'
        # Publish-Update's scan records each file by its bytes since #441,
        # with Get-BaselineEntry from Release-Baseline.ps1. The paths here are
        # made up and never on disk, and this asks only which of them ship,
        # so the lifted loop gets a stand-in that records a path without
        # opening it.
        [void]$sb.AppendLine('function Get-BaselineEntry([string]$path) { return ''0:fake'' }')
        $ast = Read-Script (Find-In $toolsDir $file)
        $own = Get-OwnLists $ast
        foreach ($a in $own) { [void]$sb.AppendLine($a.Extent.Text) }
        foreach ($fn in 'Test-Vanilla', 'Test-Runtime', 'Test-Machine', 'Test-FromCollection') {
            [void]$sb.AppendLine((Get-FunctionText $ast $fn $file))
        }
        $body = Get-LoopBody $ast $file
        $rm = @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$removed' -and $n.Right.Extent.Text -match 'Test-Machine' }, $true))
        if ($rm.Count -ne 1) { throw ("{0} has {1} removal filters that ask Test-Machine, expected one" -f $file, $rm.Count) }
        # The main channel: $Dev is false, as it is for a live release. $GameDir
        # is the folder $prefix was made from, as it is in Publish-Update, and
        # Ship-Rules hashes the six client runtime files there (entry 128).
        [void]$sb.AppendLine(@'
function Get-Shipped($files, $collection, $prefix, $optional) {
    $vortexFiles = $collection
    $GameDir = $prefix.TrimEnd('\')
    $Dev = $false
    $now = @{}
    $nowFile = @{}
    foreach ($f in $files)
'@ + $body + @'

    return ,([string[]]@($now.Keys))
}
function Select-Removed([string[]]$removed) {
'@ + $rm[0].Extent.Text + @'

    return ,([string[]]@($removed))
}
'@)
        $vanilla = Get-FunctionText $ast 'Test-Vanilla' $file
        $machine = Get-FunctionText $ast 'Test-Machine' $file
    } else {
        $file = 'Package-Thornswood.ps1'
        $ast = Read-Script (Find-In $toolsDir $file)
        $own = Get-OwnLists $ast
        foreach ($a in $own) { [void]$sb.AppendLine($a.Extent.Text) }
        foreach ($fn in 'Test-Vanilla', 'Test-Runtime', 'Test-Optional', 'Test-FromCollection') {
            [void]$sb.AppendLine((Get-FunctionText $ast $fn $file))
        }
        $body = Get-LoopBody $ast $file
        # The loop's $shipClientFiles is Ship-Rules' $ShipClientFiles here, the
        # same record read the same way; PowerShell names ignore case.
        [void]$sb.AppendLine(@'
function Get-Shipped($files, $collection, $prefix, $optional) {
    $vortexFiles = $collection
    $optionalPrefixes = $optional
    $ship = @(); $skipBytes = 0; $shipBytes = 0; $optionalBytes = 0; $optionalCount = 0; $machineCount = 0
    $collectionBytes = 0; $collectionCount = 0
    $clientShipped = 0
    $clientWrong = @()
    foreach ($f in $files)
'@ + $body + @'

    return ,([string[]]@($ship | ForEach-Object { $_.Rel }))
}
'@)
        $vanilla = Get-FunctionText $ast 'Test-Vanilla' $file
        $machine = ''
    }
    $m = [psmoduleinfo]::new([scriptblock]::Create($sb.ToString()))
    return [pscustomobject]@{
        Module   = $m
        File     = $file
        OwnLists = @($own | ForEach-Object { $_.Left.Extent.Text })
        Vanilla  = $vanilla
        Machine  = $machine
    }
}

# Made up files for the fixed paths, carrying the four things the two loops
# read off a file. This machine's game folder is fed its real files instead.
$FakePrefix = 'X:\Game\'
function New-Fakes([string[]]$paths) {
    $list = New-Object 'System.Collections.Generic.List[object]'
    $when = [datetime]::new(2026, 9, 24, 0, 0, 0, [DateTimeKind]::Utc)
    foreach ($p in $paths) {
        $list.Add([pscustomobject]@{
            FullName         = $FakePrefix + $p
            Extension        = [IO.Path]::GetExtension($p)
            Length           = [int64]1
            LastWriteTimeUtc = $when
        })
    }
    return ,$list
}

function Get-Set([string[]]$items) {
    $s = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($i in $items) { [void]$s.Add($i) }
    return ,$s
}

# What one script would carry out of these files, as a set of paths relative
# to the prefix.
function Invoke-Shipped($decider, $files, [string]$prefix, $collection, $optional) {
    return ,(Get-Set (& $decider.Module { param($a, $b, $c, $d) Get-Shipped $a $b $c $d } $files $collection $prefix $optional))
}

# Which of these paths Publish-Update would list as removed.
function Invoke-Removed($decider, [string[]]$paths) {
    # Select-Removed hands back one array. Wrapping it in @() here would nest
    # it, and an empty one would then come back as a single empty name.
    $r = & $decider.Module { param($a) Select-Removed $a } $paths
    if ($null -eq $r) { return ,([string[]]@()) }
    return ,([string[]]$r)
}

function Fate($set, [string]$p) {
    if ($set.Contains($p)) { return 'ship' }
    return 'out'
}

# optional-packs.txt: paths the installer leaves out on purpose and publishes
# as their own download. Read the way Package-Thornswood reads it, only so
# those paths can be kept out of the comparison. Empty on 24 September.
function Get-OptionalPrefixes([string]$toolsDir) {
    $out = @()
    $f = Find-In $toolsDir 'optional-packs.txt'
    if (-not (Test-Path -LiteralPath $f)) { return ,$out }
    foreach ($line in (Get-Content -LiteralPath $f)) {
        $t = $line.Trim()
        if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
        $parts = $t -split '\|'
        if ($parts.Count -lt 3) { continue }
        $prefix = $parts[2].Trim().TrimStart('\')
        if ($prefix.Length -eq 0) { continue }
        if (-not $prefix.EndsWith('\')) { $prefix += '\' }
        $out += [pscustomobject]@{ Id = $parts[0].Trim(); Prefix = $prefix }
    }
    return ,$out
}
function Test-UnderOptional([string]$rel, $optional) {
    foreach ($o in $optional) { if ($rel.StartsWith($o.Prefix, 'OrdinalIgnoreCase')) { return $true } }
    return $false
}

$pack = New-Decider $Tools 'pack'
$inst = New-Decider $Tools 'installer'
$optional = Get-OptionalPrefixes $Tools

# ---- 1. one list ---------------------------------------------------------------
Write-Host ''
Write-Host 'One list' -ForegroundColor Cyan

$hasVanilla = [bool](& $pack.Module { Get-Command Test-ShipVanilla -CommandType Function -ErrorAction SilentlyContinue })
$hasForeign = [bool](& $pack.Module { Get-Command Test-ShipForeignFramework -CommandType Function -ErrorAction SilentlyContinue })
Yes 'Ship-Rules.ps1 has Test-ShipVanilla' $hasVanilla
Yes 'Ship-Rules.ps1 has Test-ShipForeignFramework' $hasForeign
if ($hasVanilla -and $hasForeign) {
    Yes 'Test-ShipVanilla says Data\Skyrim.esm is Bethesda''s' (& $pack.Module { Test-ShipVanilla 'Data\Skyrim.esm' })
    Yes 'Test-ShipForeignFramework says Data\ShaderCache\x.bin is somebody else''s' (& $pack.Module { Test-ShipForeignFramework 'Data\ShaderCache\x.bin' })
    Yes 'and neither claims one of our own overlays' (-not (& $pack.Module {
        (Test-ShipVanilla 'Data\Platform\Plugins\thornswood-front.js') -or (Test-ShipForeignFramework 'Data\Platform\Plugins\thornswood-front.js') }))
}
Yes ('Publish-Update.ps1 keeps no list of its own' + $(if ($pack.OwnLists.Count) { ' (has ' + ($pack.OwnLists -join ', ') + ')' } else { '' })) ($pack.OwnLists.Count -eq 0)
Yes ('Package-Thornswood.ps1 keeps no list of its own' + $(if ($inst.OwnLists.Count) { ' (has ' + ($inst.OwnLists -join ', ') + ')' } else { '' })) ($inst.OwnLists.Count -eq 0)
foreach ($d in $pack, $inst) {
    Yes ($d.File + ' asks Ship-Rules for both lists in its Test-Vanilla') `
        ($d.Vanilla -match 'Test-ShipVanilla' -and $d.Vanilla -match 'Test-ShipForeignFramework')
}
Yes 'Publish-Update.ps1 decides removals through Test-ShipMachine' ($pack.Machine -match 'Test-ShipMachine')

# ---- 2. a fixed set of paths --------------------------------------------------
#
# path, what packs did before 24 September, what the installer did, what both
# do now. The before columns are what the two scripts did at c32b820 (main when
# the lists were made one); -Before c32b820 checks them against that code.
Write-Host ''
Write-Host 'A fixed set of paths' -ForegroundColor Cyan

$rows = @(
    # Bethesda's, out of both before and after.
    @('Data\Skyrim.esm',                                      'out',  'out',  'out'),
    @('Data\_ResourcePack.bsa',                               'out',  'out',  'out'),
    @('Data\Skyrim - Textures0.bsa',                          'out',  'out',  'out'),
    @('Data\ccBGSSSE001-Fish.esm',                            'out',  'out',  'out'),
    @('Data\Strings\Skyrim_English.STRINGS',                  'out',  'out',  'out'),
    @('Data\Video\BGS_Logo.bik',                              'out',  'out',  'out'),
    @('SkyrimSE.exe',                                         'out',  'out',  'out'),
    @('High.ini',                                             'out',  'out',  'out'),
    @('_DowngraderBackups\20260910-140530\bink2w64.dll',      'out',  'out',  'out'),
    @('Skyrim\SkyrimPrefs.ini',                               'out',  'out',  'out'),
    @('src\skse64\skse64\PluginAPI.h',                        'out',  'out',  'out'),
    # A log is out of a pack by its extension and out of the installer by name.
    @('d3dx9_42.log',                                         'out',  'out',  'out'),

    # Only on the installer's list before, so packs carried them. The first six
    # are the kinds measured in C:\Thornswood\Game on 24 September. The rest
    # are every other entry on that list, as a file the collection does not
    # provide. On the machine that ships, every one of those that is there
    # comes from the collection or is a log, which is why only the first kinds
    # rode in packs.
    @('BStarData\state.json',                                 'ship', 'out',  'out'),
    @('BStarData\profiles\b5ef7a061f0d6f8c\_backups\Plugins-backup.txt', 'ship', 'out', 'out'),
    @('Data\Nemesis_Engine\cache\behavior_path',              'ship', 'out',  'out'),
    @('Data\Nemesis_Engine\temp_behaviors\xml\0_master.xml',  'ship', 'out',  'out'),
    @('imgui.ini',                                            'ship', 'out',  'out'),
    @('steam_appid.txt',                                      'ship', 'out',  'out'),
    @('skse64_loader.exe',                                    'ship', 'out',  'out'),
    @('skse64_1_6_1170.dll',                                  'ship', 'out',  'out'),
    @('VERSION',                                              'ship', 'out',  'out'),
    @('Data\FNIS Behavior SE 7.6\GenerateFNIS_for_Users\GenerateFNISforUsers.exe', 'ship', 'out', 'out'),
    @('Data\CalienteTools\BodySlide\BodySlide x64.exe',       'ship', 'out',  'out'),
    @('Data\tools\xEdit\SSEEdit.exe',                         'ship', 'out',  'out'),
    @('Data\Source\Scripts\SKI_ConfigBase.psc',               'ship', 'out',  'out'),
    @('Data\ModderResource\readme.txt',                       'ship', 'out',  'out'),
    @('Data\FOMod\ModuleConfig.xml',                          'ship', 'out',  'out'),
    @('Data\Docs\readme.txt',                                 'ship', 'out',  'out'),
    @('Data\Docs and Screenshots\screenshot.png',             'ship', 'out',  'out'),
    @('Data\readmes\readme.txt',                              'ship', 'out',  'out'),
    @('Data\ShaderCache\x.bin',                               'ship', 'out',  'out'),

    # Another server's, out of both all along.
    @('Data\NirnLabUIPlatform\CEFSubprocess.exe',             'out',  'out',  'out'),
    @('Data\SKSE\Plugins\NirnLabUIPlugin.dll',                'out',  'out',  'out'),
    # One machine's own, and written at runtime.
    @('Data\SKSE\Plugins\SkyrimPlatform.ini',                 'out',  'out',  'out'),
    @('Claude outputs\notes.md',                              'out',  'out',  'out'),
    # The collection's (in the made up record below), out of both.
    @('Data\Nemesis_Engine\Nemesis Unlimited Behavior Engine.exe', 'out', 'out', 'out'),
    @('Data\SkyUI_SE.bsa',                                    'out',  'out',  'out'),

    # Ours, in both before and after.
    @('Data\Platform\Plugins\thornswood-front.js',            'ship', 'ship', 'ship'),
    @('Data\Platform\UI\index.html',                          'ship', 'ship', 'ship'),
    @('Data\Thornswood-Content.esp',                          'ship', 'ship', 'ship'),
    # MpClientPlugin.dll and TESModPlatform.pex were rows here, ship in both.
    # The client runtime is ours only when its bytes are the recorded build
    # now (entry 128), which a made up file cannot be, so they have their own
    # checks below the removal side.
    # Nemesis's output, generated from the collection's own patches (#1178).
    @('Data\meshes\actors\character\behaviors\0_master.hkx', 'ship', 'ship', 'ship'),
    @('Data\Scripts\FNIS.pex',                                'ship', 'ship', 'ship'),
    # The folder names count only straight under Data, and BStarData only at
    # the top: a folder of the same name deeper down is not those rules'. Until
    # #1178 that made these three ours; they are loose files of somebody's
    # mod, and outside Data\Platform only what Ship-Rules names is ours, so
    # they are out of both now, like RaceMenu's loose menu the packs carried.
    @('Data\meshes\tools\anvil.nif',                          'ship', 'ship', 'out'),
    @('Data\textures\Docs\sign.dds',                          'ship', 'ship', 'out'),
    @('Data\BStarData\note.txt',                              'ship', 'ship', 'out'),
    @('Data\Interface\racesex_menu.swf',                      'ship', 'ship', 'out')
)
$fixtureCollection = Get-Set @('Data\Nemesis_Engine\Nemesis Unlimited Behavior Engine.exe', 'Data\SkyUI_SE.bsa')
$paths = [string[]]@($rows | ForEach-Object { $_[0] })

$fakes = New-Fakes $paths
$packNow = Invoke-Shipped $pack $fakes $FakePrefix $fixtureCollection @()
$instNow = Invoke-Shipped $inst $fakes $FakePrefix $fixtureCollection @()

foreach ($r in $rows) {
    $p = $r[0]; $want = $r[3]
    $gotPack = Fate $packNow $p
    $gotInst = Fate $instNow $p
    Yes ("{0,-4} both  {1}" -f $want, $p) ($gotPack -eq $want -and $gotInst -eq $want)
    if ($gotPack -ne $want -or $gotInst -ne $want) {
        Write-Host ("      pack says {0}, installer says {1}" -f $gotPack, $gotInst) -ForegroundColor Red
    }
}
# Other people's loose files left the installer too (#1178), and nothing else
# changed for it.
$notOursRows = @('Data\meshes\tools\anvil.nif', 'Data\textures\Docs\sign.dds', 'Data\BStarData\note.txt', 'Data\Interface\racesex_menu.swf')
Yes 'the installer does with every row what it did before, other people''s loose files apart' (@($rows | Where-Object { $_[2] -ne $_[3] -and $notOursRows -notcontains $_[0] }).Count -eq 0)
Yes '  and those went from the installer to nowhere' (@($rows | Where-Object { $notOursRows -contains $_[0] -and ($_[2] -ne 'ship' -or $_[3] -ne 'out') }).Count -eq 0)
$changed = @($rows | Where-Object { $_[1] -ne $_[3] })
Yes 'every row whose fate changed went from a pack to nowhere, none the other way' (@($changed | Where-Object { $_[1] -ne 'ship' -or $_[3] -ne 'out' }).Count -eq 0)
Write-Host ("      {0} rows packs carried and no longer do" -f $changed.Count) -ForegroundColor DarkGray

# The removal side. Every row packs used to carry is in the baseline of the
# machine that ships, so each one now looks gone from the build. None of them
# may be listed as removed: that would delete it from every tester.
$gone = [string[]]@($changed | ForEach-Object { $_[0] })
$removedNow = Invoke-Removed $pack $gone
Yes 'none of the rows packs stopped carrying is listed as removed' ($removedNow.Count -eq 0)
foreach ($r in $removedNow) { Write-Host ("      would be deleted from every tester: {0}" -f $r) -ForegroundColor Red }
# And the filter still lets a real removal through, so the check above is not
# passing because nothing is ever removed.
$real = Invoke-Removed $pack ([string[]]@('Data\Platform\Plugins\thornswood-retired.js', ':profile:plugins.txt'))
Yes 'a file of ours that left the build is still listed as removed' ($real -contains 'Data\Platform\Plugins\thornswood-retired.js')
Yes 'and the plugin list is still not' ($real -notcontains ':profile:plugins.txt')

# The client runtime. A made up file at a recorded path is not the recorded
# build, so neither a pack nor the installer carries it, and no release lists
# it as removed. This machine's real files are in part 3, and
# test-client-by-hash.ps1 feeds the recorded bytes and one byte changed.
$clientPaths = [string[]]@('Data\SKSE\Plugins\MpClientPlugin.dll', 'Data\Scripts\TESModPlatform.pex')
$clientFakes = New-Fakes $clientPaths
$packClient = Invoke-Shipped $pack $clientFakes $FakePrefix $fixtureCollection @()
$instClient = Invoke-Shipped $inst $clientFakes $FakePrefix $fixtureCollection @()
foreach ($p in $clientPaths) {
    Yes ("out  both  {0}, made up, so not the recorded build" -f $p) ((Fate $packClient $p) -eq 'out' -and (Fate $instClient $p) -eq 'out')
}
Yes 'and neither is listed as removed' ((Invoke-Removed $pack $clientPaths).Count -eq 0)

# ---- the scripts as they were, when asked for ---------------------------------
$old = $null
$oldDir = $null
if ($Before) {
    $repo = (& git -C $Tools rev-parse --show-toplevel 2>$null)
    $have = $false
    if ($LASTEXITCODE -eq 0 -and $repo) {
        & git -C $repo cat-file -e ($Before + '^{commit}') 2>$null
        $have = ($LASTEXITCODE -eq 0)
    }
    if (-not $have) {
        Write-Host ("SKIP  {0} is not in this clone, so the scripts as they were cannot be read" -f $Before) -ForegroundColor Yellow
    } else {
        $oldDir = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-ship-lists-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        $null = New-Item -ItemType Directory -Force -Path $oldDir
        $zip = Join-Path $oldDir 'before.zip'
        & git -C $repo archive --format=zip -o $zip $Before scripts/release/Ship-Rules.ps1 scripts/release/Publish-Update.ps1 scripts/release/Package-Thornswood.ps1 records/client-build.json
        if ($LASTEXITCODE -ne 0) { throw "git archive of $Before failed" }
        Expand-Archive -LiteralPath $zip -DestinationPath $oldDir
        $old = [pscustomobject]@{
            Pack = New-Decider $oldDir 'pack'
            Inst = New-Decider $oldDir 'installer'
        }
        Write-Host ''
        Write-Host ("The fixed paths against {0}" -f $Before) -ForegroundColor Cyan
        $packThen = Invoke-Shipped $old.Pack $fakes $FakePrefix $fixtureCollection @()
        $instThen = Invoke-Shipped $old.Inst $fakes $FakePrefix $fixtureCollection @()
        $bad = @($rows | Where-Object { (Fate $packThen $_[0]) -ne $_[1] -or (Fate $instThen $_[0]) -ne $_[2] })
        Yes ("every row's before columns are what {0} did" -f $Before) ($bad.Count -eq 0)
        foreach ($b in $bad) {
            Write-Host ("      {0}: pack did {1}, installer did {2}" -f $b[0], (Fate $packThen $b[0]), (Fate $instThen $b[0])) -ForegroundColor Red
        }
    }
}

# ---- 3. this machine's game folder -------------------------------------------
Write-Host ''
Write-Host 'This machine''s game folder' -ForegroundColor Cyan

function Show-Groups([string[]]$items, [string]$colour) {
    $items | Group-Object {
        $p = $_ -split '\\'
        if ($p.Count -ge 3) { $p[0] + '\' + $p[1] + '\' } elseif ($p.Count -eq 2) { $p[0] + '\' } else { '(game folder root)' }
    } | Sort-Object Name | ForEach-Object { Write-Host ("      {0,5}  {1}" -f $_.Count, $_.Name) -ForegroundColor $colour }
}

$record = Join-Path $ProfileDir 'OwnGame\files.txt'
if (-not (Test-Path -LiteralPath (Join-Path $Game 'SkyrimSE.exe')) -or -not (Test-Path -LiteralPath $record)) {
    Write-Host ("SKIP  no game folder at {0} with a launcher record beside it; nothing on this machine to measure" -f $Game) -ForegroundColor Yellow
} else {
    $collection = & $pack.Module { param($p) Get-ShipOwnGameCollection $p } $ProfileDir
    $prefix = $Game.TrimEnd('\') + '\'
    # Listed the way both scripts list it.
    $files = @(Get-ChildItem -LiteralPath $Game -Recurse -File -Force)
    Write-Host ("      {0:n0} files in {1}, {2:n0} of them the collection's" -f $files.Count, $Game, $collection.Count) -ForegroundColor DarkGray

    $packLive = Invoke-Shipped $pack $files $prefix $collection $optional
    $instLive = Invoke-Shipped $inst $files $prefix $collection $optional
    $packOnly = [string[]]@($packLive | Where-Object { -not $instLive.Contains($_) -and -not (Test-UnderOptional $_ $optional) } | Sort-Object)
    $instOnly = [string[]]@($instLive | Where-Object { -not $packLive.Contains($_) } | Sort-Object)
    Write-Host ("      a pack would carry {0:n0}, the installer {1:n0}" -f $packLive.Count, $instLive.Count) -ForegroundColor DarkGray
    Yes 'nothing a pack carries is left out of the installer' ($packOnly.Count -eq 0)
    if ($packOnly.Count) { Show-Groups $packOnly 'Red' }
    Yes 'nothing the installer carries is left out of a pack' ($instOnly.Count -eq 0)
    if ($instOnly.Count) { Show-Groups $instOnly 'Red' }

    # Every file in a publish baseline that the installer leaves out as
    # Bethesda's or somebody else's goes through Publish-Update's own removal
    # filter. Anything that comes out the other side would be deleted from
    # every tester by the next release.
    $instVanilla = $inst.Module
    $repoRoot = $Tools
    $relSibling = Split-Path -Parent $repoRoot
    $baselinePaths = @(
        @{ Name = 'main store';    Path = (Join-Path $env:LOCALAPPDATA 'Thornswood\feed\main\published.json') },
        @{ Name = 'dev store';     Path = (Join-Path $env:LOCALAPPDATA 'Thornswood\feed\dev\published.json') },
        @{ Name = 'legacy main';   Path = (Join-Path $env:LOCALAPPDATA 'Thornswood\published.json') },
        @{ Name = 'legacy dev';    Path = (Join-Path $env:LOCALAPPDATA 'Thornswood\published-dev.json') }
    )
    $seen = @{}
    foreach ($cand in $baselinePaths) {
        if (-not (Test-Path -LiteralPath $cand.Path)) {
            Write-Host ("SKIP  no {0} baseline at {1}" -f $cand.Name, $cand.Path) -ForegroundColor Yellow
            continue
        }
        $fp = (Get-FileHash -LiteralPath $cand.Path -Algorithm SHA256).Hash
        if ($seen.ContainsKey($fp)) {
            Write-Host ("SKIP  {0} is the same bytes as {1}" -f $cand.Name, $seen[$fp]) -ForegroundColor DarkGray
            continue
        }
        $seen[$fp] = $cand.Name
        $keys = [string[]]@(((Get-Content -LiteralPath $cand.Path -Raw) -replace '^\uFEFF', '' | ConvertFrom-Json).PSObject.Properties.Name)
        $theirs = [string[]]@(& $instVanilla { param($k) $k | Where-Object { $_ -notlike ':*' -and (Test-Vanilla $_) } } $keys)
        $wouldGo = Invoke-Removed $pack $theirs
        Write-Host ("      {0}: {1:n0} paths, {2} of them Bethesda's or somebody else's" -f $cand.Name, $keys.Count, $theirs.Count) -ForegroundColor DarkGray
        Yes ("none of those would be deleted from testers by the next release ({0})" -f $cand.Name) ($wouldGo.Count -eq 0)
        if ($wouldGo.Count) { Show-Groups $wouldGo 'Red' }
    }

    if ($old) {
        Write-Host ''
        Write-Host ("This machine's game folder against {0}" -f $Before) -ForegroundColor Cyan
        $packThen = Invoke-Shipped $old.Pack $files $prefix $collection $optional
        $instThen = Invoke-Shipped $old.Inst $files $prefix $collection $optional
        $stopped = [string[]]@($packThen | Where-Object { -not $packLive.Contains($_) } | Sort-Object)
        $started = [string[]]@($packLive | Where-Object { -not $packThen.Contains($_) } | Sort-Object)
        $instLost = [string[]]@($instThen | Where-Object { -not $instLive.Contains($_) } | Sort-Object)
        $instGained = [string[]]@($instLive | Where-Object { -not $instThen.Contains($_) } | Sort-Object)
        Write-Host ("      packs: {0:n0} before, {1:n0} now. Installer: {2:n0} before, {3:n0} now" -f $packThen.Count, $packLive.Count, $instThen.Count, $instLive.Count) -ForegroundColor DarkGray
        Yes 'the installer carries exactly what it did' ($instLost.Count -eq 0 -and $instGained.Count -eq 0)
        Yes 'packs carry nothing they did not' ($started.Count -eq 0)
        if ($started.Count) { Show-Groups $started 'Red' }
        Yes 'and what packs stopped carrying is what the installer always left out' (@($stopped | Where-Object { $instThen.Contains($_) }).Count -eq 0)
        $bytes = [int64]0
        foreach ($s in $stopped) { $bytes += (Get-Item -LiteralPath (Join-Path $Game $s) -Force).Length }
        Write-Host ("      packs stopped carrying {0} files, {1:n1} MB:" -f $stopped.Count, ($bytes / 1MB)) -ForegroundColor DarkGray
        Show-Groups $stopped 'DarkGray'
        foreach ($s in $stopped) { Write-Host ("        {0}" -f $s) -ForegroundColor DarkGray }
    }
}

if ($oldDir) { Remove-Item -LiteralPath $oldDir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail) { exit 1 }
exit 0
