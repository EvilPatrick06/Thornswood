<#
  Install-Thornswood.ps1

  Everything the client needs, in one run, in the order it has to happen in.

  This replaces the sequence you have been typing by hand: the content plugin,
  the SkyMP client, the emote wheel and the creation menus, the body fix, the
  load order alignment, the gamemode, the preflight check and the launcher
  build. Each step names the files it must leave behind, and a step that exits
  cleanly without leaving them is treated as a failure, because those are the
  ones that reach five people before anybody notices.

  Nothing here starts a server or a game. When it finishes, press Play.

      .\Install-Thornswood.ps1              the lot
      .\Install-Thornswood.ps1 -SkipBody    leave the body meshes alone
      .\Install-Thornswood.ps1 -Only launcher,gamemode

  Step names for -Only and -Skip:
      content  client  emotes  body  loadorder  gamemode  check  launcher
#>
[CmdletBinding()]
param(
    [string]$Root   = 'C:\Thornswood',
    [string]$Server = 'C:\Thornswood-Dev\skymp\build\dist\server',
    [string]$Client = 'C:\Thornswood-Dev\skymp\build\dist\client',
    [string]$ServerIp = '192.135.112.23',
    [string]$ServerPort = '7777',
    [string[]]$Only = @(),
    [string[]]$Skip = @(),
    [switch]$SkipBody,
    # Publishing is the default, not an extra step to remember. This is a test
    # server: a build that is only on this machine cannot be tested by anybody
    # else, and every round of "why is it not fixed" so far has ended at a fix
    # that was built but never shipped.
    [switch]$NoShip,
    [string]$Notes,
    [switch]$NoPause
)

# Deliberately NOT Set-StrictMode. Strict mode is inherited by every script
# this one calls, and the scripts below were written and tested without it, so
# turning it on here makes them fail on lines that have always been fine. The
# same goes for ErrorActionPreference: each of them sets its own.
Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Data = Join-Path $Root 'Game\Data'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('=' * $m.Length) -ForegroundColor DarkGray }
function Good($m) { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red }
function Note($m) { Write-Host "  $m" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '  THORNSWOOD  -  install everything' -ForegroundColor White
Note $Root

if (-not (Test-Path -LiteralPath $Root)) {
    Write-Host ''
    Say "STOP. $Root does not exist. Point -Root at the build folder." 'Red'
    if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
    exit 1
}

# A game left running holds the very files every step below writes, and the
# failure it produces says "access denied" rather than "close Skyrim".
foreach ($n in 'SkyrimSE', 'skse64_loader') {
    if (Get-Process -Name $n -ErrorAction SilentlyContinue) {
        Write-Host ''
        Say "STOP. $n is running. Close the game first, or these files cannot be written." 'Red'
        if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
        exit 1
    }
}

# Run through powershell -File, -Only content,client arrives as one string
# rather than two, because -File does not parse arrays. Splitting here means it
# behaves the same whether it was typed in a session or into a shortcut.
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { $_.Trim() })
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { $_.Trim() })

if ($SkipBody) { $Skip += 'body' }

