<#
  test-setup-stub-identity.ps1

  The setup stub names itself. Until the installer is signed (issue #390), the
  window a stranger meets first, UAC and SmartScreen, has only the version
  resource to read, and a blank one leaves it showing the bare file name over
  "Unknown". Bootstrap.cs fills in the stable product NAME (Title / Product /
  Company / Copyright). FileVersion and ProductVersion are not hardcoded there;
  Build-Launcher.ps1 stamps them at compile time from launcher\app\Updater.cs
  so the stub tracks the launcher release number. The Downloads page and FAQ
  can still be written to match the stable name strings a person sees.

  This reads Bootstrap.cs and Build-Launcher.ps1 and holds them to:
    - Bootstrap still has the stable product name attrs (Title/Product/Company/
      Copyright) and does NOT hardcode AssemblyVersion / AssemblyFileVersion /
      AssemblyInformationalVersion;
    - Build-Launcher always generates ThornswoodSetupVersion.cs with those three
      version attrs from $ver / $verFour and passes it to csc with Bootstrap;
    - every address baked into the exe is https to thornswood.net, and no
      foreign host is compiled in (the two http:// left are XAML namespaces,
      which are names and not places);
    - what it downloads is a zip it checks against a SHA-256 before anything in
      it runs, and the only thing it starts is PowerShell on the payload's
      Setup-Thornswood.ps1 (Setup.bat until issue #889), so no second
      unsigned program is fetched and run;
    - the age gate's else-branch, which enables Install when the checkbox is
      missing, is left exactly as it is (locked for #429).

  Read only.
#>
[CmdletBinding()]
param([string]$BootstrapPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# This test lives in tests\; repo root is one level up.
$repoRoot = Split-Path -Parent $Here
if (-not $BootstrapPath) { $BootstrapPath = Join-Path $repoRoot 'installer\setup\Bootstrap.cs' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$bs = [IO.File]::ReadAllText($BootstrapPath)

# ---- 1. stable product name in Bootstrap; versions stamped by Build-Launcher --
Yes 'the stub carries its own product name attributes' ($bs -match '(?m)^\s*\[assembly:\s*AssemblyProduct')
Yes 'the product name is the stable "Thornswood Setup"' ($bs.Contains('[assembly: AssemblyProduct("Thornswood Setup")]'))
Yes 'and the UAC program name (AssemblyTitle) is the same' ($bs.Contains('[assembly: AssemblyTitle("Thornswood Setup")]'))
Yes 'the company is filled in' ($bs.Contains('[assembly: AssemblyCompany("Thornswood")]'))
Yes 'and a legal copyright notice' ($bs.Contains('[assembly: AssemblyCopyright("Copyright (c) Thornswood")]'))
Yes 'Bootstrap does NOT hardcode AssemblyVersion' ($bs -notmatch '(?m)^\s*\[assembly:\s*AssemblyVersion')
Yes 'Bootstrap does NOT hardcode AssemblyFileVersion' ($bs -notmatch '(?m)^\s*\[assembly:\s*AssemblyFileVersion')
Yes 'Bootstrap does NOT hardcode AssemblyInformationalVersion' ($bs -notmatch '(?m)^\s*\[assembly:\s*AssemblyInformationalVersion')

# ---- 2. https to thornswood.net, and nothing else --------------------------
Yes 'the one host it is built to reach is https to thornswood.net' (
    $bs.Contains('const string Site = "https://thornswood.net";'))
Yes 'the payload listing is read from that host' ($bs.Contains('Site + "/api/payload"'))
# Every https:// literal in the file has to be thornswood.net, so no CDN or
# other host is compiled in. A download url the site hands back at run time is
# not a literal here; the site returns a path under /file/, which the stub
# prefixes with Site.
$httpsBad = @([regex]::Matches($bs, 'https://([a-z0-9.\-]+)') | Where-Object { $_.Groups[1].Value -ne 'thornswood.net' })
Yes 'no other https host is baked into the exe' ($httpsBad.Count -eq 0)
if ($httpsBad.Count) { Write-Host ('      found: ' + (($httpsBad | ForEach-Object { $_.Value }) -join ', ')) }
# The only http:// left are the two XAML namespace names, which are identifiers
# the parser matches on and never addresses anything is fetched from.
$httpBad = @([regex]::Matches($bs, 'http://([a-z0-9.\-]+)') | Where-Object { $_.Groups[1].Value -ne 'schemas.microsoft.com' })
Yes 'no plain-http host is baked into the exe (only XAML namespaces remain)' ($httpBad.Count -eq 0)
if ($httpBad.Count) { Write-Host ('      found: ' + (($httpBad | ForEach-Object { $_.Value }) -join ', ')) }

# ---- 3. a checked zip, and no second program fetched and run ---------------
Yes 'the download is verified against a SHA-256' ($bs.Contains('SHA256.Create()') -and $bs.Contains('static bool PayloadMatches'))
Yes 'and a mismatch is deleted and stops the install' (
    $bs.Contains('static void CheckPayload') -and $bs.Contains('File.Delete(file)'))
# The check comes before the payload is opened or anything in it is run. In
# Download the SHA is checked before the path is returned; in Work that path is
# unpacked and Setup.bat started, so the order is check, then unpack, then run.
$iCheck = $bs.IndexOf('CheckPayload(target, sha);')
$iReturn = if ($iCheck -ge 0) { $bs.IndexOf('return target;', $iCheck) } else { -1 }
Yes 'the SHA is checked before the download is handed back' ($iCheck -ge 0 -and $iReturn -gt $iCheck)
# Since issue #889 that is PowerShell on the payload's Setup-Thornswood.ps1,
# started hidden, the same thing Setup.bat runs (test-setup-in-window.ps1).
$iStart = $bs.IndexOf('p.Start();')
Yes 'the only program it starts is PowerShell on the payload''s script, not a downloaded exe' (
    $bs.Contains('string script = Path.Combine(temp, "Setup-Thornswood.ps1");') -and
    $bs.Contains('SetupStartInfo(PowerShellExe(), script, installRoot, makeOwnGame, vortexGame)') -and
    $bs.Contains('var psi = new ProcessStartInfo(ps);') -and $iStart -gt 0)
# The one Process.Start is the browser on the terms, privacy or rules page
# (issue #1009), and OpenPage refuses any address that is not the site's.
$openAt = $bs.IndexOf('static void OpenPage(Uri uri)')
$psAt = @([regex]::Matches($bs, 'Process\.Start\('))
$guard = if ($openAt -gt 0) { $bs.IndexOf('if (!url.StartsWith(Site + "/", StringComparison.OrdinalIgnoreCase)) return;', $openAt) } else { -1 }
Yes 'the one Process.Start opens only a page on the site, in the browser' (
    $psAt.Count -eq 1 -and $openAt -gt 0 -and $guard -gt $openAt -and $psAt[0].Index -gt $guard)

# ---- 4. the #429 age lock, left alone --------------------------------------
# Install starts disabled and the checkbox is the only thing that enables it,
# unless the control is missing, in which case the else-branch enables it so
# the installer is not impossible to start. That branch is locked for #429.
Yes 'Install still starts disabled behind the age checkbox' ($bs.Contains('btnGo.IsEnabled = false;'))
Yes 'and the else-branch that enables it when the control is missing is intact' (
    $bs.Contains('// Rather than an installer nobody can ever start.') -and
    $bs.Contains('btnGo.IsEnabled = true;'))

# ---- 5. the build wiring: shipped name, icon, version stamp from Updater ------
# OriginalFilename and InternalName come off the /out leaf, and the shipped exe
# is Thornswood-Setup.exe, so the stub is compiled under that name and then
# moved onto out\setup-stub.exe, which packaging copies without recompiling.
# A file icon (/win32icon) keeps the download from arriving as a blank mark.
# FileVersion/ProductVersion come from a generated ThornswoodSetupVersion.cs
# stamped from Updater.cs, not from hardcoded Bootstrap attrs.
# Since #498's switch these live in installer\setup\Setup.csproj, which
# Build-Launcher.ps1 builds with MSBuild, rather than in a csc line.
$blPath = Join-Path $repoRoot 'scripts\release\Build-Launcher.ps1'
$spPath = Join-Path $repoRoot 'installer\setup\Setup.csproj'
if ((Test-Path -LiteralPath $blPath) -and (Test-Path -LiteralPath $spPath)) {
    $bl = [IO.File]::ReadAllText($blPath)
    $sp = [IO.File]::ReadAllText($spPath)
    Yes 'the setup stub is built under its shipped name, Thornswood-Setup.exe' ($sp.Contains('<AssemblyName>Thornswood-Setup</AssemblyName>'))
    Yes 'and Build-Launcher picks up that exe from the build' ($bl.Contains("`$stubNew = Join-Path `$stubBuild 'Thornswood-Setup.exe'"))
    Yes 'then moves it onto the setup-stub.exe packaging copies from' ($bl.Contains('Move-Item -LiteralPath $stubNew -Destination $stub'))
    Yes 'the stub exe gets a file icon, so it is not a blank mark in the browser' ($sp -match '<ApplicationIcon>[^<]*app\.ico</ApplicationIcon>')
    Yes 'Setup.csproj generates ThornswoodSetupVersion.cs for the stub' ($sp.Contains('ThornswoodSetupVersion.cs') -and $sp.Contains('<Compile Include="$(ThornswoodSetupVersionFile)" />'))
    Yes 'that file stamps AssemblyFileVersion from the four part version' ($sp.Contains('AssemblyFileVersion(&quot;$(ThornswoodVersionFour)&quot;)'))
    Yes 'and AssemblyInformationalVersion from Updater.cs''s version' ($sp.Contains('AssemblyInformationalVersion(&quot;$(ThornswoodVersion)&quot;)'))
} else {
    Yes 'Build-Launcher.ps1 and Setup.csproj are where this expects them' $false
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0