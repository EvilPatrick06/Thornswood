<#
  Set-NexusKey.ps1

  Puts Patrick's Nexus Mods API key on One, asked at a prompt and never shown,
  or says whether the key this machine has works (#2914).

      .\scripts\release\Set-NexusKey.ps1           ask for the key, check it, keep it
      .\scripts\release\Set-NexusKey.ps1 -Check    whether there is one and whether Nexus takes it

  WHERE IT GOES. %LOCALAPPDATA%\Thornswood\Nexus\api-key.txt on this machine,
  the place Nexus.ps1 reads it from on One, and nowhere else. A cloud session
  has it as the environment variable THORNSWOOD_NEXUS_API_KEY instead, set in
  the cloud environment's variables, and -Check there checks that one. The key
  is his own, from https://www.nexusmods.com/settings/api-keys (Personal API
  Key, at the bottom of that page).

  THE CHECK asks Nexus which mods the key's account owns
  (GET /v3/team-mods?affiliation=owner) and says whether Thornswood Content
  (192001) and the Thornswood Client Runtime (192762) are among them, because
  a key that cannot see those two cannot upload to them. It prints the mods'
  names and never the key.

.PARAMETER Check
  Writes nothing. Says where the key was found and whether Nexus takes it.

.PARAMETER NoPause
  Does not wait for Enter at the end or on a stop.
#>
[CmdletBinding()]
param(
  [switch]$Check,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Nexus.ps1')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) {
  Write-Host ''
  Write-Host "STOP. $m" -ForegroundColor Red
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}

# The mods a key has to own, read from the scripts that upload to them.
$ours = @('192001', '192762')

function Test-Key {
  $a = $null
  try { $a = Invoke-NexusApi 'GET' '/v3/team-mods?affiliation=owner&page_size=100' '' 'Asking Nexus which mods this key owns' }
  catch { Die $_.Exception.Message }
  $mods = @(@(Get-NexusField (Get-NexusField $a 'data') 'mods') | Where-Object { $_ })
  $have = @{}
  foreach ($t in $mods) {
    $m = Get-NexusField $t 'mod'
    $have[[string](Get-NexusField $m 'game_scoped_id')] = [string](Get-NexusField $m 'name')
  }
  $missing = @($ours | Where-Object { -not $have.ContainsKey($_) })
  foreach ($id in $ours) {
    if ($have.ContainsKey($id)) { Say ('  owns ' + $id + ', ' + $have[$id]) 'Green' }
    else { Say ('  does not own ' + $id) 'Red' }
  }
  return ($missing.Count -eq 0)
}

Write-Host ''
Write-Host '  THORNSWOOD  -  the Nexus Mods API key' -ForegroundColor White
Write-Host ''

if ($Check) {
  try { [void](Read-NexusKey) } catch { Die $_.Exception.Message }
  Say ('  read from ' + $script:NexusKeyFrom + ', ' + $script:NexusKey.Length + ' characters')
  if (-not (Test-Key)) { Die 'Nexus takes the key, but its account does not own both of our mods, so uploads to them would be refused.' }
  Write-Host ''
  Say 'The key works for both mods.' 'Green'
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

if (Test-NexusStandIn) { Die 'THORNSWOOD_NEXUS_STANDIN is set, and this keeps the real key; nothing was written.' }
$file = Get-NexusKeyFile
if (-not $file) { Die 'This machine has no %LOCALAPPDATA%, so there is no place for the key file. In a cloud session the key is the environment variable THORNSWOOD_NEXUS_API_KEY, set in the cloud environment''s variables.' }
Say '  Paste the Personal API Key from https://www.nexusmods.com/settings/api-keys.' 'DarkGray'
Say '  It is not shown while you paste it.' 'DarkGray'
Write-Host ''
$secure = Read-Host '  Nexus API key' -AsSecureString
$key = ([string](New-Object Net.NetworkCredential('', $secure)).Password).Trim()
if (-not $key) { Die 'Nothing was pasted, so nothing was written.' }
if ($key -match '\s') { Die 'What was pasted has a space or a line break inside it, so it is not one key. Nothing was written.' }

# Checked with the pasted key before it is kept, so a wrong paste never
# replaces a key that worked.
$script:NexusKey = $key
$script:NexusKeyFrom = 'the key just pasted'
if (-not (Test-Key)) { Die 'Nexus takes that key, but its account does not own both of our mods. Nothing was written.' }

$dir = Split-Path -Parent $file
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[IO.File]::WriteAllText($file, $key, (New-Object Text.UTF8Encoding($false)))
Write-Host ''
Say ('Kept in ' + $file + '. Send-NexusFile.ps1, Set-NexusDescription.ps1 and New-NexusRevision.ps1 read it from there.') 'Green'
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
exit 0
