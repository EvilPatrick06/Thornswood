<#
  Protect-BackupZip.ps1

  Protect-ThornswoodBackupZip encrypts a backup zip into the TSBK1 file the
  nightly backup writes (vps-nightly-backup.ps1, "encrypt"), the one format
  Restore-Backup.ps1 opens: "TSBK1", a 16 byte salt, a 16 byte IV, the zip in
  AES-256-CBC, then an HMAC-SHA256 over everything after the five letters. The
  two keys come out of the backup passphrase through PBKDF2-SHA256, 200,000
  rounds.

  Backup-Server.ps1 sends this text to the box ahead of its own and runs it on
  the zip it makes there, so the whole-server copy it brings down is
  encrypted like every other copy, and nothing plain ever leaves the box
  (#3582). Until then it brought down a plain zip of the site's sign-ins, the
  bot's and voice's folders whole (voice chat included) and every character,
  which nothing deleted.

  Writes <Enc>.<guid>.partial and renames it to Enc only once it is whole, so
  a run cut short never leaves a file that looks like a backup. Enc must not
  already be there. tests\test-3582-manual-backup.ps1 opens what this writes
  with Restore-Backup.ps1.
#>
function Protect-ThornswoodBackupZip {
  param(
    [Parameter(Mandatory = $true)][string]$Zip,
    [Parameter(Mandatory = $true)][string]$Enc,
    [Parameter(Mandatory = $true)][string]$Pass
  )
  $partial = $Enc + '.' + [Guid]::NewGuid().ToString('N') + '.partial'
  $rng = $null; $kdf = $null; $aes = $null; $hmac = $null
  $inputFile = $null; $outputFile = $null; $cryptoStream = $null; $encryptor = $null
  $partialOwned = $false; $operationFailure = $null
  try {
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $salt = New-Object byte[] 16; $rng.GetBytes($salt)
    $iv = New-Object byte[] 16; $rng.GetBytes($iv)
    $kdf = [Security.Cryptography.Rfc2898DeriveBytes]::new($Pass, $salt, 200000, [Security.Cryptography.HashAlgorithmName]::SHA256)
    $kEnc = $kdf.GetBytes(32); $kMac = $kdf.GetBytes(32)
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256; $aes.Mode = 'CBC'; $aes.Padding = 'PKCS7'; $aes.Key = $kEnc; $aes.IV = $iv
    $outputFile = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $partialOwned = $true
    $magic = [Text.Encoding]::ASCII.GetBytes('TSBK1')
    $outputFile.Write($magic, 0, 5); $outputFile.Write($salt, 0, 16); $outputFile.Write($iv, 0, 16)
    $encryptor = $aes.CreateEncryptor()
    $cryptoStream = [Security.Cryptography.CryptoStream]::new($outputFile, $encryptor, [Security.Cryptography.CryptoStreamMode]::Write, $true)
    $inputFile = [IO.File]::OpenRead($Zip)
    $inputFile.CopyTo($cryptoStream); $cryptoStream.FlushFinalBlock()
    $cryptoStream.Dispose(); $cryptoStream = $null
    $inputFile.Dispose(); $inputFile = $null
    $hmac = [Security.Cryptography.HMACSHA256]::new($kMac)
    $outputFile.Position = 5
    $left = $outputFile.Length - 5
    $chunk = New-Object byte[] 1MB
    while ($left -gt 0) {
      $n = $outputFile.Read($chunk, 0, [int][Math]::Min([long]$chunk.Length, [long]$left))
      if ($n -eq 0) { throw 'The encrypted copy ended before its signature was complete.' }
      [void]$hmac.TransformBlock($chunk, 0, $n, $chunk, 0); $left -= $n
    }
    [void]$hmac.TransformFinalBlock([byte[]]@(), 0, 0)
    $mac = $hmac.Hash; $outputFile.Write($mac, 0, $mac.Length)
    $outputFile.Flush($true); $outputFile.Dispose(); $outputFile = $null
    [IO.File]::Move($partial, $Enc)
    $partialOwned = $false
  } catch { $operationFailure = $_; throw } finally {
    $cleanupFailure = $null
    foreach ($resource in @($cryptoStream, $encryptor, $inputFile, $outputFile, $hmac, $aes, $kdf, $rng)) {
      if ($null -ne $resource) {
        try { $resource.Dispose() } catch { if (-not $cleanupFailure) { $cleanupFailure = $_ } }
      }
    }
    if ($partialOwned -and (Test-Path -LiteralPath $partial)) {
      try { Remove-Item -LiteralPath $partial -Force } catch { if (-not $cleanupFailure) { $cleanupFailure = $_ } }
    }
    if ($cleanupFailure -and -not $operationFailure) { throw $cleanupFailure }
  }
}
