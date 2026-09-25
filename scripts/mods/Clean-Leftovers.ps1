<#
  Clean-Leftovers.ps1

  The other half of Audit-Leftovers.ps1. That one measures and never touches
  anything; this one removes what it found.

  Shows you the list and deletes nothing:

      .\Clean-Leftovers.ps1

  Actually removes it:

      .\Clean-Leftovers.ps1 -Go

  Why this is a script and not a list of paths in a chat window: the small ones
  are the whole point. A 13 GB zip gets noticed and dealt with once. Three .pex
  files at 800 bytes each, a 61 KB client log, a .bak next to a plugin, a
  versionlib nobody loads any more, all sitting in a Data folder that gets
  zipped into an installer four people download, are what actually accumulates,
  precisely because each one on its own never looks worth a command. Run this
  whenever, it is fast when there is nothing to do.

  Close the game first. Files the game has open will not delete, and the script
  will say so rather than pretending otherwise.
#>
[CmdletBinding()]
param(
    # Off by default. Nothing is removed until this is passed.
    [switch]$Go,
    [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function MB($b) { '{0,9:n2} MB' -f ($b / 1MB) }

# The same folders the audit walks.
$roots = @(
    'C:\SkyrimTogether'
    'C:\Thornswood'
    (& (Join-Path $PSScriptRoot '..\release\Where.ps1') Engine)
    'C:\SkyrimRP'
    'C:\Users\evilp\Downloads'
    'C:\Users\evilp\AppData\Roaming\skyrim-rp-launcher'
    'C:\Users\evilp\AppData\Roaming\com.bstar.skymp-launcher'
    'C:\Users\evilp\AppData\Local\Temp\Skyrim Platform'
    'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition'
)

# Anything whose path says Skyrim Together, or the projects it was built on.
$togetherRx = '(?i)(skyrimtogether|skyrim[_ -]together|tiltedonline|tiltedphoques|\bSTServer\b)'

# Backups, previous copies and scratch.
$cruftRx = '(?i)(\.bak$|\.old$|\.tmp$|\.temp$|\.orig$|\.backup$|~$)'

<#
  Paths that match the patterns above and must survive anyway.

  Omega's Emotes for Skyrim Together is the one that matters. It has Skyrim
  Together in its name because of who it was published for, but it is an
  animation mod: a folder of meshes and behaviour files with no plugin, and
  removing it would take idles out of the game. The emote wheel plays names
  read out of Skyrim.esm and Dragonborn.esm so it would survive, but anything
  pointed at those animations would not, and a swept folder is not something
  you notice until something silently stops moving.

  The saves and ini folders are excluded outright rather than filtered. There
  is nothing in them worth this script's attention and a mistake there costs
  somebody their character.
#>
$keepRx = @(
    "(?i)omega's emotes"
    '(?i)\\My Games\\Skyrim Special Edition\\'
    '(?i)\\OneDrive\\'
    # The repo's own working tree. Its .orig and .bak files belong to vcpkg and
    # node_modules, which own their contents and repair them on their terms.
    # The fork was C:\Thornswood-Dev\skymp until 25 September and is the
    # engine\skymp submodule of this repository after it (scripts\release\Where.ps1).
    '(?i)\\(Thornswood-Dev|engine)\\skymp\\(vcpkg|.*node_modules)\\'
) -join '|'

<#
  Inside the Steam copy, only Skyrim Together's own files may be removed.

  That folder is where the vanilla game comes from and the installer
  fingerprints three files in it. The cruft pattern is not allowed to run
  there at all: a .bak in a vanilla Data folder might be somebody's only
  copy of something, and a saved 40 KB is not worth finding out.
#>
$steam = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition'

Head 'Looking'

$hits = New-Object System.Collections.Generic.List[object]

foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) {
        Say ("  not here: $root") 'DarkGray'
        continue
    }
    Say "  $root" 'DarkGray'

    $inSteam = $root -eq $steam

    # Directories first, so that a whole Skyrim Together tree is one entry in
    # the list rather than nine hundred.
    $dirs = @(Get-ChildItem -LiteralPath $root -Recurse -Directory -Force -EA SilentlyContinue |
              Where-Object { $_.FullName -match $togetherRx -and $_.FullName -notmatch $keepRx })

    # A directory inside a directory already on the list adds nothing.
    $topDirs = @()
    foreach ($d in ($dirs | Sort-Object { $_.FullName.Length })) {
        $under = $false
        foreach ($t in $topDirs) {
            if ($d.FullName.StartsWith($t.FullName + '\', 'OrdinalIgnoreCase')) { $under = $true; break }
        }
        if (-not $under) { $topDirs += $d }
    }

    foreach ($d in $topDirs) {
        $bytes = (Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Force -EA SilentlyContinue |
                  Measure-Object -Property Length -Sum).Sum
        if (-not $bytes) { $bytes = 0 }
        $hits.Add([pscustomobject]@{ Path = $d.FullName; Bytes = $bytes; Kind = 'folder'; Why = 'Skyrim Together' })
    }

    # Then loose files, skipping anything already inside a folder on the list.
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -EA SilentlyContinue)
    foreach ($f in $files) {
        $under = $false
        foreach ($t in $topDirs) {
            if ($f.FullName.StartsWith($t.FullName + '\', 'OrdinalIgnoreCase')) { $under = $true; break }
        }
        if ($under) { continue }
        if ($f.FullName -match $keepRx) { continue }

        if ($f.FullName -match $togetherRx) {
            $hits.Add([pscustomobject]@{ Path = $f.FullName; Bytes = $f.Length; Kind = 'file'; Why = 'Skyrim Together' })
            continue
        }
        if (-not $inSteam -and $f.Name -match $cruftRx) {
            $hits.Add([pscustomobject]@{ Path = $f.FullName; Bytes = $f.Length; Kind = 'file'; Why = 'backup or temp' })
        }
    }
}

if ($hits.Count -eq 0) {
    Write-Host ''
    Say 'Nothing to clean. Both patterns came back empty.' 'Green'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ------------------------------------------------------------------ show ----
$total = ($hits | Measure-Object -Property Bytes -Sum).Sum

Head ('Found {0} things, {1}' -f $hits.Count, (MB $total).Trim())
foreach ($h in ($hits | Sort-Object -Property Bytes -Descending)) {
    $tag = if ($h.Kind -eq 'folder') { 'DIR ' } else { '    ' }
    Say ('  {0} {1}  {2}' -f (MB $h.Bytes), $tag, $h.Path) 'DarkGray'
}

if (-not $Go) {
    Write-Host ''
    Say 'Nothing was removed. That was the list.' 'Yellow'
    Say 'To actually remove it:  .\Clean-Leftovers.ps1 -Go' 'Yellow'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ----------------------------------------------------------------- remove ----
Head 'Removing'

$gone = 0
$freed = 0
$stuck = @()

foreach ($h in $hits) {
    try {
        Remove-Item -LiteralPath $h.Path -Recurse -Force -ErrorAction Stop
        $gone++
        $freed += $h.Bytes
    } catch {
        $stuck += [pscustomobject]@{ Path = $h.Path; Error = $_.Exception.Message }
    }
}

Write-Host ''
Say ('Removed {0} of {1}, {2} back.' -f $gone, $hits.Count, (MB $freed).Trim()) 'Green'

if ($stuck.Count) {
    Write-Host ''
    Say ('{0} would not go. Almost always something still has them open:' -f $stuck.Count) 'Yellow'
    foreach ($s in $stuck) {
        Say ('  ' + $s.Path) 'DarkGray'
        Say ('      ' + $s.Error) 'DarkGray'
    }
    Say 'Close the game, the launcher and Vortex, then run it again.' 'Yellow'
}

Write-Host ''
Say 'If anything came out of C:\Thornswood\Game\Data, ship a build so the' 'Gray'
Say 'installer stops carrying it:  .\Ship.ps1 -Package' 'Gray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
