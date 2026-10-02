<#
  Setup-SshKey.ps1

  Type the VPS password one last time.

  Every script that touches the VPS shells out to ssh and scp, and each of those
  asks for the password separately, which is how a single publish ends up asking
  four times. Windows' OpenSSH has no connection sharing, so the only real fix
  is to stop using a password: this makes a key, puts the public half on the
  VPS, and from then on nothing asks again.

  You are asked for the password once, by ssh itself, on the line below where it
  says so. Nothing here reads it, stores it or passes it on.

  The awkward part is Windows specific and worth knowing about: for accounts in
  the Administrators group, the Windows SSH server ignores the usual
  .ssh\authorized_keys and reads C:\ProgramData\ssh\administrators_authorized_keys
  instead, and it refuses to use that file at all unless its permissions are
  locked to Administrators and SYSTEM. Getting either wrong fails silently and
  just keeps asking for a password, which is why both are done here explicitly
  and then tested.

      .\Setup-SshKey.ps1            make the key and install it
      .\Setup-SshKey.ps1 -Test      only check whether it already works
      .\Setup-SshKey.ps1 -KeyOnly   make the key and point ssh at it, then print
                                    the public line for Patrick to add on the VPS.
                                    For a second developer who does not hold the
                                    VPS password.

  THE BOX'S OWN KEY. Every script runs ssh and scp with StrictHostKeyChecking=yes
  (issue #450): ssh talks only to a machine already in known_hosts and never
  adds one by itself, so a machine answering in the box's place on a hostile
  network gets refused rather than handed the scripts and their secrets. This
  is the step that writes the box into known_hosts, and it writes only a key
  whose fingerprint scripts\vps\vps.json pins (Add-ThornswoodKnownHost in
  Vps.ps1). "Host key verification failed" from any script means this has not
  run on the machine yet, or the box was rebuilt. -Test only reads, and says
  which.

  ONCE Harden-VPS.ps1 HAS RUN the box takes no password at all, so the
  install step here (the one that asks for it) cannot get in. A new machine
  uses -KeyOnly, and Patrick adds the line it prints with Add-VpsKey.ps1 from
  a machine whose key already works.
#>
[CmdletBinding()]
param(
    [string]$VpsHost = '',
    [string]$VpsUser = '',
    [string]$KeyPath,
    [switch]$Test,
    [switch]$KeyOnly,
    [switch]$NoPause
)


$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Vps.ps1')
if (-not $VpsUser) { $VpsUser = Get-ThornswoodVpsUser }
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$target = "$VpsUser@$VpsHost"
if (-not $KeyPath) { $KeyPath = Join-Path $HOME '.ssh\thornswood_ed25519' }

foreach ($t in 'ssh', 'ssh-keygen', 'ssh-keyscan') {
    if (-not (Get-Command $t -ErrorAction SilentlyContinue)) {
        Die "$t is not on PATH. Windows ships it: Settings, Apps, Optional features, OpenSSH Client."
    }
}

# ------------------------------------------------------------------ test ----
function Works {
    # BatchMode means ssh fails rather than falling back to asking, so this is
    # a real answer about the key instead of a prompt.
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = Invoke-ThornswoodNative { & ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=8 $target 'echo THORNSWOOD_OK' } 2>$null
    $ErrorActionPreference = $old
    return ($out -join '') -match 'THORNSWOOD_OK'
}

Write-Host ''
Write-Host '  THORNSWOOD  -  stop asking for the password' -ForegroundColor White
Say "  $target" 'DarkGray'

# --------------------------------------------------------------- host key ---
Head "The box's own key"
$hk = Test-ThornswoodKnownHost -Address $VpsHost
if ($hk.Status -eq 'trusted') {
    Say ('  known_hosts holds the pinned key (' + ($hk.Pinned -join ', ') + ')') 'Green'
} elseif ($hk.Status -eq 'wrong') {
    Die ("known_hosts on this machine holds a key for $VpsHost that scripts\vps\vps.json does not pin (" + ($hk.Wrong -join ', ') + '). ' +
         'Either the box was rebuilt, and its new fingerprints go in vps.json first, or something else answered in its place once. ' +
         "Once you know which: ssh-keygen -R $VpsHost, then run this again.")
} elseif ($Test) {
    Say '  known_hosts has no key for the box yet, so every script will stop at "Host key verification failed".' 'Yellow'
    Say '  Run .\Setup-SshKey.ps1 without -Test, on a network you trust, to write it.' 'Yellow'
} else {
    try { $n = Add-ThornswoodKnownHost -Address $VpsHost }
    catch { Die $_.Exception.Message }
    Say "  added $n pinned key line(s) to known_hosts" 'Green'
}

Head 'Checking whether it already works'
if (Works) {
    Say '  it does. Nothing to do.' 'Green'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}
Say '  not yet' 'DarkGray'
if ($Test) { Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to close') }; exit 1 }

# ------------------------------------------------------------------- key ----
Head 'The key'
$dir = Split-Path $KeyPath -Parent
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

if (Test-Path -LiteralPath "$KeyPath.pub") {
    Say "  using the one already at $KeyPath" 'DarkGray'
} else {
    # No passphrase on purpose. A passphrase here would mean typing something
    # every time instead of the password, which is the thing being fixed. The
    # key only opens this one VPS.
    #
    # Handing ssh-keygen an EMPTY argument through PowerShell is genuinely
    # awkward: '""' works in some versions and arrives as two literal quote
    # characters in others, and the failure is a key with a passphrase on it
    # rather than an error. So rather than bet on one spelling, try them and
    # check what actually came out.
    $made = $false
    foreach ($empty in '""', '') {
        Remove-Item -LiteralPath $KeyPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$KeyPath.pub" -Force -ErrorAction SilentlyContinue
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        Invoke-ThornswoodNative { & ssh-keygen -t ed25519 -N $empty -C 'thornswood' -f $KeyPath } 2>&1 | Out-Null
        $ErrorActionPreference = $old
        if (-not (Test-Path -LiteralPath "$KeyPath.pub")) { continue }

        # And prove it opens without one, because a key that needs a passphrase
        # would put the prompt back and look like this never worked.
        $ErrorActionPreference = 'Continue'
        $null = Invoke-ThornswoodNative { & ssh-keygen -y -P '' -f $KeyPath } 2>&1
        $ok = ($LASTEXITCODE -eq 0)
        $ErrorActionPreference = $old
        if ($ok) { $made = $true; break }
    }
    if (-not $made) {
        Die ('Could not make a key without a passphrase. Do it by hand, press Enter twice when it asks:' + [Environment]::NewLine +
             '    ssh-keygen -t ed25519 -f "' + $KeyPath + '"' + [Environment]::NewLine +
             'then run this again.')
    }
    Say "  made $KeyPath" 'Green'
}
$pub = (Get-Content -LiteralPath "$KeyPath.pub" -Raw).Trim()

if ($KeyOnly) {
    # The ssh config entry below is still wanted, so every script picks the key
    # up once the VPS knows it. The install step is the one thing skipped.
    Head 'Pointing ssh at it'
    $cfg = Join-Path $HOME '.ssh\config'
    $block = @"
Host $VpsHost
    User $VpsUser
    IdentityFile $KeyPath
    IdentitiesOnly yes
    StrictHostKeyChecking yes
"@
    $text = ''
    if (Test-Path -LiteralPath $cfg) { $text = [IO.File]::ReadAllText($cfg) }
    if ($text -notmatch [regex]::Escape("Host $VpsHost")) {
        $text = $text.TrimEnd() + "`r`n`r`n" + $block
        [IO.File]::WriteAllText($cfg, $text, (New-Object Text.UTF8Encoding($false)))
        Say "  added a Host entry to $cfg" 'Green'
    } else {
        Say '  there is already an entry for this host, left alone' 'DarkGray'
    }
    Head 'Send this line to Patrick'
    Say '  It is the public half of the key. It is safe to paste anywhere; only this machine holds the private half.' 'DarkGray'
    Write-Host ''
    Write-Host $pub -ForegroundColor White
    Write-Host ''
    Say "  Once it is on the VPS, .\Setup-SshKey.ps1 -Test proves it." 'DarkGray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# ---------------------------------------------------------------- install ---
Head 'Installing it on the VPS'
Say '  ssh will ask for the password now. This is the last time.' 'Yellow'

$remote = @"
`$ErrorActionPreference = 'Stop'
# Progress records come back as a wall of CLIXML when stdout is not a console.
`$ProgressPreference = 'SilentlyContinue'
`$f = 'C:\ProgramData\ssh\administrators_authorized_keys'
`$key = '$pub'
if (-not (Test-Path -LiteralPath (Split-Path `$f -Parent))) { New-Item -ItemType Directory -Path (Split-Path `$f -Parent) -Force | Out-Null }
`$have = @()
if (Test-Path -LiteralPath `$f) { `$have = @(Get-Content -LiteralPath `$f | Where-Object { `$_.Trim() }) }
if (`$have -notcontains `$key) { `$have += `$key }
# No byte order mark and no UTF16: sshd reads this as plain ASCII and silently
# ignores a file it cannot parse, which looks exactly like a wrong key.
[IO.File]::WriteAllLines(`$f, `$have, (New-Object Text.UTF8Encoding(`$false)))
icacls `$f /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
# The server has to be running for any of this to matter, and it has to be
# restarted before a permissions change is picked up.
Set-Service sshd -StartupType Automatic
Restart-Service sshd
'installed ' + `$have.Count + ' key(s)'
"@

$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))
Invoke-ThornswoodNative { & ssh -o StrictHostKeyChecking=yes $target "powershell -NoProfile -EncodedCommand $b64" }
if ($LASTEXITCODE -ne 0) { Die "that did not go through (ssh exited with $LASTEXITCODE). Nothing was changed here. If it said Permission denied (publickey), the box takes no password any more (Harden-VPS.ps1): run this with -KeyOnly and have Patrick add the line with Add-VpsKey.ps1." }

