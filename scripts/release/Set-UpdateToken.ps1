<#
  Set-UpdateToken.ps1

  Puts the GitHub token the launcher uses to see releases into this machine's
  config.json, then proves it works before you walk away.

      .\Set-UpdateToken.ps1

  It asks at a prompt rather than taking the token on the command line, so the
  token never appears on screen and never lands in your PowerShell history.

  The token only needs to READ the release repository. A fine-grained token
  scoped to that one repo with Contents: Read-only is the whole job. Anything
  more than that is damage waiting to happen, because this value goes onto the
  machine of everyone who installs the game if the packaging ever regresses.

  To take the token out entirely, run it and press enter on an empty line.
  Updates stop working until you put one back.
#>
[CmdletBinding()]
param(
    # owner/name of the repository releases are published to. Pass it to point
    # the launcher somewhere else, leave it off to keep what is already set.
    [string]$Repo,
    [string]$Root = 'C:\Thornswood',
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

Write-Host ''
Write-Host '  THORNSWOOD  -  update token' -ForegroundColor White

$cfgPath = Join-Path $Root 'config.json'
if (-not (Test-Path -LiteralPath $cfgPath)) { Die "not found: $cfgPath" }

$raw  = [IO.File]::ReadAllBytes($cfgPath)
$skip = if ($raw.Length -ge 3 -and $raw[0] -eq 0xEF -and $raw[1] -eq 0xBB -and $raw[2] -eq 0xBF) { 3 } else { 0 }
$cfg  = [Text.Encoding]::UTF8.GetString($raw, $skip, $raw.Length - $skip) | ConvertFrom-Json

$target = if ($cfg.PSObject.Properties.Name -contains 'UpdateRepo') { [string]$cfg.UpdateRepo } else { '' }
if ($Repo) {
    if ($Repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { Die "-Repo has to be owner/name. You gave: $Repo" }
    $target = $Repo
}
if (-not $target) { Die "config.json has no UpdateRepo, so there is nothing to read from. Pass -Repo owner/name." }

Write-Host ''
Say "  Repository: $target" 'DarkGray'
Say '  If that repository is PUBLIC, press enter on an empty line. No token is' 'DarkGray'
Say '  wanted and none should exist, because whatever is here ends up on the' 'DarkGray'
Say '  machine of everyone who installs the game.' 'DarkGray'
Say '  If it is private, paste a token scoped to it with Contents: Read-only:' 'DarkGray'
Say '  https://github.com/settings/personal-access-tokens/new' 'DarkGray'
Write-Host ''

$ss = Read-Host '  Paste the token' -AsSecureString
$token = ''
if ($ss -and $ss.Length -gt 0) {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)).Trim()
}

function Ask($url, $tok) {
    $h = @{ 'User-Agent' = 'Thornswood'; Accept = 'application/vnd.github+json'
            'X-GitHub-Api-Version' = '2022-11-28' }
    if ($tok) { $h.Authorization = "Bearer $tok" }
    return Invoke-RestMethod -Uri $url -Headers $h -TimeoutSec 20
}

if (-not $token) {
    Head 'Checking it can be read with no token'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $r = Ask "https://api.github.com/repos/$target" $null
        if (-not ($r -and $r.full_name)) { Die 'GitHub answered but not with the repository. Nothing was written.' }
        if ($r.private) { Die "$target is private, so a launcher with no token cannot read it. Make it public, or paste a token." }
        Say "  reads $($r.full_name), public" 'Green'
        $null = Ask "https://api.github.com/repos/$target/releases?per_page=1" $null
        Say '  can read releases' 'Green'
    } catch {
        $code = ''
        try { $code = [int]$_.Exception.Response.StatusCode } catch { }
        if ($code -eq 404) { Die "GitHub cannot see $target without a token. Either it is private, or the name is wrong. Nothing was written." }
        else { Die "Could not reach GitHub: $($_.Exception.Message). Nothing was written." }
    }

    Head 'Writing it'
    if ($cfg.PSObject.Properties.Name -contains 'UpdateToken') { $cfg.UpdateToken = '' }
    else { $cfg | Add-Member -NotePropertyName 'UpdateToken' -NotePropertyValue '' }
    if ($cfg.PSObject.Properties.Name -contains 'UpdateRepo') { $cfg.UpdateRepo = $target }
    else { $cfg | Add-Member -NotePropertyName 'UpdateRepo' -NotePropertyValue $target }
    [IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
    Say "  updates come from $target, no token held" 'Green'
    Write-Host ''
    Say 'Nothing secret is on this machine for updates any more, which is the point.' 'DarkGray'
    Write-Host ''
    if (-not $NoPause) { [void](Read-Host 'Enter to close') }
    exit 0
}

