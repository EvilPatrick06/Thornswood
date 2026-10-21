<#
  Launcher-Csc.ps1
  Dot-sourced by every harness that compiles launcher or setup files.

      . (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')

  It sets these variables, and two functions below them, and nothing else:

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

  Find-LauncherRef <name.dll>: that assembly's path in $LauncherRefDir, or
  $null. A harness that names framework references itself (with /noconfig,
  as the build does) takes them from here.

  Add-LauncherType -Source <code>[, <code>...] [-Reference <name.dll>|<path>...]:
  what a harness calls where it would have called Add-Type on launcher or
  setup code. It compiles the sources the way the build does ($LauncherCsc,
  /langversion:$LauncherLangVersion, /noconfig, mscorlib and every
  $LauncherNeeded assembly from $LauncherRefDir, and any -Reference), loads
  the dll from its bytes and returns the assembly. A refusal throws, with
  what the compiler said; off Windows, or without the Build Tools, it throws
  saying so, so a harness asks $OnWindows before calling it.

      $asm = Add-LauncherType -Source $configSrc, $noticeSrc
      $T = $asm.GetType('Thornswood.FeedNotice')

  Add-Type and CodeDom were never the build's compiler (#2821). Under
  Windows PowerShell 5.1 they are the in-box .NET Framework csc, which stops
  at C# 5, so a harness refused a line the build takes; under pwsh 7 they are
  .NET's Roslyn against .NET 8's libraries, so a harness passed code the
  build refuses on .NET Framework 4.8.1. Sixteen harnesses compiled launcher
  files that way, and five text checks held those files to C# 5 for them.
  What a harness compiles a script's own C# with (Signature.cs and
  VortexProfileState.cs, which scripts load with Add-Type) stays theirs.

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
  install line. Off Windows there are no Build Tools at all, and the same is
  said without asking: Find-MSBuild.ps1 looks under Program Files, which only
  Windows has, and joining onto that unset folder ended every harness that
  loads this file on its first line (#2957). This file dot-sources
  tests\Windows.ps1, so a harness that loads it has $OnWindows too, and asks
  it before "the compiler is here":

      if (-not $OnWindows) { Write-Host 'SKIP  the launcher''s code, compiled and run: ...'; Done }
#>
# In a scope of its own: dot-sourcing Find-MSBuild.ps1 here would also bring
# its parameters ($Report, $Load, typed [switch]) into the harness, and a
# harness's own $report = ... then fails (measured 15 Oct, test-crash-snapshot).
$launcherFindMsb = Join-Path $PSScriptRoot '..\scripts\release\Find-MSBuild.ps1'
. (Join-Path $PSScriptRoot 'Windows.ps1')
$launcherMsb = if ($OnWindows) { & { . $launcherFindMsb -Load; Find-ThornswoodMSBuild } } else { [pscustomobject]@{ Csc = $null; RefAssemblies = $null } }
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

function Add-LauncherType {
    param(
        [Parameter(Mandatory = $true)][string[]]$Source,
        [string[]]$Reference = @()
    )
    if (-not $OnWindows) { throw 'Add-LauncherType: the compiler the build runs is the Roslyn csc that comes with Visual Studio''s Build Tools, which only Windows has. Ask $OnWindows first, and say what does not run.' }
    if (-not (Test-Path -LiteralPath $LauncherCsc)) { throw ('Add-LauncherType: the compiler the build runs is not on this machine (' + $LauncherCsc + '). Developer-Guide.md "Setting up a machine" has the Build Tools install line.') }
    $refs = New-Object System.Collections.Generic.List[string]
    foreach ($r in @('mscorlib.dll') + $LauncherNeeded + $Reference) {
        $p = if ([IO.Path]::IsPathRooted($r)) { $r } else { Find-LauncherRef $r }
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { throw ('Add-LauncherType: ' + $r + ' is not in ' + $LauncherRefDir + ', the reference assemblies the build compiles against.') }
        if (-not $refs.Contains($p)) { $refs.Add($p) }
    }
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-launchertype-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Force -Path $dir
    try {
        # One file a source, so what the compiler says names which one.
        $files = for ($i = 0; $i -lt $Source.Count; $i++) {
            $f = Join-Path $dir ('source' + $i + '.cs')
            [IO.File]::WriteAllText($f, $Source[$i], (New-Object Text.UTF8Encoding($false)))
            $f
        }
        $dll = Join-Path $dir 'launcher-type.dll'
        # /noconfig and /nostdlib with mscorlib named, as MSBuild runs it: csc.rsp
        # and the compiler's own mscorlib are the runtime's copies, not the 4.8.1
        # reference assemblies the build compiles against.
        $cscArgs = @('/noconfig', '/nostdlib+', '/nologo', '/target:library', ('/langversion:' + $LauncherLangVersion), ('/out:' + $dll)) +
                   @($refs | ForEach-Object { '/reference:' + $_ }) + @($files)
        $said = & $LauncherCsc @cscArgs 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw ('Add-LauncherType: the compiler the build runs refused it:' + [Environment]::NewLine + $said.TrimEnd()) }
        # From its bytes, so the folder can go now.
        [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
}
