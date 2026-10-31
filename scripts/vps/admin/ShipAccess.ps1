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
    try {
        $global:LASTEXITCODE = 0
        $minted = @(& $node.Source ([IO.Path]::Combine($Repo, 'scripts', 'vps', 'admin', 'ship-access.js')) 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $was
        if ($null -eq $had) { Remove-Item -LiteralPath Env:\THORNSWOOD_ADMIN_STATE -ErrorAction SilentlyContinue } else { $env:THORNSWOOD_ADMIN_STATE = $had }
    }
    # ship-access.js prints the token alone on its standard output and
    # everything else on its standard error, so the two are told apart by the
    # stream, never by the token's shape, which is GitHub's to change.
    $said = @($minted | Where-Object { $_ -is [Management.Automation.ErrorRecord] } | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    $out = @($minted | Where-Object { $_ -isnot [Management.Automation.ErrorRecord] } | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if ($code -ne 0) { throw ('ship-access.js ended ' + $code + $(if ($said.Count) { ': ' + ($said -join ' ') } else { ' and said nothing' })) }
    if ($out.Count -ne 1 -or $out[0] -match '\s') { throw ('ship-access.js ended 0 but printed ' + $out.Count + ' line(s) where one token belongs' + $(if ($said.Count) { '; it said: ' + ($said -join ' ') } else { '' })) }
    return $out[0]
}
