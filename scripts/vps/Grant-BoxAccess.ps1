<#
  Grant-BoxAccess.ps1

  Gives one person, or one machine, its own way into the box, or takes it
  away, and touches nobody else's (#2891). Everybody reaches the box's ssh
  through the bridge (wss://thornswood.net/box/, #2753), each with a key and
  a token of their own, so port 22 needs no outside address and a home
  address that changes stops nothing. Run it on a machine whose own way in
  already works (One).

      .\scripts\vps\Grant-BoxAccess.ps1 -Name djinn -FromClipboard
      .\scripts\vps\Grant-BoxAccess.ps1 -Name djinn -PublicKey 'ssh-ed25519 AAAA... thornswood'
                       a person: their PC's public key line (Setup-SshKey.ps1
                       prints it), and a token made here for them
      .\scripts\vps\Grant-BoxAccess.ps1 -Name one -ThisMachine
                       this machine: its own key and a token, and this
                       machine's ssh pointed through the bridge
      .\scripts\vps\Grant-BoxAccess.ps1 -Name cloud -MakeKey
                       cloud Claude threads: a key made here, and both halves
                       into one file for the cloud environment
      .\scripts\vps\Grant-BoxAccess.ps1 -Name djinn -Remove
                       take that one name's key and token off the box
      .\scripts\vps\Grant-BoxAccess.ps1 -List
                       who has a way in, read only

  A second grant for a name replaces that name's key and token, so the old
  pair stops working.

  THE TWO HALVES, and why neither is any use alone:
    the key     the public half goes on the box as
                    from="127.0.0.1" <type> <key> thornswood-<name>
                so sshd takes it only from the box itself, which means only
                through the bridge. A line holding the same key under
                another comment is taken off, so a key is never on the box
                twice with different rules. A person's private half never
                leaves their own PC.
    the token   what bridge.js asks for before it opens a WebSocket at all.
                The box holds only its SHA-256, in tokens\<name> in the
                bridge's folder, so nothing read off the box opens the
                bridge, and the token itself never leaves this machine except
                to its holder. bridge.js reads the folder at every
                connection, so a grant counts and a removal refuses at once.

  NOT LOCKING ANYBODY OUT. Before it changes anything the box saves the key
  file and the token folder and arms a task that puts them back in ten
  minutes ("Thornswood box access put back"). Then a NEW login from this
  machine has to get in, and only then is the task cancelled. A change that
  would cut this machine off is undone by the box itself. -ThisMachine also
  puts this machine's ssh config back as it was when its proof fails.

  WHERE THE TOKEN GOES, readable by the account running this only:
    a person     <OutDir>\<name>\box-token.txt. Send it to them alone (a Discord
                 DM), and delete the file. They paste it when Setup-SshKey.ps1
                 asks. Without their private key it opens nothing but sshd's
                 login.
    this machine .ssh\thornswood-box-token, where connect.js reads it.
    cloud        <OutDir>\cloud-access.txt with two lines,
                 THORNSWOOD_BOX_KEY_B64=... and THORNSWOOD_BOX_TOKEN=..., for
                 the cloud environment's variables (Project settings, Cloud
                 environment). Then delete the file. A cloud thread runs
                 scripts/vps/Setup-CloudSsh.ps1.
  No token or private key is printed by anything here.
#>
[CmdletBinding()]
param(
    [string]$Name = '',
    [string]$PublicKey = '',
    [switch]$FromClipboard,
    [switch]$ThisMachine,
    [switch]$MakeKey,
    [switch]$Remove,
    [switch]$List,
    # -ThisMachine: this machine's key, the one Setup-SshKey.ps1 makes.
    [string]$KeyPath = '',
    [string]$OutDir = 'C:\ThornswoodTemps&Worktrees\temp\box-access',
    [string]$BridgeRoot = 'C:\Thornswood-Bridge',
    # Where -MakeKey's proof connects, the same address connect.js uses.
    [string]$BoxUrl = 'wss://thornswood.net/box/',
    [string]$VpsHost = '',
    [string]$VpsUser = '',
    [switch]$NoPause
)

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Vps.ps1')
. (Join-Path $Here 'Send-Script.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
if (-not $KeyPath) { $KeyPath = Join-Path (Join-Path $HOME '.ssh') 'thornswood_ed25519' }
$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Done([int]$code) { Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit $code }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Done 1 }

