<#
.SYNOPSIS
  Says whether every body the game folder shows people is covered by
  underwear, men and women alike, and exits 2 when one is not.

.DESCRIPTION
  Issue #405. Patrick, 28 Sep: "I really just want no nudity in players or
  NPCs for both males and females." A body in Skyrim is one mesh per sex
  (femalebody_0.nif and _1.nif, malebody_0.nif and _1.nif), and every actor of
  that sex wears it under whatever they have on: people, NPCs, a body on the
  ground after it has been looted, and the figure in the race menu. So the
  underwear has to be part of that mesh. Vanilla Skyrim's are: FemaleUnderwear
  and MaleUnderwear_1 are shapes inside the stock meshes. A body replacer that
  leaves them out makes everybody of that sex nude the moment their clothes
  come off.

  MEASURED 28 SEP on the shipping machine: the female body in both game folders
  is CBBE 3BA 2.48's prebuilt mesh, shapes 3BA, 3BA_Vagina and 3BA_Anus with no
  Bra or Panty, and the male body is HIMBO V5's NeverNude build, whose shapes
  include "HIMBO - Boxers". Both arrive through the Nexus collection, so the
  fix is a collection revision; this is the check that says whether it landed
  and that nothing has undone it since.

  It reads each mesh's own list of shapes out of the nif (the names of its
  BSTriShape and NiTriShape blocks), rather than searching the file for a word:
  "Bra" turns up by chance in the bytes of malebody_1.nif, and bone names such
  as VaginaDeep1 and "NPC Genitals01" are in every skeleton-weighted body,
  covered or not. Then:

  - A woman's body (femalebody_0/_1) is covered when it has a shape for the
    top (Bra, a top, or a one-piece Underwear) and one for the bottom (Panty,
    Underwear, briefs, a loincloth).
  - Astrid's burned body (femalebodyastrid_0/_1, one NPC, after one Dark
    Brotherhood scene) is charred skin with no underwear even in Skyrim's own
    mesh, so it is listed on its own line and fails only when it carries a
    genital shape. Whether it should be covered as well is Patrick's call on
    issue #405.
  - A man's body (malebody_0/_1) is covered when it has a shape for the bottom
    (Boxers, Underwear, briefs, a loincloth).
  - A body that is not loose in Data comes from the game's own archive, and
    Skyrim's own bodies are covered.
  - Any other mesh under meshes\actors\character with a genital shape in it (a
    3BA extra body, The New Gentleman, Schlongs of Skyrim) has to cover it the
    same way, or it counts as nude too.

  First-person bodies are not checked: the first-person camera draws the arms
  and hands, never the torso.

  Read only. It opens meshes to read their headers and writes nothing.
  Exits 0 when every body is covered, 2 when one is nude, 1 when the folder
  is not there or a body mesh cannot be read. Ship.ps1 runs it before a
  release.

.PARAMETER Game
  The game folder, the one with Data in it. Thornswood's own by default.

.PARAMETER Quiet
  Print only what is nude or unreadable, and the verdict.

.EXAMPLE
  .\scripts\mods\Check-CoveredBodies.ps1
  One line for each body mesh saying covered, nude or vanilla, with the shapes
  it found, then the verdict.

.EXAMPLE
  .\scripts\mods\Check-CoveredBodies.ps1 -Game C:\Thornswood-DevBuild\Game
  The same for the dev build's folder.
