<#
  test-2727-feed-swap-readers.ps1

      pwsh -NoProfile -File .\tests\test-2727-feed-swap-readers.ps1

  Issue #2727. On 18 Oct a build on a VPS runner stopped the real
  Publish-Update.ps1 with NOT SHIPPED: version.json "could not be replaced
  by version.json.part: Access is denied". The feed store swapped the file
  in with MoveFileEx(MOVEFILE_REPLACE_EXISTING), and Windows refuses that
  plain rename while ANY handle is open on the file it replaces: one opened
  with share-delete, even one that only reads its attributes, the way a stat
  does. The site (site\server.js) stats version.json for every launcher's
  304 and every feed watch tick and reads it for every 200, so a Ship could
  stop because somebody's launcher asked for the feed at that moment.
  Measured on One: 2000 swaps beside a node loop doing server.js's
  statSync and readFileSync, MoveFileEx refused 1616.

  The swap is now a rename with POSIX semantics (FileRenameInfoEx). A
  reader that opened the file with share-delete keeps the old bytes it is
  reading and the name is the new file at once. A handle opened without
  share-delete still refuses it, so every read of a store file in
  Feed-Store.ps1 shares delete.

  WHAT IT HOLDS IT TO.
    1. Feed-Store.ps1's rename is FileRenameInfoEx with POSIX semantics, not
       MoveFileEx, and every read in the script the VPS runs shares delete.
    2. In this shell and in Windows PowerShell 5.1 (the VPS runs the store's
       script with it): a reader holding version.json open with share-delete
       does not stop Move-FeedStoreInto, keeps reading the old bytes, and the
       name reads the new ones; a holder without share-delete is refused,
       and the file stays the old one, whole; and the real send
       (Receive-FeedStore, then Send-FeedStore on a stand-in -SiteDir) lands
       while a reader holds the store's version.json.
    3. node, which serves the feed: a node process holding version.json
       open the way readFileSync opens it does not stop the swap, reads the
       old bytes through what it held and the new ones by name; and node
       reading the file the way site\server.js serves it (statSync, then
       readFileSync, 2000 times) while this shell swaps it for as long as
       node reads (300 to 3000 swaps): no swap refused, and the reader never
       found it missing.

  -Repo runs it against another checkout's scripts (for the code before the
  fix). Nothing outside its own temp folder is written.
#>
[CmdletBinding()]
param([string]$Repo)

$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = Split-Path -Parent $PSScriptRoot }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
    if ($script:fail -gt 0) { exit 1 }
    exit 0
}
function Text([string]$p) { return ([IO.File]::ReadAllText($p) -replace "`r`n", "`n") }

$storePs1 = Join-Path $Repo 'scripts\release\Feed-Store.ps1'
Yes 'scripts\release\Feed-Store.ps1 is there' (Test-Path -LiteralPath $storePs1)
if (-not (Test-Path -LiteralPath $storePs1)) { Done }

# ---- 1: the rename and the reads ----------------------------------------------------
$store = Text $storePs1
$swap = [regex]::Match($store, "(?s)\`$script:FeedStoreSwap = @'\n(.*?)\n'@").Groups[1].Value
$body = [regex]::Match($store, "(?s)\`$script:FeedStoreBody = @'\n(.*?)\n'@").Groups[1].Value
Yes 'Feed-Store: the rename renames with FileRenameInfoEx, replacing, with POSIX semantics' (
    $swap -match 'SetFileInformationByHandle\(h, FileRenameInfoEx, info' -and $swap -match 'const int FileRenameInfoEx = 22;' -and
    $swap -match 'const int Flags = 0x1 \| 0x2;')
Yes '...and not MoveFileEx, which any open handle on the old file refuses' ($swap -notmatch 'MoveFileEx')
Yes '...the box''s script swaps each file in with Move-FeedStoreInto' ($body -match 'Move-FeedStoreInto \$part \$p')
Yes '...and every read of a store file in it shares delete' (
    $body -match '\[IO\.FileShare\]::ReadWrite -bor \[IO\.FileShare\]::Delete' -and
    $body -notmatch '\[IO\.File\]::(OpenRead|ReadAllText|ReadAllBytes|ReadAllLines|Open)\(')
