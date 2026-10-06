<#
.SYNOPSIS
  Moves the light plugin form ids stored in a copy of a world's change forms from the light order each was stored under to the server's light order, once (#1715).

.DESCRIPTION
  A light plugin's forms have ids 0xFE000000 | (light index << 12) | local
  id, and the light index is the plugin's place among the light plugins the
  game loads. Until the engine loaded light plugins (#1715) nothing fixed
  that order: every machine's Vortex and LOOT gave its own, and the server
  stored whatever id the client sent. Measured on 5 Oct, 2 such ids on live
  and 5 on dev, every one a head part in a character's appearance, and the
  5 on dev were stored under a light order the dev build no longer has
  (docs\LIGHT-ORDER-DRIFT.md). Once the server loads light plugins and
  publishes its light order, every machine follows that order, and an id
  stored under another one names another plugin's form.

  This rewrites each such id to the same plugin and local id under the
  server's light order. It reads:

    -World  a COPY of a world's changeForms folder. Never the server's own:
            a folder under a Thornswood-Server root is refused. The server is
            stopped, its world copied, this run on the copy, the result read,
            and only then is the copy put back, by hand, with the server
            still stopped.
    -Plan   a JSON file saying which light order each record was stored
            under and which light ids were measured in it:
            {"orders": {"<name>": ["plugin", ...]},
             "records": {"<file>": {"order": "<name>", "ids": [id, ...]}}}.
            The orders are the light lists the game wrote to
            thornswood-plugins-light.txt in the session that stored the
            record, and the ids the ones docs\LIGHT-ORDER-DRIFT.md lists.
            Only a listed id is moved, so a second run finds the moved ids
            are not the plan's and moves nothing twice.
    -To     the server's light order: its published manifest.json (the
            "light" list), or a text file of plugin names in order.

  Only the ids in a character's appearance are moved (appearanceDump:
  raceId, headpartIds, headTextureSetId), because those are the only places
  one was found. A light id anywhere else, a record with light ids and no
  order in the plan, an id the plan does not list for its record (moved
  already, or stored after the plan was made), a light index past the end
  of its order, and a plugin the server's order does not have are each
  said, and that record is left as it is.

  DRY RUN BY DEFAULT: it says what it would change and writes nothing.
  -Write changes the records, after copying each one it changes, as it was,
  into -Backup (a new folder beside -World unless named). A file is written
  only when, read back, it is the same record with exactly the planned ids
  changed; every other byte of it is kept.

  Made on 5 Oct 2026 to be run once, by Patrick, after the engine that loads
  light plugins is deployed and before anybody plays on it.
  tests\test-move-light-form-ids.ps1 runs it on copies.

.EXAMPLE
  .\scripts\oneoff\Move-LightFormIds.ps1 -World D:\copy\world\changeForms -Plan .\plan.json -To .\manifest.json
.EXAMPLE
  .\scripts\oneoff\Move-LightFormIds.ps1 -World D:\copy\world\changeForms -Plan .\plan.json -To .\manifest.json -Write
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$World,
    [Parameter(Mandatory = $true)][string]$Plan,
    [Parameter(Mandatory = $true)][string]$To,
    [switch]$Write,
    [string]$Backup
)

$ErrorActionPreference = 'Stop'
function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }

$World = [IO.Path]::GetFullPath($World)
if (-not (Test-Path -LiteralPath $World -PathType Container)) { throw "-World is not a folder: $World" }
if ($World -match '(?i)[\\/]Thornswood-Server(-Dev)?([\\/]|$)') {
    throw "$World is a server's own world. This runs on a copy, never on a server; copy the folder with the server stopped and point -World at the copy."
}

# The ids that are a light plugin's: top byte 0xFE.
$LightLow = 0xFE000000L
$LightHigh = 0xFEFFFFFFL
function Test-LightId($v) {
    if ($null -eq $v) { return $false }
    if (-not ($v -is [int] -or $v -is [long] -or $v -is [decimal] -or $v -is [double])) { return $false }
    # Out of the light range before it is made a decimal: a record can hold
    # the largest float (3.4e+38, a limit that means none), which no decimal
    # holds, and the dev world of 5 Oct has one.
    if ($v -lt $LightLow -or $v -gt $LightHigh) { return $false }
    $d = [decimal]$v
    if ($d -ne [decimal]::Truncate($d)) { return $false }
    return ($d -ge $LightLow -and $d -le $LightHigh)
}

