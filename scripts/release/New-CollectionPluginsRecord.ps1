<#
.SYNOPSIS
  Records every plugin a collection revision installs, hashed from the
  collection's own pinned archives, into records\collection-plugins.json.

.DESCRIPTION
  A deploy used to send a plugin when the box lacked it or the size differed.
  That is how a 3,288 byte 3BBB.esp left One on 5 Oct and became the server's
  copy (issue #2019). The collection's collection.json pins each archive by
  md5, not the plugin files inside it, so the same archive installed with
  other installer choices produces a different 3BBB.esp of the same size.

  This reads the revision's collection.json, opens each pinned archive from
  Vortex's downloads folder or from -Downloads, refuses unless the archive
  md5 matches the Nexus pin, writes archiveSha256, then hashes only the
  plugin files that revision's installer choices actually install. Nothing
  is read from a game Data folder, Vortex staging, or a server. A later run
  at the same revision holds each archive to the recorded archiveSha256.

  ModuleConfig.xml is parsed with DtdProcessing Prohibit and XmlResolver
  null. An archive entry whose path contains .. as a segment, or is rooted,
  refuses. A scripted installer, a missing ModuleConfig, a choice that names
  no option, or two mods that install the same plugin name refuse.

  Run this in the same pull request as a collection revision move. Never
  edit the record by hand.

.PARAMETER Revision
  The collection revision to record. The collection.json must name this
  revision or the run refuses.

.PARAMETER Collection
  The revision's collection.json, or the folder that holds it. Left off,
  Get-CollectionInstalledFolder / Get-CollectionJsonPath find the installed
  one.

.PARAMETER Downloads
  Folder of pinned archives, for a clean machine or CI. Left off, Vortex's
  downloads folder is used.

.PARAMETER Out
  The record to write. Default records\collection-plugins.json.

.PARAMETER Data
  Accepted so a test can pass a decoy Data folder. Never opened.

.PARAMETER Staging
  Accepted so a test can pass a decoy Vortex staging folder. Never opened.

.PARAMETER AccessLog
  Every file this run opens is appended here, so a test can prove Data and
  staging were not.

.PARAMETER SkipArchiveMd5
  Test hook for case 3: skip the archive md5 pin so a same-md5 fixture can
  still differ in sha256. A real run never needs this.

.EXAMPLE
  .\scripts\release\New-CollectionPluginsRecord.ps1 -Revision 2 -Downloads D:\Vortex\downloads
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][int]$Revision,
  [string]$Collection,
  [string]$Downloads,
  [string]$Out,
  [string]$Data,
  [string]$Staging,
  [string]$AccessLog,
  [switch]$SkipArchiveMd5
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\deploy\CollectionPlugins.ps1')
. (Join-Path $Here '..\mods\LoadOrder.ps1')

$script:Opened = New-Object System.Collections.Generic.List[string]
function Opened([string]$Path) {
  if ($Path) { [void]$script:Opened.Add([IO.Path]::GetFullPath($Path)) }
}
function Die([string]$why) {
  if ($AccessLog) {
    $dir = Split-Path -Parent $AccessLog
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [IO.File]::WriteAllLines($AccessLog, @($script:Opened))
  }
  Write-Host $why -ForegroundColor Red
  exit 1
}

if (-not $Out) { $Out = Join-Path $Here '..\..\records\collection-plugins.json' }

# -Data and -Staging exist only so a test can hand us a decoy. They are
# never opened. Touching them would be reading a machine's Data folder,
# which is the hole this record exists to close.
$null = $Data
$null = $Staging

function Read-JsonFile([string]$Path) {
  Opened $Path
  $raw = [IO.File]::ReadAllBytes($Path)
  $skip = 0
  if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { $skip = 3 }
  return [Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip) | ConvertFrom-Json
}

function Find-CollectionJson {
  if ($Collection) {
    if (Test-Path -LiteralPath $Collection -PathType Leaf) { return (Get-Item -LiteralPath $Collection).FullName }
    if (Test-Path -LiteralPath $Collection -PathType Container) {
      $p = Get-CollectionJsonPath $Collection
      if ($p) { return $p }
      $loose = Join-Path $Collection 'collection.json'
      if (Test-Path -LiteralPath $loose) { return (Get-Item -LiteralPath $loose).FullName }
    }
    Die "no collection.json at $Collection"
  }
  $folder = Get-CollectionInstalledFolder '7essxf'
  if (-not $folder) { Die 'this machine has no installed collection 7essxf, so there is no collection.json to record. Pass -Collection.' }
  $p = Get-CollectionJsonPath $folder.FullName
  if (-not $p) { Die ("no collection.json in {0}. Pass -Collection." -f $folder.FullName) }
  return $p
}

