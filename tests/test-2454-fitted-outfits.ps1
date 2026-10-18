# Issue #2454: the outfits fitted to the covered bodies are built by
# Build-Generated from the collection's BodySlide projects, not shipped as
# meshes built on some other machine. Nothing is built from Immersive Armors
# (Patrick, 17 Oct: used as-is through the collection, nothing built from it is
# redistributed), and its 18 .tri morphs no longer ship. The travel clothes and
# the executioner come with the collection revision. No game folder needed;
# under a second.
$env:THORNSWOOD_HARNESS = '1'
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $Repo 'scripts\release\Ship-Rules.ps1')
. (Join-Path $Repo 'scripts\mods\Generated.ps1')
$pass = 0; $fail = 0
function Yes([string]$what, [bool]$ok) { if ($ok) { $script:pass++; Write-Host "PASS $what" } else { $script:fail++; Write-Host "FAIL $what" } }
function Refuses([string]$what, [scriptblock]$do, [string]$like = '*') {
    $msg = $null
    try { & $do | Out-Null } catch { $msg = $_.Exception.Message }
    Yes $what ($null -ne $msg -and $msg -like $like)
    if ($msg -and $msg -notlike $like) { Write-Host "      said: $msg" }
}

# Patrick, 17 Oct (relayed by Smeagle): Immersive Armors is used as-is through
# the collection and nothing built from it is redistributed. No Immersive
# Armors set is built, and nothing in its Bosmer armour folder is ours.
$folder = 'Data\meshes\armor\bosmerarmormaty743\'
$real = Get-GeneratedBuildList (Join-Path $Repo 'records\generated.json')
Yes 'records\generated.json builds no Immersive Armors set' (@($real.Outfits | Where-Object { $_ -like 'IA *' -or $_ -like '*Bosmer*' }).Count -eq 0)
Yes '  and no outfit yet: the travel clothes and the executioner wait for the collection revision' ($real.Outfits.Count -eq 0)
Yes '  and the bodies are unchanged' ($real.Sets.Count -eq 3 -and $real.Sets -contains 'CBBE 3BBB Amazing NeverNude')
Yes '  no slider is moved for an outfit' (@($real.Outfits | Where-Object { $real.Sliders.ContainsKey($_) }).Count -eq 0)

Yes 'Ship-Rules names no fitted outfit file yet' (@($ShipGeneratedOutfitFiles).Count -eq 0)
Yes '  and no generated pattern reaches the Bosmer armour folder' (@($ShipGeneratedPatterns | Where-Object { $_ -like ($folder + '*') }).Count -eq 0)
foreach ($n in 'torsof_0.nif', 'cape\fullcapef_1.nif', 'boots.tri', 'bracersengravedf.tri', 'cape\fullcapef.tri', '1stpersonarmortorso.tri', 'wildhunt\hunttorso.tri') {
    Yes "  $n does not ship" ((Test-ShipNotOurs ($folder + $n)) -and -not (Test-ShipOurs ($folder + $n)))
}
Yes '  no Bosmer file is left on the built-until-1259 list' (@($ShipBuiltUntil1259 | Where-Object { $_ -like ($folder + '*') }).Count -eq 0)
Yes '  and the folder is held in permission-held.txt on that ruling' ((Test-ShipPermissionHeld ($folder + 'torso.tri')) -and @($ShipPermissionHeld | Where-Object { $_.Path -ieq $folder -and $_.Reason -match 'as-is through the collection' }).Count -eq 1)

# What a set writes, as Build-Generated and Ship-Rules both read it.
$set = [pscustomobject]@{ Name = 'Common Clothes 1'; OutputPath = 'meshes\armor\travel clothes\clothes'; OutputFile = '1clothesf'; GenWeights = $true }
$o = Get-BodySlideSetOutputs $set
Yes 'a weighted set writes _0 and _1 under its OutputPath' (($o -join '|') -eq 'Data\meshes\armor\travel clothes\clothes\1clothesf_0.nif|Data\meshes\armor\travel clothes\clothes\1clothesf_1.nif')
$one = [pscustomobject]@{ Name = 'x'; OutputPath = 'meshes\x'; OutputFile = 'y'; GenWeights = $false }
Yes 'an unweighted set writes one file' (((Get-BodySlideSetOutputs $one) -join '|') -eq 'Data\meshes\x\y.nif')
Refuses 'a set writing outside meshes is refused' { Get-BodySlideSetOutputs ([pscustomobject]@{ Name = 'x'; OutputPath = 'textures\x'; OutputFile = 'y'; GenWeights = $true }) } '*outside meshes*'
Refuses 'a set climbing out with .. is refused' { Get-BodySlideSetOutputs ([pscustomobject]@{ Name = 'x'; OutputPath = 'meshes\..\..\x'; OutputFile = 'y'; GenWeights = $true }) } '*outside meshes*'
Refuses 'a set with no output is refused' { Get-BodySlideSetOutputs ([pscustomobject]@{ Name = 'x'; OutputPath = ''; OutputFile = ''; GenWeights = $true }) } '*names no output*'
Yes 'a body path is told from an outfit' ((Test-GeneratedBodyPath 'Data\meshes\actors\character\character assets\femalebody_1.nif') -and -not (Test-GeneratedBodyPath $o[0]))

