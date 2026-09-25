<#
  Build-Server.ps1

  Compiles the game server out of our fork and puts the result where
  Deploy-Server.ps1 and Publish-Server.ps1 expect to find it.

  WHY THIS EXISTS

  Every engine change we make lives in the fork, engine\skymp in this
  repository (scripts\release\Where.ps1 Engine says where), on the branch
  thornswood/engine-changes, and until now the only way to turn one into a
  running server was to remember a cmake line and a Visual Studio project name
  and type them by hand. That is fine once. It is not fine when the next
  question is "is the fix in the build that is up there", because the answer
  depends on a command nobody wrote down.

  It also means a Claude working here cannot check its own C++ compiles. The
  permission rules in .claude\settings.json name whole script paths, in the
  same shape as the Deploy and Check lines already in there, so a script is
  the thing that can be allowed. A bare compiler invocation is not.

  WHAT IT BUILDS

  skymp5-server, the Node addon, which comes out as scam_native.node. That is
  the one file records\server-build.json fingerprints and the one file
  Deploy-Server.ps1 refuses to ship when its sha256 is not the recorded one.
  Everything else in the solution is built as a dependency of it and nothing
  else is asked for, because the client runtime is a separate build with its
  own record (records\client-build.json, Sync-Client.ps1).

  WHAT IT DOES NOT DO

  It does not configure. The build folder already carries a CMakeCache from a
  previous configure and reconfiguring is a different job with different
  arguments. If the cache is missing this says so and stops rather than
  guessing at a configure line.

  It does not deploy, it does not talk to the VPS, and it does not touch the
  game folder. It compiles and, unless told not to, updates the build record.

  Usage:
    .\scripts\release\Build-Server.ps1
    .\scripts\release\Build-Server.ps1 -Configuration Debug
    .\scripts\release\Build-Server.ps1 -NoRecord      compile only, leave the record alone

  Exit code 1 if Visual Studio is not installed, if the build folder has not
  been configured, if the compile fails, or if the binary it was supposed to
  produce is not there afterwards.
#>
[CmdletBinding()]
param(
    # Our fork. The branch is checked and reported, never changed.
    [string]$Fork = (& (Join-Path $PSScriptRoot 'Where.ps1') Engine),
    # The already configured CMake build folder inside it.
    [string]$BuildDir = '',
    [ValidateSet('Release', 'Debug', 'RelWithDebInfo')]
    [string]$Configuration = 'Release',
    # Compile and stop. Without this, scripts\release\New-ServerBuildRecord.ps1 runs
    # afterwards so the deploy will accept what was just built.
    [switch]$NoRecord,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Ok($m)  { Write-Host ('  ok    ' + $m) -ForegroundColor Green }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

if (-not $BuildDir) { $BuildDir = Join-Path $Fork 'build' }

Head 'Where the source is'

if (-not (Test-Path -LiteralPath $Fork)) {
    Die "there is no fork at $Fork. DEVELOPING.md says how a machine gets one."
}
Say ("  fork        " + $Fork)

# The branch is reported and never changed. A build off the wrong branch is a
# thing to notice, not a thing for a script to quietly correct.
$branch = ''
try { $branch = (& git -C $Fork rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1) } catch { }
$commit = ''
try { $commit = (& git -C $Fork rev-parse --short HEAD 2>$null | Select-Object -First 1) } catch { }
if ($branch) {
    Say ("  branch      " + $branch + '  ' + $commit)
    if ($branch -ne 'thornswood/engine-changes') {
        Say '  NOTE: that is not thornswood/engine-changes, which is the branch our engine changes live on.' 'Yellow'
    }
}
$dirty = @()
try { $dirty = @(& git -C $Fork status --porcelain 2>$null | Where-Object { $_ }) } catch { }
if ($dirty.Count) {
    Say ("  {0} file(s) in the fork are not committed, and they WILL be in this build:" -f $dirty.Count) 'Yellow'
    foreach ($d in $dirty) { Say ('    ' + $d) 'Yellow' }
}

if (-not (Test-Path -LiteralPath (Join-Path $BuildDir 'CMakeCache.txt'))) {
    Die ("$BuildDir has no CMakeCache.txt, so it has never been configured. " +
         "Configuring is a separate job with its own arguments and this script will not guess at them. " +
         "engine\README.md has the configure line.")
}
Say ("  build       " + $BuildDir)

Head 'The compiler'

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    Die 'vswhere.exe is not there, so Visual Studio is not installed. The Build Tools are enough; the workload is "Desktop development with C++".'
}
$vsPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null | Select-Object -First 1
if (-not $vsPath) {
    Die 'vswhere found no Visual Studio with MSBuild in it. Install the Build Tools with "Desktop development with C++".'
}
$msbuild = Join-Path $vsPath 'MSBuild\Current\Bin\MSBuild.exe'
if (-not (Test-Path -LiteralPath $msbuild)) {
    Die "MSBuild is not at $msbuild even though vswhere pointed at $vsPath."
}
Ok ("MSBuild from " + $vsPath)

