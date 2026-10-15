<#
  ServerArtifact.ps1

  The server build as a versioned artifact, kept in the box's store beside the
  gamemode artifacts. Issue #459.

      . (Join-Path $PSScriptRoot 'ServerArtifact.ps1')

  WHY. A server deploy sent the fork's build straight out of one machine's
  engine build folder, and the box kept no copy of it by name: the installed
  folder and the two folders before it, then nothing. So which engine build a
  server ran could be read off its server-build.json, but those bytes could
  not be fetched again, sent to the other server, or put back once the
  folders before it had rolled off. The gamemode has been an artifact with a
  name since #1090; the server build was the half without one.

  THE ARTIFACT. Exactly the files records\server-build.json lists (the binary,
  the JavaScript half and its map, package.json, yarn.lock, launch_server.bat
  and the compiled Papyrus; ServerBuild.ps1 says which), each held to its
  sha256 in the record as it is read, and the record itself as
  server-build.json, in one stored zip written the way Artifact.ps1 writes
  every artifact (entries in ordinal order, every date 2000-01-01), named

      server-<fork commit, 12>-<sha256 of the zip, 16>.zip

  The record goes in with each CR LF read as LF, the way ServerBuild.ps1 sums
  it, so a checkout with core.autocrlf and one without make the same bytes:
  the same record and the same build give the same name on any machine.
  Beside it, <same name>.json: component server, the fork commit, the zip's
  sha256 and size, recordSha256 (Get-ThornswoodRecordSum of the record), and
  every file with its size and sha256. Nothing in the server folder that is
  not the fork's build goes in: not the gamemode, the settings, the stamp or
  the plugins, which a deploy sends on their own.

  -From is an engine build's dist\server (Deploy-Server.ps1) or a payload zip
  (Publish-Server.ps1, which keeps the files it installed, read out of the zip
  it sent). Either way a file the record does not name the way it is there,
  or a server file it does not list, refuses the artifact and nothing is
  written.

  The store keeps it at C:\Thornswood-Deploys\server\<name>.zip and .json,
  sent by Send-ThornswoodArtifact (Artifact.ps1), which checks the bytes on
  the box. tests\test-459-server-artifact.ps1.
#>

. (Join-Path $PSScriptRoot 'Artifact.ps1')
. (Join-Path $PSScriptRoot 'ServerBuild.ps1')

# The bytes of every server file in a folder or a payload zip, rel -> byte[],
# only the files ServerBuild.ps1 counts as the fork's build.
function Read-ThornswoodServerFiles([string]$From) {
  $out = @{}
  if (Test-Path -LiteralPath $From -PathType Container) {
    $full = (Get-Item -LiteralPath $From).FullName.TrimEnd('\')
    foreach ($f in @(Get-ChildItem -LiteralPath $full -Recurse -File -Force)) {
      $rel = ConvertTo-ThornswoodServerRel ($f.FullName.Substring($full.Length))
      if (Test-ThornswoodServerForkFile $rel) { $out[$rel] = [IO.File]::ReadAllBytes($f.FullName) }
    }
    return $out
  }
  if (-not (Test-Path -LiteralPath $From -PathType Leaf)) { throw "there is no server build at $From. Nothing was built." }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $za = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $From).ProviderPath)
  try {
    foreach ($ze in $za.Entries) {
      if (-not $ze.Name) { continue }
      # Compress-Archive under Windows PowerShell 5.1 writes \, under 7 /.
      $rel = ConvertTo-ThornswoodServerRel $ze.FullName
      if (-not (Test-ThornswoodServerForkFile $rel)) { continue }
      $ms = New-Object IO.MemoryStream
      $zs = $ze.Open()
      try { $zs.CopyTo($ms) } finally { $zs.Dispose() }
      $out[$rel] = $ms.ToArray()
    }
  } finally { $za.Dispose() }
  return $out
}

