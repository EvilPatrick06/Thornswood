<#
  test-site-account.ps1

      pwsh -NoProfile -File .\tests\test-site-account.ps1

  Deploy-Docs.ps1 -RunAs chooses the account the site's scheduled task runs
  as. Left out, the task keeps the account it already has, and a task made
  for the first time is SYSTEM.

  WHY THIS EXISTS. Entry 219 on the To Do List: "A real service as a low
  privilege account". The log half of that entry is done. What was left is
  the account: Deploy-Docs registered 'Thornswood Docs' with -RunLevel
  Highest -User 'SYSTEM', and for a task already on the box it called
  Set-ScheduledTask with only -Action and -Settings, so no other account could
  ever have reached it without deleting the task by hand. This is the
  parameter. Merging it changes nothing on the VPS, because the task there
  is SYSTEM and a deploy without -RunAs keeps it SYSTEM.

  It had a default of SYSTEM at first, and review found on 24 Sep that this
  undid the switch: once -RunAs 'LOCAL SERVICE' had been run, the next plain
  deploy or -Site, which is what CLAUDE.md, Install-Bot and Set-Vps tell
  people to run, put the task back on SYSTEM at Highest and the read-back
  said so as if nothing were wrong. So there is no default, and the account
  block reads the account off the task when -RunAs is not given.

  Review found a second thing on 24 Sep that only a real task shows.
  Set-ScheduledTask -Principal merges the new principal into the old one and
  keeps its privilege list, so -RunAs SYSTEM on a task that had been LOCAL
  SERVICE failed with "The task XML contains an unexpected node", the task
  stayed LOCAL SERVICE, and the way back the script promised did not work.
  Every check here passed, because none of them ever applied a principal to
  a task. So an elevated run now does, on a scratch task.

  HOW. Deploy-Docs.ps1 talks to the VPS and is never run here. Its parameter
  block is read off the syntax tree. The script it sends up to start the site
  is one here-string, and this builds it the way the deploy does, from that
  same here-string with the same variables set, then:

    parses it, as the far end will
    checks Register-ScheduledTask carries the principal, and that a task
      already there is handed back whole with the principal set on it rather
      than through Set-ScheduledTask -Principal, and that each call binds to
      a parameter set the real cmdlet has, so -Principal is never mixed with
      -User or -RunLevel
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
    runs it with no -RunAs against a task that stands in for the one on the
      box, on SYSTEM, on LOCAL SERVICE and on an account set by hand, to see
      each one keeps its account, and with -RunAs against each to see that
      what -RunAs says wins
    runs the read-back after the task is registered against a task that
      stands in for Get-ScheduledTask, for the account and for the cut
    when it is elevated, which the build check on GitHub is, runs the account
      block, the code that registers or updates the task and the read-back,
      all cut from the script that goes up, against one real scratch task,
      through every change of account a deploy makes, and reads the task back
      after each. Not elevated, that part says SKIP.

  Writes only under its own temp folder and, when elevated, one scheduled
  task whose action is cmd.exe /c exit. That task is never started and is
  removed before this ends. Never connects to anything.
#>
[CmdletBinding()]
param([string]$RepoPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $RepoPath) { $RepoPath = $Here }

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

$deploy = Join-Path $RepoPath 'scripts\deploy\Deploy-Docs.ps1'
$errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($deploy, [ref]$null, [ref]$errs)
Yes 'Deploy-Docs.ps1 parses' ($errs.Count -eq 0)

# ---- the parameter ------------------------------------------------------------
$params = @{}
foreach ($p in $ast.ParamBlock.Parameters) { $params[$p.Name.VariablePath.UserPath] = $p }
$runAsParam = $params['RunAs']
Yes 'Deploy-Docs.ps1 takes -RunAs' ($null -ne $runAsParam)
# Any default at all would be put on the task at every deploy that left
# -RunAs out, which is how SYSTEM came back after the switch.
Yes '-RunAs has no default, so a deploy without it keeps the account the task has' (
    $runAsParam -and $null -eq $runAsParam.DefaultValue)
