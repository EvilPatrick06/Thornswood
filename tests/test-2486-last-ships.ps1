<#
  test-2486-last-ships.ps1

      pwsh -NoProfile -File .\tests\test-2486-last-ships.ps1

  Thornswood-Last.esp (#2468) ships from this repository the way
  Thornswood-Content.esp does (Patrick, 12 Oct, #2486 B), never through the
  collection, and a release refuses a plugin built against other bytes than
  its own load order. Since #2791 step 3 it ships as its recipe, from which
  each machine makes the plugin: no release carries the plugin itself.

  What this proves, with no game, no box and no network:
    1. Ship-Rules.ps1: its recipe is one of ours ($ShipOursFiles) and the
       plugin is never shipped nor listed as removed (Test-ShipMachine), the
       release places the recipe from game\data as Data\Thornswood-Last.recipe
       (Ensure-ShipRequiredData), the list a pack carries enables the plugin
       last, once (Add-ShipLastPluginLine, plain for loadorder.txt), and
       Get-ShipLastPluginProblem passes the bytes and order it was built
       against and refuses everything else: another load order, other bytes
       of any plugin, the plugin not enabled last, a recipe that makes
       another plugin than the manifest's or is not the manifest's recipe,
       and a collection revision (records\collection-plugins.json) or a
       content plugin with other bytes than the ones it was built against.
    2. ServerContent.ps1: the box reads Thornswood-Last.esp's size and
       sha256 beside the content plugin's (its real far side text, run on a
       folder standing in for the server root), and a release that changes it
       is refused unless the server holds the same bytes (#2308's rule).
    3. Where it is wired: Publish-Update.ps1 (the collection does not own
       it, the pack's list enables it, the bytes check and the server check
       come before the pack), Deploy-DevGamemode.ps1 -LoadOrder (sends it,
       puts it last and sends that order), Deploy-Server.ps1 (sends it; the
       gamemode only deploy refuses a live order that does not end with it),
       Deploy-Gamemode.ps1 (the built order ends with it) and
       CollectionPlugins.ps1 (it is exempt like the content plugin).

  Everything it writes is in its own temp folder.
#>
$env:THORNSWOOD_HARNESS = '1'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Put([string]$path, [string]$text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}
function ShaFile([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }

$tmpRoot = if ($env:TEST_TMP) { $env:TEST_TMP } else { [IO.Path]::GetTempPath() }
$Scratch = Join-Path $tmpRoot ('ts-2486-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
try {
    # ---- 1. Ship-Rules ---------------------------------------------------------------
    Write-Host 'Ship-Rules.ps1'
    . (Join-Path $repo 'scripts\release\Ship-Rules.ps1')
    Yes 'Data\Thornswood-Last.recipe is one of the files that are ours' (@($ShipOursFiles) -contains 'Data\Thornswood-Last.recipe')
    Yes '  and Data\Thornswood-Last.esp is not: it is made from the recipe (#2791)' (@($ShipOursFiles) -notcontains 'Data\Thornswood-Last.esp')
    Yes '  so the rules never ship it and never list it as removed' ((Test-ShipMadeFromRecipe 'Data\Thornswood-Last.esp') -and (Test-ShipMachine 'Data\Thornswood-Last.esp') -and -not (Test-ShipMachine 'Data\Thornswood-Last.recipe'))

    # A recipe is TSLR, version 1, then the size and sha256 of the plugin it
    # makes (scripts\mods\last_recipe.py); only that much is read here.
    function Recipe([int64]$size, [string]$sha, [string]$rest) {
        $b = New-Object System.Collections.Generic.List[byte]
        $b.AddRange([byte[]][Text.Encoding]::ASCII.GetBytes('TSLR')); $b.Add(1)
        $b.AddRange([BitConverter]::GetBytes([uint32]$size))
        for ($i = 0; $i -lt 64; $i += 2) { $b.Add([Convert]::ToByte($sha.Substring($i, 2), 16)) }
        $b.AddRange([byte[]][Text.Encoding]::ASCII.GetBytes($rest))
        return ,$b.ToArray()
    }
    $fake = Join-Path $Scratch 'repo'
    $game = Join-Path $Scratch 'game'
    Put (Join-Path $fake 'game\required-data\README.md') 'empty'
    Put (Join-Path $fake 'game\content\Thornswood-Content.esp') 'the content plugin'
    $recipePath = Join-Path $fake 'game\data\last-plugin.recipe'
    $lastSha = ('ab' * 32)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $recipePath) | Out-Null
    [IO.File]::WriteAllBytes($recipePath, (Recipe 15 $lastSha 'the steps'))
    New-Item -ItemType Directory -Force -Path (Join-Path $game 'Data') | Out-Null
    Yes 'the checkout holds its recipe, so the rules apply' (Test-ShipLastPluginHeld $fake)
    Yes '  and a checkout without it is left as it was' (-not (Test-ShipLastPluginHeld (Join-Path $Scratch 'nothing')))
    $placed = @(Ensure-ShipRequiredData $game $fake)
    Yes 'the release places the recipe in Data from game\data, beside the content plugin, and not the plugin' (
        ($placed -contains 'Data\Thornswood-Last.recipe') -and ($placed -contains 'Data\Thornswood-Content.esp') -and
        ($placed -notcontains 'Data\Thornswood-Last.esp') -and
        ((ShaFile (Join-Path $game 'Data\Thornswood-Last.recipe')) -eq (ShaFile $recipePath)))
    Yes '  and a second run, the same bytes there, places nothing' (@(Ensure-ShipRequiredData $game $fake).Count -eq 0)

    $src = Join-Path $Scratch 'plugins.txt'
    [IO.File]::WriteAllText($src, "# a comment`r`n*A.esp`r`n*Thornswood-Last.esp`r`n*B.esp`r`nC.esp`r`n")
    $before = [IO.File]::ReadAllBytes($src)
    $out = Add-ShipLastPluginLine $src (Join-Path $Scratch 'plugins-last.txt')
    $text = [IO.File]::ReadAllText($out)
    Yes 'the pack''s list enables it as its last line, and once' ($text -eq "# a comment`r`n*A.esp`r`n*B.esp`r`nC.esp`r`n*Thornswood-Last.esp`r`n")
    Yes '  with the list''s own line endings, and the list itself untouched' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($src)) -eq [Convert]::ToBase64String($before))
    $lo = Join-Path $Scratch 'loadorder.txt'
    [IO.File]::WriteAllText($lo, "A.esp`nB.esp`n")
    $plain = [IO.File]::ReadAllText((Add-ShipLastPluginLine $lo (Join-Path $Scratch 'lo-last.txt') -Plain))
    Yes '  and loadorder.txt gains it with no star' ($plain -eq "A.esp`nB.esp`nThornswood-Last.esp`n")

    # Built against: the five masters, two plugins of the collection and the
    # content plugin, each a few bytes. The collection's bytes are what its
    # record (records\collection-plugins.json) says it gives people.
    $data = Join-Path $Scratch 'built'
    $order = @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm', 'A.esp', 'Thornswood-Content.esp', 'B.esp')
    $rows = @(); $recRows = @()
    foreach ($n in $order) {
        $f = if ($n -eq 'Thornswood-Content.esp') { Join-Path $fake 'game\content\Thornswood-Content.esp' } else { Join-Path $data $n }
        if ($n -ne 'Thornswood-Content.esp') { Put $f ('bytes of ' + $n) }
        $row = [ordered]@{ name = $n; size = (Get-Item -LiteralPath $f).Length; sha256 = (ShaFile $f) }
        $rows += $row
        if ($n -ne 'Thornswood-Content.esp') { $recRows += $row }
    }
    function Record($list) { Put (Join-Path $fake 'records\collection-plugins.json') ([ordered]@{ version = 1; collection = '7essxf'; revision = 9; plugins = $list } | ConvertTo-Json -Depth 5) }
    Record $recRows
    $manifest = [ordered]@{ version = 1; plugin = [ordered]@{ name = 'Thornswood-Last.esp'; size = 15; sha256 = $lastSha };
                            loadOrder = $order; builtAgainst = $rows
                            recipe = [ordered]@{ sha256 = (ShaFile $recipePath); size = (Get-Item -LiteralPath $recipePath).Length; sources = 3 } }
    Put (Join-Path $fake 'game\data\last-plugin.json') ($manifest | ConvertTo-Json -Depth 5)
    $enabled = @('A.esp', 'Thornswood-Content.esp', 'B.esp', 'Thornswood-Last.esp')
    $ok = Get-ShipLastPluginProblem $fake $enabled
    Yes 'the order it was built against, at the collection''s bytes, passes' ($ok -eq '')
    $p = Get-ShipLastPluginProblem $fake @('A.esp', 'Thornswood-Content.esp', 'B.esp')
    Yes 'a list that does not enable it last is refused' ($p -match 'does not enable Thornswood-Last\.esp last')
    $p = Get-ShipLastPluginProblem $fake @('B.esp', 'Thornswood-Content.esp', 'A.esp', 'Thornswood-Last.esp')
    Yes 'another load order is refused, naming the position and the rebuild' ($p -match 'another load order' -and $p -match 'position 6' -and $p.Contains('Build-LastPlugin.py'))
    $p = Get-ShipLastPluginProblem $fake @('A.esp', 'Thornswood-Content.esp', 'B.esp', 'D.esp', 'Thornswood-Last.esp')
    Yes 'a plugin it was not built with is refused' ($p -match 'another load order')
    $newRev = @($recRows | ForEach-Object { if ($_.name -eq 'B.esp') { [ordered]@{ name = 'B.esp'; size = $_.size; sha256 = ('0' * 64) } } else { $_ } })
    Record $newRev
    $p = Get-ShipLastPluginProblem $fake $enabled
    Yes 'a collection revision with other bytes of a plugin it copies is refused, naming the revision' ($p -match 'other bytes of B\.esp' -and $p -match 'collection revision 9')
    Record @($recRows | Where-Object { $_.name -ne 'B.esp' })
    $p = Get-ShipLastPluginProblem $fake $enabled
    Yes '  and one without a plugin it was built against' ($p -match 'which collection revision 9 does not have')
    Record $recRows
    Put (Join-Path $fake 'game\content\Thornswood-Content.esp') 'the content plugin, edited'
    $p = Get-ShipLastPluginProblem $fake $enabled
    Yes 'a content plugin changed since the build is refused' ($p -match 'another Thornswood-Content\.esp')
    Put (Join-Path $fake 'game\content\Thornswood-Content.esp') 'the content plugin'
    Yes '  and put back, it passes again' ((Get-ShipLastPluginProblem $fake $enabled) -eq '')
    [IO.File]::WriteAllBytes($recipePath, (Recipe 15 ('cd' * 32) 'the steps'))
    $p = Get-ShipLastPluginProblem $fake $enabled
    Yes 'a recipe that makes another plugin than the one the manifest describes is refused' ($p -match 'makes another Thornswood-Last\.esp')
    [IO.File]::WriteAllBytes($recipePath, (Recipe 15 $lastSha 'other steps'))
    $p = Get-ShipLastPluginProblem $fake $enabled
    Yes '  and so is one that is not the recipe the manifest describes' ($p -match 'is not the recipe')
    [IO.File]::WriteAllBytes($recipePath, (Recipe 15 $lastSha 'the steps'))
    Yes '  and put back, it passes again' ((Get-ShipLastPluginProblem $fake $enabled) -eq '')

    # The Skyrim.ccc plugins load straight after the masters and no plugin
    # list names them; the server's order, and so the built one, has them
    # there. On One on 15 Oct that was _ResourcePack.esl at position 6.
    $cccOrder = @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm', '_ResourcePack.esl', 'A.esp', 'Thornswood-Content.esp', 'B.esp')
    $rp = Join-Path $data '_ResourcePack.esl'; Put $rp 'bytes of _ResourcePack.esl'
    $rpRow = [ordered]@{ name = '_ResourcePack.esl'; size = (Get-Item -LiteralPath $rp).Length; sha256 = (ShaFile $rp) }
    Record (@($recRows) + @($rpRow))
    $manifest.loadOrder = $cccOrder; $manifest.builtAgainst = @($rows) + @($rpRow)
    Put (Join-Path $fake 'game\data\last-plugin.json') ($manifest | ConvertTo-Json -Depth 5)
    $p = Get-ShipLastPluginProblem $fake $enabled
    Yes 'built with a Skyrim.ccc plugin after the masters, a release not told of it is refused at that place' ($p -match 'position 6 this release loads A\.esp and the plugin was built with _ResourcePack\.esl')
    Yes '  and one whose Data holds it passes' ((Get-ShipLastPluginProblem $fake $enabled @('_ResourcePack.esl')) -eq '')
    Yes '  a list that also names it passes once, not twice' ((Get-ShipLastPluginProblem $fake (@('_ResourcePack.esl') + $enabled) @('_ResourcePack.esl')) -eq '')
    $p = Get-ShipLastPluginProblem $fake $enabled @('_ResourcePack.esl', 'ccBGSSSE001-Fish.esm')
    Yes '  and a Skyrim.ccc plugin it was not built with is refused' ($p -match 'position 7 this release loads ccBGSSSE001-Fish\.esm')
    Record $recRows
    $manifest.loadOrder = $order; $manifest.builtAgainst = $rows
    Put (Join-Path $fake 'game\data\last-plugin.json') ($manifest | ConvertTo-Json -Depth 5)
    Yes '  and the order without one still passes with none' ((Get-ShipLastPluginProblem $fake $enabled @()) -eq '')

    Remove-Item -LiteralPath (Join-Path $fake 'game\data\last-plugin.json')
    $p = Get-ShipLastPluginProblem $fake $enabled
    Yes '  and so is one with no manifest' ($p -match 'no game\\data\\last-plugin\.json')

    # ---- 3. Where it is wired --------------------------------------------------------
    Write-Host ''; Write-Host 'the release and the deploys'
    $pu = [IO.File]::ReadAllText((Join-Path $repo 'scripts\release\Publish-Update.ps1'))
    $refFn = $pu.IndexOf('function Get-ReferenceInServerOrder'); $refEnd = $pu.IndexOf('$IsCollection = ', $refFn)
    Yes '  the list put into the server''s order and packed enables it last' ($refFn -gt 0 -and $pu.IndexOf('Add-ShipLastPluginLine $src', $refFn) -gt $refFn -and $pu.IndexOf('Add-ShipLastPluginLine $src', $refFn) -lt $refEnd)
    $bytes = $pu.IndexOf('Get-ShipLastPluginProblem $RepoDir $lastEnabled'); $server = $bytes
    $pack = $pu.IndexOf('CreateEntryFromFile($zip')
    Yes '  the bytes check comes before the pack' ($bytes -gt 0 -and $server -gt 0 -and $pack -gt $bytes -and $pack -gt $server)
    $cccRead = $pu.LastIndexOf("Join-Path `$GameDir 'Skyrim.ccc'", $bytes)
    Yes '  and is handed the Skyrim.ccc plugins in the release''s Data' ($pu.Contains('Get-ShipLastPluginProblem $RepoDir $lastEnabled $lastCcc') -and $cccRead -gt 0 -and $bytes - $cccRead -lt 600)
    $dd = [IO.File]::ReadAllText((Join-Path $repo 'scripts\deploy\Deploy-DevGamemode.ps1'))
    Yes 'Deploy-DevGamemode -LoadOrder puts it last, and sends that order even without -Dist' ($dd.Contains('@($pluginNames | Where-Object { $_ -ine $lastName }) + $lastName') -and $dd.Contains('if ($Dist -or $FromRecord -or $orderMoved)'))
    $ds = [IO.File]::ReadAllText((Join-Path $repo 'scripts\deploy\Deploy-Server.ps1'))
    Yes 'Deploy-Server -GamemodeOnly refuses a live order that does not end with it' ($ds -match 'live load order does not end with Thornswood-Last\.esp')
    $dg = [IO.File]::ReadAllText((Join-Path $repo 'scripts\deploy\Deploy-Gamemode.ps1'))
    Yes 'Deploy-Gamemode builds an order that ends with it, its header read out of the recipe (#2791)' ($dg.Contains('$keep = @($keep | Where-Object { $_ -ine $lastName }) + $lastName') -and $dg.Contains('$info[$lastName] = Read-PluginHeaderBytes $lastHead $lastName') -and $dg.Contains('$lastHead = Get-ThornswoodLastRecipeHead'))
    Yes 'Deploy-Gamemode takes the places between full and light plugins from the order it was built against, and stops on any other' (
        $dg.Contains('$rs = Get-ThornswoodRecordedSequence ([string[]]$wanted) ([string[]]$lastOrder)') -and
        $dg.Contains('$so = Get-ThornswoodServerOrder $sequence') -and $dg.Contains('throw "$lastName was built against another load order"'))
} finally {
    $env:THORNSWOOD_TEST_SERVER_DIR = ''
    try { Remove-Item -LiteralPath $Scratch -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}
Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
