<#
  Vps.ps1

  The one place every script gets the VPS address, user, and ports from.
  Dot-source it:

      . (Join-Path $PSScriptRoot '..\vps\Vps.ps1')

  Then, after the param block:

      if (-not $User) { $User = Get-ThornswoodVpsUser }
      if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }

  An explicit -Vps or -User on the command line still wins, because the param
  keeps whatever was passed; only an empty default is filled from here.

  WHERE THE ANSWER COMES FROM, last one wins (issue #459):

    1. scripts\vps\vps.json, tracked, the box everybody uses.
    2. This machine's own file, never tracked:
       %LOCALAPPDATA%\Thornswood\vps.json, or the file THORNSWOOD_VPS_LOCAL
       names. Any field in it replaces the same field from the tracked one,
       so {"address": "203.0.113.9"} on its own points this machine at
       another box and keeps the rest.
    3. The environment: THORNSWOOD_VPS for the address, THORNSWOOD_VPS_USER
       for the user. For one shell or one scheduled task.

  So a machine that reaches the box by another address, or a new box being
  tried before Set-Vps.ps1 moves everybody, needs no edit to a tracked file.
  tests\test-vps-defaults.ps1 fails on the address written anywhere else in a
  script.
#>

function Get-ThornswoodVps {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $path = Join-Path $here 'vps.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "VPS defaults not found: $path"
    }
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $j = $raw | ConvertFrom-Json
    $local = Get-ThornswoodVpsLocalPath
    if ($local -and (Test-Path -LiteralPath $local)) {
        $mine = $null
        try { $mine = Get-Content -LiteralPath $local -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        if (-not ($mine -is [Management.Automation.PSCustomObject])) { throw "This machine's VPS file does not read as a JSON object: $local" }
        foreach ($p in $mine.PSObject.Properties) { $j | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
    }
    if ($env:THORNSWOOD_VPS) { $j | Add-Member -NotePropertyName address -NotePropertyValue ([string]$env:THORNSWOOD_VPS) -Force }
    if ($env:THORNSWOOD_VPS_USER) { $j | Add-Member -NotePropertyName user -NotePropertyValue ([string]$env:THORNSWOOD_VPS_USER) -Force }
    if (-not $j.address) { throw "vps.json has no address: $path" }
    return $j
}

# This machine's own VPS file, which nothing in git carries. It need not exist.
function Get-ThornswoodVpsLocalPath {
    if ($env:THORNSWOOD_VPS_LOCAL) { return [string]$env:THORNSWOOD_VPS_LOCAL }
    if (-not $env:LOCALAPPDATA) { return '' }
    return (Join-Path (Join-Path $env:LOCALAPPDATA 'Thornswood') 'vps.json')
}

function Get-ThornswoodVpsAddress {
    return [string](Get-ThornswoodVps).address
}

function Get-ThornswoodVpsUser {
    $u = [string](Get-ThornswoodVps).user
    if (-not $u) { $u = 'Administrator' }
    return $u
}

# ------------------------------------------------------ ssh and scp -----
# Every ssh, scp, ssh-keygen and ssh-keyscan a script runs goes through this:
#
#     $out = Invoke-ThornswoodNative { & ssh @ssh "$User@$Vps" $cmd } 2>&1
#     $wire | Invoke-ThornswoodNative { $input | & ssh @ssh $target $cmd } 2>&1
#
# so a line the program writes on stderr is never an error by itself, and
# whether it worked is its exit code ($LASTEXITCODE), the same in Windows
# PowerShell 5.1 and PowerShell 7. Issue #941: from 28 September the box's
# OpenSSH (9.5) made the client here print "** WARNING: connection is not
# using a post-quantum key exchange algorithm" on stderr for every
# connection. Under Windows PowerShell 5.1 a native program's stderr line
# becomes an error record whenever stderr is redirected (2>&1, 2>$null, or a
# caller that redirected the whole script), and with $ErrorActionPreference
# = 'Stop', which every script here sets, the first one stops the script.
# PowerShell 7 never does that, which is why Ship still worked and
# Install-Voice.ps1 under powershell.exe did not.
#
# Inside this function the preference is Continue, for the call in the block
# and nothing else, so the stderr lines still come out as they always did: in
# the pipeline as error records under 2>&1 (Where-Object { $_ -is [string] }
# still drops them, [string]$_ still reads them), gone under 2>$null, and on
# the screen with no redirection. A real failure is still a failure: ssh and
# scp exit non-zero (255 when they cannot connect), and the caller reads
# $LASTEXITCODE as before. Keep the block to the one native call, so nothing
# else in a script is softened. tests\test-ssh-stderr.ps1 runs a stand-in ssh
# that prints the warning, under both PowerShells.
#
# A plain function on purpose: an advanced one (with [Parameter]) refuses
# pipeline input it has no parameter for, and the secret goes in by pipe.
function Invoke-ThornswoodNative($ThornswoodNativeCall) {
    if (-not ($ThornswoodNativeCall -is [scriptblock])) { throw 'Invoke-ThornswoodNative takes a script block: { & ssh ... }' }
    $ErrorActionPreference = 'Continue'
    if ($MyInvocation.ExpectingInput) { $input | & $ThornswoodNativeCall }
    else { & $ThornswoodNativeCall }
}

# ------------------------------------------------------------ host key ----
# Every script that reaches the box runs ssh and scp with
# StrictHostKeyChecking=yes (issue #450), so ssh only talks to a machine whose
# key is already in this machine's known_hosts, and never adds one by itself.
# What goes into known_hosts is decided here: vps.json "hostKeys" holds the
# box's public host key fingerprints (SHA256), and a key is written only when
# the machine answering at the address shows one of them. A fingerprint is
# public: anybody who connects to port 22 is shown it. Read on 28 September
# with ssh-keyscan and matched against Patrick's known_hosts, which had held
# them since the box was set up.
#
# A rebuilt box has new keys. Put its fingerprints in vps.json (read them in
# the provider's console on the box itself: for each
# C:\ProgramData\ssh\ssh_host_*_key.pub, ssh-keygen -lf <file>), then
# ssh-keygen -R <address> on each machine and Setup-SshKey.ps1 again.

function Get-ThornswoodVpsHostKeys {
    return @(@((Get-ThornswoodVps).hostKeys) | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim() })
}

# The SHA256 fingerprint of one known_hosts or ssh-keyscan line
# ("host keytype base64"), from ssh-keygen itself. '' when it is not a key.
function Get-ThornswoodSshFingerprint([string]$Line) {
    $tmp = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($tmp, $Line.Trim() + "`n", (New-Object Text.UTF8Encoding($false)))
        $out = @(Invoke-ThornswoodNative { & ssh-keygen -l -E sha256 -f $tmp } 2>$null)
        foreach ($o in $out) {
            $m = [regex]::Match([string]$o, 'SHA256:[A-Za-z0-9+/]+')
            if ($m.Success) { return $m.Value }
        }
        return ''
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

# One folder at a time, so the path is right in a cloud thread too (#2753):
# PowerShell on Linux takes '.ssh\known_hosts' as one file name in $HOME.
function Get-ThornswoodKnownHostsPath {
    return (Join-Path (Join-Path $HOME '.ssh') 'known_hosts')
}

# What known_hosts holds for the address, against the pin. Read only.
#   Status 'trusted'  every key held for the address is a pinned one
#          'wrong'    it holds a key that is not pinned: a rebuilt box, or
#                     something that once answered in its place
#          'none'     nothing for the address yet
function Test-ThornswoodKnownHost {
    param(
        [Parameter(Mandatory = $true)][string]$Address,
        [string]$KnownHosts = (Get-ThornswoodKnownHostsPath),
        [string[]]$Pinned = (Get-ThornswoodVpsHostKeys)
    )
    $held = @()
    if (Test-Path -LiteralPath $KnownHosts) {
        $out = @(Invoke-ThornswoodNative { & ssh-keygen -F $Address -f $KnownHosts -l -E sha256 } 2>$null)
        foreach ($o in $out) {
            if ([string]$o -match '^\s*#') { continue }
            $m = [regex]::Match([string]$o, 'SHA256:[A-Za-z0-9+/]+')
            if ($m.Success) { $held += $m.Value }
        }
    }
    $good = @($held | Where-Object { $Pinned -contains $_ })
    $bad = @($held | Where-Object { $Pinned -notcontains $_ })
    $status = 'none'
    if ($bad.Count) { $status = 'wrong' } elseif ($good.Count) { $status = 'trusted' }
    return [pscustomobject]@{ Status = $status; Pinned = $good; Wrong = $bad }
}

# The setup step. Asks the machine at the address for its host keys and writes
# into known_hosts only the ones vps.json pins. Throws, writing nothing, when
# known_hosts already holds a key that is not pinned or when the machine shows
# none of the pinned keys. Returns how many lines it added (0 when it already
# trusted the box).
#   -Scanned  the key lines, already asked for some other way, in place of
#             ssh-keyscan, which cannot go through a ProxyCommand. A cloud
#             thread reaches the box only through the bridge (#2753), so
#             Setup-CloudSsh.ps1 has ssh itself write the key it was shown to
#             a scratch file and hands those lines here, where they meet the
#             same pin.
function Add-ThornswoodKnownHost {
    param(
        [Parameter(Mandatory = $true)][string]$Address,
        [string]$KnownHosts = (Get-ThornswoodKnownHostsPath),
        [string[]]$Pinned = (Get-ThornswoodVpsHostKeys),
        [string[]]$Scanned = $null
    )
    if (-not $Pinned.Count) { throw 'scripts\vps\vps.json pins no host keys, so there is nothing to check the box against. Nothing was written.' }
    $now = Test-ThornswoodKnownHost -Address $Address -KnownHosts $KnownHosts -Pinned $Pinned
    if ($now.Status -eq 'wrong') {
        throw ("$KnownHosts holds a key for $Address that is not the one scripts\vps\vps.json pins (" + ($now.Wrong -join ', ') +
               '). Either the box was rebuilt, and its new fingerprints go in vps.json first, or something else answered in its place once. Nothing was written.')
    }
    if ($now.Status -eq 'trusted') { return 0 }

    if ($null -ne $Scanned) { $scan = @($Scanned) }
    else { $scan = @(Invoke-ThornswoodNative { & ssh-keyscan -T 10 $Address } 2>$null) }
    $keep = @()
    foreach ($line in $scan) {
        $l = ([string]$line).Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $fp = Get-ThornswoodSshFingerprint $l
        if ($fp -and ($Pinned -contains $fp)) { $keep += $l }
    }
    if (-not $keep.Count) {
        throw ("The machine answering at $Address did not show any host key scripts\vps\vps.json pins (it showed " + $scan.Count +
               ' key line(s)). Do not go on from this network. Nothing was written.')
    }
    $dir = Split-Path -Parent $KnownHosts
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $text = ''
    if (Test-Path -LiteralPath $KnownHosts) { $text = [IO.File]::ReadAllText($KnownHosts) }
    if ($text -and -not $text.EndsWith("`n")) { $text += "`n" }
    $text += (($keep -join "`n") + "`n")
    [IO.File]::WriteAllText($KnownHosts, $text, (New-Object Text.UTF8Encoding($false)))
    return $keep.Count
}
