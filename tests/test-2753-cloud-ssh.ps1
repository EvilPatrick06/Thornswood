<#
  test-2753-cloud-ssh.ps1

      pwsh -NoProfile -File .\tests\test-2753-cloud-ssh.ps1
      powershell -NoProfile -File .\tests\test-2753-cloud-ssh.ps1

  The PowerShell half of ssh from cloud Claude threads (#2753):
  Install-Bridge.ps1 (the box's end, as a task), New-CloudAccess.ps1 (the
  cloud key and the bridge's token, made on One) and Setup-CloudSsh.ps1 (the
  cloud thread's end). tests\test-2753-box-bridge.js runs the bridge itself.

  WHAT IT HOLDS THEM TO.
    1. Each parses, and each script it sends to the box, built the way the
       script builds it with stand-in values, parses as PowerShell too, so a
       backtick in the wrong place fails here and not on the box.
    2. Install-Bridge.ps1: a commit or nothing (Artifact.ps1), the task as
       LOCAL SERVICE with a SID of its own after the fail-safe
       (ServiceAccount.ps1, #2578), priority 4 (#1968), the log through
       server-log.js kept 90 days (#2166), the folder taking nothing from C:\,
       and the old files and task back when the new one does not answer.
    3. New-CloudAccess.ps1: the token goes on standard input
       (Invoke-ThornswoodSecretRemote, #451) and is never printed, the key
       line carries from="127.0.0.1", and a run takes the old cloud line off
       by its comment and touches no other key.
    4. Setup-CloudSsh.ps1: ssh with StrictHostKeyChecking yes from the first
       connection, the box's key only through Add-ThornswoodKnownHost -Scanned
       (the pin), neither secret printed.
    5. Add-ThornswoodKnownHost -Scanned, against throwaway keys: a pinned line
       is written under the box's address, one that is not pinned is refused
       with nothing written, and ssh-keyscan is not asked.
    6. The Caddyfile carries /box/ to the port the bridge and its installer
       use, and Setup-Domain.ps1 refuses a Caddyfile without it.
  Nothing connects to anything and nothing leaves this machine.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function P([string[]]$parts) { return [IO.Path]::Combine([string[]](@($repo) + $parts)) }
function Text([string]$p) { return [IO.File]::ReadAllText($p) }
function ParseErrors([string]$code) {
    $e = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$e)
    return @($e)
}

$installPath = P 'scripts', 'deploy', 'Install-Bridge.ps1'
$accessPath  = P 'scripts', 'vps', 'New-CloudAccess.ps1'
$setupPath   = P 'scripts', 'vps', 'Setup-CloudSsh.ps1'
$install = Text $installPath
$access  = Text $accessPath
$setup   = Text $setupPath

# ---- 1. they parse --------------------------------------------------------
foreach ($p in $installPath, $accessPath, $setupPath) {
    $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$null, [ref]$e)
    Yes ((Split-Path -Leaf $p) + ' parses') (@($e).Count -eq 0)
}

# The here-strings each script sends, expanded with stand-in values the way
# the script expands them, then parsed.
function HereStrings([string]$path) {
    $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$e)
    return @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -and $n.StringConstantType -eq 'DoubleQuotedHereString' }, $true))
}
# A here-string as the script expands it: its text between @" and "@, with
# its backticks and variables, expanded here.
function Build($h) {
    $t = $h.Extent.Text
    $t = $t.Substring($t.IndexOf("`n") + 1)
    $t = $t.Substring(0, $t.LastIndexOf("`n"))
    return $ExecutionContext.InvokeCommand.ExpandString($t)
}

