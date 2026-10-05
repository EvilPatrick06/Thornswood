<#
  test-signer-check.ps1

      pwsh -NoProfile -File .\tests\test-signer-check.ps1
      pwsh -NoProfile -File .\tests\test-signer-check.ps1 -Signed <a signed Thornswood.exe>

  The check a launcher runs on a downloaded launcher before it swaps it in
  (launcher\app\Signature.cs, called by Updater.CheckSigner), pointed at real
  files.

  WHY THIS EXISTS. Issue #912. Until then the check read the Subject of the
  embedded certificate (X509Certificate.CreateFromSignedFile) and looked for
  the signer's name in it. That call verifies nothing, so a certificate anybody
  can make on their own machine with that name passed. This proves the new
  check on each file it has to decide:

    accepted  the real signed dev launcher (by default
              C:\Thornswood-DevBuild\Launcher\Thornswood.exe), and a copy of
              it in another folder.
    refused   an unsigned exe; the same exe signed with a self-made
              certificate named as the signer, and with one that also copies
              every usage Thornswood's real certificate carries; a program
              validly signed by another publisher (csc.exe); a program signed
              through Artifact Signing by another publisher (Git for
              Windows), even asked for its own name; the real launcher with one
              byte changed; the real launcher asked for another identity or
              another name.

  For the self-made certificate it also runs the old Subject read, to show
  that one passed (the bug this closes).

  Issue #1330: Signature.MicrosoftRefusal, which Voice asks before it runs
  the WebView2 installer it downloads, is pointed at the same files. It
  refuses all of them, and an installer signed with a self-made certificate
  named Microsoft Corporation. A program on this machine that Microsoft
  signed (Edge, its updater, the WebView2 runtime, csc.exe) is accepted when
  the chain Windows builds for it ends at Microsoft's own root and names
  Microsoft Corporation, and refused otherwise.

  The self-made certificates are made with New-SelfSignedCertificate in the
  CurrentUser store, used once, and removed from every CurrentUser store
  before this ends, whatever happens. Nothing is trusted, nothing is written
  outside its own temp folder, and nothing touches the network except what
  Windows itself asks for to check revocation.

  When the signed launcher is not on this machine (the VPS), the cases that
  need it say SKIP and are not counted; the refusals are still proved.

  It also runs scripts\release\Assert-PublishSigned.ps1's gate on the same
  files, because Ship and Publish-Installer must refuse whatever the launcher
  would.

  Runs under Windows PowerShell 5.1, and restarts itself there from pwsh: the
  launcher runs on the .NET Framework.
#>
[CmdletBinding()]
param([string]$Signed = 'C:\Thornswood-DevBuild\Launcher\Thornswood.exe')

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core') {
    $winps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $winps)) {
        Write-Host 'FAIL  Windows PowerShell is here to run this on the .NET Framework the launcher runs on'
        Write-Host ''
        Write-Host '0 passed, 1 failed'
        exit 1
    }
    & $winps -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Signed $Signed
    exit $LASTEXITCODE
}

$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$App = Join-Path $Repo 'launcher\app'
# The name on the signing certificate, read from the one place it is written,
# ExpectedSigner in launcher\app\Updater.cs, so no other file carries it (#1052).
$Signer = ''
$m = [regex]::Match([IO.File]::ReadAllText((Join-Path $App 'Updater.cs')), 'const string ExpectedSigner = "([^"]+)"')
if ($m.Success) { $Signer = $m.Groups[1].Value }
if (-not $Signer) { Write-Host 'FAIL  ExpectedSigner could not be read from launcher\app\Updater.cs'; exit 1 }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Skip([string]$what) { Write-Host "SKIP  $what" }
function Finish {
    Write-Host ''
    Write-Host "$($script:pass) passed, $($script:fail) failed"
    if ($script:fail) { exit 1 }
    exit 0
}

# ---- the sources say what they should ---------------------------------------
$sigCs = Join-Path $App 'Signature.cs'
Yes 'launcher\app\Signature.cs exists' (Test-Path -LiteralPath $sigCs)
if (-not (Test-Path -LiteralPath $sigCs)) { Finish }
$sigSrc = [IO.File]::ReadAllText($sigCs)
$upd = [IO.File]::ReadAllText((Join-Path $App 'Updater.cs'))
Yes 'Signature.cs has no C# 6: no $", no ?., no nameof' (-not ($sigSrc -match '\$"|\?\.|nameof\('))
Yes 'Signature.cs asks WinVerifyTrust with WINTRUST_ACTION_GENERIC_VERIFY_V2' (
    $sigSrc -match 'WinVerifyTrust' -and $sigSrc -match '00AAC56B-CD44-11d0-8CC2-00C04FC295EE')