# ----------------------------------------------------------------- config ---
# So plain "ssh Administrator@..." uses the key too, and every script that
# shells out to ssh or scp gets it without being told.
Head 'Pointing ssh at it'
$cfg = Join-Path $HOME '.ssh\config'
$block = @"
Host $VpsHost
    User $VpsUser
    IdentityFile $KeyPath
    IdentitiesOnly yes
    StrictHostKeyChecking yes
"@
$text = ''
if (Test-Path -LiteralPath $cfg) { $text = [IO.File]::ReadAllText($cfg) }
if ($text -notmatch [regex]::Escape("Host $VpsHost")) {
    $text = $text.TrimEnd() + "`r`n`r`n" + $block
    [IO.File]::WriteAllText($cfg, $text, (New-Object Text.UTF8Encoding($false)))
    Say "  added a Host entry to $cfg" 'Green'
} else {
    Say '  there is already an entry for this host, left alone' 'DarkGray'
}

# ------------------------------------------------------------------ prove ---
Head 'Proving it'
Start-Sleep -Seconds 2
if (Works) {
    Write-Host ''
    Say 'Done. Nothing will ask for that password again.' 'Green'
    Say 'Publish-Server, Install-Voice and Reset-Character all go straight through now.' 'DarkGray'
} else {
    Write-Host ''
    Say 'The key went up but the server is still not accepting it.' 'Red'
    Say 'Almost always the permissions on the file. Check with:' 'Yellow'
    Say "  ssh $target `"icacls C:\ProgramData\ssh\administrators_authorized_keys`"" 'DarkGray'
    Say 'It should list only Administrators and SYSTEM.' 'DarkGray'
}
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
