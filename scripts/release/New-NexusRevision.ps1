<#
  New-NexusRevision.ps1

  Makes the next revision of the Thornswood collection on Nexus Mods (slug
  7essxf), as a draft, from the revision published now with one or more of its
  mods moved to a new Nexus file; and publishes a draft once it has been
  checked (#2914).

      .\scripts\release\New-NexusRevision.ps1 -Mod 192762 -FileId <new file id> -Archive <the archive uploaded> -WhatIf
      .\scripts\release\New-NexusRevision.ps1 -Mod 192762 -FileId <new file id> -Archive <the archive uploaded>
      .\scripts\release\New-NexusRevision.ps1 -Add <mods to add>.json -WhatIf
      pwsh scripts/release/New-NexusRevision.ps1 -SetLight RaceMenu.esp,XPMSE.esp -Layout <the -Record folder> -WhatIf
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

  ADDING A MOD (#2969). -Add names a JSON file of mods the revision does not
  carry yet, each a Nexus file put in with Vortex's basic installer:
      [{ "modId": 1932, "fileId": 8662, "archive": "<the downloaded archive>",
         "plugins": [{ "name": "KS_Hairdo's_Lite_NoNPCs.esp",
                       "after": ["Playable Rieklings.esp"] }] }]
  The mod's name, author and category and the file's name and version are
  read from Nexus, the md5 and size from the archive, and the archive's own
  plugins have to be the ones "plugins" names. An archive with a FOMOD
  installer is refused: its answers are Vortex's to work out. Each plugin goes
  on the end of the plugin list after the plugins its "after" names
  (docs\LIGHT-ORDER-DRIFT.md: a new plugin goes on the end of its own kind,
  never mid-order). Install-NexusRevision.ps1 -CollectionArchive lays the new
  archive out to check it, from One or a cloud session.

  A DRAFT WAITING. Nexus keeps one draft at a time, so a real run refuses
  while there is one. -WhatIf builds on the draft instead, so the revision
  after it can be laid out and checked while the draft waits.

  LIGHT FLAGS (#2979). -SetLight and -ClearLight name plugins whose ESL flag
  (0x200 in the TES4 header) the revision sets or clears, the way the
  collection already sets FNIS.esp's: a binary patch on the entry that
  installs the plugin, patches\<entry name>\<plugin>.diff, with the CRC-32 of
  the archive's own file under the entry's "patches". Vortex applies it after
  it installs the mod (collections/util/binaryPatching.ts), and
  Install-NexusRevision.ps1 does the same.
  Why: until 20 October the flag was set on the Plugins page in Vortex on One,
  which writes it into Vortex's copy of the file and nowhere else. On 26
  September eight plugins were marked light there and CBBE.esp unmarked, and
  the collection was made from that install with no patch for any of them, so
  One and the servers had the edited bytes and every other install had the
  archives' (#2979).
  -Layout is the folder Install-NexusRevision.ps1 -Record wrote for the
  revision this starts from. Its files.txt says which Nexus file puts each
  plugin in Data and what its bytes are; the archive is downloaded, held to
  the revision's md5 and size, and the plugin is found in it by that sha256.
  Each patch is read back and applied before it is packed, and the plugin it
  makes is compared with records\collection-plugins.json, the bytes One
  deploys. Lay the new archive out with Install-NexusRevision.ps1
  -CollectionArchive ... -Record to check it end to end.

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

.PARAMETER Add
  A JSON file of mods to add, as ADDING A MOD above says.

.PARAMETER SetLight
  Plugins the revision gives the ESL flag, as LIGHT FLAGS above says.

.PARAMETER ClearLight
  Plugins the revision takes the ESL flag off.

.PARAMETER Layout
  The -Record folder of the revision this starts from, for -SetLight and
  -ClearLight.

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
  [string]$Add,
  [string[]]$SetLight = @(),
  [string[]]$ClearLight = @(),
  [string]$Layout,
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
. (Join-Path $Here 'Read-JsonFile.ps1')   # ConvertFrom-ThornswoodJson: a bad JSON file named

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

# BSDIFF40, the patch format Vortex's binaryPatching applies (bsdiff 4): a 32
# byte header of the magic, the control block's length, the diff block's and
# the new file's size, each a sign-magnitude int64, then the three blocks,
# each bzip2. 7-Zip packs and unpacks the blocks, as Install-NexusRevision.ps1
# does, because neither PowerShell has bzip2.
function ConvertTo-OffT([long]$v) {
  $m = [Math]::Abs($v); $b = New-Object byte[] 8
  for ($i = 0; $i -lt 8; $i++) { $b[$i] = [byte]($m -band 0xFF); $m = $m -shr 8 }
  if ($v -lt 0) { $b[7] = $b[7] -bor 0x80 }
  return , $b
}
function ConvertFrom-OffT([byte[]]$b, [int]$at) {
  [long]$y = $b[$at + 7] -band 0x7F
  for ($i = 6; $i -ge 0; $i--) { $y = $y * 256 + $b[$at + $i] }
  if ($b[$at + 7] -band 0x80) { $y = -$y }
  return $y
}
function Compress-Bzip2([string]$sz, [byte[]]$bytes, [string]$path) {
  [IO.File]::WriteAllBytes($path, $bytes)
  $r = Invoke-Tool $sz @('a', '-tbzip2', '-mx=9', '-y', ($path + '.bz2'), $path)
  if ($r.Code -ne 0) { throw ('7-Zip could not pack ' + $path + ' as bzip2: ' + $r.Err.Trim()) }
  return , [IO.File]::ReadAllBytes($path + '.bz2')
}
function Expand-Bzip2([string]$sz, [byte[]]$bytes, [string]$path) {
  [IO.File]::WriteAllBytes($path + '.bz2', $bytes)
  $r = Invoke-Tool $sz @('e', '-y', ('-o' + (Split-Path -Parent $path)), ($path + '.bz2'))
  if ($r.Code -ne 0) { throw ('7-Zip could not unpack ' + $path + '.bz2: ' + $r.Err.Trim()) }
  return , [IO.File]::ReadAllBytes($path)
}
# The patch from one file to another of the same size: one control entry that
# adds the whole new file to the old, byte by byte, and copies nothing extra.
function New-BsdiffPatch([string]$sz, [byte[]]$old, [byte[]]$new, [string]$dir) {
  if ($old.Length -ne $new.Length) { throw 'a patch here only changes bytes in place, and the two files are not one size' }
  $diff = New-Object byte[] $new.Length
  for ($i = 0; $i -lt $new.Length; $i++) { $diff[$i] = [byte](($new[$i] - $old[$i] + 256) % 256) }
  $ctrl = [byte[]]((ConvertTo-OffT $new.Length) + (ConvertTo-OffT 0) + (ConvertTo-OffT 0))
  $c = Compress-Bzip2 $sz $ctrl (Join-Path $dir 'ctrl')
  $d = Compress-Bzip2 $sz $diff (Join-Path $dir 'diff')
  $e = Compress-Bzip2 $sz (New-Object byte[] 0) (Join-Path $dir 'extra')
  $head = [byte[]]([Text.Encoding]::ASCII.GetBytes('BSDIFF40') + (ConvertTo-OffT $c.Length) + (ConvertTo-OffT $d.Length) + (ConvertTo-OffT $new.Length))
  return , [byte[]]($head + $c + $d + $e)
}
# Any BSDIFF40 patch applied to a file, the way bspatch does, to read back
# what Vortex will make of it.
function Invoke-Bspatch([string]$sz, [byte[]]$old, [byte[]]$patch, [string]$dir) {
  if ($patch.Length -lt 32 -or [Text.Encoding]::ASCII.GetString($patch, 0, 8) -ne 'BSDIFF40') { throw 'it is not a BSDIFF40 patch' }
  $cl = ConvertFrom-OffT $patch 8; $dl = ConvertFrom-OffT $patch 16; $n = ConvertFrom-OffT $patch 24
  if ($cl -lt 0 -or $dl -lt 0 -or $n -lt 0 -or 32 + $cl + $dl -gt $patch.Length) { throw 'its header does not fit it' }
  $blocks = @()
  $at = 32
  foreach ($len in @($cl, $dl, ($patch.Length - 32 - $cl - $dl))) {
    $part = New-Object byte[] $len
    [Array]::Copy($patch, $at, $part, 0, $len)
    $blocks += , (Expand-Bzip2 $sz $part (Join-Path $dir ('block' + $blocks.Count)))
    $at += $len
  }
  $ctrl = $blocks[0]; $diff = $blocks[1]; $extra = $blocks[2]
  $out = New-Object byte[] $n
  [long]$o = 0; [long]$w = 0; $ci = 0; [long]$di = 0; [long]$ei = 0
  while ($w -lt $n) {
    if ($ci + 24 -gt $ctrl.Length) { throw 'its control block ends early' }
    $add = ConvertFrom-OffT $ctrl $ci; $copy = ConvertFrom-OffT $ctrl ($ci + 8); $seek = ConvertFrom-OffT $ctrl ($ci + 16); $ci += 24
    if ($add -lt 0 -or $copy -lt 0 -or $w + $add -gt $n -or $di + $add -gt $diff.Length) { throw 'it is corrupt' }
    for ($i = 0; $i -lt $add; $i++) {
      $ob = if ($o + $i -ge 0 -and $o + $i -lt $old.Length) { $old[$o + $i] } else { 0 }
      $out[$w + $i] = [byte](($diff[$di + $i] + $ob) % 256)
    }
    $di += $add; $w += $add; $o += $add
    if ($w + $copy -gt $n -or $ei + $copy -gt $extra.Length) { throw 'it is corrupt' }
    if ($copy) { [Array]::Copy($extra, $ei, $out, $w, $copy) }
    $ei += $copy; $w += $copy; $o += $seek
  }
  return , $out
}
function Get-Sha256Hex([byte[]]$b) {
  $h = [Security.Cryptography.SHA256]::Create()
  try { return (-join ($h.ComputeHash($b) | ForEach-Object { $_.ToString('x2') })) } finally { $h.Dispose() }
}
# The CRC-32 Vortex records for a patched file, as 7-Zip's hash command gives it.
function Get-Crc32Hex([string]$sz, [string]$path) {
  $r = Invoke-Tool $sz @('h', '-scrcCRC32', $path)
  $m = [regex]::Match($r.Out, 'CRC32\s+for data:\s+([0-9A-Fa-f]{8})')
  if ($r.Code -ne 0 -or -not $m.Success) { throw ('7-Zip gave no CRC-32 for ' + $path + ': ' + $r.Err.Trim()) }
  return $m.Groups[1].Value.ToUpperInvariant()
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
  if ($Mod.Count -or $FileId.Count -or $Archive.Count -or $From -or $Add -or $SetLight.Count -or $ClearLight.Count) { Die '-Publish publishes a draft that is already there, so it takes no -Mod, -FileId, -Archive, -Add, -SetLight, -ClearLight or -From.' }
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
if (-not $Mod.Count -and -not $Add -and -not $SetLight.Count -and -not $ClearLight.Count) { Die 'Say which mods move to a new file with -Mod, -FileId and -Archive, which are added with -Add, which plugins get or lose the light flag with -SetLight and -ClearLight, or publish a draft with -Publish.' }
$Mod = @($Mod | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$FileId = @($FileId | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Mod.Count -ne $FileId.Count -or $Mod.Count -ne $Archive.Count) { Die ('-Mod, -FileId and -Archive go together, one of each for every mod: ' + $Mod.Count + ', ' + $FileId.Count + ' and ' + $Archive.Count + ' were given.') }
for ($i = 0; $i -lt $Mod.Count; $i++) {
  if ($Mod[$i] -notmatch '^\d+$') { Die ('-Mod ' + $Mod[$i] + ' is not a mod number.') }
  if ($FileId[$i] -notmatch '^\d+$') { Die ('-FileId ' + $FileId[$i] + ' is not a file id.') }
}
$adds = @()
if ($Add) {
  if (-not (Test-Path -LiteralPath $Add -PathType Leaf)) { Die ('There is no file at ' + $Add + '.') }
  try { $adds = @(ConvertFrom-Json ([IO.File]::ReadAllText($Add) -replace ('^' + [char]0xFEFF), '')) }
  catch { Die ($Add + ' is not JSON this can read: ' + $_.Exception.Message) }
  if (-not $adds.Count) { Die ($Add + ' names no mods to add.') }
  foreach ($a in $adds) {
    if ([string]$a.modId -notmatch '^\d+$') { Die ('A mod to add in ' + $Add + ' has the mod number "' + $a.modId + '".') }
    if ([string]$a.fileId -notmatch '^\d+$') { Die ('Mod ' + $a.modId + ' in ' + $Add + ' has the file id "' + $a.fileId + '".') }
    if (-not $a.archive -or -not (Test-Path -LiteralPath ([string]$a.archive) -PathType Leaf)) { Die ('Mod ' + $a.modId + ' in ' + $Add + ' names no archive that is there: "' + $a.archive + '".') }
  }
}
$lights = @()
foreach ($n in @($SetLight | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { $lights += [pscustomobject]@{ Name = $n; Light = $true } }
foreach ($n in @($ClearLight | ForEach-Object { ([string]$_).Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })) { $lights += [pscustomobject]@{ Name = $n; Light = $false } }
foreach ($l in $lights) {
  if ($l.Name -notmatch '^[^\\/:*?"<>|]+\.es[mp]$') { Die ($l.Name + ' is not a plugin file name (.esm or .esp): an .esl is light by its name, with no flag to set.') }
  if (@($lights | Where-Object { $_.Name -ieq $l.Name }).Count -gt 1) { Die ($l.Name + ' is named more than once in -SetLight and -ClearLight.') }
}
if ($lights.Count) {
  if (-not $Layout) { Die '-SetLight and -ClearLight need -Layout, the Install-NexusRevision.ps1 -Record folder of the revision this starts from.' }
  foreach ($f in 'layout.json', 'files.txt') { if (-not (Test-Path -LiteralPath (Join-Path $Layout $f) -PathType Leaf)) { Die ('There is no ' + $f + ' in ' + $Layout + ', so it is not an Install-NexusRevision.ps1 -Record folder.') } }
}
# The revision this starts from: the latest published, or the waiting draft
# for a -WhatIf, as A DRAFT WAITING above says.
$start = $latest; $startStatus = 'published'
if ($draft) {
  if (-not $WhatIf) { Die ('Revision ' + $draft + ' is already a draft on Nexus. Publish it with -Publish ' + $draft + ', or discard it on the website, before making another.') }
  $start = [int]$draft; $startStatus = 'draft'
  Say ('  Revision ' + $draft + ' is a draft, so this -WhatIf builds on it. A run that writes waits until it is published.') 'Yellow'
}
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Die 'node is not on this machine, and nexus-collection.js writes collection.json the way Vortex does.' }
$sz = Find-SevenZip
if (-not $sz) { Die '7-Zip is not on this machine (7z.exe in Program Files, or 7z, 7zz or 7za on PATH), and the collection is a 7z archive.' }

$scratch = & (Join-Path $Here 'Get-ScratchDir.ps1') ('nexus-revision-' + $Slug)
if (-not $From) {
  $rq = '{ collectionRevision(slug: "' + $Slug + '", revision: ' + $start + ', domainName: "' + $Game + '") { id status downloadLink } }'
  $rev = Get-NexusField (Step { Invoke-NexusGraph $rq $null ('Reading revision ' + $start) }) 'collectionRevision'
  $link = [string](Get-NexusField $rev 'downloadLink')
  if ([string](Get-NexusField $rev 'status') -ne $startStatus -or $link -notmatch '^/v2/collections/\d+/revisions/\d+/download_link$') { Die ('Nexus gave revision ' + $start + ' as ' + [string](Get-NexusField $rev 'status') + ' with the download link "' + $link + '", not a ' + $startStatus + ' revision''s API path, so it was not downloaded.') }
  $links = @(Get-NexusField (Step { Invoke-NexusApi 'GET' $link '' ('Asking for revision ' + $start + '''s download') }) 'download_links')
  $uri = [string](Get-NexusField ($links | Select-Object -First 1) 'URI')
  if (-not $uri) { Die ('Nexus gave no download address for revision ' + $start + '.') }
  $pub = Join-Path $scratch 'published'
  if (Test-Path -LiteralPath $pub) { Remove-Item -LiteralPath $pub -Recurse -Force }
  $got = Step { Receive-NexusPresigned $uri $pub ('Downloading revision ' + $start) ('collection_' + $Slug + '_' + $start + '_.7z') }
  $From = $got.Path
  $BaseRevision = $start
}
if (-not (Test-Path -LiteralPath $From)) { Die ('There is nothing at ' + $From + '.') }
if (-not $BaseRevision) {
  $bm = [regex]::Match((Split-Path -Leaf $From), ('^collection_' + $Slug + '_(\d+)_'))
  if (-not $bm.Success) { Die ((Split-Path -Leaf $From) + ' does not say which revision it is; say it with -BaseRevision.') }
  $BaseRevision = [int]$bm.Groups[1].Value
}
Head 'The revision it starts from'
Say ('  ' + $From)
if ($BaseRevision -ne $start) { Die ('That is revision ' + $BaseRevision + ', but this starts from revision ' + $start + ', ' + $(if ($startStatus -eq 'draft') { 'the draft' } else { 'the latest published' }) + '. Start from revision ' + $start + ' (leave -From off and it is downloaded from Nexus).') }
Say ('  revision ' + $BaseRevision + ', ' + $(if ($startStatus -eq 'draft') { 'the draft' } else { 'the latest published' })) 'Green'

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
if ($Mod.Count) { Head 'The new files' }
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

# ------------------------------------------------------------ the adds ---
if ($adds.Count) { Head 'The mods added' }
foreach ($a in $adds) {
  $m = [string]$a.modId; $fid = [string]$a.fileId; $arc = [string]$a.archive
  $lq = '{ legacyModsByDomain(ids: [{gameDomain: "' + $Game + '", modId: ' + $m + '}]) { nodes { modId name author modCategory { name } } } }'
  $modNode = @(Get-NexusField (Get-NexusField (Step { Invoke-NexusGraph $lq $null ('Reading mod ' + $m) }) 'legacyModsByDomain') 'nodes') | Select-Object -First 1
  if (-not $modNode) { Die ('Nexus has no mod ' + $m + ' on ' + $Game + '.') }
  $modName = [string](Get-NexusField $modNode 'name')
  $author = [string](Get-NexusField $modNode 'author')
  $category = [string](Get-NexusField (Get-NexusField $modNode 'modCategory') 'name')
  if (-not $author -or -not $category) { Die ('Nexus gave mod ' + $m + ' with no author or no category, which every entry Vortex writes carries.') }
  $info = Step { Get-NexusField (Invoke-NexusApi 'GET' ('/v3/games/' + $Game + '/mods/' + $m) '' ('Reading mod ' + $m)) 'data' }
  $uid = [string](Get-NexusField $info 'id')
  $v = Step { Get-NexusField (Invoke-NexusApi 'GET' ('/v3/games/' + $Game + '/mod-file-versions/' + $fid) '' ('Reading file id ' + $fid)) 'data' }
  $vFile = [string](Get-NexusField (Get-NexusField $v 'file') 'id')
  $files = @(@(Get-NexusField (Get-NexusField (Step { Invoke-NexusApi 'GET' ('/v3/mods/' + $uid + '/files') '' ('Reading the files of mod ' + $m) }) 'data') 'mod_files') | Where-Object { $_ })
  if (-not @($files | Where-Object { [string](Get-NexusField $_ 'id') -eq $vFile }).Count) { Die ('File id ' + $fid + ' is not a file of mod ' + $m + '.') }
  $cat = [string](Get-NexusField $v 'category')
  if (@('main', 'update', 'optional', 'miscellaneous') -notcontains $cat) { Die ('File id ' + $fid + ' of mod ' + $m + ' is ' + $cat + ', not a file people can download now.') }
  $fileName = [string](Get-NexusField $v 'name')
  # The name Vortex shows: the file's own name when it says which mod it is,
  # else the mod's name before it.
  $entryName = if ($fileName.IndexOf($modName, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $fileName } else { $modName + ' - ' + $fileName }

  # The plugins it carries, wherever they sit: where each lands is the basic
  # installer's to work out, and Install-NexusRevision.ps1 does that as
  # Vortex does when the new revision is laid out.
  $paths = @(Step { Get-ArchivePaths $sz $arc })
  if (@($paths | Where-Object { $_ -match '(^|\\)fomod\\moduleconfig\.xml$' }).Count) { Die ($arc + ' has a FOMOD installer, whose answers Vortex works out when it installs it. Add it in Vortex on One.') }
  $found = @($paths | Where-Object { $_ -match '\.es[mpl]$' } | ForEach-Object { $_.Substring($_.LastIndexOf('\') + 1) })
  $named = @(@($a.plugins) | Where-Object { $_ } | ForEach-Object { [string]$_.name })
  $missing = @($found | Where-Object { $named -inotcontains $_ })
  $extraNamed = @($named | Where-Object { @($found) -inotcontains $_ })
  if ($missing.Count -or $extraNamed.Count) { Die ('The plugins named for mod ' + $m + ' are not the ones its archive holds (in the archive only: ' + ($missing -join ', ') + '; named only: ' + ($extraNamed -join ', ') + ').') }

  # Only its md5 and size: this archive is the mod author's, read and never
  # uploaded, so its name is not held to what an upload header can carry.
  $facts = Step { $it = Get-Item -LiteralPath $arc; [pscustomobject]@{ Name = $it.Name; Size = [long]$it.Length; Md5Hex = (Get-FileHash -LiteralPath $it.FullName -Algorithm MD5).Hash.ToLowerInvariant() } }
  Say ('  mod ' + $m + ' (' + $modName + ' by ' + $author + ', ' + $category + '): file id ' + $fid + ', "' + $fileName + '" ' + (Get-NexusField $v 'version') + ', ' + $cat)
  Say ('    ' + $facts.Name + ', ' + $facts.Size.ToString('N0') + ' bytes, md5 ' + $facts.Md5Hex + ', ' + @($found).Count + ' plugin(s)') 'DarkGray'
  $plugins = @(@($a.plugins) | Where-Object { $_ } | ForEach-Object { [ordered]@{ name = [string]$_.name; after = @(@($_.after) | ForEach-Object { [string]$_ }) } })
  $swaps.Add([ordered]@{ add = $true; modId = $m; fileId = $fid; version = [string](Get-NexusField $v 'version'); md5 = $facts.Md5Hex; fileSize = $facts.Size;
    logicalFilename = $fileName; name = $entryName; author = $author; category = $category; plugins = $plugins })
}

# ------------------------------------------------------- the light flags ---
# LIGHT FLAGS above: each plugin found by the layout, its archive downloaded
# and held to the revision, the patch made, read back and staged.
$staged = Join-Path $scratch 'light'
$lightPaths = @()
if ($lights.Count) {
  Head 'The light flags'
  if (-not $isArchive) { Die ('-SetLight and -ClearLight hold -Layout to the archive it was laid out from, and -From is a folder.') }
  $lay = Step { ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText((Join-Path $Layout 'layout.json'))) (Join-Path $Layout 'layout.json') }
  $fromMd5 = (Get-FileHash -LiteralPath $From -Algorithm MD5).Hash.ToLowerInvariant()
  if ([int]$lay.collection.revision -ne $BaseRevision -or [string]$lay.collection.archiveMd5 -ne $fromMd5) { Die ($Layout + ' is the layout of revision ' + $lay.collection.revision + ' (archive md5 ' + $lay.collection.archiveMd5 + '), not of revision ' + $BaseRevision + ' as downloaded (md5 ' + $fromMd5 + '). Lay this revision out with Install-NexusRevision.ps1 -Record first.') }
  $placedBy = @{}
  foreach ($line in [IO.File]::ReadAllLines((Join-Path $Layout 'files.txt'))) {
    if ($line.StartsWith('#')) { continue }
    $c = $line.Split("`t")
    if ($c.Count -eq 4) { $placedBy[$c[3].ToLowerInvariant()] = [pscustomobject]@{ Sha256 = $c[0]; Size = [long]$c[1]; FileId = $c[2] } }
  }
  $recordPath = Join-Path $Here '..\..\records\collection-plugins.json'
  $onOne = @{}
  if (Test-Path -LiteralPath $recordPath) { foreach ($p in @((ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText($recordPath)) $recordPath).plugins)) { $onOne[([string]$p.name).ToLowerInvariant()] = [string]$p.sha256 } }
  $baseCol = Step { ConvertFrom-Json ([IO.File]::ReadAllText($baseJson)) }
  if (Test-Path -LiteralPath $staged) { Remove-Item -LiteralPath $staged -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $staged | Out-Null
  $unpacked = @{}
  foreach ($l in $lights) {
    $what = $l.Name + $(if ($l.Light) { ' light' } else { ' not light' })
    $row = $placedBy[('data\' + $l.Name).ToLowerInvariant()]
    if (-not $row) { Die ('Revision ' + $BaseRevision + ' puts no ' + $l.Name + ' in Data, by ' + $Layout + '\files.txt.') }
    $hits = @($baseCol.mods | Where-Object { $_.source -and [string]$_.source.fileId -eq $row.FileId })
    if ($hits.Count -ne 1) { Die ('Revision ' + $BaseRevision + ' has ' + $hits.Count + ' entries for file ' + $row.FileId + ', which puts ' + $l.Name + ' in Data, so there is no one entry to patch.') }
    $e = $hits[0]
    # Vortex keeps a mod's patches under patches\<its name>, and an entry of
    # the default mod type deploys into Data, so the file's path in the mod
    # is its path in Data.
    $type = if ($e.details -and $e.details.PSObject.Properties['type']) { [string]$e.details.type } else { '' }
    if ($type) { Die ($e.name + ' is mod type "' + $type + '", which does not deploy into Data, so its patch path is not ' + $l.Name + '.') }
    if (([string]$e.name).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { Die ('The entry name "' + $e.name + '" cannot be a folder under patches.') }
    if ($e.PSObject.Properties['patches'] -and $e.patches -and @($e.patches.PSObject.Properties | Where-Object { $_.Name -ieq $l.Name }).Count) { Die ($e.name + ' already patches ' + $l.Name + ' in revision ' + $BaseRevision + '.') }
    $fid = [string]$row.FileId
    if (-not $unpacked.ContainsKey($fid)) {
      $dir = Join-Path $staged $fid
      $dl = Get-NexusField (Step { Invoke-NexusApi 'GET' ('/v3/games/' + $Game + '/mod-file-versions/' + $fid + '/download-link') '' ('Asking for the download of ' + $e.name) }) 'data'
      $url = [string](Get-NexusField (@(Get-NexusField $dl 'links') | Select-Object -First 1) 'url')
      if (-not $url) { Die ('Nexus gave no download address for ' + $e.name + ', file ' + $fid + '.') }
      $got = Step { Receive-NexusPresigned $url $dir ('Downloading ' + $e.name) ($fid + '.archive') }
      if ($got.Size -ne [long]$e.source.fileSize -or $got.Md5Hex -ne [string]$e.source.md5) { Die ('The download of ' + $e.name + ' is ' + $got.Size + ' bytes, md5 ' + $got.Md5Hex + ', and revision ' + $BaseRevision + ' says ' + $e.source.fileSize + ' bytes, md5 ' + $e.source.md5 + '.') }
      $x = Join-Path $dir 'unpacked'
      $r = Invoke-Tool $sz @('x', '-y', ('-o' + $x), $got.Path, '-ir!*.esp', '-ir!*.esm')
      if ($r.Code -ne 0) { Die ('7-Zip could not unpack ' + $got.Path + ': ' + $r.Err.Trim()) }
      [IO.File]::Delete($got.Path)
      $unpacked[$fid] = $x
    }
    $src = @(Get-ChildItem -LiteralPath $unpacked[$fid] -Recurse -File | Where-Object { $_.Length -eq $row.Size -and (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -eq $row.Sha256 }) | Select-Object -First 1
    if (-not $src) { Die ($e.name + '''s archive holds no file with the bytes revision ' + $BaseRevision + ' puts in Data as ' + $l.Name + ' (sha256 ' + $row.Sha256 + ').') }
    $old = [IO.File]::ReadAllBytes($src.FullName)
    if ($old.Length -lt 12 -or [Text.Encoding]::ASCII.GetString($old, 0, 4) -ne 'TES4') { Die ($l.Name + ' in ' + $e.name + ' has no TES4 header, so it is not a plugin.') }
    $flags = [BitConverter]::ToUInt32($old, 8)
    if ((($flags -band 0x200) -ne 0) -eq $l.Light) { Die ($l.Name + ' is already' + $(if ($l.Light) { '' } else { ' not' }) + ' light in ' + $e.name + ', so there is nothing to patch.') }
    $new = [byte[]]$old.Clone()
    $nf = if ($l.Light) { $flags -bor 0x200 } else { $flags -band (-bnot [uint32]0x200) }
    [Array]::Copy([BitConverter]::GetBytes([uint32]$nf), 0, $new, 8, 4)
    $work = Join-Path $staged ('work-' + $l.Name)
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $patch = Step { New-BsdiffPatch $sz $old $new $work }
    $back = Step { Invoke-Bspatch $sz $old $patch $work }
    $want = Get-Sha256Hex $new
    if ((Get-Sha256Hex $back) -ne $want) { Die ('The patch made for ' + $l.Name + ' does not give back the file it was made for, so it was not packed.') }
    $crc = Step { Get-Crc32Hex $sz $src.FullName }
    $rel = 'patches\' + $e.name + '\' + $l.Name + '.diff'
    $to = Join-Path $staged ('patches\' + $e.name)
    New-Item -ItemType Directory -Force -Path $to | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $to ($l.Name + '.diff')), $patch)
    Remove-Item -LiteralPath $work -Recurse -Force
    $lightPaths += $rel
    if (-not ($basePaths -contains ('patches\' + $e.name))) { $lightPaths += ('patches\' + $e.name) }
    $one = $onOne[$l.Name.ToLowerInvariant()]
    $vs = if (-not $one) { 'records\collection-plugins.json does not name it' } elseif ($one -eq $want) { 'the same bytes as records\collection-plugins.json' } else { 'NOT the bytes records\collection-plugins.json has (' + $one + ')' }
    Say ('  ' + $what + ': ' + $e.name + ', file ' + $fid + ', CRC-32 ' + $crc + ', flags 0x' + $flags.ToString('X8') + ' -> 0x' + ([uint32]$nf).ToString('X8') + ', sha256 ' + $want)
    Say ('    ' + $rel + ', ' + $patch.Length + ' bytes, read back; ' + $vs) $(if ($one -and $one -ne $want) { 'Yellow' } else { 'DarkGray' })
    $swaps.Add([ordered]@{ patch = $true; fileId = $fid; path = $l.Name; crc = $crc })
  }
  foreach ($k in @($unpacked.Keys)) { Remove-Item -LiteralPath (Split-Path -Parent $unpacked[$k]) -Recurse -Force }
  if (-not ($basePaths -contains 'patches')) { $lightPaths += 'patches' }
}

# --------------------------------------------------------- the new archive ---
Head 'The new revision'
Copy-Item -Path (Join-Path $base '*') -Destination $build -Recurse -Force
if ($lights.Count) { Copy-Item -Path (Join-Path $staged 'patches') -Destination $build -Recurse -Force }
$swapsJson = Join-Path $scratch 'swaps.json'
$payloadJson = Join-Path $scratch 'payload.json'
[IO.File]::WriteAllText($swapsJson, (ConvertTo-Json -InputObject @($swaps.ToArray()) -Depth 6), (New-Object Text.UTF8Encoding($false)))
$r = Invoke-Tool $node.Source @((Join-Path $Here 'nexus-collection.js'), $baseJson, $swapsJson, (Join-Path $build 'collection.json'), $payloadJson)
if ($r.Code -ne 0) { Die ($r.Err.Trim() + ' Nothing was built.') }
foreach ($line in ($r.Out -split "`r?`n" | Where-Object { $_ })) {
  $c = $line.Split("`t")
  if ($c[1] -eq 'added' -or $c[1] -eq 'plugin' -or $c[1] -eq 'patch') { Say ('  ' + $c[0] + ', ' + $c[1] + ': ' + $c[3]) }
  else { Say ('  ' + $c[0] + ', ' + $c[1] + ': ' + $c[2] + ' -> ' + $c[3]) }
}
$newRev = $start + 1
$out = Join-Path $outDir ('collection_' + $newRev + '.7z')
$tops = @(Get-ChildItem -LiteralPath $build -Force | ForEach-Object { $_.Name })
$r = Invoke-Tool $sz (@('a', '-t7z', '-y', $out) + $tops) $build
if ($r.Code -ne 0) { Die ('7-Zip could not pack the new revision: ' + $r.Err.Trim()) }
$newPaths = @(Step { Get-ArchivePaths $sz $out })
$gone = @($basePaths | Where-Object { $newPaths -notcontains $_ })
$extra = @($newPaths | Where-Object { $basePaths -notcontains $_ -and $lightPaths -notcontains $_ })
if ($gone.Count -or $extra.Count) { Die ('The new archive does not hold the same files and folders as revision ' + $start + ' (missing: ' + ($gone -join ', ') + '; extra: ' + ($extra -join ', ') + '). Nothing was sent.') }
$facts = Step { Get-NexusArchiveFacts $out }
Say ('  ' + $out)
$addedPaths = @($newPaths | Where-Object { $basePaths -notcontains $_ })
Say ('  ' + $facts.Size.ToString('N0') + ' bytes, md5 ' + $facts.Md5Hex + ', the same ' + ($newPaths.Count - $addedPaths.Count) + ' files and folders as revision ' + $start + $(if ($addedPaths.Count) { ' and ' + $addedPaths.Count + ' more for the light flags' } else { '' }))
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
