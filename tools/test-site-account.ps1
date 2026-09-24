<#
  test-site-account.ps1

      pwsh -NoProfile -File .\tools\test-site-account.ps1

  Deploy-Docs.ps1 -RunAs chooses the account the site's scheduled task runs
  as, and SYSTEM is the default.

  WHY THIS EXISTS. Entry 219 on the To Do List: "A real service as a low
  privilege account". The log half of that entry is done. What was left is
  the account: Deploy-Docs registered 'Thornswood Docs' with -RunLevel
  Highest -User 'SYSTEM', and for a task already on the box it called
  Set-ScheduledTask with only -Action and -Settings, so no other account could
  ever have reached it without deleting the task by hand. This is the
  parameter. SYSTEM stays the default until Patrick has chosen the account and
  tried it, so merging it changes nothing on the VPS.

  HOW. Deploy-Docs.ps1 talks to the VPS and is never run here. Its parameter
  block is read off the syntax tree. The script it sends up to start the site
  is one here-string, and this builds it the way the deploy does, from that
  same here-string with the same variables set, then:

    parses it, as the far end will
    checks Register-ScheduledTask and Set-ScheduledTask both carry the
      principal, and that each call binds to a parameter set the real cmdlet
      has, so -Principal is never mixed with -User or -RunLevel
    checks the principal for anything but SYSTEM is cut to one privilege,
      SeChangeNotifyPrivilege, with -ProcessTokenSidType Unrestricted. The
      entry asks for "a low privilege account", and on LOCAL SERVICE
      -RunLevel Limited removes nothing, because a built-in service account
      has no split token. Without the list the task can start with the
      account's impersonation and token replacing rights, either of which
      public tools turn into SYSTEM. Found in review on 24 Sep.
    runs the account block, between its markers, on this machine, with the
      folders it grants on swapped for scratch ones and the real icacls, and
      reads what it did back with Get-Acl and off the principal it built
    runs it again with icacls standing in and refusing, to see it says so
    runs the read-back after the task is registered against a task that
      stands in for Get-ScheduledTask, for the account and for the cut

  Writes only under its own temp folder. Never connects to anything and never
  registers a task.
#>
[CmdletBinding()]
param([string]$ToolsPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ToolsPath) { $ToolsPath = $Here }

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

$deploy = Join-Path $ToolsPath 'Deploy-Docs.ps1'
$errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($deploy, [ref]$null, [ref]$errs)
Yes 'Deploy-Docs.ps1 parses' ($errs.Count -eq 0)

# ---- the parameter ------------------------------------------------------------
$params = @{}
foreach ($p in $ast.ParamBlock.Parameters) { $params[$p.Name.VariablePath.UserPath] = $p }
$runAsParam = $params['RunAs']
Yes 'Deploy-Docs.ps1 takes -RunAs' ($null -ne $runAsParam)
$default = $null
if ($runAsParam -and $runAsParam.DefaultValue) { $default = $runAsParam.DefaultValue.SafeGetValue() }
Yes '-RunAs defaults to SYSTEM, so a deploy without it changes nothing' ($default -eq 'SYSTEM')
$set = @()
if ($runAsParam) {
    foreach ($at in $runAsParam.Attributes) {
        if ($at.TypeName.Name -eq 'ValidateSet') { $set = @($at.PositionalArguments | ForEach-Object { $_.SafeGetValue() }) }
    }
}
Yes '-RunAs takes SYSTEM and LOCAL SERVICE and nothing else' ((($set | Sort-Object) -join ',') -eq 'LOCAL SERVICE,SYSTEM')

# ---- the script it sends up ------------------------------------------------------
$remotes = @($ast.FindAll({ param($n)
    $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and
    $n.Extent.Text -like '*Register-ScheduledTask*'
}, $true))
Yes 'there is one script that registers the task' ($remotes.Count -eq 1)
if ($remotes.Count -ne 1) { Done }
$remote = $remotes[0]