. (P 'scripts', 'deploy', 'ServiceAccount.ps1')
$Root = 'C:\Thornswood-Bridge'; $Port = 7790; $TaskName = 'Thornswood Bridge'; $Wait = 20; $AsSystem = $false
$log = 'C:\Thornswood-Bridge\bridge.log'; $stage = '.stage-20261020-000000'; $prev = '.prev-20261020-000000'
$want = "'bridge.js' = 'AA'; 'ws.js' = 'BB'; 'server-log.js' = 'CC'"
$hs = HereStrings $installPath
$stopAst = @($hs | Where-Object { $_.Extent.Text -match '^@"\r?\nfunction StopIt' })
Yes 'Install-Bridge.ps1 has one StopIt it sends' ($stopAst.Count -eq 1)
$stopIt = Build $stopAst[0]
$bad = @()
foreach ($h in $hs) {
    try { $code = Build $h } catch { $bad += ('line ' + $h.Extent.StartLineNumber + ' does not build: ' + $_.Exception.Message); continue }
    $errs = @(ParseErrors $code)
    if ($errs.Count) { $bad += ('line ' + $h.Extent.StartLineNumber + ': ' + $errs[0].Message) }
}
Yes ('every script Install-Bridge.ps1 sends parses once built (' + $hs.Count + ')' + $(if ($bad.Count) { ': ' + ($bad -join '; ') })) ($hs.Count -ge 5 -and $bad.Count -eq 0)

$installCode = Build (@($hs | Where-Object { $_.Extent.Text -match 'BRIDGE OK' })[0])

