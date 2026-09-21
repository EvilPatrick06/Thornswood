<#
  Check-Manifest.ps1

  Says what load order the game server is actually handing out, and how it
  compares to the one you play with.

      .\tools\Check-Manifest.ps1
      .\tools\Check-Manifest.ps1 -Full     print both lists in full

  Why it matters: SkyMP's client compares the server's manifest against your
  plugin list position by position. One plugin out of place and the person is
  turned away with a load order error that says nothing useful. Before building
  a Nexus collection, the list in here is the thing that has to be matched, and
  a stale copy on a client is not evidence of anything.
#>
[CmdletBinding()]
param(
  [string]$Vps  = '192.135.112.23',
  [string]$User = 'Administrator',
  [string]$Client = 'C:\Thornswood',
  [switch]$Full,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$ssh = @('-o','BatchMode=yes','-o','StrictHostKeyChecking=no')

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }

function Remote($script) {
  $e = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
  $cmd = "powershell -NoProfile -EncodedCommand $e"

  # A long script does not fit on a command line, and nothing says so.
  #
  # sshd on Windows hands the command to cmd.exe, which stops at 8,191
  # characters. Base64 of UTF-16 is about 2.7 times the script, so a block of
  # any size arrives cut in half and PowerShell then complains about a brace or
  # a token in a script nobody can see. Deploy-Docs.ps1 hit this on 17 Sep and
  # solved it; every other script here carried the short version that cannot,
  # and on 20 Sep this one truncated at 10,252 characters and reported
  # "Unexpected token '$?'" about a line fifteen above the one that was cut.
  # This is that fix, copied across so the sixteen scripts that talk to the VPS
  # all behave the same way.
  #
  # Under the limit it goes on the command line as before, because that is one
  # round trip. Over it, the script is sent as a file and run from there, which
  # has no length to run into.
  if ($cmd.Length -le 6000) {
    return & ssh @ssh "$User@$Vps" $cmd 2>&1
  }

  $far = 'C:/Windows/Temp/thornswood-remote.ps1'
  $tmp = [IO.Path]::GetTempFileName()
  try {
    Set-Content -LiteralPath $tmp -Value $script -Encoding UTF8
    & scp @ssh $tmp "$User@${Vps}:$far" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "could not send a script to $Vps" }
    # The path goes across as it is. Windows PowerShell takes forward
    # slashes, and converting them was how this shipped with the slashes
    # stripped out of it entirely: C:WindowsTempthornswood-remote.ps1.
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -ExecutionPolicy Bypass -File '$far'" 2>&1
    & ssh @ssh "$User@$Vps" "powershell -NoProfile -Command Remove-Item -LiteralPath '$far' -Force" 2>&1 | Out-Null
  }
  finally { Remove-Item -LiteralPath $tmp -Force -EA SilentlyContinue }
}

Write-Host ''
Write-Host '  THORNSWOOD  -  what load order the server wants' -ForegroundColor White

# The server root has moved before, so find it rather than assume it.
Head 'Finding the server'
$found = Remote @"
`$ErrorActionPreference = 'Continue'
`$roots = @()
foreach (`$d in (Get-ChildItem 'C:\' -Directory -EA SilentlyContinue)) {
  if (Test-Path (Join-Path `$d.FullName 'server-settings.json')) { `$roots += `$d.FullName }
}
if (-not `$roots) {
  # Second pass: one level deeper, for a server inside a folder of its own.
  foreach (`$d in (Get-ChildItem 'C:\' -Directory -EA SilentlyContinue)) {
    foreach (`$s in (Get-ChildItem `$d.FullName -Directory -EA SilentlyContinue)) {
      if (Test-Path (Join-Path `$s.FullName 'server-settings.json')) { `$roots += `$s.FullName }
    }
  }
}
if (-not `$roots) { 'NO SERVER FOUND'; exit }
foreach (`$r in `$roots) { 'ROOT ' + `$r }
"@
$found | ForEach-Object { Say "  $_" }
if ("$found" -match 'NO SERVER FOUND') {
  Write-Host ''
  Say '  No server-settings.json anywhere on C:. Is the game server on this box?' 'Red'
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 1
}
$root = (@($found) | Where-Object { $_ -match '^ROOT ' } | Select-Object -First 1) -replace '^ROOT ', ''
$root = "$root".Trim()

Head "Reading the manifests under $root"
$out = Remote @"
`$ErrorActionPreference = 'Continue'
`$root = '$root'
`$dataDir = 'data'
try {
  `$cfg = Get-Content (Join-Path `$root 'server-settings.json') -Raw | ConvertFrom-Json
  if (`$cfg.dataDir) { `$dataDir = [string]`$cfg.dataDir }
} catch { }
`$data = Join-Path `$root `$dataDir
'dataDir  ' + `$data

# The same manifest is written twice, once where it is generated and once
# where the client asks for it. Reading both and concatenating made the server
# look like it wanted 122 plugins when it wants 61.
`$seen = `$false
foreach (`$f in (Get-ChildItem `$data -Recurse -Filter 'manifest.json' -File -EA SilentlyContinue)) {
  try {
    `$m = Get-Content `$f.FullName -Raw | ConvertFrom-Json
    `$n = @(`$m.loadOrder).Count
    `$k = @(`$m.mods).Count
    'FILE ' + `$f.FullName
    '  loadOrder ' + `$n + '   mods ' + `$k + '   written ' + `$f.LastWriteTime
    if (-not `$seen) { foreach (`$p in `$m.loadOrder) { 'LO ' + `$p }; `$seen = `$true }
    else { '  same list as above, not counted twice' }
  } catch { 'FILE ' + `$f.FullName + '  UNREADABLE: ' + `$_.Exception.Message }
}
"@

$lines = @($out | ForEach-Object { "$_" })
$serverOrder = @()
foreach ($l in $lines) {
  if ($l -match '^\s*LO (.+)$') { $serverOrder += $Matches[1].Trim() }
  else { Say "  $l" }
}

if ($serverOrder.Count -eq 0) {
  Write-Host ''
  Say '  The server has not written a manifest. It writes one at startup, so it' 'Yellow'
  Say '  either has not been started since the last deploy, or it failed early.' 'Yellow'
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 1
}

# ------------------------------------------------------- the comparison ---
$plug = Join-Path $Client 'Profile\LocalAppData\plugins.txt'
Head 'Against the load order you play with'
if (-not (Test-Path -LiteralPath $plug)) {
  Say "  No plugins.txt at $plug" 'Yellow'
} else {
  $mine = @()
  foreach ($l in (Get-Content -LiteralPath $plug)) {
    $t = "$l".Trim()
    if ($t.Length -eq 0 -or $t.StartsWith('#')) { continue }
    if ($t.StartsWith('*')) { $mine += $t.Substring(1) }
  }
  # Bethesda's five are always first on the server and are not in plugins.txt.
  $vanilla = @('Skyrim.esm','Update.esm','Dawnguard.esm','HearthFires.esm','Dragonborn.esm')
  $mineFull = @($vanilla + $mine)

  Say ("  server wants  {0} plugins" -f $serverOrder.Count)
  Say ("  you have      {0} enabled (five Bethesda masters included)" -f $mineFull.Count)
  Write-Host ''

  $extra   = @($mineFull | Where-Object { $serverOrder -notcontains $_ })
  $missing = @($serverOrder | Where-Object { $mineFull -notcontains $_ })

  if ($missing.Count) {
    Say ("  {0} the server wants that you DO NOT have:" -f $missing.Count) 'Red'
    $missing | ForEach-Object { Say "    $_" 'Red' }
  } else {
    Say '  you have every plugin the server wants' 'Green'
  }
  Write-Host ''
  if ($extra.Count) {
    Say ("  {0} you have that the server does NOT list:" -f $extra.Count) 'Yellow'
    $extra | ForEach-Object { Say "    $_" 'DarkGray' }
    Write-Host ''
    Say '  Those are the ones that could be optional in a collection, IF the' 'DarkGray'
    Say '  client tolerates them. The first mismatched position below says' 'DarkGray'
    Say '  whether it does.' 'DarkGray'
  } else {
    Say '  you have nothing the server does not list' 'Green'
  }

  Write-Host ''
  $n = [Math]::Min($serverOrder.Count, $mineFull.Count)
  $firstBad = -1
  for ($i = 0; $i -lt $n; $i++) {
    if ($serverOrder[$i] -ne $mineFull[$i]) { $firstBad = $i; break }
  }
  if ($firstBad -lt 0 -and $serverOrder.Count -eq $mineFull.Count) {
    Say '  POSITION BY POSITION: identical.' 'Green'
  } elseif ($firstBad -lt 0) {
    Say ("  POSITION BY POSITION: the first {0} match, then one list runs out." -f $n) 'Yellow'
  } else {
    Say ("  POSITION BY POSITION: they part company at slot {0}." -f ($firstBad + 1)) 'Red'
    Say ("    server: " + $serverOrder[$firstBad]) 'Red'
    Say ("    you:    " + $mineFull[$firstBad]) 'Red'
    Write-Host ''
    Say '  If you can still connect with this, the client is NOT comparing' 'Yellow'
    Say '  strictly by position, and a collection can have optional plugins.' 'Yellow'
    Say '  If you cannot, the server manifest is stale and needs regenerating.' 'Yellow'
  }
}

if ($Full) {
  Head 'The server list in full'
  $i = 0
  foreach ($p in $serverOrder) { $i++; Say ('  {0,3}  {1}' -f $i, $p) }
}

Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