# Only these four are filled in on this side. Anything else in there would be
# built from a variable this does not set, and the test would be testing a
# different script from the one that goes up.
$known = @('Task', 'Port', 'rootWin', 'RunAs')
$used = @($remote.NestedExpressions | ForEach-Object {
    if ($_ -is [System.Management.Automation.Language.VariableExpressionAst]) { $_.VariablePath.UserPath } else { $_.Extent.Text }
} | Sort-Object -Unique)
$strangers = @($used | Where-Object { $known -notcontains $_ })
Yes ('the script is filled in from $Task, $Port, $rootWin and $RunAs and nothing else' +
     $(if ($strangers.Count) { ' (also ' + ($strangers -join ', ') + ')' } else { '' })) ($strangers.Count -eq 0)

# The here-string, evaluated exactly as Deploy-Docs evaluates it.
function Build([string]$account, [string]$docsRoot) {
    $RunAs = $account
    $rootWin = $docsRoot
    $Task = 'Thornswood Docs'
    $Port = 3001
    return (& ([ScriptBlock]::Create($script:remote.Extent.Text)))
}

$open  = '# ==== thornswood site account ===='
$close = '# ==== end thornswood site account ===='
function BlockOf([string]$text) {
    $a = $text.IndexOf($open)
    $b = $text.IndexOf($close)
    if ($a -lt 0 -or $b -le $a) { return $null }
    return $text.Substring($a, $b + $close.Length - $a)
}
function CallsOf($scriptAst, [string]$name) {
    return @($scriptAst.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $name
    }, $true))
}
function NamesOf($cmd) {
    return @($cmd.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } |
             ForEach-Object { $_.ParameterName })
}
# True when every parameter named on the call is in one parameter set of the
# real cmdlet. Null when the cmdlet is not on this machine to ask.
function Binds($cmd) {
    $real = Get-Command $cmd.GetCommandName() -ErrorAction SilentlyContinue
    if (-not $real) { return $null }
    $names = @(NamesOf $cmd)
    foreach ($ps in $real.ParameterSets) {
        $has = @($ps.Parameters | ForEach-Object { $_.Name; $_.Aliases })
        if (@($names | Where-Object { $has -notcontains $_ }).Count -eq 0) { return $true }
    }
    return $false
}

foreach ($account in @('SYSTEM', 'LOCAL SERVICE')) {
    $text = Build $account 'C:\Thornswood-Docs'
    $perrs = $null
    $sent = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$perrs)
    Yes "$account`: the script that goes up parses" ($perrs.Count -eq 0)
    Yes "$account`: it is told the account" ($text.Contains("`$runAs = '$account'"))

    $block = BlockOf $text
    Yes "$account`: it carries the account block between its markers" ($null -ne $block)
    $firstStop = $text.IndexOf('Stop-Process')
    Yes "$account`: the account is worked out before anything is stopped" (
        $null -ne $block -and $firstStop -gt 0 -and $text.IndexOf($open) -lt $firstStop)

    $reg = @(CallsOf $sent 'Register-ScheduledTask')
    $upd = @(CallsOf $sent 'Set-ScheduledTask')
    Yes "$account`: one Register-ScheduledTask and one Set-ScheduledTask" ($reg.Count -eq 1 -and $upd.Count -eq 1)
    if ($reg.Count -eq 1 -and $upd.Count -eq 1) {
        $rn = @(NamesOf $reg[0])
        $un = @(NamesOf $upd[0])
        Yes "$account`: a new task is registered with the principal" ($rn -contains 'Principal')
        Yes "$account`: and not with -User 'SYSTEM' or -RunLevel written into the call" (
            $rn -notcontains 'User' -and $rn -notcontains 'RunLevel')
        Yes "$account`: a task already there is given the principal too, so -RunAs reaches it" ($un -contains 'Principal')
        Yes "$account`: and still its action and settings" ($un -contains 'Action' -and $un -contains 'Settings')
        $rb = Binds $reg[0]
        $ub = Binds $upd[0]
        if ($null -eq $rb -or $null -eq $ub) {
            Write-Host "SKIP  $account`: the ScheduledTasks cmdlets are not on this machine to bind against"
        } else {
            Yes "$account`: Register-ScheduledTask binds to one of its real parameter sets" $rb
            Yes "$account`: Set-ScheduledTask binds to one of its real parameter sets" $ub
        }
    }
}

