<#
  test-missing-files-stop.ps1

      pwsh -NoProfile -File .\tests\test-missing-files-stop.ps1

  A file the repository tracks that a build step cannot find stops the build.

  WHY. Build-Launcher.ps1, Package-Thornswood.ps1 and Go.ps1 used to say a
  missing file in yellow and carry on, so a path that went wrong shipped a
  release without the file. The reorganisation (issue #440) moves most of the
  repository, and this is phase 0 of it: before anything moves, a wrong path
  has to be loud. Ship's untracked-file gate also looked only under tools, and
  the folders a release is built from are leaving tools.

  HOW. Reads the scripts as text. Each missing-file line for a tracked file is
  a Die or a Gone, Go.ps1 exits 1 when anything is Gone, and Ship stops when
  Go.ps1 does. Then checks the files these lines name really are tracked, so
  no build stops on something that was never in the repository.
#>
[CmdletBinding()]
param([string]$Repo)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $Repo) { $Repo = $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
# In scripts\<area> since phase 8 of issue #440.
function Read([string]$name) {
    $p = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'scripts') -Filter $name -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)[0]
    if (-not $p) { $p = Join-Path $Repo $name }
    [IO.File]::ReadAllText($p)
}

# ---- Build-Launcher.ps1 --------------------------------------------------------
$b = Read 'Build-Launcher.ps1'
# Since #498's switch the project files hold the list of what goes in, and
# their ThornswoodCheckInputs target stops MSBuild by name on a missing one;
# Build-Launcher.ps1 stops when MSBuild does.
$appProj = [IO.File]::ReadAllText((Join-Path $Repo 'launcher\app\Thornswood.csproj'))
$setupProj = [IO.File]::ReadAllText((Join-Path $Repo 'installer\setup\Setup.csproj'))
$checksInputs = '<Error Condition="!Exists(''%(EmbeddedResource.FullPath)'')"'
Yes 'the launcher project stops the build on any embedded file that is not found' ($appProj.Contains($checksInputs))
foreach ($n in 'logo.png', 'launcher-header.jpg', 'launcher-header.mp4', 'Thornswood.ini', 'client-build.json', 'ui-gone.json') {
    Yes "  $n is one of them" ($appProj -match ('<EmbeddedResource Include="[^"]*' + [regex]::Escape($n) + '"'))
}
Yes 'Build-Launcher stops when MSBuild does' ($b -match 'if \(\$rc -ne 0 -or -not \(Test-Path \$exe\)\) \{ Die "MSBuild exited with \$rc" \}')
Yes '  and no longer only warns about a missing file' ($b -notmatch "is missing, the launcher will run without its emblem' 'Yellow'" -and $b -notmatch "client-build\.json is missing; the launcher will not be able")
Yes 'the setup project compiles Bootstrap.cs, so a missing one stops its build' ($setupProj.Contains('<Compile Include="Bootstrap.cs" />') -and $setupProj.Contains($checksInputs))
Yes 'Build-Launcher stops when the setup stub fails to rebuild' ($b -match "Die 'setup-stub\.exe did not rebuild" -and $b -notmatch "packaging carries on with that one")

# ---- Package-Thornswood.ps1 ----------------------------------------------------
$p = Read 'Package-Thornswood.ps1'
Yes 'Package-Thornswood stops when an installer file is not found' ($p -match 'Die "\$f is not at \$s\.')
Yes '  and no longer only warns' ($p -notmatch 'missing next to this script'' ''Yellow''')

# ---- Go.ps1 ----------------------------------------------------------------------
$g = Read 'Go.ps1'
Yes 'Go.ps1 has a Gone for tracked files that are not found' ($g -match 'function Gone\(\$t\)')
foreach ($what in 'game\\ui\\index.html is missing', 'is not in site\\public', 'game\\ui is not beside tools', 'is not in game\\menu', 'game\\plugins is not beside tools', 'Sync-Client.ps1 is not next') {
    Yes "  $($what -replace '\\\\', '\') is a Gone" ($g -match ('Gone [^\r\n]*' + $what))
}
Yes '  and exits 1 when anything is Gone' ($g -match 'if \(\$script:gone\.Count\) \{[^}]*exit 1' -and $g -match '(?m)^exit 0\s*$')
# The front zip is built from the pinned fork and recorded since #2754, so a
# missing or unrecorded one stops the run like a missing file of ours.
Yes '  a front zip that is missing or not the recorded build is a Gone (#2754)' ($g -match "Gone 'the front is not the recorded build" -and $g -match 'Get-ThornswoodFrontProblems')

# ---- Ship.ps1 --------------------------------------------------------------------
$s = Read 'Ship.ps1'
$go = $s.IndexOf("& (Join-Path `$Here 'Go.ps1') @goArgs")
$stop = $s.IndexOf('if ($LASTEXITCODE -ne 0) {', [Math]::Max($go, 0))
Yes 'Ship stops when Go.ps1 fails' ($go -gt 0 -and $stop -gt $go -and ($stop - $go) -lt 400)
Yes 'Ship''s untracked-file gate looks past tools' ($s -match "\`$moreRoots = @\(@\('scripts', 'records', 'site', 'game', 'launcher', 'installer'\)" -and $s -match 'ls-files --others --exclude-standard -- @moreRoots')

# ---- every file these lines name is tracked --------------------------------------
if (Get-Command git -ErrorAction SilentlyContinue) {
    $tracked = @(& git -C $repo ls-files 2>$null)
    foreach ($f in 'launcher/logo.png', 'launcher/launcher-header.jpg', 'launcher/launcher-header.mp4', 'launcher/Thornswood.ini',
                   'records/client-build.json', 'records/ui-gone.json', 'installer/Setup-Thornswood.ps1', 'installer/Install.bat', 'installer/Setup.bat', 'installer/READ ME FIRST.txt',
                   'game/ui/index.html', 'site/public/banner.webm', 'site/public/banner.mp4', 'site/public/banner.jpg',
                   'game/menu/logo.nif', 'game/menu/logo01ae.nif', 'game/menu/Mainmenuwallpaper.dds', 'scripts/release/Sync-Client.ps1', 'installer/setup/Bootstrap.cs') {
        Yes "$f is tracked, so its absence is a wrong path" ($tracked -contains $f)
    }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
