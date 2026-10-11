<#
  test-new-box-runbook.ps1

      pwsh -NoProfile -File .\tests\test-new-box-runbook.ps1

  Issue #454: the new-box runbook did not survive being followed. Measured on
  29 September, before this harness: it named Backup-Server.ps1, whose zip
  Restore-Server.ps1 cannot read; ran Bootstrap-VPS.ps1 and
  Install-ThornswoodServer.ps1 "against the new address", which neither takes
  (both run on the box); restored by hand into folders that did not exist yet;
  imported scheduled tasks from a folder the nightly backup has never had;
  sent -CodeOnly to a bot that was not installed; had no dev server, no feed,
  no installer and no watchers; and ended with a Ship note Ship refuses. None
  of it failed anything, because nothing read the page.

  This reads it. Both "If it is a new machine, new address" in
  docs\MOVING-THE-SERVER.md and "The box is gone" in docs\RESTORING.md:

    1. every command in them parses, every script they name exists and
       parses, and every -Parameter they pass is one that script has, with a
       value its ValidateSet allows. That includes a script carried to the box
       by Remote.ps1 -File with -Arguments, and one run there by ssh
       "powershell ... -File C:\<script>.ps1 <arguments>".
    2. every scp that carries Install-ThornswoodServer.ps1 up carries every
       file it loads from beside itself, read off the installer's own syntax
       tree (issue #1884: step 6 left ServerBuild.ps1 behind, and the
       installer stops without it). The rehearsal in RESTORING.md, which
       records what was typed before that file existed, says it is needed
       today.
    3. the steps are in the order the scripts need: the address first, the
       ssh key before anything that uses it, the server program before the
       restore, the restore before the site, the bot and the game start, and
       the watchdog, which starts whatever is stopped, after all of them. The
       page ends with the watchers.
    4. no command carries a secret, and every secret the steps need says where
       it comes from, with the passphrase's file the one Restore-Box.ps1 and
       Install-Backup.ps1 actually default to.
    5. what can run here does: Where.ps1 knows the payload it names, the Ship
       note passes Ship's own rules, and Restore-Box.ps1 refuses a backup it
       cannot use before it reaches for ssh.
    6. the box-side half, under Windows PowerShell 5.1 as on the VPS: the real
       vps-nightly-backup.ps1 takes every site upload even over its advisory
       threshold, and the feed store (not its downloads)
       from a scratch site, and the real vps-restore-services.ps1
       puts every piece back into scratch folders, keeps what was there
       aside, locks the bot's settings, compares the gamemode, refuses a
       backup without the essentials and refuses while the site runs.

  Touches nothing but a scratch folder under the temp folder. Never reaches
  the VPS.
#>
[CmdletBinding()]
param()
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here

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

# ------------------------------------------------------------ the pages ----
function Section([string]$rel, [string]$heading) {
    $text = [IO.File]::ReadAllText((Join-Path $Repo $rel)) -replace "`r`n", "`n"
    $a = $text.IndexOf("`n$heading`n")
    if ($a -lt 0) { return $null }
    $b = $text.IndexOf("`n## ", $a + $heading.Length + 1)
    if ($b -lt 0) { $b = $text.Length }
    return $text.Substring($a + 1, $b - $a - 1)
}
$pages = [ordered]@{
    'MOVING-THE-SERVER.md, new machine' = Section 'docs\MOVING-THE-SERVER.md' '## If it is a new machine, new address'
    'RESTORING.md, the box is gone'     = Section 'docs\RESTORING.md' '## The box is gone'
}
foreach ($k in $pages.Keys) { Yes "$k is there" ([bool]$pages[$k]) }
if (@($pages.Values | Where-Object { -not $_ }).Count) { Done }

# Every command on a page, in order: each fenced block whole, and each inline
# code span, joined across a line break the way markdown reads it. Only the
# ones that run a script or talk to the box are commands; the rest are names.
function Commands([string]$text) {
    $out = @()
    $fence = [regex]'(?ms)^[ \t]*```[a-z]*\n(.*?)^[ \t]*```'
    foreach ($m in $fence.Matches($text)) {
        # A fenced block may hold several commands and one string over lines,
        # so it is parsed whole.
        $out += [pscustomobject]@{ At = $m.Index; Text = $m.Groups[1].Value }
    }
    $rest = $fence.Replace($text, { param($m) ' ' * $m.Length })
    foreach ($m in ([regex]'`([^`]+)`').Matches($rest)) {
        $t = ($m.Groups[1].Value -replace '\n[ \t]*', ' ').Trim()
        if ($t -match '\.ps1\b' -or $t -match '^(ssh|scp)\s') { $out += [pscustomobject]@{ At = $m.Index; Text = $t } }
    }
    return @($out | Sort-Object At)
}

# ------------------------------------------------------------ the scripts --
$scriptsDir = Join-Path $Repo 'scripts'
$byLeaf = @{}
foreach ($f in @(Get-ChildItem -LiteralPath $scriptsDir -Recurse -File -Filter *.ps1)) {
    if (-not $byLeaf.ContainsKey($f.Name)) { $byLeaf[$f.Name] = @() }
    $byLeaf[$f.Name] += $f.FullName
}
$common = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable',
            'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm')
$paramCache = @{}
function ParamsOf([string]$path) {
    if ($paramCache.ContainsKey($path)) { return $paramCache[$path] }
    $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errs)
    $info = @{ Errors = @($errs).Count; Names = @{} }
    if ($ast.ParamBlock) {
        foreach ($p in $ast.ParamBlock.Parameters) {
            $set = $null
            foreach ($a in $p.Attributes) {
                if ($a.TypeName.Name -eq 'ValidateSet') { $set = @($a.PositionalArguments | ForEach-Object { $_.Value }) }
            }
            $info.Names[$p.Name.VariablePath.UserPath] = $set
        }
    }
    $paramCache[$path] = $info
    return $info
}

