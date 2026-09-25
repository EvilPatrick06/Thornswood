<#
  Set-Server.ps1

  Sets the server everyone connects to, in the two places that decide it, and
  pushes.

      .\Set-Server.ps1 -Address 192.135.112.23 -Port 7777

  The two places:
    config.json     this machine's launcher
    version.json    every other launcher, which copies it into their config on
                    the next update check

  Only changing one of them does not hold. Fix config.json alone and the next
  update check puts the published value straight back over it. Fix version.json
  alone and the next publish copies this machine's stale config over that. They
  have to move together, which is what this does.

  It checks the address answers before writing anything, because publishing one
  that does not is how five people end up in single player wondering what they
  broke. -Force skips that.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Address,
    [string]$Port = '7777',
    [string]$Root = 'C:\Thornswood',
    [string]$RepoDir,
    [string]$ReleaseDir,
    [switch]$Force,
    [switch]$NoPush,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $RepoDir) { $RepoDir = Split-Path -Parent $Here }
# version.json is published from the public releases clone, not the source one.
if (-not $ReleaseDir) {
    $guess = Join-Path (Split-Path -Parent $RepoDir) 'Thornswood-Releases'
    # The feed lives only in the releases clone. This repository's own copy, the
    # old fallback, was deleted on 25 September (#363), so without a clone
    # there is nothing to edit and this stops rather than guess.
    if (-not (Test-Path (Join-Path $guess '.git'))) { throw "No Thornswood-Releases clone at $guess. Clone it there (git clone https://github.com/EvilPatrick06/Thornswood-Releases), or pass -ReleaseDir." }
    $ReleaseDir = $guess
}

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

Write-Host ''
Write-Host '  THORNSWOOD  -  set the server' -ForegroundColor White
Say "  $Address`:$Port" 'DarkGray'

# ------------------------------------------------------------- is it there ---
if (-not $Force) {
    Head 'Checking it answers'
    # Game traffic is UDP with nothing to connect to, so the resources folder on
    # 3000 is what a probe can actually reach.
    $up = $false
    try {
        $c = New-Object Net.Sockets.TcpClient
        $null = $c.BeginConnect($Address, 3000, $null, $null).AsyncWaitHandle.WaitOne(2000)
        $up = $c.Connected
        $c.Close()
    } catch { }
    if ($up) { Say '  answering' 'Green' }
    else {
        Die "Nothing is answering at ${Address}:3000. Start the server first, or pass -Force if you know it is coming up later."
    }
}

# ------------------------------------------------------------- config.json ---
Head 'This machine'
$cfgPath = Join-Path $Root 'config.json'
if (-not (Test-Path -LiteralPath $cfgPath)) { Die "not found: $cfgPath" }

$raw = [IO.File]::ReadAllBytes($cfgPath)
$skip = if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { 3 } else { 0 }
$cfg = [Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip) | ConvertFrom-Json

Say ("  was  {0}:{1}" -f $cfg.ServerAddress, $cfg.ServerPort) 'DarkGray'
$cfg.ServerAddress = $Address
$cfg.ServerPort = $Port
# No byte order mark. The launcher's reader stops on one.
[IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
Say ("  now  {0}:{1}" -f $Address, $Port) 'Green'

# ------------------------------------------------------------ version.json ---
Head 'Everyone else'
$VersionFile = Join-Path $ReleaseDir 'version.json'
if (-not (Test-Path -LiteralPath $VersionFile)) { Die "not found: $VersionFile" }

$doc = Get-Content -LiteralPath $VersionFile -Raw | ConvertFrom-Json
$wasA = if ($doc.PSObject.Properties.Name -contains 'serverAddress') { [string]$doc.serverAddress } else { '' }
$wasP = if ($doc.PSObject.Properties.Name -contains 'serverPort') { [string]$doc.serverPort } else { '' }
Say ("  was  {0}:{1}" -f $wasA, $wasP) 'DarkGray'

foreach ($pair in @(@('serverAddress', $Address), @('serverPort', $Port))) {
    if ($doc.PSObject.Properties.Name -contains $pair[0]) { $doc.($pair[0]) = $pair[1] }
    else { $doc | Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] }
}
[IO.File]::WriteAllText($VersionFile, ($doc | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
Say ("  now  {0}:{1}" -f $Address, $Port) 'Green'

if ($NoPush) {
    Write-Host ''
    Say 'Not pushed, as asked. Until it is, the other launchers still have the old one.' 'Yellow'
}
else {
    Head 'Pushing'
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git -C $ReleaseDir add version.json 2>&1 | Out-Host
    & git -C $ReleaseDir commit -m "Server is now ${Address}:${Port}" 2>&1 | Out-Host
    & git -C $ReleaseDir push 2>&1 | Out-Host
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($rc -ne 0) { Die "git push exited with $rc. Both files are fixed here, they are just not up yet." }
    Say '  pushed' 'Green'
}

Write-Host ''
Say 'Everyone picks this up the next time their launcher checks for updates.' 'Green'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
