<#
  Check-Backdrop.ps1

  Read only. Says what the main menu backdrop is in a game folder: the two
  logo meshes (their hashes and the root scale that decides whether the
  second plate draws) and the wallpaper texture (size, mip levels, format),
  against what the repo carries in tools\art\menu. Nothing is changed.

    .\tools\Check-Backdrop.ps1                          C:\Thornswood\Game
    .\tools\Check-Backdrop.ps1 -Game C:\Thornswood-DevBuild\Game

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
$repoMenu = Join-Path $Here 'art\menu'

function Md5([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm MD5).Hash.Substring(0, 8).ToLowerInvariant() }
function ScaleAt([string]$p) {
    $b = [IO.File]::ReadAllBytes($p)
    if ($b.Length -lt 0x167) { return [double]::NaN }
    return [BitConverter]::ToSingle($b, 0x163)
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
    $p = Join-Path $Game $f.Rel
    $leaf = Split-Path $f.Rel -Leaf
    $ours = Join-Path $repoMenu $leaf
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "  $($f.Rel): MISSING" -ForegroundColor Red; $bad++; continue }
    $line = '  ' + $f.Rel + ': md5 ' + (Md5 $p)
    if ($f.Kind -eq 'mesh') {
        $s = ScaleAt $p
        $line += (', root scale {0:n3}' -f $s)
        if ($leaf -ieq 'logo01ae.nif') {
            if ($s -eq 0) { $line += ' (collapsed, draws nothing: right)' }
            else { $line += ' (DRAWS A SECOND PLATE: the double)'; $bad++ }
        }
    } else {
        $d = Dds $p
        $line += ', ' + $d
        if ($d -match ', 1 mip level') { $line += ' (NO MIPS: soft at any size but its own)'; $bad++ }
    }
    if (Test-Path -LiteralPath $ours) {
        if ((Md5 $p) -eq (Md5 $ours)) { $line += ' = the repo copy' } else { $line += ' <> the repo copy in tools\art\menu'; $bad++ }
    } else {
        $line += ' (nothing to compare with in tools\art\menu)'
    }
    Write-Host $line -ForegroundColor $(if ($bad) { 'Yellow' } else { 'Green' })
}
Write-Host ''
if ($bad) { Write-Host "  $bad thing(s) wrong. Go.ps1 puts the repo's copies in; Ship carries them." -ForegroundColor Yellow; exit 1 }
Write-Host '  one plate, mipped texture, all as the repo has them.' -ForegroundColor Green
exit 0
