<#
  Ship.ps1, forwarding.

  tools\Ship.ps1 moved to scripts\release\Ship.ps1 on 25 September, when the scripts
  were sorted into scripts\<area> (issue #440, phase 8). This runs that one
  with the same arguments, so the command people already type keeps working
  for one release. It goes after the next main release.
#>
Write-Host 'tools\Ship.ps1 is scripts\release\Ship.ps1 now; running that.' -ForegroundColor DarkGray
& (Join-Path $PSScriptRoot '..\scripts\release\Ship.ps1') @args
exit $LASTEXITCODE
