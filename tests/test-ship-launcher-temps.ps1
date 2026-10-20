<#
  test-ship-launcher-temps.ps1

  Ship and Install-Thornswood stage the launcher under the temps folder, not
  %TEMP%. Issue #1272.

  Patrick, 28 September: every build scratch root goes under the temps
  folder, never [IO.Path]::GetTempPath(). Since #2900 (20 Oct) that is the
  repository's own temp\<task>, the main checkout's from a worktree; until
  then it was C:\ThornswoodTemps&Worktrees\temp\<task> on One.
  Until #1272 both scripts joined GetTempPath() for Thornswood-launcher-*,
  and Ship also did for Thornswood-setup-*, so a Ship could write under the
  system temp folder and two Ships for the same Root could share one folder.

  HOW. Reads the real Ship.ps1, Install-Thornswood.ps1 and Get-ScratchDir.ps1.
  Asserts the two call sites no longer name GetTempPath for those folders,
  that both call Get-ScratchDir.ps1, and that Get-ScratchDir itself prefers
  the temps folder (or THORNSWOOD_SCRATCH_ROOT) and never returns a path under
  the system temp when the temps folder (or the override) is in use.

  Then drives Get-ScratchDir with a sandboxed THORNSWOOD_SCRATCH_ROOT and
  proves a Ship -DryRun build step's launcher OutDir would land there, not
  under GetTempPath(). No real Ship runs: the dry-run harness already covers
  a full Ship with stand-ins; this only holds the scratch path.

  Read only apart from files under its own scratch folder, which it removes.
