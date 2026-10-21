<#
  test-2914-nexus-scripts.ps1

      pwsh -NoProfile -File .\tests\test-2914-nexus-scripts.ps1

  The Nexus Mods scripts (#2914) against a stand-in Nexus on this machine's
  loopback address, never the real one: Send-NexusFile.ps1 (a new file
  version), Set-NexusDescription.ps1 (a line in a mod page's description),
  New-NexusRevision.ps1 and nexus-collection.js (a collection revision and
  publishing it), and Nexus.ps1, which they all talk through.

  WHY. Until 20 October Patrick uploaded every file and made every revision by
  hand. These scripts do it with his API key, and there is no key and no
  Nexus test site to try them on, so what they send is held here to the shapes
  in https://api.nexusmods.com/openapi.yaml (read on 20 October) by
  tests\fixtures\nexus-standin.js, which refuses what Nexus would refuse.

  WHAT IT HOLDS:
    1. the key: read only from the stand-in's own made-up key while the
       stand-in is set, sent on every API request with Application-Name and
       Application-Version, never to the storage addresses, never printed;
       with no key on the machine a script stops before it asks anything,
       saying where the key goes; Set-NexusKey.ps1 -Check says the key's
       account owns both mods, and the prompt never runs against a stand-in;
    2. the CRC-64/NVME the multipart upload is bound to, against the
       algorithm's published check value, and the md5;
    3. a new file version, under pwsh and under Windows PowerShell 5.1: -WhatIf
       writes nothing; a bad version, a version already there and a file that
       is not the mod's stop before any write; one part with md5 and
       Content-MD5, and many parts with the CRC, each make the version with
       the old one archived and print the new file id, size and md5; a refused
       version and an upload in a state the spec does not name stop saying
       what is on Nexus;
    4. a description: -WhatIf writes nothing; the line goes under the heading
       as its own paragraph and is read back; a second run leaves it; a page
       this cannot read back exactly, or text it cannot store, is refused;
       when Nexus keeps something else the run stops with the way back, and
       -From puts the page back;
    5. a collection revision: the collection_data is Vortex's own mapping; an
       entry with patches, hashes or a mod rule is refused; -WhatIf builds the
       archive and writes nothing; the real run uploads an archive with the
       same files as the published one and only the swapped entry changed,
       as a draft; a second draft, a base that is not the latest and a
       publish of something that is not a draft are refused; -Publish
       publishes it.

  Needs node. The collection part needs 7-Zip and says SKIP without it; the
  5.1 runs say SKIP where there is no Windows PowerShell. Everything it writes
  is under its own temp folder, which it removes.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
$rel = Join-Path $repo 'scripts\release'

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Skip([string]$what) { Write-Host "SKIP  $what" }
$script:standin = $null
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-2914-' + [Guid]::NewGuid().ToString('N').Substring(0, 10))
function Done {
    if ($script:standin -and -not $script:standin.HasExited) { $script:standin.Kill() }
    if (Test-Path -LiteralPath $T) { Remove-Item -LiteralPath $T -Recurse -Force }
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}
function Put([string]$path, [string]$text) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}
function Q([string]$s) { return '"' + (($s -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }

$node = Get-Command node -ErrorAction SilentlyContinue
Yes 'node is on PATH, for the stand-in Nexus' ($null -ne $node)
if ($null -eq $node) { Done }
$pwsh = (Get-Process -Id $PID).Path
. (Join-Path $PSScriptRoot 'Windows.ps1')
$winps = if ($OnWindows) { Get-WindowsPowerShell } else { '' }
$sz = ''
if ($env:ProgramFiles -and (Test-Path -LiteralPath (Join-Path $env:ProgramFiles '7-Zip\7z.exe'))) { $sz = Join-Path $env:ProgramFiles '7-Zip\7z.exe' }
if (-not $sz) { foreach ($n in '7z', '7zz', '7za') { $g = Get-Command $n -ErrorAction SilentlyContinue; if ($g) { $sz = $g.Source; break } } }

New-Item -ItemType Directory -Force -Path $T, (Join-Path $T 'save'), (Join-Path $T 'scratch'), (Join-Path $T 'appdata') | Out-Null

# ---- the stand-in ---------------------------------------------------------------
$KEY = 'standin-' + [Guid]::NewGuid().ToString('N')
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $node.Source; $psi.Arguments = Q (Join-Path $repo 'tests\fixtures\nexus-standin.js')
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.EnvironmentVariables['NEXUS_STANDIN_KEY'] = $KEY
$psi.EnvironmentVariables['NEXUS_STANDIN_SAVE'] = (Join-Path $T 'save')
$script:standin = [Diagnostics.Process]::Start($psi)
# A harness that stops part way still takes its stand-in and its folder with it.
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
function Control($h) { [void](Invoke-RestMethod -Method Post -Uri ($base + '/_control') -ContentType 'application/json' -Body ($h | ConvertTo-Json -Compress -Depth 5)) }
function Since([int]$n) { $all = @((State).requests); if ($all.Count -le $n) { return @() }; return @($all[$n..($all.Count - 1)]) }
function Count { return @((State).requests).Count }

# The children get the stand-in through the environment, and no real key.
$env:THORNSWOOD_NEXUS_STANDIN = $base
$env:THORNSWOOD_NEXUS_STANDIN_KEY = $KEY
$env:THORNSWOOD_NEXUS_API_KEY = $null
$env:THORNSWOOD_NEXUS_STANDIN_SINGLE_MAX = $null
$env:THORNSWOOD_SCRATCH_ROOT = (Join-Path $T 'scratch')
$realAppData = $env:LOCALAPPDATA

$script:outs = New-Object System.Collections.Generic.List[string]
function Run([string]$name, [string[]]$arguments, [switch]$Win51) {
    $exe = $pwsh
    if ($Win51) { $exe = $winps }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ((@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Q (Join-Path $rel $name))) + @($arguments | ForEach-Object { Q $_ }) + @('-NoPause')) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $e = $p.StandardError.ReadToEndAsync()
    $o = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $text = $o + $e.Result
    $script:outs.Add($text)
    return [pscustomobject]@{ Code = $p.ExitCode; Out = $text }
}
function Show($r) { Write-Host (($r.Out -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 14) -join "`n") -ForegroundColor DarkGray }
function YesR([string]$what, [bool]$cond, $r) { Yes $what $cond; if (-not $cond) { Show $r } }
function Writes($reqs) { return @($reqs | Where-Object { $_.method -ne 'GET' -and -not ($_.path -eq '/v2/graphql' -and -not ([string]$_.json.query).StartsWith('mutation')) }) }

$archive = Join-Path $T 'Thornswood Client Runtime-1.0.1.7z'
$bytes = New-Object byte[] 300000
(New-Object Random 2914).NextBytes($bytes)
[IO.File]::WriteAllBytes($archive, $bytes)
$md5 = (Get-FileHash -LiteralPath $archive -Algorithm MD5).Hash.ToLowerInvariant()

# ---- 1 and 2: the key, the CRC and the md5, in this process -------------------------
. (Join-Path $rel 'Nexus.ps1')
$crc = Get-NexusCrc64Nvme $archive
$check = [Convert]::ToBase64String([byte[]](0xAE, 0x8B, 0x14, 0x86, 0x0A, 0x79, 0x98, 0x88))
Yes 'CRC-64/NVME of "123456789" is the published check value AE8B14860A799888, most significant byte first' ([ThornswoodCrc64Nvme]::OfBytes([Text.Encoding]::ASCII.GetBytes('123456789')) -ceq $check -and $check -ceq 'rosUhgp5mIg=')
$facts = Get-NexusArchiveFacts $archive
Yes 'the md5 is the file''s md5, in hex and in base64' ($facts.Md5Hex -eq $md5 -and [Convert]::ToBase64String([Convert]::FromBase64String($facts.Md5Base64)) -eq $facts.Md5Base64 -and (($([Convert]::FromBase64String($facts.Md5Base64)) | ForEach-Object { $_.ToString('x2') }) -join '') -eq $md5)
Yes 'while the stand-in is set the key read is its made-up one' ((Read-NexusKey) -eq $KEY)
$env:THORNSWOOD_NEXUS_STANDIN = 'http://203.0.113.5:80'
$refused = ''; try { [void](Get-NexusBase) } catch { $refused = $_.Exception.Message }
Yes 'a stand-in address that is not loopback is refused' ($refused -match 'loopback')
$env:THORNSWOOD_NEXUS_STANDIN = $base

$env:THORNSWOOD_NEXUS_STANDIN = $null; $env:LOCALAPPDATA = (Join-Path $T 'appdata')
$n0 = Count
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192762', '-Archive', $archive, '-Version', '1.0.1')
$env:THORNSWOOD_NEXUS_STANDIN = $base; $env:LOCALAPPDATA = $realAppData
YesR 'with no key on the machine a file upload stops, naming the variable and the file' ($r.Code -eq 1 -and $r.Out -match 'THORNSWOOD_NEXUS_API_KEY' -and $r.Out -match 'Thornswood\\Nexus\\api-key\.txt' -and $r.Out -match 'Nothing was changed on Nexus') $r
Yes 'and asks nothing first' ((Count) -eq $n0)

$r = Run 'Set-NexusKey.ps1' @('-Check')
YesR 'Set-NexusKey.ps1 -Check says where the key is and that its account owns both mods' ($r.Code -eq 0 -and $r.Out -match 'owns 192001, Thornswood Content' -and $r.Out -match 'owns 192762, Thornswood Client Runtime' -and $r.Out -match 'THORNSWOOD_NEXUS_STANDIN_KEY') $r
$r = Run 'Set-NexusKey.ps1' @()
YesR 'and it never writes the real key file while the stand-in is set' ($r.Code -eq 1 -and $r.Out -match 'nothing was written') $r

# ---- 3: a new file version ---------------------------------------------------------
$n0 = Count
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192762', '-Archive', $archive, '-Version', '1.0.1', '-WhatIf')
$got = @(Since $n0)
YesR '-WhatIf reads the mod and says the upload and the version it would make' ($r.Code -eq 0 -and $r.Out -match ('POST /v3/uploads\s+\{"size_bytes":300000,"filename":"Thornswood Client Runtime-1\.0\.1\.7z","md5":"' + $md5 + '"\}') -and $r.Out -match 'POST /v3/mod-files/file-runtime/versions' -and $r.Out -match '"archive_existing_file":true' -and $r.Out -match 'which archives 1\.0\.0 \(file id 809366\)') $r
Yes '-WhatIf sends only reads' ($got.Count -ge 3 -and @(Writes $got).Count -eq 0)
Yes 'every API request carries the key and both Application headers' (@($got | Where-Object { $_.key -ne 'right' -or -not $_.appName -or $_.appVersion -notmatch '^\d+\.\d+' }).Count -eq 0)

$n0 = Count
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192762', '-Archive', $archive, '-Version', 'one point one!')
YesR 'a version Nexus refuses stops before anything is asked' ($r.Code -eq 1 -and $r.Out -match 'not a version Nexus takes' -and (Count) -eq $n0) $r
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192762', '-Archive', $archive, '-Version', '1.0.0')
YesR 'a version already on the file stops before any write' ($r.Code -eq 1 -and $r.Out -match 'already on that file, as file id 809366' -and @(Writes @(Since $n0)).Count -eq 0) $r
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192001', '-File', 'nothing of ours', '-Archive', $archive, '-Version', '1.3', '-WhatIf')
YesR 'a -File that is not the mod''s stops and lists its files' ($r.Code -eq 1 -and $r.Out -match 'no file of mod 192001 answers' -and $r.Out -match '"Thornswood Content", id file-content') $r
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192001', '-File', '809365', '-Archive', $archive, '-Version', '1.3', '-WhatIf')
YesR '-File finds the file by the file id of an old version' ($r.Code -eq 0 -and $r.Out -match 'POST /v3/mod-files/file-content/versions' -and $r.Out -match 'which archives 1\.2 \(file id 811029\)') $r
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192001', '-File', 'thornswood content', '-Archive', $archive, '-Version', '1.3', '-WhatIf')
YesR 'and by the file''s name' ($r.Code -eq 0 -and $r.Out -match 'POST /v3/mod-files/file-content/versions') $r

$n0 = Count
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192762', '-Archive', $archive, '-Version', '1.0.1', '-UpdateModVersion', '-Changelog', 'Drops a script nothing loads.')
$got = @(Since $n0)
YesR 'one part: the upload makes the version and prints its file id, size and md5' ($r.Code -eq 0 -and $r.Out -match 'File id\s+812345' -and $r.Out -match 'Size\s+300000 bytes' -and $r.Out -match ('md5\s+' + $md5)) $r
$mk = @($got | Where-Object { $_.method -eq 'POST' -and $_.path -eq '/v3/uploads' }) | Select-Object -First 1
Yes 'POST /v3/uploads carries the size, the name and the md5' ($null -ne $mk -and $mk.json.md5 -eq $md5 -and $mk.json.size_bytes -eq 300000 -and $mk.json.filename -eq 'Thornswood Client Runtime-1.0.1.7z')
$put = @($got | Where-Object { $_.path -like '/s3/single/*' }) | Select-Object -First 1
Yes 'the bytes go to the storage address with no key, with Content-MD5 and Content-Disposition' ($null -ne $put -and $put.key -eq 'none' -and $put.contentMd5 -eq $facts.Md5Base64 -and $put.contentDisposition -eq 'attachment; filename="Thornswood Client Runtime-1.0.1.7z"' -and $put.length -eq 300000)
$order = @($got | Where-Object { $_.method -ne 'GET' } | ForEach-Object { $_.method + ' ' + ($_.path -replace '[0-9a-f]{8}-[0-9a-f-]{27}', 'ID') })
Yes ('the writes go in the order of the API: ' + ($order -join ', ')) (($order -join '|') -eq 'POST /v3/uploads|PUT /s3/single/ID|POST /v3/uploads/ID/finalise|POST /v3/mod-files/file-runtime/versions|POST /v3/mods/mod-192762/changelogs')
Yes 'it waits until the upload is available before making the version' (@($got | Where-Object { $_.method -eq 'GET' -and $_.path -like '/v3/uploads/*' }).Count -eq 3)
$vr = @($got | Where-Object { $_.path -eq '/v3/mod-files/file-runtime/versions' -and $_.method -eq 'POST' }) | Select-Object -First 1
$vb = if ($vr) { $vr.json } else { [pscustomobject]@{ name = ''; version = ''; file_category = ''; archive_existing_file = $false; update_mod_version = $false; allow_mod_manager_download = $false; primary_mod_manager_download = $false } }
Yes 'the version keeps the name, takes main, archives the old one, updates the mod''s version and stays the mod manager download' ($vb.name -eq 'Thornswood Client Runtime' -and $vb.version -eq '1.0.1' -and $vb.file_category -eq 'main' -and $vb.archive_existing_file -eq $true -and $vb.update_mod_version -eq $true -and $vb.allow_mod_manager_download -eq $true -and $vb.primary_mod_manager_download -eq $true)
$st = State
Yes 'the stand-in has 1.0.0 archived and the changelog' (@($st.files.'file-runtime'.versions | Where-Object { $_.version -eq '1.0.0' -and $_.category -eq 'archived' }).Count -eq 1 -and @($st.changelogs | Where-Object { $_.version -eq '1.0.1' }).Count -eq 1)

$env:THORNSWOOD_NEXUS_STANDIN_SINGLE_MAX = '100000'
$n0 = Count
if ($winps) { $r = Run 'Send-NexusFile.ps1' @('-Mod', '192762', '-Archive', $archive, '-Version', '1.0.2') -Win51; $shell = 'Windows PowerShell 5.1' }
else { Skip 'this is not Windows, which is the only place Windows PowerShell 5.1 runs, so the multipart run is under pwsh'; $r = Run 'Send-NexusFile.ps1' @('-Mod', '192762', '-Archive', $archive, '-Version', '1.0.2'); $shell = 'pwsh' }
$env:THORNSWOOD_NEXUS_STANDIN_SINGLE_MAX = $null
$got = @(Since $n0)
YesR ("many parts, under $shell" + ': the version is made and its file id printed') ($r.Code -eq 0 -and $r.Out -match 'File id\s+812346' -and $r.Out -match ('md5\s+' + $md5)) $r
$mk = @($got | Where-Object { $_.path -eq '/v3/uploads/multipart' }) | Select-Object -First 1
$crc = Get-NexusCrc64Nvme $archive
Yes 'POST /v3/uploads/multipart carries the CRC-64/NVME and no md5' ($null -ne $mk -and $mk.json.crc64nvme -eq $crc -and $null -eq $mk.json.PSObject.Properties['md5'])
$parts = @($got | Where-Object { $_.path -like '/s3/part/*' })
$done = @($got | Where-Object { $_.path -like '/s3/complete/*' }) | Select-Object -First 1
Yes ('the ' + $parts.Count + ' parts and the complete go to storage with no key, and the complete goes to the address bound to the CRC, with no unsigned x-amz header') ($parts.Count -eq 5 -and @($parts | Where-Object { $_.key -ne 'none' }).Count -eq 0 -and $null -ne $done -and $done.key -eq 'none' -and $done.boundCrc -eq $crc -and $done.crc -eq '' -and $done.contentType -eq 'application/xml')

if ($winps) {
    $n0 = Count
    $r = Run 'Send-NexusFile.ps1' @('-Mod', '192001', '-Archive', $archive, '-Version', '1.3', '-Category', 'main') -Win51
    YesR 'one part under Windows PowerShell 5.1 too' ($r.Code -eq 0 -and $r.Out -match 'File id\s+812347') $r
    $put = @((Since $n0) | Where-Object { $_.path -like '/s3/single/*' }) | Select-Object -First 1
    Yes 'with the same Content-MD5 and Content-Disposition' ($null -ne $put -and $put.contentMd5 -eq $facts.Md5Base64 -and $put.contentDisposition -eq 'attachment; filename="Thornswood Client Runtime-1.0.1.7z"')
}
else { Skip 'one part under Windows PowerShell 5.1: this is not Windows' }

Control @{ unboundComplete = $true }
$env:THORNSWOOD_NEXUS_STANDIN_SINGLE_MAX = '100000'
$n0 = Count
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192762', '-Archive', $archive, '-Version', '1.0.3')
$env:THORNSWOOD_NEXUS_STANDIN_SINGLE_MAX = $null
Control @{ unboundComplete = $false }
YesR 'a complete address not bound to the CRC stops before any part is sent' ($r.Code -eq 1 -and $r.Out -match 'is not bound to the archive''s CRC-64/NVME' -and @((Since $n0) | Where-Object { $_.path -like '/s3/*' }).Count -eq 0) $r

Control @{ versionFails = $true }
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192762', '-Archive', $archive, '-Version', '1.0.3')
Control @{ versionFails = $false }
YesR 'a refused version stops with Nexus''s reason and says the upload is there, attached to nothing' ($r.Code -eq 1 -and $r.Out -match 'was refused: HTTP 422' -and $r.Out -match 'told to refuse this version' -and $r.Out -match 'On Nexus from this run: upload [0-9a-f-]+ is processed and available, attached to nothing') $r
Control @{ unknownState = 'quarantined' }
$n0 = Count
$r = Run 'Send-NexusFile.ps1' @('-Mod', '192762', '-Archive', $archive, '-Version', '1.0.3')
Control @{ unknownState = '' }
YesR 'an upload in a state the spec does not name stops, and no version is made' ($r.Code -eq 1 -and $r.Out -match '"quarantined", which is neither created nor available' -and @((Since $n0) | Where-Object { $_.path -like '/v3/mod-files/*' -and $_.method -eq 'POST' }).Count -eq 0) $r

# ---- 4: a description ----------------------------------------------------------------
$LINE = 'THIS MOD IS NOT MADE, GUARANTEED OR SUPPORTED BY ZENIMAX OR ITS AFFILIATES.'
function StoredOf([string]$t) { return $t.Replace('\', '&#92;').Replace("`n", "`n<br />") }
$contentWas = "[size=4][b]Description[/b][/size]`nThornswood Content is the plugin for Thornswood.`n`n[size=4][b]Installation[/b][/size]`nThe collection installs it."
$runtimeWas = "[size=4][b]Thornswood Client Runtime[/b][/size]`n`nThe runtime, in Data\Platform\Distribution.`n`n[b]What is in it[/b]`nThe server's files."
$n0 = Count
$r = Run 'Set-NexusDescription.ps1' @('-Mod', '192001,192762', '-AddLine', $LINE, '-WhatIf')
YesR '-WhatIf shows where the line goes on both pages and sends no edit' ($r.Code -eq 0 -and ([regex]::Matches($r.Out, '2  THIS MOD IS NOT MADE')).Count -eq 2 -and @(Writes @(Since $n0)).Count -eq 0) $r
$n0 = Count
$r = Run 'Set-NexusDescription.ps1' @('-Mod', '192001,192762', '-AddLine', $LINE)
$got = @(Since $n0)
$patches = @($got | Where-Object { $_.method -eq 'PATCH' })
$wantC = "[size=4][b]Description[/b][/size]`n$LINE`n`nThornswood Content is the plugin for Thornswood.`n`n[size=4][b]Installation[/b][/size]`nThe collection installs it."
$wantR = "[size=4][b]Thornswood Client Runtime[/b][/size]`n$LINE`n`nThe runtime, in Data\Platform\Distribution.`n`n[b]What is in it[/b]`nThe server's files."
YesR 'the line goes under each heading as its own paragraph, and each page is read back' ($r.Code -eq 0 -and $patches.Count -eq 2 -and $patches[0].path -eq '/v3/mods/mod-192001' -and $patches[0].json.description -ceq $wantC -and $patches[1].json.description -ceq $wantR -and ([regex]::Matches($r.Out, 'Nexus kept exactly what was sent')).Count -eq 2) $r
$st = State
Yes 'the stand-in keeps both in the stored form' ($st.mods.'192001'.description -ceq (StoredOf $wantC) -and $st.mods.'192762'.description -ceq (StoredOf $wantR))
$kept = @(Get-ChildItem -LiteralPath (Join-Path $T 'scratch\nexus-description') -Filter '192762-*-before.txt' -ErrorAction SilentlyContinue)
Yes 'the description as it was is kept in the scratch folder, as the editor holds it' ($kept.Count -eq 1 -and [IO.File]::ReadAllText($kept[0].FullName) -ceq $runtimeWas)
$n0 = Count
$r = Run 'Set-NexusDescription.ps1' @('-Mod', '192001', '-AddLine', $LINE)
YesR 'a second run finds the line there and leaves the page' ($r.Code -eq 0 -and $r.Out -match 'already has the line' -and @((Since $n0) | Where-Object { $_.method -eq 'PATCH' }).Count -eq 0) $r
$n0 = Count
$r = Run 'Set-NexusDescription.ps1' @('-Mod', '192762', '-AddLine', 'Use <b> here')
YesR 'text with a < is refused before anything is asked' ($r.Code -eq 1 -and $r.Out -match 'has <' -and (Count) -eq $n0) $r
Control @{ setStored = @{ mod = '192762'; stored = (StoredOf $wantR) + "`n<br />Fish &amp; chips" } }
$n0 = Count
$r = Run 'Set-NexusDescription.ps1' @('-Mod', '192762', '-AddLine', 'Another line.')
YesR 'a page with an & this has not seen stored is refused, with no edit' ($r.Code -eq 1 -and $r.Out -match 'cannot be sure of sending it back unchanged' -and @((Since $n0) | Where-Object { $_.method -eq 'PATCH' }).Count -eq 0) $r
Control @{ setStored = @{ mod = '192762'; stored = (StoredOf $wantR) } }
$r = Run 'Set-NexusDescription.ps1' @('-Mod', '192762', '-From', $kept[0].FullName)
YesR '-From puts a page back from the file kept before the edit, and reads it back as it was' ($r.Code -eq 0 -and $kept.Count -eq 1 -and (State).mods.'192762'.description -ceq (StoredOf $runtimeWas)) $r
Control @{ storeOdd = $true }
$r = Run 'Set-NexusDescription.ps1' @('-Mod', '192762', '-AddLine', $LINE)
Control @{ storeOdd = $false }
YesR 'when Nexus keeps something other than what was sent the run stops with the command that puts it back' ($r.Code -eq 1 -and $r.Out -match 'Nexus kept something other than what was sent' -and $r.Out -match 'Set-NexusDescription\.ps1 -Mod 192762 -From ".+-before\.txt"' -and $r.Out -match 'On Nexus from this run: mod 192762 description edited') $r

# ---- 5: a collection revision -----------------------------------------------------
$js = Join-Path $rel 'nexus-collection.js'
# A name with a letter outside ASCII, so the round trip through node is held to keep it.
$E = [string][char]0x00C9
$fixture = [ordered]@{
    info = [ordered]@{ author = 'EvilPatrick06'; authorUrl = ''; name = 'Thornswood'; description = ''; installInstructions = 'Install it.'; domainName = 'skyrimspecialedition'; gameVersions = @('1.6.1170.0') }
    mods = @(
        [ordered]@{ name = 'Thornswood Content'; version = '1.2'; optional = $false; domainName = 'skyrimspecialedition'
            source = [ordered]@{ type = 'nexus'; modId = 192001; fileId = 811029; md5 = 'ee881bf2a869d0810113a82ca1405445'; fileSize = 660022; logicalFilename = 'Thornswood Content'; updatePolicy = 'exact'; tag = 'QXsOYonzPMT' }
            patches = [ordered]@{ 'Thornswood-Content.esp' = '023593E0' }; author = 'EvilPatrick06'; details = [ordered]@{ category = 'Miscellaneous'; type = '' }; phase = 0 },
        [ordered]@{ name = 'Thornswood Client Runtime'; version = '1.0.0'; optional = $false; domainName = 'skyrimspecialedition'
            source = [ordered]@{ type = 'nexus'; modId = 192762; fileId = 809366; md5 = 'c515679068f6563750b1ca1f9260031f'; fileSize = 148896610; logicalFilename = 'Thornswood Client Runtime'; updatePolicy = 'exact'; tag = 'Km2wtoJLmxn' }
            author = 'EvilPatrick06'; details = [ordered]@{ category = 'Utilities'; type = '' }; phase = 0 },
        [ordered]@{ name = ('A Fishing Mod, ' + $E + 'dition'); version = '1.0.0'; optional = $false; domainName = 'skyrimspecialedition'
            source = [ordered]@{ type = 'nexus'; modId = 47618; fileId = 191234; md5 = 'fa1fe7613d21ab5826d4a3a3b258f14a'; fileSize = 1000; logicalFilename = 'Fishing In Skyrim'; updatePolicy = 'exact'; tag = 'abcDEF12345' }
            author = 'Someone'; details = [ordered]@{ category = 'Gameplay'; type = '' }; phase = 0 },
        [ordered]@{ name = 'A Hashed Mod'; version = '2.0'; optional = $true; domainName = 'skyrimspecialedition'
            source = [ordered]@{ type = 'nexus'; modId = 1111; fileId = 2222; md5 = '00000000000000000000000000000001'; fileSize = 10; logicalFilename = 'Hashed'; updatePolicy = 'exact'; tag = 'zzz' }
            hashes = @([ordered]@{ path = 'a.esp'; md5 = '00000000000000000000000000000002' }); author = 'Someone'; details = [ordered]@{ category = 'Gameplay'; type = '' }; phase = 1 }
    )
    modRules = @([ordered]@{ type = 'before'; reference = [ordered]@{ fileMD5 = 'ee881bf2a869d0810113a82ca1405445'; logicalFileName = 'Thornswood Content'; versionMatch = '1.2.0' }
                           source = [ordered]@{ fileMD5 = 'fa1fe7613d21ab5826d4a3a3b258f14a'; logicalFileName = 'Fishing In Skyrim'; versionMatch = '1.0.0' } })
    tools = @(); plugins = @(); pluginRules = [ordered]@{ plugins = @(); groups = @() }; collectionConfig = [ordered]@{ recommendNewProfile = $true; referenceTagScheme = 'v1' }
}
$cj = Join-Path $T 'fixture\collection.json'
# Written by node, so the fixture is in the layout Vortex writes and the round trip is the real one.
Put (Join-Path $T 'fixture-in.json') ($fixture | ConvertTo-Json -Depth 8)
New-Item -ItemType Directory -Force -Path (Join-Path $T 'fixture\patches\Thornswood Content'), (Join-Path $T 'fixture\bundled') | Out-Null
& $node.Source -e "const fs=require('fs');fs.writeFileSync(process.argv[2], JSON.stringify(JSON.parse(fs.readFileSync(process.argv[1],'utf8')), undefined, 2))" (Join-Path $T 'fixture-in.json') $cj
Put (Join-Path $T 'fixture\patches\Thornswood Content\Thornswood-Content.esp.diff') 'BSDIFF40'

# The mapping against the payload Vortex's toV3CollectionPayload makes of it.
$sw = Join-Path $T 'swap-runtime.json'
Put $sw ('[{"modId":"192762","fileId":"812346","version":"1.0.2","md5":"' + $md5 + '","fileSize":300000,"logicalFilename":"Thornswood Client Runtime"}]')
$o1 = Join-Path $T 'map-collection.json'; $o2 = Join-Path $T 'map-payload.json'
$said = & $node.Source $js $cj $sw $o1 $o2
Yes 'nexus-collection.js changes only the runtime entry''s version, file id, md5 and size' ($LASTEXITCODE -eq 0 -and (@($said) -join '|') -eq ('Thornswood Client Runtime' + "`t" + 'version' + "`t" + '1.0.0' + "`t" + '1.0.2|Thornswood Client Runtime' + "`t" + 'source.fileId' + "`t" + '809366' + "`t" + '812346|Thornswood Client Runtime' + "`t" + 'source.md5' + "`t" + 'c515679068f6563750b1ca1f9260031f' + "`t" + $md5 + '|Thornswood Client Runtime' + "`t" + 'source.fileSize' + "`t" + '148896610' + "`t" + '300000'))
$wantPayload = '{"adult_content":false,"collection_manifest":{"info":{"author":"EvilPatrick06","author_url":null,"name":"Thornswood","description":null,"summary":null,"domain_name":"skyrimspecialedition","game_versions":["1.6.1170.0"]},"mods":[' +
    '{"name":"Thornswood Content","version":"1.2","optional":false,"domain_name":"skyrimspecialedition","source":{"type":"nexus","mod_id":"192001","file_id":"811029","md5":"ee881bf2a869d0810113a82ca1405445","file_size":null,"update_policy":"exact","logical_filename":"Thornswood Content","file_expression":null,"url":null,"adult_content":null},"author":"EvilPatrick06"},' +
    '{"name":"Thornswood Client Runtime","version":"1.0.2","optional":false,"domain_name":"skyrimspecialedition","source":{"type":"nexus","mod_id":"192762","file_id":"812346","md5":"' + $md5 + '","file_size":null,"update_policy":"exact","logical_filename":"Thornswood Client Runtime","file_expression":null,"url":null,"adult_content":null},"author":"EvilPatrick06"},' +
    '{"name":"A Fishing Mod, ' + $E + 'dition","version":"1.0.0","optional":false,"domain_name":"skyrimspecialedition","source":{"type":"nexus","mod_id":"47618","file_id":"191234","md5":"fa1fe7613d21ab5826d4a3a3b258f14a","file_size":null,"update_policy":"exact","logical_filename":"Fishing In Skyrim","file_expression":null,"url":null,"adult_content":null},"author":"Someone"},' +
    '{"name":"A Hashed Mod","version":"2.0","optional":true,"domain_name":"skyrimspecialedition","source":{"type":"nexus","mod_id":"1111","file_id":"2222","md5":"00000000000000000000000000000001","file_size":null,"update_policy":"exact","logical_filename":"Hashed","file_expression":null,"url":null,"adult_content":null},"author":"Someone"}' +
    ']},"collection_schema_id":1}'
Yes 'the collection_data is Vortex''s mapping: empty strings to null, ids as strings, file_size dropped by filterInfo, schema 1' ((Test-Path -LiteralPath $o2) -and ([IO.File]::ReadAllText($o2, [Text.Encoding]::UTF8)) -ceq $wantPayload)
& $node.Source -e "const fs=require('fs');const a=JSON.parse(fs.readFileSync(process.argv[1],'utf8')),t=fs.readFileSync(process.argv[2],'utf8'),b=JSON.parse(t);const layout=t===JSON.stringify(b,undefined,2);const r=b.mods[1];r.version='1.0.0';r.source.fileId=809366;r.source.md5='c515679068f6563750b1ca1f9260031f';r.source.fileSize=148896610;process.exit(layout&&JSON.stringify(a)===JSON.stringify(b)?0:1)" $cj $o1
Yes 'and the rest of collection.json is as it was, in the layout Vortex writes' ($LASTEXITCODE -eq 0)
foreach ($case in @(
        @('192001', 'patches', 'Thornswood Content carries patches'),
        @('1111', 'hashes', 'A Hashed Mod carries hashes'),
        @('47618', 'a mod rule', 'mod rules name A Fishing Mod'))) {
    Put $sw ('[{"modId":"' + $case[0] + '","fileId":"999","version":"9","md5":"' + $md5 + '","fileSize":1,"logicalFilename":"x"}]')
    $null = & $node.Source $js $cj $sw (Join-Path $T 'no.json') (Join-Path $T 'no-payload.json') 2>$null
    Yes ('an entry with ' + $case[1] + ' is refused, and nothing is written') ($LASTEXITCODE -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $T 'no.json')))
}

if (-not $sz) { Skip 'the collection revision runs: 7-Zip is not on this machine'; Done }
$baseArchive = Join-Path $T 'vortex\collection_7essxf_2_2026-10-03T17-33-45Z.7z'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $baseArchive) | Out-Null
Push-Location (Join-Path $T 'fixture'); & $sz a -t7z -y $baseArchive 'bundled' 'collection.json' 'patches' | Out-Null; Pop-Location
Yes 'a published revision''s archive stands in for the one in Vortex''s downloads' (Test-Path -LiteralPath $baseArchive)
$newFileArchive = $archive

$n0 = Count
# Content's live file is 1.3 when the 5.1 run above made it, and 1.2 otherwise.
$contentLive = if ($winps) { '812347' } else { '811029' }
$r = Run 'New-NexusRevision.ps1' @('-From', $baseArchive, '-Mod', '192001', '-FileId', $contentLive, '-Archive', $newFileArchive, '-WhatIf')
YesR 'a revision that moves Thornswood Content is refused, because of its patch' ($r.Code -eq 1 -and $r.Out -match 'Thornswood Content carries patches' -and @(Writes @(Since $n0)).Count -eq 0) $r
$r = Run 'New-NexusRevision.ps1' @('-From', $baseArchive, '-Mod', '192762', '-FileId', '812345', '-Archive', $newFileArchive, '-WhatIf')
YesR 'a file id that has been archived is refused' ($r.Code -eq 1 -and $r.Out -match 'is archived, not a file people can download now') $r
$r = Run 'New-NexusRevision.ps1' @('-From', $baseArchive, '-Mod', '192762', '-FileId', '811029', '-Archive', $newFileArchive, '-WhatIf')
YesR 'a file id of another mod is refused' ($r.Code -eq 1 -and $r.Out -match 'File id 811029 is not a file of mod 192762') $r

$n0 = Count
$r = Run 'New-NexusRevision.ps1' @('-From', $baseArchive, '-Mod', '192762', '-FileId', '812346', '-Archive', $newFileArchive, '-WhatIf')
$built = Join-Path $T 'scratch\nexus-revision-7essxf\out\collection_3.7z'
YesR '-WhatIf builds collection_3.7z with the same files as revision 2 and writes nothing' ($r.Code -eq 0 -and $r.Out -match 'source\.fileId: 809366 -> 812346' -and $r.Out -match 'the same 5 files and folders as revision 2' -and (Test-Path -LiteralPath $built) -and @(Writes @(Since $n0)).Count -eq 0) $r
# Issue #2969: with no -From the published revision comes from Nexus, as it
# does in a cloud session, where there is no Vortex.
Control @{ addRevision = @{ n = 2; id = 801014; status = 'published'; archive = $baseArchive } }
$n0 = Count
$r = Run 'New-NexusRevision.ps1' @('-Mod', '192762', '-FileId', '812346', '-Archive', $newFileArchive, '-WhatIf')
$got = @(Since $n0)
YesR 'with no -From it downloads the published revision from Nexus, the CDN getting no key' ($r.Code -eq 0 -and $r.Out -match 'revision 2, the latest published' -and $r.Out -match 'the same 5 files and folders as revision 2' -and @($got | Where-Object { $_.path -eq '/v2/collections/515846/revisions/801014/download_link' }).Count -eq 1 -and @($got | Where-Object { $_.path -like '/cdn/collection/801014*' -and $_.key -eq 'none' }).Count -eq 1 -and @(Writes $got).Count -eq 0) $r

$n0 = Count
$r = Run 'New-NexusRevision.ps1' @('-From', $baseArchive, '-Mod', '192762', '-FileId', '812346', '-Archive', $newFileArchive)
$got = @(Since $n0)
YesR 'the real run makes revision 3 as a draft' ($r.Code -eq 0 -and $r.Out -match 'revision 3, draft, id 900003' -and $r.Out -match 'New-NexusRevision\.ps1 -Publish 3') $r
$order = @($got | Where-Object { $_.method -ne 'GET' -and $_.path -ne '/v2/graphql' } | ForEach-Object { $_.method + ' ' + ($_.path -replace '[0-9a-f]{8}-[0-9a-f-]{27}', 'ID') })
Yes ('it uploads with md5 and then makes the revision: ' + ($order -join ', ')) (($order -join '|') -eq 'POST /v3/uploads|PUT /s3/single/ID|POST /v3/uploads/ID/finalise|POST /v3/collections/515846/revisions')
$st = State
$up = @($st.uploads | Where-Object { $_.filename -eq 'collection_3.7z' }) | Select-Object -First 1
$saved = if ($up) { Join-Path $T ('save\' + $up.id + '.bin') } else { '' }
Yes 'the upload is the archive built, bound to its md5' ($up -and $up.md5 -eq (Get-FileHash -LiteralPath $built -Algorithm MD5).Hash.ToLowerInvariant() -and (Test-Path -LiteralPath $saved) -and (Get-FileHash -LiteralPath $saved).Hash -eq (Get-FileHash -LiteralPath $built).Hash)
$x = Join-Path $T 'unpacked'
& $sz x -y ('-o' + $x) $built | Out-Null
Yes 'the archive holds collection.json, patches and the empty bundled folder, as Vortex packs them' ((Test-Path -LiteralPath (Join-Path $x 'collection.json')) -and (Test-Path -LiteralPath (Join-Path $x 'patches\Thornswood Content\Thornswood-Content.esp.diff')) -and (Test-Path -LiteralPath (Join-Path $x 'bundled') -PathType Container))
& $node.Source -e "const fs=require('fs');const a=JSON.parse(fs.readFileSync(process.argv[1],'utf8')),b=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));const r=b.mods[1];if(r.source.fileId!==812346||r.version!=='1.0.2')process.exit(2);r.version='1.0.0';r.source.fileId=809366;r.source.md5='c515679068f6563750b1ca1f9260031f';r.source.fileSize=148896610;process.exit(JSON.stringify(a)===JSON.stringify(b)?0:1)" $cj (Join-Path $x 'collection.json')
Yes 'its collection.json is revision 2''s with only the runtime entry moved' ($LASTEXITCODE -eq 0)
$rv = (State).collection.revisions.PSObject.Properties['3']
if ($rv) { $rv = $rv.Value }
Yes 'the revision''s collection_data names the new runtime file' ($null -ne $rv -and $rv.status -eq 'draft' -and @($rv.data.collection_manifest.mods | Where-Object { $_.source.mod_id -eq '192762' -and $_.source.file_id -eq '812346' -and $_.source.md5 -eq $md5 }).Count -eq 1)

$r = Run 'New-NexusRevision.ps1' @('-From', $baseArchive, '-Mod', '192762', '-FileId', '812346', '-Archive', $newFileArchive, '-WhatIf')
YesR 'while revision 3 is a draft another one is refused' ($r.Code -eq 1 -and $r.Out -match 'Revision 3 is already a draft') $r
$n0 = Count
$r = Run 'New-NexusRevision.ps1' @('-Publish', '3', '-WhatIf')
YesR '-Publish -WhatIf names the revision and sends no mutation' ($r.Code -eq 0 -and $r.Out -match 'publishRevision\(revisionId: "900003"\)' -and @(Writes @(Since $n0)).Count -eq 0) $r
$n0 = Count
$r = Run 'New-NexusRevision.ps1' @('-Publish', '3')
$mut = @((Since $n0) | Where-Object { $_.path -eq '/v2/graphql' -and ([string]$_.json.query).StartsWith('mutation') }) | Select-Object -First 1
YesR '-Publish publishes the draft with publishRevision and reads it back as the latest' ($r.Code -eq 0 -and $r.Out -match 'Revision 3 is published' -and $null -ne $mut -and $mut.key -eq 'right' -and [string]$mut.json.variables.revisionId -eq '900003' -and (State).collection.latest -eq 3) $r
$r = Run 'New-NexusRevision.ps1' @('-Publish', '3')
YesR 'publishing it again is refused' ($r.Code -eq 1 -and $r.Out -match 'Revision 3 is published, not a draft') $r
$r = Run 'New-NexusRevision.ps1' @('-From', $baseArchive, '-Mod', '192762', '-FileId', '812346', '-Archive', $newFileArchive, '-WhatIf')
YesR 'starting from revision 2 once 3 is published is refused' ($r.Code -eq 1 -and $r.Out -match 'latest published revision is 3') $r

# ---- the key, across every run ---------------------------------------------------
Yes ('no run printed the key, in ' + $script:outs.Count + ' runs') (@($script:outs | Where-Object { $_.Contains($KEY) }).Count -eq 0)
$v = @((State).violations)
Yes 'the stand-in saw no request without the key or the Application headers, and no key sent to storage' ($v.Count -eq 0)
foreach ($x in $v) { Write-Host ('      ' + $x) }
Done
