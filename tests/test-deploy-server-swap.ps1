<#
  test-deploy-server-swap.ps1

  Deploy-Server.ps1 stages and checks before it stops anything, and puts the
  old files back when the new server does not answer.

  WHY THIS EXISTS. Entry 209 on the To Do List: "Upload to a staging path,
  verify there, the shortest possible stop, an atomic rename, a real health
  check." Until then the script that runs most often stopped the live server
  first, copied straight over the running folder, waited six seconds and
  printed SERVER IS NOT LISTENING without exiting non-zero or putting anything
  back.

  HOW. The two blocks that run on the box are taken out of Deploy-Server.ps1
  from between its markers, given a scratch folder in place of
  C:\Thornswood-Server, and run by Windows PowerShell 5.1, which is what runs
  them on the VPS. The server is a node stub that holds its game port on UDP
  and its resources port on TCP the way skymp5-server does, and a second stub
  on other ports stands in for the server that is not being deployed. The
  stop, the port checks, the renames and the health check are the real ones.
  Only the task scheduler is not: Start-ScheduledTask and Stop-ScheduledTask
  are replaced by functions that start the stub, so nothing here registers or
  touches a real task.

  It proves:
    - a load order naming a plugin that is nowhere leaves the live files as
      they were and the server answering, and so does a port that moves, a
      file that arrived different, a byte order mark, and a binary that is not
      the recorded build
    - a new server that hangs on its game port, or that dies on start, gets
      the old files back, the old server started again, and SWAP ROLLED BACK
    - a good deploy swaps every file in, keeps what it replaced, answers,
      keeps the newest two .prev folders, and never touches the other server
    - the build stamp is one of the staged files, so it goes in beside
      gamemode.js on a good deploy and goes back with it on a rollback

  Connects to nothing but 127.0.0.1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

# ---- the blocks, out of the script itself -----------------------------------
# Swap.ps1 since issue #446, which Deploy-Server.ps1 and Deploy-DevGamemode.ps1
# both load.
$src = Get-Content -LiteralPath (Join-Path $Here 'scripts\deploy\Deploy-Server.ps1') -Raw
$lib = Get-Content -LiteralPath (Join-Path $Here 'scripts\deploy\Swap.ps1') -Raw
$a = $lib.IndexOf('# ==== deploy-server remote blocks ====')
$b = $lib.IndexOf('# ==== end deploy-server remote blocks ====')
Yes 'Swap.ps1 keeps the blocks that run on the box between their markers' ($a -ge 0 -and $b -gt $a)
if ($a -lt 0 -or $b -le $a) { Done }
$checkBlock = $null
$swapBlock = $null
Invoke-Expression $lib.Substring($a, $b - $a)
$c = $lib.IndexOf('# ==== put-back pick ====')
$d = $lib.IndexOf('# ==== end put-back pick ====')
$putBackPick = $null
if ($c -ge 0 -and $d -gt $c) { Invoke-Expression $lib.Substring($c, $d - $c) }
Yes 'the stage check, the swap, the put-back pick and SwapVars are all there' (
    [bool]$checkBlock -and [bool]$swapBlock -and [bool]$putBackPick -and [bool](Get-Command SwapVars -EA SilentlyContinue))
Yes 'Deploy-Server.ps1 loads Swap.ps1' ($src -match "\. \(Join-Path \`$Here 'Swap\.ps1'\)")

# ---- read, not run ----------------------------------------------------------
Yes 'the blocks are plain ASCII, which the far end reads right with or without a byte order mark' (
    ($checkBlock + $swapBlock + $putBackPick) -notmatch '[^\x00-\x7F]')

# The narrowing on 17 September was a fix. The TCP port one above the game
# port is 7778 on the live root, which is the voice service.
Yes 'the stop is still by the UDP port and nothing else' (
    $swapBlock -match 'Get-NetUDPEndpoint -LocalPort \$port' -and
    $swapBlock -notmatch 'Get-NetTCPConnection' -and
    $swapBlock -notmatch 'Win32_Process' -and
    $swapBlock -notmatch 'CommandLine')