# ---- the outside folders are the ones server.js reads ------------------------------
#
# Every C: path written into server.js is somewhere the site reads outside its
# own folder. Each one has to be granted, or the page that shows it goes blank
# the day the site stops being SYSTEM, with nothing in any log to say why.
$real = BlockOf (Build 'LOCAL SERVICE' 'C:\Thornswood-Docs')
Yes 'LOCAL SERVICE: its own folder gets Modify' ($real -and $real.Contains("@('C:\Thornswood-Docs', '(OI)(CI)M')"))
$serverJs = Get-Content -LiteralPath (Join-Path $ToolsPath 'docs-app\server.js') -Raw
$outside = @()
foreach ($m in [regex]::Matches($serverJs, "'([A-Za-z]:(?:\\\\|/)[^']*)'")) {
    $p = $m.Groups[1].Value.Replace('\\', '\').Replace('/', '\')
    if ([IO.Path]::GetExtension($p)) { $p = Split-Path -Parent $p }
    if ($outside -notcontains $p) { $outside += $p }
}
Yes "server.js names places outside its folder to read ($($outside.Count) of them)" ($outside.Count -ge 4)
foreach ($p in $outside) {
    Yes "LOCAL SERVICE: read on $p, which server.js reads" ($real -and $real.Contains("@('$p', '(OI)(NP)R')"))
}
$grantLines = @([regex]::Matches($real, "@\('([^']+)', '([^']+)'\)") | ForEach-Object { $_.Groups[1].Value + '|' + $_.Groups[2].Value })
Yes 'LOCAL SERVICE: nothing else is granted, and nothing outside its folder more than read' (
    $grantLines.Count -eq $outside.Count + 1 -and
    @($grantLines | Where-Object { $_ -notlike 'C:\Thornswood-Docs|*' -and $_ -notlike '*|(OI)(NP)R' }).Count -eq 0)

# ---- the privilege cut ---------------------------------------------------------------
#
# Read off the New-ScheduledTaskPrincipal calls in the script that goes up,
# not off its text, because the comment above them names the privileges too.
# The value after a parameter, or $null when the call does not name it.
function ArgOf($cmd, [string]$name) {
    $els = @($cmd.CommandElements)
    for ($i = 0; $i -lt $els.Count; $i++) {
        $e = $els[$i]
        if ($e -is [System.Management.Automation.Language.CommandParameterAst] -and $e.ParameterName -eq $name) {
            $v = $e.Argument
            if (-not $v -and $i + 1 -lt $els.Count) { $v = $els[$i + 1] }
            if (-not $v) { return $null }
            try { return @($v.SafeGetValue()) } catch { return @($v.Extent.Text) }
        }
    }
    return $null
}
$sentLs = [System.Management.Automation.Language.Parser]::ParseInput((Build 'LOCAL SERVICE' 'C:\Thornswood-Docs'), [ref]$null, [ref]$null)
$made    = @(CallsOf $sentLs 'New-ScheduledTaskPrincipal')
$sysMade = @($made | Where-Object { $_.Extent.Text -match "-UserId 'SYSTEM'" })
$lsMade  = @($made | Where-Object { $_.Extent.Text -notmatch "-UserId 'SYSTEM'" })
Yes 'there are two principals, one for SYSTEM and one for any other account' (
    $made.Count -eq 2 -and $sysMade.Count -eq 1 -and $lsMade.Count -eq 1)
if ($sysMade.Count -eq 1 -and $lsMade.Count -eq 1) {
    $privs = ArgOf $lsMade[0] 'RequiredPrivilege'
    Yes 'LOCAL SERVICE: the principal lists its privileges, so the task does not start with all of the account''s' ($null -ne $privs)
    Yes 'LOCAL SERVICE: and the list is SeChangeNotifyPrivilege alone' ((@($privs) -join ',') -eq 'SeChangeNotifyPrivilege')
    Yes 'LOCAL SERVICE: neither privilege that public tools turn into SYSTEM is listed' (
        @($privs) -notcontains 'SeImpersonatePrivilege' -and @($privs) -notcontains 'SeAssignPrimaryTokenPrivilege')
    Yes 'LOCAL SERVICE: the token SID type is Unrestricted' ((@(ArgOf $lsMade[0] 'ProcessTokenSidType') -join ',') -eq 'Unrestricted')
    $sn = @(NamesOf $sysMade[0])
    Yes 'SYSTEM: the principal it always had, with no privilege list and no token SID type' (
        $sn -notcontains 'RequiredPrivilege' -and $sn -notcontains 'ProcessTokenSidType')
    $pb = Binds $lsMade[0]
    if ($null -eq $pb) {
        Write-Host 'SKIP  New-ScheduledTaskPrincipal is not on this machine to bind against'
    } else {
        Yes 'LOCAL SERVICE: New-ScheduledTaskPrincipal binds to one of its real parameter sets' $pb
    }
}

# ---- run the block ----------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-site-account-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
function Put([string]$path, [string]$text) {
    $d = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    [IO.File]::WriteAllText($path, $text)
}
# The block's own folders, swapped for scratch ones. Every one of them has to
# be found and swapped, or this would be granting on the real C:\ folders.
function Scratch([string]$block, [hashtable]$map) {
    foreach ($k in $map.Keys) { $block = $block.Replace("'" + $k + "'", "'" + $map[$k] + "'") }
    return $block
}
# Runs a block in a scope of its own and hands back what it said and what it
# left behind.
function Run([string]$code) {
    $lines = @(. ([ScriptBlock]::Create($code)) 2>&1 | ForEach-Object { "$_" })
    return @{ said = $lines; principal = $principal; sid = $sid }
}
function RulesFor([string]$path, [string]$who) {
    return @((Get-Acl -LiteralPath $path).Access | Where-Object {
        try { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq $who } catch { $false }
    })
}
$fsr = [Security.AccessControl.FileSystemRights]
$writing = $fsr::WriteData -bor $fsr::AppendData -bor $fsr::Delete -bor $fsr::ChangePermissions -bor $fsr::TakeOwnership
function ReadsOnly($rules) {
    if (-not $rules.Count) { return $false }
    foreach ($r in $rules) {
        if (($r.FileSystemRights -band $fsr::ReadData) -eq 0) { return $false }
        if (($r.FileSystemRights -band $writing) -ne 0) { return $false }
    }
    return $true
}
function Modifies($rules) {
    foreach ($r in $rules) { if (($r.FileSystemRights -band $fsr::Modify) -eq $fsr::Modify) { return $true } }
    return $false
}

if (-not (Get-Command New-ScheduledTaskPrincipal -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP  New-ScheduledTaskPrincipal is not on this machine, so the account block was not run'
    Done
}
try {
    $docs   = Join-Path $tmp 'Thornswood-Docs'
    $server = Join-Path $tmp 'Thornswood-Server'
    $dev    = Join-Path $tmp 'Thornswood-Server-Dev'
    $voice  = Join-Path $tmp 'Thornswood-Voice\chat'
    $voiceDev = Join-Path $tmp 'Thornswood-Voice-Dev\chat'
    Put (Join-Path $docs 'config.json') '{}'
    Put (Join-Path $docs 'data\board.json') '{}'
    Put (Join-Path $server 'server.log') 'before'
    Put (Join-Path $server 'data\online.json') '{"now":0}'
    Put (Join-Path $server 'world\changeForms.json') '{}'
    Put (Join-Path $voice '2026-09-24.jsonl') '{}'
    Put (Join-Path $voiceDev '2026-09-24.jsonl') '{}'
    # $dev is left out on purpose: a box with no dev server has no folder.
    $map = @{
        'C:\Thornswood-Server\data'    = (Join-Path $server 'data')
        'C:\Thornswood-Server'         = $server
        'C:\Thornswood-Server-Dev'     = $dev
        'C:\Thornswood-Voice\chat'     = $voice
        'C:\Thornswood-Voice-Dev\chat' = $voiceDev
    }

    # -- SYSTEM: the principal it always had, and not one grant -----------------
    $script:icaclsCalls = 0
    $code = 'function icacls { $script:icaclsCalls++; $global:LASTEXITCODE = 0 }' + "`n" +
            (Scratch (BlockOf (Build 'SYSTEM' $docs)) $map)
    $r = Run $code
    Yes 'SYSTEM: the task runs as SYSTEM' ($r.principal -and $r.principal.UserId -eq 'SYSTEM')
    Yes 'SYSTEM: at Highest, as it was registered from the start' ($r.principal -and "$($r.principal.RunLevel)" -eq 'Highest')
    Yes 'SYSTEM: as a service account, so no password is kept' ($r.principal -and "$($r.principal.LogonType)" -eq 'ServiceAccount')
    Yes 'SYSTEM: nothing is granted anywhere, so the box is left as it was' ($script:icaclsCalls -eq 0)
    Yes 'SYSTEM: the principal it builds cuts no privileges and leaves the token SID type at Default' (
        $r.principal -and @($r.principal.RequiredPrivilege | Where-Object { $_ }).Count -eq 0 -and
        "$($r.principal.ProcessTokenSidType)" -eq 'Default')
    Yes 'SYSTEM: the SID it compares the read-back with is SYSTEM''s' ($r.sid -eq 'S-1-5-18')

    # -- LOCAL SERVICE, with the real icacls on the scratch folders -------------
    $block = Scratch (BlockOf (Build 'LOCAL SERVICE' $docs)) $map
    Yes 'LOCAL SERVICE: every folder in the block was swapped for a scratch one' ($block -notmatch "'C:\\Thornswood-")
    $r = Run $block
    $said = $r.said -join "`n"
    Yes 'LOCAL SERVICE: the task runs as LOCAL SERVICE' ($r.principal -and $r.principal.UserId -match 'LOCAL SERVICE$')
    $resolved = ''
    try { $resolved = (New-Object Security.Principal.NTAccount($r.principal.UserId)).Translate([Security.Principal.SecurityIdentifier]).Value } catch { }
    Yes 'LOCAL SERVICE: the name it gives the task resolves, and to S-1-5-19' ($resolved -eq 'S-1-5-19')
    # Limited is kept, but on a built-in service account it takes nothing
    # away. The privilege list is what makes this a low privilege account.
    Yes 'LOCAL SERVICE: at Limited' ($r.principal -and "$($r.principal.RunLevel)" -eq 'Limited')
    Yes 'LOCAL SERVICE: the principal it builds keeps SeChangeNotifyPrivilege and nothing else' (
        $r.principal -and (@($r.principal.RequiredPrivilege) -join ',') -eq 'SeChangeNotifyPrivilege')
    Yes 'LOCAL SERVICE: so SeImpersonatePrivilege and SeAssignPrimaryTokenPrivilege are not in it' (
        $r.principal -and @($r.principal.RequiredPrivilege | Where-Object { $_ }).Count -gt 0 -and
        @($r.principal.RequiredPrivilege) -notcontains 'SeImpersonatePrivilege' -and
        @($r.principal.RequiredPrivilege) -notcontains 'SeAssignPrimaryTokenPrivilege')
    Yes 'LOCAL SERVICE: with the token SID type Unrestricted' ($r.principal -and "$($r.principal.ProcessTokenSidType)" -eq 'Unrestricted')
    Yes 'LOCAL SERVICE: as a service account, so no password is kept' ($r.principal -and "$($r.principal.LogonType)" -eq 'ServiceAccount')
    Yes 'LOCAL SERVICE: it says what it granted' ($said -match [regex]::Escape("granted LOCAL SERVICE (OI)(CI)M on $docs"))
    Yes 'LOCAL SERVICE: a folder that is not there is said and skipped, not failed' (
        $said -match [regex]::Escape("not here, nothing granted: $dev") -and $said -notmatch 'COULD NOT GRANT')
    Yes 'LOCAL SERVICE: no folder was made that was not there' (-not (Test-Path -LiteralPath $dev))

    $ls = 'S-1-5-19'
    $own = RulesFor $docs $ls
    Yes 'its own folder: LOCAL SERVICE may change it' (Modifies $own)
    Yes 'its own folder: a file that was already there, config.json, inherits it' (Modifies (RulesFor (Join-Path $docs 'config.json') $ls))
    Yes 'its own folder: and one a folder down, data\board.json' (Modifies (RulesFor (Join-Path $docs 'data\board.json') $ls))
    Put (Join-Path $docs 'site.log') 'new'
    Yes 'its own folder: site.log made afterwards inherits it, so the roll can rename it' (Modifies (RulesFor (Join-Path $docs 'site.log') $ls))

    # server.log is deleted and made again at every server start. The grant has
    # to survive that, which a grant on the file would not.
    Remove-Item -LiteralPath (Join-Path $server 'server.log') -Force
    Put (Join-Path $server 'server.log') 'after a restart'
    Yes 'server.log made again after the grant can still be read' (ReadsOnly (RulesFor (Join-Path $server 'server.log') $ls))
    Yes 'online.json can be read' (ReadsOnly (RulesFor (Join-Path $server 'data\online.json') $ls))
    Yes 'the chat can be read' (ReadsOnly (RulesFor (Join-Path $voice '2026-09-24.jsonl') $ls))
    # The dev voice service writes its own chat folder, and a dev session on
    # /sessions reads it since main's #298.
    Yes 'the dev chat can be read' (ReadsOnly (RulesFor (Join-Path $voiceDev '2026-09-24.jsonl') $ls))
    Yes 'and none of those four can be written' (
        -not (Modifies (RulesFor (Join-Path $server 'server.log') $ls)) -and
        -not (Modifies (RulesFor (Join-Path $server 'data\online.json') $ls)) -and
        -not (Modifies (RulesFor (Join-Path $voice '2026-09-24.jsonl') $ls)) -and
        -not (Modifies (RulesFor (Join-Path $voiceDev '2026-09-24.jsonl') $ls)))
    Yes 'the world data under the server folder is not reached' (
        (RulesFor (Join-Path $server 'world\changeForms.json') $ls).Count -eq 0 -and
        (RulesFor (Join-Path $server 'world') $ls).Count -eq 0)

    # -- icacls refusing: said, and the rest still tried ------------------------
    $code = 'function icacls { ''Access is denied.''; $global:LASTEXITCODE = 5 }' + "`n" + $block
    $threw = $false
    $r = $null
    try { $r = Run $code } catch { $threw = $true }
    $said = ''
    if ($r) { $said = $r.said -join "`n" }
    $refused = @([regex]::Matches($said, 'COULD NOT GRANT')).Count
    Yes 'a grant that fails does not throw' (-not $threw)
    Yes 'each one that fails is said, with what icacls said, and the rest are still tried' (
        $refused -eq 5 -and $said -match 'Access is denied')

    # -- an account this box does not have: nothing is stopped ------------------
    $script:icaclsCalls = 0
    $code = 'function icacls { $script:icaclsCalls++; $global:LASTEXITCODE = 0 }' + "`n" +
            (Scratch (BlockOf (Build 'NOBODY AT ALL' $docs)) $map)
    $r = Run $code
    Yes 'an account that does not resolve is said' (($r.said -join "`n") -match 'NO SUCH ACCOUNT HERE: NOBODY AT ALL')
    Yes 'and nothing is granted and no principal is made' ($script:icaclsCalls -eq 0 -and $null -eq $r.principal)
    $whole = Build 'NOBODY AT ALL' 'C:\Thornswood-Docs'
    Yes 'and it returns from the block before the old site is stopped' (
        $whole.IndexOf('Nothing was stopped or changed.''; return') -gt 0 -and
        $whole.IndexOf('Nothing was stopped or changed.''; return') -lt $whole.IndexOf('Stop-Process'))

    # ---- the read-back, after the task is registered --------------------------
    $sent = [System.Management.Automation.Language.Parser]::ParseInput((Build 'LOCAL SERVICE' 'C:\Thornswood-Docs'), [ref]$null, [ref]$null)
    $top = @($sent.EndBlock.Statements)
    $at = -1
    for ($i = 0; $i -lt $top.Count; $i++) {
        $s = $top[$i]
        if ($s -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $s.Left.Extent.Text -eq '$who' -and $s.Right.Extent.Text -match 'Get-ScheduledTask') { $at = $i }
    }
    Yes 'the account the task runs as is read back after it is registered' (
        $at -gt 0 -and $at + 1 -lt $top.Count -and $top[$at + 1] -is [System.Management.Automation.Language.IfStatementAst] -and
        $top[$at].Extent.StartOffset -gt @(CallsOf $sent 'Set-ScheduledTask')[0].Extent.StartOffset)
    if ($at -gt 0 -and $at + 1 -lt $top.Count) {
        $readBack = $top[$at].Extent.Text + "`n" + $top[$at + 1].Extent.Text
        # The stand-in task carries a privilege list and token SID type as
        # well as the account, as Get-ScheduledTask's principal does.
        function ReadBack([string]$askedFor, [string]$sidAsked, [string]$taskSays, $privsSay, [string]$sidTypeSays) {
            $runAs = $askedFor
            $sid = $sidAsked
            $script:taskPrincipal = [pscustomobject]@{
                UserId = $taskSays; RunLevel = 'Limited'
                RequiredPrivilege = $privsSay; ProcessTokenSidType = $sidTypeSays
            }
            function Get-ScheduledTask { [pscustomobject]@{ Principal = $script:taskPrincipal } }
            # The comma keeps a one-line answer an array, so [0] is the line
            # and not its first letter.
            return ,@(. ([ScriptBlock]::Create($readBack)))
        }
        $cut = @('SeChangeNotifyPrivilege')
        $said = ReadBack 'LOCAL SERVICE' 'S-1-5-19' 'LOCAL SERVICE' $cut 'Unrestricted'
        Yes 'read-back: the task running as LOCAL SERVICE says so' ($said[0] -eq 'task runs as LOCAL SERVICE, run level Limited')
        Yes 'read-back: and says its privileges were cut' (
            $said.Count -eq 2 -and $said[1] -eq 'task privileges: SeChangeNotifyPrivilege only, token SID type Unrestricted')
        Yes 'read-back: with NT AUTHORITY in front, the same account still matches' (
            (ReadBack 'LOCAL SERVICE' 'S-1-5-19' 'NT AUTHORITY\LOCAL SERVICE' $cut 'Unrestricted')[0] -like 'task runs as *')
        Yes 'read-back: a task still on SYSTEM after asking for LOCAL SERVICE is shouted' (
            (ReadBack 'LOCAL SERVICE' 'S-1-5-19' 'SYSTEM' $null 'Default')[0] -eq 'THE TASK RUNS AS SYSTEM, NOT LOCAL SERVICE')
        $said = ReadBack 'LOCAL SERVICE' 'S-1-5-19' 'LOCAL SERVICE' $null 'Default'
        Yes 'read-back: a LOCAL SERVICE task that kept every privilege is shouted, not passed as done' (
            $said.Count -eq 2 -and $said[1] -like 'THE TASK KEEPS MORE THAN IT SHOULD: privileges every one LOCAL SERVICE has, token SID type Default*')
        $said = ReadBack 'LOCAL SERVICE' 'S-1-5-19' 'LOCAL SERVICE' @('SeChangeNotifyPrivilege', 'SeImpersonatePrivilege') 'Unrestricted'
        Yes 'read-back: and so is one that kept SeImpersonatePrivilege beside the one it needs' (
            $said.Count -eq 2 -and $said[1] -like 'THE TASK KEEPS MORE THAN IT SHOULD: privileges SeChangeNotifyPrivilege,SeImpersonatePrivilege,*')
        $said = ReadBack 'LOCAL SERVICE' 'S-1-5-19' 'LOCAL SERVICE' $cut 'Default'
        Yes 'read-back: and so is one whose token SID type did not take' (
            $said.Count -eq 2 -and $said[1] -like 'THE TASK KEEPS MORE THAN IT SHOULD:*token SID type Default*')
        $said = ReadBack 'SYSTEM' 'S-1-5-18' 'SYSTEM' $null 'Default'
        Yes 'read-back: SYSTEM asked and SYSTEM there says so, and nothing about privileges' (
            $said.Count -eq 1 -and $said[0] -like 'task runs as SYSTEM*')
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
