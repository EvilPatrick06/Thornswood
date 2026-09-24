<#
  MaxOnline.ps1

  How many people a Thornswood server seats: read from the one place it is
  written, and put into server-settings.json as the engine's own maxPlayers.
  Dot-sourced by Deploy-Gamemode.ps1 (the live server, through the built
  server's settings) and Deploy-DevGamemode.ps1 (the dev server, in place).

  WHY, entry 281: "Nothing anywhere limits how many people can connect, and
  the only number that looks like a limit is decoration."

  Measured on 24 September, the first half is wrong and the second is right.
  The engine does cap connections: ScampServer.cpp:205 reads maxPlayers out of
  server-settings.json, a key it requires, and Networking.cpp:157-162 hands it
  to RakNet as the slot count. But nothing in this repo ever wrote that key,
  so it was whatever the skymp build put there: 100 in the built server's file
  and 100 in the 16 September copy of the VPS's. The launcher's number is a
  different one, MaxOnline in the launcher's config.json, 25 on both of
  Patrick's launchers. Publish-Update.ps1 puts it in the feed as maxOnline,
  Shell.cs adopts it and the Play page says "N of 25 awake". People were told
  25, the engine seated 100, and neither number knew about the other.

  ONE NUMBER, IN ONE PLACE. The place is MaxOnline in the config.json of the
  launcher a release is published from, because that is where the feed
  already reads it, and Publish-Update.ps1 is on the shared list. These
  functions read the same key out of the same file by the same rule and the
  deploy scripts write it as maxPlayers, so the feed, the Play page and the
  engine say one number. The live server takes C:\Thornswood\config.json and
  the dev server C:\Thornswood-DevBuild\config.json, the two files the live
  and the dev feed are published from.

  To change it: close the launcher first, because it writes the feed's number
  back into its own config.json the next time it reads the feed. Edit
  MaxOnline, then run the deploy and Ship together, so the engine and the feed
  move at once.

  What this does not do yet, and the entry says so: the number is not chosen
  from a load test, and a person refused past it is told nothing. RakNet
  answers "No free incoming connections" and the client only traces it
  (skympClient.ts), so until the gamemode logs it and the client shows it,
  this is a limit the server keeps and nobody sees.
#>

# The same rule as Find-Root in Publish-Update.ps1: C:\Thornswood when it
# holds a launcher, otherwise the first drive that does, otherwise
# C:\Thornswood. Kept identical so the config.json read here is the one the
# feed was published from on any machine. The dev launcher is this plus
# -DevBuild, the same as there.
function Find-LauncherRoot {
    $first = 'C:\Thornswood'
    if (Test-Path -LiteralPath (Join-Path $first 'Launcher\Thornswood.exe')) { return $first }
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
        $cand = Join-Path $d.Root 'Thornswood'
        if (Test-Path -LiteralPath (Join-Path $cand 'Launcher\Thornswood.exe')) { return $cand }
    }
    return $first
}

<#
  The number, and the file it came from.

  Value is 0 when there is no number to take, and Why says which way it was
  missing. The caller then leaves maxPlayers as the server has it, which is
  the rule the feed follows too: Publish-Update.ps1 writes maxOnline only when
  it reads a number above zero.

  Why never quotes the file. config.json carries the server password, and a
  parse error can echo the text it choked on.

  Throws on a number the engine refuses. MAX_PLAYERS is 1000
  (skymp5-server/cpp/CMakeLists.txt:46), and Networking.cpp:148 throws
  "Current slots limit is 1000" at start above it, so a bigger number written
  here is a server that does not come up. Stopping the deploy is better.
#>
function Get-MaxOnline([string]$LauncherRoot) {
    $ceiling = 1000
    $path = Join-Path $LauncherRoot 'config.json'
    $r = [pscustomobject]@{ Value = 0; From = $path; Why = '' }
    if (-not (Test-Path -LiteralPath $path)) { $r.Why = 'there is no config.json there'; return $r }
    $cfg = $null
    try {
        # A byte order mark is skipped the way Publish-Update.ps1 skips it.
        $raw = [IO.File]::ReadAllBytes($path)
        $skip = 0
        if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { $skip = 3 }
        $cfg = [Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip) | ConvertFrom-Json
    } catch {
        $r.Why = 'it does not read as JSON'
        return $r
    }
    if ($null -eq $cfg -or $cfg.PSObject.Properties.Name -notcontains 'MaxOnline') {
        $r.Why = 'it has no MaxOnline'
        return $r
    }
    $n = 0
    [void][int]::TryParse([string]$cfg.MaxOnline, [ref]$n)
    if ($n -le 0) {
        $r.Why = 'its MaxOnline is not a whole number above zero'
        return $r
    }
    if ($n -gt $ceiling) {
        throw ("MaxOnline in {0} is {1}. The engine seats at most {2} and will not start above it. Nothing was written." -f $path, $n, $ceiling)
    }
    $r.Value = $n
    return $r
}

<#
  Puts the number into a server-settings object as maxPlayers and says what
  moved. With no number the key is left exactly as it was: the engine reads
  maxPlayers with at(), which throws on a missing key, and every build writes
  one, so leaving it is always safe and inventing one is not.
#>
function Set-MaxPlayers($settings, $got) {
    $had = ''
    if ($settings.PSObject.Properties.Name -contains 'maxPlayers') { $had = [string]$settings.maxPlayers }
    if ($got.Value -le 0) {
        Write-Host ("  most online: left at {0}, because {1} gave no number ({2})" -f $(if ($had) { $had } else { 'nothing' }), $got.From, $got.Why) -ForegroundColor Yellow
        return
    }
    $settings | Add-Member -NotePropertyName maxPlayers -NotePropertyValue $got.Value -Force
    if ($had -ne [string]$got.Value) {
        Write-Host ("  most online: {0}, was {1}. From MaxOnline in {2}, the number the feed announces" -f $got.Value, $(if ($had) { $had } else { 'nothing' }), $got.From) -ForegroundColor Yellow
    } else {
        Write-Host ("  most online: {0}, from MaxOnline in {1}" -f $got.Value, $got.From) -ForegroundColor DarkGray
    }
}
