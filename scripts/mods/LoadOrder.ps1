<#
  LoadOrder.ps1

  The load order as the game counts it, and how to put a plugin list into the
  server's order. Dot-sourced by Publish-Update.ps1, so the reference plugin
  list that goes into a pack ships in the order the server actually runs.

  The same rule as launcher\app\LoadOrder.cs in the launcher, function for
  function, and the two are held to identical output by a test. Change one,
  change the other.

  The game hands a normal index to the five masters, then to every plugin
  Skyrim.ccc names that is in Data, then to every enabled entry of plugins.txt
  that is in Data. Light plugins (an .esl, or the ESL flag in the header) get
  no normal index and are skipped throughout. The client compares that list
  with the server's manifest position by position, and one name out of place
  is LOAD ORDER ERROR for the session.
#>

$script:LoadOrderMasters = 'Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm'

<#
  Which revision of the collection this machine has installed, or 0.

  The same rule as Checks.CollectionRevision in the launcher, and it is here
  because the SHIPPING machine's answer is the one that goes in the feed: the
  server's load order and the reference plugin list are both derived from this
  machine's Vortex deployment, so the revision it is on is the revision the
  release agrees with.

  Found on 22 September, and this is why it exists: this machine was on
  revision 2 while the collection on Nexus was on 4. Nothing said so, because
  the only test was whether one named file existed and that file was not in
  the collection at all. Two revisions of drift, on the machine that builds
  the server.

  WHERE THE NUMBER COMES FROM, and why this was rewritten on 27 September.
  The first version read the revision out of the name Vortex gave the mod
  folder:

      %APPDATA%\Vortex\skyrimse\mods\collection_ombo2a_2_2026-09-15T21-08-00Z
                                                slug  ^ revision

  Current Vortex does not name the folder that way any more. It names it for
  the mod id it made up, with no slug and no number in it at all:

      %APPDATA%\Vortex\skyrimse\mods\vortex_collection_ZRT7NjhN_

  So the folder name stopped being able to answer the question, Have went to
  0 on every up to date machine, Get-CollectionState.Known went false, and
  Deploy-Gamemode's revision gate refused every deploy unless -IgnoreRevision.

  The honest source is Vortex's own state, not the folder name. When Vortex
  installs a collection it records, against the mod, the slug it was installed
  from and the revision NUMBER it is on. That is independent of what the folder
  is called, so it answers for both eras. It is read the same way
  Get-CollectionNewest reads state.v2, as text rather than by opening the
  database, because this only needs a number and must never be the reason a
  deploy fails. The old folder-name parse stays as a fallback for a machine
  that only has the legacy folders and no readable state.
#>
function Get-CollectionRevision([string]$Slug) {
    if (-not $Slug) { return 0 }
    $fromState = Get-CollectionRevisionFromState $Slug
    if ($fromState -gt 0) { return $fromState }
    return Get-CollectionRevisionFromFolder $Slug
}

<#
  The installed revision as Vortex records it in state.v2, or 0.

  Vortex keeps the redux state flattened into LevelDB keys joined by ###, the
  same shape Get-CollectionNewest reads. For an installed collection the two
  keys that matter are, under the mod's own id:

      persistent###mods###skyrimse###<modId>###attributes###collectionSlug -> "ombo2a"
      persistent###mods###skyrimse###<modId>###attributes###revisionNumber -> 5

  LevelDB writes the key, then a length byte (a control character), then that
  many bytes of the value's JSON, so a string value is "ombo2a" and a number
  value is a bare 5. The slug and the number are separate keys, tied together
  only by the <modId> that both carry, so this reads both, matches the slug
  to its mod id, and takes the highest revision recorded against a mod id
  whose slug is the one asked for. That last part matters: a machine can have
  two collections installed at once (ombo2a on main, 7essxf on dev), and the
  revision numbers must not be mixed up between them.

  The length byte is [\x00-\x1F], a bounded class rather than a wildcard, for
  the reason Get-CollectionNewest gives: a wildcard would step over a quote
  and read a number out of a neighbouring key.
