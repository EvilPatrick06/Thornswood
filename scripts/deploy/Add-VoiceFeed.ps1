<#
  Add-VoiceFeed.ps1

  Adds the position feed to gamemode.js and redeploys it.

  The voice service needs to know where everybody is. It gets that from the
  game server, which already knows, rather than from anybody's game. So voice
  works whichever client somebody runs, nobody can move their own voice by
  editing a file, and there is nothing to install on five machines.

  The block it adds is self contained and wrapped end to end. A voice service
  that is down, slow, or never installed cannot take the game server with it:
  the worst case is a line in the log once and no voice.

  Safe to run twice. It replaces its own block rather than stacking another.

  IT WILL NOT UNDO A NEWER BLOCK. The copy between the markers in
  game\gamemode.js has moved on since voice\gamemode-voice.js was written: it
  reads its port from server-settings.json, so the dev server feeds the dev
  voice service, where the file still has 7778 written in. Running this used
  to put the old file over it and redeploy the live gamemode (issue #546).
  Now it stops when the block in the gamemode is not the file, and -Force is
  the only way past that.
#>
[CmdletBinding()]
param(
    [string]$Gamemode,
    [string]$Block,
    [switch]$Remove,
    [switch]$NoDeploy,
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $Gamemode) { $Gamemode = Join-Path $Here '..\..\game\gamemode.js' }
if (-not $Block)    { $Block    = Join-Path $Here '..\..\voice\gamemode-voice.js' }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

if (-not (Test-Path -LiteralPath $Gamemode)) { Die "not found: $Gamemode" }

$START = '// ==== thornswood voice feed, added by Add-VoiceFeed.ps1 ===='
$END   = '// ==== end thornswood voice feed ===='

$text = [IO.File]::ReadAllText($Gamemode)

# Take any previous copy out first, so running this twice replaces rather than
# stacks, and -Remove has nothing special to do.
$pattern = [regex]::Escape($START) + '.*?' + [regex]::Escape($END)
$had = [regex]::IsMatch($text, $pattern, 'Singleline')
if ($had -and -not $Remove -and -not $Force -and (Test-Path -LiteralPath $Block)) {
    $inside = [regex]::Match($text, [regex]::Escape($START) + '\r?\n(.*?)\r?\n' + [regex]::Escape($END), 'Singleline').Groups[1].Value
    $file = [IO.File]::ReadAllText($Block).TrimEnd()
    if ($inside.Replace("`r`n", "`n").TrimEnd() -ne $file.Replace("`r`n", "`n")) {
        Die ("The voice feed in $Gamemode is not ${Block}: it has been changed since, and this would put the older one back " +
             "and redeploy it. Nothing was changed. Put the change into $Block first, or run with -Force if replacing it is what you mean.")
    }
}
if ($had) {
    $text = [regex]::Replace($text, $pattern, '', 'Singleline').TrimEnd() + "`r`n"
    Say '  removed the previous feed block' 'DarkGray'
}

if ($Remove) {
    [IO.File]::WriteAllText($Gamemode, $text, (New-Object Text.UTF8Encoding($false)))
    Say 'Voice feed taken out of gamemode.js.' 'Green'
    if (-not $NoDeploy) {
        Head 'Redeploying'
        & (Join-Path $Here 'Deploy-Gamemode.ps1')
    }
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

if (-not (Test-Path -LiteralPath $Block)) { Die "not found: $Block" }

Head 'Adding the position feed'
$body = [IO.File]::ReadAllText($Block)
$text = $text.TrimEnd() + "`r`n`r`n" + $START + "`r`n" + $body.TrimEnd() + "`r`n" + $END + "`r`n"

# No byte order mark: the server reads this as plain JavaScript and a BOM has
# already cost an evening once on server-settings.json.
[IO.File]::WriteAllText($Gamemode, $text, (New-Object Text.UTF8Encoding($false)))
Say ("  gamemode.js is now {0:N0} KB" -f ((Get-Item $Gamemode).Length / 1KB)) 'Green'

if ($NoDeploy) {
    Write-Host ''
    Say 'Not deployed, as asked. The server is still running the old gamemode.' 'Yellow'
    Say '  .\Deploy-Gamemode.ps1   then  .\Publish-Server.ps1' 'DarkGray'
} else {
    Head 'Redeploying'
    & (Join-Path $Here 'Deploy-Gamemode.ps1')
    Write-Host ''
    Say 'Local gamemode updated. Push it to the VPS so the server actually runs it:' 'Yellow'
    Say '  .\Publish-Server.ps1' 'Yellow'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
