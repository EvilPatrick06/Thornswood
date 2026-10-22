<#
  test-3196-dev-reload.ps1

  A dev gamemode deploy that changes only gamemode.js loads it in the running
  dev server instead of restarting it, knows from server.log that it loaded,
  and puts the old one back when it did not (#3196, Patrick's C on 22 Oct
  2026). scripts\deploy\Reload.ps1 has the block and the why.

  HOW. The block is taken out of Reload.ps1 the way Deploy-DevGamemode.ps1
  takes it, given its values by ReloadVars, and run against a scratch server
  folder: by Windows PowerShell 5.1 on Windows, which is what runs it on the
  box, and by pwsh elsewhere. The engine is a node stand-in that does what
  skymp5-server does with a gamemode (ts/index.ts and ts/gamemodeLoad.ts in
  Thornswood's fork): it loads gamemode.js again when its bytes change, and
  says in server.log what the gamemode says as it loads (gamemodeId, taken
  out of game\gamemode.js itself) and then how the load went. Marker files in
  the scratch folder make it a load that throws, an engine that never loads,
  and a server.log rolled half way through a load. The only other stand-in is
  Get-NetUDPEndpoint, which answers from a file in the scratch folder, so the
  server is running or not as a case needs.

  It proves:
    - the git blob id the deploy waits for is the one git and the gamemode
      give, carriage returns and all
    - a new gamemode goes in while the server runs, the block waits for the
      server to say it loaded that blob, and keeps the old files in .prev,
      keeping only the newest two .prev folders
    - the same gamemode with a new stamp swaps the stamp and waits for nothing
    - a load that crosses a roll of server.log is still read
    - it does not reload, and touches nothing, for a run that sends a plugin,
      changes a setting, meets an engine that cannot say how a load went, a
      server that is not running, or a gamemode loaded from somewhere else
    - a gamemode that throws at load is put back and the old one loads again,
      with the server never stopped
    - an engine that loads neither leaves the old files on disk and in .prev,
      and says RELOAD FAILED, for the put-back swap
    - Deploy-DevGamemode.ps1 reloads only when neither -PutBack nor -Restart
      is given, before the warning, and restarts with the put-back after
      RELOAD FAILED

  Connects to nothing.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Windows.ps1')
$repo = Split-Path -Parent $PSScriptRoot

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
  if ($cond) { $script:pass++; Write-Host "PASS  $what" }
  else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Done {
  Write-Host ''
  Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
  if ($script:fail) { exit 1 }
  exit 0
}

if (-not (Get-Command node -EA SilentlyContinue)) { Write-Host 'NOT RUN  the stand-in engine is node, and node is not on this machine'; exit 0 }
$ps = 'pwsh'
if ($OnWindows) { $ps = Get-WindowsPowerShell }

. (Join-Path $repo 'scripts\deploy\Swap.ps1')
. (Join-Path $repo 'scripts\deploy\Reload.ps1')
$reloadText = [IO.File]::ReadAllText((Join-Path $repo 'scripts\deploy\Reload.ps1'))
Yes 'Reload.ps1 keeps its block between markers, in plain ASCII' (
  $reloadText.Contains('# ==== dev reload block ====') -and $reloadText.Contains('# ==== end dev reload block ====') -and $reloadText -notmatch '[^\x00-\x7F]')
Yes 'and the folders'' turn (#3247) and the blob function go up in front of it' (
  $reloadBlock.StartsWith([IO.File]::ReadAllText((Join-Path $repo 'scripts\deploy\ServerFolderTurn.ps1'))) -and $reloadBlock.Contains('function Get-ThornswoodGamemodeBlob {'))

# ---- the id ------------------------------------------------------------------
$gmText = [IO.File]::ReadAllText((Join-Path $repo 'game\gamemode.js'))
$idFn = [regex]::Match($gmText, '(?s)function gamemodeId\(bytes\) \{.*?\n\}').Value
Yes 'game\gamemode.js still works out its own id with gamemodeId' ([bool]$idFn)
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-3196-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $scratch
$crlf = Join-Path $scratch 'crlf.js'
[IO.File]::WriteAllText($crlf, "'use strict';`r`nconst a = 1;`r`n// a lone`r carriage return stays`n")
$git = ''
[IO.File]::WriteAllText((Join-Path $scratch 'lf.js'), "'use strict';`nconst a = 1;`n// a lone`r carriage return stays`n")
try { $git = [string](& git hash-object --no-filters (Join-Path $scratch 'lf.js')) } catch { $git = '' }
$idJs = Join-Path $scratch 'id.js'
[IO.File]::WriteAllText($idJs, $idFn + "`nprocess.stdout.write(gamemodeId(require('fs').readFileSync(process.argv[2])).blob);`n")
$fromGamemode = [string](& node $idJs $crlf)
$mine = Get-ThornswoodGamemodeBlob $crlf
Yes ('the deploy''s id for a file with CR LF is the gamemode''s own (' + $mine + ')') ($mine -eq $fromGamemode -and $mine -match '^[0-9a-f]{40}$')
if ($git) { Yes '  and git hash-object''s for the same file with LF' ($mine -eq $git.Trim()) }

# ---- the stand-in engine -------------------------------------------------------
$engineJs = Join-Path $scratch 'engine.js'
[IO.File]::WriteAllText($engineJs, $idFn + @'

const fs = require('fs'), path = require('path');
const root = process.argv[2];
const gm = path.join(root, 'gamemode.js'), log = path.join(root, 'server.log');
const has = (m) => fs.existsSync(path.join(root, m));
function say(l) { fs.appendFileSync(log, '[' + new Date().toISOString() + '] ' + l + '\n'); }
let last = null, loads = 0, failed = false;
function load() {
  let b;
  try { b = fs.readFileSync(gm); } catch (e) { return; }
  const t = b.toString('latin1');
  if (t === last) return;
  if (loads > 0 && (has('.stub-deaf') || (failed && has('.stub-deaf-after-fail')))) return;
  last = t;
  loads++;
  say('[thornswood] gamemode.js is git blob ' + gamemodeId(b).blob + ', ' + b.length + ' bytes');
  if (t.indexOf('THROW') >= 0) {
    failed = true;
    say('Error: the gamemode threw at load');
    say('[thornswood] gamemode did not load; the error is above');
    return;
  }
  if (has('.stub-roll')) {
    const d = new Date();
    fs.renameSync(log, log + '.' + d.getTime());
    fs.unlinkSync(path.join(root, '.stub-roll'));
  }
  say('[thornswood] gamemode client scripts 0123456789ab (4), ' + (loads === 1 ? 'the first load in this process' : 'changed since the last load'));
}
load();
setInterval(load, 150);
'@)

# Get-NetUDPEndpoint, answering from .stub-udp in the server folder: its port
# when the server runs, nothing when the file is not there.
$udpStandIn = @'
function Get-NetUDPEndpoint {
  $f = Join-Path $Root '.stub-udp'
  if (-not (Test-Path -LiteralPath $f)) { return }
  [pscustomobject]@{ LocalPort = [int]([IO.File]::ReadAllText($f).Trim()); OwningProcess = $PID }
}

'@

$oldGm = "'use strict';`r`n// the gamemode that runs`r`nmp.x = 1;`r`n"
$newGm = "'use strict';`r`n// the gamemode this deploy sends`r`nmp.x = 2;`r`n"
$script:case = 0
# A server folder running $oldGm, a stage holding what $send names, and the
# engine started on it. Returns what the case needs.
function New-Server([hashtable]$send, [string[]]$marks = @(), [string]$engineSays = '[thornswood] gamemode did not load; the error is above', [bool]$running = $true, [string]$stageSettings = '') {
  $script:case++
  $root = Join-Path $scratch ('root' + $script:case)
  $null = New-Item -ItemType Directory -Path (Join-Path $root 'dist_back') -Force
  $settings = '{"port":7787,"name":"dev"}'
  [IO.File]::WriteAllText((Join-Path $root 'server-settings.json'), $settings)
  [IO.File]::WriteAllText((Join-Path $root 'gamemode.js'), $oldGm)
  [IO.File]::WriteAllText((Join-Path $root 'thornswood-build.json'), '{"commit":"old"}')
  [IO.File]::WriteAllText((Join-Path (Join-Path $root 'dist_back') 'skymp5-server.js'), 'console.log("' + $engineSays + '")')
  [IO.File]::WriteAllText((Join-Path $root 'server.log'), "[start] Current process ID is 1`n")
  if ($running) { [IO.File]::WriteAllText((Join-Path $root '.stub-udp'), '7787') }
  foreach ($m in $marks) { [IO.File]::WriteAllText((Join-Path $root $m), '') }
  $stamp = '20261022-' + (100000 + $script:case)
  $stage = Join-Path $root ('.stage-' + $stamp)
  $null = New-Item -ItemType Directory -Path (Join-Path $stage 'plugins') -Force
  if (-not $stageSettings) { $stageSettings = $settings }
  $send['server-settings.json'] = $stageSettings
  $sums = [ordered]@{}
  foreach ($rel in $send.Keys) {
    $at = Join-Path $stage $rel
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $at) -Force
    [IO.File]::WriteAllText($at, $send[$rel])
    $sums[$rel] = (Get-FileHash -LiteralPath $at -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  $how = @{ FilePath = (Get-Command node).Source; ArgumentList = @($engineJs, $root); PassThru = $true }
  if ($OnWindows) { $how.WindowStyle = 'Hidden' }
  $proc = Start-Process @how
  # The engine's first load, as at a start.
  $until = (Get-Date).AddSeconds(10)
  while ((Get-Date) -lt $until -and -not ([IO.File]::ReadAllText((Join-Path $root 'server.log')).Contains('first load'))) { Start-Sleep -Milliseconds 100 }
  return @{ Root = $root; Stage = $stage; StageName = ('.stage-' + $stamp); PrevName = ('.prev-' + $stamp); Sums = $sums; Engine = $proc }
}
function Invoke-Reload($srv, [int]$wait = 6) {
  $blob = ''
  $staged = Join-Path $srv.Stage 'gamemode.js'
  if (Test-Path -LiteralPath $staged) { $blob = Get-ThornswoodGamemodeBlob $staged } else { $blob = Get-ThornswoodGamemodeBlob (Join-Path $srv.Root 'gamemode.js') }
  $vars = ReloadVars $srv.Root 'Thornswood Dev Server' $srv.StageName $srv.PrevName $wait $srv.Sums $blob
  # SwapVars writes the root the box's way; off Windows the scratch root is
  # a path with forward slashes, so it goes in as it is.
  if (-not $OnWindows) { $vars = [regex]::Replace($vars, "(?m)^\`$Root  = '.*'\r?$", ("`$Root  = '" + $srv.Root.Replace("'", "''") + "'")) }
  $f = Join-Path $scratch ('reload' + $script:case + '.ps1')
  [IO.File]::WriteAllText($f, $vars + $udpStandIn + $reloadBlock)
  $out = @(& $ps -NoProfile -ExecutionPolicy Bypass -File $f 2>&1 | ForEach-Object { "$_".Trim() })
  foreach ($l in $out) { Write-Host ('      ' + $l) -ForegroundColor DarkGray }
  return $out
}
function Stop-Server($srv) { try { Stop-Process -Id $srv.Engine.Id -Force -EA SilentlyContinue } catch { } }
function Read-At($srv, [string]$rel) { $p = Join-Path $srv.Root $rel; if (Test-Path -LiteralPath $p) { [IO.File]::ReadAllText($p) } else { $null } }
function Logs($srv) { (@(Get-ChildItem -LiteralPath $srv.Root -File -Force -Filter 'server.log*') | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join '' }

try {
  # ---- a good reload ---------------------------------------------------------
  $srv = New-Server @{ 'gamemode.js' = $newGm; 'thornswood-build.json' = '{"commit":"new"}' }
  foreach ($old in '.prev-20261020-000001', '.prev-20261021-000001', '.prev-20261021-000002') { $null = New-Item -ItemType Directory -Path (Join-Path $srv.Root $old) }
  $out = Invoke-Reload $srv
  $newBlob = Get-ThornswoodGamemodeBlob (Join-Path $srv.Root 'gamemode.js')
  Yes 'a gamemode-only deploy to a running server reloads: RELOAD OK' ($out -contains 'RELOAD OK')
  Yes '  the new gamemode and its stamp are in place' ((Read-At $srv 'gamemode.js') -eq $newGm -and (Read-At $srv 'thornswood-build.json') -eq '{"commit":"new"}')
  Yes '  it waited for the server to say it loaded that blob' (@($out | Where-Object { $_ -like "*gamemode.js is git blob $newBlob*" }).Count -eq 1 -and ($out -match '^PASS: the dev server loaded git blob').Count -eq 1)
  $prev = Join-Path $srv.Root $srv.PrevName
  Yes '  the old gamemode, stamp and settings are kept in .prev' (
    [IO.File]::ReadAllText((Join-Path $prev 'gamemode.js')) -eq $oldGm -and [IO.File]::ReadAllText((Join-Path $prev 'thornswood-build.json')) -eq '{"commit":"old"}' -and
    (Test-Path -LiteralPath (Join-Path $prev 'server-settings.json')))
  Yes '  the stage is gone, and the settings are the ones it ran with' (-not (Test-Path -LiteralPath $srv.Stage) -and (Read-At $srv 'server-settings.json') -eq '{"port":7787,"name":"dev"}')
  $prevs = @(Get-ChildItem -LiteralPath $srv.Root -Directory -Force | Where-Object { $_.Name -like '.prev-*' } | ForEach-Object { $_.Name } | Sort-Object)
  Yes ('  only the newest two .prev folders are kept (' + ($prevs -join ', ') + ')') (($prevs -join ',') -eq ('.prev-20261021-000002,' + $srv.PrevName))
  Yes '  and the server was never stopped' (-not $srv.Engine.HasExited)
  Stop-Server $srv

  # ---- the same gamemode, a new stamp -----------------------------------------
  $srv = New-Server @{ 'gamemode.js' = $oldGm; 'thornswood-build.json' = '{"commit":"newer"}' }
  $t0 = Get-Date
  $out = Invoke-Reload $srv
  Yes 'the gamemode it already runs, with a new stamp: RELOAD OK, the stamp moved' ($out -contains 'RELOAD OK' -and (Read-At $srv 'thornswood-build.json') -eq '{"commit":"newer"}')
  Yes '  without waiting for a load that cannot come' (@($out | Where-Object { $_ -like '*already runs git blob*' }).Count -eq 1 -and ((Get-Date) - $t0).TotalSeconds -lt 6)
  Stop-Server $srv

  # ---- a roll of server.log in the middle of the load ---------------------------
  $srv = New-Server @{ 'gamemode.js' = $newGm; 'thornswood-build.json' = '{"commit":"new"}' } @('.stub-roll')
  $out = Invoke-Reload $srv
  Yes 'a load whose lines cross a roll of server.log is still read: RELOAD OK' ($out -contains 'RELOAD OK')
  Yes '  and server.log was rolled in the middle' (@(Get-ChildItem -LiteralPath $srv.Root -File -Force | Where-Object { $_.Name -match '^server\.log\.\d+$' }).Count -eq 1)
  Stop-Server $srv

  # ---- not a reload -----------------------------------------------------------
  $notHere = @(
    @{ What = 'a run that also sends a plugin'; Send = @{ 'gamemode.js' = $newGm; 'plugins/Thornswood-Content.esp' = 'esp' }; Says = 'plugins/Thornswood-Content.esp' },
    @{ What = 'a run that changes a setting'; Send = @{ 'gamemode.js' = $newGm }; Settings = '{"port":7787,"name":"dev","npcEnabled":false}'; Says = 'dev settings change' },
    @{ What = 'an engine that cannot say how a load went'; Send = @{ 'gamemode.js' = $newGm }; Engine = 'console.log("Bad syntax, ignoring")'; Says = 'does not say how a gamemode load went' },
    @{ What = 'a server that is not running'; Send = @{ 'gamemode.js' = $newGm }; Down = $true; Says = 'is not running' },
    @{ What = 'a server whose gamemode is loaded from somewhere else'; Send = @{ 'gamemode.js' = $newGm }; Settings = '{"port":7787,"name":"dev","gamemodePath":"other.js"}'; Same = $true; Says = 'loads its gamemode from' }
  )
  foreach ($n in $notHere) {
    $engineSays = '[thornswood] gamemode did not load; the error is above'
    if ($n.Engine) { $engineSays = $n.Engine.Replace('console.log("', '').Replace('")', '') }
    $stageSettings = ''
    if ($n.Settings) { $stageSettings = $n.Settings }
    $srv = New-Server $n.Send @() $engineSays (-not $n.Down) $stageSettings
    if ($n.Same) { [IO.File]::WriteAllText((Join-Path $srv.Root 'server-settings.json'), $n.Settings) }
    $out = Invoke-Reload $srv
    $said = @($out | Where-Object { $_ -like 'not reloading: *' })
    Yes ($n.What + ' is not reloaded: RELOAD NOT HERE, saying why') ($out -contains 'RELOAD NOT HERE' -and $said.Count -eq 1 -and $said[0].Contains($n.Says))
    Yes '  and nothing was touched: the stage is there for the swap, no .prev' (
      (Read-At $srv 'gamemode.js') -eq $oldGm -and (Test-Path -LiteralPath (Join-Path $srv.Stage 'gamemode.js')) -and -not (Test-Path -LiteralPath (Join-Path $srv.Root $srv.PrevName)))
    Stop-Server $srv
  }

  # ---- a gamemode that throws ---------------------------------------------------
  $bad = "'use strict';`r`nTHROW`r`n"
  $srv = New-Server @{ 'gamemode.js' = $bad; 'thornswood-build.json' = '{"commit":"bad"}' }
  $out = Invoke-Reload $srv
  $oldBlob = Get-ThornswoodGamemodeBlob (Join-Path $srv.Root 'gamemode.js')
  Yes 'a gamemode that throws at load is put back: RELOAD PUT BACK' ($out -contains 'RELOAD PUT BACK')
  Yes '  saying it did not load, with the log since it went in' (@($out | Where-Object { $_ -like '*the new gamemode did not take: it did not load*' }).Count -eq 1 -and ($out -contains 'Error: the gamemode threw at load' -or @($out | Where-Object { $_ -like '*Error: the gamemode threw at load' }).Count -ge 1))
  Yes '  the old gamemode and stamp are back, and the server loaded the old one again' (
    (Read-At $srv 'gamemode.js') -eq $oldGm -and (Read-At $srv 'thornswood-build.json') -eq '{"commit":"old"}' -and $oldBlob -eq (Get-ThornswoodGamemodeBlob (Join-Path $srv.Root 'gamemode.js')) -and
    ((Logs $srv) -split "`n" | Where-Object { $_ -like '*client scripts*changed since the last load*' }).Count -eq 1)
  Yes '  with the stage and the .prev copy gone, and the server never stopped' (
    -not (Test-Path -LiteralPath $srv.Stage) -and -not (Test-Path -LiteralPath (Join-Path $srv.Root $srv.PrevName)) -and -not $srv.Engine.HasExited)
  Stop-Server $srv

  # ---- an engine that loads neither -----------------------------------------------
  $srv = New-Server @{ 'gamemode.js' = $newGm; 'thornswood-build.json' = '{"commit":"new"}' } @('.stub-deaf')
  $out = Invoke-Reload $srv 3
  Yes 'an engine that loads neither the new nor the old: RELOAD FAILED' ($out -contains 'RELOAD FAILED')
  Yes '  having waited for each, and said so' (@($out | Where-Object { $_ -like '*nothing in server.log said it loaded within 3 seconds*' }).Count -eq 2)
  $prev = Join-Path $srv.Root $srv.PrevName
  Yes '  the old files are back on disk and kept in .prev, for the put-back swap' (
    (Read-At $srv 'gamemode.js') -eq $oldGm -and (Read-At $srv 'thornswood-build.json') -eq '{"commit":"old"}' -and
    [IO.File]::ReadAllText((Join-Path $prev 'gamemode.js')) -eq $oldGm -and (Test-Path -LiteralPath (Join-Path $prev 'server-settings.json')) -and -not (Test-Path -LiteralPath $srv.Stage))
  Stop-Server $srv
} finally {
  Get-Process -Name node -EA SilentlyContinue | Where-Object { try { $_.CommandLine -like "*$engineJs*" } catch { $false } } | Stop-Process -Force -EA SilentlyContinue
}

# ---- Deploy-DevGamemode.ps1 -------------------------------------------------------
$dev = [IO.File]::ReadAllText((Join-Path $repo 'scripts\deploy\Deploy-DevGamemode.ps1'))
$cmd = Get-Command -Name (Join-Path $repo 'scripts\deploy\Deploy-DevGamemode.ps1')
Yes 'Deploy-DevGamemode.ps1 takes -Restart and loads Reload.ps1' ($cmd.Parameters.ContainsKey('Restart') -and $dev.Contains(". (Join-Path `$Here 'Reload.ps1')"))
Yes '  it waits for the blob of the gamemode it sends' ($dev.Contains('$newBlob = Get-ThornswoodGamemodeBlob $Gamemode') -and $dev.Contains('(ReloadVars $Root $Task $stageName $prevName $Wait $hashes $newBlob) + $reloadBlock'))
$atReload = $dev.IndexOf('+ $reloadBlock')
$atWarn = $dev.IndexOf("Write-Host 'Who is on the dev server...'")
Yes '  it reloads before the warning, and only without -PutBack and -Restart' ($atReload -gt 0 -and $atWarn -gt $atReload -and $dev.Contains('if (-not $PutBack -and -not $Restart) {'))
Yes '  the warning and the swap run only for a restart or the put-back after RELOAD FAILED' (
  $dev.Contains("if (`$outcome -eq 'swap' -or `$outcome -eq 'recover') {") -and $dev.Contains("if (`$PutBack -or `$outcome -eq 'recover') { `$pick = `$putBackPick }") -and
  $dev.Contains("elseif (`$reloadOut -contains 'RELOAD FAILED') {"))
Yes '  and a reload that did not take fails the run, even when the put-back after it answered' (
  $dev.Contains("`$deployed = (`$outcome -eq 'reloaded') -or (`$outcome -eq 'swap' -and `$swapped)") -and $dev.Contains('if (-not $deployed) { exit 1 }'))

Remove-Item -LiteralPath $scratch -Recurse -Force -EA SilentlyContinue
Done
