<#
  Clean-Everything.ps1

      .\scripts\mods\Clean-Everything.ps1              show what is there, delete nothing
      .\scripts\mods\Clean-Everything.ps1 -Delete      delete it, after you type DELETE

  Finds the old installers, build leftovers, temp files, stale backups and old
  GitHub release assets across this machine, the server and the source repository,
  adds up what they are costing, and prints it.

  It deletes NOTHING unless you pass -Delete, and even then it asks you to type
  the word out. What it deletes is exactly what it printed, nothing found later
  and nothing inferred.

  Never touched, whatever you pass:

    the Vortex downloads folder    those archives are every mod you have, and
                                   re-downloading them is 20 GB and an evening
    the newest backup              a cleanup that removes your only backup is
                                   not a cleanup
    anything under Game\Data       that is the build, not leftovers
    the repositories themselves    only their release assets are in scope

  Pick a part with -Installers, -Packs, -Stage, -Backups, -Temp, -Github or
  -ServerSaves. With none of them it looks at all of them except -ServerSaves,
  which is a wipe and has to be asked for by name.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '',
  [string]$User = 'Administrator',
  [string]$Root = 'C:\Thornswood',
  # Another repository whose release assets to look at. Thornswood-Releases
  # was the default until #907 deleted it.
  [string]$Repo = '',
  [string]$SourceRepo = 'EvilPatrick06/Thornswood',
  [string]$BackupDir,
  # How many of the newest to keep in each group that has a series.
  [int]$KeepBackups = 2,
  [int]$KeepReleases = 5,
  [switch]$Installers,
  [switch]$Packs,
  [switch]$Stage,
  [switch]$Backups,
  [switch]$Temp,
  [switch]$Github,
  # The server's character storage. This is a wipe, not a cleanup, so it is
  # never part of -All and has to be named.
  [switch]$ServerSaves,
  [switch]$Delete,
  [switch]$NoPause
)


$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=yes')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) {
  Write-Host ''
  Write-Host "STOP. $m" -ForegroundColor Red
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}
function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  $cmd = "powershell -NoProfile -EncodedCommand $e"

  # A long script does not fit on a command line, and nothing says so.
  #
  # sshd on Windows hands the command to cmd.exe, which stops at 8,191
  # characters. Base64 of UTF-16 is about 2.7 times the script, so a block of
  # any size arrives cut in half and PowerShell then complains about a brace or
  # a token in a script nobody can see. Deploy-Docs.ps1 hit this on 17 Sep and
  # solved it; every other script here carried the short version that cannot,
  # and on 20 Sep this one truncated at 10,252 characters and reported
  # "Unexpected token '$?'" about a line fifteen above the one that was cut.
  # This is that fix, copied across so the sixteen scripts that talk to the VPS
  # all behave the same way.
  #
  # Under the limit it goes on the command line as before, because that is one
  # round trip. Over it, the script is sent as a file and run from there, which
  # has no length to run into.
  if ($cmd.Length -le 6000) {
    return & ssh @ssh "$User@$Vps" $cmd 2>&1
  }

  $far = 'C:/Windows/Temp/thornswood-remote.ps1'
  $tmp = [IO.Path]::GetTempFileName()
  try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    & scp @ssh $tmp "$User@${Vps}:$far" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not send a script to $Vps" }
    # The path goes across as it is. Windows PowerShell takes forward
    # slashes, and converting them was how this shipped with the slashes
    # stripped out of it entirely: C:WindowsTempthornswood-remote.ps1.
    # And bare, with no quotes round it; the path above is ours and has no
    # spaces. Measured on this machine on 24 September, not on the VPS: bare
    # runs whether cmd.exe or Windows PowerShell hands the line on, and the
    # old form, the path in single quotes, fails under cmd.exe. The old form
    # did run on the VPS on 20 and 21 September, so which shell sshd uses
    # there is not known, and bare is the form that works under either.
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File $far" 2>&1
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}
function Mb($b) { return [math]::Round($b / 1MB, 1) }
function Gb($b) { return [math]::Round($b / 1GB, 2) }

if (-not $BackupDir) {
  $BackupDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\Thornswood-Backups'
}

