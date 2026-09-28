<#
  test-pack-feed.ps1

  Publish-Pack.ps1 pulls the releases clone before it edits version.json, and
  never writes a pack into the feed that a launcher cannot download.

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

  It never reaches GitHub. The block between the pack feed markers is lifted
  out of the script by the parser and run against real git repositories under
  this harness's own temp folder: a bare one standing in for GitHub, a clone
  standing in for the releases clone on the machine publishing, and a second
  clone standing in for somebody else's machine.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$PackPath)

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
foreach ($mark in 'WriteAllText($vf', "Head 'Pushing'", 'git commit') {
    $at = $src.IndexOf($mark)
    Yes ("the block comes before the first " + $mark) ($at -lt 0 -or $a -lt $at)
}
# And the pull has to come before the read, not after it.
$pullAt = $block.IndexOf('pull --rebase')
$readAt = $block.IndexOf('ReadAllText($vf)')
Yes 'the block pulls the clone' ($pullAt -ge 0)
Yes 'and reads version.json only after the pull' ($readAt -gt $pullAt)

. $RulesPath

$pub  = 'EvilPatrick06/Thornswood-Releases'
$priv = 'EvilPatrick06/Thornswood'
function Asset([string]$repo, [string]$id) { return "https://github.com/$repo/releases/download/packs-20260927-0100/$id.zip" }
function Pack([string]$id, [string]$url) { return [pscustomobject]@{ Id = $id; Url = $url } }

