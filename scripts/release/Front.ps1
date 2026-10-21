<#
  Front.ps1

      . (Join-Path $PSScriptRoot 'Front.ps1')

  What Build-Front.ps1 and Go.ps1 share about the front build, the page
  skymp5-front's webpack makes for Data\Platform\UI: the record of it, the
  zip it travels in, and the check that a zip is the recorded build.

  WHY. Until 20 October the front was local\thornswood-front.zip, built on
  One from nobody knew which commit and checked by nothing, and Go.ps1
  unpacked whatever was there. Measured that day (#1317): the zip predated
  the fork's #40, so every release still shipped four commercial faces, DIN
  Pro and Futura PT, as hashed .ttf files under Data\Platform\UI, a month
  after the fork had taken them out. Patrick's A on #2754 builds the front
  from the pinned fork instead, in the cloud or anywhere, so the build is
  recorded like the client's (records\front-build.json) and a zip that is not
  that build is refused.

  Works on Windows PowerShell 5.1 and PowerShell 7, on Windows and Linux.
#>

$ThornswoodFrontRecordPath = Join-Path $PSScriptRoot '..\..\records\front-build.json'

function Add-ThornswoodZipTypes {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}

function Get-ThornswoodSha256OfStream([IO.Stream]$s) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($s)) -replace '-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

# Each file in a folder, by its name relative to the folder with / between
# parts, to its sha256 and bytes, in ordinal order.
function Get-ThornswoodFolderFiles([string]$Folder) {
    $root = (Resolve-Path -LiteralPath $Folder).ProviderPath.TrimEnd('\', '/')
    $out = [ordered]@{}
    $all = @(Get-ChildItem -LiteralPath $root -File -Recurse | ForEach-Object {
        [pscustomobject]@{ Rel = $_.FullName.Substring($root.Length + 1).Replace('\', '/'); Full = $_.FullName; Bytes = $_.Length }
    })
    foreach ($f in @($all | Sort-Object { $_.Rel } -Culture '' -CaseSensitive)) {
        $s = [IO.File]::OpenRead($f.Full)
        try { $h = Get-ThornswoodSha256OfStream $s } finally { $s.Dispose() }
        $out[$f.Rel] = [pscustomobject]@{ sha256 = $h; bytes = [long]$f.Bytes }
    }
    return $out
}

# Each file in a zip, the same way.
function Get-ThornswoodZipFiles([string]$Zip) {
    Add-ThornswoodZipTypes
    $out = [ordered]@{}
    $z = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($e in @($z.Entries | Where-Object { $_.Name } | Sort-Object { $_.FullName.Replace('\', '/') } -Culture '' -CaseSensitive)) {
            $s = $e.Open()
            try { $h = Get-ThornswoodSha256OfStream $s } finally { $s.Dispose() }
            $out[$e.FullName.Replace('\', '/')] = [pscustomobject]@{ sha256 = $h; bytes = [long]$e.Length }
        }
    } finally { $z.Dispose() }
    return $out
}

# A zip of the folder's files, in ordinal order with one fixed time, so the
# same build makes the same zip on any machine.
function Write-ThornswoodFrontZip([string]$Folder, [string]$Zip) {
    Add-ThornswoodZipTypes
    $root = (Resolve-Path -LiteralPath $Folder).ProviderPath.TrimEnd('\', '/')
    if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
    $dir = Split-Path -Parent $Zip
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $when = New-Object DateTimeOffset 2000, 1, 1, 0, 0, 0, ([TimeSpan]::Zero)
    $z = [IO.Compression.ZipFile]::Open($Zip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($rel in @((Get-ThornswoodFolderFiles $root).Keys)) {
            $e = $z.CreateEntry($rel, [IO.Compression.CompressionLevel]::Optimal)
            $e.LastWriteTime = $when
            $w = $e.Open()
            try {
                $r = [IO.File]::OpenRead((Join-Path $root $rel))
                try { $r.CopyTo($w) } finally { $r.Dispose() }
            } finally { $w.Dispose() }
        }
    } finally { $z.Dispose() }
}

function Read-ThornswoodFrontRecord([string]$Path = $ThornswoodFrontRecordPath) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "there is no front build record at $Path" }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8).TrimStart([char]0xFEFF) | ConvertFrom-Json
}

# What is wrong with a set of files against the record: a file it does not
# list, a file with other bytes, a file it lists that is not there. None is
# the recorded build.
function Get-ThornswoodFrontProblems($Files, $Record) {
    $want = @{}
    foreach ($p in $Record.files.PSObject.Properties) { $want[$p.Name] = $p.Value }
    $out = @()
    foreach ($k in @($Files.Keys)) {
        if (-not $want.ContainsKey($k)) { $out += "$k is not in the recorded build"; continue }
        if ($Files[$k].sha256 -ne ([string]$want[$k].sha256).ToLowerInvariant()) { $out += "$k is not the recorded bytes" }
    }
    foreach ($k in @($want.Keys | Sort-Object)) { if (-not $Files.Contains($k)) { $out += "$k, which the build makes, is missing" } }
    return $out
}
