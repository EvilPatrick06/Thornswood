<#
  Revert.ps1 - put the game back to the state it was working in.

  Two things went in today that should not have gone in together, and the load
  order one is what broke creation.

  Enabling MCMHelper.esp inserted a plugin into the load order. Every plugin
  after it moves up an index, Thornswood-Content.esp included. The server still
  builds its form ids from its own unchanged order and sends them as numbers, so
  the writs and passages it put in the pack arrived pointing at whatever now
  sits at that index on this machine. Skyrim.esm is index 00 and never moves,
  which is why the shirt and boots turned up and nothing else did.

  The overlay goes too. Not because it is known to be at fault, but because a
  machine that freezes is not a machine to debug three new things on, and the
  overlay is the one holding the browser visible over the game every frame.

  What stays: the server side creation fix (it opens the race menu rather than
  waiting forever), and mod settings on F4 instead of F1. Neither touches the
  load order or the overlay.
#>

[CmdletBinding()]
param(
  [string] $Game = 'C:\Thornswood'
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$G       = Join-Path $Game 'Game'
$ui      = Join-Path $G 'Data\Platform\UI'
$plugins = Join-Path $G 'Data\Platform\Plugins'
$src     = Join-Path $Here 'emotes'

function Head($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }
function Note($t) { Write-Host "  $t" }
function Bad($t)  { Write-Host "  $t" -ForegroundColor Yellow }

# ------------------------------------------------------------- load order --
Head 'Load order'
foreach ($f in @(
  (Join-Path $Game 'Profile\LocalAppData\Plugins.txt'),
  (Join-Path $Game 'Profile\Default\plugins.txt')
)) {
  if (-not (Test-Path -LiteralPath $f)) { continue }
  $lines = [IO.File]::ReadAllLines($f)
  $hit = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq '*MCMHelper.esp') { $lines[$i] = 'MCMHelper.esp'; $hit = $true }
  }
  if ($hit) {
    [IO.File]::WriteAllLines($f, $lines, (New-Object Text.UTF8Encoding($false)))
    Note "MCMHelper.esp disabled again in $(Split-Path -Leaf $f)"
  } else {
    Note "already back in $(Split-Path -Leaf $f)"
  }
}

# ----------------------------------------------------------------- plugins --
Head 'Plugins'
foreach ($n in @('thornswood-front.js', 'thornswood-voice.js', 'thornswood-probe.js')) {
  $p = Join-Path $plugins $n
  if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Note "removed $n" }
}

foreach ($n in @('thornswood-emotes.js')) {
  $s = Join-Path $src $n
  if (Test-Path -LiteralPath $s) {
    Copy-Item -LiteralPath $s -Destination (Join-Path $plugins $n) -Force
    Note "restored $n"
  } else {
    Bad "$n is not in the emotes folder, cannot restore it"
  }
}

# --------------------------------------------------------------------- ui --
Head 'Wheel'
$wheelSrc = Join-Path $src 'thornswood-emotes.html'
if (Test-Path -LiteralPath $wheelSrc) {
  New-Item -ItemType Directory -Force -Path $ui | Out-Null
  Copy-Item -LiteralPath $wheelSrc -Destination (Join-Path $ui 'thornswood-emotes.html') -Force
  Note 'the wheel has its page back'
} else {
  Bad 'thornswood-emotes.html is not in the emotes folder'
}

# The front's own files are left where they are. Nothing loads them now, and
# SkyrimPlatform's default address does not resolve to a real folder, so they
# sit there inert rather than being downloaded again later.
foreach ($n in @('thornswood-emotes.js', 'thornswood-voice.js')) {
  $p = Join-Path $ui $n
  if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force; Note "removed the $n overlay" }
}

# Anything in the plugins folder that is not a plugin makes SkyrimPlatform
# reload every plugin, over and over. That is the black screen with a dead
# keyboard, and it is worth checking every single time.
foreach ($s in (Get-ChildItem -LiteralPath $plugins -File |
                Where-Object { $_.Extension -ne '.js' -and $_.Name -ne 'skymp5-client-settings.txt' })) {
  Bad "removing stray file from the plugins folder: $($s.Name)"
  Remove-Item -LiteralPath $s.FullName -Force
}

Head 'Now'
Note 'Plugins folder holds only:'
Get-ChildItem -LiteralPath $plugins -File | ForEach-Object { Note "    $($_.Name)" }
Note ''
Note 'Start from the launcher and make a new character.'
