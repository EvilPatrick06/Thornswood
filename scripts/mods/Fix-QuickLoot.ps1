<#
  Fix-QuickLoot.ps1 - turn MCMHelper.esp on, on both sides, in one go.

  QuickLoot's settings quest is registered through MCM Helper, and MCM Helper
  needs its own plugin active. It is a hundred byte stub with no records worth
  the name, so on its own it is nothing. The catch is what it does to the
  numbering.

  SkyMP resolves a form as fileIndex * 0x01000000 + localId and nothing
  translates between client and server. The client checks this at startup, in
  loadOrderVerificationService: for every entry the server lists, the client's
  plugin at that same index must match by filename, size and CRC. More mods
  than the server is allowed and gives the yellow warning. A mismatch inside
  the server's list is the red one, and the message it prints is "Expect
  EVERYTHING BREAK", because every form id from a mod plugin then lands on the
  wrong object.

  MCMHelper.esp is not ESL flagged (its TES4 header flags are 0x00000000), so
  it takes a real index. In plugins.txt it sits at line 80, between
  SunHelmDiseases.esp at 79 and chfshVariousActions.esp at 86, which is index
  41 and 42 of the server's list. So enabling it client side alone shifts
  seventeen server entries by one. That is the whole reason this is a script
  and not a tick box.

  Both sides, or neither.
#>

[CmdletBinding()]
param(
  [string] $Game     = 'C:\Thornswood',
  [string] $Settings = (& (Join-Path $PSScriptRoot '..\release\Where.ps1') ServerSettings),
  [string] $After    = 'SunHelmDiseases.esp'
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Head($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }
function Note($t) { Write-Host "  $t" }
function Bad($t)  { Write-Host "  $t" -ForegroundColor Yellow }

if (-not (Test-Path -LiteralPath $Settings)) { throw "server settings not found: $Settings" }

# ------------------------------------------------------------ the server ---
Head 'Server load order'
$raw = Get-Content -LiteralPath $Settings -Raw
$s   = $raw | ConvertFrom-Json
$lo  = @($s.loadOrder)

$already = $false
foreach ($p in $lo) { if ([IO.Path]::GetFileName($p) -ieq 'MCMHelper.esp') { $already = $true } }

if ($already) {
  Note 'MCMHelper.esp is already in the server list'
} else {
  $at = -1
  for ($i = 0; $i -lt $lo.Count; $i++) {
    if ([IO.Path]::GetFileName($lo[$i]) -ieq $After) { $at = $i; break }
  }
  if ($at -lt 0) { throw "could not find $After in the server load order, not touching it" }

  $entry = ($lo[$at] -replace '[^/\\]+$', 'MCMHelper.esp')
  $new = @()
  for ($i = 0; $i -lt $lo.Count; $i++) {
    $new += $lo[$i]
    if ($i -eq $at) { $new += $entry }
  }
  $s.loadOrder = $new

  # No BOM. Node reads this file, and a BOM makes it "Unexpected token" rather
  # than JSON, which is a confusing way to find out.
  $json = $s | ConvertTo-Json -Depth 12
  [IO.File]::WriteAllText($Settings, $json, (New-Object Text.UTF8Encoding($false)))
  Note "inserted after $After, now $($new.Count) entries"
}

# ------------------------------------------------------------ the client ---
Head 'Client load order'
foreach ($f in @(
  (Join-Path $Game 'Profile\LocalAppData\Plugins.txt'),
  (Join-Path $Game 'Profile\Default\plugins.txt')
)) {
  if (-not (Test-Path -LiteralPath $f)) { continue }
  $lines = [IO.File]::ReadAllLines($f)
  $hit = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq 'MCMHelper.esp') { $lines[$i] = '*MCMHelper.esp'; $hit = $true }
  }
  if ($hit) {
    [IO.File]::WriteAllLines($f, $lines, (New-Object Text.UTF8Encoding($false)))
    Note "enabled in $(Split-Path -Leaf $f)"
  } else {
    Note "already enabled in $(Split-Path -Leaf $f)"
  }
}

# ------------------------------------------------------------- quickloot ---
Head 'QuickLoot'
$off = Join-Path $Game 'Game\Data\SKSE\Plugins\QuickLootIE.dll.off'
if (Test-Path -LiteralPath $off) {
  Rename-Item -LiteralPath $off -NewName 'QuickLootIE.dll'
  Note 'plugin switched back on'
} else {
  Note 'plugin was never switched off'
}

# ----------------------------------------------------------------- check ---
Head 'Checking both sides line up'
$align = Join-Path $Here 'Align-LoadOrder.ps1'
if (Test-Path -LiteralPath $align) {
  & $align -Plugins (Join-Path $Game 'Profile\LocalAppData\Plugins.txt') -Settings $Settings
} else {
  Bad 'Align-LoadOrder.ps1 is missing, cannot verify'
}

Head 'Now'
Note 'The server has to be republished before you launch, or the two lists disagree'
Note 'and every form id from a mod plugin lands on the wrong object:'
Note ''
Note '    .\Publish-Server.ps1'
Note ''
Note 'MCMHelper.esp is a header only plugin. If the server will not start after'
Note 'publishing, libespm refused it, and the answer is to take it back out'
Note 'rather than to keep QuickLoot.'