function Find-DownloadsFolder {
  if ($Downloads) {
    if (-not (Test-Path -LiteralPath $Downloads -PathType Container)) { Die "no downloads folder at $Downloads" }
    return (Get-Item -LiteralPath $Downloads).FullName
  }
  $spots = @(
    (Join-Path $env:APPDATA 'Vortex\downloads\skyrimse'),
    (Join-Path $env:APPDATA 'Vortex\downloads')
  )
  foreach ($s in $spots) { if ($s -and (Test-Path -LiteralPath $s -PathType Container)) { return $s } }
  Die 'no Vortex downloads folder on this machine. Pass -Downloads with the pinned archives.'
}

function Find-PinnedArchive([string]$Folder, $Source) {
  $wantMd5 = ''
  $srcNames = @($Source.PSObject.Properties | ForEach-Object { $_.Name })
  if ($srcNames -contains 'md5' -and $Source.md5) { $wantMd5 = ([string]$Source.md5).ToLowerInvariant() }
  $logical = ''
  if ($srcNames -contains 'logicalFilename' -and $Source.logicalFilename) { $logical = [string]$Source.logicalFilename }
  $modId = ''
  $fileId = ''
  if ($srcNames -contains 'modId') { $modId = [string]$Source.modId }
  if ($srcNames -contains 'fileId') { $fileId = [string]$Source.fileId }

  # Name first, then md5. A file at the pinned name with the wrong hash
  # must reach the caller so it can refuse as an md5 mismatch, not as
  # a missing archive. SkipArchiveMd5 (case 3) also needs the file
  # found by name when the bytes have changed.
  if ($logical) {
    $exact = Join-Path $Folder $logical
    if (Test-Path -LiteralPath $exact -PathType Leaf) {
      Opened $exact
      return (Get-Item -LiteralPath $exact).FullName
    }
  }
  if ($modId -and $fileId) {
    $hits = @(Get-ChildItem -LiteralPath $Folder -File -EA SilentlyContinue | Where-Object { $_.Name -like ($modId + '-' + $fileId + '*') })
    if ($hits.Count -eq 1) {
      Opened $hits[0].FullName
      return $hits[0].FullName
    }
  }
  if ($wantMd5) {
    foreach ($f in @(Get-ChildItem -LiteralPath $Folder -File -EA SilentlyContinue)) {
      if ($f.Extension -notin '.zip', '.7z', '.rar') { continue }
      Opened $f.FullName
      if ((Get-CollectionPluginsMd5 $f.FullName) -eq $wantMd5) { return $f.FullName }
    }
  }
  return $null
}

function Get-SevenZipExe {
  $c = Get-Command 7z -CommandType Application -EA SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  if (Get-Command Get-SevenZipPath -EA SilentlyContinue) { return Get-SevenZipPath }
  return $null
}

function Get-ArchiveEntryNames([string]$Archive) {
  $names = New-Object System.Collections.Generic.List[string]
  $ext = [IO.Path]::GetExtension($Archive).ToLowerInvariant()
  if ($ext -eq '.zip') {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -EA SilentlyContinue
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try { foreach ($e in $zip.Entries) { [void]$names.Add($e.FullName) } }
    finally { $zip.Dispose() }
    return $names.ToArray()
  }
  if ($ext -eq '.7z') {
    $exe = Get-SevenZipExe
    if (-not $exe) { throw 'reading a .7z needs 7-Zip and this machine has none' }
    $was = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $said = @(& $exe l -slt $Archive 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $was }
    foreach ($l in $said) {
      if ($l -match '^Path = (.+)$') {
        $p = $Matches[1]
        if ($p -ne $Archive) { [void]$names.Add($p) }
      }
    }
    return $names.ToArray()
  }
  throw ("archive {0} is not a .zip or .7z" -f [IO.Path]::GetFileName($Archive))
}

