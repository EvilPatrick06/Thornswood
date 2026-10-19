<#
  test-2298-held-board.ps1

      pwsh -NoProfile -File .\tests\test-2298-held-board.ps1

  #2298: dev 1.2.3 listed the notice board's mesh as gone, so every board the
  content plugin places lost its model. New-ShipHeld in
  scripts\release\Ship-Rules.ps1 gave every held line Revision 2, the board's
  included, though its own comment said no revision carries it, and releases
  are built against revision 2. Now every line names its own way out with no
  default: -Revision N, or -WhileContentNamesIt, which holds a mesh for exactly
  as long as game\content\Thornswood-Content.esp names it as a model.

  Since #2298 the committed plugin's board is Thornswood's own mesh, so the
  old board's line held nothing, and on 16 October it came out (#400,
  decision C: the old mesh's folder carries the other server's short name,
  which is named nowhere here). The way out stays for the next mesh the
  plugin names that no revision carries, so the plugins built below prove it
  on a held line made for the test, at a path of the same shape.

  This proves:
    a line with no way out, or with both, cannot be made;
    no line is held by the plugin while the committed plugin does not name its
      mesh (a line that holds nothing); the committed plugin names
      Thornswood's own board, the new board and drop box are ours, and a mesh
      shaped like the old board is somebody else's file at every revision;
    a plugin that names a held mesh holds it, at every revision;
    a plugin that no longer names it lets it go at once, at every revision;
    a model inside a compressed record is still read;
    a missing plugin stops rather than guessing;
    every line in Ship-Rules leaves at its revision, as before.
  Plugins here are built in a scratch folder; nothing outside it is written.
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
. (Join-Path $Repo 'scripts\release\Ship-Rules.ps1')

# A mesh of the old board's shape: MissiveBoardCOTND.nif in a folder of a
# server's own under meshes.
$board = 'Data\meshes\otherserver-messageboard\missiveboardcotnd.nif'
$boardModel = 'otherserver-messageboard\MissiveBoardCOTND.nif'

