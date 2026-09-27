<#
  test-remirror-feed.ps1

      pwsh .\tests\test-remirror-feed.ps1

  Remirror-Site-Feed.ps1 puts the tip version.json on the site along with every
  asset it names, so /feed/version.json and /feed/assets/<sha256> match
  Thornswood-Releases. Publish-Update.ps1 -HostAssetUrls has written those urls
  since the #649 cutover, and until this script nothing sent the bytes.

  What is checked, all against scratch files and without connecting to
  anything:

    the block that works out which assets the feed needs, run on its own
      between its markers: host assets are collected in feed order, a GitHub
      url is counted and not mirrored, a url for the other channel is named
      and refused, the same sha named twice is one asset, and an entry with no
      url is skipped;
    the whole script with -Check, in a child PowerShell, against a scratch feed
      and a scratch asset folder: it says which assets it would send and which
      are missing, and sends nothing.

  The dry run needs ssh on the path only to find out that it cannot reach a
  VPS; it is pointed at an address that answers nothing, and -Check is the
  switch that makes an unreachable site a line on screen rather than a stop.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$repo = Split-Path -Parent $here
$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    exit $(if ($script:fail) { 1 } else { 0 })
}

$mirror = Join-Path $repo 'scripts\deploy\Remirror-Site-Feed.ps1'
$rules  = Join-Path $repo 'scripts\release\Feed-Rules.ps1'
if (-not (Test-Path -LiteralPath $mirror)) { Yes 'Remirror-Site-Feed.ps1 is in scripts\deploy' $false; Done }
if (-not (Test-Path -LiteralPath $rules))  { Yes 'Feed-Rules.ps1 is in scripts\release' $false; Done }
. $rules

# ------------------------------------------------- the block, on its own ---
$src = Get-Content -LiteralPath $mirror -Raw
$open  = '# ==== thornswood feed assets wanted ===='
$close = '# ==== end thornswood feed assets wanted ===='
$a = $src.IndexOf($open)
$b = $src.IndexOf($close)
Yes 'the block that works out what the feed needs is still between its markers' ($a -ge 0 -and $b -gt $a)
if ($a -lt 0 -or $b -le $a) {
    Write-Host '  Remirror-Site-Feed.ps1 moved or renamed its markers, so this test can read nothing.' -ForegroundColor Red
    Done
}
$block = $src.Substring($a, $b - $a)

# The two readers the script carries, so the block can be run without it.
function Prop($obj, $name) {
    if ($null -eq $obj) { return '' }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return '' }
    return [string]$p.Value
}
function PropList($obj, $name) {
    if ($null -eq $obj) { return @() }
    $p = $obj.PSObject.Properties[$name]
    if ($null -eq $p) { return @() }
    return @($p.Value)
}

function Sha([string]$seed) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($seed)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}
function FeedUrl([string]$sha, [string]$channel) { return "https://thornswood.net/$channel/assets/$sha" }

$shaLauncher = Sha 'launcher'
$shaClient   = Sha 'client'
$shaPackOne  = Sha 'pack one'
$shaPackTwo  = Sha 'pack two'

$feed = [pscustomobject]@{
    launcherVersion = '1.1.101'
    launcherUrl     = (FeedUrl $shaLauncher 'feed')
    launcherSha256  = $shaLauncher
    packs           = @(
        [pscustomobject]@{ id = 'a-github'; url = 'https://api.github.com/repos/EvilPatrick06/Thornswood-Releases/releases/assets/591560398'; sha256 = $shaPackOne },
        [pscustomobject]@{ id = 'b-host';   url = (FeedUrl $shaPackOne 'feed');     sha256 = $shaPackOne },
        [pscustomobject]@{ id = 'c-dev';    url = (FeedUrl $shaPackTwo 'feed-dev'); sha256 = $shaPackTwo },
        [pscustomobject]@{ id = 'd-again';  url = (FeedUrl $shaPackOne 'feed');     sha256 = $shaPackOne },
        [pscustomobject]@{ id = 'e-no-url'; sha256 = $shaPackTwo },
        [pscustomobject]@{ id = 'f-nowhere'; url = ('https://evil.example/feed/assets/' + $shaPackTwo); sha256 = $shaPackTwo }
    )
    optional        = @([pscustomobject]@{ id = 'g-optional'; url = (FeedUrl $shaPackTwo 'feed') })
    clientRuntime   = [pscustomobject]@{ url = (FeedUrl $shaClient 'feed'); sha256 = $shaClient; forkCommit = 'd0006351' }
}

