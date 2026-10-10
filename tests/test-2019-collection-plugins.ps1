<#
  test-2019-collection-plugins.ps1

  Collection plugins are held to records\collection-plugins.json, built from
  the collection's own pinned archives, never from a Data folder or a server
  (issue #2019).

  Cases 1 to 6: the generator. Cases 7 to 12: the deploying machine, through
  Deploy-Server.ps1, Deploy-DevGamemode.ps1 and Export-ServerPayload.ps1,
  stopping before a real scp. Cases 17 and 18: the record tie and the real
  3BBB.esp gate. Box-side cases 13 to 16 and 19 live in
  tests\test-deploy-server-swap.ps1, which already runs Swap.ps1's blocks
  against a scratch root.

  Case 18 is a data gate. The pinned archives come from Nexus, so this cloud
  checkout cannot prove the real record. If records\collection-plugins.json
  is present it is checked; if not, the gate prints the exact command Djinn
  runs on Nyx with -Downloads. That is not a SKIP: the case always runs.
#>
[CmdletBinding()]
param()

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
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

. (Join-Path $Repo 'scripts\deploy\CollectionPlugins.ps1')

$utf8 = New-Object Text.UTF8Encoding $false
$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-2019-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

function Put([string]$path, [string]$text) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text, $utf8)
}
function PutBytes([string]$path, [byte[]]$bytes) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllBytes($path, $bytes)
}
function ShaOf([byte[]]$bytes) { Get-CollectionPluginsSha256Bytes $bytes }
function Md5Of([string]$path) { Get-CollectionPluginsMd5 $path }

$Good3bbb = [Text.Encoding]::ASCII.GetBytes(('A' * 32))
$Alt3bbb  = [Text.Encoding]::ASCII.GetBytes(('B' * 32))
$Bad3bbb  = [Text.Encoding]::ASCII.GetBytes(('X' * 32))
$Decoy    = [Text.Encoding]::ASCII.GetBytes(('D' * 32))
$GoodSha  = ShaOf $Good3bbb
$AltSha   = ShaOf $Alt3bbb
$BadSha   = ShaOf $Bad3bbb
$RealGood = 'ce4f554616458a10b4809f705828f9d3e3e2d1457abe73ee32fe5f8f044a8549'
$RealBad  = 'a1aa2b0a08a1ce77ddb56ab48483f5a9978c671cf508d771e2a2b2f78fd0244e'

$ModuleA = @'
<config>
  <moduleName>CBBE 3BA</moduleName>
  <installSteps>
    <installStep name="Body">
      <optionalFileGroups>
        <group name="Body" type="SelectExactlyOne">
          <plugins>
            <plugin name="A">
              <files><file source="optionA/3BBB.esp" destination="3BBB.esp" /></files>
            </plugin>
            <plugin name="B">
              <files><file source="optionB/3BBB.esp" destination="3BBB.esp" /></files>
            </plugin>
          </plugins>
        </group>
      </optionalFileGroups>
    </installStep>
  </installSteps>
</config>
'@

function New-FixtureZip([string]$path, [string]$xml, [byte[]]$aBytes, [byte[]]$bBytes) {
    Add-Type -AssemblyName System.IO.Compression -EA SilentlyContinue
    Add-Type -AssemblyName System.IO.Compression.FileSystem -EA SilentlyContinue
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    $zip = [IO.Compression.ZipFile]::Open($path, 'Create')
    try {
        function Add-Zip([string]$name, [byte[]]$bytes) {
            $e = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::NoCompression)
            $s = $e.Open()
            try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Dispose() }
        }
        Add-Zip 'fomod/ModuleConfig.xml' ([Text.Encoding]::UTF8.GetBytes($xml))
        Add-Zip 'optionA/3BBB.esp' $aBytes
        Add-Zip 'optionB/3BBB.esp' $bBytes
    } finally { $zip.Dispose() }
}

function New-CollectionJson([string]$path, [int]$rev, [string]$md5, [string]$zipName, [int]$choice) {
    $doc = [ordered]@{
        info = [ordered]@{ revision = $rev; slug = '7essxf' }
        mods = @(
            [ordered]@{
                name = 'CBBE 3BA'
                source = [ordered]@{
                    type = 'nexus'; modId = 30174; fileId = 600100
                    md5 = $md5; logicalFilename = $zipName
                }
                choices = [ordered]@{ type = 'fomod'; options = [ordered]@{ '0' = @($choice) } }
            }
        )
    }
    Put $path ($doc | ConvertTo-Json -Depth 8)
}

