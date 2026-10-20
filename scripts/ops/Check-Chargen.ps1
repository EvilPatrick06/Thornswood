<#
  Check-Chargen.ps1

  Preflight for character creation. Everything it looks at is something that
  silently produces a broken first join rather than an error message, so it is
  worth thirty seconds before starting the server.

  It checks, in order:
    - the server's load order holds both plugins the flow needs
    - the plugin on disk really carries the fourteen new book records
    - the fifteen salvaged manuals have a name and a mesh, which they did not
      when they were first shipped
    - gamemode.js is the build that knows about all of it
    - the start point in server-settings.json is the creation room, computed
      from this load order rather than written down

      .\scripts\ops\Check-Chargen.ps1              the build on this machine
      .\scripts\ops\Check-Chargen.ps1 -From dev    the dev server's own settings
      .\scripts\ops\Check-Chargen.ps1 -From live   the live server's own settings

  ASK THE BOX, NOT ONLY THE BUILD. Until 23 September this read the built
  server on this machine and nothing else, and the file that went wrong was
  the one on the dev box: it keeps its own server-settings.json, which is
  the whole reason Deploy-DevGamemode exists, and its start point was left
  naming file index 58 after the load order under it moved. Skyrim Unbound
  is at 54 there, in a list of 57, so every new character died at login with
  'FromFormId failed due to invalid file index 58' and the client showed a
  box saying only that there were technical difficulties. This check would
  have found it in ten seconds and could not be pointed at the file.

  Read only, here and there. It changes nothing on either machine.
#>
param(
    [string]$Dist = (& (Join-Path $PSScriptRoot '..\release\Where.ps1') ServerDist),
    [string]$Data = 'C:\Thornswood\Game\Data',
    # Whose settings to read: the build on this machine, or a server's own.
    [ValidateSet('build', 'live', 'dev')][string]$From = 'build',
    [string]$Vps  = '',
    [string]$User = ''
)


$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\deploy\ServerOrder.ps1')
if (-not $User) { $User = Get-ThornswoodVpsUser }
if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }
$fail = 0
function Ok  ($m) { Write-Host "  ok    $m" -ForegroundColor Green }
function Bad ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Note($m) { Write-Host "        $m" -ForegroundColor DarkGray }

