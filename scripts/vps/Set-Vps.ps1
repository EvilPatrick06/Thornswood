<#
  Set-Vps.ps1

  Points everything at a different server box.

      .\scripts\vps\Set-Vps.ps1

  It asks for the new address, shows you what it is about to change, and waits
  for a yes before touching anything.

  Why this exists: the address of the box lives in scripts\vps\vps.json, and
  the admin scripts read it through Vps.ps1. The same address is still written
  into 18 other files that genuinely embed it: the launcher source, the
  plugins, the docs, and a few config examples. Changing those by hand is how
  you end up with a website that deploys to a dead box for two days without
  anybody noticing. This script walks the repo (vps.json included) so one
  address change stays one address change.

  It also adds a line to the launcher so that every copy already installed on
  somebody's machine moves itself across the first time it runs. The old
  address becomes a redirect rather than a dead end.

  What it does NOT do, because Set-Server.ps1 already does it properly:
  config.json on this machine, and version.json for everyone else's launcher.
  Run that one after this one. It is printed at the end.

  Reads and rewrites files in the repo only. Nothing is sent anywhere.
#>
[CmdletBinding()]
param(
  [string]$Address,
  [switch]$Preview,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$RepoDir = Split-Path -Parent (Split-Path -Parent $Here)

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) {
  Write-Host ''
  Write-Host "STOP. $m" -ForegroundColor Red
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}

function ReadText($path) {
  $raw = [IO.File]::ReadAllBytes($path)
  $skip = 0
  if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { $skip = 3 }
  return [Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip)
}

