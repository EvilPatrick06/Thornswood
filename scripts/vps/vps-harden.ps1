<#
.SYNOPSIS
  Runs ON THE VPS, sent there by Harden-VPS.ps1: turns ssh password login off, turns Remote Desktop off and the Windows services the box never uses, leaving ssh on port 22 alone.

.DESCRIPTION
  Do not run this by hand. Harden-VPS.ps1 proves key login works first, from
  your machine, and refuses to send this otherwise; run that instead. It
  sends this file's text on ssh's standard input and Windows PowerShell 5.1
  runs it from there, so nothing of it is ever written on the box (#3035).

  In this order, each step saying what it found and what it did:

    Remote Desktop   fDenyTSConnections set to 1, every enabled inbound allow
                     rule in the Remote Desktop group or on port 3389 turned
                     off, and the Remote Desktop service stopped and set to
                     Disabled. A rule that also covers port 22 is never
                     touched, and neither are the rules that allow ssh.
    services         the Windows services in $IdleServices below, which a
                     box that runs game servers, a site, a bot and build
                     runners with nobody signed in never uses, each stopped
                     and set to Disabled, with the reason beside it (#3186).
                     One that is not installed is said and left.
    sshd_config      PasswordAuthentication no and KbdInteractiveAuthentication
                     no, as the first setting of each (sshd takes the first
                     one it reads) and above the Match block, where a global
                     setting has to be. The new file is checked with
                     sshd -t before it replaces the old one, and the old one
                     is kept beside it as sshd_config.before-harden-<time>,
                     which only SYSTEM and Administrators may read (#3034).
    restart          sshd is restarted by a one time scheduled task a few
                     seconds after this returns, so the answer gets back
                     before the connection goes. A second task puts the old
                     sshd_config back and restarts sshd ten minutes later
                     unless Harden-VPS.ps1 cancels it after proving key login
                     still works: if the change ever locked the key out, the
                     box undoes it on its own.

  Every line of output starts with one word: CHANGED, WOULD (with -DryRun),
  ALREADY, KEPT, WARN or STOP. STOP means nothing after it was done, and the
  exit code is 1.

.PARAMETER DryRun
  Read everything, change nothing, and say WOULD for each change.

.PARAMETER SshdConfig
  The sshd_config to change. The Windows OpenSSH server's own by default.

.PARAMETER Sshd
  The sshd.exe that checks the new file (sshd -t) before it is used.

.PARAMETER Layer
  A file that replaces the functions below that touch Windows (the registry,
  the firewall, services, scheduled tasks, sshd -t, the copy's rules). Only
  tests\test-harden-vps.ps1 passes it, to run this against stand-ins.
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$SshdConfig = (Join-Path $env:ProgramData 'ssh\sshd_config'),
    [string]$Sshd = (Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'),
    [string]$Layer = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RdpGroup = '@FirewallAPI.dll,-28752'
$TsKey = 'HKLM:\System\CurrentControlSet\Control\Terminal Server'
$RestartTask = 'Thornswood sshd restart'

# Windows services the box runs and never uses (#3186). Found running and
# set to start on their own on 21 Oct 2026. The box is a server nobody signs
# in to: it prints nothing, has no desktop, no devices plugged in, nobody to
# notify and no files linked across machines. All 45 svchost processes
# together used about 0.03 of a core, so each of these is a little memory
# and processor time, and the print spooler is attack surface with a history
# (PrintNightmare). Microsoft Edge's update tasks stay: the same updater
# keeps the WebView2 runtime patched, and an Edge left unpatched on the box
# is worse than a few seconds an hour.
$IdleServices = @(
    @{ Name = 'Spooler'; Why = 'print spooler: nothing prints from the box, and it is the PrintNightmare service' },
    @{ Name = 'DiagTrack'; Why = 'Connected User Experiences and Telemetry: sends usage data to Microsoft' },
    @{ Name = 'SysMain'; Why = 'SysMain (Superfetch): preloads programs a person opens; the box keeps its own running' },
    @{ Name = 'Themes'; Why = 'Themes: the desktop''s look, and nobody signs in to a desktop' },
    @{ Name = 'ShellHWDetection'; Why = 'Shell Hardware Detection: AutoPlay for discs and sticks put in' },
    @{ Name = 'CDPSvc'; Why = 'Connected Devices Platform: phones and PCs paired to a signed in person' },
    @{ Name = 'WpnService'; Why = 'Windows Push Notifications: toasts for a signed in person' },
    @{ Name = 'TrkWks'; Why = 'Distributed Link Tracking Client: follows shortcuts to files moved across machines' }
)
$RollbackTask = 'Thornswood harden rollback'

# ---------------------------------------------------------------- the layer ---
# Everything that touches Windows goes through these, so the harness can put
# stand-ins in their place with -Layer and run the rest of this for real.

function Get-RdpDeny {
    $v = Get-ItemProperty -LiteralPath $TsKey -Name fDenyTSConnections -ErrorAction SilentlyContinue
    if ($null -eq $v) { return -1 }
    return [int]$v.fDenyTSConnections
}
function Set-RdpDeny { Set-ItemProperty -LiteralPath $TsKey -Name fDenyTSConnections -Value 1 -Type DWord }

# Enabled inbound rules, each as Name, DisplayName, Action, Group, Ports.
function Get-InboundRules {
    foreach ($r in @(Get-NetFirewallRule -Direction Inbound -Enabled True -ErrorAction SilentlyContinue)) {
        $pf = $r | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Name = [string]$r.Name; DisplayName = [string]$r.DisplayName; Action = [string]$r.Action
            Group = [string]$r.Group; Ports = @(@($pf.LocalPort) | ForEach-Object { [string]$_ })
        }
    }
}
function Disable-InboundRule([string]$Name) { Disable-NetFirewallRule -Name $Name }

function Get-TermService {
    $s = Get-Service -Name TermService -ErrorAction SilentlyContinue
    if (-not $s) { return $null }
    return [pscustomobject]@{ Status = [string]$s.Status; StartType = [string]$s.StartType }
}
function Stop-TermService { Stop-Service -Name TermService -Force }
function Disable-TermService { Set-Service -Name TermService -StartupType Disabled }

function Get-IdleService([string]$Name) {
    $s = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $s) { return $null }
    return [pscustomobject]@{ Status = [string]$s.Status; StartType = [string]$s.StartType }
}
function Stop-IdleService([string]$Name) { Stop-Service -Name $Name -Force }
function Disable-IdleService([string]$Name) { Set-Service -Name $Name -StartupType Disabled }

function Test-SshdFile([string]$Path) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = @(& $Sshd -t -f $Path 2>&1 | ForEach-Object { [string]$_ })
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    return [pscustomobject]@{ Ok = ($rc -eq 0); Said = ($out -join ' ') }
}

# A task, not Restart-Service here: an ssh session's own processes go with it,
# and restarting sshd from inside the session could cut this answer off.
function Start-SshdRestart {
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ("-NoProfile -Command `"Start-Sleep -Seconds 5; Restart-Service sshd -Force; Unregister-ScheduledTask -TaskName '" + $RestartTask + "' -Confirm:`$false`"")
    $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $RestartTask -Action $a -Principal $p -Force | Out-Null
    Start-ScheduledTask -TaskName $RestartTask
}

function Register-Rollback([string]$Backup) {
    $cmd = "Copy-Item -LiteralPath '" + $Backup + "' -Destination '" + $SshdConfig + "' -Force; Restart-Service sshd -Force; Unregister-ScheduledTask -TaskName '" + $RollbackTask + "' -Confirm:`$false"
    $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -Command "' + $cmd + '"')
    $t = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(10))
    $p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $RollbackTask -Action $a -Trigger $t -Principal $p -Force | Out-Null
}

# Makes $Path an empty file only SYSTEM and Administrators may open, taking
# nothing from its folder (#3034). C:\ProgramData\ssh gives every signed in
# account read, as Windows OpenSSH installs it, and a file made there takes
# that rule, so a copy made there plainly is open to every account on the
# box. The rules are set while the file is empty, so its content is never
# open, and they are the ones administrators_authorized_keys has.
function New-PrivateFile([string]$Path) {
    [IO.File]::WriteAllBytes($Path, [byte[]]@())
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($s in 'S-1-5-18', 'S-1-5-32-544') {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($s)), 'FullControl', 'Allow')))
    }
    $item = Get-Item -LiteralPath $Path -Force
    if ($PSVersionTable.PSEdition -eq 'Core') { [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]$item, $acl) } else { $item.SetAccessControl($acl) }
    # Read back, not taken from the call: a FileSecurity already written once
    # writes nothing the second time and says nothing (#3034, on the box).
    $got = Get-Acl -LiteralPath $Path
    $who = @($got.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)
    if (-not $got.AreAccessRulesProtected -or ($who -join ',') -ne 'S-1-5-18,S-1-5-32-544') { throw ($Path + ' did not take SYSTEM and Administrators alone: ' + ($who -join ', ')) }
}

