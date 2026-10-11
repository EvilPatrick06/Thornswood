<#
  test-bad-json-records.ps1

      powershell -NoProfile -File .\tests\test-bad-json-records.ps1
      pwsh -NoProfile -File .\tests\test-bad-json-records.ps1

  A record that is empty, cut off or not JSON at all, fed straight to
  ConvertFrom-Json, came out as a bare parse error ("Invalid JSON primitive",
  "Conversion from JSON failed", or 5.1's "Cannot bind argument to parameter
  'InputObject' because it is null") or a null property later, and none of
  them named the file. Each now names it:
    Sync-Client.ps1        the client build record (-Record)
    Set-Collection.ps1     config.json and the feed's version.json
    Set-Server.ps1         config.json and the feed's version.json
    Where.ps1              layout.json (scratch copy of the script)
    Ship-Rules.ps1         records\ui-gone.json (scratch copy)
  Scratch files only. -ReleaseDir with -NoPush, so no feed is received or sent;
  Set-Collection runs from a scratch copy whose Feed-Store is a stub.
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$Shell = (Get-Process -Id $PID).Path
$script:pass = 0; $script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" } else { $script:fail++; Write-Host "FAIL  $what" }
}
$T = Join-Path ([IO.Path]::GetTempPath()) ('ts-badjson-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
[void][IO.Directory]::CreateDirectory($T)
function W([string]$p, [string]$t) { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $p)); [IO.File]::WriteAllText($p, $t, (New-Object Text.UTF8Encoding($false))) }
function Child([string[]]$a) {
    $ErrorActionPreference = 'Continue'
    $o = & $Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File @a 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Out = ($o -replace '\s+', ' ') }
}
$bad = [ordered]@{ 'empty' = ''; 'cut off' = '{"files": {"a": {"sha256": "ab'; 'not JSON' = 'this is not json' }
$expect = @{ 'empty' = 'is empty'; 'cut off' = 'is not valid JSON'; 'not JSON' = 'is not valid JSON' }
function Named($r, [string]$path, [string]$kind) { $r.Code -ne 0 -and $r.Out.Contains(($path -replace '\s+', ' ') + ' ' + $expect[$kind]) }
try {
    # ---- Sync-Client -Record --------------------------------------------------------
    $game = Join-Path $T 'Game'; $dist = Join-Path $T 'dist'
    [void][IO.Directory]::CreateDirectory($game); [void][IO.Directory]::CreateDirectory($dist)
    foreach ($k in $bad.Keys) {
        $rec = Join-Path $T 'client-build.json'; W $rec $bad[$k]
        $r = Child @((Join-Path $Repo 'scripts\release\Sync-Client.ps1'), '-Record', $rec, '-Game', $game, '-Dist', $dist, '-Check', '-NoPause')
        Yes ("Sync-Client: a client record that is {0} is named ({1})" -f $k, $expect[$k]) (Named $r $rec $k)
    }

    # ---- Set-Server: config.json, then version.json ------------------------------------
    $root = Join-Path $T 'ss-root'; $rel = Join-Path $T 'ss-feed'
    foreach ($k in $bad.Keys) {
        W (Join-Path $root 'config.json') $bad[$k]; W (Join-Path $rel 'version.json') '{"serverAddress":"a","serverPort":"1"}'
        $r = Child @((Join-Path $Repo 'scripts\ops\Set-Server.ps1'), '-Address', '192.0.2.5', '-Root', $root, '-ReleaseDir', $rel, '-Force', '-NoPush', '-NoPause')
        Yes ("Set-Server: a config.json that is {0} is named, and the feed is untouched" -f $k) ((Named $r (Join-Path $root 'config.json') $k) -and [IO.File]::ReadAllText((Join-Path $rel 'version.json')) -match '"serverAddress":"a"')
    }
    foreach ($k in $bad.Keys) {
        W (Join-Path $root 'config.json') '{"ServerAddress":"x","ServerPort":1}'; W (Join-Path $rel 'version.json') $bad[$k]
        $r = Child @((Join-Path $Repo 'scripts\ops\Set-Server.ps1'), '-Address', '192.0.2.5', '-Root', $root, '-ReleaseDir', $rel, '-Force', '-NoPush', '-NoPause')
        Yes ("Set-Server: a version.json that is {0} is named" -f $k) (Named $r (Join-Path $rel 'version.json') $k)
    }

    # ---- Set-Collection, from a scratch copy with a stub Feed-Store --------------------
    $sc = Join-Path $T 'sc'
    [void][IO.Directory]::CreateDirectory((Join-Path $sc 'scripts\ops'))
    [IO.File]::Copy((Join-Path $Repo 'scripts\ops\Set-Collection.ps1'), (Join-Path $sc 'scripts\ops\Set-Collection.ps1'))
    W (Join-Path $sc 'scripts\release\Feed-Store.ps1') "function Get-FeedStoreDir { 'unused' }`nfunction Receive-FeedStore { throw 'stub: no receive' }`nfunction Send-FeedStore { throw 'stub: no send' }`n"
    $croot = Join-Path $T 'sc-root'; $cfeed = Join-Path $T 'sc-feed'
    $url = 'https://www.nexusmods.com/games/skyrimspecialedition/collections/abc'
    foreach ($k in $bad.Keys) {
        W (Join-Path $croot 'config.json') $bad[$k]; W (Join-Path $cfeed 'version.json') '{}'
        $r = Child @((Join-Path $sc 'scripts\ops\Set-Collection.ps1'), '-Url', $url, '-Root', $croot, '-ReleaseDir', $cfeed, '-NoPush', '-NoPause')
        Yes ("Set-Collection: a config.json that is {0} is named" -f $k) (Named $r (Join-Path $croot 'config.json') $k)
        W (Join-Path $croot 'config.json') '{}'; W (Join-Path $cfeed 'version.json') $bad[$k]
        $r = Child @((Join-Path $sc 'scripts\ops\Set-Collection.ps1'), '-Url', $url, '-Root', $croot, '-ReleaseDir', $cfeed, '-NoPush', '-NoPause')
        Yes ("Set-Collection: a version.json that is {0} is named" -f $k) (Named $r (Join-Path $cfeed 'version.json') $k)
    }

    # ---- Where.ps1 and layout.json ----------------------------------------------------
    $wh = Join-Path $T 'wh'
    [void][IO.Directory]::CreateDirectory((Join-Path $wh 'scripts\release'))
    [IO.File]::Copy((Join-Path $Repo 'scripts\release\Where.ps1'), (Join-Path $wh 'scripts\release\Where.ps1'))
    foreach ($k in $bad.Keys) {
        W (Join-Path $wh 'layout.json') $bad[$k]
        $r = Child @((Join-Path $wh 'scripts\release\Where.ps1'), 'Repo')
        Yes ("Where.ps1: a layout.json that is {0} is named" -f $k) ($r.Out.Contains('layout.json at ' + ((Join-Path $wh 'layout.json') -replace '\s+', ' ') + ' ' + $expect[$k]))
    }

    # ---- Ship-Rules and records\ui-gone.json ------------------------------------------
    $sr = Join-Path $T 'sr'
    [void][IO.Directory]::CreateDirectory((Join-Path $sr 'scripts\release'))
    [IO.File]::Copy((Join-Path $Repo 'scripts\release\Ship-Rules.ps1'), (Join-Path $sr 'scripts\release\Ship-Rules.ps1'))
    $load = Join-Path $sr 'load.ps1'
    W $load ("`$ErrorActionPreference = 'Stop'`ntry { . '" + (Join-Path $sr 'scripts\release\Ship-Rules.ps1').Replace("'", "''") + "'; 'LOADED' } catch { 'THREW ' + `$_.Exception.Message; exit 1 }`n")
    foreach ($k in $bad.Keys) {
        W (Join-Path $sr 'records\ui-gone.json') $bad[$k]
        $r = Child @($load)
        Yes ("Ship-Rules: a ui-gone.json that is {0} is named" -f $k) ($r.Out -match ('THREW records\\ui-gone\.json ' + $expect[$k]))
    }
    [IO.File]::Copy((Join-Path $Repo 'records\ui-gone.json'), (Join-Path $sr 'records\ui-gone.json'), $true)
    $r = Child @($load)
    Yes '  and the real one still loads' ($r.Out -match 'LOADED')
}
finally { Remove-Item -LiteralPath $T -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }