<#
  test-pack-feed.ps1

  Publish-Pack.ps1 receives the live feed from the VPS before it edits
  version.json (it pulled the releases clone until #907), and never writes a
  pack into the feed that a launcher cannot download.

  WHY THIS EXISTS. Publish-Pack uploads the optional packs as release assets
  first and edits version.json afterwards, then commits and pushes it. It read
  the clone as it stood, so a publish from a second machine edited a copy from
  before whatever the first machine had published, git push refused it, and the
  script ended on its own line: "the zips are up but nobody will be offered
  them". Publish-Update.ps1 has pulled before editing for exactly this reason;
  this is the same pull, in the same place, one step before the file is read.

  And the Add-ons tab fetches an optional pack through the same Updater code
  as a required one, so the rule in Feed-Rules.ps1 is the rule here too: an
  asset held anywhere but the repository the feed names answers 404 to every
  launcher. Publish-Update refuses a required pack like that. Until this,
  -Repo pointed at another repository wrote optional ones in without a word.

  It never reaches GitHub or the VPS. The block between the pack feed markers
  is lifted out of the script by the parser and run against a folder under
  this harness's own temp folder standing in for the VPS store
  (THORNSWOOD_TEST_SITE_DIR, Feed-Store.ps1), which another machine's release
  is written into between runs.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$PackPath)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo0 = Split-Path -Parent $Here
if (-not $PackPath) { $PackPath = Join-Path (Join-Path (Join-Path $Repo0 'scripts') 'release') 'Publish-Pack.ps1' }
$RulesPath = Join-Path (Split-Path -Parent $PackPath) 'Feed-Rules.ps1'

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

# ---- the script parses, the same gate the build check uses -----------------
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $PackPath).Path, [ref]$tokens, [ref]$errors)
Yes 'Publish-Pack.ps1 parses' (@($errors).Count -eq 0)
$src = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $PackPath).Path)

# ---- it reads the one rule rather than carrying a second copy of it --------
Yes 'Feed-Rules.ps1 is beside it' (Test-Path -LiteralPath $RulesPath)
Yes 'and Publish-Pack.ps1 dot-sources it' ($src -match "\.\s*\(Join-Path \`$Here 'Feed-Rules\.ps1'\)")

