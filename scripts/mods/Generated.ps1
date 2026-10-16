<#
.SYNOPSIS
  What Thornswood's generated files are, what they were built from, and
  whether the ones in a game folder are still current. Dot-sourced by
  Build-Generated.ps1, Ship.ps1 and Check-ShipReady.ps1.

.DESCRIPTION
  Issue #1247. Patrick, 29 Sep: the behavior files (Nemesis' output until
  then) and BodySlide's body meshes are made in Thornswood's own folder, as a
  scripted step on the shipping PC before a Ship. Steam's copy stays the
  person's own. The behavior files are made by Pandora Behaviour Engine+,
  Nemesis' successor, which reads the same patches and has a command line that
  works; Nemesis' -generate never starts its work (Build-Generated.ps1).

  Until then both tools were run into the Steam copy, and Thornswood's folder
  took their output from there. Since #1232 the folder takes only Skyrim's own
  files, Vortex's and Thornswood's, so output made in the Steam copy never
  reaches a release any more. Build-Generated.ps1 makes it in the folder
  itself and writes this record of it:

      <Root>\Profile\OwnGame\generated.txt

      generated 1
      game C:\Thornswood-DevBuild\Game
      built 2026-09-29T21:04:11
      part list <sha256>          records\generated.json and the recipe
      part plugins <sha256>       the mod list, Profile\OwnGame\plugins.txt
      part behaviors <sha256>     Vortex's files Pandora reads
      part bodyslide <sha256>     Vortex's files BodySlide builds from
      inputs <sha256>             all four together
      file <sha256> <path>        one line per file it made, path under the game folder

  The launcher reads the file lines (OwnGameKinds.cs): each is Thornswood's
  own, and a refresh leaves it as built even where Vortex deploys a file of
  the same name. Ship-Rules.ps1 reads them too, so Publish-Update and the
  installer carry them although the launcher's files.txt says Vortex deploys
  that path.

  CURRENT means: the record is there, for this folder, every part matches what
  is on this machine now, and every file on it is in the folder with the bytes
  it was built with. The parts are read from the launcher's own record of what
  Vortex deployed (files.txt, the V lines, with the size and time of Vortex's
  own copy), never from the folder's files, which the tools rewrite. So a
  collection revision that changes a behavior patch, an animation list, a
  slider set or BodySlide itself makes it stale, and so does a changed mod
  list or a change to records\generated.json.
#>

# Move this when Build-Generated.ps1 changes what it builds or how, so every
# record made the old way reads as stale.
$GeneratedRecipe = 2

# Vortex's files each tool reads, by path under the game folder. What one of
# them is changes the tool's output, so a change to any makes the build stale.
# Pandora: the patches (Nemesis' format and its own), Pandora itself in the
# folder the collection puts it in, and the animations and lists under meshes.
$GeneratedBehaviorInputs = @(
    '^Data\\Nemesis_Engine\\mod\\',
    '^Data\\Pandora_Engine\\',
    '^Data\\[^\\]*pandora[^\\]*\\',
    '^Data\\meshes\\actors\\.+\.(hkx|txt)$',
    '^Data\\meshes\\[^\\]+\.txt$'
)
$GeneratedBodySlideInputs = @(
    '^Data\\CalienteTools\\BodySlide\\',
    '^Data\\meshes\\actors\\character\\character assets\\'
)

# The tools' own folders. What BodySlide writes there (its settings, its log,
# the group and preset made for a build) is the tool's, never output, and
# Ship-Rules keeps the folder out of every pack. Pandora runs from a copy in
# the work folder and writes nothing in the game folder at all.
$GeneratedToolDirs = @('Data\CalienteTools\')

# BODY SHAPE (issue #1004). Patrick, 28 Sep: nothing that changes breasts, the
# seat, genitals or nipples. A slider whose name says it shapes one of them
# must stay where it does nothing: 0, or 100 on an inverted slider.
$GeneratedShapeRule = '(?i)(breast|boob|bust|cleavage|nipple|areola|butt|glute|booty|cheek|crotch|vagina|labia|clit|pussy|anus|anal|genital|schlong|penis|scrotum|testic|bulge|pubic|camel|push.?up|melon|oppai|chest|7b)'
# COVERED (issue #405). A zap slider takes a whole shape off the mesh. One
# named for the underwear must stay at 0, or the body is built nude.
$GeneratedCoverRule = '(?i)(bra|panty|panties|underwear|boxer|brief|loincloth|thong|shorts|top|smallclothes)'

function Get-GeneratedRecordPath([string]$Root) {
    return (Join-Path $Root 'Profile\OwnGame\generated.txt')
}

function Get-GeneratedSha([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash($Bytes) | ForEach-Object { $_.ToString('x2') })) }
    finally { $sha.Dispose() }
}

