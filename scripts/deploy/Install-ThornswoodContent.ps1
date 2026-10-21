<#
  Install-ThornswoodContent.ps1

  Drops Thornswood-Content.esp into the game folder and inserts it into the load
  order ahead of the city overhauls.

  Why ahead of them: the plugin carries 101 CELL records purely as parents for
  its references. Their data restates vanilla, so letting JK's Whiterun, The
  Great Cities and the rest win those records costs us nothing, while references
  from every plugin accumulate regardless of order.
#>
param(
    [string]$Esp,
    [string]$Data     = ((& (Join-Path $PSScriptRoot '..\release\Where.ps1') Install) + '\Game\Data'),
    [string]$Profile  = ((& (Join-Path $PSScriptRoot '..\release\Where.ps1') Install) + '\Profile'),
    [string]$Before   = 'The Great Cities - Minor Cities and Towns.esp'
)


# Resolved from where this script is rather than from a fixed path under
# Downloads. The repo folder gets renamed and moved, and a default that names it
# turns every one of these into a broken command the first time it does.
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Esp) { $Esp = Join-Path $Here '..\..\game\content\Thornswood-Content.esp' }

$name = 'Thornswood-Content.esp'

if (-not (Test-Path -LiteralPath $Esp)) { throw "not found: $Esp" }
Copy-Item -LiteralPath $Esp -Destination (Join-Path $Data $name) -Force
Write-Host "copied $name -> $Data" -ForegroundColor Cyan

$targets = @(
    @{ Path = "$Profile\Default\plugins.txt";      Star = $true  }
    @{ Path = "$Profile\Default\loadorder.txt";    Star = $false }
    @{ Path = "$Profile\LocalAppData\Plugins.txt"; Star = $true  }
    @{ Path = "$Profile\LocalAppData\loadorder.txt"; Star = $false }
)

foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t.Path)) { Write-Host "  skip (absent) $($t.Path)" -ForegroundColor DarkGray; continue }

    $lines = [Collections.Generic.List[string]](Get-Content -LiteralPath $t.Path)
    $entry = if ($t.Star) { "*$name" } else { $name }

    # already there? take it out first so a re-run repositions instead of duplicating
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i].TrimStart('*').Trim() -ieq $name) { $lines.RemoveAt($i) }
    }

    $at = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimStart('*').Trim() -ieq $Before) { $at = $i; break }
    }
    if ($at -lt 0) { $at = $lines.Count }        # anchor missing: append
    $lines.Insert($at, $entry)

    # WriteAllLines, not Set-Content -Encoding UTF8: that adds a byte order mark
    # under Windows PowerShell 5.1 and not under 7, so the same line produces a
    # different file depending on who runs it. The game and SkyrimPlatform both
    # stop on a BOM, and the .cmd wrappers use 5.1.
    [IO.File]::WriteAllLines($t.Path, $lines, (New-Object Text.UTF8Encoding($false)))
    $n = ($lines | Where-Object { $_ -match '^\*' }).Count
    Write-Host ("  {0,-46} line {1}{2}" -f (Split-Path $t.Path -Leaf), ($at + 1),
                $(if ($t.Star) { ", $n enabled" } else { '' })) -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'done. Thornswood-Content.esp is installed and positioned.' -ForegroundColor Green
Write-Host 'It adds 116 crafting and gathering stations and 119 fixes to vanilla objects.' -ForegroundColor DarkGray
