<#
  Reset-Character.ps1

  Throws away the character on the server so the next launch runs creation from
  the top. Works against the VPS or against a server on this machine.

  Your character is not a save file under SkyMP. It is a change form the server
  holds, so New Game in Skyrim's own menu hands the same body, the same
  inventory and the same face straight back. This is the only thing that
  actually gives you a new one.

  The change forms named with a bare number are the ones belonging to people.
  Everything else in that folder describes the world and is left alone. Nothing
  is deleted: what is thrown away goes into a _discarded folder beside it.

      .\Reset-Character.ps1            the VPS
      .\Reset-Character.ps1 -Local     a server running on this machine

  The launcher has a switch for this in Settings, but only for a local server,
  because it will not hold your VPS password and neither will this.
#>
[CmdletBinding()]
param(
    [string]$VpsHost  = '',
    [string]$VpsUser  = '',
    [string]$VpsRoot  = 'C:\Thornswood-Server',
    [string]$TaskName = 'Thornswood Server',
    [string]$Local    = (& (Join-Path $PSScriptRoot '..\release\Where.ps1') ServerDist),
    [switch]$UseLocal,
    [switch]$NoPause
)


$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

# The body of the job, written once and run in both places. Everything it needs
# arrives as two arguments, so there is no second copy of this logic to drift.
$body = @'
param([string]$Root)
$forms = Join-Path $Root 'world\changeForms'
if (-not (Test-Path -LiteralPath $forms)) { Write-Host 'no characters saved yet, nothing to do'; exit 0 }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bin = Join-Path $forms ('_discarded-' + $stamp)
$moved = 0
foreach ($f in (Get-ChildItem -LiteralPath $forms -Filter *.json -File)) {
    if ($f.BaseName -notmatch '^[0-9]+$') { continue }
    if (-not (Test-Path -LiteralPath $bin)) { New-Item -ItemType Directory -Path $bin -Force | Out-Null }
    Move-Item -LiteralPath $f.FullName -Destination (Join-Path $bin $f.Name) -Force
    $moved++
}
if ($moved -eq 0) { Write-Host 'there was no character on the server to throw away' }
else { Write-Host ("thrown away: {0} change form(s), kept at {1}" -f $moved, $bin) }
'@

if ($UseLocal) {
    Head 'This machine'
    if (-not (Test-Path -LiteralPath $Local)) { Die "no server at $Local" }

    $node = Get-Process -Name node -ErrorAction SilentlyContinue
    if ($node) {
        Say 'stopping the server so its files can be moved' 'Yellow'
        $node | Stop-Process -Force
        Start-Sleep -Seconds 2
    }

    $tmp = Join-Path $env:TEMP 'thornswood-reset.ps1'
    Set-Content -LiteralPath $tmp -Value $body -Encoding UTF8
    & powershell -NoProfile -ExecutionPolicy Bypass -File $tmp -Root $Local
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

    Write-Host ''
    Say 'Done. Press Play and creation runs from the top.' 'Green'
    Say 'The launcher will start the server again for you.' 'DarkGray'
}
else {
    Head "The VPS at $VpsHost"
    foreach ($t in 'ssh', 'scp') {
        if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
            Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client."
        }
    }
    $target = "$VpsUser@$VpsHost"
    # Host key checking on (issue #450): ssh talks only to the box whose key
    # Setup-SshKey.ps1 wrote into known_hosts, checked against vps.json.
    $ssh = @('-o', 'StrictHostKeyChecking=yes')

    $tmp = Join-Path $env:TEMP 'thornswood-reset.ps1'
    Set-Content -LiteralPath $tmp -Value $body -Encoding UTF8

    Invoke-ThornswoodNative { & scp @ssh $tmp "${target}:C:/thornswood-reset.ps1" }
    if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE" }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

    # One ssh session for the whole job, so it is one password rather than three.
    $remote = "powershell -NoProfile -Command `"" +
              "Stop-ScheduledTask -TaskName '$TaskName' -ErrorAction SilentlyContinue; " +
              "Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { \$_.Name -eq 'node.exe' -and \$_.CommandLine -like '*skymp5-server*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -EA SilentlyContinue }; " +
              "Start-Sleep -Seconds 2; " +
              "& powershell -NoProfile -ExecutionPolicy Bypass -File C:\thornswood-reset.ps1 -Root '$VpsRoot'; " +
              "Start-ScheduledTask -TaskName '$TaskName'; " +
              "Start-Sleep -Seconds 3; " +
              "'server restarted'`""
    Invoke-ThornswoodNative { & ssh @ssh $target $remote }
    if ($LASTEXITCODE -ne 0) { Die "the reset on the VPS exited with $LASTEXITCODE" }

    Head 'Checking it came back'
    $up = $false
    for ($i = 0; $i -lt 20; $i++) {
        try {
            $c = New-Object Net.Sockets.TcpClient
            $null = $c.BeginConnect($VpsHost, 3000, $null, $null).AsyncWaitHandle.WaitOne(1000)
            $up = $c.Connected
            $c.Close()
        } catch { }
        if ($up) { break }
        Start-Sleep -Seconds 2
    }

    Write-Host ''
    if ($up) {
        Say 'Done. Press Play and creation runs from the top.' 'Green'
    } else {
        Say "The character was cleared but the server has not come back on ${VpsHost}:3000." 'Red'
        Say "  ssh $target" 'DarkGray'
        Say "  Start-ScheduledTask -TaskName '$TaskName'   (the task runs node High, #2491; node started by hand does not)" 'DarkGray'
    }
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