$target = "$VpsUser@$VpsHost"
$ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
$PutBack = 'Thornswood box access put back'
$BridgeDir = Join-Path $Here 'bridge'

# ------------------------------------------------------------- the line ----
# A public key line however it was copied: on its own, inside a Discord
# message with words around it, in a code block, or split over two lines by
# a narrow window. Returns "type key" with no comment (the box's line gets
# thornswood-<name>), or '' when there is none.
function Find-PublicKeyLine([string]$Text) {
    $pattern = '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ([A-Za-z0-9+/=]+)( .*)?$'
    # A whole key decodes as base64; an ed25519 one is always 68 characters.
    # A line cut by a console at its window width is neither.
    function Test-Body([string]$type, [string]$body) {
        if ($type -eq 'ssh-ed25519' -and $body.Length -ne 68) { return $false }
        try { [void][Convert]::FromBase64String($body); return $true } catch { return $false }
    }
    $lines = @($Text -replace '`', ' ' -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256)\b') { continue }
        if ($lines[$i] -match $pattern -and (Test-Body $Matches[1] $Matches[2])) { return ($Matches[1] + ' ' + $Matches[2]) }
        # Wrapped: the type word, then the key cut into pieces over the next
        # line or two, then the comment. The pieces are glued back together
        # until they make a whole key.
        $last = [Math]::Min($i + 3, $lines.Count - 1)
        $words = @((($lines[$i..$last]) -join ' ') -split '\s+' | Where-Object { $_ })
        $type = $words[0]; $body = ''; $k = 1
        while ($k -lt $words.Count -and $words[$k] -match '^[A-Za-z0-9+/=]+$') {
            $body += $words[$k]; $k++
            if (Test-Body $type $body) { break }
        }
        if (Test-Body $type $body) { return ($type + ' ' + $body) }
    }
    return ''
}

# ------------------------------------------------------- on the box -------
# The change, as one script. It saves what is there and arms the put back
# before it changes anything, and says ARMED, then CHANGED lines, then DONE.
# $Digest and $KeyLine both '' take the name away.
function Get-BoxChangeScript([string]$Who, [string]$Digest, [string]$KeyLine, [string]$Blob) {
    return @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$keys = 'C:\ProgramData\ssh\administrators_authorized_keys'
`$tokens = '$BridgeRoot\tokens'
`$save = 'C:\ProgramData\ssh\box-access-before'
`$task = '$PutBack'
if (-not (Test-Path -LiteralPath '$BridgeRoot\bridge.js')) { 'STOP there is no bridge in $BridgeRoot. Run scripts\deploy\Install-Bridge.ps1 first. Nothing was changed.'; exit 1 }
if (Get-ScheduledTask -TaskName `$task -EA SilentlyContinue) { 'STOP the put back from an earlier run is still armed, so that run is not finished: it puts its key file and tokens back within ten minutes of when it started. Run this again after that. Nothing was changed.'; exit 1 }

# What is there now, for the put back. The folder is under ProgramData\ssh,
# which only Administrators and SYSTEM can read.
if (Test-Path -LiteralPath `$save) { Remove-Item -LiteralPath `$save -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path `$save 'tokens') -Force | Out-Null
if (Test-Path -LiteralPath `$keys) { Copy-Item -LiteralPath `$keys -Destination (Join-Path `$save 'keys') }
if (Test-Path -LiteralPath `$tokens) { Get-ChildItem -LiteralPath `$tokens -File | Copy-Item -Destination (Join-Path `$save 'tokens') }
`$back = @'
`$keys = 'C:\ProgramData\ssh\administrators_authorized_keys'
`$tokens = '$BridgeRoot\tokens'
`$save = 'C:\ProgramData\ssh\box-access-before'
if (Test-Path -LiteralPath (Join-Path `$save 'keys')) { Copy-Item -LiteralPath (Join-Path `$save 'keys') -Destination `$keys -Force }
else { Remove-Item -LiteralPath `$keys -Force -EA SilentlyContinue }
if (Test-Path -LiteralPath `$keys) { icacls `$keys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null }
if (-not (Test-Path -LiteralPath `$tokens)) { New-Item -ItemType Directory -Path `$tokens -Force | Out-Null }
Get-ChildItem -LiteralPath `$tokens -File | Remove-Item -Force
Get-ChildItem -LiteralPath (Join-Path `$save 'tokens') -File | Copy-Item -Destination `$tokens
Unregister-ScheduledTask -TaskName '$PutBack' -Confirm:`$false
'@
[IO.File]::WriteAllText((Join-Path `$save 'put-back.ps1'), `$back, (New-Object Text.UTF8Encoding(`$true)))
`$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path `$save 'put-back.ps1') + '"')
`$t = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(10))
`$p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName `$task -Action `$a -Trigger `$t -Principal `$p -Force | Out-Null
'ARMED the box puts the key file and tokens back by itself in ten minutes, unless a new login proves the change'

