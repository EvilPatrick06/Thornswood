<#
  Launcher-Csc.ps1
  Dot-sourced by every harness that compiles launcher or setup files.

      . (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')

  It sets these variables, and one function below them, and nothing else:

    $LauncherCsc          the Roslyn csc.exe that MSBuild itself runs when it
                          builds launcher\app\Thornswood.csproj, found the way
                          the build finds it (scripts\release\Find-MSBuild.ps1).
    $LauncherLangVersion  the LangVersion launcher\app\Thornswood.csproj says.
    $LauncherNeeded       the framework assemblies it references, as file
                          names (System.dll, PresentationFramework.dll, ...).
    $LauncherWv2Managed   the WebView2 assemblies it references, as their
                          file names under launcher\lib\webview2.
    $LauncherRefDir       the .NET Framework 4.8.1 reference assemblies the
                          project builds against, the WPF ones included.

  And one function, Find-LauncherRef <name.dll>: that assembly's path in
  $LauncherRefDir, or $null. A harness that names framework references
  itself (with /noconfig, as the build does) takes them from here.

  WHY ONE PLACE (#498, 15 Oct). Until the switch every harness found the
  in-box .NET Framework csc by itself and compiled at /langversion:5, because
  that was the only compiler the build had. The build is MSBuild and the
  project files now, at the C# version the project names, so a harness that
  kept its own compiler would pass code the build refuses, or refuse code the
  build takes. Both come from here so a harness and the build cannot drift.

  The references come from here for the same reason. Until 19 Oct each
  harness hunted for them the way the old Build-Launcher.ps1 did: the v4.8,
  v4.7.2 and v4.6.1 reference folders, none of which One or the VPS has, then
  the runtime under Windows\Microsoft.NET. The build compiles against the 4.8.1
  reference assemblies, so the harnesses do too.

  On a machine without the Build Tools, $LauncherCsc and $LauncherRefDir are
  paths that do not exist, so the harness's own "the compiler is here" check
  (Test-Path -LiteralPath $LauncherCsc) says so plainly rather than a null
  somewhere further down. Developer-Guide.md "Setting up a machine" has the
  install line.
#>
# In a scope of its own: dot-sourcing Find-MSBuild.ps1 here would also bring
# its parameters ($Report, $Load, typed [switch]) into the harness, and a
# harness's own $report = ... then fails (measured 15 Oct, test-crash-snapshot).
$launcherFindMsb = Join-Path $PSScriptRoot '..\scripts\release\Find-MSBuild.ps1'
$launcherMsb = & { . $launcherFindMsb -Load; Find-ThornswoodMSBuild }
$LauncherCsc = if ($launcherMsb.Csc) { $launcherMsb.Csc } else { Join-Path ([IO.Path]::GetTempPath()) 'no-build-tools-roslyn-csc\csc.exe' }
$LauncherRefDir = if ($launcherMsb.RefAssemblies) { $launcherMsb.RefAssemblies } else { Join-Path ([IO.Path]::GetTempPath()) 'no-build-tools-net481-refs' }
function Find-LauncherRef([string]$name) {
    $p = Join-Path $LauncherRefDir $name
    if (Test-Path -LiteralPath $p) { return $p }
    $null
}
$launcherProj = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\launcher\app\Thornswood.csproj'))
$launcherLang = [regex]::Match($launcherProj, '<LangVersion>([^<]+)</LangVersion>')
if (-not $launcherLang.Success) { throw 'launcher\app\Thornswood.csproj names no LangVersion, so the harnesses cannot compile at the version the build does.' }
$LauncherLangVersion = $launcherLang.Groups[1].Value.Trim()

# The assemblies the launcher compiles against, read from the same project
# file: the framework ones as file names (System.dll, ...) for a harness's own
# lookup, and the WebView2 ones as the file names under launcher\lib\webview2.
# Until the switch these were lists inside Build-Launcher.ps1 ($needed and
# $wv2Managed), which the harnesses read out of it; the project file is their
# only home now.
$launcherProjXml = [xml]$launcherProj
$launcherNs = New-Object Xml.XmlNamespaceManager($launcherProjXml.NameTable)
$launcherNs.AddNamespace('m', 'http://schemas.microsoft.com/developer/msbuild/2003')
$LauncherNeeded = @($launcherProjXml.SelectNodes('//m:Reference[not(m:HintPath)]/@Include', $launcherNs) | ForEach-Object { $_.Value.Trim() + '.dll' })
$LauncherWv2Managed = @($launcherProjXml.SelectNodes('//m:Reference/m:HintPath', $launcherNs) | ForEach-Object { [IO.Path]::GetFileName($_.InnerText.Trim()) })
