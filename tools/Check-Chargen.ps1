<#
  Check-Chargen.ps1

  Preflight for character creation. Everything it looks at is something that
  silently produces a broken first join rather than an error message, so it is
  worth thirty seconds before starting the server.

  It checks, in order:
    - the server's load order holds both plugins the flow needs
    - the plugin on disk really carries the fourteen new book records
    - the fifteen Keizaal manuals have a name and a mesh, which they did not
      when Keizaal shipped them
    - gamemode.js is the build that knows about all of it
    - the start point in server-settings.json is the creation room, computed
      from this load order rather than written down

  Read only. It changes nothing.
#>
param(
    [string]$Dist = 'C:\Thornswood-Dev\skymp\build\dist\server',
    [string]$Data = 'C:\Thornswood\Game\Data'
)

$fail = 0
function Ok  ($m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Bad ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Note($m) { Write-Host "        $m" -ForegroundColor DarkGray }

$settingsPath = Join-Path $Dist 'server-settings.json'
if (-not (Test-Path -LiteralPath $settingsPath)) { throw "not found: $settingsPath" }
$s = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$order = @($s.loadOrder | ForEach-Object { [IO.Path]::GetFileName($_) })

Write-Host ''
Write-Host 'load order' -ForegroundColor Cyan
$idxContent = [Array]::FindIndex($order, [Predicate[string]]{ param($x) $x -ieq 'Thornswood-Content.esp' })
$idxUnbound = [Array]::FindIndex($order, [Predicate[string]]{ param($x) $x -ieq 'Skyrim Unbound.esp' })

if ($idxContent -lt 0) { Bad 'Thornswood-Content.esp is not in the server load order' }
else { Ok ("Thornswood-Content.esp at index {0} (0x{0:X2})" -f $idxContent) }

if ($idxUnbound -lt 0) {
    Bad 'Skyrim Unbound.esp is not in the server load order, so there is no creation room'
    Note 'creation still runs, wherever the start point happens to be'
} else {
    Ok ("Skyrim Unbound.esp at index {0} (0x{0:X2})" -f $idxUnbound)
}

Write-Host ''
Write-Host 'plugin records' -ForegroundColor Cyan
$esp = Join-Path $Data 'Thornswood-Content.esp'
if (-not (Test-Path -LiteralPath $esp)) {
    Bad "not found: $esp"
} else {
    $bytes = [IO.File]::ReadAllBytes($esp)
    # Walk the BOOK top group rather than the whole file: the records are small,
    # uncompressed, and all in one place.
    $books = @{}
    $menus = @{}
    $i = 0
    while ($i + 24 -le $bytes.Length) {
        $tag = [Text.Encoding]::ASCII.GetString($bytes, $i, 4)
        if ($tag -eq 'GRUP') {
            $gs = [BitConverter]::ToUInt32($bytes, $i + 4)
            if ($gs -lt 24) { break }
            $label = [Text.Encoding]::ASCII.GetString($bytes, $i + 8, 4)
            if ($label -eq 'MESG') {
                $j = $i + 24
                while ($j + 24 -le $i + $gs) {
                    $ds  = [BitConverter]::ToUInt32($bytes, $j + 4)
                    $fid = [BitConverter]::ToUInt32($bytes, $j + 12)
                    $body = [Text.Encoding]::GetEncoding(1252).GetString($bytes, $j + 24, $ds)
                    $buttons = ([regex]::Matches($body, 'ITXT')).Count
                    $menus[$fid] = $buttons
                    $j += 24 + $ds
                }
            }
            if ($label -eq 'BOOK') {
                $j = $i + 24
                while ($j + 24 -le $i + $gs) {
                    $ds  = [BitConverter]::ToUInt32($bytes, $j + 4)
                    $fid = [BitConverter]::ToUInt32($bytes, $j + 12)
                    $body = [Text.Encoding]::GetEncoding(1252).GetString($bytes, $j + 24, $ds)
                    $books[$fid] = @{
                        HasName = $body.Contains('FULL')
                        HasMesh = $body.Contains('MODL')
                        Size    = $ds
                    }
                    $j += 24 + $ds
                }
            }
            $i += $gs
            continue
        }
        $ds = [BitConverter]::ToUInt32($bytes, $i + 4)
        $i += 24 + $ds
    }

    $writs    = 0x05E80010..0x05E8001F
    $passages = 0x05E80030..0x05E80039
    $extra    = @(0x05E80000, 0x05E80001)
    $manuals  = @(0x0500B276,0x0500B277,0x0500B278,0x0500B279,
                  0x0500B27A,0x0500B27B,0x0500B27C,0x0500B27D,
                  0x05015489,0x0501548A,0x0501548B,0x0501548C,
                  0x05047F6C,0x05047F6D,0x05047F6E)

    function CheckSet($label, $ids) {
        $missing  = @($ids | Where-Object { -not $books.ContainsKey([uint32]$_) })
        $nameless = @($ids | Where-Object { $books.ContainsKey([uint32]$_) -and -not $books[[uint32]$_].HasName })
        $bodiless = @($ids | Where-Object { $books.ContainsKey([uint32]$_) -and -not $books[[uint32]$_].HasMesh })
        if ($missing)  { Bad ("{0}: {1} of {2} missing from the plugin" -f $label, $missing.Count, $ids.Count); return }
        if ($nameless) { Bad ("{0}: {1} have no name" -f $label, $nameless.Count); return }
        if ($bodiless) { Bad ("{0}: {1} have no mesh" -f $label, $bodiless.Count); return }
        Ok ("{0}: all {1} present, named and visible" -f $label, $ids.Count)
    }

    Ok ("{0} BOOK records in the plugin" -f $books.Count)
    foreach ($m in @(
        @{ Id = 0x05E80050; Name = 'trade menu, page 1'; Want = 9 }
        @{ Id = 0x05E80051; Name = 'trade menu, page 2'; Want = 9 }
        @{ Id = 0x05E80052; Name = 'town menu, page 1';  Want = 6 }
        @{ Id = 0x05E80053; Name = 'town menu, page 2';  Want = 6 }
    )) {
        if (-not $menus.ContainsKey([uint32]$m.Id)) {
            Bad ("{0} message box is missing from the plugin" -f $m.Name)
        } elseif ($menus[[uint32]$m.Id] -ne $m.Want) {
            Bad ("{0} has {1} buttons, expected {2}" -f $m.Name, $menus[[uint32]$m.Id], $m.Want)
        } elseif ($menus[[uint32]$m.Id] -gt 10) {
            Bad ("{0} has {1} buttons; Skyrim shows at most ten" -f $m.Name, $menus[[uint32]$m.Id])
        } else {
            Ok ("{0}: {1} buttons" -f $m.Name, $menus[[uint32]$m.Id])
        }
    }
    CheckSet 'trade writs'     $writs
    CheckSet 'town passages'   $passages
    CheckSet 'welcome + novice alchemy' $extra
    CheckSet 'skill manuals'   $manuals
}

Write-Host ''
Write-Host 'gamemode' -ForegroundColor Cyan
$cgPlugin = Join-Path $Data 'Platform\Plugins\thornswood-chargen.js'
if (Test-Path -LiteralPath $cgPlugin) {
    Ok 'the creation menu plugin is installed on this machine'
} else {
    Note 'the creation menu plugin is not installed here, so choices fall back to reading the books'
}

$gm = Join-Path $Dist 'gamemode.js'
if (-not (Test-Path -LiteralPath $gm)) {
    Bad "not found: $gm"
} else {
    $js = Get-Content -LiteralPath $gm -Raw
    foreach ($needle in @(
        @{ Text = "e8001f:Thornswood-Content.esp"; What = 'the trade writs' }
        @{ Text = "e80039:Thornswood-Content.esp"; What = 'the town passages' }
        @{ Text = "19bad4:Skyrim Unbound.esp";     What = 'the creation room' }
        @{ Text = "thornswoodChargen";             What = 'the creation state property' }
    )) {
        if ($js.Contains($needle.Text)) { Ok ("gamemode.js knows {0}" -f $needle.What) }
        else { Bad ("gamemode.js does not mention {0} - it is the old build" -f $needle.What) }
    }
}

Write-Host ''
Write-Host 'start point' -ForegroundColor Cyan
$sp = @($s.startPoints)[0]
if (-not $sp) {
    Bad 'server-settings.json has no startPoints'
} elseif ($idxUnbound -ge 0) {
    $want = ($idxUnbound * 0x01000000) + 0x19BAD4
    $got  = [Convert]::ToUInt32(([string]$sp.worldOrCell -replace '^0[xX]', ''), 16)
    if ($got -eq $want) {
        Ok ("start point is the creation room (0x{0:X8})" -f $want)
    } else {
        Bad ("start point is 0x{0:X8}, the creation room is 0x{1:X8}" -f $got, $want)
        Note 'run Deploy-Gamemode.ps1 again; it computes this from the load order'
    }
} else {
    Note ("start point is {0}, which is the fallback" -f $sp.worldOrCell)
}

Write-Host ''
if ($fail) {
    Write-Host "$fail check(s) failed. Fix those before starting the server." -ForegroundColor Red
    exit 1
}
Write-Host 'everything checks out.' -ForegroundColor Green
