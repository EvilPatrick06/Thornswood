<#
  ServiceAccount.ps1

  The account the services that run code we deploy run as (#2578): both game
  servers, both voice services and Caddy. Until 16 Oct 2026 each of their
  installers registered its task as SYSTEM at the highest run level, so
  anything gamemode.js, voice-server.js or caddy.exe did, it did as SYSTEM:
  every secret on the box, the backups and their passphrase, the runners.

  Now each task runs as NT AUTHORITY\LOCAL SERVICE, Limited, the way the
  site already does (Deploy-Docs.ps1 -RunAs, which says why each part is
  there):
    - SeChangeNotifyPrivilege and no other privilege. LOCAL SERVICE is given
      "Impersonate a client" and "Replace a process level token" by default,
      and either can be turned into SYSTEM, so the task asks for the one it
      needs and is started without the rest.
    - ProcessTokenSidType Unrestricted, which puts a SID of the task's own
      (NT TASK\<task name>) in its token. Every grant below goes to that SID,
      not to LOCAL SERVICE, so the site and the other services, which are
      LOCAL SERVICE too, get nothing from them.

  A task's folder (Grant-ThornswoodServiceFolder):
    - the root and everything in it: read and execute, so the code the deploy
      put there is readable and nothing in it can be changed or deleted;
    - the root itself: make files and folders in it, for the logs and the
      folders a first start makes. CREATOR OWNER gets Modify on what it makes,
      so a log the service started it can write to, roll and cut, and a file
      somebody else put there it cannot;
    - the folders it keeps its state in (-Writable): Modify;
    - files already there that it must keep writing (-Files, the logs a
      SYSTEM task left behind): Modify on each.

  THE FAIL-SAFE (Test-ThornswoodServiceCannotReach). Before any installer
  moves a task to LOCAL SERVICE it reads the rules on the places no service
  may read (Get-ThornswoodServiceNeverReach), and refuses, with nothing
  changed, when Everyone, Authenticated Users, Users or LOCAL SERVICE may read
  one. -AsSystem on each installer registers the task as it was, SYSTEM and
  Highest, and is the way back.

  Install-ThornswoodServer.ps1 runs on the box and carries a copy of these
  functions (every file Publish-Server.ps1 sends is a recorded remote call);
  the test fails when the copy differs. Install-Voice.ps1 and
  Setup-Domain.ps1 run on this machine, so they send the functions as text
  inside the script they run on the box (Get-ThornswoodServiceAccountScript).
  tests\test-2578-service-principals.ps1 runs it on scratch folders.
#>

function New-ThornswoodServicePrincipal {
    param([switch]$AsSystem)
    if ($AsSystem) {
        return New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    }
    return New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\LOCAL SERVICE' -LogonType ServiceAccount -RunLevel Limited `
        -RequiredPrivilege 'SeChangeNotifyPrivilege' -ProcessTokenSidType Unrestricted
}

# The SID of a task registered with ProcessTokenSidType Unrestricted, or ''.
function Get-ThornswoodTaskSid {
    param([string]$TaskName)
    try {
        return (New-Object Security.Principal.NTAccount('NT TASK', $TaskName)).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch { return '' }
}

# The places no service that runs our code may read. -Own is the root of the
# service asking, whose own private folder or key it does need.
function Get-ThornswoodServiceNeverReach {
    param([string]$Own = '')
    $own = $Own.TrimEnd('\')
    $list = @('C:\Thornswood-Backup', 'C:\Thornswood-Deploys', 'C:\Thornswood-Watch', 'C:\Thornswood-Maint')
    foreach ($r in 'C:\Thornswood-Server', 'C:\Thornswood-Server-Dev') {
        if ($r -ine $own) { $list += (Join-Path $r 'private') }
    }
    foreach ($r in 'C:\Thornswood-Voice', 'C:\Thornswood-Voice-Dev') {
        if ($r -ine $own) { $list += (Join-Path $r 'token-key.txt') }
    }
    return $list
}

# Each rule that lets a broad group, LOCAL SERVICE or one of -Sids read one of
# -Paths, as a line. None means the move is safe. A path that is not there is
# passed over; one whose rules cannot be read is a problem.
function Test-ThornswoodServiceCannotReach {
    param([string[]]$Paths, [string[]]$Sids = @())
    $who = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-19') + @($Sids | Where-Object { $_ })
    # ReadData (ListDirectory on a folder), GENERIC_READ and GENERIC_ALL.
    $read = [long]0x90000001
    $problems = @()
    foreach ($p in @($Paths)) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        try { $acl = Get-Acl -LiteralPath $p }
        catch { $problems += ($p + ': its rules could not be read (' + $_.Exception.Message + ')'); continue }
        foreach ($r in @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))) {
            if ([string]$r.AccessControlType -ne 'Allow') { continue }
            if ($who -notcontains $r.IdentityReference.Value) { continue }
            if (([long][int]$r.FileSystemRights -band $read) -eq 0) { continue }
            $problems += ($p + ': ' + $r.IdentityReference.Value + ' may read it (' + $r.FileSystemRights + ')')
        }
    }
    # Unrolled: callers wrap it in @(), so none is a count of 0.
    return $problems
}

