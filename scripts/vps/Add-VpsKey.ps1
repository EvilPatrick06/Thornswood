<#
  Add-VpsKey.ps1

  Puts another person's public SSH key on the VPS, so they can run the scripts
  that talk to it from their own machine without ever holding the Administrator
  password. Run it from a machine whose own key already works (Setup-SshKey.ps1).

      .\Add-VpsKey.ps1 -FromClipboard
      .\Add-VpsKey.ps1 -PublicKey 'ssh-ed25519 AAAA... thornswood'
      .\Add-VpsKey.ps1 -PublicKey 'ssh-ed25519 AAAA... thornswood' -Remove

  -FromClipboard takes whatever is on the clipboard, a whole Discord message
  included, and picks the key line out of it.

  The key goes into C:\ProgramData\ssh\administrators_authorized_keys, the one
  file Windows' sshd reads for administrators, with the permissions that file
  has to have or sshd ignores it. Duplicates are not added twice.
#>
[CmdletBinding()]
param(
    [string]$PublicKey,
    [switch]$FromClipboard,
    [switch]$Remove,
    [string]$VpsHost = '',
    [string]$VpsUser = 'Administrator',
    [switch]$NoPause
)

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
. (Join-Path $Here 'Vps.ps1')
if (-not $VpsHost) { $VpsHost = Get-ThornswoodVpsAddress }
$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

if ($FromClipboard) { $PublicKey = [string](Get-Clipboard -Raw) }
if (-not $PublicKey) { Die 'Nothing to add. Pass -PublicKey with the line, or -FromClipboard with the line copied.' }
if ($PublicKey -match 'PRIVATE KEY') { Die 'That is a private key. Never send those anywhere. Ask for the .pub file instead.' }

# The line arrives however it was copied: on its own, inside a Discord message
# with words around it, wrapped in a code block, or split over two lines by a
# narrow window. Everything is put back on one line per key and the first
# thing that is a key is taken.
$pattern = '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) ([A-Za-z0-9+/=]+)( .*)?$'
# A whole body decodes as base64; an ed25519 one is always 68 characters. A
# line cut by a console at its window width has a body that is neither.
function Test-Body([string]$type, [string]$body) {
    if ($type -eq 'ssh-ed25519' -and $body.Length -ne 68) { return $false }
    try { [void][Convert]::FromBase64String($body); return $true } catch { return $false }
}
$lines = @($PublicKey -replace '`', ' ' -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$key = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256)\b') { continue }
    if ($lines[$i] -match $pattern -and (Test-Body $Matches[1] $Matches[2])) { $key = $lines[$i]; break }
    # Wrapped by a console at its window width: the type word, then the base64
    # body cut into pieces over the next line or two, then the comment. The
    # pieces are glued back together until they make a whole body.
    $last = [Math]::Min($i + 3, $lines.Count - 1)
    $tokens = @((($lines[$i..$last]) -join ' ') -split '\s+' | Where-Object { $_ })
    $type = $tokens[0]; $body = ''; $k = 1
    while ($k -lt $tokens.Count -and $tokens[$k] -match '^[A-Za-z0-9+/=]+$') {
        $body += $tokens[$k]; $k++
        if (Test-Body $type $body) { break }
    }
    if (-not (Test-Body $type $body)) { continue }
    $rest = if ($k -lt $tokens.Count) { ' ' + ($tokens[$k..($tokens.Count - 1)] -join ' ') } else { '' }
    $key = "$type $body$rest"
    break
}
if (-not $key) {
    Die ("No public key line in what was given ({0} line(s) looked at). The line starts with ssh-ed25519 or ssh-rsa, then a long run of letters and digits, then usually the word thornswood. Have him run   Get-Content `"`$HOME\.ssh\thornswood_ed25519.pub`"   and send exactly what it prints." -f $lines.Count)
}
Say "  key line found: $($key.Substring(0, [Math]::Min(40, $key.Length)))..." 'DarkGray'

$remote = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$f = 'C:\ProgramData\ssh\administrators_authorized_keys'
`$key = '$($key.Replace("'", "''"))'
`$have = @()
if (Test-Path -LiteralPath `$f) { `$have = @(Get-Content -LiteralPath `$f | Where-Object { `$_.Trim() }) }
if ($(if ($Remove) { '$true' } else { '$false' })) {
    `$after = @(`$have | Where-Object { `$_.Trim() -ne `$key })
    `$said = 'removed, ' + `$after.Count + ' key(s) left'
} else {
    `$after = `$have
    if (`$after -notcontains `$key) { `$after += `$key; `$said = 'added, ' + `$after.Count + ' key(s) now' } else { `$said = 'already there, ' + `$after.Count + ' key(s)' }
}
[IO.File]::WriteAllLines(`$f, [string[]]`$after, (New-Object Text.UTF8Encoding(`$false)))
icacls `$f /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
`$said
"@
$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remote))
$out = & ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$VpsUser@$VpsHost" "powershell -NoProfile -EncodedCommand $b64" 2>&1
if ($LASTEXITCODE -ne 0) { Die "ssh did not go through (exit $LASTEXITCODE): $out" }
Say ("  " + ($out | Where-Object { $_ -notmatch '^#< CLIXML|^<Objs' } | Out-String).Trim()) 'Green'
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
