<#
  Find-MSBuild.ps1
  Says where the MSBuild that builds launcher\app\Thornswood.csproj is, and
  whether this machine has the .NET Framework 4.8.1 reference assemblies it
  builds against (issue #498).

  Reads only. It installs nothing and builds nothing.

    .\scripts\release\Find-MSBuild.ps1           prints the MSBuild.exe path, or exits 1 saying what is missing
    .\scripts\release\Find-MSBuild.ps1 -Report   one line for each thing it looked at, exit 0 or 1 the same way

  What it needs, and how a machine gets it, is Developer-Guide.md "Setting up a
  machine": Visual Studio 2022 (any edition, or the free Build Tools) with the
  MSBuild component and the .NET Framework 4.8.1 targeting pack. The in-box
  MSBuild under Windows\Microsoft.NET is not it: that one drives the in-box
  csc, which knows nothing past C# 5. Since the switch (#498) the launcher is
  built only this way, and the harnesses compile launcher files with the
  Roslyn csc beside this MSBuild (Find-ThornswoodMSBuild's Csc).

  Dot-source it for the function alone:  . .\scripts\release\Find-MSBuild.ps1 -Load
#>
[CmdletBinding()]
param(
    [switch]$Report,
    [switch]$Load
)

function Find-ThornswoodMSBuild {
    # Returns @{ MSBuild = <path or $null>; Csc = <path or $null>; RefAssemblies = <path or $null>; VsWhere = <path or $null>; Instance = <name or $null> }
    # Csc is the Roslyn compiler that MSBuild itself runs (Bin\Roslyn\csc.exe
    # beside MSBuild.exe), the one the harnesses compile launcher files with,
    # so a test and the build cannot be on different compilers (#498).
    $r = @{ MSBuild = $null; Csc = $null; RefAssemblies = $null; VsWhere = $null; Instance = $null }
    $pf86 = ${env:ProgramFiles(x86)}
    if (-not $pf86) { $pf86 = $env:ProgramFiles }
    # Off Windows neither is set, so there is no Visual Studio to find; the
    # join below stopped on the null before saying so (#2989).
    if (-not $pf86) { return $r }
    $vswhere = Join-Path $pf86 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $r.VsWhere = $vswhere
        # -products * takes Build Tools as well as the editions with the editor.
        # Newest first; -find gives the amd64-neutral Bin\MSBuild.exe.
        $found = @(& $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' 2>$null |
                   Where-Object { $_ -and ($_ -notmatch '\\amd64\\|\\arm64\\') })
        if ($found.Count -gt 0 -and (Test-Path -LiteralPath $found[0])) {
            $r.MSBuild = $found[0]
            $roslyn = Join-Path (Split-Path -Parent $found[0]) 'Roslyn\csc.exe'
            if (Test-Path -LiteralPath $roslyn) { $r.Csc = $roslyn }
        }
        $name = @(& $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -property displayName 2>$null)
        if ($name.Count -gt 0) { $r.Instance = $name[0] }
    }
    $ref = Join-Path $pf86 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1'
    if (Test-Path -LiteralPath (Join-Path $ref 'mscorlib.dll')) { $r.RefAssemblies = $ref }
    $r
}

if ($Load) { return }

$f = Find-ThornswoodMSBuild
if ($Report) {
    if ($f.VsWhere) { Write-Host "  vswhere          $($f.VsWhere)" } else { Write-Host '  vswhere          missing: no Visual Studio 2022 or Build Tools is installed' }
    if ($f.MSBuild) { Write-Host "  MSBuild          $($f.MSBuild)  ($($f.Instance))" } else { Write-Host '  MSBuild          missing: install Visual Studio 2022 Build Tools with the MSBuild component' }
    if ($f.Csc) { Write-Host "  csc (Roslyn)     $($f.Csc)" } elseif ($f.MSBuild) { Write-Host '  csc (Roslyn)     missing beside MSBuild: the Build Tools install is incomplete' }
    if ($f.RefAssemblies) { Write-Host "  .NET 4.8.1 refs  $($f.RefAssemblies)" } else { Write-Host '  .NET 4.8.1 refs  missing: the .NET Framework 4.8.1 targeting pack (a Build Tools component)' }
}
if (-not $f.MSBuild -or -not $f.Csc -or -not $f.RefAssemblies) {
    $what = @()
    if (-not $f.MSBuild) { $what += 'MSBuild from Visual Studio 2022 or its Build Tools' }
    elseif (-not $f.Csc) { $what += 'the Roslyn csc beside MSBuild (repair the Build Tools install)' }
    if (-not $f.RefAssemblies) { $what += 'the .NET Framework 4.8.1 targeting pack' }
    Write-Host ("This machine cannot build Thornswood.csproj. Missing: " + ($what -join '; ') + '. Developer-Guide.md "Setting up a machine" has the one install line.') -ForegroundColor Yellow
    exit 1
}
if (-not $Report) { $f.MSBuild }
exit 0
