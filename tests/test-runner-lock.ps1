<#
  test-runner-lock.ps1

      pwsh -NoProfile -File .\tests\test-runner-lock.ps1

  Several build runners on the VPS, and each one's folder shut to the others.

  WHY. On 4 October a second runner went on the box beside the first
  (Install-Runner.ps1 -Number 2 names). Its install shut its own account out
  of every C:\Thornswood-* folder, the first runner's included, and nothing
  shut the first runner's account out of the second's folder, which did not
  exist when the first was installed. A folder made under C:\ lets BUILTIN\Users
  read it, every runner account is in Users, and a runner's folder holds the
  credentials GitHub gave it. So each runner's folder is now locked the way
  #1105 locked the server folders, and -Lock puts every runner on the box
  right without replacing any of them.

  CRASH DUMPS (#2127, #2488). Lock-VpsFolders.ps1 gives every runner account
  write and no read on C:\Thornswood-Dumps (Patrick, 11 October), and until
  12 October every install and -Lock put a full deny on it for every runner,
  which beats that write. This pins that Install-Runner leaves exactly the
  folder Lock-VpsFolders.ps1 names to it, that no other deny is in the
  script, and, on scratch folders with the real Lock-VpsFolders.ps1, that the
  lock takes an old deny off, says so, and keeps the write.

  HOW. Reads Install-Runner.ps1 for the names -Number gives and for where the
  locks run. Then, on Windows, lifts the real Lock-RunnerRoot and
  Close-RunnerAccount out of the script and runs them on scratch folders
  under TEMP, never under C:\, and reads the rules back. The account shut out
  is ANONYMOUS LOGON (*S-1-5-7), a principal that is never the one running
  this, so the scratch folders stay this account's to remove. Off Windows the
  scratch part says SKIP.
#>
[CmdletBinding()]
param([string]$Repo)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $Repo) { $Repo = $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$path = Join-Path $Repo 'scripts\deploy\Install-Runner.ps1'
$text = [IO.File]::ReadAllText($path)
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
Yes 'Install-Runner.ps1 parses' (-not $e -or $e.Count -eq 0)

# The value of a top-level "$name = @'...'@" or "$name = $other + @'...'@".
function HereOf([string]$name) {
    $a = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq ('$' + $name) }, $false))
    if (-not $a.Count) { return $null }
    $s = @($a[0].Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.StringConstantType -eq 'SingleQuotedHereString' }, $true))
    if (-not $s.Count) { return $null }
    return $s[-1].Value
}
$lib = HereOf 'lockLib'
$all = HereOf 'lockAll'
Yes 'the locks are one block the install and -Lock both send' ([bool]$lib -and [bool]$all -and $text.Contains('$lockAll = $lockLib + $watcherLib + "`n`$liveFilter = '''))

# ---- the names -Number gives ------------------------------------------------------
Yes '-Number is a parameter, 1 to 99' ($text -match '\[ValidateRange\(1, 99\)\]\[int\]\$Number = 1')
$names = @{
    Root = "\`$Root = 'C:\\Thornswood-Runner' \+ \`$Number"
    Account = "\`$Account = 'thornswood-runner' \+ \`$Number"
    RunnerName = "\`$RunnerName = 'thornswood-vps-' \+ \`$Number"
}
foreach ($k in $names.Keys) {
    Yes "  from 2 up, $k gets the number unless it is given" ($text -match ("if \(-not \`$PSBoundParameters\.ContainsKey\('" + $k + "'\)\)\s*\{ " + $names[$k] + ' \}'))
}
# The real block, run with -Number 2 and nothing else given: the names the
# second runner was installed with by hand on 4 October.
$numIf = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and "$($n.Clauses[0].Item1)" -eq '$Number -gt 1' }, $true))
$got = @()
if ($numIf.Count) {
    # Its priority task, Thornswood Runner 2 Priority, went with #1969.
    $defaults = "`$Root = 'C:\Thornswood-Runner'; `$Account = 'thornswood-runner'; `$RunnerName = 'thornswood-vps'"
    $got = @(& ([scriptblock]::Create("param(`$Number) $defaults`n" + $numIf[0].Extent.Text + "`n@(`$Root, `$Account, `$RunnerName)")) 2)
}
Yes ('  run with -Number 2 it gives the names the second runner has (' + ($got -join ', ') + ')') (($got -join '|') -eq 'C:\Thornswood-Runner2|thornswood-runner2|thornswood-vps-2')
Yes '  the 99th account name fits the 20 characters a local account may have' (('thornswood-runner' + 99).Length -le 20)
Yes '  every runner keeps the one label build.yml asks for' ($text -notmatch '\$Label\s*=\s*[^\r\n]*\$Number')

