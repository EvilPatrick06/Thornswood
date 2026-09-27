<#
  test-setup-stub-identity.ps1

  The setup stub names itself. Until the installer is signed (issue #390), the
  window a stranger meets first, UAC and SmartScreen, has only the version
  resource to read, and a blank one leaves it showing the bare file name over
  "Unknown". Bootstrap.cs fills that in and keeps it stable, so the identity
  does not change from one build to the next and the Downloads page and FAQ
  can be written to match what a person sees.

  This reads Bootstrap.cs and holds it to four things, none of which needs the
  Windows compiler, so it runs anywhere:
    - the version resource is there, with a stable product name;
    - every address baked into the exe is https to thornswood.net, and no
      foreign host is compiled in (the two http:// left are XAML namespaces,
      which are names and not places);
    - what it downloads is a zip it checks against a SHA-256 before anything in
      it runs, and the only thing it starts is Setup.bat, so no second unsigned
      program is fetched and run;
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
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $BootstrapPath) { $BootstrapPath = Join-Path $Here '..\installer\setup\Bootstrap.cs' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$bs = [IO.File]::ReadAllText($BootstrapPath)

# ---- 1. the version resource, and a stable product identity ------------------
Yes 'the stub carries its own version resource attributes' ($bs -match '(?m)^\s*\[assembly:\s*AssemblyProduct')
Yes 'the product name is the stable "Thornswood Setup"' ($bs.Contains('[assembly: AssemblyProduct("Thornswood Setup")]'))
Yes 'and the UAC program name (AssemblyTitle) is the same' ($bs.Contains('[assembly: AssemblyTitle("Thornswood Setup")]'))
Yes 'the company is filled in' ($bs.Contains('[assembly: AssemblyCompany("Thornswood")]'))
Yes 'and the copyright' ($bs.Contains('[assembly: AssemblyCopyright("Thornswood")]'))
$fileVer = [regex]::Match($bs, '\[assembly:\s*AssemblyFileVersion\("([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)"\)\]')
$prodVer = [regex]::Match($bs, '\[assembly:\s*AssemblyInformationalVersion\("([0-9][0-9.]*)"\)\]')
Yes 'a four-part file version is set' ($fileVer.Success)
Yes 'a product version is set' ($prodVer.Success)
if ($fileVer.Success) { Write-Host ("      FileVersion    " + $fileVer.Groups[1].Value) }
if ($prodVer.Success) { Write-Host ("      ProductVersion " + $prodVer.Groups[1].Value) }

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
$iStart = $bs.IndexOf('Process.Start(psi);')
Yes 'the only program it starts is the payload''s Setup.bat, not a downloaded exe' (
    $bs.Contains('string bat = Path.Combine(temp, "Setup.bat");') -and
    $bs.Contains('new ProcessStartInfo(bat)') -and $iStart -gt 0)

# ---- 4. the #429 age lock, left alone --------------------------------------
# Install starts disabled and the checkbox is the only thing that enables it,
# unless the control is missing, in which case the else-branch enables it so
# the installer is not impossible to start. That branch is locked for #429.
Yes 'Install still starts disabled behind the age checkbox' ($bs.Contains('btnGo.IsEnabled = false;'))
Yes 'and the else-branch that enables it when the control is missing is intact' (
    $bs.Contains('// Rather than an installer nobody can ever start.') -and
    $bs.Contains('btnGo.IsEnabled = true;'))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
