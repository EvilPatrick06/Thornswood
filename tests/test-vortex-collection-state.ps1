param([string]$Scratch)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if(-not $Scratch){$Scratch=Join-Path ([IO.Path]::GetTempPath()) ('thornswood-collection-state-'+[guid]::NewGuid().ToString('N'))}
New-Item -ItemType Directory -Path $Scratch -Force | Out-Null
& python (Join-Path $PSScriptRoot 'fixtures\vortex-collection-state.py') $Scratch
if($LASTEXITCODE){throw 'Collection fixture generation failed'}
. (Join-Path $repo 'scripts\mods\LoadOrder.ps1')
$oldAppData=$env:APPDATA
$cases=@{
 'compressed'=2; 'updated'=3; 'downgraded'=1; 'deleted'=0; 'revision-deleted'=0; 'other-slug'=0;
 'mixed'=2; 'latest-not-installed'=2; 'obsolete'=2; 'authoring'=2; 'authoring-version'=2; 'authoring-numeric-version'=2;
 'cache-only'=0; 'ordinary-mod-cache'=0; 'other-author'=0; 'author-link-deleted'=0;
 'negative'=0; 'zero'=0; 'fraction'=0; 'overflow'=0; 'string-revision'=0; 'corrupt'=0; 'partial'=0
}
$count=0
try {
 # Exercise the publishing entry point first: the old raw-byte reader must fail.
 foreach($case in @('compressed')+@($cases.Keys | Where-Object {$_ -ne 'compressed'} | Sort-Object)){
  $env:APPDATA=Join-Path $Scratch ('collection-'+$case)
  $got=Get-CollectionRevisionFromState '7essxf'
  if($got -ne $cases[$case]){throw ('Collection '+$case+': expected '+$cases[$case]+', got '+$got)}
  $count++;Write-Host ('PASS publishing '+$case)
 }
 $csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
 $dll=Join-Path $Scratch 'VortexCollectionState.dll'
 & $csc /noconfig /nologo /target:library /langversion:5 ("/out:"+$dll) /reference:System.dll /reference:System.Core.dll /reference:System.Xml.dll /reference:System.Runtime.Serialization.dll (Join-Path $repo 'launcher\app\VortexProfileState.cs')
 if($LASTEXITCODE){throw 'Framework compilation failed'}
 foreach($case in $cases.Keys | Sort-Object){
  $state=Join-Path (Join-Path $Scratch ('collection-'+$case)) 'Vortex\state.v2'
  $got=0
  try{$got=[Thornswood.VortexProfileState]::CollectionRevision($state,'7essxf')}catch{if($case -notin @('corrupt','partial')){throw}}
  if($got -ne $cases[$case]){throw ('Shared C# reader '+$case+' differs')}
  $count++;Write-Host ('PASS reader '+$case)
 }
 Write-Host ($count.ToString()+' collection cases and C# 5 compilation passed')
}finally{$env:APPDATA=$oldAppData}
