<#
  Bump-Version.ps1, forwarding.

  tools\Bump-Version.ps1 moved to scripts\release\Bump-Version.ps1 on 25 September, when the scripts
  were sorted into scripts\<area> (issue #440, phase 8). This runs that one
  with the same arguments, so the command people already type keeps working
  for one release. It goes after the next main release.
#>
Write-Host 'tools\Bump-Version.ps1 is scripts\release\Bump-Version.ps1 now; running that.' -ForegroundColor DarkGray
& (Join-Path $PSScriptRoot '..\scripts\release\Bump-Version.ps1') @args
exit $LASTEXITCODE
