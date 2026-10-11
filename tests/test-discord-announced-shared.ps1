<#
  test-discord-announced-shared.ps1

      pwsh -NoProfile -File .\tests\test-discord-announced-shared.ps1

  Publish-Discord.ps1 keeps what it announced in the channel's VPS store
  (announced.json beside the feed, through Feed-Store.ps1), not in the
  checkout that posted (#2167). Two scratch checkouts share one stand-in
  store ($env:THORNSWOOD_TEST_SITE_DIR, so nothing connects to the VPS) and a
  stand-in webhook on 127.0.0.1 (so nothing reaches Discord):
    - a post from checkout A lands in the store, and a dry run from checkout
      B then says "already announced";
    - -Record from one checkout is seen by the other;
    - a new release is not taken for an old one, and -Force still posts;
    - an old bot\announced.json is still read while the store has none;
    - a store that cannot be read posts nothing.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
$pwshExe = (Get-Process -Id $PID).Path

$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" -ForegroundColor Red }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tw-announced-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$site = Join-Path $tmp 'site'
$local = Join-Path $tmp 'localappdata'
foreach ($d in (Join-Path $site 'feed'), (Join-Path $site 'feed-dev'), $local) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

$listener = New-Object Net.HttpListener
$port = 0
foreach ($try in 1..20) {
    $port = Get-Random -Minimum 41000 -Maximum 59000
    try { $listener = New-Object Net.HttpListener; $listener.Prefixes.Add("http://127.0.0.1:$port/"); $listener.Start(); break } catch { $port = 0 }
}
if (-not $port) { throw 'no free port for the stand-in webhook' }

function New-Checkout([string]$name) {
    $c = Join-Path $tmp $name
    New-Item -ItemType Directory -Force -Path (Join-Path $c 'bot') | Out-Null
    Copy-Item -LiteralPath (Join-Path $Repo 'scripts') -Destination (Join-Path $c 'scripts') -Recurse
    # The webhook, never the real one: Discord-Hook.ps1 would ask the VPS.
    [IO.File]::WriteAllText((Join-Path $c 'scripts\ops\Discord-Hook.ps1'), "param([string]`$Name, [string]`$RemoteScript)`r`n'http://127.0.0.1:$port/hook'`r`n")
    return $c
}
$A = New-Checkout 'A'
$B = New-Checkout 'B'

$feed = Join-Path $tmp 'feed-dev'
New-Item -ItemType Directory -Force -Path $feed | Out-Null
function Set-Feed([string]$ver, [string]$title) {
    $j = @{ launcherVersion = $ver; news = @(@{ title = $title; date = '2026-10-11'; details = @('The door opens on the first knock.'); body = '' }) } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $feed 'version.json'), $j)
}

$script:posts = 0
function Run([string]$checkout, [string[]]$more, [switch]$Serve) {
    $out = Join-Path $tmp ('out-' + [guid]::NewGuid().ToString('N') + '.txt')
    $a = @('-NoProfile', '-NonInteractive', '-File', (Join-Path $checkout 'scripts\ops\Publish-Discord.ps1'), '-Dev', '-ReleaseDir', $feed) + $more
    $env:THORNSWOOD_TEST_SITE_DIR = $script:siteNow
    $oldLocal = $env:LOCALAPPDATA; $env:LOCALAPPDATA = $local
    try { $p = Start-Process -FilePath $pwshExe -ArgumentList $a -RedirectStandardOutput $out -RedirectStandardError ($out + '.err') -PassThru -NoNewWindow }
    finally { $env:LOCALAPPDATA = $oldLocal; Remove-Item Env:\THORNSWOOD_TEST_SITE_DIR -ErrorAction SilentlyContinue }
    if ($Serve) {
        $task = $listener.GetContextAsync()
        if ($task.Wait(60000)) {
            $ctx = $task.Result; $script:posts++
            $ctx.Response.StatusCode = 204; $ctx.Response.Close()
        }
    }
    if (-not $p.WaitForExit(120000)) { $p.Kill(); throw 'Publish-Discord did not finish' }
    $text = ([IO.File]::ReadAllText($out) + [IO.File]::ReadAllText($out + '.err'))
    return $text
}
$script:siteNow = $site
$store = Join-Path $site 'feed-dev\announced.json'

