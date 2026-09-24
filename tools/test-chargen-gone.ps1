<#
  test-chargen-gone.ps1

      pwsh -NoProfile -File .\tools\test-chargen-gone.ps1

  The retired dresser, thornswood-chargen.js, is out of the repo, nothing that
  installs or ships the game names it, and the next pack takes it off the
  machines that already have it.

  WHY. To Do List entry 127. On 20 September the dresser was found putting the
  best armour it could find into every empty slot five seconds after any pack
  change, which is Patrick's "it is auto equipping things sometimes, like a
  hat". It was retired that day (c529c67) to print one line and do nothing, and
  the entry left the rest as "delete the file and the four scripts that name it
  (Install-Emotes, Install-Thornswood, Revert, Check-Chargen), which is a small
  tidy".

  There were two copies, not one. tools\ts-plugins is where Ship takes the
  plugins from. tools\emotes is where Install-Emotes.ps1 and Revert.ps1 took it
  from, and that copy was the dresser from BEFORE it was retired, with no
  whose-game gate and its equipItem call intact, so running either script put
  the hat back on people.

  What it checks:
    1. Neither copy is in the repo, and no script, launcher source or plugin
       under tools names it. Harnesses are left out of that search, since
       this one has to.
    2. Go.ps1's sweep of the plugin folder, lifted by text and run against a
       scratch folder, takes a leftover copy out and leaves ours and the
       client alone. Ship runs Go.ps1 into the shipping machine's game folder
       before it scans, so this is what takes it out of the folder a pack is
       made from.
    3. Publish-Update.ps1's diff and its collection filter, lifted by text the
       way test-ship-rules.ps1 does, list it as removed when the last pack
       carried it, and the pack writes that list into delete.txt. Updater
       deletes every line of delete.txt and hands the same list to
       Keep.Forget, so the kept copy under Profile\Keep does not come back at
       the next Play.
    4. On this machine, where it can: which publish baselines carry it, and
       whether the launcher's record of what Vortex deployed claims it. A
       file the record marks as the collection's is dropped from the removal
       list, which is how map.swf never left anybody's machine on 22 Sep.

  Read only, apart from a scratch folder under TEMP that it removes.
#>
[CmdletBinding()]
param([string]$Root = 'C:\Thornswood')

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

$name = 'thornswood-chargen.js'
$rel  = 'Data\Platform\Plugins\' + $name

# ---- 1. the file and every name of it ------------------------------------------
Yes 'tools\ts-plugins no longer holds the retired dresser' (-not (Test-Path -LiteralPath (Join-Path $Here "ts-plugins\$name")))
Yes 'and tools\emotes no longer holds the unretired copy Install-Emotes and Revert installed' (-not (Test-Path -LiteralPath (Join-Path $Here "emotes\$name")))