# New-CloudAccess.ps1: its key file function, defined from its own text.
$e = $null
$aast = [System.Management.Automation.Language.Parser]::ParseFile($accessPath, [ref]$null, [ref]$e)
$fn = @($aast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-KeyFileScript' }, $true))
Yes 'New-CloudAccess.ps1 builds the key file script in one function' ($fn.Count -eq 1)
$comment = 'thornswood-cloud'; $BridgeRoot = 'C:\Thornswood-Bridge'; $NewLine = 'from="127.0.0.1" ssh-ed25519 AAAA thornswood-cloud'
Invoke-Expression $fn[0].Extent.Text
$pub = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGRZxJ2G1nGDrjqLMTed+Bui13icdTMAODXpx0ZQd55T thornswood-cloud'
$keyScript = Get-KeyFileScript ('from="127.0.0.1" ' + $pub)
$bad = @()
foreach ($h in (HereStrings $accessPath)) {
    try { $code = Build $h } catch { $bad += ('line ' + $h.Extent.StartLineNumber + ' does not build: ' + $_.Exception.Message); continue }
    $errs = @(ParseErrors $code)
    if ($errs.Count) { $bad += ('line ' + $h.Extent.StartLineNumber + ': ' + $errs[0].Message) }
}
Yes ('every script New-CloudAccess.ps1 sends parses once built' + $(if ($bad.Count) { ': ' + ($bad -join '; ') })) ($bad.Count -eq 0)

# ---- 2. Install-Bridge.ps1 ------------------------------------------------
Yes 'Install-Bridge.ps1 builds an artifact from the commit and checks it before sending' (
    $install -match 'New-ThornswoodArtifact -Component bridge' -and $install -match 'Assert-ThornswoodSourceIntegrity' -and
    $install -match "'scripts/vps/bridge/bridge.js', 'scripts/vps/bridge/ws.js'" -and $install -match "-AlsoSends 'scripts/vps/Server-Log.js'")
Yes '  and records what the box runs only once it answers' ($install.IndexOf('Set-ThornswoodArtifactCurrent') -gt $install.IndexOf("-notcontains 'BRIDGE OK'"))
Yes 'the task is LOCAL SERVICE with its own SID, granted its folder, after the fail-safe' (
    $installCode -match 'New-ThornswoodServicePrincipal -AsSystem:\$system' -and $installCode -match 'Get-ThornswoodTaskSid' -and
    $installCode -match 'Grant-ThornswoodServiceFolder' -and
    $installCode.IndexOf('Test-ThornswoodServiceCannotReach (') -ge 0 -and $installCode.IndexOf('Test-ThornswoodServiceCannotReach (') -lt $installCode.IndexOf('if (-not (StopIt))'))
Yes '  at priority 4, normal (#1968)' ($installCode -match 'New-ScheduledTaskSettingsSet [^\r\n]*-Priority 4\b')
Yes '  and runs the bridge under server-log.js, kept 90 days with a time on each line (#2166)' ($installCode -match '--log "\{1\}" --days 90 --stamp bridge\.js')
Yes '  on the port the Caddyfile hands /box/ to' ($installCode -match 'THORNSWOOD_BRIDGE_PORT=7790&&')
Yes 'the folder takes nothing from C:\ and no broad group keeps a rule on it' (
    $install -match 'SetAccessRuleProtection\(`\$true, `\$false\)' -and $install -match "'S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-19'")
Yes 'the stage is checked by hash and node --check before the bridge is stopped' (
    $installCode.IndexOf('did not arrive as it was sent') -lt $installCode.IndexOf('if (-not (StopIt))') -and
    $installCode.IndexOf('--check') -lt $installCode.IndexOf('if (-not (StopIt))'))
Yes 'a bridge that does not answer gets the old files and the old task back' ($installCode -match 'Register-ScheduledTask -TaskName .Thornswood Bridge. -Xml \$oldXml' -and $installCode -match "BRIDGE ROLLED BACK")
Yes 'StopIt stops only what names bridge.log, and the child it started' ($stopIt -match [regex]::Escape("like ('*' + 'C:\Thornswood-Bridge\bridge.log' + '*')") -and $stopIt -match 'ParentProcessId -eq')
Yes 'the status says whether a token is there, never what it is' ($install -match "token     there" -and $install -notmatch 'Get-Content[^\r\n]*token\.txt')

# ---- 3. New-CloudAccess.ps1 ----------------------------------------------
Yes 'the token goes on standard input, never on a command line (#451)' ($access -match 'Invoke-ThornswoodSecretRemote -Target \$target -SshArgs \$ssh -Secret \$token' -and $access -match '`\$tok = `\$ThornswoodSecret; `\$ThornswoodSecret = `\$null')
Yes '  and is never printed' (-not ($access -match '(?m)^\s*(Say|Write-Host)[^\r\n]*\$token') -and -not ($access -match '(?m)^\s*(Say|Write-Host)[^\r\n]*\$keyB64'))
Yes 'the cloud key line is taken only from 127.0.0.1' ($keyScript.Contains("`$new = 'from=""127.0.0.1"" " + $pub + "'"))
Yes 'a run takes off only lines ending in the cloud comment' ($keyScript.Contains("Where-Object { `$_.Trim() -notmatch ' thornswood-cloud$' }"))
# The key file edit, run here on a scratch copy.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-2753-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $kf = Join-Path $tmp 'administrators_authorized_keys'
    [IO.File]::WriteAllLines($kf, [string[]]@('ssh-ed25519 AAAAone patrick', 'from="127.0.0.1" ssh-ed25519 AAAAold thornswood-cloud', 'ssh-rsa AAAAtwo djinn'))
    $run = $keyScript.Replace('C:\ProgramData\ssh\administrators_authorized_keys', $kf) -replace '(?m)^icacls .*$', ''
    $said = & ([scriptblock]::Create($run))
    $after = @([IO.File]::ReadAllLines($kf))
    Yes 'run on a scratch key file: the old cloud line goes, the new one comes, the others stay' (
        $after.Count -eq 3 -and $after[0] -eq 'ssh-ed25519 AAAAone patrick' -and $after[1] -eq 'ssh-rsa AAAAtwo djinn' -and
        $after[2] -eq ('from="127.0.0.1" ' + $pub) -and "$said" -match 'taken off: 1')
    $remove = (Get-KeyFileScript '').Replace('C:\ProgramData\ssh\administrators_authorized_keys', $kf) -replace '(?m)^icacls .*$', ''
    $null = & ([scriptblock]::Create($remove))
    $after = @([IO.File]::ReadAllLines($kf))
    Yes '  and -Remove leaves every other key' ($after.Count -eq 2 -and ($after -join '|') -eq 'ssh-ed25519 AAAAone patrick|ssh-rsa AAAAtwo djinn')
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
Yes 'it proves the way in before it writes the file for the cloud environment' ($access.IndexOf("'echo THORNSWOOD_OK'") -lt $access.IndexOf('WriteAllText($Out, ("THORNSWOOD_BOX_KEY_B64'))
Yes '  and the copy of the private key it made in is deleted however it ends' ($access -match '(?s)finally \{\s*Remove-Item -LiteralPath \$work -Recurse -Force')

# ---- 4. Setup-CloudSsh.ps1 -----------------------------------------------
Yes 'Setup-CloudSsh.ps1 writes StrictHostKeyChecking yes into the Host block' ($setup -match "'    StrictHostKeyChecking yes'")
Yes '  never turns checking down' ($setup -notmatch '(?i)StrictHostKeyChecking\s*[= ]\s*"?(no|off|accept-new|ask)\b')
Yes '  writes known_hosts only through the pin' ($setup -match 'Add-ThornswoodKnownHost -Address \$VpsHost -Scanned \$lines' -and $setup -notmatch 'Add-Content[^\r\n]*known_hosts')
Yes '  asks ssh-keyscan through listen.js, never the box''s own port' ($setup -match "listen\.js" -and $setup -match 'ssh-keyscan -T 20 -p \$port 127\.0\.0\.1')
Yes '  and prints neither secret' (-not ($setup -match '(?m)^\s*(Say|Write-Host)[^\r\n]*\$(keyB64|keyText|env:THORNSWOOD_BOX_TOKEN\b[^)])'))

# ---- 5. Add-ThornswoodKnownHost -Scanned ----------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-2753-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    . (P 'scripts', 'vps', 'Vps.ps1')
    $keys = @{}
    foreach ($k in 'box', 'impostor') {
        $kp = Join-Path $tmp $k
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        foreach ($empty in '""', '') {
            & ssh-keygen -q -t ed25519 -N $empty -C $k -f $kp 2>&1 | Out-Null
            if (Test-Path -LiteralPath "$kp.pub") { break }
        }
        $ErrorActionPreference = $old
        $pk = ([IO.File]::ReadAllText("$kp.pub")).Trim() -split '\s+'
        $keys[$k] = '203.0.113.9 ' + $pk[0] + ' ' + $pk[1]
    }
    $boxFp = Get-ThornswoodSshFingerprint $keys['box']
    $global:ThornswoodScanAsked = $false
    function global:ssh-keyscan { $global:ThornswoodScanAsked = $true }
    $kh = Join-Path $tmp 'known_hosts'
    $threw = $false
    try { [void](Add-ThornswoodKnownHost -Address '203.0.113.9' -KnownHosts $kh -Pinned @($boxFp) -Scanned @($keys['impostor'])) } catch { $threw = $true }
    Yes 'a scanned line that is not pinned is refused, nothing written' ($threw -and -not (Test-Path -LiteralPath $kh))
    $n = Add-ThornswoodKnownHost -Address '203.0.113.9' -KnownHosts $kh -Pinned @($boxFp) -Scanned @($keys['impostor'], $keys['box'])
    $held = [IO.File]::ReadAllText($kh)
    Yes '  and the pinned one is written, the other left out' ($n -eq 1 -and $held.Contains($keys['box']) -and -not $held.Contains($keys['impostor']))
    Yes '  and ssh-keyscan was never asked' (-not $global:ThornswoodScanAsked)
    Yes 'the known_hosts path is one folder at a time, so it is right on Linux too' ((Get-ThornswoodKnownHostsPath) -eq (Join-Path (Join-Path $HOME '.ssh') 'known_hosts'))
}
finally {
    Remove-Item -Path function:global:ssh-keyscan -ErrorAction SilentlyContinue
    Remove-Variable -Name ThornswoodScanAsked -Scope Global -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 6. the door ----------------------------------------------------------
$caddy = Text (P 'scripts', 'deploy', 'Caddyfile')
$bridgeJs = Text (P 'scripts', 'vps', 'bridge', 'bridge.js')
Yes 'the Caddyfile hands /box/ to 127.0.0.1:7790' ($caddy -match '(?s)handle_path /box/\* \{\s*reverse_proxy 127\.0\.0\.1:7790\s*\}')
Yes '  the port bridge.js takes when none is given' ($bridgeJs -match 'THORNSWOOD_BRIDGE_PORT\) \|\| 7790')
Yes '  and Install-Bridge.ps1 installs it on' ($install -match '\[int\]\$Port\s+= 7790')
Yes 'Setup-Domain.ps1 refuses a Caddyfile without the /box/ block' ((Text (P 'scripts', 'deploy', 'Setup-Domain.ps1')) -match "'handle_path /box/\*'")

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
