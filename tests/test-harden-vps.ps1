<#
  test-harden-vps.ps1

      pwsh -NoProfile -File .\tests\test-harden-vps.ps1

  scripts\vps\Harden-VPS.ps1 refuses unless key login is proven, and
  scripts\vps\vps-harden.ps1 turns ssh password login and Remote Desktop off
  on the box without ever touching ssh on port 22.

  WHY. Issue #450. Patrick, 28 September: password login off once key login
  is proven, and Remote Desktop off ("I use SSH not RDP"). Both servers run on
  that one box and ssh is the only way in that is not the provider's console,
  so the order and the refusals matter more than the change itself: a
  hardening that ran without the key proven would lock everybody out.

  HOW. NEVER CONNECTS. Two halves.

  The box half runs vps-harden.ps1 here, in this process, with -Layer: a
  stand-in for every function in it that touches Windows (the registry value,
  the firewall rules, the Remote Desktop service, sshd -t, the scheduled
  tasks) that keeps its state in a table this harness reads. The sshd_config
  it edits is a copy of the Windows OpenSSH default in a temp folder. It
  checks: a dry run changes nothing; a real run sets PasswordAuthentication no
  and KbdInteractiveAuthentication no above the Match block, keeps the old
  file, turns the Remote Desktop rules and service off, leaves every rule for
  port 22 on, and arms the rollback and the restart; a second run changes
  nothing; a file sshd -t refuses is never put in place. And that every
  command in it that changes Windows sits inside a layer function, so the
  stand-in covers all of them.

  The machine half runs Harden-VPS.ps1 with ssh, scp and ssh-keygen as
  stand-ins (functions win over programs of the same name). ssh answers the
  key probe as told, names login methods from the stand-in sshd_config, and,
  given the script Send-Script.ps1 sends on its standard input, checks it
  carries the whole of vps-harden.ps1 and runs that file against the
  stand-in layer with the arguments the script gave it. It checks: no pinned
  key, or no key login, means a refusal before anything is sent; nothing is
  ever copied to the box (#3035); -WhatIf runs the box read only; a real run
  ends with key login proven, the rollback cancelled, password login refused
  and the port closed, and says FAIL when the port still answers.
  tests\test-3035-file-script.ps1 runs the sent form itself, in a process of
  its own.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here
$Box = Join-Path $repo 'scripts\vps\vps-harden.ps1'
$Driver = Join-Path $repo 'scripts\vps\Harden-VPS.ps1'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-harden-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)

# The Windows OpenSSH server's own sshd_config, as the box had it on
# 28 September (only the lines that matter, and its comments).
$defaultCfg = @(
    '# This is the sshd server system-wide configuration file.  See',
    '# sshd_config(5) for more information.',
    '',
    '#Port 22',
    '#PubkeyAuthentication yes',
    '',
    'AuthorizedKeysFile	.ssh/authorized_keys',
    '',
    '# To disable tunneled clear text passwords, change to no here!',
    '#PasswordAuthentication yes',
    '#PermitEmptyPasswords no',
    '',
    '# override default of no subsystems',
    'Subsystem	sftp	sftp-server.exe',
    '',
    '# Example of overriding settings on a per-user basis',
    '#Match User anoncvs',
    '#	AllowTcpForwarding no',
    '',
    'Match Group administrators',
    '       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys'
) -join "`r`n"
$defaultCfg += "`r`n"

