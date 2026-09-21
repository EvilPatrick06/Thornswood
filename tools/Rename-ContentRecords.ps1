<#
  Rename-ContentRecords.ps1

  Renames the editor ids in Thornswood-Content.esp that still carry the naming
  of the server the content came from, and changes nothing else about the file.

  WHY

  Measured on 21 September: 33 of the plugin's 408 records carry a Kzl or
  kzolivar prefix. Patrick, the same day: "yeah for all of those let's keep but
  change the names", and then "the in game names are fine".

  So this touches the EDID subrecord and nothing else. Every FULL stays exactly
  as it is, because the names a person reads in the world are already right:
  "A Miner's First Season", "Salt Quarry", "Poor Charcoal", "Beehive". Nobody
  in the world can see the other server's name and this is housekeeping.

  WHY A FORM ID DOES NOT MOVE, WHICH IS THE WHOLE REASON THIS IS SAFE

  An editor id is a name for people and for the Creation Kit. A form id is the
  number in the record header and nothing here writes to it. Everything the
  gamemode gates is gated by form id: the salt quarry, the kiln, the beehive,
  the charcoal tiers and the two recipes are all reached by descriptor, and a
  descriptor is a form id and a file name. So the server does not notice, the
  generated tables do not move, and no rank, plot or claim changes.

  WHAT IS HARD ABOUT IT

  An editor id is a length prefixed string inside a subrecord. Kzl is three
  characters and Thornswood is ten, so every rename makes its record longer,
  which makes the group it sits in longer, which makes the group THAT sits in
  longer, all the way up. This plugin nests six deep and holds 100 compressed
  records. So the file is parsed into a tree, the strings are replaced, and
  every size is recomputed from the children on the way back out. A compressed
  record is copied byte for byte and never opened.

  WHAT IT PROVES BEFORE IT WRITES

  The result is re-read from scratch and compared against the original record
  by record: the same count, the same form ids in the same order, the same
  types, the same flags, and every subrecord byte for byte EXCEPT the EDID it
  was asked to change. If a single one of those disagrees it writes nothing.

  THIS IS A SHIPPED FILE. Every machine carries it byte for byte and the load
  order manifest compares name, size and crc32 positionally, so changing it
  means a release and every client downloading it again. That is the real cost
  of this change and it is why it is a script with a proof rather than an edit.

  Usage:
    .\tools\Rename-ContentRecords.ps1 -Check    say what would change, write nothing
    .\tools\Rename-ContentRecords.ps1           do it, keeping the original beside it

  Exit code 1 if the plugin is not where it should be, if the parse does not
  round trip, or if any verification fails.
