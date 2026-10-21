<#
  test-source-notice.ps1

      pwsh -NoProfile -File .\tests\test-source-notice.ps1

  The update feed's downloads that carry SkyMP files carry, beside them, a
  note saying where their source is and the GNU GPL and AGPL texts.

  WHY IT MATTERS. Issue #421. The six files in records\client-build.json are
  SkyMP, under the GNU GPL version 3 and (MpClientPlugin.dll) the AGPL, and
  both ask that the licence and the directions to the source go with the
  files. The installer did that since #788. The feed did not: on 28 September
  client-runtime-fde333f1.zip on the dev feed and client-runtime-258fac47.zip
  on the live one held the six files and nothing else, and those downloads
  are where the launcher takes the files from.

  What this checks:
    - Source-Notice.ps1 writes README.txt (client runtime) or SOURCE CODE.txt
      (pack) from the record, naming the commit, the fork's tree, the branch,
      the upstream base and every file the download carries with its folder
      and licence, and puts GPL-3.0.txt and AGPL-3.0.txt from
      installer\licences beside it.
    - Each folder and licence agrees with the installer's SOURCE CODE.txt
      (Get-SourceNotice, lifted out of Package-Thornswood.ps1 by text).
    - A pack of only our own files gets nothing; a SkyMP file taken from
      upstream is named apart with no commit; a recorded file with no known
      folder stops it.
    - A zip written the way Publish-Update writes it holds the three at its
      top level, and Check-Secrets passes it.
    - Publish-Update.ps1 calls it for every pack part and for the client
      runtime, and a client runtime already on the feed without the note is
      published again.
    - The launcher takes nothing but game files out of either zip, so the
      note changes nothing a launcher does.

  Read only apart from its own temp folder.
#>
[CmdletBinding()]
param()
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Read-Json([string]$p) { return (((Get-Content -LiteralPath $p -Raw) -replace '^﻿', '') | ConvertFrom-Json) }
function Text($entries, [string]$name) {
    foreach ($e in @($entries)) { if ($e -and $e.Name -eq $name) { return [Text.Encoding]::UTF8.GetString($e.Bytes) } }
    return ''
}
function Names($entries) { return @(@($entries) | Where-Object { $_ } | ForEach-Object { $_.Name }) }
function Get-FunctionText([string]$text, [string]$name) {
    $at = $text.IndexOf("function $name")
    if ($at -lt 0) { return $null }
    $b = $text.IndexOf('{', $at)
    $depth = 0
    for ($i = $b; $i -lt $text.Length; $i++) {
        if ($text[$i] -eq '{') { $depth++ }
        elseif ($text[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($at, $i - $at + 1) } }
    }
    return $null
}

$record   = Join-Path $Repo 'records\client-build.json'
$server   = Join-Path $Repo 'records\server-build.json'
$licences = Join-Path $Repo 'installer\licences'
$notice   = Join-Path $Repo 'scripts\release\Source-Notice.ps1'
$publish  = Join-Path $Repo 'scripts\release\Publish-Update.ps1'
$package  = Join-Path $Repo 'scripts\release\Package-Thornswood.ps1'

Yes 'scripts\release\Source-Notice.ps1 is there' (Test-Path -LiteralPath $notice)
. $notice