#>
[CmdletBinding()]
param(
    [string]$Game = ((& (Join-Path $PSScriptRoot '..\release\Where.ps1') Install) + '\Game'),
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

# ------------------------------------------------------------- the words
# Shape names that cover. Matched against whole words of a shape's name, so
# "Bracers" is not a bra and "HIMBO - Boxers" is boxers.
$TopWords    = '(?i)(^|[^a-z])(bra|top|bandeau|chestwrap|breastband)([^a-z]|$)'
$BottomWords = '(?i)(^|[^a-z])(panty|panties|pants|brief|briefs|boxer|boxers|loincloth|thong|shorts|smallclothes)([^a-z]|$)'
# A one-piece: vanilla's FemaleUnderwear and MaleUnderwear_1, HIMBO's
# "HIMBO - Underwear". Covers the top and the bottom.
$OnePiece    = '(?i)underwear'
# Shape names that are anatomy. VaginaDeep1 and "NPC Genitals01" are bones and
# never shape names, which is why this reads shapes and not the whole file.
$Anatomy     = '(?i)(vagina|anus|labia|genital|penis|schlong|scrotum|testic)'

# ------------------------------------------------------------- reading a nif
# The header of a Skyrim nif (20.2.0.7, LE or SE) lists the block types, each
# block's type and size, and a table of strings; a shape block's first field is
# the index of its name in that table. Returns the names of the shape blocks,
# or throws when the file is not a nif this understands.
function Get-NifShapeNames([string]$Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    $nl = [Array]::IndexOf($b, [byte]10)
    if ($nl -lt 0 -or $nl -gt 64) { throw 'no nif header line' }
    $head = [Text.Encoding]::ASCII.GetString($b, 0, $nl)
    if ($head -notmatch '^Gamebryo File Format, Version 20\.2\.0\.7') { throw "not a Skyrim nif ($head)" }
    $i = $nl + 1
    $i += 4                                     # version
    $i += 1                                     # endian
    $i += 4                                     # user version
    $nBlocks = [BitConverter]::ToUInt32($b, $i); $i += 4
    $bsVer = [BitConverter]::ToUInt32($b, $i); $i += 4
    $shorts = 3; if ($bsVer -ge 130) { $shorts = 4 }
    for ($k = 0; $k -lt $shorts; $k++) { $i += 1 + $b[$i] }
    $nTypes = [BitConverter]::ToUInt16($b, $i); $i += 2
    $types = New-Object 'string[]' $nTypes
    for ($k = 0; $k -lt $nTypes; $k++) {
        $l = [BitConverter]::ToUInt32($b, $i); $i += 4
        $types[$k] = [Text.Encoding]::ASCII.GetString($b, $i, $l); $i += $l
    }
    $blockType = New-Object 'int[]' $nBlocks
    for ($k = 0; $k -lt $nBlocks; $k++) { $blockType[$k] = [BitConverter]::ToUInt16($b, $i) -band 0x7FFF; $i += 2 }
    $blockSize = New-Object 'long[]' $nBlocks
    for ($k = 0; $k -lt $nBlocks; $k++) { $blockSize[$k] = [BitConverter]::ToUInt32($b, $i); $i += 4 }
    $nStrings = [BitConverter]::ToUInt32($b, $i); $i += 4
    $i += 4                                     # longest string
    $strings = New-Object 'string[]' $nStrings
    for ($k = 0; $k -lt $nStrings; $k++) {
        $l = [BitConverter]::ToUInt32($b, $i); $i += 4
        $strings[$k] = [Text.Encoding]::ASCII.GetString($b, $i, $l); $i += $l
    }
    $nGroups = [BitConverter]::ToUInt32($b, $i); $i += 4 + 4 * $nGroups
    $names = New-Object Collections.Generic.List[string]
    for ($k = 0; $k -lt $nBlocks; $k++) {
        if ($i + $blockSize[$k] -gt $b.Length) { throw 'block runs past the end of the file' }
        $t = $types[$blockType[$k]]
        if ($t -match 'TriShape$|TriStrips$') {
            $idx = [BitConverter]::ToInt32($b, $i)
            if ($idx -ge 0 -and $idx -lt $nStrings) { $names.Add($strings[$idx]) }
        }
        $i += $blockSize[$k]
    }
    return , $names.ToArray()
}

# What a list of shape names says about a body. Sex is 'female', 'male' or ''
# (a mesh found by its anatomy, whose sex the name does not say).
function Get-BodyVerdict([string[]]$Shapes, [string]$Sex) {
    $top = @($Shapes | Where-Object { $_ -match $TopWords -or $_ -match $OnePiece }).Count -gt 0
    $bottom = @($Shapes | Where-Object { $_ -match $BottomWords -or $_ -match $OnePiece }).Count -gt 0
    $anatomy = @($Shapes | Where-Object { $_ -match $Anatomy })
    $covered = $bottom
    if ($Sex -eq 'female') { $covered = $top -and $bottom }
    $missing = @()
    if ($Sex -eq 'female' -and -not $top) { $missing += 'nothing over the chest' }
    if (-not $bottom) { $missing += 'nothing over the groin' }
    return [pscustomobject]@{ Covered = $covered; Missing = $missing; Anatomy = $anatomy }
}

# ------------------------------------------------------------- the folder
$data = Join-Path $Game 'Data'
$assets = Join-Path $data 'meshes\actors\character\character assets'
if (-not (Test-Path -LiteralPath $data)) {
    Say "No Data folder in $Game. Nothing to check." 'Red'
    exit 1
}

$bodies = @(
    @{ Name = 'femalebody_0.nif';       Sex = 'female' },
    @{ Name = 'femalebody_1.nif';       Sex = 'female' },
    @{ Name = 'femalebodyastrid_0.nif'; Sex = 'astrid' },
    @{ Name = 'femalebodyastrid_1.nif'; Sex = 'astrid' },
    @{ Name = 'malebody_0.nif';         Sex = 'male' },
    @{ Name = 'malebody_1.nif';         Sex = 'male' }
)

$nude = 0
$unread = 0
if (-not $Quiet) { Say "Bodies in $data" 'Cyan' }

foreach ($body in $bodies) {
    $p = Join-Path $assets $body.Name
    if (-not (Test-Path -LiteralPath $p)) {
        $why = "not loose in Data, so the game's own archive supplies it, with its underwear"
        if ($body.Sex -eq 'astrid') { $why = "not loose in Data, so the game's own archive supplies it, as Skyrim ships it" }
        if (-not $Quiet) { Say ("  vanilla  {0,-24} {1}" -f $body.Name, $why) 'DarkGray' }
        continue
    }
    try { $shapes = Get-NifShapeNames $p }
    catch {
        $unread++
        Say ("  UNREAD   {0,-24} {1}" -f $body.Name, $_.Exception.Message) 'Red'
        continue
    }
    $list = ($shapes -join ', ')
    if ($body.Sex -eq 'astrid') {
        $v = Get-BodyVerdict $shapes 'female'
        if ($v.Covered) {
            if (-not $Quiet) { Say ("  covered  {0,-24} shapes: {1}" -f $body.Name, $list) 'Green' }
        } elseif ($v.Anatomy.Count) {
            $nude++
            Say ("  NUDE     {0,-24} shapes: {1}; a genital shape on Astrid's burned body" -f $body.Name, $list) 'Red'
        } elseif (-not $Quiet) {
            Say ("  burned   {0,-24} shapes: {1}; Astrid's charred body, bare in Skyrim's own mesh too, not counted (issue #405)" -f $body.Name, $list) 'Yellow'
        }
        continue
    }
    $v = Get-BodyVerdict $shapes $body.Sex
    if ($v.Covered) {
        if (-not $Quiet) { Say ("  covered  {0,-24} shapes: {1}" -f $body.Name, $list) 'Green' }
    } else {
        $nude++
        Say ("  NUDE     {0,-24} shapes: {1}; {2}" -f $body.Name, $list, ($v.Missing -join ', ')) 'Red'
    }
}

# Anything else under meshes\actors\character that carries anatomy. FaceGenData
# is thousands of heads and never a body, so it is left out. Off Windows the
# folders are joined with /, so either separator is read, and a file is named
# with \ on any machine (#2989).
$root = Join-Path $data 'meshes\actors\character'
$named = @($bodies | ForEach-Object { $_.Name.ToLowerInvariant() })
if (Test-Path -LiteralPath $root) {
    $others = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.nif -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '(?i)[\\/]facegendata[\\/]' -and
            $_.Name -notmatch '(?i)^1stperson' -and
            -not ($_.DirectoryName -eq $assets -and $named -contains $_.Name.ToLowerInvariant())
        })
    foreach ($f in $others) {
        try { $shapes = Get-NifShapeNames $f.FullName } catch { continue }
        $v = Get-BodyVerdict $shapes ''
        if ($v.Anatomy.Count -eq 0) { continue }
        $sex = ''
        if ($f.Name -match '(?i)female') { $sex = 'female'; $v = Get-BodyVerdict $shapes 'female' }
        $rel = $f.FullName.Substring($data.Length + 1).Replace([IO.Path]::DirectorySeparatorChar, '\')
        if ($v.Covered) {
            if (-not $Quiet) { Say ("  covered  {0} shapes: {1}" -f $rel, ($shapes -join ', ')) 'Green' }
        } else {
            $nude++
            Say ("  NUDE     {0} shapes: {1}; {2}" -f $rel, ($shapes -join ', '), ($v.Missing -join ', ')) 'Red'
        }
    }
}

Say ''
if ($unread) {
    Say ("{0} body mesh{1} could not be read. Nothing is certain until it can." -f $unread, $(if ($unread -eq 1) { '' } else { 'es' })) 'Red'
    exit 1
}
if ($nude) {
    Say ("{0} body mesh{1} would show somebody nude. The bodies come from the Nexus collection: the covered ones go in as a collection revision (issue #405)." -f $nude, $(if ($nude -eq 1) { '' } else { 'es' })) 'Red'
    exit 2
}
Say 'Every body is covered.' 'Green'
exit 0
