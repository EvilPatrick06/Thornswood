<#
  Clean-Downloads.ps1

  Moves known-safe clutter out of Downloads into a quarantine folder.
  It does NOT delete anything, and it does NOT touch:
    - Vortex mod archives (.7z / .zip mod downloads)
    - SkyrimTogether-Repo, SkyrimTogether-Tools, SDT
    - any coursework, resume, or document
    - __folder_managed_by_vortex or desktop.ini

  Run with -WhatIf first to see the list without moving anything.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Downloads = "$HOME\Downloads",
    [string]$Quarantine = "$HOME\Downloads\_cleanup",
    [switch]$IncludeTNG   # also quarantine the kept The New Gentleman archive
)

$targets = @(
    # the two files that overwrote the live load order
    'plugins.txt'
    'loadorder.txt'

    # scripts I generated in earlier sessions; copies live in the repo/outputs
    'Add-SteamLibrary.ps1'
    'Cut-CreationClub.ps1'
    'Lock-SkyrimVersion.ps1'
    'Preflight-FUS.ps1'
    'Prep-VR.ps1'
    'Remove-Mereth.ps1'
    'Remove-SkyrimRP.ps1'
    'Reset-Vortex.ps1'
    'Restore-VortexData.ps1'
    'Wipe-Keizaal.ps1'
    'app_preview.png'

    # discord exports
    'message.txt'
    'message (1).txt'
    'message (2).txt'
    'message (3).txt'
    'message (4).txt'

    # stale logs and bundles
    'crash-2026-08-23-15-59-02.log'
    'crash-2026-09-11-05-42-01.log'
    'thornswood-20260911-1955.zip'
    'SkyrimTogether-1.0.1.bak'

    # strays and exact duplicates
    'midm.esp'
    'install.txt'
    'PapyrusUtil AE SE - Scripting Utility Functions-13048-4-6-1705639805 (1).zip'
    'skse64_2_02_06 (1).7z'
    'The New Gentleman 104215 4.2.6 2026-08-26T18-20Z IoFlhf4M8 (1).7z'
)

if ($IncludeTNG) {
    $targets += 'The New Gentleman 104215 4.2.6 2026-08-26T18-20Z IoFlhf4M8.7z'
}

if (-not (Test-Path $Quarantine)) {
    New-Item -ItemType Directory -Path $Quarantine -Force | Out-Null
}

$moved = 0; $bytes = 0; $absent = @()
foreach ($t in $targets) {
    $p = Join-Path $Downloads $t
    if (-not (Test-Path -LiteralPath $p)) { $absent += $t; continue }
    $size = (Get-Item -LiteralPath $p).Length
    if ($PSCmdlet.ShouldProcess($t, 'move to _cleanup')) {
        Move-Item -LiteralPath $p -Destination (Join-Path $Quarantine $t) -Force
        $moved++; $bytes += $size
    }
}

Write-Host ''
Write-Host ("moved {0} files, {1:N1} MB -> {2}" -f $moved, ($bytes/1MB), $Quarantine) -ForegroundColor Cyan
if ($absent) {
    Write-Host ("not found (already gone): {0}" -f ($absent -join ', ')) -ForegroundColor DarkGray
}
Write-Host 'Nothing was deleted. Check the folder, then bin it yourself when happy.' -ForegroundColor DarkGray
