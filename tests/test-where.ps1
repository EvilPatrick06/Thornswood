<#
  test-where.ps1

      pwsh -NoProfile -File .\tests\test-where.ps1

  Where.ps1 finds the engine fork and the build output in the repository once
  they are there, in C:\Thornswood-Dev while they are still there, and in the
  repository on a machine that never had that folder; and no script names
  C:\Thornswood-Dev for itself any more.

  WHY. On 25 September the fork, its build and the release output moved from
  C:\Thornswood-Dev into the repository (engine\skymp, a submodule, and out,
  ignored by git), asked for by Patrick and agreed by Djinn. About thirty
  scripts named the old folder by hand. They ask Where.ps1 now, and it has to
  be right before, during and after the move on each machine, because a
  script pointed at a folder that is not there deploys nothing, or the wrong
  thing.

  HOW. The real Where.ps1 is copied into a scratch repository under a temp
  folder, with a stand-in for the old folder beside it, and asked for each
  place at each stage of the move. The scripts are read with PowerShell's own
  parser, so a path in a comment does not count and a path in a string does.
  Nothing outside the temp folder is touched.
#>
[CmdletBinding()]
param([string]$Tools)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $Tools) { $Tools = $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$where = Join-Path $Tools '..\scripts\release\Where.ps1'
Yes 'scripts\release\Where.ps1 is there' (Test-Path -LiteralPath $where)
if (-not (Test-Path -LiteralPath $where)) { Write-Host ''; Write-Host '0 passed, 1 failed'; exit 1 }

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-where-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    $repo = Join-Path $work 'Thornswood-Repo'
    $old = Join-Path $work 'Thornswood-Dev'
    New-Item -ItemType Directory -Force -Path (Join-Path $repo 'scripts\release') | Out-Null
    Copy-Item -LiteralPath $where -Destination (Join-Path $repo 'scripts\release\Where.ps1')
    $w = Join-Path $repo 'scripts\release\Where.ps1'
    function Ask([string]$what) { return [string](& $w $what -OldRoot $old) }
    function Same([string]$a, [string]$b) { return [IO.Path]::GetFullPath($a).TrimEnd('\', '/') -eq [IO.Path]::GetFullPath($b).TrimEnd('\', '/') }
    $newEngine = Join-Path $repo 'engine\skymp'
    $newOut = Join-Path $repo 'out'
    $oldEngine = Join-Path $old 'skymp'

    # 1. A machine that never had the old folder: Djinn's, or a fresh clone.
    Yes 'Repo is the folder above tools' (Same (Ask 'Repo') $repo)
    Yes 'Releases is the sibling Thornswood-Releases' (Same (Ask 'Releases') (Join-Path (Split-Path -Parent $repo) 'Thornswood-Releases'))
    Yes 'ReleasesDev is the sibling Thornswood-Releases-dev' (Same (Ask 'ReleasesDev') (Join-Path (Split-Path -Parent $repo) 'Thornswood-Releases-dev'))
    Yes 'with nothing anywhere, the engine is engine\skymp' (Same (Ask 'Engine') $newEngine)
    Yes 'and the output is out' (Same (Ask 'Out') $newOut)
    Yes 'and ServerDist is under the engine''s build' (Same (Ask 'ServerDist') (Join-Path $newEngine 'build\dist\server'))
    Yes 'and Package is out\dist\Thornswood\_dist' (Same (Ask 'Package') (Join-Path $newOut 'dist\Thornswood\_dist'))

    # 2. Patrick's machine before the move: the old folder is full, and the
    #    submodule is the empty folder git leaves for one not fetched yet.
    New-Item -ItemType Directory -Force -Path (Join-Path $oldEngine 'build\dist\server') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $old 'dist\Thornswood\_dist') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $old '_payload') | Out-Null
    [IO.File]::WriteAllText((Join-Path $oldEngine 'CMakeLists.txt'), 'project(skymp)')
    New-Item -ItemType Directory -Force -Path $newEngine | Out-Null
    Yes 'before the move, an empty engine\skymp does not count and the old clone is the engine' (Same (Ask 'Engine') $oldEngine)
    Yes 'and ServerDist, ClientDist, ServerSettings and ChangeForms are the old build''s' (
        (Same (Ask 'ServerDist') (Join-Path $oldEngine 'build\dist\server')) -and
        (Same (Ask 'ClientDist') (Join-Path $oldEngine 'build\dist\client')) -and
        (Same (Ask 'ServerSettings') (Join-Path $oldEngine 'build\dist\server\server-settings.json')) -and
        (Same (Ask 'ChangeForms') (Join-Path $oldEngine 'build\dist\server\world\changeForms')))
    Yes 'and the output is the old folder: Dist, Package, Payload and ServerZip' (
        (Same (Ask 'Out') $old) -and
        (Same (Ask 'Dist') (Join-Path $old 'dist')) -and
        (Same (Ask 'Package') (Join-Path $old 'dist\Thornswood\_dist')) -and
        (Same (Ask 'Payload') (Join-Path $old '_payload')) -and
        (Same (Ask 'ServerZip') (Join-Path $old 'thornswood-server.zip')))

    # 3. Halfway: the engine has moved and the output has not.
    [IO.File]::WriteAllText((Join-Path $newEngine 'CMakeLists.txt'), 'project(skymp)')
    Yes 'once engine\skymp has the fork in it, it is the engine even with the old clone still there' (Same (Ask 'Engine') $newEngine)
    Yes 'and the output stays where it is until out exists' (Same (Ask 'Out') $old)

    # 4. After the move.
    New-Item -ItemType Directory -Force -Path $newOut | Out-Null
    Yes 'once out exists, it is the output' (Same (Ask 'Out') $newOut)
    Yes 'and Dist is out\dist' (Same (Ask 'Dist') (Join-Path $newOut 'dist'))

    # 5. A name nobody knows is refused rather than guessed at.
    $refused = $false
    try { & $w 'Engin' -OldRoot $old | Out-Null } catch { $refused = $true }
    Yes 'a place Where.ps1 does not know is refused' $refused

    # ---- the scripts --------------------------------------------------------
    # A string naming C:\Thornswood-Dev, other than in Where.ps1 itself, in
    # the release test's made-up asset names.
    $allowed = @('Where.ps1', 'test-release-prerelease.ps1', 'test-where.ps1')
    $named = @()
    $keys = @('Repo', 'Engine', 'ServerDist', 'ClientDist', 'ServerSettings', 'ChangeForms', 'Out', 'Dist', 'Package', 'Payload', 'ServerZip', 'Releases', 'ReleasesDev')
    $badKeys = @()
    $callers = 0
    # scripts\<area> since phase 8 of issue #440; scripts\oneoff is parked history.
    $scriptsDir = Join-Path (Split-Path -Parent $Tools) 'scripts'
    foreach ($f in @(Get-ChildItem -LiteralPath $scriptsDir -Filter *.ps1 -File -Recurse | Where-Object { $_.FullName -notmatch '[\\/]oneoff[\\/]' })) {
        $tokens = $null; $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        if ($allowed -notcontains $f.Name) {
            foreach ($t in $tokens) {
                if (($t.Kind -eq 'StringLiteral' -or $t.Kind -eq 'StringExpandable') -and $t.Text -match '(?i)C:[\\/]+Thornswood-Dev(?!Build)') {
                    $named += ('{0}:{1}' -f $f.Name, $t.Extent.StartLineNumber)
                }
            }
        }
        $text = [IO.File]::ReadAllText($f.FullName)
        foreach ($m in [regex]::Matches($text, "Join-Path \`$PSScriptRoot '(?:\.\.\\release\\)?Where\.ps1'\)\s+(\w+)")) {
            $callers++
            if ($keys -notcontains $m.Groups[1].Value) { $badKeys += ('{0}: {1}' -f $f.Name, $m.Groups[1].Value) }
        }
    }
    Yes ('no script names C:\Thornswood-Dev for itself' + $(if ($named.Count) { ': ' + ($named -join ', ') } else { '' })) ($named.Count -eq 0)
    Yes ('the scripts ask Where.ps1 ({0} places)' -f $callers) ($callers -ge 30)
    Yes ('and only for places it knows' + $(if ($badKeys.Count) { ': ' + ($badKeys -join ', ') } else { '' })) ($badKeys.Count -eq 0)
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
