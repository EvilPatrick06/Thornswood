<#
  test-collection-revision-2.ps1

      pwsh -NoProfile -File .\tests\test-collection-revision-2.ps1
      pwsh -NoProfile -File .\tests\test-collection-revision-2.ps1 -Offline

  docs\COLLECTION-REVISION-2.md, the checklist for the Vortex pass that cuts
  collection revision 2, and scripts\mods\Check-CleanInstall.ps1, the check a
  person runs after a clean install of it. Issue #476.

  WHY. The checklist writes down the exact plugin order a clean install must
  land in, and the order that decides whether anybody gets in is the one the
  server hands out. A written order drifts the day a plugin is added and
  nobody edits the page. So this reads the page's table against the truth,
  every source it can reach:
    - both servers' manifests, over plain HTTP (live on 3000, dev on 7788, the
      address from scripts\vps\vps.json). THIS PART TALKS TO THE VPS: it only
      reads the manifest a launcher reads. -Offline leaves it out.
    - the built server settings on the shipping machine
      (Where.ps1 ServerSettings), which Deploy-DevGamemode.ps1 sends.
  A source that is not there says SKIP. One that is there and disagrees with
  the table is a FAIL naming the first position where they part.

  It also checks the page against itself (every rule it adds ties a plugin to
  the one right before it in the table, every rule it removes contradicts the
  table) and runs Check-CleanInstall.ps1 as a child process against its own
  plugin files, lists and manifests, for each kind of difference it must name,
  and proves it wrote nothing.