if ($From -eq 'build') {
    $settingsPath = Join-Path $Dist 'server-settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) { throw "not found: $settingsPath" }
    $s = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    Write-Host ''
    Write-Host "reading the build at $settingsPath" -ForegroundColor DarkGray
} else {
    # The files are read where they live and only text comes back. Nothing
    # is written on either machine.
    #
    # WHICH PLUGINS ARE LIGHT IS THE BOX'S TOO (#2947): each file the
    # settings' loadOrder names is read there by Test-ThornswoodPluginLight,
    # and whether the engine loads light plugins comes from the server's own
    # server-build.json. Until then both came from this machine (the game
    # folder in -Data and this checkout's record), so on a machine with no
    # game folder (a cloud one) this stopped on the first plugin it could
    # not find, and a game folder with another copy of a plugin answered for
    # a file the server does not load.
    $root = if ($From -eq 'dev') { 'C:\Thornswood-Server-Dev' } else { 'C:\Thornswood-Server' }
    $settingsPath = "$root\server-settings.json"
    $lightDef = 'function Test-ThornswoodPluginLight {' + "`n" + (Get-Command Test-ThornswoodPluginLight).Definition + "`n}"
    $remote = @"
`$ProgressPreference = 'SilentlyContinue'
$lightDef
`$raw = Get-Content -LiteralPath '$settingsPath' -Raw
`$rp = '$root\server-build.json'
if (-not (Test-Path -LiteralPath `$rp)) { 'ENGINE none' }
else { try { `$r = Get-Content -LiteralPath `$rp -Raw | ConvertFrom-Json; 'ENGINE ' + [string](`$r.lightPlugins -eq `$true) } catch { 'ENGINE unreadable' } }
foreach (`$o in @((`$raw | ConvertFrom-Json).loadOrder)) {
  `$f = [string]`$o
  try { 'LIGHT ' + [int](Test-ThornswoodPluginLight `$f) + ' ' + [IO.Path]::GetFileName(`$f) } catch { 'UNREAD ' + [IO.Path]::GetFileName(`$f) }
}
'SETTINGS'
`$raw
"@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))
    $text = Invoke-ThornswoodNative { & ssh -o BatchMode=yes -o StrictHostKeyChecking=yes "$User@$Vps" "powershell -NoProfile -EncodedCommand $enc" } 2>&1
    $lines = @($text | ForEach-Object { "$_" })
    $at = [Array]::IndexOf([string[]]$lines, 'SETTINGS')
    if ($at -lt 0) { throw "could not read $settingsPath from $Vps : $($lines -join "`n")" }
    $json = (@($lines | Select-Object -Skip ($at + 1)) -join "`n")
    if ($json.IndexOf('{') -lt 0) { throw "could not read $settingsPath from $Vps : $json" }
    $s = $json.Substring($json.IndexOf('{')) | ConvertFrom-Json
    $boxEngine = @($lines | Where-Object { $_ -like 'ENGINE *' } | Select-Object -First 1)
    $boxLight = @{}
    $boxUnread = @()
    foreach ($l in $lines) {
        if ($l -match '^LIGHT ([01]) (.+)$') { $boxLight[$Matches[2].Trim().ToLowerInvariant()] = ($Matches[1] -eq '1') }
        elseif ($l -match '^UNREAD (.+)$') { $boxUnread += $Matches[1].Trim() }
    }
    Write-Host ''
    Write-Host "reading the $From server at $Vps, $settingsPath" -ForegroundColor DarkGray
    Write-Host '  and which of its plugins are light, from the files it loads there' -ForegroundColor DarkGray
    Write-Host '  the plugin and gamemode checks below still read this machine' -ForegroundColor DarkGray
}
$order = @($s.loadOrder | ForEach-Object { @("$_".Trim() -split '[\\/]')[-1] })

Write-Host ''
Write-Host 'load order' -ForegroundColor Cyan
# Full indices: an engine that loads light plugins lists them and gives them
# none (#1715). For the build on this machine, which engine is this
# checkout's record and which plugins are light is read from -Data, like the
# checks below; for a server, both are the box's own (above).
if ($From -eq 'build') {
    $lightTest = Get-ThornswoodLightTest ([string[]]@($order | ForEach-Object { Join-Path $Data $_ })) (Join-Path $Here '..\..\records\server-build.json')
} else {
    if ($boxEngine -notcontains 'ENGINE True' -and $boxEngine -notcontains 'ENGINE False') {
        throw ("the $From server's server-build.json said " + ($boxEngine -join ' ') + ', so it is not known whether its engine loads light plugins')
    }
    if ($boxUnread.Count) {
        throw ("the $From server cannot read whether " + ($boxUnread -join ', ') + ' is light, so no full index can be counted')
    }
    $lightTest = $null
    if ($boxEngine -contains 'ENGINE True') { $lightTest = { param($n) [bool]$boxLight[$n.ToLowerInvariant()] }.GetNewClosure() }
}
$idxContent = Get-ThornswoodFullIndex ([string[]]$order) $lightTest 'Thornswood-Content.esp'
$idxUnbound = Get-ThornswoodFullIndex ([string[]]$order) $lightTest 'Skyrim Unbound.esp'

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
        Note ("it names file index {0}; Skyrim Unbound.esp is at {1} in this load order" -f
              [int]($got -shr 24), $idxUnbound)
        Note 'a new character cannot spawn at all: the server throws FromFormId failed'
        Note 'and the client shows a box saying only that there are technical difficulties'
        if ($From -eq 'build') {
            Note 'run Deploy-Gamemode.ps1 again; it computes this from the load order'
        } else {
            Note 'run Deploy-DevGamemode.ps1; it recomputes this on the box every run'
        }
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
