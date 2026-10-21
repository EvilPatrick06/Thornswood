<#
  test-2163-release-manifest.ps1

      pwsh -NoProfile -File .\tests\test-2163-release-manifest.ps1

  The signed release manifest, phase B of docs\SIGNED-RELEASES.md (#2163):
  scripts\release\Release-Manifest.ps1, Sign-ReleaseCatalog.ps1 and the block
  of Publish-Update.ps1 that signs a release before the feed names it.

  WHY. A checksum never says who released a file, because whoever writes
  version.json writes the hashes too. Each release now lists the hash of every
  asset that carries code or names files in a catalog signed by
  ThornswoodRelease. If the list misses an asset, or the catalog no longer
  holds the list as written, or an unsigned catalog passes, the signature
  vouches for less than it seems to, and nothing else would go red.

  What it runs:
    1. Get-ReleaseManifestAssets on a feed: the launcher, the client runtime,
       each pack and optional pack and the baseline record, not the news file;
       an asset with a url and no sha256 is refused.
    2. New-ReleaseManifestFiles and Get-ReleaseManifestRefusal in a scratch
       folder: the files, the catalog holding release.json, a changed
       release.json refused, a feed asset the manifest lacks refused.
    3. The publish gate refusing the catalog while it is unsigned (no signing
       is done here; Sign-ReleaseCatalog.ps1 is read for what it runs).
    4. Publish-Update.ps1's wiring, by text.

  Signs nothing and sends nothing. Keep it ASCII and Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()
$env:THORNSWOOD_HARNESS = '1'
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$Release = Join-Path $Repo 'scripts\release'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

. (Join-Path $Release 'Feed-Rules.ps1')
. (Join-Path $Release 'Release-Manifest.ps1')
. (Join-Path $Release 'Assert-PublishSigned.ps1')

function Sha([string]$c) { return ([string]$c * 64).Substring(0, 64) }
function New-Doc {
    return ([pscustomobject]@{
        launcherVersion = '1.2.6'
        launcherUrl     = 'https://thornswood.net/feed-dev/assets/' + (Sha 'a')
        launcherSha256  = (Sha 'a')
        clientRuntime   = [pscustomobject]@{ url = 'https://thornswood.net/feed-dev/assets/' + (Sha 'b'); sha256 = (Sha 'b'); forkCommit = 'f00d' }
        packs           = @([pscustomobject]@{ id = 'p1'; url = 'https://thornswood.net/feed-dev/assets/' + (Sha 'c'); sha256 = (Sha 'c') })
        optional        = @([pscustomobject]@{ id = 'o1'; url = 'https://thornswood.net/feed-dev/assets/' + (Sha 'd'); sha256 = (Sha 'd') })
        baseline        = [pscustomobject]@{ id = '20991231-0000-dev'; url = 'https://thornswood.net/feed-dev/assets/' + (Sha 'e'); sha256 = (Sha 'e') }
        newsFile        = [pscustomobject]@{ url = 'https://thornswood.net/feed-dev/assets/' + (Sha 'f'); sha256 = (Sha 'f') }
        release         = [pscustomobject]@{ id = '20991231-0000-dev'; commit = ('1' * 40); branch = 'HEAD' }
    })
}

# ---- 1. what the manifest lists ----------------------------------------------
$doc = New-Doc
$assets = @(Get-ReleaseManifestAssets $doc)
$shas = @($assets | ForEach-Object { $_.Sha })
Yes 'it lists the launcher, the client runtime, the pack, the optional pack and the baseline record, in that order' ((($shas | ForEach-Object { $_.Substring(0, 1) }) -join '') -eq 'abcde')
Yes '  and not the news file (Dev-News rewrites it after a Ship)' (-not ($shas -contains (Sha 'f')))
$bad = New-Doc
$bad.packs[0].sha256 = ''
$threw = $false
try { [void](Get-ReleaseManifestAssets $bad) } catch { $threw = $_.Exception.Message -match 'pack p1' }
Yes 'a pack with a url and no sha256 is refused, by name' $threw
$noBase = New-Doc
$noBase.baseline.sha256 = 'nope'
$threw = $false
try { [void](Get-ReleaseManifestAssets $noBase) } catch { $threw = $_.Exception.Message -match 'baseline' }
Yes 'a baseline record with no sha256 is refused' $threw

# ---- 2. the files and the refusals ----------------------------------------------
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-2163-' + [guid]::NewGuid().ToString('N'))
# The catalog is New-FileCatalog's and Test-FileCatalog's, which only Windows
# has. Off Windows the manifest is written without it, as a release from the
# feed writes it (-NoCatalog, Sign-OnGitHub.ps1), and its listing is checked
# the way that release checks it (-CatalogChecked).
. (Join-Path $PSScriptRoot 'Windows.ps1')
$offWin = -not $OnWindows
try {
    if ($OnWindows) {
        $sm = New-ReleaseManifestFiles $doc '20991231-0000-dev' 'dev' $scratch
        Yes 'it writes files\release.json and release.cat' ((Test-Path -LiteralPath $sm.Json -PathType Leaf) -and (Test-Path -LiteralPath $sm.Catalog -PathType Leaf))
    } else {
        $said = ''
        try { [void](New-ReleaseManifestFiles $doc '20991231-0000-dev' 'dev' $scratch) } catch { $said = $_.Exception.Message }
        Yes 'off Windows a catalog made here is refused in words: New-FileCatalog is only on Windows' ($said -match 'only on Windows' -and $said -notmatch 'not recognized')
        $sm = New-ReleaseManifestFiles $doc '20991231-0000-dev' 'dev' $scratch -NoCatalog
        Yes 'with -NoCatalog it writes files\release.json alone' ((Test-Path -LiteralPath $sm.Json -PathType Leaf) -and -not (Test-Path -LiteralPath $sm.Catalog))
    }
    $bytes = [IO.File]::ReadAllBytes($sm.Json)
    Yes '  release.json has no byte order mark and is one line' ($bytes[0] -ne 0xEF -and -not ([IO.File]::ReadAllText($sm.Json).Contains("`n")))
    $m = [IO.File]::ReadAllText($sm.Json) | ConvertFrom-Json
    Yes '  it names the release, the channel, the commit and the fork commit' ($m.release -eq '20991231-0000-dev' -and $m.channel -eq 'dev' -and $m.commit -eq ('1' * 40) -and $m.forkCommit -eq 'f00d' -and $m.schema -eq 1)
    Yes '  and lists the five assets' (@($m.assets).Count -eq 5)
    Yes '  the catalog holds only release.json' (@(Get-ChildItem -LiteralPath $sm.Files -File).Count -eq 1)
    Yes 'the manifest as written passes' ((Get-ReleaseManifestRefusal $sm $doc -CatalogChecked:$offWin) -eq '')
    $more = New-Doc
    $more.packs += [pscustomobject]@{ id = 'p2'; url = 'https://thornswood.net/feed-dev/assets/' + (Sha '9'); sha256 = (Sha '9') }
    $why = Get-ReleaseManifestRefusal $sm $more -CatalogChecked:$offWin
    Yes 'a feed asset the manifest does not list is refused, by name' ($why -match 'pack p2')

    if ($OnWindows) {
        # 3. the gate refuses the unsigned catalog
        $expected = Get-ExpectedSignerFragment -RepoRoot $Repo
        $gate = Get-PublishSignRefusal -Path $sm.Catalog -ExpectedSigner $expected
        Yes 'the publish gate refuses the catalog while it is unsigned' ($gate -match 'not Authenticode Valid')

        [IO.File]::WriteAllText($sm.Json, ([IO.File]::ReadAllText($sm.Json)).Replace((Sha 'c'), (Sha '8')), (New-Object Text.UTF8Encoding($false)))
        $why = Get-ReleaseManifestRefusal $sm $doc
        Yes 'a release.json changed after the catalog was made is refused' ($why -match 'Test-FileCatalog')
    } else {
        Write-Host 'SKIP  the catalog: the gate on it unsigned, and a release.json changed after it was made; New-FileCatalog, Test-FileCatalog and Authenticode are only on Windows'
    }
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

# ---- 3b. what Sign-ReleaseCatalog.ps1 runs --------------------------------------
$src = [IO.File]::ReadAllText((Join-Path $Release 'Sign-ReleaseCatalog.ps1'))
Yes 'Sign-ReleaseCatalog.ps1 signs through Sign-Artifact.ps1 -Required' ($src.Contains("Join-Path `$PSScriptRoot 'Sign-Artifact.ps1'") -and $src.Contains('-Path $Catalog -Required'))
Yes '  and then runs the publish gate and Signature.cs on the catalog' ($src.Contains('Get-PublishSignRefusal -Path $Catalog -ExpectedSigner $expected'))
Yes '  and has no switch that skips either' (-not ($src -match '\[switch\]'))

# ---- 4. Publish-Update.ps1 ------------------------------------------------------
$pu = [IO.File]::ReadAllText((Join-Path $Release 'Publish-Update.ps1'))
$a = $pu.IndexOf('# ==== thornswood signed manifest ====')
$b = $pu.IndexOf('# ==== end thornswood signed manifest ====')
$block = if ($a -ge 0 -and $b -gt $a) { $pu.Substring($a, $b - $a) } else { '' }
Yes 'Publish-Update.ps1 dot-sources Release-Manifest.ps1 and Sign-ReleaseCatalog.ps1' ($pu.Contains(". (Join-Path `$Here 'Release-Manifest.ps1')") -and $pu.Contains(". (Join-Path `$Here 'Sign-ReleaseCatalog.ps1')"))
Yes 'the signed manifest block is marked' ($block -ne '')
Yes '  it sits after the release record and the news, before version.json is written' ($a -gt $pu.IndexOf('# ==== end thornswood news out ====') -and $a -gt $pu.IndexOf('# ==== end thornswood release record ====') -and $b -lt $pu.IndexOf('Write-FeedVersionFile $VersionFile $doc'))
Yes '  it runs on every run that uploads, and on none that does not' ($block.Contains('if (-not $NoUpload) {'))
Yes '  it signs, then checks the manifest, and stops the publish on either' ($block.Contains('Invoke-ReleaseCatalogSign $sm.Catalog $RepoDir') -and $block.Contains('Get-ReleaseManifestRefusal $sm $doc') -and $block.Contains('if ($smWhy) {') -and $block.Contains('Die ('))
Yes '  it sends both files to the site before the feed names them' ($block.IndexOf("Remirror-Site-Feed.ps1') @smArgs") -gt 0 -and $block.IndexOf("Remirror-Site-Feed.ps1') @smArgs") -lt $block.IndexOf("Set-Prop `$doc 'signedManifest'"))
Yes '  and the feed names them by url and sha256' ($block.Contains('catalogSha256 = $smCatSha') -and $block.Contains('sha256        = $smJsonSha'))
Yes '  a run that uploads nothing leaves no older release''s manifest named' ($block.Contains("`$doc.PSObject.Properties.Remove('signedManifest')"))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
