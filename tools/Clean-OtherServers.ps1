<#
  Clean-OtherServers.ps1

  Removes what belongs to the other roleplay servers and what Thornswood
  stopped using, out of the Vortex staging folder and out of the Steam Data
  folder.

      .\tools\Clean-OtherServers.ps1         show what it would remove
      .\tools\Clean-OtherServers.ps1 -Go     actually remove it

  Nothing goes until -Go, and even then it asks. What it prints is exactly
  what it removes: no wildcards over mod names, no guessing from what a
  folder is called.

  Three jobs, and they are separate for a reason.

  STAGING. Vortex keeps every mod it has ever installed under
  AppData\Roaming\Vortex\skyrimse\mods, whether a profile uses it or not.
  The ones named below are Daedric Online's, Keizaal's, or mods Thornswood
  took out in 1.1. They are named one by one rather than worked out, because
  "not deployed right now" also describes SKSE, Nemesis and BodySlide, and a
  script that deleted those would be a very bad afternoon.

  DATA. Plugins and archives sitting loose in the Steam Data folder that
  Vortex did not put there and does not manage. Those came from installing
  the other servers by hand. This one IS worked out rather than listed:
  anything in Data that vortex.deployment.json does not claim, that is not
  vanilla or a DLC, is a leftover. It never touches a folder, only files in
  the root of Data.

  BACKUPS. Vortex writes a .vortex_backup beside any file it had to
  overwrite, so it can put yours back when you purge. Those are copies of
  files that were loose in Data before, which is the same mess as above, and
  on this machine they are several gigabytes of it.

  Close Vortex and the game first. A file either of them has open will not
  delete, and this says so rather than pretending.
