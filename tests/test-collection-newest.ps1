<#
  test-collection-newest.ps1

      pwsh -NoProfile -File .\tests\test-collection-newest.ps1

  Which revision of the collection Vortex knows is out, read out of its own
  state.v2. This is the number the deploy gate stands on, and on 22 September
  it silently went blind.

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

  These build a state.v2 of their own out of those exact bytes and point the
  real function at it through APPDATA, so what is under test is the shipped
  function rather than a copy of it.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$LoadOrderPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $LoadOrderPath) { $LoadOrderPath = Join-Path $Here '..\scripts\mods\LoadOrder.ps1' }
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
function Put([string]$name, [byte[]]$bytes) {
  [IO.File]::WriteAllBytes((Join-Path $state $name), $bytes)
}
function Clear-State { Get-ChildItem $state -File | Remove-Item -Force }

try {
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

  # ---- what the callers see ------------------------------------------------
  Clear-State; Put '000124.log' (Plain 5)
  $st = Get-CollectionState 'https://next.nexusmods.com/skyrimspecialedition/collections/ombo2a'
  Yes 'Get-CollectionState carries the newest through' ($st.Newest -eq 5)
  Yes 'and says it knew both numbers when it did' `
    (($st.Have -gt 0 -and $st.Known) -or (-not $st.Have -and -not $st.Known))

  Clear-State
  $blind = Get-CollectionState 'https://next.nexusmods.com/skyrimspecialedition/collections/ombo2a'
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