# ---- where the locks run ------------------------------------------------------------
$lockAt = $text.IndexOf('Lock-RunnerRoot `$root `$acct')
$cfgAt = $text.IndexOf('& .\config.cmd --unattended')
Yes 'the install locks its own folder before config.cmd writes the credentials into it' ($lockAt -gt 0 -and $cfgAt -gt $lockAt)
Yes '  and sends the locks with the install' ($text.Contains('$out = Send-WithSecret $token ($lockLib + $watcherLib + "`n" + @"'))
$installAt = $text.IndexOf('# ----------------------------------------------------------------- install --')
$lockMode = $text.IndexOf('if ($Lock) {')
Yes '-Lock is its own mode, before the install' ($lockMode -gt 0 -and $installAt -gt $lockMode)
$lastAll = $text.LastIndexOf('Remote $lockAll')
Yes 'an install ends by locking every runner on the box' ($lastAll -gt $cfgAt)
Yes '  and both say so when the box does not finish' (([regex]::Matches($text, 'if \(\$code -ne 0\) \{ Die')).Count -ge 2)
if ($all) {
    Yes '-Lock finds the runners by their Windows services' ($all -match "Name LIKE 'actions\.runner\.%'")
    Yes '  their folders by where RunnerService.exe is, their accounts by what they run as' ($all -match 'PathName' -and $all -match 'StartName')
    Yes '  only folders under C:\Thornswood-Runner' ($all.Contains("-notlike 'C:\Thornswood-Runner*'"))
    Yes '  and touches no runner: no service stopped, removed or registered' ($all -notmatch '(?i)Stop-Service|Restart-Service|sc\.exe|config\.cmd|Remove-LocalUser|Set-LocalUser')
}
# ---- crash dumps (#2127, #2488) ---------------------------------------------------
# Lock-VpsFolders.ps1 gives every thornswood-runner* account write and no read
# on one folder, so a build's node crash leaves its dump. Install-Runner must
# never deny the runners that folder: a deny beats the allow, and until 12
# October the install and -Lock put one there for every runner.
$lvfPath = Join-Path $Repo 'scripts\vps\Lock-VpsFolders.ps1'
$lvf = [IO.File]::ReadAllText($lvfPath)
$dumpsName = [regex]::Match($lvf, "\`$isDumps = \`$f\.Name -eq '([^']+)'").Groups[1].Value
Yes ("Lock-VpsFolders.ps1 gives the runner accounts write on one folder (" + $dumpsName + ')') ($dumpsName -and $lvf.Contains('W = $(if ($isDumps) { $dumpWriters }') -and $lvf -match "Name -like 'thornswood-runner\*'")
$leaveAsg = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and "$($n.Left)" -eq '$leaveList' }, $false))
$onBox = @(); $offBox = @('not run')
if ($leaveAsg.Count -eq 1) {
    $src = { param($o) & ([scriptblock]::Create("param(`$OffBox) " + $leaveAsg[0].Extent.Text + "`n`$leaveList")) $o }
    $onBox = @(& ([scriptblock]::Create((& $src $false))))
    $offBox = @(& ([scriptblock]::Create((& $src $true))))
}
Yes ('on the VPS Install-Runner leaves exactly that folder to Lock-VpsFolders.ps1 (' + ($onBox -join ', ') + ')') ($dumpsName -and $onBox.Count -eq 1 -and $onBox[0] -eq $dumpsName)
Yes '  off the box (-OffBox) it leaves nothing out' ($offBox.Count -eq 0)
$calls = @([regex]::Matches($text, '(?m)^[ \t]*Close-RunnerAccount [^\r\n]*') | ForEach-Object { $_.Value.Trim() })
Yes ('both Close-RunnerAccount calls, the install''s and the lock''s, pass that list (' + $calls.Count + ' found)') ($calls.Count -eq 2 -and @($calls | Where-Object { $_ -match '\$leave(List)?$' }).Count -eq 2)
$denies = @([regex]::Matches($text, '(?m)^[^\r\n#]*/deny[^\r\n]*') | ForEach-Object { $_.Value.Trim() })
Yes ('no other folder deny in the script: Close-RunnerAccount''s and the off-box read guard''s only (' + $denies.Count + ' found)') ($denies.Count -eq 2 -and
    @($denies | Where-Object { $_ -eq '$null = & icacls.exe $d.FullName /deny ($acct + '':(OI)(CI)F'') /C /Q 2>&1' -or $_ -eq '$null = & icacls.exe $p /deny ($acct + '':(OI)(CI)F'') /C /Q 2>&1' }).Count -eq 2)
