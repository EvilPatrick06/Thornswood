<#
  Compare-NexusLayout.ps1

  Says whether a collection revision's layout record (what
  Install-NexusRevision.ps1 writes) is the same as another layout record, or
  the same as what Vortex deployed into a game folder, file by file and
  plugin by plugin (#2969). It reads; it writes nothing but -Out.

      pwsh scripts/release/Compare-NexusLayout.ps1 -Record <folder> -With <folder>
      pwsh scripts/release/Compare-NexusLayout.ps1 -Record <folder> -Vortex <game folder>

  WHY. Install-NexusRevision.ps1 lays a revision out without Vortex, and a
  cloud session can run it. Before anything reads its record in place of
  Vortex's deployment, the two have to be shown to be the same. The only
  Vortex deployment of the collection is One's Steam copy, so -Vortex runs
  on One; -With runs anywhere, and two records whose files.txt have the same
  sha256 laid out the same files (the record is written byte for byte the
  same on Windows and Linux).

  -With compares two records: files.txt path by path (sha256 and size), and
  the plugin order of plugins.txt.

  -Vortex reads Vortex's own records of what it deployed,
  <game>\Data\vortex.deployment.json and, for the script extender and other
  game-folder mods, <game>\vortex.deployment.dinput.json, hashes each file it
  names in the game folder, and compares them with files.txt. Files Vortex
  deployed that the layout does not have are grouped by the Vortex mod they
  came from, since a mod made on One (generated files, a hand-made mod) is
  not in the collection. The plugin order is compared with -Plugins, the
  plugins.txt Vortex writes for the game (%LOCALAPPDATA%\Skyrim Special
  Edition\plugins.txt unless said otherwise).

  Exit 0 when the files and the plugin order are the same, 1 when anything
  differs or cannot be read. Every difference is printed, the first 40 of
  each kind on screen and all of them in -Out when it is given.

.PARAMETER Record
  The layout record: the folder holding files.txt, plugins.txt and
  layout.json (a -Record folder, or <game>\Thornswood Layout).

.PARAMETER With
  Another layout record to compare with.

.PARAMETER Vortex
  A game folder Vortex deployed the collection into.

.PARAMETER Plugins
  With -Vortex: the plugins.txt to compare the plugin order with.

.PARAMETER Out
  A text file for every difference.

.PARAMETER NoPause
  Does not wait for Enter at the end.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Record,
  [string]$With,
  [string]$Vortex,
  [string]$Plugins,
  [string]$Out,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) {
  Write-Host ''
  Write-Host "STOP. $m" -ForegroundColor Red
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}
function Join-Rel([string]$root, [string]$rel) { return (Join-Path $root ($rel.Replace('\', [IO.Path]::DirectorySeparatorChar))) }

if ([bool]$With -eq [bool]$Vortex) { Die 'Give one of -With (another layout record) or -Vortex (a game folder Vortex deployed into).' }

# files.txt: sha256, size, Nexus file id, path; one line each.
function Read-Files([string]$dir) {
  $f = Join-Path $dir 'files.txt'
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Die ('There is no files.txt in ' + $dir + ', so it is not a layout record.') }
  $all = [IO.File]::ReadAllLines($f)
  if (-not $all.Count -or -not $all[0].StartsWith('# Install-NexusRevision.ps1:') -or $all[0] -match 'Being placed') { Die ($f + ' is not a whole layout record (its first line says ' + $(if ($all.Count) { $all[0] } else { 'nothing' }) + ').') }
  $map = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($line in $all) {
    if (-not $line -or $line.StartsWith('#')) { continue }
    $c = $line.Split("`t")
    if ($c.Count -ne 4) { Die ($f + ' has a line that is not sha256, size, file id and path: ' + $line) }
    $map[$c[3]] = [pscustomobject]@{ Sha256 = $c[0]; Size = [long]$c[1]; FileId = $c[2]; Rel = $c[3] }
  }
  $sha = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant()
  return [pscustomobject]@{ Map = $map; Sha256 = $sha; Head = $all[0] }
}
# A plugins.txt as the game reads it: names in order, a star for enabled.
function Read-Plugins([string]$f) {
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Die ('There is no ' + $f + '.') }
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($line in [IO.File]::ReadAllLines($f)) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('#')) { continue }
    $on = $t.StartsWith('*')
    $list.Add([pscustomobject]@{ Name = $t.TrimStart('*'); Enabled = $on })
  }
  return $list
}
# The mod names layout.json gives each file id, for saying where a file came from.
function Read-Mods([string]$dir) {
  $names = @{}
  $lj = Join-Path $dir 'layout.json'
  if (Test-Path -LiteralPath $lj) { foreach ($m in @((Get-Content -Raw -LiteralPath $lj | ConvertFrom-Json).mods)) { $names[[string]$m.fileId] = [string]$m.name } }
  return $names
}

$Record = [IO.Path]::GetFullPath($Record)
$a = Read-Files $Record
$names = Read-Mods $Record
Write-Host ''
Write-Host '  THORNSWOOD  -  a collection layout compared' -ForegroundColor White
Say ('  record: ' + $Record)
Say ('    ' + $a.Head.Substring(2)) 'DarkGray'
Say ('    ' + $a.Map.Count + ' files, files.txt sha256 ' + $a.Sha256) 'DarkGray'

