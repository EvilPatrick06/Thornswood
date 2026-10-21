<#
  test-public-news.ps1

  What a stranger reads on the site's News page.

  Entry 187 on the To Do List, "The public news feed is a developer
  changelog": "Patch notes people read are short and about what they will
  notice: lockpicking works, locks are back. The front page currently shows
  strangers a 403 and a load order index".

  MEASURED 24 SEPTEMBER. The newest entry in this repo's version.json is one
  Publish-Server wrote on 20 September. Its body is "The server at" the VPS
  address "was reinstalled and is answering", and two of its three details
  are "The gamemode was rebuilt: starting kits, creation and arrival points
  live in it", untrue since the kits went that same day, and "Load order: 60
  plugins server side". Publish-News let all three through to the site. Since
  23 September Publish-Server writes into the live feed rather than this
  repo's copy, so the next server publish would have put them in front of
  strangers and in every launcher's News tab.

  This runs the real Publish-News.ps1 with -OutFile, which writes the page
  into a temp folder and sends nothing, over two feeds: one built here in the
  shapes Publish-Server and Publish-Update write, and a copy of this repo's
  own version.json. Then it reads Publish-Server.ps1 and checks those lines
  are no longer written at all, and that Publish-Discord strips everything
  Publish-News strips, because its comment says they are the same list.

  -Vps is a name that cannot resolve, so if -OutFile ever stopped working
  this would fail to send rather than put a test page on the site.

  -Repo runs it against another copy of the scripts, which is how it was
  shown to fail on the code before the fix.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$Repo)
# Scripts this runs whole go to a stand-in box, so the freshness guard lets them be (#2118).
$env:THORNSWOOD_HARNESS = '1'

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
$Here = Split-Path -Parent $Here
if (-not $Repo) { $Repo = $Here }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$newsScript = Join-Path $Repo 'scripts\ops\Publish-News.ps1'
$ip = '\b\d{1,3}(\.\d{1,3}){3}\b'

