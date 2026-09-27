<#
  Assert-PublishSigned.ps1

  Helpers for the publish sign gate. Dot-source this from Ship.ps1 and
  Publish-Installer.ps1. Do not call it as a standalone entry: it only
  defines functions.

  WHY. Since 27 September launchers from ExpectedSigner on refuse an update
  that is not signed by that certificate (CONTRIBUTING, issue #390). Build and
  Package may still leave a local binary unsigned: Sign-Artifact.ps1 prints
  "not signing" and exits 0 when tools\signing.json is missing or disabled.
  That soft skip must not reach the site or the feed. Ship and Publish-
  Installer refuse instead.

  SCOPE. Site and feed publish only. Local Build-Launcher and Package
  -NoPublish stay soft. Build-Launcher still signs Thornswood.exe only and
  leaves setup-stub unsigned so OneFile attach can be signed afterwards (#813).
#>

function Get-ExpectedSignerFragment {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $cs = Join-Path $RepoRoot 'launcher\app\Updater.cs'
    if (-not (Test-Path -LiteralPath $cs)) {
        throw "launcher\app\Updater.cs is missing under $RepoRoot; cannot read ExpectedSigner"
    }
    $raw = [IO.File]::ReadAllText($cs)
    $m = [regex]::Match($raw, 'ExpectedSigner\s*=\s*"([^"]+)"')
    if (-not $m.Success -or [string]::IsNullOrWhiteSpace($m.Groups[1].Value)) {
        throw "ExpectedSigner is not set in launcher\app\Updater.cs"
    }
    return $m.Groups[1].Value.Trim()
}

function Get-SigningConfigRefusal {
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [string]$RepoRoot
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return ('There is no tools\signing.json on this machine. Only a signing machine may Ship, ' +
                'dev included (CONTRIBUTING). Nothing was published.')
    }

    $cfg = $null
    try {
        $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    } catch {
        return ('tools\signing.json is not valid JSON: ' + $_.Exception.Message +
                ' Nothing was published.')
    }

    if ($null -ne $cfg.enabled -and -not $cfg.enabled) {
        return ('tools\signing.json has "enabled": false. Only a signing machine may Ship, ' +
                'dev included (CONTRIBUTING). Nothing was published.')
    }

    $m = if ($cfg.metadata) { [string]$cfg.metadata } else { '' }
    if ($m -and $RepoRoot -and -not [IO.Path]::IsPathRooted($m)) {
        $m = Join-Path $RepoRoot $m
    }
    if ($m -and (Test-Path -LiteralPath $m)) {
        $meta = $null
        try { $meta = Get-Content -LiteralPath $m -Raw | ConvertFrom-Json } catch { $meta = $null }
        $profName = if ($meta -and $meta.CertificateProfileName) { [string]$meta.CertificateProfileName } else { '' }
        if (-not $profName -or $profName -match 'FILL THIS IN|YOUR_|<|\s') {
            return ('the certificate profile in ' + $m + ' is not filled in yet. ' +
                    'Only a signing machine may Ship. Nothing was published.')
        }
    }

    return ''
}

function Get-PublishSignRefusal {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSigner
    )

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return ("missing file to check for a publish signature: $Path")
    }

    $sig = $null
    try {
        $sig = Get-AuthenticodeSignature -LiteralPath $Path
    } catch {
        return ((Split-Path -Leaf $Path) + ' could not be read for Authenticode: ' +
                $_.Exception.Message + ' Nothing was published.')
    }

    if ($null -eq $sig -or $sig.Status -ne 'Valid') {
        $st = if ($sig) { [string]$sig.Status } else { 'unknown' }
        return ((Split-Path -Leaf $Path) + ' is not Authenticode Valid (status ' + $st + '). ' +
                'Ship and site publish refuse an unsigned tip. Sign it on a machine with ' +
                'tools\signing.json, then publish again. Nothing was published.')
    }

    $who = ''
    if ($sig.SignerCertificate -and $sig.SignerCertificate.Subject) {
        $who = [string]$sig.SignerCertificate.Subject
    }
    if ([string]::IsNullOrWhiteSpace($who) -or
        $who.IndexOf($ExpectedSigner, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        return ((Split-Path -Leaf $Path) + ' is signed by "' + $who + '", which does not contain ' +
                'ExpectedSigner "' + $ExpectedSigner + '". Nothing was published.')
    }

    return ''
}