#>
function Get-CollectionRevisionFromState([string]$Slug) {
    if (-not $Slug) { return 0 }
    $st = Join-Path $env:APPDATA 'Vortex\state.v2'
    if (-not (Test-Path -LiteralPath $st)) { return 0 }
    $slugRe = 'mods###skyrimse###([^#]+)###attributes###collectionSlug[\x00-\x1F]{1,4}"' + [regex]::Escape($Slug) + '"'
    $revRe = 'mods###skyrimse###([^#]+)###attributes###revisionNumber[\x00-\x1F]{1,4}(\d+)'
    $mine = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $rev = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    foreach ($f in (Get-ChildItem -LiteralPath $st -File -EA SilentlyContinue)) {
        try {
            $txt = [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($f.FullName))
            foreach ($m in [regex]::Matches($txt, $slugRe)) { [void]$mine.Add($m.Groups[1].Value) }
            foreach ($m in [regex]::Matches($txt, $revRe)) {
                $id = $m.Groups[1].Value
                $n = 0
                if ([int]::TryParse($m.Groups[2].Value, [ref]$n)) {
                    if (-not $rev.ContainsKey($id) -or $n -gt $rev[$id]) { $rev[$id] = $n }
                }
            }
        } catch { }
    }
    $best = 0
    foreach ($id in $mine) { if ($rev.ContainsKey($id) -and $rev[$id] -gt $best) { $best = $rev[$id] } }
    return $best
}

<#
  The legacy fallback: the revision out of the old folder name, or 0. Kept for
  a machine that still has collection_<slug>_<rev>_<when> folders and no state
  to read. Current Vortex does not write these any more; see
  Get-CollectionRevision above.
#>
function Get-CollectionRevisionFromFolder([string]$Slug) {
    if (-not $Slug) { return 0 }
    $dir = Join-Path $env:APPDATA 'Vortex\skyrimse\mods'
    if (-not (Test-Path -LiteralPath $dir)) { return 0 }
    $best = 0
    foreach ($d in (Get-ChildItem -LiteralPath $dir -Directory -Filter ("collection_" + $Slug + "_*") -EA SilentlyContinue)) {
        $rest = $d.Name.Substring(("collection_" + $Slug + "_").Length)
        $cut = $rest.IndexOf('_')
        if ($cut -le 0) { continue }
        $n = 0
        if (-not [int]::TryParse($rest.Substring(0, $cut), [ref]$n)) { continue }
        if ($n -gt $best) { $best = $n }
    }
    return $best
}

<#
  The mod ids Vortex has recorded against a collection slug, from state.v2.
  Empty when state cannot be read or names no collection with that slug. Used
  to find the collection's mod folder now that the folder is named for the mod
  id rather than the slug (see Get-CollectionInstalledFolder).
#>
function Get-CollectionModIds([string]$Slug) {
    $ids = New-Object Collections.Generic.List[string]
    if (-not $Slug) { return , [string[]]$ids.ToArray() }
    $st = Join-Path $env:APPDATA 'Vortex\state.v2'
    if (-not (Test-Path -LiteralPath $st)) { return , [string[]]$ids.ToArray() }
    $slugRe = 'mods###skyrimse###([^#]+)###attributes###collectionSlug[\x00-\x1F]{1,4}"' + [regex]::Escape($Slug) + '"'
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($f in (Get-ChildItem -LiteralPath $st -File -EA SilentlyContinue)) {
        try {
            $txt = [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($f.FullName))
            foreach ($m in [regex]::Matches($txt, $slugRe)) {
                if ($seen.Add($m.Groups[1].Value)) { [void]$ids.Add($m.Groups[1].Value) }
            }
        } catch { }
    }
    return , [string[]]$ids.ToArray()
}

<#
  The staging folder holding the installed collection's collection.json, or
  $null. Check-CollectionRules needs the file itself, not just the number, and
  the folder is no longer named for the slug, so this maps slug to mod id
  through state (new naming) and falls back to the collection_<slug>_<rev>_*
  folder (legacy). The newest revision wins in both cases.
