param([string]$Scratch)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
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
    # Compile the same helper at C# 5 as well: scripts\mods\LoadOrder.ps1
    # loads this file with Add-Type, which in Windows PowerShell is the .NET
    # Framework compiler and stops at C# 5 (Developer-Guide.md, Settled design).
    if ($OnWindows) {
        $dll=Join-Path $Scratch 'VortexProfileState.dll'
        & $LauncherCsc /noconfig /nologo /target:library "/langversion:5" ("/out:"+$dll) /reference:System.dll /reference:System.Core.dll /reference:System.Xml.dll /reference:System.Runtime.Serialization.dll (Join-Path $repo 'launcher\app\VortexProfileState.cs')
        if($LASTEXITCODE -or -not(Test-Path -LiteralPath $dll)){throw 'Framework compilation failed'}
    } else {
        Write-Host 'SKIP  VortexProfileState.cs compiled at C# 5, the most Windows PowerShell''s Add-Type takes: the build''s compiler (the Build Tools'' csc) is only on Windows'
    }
    Write-Host ($count.ToString()+' profile cases'+$(if($OnWindows){' and framework compilation'}else{''})+' passed')
} finally {$env:APPDATA=$oldAppData}
