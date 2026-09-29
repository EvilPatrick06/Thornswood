<#
  test-install-server.ps1

  Install-ThornswoodServer.ps1, and Publish-Server.ps1 that sends it, never
  stop or remove the running server before the new one has checked out, and
  put the old one back when the new one does not answer.

  WHY THIS EXISTS. Issue #446: "A failed publish deletes the live server before
  checking the new one". Until 28 September the installer stopped the server,
  deleted the whole root, unpacked the payload into the empty folder, and only
  then checked the load order, so a payload naming a plugin it did not carry
  left no server at all; Publish-Server stopped it even earlier, before the
  copy, and said "Nothing local was changed". The issue's own Done when: a
  payload with a plugin missing from the load order leaves the old root byte
  for byte as it was, and the old server still answers.

  HOW. The installer is run by Windows PowerShell 5.1, which is what runs it on
  the VPS, against a root in a scratch folder, with -AllowGamingPc so it runs on
  a machine with the game on it. The payloads are real zips. The server in
  them is a node stub that holds its game port on UDP and its resources port on
  TCP the way skymp5-server does, and dies on start, or never opens the
  resources port, when its gamemode says so. The scheduled task cmdlets are the
  only stand-ins: functions in front of them keep a task in a file and start
  its real action, cmd.exe and all, so nothing here registers a real task.
  Publish-Server.ps1 is driven whole, with ssh and scp replaced by functions
  that run the same thing against the scratch folder, the way
  test-remote-big-script.ps1 replaces them.

  It proves:
    - a first install unpacks, answers and records what the payload shipped
    - a payload naming a plugin it does not carry, a zip that arrived
      different, a gamemode that does not parse and a binary that is not its
      recorded build are each INSTALL REFUSED with the root byte for byte as
      it was and the same server process still answering
    - a payload that does not start is INSTALL ROLLED BACK: the old root back
      as it was, answering again, the new one kept as .failed to read
    - a good one swaps in, carries the world, the roster, the runtime data and
      the logs across, keeps the old root as .prev and the newest two of them
    - -PutBack puts the newest .prev back and keeps what it took out
    - a root that cannot be moved because something holds a file in it is
      INSTALL REFUSED, and the old server is started again
    - -FreshWorld starts with no world and leaves the old one in .prev
    - Publish-Server.ps1 exits 1 on a refused payload without having stopped
      anything, and publishes and puts back through the same installer

  Connects to nothing but 127.0.0.1.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
$installer = [IO.Path]::GetFullPath((Join-Path $Here '..\scripts\deploy\Install-ThornswoodServer.ps1'))
$publish   = [IO.Path]::GetFullPath((Join-Path $Here '..\scripts\release\Publish-Server.ps1'))

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Remove-Item -Path function:global:ssh, function:global:scp -ErrorAction SilentlyContinue
    Remove-Variable -Name TsBox -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name TsSshSeen, TsScpFail, TsLastCode -Scope Global -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

# ---- read, not run ------------------------------------------------------------
$src = [IO.File]::ReadAllText($installer)
$iStage = $src.IndexOf('Expand-Archive -LiteralPath $Zip -DestinationPath $stageDir')
$iCheck = $src.IndexOf('load order does not resolve')
$iStop  = $src.IndexOf("StopServer `$Root`r`n")
if ($iStop -lt 0) { $iStop = $src.IndexOf("StopServer `$Root`n") }
Yes 'the installer unpacks into a stage and checks the load order before it stops anything' (
    $iStage -gt 0 -and $iCheck -gt $iStage -and $iStop -gt $iCheck)
Yes 'and no longer deletes the root' ($src -notmatch 'Remove-Item -LiteralPath \$Root -Recurse')
Yes 'and sets nothing aside in %TEMP% any more' ($src -notmatch '\$env:TEMP')
$pub = [IO.File]::ReadAllText($publish)
Yes 'Publish-Server no longer stops the server before it copies' ($pub -notmatch 'Stop-ScheduledTask' -and $pub -notmatch 'stopRemote')
Yes 'and no longer throws the world away over ssh before the install' ($pub -notmatch "Remove-Item -LiteralPath '\`$VpsRoot\\world'")
Yes 'and sends the zip''s hash for the installer to check' ($pub -match '-ZipSha256 \$zipSum')

# ---- run, against a scratch folder ------------------------------------------
$node = Get-Command node -CommandType Application -EA SilentlyContinue | Select-Object -First 1
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not $node -or -not (Test-Path -LiteralPath $ps51) -or
    -not (Get-Command Get-NetUDPEndpoint -EA SilentlyContinue)) {
    Write-Host 'SKIP  the runs need node, Windows PowerShell 5.1 and Get-NetUDPEndpoint, and this machine lacks one'
    Done
}