Yes 'the stage check stops nothing' ($checkBlock -notmatch 'Stop-Process|Stop-ScheduledTask')

$flow = $src.Substring([Math]::Max(0, $src.IndexOf('# ------------------------------------------------------------- the stage')))
$iStage = $flow.IndexOf('$checkBlock)')
$iWarn  = $flow.IndexOf('# ------------------------------------------------------------- the warning')
$iSwap  = $flow.IndexOf('$swapBlock)')
Yes 'the stage is checked before anybody is warned, and the swap comes after both' (
    $iStage -ge 0 -and $iWarn -gt $iStage -and $iSwap -gt $iWarn)
Yes 'a stage that does not check out ends the run' ($flow -match "-notcontains 'STAGE OK'")
Yes 'nothing is copied straight over the live folder any more' (
    $flow -notmatch ':\$Root/' -and $flow -notmatch ':\$remotePlugins/')
Yes 'a swap that is not SWAP OK exits 1' ($flow -match "-notcontains 'SWAP OK'\)\s*\{[\s\S]*?exit 1")

# A plugin name is free text. One with an apostrophe in it must not end the
# string early on the far side.
$pre = SwapVars 'C:/Thornswood-Server' "Tom's Task" '.stage-x' '.prev-x' 7 ([ordered]@{ "plugins/Bob's.esp" = 'ab12' })
Yes 'SwapVars turns the root to backslashes and doubles every single quote' (
    $pre -match [regex]::Escape("`$Root  = 'C:\Thornswood-Server'") -and
    $pre -match [regex]::Escape("`$Task  = 'Tom''s Task'") -and
    $pre -match [regex]::Escape("`$Want['plugins/Bob''s.esp'] = 'ab12'"))
$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($pre + $swapBlock, [ref]$tokens, [ref]$errors)
Yes 'and what it makes parses with the swap behind it' ($errors.Count -eq 0)

# ---- run, against a scratch folder ------------------------------------------
$node = Get-Command node -EA SilentlyContinue
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not $node -or -not (Test-Path -LiteralPath $ps51) -or
    -not (Get-Command Get-NetUDPEndpoint -EA SilentlyContinue)) {
    Write-Host 'SKIP  the runs need node, Windows PowerShell 5.1 and Get-NetUDPEndpoint, and this machine lacks one'
    Done
}

function Free([int]$p) {
    (-not @(Get-NetUDPEndpoint -LocalPort $p -EA SilentlyContinue).Count) -and
    (-not @(Get-NetTCPConnection -LocalPort $p -EA SilentlyContinue).Count)
}
$rand = New-Object Random
function PickPorts {
    do { $script:P = $rand.Next(41000, 48000) } until ((Free $script:P) -and (Free ($script:P + 1)))
    do { $script:Q = $rand.Next(41000, 48000) } until ([Math]::Abs($script:Q - $script:P) -gt 2 -and
                                                        (Free $script:Q) -and (Free ($script:Q + 1)))
}

$work  = Join-Path ([IO.Path]::GetTempPath()) ('ts-swap-' + [Guid]::NewGuid().ToString('N'))
$root   = Join-Path $work 'Thornswood-Server'
$other  = Join-Path $work 'Thornswood-Server-Other'
$pidLog = Join-Path $work 'pids.txt'
$stub   = Join-Path $work 'stub.js'
$bob    = "Bob's Armour - Extra.esp"
$utf8   = New-Object Text.UTF8Encoding($false)