# ---- a line names exactly one way out -----------------------------------------
$threw = $false; try { $null = New-ShipHeld 'Data\meshes\x\y.nif' 'some mod (1)' } catch { $threw = $true }
Yes 'a held line with no way out cannot be made (the old default of revision 2 is gone)' $threw
$threw = $false; try { $null = New-ShipHeld 'Data\meshes\x\y.nif' 'some mod (1)' -Revision 2 -WhileContentNamesIt } catch { $threw = $true }
Yes 'a held line with both a revision and the plugin cannot be made' $threw
$threw = $false; try { $null = New-ShipHeld 'Data\meshes\x\' 'some mod (1)' -WhileContentNamesIt } catch { $threw = $true }
Yes 'the plugin way out is for one mesh file, not a folder' $threw
$threw = $false; try { $null = New-ShipHeld 'Data\textures\x.dds' 'some mod (1)' -WhileContentNamesIt } catch { $threw = $true }
Yes '  and only under Data\meshes\, where a plugin''s models are' $threw
$made = New-ShipHeld 'Data\meshes\A\B.nif' 'some mod (1)' -WhileContentNamesIt
Yes 'the model it asks the plugin for is the path under meshes\' ($made.ContentModel -eq 'A\B.nif' -and $made.Revision -eq 0)

# ---- the held lines, against the committed plugin -----------------------------
$byPlugin = @($ShipHeldForCollection | Where-Object { [string]$_.ContentModel })
$dead = @($byPlugin | Where-Object { -not (Test-ShipContentNames ([string]$_.ContentModel)) })
Yes ('no line is held by the plugin while the plugin does not name its mesh ({0} held that way)' -f $byPlugin.Count) ($dead.Count -eq 0)
foreach ($d in $dead) { Write-Host ('      holds nothing: ' + [string]$d.Path) }
Yes 'the committed plugin names Thornswood''s own board, meshes\thornswood\noticeboard01.nif' (Test-ShipContentNames 'thornswood\noticeboard01.nif')
Yes '  and not a mesh shaped like the old board' (-not (Test-ShipContentNames $boardModel))
foreach ($rev in 0, 1, 2, 3, 99) {
    Yes "a mesh shaped like the old board is not held at revision $rev" (-not (Test-ShipHeld $board $rev))
    Yes "  and does not ship at revision $rev" (Test-ShipNotOurs $board $rev)
}
Yes 'the new board and its drop box are ours at every revision' (
    -not (Test-ShipNotOurs 'Data\meshes\thornswood\noticeboard01.nif' 2) -and -not (Test-ShipNotOurs 'Data\meshes\thornswood\dropbox01.nif' 99))

# ---- plugins built here --------------------------------------------------------
function Sub([string]$tag, [byte[]]$body) {
    $out = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter $out
    $w.Write([Text.Encoding]::ASCII.GetBytes($tag)); $w.Write([uint16]$body.Length); $w.Write($body); $w.Flush()
    return $out.ToArray()
}
function Z([string]$s) { return [Text.Encoding]::ASCII.GetBytes($s + [char]0) }
function Rec([string]$tag, [uint32]$fid, [byte[]]$data, [bool]$compress) {
    $flags = [uint32]0
    if ($compress) {
        $flags = [uint32]0x00040000
        $z = New-Object IO.MemoryStream
        $z.WriteByte(0x78); $z.WriteByte(0x9C)
        $d = New-Object IO.Compression.DeflateStream $z, ([IO.Compression.CompressionMode]::Compress), $true
        $d.Write($data, 0, $data.Length); $d.Dispose()
        $packed = New-Object IO.MemoryStream
        $pw = New-Object IO.BinaryWriter $packed
        $pw.Write([uint32]$data.Length); $pw.Write($z.ToArray()); $pw.Flush()
        $data = $packed.ToArray()
    }
    $out = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter $out
    $w.Write([Text.Encoding]::ASCII.GetBytes($tag)); $w.Write([uint32]$data.Length); $w.Write($flags); $w.Write($fid)
    $w.Write([byte[]](0, 0, 0, 0, 44, 0, 0, 0)); $w.Write($data); $w.Flush()
    return $out.ToArray()
}
function Plugin([string]$path, [string]$model, [bool]$compress) {
    $acti = Rec 'ACTI' 0x0500593B ((Sub 'EDID' (Z 'ThornswoodMessageBoard')) + (Sub 'MODL' (Z $model))) $compress
    $grup = New-Object IO.MemoryStream
    $gw = New-Object IO.BinaryWriter $grup
    $gw.Write([Text.Encoding]::ASCII.GetBytes('GRUP')); $gw.Write([uint32](24 + $acti.Length))
    $gw.Write([Text.Encoding]::ASCII.GetBytes('ACTI')); $gw.Write([uint32]0); $gw.Write([uint32]0); $gw.Write([uint32]0)
    $gw.Write([byte[]]$acti); $gw.Flush()
    $hedr = New-Object IO.MemoryStream
    $hw = New-Object IO.BinaryWriter $hedr
    $hw.Write([single]1.7); $hw.Write([int]1); $hw.Write([uint32]0x800); $hw.Flush()
    $tes4 = Rec 'TES4' 0 ((Sub 'HEDR' $hedr.ToArray()) + (Sub 'MAST' (Z 'Skyrim.esm')) + (Sub 'DATA' ([byte[]](0, 0, 0, 0, 0, 0, 0, 0)))) $false
    [IO.File]::WriteAllBytes($path, [byte[]]($tes4 + $grup.ToArray()))
}

$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-2298-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($T)
$was = $ShipContentPlugin
$wasHeld = $ShipHeldForCollection
try {
    # A line held while the plugin names the mesh, made for the test.
    $ShipHeldForCollection = @($wasHeld) + @(New-ShipHeld $board 'none: a mesh no collection revision carries' -WhileContentNamesIt)
    $named = Join-Path $T 'names-it.esp'
    $moved = Join-Path $T 'repointed.esp'
    $packed = Join-Path $T 'compressed.esp'
    Plugin $named $boardModel $false
    Plugin $moved 'Clutter\Missives\MissiveBoardCOTND.nif' $false
    Plugin $packed $boardModel $true

    $ShipContentPlugin = $named
    Yes 'a plugin built here that names the mesh holds it at revision 2' ((Test-ShipHeld $board 2) -and -not (Test-ShipNotOurs $board 2))
    foreach ($rev in 0, 3, 99) { Yes "  and at revision $rev" (Test-ShipHeld $board $rev) }
    Yes '  in any case and with either slash' ((Test-ShipHeld $board.ToUpperInvariant() 2) -and (Test-ShipHeld $board.Replace('\', '/') 2))

    $ShipContentPlugin = $moved
    Yes 'repointed at a mesh the collection installs, the held mesh is let go at revision 0' (-not (Test-ShipHeld $board 0))
    Yes '  and at revision 2' (-not (Test-ShipHeld $board 2))
    Yes '  and is then somebody else''s file, which never ships' (Test-ShipNotOurs $board 2)

    $ShipContentPlugin = $packed
    Yes 'a model inside a compressed record is read: held' (Test-ShipHeld $board 2)

    $ShipContentPlugin = Join-Path $T 'missing.esp'
    $threw = $false; try { $null = Test-ShipHeld $board 2 } catch { $threw = $true }
    Yes 'no plugin to read stops rather than guessing whether the board ships' $threw
    $threw = $false; try { $null = Test-ShipHeld 'Data\meshes\furniture\noble\nobleendtable04.nif' 1 } catch { $threw = $true }
    Yes '  while a line a revision settles is not asked of the plugin at all' (-not $threw)

    $bad = Join-Path $T 'not-a-plugin.esp'
    [IO.File]::WriteAllBytes($bad, [byte[]](1..64))
    $ShipContentPlugin = $bad
    $threw = $false; try { $null = Test-ShipHeld $board 2 } catch { $threw = $true }
    Yes 'a file that is not a plugin stops too' $threw

    $ShipContentPlugin = $named
    Yes 'a file beside the held mesh is not held' (-not (Test-ShipHeld ($board -replace 'missiveboardcotnd\.nif$', 'other.nif') 2))
}
finally {
    $ShipContentPlugin = $was
    $ShipHeldForCollection = $wasHeld
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- every line in Ship-Rules, as before ----------------------------------------
$others = @($ShipHeldForCollection)
Yes ('the {0} lines in Ship-Rules each leave at a revision' -f $others.Count) ($others.Count -gt 0 -and @($others | Where-Object { [int]$_.Revision -lt 1 -or [string]$_.ContentModel }).Count -eq 0)
foreach ($h in $others) {
    $p = [string]$h.Path
    $rel = $(if ($p.EndsWith('\')) { $p + 'x.nif' } else { $p })
    Yes ("{0}: held below revision {1}, gone from it" -f $rel, $h.Revision) ((Test-ShipHeld $rel ([int]$h.Revision - 1)) -and -not (Test-ShipHeld $rel ([int]$h.Revision)))
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
