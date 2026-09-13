<#
  Install-SkyMPClient.ps1

  Switches the game folder from Skyrim Together Reborn to SkyMP.

  The two cannot coexist. They hook the same engine points, ship competing SKSE
  plugins, and Skyrim Together's own .esp takes a normal load order slot that
  SkyMP's index arithmetic would then be wrong about.

  Order matters here. Removing SkyrimTogether.esp shifts every plugin after it
  up by one, so the server's load order has to be regenerated AFTER this runs,
  never before. The script says so at the end rather than assuming you remember.

  Nothing is deleted. The Skyrim Together files move to Data\_removedST with
  their paths intact, so putting it back is a move in the other direction.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Dist    = 'C:\Thornswood-Dev\skymp\build\dist\client',
    [string]$Data    = 'C:\Thornswood\Game\Data',
    [string]$Profile = 'C:\Thornswood\Profile',
    [string]$ServerIp = '127.0.0.1',
    [int]   $ServerPort = 7777
)


# Resolved from where this script is rather than from a fixed path under
# Downloads. The repo folder gets renamed and moved, and a default that names it
# turns every one of these into a broken command the first time it does.
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$Game = Split-Path $Data -Parent

$quarantine = Join-Path $Data '_removedST'

# ---- 1. the Skyrim Together stack -----------------------------------------
$stFiles = @(
    'SkyrimTogether.esp'
    'TradeTogetherMCM.esp'
    'SkyrimTogetherReborn'
    'SkyrimTogetherRebornBehaviors'
    'SKSE\Plugins\SkyrimTogetherTweaks.dll'
    'SKSE\Plugins\SkyrimTogetherTweaks.ini'
    'SKSE\Plugins\SkyrimTogetherTweaks_preload.txt'
    'SKSE\Plugins\TradeTogether.dll'
    'SKSE\Plugins\TradeTogether.ini'
    'SKSE\Plugins\MorphSyncTogether.dll'
    'SKSE\Plugins\MorphSyncTogether.ini'
    'SKSE\Plugins\MorphSyncTogether'
    'SKSE\Plugins\STRPluginMessagingAPI.dll'
    'SKSE\Plugins\STRPluginMessagingAPI.ini'
    'SKSE\Plugins\STRPluginMessagingBridge.dll'
)

$moved = 0
foreach ($f in $stFiles) {
    $src = Join-Path $Data $f
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $dst = Join-Path $quarantine $f
    $dir = Split-Path $dst -Parent
    if ($PSCmdlet.ShouldProcess($f, 'move to _removedST')) {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Move-Item -LiteralPath $src -Destination $dst -Force
        $moved++
        Write-Host "  moved  $f" -ForegroundColor DarkGray
    }
}
Write-Host ("Skyrim Together: {0} item(s) -> {1}" -f $moved, $quarantine) -ForegroundColor Cyan

# ---- 2. drop its plugins from all four load order files --------------------
$gone = 'SkyrimTogether.esp','TradeTogetherMCM.esp'
$targets = @(
    "$Profile\Default\plugins.txt"
    "$Profile\Default\loadorder.txt"
    "$Profile\LocalAppData\Plugins.txt"
    "$Profile\LocalAppData\loadorder.txt"
)
foreach ($t in $targets) {
    if (-not (Test-Path -LiteralPath $t)) { continue }
    $lines = @(Get-Content -LiteralPath $t | Where-Object {
        $gone -notcontains $_.TrimStart('*').Trim()
    })
    if ($PSCmdlet.ShouldProcess((Split-Path $t -Leaf), 'drop Skyrim Together plugins')) {
        # WriteAllLines, not Set-Content -Encoding UTF8: that adds a byte order mark
        # under Windows PowerShell 5.1 and not under 7, so the same line produces a
        # different file depending on who runs it. The game and SkyrimPlatform both
        # stop on a BOM, and the .cmd wrappers use 5.1.
        [IO.File]::WriteAllLines($t, $lines, (New-Object Text.UTF8Encoding($false)))
        $n = ($lines | Where-Object { $_ -match '^\*' }).Count
        Write-Host ("  {0,-16} {1} enabled" -f (Split-Path $t -Leaf), $n) -ForegroundColor DarkGray
    }
}

# ---- 3. lay down the SkyMP client ------------------------------------------
if (-not (Test-Path -LiteralPath "$Dist\Data")) { throw "client dist not found: $Dist\Data" }
if ($PSCmdlet.ShouldProcess('SkyMP client', "copy into $Data")) {
    Copy-Item -Path "$Dist\Data\*" -Destination $Data -Recurse -Force
    $mb = [math]::Round((Get-ChildItem -LiteralPath "$Dist\Data" -Recurse -File |
                         Measure-Object Length -Sum).Sum / 1MB)
    Write-Host ("SkyMP client: {0} MB copied into {1}" -f $mb, $Data) -ForegroundColor Cyan
}

# ---- 4. point the client at the server -------------------------------------
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
Write-Host ('  & "' + (Join-Path $Here 'Deploy-Gamemode.ps1') + '"') -ForegroundColor Yellow
