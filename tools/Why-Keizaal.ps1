<#
  Why-Keizaal.ps1

  Reads out why Thornswood's game files ran when Keizaal Online (or any other
  server) was launched from the same Skyrim. Reads only, changes nothing, and
  hides every key, token and password before printing.

      .\tools\Why-Keizaal.ps1
      .\tools\Why-Keizaal.ps1 -NoPause     from another script

  Give the whole output to Gavin. It can be run on any machine that has both
  servers installed: it finds Skyrim through Steam the same way the launcher
  does.

  What it looks at, and why:

    Data\Platform\Plugins     Skyrim Platform loads EVERY .js in here, whichever
                              server the client is about to join. So the
                              question is only what is in the folder.
    skymp5-client-settings    Whichever launcher ran last wrote this. Its
                              server-ip says whose game the client thinks it is
                              joining.
    SkyrimPlatform.ini        Where SP looks for plugins, and which browser
                              backend it uses.
    vortex.deployment.json    Which mod claims which Platform file, and whether
                              Keizaal Online or Daedric Online are deployed
                              into the same Data folder.
    the Keizaal launcher      Where it is installed and what its config points
                              at, with anything secret blanked.
    skse64.log                Which SKSE plugins actually loaded last run.
#>
[CmdletBinding()]
param(
  [string]$GameDir,
  [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function When($f) { '{0:yyyy-MM-dd HH:mm}' -f $f.LastWriteTime }
function KB($b) { '{0,9:n0} KB' -f ($b / 1KB) }

# Anything that looks like a credential is replaced before it is printed.
$secretRx = '(?i)(token|password|passwd|secret|master-key|masterkey|apikey|api_key|\bkey\b|cookie|auth)'
function Mask($obj, $depth = 0) {
  if ($null -eq $obj) { return $null }
  if ($depth -gt 6) { return '...' }
  if ($obj -is [array]) { return @($obj | ForEach-Object { Mask $_ ($depth + 1) }) }
  if ($obj -is [PSCustomObject]) {
    $out = [ordered]@{}
    foreach ($p in $obj.PSObject.Properties) {
      if ($p.Name -match $secretRx) { $out[$p.Name] = '<hidden>' }
      else { $out[$p.Name] = Mask $p.Value ($depth + 1) }
    }
    return $out
  }
  return $obj
}
function ShowJson($path) {
  try {
    $raw = Get-Content -LiteralPath $path -Raw -EA Stop
    if ($raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
    $j = $raw | ConvertFrom-Json -EA Stop
    (Mask $j | ConvertTo-Json -Depth 8) -split "`n" | ForEach-Object { Say "    $_" 'DarkGray' }
  } catch {
    # Not JSON, or half of one. Print it with the secrets blanked line by line.
    Get-Content -LiteralPath $path -EA SilentlyContinue | Select-Object -First 60 | ForEach-Object {
      if ($_ -match $secretRx) { Say ('    ' + ($_ -replace '(?<=[:=]\s*).*$', '<hidden>')) 'DarkGray' } else { Say "    $_" 'DarkGray' }
    }
  }
}

# Where Skyrim is: the registry, then every Steam library, and the one holding
# SkyrimSE.exe wins. Same walk the launcher does.
function Get-SkyrimPath {
  $roots = @()
  foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\Wow6432Node\Valve\Steam')) {
    try { $p = (Get-ItemProperty -Path $k -EA Stop).SteamPath; if ($p) { $roots += ($p -replace '/', '\') } } catch { }
  }
  foreach ($r in @($roots)) {
    $vdf = Join-Path $r 'config\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
      foreach ($line in Get-Content -LiteralPath $vdf) {
        if ($line -match '^\s*"path"\s+"(.+)"\s*$') { $roots += ($Matches[1] -replace '\\\\', '\') }
      }
    }
  }
  foreach ($r in @($roots | Select-Object -Unique)) {
    $g = Join-Path $r 'steamapps\common\Skyrim Special Edition'
    if (Test-Path -LiteralPath (Join-Path $g 'SkyrimSE.exe')) { return $g }
  }
  $g = 'C:\Program Files (x86)\Steam\steamapps\common\Skyrim Special Edition'
  if (Test-Path -LiteralPath (Join-Path $g 'SkyrimSE.exe')) { return $g }
  return $null
}

Write-Host ''
Write-Host '  THORNSWOOD  -  why another server ran our files' -ForegroundColor White
Say ('  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + '  on ' + $env:COMPUTERNAME) 'DarkGray'

if (-not $GameDir) { $GameDir = Get-SkyrimPath }
Head 'Skyrim'
if (-not $GameDir) { Say '  SkyrimSE.exe not found through Steam. Pass -GameDir.' 'Red'; if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 1 }
Say "  $GameDir"
$Data = Join-Path $GameDir 'Data'

# ------------------------------------------------------------ the plugins ---
Head 'Data\Platform\Plugins  (Skyrim Platform loads every .js here, for every server)'
$plug = Join-Path $Data 'Platform\Plugins'
if (-not (Test-Path -LiteralPath $plug)) { Say '  folder missing' 'Yellow' }
else {
  foreach ($f in Get-ChildItem -LiteralPath $plug -File | Sort-Object Name) {
    $who = if ($f.Name -like 'thornswood-*') { 'THORNSWOOD' }
           elseif ($f.Name -like 'skymp5-client*') { 'SkyMP client' }
           else { 'other' }
    Say ('  {0,-14} {1}  {2}  {3}' -f $who, (KB $f.Length), (When $f), $f.Name) $(if ($who -eq 'THORNSWOOD') { 'Green' } elseif ($who -eq 'other') { 'Yellow' } else { 'Gray' })
  }
  $dev = Join-Path $Data 'Platform\PluginsDev'
  if (Test-Path -LiteralPath $dev) {
    Say '  PluginsDev is also loaded:' 'Yellow'
    Get-ChildItem -LiteralPath $dev -File | ForEach-Object { Say ('    {0}  {1}' -f (When $_), $_.Name) 'Yellow' }
  }
}

$ui = Join-Path $Data 'Platform\UI'
if (Test-Path -LiteralPath $ui) {
  Head 'Data\Platform\UI  (the pages the plugins draw, chat and the voice indicator among them)'
  Get-ChildItem -LiteralPath $ui -File | Sort-Object Name | ForEach-Object { Say ('  {0}  {1}  {2}' -f (KB $_.Length), (When $_), $_.Name) }
}

# ------------------------------------------------- whose server it points at --
Head 'skymp5-client-settings.txt  (written by whichever launcher ran last)'
$st = Join-Path $plug 'skymp5-client-settings.txt'
if (Test-Path -LiteralPath $st) {
  Say ('  written ' + (When (Get-Item -LiteralPath $st)))
  try {
    $raw = Get-Content -LiteralPath $st -Raw
    if ($raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
    $j = $raw | ConvertFrom-Json
    $ip = [string]$j.'server-ip'; $port = [string]$j.'server-port'
    $whose = if ($ip -eq '192.135.112.23') { 'THORNSWOOD' } elseif ($ip) { 'ANOTHER SERVER' } else { 'nobody, no server-ip' }
    Say ("  server-ip $ip  port $port  ->  $whose") $(if ($whose -eq 'THORNSWOOD') { 'Green' } else { 'Yellow' })
    Say ('  master ' + [string]$j.master)
    Say ('  keys in the file: ' + (($j.PSObject.Properties | ForEach-Object Name) -join ', ')) 'DarkGray'
    if ($j.keybinds) { Say '  a keybinds block is present, which Keizaal''s client reads and Thornswood''s does not' 'Yellow' }
  } catch { Say "  could not parse it: $_" 'Yellow' }
} else { Say '  missing' 'Yellow' }

# --------------------------------------------------------- SkyrimPlatform ---
Head 'SkyrimPlatform.ini'
$spi = Join-Path $Data 'SKSE\Plugins\SkyrimPlatform.ini'
if (Test-Path -LiteralPath $spi) {
  Get-Content -LiteralPath $spi | Where-Object { $_ -match '^\s*(PluginFolders|BackendName|ChromiumEnabled)\s*=' } | ForEach-Object { Say "  $($_.Trim())" }
  Say ('  written ' + (When (Get-Item -LiteralPath $spi))) 'DarkGray'
} else { Say '  missing' 'Yellow' }
foreach ($n in 'SkyrimPlatform.dll', 'NirnLabUIPlugin.dll', 'DaedricItemUseProbe.dll') {
  $f = Join-Path $Data "SKSE\Plugins\$n"
  if (Test-Path -LiteralPath $f) { $i = Get-Item -LiteralPath $f; Say ('  {0}  {1}  {2}' -f (KB $i.Length), (When $i), $n) }
}

# ----------------------------------------------------------------- Vortex ---
Head 'Vortex  (who deployed what)'
$vd = Join-Path $Data 'vortex.deployment.json'
if (Test-Path -LiteralPath $vd) {
  try {
    $v = Get-Content -LiteralPath $vd -Raw | ConvertFrom-Json
    Say ('  deployed ' + ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$v.deploymentTime).LocalDateTime.ToString('yyyy-MM-dd HH:mm')) + '  ' + $v.files.Count + ' files from ' + $v.stagingPath) 'DarkGray'
    $mods = @{}
    foreach ($f in $v.files) {
      $rp = [string]$f.relPath
      if ($rp -like 'Platform\*' -or $rp -like 'platform\*' -or $rp -like 'SKSE\Plugins\SkyrimPlatform*' -or $rp -like 'SKSE\Plugins\NirnLab*' -or $rp -like 'NirnLabUIPlatform\*') {
        if (-not $mods.ContainsKey($f.source)) { $mods[$f.source] = New-Object System.Collections.ArrayList }
        [void]$mods[$f.source].Add($rp)
      }
    }
    if ($mods.Count) {
      Say '  mods providing Platform, Skyrim Platform or NirnLab files:'
      foreach ($k in ($mods.Keys | Sort-Object)) {
        Say ('    {0}  ({1} files)' -f $k, $mods[$k].Count) 'Gray'
        $mods[$k] | Select-Object -First 6 | ForEach-Object { Say "      $_" 'DarkGray' }
        if ($mods[$k].Count -gt 6) { Say '      ...' 'DarkGray' }
      }
    } else { Say '  no mod provides Platform files, so everything in Data\Platform is loose' }
    $others = @($v.files | Where-Object { $_.source -match '(?i)keizaal|daedric' } | ForEach-Object { $_.source } | Select-Object -Unique)
    if ($others.Count) { Say '  OTHER SERVERS DEPLOYED INTO THIS DATA FOLDER:' 'Yellow'; $others | ForEach-Object { Say "    $_" 'Yellow' } }
    else { Say '  no Keizaal or Daedric mod is deployed by Vortex right now' 'Green' }
  } catch { Say "  could not read it: $_" 'Yellow' }
} else { Say '  no vortex.deployment.json, this Skyrim is not managed by Vortex' 'Yellow' }

$staging = Join-Path $env:APPDATA 'Vortex\skyrimse\mods'
if (Test-Path -LiteralPath $staging) {
  $st2 = @(Get-ChildItem -LiteralPath $staging -Directory | Where-Object { $_.Name -match '(?i)keizaal|daedric' })
  if ($st2.Count) { Say '  in Vortex staging (installed, deployed or not):'; $st2 | ForEach-Object { Say "    $($_.Name)" } }
}

# ------------------------------------------------------- the other launcher --
Head 'Keizaal Online launcher (skyrim-rp-launcher)'
$kl = Join-Path $env:LOCALAPPDATA 'Programs\skyrim-rp-launcher'
if (Test-Path -LiteralPath $kl) {
  Say "  installed at $kl"
  Get-ChildItem -LiteralPath $kl -File -Filter *.exe | ForEach-Object {
    $ver = try { (Get-Item -LiteralPath $_.FullName).VersionInfo.ProductVersion } catch { '' }
    Say ('    {0}  {1}  {2}' -f (When $_), $_.Name, $ver)
  }
} else { Say '  not installed on this machine' }
$kc = Join-Path $env:APPDATA 'skyrim-rp-launcher'
if (Test-Path -LiteralPath $kc) {
  Say "  config at $kc"
  foreach ($f in Get-ChildItem -LiteralPath $kc -File | Where-Object { $_.Extension -in '.json', '.txt', '.ini', '.cfg' } | Sort-Object Name) {
    Say ('  {0}  {1}  {2}' -f (KB $f.Length), (When $f), $f.Name)
    if ($f.Length -lt 20KB) { ShowJson $f.FullName }
  }
  $logs = @(Get-ChildItem -LiteralPath $kc -Recurse -File -Filter *.log -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  if ($logs.Count) {
    Say ('  newest log ' + $logs[0].FullName) 'DarkGray'
    Get-Content -LiteralPath $logs[0].FullName -Tail 25 -EA SilentlyContinue | ForEach-Object {
      if ($_ -match $secretRx) { Say ('    ' + ($_ -replace '(?<=[:=]\s*)\S+', '<hidden>')) 'DarkGray' } else { Say "    $_" 'DarkGray' }
    }
  }
} else { Say '  no config folder, it has never run here' }

# -------------------------------------------------------------- Thornswood --
Head 'Thornswood launcher'
$launcherRoots = @("$env:LOCALAPPDATA\Thornswood")
foreach ($d in @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' })) {
  foreach ($n in 'Thornswood', 'Thornswood-DevBuild') {
    $cand = Join-Path $d.Root $n
    if (Test-Path -LiteralPath (Join-Path $cand 'Launcher\Thornswood.exe')) { $launcherRoots = @($cand) + $launcherRoots }
  }
}
foreach ($root in $launcherRoots) {
  $p = Join-Path $root 'Profile\installed-into-game.txt'
  if (Test-Path -LiteralPath $p) {
    $n = @(Get-Content -LiteralPath $p | Where-Object { $_.Trim() }).Count
    Say "  $root  put $n files into the game folder over time (Profile\installed-into-game.txt)"
    Get-Content -LiteralPath $p | Where-Object { $_ -like '*Platform*' } | ForEach-Object { Say "    $_" 'DarkGray' }
  }
  $lg = Join-Path $root 'Profile\launcher.log'
  if (Test-Path -LiteralPath $lg) {
    Say "  last lines of $lg" 'DarkGray'
    Get-Content -LiteralPath $lg -Tail 8 -EA SilentlyContinue | ForEach-Object { Say "    $_" 'DarkGray' }
  }
}

# ------------------------------------------------------------------ SKSE ----
Head 'skse64.log  (what actually loaded last run)'
$docs = [Environment]::GetFolderPath('MyDocuments')
$logs = @()
foreach ($d in @((Join-Path $docs 'My Games\Skyrim Special Edition\SKSE'), (Join-Path $env:USERPROFILE 'OneDrive\Documents\My Games\Skyrim Special Edition\SKSE'))) {
  $f = Join-Path $d 'skse64.log'
  if (Test-Path -LiteralPath $f) { $logs += Get-Item -LiteralPath $f }
}
if ($logs.Count) {
  $l = $logs | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  Say ('  ' + $l.FullName + '  written ' + (When $l)) 'DarkGray'
  Get-Content -LiteralPath $l.FullName | Where-Object { $_ -match '(?i)skyrimplatform|nirnlab|daedric|couldn.t load|disabled|error' } | Select-Object -First 25 | ForEach-Object { Say "  $_" }
} else { Say '  no skse64.log found' 'Yellow' }

Head 'What this adds up to'
Say '  Skyrim Platform reads PluginFolders out of SkyrimPlatform.ini and runs every .js it finds there.'
Say '  It does not know or care which server skymp5-client is about to join. Thornswood''s plugins sit'
Say '  in that folder, so a Keizaal launch runs them too, and the voice indicator you saw is ours.'
Say '  The fix is in the plugins: from 1.1.33 they read server-ip out of skymp5-client-settings.txt'
Say '  and do nothing at all when it is not 192.135.112.23.'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
