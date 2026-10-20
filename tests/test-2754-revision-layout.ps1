<#
  test-2754-revision-layout.ps1

      pwsh -NoProfile -File .\tests\test-2754-revision-layout.ps1

  Install-NexusRevision.ps1 (#2754) against the stand-in Nexus on this
  machine's loopback address (tests\fixtures\nexus-standin.js), with a small
  made-up collection, never the real one.

  WHY. The layout step replaces Vortex as the thing that turns a revision
  into files, and every release step will read what it writes. What it must
  refuse, and what it must never write over, is held here.

  WHAT IT HOLDS:
    1. -Game is required, and a folder in a Steam library or one Vortex
       deploys into is refused before anything is asked;
    2. a revision with a kind not laid out here (an optional mod, a later
       phase) is refused naming each entry, with nothing downloaded;
    3. a download whose md5 is not the revision's stops the run naming the
       file, and leaves nothing of it in the cache; a free account's 403 on
       download-link stops it the same way;
    4. the cache: a second run downloads nothing, and a cached archive that
       changed is downloaded again, that one only;
    5. with 7-Zip: the layout itself. A plain archive cut at its first stop
       pattern, a hashes list, a FOMOD run with the collection's choices, a
       script extender to the game folder, a bsdiff patch, a file two mods
       share going to the one the mod rules deploy last, the plugin order
       with an unlisted plugin disabled at the end, files.txt holding every
       file with its sha256, and layout.json the revision and file ids;
    6. a run again replaces the layout; a layout file that changed, and a
       file no layout put there, are never written over; two mods sharing a
       file with no rule between them stop the run with -Game untouched;
    7. -Revision through the API: GraphQL's downloadLink, the v2
       download_link, and the CDN, which never gets the key.

  Needs node. Part 5 onward needs 7-Zip and says SKIP without it. Everything
  it writes is under its own temp folder, which it removes.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
$script_ = Join-Path $repo 'scripts\release\Install-NexusRevision.ps1'

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Skip([string]$what) { Write-Host "SKIP  $what" }
$script:standin = $null
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-2754-' + [Guid]::NewGuid().ToString('N').Substring(0, 10))
function Done {
    if ($script:standin -and -not $script:standin.HasExited) { $script:standin.Kill() }
    if (Test-Path -LiteralPath $T) { [IO.Directory]::Delete($T, $true) }
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}
function Put([string]$path, [string]$text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}
function Md5([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm MD5).Hash.ToLowerInvariant() }
function Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

$node = Get-Command node -ErrorAction SilentlyContinue
Yes 'node is on PATH, for the stand-in Nexus' ($null -ne $node)
if ($null -eq $node) { Done }
$pwsh = (Get-Process -Id $PID).Path
$sz = ''
if ($env:ProgramFiles -and (Test-Path -LiteralPath (Join-Path $env:ProgramFiles '7-Zip\7z.exe'))) { $sz = Join-Path $env:ProgramFiles '7-Zip\7z.exe' }
if (-not $sz) { foreach ($n in '7z', '7zz', '7za') { $g = Get-Command $n -ErrorAction SilentlyContinue; if ($g) { $sz = $g.Source; break } } }
New-Item -ItemType Directory -Force -Path $T, (Join-Path $T 'scratch') | Out-Null

# ---- the stand-in -----------------------------------------------------------
$KEY = 'standin-' + [Guid]::NewGuid().ToString('N')
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $node.Source
[void]$psi.ArgumentList.Add((Join-Path $repo 'tests\fixtures\nexus-standin.js'))
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.EnvironmentVariables['NEXUS_STANDIN_KEY'] = $KEY
$script:standin = [Diagnostics.Process]::Start($psi)
trap { $script:fail++; Write-Host ('FAIL  the harness itself stopped: ' + $_.Exception.Message) -ForegroundColor Red; Done }
$errRead = $script:standin.StandardError.ReadToEndAsync()
$first = $script:standin.StandardOutput.ReadLineAsync()
$heard = if ($first.Wait(15000)) { [string]$first.Result } else { '' }
$pm = [regex]::Match($heard, '^\[nexus\] listening on 127\.0\.0\.1:(\d+)$')
$port = if ($pm.Success) { [int]$pm.Groups[1].Value } else { 0 }
Yes "the stand-in Nexus says it is listening on its own port ($port)" ($port -gt 0)
if (-not $port) { if ($errRead.Wait(2000)) { Write-Host ('      ' + $errRead.Result) }; Done }
$null = $script:standin.StandardOutput.ReadToEndAsync()
$base = 'http://127.0.0.1:' + $port
function State { return (Invoke-RestMethod -Uri ($base + '/_requests')) }
function Control($h) { [void](Invoke-RestMethod -Method Post -Uri ($base + '/_control') -ContentType 'application/json' -Body ($h | ConvertTo-Json -Compress -Depth 6)) }
function Since([int]$n) { $all = @((State).requests); if ($all.Count -le $n) { return @() }; return @($all[$n..($all.Count - 1)]) }
function Count { return @((State).requests).Count }
function Cdn($reqs, [string]$id = '') { return , @($reqs | Where-Object { $_.path -like ('/cdn/file/' + $id + '*') }) }

$env:THORNSWOOD_NEXUS_STANDIN = $base
$env:THORNSWOOD_NEXUS_STANDIN_KEY = $KEY
$env:THORNSWOOD_NEXUS_API_KEY = $null
$env:THORNSWOOD_SCRATCH_ROOT = (Join-Path $T 'scratch')
$script:outs = New-Object System.Collections.Generic.List[string]
function Run([string[]]$arguments) {
    $p = New-Object Diagnostics.ProcessStartInfo
    $p.FileName = $pwsh
    foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script_) + $arguments + @('-NoPause')) { [void]$p.ArgumentList.Add($a) }
    $p.UseShellExecute = $false; $p.CreateNoWindow = $true; $p.RedirectStandardOutput = $true; $p.RedirectStandardError = $true
    $pr = [Diagnostics.Process]::Start($p)
    $e = $pr.StandardError.ReadToEndAsync()
    $o = $pr.StandardOutput.ReadToEnd()
    $pr.WaitForExit()
    $text = $o + $e.Result
    $script:outs.Add($text)
    return [pscustomobject]@{ Code = $pr.ExitCode; Out = $text }
}
function Show($r) { Write-Host (($r.Out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 16) -join "`n") -ForegroundColor DarkGray }
function YesR([string]$what, [bool]$cond, $r) { Yes $what $cond; if (-not $cond) { Show $r } }

