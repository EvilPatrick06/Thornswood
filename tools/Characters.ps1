<#
  Characters.ps1

  Who has what, and a way to wipe it.

  A character on this server is not a save file. It is a change form the game
  server holds, keyed by a profile id, and the register in the voice service
  says which profile ids belong to which Steam account. This reads that
  register and, when you ask it to, forgets somebody.

      .\Characters.ps1                      list everyone

      .\Characters.ps1 -Wipe 76561198...    wipe that Steam account

  What a wipe actually does, said plainly, because it is not a delete:

    The register entry is removed. That is all. Since 20 September the
    launcher neither reads nor writes the register (the sync that did was
    deleted; it never got an answer, because it sent no password), so a wipe
    changes nothing on the person's machine: their profiles.txt still lists
    their ids and the game's main menu still offers them. Nothing feeds the
    register any more either, so what this lists is what launchers claimed
    before that date.

    The change forms stay in the world file. That is on purpose. A profile
    id is the only handle anything has on a character, and a wipe that also
    reached into the world would be a wipe you could not take back if you
    typed the wrong Steam id. The register keeps a history of every id it
    has seen for an account. Run with -History to see them.

    If you want the world file itself emptied, that is a different and much
    bigger thing: stop the server, move C:\Thornswood-Server\world aside, and
    start it. That wipes everybody, including you.
#>
[CmdletBinding()]
param(
    [string]$Wipe = '',
    [switch]$History,
    [string]$VpsHost = '192.135.112.23',
    [int]$Port = 7778,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

# The same secret the launcher sends, out of the same file the installer read
# it from. If these two ever disagree the server answers 403 and says nothing.
$secret = ''
$secretFile = Join-Path (Split-Path -Parent $Here) 'server-secret.txt'
try {
    # Kept out of version.json on purpose: that file is published into a PUBLIC
    # repository, so a secret written there is a secret handed to everybody.
    # server-secret.txt is gitignored and never leaves this machine. The
    # version.json fallback is only for a checkout made before that changed.
    if (Test-Path -LiteralPath $secretFile) {
        $secret = [string]([IO.File]::ReadAllText($secretFile)).Trim()
    }
    if (-not $secret) {
        $vjson = Join-Path (Split-Path -Parent $Here) 'version.json'
        if (Test-Path -LiteralPath $vjson) {
            $secret = [string]((Get-Content -LiteralPath $vjson -Raw | ConvertFrom-Json).serverPassword)
        }
    }
} catch { }
if (-not $secret) { Die 'No server-secret.txt beside the repo, so there is nothing to authenticate with. Run Ship or Publish-Update once to write it.' }

$body = @{ password = $secret }
if ($Wipe) {
    if ($Wipe -notmatch '^[0-9]{5,20}$') { Die "'$Wipe' is not a Steam id. It is 17 digits." }

    Head 'Wiping'
    Say "  Steam account $Wipe" 'Yellow'
    Say '  Only the register entry goes. Their launcher still lists their ids' 'Yellow'
    Say '  and the game menu still offers them; the world file is not touched.' 'DarkGray'
    Write-Host ''
    $sure = Read-Host 'Type the last four digits of that Steam id to go ahead'
    if ($sure -ne $Wipe.Substring($Wipe.Length - 4)) { Die 'Not confirmed, nothing was changed.' }
    $body['forget'] = $Wipe
}

$json = $body | ConvertTo-Json -Compress
try {
    $answer = Invoke-RestMethod -Uri "http://${VpsHost}:$Port/owners" -Method Post `
                                -ContentType 'application/json' -Body $json -TimeoutSec 10
} catch {
    Die "Could not reach the register at ${VpsHost}:$Port. $($_.Exception.Message)"
}

if ($Wipe) { Say '  done' 'Green' }

Head 'Characters on the server'

<#
  @($null) is an array of length one containing nothing, not an empty array.

  That is why an empty register printed a blank account with a blank character
  under it instead of saying nobody is registered: $answer.owners came back
  null, @($null) counted as one, and the loop ran once over nothing.
#>
$accounts = $answer.owners
if ($null -eq $accounts) {
    Say '  The server answered, but with no register in it.' 'Yellow'
    Say '  That usually means secret.txt is missing up there, so every' 'DarkGray'
    Say '  account route is switched off. Run .\Install-Voice.ps1 again.' 'DarkGray'
    Write-Host ''
    Say ('  raw answer: ' + ($answer | ConvertTo-Json -Compress -Depth 5)) 'DarkGray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 1
}

$names = @($accounts.PSObject.Properties.Name | Where-Object { $_ })
if (-not $names.Count) {
    Say '  Nobody is registered yet.' 'DarkGray'
    Say '  The register fills in as people open the launcher, one entry each.' 'DarkGray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

foreach ($steam in $names) {
    $rec = $accounts.$steam
    Write-Host ''
    Say "  $steam" 'White'
    foreach ($p in @($rec.profiles | Where-Object { $_ })) {
        $who = if ($p.name) { $p.name } else { '(unnamed)' }
        $when = ''
        try {
            if ($p.played -gt 0) { $when = '  last played ' + ([datetime]$p.played).ToString('d MMM HH:mm') }
        } catch { }
        Say ("    slot {0}   profile {1,-12} {2}{3}" -f $p.slot, $p.profileId, $who, $when) 'Gray'
    }
    if ($History) {
        $seen = @($rec.seen | Where-Object { $_ })
        if ($seen.Count) { Say ('    every id ever seen: ' + ($seen -join ', ')) 'DarkGray' }
    }
}

Write-Host ''
if (-not $History) { Say 'Add -History to see ids these accounts used to own.' 'DarkGray' }
Say 'To wipe one:  .\Characters.ps1 -Wipe <steam id>' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
