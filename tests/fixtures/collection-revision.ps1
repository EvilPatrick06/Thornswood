<#
  tests\fixtures\collection-revision.ps1

  A release names records\collection-plugins.json's collection revision and
  stops unless the machine it is built on has that revision installed (#3597).
  A harness that runs the real Publish-Update.ps1 gives it both:

      . (Join-Path $repo 'tests\fixtures\collection-revision.ps1')
      Install-CollectionRevisionFixture -From $repo -RepoCopy $fake -AppData $roaming
      $env:APPDATA = $roaming   # around the child it starts

  The record is the committed one, copied into the harness's repository. The
  installed revision is the legacy Vortex folder LoadOrder.ps1 still reads
  (collection_<slug>_<rev>_<when>), under an APPDATA of the harness's own, so
  no harness reads the Vortex of the machine it runs on. -Revision puts
  another revision there, for a harness that wants a machine behind.

  The record also has to be the newest revision published on Nexus (#4068),
  which scripts\release\NexusPublished.ps1 asks Nexus. The copy gets a
  NexusPublished.ps1 of its own in its place, saying the record's revision,
  or -Published's, so no harness asks Nexus.
  Returns the record's revision.
#>
function Install-CollectionRevisionFixture([string]$From, [string]$RepoCopy, [string]$AppData, [int]$Revision = 0, [int]$Published = 0) {
    $src = Join-Path (Join-Path $From 'records') 'collection-plugins.json'
    $dstDir = Join-Path $RepoCopy 'records'
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    Copy-Item -LiteralPath $src -Destination (Join-Path $dstDir 'collection-plugins.json') -Force
    $doc = ([IO.File]::ReadAllText($src) -replace ('^' + [char]0xFEFF), '') | ConvertFrom-Json
    $rev = if ($Revision -gt 0) { $Revision } else { [int]$doc.revision }
    $mods = Join-Path (Join-Path (Join-Path $AppData 'Vortex') 'skyrimse') 'mods'
    New-Item -ItemType Directory -Force -Path (Join-Path $mods ('collection_' + [string]$doc.collection + '_' + $rev + '_2026-10-27T00-00-00Z')) | Out-Null
    $pub = if ($Published -gt 0) { $Published } else { [int]$doc.revision }
    $rel = Join-Path (Join-Path $RepoCopy 'scripts') 'release'
    New-Item -ItemType Directory -Force -Path $rel | Out-Null
    [IO.File]::WriteAllText((Join-Path $rel 'NexusPublished.ps1'), ("param([string]`$Slug, [string]`$Game)`r`nreturn " + $pub + "`r`n"), (New-Object Text.UTF8Encoding($false)))
    return [int]$doc.revision
}
