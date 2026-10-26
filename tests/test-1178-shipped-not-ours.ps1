<#
  test-1178-shipped-not-ours.ps1

      pwsh -NoProfile -File .\tests\test-1178-shipped-not-ours.ps1

  Other authors' loose files the packs and the installer handed out before the
  scrub of 29 Sep 2026 leave every install they reached (#1178).

  WHY THIS EXISTS. The scrub (#1257) took 166 files of other authors (RaceMenu's
  loose interface, IED, MCM Helper's old scripts, the other server's haybale,
  outfit meshes nobody gave us) out of every pack and every record. #1261, a
  few days later, made a release turn another author's file the previous
  record named into a gone line with the sha256 we shipped. But the records
  had already stopped naming these, so no record ever carried them as gone,
  and every install the old packs reached kept them: on 12 Oct the main
  install on the shipping machine still held all 166, 67.6 MB.

  records\shipped-not-ours.json lists them with the sha256 we shipped, and
  Publish-Update carries each into every record as a gone line. This holds:
    1. the list: it reads as its record kind, every path is somebody else's by
       Ship-Rules and none is Bethesda's, one machine's or a backup (those never
       become a gone line, and the record guards would stop the release);
    2. Publish-Update's block, lifted out between its markers and run against
       the real list: every file becomes gone by its sha256, a release that
       ships one of the paths keeps it, Ship-Rules' delete list keeps its
       "always", the list going forward does not undo it, and the record
       guards let the result through;
    3. a missing or broken list stops the release.
  The launcher's half (delete only when the bytes match, and never a path
  Vortex deploys) is tests\test-record-sync.ps1's (#1261).

  Read only apart from its own scratch folder. Never connects to anything.
#>
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$Release = Join-Path $Repo 'scripts\release'
. (Join-Path $Release 'Ship-Rules.ps1')

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Get-Block([string]$src, [string]$name) {
    $a = $src.IndexOf("# ==== thornswood $name ====")
    $b = $src.IndexOf("# ==== end thornswood $name ====")
    if ($a -lt 0 -or $b -le $a) { return $null }
    return $src.Substring($a, $b - $a)
}

# ---- 1. the list ----------------------------------------------------------------
Write-Host ''; Write-Host 'the list'
$listPath = Join-Path $Repo 'records\shipped-not-ours.json'
$doc = Read-ThornswoodRecord -Path $listPath -Kind shipped-not-ours
$files = [ordered]@{}
foreach ($p in @($doc.files.PSObject.Properties)) { $files[$p.Name] = [string]$p.Value.sha256 }
Yes ('records\shipped-not-ours.json reads as its kind and lists the 166 files measured on 12 Oct ({0})' -f $files.Count) ($files.Count -eq 166)
Yes ('  67.6 MB of them ({0:N1} MB)' -f ((@($doc.files.PSObject.Properties | ForEach-Object { [int64]$_.Value.bytes }) | Measure-Object -Sum).Sum / 1MB)) (
    [Math]::Round((@($doc.files.PSObject.Properties | ForEach-Object { [int64]$_.Value.bytes }) | Measure-Object -Sum).Sum / 1MB, 1) -eq 67.6)