# A script as the page names it: .\scripts\<area>\<leaf> in the repository,
# or a copy on the box (C:\Install-ThornswoodServer.ps1), matched by its name.
function Resolve-Named([string]$name) {
    $n = $name.Trim('"', "'")
    # A harness the page points at, which is read rather than run.
    if ($n -match '^(\.\\)?tests\\') { $p = Join-Path $Repo ($n -replace '^\.\\', ''); if (Test-Path -LiteralPath $p) { return $p } else { return $null } }
    if ($n -match '^\.\\scripts\\') { $p = Join-Path $Repo $n.Substring(2); if (Test-Path -LiteralPath $p) { return $p } else { return $null } }
    $leaf = Split-Path -Leaf $n
    if ($byLeaf.ContainsKey($leaf) -and @($byLeaf[$leaf]).Count -eq 1) { return $byLeaf[$leaf][0] }
    return $null
}

$script:bad = @()
# Checks the parameters of one call against the script it runs. $elements
# are the call's CommandElements after the script's own name.
function Check-Call([string]$page, [string]$name, [string]$path, $elements) {
    $info = ParamsOf $path
    if ($info.Errors) { $script:bad += "$page : $name does not parse"; return @() }
    $used = @()
    $els = @($elements)
    for ($i = 0; $i -lt $els.Count; $i++) {
        $e = $els[$i]
        if ($e -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
        $p = $e.ParameterName
        $used += $p
        if ($common -contains $p) { continue }
        $match = @($info.Names.Keys | Where-Object { $_ -eq $p })
        if (-not $match.Count) { $script:bad += "$page : $name has no -$p"; continue }
        $set = $info.Names[$match[0]]
        $arg = $e.Argument
        if (-not $arg -and $i + 1 -lt $els.Count -and $els[$i + 1] -isnot [System.Management.Automation.Language.CommandParameterAst]) { $arg = $els[$i + 1] }
        if ($set -and $arg -is [System.Management.Automation.Language.StringConstantExpressionAst] -and ($set -notcontains $arg.Value)) {
            $script:bad += "$page : $name -$p $($arg.Value) is not one of $($set -join ', ')"
        }
    }
    return $used
}

function Read-Page([string]$page, [string]$pageText) {
    $list = @()
    foreach ($c in (Commands $pageText)) {
        # A placeholder the page writes as <new address> is one word here.
        $text = [regex]::Replace($c.Text, '<[^<>\n]+>', 'PLACEHOLDER')
        $errs = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errs)
        if (@($errs).Count) { $script:bad += "$page : does not parse: $($c.Text) ($($errs[0].Message))"; continue }
        foreach ($cmd in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))) {
            $name = $cmd.GetCommandName()
            if (-not $name) { continue }
            $els = @($cmd.CommandElements | Select-Object -Skip 1)
            if ($name -like '*.ps1') {
                $path = Resolve-Named $name
                if (-not $path) { $script:bad += "$page : no such script: $name"; continue }
                $used = Check-Call $page $name $path $els
                $leaf = Split-Path -Leaf $path
                # Remote.ps1 -File <script> -Arguments '<its arguments>'
                if ($leaf -eq 'Remote.ps1') {
                    for ($i = 0; $i -lt $els.Count; $i++) {
                        if ($els[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and $els[$i].ParameterName -eq 'File' -and $i + 1 -lt $els.Count) {
                            $far = Resolve-Named ([string]$els[$i + 1].Extent.Text)
                            if (-not $far) { $script:bad += "$page : Remote.ps1 -File names no script: $($els[$i + 1].Extent.Text)"; continue }
                            $argText = ''
                            for ($j = 0; $j -lt $els.Count; $j++) {
                                if ($els[$j] -is [System.Management.Automation.Language.CommandParameterAst] -and $els[$j].ParameterName -eq 'Arguments' -and $j + 1 -lt $els.Count) { $argText = $els[$j + 1].Value }
                            }
                            $inner = [System.Management.Automation.Language.Parser]::ParseInput("& x $argText", [ref]$null, [ref]$null)
                            $ic = $inner.Find({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
                            $farUsed = Check-Call $page (Split-Path -Leaf $far) $far @($ic.CommandElements | Select-Object -Skip 1)
                            $list += [pscustomobject]@{ At = $c.At; Leaf = (Split-Path -Leaf $far); Params = $farUsed; Text = $c.Text; Via = 'Remote.ps1' }
                        }
                    }
                }
                $list += [pscustomobject]@{ At = $c.At; Leaf = $leaf; Params = $used; Text = $c.Text; Via = '' }
            }
            elseif ($name -eq 'ssh') {
                # ssh <box> "powershell ... -File C:\<script>.ps1 <arguments>"
                foreach ($s in @($els | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $_.Value -match '-File\s' })) {
                    $far = [System.Management.Automation.Language.Parser]::ParseInput($s.Value, [ref]$null, [ref]$null)
                    $fc = $far.Find({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
                    $fe = @($fc.CommandElements)
                    for ($i = 0; $i -lt $fe.Count; $i++) {
                        if ($fe[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and $fe[$i].ParameterName -eq 'File' -and $i + 1 -lt $fe.Count) {
                            $target = [string]$fe[$i + 1].Extent.Text
                            $path = Resolve-Named $target
                            if (-not $path) { $script:bad += "$page : ssh runs a script the repository does not have: $target"; continue }
                            $used = Check-Call $page (Split-Path -Leaf $path) $path @($fe | Select-Object -Skip ($i + 2))
                            $list += [pscustomobject]@{ At = $c.At; Leaf = (Split-Path -Leaf $path); Params = $used; Text = $c.Text; Via = 'ssh' }
                        }
                    }
                }
            }
            elseif ($name -eq 'scp') {
                # What goes up has to be in the repository.
                foreach ($e in $els) {
                    if ($e -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $e.Value -match '^\.\\scripts\\') {
                        if (-not (Test-Path -LiteralPath (Join-Path $Repo $e.Value.Substring(2)))) { $script:bad += "$page : scp sends a file the repository does not have: $($e.Value)" }
                    }
                }
            }
        }
    }
    return , @($list | Sort-Object At)
}

# The check itself, on a page written wrong on purpose, so a checker that
# stopped seeing anything cannot pass the real pages by finding nothing.
$wrong = @'
1. `.\scripts\vps\Restore-Server.ps1 -Backup <b> -Root C:\x -Which staging -Nope`
2. `.\scripts\vps\Remote.ps1 -File .\scripts\vps\Bootstrap-VPS.ps1 -Arguments '-IncludeGits'`
3. `ssh Administrator@<new address> "powershell -NoProfile -File C:\Install-ThornswoodServer.ps1 -Zipp C:\z.zip"`
4. `.\scripts\vps\No-Such-Script.ps1`
   ```powershell
   scp .\scripts\vps\Not-There.ps1 Administrator@<new address>:C:/
   ```
'@
$script:bad = @()
[void](Read-Page 'a wrong page' $wrong)
$caught = $script:bad -join "`n"
Yes ('the check catches a wrong parameter, a value outside a ValidateSet, a wrong -Arguments, a wrong argument over ssh, ' +
     'a missing script and a missing file sent up ({0} of 6)' -f $script:bad.Count) (
    $script:bad.Count -eq 6 -and $caught -match 'has no -Nope' -and $caught -match 'staging is not one of' -and
    $caught -match 'Bootstrap-VPS.ps1 has no -IncludeGits' -and $caught -match 'Install-ThornswoodServer.ps1 has no -Zipp' -and
    $caught -match 'no such script' -and $caught -match 'Not-There')

$script:bad = @()
$records = @{}
foreach ($page in $pages.Keys) { $records[$page] = Read-Page $page $pages[$page] }
$moving = $records['MOVING-THE-SERVER.md, new machine']
$gone = $records['RESTORING.md, the box is gone']
Yes ("the new machine steps name scripts ({0} calls)" -f $moving.Count) ($moving.Count -ge 30)
Yes ("the box is gone steps name scripts ({0} calls)" -f $gone.Count) ($gone.Count -ge 5)
Yes 'every command parses, names a script the repository has, and passes only parameters it takes' ($script:bad.Count -eq 0)
foreach ($b in $script:bad) { Write-Host "        $b" }

# --------------------------------------------------------------- the order --
function First($list, [string]$leaf, [scriptblock]$also) {
    for ($i = 0; $i -lt $list.Count; $i++) {
        $r = $list[$i]
        if ($r.Leaf -ne $leaf) { continue }
        if ($also -and -not (& $also $r)) { continue }
        return $i
    }
    return -1
}
function Has($r, [string]$p) { return @($r.Params | Where-Object { $_ -eq $p }).Count -gt 0 }
$steps = @(
    @{ Say = 'Set-Vps points the branch at the new box';             Leaf = 'Set-Vps.ps1' },
    @{ Say = 'Setup-SshKey puts the key on it';                      Leaf = 'Setup-SshKey.ps1' },
    @{ Say = 'Bootstrap-VPS, carried there by Remote.ps1';           Leaf = 'Bootstrap-VPS.ps1'; Also = { param($r) $r.Via -eq 'Remote.ps1' } },
    @{ Say = 'Install-ThornswoodServer, run on the box';             Leaf = 'Install-ThornswoodServer.ps1'; Also = { param($r) $r.Via -eq 'ssh' } },
    @{ Say = 'Install-Voice';                                        Leaf = 'Install-Voice.ps1' },
    @{ Say = 'vps-dev-instance, which needs the live server and voice tasks'; Leaf = 'vps-dev-instance.ps1' },
    @{ Say = 'Restore-Box -Check';                                   Leaf = 'Restore-Box.ps1'; Also = { param($r) Has $r 'Check' } },
    @{ Say = 'vps-freeze on the old box';                            Leaf = 'vps-freeze.ps1' },
    @{ Say = 'Fetch-Backups from the old box';                       Leaf = 'Fetch-Backups.ps1'; Also = { param($r) Has $r 'VpsHost' } },
    @{ Say = 'Restore-Box';                                          Leaf = 'Restore-Box.ps1'; Also = { param($r) -not (Has $r 'Check') } },
    @{ Say = 'Deploy-Docs';                                          Leaf = 'Deploy-Docs.ps1' },
    @{ Say = 'Install-Bot';                                          Leaf = 'Install-Bot.ps1' },
    @{ Say = 'the live game server started';                         Leaf = 'Remote.ps1'; Also = { param($r) $r.Text -match "Start-ScheduledTask -TaskName 'Thornswood Server'" } },
    @{ Say = 'the feed';                                             Leaf = 'Remirror-Site-Feed.ps1' },
    @{ Say = 'Setup-Domain';                                         Leaf = 'Setup-Domain.ps1' },
    @{ Say = 'Check-Site from outside';                              Leaf = 'Check-Site.ps1' },
    @{ Say = 'the watchdog installed';                               Leaf = 'Watch-Services.ps1'; Also = { param($r) Has $r 'Install' } },
    @{ Say = 'Install-Backup';                                       Leaf = 'Install-Backup.ps1' },
    @{ Say = 'Install-Runner';                                       Leaf = 'Install-Runner.ps1' },
    @{ Say = 'Harden-VPS, once key login works (issue #450)';        Leaf = 'Harden-VPS.ps1' },
    @{ Say = 'Set-Server moves everybody';                           Leaf = 'Set-Server.ps1' },
    @{ Say = 'the main Ship';                                        Leaf = 'Ship.ps1' },
    @{ Say = 'the outside watch installed';                          Leaf = 'Watch-Outside.ps1'; Also = { param($r) Has $r 'Install' } }
)
$prev = -1; $prevSay = 'the start'; $inOrder = $true
foreach ($s in $steps) {
    $at = First $moving $s.Leaf $s.Also
    if ($at -lt 0) { Yes "the new machine steps have: $($s.Say)" $false; $inOrder = $false; continue }
    if ($at -le $prev) { Yes "$($s.Say) comes after $prevSay" $false; $inOrder = $false }
    $prev = $at; $prevSay = $s.Say
}
Yes ("the new machine steps run in the order the scripts need ({0} steps)" -f $steps.Count) $inOrder
$lastPs1 = $moving[$moving.Count - 1]
Yes ("and end with the watchers (the last is {0})" -f $lastPs1.Leaf) (@('Watch-Outside.ps1', 'Fetch-Backups.ps1') -contains $lastPs1.Leaf -and ((Has $lastPs1 'Install') -or (Has $lastPs1 'Schedule')))
$mt = $pages['MOVING-THE-SERVER.md, new machine']
$pinAt = $mt.IndexOf('hostKeys')
Yes 'the new box''s host key is pinned in vps.json before Setup-SshKey reaches for it (issue #450)' (
    $pinAt -ge 0 -and $pinAt -lt $mt.IndexOf('.\scripts\vps\Setup-SshKey.ps1') -and $mt -match 'ssh-keygen -lf')
$watchAt = First $moving 'Watch-Services.ps1' { param($r) Has $r 'Install' }
$startAt = @(for ($i = 0; $i -lt $moving.Count; $i++) { if ($moving[$i].Text -match 'Start-ScheduledTask') { $i } })
Yes 'the watchdog, which starts whatever is down, goes in after every service is started' ($startAt.Count -and $watchAt -gt ($startAt | Measure-Object -Maximum).Maximum)
Yes 'nothing starts the live server before the restore (no -StartNow)' (
    @($moving + $gone | Where-Object { $_.Leaf -eq 'Install-ThornswoodServer.ps1' -and (Has $_ 'StartNow') }).Count -eq 0)
Yes 'the bot is installed whole, never -CodeOnly, and asks for no token (-NoToken)' (
    @($moving + $gone | Where-Object { $_.Leaf -eq 'Install-Bot.ps1' }).Count -ge 2 -and
    @($moving + $gone | Where-Object { $_.Leaf -eq 'Install-Bot.ps1' -and ((Has $_ 'CodeOnly') -or -not (Has $_ 'NoToken')) }).Count -eq 0)
Yes 'the site is never deployed with -SeedDocs' (@($moving + $gone | Where-Object { $_.Leaf -eq 'Deploy-Docs.ps1' -and (Has $_ 'SeedDocs') }).Count -eq 0)
# Auth has no flag since #1303: the service refuses every unproven join.
Yes 'voice goes on with loopback, as live and dev run it, and passes no -Auth, which Install-Voice no longer has' (
    @($moving | Where-Object { $_.Leaf -eq 'Install-Voice.ps1' }).Count -eq 2 -and
    @($moving | Where-Object { $_.Leaf -eq 'Install-Voice.ps1' -and ($_.Text -notmatch '-Bind 127\.0\.0\.1' -or $_.Text -match '-Auth') }).Count -eq 0)
Yes 'the hand-run Backup-Server.ps1, whose zip Restore-Server cannot read, is not the backup a move uses' (
    @($moving + $gone | Where-Object { $_.Leaf -eq 'Backup-Server.ps1' }).Count -eq 0)
$gCheck = First $gone 'Restore-Box.ps1' { param($r) Has $r 'Check' }
$gRestore = First $gone 'Restore-Box.ps1' { param($r) -not (Has $r 'Check') }
Yes 'the box is gone: Restore-Box -Check, then Restore-Box' ($gCheck -ge 0 -and $gRestore -gt $gCheck)
Yes '  and the site and the bot after it' (
    (First $gone 'Deploy-Docs.ps1' $null) -gt $gRestore -and (First $gone 'Install-Bot.ps1' $null) -gt $gRestore)
Yes 'neither page still tells anyone to import scheduled tasks from the backup' (
    @($pages.Values | Where-Object { $_ -match '(?i)import the scheduled tasks|tasks. folder in the backup' }).Count -eq 0)

# ---------------------------------------- what goes up with the installer --
# Install-ThornswoodServer.ps1 loads files from the folder it runs in and
# stops without them. Step 6 sent it without ServerBuild.ps1, which it loads
# since #1214, so followed as written it installed nothing (#1884). Read off
# the installer's syntax tree, so a file it starts loading from beside itself
# is wanted here the day it does: every Join-Path of the folder it runs from
# ($PSScriptRoot, or a variable given it) and a bare file name.
function Beside([string]$path) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
    $here = @('PSScriptRoot')
    foreach ($a in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Right.Extent.Text -eq '$PSScriptRoot' }, $true))) {
        if ($a.Left -is [System.Management.Automation.Language.VariableExpressionAst]) { $here += $a.Left.VariablePath.UserPath }
    }
    $out = @()
    foreach ($c in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Join-Path' }, $true))) {
        $e = @($c.CommandElements | Select-Object -Skip 1)
        if ($e.Count -ne 2) { continue }
        if ($e[0] -isnot [System.Management.Automation.Language.VariableExpressionAst] -or $here -notcontains $e[0].VariablePath.UserPath) { continue }
        if ($e[1] -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or $e[1].Value -match '[\\/]') { continue }
        $out += $e[1].Value
    }
    return , @($out | Sort-Object -Unique)
}
# Every scp on a page: the names of the files it sends, and the command.
function Scps([string]$pageText) {
    $out = @()
    foreach ($c in (Commands $pageText)) {
        $text = [regex]::Replace($c.Text, '<[^<>\n]+>', 'PLACEHOLDER')
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
        foreach ($cmd in @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'scp' }, $true))) {
            $a = @($cmd.CommandElements | Select-Object -Skip 1 | Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] })
            if ($a.Count -lt 2) { continue }
            $sends = @($a | Select-Object -First ($a.Count - 1) | ForEach-Object { ([string]$_.Extent.Text).Trim('"', "'") -split '[\\/]' | Select-Object -Last 1 })
            $out += [pscustomobject]@{ Sends = $sends; Text = $cmd.Extent.Text }
        }
    }
    return , @($out)
}
$beside = Beside (Join-Path $scriptsDir 'deploy\Install-ThornswoodServer.ps1')
Yes ('the installer loads {0} from beside itself, read off its syntax tree' -f ($beside -join ', ')) (
    $beside -contains 'ServerSettings.ps1' -and $beside -contains 'ServerBuild.ps1' -and
    $beside -contains 'ServerReadyWait.ps1')
