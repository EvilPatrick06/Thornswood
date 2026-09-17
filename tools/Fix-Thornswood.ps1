<#
  Fix-Thornswood.ps1

  For somebody whose launcher is stuck: Skyrim will not close, the launcher
  will not update, or another server's main menu comes up instead of Skyrim's.

    1. Closes Skyrim and the launcher, by force.
    2. Lists what is actually in the game's script extender and interface
       folders, so the exact file names can be read rather than guessed at.
    3. Removes anything belonging to another server, matched by name.
    4. Updates Thornswood.exe itself, checked against the published hash.

  Run it in PowerShell as Administrator. Nothing in it needs editing.
  Send the whole output back if the menu is still wrong afterwards.
#>

$ErrorActionPreference = 'Continue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

Write-Host ''
Write-Host '  THORNSWOOD  -  unstick' -ForegroundColor White

# ------------------------------------------------------------------ 1. kill
Head 'Closing Skyrim and the launcher'
$names = 'SkyrimSE','skse64_loader','SkyrimSELauncher','Thornswood','SkyrimTogether'
$killed = 0
foreach ($n in $names) {
  foreach ($p in @(Get-Process $n -ErrorAction SilentlyContinue)) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $killed++; Say "  closed $n (pid $($p.Id))" }
    catch { Say "  could NOT close $n (pid $($p.Id)): $($_.Exception.Message)" 'Red' }
  }
}
if ($killed -eq 0) { Say '  nothing was running' 'DarkGray' }
Start-Sleep -Seconds 2
$still = @(); foreach ($n in $names) { $still += @(Get-Process $n -ErrorAction SilentlyContinue) }
if ($still.Count -gt 0) {
  Say ''; Say '  Some of it will not close. Restart the PC, then run this again first thing.' 'Red'
  Read-Host 'Enter to close'; exit 1
}

# ------------------------------------------------------------ find the game
Head 'Finding Skyrim'
$paths = @()
foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Bethesda Softworks\Skyrim Special Edition',
               'HKLM:\SOFTWARE\Bethesda Softworks\Skyrim Special Edition') {
  try { $v = (Get-ItemProperty $k -ErrorAction Stop).'Installed Path'; if ($v) { $paths += $v } } catch { }
}
foreach ($vdf in @("${env:ProgramFiles(x86)}\Steam\steamapps\libraryfolders.vdf",
                   "$env:ProgramFiles\Steam\steamapps\libraryfolders.vdf")) {
  if (Test-Path $vdf) {
    foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
      $p = Join-Path ($m.Groups[1].Value -replace '\\\\','\') 'steamapps\common\Skyrim Special Edition'
      if (Test-Path $p) { $paths += $p }
    }
  }
}
$game = $paths | Where-Object { Test-Path (Join-Path $_ 'SkyrimSE.exe') } | Select-Object -First 1
if (-not $game) {
  Say '  Could not find Skyrim. In Steam: right click Skyrim Special Edition, Manage, Browse local files.' 'Red'
  Read-Host 'Enter to close'; exit 1
}
Say "  $game" 'Green'
$data = Join-Path $game 'Data'

# ------------------------------------------------------------- 2. what is there
# Printed in full rather than searched for a list of names somebody guessed,
# which is how the last two attempts at this missed the actual file.
Head 'Script extender plugins that are installed'
$skse = Join-Path $data 'SKSE\Plugins'
if (Test-Path $skse) {
  Get-ChildItem $skse -File -EA SilentlyContinue |
    Where-Object { $_.Extension -in '.dll','.json','.ini','.toml' } |
    Sort-Object Name | ForEach-Object { Say ("  {0,-46} {1,8:N0} KB" -f $_.Name, ($_.Length/1KB)) }
  Get-ChildItem $skse -Directory -EA SilentlyContinue | Sort-Object Name | ForEach-Object { Say ("  {0,-46} <folder>" -f $_.Name) }
} else { Say '  no SKSE\Plugins folder' 'Yellow' }

Head 'Interface folder, which is what draws the main menu'
$iface = Join-Path $data 'Interface'
if (Test-Path $iface) {
  Get-ChildItem $iface -File -EA SilentlyContinue | Sort-Object Name |
    ForEach-Object { Say ("  {0,-46} {1,8:N0} KB" -f $_.Name, ($_.Length/1KB)) }
  Get-ChildItem $iface -Directory -EA SilentlyContinue | Sort-Object Name | ForEach-Object { Say ("  {0,-46} <folder>" -f $_.Name) }
} else { Say '  no Interface folder' 'DarkGray' }

