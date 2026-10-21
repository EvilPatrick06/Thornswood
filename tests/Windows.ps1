<#
  Windows.ps1
  Dot-sourced by every harness that runs something only Windows has: Windows
  PowerShell 5.1, cmd.exe, a scheduled task, a folder's ACL, the .NET
  Framework.

      . (Join-Path $PSScriptRoot 'Windows.ps1')

  It sets one variable and two functions, and nothing else:

    $OnWindows             $true on Windows, under pwsh or under Windows
                           PowerShell 5.1, and $false anywhere else.
    Get-WindowsPath <rel>  <rel> under the Windows folder, as in
                           Get-WindowsPath 'System32\cmd.exe'. Off Windows it
                           throws, because there is no Windows folder to name.
    Get-WindowsPowerShell  Windows PowerShell 5.1's powershell.exe, the one the
                           box runs its scripts in. It throws when that file is
                           not where Windows keeps it, and it throws off Windows.

  A harness asks $OnWindows first, and only then asks for a path:

      if (-not $OnWindows) {
          Write-Host 'SKIP  the runs: they need Windows PowerShell 5.1, which only Windows has'
          Done
      }
      $ps51 = Get-WindowsPowerShell

  A harness that is about Windows from end to end (a folder's ACL, a task, a
  script only the box runs) says so at its top and ends there, with no count,
  because it checked nothing:

      if (-not $OnWindows) { Write-Host 'NOT RUN  <what it proves> happens only on Windows'; exit 0 }

  WHY ONE PLACE (#2957, 21 Oct). Every harness found Windows PowerShell by
  itself: by joining a path onto $env:SystemRoot or $env:WINDIR, or by asking
  Get-Command for powershell.exe. Off Windows those variables are unset, so the
  join threw "Cannot bind argument to parameter 'Path' because it is null"
  before any guard after it ran, and harness after harness stopped on its first
  lines under pwsh on Linux; the line was copied from one harness to the next,
  so each new one did the same. On Windows, Get-Command found nothing when
  powershell.exe was missing, and the harness said SKIP, or ran pwsh in its
  place, and passed without running what it was for. Here, off Windows is said
  plainly, and on Windows a powershell.exe that is not where Windows keeps it
  is a failure, never a skip. tests\test-2957-windows-one-way.ps1 fails on a
  harness that finds Windows any other way.
#>
$OnWindows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
function Get-WindowsPath([string]$Relative) {
    if (-not $OnWindows) { throw ('Get-WindowsPath ' + $Relative + ': this is not Windows. Ask $OnWindows first, and say what does not run.') }
    # The Windows folder from .NET, not from the environment, which a child
    # can be started without.
    Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) $Relative
}
function Get-WindowsPowerShell {
    $p = Get-WindowsPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $p)) { throw ('Windows PowerShell 5.1 is not at ' + $p + ', where Windows keeps it, so nothing that needs it can be checked here.') }
    $p
}