if ($Layer) { . $Layer }

# ---- BoxGuard.ps1 (copy) ----
function Get-ThornswoodBoxRefusal {
    # scripts\vps\BoxGuard.ps1 says why this asks Windows rather than looking
    # for the game, and why it refuses when it cannot tell (#3041).
    try { $type = [int](Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).ProductType }
    catch { return ('Windows did not say whether this is a server (' + $_.Exception.Message + '), so it is not taken for the box') }
    if ($type -eq 2 -or $type -eq 3) { return '' }
    if ($type -eq 1) { return 'this is a Windows workstation, a gaming PC or a developer''s machine, not the box' }
    return ('Windows gives this machine product type ' + $type + ', which is not a server, so it is not taken for the box')
}
# ---- end BoxGuard.ps1 ----

# ---------------------------------------------------------------- the file ---
# Sets Key to Value everywhere sshd would read it, and above the first Match
# line when no global line says it: sshd takes the first value it reads, and a
# line under Match applies only to that match.
function Set-SshdOption([string[]]$Lines, [string]$Key, [string]$Value) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $Lines) { $out.Add($l) }
    $rx = '^(\s*)' + [regex]::Escape($Key) + '(\s+|\s*=\s*)(\S+)(.*)$'
    $matchAt = $out.Count
    for ($i = 0; $i -lt $out.Count; $i++) { if ($out[$i] -match '^\s*Match\s') { $matchAt = $i; break } }
    $global = $false
    for ($i = 0; $i -lt $out.Count; $i++) {
        $m = [regex]::Match($out[$i], $rx, 'IgnoreCase')
        if (-not $m.Success) { continue }
        if ($i -lt $matchAt) { $global = $true }
        if ($m.Groups[3].Value -ne $Value) { $out[$i] = $m.Groups[1].Value + $Key + ' ' + $Value + $m.Groups[4].Value }
    }
    if (-not $global) {
        $at = -1
        for ($i = 0; $i -lt $matchAt; $i++) {
            if ($out[$i] -match ('^\s*#\s*' + [regex]::Escape($Key) + '\b')) { $at = $i + 1; break }
        }
        if ($at -lt 0) { $at = $matchAt }
        $out.Insert($at, $Key + ' ' + $Value)
    }
    return , ($out.ToArray())
}