Head 'Anything named after another server, anywhere in Data'
$words = 'daedric','nirnlab','nirn lab','keizaal','kzl'
$hits = @()
foreach ($item in Get-ChildItem $data -Recurse -Depth 3 -EA SilentlyContinue) {
  foreach ($w in $words) {
    if ($item.Name -like "*$w*") { $hits += $item; break }
  }
}
if ($hits.Count -eq 0) { Say '  nothing matched' 'DarkGray' }
else { foreach ($h in $hits) { Say ("  {0}" -f $h.FullName.Substring($data.Length + 1)) 'Yellow' } }

# --------------------------------------------------------------- 3. remove
Head 'Removing them'
$gone = 0
foreach ($h in ($hits | Sort-Object { $_.FullName.Length } -Descending)) {
  try {
    if ($h.PSIsContainer) { Remove-Item $h.FullName -Recurse -Force -EA Stop }
    else { Remove-Item $h.FullName -Force -EA Stop }
    Say ("  removed {0}" -f $h.Name) 'Green'; $gone++
  } catch { Say ("  could not remove {0}: {1}" -f $h.Name, $_.Exception.Message) 'Red' }
}
if ($gone -eq 0) { Say '  nothing to remove' 'DarkGray' }

# ---------------------------------------------------------- 4. the launcher
Head 'Updating Thornswood'
$exe = $null
foreach ($d in [IO.DriveInfo]::GetDrives()) {
  if ($d.DriveType -ne 'Fixed' -or -not $d.IsReady) { continue }
  $try = Join-Path $d.RootDirectory.FullName 'Thornswood\Launcher\Thornswood.exe'
  if (Test-Path $try) { $exe = $try; break }
}
if (-not $exe) { Say '  Could not find Thornswood.exe.' 'Yellow'; Read-Host 'Enter to close'; exit 1 }
$have = (Get-Item $exe).VersionInfo.FileVersion
Say "  installed: $have  ($exe)" 'DarkGray'
try {
  $v = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/EvilPatrick06/Thornswood-Releases/main/version.json' -UseBasicParsing -TimeoutSec 30
} catch { Say "  could not reach the update: $($_.Exception.Message)" 'Red'; Read-Host 'Enter to close'; exit 1 }
Say "  published: $($v.launcherVersion)" 'DarkGray'

if ($v.launcherVersion -eq $have) { Say '  already current' 'Green' }
elseif (-not $v.launcherUrl) { Say '  no launcher on the release' 'Yellow' }
else {
  $tmp = Join-Path $env:TEMP 'Thornswood-new.exe'
  if (Test-Path $tmp) { Remove-Item $tmp -Force -EA SilentlyContinue }
  Say '  downloading...' 'DarkGray'
  try {
    Invoke-WebRequest -Uri $v.launcherUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 180 `
      -Headers @{ 'Accept' = 'application/octet-stream'; 'User-Agent' = 'Thornswood-Unstick' }
  } catch { Say "  download failed: $($_.Exception.Message)" 'Red'; Read-Host 'Enter to close'; exit 1 }

  # Never overwrite somebody's launcher with bytes that were not checked.
  $sha = (Get-FileHash $tmp -Algorithm SHA256).Hash
  if ($v.launcherSha256 -and $sha -ne $v.launcherSha256.ToUpper()) {
    Say '  the download did not match the published hash, nothing was replaced' 'Red'
    Remove-Item $tmp -Force -EA SilentlyContinue; Read-Host 'Enter to close'; exit 1
  }
  $old = "$exe.old"
  try {
    if (Test-Path $old) { Remove-Item $old -Force -EA SilentlyContinue }
    Move-Item $exe $old -Force; Move-Item $tmp $exe -Force
    Remove-Item $old -Force -EA SilentlyContinue
    Say "  updated to $($v.launcherVersion)" 'Green'
  } catch {
    Say "  could not replace the launcher: $($_.Exception.Message)" 'Red'
    if ((Test-Path $old) -and -not (Test-Path $exe)) { Move-Item $old $exe -Force }
    Read-Host 'Enter to close'; exit 1
  }
}

Head 'Done'
Say '  If the wrong main menu still comes up, send this whole window back.' 'Yellow'
Say '  Opening Thornswood.' 'Green'
try { Start-Process $exe } catch { Say "  Open it yourself: $exe" 'Yellow' }
Write-Host ''
Read-Host 'Enter to close'