# Writes back only the access rules, never the audit part (#1120).
function Set-ThornswoodServiceAcl {
    param([string]$Path, $Acl)
    $item = Get-Item -LiteralPath $Path -Force
    if ($PSVersionTable.PSEdition -eq 'Core') {
        if ($item -is [IO.DirectoryInfo]) { [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]$item, [Security.AccessControl.DirectorySecurity]$Acl) }
        else { [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]$item, [Security.AccessControl.FileSecurity]$Acl) }
    } else { $item.SetAccessControl($Acl) }
}

# What one service's task may do in its folder (the header). Throws when a
# rule cannot be written; the caller puts the task back on SYSTEM then.
function Grant-ThornswoodServiceFolder {
    param([string]$Root, [string]$Sid, [string[]]$Writable = @(), [string[]]$Files = @())
    if (-not $Root -or -not (Test-Path -LiteralPath $Root)) { throw ('not here: ' + $Root) }
    if (-not $Sid) { throw 'no SID to grant to' }
    $fsr  = [Security.AccessControl.FileSystemRights]
    $inh  = [Security.AccessControl.InheritanceFlags]
    $prop = [Security.AccessControl.PropagationFlags]
    $tree = $inh::ContainerInherit -bor $inh::ObjectInherit
    $who  = New-Object Security.Principal.SecurityIdentifier($Sid)
    $made = New-Object Security.Principal.SecurityIdentifier('S-1-3-0')
    $said = @()

    $acl = Get-Acl -LiteralPath $Root
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($who, $fsr::ReadAndExecute, $tree, $prop::None, 'Allow')))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($who, ($fsr::CreateFiles -bor $fsr::CreateDirectories), $inh::None, $prop::None, 'Allow')))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($made, $fsr::Modify, $tree, $prop::InheritOnly, 'Allow')))
    Set-ThornswoodServiceAcl $Root $acl
    $said += ('read and run in ' + $Root + ', make files there, change only what it made')

    foreach ($w in @($Writable | Where-Object { $_ })) {
        $d = Join-Path $Root $w
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $a = Get-Acl -LiteralPath $d
        $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($who, $fsr::Modify, $tree, $prop::None, 'Allow')))
        Set-ThornswoodServiceAcl $d $a
        $said += ('change ' + $d)
    }
    foreach ($pat in @($Files | Where-Object { $_ })) {
        foreach ($f in @(Get-ChildItem -LiteralPath $Root -File -Force -Filter $pat -ErrorAction SilentlyContinue)) {
            $a = Get-Acl -LiteralPath $f.FullName
            $a.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($who, $fsr::Modify, 'Allow')))
            Set-ThornswoodServiceAcl $f.FullName $a
            $said += ('change ' + $f.FullName)
        }
    }
    return $said
}

# The functions above as text, for a script that runs on the box.
function Get-ThornswoodServiceAccountScript {
    $out = ''
    foreach ($n in 'New-ThornswoodServicePrincipal', 'Get-ThornswoodTaskSid', 'Get-ThornswoodServiceNeverReach',
                   'Test-ThornswoodServiceCannotReach', 'Set-ThornswoodServiceAcl', 'Grant-ThornswoodServiceFolder') {
        $out += 'function ' + $n + ' {' + (Get-Item ('function:' + $n)).ScriptBlock.ToString() + "}`r`n"
    }
    return $out
}