$pickedAny = $Installers -or $Packs -or $Stage -or $Backups -or $Temp -or $Github -or $ServerSaves
if (-not $pickedAny) {
  $Installers = $true; $Packs = $true; $Stage = $true
  $Backups = $true; $Temp = $true; $Github = $true
}

Write-Host ''
Write-Host '  THORNSWOOD  -  what is lying around' -ForegroundColor White
if (-not $Delete) { Say '  Looking only. Nothing will be deleted.' 'DarkGray' }
else { Say '  -Delete is on. You will be asked to confirm before anything goes.' 'Yellow' }

# Every candidate lands here: Where (this machine / the server / github),
# What (a label), Path, Bytes. Deletion walks this and nothing else.
$found = @()
function Add-Found($where, $what, $path, $bytes) {
  $script:found += [pscustomobject]@{ Where = $where; What = $what; Path = $path; Bytes = [int64]$bytes }
}

function Folder-Bytes($path) {
  if (-not (Test-Path -LiteralPath $path)) { return 0 }
  $sum = 0
  foreach ($f in (Get-ChildItem -LiteralPath $path -Recurse -File -Force -EA SilentlyContinue)) { $sum += $f.Length }
  return $sum
}

# ------------------------------------------------------- this machine ---
$dist = Join-Path $Root '_dist'

if ($Installers) {
  Head 'Old installers on this machine'
  foreach ($n in @('Thornswood-Setup.zip', 'Thornswood-Setup.exe')) {
    $p = Join-Path $dist $n
    if (Test-Path -LiteralPath $p) {
      $i = Get-Item -LiteralPath $p
      Add-Found 'this machine' 'old installer' $p $i.Length
      Say ("  {0,10:n1} GB  {1}   built {2}" -f (Gb $i.Length), $n, $i.LastWriteTime.ToString('dd MMM HH:mm'))
    }
  }
  if (-not ($found | Where-Object { $_.What -eq 'old installer' })) { Say '  none' 'DarkGray' }
}

if ($Packs) {
  Head 'Old pack builds'
  $packs = @(Get-ChildItem -LiteralPath $dist -Filter 'pack-*.zip' -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending)
  if ($packs.Count -eq 0) { Say '  none' 'DarkGray' }
  else {
    $keep = [Math]::Min(2, $packs.Count)
    Say ("  {0} pack zip(s), keeping the newest {1}" -f $packs.Count, $keep) 'DarkGray'
    for ($i = $keep; $i -lt $packs.Count; $i++) {
      Add-Found 'this machine' 'old pack' $packs[$i].FullName $packs[$i].Length
    }
    $sum = ($packs | Select-Object -Skip $keep | Measure-Object -Property Length -Sum).Sum
    Say ("  {0,10:n1} MB  in {1} older pack(s)" -f (Mb $sum), ($packs.Count - $keep))
  }
}

if ($Stage) {
  Head 'Packaging leftovers'
  foreach ($n in @('stage', 'removed-plugins', 'unbound-locked', 'unbound-original', 'sfx', 'server')) {
    $p = Join-Path $dist $n
    if (Test-Path -LiteralPath $p) {
      $b = Folder-Bytes $p
      Add-Found 'this machine' 'packaging leftover' $p $b
      Say ("  {0,10:n1} GB  _dist\{1}" -f (Gb $b), $n)
    }
  }
  # The build tree's debug symbols. Enormous and rebuildable.
  $pdb = Join-Path (& (Join-Path $PSScriptRoot '..\release\Where.ps1') ServerDist) 'scam_native.pdb'
  if (Test-Path -LiteralPath $pdb) {
    $i = Get-Item -LiteralPath $pdb
    Add-Found 'this machine' 'debug symbols' $pdb $i.Length
    Say ("  {0,10:n1} MB  scam_native.pdb   debug symbols, rebuildable" -f (Mb $i.Length))
  }
}

