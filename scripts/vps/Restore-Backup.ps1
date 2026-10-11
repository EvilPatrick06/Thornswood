<#
  Restore-Backup.ps1

  Opens one of the nightly backups: checks it has not been tampered with,
  decrypts it, and unpacks it into a folder you name. Runs on this machine and
  touches nothing on the VPS, so it is safe to run whenever you want to know
  whether the backups are real.

      .\scripts\vps\Restore-Backup.ps1 -Backup ...\thornswood-20260918-030000.zip.enc
      .\scripts\vps\Restore-Backup.ps1 -Backup ...\thornswood-...enc -To C:\test-restore -Work C:\ThornswoodTemps&Worktrees\temp\restore
      .\scripts\vps\Restore-Backup.ps1 -Backup ...\thornswood-...enc -CheckOnly

  The passphrase is the one in the key file that Install-Backup.ps1 made. Pass
  -KeyFile to point at your copy of it. It is never printed and never written
  anywhere by this script.

  -CheckOnly verifies the signature, then reads the numbered change forms
  under game/world in the zip (0.json, 1.json, ...: a slot, not a profile id).
  It fails when none of them has a profile id above 0 that is not deleted, the
  same question Restore-Server.ps1 asks of a world (#1047). A world of only
  deleted slots, or only change forms that are not characters, is not a backup
  of anyone. That is worth running on a schedule: it is the difference between
  having backups and believing you do.

  Putting what comes out back onto the server is docs\RESTORING.md. This
  script deliberately does not do that part. Writing over a live world folder
  is not something a script should be able to do by accident.

  -Work is where the decrypted zip is written while this runs. Left out, that
  is %TEMP%. The zip holds the bot token and the site keys, so it is deleted
  before this exits, whether the backup was unpacked or the run was refused.
  -To is the folder the backup is unpacked into, and is not -Work.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Backup,
  [string]$To,
  [string]$KeyFile,
  # Where the decrypted zip is written. Left out, %TEMP%. Deleted before exit.
  [string]$Work,
  [switch]$CheckOnly,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }
function Head($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan; Write-Host ('-' * $m.Length) -ForegroundColor DarkGray }
$script:temp = $null
function Clear-RestoreZip {
  if ($script:temp -and (Test-Path -LiteralPath $script:temp)) {
    Remove-Item -LiteralPath $script:temp -Force -EA Stop
  }
}
function Die($m) {
  Clear-RestoreZip
  Write-Host ''
  Write-Host "STOP. $m" -ForegroundColor Red
  if (-not $NoPause) { [void](Read-Host 'Enter to exit') }
  exit 1
}

if (-not $Work) { $Work = $env:TEMP }
if (-not $Work) { Die 'No folder for the decrypted backup: -Work was not passed and %TEMP% is not set.' }
try { [void][IO.Directory]::CreateDirectory($Work) }
catch { Die ("-Work is not a folder: " + $Work + " (" + $_.Exception.Message + ")") }