# Kept for Build below, so a deploy that leaves -RunAs out is built with
# whatever the script would really put there.
$script:runAsDefault = ''
if ($runAsParam -and $runAsParam.DefaultValue) {
    try { $script:runAsDefault = [string]$runAsParam.DefaultValue.SafeGetValue() } catch { $script:runAsDefault = '' }
}
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

# The here-string, evaluated exactly as Deploy-Docs evaluates it. An empty
# account is a deploy with no -RunAs, which gets the parameter's default.
# The task name is the real one unless a scratch task is being driven.
function Build([string]$account, [string]$docsRoot, [string]$taskName = 'Thornswood Docs') {
    if (-not $account) { $account = $script:runAsDefault }
    $RunAs = $account
    $rootWin = $docsRoot
    $Task = $taskName
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

# '' is a deploy with no -RunAs, which is every routine one.
foreach ($account in @('', 'SYSTEM', 'LOCAL SERVICE')) {
    $label = $account
    if (-not $label) { $label = 'no -RunAs' }
    $text = Build $account 'C:\Thornswood-Docs'
    $perrs = $null
    $sent = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$perrs)
    Yes "$label`: the script that goes up parses" ($perrs.Count -eq 0)
    Yes "$label`: it is told the account, or told none" ($text.Contains("`$runAs = '$account'"))

    $block = BlockOf $text
    Yes "$label`: it carries the account block between its markers" ($null -ne $block)
    # Since issue #446 this block stops nothing: it ends with SETUP DONE, and
    # only then does Deploy-Docs send the swap that stops the old site.
    $firstStop = $text.IndexOf('Stop-Process')
    Yes "$label`: the account is worked out, and the block stops nothing" (
        $null -ne $block -and $firstStop -lt 0 -and $text.IndexOf($open) -lt $text.IndexOf("'SETUP DONE'"))

    $reg = @(CallsOf $sent 'Register-ScheduledTask')
    $upd = @(CallsOf $sent 'Set-ScheduledTask')
    Yes "$label`: one Register-ScheduledTask and one Set-ScheduledTask" ($reg.Count -eq 1 -and $upd.Count -eq 1)
    if ($reg.Count -eq 1 -and $upd.Count -eq 1) {
        $rn = @(NamesOf $reg[0])
        $un = @(NamesOf $upd[0])
        Yes "$label`: a new task is registered with the principal" ($rn -contains 'Principal')
        Yes "$label`: and not with -User 'SYSTEM' or -RunLevel written into the call" (
            $rn -notcontains 'User' -and $rn -notcontains 'RunLevel')
        # Which principal that is, with and without -RunAs, is run below
        # against a task standing in for the one on the box, and, elevated,
        # against a real one.
        #
        # A task already there is handed back whole, as the object
        # Set-ScheduledTask takes from the pipeline, with the principal, the
        # action and the settings set on it first. Set-ScheduledTask
        # -Principal merges into the old principal and keeps its privilege
        # list, which is how -RunAs SYSTEM after LOCAL SERVICE failed.
        $fed = ''
        $pipe = $upd[0].Parent
        if ($pipe -is [System.Management.Automation.Language.PipelineAst] -and
            $pipe.PipelineElements.Count -ge 2 -and $pipe.PipelineElements[1] -eq $upd[0] -and
            $pipe.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst] -and
            $pipe.PipelineElements[0].Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $fed = $pipe.PipelineElements[0].Expression.Extent.Text
        }
        $setOn = @()
        if ($fed) {
            $setOn = @($sent.FindAll({ param($n)
                $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left -is [System.Management.Automation.Language.MemberExpressionAst] -and
                $n.Left.Expression.Extent.Text -eq $fed -and
                $n.Extent.EndOffset -lt $upd[0].Extent.StartOffset
            }, $true) | ForEach-Object { $_.Left.Member.Extent.Text })
        }
        Yes "$label`: a task already there is handed to Set-ScheduledTask whole, with the principal set on it, so -RunAs reaches it" (
            $fed -and $setOn -contains 'Principal')
        Yes "$label`: and still its action and settings" ($setOn -contains 'Actions' -and $setOn -contains 'Settings')
        Yes "$label`: and not through Set-ScheduledTask -Principal, which keeps the old privilege list" ($un -notcontains 'Principal')
        $rb = Binds $reg[0]
        $ub = Binds $upd[0]
        if ($null -eq $rb -or $null -eq $ub) {
            Write-Host "SKIP  $label`: the ScheduledTasks cmdlets are not on this machine to bind against"
        } else {
            Yes "$label`: Register-ScheduledTask binds to one of its real parameter sets" $rb
            Yes "$label`: Set-ScheduledTask binds to one of its real parameter sets" $ub
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
$serverJs = Get-Content -LiteralPath (Join-Path $RepoPath 'site\server.js') -Raw
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
    # The deploy records /api/deploys lists (#459).
    $deploys = Join-Path $tmp 'Thornswood-Deploys\current'
    Put (Join-Path $docs 'config.json') '{}'
    Put (Join-Path $docs 'data\board.json') '{}'
    Put (Join-Path $server 'server.log') 'before'
    Put (Join-Path $server 'data\online.json') '{"now":0}'
    Put (Join-Path $server 'world\changeForms.json') '{}'
    Put (Join-Path $voice '2026-09-24.jsonl') '{}'
    Put (Join-Path $voiceDev '2026-09-24.jsonl') '{}'
    Put (Join-Path $deploys 'thornswood-docs.json') '{}'
    # The update feed the site serves and must not write (#913).
    Put (Join-Path $docs 'feed\version.json') '{}'
    Put (Join-Path $docs 'feed\assets\0000000000000000000000000000000000000000000000000000000000000000') 'x'
    Put (Join-Path $docs 'feed-dev\version.json') '{}'
    # BUILTIN\Users reaches the real site folder by inheriting from C:\. The
    # scratch one gets the same, from the scratch folder above it.
    $usersSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
    $top = Get-Acl -LiteralPath $tmp
    $top.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($usersSid, 'ReadAndExecute',
        [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
        [Security.AccessControl.PropagationFlags]::None, 'Allow')))
    Set-Acl -LiteralPath $tmp -AclObject $top
    # $dev is left out on purpose: a box with no dev server has no folder.
    $map = @{
        'C:\Thornswood-Server\data'    = (Join-Path $server 'data')
        'C:\Thornswood-Server'         = $server
        'C:\Thornswood-Server-Dev'     = $dev
        'C:\Thornswood-Voice\chat'     = $voice
        'C:\Thornswood-Voice-Dev\chat' = $voiceDev
        'C:\Thornswood-Deploys\current' = $deploys
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
    Yes 'the deploy records: LOCAL SERVICE reads them and changes nothing (#459)' (ReadsOnly (RulesFor (Join-Path $deploys 'thornswood-docs.json') $ls))
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

    # -- #913: the feed is read, never written, by the site account ---------------
    # A deny that carries SYNCHRONIZE stops node opening the file at all, which
    # is what icacls' W did to both feeds on 28 Sep.
    $noWrite = $fsr::WriteData -bor $fsr::AppendData -bor $fsr::WriteExtendedAttributes -bor
               $fsr::WriteAttributes -bor $fsr::Delete -bor $fsr::DeleteSubdirectoriesAndFiles
    function DeniesOf($rules) { return @($rules | Where-Object { "$($_.AccessControlType)" -eq 'Deny' }) }
    foreach ($f in @('feed', 'feed-dev')) {
        $d = DeniesOf (RulesFor (Join-Path $docs $f) $ls)
        Yes "$f`: the site account is denied writing and deleting there" (
            $d.Count -eq 1 -and ($d[0].FileSystemRights -band $noWrite) -eq $noWrite)
        Yes "$f`: and the deny leaves out SYNCHRONIZE and every read right, so the site still serves it" (
            $d.Count -eq 1 -and ($d[0].FileSystemRights -band ($fsr::Synchronize -bor $fsr::ReadData -bor $fsr::ReadAttributes)) -eq 0)
        Yes "$f`: and reaches what is inside it" ($d.Count -eq 1 -and "$($d[0].InheritanceFlags)" -eq 'ContainerInherit, ObjectInherit')
        Yes "$f`: it says so" ($said -match [regex]::Escape("denied LOCAL SERVICE writing and deleting in " + (Join-Path $docs $f)))
    }
    $vj = RulesFor (Join-Path $docs 'feed\version.json') $ls
    Yes 'feed\version.json inherits the deny and still the read under it' (
        (DeniesOf $vj).Count -eq 1 -and (Modifies @($vj | Where-Object { "$($_.AccessControlType)" -eq 'Allow' })))
    Yes 'feed\assets inherits the deny too' (
        (DeniesOf (RulesFor (Join-Path $docs 'feed\assets\0000000000000000000000000000000000000000000000000000000000000000') $ls)).Count -eq 1)
    Yes 'the rest of its folder is not denied anything' (
        (DeniesOf (RulesFor (Join-Path $docs 'data\board.json') $ls)).Count -eq 0 -and
        (DeniesOf (RulesFor (Join-Path $docs 'config.json') $ls)).Count -eq 0)
    Yes 'the deploy script never denies with icacls, whose W carries SYNCHRONIZE' (
        (Get-Content -LiteralPath $deploy -Raw) -notmatch 'icacls[^\r\n]*/deny')

    # -- #913: BUILTIN\Users no longer reaches the site folder ---------------------
    $u = 'S-1-5-32-545'
    Yes 'the scratch folder above gave BUILTIN\Users read, as C:\ does on the box' ((RulesFor $tmp $u).Count -ge 1)
    Yes 'BUILTIN\Users has nothing on the site folder' ((RulesFor $docs $u).Count -eq 0)
    Yes 'nor on config.json, data or the feed' (
        (RulesFor (Join-Path $docs 'config.json') $u).Count -eq 0 -and
        (RulesFor (Join-Path $docs 'data\board.json') $u).Count -eq 0 -and
        (RulesFor (Join-Path $docs 'feed\version.json') $u).Count -eq 0)
    Yes 'the site folder stopped inheriting, so a rule put back on the folder above does not come back' (
        (Get-Acl -LiteralPath $docs).AreAccessRulesProtected)
    $meSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Yes 'whoever ran it keeps what they had there (Administrators on the box)' (
        (Modifies (RulesFor $docs $meSid)) -or (Modifies (RulesFor $docs 'S-1-5-32-544')))
    Yes 'and the site account keeps Modify on its folder' (Modifies (RulesFor (Join-Path $docs 'config.json') $ls))
    Yes 'it says Users was taken off' ($said -match 'BUILTIN\\Users no longer reaches')
    # What it said instead, so a red on the build runner shows why in the log.
    foreach ($l in @(($said -split "`n") | Where-Object { $_ -match 'COULD NOT' })) { Write-Host ('      ' + $l) }

    # The grants are given again at every deploy while the site is not SYSTEM,
    # so a second run has to leave the same rules, not a second copy of each.
    $before = @($docs, $server, (Join-Path $server 'data'), $voice, $voiceDev | ForEach-Object { (RulesFor $_ $ls).Count })
    $r = Run $block
    $after = @($docs, $server, (Join-Path $server 'data'), $voice, $voiceDev | ForEach-Object { (RulesFor $_ $ls).Count })
    Yes ('a second run grants again without doubling a rule (' + ($before -join ',') + ' then ' + ($after -join ',') + ')') (
        ($before -join ',') -eq ($after -join ',') -and @($after | Where-Object { $_ -ne 1 }).Count -eq 0)
    Yes 'a second run leaves one deny on each feed folder, not two' (
        (DeniesOf (RulesFor (Join-Path $docs 'feed') $ls)).Count -eq 1 -and
        (DeniesOf (RulesFor (Join-Path $docs 'feed-dev') $ls)).Count -eq 1)
    Yes 'and BUILTIN\Users is still off, with nothing refused' (
        (RulesFor $docs $u).Count -eq 0 -and ($r.said -join "`n") -notmatch 'COULD NOT (DENY|TAKE)')
    Yes 'and the second run still says what it granted, with nothing refused' (
        ($r.said -join "`n") -match [regex]::Escape("granted LOCAL SERVICE (OI)(CI)M on $docs") -and
        ($r.said -join "`n") -notmatch 'COULD NOT GRANT')

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
        $refused -eq 6 -and $said -match 'Access is denied')

    # -- an account this box does not have: nothing is stopped ------------------
    $script:icaclsCalls = 0
    $code = 'function icacls { $script:icaclsCalls++; $global:LASTEXITCODE = 0 }' + "`n" +
            (Scratch (BlockOf (Build 'NOBODY AT ALL' $docs)) $map)
    $r = Run $code
    Yes 'an account that does not resolve is said' (($r.said -join "`n") -match 'NO SUCH ACCOUNT HERE: NOBODY AT ALL')
    Yes 'and nothing is granted and no principal is made' ($script:icaclsCalls -eq 0 -and $null -eq $r.principal)
    $whole = Build 'NOBODY AT ALL' 'C:\Thornswood-Docs'
    $deployText = Get-Content -LiteralPath $deploy -Raw
    $gate = $deployText.IndexOf("if (`$setup -notcontains 'SETUP DONE')")
    Yes 'and it returns from the block before SETUP DONE, and Deploy-Docs swaps nothing without it' (
        $whole.IndexOf('Nothing was stopped or changed.''; return') -gt 0 -and
        $whole.IndexOf('Nothing was stopped or changed.''; return') -lt $whole.IndexOf("'SETUP DONE'") -and
        $gate -gt 0 -and $gate -lt $deployText.IndexOf('$serviceSwapBlock)'))

    # -- no -RunAs keeps the account the task already has -----------------------
    #
    # The finding of 24 Sep: with a default of SYSTEM, the next plain deploy or
    # -Site after -RunAs 'LOCAL SERVICE' put the task back on SYSTEM. Every
    # routine deploy leaves -RunAs out, so the block is run with none, against
    # a stand-in for the task on the box, and with -RunAs, to see it wins.
    $script:taskWas = $null
    $script:taskAsked = 0
    $standins = 'function icacls { $script:icaclsCalls++; $global:LASTEXITCODE = 0 }' + "`n" +
                'function Get-ScheduledTask { $script:taskAsked++; if ($script:taskWas) { [pscustomobject]@{ Principal = $script:taskWas } } }' + "`n"
    function Against([string]$given, [string]$taskRunsAs) {
        $script:icaclsCalls = 0
        $script:taskAsked = 0
        $script:taskWas = $null
        if ($taskRunsAs) { $script:taskWas = [pscustomobject]@{ UserId = $taskRunsAs; RunLevel = 'Limited' } }
        return Run ($standins + (Scratch (BlockOf (Build $given $docs)) $map))
    }
    # Folders the scratch box has, so the grants the block should give.
    $there = @($map.Values | Where-Object { Test-Path -LiteralPath $_ }).Count + 1

    $r = Against '' $null
    Yes 'no -RunAs and no task yet: a new task is SYSTEM, as it always was' (
        $r.principal -and $r.principal.UserId -eq 'SYSTEM' -and "$($r.principal.RunLevel)" -eq 'Highest' -and $r.sid -eq 'S-1-5-18')
    Yes 'and nothing is granted' ($script:icaclsCalls -eq 0)
    Yes 'and it says which account it kept' (($r.said -join "`n") -match 'no -RunAs, so the task keeps the account it has: SYSTEM')

    $r = Against '' 'SYSTEM'
    Yes 'no -RunAs, task on SYSTEM: it stays SYSTEM at Highest, nothing granted' (
        $r.principal -and $r.principal.UserId -eq 'SYSTEM' -and "$($r.principal.RunLevel)" -eq 'Highest' -and
        $r.sid -eq 'S-1-5-18' -and $script:icaclsCalls -eq 0)

    foreach ($name in @('LOCAL SERVICE', 'NT AUTHORITY\LOCAL SERVICE')) {
        $r = Against '' $name
        Yes "no -RunAs, task on $name`: it stays LOCAL SERVICE, not back to SYSTEM" (
            $r.principal -and $r.principal.UserId -match 'LOCAL SERVICE$' -and $r.sid -eq 'S-1-5-19')
        Yes "no -RunAs, task on $name`: with the privilege cut and token SID type it had" (
            $r.principal -and (@($r.principal.RequiredPrivilege) -join ',') -eq 'SeChangeNotifyPrivilege' -and
            "$($r.principal.ProcessTokenSidType)" -eq 'Unrestricted' -and "$($r.principal.RunLevel)" -eq 'Limited')
        Yes "no -RunAs, task on $name`: its folders are granted again ($there of them)" ($script:icaclsCalls -eq $there)
        Yes "no -RunAs, task on $name`: and it says it kept LOCAL SERVICE" (
            ($r.said -join "`n") -match 'no -RunAs, so the task keeps the account it has: LOCAL SERVICE')
    }

    # An account set on the task by hand, which the entry's own steps suggest
    # making: handed back to the task as it is, and nothing granted to it.
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    foreach ($name in @($me, 'NO SUCH USER 219')) {
        $r = Against '' $name
        Yes "no -RunAs, task on an account set by hand ($name): the task's own principal goes back unchanged" (
            $null -ne $r.principal -and [object]::ReferenceEquals($r.principal, $script:taskWas))
        Yes "no -RunAs, task on an account set by hand ($name): nothing is granted" ($script:icaclsCalls -eq 0)
        Yes "no -RunAs, task on an account set by hand ($name): it says it left it alone" (
            ($r.said -join "`n") -match 'left as it is, nothing granted')
    }

    # -RunAs wins over the task, and does not even ask it.
    $r = Against 'SYSTEM' 'LOCAL SERVICE'
    Yes '-RunAs SYSTEM on a LOCAL SERVICE task puts it back on SYSTEM' (
        $r.principal -and $r.principal.UserId -eq 'SYSTEM' -and "$($r.principal.RunLevel)" -eq 'Highest' -and $r.sid -eq 'S-1-5-18')
    Yes 'and it did not read the task to decide' ($script:taskAsked -eq 0)
    $r = Against 'LOCAL SERVICE' 'SYSTEM'
    Yes '-RunAs LOCAL SERVICE on a SYSTEM task moves it, with the cut' (
        $r.principal -and $r.principal.UserId -match 'LOCAL SERVICE$' -and
        (@($r.principal.RequiredPrivilege) -join ',') -eq 'SeChangeNotifyPrivilege' -and $script:icaclsCalls -eq $there)
    Yes 'and it did not read the task to decide either' ($script:taskAsked -eq 0)

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

    # ---- on a real task, when this is elevated ------------------------------------
    #
    # Everything above builds principals and reads stand-ins back. None of it
    # ever applied a principal to a task, and the fault review found on 24 Sep
    # shows only when one is: Set-ScheduledTask -Principal merged SYSTEM into a
    # LOCAL SERVICE principal, kept its privilege list and failed, so -RunAs
    # SYSTEM did not put the site back. So, elevated, the account block and
    # everything from the settings to the read-back of the account are cut
    # from the script that goes up and run against one scratch task, through
    # every change of account a deploy makes, and the task is read back after
    # each. Its action is cmd.exe /c exit. Nothing here starts it, and it is
    # removed before this ends.
    $elevated = $false
    try {
        $elevated = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { $elevated = $false }
    if (-not $elevated) {
        Write-Host 'SKIP  not elevated, so the account changes were not applied to a real task'
    } else {
        # Not 'Thornswood test...': test-deploy-swaps and test-install-server
        # clear away every task named 'Thornswood Test*', and task names match
        # without case, so one of them running beside this deleted its task
        # half way and the update said "The system cannot find the file
        # specified" (issue #1135).
        $scratchTask = 'Thornswood site-account harness ' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
        # From the settings set to the read-back of the account, and not the
        # Start-ScheduledTask after it. The account does not change this part
        # of the script, only the task name does.
        $realTop = @([System.Management.Automation.Language.Parser]::ParseInput(
            (Build 'SYSTEM' $docs $scratchTask), [ref]$null, [ref]$null).EndBlock.Statements)
        $from = -1
        $to = -1
        for ($i = 0; $i -lt $realTop.Count; $i++) {
            $st = $realTop[$i]
            if (-not ($st -is [System.Management.Automation.Language.AssignmentStatementAst])) { continue }
            if ($from -lt 0 -and $st.Left.Extent.Text -eq '$s' -and $st.Right.Extent.Text -match 'New-ScheduledTaskSettingsSet') { $from = $i }
            if ($st.Left.Extent.Text -eq '$who' -and $i + 1 -lt $realTop.Count) { $to = $i + 1 }
        }
        $makeOrUpdate = ''
        if ($from -ge 0 -and $to -gt $from) {
            $makeOrUpdate = (@($realTop[$from..$to] | ForEach-Object { $_.Extent.Text }) -join "`n")
        }
        Yes 'real task: the code that registers or updates the task and reads it back is found, and nothing that starts or stops anything' (
            $makeOrUpdate -match 'Register-ScheduledTask' -and $makeOrUpdate -match 'Set-ScheduledTask' -and
            $makeOrUpdate -match [regex]::Escape($scratchTask) -and
            $makeOrUpdate -notmatch 'Start-ScheduledTask' -and $makeOrUpdate -notmatch 'Stop-Process')

        # One deploy against the scratch task: the account block with the
        # scratch folders and icacls standing in, an action that does nothing,
        # then the real register-or-update and read-back, with Continue as the
        # far end has it. Hands back what it said and the task as it is after.
        function OnTask([string]$given, [int]$n) {
            $code = '$ErrorActionPreference = ''Continue''' + "`n" +
                    'function icacls { $script:icaclsCalls++; $global:LASTEXITCODE = 0 }' + "`n" +
                    (Scratch (BlockOf (Build $given $docs $scratchTask)) $map) + "`n" +
                    ('$a = New-ScheduledTaskAction -Execute ''cmd.exe'' -Argument ''/c exit {0}''' -f $n) + "`n" +
                    $makeOrUpdate
            $script:icaclsCalls = 0
            # A cmdlet that fails in there can still end this script, because
            # a module's cmdlet does not always see the Continue set above.
            # Kept as what it said, so the checks below fail by name instead.
            try { $ran = Run $code }
            catch { $ran = @{ said = @('THREW: ' + $_.Exception.Message) } }
            $task = Get-ScheduledTask -TaskName $scratchTask -ErrorAction SilentlyContinue
            $p = $null
            if ($task) { $p = $task.Principal }
            return @{ said = ($ran.said -join "`n"); task = $task; p = $p }
        }
        function PrivsOf($p) { return ((@($p.RequiredPrivilege) | Where-Object { $_ }) -join ',') }
        function ArgsOf($task) { if (-not $task) { return '' }; return [string](@($task.Actions)[0].Arguments) }
        # The start-up trigger it was registered with, and the ten restarts.
        function Kept($task) {
            return [bool]($task -and @($task.Triggers | Where-Object { $_ }).Count -eq 1 -and $task.Settings.RestartCount -eq 10)
        }
        function IsSystem($p) {
            return [bool]($p -and $p.UserId -eq 'SYSTEM' -and "$($p.RunLevel)" -eq 'Highest' -and
                -not (PrivsOf $p) -and "$($p.ProcessTokenSidType)" -eq 'Default')
        }
        function IsCut($p) {
            return [bool]($p -and $p.UserId -match 'LOCAL SERVICE$' -and "$($p.RunLevel)" -eq 'Limited' -and
                (PrivsOf $p) -eq 'SeChangeNotifyPrivilege' -and "$($p.ProcessTokenSidType)" -eq 'Unrestricted')
        }

        if ($makeOrUpdate) {
            try {
                $r = OnTask '' 1
                Yes 'real task: no -RunAs and no task yet registers one' ($r.said -match 'scheduled task created' -and $null -ne $r.task)
                Yes 'real task: on SYSTEM at Highest, with no privilege list and token SID type Default' (IsSystem $r.p)
                Yes 'real task: with its start-up trigger, ten restarts and the action it was given' (
                    (Kept $r.task) -and (ArgsOf $r.task) -eq '/c exit 1')
                Yes 'real task: and the read-back says SYSTEM' ($r.said -match 'task runs as SYSTEM, run level Highest')

                $r = OnTask 'LOCAL SERVICE' 2
                Yes 'real task: -RunAs LOCAL SERVICE updates it without an error' (
                    $r.said -match 'scheduled task updated' -and $r.said -notmatch 'COULD NOT UPDATE')
                if ($r.said -notmatch 'scheduled task updated' -or $r.said -match 'COULD NOT UPDATE') {
                    foreach ($l in @($r.said -split "`n" | Select-Object -Last 15)) { Write-Host ('      said: ' + $l) }
                }
                Yes 'real task: it is now LOCAL SERVICE at Limited, SeChangeNotifyPrivilege only, token SID type Unrestricted' (IsCut $r.p)
                Yes 'real task: the trigger and settings kept, and this deploy''s action on it' (
                    (Kept $r.task) -and (ArgsOf $r.task) -eq '/c exit 2')
                Yes 'real task: and the read-back says LOCAL SERVICE with the cut' (
                    $r.said -match 'task runs as LOCAL SERVICE, run level Limited' -and
                    $r.said -match 'task privileges: SeChangeNotifyPrivilege only, token SID type Unrestricted')

                $r = OnTask '' 3
                Yes 'real task: a deploy without -RunAs after that reads LOCAL SERVICE off the task and keeps it, cut' (
                    $r.said -match 'keeps the account it has: LOCAL SERVICE' -and (IsCut $r.p) -and (ArgsOf $r.task) -eq '/c exit 3')

                # The finding. Before the fix this said "scheduled task
                # updated" and left the task on LOCAL SERVICE with the last
                # deploy's action.
                $r = OnTask 'SYSTEM' 4
                Yes 'real task: -RunAs SYSTEM on the LOCAL SERVICE task updates it without an error' (
                    $r.said -match 'scheduled task updated' -and $r.said -notmatch 'COULD NOT UPDATE' -and $r.said -notmatch 'unexpected node')
                Yes 'real task: -RunAs SYSTEM puts it back on SYSTEM at Highest, with no privilege list left over' (IsSystem $r.p)
                Yes 'real task: with this deploy''s action on it, not the last one''s' ((Kept $r.task) -and (ArgsOf $r.task) -eq '/c exit 4')
                Yes 'real task: and the read-back says SYSTEM' (
                    $r.said -match 'task runs as SYSTEM, run level Highest' -and $r.said -notmatch 'THE TASK RUNS AS')

                $r = OnTask '' 5
                Yes 'real task: and a deploy without -RunAs after that keeps SYSTEM' (
                    $r.said -match 'keeps the account it has: SYSTEM' -and (IsSystem $r.p) -and (ArgsOf $r.task) -eq '/c exit 5')
            }
            finally {
                Unregister-ScheduledTask -TaskName $scratchTask -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
        Yes 'real task: the scratch task is gone again' ($null -eq (Get-ScheduledTask -TaskName $scratchTask -ErrorAction SilentlyContinue))
    }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Done
