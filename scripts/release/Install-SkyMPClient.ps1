<#
  Install-SkyMPClient.ps1

  Lays the SkyMP client from the client build into the game folder and points it at the server.

  Order matters here. The server's load order has to be regenerated after
  anything that changes the plugins, never before. The script says so at the
  end rather than assuming you remember.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Dist    = (& (Join-Path $PSScriptRoot 'Where.ps1') ClientDist),
    [string]$Data    = 'C:\Thornswood\Game\Data',
    [string]$ServerIp = '127.0.0.1',
    [int]   $ServerPort = 7777
)


# Resolved from where this script is rather than from a fixed path under
# Downloads. The repo folder gets renamed and moved, and a default that names it
# turns every one of these into a broken command the first time it does.
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$Game = Split-Path $Data -Parent

# ---- 1. lay down the SkyMP client ------------------------------------------
if (-not (Test-Path -LiteralPath "$Dist\Data")) { throw "client dist not found: $Dist\Data" }
if ($PSCmdlet.ShouldProcess('SkyMP client', "copy into $Data")) {
    Copy-Item -Path "$Dist\Data\*" -Destination $Data -Recurse -Force
    $mb = [math]::Round((Get-ChildItem -LiteralPath "$Dist\Data" -Recurse -File |
                         Measure-Object Length -Sum).Sum / 1MB)
    Write-Host ("SkyMP client: {0} MB copied into {1}" -f $mb, $Data) -ForegroundColor Cyan
}

# ---- 2. point the client at the server -------------------------------------
$cs = Join-Path $Data 'Platform\Plugins\skymp5-client-settings.txt'
if (Test-Path -LiteralPath $cs) {
    $j = Get-Content -LiteralPath $cs -Raw | ConvertFrom-Json
    $j | Add-Member -NotePropertyName 'server-ip'   -NotePropertyValue $ServerIp   -Force
    $j | Add-Member -NotePropertyName 'server-port' -NotePropertyValue $ServerPort -Force
    if ($PSCmdlet.ShouldProcess('skymp5-client-settings.txt', "point at ${ServerIp}:${ServerPort}")) {
        [IO.File]::WriteAllText($cs, ($j | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
        Write-Host ("client -> {0}:{1}" -f $ServerIp, $ServerPort) -ForegroundColor Cyan
    }
}

Write-Host ''
Write-Host 'Load order just changed, so the server list is stale. Regenerate it:' -ForegroundColor Yellow
Write-Host ('  & "' + (Join-Path $Here '..\deploy\Deploy-Gamemode.ps1') + '"') -ForegroundColor Yellow
