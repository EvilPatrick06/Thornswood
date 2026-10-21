<#
  test-2932-ssh-proxy-speed.ps1

      pwsh -NoProfile -File .\tests\test-2932-ssh-proxy-speed.ps1

  Issue #2932. On 21 Oct 2026 One copied 50 MB to the box by scp through the
  bridge at 1.76 MB/s, while One's own line carried the same 50 MB over HTTPS
  at 11.1 MB/s, a cloud thread's scp through the same bridge ran at 12.5 MB/s,
  and the bridge's code alone runs at 250 MB/s on the box
  (test-2932-bridge-throughput.js). So the slow part is on One, between
  Windows' ssh client and connect.js, its ProxyCommand.

  This measures that here, on Windows, with Windows' own ssh and scp and a
  throwaway sshd on loopback that takes this account's throwaway key, so
  nothing leaves the machine and no real key is used. The same 32 MB file is
  copied up and down three ways:
    1. straight to the sshd's port, with no ProxyCommand;
    2. through a ProxyCommand that only joins standard input and output to
       the sshd's port (relay.js, written here), so what it adds is the pipe
       between ssh and its ProxyCommand and nothing of the bridge;
    3. through connect.js and bridge.js, the way One reaches the box.
  It prints each rate. Every copy must arrive whole.

  Windows only: it says NOT RUN elsewhere. The scratch folder, the sshd and
  every process it starts are gone when it ends.
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Windows.ps1')
if (-not $OnWindows) { Write-Host 'NOT RUN  this measures Windows'' own ssh client and its ProxyCommand pipe, which only Windows has'; exit 0 }

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$ok) {
    if ($ok) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
$sshDir = Get-WindowsPath 'System32\OpenSSH'
$ssh = Join-Path $sshDir 'ssh.exe'; $scp = Join-Path $sshDir 'scp.exe'; $sshd = Join-Path $sshDir 'sshd.exe'; $keygen = Join-Path $sshDir 'ssh-keygen.exe'
$node = (Get-Command node -ErrorAction Stop).Source
Write-Host ("ssh: " + (& $ssh -V 2>&1) + "; node " + (& $node -v) + "; " + [Environment]::OSVersion.VersionString + "; " + $env:USERNAME)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-2932-ssh-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $tmp
$procs = @()
try {
    & $keygen -q -t ed25519 -N '' -f (Join-Path $tmp 'host') | Out-Null
    & $keygen -q -t ed25519 -N '' -f (Join-Path $tmp 'user') | Out-Null
    Copy-Item (Join-Path $tmp 'user.pub') (Join-Path $tmp 'authorized_keys')
    $l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    $fwd = $tmp.Replace('\', '/')
    @(
        "Port $port", 'ListenAddress 127.0.0.1', "HostKey $fwd/host", "AuthorizedKeysFile $fwd/authorized_keys",
        "PidFile $fwd/sshd.pid", 'StrictModes no', 'PasswordAuthentication no', "Subsystem sftp $($sshDir.Replace('\', '/'))/sftp-server.exe",
        'LogLevel ERROR'
    ) | Set-Content -LiteralPath (Join-Path $tmp 'sshd_config') -Encoding ascii
    $so = Join-Path $tmp 'sshd.out'
    $procs += Start-Process -FilePath $sshd -ArgumentList @('-D', '-e', '-f', "`"$tmp\sshd_config`"") -PassThru -RedirectStandardError $so
    $up = $false
    for ($i = 0; $i -lt 50 -and -not $up; $i++) {
        try { $c = [Net.Sockets.TcpClient]::new('127.0.0.1', $port); $c.Close(); $up = $true } catch { Start-Sleep -Milliseconds 100 }
    }
    Yes "a throwaway sshd listens on 127.0.0.1:$port as this account" $up
    if (-not $up) { Write-Host ('      sshd said: ' + ((Get-Content -LiteralPath $so -Raw -ErrorAction SilentlyContinue) -replace '\s+', ' ')); throw 'no sshd' }

    # The ProxyCommand that adds nothing but the pipe.
    $relay = Join-Path $tmp 'relay.js'
    [IO.File]::WriteAllText($relay, "const s=require('net').connect(Number(process.argv[2]),'127.0.0.1');process.stdin.pipe(s);s.pipe(process.stdout);s.on('close',()=>process.exit(0));")
    # The bridge, on loopback, joined to the throwaway sshd.
    $tokens = Join-Path $tmp 'tokens'; $null = New-Item -ItemType Directory -Path $tokens
    $token = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    $sha = [Security.Cryptography.SHA256]::Create()
    [IO.File]::WriteAllText((Join-Path $tokens 'speed'), (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($token)) | ForEach-Object { $_.ToString('x2') })))
    $l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $l.Start(); $bport = $l.LocalEndpoint.Port; $l.Stop()
    $env:THORNSWOOD_BRIDGE_PORT = "$bport"; $env:THORNSWOOD_BRIDGE_TOKENS = $tokens; $env:THORNSWOOD_BRIDGE_TARGET = "127.0.0.1:$port"
    $procs += Start-Process -FilePath $node -ArgumentList @("`"$Repo\scripts\vps\bridge\bridge.js`"") -PassThru -RedirectStandardOutput (Join-Path $tmp 'bridge.out')
    Start-Sleep -Milliseconds 800
    $env:THORNSWOOD_BOX_URL = "ws://127.0.0.1:$bport/box/"; $env:THORNSWOOD_BOX_TOKEN = $token
    Remove-Item Env:\HTTPS_PROXY -ErrorAction SilentlyContinue; Remove-Item Env:\https_proxy -ErrorAction SilentlyContinue

    $MB = 32
    $file = Join-Path $tmp 'r.bin'
    $b = New-Object byte[] ($MB * 1MB); (New-Object Random 2932).NextBytes($b); [IO.File]::WriteAllBytes($file, $b)
    $want = (Get-FileHash -LiteralPath $file).Hash
    $common = @('-F', 'NUL', '-o', 'BatchMode=yes', '-o', "IdentityFile=$tmp\user", '-o', 'IdentitiesOnly=yes',
                '-o', "UserKnownHostsFile=$tmp\known_hosts", '-o', 'StrictHostKeyChecking=accept-new', '-o', 'LogLevel=ERROR')
    $ways = [ordered]@{
        'straight to the port'           = @('-P', "$port")
        'through a plain pipe relay'     = @('-o', "ProxyCommand=`"$node`" `"$relay`" $port")
        'through connect.js and bridge.js' = @('-o', "ProxyCommand=`"$node`" `"$Repo\scripts\vps\bridge\connect.js`"")
    }
    foreach ($w in $ways.Keys) {
        $a = $common + $ways[$w]
        $dst = "$tmp\up-$($ways.Keys.IndexOf($w)).bin"
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $scp @a -q $file ("$env:USERNAME@127.0.0.1:" + $dst.Replace('\', '/')) 2>&1 | ForEach-Object { Write-Host "      $_" }
        $upMs = $sw.ElapsedMilliseconds; $upOk = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $dst) -and (Get-FileHash -LiteralPath $dst).Hash -eq $want)
        $back = "$tmp\down-$($ways.Keys.IndexOf($w)).bin"
        $sw = [Diagnostics.Stopwatch]::StartNew()
        & $scp @a -q ("$env:USERNAME@127.0.0.1:" + $file.Replace('\', '/')) $back 2>&1 | ForEach-Object { Write-Host "      $_" }
        $dnMs = $sw.ElapsedMilliseconds; $dnOk = ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $back) -and (Get-FileHash -LiteralPath $back).Hash -eq $want)
        Write-Host ("  {0}: up {1} ms, {2:N1} MB/s; down {3} ms, {4:N1} MB/s" -f $w, $upMs, ($MB * 1000 / [Math]::Max(1, $upMs)), $dnMs, ($MB * 1000 / [Math]::Max(1, $dnMs)))
        Yes "$w`: the copy up arrived whole" $upOk
        Yes "$w`: the copy down arrived whole" $dnOk
        Remove-Item -LiteralPath $dst, $back -Force -ErrorAction SilentlyContinue
    }
} finally {
    foreach ($p in $procs) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { Write-Host "      could not stop $($p.Id): $($_.Exception.Message)" } }
    Start-Sleep -Milliseconds 300
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
Write-Host "$script:pass passed, $script:fail failed"
if ($script:fail) { exit 1 }
exit 0
