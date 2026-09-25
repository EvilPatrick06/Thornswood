<#
  Go.ps1, forwarding.

  tools\Go.ps1 moved to scripts\release\Go.ps1 on 25 September, when the scripts
  were sorted into scripts\<area> (issue #440, phase 8). This runs that one
  with the same arguments, so the command people already type keeps working
  for one release. It goes after the next main release.
#>
Write-Host 'tools\Go.ps1 is scripts\release\Go.ps1 now; running that.' -ForegroundColor DarkGray
& (Join-Path $PSScriptRoot '..\scripts\release\Go.ps1') @args
exit $LASTEXITCODE
