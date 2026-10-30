<#
  Sealed.ps1

  The seal a workflow puts on what it sends back to the session that started
  it, for scripts\vps\Box-Run.ps1 (the deploy gate) and
  scripts\release\Nexus-Run.ps1 (the Nexus scripts), both #2841. Each
  dot-sources this. PowerShell 7 only (AesGcm).

      . (Join-Path $PSScriptRoot 'Sealed.ps1')

  WHY. Once the repository is public, anyone can read a run's log and
  download its artifacts. A deploy's output, the servers' logs and what the
  Nexus scripts print are not for them. So the session makes a key for that
  run alone and sends only its public half; the runner seals the output to it
  and uploads the sealed file; only the private half, which never leaves the
  session's scratch folder, opens it.

  THE FORMAT. "TWSEAL1", the wrapped key's length (2 bytes, big end first),
  the AES key wrapped with RSA-OAEP-SHA256, the 12 byte nonce, the 16 byte
  tag, then the zip encrypted with AES-256-GCM. A recipient key under 3072
  bits is refused.
#>

# A key for one run: Public goes with the run, Private stays in the session.
function New-ThornswoodSealKey {
    $rsa = [Security.Cryptography.RSA]::Create(3072)
    return [pscustomobject]@{
        Public  = [Convert]::ToBase64String($rsa.ExportSubjectPublicKeyInfo())
        Private = [Convert]::ToBase64String($rsa.ExportPkcs8PrivateKey())
    }
}

function Protect-ThornswoodSealed([byte[]]$Plain, [string]$RecipientB64) {
    $rsa = [Security.Cryptography.RSA]::Create()
    $read = 0
    $rsa.ImportSubjectPublicKeyInfo([Convert]::FromBase64String($RecipientB64), [ref]$read)
    if ($rsa.KeySize -lt 3072) { throw ('the recipient key is ' + $rsa.KeySize + ' bits, under 3072') }
    $key = New-Object byte[] 32; $nonce = New-Object byte[] 12; $tag = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Fill($key); [Security.Cryptography.RandomNumberGenerator]::Fill($nonce)
    $cipher = New-Object byte[] $Plain.Length
    $gcm = [Security.Cryptography.AesGcm]::new($key, 16)
    $gcm.Encrypt($nonce, $Plain, $cipher, $tag)
    $wrapped = $rsa.Encrypt($key, [Security.Cryptography.RSAEncryptionPadding]::OaepSHA256)
    $ms = New-Object IO.MemoryStream
    $head = [Text.Encoding]::ASCII.GetBytes('TWSEAL1')
    $ms.Write($head, 0, $head.Length)
    $ms.WriteByte([byte]($wrapped.Length -shr 8)); $ms.WriteByte([byte]($wrapped.Length -band 255))
    foreach ($b in $wrapped, $nonce, $tag, $cipher) { $ms.Write($b, 0, $b.Length) }
    return $ms.ToArray()
}

function Unprotect-ThornswoodSealed([byte[]]$Sealed, [string]$PrivateB64) {
    $head = [Text.Encoding]::ASCII.GetString($Sealed, 0, 7)
    if ($head -ne 'TWSEAL1') { throw 'the sealed file is not one a Thornswood run made' }
    $n = ([int]$Sealed[7] -shl 8) + [int]$Sealed[8]
    $at = 9
    $wrapped = $Sealed[$at..($at + $n - 1)]; $at += $n
    $nonce = $Sealed[$at..($at + 11)]; $at += 12
    $tag = $Sealed[$at..($at + 15)]; $at += 16
    $cipher = if ($at -lt $Sealed.Length) { [byte[]]$Sealed[$at..($Sealed.Length - 1)] } else { [byte[]]@() }
    $rsa = [Security.Cryptography.RSA]::Create()
    $read = 0
    $rsa.ImportPkcs8PrivateKey([Convert]::FromBase64String($PrivateB64), [ref]$read)
    $key = $rsa.Decrypt([byte[]]$wrapped, [Security.Cryptography.RSAEncryptionPadding]::OaepSHA256)
    $plain = New-Object byte[] $cipher.Length
    $gcm = [Security.Cryptography.AesGcm]::new($key, 16)
    $gcm.Decrypt([byte[]]$nonce, $cipher, [byte[]]$tag, $plain)
    return $plain
}

# The runner's half: zips everything in $Folder (output.txt and files\),
# seals it to $RecipientB64 and writes it to $To. Returns how many files went.
function Save-ThornswoodSealed([string]$Folder, [string]$RecipientB64, [string]$To) {
    $zip = $Folder.TrimEnd('\', '/') + '.zip'
    Compress-Archive -Path (Join-Path $Folder '*') -DestinationPath $zip -Force
    try {
        $sealed = Protect-ThornswoodSealed ([IO.File]::ReadAllBytes($zip)) $RecipientB64
        New-Item -ItemType Directory -Path (Split-Path -Parent $To) -Force | Out-Null
        [IO.File]::WriteAllBytes($To, $sealed)
    }
    finally { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
    return @(Get-ChildItem -LiteralPath (Join-Path $Folder 'files') -Recurse -File -ErrorAction SilentlyContinue).Count
}

# The session's half: downloads artifact $Artifact of run $Run, opens its
# $File with the key at $KeyPath into $Into (output.txt and files\). Returns
# @{ Ok; Why }; Why says what gh said when there was nothing to open.
function Open-ThornswoodSealedRun {
    param([string]$Repo, [long]$Run, [string]$Artifact, [string]$File, [string]$KeyPath, [string]$Into)
    $dl = $Into.TrimEnd('\', '/') + '.download'
    Remove-Item -LiteralPath $dl -Recurse -Force -ErrorAction SilentlyContinue
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $got = @(& gh run download $Run -R $Repo -n $Artifact -D $dl 2>&1 | ForEach-Object { "$_" })
    $ErrorActionPreference = $old
    $sealedFile = Join-Path $dl $File
    if (-not (Test-Path -LiteralPath $sealedFile)) {
        Remove-Item -LiteralPath $dl -Recurse -Force -ErrorAction SilentlyContinue
        return @{ Ok = $false; Why = (($got | Select-Object -Last 1) -join '') }
    }
    $plain = Unprotect-ThornswoodSealed ([IO.File]::ReadAllBytes($sealedFile)) ([IO.File]::ReadAllText($KeyPath).Trim())
    Remove-Item -LiteralPath $Into -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $Into -Force | Out-Null
    $zip = Join-Path $Into 'out.zip'
    [IO.File]::WriteAllBytes($zip, $plain)
    Expand-Archive -LiteralPath $zip -DestinationPath $Into -Force
    Remove-Item -LiteralPath $zip, $dl -Recurse -Force -ErrorAction SilentlyContinue
    return @{ Ok = $true; Why = '' }
}
