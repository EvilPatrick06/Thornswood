<#
  Package-Stage.ps1
  The installer's stage folder, kept from one build to the next, and the one
  compression of it. Dot-sourced by Package-Thornswood.ps1, and by
  tests\test-3752-package-stage.ps1, which runs both against a scratch folder.

  WHY THE STAGE IS KEPT (#3752). Every Ship deleted the stage and copied every
  kept file into it again, because only -ReuseStage synced, and neither Ship
  nor Ship-Stack passed it. That sync compared length and write time, which is
  not enough for this build: the front's zip gives every file one fixed time
  (Write-ThornswoodFrontZip, Front.ps1), so a front file that changed and kept
  its length had the same length and the same time as the staged copy and
  stayed stale. So now there is one path, and it compares content wherever
  length and time agree. The stage it leaves is the stage a clean copy would
  leave, file for file and byte for byte, with no empty folder from a file
  that left the build, so no switch for a clean stage is needed.

  WHY ONE COMPRESSION (#3752). A failed zip was built again from the start
  with no -mx, which is 7-Zip's level 5: slower, and no help against what fails
  it (a full disk, a file held open). 7-Zip's exit 1 was taken as success,
  though it means a file could not be read and is not in the archive.
#>

# This system's separator, and a record's backslashes turned into it, so the
# same rels work on Windows and in a harness under pwsh on Linux (#2989).
function Get-PackageStagePath([string]$Dir, [string]$Rel) {
    return (Join-Path $Dir $Rel.Replace('\', [string][IO.Path]::DirectorySeparatorChar))
}

function Get-PackageStageSha256([string]$Full) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fs = New-Object IO.FileStream($Full, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try { return [BitConverter]::ToString($sha.ComputeHash($fs)) }
        finally { $fs.Dispose() }
    }
    finally { $sha.Dispose() }
}

<#
  Brings <Stage>\payload level with $Ship, the files Package-Thornswood keeps
  (each with Rel, Full, Len and Time), and empties the rest of the stage, which
  the packager writes fresh after this. Anything an earlier build left at the
  top of the stage would otherwise go into the zip, which takes all of it.

  A staged file is kept when its length and write time are the build's and
  its content is too. A copy is given the build file's write time, so the next
  build finds it level. A file that left the build is removed, and so is a
  folder that leaves empty. A removal that fails throws: that file is not in
  the build and would be in the installer.

  Returns the counts, what was copied, and the longest path in the payload,
  worked out from the rels rather than by listing the payload again.
#>
function Sync-PackageStage {
    param(
        [Parameter(Mandatory)][string]$Stage,
        [AllowEmptyCollection()][object[]]$Ship = @()
    )
    $payload = Join-Path $Stage 'payload'
    $null = New-Item -ItemType Directory -Force -Path $Stage
    foreach ($top in @(Get-ChildItem -LiteralPath $Stage -Force)) {
        if ($top.PSIsContainer -and $top.Name -eq 'payload') { continue }
        Remove-Item -LiteralPath $top.FullName -Recurse -Force -ErrorAction Stop
    }
    $null = New-Item -ItemType Directory -Force -Path $payload, (Join-Path $Stage 'profile')

    $sep = [string][IO.Path]::DirectorySeparatorChar
    $listed = (Get-Item -LiteralPath $payload).FullName.TrimEnd($sep)
    $have = New-Object 'System.Collections.Generic.Dictionary[string,IO.FileInfo]' ([StringComparer]::OrdinalIgnoreCase)
    $dirs = @()
    foreach ($e in (Get-ChildItem -LiteralPath $listed -Recurse -Force)) {
        if ($e.PSIsContainer) { $dirs += $e.FullName; continue }
        $have[$e.FullName.Substring($listed.Length + 1).Replace($sep, '\')] = $e
    }

    $new = 0; $changed = 0; $kept = 0
    $copied = New-Object 'System.Collections.Generic.List[string]'
    $longest = 0; $longestPath = ''
    foreach ($f in $Ship) {
        $dest = Get-PackageStagePath $listed $f.Rel
        if ($dest.Length -gt $longest) { $longest = $dest.Length; $longestPath = $dest }
        $old = $null
        if ($have.TryGetValue($f.Rel, [ref]$old)) {
            [void]$have.Remove($f.Rel)
            if ($old.Length -eq $f.Len -and $old.LastWriteTimeUtc -eq $f.Time -and
                (Get-PackageStageSha256 $old.FullName) -eq (Get-PackageStageSha256 $f.Full)) { $kept++; continue }
            $changed++
        } else { $new++ }
        $dir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Force -Path $dir }
        Copy-Item -LiteralPath $f.Full -Destination $dest -Force
        [IO.File]::SetLastWriteTimeUtc($dest, $f.Time)
        $copied.Add($f.Rel)
    }

    # Whatever is left in the table is no longer part of the build.
    $gone = 0
    foreach ($leftover in $have.Values) { Remove-Item -LiteralPath $leftover.FullName -Force -ErrorAction Stop; $gone++ }
    # Deepest first, so a folder whose only content was an empty folder goes too.
    foreach ($d in @($dirs | Sort-Object Length -Descending)) {
        if (-not [IO.Directory]::EnumerateFileSystemEntries($d).GetEnumerator().MoveNext()) { Remove-Item -LiteralPath $d -Force -ErrorAction Stop }
    }

    return [pscustomobject]@{
        New = $new; Changed = $changed; Gone = $gone; Kept = $kept
        Copied = @($copied); Longest = $longest; LongestPath = $longestPath
    }
}

# The stage's size: the payload's bytes, which the listing already summed, and
# whatever the packager wrote beside it, which is a few small files.
function Get-PackageStageBytes([string]$Stage, [long]$PayloadBytes) {
    $bytes = $PayloadBytes
    foreach ($top in @(Get-ChildItem -LiteralPath $Stage -Force)) {
        if ($top.PSIsContainer -and $top.Name -eq 'payload') { continue }
        if ($top.PSIsContainer) {
            foreach ($f in (Get-ChildItem -LiteralPath $top.FullName -Recurse -File -Force)) { $bytes += $f.Length }
        } else { $bytes += $top.Length }
    }
    return $bytes
}

<#
  Zips the stage into $Blob once, at -mx$Level, from inside the stage so the
  archive's paths start there. Zip, not 7z, because the installer unpacks it
  with what .NET already has and never needs 7-Zip on anybody's machine.

  Only exit 0 with the archive written is a zip. Returns the exit code and
  what 7-Zip said; the caller says what the code means and stops.

  A native tool writing a single line to stderr is enough to kill the whole
  script while ErrorActionPreference is Stop, so 7-Zip runs with it relaxed.
  Its output is kept apart from the exit code, which an earlier version
  returned together, so the code read as an array of every line 7-Zip printed.
#>
function Invoke-PackageZip([string]$SevenZip, [string]$Stage, [string]$Blob, [int]$Level) {
    $zargs = @('a', '-tzip', '-y', "-mx$Level", $Blob, '*')
    Write-Host ("  > 7z " + ($zargs -join ' ')) -ForegroundColor DarkGray
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location -LiteralPath $Stage
    try {
        $global:LASTEXITCODE = 0
        $said = @(& $SevenZip @zargs 2>&1 | ForEach-Object { "$_" })
        $code = [int]$LASTEXITCODE
    }
    finally { Pop-Location; $ErrorActionPreference = $old }
    if ($code -eq 0 -and -not (Test-Path -LiteralPath $Blob)) { $code = -1 }
    if ($code -ne 0 -and (Test-Path -LiteralPath $Blob)) { Remove-Item -LiteralPath $Blob -Force }
    return [pscustomobject]@{ Code = $code; Said = $said }
}

# What a failed zip's exit code means, for the person running the build, from
# 7-Zip's own list of codes. None of them is helped by running it again.
function Get-PackageZipWhy([int]$Code) {
    switch ($Code) {
        -1 { return @('7-Zip exited 0 but wrote no archive.') }
        1 { return @('Exit code 1 is a warning: a file could not be read, nearly always because something holds it open,',
                     'so the archive would be missing it. The lines above name it. Close what holds it, then run this again.') }
        2 { return @('Exit code 2 is a fatal error, nearly always the disk filling up part way through.',
                     'Check free space first:', '    Get-PSDrive C | Select-Object Used, Free') }
        7 { return @('Exit code 7 is a command line 7-Zip did not accept, so the line above is wrong in this script.') }
        8 { return @('Exit code 8 is 7-Zip running out of memory.') }
        default { return @("7-Zip exited with $Code.") }
    }
}
