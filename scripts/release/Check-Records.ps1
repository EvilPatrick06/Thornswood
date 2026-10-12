<#
  Check-Records.ps1

  Holds the committed high-risk records to their shape and version, fail
  closed (#2180). Reads each record RecordShape.ps1 names, from this checkout
  or -Repo, and prints one line per record; exits 1 naming every record that
  is missing, empty, broken JSON, a version this checkout does not know, or
  short of a field its readers depend on.

      .\scripts\release\Check-Records.ps1
      .\scripts\release\Check-Records.ps1 -Repo <another checkout>

  Reads only. docs\JSON-STATE-INVENTORY.md lists the rest of the critical
  JSON and who owns it.
#>
[CmdletBinding()]
param([string]$Repo)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RecordShape.ps1')
if (-not $Repo) { $Repo = Join-Path $PSScriptRoot '..\..' }
$Repo = (Resolve-Path -LiteralPath $Repo).Path
$bad = 0
foreach ($kind in @($script:ThornswoodRecordKinds.Keys)) {
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
} catch { }   # either file unreadable is already REFUSED above
if ($bad) { Write-Host "$bad record(s) cannot be trusted." -ForegroundColor Red; exit 1 }
Write-Host 'Every high-risk record reads at a known version with the fields its readers need.'
# Said out loud: a caller that dot-runs this reads $LASTEXITCODE, which is
# otherwise whatever native command ran last (the build check's first run).
exit 0
