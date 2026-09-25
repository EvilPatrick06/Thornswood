<#
  Restore-Backup.ps1

  Opens one of the nightly backups: checks it has not been tampered with,
  decrypts it, and unpacks it into a folder you name. Runs on this machine and
  touches nothing on the VPS, so it is safe to run whenever you want to know
  whether the backups are real.

      .\scripts\vps\Restore-Backup.ps1 -Backup ...\thornswood-20260918-030000.zip.enc
      .\scripts\vps\Restore-Backup.ps1 -Backup ...\thornswood-...enc -To C:\test-restore
      .\scripts\vps\Restore-Backup.ps1 -Backup ...\thornswood-...enc -CheckOnly

  The passphrase is the one in the key file that Install-Backup.ps1 made. Pass
  -KeyFile to point at your copy of it. It is never printed and never written
  anywhere by this script.

  -CheckOnly verifies the signature and stops. That is worth running on a
  schedule: it is the difference between having backups and believing you do.

  Putting what comes out back onto the server is docs\RESTORING.md. This
  script deliberately does not do that part. Writing over a live world folder
  is not something a script should be able to do by accident.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Backup,
  [string]$To,
  [string]$KeyFile,
  [switch]$CheckOnly,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
function Die($m) { Write-Host ''; Write-Host "STOP. $m" -ForegroundColor Red; if (-not $NoPause) { [void](Read-Host 'Enter to exit') }; exit 1 }

if (-not (Test-Path -LiteralPath $Backup)) { Die "There is no file at $Backup" }
$src = (Resolve-Path -LiteralPath $Backup).Path
Head 'The backup'
Say ("  {0}" -f (Split-Path -Leaf $src))
Say ("  {0} MB, written {1}" -f [math]::Round((Get-Item $src).Length / 1MB, 2), (Get-Item $src).LastWriteTime) 'DarkGray'

$zipPath = $null
$temp = $null

