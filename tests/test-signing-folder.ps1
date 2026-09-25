<#
  test-signing-folder.ps1

      pwsh -NoProfile -File .\tests\test-signing-folder.ps1

  The signing setup lives in tools\signing, and Sign-Artifact.ps1 finds a dlib
  or metadata that signing.json names relative to the repository.

  WHY. Until 25 September the signing setup was C:\tools on Patrick's machine:
  metadata.json and Microsoft's signing client, backed up nowhere and on no
  other machine. It moved into the repository with the rest of the folder
  consolidation (C:\Thornswood-Dev), asked for by Patrick and agreed by
  Djinn. signing.json named C:\tools by full path, so it has to be able to
  name tools\signing instead, and that has to mean the repository's, not
  whatever folder the build happens to run from.

  HOW. Sign-Artifact.ps1 is run for real with a signing.json in a temp folder
  whose metadata is "tools\signing\metadata.json", from a working folder that
  is not the repository. The tracked metadata.json still has no certificate
  profile, so the script says so and signs nothing; that answer, naming the
  repository's file, is the proof the relative path was read from the right
  place. Nothing is signed and nothing outside the temp folder is written.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
$repo = Split-Path -Parent $Here
$shell = (Get-Process -Id $PID).Path

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$meta = Join-Path $Here 'signing\metadata.json'
Yes 'tools\signing\metadata.json is in the repository' (Test-Path -LiteralPath $meta)
$m = $null
try { $m = Get-Content -LiteralPath $meta -Raw | ConvertFrom-Json } catch { }
Yes 'it names the account, the region and the profile' ($m -and $m.CodeSigningAccountName -eq 'ThornswoodSigning' -and $m.Endpoint -eq 'https://wus2.codesigning.azure.net' -and $m.CertificateProfileName)
$keys = @(); if ($m) { $keys = @($m.PSObject.Properties.Name | Sort-Object) }
Yes 'and nothing else, so nothing secret can sit in it unnoticed' (($keys -join ',') -eq 'CertificateProfileName,CodeSigningAccountName,Endpoint')
function Ignored([string]$rel) { & git -C $repo check-ignore -q $rel 2>$null; return ($LASTEXITCODE -eq 0) }
Yes 'tools\signing\client is ignored by git' (Ignored 'tools/signing/client/Azure.CodeSigning.Dlib.dll')
Yes 'and metadata.json is not' (-not (Ignored 'tools/signing/metadata.json'))

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-signing-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
Push-Location $work
try {
    $cfg = Join-Path $work 'signing.json'
    [IO.File]::WriteAllText($cfg, '{"method":"artifactsigning","dlib":"tools\\signing\\client\\Azure.CodeSigning.Dlib.dll","metadata":"tools\\signing\\metadata.json"}')
    $out = & $shell -NoProfile -File (Join-Path $Here 'Sign-Artifact.ps1') -Path (Join-Path $work 'nothing.exe') -ConfigPath $cfg 2>&1 | Out-String
    $code = $LASTEXITCODE
    Yes 'a relative metadata path is read from the repository, not from the working folder' ($out -match 'not filled in yet' -and $out -match [regex]::Escape('signing'))
    Yes 'and with no certificate profile yet it signs nothing and does not fail the build' ($code -eq 0)
    $out = & $shell -NoProfile -File (Join-Path $Here 'Sign-Artifact.ps1') -Path (Join-Path $work 'nothing.exe') -ConfigPath $cfg -Required 2>&1 | Out-String
    Yes 'with -Required, the same missing profile stops a release' ($LASTEXITCODE -ne 0 -and $out -match 'not filled in yet')
}
finally {
    Pop-Location
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
