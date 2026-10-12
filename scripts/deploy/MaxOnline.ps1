<#
  MaxOnline.ps1

  How many people a Thornswood server holds at once: read from the one place
  it is written, records\most-online.json, and put into server-settings.json.
  Dot-sourced by Deploy-Gamemode.ps1 (the live server, through the built
  server's settings), Deploy-DevGamemode.ps1 (the dev server, in place),
  Publish-Server.ps1 (the settings it packs) and Publish-Update.ps1 (the
  feed's maxOnline).

  WHY, issue #481: "Nothing anywhere limits how many people can connect, and
  the only number that looks like a limit is decoration." Patrick, 28 Sep:
  25 at once for the alpha, raised later.

  TWO KEYS, ONE NUMBER.
    thornswoodMostOnline  the number itself. The gamemode's seats block turns
                          away anybody past it with a plain line and the log
                          says "door: full". Staff roles may go over it.
    maxPlayers            the engine's own slot count (ScampServer.cpp:205,
                          handed to RakNet by Networking.cpp:157-162). Set to
                          the number plus staffSeats, so staff still reach
                          the gamemode's check when the world is full. Past
                          it RakNet refuses with nothing said at all, so it is
                          the backstop, never the limit people meet.

  ONE PLACE. Until #481 the number was MaxOnline in the config.json of the
  launcher a release was published from, which the launcher itself rewrites
  from the feed, so changing it meant closing the launcher first and each
  machine had its own. Now it is records\most-online.json in the repository:
  change it there, merge, then run the deploy for each server and Ship, so the
  engine, the gamemode and the feed move together. The launcher and the site
  read the number the running server announces in online.json.
#>

. (Join-Path $PSScriptRoot '..\release\Read-JsonFile.ps1')   # ConvertFrom-ThornswoodJson: a bad JSON file named
$MostOnlineRecord = Join-Path $PSScriptRoot '..\..\records\most-online.json'

<#
  The number, the engine's seats and where they came from.

  Value is 0 when there is no number to take, and Why says which way it was
  missing. The caller then leaves both keys as the server has them. Throws on
  a seat count the engine refuses: MAX_PLAYERS is 1000
  (skymp5-server/cpp/CMakeLists.txt:46), and Networking.cpp:148 throws
  "Current slots limit is 1000" at start above it, so a bigger number written
  here is a server that does not come up. Stopping the deploy is better.
#>
function Get-MostOnline([string]$Path = '') {
    $ceiling = 1000
    if (-not $Path) { $Path = $MostOnlineRecord }
    $r = [pscustomobject]@{ Value = 0; Staff = 0; Seats = 0; From = $Path; Why = '' }
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { $r.Why = 'there is no most-online.json there'; return $r }
    $doc = $null
    try {
        $raw = [IO.File]::ReadAllBytes($Path)
        $skip = 0
        if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { $skip = 3 }
        $doc = ConvertFrom-ThornswoodJson ([Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip)) $Path
    } catch {
        $r.Why = 'it does not read as JSON (' + $_.Exception.Message + ')'
        return $r
    }
    if ($null -eq $doc -or $doc.PSObject.Properties.Name -notcontains 'people') {
        $r.Why = 'it has no people'
        return $r
    }
    $n = 0
    [void][int]::TryParse([string]$doc.people, [ref]$n)
    if ($n -le 0) {
        $r.Why = 'its people is not a whole number above zero'
        return $r
    }
    $staff = 0
    if ($doc.PSObject.Properties.Name -contains 'staffSeats') {
        [void][int]::TryParse([string]$doc.staffSeats, [ref]$staff)
        if ($staff -lt 0) { $staff = 0 }
    }
    if ($n + $staff -gt $ceiling) {
        throw ("{0} asks for {1} people and {2} staff seats, {3} in all. The engine seats at most {4} and will not start above it. Nothing was written." -f $Path, $n, $staff, ($n + $staff), $ceiling)
    }
    $r.Value = $n
    $r.Staff = $staff
    $r.Seats = $n + $staff
    return $r
}

<#
  Puts the number into a server-settings object: thornswoodMostOnline for the
  gamemode and maxPlayers, with the staff seats on top, for the engine. Says
  what moved. With no number both keys are left exactly as they were: the
  engine reads maxPlayers with at(), which throws on a missing key, and every
  build writes one, so leaving it is always safe and inventing one is not.
#>
function Set-MaxPlayers($settings, $got) {
    $names = $settings.PSObject.Properties.Name
    $had = ''
    if ($names -contains 'thornswoodMostOnline') { $had = [string]$settings.thornswoodMostOnline }
    $hadSeats = ''
    if ($names -contains 'maxPlayers') { $hadSeats = [string]$settings.maxPlayers }
    if ($got.Value -le 0) {
        Write-Host ("  most online: left at {0}, engine seats {1}, because {2} gave no number ({3})" -f $(if ($had) { $had } else { 'nothing' }), $(if ($hadSeats) { $hadSeats } else { 'nothing' }), $got.From, $got.Why) -ForegroundColor Yellow
        return
    }
    $settings | Add-Member -NotePropertyName thornswoodMostOnline -NotePropertyValue $got.Value -Force
    $settings | Add-Member -NotePropertyName maxPlayers -NotePropertyValue $got.Seats -Force
    $line = "  most online: {0}, engine seats {1} ({2} over it for staff roles), from {3}" -f $got.Value, $got.Seats, $got.Staff, $got.From
    if ($had -ne [string]$got.Value -or $hadSeats -ne [string]$got.Seats) {
        Write-Host ($line + ("; was {0}, engine seats {1}" -f $(if ($had) { $had } else { 'nothing' }), $(if ($hadSeats) { $hadSeats } else { 'nothing' }))) -ForegroundColor Yellow
    } else {
        Write-Host $line -ForegroundColor DarkGray
    }
}