function New-ThornswoodServerBuildArtifact {
  param(
    [Parameter(Mandatory = $true)][string]$From,
    [Parameter(Mandatory = $true)][string]$Record,
    [string]$OutDir = ''
  )
  Initialize-ThornswoodArtifactType
  if (-not (Test-Path -LiteralPath $Record -PathType Leaf)) {
    throw "there is no build record at $Record, so nothing says which server build to keep. Nothing was built."
  }
  $raw = [IO.File]::ReadAllBytes($Record)
  $l1 = [Text.Encoding]::GetEncoding(28591)
  [byte[]]$recBytes = $l1.GetBytes($l1.GetString($raw).Replace("`r`n", "`n"))
  $rec = $null
  try { $rec = ([Text.Encoding]::UTF8.GetString($recBytes) -replace '^\uFEFF', '') | ConvertFrom-Json } catch { $rec = $null }
  if ($null -eq $rec) { throw "$Record does not parse, so nothing says which server build to keep. Nothing was built." }
  $commit = ([string](Get-ThornswoodServerRecordValue (Get-ThornswoodServerRecordValue $rec 'source') 'commit')).ToLowerInvariant()
  if ($commit -notmatch '^[0-9a-f]{40}$') { throw "$Record names no fork commit (source.commit), so the server build cannot be named. Nothing was built." }

  # Held to the record on the bytes that go in, not a read before them.
  $bytes = Read-ThornswoodServerFiles $From
  $sums = @{}
  foreach ($k in @($bytes.Keys)) { $sums[$k] = Get-ThornswoodSha256Hex $bytes[$k] }
  $why = @(Get-ThornswoodServerBuildProblems $rec $sums $From $Record)
  if ($why.Count) {
    throw ('the server files in ' + $From + ' are not the build ' + $Record + ' names: ' + ($why -join '; ') + '. Nothing was built.')
  }

  if (-not $OutDir) {
    $where = Join-Path $PSScriptRoot '..\release\Where.ps1'
    $OutDir = Join-Path (Join-Path (& $where Out) 'deploys') 'server'
  }
  if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
  $OutDir = (Resolve-Path -LiteralPath $OutDir).ProviderPath

  [string[]]$names = @(@((Get-ThornswoodServerRecordFiles $rec).Keys) + @('server-build.json'))
  [Array]::Sort($names, [StringComparer]::Ordinal)
  $datas = New-Object 'byte[][]' $names.Count
  for ($i = 0; $i -lt $names.Count; $i++) {
    if ($names[$i] -eq 'server-build.json') { $datas[$i] = $recBytes } else { $datas[$i] = $bytes[$names[$i]] }
  }

  $building = Join-Path $OutDir ('.building-' + [Guid]::NewGuid().ToString('N') + '.zip')
  [ThornswoodArtifactZip]::WriteStored($building, $names, $datas)
  $sha = (Get-FileHash -LiteralPath $building -Algorithm SHA256).Hash.ToLowerInvariant()
  $short = $commit.Substring(0, 12)
  $name = 'server-' + $short + '-' + $sha.Substring(0, 16) + '.zip'
  $zip = Join-Path $OutDir $name
  if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $building -Force }
  else { Move-Item -LiteralPath $building -Destination $zip }

  $contents = @()
  for ($i = 0; $i -lt $names.Count; $i++) {
    $contents += [ordered]@{ path = $names[$i]; size = $datas[$i].Length; sha256 = (Get-ThornswoodSha256Hex $datas[$i]) }
  }
  # Not $record: PowerShell names are case blind, and $Record is the path.
  $meta = [ordered]@{
    component    = 'server'
    name         = $name
    commit       = $commit
    sha256       = $sha
    size         = (Get-Item -LiteralPath $zip).Length
    recordSha256 = (Get-ThornswoodRecordSum $raw)
    files        = $contents
  }
  $recordPath = [IO.Path]::ChangeExtension($zip, '.json')
  [IO.File]::WriteAllText($recordPath, (ConvertTo-Json -InputObject $meta -Depth 5), (New-Object Text.UTF8Encoding($false)))

  return [pscustomobject]@{
    Component  = 'server'
    Name       = $name
    Zip        = $zip
    RecordPath = $recordPath
    Record     = $meta
    Folder     = ''
    Commit     = $commit
    Short      = $short
    Sha256     = $sha
    Size       = $meta.size
  }
}