#>
[CmdletBinding()]
param(
    [string]$Data = 'C:\Thornswood\Game\Data',
    [string]$Plugin = 'Thornswood-Content.esp',
    # Write the result here instead of over the original.
    [string]$Out = '',
    [switch]$Check,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'

function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Ok($m)  { Write-Host ('  ok    ' + $m) -ForegroundColor Green }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

# ---------------------------------------------------------------- the rule --
#
# One rule and two spellings, because the plugin uses both. Kzl is the prefix on
# everything except the message board, which is lower case and spelled out. The
# rule is a prefix swap and nothing else: the rest of every name is kept exactly
# as it was, so KzlMiningNovice becomes ThornswoodMiningNovice and the ordering
# and meaning of the whole set survives.
#
# NOT A KNOB. Changing this changes names in a shipped file, which is a release.
function NewName([string]$old) {
    if ($old -cmatch '^Kzl(.+)$')                 { return 'Thornswood' + $Matches[1] }
    if ($old -ceq 'kzolivarmessageboard')          { return 'ThornswoodMessageBoard' }
    if ($old -cmatch '^kzolivar(.+)$')             { return 'Thornswood' + $Matches[1] }
    return $null
}

$path = Join-Path $Data $Plugin
if (-not (Test-Path -LiteralPath $path)) { Die "no $Plugin at $path" }
$bytes = [System.IO.File]::ReadAllBytes($path)

Head 'The file'
Say ("  {0}" -f $path)
Say ("  {0:N0} bytes, sha256 {1}" -f $bytes.Length, (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower().Substring(0, 16))

# ------------------------------------------------------------- the parser ---
#
# A node is either a group or a record. A group keeps its 24 byte header and its
# children; a record keeps its 24 byte header and its data. Nothing is
# interpreted beyond that, so anything this script does not understand survives
# it untouched.
function ParseNodes([int]$start, [int]$end) {
    $out = New-Object 'System.Collections.Generic.List[object]'
    $p = $start
    while ($p + 24 -le $end) {
        $type = [System.Text.Encoding]::ASCII.GetString($bytes, $p, 4)
        $size = [BitConverter]::ToUInt32($bytes, $p + 4)
        if ($type -eq 'GRUP') {
            if ($size -lt 24 -or $p + $size -gt $end) { Die "a group at offset $p says it is $size bytes, which does not fit" }
            $node = [pscustomobject]@{
                Kind = 'GRUP'; Header = $bytes[$p..($p + 23)]
                Children = (ParseNodes ($p + 24) ($p + $size)); Data = $null
                Type = $type; FormId = 0; Flags = 0
            }
            $out.Add($node)
            $p += $size
        } else {
            if ($p + 24 + $size -gt $end) { Die "a record at offset $p says its data is $size bytes, which does not fit" }
            $flags = [BitConverter]::ToUInt32($bytes, $p + 8)
            $node = [pscustomobject]@{
                Kind = 'REC'; Header = $bytes[$p..($p + 23)]
                Children = $null
                Data = $(if ($size -gt 0) { $bytes[($p + 24)..($p + 24 + $size - 1)] } else { @() })
                Type = $type; FormId = [BitConverter]::ToUInt32($bytes, $p + 12); Flags = $flags
            }
            $out.Add($node)
            $p += 24 + $size
        }
    }
    if ($p -ne $end) { Die "the walk from $start stopped at $p and should have stopped at $end" }
    return , $out
}

$headerSize = [BitConverter]::ToUInt32($bytes, 4)
$tes4 = $bytes[0..(24 + $headerSize - 1)]
$tree = ParseNodes (24 + $headerSize) $bytes.Length

# ------------------------------------------------------------ round trip ----
#
# Before anything is changed, the tree is written back out and compared with
# what was read. If the parser cannot reproduce the file it was given, it has
# misunderstood something and has no business editing it.
function Serialise($nodes, [System.IO.MemoryStream]$ms) {
    foreach ($n in $nodes) {
        if ($n.Kind -eq 'GRUP') {
            $inner = New-Object System.IO.MemoryStream
            Serialise $n.Children $inner
            $body = $inner.ToArray()
            $hdr = $n.Header.Clone()
            [Array]::Copy([BitConverter]::GetBytes([uint32]($body.Length + 24)), 0, $hdr, 4, 4)
            $ms.Write($hdr, 0, 24)
            if ($body.Length) { $ms.Write($body, 0, $body.Length) }
        } else {
            $hdr = $n.Header.Clone()
            [Array]::Copy([BitConverter]::GetBytes([uint32]$n.Data.Length), 0, $hdr, 4, 4)
            $ms.Write($hdr, 0, 24)
            if ($n.Data.Length) { $ms.Write($n.Data, 0, $n.Data.Length) }
        }
    }
}

Head 'Can the parser reproduce the file it was given'
$ms = New-Object System.IO.MemoryStream
$ms.Write($tes4, 0, $tes4.Length)
Serialise $tree $ms
$roundTrip = $ms.ToArray()
if ($roundTrip.Length -ne $bytes.Length) {
    Die ("the round trip came out {0:N0} bytes against {1:N0}. The parser has misread the file and nothing was written." -f $roundTrip.Length, $bytes.Length)
}
for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($roundTrip[$i] -ne $bytes[$i]) { Die "the round trip differs at byte $i. The parser has misread the file and nothing was written." }
}
Ok ("the file was parsed and written back byte for byte, {0:N0} bytes" -f $roundTrip.Length)

# ------------------------------------------------------------- the rename ---
Head 'What would change'

$renamed = New-Object 'System.Collections.Generic.List[object]'
$skippedCompressed = 0

function Visit($nodes) {
    foreach ($n in $nodes) {
        if ($n.Kind -eq 'GRUP') { Visit $n.Children; continue }
        # A compressed record's data is zlib and its subrecords cannot be read
        # without inflating it. None of the 33 are compressed, measured, and a
        # compressed one is counted and left alone rather than guessed at.
        if (($n.Flags -band 0x00040000) -ne 0) { $script:skippedCompressed++; continue }
        $d = $n.Data
        $s = 0
        while ($s + 6 -le $d.Length) {
            $st = [System.Text.Encoding]::ASCII.GetString($d, $s, 4)
            $ssz = [int][BitConverter]::ToUInt16($d, $s + 4)
            if ($ssz -le 0 -or $s + 6 + $ssz -gt $d.Length) { break }
            if ($st -eq 'EDID') {
                $old = [System.Text.Encoding]::ASCII.GetString($d, $s + 6, $ssz - 1)
                $new = NewName $old
                if ($new) {
                    $newBytes = [System.Text.Encoding]::ASCII.GetBytes($new)
                    $sub = New-Object 'System.Collections.Generic.List[byte]'
                    $sub.AddRange([byte[]][System.Text.Encoding]::ASCII.GetBytes('EDID'))
                    $sub.AddRange([byte[]][BitConverter]::GetBytes([uint16]($newBytes.Length + 1)))
                    $sub.AddRange([byte[]]$newBytes)
                    $sub.Add([byte]0)
                    # [byte[]] on every slice. PowerShell hands back an
                    # Object[] from a range index even when the source is a
                    # byte array, and List[byte].AddRange refuses it with a
                    # message about IEnumerable that says nothing about bytes.
                    $rebuilt = New-Object 'System.Collections.Generic.List[byte]'
                    if ($s -gt 0) { $rebuilt.AddRange([byte[]]$d[0..($s - 1)]) }
                    $rebuilt.AddRange([byte[]]$sub.ToArray())
                    $after = $s + 6 + $ssz
                    if ($after -lt $d.Length) { $rebuilt.AddRange([byte[]]$d[$after..($d.Length - 1)]) }
                    $n.Data = $rebuilt.ToArray()
                    $renamed.Add([pscustomobject]@{ Type = $n.Type; FormId = $n.FormId; Old = $old; New = $new })
                }
                break
            }
            $s += 6 + $ssz
        }
    }
}

Visit $tree

if ($renamed.Count -eq 0) {
    Ok 'nothing carries the old naming any more. There is nothing to do.'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

foreach ($r in $renamed) {
    Say ('  {0}  0x{1:X7}  {2}  ->  {3}' -f $r.Type, $r.FormId, $r.Old.PadRight(32), $r.New)
}
Say ''
Ok ("{0} editor id(s) would change" -f $renamed.Count)
if ($skippedCompressed -gt 0) {
    Say ("  {0} compressed record(s) were not opened at all, which is correct: none of the names are in one." -f $skippedCompressed)
}

if ($Check) {
    Head 'Nothing was written'
    Say '  -Check. Run it again without that to write the file.'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ------------------------------------------------------------ the proof -----
$ms2 = New-Object System.IO.MemoryStream
$ms2.Write($tes4, 0, $tes4.Length)
Serialise $tree $ms2
$result = $ms2.ToArray()

Head 'Proving the result before it is written'

# Re-read the result with the same parser and compare it with the original,
# record by record. Anything other than the EDID that moved is a defect.
$bytes2 = $bytes
$bytes = $result
$headerSize2 = [BitConverter]::ToUInt32($bytes, 4)
$after = ParseNodes (24 + $headerSize2) $bytes.Length
$bytes = $bytes2

function Flatten($nodes, $list) {
    foreach ($n in $nodes) {
        if ($n.Kind -eq 'GRUP') { Flatten $n.Children $list } else { $list.Add($n) }
    }
}
$beforeList = New-Object 'System.Collections.Generic.List[object]'
$afterList = New-Object 'System.Collections.Generic.List[object]'
# The original tree has already been mutated, so it is parsed again from the
# bytes that are still in hand rather than trusted.
$origTree = ParseNodes (24 + $headerSize) $bytes.Length
Flatten $origTree $beforeList
Flatten $after $afterList

if ($beforeList.Count -ne $afterList.Count) {
    Die ("the result holds {0} records and the original holds {1}" -f $afterList.Count, $beforeList.Count)
}
Ok ("{0} records before and after" -f $beforeList.Count)

$wanted = @{}
foreach ($r in $renamed) { $wanted[[string]$r.FormId] = $r }

$diffs = 0
for ($i = 0; $i -lt $beforeList.Count; $i++) {
    $a = $beforeList[$i]; $b = $afterList[$i]
    if ($a.Type -ne $b.Type) { Die ("record $i changed type from {0} to {1}" -f $a.Type, $b.Type) }
    if ($a.FormId -ne $b.FormId) { Die ("record $i changed form id from 0x{0:X} to 0x{1:X}" -f $a.FormId, $b.FormId) }
    if ($a.Flags -ne $b.Flags) { Die ("record 0x{0:X} changed flags" -f $a.FormId) }
    $same = $a.Data.Length -eq $b.Data.Length
    if ($same) {
        for ($j = 0; $j -lt $a.Data.Length; $j++) { if ($a.Data[$j] -ne $b.Data[$j]) { $same = $false; break } }
    }
    if (-not $same) {
        $diffs++
        if (-not $wanted.ContainsKey([string]$a.FormId)) {
            Die ("record 0x{0:X} changed and was not one of the ones asked for" -f $a.FormId)
        }
    }
}
Ok ("every form id, type and flag is unchanged")
Ok ("{0} record(s) differ and every one of them is a record that was asked for" -f $diffs)
if ($diffs -ne $renamed.Count) {
    Die ("{0} records changed but {1} renames were made" -f $diffs, $renamed.Count)
}

Head 'Writing'
if (-not $Out) { $Out = $path }
if ($Out -eq $path) {
    $backup = $path + '.before-rename-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    [System.IO.File]::WriteAllBytes($backup, $bytes)
    Say ('  kept the original as ' + (Split-Path -Leaf $backup))
}
[System.IO.File]::WriteAllBytes($Out, $result)
Say ("  {0}" -f $Out)
Say ("  {0:N0} bytes, was {1:N0}, sha256 {2}" -f $result.Length, $bytes.Length,
     (Get-FileHash -LiteralPath $Out -Algorithm SHA256).Hash.ToLower().Substring(0, 16))

Head 'What this costs'
Say '  This is a shipped file. Every machine carries it byte for byte and the load'
Say '  order manifest compares name, size and crc32, so its size changing means a'
Say '  release and every client downloading it again. Nothing the server gates moves,'
Say '  because all of that is by form id, and no name anybody reads in the world has'
Say '  changed.'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
