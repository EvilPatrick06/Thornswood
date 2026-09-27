<#
  Vps.ps1, forwarding.

  tools\Vps.ps1 lives at scripts\vps\Vps.ps1 since the scripts were sorted into
  scripts\<area> (issue #440, phase 8). This dotsources that one, so a script
  that still says tools\Vps.ps1 keeps working for one release.
#>
. (Join-Path $PSScriptRoot '..\scripts\vps\Vps.ps1')
