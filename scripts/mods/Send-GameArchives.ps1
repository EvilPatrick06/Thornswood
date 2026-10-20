<#
  Send-GameArchives.ps1

  Puts Skyrim's own archives that the content tools read on the VPS box, in
  C:\Thornswood-GameData, each checked against records\skyrim-files.json on
  this machine before it goes and on the box after it lands. Issue #2899.

      .\scripts\mods\Send-GameArchives.ps1
      .\scripts\mods\Send-GameArchives.ps1 -Data 'D:\Steam\steamapps\common\Skyrim Special Edition\Data'
      .\scripts\mods\Send-GameArchives.ps1 -Check

  WHY. Patrick, 20 Oct 2026, A on #2899 (his page answer): "All needed
  archives. Interface, Meshes0-1 and Textures0-8 (about 9.7 GB) go in a
  staff-only folder on the box." scripts\mods\Run-OnBox.ps1 runs the content
  tools on the box against a game server's plugins; the string tables, the
  start menu, the meshes and the textures those tools also read were only on
  One. With them on the box, every content tool runs from a machine with no
  game at all.

  WHAT GOES. The twelve archives scripts\mods\OnBox.ps1 names, and nothing
  else: no plugin, no loose file, nothing of a mod's. Each is held to the
  size and sha1 records\skyrim-files.json gives for the pinned Skyrim build,
  so a changed or modded archive is refused here, before anything is sent.
  An archive the box already holds with those bytes is not sent again.

  ON THE BOX. C:\Thornswood-GameData is made locked (SYSTEM's and
  Administrators' only, Lock-Folder.ps1 -Only) and nothing serves it. Each
  archive arrives as .incoming-<name>, is hashed there, and takes its name
  only when it is the recorded bytes; then it is made read only to everyone
  but SYSTEM (OnBox.ps1 says why). An arrival that is not the recorded bytes
  is deleted and the run stops.

  -Check hashes what is here and asks the box what it holds, and sends
  nothing.
#>
[CmdletBinding()]
param(
    # The game's Data folder on this machine.
    [string]$Data = 'C:\Thornswood\Game\Data',
    [switch]$Check,
    [string]$VpsHost = '',
    [string]$VpsUser = ''
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\deploy\Artifact.ps1')
. (Join-Path $Here 'OnBox.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
$store = $ThornswoodGameArchiveStore

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

# ---------------------------------------------------------------- here ----
$record = Get-Content -LiteralPath (Join-Path $Here '..\..\records\skyrim-files.json') -Raw | ConvertFrom-Json
$want = [ordered]@{}
foreach ($n in $ThornswoodGameArchives) {
    $r = $record.files.('Data\' + $n)
    if (-not $r -or -not $r.sha1 -or -not $r.bytes) { throw "records\skyrim-files.json has no size and sha1 for Data\$n. Nothing was sent." }
    $want[$n] = [pscustomobject]@{ Bytes = [long]$r.bytes; Sha1 = ([string]$r.sha1).ToLowerInvariant() }
}

Say "Here, in $Data" 'Cyan'
$sha1 = [Security.Cryptography.SHA1]::Create()
$bad = @()
foreach ($n in $want.Keys) {
    $p = Join-Path $Data $n
    if (-not (Test-Path -LiteralPath $p)) { $bad += "$n is not there"; continue }
    $len = (Get-Item -LiteralPath $p).Length
    if ($len -ne $want[$n].Bytes) { $bad += ("$n is {0:N0} bytes, the record says {1:N0}" -f $len, $want[$n].Bytes); continue }
    $s = [IO.File]::OpenRead($p)
    try { $h = ([BitConverter]::ToString($sha1.ComputeHash($s)) -replace '-', '').ToLowerInvariant() } finally { $s.Close() }
    if ($h -ne $want[$n].Sha1) { $bad += "$n has sha1 $h, the record says $($want[$n].Sha1)"; continue }
    Say ("  ok    {0}  {1:N0} bytes" -f $n, $len)
}
if ($bad.Count) {
    foreach ($b in $bad) { Say "  STOP  $b" 'Red' }
    throw ('These are not the pinned Skyrim build''s archives (records\skyrim-files.json), so nothing was sent. Point -Data at the game''s own Data folder.')
}

# -------------------------------------------------------------- the box ---
$lines = @()
foreach ($n in $want.Keys) { $lines += "'" + $n + "' = '" + $want[$n].Sha1 + "'" }
$table = '@{ ' + ($lines -join '; ') + ' }'
$ask = @"
`$ErrorActionPreference = 'Stop'
$(Get-ThornswoodLockedFolderScript $store -Only)
`$want = $table
`$sha1 = [Security.Cryptography.SHA1]::Create()
foreach (`$n in `$want.Keys) {
  `$p = Join-Path '$store' `$n
  if (-not (Test-Path -LiteralPath `$p)) { 'NEEDS ' + `$n; continue }
  `$s = [IO.File]::OpenRead(`$p)
  try { `$h = ([BitConverter]::ToString(`$sha1.ComputeHash(`$s)) -replace '-', '').ToLowerInvariant() } finally { `$s.Close() }
  if (`$h -eq `$want[`$n]) { 'HAS ' + `$n } else { 'NEEDS ' + `$n }
}
"@
Say ''
Say "On the box, in $store" 'Cyan'
$answer = @(Invoke-ThornswoodArtifactRemote $target $ssh $ask)
foreach ($l in @($answer | Where-Object { $_ -like 'locked *' -or $_ -like 'FAILED *' })) { Say "  $l" }
if (@($answer | Where-Object { $_ -like 'FAILED *' }).Count) { throw "the box could not lock $store. Nothing was sent." }
$has = @($answer | Where-Object { $_ -like 'HAS *' } | ForEach-Object { $_.Substring(4) })
$needs = @($answer | Where-Object { $_ -like 'NEEDS *' } | ForEach-Object { $_.Substring(6) })
if (($has.Count + $needs.Count) -ne $want.Count) { throw ('the box did not answer for every archive (' + ($answer -join ' ') + '). Nothing was sent.') }
foreach ($n in $has) { Say "  has   $n" }
foreach ($n in $needs) { Say "  needs $n" 'Yellow' }
if ($Check) { Say ''; Say '-Check, so nothing was sent.'; exit 0 }
if (-not $needs.Count) { Say ''; Say 'The box already holds every archive, so nothing was sent.' 'Green'; exit 0 }

