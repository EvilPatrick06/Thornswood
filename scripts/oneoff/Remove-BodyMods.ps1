<#
  Remove-BodyMods.ps1

  Pulls the male and female genitalia mods out of the Thornswood game folder.

  C:\SkyrimTogether\Game\Data is NOT Vortex-managed (no vortex.deployment.json
  lives there, only inert __folder_managed_by_vortex markers left over from the
  copy out of the Steam install), so moving files here desyncs nothing.

  Nothing is deleted. Everything lands in Data\_removedBody\ with its original
  relative path, so Restore-BodyMods.ps1 can put it all back.

  Male side (The New Gentleman) is complete after this runs.
  Female side (CBBE 3BA) needs one BodySlide build afterwards, because 3BA bakes
  the geometry into femalebody_*.nif itself. This script removes the 3BA slider
  sets so BodySlide can only offer the plain CBBE body.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # Was C:\SkyrimTogether until 23 September. This one DELETES, so a default
    # pointing at a folder that does not exist made it a no-op that looked like
    # a clean run, and on any machine that did have that folder it would have
    # deleted out of the wrong one.
    [string]$Data = 'C:\Thornswood\Game\Data',
    [switch]$IncludePubeOverlays   # also disable MorphSync pubic-hair providers
)

$quarantine = Join-Path $Data '_removedBody'

$targets = @(
    # ---- male: The New Gentleman -------------------------------------------
    'TheNewGentleman.esp'
    'SKSE\Plugins\TheNewGentleman.dll'
    'SKSE\Plugins\TheNewGentleman5.ini'
    'meshes\actors\character\character assets\TNG'
    'CalienteTools\BodySlide\SliderSets\TNG.osp'
    'CalienteTools\BodySlide\ShapeData\TNG'
    'CalienteTools\BodySlide\SliderPresets\TNG.xml'
    '70 SOS Physics - CBPC nonFloppy'

    # ---- female: CBBE 3BA / 3BBB -------------------------------------------
    'CalienteTools\BodySlide\SliderSets\CBBE 3BA 1st person.osp'
    'CalienteTools\BodySlide\SliderSets\SE 3BBB Amazing.osp'
    'CalienteTools\BodySlide\ShapeData\CBBE 3BA Reference'
    'CalienteTools\BodySlide\ShapeData\CBBE 3BA UniBody Ref'
    'CalienteTools\BodySlide\ShapeData\SE 3BBB Amazing'
    '90 Old RaceMenuMorphs - 3BBB'

    # genital-detail normal map; plain CBBE has nothing for it to shade
    'textures\actors\character\female\femalebody_1_msn.dds'
)

# left alone on purpose:
#   SKSE\Plugins\hdtSkinnedMeshConfigs  - shared with Nirn Necessities SMP Accessories
#   99 Only CBPC                        - generic CBPC config, unrelated
#   CBBE.esp / RaceMenuMorphsCBBE.esp   - base body + morphs, needed by every armor refit
#   meshes\...\femalebody_*.nif / .tri  - overwritten by the BodySlide build, not moved

$moved = 0; $bytes = 0; $absent = @()
foreach ($t in $targets) {
    $src = Join-Path $Data $t
    if (-not (Test-Path -LiteralPath $src)) { $absent += $t; continue }

    $size = if ((Get-Item -LiteralPath $src).PSIsContainer) {
        (Get-ChildItem -LiteralPath $src -Recurse -File | Measure-Object Length -Sum).Sum
    } else { (Get-Item -LiteralPath $src).Length }

    $dst = Join-Path $quarantine $t
    $dstDir = Split-Path $dst -Parent
    if ($PSCmdlet.ShouldProcess($t, 'move to _removedBody')) {
        if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        Move-Item -LiteralPath $src -Destination $dst -Force
        $moved++; $bytes += [int64]$size
        Write-Host "  moved  $t" -ForegroundColor DarkGray
    }
}

# MorphSync provider flags: rename rather than move, that's how the plugin reads them
$prov = Join-Path $Data 'SKSE\Plugins\MorphSyncTogether\Providers'
$flags = @('TNG.enabled')
if ($IncludePubeOverlays) {
    $flags += 'HIMBOBodyhair.enabled','MorePubesSlaveTats.enabled','NaturalPubicHairstyles.enabled',
              'NaturalPubicHairstylesUBE.enabled','NordicWarmaiden.enabled','OPubes.enabled',
              'PubesForeverFemale.enabled','PubesForeverMale.enabled'
}
foreach ($f in $flags) {
    $p = Join-Path $prov $f
    if (Test-Path -LiteralPath $p) {
        if ($PSCmdlet.ShouldProcess($f, 'disable provider')) {
            Rename-Item -LiteralPath $p -NewName ($f -replace '\.enabled$', '.disabled') -Force
            Write-Host "  disabled provider  $f" -ForegroundColor DarkGray
        }
    }
}

Write-Host ''
Write-Host ("moved {0} items, {1:N1} MB -> {2}" -f $moved, ($bytes/1MB), $quarantine) -ForegroundColor Cyan
if ($absent) { Write-Host ("already gone: {0}" -f ($absent -join ', ')) -ForegroundColor DarkGray }

# ---- report what still needs the BodySlide pass -----------------------------
$fb = Join-Path $Data 'meshes\actors\character\character assets\femalebody_0.nif'
if (Test-Path -LiteralPath $fb) {
    $kb = [math]::Round((Get-Item -LiteralPath $fb).Length / 1KB)
    Write-Host ''
    if ($kb -gt 1200) {
        Write-Host "femalebody_0.nif is $kb KB -> still the 3BA body." -ForegroundColor Yellow
        Write-Host "Run BodySlide and build 'CBBE Body Physics' with the Thornswood preset." -ForegroundColor Yellow
        Write-Host "  $Data\CalienteTools\BodySlide\BodySlide x64.exe" -ForegroundColor Yellow
    } else {
        Write-Host "femalebody_0.nif is $kb KB -> plain CBBE, female side done." -ForegroundColor Green
    }
}
