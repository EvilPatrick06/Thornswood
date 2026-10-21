<#
  New-NexusRevision.ps1

  Makes the next revision of the Thornswood collection on Nexus Mods (slug
  7essxf), as a draft, from the revision published now with one or more of its
  mods moved to a new Nexus file; and publishes a draft once it has been
  checked (#2914).

      .\scripts\release\New-NexusRevision.ps1 -Mod 192762 -FileId <new file id> -Archive <the archive uploaded> -WhatIf
      .\scripts\release\New-NexusRevision.ps1 -Mod 192762 -FileId <new file id> -Archive <the archive uploaded>
      .\scripts\release\New-NexusRevision.ps1 -Publish 3 -WhatIf
      .\scripts\release\New-NexusRevision.ps1 -Publish 3

  WHY. Until 20 October every revision was made by Patrick in Vortex and
  published on the website. The commonest one is a new file of our own mod,
  above all the Client Runtime, whose entry is only a file id, a version, an
  md5, a size and a name. This makes that revision with his API key (Nexus.ps1
  says where it is read from), the way Vortex makes one, so the release desk
  can run it.

  HOW VORTEX MAKES A REVISION, read in Nexus-Mods/Vortex at 2e29b16d on
  20 October (collectionExport.ts, submitCollectionV3.ts, manifestMapping.ts):
  it writes collection.json from what is installed, copies the collection's
  INI Tweaks, bundled and patches folders beside it, packs them as
  collection_<n>.7z with 7-Zip, uploads that (the same upload as a mod file),
  and sends POST /v3/collections/<id>/revisions with the upload's id and
  collection_data, the manifest mapped from collection.json. The revision is a
  draft until it is published, which v3 has no operation for; the v2 GraphQL
  mutation publishRevision(revisionId: ID!) does it (read from the live
  schema on 20 October).

  WHAT THIS DOES DIFFERENTLY, on purpose. It does not rebuild collection.json
  from an installed game, because that is Vortex's own work from its state on
  One (mods, installer choices, file hashes, patches, plugin rules). It starts
  from the archive of the revision that is published now, downloaded from
  Nexus (the GraphQL collectionRevision's downloadLink), the same archive
  Vortex keeps in its downloads when it installs the collection; so it runs
  the same from One or a cloud session (#2969). It changes only the entries
  named, and packs the rest exactly as it was. So:
    - it checks the archive is the latest published revision, and that no
      draft is waiting, before anything else;
    - it refuses an entry whose new file would need anything worked out from
      the archive's contents (hashes, installer choices, patches, file
      overrides) or that a mod rule names by its old archive, which today is
      Thornswood Content (it carries a patch and a rule). Those revisions are
      still made in Vortex on One;
    - for each entry it reads the new file from Nexus (the file id has to be
      a live version of that mod) and takes the md5 and size from the archive
      that was uploaded, as Vortex does from the archive it downloaded;
    - nexus-collection.js writes the new collection.json the way Vortex does
      and the collection_data with Vortex's own mapping, ported line for line;
    - the new archive is checked to hold the same files and folders as the
      published one before it goes up. Vortex skips one step here: it renames
      the collection to its own name first (PATCH /v3/collections/<id>). The
      name does not change in a revision made this way, so that write is left
      out.

  Nothing in this checks the game. A new Client Runtime is checked on Dev
  before the draft is published (docs\COLLECTION-REVISION-2.md, steps 8 to
  14, and #2754 and #2903 for running those off One).

  -WhatIf does every read, builds the new archive in the scratch folder
  (Get-ScratchDir.ps1 nexus-revision-<slug>), prints every change and the
  writes it would make, and sends nothing.

  Only tested against the stand-in in tests\test-2914-nexus-scripts.ps1 until
  its first real run.

.PARAMETER Mod
  The mods to move to a new file, by their numbers on the website, in the same
  order as -FileId and -Archive.

.PARAMETER FileId
  Each mod's new file id, the number Send-NexusFile.ps1 printed.

.PARAMETER Archive
  Each mod's archive, the one that was uploaded as that file id.

.PARAMETER From
  The published revision to start from: its .7z, or a folder holding it
  unpacked. Downloaded from Nexus unless said otherwise.

.PARAMETER BaseRevision
  The revision number -From is, when its name does not say.

.PARAMETER Slug
  The collection. 7essxf, the only one Thornswood has, unless said otherwise.

.PARAMETER Game
  The game's domain on Nexus. skyrimspecialedition unless said otherwise.

.PARAMETER Publish
  Publishes this revision number, which has to be the draft. Nothing else is
  done in that run.

.PARAMETER WaitSeconds
  How long to wait for Nexus to process the upload. 600 unless said otherwise.

.PARAMETER WhatIf
  Reads everything, builds the archive locally and says each write it would
  make. Writes nothing to Nexus.

.PARAMETER NoPause
  Does not wait for Enter at the end or on a stop.
#>
[CmdletBinding()]
param(
  [string[]]$Mod = @(),
  [string[]]$FileId = @(),
  [string[]]$Archive = @(),
  [string]$From,
  [int]$BaseRevision = 0,
  [string]$Slug = '7essxf',
  [string]$Game = 'skyrimspecialedition',
  [int]$Publish = 0,
  [int]$WaitSeconds = 600,
  [switch]$WhatIf,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Nexus.ps1')

$script:Done = New-Object System.Collections.Generic.List[string]
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) {
  Write-Host ''
  Write-Host "STOP. $m" -ForegroundColor Red
  if ($script:Done.Count) { Write-Host ('On Nexus from this run: ' + ($script:Done -join '; ') + '.') -ForegroundColor Yellow }
  else { Write-Host 'Nothing was changed on Nexus.' -ForegroundColor Yellow }
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}
function Step([scriptblock]$b) { try { return (& $b) } catch { Die $_.Exception.Message } }

# A program run with its output kept apart from its errors, the same in
# Windows PowerShell 5.1 (where a redirected error line would stop the
# script) and in pwsh 7.
function Invoke-Tool([string]$exe, [string[]]$arguments, [string]$cwd = '') {
  $q = @($arguments | ForEach-Object { '"' + (($_ -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' })
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $exe; $psi.Arguments = ($q -join ' ')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  if ($cwd) { $psi.WorkingDirectory = $cwd }
  $p = [Diagnostics.Process]::Start($psi)
  $err = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd()
  $p.WaitForExit()
  return [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $err.Result }
}

function Find-SevenZip {
  $c = @()
  if ($env:ProgramFiles) { $c += (Join-Path $env:ProgramFiles '7-Zip\7z.exe') }
  foreach ($p in $c) { if (Test-Path -LiteralPath $p) { return $p } }
  foreach ($n in '7z', '7zz', '7za') { $g = Get-Command $n -ErrorAction SilentlyContinue; if ($g) { return $g.Source } }
  return ''
}

# Every path in a 7z archive, as 7-Zip lists it, with \ between folders.
function Get-ArchivePaths([string]$sz, [string]$archive) {
  $r = Invoke-Tool $sz @('l', '-slt', $archive)
  if ($r.Code -ne 0) { throw ('7-Zip could not list ' + $archive + ': ' + $r.Err.Trim()) }
  $after = $false
  $paths = New-Object System.Collections.Generic.List[string]
  foreach ($line in ($r.Out -split "`r?`n")) {
    if ($line -eq '----------') { $after = $true; continue }
    if ($after -and $line.StartsWith('Path = ')) { $paths.Add($line.Substring(7).Replace('/', '\')) }
  }
  return @($paths | Sort-Object)
}

Write-Host ''
Write-Host '  THORNSWOOD  -  a revision of the collection on Nexus Mods' -ForegroundColor White
if ($WhatIf) { Say '  -WhatIf: reads only, and says what it would write.' 'Yellow' }
if ($Slug -notmatch '^[a-z0-9]+$') { Die ('-Slug ' + $Slug + ' is not a collection slug.') }
if ($Game -notmatch '^[a-z0-9]+$') { Die ('-Game ' + $Game + ' is not a game domain.') }
[void](Step { Read-NexusKey })
Say ('  key from ' + $script:NexusKeyFrom) 'DarkGray'

$q = '{ collection(slug: "' + $Slug + '", domainName: "' + $Game + '") { id name latestPublishedRevision { id revisionNumber } draftRevisionNumber } }'
$col = Get-NexusField (Step { Invoke-NexusGraph $q $null ('Reading collection ' + $Slug) }) 'collection'
$colId = [string](Get-NexusField $col 'id')
if (-not $colId) { Die ('Nexus has no collection ' + $Slug + ' on ' + $Game + '.') }
$latest = [int](Get-NexusField (Get-NexusField $col 'latestPublishedRevision') 'revisionNumber')
$draft = Get-NexusField $col 'draftRevisionNumber'
Head ('Collection ' + $Slug)
Say ('  "' + (Get-NexusField $col 'name') + '", id ' + $colId + ', revision ' + $latest + ' published' + $(if ($draft) { ', revision ' + $draft + ' a draft' } else { ', no draft' }))

# --------------------------------------------------------------- publish ---
if ($Publish) {
  if ($Mod.Count -or $FileId.Count -or $Archive.Count -or $From) { Die '-Publish publishes a draft that is already there, so it takes no -Mod, -FileId, -Archive or -From.' }
  $rq = '{ collectionRevision(slug: "' + $Slug + '", revision: ' + $Publish + ', domainName: "' + $Game + '") { id revisionNumber status } }'
  $rev = Get-NexusField (Step { Invoke-NexusGraph $rq $null ('Reading revision ' + $Publish) }) 'collectionRevision'
  $revId = [string](Get-NexusField $rev 'id')
  $status = [string](Get-NexusField $rev 'status')
  if (-not $revId) { Die ('Nexus has no revision ' + $Publish + ' of ' + $Slug + '.') }
  Say ('  revision ' + $Publish + ' is ' + $status + ' (id ' + $revId + ')')
  if ($status -ne 'draft') { Die ('Revision ' + $Publish + ' is ' + $status + ', not a draft, so there is nothing to publish.') }
  if ($Publish -le $latest) { Die ('Revision ' + $Publish + ' is not after the published revision ' + $latest + '.') }
  $mut = 'mutation publishRevision($revisionId: ID!) { publishRevision(revisionId: $revisionId) { success } }'
  if ($WhatIf) {
    Say ('  would send the GraphQL mutation publishRevision(revisionId: "' + $revId + '")') 'Yellow'
    Write-Host ''; Say 'Nothing was written.' 'Green'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
  }
  $res = Step { Invoke-NexusGraph $mut ([ordered]@{ revisionId = $revId }) ('Publishing revision ' + $Publish) }
  if ((Get-NexusField (Get-NexusField $res 'publishRevision') 'success') -ne $true) { Die ('Nexus answered the publish of revision ' + $Publish + ' without saying it succeeded. Look at the collection''s page before running this again.') }
  $script:Done.Add('revision ' + $Publish + ' published')
  $now = Get-NexusField (Step { Invoke-NexusGraph $q $null ('Reading collection ' + $Slug + ' again') }) 'collection'
  $nowLatest = [int](Get-NexusField (Get-NexusField $now 'latestPublishedRevision') 'revisionNumber')
  if ($nowLatest -ne $Publish) { Die ('Nexus said the publish succeeded, but the latest published revision still reads as ' + $nowLatest + '.') }
  Write-Host ''
  Say ('Revision ' + $Publish + ' is published: https://www.nexusmods.com/games/' + $Game + '/collections/' + $Slug) 'Green'
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

# ------------------------------------------------------- refused up front ---
if (-not $Mod.Count) { Die 'Say which mods move to a new file with -Mod, -FileId and -Archive, or publish a draft with -Publish.' }
$Mod = @($Mod | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$FileId = @($FileId | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Mod.Count -ne $FileId.Count -or $Mod.Count -ne $Archive.Count) { Die ('-Mod, -FileId and -Archive go together, one of each for every mod: ' + $Mod.Count + ', ' + $FileId.Count + ' and ' + $Archive.Count + ' were given.') }
for ($i = 0; $i -lt $Mod.Count; $i++) {
  if ($Mod[$i] -notmatch '^\d+$') { Die ('-Mod ' + $Mod[$i] + ' is not a mod number.') }
  if ($FileId[$i] -notmatch '^\d+$') { Die ('-FileId ' + $FileId[$i] + ' is not a file id.') }
}
if ($draft) { Die ('Revision ' + $draft + ' is already a draft on Nexus. Publish it with -Publish ' + $draft + ', or discard it on the website, before making another.') }
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Die 'node is not on this machine, and nexus-collection.js writes collection.json the way Vortex does.' }
$sz = Find-SevenZip
if (-not $sz) { Die '7-Zip is not on this machine (7z.exe in Program Files, or 7z, 7zz or 7za on PATH), and the collection is a 7z archive.' }

$scratch = & (Join-Path $Here 'Get-ScratchDir.ps1') ('nexus-revision-' + $Slug)
if (-not $From) {
  $rq = '{ collectionRevision(slug: "' + $Slug + '", revision: ' + $latest + ', domainName: "' + $Game + '") { id status downloadLink } }'
  $rev = Get-NexusField (Step { Invoke-NexusGraph $rq $null ('Reading revision ' + $latest) }) 'collectionRevision'
  $link = [string](Get-NexusField $rev 'downloadLink')
  if ([string](Get-NexusField $rev 'status') -ne 'published' -or $link -notmatch '^/v2/collections/\d+/revisions/\d+/download_link$') { Die ('Nexus gave revision ' + $latest + ' as ' + [string](Get-NexusField $rev 'status') + ' with the download link "' + $link + '", not a published revision''s API path, so it was not downloaded.') }
  $links = @(Get-NexusField (Step { Invoke-NexusApi 'GET' $link '' ('Asking for revision ' + $latest + '''s download') }) 'download_links')
  $uri = [string](Get-NexusField ($links | Select-Object -First 1) 'URI')
  if (-not $uri) { Die ('Nexus gave no download address for revision ' + $latest + '.') }
  $pub = Join-Path $scratch 'published'
  if (Test-Path -LiteralPath $pub) { Remove-Item -LiteralPath $pub -Recurse -Force }
  $got = Step { Receive-NexusPresigned $uri $pub ('Downloading revision ' + $latest) ('collection_' + $Slug + '_' + $latest + '_.7z') }
  $From = $got.Path
  $BaseRevision = $latest
}
if (-not (Test-Path -LiteralPath $From)) { Die ('There is nothing at ' + $From + '.') }
if (-not $BaseRevision) {
  $bm = [regex]::Match((Split-Path -Leaf $From), ('^collection_' + $Slug + '_(\d+)_'))
  if (-not $bm.Success) { Die ((Split-Path -Leaf $From) + ' does not say which revision it is; say it with -BaseRevision.') }
  $BaseRevision = [int]$bm.Groups[1].Value
}
Head 'The revision it starts from'
Say ('  ' + $From)
if ($BaseRevision -ne $latest) { Die ('That is revision ' + $BaseRevision + ', but Nexus''s latest published revision is ' + $latest + '. Start from revision ' + $latest + ' (leave -From off and it is downloaded from Nexus).') }
Say ('  revision ' + $BaseRevision + ', the latest published') 'Green'

$base = Join-Path $scratch 'base'; $build = Join-Path $scratch 'build'; $outDir = Join-Path $scratch 'out'
foreach ($d in $base, $build, $outDir) {
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
}
$isArchive = Test-Path -LiteralPath $From -PathType Leaf
if ($isArchive) {
  $r = Invoke-Tool $sz @('x', '-y', ('-o' + $base), $From)
  if ($r.Code -ne 0) { Die ('7-Zip could not unpack ' + $From + ': ' + $r.Err.Trim()) }
  $basePaths = @(Step { Get-ArchivePaths $sz $From })
}
else {
  Copy-Item -Path (Join-Path $From '*') -Destination $base -Recurse -Force
  $basePaths = @(Get-ChildItem -LiteralPath $base -Recurse -Force | ForEach-Object { $_.FullName.Substring($base.Length + 1).Replace('/', '\') } | Sort-Object)
}
$baseJson = Join-Path $base 'collection.json'
if (-not (Test-Path -LiteralPath $baseJson)) { Die ($From + ' has no collection.json at its top, so it is not a collection Vortex made.') }
Say ('  ' + $basePaths.Count + ' files and folders in it')

# ------------------------------------------------------------- the swaps ---
Head 'The new files'
$swaps = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $Mod.Count; $i++) {
  $m = $Mod[$i]; $fid = $FileId[$i]
  $info = Step { Get-NexusField (Invoke-NexusApi 'GET' ('/v3/games/' + $Game + '/mods/' + $m) '' ('Reading mod ' + $m)) 'data' }
  $uid = [string](Get-NexusField $info 'id')
  $v = Step { Get-NexusField (Invoke-NexusApi 'GET' ('/v3/games/' + $Game + '/mod-file-versions/' + $fid) '' ('Reading file id ' + $fid)) 'data' }
  $vFile = [string](Get-NexusField (Get-NexusField $v 'file') 'id')
  $files = @(@(Get-NexusField (Get-NexusField (Step { Invoke-NexusApi 'GET' ('/v3/mods/' + $uid + '/files') '' ('Reading the files of mod ' + $m) }) 'data') 'mod_files') | Where-Object { $_ })
  if (-not @($files | Where-Object { [string](Get-NexusField $_ 'id') -eq $vFile }).Count) { Die ('File id ' + $fid + ' is not a file of mod ' + $m + '.') }
  $cat = [string](Get-NexusField $v 'category')
  if (@('main', 'update', 'optional', 'miscellaneous') -notcontains $cat) { Die ('File id ' + $fid + ' of mod ' + $m + ' is ' + $cat + ', not a file people can download now.') }
  $facts = Step { Get-NexusArchiveFacts $Archive[$i] }
  Say ('  mod ' + $m + ' (' + (Get-NexusField $info 'name') + '): file id ' + $fid + ', "' + (Get-NexusField $v 'name') + '" ' + (Get-NexusField $v 'version') + ', ' + $cat)
  Say ('    ' + $facts.Name + ', ' + $facts.Size.ToString('N0') + ' bytes, md5 ' + $facts.Md5Hex) 'DarkGray'
  $swaps.Add([ordered]@{ modId = $m; fileId = $fid; version = [string](Get-NexusField $v 'version'); md5 = $facts.Md5Hex; fileSize = $facts.Size; logicalFilename = [string](Get-NexusField $v 'name') })
}

# --------------------------------------------------------- the new archive ---
Head 'The new revision'
Copy-Item -Path (Join-Path $base '*') -Destination $build -Recurse -Force
$swapsJson = Join-Path $scratch 'swaps.json'
$payloadJson = Join-Path $scratch 'payload.json'
[IO.File]::WriteAllText($swapsJson, (ConvertTo-Json -InputObject @($swaps.ToArray()) -Depth 4), (New-Object Text.UTF8Encoding($false)))
$r = Invoke-Tool $node.Source @((Join-Path $Here 'nexus-collection.js'), $baseJson, $swapsJson, (Join-Path $build 'collection.json'), $payloadJson)
if ($r.Code -ne 0) { Die ($r.Err.Trim() + ' Nothing was built.') }
foreach ($line in ($r.Out -split "`r?`n" | Where-Object { $_ })) {
  $c = $line.Split("`t")
  Say ('  ' + $c[0] + ', ' + $c[1] + ': ' + $c[2] + ' -> ' + $c[3])
}
$newRev = $latest + 1
$out = Join-Path $outDir ('collection_' + $newRev + '.7z')
$tops = @(Get-ChildItem -LiteralPath $build -Force | ForEach-Object { $_.Name })
$r = Invoke-Tool $sz (@('a', '-t7z', '-y', $out) + $tops) $build
if ($r.Code -ne 0) { Die ('7-Zip could not pack the new revision: ' + $r.Err.Trim()) }
$newPaths = @(Step { Get-ArchivePaths $sz $out })
$gone = @($basePaths | Where-Object { $newPaths -notcontains $_ })
$extra = @($newPaths | Where-Object { $basePaths -notcontains $_ })
if ($gone.Count -or $extra.Count) { Die ('The new archive does not hold the same files and folders as revision ' + $latest + ' (missing: ' + ($gone -join ', ') + '; extra: ' + ($extra -join ', ') + '). Nothing was sent.') }
$facts = Step { Get-NexusArchiveFacts $out }
Say ('  ' + $out)
Say ('  ' + $facts.Size.ToString('N0') + ' bytes, md5 ' + $facts.Md5Hex + ', the same ' + $newPaths.Count + ' files and folders as revision ' + $latest)
$payloadText = ([IO.File]::ReadAllText($payloadJson)).Trim()

if ($WhatIf) {
  Head 'What it would write'
  Say ('  POST /v3/uploads  {"size_bytes":' + $facts.Size + ',"filename":"' + $facts.Name + '","md5":"' + $facts.Md5Hex + '"}, the archive to the address it gives, finalise, wait until available')
  Say ('  POST /v3/collections/' + $colId + '/revisions  {"upload_id":"<that upload>","collection_data":<' + $payloadText.Length + ' characters, in ' + $payloadJson + '>}')
  Say ('  which makes revision ' + $newRev + ' a draft; publishing it is a separate run with -Publish ' + $newRev)
  Write-Host ''
  Say 'Nothing was written to Nexus.' 'Green'
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

Head 'Uploading'
$said = { param($line) Say ('  ' + $line) }
$up = Step { Send-NexusUpload $facts $said $WaitSeconds }
$script:Done.Add('upload ' + $up + ' is processed and available, attached to nothing')
$body = '{"upload_id":' + (ConvertTo-Json $up) + ',"collection_data":' + $payloadText + '}'
$made = Get-NexusField (Step { Invoke-NexusApi 'POST' ('/v3/collections/' + $colId + '/revisions') $body ('Making revision ' + $newRev) }) 'data'
$script:Done.Clear()
$num = Get-NexusField $made 'revision_number'
$script:Done.Add('revision ' + $num + ' made as ' + (Get-NexusField $made 'revision_status') + ' (id ' + (Get-NexusField $made 'id') + ')')
Head 'Done'
Say ('  revision ' + $num + ', ' + (Get-NexusField $made 'revision_status') + ', id ' + (Get-NexusField $made 'id')) 'Green'
if ([string]$num -ne [string]$newRev) { Say ('  Nexus numbered it ' + $num + ', not ' + $newRev + ' as expected; publish it by the number Nexus gave.') 'Yellow' }
Say ('  Check it on Dev, then publish it: .\scripts\release\New-NexusRevision.ps1 -Publish ' + $num)
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
exit 0