# Runs Publish-News over one feed and hands back what it would have published,
# or $null if it stopped or wrote nothing.
function Get-Page($releaseDir, $outFile) {
    try {
        & $newsScript -ReleaseDir $releaseDir -OutFile $outFile -From '2026-09-01' `
            -Vps 'nowhere.invalid' -User 'nobody' -Root 'C:/nowhere' -Quiet *>&1 | Out-Null
    } catch {
        Write-Host ('      Publish-News stopped: ' + $_.Exception.Message)
        return $null
    }
    if (-not (Test-Path -LiteralPath $outFile)) { return $null }
    return $outFile
}
function Read-Page($file) {
    return (([IO.File]::ReadAllText($file)) -replace '^\uFEFF', '') | ConvertFrom-Json
}
function Details($entry) {
    $p = $entry.PSObject.Properties['details']
    if ($null -eq $p -or $null -eq $p.Value) { return @() }
    return @($p.Value)
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-news-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    # ---- a feed in the shapes the two writers use ---------------------------
    # The address is from the range kept for documentation, not the VPS.
    $made = Join-Path $tmp 'made'
    New-Item -ItemType Directory -Path $made -Force | Out-Null
    $feed = [ordered]@{
        launcherVersion = '9.9.9'
        collectionUrl   = 'https://example.invalid/collection'
        news = @(
            [ordered]@{
                date = '23 Sep 2026'; title = 'Server updated'
                body = 'The server at 203.0.113.7 was reinstalled and is answering.'
                details = @('Load order: 60 plugins server side',
                            'Nothing to download for this one. It is on the server, so it is already live.')
                files = @(); kind = 'server'; named = $false
            },
            [ordered]@{
                date = '22 Sep 2026'; title = 'Your gear and your spells stay on across a relog'
                body = 'The server at 203.0.113.7 was reinstalled and is answering.'
                details = @('The gamemode was rebuilt: starting kits, creation and arrival points live in it',
                            'Load order: 60 plugins server side',
                            'Nothing to download for this one. It is on the server, so it is already live.')
                files = @(); kind = 'server'; named = $true
            },
            [ordered]@{
                date = '21 Sep 2026'; title = 'The mod list has a new revision, and the world has started over'
                body = 'Before you press Play, update the Thornswood collection in Vortex.'
                details = @('Launcher 1.1.80', '1 file to download, 0.0 MB',
                            'The load order moved, so start a new character or expect the old save to complain')
            },
            [ordered]@{
                date = '20 Sep 2026'; title = 'Doors you own open for you again'
                body = ''
                details = @('Load order: 96 plugins server side', 'Your key works on your own door.')
                files = @(); kind = 'server'; named = $true
            }
        )
    }
    [IO.File]::WriteAllText((Join-Path $made 'version.json'), ($feed | ConvertTo-Json -Depth 6),
        (New-Object Text.UTF8Encoding $false))

    $out = Get-Page $made (Join-Path $tmp 'made-news.json')
    Yes 'Publish-News writes the page to a file and sends nothing (-OutFile)' ($null -ne $out)
    if ($out) {
        $bytes = [IO.File]::ReadAllBytes($out)
        Yes 'the page has no byte order mark, which the site cannot read' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB))
        $page = Read-Page $out
        $all = @($page.news)
        $titles = @($all | ForEach-Object { [string]$_.title })
        $lines = @($all | ForEach-Object { Details $_ } | ForEach-Object { [string]$_ })
        $bodies = @($all | ForEach-Object { [string]$_.body })

        Yes 'a bare Server updated does not reach the page' (-not ($titles -contains 'Server updated'))
        Yes 'the named server release does' ($titles -contains 'Your gear and your spells stay on across a relog')
        Yes 'no detail line is a load order count' (-not ($lines | Where-Object { $_ -match '^\s*Load order\s*:' }))
        Yes 'no detail line says the gamemode was rebuilt' (-not ($lines | Where-Object { $_ -match 'gamemode was rebuilt' }))
        Yes 'no body says the server was reinstalled and is answering' (-not ($bodies | Where-Object { $_ -match 'reinstalled and is answering' }))
        Yes 'no address of any server is on the page' (-not (@($titles + $bodies + $lines) | Where-Object { $_ -match $ip }))
        Yes 'the launcher version and the download size are still dropped' (-not ($lines | Where-Object { $_ -match '^Launcher \d|files? to download' }))

        $relog = @($all | Where-Object { $_.title -eq 'Your gear and your spells stay on across a relog' })[0]
        if ($relog) {
            Yes 'the server release keeps the line people want: nothing to download' (@(Details $relog) -contains 'Nothing to download for this one. It is on the server, so it is already live.')
            Yes 'and its body is empty rather than a note to whoever ran it' ([string]$relog.body -eq '')
        }
        Yes 'a line for the reader that mentions the load order still goes out' ($lines -contains 'The load order moved, so start a new character or expect the old save to complain')
        Yes 'a body written for people still goes out' ($bodies -contains 'Before you press Play, update the Thornswood collection in Vortex.')

        # One line left after the filter is the trap PropList's comment is
        # about: a bare string where the site expects a list.
        $doors = @($all | Where-Object { $_.title -eq 'Doors you own open for you again' })[0]
        Yes 'an entry left with one detail keeps it as a list' ($doors -and ($doors.details -is [System.Array]) -and @($doors.details).Count -eq 1 -and @($doors.details)[0] -eq 'Your key works on your own door.')
    }

    # ---- the live feed, read as a stranger would -----------------------------
    # From this machine's working copy of the live feed (Feed-Store.ps1, #907),
    # where the scripts that publish look for it. This repository's own
    # version.json, which this read until 25 September, was a stale copy and is gone.
    $repoV = Join-Path (& (Join-Path $Here 'scripts\release\Where.ps1') Releases) 'version.json'
    if (-not (Test-Path -LiteralPath $repoV)) {
        Write-Host "SKIP  no live feed received on this machine to read"
    } else {
        $copy = Join-Path $tmp 'copy'
        New-Item -ItemType Directory -Path $copy -Force | Out-Null
        Copy-Item -LiteralPath $repoV -Destination (Join-Path $copy 'version.json')
        $src = Read-Page (Join-Path $copy 'version.json')
        # Wherever the feed keeps its notes: in "news", or since main's 1.2.4
        # Ship (12 Oct) a file of their own named as "newsFile", with "news"
        # empty (Feed-News.ps1, #1050). Reading "news" alone found no title
        # and failed this from that Ship on.
        . (Join-Path $Here 'scripts\release\Feed-News.ps1')
        $srcTitles = @(@(Get-FeedNewsList $src $env:THORNSWOOD_TEST_SITE_DIR) | ForEach-Object { [string]$_.title })

        $out2 = Get-Page $copy (Join-Path $tmp 'copy-news.json')
        Yes 'Publish-News reads a copy of the live feed' ($null -ne $out2)
        if ($out2) {
            $all2 = @((Read-Page $out2).news)
            $fromFeed = @($all2 | Where-Object { $srcTitles -contains [string]$_.title })
            Write-Host ("      {0} of the {1} titles in the repo feed reach the page:" -f $fromFeed.Count, $srcTitles.Count)
            foreach ($e in $fromFeed) { Write-Host ('        ' + $e.title) }
            Yes 'titles from the feed reach the page' ($fromFeed.Count -gt 0)
            Yes 'no title is a bare Server updated' (-not ($fromFeed | Where-Object { $_.title -match '^\s*server updated\.?\s*$' }))
            Yes 'no title carries a launcher version' (-not ($fromFeed | Where-Object { $_.title -match '\b\d+\.\d+\.\d+\b' }))
            Yes 'no title is a path' (-not ($fromFeed | Where-Object { $_.title -match '[\\/](SKSE|Data|tools)[\\/]' }))
            Yes 'no title is a plugin count' (-not ($fromFeed | Where-Object { $_.title -match 'plugins server side' }))
            $lines2 = @($all2 | ForEach-Object { Details $_ } | ForEach-Object { [string]$_ })
            $bodies2 = @($all2 | ForEach-Object { [string]$_.body })
            Yes 'no detail anywhere on the page is a load order count' (-not ($lines2 | Where-Object { $_ -match '^\s*Load order\s*:' }))
            Yes 'no detail says the gamemode was rebuilt' (-not ($lines2 | Where-Object { $_ -match 'gamemode was rebuilt' }))
            Yes 'no server address anywhere on the page' (-not (@($bodies2 + $lines2 + @($all2 | ForEach-Object { [string]$_.title })) | Where-Object { $_ -match $ip }))
        }
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- Publish-Server no longer writes them ------------------------------------
# It needs the VPS to run, so its source is read instead: every place it adds
# to the details, and every place it sets the body.
$psPath = Join-Path $Repo 'scripts\release\Publish-Server.ps1'
$tk = $null; $er = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($psPath, [ref]$tk, [ref]$er)
Yes 'Publish-Server.ps1 parses' (@($er).Count -eq 0)
$assigns = @($ast.FindAll({ param($a) $a -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))
$toDetails = @($assigns | Where-Object { $_.Left.Extent.Text -eq '$details' -and [string]$_.Operator -eq 'PlusEquals' })
Yes ("Publish-Server adds to the details in {0} places, so there is something to read" -f $toDetails.Count) ($toDetails.Count -ge 2)
Yes 'none of them is a load order count' (-not ($toDetails | Where-Object { $_.Right.Extent.Text -match '(?i)load order' }))
Yes 'none of them says the gamemode was rebuilt' (-not ($toDetails | Where-Object { $_.Right.Extent.Text -match '(?i)gamemode was rebuilt' }))
Yes 'the line people do want is still written' (@($toDetails | Where-Object { $_.Right.Extent.Text -match 'Nothing to download for this one' }).Count -eq 1)
$toBody = @($assigns | Where-Object { $_.Left.Extent.Text -eq '$body' })
Yes 'Publish-Server sets a body' ($toBody.Count -ge 1)
Yes 'no body it sets carries the VPS address or says it was reinstalled' (-not ($toBody | Where-Object { $_.Right.Extent.Text -match '(?i)VpsHost|reinstalled and is answering' }))

# ---- Publish-Discord strips what Publish-News strips --------------------------
function Noise-List($path) {
    $t = $null; $e = $null
    $a = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
    # Publish-Discord keeps its list in Get-ThornswoodDiscordNoise and assigns
    # $noise from a call to it, so the function is read first: the assignment
    # there has no strings of its own. Publish-News assigns the list directly.
    $fn = $a.Find({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Get-ThornswoodDiscordNoise' }, $true)
    if ($fn) {
        return @($fn.Body.FindAll({ param($x) $x -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
    }
    $as = $a.Find({ param($x) $x -is [System.Management.Automation.Language.AssignmentStatementAst] -and $x.Left.Extent.Text -eq '$noise' }, $true)
    if (-not $as) { return @() }
    return @($as.Right.FindAll({ param($x) $x -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
}
$newsNoise = @(Noise-List $newsScript)
$discordNoise = @(Noise-List (Join-Path $Repo 'scripts\ops\Publish-Discord.ps1'))
Yes ("Publish-News strips {0} kinds of line, the load order and the gamemode among them" -f $newsNoise.Count) (($newsNoise -contains '^\s*Load order\s*:') -and ($newsNoise -contains '^\s*The gamemode was rebuilt\b'))
$missing = @($newsNoise | Where-Object { $discordNoise -notcontains $_ })
foreach ($m in $missing) { Write-Host ('      Publish-Discord does not strip: ' + $m) }
Yes 'Publish-Discord strips every one of them too, as its comment says' ($missing.Count -eq 0)

Write-Host ''
Write-Host "$script:pass passed, $script:fail failed"
exit $(if ($script:fail) { 1 } else { 0 })