function Short-Of($scps) {
    $miss = @()
    foreach ($sc in $scps) {
        if ($sc.Sends -notcontains 'Install-ThornswoodServer.ps1') { continue }
        foreach ($b in $beside) { if ($sc.Sends -notcontains $b) { $miss += "$b is not in: $($sc.Text)" } }
    }
    return , @($miss)
}
# The check itself, on step 6 as it was, so a check that stopped finding the
# scp cannot pass the real pages by finding nothing.
$wasStep6 = "   ``````powershell`n   scp .\scripts\deploy\Install-ThornswoodServer.ps1 .\scripts\deploy\ServerSettings.ps1 .\scripts\vps\Roll-Log.ps1 Administrator@<new address>:C:/`n   ``````"
$caughtScp = Short-Of (Scps $wasStep6)
$caughtNames = @($caughtScp | ForEach-Object { ($_ -split ' ')[0] })
Yes 'the check catches step 6 as it was, which left ServerBuild.ps1 behind' (
    $caughtNames -contains 'ServerBuild.ps1' -and $caughtNames -contains 'ServerReadyWait.ps1' -and
    $caughtScp.Count -eq 2)
$carries = 0; $short = @()
foreach ($page in $pages.Keys) {
    $sc = Scps $pages[$page]
    $carries += @($sc | Where-Object { $_.Sends -contains 'Install-ThornswoodServer.ps1' }).Count
    $miss = Short-Of $sc
    foreach ($m in $miss) { $short += "$page : $m" }
}
Yes ('every scp that carries the installer up carries all of them with it ({0} on the pages)' -f $carries) ($carries -ge 1 -and $short.Count -eq 0)
foreach ($m in $short) { Write-Host "        $m" }
# The rehearsal in RESTORING.md records what was typed on 28 September,
# before ServerBuild.ps1, and stays as it was typed. Whatever the installer
# loads from beside itself that no scp there sends, the section says, outside
# that record, is needed today.
$rehearsal = Section 'docs\RESTORING.md' '## Rehearsing it'
$rs = @(); $prose = ''
if ($rehearsal) {
    $rs = Scps $rehearsal
    $prose = ([regex]'(?ms)^[ \t]*```[a-z]*\n(.*?)^[ \t]*```').Replace($rehearsal, '')
}
$sentThere = @($rs | ForEach-Object { $_.Sends })
$unsaid = @($beside | Where-Object { $sentThere -notcontains $_ -and -not $prose.Contains($_) })
Yes ('RESTORING.md''s rehearsal says what the installer needs beside it today that was not typed then' + $(if ($unsaid.Count) { ': not ' + ($unsaid -join ', ') } else { '' })) (
    @($rs | Where-Object { $_.Sends -contains 'Install-ThornswoodServer.ps1' }).Count -ge 1 -and $unsaid.Count -eq 0)

