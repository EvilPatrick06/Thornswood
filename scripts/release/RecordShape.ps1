<#
  RecordShape.ps1

  The shape and version each high-risk JSON record must have, checked fail
  closed (#2180, first slice). docs\JSON-STATE-INVENTORY.md lists every
  critical JSON file, who writes it and who reads it. This file holds the
  contract for the records in that list that a release or deploy trusts most:

      server-build        records\server-build.json      the server build every deploy is held to
      client-build        records\client-build.json      the client build Ship and the launcher are held to
      most-online         records\most-online.json       the seat count the engine and gamemode take
      collection-plugins  records\collection-plugins.json  the collection's plugin bytes (#2019)

      $doc = Read-ThornswoodRecord -Path <file> -Kind server-build
      $problems = Get-ThornswoodRecordProblems -Doc $doc -Kind server-build

  Read-ThornswoodRecord reads through ConvertFrom-ThornswoodJson (an empty or
  broken file names itself), then throws, naming the file, on:
    - a version this checkout does not know. Most records predate a version
      field and are read as version 1 when there is none; a record from a
      newer checkout that says 2 is refused rather than half understood.
    - a missing or wrongly typed field the readers depend on.
  No record is rewritten and no field is added: this is the check, not a
  migration. scripts\release\Check-Records.ps1 runs it over the committed
  records, and tests\test-record-shapes.ps1 holds it.
  Works on Windows PowerShell 5.1 and PowerShell 7.
#>
. (Join-Path $PSScriptRoot 'Read-JsonFile.ps1')

# Which versions each kind is understood at, and whether the file must say so.
$script:ThornswoodRecordKinds = [ordered]@{
    'server-build'       = @{ File = 'records\server-build.json';       Versions = @(1); MustSay = $false }
    'client-build'       = @{ File = 'records\client-build.json';       Versions = @(1); MustSay = $false }
    'most-online'        = @{ File = 'records\most-online.json';        Versions = @(1); MustSay = $false }
    'collection-plugins' = @{ File = 'records\collection-plugins.json'; Versions = @(1); MustSay = $true }
}

function Get-ThornswoodRecordProp($o, [string]$name) {
    if ($null -eq $o -or $o -isnot [psobject]) { return $null }
    $p = $o.PSObject.Properties[$name]
    if ($p) { return $p.Value }
    return $null
}
function Test-ThornswoodWhole($v, [int64]$min) {
    if ($null -eq $v -or $v -is [bool] -or $v -is [string]) { return $false }
    $n = 0L
    if (-not [int64]::TryParse([string]$v, [ref]$n)) { return $false }
    return ($n -ge $min -and [string]$n -eq [string]$v)
}
function Test-ThornswoodHex($v, [int]$min, [int]$max) {
    return ($v -is [string] -and $v -match ('^[0-9a-fA-F]{' + $min + ',' + $max + '}$'))
}
# A files map: { "<path>": { "sha256": ..., "bytes": ... }, ... }, not empty.
function Get-ThornswoodFilesMapProblems($files, [string]$what) {
    $out = @()
    if ($null -eq $files -or $files -isnot [psobject] -or $files -is [array] -or $files -is [string] -or @($files.PSObject.Properties).Count -eq 0) {
        return @("$what is missing, empty, or not a map of file to sha256 and bytes")
    }
    foreach ($p in $files.PSObject.Properties) {
        if (-not (Test-ThornswoodHex (Get-ThornswoodRecordProp $p.Value 'sha256') 64 64)) { $out += "$what.$($p.Name) has no sha256" }
        if (-not (Test-ThornswoodWhole (Get-ThornswoodRecordProp $p.Value 'bytes') 0)) { $out += "$what.$($p.Name) has no whole bytes" }
    }
    return $out
}

function Get-ThornswoodRecordProblems {
    param([Parameter(Mandatory)][AllowNull()]$Doc, [Parameter(Mandatory)][string]$Kind)
    if (-not $script:ThornswoodRecordKinds.Contains($Kind)) { throw "no record kind '$Kind' (known: $(@($script:ThornswoodRecordKinds.Keys) -join ', '))" }
    $k = $script:ThornswoodRecordKinds[$Kind]
    if ($null -eq $Doc -or $Doc -isnot [psobject] -or $Doc -is [array] -or $Doc -is [string]) { return @('it is not a JSON object') }
    $out = @()
    $ver = Get-ThornswoodRecordProp $Doc 'version'
    if ($null -eq $ver) {
        if ($k.MustSay) { $out += 'it has no version' }
    } elseif (-not (Test-ThornswoodWhole $ver 1) -or $k.Versions -notcontains [int]$ver) {
        $out += ("it is version {0}, and this checkout knows {1}: update the checkout, or the record came from somewhere else" -f $ver, ($k.Versions -join ', '))
        return $out
    }
    switch ($Kind) {
        'server-build' {
            if (-not (Test-ThornswoodHex (Get-ThornswoodRecordProp $Doc 'sha256') 64 64)) { $out += 'sha256 is missing or not 64 hex digits' }
            if (-not (Test-ThornswoodWhole (Get-ThornswoodRecordProp $Doc 'bytes') 1)) { $out += 'bytes is missing or not a whole number above zero' }
            if (-not (Test-ThornswoodHex (Get-ThornswoodRecordProp (Get-ThornswoodRecordProp $Doc 'source') 'commit') 40 40)) { $out += 'source.commit is missing or not a full commit SHA' }
            $out += @(Get-ThornswoodFilesMapProblems (Get-ThornswoodRecordProp $Doc 'files') 'files')
            $lp = Get-ThornswoodRecordProp $Doc 'lightPlugins'
            if ($null -ne $lp -and $lp -isnot [bool]) { $out += 'lightPlugins is there and not true or false' }
        }
        'client-build' {
            if (-not (Test-ThornswoodHex (Get-ThornswoodRecordProp $Doc 'forkCommit') 7 40)) { $out += 'forkCommit is missing or not a commit SHA' }
            $out += @(Get-ThornswoodFilesMapProblems (Get-ThornswoodRecordProp $Doc 'files') 'files')
        }
        'most-online' {
            if (-not (Test-ThornswoodWhole (Get-ThornswoodRecordProp $Doc 'people') 1)) { $out += 'people is missing or not a whole number above zero' }
            elseif ([int64](Get-ThornswoodRecordProp $Doc 'people') -gt 1000) { $out += 'people is over 1000, the engine''s limit' }
            $s = Get-ThornswoodRecordProp $Doc 'staffSeats'
            if ($null -ne $s -and -not (Test-ThornswoodWhole $s 0)) { $out += 'staffSeats is there and not a whole number' }
        }
        'collection-plugins' {
            $rows = Get-ThornswoodRecordProp $Doc 'plugins'
            if ($null -eq $rows -or @($rows).Count -eq 0) { $out += 'plugins is missing or empty' }
            else {
                $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
                foreach ($r in @($rows)) {
                    $n = Get-ThornswoodRecordProp $r 'name'
                    if (-not ($n -is [string]) -or -not $n) { $out += 'a plugins row has no name'; continue }
                    if (-not $seen.Add($n)) { $out += "plugins lists $n twice" }
                    if (-not (Test-ThornswoodWhole (Get-ThornswoodRecordProp $r 'size') 0)) { $out += "plugins.$n has no whole size" }
                    if (-not (Test-ThornswoodHex (Get-ThornswoodRecordProp $r 'sha256') 64 64)) { $out += "plugins.$n has no sha256" }
                }
            }
        }
    }
    return $out
}

function Read-ThornswoodRecord {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Kind)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "there is no $Kind record at $Path" }
    $doc = ConvertFrom-ThornswoodJson (Get-Content -LiteralPath $Path -Raw) $Path
    $bad = @(Get-ThornswoodRecordProblems -Doc $doc -Kind $Kind)
    if ($bad.Count) { throw ("{0} is not a {1} record this checkout can trust: {2}" -f $Path, $Kind, ($bad -join '; ')) }
    return $doc
}