# The key: every line for this name, or holding this key under another
# comment, goes; the new one comes.
`$who = '$Who'
`$blob = '$Blob'
`$line = '$($KeyLine.Replace("'", "''"))'
`$have = @()
if (Test-Path -LiteralPath `$keys) { `$have = @(Get-Content -LiteralPath `$keys | Where-Object { `$_.Trim() }) }
`$after = @(`$have | Where-Object { `$l = ' ' + `$_.Trim() + ' '; -not (`$l.EndsWith(' thornswood-' + `$who + ' ') -or (`$blob -and `$l.Contains(' ' + `$blob + ' '))) })
`$gone = `$have.Count - `$after.Count
if (`$line) { `$after += `$line }
# No byte order mark: sshd silently ignores a file it cannot parse.
[IO.File]::WriteAllLines(`$keys, [string[]]`$after, (New-Object Text.UTF8Encoding(`$false)))
icacls `$keys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null

# The token's digest, in the bridge's folder, whose rules it takes.
if (-not (Test-Path -LiteralPath `$tokens)) { New-Item -ItemType Directory -Path `$tokens -Force | Out-Null }
`$tf = Join-Path `$tokens `$who
`$digest = '$Digest'
if (`$digest) { [IO.File]::WriteAllText(`$tf, `$digest, (New-Object Text.UTF8Encoding(`$false))) }
else { Remove-Item -LiteralPath `$tf -Force -EA SilentlyContinue }
'CHANGED ' + `$who + ': ' + `$gone + ' key line(s) taken off' + `$(if (`$line) { ', its key put on, only through the bridge' } else { '' }) + `$(if (`$digest) { ', its token written' } else { ', its token taken off' })
'CHANGED now ' + `$after.Count + ' key line(s), and tokens for: ' + ((@(Get-ChildItem -LiteralPath `$tokens -File | ForEach-Object { `$_.Name }) -join ', '))
'DONE'
"@
}

# Once a new login has got in: the put back is cancelled and its copy goes.
function Get-BoxKeepScript {
    return @"
Unregister-ScheduledTask -TaskName '$PutBack' -Confirm:`$false -EA SilentlyContinue
if (Get-ScheduledTask -TaskName '$PutBack' -EA SilentlyContinue) { 'PUT BACK STILL ARMED' }
else { Remove-Item -LiteralPath 'C:\ProgramData\ssh\box-access-before' -Recurse -Force -EA SilentlyContinue; 'KEPT' }
"@
}

# Read only: every key line and every token name.
function Get-BoxListScript {
    return @"
`$ErrorActionPreference = 'SilentlyContinue'
`$keys = 'C:\ProgramData\ssh\administrators_authorized_keys'
if (Test-Path -LiteralPath `$keys) { Get-Content -LiteralPath `$keys | Where-Object { `$_.Trim() } | ForEach-Object { 'KEY ' + `$_.Trim() } }
Get-ChildItem -LiteralPath '$BridgeRoot\tokens' -File | ForEach-Object { 'TOKEN ' + `$_.Name + ' ' + `$_.LastWriteTime.ToString('yyyy-MM-dd HH:mm') }
if (Get-ScheduledTask -TaskName '$PutBack') { 'ARMED' }
'LISTED'
"@
}

function Clean($lines) {
    @($lines | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch 'post-quantum|store now, decrypt later|openssh\.com/pq\.html' })
}

