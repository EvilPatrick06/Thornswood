<#
  Lock-VpsFolders.ps1

  Takes the rule that lets every account on the box read them off the game
  servers', the voice services' and the backups' folders, now rather than at
  each one's next install (issues #1105 and #1173). Runs ON the VPS, as
  Administrator, through Remote.ps1.

      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Lock-VpsFolders.ps1 -Arguments '-WhatIf'
      .\scripts\vps\Remote.ps1 -File .\scripts\vps\Lock-VpsFolders.ps1

  WHY. Every folder made under C:\ inherits Windows' rule that BUILTIN\Users may
  read it and make files in it, and every service account on the box is in
  Users: the bot's NT SERVICE\ThornswoodBot, the site's LOCAL SERVICE, the
  build runner's. So each of them could read C:\Thornswood-Server\private\door.json
  and the dev one (the key the site trusts), server-settings.json, the voice
  services' token-key.txt and their chat logs. The game servers and voice run
  as SYSTEM, the site reads what Deploy-Docs.ps1 grants it by name, and the bot
  reads private\moderation.log through a rule on that file (Install-Bot.ps1).
  Nothing needs the Users rule.

  WHAT IT DOES, for C:\Thornswood-Server, C:\Thornswood-Server-Dev,
  C:\Thornswood-Voice, C:\Thornswood-Voice-Dev, the .prev, .undone and
  .failed folders the installers keep beside the servers, and
  C:\Thornswood-Backup (issue #1173), which holds the backup passphrase and
  every backup, and so every secret on the box: that one is SYSTEM's and
  Administrators' only, like private, and nothing else reads it. And the
  service folders (issues #1183 and #1691): C:\Thornswood-Watch,
  C:\Thornswood-Deploys, C:\Thornswood-Caddy and C:\Thornswood-Maint lose
  Users the same way, keeping their rules by name (the bot's on Watch, the
  site's on Deploys\current), and C:\Thornswood-Dumps is SYSTEM's and
  Administrators' only, since nothing known reads it. Watch is refused while
  the bot runs with no rule on it by name (run Install-Bot.ps1 first), and
  Deploys while the site has none on current (run Deploy-Docs.ps1 first).
    the folder takes nothing from C:\ any more; SYSTEM, Administrators and the
      account running this have Full Control; every rule set on it by name
      stays (the site's, a deny for the build runner); Users, Everyone,
      Authenticated Users and CREATOR OWNER go.
    data and private under a server the same way, and private keeps nothing
      of the root's: SYSTEM and Administrators only. Rules on single files,
      the bot's on moderation.log, stay where they are.
  Install-ThornswoodServer.ps1 does the same at every server install from now
  on, and vps-dev-instance.ps1 for the dev folders it makes.

  WHAT IT REFUSES.
    - anywhere with SkyrimSE.exe on it, which is the gaming PC, not the VPS
    - an account that is not an elevated Administrator
    - a folder whose name is not one of the above, or that is a link
    - a server or voice folder the site's account has no rule on by name,
      when the site runs as an account of its own (LOCAL SERVICE): taking
      Users off it would stop the site reading server.log or the chat logs.
      Deploy-Docs.ps1 gives it that rule; run it first. That folder is left
      as it is and the rest go ahead.
  -WhatIf says what it would change and changes nothing. Every folder is read
  back afterwards: its rules, one line each, and whether Users still reaches it.

  tests\test-server-acl.ps1 and tests\test-vps-service-folders.ps1 run it against scratch folders.
#>
param(
    [switch]$WhatIf,
    # Where the folders are. Only the tests pass anything else.
    [string]$Parent = 'C:\',
    # The site's account as a SID; worked out from the site's task when empty.
    # 'none' says there is no site on this box to keep reading.
    [string]$SiteSid = '',
    # The tests run on a machine with the game, as an account that is not an
    # elevated Administrator, against scratch folders. Nothing else passes it.
    [switch]$AllowGamingPc,
    # The bot's account as a SID; worked out from NT SERVICE\ThornswoodBot when
    # empty. 'none' says there is no bot on this box to keep reading the watchdog.
    [string]$BotSid = ''
)
$ErrorActionPreference = 'Stop'
function Say([string]$m) { Write-Output $m }

if (-not $AllowGamingPc) {
    if (Test-Path 'C:\Thornswood\Game\SkyrimSE.exe') { Say 'REFUSED: SkyrimSE.exe is here, so this is the gaming PC, not the VPS. Nothing was changed.'; exit 1 }
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Say 'REFUSED: this is not an elevated Administrator. Nothing was changed.'; exit 1 }
}

$broad = @('S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-3-0')
$tree = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
$keepers = @('S-1-5-18', 'S-1-5-32-544', [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
$nameRule = '^(Thornswood-(Server|Server-Dev|Voice|Voice-Dev)(\.(prev|undone|failed)-\d{8}-\d{6})?|Thornswood-Backup|Thornswood-(Watch|Deploys|Caddy|Maint|Dumps))$'
# The service folders (#1183, #1691). Each keeps its rules by name, and Users goes:
#   Watch    watch.ps1 and load.ps1 run as SYSTEM; the bot reads alerts and
#            writes alerts-sent-bot.txt by the rules Install-Bot.ps1 gives it
#            (Grant-ThornswoodBotAccess), so the bot must have one first.
#   Deploys  the deploy store, written as Administrator over scp (Artifact.ps1);
#            the site reads current\ by the rule Deploy-Docs.ps1 gives it, so
#            the site must have one there first.
#   Caddy    caddy.exe runs as SYSTEM ('Thornswood Web', Setup-Domain.ps1);
#            nothing else reads it.
#   Maint    update.ps1 and dev-instance.ps1 run as SYSTEM; nothing else.
#   Dumps    nothing in scripts\ makes or reads it, so what is in it is not
#            known: SYSTEM's and Administrators' only, like the backups.
$svcRule = '^Thornswood-(Watch|Deploys|Caddy|Maint|Dumps)$'

# The site's account, from its task, when it is one of its own.
if (-not $SiteSid) {
    $SiteSid = 'none'
    try {
        $t = Get-ScheduledTask -TaskName 'Thornswood Docs' -ErrorAction Stop
        $s = (New-Object Security.Principal.NTAccount([string]$t.Principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value
        if ($s -ne 'S-1-5-18') { $SiteSid = $s }
    } catch { }
}
if (-not $BotSid) {
    $BotSid = 'none'
    if (Get-Service -Name 'ThornswoodBot' -ErrorAction SilentlyContinue) {
        try { $BotSid = (New-Object Security.Principal.NTAccount('NT SERVICE\ThornswoodBot')).Translate([Security.Principal.SecurityIdentifier]).Value } catch { }
    }
}
if ($SiteSid -ne 'none') { Say ('the site runs as ' + $SiteSid + ', so each folder must have its rule before Users comes off') }

function Explicit([string]$path) {
    return @((Get-Acl -LiteralPath $path).GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))
}
function Show([string]$path) {
    $acl = Get-Acl -LiteralPath $path
    $users = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object { $broad -contains $_.IdentityReference.Value })
    Say ('  ' + $path + ': ' + $(if ($acl.AreAccessRulesProtected) { 'takes nothing from above' } else { 'INHERITS from above' }) + ', ' +
         $(if ($users.Count) { 'USERS OR EVERYONE STILL REACH IT' } else { 'no Users rule' }))
    foreach ($r in @($acl.Access)) {
        $who = "$($r.IdentityReference)"
        Say ('      ' + $r.AccessControlType + ' ' + $who + ' ' + $r.FileSystemRights + $(if ($r.IsInherited) { ' (inherited)' } else { '' }))
    }
}
# $only: SYSTEM, Administrators and this account and nothing else by name
# (private); otherwise every rule by name stays but the broad ones.
function Lock([string]$path, [bool]$only) {
    $acl = Get-Acl -LiteralPath $path
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in @($acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))) {
        $id = $r.IdentityReference.Value
        if ($broad -contains $id -or ($only -and $keepers -notcontains $id)) { [void]$acl.RemoveAccessRuleSpecific($r) }
    }
    foreach ($s in $keepers) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            (New-Object Security.Principal.SecurityIdentifier($s)), 'FullControl', $tree, 'None', 'Allow')))
    }
    # Writes back only the access rules. Set-Acl can also try to write the audit
    # part, which needs a privilege the build runner's account does not have
    # (issue #1120, Set-ThornswoodAclAccess in Bot-Service.ps1).
    $item = Get-Item -LiteralPath $path -Force
    if ($PSVersionTable.PSEdition -eq 'Core') {
        if ($item -is [IO.DirectoryInfo]) { [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]$item, [Security.AccessControl.DirectorySecurity]$acl) }
        else { [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]$item, [Security.AccessControl.FileSecurity]$acl) }
    } else { $item.SetAccessControl($acl) }
}

