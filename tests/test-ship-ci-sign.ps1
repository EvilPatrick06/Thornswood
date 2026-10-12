<#
  test-ship-ci-sign.ps1

  A main Ship signs the launcher CI built, or stops. Issue #921.

  release.yml built Thornswood.exe on the VPS runner, which holds no signing
  certificate, so every v<version> draft carried an unsigned exe. Since #2163
  the hosted job signs it on a v tag; the VPS fallback's draft is still unsigned. On 27 Sep
  20260927-1633 put that exe on Main as 1.1.101, unsigned, and every launcher
  from dev 1.1.101.17 on refuses an unsigned update. Ship now signs the
  verified download with Sign-Artifact.ps1 -Required and reads it back against
  ExpectedSigner before it is installed or packed.

  This lifts Set-ReleaseLauncherSignature out of the shipped Ship.ps1 by the
  parser, the way test-ship-ci-launcher.ps1 lifts Get-ReleaseLauncher, and
  drives it with a stand-in Get-PublishSignRefusal and fake signers, so no
  certificate and no signtool are needed. It also checks the order in Ship.ps1:
  the CI branch signs after SHA256SUMS and before Install-Launcher, and the
  sign helpers are loaded before that. If a name moves, this says so rather
  than quietly testing nothing.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ShipPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ShipPath) { $ShipPath = Join-Path (Split-Path -Parent $Here) 'scripts/release/Ship.ps1' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail) { exit 1 }
    exit 0
}

# ---- lift the function ------------------------------------------------------
$src = [IO.File]::ReadAllText($ShipPath)
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$t, [ref]$e)
Yes 'Ship.ps1 parses' (@($e).Count -eq 0)

$FnAst = [System.Management.Automation.Language.FunctionDefinitionAst]
$fns = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is $FnAst }, $true)) { $fns[$f.Name] = $f.Extent.Text }
Yes 'Ship.ps1 has Set-ReleaseLauncherSignature' ($fns.ContainsKey('Set-ReleaseLauncherSignature'))
if (-not $fns.ContainsKey('Set-ReleaseLauncherSignature')) { Done }
Invoke-Expression $fns['Set-ReleaseLauncherSignature']

# ---- the order in Ship.ps1 --------------------------------------------------
$iAssert  = $src.IndexOf(". (Join-Path `$Here 'Assert-PublishSigned.ps1')")
$iGet     = $src.IndexOf('$why = Get-ReleaseLauncher $srcRepo $target $buildOut')
$iSign    = $src.IndexOf('$why = Set-ReleaseLauncherSignature (Join-Path $buildOut')
$iInstall = $src.IndexOf("& (Join-Path `$Here 'Install-Launcher.ps1') @installArgs")
$iElse    = $src.IndexOf("Head 'Building the launcher'")
$iPublish = $src.IndexOf("& (Join-Path `$Here 'Publish-Update.ps1') @pubArgs")
Yes 'Ship dot-sources Assert-PublishSigned.ps1 at the top level' ($iAssert -ge 0)
Yes 'Ship takes the exe CI built' ($iGet -ge 0)
Yes 'Ship signs the exe CI built' ($iSign -ge 0)
Yes '  after SHA256SUMS is verified' ($iSign -gt $iGet)
Yes '  in the main branch, before the local build branch' ($iElse -gt $iSign)
Yes '  before Install-Launcher puts it in place' ($iInstall -gt $iSign)
Yes '  and before Publish-Update' ($iPublish -gt $iSign)
Yes '  with the sign helpers loaded before any of it' ($iAssert -ge 0 -and $iAssert -lt $iGet)
Yes 'Ship still keeps the publish sign gate' ($src -match 'Get-PublishSignRefusal -Path \$pubExe')
Yes 'Ship passes -Required to the signer' ($fns['Set-ReleaseLauncherSignature'] -match '-Required')