$sha = [regex]::Match($store, '(?s)function Get-FeedStoreSha\(.*?\n\}').Value
Yes '...and so does this machine''s read of its working folder' ($sha -match '\[IO\.FileShare\]::ReadWrite -bor \[IO\.FileShare\]::Delete' -and $sha -notmatch 'OpenRead')
$server = Text (Join-Path (Split-Path -Parent $PSScriptRoot) 'site\server.js')
$feedBranch = [regex]::Match($server, '(?s)const feedVer = p\.match.*?\n  \}\n').Value
Yes 'site\server.js serves version.json with statSync and readFileSync, the reads part 3 stands in for' (
    $feedBranch -match 'fs\.statSync\(file\)' -and $feedBranch -match 'fs\.readFileSync\(file\)')

$work = Join-Path ([IO.Path]::GetTempPath()) ('ts-2727-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Force -Path $work
$oldAppData = $env:LOCALAPPDATA
$reader = $null
try {
    # ---- 2: held open, in this shell and in Windows PowerShell 5.1 --------------------
    # The same script in both: it prints one line a check, OK or NO and what it saw.
    $held = Join-Path $work 'held.ps1'
    [IO.File]::WriteAllText($held, @'
param($store, $dir)
$ErrorActionPreference = 'Stop'
. $store
$share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
function Say([string]$name, [bool]$ok, [string]$saw) { ($(if ($ok) { 'OK ' } else { 'NO ' }) + $name + ' | ' + $saw) }
function Swap($from, $to) { try { Move-FeedStoreInto $from $to; return '' } catch { return [string]$_.Exception.Message } }

# a. a reader with share-delete, as node opens it
$to = Join-Path $dir 'a\version.json'; $part = $to + '.part'
$null = New-Item -ItemType Directory -Force -Path (Split-Path $to)
[IO.File]::WriteAllText($to, '{"feed":"old"}'); [IO.File]::WriteAllText($part, '{"feed":"new one"}')
$h = New-Object IO.FileStream($to, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
$err = Swap $part $to
$r = New-Object IO.StreamReader($h); $was = $r.ReadToEnd(); $r.Dispose()
$now = [IO.File]::ReadAllText($to)
Say 'shared' ($err -eq '' -and $was -eq '{"feed":"old"}' -and $now -eq '{"feed":"new one"}' -and -not (Test-Path -LiteralPath $part)) ("error '" + $err + "', the reader read " + $was + ", the name reads " + $now)

# b. a holder without share-delete
$to = Join-Path $dir 'b\version.json'; $part = $to + '.part'
$null = New-Item -ItemType Directory -Force -Path (Split-Path $to)
[IO.File]::WriteAllText($to, '{"feed":"old"}'); [IO.File]::WriteAllText($part, '{"feed":"new one"}')
$h = New-Object IO.FileStream($to, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
$err = Swap $part $to
$h.Dispose()
$now = [IO.File]::ReadAllText($to)
Say 'unshared' ($err -match 'being used by another process' -and $now -eq '{"feed":"old"}' -and (Test-Path -LiteralPath $part)) ("error '" + $err + "', the name reads " + $now)

# c. the real send on a stand-in site, a reader holding the store's version.json
$site = Join-Path $dir 'site'
$feed = Join-Path $site 'feed'
$null = New-Item -ItemType Directory -Force -Path $feed
[IO.File]::WriteAllText((Join-Path $feed 'version.json'), '{"launcherVersion":"1.0.1","packs":[]}')
[IO.File]::WriteAllText((Join-Path $feed 'published.json'), '{}')
$wd = Join-Path $dir 'working'
$err = ''
$sent = @()
try {
    [void](Receive-FeedStore 'main' $wd @('version.json', 'published.json') -SiteDir $site)
    [IO.File]::WriteAllText((Join-Path $wd 'version.json'), '{"launcherVersion":"1.0.2","packs":[]}')
    $h = New-Object IO.FileStream((Join-Path $feed 'version.json'), [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
    try { $sent = @((Send-FeedStore 'main' $wd @('version.json') -SiteDir $site).Sent) } finally { $h.Dispose() }
} catch { $err = [string]$_.Exception.Message }
$now = [IO.File]::ReadAllText((Join-Path $feed 'version.json'))
Say 'send' ($err -eq '' -and $sent -contains 'version.json' -and $now -eq '{"launcherVersion":"1.0.2","packs":[]}') ("error '" + $err + "', sent " + ($sent -join ',') + ", the site's copy reads " + $now)
'@, (New-Object Text.UTF8Encoding($false)))

    $env:LOCALAPPDATA = Join-Path $work 'appdata'
    $shells = @(@{ Name = ('this shell, PowerShell ' + $PSVersionTable.PSVersion.ToString()); Run = { param($d) & $held $storePs1 $d } })
    $ps51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Yes 'Windows PowerShell 5.1, which the VPS runs the store''s script with, is here' (Test-Path -LiteralPath $ps51)
    if (Test-Path -LiteralPath $ps51) {
        $shells += @{ Name = 'Windows PowerShell 5.1'; Run = { param($d) & $ps51 -NoProfile -ExecutionPolicy Bypass -File $held $storePs1 $d 2>&1 } }
    }
    $k = 0
    foreach ($s in $shells) {
        $k++
        $d = Join-Path $work ('held-' + $k)
        $null = New-Item -ItemType Directory -Force -Path $d
        $out = @(& $s.Run $d | ForEach-Object { [string]$_ })
        function Line([string]$name) { return @($out | Where-Object { $_ -match ('^(OK|NO) ' + $name + ' \|') }) }
        $a = @(Line 'shared'); $b = @(Line 'unshared'); $c = @(Line 'send')
        $why = { param($l) if ($l.Count) { ' (' + ($l[0] -replace '^(OK|NO) \S+ \| ', '') + ')' } else { ' (no answer: ' + (($out | Select-Object -Last 2) -join ' ') + ')' } }
        Yes ("$($s.Name): a reader with share-delete open on version.json does not stop the swap; it reads the old bytes, the name the new" + (& $why $a)) ($a.Count -eq 1 -and $a[0].StartsWith('OK '))
        Yes ("$($s.Name): a holder without share-delete is refused, and the file stays the old one, whole" + (& $why $b)) ($b.Count -eq 1 -and $b[0].StartsWith('OK '))
        Yes ("$($s.Name): the real send lands while a reader holds the store's version.json" + (& $why $c)) ($c.Count -eq 1 -and $c[0].StartsWith('OK '))
    }
    $env:LOCALAPPDATA = $oldAppData

    # ---- 3: beside the site's own reads ------------------------------------------------
    $node = Get-Command node -ErrorAction SilentlyContinue
    Yes 'node is on PATH, for the stand-in of the site''s reads' ($null -ne $node)
    if ($null -eq $node) { Done }
    . $storePs1
    # One read held open across the swap: the file opened the way readFileSync
    # opens it (libuv, share-delete), the swap, then the read through that fd.
    $holdJs = Join-Path $work 'hold.js'
    [IO.File]::WriteAllText($holdJs, @'
const fs = require('fs');
const file = process.argv[2];
const fd = fs.openSync(file, 'r');
console.log('holding');
process.stdin.once('data', () => {
  const held = fs.readFileSync(fd, 'utf8');
  fs.closeSync(fd);
  console.log(JSON.stringify({ held: held, now: fs.readFileSync(file, 'utf8') }));
  process.exit(0);
});
'@, (New-Object Text.UTF8Encoding($false)))
    $hj = Join-Path $work 'hold\version.json'
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $hj)
    [IO.File]::WriteAllText($hj, '{"feed":"old"}'); [IO.File]::WriteAllText($hj + '.part', '{"feed":"new one"}')
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source; $psi.Arguments = '"' + $holdJs + '" "' + $hj + '"'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardInput = $true
    $reader = [Diagnostics.Process]::Start($psi)
    $first = $reader.StandardOutput.ReadLineAsync()
    $holding = $first.Wait(15000) -and $first.Result -eq 'holding'
    $err = ''
    if ($holding) { try { Move-FeedStoreInto ($hj + '.part') $hj } catch { $err = [string]$_.Exception.Message } }
    $reader.StandardInput.WriteLine('go'); $reader.StandardInput.Close()
    $answer = $reader.StandardOutput.ReadToEndAsync()
    $null = $reader.WaitForExit(15000)
    $saw = $null; try { $saw = ([string]$answer.Result).Trim() | ConvertFrom-Json } catch { $saw = $null }
    Yes ("node holding version.json open as server.js's readFileSync opens it does not stop the swap (" + $(if ($err) { $err } else { 'replaced' }) + ")") ($holding -and $err -eq '')
    Yes ("...node reads the old bytes through what it held, and the new ones by name (" + ([string]$answer.Result).Trim() + ")") (
        $null -ne $saw -and $saw.held -eq '{"feed":"old"}' -and $saw.now -eq '{"feed":"new one"}')
    $reader.Dispose(); $reader = $null

    $loopJs = Join-Path $work 'reads.js'
    [IO.File]::WriteAllText($loopJs, @'
// site/server.js on GET /feed/version.json: statSync for the ETag, then
// readFileSync for the body, 2000 times, while the harness swaps the file.
const fs = require('fs');
const file = process.argv[2];
let passes = 0, missing = 0, other = 0;
console.log('reading');
for (let i = 0; i < 2000; i++) {
  try { fs.statSync(file); fs.readFileSync(file); passes++; }
  catch (e) { if (e.code === 'ENOENT') missing++; else other++; }
}
console.log('passes ' + passes + ' missing ' + missing + ' other ' + other);
'@, (New-Object Text.UTF8Encoding($false)))
    $vj = Join-Path $work 'race\version.json'
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $vj)
    $doc = '{"launcherVersion":"1.0.1","news":"' + ('x' * 90000) + '"}'
    [IO.File]::WriteAllText($vj, $doc)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source; $psi.Arguments = '"' + $loopJs + '" "' + $vj + '"'
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
    $reader = [Diagnostics.Process]::Start($psi)
    $first = $reader.StandardOutput.ReadLineAsync()
    $started = $first.Wait(15000) -and $first.Result -eq 'reading'
    Yes 'the node reader is reading' $started
    if (-not $started) { Done }
    # Swaps for as long as node reads, at least 300 and at most 3000 of them.
    $last = $reader.StandardOutput.ReadToEndAsync()
    $refused = 0; $said = ''; $swaps = 0
    while (($swaps -lt 300 -or -not $last.IsCompleted) -and $swaps -lt 3000) {
        [IO.File]::WriteAllText($vj + '.part', $doc)
        try { Move-FeedStoreInto ($vj + '.part') $vj }
        catch { $refused++; if (-not $said) { $said = $_.Exception.Message } }
        $swaps++
    }
    $null = $reader.WaitForExit(30000)
    $tally = [regex]::Match([string]$last.Result, 'passes (\d+) missing (\d+) other (\d+)')
    Yes ("{0} swaps while node read it the way server.js serves it: none refused ({1} refused{2})" -f $swaps, $refused, $(if ($said) { ', first: ' + $said } else { '' })) ($refused -eq 0)
    Yes ("...and the reader never found it missing or failed to read it ({0})" -f $(if ($tally.Success) { $tally.Value } else { 'no tally: ' + [string]$last.Result })) (
        $tally.Success -and $tally.Groups[2].Value -eq '0' -and $tally.Groups[3].Value -eq '0')
}
finally {
    $env:LOCALAPPDATA = $oldAppData
    if ($reader) { try { if (-not $reader.HasExited) { $reader.Kill() } } catch { Write-Host "NOTE  the node reader could not be stopped: $($_.Exception.Message)" } }
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction Stop } catch { Write-Host "NOTE  $work could not be removed: $($_.Exception.Message)" }
}

Done