# Shape check before anything is written. A classic ghp_ token still works but
# they cannot be scoped to one repository, which is the entire point.
if ($token -match '^(your|paste|token|xxx|<)') {
    Die 'That looks like a placeholder rather than a token. Nothing was written.'
}
if ($token -notmatch '^(github_pat_|ghp_|gho_|ghs_)') {
    Write-Host ''
    Say '  That does not start like a GitHub token. Carrying on anyway, the check below decides.' 'Yellow'
}
if ($token -match '^ghp_') {
    Write-Host ''
    Say '  That is a classic token. Classic tokens cannot be limited to one repository,' 'Yellow'
    Say '  so it can reach everything you own. A fine-grained one is worth the two minutes.' 'Yellow'
}

# ------------------------------------------------------------------ check ---
Head 'Asking GitHub'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ok = $false
try {
    $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$target" -Headers @{
        Authorization          = "Bearer $token"
        'User-Agent'           = 'Thornswood'
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    } -TimeoutSec 20
    if ($r -and $r.full_name) {
        $ok = $true
        Say "  reads $($r.full_name), private: $($r.private)" 'Green'
    }
} catch {
    $code = ''
    try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    if ($code -eq 401) { Die 'GitHub refused the token. It is wrong, or it has been revoked. Nothing was written.' }
    elseif ($code -eq 404) { Die "GitHub says $target does not exist for this token. Check the token is scoped to that repository. Nothing was written." }
    else { Die "Could not reach GitHub: $($_.Exception.Message). Nothing was written." }
}
if (-not $ok) { Die 'GitHub answered but not with the repository. Nothing was written.' }

# Releases are what the launcher actually reads, so check that too rather than
# finding out at the next Ship.
try {
    $null = Invoke-RestMethod -Uri "https://api.github.com/repos/$target/releases?per_page=1" -Headers @{
        Authorization          = "Bearer $token"
        'User-Agent'           = 'Thornswood'
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    } -TimeoutSec 20
    Say '  can read releases' 'Green'
} catch {
    Die 'The token reads the repository but not its releases. Give it Contents: Read-only. Nothing was written.'
}

# ------------------------------------------------------------------ write ---
Head 'Writing it'
if ($cfg.PSObject.Properties.Name -contains 'UpdateToken') { $cfg.UpdateToken = $token }
else { $cfg | Add-Member -NotePropertyName 'UpdateToken' -NotePropertyValue $token }
if ($cfg.PSObject.Properties.Name -contains 'UpdateRepo') { $cfg.UpdateRepo = $target }
else { $cfg | Add-Member -NotePropertyName 'UpdateRepo' -NotePropertyValue $target }
[IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
$token = $null

# Nobody else on this machine has any business reading it. The launcher
# encrypts the value itself the next time it saves, this is the other half.
try {
    $acl = Get-Acl $cfgPath
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in @($acl.Access)) { [void]$acl.RemoveAccessRule($r) }
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        [Security.Principal.WindowsIdentity]::GetCurrent().Name, 'FullControl', 'Allow')))
    Set-Acl $cfgPath $acl
    Say '  written, and the file is now readable only by you' 'Green'
} catch {
    Say '  written. Could not tighten the file permissions, which is not fatal.' 'Yellow'
}

Write-Host ''
Say 'Next launch of the launcher will encrypt it in place.' 'DarkGray'
Say 'The token is not in your PowerShell history: it was never on the command line.' 'DarkGray'
Write-Host ''
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