try {
if (-not (Test-Path -LiteralPath $Backup)) { Die "There is no file at $Backup" }
$src = (Resolve-Path -LiteralPath $Backup).Path
Head 'The backup'
Say ("  {0}" -f (Split-Path -Leaf $src))
Say ("  {0} MB, written {1}" -f [math]::Round((Get-Item $src).Length / 1MB, 2), (Get-Item $src).LastWriteTime) 'DarkGray'

$zipPath = $null

if ($src.ToLower().EndsWith('.enc')) {
  if (-not $KeyFile) {
    # Where Install-Backup.ps1 copies it down to first, then the older places.
    $guesses = @()
    if ($env:USERPROFILE) { $guesses += Join-Path $env:USERPROFILE 'Documents\thornswood-backup-key.txt' }
    $guesses += (Join-Path $PSScriptRoot '..\..\local\backup-key.txt'), 'C:\Thornswood-Backup\key.txt'
    foreach ($guess in $guesses) {
      if (Test-Path -LiteralPath $guess) { $KeyFile = $guess; break }
    }
  }
  if (-not $KeyFile -or -not (Test-Path -LiteralPath $KeyFile)) {
    Die 'No passphrase file. Pass -KeyFile pointing at your copy of the one Install-Backup.ps1 made.'
  }
  # "$()": an empty file reads as $null (even through [string](...)), and a method on $null throws. Without it the
  # line below, which names the empty file, was never reached.
  $pass = ("$(Get-Content -LiteralPath $KeyFile -Raw)").Trim()
  if (-not $pass) { Die "The passphrase file at $KeyFile is empty." }

  $inputFile = $null; $outputFile = $null; $kdf = $null; $hmac = $null
  $aes = $null; $decryptor = $null; $cryptoStream = $null
  $operationFailure = $null
  try {
    # Keep one read-only handle for verification and decryption. The bytes
    # cannot be replaced or written between those passes on Windows.
    $inputFile = [IO.File]::Open($src, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    if ($inputFile.Length -lt 85) { Die 'That file is too short to be one of these backups.' }
    $header = New-Object byte[] 37
    $read = 0
    while ($read -lt $header.Length) {
      $n = $inputFile.Read($header, $read, $header.Length - $read)
      if ($n -eq 0) { Die 'That backup has an incomplete header.' }
      $read += $n
    }
    $magic = [Text.Encoding]::ASCII.GetString($header, 0, 5)
    if ($magic -ne 'TSBK1') { Die "That is not a Thornswood backup: it starts with '$magic', not TSBK1." }
    $salt = [byte[]]$header[5..20]; $iv = [byte[]]$header[21..36]
    $cipherLen = $inputFile.Length - 69
    if ($cipherLen % 16 -ne 0) { Die 'That backup has a truncated or invalid ciphertext length. Nothing was decrypted.' }
    Head 'Checking it has not been changed'
    $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($pass, $salt, 200000, [Security.Cryptography.HashAlgorithmName]::SHA256)
    $kEnc = $kdf.GetBytes(32); $kMac = $kdf.GetBytes(32)
    $hmac = [Security.Cryptography.HMACSHA256]::new($kMac)
    $inputFile.Position = 5
    $left = $inputFile.Length - 37
    $chunk = New-Object byte[] 1MB
    while ($left -gt 0) {
      $n = $inputFile.Read($chunk, 0, [int][Math]::Min([long]$chunk.Length, [long]$left))
      if ($n -eq 0) { Die 'That backup ended before its signature. Nothing was decrypted.' }
      [void]$hmac.TransformBlock($chunk, 0, $n, $chunk, 0); $left -= $n
    }
    [void]$hmac.TransformFinalBlock([byte[]]@(), 0, 0)
    $want = $hmac.Hash
    $mac = New-Object byte[] 32; $read = 0
    while ($read -lt $mac.Length) {
      $n = $inputFile.Read($mac, $read, $mac.Length - $read)
      if ($n -eq 0) { Die 'That backup has an incomplete signature. Nothing was decrypted.' }
      $read += $n
    }
    $diff = 0
    for ($i = 0; $i -lt 32; $i++) { $diff = $diff -bor ($want[$i] -bxor $mac[$i]) }
    if ($diff -ne 0) {
      Die 'The signature does not match. Either the passphrase is wrong or the file has been changed or damaged. Nothing was decrypted.'
    }
    Say '  signature matches' 'Green'
    # Only authenticated ciphertext reaches the plaintext file. The old
    # TSBK1 format and KDF remain unchanged; memory use stays bounded.
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $kEnc; $aes.IV = $iv
    $temp = Join-Path $Work ('thornswood-restore-' + [Guid]::NewGuid().ToString('N') + '.zip')
    $outputFile = [IO.File]::Open($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $script:temp = $temp
    $decryptor = $aes.CreateDecryptor()
    $cryptoStream = [Security.Cryptography.CryptoStream]::new($outputFile, $decryptor, [Security.Cryptography.CryptoStreamMode]::Write, $true)
    $inputFile.Position = 37; $left = $cipherLen
    while ($left -gt 0) {
      $n = $inputFile.Read($chunk, 0, [int][Math]::Min([long]$chunk.Length, [long]$left))
      if ($n -eq 0) { throw 'The authenticated ciphertext ended prematurely.' }
      $cryptoStream.Write($chunk, 0, $n); $left -= $n
    }
    $cryptoStream.FlushFinalBlock(); $outputFile.Flush($true)
    $zipPath = $temp
    Say ("  decrypted to a zip of {0} MB" -f [math]::Round($outputFile.Length / 1MB, 2)) 'DarkGray'
  } catch { $operationFailure = $_; throw } finally {
    $cleanupFailure = $null
    foreach ($resource in @($cryptoStream, $decryptor, $outputFile, $inputFile, $aes, $hmac, $kdf)) {
      if ($null -ne $resource) {
        try { $resource.Dispose() } catch { if (-not $cleanupFailure) { $cleanupFailure = $_ } }
      }
    }
    if ($cleanupFailure -and -not $operationFailure) { throw $cleanupFailure }
  }
} else {
  $zipPath = $src
  Say '  not encrypted, so there is nothing to check' 'Yellow'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zf = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
$entries = @($zf.Entries)
# Either slash: which one ZipFile writes has depended on the .NET version.
$worldCount = @($entries | Where-Object { $_.FullName -match '^game[/\\]world[/\\]' }).Count
$privCount  = @($entries | Where-Object { $_.FullName -match '^game[/\\]private[/\\]' }).Count

Head 'What is in it'
Say ("  {0} entries" -f $entries.Count)
Say ("  {0,-28} {1}" -f 'game/world (characters)', $(if ($worldCount) { "$worldCount files" } else { 'NOTHING. This backup has no characters in it.' })) $(if ($worldCount) { 'Green' } else { 'Red' })
Say ("  {0,-28} {1} files" -f 'game/private', $privCount)
foreach ($top in ($entries | ForEach-Object { ($_.FullName -split '[/\\]')[0] } | Sort-Object -Unique)) {
  $n = @($entries | Where-Object { $_.FullName -like "$top/*" -or $_.FullName -like "$top\*" -or $_.FullName -eq $top }).Count
  Say ("  {0,-28} {1} entries" -f $top, $n) 'DarkGray'
}
$notes = $entries | Where-Object { $_.FullName -eq 'NOTES.txt' } | Select-Object -First 1
if ($notes) {
  Head 'NOTES.txt from the box it was taken on'
  $sr = New-Object System.IO.StreamReader($notes.Open())
  $sr.ReadToEnd() -split "`r?`n" | ForEach-Object { Say "  $_" 'DarkGray' }
  $sr.Close()
}

# A character is a numbered change form (0.json, 1.json, ...) whose profile id
# is above 0 and which is not deleted. Counting every file under game/world
# called a world of only deleted slots, or only forms that are not characters,
# a good backup (#1047). Read here, before the zip is closed, and only for
# -CheckOnly: unpacking still does not decide that, Restore-Server.ps1 does.
$living = 0
if ($CheckOnly) {
  foreach ($en in $entries) {
    if ($en.FullName -notmatch '^game[/\\]world[/\\]changeForms[/\\][0-9]+\.json$') { continue }
    $sr = $null
    $o = $null
    try {
      $sr = New-Object System.IO.StreamReader($en.Open())
      $o = (($sr.ReadToEnd()) -replace '^\uFEFF', '') | ConvertFrom-Json
    } catch { $o = $null }
    finally { if ($null -ne $sr) { $sr.Dispose() } }
    $id = 0L
    if ($null -ne $o -and $null -ne $o.profileId) { try { $id = [long]$o.profileId } catch { $id = 0L } }
    if ($id -gt 0 -and -not ($null -ne $o -and $o.isDeleted -eq $true)) { $living++ }
  }
}
$zf.Dispose()

if ($CheckOnly) {
  # A backup that opens and holds no characters is the failure this exists
  # to catch (the 15 September pair), so -CheckOnly calls it one, and
  # Fetch-Backups.ps1 and its task see a non-zero result. Files under
  # game/world are not enough: none of them may be a living character.
  if (-not $worldCount) {
    Die 'The backup opens, but there is nothing under game/world in it, so it holds no characters.'
  }
  if ($living -lt 1) {
    Die 'The backup opens, but none of the numbered change forms under game/world has a profile id above 0 that is not deleted, so it holds no characters.'
  }
  Say ("  {0} numbered change form(s) name a character" -f $living) 'Green'
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

Head 'Unpacked'
Say "  $To" 'Green'
Write-Host ''
Say '  Putting this back into a server folder is Restore-Server.ps1, which' 'DarkGray'
Say '  also checks the load order resolves; docs\RESTORING.md has the rest.' 'DarkGray'
if (-not $NoPause) { [void](Read-Host 'Enter to close') }
exit 0

} finally {
  Clear-RestoreZip
}