if ($Backups) {
  Head 'Old backups'
  $zips = @(Get-ChildItem -LiteralPath $BackupDir -Filter 'thornswood-backup-*.zip' -File -EA SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
  if ($zips.Count -eq 0) { Say '  none' 'DarkGray' }
  else {
    $keep = [Math]::Min($KeepBackups, $zips.Count)
    Say ("  {0} backup(s), keeping the newest {1}" -f $zips.Count, $keep) 'DarkGray'
    foreach ($z in ($zips | Select-Object -First $keep)) {
      Say ("  {0,10:n1} MB  {1}   KEPT" -f (Mb $z.Length), $z.Name) 'Green'
    }
    foreach ($z in ($zips | Select-Object -Skip $keep)) {
      Add-Found 'this machine' 'old backup' $z.FullName $z.Length
      Say ("  {0,10:n1} MB  {1}" -f (Mb $z.Length), $z.Name)
    }
  }
}

if ($Temp) {
  Head 'Temp files on this machine'
  foreach ($dir in @($env:TEMP, 'C:\Windows\Temp')) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter 'thornswood*' -Force -EA SilentlyContinue)) {
      $b = if ($f.PSIsContainer) { Folder-Bytes $f.FullName } else { $f.Length }
      Add-Found 'this machine' 'temp' $f.FullName $b
      Say ("  {0,10:n1} MB  {1}" -f (Mb $b), $f.FullName)
    }
  }
  if (-not ($found | Where-Object { $_.What -eq 'temp' -and $_.Where -eq 'this machine' })) { Say '  none' 'DarkGray' }
}

# ------------------------------------------------------------ the server ---
if ($Installers -or $Temp) {
  Head 'On the server'
  $lines = Remote @"
`$ErrorActionPreference = 'Continue'
foreach (`$d in @('C:\Thornswood-Docs\public\downloads', 'C:\Windows\Temp')) {
  if (-not (Test-Path `$d)) { continue }
  foreach (`$f in (Get-ChildItem `$d -Force -EA SilentlyContinue)) {
    if (`$f.PSIsContainer) { continue }
    if (`$f.Name -notmatch '(?i)(thornswood|setup|pack-|\.zip`$|\.exe`$)') { continue }
    'FILE|' + `$f.FullName + '|' + `$f.Length + '|' + `$f.LastWriteTime.ToString('yyyy-MM-dd')
  }
}
foreach (`$d in (Get-ChildItem 'C:\' -Directory -EA SilentlyContinue)) {
  `$lg = Join-Path `$d.FullName 'server.log'
  if (Test-Path `$lg) { `$i = Get-Item `$lg; 'FILE|' + `$i.FullName + '|' + `$i.Length + '|' + `$i.LastWriteTime.ToString('yyyy-MM-dd') }
}
"@
  $any = $false
  foreach ($l in $lines) {
    $bits = "$l" -split '\|'
    if ($bits.Count -lt 4 -or $bits[0] -ne 'FILE') { continue }
    $any = $true
    Add-Found 'the server' 'server leftover' $bits[1] ([int64]$bits[2])
    Say ("  {0,10:n1} MB  {1}   {2}" -f (Mb ([int64]$bits[2])), $bits[1], $bits[3])
  }
  if (-not $any) { Say '  nothing worth removing' 'DarkGray' }
}

# ----------------------------------------------------------------- github ---
if ($Github) {
  Head 'GitHub release assets'
  $gh = Get-Command gh -EA SilentlyContinue
  if (-not $gh) {
    Say '  gh is not installed, so the repositories were not looked at.' 'Yellow'
    Say '  winget install --id GitHub.cli' 'DarkGray'
  }
  else {
    foreach ($r in @(@($Repo, $SourceRepo) | Where-Object { $_ })) {
      Say "  $r" 'White'
      $json = & gh api "repos/$r/releases?per_page=100" 2>$null
      if ($LASTEXITCODE -ne 0 -or -not $json) { Say '    could not read it, skipping' 'Yellow'; continue }
      $rels = $json | ConvertFrom-Json
      $rels = @($rels | Sort-Object { [datetime]$_.created_at } -Descending)
      if ($rels.Count -eq 0) { Say '    no releases' 'DarkGray'; continue }
      $keep = [Math]::Min($KeepReleases, $rels.Count)
      Say ("    {0} release(s), keeping the newest {1}" -f $rels.Count, $keep) 'DarkGray'
      foreach ($rel in ($rels | Select-Object -Skip $keep)) {
        $b = 0
        foreach ($a in @($rel.assets)) { $b += [int64]$a.size }
        if ($b -eq 0) { continue }
        Add-Found 'github' "release $r" ("$r#" + $rel.tag_name) $b
        Say ("    {0,10:n1} MB  {1}   {2}" -f (Mb $b), $rel.tag_name, ([datetime]$rel.created_at).ToString('dd MMM'))
      }
    }
  }
}

# ------------------------------------------------------------ the totals ---
Head 'Altogether'
if ($found.Count -eq 0) {
  Say '  Nothing to clean up.' 'Green'
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}
foreach ($g in ($found | Group-Object Where | Sort-Object Name)) {
  $b = ($g.Group | Measure-Object -Property Bytes -Sum).Sum
  Say ("  {0,10:n2} GB  {1}   ({2} item(s))" -f (Gb $b), $g.Name, $g.Count)
}
$total = ($found | Measure-Object -Property Bytes -Sum).Sum
Say ("  {0,10:n2} GB  in total" -f (Gb $total)) 'Green'

if ($ServerSaves) {
  Head 'The server wipe, separately'
  Say '  Asked for with -ServerSaves. This is every character anybody has made.' 'Yellow'
  $lines = Remote @"
`$ErrorActionPreference = 'Continue'
foreach (`$d in (Get-ChildItem 'C:\' -Directory -EA SilentlyContinue)) {
  foreach (`$n in @('world', 'private\characters.json', 'data\online.json')) {
    `$p = Join-Path `$d.FullName `$n
    if (Test-Path `$p) {
      `$b = 0
      if ((Get-Item `$p).PSIsContainer) {
        foreach (`$f in (Get-ChildItem `$p -Recurse -File -EA SilentlyContinue)) { `$b += `$f.Length }
      } else { `$b = (Get-Item `$p).Length }
      'SAVE|' + `$p + '|' + `$b
    }
  }
}
"@
  foreach ($l in $lines) {
    $bits = "$l" -split '\|'
    if ($bits.Count -lt 3 -or $bits[0] -ne 'SAVE') { continue }
    Say ("  {0,10:n1} MB  {1}" -f (Mb ([int64]$bits[2])), $bits[1]) 'Yellow'
  }
  Write-Host ''
  Say '  Not deleted by this script. Take a backup first, then wipe it from the' 'Yellow'
  Say '  server with the machine stopped, or characters come back from memory.' 'Yellow'
}

