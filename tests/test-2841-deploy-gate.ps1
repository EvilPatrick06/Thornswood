<#
  test-2841-deploy-gate.ps1

      pwsh -NoProfile -File .\tests\test-2841-deploy-gate.ps1

  The deploy gate (#2841): the restricted, non-admin account whose key runs
  one dispatcher with only the named Deploy, Install and Get-Logs verbs, held
  only in the "desk" GitHub environment. This holds:
    1. Every file of it parses, and the files the box runs under Windows
       PowerShell 5.1 are plain ASCII (5.1 reads a file with no byte order
       mark as the system code page).
    2. The rules (scripts\vps\gate\GateRules.ps1): lines the gate takes give
       exactly the words the broker starts the script with, and every line
       that names another verb, a parameter outside the verb's list, a value
       outside its rule or a character a shell or PowerShell would read is
       refused whole. Under Windows PowerShell 5.1 too, when there is one.
    3. verbs.json against the scripts: each verb's script is there, takes
       every parameter the gate lets through and every fixed word, and no
       verb lets a caller name a host, a user, a folder, a file or a task.
    4. Gate.ps1 holds no rule and runs nothing: it reads
       SSH_ORIGINAL_COMMAND, hands it over the pipe and prints the answer.
    5. GateBroker.ps1: the pipe takes only SYSTEM and the deploy account, and
       no other machine; every line goes through Test-ThornswoodGateRequest
       before anything runs; what runs is main's tip and nothing a caller
       names; the program is started with no shell.
    6. Install-Gate.ps1: the account goes in no group, its .ssh only SYSTEM
       and Administrators may change, it may read Gate.ps1 alone, and the
       files go up from HEAD.
    7. Grant-BoxAccess.ps1 -Deploy: the line it writes, and its reader.
    8. box-run.yml: main-only environment, the key in one step's
       environment, no input pasted into a script, actions pinned by SHA.
    9. The seal (scripts\ops\Sealed.ps1) opens with its own key only, and a changed byte
       is refused; the box half uses the signed ssh.exe by full path.
  Nothing connects anywhere and nothing outside the temp folder is touched.
#>
[CmdletBinding()]
param()
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
function Text([string]$rel) { return [IO.File]::ReadAllText((Join-Path $Repo $rel)) }
# The named functions of a script, defined here without running the script.
function Import-Functions([string]$rel, [string[]]$names) {
    $err = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo $rel), [ref]$null, [ref]$err)
    $out = @()
    foreach ($n in $names) {
        $f = $ast.Find({ param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq $n }, $true)
        if ($f) { $out += $f.Extent.Text }
    }
    return ($out -join "`n")
}

$gateFiles = @('scripts/vps/gate/Gate.ps1', 'scripts/vps/gate/GateBroker.ps1', 'scripts/vps/gate/GateRules.ps1')
$all = $gateFiles + @('scripts/deploy/Install-Gate.ps1', 'scripts/vps/Box-Run.ps1', 'scripts/vps/Grant-BoxAccess.ps1')

# ---- 1. parses, and plain ASCII where 5.1 reads it ---------------------------
foreach ($f in $all) {
    $err = $null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $Repo $f), [ref]$null, [ref]$err)
    Yes "$f parses" (-not $err -or $err.Count -eq 0)
}
foreach ($f in $gateFiles + @('scripts/vps/gate/verbs.json', 'scripts/deploy/Install-Gate.ps1')) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $Repo $f))
    Yes "$f is plain ASCII" (-not @($bytes | Where-Object { $_ -gt 126 -or ($_ -lt 32 -and $_ -ne 9 -and $_ -ne 10 -and $_ -ne 13) }).Count)
}
$verbsRaw = Text 'scripts/vps/gate/verbs.json'
$verbs = $verbsRaw | ConvertFrom-Json
Yes 'verbs.json is JSON with verbs' ($null -ne $verbs.verbs)

