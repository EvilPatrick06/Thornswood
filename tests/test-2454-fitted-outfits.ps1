# Issue #2454: the outfits fitted to the covered bodies are built by
# Build-Generated from the collection's BodySlide projects, not shipped as
# meshes built on some other machine. Part one: Immersive Armours' Bosmer
# armour, built from 'Immersive Armours SSE CBBE.osp', with its 18 .tri morphs
# no longer shipped (#1004). No game folder needed; under a second.
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

$bosmer = @('IA CBBE - Bosmer', 'IA CBBE - Bosmer Engraved', 'IA CBBE - Bosmer Reinforced', 'IA CBBE - Bosmer Bracers',
    'IA CBBE - Bosmer Engraved Bracers', 'IA CBBE - Bosmer Gauntlets', 'IA CBBE - Bosmer Full Cape',
    'IA CBBE - Bosmer Shoulder Cape', 'IA CBBE - Bosmer Engraved Shoulder Cape')

# The committed list.
$real = Get-GeneratedBuildList (Join-Path $Repo 'records\generated.json')
Yes 'records\generated.json names the outfit sets apart from the bodies' ($real.Outfits.Count -gt 0)
Yes ('  every Bosmer set of Immersive Armours SSE CBBE.osp ({0})' -f $real.Outfits.Count) (@($bosmer | Where-Object { $real.Outfits -notcontains $_ }).Count -eq 0)
Yes '  and the bodies are unchanged' ($real.Sets.Count -eq 3 -and $real.Sets -contains 'CBBE 3BBB Amazing NeverNude')
Yes '  no outfit slider is moved from its default' (@($real.Outfits | Where-Object { $real.Sliders.ContainsKey($_) }).Count -eq 0)

# Ship-Rules: the 18 built .nif files are ours, the 18 .tri morphs are not.
Yes ('Ship-Rules lists 18 fitted outfit files ({0})' -f @($ShipGeneratedOutfitFiles).Count) (@($ShipGeneratedOutfitFiles).Count -eq 18)
Yes '  each one ships as generated output' (@($ShipGeneratedOutfitFiles | Where-Object { -not (Test-ShipGenerated $_) -or (Test-ShipNotOurs $_) }).Count -eq 0)
Yes '  none is a body' (@($ShipGeneratedOutfitFiles | Where-Object { Test-GeneratedBodyPath $_ }).Count -eq 0)
foreach ($t in 'boots.tri', 'bracersengravedf.tri', 'cape\fullcapef.tri', '1stpersonarmortorso.tri') {
    $rel = 'Data\meshes\armor\bosmerarmormaty743\' + $t
    Yes "  the morph $t no longer ships" ((Test-ShipNotOurs $rel) -and -not $ShipBuiltUntil1259.Contains($rel))
}
Yes '  no Bosmer file is left on the built-until-1259 list' (@($ShipBuiltUntil1259 | Where-Object { $_ -like 'Data\meshes\armor\bosmerarmormaty743\*' }).Count -eq 0)
Yes '  an unbuilt .nif beside them is still not ours' (Test-ShipNotOurs 'Data\meshes\armor\bosmerarmormaty743\boots_0.nif')

# What a set writes, as Build-Generated and Ship-Rules both read it.
$set = [pscustomobject]@{ Name = 'IA CBBE - Bosmer Full Cape'; OutputPath = 'meshes\armor\bosmerarmormaty743\cape'; OutputFile = 'fullcapef'; GenWeights = $true }
$o = Get-BodySlideSetOutputs $set
Yes 'a weighted set writes _0 and _1 under its OutputPath' (($o -join '|') -eq 'Data\meshes\armor\bosmerarmormaty743\cape\fullcapef_0.nif|Data\meshes\armor\bosmerarmormaty743\cape\fullcapef_1.nif')
Yes '  and both are on Ship-Rules'' list' (@($o | Where-Object { @($ShipGeneratedOutfitFiles) -inotcontains $_ }).Count -eq 0)
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

Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail) { exit 1 }
exit 0