Yes 'Updater.CheckSigner goes through Signature.Refusal' ($upd -match 'Signature\.Refusal\(path, ExpectedSigner, out said\)')
Yes 'nothing in the launcher decides a signer from CreateFromSignedFile any more' (
    -not (@(Get-ChildItem (Join-Path $App '*.cs') | Where-Object {
        [IO.File]::ReadAllText($_.FullName) -match 'CreateFromSignedFile\s*\(' }).Count))

# ---- compile Signature.cs on its own ----------------------------------------
$csc = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
Yes 'the .NET Framework 4 csc is on this machine' ([bool]$csc)
if (-not $csc) { Finish }
$fw = Split-Path -Parent $csc

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tssigner-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Force -Path $tmp
$made = @()

function Compile([string[]]$cscArgs) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $said = & $csc @cscArgs 2>&1
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    if ($rc -ne 0) { foreach ($l in @($said | Select-Object -First 20)) { Write-Host "      $l" } }
    return ($rc -eq 0)
}

function Drop-Cert([string]$thumb) {
    foreach ($store in 'My', 'CA', 'Root', 'TrustedPublisher', 'Disallowed') {
        $p = "Cert:\CurrentUser\$store\$thumb"
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
}

try {
    $dll = Join-Path $tmp 'Signature.dll'
    $ok = Compile @('/noconfig', '/nologo', '/langversion:5', '/target:library', '/platform:anycpu',
                    "/reference:$fw\System.dll", "/out:$dll", $sigCs)
    Yes 'Signature.cs compiles on its own with the .NET Framework csc at C# 5' $ok
    if (-not $ok) { Finish }
    $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
    $S = $asm.GetType('Thornswood.Signature')
    $flags = [Reflection.BindingFlags]'Static, Public'
    $three = $S.GetMethod('Refusal', $flags, $null,
        [Type[]]@([string], [string], [string].MakeByRefType()), $null)
    $four = $S.GetMethod('Refusal', $flags, $null,
        [Type[]]@([string], [string], [string[]], [string].MakeByRefType()), $null)
    Yes 'Signature.Refusal is there, with and without an identity list' ($null -ne $three -and $null -ne $four)
    $ids = [string[]]$S.GetField('Identities').GetValue($null)

    function Check([string]$path, [string]$who) {
        $a = [object[]]@($path, $who, $null)
        $why = [string]$three.Invoke($null, $a)
        return @{ Why = $why; Said = [string]$a[2] }
    }
    function CheckAs([string]$path, [string]$who, [string[]]$idList) {
        $a = [object[]]@($path, $who, $idList, $null)
        return [string]$four.Invoke($null, $a)
    }
    # What the launcher did before #912, kept here only to show it passed.
    function OldCheck([string]$path, [string]$who) {
        try {
            $c = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($path)
            return ($c.Subject.IndexOf($who, [StringComparison]::OrdinalIgnoreCase) -ge 0)
        } catch { return $false }
    }

    . (Join-Path $Repo 'scripts\release\Assert-PublishSigned.ps1')

    # ---- a real signed launcher is accepted --------------------------------
    $haveSigned = $Signed -and (Test-Path -LiteralPath $Signed)
    if ($haveSigned) {
        $r = Check $Signed $Signer
        Yes ('the real signed launcher is accepted: ' + $(if ($r.Why) { $r.Why } else { $r.Said })) ($r.Why -eq '')
        Yes 'the log line says who signed it and that it is timestamped' (
            $r.Said -match [regex]::Escape($Signer) -and $r.Said -match 'Artifact Signing' -and $r.Said -match 'timestamped')
        $copy = Join-Path $tmp 'elsewhere\Thornswood.exe'
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $copy)
        Copy-Item -LiteralPath $Signed -Destination $copy
        $r = Check $copy $Signer
        Yes 'a copy of it in another folder is accepted' ($r.Why -eq '')
        $g = Get-PublishSignRefusal -Path $Signed -ExpectedSigner $Signer
        Yes ('the publish gate accepts it too' + $(if ($g) { ': ' + $g } else { '' })) ($g -eq '')

        $r = Check $Signed 'Somebody Else'
        Yes ('asked for another name, it is refused: ' + $r.Why) ($r.Why -match 'does not name Somebody Else')
        $why = CheckAs $Signed $Signer @('1.3.6.1.4.1.311.97.1.2.3.4')
        Yes ('asked for another identity, it is refused: ' + $why) ($why -match "somebody else's identity")

        # One byte in the middle of the file, well before the signature at its end.
        $flip = Join-Path $tmp 'flipped\Thornswood.exe'
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $flip)
        $bytes = [IO.File]::ReadAllBytes($Signed)
        $at = [int]($bytes.Length / 3)
        $bytes[$at] = $bytes[$at] -bxor 0xFF
        [IO.File]::WriteAllBytes($flip, $bytes)
        $r = Check $flip $Signer
        Yes ('the real launcher with one byte changed is refused: ' + $r.Why) ($r.Why -match 'changed since it was signed')
        Yes 'the old Subject read would have passed the changed file' (OldCheck $flip $Signer)
        $g = Get-PublishSignRefusal -Path $flip -ExpectedSigner $Signer
        Yes 'the publish gate refuses the changed file' ($g -ne '')
    } else {
        Skip "no signed launcher at $Signed on this machine: accepted, byte changed and another identity not run"
    }

    # ---- an unsigned exe is refused ----------------------------------------
    $stubCs = Join-Path $tmp 'stub.cs'
    [IO.File]::WriteAllText($stubCs, 'static class P { static void Main() { } }')
    $stub = Join-Path $tmp 'unsigned\Thornswood.exe'
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stub)
    $ok = Compile @('/noconfig', '/nologo', '/target:exe', "/out:$stub", $stubCs)
    Yes 'a stand-in exe compiles' $ok
    if ($ok) {
        $r = Check $stub $Signer
        Yes ('an unsigned exe is refused: ' + $r.Why) ($r.Why -eq 'is not signed.')
    }
    $junk = Join-Path $tmp 'junk\Thornswood.exe'
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $junk)
    [IO.File]::WriteAllBytes($junk, [byte[]](0x4D, 0x5A, 0, 0, 0, 0, 0, 0))
    $r = Check $junk $Signer
    Yes ('a file that is not a program is refused: ' + $r.Why) ($r.Why -ne '')
    $r = Check (Join-Path $tmp 'gone.exe') $Signer
    Yes ('a missing file is refused: ' + $r.Why) ($r.Why -match 'could not be opened')

    # ---- self-made certificates named as the signer are refused ------------
    if ($ok -and (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
        $plain = New-SelfSignedCertificate -Type CodeSigningCert -Subject ('CN=' + $Signer + ', O=' + $Signer + ', C=US') `
                    -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddDays(2)
        $made += $plain.Thumbprint
        # Every usage the real one carries, Thornswood's durable identity included.
        $eku = '2.5.29.37={text}1.3.6.1.5.5.7.3.3,1.3.6.1.4.1.311.97.1.0,' + $ids[0]
        $forged = New-SelfSignedCertificate -Type Custom -Subject ('CN=' + $Signer + ', O=' + $Signer + ', C=US') `
                    -KeyUsage DigitalSignature -TextExtension @($eku) `
                    -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddDays(2)
        $made += $forged.Thumbprint

        foreach ($pair in @(@('self', $plain, 'a self-made certificate named as the signer'),
                            @('forged', $forged, "a self-made certificate with Thornswood's name and every usage its real one has"))) {
            $f = Join-Path $tmp ($pair[0] + '\Thornswood.exe')
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f)
            Copy-Item -LiteralPath $stub -Destination $f
            $null = Set-AuthenticodeSignature -LiteralPath $f -Certificate $pair[1] -HashAlgorithm SHA256
            $on = (Get-AuthenticodeSignature -LiteralPath $f).SignerCertificate
            Yes ('the exe signed with ' + $pair[2] + ' carries that signature') ($null -ne $on -and $on.Thumbprint -eq $pair[1].Thumbprint)
            Yes ('the old Subject read would have accepted ' + $pair[2] + ' (#912)') (OldCheck $f $Signer)
            $r = Check $f $Signer
            Yes ('signed with ' + $pair[2] + ', it is refused: ' + $r.Why) ($r.Why -match 'does not trust')
            $g = Get-PublishSignRefusal -Path $f -ExpectedSigner $Signer
            Yes ('the publish gate refuses ' + $pair[2]) ($g -ne '')
        }
    } else {
        Yes 'New-SelfSignedCertificate is here to make the self-made certificate' $false
    }

    # ---- a program validly signed by another publisher is refused ------------
    $other = $null
    $candidates = @(
        (Join-Path $fw 'csc.exe'),
        (Join-Path $fw 'MSBuild.exe'),
        (Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'),
        (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe')
    )
    foreach ($c in $candidates) {
        if (-not (Test-Path -LiteralPath $c)) { continue }
        # $sig, not $s: PowerShell names are not case sensitive, and $s is $S,
        # the Signature type that MicrosoftRefusal is read from further down.
        $sig = Get-AuthenticodeSignature -LiteralPath $c
        # Embedded, not from a catalog: a catalog signature is not in the file.
        $embedded = $false
        try { $null = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($c); $embedded = $true } catch { $embedded = $false }
        if ($sig.Status -eq 'Valid' -and $embedded) { $other = $c; break }
    }
    if ($other) {
        $r = Check $other $Signer
        Yes ('a program validly signed by Microsoft (' + (Split-Path -Leaf $other) + ') is refused: ' + $r.Why) ($r.Why -ne '')
        $r = Check $other 'Microsoft'
        Yes ('it is refused even when asked for its own name, because it is not Thornswood''s identity: ' + $r.Why) ($r.Why -ne '')
    } else {
        Yes 'a program validly signed by another publisher is on this machine' $false
    }

    # ---- another publisher signed through Artifact Signing too ---------------
    # The hardest one: same root, same kind of authority, same usages. Only
    # the durable identity tells it apart, and asked for its own name it has
    # to be refused all the same. Git for Windows is signed this way (MEASURED
    # 28 SEP: CN=Johannes Schindelin, issued by Microsoft ID Verified CS).
    $peer = $null
    foreach ($c in @((Join-Path $env:ProgramFiles 'Git\git-bash.exe'), (Join-Path $env:ProgramFiles 'Git\cmd\git.exe'))) {
        if (-not (Test-Path -LiteralPath $c)) { continue }
        try {
            $pc = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($c)
            if ($pc.Issuer -like 'CN=Microsoft ID Verified CS *' -and $pc.Subject -notlike ('*' + $Signer + '*')) { $peer = $c; break }
        } catch { $peer = $null }
    }
    if ($peer) {
        $pc = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($peer)
        $peerName = ([regex]::Match($pc.Subject, 'CN=([^,]+)')).Groups[1].Value
        $r = Check $peer $Signer
        Yes ('another publisher''s Artifact Signing program (' + $peer + ') is refused: ' + $r.Why) (
            $r.Why -match "somebody else's identity")
        $r = Check $peer $peerName
        Yes ('it is refused even when asked for its own name, ' + $peerName + ', because only the identity decides: ' + $r.Why) (
            $r.Why -match "somebody else's identity")
    } else {
        Skip 'no program signed through Artifact Signing by another publisher on this machine (Git for Windows is one)'
    }

    # ---- Microsoft's own programs (issue #1330) --------------------------------
    # Signature.MicrosoftRefusal, which Voice asks before it runs the WebView2
    # installer it downloads. Everything above that is not a program Microsoft
    # signed under its own root is refused by it too, and a program on this
    # machine that Microsoft did sign is accepted or refused by where the chain
    # Windows builds for it ends.
    $ms = $S.GetMethod('MicrosoftRefusal', $flags, $null, [Type[]]@([string], [string].MakeByRefType()), $null)
    Yes 'Signature.MicrosoftRefusal is there' ($null -ne $ms)
    if ($ms) {
        $msRoot = [string]$S.GetField('MicrosoftRoot').GetValue($null)
        $msName = [string]$S.GetField('MicrosoftSigner').GetValue($null)
        function MsCheck([string]$path) {
            $a = [object[]]@($path, $null)
            $why = [string]$ms.Invoke($null, $a)
            return @{ Why = $why; Said = [string]$a[1] }
        }

        if ($haveSigned) {
            $r = MsCheck $Signed
            Yes ('Thornswood''s own signed launcher is not Microsoft''s program: ' + $r.Why) ($r.Why -match "not under Microsoft's own root")
            $r = MsCheck $flip
            Yes ('with one byte changed it is refused for that first: ' + $r.Why) ($r.Why -match 'changed since it was signed')
        }
        if ($ok) {
            $r = MsCheck $stub
            Yes ('MicrosoftRefusal refuses an unsigned exe: ' + $r.Why) ($r.Why -eq 'is not signed.')
        }
        $r = MsCheck $junk
        Yes ('MicrosoftRefusal refuses a file that is not a program: ' + $r.Why) ($r.Why -ne '')
        $r = MsCheck (Join-Path $tmp 'gone.exe')
        Yes ('MicrosoftRefusal refuses a missing file: ' + $r.Why) ($r.Why -match 'could not be opened')
        if ($peer) {
            $r = MsCheck $peer
            Yes ('another publisher''s Artifact Signing program is not Microsoft''s: ' + $r.Why) ($r.Why -match "not under Microsoft's own root")
        }
        if ($ok -and (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
            $fake = New-SelfSignedCertificate -Type CodeSigningCert -Subject ('CN=' + $msName + ', O=' + $msName + ', C=US') `
                        -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddDays(2)
            $made += $fake.Thumbprint
            $f = Join-Path $tmp 'msfake\MicrosoftEdgeWebview2Setup.exe'
            $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f)
            Copy-Item -LiteralPath $stub -Destination $f
            $null = Set-AuthenticodeSignature -LiteralPath $f -Certificate $fake -HashAlgorithm SHA256
            $r = MsCheck $f
            Yes ('an installer signed with a self-made certificate named ' + $msName + ' is refused: ' + $r.Why) ($r.Why -match 'does not trust')
        }

        $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
        $mine = @()
        foreach ($c in @((Join-Path $pf86 'Microsoft\Edge\Application\msedge.exe'),
                         (Join-Path $pf86 'Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe'),
                         (Join-Path $fw 'csc.exe'))) {
            if (Test-Path -LiteralPath $c) { $mine += $c }
        }
        $wv = @(Get-ChildItem -Path (Join-Path $pf86 'Microsoft\EdgeWebView\Application\*\msedgewebview2.exe') -ErrorAction SilentlyContinue)
        if ($wv.Count) { $mine += $wv[0].FullName }
        $accepted = 0
        foreach ($c in $mine) {
            $sc = (Get-AuthenticodeSignature -LiteralPath $c).SignerCertificate
            # Embedded, not from a catalog: a catalog signature is not in the file.
            $embedded = $false
            try { $null = [Security.Cryptography.X509Certificates.X509Certificate]::CreateFromSignedFile($c); $embedded = $true } catch { $embedded = $false }
            if (-not $sc -or -not $embedded) { continue }
            $ch = New-Object Security.Cryptography.X509Certificates.X509Chain
            $ch.ChainPolicy.RevocationMode = 'NoCheck'
            $null = $ch.Build($sc)
            $top = $ch.ChainElements[$ch.ChainElements.Count - 1].Certificate
            $theirs = ($top.Thumbprint -eq $msRoot) -and ($sc.GetNameInfo('SimpleName', $false) -eq $msName)
            $r = MsCheck $c
            if ($theirs) {
                $accepted++
                Yes ((Split-Path -Leaf $c) + ', signed by ' + $msName + ' under Microsoft''s own root, is accepted: ' + $(if ($r.Why) { $r.Why } else { $r.Said })) ($r.Why -eq '')
            } else {
                Yes ((Split-Path -Leaf $c) + ', signed for ' + $sc.Subject + ' under ' + $top.Subject + ', is refused: ' + $r.Why) ($r.Why -ne '')
            }
        }
        if (-not $accepted) { Skip 'no program Microsoft signed under its own root on this machine (Edge, its updater and the WebView2 runtime are): accepted not run' }
    }
}
finally {
    foreach ($t in $made) { Drop-Cert $t }
    $left = @($made | Where-Object {
        $t = $_
        @('My', 'CA', 'Root', 'TrustedPublisher') | Where-Object { Test-Path -LiteralPath "Cert:\CurrentUser\$_\$t" }
    })
    if ($made.Count) { Yes ('the ' + $made.Count + ' self-made certificates are gone from every CurrentUser store') ($left.Count -eq 0) }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Finish