# The build list refuses what it cannot build safely.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-2454-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
function ListOf([string]$json) { $p = Join-Path $tmp ([guid]::NewGuid().ToString('N') + '.json'); [IO.File]::WriteAllText($p, $json); Get-GeneratedBuildList $p }
try {
    $ok = ListOf '{"bodyslide":{"sets":[],"outfits":["A"],"sliders":{"A":{"Waist":{"big":10}}}}}'
    Yes 'outfits alone are something to build, and their sliders may move' ($ok.Outfits.Count -eq 1 -and $ok.Sliders.ContainsKey('A'))
    Refuses 'a set named as body and outfit is refused' { ListOf '{"bodyslide":{"sets":["A"],"outfits":["A"]}}' } '*one or the other*'
    Refuses 'an outfit named twice is refused' { ListOf '{"bodyslide":{"sets":[],"outfits":["A","A"]}}' } '*more than once*'
    Refuses 'an empty outfit name is refused' { ListOf '{"bodyslide":{"sets":[],"outfits":[" "]}}' } '*outfit*'
    Refuses 'outfits that are not a list are refused' { ListOf '{"bodyslide":{"sets":[],"outfits":"A"}}' } '*bodyslide.outfits*'
    Refuses 'sliders of a set it does not build are refused' { ListOf '{"bodyslide":{"sets":[],"outfits":["A"],"sliders":{"B":{}}}}' } '*not one of the sets*'

    # The body rules (#1004, #405) apply to an outfit set as to a body.
    $osp = Join-Path $tmp 'SliderSets'
    New-Item -ItemType Directory -Path $osp | Out-Null
    [IO.File]::WriteAllText((Join-Path $osp 'o.osp'), '<SliderSetInfo><SliderSet name="Outfit"><OutputPath>meshes\o</OutputPath><OutputFile GenWeights="true">o</OutputFile><Shape>Top</Shape><Slider name="Breasts" big="0" small="0"/><Slider name="Waist" big="0" small="0"/></SliderSet></SliderSetInfo>')
    $s = Get-BodySlideSet $osp 'Outfit'
    Yes 'an outfit at its defaults keeps to the body rules' ((Test-BodySlideRules $s (Get-BodySlideValues $s $null) $null).Count -eq 0)
    $mv = @{ Breasts = @{ big = 50 } }
    Yes '  and one that shapes the breasts is refused (#1004)' ((Test-BodySlideRules $s (Get-BodySlideValues $s $mv) $mv).Count -gt 0)
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

# Build-Generated wires the outfits in: built after the bodies, checked for
# bodies they must not write, and for exactly the files their sets name.
$bg = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\mods\Build-Generated.ps1'))
Yes 'Build-Generated builds the outfit sets from the list' ($bg.Contains('$list.Outfits'))
Yes '  refuses an outfit that writes a body' ($bg.Contains('Test-GeneratedBodyPath $_') -and $bg.Contains('writes a body'))
Yes '  refuses a missing or stray outfit file' ($bg.Contains('did not build every outfit file') -and $bg.Contains('built files no set names'))
Yes '  and still refuses any .tri morph' ($bg.Contains("Extension -ieq '.tri'"))

# Each outfit group's permissions are recorded in the provenance register,
# read off the mod pages (#2454): who made it, the licence, the credit.
$prov = Get-Content -LiteralPath (Join-Path $Repo 'records\asset-provenance.json') -Raw | ConvertFrom-Json
$rows = @($prov.notInRepo)
function RowOf([string]$like) { @($rows | Where-Object { $_.path -like $like }) }
Yes 'the register no longer counts 140 built meshes as one row' ((RowOf 'The 140 outfit meshes*').Count -eq 0)
$tc = @(RowOf 'The 120 travel clothes meshes*')
Yes '  the 120 travel clothes have a row naming Nexus 83980 and 21305' ($tc.Count -eq 1 -and $tc[0].source -like '*83980*' -and $tc[0].source -like '*21305*' -and $tc[0].issue -eq 2454)
$ex = @(RowOf 'The 2 executioner meshes*')
Yes '  the executioner has a row with MCE''s licence (Nexus 44666, CC BY-NC-SA 4.0) and its credit' ($ex.Count -eq 1 -and $ex[0].source -like '*44666*' -and $ex[0].licence -like '*Attribution-NonCommercial-ShareAlike 4.0*' -and $ex[0].attribution -like '*Parapets*')
Yes '  and no row for a Bosmer build, since none is made or handed on' ((RowOf 'The 18 Bosmer*').Count -eq 0)
$counted = 0; foreach ($r in @($tc) + @($ex)) { if ($r.path -match '^The (\d+) ') { $counted += [int]$Matches[1] } }
Yes ('  the rows for built-until-1259 count its {0} lines' -f $ShipBuiltUntil1259.Count) ($counted -eq $ShipBuiltUntil1259.Count)

Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail) { exit 1 }
exit 0