# A new connection from this machine, the way every script here makes one.
function Test-Login {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = @(Invoke-ThornswoodNative { & ssh @ssh -o ConnectTimeout=20 $target 'echo THORNSWOOD_OK' } 2>&1 | ForEach-Object { "$_" })
    $ErrorActionPreference = $old
    return [pscustomobject]@{ Ok = (($out -join '') -match 'THORNSWOOD_OK'); Out = $out }
}

foreach ($t in 'ssh', 'ssh-keygen') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client." }
}
$ways = @(@($PublicKey -or $FromClipboard, $ThisMachine, $MakeKey, $Remove, $List) | Where-Object { $_ }).Count
if ($ways -ne 1) { Die 'Pass one of: -PublicKey (or -FromClipboard), -ThisMachine, -MakeKey, -Remove, -List. Nothing was changed.' }

Write-Host ''
Write-Host '  THORNSWOOD  -  who may reach the box' -ForegroundColor White
Say "  $target, through $BoxUrl" 'DarkGray'

# ------------------------------------------------------------------ list ----
if ($List) {
    Head 'On the box'
    $said = Clean (Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script (Get-BoxListScript))
    if ($said -notcontains 'LISTED') { $said | ForEach-Object { Say "  $_" 'DarkGray' }; Die 'the box did not answer the list. The lines above say why.' }
    foreach ($l in @($said | Where-Object { $_ -like 'KEY *' })) {
        $k = $l.Substring(4)
        $who = if ($k -match ' thornswood-([a-z0-9][a-z0-9-]*)$') { $Matches[1] } else { '(no thornswood- name)' }
        $bare = $k -replace '^from="[^"]*"\s+', ''
        $fp = Get-ThornswoodSshFingerprint ('x ' + $bare)
        $how = if ($k -match '^from="127\.0\.0\.1"\s') { 'only through the bridge' } else { 'from any address that reaches port 22' }
        Say ('  key    {0,-22} {1}  {2}' -f $who, $fp, $how) $(if ($how -like 'only*') { 'Green' } else { 'Yellow' })
    }
    foreach ($l in @($said | Where-Object { $_ -like 'TOKEN *' })) {
        $bits = $l.Substring(6) -split ' ', 2
        Say ('  token  {0,-22} since {1}' -f $bits[0], $bits[1]) 'Green'
    }
    if ($said -contains 'ARMED') { Say "  the put back task is armed, so a run is unfinished or failed its proof" 'Yellow' }
    Done 0
}

# ------------------------------------------------------------- the name ----
if ($Name -notmatch '^[a-z0-9][a-z0-9-]{0,31}$') { Die 'The name is one word, lower case letters, digits and hyphens, the way the bridge logs it: djinn, one, cloud. Nothing was changed.' }
if ($MakeKey -and $Name -ne 'cloud') { Say "  -MakeKey makes a key here, for the cloud environment; it is named $Name." 'Yellow' }

