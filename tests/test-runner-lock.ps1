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
if ($lib) {
    Yes 'a runner''s folder takes nothing from C:\' ($lib.Contains('/inheritance:r'))
    Yes '  SYSTEM and Administrators Full Control, its own account Modify' ($lib.Contains("'*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' (`$acct + ':(OI)(CI)M')"))
    Yes '  and it is read back, not taken on trust' ($lib -match 'AreAccessRulesProtected' -and $lib -match 'still open')
}

# ---- for real, on scratch folders -----------------------------------------------------
$icacls = $null
if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') { $icacls = Get-Command icacls.exe -ErrorAction SilentlyContinue }
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