#>
function Get-CollectionInstalledFolder([string]$Slug) {
    if (-not $Slug) { return $null }
    $dir = Join-Path $env:APPDATA 'Vortex\skyrimse\mods'
    if (-not (Test-Path -LiteralPath $dir)) { return $null }

    # New naming: the folder is the mod id Vortex made up, which state ties to
    # the slug. Newest by write time, since the id carries no number.
    $new = New-Object Collections.Generic.List[object]
    foreach ($id in (Get-CollectionModIds $Slug)) {
        foreach ($d in (Get-ChildItem -LiteralPath $dir -Directory -Filter ($id + '*') -EA SilentlyContinue)) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName 'collection.json')) { [void]$new.Add($d) }
        }
    }
    if ($new.Count -gt 0) { return ($new | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1) }

    # Legacy naming: collection_<slug>_<rev>_<when>, highest revision wins.
    $best = $null
    $bestRev = -1
    foreach ($d in (Get-ChildItem -LiteralPath $dir -Directory -Filter ('collection_' + $Slug + '_*') -EA SilentlyContinue)) {
        if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'collection.json'))) { continue }
        $m = [regex]::Match($d.Name, '^collection_' + [regex]::Escape($Slug) + '_(\d+)_')
        if (-not $m.Success) { continue }
        $r = [int]$m.Groups[1].Value
        if ($r -gt $bestRev) { $bestRev = $r; $best = $d }
    }
    return $best
}

<#
  The newest collection revision VORTEX KNOWS ABOUT, or 0.

  This is the half that was missing, and it is the answer to "why was the
  server derived from something out of date".

  The server's load order and the reference plugin list are both derived from
  whatever Vortex has DEPLOYED on the shipping machine. Nothing ever asked
  whether that deployment was current. It did not have to go and look: Vortex
  polls Nexus itself and writes down what it finds, and on 22 September its
  own state held, in order:

      "newestVersion","from":"2","to":"3"
      "newestVersion","from":"3","to":"4"

  So the machine knew revision 4 existed, and had known for days, while every
  release went out built against revision 2. The information was there and
  nothing read it.

  Read out of Vortex's state as text rather than by opening the database,
  because this only needs a number and must never be the reason a deploy
  fails. Every transition is scanned and the highest destination wins, since
  the log holds the whole history. 0 when nothing can be read, which means say
  nothing: a wrong number here would stop a deploy that is perfectly correct.
#>
function Get-CollectionNewest {
    $st = Join-Path $env:APPDATA 'Vortex\state.v2'
    if (-not (Test-Path -LiteralPath $st)) { return 0 }
    $best = 0
    foreach ($f in (Get-ChildItem -LiteralPath $st -File -EA SilentlyContinue)) {
        try {
            $txt = [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($f.FullName))

            # SHAPE ONE, the transition Vortex writes the moment it notices a
            # newer revision than the one installed:
            #     "newestVersion","from":"3","to":"4"
            foreach ($m in [regex]::Matches($txt, '"newestVersion"\s*,\s*"from"\s*:\s*"(\d+)"\s*,\s*"to"\s*:\s*"(\d+)"')) {
                $n = 0
                if ([int]::TryParse($m.Groups[2].Value, [ref]$n) -and $n -gt $best) { $best = $n }
            }

            # SHAPE TWO, THE PLAIN CURRENT VALUE, and this is what is actually
            # there once the machine is ON the newest revision, because there
            # is no transition left to record. Only shape one was read until
            # 22 September, so the moment revision 5 was installed the newest
            # went back to 0 and the deploy gate stopped checking anything,
            # which is the exact failure the gate was added for a day earlier.
            #
            # LevelDB writes the key, then ONE length byte, then that many
            # bytes of JSON. Measured on this machine:
            #
            #   6E 65 77 65 73 74 56 65 72 73 69 6F 6E 03 22 35 22
            #   n  e  w  e  s  t  V  e  r  s  i  o  n  len "  5  "
            #
            # A deleted key writes a length of 0 and no value, and is simply
            # not matched. The length byte is any control character, so the
            # class is bounded rather than a wildcard: a bare .{1,4} would
            # happily match a quote and read somebody else's number.
            foreach ($m in [regex]::Matches($txt, 'newestVersion[\x00-\x1F]{1,4}"(\d+)"')) {
                $n = 0
                if ([int]::TryParse($m.Groups[1].Value, [ref]$n) -and $n -gt $best) { $best = $n }
            }
        } catch { }
    }
    return $best
}

