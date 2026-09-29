<#
  Build-Engine.ps1

  Takes a machine from a fresh clone to a built engine: the SkyMP server and
  the client runtime, out of the fork in engine\skymp. Any developer runs it
  on their own machine; nothing about it is Patrick's.

      .\scripts\release\Build-Engine.ps1                first time: checks, configures, builds
      .\scripts\release\Build-Engine.ps1 -Check         says what is missing, changes nothing

  WHY THIS EXISTS. Until 25 September a dev Ship worked only on Patrick's
  machine: Ship checks the client runtime against records\client-build.json,
  and the only built engine was his, configured by hand from a line in
  engine\README.md that no script ran (issue #545). Patrick, asked whether to
  work around it: "Can't we just add the ability and instructions for people
  to do that instead of doing workarounds". This is the ability;
  engine\README.md is the instructions.

  WHAT IT DOES, IN ORDER
    1. Checks the tools: Visual Studio 2022 or its Build Tools with MSBuild
       ("Desktop development with C++"), CMake (the one in Visual Studio is
       found), git, node and yarn. Says exactly what to install for anything
       missing and stops before building.
    2. Fetches the fork at the commit this repository pins, and the fork's own
       submodules (vcpkg among them).
    3. Configures engine\skymp\build if it has never been configured, with
       the settings engine\README.md gives (read off the shipping machine's
       CMakeCache, 24 Sep; the option names checked against the fork's
       CMakeLists.txt on 25 Sep). SKYRIM_DIR is the game folder with
       SkyrimSE.exe in it: C:\Thornswood\Game unless -SkyrimDir says another.
       The first configure builds every vcpkg library and takes a long time.
    4. Builds everything, Release. After the first time only what changed is
       rebuilt, so a fork change that touches the client bundle is quick.
    5. Compares the six client files with records\client-build.json, the check
       Ship makes, and says whether this build is the recorded one.

  WHAT IT DOES NOT DO. It never changes a record: when the build is not the
  recorded one it says so, and New-ClientBuildRecord.ps1 is the step for a
  deliberate engine change (engine\README.md). It sends nothing anywhere and
  never touches the game folder; Sync-Client.ps1 copies the files in.
#>
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$SkyrimDir = 'C:\Thornswood\Game',
    [string]$Fork = (& (Join-Path $PSScriptRoot 'Where.ps1') Engine),
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Ok($m) { Write-Host ('  ok       ' + $m) -ForegroundColor Green }
function Miss($m) { Write-Host ('  MISSING  ' + $m) -ForegroundColor Red }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }
# Native tools write progress to stderr; the exit code alone decides. Their
# output is written to the screen, not returned: returned, every line cmake
# printed came back with the code, "$code -ne 0" was true for any configure
# or build that printed anything, and a configure that succeeded stopped with
# "cmake configure exited with ... 0" (found building for #919).
function Run {
    $ErrorActionPreference = 'Continue'
    & $args[0] @($args | Select-Object -Skip 1) 2>&1 | ForEach-Object { Write-Host $_ }
    return [int]$LASTEXITCODE
}

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$build = Join-Path $Fork 'build'
$record = Join-Path $repo 'records\client-build.json'

# ---- 1. tools ---------------------------------------------------------------
Head 'Tools'
$missing = 0
$msbuild = $null; $vsPath = $null
$vswhere = $null
if (${env:ProgramFiles(x86)}) { $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe' }
if ($vswhere -and (Test-Path -LiteralPath $vswhere)) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null | Select-Object -First 1
}
if ($vsPath -and (Test-Path -LiteralPath (Join-Path $vsPath 'MSBuild\Current\Bin\MSBuild.exe'))) {
    $msbuild = Join-Path $vsPath 'MSBuild\Current\Bin\MSBuild.exe'; Ok "MSBuild, $vsPath"
} else { Miss 'Visual Studio 2022 or Build Tools 2022 with the "Desktop development with C++" workload: https://visualstudio.microsoft.com/downloads/'; $missing++ }

$cmake = (Get-Command cmake -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if (-not $cmake -and $vsPath) {
    $c = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (Test-Path -LiteralPath $c) { $cmake = $c }
}
if ($cmake) { Ok "cmake, $cmake" } else { Miss 'CMake: the C++ workload above installs it'; $missing++ }
foreach ($t in @(
        @{ Name = 'git'; How = 'Git for Windows: https://git-scm.com/download/win' },
        @{ Name = 'node'; How = 'Node.js 24: https://nodejs.org/' },
        @{ Name = 'yarn'; How = 'yarn: run  corepack enable  in an administrator PowerShell once Node is in (the fork builds its client with yarn)' })) {
    $g = Get-Command $t.Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g) { Ok ($t.Name + ', ' + $g.Source) } else { Miss $t.How; $missing++ }
}
if (Test-Path -LiteralPath (Join-Path $SkyrimDir 'SkyrimSE.exe')) { Ok "SkyrimSE.exe in $SkyrimDir" }
else { Miss "SkyrimSE.exe in $SkyrimDir. Install Thornswood first (the launcher makes that folder), or pass -SkyrimDir with the folder that has it."; $missing++ }
if ($missing) { Die "$missing thing(s) missing, listed above. Nothing was built." }

