<#
  test-bump-version-live.ps1

  Bump-Version.ps1 never proposes, and refuses to write, a launcher number at or
  below the one live launchers already have.

  25 September: main's Updater.cs said 1.1.92 while the hotfixes had put 1.1.94
  on every live launcher. The plain bump would have made 1.1.93, which the
  updater never takes over 1.1.94, and a main release resets dev, so dev
  launchers on 1.1.94.1 would have ignored it too. Nothing said so.

  This runs the real Bump-Version.ps1 with -WhatIf, which stops before it writes
  or commits, in a scratch repository with a stand-in Thornswood-Releases
  beside it, the layout Ship reads, and reads what it says and how it exits.
  Pointed at another copy with -BumpPath, it shows the checks fail on the
  script before the change. Everything it makes is under a temp folder it
  removes.
#>
[CmdletBinding()]
param([string]$BumpPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $BumpPath) { $BumpPath = Join-Path $Here '..\scripts\release\Bump-Version.ps1' }
$shell = (Get-Process -Id $PID).Path

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-bump-' + [Guid]::NewGuid().ToString('N'))

# A repository whose Updater.cs says $current, with a releases feed beside it
# saying $live, or no feed at all. Returns what -WhatIf printed and its exit.
function Run([string]$current, [string]$live, [string[]]$extra) {
    $root = Join-Path $work ([Guid]::NewGuid().ToString('N'))
    $repo = Join-Path $root 'Thornswood-Repo'
    New-Item -ItemType Directory -Path (Join-Path $repo 'launcher\app'), (Join-Path $repo 'scripts\release') -Force | Out-Null
    Copy-Item -LiteralPath $BumpPath -Destination (Join-Path $repo 'scripts\release\Bump-Version.ps1')
    $cs = Join-Path $repo 'launcher\app\Updater.cs'
    [IO.File]::WriteAllText($cs, "namespace Thornswood { static class Updater {`n    public const string Version = `"$current`";`n} }`n")
    & git -C $repo init -q 2>&1 | Out-Null
    if ($live) {
        $rel = Join-Path $root 'Thornswood-Releases'
        New-Item -ItemType Directory -Path $rel -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $rel 'version.json'), '{"launcherVersion":"' + $live + '","packs":[]}')
    }
    $args2 = @('-NoProfile', '-File', (Join-Path $repo 'scripts\release\Bump-Version.ps1'), '-WhatIf', '-NoPause') + $extra
    $out = (& $shell @args2 2>&1 | Out-String)
    return @{ Out = $out; Code = $LASTEXITCODE; Cs = [IO.File]::ReadAllText($cs); Repo = $repo }
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
    Yes 'with no releases clone it bumps as before' ($r.Code -eq 0 -and $r.Out -match '1\.1\.92\s+->\s+1\.1\.93')
    Yes 'and says the number was not checked' ($r.Out -match 'not checked')
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