<#
  Is this machine's collection behind what Vortex knows is out there?

  Returns a small object rather than a bool, because every caller wants to
  say the two numbers and a bool cannot. Behind is $false when either number
  is unknown: silence beats a guess in both directions.
#>
function Get-CollectionState([string]$Url) {
    $slug = Get-CollectionSlug $Url
    $have = Get-CollectionRevision $slug
    $newest = Get-CollectionNewest
    return [pscustomobject]@{
        Slug     = $slug
        Have     = $have
        Newest   = $newest
        Behind   = ($have -gt 0 -and $newest -gt 0 -and $have -lt $newest)
        Known    = ($have -gt 0 -and $newest -gt 0)
    }
}

# "7essxf" out of https://www.nexusmods.com/games/skyrimspecialedition/collections/7essxf
function Get-CollectionSlug([string]$Url) {
    if (-not $Url) { return '' }
    $at = $Url.LastIndexOf('/collections/', [StringComparison]::OrdinalIgnoreCase)
    if ($at -lt 0) { return '' }
    $s = $Url.Substring($at + '/collections/'.Length).Trim()
    $q = $s.IndexOfAny([char[]]('/', '?', '#'))
    if ($q -ge 0) { $s = $s.Substring(0, $q) }
    if ($s -notmatch '^[A-Za-z0-9]+$') { return '' }
    return $s
}