function Get-GeneratedTextSha([string]$Text) {
    return (Get-GeneratedSha ([Text.Encoding]::UTF8.GetBytes($Text)))
}

function Get-GeneratedFileSha([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# The record, or $null when there is none. Throws on a line it does not know,
# because a record read wrong would call a stale build current.
function Read-GeneratedRecord([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $rec = [pscustomobject]@{
        Version = 0; Game = ''; Built = ''; Inputs = ''
        Parts = [ordered]@{}
        Files = New-Object 'System.Collections.Generic.List[object]'
    }
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $n++
        if ($line.Trim().Length -eq 0) { continue }
        $m = [regex]::Match($line, '^file ([0-9a-f]{64}) (.+)$')
        if ($m.Success) { $rec.Files.Add([pscustomobject]@{ Sha = $m.Groups[1].Value; Rel = $m.Groups[2].Value }); continue }
        $m = [regex]::Match($line, '^part ([a-z]+) ([0-9a-f]{64})$')
        if ($m.Success) { $rec.Parts[$m.Groups[1].Value] = $m.Groups[2].Value; continue }
        $m = [regex]::Match($line, '^inputs ([0-9a-f]{64})$')
        if ($m.Success) { $rec.Inputs = $m.Groups[1].Value; continue }
        $m = [regex]::Match($line, '^generated ([0-9]+)$')
        if ($m.Success) { $rec.Version = [int]$m.Groups[1].Value; continue }
        $m = [regex]::Match($line, '^game (.+)$')
        if ($m.Success) { $rec.Game = $m.Groups[1].Value; continue }
        $m = [regex]::Match($line, '^built (.+)$')
        if ($m.Success) { $rec.Built = $m.Groups[1].Value; continue }
        throw ("Line $n of $Path is not one this understands: " + $line)
    }
    return $rec
}

# Writes the record in one step, so nothing ever reads half of one.
function Write-GeneratedRecord([string]$Path, [string]$Game, $Inputs, $Files) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('generated 1')
    $lines.Add('game ' + $Game)
    $lines.Add('built ' + (Get-Date).ToString('s'))
    foreach ($k in $Inputs.Parts.Keys) { $lines.Add('part ' + $k + ' ' + $Inputs.Parts[$k]) }
    $lines.Add('inputs ' + $Inputs.Sha)
    foreach ($f in @($Files | Sort-Object -Property Rel)) { $lines.Add('file ' + $f.Sha + ' ' + $f.Rel) }
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $tmp = $Path + '.new'
    [IO.File]::WriteAllLines($tmp, $lines.ToArray(), (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Delete($Path) }
    [IO.File]::Move($tmp, $Path)
}

# records\generated.json, checked. Throws with the sentence to show.
function Get-GeneratedBuildList([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "There is no build list at $Path." }
    $doc = $null
    try { $doc = ([IO.File]::ReadAllText($Path) -replace '^\uFEFF', '') | ConvertFrom-Json }
    catch { throw ("$Path is not valid JSON: " + $_.Exception.Message) }
    # RecordShape.ps1 (#2180): a version this checkout does not know stops here.
    . (Join-Path $PSScriptRoot '..\release\RecordShape.ps1')
    $shape = @(Get-ThornswoodRecordProblems -Doc $doc -Kind generated)
    if ($shape.Count) { throw ("$Path is not a generated build list this checkout can trust: " + ($shape -join '; ')) }
    $patches = @()
    if ($doc.PSObject.Properties['pandora'] -and $doc.pandora.PSObject.Properties['patches']) { $patches = @($doc.pandora.patches | ForEach-Object { [string]$_ }) }
    foreach ($p in $patches) {
        if ($p -notmatch '^[A-Za-z0-9_]+$') { throw "$Path names a behavior patch '$p', which is not a patch code (the folder name under Data\Nemesis_Engine\mod or Data\Pandora_Engine\mod)." }
    }
    $sets = @()
    if ($doc.PSObject.Properties['bodyslide'] -and $doc.bodyslide.PSObject.Properties['sets']) { $sets = @($doc.bodyslide.sets | ForEach-Object { [string]$_ }) }
    foreach ($s in $sets) { if (-not $s.Trim()) { throw "$Path names an empty BodySlide slider set." } }
    # Outfits fitted to those bodies (#2454): built the same way, under the
    # same rules, and never a body as well.
    $outfits = @()
    if ($doc.PSObject.Properties['bodyslide'] -and $doc.bodyslide.PSObject.Properties['outfits']) { $outfits = @($doc.bodyslide.outfits | ForEach-Object { [string]$_ }) }
    foreach ($s in $outfits) {
        if (-not $s.Trim()) { throw "$Path names an empty BodySlide outfit set." }
        if ($sets -contains $s) { throw "$Path names '$s' as a body and as an outfit; it is one or the other." }
    }
    $dupes = @($outfits | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    if ($dupes.Count) { throw "$Path names the outfit set '$($dupes[0])' more than once." }
    $sliders = @{}
    if ($doc.PSObject.Properties['bodyslide'] -and $doc.bodyslide.PSObject.Properties['sliders'] -and $doc.bodyslide.sliders) {
        foreach ($sp in $doc.bodyslide.sliders.PSObject.Properties) {
            if ($sets -notcontains $sp.Name -and $outfits -notcontains $sp.Name) { throw "$Path moves sliders of '$($sp.Name)', which is not one of the sets it builds." }
            $one = @{}
            foreach ($sl in $sp.Value.PSObject.Properties) {
                $v = @{}
                foreach ($size in 'big', 'small') {
                    if ($sl.Value.PSObject.Properties[$size]) { $v[$size] = [double]$sl.Value.$size }
                }
                $one[$sl.Name] = $v
            }
            $sliders[$sp.Name] = $one
        }
    }
    if (-not $patches.Count -and -not $sets.Count -and -not $outfits.Count) { throw "$Path names nothing to build." }
    return [pscustomobject]@{ Path = $Path; Patches = $patches; Sets = $sets; Outfits = $outfits; Sliders = $sliders }
}

# The files a slider set writes, under the game folder: OutputPath\OutputFile,
# as _0 and _1 when it builds weights. An outfit that would write a body, or
# anything outside meshes, is refused (#2454).
function Get-BodySlideSetOutputs($Set) {
    $dir = ([string]$Set.OutputPath).Trim().Trim('\').Replace('/', '\')
    $name = ([string]$Set.OutputFile).Trim()
    if (-not $dir -or -not $name) { throw "The slider set '$($Set.Name)' names no output, so what it builds cannot be told." }
    if ($dir -notmatch '(?i)^meshes\\' -or $dir -match '\.\.') { throw "The slider set '$($Set.Name)' writes to $dir, outside meshes." }
    if ($Set.GenWeights) { $files = @("$name`_0.nif", "$name`_1.nif") } else { $files = @("$name.nif") }
    return , @($files | ForEach-Object { 'Data\' + $dir + '\' + $_ })
}

# Whether a path under the game folder is one of the bodies (#405 checks
# those); an outfit set may not write one.
function Test-GeneratedBodyPath([string]$Rel) {
    return ($Rel -match '(?i)^Data\\meshes\\actors\\character\\character assets\\(female|male)body')
}

# The files of Pandora's mod when Vortex deployed its archive loose into Data.
# The build and its freshness check must agree on the exe and every library.
function Get-GeneratedLoosePandoraFiles([string]$Root) {
    $made = Join-Path $Root 'Profile\OwnGame\made.txt'
    $source = ''
    $steam = ''
    if (Test-Path -LiteralPath $made) {
        foreach ($line in [IO.File]::ReadAllLines($made)) {
            $m = [regex]::Match($line.TrimStart([char]0xFEFF), '^(source|game)=(.+)$')
            if (-not $m.Success) { continue }
            if ($m.Groups[1].Value -eq 'source') { $source = $m.Groups[2].Value.Trim() } else { $steam = $m.Groups[2].Value.Trim() }
        }
    }
    if (-not $source) { throw "$made names no source, so the files of Pandora's mod cannot be read." }
    # The source may itself be a Thornswood folder rather than the one Vortex
    # deploys into: the dev release folder and the main install on One both
    # record source=C:\Thornswood-DevBuild\Game. A Thornswood folder never holds
    # Vortex's record (OwnGame leaves it out, and Build-Generated refuses a folder
    # that has it), so on 11 Oct, once the dev install's refresh had taken it
    # out, every Ship from those folders stopped here; and later that day that
    # folder was deleted altogether. Follow each Thornswood folder's own record
    # back to the folder that has Vortex's, a few steps at most so a loop of
    # records cannot spin, and when the chain ends without it, take the game
    # folder the record names (game=, the Steam copy Vortex deploys into).
    $manifest = Join-Path $source 'Data\vortex.deployment.json'
    $seen = @($source)
    for ($hop = 0; $hop -lt 4 -and -not (Test-Path -LiteralPath $manifest); $hop++) {
        $back = Join-Path (Split-Path -Parent $source) 'Profile\OwnGame\made.txt'
        $next = ''
        if (Test-Path -LiteralPath $back) {
            foreach ($line in [IO.File]::ReadAllLines($back)) {
                $m = [regex]::Match($line.TrimStart([char]0xFEFF), '^source=(.+)$')
                if ($m.Success) { $next = $m.Groups[1].Value.Trim() }
            }
        }
        if (-not $next -or $seen -contains $next) { break }
        $seen += $next
        $source = $next
        $manifest = Join-Path $source 'Data\vortex.deployment.json'
    }
    if (-not (Test-Path -LiteralPath $manifest) -and $steam) {
        $atSteam = Join-Path $steam 'Data\vortex.deployment.json'
        if (Test-Path -LiteralPath $atSteam) { $manifest = $atSteam }
    }
    if (-not (Test-Path -LiteralPath $manifest)) { throw "Vortex's record ($manifest) cannot be read, so the files of Pandora's mod cannot be read." }
    $doc = ([IO.File]::ReadAllText($manifest) -replace '^\uFEFF', '') | ConvertFrom-Json
    $mine = @($doc.files | Where-Object { ([string]$_.relPath) -ieq 'Pandora Behaviour Engine+.exe' })
    if ($mine.Count -ne 1) { throw "Vortex's record ($manifest) does not name one mod for Pandora Behaviour Engine+.exe." }
    return @($doc.files | Where-Object { [string]$_.source -eq [string]$mine[0].source } | ForEach-Object { ([string]$_.relPath).TrimStart('\') })
}
# The four parts a build depends on, each as a sha256, and all four together.
# Reads the launcher's record of what Vortex deployed, never the folder itself.
function Get-GeneratedInputs([string]$Root, [string]$ListPath) {
    $filesTxt = Join-Path $Root 'Profile\OwnGame\files.txt'
    if (-not (Test-Path -LiteralPath $filesTxt)) {
        throw "There is no $filesTxt, the launcher's record of what Vortex deployed into this folder, so what the tools build from cannot be read."
    }
    $loose = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath (Join-Path $Root 'Game\Data\Pandora Behaviour Engine+.exe')) {
        foreach ($rel in @(Get-GeneratedLoosePandoraFiles $Root)) { [void]$loose.Add('Data\' + $rel) }
    }
    $nem = New-Object 'System.Collections.Generic.List[string]'
    $bs = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in [IO.File]::ReadLines($filesTxt)) {
        $p = $line.Split([char[]]'|', 5)
        if ($p.Count -ne 5 -or $p[1] -ne 'V') { continue }
        $rel = $p[4]
        $row = $rel.ToLowerInvariant() + '|' + $p[2] + '|' + $p[3]
        if ($loose.Contains($rel)) { $nem.Add($row) }
        else { foreach ($rx in $GeneratedBehaviorInputs) { if ($rel -match "(?i)$rx") { $nem.Add($row); break } } }
        foreach ($rx in $GeneratedBodySlideInputs) { if ($rel -match "(?i)$rx") { $bs.Add($row); break } }
    }
    $nemA = $nem.ToArray(); [Array]::Sort($nemA, [StringComparer]::Ordinal)
    $bsA = $bs.ToArray(); [Array]::Sort($bsA, [StringComparer]::Ordinal)

    $plugins = Join-Path $Root 'Profile\OwnGame\plugins.txt'
    $pl = 'none'
    if (Test-Path -LiteralPath $plugins) {
        $pl = (@([IO.File]::ReadAllLines($plugins) | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }) -join "`n")
    }
    $list = ([IO.File]::ReadAllText($ListPath) -replace "`r`n", "`n") + "`nrecipe=$GeneratedRecipe"

    $parts = [ordered]@{
        list      = (Get-GeneratedTextSha $list)
        plugins   = (Get-GeneratedTextSha $pl)
        behaviors = (Get-GeneratedTextSha ($nemA -join "`n"))
        bodyslide = (Get-GeneratedTextSha ($bsA -join "`n"))
    }
    $all = @($parts.Keys | ForEach-Object { $_ + '=' + $parts[$_] }) -join "`n"
    return [pscustomobject]@{ Sha = (Get-GeneratedTextSha $all); Parts = $parts; BehaviorFiles = $nemA.Count; BodySlideFiles = $bsA.Count }
}

# What a part changing means, in plain words.
function Get-GeneratedPartSays([string]$Part) {
    switch ($Part) {
        'list'      { return 'what records\generated.json says to build, or how Build-Generated.ps1 builds it, changed' }
        'plugins'   { return 'the mod list changed (Profile\OwnGame\plugins.txt)' }
        'behaviors' { return 'a file Pandora reads changed in Vortex (a behavior patch, an animation list or Pandora itself)' }
        'bodyslide' { return 'a file BodySlide builds from changed in Vortex (a slider set, its shape data, a body mesh or BodySlide itself)' }
    }
    return "$Part changed"
}

# Whether the generated files in <Root>\Game are current. Current is $true, or
# $false with Why saying each reason in plain words.
function Get-GeneratedState([string]$Root, [string]$ListPath) {
    $game = Join-Path $Root 'Game'
    $why = New-Object 'System.Collections.Generic.List[string]'
    $rec = Read-GeneratedRecord (Get-GeneratedRecordPath $Root)
    if ($null -eq $rec) {
        $why.Add("they have never been built in $game")
        return [pscustomobject]@{ Current = $false; Why = $why.ToArray(); Record = $null; Inputs = $null; Game = $game }
    }
    $in = Get-GeneratedInputs $Root $ListPath
    if ($rec.Game -and -not [string]::Equals($rec.Game.TrimEnd('\'), $game.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        $why.Add("they were built for " + $rec.Game + ", not this folder")
    }
    foreach ($k in $in.Parts.Keys) {
        $was = ''
        if ($rec.Parts.Contains($k)) { $was = $rec.Parts[$k] }
        if ($was -ne $in.Parts[$k]) { $why.Add((Get-GeneratedPartSays $k)) }
    }
    if ($rec.Files.Count -eq 0) { $why.Add('the record of the last build lists no files') }
    $off = New-Object 'System.Collections.Generic.List[string]'
    foreach ($f in $rec.Files) {
        $p = Join-Path $game $f.Rel
        if (-not (Test-Path -LiteralPath $p)) { $off.Add($f.Rel + ' is gone'); continue }
        if ((Get-GeneratedFileSha $p) -ne $f.Sha) { $off.Add($f.Rel + ' is not as built') }
    }
    if ($off.Count) {
        $shown = @($off | Select-Object -First 4)
        $more = $(if ($off.Count -gt $shown.Count) { ' and ' + ($off.Count - $shown.Count) + ' more' } else { '' })
        $why.Add(("{0} of the {1} files it built {2} not in the folder as built, most likely because the launcher made the folder again or a refresh put Vortex's back: {3}{4}" -f
            $off.Count, $rec.Files.Count, $(if ($off.Count -eq 1) { 'is' } else { 'are' }), ($shown -join ', '), $more))
    }
    return [pscustomobject]@{ Current = ($why.Count -eq 0); Why = $why.ToArray(); Record = $rec; Inputs = $in; Game = $game }
}

# The sentence Ship and Check-ShipReady stop with.
function Get-GeneratedStaleSays($State, [string]$Channel) {
    return ("Thornswood's animation and body files (Pandora and BodySlide) in " + $State.Game + " are out of date: " +
            ($State.Why -join '; ') + ". Close the game and the launcher, run .\scripts\mods\Build-Generated.ps1 -Channel " +
            $Channel + " on this machine, then Ship again. It builds them in Thornswood's own folder and never writes into the Steam copy.")
}

# ------------------------------------------------------------ BodySlide sets

# One slider set, out of the .osp files in SliderSets: its output and shapes,
# and every slider with its defaults. Throws when no .osp has it, or two do.
function Get-BodySlideSet([string]$SliderSetsDir, [string]$Name) {
    $found = @()
    foreach ($osp in @(Get-ChildItem -LiteralPath $SliderSetsDir -Filter '*.osp' -File -ErrorAction Stop)) {
        $x = New-Object Xml.XmlDocument
        $x.Load($osp.FullName)
        foreach ($s in @($x.SelectNodes('/SliderSetInfo/SliderSet'))) {
            if ($s.GetAttribute('name') -ne $Name) { continue }
            $sliders = @()
            foreach ($sl in @($s.SelectNodes('Slider'))) {
                $sliders += [pscustomobject]@{
                    Name   = $sl.GetAttribute('name')
                    Big    = [double]$(if ($sl.GetAttribute('big')) { $sl.GetAttribute('big') } else { '0' })
                    Small  = [double]$(if ($sl.GetAttribute('small')) { $sl.GetAttribute('small') } else { '0' })
                    Invert = ($sl.GetAttribute('invert') -eq 'true')
                    Zap    = ($sl.GetAttribute('zap') -eq 'true')
                    Hidden = ($sl.GetAttribute('hidden') -eq 'true')
                }
            }
            $outNode = $s.SelectSingleNode('OutputFile')
            $found += [pscustomobject]@{
                Name       = $Name
                File       = $osp.FullName
                OutputPath = [string]$s.SelectSingleNode('OutputPath').InnerText
                OutputFile = [string]$outNode.InnerText
                GenWeights = ($outNode.GetAttribute('GenWeights') -eq 'true')
                Shapes     = @($s.SelectNodes('Shape') | ForEach-Object { $_.InnerText })
                Sliders    = $sliders
            }
        }
    }
    if ($found.Count -eq 0) { throw "No slider set named '$Name' is in $SliderSetsDir. It comes with the collection; is the mod that has it deployed?" }
    if ($found.Count -gt 1) { throw "Two slider sets are named '$Name' ($(($found | ForEach-Object { Split-Path -Leaf $_.File }) -join ', ')), so which one is built cannot be told." }
    return $found[0]
}

# Every slider of a set at the value it is built with: its default, or what
# the build list moves it to.
function Get-BodySlideValues($Set, $Moves) {
    $vals = @()
    foreach ($sl in $Set.Sliders) {
        $big = $sl.Big; $small = $sl.Small
        if ($Moves -and $Moves.ContainsKey($sl.Name)) {
            if ($Moves[$sl.Name].ContainsKey('big')) { $big = $Moves[$sl.Name]['big'] }
            if ($Moves[$sl.Name].ContainsKey('small')) { $small = $Moves[$sl.Name]['small'] }
        }
        $vals += [pscustomobject]@{ Name = $sl.Name; Big = $big; Small = $small; Slider = $sl }
    }
    return , $vals
}

# What would break the body rules in a set built at these values: a slider
# that shapes the breasts, the seat, the genitals or the nipples doing
# anything (#1004), a zap taking the underwear off (#405), any other zap moved
# from its default, and a move that names a slider the set does not have.
# Empty when the build keeps to the rules.
function Test-BodySlideRules($Set, $Values, $Moves) {
    $bad = @()
    foreach ($v in $Values) {
        $sl = $v.Slider
        foreach ($pair in @(@('big', $v.Big, $sl.Big), @('small', $v.Small, $sl.Small))) {
            $size = $pair[0]; $val = [double]$pair[1]; $def = [double]$pair[2]
            if ($sl.Zap) {
                if ($sl.Name -match $GeneratedCoverRule) {
                    if ($val -ne 0) { $bad += ("'{0}' in {1} takes the underwear off at {2} ({3}); it has to stay at 0" -f $sl.Name, $Set.Name, $val, $size) }
                } elseif ($val -ne $def) {
                    $bad += ("'{0}' in {1} is a zap moved from its default {2} to {3} ({4})" -f $sl.Name, $Set.Name, $def, $val, $size)
                }
                continue
            }
            if ($sl.Name -match $GeneratedShapeRule) {
                $none = $(if ($sl.Invert) { 100 } else { 0 })
                if ($val -ne $none) { $bad += ("'{0}' in {1} shapes the body at {2} ({3}); it has to stay at {4}, where it does nothing" -f $sl.Name, $Set.Name, $val, $size, $none) }
            }
        }
    }
    if ($Moves) {
        $names = @($Set.Sliders | ForEach-Object { $_.Name })
        foreach ($k in $Moves.Keys) { if ($names -notcontains $k) { $bad += ("records\generated.json moves '{0}', which {1} does not have" -f $k, $Set.Name) } }
    }
    return , $bad
}