# ------------------------------------------------------------- the secrets --
$all = @($moving + $gone)
Yes 'no command passes a password, a token, a secret or a webhook on its command line' (
    @($all | Where-Object { @($_.Params | Where-Object { $_ -match '^(Password|Token|Secret|Webhook|Key)$' }).Count }).Count -eq 0)
Yes '  and neither page holds a webhook address or anything shaped like a key' (
    @($pages.Values | Where-Object { $_ -match 'discord(app)?\.com/api/webhooks/\d' -or $_ -match '[A-Za-z0-9+/_-]{40,}' }).Count -eq 0)
$table = @($pages['MOVING-THE-SERVER.md, new machine'] -split "`n" | Where-Object { $_ -match '^\| ' -and $_ -notmatch '^\| (Secret|---)' })
$rows = @{}
foreach ($t in $table) {
    $c = @($t.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
    if ($c.Count -ge 3) { $rows[$c[0]] = $c }
}
Yes ("the page lists the secrets a move needs ({0})" -f $rows.Count) ($rows.Count -ge 6)
Yes '  and says where every one comes from and where it is used' (@($rows.Values | Where-Object { -not $_[1] -or -not $_[2] }).Count -eq 0)
function Row([string]$like) { return , @($rows.Keys | Where-Object { $_ -like $like } | ForEach-Object { , $rows[$_] }) }
$pw = Row '*Administrator password*'
Yes '  the box''s password, which Setup-SshKey asks for, from the provider''s panel' ($pw.Count -eq 1 -and $pw[0][1] -match 'panel' -and $pw[0][2] -match 'Setup-SshKey')
$hook = Row '*webhook*'
Yes '  the webhook, which Watch-Services -SetWebhook asks for, from Discord' (
    $hook.Count -eq 1 -and $hook[0][1] -match 'Integrations, Webhooks' -and
    @($moving | Where-Object { $_.Leaf -eq 'Watch-Services.ps1' -and (Has $_ 'SetWebhook') }).Count -eq 1)
$phrase = Row '*passphrase*'
$keyPath = 'Documents\thornswood-backup-key.txt'
$rbDefault = [regex]::Match([IO.File]::ReadAllText((Join-Path $scriptsDir 'vps\Restore-Box.ps1')), '\$KeyFile\s*=\s*"([^"]+)"').Groups[1].Value
$ibDefault = [regex]::Match([IO.File]::ReadAllText((Join-Path $scriptsDir 'deploy\Install-Backup.ps1')), '\$KeyOut\s*=\s*"([^"]+)"').Groups[1].Value
Yes '  the passphrase from the file Restore-Box.ps1 and Install-Backup.ps1 both default to' (
    $phrase.Count -eq 1 -and $phrase[0][1] -match [regex]::Escape($keyPath) -and
    $rbDefault.EndsWith($keyPath) -and $ibDefault.EndsWith($keyPath))
$tok = Row '*bot token*'
Yes '  the bot token and the site keys from inside the backup, so Install-Bot asks for none' ($tok.Count -eq 1 -and $tok[0][1] -match 'backup' -and $tok[0][2] -match '-NoToken')

# --------------------------------------------------------- what runs here --
$whereOut = $null
try { $whereOut = & (Join-Path $scriptsDir 'release\Where.ps1') ServerZip } catch { $whereOut = $null }
Yes "Where.ps1 knows ServerZip, the payload step 6 sends ($whereOut)" ([bool]$whereOut -and "$whereOut".EndsWith('.zip'))

$ship = @($moving | Where-Object { $_.Leaf -eq 'Ship.ps1' })
$note = ''
if ($ship.Count) {
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($ship[0].Text, [ref]$null, [ref]$null)
    $sc = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -like '*Ship.ps1' }, $true)
    $s = @($sc.CommandElements | Select-Object -Skip 1 | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -or $_ -is [System.Management.Automation.Language.ExpandableStringExpressionAst] })
    if ($s.Count) { $note = $s[0].Value }
}
. (Join-Path $scriptsDir 'release\Note-Rules.ps1')
$noteLines = @($note -split "`r?`n")
$title = (@($noteLines | Where-Object { $_.Trim() }) + @(''))[0].Trim()
$bullets = @($noteLines | Where-Object { $_ -match '^\s*-\s*\S' -and ($_ -replace '^\s*-\s*', '').Trim().Length -ge 12 })
Yes ('the Ship note has a title of three words or more and a detail line, as Ship.ps1 requires: ' + $title) (
    @($title -split '\s+' | Where-Object { $_ }).Count -ge 3 -and $bullets.Count -ge 1)