#>
[CmdletBinding()]
param(
  [switch]$Go,
  [switch]$Staging,
  [switch]$Data,
  [switch]$Backups,
  # Walk the whole Data tree and report every loose asset Vortex does not
  # claim. Reports only, never removes, because this one is a judgement call.
  [switch]$Assets,
  [string]$Vortex = "$env:APPDATA\Vortex\skyrimse\mods",
  [string]$GameData,
  [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function MB($b) { '{0,10:n1} MB' -f ($b / 1MB) }

# With none of the three switches, all three.
if (-not ($Staging -or $Data -or $Backups -or $Assets)) { $Staging = $true; $Data = $true; $Backups = $true }

# Where Skyrim is. The same walk the launcher does: the registry, then every
# library in libraryfolders.vdf, and the one holding SkyrimSE.exe wins.
function Get-SkyrimPath {
  $roots = @()
  foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\Wow6432Node\Valve\Steam')) {
    try {
      $p = (Get-ItemProperty -Path $k -EA Stop).SteamPath
      if ($p) { $roots += ($p -replace '/', '\') }
    } catch { }
  }
  foreach ($r in @($roots)) {
    $vdf = Join-Path $r 'config\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
      foreach ($line in Get-Content -LiteralPath $vdf) {
        if ($line -match '^\s*"path"\s+"(.+)"\s*$') { $roots += ($Matches[1] -replace '\\\\', '\') }
      }
    }
  }
  foreach ($r in $roots) {
    $g = Join-Path $r 'steamapps\common\Skyrim Special Edition'
    if (Test-Path -LiteralPath (Join-Path $g 'SkyrimSE.exe')) { return $g }
  }
  return ''
}

if (-not $GameData) {
  $g = Get-SkyrimPath
  if ($g) { $GameData = Join-Path $g 'Data' }
}

# --------------------------------------------------------------- staging ---
#
# Named one at a time. Every name here is either another server's content or
# something 1.1 took out, and the reason is next to it so the next person
# reading this does not have to take my word for it.
$stagingNames = @(
  # Daedric Online and Keizaal Online. Not ours, never were.
  'Daedric-Online-768397-22-1787432247'
  'Keizaal-Online-755596-7-1786042685'
  'KzlOnlineContent 186633 1 2026-07-27T13-24Z 4t2yDcbtH'
  'Nirn Necessities - SMP Accessories-112481-1-03-1731887957+Daedric Online.1'
  'Sentinel - An Equipment Overhaul-100985-3-2-0-1740901216+Daedric Online.1'

  # Superseded by JK's Skyrim all in one. 155 of 155 and 138 of 143 of their
  # edits are already in it, which is why they came out.
  "JK's Riverwood V1.3d - SSE-2013-1-3d"
  "JK's Whiterun V1.4b - SSE-2259-1-4b"

  # Doing a job we are building ourselves.
  'Missives 2.03 SSE-17576-2-03-1562185360'
  'The Notice Board-3218-1-4'

  # Removed outright.
  'Survival Control Panel-41891-1-1-2-1664687771'
  'B. Whiterun Expansion 1.3 Exterior Compatibility Version-37982-1-3-1598121752'

  # The Great Cities and Cities of the North. 413 records shared with JK's,
  # 82 of them navmeshes, and the patch that fixes it needs Creation Club
  # content that cannot be shipped. The whole branch is closed.
  'The Great Cities 2.01-20272-2-01-1551532639'
  'The Great Cities - Resources 2k-104373-1-1-1734084651'
  "The Great Cities of JK's North v6-33687-6-01-1732373746"
  'The Great City of Dawnstar SSE-19491-2-12-1674666614'
  'The Great City of Dragon Bridge 1.12-19962-1-12-1539428884'
  'The Great City of Falkreath-19709-1-22-1679571743'
  'The Great City of Morthal-19592-1-11'
  'The Great City of Rorikstead 1.2-20151-1-2-1551470732'
  'The Great City of Winterhold-17127-4-2-3-1736080766'
  'The Great City of Winterhold Patch Collection-74560-2-10-1761247389'
  'Cities of the North - Falkreath Patch-56731-1-3-1681414570'
  'Cities of the North - Morthal-34168-1-2-1700483274'
  'Cities of the North - Winterhold-40088-1-1-1602459318'
  'COTN Dawnstar Patch Collection-30885-5-9-1771973931'
  'COTN Falkreath Patch Collection-56734-1-29-1768260027'
  'COTN Morthal Patch Collection-34228-3-7-1771708887'
  'COTN Winterhold - Castle Interior Enhanced (ESP version)-75774-2-1-1663966145'

  # The hand made copy of our own content plugin. The Nexus one replaced it,
  # and having both is how the wrong one ends up deployed.
  'Thornswood-Content'

  # Older copies of things that have a newer one installed beside them.
  'CrashLogger-59818-1-20-1-1770787893'
  'MCM Helper-53000-1-6-1-1775573523'
  "powerofthree's Tweaks-51073-1-1-5-1-1756670335"
  'SkyPatcher - AE-106659-6-3-3-1775303895'
)

# -------------------------------------------------------- what is vanilla ---
$vanilla = @(
  'skyrim.esm', 'update.esm', 'dawnguard.esm', 'hearthfires.esm', 'dragonborn.esm',
  '_resourcepack.esl', '_resourcepack.bsa', 'marketplacetextures.bsa'
)

# ------------------------------------------------- what is actually loaded ---
#
# The guard that was missing the first time this ran, and it nearly cost three
# plugins.
#
# "Vortex did not put this here" and "nothing needs this" are not the same
# sentence. TrueHUD, True Directional Movement and Precision were installed by
# hand long before Vortex was managing anything, so they sit in Data unmanaged
# while being switched on in the load order the server checks against. A pass
# that only asked the deployment manifest would have taken all three.
#
# So the live plugin list gets the final say. Anything switched on in it stays,
# whoever put it there, and it is named on the way past so it is obvious that
# something is being kept rather than missed.
function Get-EnabledPlugins($dataDir) {
  $out = @{}
  $files = @(
    (Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition\Plugins.txt')
    (Join-Path $env:LOCALAPPDATA 'Skyrim Special Edition GOG\Plugins.txt')
  )
  foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    foreach ($line in Get-Content -LiteralPath $f -EA SilentlyContinue) {
      $t = $line.Trim()
      if ($t.StartsWith('*') -and $t.Length -gt 1) { $out[$t.Substring(1).ToLowerInvariant()] = $true }
    }
  }
  return $out
}

# A bsa is loaded by the plugin it is named after, so Foo.bsa and
# Foo - Textures.bsa both belong to Foo.esp and go when it goes, not before.
function Is-Needed($name, $enabled) {
  $low = $name.ToLowerInvariant()
  if ($enabled.ContainsKey($low)) { return $true }
  if ([IO.Path]::GetExtension($low) -ne '.bsa') { return $false }
  $base = [IO.Path]::GetFileNameWithoutExtension($low)
  $bases = @($base)
  if ($base -match '^(.*) - [a-z0-9]+$') { $bases += $Matches[1] }
  foreach ($b in $bases) {
    foreach ($e in @('.esp', '.esm', '.esl')) {
      if ($enabled.ContainsKey($b + $e)) { return $true }
    }
  }
  return $false
}

$targets = @()   # @{ Path; Why; Bytes }

function Size($p) {
  try {
    if (Test-Path -LiteralPath $p -PathType Leaf) { return (Get-Item -LiteralPath $p).Length }
    return (Get-ChildItem -LiteralPath $p -Recurse -File -EA SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
  } catch { return 0 }
}

if ($Staging) {
  Head 'Vortex staging'
  if (-not (Test-Path -LiteralPath $Vortex)) {
    Say "  not found: $Vortex" 'Yellow'
  } else {
    foreach ($n in $stagingNames) {
      $p = Join-Path $Vortex $n
      if (Test-Path -LiteralPath $p) {
        $b = Size $p
        $targets += @{ Path = $p; Why = 'staging'; Bytes = $b }
        Say ("  {0}  {1}" -f (MB $b), $n)
      }
    }
    if (-not ($targets | Where-Object { $_.Why -eq 'staging' })) { Say '  nothing to remove' 'DarkGray' }
  }
}

if (($Data -or $Backups) -and -not $GameData) {
  Say ''
  Say '  Could not find the Steam copy of Skyrim, so the Data folder was skipped.' 'Yellow'
  Say '  Pass -GameData with the path to its Data folder to do that part.' 'Yellow'
}

if ($GameData -and (Test-Path -LiteralPath $GameData)) {

  # What Vortex says it put there. Without this file nothing in Data is
  # touched, because then there is no way to tell a managed file from a
  # leftover and guessing is how somebody loses their build.
  $managed = @{}
  $manifest = Join-Path $GameData 'vortex.deployment.json'
  $haveManifest = $false
  if (Test-Path -LiteralPath $manifest) {
    try {
      $doc = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
      foreach ($f in $doc.files) { $managed[$f.relPath.ToLowerInvariant()] = $true }
      $haveManifest = $true
    } catch {
      Say "  vortex.deployment.json could not be read: $($_.Exception.Message)" 'Red'
    }
  }

  if ($Data) {
    Head 'Loose in the Steam Data folder'
    if (-not $haveManifest) {
      Say '  No readable vortex.deployment.json, so nothing here is touched.' 'Yellow'
      Say '  Deploy once in Vortex and run this again.' 'Yellow'
    } else {
      $enabled = Get-EnabledPlugins $GameData
      if ($enabled.Count -eq 0) {
        Say '  No Plugins.txt could be read, so nothing in Data is touched.' 'Yellow'
        Say '  Without it there is no way to tell a leftover from a plugin the' 'Yellow'
        Say '  build is using. Start the game or Vortex once and run this again.' 'Yellow'
      } else {
        $kept = @()
        foreach ($f in Get-ChildItem -LiteralPath $GameData -File -EA SilentlyContinue) {
          $ext = $f.Extension.ToLowerInvariant()
          if ($ext -notin @('.esp', '.esm', '.esl', '.bsa')) { continue }
          $low = $f.Name.ToLowerInvariant()
          if ($vanilla -contains $low) { continue }
          if ($low -like 'skyrim - *.bsa') { continue }
          if ($managed.ContainsKey($low)) { continue }
          if (Is-Needed $f.Name $enabled) { $kept += $f.Name; continue }
          $targets += @{ Path = $f.FullName; Why = 'data'; Bytes = $f.Length }
          Say ("  {0}  {1}" -f (MB $f.Length), $f.Name)
        }
        if (-not ($targets | Where-Object { $_.Why -eq 'data' })) { Say '  nothing to remove' 'DarkGray' }
        if ($kept.Count -gt 0) {
          Write-Host ''
          Say '  Kept, because they are switched on in the load order even though' 'Cyan'
          Say '  Vortex is not managing them. These belong in the collection:' 'Cyan'
          foreach ($k in $kept) { Say "    $k" 'Cyan' }
        }
      }
    }
  }

  # ------------------------------------------- other servers' skse plugins ---
  #
  # The first pass only walked the root of Data, so script extender plugins
  # belonging to the other servers sat one folder down and survived it. They
  # are DLLs rather than plugins, so nothing in the load order names them and
  # nothing warns about them. They just load.
  if ($Data) {
    Head "Other servers' script extender plugins"
    $skse = Join-Path $GameData 'SKSE\Plugins'
    $foreign = @(
      'DaedricItemUseProbe.dll'       # Daedric Online
      'DaedricItemUseProbe.json'
      'DaedricItemUseProbe.NOTICES.txt'
      'NirnLabUIPlugin.dll'           # Keizaal Online's UI platform
    )
    $n = 0
    foreach ($name in $foreign) {
      $p = Join-Path $skse $name
      if (Test-Path -LiteralPath $p -PathType Leaf) {
        $len = (Get-Item -LiteralPath $p).Length
        $targets += @{ Path = $p; Why = 'skse'; Bytes = $len }
        Say ("  {0}  {1}" -f (MB $len), $name)
        $n++
      }
    }
    if ($n -eq 0) { Say '  nothing to remove' 'DarkGray' }
  }

  if ($Backups) {
    Head 'Vortex backups of files that were already loose'
    $n = 0
    foreach ($f in Get-ChildItem -LiteralPath $GameData -File -Filter '*.vortex_backup' -EA SilentlyContinue) {
      $targets += @{ Path = $f.FullName; Why = 'backup'; Bytes = $f.Length }
      $n++
      if ($f.Length -gt 20MB) { Say ("  {0}  {1}" -f (MB $f.Length), $f.Name) }
    }
    if ($n -eq 0) { Say '  nothing to remove' 'DarkGray' }
    else { Say ("  {0} files in total, the ones over 20 MB are listed above" -f $n) 'DarkGray' }
  }
}

# ----------------------------------------------------- loose assets report ---
#
# Why this exists: the 1.1 installer was built out of the Steam copy and came
# out at 1.6 GB when it should have been a launcher and our own content. Files
# in the root of Data are easy to see. Whole trees of meshes, textures, sounds
# and scripts that another server's installer dropped in by hand are not, and
# neither the vanilla list nor Vortex's manifest names them, so the packager
# swept them all up as though they were ours.
#
# This reports and removes nothing. What it finds is other people's work sitting
# in a folder Vortex now owns, and deciding what to do about it is not something
# a script should guess at.
if ($Assets -and $GameData -and (Test-Path -LiteralPath $GameData)) {
  Head 'Loose assets Vortex does not claim'

  $manifest = Join-Path $GameData 'vortex.deployment.json'
  if (-not (Test-Path -LiteralPath $manifest)) {
    Say '  No vortex.deployment.json, so there is nothing to compare against.' 'Yellow'
  } else {
    $claimed = @{}
    try {
      $doc = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
      foreach ($f in $doc.files) { $claimed[$f.relPath.ToLowerInvariant()] = $true }
    } catch {
      Say "  could not read the manifest: $($_.Exception.Message)" 'Red'
    }

    # Ours, and Bethesda's. Everything else under Data is the question.
    $mine = @('platform', 'skse', 'bashtags', 'seq', 'shadercache', 'dialogueviews')
    $vanillaTop = @('video', 'strings')

    $groups = @{}
    $total = 0; $count = 0
    foreach ($f in Get-ChildItem -LiteralPath $GameData -Recurse -File -Force -EA SilentlyContinue) {
      $rel = $f.FullName.Substring($GameData.TrimEnd('\').Length + 1)
      $low = $rel.ToLowerInvariant()
      if ($claimed.ContainsKey($low)) { continue }
      $top = ($rel -split '\\')[0]
      $topLow = $top.ToLowerInvariant()
      if ($rel -eq $top) { continue }                       # root of Data, other passes cover it
      if ($mine -contains $topLow) { continue }
      if ($vanillaTop -contains $topLow) { continue }
      if ($f.Extension -in '.pdb', '.log') { continue }
      if (-not $groups.ContainsKey($top)) { $groups[$top] = @{ Bytes = 0; Count = 0 } }
      $groups[$top].Bytes += $f.Length
      $groups[$top].Count++
      $total += $f.Length; $count++
    }

    # Named, so they can go. Everything else in this report is a folder the
    # game itself reads, and a loose file in meshes or textures is as likely to
    # be a BodySlide build of your own body meshes as it is somebody else's
    # leftovers. Those need looking at rather than deleting, so this only ever
    # offers the ones there is no question about.
    #
    # NirnLabUIPlatform is another roleplay server's interface framework.
    # Nothing in the 96 plugins this game loads asks for it.
    $namedForeign = @('NirnLabUIPlatform')

    if ($count -eq 0) {
      Say '  nothing, the Data tree is all Vortex or vanilla' 'Green'
    } else {
      foreach ($k in ($groups.Keys | Sort-Object { -$groups[$_].Bytes })) {
        $mark = ''
        if ($namedForeign -contains $k) { $mark = '   <- not ours, can go' }
        Say ("  {0}  {1,6:n0} files   {2}{3}" -f (MB $groups[$k].Bytes), $groups[$k].Count, $k, $mark)
      }
      Write-Host ''
      Say ("  {0:n0} files, {1:n2} GB that Vortex did not put there." -f $count, ($total / 1GB)) 'Yellow'
      Say '  The installer no longer ships any of it either way: Package-Thornswood' 'DarkGray'
      Say '  leaves out the frameworks and tool folders whatever is on this machine.' 'DarkGray'

      foreach ($k in $namedForeign) {
        if (-not $groups.ContainsKey($k)) { continue }
        $path = Join-Path $GameData $k
        if (-not (Test-Path -LiteralPath $path)) { continue }
        # Same shape as every other pass puts in, so the removal loop and the
        # total at the bottom do not have to know where a target came from.
        $targets += @{ Path = $path; Why = 'assets'; Bytes = $groups[$k].Bytes }
        Say "  offering $k for removal" 'Yellow'
      }

      Write-Host ''
      Say '  meshes and textures are NOT offered. Loose files in there are as' 'Cyan'
      Say '  likely to be your own BodySlide builds as somebody else''s leftovers,' 'Cyan'
      Say '  and one of those two is not replaceable by reinstalling anything.' 'Cyan'
    }
  }
}

# ------------------------------------------------------------------ total ---
$total = ($targets | Measure-Object -Property Bytes -Sum).Sum
Head 'Total'
Say ("  {0} things, {1:n2} GB" -f $targets.Count, ($total / 1GB)) 'Green'

if ($targets.Count -eq 0) {
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  return
}

if (-not $Go) {
  Write-Host ''
  Say '  Nothing has been removed. Run it again with -Go to actually do it.' 'Yellow'
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  return
}

Write-Host ''
Say '  This is permanent. There is no recycle bin step.' 'Red'
$a = Read-Host '  Type DELETE to go ahead'
if ($a -ne 'DELETE') { Say '  stopped, nothing was removed'; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; return }

Head 'Removing'
$gone = 0; $freed = 0; $stuck = @()
foreach ($t in $targets) {
  try {
    Remove-Item -LiteralPath $t.Path -Recurse -Force -EA Stop
    $gone++; $freed += $t.Bytes
  } catch {
    $stuck += $t.Path
  }
}
Say ("  removed {0}, freed {1:n2} GB" -f $gone, ($freed / 1GB)) 'Green'
if ($stuck.Count -gt 0) {
  Write-Host ''
  Say '  These would not go. Something still has them open, almost always Vortex' 'Yellow'
  Say '  or the game. Close both and run it again.' 'Yellow'
  foreach ($s in $stuck) { Say "    $s" 'DarkGray' }
}

Write-Host ''
Say '  Deploy once in Vortex afterwards, so it notices what changed.' 'Cyan'
if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
