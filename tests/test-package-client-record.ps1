<#
  test-package-client-record.ps1

      pwsh -NoProfile -File .\tests\test-package-client-record.ps1

  Issue #1243. Package-Thornswood.ps1 used to pin the six client runtime
  files to records\client-build.json in the checkout. The launcher it packs
  carries its own embedded record, and between main Ships the two disagree.

  This builds a launcher with one record embedded and a checkout record with
  another, and drives Package's own listing. The client that matches the
  packed launcher is kept. The client that matches the checkout, and a
  launcher client with one byte changed, are refused. With no launcher, the
  same listing is held to a client-runtime zip named by the main feed's
  clientRuntime.

  Writes only to a temp folder of its own, and removes it. It does not run
  Package-Thornswood.ps1.
#>
param([string]$Repo)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Repo) {
    $Repo = $PSScriptRoot
    if (-not $Repo) { $Repo = Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $Repo = Split-Path -Parent $Repo
}

$pass = 0; $fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" -ForegroundColor Green }
    else       { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Say($m, $c = 'Gray') { }
function Die($m) { throw ('DIE ' + $m) }

$names = @(
    'Data\SKSE\Plugins\MpClientPlugin.dll',
    'Data\SKSE\Plugins\SkyrimPlatform.dll',
    'Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformImpl.dll',
    'Data\Platform\Distribution\RuntimeDependencies\SkyrimPlatformCEF.exe.hidden',
    'Data\Platform\Plugins\skymp5-client.js',
    'Data\Scripts\TESModPlatform.pex'
)
$bundle = 'Data\Platform\Plugins\skymp5-client.js'

$pkgPath = Join-Path $Repo 'scripts\release\Package-Thornswood.ps1'
$helperPath = Join-Path $Repo 'scripts\release\Package-ClientRecord.ps1'
$rulesPath = Join-Path $Repo 'scripts\release\Ship-Rules.ps1'

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-1243-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))

function New-ClientTree([string]$dir, [string]$body) {
    $files = [ordered]@{}
    foreach ($n in $script:names) {
        $full = Join-Path $dir $n
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $full -Parent)
        [IO.File]::WriteAllText($full, ($body + ' ' + $n))
        $item = Get-Item -LiteralPath $full
        $files[$n] = [ordered]@{ sha256 = (Get-ClientFileSha256 $full); bytes = [int64]$item.Length }
    }
    return $files
}

function New-RecordText($files, [string]$commit) {
    $rec = [ordered]@{
        fork         = 'https://github.com/EvilPatrick06/skymp'
        forkBranch   = 'thornswood/engine-changes'
        forkCommit   = $commit
        upstreamBase = 'f926944b'
        files        = $files
    }
    return ($rec | ConvertTo-Json -Depth 6)
}

function Write-Utf8([string]$path, [string]$text) {
    $parent = Split-Path -Parent $path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Force -Path $parent
    }
    [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

function New-RuntimeZip([string]$zip, [string]$tree) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    $fs = New-Object IO.FileStream($zip, [IO.FileMode]::CreateNew)
    try {
        $archive = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($n in $script:names) {
                $entry = $archive.CreateEntry(($n -replace '\\', '/'), [IO.Compression.CompressionLevel]::NoCompression)
                $opened = $entry.Open()
                try {
                    $bytes = [IO.File]::ReadAllBytes((Join-Path $tree $n))
                    $opened.Write($bytes, 0, $bytes.Length)
                } finally { $opened.Dispose() }
            }
        } finally { $archive.Dispose() }
    } finally { $fs.Dispose() }
}

