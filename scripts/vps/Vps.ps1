<#
  Vps.ps1

  Shared defaults for the VPS address, user, and ports. Dot-source it:

      . (Join-Path $PSScriptRoot '..\vps\Vps.ps1')

  Then, after the param block:

      if (-not $Vps) { $Vps = Get-ThornswoodVpsAddress }

  An explicit -Vps on the command line still wins, because the param keeps
  whatever was passed; only an empty default is filled from vps.json.
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
    if (-not $j.address) { throw "vps.json has no address: $path" }
    return $j
}

function Get-ThornswoodVpsAddress {
    return [string](Get-ThornswoodVps).address
}

function Get-ThornswoodVpsUser {
    $u = [string](Get-ThornswoodVps).user
    if (-not $u) { $u = 'Administrator' }
    return $u
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
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $out = @(& ssh-keygen -l -E sha256 -f $tmp 2>$null)
        $ErrorActionPreference = $old
        foreach ($o in $out) {
            $m = [regex]::Match([string]$o, 'SHA256:[A-Za-z0-9+/]+')
            if ($m.Success) { return $m.Value }
        }
        return ''
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Get-ThornswoodKnownHostsPath {
    return (Join-Path $HOME '.ssh\known_hosts')
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
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $out = @(& ssh-keygen -F $Address -f $KnownHosts -l -E sha256 2>$null)
        $ErrorActionPreference = $old
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
function Add-ThornswoodKnownHost {
    param(
        [Parameter(Mandatory = $true)][string]$Address,
        [string]$KnownHosts = (Get-ThornswoodKnownHostsPath),
        [string[]]$Pinned = (Get-ThornswoodVpsHostKeys)
    )
    if (-not $Pinned.Count) { throw 'scripts\vps\vps.json pins no host keys, so there is nothing to check the box against. Nothing was written.' }
    $now = Test-ThornswoodKnownHost -Address $Address -KnownHosts $KnownHosts -Pinned $Pinned
    if ($now.Status -eq 'wrong') {
        throw ("$KnownHosts holds a key for $Address that is not the one scripts\vps\vps.json pins (" + ($now.Wrong -join ', ') +
               '). Either the box was rebuilt, and its new fingerprints go in vps.json first, or something else answered in its place once. Nothing was written.')
    }
    if ($now.Status -eq 'trusted') { return 0 }

    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $scan = @(& ssh-keyscan -T 10 $Address 2>$null)
    $ErrorActionPreference = $old
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