try {
    Set-Feed '1.2.2' 'The door answers on the first knock'
    $o = Run $A @('-DryRun')
    Yes 'nothing recorded anywhere: a dry run from A says it would post' ($o -match 'would post to the dev updates channel')
    Yes '  and writes nothing into the store' (-not (Test-Path -LiteralPath $store))

    $o = Run $A @() -Serve
    Yes 'A posts it, through the stand-in webhook only' ($script:posts -eq 1 -and $o -match 'posted to Discord')
    Yes '  and the record is in the shared store, naming 1.2.2' ((Test-Path -LiteralPath $store) -and ([IO.File]::ReadAllText($store) -match '1\.2\.2'))
    Yes '  and not in either checkout''s bot folder' (-not (Test-Path (Join-Path $A 'bot\announced.json')) -and -not (Test-Path (Join-Path $B 'bot\announced.json')))

    # The other checkout, with its own working folder gone too: only the store knows.
    Remove-Item -LiteralPath (Join-Path $local 'Thornswood\feed\announced-dev') -Recurse -Force -ErrorAction SilentlyContinue
    $o = Run $B @('-DryRun')
    Yes 'a dry run from checkout B says already announced 1.2.2' ($o -match 'already announced 1\.2\.2 in the dev updates channel')
    $o = Run $B @()
    Yes '  and a real run from B posts nothing' ($script:posts -eq 1 -and $o -match 'already announced')

    $o = Run $B @('-Force') -Serve
    Yes '-Force from B still posts it again' ($script:posts -eq 2 -and $o -match 'posted to Discord')

    Set-Feed '1.2.3' 'Lanterns stay lit in the rain'
    $o = Run $B @('-DryRun')
    Yes 'a new release is not taken for the old one' ($o -match 'would post' -and $o -notmatch 'already announced')
    $o = Run $B @('-Record')
    Yes '-Record from B records 1.2.3 and posts nothing' ($script:posts -eq 2 -and $o -match 'recorded 1\.2\.3 as announced')
    $o = Run $A @('-DryRun')
    Yes '  and a dry run from A then says already announced 1.2.3' ($o -match 'already announced 1\.2\.3')

    # A store with no record yet: the old per-checkout file still counts, read only.
    Remove-Item -LiteralPath $store -Force
    $legacy = @{ dev = @{ stamp = '1.2.3|Dev build: Lanterns stay lit in the rain'; version = '1.2.3' } } | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText((Join-Path $A 'bot\announced.json'), $legacy)
    $o = Run $A @('-DryRun')
    Yes 'with no record in the store, A''s old bot\announced.json still says already announced' ($o -match 'already announced 1\.2\.3')
    Yes '  and is not copied into the store by a dry run' (-not (Test-Path -LiteralPath $store))

    # A store that cannot be read (a third checkout whose store answers nothing): nothing posted.
    $C = New-Checkout 'C'
    Add-Content -LiteralPath (Join-Path $C 'scripts\release\Feed-Store.ps1') -Value "`r`nfunction Receive-FeedStore { throw 'stand-in: the VPS did not answer' }"
    $o = Run $C @()
    Yes 'a store that cannot be read: nothing posted, and it says so' ($script:posts -eq 2 -and $o -match 'COULD NOT READ what was already announced')

    $src = [IO.File]::ReadAllText((Join-Path $Repo 'scripts\ops\Publish-Discord.ps1'))
    Yes 'Publish-Discord.ps1 never writes bot\announced.json any more' ($src -notmatch 'Set-Content -LiteralPath \$stateFile' -and $src -match 'Send-FeedStore')
} finally {
    $listener.Stop()
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0