# ---- the plan and the server's light order ----------------------------------
$planDoc = [IO.File]::ReadAllText($Plan) | ConvertFrom-Json
$orders = @{}
foreach ($p in $planDoc.orders.PSObject.Properties) { $orders[$p.Name] = [string[]]@($p.Value | ForEach-Object { "$_".Trim() }) }
$recordOrder = @{}
$recordIds = @{}
foreach ($p in $planDoc.records.PSObject.Properties) {
    $k = $p.Name.ToLowerInvariant()
    $recordOrder[$k] = [string]$p.Value.order
    $recordIds[$k] = @{}
    foreach ($id in @($p.Value.ids)) { if ($null -ne $id) { $recordIds[$k][[string][long][decimal]$id] = $true } }
    if (-not $orders.ContainsKey($recordOrder[$k])) { throw "the plan names order '$($recordOrder[$k])' for $k and has no such order" }
    if ($recordIds[$k].Count -eq 0) { throw "the plan lists no ids for $k" }
}

$toText = [IO.File]::ReadAllText($To)
if ($To -match '\.json$') {
    $toDoc = $toText | ConvertFrom-Json
    if ($null -eq $toDoc -or -not ($toDoc.PSObject.Properties.Name -contains 'light')) { throw "$To is a manifest with no light list, so it is not the order of a server that loads light plugins" }
    $toNames = [string[]]@($toDoc.light | ForEach-Object { "$($_.filename)" } | Where-Object { $_ -match '\.(esp|esm|esl)$' })
} else {
    $toNames = [string[]]@($toText -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
}
if ($toNames.Count -eq 0) { throw "$To names no light plugin, so there is no server light order to move ids to" }
$toIndex = @{}
for ($i = 0; $i -lt $toNames.Count; $i++) { if (-not $toIndex.ContainsKey($toNames[$i].ToLowerInvariant())) { $toIndex[$toNames[$i].ToLowerInvariant()] = $i } }

# ---- every light id in a record, with where it is ---------------------------
function Get-LightIds($node, [string]$at) {
    $found = New-Object Collections.Generic.List[object]
    if ($null -eq $node) { return ,$found }
    if ($node -is [Management.Automation.PSCustomObject]) {
        foreach ($p in $node.PSObject.Properties) { foreach ($f in (Get-LightIds $p.Value ($at + '.' + $p.Name))) { $found.Add($f) } }
    } elseif ($node -is [Collections.IList] -and -not ($node -is [string])) {
        for ($i = 0; $i -lt $node.Count; $i++) { foreach ($f in (Get-LightIds $node[$i] ($at + '[' + $i + ']'))) { $found.Add($f) } }
    } elseif (Test-LightId $node) {
        $found.Add([pscustomobject]@{ Path = $at; Id = [long][decimal]$node })
    }
    return ,$found
}
$Movable = '^\.appearanceDump\.(raceId|headTextureSetId|headpartIds\[\d+\])$'

# The text of the value at a top level key: from the colon after "key" to the
# end of the value, strings skipped, so a rewrite touches nothing outside it.
function Get-ValueSpan([string]$text, [string]$key) {
    $m = [regex]::Match($text, '"' + [regex]::Escape($key) + '"\s*:\s*')
    if (-not $m.Success) { return $null }
    $start = $m.Index + $m.Length
    $depth = 0; $inStr = $false
    for ($i = $start; $i -lt $text.Length; $i++) {
        $c = $text[$i]
        if ($inStr) { if ($c -eq '\') { $i++ } elseif ($c -eq '"') { $inStr = $false }; continue }
        if ($c -eq '"') { $inStr = $true }
        elseif ($c -eq '{' -or $c -eq '[') { $depth++ }
        elseif ($c -eq '}' -or $c -eq ']') { $depth--; if ($depth -eq 0) { return @($start, $i + 1) } }
        elseif ($depth -eq 0 -and $c -eq ',') { return @($start, $i) }
    }
    return $null
}

# Every number token in a piece of JSON text that is a key of $map, outside
# strings, replaced by its value, in one pass, so an id moved onto another
# id's old number is not moved twice. A name that happens to hold the same
# digits is text, not an id, and is left as it is.
function Set-NumberToken([string]$text, [hashtable]$map) {
    $sb = New-Object Text.StringBuilder
    $i = 0; $inStr = $false
    while ($i -lt $text.Length) {
        $c = $text[$i]
        if ($inStr) {
            [void]$sb.Append($c)
            if ($c -eq '\' -and $i + 1 -lt $text.Length) { [void]$sb.Append($text[$i + 1]); $i += 2; continue }
            if ($c -eq '"') { $inStr = $false }
            $i++; continue
        }
        if ($c -eq '"') { $inStr = $true; [void]$sb.Append($c); $i++; continue }
        if ($c -eq '-' -or [char]::IsDigit($c)) {
            $j = $i + 1
            while ($j -lt $text.Length -and '0123456789.eE+-'.IndexOf($text[$j]) -ge 0) { $j++ }
            $tok = $text.Substring($i, $j - $i)
            [void]$sb.Append($(if ($map.ContainsKey($tok)) { $map[$tok] } else { $tok }))
            $i = $j; continue
        }
        [void]$sb.Append($c); $i++
    }
    return $sb.ToString()
}

function Compare-Node($a, $b, [hashtable]$changed, [string]$at) {
    if ($changed.ContainsKey($at)) { return ([long][decimal]$b -eq $changed[$at]) }
    if ($null -eq $a -or $null -eq $b) { return ($null -eq $a -and $null -eq $b) }
    if ($a -is [Management.Automation.PSCustomObject]) {
        if (-not ($b -is [Management.Automation.PSCustomObject])) { return $false }
        $an = @($a.PSObject.Properties.Name); $bn = @($b.PSObject.Properties.Name)
        if (($an -join '|') -ne ($bn -join '|')) { return $false }
        foreach ($n in $an) { if (-not (Compare-Node $a.$n $b.$n $changed ($at + '.' + $n))) { return $false } }
        return $true
    }
    if ($a -is [Collections.IList] -and -not ($a -is [string])) {
        if (-not ($b -is [Collections.IList]) -or $a.Count -ne $b.Count) { return $false }
        for ($i = 0; $i -lt $a.Count; $i++) { if (-not (Compare-Node $a[$i] $b[$i] $changed ($at + '[' + $i + ']'))) { return $false } }
        return $true
    }
    return ([string]$a -ceq [string]$b)
}

# ---- each record ------------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $Backup) { $Backup = Join-Path (Split-Path -Parent $World) ('light-form-ids-backup-' + $stamp) }
$counts = [ordered]@{ records = 0; withLightIds = 0; ids = 0; moved = 0; same = 0; leftAlone = 0; written = 0 }
Say ("{0} {1}" -f $(if ($Write) { 'Moving light form ids in' } else { 'Dry run, nothing is written. Light form ids in' }), $World) 'Cyan'
Say ("  the server's light order: {0} light plugins, from {1}" -f $toNames.Count, $To) 'DarkGray'
foreach ($f in @(Get-ChildItem -LiteralPath $World -Filter '*.json' -File | Sort-Object Name)) {
    $counts.records++
    $raw = [IO.File]::ReadAllBytes($f.FullName)
    $bom = $raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF
    $text = (New-Object Text.UTF8Encoding($false)).GetString($raw, $(if ($bom) { 3 } else { 0 }), $raw.Length - $(if ($bom) { 3 } else { 0 }))
    try { $doc = $text | ConvertFrom-Json } catch { Say ("  {0}: does not read as JSON, left alone ({1})" -f $f.Name, $_.Exception.Message) 'Yellow'; $counts.leftAlone++; continue }
    $ids = Get-LightIds $doc ''
    if ($ids.Count -eq 0) { continue }
    $counts.withLightIds++
    $counts.ids += $ids.Count
    $why = @()
    $odd = @($ids | Where-Object { $_.Path -notmatch $Movable })
    foreach ($o in $odd) { $why += ("a light id at {0} (0x{1:X8}), which this does not move" -f $o.Path, $o.Id) }
    $orderName = $recordOrder[$f.Name.ToLowerInvariant()]
    if (-not $orderName) { $why += 'no light order for it in the plan' }
    $moveList = New-Object Collections.Generic.List[object]
    if ($orderName) {
        $from = $orders[$orderName]
        foreach ($x in @($ids | Where-Object { $_.Path -match $Movable })) {
            if (-not $recordIds[$f.Name.ToLowerInvariant()].ContainsKey([string]$x.Id)) {
                $why += ("{0} 0x{1:X8} is not an id the plan lists for this record: moved already, or stored after the plan was made" -f $x.Path, $x.Id); continue
            }
            $idx = [int](($x.Id -shr 12) -band 0xFFF)
            $local = [long]($x.Id -band 0xFFF)
            if ($idx -ge $from.Count) { $why += ("{0} 0x{1:X8}: light index 0x{2:X3} is past the end of order '{3}' ({4} plugins)" -f $x.Path, $x.Id, $idx, $orderName, $from.Count); continue }
            $plugin = $from[$idx]
            if (-not $toIndex.ContainsKey($plugin.ToLowerInvariant())) { $why += ("{0} 0x{1:X8}: {2} is not in the server's light order" -f $x.Path, $x.Id, $plugin); continue }
            $new = $LightLow -bor ([long]$toIndex[$plugin.ToLowerInvariant()] -shl 12) -bor $local
            $moveList.Add([pscustomobject]@{ Path = $x.Path; Old = $x.Id; New = $new; Plugin = $plugin; Local = $local })
        }
    }
    Say ("  {0}{1}" -f $f.Name, $(if ($null -ne $doc.profileId) { ', profile ' + $doc.profileId } else { '' })) 'White'
    foreach ($p in $moveList) {
        $what = if ($p.Old -eq $p.New) { 'already the server''s' } else { 'moves to 0x{0:X8}' -f $p.New }
        Say ("    {0,-32} 0x{1:X8}  {2} {3:X3}, {4}" -f $p.Path, $p.Old, $p.Plugin, $p.Local, $what) $(if ($p.Old -eq $p.New) { 'DarkGray' } else { 'Gray' })
    }
    if ($why.Count) {
        foreach ($w in $why) { Say ("    left alone: {0}" -f $w) 'Yellow' }
        $counts.leftAlone++
        continue
    }
    $moves = @($moveList | Where-Object { $_.Old -ne $_.New })
    $counts.same += ($moveList.Count - $moves.Count)
    $counts.moved += $moves.Count
    if (-not $moves.Count -or -not $Write) { continue }

    # The rewrite: each id replaced as a whole number inside appearanceDump's
    # own text, then the file read back and held to the plan.
    $span = Get-ValueSpan $text 'appearanceDump'
    if ($null -eq $span) { Say '    left alone: appearanceDump could not be found in the text' 'Yellow'; $counts.leftAlone++; continue }
    $part = $text.Substring($span[0], $span[1] - $span[0])
    $map = @{}
    foreach ($p in $moves) { $map[[string]$p.Old] = [string]$p.New }
    $part = Set-NumberToken $part $map
    $newText = $text.Substring(0, $span[0]) + $part + $text.Substring($span[1])
    $changed = @{}
    foreach ($p in $moveList) { $changed[$p.Path] = $p.New }
    $back = $newText | ConvertFrom-Json
    if (-not (Compare-Node $doc $back $changed '')) { Say '    left alone: the rewritten record did not read back as the same record with only these ids changed' 'Yellow'; $counts.leftAlone++; continue }
    New-Item -ItemType Directory -Force -Path $Backup | Out-Null
    $saved = Join-Path $Backup $f.Name
    if (Test-Path -LiteralPath $saved) { throw "$saved is already there; a backup is never written over" }
    [IO.File]::WriteAllBytes($saved, $raw)
    $body = New-Object Collections.Generic.List[byte]
    if ($bom) { $body.AddRange([byte[]](0xEF, 0xBB, 0xBF)) }
    $body.AddRange((New-Object Text.UTF8Encoding($false)).GetBytes($newText))
    [IO.File]::WriteAllBytes($f.FullName, $body.ToArray())
    $counts.written++
    Say ("    written, the record as it was is {0}" -f $saved) 'Green'
}
Say ''
Say ("{0} records, {1} with light ids, {2} light ids: {3} {4}, {5} already the server's; {6} record(s) left alone{7}" -f `
    $counts.records, $counts.withLightIds, $counts.ids, $counts.moved, $(if ($Write) { 'moved' } else { 'would move' }), $counts.same, $counts.leftAlone,
    $(if ($Write) { ', ' + $counts.written + ' written' } else { '' })) 'Cyan'
if ($counts.leftAlone) { exit 2 }