$c = Read-Json $record
$six = @($c.files.PSObject.Properties.Name)
$commit = [string]$c.forkCommit
$fork = ([string]$c.fork).TrimEnd('/')
function Leaf([string]$p) { return $p.Substring($p.LastIndexOf('\') + 1) }

# ---- the client runtime zip's README ---------------------------------------
$rt = @(Get-SourceNoticeEntries $record $six 'runtime' $licences)
Yes ('the client runtime gets README.txt, GPL-3.0.txt and AGPL-3.0.txt: ' + ((Names $rt) -join ', ')) `
    (((Names $rt) -join '|') -eq 'README.txt|GPL-3.0.txt|AGPL-3.0.txt')
$readme = Text $rt 'README.txt'
Yes ('it names the recorded commit ' + $commit + ' and links its tree') ($readme.Contains($fork + '/tree/' + $commit))
Yes 'it names the branch' ($readme.Contains([string]$c.forkBranch))
Yes 'it names the upstream commit it starts from, where the record has one' `
    (-not ([string]$c.upstreamBase -match '^[0-9a-f]{7,40}$') -or $readme.Contains([string]$c.upstreamBase))
$missing = @($six | Where-Object { -not $readme.Contains((Leaf $_)) })
Yes ('it names all six files' + $(if ($missing.Count) { ', missing ' + ($missing -join ', ') } else { '' })) ($missing.Count -eq 0)
Yes 'it names MpClientPlugin.dll as skymp5-server, GNU AGPL version 3' `
    ($readme -match '(?m)^\s{2}MpClientPlugin\.dll\s{2,}skymp5-server\s{2,}GNU AGPL version 3\s*$')
Yes 'it names the two texts beside it' ($readme.Contains('GPL-3.0.txt') -and $readme.Contains('AGPL-3.0.txt'))
Yes 'it points at the credits page' ($readme.Contains('https://thornswood.net/credits#source'))
Yes 'it says the launcher fetches it and nothing needs copying by hand' ($readme -match 'fetches it by itself' -and $readme -match 'by hand')
Yes 'it is plain ASCII, for Notepad' (-not ($readme -match '[^\x09\x0A\x0D\x20-\x7E]'))
Yes 'it has no em dash and never says player' (-not ($readme -match '—') -and -not ($readme -match '(?i)\bplayers?\b'))
Yes 'with every file built, it names no upstream group' (-not $readme.Contains('Thornswood did not build'))
$gplBytes  = [IO.File]::ReadAllBytes((Join-Path $licences 'GPL-3.0.txt'))
$agplBytes = [IO.File]::ReadAllBytes((Join-Path $licences 'AGPL-3.0.txt'))
$gplOut  = @($rt | Where-Object { $_.Name -eq 'GPL-3.0.txt' })[0].Bytes
$agplOut = @($rt | Where-Object { $_.Name -eq 'AGPL-3.0.txt' })[0].Bytes
Yes 'GPL-3.0.txt is installer\licences\GPL-3.0.txt, byte for byte' ([Convert]::ToBase64String($gplOut) -eq [Convert]::ToBase64String($gplBytes))
Yes 'AGPL-3.0.txt is installer\licences\AGPL-3.0.txt, byte for byte' ([Convert]::ToBase64String($agplOut) -eq [Convert]::ToBase64String($agplBytes))

# ---- the same folders and licences as the installer's note -----------------
$pkgText = Get-Content -LiteralPath $package -Raw
$fn = Get-FunctionText $pkgText 'Get-SourceNotice'
Yes 'Package-Thornswood.ps1 has a Get-SourceNotice to compare with' ($null -ne $fn)
if ($fn) {
    . ([ScriptBlock]::Create($fn))
    $inst = Get-SourceNotice $record $server
    $rowRx = '^\s{2}(\S+)\s{2,}(\S+)\s{2,}(GNU A?GPL version 3)\s*$'
    $want = @{}
    foreach ($l in ($inst -split "`r?`n")) { $m = [regex]::Match($l, $rowRx); if ($m.Success) { $want[$m.Groups[1].Value] = $m.Groups[2].Value + '|' + $m.Groups[3].Value } }
    $bad = @()
    foreach ($f in $six) {
        $leaf = Leaf $f
        $m = [regex]::Match(($readme -split "`r?`n" | Where-Object { $_ -match ('^\s{2}' + [regex]::Escape($leaf) + '\s') } | Select-Object -First 1), $rowRx)
        if (-not $m.Success -or $want[$leaf] -ne ($m.Groups[2].Value + '|' + $m.Groups[3].Value)) { $bad += $leaf }
    }
    Yes ('every file has the folder and licence the installer''s note gives it' + $(if ($bad.Count) { ', differ: ' + ($bad -join ', ') } else { '' })) ($bad.Count -eq 0)
}

# ---- packs -------------------------------------------------------------------
$own = @('Data\Platform\Plugins\thornswood-front.js', 'Data\Platform\UI\thornswood-select.js')
Yes 'a pack of only our own files gets nothing' (@(Get-SourceNoticeEntries $record $own 'pack' $licences | Where-Object { $_ }).Count -eq 0)
Yes 'nor does a pack of nothing, like one that only removes' (@(Get-SourceNoticeEntries $record @() 'pack' $licences | Where-Object { $_ }).Count -eq 0)
$one = @(Get-SourceNoticeEntries $record ($own + 'Data\Platform\Plugins\skymp5-client.js') 'pack' $licences)
$src = Text $one 'SOURCE CODE.txt'
Yes ('a pack carrying skymp5-client.js gets SOURCE CODE.txt and both texts: ' + ((Names $one) -join ', ')) `
    (((Names $one) -join '|') -eq 'SOURCE CODE.txt|GPL-3.0.txt|AGPL-3.0.txt')
Yes '  naming skymp5-client.js, skymp5-client, GNU GPL version 3' ($src -match '(?m)^\s{2}skymp5-client\.js\s{2,}skymp5-client\s{2,}GNU GPL version 3\s*$')
Yes '  and the recorded commit' ($src.Contains($fork + '/tree/' + $commit))
Yes '  and not the files it does not carry' (-not $src.Contains('SkyrimPlatformImpl.dll') -and -not $src.Contains('thornswood-front.js'))
Yes '  matched without regard to case' ((Names (Get-SourceNoticeEntries $record @('data\platform\plugins\SKYMP5-CLIENT.js') 'pack' $licences)) -contains 'SOURCE CODE.txt')
# build.js is built from the fork's skymp5-front at the pin by every Ship since
# #2931 and held to records\front-build.json, beside the client record.
$fb = @(Get-SourceNoticeEntries $record @('Data\Platform\UI\build.js') 'pack' $licences)
$fbText = Text $fb 'SOURCE CODE.txt'
Yes 'a pack carrying only build.js names it as built from skymp5-front, GNU GPL version 3' ($fbText -match '(?m)^\s{2}build\.js\s{2,}skymp5-front\s{2,}GNU GPL version 3\s*$')
Yes '  at the recorded commit, with no group of what Thornswood did not build' ($fbText.Contains($fork + '/tree/' + $commit) -and -not $fbText.Contains('Thornswood did not build'))

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-source-notice-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $tmp
try {
    # A client record with no front record beside it, as before #2931: build.js
    # is SkyMP's own, with no commit.
    $bare = Join-Path $tmp 'bare'
    $null = New-Item -ItemType Directory -Force -Path $bare
    [IO.File]::Copy($record, (Join-Path $bare 'client-build.json'))
    $up = @(Get-SourceNoticeEntries (Join-Path $bare 'client-build.json') @('Data\Platform\UI\build.js') 'pack' $licences)
    $upText = Text $up 'SOURCE CODE.txt'
    Yes 'with no front record, a pack carrying only build.js names it as SkyMP''s skymp5-front, GNU GPL version 3' ($upText -match '(?m)^\s{2}build\.js\s{2,}skymp5-front\s{2,}GNU GPL version 3\s*$')
    Yes '  says Thornswood did not build it and names no commit for it' ($upText.Contains('Thornswood did not build') -and -not $upText.Contains('/tree/'))
    Yes '  and points at upstream SkyMP' ($upText.Contains('https://github.com/skyrim-multiplayer/skymp'))
    # A front record of another commit stops it.
    $fr = Read-Json (Join-Path $Repo 'records\front-build.json')
    $fr.forkCommit = 'abcdef1234567890abcdef1234567890abcdef12'
    [IO.File]::WriteAllText((Join-Path $bare 'front-build.json'), ($fr | ConvertTo-Json -Depth 6))
    $threw = $false
    try { $null = Get-SourceNoticeEntries (Join-Path $bare 'client-build.json') @('Data\Platform\UI\build.js') 'pack' $licences } catch { $threw = $_.Exception.Message -match 'one commit' }
    Yes 'a front record of another commit than the client record stops it' $threw

    $c3 = Read-Json $record
    $c3.files | Add-Member -NotePropertyName 'Data\SKSE\Plugins\Unheard.dll' -NotePropertyValue ([pscustomobject]@{ sha256 = '00'; bytes = 1 })
    $cp = Join-Path $tmp 'client-build.json'
    [IO.File]::WriteAllText($cp, ($c3 | ConvertTo-Json -Depth 6))
    $threw = $false
    try { $null = Get-SourceNoticeEntries $cp $six 'runtime' $licences } catch { $threw = $true }
    Yes 'a recorded file with no known source folder stops it' $threw
    $threw = $false
    try { $null = Get-SourceNoticeEntries $record $six 'runtime' (Join-Path $tmp 'nolicences') } catch { $threw = $true }
    Yes 'a missing licence text stops it' $threw

    # ---- a zip, written the way Publish-Update writes a pack ----------------
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zp = Join-Path $tmp 'pack-test.zip'
    $z = [IO.Compression.ZipFile]::Open($zp, 'Create')
    try {
        $e = $z.CreateEntry('game/Data/Platform/UI/thornswood-select.js')
        $s = $e.Open(); $b = [Text.Encoding]::UTF8.GetBytes('// ours'); $s.Write($b, 0, $b.Length); $s.Dispose()
        Add-SourceNoticeToZip $z (Get-SourceNoticeEntries $record @('Data\Platform\UI\build.js') 'pack' $licences)
        Add-SourceNoticeToZip $z (Get-SourceNoticeEntries $record $own 'pack' $licences)
    } finally { $z.Dispose() }
    $z = [IO.Compression.ZipFile]::OpenRead($zp)
    try { $names = @($z.Entries | ForEach-Object { $_.FullName }) } finally { $z.Dispose() }
    Yes ('the pack zip holds the note and both texts at its top: ' + ($names -join ', ')) `
        ($names -contains 'SOURCE CODE.txt' -and $names -contains 'GPL-3.0.txt' -and $names -contains 'AGPL-3.0.txt' -and $names.Count -eq 4)
    $scan = Join-Path $Repo 'scripts\dev\Check-Secrets.ps1'
    $out = (@(& $scan -Zip $zp *>&1 | ForEach-Object { [string]$_ }) -join "`n")
    Yes ('Check-Secrets passes a zip carrying them (exit ' + $LASTEXITCODE + ')') ($LASTEXITCODE -eq 0)
    if ($LASTEXITCODE -ne 0) { Write-Host $out }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- Publish-Update.ps1 uses it ---------------------------------------------
$pu = Get-Content -LiteralPath $publish -Raw
Yes 'Publish-Update.ps1 dot-sources Source-Notice.ps1' ($pu.Contains(". (Join-Path `$Here 'Source-Notice.ps1')"))
$packAt = $pu.IndexOf("Head 'Building the pack'")
$packCall = $pu.IndexOf("Get-SourceNoticeEntries `$sourceRecord `$inPart 'pack' `$sourceLicences")
$deleteAt = $pu.IndexOf("CreateEntry('delete.txt')")
Yes 'every pack part gets the note, once its game files are in' ($packAt -ge 0 -and $packCall -gt $packAt -and $packCall -lt $deleteAt -and $pu.Contains('Add-SourceNoticeToZip $zip (Get-SourceNoticeEntries'))
$rtCall = $pu.IndexOf("Get-SourceNoticeEntries `$cbPath `$names 'runtime' `$sourceLicences")
$rtZip = $pu.IndexOf('[IO.Compression.ZipFile]::CreateFromDirectory($stage, $clientZip')
Yes 'the client runtime gets the note in its stage before it is zipped' ($rtCall -gt 0 -and $rtZip -gt $rtCall)
Yes 'the feed records which note the client runtime carries' ($pu -match 'notice\s+=\s+\$SourceNoticeVersion')

# The "already on the feed" test, lifted and run: a runtime already there
# without the note is published again, one with it is left alone.
$m = [regex]::Match($pu, '(?s)\$already = (.+?)\r?\n\s*if \(\$already\)')
Yes 'Publish-Update.ps1 still decides "already on the feed" in one expression' $m.Success
if ($m.Success) {
    $expr = [ScriptBlock]::Create($m.Groups[1].Value)
    $cbCommit = $commit
    $have = [pscustomobject]@{ url = 'https://thornswood.net/feed-dev/assets/x'; sha256 = 'x'; bytes = 1; forkCommit = $commit }
    Yes 'a runtime on the feed from before the note is published again' (-not [bool](& $expr))
    $have = [pscustomobject]@{ url = 'https://thornswood.net/feed-dev/assets/x'; sha256 = 'x'; bytes = 1; forkCommit = $commit; notice = $SourceNoticeVersion }
    Yes 'a runtime on the feed with the note is left alone' ([bool](& $expr))
    $have = [pscustomobject]@{ url = 'https://thornswood.net/feed-dev/assets/x'; sha256 = 'x'; bytes = 1; forkCommit = 'deadbeef'; notice = $SourceNoticeVersion }
    Yes 'a runtime of another commit is published again' (-not [bool](& $expr))
}

# ---- the launcher ignores what this adds -------------------------------------
$cr = Get-Content -LiteralPath (Join-Path $Repo 'launcher\app\ClientRuntime.cs') -Raw
Yes 'ClientRuntime.cs takes out only the recorded paths it wants (Find by name)' `
    ($cr -match 'ZipArchiveEntry en = Find\(ar, rel\);' -and $cr -match 'string rel = want\[i\];')
$up2 = Get-Content -LiteralPath (Join-Path $Repo 'launcher\app\Updater.cs') -Raw
Yes 'Updater.cs skips a pack entry that is not game\, profile\ or delete.txt' `
    ($up2 -match '(?s)rel\.Equals\("delete\.txt", StringComparison\.OrdinalIgnoreCase\)\)\s*continue;\s*else if \(rel\.Equals\("ui-assets\.txt", StringComparison\.OrdinalIgnoreCase\)\)\s*\{.*?\bcontinue;\s*\}\s*else\s*continue;\s*// The fence is')

# ---- THIRD-PARTY.md says so, and not what stopped being true ----------------
$tp = Get-Content -LiteralPath (Join-Path $Repo 'THIRD-PARTY.md') -Raw
$reach = [regex]::Match($tp, '(?s)\n## How it reaches people(.+?)\n## ').Groups[1].Value
Yes 'THIRD-PARTY.md says the client runtime zip carries README.txt and the two texts (Source-Notice.ps1)' `
    ($reach.Contains('README.txt') -and $reach.Contains('GPL-3.0.txt') -and $reach.Contains('AGPL-3.0.txt') -and $reach.Contains('Source-Notice.ps1'))
Yes 'THIRD-PARTY.md no longer names Get-ReleaseSourceFooter, which #907 removed' (-not $tp.Contains('Get-ReleaseSourceFooter') -and -not $pu.Contains('function Get-ReleaseSourceFooter'))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
