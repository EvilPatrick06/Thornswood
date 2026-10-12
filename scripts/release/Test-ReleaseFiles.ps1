<#
.SYNOPSIS
  Checks the files of a launcher release draft on any machine, with no signing setup: each against SHA256SUMS, and with -RequireSigned the launcher's signature the way an installed launcher checks it (issue #2163).

.DESCRIPTION
  release.yml drafts Thornswood.exe, setup-stub.exe and SHA256SUMS for each
  v<version> tag. Since #2163 its hosted job signs the launcher there, and its
  "verify" job downloads that draft onto a VPS runner, which holds no signing
  client, no records\signing\signing.json and no Azure sign in, and runs this.
  So a signed release is accepted by a second machine on its files alone
  before anybody ships it. The same command checks a draft by hand anywhere:
  download the three files into one folder and point -Dir at it.

  The checks, in order, each printed as PASS or FAIL:
    1. SHA256SUMS is there and has exactly one line for Thornswood.exe and one
       for setup-stub.exe, and each file's sha256 is its line (the checksum
       layer stays first, as Ship has it).
    2. With -RequireSigned: the publish gate (Get-PublishSignRefusal in
       Assert-PublishSigned.ps1) accepts Thornswood.exe. That is Authenticode
       Valid, a Subject naming ExpectedSigner, and launcher\app\Signature.cs,
       the class every installed launcher uses to accept an update.
    3. With -RequireSigned: a copy with one byte changed inside what
       Authenticode hashes (the DOS stub text) is refused by both the
       checksum and the signature check, so a failed signature is a refusal
       on this very file, not only on the pilot's.
  setup-stub.exe is listed but never required to be signed: Package signs the
  finished Setup after the OneFile attach (Build-Launcher.ps1). It says which
  it is. Exit 0 only when every check holds. Reads only; writes nothing but a
  temporary copy for check 3, which it removes.

.PARAMETER Dir
  The folder holding Thornswood.exe, setup-stub.exe and SHA256SUMS.

.PARAMETER RequireSigned
  The launcher has to pass the publish gate and the launcher's own check.
  Without it only the checksums are checked and the signature is reported.

.PARAMETER ExpectedSigner
  What the signer's Subject has to contain. Without it, ExpectedSigner from
  launcher\app\Updater.cs in this checkout.

.EXAMPLE
  .\scripts\release\Test-ReleaseFiles.ps1 -Dir $env:TEMP\draft -RequireSigned
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Dir,
    [switch]$RequireSigned,
    [string]$ExpectedSigner
)
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = (Resolve-Path (Join-Path $Here '..\..')).Path
. (Join-Path $Here 'Assert-PublishSigned.ps1')

$script:fails = 0
function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host ('PASS  ' + $what) -ForegroundColor Green }
    else { Write-Host ('FAIL  ' + $what) -ForegroundColor Red; $script:fails++ }
}
function Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Finish {
    if ($script:fails) { Write-Host ("{0} check(s) failed. Do not ship these files." -f $script:fails) -ForegroundColor Red; exit 1 }
    Write-Host 'release files OK' -ForegroundColor Green
    exit 0
}

$exe = Join-Path $Dir 'Thornswood.exe'
$stub = Join-Path $Dir 'setup-stub.exe'
$sums = Join-Path $Dir 'SHA256SUMS'
foreach ($p in $exe, $stub, $sums) { Check (Test-Path -LiteralPath $p) ((Split-Path -Leaf $p) + ' is there') }
if ($script:fails) { Finish }

# 1. Each file against its one line, "<sha256>  <name>" (sha256sum's shape).
$lines = @([IO.File]::ReadAllLines($sums) | Where-Object { $_.Trim() })
foreach ($p in $exe, $stub) {
    $n = Split-Path -Leaf $p
    $hits = @($lines | ForEach-Object { [regex]::Match($_, ('(?i)^\s*([0-9a-f]{64})\s+\*?' + [regex]::Escape($n) + '\s*$')) } | Where-Object { $_.Success })
    Check ($hits.Count -eq 1) ("SHA256SUMS has one line for $n (found " + $hits.Count + ')')
    if ($hits.Count -eq 1) {
        $want = $hits[0].Groups[1].Value.ToLowerInvariant()
        $have = Sha $p
        Check ($have -eq $want) ("$n is the file SHA256SUMS names (" + $have + ')')
    }
}

$exeSig = Get-AuthenticodeSignature -LiteralPath $exe
$stubSig = Get-AuthenticodeSignature -LiteralPath $stub
$who = if ($exeSig.SignerCertificate) { $exeSig.SignerCertificate.Subject } else { 'nobody' }
Write-Host ('      Thornswood.exe Authenticode: ' + $exeSig.Status + ', signed by ' + $who)
Write-Host ('      setup-stub.exe Authenticode: ' + $stubSig.Status + ' (Package signs the finished Setup, not this)')

if ($RequireSigned) {
    if (-not $ExpectedSigner) { $ExpectedSigner = Get-ExpectedSignerFragment -RepoRoot $Repo }
    # 2. The publish gate and the launcher's own check.
    $why = Get-PublishSignRefusal -Path $exe -ExpectedSigner $ExpectedSigner
    Check (-not $why) ('the publish gate and the launcher''s Signature.cs accept Thornswood.exe' + $(if ($why) { ': ' + $why } else { '' }))
    if ($why) { Finish }
    # 3. One byte changed where Authenticode hashes: refused by both checks.
    # Offset 0x4E is the DOS stub text. A byte in the signature blob itself
    # is outside the hash and proves nothing (docs\SIGNED-RELEASES.md 7).
    # Only for a launcher check 2 accepted: on one it refused, there is no
    # signature for a changed byte to break.
    $bad = Join-Path ([IO.Path]::GetTempPath()) ('release-files-tampered-' + [guid]::NewGuid().ToString('N') + '.exe')
    try {
        $b = [IO.File]::ReadAllBytes($exe); $b[0x4E] = $b[0x4E] -bxor 0xFF
        [IO.File]::WriteAllBytes($bad, $b)
        Check ((Sha $bad) -ne (Sha $exe)) 'a one byte change fails the checksum'
        Check ([bool](Get-PublishSignRefusal -Path $bad -ExpectedSigner $ExpectedSigner)) 'a one byte change fails the signature check'
    } finally { Remove-Item -LiteralPath $bad -Force -ErrorAction SilentlyContinue }
}
Finish
