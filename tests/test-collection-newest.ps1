<#
  test-collection-newest.ps1

      pwsh -NoProfile -File .\tests\test-collection-newest.ps1

  The two revision numbers the deploy gate stands on, both read out of Vortex's
  own state.v2: the newest Vortex KNOWS is out (Get-CollectionNewest), and the
  revision this machine HAS installed (Get-CollectionRevision). The newest half
  silently went blind on 22 September; the installed half went blind on
  27 September, when it is covered here, because current Vortex stopped naming
  the mod folder for the collection and the folder-name reader could no longer
  find a number.

  WHAT HAPPENED. Get-CollectionNewest only knew ONE shape, the transition
  Vortex writes the moment it notices a newer revision than the one installed:

      "newestVersion","from":"3","to":"4"

  That worked while the machine was behind. The moment revision 5 was actually
  installed there was no transition left to record, Vortex wrote the plain
  current value instead, the regex matched nothing, and the function answered
  0. Behind is false when either number is unknown, so the gate that had been
  added the day before to stop a stale collection reaching the server passed
  without checking anything, and nothing in the output said so.

  The plain shape, measured off this machine's own state.v2:

      6E 65 77 65 73 74 56 65 72 73 69 6F 6E 03 22 35 22
      n  e  w  e  s  t  V  e  r  s  i  o  n  len "  5  "

  LevelDB writes the key, then ONE length byte, then that many bytes of JSON.

  The newest half builds a state.v2 of its own out of those exact bytes and
  points the real function at it through APPDATA, so what is under test is the
  shipped function rather than a copy of it. The installed half reads state
  as LevelDB since #1582, so its cases are LevelDB, written by the same writer
  as the reader's own fixtures (see Case below).

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$LoadOrderPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $LoadOrderPath) { $LoadOrderPath = Join-Path $Here 'scripts\mods\LoadOrder.ps1' }
. $LoadOrderPath