# ---- no path into anybody's home folder ------------------------------------
# What #712 took out. It would come back the moment somebody wrote a default
# in again, and the default is the whole point of that change.
$homePaths = @($ast.FindAll({
    param($n)
    ($n -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
     $n -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
    ($n.Value -match '(?i)^[a-z]:\\Users\\')
}, $true))
Yes 'no string in the script is a path under C:\Users' ($homePaths.Count -eq 0)
foreach ($h in $homePaths) { Write-Host ("      line {0}: {1}" -f $h.Extent.StartLineNumber, $h.Extent.Text) }

# ---- lift the block --------------------------------------------------------
$open = '# ==== thornswood pack feed ===='
$shut = '# ==== end thornswood pack feed ===='
$a = $src.IndexOf($open)
$b = $src.IndexOf($shut)
Yes 'the pack feed block markers are in Publish-Pack.ps1' ($a -ge 0 -and $b -gt $a)
if ($a -lt 0 -or $b -le $a) { Done }
$block = $src.Substring($a, $b - $a)

# The block has to sit before the file is written and before it is pushed, or
# the pull and the check are decorations.
foreach ($mark in 'Write-FeedVersionFile $vf', "Head 'Pushing'", 'git commit') {
    $at = $src.IndexOf($mark)
    Yes ("the block comes before the first " + $mark) ($at -lt 0 -or $a -lt $at)
}
# And the receive has to come before the read, not after it (#907).
$pullAt = $block.IndexOf('Receive-FeedStore')
$readAt = $block.IndexOf('ReadAllText($vf)')
Yes 'the block receives the feed from the VPS' ($pullAt -ge 0)
Yes 'and reads version.json only after the receive' ($readAt -gt $pullAt)

. $RulesPath

$pub  = 'EvilPatrick06/Thornswood-Releases'
$priv = 'EvilPatrick06/Thornswood'
function Asset([string]$repo, [string]$id) { return "https://github.com/$repo/releases/download/packs-20260927-0100/$id.zip" }
function Pack([string]$id, [string]$url) { return [pscustomobject]@{ Id = $id; Url = $url } }

# The store it receives from (Feed-Store.ps1, #907), with the VPS stood in for
# by a folder through the test variable, so nothing connects anywhere.
. (Join-Path (Split-Path -Parent $PackPath) 'Feed-Store.ps1')

# Runs the lifted block the way the script does: $ReleaseDir is the working
# folder, $receive says whether it was left to default (and so is received
# from the VPS first), $built is what the upload came back with, and Die is
# the script's stop, so here it throws and the message comes back.
function Run-Block([string]$releaseDir, $built, [bool]$receive = $true) {
    $ReleaseDir = $releaseDir
    $vf = ''
    $doc = $null
    $feedRepo = ''
    function Say($m, $c = 'Gray') { Write-Host ("      " + $m) -ForegroundColor DarkGray }
    function Die($m) { throw ('DIE: ' + $m) }
    $died = ''
    try { . ([scriptblock]::Create($block)) }
    catch { $died = [string]$_.Exception.Message }
    return [pscustomobject]@{ Doc = $doc; FeedRepo = $feedRepo; Died = $died }
}
function Feed([string]$dir, $doc) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'version.json'), ($doc | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}
# The stand-in site keeps no version.json: its feed is the newest of the
# channel's write-once generations, version\<8 digits>.json (#2727), so a
# release from another machine is the next one, the way the store sends it.
function SiteFeed([string]$channelDir, $doc) {
    $v = Join-Path $channelDir 'version'
    New-Item -ItemType Directory -Path $v -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $v (Get-FeedVersionNext $channelDir)), ($doc | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-pack-feed-' + [Guid]::NewGuid().ToString('N'))
$oldSite = $env:THORNSWOOD_TEST_SITE_DIR
try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $siteRoot = Join-Path $work 'site-store'
    $env:THORNSWOOD_TEST_SITE_DIR = $siteRoot
    $up = Join-Path $siteRoot 'feed'
    $mine = Join-Path $work 'store\main'
    SiteFeed $up ([pscustomobject]@{ launcherVersion = '1.1.101'; optional = @() })
    Yes 'the stand-in site''s feed starts as its first generation' ((Get-FeedVersionName $up) -eq '00000001.json')
    [IO.File]::WriteAllText((Join-Path $up 'published.json'), '{}')
    $siteAsset = 'https://thornswood.net/feed/assets/' + ('c' * 64)

    # ---- the ordinary run: the feed is received, reads, nothing stops
    $r = Run-Block $mine @((Pack 'hd-textures' $siteAsset))
    Yes 'a pack on the site does not stop the publish' ($r.Died -eq '')
    Yes 'and the feed it read is the one on the VPS, received into the working folder' ($null -ne $r.Doc -and $r.Doc.launcherVersion -eq '1.1.101' -and
        (Test-Path -LiteralPath (Join-Path $mine 'read.json')))

    # ---- somebody else published while this machine was building
    SiteFeed $up ([pscustomobject]@{ launcherVersion = '1.1.102'; optional = @() })
    $r = Run-Block $mine @((Pack 'hd-textures' $siteAsset))
    Yes 'the run receives it again, so the edit lands on their release and not over it' ($r.Died -eq '' -and $r.Doc.launcherVersion -eq '1.1.102')

    # ---- a VPS that does not answer stops before the file is read
    $env:THORNSWOOD_TEST_SITE_DIR = ''
    function Receive-FeedStore { throw 'the VPS did not answer' }
    $before = [IO.File]::ReadAllText((Join-Path $mine 'version.json'))
    $r = Run-Block $mine @((Pack 'hd-textures' $siteAsset))
    Yes 'a receive that fails stops the publish' ($r.Died -like 'DIE: *')
    Yes 'and says that version.json was not touched' ($r.Died -match '(?i)has not been touched')
    Yes 'and the file really was not touched' ([IO.File]::ReadAllText((Join-Path $mine 'version.json')) -eq $before)
    Yes 'and it never got as far as reading the feed' ($null -eq $r.Doc)
    Remove-Item Function:\Receive-FeedStore
    . (Join-Path (Split-Path -Parent $PackPath) 'Feed-Store.ps1')
    $env:THORNSWOOD_TEST_SITE_DIR = $siteRoot

    # ---- a pack on GitHub is refused, now the feed names no repository
    $r = Run-Block $mine @((Pack 'hd-textures' $siteAsset), (Pack 'weather' (Asset $pub 'weather')))
    Yes 'a pack held on GitHub stops the publish (#907)' ($r.Died -like 'DIE: *')
    Yes 'and says a launcher cannot download it' ($r.Died -match 'cannot download')
    Yes 'and says version.json was not touched' ($r.Died -match '(?i)has not been touched')

    # ---- an empty url is refused the same way, which is what took Play out
    $r = Run-Block $mine @((Pack 'hd-textures' ''))
    Yes 'a pack whose upload came back with no url stops the publish' ($r.Died -like 'DIE: *')

    # ---- a folder passed with -ReleaseDir is read as it is, not received
    $loose = Join-Path $work 'loose'
    Feed $loose ([pscustomobject]@{ launcherVersion = '1.1.103'; optional = @() })
    $r = Run-Block $loose @((Pack 'hd-textures' $siteAsset)) $false
    Yes 'a -ReleaseDir is read as it stands, without receiving' ($r.Died -eq '' -and $r.Doc.launcherVersion -eq '1.1.103' -and
        -not (Test-Path -LiteralPath (Join-Path $loose 'read.json')))

    # ---- no version.json at all stops, and says where it looked
    $empty = Join-Path $work 'empty'
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $r = Run-Block $empty @((Pack 'hd-textures' $siteAsset)) $false
    Yes 'no version.json where it looked stops the publish' ($r.Died -like 'DIE: *' -and $r.Died.Contains($empty))

    # ---- #897: the packs go to the site, not to a GitHub release -------------
    $gone = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -in 'AssetHost', 'Repo' })
    Yes 'Publish-Pack.ps1 takes no -AssetHost and no -Repo: packs go to the site and nowhere else (#907)' ($gone.Count -eq 0)
    $sOpen = '# ==== thornswood pack site upload ===='
    $sShut = '# ==== end thornswood pack site upload ===='
    $sa = $src.IndexOf($sOpen)
    $sb = $src.IndexOf($sShut)
    Yes 'the site upload block markers are in Publish-Pack.ps1' ($sa -ge 0 -and $sb -gt $sa)
    if ($sa -ge 0 -and $sb -gt $sa) {
        $siteBlock = $src.Substring($sa, $sb - $sa)
        Yes 'the site upload comes before the feed is read or written' ($sb -lt $a)
        Yes 'and GitHub is never asked for a token (#907)' ($src -notmatch 'gh auth token' -and $src -notmatch 'GITHUB_TOKEN')
        Yes 'the site upload never talks to GitHub' ($siteBlock -notmatch 'api\.github\.com|Invoke-RestMethod')
        $fOpen = $src.IndexOf('# ==== thornswood pack site feed ====')
        Yes 'the feed goes to the site after it is written, so launchers hear of the packs' (
            $src.IndexOf('Write-FeedVersionFile $vf') -gt 0 -and $fOpen -gt $src.IndexOf('Write-FeedVersionFile $vf') -and $src.Substring($fOpen) -match 'Remirror-Site-Feed\.ps1')

        # Runs the lifted block with Remirror-Site-Feed.ps1 -Send into a scratch
        # site folder, the same way test-site-assets.ps1 drives Publish-Update.
        function Run-Site($built, [string]$siteDir) {
            $Here = Split-Path -Parent $PackPath
            $SiteDir = $siteDir
            function Say($m, $c = 'Gray') { Write-Host ("      " + $m) -ForegroundColor DarkGray }
            function Head($m) { }
            function Die($m) { throw ('DIE: ' + $m) }
            $died = ''
            try { . ([scriptblock]::Create($siteBlock)) *>&1 | Out-Null }
            catch { $died = [string]$_.Exception.Message }
            return $died
        }
        $zipDir = Join-Path $work 'zips'
        New-Item -ItemType Directory -Path $zipDir -Force | Out-Null
        $zipA = Join-Path $zipDir 'hd-textures.zip'
        [IO.File]::WriteAllBytes($zipA, [Text.Encoding]::UTF8.GetBytes('pretend pack, hd textures'))
        $shaA = (Get-FileHash -LiteralPath $zipA -Algorithm SHA256).Hash.ToLowerInvariant()
        $siteDir = Join-Path $work 'site'
        $builtA = @([pscustomobject]@{ Id = 'hd-textures'; Name = 'HD'; Zip = $zipA; Sha = $shaA; Bytes = 25; Files = 1 })
        $died = Run-Site $builtA $siteDir
        $landed = Join-Path (Join-Path (Join-Path $siteDir 'feed') 'assets') $shaA
        Yes ('site: the pack is sent to feed\assets under its sha256' + $(if ($died) { " ($died)" } else { '' })) (
            $died -eq '' -and (Test-Path -LiteralPath $landed))
        Yes 'site: the bytes up there are the zip''s' (
            (Test-Path -LiteralPath $landed) -and (Get-FileHash -LiteralPath $landed -Algorithm SHA256).Hash.ToLowerInvariant() -eq $shaA)
        Yes 'site: nothing goes to feed-dev' (-not (Test-Path -LiteralPath (Join-Path (Join-Path $siteDir 'feed-dev') 'assets')))
        Yes 'site: no .part is left behind' (@(Get-ChildItem -LiteralPath (Split-Path -Parent $landed) -Filter '*.part' -ErrorAction SilentlyContinue).Count -eq 0)
        $urlA = ''
        if ($builtA[0].PSObject.Properties['Url']) { $urlA = [string]$builtA[0].Url }
        Yes 'site: the feed names it at its site url' ($urlA -eq "https://thornswood.net/feed/assets/$shaA")
        Yes 'site: and that url passes the rule the feed block holds packs to' (Test-FeedPackUrl $urlA $pub)
        $r = Run-Block $mine @((Pack 'hd-textures' $urlA))
        Yes 'site: and the feed block takes it' ($r.Died -eq '')

        $missing = @([pscustomobject]@{ Id = 'weather'; Name = 'W'; Zip = (Join-Path $zipDir 'no-such.zip'); Sha = ('b' * 64); Bytes = 1; Files = 1 })
        $died = Run-Site $missing $siteDir
        Yes 'site: a pack that does not reach the site stops the publish' ($died -like 'DIE: *')
        Yes 'site: and says version.json was not touched' ($died -match '(?i)has not been touched')
        Yes 'site: and gives it no url, so nothing could name it' (-not $missing[0].PSObject.Properties['Url'])
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $env:THORNSWOOD_TEST_SITE_DIR = $oldSite
}

Done
