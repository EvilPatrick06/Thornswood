<#
.SYNOPSIS
  Records which vcpkg libraries are in the client files, with each one's
  licence text, into records\client-licences.json and records\client-licences\.

.DESCRIPTION
  Issue #3099. The four native files of the six in records\client-build.json
  link the fork's vcpkg libraries statically (the fork's
  overlay_triplets\x64-windows-sp.cmake), so each library's code is inside
  the file that uses it, and the MIT and BSD ones ask for their copyright
  notice and licence text to go with every binary copy. None did: the client
  runtime zip, the packs and the installer carried the GPL and AGPL texts
  and no vcpkg one.

  The fork's build measures it (misc\thornswood\Write-ClientLicences.ps1 in
  the fork): it reads each file's own program database for the libraries the
  linker took and the source files with code in it, and writes each port's
  vcpkg copyright text and licences.json into build\licences. The fork's
  build keeps that folder in the artifact engine.yml records
  (ForkEngineBuild.ps1), and a build made here writes it the same way.

  This holds that folder to the clone's commit and to the client record, and
  writes:
    records\client-licences.json     the fork commit, what read it, each
                                     native client file and the ports in it,
                                     and each port's version, declared
                                     licence, files, and its text's size and
                                     sha256
    records\client-licences\<port>.txt   each text, byte for byte
  engine.yml keeps both under records\ in its artifact, and the pin pull
  request commits them with the other two records (engine\README.md, "The
  engine built in CI").

  Run it after New-ClientBuildRecord.ps1, from the same build. Read only
  except for what it writes. It never starts anything and never talks to
  the VPS.

.PARAMETER Licences
  The build's licences folder: licences.json and the texts.

.PARAMETER Clone
  The skymp clone the build is of, read for its commit.

.PARAMETER ClientRecord
  The client record the same build wrote.

.PARAMETER Out
  The record to write. The texts go in the folder of the same name beside it.

.EXAMPLE
  .\scripts\release\New-ClientLicenceRecord.ps1 -Licences engine\skymp\build\licences -Clone engine\skymp
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Licences,
  [string]$Clone = (& (Join-Path $PSScriptRoot 'Where.ps1') Engine),
  [string]$ClientRecord,
  [string]$Out
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Read-JsonFile.ps1')   # ConvertFrom-ThornswoodJson: a bad JSON file named
if (-not $ClientRecord) { $ClientRecord = Join-Path $PSScriptRoot '..\..\records\client-build.json' }
if (-not $Out) { $Out = Join-Path $PSScriptRoot '..\..\records\client-licences.json' }
$textDir = Join-Path (Split-Path -Parent $Out) ([IO.Path]::GetFileNameWithoutExtension($Out))

$measured = Join-Path $Licences 'licences.json'
if (-not (Test-Path -LiteralPath $measured)) { throw "$measured is not there: the build did not measure its client files' libraries (the fork's misc\thornswood\Write-ClientLicences.ps1). Nothing was recorded." }
$m = ConvertFrom-ThornswoodJson (Get-Content -LiteralPath $measured -Raw) $measured
$c = ConvertFrom-ThornswoodJson (Get-Content -LiteralPath $ClientRecord -Raw) $ClientRecord

$why = @()
$ErrorActionPreference = 'Continue'
$head = ((& git -C $Clone rev-parse HEAD 2>$null) -join '').Trim().ToLowerInvariant()
$ErrorActionPreference = 'Stop'
if ($head -notmatch '^[0-9a-f]{40}$') { throw "not a git clone, or it has no commit: $Clone. Nothing was recorded." }
if (([string]$m.commit).ToLowerInvariant() -ne $head) { $why += "licences.json is the build of $($m.commit), and $Clone is at $head" }
if (-not $head.StartsWith(([string]$c.forkCommit).ToLowerInvariant())) { $why += "$ClientRecord names fork commit $($c.forkCommit), and $Clone is at $head" }

# Every native file of the client record is measured, and nothing else is.
$native = @($c.files.PSObject.Properties.Name | Where-Object { $_ -match '\.(dll|exe\.hidden)$' })
$files = [ordered]@{}
$seen = @{}
foreach ($p in @($m.files.PSObject.Properties)) {
  $rel = ([string]$p.Name).Replace('/', '\')
  $seen[$rel] = $true
  if ($native -notcontains $rel) { $why += "licences.json measured $rel, which $ClientRecord does not record"; continue }
  $files[$rel] = @($p.Value.ports | ForEach-Object { [string]$_ } | Sort-Object)
}
foreach ($rel in $native) { if (-not $seen.ContainsKey($rel)) { $why += "$rel is in $ClientRecord and licences.json did not measure it" } }

# Every port named in a file has its text, as licences.json says it is.
$ports = [ordered]@{}
$named = @{}
foreach ($rel in $files.Keys) { foreach ($n in $files[$rel]) { $named[$n] = $true } }
foreach ($p in @($m.ports.PSObject.Properties | Sort-Object Name)) {
  $n = [string]$p.Name
  if ($n -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { $why += "licences.json names a port '$n', which is not a vcpkg port name"; continue }
  if (-not $named.ContainsKey($n)) { $why += "licences.json lists port $n, and no client file has it"; continue }
  $text = Join-Path $Licences ($n + '.txt')
  if (-not (Test-Path -LiteralPath $text -PathType Leaf)) { $why += "$n is in a client file and the build has no $n.txt"; continue }
  $sha = (Get-FileHash -LiteralPath $text -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($sha -ne ([string]$p.Value.sha256).ToLowerInvariant()) { $why += "$n.txt is not the text licences.json names (sha256)"; continue }
  $in = @($files.Keys | Where-Object { $files[$_] -contains $n })
  $ports[$n] = [ordered]@{
    version     = [string]$p.Value.version
    portVersion = [int]$p.Value.portVersion
    licence     = $(if ($p.Value.licence) { [string]$p.Value.licence } else { $null })
    in          = $in
    sha256      = $sha
    bytes       = (Get-Item -LiteralPath $text).Length
  }
}
$listed = @($m.ports.PSObject.Properties.Name)
foreach ($n in @($named.Keys | Sort-Object)) { if ($listed -notcontains $n) { $why += "$n is in a client file and licences.json lists no port $n" } }
if ($why.Count) { throw ('the build''s licences are not those of the client it recorded, and nothing was recorded: ' + ($why -join '; ')) }

if (Test-Path -LiteralPath $textDir) { Remove-Item -LiteralPath $textDir -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $textDir
foreach ($n in $ports.Keys) { Copy-Item -LiteralPath (Join-Path $Licences ($n + '.txt')) -Destination (Join-Path $textDir ($n + '.txt')) }

$record = [ordered]@{
  _note      = 'The vcpkg libraries whose code is in each native client file, read from its program database by the fork''s build, and each one''s licence text in client-licences\<port>.txt. Written by scripts\release\New-ClientLicenceRecord.ps1 (#3099).'
  forkCommit = [string]$c.forkCommit
  readWith   = [string]$m.readWith
  files      = $files
  ports      = $ports
}
[IO.File]::WriteAllText($Out, (($record | ConvertTo-Json -Depth 5) + "`n"), (New-Object Text.UTF8Encoding($false)))

Write-Host "recorded $($ports.Count) port(s) in $($files.Count) client file(s) from $($c.forkCommit) -> $Out" -ForegroundColor Green
foreach ($n in $ports.Keys) {
  $r = $ports[$n]
  Write-Host ("  {0,-30} {1,-14} {2,-22} {3}" -f $n, $r.version, $(if ($r.licence) { $r.licence } else { '(not declared)' }), (@($r.in | ForEach-Object { Split-Path -Leaf $_ }) -join ', '))
}
