param([string]$Scratch)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the .NET SDK the launcher builds with (#498, #4823)
$repo=Split-Path -Parent $PSScriptRoot
if(-not $Scratch){$Scratch=Join-Path ([IO.Path]::GetTempPath()) ('thornswood-vortex-state-'+[guid]::NewGuid().ToString('N'))}
New-Item -ItemType Directory -Path $Scratch -Force | Out-Null
& python (Join-Path $PSScriptRoot 'fixtures\vortex-profile-state.py') $Scratch
if($LASTEXITCODE){throw 'Fixture generation failed'}
. (Join-Path $repo 'scripts\mods\LoadOrder.ps1')
$oldAppData=$env:APPDATA
$count=0
function Check($case,$expected,$name='Thornswood',$throws=$false){
    $env:APPDATA=Join-Path $Scratch $case
    $got=$null; $didThrow=$false
    try{$got=Get-VortexProfileDir $name}catch{$didThrow=$true}
    if($didThrow -ne $throws -or (-not $throws -and (($expected -eq $null -and $got) -or ($expected -ne $null -and (Split-Path -Leaf $got) -ne $expected)))) {
        throw ('Profile check failed: '+$case)
    }
    $script:count++; Write-Host ('PASS '+$case)
}
try {
    Check 'compressed' 'active'
    Check 'renamed' $null
    Check 'deleted' $null
    Check 'different-game' $null
    Check 'duplicate' $null 'Thornswood' $true
    Check 'escaped' 'active' 'Thorns"wood'
    Check 'obsolete' $null
    Check 'corrupt' $null 'Thornswood' $true
    Check 'partial' $null 'Thornswood' $true
    Check 'fragmented' $null
    Check 'unknown-manifest' $null 'Thornswood' $true
    Check 'missing-manifest-fields' $null 'Thornswood' $true
    Check 'current-no-newline' $null 'Thornswood' $true
    Check 'duplicate-missing-list' $null 'Thornswood' $true
    Check 'invalid-kind' $null 'Thornswood' $true
    Check 'equal-conflict' $null 'Thornswood' $true
    Check 'equal-identical' 'active'
    Check 'short-header' $null 'Thornswood' $true
    Check 'interrupted' $null 'Thornswood' $true
    Check 'two-large-fragments' $null
    Check 'trailing-json' $null 'Thornswood' $true
    Check 'number-json' $null 'Thornswood' $true
    $locked=Join-Path $Scratch 'compressed\Vortex\state.v2\MANIFEST-000002'
    $handle=[IO.File]::Open($locked,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{Check 'compressed' $null 'Thornswood' $true}finally{$handle.Dispose()}
    # Compile the same helper at C# 5 against the .NET Framework as well:
    # scripts\mods\LoadOrder.ps1 loads this file with Add-Type, which in
    # Windows PowerShell is the .NET Framework compiler and stops at C# 5
    # (Developer-Guide.md, Settled design). The .NET SDK the launcher builds
    # with fetches the Framework's reference assemblies on any machine, so
    # this runs everywhere (#4823).
    $fx=Join-Path $Scratch 'framework'
    New-Item -ItemType Directory -Path $fx -Force | Out-Null
    $cs=[IO.Path]::Combine($repo,'launcher','app','VortexProfileState.cs')
    $proj=@(
        '<Project Sdk="Microsoft.NET.Sdk">',
        '  <PropertyGroup>',
        '    <TargetFramework>net48</TargetFramework>',
        '    <LangVersion>5</LangVersion>',
        '    <OutputType>Library</OutputType>',
        '    <EnableDefaultItems>false</EnableDefaultItems>',
        '  </PropertyGroup>',
        '  <ItemGroup>',
        ('    <Compile Include="'+[Security.SecurityElement]::Escape($cs)+'" />'),
        '    <Reference Include="System.Xml" />',
        '  </ItemGroup>',
        '</Project>') -join "`n"
    [IO.File]::WriteAllText((Join-Path $fx 'VortexProfileState.csproj'),$proj)
    if(-not(Test-Path -LiteralPath $LauncherDotnet)){throw ('The .NET SDK the launcher builds with is not on this machine ('+$LauncherDotnet+')')}
    $bin=Join-Path $fx 'bin'
    $said=& $LauncherDotnet build (Join-Path $fx 'VortexProfileState.csproj') -nologo -v:q '-clp:NoSummary;ErrorsOnly' -o $bin 2>&1 | Out-String
    if($LASTEXITCODE -or -not(Test-Path -LiteralPath (Join-Path $bin 'VortexProfileState.dll'))){Write-Host $said.Trim(); throw 'Framework compilation failed'}
    Write-Host 'PASS framework compilation: VortexProfileState.cs at C# 5 against the .NET Framework'
    Write-Host ($count.ToString()+' profile cases and framework compilation passed')
} finally {$env:APPDATA=$oldAppData}