# Runs the lifted block the way the script does: $ReleaseDir is a scratch
# clone, $built is what the upload came back with, and Die is the script's
# stop, so here it throws and the message comes back.
function Run-Block([string]$releaseDir, $built) {
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

# Called RunGit rather than Git: PowerShell resolves a function before a
# command and does not care about case, so a function called Git calling git
# calls itself until the stack runs out.
$GitExe = ''
$found = Get-Command git -ErrorAction SilentlyContinue
if ($found) { $GitExe = $found.Source }
function RunGit() {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = (@(& $GitExe @args 2>&1) | ForEach-Object { [string]$_ }) -join "`n" } finally { $ErrorActionPreference = $old }
    if ($LASTEXITCODE -ne 0) { throw ("git " + ($args -join ' ') + " failed: " + $out) }
    return $out
}
function Feed([string]$dir, $doc) {
    [IO.File]::WriteAllText((Join-Path $dir 'version.json'), ($doc | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

if (-not $GitExe) {
    Write-Host 'SKIP  no git on PATH, so the pull was not measured'
    Done
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-pack-feed-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $bare = Join-Path $work 'remote.git'
    $mine = Join-Path $work 'Thornswood-Releases'
    $theirs = Join-Path $work 'Thornswood-Releases-other'

    RunGit init --bare -b main $bare | Out-Null
    RunGit init -b main $mine | Out-Null
    RunGit -C $mine config user.email 'harness@example.com' | Out-Null
    RunGit -C $mine config user.name 'Harness' | Out-Null
    Feed $mine ([pscustomobject]@{ launcherVersion = '1.1.101'; updateRepo = $pub; optional = @() })
    RunGit -C $mine add version.json | Out-Null
    RunGit -C $mine commit -m 'first feed' | Out-Null
    RunGit -C $mine remote add origin $bare | Out-Null
    RunGit -C $mine push -u origin main | Out-Null
    RunGit clone $bare $theirs | Out-Null
    RunGit -C $theirs config user.email 'other@example.com' | Out-Null
    RunGit -C $theirs config user.name 'Other' | Out-Null

    # ---- the ordinary run: nothing to pull, the feed reads, nothing stops
    $r = Run-Block $mine @((Pack 'hd-textures' (Asset $pub 'hd-textures')))
    Yes 'a pack in the feed repository does not stop the publish' ($r.Died -eq '')
    Yes 'and the feed it read is the one in the clone' ($null -ne $r.Doc -and $r.Doc.launcherVersion -eq '1.1.101')
    Yes 'and the repository it holds packs to is the one the feed names' ($r.FeedRepo -eq $pub)

    # ---- somebody else published while this machine was uploading
    $was = [IO.File]::ReadAllText((Join-Path $mine 'version.json'))
    Feed $theirs ([pscustomobject]@{ launcherVersion = '1.1.102'; updateRepo = $pub; optional = @() })
    RunGit -C $theirs add version.json | Out-Null
    RunGit -C $theirs commit -m 'their release' | Out-Null
    RunGit -C $theirs push origin main | Out-Null
    Yes 'the clone on this machine is behind before the run' (
        [IO.File]::ReadAllText((Join-Path $mine 'version.json')) -eq $was)
    $r = Run-Block $mine @((Pack 'hd-textures' (Asset $pub 'hd-textures')))
    Yes 'the run pulls it, so the edit lands on their release and not over it' ($r.Died -eq '' -and $r.Doc.launcherVersion -eq '1.1.102')

    # ---- a pull that cannot work stops before the file is read
    $good = RunGit -C $mine remote get-url origin
    RunGit -C $mine remote set-url origin (Join-Path $work 'not-a-repo.git') | Out-Null
    $before = [IO.File]::ReadAllText((Join-Path $mine 'version.json'))
    $r = Run-Block $mine @((Pack 'hd-textures' (Asset $pub 'hd-textures')))
    Yes 'a pull that fails stops the publish' ($r.Died -like 'DIE: *')
    Yes 'and says which clone and that version.json was not touched' (
        $r.Died.Contains($mine) -and $r.Died -match '(?i)has not been touched')
    Yes 'and the file really was not touched' ([IO.File]::ReadAllText((Join-Path $mine 'version.json')) -eq $before)
    Yes 'and it never got as far as reading the feed' ($null -eq $r.Doc)
    RunGit -C $mine remote set-url origin $good | Out-Null

    # ---- a pack outside the feed repository is refused
    $r = Run-Block $mine @((Pack 'hd-textures' (Asset $pub 'hd-textures')), (Pack 'weather' (Asset $priv 'weather')))
    Yes 'a pack held in another repository stops the publish' ($r.Died -like 'DIE: *')
    Yes 'and names the repository launchers read the feed from' ($r.Died.Contains($pub))
    Yes 'and says version.json was not touched' ($r.Died -match '(?i)has not been touched')

    # ---- an empty url is refused the same way, which is what took Play out
    $r = Run-Block $mine @((Pack 'hd-textures' ''))
    Yes 'a pack whose upload came back with no url stops the publish' ($r.Died -like 'DIE: *')

    # ---- a thornswood.net feed asset is allowed, by the same rule (#649)
    $sha = 'a' * 64
    $r = Run-Block $mine @((Pack 'hd-textures' ("https://thornswood.net/feed/assets/$sha")))
    Yes 'a thornswood.net feed asset is allowed' ($r.Died -eq '')

    # ---- a folder that is not a clone still reads, and is not pulled
    $loose = Join-Path $work 'loose'
    New-Item -ItemType Directory -Path $loose -Force | Out-Null
    Feed $loose ([pscustomobject]@{ launcherVersion = '1.1.103'; updateRepo = $pub; optional = @() })
    $r = Run-Block $loose @((Pack 'hd-textures' (Asset $pub 'hd-textures')))
    Yes 'a -ReleaseDir that is not a git clone is read without a pull' ($r.Died -eq '' -and $r.Doc.launcherVersion -eq '1.1.103')

    # ---- no version.json at all stops, and says where it looked
    $empty = Join-Path $work 'empty'
    New-Item -ItemType Directory -Path $empty -Force | Out-Null
    $r = Run-Block $empty @((Pack 'hd-textures' (Asset $pub 'hd-textures')))
    Yes 'no version.json where it looked stops the publish' ($r.Died -like 'DIE: *' -and $r.Died.Contains($empty))

    # ---- #897: the packs go to the site, not to a GitHub release -------------
    $hostParam = @($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'AssetHost' })
    Yes 'Publish-Pack.ps1 takes -AssetHost' ($hostParam.Count -eq 1)
    Yes 'and its default is site, the same as Publish-Update.ps1' (
        $hostParam.Count -eq 1 -and $hostParam[0].DefaultValue -and $hostParam[0].DefaultValue.SafeGetValue() -eq 'site')
    $sOpen = '# ==== thornswood pack site upload ===='
    $sShut = '# ==== end thornswood pack site upload ===='
    $sa = $src.IndexOf($sOpen)
    $sb = $src.IndexOf($sShut)
    Yes 'the site upload block markers are in Publish-Pack.ps1' ($sa -ge 0 -and $sb -gt $sa)
    if ($sa -ge 0 -and $sb -gt $sa) {
        $siteBlock = $src.Substring($sa, $sb - $sa)
        Yes 'the site upload comes before the feed is read or written' ($sb -lt $a)
        Yes 'and before GitHub is ever asked for a token, which only the github way does' (
            $sb -lt $src.IndexOf('gh auth token'))
        Yes 'the site upload never talks to GitHub' ($siteBlock -notmatch 'api\.github\.com|Invoke-RestMethod')
        $fOpen = $src.IndexOf('# ==== thornswood pack site feed ====')
        Yes 'the feed goes to the site after it is pushed, so launchers hear of the packs' (
            $fOpen -gt $src.IndexOf('& git push') -and $src.Substring($fOpen) -match 'Remirror-Site-Feed\.ps1')

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
}

Done