$layerText = @'
function Get-RdpDeny { return [int]$global:Fake.fDeny }
function Set-RdpDeny { $global:Fake.fDeny = 1; $global:Fake.log.Add('Set-RdpDeny') }
function Get-InboundRules {
    foreach ($r in $global:Fake.rules) {
        if ($r.Enabled) { [pscustomobject]@{ Name = $r.Name; DisplayName = $r.DisplayName; Action = $r.Action; Group = $r.Group; Ports = @($r.Ports) } }
    }
}
function Disable-InboundRule([string]$Name) {
    foreach ($r in $global:Fake.rules) { if ($r.Name -eq $Name) { $r.Enabled = $false } }
    $global:Fake.log.Add('Disable-InboundRule ' + $Name)
}
function Get-TermService {
    if (-not $global:Fake.term) { return $null }
    return [pscustomobject]@{ Status = $global:Fake.term.Status; StartType = $global:Fake.term.StartType }
}
function Stop-TermService { $global:Fake.term.Status = 'Stopped'; $global:Fake.log.Add('Stop-TermService') }
function Disable-TermService { $global:Fake.term.StartType = 'Disabled'; $global:Fake.log.Add('Disable-TermService') }
function Test-SshdFile([string]$Path) {
    $global:Fake.checked.Add([IO.File]::ReadAllText($Path))
    return [pscustomobject]@{ Ok = [bool]$global:Fake.sshdOk; Said = 'line 12: Bad configuration option: KbdInteractiveAuthentication' }
}
function Start-SshdRestart { $global:Fake.restarts++; $global:Fake.log.Add('Start-SshdRestart') }
function Register-Rollback([string]$Backup) { $global:Fake.rollback = $Backup; $global:Fake.log.Add('Register-Rollback') }
function New-PrivateFile([string]$Path) {
    $global:Fake.private.Add([pscustomobject]@{ Path = $Path; Existed = (Test-Path -LiteralPath $Path) })
    [IO.File]::WriteAllBytes($Path, [byte[]]@())
    $global:Fake.log.Add('New-PrivateFile')
}
'@
$Layer = Join-Path $tmp 'layer.ps1'
[IO.File]::WriteAllText($Layer, $layerText, $utf8)

function New-Fake {
    $global:Fake = @{
        fDeny = 0
        rules = @(
            @{ Name = 'RemoteDesktop-UserMode-In-TCP'; DisplayName = 'Remote Desktop - User Mode (TCP-In)'; Action = 'Allow'; Group = '@FirewallAPI.dll,-28752'; Ports = @('3389'); Enabled = $true },
            @{ Name = 'RemoteDesktop-Shadow-In-TCP'; DisplayName = 'Remote Desktop - Shadow (TCP-In)'; Action = 'Allow'; Group = '@FirewallAPI.dll,-28752'; Ports = @('Any'); Enabled = $true },
            @{ Name = 'Custom-RDP'; DisplayName = 'RDP from anywhere'; Action = 'Allow'; Group = ''; Ports = @('3389'); Enabled = $true },
            @{ Name = 'Both-22-3389'; DisplayName = 'ssh and rdp together'; Action = 'Allow'; Group = ''; Ports = @('22', '3389'); Enabled = $true },
            @{ Name = 'OpenSSH-Server-In-TCP'; DisplayName = 'OpenSSH SSH Server (sshd)'; Action = 'Allow'; Group = 'OpenSSH Server'; Ports = @('22'); Enabled = $true },
            @{ Name = 'Block-RDP'; DisplayName = 'Thornswood: block RDP from outside'; Action = 'Block'; Group = ''; Ports = @('3389'); Enabled = $true },
            @{ Name = 'Thornswood-Game'; DisplayName = 'Thornswood game'; Action = 'Allow'; Group = ''; Ports = @('7777'); Enabled = $true }
        )
        term = @{ Status = 'Running'; StartType = 'Manual' }
        sshdOk = $true
        restarts = 0
        rollback = ''
        log = New-Object System.Collections.Generic.List[string]
        checked = New-Object System.Collections.Generic.List[string]
        private = New-Object System.Collections.Generic.List[object]
    }
}
function Rule([string]$name) { return @($global:Fake.rules | Where-Object { $_.Name -eq $name })[0] }

# Runs the box script here against the stand-ins.
function Invoke-BoxHere([string]$cfg, [switch]$Dry) {
    $a = @{ Layer = $Layer; SshdConfig = $cfg; Sshd = 'not-used.exe' }
    if ($Dry) { $a.DryRun = $true }
    $global:LASTEXITCODE = 0
    $out = @(& $Box @a 2>&1 | ForEach-Object { [string]$_ })
    return [pscustomobject]@{ Code = $LASTEXITCODE; Lines = $out }
}
function Has($lines, [string]$rx) { return (@($lines | Where-Object { $_ -match $rx }).Count -gt 0) }

