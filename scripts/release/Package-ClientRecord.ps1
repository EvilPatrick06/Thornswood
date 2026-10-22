<#
  Package-ClientRecord.ps1

  The client runtime an installer is held to. Issue #1243.

  records\client-build.json in the checkout moves ahead of main between Ships.
  The launcher an installer packs was built with its own copy, embedded as
  client-build.json, and that is the client it checks and puts back. The main
  feed's clientRuntime is that same client when the packed launcher is the one
  main shipped. Package-Thornswood.ps1 asks this file, not the checkout.

      Resolve-PackageClientRecord -LauncherExe <exe> -FeedVersion <version.json> -CheckoutRecord <client-build.json>
      Apply-PackageClientRecord $resolved.Record
      Test-ClientRecordMatch $resolved.Record $rel $full
#>

function Get-Prop($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-ClientFileSha256([string]$Full) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        # ReadWrite, the way ClientRuntime.Sha256Of and Test-ShipClientRecorded
        # open it: SkyrimPlatform holds these open while the game runs.
        $fs = New-Object IO.FileStream($Full, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { return ([BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-', '').ToLowerInvariant() }
        finally { $fs.Dispose() }
    }
    finally { $sha.Dispose() }
}

function Read-JsonFile([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $text = [IO.File]::ReadAllText($Path).TrimStart([char]0xFEFF)
    if (-not $text) { return $null }
    return [pscustomobject]@{ Text = $text; Doc = ($text | ConvertFrom-Json) }
}

# The client-build.json Build-Launcher.ps1 embedded. $null when there is no
# exe, or it was built without the resource. An exe that will not load, or a
# record in it that does not read, stops it (#2711): the catch below used to
# hand back $null for those too, and Resolve-PackageClientRecord then took the
# feed's client or the checkout's for the launcher it packs.
function Read-LauncherClientRecord([string]$Exe) {
    if (-not $Exe -or -not (Test-Path -LiteralPath $Exe)) { return $null }
    try {
        $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($Exe))
        $name = @($asm.GetManifestResourceNames()) | Where-Object {
            $_ -eq 'client-build.json' -or
            $_.EndsWith('.client-build.json') -or
            $_.EndsWith('\client-build.json') -or
            $_.EndsWith('/client-build.json')
        } | Select-Object -First 1
        if (-not $name) { return $null }
        $sr = New-Object IO.StreamReader($asm.GetManifestResourceStream($name))
        try { $text = $sr.ReadToEnd() } finally { $sr.Dispose() }
        if (-not $text) { return $null }
        $text = $text.TrimStart([char]0xFEFF)
        $doc = $text | ConvertFrom-Json
        $files = Get-Prop $doc 'files'
        if ($null -eq $files -or @($files.PSObject.Properties).Count -lt 1) { return $null }
        return [pscustomobject]@{ Doc = $doc; Text = $text }
    }
    catch { throw ("the launcher at $Exe cannot be read for the client-build.json it was built with, so the client it puts back is not known: " + $_.Exception.Message) }
}

function Read-FeedClientRuntime([string]$VersionJson) {
    $parsed = Read-JsonFile $VersionJson
    if ($null -eq $parsed) { return $null }
    $rt = Get-Prop $parsed.Doc 'clientRuntime'
    if ($null -eq $rt) { return $null }
    if (-not (Get-Prop $rt 'forkCommit') -and -not (Get-Prop $rt 'sha256') -and -not (Get-Prop $rt 'url')) { return $null }
    return $rt
}

# A client-runtime zip already sitting beside the feed, named the way
# Publish-Update names it or stored by the feed's sha256. Nothing is downloaded.
function Find-FeedRuntimeZip([string]$VersionJson, $runtime) {
    if (-not $VersionJson) { return '' }
    $dir = Split-Path -Parent $VersionJson
    $fork = [string](Get-Prop $runtime 'forkCommit')
    $sha = ([string](Get-Prop $runtime 'sha256')).ToLowerInvariant()
    $cands = @()
    if ($fork) { $cands += (Join-Path $dir ("client-runtime-" + $fork + ".zip")) }
    $cands += (Join-Path $dir 'client-runtime.zip')
    if ($sha) {
        $cands += (Join-Path (Join-Path $dir 'assets') $sha)
        $cands += (Join-Path (Join-Path $dir 'assets') ($sha + '.zip'))
    }
    foreach ($c in $cands) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return ''
}

function Test-RuntimeZipSha([string]$Zip, $runtime) {
    $want = ([string](Get-Prop $runtime 'sha256')).ToLowerInvariant()
    if (-not $want -or $want.Length -ne 64) { return $false }
    if (-not (Test-Path -LiteralPath $Zip)) { return $false }
    return ((Get-ClientFileSha256 $Zip) -eq $want)
}

# The six files in the zip, hashed, under the paths the checkout record names.
# The fork commit is the feed's, not the checkout's. $null when the zip is not
# the feed's sha256 or does not hold every recorded path.
function Get-ClientRecordFromRuntimeZip([string]$Zip, $runtime, $checkoutDoc) {
    if (-not (Test-RuntimeZipSha $Zip $runtime)) { return $null }
    $checkoutFiles = Get-Prop $checkoutDoc 'files'
    if ($null -eq $checkoutFiles) { return $null }
    $names = @($checkoutFiles.PSObject.Properties.Name)
    if ($names.Count -lt 1) { return $null }
    [void](Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue)
    $fs = New-Object IO.FileStream($Zip, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $archive = New-Object IO.Compression.ZipArchive($fs, [IO.Compression.ZipArchiveMode]::Read)
        try {
            $byName = @{}
            foreach ($entry in $archive.Entries) {
                $rel = ($entry.FullName -replace '/', '\').TrimStart('\')
                if ($rel) { $byName[$rel] = $entry }
            }
            $files = [ordered]@{}
            foreach ($n in $names) {
                if (-not $byName.ContainsKey($n)) { return $null }
                $opened = $byName[$n].Open()
                try {
                    $ms = New-Object IO.MemoryStream
                    try { $opened.CopyTo($ms); $bytes = $ms.ToArray() }
                    finally { $ms.Dispose() }
                }
                finally { $opened.Dispose() }
                $files[$n] = [pscustomobject]@{ sha256 = (Get-BytesSha256 $bytes); bytes = [int64]$bytes.Length }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $fs.Dispose() }
    return [pscustomobject]@{
        fork          = [string](Get-Prop $checkoutDoc 'fork')
        forkBranch    = [string](Get-Prop $checkoutDoc 'forkBranch')
        forkCommit    = [string](Get-Prop $runtime 'forkCommit')
        upstreamBase  = [string](Get-Prop $checkoutDoc 'upstreamBase')
        files         = [pscustomobject]$files
    }
}

# One record. The launcher the installer packs, when it carries one. Otherwise
# the main feed's clientRuntime: the zip beside that feed, or the checkout
# record when its fork commit is still the one the feed names. Never the
# checkout record on its own once that commit has moved.
function Resolve-PackageClientRecord {
    param(
        [string]$LauncherExe,
        [string]$FeedVersion,
        [string]$CheckoutRecord,
        [string]$RuntimeZip = ''
    )
    $runtime = Read-FeedClientRuntime $FeedVersion
    $feedFork = ''
    if ($null -ne $runtime) { $feedFork = [string](Get-Prop $runtime 'forkCommit') }
    $checkout = Read-JsonFile $CheckoutRecord

    $fromExe = Read-LauncherClientRecord $LauncherExe
    if ($null -ne $fromExe) {
        return [pscustomobject]@{
            Source   = 'launcher'
            Record   = $fromExe.Doc
            Json     = $fromExe.Text
            FeedFork = $feedFork
        }
    }

    $zipPath = $RuntimeZip
    if (-not $zipPath -and $null -ne $runtime) { $zipPath = Find-FeedRuntimeZip $FeedVersion $runtime }
    if ($zipPath -and $null -ne $runtime -and $null -ne $checkout) {
        $built = Get-ClientRecordFromRuntimeZip $zipPath $runtime $checkout.Doc
        if ($null -ne $built) {
            return [pscustomobject]@{
                Source   = 'feed'
                Record   = $built
                Json     = $null
                FeedFork = $feedFork
            }
        }
    }

    if ($null -ne $checkout -and $feedFork -and ([string](Get-Prop $checkout.Doc 'forkCommit') -eq $feedFork)) {
        $files = Get-Prop $checkout.Doc 'files'
        if ($null -ne $files -and @($files.PSObject.Properties).Count -gt 0) {
            return [pscustomobject]@{
                Source   = 'feed'
                Record   = $checkout.Doc
                Json     = $checkout.Text
                FeedFork = $feedFork
            }
        }
    }
    return $null
}

# What Package's listing asks Test-ShipClientRecorded. Replacing the hashes
# Ship-Rules loaded from the checkout is the whole of the pin.
function Apply-PackageClientRecord($Record) {
    $files = Get-Prop $Record 'files'
    if ($null -eq $files) { throw 'the client record names no files' }
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $hashes = @{}
    foreach ($prop in @($files.PSObject.Properties)) {
        [void]$set.Add([string]$prop.Name)
        $hashes[[string]$prop.Name] = ([string](Get-Prop $prop.Value 'sha256')).ToLowerInvariant()
    }
    if ($set.Count -lt 1) { throw 'the client record names no files' }
    $script:shipClientFiles = $set
    $script:ShipClientHashes = $hashes
}

function Save-PackageClientRecord($Resolved, [string]$Path) {
    $json = $null
    if ($null -ne $Resolved) { $json = $Resolved.Json }
    if (-not $json) { $json = ($Resolved.Record | ConvertTo-Json -Depth 6) }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding $false))
}

<#
  The licence record of the vcpkg libraries in the client this installer
  packs, and their texts (#3099), copied into $IntoDir beside the client
  record saved there: client-licences.json and client-licences\. The
  checkout's own when it is of $ForkCommit. Between main Ships the launcher
  being packed can carry an older client than the checkout records (#1243,
  above), and then it is the one the checkout's history committed for that
  client, taken with git archive, which writes the texts as committed
  (records/client-licences/** is -text). Throws a sentence when no commit of
  the checkout has one: the texts are owed with those files.
#>
function Save-PackageClientLicences([string]$ForkCommit, [string]$Repo, [string]$IntoDir) {
    $want = $ForkCommit.ToLowerInvariant()
    $null = New-Item -ItemType Directory -Force -Path $IntoDir
    $mine = Join-Path $Repo 'records\client-licences.json'
    if (Test-Path -LiteralPath $mine) {
        $read = Read-JsonFile $mine
        if ($read -and ([string](Get-Prop $read.Doc 'forkCommit')).ToLowerInvariant() -eq $want) {
            Copy-Item -LiteralPath $mine -Destination (Join-Path $IntoDir 'client-licences.json')
            Copy-Item -LiteralPath (Join-Path $Repo 'records\client-licences') -Destination (Join-Path $IntoDir 'client-licences') -Recurse
            return 'checkout'
        }
    }
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $revs = @(& git -C $Repo log --format=%H -- records/client-licences.json 2>$null | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        foreach ($rev in $revs) {
            $text = (@(& git -C $Repo show ($rev + ':records/client-licences.json') 2>$null) -join "`n")
            if ($LASTEXITCODE -ne 0 -or -not $text) { continue }
            $doc = $null
            try { $doc = $text | ConvertFrom-Json } catch { continue }
            if (([string](Get-Prop $doc 'forkCommit')).ToLowerInvariant() -ne $want) { continue }
            $zip = Join-Path $IntoDir 'client-licences.zip'
            & git -C $Repo archive --format=zip -o $zip $rev -- records/client-licences.json records/client-licences 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "git archive of records\client-licences at $rev exited $LASTEXITCODE" }
            $x = Join-Path $IntoDir 'x'
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::ExtractToDirectory($zip, $x)
            Move-Item -LiteralPath (Join-Path $x 'records\client-licences.json') -Destination (Join-Path $IntoDir 'client-licences.json')
            Move-Item -LiteralPath (Join-Path $x 'records\client-licences') -Destination (Join-Path $IntoDir 'client-licences')
            Remove-Item -LiteralPath $zip, $x -Recurse -Force
            return $rev
        }
    } finally { $ErrorActionPreference = $eap }
    throw "no commit of this checkout records the licences of client $ForkCommit (records\client-licences.json), and the texts of the libraries inside its files have to go with them (#3099)"
}

function Test-ClientRecordMatch($Record, [string]$Rel, [string]$Full) {
    $files = Get-Prop $Record 'files'
    if ($null -eq $files -or -not $Full -or -not (Test-Path -LiteralPath $Full -PathType Leaf)) { return $false }
    $want = $null
    foreach ($prop in @($files.PSObject.Properties)) {
        if ([string]::Equals([string]$prop.Name, $Rel, [StringComparison]::OrdinalIgnoreCase)) {
            $want = [string](Get-Prop $prop.Value 'sha256')
            break
        }
    }
    if (-not $want) { return $false }
    return ((Get-ClientFileSha256 $Full) -eq $want.ToLowerInvariant())
}