$doc = $feed
$prefix = 'feed'
Invoke-Expression $block
$order = @($need.Keys)
Yes 'the launcher, the client runtime and the host packs are what it asks for, in feed order' `
    (($order -join ',') -eq (($shaLauncher, $shaClient, $shaPackOne, $shaPackTwo) -join ','))
Yes 'and each one is named by what publishes it' `
    ($need[$shaLauncher] -eq 'launcher 1.1.101' -and
     $need[$shaClient] -eq 'client runtime d0006351' -and
     $need[$shaPackOne] -eq 'pack b-host' -and
     $need[$shaPackTwo] -eq 'optional pack g-optional')
Yes 'the same sha named twice is one asset, not two' (@($order | Where-Object { $_ -eq $shaPackOne }).Count -eq 1)
Yes 'the two urls a launcher fetches from GitHub are counted and not mirrored' ($offSite -eq 2)
Yes 'the dev channel pack is named as not mirrored by this run' `
    (@($wrongChannel).Count -eq 1 -and $wrongChannel[0] -match 'pack c-dev is published under /feed-dev/')
Yes 'and it is not in the list to send' (-not $need.Contains($shaPackTwo) -or $need[$shaPackTwo] -ne 'pack c-dev')

# The same feed read for the dev channel: now the dev pack is wanted and the
# live ones are what this run leaves alone.
$doc = $feed
$prefix = 'feed-dev'
Invoke-Expression $block
Yes 'read as the dev channel, the dev pack is the only one it would send' `
    ((@($need.Keys) -join ',') -eq $shaPackTwo)
# The launcher, the client runtime, both host packs and the optional one: five
# lines, one for each url, because each one is a line somebody has to read.
Yes 'and every live url is named as belonging to the other channel' `
    (@($wrongChannel).Count -eq 5)

# ------------------------------------------------- the script, dry run -----
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host 'SKIP  no ssh here, so the dry run was not attempted'
    Done
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-remirror-' + [Guid]::NewGuid().ToString('N'))
$feedDir = Join-Path $tmp 'feed'
$assets  = Join-Path $tmp 'assets'
New-Item -ItemType Directory -Path $feedDir -Force | Out-Null
New-Item -ItemType Directory -Path $assets -Force | Out-Null
try {
    # One asset that is on this machine under its own hash, and one the feed
    # names that nobody has.
    $bytes = [Text.Encoding]::UTF8.GetBytes("a pack, near enough`n")
    $packFile = Join-Path $assets 'pack-20260927-0508.zip'
    [IO.File]::WriteAllBytes($packFile, $bytes)
    $packSha = (Get-FileHash -LiteralPath $packFile -Algorithm SHA256).Hash.ToLower()
    $goneSha = 'b' * 64
    $scratch = [ordered]@{
        launcherVersion = '1.1.101'
        launcherUrl     = (FeedUrl $goneSha 'feed')
        launcherSha256  = $goneSha
        packs           = @([ordered]@{ id = '20260927-0508'; url = (FeedUrl $packSha 'feed'); sha256 = $packSha; notes = 'a pack' })
    }
    [IO.File]::WriteAllText((Join-Path $feedDir 'version.json'),
        ($scratch | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))

    # 127.0.0.1 with a user nobody has: BatchMode means it gives up at once
    # rather than asking for a password. -Check is what turns "the site did not
    # answer" into a line on screen.
    $shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    $said = & $shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $mirror `
        -Check -FeedDir $feedDir -AssetDir $assets -Vps '127.0.0.1' -User 'thornswood-no-such-user' 2>&1
    $code = $LASTEXITCODE
    $text = (@($said) -join [Environment]::NewLine)

    Yes 'the dry run finishes without a stop' ($code -eq 0)
    Yes 'it reads the feed it was pointed at' ($text -match 'launcher 1\.1\.101, 1 pack\(s\), for /feed/ on the site')
    Yes 'it says the site did not answer rather than stopping' ($text -match 'did not say what is already up there')
    Yes 'the pack it can find on this machine is one it would send' ($text -match ('to send\s+' + $packSha.Substring(0, 12)))
    Yes 'the launcher nobody has is named as missing' ($text -match ('MISSING\s+' + $goneSha.Substring(0, 12)))
    Yes 'and nothing left this machine' ($text -match 'may already be up there|Nothing left this machine')
    Yes 'it never printed the address of the VPS it was not given' ($text -notmatch '192\.135\.112\.23')
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

Done
