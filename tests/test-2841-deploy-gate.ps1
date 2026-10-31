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
    8. box-run.yml is not in this repository but in the private ops
       repository, with the VPS runners (#4013), and Box-Run.ps1 starts it
       there; the ops repository's tests\test-box-workflows.ps1 holds its
       shape.
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
# The weekly review's launcher start read (#3534): a number of days and
# nothing else, never the folder it reads.
Yes 'Read-LauncherStarts takes -Days, a number, and nothing else' ((Words 'Read-LauncherStarts -Days 7') -eq '-Days|7' -and (Words 'Read-LauncherStarts') -eq '' -and
    (Words 'Read-LauncherStarts -Days week') -eq 'REFUSED' -and (Words 'Read-LauncherStarts -Folder x') -eq 'REFUSED')
# Publish-Server through the gate is the dev server's, from the box's store,
# and nothing else (#4987): main stays with a Main run Patrick approves.
Yes 'Publish-Server is held to -Channel dev' ((Words 'Publish-Server') -eq '-Channel|dev' -and
    (Words 'Publish-Server -RequirePass on -Wait 300') -eq '-Channel|dev|-RequirePass|on|-Wait|300' -and
    $verbs.verbs.'Publish-Server'.script -eq 'scripts/release/Publish-ServerOnBox.ps1')
Yes '  and a caller cannot name main, a build, a zip or a fresh world' ((Words 'Publish-Server -Channel main') -eq 'REFUSED' -and
    (Words 'Publish-Server -ServerBuild x') -eq 'REFUSED' -and (Words 'Publish-Server -Zip x') -eq 'REFUSED' -and (Words 'Publish-Server -FreshWorld') -eq 'REFUSED')
# The live verbs (Patrick, 30 Oct 2026: Ships and deploys run from the
# cloud, never One): each names the exact build of main it is for with
# -Build, which the broker holds to main's tip and never hands the script.
$sha = 'a' * 40
foreach ($live in 'Deploy-Server', 'Publish-Server-Main') { Yes "$live is a live verb, held to a build" ($verbs.verbs.$live.build -eq $true) }
Yes 'a live verb without -Build is refused, and says why' ((Words 'Deploy-Server -GamemodeOnly') -eq 'REFUSED' -and
    (Test-ThornswoodGateRequest -Line 'Deploy-Server -GamemodeOnly' -Verbs $verbs).Why -match 'exact build')
$req = Test-ThornswoodGateRequest -Line ("Deploy-Server -GamemodeOnly -Build $sha -Mode restart") -Verbs $verbs
Yes '  and with it, the build is the gate''s and never the script''s' ($req.Ok -and $req.Build -eq $sha -and ($req.Args -join '|') -eq '-GamemodeOnly|-Mode|restart')
Yes '  -Build is a full lower case commit, given once' ((Words "Deploy-Server -FromStore -Build abc123") -eq 'REFUSED' -and (Words ("Deploy-Server -FromStore -Build " + ('A' * 40))) -eq 'REFUSED' -and
    (Words "Deploy-Server -FromStore -Build $sha -Build $sha") -eq 'REFUSED' -and (Words 'Deploy-Server -FromStore -Build') -eq 'REFUSED')
Yes '  a verb that is not live takes no -Build' ((Words "Deploy-DevGamemode -Build $sha") -eq 'REFUSED' -and (Test-ThornswoodGateRequest -Line 'Deploy-DevGamemode' -Verbs $verbs).Build -eq '')
Yes 'Publish-Server-Main is held to -Channel main' ((Words "Publish-Server-Main -Build $sha -RequirePass on") -eq '-Channel|main|-RequirePass|on' -and
    $verbs.verbs.'Publish-Server-Main'.script -eq 'scripts/release/Publish-ServerOnBox.ps1' -and
    (Words "Publish-Server-Main -Build $sha -Channel dev") -eq 'REFUSED' -and (Words "Publish-Server-Main -Build $sha -ServerBuild x") -eq 'REFUSED')
$pubBox = Text 'scripts/release/Publish-ServerOnBox.ps1'
# A pin move's first publish (31 Oct 2026, 09a4b398): the store lacked the
# new build, and only One's plain publish sent it there.
Yes '  Publish-ServerOnBox.ps1 fetches CI''s engine build with the App''s token and sends its zip to the store before publishing from it' (
    $pubBox.Contains("& (Join-Path `$Here 'Get-EngineArtifact.ps1') -NoPause") -and $pubBox.Contains("`$pub['FromStore'] = `$true") -and $pubBox.Contains("`$pub['ServerBuild'] = `$ciZip") -and
    $pubBox.Contains('$env:GH_TOKEN = $token') -and $pubBox.Contains('finally { Remove-Item -LiteralPath Env:\GH_TOKEN') -and
    $pubBox.IndexOf('Get-EngineArtifact.ps1') -lt $pubBox.IndexOf("& (Join-Path `$Here 'Publish-Server.ps1') @pub"))
Yes '  and -PutBack and -TaskOnly go without a fetch or -FromStore, which Publish-Server.ps1 refuses with them' ($pubBox.Contains('if (-not $PutBack -and -not $TaskOnly) {') -and
    (Text 'scripts/release/Publish-Server.ps1').Contains('if ($FromStore -and ($PutBack -or $TaskOnly))'))
Yes '  both box scripts mint the token through ShipAccess.ps1' ($pubBox.Contains('Get-ThornswoodShipAccess -Repo $repo -AdminState $AdminState') -and
    (Text 'scripts/release/Ship-OnBox.ps1').Contains('Get-ThornswoodShipAccess -Repo $repo -AdminState $AdminState'))
Yes 'Deploy-Server takes no host, folder, build folder or role list' ((Words "Deploy-Server -Build $sha -Vps x") -eq 'REFUSED' -and (Words "Deploy-Server -Build $sha -Root C:/x") -eq 'REFUSED' -and
    (Words "Deploy-Server -Build $sha -Dist x") -eq 'REFUSED' -and (Words "Deploy-Server -Build $sha -Devs 1") -eq 'REFUSED')
# Content rebuilds through the gate (Patrick's card, 30 Oct 2026): main's
# whole chain against a server's plugins, its files back through -Out.
Yes 'Rebuild-ContentTables takes -Server dev or main, and names its out parameter' ((Words 'Rebuild-ContentTables') -eq '' -and (Words 'Rebuild-ContentTables -Server main') -eq '-Server|main' -and
    (Words 'Rebuild-ContentTables -Server live') -eq 'REFUSED' -and (Test-ThornswoodGateRequest -Line 'Rebuild-ContentTables' -Verbs $verbs).Out -eq '-Out')
Yes '  and cannot name a branch, a tool or a build' ((Words "Rebuild-ContentTables -Build $sha") -eq 'REFUSED' -and (Words 'Rebuild-ContentTables -Script x') -eq 'REFUSED' -and (Words 'Rebuild-ContentTables -Branch x') -eq 'REFUSED')
$rebuild = Text 'scripts/mods/Rebuild-OnBox.ps1'
# A pull request's data, never its code (Patrick's B on the #4835 card).
Yes '  a pull request by number and its full head commit' ((Words "Rebuild-ContentTables -Pull 4835 -Head $sha") -eq "-Pull|4835|-Head|$sha" -and
    (Words 'Rebuild-ContentTables -Pull 0') -eq 'REFUSED' -and (Words 'Rebuild-ContentTables -Head abc') -eq 'REFUSED' -and (Words 'Rebuild-ContentTables -Pull x') -eq 'REFUSED')
Yes '  it takes only the listed data files from the pull request, held to its head, and commits them for Run-OnBox.ps1' (
    $rebuild.Contains("`$DataFromPull = @('game/content/Thornswood-Content.esp', 'records/recipe-owners.json')") -and
    $rebuild.Contains("'checkout', `$Head, '--', `$p") -and $rebuild.Contains('if ($at -cne $Head)') -and $rebuild.Contains("'commit', '--quiet', '--allow-empty'") -and
    $rebuild.IndexOf("'commit', '--quiet'") -lt $rebuild.IndexOf("Run-OnBox.ps1')"))
Yes '  and no file of the list is a script' (@([regex]::Match($rebuild, '\$DataFromPull = @\(([^)]*)\)').Groups[1].Value -split ',' | Where-Object { $_ -match '\.(ps1|psm1|py|js|cmd|bat|exe|dll)''' }).Count -eq 0)
Yes '  it runs the chain by Run-OnBox.ps1, its words quoted so none is read as a parameter' ($rebuild.Contains("'scripts/mods/Rebuild-ContentTables.ps1' '-Data' '{data}' '-PluginsTxt' '{plugins}' -Server `$Server -Out `$Out"))
Yes '  and Run-OnBox.ps1 copies what came back into -Out as well as the checkout' ((Text 'scripts/mods/Run-OnBox.ps1').Contains('foreach ($into in @($repo, $Out | Where-Object { $_ }))'))
# The Ship verbs (Patrick's A, 30 Oct 2026: the box admin App mints the
# token a Ship from the feed signs with, and the whole Ship runs on the box).
Yes 'Ship-Dev is a dev Ship from the feed, its note as a title and detail lines' ((Words 'Ship-Dev -Title "Market stalls take your prices" -Detail "Claim a stall"') -eq '-Channel|dev|-Title|Market stalls take your prices|-Detail|Claim a stall' -and
    (Words 'Ship-Dev -Channel main -Title x -Detail y') -eq 'REFUSED' -and (Words 'Ship-Dev -Title x -Detail y -Root C:/x') -eq 'REFUSED' -and (Words 'Ship-Dev -Title x -Detail y -Package') -eq 'REFUSED')
Yes 'Ship-Main is held to a build and to -Channel main' ($verbs.verbs.'Ship-Main'.build -eq $true -and (Words 'Ship-Main -Title x -Detail y') -eq 'REFUSED' -and
    (Words "Ship-Main -Build $sha -Title x -Detail y -ModsOnly") -eq '-Channel|main|-Title|x|-Detail|y|-ModsOnly' -and (Words "Ship-Main -Build $sha -Title x -Detail y -MoveServer") -eq 'REFUSED')
$shipBox = Text 'scripts/release/Ship-OnBox.ps1'
Yes '  Ship-OnBox.ps1 runs Ship.ps1 from the feed, a dev one mods only, with the token in GH_TOKEN alone and gone after' (
    $shipBox.Contains("`$ship = @{ Notes = `$notes; FromFeed = `$true; NoPause = `$true }") -and $shipBox.Contains("if (`$Channel -eq 'dev') { `$ship['Channel'] = 'dev'; `$ship['ModsOnly'] = `$true }") -and
    $shipBox.Contains('$env:GH_TOKEN = $token') -and $shipBox.Contains('finally { Remove-Item -LiteralPath Env:\GH_TOKEN'))
Yes '  a main Ship goes from the branch main at the fetched origin/main' ($shipBox.Contains("checkout --quiet -B main refs/remotes/origin/main"))
$gt = Text 'scripts/vps/admin/ship-access.js'
Yes '  the token is the App''s, for the fork and Thornswood only, Actions write and Contents read and nothing more' (
    $gt.Contains("const REPOS = ['skymp', 'Thornswood'];") -and $gt.Contains("const PERMISSIONS = { actions: 'write', contents: 'read' };") -and $gt.Contains('{ repositories: REPOS, permissions: PERMISSIONS }'))
$ig = Text 'scripts/deploy/Install-Gate.ps1'
Yes 'Install-Gate pins the GitHub CLI by version and SHA-256 and refuses one that does not match' ($ig -match "\`$GhVersion = '\d+\.\d+\.\d+'" -and $ig -match "\`$GhSha = '[0-9A-F]{64}'" -and
    $ig.Contains('if (`$got -ne ''$GhSha'')') -and $ig.Contains('gh = `$gh;'))
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
    # A fixed word with no hyphen is the value of the fixed parameter before it,
    # so that one is a value in the script, never a switch (Publish-Server is
    # held to -Channel dev this way, #4987).
    $fixedWords = @($v.fixed | Where-Object { $_ })
    for ($k = 0; $k -lt $fixedWords.Count; $k++) {
        $w = [string]$fixedWords[$k]
        if ($w.StartsWith('-')) { Yes "$($p.Name) fixed $w`: the script takes it" ($takes -contains $w.TrimStart('-')); continue }
        $before = if ($k -gt 0) { ([string]$fixedWords[$k - 1]).TrimStart('-') } else { '' }
        Yes "$($p.Name) fixed value $w`: it follows a fixed parameter that takes a value" ($k -gt 0 -and ([string]$fixedWords[$k - 1]).StartsWith('-') -and $takes -contains $before -and -not $isSwitch[$before])
        Yes "$($p.Name) fixed value $w`: a caller cannot give that parameter again" ($null -eq $v.params.$before)
    }
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
# The pipe keeps other machines out with PIPE_REJECT_REMOTE_CLIENTS and
# denies nothing: a NETWORK deny also shut out thornswood-deploy, whose ssh
# key login is a network logon (30 Oct, the first ping through the gate).
Yes 'the pipe refuses other machines itself (PIPE_REJECT_REMOTE_CLIENTS), takes one connection at a time, and nothing else may take its name first' ($brokerCode -match 'RejectRemote = 0x8' -and $brokerCode -match 'FirstInstance \| Overlapped, RejectRemote, 1,')
Yes '  and its access list denies nothing, NETWORK above all' ($brokerCode -notmatch 'AccessControlType\]::Deny' -and $brokerCode -notmatch "'S-1-5-2'")
Yes '  and allows SYSTEM and the deploy account alone' (
    $brokerCode.Contains("SecurityIdentifier('S-1-5-18')") -and $brokerCode.Contains('[string]$Cfg.deploySid') -and
    @([regex]::Matches($brokerCode, 'AccessControlType\]::Allow')).Count -eq 2)
$pipeBlock = [regex]::Match($broker, "(?s)\`$GatePipeCode = @'.*?\nfunction New-GatePipe.*?\n\}\r?\n").Value
Yes '  and the pipe is made in one block a harness can run' ($pipeBlock.Length -gt 0)
if (-not $OnWindows) {
    Write-Host 'SKIP  the pipe under Windows PowerShell 5.1, which the broker runs under: this is not Windows'
} else {
    # Under 5.1, as the broker runs it: the pipe made for this account, a
    # line through it, its access list read back, and its name refused to a
    # second maker while the first holds it.
    $pipeProbe = Join-Path ([IO.Path]::GetTempPath()) ('tw-2841-pipe-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
    $pipeRun = @'
$name = 'tw-2841-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$server = New-GatePipe $name
try {
    $wait = $server.BeginWaitForConnection($null, $null)
    $client = New-Object IO.Pipes.NamedPipeClientStream('.', $name, [IO.Pipes.PipeDirection]::InOut)
    $client.Connect(5000)
    if (-not $wait.AsyncWaitHandle.WaitOne(5000)) { 'NO CONNECTION'; exit 1 }
    $server.EndWaitForConnection($wait)
    $w = New-Object IO.StreamWriter($client)
    $w.AutoFlush = $true
    $w.WriteLine('LINE x')
    'GOT ' + (New-Object IO.StreamReader($server)).ReadLine()
    $rules = @($server.GetAccessControl().GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))
    'DENY ' + @($rules | Where-Object { $_.AccessControlType -eq 'Deny' }).Count
    'ALLOW ' + ((@($rules | ForEach-Object { $_.IdentityReference.Value }) | Sort-Object -Unique) -join ',')
    $second = $null
    try { $second = New-GatePipe $name; 'SECOND MADE' } catch { 'SECOND REFUSED' } finally { if ($second) { $second.Dispose() } }
    $client.Dispose()
} finally { $server.Dispose() }
'@
    try {
        $head = "`$ErrorActionPreference = 'Stop'`r`n`$Cfg = @{ deploySid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }`r`n"
        [IO.File]::WriteAllText($pipeProbe, $head + $pipeBlock + $pipeRun)
        $said = @(& (Get-WindowsPowerShell) -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $pipeProbe 2>&1 | ForEach-Object { "$_" })
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $want = @('GOT LINE x', 'DENY 0', ('ALLOW ' + ((@('S-1-5-18', $me) | Sort-Object -Unique) -join ',')), 'SECOND REFUSED')
        Yes 'under Windows PowerShell 5.1 the pipe takes its account''s line, denies nothing, allows SYSTEM and that account, and holds its name' (($said -join ';') -eq ($want -join ';'))
        if (($said -join ';') -ne ($want -join ';')) { $said | Write-Host }
    } finally { Remove-Item -LiteralPath $pipeProbe -Force -ErrorAction SilentlyContinue }
}
Yes 'the broker puts the pinned GitHub CLI first on the verbs'' PATH' ($brokerCode.Contains("`$env:PATH = (Split-Path -Parent ([string]`$Cfg.gh)) + ';' + `$env:PATH"))
# Patrick's A, 30 Oct 2026: the verbs are main's own verbs.json, read from
# the checkout the broker has just fetched, so a merged verb needs no install.
# The line's shape is still checked before git is asked anything.
$shaped = $brokerCode.IndexOf('Split-ThornswoodGateLine $line')
$tested = $brokerCode.IndexOf('Test-ThornswoodGateRequest -Line $line')
Yes 'a line''s shape is checked before git is asked anything' ($shaped -gt 0 -and $shaped -lt $brokerCode.IndexOf('$commit = Update-Checkout'))
Yes 'every line goes through the rules after the fetch and before anything runs' ($tested -gt $brokerCode.IndexOf('$commit = Update-Checkout') -and $tested -lt $brokerCode.IndexOf('Invoke-Child ([string]$Cfg.pwsh)'))
Yes '  and the rules are main''s verbs.json in the fetched checkout, never anything sent or installed' ($brokerCode.Contains("`$verbsAt = Join-Path `$Repo 'scripts\vps\gate\verbs.json'") -and
    $brokerCode.Contains('Read-ThornswoodGateVerbs $verbsAt') -and -not $brokerCode.Contains("Read-ThornswoodGateVerbs (Join-Path `$Root 'verbs.json')"))
Yes '  and the installer no longer puts a verbs.json beside the broker, and takes an old one away' (
    (Text 'scripts/deploy/Install-Gate.ps1') -notmatch "\$Files = @\([^)]*verbs\.json" -and (Text 'scripts/deploy/Install-Gate.ps1').Contains('Remove-Item -LiteralPath (Join-Path `$root ''verbs.json'') -Force'))
Yes 'what runs is the tip of main: fetched into origin/main and checked out from it' (
    $brokerCode.Contains("'+refs/heads/main:refs/remotes/origin/main'") -and $brokerCode.Contains("'--detach', 'refs/remotes/origin/main'") -and $brokerCode.Contains("'clean', '-ffdxq'"))
Yes 'a live verb runs only when main is at the build it named, checked after the fetch' ($brokerCode.Contains('if ($req.Build -and $req.Build -cne $commit)') -and
    $brokerCode.IndexOf('if ($req.Build -and $req.Build -cne $commit)') -gt $brokerCode.IndexOf('$commit = Update-Checkout') -and
    $brokerCode.IndexOf('if ($req.Build -and $req.Build -cne $commit)') -lt $brokerCode.IndexOf('Invoke-Child ([string]$Cfg.pwsh)'))
Yes 'the script is the verb''s from verbs.json, under the checkout' ($brokerCode.Contains('Join-Path $Repo ($req.Script.Replace(''/'', ''\'')'))
Yes 'the program starts with no shell, and nothing on its input' ($brokerCode.Contains('$si.UseShellExecute = $false') -and $brokerCode.Contains('$p.StandardInput.Close()') -and $brokerCode -notmatch 'Invoke-Expression|\biex\b|cmd(\.exe)? /c')
Yes 'a run past its time is ended with everything it started' ($brokerCode.Contains('taskkill.exe" @(''/T'', ''/F'', ''/PID'''))
Yes 'git reads with the deploy key and pinned host keys only' ($brokerCode.Contains('-F none -i') -and $brokerCode.Contains('StrictHostKeyChecking=yes') -and $brokerCode.Contains('github_known_hosts'))
Yes 'every request is logged, refusals too' ($brokerCode.Contains("Log ('REFUSED [") -and $brokerCode.Contains("Log ('START ") -and $brokerCode.Contains("Log ('END "))

# ---- 6. the installer ----------------------------------------------------------
$inst = Text 'scripts/deploy/Install-Gate.ps1'
$du = [regex]::Match($inst, "(?m)^\`$DeployUser\s*=\s*'([^']+)'").Groups[1].Value
Yes "the account's name fits the 20 characters a local account may have (found '$du')" ($du.Length -ge 1 -and $du.Length -le 20)
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

# The box's host keys are fingerprinted in the script, never by ssh-keygen -l:
# on 29 Oct the box's OpenSSH refused its old DSA key file, and what it wrote
# to stderr stopped the install under 'Stop' in Windows PowerShell 5.1. The
# block runs here against a folder holding GitHub's published ed25519 host key
# (SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU), a DSA key and a file
# that is not a key.
Yes 'no ssh-keygen -l on the box' ($inst -notmatch 'keygen\s+-l')
Yes 'ssh-keygen''s stderr cannot stop the key making before the second way is tried' ([regex]::Match($inst, '(?s)function New-GateKey.*?\n\}').Value -match "ErrorActionPreference = 'Continue'")
$hostBlock = [regex]::Match($inst, "(?s)# ---- the box's own host keys.*?(?=\nif \(-not ``\`$lines\.Count\))").Value
Yes 'the host key block is found' ($hostBlock.Length -gt 0)
$keysDir = Join-Path ([IO.Path]::GetTempPath()) ('tw-2841-keys-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $keysDir 'ssh') -Force | Out-Null
try {
    [IO.File]::WriteAllText((Join-Path $keysDir 'ssh/ssh_host_ed25519_key.pub'), "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl root@box`n")
    [IO.File]::WriteAllText((Join-Path $keysDir 'ssh/ssh_host_dsa_key.pub'), "ssh-dss AAAAB3NzaC1kc3MAAACBAP1/U4EddRIpUt9KnC7s5Of2EbdSPO9EAMMeP4C2USZpRV1AIlH7WT2NWPq/xfW6MPbLm1Vs14E7gB00b/JmYLdrmVClpJ+f6AR7ECLCT7up1/63xhv4O1fnxqimFQ8E+4P208UewwI1VBNaFpEy9nXzrith1yrv8iIDGZ3RSAHHAAAAFQCXYFCPFSMLzLKSuYKi64QL8Fgc9QAAAIEA9+GghdabPd7LvKtcNrhXuXmUr7v6OuqC+VdMCz0HgmdRWVeOutRZT+ZxBxCBgLRJFnEj6EwoFhO3zwkyjMim4TwWeotUfI0o4KOuHiuzpnWRbqN/C/ohNWLx+2J6ASQ7zKTxvqhRkImog9/hWuWfBpKLZl6Ae1UlZAFMO/7PSSo= root@box`n")
    [IO.File]::WriteAllText((Join-Path $keysDir 'ssh/ssh_host_bad_key.pub'), "not a key`n")
    $run = $hostBlock.Replace('`$', '$').Replace('@($pinned)', "@('SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU')").Replace('$Address', '192.0.2.1') + "`n" + '$lines'
    $oldPd = $env:ProgramData; $env:ProgramData = $keysDir
    $ErrorActionPreference = 'Stop'
    $got = @(& ([scriptblock]::Create($run)))
    $env:ProgramData = $oldPd
    Yes "the pinned ed25519 key is found by its fingerprint, past a DSA key and a file that is not a key (got $($got.Count))" ($got.Count -eq 1 -and $got[0] -eq '192.0.2.1 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl')
}
catch { $env:ProgramData = $oldPd; Yes ('the host key block runs: ' + $_.Exception.Message) $false }
finally { Remove-Item -LiteralPath $keysDir -Recurse -Force -ErrorAction SilentlyContinue }

# The broker runs under Windows PowerShell 5.1 too: every short program whose
# stderr it reads goes through Invoke-Short, which holds 'Continue' for itself.
$bk = Text 'scripts/vps/gate/GateBroker.ps1'
$shortFn = [regex]::Match($bk, '(?s)function Invoke-Short.*?\n\}').Value
Yes 'the broker''s short programs run with stderr unable to stop it' ($shortFn -match "ErrorActionPreference = 'Continue'" -and @([regex]::Matches($bk, '2>&1')).Count -eq 1 -and $bk -notmatch '2>\$null')

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

# ---- 8. box-run.yml, in the ops repository (#4013) ---------------------------
Yes 'box-run.yml is not in this repository, which has no VPS runner once public' (-not (Test-Path -LiteralPath ([IO.Path]::Combine($Repo, '.github', 'workflows', 'box-run.yml'))))
$br = Text 'scripts/vps/Box-Run.ps1'
Yes '  Box-Run.ps1 starts it in the private ops repository, where the runners are registered' ($br.Contains("[string]`$GitHubRepo = 'EvilPatrick06/Thornswood-Ops'") -and $br.Contains("`$Workflow = 'box-run.yml'"))

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
