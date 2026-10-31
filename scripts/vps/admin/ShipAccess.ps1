<#
  ShipAccess.ps1

  Get-ThornswoodShipAccess: the box admin App's token for one release step
  through the deploy gate (#2841), from scripts\vps\admin\ship-access.js:
  Actions write on the engine fork and Thornswood, Contents read on
  Thornswood, ended by GitHub within the hour. Dot-sourced by the gate's
  box scripts that reach GitHub through gh: Ship-OnBox.ps1 (the Ship signs
  in the fork) and Publish-ServerOnBox.ps1 (CI's engine build of the pin
  comes from the fork's artifacts). The caller hands it to gh through
  GH_TOKEN for that run alone and removes it after.

      . scripts\vps\admin\ShipAccess.ps1
      $token = Get-ThornswoodShipAccess -Repo $repo -AdminState 'C:\Thornswood-Admin\state'

  It returns the token, or throws with what ship-access.js said; nothing of
  the App's key is ever in what it returns or throws.
#>
function Get-ThornswoodShipAccess {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [string]$AdminState = 'C:\Thornswood-Admin\state'
    )
    $node = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $node) { throw 'there is no node on this machine to mint the App''s token with.' }
    $had = $env:THORNSWOOD_ADMIN_STATE
    $env:THORNSWOOD_ADMIN_STATE = $AdminState
    $was = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $minted = @(& $node.Source (Join-Path $Repo 'scripts\vps\admin\ship-access.js') 2>&1 | ForEach-Object { "$_" }) }
    finally {
        $ErrorActionPreference = $was
        if ($null -eq $had) { Remove-Item -LiteralPath Env:\THORNSWOOD_ADMIN_STATE -ErrorAction SilentlyContinue } else { $env:THORNSWOOD_ADMIN_STATE = $had }
    }
    $token = @($minted | Where-Object { $_ -match '^gh[sp]_[A-Za-z0-9_]{20,}$' }) | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $token) { throw ((@($minted | Where-Object { $_ -notmatch '^gh[sp]_' })) -join ' ') }
    return $token
}