# ---- 2. the rules ------------------------------------------------------------
. (Join-Path $Repo 'scripts/vps/gate/GateRules.ps1')
function Words([string]$line) { $r = Test-ThornswoodGateRequest -Line $line -Verbs $verbs; if ($r.Ok) { return ($r.Args -join '|') } else { return 'REFUSED' } }
Yes 'ping is taken, with nothing after it' ((Test-ThornswoodGateRequest -Line 'ping' -Verbs $verbs).Verb -eq 'ping' -and (Words 'ping now') -eq 'REFUSED')
Yes 'a switch and a quoted text value become their words, in order' ((Words 'Deploy-DevGamemode -Restart -Why "a gamemode update"') -eq '-Restart|-Why|a gamemode update')
Yes 'a verb''s fixed words come first' ((Words 'Install-Bot -PutBack') -eq '-CodeOnly|-NoPause|-PutBack')
Yes 'Get-Logs takes -Dev and -Lines, and names its out parameter' ((Words 'Get-Logs -Dev -Lines 2000') -eq '-NoPause|-Dev|-Lines|2000' -and (Test-ThornswoodGateRequest -Line 'Get-Logs' -Verbs $verbs).Out -eq '-Out')
Yes 'an enum value outside its list is refused' ((Words 'Deploy-DevGamemode -Npcs maybe') -eq 'REFUSED')
$refused = @(
    @('', 'an empty line'),
    @('Remove-Item C:\', 'a verb that is not on the list'),
    @('deploy-devgamemode', 'a verb in another case'),
    @('Deploy-DevGamemode -putback', 'a parameter in another case'),
    @('Deploy-DevGamemode -Vps 1.2.3.4', 'a host'),
    @('Deploy-DevGamemode -Root C:/x', 'a folder'),
    @('Deploy-DevGamemode -Data x', 'a data folder'),
    @('Deploy-DevGamemode -Dist x', 'a build folder'),
    @('Deploy-Docs -PasswordFile x', 'a file'),
    @('Get-Logs -Out x', 'the out folder, which the broker sets'),
    @('Install-Bot -RotateKey', 'a secret change'),
    @('Deploy-DevGamemode -Restart -Restart', 'a parameter twice'),
    @('Deploy-DevGamemode -Why', 'a parameter with no value'),
    @('Deploy-DevGamemode -Why -Restart', 'a value that starts with a hyphen'),
    @('Deploy-DevGamemode -Why "-Restart"', 'a quoted value that starts with a hyphen'),
    @('Deploy-DevGamemode -Why $(whoami)', 'a dollar sign'),
    @('Deploy-DevGamemode -Why a`b', 'a backtick'),
    @('Deploy-DevGamemode -Why a\b', 'a backslash'),
    @('Deploy-DevGamemode -Why a|b', 'a pipe'),
    @('Deploy-DevGamemode -Why a>b', 'an angle bracket'),
    @('Deploy-DevGamemode -Why "a"b', 'a quote followed by more'),
    @('Deploy-DevGamemode -Why "open', 'a quote that never closes'),
    @('Deploy-DevGamemode -Why a"b', 'a quote inside a word'),
    @('Deploy-DevGamemode -Why a&b', 'an ampersand'),
    @('Deploy-DevGamemode -Why a%PATH%', 'a percent sign'),
    @("Deploy-DevGamemode -Why caf`u{e9}", 'a character outside ASCII'),
    @("Deploy-DevGamemode -Restart`nGet-Logs", 'a second line'),
    @('Deploy-DevGamemode -Restart:$false', 'a switch with a value glued on'),
    @('Deploy-DevGamemode Restart', 'a word that is not a parameter'),
    @('Deploy-DevGamemode -Minutes 1e9', 'a number outside its pattern'),
    @(('Deploy-DevGamemode -Why "' + ('a' * 200) + '"'), 'text over its length'),
    @(('ping ' + ('a' * 700)), 'a line over 600 characters')
)
foreach ($r in $refused) { Yes ('refused: ' + $r[1]) ((Words $r[0]) -eq 'REFUSED') }
Yes 'a refusal says what the verb takes' ((Test-ThornswoodGateRequest -Line 'Deploy-DevGamemode -Vps x' -Verbs $verbs).Why -match '-Restart' )
Yes 'the command line quotes a word with a space and nothing else' ((Join-ThornswoodGateArgs @('-Why', 'a b', '-Restart', 'C:\Thornswood-Gate\repo')) -eq '-Why "a b" -Restart C:\Thornswood-Gate\repo')
$threw = $false; try { [void](Join-ThornswoodGateArgs @('a"b')) } catch { $threw = $true }
Yes 'the command line refuses a word with a double quote' $threw
$threw = $false; try { [void](Join-ThornswoodGateArgs @('x\y')) } catch { $threw = $true }
Yes '  and a backslash that is not a folder path of the broker''s' $threw
$threw = $false; try { [void](Join-ThornswoodGateArgs @('C:\x\')) } catch { $threw = $true }
Yes '  and a folder path that ends in a backslash' $threw

. (Join-Path $PSScriptRoot 'Windows.ps1')
if (-not $OnWindows) {
    Write-Host 'SKIP  the rules under Windows PowerShell 5.1, which the box runs them with: this is not Windows'
} else {
    $ps51 = Get-WindowsPowerShell
    $probe = Join-Path ([IO.Path]::GetTempPath()) ('tw-2841-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
    try {
        [IO.File]::WriteAllText($probe, @"
. '$((Join-Path $Repo 'scripts\vps\gate\GateRules.ps1').Replace("'", "''"))'
`$v = Read-ThornswoodGateVerbs '$((Join-Path $Repo 'scripts\vps\gate\verbs.json').Replace("'", "''"))'
foreach (`$l in 'Deploy-DevGamemode -Restart -Why "a gamemode update"', 'Install-Bot', 'Deploy-DevGamemode -Vps x', 'Deploy-DevGamemode -Why `$(x)', 'ping') {
  `$r = Test-ThornswoodGateRequest -Line `$l -Verbs `$v
  if (`$r.Ok) { 'OK ' + (`$r.Args -join '|') } else { 'NO' }
}
"@)
        $said = @(& $ps51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe 2>&1 | ForEach-Object { "$_" })
        Yes 'under Windows PowerShell 5.1 the rules give the same words and refusals' (
            ($said -join ';') -eq 'OK -Restart|-Why|a gamemode update;OK -CodeOnly|-NoPause;NO;NO;OK ')
        if (($said -join ';') -ne 'OK -Restart|-Why|a gamemode update;OK -CodeOnly|-NoPause;NO;NO;OK ') { $said | Write-Host }
    } finally { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
}

# ---- 3. verbs.json against the scripts ---------------------------------------
$never = @('Vps', 'VpsHost', 'User', 'VpsUser', 'Root', 'Task', 'TaskName', 'Data', 'Dist', 'Out', 'PasswordFile', 'Path', 'Script', 'Command', 'Site', 'Gamemode', 'ServerBuild', 'Note', 'DropPlugins', 'AsSystem', 'RunAs', 'Remove', 'RotateKey', 'Password')
# Deploy-Docs -Site is a switch (which part of the site to send), not an address.
foreach ($p in $verbs.verbs.PSObject.Properties) {
    $v = $p.Value
    $path = Join-Path $Repo $v.script
    Yes "$($p.Name): its script $($v.script) is there" (Test-Path -LiteralPath $path)
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
    $takes = @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    $isSwitch = @{}
    foreach ($pp in @($ast.ParamBlock.Parameters)) { $isSwitch[$pp.Name.VariablePath.UserPath] = ($pp.StaticType -eq [switch]) }
    foreach ($q in @($v.params.PSObject.Properties)) {
        Yes "$($p.Name) -$($q.Name): the script takes it" ($takes -contains $q.Name)
        if ($takes -contains $q.Name) { Yes "$($p.Name) -$($q.Name): a switch in the script is a switch at the gate, and a value a value" ($isSwitch[$q.Name] -eq ($q.Value -eq 'switch')) }
        $isSiteSwitch = ($p.Name -eq 'Deploy-Docs' -and $q.Name -eq 'Site')
        Yes "$($p.Name) -$($q.Name): not a host, user, folder, file, task or secret" ($isSiteSwitch -or $never -notcontains $q.Name)
    }
    foreach ($w in @($v.fixed | Where-Object { $_ })) { Yes "$($p.Name) fixed $w`: the script takes it" ($takes -contains $w.TrimStart('-')) }
    if ($v.out) { Yes "$($p.Name) out $($v.out): the script takes it" ($takes -contains ([string]$v.out).TrimStart('-')) }
    Yes "$($p.Name): a timeout of an hour at most, which box-run.yml's job allows" ([int]$v.timeoutMinutes -gt 0 -and [int]$v.timeoutMinutes -le 45)
}

# ---- 4. Gate.ps1 holds no rule and runs nothing ------------------------------
$gate = Text 'scripts/vps/gate/Gate.ps1'
$gateCode = ($gate -replace '(?s)<#.*?#>', '')
Yes 'Gate.ps1 reads SSH_ORIGINAL_COMMAND and nothing else from the caller' ($gateCode.Contains('$env:SSH_ORIGINAL_COMMAND') -and $gateCode -notmatch '\$args|param\(')
Yes '  runs nothing: no Invoke-Expression, no call operator, no Start-Process, no Process' ($gateCode -notmatch 'Invoke-Expression|\biex\b|Start-Process|Diagnostics\.Process|(^|\s)&\s' )
Yes '  and talks to the broker''s pipe by its name' ($gateCode.Contains("'thornswood-gate'"))
Yes '  sends the line in base64, so no character in it ends the request' ($gateCode.Contains("'LINE ' + [Convert]::ToBase64String"))
Yes '  loads no module and writes through [Console] (#3059)' ($gateCode -notmatch 'ConvertTo-Json|Import-Module|Write-Host|Write-Output' -and $gateCode.Contains('[Console]::Out'))

# ---- 5. the broker -----------------------------------------------------------
$broker = Text 'scripts/vps/gate/GateBroker.ps1'
$brokerCode = ($broker -replace '(?s)<#.*?#>', '')
Yes 'the pipe denies every other machine (NETWORK)' ($brokerCode -match "S-1-5-2'\)\), \[IO\.Pipes\.PipeAccessRights\]::FullControl, \[Security\.AccessControl\.AccessControlType\]::Deny")
Yes '  and allows SYSTEM and the deploy account alone' (
    $brokerCode.Contains("SecurityIdentifier('S-1-5-18')") -and $brokerCode.Contains('[string]$Cfg.deploySid') -and
    @([regex]::Matches($brokerCode, 'AccessControlType\]::Allow')).Count -eq 2)
Yes '  and takes one connection at a time' ($brokerCode -match "NamedPipeServerStream\('thornswood-gate', \[IO\.Pipes\.PipeDirection\]::InOut, 1,")
$tested = $brokerCode.IndexOf('Test-ThornswoodGateRequest -Line $line')
Yes 'every line goes through the rules before anything runs' ($tested -gt 0 -and $tested -lt $brokerCode.IndexOf('$commit = Update-Checkout') -and $tested -lt $brokerCode.IndexOf('Invoke-Child ([string]$Cfg.pwsh)'))
Yes '  and the rules are the installed verbs.json, not anything sent' ($brokerCode.Contains("Read-ThornswoodGateVerbs (Join-Path `$Root 'verbs.json')"))
Yes 'what runs is the tip of main: fetched into origin/main and checked out from it' (
    $brokerCode.Contains("'+refs/heads/main:refs/remotes/origin/main'") -and $brokerCode.Contains("'--detach', 'refs/remotes/origin/main'") -and $brokerCode.Contains("'clean', '-ffdxq'"))
Yes 'the script is the verb''s from verbs.json, under the checkout' ($brokerCode.Contains('Join-Path $Repo ($req.Script.Replace(''/'', ''\'')'))
Yes 'the program starts with no shell, and nothing on its input' ($brokerCode.Contains('$si.UseShellExecute = $false') -and $brokerCode.Contains('$p.StandardInput.Close()') -and $brokerCode -notmatch 'Invoke-Expression|\biex\b|cmd(\.exe)? /c')
Yes 'a run past its time is ended with everything it started' ($brokerCode.Contains('taskkill.exe" /T /F /PID'))
Yes 'git reads with the deploy key and pinned host keys only' ($brokerCode.Contains('-F none -i') -and $brokerCode.Contains('StrictHostKeyChecking=yes') -and $brokerCode.Contains('github_known_hosts'))
Yes 'every request is logged, refusals too' ($brokerCode.Contains("Log ('REFUSED [") -and $brokerCode.Contains("Log ('START ") -and $brokerCode.Contains("Log ('END "))

# ---- 6. the installer ----------------------------------------------------------
$inst = Text 'scripts/deploy/Install-Gate.ps1'
Yes 'the account is made in no group, and taken out of any it is in' ($inst.Contains('New-LocalUser -Name `$user') -and $inst.Contains('Remove-LocalGroupMember') -and $inst -notmatch 'Add-LocalGroupMember')
Yes 'its .ssh and authorized_keys: only SYSTEM and Administrators change them, it reads them' (
    $inst.Contains('foreach (`$s in ''S-1-5-18'', ''S-1-5-32-544'')') -and $inst.Contains('SecurityIdentifier(`$sid)), ''ReadAndExecute''') -and $inst.Contains('SetAccessRuleProtection(`$true, `$false)'))
Yes 'it may read Gate.ps1, and no other file of the gate is given to it' (@([regex]::Matches($inst, [regex]::Escape('SecurityIdentifier(`$sid)), ''ReadAndExecute'''))).Count -eq 2 -and $inst.Contains('`$gate = Join-Path `$root ''Gate.ps1'''))
Yes 'the gate''s folder is locked to SYSTEM and Administrators' ($inst.Contains('Lock-ThornswoodFolder -Path `$root -Only'))
Yes 'the files go up from HEAD, and uncommitted changes stop it' ($inst.Contains("'cat-file', 'blob', `"HEAD:`$f`"") -and $inst.Contains('status --porcelain -- $Files'))
Yes 'the GitHub key goes on read only' ($inst.Contains('read_only = $true') -and $inst -notmatch 'read_only = \$false')
Yes 'the gate''s admin key is taken only from 127.0.0.1' ($inst.Contains('`$want = ''from="127.0.0.1" '' + `$bare + '' thornswood-gate'''))
Yes 'the box''s host keys are held to vps.json''s pins' ($inst.Contains('Get-ThornswoodVpsHostKeys') -and $inst.Contains('`$pins -contains `$fp'))
Yes 'the task runs the installed broker, not anything in the checkout' ($inst.Contains('(Join-Path `$root ''GateBroker.ps1'')'))

# ---- 7. Grant-BoxAccess -Deploy ------------------------------------------------
Invoke-Expression (Import-Functions 'scripts/vps/Grant-BoxAccess.ps1' @('Get-BoxKeyLine', 'Read-BoxKeyLine'))
$GateScript = 'C:\Thornswood-Gate\Gate.ps1'
$SayStaff = 'C:\Thornswood-Watch\say-staff.ps1'
$bare = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKk0ZXN0a2V5Zm9ydGhlZ2F0ZXRlc3QwMDAwMDAwMDAw'
$line = Get-BoxKeyLine $bare 'desk' $false $true
Yes 'a deploy key''s line: from the box only, restricted, forced to Gate.ps1' ($line -eq ('from="127.0.0.1",restrict,command="powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\Thornswood-Gate\Gate.ps1" ' + $bare + ' thornswood-desk'))
$parts = Read-BoxKeyLine $line
Yes '  and its reader sees the bridge and the gate in it, and no notices command' ($parts.Bridge -and $parts.Gate -and -not $parts.Notices -and $parts.Key -eq $bare)
Yes 'a plain key''s line is unchanged' ((Get-BoxKeyLine $bare 'one' $false) -eq ('from="127.0.0.1" ' + $bare + ' thornswood-one'))
Yes 'a notices key''s line is unchanged' ((Get-BoxKeyLine $bare 'claude' $true) -like 'from="127.0.0.1",restrict,command="powershell.exe * -File C:\Thornswood-Watch\say-staff.ps1 -From claude" *')
$grant = Text 'scripts/vps/Grant-BoxAccess.ps1'
Yes 'a deploy key goes into the gate account''s authorized_keys, and stops without the account' ($grant.Contains("Run scripts\deploy\Install-Gate.ps1 first") -and $grant.Contains("ProfileImagePath '.ssh\authorized_keys'"))
Yes 'its proof needs a refused command and GATE READY' ($grant.Contains("@('echo THORNSWOOD_OK', 'ping')") -and $grant.Contains("'^\| GATE READY'") -and $grant.Contains('($NoticesOnly -or $Deploy) -and @($proof | Where-Object { $_ -match ''THORNSWOOD_OK'' }).Count'))
Yes 'it goes into DESK_KEY_B64 of a main-only environment' ($grant.Contains("if (`$Deploy) { 'DESK_KEY_B64' }") -and $grant.Contains('gh secret set $SecretName --env $ToEnvironment'))

# ---- 8. box-run.yml ------------------------------------------------------------
$wf = Text '.github/workflows/box-run.yml'
Yes 'box-run.yml starts by hand only (workflow_dispatch)' ($wf -match '(?m)^on:\s*\r?\n\s+workflow_dispatch:' -and $wf -notmatch '(?m)^\s+(push|pull_request|pull_request_target|schedule|workflow_run):')
Yes '  in the desk environment, on a box runner' ($wf.Contains('environment: desk') -and $wf.Contains('runs-on: [self-hosted, Windows, thornswood-vps]'))
Yes '  the key in one step''s environment, and nowhere else' (@([regex]::Matches($wf, 'secrets\.')).Count -eq 1 -and $wf.Contains('THORNSWOOD_DESK_KEY_B64: ${{ secrets.DESK_KEY_B64 }}'))
$runBlocks = @([regex]::Matches($wf, '(?ms)^\s+run: \|\s*\r?\n(.*?)(?=^\s+- |\z)') | ForEach-Object { $_.Groups[1].Value })
Yes '  no input is pasted into a script; they reach it through the environment' (-not @($runBlocks | Where-Object { $_ -match '\$\{\{' }).Count)
Yes '  every action pinned by a full commit SHA' (-not @([regex]::Matches($wf, 'uses: [^\s@]+@(?![0-9a-f]{40}\b)')).Count)
Yes '  its output leaves the runner sealed, kept a day' ($wf.Contains('name: box-run-sealed') -and $wf.Contains('retention-days: 1'))

# ---- 9. the seal, and the ssh it uses -------------------------------------------
. (Join-Path $Repo 'scripts/ops/Sealed.ps1')
$rsa = [Security.Cryptography.RSA]::Create(3072)
$other = [Security.Cryptography.RSA]::Create(3072)
$plain = [Text.Encoding]::UTF8.GetBytes('the servers'' logs ' + ('x' * 5000))
$sealed = Protect-ThornswoodSealed $plain ([Convert]::ToBase64String($rsa.ExportSubjectPublicKeyInfo()))
$back = Unprotect-ThornswoodSealed $sealed ([Convert]::ToBase64String($rsa.ExportPkcs8PrivateKey()))
Yes 'a sealed run opens with its own key to what went in' ([Convert]::ToBase64String($back) -eq [Convert]::ToBase64String($plain))
Yes '  and holds none of it in the clear' (-not ([Text.Encoding]::UTF8.GetString($sealed)).Contains('servers'))
$threw = $false; try { [void](Unprotect-ThornswoodSealed $sealed ([Convert]::ToBase64String($other.ExportPkcs8PrivateKey()))) } catch { $threw = $true }
Yes '  another key does not open it' $threw
$bent = [byte[]]$sealed.Clone(); $bent[$bent.Length - 3] = $bent[$bent.Length - 3] -bxor 1
$threw = $false; try { [void](Unprotect-ThornswoodSealed $bent ([Convert]::ToBase64String($rsa.ExportPkcs8PrivateKey()))) } catch { $threw = $true }
Yes '  and a changed byte is refused' $threw
$small = [Security.Cryptography.RSA]::Create(2048)
$threw = $false; try { [void](Protect-ThornswoodSealed $plain ([Convert]::ToBase64String($small.ExportSubjectPublicKeyInfo()))) } catch { $threw = $true }
Yes '  a recipient key under 3072 bits is refused' $threw
$br = Text 'scripts/vps/Box-Run.ps1'
Yes 'the box half uses the Microsoft-signed ssh.exe by its full path' ($br.Contains("& `$sshExe @sshArgs (`$GateUser + '@127.0.0.1') `$Line") -and $br.Contains('Get-AuthenticodeSignature') -and $br.Contains("O=Microsoft Corporation"))
Yes '  with the host keys held to the checkout''s pins, in a known_hosts of the run''s own' ($br.Contains('Get-ThornswoodVpsCommitted') -and $br.Contains("UserKnownHostsFile=`$knownHosts") -and $br.Contains("'-F', 'none'"))
Yes '  and prints none of the verb''s output into the run''s log' ($br -notmatch 'Write-Host \$Matches\[1\]' -and $br.Contains("[IO.File]::AppendAllText(`$out, `$Matches[1]"))

Write-Host ''
Write-Host "$script:pass passed, $script:fail failed"
if ($script:fail) { exit 1 }
