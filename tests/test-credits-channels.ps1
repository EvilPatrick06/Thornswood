<#
  test-credits-channels.ps1

  Issue #990. The credits page used to name one client commit, the one in
  records\client-build.json. A channel's feed can still be serving an older
  build. The page now names the public feed and the dev feed. This holds
  each shown commit to clientRuntime.forkCommit in that channel's
  version.json.

  It reads feed files on disk. It does not fetch thornswood.net, and it does
  not treat the live site as the proof.

  The default feeds are this machine's working copies:
    %LOCALAPPDATA%\Thornswood\feed\main\version.json
    %LOCALAPPDATA%\Thornswood\feed\dev\version.json
  -PublicFeed and -DevFeed point at other files.

  A fixture half always runs, in this test's temp folder, so a parser that
  swaps the channels fails even on a machine with no feed. The page half
  runs when both feeds are present. If neither default feed is there, that
  half is skipped. If only one is there, it fails.
#>
[CmdletBinding()]
param(
    [string]$PublicFeed,
    [string]$DevFeed,
    [string]$Credits
)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $Credits) { $Credits = Join-Path $Repo 'site\data\site\credits.md' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

function Read-FeedFork([string]$path) {
    $raw = [IO.File]::ReadAllText($path)
    $raw = $raw -replace '^\uFEFF', ''
    $doc = $raw | ConvertFrom-Json
    $cr = $doc.PSObject.Properties['clientRuntime']
    if (-not $cr -or $null -eq $cr.Value) { return $null }
    $prop = $cr.Value.PSObject.Properties['forkCommit']
    if (-not $prop) { return $null }
    return [string]$prop.Value
}

function Get-ShownCommit([string]$text, [string]$channel, [string]$feed) {
    $re = '(?m)^\|\s*' + [regex]::Escape($channel) + '\s*\|\s*`' + [regex]::Escape($feed) + '`\s*\|\s*\[`([0-9a-f]{7,40})`\]'
    $m = [regex]::Match($text, $re)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Test-Holds([string]$text, [string]$publicPath, [string]$devPath, [string]$label) {
    $shownPublic = Get-ShownCommit $text 'Public' 'feed/version.json'
    $shownDev = Get-ShownCommit $text 'Dev' 'feed-dev/version.json'
    $feedPublic = Read-FeedFork $publicPath
    $feedDev = Read-FeedFork $devPath
    Yes ($label + ': the page names a public commit') ($shownPublic -match '^[0-9a-f]{7,40}$')
    Yes ($label + ': the page names a dev commit') ($shownDev -match '^[0-9a-f]{7,40}$')
    Yes ($label + ': the public row matches that feed') ($shownPublic -and $shownPublic -eq $feedPublic)
    Yes ($label + ': the dev row matches that feed') ($shownDev -and $shownDev -eq $feedDev)
    Yes ($label + ': the two rows are not swapped') (
        $shownPublic -and $shownDev -and $feedPublic -and $feedDev -and
        -not ($shownPublic -eq $feedDev -and $shownDev -eq $feedPublic -and $feedPublic -ne $feedDev))
}

# ---- fixture: the parser holds each row to its own file --------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-credits-channels-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $tmp
try {
    $pubPath = Join-Path $tmp 'public.json'
    $devPath = Join-Path $tmp 'dev.json'
    [IO.File]::WriteAllText($pubPath, '{"clientRuntime":{"forkCommit":"aaaaaaa1"}}')
    [IO.File]::WriteAllText($devPath, '{"clientRuntime":{"forkCommit":"bbbbbbb2"}}')
    $good = @"
| Channel | Feed | The six client files are built from |
|---|---|---|
| Public | ``feed/version.json`` | [``aaaaaaa1``](https://github.com/EvilPatrick06/skymp/tree/aaaaaaa1) |
| Dev | ``feed-dev/version.json`` | [``bbbbbbb2``](https://github.com/EvilPatrick06/skymp/tree/bbbbbbb2) |
"@
    $swapped = @"
| Channel | Feed | The six client files are built from |
|---|---|---|
| Public | ``feed/version.json`` | [``bbbbbbb2``](https://github.com/EvilPatrick06/skymp/tree/bbbbbbb2) |
| Dev | ``feed-dev/version.json`` | [``aaaaaaa1``](https://github.com/EvilPatrick06/skymp/tree/aaaaaaa1) |
"@
    Test-Holds $good $pubPath $devPath 'fixture'
    $shownSwapPublic = Get-ShownCommit $swapped 'Public' 'feed/version.json'
    $feedPublic = Read-FeedFork $pubPath
    Yes 'a swapped page does not match the public feed' ($shownSwapPublic -ne $feedPublic)
    [IO.File]::WriteAllText((Join-Path $tmp 'empty.json'), '{}')
    Yes 'a feed with no clientRuntime has no commit' ($null -eq (Read-FeedFork (Join-Path $tmp 'empty.json')))
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- the credits page, against the feeds when they are on disk -------------
$asked = [bool]($PublicFeed -or $DevFeed)
if (-not $PublicFeed) { $PublicFeed = Join-Path $env:LOCALAPPDATA 'Thornswood\feed\main\version.json' }
if (-not $DevFeed) { $DevFeed = Join-Path $env:LOCALAPPDATA 'Thornswood\feed\dev\version.json' }
$hasPublic = Test-Path -LiteralPath $PublicFeed
$hasDev = Test-Path -LiteralPath $DevFeed
if ($asked -or ($hasPublic -and $hasDev)) {
    if (-not ($hasPublic -and $hasDev)) {
        Yes 'both channel feeds are on disk when one of them is' $false
    } else {
        $page = [IO.File]::ReadAllText($Credits)
        Test-Holds $page $PublicFeed $DevFeed 'credits.md'
    }
} elseif ($hasPublic -or $hasDev) {
    Yes 'both channel feeds are on disk when one of them is' $false
} else {
    Write-Host 'SKIP  neither channel feed is on disk, so credits.md was not held to a feed here'
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
