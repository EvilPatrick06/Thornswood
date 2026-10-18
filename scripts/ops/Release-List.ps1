<#
  Release-List.ps1

  The release list a game server lets go of at its next start (#2351), as
  Reset-Character.ps1, Wipe-Saves.ps1 (#2668) and New-Character.ps1 (#2673)
  write it. Dot-sourced by all three; it does nothing on its own.
  $ThornswoodReleaseList is the text of the functions below, sent with the
  step each script already runs on the server (Windows PowerShell 5.1 there)
  or, for New-Character on a local test server, run in place, so there is
  one copy of it and the scripts cannot drift apart.

  The list is private\deleted-characters.json (the server's privDir), the
  same shape Delete-Person.ps1 writes and game\gamemode.js reads:

      { "profiles": [ ... ], "actors": [ form ids ], "done": { part: time } }

  WHO IT NAMES. A reset, a new character or a wipe throws characters away
  and keeps every profile: the profile keeps its id, its mod menu choices
  and, after a reset or a new character, its house, offices, books and
  farm. So each names the thrown-away
  characters by form id only and never a profile. Each register's release
  in gamemode.js lets go by profile what a profile holds and by form id
  only what the character held (a dungeon chest's reservation, an embassy
  row with no profile, a trader's supply waits, a trade waiting on that
  character and the trade ships' manifest, #511), so a list with no profiles in it never takes anything a
  profile holds (#2668 has the table, part by part).

  A character's form id is read off its change form the way Delete-Person
  reads it: profileId above 0 and a formDesc made in the world, a hex
  number with no plugin (FormDesc::ToString).

  MERGED, NOT REPLACED. A list still waiting there (a deletion the server
  has not let go of yet) keeps every id it names; the new ids join it. A
  list there that is not one is never overwritten: the caller is told and
  writes nothing. Done is what the caller says: cleared for a reset, so
  every part runs for the new ids; for a wipe, the parts whose registers
  the wipe has just set aside, so only the merchant ledger, the register a
  wipe keeps, waits on it.

  Each function says what it did as lines, for the caller to print:
    RELEASE|<file>|<profiles>|<characters>[|done: <parts>]
    RELEASE|none                     nothing to name
    RELEASENOTE|<why>                carried on, but worth saying
    RELEASEBAD|<why>                 no list was written
#>
$ThornswoodReleaseList = @'
# ---- the release list (scripts\ops\Release-List.ps1, #2668) ----
function Get-ThornswoodPrivDir([string]$Root) {
  $priv = 'private'
  try {
    $cfg = [IO.File]::ReadAllText((Join-Path $Root 'server-settings.json')) -replace '^\uFEFF', '' | ConvertFrom-Json
    if ($cfg -and $cfg.privDir) { $priv = [string]$cfg.privDir }
  } catch { }
  if ([IO.Path]::IsPathRooted($priv)) { return $priv }
  return (Join-Path $Root $priv)
}
function Get-ThornswoodReleaseListPath([string]$Root) {
  return (Join-Path (Get-ThornswoodPrivDir $Root) 'deleted-characters.json')
}
function ConvertTo-ThornswoodIds($a, [long]$top) {
  if ($null -eq $a -or -not ($a -is [array])) { return $null }
  $out = New-Object 'System.Collections.Generic.List[long]'
  foreach ($n in $a) {
    if (-not ($n -is [int] -or $n -is [long] -or $n -is [decimal] -or $n -is [double])) { return $null }
    if ($n -ne [math]::Floor($n) -or $n -le 0 -or $n -gt $top) { return $null }
    $out.Add([long]$n)
  }
  return ,$out.ToArray()
}
function Read-ThornswoodReleaseList([string]$File) {
  if (-not (Test-Path -LiteralPath $File)) { return @{ ok = $true; missing = $true; profiles = @(); actors = @() } }
  $v = $null
  try { $v = [IO.File]::ReadAllText($File) -replace '^\uFEFF', '' | ConvertFrom-Json } catch { $v = $null }
  if (-not ($v -is [System.Management.Automation.PSCustomObject])) { return @{ ok = $false } }
  $acts = $v.actors
  if ($null -eq $acts) { $acts = @() }
  $p = ConvertTo-ThornswoodIds $v.profiles 9007199254740991
  $a = ConvertTo-ThornswoodIds $acts 4294967295
  if ($null -eq $p -or $null -eq $a) { return @{ ok = $false } }
  return @{ ok = $true; missing = $false; profiles = $p; actors = $a }
}
function Get-ThornswoodCharacterIds($Files) {
  $ids = @()
  foreach ($f in @($Files)) {
    if (-not $f) { continue }
    $o = $null
    try { $o = [IO.File]::ReadAllText([string]$f) -replace '^\uFEFF', '' | ConvertFrom-Json } catch { continue }
    if (-not ($o -is [System.Management.Automation.PSCustomObject])) { continue }
    $p = 0
    try { $p = [double]$o.profileId } catch { $p = 0 }
    $d = [string]$o.formDesc
    if ($p -gt 0 -and $d -match '^[0-9a-fA-F]{1,8}$') { $ids += [Convert]::ToInt64($d, 16) }
  }
  return ,@($ids | Sort-Object -Unique)
}
function Write-ThornswoodReleaseList {
  param([string]$Root, $Actors = @(), [string]$Carry = '', [string[]]$Done = @())
  $file = Get-ThornswoodReleaseListPath $Root
  $now = Read-ThornswoodReleaseList $file
  if (-not $now.ok) { 'RELEASEBAD|' + $file + ' is not a list of deleted characters, so no list was written and it is left as it is'; return }
  $P = @($now.profiles)
  $A = @($now.actors) + @($Actors)
  if ($Carry) {
    $old = Read-ThornswoodReleaseList $Carry
    if (-not $old.ok) { 'RELEASENOTE|' + $Carry + ' is not a list of deleted characters, so nothing was carried from it; it is left as it is' }
    elseif (-not $old.missing) { $P += @($old.profiles); $A += @($old.actors) }
  }
  $P = @($P | Where-Object { $null -ne $_ } | ForEach-Object { [long]$_ } | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
  $A = @($A | Where-Object { $null -ne $_ } | ForEach-Object { [long]$_ } | Where-Object { $_ -gt 0 -and $_ -le 4294967295 } | Sort-Object -Unique)
  if (-not $P.Count -and -not $A.Count) { 'RELEASE|none'; return }
  $parts = @($Done | Where-Object { $_ -match '^[a-z]+$' } | Sort-Object -Unique)
  $t = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $json = '{"profiles":[' + ($P -join ',') + '],"actors":[' + ($A -join ',') + ']'
  if ($parts.Count) { $json += ',"done":{' + (($parts | ForEach-Object { '"' + $_ + '":' + $t }) -join ',') + '}' }
  $json += '}'
  try {
    $dir = Split-Path -Parent $file
    if (-not (Test-Path -LiteralPath $dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    $tmp = $file + '.tmp'
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $file) { [IO.File]::Replace($tmp, $file, [NullString]::Value) } else { [IO.File]::Move($tmp, $file) }
  } catch { 'RELEASEBAD|' + $file + ' could not be written: ' + $_.Exception.Message; return }
  $line = 'RELEASE|' + $file + '|' + $P.Count + '|' + $A.Count
  if ($parts.Count) { $line += '|done: ' + ($parts -join ', ') }
  $line
}
# ---- end of the release list ----
'@
