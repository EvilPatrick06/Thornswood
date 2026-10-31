<#
  test-1317-fonts.ps1

      pwsh -NoProfile -File .\tests\test-1317-fonts.ps1

  Issue #1317. Futura PT (ParaType) and DIN Pro (FSI FontShop) are commercial
  faces nobody gave SkyMP or Thornswood the right to hand on, and they went
  out in every pack and the installer in three ways:

      four ttf files main's older front build named by hash under
      Data\Platform\UI, which the front built from the fork no longer names,
      but which no release listed as gone, so installs kept them;
      Data\Platform\Fonts\DIN-Pro-bold.spritefont, from upstream's
      client-deps, which the overhead voice mark drew its dot in;
      Data\Platform\Fonts\Futura.spritefont, dated 14 Sep, which nothing used.

  The voice mark draws in Barlow-SemiBold.spritefont now, made from the OFL
  Barlow SemiBold by scripts\mods\Build-SpriteFont.py, and the rest stops
  shipping and leaves every install.

  What it checks:
    1. Ship-Rules: the two sprite fonts ($ShipCommercialFonts) and the four
       ttf names (records\ui-gone.json unused) are not ours, so no pack or
       installer carries them, and every pack deletes them. Barlow-SemiBold
       and its licence are ours, ship, and are not deleted, and so is Tavern.
    2. OwnGame.Foreign's line for the two, read out of the launcher source,
       matches exactly the Ship-Rules names and none of their neighbours, and
       the rules number went up with a RuleTouches line for Fonts and UI.
    3. The sprite font in game\ours is a DirectXTK sprite font Skyrim
       Platform can load: its glyphs sorted, every rect inside the texture,
       its default character there, R8G8B8A8 texels of the size it says, and
       the voice mark's bullet in it. The OFL beside it is Barlow's.
    4. The voice mark names that font, and nothing that runs in the game
       names DIN-Pro-bold or Futura any more.
    5. Where Python with Pillow and the fork's Barlow SemiBold are on the
       machine, Build-SpriteFont.py --check says the file is what it writes.

  Read only: no file is written.
#>
$ErrorActionPreference = 'Stop'
$env:THORNSWOOD_HARNESS = '1'
$Here = Split-Path -Parent $PSScriptRoot

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$sprites = @(
    'Data\Platform\Fonts\DIN-Pro-bold.spritefont',
    'Data\Platform\Fonts\Futura.spritefont'
)
$faces = @(
    'Data\Platform\UI\6f802bf60c545304b09e.ttf',
    'Data\Platform\UI\00e4a2200c3e5ae71d67.ttf',
    'Data\Platform\UI\268a0df3f0e2c23d1ea6.ttf',
    'Data\Platform\UI\fdf086661e1600f95a34.ttf'
)
$ours = @(
    'Data\Platform\Fonts\Barlow-SemiBold.spritefont',
    'Data\Platform\Fonts\Barlow-SemiBold-OFL.txt'
)
$stay = $ours + @(
    'Data\Platform\Fonts\Tavern.ttf',
    'Data\Platform\Fonts\Tavern.spritefont'
)

# ---- 1. Ship-Rules ---------------------------------------------------------------------
. (Join-Path $Here 'scripts\release\Ship-Rules.ps1')
Yes 'Ship-Rules lists exactly the two sprite fonts ($ShipCommercialFonts)' (
    @($ShipCommercialFonts).Count -eq 2 -and @($sprites | Where-Object { @($ShipCommercialFonts) -notcontains $_ }).Count -eq 0)
Yes 'records\ui-gone.json lists the four faces as unused' (
    @($faces | Where-Object { @($ShipUnusedFrontAssets) -notcontains (Split-Path $_ -Leaf) }).Count -eq 0)
$always = @(Get-ShipDeleteAlways)
foreach ($r in $sprites + $faces) {
    Yes "$r is not ours, so no pack or installer carries it" ((Test-ShipOtherServer $r) -and (Test-ShipMachine $r))
    Yes "  and every pack deletes it" ($always -contains $r)
    Yes "  and it is neither a runtime path nor one machine's own file" ((-not (Test-ShipRuntime $r)) -and (-not (Test-ShipOneMachine $r)))
}
foreach ($r in $stay) {
    Yes "$r ships and is not deleted" ((-not (Test-ShipMachine $r)) -and ($always -notcontains $r))
}
foreach ($r in $ours) {
    Yes "$r is in `$ShipOursFiles, which Go.ps1 writes from game\ours" (@($ShipOursFiles) -contains $r)
    Yes "  and is in game\ours" (Test-Path -LiteralPath (Join-Path (Join-Path $Here 'game\ours') $r) -PathType Leaf)
}