if ($all) { Yes '  and -Lock says what Dumps is, once for the box' ($all.Contains("Show-LeftFolders 'C:\' `$leave")) }

if ($lib) {
    Yes 'a runner''s folder takes nothing from C:\' ($lib.Contains('/inheritance:r'))
    Yes '  SYSTEM and Administrators Full Control, its own account Modify' ($lib.Contains("'*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' (`$acct + ':(OI)(CI)M')"))
    Yes '  and it is read back, not taken on trust' ($lib -match 'AreAccessRulesProtected' -and $lib -match 'still open')
}

# ---- TEMP IN ITS OWN FOLDER (#3117) ---------------------------------------------------
# A job's temp files went to the account's own temp folder, outside the folder
# Defender skips and never emptied: 26,214 to 28,472 entries per build runner
# on 21 Oct 2026. The runner's .env sends TEMP and TMP to its _work\_temp.
if ($lib -and $all) {
    Yes 'the runner''s .env sends a job''s TEMP and TMP to its own _work\_temp (#3117)' ($lib -match "function Set-RunnerTemp" -and $lib.Contains("Join-Path `$root '_work\_temp'") -and $lib.Contains("@(('TEMP=' + `$temp), ('TMP=' + `$temp))"))
    Yes '  -Lock writes it for every runner on the box' ($all.Contains('Set-RunnerTemp $root $svc.Name'))
    Yes '  and the install writes it before config.cmd first starts the service' ($text.IndexOf('Set-RunnerTemp `$root ''$service''') -gt 0 -and $text.IndexOf('Set-RunnerTemp `$root ''$service''') -lt $text.IndexOf('config.cmd --unattended'))
    # Run on a scratch folder, any OS: no service is asked about there.
    . ([scriptblock]::Create($lib))
    function Get-CimInstance { $null }
    $tr = Join-Path ([IO.Path]::GetTempPath()) ('tw-runner-temp-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tr -Force | Out-Null
    try {
        $envFile = Join-Path $tr '.env'
        [IO.File]::WriteAllText($envFile, "http_proxy=none`r`nTEMP=C:\old`r`n")
        $said1 = Set-RunnerTemp $tr 'actions.runner.x'
        $lines = @(Get-Content -LiteralPath $envFile)
        $want = Join-Path $tr '_work\_temp'
        Yes 'Set-RunnerTemp keeps the runner''s own lines and puts TEMP and TMP right' ($lines.Count -eq 3 -and $lines[0] -eq 'http_proxy=none' -and $lines -contains ('TEMP=' + $want) -and $lines -contains ('TMP=' + $want) -and $said1 -like '* now sends *')
        $said2 = Set-RunnerTemp $tr 'actions.runner.x'
        Yes '  and a second run changes nothing and says so' ($said2 -like '* already' -and @(Get-Content -LiteralPath $envFile).Count -eq 3)
    } finally {
        Remove-Item -LiteralPath $tr -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue
    }
}

# ---- for real, on scratch folders -----------------------------------------------------
$icacls = $null
. (Join-Path $PSScriptRoot 'Windows.ps1')
if ($OnWindows) { $icacls = Get-Command icacls.exe -ErrorAction SilentlyContinue }
if (-not $icacls -or -not $lib) {
    Write-Host 'SKIP  the locks on scratch folders: they need Windows and icacls'
} else {
    . ([scriptblock]::Create($lib))
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ('tw-runner-lock-' + [guid]::NewGuid().ToString('N'))
    $own = Join-Path $scratch 'Thornswood-Runner9'
    $open = Join-Path $scratch 'Thornswood-Open'
    $shut = Join-Path $scratch 'Thornswood-Shut'
    $other = Join-Path $scratch 'Other'
    try {
        foreach ($d in $own, $open, $shut, $other) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        # What C:\ gives a new folder there, Users may read, on the runner's own
        # folder and on one the account should be shut out of.
        foreach ($d in $own, $open) { $null = & icacls.exe $d /grant '*S-1-5-32-545:(OI)(CI)RX' /C /Q 2>&1 }
        Set-Content -LiteralPath (Join-Path $own '.credentials') -Value 'stand-in'
        function Rules([string]$d) { @((Get-Acl -LiteralPath $d).GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) }

        $said = @(Lock-RunnerRoot $own ('*' + $me))
        $acl = Get-Acl -LiteralPath $own
        $allow = @(Rules $own | Where-Object { "$($_.AccessControlType)" -eq 'Allow' } | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)
        Yes 'Lock-RunnerRoot: the folder takes nothing from its parent' ($acl.AreAccessRulesProtected)
        Yes '  Users may not read it any more' ($allow -notcontains 'S-1-5-32-545')
        Yes '  SYSTEM, Administrators and the runner''s account may' ($allow -contains 'S-1-5-18' -and $allow -contains 'S-1-5-32-544' -and $allow -contains $me)
        Yes '  and nobody else' (@($allow | Where-Object { @('S-1-5-18', 'S-1-5-32-544', $me) -notcontains $_ }).Count -eq 0)
        $credAllow = @(Rules (Join-Path $own '.credentials') | Where-Object { "$($_.AccessControlType)" -eq 'Allow' } | ForEach-Object { $_.IdentityReference.Value })
        Yes '  the credentials file in it follows' ($credAllow -notcontains 'S-1-5-32-545')
        Yes '  and it says who may use it' ($said.Count -eq 1 -and $said[0] -like "$own is locked: only *")

        $said = @(Close-RunnerAccount '*S-1-5-7' $own $scratch)
        $deny = { param($d) @(Rules $d | Where-Object { "$($_.AccessControlType)" -eq 'Deny' -and $_.IdentityReference.Value -eq 'S-1-5-7' }).Count }
        Yes 'Close-RunnerAccount: shut out of every Thornswood-* folder beside its own' ((& $deny $open) -ge 1 -and (& $deny $shut) -ge 1)
        Yes '  never its own' ((& $deny $own) -eq 0)
        Yes '  and nothing that is not a Thornswood-* folder' ((& $deny $other) -eq 0)
        Yes '  it names the one Users could read' (@($said | Where-Object { $_ -eq ('*S-1-5-7 COULD READ ' + $open + ' until now; shut out of it') }).Count -eq 1)
        Yes '  and counts the one that was closed anyway' (@($said | Where-Object { $_ -like '*: already shut out of 0 folder(s), and a deny added on 1 that were closed to it anyway' }).Count -eq 1)
        $said = @(Close-RunnerAccount '*S-1-5-7' $own $scratch)
        Yes '  a second run finds both already shut and names nothing' ($said.Count -eq 1 -and $said[0] -eq '*S-1-5-7: already shut out of 2 folder(s)')

        # #2711: an account name Windows does not know was looked up in a try
        # with an empty catch; now the stop says what the lookup said. And the
        # names Lock-RunnerRoot gives come from a lookup that cannot throw: a
        # SID Windows cannot name stays a SID.
        $why = ''; try { $null = Close-RunnerAccount ('no-such-runner-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)) $own $scratch } catch { $why = $_.Exception.Message }
        Yes 'an account Windows does not know stops it, with what the lookup said' ($why -match '^there is no account called no-such-runner-\w+ on this box: \S')
        $gone = 'S-1-5-21-1-2-3-4999'
        # icacls refuses a SID nobody can name, so the rule goes on through .NET.
        $acl = Get-Acl -LiteralPath $other
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($gone)), 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        Set-Acl -LiteralPath $other -AclObject $acl
        $said = @(Lock-RunnerRoot $other ('*' + $me))
        Yes 'Lock-RunnerRoot names an account Windows no longer knows by its SID, and the rest by name' ($said.Count -eq 1 -and $said[0] -match 'SYSTEM' -and $said[0] -match [regex]::Escape($gone))

        # ---- crash dumps, for real: the real Lock-VpsFolders.ps1 on a scratch
        # Dumps, then the deny an install before #2488 left, then the lock.
        $box = Join-Path $scratch 'box'
        $dumps = Join-Path $box $dumpsName
        $server = Join-Path $box 'Thornswood-Server'
        $own2 = Join-Path $box 'Thornswood-Runner9'
        foreach ($d in $dumps, $server, $own2) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        Set-Content -LiteralPath (Join-Path $dumps 'node.exe.1234.dmp') -Value 'stand-in'
        $ps51 = Get-WindowsPowerShell
        function LockBox {
            $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { $o = @(& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $lvfPath -Parent $box -SiteSid none -BotSid none -AllowGamingPc -DumpWriterSids 'S-1-5-7' 2>&1 | ForEach-Object { "$_" }) }
            finally { $ErrorActionPreference = $eap }
            return @{ Code = $LASTEXITCODE; Said = ($o -join ' ') }
        }
        $lv = LockBox
        Yes ('Lock-VpsFolders.ps1 locks the scratch Dumps (exit ' + $lv.Code + ')') ($lv.Code -eq 0 -and $lv.Said -match [regex]::Escape('locked ' + $dumps))
        $writeBit = [int][Security.AccessControl.FileSystemRights]::WriteData
        $readBit = [int][Security.AccessControl.FileSystemRights]::ReadData
        $mayWrite = { param($d) @(Rules $d | Where-Object { "$($_.AccessControlType)" -eq 'Allow' -and $_.IdentityReference.Value -eq 'S-1-5-7' -and ([int]$_.FileSystemRights -band $writeBit) -and -not ([int]$_.FileSystemRights -band $readBit) }).Count -ge 1 }
        Yes '  ANONYMOUS LOGON, standing in for a runner account, may write there and not read' (& $mayWrite $dumps)
        # What an install before #2488 did. icacls /deny also takes the
        # account's own allow off the folder, so the write goes with it.
        $null = & icacls.exe $dumps /deny '*S-1-5-7:(OI)(CI)F' /C /Q 2>&1
        Yes '  an install before #2488 put a full deny on it (the control)' ((& $deny $dumps) -ge 1 -and (& $deny (Join-Path $dumps 'node.exe.1234.dmp')) -ge 1)
        Yes '  and that deny took the write away with it' (-not (& $mayWrite $dumps))

        $said = @(Close-RunnerAccount '*S-1-5-7' $own2 $box 'Thornswood-*' @() $onBox)
        Yes 'Close-RunnerAccount with the VPS list: no deny left on Dumps' ((& $deny $dumps) -eq 0)
        Yes '  nor on the dump in it' ((& $deny (Join-Path $dumps 'node.exe.1234.dmp')) -eq 0)
        Yes '  it says it took the old deny off, and that Lock-VpsFolders.ps1 gives the write back' (@($said | Where-Object { $_ -eq ('*S-1-5-7: took off the deny an earlier install put on ' + $dumps + '; that deny also took its write away, so run Lock-VpsFolders.ps1 to give it write and no read there again (#2127, #2488)') }).Count -eq 1)
        Yes '  every other Thornswood-* folder is still shut' ((& $deny $server) -ge 1 -and (& $deny $own2) -eq 0)
        $lv = LockBox
        Yes ('Lock-VpsFolders.ps1 run after it gives the write back (exit ' + $lv.Code + ')') ($lv.Code -eq 0 -and (& $mayWrite $dumps) -and (& $deny $dumps) -eq 0)
        $said = @(Close-RunnerAccount '*S-1-5-7' $own2 $box 'Thornswood-*' @() $onBox)
        Yes 'a lock after that puts no deny back, has nothing to take off, and keeps the write' ((& $deny $dumps) -eq 0 -and -not ($said -join ' ' -match 'took off') -and (& $mayWrite $dumps))
        $said = @(Show-LeftFolders $box $onBox)
        Yes 'Show-LeftFolders: Dumps locked by Lock-VpsFolders.ps1 is said to be closed to Users' ($said.Count -eq 1 -and $said[0] -like ($dumps + ' is left to Lock-VpsFolders.ps1 (#2127): no deny from here, and Users do not reach it'))
        $null = & icacls.exe $dumps /grant '*S-1-5-32-545:(OI)(CI)RX' /C /Q 2>&1
        $said = @(Show-LeftFolders $box $onBox)
        Yes '  and one Users still reach is named, with what to run' ($said.Count -eq 1 -and $said[0] -like ($dumps + ' is left to Lock-VpsFolders.ps1 (#2127), and USERS STILL REACH IT*Lock-VpsFolders.ps1*'))
    }
    finally {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
    Yes 'the scratch folders are gone again' (-not (Test-Path -LiteralPath $scratch))
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
