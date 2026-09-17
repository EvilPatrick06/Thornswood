<#
  Patch-Client.ps1

  Every change Thornswood makes to skymp5-client.js, in one place.

  The client bundle is not built here. It is another server's build (Keizaal's
  until 16 Sep, Daedric Online's since, whichever launcher last wrote the file)
  and it gets replaced whenever one of those launchers runs on the machine that
  ships. On 14 Sep the fixes for locks and activators were made by hand in the
  bundle; on 16 Sep at 14:58 a fresh build landed, Keep took it as ours, the
  15:23 pack carried it to everyone, and the hand edits were gone with nobody
  noticing until doors were unlocked again on the 17th. So nothing is edited by
  hand any more. Each change is a block below with the exact text it expects
  and the text it puts there, and Ship.ps1 runs this before every publish. A
  bundle that no longer has the expected text stops the release, because a
  bundle shipped without these is the bundle everybody ran on the 17th.

  The changes:

  1. Offline login. In offline mode the bundle's AuthService answers
     connectionAccepted with a charSelectQuery packet and waits for a character
     select screen. Thornswood's server has no handler for that packet, so the
     connection sat idle until it timed out. The bundle already carries
     sendOfflineLogin(), the exact shape the server's offlineMode branch reads;
     this makes the offline path call it at once. The launcher picks the
     character before the game starts, so the in-game select was dead weight.

  2. Locks, activators and furniture. Upstream's dealWithRef unlocks every
     reference the server tracks and blocks activation on containers, doors,
     items, actors, activators and furniture. Locked plus blocked is unopenable
     by any means, which is why it unlocked everything: every lock in the world
     was simply gone. Now a locked reference keeps Skyrim's own handling until
     it is open, and activators and furniture are never blocked: levers,
     chains, bars, chairs and shrines are Skyrim's to run, the server has no
     scripts for them (gamemode.js hands out the shrine and nirnroot results
     itself, on the message the client sends either way).

  Idempotent: a block whose marker is already in the file is skipped, and it
  says "already patched" and exits 0 when there is nothing left to do. It
  exits 1 when a block's expected text is not there exactly once.

      .\Patch-Client.ps1            apply whatever is missing
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

# Each block: the marker that says it is in, the lines it expects, the lines
# it writes. Lines, joined with the file's own line ending at run time, so
# the same block matches a bundle saved either way.
$blocks = @(
    @{
        Name   = 'offline login'
        Marker = 'Thornswood: the launcher picks the character before the'
        Old    = @(
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
        New    = @(
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
    },
    @{
        Name   = 'locks, activators and furniture'
        Marker = 'Thornswood: a locked door or chest keeps Skyrim''s own handling'
        Old    = @(
            '                    if (t === 40 || t === 24 || t === 28 || isItem || t === 43 || t === 29 && ((_a = self.getBaseObject()) === null || _a === void 0 ? void 0 : _a.getFormID()) !== caveGSecretDoor01) {',
            '                        self.blockActivation(true);',
            '                    } else {',
            '                        self.blockActivation(false);',
            '                    }',
            '                    if (self.isLocked()) {',
            '                        self.lock(false, false);',
            '                    }'
        )
        New    = @(
            '                    // Thornswood: a locked door or chest keeps Skyrim''s own handling',
            '                    // until it is open. Upstream unlocked every tracked reference and',
            '                    // blocked activation on it, and locked plus blocked is unopenable',
            '                    // by any means, so every lock in the world was simply gone.',
            '                    // Activators (24) and furniture (40) are not blocked either:',
            '                    // levers, chains, bars, chairs and shrines are Skyrim''s to run,',
            '                    // the server has no scripts for them. Containers, doors, items',
            '                    // and actors still go through the server as before.',
            '                    if (self.isLocked()) {',
            '                        self.blockActivation(false);',
            '                    } else if (t === 28 || isItem || t === 43 || t === 29 && ((_a = self.getBaseObject()) === null || _a === void 0 ? void 0 : _a.getFormID()) !== caveGSecretDoor01) {',
            '                        self.blockActivation(true);',
            '                    } else {',
            '                        self.blockActivation(false);',
            '                    }'
        )
    }
)

$out = $raw
$applied = @()
$already = @()
foreach ($b in $blocks) {
    if ($out.Contains($b.Marker)) { $already += $b.Name; continue }
    $old = ($b.Old -join $nl) + $nl
    $new = ($b.New -join $nl) + $nl
    $idx = $out.IndexOf($old, [StringComparison]::Ordinal)
    if ($idx -lt 0) {
        Write-Host ("Patch-Client: the {0} block is not where this expects it." -f $b.Name) -ForegroundColor Red
        Write-Host '  The client bundle has changed shape. Do not ship it until somebody looks:' -ForegroundColor Red
        Write-Host '  a bundle without these changes is the one everybody ran on 17 Sep.' -ForegroundColor Red
        exit 1
    }
    if ($out.LastIndexOf($old, [StringComparison]::Ordinal) -ne $idx) {
        Write-Host ("Patch-Client: the {0} block appears more than once, refusing to guess." -f $b.Name) -ForegroundColor Red
        exit 1
    }
    $out = $out.Substring(0, $idx) + $new + $out.Substring($idx + $old.Length)
    $applied += $b.Name
}

if ($applied.Count -eq 0) {
    Write-Host ("Patch-Client: already patched ({0}), nothing to do" -f ($already -join '; ')) -ForegroundColor DarkGray
    exit 0
}
if ($Check) {
    Write-Host ("Patch-Client: NOT patched: {0}. Run without -Check to apply." -f ($applied -join '; ')) -ForegroundColor Yellow
    exit 1
}
# WriteAllText with an explicit encoding: Set-Content -Encoding UTF8 adds a
# byte order mark under Windows PowerShell 5.1, and SkyrimPlatform stops on it.
[IO.File]::WriteAllText($file, $out, (New-Object Text.UTF8Encoding($false)))
Write-Host ("Patch-Client: patched {0}, {1:n0} chars -> {2:n0} chars" -f ($applied -join '; '), $raw.Length, $out.Length) -ForegroundColor Green
exit 0
