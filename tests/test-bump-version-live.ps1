<#
  test-bump-version-live.ps1

  Bump-Version.ps1 never proposes, and refuses to write, a launcher number at or
  below the one live launchers already have.

  25 September: main's Updater.cs said 1.1.92 while the hotfixes had put 1.1.94
  on every live launcher. The plain bump would have made 1.1.93, which the
  updater never takes over 1.1.94, and a main release resets dev, so dev
  launchers on 1.1.94.1 would have ignored it too. Nothing said so.

  This runs the real Bump-Version.ps1 with -WhatIf, which stops before it writes
  or commits, in a scratch repository with a stand-in for the site's live feed
  (THORNSWOOD_TEST_SITE_DIR), the feed Ship reads, and reads what it says and how it exits.
  Pointed at another copy with -BumpPath, it shows the checks fail on the
  script before the change. Everything it makes is under a temp folder it
  removes.
#>
[CmdletBinding()]
param([string]$BumpPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
. (Join-Path $PSScriptRoot 'Windows.ps1')
if (-not $BumpPath) { $BumpPath = Join-Path $Here 'scripts\release\Bump-Version.ps1' }
$shell = (Get-Process -Id $PID).Path

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-bump-' + [Guid]::NewGuid().ToString('N'))

# A repository whose Updater.cs says $current, with a live feed on the stand-in site
# saying $live, or no feed at all. Returns what -WhatIf printed and its exit.
function Run([string]$current, [string]$live, [string[]]$extra) {
    $root = Join-Path $work ([Guid]::NewGuid().ToString('N'))
    $repo = Join-Path $root 'Thornswood-Repo'
    New-Item -ItemType Directory -Path (Join-Path $repo 'launcher\app'), (Join-Path $repo 'scripts\release') -Force | Out-Null
    Copy-Item -LiteralPath $BumpPath -Destination (Join-Path $repo 'scripts\release\Bump-Version.ps1')
    $cs = Join-Path $repo 'launcher\app\Updater.cs'
    [IO.File]::WriteAllText($cs, "namespace Thornswood { static class Updater {`n    public const string Version = `"$current`";`n} }`n")
    & git -C $repo init -q 2>&1 | Out-Null
    # The site's root, standing in for thornswood.net (Feed-Store.ps1's test
    # variable), so the live feed is read from a file and nothing is fetched.
    $site = Join-Path $root 'site'
    New-Item -ItemType Directory -Path (Join-Path $site 'feed\version') -Force | Out-Null
    if ($live) {
        # The feed's newest generation (Feed-Store.ps1, #2727).
        [IO.File]::WriteAllText((Join-Path $site 'feed\version\00000001.json'), '{"launcherVersion":"' + $live + '","packs":[]}')
    }
    $args2 = @('-NoProfile', '-File', (Join-Path $repo 'scripts\release\Bump-Version.ps1'), '-WhatIf', '-NoPause') + $extra
    $oldSite = $env:THORNSWOOD_TEST_SITE_DIR
    $env:THORNSWOOD_TEST_SITE_DIR = $site
    try { $out = (& $shell @args2 2>&1 | Out-String); $code = $LASTEXITCODE }
    finally { $env:THORNSWOOD_TEST_SITE_DIR = $oldSite }
    return @{ Out = $out; Code = $code; Cs = [IO.File]::ReadAllText($cs); Repo = $repo }
}

try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null

    # 1. 25 September exactly.
    $r = Run '1.1.92' '1.1.94' @()
    Yes 'main on 1.1.92 with 1.1.94 live proposes 1.1.95' ($r.Out -match '1\.1\.92\s+->\s+1\.1\.95')
    Yes 'and says why, naming the live number' ($r.Out -match 'already have 1\.1\.94')
    Yes 'and -WhatIf wrote nothing' ($r.Cs.Contains('"1.1.92"'))
    Yes 'and exits 0' ($r.Code -eq 0)

    # 2. A number asked for that no launcher would take.
    $r = Run '1.1.92' '1.1.94' @('-To', '1.1.93')
    Yes '-To 1.1.93 with 1.1.94 live is refused' ($r.Code -ne 0 -and $r.Out -match 'STOP')
    Yes 'and the refusal names the live number and what to give instead' ($r.Out -match '1\.1\.94' -and $r.Out -match 'above 1\.1\.94')
    $r = Run '1.1.92' '1.1.94' @('-To', '1.1.94')
    Yes 'so is -To the live number itself' ($r.Code -ne 0)
    $r = Run '1.1.92' '1.1.94' @('-To', '1.1.95')
    Yes '-To above it goes through' ($r.Code -eq 0 -and $r.Out -match '1\.1\.92\s+->\s+1\.1\.95')

    # 3. The ordinary case is unchanged.
    $r = Run '1.1.94' '1.1.94' @()
    Yes 'main level with live bumps as it always did' ($r.Code -eq 0 -and $r.Out -match '1\.1\.94\s+->\s+1\.1\.95')
    Yes 'and says nothing about the live number' ($r.Out -notmatch 'already have')
    $r = Run '1.1.94' '1.1.93' @()
    Yes 'main ahead of live is left alone' ($r.Code -eq 0 -and $r.Out -match '1\.1\.94\s+->\s+1\.1\.95')

    # 4. Nothing to read.
    $r = Run '1.1.92' '' @()
    Yes 'with no live feed to read it bumps as before' ($r.Code -eq 0 -and $r.Out -match '1\.1\.92\s+->\s+1\.1\.93')
    Yes 'and says the number was not checked' ($r.Out -match 'not checked')

    # 5. The next steps on main (#2711). Asking GitHub whether main is
    # protected against everybody had an empty catch, and a gh that could not
    # answer read as "off": the steps then printed a direct push as allowed.
    # A real run here, not -WhatIf, in a scratch repository on main with a
    # stand-in gh first on the path; the commit it makes is the scratch one's.
    function RunMain([string]$ghSays, [int]$ghExit) {
        $root = Join-Path $work ([Guid]::NewGuid().ToString('N'))
        $repo = Join-Path $root 'Thornswood-Repo'
        New-Item -ItemType Directory -Path (Join-Path $repo 'launcher\app'), (Join-Path $repo 'scripts\release') -Force | Out-Null
        Copy-Item -LiteralPath $BumpPath -Destination (Join-Path $repo 'scripts\release\Bump-Version.ps1')
        [IO.File]::WriteAllText((Join-Path $repo 'launcher\app\Updater.cs'), "namespace Thornswood { static class Updater {`n    public const string Version = `"1.1.94`";`n} }`n")
        & { $ErrorActionPreference = 'Continue'
            & git -C $repo init -q -b main 2>&1 | Out-Null
            & git -C $repo config user.email t@t 2>&1 | Out-Null
            & git -C $repo config user.name t 2>&1 | Out-Null
            & git -C $repo add -A 2>&1 | Out-Null
            & git -C $repo commit -q -m one 2>&1 | Out-Null }
        $bin = Join-Path $root 'bin'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        # A .cmd runs only on Windows; elsewhere the stand-in is a shell script.
        if ($OnWindows) { [IO.File]::WriteAllText((Join-Path $bin 'gh.cmd'), "@echo off`r`necho $ghSays`r`nexit /b $ghExit`r`n") }
        else {
            [IO.File]::WriteAllText((Join-Path $bin 'gh'), "#!/bin/sh`nprintf '%s\n' '" + $ghSays.Replace("'", "'\''") + "'`nexit $ghExit`n")
            & chmod 755 (Join-Path $bin 'gh')
        }
        $site = Join-Path $root 'site'
        New-Item -ItemType Directory -Path (Join-Path $site 'feed') -Force | Out-Null
        $oldSite = $env:THORNSWOOD_TEST_SITE_DIR; $oldPath = $env:PATH
        $env:THORNSWOOD_TEST_SITE_DIR = $site; $env:PATH = $bin + [IO.Path]::PathSeparator + $env:PATH
        try { $out = (& $shell -NoProfile -File (Join-Path $repo 'scripts\release\Bump-Version.ps1') -NoPause 2>&1 | Out-String); $code = $LASTEXITCODE }
        finally { $env:THORNSWOOD_TEST_SITE_DIR = $oldSite; $env:PATH = $oldPath }
        return @{ Out = $out; Code = $code }
    }
    $r = RunMain 'HTTP 401: Bad credentials' 1
    Yes 'a gh that cannot answer is said, with what it said' ($r.Code -eq 0 -and $r.Out -match 'Could not ask GitHub whether main is protected' -and $r.Out -match 'exit 1' -and $r.Out -match 'Bad credentials')
    Yes '  and the steps take the branch, never a direct push' ($r.Out -match 'git push -u origin patrick/launcher-1\.1\.95' -and $r.Out -notmatch 'direct push to main is still allowed')
    $r = RunMain 'true' 0
    Yes 'protection on: the branch, as before' ($r.Out -match 'protected against everybody, including you' -and $r.Out -match 'git push -u origin patrick/launcher-1\.1\.95')
    $r = RunMain 'false' 0
    Yes 'protection off: the direct push, as before' ($r.Out -match 'direct push to main is still allowed' -and $r.Out -notmatch 'patrick/launcher-')
    $r = RunMain 'null' 0
    Yes 'an answer that is neither true nor false is said, and takes the branch' ($r.Out -match 'not true or false' -and $r.Out -match 'git push -u origin patrick/launcher-1\.1\.95')
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
