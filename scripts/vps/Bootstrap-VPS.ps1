<#
  Bootstrap-VPS.ps1

  Run this ON THE VPS, once, in the PowerShell 5.1 that ships with Windows
  Server 2022. It brings the box up to what the Thornswood server needs and
  nothing more.

  What it installs:
    PowerShell 7   so scripts behave the same here as on the build machine
    Node 24        matching the build machine exactly
    Git (optional) only if you want to pull updates here rather than copy them
    Build Tools (optional, -IncludeBuildTools) MSBuild and the .NET Framework
                   4.8.1 targeting pack, for the build runners (below)

  What it deliberately does NOT install:
    CMake, Python, vcpkg, or the C++ half of Visual Studio Build Tools. The
    server is not built here, it is copied here already built, and that
    toolchain is about 10 GB and an hour for no benefit.

  THE BUILD TOOLS, FOR THE RUNNERS (#498, Patrick, 12 Oct: "install the Build
  Tools on the VPS runners"). The launcher is built from launcher\app\
  Thornswood.csproj and installer\setup\Setup.csproj with MSBuild, and the
  build check runs on these runners whenever GitHub's own runner is refused
  (#2393). Windows Server has no MSBuild of its own that understands those
  projects: the in-box one under Microsoft.NET drives the in-box csc, which
  knows nothing past C# 5. So -IncludeBuildTools installs the two Build Tools
  parts the projects need, MSBuild (Microsoft.VisualStudio.Workload.MSBuildTools,
  with the Roslyn compiler) and the .NET Framework 4.8.1 reference assemblies
  (Microsoft.Net.Component.4.8.1.TargetingPack), about 1.5 GB, and nothing
  else. Measured before it on 15 Oct: no MSBuild, no vswhere and no reference
  assemblies anywhere on the box. The bootstrapper is Microsoft's own
  aka.ms/vs/17/release/vs_buildtools.exe, which has no fixed hash to pin (it
  changes with every Visual Studio servicing release), so it is held to its
  Authenticode signature instead: valid, and signed by Microsoft Corporation,
  or it is deleted unrun.

  On the Node version: scam_native.node is a Node-API addon (it exports
  napi_register_module_v1 and links node-addon-api), and Node-API is ABI stable
  across major versions, so the 22.11.0 already on this box would load it. 24 is
  installed anyway so that "does the addon match the runtime" never has to be
  asked again.

  winget does not exist on Windows Server 2022, so everything here is a direct
  MSI. PowerShell 7 and Git are resolved at download time. Node is not: it is
  one exact release with the SHA-256 nodejs.org publishes for it, because the
  newest v24 on the day is whatever the next fresh box happens to get, and
  nodejs.org keeps every release at the same address, so that URL does not rot.
#>
[CmdletBinding()]
param(
    [int]   $GamePort     = 7777,
    [int]   $ResourcePort = 3000,
    [string]$NodeMajor    = 'v24',
    # The Node release a fresh box gets, and the SHA-256 of its x64 msi from
    # https://nodejs.org/dist/<version>/SHASUMS256.txt. Bump both together, on
    # purpose. Never below the build machine, which ran v24.15.0 on 24 Sep.
    # v24.21.0 is the newest v24 as of that day and so what this script was
    # already installing; v24.17.0 and v24.18.1, both after the build
    # machine's, are security releases.
    [string]$NodeVersion  = 'v24.21.0',
    [string]$NodeSha256   = 'bb0eaee134f9357f22aea915ee793343e627aefc1e66488164bac6915bce2cac',
    [switch]$IncludeGit,
    # MSBuild and the .NET Framework 4.8.1 reference assemblies, for the build
    # runners (#498). See the header.
    [switch]$IncludeBuildTools,
    [switch]$SkipFirewall
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# --- refuse to run anywhere that is not the VPS -----------------------------
#
# THE GUARD USED TO TEST A FOLDER THAT NO LONGER EXISTS. It looked for
# SkyrimSE.exe in the old build folder, which was the install path before the
# rename, so on either machine as they are today the guard cannot fire and this
# script goes on to install Node and Python as though it were the VPS.
#
# A safety check has to test the thing it protects against, and it has to keep
# testing it when that thing moves. So this asks Windows what it IS rather than
# looking for one file: ProductType 1 is a workstation, 2 is a domain
# controller and 3 is a server. The VPS is a server; both of the machines this
# is meant to refuse are workstations.
#
# The Skyrim check stays underneath it as a second net, pointed at the paths
# that exist now. Either one firing is enough.
$productType = 1
try { $productType = [int](Get-CimInstance Win32_OperatingSystem).ProductType } catch { }
if ($productType -eq 1) {
    throw "This is a workstation, not a server, so it is not the VPS. Nothing was changed."
}

foreach ($sign in @('C:\Thornswood\Game\SkyrimSE.exe',
                    'C:\Thornswood-DevBuild\Game\SkyrimSE.exe')) {
    if (Test-Path -LiteralPath $sign) {
        throw "$sign is present, so this looks like a gaming PC, not the VPS. Nothing was changed."
    }
}
Write-Host "host: $env:COMPUTERNAME   user: $env:USERNAME" -ForegroundColor Cyan
Write-Host "PowerShell currently: $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
Write-Host ''

$tmp = Join-Path $env:TEMP 'thornswood-bootstrap'
if (-not (Test-Path $tmp)) { New-Item -ItemType Directory -Path $tmp -Force | Out-Null }

function Install-Msi([string]$url, [string]$name, [string]$sha256) {
    $file = Join-Path $tmp (Split-Path $url -Leaf)
    Write-Host "  downloading $name" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing
    # Checked before msiexec sees it, when there is a published value to check
    # against. A file that does not match is deleted and never installed.
    if ($sha256) {
        $got = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        if ($got -ne $sha256) {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            throw "$name does not match its published SHA-256, so it was not installed. Expected $sha256, got $got"
        }
        Write-Host "  checksum matched for $name" -ForegroundColor DarkGray
    }
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
    Write-Host "Node ($NodeVersion, currently $(if ($haveNode) { $haveNode } else { 'absent' }))" -ForegroundColor Cyan
    # The exact release above rather than the newest $NodeMajor on the day.
    if (-not $NodeVersion.StartsWith("$NodeMajor.")) { throw "NodeVersion $NodeVersion is not a $NodeMajor release" }
    Install-Msi "https://nodejs.org/dist/$NodeVersion/node-$NodeVersion-x64.msi" "Node $NodeVersion" $NodeSha256
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

# --- Build Tools, only if asked (#498) --------------------------------------
# What builds the two project files: MSBuild with the Roslyn compiler, and the
# .NET Framework 4.8.1 reference assemblies. Asked of vswhere and the reference
# folder the same way scripts\release\Find-MSBuild.ps1 asks, so "present" here
# means what the build means by it.
$pf86 = ${env:ProgramFiles(x86)}
if (-not $pf86) { $pf86 = $env:ProgramFiles }
$vswhere = Join-Path $pf86 'Microsoft Visual Studio\Installer\vswhere.exe'
$refs481 = Join-Path $pf86 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1\mscorlib.dll'
function Test-BuildTools {
    $msb = $null
    if (Test-Path -LiteralPath $vswhere) {
        $msb = @(& $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' 2>$null |
                 Where-Object { $_ -and ($_ -notmatch '\\amd64\\|\\arm64\\') }) | Select-Object -First 1
    }
    @{ MSBuild = $msb; Refs = (Test-Path -LiteralPath $refs481) }
}
if ($IncludeBuildTools) {
    $bt = Test-BuildTools
    if ($bt.MSBuild -and $bt.Refs) {
        Write-Host "Build Tools already present: $($bt.MSBuild)" -ForegroundColor Green
    } else {
        Write-Host 'Build Tools (MSBuild and the .NET Framework 4.8.1 targeting pack)' -ForegroundColor Cyan
        $boot = Join-Path $tmp 'vs_buildtools.exe'
        Write-Host '  downloading the Visual Studio 2022 Build Tools bootstrapper' -ForegroundColor DarkGray
        Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vs_buildtools.exe' -OutFile $boot -UseBasicParsing
        # No fixed hash exists for it (see the header), so its signature decides.
        $sig = Get-AuthenticodeSignature -LiteralPath $boot
        $who = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '' }
        if ("$($sig.Status)" -ne 'Valid' -or $who -notmatch '^CN=Microsoft Corporation,') {
            Remove-Item -LiteralPath $boot -Force -ErrorAction SilentlyContinue
            throw "The Build Tools bootstrapper is not a valid Microsoft-signed file (status $($sig.Status), signer '$who'), so it was deleted unrun. Nothing was installed."
        }
        Write-Host "  signature valid, $($who.Split(',')[0])" -ForegroundColor DarkGray
        Write-Host '  installing, about 1.5 GB; this takes several minutes' -ForegroundColor DarkGray
        $btArgs = @('--quiet', '--wait', '--norestart', '--nocache',
                    '--add', 'Microsoft.VisualStudio.Workload.MSBuildTools',
                    '--add', 'Microsoft.Net.Component.4.8.1.TargetingPack')
        $p = Start-Process -FilePath $boot -ArgumentList $btArgs -Wait -PassThru
        # 3010 is "done, a restart finishes it"; MSBuild works before that restart.
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "The Build Tools installer exited with $($p.ExitCode). Its log is under $env:TEMP\dd_*.log." }
        $bt = Test-BuildTools
        if (-not $bt.MSBuild -or -not $bt.Refs) {
            throw ("The Build Tools installer finished (exit $($p.ExitCode)) but " +
                   $(if (-not $bt.MSBuild) { 'vswhere finds no MSBuild' } else { 'the 4.8.1 reference assemblies are not at ' + (Split-Path $refs481) }) + '.')
        }
        Write-Host "  MSBuild at $($bt.MSBuild)$(if ($p.ExitCode -eq 3010) { ' (Windows asks for a restart to finish; the build works before it)' })" -ForegroundColor Green
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
$bt = Test-BuildTools
Write-Host ("  {0,-6} {1}" -f 'msbuild', $(if ($bt.MSBuild -and $bt.Refs) { $bt.MSBuild } elseif ($bt.MSBuild) { 'present, but no .NET Framework 4.8.1 reference assemblies' } else { 'not installed (-IncludeBuildTools for the runners)' })) -ForegroundColor DarkGray
$free = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
Write-Host ("  disk   {0} GB free on C:" -f $free) -ForegroundColor DarkGray

Write-Host ''
Write-Host 'Open a NEW window so the updated PATH applies, then send the server payload.' -ForegroundColor Yellow