$node = Get-Command node -ErrorAction SilentlyContinue
if (($ThisMachine -or $MakeKey) -and -not $node) { Die 'node is not on PATH, and the bridge client is node. Nothing was changed.' }

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-access-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$tokenPath = Get-ThornswoodBridgeTokenPath
$hadToken = $null
$cfgBefore = $null
try {
    # -------------------------------------------------------------- key ----
    $keyLine = ''
    $newKey = ''
    $bare = ''
    if ($Remove) {
        Head "Taking $Name's way in away"
    } else {
        Head "$Name's key"
        if ($FromClipboard) { $PublicKey = [string](Get-Clipboard -Raw) }
        if ($ThisMachine) {
            if (-not (Test-Path -LiteralPath "$KeyPath.pub")) { Die "this machine has no key at $KeyPath. Run .\scripts\vps\Setup-SshKey.ps1 first; it makes one. Nothing was changed." }
            $PublicKey = [IO.File]::ReadAllText("$KeyPath.pub")
        }
        if ($MakeKey) {
            # An empty passphrase through PowerShell: '""' in some versions and ''
            # in others (Setup-SshKey.ps1 says why), so both are tried and proved.
            $newKey = Join-Path $work 'cloud_ed25519'
            $made = $false
            foreach ($empty in '""', '') {
                Remove-Item -LiteralPath $newKey, "$newKey.pub" -Force -ErrorAction SilentlyContinue
                $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                Invoke-ThornswoodNative { & ssh-keygen -q -t ed25519 -N $empty -C "thornswood-$Name" -f $newKey } 2>&1 | Out-Null
                if (Test-Path -LiteralPath "$newKey.pub") {
                    $null = Invoke-ThornswoodNative { & ssh-keygen -y -P '' -f $newKey } 2>&1
                    if ($LASTEXITCODE -eq 0) { $made = $true }
                }
                $ErrorActionPreference = $old
                if ($made) { break }
            }
            if (-not $made) { Die 'could not make a key without a passphrase. Nothing was put on the box.' }
            $PublicKey = [IO.File]::ReadAllText("$newKey.pub")
        }
        if ($PublicKey -match 'PRIVATE KEY') { Die 'That is a private key. It never leaves the PC it was made on; ask for the line Setup-SshKey.ps1 prints instead. Nothing was changed.' }
        $bare = Find-PublicKeyLine $PublicKey
        if (-not $bare) {
            Die 'No public key line in what was given. It starts with ssh-ed25519 or ssh-rsa, then a long run of letters and digits; Setup-SshKey.ps1 prints it on the PC it was made on. Nothing was changed.'
        }
        $keyLine = 'from="127.0.0.1" ' + $bare + ' thornswood-' + $Name
        Say ('  ' + (Get-ThornswoodSshFingerprint ('x ' + $bare)) + ', taken only through the bridge') 'Green'
    }
    $blob = if ($bare) { ($bare -split ' ')[1] } else { '' }
    $token = ''
    $digest = ''
    if (-not $Remove) {
        $token = New-ThornswoodBridgeToken
        $digest = Get-ThornswoodBridgeDigest $token
    }

    # This machine's ssh config is checked before the box is touched, so a
    # Host entry in the way stops it with nothing changed anywhere.
    if ($ThisMachine) {
        try { $null = Set-ThornswoodBridgeSsh -Address $VpsHost -User $VpsUser -KeyPath $KeyPath -Node $node.Source -Connect 'x' -CheckOnly }
        catch { Die $_.Exception.Message }
    }

    # ---------------------------------------------------------- the box ----
    Head 'On the box'
    $said = Clean (Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script (Get-BoxChangeScript $Name $digest $keyLine $blob))
    foreach ($l in $said) { Say "  $l" $(if ($l -like 'STOP*') { 'Red' } elseif ($l -like 'CHANGED*') { 'Green' } else { 'Gray' }) }
    if ($said -notcontains 'DONE') {
        if (@($said | Where-Object { $_ -like 'ARMED*' }).Count) { Die "the box did not finish. It puts the key file and tokens back by itself within ten minutes (the task '$PutBack')." }
        Die 'the box changed nothing. The lines above say why.'
    }

    # ------------------------------------------------------ this machine ---
    if ($ThisMachine) {
        Head 'This machine'
        if (Test-Path -LiteralPath $tokenPath) { $hadToken = [IO.File]::ReadAllText($tokenPath) }
        Write-ThornswoodPrivateFile -Path $tokenPath -Text $token
        Say "  the token is in $tokenPath, readable by this account only" 'Green'
        $client = Install-ThornswoodBridgeClient $BridgeDir
        $cfgBefore = Set-ThornswoodBridgeSsh -Address $VpsHost -User $VpsUser -KeyPath $KeyPath -Node $node.Source -Connect (Join-Path $client 'connect.js')
        Say "  ssh to $VpsHost now goes through the bridge (.ssh\config, the client in $client)" 'Green'
        try { $n = Add-ThornswoodKnownHostThroughBridge -Address $VpsHost -Node $node.Source -Listen (Join-Path $client 'listen.js') }
        catch { $n = -1; Say ('  ' + $_.Exception.Message) 'Red' }
        if ($n -gt 0) { Say "  added $n pinned host key line(s) to known_hosts" 'Green' }
    }

    # ------------------------------------------------------------ proof ----
    Head 'A new login from this machine'
    $w = Test-Login
    if (-not $w.Ok) {
        $w.Out | Select-Object -Last 5 | ForEach-Object { Say "  $_" 'DarkGray' }
        if ($ThisMachine) {
            [IO.File]::WriteAllText((Join-Path (Join-Path $HOME '.ssh') 'config'), $cfgBefore, (New-Object Text.UTF8Encoding($false)))
            if ($null -ne $hadToken) { Write-ThornswoodPrivateFile -Path $tokenPath -Text $hadToken } else { Remove-Item -LiteralPath $tokenPath -Force -ErrorAction SilentlyContinue }
            Say '  this machine''s ssh config and token file are back as they were' 'Yellow'
        }
        Die ("it does not get in, so the change is not kept: the box puts the key file and tokens back by itself within ten minutes (the task '$PutBack'), and ssh from here works again after that. " +
             'A "box bridge:" line is the bridge, Caddy or the token; "Permission denied" is the key.')
    }
    Say '  it gets in' 'Green'
    $kept = Clean (Invoke-ThornswoodRemote -Target $target -SshArgs $ssh -Script (Get-BoxKeepScript))
    if ($kept -notcontains 'KEPT') { Die "could not cancel the put back ('$PutBack'), so the box puts the old key file and tokens back within ten minutes. Run this again after that." }
    Say '  the put back is cancelled, so the change stays' 'Green'

    # -------------------------------------------------------- the holder ---
    if ($Remove) {
        Say "  $Name has no way in now. Everybody else's is as it was." 'Green'
    } elseif ($ThisMachine) {
        Say "  This machine reaches the box through the bridge with its own key and token, named $Name." 'Green'
    } elseif ($MakeKey) {
        Head 'Proving the new key through the bridge'
        # The way a cloud thread goes: connect.js as the ProxyCommand with the
        # token in its environment, the new key, and the box's host key checked
        # as every script checks it. The token is in this process's environment
        # for the length of the call and on no command line.
        $env:THORNSWOOD_BOX_TOKEN = $token
        $env:THORNSWOOD_BOX_URL = $BoxUrl
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $proof = @(Invoke-ThornswoodNative {
            & ssh -F none -i $newKey -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=20 `
                -o ("ProxyCommand=`"" + $node.Source + "`" `"" + (Join-Path $BridgeDir 'connect.js') + "`"") $target 'echo THORNSWOOD_OK'
        } 2>&1 | ForEach-Object { "$_" })
        $ErrorActionPreference = $old
        Remove-Item Env:THORNSWOOD_BOX_TOKEN, Env:THORNSWOOD_BOX_URL -ErrorAction SilentlyContinue
        if (($proof -join '') -notmatch 'THORNSWOOD_OK') {
            $proof | Select-Object -Last 5 | ForEach-Object { Say "  $_" 'DarkGray' }
            Die "it did not get in, so no file was written. Its key and token are on the box; run this again once the lines above are dealt with, or -Name $Name -Remove to take them off."
        }
        Say '  ssh through the bridge with the new key got in' 'Green'
        $out = Join-Path $OutDir 'cloud-access.txt'
        Write-ThornswoodPrivateFile -Path $out -Text ("THORNSWOOD_BOX_KEY_B64=" + [Convert]::ToBase64String([IO.File]::ReadAllBytes($newKey)) + "`nTHORNSWOOD_BOX_TOKEN=$token`n")
        Head 'The file for the cloud environment'
        Say "  $out" 'Green'
        Say '  Its two lines go into the cloud environment''s variables as they are: Project settings, Cloud environment, the gear' 'White'
        Say '  beside the environment. Then delete the file. A new cloud session picks them up and runs scripts/vps/Setup-CloudSsh.ps1.' 'White'
    } else {
        $out = Join-Path (Join-Path $OutDir $Name) 'box-token.txt'
        Write-ThornswoodPrivateFile -Path $out -Text ($token + "`n")
        Head "$Name's token"
        Say "  $out" 'Green'
        Say "  Send what is in it to $Name alone (a Discord DM), then delete the file and its folder. They paste it when" 'White'
        Say '  .\scripts\vps\Setup-SshKey.ps1 asks, on their own PC. It opens nothing without their private key.' 'White'
    }
    $token = $null
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Done 0
