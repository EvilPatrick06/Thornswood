<#
  Add-VpsKey.ps1

  Puts another person's public SSH key on the VPS, so they can run the scripts
  that talk to it from their own machine without ever holding the Administrator
  password. Run it from a machine whose own key already works (Setup-SshKey.ps1).

      .\Add-VpsKey.ps1 -PublicKey 'ssh-ed25519 AAAA... thornswood'
      .\Add-VpsKey.ps1 -PublicKey 'ssh-ed25519 AAAA... thornswood' -Remove

  The key goes into C:\ProgramData\ssh\administrators_authorized_keys, the one
  file Windows' sshd reads for administrators, with the permissions that file
  has to have or sshd ignores it. Duplicates are not added twice.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PublicKey,
    [switch]$Remove,
    [string]$VpsHost = '192.135.112.23',
    [string]$VpsUser = 'Administrator',
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; Write-Host ''; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

$key = $PublicKey.Trim()
if ($key -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256) [A-Za-z0-9+/=]+( .*)?$') {
    Die 'That does not look like a public key line. It starts with ssh-ed25519 or ssh-rsa and is one line long.'
}
if ($key -match 'PRIVATE KEY') { Die 'That is a private key. Never send those anywhere. Ask for the .pub file instead.' }

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
