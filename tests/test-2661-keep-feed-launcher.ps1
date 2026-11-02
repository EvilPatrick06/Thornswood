<#
  test-2661-keep-feed-launcher.ps1

  Get-FeedLauncher in Ship.ps1 (issue #2661): a launcher a feed already
  offers, downloaded from its launcherUrl and held to the feed's
  launcherSha256 and to the signature, for a Ship that puts that launcher out
  again rather than building one (main's own on dev, or the one dev tried, on
  main). It began as the half of a main Ship with -Package that put the
  feed's launcher into the ship root for the old installer; that half,
  Install-FeedLauncher, went with the installer (#4824).

  This lifts Get-FeedLauncher out of the shipped Ship.ps1 by the parser and
  drives it against a file:// feed and a stand-in Get-PublishSignRefusal, so
  no network, certificate or signtool is needed: the feed's launcher arrives
  whole with no .part left, and a download that is not the feed's sha256,
  one signed by somebody else, a feed naming no whole launcher, an empty
  ExpectedSigner and a URL that does not answer each stop with a reason and
  leave nothing half written. If the name moves, this says so rather than
  quietly testing nothing.

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

# ---- lift the functions -----------------------------------------------------
# Line ends as LF, so a checkout with CRLF reads the same.
$src = [IO.File]::ReadAllText($ShipPath) -replace "`r`n", "`n"
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$t, [ref]$e)
Yes 'Ship.ps1 parses' (@($e).Count -eq 0)

$FnAst = [System.Management.Automation.Language.FunctionDefinitionAst]
$fns = @{}
foreach ($f in $ast.FindAll({ param($n) $n -is $FnAst }, $true)) { $fns[$f.Name] = $f.Extent.Text }
foreach ($n in 'Get-FeedLauncher') {
    Yes "Ship.ps1 has $n" ($fns.ContainsKey($n))
    if (-not $fns.ContainsKey($n)) { Done }
    Invoke-Expression $fns[$n]
}


Yes 'Get-FeedLauncher checks the signature with Get-PublishSignRefusal' ($fns['Get-FeedLauncher'] -match 'Get-PublishSignRefusal -Path \$exe -ExpectedSigner \$expectedSigner')

# ---- drive it ---------------------------------------------------------------
# The stand-in reads the signer off the exe's first line: "signed by <who>".
function Get-PublishSignRefusal {
    param([string]$Path, [string]$ExpectedSigner)
    if (-not (Test-Path -LiteralPath $Path)) { return "missing file to check for a publish signature: $Path" }
    $first = @([IO.File]::ReadAllLines($Path))[0]
    if ($first -notmatch '^signed by (.+)$') { return ((Split-Path -Leaf $Path) + ' is not Authenticode Valid (status NotSigned). Nothing was published.') }
    if ($Matches[1] -ne $ExpectedSigner) { return ((Split-Path -Leaf $Path) + ' is signed by "' + $Matches[1] + '". Nothing was published.') }
    return ''
}
function Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-2661-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $who = 'The Name On The Certificate'
    $feedDir = Join-Path $work 'feed'
    New-Item -ItemType Directory -Force -Path $feedDir | Out-Null
    $feedExe = Join-Path $feedDir 'Thornswood.exe'
    [IO.File]::WriteAllText($feedExe, "signed by $who`nthe 1.2.5 main's feed offers`n")
    $theirs = Join-Path $feedDir 'Theirs.exe'
    [IO.File]::WriteAllText($theirs, "signed by Somebody Else`nnot ours`n")
    # Absolute by name: a cast takes /tmp/... as a relative URI off Windows (#2989).
    function Url([string]$p) { return ([Uri]::new($p, [UriKind]::Absolute)).AbsoluteUri }
    function Pub([string]$url, [string]$sha) { return [pscustomobject]@{ Version = '1.2.5'; Url = $url; Sha = $sha; Inputs = 'abc' } }
    $good = Pub (Url $feedExe) (Sha $feedExe)

    function Left([string]$dir) { return @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) }

    # ---- Get-FeedLauncher ---------------------------------------------------
    $into = Join-Path $work 'dl'
    $why = Get-FeedLauncher $good $into $who
    Yes "the feed's launcher downloads and checks: '$why'" ($why -eq '')
    Yes '  and is in the folder with the feed''s sha256' ((Test-Path -LiteralPath (Join-Path $into 'Thornswood.exe')) -and (Sha (Join-Path $into 'Thornswood.exe')) -eq $good.Sha)
    Yes '  with no .part left' (-not (Test-Path -LiteralPath (Join-Path $into 'Thornswood.exe.part')))
    $why = Get-FeedLauncher (Pub (Url $feedExe) ($good.Sha.ToUpperInvariant())) $into $who
    Yes "  the feed's sha256 in capitals is the same sha256: '$why'" ($why -eq '')

    $why = Get-FeedLauncher (Pub (Url $feedExe) ('0' * 64)) $into $who
    Yes "a download that is not the feed's sha256 stops: '$why'" ($why -match 'does not match the feed''s launcherSha256' -and $why -match 'Nothing was published')
    Yes '  and leaves nothing in the folder' ((Left $into).Count -eq 0)

    $why = Get-FeedLauncher (Pub (Url $theirs) (Sha $theirs)) $into $who
    Yes "a download signed by somebody else stops: '$why'" ($why -match 'is not signed by ExpectedSigner' -and $why -match 'Somebody Else')
    Yes '  and leaves nothing in the folder' ((Left $into).Count -eq 0)

    $why = Get-FeedLauncher (Pub '' $good.Sha) $into $who
    Yes "a feed with no launcherUrl stops: '$why'" ($why -match 'names no whole launcher')
    $why = Get-FeedLauncher (Pub (Url $feedExe) 'aa') $into $who
    Yes "a feed whose launcherSha256 is not 64 hex digits stops: '$why'" ($why -match 'names no whole launcher')
    $why = Get-FeedLauncher $null $into $who
    Yes "no feed at all stops: '$why'" ($why -match 'names no whole launcher')
    $why = Get-FeedLauncher $good $into ''
    Yes "an empty ExpectedSigner stops: '$why'" ($why -match 'ExpectedSigner is empty')
    $why = Get-FeedLauncher (Pub (Url (Join-Path $feedDir 'gone.exe')) $good.Sha) $into $who
    Yes "a launcherUrl that does not answer stops: '$why'" ($why -match 'could not be downloaded' -and $why -match 'Run this same Ship again')
    Yes '  and leaves nothing in the folder' ((Left $into).Count -eq 0)

}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Done
