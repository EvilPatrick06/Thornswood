<#
  MaxOnline.ps1

  How many people a Thornswood server holds at once: read from the one place
  it is written, records\most-online.json, and put into server-settings.json.
  Dot-sourced by Deploy-Gamemode.ps1 (the live server, through the built
  server's settings), Deploy-DevGamemode.ps1 (the dev server, in place,
  -Channel dev), Publish-Server.ps1 (the settings it packs, for its
  -Channel), Publish-Update.ps1 (the feed's maxOnline, the channel's seats)
  and Install-Voice.ps1 (the voice service's own number, voice, which goes
  on its command line as THORNSWOOD_VOICE_MOST; dev's for
  C:\Thornswood-Voice-Dev). Main and dev each have their own numbers since
  12 Oct (Get-MostOnline below).

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
. (Join-Path $PSScriptRoot '..\release\RecordShape.ps1')   # #2180: a version this checkout knows
$MostOnlineRecord = Join-Path $PSScriptRoot '..\..\records\most-online.json'

<#
  The number, the engine's seats and where they came from, for one channel.

  Value is 0 when there is no number to take, and Why says which way it was
  missing. The caller then leaves both keys as the server has them. Throws on
  a seat count the engine refuses: MAX_PLAYERS is 1000
  (skymp5-server/cpp/CMakeLists.txt:46), and Networking.cpp:148 throws
  "Current slots limit is 1000" at start above it, so a bigger number written
  here is a server that does not come up. Stopping the deploy is better.

  EACH CHANNEL ITS OWN NUMBERS. Patrick, 12 Oct: "change dev to of 5 awake
  cap both voice and in game to 5 for the dev server". The record's own
  people, staffSeats and voice are main's (the live server, its voice and
  the main feed). Its "dev" object holds the same three keys for the dev
  server, dev voice and the dev feed, read with -Channel dev. A record with no
  dev object gives dev main's numbers, which is how both servers were run
  before 12 Oct, and Note says so. Every rule below holds for each channel on
  its own: the engine's ceiling, and voice never fewer than that channel's
  seats.

  Seats is what the world holds at once, the people and the staff seats
  together, and is the number people are shown ("N of 30 awake"; Patrick,
  12 Oct: "the real cap is 30 but 25 for people with non staff roles I still
  want it to say of 30 awake tho"). Value is the door's number, past which
  only the Discord staff roles get in.
#>
function Get-MostOnline([string]$Path = '', [ValidateSet('main', 'dev')][string]$Channel = 'main') {
    $ceiling = 1000
    if (-not $Path) { $Path = $MostOnlineRecord }
    $r = [pscustomobject]@{ Value = 0; Staff = 0; Seats = 0; Voice = 0; From = $Path; Why = ''; Channel = $Channel; Note = '' }
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
    # A version this checkout does not know is not "no number": it is a record
    # from somewhere newer, and guessing at it is how a wrong seat count goes
    # out. Stop the deploy, naming the file (RecordShape.ps1, #2180).
    $newer = @(Get-ThornswoodRecordProblems -Doc $doc -Kind most-online | Where-Object { $_ -like 'it is version*' })
    if ($newer.Count) { throw ("{0}: {1}" -f $Path, $newer[0]) }
    # Which object the numbers come from: the record itself for main, its dev
    # object for dev when there is one.
    $nums = $doc
    $where = $Path
    $its = 'its'
    if ($Channel -eq 'dev' -and $null -ne $doc -and $doc.PSObject.Properties.Name -contains 'dev') {
        $nums = $doc.dev
        $where = $Path + ', its dev numbers,'
        $its = 'its dev'
        if ($nums -isnot [System.Management.Automation.PSCustomObject]) {
            $r.Why = 'its dev is not an object of people, staffSeats and voice'
            return $r
        }
    } elseif ($Channel -eq 'dev') {
        $r.Note = 'the record has no dev numbers, so dev takes main''s'
    }
    if ($null -eq $nums -or $nums.PSObject.Properties.Name -notcontains 'people') {
        $r.Why = $(if ($its -eq 'its') { 'it has no people' } else { 'its dev has no people' })
        return $r
    }
    $n = 0
    [void][int]::TryParse([string]$nums.people, [ref]$n)
    if ($n -le 0) {
        $r.Why = $its + ' people is not a whole number above zero'
        return $r
    }
    $staff = 0
    if ($nums.PSObject.Properties.Name -contains 'staffSeats') {
        [void][int]::TryParse([string]$nums.staffSeats, [ref]$staff)
        if ($staff -lt 0) { $staff = 0 }
    }
    if ($n + $staff -gt $ceiling) {
        throw ("{0} asks for {1} people and {2} staff seats, {3} in all. The engine seats at most {4} and will not start above it. Nothing was written." -f $where, $n, $staff, ($n + $staff), $ceiling)
    }
    $r.Value = $n
    $r.Staff = $staff
    $r.Seats = $n + $staff
    # The most people the voice service takes at once (#481), which every
    # person seated holds a socket to and every person waiting in line at the
    # menu as well, so it is never fewer than the seats. 0 when the record
    # has none, and Install-Voice.ps1 then leaves the service uncapped.
    if ($nums.PSObject.Properties.Name -contains 'voice') {
        $v = 0
        [void][int]::TryParse([string]$nums.voice, [ref]$v)
        if ($v -lt $r.Seats) {
            throw ("{0} gives voice {1}, fewer than the {2} seats ({3} people and {4} for staff roles), so somebody seated could be kept out of voice and chat. Nothing was written." -f $where, $nums.voice, $r.Seats, $n, $staff)
        }
        $r.Voice = $v
    }
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
