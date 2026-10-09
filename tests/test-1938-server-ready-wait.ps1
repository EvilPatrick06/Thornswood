<#
  test-1938-server-ready-wait.ps1

      pwsh -NoProfile -File .\tests\test-1938-server-ready-wait.ps1

  A healthy game server start that takes more than 60 s is kept, and a start
  that never answers still rolls back when the ceiling is reached.

  WHY. Deploy-Server, Deploy-DevGamemode, Publish-Server and
  Install-ThornswoodServer each defaulted -Wait to 60. Swap.ps1's Answering
  (and the installer's Answers) wait for both ports: UDP on the game port and
  TCP on the resources port, which opens only once the native server has been
  built without throwing. That is the right signal. The 60 s ceiling was not
  derived from how long a start takes. On 5 Oct Live took 66 s from start to
  both ports answering, so a healthy deploy was rolled back. Dev has taken
  113 s.

  HOW.
    1. Read, not run, wherever PowerShell runs: one file holds the measured
       starts and the derived ceiling (half again the worst of them). The
       four scripts take that ceiling when -Wait is omitted, and the swap
       block waits on $Wait rather than a literal 60.
    2. On Windows, with node, the real swap block is run against a scratch
       folder and a stub that holds the ports the way skymp5-server does:
         - a start that never opens the resources port is SWAP ROLLED BACK
           in about the passed ceiling, not the old 60 s and not forever
         - a start that opens the resources port after 61 s, past the old
           60 s wait, is SWAP OK when the ceiling is the shared one

  Connects to nothing but 127.0.0.1.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$Deploy = Join-Path $Repo 'scripts\deploy'
$WaitLib = Join-Path $Deploy 'ServerReadyWait.ps1'
$SwapLib = Join-Path $Deploy 'Swap.ps1'

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

Yes 'ServerReadyWait.ps1 and Swap.ps1 are there' (
    (Test-Path -LiteralPath $WaitLib) -and (Test-Path -LiteralPath $SwapLib))

. $WaitLib
$measuredWorst = [Math]::Max($ThornswoodServerReadyLiveSeconds, $ThornswoodServerReadyDevSeconds)
$derived = [int][Math]::Ceiling($measuredWorst * 1.5)
Yes 'the Live 5 Oct start (66 s) and the Dev start (113 s) are the recorded times' (
    $ThornswoodServerReadyLiveSeconds -eq 66 -and $ThornswoodServerReadyDevSeconds -eq 113)
Yes 'the shared ceiling is half again the worst of those, and past 60 s' (
    $ThornswoodServerReadyWaitSeconds -eq $derived -and
    (Get-ThornswoodServerReadyWait) -eq $derived -and
    $derived -gt 60 -and $derived -ge 113 -and $derived -eq 170)
Yes 'ServerReadyWait.ps1 is plain ASCII, which the box reads right' (
    ([IO.File]::ReadAllText($WaitLib)) -notmatch '[^\x00-\x7F]')

$swapText = [IO.File]::ReadAllText($SwapLib)
Yes 'Swap.ps1 loads the shared wait, and Answering waits $Wait seconds not a literal 60' (
    $swapText.Contains(". (Join-Path `$PSScriptRoot 'ServerReadyWait.ps1')") -and
    $swapText.Contains('(Get-Date).AddSeconds($Wait)') -and
    $swapText -notmatch 'AddSeconds\(\s*60\s*\)')

$callers = @(
    'scripts\deploy\Deploy-Server.ps1',
    'scripts\deploy\Deploy-DevGamemode.ps1',
    'scripts\deploy\Install-ThornswoodServer.ps1',
    'scripts\release\Publish-Server.ps1'
)
foreach ($rel in $callers) {
    $t = [IO.File]::ReadAllText((Join-Path $Repo $rel))
    Yes ("{0} takes the shared ceiling when -Wait is omitted" -f $rel) (
        $t.Contains("if (-not `$PSBoundParameters.ContainsKey('Wait'))") -and
        $t.Contains('$Wait = Get-ThornswoodServerReadyWait') -and
        $t -notmatch '\[int\]\$Wait\s*=\s*60')
}

$inst = [IO.File]::ReadAllText((Join-Path $Deploy 'Install-ThornswoodServer.ps1'))
Yes 'the installer Answers with $Wait as well, not a literal 60' (
    $inst.Contains('(Get-Date).AddSeconds($Wait)') -and
    $inst -notmatch 'AddSeconds\(\s*60\s*\)' -and
    $inst.Contains("Join-Path `$here 'ServerReadyWait.ps1'"))

$pub = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\release\Publish-Server.ps1'))
Yes 'Publish-Server sends ServerReadyWait.ps1 beside the installer, and refuses to send an uncommitted copy' (
    $pub.Contains("scp @ssh `$waitLib `"`${target}:C:/ServerReadyWait.ps1`"") -and
    $pub.Contains("'scripts/deploy/ServerReadyWait.ps1'") -and
    ([regex]::Matches($pub, 'C:/ServerReadyWait\.ps1')).Count -eq 2)

# ---- run, against a scratch folder ------------------------------------------
$node = Get-Command node -EA SilentlyContinue
$ps51 = $null
if ($env:SystemRoot) {
    $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}
if (-not $node -or -not $ps51 -or -not (Test-Path -LiteralPath $ps51) -or
    -not (Get-Command Get-NetUDPEndpoint -EA SilentlyContinue)) {
    Write-Host 'SKIP  the runs need node, Windows PowerShell 5.1 and Get-NetUDPEndpoint, and this machine lacks one'
    Done
}

. $SwapLib
Yes 'Swap.ps1 gives SwapVars and the swap block' (
    [bool]$swapBlock -and [bool](Get-Command SwapVars -EA SilentlyContinue))

$rand = New-Object Random
function Free([int]$p) {
    (-not @(Get-NetUDPEndpoint -LocalPort $p -EA SilentlyContinue).Count) -and
    (-not @(Get-NetTCPConnection -LocalPort $p -EA SilentlyContinue).Count)
}
function PickPort {
    do { $script:P = $rand.Next(41000, 48000) } until ((Free $script:P) -and (Free ($script:P + 1)))
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-1938-' + [Guid]::NewGuid().ToString('N'))
$root = Join-Path $work 'Thornswood-Server'
$pidLog = Join-Path $work 'pids.txt'
$stub = Join-Path $work 'stub.js'
$utf8 = New-Object Text.UTF8Encoding($false)

function Put([string]$path, [string]$text) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text, $utf8)
}
function Sha([string]$text) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { return (($h.ComputeHash($utf8.GetBytes($text)) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $h.Dispose() }
}
function SettingsJson([int]$port) {
    return (@{ port = $port; name = 'Thornswood Test'; loadOrder = @('Skyrim.esm') } | ConvertTo-Json -Compress)
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
function MakeStage([string]$name, [string]$gamemode) {
    $dir = Join-Path $root $name
    $files = [ordered]@{
        'gamemode.js'          = $gamemode
        'server-settings.json' = (SettingsJson $script:P)
    }
    $want = [ordered]@{}
    foreach ($k in $files.Keys) {
        $path = Join-Path $dir ($k -replace '/', '\')
        Put $path $files[$k]
        $want[$k] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $want
}
function RunFar([string]$stageName, [string]$prevName, [int]$wait, $want) {
    $mock = @"
function Get-ScheduledTask { [CmdletBinding()] param([string]`$TaskName) }
function Set-ScheduledTask { [CmdletBinding()] param([Parameter(ValueFromPipeline = `$true)]`$InputObject) }
function Stop-ScheduledTask { [CmdletBinding()] param([string]`$TaskName) }
function Start-ScheduledTask { [CmdletBinding()] param([string]`$TaskName)
  Start-Process -FilePath '$($node.Source)' -WindowStyle Hidden -ArgumentList '"$stub" "$root" "$pidLog"'
}

"@
    $body = (SwapVars $root 'Thornswood Test 1938' $stageName $prevName $wait $want) + $mock + $swapBlock
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
const fs = require('fs');
const path = require('path');
const dgram = require('dgram');
const net = require('net');
const root = process.argv[2];
fs.appendFileSync(process.argv[3], process.pid + '\n');
function log(m) { fs.appendFileSync(path.join(root, 'server.log'), m + '\n'); }
const gm = fs.readFileSync(path.join(root, 'gamemode.js'), 'utf8');
const s = JSON.parse(fs.readFileSync(path.join(root, 'server-settings.json'), 'utf8'));
const res = s.port === 7777 ? 3000 : s.port + 1;
dgram.createSocket('udp4').bind(s.port, '127.0.0.1');
function listen() { net.createServer(function (c) { c.end(); }).listen(res, '127.0.0.1'); }
if (gm.indexOf('udp-only') >= 0) {
  log('listening on ' + s.port + ' only');
} else if (gm.indexOf('slow-start-past-60') >= 0) {
  setTimeout(listen, 61000);
  log('listening on ' + s.port + ', resources after 61 s');
} else {
  listen();
  log('listening on ' + s.port + ' and ' + res);
}
setInterval(function () { if (!fs.existsSync(root)) { process.exit(0); } }, 1000);
setTimeout(function () { process.exit(0); }, 600000);
'@

try {
    Put $stub $stubJs
    Put (Join-Path $root 'gamemode.js') '// old gamemode'
    Put (Join-Path $root 'plugins\Skyrim.esm') 'skyrim'
    $up = $false
    $oldPid = 0
    for ($try = 0; $try -lt 5 -and -not $up; $try++) {
        PickPort
        Put (Join-Path $root 'server-settings.json') (SettingsJson $P)
        $oldPid = (Start-Process -FilePath $node.Source -WindowStyle Hidden -PassThru `
                                 -ArgumentList ('"' + $stub + '" "' + $root + '" "' + $pidLog + '"')).Id
        $up = WaitUp $P
        if (-not $up) { Stop-Process -Id $oldPid -Force -EA SilentlyContinue }
    }
    Yes ("the stand-in server is answering on UDP {0} and TCP {1}" -f $P, ($P + 1)) $up
    if (-not $up) { throw 'no stand-in server came up, so there is nothing to deploy over' }
    $before = (Get-FileHash -LiteralPath (Join-Path $root 'gamemode.js') -Algorithm SHA256).Hash

    # A start that never becomes ready still rolls back within the ceiling.
    $w = MakeStage '.stage-never' '// new gamemode, udp-only'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = RunFar '.stage-never' '.prev-never' 4 $w
    $sw.Stop()
    $said = $out -join "`n"
    $failed = $script:fail
    Yes 'a start that never opens the resources port is SWAP ROLLED BACK' ($out -contains 'SWAP ROLLED BACK')
    Yes '  and it says FAIL, naming both ports and the 4 s ceiling' (
        $said -match ('FAIL: nothing answered on UDP ' + $P + ' and ' + ($P + 1) + ' within 4 seconds'))
    Yes ("  and the swap finished in {0:n1} s, within the 4 s ceiling plus the put-back, not the old 60 s" -f $sw.Elapsed.TotalSeconds) (
        $sw.Elapsed.TotalSeconds -lt 50 -and $sw.Elapsed.TotalSeconds -ge 3)
    Yes '  and the old gamemode is back' (
        (Get-FileHash -LiteralPath (Join-Path $root 'gamemode.js') -Algorithm SHA256).Hash -eq $before)
    Yes '  and the old server is answering again' (WaitUp $P)
    if ($script:fail -gt $failed) { Show }

    # A slow-but-healthy start past 60 s is kept.
    $running = Owner $P
    $w = MakeStage '.stage-slow' '// new gamemode, slow-start-past-60'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $out = RunFar '.stage-slow' '.prev-slow' (Get-ThornswoodServerReadyWait) $w
    $sw.Stop()
    $said = $out -join "`n"
    $failed = $script:fail
    Yes 'a start that answers after 61 s, past the old 60 s wait, is SWAP OK' ($out -contains 'SWAP OK')
    Yes '  and says PASS from the resources port' (
        $said -match ('PASS: the server is answering on ' + ($P + 1) + ', game port ' + $P))
    Yes ("  and that wait took {0:n1} s, past 60 s and inside the shared ceiling" -f $sw.Elapsed.TotalSeconds) (
        $sw.Elapsed.TotalSeconds -ge 60 -and $sw.Elapsed.TotalSeconds -lt (Get-ThornswoodServerReadyWait))
    Yes '  and the new gamemode is the one answering' (
        ([IO.File]::ReadAllText((Join-Path $root 'gamemode.js'))) -match 'slow-start-past-60' -and
        (Answers $P) -and ((Owner $P) -ne $running))
    if ($script:fail -gt $failed) { Show }
}
catch {
    Yes ('the runs finished without an error: ' + $_.Exception.Message) $false
}
finally {
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
