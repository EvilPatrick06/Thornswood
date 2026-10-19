<#
  test-2163-manifest-check.ps1

      pwsh -NoProfile -File .\tests\test-2163-manifest-check.ps1

  The launcher's check of the signed release manifest, phase C of
  docs\SIGNED-RELEASES.md (#2163): launcher\app\ReleaseManifest.cs and
  Signature.cs, compiled on their own, against tests\fixtures\2163-manifest,
  a release.json in the shape Release-Manifest.ps1 writes and its catalog,
  which ThornswoodRelease really signed on 19 Oct (one signature, on One).
  The fixture names assets that do not exist and was never shipped.

  WHY. Phase C tells the log whether every asset a feed names is one the
  signer released. A check that passes a catalog it should not, or misses an
  asset the feed names, says "signed" about files nobody signed for, and
  phase D would then enforce that. Each case below is one way that goes
  wrong.

  What it runs:
    1. The fixture as signed, with the assets it lists: passes, and says so.
    2. A feed asset the manifest does not list: refused, by name.
    3. A release.json changed after signing: refused, the catalog does not
       list it.
    4. The same release.json under a catalog nobody signed: refused by
       Signature.cs.
    5. The catalog's own digests: release.json's sha256 is one of them.
    6. The wiring, by text: the feed reads "signedManifest" apart, the update
       check logs the line, and nothing refuses on it yet.

  Reads the fixture, writes only a temp folder, sends nothing. Signature.cs
  asks Windows about revocation; with no network it says so and checks
  without. Keep it ASCII and Windows PowerShell 5.1.
#>
[CmdletBinding()]
param()
$env:THORNSWOOD_HARNESS = '1'
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$App = Join-Path $Repo 'launcher\app'
$Fix = Join-Path $Here 'fixtures\2163-manifest'

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

# Compiled the way the build compiles the launcher (Launcher-Csc.ps1), the two
# files on their own, under a namespace of their own so a session that already
# loaded another copy is not answered by it.
. (Join-Path $Here 'Launcher-Csc.ps1')
Yes 'the build''s compiler is on this machine' (Test-Path -LiteralPath $LauncherCsc)
$fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
if (-not (Test-Path -LiteralPath $fw)) { $fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319' }
$ns = 'T2163_' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$build = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-2163b-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $build | Out-Null
$cscArgs = @('/noconfig', '/nologo', "/langversion:$LauncherLangVersion", '/target:library', '/platform:anycpu', ('/out:' + (Join-Path $build 'm.dll')))
foreach ($r in 'mscorlib.dll', 'System.dll', 'System.Core.dll', 'System.Runtime.Serialization.dll', 'System.Security.dll', 'System.Xml.dll') { $cscArgs += ('/reference:' + (Join-Path $fw $r)) }
foreach ($f in 'Signature.cs', 'ReleaseManifest.cs') {
    $to = Join-Path $build $f
    [IO.File]::WriteAllText($to, [IO.File]::ReadAllText((Join-Path $App $f)).Replace('namespace Thornswood', "namespace $ns"))
    $cscArgs += $to
}
$old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
$cscSaid = & $LauncherCsc @cscArgs 2>&1
$cscRc = $LASTEXITCODE
$ErrorActionPreference = $old
Yes 'Signature.cs and ReleaseManifest.cs compile on their own with the build''s compiler' ($cscRc -eq 0)
if ($cscRc -ne 0) { $cscSaid | Select-Object -First 20 | ForEach-Object { Write-Host "      $_" }; exit 1 }
$RM = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes((Join-Path $build 'm.dll'))).GetType("$ns.ReleaseManifest")
Remove-Item -LiteralPath $build -Recurse -Force -ErrorAction SilentlyContinue
# The name on the signing certificate, written once, in Updater.cs (#1052).
$Signer = [regex]::Match([IO.File]::ReadAllText((Join-Path $App 'Updater.cs')), 'const string ExpectedSigner = "([^"]+)"').Groups[1].Value
Yes 'ExpectedSigner is read from launcher\app\Updater.cs' ([bool]$Signer)

function Assets([string[]]$pairs) {
    $l = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
    for ($i = 0; $i -lt $pairs.Count; $i += 2) { $l.Add((New-Object 'System.Collections.Generic.KeyValuePair[string,string]' $pairs[$i], $pairs[$i + 1])) }
    return ,$l
}
function Check([string]$cat, [string]$json, $assets) {
    $a = [object[]]@($cat, $json, $assets.PSObject.BaseObject, $Signer, $null)
    $why = $RM.GetMethod('Refusal').Invoke($null, $a)
    return [pscustomobject]@{ Why = [string]$why; Said = [string]$a[4] }
}
function Sha([string]$c) { return ([string]$c * 64).Substring(0, 64) }

$cat = Join-Path $Fix 'release.cat'
$json = Join-Path $Fix 'release.json'
Yes 'the fixture is there: release.json and its signed catalog' ((Test-Path -LiteralPath $cat) -and (Test-Path -LiteralPath $json))
$all = Assets @('launcher 9.9.9', (Sha 'a'), 'client runtime fixture', (Sha 'b'), 'pack p1', (Sha 'c'), 'release record fixture-2163', (Sha 'e'))

# ---- 1. as signed ---------------------------------------------------------------
$r = Check $cat $json $all
Yes 'the fixture as signed passes with the four assets it lists' ($r.Why -eq '')
Yes '  and the line says the release and that all four are listed, signed' ($r.Said -match 'fixture-2163' -and $r.Said -match 'all 4' -and $r.Said -match 'Artifact Signing')
$r = Check $cat $json (Assets @('pack p1', (Sha 'c')))
Yes '  a feed naming fewer assets than the manifest lists also passes' ($r.Why -eq '')

# ---- 2. an asset the manifest does not list ------------------------------------
$more = Assets @('launcher 9.9.9', (Sha 'a'), 'pack p2', (Sha '9'))
$r = Check $cat $json $more
Yes 'a feed asset the manifest does not list is refused, by name' ($r.Why -match 'does not list pack p2' -and $r.Said -eq '')

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-2163c-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $scratch | Out-Null
try {
    # ---- 3. release.json changed after signing ----------------------------------
    $changed = Join-Path $scratch 'release.json'
    [IO.File]::WriteAllText($changed, ([IO.File]::ReadAllText($json)).Replace((Sha 'c'), (Sha '9')), (New-Object Text.UTF8Encoding($false)))
    $r = Check $cat $changed $more
    Yes 'a release.json changed after signing is refused: the catalog does not list it' ($r.Why -match 'does not list release.json as it arrived')

    # ---- 4. a catalog nobody signed -----------------------------------------------
    $files = Join-Path $scratch 'files'
    New-Item -ItemType Directory -Force -Path $files | Out-Null
    Copy-Item -LiteralPath $json -Destination (Join-Path $files 'release.json')
    $bare = Join-Path $scratch 'unsigned.cat'
    New-FileCatalog -Path $files -CatalogFilePath $bare -CatalogVersion 2.0 | Out-Null
    $r = Check $bare (Join-Path $files 'release.json') $all
    Yes 'the same release.json under a catalog nobody signed is refused by Signature.cs' ($r.Why -match '^catalog ' -and $r.Said -eq '')

    # ---- 5. the digests -----------------------------------------------------------
    $d = $RM.GetMethod('CatalogDigests').Invoke($null, [object[]]@([string]$cat))
    $jsonSha = (Get-FileHash -LiteralPath $json -Algorithm SHA256).Hash.ToLowerInvariant()
    Yes "the catalog's digests include release.json's sha256" ($d.Contains($jsonSha))
    $r = Check (Join-Path $scratch 'missing.cat') $json $all
    Yes 'a catalog that is not there is refused, never thrown' ($r.Why.Length -gt 0)
} finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 6. the wiring ----------------------------------------------------------------
$cfg = [IO.File]::ReadAllText((Join-Path $App 'Config.cs'))
$fm = [IO.File]::ReadAllText((Join-Path $App 'FeedManifest.cs'))
$su = [IO.File]::ReadAllText((Join-Path $App 'ShellUpdate.cs'))
Yes 'VersionDoc.Parse reads "signedManifest" apart, like the record and the news file' ($cfg.Contains('doc.manifestRef = ManifestRef.FromFeed(raw, at);') -and $cfg.Contains('root.TryGetValue("signedManifest", out b)'))
Yes 'the manifest must list the launcher, the client runtime, the packs, the optional packs and the record' ($fm.Contains('v.launcherSha256') -and $fm.Contains('v.clientRuntime.sha256') -and $fm.Contains('new[] { v.packs, v.optional }') -and $fm.Contains('v.record.sha256'))
Yes 'each file is fetched by a url on the list, stored under its sha256, and must hash to it' ($fm.Contains('CheckUrl(url);') -and $fm.Contains('EndsWith("/" + sha') -and $fm.Contains('if (got != sha) throw'))
Yes 'it checks with the launcher''s own signer' ($fm.Contains('ReleaseManifest.Refusal(cat, json, assets, ExpectedSigner, out said)'))
Yes 'the update check logs the line, on its own thread, before the feed is acted on' ($su.Contains('string manifest = Updater.ManifestLine(cfg, v);') -and $su.Contains('if (manifest != null) LogOnly(manifest);'))
Yes 'phase C refuses nothing on it: the line is only logged' (-not ($su -match 'manifest[^\r\n]*(CheckFailed|return;)') -and $fm.Contains('Nothing was refused for it yet'))

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