$started = Get-Date
$work    = Join-Path ([IO.Path]::GetTempPath()) ('ts-install-' + [Guid]::NewGuid().ToString('N'))
$box     = Join-Path $work 'box'          # stands in for C:\ on the VPS
$tasks   = Join-Path $work 'tasks'        # the stand-in task scheduler's book
$far     = Join-Path $work 'far'          # the scripts the stand-in ssh runs
$pidLog  = Join-Path $work 'pids.txt'
$root    = Join-Path $box 'Thornswood-Server'
$utf8    = New-Object Text.UTF8Encoding($false)
foreach ($d in $box, $tasks, $far) { $null = [IO.Directory]::CreateDirectory($d) }

function Put([string]$path, [string]$text) {
    $null = [IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text, $utf8)
}
# Read even while a server holds it open for writing, as it does server.log.
function Get([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $fs = New-Object IO.FileStream($path, 'Open', 'Read', 'ReadWrite')
    try { $r = New-Object IO.StreamReader($fs); return $r.ReadToEnd() } finally { $fs.Dispose() }
}
# A real task by the name the stand-ins use means a stand-in did not take.
# Taken off again at once, and a failure, because nothing here may leave one.
function NoRealTask {
    # The task folder on disk, when this account can read it, because asking
    # the scheduler takes seconds and this is asked after every far call.
    $folder = Join-Path $env:SystemRoot 'System32\Tasks'
    $readable = $false
    try { $null = [IO.Directory]::GetFiles($folder, 'x'); $readable = $true } catch { }
    if ($readable -and -not (Test-Path -Path (Join-Path $folder 'Thornswood Test*'))) { return $true }
    $real = @(Get-ScheduledTask -TaskName 'Thornswood Test*' -ErrorAction SilentlyContinue)
    foreach ($r in $real) {
        Stop-ScheduledTask -TaskName $r.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $r.TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    return ($real.Count -eq 0)
}
function Sha([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
# Every file and folder under a root and its hash, logs left out: a server
# that ran appends to them, and they are carried across on purpose.
function Tree([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return '(none)' }
    $rows = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Force)) {
        if ($f.Name -match '\.log(\.\d+)?$') { continue }
        $rows += ($f.FullName.Substring($dir.Length) + '|' + (Sha $f.FullName))
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $dir -Recurse -Directory -Force)) { $rows += ($d.FullName.Substring($dir.Length) + '|folder') }
    return (($rows | Sort-Object) -join "`n")
}
function Beside([string]$kind) {
    return @(Get-ChildItem -LiteralPath $box -Directory -Force | Where-Object { $_.Name -like ('Thornswood-Server' + $kind) } |
             Sort-Object Name | ForEach-Object { $_.FullName })
}
function Free([int]$p) {
    (-not @(Get-NetUDPEndpoint -LocalPort $p -EA SilentlyContinue).Count) -and
    (-not @(Get-NetTCPConnection -LocalPort $p -EA SilentlyContinue).Count)
}
function Owner([int]$port) {
    $e = @(Get-NetUDPEndpoint -LocalPort $port -EA SilentlyContinue)
    if ($e.Count) { return [int]$e[0].OwningProcess }
    return 0
}
function Answers([int]$port) {
    if (-not (Owner $port)) { return $false }
    $res = if ($port -eq 7777) { 3000 } else { $port + 1 }
    $ok = $false
    try {
        $c = New-Object Net.Sockets.TcpClient
        $null = $c.BeginConnect('127.0.0.1', $res, $null, $null).AsyncWaitHandle.WaitOne(500)
        $ok = $c.Connected
        $c.Close()
    } catch { }
    return $ok
}
function WaitUp([int]$port) {
    for ($i = 0; $i -lt 40; $i++) { if (Answers $port) { return $true }; Start-Sleep -Milliseconds 250 }
    return $false
}

# The task scheduler, for the far side. A task is a file holding its action;
# starting it starts that action, the real cmd.exe line, and stopping it ends
# the process it started and nothing under it, as Task Scheduler does.
$prelude = @'
# Loaded first, on purpose. It is a module of functions, and loaded part way
# through a script, by the first use of New-ScheduledTaskAction, it is put
# where it hides the stand-ins below; loaded here, the stand-ins are found
# first. Without this the real Register-ScheduledTask ran and registered a
# real task on the machine running this, which the harness now checks for.
Import-Module ScheduledTasks -ErrorAction SilentlyContinue
if (-not (Get-Module ScheduledTasks)) { 'THE TASK MODULE DID NOT LOAD, SO THE STAND-INS CANNOT BE TRUSTED'; exit 98 }
# And every command of it the scripts use is a stand-in too, so nothing in
# them can load it again part way through and bring the real ones back.
function New-ScheduledTaskAction { [CmdletBinding()] param([string]$Execute, [string]$Argument, [string]$WorkingDirectory) [pscustomobject]@{ Execute = $Execute; Arguments = $Argument; WorkingDirectory = $WorkingDirectory } }
function New-ScheduledTaskTrigger { [CmdletBinding()] param([switch]$AtStartup, [switch]$Once, $At, $RepetitionInterval) [pscustomobject]@{ AtStartup = [bool]$AtStartup } }
function New-ScheduledTaskSettingsSet { [CmdletBinding()] param([switch]$AllowStartIfOnBatteries, [switch]$DontStopIfGoingOnBatteries, [switch]$StartWhenAvailable, $RestartCount, $RestartInterval, $ExecutionTimeLimit) [pscustomobject]@{ RestartCount = $RestartCount; ExecutionTimeLimit = 'PT0S' } }
function New-ScheduledTaskPrincipal { [CmdletBinding()] param([string]$UserId, $LogonType, $RunLevel, $RequiredPrivilege, $ProcessTokenSidType) [pscustomobject]@{ UserId = $UserId; RunLevel = [string]$RunLevel } }
$env:TS_PIDLOG = '@@PIDLOG@@'
$TsTasks = '@@TASKS@@'
function TsTaskFile([string]$n) { Join-Path $TsTasks (($n -replace '[^A-Za-z0-9]', '_') + '.json') }
function TsRead([string]$n) { $f = TsTaskFile $n; if (Test-Path -LiteralPath $f) { return ([IO.File]::ReadAllText($f) | ConvertFrom-Json) }; return $null }
function TsWrite([string]$n, $t) { [IO.File]::WriteAllText((TsTaskFile $n), ($t | ConvertTo-Json -Depth 4)) }
function Get-ScheduledTask {
  [CmdletBinding()] param([string]$TaskName)
  $t = TsRead $TaskName
  if (-not $t) { return }
  [pscustomobject]@{ TaskName = $TaskName; State = 'Ready'
    Actions = @([pscustomobject]@{ Execute = $t.Execute; Arguments = $t.Argument; WorkingDirectory = $t.WorkingDirectory })
    Principal = [pscustomobject]@{ UserId = 'SYSTEM'; RunLevel = 'Highest' }; Settings = $null }
}
function Register-ScheduledTask {
  [CmdletBinding()] param([string]$TaskName, $Action, $Trigger, $Settings, $Principal, [string]$Xml, [string]$User, [string]$RunLevel)
  $t = [ordered]@{ Execute = ''; Argument = ''; WorkingDirectory = ''; Pid = 0 }
  if ($Xml) {
    $x = [xml]$Xml
    $e = $x.Task.Actions.Exec
    $t.Execute = [string]$e.Command; $t.Argument = [string]$e.Arguments; $t.WorkingDirectory = [string]$e.WorkingDirectory
  } else {
    $a = @($Action)[0]
    $t.Execute = [string]$a.Execute; $t.Argument = [string]$a.Arguments; $t.WorkingDirectory = [string]$a.WorkingDirectory
  }
  TsWrite $TaskName $t
}
function Set-ScheduledTask {
  [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$InputObject)
  process {
    $t = TsRead $InputObject.TaskName
    $a = @($InputObject.Actions)[0]
    $n = [ordered]@{ Execute = [string]$a.Execute; Argument = [string]$a.Arguments; WorkingDirectory = [string]$a.WorkingDirectory; Pid = 0 }
    if ($t) { $n.Pid = $t.Pid }
    TsWrite $InputObject.TaskName $n
  }
}
function Unregister-ScheduledTask {
  [CmdletBinding(SupportsShouldProcess = $true)] param([string]$TaskName)
  Remove-Item -LiteralPath (TsTaskFile $TaskName) -Force -EA SilentlyContinue
}
function Export-ScheduledTask {
  [CmdletBinding()] param([string]$TaskName)
  $t = TsRead $TaskName
  if (-not $t) { return }
  $x = New-Object xml
  $task = $x.AppendChild($x.CreateElement('Task'))
  $exec = $task.AppendChild($x.CreateElement('Actions')).AppendChild($x.CreateElement('Exec'))
  foreach ($k in @(@('Command', $t.Execute), @('Arguments', $t.Argument), @('WorkingDirectory', $t.WorkingDirectory))) {
    $null = $exec.AppendChild($x.CreateElement($k[0])).AppendChild($x.CreateTextNode([string]$k[1]))
  }
  $x.OuterXml
}
function Start-ScheduledTask {
  [CmdletBinding()] param([string]$TaskName)
  $t = TsRead $TaskName
  if (-not $t) { return }
  $p = Start-Process -FilePath $t.Execute -ArgumentList $t.Argument -WorkingDirectory $t.WorkingDirectory -WindowStyle Hidden -PassThru
  [IO.File]::AppendAllText($env:TS_PIDLOG, [string]$p.Id + "`n")
  $n = [ordered]@{ Execute = $t.Execute; Argument = $t.Argument; WorkingDirectory = $t.WorkingDirectory; Pid = $p.Id }
  TsWrite $TaskName $n
}
function Stop-ScheduledTask {
  [CmdletBinding()] param([string]$TaskName)
  $t = TsRead $TaskName
  if ($t -and $t.Pid) { Stop-Process -Id ([int]$t.Pid) -Force -EA SilentlyContinue }
}
function Get-ScheduledTaskInfo { [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$InputObject) process { [pscustomobject]@{ LastTaskResult = 0 } } }
function Get-NetFirewallRule { }
function New-NetFirewallRule { }
function Remove-NetFirewallRule { }
foreach ($n in 'Get-ScheduledTask', 'Register-ScheduledTask', 'Start-ScheduledTask', 'Stop-ScheduledTask',
               'Unregister-ScheduledTask', 'Set-ScheduledTask', 'Export-ScheduledTask', 'New-NetFirewallRule',
               'New-ScheduledTaskAction', 'New-ScheduledTaskTrigger', 'New-ScheduledTaskSettingsSet', 'New-ScheduledTaskPrincipal') {
  $c = Get-Command $n
  if ($c.CommandType -ne 'Function' -or $c.Source) { 'THE STAND-IN FOR ' + $n + ' IS NOT THE ONE FOUND'; exit 97 }
}

'@
$prelude = $prelude.Replace('@@PIDLOG@@', $pidLog.Replace("'", "''")).Replace('@@TASKS@@', $tasks.Replace("'", "''"))

# Everything the stand-ins below read is in $global:TsBox, not in a variable
# of this script: they run inside the script under test, and PowerShell
# finds that script's own variables first (its Remote has a $far of its own).
$global:TsBox = [pscustomobject]@{ Far = $far; Prelude = $prelude; Work = $work; Ps51 = $ps51; Box = $box }
function RunWrapped([string]$body) {
    $f = Join-Path $global:TsBox.Far ('far-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    [IO.File]::WriteAllText($f, ($global:TsBox.Prelude + $body), (New-Object Text.UTF8Encoding($true)))
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location -LiteralPath $global:TsBox.Work
    try { $out = @(& $global:TsBox.Ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $f 2>&1 | ForEach-Object { "$_".TrimEnd() }) }
    finally { Pop-Location; $ErrorActionPreference = $eap }
    $script:lastCode = $LASTEXITCODE
    $global:TsLastCode = $LASTEXITCODE
    $script:lastOut = $out
    if (-not (NoRealTask)) { Yes 'no real scheduled task was touched' $false; throw 'a real scheduled task was registered, and has been removed' }
    return $out
}
function Show { foreach ($l in $script:lastOut) { Write-Host ('        ' + $l) } }

# The installer, the way Publish-Server has the box run it.
function Install([string]$zip, [string[]]$more) {
    $a = "-Zip '" + $zip.Replace("'", "''") + "' -Root '" + $root.Replace("'", "''") + "' -TaskName 'Thornswood Test Server' -StartNow -AllowGamingPc -Wait 8 " + ($more -join ' ')
    return (RunWrapped ("& '" + $installer.Replace("'", "''") + "' " + $a + "`r`nexit `$LASTEXITCODE`r`n"))
}

# The server in a payload: skymp5-server.js as the task starts it, from the
# root, with its output going to server.log through cmd.
$stubJs = @'
const fs = require('fs');
const dgram = require('dgram');
const net = require('net');
try { fs.appendFileSync(process.env.TS_PIDLOG, process.pid + '\n'); } catch (e) { }
const root = process.cwd();
const gm = fs.readFileSync('gamemode.js', 'utf8');
if (gm.indexOf('will-not-start') >= 0) { console.log('Error: this gamemode will not start'); process.exit(1); }
const s = JSON.parse(fs.readFileSync('server-settings.json', 'utf8'));
const res = s.port === 7777 ? 3000 : s.port + 1;
dgram.createSocket('udp4').bind(s.port, '127.0.0.1');
if (gm.indexOf('udp-only') < 0) { net.createServer(function (c) { c.end(); }).listen(res, '127.0.0.1'); }
console.log('listening on ' + s.port);
setTimeout(function () { process.exit(0); }, 600000);
'@

$script:zipN = 0
# A payload as Export-ServerPayload makes one: the load order written out in
# full under the root it is for.
function Payload {
    param([string]$Gamemode = '// v2', [string[]]$Order = @('Skyrim.esm', 'A.esp'), [string[]]$Carry = @('Skyrim.esm', 'A.esp'),
          [string]$Binary = 'binary v2', [string]$RecordFor = '', [string]$Shipped = 'shipped v2', [int]$Port = $P,
          [string]$ForRoot = $root)
    $script:zipN++
    $dir = Join-Path $work ('payload-' + $script:zipN)
    foreach ($n in $Carry) { Put (Join-Path $dir ('plugins\' + $n)) ('plugin ' + $n) }
    Put (Join-Path $dir 'gamemode.js') $Gamemode
    Put (Join-Path $dir 'dist_back\skymp5-server.js') $stubJs
    Put (Join-Path $dir 'scam_native.node') $Binary
    if (-not $RecordFor) { $RecordFor = $Binary }
    $h = [Security.Cryptography.SHA256]::Create()
    $sum = (($h.ComputeHash($utf8.GetBytes($RecordFor)) | ForEach-Object { $_.ToString('x2') }) -join '')
    Put (Join-Path $dir 'server-build.json') ('{ "sha256": "' + $sum + '" }')
    Put (Join-Path $dir 'data\shipped.txt') $Shipped
    $far = ($ForRoot -replace '\\', '/') + '/plugins/'
    Put (Join-Path $dir 'server-settings.json') (([ordered]@{ port = $Port; name = 'Thornswood Test'; dataDir = 'data'
        loadOrder = @($Order | ForEach-Object { $far + $_ }) }) | ConvertTo-Json -Depth 5)
    $zip = Join-Path $work ('payload-' + $script:zipN + '.zip')
    Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $zip -Force
    return $zip
}

$rand = New-Object Random
try {
    do { $P = $rand.Next(41000, 48000) } until ((Free $P) -and (Free ($P + 1)))

    # ---- a first install ---------------------------------------------------
    $v1 = Payload -Gamemode '// v1' -Binary 'binary v1' -Shipped 'shipped v1'
    $out = Install $v1 @()
    $failed = $script:fail
    Yes 'a first install is INSTALL OK' ($out -contains 'INSTALL OK')
    Yes '  and the server answers on both its ports' (WaitUp $P)
    Yes '  and what the payload shipped into data is written down' ((Get (Join-Path $root '.payload-data.txt')) -match 'shipped\.txt')
    Yes '  and an empty private folder is made, with a line saying so' (
        (Test-Path -LiteralPath (Join-Path $root 'private')) -and (($out -join "`n") -match 'no roster to restore'))
    Yes '  and no stage is left beside it' (@(Beside '.stage-*').Count -eq 0)
    if ($script:fail -gt $failed) { Show }

    # ---- a scratch root whose settings name another server's port ------------
    # docs\RESTORING.md installs into C:\Thornswood-RestoreTest\server with
    # -NoTask, from a payload whose settings are the live server's. The stop
    # must be by this root's own processes: the one on that port is live.
    $Q = 0
    do { $Q = $rand.Next(41000, 48000) } until ((Free $Q) -and (Free ($Q + 1)) -and [Math]::Abs($Q - $P) -gt 2)
    $other = Join-Path $work 'other-server'
    Put (Join-Path $other 'gamemode.js') '// the other server'
    Put (Join-Path $other 'server-settings.json') ((@{ port = $Q; name = 'other' }) | ConvertTo-Json)
    Put (Join-Path $work 'other-stub.js') $stubJs
    $env:TS_PIDLOG = $pidLog
    $o = Start-Process -FilePath $node.Source -ArgumentList ('"' + (Join-Path $work 'other-stub.js') + '"') -WorkingDirectory $other -WindowStyle Hidden -PassThru
    $scratch = Join-Path $box 'RestoreTest\server'
    $saveRoot = $root
    try {
        $script:otherUp = WaitUp $Q
        $root = $scratch
        foreach ($n in 1..2) {
            $a = "-Zip '" + (Payload -Port $Q -ForRoot $scratch).Replace("'", "''") + "' -Root '" + $scratch.Replace("'", "''") + "' -NoTask -AllowGamingPc`r`nexit `$LASTEXITCODE`r`n"
            $out = RunWrapped ("& '" + $installer.Replace("'", "''") + "' " + $a)
        }
    } finally { $root = $saveRoot }
    $failed = $script:fail
    Yes '-NoTask into a scratch root is INSTALL OK, twice over' ($out -contains 'INSTALL OK')
    Yes '  and the other server on the port its settings name was never stopped' ($script:otherUp -and ((Owner $Q) -eq $o.Id) -and (Answers $Q))
    if ($script:fail -gt $failed) { Show }

    # What a server that has been running has, that no payload brings.
    Put (Join-Path $root 'world\w.txt') 'every character'
    Put (Join-Path $root 'private\door.json') '{ "site": "x" }'
    Put (Join-Path $root 'data\book.txt') 'the character book'
    Put (Join-Path $root 'thornswood.log') 'the gamemode log'
    $before = Tree $root
    $running = Owner $P

    # ---- refusals: nothing stops, nothing moves ----------------------------
    foreach ($case in @(
        @{ Label = 'a payload naming a plugin it does not carry'; Why = 'not in the payload or on disk';
           Zip = { Payload -Order @('Skyrim.esm', 'A.esp', 'Nowhere.esp') }; More = @() },
        @{ Label = 'a zip that arrived different from what was sent'; Why = 'arrived different from what was sent';
           Zip = { Payload }; More = @('-ZipSha256 00112233') },
        @{ Label = 'a gamemode that does not parse'; Why = 'gamemode\.js does not parse';
           Zip = { Payload -Gamemode 'function ( { not javascript' }; More = @() },
        @{ Label = 'a binary that is not its recorded build'; Why = 'not the build server-build\.json records';
           Zip = { Payload -RecordFor 'some other binary' }; More = @() }
    )) {
        $zip = & $case.Zip
        $out = Install $zip $case.More
        $failed = $script:fail
        $label = $case.Label
        Yes "$label is INSTALL REFUSED" (($out -contains 'INSTALL REFUSED') -and $script:lastCode -ne 0)
        Yes '  and it says why' (($out -join "`n") -match $case.Why)
        Yes '  and the root is byte for byte as it was, with no stage left' (((Tree $root) -eq $before) -and @(Beside '.stage-*').Count -eq 0)
        Yes '  and the same server process is still answering' (((Owner $P) -eq $running) -and (Answers $P))
        if ($script:fail -gt $failed) { Show }
    }

    # ---- a payload that does not start -------------------------------------
    $bad = Payload -Gamemode '// v3, will-not-start'
    $out = Install $bad @()
    $failed = $script:fail
    Yes 'a payload that does not start is INSTALL ROLLED BACK' (($out -contains 'INSTALL ROLLED BACK') -and $script:lastCode -ne 0)
    Yes '  and says why from its log' (($out -join "`n") -match 'this gamemode will not start')
    Yes '  and the old root is back as it was, world, roster and runtime data included' ((Tree $root) -eq $before)
    Yes '  and the old server is answering again, as a new process' ((WaitUp $P) -and ((Owner $P) -ne $running))
    $kept = @(Beside '.failed-*')
    Yes '  and the new one is kept to read, beside it' ($kept.Count -eq 1 -and (Get (Join-Path $kept[0] 'gamemode.js')) -match 'will-not-start')
    Yes '  and no .prev is left, since the old root is the root again' (@(Beside '.prev-*').Count -eq 0)
    Yes '  and the logs came back with it, the failed start in them' ((Get (Join-Path $root 'server.log')) -match 'will not start')
    if ($script:fail -gt $failed) { Show }

    # ---- a good one ----------------------------------------------------------
    $running = Owner $P
    $v2 = Payload
    $out = Install $v2 @()
    $failed = $script:fail
    Yes 'a good payload is INSTALL OK' ($out -contains 'INSTALL OK')
    Yes '  and the new gamemode and binary are live, and answering as a new process' (
        (Get (Join-Path $root 'gamemode.js')) -eq '// v2' -and (Get (Join-Path $root 'scam_native.node')) -eq 'binary v2' -and
        (WaitUp $P) -and ((Owner $P) -ne $running))
    Yes '  and the world and the roster were carried across' (
        (Get (Join-Path $root 'world\w.txt')) -eq 'every character' -and (Get (Join-Path $root 'private\door.json')) -match 'site')
    Yes '  and the runtime data came too, while what the payload ships is the new one' (
        (Get (Join-Path $root 'data\book.txt')) -eq 'the character book' -and (Get (Join-Path $root 'data\shipped.txt')) -eq 'shipped v2')
    Yes '  and the logs were carried, not deleted' ((Get (Join-Path $root 'thornswood.log')) -eq 'the gamemode log')
    $prev = @(Beside '.prev-*')
    Yes '  and the old root is kept beside it as .prev, with what it shipped' (
        $prev.Count -eq 1 -and (Get (Join-Path $prev[0] 'gamemode.js')) -eq '// v1' -and
        (Get (Join-Path $prev[0] 'data\shipped.txt')) -eq 'shipped v1')
    Yes '  and without the world, which moved rather than being copied' (-not (Test-Path -LiteralPath (Join-Path $prev[0] 'world')))
    if ($script:fail -gt $failed) { Show }

    # ---- -PutBack --------------------------------------------------------------
    Put (Join-Path $root 'world\w2.txt') 'a character made since'
    $running = Owner $P
    $out = RunWrapped ("& '" + $installer.Replace("'", "''") + "' -Root '" + $root.Replace("'", "''") +
                       "' -TaskName 'Thornswood Test Server' -StartNow -AllowGamingPc -Wait 8 -PutBack`r`nexit `$LASTEXITCODE`r`n")
    $failed = $script:fail
    Yes '-PutBack is INSTALL OK' ($out -contains 'INSTALL OK')
    Yes '  and the old gamemode is live again, answering as a new process' (
        (Get (Join-Path $root 'gamemode.js')) -eq '// v1' -and (WaitUp $P) -and ((Owner $P) -ne $running))
    Yes '  and the world it runs is the current one, with what was made since' ((Get (Join-Path $root 'world\w2.txt')) -eq 'a character made since')
    $undone = @(Beside '.undone-*')
    Yes '  and what it took out is kept as .undone, and the .prev it put back is gone' (
        $undone.Count -eq 1 -and (Get (Join-Path $undone[0] 'gamemode.js')) -eq '// v2' -and @(Beside '.prev-*').Count -eq 0)
    if ($script:fail -gt $failed) { Show }

    # ---- a root something is holding -------------------------------------------
    $before = Tree $root
    $running = Owner $P
    $held = [IO.File]::Open((Join-Path $root 'world\w.txt'), 'Open', 'Read', 'None')
    try { $out = Install (Payload) @() } finally { $held.Close() }
    $failed = $script:fail
    Yes 'a root that cannot be moved aside is INSTALL REFUSED' (($out -contains 'INSTALL REFUSED') -and $script:lastCode -ne 0)
    Yes '  and names the file that is held' (($out -join "`n") -match 'still open: .*w\.txt')
    Yes '  and the root is as it was, with no stage left' (((Tree $root) -eq $before) -and @(Beside '.stage-*').Count -eq 0)
    Yes '  and the old server was started again' ((WaitUp $P) -and ((Owner $P) -ne $running))
    if ($script:fail -gt $failed) { Show }

    # ---- -FreshWorld, and the newest two .prev -----------------------------------
    foreach ($n in 1..4) { Put (Join-Path $box ('Thornswood-Server.prev-20000101-00000' + $n + '\gamemode.js')) '// long ago' }
    $out = Install (Payload -Gamemode '// v4') @('-FreshWorld')
    $failed = $script:fail
    Yes '-FreshWorld is INSTALL OK and starts with no world' (($out -contains 'INSTALL OK') -and -not (Test-Path -LiteralPath (Join-Path $root 'world')))
    $prev = @(Beside '.prev-*')
    Yes '  and the old world is kept in the .prev it left' ((Get (Join-Path $prev[-1] 'world\w.txt')) -eq 'every character')
    Yes '  and the roster still came across' ((Get (Join-Path $root 'private\door.json')) -match 'site')
    Yes '  and only the newest two .prev folders are kept, not three (#1121)' (
        $prev.Count -eq 2 -and -not (Test-Path -LiteralPath (Join-Path $box 'Thornswood-Server.prev-20000101-000003')))
    if ($script:fail -gt $failed) { Show }

    # ---- Publish-Server.ps1, whole, against the dev channel's ports ---------------
    # Publish-Server checks the answer from here on the dev server's own
    # ports, 7787 and 7788, so this part needs those two free.
    if (-not ((Free 7787) -and (Free 7788))) {
        Write-Host 'SKIP  Publish-Server.ps1 is checked on 7787 and 7788, and something on this machine holds one'
    } else {
        $devRoot = Join-Path $box 'Thornswood-Server-Dev'
        $dist = Join-Path $work 'dist'
        Put (Join-Path $dist 'server-settings.json') ((@{ port = 7777; name = 'Thornswood'; loadOrder = @('c:/x/Skyrim.esm') }) | ConvertTo-Json)
        Put (Join-Path $dist 'gamemode.js') '// the dist copy'
        $global:TsScpFail = ''

        # ssh and scp, for the box under $box. The fixed paths Publish-Server
        # names on C:\ land in the scratch folder, and the live root it reads
        # the roster from is the scratch one, which has none.
        function MapFar([string]$s) {
            foreach ($p in 'C:\thornswood-server.zip', 'C:\Install-ThornswoodServer.ps1', 'C:\Roll-Log.ps1', 'C:\Thornswood-Server\') {
                $to = Join-Path $global:TsBox.Box $p.Substring(3)
                $s = $s.Replace($p, $to).Replace($p.Replace('\', '/'), $to)
            }
            return $s
        }
        function global:ssh {
            $all = @($args | ForEach-Object { [string]$_ })
            $cmd = $all[-1]
            [void]$global:TsSshSeen.Add($cmd)
            $body = ''
            $m = [regex]::Match($cmd, 'EncodedCommand\s+(\S+)')
            if ($m.Success) { $body = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($m.Groups[1].Value)) }
            else {
                $m = [regex]::Match($cmd, '-File\s+(\S+)(.*)$')
                if ($m.Success) {
                    # The zip goes in quotes: the scratch folder can hold an &.
                    $rest = $m.Groups[2].Value.Replace('C:\thornswood-server.zip', "'" + (Join-Path $global:TsBox.Box 'thornswood-server.zip').Replace("'", "''") + "'")
                    $body = "& '" + (MapFar $m.Groups[1].Value).Replace("'", "''") + "'" + $rest + " -AllowGamingPc`r`nexit `$LASTEXITCODE"
                }
                else {
                    $m = [regex]::Match($cmd, '-Command\s+(.*)$')
                    if ($m.Success) { $body = (MapFar $m.Groups[1].Value).Trim('"') }
                }
            }
            $out = RunWrapped (MapFar $body)
            foreach ($l in $out) { $l }
            $global:LASTEXITCODE = $global:TsLastCode
        }
        function global:scp {
            $all = @($args | ForEach-Object { [string]$_ })
            $src = $all[-2]; $dst = $all[-1]
            $m = [regex]::Match($dst, '^[^@\s]+@[^:\s]+:(.+)$')
            $global:LASTEXITCODE = 1
            if (-not $m.Success) { return }
            if ($global:TsScpFail -and $m.Groups[1].Value -match $global:TsScpFail) { return }
            $to = MapFar $m.Groups[1].Value
            if ($to -eq $m.Groups[1].Value) { return }
            Copy-Item -LiteralPath $src -Destination $to -Force
            $global:LASTEXITCODE = 0
        }
        $global:TsSshSeen = New-Object Collections.Generic.List[string]
        function Publish([string]$zip, [string[]]$more) {
            $a = @{ Channel = 'dev'; VpsRoot = $devRoot; TaskName = 'Thornswood Test Dev'; VpsHost = '127.0.0.1'; VpsUser = 'nobody'
                    Dist = $dist; Zip = $zip; SkipBuild = $true; NoPause = $true; Wait = 8 }
            foreach ($x in $more) { $a[$x] = $true }
            $global:TsSshSeen.Clear()
            $global:LASTEXITCODE = 0
            $said = @(& $publish @a *>&1 | ForEach-Object { "$_" })
            $script:lastOut = $said
            return $global:LASTEXITCODE
        }

        $code = Publish (Payload -Port 7787 -ForRoot $devRoot -Gamemode '// dev v1') @()
        $failed = $script:fail
        Yes 'Publish-Server puts a first dev server up and exits 0' ($code -eq 0 -and (WaitUp 7787))
        if ($script:fail -gt $failed) { Show }
        $devBefore = Tree $devRoot
        $devPid = Owner 7787

        $code = Publish (Payload -Port 7787 -ForRoot $devRoot -Order @('Skyrim.esm', 'Missing.esp')) @()
        $failed = $script:fail
        Yes 'Publish-Server with a payload the installer refuses exits 1' ($code -ne 0)
        Yes '  and says the server was not stopped or changed' ((($script:lastOut) -join "`n") -match 'was not stopped or changed')
        Yes '  and it was not: the same process, the root as it was' (((Owner 7787) -eq $devPid) -and ((Tree $devRoot) -eq $devBefore))
        Yes '  and nothing it sent the box before the installer stops anything' (
            @($global:TsSshSeen | Where-Object { $_ -match 'EncodedCommand' }).Count -eq 0)
        if ($script:fail -gt $failed) { Show }

        $global:TsScpFail = 'thornswood-server\.zip'
        $code = Publish (Payload -Port 7787 -ForRoot $devRoot) @()
        $global:TsScpFail = ''
        $failed = $script:fail
        Yes 'Publish-Server whose copy fails exits 1 with the server untouched' (
            $code -ne 0 -and ((Owner 7787) -eq $devPid) -and ((Tree $devRoot) -eq $devBefore))
        if ($script:fail -gt $failed) { Show }

        $code = Publish (Payload -Port 7787 -ForRoot $devRoot -Gamemode '// dev v2') @()
        $failed = $script:fail
        Yes 'Publish-Server with a good payload exits 0 and the new gamemode answers' (
            $code -eq 0 -and (Get (Join-Path $devRoot 'gamemode.js')) -eq '// dev v2' -and (WaitUp 7787))
        if ($script:fail -gt $failed) { Show }

        $code = Publish '' @('PutBack')
        $failed = $script:fail
        Yes 'Publish-Server -PutBack exits 0 and the previous gamemode answers again' (
            $code -eq 0 -and (Get (Join-Path $devRoot 'gamemode.js')) -eq '// dev v1' -and (WaitUp 7787))
        if ($script:fail -gt $failed) { Show }
    }
}
catch {
    Yes ('the runs finished without an error: ' + $_.Exception.Message) $false
    Show
}
finally {
    Yes 'no real scheduled task was left behind' (NoRealTask)
    # Only what this run started: the pids it wrote down, and only processes
    # that began after it did, so a pid Windows has since handed to something
    # else is left alone.
    if (Test-Path -LiteralPath $pidLog) {
        foreach ($id in @(Get-Content -LiteralPath $pidLog | Where-Object { $_ })) {
            $p = Get-Process -Id ([int]$id) -EA SilentlyContinue
            if ($p -and $p.StartTime -ge $started) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
        }
    }
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}

Done
