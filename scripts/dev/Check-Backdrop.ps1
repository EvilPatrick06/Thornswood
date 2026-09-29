<#
  Check-Backdrop.ps1

  Read only. Says what the main menu backdrop is in a game folder: the two
  logo meshes (their hashes and how many shapes each carries, which decides
  whether a second plate draws) and the wallpaper texture (size, mip levels,
  format), against what the repo carries in game\menu. Nothing is changed.

    .\scripts\dev\Check-Backdrop.ps1                          C:\Thornswood\Game
    .\scripts\dev\Check-Backdrop.ps1 -Game C:\Thornswood-DevBuild\Game

  Why it exists: entry 83 on the To Do List. Both logo meshes were the same
  replacer plate, so the menu drew the backdrop twice, and the texture was a
  single mip built from the old 1536 wide art. Somebody looking at a soft,
  doubled menu can run this and read which half is still wrong.
#>
[CmdletBinding()]
param(
    [string]$Game = 'C:\Thornswood\Game'
)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoMenu = Join-Path $Here '..\..\game\menu'

function Md5([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm MD5).Hash.Substring(0, 8).ToLowerInvariant() }
# How many blocks in a Skyrim SE nif are shapes (anything the engine draws:
# BSTriShape, NiTriShape, NiTriStrips and their kin). -1 when it is not a nif
# this can read. Issue #425: logo01ae.nif is an empty node, 0 shapes.
function Shapes([string]$p) {
    $b = [IO.File]::ReadAllBytes($p)
    $o = [Array]::IndexOf($b, [byte]10) + 1
    if ($o -le 0 -or $b.Length -lt $o + 21) { return -1 }
    if ([BitConverter]::ToUInt32($b, $o) -ne 0x14020007) { return -1 }
    $blocks = [BitConverter]::ToUInt32($b, $o + 9)
    $o += 17
    for ($i = 0; $i -lt 3; $i++) { $o += 1 + $b[$o] }
    $ntypes = [BitConverter]::ToUInt16($b, $o); $o += 2
    $types = @()
    for ($i = 0; $i -lt $ntypes; $i++) {
        $n = [BitConverter]::ToUInt32($b, $o); $o += 4
        $types += [Text.Encoding]::ASCII.GetString($b, $o, $n); $o += $n
    }
    $count = 0
    for ($i = 0; $i -lt $blocks; $i++) {
        if ($types[[BitConverter]::ToUInt16($b, $o + 2 * $i)] -match 'TriShape|TriStrips') { $count++ }
    }
    return $count
}
function Dds([string]$p) {
    $b = [IO.File]::ReadAllBytes($p)
    if ($b.Length -lt 128 -or [Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'DDS ') { return 'not a DDS file' }
    $h = [BitConverter]::ToUInt32($b, 12); $w = [BitConverter]::ToUInt32($b, 16)
    $mips = [BitConverter]::ToUInt32($b, 28)
    $fourcc = [Text.Encoding]::ASCII.GetString($b, 84, 4)
    $flags = [BitConverter]::ToUInt32($b, 8)
    $mipFlag = if ($flags -band 0x20000) { 'mipmap flag set' } else { 'no mipmap flag' }
    return ('{0}x{1}, {2} mip level(s), {3}, {4}, {5:n0} bytes' -f $w, $h, $mips, $fourcc, $mipFlag, $b.Length)
}

Write-Host ''
Write-Host "Main menu backdrop in $Game" -ForegroundColor Cyan
$files = @(
    @{ Rel = 'Data\meshes\interface\logo\logo.nif';                    Kind = 'mesh' },
    @{ Rel = 'Data\meshes\interface\logo\logo01ae.nif';                Kind = 'mesh' },
    @{ Rel = 'Data\textures\interface\objects\Mainmenuwallpaper.dds';  Kind = 'dds' }
)
$bad = 0
foreach ($f in $files) {
    $badBefore = $bad
    $p = Join-Path $Game $f.Rel
    $leaf = Split-Path $f.Rel -Leaf
    $ours = Join-Path $repoMenu $leaf
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "  $($f.Rel): MISSING" -ForegroundColor Red; $bad++; continue }
    $line = '  ' + $f.Rel + ': md5 ' + (Md5 $p)
    if ($f.Kind -eq 'mesh') {
        $s = Shapes $p
        $line += (', {0} shape(s)' -f $s)
        if ($leaf -ieq 'logo01ae.nif') {
            if ($s -eq 0) { $line += ' (empty node, draws nothing: right)' }
            else { $line += ' (A SECOND PLATE: the double, or the old copy collapsed to scale 0)'; $bad++ }
        } elseif ($s -ne 1) { $line += ' (the backdrop plate should be one shape)'; $bad++ }
    } else {
        $d = Dds $p
        $line += ', ' + $d
        if ($d -match ', 1 mip level') { $line += ' (NO MIPS: soft at any size but its own)'; $bad++ }
    }
    if (Test-Path -LiteralPath $ours) {
        if ((Md5 $p) -eq (Md5 $ours)) { $line += ' = the repo copy' } else { $line += ' <> the repo copy in game\menu'; $bad++ }
    } else {
        $line += ' (nothing to compare with in game\menu)'
    }
    Write-Host $line -ForegroundColor $(if ($bad -gt $badBefore) { 'Yellow' } else { 'Green' })
}
Write-Host ''
if ($bad) { Write-Host "  $bad thing(s) wrong. Go.ps1 puts the repo's copies in; Ship carries them." -ForegroundColor Yellow; exit 1 }
Write-Host '  one plate, mipped texture, all as the repo has them.' -ForegroundColor Green
exit 0