$changes = 0
$stopped = $false
function Say([string]$word, [string]$what) { Write-Output ($word + ' ' + $what) }
function Change([string]$what) {
    $script:changes++
    if ($DryRun) { Say 'WOULD' $what } else { Say 'CHANGED' $what }
}

function Invoke-Harden {
    # Only ever on the box (BoxGuard.ps1, carried below its layer).
    if (-not $Layer) {
        $notBox = Get-ThornswoodBoxRefusal
        if ($notBox) { $script:stopped = $true; Say 'STOP' ($notBox + '. Run Harden-VPS.ps1 on your machine; it sends this to the box.'); return }
    }

    # ---------------------------------------------------------- ssh stays ---
    $rules = @(Get-InboundRules)
    $sshRules = @($rules | Where-Object { $_.Action -eq 'Allow' -and ($_.Ports -contains '22') })
    if ($sshRules.Count) {
        foreach ($r in $sshRules) { Say 'KEPT' ("ssh: firewall rule '" + $r.DisplayName + "' allows port 22, left on") }
    } else {
        Say 'WARN' 'no enabled firewall rule names port 22; ssh is reaching the box some other way (a rule for any port, or the firewall off). Nothing here changes that.'
    }

    # ---------------------------------------------------- Remote Desktop ---
    $deny = Get-RdpDeny
    if ($deny -eq 1) { Say 'ALREADY' 'Remote Desktop connections refused (fDenyTSConnections 1)' }
    else {
        if (-not $DryRun) { Set-RdpDeny }
        Change ('Remote Desktop connections refused (fDenyTSConnections ' + $deny + ' to 1)')
    }

    $rdpRules = @($rules | Where-Object { $_.Action -eq 'Allow' -and ($_.Group -eq $RdpGroup -or $_.Ports -contains '3389') })
    foreach ($r in $rdpRules) {
        if ($r.Ports -contains '22') { Say 'KEPT' ("firewall rule '" + $r.DisplayName + "' covers port 22 as well as Remote Desktop, so it was left on. Look at it by hand."); continue }
        if (-not $DryRun) { Disable-InboundRule $r.Name }
        Change ("firewall rule '" + $r.DisplayName + "' turned off (allowed " + (($r.Ports | Where-Object { $_ }) -join ',') + ')')
    }
    if (-not $rdpRules.Count) { Say 'ALREADY' 'no enabled firewall rule lets Remote Desktop in' }

    $ts = Get-TermService
    if (-not $ts) { Say 'ALREADY' 'the Remote Desktop service is not installed' }
    else {
        if ($ts.Status -ne 'Stopped') {
            if (-not $DryRun) { Stop-TermService }
            Change ('Remote Desktop service stopped (was ' + $ts.Status + ')')
        } else { Say 'ALREADY' 'Remote Desktop service stopped' }
        if ($ts.StartType -ne 'Disabled') {
            if (-not $DryRun) { Disable-TermService }
            Change ('Remote Desktop service set to Disabled (was ' + $ts.StartType + ')')
        } else { Say 'ALREADY' 'Remote Desktop service Disabled' }
    }

    # ---------------------------------------------- services it never uses ---
    foreach ($svc in $IdleServices) {
        $st = Get-IdleService $svc.Name
        if (-not $st) { Say 'ALREADY' ($svc.Name + ' is not installed (' + $svc.Why + ')'); continue }
        if ($st.Status -ne 'Stopped') {
            if (-not $DryRun) { Stop-IdleService $svc.Name }
            Change ($svc.Name + ' stopped (was ' + $st.Status + '): ' + $svc.Why)
        } else { Say 'ALREADY' ($svc.Name + ' stopped') }
        if ($st.StartType -ne 'Disabled') {
            if (-not $DryRun) { Disable-IdleService $svc.Name }
            Change ($svc.Name + ' set to Disabled (was ' + $st.StartType + ')')
        } else { Say 'ALREADY' ($svc.Name + ' Disabled') }
    }

    # ------------------------------------------------------- sshd_config ---
    if (-not (Test-Path -LiteralPath $SshdConfig)) { $script:stopped = $true; Say 'STOP' ("there is no sshd_config at " + $SshdConfig + ". sshd was not touched."); return }
    $text = [IO.File]::ReadAllText($SshdConfig)
    $nl = "`n"; if ($text.Contains("`r`n")) { $nl = "`r`n" }
    $lines = @($text -split "`r?`n")
    if ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines = @($lines[0..($lines.Count - 2)]) }
    $new = $lines
    foreach ($k in 'PasswordAuthentication', 'KbdInteractiveAuthentication') { $new = Set-SshdOption $new $k 'no' }
    $newText = ($new -join $nl) + $nl

    if ($newText -eq (($lines -join $nl) + $nl)) {
        Say 'ALREADY' 'sshd_config: PasswordAuthentication no, KbdInteractiveAuthentication no'
    } else {
        # The new file is checked from a temp copy first, so a line sshd does
        # not understand never reaches the one it starts from.
        $cand = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($cand, $newText, (New-Object Text.UTF8Encoding($false)))
        try { $check = Test-SshdFile $cand }
        finally { Remove-Item -LiteralPath $cand -Force -ErrorAction SilentlyContinue }
        if (-not $check.Ok) {
            $script:stopped = $true
            Say 'STOP' ('sshd -t refused the new sshd_config, so the old one is still in place and sshd was not restarted: ' + $check.Said)
            return
        }
        if ($DryRun) {
            Change 'sshd_config: PasswordAuthentication no, KbdInteractiveAuthentication no (sshd -t accepts the new file), then sshd restarted'
        } else {
            $backup = $SshdConfig + '.before-harden-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
            # Byte for byte, into a file only SYSTEM and Administrators may
            # open, not Copy-Item's, which takes the folder's rules.
            New-PrivateFile $backup
            [IO.File]::WriteAllBytes($backup, [IO.File]::ReadAllBytes($SshdConfig))
            # Written in place, so the file keeps the permissions sshd insists on.
            [IO.File]::WriteAllText($SshdConfig, $newText, (New-Object Text.UTF8Encoding($false)))
            Change ('sshd_config: PasswordAuthentication no, KbdInteractiveAuthentication no (old file kept as ' + $backup + ')')
            Register-Rollback $backup
            Say 'CHANGED' ("a task named '" + $RollbackTask + "' puts the old sshd_config back in ten minutes unless Harden-VPS.ps1 cancels it once key login is proven again")
            Start-SshdRestart
            Say 'CHANGED' 'sshd restarts in about five seconds'
        }
    }
}

try { Invoke-Harden }
catch {
    $stopped = $true
    Say 'STOP' ('it failed partway, at: ' + $_.Exception.Message)
}
finally {
    if ($DryRun) { Say 'DONE' ([string]$changes + ' change(s) would be made. Nothing was changed.') }
    elseif ($stopped) { Say 'DONE' ([string]$changes + ' change(s) made before it stopped.') }
    else { Say 'DONE' ([string]$changes + ' change(s) made.') }
}
if ($stopped) { exit 1 }
exit 0