$pass = 0; $fail = 0
function Yes($what, $cond) {
  if ($cond) { $script:pass++; Write-Host "PASS  $what" -ForegroundColor Green }
  else       { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-newest-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$state = Join-Path $root 'Vortex\state.v2'
$null = New-Item -ItemType Directory -Force -Path $state
$realAppData = $env:APPDATA

# The plain value, byte for byte as Vortex writes it: key, length, JSON.
function Plain([int]$n) {
  $v = '"' + $n + '"'
  $b = [Collections.Generic.List[byte]]::new()
  $b.AddRange([Text.Encoding]::ASCII.GetBytes('newestVersion'))
  $b.Add([byte]$v.Length)
  $b.AddRange([Text.Encoding]::ASCII.GetBytes($v))
  $b.AddRange([Text.Encoding]::ASCII.GetBytes([char]1 + 'persistent###mods###skyrimse'))
  return $b.ToArray()
}
function Transition([int]$from, [int]$to) {
  return [Text.Encoding]::ASCII.GetBytes(
    'persistent###mods###skyrimse###"newestVersion","from":"' + $from + '","to":"' + $to + '"')
}
# The installed half (Have). Since #1582 the installed revision is read by
# launcher\app\VortexProfileState.cs, which reads state.v2 as LevelDB: CURRENT,
# the manifest it names, the tables and the log, with sequences, deletions and
# checksums. Bytes with no CURRENT read as nothing there. So each case here is
# a LevelDB folder written by tests\fixtures\vortex-state-rows.py, the writer
# the reader's own fixtures use, and is its own APPDATA under $cases.
#
# One row is one flattened key, joined by ###, and the JSON Vortex stores for
# it. The installed revision is recorded against the mod, tied to the
# collection by the slug recorded against the same mod id.
$cases = Join-Path $root 'cases'
$spec = [ordered]@{}
function Row([string]$key, [string]$json) { [pscustomobject]@{ key = $key; value = $json } }
function Attr([string]$modId, [string]$name, [string]$valueJson) {
  Row "persistent###mods###skyrimse###$modId###attributes###$name" $valueJson
}
function RevInfo([string]$revId, [string]$slug, [int]$num) {
  Row "persistent###collections###revisions###$revId###info###collection###slug" ('"' + $slug + '"')
  Row "persistent###collections###revisions###$revId###info###revisionNumber" ([string]$num)
}
# Rows in the compressed table are state as Vortex leaves it after compaction;
# rows in the log are a change as Vortex writes it before compaction. Newest
# and the mod ids still read state as text, which only the log keeps whole
# (#1902), so a case those readers also look at keeps its rows in the log.
function Case([string]$name, [object[]]$table, [object[]]$log) {
  $spec[$name] = [ordered]@{ table = $table; log = $log }
}
function Put([string]$name, [byte[]]$bytes) {
  [IO.File]::WriteAllBytes((Join-Path $state $name), $bytes)
}
function Clear-State { Get-ChildItem $state -File | Remove-Item -Force }

$z = 'vortex_collection_ZRT7NjhN_'
Case 'installed' @((Attr $z 'collectionSlug' '"ombo2a"'), (Attr $z 'revisionNumber' '5')) @()
Case 'installed-two' @((Attr $z 'collectionSlug' '"ombo2a"'), (Attr $z 'revisionNumber' '5'),
  (Attr 'vortex_collection_AAbb99xx_' 'collectionSlug' '"7essxf"'), (Attr 'vortex_collection_AAbb99xx_' 'revisionNumber' '12')) @()
Case 'ready' @() @((Attr $z 'collectionSlug' '"ombo2a"'), (Attr $z 'revisionNumber' '5'), (Attr $z 'newestVersion' '"5"'))
Case 'draft' @() (@((Attr $z 'collectionSlug' '"7essxf"'), (Attr $z 'revisionNumber' '1')) + @(RevInfo '796316' '7essxf' 1))
Case 'authoring' @() (@((Attr $z 'newestFileId' '796316'), (Attr $z 'newestVersion' '"1"')) + @(RevInfo '796316' '7essxf' 1))
Case 'slug-only' @() @(Attr $z 'collectionSlug' '"7essxf"')

try {
  $specPath = Join-Path $root 'cases.json'
  [IO.File]::WriteAllText($specPath, (ConvertTo-Json -InputObject $spec -Depth 6), (New-Object Text.UTF8Encoding($false)))
  & python (Join-Path $Here 'tests\fixtures\vortex-state-rows.py') $cases $specPath
  if ($LASTEXITCODE) { throw 'tests\fixtures\vortex-state-rows.py could not write the installed cases' }

  $env:APPDATA = $root

  # ---- the shape that broke it ---------------------------------------------
  Clear-State; Put '000124.log' (Plain 5)
  Yes 'the plain current value is read' ((Get-CollectionNewest) -eq 5)

  Clear-State; Put '000124.log' (Transition 3 4)
  Yes 'the transition shape still works' ((Get-CollectionNewest) -eq 4)

  # Both in one file is the real world: the log holds the whole history, so a
  # machine that went 3 to 4 and then sat on 5 has both written down.
  Clear-State
  $mix = [Collections.Generic.List[byte]]::new()
  $mix.AddRange([byte[]](Transition 3 4)); $mix.AddRange([byte[]](Plain 5))
  Put '000124.log' $mix.ToArray()
  Yes 'with both shapes present the highest wins' ((Get-CollectionNewest) -eq 5)

  # ---- the history, and the whole reason it scans everything ----------------
  Clear-State
  $hist = [Collections.Generic.List[byte]]::new()
  $hist.AddRange([byte[]](Transition 2 3)); $hist.AddRange([byte[]](Transition 3 4))
  Put '000124.log' $hist.ToArray()
  Yes 'the newest transition wins, not the first' ((Get-CollectionNewest) -eq 4)

  Clear-State
  Put '000122.log' (Transition 2 3)
  Put '000124.log' (Plain 7)
  Yes 'every file in the folder is scanned' ((Get-CollectionNewest) -eq 7)

  # A later file holding an OLDER number must not win. The log is a history and
  # the highest is the answer, whichever file it is in.
  Clear-State
  Put '000122.log' (Plain 9)
  Put '000124.log' (Plain 4)
  Yes 'an older number in a later file does not win' ((Get-CollectionNewest) -eq 9)

  Yes 'two digit revisions read whole, not truncated' `
    ((& { Clear-State; Put '000124.log' (Plain 12); Get-CollectionNewest }) -eq 12)

  # ---- when it genuinely cannot tell ---------------------------------------
  # 0 has to keep meaning "could not read", because Behind is false on 0 and
  # the deploy gate refuses on an unreadable revision rather than passing.
  Clear-State
  Yes 'an empty state folder reads 0' ((Get-CollectionNewest) -eq 0)

  Clear-State; Put '000124.log' ([Text.Encoding]::ASCII.GetBytes('persistent###mods###skyrimse###nothing of interest'))
  Yes 'a file with no version in it reads 0' ((Get-CollectionNewest) -eq 0)

  # A deleted key writes a length of 0 and no value. It must not be read as a
  # number, and it must not throw.
  Clear-State
  $del = [Collections.Generic.List[byte]]::new()
  $del.AddRange([Text.Encoding]::ASCII.GetBytes('newestVersion'))
  $del.Add([byte]0)
  $del.AddRange([Text.Encoding]::ASCII.GetBytes('bpersistent###mods###skyrimse'))
  Put '000124.log' $del.ToArray()
  Yes 'a deleted key reads 0 rather than a number' ((Get-CollectionNewest) -eq 0)

  $env:APPDATA = Join-Path $root 'no-such-folder'
  Yes 'no state.v2 at all reads 0' ((Get-CollectionNewest) -eq 0)
  $env:APPDATA = $root

  # ---- the bound on the length byte ----------------------------------------
  # The class is [\x00-\x1F] rather than a wildcard on purpose. A wildcard
  # would step over a quote and read the number out of a neighbouring key.
  Clear-State
  Put '000124.log' ([Text.Encoding]::ASCII.GetBytes('newestVersionXXXX"99"'))
  Yes 'printable filler between the key and a number is not a length byte' ((Get-CollectionNewest) -eq 0)

  # ---- the installed revision (Have), read from state under the new naming --
  # Vortex stopped naming the mod folder for the collection (it is
  # vortex_collection_<opaque id>_ now), so the installed revision NUMBER is
  # read from state.v2, tied to the collection by its slug. These point the
  # shipped Get-CollectionRevision at the cases built above through APPDATA,
  # so what is under test is the shipped reader, not a copy of it.
  $ombo = 'https://www.nexusmods.com/games/skyrimspecialedition/collections/ombo2a'

  $env:APPDATA = Join-Path $cases 'installed'
  Yes 'the installed revision is read from state under vortex_collection_* naming' ((Get-CollectionRevision 'ombo2a') -eq 5)

  # Two collections installed at once, ombo2a on main and 7essxf on dev: each
  # answers about its own, tied by the mod id, never the other's number.
  $env:APPDATA = Join-Path $cases 'installed-two'
  Yes 'ombo2a reads its own 5, not the other collection''s 12' ((Get-CollectionRevision 'ombo2a') -eq 5)
  Yes 'and 7essxf reads its own 12' ((Get-CollectionRevision '7essxf') -eq 12)

  # The legacy folder is still read when there is no state to read: a machine
  # that only ever had the old collection_<slug>_<rev>_* folders.
  $env:APPDATA = $root
  Clear-State
  $legacyMods = Join-Path $root 'Vortex\skyrimse\mods'
  $null = New-Item -ItemType Directory -Force -Path (Join-Path $legacyMods 'collection_ombo2a_4_2026-09-20T10-00-00Z')
  $null = New-Item -ItemType Directory -Force -Path (Join-Path $legacyMods 'collection_ombo2a_5_2026-09-22T22-26-11Z')
  Yes 'with no state, the legacy folder name is still read, newest wins' ((Get-CollectionRevision 'ombo2a') -eq 5)
  Remove-Item -LiteralPath $legacyMods -Recurse -Force -EA SilentlyContinue

  # Have and Newest together, the two numbers Deploy-Gamemode stands on: with
  # the collection installed at 5 and Vortex knowing 5 is newest, the state is
  # Known and not Behind, which is a deploy that no longer needs -IgnoreRevision.
  $env:APPDATA = Join-Path $cases 'ready'
  $csReady = Get-CollectionState $ombo
  Yes 'Get-CollectionState reads Have from state now' ($csReady.Have -eq 5)
  Yes 'and Known is true, so the deploy gate reads a real revision without -IgnoreRevision' ($csReady.Known)
  Yes 'and Behind is false when Have matches Newest' (-not $csReady.Behind)

  # ---- Known without newestVersion (draft / first revision) ----------------
  $env:APPDATA = Join-Path $cases 'draft'
  $csDraft = Get-CollectionState 'https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf'
  Yes 'without newestVersion, Have still reads 1 from state' ($csDraft.Have -eq 1)
  Yes 'and Newest is 1 from collections revisions / installed floor' ($csDraft.Newest -eq 1)
  Yes 'so Known is true on a current draft with no newestVersion key' ($csDraft.Known)


  # ---- authoring shape: newestFileId, no collectionSlug (live ship PC) ------
  $env:APPDATA = Join-Path $cases 'authoring'
  $csAuthor = Get-CollectionState 'https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf'
  Yes 'without collectionSlug, Have still reads 1 via newestFileId + revisions table' ($csAuthor.Have -eq 1)
  Yes 'and Newest is 1 so Known is true on the authoring shape' ($csAuthor.Known)
  Yes 'ombo2a stays 0 when only 7essxf is wired through newestFileId' ((Get-CollectionRevision 'ombo2a') -eq 0)
  $modsAuthor = @((Get-CollectionModIds '7essxf') | ForEach-Object { $_ })
  Yes 'ModIds finds vortex_collection_* via newestFileId when collectionSlug is absent' `
    ($modsAuthor -contains 'vortex_collection_ZRT7NjhN_')
  $modsDirA = Join-Path $env:APPDATA 'Vortex\skyrimse\mods'
  $opaqueA = Join-Path $modsDirA 'vortex_collection_ZRT7NjhN_'
  $null = New-Item -ItemType Directory -Force -Path $opaqueA
  $foundA = Get-CollectionInstalledFolder '7essxf'
  Yes 'InstalledFolder maps via newestFileId when collectionSlug is absent' `
    ($null -ne $foundA -and ([IO.Path]::GetFullPath($foundA.FullName) -eq [IO.Path]::GetFullPath($opaqueA)))
  Remove-Item -LiteralPath $modsDirA -Recurse -Force -EA SilentlyContinue

  # ---- InstalledFolder via state, with or without collection.json ----------
  $env:APPDATA = Join-Path $cases 'slug-only'
  $modsDir = Join-Path $env:APPDATA 'Vortex\skyrimse\mods'
  $opaque = Join-Path $modsDir 'vortex_collection_ZRT7NjhN_'
  $null = New-Item -ItemType Directory -Force -Path $opaque
  $found = Get-CollectionInstalledFolder '7essxf'
  Yes 'InstalledFolder maps slug to vortex_collection_* via state without collection.json' `
    ($null -ne $found -and ([IO.Path]::GetFullPath($found.FullName) -eq [IO.Path]::GetFullPath($opaque)))
  Set-Content -LiteralPath (Join-Path $opaque 'collection.json') -Value '{}' -Encoding ASCII
  $found2 = Get-CollectionInstalledFolder '7essxf'
  Yes 'InstalledFolder still returns the state-mapped folder when collection.json is present' `
    ($null -ne $found2 -and ([IO.Path]::GetFullPath($found2.FullName) -eq [IO.Path]::GetFullPath($opaque)))
  Remove-Item -LiteralPath $modsDir -Recurse -Force -EA SilentlyContinue

  # ---- Thornswood profile lock helper --------------------------------------
  $env:APPDATA = $root
  Clear-State
  $profLog = [Text.Encoding]::ASCII.GetBytes(
    '{"type":"mod-enabled","data":{"profileId":"ZRT7NjhN_","profileName":"Thornswood"}}')
  Put '000200.log' $profLog
  $profDir = Join-Path $root 'Vortex\skyrimse\profiles\ZRT7NjhN_'
  $null = New-Item -ItemType Directory -Force -Path $profDir
  Set-Content -LiteralPath (Join-Path $profDir 'plugins.txt') -Value '*Skyrim.esm' -Encoding ASCII
  $got = Get-VortexProfileDir 'Thornswood'
  Yes 'Get-VortexProfileDir finds the Thornswood profile by name in state' `
    ($null -ne $got -and ([IO.Path]::GetFullPath($got) -eq [IO.Path]::GetFullPath($profDir)))
  Remove-Item -LiteralPath (Join-Path $root 'Vortex\skyrimse\profiles') -Recurse -Force -EA SilentlyContinue

  # ---- what the callers see ------------------------------------------------
  Clear-State; Put '000124.log' (Plain 5)
  $st = Get-CollectionState 'https://next.nexusmods.com/skyrimspecialedition/collections/7essxf'
  Yes 'Get-CollectionState carries the newest through' ($st.Newest -eq 5)
  Yes 'and says it knew both numbers when it did' `
    (($st.Have -gt 0 -and $st.Known) -or (-not $st.Have -and -not $st.Known))

  Clear-State
  $blind = Get-CollectionState 'https://next.nexusmods.com/skyrimspecialedition/collections/7essxf'
  Yes 'with nothing readable, Known is false' (-not $blind.Known)
  Yes 'and Behind is false too, so the bool alone cannot tell them apart' (-not $blind.Behind)
}
finally {
  $env:APPDATA = $realAppData
  Remove-Item -LiteralPath $root -Recurse -Force -EA SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $pass, $fail) -ForegroundColor $(if ($fail) { 'Red' } else { 'Green' })
if ($fail) { exit 1 }