# ---------------------------------------------------------------- delete ---
if (-not $Delete) {
  Write-Host ''
  Say '  Nothing was deleted. Run it again with -Delete to remove exactly the' 'DarkGray'
  Say '  items above, and nothing else.' 'DarkGray'
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

Write-Host ''
Say ("  About to delete {0} item(s), {1:n2} GB." -f $found.Count, (Gb $total)) 'Red'
$typed = Read-Host '  Type DELETE to go ahead'
if ($typed -cne 'DELETE') { Die 'Not deleted.' }

Head 'Deleting'
$goneBytes = 0; $goneCount = 0; $failed = 0
foreach ($f in $found) {
  try {
    if ($f.Where -eq 'this machine') {
      if (Test-Path -LiteralPath $f.Path) {
        Remove-Item -LiteralPath $f.Path -Recurse -Force -ErrorAction Stop
      }
    }
    elseif ($f.Where -eq 'the server') {
      [void](Remote "Remove-Item -LiteralPath '$($f.Path)' -Recurse -Force -EA SilentlyContinue")
    }
    else {
      $bits = $f.Path -split '#'
      & gh release delete $bits[1] --repo $bits[0] --yes --cleanup-tag 2>&1 | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "gh release delete exited with $LASTEXITCODE" }
    }
    $goneBytes += $f.Bytes; $goneCount++
    Say ("  gone   {0}" -f $f.Path) 'Green'
  }
  catch {
    $failed++
    Say ("  FAILED {0}" -f $f.Path) 'Red'
    Say ("         " + $_.Exception.Message) 'DarkGray'
  }
}

Head 'Done'
Say ("  {0} item(s) removed, {1:n2} GB back" -f $goneCount, (Gb $goneBytes)) 'Green'
if ($failed) { Say ("  {0} could not be removed, listed above" -f $failed) 'Yellow' }

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