# ---- 2. the fork ------------------------------------------------------------
Head 'The fork'
if (-not (Test-Path -LiteralPath (Join-Path $Fork 'CMakeLists.txt'))) {
    if ($Check) { Miss "the fork is not checked out at $Fork; this run would fetch it" }
    else {
        Say "  fetching the fork into $Fork (the commit this repository pins)"
        if ((Run git -C $repo submodule update --init engine/skymp) -ne 0) { Die 'git could not fetch engine\skymp. Is this a clone of the repository, and can this account read EvilPatrick06/skymp?' }
    }
}
$pinned = ((& git -C $repo ls-tree HEAD engine/skymp 2>$null) -split '\s+')[2]
$at = (& git -C $Fork rev-parse HEAD 2>$null | Select-Object -First 1)
if ($at) {
    Say ("  pinned   {0}" -f $pinned)
    Say ("  at       {0}" -f $at)
    if ($pinned -and $at -ne $pinned) { Say '  NOTE: the fork is not at the pinned commit. That is expected while you change the engine; otherwise run  git submodule update engine/skymp' 'Yellow' }
}
if (-not $Check -and (Test-Path -LiteralPath (Join-Path $Fork 'CMakeLists.txt'))) {
    Say '  the fork''s own submodules (vcpkg among them)'
    if ((Run git -C $Fork submodule update --init --recursive) -ne 0) { Die 'git could not fetch the fork''s submodules.' }
    Ok 'fork ready'
}

# ---- 3. configure -----------------------------------------------------------
Head 'Configure'
$cache = Join-Path $build 'CMakeCache.txt'
if (Test-Path -LiteralPath $cache) { Ok "already configured: $build" }
elseif ($Check) { Miss "$build is not configured; this run would configure it (the first time builds every vcpkg library, which is slow)" }
else {
    $toolchain = Join-Path $Fork 'vcpkg\scripts\buildsystems\vcpkg.cmake'
    Say '  configuring. The first time builds every vcpkg library; expect it to take a long while.'
    $code = Run $cmake -S $Fork -B $build -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_TOOLCHAIN_FILE=$toolchain" '-DVCPKG_TARGET_TRIPLET=x64-windows-sp' '-DOFFLINE_MODE=ON' '-DBUILD_CLIENT=ON' '-DBUILD_SKYRIM_PLATFORM=ON' "-DSKYRIM_DIR=$SkyrimDir"
    if ($code -ne 0) { Die "cmake configure exited with $code. The first error above is usually the real one." }
    Ok 'configured'
}

if ($Check) {
    Head 'Check finished'
    Say '  Nothing was changed. Run without -Check to fetch, configure and build.' 'Yellow'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ---- 4. build ---------------------------------------------------------------
Head 'Build'
Say '  Release, everything (only what changed, after the first time)'
# '--' is quoted: bare, PowerShell takes it as the end of Run's own
# parameters and drops it, and cmake then refuses /m as its own argument.
$code = Run $cmake --build $build --config Release '--' /m /v:minimal /nologo
if ($code -ne 0) { Die "the build exited with $code. The errors are above; the first one is usually the only real one." }
Ok 'built'

# ---- 5. the recorded client -------------------------------------------------
Head 'Is this the recorded client?'
$rec = Get-Content -LiteralPath $record -Raw | ConvertFrom-Json
$dist = Join-Path $build 'dist\client'
$differ = 0
foreach ($rel in @($rec.files.PSObject.Properties.Name)) {
    $p = Join-Path $dist $rel
    if (-not (Test-Path -LiteralPath $p)) { Miss $rel; $differ++; continue }
    $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($h -eq $rec.files.$rel.sha256) { Ok $rel } else { Say ('  differs  ' + $rel) 'Yellow'; $differ++ }
}
Say ''
if ($differ) {
    Say "  $differ of the six are not the recorded build (records\client-build.json, fork $($rec.forkCommit))." 'Yellow'
    Say '  If you changed the engine on purpose: .\scripts\release\New-ClientBuildRecord.ps1, and the new record goes in your pull request.' 'Gray'
    Say '  If you did not: the fork is not at the pinned commit, or this machine builds the native files differently; engine\README.md says what to do.' 'Gray'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 2
}
Say '  All six are the recorded build. .\scripts\release\Sync-Client.ps1 puts them in the game, and a dev Ship will accept them.' 'Green'
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
exit 0