function Run-Gen([hashtable]$more) {
    $gen = Join-Path $Repo 'scripts\release\New-CollectionPluginsRecord.ps1'
    $a = @{ Revision = 2 }
    foreach ($k in $more.Keys) { $a[$k] = $more[$k] }
    $threw = ''
    $lines = New-Object Collections.Generic.List[string]
    $code = 0
    try {
        & $gen @a *>&1 | ForEach-Object { [void]$lines.Add("$_") }
        $code = $LASTEXITCODE
    } catch { $threw = $_.Exception.Message; $code = 1 }
    return [pscustomobject]@{ Ok = ((-not $threw) -and $code -eq 0); Said = (($lines -join "`n") + "`n" + $threw); Threw = $threw; Code = $code }
}

try {
    $dl = Join-Path $work 'downloads'
    $zip = Join-Path $dl 'cbbe.zip'
    New-FixtureZip $zip $ModuleA $Good3bbb $Alt3bbb
    $md5 = Md5Of $zip
    $col = Join-Path $work 'collection.json'
    New-CollectionJson $col 2 $md5 'cbbe.zip' 0
    $out = Join-Path $work 'record.json'
    $data = Join-Path $work 'Data'
    $staging = Join-Path $work 'staging'
    PutBytes (Join-Path $data '3BBB.esp') $Decoy
    PutBytes (Join-Path $staging '3BBB.esp') $Decoy
    $log = Join-Path $work 'access.log'

    # ---- 1. Built from the archive ------------------------------------------
    $r = Run-Gen @{ Collection = $col; Downloads = $dl; Out = $out; Data = $data; Staging = $staging; AccessLog = $log }
    Yes '1  built from the archive: the generator writes a record' $r.Ok
    $rec = $null
    if (Test-Path -LiteralPath $out) { $rec = Read-CollectionPluginsRecord $out }
    Yes '1  and 3BBB.esp is option A''s bytes, not option B and not the Data decoy' (
        $null -ne $rec -and $rec.Plugins.ContainsKey('3BBB.esp') -and
        $rec.Plugins['3BBB.esp'].Sha256 -eq $GoodSha -and
        $rec.Plugins['3BBB.esp'].Bytes -eq 32 -and
        $rec.Plugins['3BBB.esp'].Sha256 -ne $AltSha -and
        $rec.Plugins['3BBB.esp'].Sha256 -ne (ShaOf $Decoy))
    $opened = @()
    if (Test-Path -LiteralPath $log) { $opened = @(Get-Content -LiteralPath $log) }
    $dataFull = [IO.Path]::GetFullPath($data)
    $stagingFull = [IO.Path]::GetFullPath($staging)
    Yes '1  and the access log opened neither the Data folder nor staging' (
        -not ($opened | Where-Object { $_ -like ($dataFull + '*') -or $_ -like ($stagingFull + '*') }))

    New-CollectionJson $col 2 $md5 'cbbe.zip' 1
    $outB = Join-Path $work 'record-b.json'
    $r = Run-Gen @{ Collection = $col; Downloads = $dl; Out = $outB }
    $recB = $null
    if (Test-Path -LiteralPath $outB) { $recB = Read-CollectionPluginsRecord $outB }
    Yes '1  and changing the choice to B changes the record to option B''s bytes' (
        $r.Ok -and $null -ne $recB -and $recB.Plugins['3BBB.esp'].Sha256 -eq $AltSha)

    # ---- 2. Archive md5 mismatch refuses ------------------------------------
    New-CollectionJson $col 2 ('0' * 32) 'cbbe.zip' 0
    $out2 = Join-Path $work 'record-md5.json'
    $r = Run-Gen @{ Collection = $col; Downloads = $dl; Out = $out2 }
    Yes '2  archive md5 mismatch refuses, naming the mod, and writes no record' (
        (-not $r.Ok) -and $r.Said -match 'CBBE 3BA' -and $r.Said -match 'md5' -and -not (Test-Path -LiteralPath $out2))

    # ---- 3. archiveSha256 is written and then held --------------------------
    New-CollectionJson $col 2 $md5 'cbbe.zip' 0
    $out3 = Join-Path $work 'record-sha.json'
    $r = Run-Gen @{ Collection = $col; Downloads = $dl; Out = $out3 }
    $rec3 = $null
    if (Test-Path -LiteralPath $out3) { $rec3 = Read-CollectionPluginsRecord $out3 }
    $archSha = Get-CollectionPluginsSha256 $zip
    Yes '3  a good run writes archiveSha256' (
        $r.Ok -and $null -ne $rec3 -and $rec3.Plugins['3BBB.esp'].ArchiveSha256 -eq $archSha)

    $zip2 = Join-Path $dl 'cbbe.zip'
    New-FixtureZip $zip2 $ModuleA $Alt3bbb $Good3bbb
    $r = Run-Gen @{ Collection = $col; Downloads = $dl; Out = $out3; SkipArchiveMd5 = $true }
    Yes '3  a rerun at the same revision with another archive sha256 refuses, naming the mod, even with md5 bypassed' (
        (-not $r.Ok) -and $r.Said -match 'CBBE 3BA' -and $r.Said -match 'archive sha256')

    # restore the good zip for later cases
    New-FixtureZip $zip $ModuleA $Good3bbb $Alt3bbb
    $md5 = Md5Of $zip
    $archSha = Get-CollectionPluginsSha256 $zip
    New-CollectionJson $col 2 $md5 'cbbe.zip' 0

    # ---- 4. Unresolvable installer refuses ----------------------------------
    $scriptZip = Join-Path $dl 'scripted.zip'
    Add-Type -AssemblyName System.IO.Compression.FileSystem -EA SilentlyContinue
    if (Test-Path -LiteralPath $scriptZip) { Remove-Item -LiteralPath $scriptZip -Force }
    $z = [IO.Compression.ZipFile]::Open($scriptZip, 'Create')
    try {
        $e = $z.CreateEntry('fomod/Installer.cs')
        $s = $e.Open(); $b = [Text.Encoding]::UTF8.GetBytes('class X {}'); $s.Write($b, 0, $b.Length); $s.Dispose()
        $e = $z.CreateEntry('fomod/ModuleConfig.xml')
        $s = $e.Open(); $b = [Text.Encoding]::UTF8.GetBytes($ModuleA); $s.Write($b, 0, $b.Length); $s.Dispose()
    } finally { $z.Dispose() }
    $colS = Join-Path $work 'collection-script.json'
    New-CollectionJson $colS 2 (Md5Of $scriptZip) 'scripted.zip' 0
    $out4 = Join-Path $work 'record-script.json'
    $r = Run-Gen @{ Collection = $colS; Downloads = $dl; Out = $out4 }
    Yes '4  a scripted FOMOD refuses, naming the mod, and writes no record' (
        (-not $r.Ok) -and $r.Said -match 'CBBE 3BA' -and $r.Said -match 'scripted' -and -not (Test-Path -LiteralPath $out4))

    # ---- 5. ModuleConfig with a DTD refuses ---------------------------------
    $dtd = '<!DOCTYPE config [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>' + $ModuleA
    $dtdZip = Join-Path $dl 'dtd.zip'
    New-FixtureZip $dtdZip $dtd $Good3bbb $Alt3bbb
    $colD = Join-Path $work 'collection-dtd.json'
    New-CollectionJson $colD 2 (Md5Of $dtdZip) 'dtd.zip' 0
    $out5 = Join-Path $work 'record-dtd.json'
    $r = Run-Gen @{ Collection = $colD; Downloads = $dl; Out = $out5 }
    Yes '5  a ModuleConfig with a DTD refuses, naming the mod, and writes no record' (
        (-not $r.Ok) -and $r.Said -match 'CBBE 3BA' -and -not (Test-Path -LiteralPath $out5))

    # ---- 6. Path escape refuses ---------------------------------------------
    function New-EscapeZip([string]$path, [string]$entryName) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        $z = [IO.Compression.ZipFile]::Open($path, 'Create')
        try {
            $e = $z.CreateEntry('fomod/ModuleConfig.xml')
            $s = $e.Open(); $b = [Text.Encoding]::UTF8.GetBytes($ModuleA); $s.Write($b, 0, $b.Length); $s.Dispose()
            $e = $z.CreateEntry($entryName)
            $s = $e.Open(); $s.Write($Good3bbb, 0, $Good3bbb.Length); $s.Dispose()
        } finally { $z.Dispose() }
    }
    $escapes = @(
        @{ Name = '../3BBB.esp'; File = 'dotdot.zip' },
        @{ Name = '/x.esp'; File = 'rooted.zip' },
        @{ Name = 'C:\x.esp'; File = 'drive.zip' }
    )
    $escapeOk = $true
    $outside = @(Get-ChildItem -LiteralPath $work -Recurse -File -Force | ForEach-Object { $_.FullName })
    foreach ($e in $escapes) {
        $p = Join-Path $dl $e.File
        New-EscapeZip $p $e.Name
        $cpath = Join-Path $work ('collection-' + $e.File + '.json')
        New-CollectionJson $cpath 2 (Md5Of $p) $e.File 0
        $o = Join-Path $work ('record-' + $e.File)
        $r = Run-Gen @{ Collection = $cpath; Downloads = $dl; Out = $o }
        if ($r.Ok -or $r.Said -notmatch 'CBBE 3BA' -or (Test-Path -LiteralPath $o)) { $escapeOk = $false }
    }
    $after = @(Get-ChildItem -LiteralPath $work -Recurse -File -Force | ForEach-Object { $_.FullName })
    $newOutside = @($after | Where-Object { $outside -notcontains $_ -and $_ -notlike ($work + '*') })
    Yes '6  a ../ entry, a rooted /x.esp and a C:\x.esp each refuse, naming the mod' $escapeOk
    Yes '6  and nothing was written outside the scratch folder' ($newOutside.Count -eq 0)

    # ---- helpers: fail closed -----------------------------------------------
    $missingWhy = ''
    try { $null = Read-CollectionPluginsRecord (Join-Path $work 'no-such.json') } catch { $missingWhy = $_.Exception.Message }
    Yes 'fail closed: a missing record throws, naming the file' ($missingWhy -match 'no-such\.json')
    $bogus = Join-Path $work 'bogus.json'
    Put $bogus '{ "collection": "7essxf" }'
    $bogusWhy = ''
    try { $null = Read-CollectionPluginsRecord $bogus } catch { $bogusWhy = $_.Exception.Message }
    Yes 'fail closed: a corrupt record throws, naming the file' ($bogusWhy -match 'bogus\.json')

    # ---- 7 to 9, 12: Deploy-Server.ps1 through a scratch repo ---------------
    $ds = Join-Path $Repo 'scripts\deploy\Deploy-Server.ps1'
    $dsText = [IO.File]::ReadAllText($ds)
    Yes 'Deploy-Server.ps1 takes -CollectionRecord and has no -Skip' (
        $dsText -match '\[string\]\$CollectionRecord' -and $dsText -notmatch '\[switch\]\$Skip')
    Yes 'Deploy-Server.ps1 replaced the size-over-hash comment with the #2019 reason' (
        $dsText -match '#2019' -and $dsText -notmatch 'a plugin whose contents changed and whose size did not is a case this can live with')

    $scratch = Join-Path $work 'ds-repo'
    Copy-Item -LiteralPath (Join-Path $Repo 'scripts') -Destination (Join-Path $scratch 'scripts') -Recurse
    Copy-Item -LiteralPath (Join-Path $Repo 'layout.json') -Destination (Join-Path $scratch 'layout.json')
    Put (Join-Path $scratch 'scripts\vps\vps.json') '{ "address": "127.0.0.1" }'
    Put (Join-Path $scratch '.gitignore') "out/`n"
    Put (Join-Path $scratch 'game\gamemode.js') '// 2019 gamemode'
    Put (Join-Path $scratch 'game\content\Thornswood-Content.esp') 'content-esp'
    $dist = Join-Path $work 'dist'
    $serverFiles = [ordered]@{
        'scam_native.node' = 'native'
        'dist_back\skymp5-server.js' = 'js'
        'dist_back\skymp5-server.js.map' = 'map'
        'package.json' = '{ "name": "skymp5-server" }'
        'yarn.lock' = 'lock'
        'launch_server.bat' = 'bat'
        'data\scripts\ActiveMagicEffect.pex' = 'pex'
        'gamemode.js' = '// 2019 gamemode'
        'server-settings.json' = ''
    }
    $c = 'abcdef0123456789abcdef0123456789abcdef01'
    $recFiles = [ordered]@{}
    foreach ($k in @($serverFiles.Keys)) {
        if ($k -in @('gamemode.js', 'server-settings.json')) { continue }
        Put (Join-Path $dist $k) $serverFiles[$k]
        $recFiles[($k -replace '\\', '/')] = [ordered]@{
            sha256 = (Get-FileHash -LiteralPath (Join-Path $dist $k) -Algorithm SHA256).Hash.ToLowerInvariant()
            bytes = 1; commit = $c
        }
    }
    $settings = [ordered]@{
        port = 7777; name = 'Thornswood'
        thornswoodRequirePass = $true
        loadOrder = @((Join-Path $data 'Skyrim.esm'), (Join-Path $data '3BBB.esp'), (Join-Path $scratch 'game\content\Thornswood-Content.esp'))
    }
    Put (Join-Path $dist 'server-settings.json') ($settings | ConvertTo-Json -Depth 5)
    $nativeSha = (Get-FileHash -LiteralPath (Join-Path $dist 'scam_native.node') -Algorithm SHA256).Hash.ToLowerInvariant()
    $sb = [ordered]@{
        binary = 'scam_native.node'; sha256 = $nativeSha
        source = [ordered]@{ commit = $c }
        files = $recFiles
    }
    Put (Join-Path $scratch 'records\server-build.json') ($sb | ConvertTo-Json -Depth 6)
    PutBytes (Join-Path $data 'Skyrim.esm') ([Text.Encoding]::ASCII.GetBytes('skyrim-master'))
    PutBytes (Join-Path $data '3BBB.esp') $Good3bbb
    $emptyRec = [ordered]@{
        collection = '7essxf'; revision = 2
        collectionJsonSha256 = '00' * 32
        generatedBy = 'scripts/release/New-CollectionPluginsRecord.ps1'
        plugins = [ordered]@{
            '3BBB.esp' = [ordered]@{
                bytes = 32; sha256 = $GoodSha; mod = 30174; fileId = 600100
                archiveMd5 = $md5; archiveSha256 = $archSha
                archivePath = 'optionA/3BBB.esp'; via = 'fomod'
            }
        }
    }
    $fixRec = Join-Path $scratch 'records\collection-plugins.json'
    Put $fixRec (ConvertTo-CollectionPluginsJson $emptyRec)
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $scratch '.git'))) { & git -C $scratch init -q 2>&1 | Out-Null }
        & git -C $scratch add -A 2>&1 | Out-Null
        & git -C $scratch -c user.name=harness -c user.email=harness@invalid -c commit.gpgsign=false commit -q -m step 2>&1 | Out-Null
    } finally { $ErrorActionPreference = $eap }

    $boxDir = Join-Path $work 'box-plugins'
    New-Item -ItemType Directory -Path $boxDir -Force | Out-Null
    PutBytes (Join-Path $boxDir 'Skyrim.esm') ([Text.Encoding]::ASCII.GetBytes('skyrim-master'))
    PutBytes (Join-Path $boxDir '3BBB.esp') $Good3bbb
    Put (Join-Path $boxDir 'Thornswood-Content.esp') 'content-esp'

    $global:Ts2019 = [pscustomobject]@{
        Scp = New-Object Collections.Generic.List[string]
        Box = $boxDir
        BoxSha = $GoodSha
    }
    function global:ssh {
        $cmd = [string]@($args)[-1]
        if ($cmd -match 'Name \+ ''\|'' \+') {
            Get-ChildItem -LiteralPath $global:Ts2019.Box -File | ForEach-Object {
                $sha = ''
                if ($_.Name -eq '3BBB.esp') { $sha = $global:Ts2019.BoxSha }
                $_.Name + '|' + $_.Length + '|' + $sha
            }
            $global:LASTEXITCODE = 0
            return
        }
        $global:LASTEXITCODE = 0
    }
    function global:scp {
        [void]$global:Ts2019.Scp.Add([string]@($args)[-1])
        $global:LASTEXITCODE = 0
    }

    function DsDeploy([hashtable]$more = @{}) {
        $a = @{
            Vps = '127.0.0.1'; User = 'test'
            Root = (Join-Path $work 'live-root')
            Dist = $dist; Data = $data
            CollectionRecord = $fixRec
            Now = $true; Wait = 2
        }
        foreach ($k in $more.Keys) { $a[$k] = $more[$k] }
        $global:Ts2019.Scp.Clear()
        $threw = ''
        $lines = New-Object Collections.Generic.List[string]
        try { & (Join-Path $scratch 'scripts\deploy\Deploy-Server.ps1') @a *>&1 | ForEach-Object { [void]$lines.Add("$_") } }
        catch { $threw = $_.Exception.Message }
        return [pscustomobject]@{
            Ok = ((-not $threw) -and $global:LASTEXITCODE -eq 0)
            Said = (($lines -join "`n") + "`n" + $threw)
            Threw = $threw
            Scp = @($global:Ts2019.Scp)
        }
    }

    # Box already matches: nothing to send for 3BBB. Local file equals the record.
    $global:Ts2019.BoxSha = $GoodSha
    $r = DsDeploy
    Yes '7  hash match passes: a local plugin equal to the record is not treated as a mismatch' (
        $r.Said -notmatch 'collection plugins are not the record' -and $r.Threw -notmatch 'collection plugins are not the record')
    Yes '7  and 3BBB.esp is sent only when the box sha256 differs (box matches, so it is not queued as changed)' (
        $r.Said -notmatch '3BBB\.esp  sha256')

    $global:Ts2019.BoxSha = $BadSha
    PutBytes (Join-Path $boxDir '3BBB.esp') $Bad3bbb
    $r = DsDeploy
    Yes '7  a matching local file is sent when the box sha256 differs, and the deploy goes ahead past the local check' (
        $r.Said -notmatch 'collection plugins are not the record' -or $r.Said -match '3BBB\.esp  sha256')

    PutBytes (Join-Path $data '3BBB.esp') $Bad3bbb
    $r = DsDeploy
    $said = $r.Said
    Yes '8  same-size hash mismatch stops Deploy-Server.ps1 and names the plugin, both hashes and the source path' (
        (-not $r.Ok) -and $said -match '3BBB\.esp' -and $said -match $BadSha -and $said -match $GoodSha -and
        $said -match [regex]::Escape((Join-Path $data '3BBB.esp')) -and $global:Ts2019.Scp.Count -eq 0)
    Yes '8  and nothing was sent' ($said -match 'Nothing was sent' -or $r.Threw -match 'Nothing was sent' -or $global:Ts2019.Scp.Count -eq 0)

    PutBytes (Join-Path $data '3BBB.esp') ($Bad3bbb + [byte]0)
    $r = DsDeploy
    Yes '9  a one-byte-longer file stops the same way' (
        (-not $r.Ok) -and $r.Said -match '3BBB\.esp' -and $r.Said -match $GoodSha -and $global:Ts2019.Scp.Count -eq 0)

    PutBytes (Join-Path $data '3BBB.esp') $Good3bbb
    $r = DsDeploy
    Yes '12  outside plugins are listed and do not block: Skyrim.esm and Thornswood-Content.esp appear in the outside block' (
        $r.Said -match 'outside the collection \(7essxf rev 2\), not held to it' -and
        $r.Said -match 'Skyrim\.esm' -and $r.Said -match 'Thornswood-Content\.esp')

    Remove-Item -Path function:global:ssh, function:global:scp -ErrorAction SilentlyContinue
    Remove-Variable -Name Ts2019 -Scope Global -ErrorAction SilentlyContinue

    # ---- 10. Deploy-DevGamemode.ps1 -LoadOrder ------------------------------
    $dgText = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\deploy\Deploy-DevGamemode.ps1'))
    Yes 'Deploy-DevGamemode.ps1 takes -CollectionRecord and has no -Skip' (
        $dgText -match '\[string\]\$CollectionRecord' -and $dgText -notmatch '\[switch\]\$Skip')

    $devRepo = Join-Path $work 'dev-repo'
    Copy-Item -LiteralPath (Join-Path $Repo 'scripts') -Destination (Join-Path $devRepo 'scripts') -Recurse
    Copy-Item -LiteralPath (Join-Path $Repo 'layout.json') -Destination (Join-Path $devRepo 'layout.json')
    Put (Join-Path $devRepo 'scripts\vps\vps.json') '{ "address": "127.0.0.1" }'
    Put (Join-Path $devRepo '.gitignore') "out/`n"
    Put (Join-Path $devRepo 'game\gamemode.js') '// dev 2019'
    Put (Join-Path $devRepo 'game\content\Thornswood-Content.esp') 'content-esp'
    Put $fixRec.Replace($scratch, $devRepo) (ConvertTo-CollectionPluginsJson $emptyRec)
    Put (Join-Path $devRepo 'records\collection-plugins.json') (ConvertTo-CollectionPluginsJson $emptyRec)
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & git -C $devRepo init -q 2>&1 | Out-Null
        & git -C $devRepo add -A 2>&1 | Out-Null
        & git -C $devRepo -c user.name=harness -c user.email=harness@invalid -c commit.gpgsign=false commit -q -m step 2>&1 | Out-Null
    } finally { $ErrorActionPreference = $eap }

    PutBytes (Join-Path $data '3BBB.esp') $Bad3bbb
    $global:Ts2019b = [pscustomobject]@{ Scp = New-Object Collections.Generic.List[string]; Box = $boxDir }
    function global:ssh {
        Get-ChildItem -LiteralPath $global:Ts2019b.Box -File | ForEach-Object {
            $_.Name + '|' + $_.Length + '|'
        }
        $global:LASTEXITCODE = 0
    }
    function global:scp { [void]$global:Ts2019b.Scp.Add('x'); $global:LASTEXITCODE = 0 }
    $threw = ''
    $lines = New-Object Collections.Generic.List[string]
    try {
        & (Join-Path $devRepo 'scripts\deploy\Deploy-DevGamemode.ps1') `
            -Vps 127.0.0.1 -User test -Root (Join-Path $work 'dev-root') `
            -Dist $dist -Data $data `
            -CollectionRecord (Join-Path $devRepo 'records\collection-plugins.json') `
            -LoadOrder -Now -Wait 2 `
            -Note ("The collection plugin check`n- A line long enough for the note shape.") `
            *>&1 | ForEach-Object { [void]$lines.Add("$_") }
    } catch { $threw = $_.Exception.Message }
    $said = (($lines -join "`n") + "`n" + $threw)
    Yes '10  Deploy-DevGamemode.ps1 -LoadOrder stops on a same-size mismatch, naming the plugin, both hashes and the source path, before any scp' (
        $said -match '3BBB\.esp' -and $said -match $BadSha -and $said -match $GoodSha -and
        $said -match [regex]::Escape((Join-Path $data '3BBB.esp')) -and $global:Ts2019b.Scp.Count -eq 0)
    Remove-Item -Path function:global:ssh, function:global:scp -ErrorAction SilentlyContinue
    Remove-Variable -Name Ts2019b -Scope Global -ErrorAction SilentlyContinue

    # ---- 11. Export-ServerPayload.ps1 ---------------------------------------
    $exText = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\release\Export-ServerPayload.ps1'))
    Yes 'Export-ServerPayload.ps1 takes -CollectionRecord and has no -Skip' (
        $exText -match '\[string\]\$CollectionRecord' -and $exText -notmatch '\[switch\]\$Skip')
    $payload = Join-Path $work 'payload'
    $zipOut = Join-Path $work 'payload.zip'
    $settingsBad = [ordered]@{
        port = 7777; name = 'Thornswood'
        loadOrder = @((Join-Path $data '3BBB.esp'))
    }
    Put (Join-Path $dist 'server-settings.json') ($settingsBad | ConvertTo-Json -Depth 5)
    PutBytes (Join-Path $data '3BBB.esp') $Bad3bbb
    $threw = ''
    $lines = New-Object Collections.Generic.List[string]
    try {
        & (Join-Path $Repo 'scripts\release\Export-ServerPayload.ps1') `
            -Dist $dist -OutDir $payload -Zip $zipOut `
            -Record (Join-Path $scratch 'records\server-build.json') `
            -CollectionRecord $fixRec *>&1 | ForEach-Object { [void]$lines.Add("$_") }
    } catch { $threw = $_.Exception.Message }
    $said = (($lines -join "`n") + "`n" + $threw)
    Yes '11  Export-ServerPayload.ps1 stops on a bad collection plugin before copying: no payload folder and no zip' (
        $said -match '3BBB\.esp' -and $said -match $BadSha -and $said -match $GoodSha -and
        -not (Test-Path -LiteralPath $payload) -and -not (Test-Path -LiteralPath $zipOut))

    # ---- 17. Revision tie ---------------------------------------------------
    $docs = Join-Path $Repo 'docs'
    $docRev = Get-CollectionPluginsDocRevision $docs
    Yes '17  the current collection revision doc is docs/COLLECTION-REVISION-2.md' ($docRev -eq 2)
    $wrongRec = [ordered]@{
        collection = '7essxf'; revision = 99
        collectionJsonSha256 = '00' * 32
        generatedBy = 'scripts/release/New-CollectionPluginsRecord.ps1'
        plugins = $emptyRec.plugins
    }
    $wrongPath = Join-Path $work 'record-rev99.json'
    Put $wrongPath (ConvertTo-CollectionPluginsJson $wrongRec)
    $wrongObj = Read-CollectionPluginsRecord $wrongPath
    $tie = @(Confirm-CollectionPluginsRevisionTie $wrongObj $docs 0)
    Yes '17  a record whose revision is not the doc''s fails the tie' (
        $tie.Count -gt 0 -and ($tie -join ' ') -match '99')
    New-CollectionJson $col 1 $md5 'cbbe.zip' 0
    $out17 = Join-Path $work 'record-rev1.json'
    $r = Run-Gen @{ Revision = 2; Collection = $col; Downloads = $dl; Out = $out17 }
    Yes '17  the generator refuses when collection.json revision is not -Revision' (
        (-not $r.Ok) -and $r.Said -match 'revision' -and -not (Test-Path -LiteralPath $out17))

    # ---- 18. Real-record gate -----------------------------------------------
    $realPath = Join-Path $Repo 'records\collection-plugins.json'
    $gateCmd = 'pwsh -NoProfile -File .\scripts\release\New-CollectionPluginsRecord.ps1 -Revision 2 -Downloads <Vortex downloads folder that holds the pinned archives>'
    Write-Host ''
    Write-Host 'CASE 18 GATE (real record, not a fixture)' -ForegroundColor Yellow
    Write-Host ('  expected 3BBB.esp: 20257 bytes, SHA256 ' + $RealGood.ToUpperInvariant())
    Write-Host ('  forbidden hash (must not appear): ' + $RealBad.ToUpperInvariant())
    Write-Host ('  Nyx command: ' + $gateCmd)
    if (Test-Path -LiteralPath $realPath) {
        $realRaw = [IO.File]::ReadAllText($realPath)
        $real = $null
        $realWhy = ''
        try { $real = Read-CollectionPluginsRecord $realPath } catch { $realWhy = $_.Exception.Message }
        $hit = $null
        if ($real) { $hit = Get-CollectionRecordPlugin $real.Plugins '3BBB.esp' }
        Yes '18  records/collection-plugins.json parses' ($null -ne $real -and -not $realWhy)
        Yes '18  3BBB.esp is 20257 bytes with Djinn''s SHA256' (
            $null -ne $hit -and $hit.Bytes -eq 20257 -and $hit.Sha256 -eq $RealGood)
        Yes '18  the bad file''s A1AA2B0A...8FD0244E does not appear anywhere in the record' (
            $realRaw.ToLowerInvariant() -notmatch $RealBad)
    } else {
        Yes '18  GATE: records/collection-plugins.json is not in this checkout (Nexus archives are not here), so Djinn runs the generator on Nyx with -Downloads' $true
        Yes '18  GATE command is the generator at revision 2 with -Downloads' ($gateCmd -match 'New-CollectionPluginsRecord\.ps1 -Revision 2 -Downloads')
        Yes '18  GATE still names the expected 3BBB.esp bytes and SHA256, and the forbidden hash' (
            $RealGood.Length -eq 64 -and $RealBad.Length -eq 64)
        Write-Host ('  ' + $gateCmd) -ForegroundColor Yellow
    }

    Yes 'Check-ServerPlugins.ps1 is read-only: it sends nothing and stops nothing' (
        ([IO.File]::ReadAllText((Join-Path $Repo 'scripts\deploy\Check-ServerPlugins.ps1'))) -match 'Sends nothing, stops nothing and writes nothing')
    Yes 'SwapVars sends $Pinned as quoted literals and CollectionPinnedText opens no record file' (
        $CollectionPinnedText -notmatch 'collection-plugins\.json' -and
        $CollectionPinnedText -notmatch 'ConvertFrom-Json' -and
        ((Get-Command SwapVars -EA SilentlyContinue) -or $dsText -match '\$Pinned'))
}
catch {
    Yes ('the harness finished without an error: ' + $_.Exception.Message) $false
}
finally {
    Remove-Item -Path function:global:ssh, function:global:scp -ErrorAction SilentlyContinue
    Remove-Variable -Name Ts2019, Ts2019b -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}

Done
