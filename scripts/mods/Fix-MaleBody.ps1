<#
  Fix-MaleBody.ps1

  The male body mesh in the game folder is a genital-slotted one, left behind
  when The New Gentleman was taken out. The plugin that supplied the part is
  gone, so the slot in the body renders as a hole you can see the sky through.

  malebody_0.nif here is about 1 MB. The stock one inside Skyrim - Meshes0.bsa
  is a fraction of that and has no slot, so moving the loose files aside is the
  whole fix: the archive supplies the body again the moment nothing overrides
  it. Nothing is deleted, so putting it back is one move.

  The female body is left alone. It is a CBBE build with no slot and no missing
  part, and replacing it would undo work that is not broken.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Data = 'C:\Thornswood\Game\Data',
    [switch]$Undo
)

$assets = Join-Path $Data 'meshes\actors\character\character assets'
$stash  = Join-Path $Data '_removedBody\meshes\actors\character\character assets'
$names  = 'malebody_0.nif', 'malebody_1.nif', 'malebody.tri'

if (-not (Test-Path -LiteralPath $assets)) { throw "not found: $assets" }

$from = if ($Undo) { $stash }  else { $assets }
$to   = if ($Undo) { $assets } else { $stash }

if (-not (Test-Path -LiteralPath $to)) { New-Item -ItemType Directory -Path $to -Force | Out-Null }

$moved = 0
foreach ($n in $names) {
    $src = Join-Path $from $n
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host ("  not there  {0}" -f $n) -ForegroundColor DarkGray
        continue
    }
    $mb = [math]::Round((Get-Item -LiteralPath $src).Length / 1MB, 2)
    if (-not $PSCmdlet.ShouldProcess($n, $(if ($Undo) { 'restore' } else { 'move aside' }))) { continue }
    Move-Item -LiteralPath $src -Destination (Join-Path $to $n) -Force
    Write-Host ("  {0,-18} {1} MB  ->  {2}" -f $n, $mb, (Split-Path $to -Leaf)) -ForegroundColor Cyan
    $moved++
}

Write-Host ''
if ($moved -eq 0) {
    Write-Host 'nothing moved.' -ForegroundColor Yellow
} elseif ($Undo) {
    Write-Host "$moved file(s) restored. The slotted body is back." -ForegroundColor Green
} else {
    Write-Host "$moved file(s) moved aside. Skyrim falls back to the body in Skyrim - Meshes0.bsa." -ForegroundColor Green
    Write-Host 'Run with -Undo to put them back.' -ForegroundColor DarkGray
}
