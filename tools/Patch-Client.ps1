<#
  Patch-Client.ps1

  Points skymp5-client.js at the login this server actually answers.

  The client bundle is Keizaal's build. In offline mode, which is what the
  launcher puts it in every launch by writing gameData.profileId, its
  AuthService answers connectionAccepted by sending a charSelectQuery packet
  and then waits for a character select screen to come back. Thornswood's
  server has no handler for that packet. Its Login system opens with

      if (r !== "loginWithSkympIo") return;

  so the query is dropped on arrival, nothing is ever sent back, and the game
  sits on the main menu until the connection times out. That was the whole of
  "it does not walk into the creation hall" on 2026-09-16: the server log
  showed connect, sixty seconds of silence, disconnect.

  The same bundle already carries sendOfflineLogin(), which sends
  loginWithSkympIo with gameData.profileId, the exact shape the server's
  offlineMode branch reads. It only ever ran after a slot was picked on a
  screen this server never shows. This makes the offline path call it at once.

  Nothing is lost. The launcher chooses the character before the game starts,
  so the in-game select was dead weight here anyway.

  Idempotent: it says "already patched" and exits 0 when there is nothing to
  do. It exits 1 and says so when the bundle has changed shape and the block
  it expects is not there, because an unpatched client connects and then sits
  on the menu for everybody, and that has to stop a release, not slip through
  one. Ship.ps1 calls this before publishing and stops on a non zero exit.

      .\Patch-Client.ps1            apply if needed
      .\Patch-Client.ps1 -Check     report only, change nothing
#>
[CmdletBinding()]
param(
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition',
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

# Skyrim is wherever Steam put it. The default above is the usual place; when
# it is not there and -Game was not given, the registry and every Steam
# library are tried, the same lookup Publish-Update and the launcher use, so
# a machine with Steam on another drive patches the right copy.
if (-not $PSBoundParameters.ContainsKey('Game') -and -not (Test-Path -LiteralPath (Join-Path $Game 'SkyrimSE.exe'))) {
    $roots = @()
    foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\Wow6432Node\Valve\Steam')) {
        try { $sp = (Get-ItemProperty -Path $k -EA Stop).SteamPath; if ($sp) { $roots += ($sp -replace '/', '\') } } catch { }
    }
    foreach ($r in @($roots)) {
        $vdf = Join-Path $r 'config\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf) {
                if ($line -match '^\s*"path"\s+"(.+)"\s*$') { $roots += ($Matches[1] -replace '\\\\', '\') }
            }
        }
    }
    foreach ($r in $roots) {
        $g = Join-Path $r 'steamapps\common\Skyrim Special Edition'
        if (Test-Path -LiteralPath (Join-Path $g 'SkyrimSE.exe')) { $Game = $g; break }
    }
}

$file = Join-Path $Game 'Data\Platform\Plugins\skymp5-client.js'
if (-not (Test-Path -LiteralPath $file)) {
    Write-Host "Patch-Client: not found: $file" -ForegroundColor Red
    exit 1
}

$raw = [IO.File]::ReadAllText($file)
$nl = "`n"
if ($raw.Contains("`r`n")) { $nl = "`r`n" }

$marker = 'Thornswood: the launcher picks the character before the'
if ($raw.Contains($marker)) {
    Write-Host 'Patch-Client: already patched, nothing to do' -ForegroundColor DarkGray
    exit 0
}

$oldLines = @(
    '                        var message = {',
    '                            t: _messages__WEBPACK_IMPORTED_MODULE_9__.MsgType.CustomPacket,',
    '                            contentJsonDump: JSON.stringify({',
    '                                customPacketType: "charSelectQuery",',
    '                                profileId: authData.local.profileId,',
    '                                sessionToken',
    '                            })',
    '                        };',
    '                        this.controller.emitter.emit("sendMessage", {',
    '                            message,',
    '                            reliability: "reliable"',
    '                        });'
)
$newLines = @(
    '                        // Thornswood: the launcher picks the character before the',
    '                        // game is started, so the in-game character select screen',
    '                        // is dead weight here. More to the point, this server has',
    '                        // no charSelectQuery handler at all: its Login system',
    '                        // opens with `if (r !== "loginWithSkympIo") return`, so the',
    '                        // query was being dropped on arrival and the connection sat',
    '                        // idle until it timed out. sendOfflineLogin sends the packet',
    '                        // the server does accept, with gameData.profileId, which is',
    '                        // what its offlineMode branch reads.',
    '                        void sessionToken;',
    '                        this.sendOfflineLogin();'
)
$old = ($oldLines -join $nl) + $nl
$new = ($newLines -join $nl) + $nl

$idx = $raw.IndexOf($old, [StringComparison]::Ordinal)
if ($idx -lt 0) {
    Write-Host 'Patch-Client: the charSelectQuery block is not where this expects it.' -ForegroundColor Red
    Write-Host '  The client bundle has changed shape. Do not ship it until somebody looks:' -ForegroundColor Red
    Write-Host '  an unpatched client connects and then sits on the main menu.' -ForegroundColor Red
    exit 1
}
if ($raw.LastIndexOf($old, [StringComparison]::Ordinal) -ne $idx) {
    Write-Host 'Patch-Client: that block appears more than once, refusing to guess.' -ForegroundColor Red
    exit 1
}
if ($Check) {
    Write-Host 'Patch-Client: NOT patched. Run without -Check to apply.' -ForegroundColor Yellow
    exit 1
}

$out = $raw.Substring(0, $idx) + $new + $raw.Substring($idx + $old.Length)
# WriteAllText with an explicit encoding: Set-Content -Encoding UTF8 adds a
# byte order mark under Windows PowerShell 5.1, and SkyrimPlatform stops on it.
[IO.File]::WriteAllText($file, $out, (New-Object Text.UTF8Encoding($false)))
Write-Host ("Patch-Client: patched, {0:n0} chars -> {1:n0} chars" -f $raw.Length, $out.Length) -ForegroundColor Green
exit 0