# ---- the made-up mods ----------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Zip([string]$name, [hashtable]$files) {
    $src = Join-Path $T ('src\' + $name)
    foreach ($k in $files.Keys) { Put (Join-Path $src $k) $files[$k] }
    $zip = Join-Path $T ('archives\' + $name + '.zip')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $zip) | Out-Null
    [IO.Compression.ZipFile]::CreateFromDirectory($src, $zip)
    return $zip
}
$fomodXml = @'
<?xml version="1.0" encoding="utf-8"?>
<config xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://qconsulting.ca/fo3/ModConfig5.0.xsd">
  <moduleName>Gamma</moduleName>
  <requiredInstallFiles>
    <folder source="common" destination="" />
  </requiredInstallFiles>
  <installSteps order="Explicit">
    <installStep name="Main">
      <optionalFileGroups order="Explicit">
        <group name="Pick" type="SelectExactlyOne">
          <plugins order="Explicit">
            <plugin name="One"><description>one</description><files><file source="opt1\Gamma.esp" destination="Gamma.esp" /></files><typeDescriptor><type name="Optional"/></typeDescriptor></plugin>
            <plugin name="Two"><description>two</description><files><file source="opt2\Gamma.esp" destination="Gamma.esp" /></files><typeDescriptor><type name="Optional"/></typeDescriptor></plugin>
          </plugins>
        </group>
      </optionalFileGroups>
    </installStep>
  </installSteps>
</config>
'@
$arc = [ordered]@{
    alpha = Zip 'Alpha' @{ 'Data\Alpha.esp' = 'alpha plugin'; 'Data\Zeta.esp' = 'zeta plugin'; 'Data\textures\shared.dds' = 'alpha texture'; 'readme.txt' = 'read me'; 'Data\meta.ini' = '[General]' }
    beta  = Zip 'Beta' @{ 'junk\Beta.esp' = 'beta plugin'; 'junk\other.txt' = 'not listed' }
    gamma = Zip 'Gamma' @{ 'fomod\ModuleConfig.xml' = $fomodXml; 'opt1\Gamma.esp' = 'gamma one'; 'opt2\Gamma.esp' = 'gamma two'; 'common\textures\shared.dds' = 'gamma texture' }
    delta = Zip 'Delta' @{ 'delta_1\skse64_loader.exe' = 'loader'; 'delta_1\Data\Scripts\delta.pex' = 'script' }
    eps   = Zip 'Epsilon' @{ 'Eps.esp' = 'AAAA' }
}
$ids = @{ alpha = 900001; beta = 900002; gamma = 900003; delta = 900004; eps = 900005 }
$serve = @{}
foreach ($k in $arc.Keys) { $serve[[string]$ids[$k]] = @{ path = $arc[$k]; name = (Split-Path -Leaf $arc[$k]) } }
Control @{ serve = $serve }
$betaMd5 = (Get-FileHash -LiteralPath (Join-Path $T 'src\Beta\junk\Beta.esp') -Algorithm MD5).Hash.ToLowerInvariant()
function Entry([string]$k, [string]$name, [hashtable]$extra) {
    $e = [ordered]@{ name = $name; version = '1.0'; optional = $false; domainName = 'skyrimspecialedition'
        source = [ordered]@{ type = 'nexus'; modId = ($ids[$k] - 900000 + 100); fileId = $ids[$k]; md5 = (Md5 $arc[$k]); fileSize = (Get-Item -LiteralPath $arc[$k]).Length; logicalFilename = $name; updatePolicy = 'exact'; tag = ('tag' + $k) }
        author = 'Someone'; details = [ordered]@{ category = 'Misc'; type = '' }; phase = 0 }
    foreach ($x in $extra.Keys) { if ($x -eq 'type') { $e.details.type = $extra[$x] } else { $e[$x] = $extra[$x] } }
    return $e
}
function Collection([object[]]$mods, [object[]]$rules) {
    return [ordered]@{
        info = [ordered]@{ author = 'Someone'; authorUrl = ''; name = 'Made Up'; description = ''; installInstructions = ''; domainName = 'skyrimspecialedition'; gameVersions = @('1.6.1170.0') }
        mods = $mods; modRules = $rules; tools = @()
        plugins = @(@{ name = 'Alpha.esp'; enabled = $true }, @{ name = 'Gamma.esp'; enabled = $true }, @{ name = 'Beta.esp'; enabled = $true }, @{ name = 'Eps.esp'; enabled = $true })
        pluginRules = [ordered]@{ plugins = @([ordered]@{ name = 'gamma.esp'; after = @('alpha.esp') }); groups = @() }
        collectionConfig = [ordered]@{ recommendNewProfile = $true; referenceTagScheme = 'v1' }
    }
}
$alphaE = Entry 'alpha' 'Alpha' @{}
$betaE = Entry 'beta' 'Beta' @{ hashes = @([ordered]@{ path = 'Beta.esp'; md5 = $betaMd5 }) }
$gammaE = Entry 'gamma' 'Gamma' @{ choices = [ordered]@{ type = 'fomod'; options = @([ordered]@{ name = 'Main'; groups = @([ordered]@{ name = 'Pick'; choices = @([ordered]@{ name = 'Two'; idx = 1 }) }) }) } }
$deltaE = Entry 'delta' 'Delta' @{ type = 'dinput' }
$crcOld = '' ; $epsE = $null
$rule = [ordered]@{ type = 'after'; reference = [ordered]@{ fileMD5 = (Md5 $arc.alpha); versionMatch = '1.0.0'; logicalFileName = 'Alpha' }; source = [ordered]@{ fileMD5 = (Md5 $arc.gamma); versionMatch = '1.0.0'; logicalFileName = 'Gamma' } }
function Write-Col([string]$dir, $c) { Put (Join-Path $dir 'collection.json') ($c | ConvertTo-Json -Depth 12); New-Item -ItemType Directory -Force -Path (Join-Path $dir 'bundled') | Out-Null }

# ---- 1: -Game ----------------------------------------------------------------------
$colPlain = Join-Path $T 'col-plain'
Write-Col $colPlain (Collection @($alphaE, $betaE, $gammaE, $deltaE) @($rule))
$n0 = Count
$r = Run @('-CollectionArchive', $colPlain, '-Revision', '5')
YesR 'with no -Game it stops and says there is no default' ($r.Code -eq 1 -and $r.Out -match 'Say which folder' -and (Count) -eq $n0) $r
$steam = Join-Path $T 'steamapps\common\Skyrim Special Edition'
$r = Run @('-CollectionArchive', $colPlain, '-Revision', '5', '-Game', $steam)
YesR 'a folder in a Steam library is refused' ($r.Code -eq 1 -and $r.Out -match 'is in a Steam library' -and -not (Test-Path -LiteralPath $steam)) $r
$vg = Join-Path $T 'vortex-game'
Put (Join-Path $vg 'Data\vortex.deployment.json') '{}'
$r = Run @('-CollectionArchive', $colPlain, '-Revision', '5', '-Game', $vg)
YesR 'a folder Vortex deploys into is refused' ($r.Code -eq 1 -and $r.Out -match 'is a folder Vortex deploys into' -and @(Get-ChildItem -LiteralPath $vg -Recurse -File).Count -eq 1) $r
Put (Join-Path $vg 'vortex.deployment.dinput.json') '{}'
[IO.File]::Delete((Join-Path $vg 'Data\vortex.deployment.json'))
$r = Run @('-CollectionArchive', $colPlain, '-Revision', '5', '-Game', $vg)
YesR 'and so is one with only the dinput record at its top' ($r.Code -eq 1 -and $r.Out -match 'Vortex deployment record') $r
Yes 'none of these asked the stand-in anything' ((Count) -eq $n0)

# ---- 2: a kind not laid out here ------------------------------------------------------------
$colOdd = Join-Path $T 'col-odd'
$oddA = Entry 'alpha' 'Alpha' @{ optional = $true }
$oddB = Entry 'beta' 'Beta' @{ phase = 1 }
Write-Col $colOdd (Collection @($oddA, $oddB) @())
$n0 = Count
$r = Run @('-CollectionArchive', $colOdd, '-Revision', '5', '-Game', (Join-Path $T 'game-odd'), '-Cache', (Join-Path $T 'cache'))
YesR 'an optional mod and a later phase are refused, each named, and nothing is downloaded' ($r.Code -eq 1 -and $r.Out -match 'Alpha \(mod 101, file 900001\) is optional' -and $r.Out -match 'Beta \(mod 102, file 900002\) is in phase 1' -and $r.Out -match 'nothing was downloaded' -and (Count) -eq $n0 -and -not (Test-Path -LiteralPath (Join-Path $T 'cache'))) $r

# ---- 3: a download that is not the revision's -----------------------------------------------
$cache = Join-Path $T 'cache'
Control @{ corrupt = @('900002') }
$n0 = Count
$r = Run @('-CollectionArchive', $colPlain, '-Revision', '5', '-Game', (Join-Path $T 'game'), '-Cache', $cache)
Control @{ corrupt = @() }
YesR 'a download whose md5 is not the revision''s stops the run, naming the file' ($r.Code -eq 1 -and $r.Out -match 'The download of Beta \(mod 102, file 900002\) is not the archive the revision lists' -and $r.Out -match 'deleted from the cache') $r
Yes 'and nothing of it stays in the cache, while the one before it does' (@(Get-ChildItem -LiteralPath (Join-Path $cache '900002') -File -ErrorAction SilentlyContinue).Count -eq 0 -and @(Get-ChildItem -LiteralPath (Join-Path $cache '900001') -File).Count -eq 1)
Yes 'and -Game was not made' (-not (Test-Path -LiteralPath (Join-Path $T 'game')))
$got = @(Since $n0)
Yes 'the download links were asked for with the key, and the CDN got none' (@($got | Where-Object { $_.path -like '*/download-link' -and $_.key -ne 'right' }).Count -eq 0 -and (Cdn $got).Count -ge 2 -and @((Cdn $got) | Where-Object { $_.key -ne 'none' }).Count -eq 0)
Control @{ premium = $false }
$r = Run @('-CollectionArchive', $colPlain, '-Revision', '5', '-Game', (Join-Path $T 'game'), '-Cache', $cache)
Control @{ premium = $true }
YesR 'a free account''s 403 on download-link stops it naming the file' ($r.Code -eq 1 -and $r.Out -match 'Asking for the download of Beta \(mod 102, file 900002\) was refused: HTTP 403' -and $r.Out -match 'Premium') $r

# ---- 4: the cache ----------------------------------------------------------------------
$n0 = Count
$r = Run @('-CollectionArchive', $colPlain, '-Revision', '5', '-Game', (Join-Path $T 'game'), '-Cache', $cache, '-WhatIf')
$first4 = @(Since $n0)
YesR 'the first whole run downloads what the cache lacks' ((Cdn $first4).Count -eq 3 -and $r.Out -match '1 from the cache, 3 downloaded') $r
$n0 = Count
$r = Run @('-CollectionArchive', $colPlain, '-Revision', '5', '-Game', (Join-Path $T 'game'), '-Cache', $cache, '-WhatIf')
YesR 'a second run downloads nothing and asks for no link' ((Cdn @(Since $n0)).Count -eq 0 -and @((Since $n0) | Where-Object { $_.path -like '*/download-link' }).Count -eq 0 -and $r.Out -match '4 from the cache, 0 downloaded') $r
$cachedGamma = @(Get-ChildItem -LiteralPath (Join-Path $cache '900003') -File)[0].FullName
[IO.File]::AppendAllText($cachedGamma, 'x')
$n0 = Count
$r = Run @('-CollectionArchive', $colPlain, '-Revision', '5', '-Game', (Join-Path $T 'game'), '-Cache', $cache, '-WhatIf')
$got = @(Since $n0)
YesR 'a cached archive that changed is downloaded again, that one only' ((Cdn $got).Count -eq 1 -and (Cdn $got '900003').Count -eq 1 -and $r.Out -match 'is not the archive the revision lists for file 900003, so it is replaced' -and (Md5 $cachedGamma) -eq (Md5 $arc.gamma)) $r

if (-not $sz) { Skip 'the layout itself, a run again and -Revision through the API: 7-Zip is not on this machine'; Done }

# ---- 5: the layout ----------------------------------------------------------------------
# A bsdiff patch for Epsilon's Eps.esp, AAAA to AAAB, made the way bsdiff
# writes one: a control triple, the byte differences, no extra bytes.
function OffT([long]$v) { $b = [BitConverter]::GetBytes([long][Math]::Abs($v)); if ($v -lt 0) { $b[7] = $b[7] -bor 0x80 }; return $b }
function Bz([byte[]]$data, [string]$name) {
    $f = Join-Path $T ('bz\' + $name); New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f) | Out-Null
    [IO.File]::WriteAllBytes($f, $data)
    & $sz a -tbzip2 -y ($f + '.bz2') $f | Out-Null
    return [IO.File]::ReadAllBytes($f + '.bz2')
}
$ctrl = Bz ((OffT 4) + (OffT 0) + (OffT 0)) 'ctrl'
$dif = Bz ([byte[]](0, 0, 0, 1)) 'diff'
$ext = Bz ([byte[]]@()) 'extra'
$patch = [byte[]]([Text.Encoding]::ASCII.GetBytes('BSDIFF40') + (OffT $ctrl.Length) + (OffT $dif.Length) + (OffT 4) + $ctrl + $dif + $ext)
Add-Type -LiteralPath (Join-Path $repo 'scripts\release\NexusLayout.cs')
$crcOld = [Thornswood.Layout.NexusLayout]::Crc32Of((Join-Path $T 'src\Epsilon\Eps.esp'))
$epsE = Entry 'eps' 'Epsilon' @{ patches = [ordered]@{ 'Eps.esp' = $crcOld } }
$colFull = Join-Path $T 'col-full'
Write-Col $colFull (Collection @($alphaE, $betaE, $gammaE, $deltaE, $epsE) @($rule))
New-Item -ItemType Directory -Force -Path (Join-Path $colFull 'patches\Epsilon') | Out-Null
[IO.File]::WriteAllBytes((Join-Path $colFull 'patches\Epsilon\Eps.esp.diff'), $patch)
$game = Join-Path $T 'game'
$r = Run @('-CollectionArchive', $colFull, '-Revision', '5', '-Game', $game, '-Cache', $cache)
YesR 'the layout runs to the end' ($r.Code -eq 0 -and $r.Out -match 'revision 5 of 7essxf: ') $r
function Text([string]$rel) { $p = Join-Path $game $rel; if (Test-Path -LiteralPath $p) { return [IO.File]::ReadAllText($p) }; return $null }
Yes 'a plain archive is cut at its first stop pattern: Data\Alpha.esp, and readme.txt beside it in Data' ((Text 'Data\Alpha.esp') -eq 'alpha plugin' -and (Text 'Data\readme.txt') -eq 'read me' -and -not (Test-Path -LiteralPath (Join-Path $game 'Data\Data')))
Yes 'meta.ini is never deployed' (-not (Test-Path -LiteralPath (Join-Path $game 'Data\meta.ini')))
Yes 'a hashes list puts the listed md5 at its path and nothing else' ((Text 'Data\Beta.esp') -eq 'beta plugin' -and -not (Test-Path -LiteralPath (Join-Path $game 'Data\other.txt')) -and -not (Test-Path -LiteralPath (Join-Path $game 'Data\junk')))
Yes 'the FOMOD runs with the collection''s choice (Two) and its required folder' ((Text 'Data\Gamma.esp') -eq 'gamma two')
Yes 'the file Alpha and Gamma share is Gamma''s, the mod the rule deploys after' ((Text 'Data\textures\shared.dds') -eq 'gamma texture')
Yes 'the script extender goes to the game folder, from its own folder down' ((Text 'skse64_loader.exe') -eq 'loader' -and (Text 'Data\Scripts\delta.pex') -eq 'script' -and -not (Test-Path -LiteralPath (Join-Path $game 'Data\skse64_loader.exe')))
Yes 'the patch makes Eps.esp AAAB' ((Text 'Data\Eps.esp') -eq 'AAAB')
$recDir = Join-Path $game 'Thornswood Layout'
$pl = @([IO.File]::ReadAllLines((Join-Path $recDir 'plugins.txt')) | Where-Object { $_ -and -not $_.StartsWith('#') })
Yes ('plugins.txt is the collection''s order, then the plugin it does not list, disabled: ' + ($pl -join ' ')) (($pl -join '|') -eq '*Alpha.esp|*Gamma.esp|*Beta.esp|*Eps.esp|Zeta.esp')
$lo = @([IO.File]::ReadAllLines((Join-Path $recDir 'loadorder.txt')) | Where-Object { $_ -and -not $_.StartsWith('#') })
Yes 'loadorder.txt is the same names without stars' (($lo -join '|') -eq 'Alpha.esp|Gamma.esp|Beta.esp|Eps.esp|Zeta.esp')
$lines = @([IO.File]::ReadAllLines((Join-Path $recDir 'files.txt')) | Where-Object { $_ -and -not $_.StartsWith('#') })
$onDisk = @(Get-ChildItem -LiteralPath $game -Recurse -File | Where-Object { -not $_.FullName.StartsWith($recDir) })
$okLines = @($lines | Where-Object { $c = $_.Split("`t"); $f = Join-Path $game $c[3]; (Test-Path -LiteralPath $f) -and (Sha $f) -eq $c[0] -and (Get-Item -LiteralPath $f).Length -eq [long]$c[1] })
Yes ('files.txt names every file placed, ' + $lines.Count + ', each with its sha256 and size') ($lines.Count -eq 9 -and $okLines.Count -eq $lines.Count -and $onDisk.Count -eq $lines.Count)
$lj = Get-Content -Raw -LiteralPath (Join-Path $recDir 'layout.json') | ConvertFrom-Json
Yes 'layout.json says the revision, and each mod''s file id, md5 and installer' ($lj.collection.revision -eq 5 -and $lj.collection.slug -eq '7essxf' -and $lj.files -eq 9 -and (@($lj.mods | ForEach-Object { [string]$_.fileId + ':' + $_.installer }) -join ' ') -eq '900001:basic 900002:list 900003:fomod 900004:script-extender 900005:basic' -and @($lj.mods | Where-Object { $_.fileId -eq 900003 })[0].md5 -eq (Md5 $arc.gamma))
Yes 'and files.txt carries the file id each file came from' (@($lines | Where-Object { $_.EndsWith("`tData\textures\shared.dds") -and $_.Split("`t")[2] -eq '900003' }).Count -eq 1)
Yes 'the scratch folder is gone after' (-not (Test-Path -LiteralPath (Join-Path $T 'scratch\revision-layout-7essxf-5')))

# ---- 6: a run again, and what is never written over ------------------------------------------
$r = Run @('-CollectionArchive', $colFull, '-Revision', '5', '-Game', $game, '-Cache', $cache)
YesR 'a run again over its own layout replaces it' ($r.Code -eq 0 -and $r.Out -match 'the layout there now has 9 files, all as its files.txt says' -and (Text 'Data\Gamma.esp') -eq 'gamma two') $r
[IO.File]::WriteAllText((Join-Path $game 'Data\Alpha.esp'), 'edited by hand')
$r = Run @('-CollectionArchive', $colFull, '-Revision', '5', '-Game', $game, '-Cache', $cache)
YesR 'a layout file that changed is not taken out, and the run stops naming it' ($r.Code -eq 1 -and $r.Out -match 'not what its files.txt says' -and $r.Out -match 'Data\\Alpha.esp' -and (Text 'Data\Alpha.esp') -eq 'edited by hand') $r
$game2 = Join-Path $T 'game2'
Put (Join-Path $game2 'Data\Beta.esp') 'somebody else''s'
$r = Run @('-CollectionArchive', $colFull, '-Revision', '5', '-Game', $game2, '-Cache', $cache)
YesR 'a file no layout put there is never written over' ($r.Code -eq 1 -and $r.Out -match 'no layout put them there' -and $r.Out -match 'Data\\Beta.esp' -and @(Get-ChildItem -LiteralPath $game2 -Recurse -File).Count -eq 1) $r
$colNoRule = Join-Path $T 'col-norule'
Write-Col $colNoRule (Collection @($alphaE, $gammaE) @())
$game3 = Join-Path $T 'game3'
$r = Run @('-CollectionArchive', $colNoRule, '-Revision', '5', '-Game', $game3, '-Cache', $cache)
YesR 'two mods that share a file with no rule between them stop the run, and -Game is untouched' ($r.Code -eq 1 -and $r.Out -match 'No mod rule says which' -and $r.Out -match 'Alpha and Gamma \(1 files\)' -and -not (Test-Path -LiteralPath $game3)) $r

# ---- 7: -Revision through the API -----------------------------------------------------------
$colArc = Join-Path $T 'collection_6.7z'
Push-Location $colFull; & $sz a -t7z -y $colArc 'collection.json' 'bundled' 'patches' | Out-Null; Pop-Location
Control @{ addRevision = @{ n = 6; id = 906006; status = 'draft'; archive = $colArc } }
$game6 = Join-Path $T 'game6'
$n0 = Count
$r = Run @('-Revision', '6', '-Game', $game6, '-Cache', $cache)
$got = @(Since $n0)
YesR '-Revision reads the revision from Nexus and lays it out' ($r.Code -eq 0 -and $r.Out -match 'revision 6, draft, id 906006' -and (Test-Path -LiteralPath (Join-Path $game6 'Data\Gamma.esp'))) $r
$lj6 = Get-Content -Raw -LiteralPath (Join-Path $game6 'Thornswood Layout\layout.json') | ConvertFrom-Json
Yes 'its layout.json says the revision id, the status and the collection archive''s md5' ($lj6.collection.revision -eq 6 -and $lj6.collection.revisionId -eq '906006' -and $lj6.collection.status -eq 'draft' -and $lj6.collection.archiveMd5 -eq (Md5 $colArc))
Yes 'the v2 download_link was asked with the key, and the collection''s CDN download without it' (@($got | Where-Object { $_.path -eq '/v2/collections/515846/revisions/906006/download_link' -and $_.key -eq 'right' }).Count -eq 1 -and @($got | Where-Object { $_.path -eq '/cdn/collection/906006' -and $_.key -eq 'none' }).Count -eq 1)

# ---- the key, across every run ---------------------------------------------------
Yes ('no run printed the key, in ' + $script:outs.Count + ' runs') (@($script:outs | Where-Object { $_.Contains($KEY) }).Count -eq 0)
$v = @((State).violations)
Yes 'the stand-in saw no request without the key, and no key sent to the CDN' ($v.Count -eq 0)
foreach ($x in $v) { Write-Host ('      ' + $x) }
Done
