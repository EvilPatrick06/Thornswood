<#
  Sync-LoadOrder.ps1 - build the server's load order from the client's.

  Stop patching this one plugin at a time. The server's list is supposed to be
  the client's list, and every time they drift something breaks in a way that
  looks like anything except a load order problem.

  Why it matters: SkyMP resolves a form as fileIndex * 0x01000000 + localId and
  nothing translates between the two sides. The client checks at startup, in
  loadOrderVerificationService: for each entry the server lists, the client's
  plugin at that index must match by filename, size and CRC. Its own words for
  a mismatch are "Expect EVERYTHING BREAK".

  Two rules decide what can go in:

  1. ESL flagged plugins get no normal index. The game loads them into the FE
     space, so Game.GetModCount skips them, and the server must skip them too
     or every index after the first one is wrong.

  2. The server's reader will not load a plugin whose masters are absent. Since
     a light plugin cannot be in the list, anything mastering to one cannot be
     either. Those are found and named rather than silently dropped, because
     dropping one silently is what caused the drift in the first place.

  Nothing is written to the client. If a plugin cannot go server side, the two
  lists cannot match while it is switched on, and that is your call to make,
  not this script's.
#>

[CmdletBinding()]
param(
  [string] $Data     = ((& (Join-Path $PSScriptRoot '..\release\Where.ps1') Install) + '\Game\Data'),
  [string] $Plugins  = ((& (Join-Path $PSScriptRoot '..\release\Where.ps1') Install) + '\Profile\LocalAppData\Plugins.txt'),
  [string] $Settings = (& (Join-Path $PSScriptRoot '..\release\Where.ps1') ServerSettings),
  [switch] $WhatIfOnly
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

foreach ($p in @($Data, $Plugins, $Settings)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "not found: $p" }
}

# When the Plugins path is under a Vortex profile, it must be the named
# Thornswood profile (#557). Another profile's list must not bake the server.
. (Join-Path $PSScriptRoot 'LoadOrder.ps1')
if ($Plugins -match '(?i)[\\/]Vortex[\\/].*[\\/]profiles[\\/]') {
  $tw = Assert-VortexProfile 'Thornswood'
  $full = [IO.Path]::GetFullPath($Plugins)
  $twDir = [IO.Path]::GetFullPath($tw)
  if (-not $full.StartsWith($twDir, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Sync-LoadOrder will only read the Vortex profile named Thornswood (at $tw). Refusing $Plugins."
  }
}


function Head($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }
function Note($t) { Write-Host "  $t" }
function Bad($t)  { Write-Host "  $t" -ForegroundColor Yellow }

# Reads the TES4 header: the light flag, and every master it names.
function Get-PluginInfo([string]$path) {
  $info = @{ Light = $false; Masters = @() }
  if ($path -match '\.esl$') { $info.Light = $true }
  $fs = [IO.File]::OpenRead($path)
  try {
    $br = New-Object IO.BinaryReader($fs)
    if ([Text.Encoding]::ASCII.GetString($br.ReadBytes(4)) -ne 'TES4') { return $info }
    $dataSize = $br.ReadUInt32()
    $flags    = $br.ReadUInt32()
    if (($flags -band 0x200) -ne 0) { $info.Light = $true }
    $null = $br.ReadBytes(12)          # formId, revision, version, unknown

    $end = $fs.Position + $dataSize
    while ($fs.Position -lt $end -and $fs.Position -lt $fs.Length) {
      $sig = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
      $len = $br.ReadUInt16()
      $buf = $br.ReadBytes($len)
      if ($sig -eq 'MAST') {
        $name = [Text.Encoding]::ASCII.GetString($buf).TrimEnd([char]0)
        if ($name) { $info.Masters += $name }
      }
    }
  } finally { $fs.Close() }
  return $info
}

# ------------------------------------------------------------ the client ---
Head 'Reading the client list'
$implicit = 'Skyrim.esm','Update.esm','Dawnguard.esm','HearthFires.esm','Dragonborn.esm'
$fromFile = Get-Content -LiteralPath $Plugins |
            Where-Object { $_ -match '^\*' } |
            ForEach-Object { $_.TrimStart('*').Trim() } |
            Where-Object { $_ }
$wanted = @($implicit | Where-Object { $fromFile -notcontains $_ }) + $fromFile
Note "$($wanted.Count) plugins switched on"

$info = @{}
$light = @{}
$present = @()
foreach ($n in $wanted) {
  $full = Join-Path $Data $n
  if (-not (Test-Path -LiteralPath $full)) { Bad "missing from Data, skipped: $n"; continue }
  $i = Get-PluginInfo $full
  $info[$n] = $i
  if ($i.Light) { $light[$n.ToLower()] = $true }
  $present += $n
}
Note "$(($light.Keys).Count) of them are light and take no index"

# ------------------------------------------------------------ the server ---
Head 'Building the server list'
$order = @()
$blocked = @()
foreach ($n in $present) {
  if ($info[$n].Light) { continue }

  # A master that is light, or not switched on at all, is a master the server
  # cannot load, so this plugin cannot go in the list either.
  $why = @()
  foreach ($m in $info[$n].Masters) {
    if ($light.ContainsKey($m.ToLower())) { $why += "$m is light" ; continue }
    $hasIt = $false
    foreach ($p in $present) { if ($p -ieq $m) { $hasIt = $true; break } }
    if (-not $hasIt) { $why += "$m is not switched on" }
  }
  if ($why.Count -gt 0) { $blocked += [pscustomobject]@{ Name = $n; Why = ($why -join ', ') }; continue }

  $order += ($Data -replace '\\', '/') + '/' + $n
}

Note "$($order.Count) plugins can go server side"

if ($blocked.Count -gt 0) {
  Head 'These cannot, and they break the match while they are on'
  foreach ($b in $blocked) { Bad ("{0}  ({1})" -f $b.Name, $b.Why) }
  Note ''
  Note 'Each one takes an index the server has no entry for, so everything after'
  Note 'it resolves to the wrong object. Either switch them off in your load'
  Note 'order, or accept that mod forms after the first one are unreliable.'
}

$bytes = 0
foreach ($p in $order) { $f = $p -replace '/', '\'; if (Test-Path -LiteralPath $f) { $bytes += (Get-Item -LiteralPath $f).Length } }
Note ("payload would be {0:N1} MB of plugin files" -f ($bytes / 1MB))

if ($WhatIfOnly) { Head 'Nothing written (-WhatIfOnly)'; return }

# ------------------------------------------------------------------ write --
Head 'Writing'
$s = Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json
$was = @($s.loadOrder).Count
$s.loadOrder = $order

# No BOM: node reads this, and a BOM turns it into "Unexpected token" rather
# than JSON, which is a memorable way to lose an evening.
$json = $s | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText($Settings, $json, (New-Object Text.UTF8Encoding($false)))
Note "server load order: $was -> $($order.Count)"

Head 'Now'
Note 'Nothing has changed until the server has this:'
Note ''
Note '    .\Publish-Server.ps1'
Note ''
Note 'Then launch. The yellow LOAD ORDER WARNING should be gone. If the server'
Note 'will not start, its reader refused one of the new plugins and the log'
Note 'names it: take that one out and run this again.'
