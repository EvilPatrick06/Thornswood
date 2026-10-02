<#
  Get-ScratchDir.ps1

      & (Join-Path $PSScriptRoot 'Get-ScratchDir.ps1') 'Thornswood-launcher-Thornswood'

  Says where a short-lived build scratch folder goes, so Ship and
  Install-Thornswood take their launcher build (and the CI setup stub)
  from one place instead of each calling [IO.Path]::GetTempPath().

  WHY. Patrick, 28 September: every build scratch root and temp file goes
  under C:\ThornswoodTemps&Worktrees\temp\<task>, never %TEMP%. Until this
  helper, Ship.ps1 and Install-Thornswood.ps1 both staged the launcher under
  GetTempPath(), so two Ships from two worktrees for the same Root shared one
  %TEMP% folder and could pick up each other's exe (issue #1272).

  OVERRIDE. THORNSWOOD_SCRATCH_ROOT, when set, replaces the temps folder.
  tests\test-ship-dry-run.ps1 points it at its own sandbox so a dry run never
  writes beside the real temps tree. On a machine without the temps folder,
  falls back to [IO.Path]::GetTempPath() so a checkout elsewhere still runs.

  Read only for the path itself: creates nothing and prints nothing but the
  one path. Callers that write must use -LiteralPath (the & in
  ThornswoodTemps&Worktrees is real).

.PARAMETER Task
  Folder name under the scratch root, for example
  Thornswood-launcher-Thornswood or Thornswood-setup-Thornswood.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Task
)

if (-not $Task) { throw 'Get-ScratchDir.ps1 needs a Task name.' }

$base = $env:THORNSWOOD_SCRATCH_ROOT
if (-not $base) {
    $base = 'C:\ThornswoodTemps&Worktrees\temp'
    if (-not (Test-Path -LiteralPath $base)) {
        $base = [IO.Path]::GetTempPath()
    }
}

Join-Path $base $Task
