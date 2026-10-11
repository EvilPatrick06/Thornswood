# Generated covered body outputs must override collection defaults in updates
# and installers. A nearby ungenerated mod asset remains collection-owned.
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\release\Ship-Rules.ps1')
$pass=0; $fail=0
function Yes([string]$what,[bool]$ok){if($ok){$script:pass++;Write-Host "PASS $what"}else{$script:fail++;Write-Host "FAIL $what"}}
$bodies=@('femalebody_0.nif','femalebody_1.nif','femalebodyastrid_0.nif','femalebodyastrid_1.nif','malebody_0.nif','malebody_1.nif') | ForEach-Object {'Data\meshes\actors\character\character assets\'+$_}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('thornswood-body-shipping-'+[guid]::NewGuid().ToString('N'))
$ProfileDir=Join-Path $fixture 'Profile'
$game=Join-Path $fixture 'Game'
$receipt=Join-Path $ProfileDir 'OwnGame\generated.txt'
New-Item -ItemType Directory -Path (Split-Path $receipt) -Force | Out-Null
$rows=@()
foreach($b in $bodies){
  $file=Join-Path $game $b
  New-Item -ItemType Directory -Path (Split-Path $file) -Force | Out-Null
  [IO.File]::WriteAllText($file,'covered output fixture '+$b)
  $rows+='file '+(Get-FileHash $file).Hash.ToLowerInvariant()+' '+$b
}
[IO.File]::WriteAllLines($receipt,$rows)
Assert-ShipGeneratedBodyFiles $game $ProfileDir
Yes 'all six body hashes match the actual receipt' $true
foreach($scriptName in 'Publish-Update.ps1','Package-Thornswood.ps1'){
  $tokens=$null; $errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo ('scripts\release\'+$scriptName)),[ref]$tokens,[ref]$errors)
  Yes "$scriptName parses" ($errors.Count -eq 0)
  $fn=$ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-FromCollection'},$true) | Select-Object -First 1
  $vortexFiles=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $assignment=$ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$shipGeneratedFiles'},$true) | Select-Object -First 1
  . ([scriptblock]::Create($assignment.Extent.Text))
  Yes "$scriptName checks generated provenance before scanning" ($ast.Extent.Text.Contains('Assert-ShipGeneratedBodies $GameDir $ProfileDir'))
  foreach($b in $bodies){[void]$vortexFiles.Add($b)}
  $other='Data\meshes\actors\character\character assets\femalehands_0.nif'
  [void]$vortexFiles.Add($other)
  . ([scriptblock]::Create($fn.Extent.Text))
  foreach($b in $bodies){
    Yes "$scriptName includes the generated $([IO.Path]::GetFileName($b)) beyond the collection" (-not (Test-FromCollection $b))
    Yes "$scriptName does not discard that generated body as somebody else's loose art" (-not (Test-ShipNotOurs $b 2))
  }
  Yes "$scriptName still excludes an ungenerated collection asset" (Test-FromCollection $other)
  Yes "$scriptName recognizes generated output case-insensitively" (-not (Test-FromCollection $bodies[0].ToUpperInvariant()))
}
function Refuses([string]$what,[scriptblock]$action,[string]$reason){$refused=$false;try{& $action}catch{$refused=(-not $reason -or $_.Exception.Message -like $reason)};Yes $what $refused}
[IO.File]::WriteAllLines($receipt,$rows[1..5])
Refuses 'a partial body receipt is refused' {Assert-ShipGeneratedBodyFiles $game $ProfileDir}
[IO.File]::WriteAllLines($receipt,($rows+$rows[0]))
Refuses 'a duplicate body receipt is refused' {Assert-ShipGeneratedBodyFiles $game $ProfileDir}
[IO.File]::WriteAllLines($receipt,($rows+$rows[0].Replace('\','/')))
Refuses 'an alias of an already recorded destination is refused' {Assert-ShipGeneratedBodyFiles $game $ProfileDir} '*exactly one*'
[IO.File]::WriteAllLines($receipt,$rows)
[IO.File]::WriteAllText((Join-Path $game $bodies[0]),'overwritten collection default')
Refuses 'a body changed after generation is refused' {Assert-ShipGeneratedBodyFiles $game $ProfileDir}
[IO.File]::WriteAllText((Join-Path $game $bodies[0]),'covered output fixture '+$bodies[0])
. (Join-Path $repo 'scripts\mods\Generated.ps1')
[IO.File]::WriteAllText((Join-Path $ProfileDir 'OwnGame\files.txt'),'')
$inputs=Get-GeneratedInputs $fixture (Join-Path $repo 'records\generated.json')
$outputs=@($bodies | ForEach-Object {[pscustomobject]@{Rel=$_;Sha=(Get-FileHash (Join-Path $game $_)).Hash.ToLowerInvariant()}})
Write-GeneratedRecord $receipt $game $inputs $outputs
Assert-ShipGeneratedBodies $game $ProfileDir
Yes 'a complete fixture with current input provenance first succeeds' $true
$complete=[IO.File]::ReadAllLines($receipt)
[IO.File]::WriteAllLines($receipt,@($complete | Where-Object {$_ -notmatch '^game '}))
Refuses 'missing source provenance is refused' {Assert-ShipGeneratedBodies $game $ProfileDir} '*exactly one source*'
[IO.File]::WriteAllLines($receipt,$complete)
Refuses 'a genuinely different source game folder is refused' {Assert-ShipGeneratedBodies (Join-Path $fixture 'DifferentGame') $ProfileDir} '*missing*'
# Copy the six fixture outputs, so this fails for source identity, not absence.
$different=Join-Path $fixture 'DifferentGame'
foreach($b in $bodies){$dst=Join-Path $different $b;New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null;Copy-Item -LiteralPath (Join-Path $game $b) -Destination $dst}
Refuses 'matching body bytes in another source folder are refused' {Assert-ShipGeneratedBodies $different $ProfileDir} '*own game folder*'
[IO.File]::WriteAllText((Join-Path $ProfileDir 'OwnGame\plugins.txt'),'*ChangedInput.esp')
Refuses 'changed generated inputs are refused' {Assert-ShipGeneratedBodies $game $ProfileDir} '*Generated files are stale*'
# The fixture is preserved for inspection; it contains no account data.
Write-Host "$pass passed, $fail failed"
if($fail){exit 1}