#>
[CmdletBinding()]
param(
    [string]$ShipPath,
    [string]$InstallPath,
    [string]$ScratchHelper
)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $ShipPath) { $ShipPath = Join-Path $Repo 'scripts\release\Ship.ps1' }
if (-not $InstallPath) { $InstallPath = Join-Path $Repo 'scripts\dev\Install-Thornswood.ps1' }
if (-not $ScratchHelper) { $ScratchHelper = Join-Path $Repo 'scripts\release\Get-ScratchDir.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

Yes 'Ship.ps1 is present' (Test-Path -LiteralPath $ShipPath)
Yes 'Install-Thornswood.ps1 is present' (Test-Path -LiteralPath $InstallPath)
Yes 'Get-ScratchDir.ps1 is present' (Test-Path -LiteralPath $ScratchHelper)
if (-not ((Test-Path -LiteralPath $ShipPath) -and (Test-Path -LiteralPath $InstallPath) -and (Test-Path -LiteralPath $ScratchHelper))) { Done }

$ship = [IO.File]::ReadAllText($ShipPath)
$inst = [IO.File]::ReadAllText($InstallPath)
$help = [IO.File]::ReadAllText($ScratchHelper)

Yes 'Ship.ps1 parses' ([bool]([System.Management.Automation.Language.Parser]::ParseInput($ship, [ref]$null, [ref]$null)))
Yes 'Install-Thornswood.ps1 parses' ([bool]([System.Management.Automation.Language.Parser]::ParseInput($inst, [ref]$null, [ref]$null)))
Yes 'Get-ScratchDir.ps1 parses' ([bool]([System.Management.Automation.Language.Parser]::ParseInput($help, [ref]$null, [ref]$null)))

# The launcher build / setup stub lines must not call GetTempPath any more.
Yes 'Ship.ps1 launcher buildOut does not use GetTempPath' ($ship -notmatch '\$buildOut\s*=\s*Join-Path\s*\(\[IO\.Path\]::GetTempPath\(\)\)')
Yes 'Ship.ps1 setup stubDir does not use GetTempPath' ($ship -notmatch '\$stubDir\s*=\s*Join-Path\s*\(\[IO\.Path\]::GetTempPath\(\)\)')
Yes 'Install-Thornswood.ps1 launcherBuild does not use GetTempPath' ($inst -notmatch '\$launcherBuild\s*=\s*Join-Path\s*\(\[IO\.Path\]::GetTempPath\(\)\)')

Yes 'Ship.ps1 buildOut calls Get-ScratchDir.ps1' ($ship -match '\$buildOut\s*=\s*&\s*\(Join-Path \$Here ''Get-ScratchDir\.ps1''\)')
Yes 'Ship.ps1 stubDir calls Get-ScratchDir.ps1' ($ship -match '\$stubDir\s*=\s*&\s*\(Join-Path \$Here ''Get-ScratchDir\.ps1''\)')
Yes 'Install-Thornswood.ps1 launcherBuild calls Get-ScratchDir.ps1' ($inst -match '\$launcherBuild\s*=\s*&\s*\(Join-Path \$Here ''\.\.\\release\\Get-ScratchDir\.ps1''\)')

Yes 'Get-ScratchDir takes the temps folder from the main checkout' ($help -match 'commondir')
Yes 'Get-ScratchDir honours THORNSWOOD_SCRATCH_ROOT' ($help -match 'THORNSWOOD_SCRATCH_ROOT')
Yes 'Get-ScratchDir falls back to GetTempPath only outside a checkout' ($help -match 'GetTempPath\(\)')

# ---- drive the helper under a sandbox -----------------------------------------
$sysTemp = [IO.Path]::GetTempPath().TrimEnd('\', '/')
$oldScratch = $env:THORNSWOOD_SCRATCH_ROOT
$box = Join-Path $sysTemp ('ts-launcher-temps-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $box | Out-Null
try {
    $env:THORNSWOOD_SCRATCH_ROOT = Join-Path $box 'scratch'
    New-Item -ItemType Directory -Force -Path $env:THORNSWOOD_SCRATCH_ROOT | Out-Null

    $task = 'Thornswood-launcher-Thornswood'
    $got = & $ScratchHelper $task
    Yes ("Get-ScratchDir with override returns under the sandbox ($got)") (
        $got.StartsWith($env:THORNSWOOD_SCRATCH_ROOT, [StringComparison]::OrdinalIgnoreCase)
    )
    Yes 'Get-ScratchDir with override is not under the system temp root alone' (
        -not ($got.StartsWith($sysTemp, [StringComparison]::OrdinalIgnoreCase) -and
              -not $got.StartsWith($env:THORNSWOOD_SCRATCH_ROOT, [StringComparison]::OrdinalIgnoreCase))
    )
    Yes 'Get-ScratchDir joins the task name' ($got.EndsWith($task, [StringComparison]::OrdinalIgnoreCase))

    # Without override, in a checkout the answer is the main checkout's temp
    # folder, which git itself names here as a check on how the helper reads
    # git's files, and not under GetTempPath().
    Remove-Item Env:THORNSWOOD_SCRATCH_ROOT -ErrorAction SilentlyContinue
    $helperDir = Split-Path -Parent $ScratchHelper
    $common = [string](git -C $helperDir rev-parse --git-common-dir)
    if ($LASTEXITCODE -eq 0 -and $common) {
        $common = [IO.Path]::GetFullPath([IO.Path]::Combine($helperDir, $common.Trim()))
        $tempsRoot = Join-Path (Split-Path -Parent $common) 'temp'
        $live = & $ScratchHelper $task
        Yes ("Get-ScratchDir default is under the temps folder ($live)") (
            $live.StartsWith($tempsRoot, [StringComparison]::OrdinalIgnoreCase)
        )
        $sysFull = [IO.Path]::GetFullPath($sysTemp)
        $liveFull = [IO.Path]::GetFullPath($live)
        Yes 'Get-ScratchDir default is not under GetTempPath()' (
            -not $liveFull.StartsWith($sysFull, [StringComparison]::OrdinalIgnoreCase)
        )
    } else {
        Yes 'git names the main checkout of this harness''s own checkout' $false
    }

    # What a Ship -DryRun build step would pass as OutDir: same formula Ship uses.
    $env:THORNSWOOD_SCRATCH_ROOT = Join-Path $box 'scratch'
    $rootLeaf = 'Play'
    $buildOut = & $ScratchHelper ('Thornswood-launcher-' + $rootLeaf)
    $sysFull = [IO.Path]::GetFullPath($sysTemp)
    $buildFull = [IO.Path]::GetFullPath($buildOut)
    $scratchFull = [IO.Path]::GetFullPath($env:THORNSWOOD_SCRATCH_ROOT)
    Yes 'Ship-style launcher OutDir stays out of GetTempPath() or is under the scratch override' (
        (-not $buildFull.StartsWith($sysFull, [StringComparison]::OrdinalIgnoreCase)) -or
        $buildFull.StartsWith($scratchFull, [StringComparison]::OrdinalIgnoreCase)
    )
    Yes 'Ship-style launcher OutDir is under THORNSWOOD_SCRATCH_ROOT' (
        [IO.Path]::GetFullPath($buildOut).StartsWith([IO.Path]::GetFullPath($env:THORNSWOOD_SCRATCH_ROOT), [StringComparison]::OrdinalIgnoreCase)
    )
}
finally {
    if ($null -eq $oldScratch) { Remove-Item Env:THORNSWOOD_SCRATCH_ROOT -ErrorAction SilentlyContinue }
    else { $env:THORNSWOOD_SCRATCH_ROOT = $oldScratch }
    Remove-Item -LiteralPath $box -Recurse -Force -ErrorAction SilentlyContinue
}

Done