try {
    # =================================================================== the box ===
    # ---- the file itself --------------------------------------------------------
    $boxText = [IO.File]::ReadAllText($Box)
    $errs = $null; $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($boxText, [ref]$tokens, [ref]$errs)
    Yes 'vps-harden.ps1 parses' (-not $errs -or $errs.Count -eq 0)
    Yes '  and is plain ASCII, which Windows PowerShell on the box reads right without a byte order mark' (-not ($boxText.ToCharArray() | Where-Object { [int]$_ -gt 127 }))

    $layerNames = @('Get-RdpDeny', 'Set-RdpDeny', 'Get-InboundRules', 'Disable-InboundRule', 'Get-TermService', 'Stop-TermService', 'Disable-TermService', 'Test-SshdFile', 'Start-SshdRestart', 'Register-Rollback', 'New-PrivateFile')
    $defined = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
    Yes 'every layer function the stand-in replaces is defined in it' (@($layerNames | Where-Object { $defined -notcontains $_ }).Count -eq 0)
    $fakeAst = [System.Management.Automation.Language.Parser]::ParseInput($layerText, [ref]$null, [ref]$null)
    $fakeNames = @($fakeAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
    Yes '  and the stand-in replaces every one of them' (@($layerNames | Where-Object { $fakeNames -notcontains $_ }).Count -eq 0)

    $touchers = 'Set-ItemProperty', 'Get-ItemProperty', 'Get-NetFirewallRule', 'Get-NetFirewallPortFilter', 'Disable-NetFirewallRule', 'Enable-NetFirewallRule',
                'Get-Service', 'Stop-Service', 'Set-Service', 'Restart-Service', 'Register-ScheduledTask', 'Start-ScheduledTask', 'Unregister-ScheduledTask', 'New-ItemProperty', 'Remove-NetFirewallRule'
    $loose = @()
    foreach ($c in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $name = $c.GetCommandName()
        if (-not $name -or $touchers -notcontains $name) { continue }
        $p = $c.Parent
        while ($p -and -not ($p -is [System.Management.Automation.Language.FunctionDefinitionAst])) { $p = $p.Parent }
        if (-not $p -or $layerNames -notcontains $p.Name) { $loose += ('{0} at line {1}' -f $name, $c.Extent.StartLineNumber) }
    }
    Yes ('every command in it that touches Windows is inside a layer function' + $(if ($loose.Count) { ': ' + ($loose -join ', ') } else { '' })) ($loose.Count -eq 0)
    # A copy written plainly into C:\ProgramData\ssh takes the folder's rule
    # for every signed in account (#3034), so rules are set in one place.
    $setAcl = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and [string]$n.Member -eq 'SetAccessControl' }, $true) | Where-Object {
        $p = $_.Parent; while ($p -and -not ($p -is [System.Management.Automation.Language.FunctionDefinitionAst])) { $p = $p.Parent }; -not $p -or $p.Name -ne 'New-PrivateFile' })
    $copies = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and @('Copy-Item', 'Set-Acl', 'icacls', 'icacls.exe') -contains $n.GetCommandName() }, $true))
    Yes '  a file''s rules are set only in New-PrivateFile, and no Copy-Item, Set-Acl or icacls makes or changes one' (-not $setAcl.Count -and -not $copies.Count)

    # ---- a dry run changes nothing ------------------------------------------------
    New-Fake
    $cfg = Join-Path $tmp 'sshd_config'
    [IO.File]::WriteAllText($cfg, $defaultCfg, $utf8)
    $r = Invoke-BoxHere $cfg -Dry
    Yes 'dry run: exits 0' ($r.Code -eq 0)
    Yes '  says WOULD for Remote Desktop, its two allow rules, its service and sshd_config' ((Has $r.Lines '^WOULD Remote Desktop connections refused') -and (Has $r.Lines "^WOULD firewall rule 'Remote Desktop - User Mode") -and
        (Has $r.Lines "^WOULD firewall rule 'RDP from anywhere'") -and (Has $r.Lines '^WOULD Remote Desktop service set to Disabled') -and (Has $r.Lines '^WOULD sshd_config: PasswordAuthentication no'))
    Yes '  and changes nothing: not the file, the registry value, a rule, the service' ([IO.File]::ReadAllText($cfg) -eq $defaultCfg -and $global:Fake.fDeny -eq 0 -and
        (Rule 'Custom-RDP').Enabled -and $global:Fake.term.StartType -eq 'Manual' -and $global:Fake.log.Count -eq 0)
    Yes '  nor restarts sshd or arms a rollback' ($global:Fake.restarts -eq 0 -and -not $global:Fake.rollback)
    Yes '  but does have sshd -t check the file it would write' ($global:Fake.checked.Count -eq 1 -and $global:Fake.checked[0] -match '(?m)^PasswordAuthentication no')
    Yes '  and has nothing of its own to delete, since it is never written on the box (#3035)' ($boxText -notmatch 'PSCommandPath|KeepSelf')
    Yes '  and its last line says nothing was changed' ($r.Lines[-1] -match '^DONE \d+ change\(s\) would be made\. Nothing was changed\.')

    # ---- a real run -------------------------------------------------------------------
    $r = Invoke-BoxHere $cfg
    $new = [IO.File]::ReadAllText($cfg)
    $newLines = @($new -split "`r`n")
    $matchAt = [array]::IndexOf($newLines, 'Match Group administrators')
    $pwAt = [array]::IndexOf($newLines, 'PasswordAuthentication no')
    $kbAt = [array]::IndexOf($newLines, 'KbdInteractiveAuthentication no')
    Yes 'real run: exits 0' ($r.Code -eq 0)
    Yes '  PasswordAuthentication no is a global line, above Match' ($pwAt -ge 0 -and $pwAt -lt $matchAt)
    Yes '  right under the commented default it replaces' ($pwAt -gt 0 -and $newLines[$pwAt - 1] -eq '#PasswordAuthentication yes')
    Yes '  KbdInteractiveAuthentication no too, above Match' ($kbAt -ge 0 -and $kbAt -lt $matchAt)
    Yes '  and the rest of the file is as it was, Match block included' (($new -replace '(?m)^(PasswordAuthentication|KbdInteractiveAuthentication) no\r\n', '') -eq $defaultCfg)
    $backups = @(Get-ChildItem -LiteralPath $tmp -Filter 'sshd_config.before-harden-*')
    Yes '  the old file is kept beside it' ($backups.Count -eq 1 -and [IO.File]::ReadAllText($backups[0].FullName) -eq $defaultCfg)
    Yes '  made by New-PrivateFile while it did not exist yet, so its rules are set before the old file goes in (#3034)' ($global:Fake.private.Count -eq 1 -and
        $global:Fake.private[0].Path -eq $backups[0].FullName -and -not $global:Fake.private[0].Existed -and $global:Fake.log.IndexOf('New-PrivateFile') -lt $global:Fake.log.IndexOf('Register-Rollback'))
    Yes '  Remote Desktop refused' ($global:Fake.fDeny -eq 1)
    Yes '  its allow rules off, the group ones and the one on 3389' (-not (Rule 'RemoteDesktop-UserMode-In-TCP').Enabled -and -not (Rule 'RemoteDesktop-Shadow-In-TCP').Enabled -and -not (Rule 'Custom-RDP').Enabled)
    Yes '  ssh''s rule on 22 left on' ((Rule 'OpenSSH-Server-In-TCP').Enabled -and (Has $r.Lines "^KEPT ssh: firewall rule 'OpenSSH SSH Server"))
    Yes '  a rule that covers 22 as well as 3389 left on, and said so' ((Rule 'Both-22-3389').Enabled -and (Has $r.Lines "^KEPT firewall rule 'ssh and rdp together' covers port 22"))
    Yes '  the block rule and the game''s rule not touched' ((Rule 'Block-RDP').Enabled -and (Rule 'Thornswood-Game').Enabled)
    Yes '  its service stopped and Disabled' ($global:Fake.term.Status -eq 'Stopped' -and $global:Fake.term.StartType -eq 'Disabled')
    Yes '  the rollback armed with the old file, then the restart, in that order' ($global:Fake.rollback -eq $backups[0].FullName -and
        $global:Fake.restarts -eq 1 -and $global:Fake.log.IndexOf('Register-Rollback') -lt $global:Fake.log.IndexOf('Start-SshdRestart'))
    Yes '  Remote Desktop before sshd, so a restart that cut the session off would come last' ($global:Fake.log.IndexOf('Disable-TermService') -lt $global:Fake.log.IndexOf('Register-Rollback'))
    Yes '  every change printed as CHANGED' (@($r.Lines | Where-Object { $_ -match '^CHANGED ' }).Count -ge 7)
    Yes '  and the count is in the last line' ($r.Lines[-1] -match '^DONE \d+ change\(s\) made\.$')

    # ---- a second run -----------------------------------------------------------------
    $r2 = Invoke-BoxHere $cfg
    Yes 'second run: nothing to change' ($r2.Code -eq 0 -and $r2.Lines[-1] -eq 'DONE 0 change(s) made.' -and -not (Has $r2.Lines '^(CHANGED|WOULD) '))
    Yes '  no second backup and no second restart' (@(Get-ChildItem -LiteralPath $tmp -Filter 'sshd_config.before-harden-*').Count -eq 1 -and $global:Fake.restarts -eq 1 -and $global:Fake.private.Count -eq 1)

    # ---- sshd -t refuses the new file ---------------------------------------------------
    New-Fake
    $global:Fake.sshdOk = $false
    $cfg2 = Join-Path $tmp 'refused\sshd_config'
    New-Item -ItemType Directory -Path (Split-Path $cfg2) -Force | Out-Null
    [IO.File]::WriteAllText($cfg2, $defaultCfg, $utf8)
    $r = Invoke-BoxHere $cfg2
    Yes 'a file sshd -t refuses: exit 1 and a STOP line saying why' ($r.Code -eq 1 -and (Has $r.Lines '^STOP sshd -t refused the new sshd_config.*Bad configuration option'))
    Yes '  the old file stays, with no backup, no rollback and no restart' ([IO.File]::ReadAllText($cfg2) -eq $defaultCfg -and
        @(Get-ChildItem -LiteralPath (Split-Path $cfg2) -Filter '*.before-harden-*').Count -eq 0 -and -not $global:Fake.rollback -and $global:Fake.restarts -eq 0)

    # ---- a file that already says yes, globally and under Match ---------------------------------
    New-Fake
    $cfg3 = Join-Path $tmp 'yes\sshd_config'
    New-Item -ItemType Directory -Path (Split-Path $cfg3) -Force | Out-Null
    $yesCfg = "PasswordAuthentication yes`r`nPasswordAuthentication yes`r`nSubsystem sftp sftp-server.exe`r`nMatch Group administrators`r`n    PasswordAuthentication yes`r`n    AuthorizedKeysFile x`r`n"
    [IO.File]::WriteAllText($cfg3, $yesCfg, $utf8)
    $r = Invoke-BoxHere $cfg3
    $t3 = [IO.File]::ReadAllText($cfg3)
    Yes 'a file that says yes: every PasswordAuthentication line becomes no, the one under Match too' ($r.Code -eq 0 -and $t3 -notmatch 'PasswordAuthentication yes' -and ([regex]::Matches($t3, 'PasswordAuthentication no')).Count -eq 3)
    Yes '  with no extra global line added' ($t3.StartsWith("PasswordAuthentication no`r`nPasswordAuthentication no`r`nSubsystem"))
    Yes '  and the Match line keeps its indent' ($t3 -match "(?m)^    PasswordAuthentication no\r$")

    # ---- no service, and ssh with no rule of its own -----------------------------------------
    New-Fake
    $global:Fake.term = $null
    $global:Fake.rules = @($global:Fake.rules | Where-Object { $_.Name -notin 'OpenSSH-Server-In-TCP', 'Both-22-3389' })
    $r = Invoke-BoxHere $cfg -Dry
    Yes 'no Remote Desktop service: said, not an error' ($r.Code -eq 0 -and (Has $r.Lines '^ALREADY the Remote Desktop service is not installed'))
    Yes 'no rule naming port 22: a WARN, and nothing about ssh changed' (Has $r.Lines '^WARN no enabled firewall rule names port 22')

    # ============================================================= the machine ===
    $vpsJson = Get-Content -LiteralPath (Join-Path $repo 'scripts\vps\vps.json') -Raw | ConvertFrom-Json
    $pin = [string]@($vpsJson.hostKeys)[0]
    $kh = Join-Path $tmp 'known_hosts'
    [IO.File]::WriteAllText($kh, "stand-in`n", $utf8)
    $far = Join-Path $tmp 'far'
    New-Item -ItemType Directory -Path $far -Force | Out-Null

    . (Join-Path $repo 'scripts\vps\Send-Script.ps1')
    $global:H = @{
        KeyWorks = $true; HostFp = $pin; Calls = (New-Object System.Collections.Generic.List[string])
        Far = $far; Layer = $Layer; Cfg = ''; Cancelled = $false; Sent = ''
        Box = $Box; BoxText = [IO.File]::ReadAllText($Box); Reader = (Get-ThornswoodStdinReader)
    }
    function global:ssh-keygen {
        $a = @($args | ForEach-Object { [string]$_ })
        if ($a -contains '-F') { '# Host 127.0.0.1 found: line 1'; ('127.0.0.1 ED25519 ' + $global:H.HostFp) ; $global:LASTEXITCODE = 0; return }
        $global:LASTEXITCODE = 1
    }
    function global:scp {
        # The real one is its own process; -WhatIf on the driver never reaches it.
        $WhatIfPreference = $false
        $a = @($args | ForEach-Object { [string]$_ })
        $global:H.Calls.Add('scp ' + ($a -join ' '))
        $leaf = ($a[-1] -split '/')[-1]
        Copy-Item -LiteralPath $a[-2] -Destination (Join-Path $global:H.Far $leaf) -Force
        $global:H.Sent = Join-Path $global:H.Far $leaf
        $global:LASTEXITCODE = 0
    }
    function global:ssh {
        $WhatIfPreference = $false
        $a = @($args | ForEach-Object { [string]$_ })
        $in = @($input | ForEach-Object { [string]$_ })
        $last = $a[-1]
        # The script as the box would run it: inline, or Send-Script.ps1's
        # reader on the line with the script on standard input.
        $s = ''
        if ($last -match 'EncodedCommand (\S+)') {
            $s = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Matches[1]))
            if ($s -eq $global:H.Reader -and $in.Count) { $s = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($in[0])) }
        }
        # vps-harden.ps1 whole, as a block with its arguments after it: the
        # file under test runs here with them, against the stand-in layer.
        $at = $s.IndexOf($global:H.BoxText)
        if ($at -ge 0) {
            $given = $s.Substring($at + $global:H.BoxText.Length).Trim().TrimStart('}').Trim()
            $global:H.Calls.Add(('ssh ' + (($a | Select-Object -SkipLast 1) -join ' ') + ' BOX ' + $given).TrimEnd())
            $out = @(& $global:H.Box -Layer $global:H.Layer -SshdConfig $global:H.Cfg -Sshd 'not-used.exe' -DryRun:($given -match '(^|\s)-DryRun(\s|$)') 2>&1 | ForEach-Object { [string]$_ })
            $code = $LASTEXITCODE
            $out
            $global:LASTEXITCODE = $code; return
        }
        $global:H.Calls.Add('ssh ' + ($a -join ' '))
        if ($a -contains '-v') {
            $cfgText = ''
            if ($global:H.Cfg -and (Test-Path -LiteralPath $global:H.Cfg)) { $cfgText = [IO.File]::ReadAllText($global:H.Cfg) }
            $m = 'publickey,password,keyboard-interactive'
            if ($cfgText -match '(?m)^PasswordAuthentication no' -and $cfgText -match '(?m)^KbdInteractiveAuthentication no') { $m = 'publickey' }
            'debug1: Remote protocol version 2.0, remote software version OpenSSH_for_Windows_9.5'
            ('debug1: Authentications that can continue: ' + $m)
            ('Administrator@127.0.0.1: Permission denied (' + $m + ').')
            $global:LASTEXITCODE = 255; return
        }
        if ($last -eq 'echo THORNSWOOD_KEY_OK') {
            if ($global:H.KeyWorks) { '** WARNING: connection is not using a post-quantum key exchange algorithm.'; 'THORNSWOOD_KEY_OK'; $global:LASTEXITCODE = 0 }
            else { 'Administrator@127.0.0.1: Permission denied (publickey).'; $global:LASTEXITCODE = 255 }
            return
        }
        if ($s) {
            if ($s -match 'Unregister-ScheduledTask -TaskName ''Thornswood harden rollback''') { $global:H.Cancelled = $true; 'ROLLBACK_CANCELLED' }
            $global:LASTEXITCODE = 0; return
        }
        $global:LASTEXITCODE = 1
    }

    # A port nothing listens on: bind one, then let it go.
    $l = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $l.Start(); $closedPort = $l.LocalEndpoint.Port; $l.Stop()

    function Invoke-Driver([hashtable]$extra) {
        $a = @{ Vps = '127.0.0.1'; User = 'Administrator'; KnownHosts = $kh; RdpPort = $closedPort; SettleSeconds = 0; NoPause = $true }
        foreach ($k in $extra.Keys) { $a[$k] = $extra[$k] }
        $global:LASTEXITCODE = 0
        $out = @(& $Driver @a 6>&1 2>&1 | ForEach-Object { [string]$_ })
        return [pscustomobject]@{ Code = $LASTEXITCODE; Lines = $out; Text = ($out -join "`n") }
    }
    function Fresh {
        New-Fake
        $global:H.Calls.Clear(); $global:H.Cancelled = $false; $global:H.Sent = ''
        $d = Join-Path $tmp ('m-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $global:H.Cfg = Join-Path $d 'sshd_config'
        [IO.File]::WriteAllText($global:H.Cfg, $defaultCfg, $utf8)
    }

    # ---- no pinned key in known_hosts ----------------------------------------------------
    Fresh
    $global:H.HostFp = 'SHA256:' + ('A' * 43)
    $r = Invoke-Driver @{}
    Yes 'known_hosts without the pinned key: refused, exit 1' ($r.Code -eq 1 -and $r.Text -match 'does not hold the key scripts\\vps\\vps\.json pins' -and $r.Text -match 'Setup-SshKey')
    Yes '  before any ssh at all' ($global:H.Calls.Count -eq 0)
    $global:H.HostFp = $pin

    # ---- key login not proven ----------------------------------------------------------
    Fresh
    $global:H.KeyWorks = $false
    $r = Invoke-Driver @{}
    Yes 'key login not proven: refused, exit 1, and says why' ($r.Code -eq 1 -and $r.Text -match 'Key login as Administrator is not proven' -and $r.Text -match 'Nothing was changed')
    Yes '  the only thing it did was the key probe' ($global:H.Calls.Count -eq 1 -and $global:H.Calls[0] -match 'echo THORNSWOOD_KEY_OK')
    Yes '  which allowed publickey and nothing else, with the host key checked' ($global:H.Calls[0] -match 'PreferredAuthentications=publickey' -and $global:H.Calls[0] -match 'StrictHostKeyChecking=yes' -and $global:H.Calls[0] -match 'BatchMode=yes')
    Yes '  nothing was sent and nothing changed' (-not $global:H.Sent -and [IO.File]::ReadAllText($global:H.Cfg) -eq $defaultCfg -and $global:Fake.log.Count -eq 0)
    $global:H.KeyWorks = $true

    # ---- -WhatIf -------------------------------------------------------------------------
    Fresh
    $r = Invoke-Driver @{ WhatIf = $true }
    Yes '-WhatIf: exit 0 and says nothing was changed' ($r.Code -eq 0 -and $r.Text -match 'Nothing was changed\. Run it again without -WhatIf')
    Yes '  the box ran read only' (@($global:H.Calls | Where-Object { $_ -match ' BOX -DryRun$' }).Count -eq 1 -and $r.Text -match 'WOULD sshd_config')
    Yes '  and nothing changed there' ([IO.File]::ReadAllText($global:H.Cfg) -eq $defaultCfg -and $global:Fake.log.Count -eq 0 -and $global:Fake.fDeny -eq 0)
    Yes '  vps-harden.ps1 went whole on ssh''s standard input, and nothing was copied to the box (#3035)' (
        -not $global:H.Sent -and @($global:H.Calls | Where-Object { $_ -like 'scp *' -or $_ -match '-File ' }).Count -eq 0)
    Yes '  it showed the login methods and the port before' ($r.Text -match 'login methods now\s+publickey, password, keyboard-interactive' -and $r.Text -match "port $closedPort now\s+does not answer")

    # ---- the real run ----------------------------------------------------------------------
    Fresh
    $r = Invoke-Driver @{}
    Yes 'real run: exit 0' ($r.Code -eq 0)
    Yes '  the box ran for real, after the key probe' (@($global:H.Calls | Where-Object { $_ -match ' BOX$' }).Count -eq 1 -and $global:H.Calls[0] -match 'echo THORNSWOOD_KEY_OK')
    Yes '  and made the change' ([IO.File]::ReadAllText($global:H.Cfg) -match '(?m)^PasswordAuthentication no' -and $global:Fake.fDeny -eq 1 -and $global:Fake.term.StartType -eq 'Disabled')
    Yes '  key login proven again before the rollback was cancelled' ($global:H.Cancelled -and
        (@($global:H.Calls | Select-Object -Skip 1 | ForEach-Object { $_ }) -join "`n") -match '(?s) BOX\n.*echo THORNSWOOD_KEY_OK.*\n.*EncodedCommand')
    Yes '  PASS for key login, password refused and the port closed' ($r.Text -match 'PASS  key login works' -and $r.Text -match 'PASS  password login refused \(the box offers publickey\)' -and $r.Text -match "PASS  port $closedPort closed from here")
    Yes '  every ssh it ran checked the host key, and nothing went by scp' (@($global:H.Calls | Where-Object { $_ -notmatch 'StrictHostKeyChecking=yes' -or $_ -like 'scp *' }).Count -eq 0)

    # ---- the port still answers --------------------------------------------------------------
    Fresh
    $open = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $open.Start()
    try { $r = Invoke-Driver @{ RdpPort = $open.LocalEndpoint.Port } }
    finally { $open.Stop() }
    Yes 'a port that still answers afterwards: FAIL and exit 1' ($r.Code -eq 1 -and $r.Text -match 'FAIL  port \d+ closed from here')

    # ---- the box stops ---------------------------------------------------------------------------
    Fresh
    $global:Fake.sshdOk = $false
    $r = Invoke-Driver @{}
    Yes 'the box stopping stops it too, exit 1, with no rollback to cancel' ($r.Code -eq 1 -and $r.Text -match 'The box stopped' -and -not $global:H.Cancelled)
}
finally {
    foreach ($f in 'ssh', 'scp', 'ssh-keygen') { Remove-Item -Path ("function:global:" + $f) -ErrorAction SilentlyContinue }
    Remove-Variable -Name Fake, H -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