$report = New-Object System.Collections.Generic.List[string]
$diffs = 0
# A kind of difference, the first 40 on screen. -Note is for what differs
# only in where it came from, not in what is laid out: listed, not counted.
function Show([string]$title, [string[]]$items, [switch]$Note) {
  if (-not $items.Count) { return }
  $show = 40
  if ($Note) { $show = 5; Say ('  ' + $title + ': ' + $items.Count + ', not a difference in what is laid out') 'DarkGray' }
  else { $script:diffs += $items.Count; Say ('  ' + $title + ': ' + $items.Count) 'Yellow' }
  foreach ($i in ($items | Select-Object -First $show)) { Say ('    ' + $i) }
  if ($items.Count -gt $show) { Say ('    and ' + ($items.Count - $show) + ' more' + $(if ($Out) { ', all in ' + $Out } else { '; give -Out for all of them' })) 'DarkGray' }
  $report.Add(''); $report.Add($title + ': ' + $items.Count)
  foreach ($i in $items) { $report.Add('  ' + $i) }
}
function From([string]$fileId) { if ($names.ContainsKey($fileId)) { return $names[$fileId] + ' (file ' + $fileId + ')' }; return 'file ' + $fileId }

if ($With) {
  $With = [IO.Path]::GetFullPath($With)
  $b = Read-Files $With
  $bNames = Read-Mods $With
  Say ('  with:   ' + $With)
  Say ('    ' + $b.Head.Substring(2)) 'DarkGray'
  Say ('    ' + $b.Map.Count + ' files, files.txt sha256 ' + $b.Sha256) 'DarkGray'
  Head 'Files'
  if ($a.Sha256 -eq $b.Sha256) { Say '  files.txt is the same file in both: every path, sha256, size and file id.' 'Green' }
  $onlyA = @(); $onlyB = @(); $differ = @(); $moved = @()
  foreach ($k in $a.Map.Keys) {
    $x = $a.Map[$k]
    if (-not $b.Map.ContainsKey($k)) { $onlyA += ($x.Rel + '  from ' + (From $x.FileId)); continue }
    $y = $b.Map[$k]
    if ($x.Sha256 -ne $y.Sha256 -or $x.Size -ne $y.Size) { $differ += ($x.Rel + '  ' + (From $x.FileId) + ' / file ' + $y.FileId) }
    elseif ($x.FileId -ne $y.FileId) { $moved += ($x.Rel + '  the same bytes, from file ' + $x.FileId + ' / ' + $y.FileId) }
    elseif ($x.Rel -cne $y.Rel) { $moved += ($x.Rel + '  the same bytes, named ' + $y.Rel) }
  }
  foreach ($k in $b.Map.Keys) { if (-not $a.Map.ContainsKey($k)) { $y = $b.Map[$k]; $onlyB += ($y.Rel + '  from file ' + $y.FileId + $(if ($bNames.ContainsKey($y.FileId)) { ' (' + $bNames[$y.FileId] + ')' } else { '' })) } }
  Show 'only in the record' @($onlyA | Sort-Object)
  Show 'only in the other' @($onlyB | Sort-Object)
  Show 'different bytes' @($differ | Sort-Object)
  Show 'the same bytes, from another file id or named in another case' @($moved | Sort-Object) -Note
  $pa = Read-Plugins (Join-Path $Record 'plugins.txt')
  $pb = Read-Plugins (Join-Path $With 'plugins.txt')
}
else {
  $Vortex = [IO.Path]::GetFullPath($Vortex)
  Say ('  Vortex: ' + $Vortex)
  $deployed = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
  $recs = @(@((Join-Path (Join-Path $Vortex 'Data') 'vortex.deployment.json'), 'Data\'), @((Join-Path $Vortex 'vortex.deployment.dinput.json'), ''))
  if (-not (Test-Path -LiteralPath $recs[0][0])) { Die ('There is no ' + $recs[0][0] + ', so Vortex has not deployed into ' + $Vortex + '.') }
  foreach ($r in $recs) {
    if (-not (Test-Path -LiteralPath $r[0])) { continue }
    $doc = ([IO.File]::ReadAllText($r[0]) -replace '^﻿', '') | ConvertFrom-Json
    Say ('    ' + (Split-Path -Leaf $r[0]) + ': ' + @($doc.files).Count + ' files, deployed by ' + [string]$doc.deploymentMethod) 'DarkGray'
    foreach ($vf in @($doc.files)) {
      $rel = $r[1] + ([string]$vf.relPath).TrimStart('\', '/').Replace('/', '\')
      $deployed[$rel] = [pscustomobject]@{ Rel = $rel; Source = [string]$vf.source }
    }
  }
  Head 'Files'
  Say ('  hashing the ' + $deployed.Count + ' files Vortex deployed') 'DarkGray'
  $onlyA = @(); $onlyV = @{}; $differ = @(); $gone = @(); $same = 0
  foreach ($d in $deployed.Values) {
    $full = Join-Rel $Vortex $d.Rel
    if (-not $a.Map.ContainsKey($d.Rel)) {
      if (-not $onlyV.ContainsKey($d.Source)) { $onlyV[$d.Source] = New-Object System.Collections.Generic.List[string] }
      $onlyV[$d.Source].Add($d.Rel); continue
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { $gone += ($d.Rel + '  (' + $d.Source + ')'); continue }
    $x = $a.Map[$d.Rel]
    $len = (Get-Item -LiteralPath $full).Length
    if ($len -ne $x.Size -or (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() -ne $x.Sha256) { $differ += ($d.Rel + '  layout: ' + (From $x.FileId) + ', Vortex: ' + $d.Source) }
    else { $same++ }
  }
  foreach ($k in $a.Map.Keys) { if (-not $deployed.ContainsKey($k)) { $x = $a.Map[$k]; $onlyA += ($x.Rel + '  from ' + (From $x.FileId)) } }
  Say ('  ' + $same + ' files are the same in both') 'Green'
  Show 'only in the layout' @($onlyA | Sort-Object)
  Show 'only in Vortex''s deployment, by the Vortex mod they came from' @($onlyV.Keys | Sort-Object | ForEach-Object { $_ + ': ' + $onlyV[$_].Count + ' files, ' + ((@($onlyV[$_]) | Sort-Object | Select-Object -First 3) -join ', ') + $(if ($onlyV[$_].Count -gt 3) { ', ...' } else { '' }) })
  Show 'in Vortex''s record but not in the game folder' @($gone | Sort-Object)
  Show 'different bytes' @($differ | Sort-Object)
  if ($onlyV.Count -and $Out) { $report.Add(''); $report.Add('every file only in Vortex''s deployment:'); foreach ($s in ($onlyV.Keys | Sort-Object)) { foreach ($f in ($onlyV[$s] | Sort-Object)) { $report.Add('  ' + $f + '  (' + $s + ')') } } }
  if (-not $Plugins) {
    if (-not $env:LOCALAPPDATA) { Die 'There is no %LOCALAPPDATA% here to find the game''s plugins.txt; give it with -Plugins.' }
    $Plugins = Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition\plugins.txt'
  }
  $pa = Read-Plugins (Join-Path $Record 'plugins.txt')
  $pb = Read-Plugins $Plugins
  Say ('  plugins: ' + $Plugins) 'DarkGray'
}

Head 'Plugins'
$ia = @{}; for ($i = 0; $i -lt $pa.Count; $i++) { $ia[$pa[$i].Name.ToLowerInvariant()] = $i }
$ib = @{}; for ($i = 0; $i -lt $pb.Count; $i++) { $ib[$pb[$i].Name.ToLowerInvariant()] = $i }
$both = @($pa | Where-Object { $ib.ContainsKey($_.Name.ToLowerInvariant()) })
# The order that matters is the one the game loads: the plugins both name
# and both enable. Where a disabled plugin sits loads nothing.
$onA = @($both | Where-Object { $_.Enabled -and $pb[$ib[$_.Name.ToLowerInvariant()]].Enabled })
$onB = @($pb | Where-Object { $_.Enabled -and $ia.ContainsKey($_.Name.ToLowerInvariant()) -and $pa[$ia[$_.Name.ToLowerInvariant()]].Enabled })
$order = @()
for ($i = 0; $i -lt $onA.Count; $i++) {
  if ($onA[$i].Name -ine $onB[$i].Name) { $order += ('position ' + ($i + 1) + ' of the ' + $onA.Count + ' plugins both enable: ' + $onA[$i].Name + ' here, ' + $onB[$i].Name + ' there'); break }
}
$state = @($both | Where-Object { $_.Enabled -ne $pb[$ib[$_.Name.ToLowerInvariant()]].Enabled } | ForEach-Object { $_.Name + ' is ' + $(if ($_.Enabled) { 'enabled here and disabled there' } else { 'disabled here and enabled there' }) })
Say ('  ' + $pa.Count + ' plugins in the record, ' + $pb.Count + ' in the other, ' + $both.Count + ' in both')
Show 'plugins only in the record' @($pa | Where-Object { -not $ib.ContainsKey($_.Name.ToLowerInvariant()) } | ForEach-Object { $_.Name })
Show 'plugins only in the other' @($pb | Where-Object { -not $ia.ContainsKey($_.Name.ToLowerInvariant()) } | ForEach-Object { $_.Name })
Show 'the first place the load order differs' $order
Show 'enabled in one and not the other' $state

if ($Out) {
  $Out = [IO.Path]::GetFullPath($Out)
  $report.Insert(0, 'Compare-NexusLayout.ps1: ' + $Record + ' (files.txt sha256 ' + $a.Sha256 + ') with ' + $(if ($With) { $With } else { 'Vortex''s deployment in ' + $Vortex }))
  [IO.File]::WriteAllText($Out, (($report -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
}
Write-Host ''
if ($diffs) { Say ($diffs.ToString() + ' differences.') 'Yellow'; $code = 1 }
else { Say 'The same: every file and the plugin order.' 'Green'; $code = 0 }
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
exit $code