function Read-ArchiveEntryBytes([string]$Archive, [string]$Entry) {
  $ext = [IO.Path]::GetExtension($Archive).ToLowerInvariant()
  if ($ext -eq '.zip') {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -EA SilentlyContinue
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
      $want = $Entry.Replace('\', '/')
      $hit = @($zip.Entries | Where-Object {
        $_.FullName.Replace('\', '/') -eq $want -or
        $_.FullName.Replace('\', '/').TrimEnd('/') -eq $want.TrimEnd('/')
      }) | Select-Object -First 1
      if (-not $hit) { throw "archive $Archive has no entry $Entry" }
      $ms = New-Object IO.MemoryStream
      $s = $hit.Open()
      try { $s.CopyTo($ms) } finally { $s.Dispose() }
      return $ms.ToArray()
    } finally { $zip.Dispose() }
  }
  if ($ext -eq '.7z') {
    $exe = Get-SevenZipExe
    if (-not $exe) { throw 'reading a .7z needs 7-Zip and this machine has none' }
    $was = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $bytes = & $exe e -so $Archive $Entry 2>$null
      if ($LASTEXITCODE -ne 0 -or $null -eq $bytes) { throw "archive $Archive has no entry $Entry" }
      if ($bytes -is [byte[]]) { return $bytes }
      if ($bytes -is [string]) { return [Text.Encoding]::UTF8.GetBytes($bytes) }
      $ms = New-Object IO.MemoryStream
      foreach ($x in @($bytes)) {
        if ($x -is [byte[]]) { $null = $ms.Write($x, 0, $x.Length) }
        else {
          $b = [Text.Encoding]::UTF8.GetBytes([string]$x)
          $null = $ms.Write($b, 0, $b.Length)
        }
      }
      return $ms.ToArray()
    } finally { $ErrorActionPreference = $was }
  }
  throw ("archive {0} is not a .zip or .7z" -f [IO.Path]::GetFileName($Archive))
}

function Read-ModuleConfigXml([byte[]]$Bytes, [string]$ModName) {
  $settings = New-Object System.Xml.XmlReaderSettings
  $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
  $settings.XmlResolver = $null
  $settings.IgnoreWhitespace = $true
  $ms = New-Object IO.MemoryStream (,$Bytes)
  try {
    $reader = [System.Xml.XmlReader]::Create($ms, $settings)
    try {
      $doc = New-Object System.Xml.XmlDocument
      $doc.XmlResolver = $null
      $doc.Load($reader)
      return $doc
    } finally { $reader.Dispose() }
  } catch {
    throw ("mod {0}: ModuleConfig.xml refused: {1}" -f $ModName, $_.Exception.Message)
  } finally { $ms.Dispose() }
}

function Get-FomodFileSources($FilesNode) {
  $out = New-Object System.Collections.Generic.List[string]
  if ($null -eq $FilesNode) { return $out.ToArray() }
  foreach ($n in @($FilesNode.ChildNodes)) {
    if ($n.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
    $src = $n.GetAttribute('source')
    if (-not $src) { $src = $n.GetAttribute('Source') }
    if ($src) { [void]$out.Add($src) }
  }
  return $out.ToArray()
}

function Resolve-FomodPlugins([xml]$Doc, $Choices, [string[]]$EntryNames, [string]$ModName) {
  if ($Doc.SelectSingleNode('//*[local-name()="moduleScript"]') -or
      $Doc.SelectSingleNode('//*[local-name()="moduleInterface"]')) {
    throw ("mod {0}: scripted installer, which this generator does not run" -f $ModName)
  }
  $groups = @($Doc.SelectNodes('//*[local-name()="group"]'))
  $chosenFlags = @{}
  $sources = New-Object System.Collections.Generic.List[string]
  $required = $Doc.SelectSingleNode('//*[local-name()="requiredInstallFiles"]')
  foreach ($s in @(Get-FomodFileSources $required)) { [void]$sources.Add($s) }

  $opt = $null
  if ($Choices) {
    $cNames = @($Choices.PSObject.Properties | ForEach-Object { $_.Name })
    if ($cNames -contains 'options') { $opt = $Choices.options }
    elseif ($cNames -contains 'type' -or $cNames.Count) { $opt = $Choices }
  }
  for ($gi = 0; $gi -lt $groups.Count; $gi++) {
    $plugins = @($groups[$gi].SelectNodes('./*[local-name()="plugins"]/*[local-name()="plugin"]'))
    $picked = @()
    if ($opt) {
      $key = [string]$gi
      $prop = $opt.PSObject.Properties | Where-Object { $_.Name -eq $key } | Select-Object -First 1
      if (-not $prop) { $prop = $opt.PSObject.Properties | Where-Object { $_.Name -eq $groups[$gi].GetAttribute('name') } | Select-Object -First 1 }
      if ($prop) { $picked = @($prop.Value) }
    }
    if ($opt -and -not $picked.Count -and $plugins.Count) {
      throw ("mod {0}: choice for group {1} names no option" -f $ModName, $gi)
    }
    foreach ($idx in $picked) {
      $i = 0
      if (-not [int]::TryParse([string]$idx, [ref]$i)) { throw ("mod {0}: choice for group {1} names no option" -f $ModName, $gi) }
      if ($i -lt 0 -or $i -ge $plugins.Count) { throw ("mod {0}: choice for group {1} names no option" -f $ModName, $gi) }
      $plug = $plugins[$i]
      foreach ($s in @(Get-FomodFileSources ($plug.SelectSingleNode('./*[local-name()="files"]')))) { [void]$sources.Add($s) }
      foreach ($flag in @($plug.SelectNodes('.//*[local-name()="flag"]'))) {
        $chosenFlags[$flag.GetAttribute('name')] = $flag.InnerText
      }
    }
  }

  foreach ($pattern in @($Doc.SelectNodes('//*[local-name()="conditionalFileInstalls"]//*[local-name()="pattern"]'))) {
    $ok = $true
    foreach ($dep in @($pattern.SelectNodes('.//*[local-name()="flagDependency"]'))) {
      $name = $dep.GetAttribute('flag')
      $want = $dep.GetAttribute('value')
      $got = ''
      if ($chosenFlags.ContainsKey($name)) { $got = [string]$chosenFlags[$name] }
      if ($got -ne $want) { $ok = $false; break }
    }
    if (-not $ok) { continue }
    foreach ($s in @(Get-FomodFileSources ($pattern.SelectSingleNode('./*[local-name()="files"]')))) { [void]$sources.Add($s) }
  }

  $resolved = New-Object System.Collections.Generic.List[string]
  foreach ($src in $sources) {
    $want = $src.Replace('\', '/').TrimStart('/')
    $hits = @($EntryNames | Where-Object {
      $e = $_.Replace('\', '/').TrimStart('/')
      $e -eq $want -or $e.StartsWith($want.TrimEnd('/') + '/')
    })
    foreach ($h in $hits) { [void]$resolved.Add($h) }
  }
  return $resolved.ToArray()
}

function Get-PlainCopyEntries([string[]]$EntryNames) {
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($e in $EntryNames) {
    $norm = $e.Replace('\', '/')
    $segs = @($norm.Split('/'))
    if ($segs -contains 'fomod') { continue }
    $leaf = $segs[-1]
    if (-not $leaf -or -not (Test-CollectionPluginName $leaf)) { continue }
    [void]$out.Add($e)
  }
  return $out.ToArray()
}

# ---- collection.json --------------------------------------------------------
$jsonPath = Find-CollectionJson
$doc = Read-JsonFile $jsonPath
$haveRev = Get-CollectionJsonRevision $doc
if ($haveRev -ne $Revision) {
  Die ("collection.json revision is {0}, not -Revision {1}" -f $(if ($haveRev -gt 0) { $haveRev } else { 'missing' }), $Revision)
}
$slug = Get-CollectionJsonSlug $doc
$jsonSha = Get-CollectionPluginsSha256 $jsonPath
$dl = Find-DownloadsFolder

$prior = $null
if (Test-Path -LiteralPath $Out -PathType Leaf) {
  try {
    $prior = Read-CollectionPluginsRecord $Out
    if ($prior.Revision -ne $Revision) { $prior = $null }
  } catch { $prior = $null }
}

$mods = @()
$docNames = @($doc.PSObject.Properties | ForEach-Object { $_.Name })
if ($docNames -contains 'mods' -and $null -ne $doc.mods) { $mods = @($doc.mods) }

$pluginRows = @{}
foreach ($mod in $mods) {
  if ($null -eq $mod) { continue }
  $mNames = @($mod.PSObject.Properties | ForEach-Object { $_.Name })
  $modName = $(if ($mNames -contains 'name') { [string]$mod.name } else { 'unnamed' })
  if ($mNames -notcontains 'source' -or $null -eq $mod.source) { continue }
  $src = $mod.source
  $srcNames = @($src.PSObject.Properties | ForEach-Object { $_.Name })
  $archive = Find-PinnedArchive $dl $src
  if (-not $archive) {
    Die ("mod {0}: the pinned archive is not in {1}" -f $modName, $dl)
  }
  $gotMd5 = Get-CollectionPluginsMd5 $archive
  $wantMd5 = ''
  if ($srcNames -contains 'md5' -and $src.md5) { $wantMd5 = ([string]$src.md5).ToLowerInvariant() }
  if (-not $SkipArchiveMd5) {
    if (-not $wantMd5) { Die ("mod {0}: collection.json names no source.md5" -f $modName) }
    if ($gotMd5 -ne $wantMd5) {
      Die ("mod {0}: archive md5 {1} is not the collection pin {2}" -f $modName, $gotMd5, $wantMd5)
    }
  }
  $archSha = Get-CollectionPluginsSha256 $archive
  if ($prior) {
    foreach ($old in @($prior.Plugins.Values)) {
      $sameMod = $false
      if ($srcNames -contains 'modId' -and $null -ne $old.Mod -and [string]$old.Mod -eq [string]$src.modId) { $sameMod = $true }
      if ($sameMod -and $old.ArchiveSha256 -and $old.ArchiveSha256 -ne $archSha) {
        Die ("mod {0}: archive sha256 {1} is not the recorded archiveSha256 {2}" -f $modName, $archSha, $old.ArchiveSha256)
      }
    }
  }

  $entryNames = @(Get-ArchiveEntryNames $archive)
  foreach ($e in $entryNames) {
    if (-not (Test-ArchiveEntryPathSafe $e)) {
      Die ("mod {0}: archive entry '{1}' is a path escape or a rooted path" -f $modName, $e)
    }
  }

  $csEntries = @($entryNames | Where-Object { $_ -match '(^|[/\\])fomod[/\\].+\.cs$' })
  if ($csEntries.Count) { Die ("mod {0}: scripted installer, which this generator does not run" -f $modName) }

  $configName = @($entryNames | Where-Object { [IO.Path]::GetFileName($_) -eq 'ModuleConfig.xml' } | Select-Object -First 1)
  $via = 'copy'
  $installFrom = @()
  $hasFomod = [bool]($entryNames | Where-Object { $_ -replace '\\', '/' -match '(^|/)fomod/' })
  if ($hasFomod -and -not $configName) { Die ("mod {0}: missing ModuleConfig" -f $modName) }
  if ($configName) {
    $via = 'fomod'
    $xmlBytes = Read-ArchiveEntryBytes $archive $configName
    $xml = Read-ModuleConfigXml $xmlBytes $modName
    $choices = $null
    if ($mNames -contains 'choices') { $choices = $mod.choices }
    elseif ($mNames -contains 'installerChoices') { $choices = $mod.installerChoices }
    $installFrom = @(Resolve-FomodPlugins $xml $choices $entryNames $modName)
  } else {
    $installFrom = @(Get-PlainCopyEntries $entryNames)
  }

  foreach ($e in $installFrom) {
    $key = ConvertTo-CollectionPluginKey $e
    if (-not (Test-CollectionPluginName $key)) { continue }
    $bytes = Read-ArchiveEntryBytes $archive $e
    $sha = Get-CollectionPluginsSha256Bytes $bytes
    if ($pluginRows.ContainsKey($key)) {
      Die ("mod {0}: installs {1}, which {2} already installed" -f $modName, $key, $pluginRows[$key].ModName)
    }
    $pluginRows[$key] = [pscustomobject]@{
      Bytes         = [int64]$bytes.Length
      Sha256        = $sha
      Mod           = $(if ($srcNames -contains 'modId') { $src.modId } else { $null })
      FileId        = $(if ($srcNames -contains 'fileId') { $src.fileId } else { $null })
      ArchiveMd5    = $gotMd5
      ArchiveSha256 = $archSha
      ArchivePath   = $e
      Via           = $via
      ModName       = $modName
    }
  }
}

$obj = New-CollectionPluginsRecordObject $slug $Revision $jsonSha $pluginRows
Write-CollectionPluginsRecord $Out $obj
if ($AccessLog) {
  $dir = Split-Path -Parent $AccessLog
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  [IO.File]::WriteAllLines($AccessLog, @($script:Opened))
}
Write-Host ("wrote {0} plugins for {1} rev {2} to {3}" -f $pluginRows.Count, $slug, $Revision, $Out) -ForegroundColor Cyan
exit 0
