<#
  test-3752-package-stage.ps1

      pwsh -NoProfile -File .\tests\test-3752-package-stage.ps1
      powershell -NoProfile -File .\tests\test-3752-package-stage.ps1

  Issue #3752. Package-Thornswood.ps1 deleted its stage and copied every kept
  file again on every Ship, because only -ReuseStage synced and no Ship passed
  it; that sync compared length and write time only, which misses a front file
  that changed and kept its length (the front's zip gives every file one fixed
  time). A failed zip was built a second time at 7-Zip's slower default level,
  and 7-Zip's exit 1, a file it could not read, counted as a zip.

  This runs scripts\release\Package-Stage.ps1, which the packager dot-sources,
  against a small game folder in a scratch folder: the first build copies
  everything; the second copies nothing; a file changed with the same length
  and the same time is copied, alone; a file that left the build goes with
  its folder; what an earlier build left at the top of the stage goes. Then
  Invoke-PackageZip against a stand-in 7z that notes each call: exit 2 is one
  call, at -mx1, and no archive; exit 1 is no archive either. And it reads
  Package-Thornswood.ps1 for the parts it cannot run (it needs a recorded
  client and the live feed): it uses the stage sync and the one zip, walks the
  stage for nothing it already has, and says the optional packs once.

  Scratch folder only. Nothing reaches the network.
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
. (Join-Path $Repo 'scripts\release\Package-Stage.ps1')

