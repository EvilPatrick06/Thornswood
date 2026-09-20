<#
  Add-Characters.ps1

  Installs Start On Save into the build.

  Until 20 September this was what turned Play into a character screen: two
  slots, each with its own save folder, and Start On Save walked straight
  into whoever you picked, because Skyrim has no command line that says
  "load this save". The launcher tells the mod to stand still now
  (Chars.WriteStartIni, rewritten on every Play) and you pick your character
  at the game's main menu. The build still ships the mod and Verify checks
  its file, so this is still how the dll gets into a build.

      .\tools\Add-Characters.ps1

  Options:
      -Notes "..."     what the News page says about this release
      -NoShip          install only, publish nothing
#>
[CmdletBinding()]
param(
    # C:\SkyrimTogether until Sep 2026, which stopped existing when that build
    # was removed. Every other script in here already defaulted to the live
    # one, so this was the only script that could not find the game.
    [string]$Root      = 'C:\Thornswood',
    [string]$Downloads = "$env:USERPROFILE\Downloads",
    [string]$Notes = "Start On Save is in the build`n- the launcher tells it to load nothing, and you pick your character at the game's main menu",
    [switch]$NoShip,
    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Close-Launcher.ps1')

$Data = Join-Path $Root 'Game\Data'
if (-not (Test-Path $Data)) { Die "No build at $Data." }

Head 'Making room'
if (Test-GameRunning -Root $Root) { Die 'Skyrim is running. Quit the game first.' }
$null = Stop-Launcher -Root $Root

Head 'Finding the download'
$sos = @(Get-ChildItem -LiteralPath $Downloads -Filter 'Start On Save*' -File -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1)
if (-not $sos.Count) { Die "Could not find a 'Start On Save*' archive in $Downloads." }
Say "  $($sos[0].Name)" 'Green'

$7z = @(
    "$env:ProgramFiles\7-Zip\7z.exe"
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
    "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $7z) { Die '7-Zip is not installed.' }

$work = Join-Path $env:TEMP 'StartOnSave-install'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
$null = New-Item -ItemType Directory -Force -Path $work

Head 'Unpacking'
$old = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try { & $7z x -y "-o$work" $sos[0].FullName | Out-Null; $code = $LASTEXITCODE }
finally { $ErrorActionPreference = $old }
if ($code -gt 1) { Die 'Could not unpack the Start On Save archive.' }

# The archive is a FOMOD with one folder per runtime. AE1170 is this build's
# Skyrim. The plain AE folder is for the older 1.6.640 era and SE is 1.5.97,
# and picking either of those gets a dll that refuses to load.
Head 'Installing'
$dllDir = @(Get-ChildItem -LiteralPath $work -Recurse -Directory -Filter 'AE1170' -ErrorAction SilentlyContinue |
            Select-Object -First 1)
if (-not $dllDir.Count) { Die 'The archive has no AE1170 folder. Did the mod change shape?' }

$dll = Join-Path $dllDir[0].FullName 'SKSE\Plugins\po3_StartOnSave.dll'
if (-not (Test-Path -LiteralPath $dll)) { Die "No po3_StartOnSave.dll under $($dllDir[0].FullName)." }

$dest = Join-Path $Data 'SKSE\Plugins'
$null = New-Item -ItemType Directory -Force -Path $dest
Copy-Item -LiteralPath $dll -Destination (Join-Path $dest 'po3_StartOnSave.dll') -Force
Say '  po3_StartOnSave.dll  (the AE1170 build)' 'Green'

# The ini ships as a starting point only. The launcher rewrites it on every
# Play, so whatever is in it now does not matter much.
$ini = @(Get-ChildItem -LiteralPath $work -Recurse -File -Filter 'po3_StartOnSave.ini' -ErrorAction SilentlyContinue |
         Select-Object -First 1)
if ($ini.Count) {
    Copy-Item -LiteralPath $ini[0].FullName -Destination (Join-Path $dest 'po3_StartOnSave.ini') -Force
    Say '  po3_StartOnSave.ini  (rewritten by the launcher every time you press Play)' 'Green'
}

Head 'Load order'
Say '  untouched, Start On Save ships no plugin' 'DarkGray'

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

Head 'Your existing saves'
# The two slot folders under Profile\Characters went on 20 September. The
# launcher points the Saves folder at Profile\Characters\saves on every Play
# and sets a real Saves folder aside whole; nothing here has to check.
Say '  untouched, the launcher redirects the Saves folder on every Play' 'DarkGray'

if ($NoShip) {
    Head 'Done'
    Say 'Installed. Nothing published, you asked for -NoShip.' 'Green'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

Head 'Handing over to Ship'
& (Join-Path $Here 'Ship.ps1') -Notes $Notes -Root $Root