if ($src.ToLower().EndsWith('.enc')) {
  if (-not $KeyFile) {
    foreach ($guess in @((Join-Path $PSScriptRoot '..\..\tools\backup-key.txt'), 'C:\Thornswood-Backup\key.txt')) {
      if (Test-Path -LiteralPath $guess) { $KeyFile = $guess; break }
    }
  }
  if (-not $KeyFile -or -not (Test-Path -LiteralPath $KeyFile)) {
    Die 'No passphrase file. Pass -KeyFile pointing at your copy of the one Install-Backup.ps1 made.'
  }
  $pass = (Get-Content -LiteralPath $KeyFile -Raw).Trim()
  if (-not $pass) { Die "The passphrase file at $KeyFile is empty." }

  $bytes = [System.IO.File]::ReadAllBytes($src)
  if ($bytes.Length -lt 5 + 16 + 16 + 32) { Die 'That file is too short to be one of these backups.' }
  $magic = [Text.Encoding]::ASCII.GetString($bytes, 0, 5)
  if ($magic -ne 'TSBK1') { Die "That is not a Thornswood backup: it starts with '$magic', not TSBK1." }

  $salt = New-Object byte[] 16; [Array]::Copy($bytes, 5, $salt, 0, 16)
  $iv   = New-Object byte[] 16; [Array]::Copy($bytes, 21, $iv, 0, 16)
  $cipherLen = $bytes.Length - 5 - 16 - 16 - 32
  $cipher = New-Object byte[] $cipherLen
  [Array]::Copy($bytes, 37, $cipher, 0, $cipherLen)
  $mac = New-Object byte[] 32
  [Array]::Copy($bytes, $bytes.Length - 32, $mac, 0, 32)

  Head 'Checking it has not been changed'
  $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($pass, $salt, 200000, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
  $kEnc = $kdf.GetBytes(32)
  $kMac = $kdf.GetBytes(32)
  $hmac = [System.Security.Cryptography.HMACSHA256]::new($kMac)
  $signed = New-Object byte[] (32 + $cipherLen)
  [Array]::Copy($salt, 0, $signed, 0, 16)
  [Array]::Copy($iv, 0, $signed, 16, 16)
  [Array]::Copy($cipher, 0, $signed, 32, $cipherLen)
  $want = $hmac.ComputeHash($signed)
  # Compared a byte at a time to the end rather than stopping at the first
  # difference, so how long this takes says nothing about how close a wrong
  # answer was.
  $same = $want.Length -eq $mac.Length
  $diff = 0
  for ($i = 0; $i -lt $mac.Length; $i++) { $diff = $diff -bor ($want[$i] -bxor $mac[$i]) }
  if (-not $same -or $diff -ne 0) {
    $kdf.Dispose(); $hmac.Dispose()
    Die ("The signature does not match. Either the passphrase is not the one this was made with, " +
         "or the file has been changed or damaged. Nothing was decrypted.")
  }
  Say '  signature matches' 'Green'

  $aes = [System.Security.Cryptography.Aes]::Create()
  $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'
  $aes.Key = $kEnc; $aes.IV = $iv
  $plain = $aes.CreateDecryptor().TransformFinalBlock($cipher, 0, $cipher.Length)
  $aes.Dispose(); $kdf.Dispose(); $hmac.Dispose()

  $temp = Join-Path $env:TEMP ('thornswood-restore-' + [Guid]::NewGuid().ToString('N').Substring(0, 8) + '.zip')
  [System.IO.File]::WriteAllBytes($temp, $plain)
  $zipPath = $temp
  Say ("  decrypted to a zip of {0} MB" -f [math]::Round($plain.Length / 1MB, 2)) 'DarkGray'
} else {
  $zipPath = $src
  Say '  not encrypted, so there is nothing to check' 'Yellow'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zf = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
$entries = @($zf.Entries)
$worldCount = @($entries | Where-Object { $_.FullName -match '^game/world/' }).Count
$privCount  = @($entries | Where-Object { $_.FullName -match '^game/private/' }).Count

Head 'What is in it'
Say ("  {0} entries" -f $entries.Count)
Say ("  {0,-28} {1}" -f 'game/world (characters)', $(if ($worldCount) { "$worldCount files" } else { 'NOTHING. This backup has no characters in it.' })) $(if ($worldCount) { 'Green' } else { 'Red' })
Say ("  {0,-28} {1} files" -f 'game/private', $privCount)
foreach ($top in ($entries | ForEach-Object { ($_.FullName -split '/')[0] } | Sort-Object -Unique)) {
  $n = @($entries | Where-Object { $_.FullName -like "$top/*" -or $_.FullName -eq $top }).Count
  Say ("  {0,-28} {1} entries" -f $top, $n) 'DarkGray'
}
$notes = $entries | Where-Object { $_.FullName -eq 'NOTES.txt' } | Select-Object -First 1
if ($notes) {
  Head 'NOTES.txt from the box it was taken on'
  $sr = New-Object System.IO.StreamReader($notes.Open())
  $sr.ReadToEnd() -split "`r?`n" | ForEach-Object { Say "  $_" 'DarkGray' }
  $sr.Close()
}
$zf.Dispose()

if ($CheckOnly) {
  if ($temp) { Remove-Item -LiteralPath $temp -Force -EA SilentlyContinue }
  Head 'Checked only'
  Say '  The backup opens and its signature is good. Nothing was written.' 'Green'
  if (-not $NoPause) { [void](Read-Host 'Enter to close') }
  exit 0
}

if (-not $To) { $To = Join-Path (Split-Path -Parent $src) ((Split-Path -Leaf $src) -replace '\.zip(\.enc)?$', '') }
if (Test-Path -LiteralPath $To) {
  if (@(Get-ChildItem -LiteralPath $To -Force -EA SilentlyContinue).Count -gt 0) {
    Die "$To already has things in it. Name an empty folder with -To; this will not write over one."
  }
} else {
  [void](New-Item -ItemType Directory -Path $To -Force)
}
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $To)
if ($temp) { Remove-Item -LiteralPath $temp -Force -EA SilentlyContinue }

Head 'Unpacked'
Say "  $To" 'Green'
Write-Host ''
Say '  Putting this back onto a server is docs\RESTORING.md. It is deliberately' 'DarkGray'
Say '  not something this script will do for you.' 'DarkGray'
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
