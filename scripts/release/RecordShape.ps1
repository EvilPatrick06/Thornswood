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
      skyrim-pin          records\skyrim-pin.json        the Skyrim build a release is pinned to
      skyrim-files        records\skyrim-files.json      every file of that build (the launcher embeds it)
      ui-gone             records\ui-gone.json           the files every pack deletes (Ship and the launcher)
      generated           records\generated.json         what Build-Generated builds before a Ship

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
# Slice 4 (#2180): the box has no checkout, so the scripts that run there get
# this file's text with Read-JsonFile.ps1's in front of it ($ThornswoodRecordShapeText
# in Swap.ps1), or the two files beside them (Install-ThornswoodServer.ps1,
# sent by Publish-Server.ps1). Either way ConvertFrom-ThornswoodJson is
# already defined, and only a reader that has not loaded it loads it here.
if (-not (Get-Command ConvertFrom-ThornswoodJson -EA SilentlyContinue)) { . (Join-Path $PSScriptRoot 'Read-JsonFile.ps1') }

# Which versions each kind is understood at, and whether the file must say so.
$script:ThornswoodRecordKinds = [ordered]@{
    'server-build'       = @{ File = 'records\server-build.json';       Versions = @(1); MustSay = $false }
    'client-build'       = @{ File = 'records\client-build.json';       Versions = @(1); MustSay = $false }
    'most-online'        = @{ File = 'records\most-online.json';        Versions = @(1); MustSay = $false }
    'collection-plugins' = @{ File = 'records\collection-plugins.json'; Versions = @(1); MustSay = $true }
    # Slice 3 (#2180): the release records the launcher and Ship are built on.
    'skyrim-pin'         = @{ File = 'records\skyrim-pin.json';         Versions = @(1); MustSay = $false }
    'skyrim-files'       = @{ File = 'records\skyrim-files.json';       Versions = @(1); MustSay = $false }
    'ui-gone'            = @{ File = 'records\ui-gone.json';            Versions = @(1); MustSay = $false }
    'generated'          = @{ File = 'records\generated.json';          Versions = @(1); MustSay = $false }
    # Slice 4 (#2180): a server's own settings, read on the box. No committed
    # file (File is $null, so Check-Records skips it): each server keeps its own.
    'server-settings'    = @{ File = $null;                             Versions = @(1); MustSay = $false }
}

