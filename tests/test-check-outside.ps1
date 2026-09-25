<#
  test-check-outside.ps1

      pwsh -NoProfile -File .\tests\test-check-outside.ps1

  Check-Outside.ps1 walks what a first install needs that this project does
  not run: the feed on GitHub, every address in it, the downloads, Steam's
  public build and the Nexus collection. Nothing watched any of it before.

  MEASURED 24 SEPTEMBER, anonymously, from Patrick's machine. The live feed
  answered with 227 packs. 164 of them point at EvilPatrick06/Thornswood,
  whose release listing answers a stranger with 404, and 63 at
  Thornswood-Releases, which lists every one of them across two pages of 100.
  The launcher's asset answered 302 to release-assets.githubusercontent.com
  and the first byte came back 206 of 3,292,160. api.steamcmd.net gave public
  build 24914197 for app 489830. The Nexus collection page answers a bare
  request with 403.

  These drive the real walk, dot-sourced out of the shipped script, with the
  one function that touches the network (Probe) replaced by answers from a
  table. So what is under test is the shipped logic, nothing here leaves the
  machine, and every address it would have asked for is written down and
  checked: none of them may be the server.

  Read only apart from files under its own temp folder.
#>
[CmdletBinding()]
param([string]$ScriptPath)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, what they test is in tools\.
$Here = Join-Path (Split-Path -Parent $Here) 'tools'
if (-not $ScriptPath) { $ScriptPath = Join-Path $Here 'Check-Outside.ps1' }
# Kept under its own name: dot-sourcing the script sets $Here to wherever the
# script is, which is not tools\ when -ScriptPath points at a copy.
$Tools = $Here

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
  if ($cond) { $script:pass++; Write-Host "PASS  $what" -ForegroundColor Green }
  else       { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

Yes 'Check-Outside.ps1 is there' (Test-Path -LiteralPath $ScriptPath)
if (-not (Test-Path -LiteralPath $ScriptPath)) { Write-Host ''; Write-Host '0 passed, 1 failed' -ForegroundColor Red; exit 1 }

. $ScriptPath
$ErrorActionPreference = 'Stop'

# ---- the table the network is replaced by ------------------------------------
$script:Served = @{}
$script:Asked = New-Object 'System.Collections.Generic.List[object]'
$script:Ever = New-Object 'System.Collections.Generic.List[string]'
function Serve([string]$url, [int]$code, [string]$body = '', [hashtable]$more) {
  $r = @{ code = $code; body = $body; location = ''; range = ''; left = ''; reset = ''; link = ''; error = '' }
  if ($more) { foreach ($k in $more.Keys) { $r[$k] = $more[$k] } }
  $script:Served[$url] = $r
}
function Probe([string]$url, [string]$accept = '', [switch]$Body, [switch]$FirstByte) {
  $script:Asked.Add([pscustomobject]@{ Url = $url; Accept = $accept; FirstByte = [bool]$FirstByte })
  $script:Ever.Add($url)
  if ($script:Served.ContainsKey($url)) { return $script:Served[$url].Clone() }
  return @{ code = 0; body = ''; location = ''; range = ''; left = ''; reset = ''; link = ''; error = 'unreachable' }
}

$A = 'Owner/Public'
$B = 'Owner/Private'
function Api([string]$repo, [string]$id) { return ('https://api.github.com/repos/' + $repo + '/releases/assets/' + $id) }
$FeedA  = 'https://api.github.com/repos/Owner/Public/contents/version.json?ref=main'
$ListA1 = 'https://api.github.com/repos/Owner/Public/releases?per_page=100'
$ListA2 = 'https://api.github.com/repositories/42/releases?per_page=100&page=2'
$ListB  = 'https://api.github.com/repos/Owner/Private/releases?per_page=100'
$Steam  = 'https://api.steamcmd.net/v1/info/489830'
$Nexus  = 'https://www.nexusmods.com/games/skyrimspecialedition/collections/abc123'
$Signed = '?sp=r&sv=2018&jwt=SECRETJWTSIGNATURE'
function Cdn([string]$id) { return ('https://release-assets.githubusercontent.com/github-production-release-asset/1/' + $id + $Signed) }

function Pack([string]$id, [string]$url, [string]$sha = 'abc') { return [ordered]@{ id = $id; url = $url; sha256 = $sha; notes = 'n' } }
function FeedJson($packs, [hashtable]$over) {
  $f = [ordered]@{
    launcherVersion = '1.1.92'
    launcherUrl = (Api $A '900'); launcherSha256 = 'aa'
    serverAddress = '192.0.2.10'; serverPort = '7777'
    siteUrl = 'https://thornswood.net'
    updateRepo = $A
    collectionUrl = $Nexus
    clientRuntime = [ordered]@{ url = (Api $A '901'); sha256 = 'bb'; bytes = 5000; forkCommit = 'c883' }
    packs = @($packs)
  }
  if ($over) { foreach ($k in $over.Keys) { $f[$k] = $over[$k] } }
  return (ConvertTo-Json -InputObject $f -Depth 8)
}
function Rel([string[]]$ids, [string]$state = 'uploaded') {
  return [ordered]@{ tag_name = 't'; assets = @($ids | ForEach-Object { [ordered]@{ id = [long]$_; name = 'x.zip'; state = $state } }) }
}
function ListJson($rels) { return (ConvertTo-Json -InputObject @($rels) -Depth 8) }
function SteamJson([string]$build) {
  return ('{"data":{"489830":{"depots":{"branches":{"public":{"buildid":"' + $build + '","timeupdated":"1787839209"}}}}},"status":"success"}')
}
$gh = @{ left = '55'; reset = '1790000000' }

# Everything answering the way it should.
function Clean {
  $script:Served = @{}
  Serve $FeedA 200 (FeedJson @((Pack 'p1' (Api $A '1')), (Pack 'p2' (Api $A '2')), (Pack 'p3' (Api $A '3')))) $gh
  Serve $ListA1 200 (ListJson @((Rel @('1', '2', '900')))) @{ left = '54'; reset = '1790000000'; link = ('<' + $ListA2 + '>; rel="next", <' + $ListA2 + '>; rel="last"') }
  Serve $ListA2 200 (ListJson @((Rel @('3', '901')))) @{ left = '53'; reset = '1790000000'; link = ('<' + $ListA1 + '>; rel="prev"') }
  foreach ($pair in @(@('900', '1234'), @('901', '5000'), @('3', '77'))) {
    Serve (Api $A $pair[0]) 302 '' @{ location = (Cdn $pair[0]); left = '52' }
    Serve (Cdn $pair[0]) 206 '' @{ range = ('bytes 0-0/' + $pair[1]) }
  }
  Serve $Steam 200 (SteamJson '100')
  Serve $Nexus 200 '<html></html>'
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('thornswood-outside-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $root
$record = Join-Path $root 'steam-build.json'
[IO.File]::WriteAllText($record, '{ "appId": 489830, "publicBuildId": "100", "recordedUtc": "2026-09-24T10:00:14Z" }')
$Allowed = Read-AllowedHosts (Join-Path $Tools '..\launcher\app\Updater.cs')

function Run([string]$feedUrl = '', [string[]]$hosts = $Allowed, [string]$steamRecord = $record) {
  $script:Asked.Clear()
  $all = @(Invoke-Outside -Repo $A -Branch 'main' -FeedUrl $feedUrl -Hosts $hosts -SteamRecord $steamRecord `
             -Collection '' -Server @('thornswood.net', '192.0.2.99') 6>&1)
  $n = @($all | Where-Object { $_ -is [int] }) | Select-Object -Last 1
  $text = (@($all | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData }) -join "`n")
  return [pscustomobject]@{
    N = $n
    Bad = @($script:Found | Where-Object { $_.Kind -eq 'bad' } | ForEach-Object { $_.Text })
    Skip = @($script:Found | Where-Object { $_.Kind -eq 'skip' } | ForEach-Object { $_.Text })
    Ok = @($script:Found | Where-Object { $_.Kind -eq 'ok' } | ForEach-Object { $_.Text })
    Lines = @($script:Found | Where-Object { $_.Kind -eq 'line' } | ForEach-Object { $_.Text })
    Text = $text
    Asked = @($script:Asked | ForEach-Object { $_ })
  }
}
function Has($list, [string]$like) { return (@($list | Where-Object { $_ -like $like }).Count -gt 0) }
function AskedFor($r, [string]$url) { return (@($r.Asked | Where-Object { $_.Url -eq $url }).Count -gt 0) }

try {
  # ---- the files it reads out of the repository ------------------------------
  Yes "AllowedHosts is read out of the real Updater.cs" (($Allowed -contains 'api.github.com') -and ($Allowed -contains 'release-assets.githubusercontent.com'))
  $d = Read-Defaults (Join-Path $Tools '..\launcher\app\Config.cs')
  Yes 'the releases repository is read out of the real Config.cs' ($d.Repo -match '^[^/\s]+/[^/\s]+$' -and $d.Repo -like '*Releases*')
  Yes 'so is the collection address' ($d.Collection -like 'https://*nexusmods.com/*')
  Yes 'and the site, so it can be kept off it' ($d.SiteHost -eq 'thornswood.net')
  $real = [IO.File]::ReadAllText((Join-Path $Tools 'steam-build.json')) | ConvertFrom-Json
  Yes 'tools\steam-build.json records app 489830 and a build number' ($real.appId -eq 489830 -and ([string]$real.publicBuildId) -match '^\d+$')

  # ---- everything as it should be ------------------------------------------
  Clean
  $r = Run
  Yes 'with nothing wrong it finds nothing, so it can exit 0' ($r.N -eq 0 -and $r.Bad.Count -eq 0)
  Yes 'the feed is read the way the launcher reads it, the contents API raw' (@($r.Asked | Where-Object { $_.Url -eq $FeedA -and $_.Accept -eq 'application/vnd.github.raw' }).Count -eq 1)
  Yes 'the second page of the listing is followed' (AskedFor $r $ListA2)
  Yes 'an asset on the second page counts as listed' (Has $r.Ok '3 packs, the launcher and the client runtime are all listed in Owner/Public.')
  Yes 'the launcher is asked for with Accept octet-stream, as the launcher asks' (@($r.Asked | Where-Object { $_.Url -eq (Api $A '900') -and $_.Accept -eq 'application/octet-stream' }).Count -eq 1)
  Yes 'then only the first byte of where GitHub sends it' (@($r.Asked | Where-Object { $_.Url -eq (Cdn '900') -and $_.FirstByte }).Count -eq 1)
  Yes 'the client runtime and the newest pack are fetched too' ((AskedFor $r (Api $A '901')) -and (AskedFor $r (Api $A '3')))
  Yes 'an older pack is not fetched, the listing already covers it' (-not (AskedFor $r (Api $A '1')))
  Yes 'the Steam build matches the record' (Has $r.Ok "Steam's public build is still 100, as recorded 2026-09-24.")
  Yes 'a 200 from Nexus is called weak evidence' (Has $r.Ok '*weak evidence*')
  Yes 'the depot pins are said to be unchecked, not passed' (Has $r.Skip '*depot manifests*check by hand.')
  Yes 'the signed download address is never printed' (($r.Text + ($r.Ok -join ' ')) -notmatch 'SECRETJWT|jwt=')
  Yes 'only its host is' ($r.Text -match 'release-assets\.githubusercontent\.com')

  # ---- the budget: a stranger gets sixty calls an hour ----------------------
  $many = @(1..150 | ForEach-Object { Pack ('m' + $_) (Api $A ([string](1000 + $_))) })
  Clean
  Serve $FeedA 200 (FeedJson $many) $gh
  Serve $ListA1 200 (ListJson @((Rel (@(1..150 | ForEach-Object { [string](1000 + $_) }) + @('900', '901'))))) $gh
  Serve (Api $A '1150') 302 '' @{ location = (Cdn '1150') }
  Serve (Cdn '1150') 206 '' @{ range = 'bytes 0-0/9' }
  $r = Run
  $apiCalls = @($r.Asked | Where-Object { $_.Url -like 'https://api.github.com/*' }).Count
  Yes ('150 packs cost ' + $apiCalls + ' GitHub API calls, not one each') ($r.N -eq 0 -and $apiCalls -le 6)

  # ---- the failure the live feed has today -----------------------------------
  Clean
  $packs = @((Pack 'b1' (Api $B '11')), (Pack 'b2' (Api $B '12')), (Pack 'b3' (Api $B '13')), (Pack 'p1' (Api $A '1')), (Pack 'p2' (Api $A '2')), (Pack 'p3' (Api $A '3')))
  Serve $FeedA 200 (FeedJson $packs) $gh
  Serve $ListB 404 '{"message":"Not Found"}' $gh
  $r = Run
  Yes 'packs in a repository a stranger gets 404 for are wrong' ($r.N -eq 1 -and (Has $r.Bad 'Owner/Private answers a stranger with 404*3 packs in the feed point there*cannot fetch them.*'))
  Yes 'and it says which, oldest and newest' (Has $r.Bad '*The oldest is b1 and the newest b3.')
  Yes 'one listing call tells it, not one per pack' (@($r.Asked | Where-Object { $_.Url -like '*Owner/Private/releases/assets/*' }).Count -eq 0)
  Yes 'the public ones are still passed' (Has $r.Ok '3 packs, the launcher and the client runtime are all listed in Owner/Public.')

  # ---- a feed that is not there, or not a feed -------------------------------
  Clean
  $wrongUrl = 'https://raw.githubusercontent.com/Owner/Public/main/no-such.json'
  Serve $wrongUrl 404 '404: Not Found'
  $r = Run $wrongUrl
  Yes 'a feed address that answers 404 is wrong' ($r.N -ge 1 -and (Has $r.Bad 'version.json answers 404*'))
  Yes 'nothing is listed off a feed it could not read' (-not (AskedFor $r $ListA1))
  Yes 'Steam is still asked, it does not come from the feed' (AskedFor $r $Steam)

  Clean
  $r = Run 'https://nowhere.example/version.json'
  Yes 'a feed that does not answer at all is wrong' (Has $r.Bad 'version.json answers nothing (unreachable)*')

  Clean
  Serve $FeedA 200 '<html>rate limited</html>' $gh
  $r = Run
  Yes 'a feed that answers but is not JSON is wrong' (Has $r.Bad 'version.json answers but is not a feed*')

  # ---- GitHub's allowance, which is not the feed's fault ---------------------
  Clean
  Serve $ListA1 403 '{"message":"API rate limit exceeded"}' @{ left = '0'; reset = '1790000000' }
  $r = Run
  Yes 'a spent allowance is said as that' (Has $r.Bad '*were not checked. GitHub*used up*')
  Yes 'and is not called a private repository' (-not (Has $r.Bad '*private*'))

  Clean
  Serve $FeedA 403 '' @{ left = '0'; reset = '1790000000' }
  $r = Run
  Yes 'a spent allowance on the feed itself is said as that' (Has $r.Bad 'version.json was not read. GitHub*used up*')

  # ---- one asset gone, one half uploaded -------------------------------------
  Clean
  Serve $FeedA 200 (FeedJson @((Pack 'p1' (Api $A '1')), (Pack 'p4' (Api $A '4')), (Pack 'p3' (Api $A '3')))) $gh
  $r = Run
  Yes 'a pack whose asset the repository no longer lists is wrong' ($r.N -eq 1 -and (Has $r.Bad 'Owner/Public no longer lists the asset behind 1 pack:'))
  Yes 'and it is named' (Has $r.Lines '*pack p4, asset 4')

  Clean
  Serve $ListA1 200 (ListJson @((Rel @('1', '900')), (Rel @('2') 'starter'))) @{ left = '54'; link = ('<' + $ListA2 + '>; rel="next"') }
  $r = Run
  Yes 'an upload that never finished is wrong' (Has $r.Bad 'in Owner/Public, the upload behind 1 pack never finished:')
  Yes 'and the pack is named with the state GitHub gave' (Has $r.Lines '*pack p2, asset 2, starter')

  # ---- what the launcher itself would refuse ---------------------------------
  Clean
  $bad = @(
    (Pack 'p5' 'http://api.github.com/repos/Owner/Public/releases/assets/5'),
    (Pack 'p6' 'https://evil.example.com/p6.zip'),
    (Pack 'p7' (Api $A '7') ''),
    (Pack 'p1' (Api $A '1')), (Pack 'p2' (Api $A '2')), (Pack 'p3' (Api $A '3')))
  Serve $FeedA 200 (FeedJson $bad) $gh
  $r = Run
  Yes 'addresses the launcher refuses are one finding' ($r.N -eq 1 -and (Has $r.Bad "3 address(es) in the feed the launcher will not download:"))
  Yes 'plain http is named' (Has $r.Lines '*pack p5 is not https*')
  Yes 'a host off AllowedHosts is named' (Has $r.Lines '*pack p6 points at evil.example.com, which the launcher refuses')
  Yes 'a missing checksum is named' (Has $r.Lines '*pack p7 has no checksum*')
  Yes 'none of them is requested' (@($r.Asked | Where-Object { $_.Url -like '*evil.example.com*' -or $_.Url -like 'http://*' -or $_.Url -eq (Api $A '7') }).Count -eq 0)

  Clean
  $r = Run '' @()
  Yes 'with no AllowedHosts to read it says so rather than passing blind' (Has $r.Bad 'could not read AllowedHosts*')

  # ---- the server is never asked --------------------------------------------
  Clean
  $srv = @(
    (Pack 'p8' 'https://thornswood.net/packs/p8.zip'),
    (Pack 'p9' 'https://github.com/Owner/Public/releases/download/t/p9.zip'),
    (Pack 'p1' (Api $A '1')), (Pack 'p2' (Api $A '2')), (Pack 'p3' (Api $A '3')))
  Serve $FeedA 200 (FeedJson $srv) $gh
  $r = Run
  Yes 'a pack on the server is reported as unchecked' ($r.N -eq 0 -and (Has $r.Skip '1 pack on the server, which this does not contact*'))
  Yes 'a pack at an address it cannot read is unchecked, not passed' (Has $r.Skip '1 pack not at a GitHub release asset address*')
  Clean
  Serve $FeedA 200 (FeedJson @((Pack 'p1' (Api $A '1')), (Pack 'p2' (Api $A '2')), (Pack 'p3' (Api $A '3'))) @{ collectionUrl = 'https://thornswood.net/collection' }) $gh
  $r = Run
  Yes 'a collection address on the server is not asked either' ((-not (AskedFor $r 'https://thornswood.net/collection')) -and (Has $r.Skip '*on the server, which this does not contact.'))
  # The one path that reaches the guard inside Ask itself: somebody hands it a
  # feed address on the server.
  Clean
  $r = Run 'https://thornswood.net/version.json'
  Yes 'a feed address on the server is refused before any request, and said' ((-not (AskedFor $r 'https://thornswood.net/version.json')) -and (Has $r.Bad 'version.json answers nothing (not asked, that is the server)*'))

  # ---- the downloads themselves ----------------------------------------------
  Clean
  Serve (Cdn '901') 206 '' @{ range = 'bytes 0-0/4000' }
  $r = Run
  Yes 'a client runtime whose size is not the feed''s is wrong' (Has $r.Bad 'the client runtime is 4000 bytes at release-assets.githubusercontent.com and the feed says 5000*')

  Clean
  Serve (Cdn '900') 403 ''
  $r = Run
  Yes 'a redirect to something that will not hand it over is wrong' (Has $r.Bad 'the launcher: GitHub sends it on to release-assets.githubusercontent.com, which answers 403*')

  Clean
  Serve (Api $A '900') 404 '' $gh
  $r = Run
  Yes 'a listed asset GitHub will not hand out is wrong' (Has $r.Bad 'GitHub answers 404 when a launcher asks for the launcher*')

  Clean
  Serve $FeedA 200 (FeedJson @((Pack 'p1' (Api $A '1')), (Pack 'p2' (Api $A '2')), (Pack 'p3' (Api $A '3'))) @{ updateRepo = $B }) $gh
  $r = Run
  Yes 'a feed that sends every launcher somewhere else is wrong' (Has $r.Bad 'the feed sends every launcher to Owner/Private*')

  # ---- Steam -----------------------------------------------------------------
  Clean
  Serve $Steam 200 (SteamJson '200')
  $r = Run
  Yes "Steam's public build moving is red" ($r.N -eq 1 -and (Has $r.Bad "Steam's public build moved from 100 to 200 on 27 Aug 2026."))
  Yes 'and it says what to do about it' (Has $r.Lines '*as publicBuildId.')

  Clean
  $script:Served.Remove($Steam)
  $r = Run
  Yes 'a third party that does not answer is unchecked, not red' ($r.N -eq 0 -and (Has $r.Skip 'Steam: api.steamcmd.net answered nothing*'))

  Clean
  $r = Run '' $Allowed (Join-Path $root 'no-such-record.json')
  Yes 'no record to compare with is red' (Has $r.Bad 'no Steam build is recorded in*')

  # ---- Nexus -------------------------------------------------------------------
  Clean
  Serve $Nexus 403 'Just a moment...'
  $r = Run
  Yes 'a 403 from Nexus is unchecked, not red and not green' ($r.N -eq 0 -and (Has $r.Skip 'the collection: Nexus answered 403*'))
  Clean
  Serve $Nexus 404 ''
  $r = Run
  Yes 'a collection that is gone is red' ($r.N -eq 1 -and (Has $r.Bad 'the collection page answers 404*'))

  # ---- over every run above --------------------------------------------------
  $toServer = @($script:Ever | Where-Object { $_ -match '^https?://([^/]+\.)?thornswood\.net(/|:|$)' -or $_ -match '192\.0\.2\.10|192\.0\.2\.99' })
  Yes ('not one request in ' + $script:Ever.Count + ' went to the server') ($toServer.Count -eq 0)

  # ---- the file itself -------------------------------------------------------
  $src = [IO.File]::ReadAllText($ScriptPath)
  $code = [regex]::Replace($src, '(?s)<#.*?#>', '')
  $code = [regex]::Replace($code, '(?m)^\s*#.*$', '')
  Yes 'no token, key or launcher config is touched' ($code -notmatch 'Authorization|Bearer|UpdateToken|GITHUB_TOKEN|GH_TOKEN|config\.json|bot\.env')
  Yes 'GET is the only method it ever sends' (([regex]::Matches($code, '\.Method\s*=')).Count -eq 1 -and $code -match "\.Method\s*=\s*'GET'")
  Yes 'no other web cmdlet is used that could send something else' ($code -notmatch 'Invoke-WebRequest|Invoke-RestMethod|WebClient|HttpClient')
}
finally {
  Remove-Item -LiteralPath $root -Recurse -Force -EA SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail) -ForegroundColor $(if ($script:fail) { 'Red' } else { 'Green' })
if ($script:fail) { exit 1 }