function Test-LoadOrderMaster([string]$Name) {
    $n = "$Name".Trim()
    foreach ($m in $script:LoadOrderMasters) {
        if ([string]::Equals($m, $n, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# An .esl, or the ESL flag in the TES4 header: Checks.TakesNoPlace in the
# launcher. A header that cannot be read answers true, as Checks.IsLight does.
# A file that is not there answers false; missing is the "not in Data" issue's.
function Test-LoadOrderLight([string]$Path) {
    if ($Path -match '\.esl$') { return $true }
    if (-not [IO.File]::Exists($Path)) { return $false }
    try {
        $b = New-Object byte[] 12
        $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $n = $fs.Read($b, 0, 12) } finally { $fs.Close() }
        if ($n -lt 12) { return $true }
        if ([Text.Encoding]::ASCII.GetString($b, 0, 4) -ne 'TES4') { return $true }
        return (([BitConverter]::ToUInt32($b, 8) -band 0x200) -ne 0)
    } catch { return $true }
}

# The plugin an enabled line switches on, or $null for a comment, a blank or a
# disabled line.
function Get-LoadOrderEnabledName([string]$Line) {
    $s = "$Line".Trim()
    if (-not $s.StartsWith('*')) { return $null }
    $n = $s.Substring(1).Trim()
    if ($n.Length -eq 0) { return $null }
    return $n
}

# The full plugin order the game will use. $IsLightOrMissing and $ExistsInData
# are script blocks taking the plugin name as their one argument.
function Get-LoadOrderGame([string[]]$Enabled, [scriptblock]$IsLightOrMissing, [string[]]$Ccc, [scriptblock]$ExistsInData) {
    $order = New-Object Collections.Generic.List[string]
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($m in $script:LoadOrderMasters) { [void]$order.Add($m); [void]$seen.Add($m) }
    foreach ($names in @($Ccc, $Enabled)) {
        foreach ($raw in @($names)) {
            $n = "$raw".Trim()
            if ($n.Length -eq 0 -or $seen.Contains($n)) { continue }
            if ($null -ne $ExistsInData -and -not (& $ExistsInData $n)) { continue }
            if ($null -ne $IsLightOrMissing -and (& $IsLightOrMissing $n)) { continue }
            [void]$seen.Add($n)
            [void]$order.Add($n)
        }
    }
    return ,[string[]]$order.ToArray()
}

# The first position where the two lists name different plugins, or where one
# of them ends; -1 when they are the same list.
function Get-LoadOrderFirstMismatch([string[]]$Game, [string[]]$Manifest) {
    $g = if ($null -eq $Game) { 0 } else { $Game.Count }
    $m = if ($null -eq $Manifest) { 0 } else { $Manifest.Count }
    $n = [Math]::Max($g, $m)
    for ($i = 0; $i -lt $n; $i++) {
        if ($i -ge $g -or $i -ge $m) { return $i }
        if (-not [string]::Equals("$($Game[$i])".Trim(), "$($Manifest[$i])".Trim(), [StringComparison]::OrdinalIgnoreCase)) { return $i }
    }
    return -1
}

# The same plugins.txt lines with the full enabled plugins in the server's
# order. A line moves only when it enables a plugin the server names and that
# plugin is not light; those lines' positions are refilled top to bottom in the
# server's order, and every other line keeps its index. The masters are skipped
# on the server's side. A light plugin the server names holds its place. A
# plugin the server names that no line enables is not this function's to
# switch on: $null comes back and the list is left as it was.
function Get-LoadOrderReordered([string[]]$Lines, [string[]]$Manifest, [scriptblock]$IsLight) {
    if ($null -eq $Lines -or $null -eq $Manifest) { return $null }
    $at = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $name = Get-LoadOrderEnabledName $Lines[$i]
        if ($null -eq $name) { continue }
        if ($at.ContainsKey($name)) { return $null }
        $at[$name] = $i
    }
    $order = New-Object Collections.Generic.List[string]
    $slots = New-Object Collections.Generic.List[int]
    $placed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($raw in $Manifest) {
        $n = "$raw".Trim()
        if ($n.Length -eq 0 -or (Test-LoadOrderMaster $n) -or $placed.Contains($n)) { continue }
        [void]$placed.Add($n)
        if (-not $at.ContainsKey($n)) { return $null }
        $line = $at[$n]
        if ($null -ne $IsLight -and (& $IsLight $n)) { continue }
        [void]$order.Add($Lines[$line])
        [void]$slots.Add($line)
    }
    $slots.Sort()
    $result = [string[]]$Lines.Clone()
    for ($k = 0; $k -lt $slots.Count; $k++) { $result[$slots[$k]] = $order[$k] }
    return ,$result
}

# How many lines Get-LoadOrderReordered changed, and the plugin now sitting on
# the first of them.
function Get-LoadOrderMoved([string[]]$Before, [string[]]$After) {
    $n = 0
    $first = $null
    if ($null -ne $Before -and $null -ne $After -and $Before.Count -eq $After.Count) {
        for ($i = 0; $i -lt $Before.Count; $i++) {
            if ([string]::Equals($Before[$i], $After[$i], [StringComparison]::Ordinal)) { continue }
            if ($null -eq $first) {
                $first = Get-LoadOrderEnabledName $After[$i]
                if ($null -eq $first) { $first = $After[$i] }
            }
            $n++
        }
    }
    return [pscustomobject]@{ Count = $n; First = $first }
}

# The manifest's plugin names that no line enables, for saying which ones.
function Get-LoadOrderNotEnabled([string[]]$Lines, [string[]]$Manifest) {
    $missing = New-Object Collections.Generic.List[string]
    if ($null -eq $Lines -or $null -eq $Manifest) { return ,[string[]]$missing.ToArray() }
    $have = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($l in $Lines) {
        $name = Get-LoadOrderEnabledName $l
        if ($null -ne $name) { [void]$have.Add($name) }
    }
    foreach ($raw in $Manifest) {
        $n = "$raw".Trim()
        if ($n.Length -eq 0 -or (Test-LoadOrderMaster $n) -or $have.Contains($n)) { continue }
        if (-not $missing.Contains($n)) { [void]$missing.Add($n) }
    }
    return ,[string[]]$missing.ToArray()
}

# A plugin list's lines, and how the file is written, so it can be written
# back the same way: the game stops on a byte order mark, and a changed
# newline is a changed file to everything that hashes it.
function Read-LoadOrderFile([string]$Path) {
    $raw = [IO.File]::ReadAllBytes($Path)
    $bom = ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF)
    $skip = if ($bom) { 3 } else { 0 }
    $text = (New-Object Text.UTF8Encoding($false)).GetString($raw, $skip, $raw.Length - $skip)
    $nl = if ($text.IndexOf("`r`n", [StringComparison]::Ordinal) -ge 0) { "`r`n" } else { "`n" }
    $trailing = $text.EndsWith("`n")
    $lines = New-Object Collections.Generic.List[string]
    foreach ($l in ($text -split "`r`n|`n")) { [void]$lines.Add($l) }
    if ($trailing -and $lines.Count -gt 0) { $lines.RemoveAt($lines.Count - 1) }
    return [pscustomobject]@{ Lines = [string[]]$lines.ToArray(); Bom = $bom; NewLine = $nl; Trailing = $trailing }
}

function Write-LoadOrderFile([string]$Path, [string[]]$Lines, $Like) {
    $body = New-Object Collections.Generic.List[byte]
    if ($Like.Bom) { $body.AddRange([byte[]](0xEF, 0xBB, 0xBF)) }
    $text = ($Lines -join $Like.NewLine)
    if ($Like.Trailing) { $text += $Like.NewLine }
    $body.AddRange((New-Object Text.UTF8Encoding($false)).GetBytes($text))
    [IO.File]::WriteAllBytes($Path, $body.ToArray())
}

# Where the launcher on this machine reads the server's manifest: the same
# address as Verify.ServerBase, on the resources port SkyMp.ResourcePortFor
# works out from config.json. The main server on 7777 serves resources on
# 3000; any other port, the dev server's 7787 among them, serves them on the
# game port plus one.
function Get-LoadOrderManifestUrl([string]$Root) {
    $cfgPath = Join-Path $Root 'config.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { throw "no config.json at $cfgPath" }
    $raw = [IO.File]::ReadAllBytes($cfgPath)
    $skip = if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { 3 } else { 0 }
    $cfg = [Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip) | ConvertFrom-Json
    $addr = ''
    $portText = ''
    if ($cfg.PSObject.Properties.Name -contains 'ServerAddress') { $addr = [string]$cfg.ServerAddress }
    if ($cfg.PSObject.Properties.Name -contains 'ServerPort') { $portText = [string]$cfg.ServerPort }
    if (-not $addr) { throw "$cfgPath names no ServerAddress" }
    $port = 0
    if (-not [int]::TryParse($portText, [ref]$port) -or $port -le 0) { $port = 7777 }
    $rp = if ($port -eq 7777) { 3000 } else { $port + 1 }
    return "http://${addr}:$rp/api/servers/thornswood/manifest.json"
}

# The plugin names out of a manifest's JSON, in the server's order, or $null
# when it is not a manifest.
function ConvertFrom-LoadOrderManifest([string]$Json) {
    try { $doc = $Json | ConvertFrom-Json } catch { return $null }
    if ($null -eq $doc -or -not ($doc.PSObject.Properties.Name -contains 'mods') -or $null -eq $doc.mods) { return $null }
    $names = New-Object Collections.Generic.List[string]
    foreach ($m in @($doc.mods)) {
        if ($null -eq $m -or -not ($m.PSObject.Properties.Name -contains 'filename')) { continue }
        $f = "$($m.filename)"
        if ($f.Length) { [void]$names.Add($f) }
    }
    if ($names.Count -eq 0) { return $null }
    return ,[string[]]$names.ToArray()
}

# The server's manifest, fetched, or $null when the server does not answer.
function Get-LoadOrderManifest([string]$Url, [int]$TimeoutMs = 4000) {
    try {
        $req = [Net.WebRequest]::Create($Url)
        $req.Timeout = $TimeoutMs
        $req.ReadWriteTimeout = $TimeoutMs
        $req.UserAgent = 'ThornswoodPublish'
        $res = $req.GetResponse()
        try {
            $sr = New-Object IO.StreamReader($res.GetResponseStream())
            try { $json = $sr.ReadToEnd() } finally { $sr.Close() }
        } finally { $res.Close() }
        return ConvertFrom-LoadOrderManifest $json
    } catch { return $null }
}