function Get-ThornswoodRecordProp($o, [string]$name) {
    if ($null -eq $o -or $o -isnot [psobject]) { return $null }
    $p = $o.PSObject.Properties[$name]
    # The comma keeps a list a list, even an empty one, instead of unrolling it.
    if ($p) { return , $p.Value }
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
            # The most the voice service takes at once (#481); MaxOnline.ps1
            # holds it to no fewer than the seats.
            $v = Get-ThornswoodRecordProp $Doc 'voice'
            if ($null -ne $v -and -not (Test-ThornswoodWhole $v 1)) { $out += 'voice is there and not a whole number above zero' }
        }
        'skyrim-pin' {
            # What Publish-Update writes into version.json and the launcher's
            # Downgrade asks Steam for: the build, the exe sizes, three depots.
            if (-not ((Get-ThornswoodRecordProp $Doc 'build') -is [string] -and (Get-ThornswoodRecordProp $Doc 'build') -match '^\d+(\.\d+){2,3}$')) { $out += 'build is missing or not a version like 1.6.1170' }
            if (-not (Test-ThornswoodWhole (Get-ThornswoodRecordProp $Doc 'appId') 1)) { $out += 'appId is missing or not a whole number above zero' }
            foreach ($k in 'expectedExeBytes', 'newerExeBytes') { if (-not (Test-ThornswoodWhole (Get-ThornswoodRecordProp $Doc $k) 1)) { $out += "$k is missing or not a whole number above zero" } }
            $deps = Get-ThornswoodRecordProp $Doc 'depots'
            if ($null -eq $deps -or $deps -isnot [array] -or @($deps).Count -ne 3) { $out += 'depots is missing or not three depots' }
            else {
                foreach ($d in @($deps)) {
                    $id = Get-ThornswoodRecordProp $d 'id'; $m = Get-ThornswoodRecordProp $d 'manifest'
                    if (-not ($id -is [string] -and $id -match '^\d+$') -or -not ($m -is [string] -and $m -match '^\d+$')) { $out += 'a depot is not an id and a manifest, each digits in a string' }
                }
            }
        }
        'skyrim-files' {
            if (-not ((Get-ThornswoodRecordProp $Doc 'build') -is [string] -and (Get-ThornswoodRecordProp $Doc 'build') -match '^\d+(\.\d+){2,3}$')) { $out += 'build is missing or not a version like 1.6.1170' }
            if (-not (Test-ThornswoodWhole (Get-ThornswoodRecordProp $Doc 'appId') 1)) { $out += 'appId is missing or not a whole number above zero' }
            $files = Get-ThornswoodRecordProp $Doc 'files'
            if ($null -eq $files -or $files -isnot [psobject] -or $files -is [array] -or $files -is [string] -or @($files.PSObject.Properties).Count -eq 0) { $out += 'files is missing, empty, or not a map of file to bytes, sha1 and depot' }
            else {
                foreach ($p in $files.PSObject.Properties) {
                    if (-not (Test-ThornswoodWhole (Get-ThornswoodRecordProp $p.Value 'bytes') 0)) { $out += "files.$($p.Name) has no whole bytes" }
                    if (-not (Test-ThornswoodHex (Get-ThornswoodRecordProp $p.Value 'sha1') 40 40)) { $out += "files.$($p.Name) has no sha1" }
                    $dp = Get-ThornswoodRecordProp $p.Value 'depot'
                    if (-not ($dp -is [string] -and $dp -match '^\d+$')) { $out += "files.$($p.Name) has no depot" }
                }
            }
        }
        'ui-gone' {
            # What every pack deletes and OwnGame.Foreign keeps out (#1318).
            $dae = Get-ThornswoodRecordProp $Doc 'daedric'
            if ($null -eq $dae -or $dae -isnot [psobject] -or $dae -is [array] -or $dae -is [string] -or @($dae.PSObject.Properties).Count -eq 0) { $out += 'daedric is missing, empty, or not a map of file name to sha256' }
            else { foreach ($p in $dae.PSObject.Properties) { if (-not (Test-ThornswoodHex $p.Value 64 64)) { $out += "daedric.$($p.Name) is not a sha256" } } }
            $un = Get-ThornswoodRecordProp $Doc 'unused'
            if ($null -eq $un -or $un -isnot [array] -or @($un).Count -eq 0) { $out += 'unused is missing, empty, or not a list of file names' }
            elseif (@($un | Where-Object { -not ($_ -is [string]) -or -not $_.Trim() }).Count) { $out += 'unused has an entry that is not a file name' }
        }
        'generated' {
            # What Build-Generated builds before a Ship (#1247). Either part may
            # be left out; what is there must be the shape Generated.ps1 reads.
            $pan = Get-ThornswoodRecordProp $Doc 'pandora'
            $bod = Get-ThornswoodRecordProp $Doc 'bodyslide'
            if ($null -eq $pan -and $null -eq $bod) { $out += 'it has neither pandora nor bodyslide, so it builds nothing' }
            if ($null -ne $pan) {
                $pp = Get-ThornswoodRecordProp $pan 'patches'
                if ($null -eq $pp -or $pp -isnot [array] -or @($pp | Where-Object { -not ($_ -is [string]) }).Count) { $out += 'pandora.patches is missing or not a list of patch codes' }
            }
            if ($null -ne $bod) {
                $ss = Get-ThornswoodRecordProp $bod 'sets'
                if ($null -eq $ss -or $ss -isnot [array] -or @($ss | Where-Object { -not ($_ -is [string]) -or -not $_.Trim() }).Count) { $out += 'bodyslide.sets is missing or not a list of set names' }
                $sl = Get-ThornswoodRecordProp $bod 'sliders'
                if ($null -ne $sl -and ($sl -isnot [psobject] -or $sl -is [array] -or $sl -is [string])) { $out += 'bodyslide.sliders is there and not a map' }
            }
        }
        'server-settings' {
            # What the box-side scripts read before they stop or start
            # anything: the port picks the process and the health check, and
            # dataDir and privDir say where the world is. skymp itself reads
            # the rest, and a broken key there is the server's to report.
            $port = Get-ThornswoodRecordProp $Doc 'port'
            if (-not (Test-ThornswoodWhole $port 1) -or [int64]$port -gt 65535) { $out += 'port is missing or not a whole number from 1 to 65535' }
            foreach ($k in 'dataDir', 'privDir') {
                $v = Get-ThornswoodRecordProp $Doc $k
                if ($null -ne $v -and (-not ($v -is [string]) -or -not $v.Trim())) { $out += "$k is there and not a folder name" }
            }
            $lo = Get-ThornswoodRecordProp $Doc 'loadOrder'
            if ($null -ne $lo -and ($lo -isnot [array] -or @($lo | Where-Object { -not ($_ -is [string]) -or -not $_.Trim() }).Count)) { $out += 'loadOrder is there and not a list of plugin paths' }
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