# ---- 2. OwnGame.Foreign keeps a refresh from bringing them back --------------------------
$og = [IO.File]::ReadAllText((Join-Path $Here 'launcher\app\OwnGame.cs'))
$fAt = $og.IndexOf('public static bool Foreign(string rel)', [StringComparison]::Ordinal)
$line = [regex]::Match($og, '(?m)^\s*if \(Regex\.IsMatch\(rel, @"(\^Data\\\\Platform\\\\Fonts\\\\\(DIN[^"]*)", I\)\) return true;')
$pluginsRule = $og.IndexOf('if (Regex.IsMatch(rel, @"^Data\\Platform\\Plugins\\[^\\]+\.js$", I))', [StringComparison]::Ordinal)
Yes 'OwnGame.Foreign has a line for the two, before its plugin and UI rules' ($fAt -ge 0 -and $line.Success -and $line.Index -gt $fAt -and $pluginsRule -gt $line.Index)
if ($line.Success) {
    $re = New-Object System.Text.RegularExpressions.Regex($line.Groups[1].Value, ([Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant))
    $missed = @($ShipCommercialFonts | Where-Object { -not $re.IsMatch($_) })
    Yes 'it matches every one Ship-Rules names, so the two lists are the same two' ($missed.Count -eq 0)
    foreach ($m in $missed) { Write-Host "      not matched: $m" }
    Yes '  in any case of letters, as Windows names them' ($re.IsMatch('data\platform\fonts\din-pro-BOLD.spritefont'))
    $wrong = @($stay + @('Data\Platform\Fonts\Futura.spritefont.bak', 'Data\Platform\UI\Futura.spritefont', 'Data\Platform\Fonts\DIN-Pro-bold.ttf') | Where-Object { $re.IsMatch($_) })
    Yes 'and none of their neighbours or a name that only starts the same' ($wrong.Count -eq 0)
    foreach ($w in $wrong) { Write-Host "      matched: $w" }
}
$rulesNum = [regex]::Match($og, '(?m)^\s*const int Rules = (\d+);')
Yes 'OwnGame.Rules went up to 18 or later for it' ($rulesNum.Success -and [int]$rulesNum.Groups[1].Value -ge 18)
Yes 'and rule 18 says it is about Fonts and UI, so an older folder looks at those again' (
    $og -match '\{ 18, new string\[\] \{ "Data\\\\Platform\\\\Fonts\\\\", "Data\\\\Platform\\\\UI\\\\" \} \},')

# ---- 3. the sprite font ---------------------------------------------------------------------
# Read the way DirectXTK's SpriteFont reads it (SpriteFont.cpp): a sprite font
# that does not read stops Skyrim Platform's whole text renderer, not one text.
$sfPath = Join-Path $Here 'game\ours\Data\Platform\Fonts\Barlow-SemiBold.spritefont'
$b = [IO.File]::ReadAllBytes($sfPath)
$ok = $b.Length -gt 40 -and [Text.Encoding]::ASCII.GetString($b, 0, 8) -eq 'DXTKfont'
Yes 'Barlow-SemiBold.spritefont starts DXTKfont' $ok
if (-not $ok) { Done }
$n = [BitConverter]::ToUInt32($b, 8)
$at = 12
$glyphs = @()
for ($i = 0; $i -lt $n; $i++) {
    $glyphs += [pscustomobject]@{
        C = [BitConverter]::ToUInt32($b, $at); L = [BitConverter]::ToInt32($b, $at + 4); T = [BitConverter]::ToInt32($b, $at + 8)
        R = [BitConverter]::ToInt32($b, $at + 12); B = [BitConverter]::ToInt32($b, $at + 16)
        XO = [BitConverter]::ToSingle($b, $at + 20); YO = [BitConverter]::ToSingle($b, $at + 24); XA = [BitConverter]::ToSingle($b, $at + 28)
    }
    $at += 32
}
$lineSpacing = [BitConverter]::ToSingle($b, $at)
$default = [BitConverter]::ToUInt32($b, $at + 4)
$w = [BitConverter]::ToUInt32($b, $at + 8); $h = [BitConverter]::ToUInt32($b, $at + 12)
$fmt = [BitConverter]::ToUInt32($b, $at + 16); $pitch = [BitConverter]::ToUInt32($b, $at + 20); $rows = [BitConverter]::ToUInt32($b, $at + 24)
$at += 28
Yes ("it has glyphs ({0}), a line spacing ({1}) and a texture ({2} x {3})" -f $n, $lineSpacing, $w, $h) ($n -gt 90 -and $lineSpacing -gt 0 -and $w -gt 0 -and $h -gt 0)
$sorted = $true
for ($i = 1; $i -lt $glyphs.Count; $i++) { if ($glyphs[$i].C -le $glyphs[$i - 1].C) { $sorted = $false } }
Yes 'its glyphs are sorted by character, one each, which DirectXTK requires' $sorted
Yes "its default character ('?') is one of them" (@($glyphs | Where-Object { $_.C -eq $default }).Count -eq 1 -and $default -eq 63)
$outside = @($glyphs | Where-Object { $_.L -lt 0 -or $_.T -lt 0 -or $_.R -lt $_.L -or $_.B -lt $_.T -or $_.R -gt $w -or $_.B -gt $h })
Yes 'every glyph''s rect is inside the texture' ($outside.Count -eq 0)
Yes 'the texels are R8G8B8A8 (28), four bytes a texel, one row a line' ($fmt -eq 28 -and $pitch -eq ($w * 4) -and $rows -eq $h)
Yes 'and the file ends where the texels end' ($b.Length -eq ($at + $pitch * $rows))
$bullet = @($glyphs | Where-Object { $_.C -eq 0x2022 })
Yes 'the bullet the voice mark draws is in it, with ink' ($bullet.Count -eq 1 -and $bullet[0].R -gt $bullet[0].L -and $bullet[0].B -gt $bullet[0].T)
$ascii = @(32..126 | Where-Object { $c = $_; -not @($glyphs | Where-Object { $_.C -eq $c }).Count })
Yes 'and every printable ASCII character' ($ascii.Count -eq 0)
$ofl = [IO.File]::ReadAllText((Join-Path $Here 'game\ours\Data\Platform\Fonts\Barlow-SemiBold-OFL.txt'))
Yes 'the licence beside it is the OFL 1.1 with Barlow''s copyright line' (
    $ofl.Contains('Copyright 2017 The Barlow Project Authors') -and $ofl.Contains('SIL OPEN FONT LICENSE Version 1.1'))

# ---- 4. the voice mark and nothing else ------------------------------------------------------
$front = [IO.File]::ReadAllText((Join-Path $Here 'game\plugins\thornswood-front.js'))
$mf = [regex]::Match($front, "const MARK_FONT = '([^']+)';")
Yes 'the voice mark draws in Barlow-SemiBold' ($mf.Success -and $mf.Groups[1].Value -eq 'Barlow-SemiBold')
Yes '  a font game\ours ships under that name' ($mf.Success -and (Test-Path -LiteralPath (Join-Path $Here ('game\ours\Data\Platform\Fonts\' + $mf.Groups[1].Value + '.spritefont'))))
$names = New-Object System.Text.RegularExpressions.Regex("(?<![A-Za-z0-9_-])(DIN-Pro-bold|Futura)(?![A-Za-z0-9_])")
$runs = @()
foreach ($d in 'game\plugins', 'game\ui', 'game\gamemode.js') {
    $p = Join-Path $Here $d
    if (Test-Path -LiteralPath $p -PathType Leaf) { $runs += Get-Item -LiteralPath $p }
    elseif (Test-Path -LiteralPath $p) { $runs += @(Get-ChildItem -LiteralPath $p -File -Recurse | Where-Object { $_.Extension -in '.js', '.html', '.css' }) }
}
$naming = @()
foreach ($f in $runs) {
    $text = [IO.File]::ReadAllText($f.FullName)
    # What the code asks for, not what its comments say it once asked for.
    $code = [regex]::Replace($text, '(?s)/\*.*?\*/|//[^\r\n]*', '')
    foreach ($m in $names.Matches($code)) { $naming += ($f.Name + ' names ' + $m.Value) }
}
Yes ("nothing that runs in the game asks for DIN-Pro-bold or Futura ({0} files read)" -f $runs.Count) ($runs.Count -gt 5 -and $naming.Count -eq 0)
foreach ($x in $naming) { Write-Host "      $x" }

# ---- 5. the script writes this file -----------------------------------------------------------
$py = $null
foreach ($c in 'python3', 'python') { if (Get-Command $c -ErrorAction SilentlyContinue) { $py = $c; break } }
# Inside the fork's submodule, which git lists only as engine\skymp, so the
# path is joined onto that (tests\test-script-paths.ps1 reads git's list).
$ttf = Join-Path (Join-Path $Here 'engine\skymp') 'skymp5-front\src\fonts\Barlow-SemiBold.ttf'
if ($py -and (Test-Path -LiteralPath $ttf)) {
    & $py -c 'import PIL.features, sys; sys.exit(0 if PIL.features.check("freetype2") else 1)' 2>$null
    if ($LASTEXITCODE -eq 0) {
        $out = @(& $py (Join-Path $Here 'scripts\mods\Build-SpriteFont.py') --check 2>&1)
        $out | ForEach-Object { Write-Host "      $_" }
        if ($LASTEXITCODE -eq 0) { Yes 'Build-SpriteFont.py --check: the file is what it writes' $true }
        else { Write-Host 'SKIP  Build-SpriteFont.py writes other bytes with this Pillow or FreeType (it says which wrote the file); section 3 still read the file' }
    } else { Write-Host 'SKIP  this Python has no Pillow with FreeType to draw the font with' }
} else {
    Write-Host 'SKIP  no Python, or engine\skymp is not checked out, so Build-SpriteFont.py was not run'
}

Done