try {
    $null = New-Item -ItemType Directory -Force -Path $scratch
    . $helperPath
    . $rulesPath

    $pkgText = [IO.File]::ReadAllText($pkgPath)
    $tok = $null; $err = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($pkgPath, [ref]$tok, [ref]$err)
    Yes 'Package-Thornswood.ps1 parses' (@($err).Count -eq 0)
    Yes 'Package resolves the record from the launcher it packs and the main feed' ($pkgText.Contains('Resolve-PackageClientRecord -LauncherExe (Get-LauncherExe $LaunchDir) -FeedVersion $vLive -CheckoutRecord $checkoutClientRecord'))
    Yes 'Package applies that record over the hashes Ship-Rules loaded' ($pkgText.Contains('Apply-PackageClientRecord $resolvedClient.Record'))
    Yes 'Package no longer pins clientRecordPath at the checkout record' (-not $pkgText.Contains("`$clientRecordPath = Join-Path `$PSScriptRoot '..\..\records\client-build.json'"))
    Yes 'a record that is neither the launcher nor the feed stops the package' ($pkgText.Contains('Neither could be read'))

    $launcherTree = Join-Path $scratch 'launcher-client'
    $feedTree = Join-Path $scratch 'feed-client'
    $checkoutTree = Join-Path $scratch 'checkout-client'
    $launcherFiles = New-ClientTree $launcherTree 'packed-launcher-client'
    $feedFiles = New-ClientTree $feedTree 'main-feed-client'
    $checkoutFiles = New-ClientTree $checkoutTree 'checkout-client'
    $launcherJson = New-RecordText $launcherFiles 'aaaa1111'
    $feedFork = 'bbbb2222'
    $checkoutJson = New-RecordText $checkoutFiles 'cccc3333'
    $launcherRecordPath = Join-Path $scratch 'launcher-client-build.json'
    $checkoutPath = Join-Path $scratch 'checkout-client-build.json'
    Write-Utf8 $launcherRecordPath $launcherJson
    Write-Utf8 $checkoutPath $checkoutJson

    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
    Yes 'the .NET Framework csc is here' (Test-Path -LiteralPath $csc)
    $cs = Join-Path $scratch 'Program.cs'
    Write-Utf8 $cs "class Program { static void Main() {} }`r`n"
    $exe = Join-Path $scratch 'Thornswood.exe'
    & $csc /nologo /target:exe "/resource:$launcherRecordPath,client-build.json" "/out:$exe" $cs | Out-Null
    Yes 'a launcher with client-build.json embedded compiled' ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $exe))

    $feedDir = Join-Path $scratch 'feed'
    $null = New-Item -ItemType Directory -Force -Path $feedDir
    $zip = Join-Path $feedDir ("client-runtime-" + $feedFork + ".zip")
    New-RuntimeZip $zip $feedTree
    $zipSha = Get-ClientFileSha256 $zip
    $versionPath = Join-Path $feedDir 'version.json'
    $version = [ordered]@{
        clientRuntime = [ordered]@{
            url        = ('https://thornswood.net/feed/assets/' + $zipSha)
            sha256     = $zipSha
            bytes      = [int64](Get-Item -LiteralPath $zip).Length
            forkCommit = $feedFork
        }
    }
    Write-Utf8 $versionPath ($version | ConvertTo-Json -Depth 6)

    $resolved = Resolve-PackageClientRecord -LauncherExe $exe -FeedVersion $versionPath -CheckoutRecord $checkoutPath
    Yes 'the packed launcher is the record, even when the feed and the checkout disagree' ($null -ne $resolved -and $resolved.Source -eq 'launcher' -and [string]$resolved.Record.forkCommit -eq 'aaaa1111')
    $launcherBundle = Join-Path $launcherTree $bundle
    $checkoutBundle = Join-Path $checkoutTree $bundle
    $feedBundle = Join-Path $feedTree $bundle
    Yes 'a file matching the packed launcher is accepted' ((Test-ClientRecordMatch $resolved.Record $bundle $launcherBundle) -eq $true)
    Yes 'a file matching the checkout record is refused' ((Test-ClientRecordMatch $resolved.Record $bundle $checkoutBundle) -eq $false)
    Yes 'a file matching the feed zip is refused while the launcher carries its own record' ((Test-ClientRecordMatch $resolved.Record $bundle $feedBundle) -eq $false)

    Apply-PackageClientRecord $resolved.Record
    Yes 'Ship-Rules now answers the packed launcher, not the checkout' ((Test-ShipClientRecorded $bundle $launcherBundle) -eq $true -and (Test-ShipClientRecorded $bundle $checkoutBundle) -eq $false)

    $loops = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.ForEachStatementAst] -and
        $n.Body.Extent.Text -match 'Test-Vanilla \$rel' }, $true))
    $stops = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.IfStatementAst] -and
        $n.Clauses[0].Item1.Extent.Text -eq '$clientWrong.Count' }, $true))
    Yes 'Package still has one listing loop' ($loops.Count -eq 1)
    Yes 'and one refusal for a client that is not the recorded build' ($stops.Count -eq 1)
    if ($loops.Count -eq 1 -and $stops.Count -eq 1) {
        foreach ($fn in 'Test-Vanilla', 'Test-Runtime', 'Test-Optional', 'Test-FromCollection') {
            $def = @($ast.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $fn }, $true))
            . ([scriptblock]::Create($def[0].Extent.Text))
        }
        $optionalPrefixes = @()
        $vortexFiles = $null
        $Root = $scratch
        $stopText = $stops[0].Extent.Text
        $src = (@(
            'function Invoke-Listing($all, $prefix) {',
            '    $ship = @(); $skipBytes = 0; $shipBytes = 0; $optionalBytes = 0; $optionalCount = 0; $machineCount = 0',
            '    $collectionBytes = 0; $collectionCount = 0',
            '    $notOursBytes = 0; $notOursCount = 0',
            '    $clientShipped = 0',
            '    $clientWrong = @()',
            '    foreach ($f in $all)'
        ) -join "`n") + "`n" + $loops[0].Body.Extent.Text + "`n" + (@(
            '    $stopped = ""',
            '    try {'
        ) -join "`n") + "`n" + $stopText + "`n" + (@(
            '    } catch { $stopped = $_.Exception.Message }',
            '    return [pscustomobject]@{ Ship = [string[]]@($ship | ForEach-Object { $_.Rel }); Wrong = [string[]]@($clientWrong); Stopped = $stopped }',
            '}'
        ) -join "`n")
        . ([scriptblock]::Create($src))

        function Invoke-Tree([string]$dir) {
            $script:GameDir = $dir
            $prefix = $dir.TrimEnd('\') + '\'
            return Invoke-Listing @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force) $prefix
        }

        $r = Invoke-Tree $launcherTree
        Yes 'Package keeps every file of the client the packed launcher was built with' (@($names | Where-Object { $r.Ship -contains $_ }).Count -eq $names.Count)
        Yes 'and does not refuse that client' ($r.Wrong.Count -eq 0 -and $r.Stopped -eq '')

        $r = Invoke-Tree $checkoutTree
        Yes 'Package refuses the checkout client when it is not the packed launcher record' ($r.Ship.Count -eq 0 -and @($names | Where-Object { $r.Wrong -contains $_ }).Count -eq $names.Count)
        Yes 'and the build stops' ($r.Stopped -like 'DIE *not the recorded build*')

        $changed = Join-Path $scratch 'one-byte'
        $null = New-Item -ItemType Directory -Force -Path $changed
        foreach ($n in $names) {
            $dest = Join-Path $changed $n
            $null = New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent)
            Copy-Item -LiteralPath (Join-Path $launcherTree $n) -Destination $dest
        }
        $changedBundle = Join-Path $changed $bundle
        $bytes = [IO.File]::ReadAllBytes($changedBundle)
        $bytes[0] = [byte]($bytes[0] -bxor 1)
        [IO.File]::WriteAllBytes($changedBundle, $bytes)
        Yes 'one byte changed is not the packed launcher record' ((Test-ClientRecordMatch $resolved.Record $bundle $changedBundle) -eq $false)
        $r = Invoke-Tree $changed
        Yes 'Package names that one file and stops' ($r.Wrong.Count -eq 1 -and $r.Wrong[0] -eq $bundle -and $r.Stopped -like 'DIE *not the recorded build*')
        Yes 'and still keeps the other five' (@($names | Where-Object { $_ -ne $bundle -and $r.Ship -contains $_ }).Count -eq ($names.Count - 1))
    }

    $fromFeed = Resolve-PackageClientRecord -LauncherExe '' -FeedVersion $versionPath -CheckoutRecord $checkoutPath
    Yes 'with no launcher, the record is the main feed clientRuntime' ($null -ne $fromFeed -and $fromFeed.Source -eq 'feed' -and [string]$fromFeed.Record.forkCommit -eq $feedFork)
    Yes 'the feed client is accepted' ((Test-ClientRecordMatch $fromFeed.Record $bundle $feedBundle) -eq $true)
    Yes 'the checkout client is refused against the feed' ((Test-ClientRecordMatch $fromFeed.Record $bundle $checkoutBundle) -eq $false)
    Apply-PackageClientRecord $fromFeed.Record
    if (Get-Command Invoke-Tree -ErrorAction SilentlyContinue) {
        $r = Invoke-Tree $feedTree
        Yes 'Package keeps the client the main feed published' (@($names | Where-Object { $r.Ship -contains $_ }).Count -eq $names.Count -and $r.Stopped -eq '')
        $r = Invoke-Tree $launcherTree
        Yes 'Package refuses the launcher client when the record came from the feed and they differ' ($r.Stopped -like 'DIE *not the recorded build*' -and $r.Wrong -contains $bundle)
    }

    $badVersion = Join-Path $scratch 'bad-feed\version.json'
    $bad = [ordered]@{
        clientRuntime = [ordered]@{
            url = 'https://thornswood.net/feed/assets/0000000000000000000000000000000000000000000000000000000000000000'
            sha256 = '0000000000000000000000000000000000000000000000000000000000000000'
            bytes = 1
            forkCommit = 'dddd4444'
        }
    }
    Write-Utf8 $badVersion ($bad | ConvertTo-Json -Depth 6)
    Copy-Item -LiteralPath $zip -Destination (Join-Path (Split-Path $badVersion -Parent) 'client-runtime-dddd4444.zip')
    $none = Resolve-PackageClientRecord -LauncherExe (Join-Path $scratch 'missing.exe') -FeedVersion $badVersion -CheckoutRecord $checkoutPath
    Yes 'a feed zip whose sha256 is not clientRuntime is not the record, and neither is a drifted checkout' ($null -eq $none)

    $sameCommit = 'cccc3333'
    $sameVersion = Join-Path $scratch 'same-feed\version.json'
    $same = [ordered]@{
        clientRuntime = [ordered]@{
            url = 'https://thornswood.net/feed/assets/1111111111111111111111111111111111111111111111111111111111111111'
            sha256 = '1111111111111111111111111111111111111111111111111111111111111111'
            bytes = 1
            forkCommit = $sameCommit
        }
    }
    Write-Utf8 $sameVersion ($same | ConvertTo-Json -Depth 6)
    $sameRec = Resolve-PackageClientRecord -LauncherExe '' -FeedVersion $sameVersion -CheckoutRecord $checkoutPath
    Yes 'with no launcher and no zip, a checkout record whose fork commit is still the feed is that client' ($null -ne $sameRec -and $sameRec.Source -eq 'feed' -and [string]$sameRec.Record.forkCommit -eq $sameCommit)
    Yes 'and its bytes are the checkout, which the feed still names' ((Test-ClientRecordMatch $sameRec.Record $bundle $checkoutBundle) -eq $true)
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $pass, $fail)
if ($fail) { exit 1 }
exit 0