$storeFar = $store.Replace('\', '/')
foreach ($n in $needs) {
    Say ''
    Say ("sending {0}, {1:N0} bytes" -f $n, $want[$n].Bytes)
    $incoming = '.incoming-' + $n
    Send-ThornswoodArtifactFile (Join-Path $Data $n) $target $ssh ($storeFar + '/' + $incoming)
    $place = @"
`$ErrorActionPreference = 'Stop'
$(Get-ThornswoodArchiveReadOnlyScript)
`$in = Join-Path '$store' '$incoming'
`$to = Join-Path '$store' '$n'
`$sha1 = [Security.Cryptography.SHA1]::Create()
`$s = [IO.File]::OpenRead(`$in)
try { `$h = ([BitConverter]::ToString(`$sha1.ComputeHash(`$s)) -replace '-', '').ToLowerInvariant() } finally { `$s.Close() }
if (`$h -ne '$($want[$n].Sha1)' -or (Get-Item -LiteralPath `$in).Length -ne $($want[$n].Bytes)) {
  Remove-Item -LiteralPath `$in -Force
  'WRONG ' + `$h
  exit 1
}
if (Test-Path -LiteralPath `$to) { Remove-Item -LiteralPath `$to -Force }
Move-Item -LiteralPath `$in -Destination `$to
Set-ThornswoodArchiveReadOnly `$to
'PLACED'
"@
    $out = @(Invoke-ThornswoodArtifactRemote $target $ssh $place)
    if ($out -notcontains 'PLACED') { throw ("$n did not arrive as the recorded bytes (" + ($out -join ' ') + '). It was deleted on the box; run this again.') }
    Say "  placed, read only" 'Green'
}
Say ''
Say ("The box holds all {0} archives in {1}." -f $want.Count, $store) 'Green'