function Put([string]$path, [string]$text, [switch]$Bom) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding([bool]$Bom)))
}
function Sha([string]$text) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { return (($h.ComputeHash($utf8.GetBytes($text)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $h.Dispose() }
}
function SettingsJson([string]$forRoot, [int]$port, [string[]]$names) {
    $far = ($forRoot -replace '\\', '/') + '/plugins/'
    return ([ordered]@{ port = $port; name = 'Thornswood Test'; loadOrder = @($names | ForEach-Object { $far + $_ }) } |
            ConvertTo-Json -Depth 5)
}
function Tree([string]$dir) {
    $rows = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force)) {
        if ($f.Name -eq 'server.log') { continue }
        $rows += ($f.FullName.Substring($dir.Length) + '|' + (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash)
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $dir -Recurse -Directory -Force)) {
        $rows += ($d.FullName.Substring($dir.Length) + '|folder')
    }
    return (($rows | Sort-Object) -join "`n")
}
function Owner([int]$port) {
    $e = @(Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue)
    if ($e.Count) { return [int]$e[0].OwningProcess }
    return 0
}
function Answers([int]$port) {
    if (-not (Owner $port)) { return $false }
    $ok = $false
    try {
        $c = New-Object Net.Sockets.TcpClient
        $null = $c.BeginConnect('127.0.0.1', $port + 1, $null, $null).AsyncWaitHandle.WaitOne(500)
        $ok = $c.Connected
        $c.Close()
    } catch { }
    return $ok
}
function WaitUp([int]$port) {
    for ($i = 0; $i -lt 40; $i++) { if (Answers $port) { return $true }; Start-Sleep -Milliseconds 250 }
    return $false
}
function StartStub([string]$dir) {
    $p = Start-Process -FilePath $node.Source -WindowStyle Hidden -PassThru `
                       -ArgumentList ('"' + $stub + '" "' + $dir + '" "' + $pidLog + '"')
    return $p.Id
}

# What gets staged. Every argument is what a real deploy could get wrong.
function MakeStage {
    param([string]$Name, [string]$Gamemode = '// new gamemode', [int]$Port = $P,
          [string[]]$Order = @('Skyrim.esm', $bob, 'New Plugin.esp'),
          [switch]$Bom, [string]$RecordFor = 'new binary', [string]$SentGamemode = '')
    $dir = Join-Path $root $Name
    $files = [ordered]@{}
    $files['plugins/' + $bob]        = 'bob v2'
    $files['plugins/New Plugin.esp'] = 'brand new'
    $files['scam_native.node']       = 'new binary'
    $files['gamemode.js']            = $Gamemode
    $files['server-settings.json']   = SettingsJson $root $Port $Order
    $files['server-build.json']      = '{ "sha256": "' + (Sha $RecordFor) + '" }'
    # The build stamp Deploy-Gamemode leaves beside gamemode.js goes up in the
    # stage with it, so a rollback cannot leave a new stamp describing the old
    # gamemode. tests\test-build-stamp.ps1 leans on this harness for that.
    $files['thornswood-build.json']  = '{ "gamemode": "' + (Sha $Gamemode) + '" }'
    $want = [ordered]@{}
    foreach ($k in $files.Keys) {
        $path = Join-Path $dir ($k -replace '/', '\')
        Put $path $files[$k] -Bom:($Bom -and $k -eq 'server-settings.json')
        $want[$k] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    if ($SentGamemode) { $want['gamemode.js'] = Sha $SentGamemode }
    return $want
}

# The far side, as Deploy-Server sends it: SwapVars, then the block. The two
# task cmdlets are replaced in between, and nothing else is.
function RunFar([string]$block, [string]$stageName, [string]$prevName, [int]$wait, $want) {
    $mock = @"
function Stop-ScheduledTask { [CmdletBinding()] param([string]`$TaskName) }
function Start-ScheduledTask { [CmdletBinding()] param([string]`$TaskName)
  Start-Process -FilePath '$($node.Source)' -WindowStyle Hidden -ArgumentList '"$stub" "$root" "$pidLog"'
}

"@
    $body = (SwapVars $root 'Thornswood Test Swap' $stageName $prevName $wait $want) + $mock + $block
    $f = Join-Path $work ('far-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    [IO.File]::WriteAllText($f, $body, (New-Object Text.UTF8Encoding($true)))
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& $ps51 -NoProfile -ExecutionPolicy Bypass -File $f 2>&1 | ForEach-Object { "$_".Trim() }) }
    finally { $ErrorActionPreference = $eap }
    $script:lastFar = $out
    return $out
}
function Show {
    foreach ($l in $script:lastFar) { Write-Host ('        ' + $l) }
}

$stubJs = @'
// A stand-in for skymp5-server: the game port on UDP, the resources port on
// TCP (3000 for 7777, otherwise the game port plus one), both on 127.0.0.1 so
// no firewall prompt comes up. A gamemode saying will-not-start dies on start;
// one saying udp-only holds the game port and never opens the resources port.
const fs = require('fs');
const path = require('path');
const dgram = require('dgram');
const net = require('net');
const root = process.argv[2];
fs.appendFileSync(process.argv[3], process.pid + '\n');
function log(m) { fs.appendFileSync(path.join(root, 'server.log'), m + '\n'); }
const gm = fs.readFileSync(path.join(root, 'gamemode.js'), 'utf8');
if (gm.indexOf('will-not-start') >= 0) { log('Error: this gamemode will not start'); process.exit(1); }
const s = JSON.parse(fs.readFileSync(path.join(root, 'server-settings.json'), 'utf8'));
const res = s.port === 7777 ? 3000 : s.port + 1;
dgram.createSocket('udp4').bind(s.port, '127.0.0.1');
if (gm.indexOf('udp-only') < 0) { net.createServer(function (c) { c.end(); }).listen(res, '127.0.0.1'); }
log('listening on ' + s.port + (gm.indexOf('udp-only') < 0 ? ' and ' + res : ' only'));
// Gone when the harness clears its scratch folder, and after ten minutes
// whatever happens, so a harness that is killed part way leaves nothing.
// Not a short fixed life. It was three minutes, and in a sweep of every
// harness on a busy machine the other server's stub was gone before the good
// deploy ran, with only one 'stopped pid' line from the stop, so the deploy
// had not touched it and the timer is what ended it.
setInterval(function () { if (!fs.existsSync(root)) { process.exit(0); } }, 1000);
setTimeout(function () { process.exit(0); }, 600000);
'@

try {
    Put $stub $stubJs
    Put (Join-Path $root 'scam_native.node') 'old binary'
    Put (Join-Path $root 'gamemode.js') '// old gamemode'
    Put (Join-Path $root 'server-build.json') ('{ "sha256": "' + (Sha 'old binary') + '" }')
    Put (Join-Path $root 'thornswood-build.json') ('{ "gamemode": "' + (Sha '// old gamemode') + '" }')
    Put (Join-Path $root 'plugins\Skyrim.esm') 'skyrim'
    Put (Join-Path $root ('plugins\' + $bob)) 'bob v1'
    Put (Join-Path $root 'data\keep.txt') 'the character book'
    Put (Join-Path $root 'world\w.txt') 'every character'
    Put (Join-Path $other 'gamemode.js') '// the other server'

    # A port that looks free can still be one Windows has reserved, and a bind
    # there fails. A few goes rather than a flaky harness.
    $up = $false
    for ($try = 0; $try -lt 5 -and -not $up; $try++) {
        PickPorts
        Put (Join-Path $root 'server-settings.json') (SettingsJson $root $P @('Skyrim.esm', $bob))
        Put (Join-Path $other 'server-settings.json') (SettingsJson $other $Q @('Skyrim.esm'))
        $oldPid = StartStub $root
        $otherPid = StartStub $other
        $up = (WaitUp $P) -and (WaitUp $Q)
        if (-not $up) { Stop-Process -Id $oldPid, $otherPid -Force -EA SilentlyContinue }
    }
    Yes "the stand-in server is answering on UDP $P and TCP $($P + 1), and the other one on $Q and $($Q + 1)" $up
    if (-not $up) { throw 'no stand-in server came up, so there is nothing to deploy over' }
    $before = Tree $root

    # ---- refusals: nothing stops, nothing moves ------------------------------
    $n = 0
    foreach ($case in @(
        @{ Label = 'a load order naming a plugin that is nowhere'; Why = 'not on disk: .*Nowhere\.esp';
           Args = @{ Order = @('Skyrim.esm', $bob, 'New Plugin.esp', 'Nowhere.esp') } },
        @{ Label = 'a port that moves'; Why = ('on port ' + ($P + 5) + ' and it is on ' + $P);
           Args = @{ Port = ($P + 5) } },
        @{ Label = 'a file that arrived different'; Why = 'arrived different from what was sent: gamemode\.js';
           Args = @{ SentGamemode = '// what left the laptop' } },
        @{ Label = 'settings with a byte order mark'; Why = 'byte order mark';
           Args = @{ Bom = $true } },
        @{ Label = 'a binary that is not the recorded build'; Why = 'not the build server-build\.json records';
           Args = @{ RecordFor = 'some other binary' } },
        @{ Label = 'a gamemode that does not parse'; Why = 'gamemode\.js does not parse';
           Args = @{ Gamemode = 'function ( { this is not javascript' } }
    )) {
        $n++
        $stageName = '.stage-20260924-00010' + $n
        $a = $case.Args
        $w = MakeStage -Name $stageName @a
        $failed = $script:fail
        $out = RunFar $checkBlock $stageName '.prev-unused' 4 $w
        $label = $case.Label
        Yes "$label is refused" (($out -contains 'STAGE REFUSED') -and ($out -notcontains 'STAGE OK'))
        Yes "  and it says why" (($out -join "`n") -match $case.Why)
        Yes "  and the stage is cleared, leaving the live folder as it was" ((Tree $root) -eq $before)
        Yes "  and the server was never stopped" (((Owner $P) -eq $oldPid) -and (Answers $P))
        if ($script:fail -gt $failed) { Show }
    }

    # ---- a new server that hangs on its game port ----------------------------
    $w = MakeStage -Name '.stage-20260924-000201' -Gamemode '// new gamemode, udp-only'
    $out = RunFar $checkBlock '.stage-20260924-000201' '.prev-20260924-000201' 4 $w
    Yes 'a good stage checks out' ($out -contains 'STAGE OK')
    Yes '  and checking it stopped nothing' (((Owner $P) -eq $oldPid) -and (Answers $P))
    $failed = $script:fail
    $out = RunFar $swapBlock '.stage-20260924-000201' '.prev-20260924-000201' 4 $w
    $said = $out -join "`n"
    Yes 'a new server that holds its game port and never opens the resources port is SWAP ROLLED BACK' ($out -contains 'SWAP ROLLED BACK')
    Yes '  and it says FAIL, naming both ports' ($said -match ('FAIL: nothing answered on UDP ' + $P + ' and ' + ($P + 1)))
    Yes '  and the old server was stopped by its port' ($out -contains ('stopped pid ' + $oldPid))
    Yes '  and so was the new one that hung' (@($out | Where-Object { $_ -like 'stopped pid *' }).Count -ge 2)
    Yes '  and every live file is back as it was, with no stage or .prev left' ((Tree $root) -eq $before)
    Yes '  and the old server is answering again, as a new process' ((WaitUp $P) -and ((Owner $P) -ne $oldPid))
    Yes '  and the other server was never touched' (((Owner $Q) -eq $otherPid) -and (Answers $Q))
    if ($script:fail -gt $failed) { Show }

    # ---- a new server that dies on start -------------------------------------
    $running = Owner $P
    $w = MakeStage -Name '.stage-20260924-000301' -Gamemode '// new gamemode, will-not-start'
    $out = RunFar $checkBlock '.stage-20260924-000301' '.prev-20260924-000301' 4 $w
    $failed = $script:fail
    $out = RunFar $swapBlock '.stage-20260924-000301' '.prev-20260924-000301' 4 $w
    $said = $out -join "`n"
    Yes 'a new server that dies on start is SWAP ROLLED BACK' ($out -contains 'SWAP ROLLED BACK')
    Yes '  and the tail of server.log shows why' ($said -match 'this gamemode will not start')
    Yes '  and every live file is back as it was' ((Tree $root) -eq $before)
    Yes '  and the old server is answering again' ((WaitUp $P) -and ((Owner $P) -ne $running))
    Yes '  and the other server was never touched' ((Owner $Q) -eq $otherPid)
    if ($script:fail -gt $failed) { Show }

    # ---- a good deploy -------------------------------------------------------
    foreach ($old in 1..4) { Put (Join-Path $root ('.prev-20000101-00000' + $old + '\gamemode.js')) '// long ago' }
    $running = Owner $P
    $w = MakeStage -Name '.stage-20260924-000401'
    $out = RunFar $checkBlock '.stage-20260924-000401' '.prev-20260924-000401' 30 $w
    $failed = $script:fail
    $out = RunFar $swapBlock '.stage-20260924-000401' '.prev-20260924-000401' 30 $w
    $said = $out -join "`n"
    Yes 'a good deploy is SWAP OK' ($out -contains 'SWAP OK')
    Yes '  and says PASS from the resources port' ($said -match ('PASS: the server is answering on ' + ($P + 1) + ', game port ' + $P))
    $allIn = $true
    foreach ($k in $w.Keys) {
        $at = Join-Path $root ($k -replace '/', '\')
        if (-not (Test-Path -LiteralPath $at) -or
            (Get-FileHash -LiteralPath $at -Algorithm SHA256).Hash.ToLowerInvariant() -ne $w[$k]) { $allIn = $false }
    }
    Yes '  and every staged file is in place, the new plugin and the changed one with them' $allIn
    $prev = Join-Path $root '.prev-20260924-000401'
    Yes '  and what it replaced is kept in .prev, and a plugin that is new has nothing there' (
        ([IO.File]::ReadAllText((Join-Path $prev 'scam_native.node')) -eq 'old binary') -and
        ([IO.File]::ReadAllText((Join-Path $prev 'gamemode.js')) -eq '// old gamemode') -and
        ([IO.File]::ReadAllText((Join-Path $prev 'thornswood-build.json')) -match (Sha '// old gamemode')) -and
        ([IO.File]::ReadAllText((Join-Path $prev ('plugins\' + $bob))) -eq 'bob v1') -and
        -not (Test-Path -LiteralPath (Join-Path $prev 'plugins\New Plugin.esp')))
    Yes '  and the stage is gone' (-not (Test-Path -LiteralPath (Join-Path $root '.stage-20260924-000401')))
    $kept = @(Get-ChildItem -LiteralPath $root -Directory -Force | Where-Object { $_.Name -like '.prev-*' } |
              Sort-Object Name | ForEach-Object { $_.Name })
    Yes '  and the newest two .prev folders are kept, not three (#1121)' (
        ($kept -join ',') -eq '.prev-20000101-000004,.prev-20260924-000401')
    Yes '  and the world and the data folder are untouched' (
        ([IO.File]::ReadAllText((Join-Path $root 'data\keep.txt')) -eq 'the character book') -and
        ([IO.File]::ReadAllText((Join-Path $root 'world\w.txt')) -eq 'every character'))
    Yes '  and the server answering is the new one' ((Answers $P) -and ((Owner $P) -ne $running))
    Yes '  and the other server was never touched' (((Owner $Q) -eq $otherPid) -and (Answers $Q))
    if ($script:fail -gt $failed) { Show }

    # ---- -PutBack: the newest .prev goes back in, checked -------------------
    # Issue #446. Deploy-Server.ps1 -PutBack sends SwapVars with no files, then
    # $putBackPick, which makes the newest .prev folder the stage, then the
    # same swap block.
    $afterGood = Tree $root
    $running = Owner $P
    $failed = $script:fail
    $out = RunFar ($putBackPick + $swapBlock) '.stage-none' '.undone-none' 30 ([ordered]@{})
    $said = $out -join "`n"
    Yes '-PutBack is SWAP OK' ($out -contains 'SWAP OK')
    Yes '  and it named the .prev folder it put back' ($said -match [regex]::Escape('.prev-20260924-000401 kept'))
    Yes '  and the old binary, gamemode, stamp and plugin are live again' (
        ([IO.File]::ReadAllText((Join-Path $root 'scam_native.node')) -eq 'old binary') -and
        ([IO.File]::ReadAllText((Join-Path $root 'gamemode.js')) -eq '// old gamemode') -and
        ([IO.File]::ReadAllText((Join-Path $root 'thornswood-build.json')) -match (Sha '// old gamemode')) -and
        ([IO.File]::ReadAllText((Join-Path $root ('plugins\' + $bob))) -eq 'bob v1'))
    $undone = @(Get-ChildItem -LiteralPath $root -Directory -Force | Where-Object { $_.Name -like '.undone-*' })
    Yes '  and what it took out is kept in one .undone folder' (
        $undone.Count -eq 1 -and
        ([IO.File]::ReadAllText((Join-Path $undone[0].FullName 'gamemode.js')) -eq '// new gamemode'))
    Yes '  and the .prev folder it emptied is gone, the older one kept' (
        -not (Test-Path -LiteralPath (Join-Path $root '.prev-20260924-000401')) -and
        (Test-Path -LiteralPath (Join-Path $root '.prev-20000101-000004')))
    Yes '  and a plugin the deploy added stays, since nothing came before it' (
        Test-Path -LiteralPath (Join-Path $root 'plugins\New Plugin.esp'))
    Yes '  and the server answering is a new process, on the old files' ((Answers $P) -and ((Owner $P) -ne $running))
    Yes '  and the other server was never touched' (((Owner $Q) -eq $otherPid) -and (Answers $Q))
    if ($script:fail -gt $failed) { Show }

    # ---- a put-back whose old files do not start ----------------------------
    Put (Join-Path $root '.prev-20990101-000001\gamemode.js') '// the kept one, will-not-start'
    Put (Join-Path $root '.prev-20990101-000001\server-settings.json') (SettingsJson $root $P @('Skyrim.esm', $bob))
    $beforeBack = Tree $root
    $running = Owner $P
    $failed = $script:fail
    $out = RunFar ($putBackPick + $swapBlock) '.stage-none' '.undone-none' 4 ([ordered]@{})
    Yes 'a put-back whose files do not start is SWAP ROLLED BACK' ($out -contains 'SWAP ROLLED BACK')
    Yes '  and what was running is back, and the .prev folder is kept full, as it was' ((Tree $root) -eq $beforeBack)
    Yes '  and the server is answering again' ((WaitUp $P) -and ((Owner $P) -ne $running))
    Yes '  and the other server was never touched' ((Owner $Q) -eq $otherPid)
    if ($script:fail -gt $failed) { Show }

    # ---- nothing to put back --------------------------------------------------
    $empty = Join-Path $work 'no-prev-root'
    Put (Join-Path $empty 'gamemode.js') '// nothing kept'
    $pre = SwapVars $empty 'Thornswood Test Swap' '.stage-none' '.undone-none' 4 ([ordered]@{})
    $f = Join-Path $work 'far-empty.ps1'
    [IO.File]::WriteAllText($f, ($pre + $putBackPick + $swapBlock), (New-Object Text.UTF8Encoding($true)))
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& $ps51 -NoProfile -ExecutionPolicy Bypass -File $f 2>&1 | ForEach-Object { "$_".Trim() }) }
    finally { $ErrorActionPreference = $eap }
    Yes 'a root with no .prev folder is SWAP REFUSED, and stops nothing' (
        ($out -contains 'SWAP REFUSED') -and ($out -notcontains 'SWAP OK') -and
        -not (@($out | Where-Object { $_ -like 'stopped pid *' }).Count))
}
catch {
    Yes ('the runs finished without an error: ' + $_.Exception.Message) $false
}
finally {
    # Only the stubs this run started, by pid and by their command line, so a
    # pid Windows has handed to something else since is left alone.
    if (Test-Path -LiteralPath $pidLog) {
        foreach ($id in @(Get-Content -LiteralPath $pidLog)) {
            $proc = Get-CimInstance Win32_Process -Filter ("ProcessId = " + [int]$id) -EA SilentlyContinue
            if ($proc -and $proc.CommandLine -and $proc.CommandLine.Contains($work)) {
                Stop-Process -Id ([int]$id) -Force -EA SilentlyContinue
            }
        }
    }
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}

Done
