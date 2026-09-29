<#
  test-build-engine.ps1

  scripts\release\Build-Engine.ps1, the script any developer runs to build
  the engine on their own machine (issue #545), and the two reorganisation
  leftovers the 25 September audit found beside it.

  WHY THIS EXISTS. The configure line lived only in engine\README.md, typed by
  hand, and Build-Server.ps1 refuses to configure, so no machine but
  Patrick's had ever built the engine and only his could Ship. This holds the
  script to the settings engine\README.md gives and to the fork's own option
  names, and checks that on a machine missing the tools it says so and builds
  nothing.

  It also checks Publish-Update.ps1 hashes the launcher source from launcher\
  (it read tools\ until the audit, and found nothing there after phase 7), and
  that Check-VoiceInstall.ps1 no longer names one person's Downloads folder.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$root = Split-Path -Parent $Here
$script = Join-Path $root 'scripts\release\Build-Engine.ps1'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$text = Get-Content -LiteralPath $script -Raw
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errs)
Yes 'Build-Engine.ps1 parses' ($errs.Count -eq 0)

# The configure settings, the same as engine\README.md's.
$readme = Get-Content -LiteralPath (Join-Path $root 'engine\README.md') -Raw
foreach ($s in 'Visual Studio 17 2022', '-A x64', 'VCPKG_TARGET_TRIPLET=x64-windows-sp', 'OFFLINE_MODE=ON', 'BUILD_CLIENT=ON', 'BUILD_SKYRIM_PLATFORM=ON', 'SKYRIM_DIR') {
    Yes "it configures with $s, as engine\README.md does" ($text.Contains($s) -and $readme.Contains($s))
}
Yes 'it points the toolchain at the fork''s own vcpkg' ($text.Contains('vcpkg\scripts\buildsystems\vcpkg.cmake'))
Yes 'it never writes a record' ($text -notmatch '&\s*\(?Join-Path[^\n]*New-(Client|Server)BuildRecord')
Yes 'it compares the six client files with records\client-build.json' ($text.Contains('records\client-build.json') -and $text.Contains('Get-FileHash'))

# Run hands back the exit code alone. It used to return the tool's output
# with it, so a configure that printed anything and exited 0 stopped as a
# failure (#919). The real function, run on a tool that prints and exits 0,
# then on one that prints and exits 3.
$runAst = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null).Find({
        param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Run' }, $true)
Yes 'it has a Run function' ($null -ne $runAst)
if ($runAst) {
    $runOk = & ([scriptblock]::Create($runAst.Extent.Text + '; Run cmd /c "echo printed & echo also 1>&2"')) 6>$null
    Yes 'Run returns 0, and only 0, for a tool that prints and succeeds' ((@($runOk).Count -eq 1) -and ($runOk -eq 0))
    $runBad = & ([scriptblock]::Create($runAst.Extent.Text + '; Run cmd /c "echo printed & exit 3"')) 6>$null
    Yes 'Run returns 3, and only 3, for a tool that prints and fails with 3' ((@($runBad).Count -eq 1) -and ($runBad -eq 3))
}
# A bare -- in a call to Run is eaten by PowerShell, so cmake got /m as its
# own argument and refused it. The build line quotes it.
$buildLine = @($text -split "`n" | Where-Object { $_ -match '^\s*\$code = Run \$cmake --build' })
Yes 'the build passes -- through to MSBuild quoted' ($buildLine.Count -eq 1 -and $buildLine[0] -match "'--' /m")

# Against the fork, when it is checked out here.
$cm = Join-Path $root 'engine\skymp\CMakeLists.txt'
if (Test-Path -LiteralPath $cm) {
    $c = Get-Content -LiteralPath $cm -Raw
    foreach ($o in 'OFFLINE_MODE', 'BUILD_CLIENT', 'BUILD_SKYRIM_PLATFORM', 'SKYRIM_DIR') {
        Yes "the fork's CMakeLists.txt has the option $o" ($c -match "option\($o\b")
    }
    Yes 'the fork defaults its triplet to x64-windows-sp' ($c.Contains('x64-windows-sp'))
} else { Write-Host 'SKIP  the fork is not checked out here, so its option names were not read' }

# On a machine without the tools: it says what is missing and builds nothing.
$fake = Join-Path ([IO.Path]::GetTempPath()) ('ts-engine-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fake | Out-Null
try {
    $saved = ${env:ProgramFiles(x86)}
    ${env:ProgramFiles(x86)} = $fake
    $out = & $script -Check -NoPause -SkyrimDir (Join-Path $fake 'nogame') -Fork (Join-Path $fake 'fork') *>&1 | Out-String
    $code = $LASTEXITCODE
    ${env:ProgramFiles(x86)} = $saved
    Yes 'with no Visual Studio it stops' ($code -eq 1 -and $out -match 'Nothing was built')
    Yes '  and names Visual Studio and the workload' ($out -match 'Desktop development with C\+\+')
    Yes '  and names the missing game folder' ($out -match 'SkyrimSE\.exe in')
    Yes '  and made no build folder' (-not (Test-Path -LiteralPath (Join-Path $fake 'fork\build')))
}
finally { Remove-Item -LiteralPath $fake -Recurse -Force -ErrorAction SilentlyContinue }

# The audit's two leftovers.
$pu = Get-Content -LiteralPath (Join-Path $root 'scripts\release\Publish-Update.ps1') -Raw
Yes 'Publish-Update hashes the launcher source from launcher\' ($pu -match "\`$srcDir = Join-Path \`$RepoDir 'launcher'")
$cv = Get-Content -LiteralPath (Join-Path $root 'scripts\vps\Check-VoiceInstall.ps1') -Raw
Yes 'Check-VoiceInstall reads Install-Voice beside it, not a Downloads folder' ($cv -notmatch 'Users\\evilp' -and $cv.Contains("Join-Path `$PSScriptRoot '..\deploy\Install-Voice.ps1'"))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
