<#
  test-package-sign-order.ps1

  OneFile Package must sign the final Setup after the payload is attached.
  Build-Launcher must not pre-sign setup-stub.exe: a signed stub plus append
  makes signtool return 0x800700C1 (measured Main Package 27 September).

  Static checks only. No signing.json, no Azure, no network.
#>
[CmdletBinding()]
param()
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
$Utf8 = New-Object Text.UTF8Encoding($false)

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$build = Join-Path $repo 'scripts\release\Build-Launcher.ps1'
$pkg = Join-Path $repo 'scripts\release\Package-Thornswood.ps1'
Yes 'Build-Launcher.ps1 is there' (Test-Path -LiteralPath $build)
Yes 'Package-Thornswood.ps1 is there' (Test-Path -LiteralPath $pkg)
if (-not ((Test-Path -LiteralPath $build) -and (Test-Path -LiteralPath $pkg))) {
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    exit 1
}

$buildSrc = [IO.File]::ReadAllText($build, $Utf8)
$pkgSrc = [IO.File]::ReadAllText($pkg, $Utf8)

Yes 'Build-Launcher says the stub stays unsigned for OneFile' (
    $buildSrc -match 'Do NOT sign setup-stub' -or $buildSrc -match 'Do not sign setup-stub')
Yes 'Build-Launcher Sign-Artifact is given the launcher exe only' (
    $buildSrc -match '& \$signer -Path \$exe\b' -and
    $buildSrc -notmatch '\$toSign \+= \$stub')
Yes 'Package still signs after the payload is attached' (
    $pkgSrc -match 'After the payload is attached, not before' -and
    $pkgSrc -match '& \$signer -Path \$exe')
Yes 'Package strips a pre-signed stub before OneFile attach' (
    $pkgSrc -match 'signtoolStrip' -and
    $pkgSrc -match 'remove /s' -and
    $pkgSrc -match '0x800700C1')
# Order: strip / attach comment block appears before Signing the installer head
$atStrip = $pkgSrc.IndexOf('stub was signed; stripping')
$atAttach = $pkgSrc.IndexOf('attaching the payload to the setup program')
$atSign = $pkgSrc.IndexOf("Head 'Signing the installer'")
Yes 'strip logic sits before attach' ($atStrip -gt 0 -and $atAttach -gt $atStrip)
Yes 'attach sits before Signing the installer' ($atAttach -gt 0 -and $atSign -gt $atAttach)

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
