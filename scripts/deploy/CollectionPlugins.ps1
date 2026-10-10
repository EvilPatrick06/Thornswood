<#
  CollectionPlugins.ps1

  The collection's own plugin bytes, held to records\collection-plugins.json
  rather than to size or to whatever a machine's Data folder happens to hold
  (issue #2019). Dot-sourced by New-CollectionPluginsRecord.ps1,
  Check-ServerPlugins.ps1, Export-ServerPayload.ps1, Deploy-Server.ps1 and
  Deploy-DevGamemode.ps1. Swap.ps1 puts $CollectionPinnedText in front of the
  stage check and the put-back pick, so the box hashes what it holds against
  $Pinned literals sent from this machine and never opens a record.

  WHY. On 5 Oct a 3,288 byte 3BBB.esp left One and became the server's copy,
  because Deploy-Server compared name and size and a same-size wrong file
  went up. The launcher then held every player to the server's manifest, so
  the bad file became truth. Size cannot catch that. The collection's pinned
  archive can.

  Keep it ASCII and Windows PowerShell 5.1: part of it runs on the box.
#>

# Far-side only: hashes load-order plugins whose names are in $Pinned, which
# SwapVars sent as quoted literals. Opens no record, no manifest, no file
# other than the plugin it is hashing. $PinRefuse is set on the deploying
# machine: $true refuses (full deploy), $false prints WARNING and goes on
# (-GamemodeOnly). -PutBack never calls this; its own pick always refuses.
$CollectionPinnedText = @'
function Test-PinnedPlugins($order, [string]$stageDir, [string]$pluginsDir, $pinned) {
  $rows = New-Object System.Collections.Generic.List[object]
  if ($null -eq $pinned) { return }
  foreach ($p in @($order)) {
    $at = ([string]$p) -replace '/', '\'
    if (-not $at) { continue }
    $leaf = [IO.Path]::GetFileName($at)
    $want = $null
    foreach ($k in @($pinned.Keys)) {
      if ([string]::Equals([string]$k, $leaf, [StringComparison]::OrdinalIgnoreCase)) { $want = [string]$pinned[$k]; break }
    }
    if (-not $want) { continue }
    $staged = $null
    if ($stageDir) { $staged = Join-Path $stageDir ('plugins\' + $leaf) }
    $path = $at
    if ($staged -and (Test-Path -LiteralPath $staged)) { $path = $staged }
    elseif ($pluginsDir) {
      $onDisk = Join-Path $pluginsDir $leaf
      if (Test-Path -LiteralPath $onDisk) { $path = $onDisk }
    }
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $got = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($got -eq $want.ToLowerInvariant()) { continue }
    $line = ($leaf + ' at ' + $path + ' is sha256 ' + $got + ', the collection''s is ' + $want.ToLowerInvariant())
    $kind = 'warn'
    if (-not (Test-Path variable:PinRefuse) -or $PinRefuse) { $kind = 'refuse' }
    [void]$rows.Add([pscustomobject]@{ Kind = $kind; Line = $line; Name = $leaf; Path = $path; Got = $got; Want = $want.ToLowerInvariant() })
  }
  foreach ($row in $rows) { $row }
}
'@

function Get-CollectionPluginsSha256([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "there is no file at $Path"
  }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-CollectionPluginsSha256Bytes([byte[]]$Bytes) {
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Get-CollectionPluginsMd5([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "there is no file at $Path"
  }
  $md5 = [Security.Cryptography.MD5]::Create()
  $fs = [IO.File]::OpenRead($Path)
  try { return [BitConverter]::ToString($md5.ComputeHash($fs)).Replace('-', '').ToLowerInvariant() }
  finally { $fs.Dispose(); $md5.Dispose() }
}

function Get-CollectionPluginsDocRevision([string]$DocsDir) {
  if (-not $DocsDir -or -not (Test-Path -LiteralPath $DocsDir -PathType Container)) { return 0 }
  $best = 0
  foreach ($f in @(Get-ChildItem -LiteralPath $DocsDir -File -Filter 'COLLECTION-REVISION-*.md' -EA SilentlyContinue)) {
    $m = [regex]::Match($f.Name, '^COLLECTION-REVISION-(\d+)\.md$')
    if (-not $m.Success) { continue }
    $n = [int]$m.Groups[1].Value
    if ($n -gt $best) { $best = $n }
  }
  return $best
}

function Test-ArchiveEntryPathSafe([string]$Name) {
  $n = [string]$Name
  if (-not $n) { return $true }
  $norm = $n.Replace('/', '\')
  if ($norm.StartsWith('\') -or $n.StartsWith('/')) { return $false }
  if ($norm -match '^[A-Za-z]:') { return $false }
  foreach ($seg in $norm.Split([char]'\') ) {
    if ($seg -eq '..') { return $false }
  }
  return $true
}

function ConvertTo-CollectionPluginKey([string]$ArchivePath) {
  $n = ([string]$ArchivePath).Replace('/', '\')
  $i = $n.LastIndexOf([char]'\')
  if ($i -ge 0) { return $n.Substring($i + 1) }
  return $n
}

function Test-CollectionPluginName([string]$Name) {
  return ([string]$Name -match '\.es[pml]$')
}

function Get-CollectionJsonRevision($Doc) {
  if ($null -eq $Doc) { return 0 }
  $names = @($Doc.PSObject.Properties | ForEach-Object { $_.Name })
  if ($names -contains 'revision' -and $Doc.revision -match '^\d+$') { return [int]$Doc.revision }
  if ($names -contains 'info' -and $null -ne $Doc.info) {
    $infoNames = @($Doc.info.PSObject.Properties | ForEach-Object { $_.Name })
    if ($infoNames -contains 'revision' -and $Doc.info.revision -match '^\d+$') { return [int]$Doc.info.revision }
    if ($infoNames -contains 'revisionNumber' -and $Doc.info.revisionNumber -match '^\d+$') { return [int]$Doc.info.revisionNumber }
  }
  return 0
}

function Get-CollectionJsonSlug($Doc) {
  if ($null -eq $Doc) { return '' }
  $names = @($Doc.PSObject.Properties | ForEach-Object { $_.Name })
  if ($names -contains 'info' -and $null -ne $Doc.info) {
    $infoNames = @($Doc.info.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($k in 'slug', 'collectionSlug', 'collectionId') {
      if ($infoNames -contains $k -and $Doc.info.$k) { return [string]$Doc.info.$k }
    }
  }
  return '7essxf'
}

function Read-CollectionPluginsRecord([string]$Path) {
  if (-not $Path) { throw 'Read-CollectionPluginsRecord was given no path, so there is no record to hold plugins to.' }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "there is no collection plugin record at $Path, so nothing says which bytes a collection plugin must be. Nothing was sent."
  }
  $raw = $null
  try { $raw = [IO.File]::ReadAllText($Path) } catch {
    throw "$Path could not be read: $($_.Exception.Message). Nothing was sent."
  }
  $doc = $null
  try { $doc = $raw | ConvertFrom-Json } catch {
    throw "$Path does not parse: $($_.Exception.Message). Nothing was sent."
  }
  if ($null -eq $doc) { throw "$Path is empty JSON, so nothing says which bytes a collection plugin must be. Nothing was sent." }
  $names = @($doc.PSObject.Properties | ForEach-Object { $_.Name })
  foreach ($need in 'collection', 'revision', 'collectionJsonSha256', 'generatedBy', 'plugins') {
    if ($names -notcontains $need) { throw "$Path has no $need, so the record is corrupt. Nothing was sent." }
  }
  if (-not $doc.collection) { throw "$Path names no collection. Nothing was sent." }
  if ([string]$doc.revision -notmatch '^\d+$' -or [int]$doc.revision -le 0) { throw "$Path revision is not a positive number. Nothing was sent." }
  if ([string]$doc.collectionJsonSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw "$Path collectionJsonSha256 is not a SHA256. Nothing was sent." }
  if ($null -eq $doc.plugins) { throw "$Path has no plugins object. Nothing was sent." }
  $plugins = @{}
  foreach ($p in @($doc.plugins.PSObject.Properties)) {
    $n = [string]$p.Name
    if (-not (Test-CollectionPluginName $n)) { throw "$Path plugin key '$n' is not an .esp, .esm or .esl. Nothing was sent." }
    $row = $p.Value
    if ($null -eq $row) { throw "$Path plugin '$n' is empty. Nothing was sent." }
    $rowNames = @($row.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($need in 'bytes', 'sha256') {
      if ($rowNames -notcontains $need) { throw "$Path plugin '$n' has no $need. Nothing was sent." }
    }
    if ([string]$row.bytes -notmatch '^\d+$' -or [int64]$row.bytes -le 0) { throw "$Path plugin '$n' bytes is not a positive count. Nothing was sent." }
    if ([string]$row.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw "$Path plugin '$n' sha256 is not a SHA256. Nothing was sent." }
    $plugins[$n] = [pscustomobject]@{
      Name          = $n
      Bytes         = [int64]$row.bytes
      Sha256        = ([string]$row.sha256).ToLowerInvariant()
      Mod           = $(if ($rowNames -contains 'mod') { $row.mod } else { $null })
      FileId        = $(if ($rowNames -contains 'fileId') { $row.fileId } else { $null })
      ArchiveMd5    = $(if ($rowNames -contains 'archiveMd5') { [string]$row.archiveMd5 } else { '' })
      ArchiveSha256 = $(if ($rowNames -contains 'archiveSha256') { ([string]$row.archiveSha256).ToLowerInvariant() } else { '' })
      ArchivePath   = $(if ($rowNames -contains 'archivePath') { [string]$row.archivePath } else { '' })
      Via           = $(if ($rowNames -contains 'via') { [string]$row.via } else { '' })
    }
  }
  return [pscustomobject]@{
    Path                 = $Path
    Collection           = [string]$doc.collection
    Revision             = [int]$doc.revision
    CollectionJsonSha256 = ([string]$doc.collectionJsonSha256).ToLowerInvariant()
    GeneratedBy          = [string]$doc.generatedBy
    Plugins              = $plugins
    Raw                  = $raw
  }
}

function Get-CollectionRecordPlugin([hashtable]$Plugins, [string]$Name) {
  if ($null -eq $Plugins -or -not $Name) { return $null }
  foreach ($k in @($Plugins.Keys)) {
    if ([string]::Equals([string]$k, $Name, [StringComparison]::OrdinalIgnoreCase)) { return $Plugins[$k] }
  }
  return $null
}

function Test-CollectionPluginFile($Record, [string]$Name, [string]$Path) {
  $hit = Get-CollectionRecordPlugin $Record.Plugins $Name
  $row = [pscustomobject]@{
    Name         = $Name
    InCollection = [bool]$hit
    Ok           = $true
    WantSha      = ''
    GotSha       = ''
    WantBytes    = [int64]0
    GotBytes     = [int64]0
    Path         = $Path
  }
  if (-not $hit) { return $row }
  $row.WantSha = $hit.Sha256
  $row.WantBytes = $hit.Bytes
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $row.Ok = $false
    return $row
  }
  $row.GotBytes = [int64](Get-Item -LiteralPath $Path).Length
  $row.GotSha = Get-CollectionPluginsSha256 $Path
  $row.Ok = ($row.GotSha -eq $row.WantSha)
  return $row
}

function Get-CollectionPluginProblems($Record, $Rows) {
  $col = $Record.Collection
  $rev = $Record.Revision
  foreach ($r in $Rows) {
    if ($null -eq $r) { continue }
    if ($r.InCollection -and -not $r.Ok) {
      $gotSha = $r.GotSha
      if (-not $gotSha) { $gotSha = 'missing' }
      '{0} from {1}: sha256 {2} ({3:N0} bytes), the collection''s ({4} rev {5}) is {6} ({7:N0} bytes)' -f `
        $r.Name, $r.Path, $gotSha, $r.GotBytes, $col, $rev, $r.WantSha, $r.WantBytes
    }
  }
}

function Get-CollectionPinnedMap($Record) {
  $map = [ordered]@{}
  foreach ($k in @($Record.Plugins.Keys | Sort-Object)) {
    $map[$k] = $Record.Plugins[$k].Sha256
  }
  return $map
}

function Get-CollectionOutsideNames([string[]]$PluginNames, $Record) {
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($n in @($PluginNames)) {
    if (-not (Get-CollectionRecordPlugin $Record.Plugins $n)) { [void]$out.Add($n) }
  }
  return $out.ToArray()
}

function Write-CollectionOutsideBlock($Record, [string[]]$Outside) {
  $n = @($Outside).Count
  Write-Host ('  outside the collection ({0} rev {1}), not held to it: {2}' -f $Record.Collection, $Record.Revision, $n) -ForegroundColor DarkGray
  if ($n) {
    Write-Host ('    ' + (@($Outside) -join ', ')) -ForegroundColor DarkGray
  }
}

function Confirm-CollectionPluginsRevisionTie($Record, [string]$DocsDir, [int]$InstalledRevision = 0) {
  $docRev = Get-CollectionPluginsDocRevision $DocsDir
  $why = New-Object System.Collections.Generic.List[string]
  if ($docRev -le 0) { [void]$why.Add('there is no docs/COLLECTION-REVISION-<N>.md to hold the record to') }
  elseif ($Record.Revision -ne $docRev) {
    [void]$why.Add(('record revision {0} is not the current docs/COLLECTION-REVISION-{1}.md' -f $Record.Revision, $docRev))
  }
  if ($InstalledRevision -gt 0 -and $Record.Revision -ne $InstalledRevision) {
    [void]$why.Add(('record revision {0} is not the installed collection revision {1}' -f $Record.Revision, $InstalledRevision))
  }
  return $why.ToArray()
}

function Confirm-CollectionPluginsDeploy($Record, [string]$DocsDir = '') {
  $why = New-Object System.Collections.Generic.List[string]
  if ($DocsDir) {
    foreach ($w in @(Confirm-CollectionPluginsRevisionTie $Record $DocsDir 0)) { [void]$why.Add($w) }
  }
  if (Get-Command Get-CollectionState -EA SilentlyContinue) {
    $url = 'https://www.nexusmods.com/games/skyrimspecialedition/collections/' + $Record.Collection
    $cs = $null
    try { $cs = Get-CollectionState $url } catch { $cs = $null }
    if ($cs -and $cs.Known -and [int]$cs.Have -gt 0 -and [int]$cs.Have -ne $Record.Revision) {
      [void]$why.Add(('this machine has collection revision {0} and the record is {1} ({2} rev {3})' -f $cs.Have, $Record.Revision, $Record.Collection, $Record.Revision))
    }
    if (Get-Command Get-CollectionInstalledFolder -EA SilentlyContinue) {
      $folder = $null
      try { $folder = Get-CollectionInstalledFolder $Record.Collection } catch { $folder = $null }
      $jsonPath = $null
      if ($folder) {
        if (Get-Command Get-CollectionJsonPath -EA SilentlyContinue) {
          try { $jsonPath = Get-CollectionJsonPath $folder.FullName } catch { $jsonPath = $null }
        }
        if (-not $jsonPath) { $jsonPath = Join-Path $folder.FullName 'collection.json' }
      }
      if ($jsonPath -and (Test-Path -LiteralPath $jsonPath -PathType Leaf)) {
        $got = Get-CollectionPluginsSha256 $jsonPath
        if ($got -ne $Record.CollectionJsonSha256) {
          [void]$why.Add(('installed collection.json sha256 {0} is not the record''s {1}' -f $got, $Record.CollectionJsonSha256))
        }
      }
    }
  }
  return $why.ToArray()
}

# Local plan for a deploy or a payload: hash every collection plugin on this
# machine, keep the name/size rule for plugins the record does not name, and
# say which collection plugins the box still needs.
function Get-CollectionPluginDeployPlan($Record, [string[]]$PluginNames, [hashtable]$LocalOf, $BoxRows) {
  $problems = New-Object System.Collections.Generic.List[object]
  $send = New-Object System.Collections.Generic.List[string]
  $changed = New-Object System.Collections.Generic.List[string]
  $outside = New-Object System.Collections.Generic.List[string]
  $box = @{}
  foreach ($row in @($BoxRows)) {
    $bits = ([string]$row).Trim() -split '\|'
    if ($bits.Count -lt 2) { continue }
    $name = $bits[0]
    if ($name -notmatch '\.es[pml]$') { continue }
    $len = 0L
    [void][int64]::TryParse($bits[1], [ref]$len)
    $sha = ''
    if ($bits.Count -ge 3) { $sha = $bits[2].ToLowerInvariant() }
    $box[$name] = [pscustomobject]@{ Name = $name; Length = $len; Sha256 = $sha }
  }
  foreach ($n in @($PluginNames)) {
    $local = $null
    if ($LocalOf -and $LocalOf.ContainsKey($n)) { $local = [string]$LocalOf[$n] }
    $check = Test-CollectionPluginFile $Record $n $local
    if ($check.InCollection) {
      if (-not $check.Ok) { [void]$problems.Add($check) }
      $there = $null
      foreach ($k in @($box.Keys)) {
        if ([string]::Equals($k, $n, [StringComparison]::OrdinalIgnoreCase)) { $there = $box[$k]; break }
      }
      if (-not $there) {
        if ($local -and (Test-Path -LiteralPath $local)) { [void]$send.Add($local) }
        else { [void]$problems.Add($check) }
      } elseif ($there.Sha256 -ne $check.WantSha) {
        if ($local -and (Test-Path -LiteralPath $local)) {
          [void]$send.Add($local)
          [void]$changed.Add(('{0}  sha256 {1} -> {2}' -f $n, $there.Sha256, $check.WantSha))
        }
      }
    } else {
      [void]$outside.Add($n)
      $there = $null
      foreach ($k in @($box.Keys)) {
        if ([string]::Equals($k, $n, [StringComparison]::OrdinalIgnoreCase)) { $there = $box[$k]; break }
      }
      if (-not $there) {
        if ($local -and (Test-Path -LiteralPath $local)) { [void]$send.Add($local) }
      } elseif ($local -and (Test-Path -LiteralPath $local)) {
        $localLen = [int64](Get-Item -LiteralPath $local).Length
        if ($localLen -ne $there.Length) {
          [void]$send.Add($local)
          [void]$changed.Add(('{0}  {1:N0} -> {2:N0} bytes' -f $n, $there.Length, $localLen))
        }
      }
    }
  }
  # .ToArray() rather than @(...): PowerShell throws "Argument types do
  # not match" when @() is wrapped round a List[object] of pscustomobjects
  # (same binder as Build-SpellTable.ps1).
  return [pscustomobject]@{
    Problems = $problems.ToArray()
    Send     = $send.ToArray()
    Changed  = $changed.ToArray()
    Outside  = $outside.ToArray()
  }
}

function New-CollectionPluginsRecordObject([string]$Collection, [int]$Revision, [string]$CollectionJsonSha256, $PluginRows) {
  $plugins = [ordered]@{}
  foreach ($n in @($PluginRows.Keys | Sort-Object)) {
    $r = $PluginRows[$n]
    $plugins[$n] = [ordered]@{
      bytes         = [int64]$r.Bytes
      sha256        = ([string]$r.Sha256).ToLowerInvariant()
      mod           = $r.Mod
      fileId        = $r.FileId
      archiveMd5    = ([string]$r.ArchiveMd5).ToLowerInvariant()
      archiveSha256 = ([string]$r.ArchiveSha256).ToLowerInvariant()
      archivePath   = [string]$r.ArchivePath
      via           = [string]$r.Via
    }
  }
  return [ordered]@{
    collection           = $Collection
    revision             = $Revision
    collectionJsonSha256 = $CollectionJsonSha256.ToLowerInvariant()
    generatedBy          = 'scripts/release/New-CollectionPluginsRecord.ps1'
    plugins              = $plugins
  }
}

function ConvertTo-CollectionPluginsJson($Object) {
  $j = $Object | ConvertTo-Json -Depth 8
  $j = $j -replace "`r`n", "`n"
  if (-not $j.EndsWith("`n")) { $j += "`n" }
  return $j
}

function Write-CollectionPluginsRecord([string]$Path, $Object) {
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $text = ConvertTo-CollectionPluginsJson $Object
  $utf8 = New-Object Text.UTF8Encoding $false
  [IO.File]::WriteAllText($Path, $text, $utf8)
}
