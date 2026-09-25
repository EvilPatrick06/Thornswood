<#
  Deploy-DevGamemode.ps1, forwarding.

  tools\Deploy-DevGamemode.ps1 moved to scripts\deploy\Deploy-DevGamemode.ps1 on 25 September, when the scripts
  were sorted into scripts\<area> (issue #440, phase 8). This runs that one
  with the same arguments, so the command people already type keeps working
  for one release. It goes after the next main release.
#>
Write-Host 'tools\Deploy-DevGamemode.ps1 is scripts\deploy\Deploy-DevGamemode.ps1 now; running that.' -ForegroundColor DarkGray
& (Join-Path $PSScriptRoot '..\scripts\deploy\Deploy-DevGamemode.ps1') @args
exit $LASTEXITCODE