# ---------------------------------------------------------------- the steps --
$launcherBuild = Join-Path ([IO.Path]::GetTempPath()) ('Thornswood-launcher-' + (Split-Path -Leaf $Root.TrimEnd('\')))
$steps = @(
    @{
        Key = 'content'; Name = 'ThornsWood content plugin'
        Script = 'Install-ThornswoodContent.ps1'
        Args = @{}
        Wants = @('Thornswood-Content.esp')
        Why = 'the books, the writs and the creation menus'
    },
    @{
        Key = 'client'; Name = 'SkyMP client'
        Script = 'Install-SkyMPClient.ps1'
        Args = @{ Dist = $Client }
        Wants = @('SKSE\Plugins\MpClientPlugin.dll', 'Platform\Plugins\skymp5-client.js')
        Why = 'the multiplayer layer itself'
    },
    @{
        Key = 'emotes'; Name = 'Emote wheel and creation menus'
        Script = 'Install-Emotes.ps1'
        Args = @{}
        Wants = @('Platform\Plugins\thornswood-emotes.js',
                  'Platform\Plugins\thornswood-chargen.js',
                  'Platform\UI\thornswood-emotes.html',
                  'SKSE\Plugins\Thornswood.ini')
        Why = 'the wheel, and the trade and town questions during creation'
    },
    @{
        Key = 'body'; Name = 'Male body fix'
        Script = 'Fix-MaleBody.ps1'
        Args = @{}
        Wants = @()
        Why = 'the hole you could see the sky through'
    },
    @{
        Key = 'loadorder'; Name = 'Load order alignment'
        Script = 'Align-LoadOrder.ps1'
        Args = @{ Fix = $true }
        Wants = @()
        Why = 'form ids are resolved by plugin index, so the two lists have to agree'
    },
    @{
        Key = 'gamemode'; Name = 'Gamemode'
        Script = 'Deploy-Gamemode.ps1'
        Args = @{ Dist = $Server }
        Wants = @()
        Why = 'the server side of creation, respawn and the shop'
        NeedsServer = $true
    },
    @{
        Key = 'check'; Name = 'Preflight'
        Script = 'Check-Chargen.ps1'
        Args = @{ Dist = $Server }
        Wants = @()
        Why = 'proves the menus, the books and the load order all line up before you launch'
        NeedsServer = $true
    },
    # Two steps under one key since 24 September, when Build-Launcher.ps1
    # stopped closing anything or touching the Desktop (To Do List entry 243).
    # The build goes to a folder of its own, so csc never meets a launcher
    # still open from $Root, and Install-Launcher.ps1 closes it and puts the
    # exe and the shortcut in place, which is what this step always did.
    @{
        Key = 'launcher'; Name = 'Launcher'
        Script = 'Build-Launcher.ps1'
        Args = @{ OutDir = $launcherBuild }
        Wants = @()
        Why = 'compiles the exe with the new settings page in it'
    },
    @{
        Key = 'launcher'; Name = 'Launcher in place'
        Script = 'Install-Launcher.ps1'
        Args = @{ From = $launcherBuild }
        Wants = @()
        Why = 'closes the old one, puts the new exe in and points the shortcut at it'
    }
)

$ran = 0; $done = @(); $skipped = @()

foreach ($s in $steps) {
    $key = $s.Key
    if (@($Only).Count -gt 0 -and $Only -notcontains $key) { continue }
    if ($Skip -contains $key) { $skipped += $s.Name; continue }

    $path = Join-Path $Here $s.Script
    if (-not (Test-Path -LiteralPath $path)) {
        Head $s.Name
        Bad "$($s.Script) is not in this folder, so this step was skipped."
        $skipped += $s.Name
        continue
    }

    # Ship builds the launcher itself, so doing it here as well compiles the
    # same exe twice in a row. The second attempt lands while Explorer still has
    # the file open from the icon refresh the first one triggered, and csc fails
    # with "used by another process". One build, done by whoever is going to
    # publish it.
    if ($key -eq 'launcher' -and -not $NoShip -and (Test-Path -LiteralPath (Join-Path $Here 'Ship.ps1'))) {
        # Both launcher steps land here, and Ship does both, so it is said once.
        if ($done -notcontains 'Launcher') {
            Head 'Launcher'
            Note 'built as part of publishing, just below'
            $done += 'Launcher'
        }
        continue
    }

    if ($s.ContainsKey('NeedsServer') -and $s.NeedsServer -and -not (Test-Path -LiteralPath $Server)) {
        Head $s.Name
        Note "no server build at $Server, so this step does not apply on this machine"
        $skipped += $s.Name
        continue
    }

    Head $s.Name
    Note $s.Why

    $splat = @{}
    foreach ($k in $s.Args.Keys) { $splat[$k] = $s.Args[$k] }

    # Every one of these takes -NoPause, and none of them should be stopping a
    # batch run to wait for a keypress nobody is there to give.
    $help = Get-Command $path
    if ($help.Parameters.ContainsKey('NoPause')) { $splat['NoPause'] = $true }
    if ($help.Parameters.ContainsKey('Root'))    { $splat['Root'] = $Root }
    if ($help.Parameters.ContainsKey('NoShip'))  { $splat['NoShip'] = $true }

    # Install-SkyMPClient writes the address into the client settings itself.
    # The launcher rewrites it on every Play anyway, but there is no reason to
    # leave 127.0.0.1 sitting in the file in the meantime.
    if ($help.Parameters.ContainsKey('ServerIp'))   { $splat['ServerIp'] = $ServerIp }
    if ($help.Parameters.ContainsKey('ServerPort')) { $splat['ServerPort'] = $ServerPort }

    # These scripts each default to C:\Thornswood on their own, which is
    # right until somebody passes -Root. Handing them the folder this run is
    # actually working on is what makes -Root mean anything.
    if ($help.Parameters.ContainsKey('Data')) { $splat['Data'] = $Data }
    if ($help.Parameters.ContainsKey('Game')) { $splat['Game'] = (Join-Path $Root 'Game') }
    # Deliberately not -Dist. Three of these take a parameter by that name and
    # it does not mean the same folder in all three: the client installer wants
    # dist\client, the gamemode and the preflight want dist\server. Handing it
    # out by name pointed the client installer at the server build, which copied
    # nothing and said so quietly. Each step names its own instead.

    $failed = $false
    $global:LASTEXITCODE = 0
    try {
        Set-StrictMode -Off
        $ErrorActionPreference = 'Continue'
        & $path @splat
        if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) { $failed = $true }
    }
    catch {
        Bad $_.Exception.Message
        $failed = $true
    }

    # A script can exit 0 and still not have written what it promised.
    $missing = @()
    foreach ($w in @($s.Wants)) {
        if (-not (Test-Path -LiteralPath (Join-Path $Data $w))) { $missing += $w }
    }

    if ($failed -or @($missing).Count) {
        foreach ($m in $missing) { Bad "$m was not written" }
        Write-Host ''
        Say "STOP. $($s.Name) did not finish. Nothing after this point was run," 'Red'
        Say 'because a half installed build is worse than an old one.' 'Red'
        if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
        exit 1
    }

    $wants = @($s.Wants)
    foreach ($w in $wants) { Good $w }
    if (-not $wants.Count) { Good 'done' }
    $done += $s.Name
    $ran++
}

# ---------------------------------------------------------------- summary ----
Head 'Done'
foreach ($d in $done) { Good $d }
foreach ($k in $skipped) { Note "skipped: $k" }

# ---------------------------------------------------------------- publish ---
# Unless told otherwise, and only when the launcher was actually rebuilt: a
# publish with nothing in it still burns a version number.
$shipped = $false
if (-not $NoShip -and ($done -contains 'Launcher')) {
    $ship = Join-Path $Here 'Ship.ps1'
    if (Test-Path -LiteralPath $ship) {
        Head 'Publishing'
        if (-not $Notes) { $Notes = 'Build from ' + (Get-Date -Format 'd MMM HH:mm') }
        Note 'so everyone else gets this too. -NoShip skips it.'

        # Only parameters Ship actually has. Passing one it does not know is a
        # binding error, not an exit code, so $LASTEXITCODE stays 0 from the
        # last thing that did run and this reported a publish that never
        # happened. Which is the exact failure this block exists to prevent.
        $shipArgs = @{}
        $shipCmd = Get-Command $ship
        if ($shipCmd.Parameters.ContainsKey('Root'))    { $shipArgs['Root'] = $Root }
        if ($shipCmd.Parameters.ContainsKey('NoPause')) { $shipArgs['NoPause'] = $true }

        $global:LASTEXITCODE = 0
        try {
            & $ship $Notes @shipArgs
            $shipped = ($null -eq $LASTEXITCODE -or $LASTEXITCODE -eq 0)
        }
        catch {
            Bad $_.Exception.Message
            $shipped = $false
        }
    }
    else { Note 'Ship.ps1 is not here, so nothing was published.' }
}

Write-Host ''
Say 'Open the launcher and press Play.' 'Green'
if ($shipped) { Note 'Published, so your friends get it on their next launcher start.' }
elseif (-not $NoShip -and ($done -contains 'Launcher')) { Note 'Publishing did not finish. Run .\Ship.ps1 yourself.' }
Write-Host ''
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