$folders = @(Get-ChildItem -LiteralPath $Parent -Directory -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match $nameRule } | Sort-Object Name)
if (-not $folders.Count) { Say ('nothing to lock: no Thornswood server, voice or service folder in ' + $Parent) }
$refused = 0; $done = 0
foreach ($f in $folders) {
    $path = $f.FullName
    Say ''
    if ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) { Say ('REFUSED ' + $path + ': it is a link, left as it is'); $refused++; continue }
    # What the site reads here, and so must reach by its own rule.
    $isVoice = $f.Name -match '^Thornswood-Voice'
    $isBackup = $f.Name -eq 'Thornswood-Backup'
    $isSvc = $f.Name -match $svcRule
    if ($isSvc) {
        $need = $null
        if ($f.Name -eq 'Thornswood-Deploys' -and $SiteSid -ne 'none') { $need = @{ P = (Join-Path $path 'current'); S = $SiteSid; Who = 'the site''s'; Run = '.\scripts\deploy\Deploy-Docs.ps1' } }
        if ($f.Name -eq 'Thornswood-Watch' -and $BotSid -ne 'none') { $need = @{ P = $path; S = $BotSid; Who = 'the bot''s'; Run = '.\scripts\deploy\Install-Bot.ps1' } }
        if ($need -and (Test-Path -LiteralPath $need.P)) {
            $has = @(Explicit $need.P | Where-Object { $_.IdentityReference.Value -eq $need.S -and $_.AccessControlType -eq 'Allow' })
            if (-not $has.Count) {
                Say ('REFUSED ' + $path + ': ' + $need.Who + ' account has no rule on ' + $need.P + ' by name, so taking Users off would stop it reading it. Run ' + $need.Run + ' first, then this again. Left as it is.')
                $refused++; continue
            }
        }
    }
    $siteNeeds = if ($isVoice) { Join-Path $path 'chat' } else { $path }
    if ($SiteSid -ne 'none' -and -not $isBackup -and -not $isSvc -and $f.Name -notmatch '\.(prev|undone|failed)-' -and (Test-Path -LiteralPath $siteNeeds)) {
        $has = @(Explicit $siteNeeds | Where-Object { $_.IdentityReference.Value -eq $SiteSid -and $_.AccessControlType -eq 'Allow' })
        if (-not $has.Count) {
            Say ('REFUSED ' + $path + ': the site''s account has no rule on ' + $siteNeeds + ' by name, so taking Users off would stop the site reading it. Run .\scripts\deploy\Deploy-Docs.ps1 first, then this again. Left as it is.')
            $refused++; continue
        }
    }
    $parts = @(@{ P = $path; Only = ($isBackup -or $f.Name -eq 'Thornswood-Dumps') })
    if (-not $isVoice -and -not $isBackup -and -not $isSvc) {
        foreach ($sub in 'data', 'private') {
            $p = Join-Path $path $sub
            if (Test-Path -LiteralPath $p) { $parts += @{ P = $p; Only = ($sub -eq 'private') } }
        }
    }
    foreach ($x in $parts) {
        $going = @(Explicit $x.P | Where-Object { $broad -contains $_.IdentityReference.Value -or ($x.Only -and $keepers -notcontains $_.IdentityReference.Value) })
        $inherits = -not (Get-Acl -LiteralPath $x.P).AreAccessRulesProtected
        if ($WhatIf) {
            Say ('WOULD LOCK ' + $x.P + ': ' + $(if ($inherits) { 'stop taking rules from above, ' } else { '' }) + $going.Count + ' rule(s) by name would go' +
                 $(if ($x.Only) { ', SYSTEM and Administrators only' } else { '' }))
            continue
        }
        try { Lock $x.P $x.Only; Say ('locked ' + $x.P) }
        catch { Say ('COULD NOT LOCK ' + $x.P + ': ' + $_.Exception.Message); $refused++ }
    }
    if (-not $isVoice -and -not $isBackup -and -not $isSvc) {
        $mod = Join-Path $path 'private\moderation.log'
        if ((Test-Path -LiteralPath $mod) -and (Get-Service -Name 'ThornswoodBot' -ErrorAction SilentlyContinue)) {
            $botSid = ''
            try { $botSid = (New-Object Security.Principal.NTAccount('NT SERVICE\ThornswoodBot')).Translate([Security.Principal.SecurityIdentifier]).Value } catch { }
            if ($botSid -and -not @(Explicit $mod | Where-Object { $_.IdentityReference.Value -eq $botSid }).Count) {
                Say ('  the bot has no rule on ' + $mod + ', so it cannot read it: run .\scripts\deploy\Install-Bot.ps1 once')
            }
        }
    }
    if (-not $WhatIf) { foreach ($x in $parts) { Show $x.P }; $done++ }
}
Say ''
if ($WhatIf) { Say ('WHATIF: nothing was changed. ' + $folders.Count + ' folder(s) looked at, ' + $refused + ' refused.') }
else { Say ('LOCKED ' + $done + ' folder(s), ' + $refused + ' refused or failed.') }
if ($refused) { exit 1 }
