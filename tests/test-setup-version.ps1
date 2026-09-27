<#
  test-setup-version.ps1

  The version resource that actually ships on Thornswood-Setup.exe, read back
  off the compiled bytes rather than off the source that writes it.

  WHY THIS EXISTS. Until the installer is signed (issue #390, held) the Win32
  version resource is the only thing UAC, SmartScreen, the properties dialog
  and most anti-virus heuristics have to read off the exe a stranger runs
  first. A blank one leaves them with the bare file name over "Unknown", which
  is exactly the shape a generic downloader flag looks for, and it is part of
  why VirusTotal marks the file at all before any reputation builds up.

  Bootstrap.cs carries the stable name attributes (Title / Product / Company /
  Copyright) and Build-Launcher.ps1 stamps FileVersion / ProductVersion from
  launcher\app\Updater.cs, so csc writes a filled version resource at compile
  time (issues #666 and #671). test-setup-stub-identity.ps1 guards that SOURCE.
  Nothing read the resource back off the exe csc produced, so a csc change, a
  stale copy left on tools\setup-stub.exe, or a bad move could ship a stub with
  a blank or wrong resource and the source test would still pass. This reads
  the bytes that ship.

  It is the verify command the Installer lane can run before it re-packages and
  re-uploads to VirusTotal to re-measure: a green line here says the honest
  metadata is on the file about to go up. Signing is a separate lever and stays
  held; this changes nothing about it.

  Reads a version resource; writes nothing and compiles nothing. Point -Path at
  any built Setup exe (the plain stub, or a one-file Thornswood-Setup.exe with
  the payload attached); with no -Path it reads tools\setup-stub.exe, which
  Build-Launcher.ps1 produces. When that is not there yet, on a fresh checkout
  before any build, it says SKIP and passes, because there is nothing to read.

      pwsh -NoProfile -File .\tests\test-setup-version.ps1
      pwsh -NoProfile -File .\tests\test-setup-version.ps1 -Path .\out\Thornswood-Setup.exe
#>
[CmdletBinding()]
param([string[]]$Path, [switch]$NoPause)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# tests\ is one level under the repo root.
$repoRoot = Split-Path -Parent $Here

# Whether a path was asked for by name. A named file that is missing is a
# failure; the default file being missing is only a fresh checkout with no
# build yet, which skips.
$named = $PSBoundParameters.ContainsKey('Path') -and $Path -and $Path.Count -gt 0
if (-not $named) { $Path = @(Join-Path $repoRoot 'tools\setup-stub.exe') }

# The number Ship reads and the launcher reports, the same source Build-Launcher
# stamps the stub from. The resource on the exe has to match it, or the stub is
# older than the launcher it installs.
$ver = '1.0.0'
$updaterCs = Join-Path $repoRoot 'launcher\app\Updater.cs'
if (Test-Path -LiteralPath $updaterCs) {
    $m = [regex]::Match([IO.File]::ReadAllText($updaterCs), 'Version\s*=\s*"([0-9.]+)"')
    if ($m.Success) { $ver = $m.Groups[1].Value }
}

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Clean($s) { if ($null -eq $s) { return '' } return $s.Trim() }

# Resolve what to read. A named file that is not there fails loudly; the
# default one being absent is nothing to measure, so the whole harness skips.
$targets = @()
foreach ($p in $Path) {
    if (Test-Path -LiteralPath $p) { $targets += (Resolve-Path -LiteralPath $p).Path }
    elseif ($named) { Yes "the file to check is there: $p" $false }
}
if ($targets.Count -eq 0 -and -not $named) {
    Write-Host 'SKIP  no tools\setup-stub.exe here yet. Build-Launcher.ps1 compiles it; nothing to read a version resource off until it has run.'
    exit 0
}

foreach ($t in $targets) {
    $leaf = Split-Path -Leaf $t
    Write-Host ''
    Write-Host "reading $leaf"

    $vi = (Get-Item -LiteralPath $t).VersionInfo
    $company = Clean $vi.CompanyName
    $product = Clean $vi.ProductName
    $descr   = Clean $vi.FileDescription
    $copy    = Clean $vi.LegalCopyright
    $fileVer = Clean $vi.FileVersion
    $prodVer = Clean $vi.ProductVersion

    Write-Host ("  CompanyName     : {0}" -f $company)
    Write-Host ("  ProductName     : {0}" -f $product)
    Write-Host ("  FileDescription : {0}" -f $descr)
    Write-Host ("  LegalCopyright  : {0}" -f $copy)
    Write-Host ("  FileVersion     : {0}" -f $fileVer)
    Write-Host ("  ProductVersion  : {0}" -f $prodVer)

    # Filled, not blank. A blank field is what leaves Windows and the scanners
    # reading the bare file name.
    Yes "$leaf names its company"          ($company.Length -gt 0)
    Yes "$leaf names its product"          ($product.Length -gt 0)
    Yes "$leaf has a file description"     ($descr.Length -gt 0)
    Yes "$leaf has a copyright notice"     ($copy.Length -gt 0)
    Yes "$leaf has a file version"         ($fileVer.Length -gt 0)
    Yes "$leaf has a product version"      ($prodVer.Length -gt 0)

    # Honest, not generic. Every string names Thornswood, so the exe is not an
    # unnamed stub wearing someone else's or nobody's metadata.
    Yes "$leaf company is Thornswood"      ($company -eq 'Thornswood')
    Yes "$leaf product names Thornswood"   ($product -like 'Thornswood*')
    Yes "$leaf description names Thornswood" ($descr -like 'Thornswood*')
    Yes "$leaf copyright names Thornswood" ($copy -like '*Thornswood*')

    # Current, not a stub left over from an older launcher. The file version
    # carries the number Updater.cs holds, and it is not the csc default of all
    # zeroes.
    Yes "$leaf file version is not 0.0.0.0" ($fileVer -ne '0.0.0.0' -and $fileVer -notmatch '^0(\.0)+$')
    Yes "$leaf file version matches Updater.cs ($ver)" ($fileVer -like "$ver*")
    Yes "$leaf product version matches Updater.cs ($ver)" ($prodVer -like "$ver*")
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) {
    Write-Host ''
    Write-Host 'The version resource on the setup exe is blank, generic or stale.' -ForegroundColor Yellow
    Write-Host 'Build-Launcher.ps1 stamps it from Bootstrap.cs and Updater.cs (#666/#671);' -ForegroundColor Yellow
    Write-Host 'rebuild the stub with Build-Launcher.ps1 and read it again before publishing.' -ForegroundColor Yellow
    if (-not $NoPause -and $Host.Name -eq 'ConsoleHost') { [void](Read-Host 'Enter to exit') }
    exit 1
}
exit 0