$problems = @(Get-NoteProblems $note)
Yes '  and passes Note-Rules.ps1' ($note -and $problems.Count -eq 0)
foreach ($p in $problems) { Write-Host "        $p" }

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-newbox-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
[void](New-Item -ItemType Directory -Path $work -Force)
$utf8 = New-Object Text.UTF8Encoding($false)
function Put([string]$path, [string]$text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
    [IO.File]::WriteAllText($path, $text, $utf8)
}
$script:last = @()
function Run([string]$exe, [string]$file, [string[]]$argv) {
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $script:last = @(& $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $file @argv 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $eap }
    return $LASTEXITCODE
}
function Show { foreach ($l in $script:last | Select-Object -Last 30) { Write-Host ('        ' + $l) } }
function Said([string]$pattern) { return (($script:last -join "`n") -match $pattern) }

try {
    $pwsh = (Get-Process -Id $PID).Path
    $rbox = Join-Path $scriptsDir 'vps\Restore-Box.ps1'
    Put (Join-Path $work 'thornswood-backup-20260929-1200.zip') 'not a nightly'
    $code = Run $pwsh $rbox @('-Backup', (Join-Path $work 'thornswood-backup-20260929-1200.zip'), '-NoPause')
    Yes "Restore-Box.ps1 refuses Backup-Server.ps1's zip before reaching for ssh (exit $code)" ($code -ne 0 -and (Said 'not a nightly backup') -and -not (Said 'Is the box ready'))
    Put (Join-Path $work 'thornswood-20260929-031500.zip.enc') 'TSBK1 but not really'
    Put (Join-Path $work 'key.txt') 'a passphrase for the test'
    $code = Run $pwsh $rbox @('-Backup', (Join-Path $work 'thornswood-20260929-031500.zip.enc'), '-KeyFile', (Join-Path $work 'no-such-key.txt'), '-NoPause')
    Yes "  and a missing passphrase file (exit $code)" ($code -ne 0 -and (Said 'no passphrase file'))
    $code = Run $pwsh $rbox @('-Backup', (Join-Path $work 'thornswood-20260929-031500.zip.enc'), '-KeyFile', (Join-Path $work 'key.txt'), '-Check', '-NoPause')
    Yes "  and a backup that does not open here, sending nothing (exit $code)" ($code -ne 0 -and (Said 'did not open here, so nothing was sent') -and -not (Said 'Is the box ready'))
    $code = Run $pwsh $rbox @('-Backup', (Join-Path $work 'thornswood-20260929-031500.zip.enc'), '-KeyFile', (Join-Path $work 'key.txt'), '-Expect', 'Brynja', '-NoPause')
    Yes "  and an -Expect that is not a profile id (exit $code)" ($code -ne 0 -and (Said 'digits only'))

    foreach ($s in 'vps-freeze.ps1', 'vps-restore-services.ps1', 'Restore-Box.ps1') {
        Yes "$s parses" ((ParamsOf (Join-Path $scriptsDir "vps\$s")).Errors -eq 0)
    }

    # ---- the box-side half, under Windows PowerShell 5.1 --------------------
    $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not $env:SystemRoot -or -not (Test-Path -LiteralPath $ps51)) {
        Write-Host 'SKIP  the box-side runs need Windows PowerShell 5.1, which runs them on the VPS'
        throw 'skip'
    }
    $old = Join-Path $work 'old'
    $site = Join-Path $old 'site'; $bot = Join-Path $old 'bot'; $caddy = Join-Path $old 'caddy'; $voice = Join-Path $old 'voice'
    Put (Join-Path $site 'data\board.json') '{"cards":[]}'
    Put (Join-Path $site 'data\site\about.md') '# About'
    Put (Join-Path $site 'config.json') '{"secret":"stand-in","botKey":"stand-in"}'
    Put (Join-Path $site 'uploads\uploads.json') '{"files":[]}'
    Put (Join-Path $site 'uploads\shot-1.png') 'a picture'
    [void](New-Item -ItemType Directory -Path (Join-Path $site 'uploads\rec') -Force)
    $fs = [IO.File]::Create((Join-Path $site 'uploads\rec\recording.mp4')); $fs.SetLength(11MB); $fs.Dispose()
    foreach ($feed in 'feed', 'feed-dev') {
        Put (Join-Path $site "$feed\version.json") ('{"launcherVersion":"1.1.1","which":"' + $feed + '"}')
        Put (Join-Path $site "$feed\published.json") '{"packs":[]}'
        Put (Join-Path $site "$feed\launchers.txt") '1.1.1'
        Put (Join-Path $site "$feed\releases.txt") 'r1'
        Put (Join-Path $site "$feed\history\20260928T000000Z-version.json") '{"old":true}'
        Put (Join-Path $site "$feed\assets\$('a' * 64)") 'a download, not for the backup'
    }
    Put (Join-Path $bot 'bot.env.json') '{"DISCORD_TOKEN":"stand-in"}'
    Put (Join-Path $bot 'joins.json') '{"n":28}'
    Put (Join-Path $caddy 'Caddyfile') 'thornswood.net { }'
    Put (Join-Path $voice 'choices.json') '{}'
    $game = Join-Path $old 'game'; $gameDev = Join-Path $old 'game-dev'
    foreach ($g in $game, $gameDev) {
        Put (Join-Path $g 'world\changeForms\0.json') '{"profileId":1234567,"isDeleted":false}'
        Put (Join-Path $g 'server-settings.json') '{"port":45777,"loadOrder":[]}'
        Put (Join-Path $g 'gamemode.js') ('// gamemode of ' + (Split-Path -Leaf $g))
    }
    $plain = Join-Path $work 'backups'
    $code = Run $ps51 (Join-Path $scriptsDir 'vps\vps-nightly-backup.ps1') @(
        '-GameRoot', $game, '-DevGameRoot', $gameDev, '-SiteRoot', $site, '-BotRoot', $bot,
        '-CaddyRoot', $caddy, '-VoiceRoot', $voice, '-Out', $plain, '-KeyFile', (Join-Path $work 'no-key.txt'), '-Plain')
    $zip = @(Get-ChildItem -LiteralPath $plain -Filter 'thornswood-*.zip' -File -EA SilentlyContinue)
    Yes "the nightly backup runs against a scratch site (exit $code)" ($code -eq 0 -and $zip.Count -eq 1)
    if (-not $zip.Count) { Show; throw 'no backup' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zip[0].FullName)
    $names = @($z.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
    $z.Dispose()
    Yes '  and takes the site''s uploads' ($names -contains 'site/uploads/shot-1.png' -and $names -contains 'site/uploads/uploads.json')
    $store = foreach ($feed in 'feed', 'feed-dev') { foreach ($n in 'version.json', 'published.json', 'launchers.txt', 'releases.txt', 'history/20260928T000000Z-version.json') { "site/$feed/$n" } }
    Yes '  and both feeds'' store with its history' (@($store | Where-Object { $names -notcontains $_ }).Count -eq 0)
    Yes '  and not the feeds'' downloads' (@($names | Where-Object { $_ -like 'site/feed*/assets/*' }).Count -eq 0)
    Yes '  and a recording in uploads while the folder is under its budget' ($names -contains 'site/uploads/rec/recording.mp4')

    # The advisory threshold must not omit a recording from recovery.
    $tight = Join-Path $work 'backups-tight'
    $code = Run $ps51 (Join-Path $scriptsDir 'vps\vps-nightly-backup.ps1') @(
        '-GameRoot', $game, '-DevGameRoot', $gameDev, '-SiteRoot', $site, '-BotRoot', $bot,
        '-CaddyRoot', $caddy, '-VoiceRoot', $voice, '-Out', $tight, '-KeyFile', (Join-Path $work 'no-key.txt'), '-Plain', '-MaxUploadsMB', '5')
    $tz = @(Get-ChildItem -LiteralPath $tight -Filter 'thornswood-*.zip' -File -EA SilentlyContinue)
    $tnames = @()
    if ($tz.Count) { $z = [IO.Compression.ZipFile]::OpenRead($tz[0].FullName); $tnames = @($z.Entries | ForEach-Object { $_.FullName -replace '\\', '/' }); $z.Dispose() }
    Yes "over its advisory threshold, uploads keeps pictures, metadata and the recording (exit $code)" (
        $code -eq 0 -and $tz.Count -eq 1 -and $tnames -contains 'site/uploads/shot-1.png' -and
        $tnames -contains 'site/uploads/uploads.json' -and $tnames -contains 'site/uploads/rec/recording.mp4' -and
        (Said 'uploads exceed the advisory threshold of 5 MB; every file will be taken'))
    if ($tz.Count) {
        $tightRestored = Join-Path $work 'tight-restored'
        $code = Run $ps51 (Join-Path $scriptsDir 'vps\Restore-Backup.ps1') @('-Backup', $tz[0].FullName, '-To', $tightRestored, '-NoPause')
        $recording = Join-Path $tightRestored 'site\uploads\rec\recording.mp4'
        Yes "the over-threshold recording restores with its original bytes (exit $code)" (
            $code -eq 0 -and (Test-Path -LiteralPath $recording) -and (Get-Item -LiteralPath $recording).Length -eq 11MB -and
            (Get-FileHash -LiteralPath $recording).Hash -eq (Get-FileHash -LiteralPath (Join-Path $site 'uploads\rec\recording.mp4')).Hash)
    }

    $unpacked = Join-Path $work 'unpacked'
    $code = Run $ps51 (Join-Path $scriptsDir 'vps\Restore-Backup.ps1') @('-Backup', $zip[0].FullName, '-To', $unpacked, '-NoPause')
    Yes "Restore-Backup.ps1 unpacks it (exit $code)" ($code -eq 0)

    $new = Join-Path $work 'new'
    $nSite = Join-Path $new 'Thornswood-Docs'; $nBot = Join-Path $new 'Thornswood-Bot'; $nCaddy = Join-Path $new 'Thornswood-Caddy'
    $nGame = Join-Path $new 'Thornswood-Server'; $nDev = Join-Path $new 'Thornswood-Server-Dev'
    # As the installers leave a new box: an empty data folder, a config the
    # site made on a first start, the downloads already mirrored, and the
    # gamemode from main in live and the backup's in dev.
    [void](New-Item -ItemType Directory -Path (Join-Path $nSite 'data') -Force)
    Put (Join-Path $nSite 'config.json') '{"secret":"made on first start"}'
    Put (Join-Path $nSite "feed\assets\$('a' * 64)") 'mirrored already'
    Put (Join-Path $nGame 'gamemode.js') '// gamemode from main'
    Put (Join-Path $nDev 'gamemode.js') '// gamemode of game-dev'
    $svc = Join-Path $scriptsDir 'vps\vps-restore-services.ps1'
    $roots = @('-SiteRoot', $nSite, '-BotRoot', $nBot, '-CaddyRoot', $nCaddy, '-GameRoot', $nGame, '-DevGameRoot', $nDev)
    $code = Run $ps51 $svc (@('-From', $unpacked) + $roots)
    Yes "vps-restore-services.ps1 puts it back (exit $code)" ($code -eq 0 -and (Said 'SERVICES OK'))
    if ($code -ne 0) { Show }
    Yes '  the site''s data' ((Test-Path -LiteralPath (Join-Path $nSite 'data\board.json')) -and (Test-Path -LiteralPath (Join-Path $nSite 'data\site\about.md')))
    Yes '  its config, keeping the one the site made on first start aside' (
        [IO.File]::ReadAllText((Join-Path $nSite 'config.json')) -match 'stand-in' -and
        @(Get-ChildItem -LiteralPath $nSite -Filter 'config.json-before-restore-*').Count -eq 1)
    Yes '  its uploads' (Test-Path -LiteralPath (Join-Path $nSite 'uploads\shot-1.png'))
    Yes '  both feeds'' store and history, beside the downloads already there' (
        [IO.File]::ReadAllText((Join-Path $nSite 'feed-dev\version.json')) -match 'feed-dev' -and
        (Test-Path -LiteralPath (Join-Path $nSite 'feed\releases.txt')) -and
        (Test-Path -LiteralPath (Join-Path $nSite 'feed\history\20260928T000000Z-version.json')) -and
        [IO.File]::ReadAllText((Join-Path $nSite "feed\assets\$('a' * 64)")) -eq 'mirrored already')
    $envFile = Join-Path $nBot 'bot.env.json'
    Yes '  the bot''s settings and join record' ((Test-Path -LiteralPath $envFile) -and (Test-Path -LiteralPath (Join-Path $nBot 'data\joins.json')))
    $acl = if (Test-Path -LiteralPath $envFile) { Get-Acl -LiteralPath $envFile } else { $null }
    $who = if ($acl) { @($acl.Access | ForEach-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value }) } else { @() }
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    Yes '  with the bot''s settings shut to all but SYSTEM, Administrators and whoever ran it' (
        $acl -and $acl.AreAccessRulesProtected -and @($who | Where-Object { @('S-1-5-18', 'S-1-5-32-544', $me) -notcontains $_ }).Count -eq 0)
    Yes '  the Caddyfile' (Test-Path -LiteralPath (Join-Path $nCaddy 'Caddyfile'))
    Yes '  and not choices.json, which the nightly backup no longer takes (#1084)' ($names -notcontains 'voice/choices.json')
    Yes '  and says the live gamemode differs from the backup''s and the dev one does not' (
        (Said ('GAMEMODE DIFFERS\s+' + [regex]::Escape($nGame))) -and (Said ('gamemode\s+' + [regex]::Escape($nDev) + '\\gamemode.js is the one')))

    $code = Run $ps51 $svc (@('-From', $unpacked) + $roots)
    Yes "a second run keeps the data folder it replaced (exit $code)" ($code -eq 0 -and @(Get-ChildItem -LiteralPath $nSite -Directory -Filter 'data-before-restore-*').Count -eq 1)

    # Two restores inside one second (#1107). What an earlier run kept under
    # this second's name is not in the way: stand-ins for it are put there for
    # the next minute, and the run keeps its own copies beside them, under
    # that second's name with a number after it.
    # Judged by what the run added, never by which number it took (#1117): on
    # a fast runner all three runs here land in one second (the VPS runner
    # takes about 0.4 s a run), the second run has already taken -2, and this
    # one rightly takes -3. So the check reads the same whichever second each
    # run lands in: exactly one new config copy and one new data copy, both
    # under a numbered name and holding what was in place, and everything
    # kept before the run left exactly as it was. The stand-ins take each
    # second's plain name and its -2 as well, so this run always meets the
    # case that went red: it has to go to -3, whatever the clock says.
    $at = Get-Date
    foreach ($s in 0..60) {
        $st = $at.AddSeconds($s).ToString('yyyyMMdd-HHmmss')
        foreach ($tail in '', '-2') {
            $cf = Join-Path $nSite ('config.json-before-restore-' + $st + $tail)
            if (-not (Test-Path -LiteralPath $cf)) { Put $cf '{"kept":"earlier"}' }
            [void](New-Item -ItemType Directory -Force -Path (Join-Path $nSite ('data-before-restore-' + $st + $tail)))
        }
    }
    function Kept {
        $h = @{}
        foreach ($i in @(Get-ChildItem -LiteralPath $nSite -Filter '*-before-restore-*' -Force)) {
            $h[$i.Name] = if ($i.PSIsContainer) { 'dir:' + ((@(Get-ChildItem -LiteralPath $i.FullName -Force -Recurse | ForEach-Object { $_.Name }) | Sort-Object) -join '|') }
                          else { 'file:' + [IO.File]::ReadAllText($i.FullName) }
        }
        return $h
    }
    $before = Kept
    $code = Run $ps51 $svc (@('-From', $unpacked) + $roots)
    $after = Kept
    $added = @($after.Keys | Where-Object { -not $before.ContainsKey($_) })
    $changed = @($before.Keys | Where-Object { $after[$_] -ne $before[$_] })
    $newFile = @($added | Where-Object { $_ -like 'config.json-before-restore-*' })
    $newDir = @($added | Where-Object { $_ -like 'data-before-restore-*' })
    $numbered = '-before-restore-\d{8}-\d{6}-\d+$'
    Yes "a run in the same second as the last keeps its copies beside that one's, not over or inside them (exit $code)" (
        $code -eq 0 -and $changed.Count -eq 0 -and $newFile.Count -eq 1 -and $newDir.Count -eq 1 -and
        $newFile[0] -match $numbered -and $newDir[0] -match $numbered -and
        $after[$newFile[0]] -match 'stand-in' -and $after[$newDir[0]] -match '(^dir:|\|)board\.json(\||$)' -and
        @(Get-ChildItem -LiteralPath $nSite -Directory -Filter 'data-before-restore-*' | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'data') }).Count -eq 0)
    if (-not ($changed.Count -eq 0 -and $newFile.Count -eq 1 -and $newDir.Count -eq 1)) {
        Write-Host ('        added: {0}; changed: {1}' -f ($added -join ', '), ($changed -join ', '))
    }

    $thin = Join-Path $work 'thin'
    Copy-Item -LiteralPath $unpacked -Destination $thin -Recurse
    Remove-Item -LiteralPath (Join-Path $thin 'bot\bot.env.json') -Force
    $code = Run $ps51 $svc (@('-From', $thin) + $roots)
    Yes "a backup without the bot's settings ends SERVICES INCOMPLETE (exit $code)" ($code -ne 0 -and (Said 'SERVICES INCOMPLETE: not in the backup: bot\\bot.env.json'))

    $code = Run $ps51 $svc (@('-From', (Join-Path $work 'nowhere')) + $roots)
    Yes "a folder that is not an unpacked backup is refused (exit $code)" ($code -ne 0 -and (Said 'no unpacked backup'))

    $node = Get-Command node -EA SilentlyContinue
    if ($node) {
        $p = Start-Process -FilePath $node.Source -WindowStyle Hidden -PassThru -ArgumentList @('-e', '"setTimeout(function(){},60000)"', ('"' + $nSite + '\server.js"'))
        try {
            Start-Sleep -Milliseconds 500
            $code = Run $ps51 $svc (@('-From', $unpacked) + $roots)
            Yes "it refuses while the site runs from the folder (exit $code)" ($code -ne 0 -and (Said 'Running from a folder this writes into'))
        } finally { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
    } else { Write-Host 'SKIP  no node here to stand in for a running site' }
}
catch {
    if ("$_" -ne 'skip') { Yes ('the runs finished without an error: ' + $_.Exception.Message) $false; Show }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -EA SilentlyContinue
}

Done
