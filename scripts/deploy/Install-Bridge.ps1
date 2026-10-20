<#
  Install-Bridge.ps1

  Puts the box's end of ssh from cloud Claude threads on the VPS (#2753):
  scripts\vps\bridge\bridge.js, as the task "Thornswood Bridge", listening on
  127.0.0.1:7790. Caddy hands wss://thornswood.net/box/ to it (the
  handle_path /box/* block in scripts\deploy\Caddyfile, sent by
  Setup-Domain.ps1), and it joins each WebSocket that brings its token to the
  box's own sshd on 127.0.0.1:22. Run it from a machine whose key already
  works; it does the remote half over ssh.

      .\scripts\deploy\Install-Bridge.ps1            install it, or the newest
                                                     commit of it, and start it
      .\scripts\deploy\Install-Bridge.ps1 -Status    what is there and its log
      .\scripts\deploy\Install-Bridge.ps1 -Remove    take it off again

  Nobody gets through it until scripts\vps\New-CloudAccess.ps1 has written
  its token (token.txt in -Root) and put the cloud key on the box. With no
  token.txt every WebSocket is refused, and New-CloudAccess.ps1 -Remove takes
  both away again.

  WHAT IT RUNS AS. LOCAL SERVICE, Limited, with a SID of its own, like voice
  and Caddy (#2578, ServiceAccount.ps1), after the same fail-safe. The folder
  takes nothing from C:\: SYSTEM, Administrators and whoever runs this, plus
  the task's own SID to read it and write its log, so no other service, all
  LOCAL SERVICE too, can read the token. -AsSystem registers it as SYSTEM,
  Highest, the way back if LOCAL SERVICE cannot run it.

  WHAT IT SENDS. A commit or nothing (Artifact.ps1, #459, #1121): bridge.js,
  ws.js and Server-Log.js out of HEAD, checked against the commit
  (Assert-ThornswoodSourceIntegrity) before anything is sent. They go into
  -Root\.stage-<stamp>, are checked there by hash and node --check with the
  bridge still running, and only then is it stopped and they are renamed in;
  what they replace goes to .prev-<stamp>. If the new one does not answer,
  the old files and the old task go back and are started.

  THE LOG. bridge.log, one line per session (opened, ended, how long, how
  many bytes), no address and nothing from inside the session, written by
  server-log.js with a time on each line and kept for 90 days, the same as
  voice.log (#2166).
#>
[CmdletBinding()]
param(
    [string]$VpsHost  = '',
    [string]$VpsUser  = '',
    [string]$Root     = 'C:\Thornswood-Bridge',
    [int]$Port        = 7790,
    [string]$TaskName = 'Thornswood Bridge',
    # The address the outside check asks. The bridge answers a plain request
    # with "box bridge: not here", which the site never says (its own 404 is
    # "not here"), so that answer through here is the bridge and Caddy
    # carrying it (#2875).
    [string]$Site     = 'https://thornswood.net',
    [int]$Wait        = 20,
    [switch]$Status,
    [switch]$Remove,
    [switch]$AsSystem,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
# The bridge's answer to a plain request, the same line as PLAIN in bridge.js.
$Plain = 'box bridge: not here'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here '..\vps\Vps.ps1')
. (Join-Path $Here '..\vps\Send-Script.ps1')
. (Join-Path $Here 'ServiceAccount.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }

function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
foreach ($t in 'ssh', 'scp') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client."
    }
}
if ($Status -and $Remove) { Die '-Status only reads and -Remove takes it off, so pass one of them. Nothing was sent.' }

function Remote($script) {
    # Send-Script.ps1 (issue #1070): a long script goes as a file of its own
    # name, removed after, and the far side's exit code comes back.
    return Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script $script
}

$log = Join-Path $Root 'bridge.log'

# ------------------------------------------------------------------ status --
if ($Status) {
    Head 'On the VPS'
    Remote @"
`$ErrorActionPreference = 'SilentlyContinue'
`$t = Get-ScheduledTask -TaskName '$TaskName'
if (`$t) { `$i = Get-ScheduledTaskInfo -TaskName '$TaskName'; 'task      ' + `$t.State + ' as ' + `$t.Principal.UserId + ', last ran ' + `$i.LastRunTime + ' result ' + `$i.LastTaskResult } else { 'task      NOT REGISTERED' }
# Whether a token is there, never what it is.
if (Test-Path -LiteralPath '$Root\token.txt') { 'token     there, so New-CloudAccess.ps1 has run' } else { 'token     NOT THERE, so every WebSocket is refused' }
try { Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:$Port/' -TimeoutSec 5 | Out-Null; 'port      $Port answered 200, which the bridge never says' }
catch {
    if ("`$(`$_.ErrorDetails.Message)".Trim() -eq '$Plain') { 'port      $Port answers as the bridge' }
    elseif (`$_.Exception.Response) { 'port      $Port answered ' + [int]`$_.Exception.Response.StatusCode + ' but not as the bridge: ' + "`$(`$_.ErrorDetails.Message)".Trim() }
    else { 'port      $Port did not answer: ' + `$_.Exception.Message }
}
if (Test-Path -LiteralPath '$log') { ''; '--- bridge.log, last 15 ---'; Get-Content -LiteralPath '$log' -Tail 15 }
"@ | ForEach-Object { Say "  $_" }
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# The task, then anything of ours still running: server-log.js names
# bridge.log on its command line, and bridge.js is its child.
$stopIt = @"
function StopIt {
    Stop-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue
    `$all = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" -EA SilentlyContinue)
    `$mine = @(`$all | Where-Object { `$_.CommandLine -and `$_.CommandLine -like ('*' + '$log' + '*') })
    foreach (`$p in `$mine) {
        foreach (`$c in @(`$all | Where-Object { `$_.ParentProcessId -eq `$p.ProcessId })) { Stop-Process -Id `$c.ProcessId -Force -EA SilentlyContinue }
        Stop-Process -Id `$p.ProcessId -Force -EA SilentlyContinue
    }
    if (`$mine.Count) { 'stopped ' + `$mine.Count + ' bridge process(es)' }
    for (`$i = 0; `$i -lt 20; `$i++) {
        if (-not (Get-NetTCPConnection -State Listen -LocalPort $Port -EA SilentlyContinue)) { return `$true }
        Start-Sleep -Milliseconds 500
    }
    'something is still listening on port $Port and would not let go'
    return `$false
}
"@

# ------------------------------------------------------------------ remove --
if ($Remove) {
    Head 'Removing'
    $out = @(Remote @"
$stopIt
`$null = StopIt
Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false -EA SilentlyContinue
Remove-Item -LiteralPath '$Root' -Recurse -Force -EA SilentlyContinue
if (Get-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue) { 'STILL THERE' } elseif (Test-Path -LiteralPath '$Root') { 'FOLDER STILL THERE' } else { 'REMOVED' }
"@ | ForEach-Object { Say "  $_"; "$_".Trim() })
    if ($out -notcontains 'REMOVED') { Die 'it was not all taken off. The lines above say what is left.' }
    Say '  Gone, token and all. The cloud key on the box goes with scripts\vps\New-CloudAccess.ps1 -Remove.' 'Green'
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ----------------------------------------------------------------- build ----
# A commit or nothing (#1121), built before anything asks the box anything.
. (Join-Path $Here 'Artifact.ps1')
$repo = Join-Path $Here '..\..'
$artifact = New-ThornswoodArtifact -Component bridge -RepoDir $repo -Paths 'scripts/vps/bridge/bridge.js', 'scripts/vps/bridge/ws.js' -AlsoSends 'scripts/vps/Server-Log.js'
Say ('artifact ' + (Format-ThornswoodArtifact $artifact)) 'DarkGray'
Assert-ThornswoodSourceIntegrity -Artifact $artifact -RepoDir $repo
# The log writer is not in the zip: -AlsoSends only holds it to the commit,
# and it goes from the checkout, as Install-Voice.ps1 sends it.
$send = [ordered]@{
    'bridge.js'     = Join-Path $artifact.Folder 'scripts\vps\bridge\bridge.js'
    'ws.js'         = Join-Path $artifact.Folder 'scripts\vps\bridge\ws.js'
    'server-log.js' = Join-Path $Here '..\vps\Server-Log.js'
}
foreach ($k in $send.Keys) { if (-not (Test-Path -LiteralPath $send[$k])) { Die "not found: $($send[$k]). Nothing was sent." } }
$hashes = [ordered]@{}
foreach ($k in $send.Keys) { $hashes[$k] = (Get-FileHash -LiteralPath $send[$k] -Algorithm SHA256).Hash }
Send-ThornswoodArtifact -Artifact $artifact -Target $target -SshArgs $ssh

# ----------------------------------------------------------------- stage ----
Head 'Staging'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stage = '.stage-' + $stamp
$prev = '.prev-' + $stamp
$made = @(Remote @"
`$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath '$Root')) { New-Item -ItemType Directory -Path '$Root' -Force | Out-Null }
# Nothing from C:\: the token is in here (the header says why).
try {
  `$broad = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-19')
  `$acl = Get-Acl -LiteralPath '$Root'
  `$acl.SetAccessRuleProtection(`$true, `$false)
  foreach (`$r in @(`$acl.GetAccessRules(`$true, `$false, [Security.Principal.SecurityIdentifier]))) {
    if (`$broad -contains `$r.IdentityReference.Value) { [void]`$acl.RemoveAccessRuleSpecific(`$r) }
  }
  foreach (`$s in @('S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)) {
    `$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier(`$s)), 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
  }
  # Only the access rules are written back (issue #1120).
  (Get-Item -LiteralPath '$Root' -Force).SetAccessControl(`$acl)
} catch { 'COULD NOT LOCK: ' + `$_.Exception.Message; exit 1 }
Get-ChildItem -LiteralPath '$Root' -Directory -Force -EA SilentlyContinue | Where-Object { `$_.Name -like '.stage-*' } |
  ForEach-Object { Remove-Item -LiteralPath `$_.FullName -Recurse -Force -EA SilentlyContinue }
New-Item -ItemType Directory -Force -Path '$Root\$stage' | Out-Null
'READY'
"@ | ForEach-Object { "$_".Trim() })
if ($made -notcontains 'READY') { Die ("could not make $Root\$stage up there: " + ($made -join ' ') + '. The bridge was not touched.') }
$rootFar = $Root -replace '\\', '/'
foreach ($k in $send.Keys) {
    Invoke-ThornswoodNative { & scp @ssh $send[$k] "${target}:$rootFar/$stage/$k" }
    if ($LASTEXITCODE -ne 0) { Die "scp exited with $LASTEXITCODE for $k. The bridge was not touched." }
}
Say '  staged' 'Green'

# ---------------------------------------------------------------- install ---
Head 'Installing'
$want = ($hashes.Keys | ForEach-Object { "'$_' = '$($hashes[$_])'" }) -join '; '
$out = @(Remote @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$node = Get-Command node -EA SilentlyContinue
if (-not `$node) {
    `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    `$node = Get-Command node -EA SilentlyContinue
}
if (-not `$node) { 'node is not installed on this machine'; 'BRIDGE REFUSED'; exit 1 }
`$stage = '$Root\$stage'
`$want = [ordered]@{ $want }

# The stage, checked with the old bridge still running.
foreach (`$f in `$want.Keys) {
    `$p = Join-Path `$stage `$f
    if (-not (Test-Path -LiteralPath `$p) -or (Get-FileHash -LiteralPath `$p -Algorithm SHA256).Hash -ne `$want[`$f]) { `$f + ' did not arrive as it was sent'; 'BRIDGE REFUSED'; exit 1 }
}
foreach (`$f in 'bridge.js', 'ws.js', 'server-log.js') {
    `$said = & `$node.Source --check (Join-Path `$stage `$f) 2>&1
    if (`$LASTEXITCODE -ne 0) { `$f + ' does not parse: ' + (`$said -join ' '); 'BRIDGE REFUSED'; exit 1 }
}
'the stage checks out'

$(Get-ThornswoodServiceAccountScript)
`$AsSystem = [bool]$([int][bool]$AsSystem)
if (-not `$AsSystem) {
    `$cannot = @(Test-ThornswoodServiceCannotReach (@(Get-ThornswoodServiceNeverReach -Own '$Root' -Box (Split-Path -Parent '$Root')) + '$Root'))
    if (`$cannot.Count) {
        'LOCAL SERVICE could read what no service may, so the bridge is not put on it:'
        `$cannot
        'Lock those (scripts\vps\Lock-VpsFolders.ps1), or pass -AsSystem. Nothing was stopped or changed.'
        'BRIDGE REFUSED'; exit 1
    }
}

$stopIt

`$writer = Join-Path '$Root' 'server-log.js'
`$cmd = ('/c "set THORNSWOOD_BRIDGE_PORT=$Port&& start "" /b /wait "{0}" "{2}" --log "{1}" --days 90 --stamp bridge.js & call exit %^errorlevel%"' -f `$node.Source, '$log', `$writer)
`$oldXml = `$null
if (Get-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue) { `$oldXml = (Export-ScheduledTask -TaskName '$TaskName' | Out-String) }

# From here one error must not leave it half done.
`$ErrorActionPreference = 'Continue'

function Register([bool]`$system) {
    `$action = New-ScheduledTaskAction -Execute "`$env:SystemRoot\System32\cmd.exe" -Argument `$cmd -WorkingDirectory '$Root'
    # Priority 4, normal, not Task Scheduler's default of 7 (#1968).
    `$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -Priority 4
    if (Get-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue) { Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false }
    Register-ScheduledTask -TaskName '$TaskName' -Action `$action -Trigger (New-ScheduledTaskTrigger -AtStartup) -Settings `$settings -Principal (New-ThornswoodServicePrincipal -AsSystem:`$system) | Out-Null
}

# Whether the port answers a plain request with one of these lines, the
# bridge's 404. A status code alone would take any other server on the port
# for the bridge (#2875).
function Answers([string[]]`$Lines) {
    `$until = (Get-Date).AddSeconds($Wait)
    while ((Get-Date) -lt `$until) {
        try { Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:$Port/' -TimeoutSec 2 | Out-Null }
        catch {
            if (`$Lines -contains "`$(`$_.ErrorDetails.Message)".Trim()) { return `$true }
        }
        Start-Sleep -Milliseconds 700
    }
    return `$false
}

if (-not (StopIt)) { 'BRIDGE REFUSED'; exit 1 }
New-Item -ItemType Directory -Force -Path '$Root\$prev' | Out-Null
foreach (`$f in `$want.Keys) {
    `$live = Join-Path '$Root' `$f
    if (Test-Path -LiteralPath `$live) { Move-Item -LiteralPath `$live -Destination (Join-Path '$Root\$prev' `$f) -Force }
    Move-Item -LiteralPath (Join-Path `$stage `$f) -Destination `$live -Force
}
Remove-Item -LiteralPath `$stage -Recurse -Force -EA SilentlyContinue

Register `$AsSystem
if (-not `$AsSystem) {
    `$why = ''
    `$sid = Get-ThornswoodTaskSid '$TaskName'
    if (-not `$sid) { `$why = 'the task SID NT TASK\$TaskName could not be looked up' }
    else {
        try { `$null = Grant-ThornswoodServiceFolder -Root '$Root' -Sid `$sid -Files 'bridge.log', 'bridge.log.*' }
        catch { `$why = 'its folder could not be granted to it: ' + `$_.Exception.Message }
    }
    if (`$why) { `$why + ', so the task goes on SYSTEM'; Register `$true }
    else { 'the task runs as LOCAL SERVICE, Limited, as NT TASK\$TaskName' }
}
try { & `$node.Source `$writer --log '$log' --days 90 --roll } catch { 'could not roll bridge.log: ' + `$_.Exception.Message }
Start-ScheduledTask -TaskName '$TaskName'
if (Answers @('$Plain')) {
    'the bridge answers on 127.0.0.1:$Port'
    if (-not (Test-Path -LiteralPath '$Root\token.txt')) { 'there is no token.txt yet, so it refuses everybody until New-CloudAccess.ps1 runs' }
    'BRIDGE OK'; exit 0
}
'it did not answer on 127.0.0.1:$Port within $Wait seconds. bridge.log says:'
if (Test-Path -LiteralPath '$log') { Get-Content -LiteralPath '$log' -Tail 15 } else { 'nothing was written' }
`$null = StopIt
`$back = @(Get-ChildItem -LiteralPath '$Root\$prev' -File -EA SilentlyContinue)
foreach (`$f in `$back) { Move-Item -LiteralPath `$f.FullName -Destination (Join-Path '$Root' `$f.Name) -Force }
if (`$oldXml) {
    if (Get-ScheduledTask -TaskName '$TaskName' -EA SilentlyContinue) { Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false }
    Register-ScheduledTask -TaskName '$TaskName' -Xml `$oldXml | Out-Null
    Start-ScheduledTask -TaskName '$TaskName'
    # The old files may be from before #2875, when the bridge's 404 said only
    # "not here". Nothing but the bridge listens on this port, and the site's
    # own "not here" can only come through Caddy, never here.
    if (Answers @('$Plain', 'not here')) { 'the old files and task are back, and it answers again' } else { 'THE OLD FILES AND TASK ARE BACK AND IT STILL DOES NOT ANSWER' }
} else {
    Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false -EA SilentlyContinue
    'there was no bridge before this, so none is left registered'
}
'BRIDGE ROLLED BACK'; exit 1
"@ | ForEach-Object { Say "  $_"; "$_".Trim() })
if ($out -notcontains 'BRIDGE OK') { Die 'the bridge was not installed. The lines above say why and what is running.' }
$null = Set-ThornswoodArtifactCurrent -Artifact $artifact -Target $target -SshArgs $ssh -Root $Root

# ---------------------------------------------------------------- outside ---
Head 'Checking from here'
# A plain request through Caddy: the bridge says "box bridge: not here" with
# a 404, and the site's own 404 says only "not here", so this whole line tells
# whether Caddy carries /box/ (#2875).
$via = $Site.TrimEnd('/') + '/box/'
$said = ''
try { $said = (Invoke-WebRequest -UseBasicParsing $via -TimeoutSec 15).Content }
catch {
    $r = $_.Exception.Response
    if ($r) {
        try { $said = (New-Object IO.StreamReader($r.GetResponseStream())).ReadToEnd() } catch { $said = '' }
        if (-not $said -and $_.ErrorDetails) { $said = [string]$_.ErrorDetails.Message }
    } else { $said = 'no answer: ' + $_.Exception.Message }
}
if ("$said".Trim() -eq $Plain) {
    Say "  $via reaches the bridge." 'Green'
} else {
    Say "  $via did not reach the bridge, so Caddy does not carry /box/ yet. Setup-Domain.ps1 -TaskOnly does not send the Caddyfile; Setup-Domain.ps1 does." 'Yellow'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
