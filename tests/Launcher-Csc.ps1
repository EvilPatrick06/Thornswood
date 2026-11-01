<#
  Launcher-Csc.ps1
  Dot-sourced by every harness that compiles launcher files.

      . (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')

  The launcher is a .NET 10 project (launcher\app\Thornswood.csproj, #4823),
  so its code is compiled the way that project compiles it: by the .NET 10
  SDK, at the project's LangVersion, against the project's target framework
  and its packages. That works on Linux as well as on Windows, so a harness
  compiles and runs launcher code everywhere, and only says SKIP where the
  code under test itself does something only Windows has.

  It sets these variables, and the functions below them, and nothing else
  (apart from $OnWindows, which it gets from tests\Windows.ps1):

    $LauncherDotnet       the dotnet that builds the launcher: the one on
                          PATH, else $env:DOTNET_ROOT's, else ~/.dotnet's.
                          A path that does not exist when there is none, so a
                          harness's "the SDK is here" check says so plainly.
    $LauncherLangVersion  the LangVersion launcher\app\Thornswood.csproj says.
    $LauncherFramework    the TargetFramework it says (net10.0-windows).

  Build-LauncherCode -Source <code>[, ...] [-File <path>[, ...]] [-Exe]:
  builds the C# given (strings the harness writes, and launcher files by
  path) as a library, or with -Exe as a program, the way the project builds:
  the same target framework, LangVersion, Nullable, ImplicitUsings,
  AllowUnsafeBlocks and every PackageReference, so launcher code that uses
  Avalonia or any other package compiles here as it does in the build. It
  returns the path of the built dll. A refusal throws, with what the
  compiler said.

  Invoke-LauncherExe <dll> [args...]: runs a program Build-LauncherCode -Exe
  built, through $LauncherDotnet, and returns what it printed, one string a
  line. $LASTEXITCODE is the program's exit code.

  Add-LauncherType -Source <code>[, ...] [-File <path>[, ...]]: what a harness
  calls where it would have called Add-Type on launcher code. It builds a
  library with Build-LauncherCode and loads it into this PowerShell, which
  runs on .NET 10 as well (pwsh 7.6), and returns the assembly.

      $asm = Add-LauncherType -File (Join-Path $App 'FeedNotice.cs') -Source $standIn
      $T = $asm.GetType('Thornswood.FeedNotice')

  WHERE THE BUILDS GO. Under out\harness\ in the repository, which git
  ignores, in a folder named by a hash of the project and every source, so
  the same code is built once and the next run of any harness reuses it. A
  build is made in a folder of its own and then renamed into place, so two
  harnesses run side by side by the gate never write into one folder. A
  loaded assembly holds its file open on Windows, so the folders are never
  removed under a harness; deleting out\ clears them.

  Add-Type and CodeDom were never the build's compiler (#2821): they compile
  with whatever runtime PowerShell runs on, not with the project's settings
  and packages. Every harness compiles launcher code through here so a
  harness and the build cannot drift. WHY ONE PLACE (#498): a harness that
  kept a compiler of its own passed code the build refused, or refused code
  the build took.

  Until #4823 this file found the Roslyn csc beside MSBuild in Visual Studio's
  Build Tools and the .NET Framework 4.8.1 reference assemblies, which only
  Windows has, so every compile here was SKIP off Windows.
#>
. (Join-Path $PSScriptRoot 'Windows.ps1')

$launcherRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$launcherProjPath = Join-Path $launcherRepo (Join-Path 'launcher' (Join-Path 'app' 'Thornswood.csproj'))
$launcherProjXml = [xml][IO.File]::ReadAllText($launcherProjPath)

function Get-LauncherProjectValue([string]$name) {
    $n = $launcherProjXml.SelectSingleNode('//PropertyGroup/' + $name)
    if ($null -eq $n) { return $null }
    $n.InnerText.Trim()
}

$LauncherLangVersion = Get-LauncherProjectValue 'LangVersion'
if (-not $LauncherLangVersion) { throw 'launcher\app\Thornswood.csproj names no LangVersion, so the harnesses cannot compile at the version the build does.' }
$LauncherFramework = Get-LauncherProjectValue 'TargetFramework'
if (-not $LauncherFramework) { throw 'launcher\app\Thornswood.csproj names no TargetFramework, so the harnesses cannot compile against what the build does.' }

# The project's own settings that change what compiles, copied as they are.
$launcherCopied = @('Nullable', 'ImplicitUsings', 'AllowUnsafeBlocks', 'EnableWindowsTargeting') | ForEach-Object {
    $v = Get-LauncherProjectValue $_
    if ($null -ne $v) { '    <' + $_ + '>' + [Security.SecurityElement]::Escape($v) + '</' + $_ + '>' }
}
$launcherPackages = @($launcherProjXml.SelectNodes('//ItemGroup/PackageReference') | ForEach-Object {
    '    <PackageReference Include="' + [Security.SecurityElement]::Escape($_.Include) + '" Version="' + [Security.SecurityElement]::Escape($_.Version) + '" />'
})

$LauncherDotnet = $null
$launcherOnPath = Get-Command dotnet -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($launcherOnPath) { $LauncherDotnet = $launcherOnPath.Source }
else {
    $launcherExeName = if ($OnWindows) { 'dotnet.exe' } else { 'dotnet' }
    foreach ($root in @($env:DOTNET_ROOT, (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dotnet'))) {
        if (-not $root) { continue }
        $p = Join-Path $root $launcherExeName
        if (Test-Path -LiteralPath $p) { $LauncherDotnet = $p; break }
    }
}
if (-not $LauncherDotnet) { $LauncherDotnet = Join-Path ([IO.Path]::GetTempPath()) (Join-Path 'no-dotnet-sdk' 'dotnet') }

function Build-LauncherCode {
    param(
        [string[]]$Source = @(),
        [string[]]$File = @(),
        [switch]$Exe
    )
    if (-not (Test-Path -LiteralPath $LauncherDotnet)) { throw ('Build-LauncherCode: the .NET SDK the launcher builds with is not on this machine (' + $LauncherDotnet + '). Developer-Guide.md "Setting up a machine" has the install line.') }
    if (@($Source).Count + @($File).Count -eq 0) { throw 'Build-LauncherCode: nothing to build.' }
    $files = foreach ($f in $File) {
        if (-not (Test-Path -LiteralPath $f)) { throw ('Build-LauncherCode: ' + $f + ' is not there.') }
        (Resolve-Path -LiteralPath $f).Path
    }

    $proj = @(
        '<Project Sdk="Microsoft.NET.Sdk">',
        '  <PropertyGroup>',
        ('    <OutputType>' + $(if ($Exe) { 'Exe' } else { 'Library' }) + '</OutputType>'),
        ('    <TargetFramework>' + $LauncherFramework + '</TargetFramework>'),
        ('    <LangVersion>' + $LauncherLangVersion + '</LangVersion>')
    ) + $launcherCopied + @(
        '    <AssemblyName>ASSEMBLY_NAME</AssemblyName>',
        '    <RootNamespace>Thornswood</RootNamespace>',
        '    <EnableDefaultItems>false</EnableDefaultItems>',
        '    <UseAppHost>false</UseAppHost>',
        '    <GenerateDocumentationFile>false</GenerateDocumentationFile>',
        '    <SatelliteResourceLanguages>en</SatelliteResourceLanguages>',
        '  </PropertyGroup>',
        '  <ItemGroup>'
    ) + $launcherPackages + @('  </ItemGroup>', '  <ItemGroup>') +
        @(for ($i = 0; $i -lt @($Source).Count; $i++) { '    <Compile Include="source' + $i + '.cs" />' }) +
        @($files | ForEach-Object { '    <Compile Include="' + [Security.SecurityElement]::Escape($_) + '" />' }) +
        @('  </ItemGroup>', '</Project>')
    $projText = ($proj -join "`n") + "`n"

    # The folder is named by everything that goes into the build.
    $sha = [Security.Cryptography.SHA256]::Create()
    $all = New-Object Text.StringBuilder
    [void]$all.Append($projText)
    foreach ($s in $Source) { [void]$all.Append("`0").Append($s) }
    foreach ($f in $files) { [void]$all.Append("`0").Append([IO.File]::ReadAllText($f)) }
    $hash = -join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($all.ToString())) | ForEach-Object { $_.ToString('x2') })
    # The assembly is named by the hash too: .NET loads one assembly of a
    # name, so two builds both called the same would be one in a harness.
    $name = 'launcher-code-' + $hash.Substring(0, 24)
    $projText = $projText.Replace('ASSEMBLY_NAME', $name)
    $base = Join-Path $launcherRepo (Join-Path 'out' 'harness')
    $done = Join-Path $base $hash.Substring(0, 24)
    $dll = Join-Path $done ($name + '.dll')
    if (Test-Path -LiteralPath $dll) { return $dll }

    $work = Join-Path $base ('building-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    $null = New-Item -ItemType Directory -Force -Path $work
    try {
        $utf8 = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText((Join-Path $work 'launcher-code.csproj'), $projText, $utf8)
        for ($i = 0; $i -lt @($Source).Count; $i++) {
            [IO.File]::WriteAllText((Join-Path $work ('source' + $i + '.cs')), $Source[$i], $utf8)
        }
        $bin = Join-Path $work 'bin'
        $said = & $LauncherDotnet build (Join-Path $work 'launcher-code.csproj') -c Release -o $bin -nologo -v:q '-clp:NoSummary;ErrorsOnly' 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $bin ($name + '.dll')))) {
            throw ('Build-LauncherCode: the .NET SDK refused it:' + [Environment]::NewLine + $said.Trim())
        }
        # Into place in one rename. Another harness may have built the same
        # code meanwhile; its copy is the same, and is used.
        try { [IO.Directory]::Move($bin, $done) }
        catch [IO.IOException] { if (-not (Test-Path -LiteralPath $dll)) { throw } }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
    $dll
}

function Invoke-LauncherExe {
    param([Parameter(Mandatory = $true, Position = 0)][string]$Path, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments = @())
    & $LauncherDotnet $Path @Arguments
}

function Add-LauncherType {
    param(
        [string[]]$Source = @(),
        [string[]]$File = @()
    )
    # LoadFrom, so the packages built beside it load from the same folder.
    [Reflection.Assembly]::LoadFrom((Build-LauncherCode -Source $Source -File $File))
}