Yes '  the other server''s haybale among them' ($files.Contains('Data\meshes\weapons\kzl\kzl_haybale.nif'))
Yes '  and RaceMenu''s loose menu, IED and MCM Helper''s old scripts' ($files.Contains('Data\Interface\racesex_menu.swf') -and $files.Contains('Data\Scripts\IED.pex') -and $files.Contains('Data\Scripts\MCM.pex'))
$notOurs = @($files.Keys | Where-Object { -not (Test-ShipNotOurs $_) })
Yes ('every one is somebody else''s by Ship-Rules{0}' -f $(if ($notOurs.Count) { ': not ' + ($notOurs -join ', ') } else { '' })) ($notOurs.Count -eq 0)
$never = @($files.Keys | Where-Object { (Test-ShipBethesda $_) -or (Test-ShipOneMachine $_) -or (Test-ShipBackup $_) })
Yes ('  and none is Bethesda''s, one machine''s or a backup, which never become a gone line{0}' -f $(if ($never.Count) { ': ' + ($never -join ', ') } else { '' })) ($never.Count -eq 0)
Yes '  every path is under Data, once' (@($files.Keys | Where-Object { -not $_.StartsWith('Data\') }).Count -eq 0 -and
    @($files.Keys | Group-Object { $_.ToLowerInvariant() } | Where-Object { $_.Count -gt 1 }).Count -eq 0)

# A list the readers cannot trust is refused, naming why.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-1178-' + [Guid]::NewGuid().ToString('N').Substring(0, 10))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    function Why([string]$text) {
        $p = Join-Path $tmp 'list.json'; [IO.File]::WriteAllText($p, $text)
        try { $null = Read-ThornswoodRecord -Path $p -Kind shipped-not-ours; return '' } catch { return $_.Exception.Message }
    }
    $sha = 'a' * 64
    Yes 'a list with no version is refused' ((Why ('{"files":{"Data\\x.nif":{"sha256":"' + $sha + '","bytes":1}}}')) -match 'it has no version')
    Yes 'a file with no sha256 is refused' ((Why '{"version":1,"files":{"Data\\x.nif":{"bytes":1}}}') -match 'has no sha256')
    Yes 'a path outside Data is refused' ((Why ('{"version":1,"files":{"SkyrimSE.exe":{"sha256":"' + $sha + '","bytes":1}}}')) -match 'not a path under Data')
    Yes 'a path that climbs out is refused' ((Why ('{"version":1,"files":{"Data\\..\\SkyrimSE.exe":{"sha256":"' + $sha + '","bytes":1}}}')) -match 'not a path under Data')
    Yes 'a path with forward slashes is refused' ((Why ('{"version":1,"files":{"Data\\meshes/x.nif":{"sha256":"' + $sha + '","bytes":1}}}')) -match 'not a path under Data')
    Yes 'an empty list is refused' ((Why '{"version":1,"files":{}}') -match 'files is missing, empty')

    # ---- 2. Publish-Update's block, run --------------------------------------------
    Write-Host ''; Write-Host 'Publish-Update carries them'
    $pub = [IO.File]::ReadAllText((Join-Path $Release 'Publish-Update.ps1'))
    $block = Get-Block $pub 'shipped not ours gone'
    Yes 'the block is in Publish-Update.ps1' ($null -ne $block)
    if ($block) {
        $at = $pub.IndexOf('# ==== thornswood shipped not ours gone ====')
        Yes '  after the gone list is read from the last record and the #1261 hashes are added' ($at -gt $pub.IndexOf('foreach ($a in $alwaysGone)') -and $at -gt $pub.IndexOf("if (`$m.Success) { `$gone[`$k] = `$m.Groups[1].Value.ToLowerInvariant() }"))
        $carry = $pub.IndexOf("foreach (`$k in @(`$gone.Keys)) { `$now[':gone:' + `$k] = [string]`$gone[`$k] }")
        Yes '  and before the gone list goes into the record' ($carry -gt $at)
        $after = $pub.Substring($at, $carry - $at)
        function Die($m) { throw "STOP $m" }
        function Test-FromCollection($k) { return $true }
        function Test-Vanilla($k) { return $true }
        function Test-Runtime($k) { return $true }
        function Test-OtherServer($k) { return $true }
        # The block and the filter after it, up to the record, with every
        # filter that drops a plain gone line saying yes.
        function Invoke-Gone([hashtable]$nowIn, [hashtable]$goneIn) {
            $script:now = $nowIn; $script:gone = $goneIn
            $now = $script:now; $gone = $script:gone; $Here = $Release
            Invoke-Expression ($after + "`nforeach (`$k in @(`$gone.Keys)) { `$now[':gone:' + `$k] = [string]`$gone[`$k] }")
            return $now
        }
        $now0 = @{ 'Data\Platform\UI\index.html' = '1:aa' }
        $r = Invoke-Gone (@{} + $now0) @{}
        $carried = @($files.Keys | Where-Object { [string]$r[':gone:' + $_] -eq $files[$_] })
        Yes ('a release that ships none of them carries all 166 as gone, each with its sha256 ({0})' -f $carried.Count) ($carried.Count -eq 166)
        Yes '  and nothing else' (@($r.Keys | Where-Object { $_.StartsWith(':gone:') }).Count -eq 166 -and [string]$r['Data\Platform\UI\index.html'] -eq '1:aa')
        $hay = 'Data\meshes\weapons\kzl\kzl_haybale.nif'
        $r = Invoke-Gone @{ $hay = '5:bb' } @{}
        Yes 'a release that ships one of the paths again does not call it gone' (-not $r.ContainsKey(':gone:' + $hay) -and [string]$r[$hay] -eq '5:bb' -and @($r.Keys | Where-Object { $_.StartsWith(':gone:') }).Count -eq 165)
        $r = Invoke-Gone (@{} + $now0) @{ 'Data\Scripts\IED.pex' = 'always' }
        Yes 'a path on Ship-Rules'' delete list stays "always"' ([string]$r[':gone:Data\Scripts\IED.pex'] -eq 'always')
        $r = Invoke-Gone (@{} + $now0) @{ 'Data\Scripts\MCM.pex' = 'removed' }
        Yes 'a plain "removed" line from an older record becomes the hash, so a person''s own copy is kept' ([string]$r[':gone:Data\Scripts\MCM.pex'] -eq $files['Data\Scripts\MCM.pex'])
        Yes 'the filter after it keeps every hash, whatever it says of the path' (@($r.Keys | Where-Object { $_.StartsWith(':gone:') }).Count -eq 166)

        # The record guards after it let the result through.
        $full = Invoke-Gone (@{} + $now0) @{}
        foreach ($guardName in "no bethesda in the record", "no one machine's files in the record") {
            $guard = Get-Block $pub $guardName
            $now = $full
            $why = ''
            try { Invoke-Expression $guard } catch { $why = $_.Exception.Message }
            Yes "  and the guard '$guardName' lets the record through" ($null -ne $guard -and $why -eq '')
        }

        # ---- 3. a list that cannot be read stops the release ----------------------
        Write-Host ''; Write-Host 'a list that cannot be read'
        $fakeRel = Join-Path $tmp 'scripts\release'
        New-Item -ItemType Directory -Force -Path $fakeRel, (Join-Path $tmp 'records') | Out-Null
        function Invoke-At([string]$relDir) {
            $now = @{} + $now0; $gone = @{}; $Here = $relDir
            try { Invoke-Expression $after; return '' } catch { return $_.Exception.Message }
        }
        $why = Invoke-At $fakeRel
        Yes 'no list beside the scripts stops the release, saying why' ($why -like 'STOP records\shipped-not-ours.json could not be read*stay in every install*')
        [IO.File]::WriteAllText((Join-Path $tmp 'records\shipped-not-ours.json'), '{"version":1,"files":')
        Yes 'a broken one stops it too' ((Invoke-At $fakeRel) -like 'STOP records\shipped-not-ours.json could not be read*not valid JSON*')
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