Head 'Building'

# skymp5-server is the Node addon and the only thing asked for. Everything it
# needs is built as a dependency; the client runtime is a separate build with
# its own record, so building the whole solution here would be slower and
# would produce files nothing in this repository ships.
$project = Join-Path $BuildDir 'skymp5-server\skymp5-server.vcxproj'
if (-not (Test-Path -LiteralPath $project)) {
    Die "the project is not at $project. Either the build folder was configured for something else or the fork has moved it."
}

$binary = Join-Path $BuildDir ('dist\server\scam_native.node')
$before = ''
if (Test-Path -LiteralPath $binary) {
    $before = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
}

Say ("  " + $Configuration + ', skymp5-server, parallel')
Say ''
& $msbuild $project "/p:Configuration=$Configuration" /m /v:minimal /nologo
$code = $LASTEXITCODE
Say ''
if ($code -ne 0) {
    Die "MSBuild exited with $code. The errors are above, in the order the compiler found them; the first one is usually the only real one."
}
Ok 'compiled'

Head 'What came out'

if (-not (Test-Path -LiteralPath $binary)) {
    Die ("the build said it succeeded and $binary is not there. " +
         "That usually means the project built something else, so check what the solution calls the addon target.")
}
$item  = Get-Item -LiteralPath $binary
$after = (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
Say ("  " + $binary)
Say ("  {0:N0} bytes, written {1}" -f $item.Length, $item.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'))
Say ("  sha256 " + $after.ToLowerInvariant())
if ($before -and $before -eq $after) {
    Say '  IDENTICAL to what was there before this run. Nothing you changed reached this binary.' 'Yellow'
} elseif ($before) {
    Ok 'different from the binary that was there before, so the change is in it'
}

if ($NoRecord) {
    Head 'The record'
    Say '  -NoRecord, so records\server-build.json was left alone.'
    Say '  Deploy-Server.ps1 refuses a binary whose sha256 is not the recorded one, so it will refuse this until the record is updated.'
} else {
    Head 'The record'
    $rec = Join-Path $Here 'New-ServerBuildRecord.ps1'
    if (-not (Test-Path -LiteralPath $rec)) {
        Say "  not found: $rec, so the record was not updated." 'Yellow'
    } else {
        # The same PowerShell that is running this, for the same reason
        # Publish-Server.ps1 does it: handing the job to 5.1 out of a 7 session
        # changes how the file gets written underneath it.
        $ps = (Get-Process -Id $PID).Path
        if (-not $ps) { $ps = 'powershell' }
        & $ps -NoProfile -ExecutionPolicy Bypass -File $rec -NoPause
        if ($LASTEXITCODE -ne 0) {
            Die "New-ServerBuildRecord.ps1 exited with $LASTEXITCODE, so records\server-build.json does not match what was just built."
        }
        Ok 'records\server-build.json now names this binary'
    }
}

Head 'Next'
Say '  Nothing has left this machine. To put it on the live server, as engine\README.md says:'
Say '      .\scripts\deploy\Deploy-Server.ps1' 'White'
Say '  That is the one that goes outside, and it is Patrick''s to run.'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