$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-3752-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$sep = [string][IO.Path]::DirectorySeparatorChar
function P([string]$dir, [string]$rel) { return (Join-Path $dir $rel.Replace('\', $sep)) }
function Put([string]$path, [string]$text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}
# The kept files, the way Package-Thornswood's listing makes them.
function Get-Ship([string]$game) {
    $cut = (Get-Item -LiteralPath $game).FullName.TrimEnd($sep).Length + 1
    return @(Get-ChildItem -LiteralPath $game -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{ Rel = $_.FullName.Substring($cut).Replace($sep, '\'); Full = $_.FullName; Len = $_.Length; Time = $_.LastWriteTimeUtc }
    })
}
function Get-Tree([string]$dir) {
    $cut = (Get-Item -LiteralPath $dir).FullName.TrimEnd($sep).Length + 1
    return @(Get-ChildItem -LiteralPath $dir -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($cut).Replace($sep, '\')
        if ($_.PSIsContainer) { "$rel\" } else { $rel + '|' + (Get-PackageStageSha256 $_.FullName) }
    })
}

try {
    $game  = Join-Path $T 'Game'
    $stage = Join-Path $T 'stage'
    $payload = Join-Path $stage 'payload'
    $fixed = [DateTime]::new(2000, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
    $files = [ordered]@{
        'Data\Thornswood.esp'                   = 'plugin one'
        'Data\Platform\UI\build.js'             = 'front AAAA'
        'Data\Platform\UI\assets\a1b2.png'      = 'picture'
        'Data\Scripts\Old\Gone.pex'             = 'leaves the build'
        'Data\SKSE\Plugins\SkyrimPlatform.dll'  = 'client'
    }
    foreach ($k in $files.Keys) { Put (P $game $k) $files[$k] }
    # The front's files carry the front zip's one fixed time.
    foreach ($k in 'Data\Platform\UI\build.js', 'Data\Platform\UI\assets\a1b2.png') { [IO.File]::SetLastWriteTimeUtc((P $game $k), $fixed) }

    # What an earlier build left at the top of the stage.
    Put (Join-Path $stage 'collection.txt') 'from an older build'
    Put (Join-Path $stage 'licences\old-port.txt') 'from an older build'

    # ---- the first build: everything is new
    $r = Sync-PackageStage -Stage $stage -Ship (Get-Ship $game)
    Yes 'first build copies every kept file' ($r.New -eq 5 -and $r.Changed -eq 0 -and $r.Gone -eq 0 -and @($r.Copied).Count -eq 5)
    Yes 'and the payload is the build, byte for byte' (((Get-Tree $payload) -join "`n") -eq ((Get-Tree $game) -join "`n"))
    Yes 'and each copy has its build file''s write time' ((Get-Item (P $payload 'Data\Platform\UI\build.js')).LastWriteTimeUtc -eq $fixed)
    $top = @(Get-ChildItem -LiteralPath $stage -Force | ForEach-Object { $_.Name } | Sort-Object)
    Yes ('what an earlier build left at the top of the stage is gone (' + ($top -join ', ') + ')') (($top -join ',') -eq 'payload,profile')
    $want = 0
    foreach ($k in $files.Keys) { $want = [math]::Max($want, (P (Get-Item -LiteralPath $payload).FullName $k).Length) }
    Yes "the longest path comes from the rels, $($r.Longest) characters" ($r.Longest -eq $want -and $r.LongestPath.EndsWith('SkyrimPlatform.dll'))

    # ---- the second build, nothing moved: nothing is copied
    $before = @{}
    foreach ($f in Get-ChildItem -LiteralPath $payload -Recurse -File) { $before[$f.FullName] = $f.CreationTimeUtc.Ticks.ToString() + '|' + $f.LastWriteTimeUtc.Ticks }
    $r = Sync-PackageStage -Stage $stage -Ship (Get-Ship $game)
    Yes ('the second build copies nothing (' + $r.New + ' new, ' + $r.Changed + ' changed, ' + $r.Gone + ' removed)') ($r.New -eq 0 -and $r.Changed -eq 0 -and $r.Gone -eq 0 -and $r.Kept -eq 5 -and @($r.Copied).Count -eq 0)
    $same = $true
    foreach ($f in Get-ChildItem -LiteralPath $payload -Recurse -File) { if ($before[$f.FullName] -ne ($f.CreationTimeUtc.Ticks.ToString() + '|' + $f.LastWriteTimeUtc.Ticks)) { $same = $false } }
    Yes 'and leaves every staged file as it was' $same

    # ---- one front file changed, same length, same fixed time
    Put (P $game 'Data\Platform\UI\build.js') 'front BBBB'
    [IO.File]::SetLastWriteTimeUtc((P $game 'Data\Platform\UI\build.js'), $fixed)
    $r = Sync-PackageStage -Stage $stage -Ship (Get-Ship $game)
    Yes 'a file changed with the same length and time is copied, and only it' ($r.Changed -eq 1 -and $r.New -eq 0 -and (@($r.Copied) -join ',') -eq 'Data\Platform\UI\build.js')
    Yes 'and the staged copy is the new one' ([IO.File]::ReadAllText((P $payload 'Data\Platform\UI\build.js')) -eq 'front BBBB')

    # ---- one file grew, one left the build, one staged copy went missing
    Put (P $game 'Data\Thornswood.esp') 'plugin one, longer now'
    Remove-Item -LiteralPath (P $game 'Data\Scripts') -Recurse
    Remove-Item -LiteralPath (P $payload 'Data\Platform\UI\assets\a1b2.png')
    $r = Sync-PackageStage -Stage $stage -Ship (Get-Ship $game)
    Yes ('a changed length, a removed file and a missing copy (' + $r.New + ' new, ' + $r.Changed + ' changed, ' + $r.Gone + ' removed)') ($r.New -eq 1 -and $r.Changed -eq 1 -and $r.Gone -eq 1 -and $r.Kept -eq 2)
    Yes 'the folder the removed file left empty goes too' (-not (Test-Path -LiteralPath (P $payload 'Data\Scripts')))
    Yes 'and the payload is the build again, byte for byte' (((Get-Tree $payload) -join "`n") -eq ((Get-Tree $game) -join "`n"))

    # ---- the stage's size, without walking the payload
    Put (Join-Path $stage 'Setup.bat') '12345'
    Put (Join-Path $stage 'licences\port.txt') '123'
    Yes 'the stage size is the payload''s bytes and what sits beside it' ((Get-PackageStageBytes $stage 1000) -eq 1008)

    # ---- the zip, once
    $calls = Join-Path $T 'calls.txt'
    $fake = Join-Path $T 'fake7z.ps1'
    $blob = Join-Path $T 'payload.zip'
    Put $fake @'
param()
Add-Content -LiteralPath $env:TS3752_CALLS -Value ($args -join ' ')
'some.file'
if ([int]$env:TS3752_WRITE) { [IO.File]::WriteAllText($args[4], 'zip') }
exit ([int]$env:TS3752_CODE)
'@
    $env:TS3752_CALLS = $calls
    function Zip([int]$code, [int]$write) {
        if (Test-Path -LiteralPath $calls) { Remove-Item -LiteralPath $calls }
        if (Test-Path -LiteralPath $blob) { Remove-Item -LiteralPath $blob }
        $env:TS3752_CODE = "$code"; $env:TS3752_WRITE = "$write"
        $z = Invoke-PackageZip $fake $stage $blob 1
        return [pscustomobject]@{ Code = $z.Code; Said = $z.Said; Calls = @(Get-Content -LiteralPath $calls); Blob = (Test-Path -LiteralPath $blob) }
    }
    $z = Zip 2 1
    Yes ('a 7-Zip that exits 2 is called once, not twice (' + $z.Calls.Count + ')') ($z.Calls.Count -eq 1)
    Yes 'at the level asked for' ($z.Calls[0] -eq "a -tzip -y -mx1 $blob *")
    Yes 'and leaves no archive, with the code' ($z.Code -eq 2 -and -not $z.Blob)
    Yes 'and exit 2 is said as a full disk, with the free space line' (((Get-PackageZipWhy 2) -join ' ') -match 'disk filling up' -and ((Get-PackageZipWhy 2) -join ' ') -match 'Get-PSDrive')
    $z = Zip 1 1
    Yes 'exit 1, a file 7-Zip could not read, is no archive either' ($z.Calls.Count -eq 1 -and $z.Code -eq 1 -and -not $z.Blob)
    $z = Zip 0 0
    Yes 'exit 0 with nothing written is no archive' ($z.Code -eq -1)
    $z = Zip 0 1
    Yes 'exit 0 with the archive written is the zip, and what 7-Zip said is kept' ($z.Code -eq 0 -and $z.Blob -and (@($z.Said) -contains 'some.file'))

    # ---- the packager itself
    $pkg = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\release\Package-Thornswood.ps1'))
    $ast = [Management.Automation.Language.Parser]::ParseInput($pkg, [ref]$null, [ref]$null)
    Yes 'Package-Thornswood loads Package-Stage.ps1' ($pkg.Contains(". (Join-Path `$Here 'Package-Stage.ps1')"))
    Yes 'and brings the stage level with the build, with no switch to remove it first' ($pkg.Contains('Sync-PackageStage -Stage $stage -Ship $ship') -and -not $pkg.Contains('ReuseStage') -and -not $pkg.Contains('Remove-Item $stage'))
    $zips = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-PackageZip' }, $true))
    Yes 'and zips once' ($zips.Count -eq 1 -and -not $pkg.Contains('$attempts'))
    $walks = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-ChildItem' -and $n.Extent.Text -match '\$(stage|payload|payloadDir)\b' }, $true))
    Yes ('and walks the stage for nothing it already has' + $(if ($walks.Count) { ' (' + (($walks | ForEach-Object { $_.Extent.Text }) -join '; ') + ')' } else { '' })) ($walks.Count -eq 0)
    Yes 'and does not read three files back out of a zip it just made' (-not $pkg.Contains("Join-Path `$OutDir 'verify'"))
    Yes 'and says the optional packs once' (([regex]::Matches($pkg, 'published separately\.')).Count -eq 1)
    $synced = $pkg.IndexOf('Sync-PackageStage -Stage')
    Yes 'and still scans the finished stage for secrets after it is synced and before it is zipped' ($synced -gt 0 -and $pkg.IndexOf('-Dir $stage -ClientRecord') -gt $synced -and $pkg.IndexOf('-Dir $stage -ClientRecord') -lt $pkg.IndexOf('Invoke-PackageZip $7z'))
}
finally {
    Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