#>
[CmdletBinding()]
param(
    [string]$DocPath,
    [string]$CheckPath,
    [switch]$Offline,
    # Where the fixtures are built. Default: the system temp folder.
    [string]$Scratch
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
$Repo = Split-Path -Parent $Here
if (-not $DocPath) { $DocPath = Join-Path $Repo 'docs\COLLECTION-REVISION-2.md' }
if (-not $CheckPath) { $CheckPath = Join-Path $Repo 'scripts\mods\Check-CleanInstall.ps1' }
if (-not $Scratch) { $Scratch = [IO.Path]::GetTempPath() }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Skip([string]$what) { Write-Host "SKIP  $what" }
function Finish {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}
function Same([string]$a, [string]$b) { return [string]::Equals($a, $b, [StringComparison]::OrdinalIgnoreCase) }

# ------------------------------------------------------------------ the page --
Yes 'docs\COLLECTION-REVISION-2.md exists' (Test-Path -LiteralPath $DocPath)
Yes 'scripts\mods\Check-CleanInstall.ps1 exists' (Test-Path -LiteralPath $CheckPath)
if (-not (Test-Path -LiteralPath $DocPath) -or -not (Test-Path -LiteralPath $CheckPath)) { Finish }

$doc = [IO.File]::ReadAllText($DocPath, [Text.Encoding]::UTF8)
$docLines = $doc -split "`r`n|`n"

# The order table sits between two markers, one row per position.
$start = [Array]::IndexOf($docLines, '<!-- order:start -->')
$end = [Array]::IndexOf($docLines, '<!-- order:end -->')
Yes 'the page marks where its order table starts and ends' ($start -ge 0 -and $end -gt $start)
$order = New-Object Collections.Generic.List[string]
$positionsRight = $true
if ($start -ge 0 -and $end -gt $start) {
    foreach ($l in $docLines[($start + 1)..($end - 1)]) {
        $m = [regex]::Match($l, '^\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|')
        if (-not $m.Success) { continue }
        if ([int]$m.Groups[1].Value -ne $order.Count + 1) { $positionsRight = $false }
        [void]$order.Add($m.Groups[2].Value)
    }
}
Yes ("the table has rows ({0})" -f $order.Count) ($order.Count -gt 5)
Yes 'the table numbers its positions 1, 2, 3 and on with no gap' $positionsRight
$dupes = @($order | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt 1 | ForEach-Object Name)
Yes ('no plugin is in the table twice' + $(if ($dupes) { ' (' + ($dupes -join ', ') + ')' })) ($dupes.Count -eq 0)
$masters = @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm')
$mastersFirst = $order.Count -ge 5
for ($i = 0; $i -lt 5 -and $mastersFirst; $i++) { if (-not (Same $order[$i] $masters[$i])) { $mastersFirst = $false } }
Yes 'the table starts with the five base masters in the game''s order' $mastersFirst

function PositionOf([string]$name) {
    for ($i = 0; $i -lt $order.Count; $i++) { if (Same $order[$i] $name) { return $i + 1 } }
    return 0
}

# The rule table: | Plugin | Rule to remove | Rule to add |, each rule written
# "load after <plugin>" or "none".
$ruleRows = 0
foreach ($l in $docLines) {
    $m = [regex]::Match($l, '^\|\s*([^|]+?\.es[mpl])\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|\s*$')
    if (-not $m.Success) { continue }
    $p = $m.Groups[1].Value
    $remove = $m.Groups[2].Value
    $add = $m.Groups[3].Value
    if (-not ($remove -match '^(none|load after .+)$' -and $add -match '^(none|load after .+)$')) { continue }
    $ruleRows++
    $at = PositionOf $p
    Yes "the rule table's $p is in the order table" ($at -gt 0)
    if ($add -match '^load after (.+)$') {
        $prev = $Matches[1].Trim()
        $pa = PositionOf $prev
        Yes "$p gets 'load after $prev', the plugin right before it in the table ($pa then $at)" ($pa -gt 0 -and $pa + 1 -eq $at)
    }
    if ($remove -match '^load after (.+)$') {
        $wrong = $Matches[1].Trim()
        $pw = PositionOf $wrong
        Yes "$p loses 'load after $wrong', which the table contradicts ($wrong is at $pw, after $at)" ($pw -gt $at)
    }
}
Yes ("the page has a rule table ({0} rows)" -f $ruleRows) ($ruleRows -gt 0)

Yes 'the page tells the person to run Check-CleanInstall.ps1' ($doc -match 'scripts\\mods\\Check-CleanInstall\.ps1')
Yes 'the page names this harness as what keeps it true' ($doc -match 'tests\\test-collection-revision-2\.ps1')
Yes 'the page tells the person to leave "Skip plugin rules" off' ($doc -match 'Skip\s+plugin rules')
Yes 'the page has no em dash' (-not $doc.Contains([string][char]0x2014))
Yes 'the page never says player' (-not ($doc -match '\bplayers?\b'))

# -------------------------------------------------------- against the truth --
function Compare-Order([string]$label, [string[]]$truth) {
    $n = [Math]::Max($truth.Count, $order.Count)
    $at = -1
    for ($i = 0; $i -lt $n; $i++) {
        if ($i -ge $truth.Count -or $i -ge $order.Count -or -not (Same $truth[$i] $order[$i])) { $at = $i; break }
    }
    $why = ''
    if ($at -ge 0) {
        $t = if ($at -lt $truth.Count) { $truth[$at] } else { '(nothing)' }
        $o = if ($at -lt $order.Count) { $order[$at] } else { '(nothing)' }
        $why = " (they part at position $($at + 1): $label has $t, the page has $o)"
    }
    Yes ("the page's order is $label's order, {0} plugins{1}" -f $truth.Count, $why) ($at -lt 0)
}

$sources = 0
if ($Offline) {
    Skip 'the servers: -Offline'
} else {
    $vpsPath = Join-Path $Repo 'scripts\vps\vps.json'
    $cfg = Get-Content -LiteralPath $vpsPath -Raw | ConvertFrom-Json
    foreach ($w in @('live', 'dev')) {
        $gamePort = if ($w -eq 'live') { [int]$cfg.livePort } else { [int]$cfg.devPort }
        $rp = if ($gamePort -eq 7777) { 3000 } else { $gamePort + 1 }
        $url = "http://$($cfg.address):$rp/api/servers/thornswood/manifest.json"
        $json = $null
        try {
            $req = [Net.WebRequest]::Create($url)
            $req.Timeout = 8000
            $req.ReadWriteTimeout = 8000
            $res = $req.GetResponse()
            try { $sr = New-Object IO.StreamReader($res.GetResponseStream()); $json = $sr.ReadToEnd(); $sr.Close() } finally { $res.Close() }
        } catch { $json = $null }
        $names = @()
        if ($json) { try { $names = @((($json | ConvertFrom-Json).mods) | ForEach-Object { [string]$_.filename } | Where-Object { $_ }) } catch { $names = @() } }
        if ($names.Count -eq 0) { Skip "the $w server's manifest ($url) did not answer"; continue }
        $sources++
        Compare-Order "the $w server" ([string[]]$names)
    }
}
$settings = ''
try { $settings = & (Join-Path $Repo 'scripts\release\Where.ps1') ServerSettings } catch { $settings = '' }
if ($settings -and (Test-Path -LiteralPath $settings)) {
    $lo = @(((Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).loadOrder) | ForEach-Object { [IO.Path]::GetFileName(([string]$_).Replace('/', '\')) } | Where-Object { $_ })
    if ($lo.Count) { $sources++; Compare-Order 'the built server settings' ([string[]]$lo) }
    else { Skip "the built server settings at $settings name no load order" }
} else {
    Skip 'the built server settings: not on this machine'
}
if ($sources -eq 0) { Skip 'nothing to compare the page''s order with here; the nightly run on the VPS reads the servers' }

# ------------------------------------------------ Check-CleanInstall itself --
$root = Join-Path $Scratch ('thornswood-cleaninstall-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$shell = (Get-Process -Id $PID).Path

# A plugin file with a TES4 header: flags 0x1 a master, 0x200 the ESL flag
# that makes it light. $pad makes two files of one size with other bytes.
function Plugin([string]$dir, [string]$name, [uint32]$flags, [byte]$pad = 0) {
    $b = New-Object byte[] 32
    [Text.Encoding]::ASCII.GetBytes('TES4').CopyTo($b, 0)
    [BitConverter]::GetBytes([uint32]8).CopyTo($b, 4)
    [BitConverter]::GetBytes($flags).CopyTo($b, 8)
    for ($i = 24; $i -lt 32; $i++) { $b[$i] = $pad }
    [IO.File]::WriteAllBytes((Join-Path $dir $name), $b)
}
# The zlib crc32, in 64 bit arithmetic: PowerShell reads 0xFFFFFFFF as the
# 32 bit -1, so the constants are spelled as positive 64 bit numbers.
function Crc([byte[]]$bytes) {
    [int64]$all = 4294967295
    [int64]$poly = 3988292384
    [int64]$c = $all
    foreach ($x in $bytes) {
        $c = $c -bxor [int64]$x
        for ($k = 0; $k -lt 8; $k++) { if ($c -band 1) { $c = $poly -bxor ($c -shr 1) } else { $c = $c -shr 1 } }
    }
    return [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32](($c -bxor $all) -band $all)), 0)
}
# A manifest the way the server writes it: every plugin in order, with size
# and crc32 (signed), the base masters with made up numbers the check skips.
function Manifest([string]$path, [string]$data, [string[]]$names) {
    $mods = foreach ($n in $names) {
        $p = Join-Path $data $n
        if ([IO.File]::Exists($p)) { $b = [IO.File]::ReadAllBytes($p); [ordered]@{ crc32 = (Crc $b); filename = $n; size = $b.Length } }
        else { [ordered]@{ crc32 = 1; filename = $n; size = 1 } }
    }
    $doc = [ordered]@{ versionMajor = 1; mods = @($mods); loadOrder = @($names) }
    [IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
}
function PluginList([string]$path, [string[]]$lines) {
    $text = (@('# This file is used by Skyrim to keep track of your downloaded content.') + $lines) -join "`r`n"
    [IO.File]::WriteAllText($path, $text + "`r`n", (New-Object Text.UTF8Encoding($false)))
}
function Run([string[]]$argList) {
    $ErrorActionPreference = 'Continue'
    $all = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $CheckPath) + $argList
    $out = & $shell @all 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
function Has([string]$text, [string]$part) { return ($text.IndexOf($part, [StringComparison]::Ordinal) -ge 0) }
function Snapshot([string]$dir) {
    return ((Get-ChildItem -LiteralPath $dir -Recurse -File | Sort-Object FullName | ForEach-Object {
        $_.FullName + '|' + $_.Length + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}

try {
    $data = Join-Path $root 'Data'
    $null = New-Item -ItemType Directory -Force -Path $data
    # Real names from the table, a slice of it.
    Plugin $data 'Water for ENB.esm' 0x1
    Plugin $data 'RaceCompatibility.esm' 0x1
    Plugin $data 'LSFX-SSE-Audiosettings.esp' 0x200
    Plugin $data 'aaaGraniteHill.esp' 0
    Plugin $data 'ElysiumEstateSSE.esp' 0
    Plugin $data 'ElysiumEstate.esp' 0
    Plugin $data 'Triumvirate - Mage Archetypes.esp' 0
    Plugin $data 'RaceMenu.esp' 0x200
    Plugin $data 'CBBE.esp' 0
    Plugin $data 'Thornswood-Content.esp' 0
    Plugin $data 'Immersive Patrols II.esp' 0
    Plugin $data 'AHZmoreHUD.esp' 0
    Plugin $data 'Playable Rieklings.esp' 0
    Plugin $data 'Expressive Facegen Morphs.esl' 0
    # What an Anniversary Edition copy of Skyrim has in Data (#479): two full
    # Creation Club masters and a light one.
    Plugin $data 'ccBGSSSE001-Fish.esm' 0x1
    Plugin $data 'ccBGSSSE025-AdvDSGS.esm' 0x1
    Plugin $data 'ccQDRSSE001-SurvivalMode.esl' 0x200

    $server = @('Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm',
                'Water for ENB.esm', 'RaceCompatibility.esm', 'aaaGraniteHill.esp', 'ElysiumEstateSSE.esp',
                'Triumvirate - Mage Archetypes.esp', 'Thornswood-Content.esp', 'Immersive Patrols II.esp',
                'AHZmoreHUD.esp', 'Playable Rieklings.esp')
    $manifest = Join-Path $root 'manifest.json'
    Manifest $manifest $data $server

    # The list a clean install should write: light plugins wherever LOOT put
    # them, a switched off plugin, the server's full plugins in its order.
    $good = @('*Water for ENB.esm', '*Expressive Facegen Morphs.esl', '*RaceCompatibility.esm', '*LSFX-SSE-Audiosettings.esp',
              '*aaaGraniteHill.esp', '*ElysiumEstateSSE.esp', '*Triumvirate - Mage Archetypes.esp', '*RaceMenu.esp', 'CBBE.esp',
              '*Thornswood-Content.esp', '*Immersive Patrols II.esp', '*AHZmoreHUD.esp', '*Playable Rieklings.esp')
    $list = Join-Path $root 'plugins.txt'
    PluginList $list $good
    $before = Snapshot $root

    $r = Run @('-List', $list, '-Data', $data, '-Manifest', $manifest)
    Yes 'the server''s order with light plugins anywhere and a plugin switched off: PASS, exit 0' ($r.Code -eq 0 -and (Has $r.Out 'PASS  all 14 positions'))

    # CBBE.esp switched on: a full plugin the server does not load.
    PluginList $list ($good | ForEach-Object { if ($_ -eq 'CBBE.esp') { '*CBBE.esp' } else { $_ } })
    $r = Run @('-List', $list, '-Data', $data, '-Manifest', $manifest)
    Yes 'CBBE.esp switched on: exit 1, named as extra at its position' ($r.Code -eq 1 -and (Has $r.Out 'extra         CBBE.esp (position 11 here)'))
    Yes '...and nothing else is called out of place for it' (-not (Has $r.Out 'out of place'))

    # Somebody who owns the Anniversary upgrade (#479): its Creation Club
    # plugins switched on, full and light, in Data and not, before and among
    # the server's. Thornswood's own game folder leaves them out, so the check
    # does not count them and it is still a PASS.
    PluginList $list (@('*ccBGSSSE001-Fish.esm', '*ccQDRSSE001-SurvivalMode.esl', '*ccASVSSE001-ALMSIVI.esm') + $good[0..3] +
                      @('*ccBGSSSE025-AdvDSGS.esm') + $good[4..($good.Count - 1)])
    $r = Run @('-List', $list, '-Data', $data, '-Manifest', $manifest)
    Yes 'Anniversary Creation Club plugins switched on as well: still PASS, exit 0' ($r.Code -eq 0 -and (Has $r.Out 'PASS  all 14 positions'))
    Yes '...and it says how many it left out and why' (Has $r.Out '4 of them Creation Club plugins, not counted')
    Yes '...and none is called extra' (-not (Has $r.Out 'extra         '))

    # Revision 1's Elysium Estate: the other plugin name.
    PluginList $list ($good | ForEach-Object { if ($_ -eq '*ElysiumEstateSSE.esp') { '*ElysiumEstate.esp' } else { $_ } })
    $r = Run @('-List', $list, '-Data', $data, '-Manifest', $manifest)
    Yes 'ElysiumEstate.esp in place of ElysiumEstateSSE.esp: the server''s is missing, not in the list' ($r.Code -eq 1 -and (Has $r.Out 'missing       ElysiumEstateSSE.esp (server position 9): it is not in the list at all'))
    Yes '...and ElysiumEstate.esp is extra' (Has $r.Out 'extra         ElysiumEstate.esp')

    # Switched off.
    PluginList $list ($good | ForEach-Object { if ($_ -eq '*AHZmoreHUD.esp') { 'AHZmoreHUD.esp' } else { $_ } })
    $r = Run @('-List', $list, '-Data', $data, '-Manifest', $manifest)
    Yes 'AHZmoreHUD.esp switched off: missing, and it says to switch it on' ($r.Code -eq 1 -and (Has $r.Out 'missing       AHZmoreHUD.esp (server position 13): it is in the list but switched off'))

    # The gap revision 1 left: AHZmoreHUD above Immersive Patrols II.
    $swapped = @($good | Where-Object { $_ -ne '*AHZmoreHUD.esp' })
    $at = [Array]::IndexOf($swapped, '*Immersive Patrols II.esp')
    $swapped = @($swapped[0..($at - 1)]) + '*AHZmoreHUD.esp' + @($swapped[$at..($swapped.Count - 1)])
    PluginList $list $swapped
    $r = Run @('-List', $list, '-Data', $data, '-Manifest', $manifest)
    $oop = ([regex]::Matches($r.Out, 'out of place')).Count
    Yes 'AHZmoreHUD.esp above Immersive Patrols II.esp: exit 1, one plugin out of place' ($r.Code -eq 1 -and $oop -eq 1)
    Yes '...naming where the server has it and what it loads after' ((Has $r.Out 'on the server, where it loads right after') -and ((Has $r.Out 'AHZmoreHUD.esp is at position') -or (Has $r.Out 'Immersive Patrols II.esp is at position')))
    Yes '...and nothing missing or extra' (-not (Has $r.Out 'missing       ') -and -not (Has $r.Out 'extra         '))

    # Enabled twice.
    PluginList $list ($good + '*aaaGraniteHill.esp')
    $r = Run @('-List', $list, '-Data', $data, '-Manifest', $manifest)
    Yes 'a plugin switched on on two lines: named as twice' ($r.Code -eq 1 -and (Has $r.Out 'twice         aaaGraniteHill.esp'))

    PluginList $list $good

    # The wrong bytes: another size, then the same size with other bytes.
    $wrongData = Join-Path $root 'WrongData'
    $null = New-Item -ItemType Directory -Force -Path $wrongData
    Get-ChildItem -LiteralPath $data -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $wrongData }
    [IO.File]::WriteAllBytes((Join-Path $wrongData 'Thornswood-Content.esp'), [byte[]](([IO.File]::ReadAllBytes((Join-Path $data 'Thornswood-Content.esp'))) + [byte]7))
    Plugin $wrongData 'Playable Rieklings.esp' 0 9
    $r = Run @('-List', $list, '-Data', $wrongData, '-Manifest', $manifest)
    Yes 'Thornswood-Content.esp one byte longer: a wrong file, with both sizes' ($r.Code -eq 1 -and (Has $r.Out 'wrong file    Thornswood-Content.esp is 33 bytes here and 32 on the server'))
    Yes 'Playable Rieklings.esp the same size with other bytes: a wrong file by its bytes' (Has $r.Out 'wrong file    Playable Rieklings.esp is the server''s size, but not its bytes')
    Yes '...and the order is not blamed for it' (-not (Has $r.Out 'out of place'))

    # A plugin the server loads as full that is light here.
    Plugin $wrongData 'Thornswood-Content.esp' 0x200
    $r = Run @('-List', $list, '-Data', $wrongData, '-Manifest', $manifest)
    Yes 'Thornswood-Content.esp light here: missing, because the file is light and the server''s is not' ($r.Code -eq 1 -and (Has $r.Out 'missing       Thornswood-Content.esp (server position 11): the file in Data is light'))

    # Switched on and not deployed.
    $thin = Join-Path $root 'ThinData'
    $null = New-Item -ItemType Directory -Force -Path $thin
    Get-ChildItem -LiteralPath $data -File | Where-Object Name -ne 'Immersive Patrols II.esp' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $thin }
    $r = Run @('-List', $list, '-Data', $thin, '-Manifest', $manifest)
    Yes 'Immersive Patrols II.esp switched on and not in Data: missing, deploy in Vortex' ($r.Code -eq 1 -and (Has $r.Out 'missing       Immersive Patrols II.esp (server position 12): it is switched on, but the file is not in Data'))

    # Could not check: exit 2, never a PASS.
    $r = Run @('-List', (Join-Path $root 'nope.txt'), '-Data', $data, '-Manifest', $manifest)
    Yes 'no plugin list: STOP, exit 2' ($r.Code -eq 2 -and (Has $r.Out 'STOP') -and -not (Has $r.Out 'PASS'))
    $r = Run @('-List', $list, '-Data', (Join-Path $root 'NoData'), '-Manifest', $manifest)
    Yes 'no Data folder: STOP, exit 2' ($r.Code -eq 2 -and (Has $r.Out 'STOP'))
    $notManifest = Join-Path $root 'not-a-manifest.json'
    [IO.File]::WriteAllText($notManifest, '{"hello":1}')
    $r = Run @('-List', $list, '-Data', $data, '-Manifest', $notManifest)
    Yes 'a file that is not a manifest: nothing compared, exit 2, no PASS' ($r.Code -eq 2 -and -not (Has $r.Out 'PASS'))
    Remove-Item -LiteralPath $notManifest -Force

    # It only reads. Everything the harness itself changed since the snapshot
    # is under WrongData and ThinData, so those are left out of the second look.
    Remove-Item -LiteralPath $wrongData, $thin -Recurse -Force
    Yes 'Check-CleanInstall.ps1 wrote nothing: every fixture file is as it was' ((Snapshot $root) -eq $before)
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -EA SilentlyContinue
}

# The script is plain ASCII, like the rest of scripts\, so Windows PowerShell
# 5.1 reads it the same as PowerShell 7.
$bytes = [IO.File]::ReadAllBytes($CheckPath)
Yes 'Check-CleanInstall.ps1 is plain ASCII' (@($bytes | Where-Object { $_ -gt 127 }).Count -eq 0)

Finish