# ---- drive it ---------------------------------------------------------------
# The stand-in reads a marker beside the file: "ours" is Valid under
# ExpectedSigner, "theirs" is signed by somebody else, none is unsigned.
function Get-PublishSignRefusal {
    param([string]$Path, [string]$ExpectedSigner)
    $m = $Path + '.sig'
    if (-not (Test-Path -LiteralPath $m)) { return ((Split-Path -Leaf $Path) + ' is not Authenticode Valid (status NotSigned).') }
    $who = [IO.File]::ReadAllText($m).Trim()
    if ($who -ne $ExpectedSigner) { return ((Split-Path -Leaf $Path) + ' is signed by "' + $who + '".') }
    return ''
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-ci-sign-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $exe = Join-Path $work 'Thornswood.exe'
    $log = Join-Path $work 'signer.log'
    $who = 'The Name On The Certificate'

    # A signer that works: records its arguments, marks the file as ours.
    $good = Join-Path $work 'good-signer.ps1'
    [IO.File]::WriteAllText($good, @"
param([string[]]`$Path, [switch]`$Required)
Add-Content -LiteralPath '$log' -Value ('signed required=' + [bool]`$Required)
foreach (`$p in `$Path) { [IO.File]::WriteAllText(`$p + '.sig', '$who') }
exit 0
"@)
    # A machine without signing.json under -Required: exits 1, signs nothing.
    $refuse = Join-Path $work 'refusing-signer.ps1'
    [IO.File]::WriteAllText($refuse, @"
param([string[]]`$Path, [switch]`$Required)
Add-Content -LiteralPath '$log' -Value 'refused'
exit 1
"@)
    # A signer that says it worked and leaves the file unsigned.
    $liar = Join-Path $work 'lying-signer.ps1'
    [IO.File]::WriteAllText($liar, @"
param([string[]]`$Path, [switch]`$Required)
Add-Content -LiteralPath '$log' -Value 'lied'
exit 0
"@)

    function Reset([string]$sig) {
        [IO.File]::WriteAllText($exe, 'the launcher CI built')
        Remove-Item -LiteralPath ($exe + '.sig'), $log -Force -EA SilentlyContinue
        if ($sig) { [IO.File]::WriteAllText($exe + '.sig', $sig) }
    }
    function SignerRan { if (Test-Path -LiteralPath $log) { return [IO.File]::ReadAllText($log).Trim() } return '' }

    # 1. Unsigned CI exe, signing machine: signed, -Required passed, returns ''.
    Reset ''
    $why = Set-ReleaseLauncherSignature $exe $good $who
    Yes "an unsigned CI exe is signed and passes: '$why'" ($why -eq '')
    Yes "  the signer ran with -Required: '$(SignerRan)'" ((SignerRan) -eq 'signed required=True')
    Yes '  and the exe now reads as ours' (-not (Get-PublishSignRefusal -Path $exe -ExpectedSigner $who))

    # 2. Already signed by us (CI signs one day): left alone.
    Reset $who
    $why = Set-ReleaseLauncherSignature $exe $good $who
    Yes "an exe already signed by ExpectedSigner passes: '$why'" ($why -eq '')
    Yes '  and the signer is not run again' ((SignerRan) -eq '')

    # 3. A machine that cannot sign: stops, and says where to Ship from.
    Reset ''
    $why = Set-ReleaseLauncherSignature $exe $refuse $who
    Yes 'a machine that cannot sign stops the Ship' ($why -ne '')
    Yes "  naming the exit code and signing.json: '$why'" ($why -match 'exit code 1' -and $why -match 'signing\.json')
    Yes '  and says nothing was published' ($why -match 'Nothing was published')

    # 4. Signer reports success but the file is still unsigned: stops.
    Reset ''
    $why = Set-ReleaseLauncherSignature $exe $liar $who
    Yes 'a signer that leaves the file unsigned stops the Ship' ($why -ne '')
    Yes "  and says the read-back refused it: '$why'" ($why -match 'Signing said it worked' -and $why -match 'NotSigned')

    # 5. Signed by somebody else: re-signed by us, then passes.
    Reset 'Somebody Else'
    $why = Set-ReleaseLauncherSignature $exe $good $who
    Yes "an exe signed by somebody else is signed by us before it passes: '$why'" ($why -eq '' -and (SignerRan) -eq 'signed required=True')

    # 6. No exe, no signer, no ExpectedSigner: each stops.
    Remove-Item -LiteralPath $exe -Force -EA SilentlyContinue
    Yes 'a missing exe stops the Ship' ((Set-ReleaseLauncherSignature $exe $good $who) -match 'no launcher at')
    Reset ''
    Yes 'a missing Sign-Artifact stops the Ship' ((Set-ReleaseLauncherSignature $exe (Join-Path $work 'nope.ps1') $who) -match 'Sign-Artifact\.ps1 is not at')
    Yes 'an empty ExpectedSigner stops the Ship' ((Set-ReleaseLauncherSignature $exe $good '') -match 'ExpectedSigner is empty')

    # Every refusal in the house words.
    foreach ($w in @(
        (Set-ReleaseLauncherSignature $exe $refuse $who),
        (Set-ReleaseLauncherSignature $exe $liar $who)
    )) {
        Yes '  refusal has no em dash and no "player"' ($w.IndexOf([char]0x2014) -lt 0 -and $w -notmatch 'player')
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Done
