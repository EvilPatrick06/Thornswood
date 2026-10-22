<#
  Check-Records.ps1

  Holds the committed high-risk records to their shape and version, fail
  closed (#2180). Reads each record RecordShape.ps1 names, from this checkout
  or -Repo, and prints one line per record; exits 1 naming every record that
  is missing, empty, broken JSON, a version this checkout does not know, or
  short of a field its readers depend on.

      .\scripts\release\Check-Records.ps1
      .\scripts\release\Check-Records.ps1 -Repo <another checkout>
      .\scripts\release\Check-Records.ps1 -Feed <a feed store folder>

  -Feed (#2180, slice 5) holds that folder's version.json (which must be
  there), published.json and releases.json (each when there) to RecordShape's
  feed contracts instead, and checks nothing else. tests\fixtures\feed-2180
  is a committed sample that passes.

  Reads only. docs\JSON-STATE-INVENTORY.md lists the rest of the critical
  JSON and who owns it.
#>
[CmdletBinding()]
param([string]$Repo, [string]$Feed)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RecordShape.ps1')
if ($Feed) {
    if (-not (Test-Path -LiteralPath $Feed -PathType Container)) { Write-Host "  REFUSED  there is no feed folder at $Feed" -ForegroundColor Red; exit 1 }
    $bad = 0
    foreach ($kind in @($script:ThornswoodRecordKinds.Keys | Where-Object { $script:ThornswoodRecordKinds[$_].ContainsKey('Feed') })) {
        $name = $script:ThornswoodRecordKinds[$kind].Feed
        $path = Join-Path $Feed $name
        if ($name -ne 'version.json' -and -not (Test-Path -LiteralPath $path)) { Write-Host ('  NONE     {0,-20} {1}' -f $kind, $name); continue }
        try {
            $null = Read-ThornswoodRecord -Path $path -Kind $kind
            Write-Host ('  OK       {0,-20} {1}' -f $kind, $name)
        } catch {
            $bad++
            Write-Host ('  REFUSED  {0,-20} {1}' -f $kind, $_.Exception.Message) -ForegroundColor Red
        }
    }
    if ($bad) { Write-Host "$bad feed file(s) cannot be trusted." -ForegroundColor Red; exit 1 }
    Write-Host 'Every feed file there reads in the shape its readers need.'
    exit 0
}
if (-not $Repo) { $Repo = Join-Path $PSScriptRoot '..\..' }
$Repo = (Resolve-Path -LiteralPath $Repo).Path
$bad = 0
foreach ($kind in @($script:ThornswoodRecordKinds.Keys)) {
    # A kind with no committed file (server-settings) is each server's own, read on the box.
    if (-not $script:ThornswoodRecordKinds[$kind].File) { continue }
    $path = Join-Path $Repo $script:ThornswoodRecordKinds[$kind].File
    try {
        $null = Read-ThornswoodRecord -Path $path -Kind $kind
        Write-Host ('  OK       {0,-20} {1}' -f $kind, $script:ThornswoodRecordKinds[$kind].File)
    } catch {
        $bad++
        Write-Host ('  REFUSED  {0,-20} {1}' -f $kind, $_.Exception.Message) -ForegroundColor Red
    }
}
# skyrim-files.json is read out of the depots skyrim-pin.json names, so the
# two must be one build of one app; a pin moved without the file list is a
# launcher that calls the new build's files mods (#2180).
try {
    $pinDoc = ConvertFrom-ThornswoodJson (Get-Content -LiteralPath (Join-Path $Repo 'records\skyrim-pin.json') -Raw) 'records\skyrim-pin.json'
    $filesDoc = ConvertFrom-ThornswoodJson (Get-Content -LiteralPath (Join-Path $Repo 'records\skyrim-files.json') -Raw) 'records\skyrim-files.json'
    if ([string]$pinDoc.build -ne [string]$filesDoc.build -or [string]$pinDoc.appId -ne [string]$filesDoc.appId) {
        $bad++
        Write-Host ('  REFUSED  {0,-20} skyrim-pin.json is build {1} of app {2}, and skyrim-files.json is build {3} of app {4}: run New-SkyrimFilesRecord.ps1 after moving the pin' -f 'skyrim pin and files', $pinDoc.build, $pinDoc.appId, $filesDoc.build, $filesDoc.appId) -ForegroundColor Red
    } else {
        Write-Host ('  OK       {0,-20} one build, {1}' -f 'skyrim pin and files', $pinDoc.build)
    }
} catch {
    # The comparison could not be made, so the pair is not known to be one
    # build (#2711). This catch used to be empty, on the grounds that a file
    # that does not read is refused above, but anything else that stopped it
    # (a pin with no build field, under strict mode) passed in silence.
    $bad++
    Write-Host ('  REFUSED  {0,-20} could not compare skyrim-pin.json with skyrim-files.json: {1}' -f 'skyrim pin and files', $_.Exception.Message) -ForegroundColor Red
}
# client-licences.json is the licences of the client client-build.json
# records, and each text it names is beside it, byte for byte, with no other
# there (#3099): the downloads carry these texts with those files.
try {
    $cDoc = ConvertFrom-ThornswoodJson (Get-Content -LiteralPath (Join-Path $Repo 'records\client-build.json') -Raw) 'records\client-build.json'
    $lDoc = ConvertFrom-ThornswoodJson (Get-Content -LiteralPath (Join-Path $Repo 'records\client-licences.json') -Raw) 'records\client-licences.json'
    $why = @()
    if ([string]$lDoc.forkCommit -ne [string]$cDoc.forkCommit) { $why += "client-licences.json is of $($lDoc.forkCommit) and client-build.json of $($cDoc.forkCommit): record both from one build" }
    $native = @($cDoc.files.PSObject.Properties.Name | Where-Object { $_ -match '\.(dll|exe\.hidden)$' })
    $measured = @($lDoc.files.PSObject.Properties.Name)
    foreach ($f in $native) { if ($measured -notcontains $f) { $why += "client-licences.json does not measure $f" } }
    foreach ($f in $measured) { if ($native -notcontains $f) { $why += "client-licences.json measures $f, which client-build.json does not record" } }
    $dir = Join-Path $Repo 'records\client-licences'
    $named = @{}
    foreach ($p in @($lDoc.ports.PSObject.Properties)) {
        $named[$p.Name + '.txt'] = $true
        $t = Join-Path $dir ($p.Name + '.txt')
        if (-not (Test-Path -LiteralPath $t -PathType Leaf)) { $why += "records\client-licences\$($p.Name).txt is missing"; continue }
        if ((Get-FileHash -LiteralPath $t -Algorithm SHA256).Hash.ToLowerInvariant() -ne ([string]$p.Value.sha256).ToLowerInvariant() -or (Get-Item -LiteralPath $t).Length -ne [long]$p.Value.bytes) {
            $why += "records\client-licences\$($p.Name).txt is not the text client-licences.json names (a checkout that turned its line ends, or an edit)"
        }
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) { if (-not $named.ContainsKey($f.Name)) { $why += "records\client-licences\$($f.Name) is there and client-licences.json names no such port" } }
    if ($why.Count) {
        $bad++
        Write-Host ('  REFUSED  {0,-20} {1}' -f 'client licences', ($why -join '; ')) -ForegroundColor Red
    } else {
        Write-Host ('  OK       {0,-20} {1} texts, of {2}' -f 'client licences', $named.Count, $lDoc.forkCommit)
    }
} catch {
    $bad++
    Write-Host ('  REFUSED  {0,-20} could not hold client-licences.json to client-build.json and its texts: {1}' -f 'client licences', $_.Exception.Message) -ForegroundColor Red
}
if ($bad) { Write-Host "$bad record(s) cannot be trusted." -ForegroundColor Red; exit 1 }
Write-Host 'Every high-risk record reads at a known version with the fields its readers need.'
# Said out loud: a caller that dot-runs this reads $LASTEXITCODE, which is
# otherwise whatever native command ran last (the build check's first run).
exit 0