$sources = @()
$sources += @(Get-ChildItem -LiteralPath $Here -File | Where-Object { $_.Extension -in '.ps1', '.js', '.cs', '.xaml' })
foreach ($d in 'app', 'ts-plugins', 'ts-ui', 'emotes', 'launcher') {
    $p = Join-Path $Here $d
    if (Test-Path -LiteralPath $p) {
        $sources += @(Get-ChildItem -LiteralPath $p -File -Recurse | Where-Object { $_.Extension -in '.ps1', '.js', '.cs', '.xaml', '.html' })
    }
}
$sources = @($sources | Where-Object { $_.Name -notlike 'test-*' })
$naming = @($sources | Where-Object { ([IO.File]::ReadAllText($_.FullName)).IndexOf($name, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
Yes ("no script, launcher source or plugin under tools names it ({0} files read)" -f $sources.Count) ($naming.Count -eq 0)
foreach ($n in $naming) { Write-Host ('      still named in ' + $n.FullName.Substring($Here.Length).TrimStart('\')) }

# Not $keep: the Go.ps1 block lifted below has a $keep of its own.
$keepCs = [IO.File]::ReadAllText((Join-Path $Here 'app\Keep.cs'))
Yes 'Keep.cs still calls any thornswood-*.js in the plugin folder ours, so a copy not yet removed is never parked' ($keepCs.IndexOf('name.StartsWith("thornswood-"', [StringComparison]::Ordinal) -ge 0)

# ---- 2. Go.ps1 takes a leftover copy out of the game folder ---------------------
$go = [IO.File]::ReadAllText((Join-Path $Here 'Go.ps1'))
$sweep = [regex]::Match($go, '(?ms)^\$keep = @\(''skymp5-client\.js''.*?^\}\r?$')
Yes 'Go.ps1 still builds its keep list from tools\ts-plugins and sweeps the plugin folder against it' ($sweep.Success -and $sweep.Value.Contains('Remove-Item -LiteralPath $s.FullName'))

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('ts-chargen-gone-' + [Diagnostics.Process]::GetCurrentProcess().Id)
$ours = @(Get-ChildItem -LiteralPath (Join-Path $Here 'ts-plugins') -Filter *.js -File | ForEach-Object { $_.Name })
try {
    if ($sweep.Success) {
        $plugins = Join-Path $scratch 'Data\Platform\Plugins'
        New-Item -ItemType Directory -Force -Path $plugins | Out-Null
        $there = @('skymp5-client.js', 'skymp5-client-settings.txt', $name) + $ours
        foreach ($n in ($there | Select-Object -Unique)) { [IO.File]::WriteAllText((Join-Path $plugins $n), 'x') }
        $plSrc = Join-Path $Here 'ts-plugins'
        function Bad($t) { }
        . ([scriptblock]::Create($sweep.Value))
        $left = @(Get-ChildItem -LiteralPath $plugins -File | ForEach-Object { $_.Name })
        Yes 'the sweep takes a leftover thornswood-chargen.js out of the game folder' ($left -notcontains $name)
        Yes ('and leaves the client, its settings and our {0} plugin(s) where they are' -f $ours.Count) (
            ($left -contains 'skymp5-client.js') -and ($left -contains 'skymp5-client-settings.txt') -and
            (@($ours | Where-Object { $left -notcontains $_ }).Count -eq 0))
    }
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

# ---- 3. the next pack lists it as removed ----------------------------------------
. (Join-Path $Here 'Ship-Rules.ps1')
Yes 'Ship-Rules does not call it another server''s or one machine''s, which would keep it out of delete.txt' (-not (Test-ShipMachine $rel))
Yes 'and it is not a runtime path' (-not (Test-ShipRuntime $rel))

$pub = [IO.File]::ReadAllText((Join-Path $Here 'Publish-Update.ps1'))
$tm   = [regex]::Match($pub, '(?m)^function Test-Machine\(.*$')
$fc   = [regex]::Match($pub, '(?ms)^function Test-FromCollection\(.*?^\}\r?$')
$dso  = [regex]::Match($pub, '(?m)^\$DevShipsOurs = .*$')
$diff = [regex]::Match($pub, '(?ms)^\$changed = @\(\); \$removed = @\(\)\r?$.*?^\$removed\s+= @\(\$removed \| Where-Object \{[^\r\n]*Test-Machine[^\r\n]*\r?$')
$coll = [regex]::Match($pub, '(?ms)^\$collectionRemovals = .*?^\}\r?$')
Yes 'Publish-Update.ps1 still has Test-Machine, Test-FromCollection, the diff and the collection filter to lift' (
    $tm.Success -and $fc.Success -and $dso.Success -and $diff.Success -and $coll.Success)
Yes 'and still writes every removal into delete.txt' ($pub.Contains('foreach ($rel in $removed) { $sw.WriteLine(($rel -replace ''\\'', ''/'')) }'))
if (-not ($tm.Success -and $fc.Success -and $dso.Success -and $diff.Success -and $coll.Success)) { Done }
. ([scriptblock]::Create($tm.Value))
. ([scriptblock]::Create($fc.Value))
. ([scriptblock]::Create($dso.Value))

# A dev pack, as Ship -Channel dev makes one. The last pack carried the dresser
# and our plugins; the folder now has our plugins and not the dresser. The
# collection record is a made up one that claims a texture and nothing of ours.
$Dev = $true
$vortexFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
[void]$vortexFiles.Add('Data\textures\gone\collection.dds')
$prev = @{}
$prev[$rel] = '11654:639252007700000000'
$prev['Data\textures\gone\collection.dds'] = '10:1'
$now = @{}
foreach ($o in $ours) {
    $prev['Data\Platform\Plugins\' + $o] = '10:1'
    $now['Data\Platform\Plugins\' + $o] = '10:1'
}
. ([scriptblock]::Create($diff.Value))
. ([scriptblock]::Create($coll.Value))
Yes 'the dev pack lists thornswood-chargen.js as removed, so its delete.txt names it' ($removed -contains $rel)
Yes 'and removes none of our plugins that are still there' (@($removed | Where-Object { $_ -like 'Data\Platform\Plugins\thornswood-*' -and $_ -ne $rel }).Count -eq 0)
Yes 'the lifted collection filter is live: a collection file that went is not removed' ($removed -notcontains 'Data\textures\gone\collection.dds')

$upd = [IO.File]::ReadAllText((Join-Path $Here 'app\Updater.cs'))
Yes 'Updater deletes each delete.txt line from the game folder and remembers it as removed' (
    $upd.Contains('ar.GetEntry("delete.txt")') -and $upd.Contains('File.Delete(target)') -and $upd.Contains('removed.Add(rel);'))
Yes 'and hands that list to Keep.Forget, so Keep does not put the file back at the next Play' ($upd.Contains('Keep.Forget(removed);'))
Yes 'Keep.Forget takes a .js under Data\Platform\Plugins' ($keepCs.Contains('rel.StartsWith(PluginDir + "\\", StringComparison.OrdinalIgnoreCase)') -and $keepCs.Contains('return rel.EndsWith(".js", StringComparison.OrdinalIgnoreCase);'))

# ---- 4. measured on this machine, where it can be -------------------------------
$stateDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Thornswood' } else { '' }
foreach ($ch in @(
    @{ Label = 'main'; Base = 'published.json';     Root = $Root },
    @{ Label = 'dev';  Base = 'published-dev.json'; Root = ($Root + '-DevBuild') }
)) {
    $base = if ($stateDir) { Join-Path $stateDir $ch.Base } else { '' }
    if ($base -and (Test-Path -LiteralPath $base)) {
        $keys = @(((Get-Content -LiteralPath $base -Raw) -replace '^\uFEFF', '' | ConvertFrom-Json).PSObject.Properties.Name)
        if ($keys -contains $rel) {
            Write-Host ("      the {0} baseline carries {1}, so the next {0} pack lists it as removed once Go.ps1 has swept it" -f $ch.Label, $name)
        } else {
            Write-Host ("      the {0} baseline does not carry {1}; a {0} pack will not list it" -f $ch.Label, $name)
        }
    } else {
        Write-Host ("SKIP  no {0} publish baseline on this machine" -f $ch.Label)
    }
    $pd = Join-Path $ch.Root 'Profile'
    $rec = Join-Path $pd 'OwnGame\files.txt'
    if (Test-Path -LiteralPath $rec) {
        $vortexFiles = Get-ShipOwnGameCollection $pd
        $Dev = ($ch.Label -eq 'dev')
        Yes ("{0}: the launcher's record in {1} does not call it the collection's, so the real filter keeps the removal" -f $ch.Label, $rec) (-not (Test-FromCollection $rel))
    } else {
        Write-Host ("SKIP  no {0} on this machine" -f $rec)
    }
    $live = Join-Path $ch.Root ('Game\' + $rel)
    if (Test-Path -LiteralPath $live) {
        Write-Host ("      {0} is still in {1}; the next {2} Ship sweeps it before it scans" -f $name, (Join-Path $ch.Root 'Game'), $ch.Label)
    }
}

Done