function WriteText($path, $text) {
  [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}

Write-Host ''
Write-Host '  THORNSWOOD  -  move to a different box' -ForegroundColor White

# ------------------------------------------------------- what it is now ---
$ConfigCs = Join-Path $Here '..\..\launcher\app\Config.cs'
if (-not (Test-Path -LiteralPath $ConfigCs)) { Die "not found: $ConfigCs" }

$cs = ReadText $ConfigCs
$m = [regex]::Match($cs, 'public\s+string\s+ServerAddress\s*=\s*"([^"]+)"')
if (-not $m.Success) { Die "Could not find the ServerAddress default in app\Config.cs. Nothing has been changed." }
$Old = $m.Groups[1].Value

Say ''
Say "  now       $Old" 'DarkGray'

# ------------------------------------------------------ what it becomes ---
if (-not $Address) {
  Write-Host ''
  $Address = (Read-Host '  New address (the IP of the new box)').Trim()
}
$Address = "$Address".Trim()
if (-not $Address) { Die 'No address given. Nothing has been changed.' }

$looksIp = $false
$parsed = $null
if ([Net.IPAddress]::TryParse($Address, [ref]$parsed)) { $looksIp = $true }
if (-not $looksIp -and $Address -notmatch '^[A-Za-z0-9]([A-Za-z0-9\-\.]*[A-Za-z0-9])?$') {
  Die "That is not an address: $Address"
}
if ($Address -eq $Old) { Die "That is already the address. Nothing has been changed." }

Say "  becomes   $Address" 'Green'

# ------------------------------------------------------------ the files ---
Head 'What carries the old address'

$skipDirs = @('.git', 'node_modules', 'bin', 'obj', '_dist', 'packages')
$hits = @()
$content = @()

foreach ($f in (Get-ChildItem -LiteralPath $RepoDir -Recurse -File -ErrorAction SilentlyContinue)) {
  $rel = $f.FullName.Substring($RepoDir.Length).TrimStart('\', '/')
  $parts = $rel -split '[\\/]'
  $skip = $false
  foreach ($p in $parts) { if ($skipDirs -contains $p) { $skip = $true } }
  if ($skip) { continue }
  if ($f.Length -gt 8MB) { continue }
  if ($f.Extension -notin @('.ps1', '.cs', '.js', '.json', '.html', '.css', '.txt', '.md', '.cmd', '.bat', '.xaml', '.ini', '.py')) { continue }

  $text = ''
  try { $text = ReadText $f.FullName } catch { continue }
  if ($text.IndexOf($Old, [StringComparison]::Ordinal) -lt 0) { continue }

  $n = ([regex]::Matches($text, [regex]::Escape($Old))).Count

  # data\board.json and the like are a record of what was said, not a setting.
  # Rewriting history there would make old messages describe a box that never
  # existed at the time. Those get listed and left alone.
  $isRecord = ($rel -match '(^|[\\/])site[\\/]data[\\/]') -and ($f.Extension -eq '.json')

  if ($isRecord) { $content += [pscustomobject]@{ Rel = $rel; Count = $n } }
  else { $hits += [pscustomobject]@{ Path = $f.FullName; Rel = $rel; Count = $n; Text = $text } }
}

if ($hits.Count -eq 0) { Die "Nothing in the repo carries $Old. Nothing has been changed." }

foreach ($h in ($hits | Sort-Object Rel)) {
  Say ("  {0}  {1}" -f $h.Count.ToString().PadLeft(3), $h.Rel)
}
Say ("  {0} file(s), {1} place(s)" -f $hits.Count, (($hits | Measure-Object -Property Count -Sum).Sum)) 'DarkGray'

if ($content.Count -gt 0) {
  Write-Host ''
  Say '  Left alone, because they are a record of what was said and not a setting:' 'DarkGray'
  foreach ($c in ($content | Sort-Object Rel)) { Say ("    {0}  {1}" -f $c.Count.ToString().PadLeft(3), $c.Rel) 'DarkGray' }
}

if ($Preview) {
  Write-Host ''
  Say 'Preview only. Nothing was changed.' 'Yellow'
  Write-Host ''
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

Write-Host ''
$yes = Read-Host "  Change all of that from $Old to $Address ? (y/n)"
if ("$yes".Trim().ToLower() -ne 'y') { Die 'Left alone, as asked.' }

# ---------------------------------------------------------- do the work ---
Head 'Changing them'

foreach ($h in ($hits | Sort-Object Rel)) {
  $new = $h.Text.Replace($Old, $Address)
  WriteText $h.Path $new
  Say ("  {0}" -f $h.Rel) 'Green'
}

# ------------------------------------------- the redirect for old copies ---
# Every launcher already installed has the old address sitting in its own
# config.json. Most of them will pick the new one up from version.json on the
# next update check. This is for the ones that do not get that far, and for
# anyone who installs an old copy of the installer months from now.
Head 'Old installs'

$cs = ReadText $ConfigCs
$line = '            if (ServerAddress == "' + $Old + '") ServerAddress = "' + $Address + '";'

if ($cs.IndexOf($line, [StringComparison]::Ordinal) -ge 0) {
  Say '  the redirect was already there' 'DarkGray'
}
else {
  $anchor = [regex]::Match($cs, '(?m)^[ \t]*if \(ServerAddress == "[^"]+"\) ServerAddress = "[^"]+";[ \t]*\r?\n')
  if ($anchor.Success) {
    $at = $anchor.Index + $anchor.Length
    $nl = if ($cs.Contains("`r`n")) { "`r`n" } else { "`n" }
    $cs = $cs.Substring(0, $at) + $line + $nl + $cs.Substring($at)
  }
  else {
    $anchor = [regex]::Match($cs, '(?m)^[ \t]*if \(ServerPort == "[^"]+"\) ServerPort = "[^"]+";[ \t]*\r?\n')
    if (-not $anchor.Success) {
      Say '  Could not find where to put it in app\Config.cs.' 'Yellow'
      Say '  Everything else is changed. Old installs will rely on version.json alone,' 'Yellow'
      Say '  which is usually enough. Worth a look when you have a minute.' 'Yellow'
      $anchor = $null
    }
    else {
      $at = $anchor.Index + $anchor.Length
      $nl = if ($cs.Contains("`r`n")) { "`r`n" } else { "`n" }
      $cs = $cs.Substring(0, $at) + $line + $nl + $cs.Substring($at)
    }
  }

  if ($anchor -and $anchor.Success) {
    # The comment above those lines counted them. It is wrong now.
    $cs = $cs.Replace('Only these two exact values are moved:', 'Only these exact values are moved:')
    WriteText $ConfigCs $cs
    Say ("  a launcher still pointed at {0} now moves itself to {1} on its next run" -f $Old, $Address) 'Green'
  }
}

# ------------------------------------------------------------ what next ---
Head 'What is left'
Say '  The repo is pointed at the new box. Three things are not, and they are' 'DarkGray'
Say '  the three that people actually connect through.' 'DarkGray'
Write-Host ''
Say '  1. This machine and everyone else, in one go:' 'White'
# Say has no -NoNewline (a stray one went to $args and split this line in
# two, issue #1086), so the command and its address are one Write-Host pair.
Write-Host '       .\scripts\ops\Set-Server.ps1 -Address ' -NoNewline -ForegroundColor Gray
Write-Host $Address -ForegroundColor Green
Say '     Run it once the new box is up and answering, not before. It checks.' 'DarkGray'
Write-Host ''
Say '  2. A launcher build carrying the new default, so fresh installs are right:' 'White'
Say '       .\scripts\release\Ship.ps1 "Server moved"' 'Gray'
Write-Host ''
Say '  3. The website, which is on the box and has to be put on the new one:' 'White'
Say '       .\scripts\deploy\Deploy-Docs.ps1 -Site' 'Gray'
Write-Host ''
Say '  And the DNS record for thornswood.net has to point at the new address,' 'DarkGray'
Say '  or the site and the Discord sign in both keep going to the old box.' 'DarkGray'

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
