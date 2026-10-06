<#
  test-where.ps1

      pwsh -NoProfile -File .\tests\test-where.ps1

  Where.ps1 finds the engine fork and the build output in the repository,
  always, and where.js agrees with it; no script names the old
  C:\Thornswood-Dev folder for itself, and nothing falls back to it or to the
  old tools\ paths any more.

  WHY. On 25 September the fork, its build and the release output moved from
  C:\Thornswood-Dev into the repository (engine\skymp, a submodule, and out,
  ignored by git), asked for by Patrick and agreed by Djinn. About thirty
  scripts named the old folder by hand. They ask Where.ps1 now. Until
  28 September Where.ps1 and where.js also answered with the old folder, or
  an old tools\ path, while a machine still had one; no machine does, and the
  rule is no backwards compatibility except for updating (issue #440), so
  that fallback went. This makes sure it stays gone: a stand-in old folder
  full of files must not change any answer.

  HOW. The real Where.ps1, where.js and layout.json are copied into a scratch
  repository under a temp folder and asked for each place. The scripts are
  read with PowerShell's own parser, so a path in a comment does not count and
  a path in a string does. Nothing outside the temp folder is touched.
#>
[CmdletBinding()]
param([string]$Tools)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\; $Tools is the tools folder beside them, which is
# how every harness here finds the repository.
$Here = Split-Path -Parent $Here
if (-not $Tools) { $Tools = $Here }
$realRepo = $Tools

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$where = Join-Path $realRepo 'scripts\release\Where.ps1'
Yes 'scripts\release\Where.ps1 is there' (Test-Path -LiteralPath $where)
if (-not (Test-Path -LiteralPath $where)) { Write-Host ''; Write-Host '0 passed, 1 failed'; exit 1 }

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-where-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    $repo = Join-Path $work 'Thornswood-Repo'
    $old = Join-Path $work 'Thornswood-Dev'
    New-Item -ItemType Directory -Force -Path (Join-Path $repo 'scripts\release') | Out-Null
    Copy-Item -LiteralPath $where -Destination (Join-Path $repo 'scripts\release\Where.ps1')
    $layoutSrc = Join-Path $realRepo 'layout.json'
    Yes 'layout.json is at the repository root' (Test-Path -LiteralPath $layoutSrc)
    Copy-Item -LiteralPath $layoutSrc -Destination (Join-Path $repo 'layout.json')
    $whereJsSrc = Join-Path $realRepo 'scripts\release\where.js'
    Yes 'scripts\release\where.js is there' (Test-Path -LiteralPath $whereJsSrc)
    Copy-Item -LiteralPath $whereJsSrc -Destination (Join-Path $repo 'scripts\release\where.js')
    $w = Join-Path $repo 'scripts\release\Where.ps1'
    function Ask([string]$what) { return [string](& $w $what) }
    function Same([string]$a, [string]$b) { return [IO.Path]::GetFullPath($a).TrimEnd('\', '/') -eq [IO.Path]::GetFullPath($b).TrimEnd('\', '/') }
    $newEngine = Join-Path $repo 'engine\skymp'
    $newOut = Join-Path $repo 'out'

    # 1. A fresh clone: nothing fetched, nothing built.
    Yes 'Repo is the folder above scripts\release' (Same (Ask 'Repo') $repo)
    Yes 'Releases is this machine''s working copy of the main feed (#907)' (Same (Ask 'Releases') (Join-Path $env:LOCALAPPDATA 'Thornswood\feed\main'))
    Yes 'ReleasesDev is the dev one' (Same (Ask 'ReleasesDev') (Join-Path $env:LOCALAPPDATA 'Thornswood\feed\dev'))
    Yes 'ShipRoots is beside them, in this machine''s own data (#1692; tests\test-1692-release-root.ps1 holds the rest)' (
        Same (Ask 'ShipRoots') (Join-Path $env:LOCALAPPDATA 'Thornswood\ship-roots.json'))
    Yes 'with nothing anywhere, the engine is engine\skymp' (Same (Ask 'Engine') $newEngine)
    Yes 'and the output is out' (Same (Ask 'Out') $newOut)
    Yes 'and ServerDist is under the engine''s build' (Same (Ask 'ServerDist') (Join-Path $newEngine 'build\dist\server'))
    Yes 'and Package is out\dist\Thornswood\_dist' (Same (Ask 'Package') (Join-Path $newOut 'dist\Thornswood\_dist'))
    # 5 October: the backups moved into the repository's local folder
    # (tests\test-local-places.ps1 holds the rest).
    Yes 'Local is local' (Same (Ask 'Local') (Join-Path $repo 'local'))
    Yes 'and Backups is local\backups' (Same (Ask 'Backups') (Join-Path $repo 'local\backups'))

    # Ship.ps1 runs with Set-StrictMode -Version Latest and so does every
    # script it calls. Where.ps1 once read a property that was not there,
    # which throws under it, and Ship stopped at Sync-Client on "The property
    # 'ClientDist' cannot be found".
    $strictSaid = @{}
    & {
        Set-StrictMode -Version Latest
        foreach ($p in 'ClientDist', 'ServerDist', 'ServerSettings', 'ChangeForms', 'Dist', 'Payload', 'ServerZip', 'Backups', 'Releases', 'ReleasesDev', 'ShipRoot', 'ShipRootDev', 'ShipRoots', 'Engine', 'Out', 'bot') {
            try { $strictSaid[$p] = [string](& $w $p) } catch { $strictSaid[$p] = 'THREW ' + $_.Exception.Message }
        }
    }
    $threw = @($strictSaid.Values | Where-Object { $_ -like 'THREW*' })
    Yes ('under Set-StrictMode, as Ship runs it, every place still answers' +
         $(if ($threw.Count) { ': ' + ($threw -join '; ') } else { '' })) (
        @($strictSaid.Values | Where-Object { $_ -like 'THREW*' -or -not $_ }).Count -eq 0)
    Yes 'and ClientDist under it is the engine''s client build' (Same $strictSaid['ClientDist'] (Join-Path $newEngine 'build\dist\client'))

    # 2. An old folder full of what the old layout held, beside the scratch
    #    repository: nothing changes.
    New-Item -ItemType Directory -Force -Path (Join-Path $old 'skymp\build\dist\server') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $old 'dist\Thornswood\_dist') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $old '_payload') | Out-Null
    [IO.File]::WriteAllText((Join-Path $old 'skymp\CMakeLists.txt'), 'project(skymp)')
    Yes 'an old folder full of the old layout does not change the engine' (Same (Ask 'Engine') $newEngine)
    Yes 'nor the output' (Same (Ask 'Out') $newOut)
    Yes 'bot is bot, even with no bot folder' (Same (Ask 'bot') (Join-Path $repo 'bot'))
    $oldRootTaken = $true
    try { & $w 'Engine' -OldRoot $old | Out-Null } catch { $oldRootTaken = $false }
    Yes 'Where.ps1 takes no -OldRoot any more' (-not $oldRootTaken)

    # 3. A name nobody knows is refused rather than guessed at.
    $refused = $false
    try { & $w 'Engin' | Out-Null } catch { $refused = $true }
    Yes 'a place Where.ps1 does not know is refused' $refused

    # ---- layout.json and where.js carry no old place ------------------------
    $layText = [IO.File]::ReadAllText($layoutSrc)
    $lay = $layText | ConvertFrom-Json
    Yes 'layout.json names no old root and no old path' (
        $layText -notmatch '(?i)"old' -and $layText -notmatch '(?i)"tools/')
    Yes 'layout.json lists the top folders' (@($lay.folders.PSObject.Properties.Name).Count -ge 10)
    foreach ($f in @($lay.folders.PSObject.Properties)) {
        Yes ('  its folder ' + $f.Name + ' is in the repository') (Test-Path -LiteralPath (Join-Path $realRepo ([string]$f.Value)))
    }
    foreach ($src in $where, $whereJsSrc) {
        $tokens = $null; $errors = $null
        $code = [IO.File]::ReadAllText($src)
        if ($src -like '*.ps1') {
            [void][System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tokens, [ref]$errors)
            $code = (@($tokens | Where-Object { $_.Kind -ne 'Comment' }) | ForEach-Object { $_.Text }) -join ' '
        }
        else {
            $code = [regex]::Replace($code, '(?s)/\*.*?\*/|//[^\r\n]*', '')
        }
        Yes ((Split-Path -Leaf $src) + ' has no fallback to the old folder or an old path in its code') (
            $code -notmatch '(?i)Thornswood-Dev(?!Build)' -and $code -notmatch '(?i)oldRoot|oldUnder|\.old\b')
    }

    $node = Get-Command node -ErrorAction SilentlyContinue
    if ($node) {
        $wj = Join-Path $repo 'scripts\release\where.js'
        function AskJs([string]$what) { return [string](& node $wj $what).Trim() }
        foreach ($p in 'Repo', 'Engine', 'Out', 'ServerDist', 'ClientDist', 'Package', 'ServerZip', 'Local', 'Backups', 'bot', 'voice') {
            Yes ('where.js ' + $p + ' matches Where.ps1') (Same (AskJs $p) (Ask $p))
        }
    } else {
        Yes 'node is available to check where.js' $false
    }

    # ---- the scripts --------------------------------------------------------
    # A string naming C:\Thornswood-Dev: scripts\oneoff is parked history.
    $named = @()
    $keys = @('Repo', 'Engine', 'ServerDist', 'ClientDist', 'ServerSettings', 'ChangeForms', 'Out', 'Dist', 'Package', 'Payload', 'ServerZip', 'Local', 'Backups', 'Releases', 'ReleasesDev', 'ShipRoot', 'ShipRootDev', 'ShipRoots')
    $badKeys = @()
    $callers = 0
    $scriptsDir = Join-Path $realRepo 'scripts'
    foreach ($f in @(Get-ChildItem -LiteralPath $scriptsDir -File -Recurse | Where-Object { $_.Extension -in '.ps1', '.py' -and $_.FullName -notmatch '[\\/]oneoff[\\/]' })) {
        $text = [IO.File]::ReadAllText($f.FullName)
        if ($f.Extension -eq '.ps1') {
            $tokens = $null; $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
            foreach ($t in $tokens) {
                if (($t.Kind -eq 'StringLiteral' -or $t.Kind -eq 'StringExpandable') -and $t.Text -match '(?i)C:[\\/]+Thornswood-Dev(?!Build)') {
                    $named += ('{0}:{1}' -f $f.Name, $t.Extent.StartLineNumber)
                }
            }
            foreach ($m in [regex]::Matches($text, "Join-Path \`$PSScriptRoot '(?:\.\.\\release\\)?Where\.ps1'\)\s+(\w+)")) {
                $callers++
                if ($keys -notcontains $m.Groups[1].Value) { $badKeys += ('{0}: {1}' -f $f.Name, $m.Groups[1].Value) }
            }
        }
        else {
            # Python: a quoted string, not a # comment.
            $i = 0
            foreach ($line in ($text -split "`n")) {
                $i++
                $codePart = ($line -replace '#.*$', '')
                if ($codePart -match '(?i)["''][^"'']*C:\\+Thornswood-Dev(?!Build)') { $named += ('{0}:{1}' -f $f.Name, $i) }
            }
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
