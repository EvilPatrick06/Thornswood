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
param([string]$Tools)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $Tools) { $Tools = $Here }
$repo = Split-Path -Parent $Tools

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Read([string]$name) { [IO.File]::ReadAllText((Join-Path $Tools $name)) }

# ---- Build-Launcher.ps1 --------------------------------------------------------
$b = Read 'Build-Launcher.ps1'
foreach ($n in 'logo.png', 'launcher-header.jpg', 'launcher-header.mp4', 'Thornswood.ini', 'client-build.json') {
    Yes "Build-Launcher stops when $n is not found" ($b -match ('Die "' + [regex]::Escape($n) + ' is not at'))
}
Yes '  and no longer only warns about any of them' ($b -notmatch "is missing, the launcher will run without its emblem' 'Yellow'" -and $b -notmatch "client-build\.json is missing; the launcher will not be able")

# ---- Package-Thornswood.ps1 ----------------------------------------------------
$p = Read 'Package-Thornswood.ps1'
Yes 'Package-Thornswood stops when an installer file is not found' ($p -match 'Die "\$f is not at \$s\.')
Yes '  and no longer only warns' ($p -notmatch 'missing next to this script'' ''Yellow''')

# ---- Go.ps1 ----------------------------------------------------------------------
$g = Read 'Go.ps1'
Yes 'Go.ps1 has a Gone for tracked files that are not found' ($g -match 'function Gone\(\$t\)')
foreach ($what in 'ts-ui\\index.html is missing', 'is not in site\\public', 'the ts-ui folder is not next', 'is not in tools\\art\\menu', 'the ts-plugins folder is not next', 'Sync-Client.ps1 is not next') {
    Yes "  $($what -replace '\\\\', '\') is a Gone" ($g -match ('Gone [^\r\n]*' + $what))
}
Yes '  and exits 1 when anything is Gone' ($g -match 'if \(\$script:gone\.Count\) \{[^}]*exit 1' -and $g -match '(?m)^exit 0\s*$')
Yes '  the front zip, which git never had, stays a warning' ($g -match "Bad 'thornswood-front\.zip is not next to this script'")

# ---- Ship.ps1 --------------------------------------------------------------------
$s = Read 'Ship.ps1'
$go = $s.IndexOf("& (Join-Path `$Here 'Go.ps1') @goArgs")
$stop = $s.IndexOf('if ($LASTEXITCODE -ne 0) {', [Math]::Max($go, 0))
Yes 'Ship stops when Go.ps1 fails' ($go -gt 0 -and $stop -gt $go -and ($stop - $go) -lt 400)
Yes 'Ship''s untracked-file gate looks past tools' ($s -match "\`$moreRoots = @\(@\('site', 'game', 'launcher', 'installer'\)" -and $s -match 'ls-files --others --exclude-standard -- tools @moreRoots')

# ---- every file these lines name is tracked --------------------------------------
if (Get-Command git -ErrorAction SilentlyContinue) {
    $tracked = @(& git -C $repo ls-files 2>$null)
    foreach ($f in 'tools/logo.png', 'tools/launcher-header.jpg', 'tools/launcher-header.mp4', 'tools/emotes/Thornswood.ini',
                   'tools/client-build.json', 'tools/Setup-Thornswood.ps1', 'tools/Install.bat', 'tools/Setup.bat', 'tools/READ ME FIRST.txt',
                   'tools/ts-ui/index.html', 'site/public/banner.webm', 'site/public/banner.mp4', 'site/public/banner.jpg',
                   'tools/art/menu/logo.nif', 'tools/art/menu/logo01ae.nif', 'tools/art/menu/Mainmenuwallpaper.dds', 'tools/Sync-Client.ps1') {
        Yes "$f is tracked, so its absence is a wrong path" ($tracked -contains $f)
    }
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
