<#
  Bootstrap-VPS.ps1

  Run this ON THE VPS, once, in the PowerShell 5.1 that ships with Windows
  Server 2022. It brings the box up to what the Thornswood server needs and
  nothing more.

  What it installs:
    PowerShell 7   so scripts behave the same here as on the build machine
    Node 24        matching the build machine exactly
    Git (optional) only if you want to pull updates here rather than copy them

  What it deliberately does NOT install:
    Visual Studio Build Tools, CMake, Python, vcpkg. The server is not built
    here, it is copied here already built, and that toolchain is about 10 GB
    and an hour for no benefit.

  On the Node version: scam_native.node is a Node-API addon (it exports
  napi_register_module_v1 and links node-addon-api), and Node-API is ABI stable
  across major versions, so the 22.11.0 already on this box would load it. 24 is
  installed anyway so that "does the addon match the runtime" never has to be
  asked again.

  winget does not exist on Windows Server 2022, so everything here is a direct
  MSI. Versions are resolved at download time rather than baked in, because
  pinned URLs rot.
#>
[CmdletBinding()]
param(
    [int]   $GamePort     = 7777,
    [int]   $ResourcePort = 3000,
    [string]$NodeMajor    = 'v24',
    [switch]$IncludeGit,
    [switch]$SkipFirewall
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- refuse to run on the gaming machine ------------------------------------
if (Test-Path 'C:\SkyrimTogether\Game\SkyrimSE.exe') {
    throw "SkyrimSE.exe is present, so this looks like the gaming PC, not the VPS. Nothing was changed."
}
Write-Host "host: $env:COMPUTERNAME   user: $env:USERNAME" -ForegroundColor Cyan
Write-Host "PowerShell currently: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
Write-Host ''

$tmp = Join-Path $env:TEMP 'thornswood-bootstrap'
if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

function Install-Msi([string]$url, [string]$name) {
    $file = Join-Path $tmp (Split-Path $url -Leaf)
    Write-Host "  downloading $name" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing
    $mb = [math]::Round((Get-Item $file).Length / 1MB, 1)
    Write-Host "  installing  $name ($mb MB), this takes a minute" -ForegroundColor DarkGray
    $p = Start-Process msiexec.exe -ArgumentList @('/i', "`"$file`"", '/quiet', '/norestart') -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        throw "$name installer exited with $($p.ExitCode)"
    }
}

# --- PowerShell 7 -----------------------------------------------------------
if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    Write-Host "PowerShell 7 already present: $(& pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')" -ForegroundColor Green
} else {
    Write-Host 'PowerShell 7' -ForegroundColor Cyan
    $rel = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' `
                             -Headers @{ 'User-Agent' = 'thornswood' } -UseBasicParsing
    $asset = $rel.assets | Where-Object { $_.name -like '*win-x64.msi' } | Select-Object -First 1
    if (-not $asset) { throw 'could not find a win-x64 msi in the latest PowerShell release' }
    Install-Msi $asset.browser_download_url "PowerShell $($rel.tag_name)"
}

# --- Node -------------------------------------------------------------------
$haveNode = $null
if (Get-Command node -ErrorAction SilentlyContinue) { $haveNode = (& node --version).Trim() }
if ($haveNode -and $haveNode.StartsWith($NodeMajor)) {
    Write-Host "Node already on the right major: $haveNode" -ForegroundColor Green
} else {
    Write-Host "Node ($NodeMajor, currently $(if ($haveNode) { $haveNode } else { 'absent' }))" -ForegroundColor Cyan
    $index = Invoke-RestMethod 'https://nodejs.org/dist/index.json' -UseBasicParsing
    $pick = $index | Where-Object { $_.version -like "$NodeMajor.*" } | Select-Object -First 1
    if (-not $pick) { throw "no $NodeMajor release listed on nodejs.org" }
    Install-Msi "https://nodejs.org/dist/$($pick.version)/node-$($pick.version)-x64.msi" "Node $($pick.version)"
}

# --- Git, only if asked -----------------------------------------------------
if ($IncludeGit -and -not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'Git' -ForegroundColor Cyan
    $rel = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest' `
                             -Headers @{ 'User-Agent' = 'thornswood' } -UseBasicParsing
    $asset = $rel.assets | Where-Object { $_.name -like '*64-bit.exe' -and $_.name -notlike '*Portable*' } | Select-Object -First 1
    if ($asset) {
        $file = Join-Path $tmp $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $file -UseBasicParsing
        Start-Process $file -ArgumentList '/VERYSILENT','/NORESTART' -Wait
    }
}

# --- firewall ---------------------------------------------------------------
# SLikeNet is UDP. A TCP-only rule looks exactly like a dead server: the client
# sits there and times out with nothing in the log to explain it.
if (-not $SkipFirewall) {
    Write-Host ''
    Write-Host 'firewall' -ForegroundColor Cyan
    $rules = @(
        @{ Name = 'Thornswood game (UDP)';      Port = $GamePort;     Protocol = 'UDP' }
        @{ Name = 'Thornswood game (TCP)';      Port = $GamePort;     Protocol = 'TCP' }
        @{ Name = 'Thornswood resources (TCP)'; Port = $ResourcePort; Protocol = 'TCP' }
    )
    foreach ($r in $rules) {
        if (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue) {
            Write-Host "  already there   $($r.Name)" -ForegroundColor DarkGray
        } else {
            New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Action Allow `
                                -Protocol $r.Protocol -LocalPort $r.Port | Out-Null
            Write-Host "  opened          $($r.Protocol)/$($r.Port)  $($r.Name)" -ForegroundColor DarkGray
        }
    }
}

# --- report -----------------------------------------------------------------
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path', 'User')

Write-Host ''
Write-Host 'ready:' -ForegroundColor Green
foreach ($c in 'pwsh','node','git') {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) {
        $v = switch ($c) {
            'pwsh' { & pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' }
            default { (& $c --version) -join ' ' }
        }
        Write-Host ("  {0,-6} {1}" -f $c, $v) -ForegroundColor DarkGray
    } else {
        Write-Host ("  {0,-6} not installed" -f $c) -ForegroundColor DarkGray
    }
}
$free = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Host ("  disk   {0} GB free on C:" -f $free) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'Open a NEW window so the updated PATH applies, then send the server payload.' -ForegroundColor Yellow
