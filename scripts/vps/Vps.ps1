<#
  Vps.ps1

  Shared defaults for the VPS address, user, and ports. Dot-source it:

      . (Join-Path $PSScriptRoot '..\vps\Vps.ps1')

  Then, after the param block:

      if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }

  An explicit -Vps on the command line still wins, because the param keeps
  whatever was passed; only an empty default is filled from vps.json.
#>

function Get-ThornswoodVps {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $path = Join-Path $here 'vps.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "VPS defaults not found: $path"
    }
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $j = $raw | ConvertFrom-Json
    if (-not $j.address) { throw "vps.json has no address: $path" }
    return $j
}

function Get-ThornswoodVpsAddress {
    return [string](Get-ThornswoodVps).address
}

function Get-ThornswoodVpsUser {
    $u = [string](Get-ThornswoodVps).user
    if (-not $u) { $u = 'Administrator' }
    return $u
}
