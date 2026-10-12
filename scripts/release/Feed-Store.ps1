<#
  Feed-Store.ps1

  Where each channel's feed, its release baseline and their history are kept,
  and the only code that reads or writes them there (#907).

      . (Join-Path $PSScriptRoot 'Feed-Store.ps1')

  WHY IT EXISTS. Until 28 September the feed (version.json) and the baseline
  Ship diffs against (published.json) lived in two git clones of
  EvilPatrick06/Thornswood-Releases beside the repository, pulled, committed
  and pushed by every script that edits the feed. Since #897 every download
  comes from thornswood.net, so that repository held nothing a launcher needs,
  and Patrick asked for it to go: "I just want the repo deleted in general if
  we won't be using it anymore". So the store moved to the VPS, beside the feed
  the site already serves:

      C:\Thornswood-Docs\feed\version.json      the live feed (served)
      C:\Thornswood-Docs\feed\published.json    the live baseline (not served)
      C:\Thornswood-Docs\feed\launchers.txt     every launcher version this
                                                channel has published (not served)
      C:\Thornswood-Docs\feed\releases.txt      every release the feed has named,
                                                by its id, with what else it is
                                                known by (#444, not served)
      C:\Thornswood-Docs\feed\releases.json     the record of each of the last
                                                thirty releases, which a rollback
                                                goes back to (#442); in the feed
                                                as "releases" until #1050 (not
                                                served). Received and sent by
                                                name, like published.json
      C:\Thornswood-Docs\feed\history\          each file as it was before it
                                                was replaced, <utc stamp>-<name>
                                                (not served)

  and the same under feed-dev for the dev channel. site\server.js answers only
  /feed[-dev]/version.json and /feed[-dev]/assets/<64 hex>, so nothing else in
  those folders can be fetched (tests\test-feed-store.ps1 asks a copy of it).

  ON THIS MACHINE each channel has a working folder, not a git repository:
  %LOCALAPPDATA%\Thornswood\feed\main and ...\feed\dev (Get-FeedStoreDir). A
  script receives the files into it, edits them there, and sends them back.
  read.json in that folder records the sha256 of each file as it was received,
  and backup\ keeps the last twenty copies of each file received, so this
  machine always has the last few feeds and baselines it saw.

  TWO PUBLISHERS AT ONCE. A send checks, on the VPS and in the same step that
  replaces the file, that every file it names still has the sha256 it had when
  this machine received it. If another Ship or feed edit has gone out since,
  nothing is replaced and the send throws, the way git refused a push that was
  behind. The file goes up as <name>.part first and is renamed over the old one
  only once it is whole, and the old one is copied into history\ first.

      Get-FeedStoreDir main|dev          this machine's working folder
      Receive-FeedStore main|dev -Dir    fetch the files, record what was read
      Send-FeedStore main|dev -Dir -Files version.json[, published.json]
                                         send them back, refusing if moved
      Get-FeedStoreThere main|dev        the sha256 of each file up there now
      Get-FeedStoreLaunchers main|dev    launchers.txt, one version a line
      Get-FeedStoreReleases main|dev     releases.txt, one release a line
      Read-SiteFeed main|dev             the feed as the public reads it
      Write-FeedVersionFile -Path -Doc   write version.json as every writer
                                         must: compact, no byte order mark
      Remove-FeedStoreAssets main|dev -Shas -Expect
                                         delete assets no feed names any more,
                                         refusing if either feed moved (#1152)

  -SiteDir <folder>, or $env:THORNSWOOD_TEST_SITE_DIR, stands in for
  C:\Thornswood-Docs on this machine: every read, send and rename happens in
  that folder, by the same script the VPS runs, and nothing connects anywhere.
  The tests use it.
#>

. (Join-Path $PSScriptRoot 'Read-JsonFile.ps1')   # ConvertFrom-ThornswoodJson: a bad JSON file named
function Get-FeedStorePrefix([string]$Channel) {
    if ($Channel -eq 'dev') { return 'feed-dev' }
    if ($Channel -eq 'main' -or -not $Channel) { return 'feed' }
    throw "Feed-Store.ps1 knows the channels main and dev, not '$Channel'."
}

# This machine's working folder for a channel. Under LOCALAPPDATA beside the
# pending-release notes, so every worktree on the machine shares one, and the
# uninstaller cannot reach it.
function Get-FeedStoreDir([string]$Channel) {
    $prefix = Get-FeedStorePrefix $Channel
    $name = if ($prefix -eq 'feed-dev') { 'dev' } else { 'main' }
    return (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Thornswood') 'feed') $name)
}

function Get-FeedStoreSiteDir([string]$SiteDir) {
    if ($SiteDir) { return $SiteDir }
    if ($env:THORNSWOOD_TEST_SITE_DIR) { return [string]$env:THORNSWOOD_TEST_SITE_DIR }
    return ''
}

function Get-FeedStoreSha([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    # .NET rather than Get-FileHash: that one comes from a module, and Windows
    # PowerShell started from a PowerShell 7 shell inherits a PSModulePath
    # whose Utility module it cannot load, so the command is not there.
    $h = [Security.Cryptography.SHA256]::Create()
    $s = [IO.File]::OpenRead((Resolve-Path -LiteralPath $path).ProviderPath)
    try { return (-join ($h.ComputeHash($s) | ForEach-Object { $_.ToString('x2') })) }
    finally { $s.Dispose(); $h.Dispose() }
}

# Where the VPS is, from scripts\vps\vps.json, unless the caller says.
function Get-FeedStoreVps([hashtable]$To) {
    $o = @{ Vps = ''; User = ''; Root = 'C:/Thornswood-Docs' }
    if ($null -ne $To) { foreach ($k in @($To.Keys)) { if ($To[$k]) { $o[$k] = [string]$To[$k] } } }
    if (-not $o.Vps -or -not $o.User) {
        $vpsPs1 = Join-Path $PSScriptRoot '..\vps\Vps.ps1'
        if (-not (Test-Path -LiteralPath $vpsPs1)) { throw "scripts\vps\Vps.ps1 is not beside Feed-Store.ps1, so the VPS address is not known." }
        . $vpsPs1
        if (-not $o.Vps) { $o.Vps = Get-ThornswoodVpsAddress }
        if (-not $o.User) { $o.User = Get-ThornswoodVpsUser }
    }
    return $o
}

# ------------------------------------------------------------ the one script
# Everything that happens up there is this one script, run by ssh on the VPS
# or in place on -SiteDir, so the tests run exactly what the VPS runs. It takes
# its inputs as the variables set in front of it and answers in lines:
#   HAVE|<name>|<sha>|<bytes>   NONE|<name>      (look)
#   L|<version>                                  (launchers)
#   R|<id><tab>...                               (releases)
#   MOVED|<what>   SHORT|<name>   SAME|<name>   SENT|<name>|<sha>   (swap)
#   DONE                                          (the end of every op)
$script:FeedStoreBody = @'
$ErrorActionPreference = 'Stop'
$dir = Join-Path $root $prefix
$hist = Join-Path $dir 'history'
$launchers = Join-Path $dir 'launchers.txt'
function Sha($p) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return '' }
  $h = [Security.Cryptography.SHA256]::Create()
  $s = [IO.File]::OpenRead((Resolve-Path -LiteralPath $p).ProviderPath)
  try { return (-join ($h.ComputeHash($s) | ForEach-Object { $_.ToString('x2') })) }
  finally { $s.Dispose(); $h.Dispose() }
}
function DropParts { foreach ($n in $names) { Remove-Item -LiteralPath (Join-Path $dir ($n + '.part')) -Force -ErrorAction SilentlyContinue } }
if ($op -eq 'look') {
  foreach ($n in $names) {
    $p = Join-Path $dir $n
    if (Test-Path -LiteralPath $p -PathType Leaf) { 'HAVE|' + $n + '|' + (Sha $p) + '|' + (Get-Item -LiteralPath $p).Length }
    else { 'NONE|' + $n }
  }
  'DONE'
  return
}
if ($op -eq 'launchers') {
  if (Test-Path -LiteralPath $launchers) {
    foreach ($l in @(Get-Content -LiteralPath $launchers)) { if ($l.Trim()) { 'L|' + $l.Trim() } }
  }
  'DONE'
  return
}
if ($op -eq 'releases') {
  $rel = Join-Path $dir 'releases.txt'
  if (Test-Path -LiteralPath $rel) {
    foreach ($l in @(Get-Content -LiteralPath $rel)) { if ($l.Trim()) { 'R|' + $l } }
  }
  'DONE'
  return
}
if ($op -eq 'forget') {
  # Deletes assets\<sha256> for each name, and only while both channels' feeds
  # are the bytes the caller read and found them missing from ($expect, keyed
  # 'feed\version.json' and 'feed-dev\version.json'). A name either feed or
  # either baseline still spells out is kept whatever the caller thought.
  $moved = @()
  foreach ($k in @($expect.Keys)) {
    $now = Sha (Join-Path $root $k)
    if ($now -ne [string]$expect[$k]) { $moved += ($k + ' was ' + ([string]$expect[$k]).Substring(0, 12) + ' and is ' + $(if ($now) { $now.Substring(0, 12) } else { 'absent' })) }
  }
  if ($moved.Count) { 'MOVED|' + ($moved -join '; '); return }
  # Names that still count as live assets. version.json is scanned as text
  # (pack and record sha256 fields), and so is releases.json, the list of
  # each release's record a rollback reads, which left version.json for the
  # store in #1050. published.json is often a baseline
  # record: only size:sha256 file entries name assets. A bare :gone: sha256
  # (#1261) is a launcher instruction, not a live asset, so it must not keep
  # the bytes on the site.
  $said = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($f in @('feed\version.json', 'feed-dev\version.json', 'feed\releases.json', 'feed-dev\releases.json')) {
    $p = Join-Path $root $f
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($p), '[0-9a-fA-F]{64}')) { [void]$said.Add($m.Value.ToLowerInvariant()) }
  }
  foreach ($f in @('feed\published.json', 'feed-dev\published.json')) {
    $p = Join-Path $root $f
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($p), '(?i)(\d+):([0-9a-f]{64})')) { [void]$said.Add($m.Groups[2].Value.ToLowerInvariant()) }
  }
  $assets = Join-Path $dir 'assets'
  foreach ($n in $names) {
    if ($n -notmatch '^[0-9a-f]{64}$') { 'BAD|' + $n; continue }
    if ($said.Contains($n)) { 'NAMED|' + $n; continue }
    $p = Join-Path $assets $n
    if (Test-Path -LiteralPath $p -PathType Leaf) { Remove-Item -LiteralPath $p -Force; 'GONE|' + $n }
    else { 'NONE|' + $n }
  }
  'DONE'
  return
}
if ($op -eq 'ready') {
  foreach ($d in @($dir, $hist)) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
  'DONE'
  return
}
if ($op -eq 'swap') {
  $moved = @()
  foreach ($n in $names) {
    $now = Sha (Join-Path $dir $n)
    if ($now -ne [string]$expect[$n]) {
      $was = if ([string]$expect[$n]) { ([string]$expect[$n]).Substring(0, 12) } else { 'absent' }
      $is = if ($now) { $now.Substring(0, 12) } else { 'absent' }
      $moved += ($n + ' was ' + $was + ' and is ' + $is)
    }
  }
  if ($moved.Count) { DropParts; 'MOVED|' + ($moved -join '; '); return }
  foreach ($n in @($sizes.Keys)) {
    $part = Join-Path $dir ($n + '.part')
    $len = -1
    if (Test-Path -LiteralPath $part -PathType Leaf) { $len = (Get-Item -LiteralPath $part).Length }
    if ($len -ne [int64]$sizes[$n]) { DropParts; 'SHORT|' + $n + '|' + $len + ' bytes of ' + $sizes[$n]; return }
  }
  if (-not (Test-Path -LiteralPath $hist)) { New-Item -ItemType Directory -Path $hist -Force | Out-Null }
  foreach ($n in $names) {
    if (-not $sizes.ContainsKey($n)) { 'SAME|' + $n; continue }
    $p = Join-Path $dir $n
    $part = $p + '.part'
    if (Test-Path -LiteralPath $p -PathType Leaf) {
      $keep = Join-Path $hist ($stamp + '-' + $n)
      $k = 2
      while (Test-Path -LiteralPath $keep) { $keep = Join-Path $hist ($stamp + '-' + $k + '-' + $n); $k++ }
      Copy-Item -LiteralPath $p -Destination $keep -Force
      # One rename over the old file, so the site never answers 404 between
      # the old feed and the new one.
      [IO.File]::Replace($part, $p, [NullString]::Value)
    } else {
      Move-Item -LiteralPath $part -Destination $p -Force
    }
    if ($n -eq 'version.json') {
      $m = [regex]::Match([IO.File]::ReadAllText($p), '"launcherVersion"\s*:\s*"([^"]+)"')
      if ($m.Success) {
        $v = $m.Groups[1].Value
        $had = @()
        if (Test-Path -LiteralPath $launchers) { $had = @(Get-Content -LiteralPath $launchers | ForEach-Object { $_.Trim() }) }
        if ($had -notcontains $v) { Add-Content -LiteralPath $launchers -Value $v -Encoding ASCII }
      }
      # releases.txt (#444): one line a release, tab separated, its id first,
      # then channel, launcher, packs, baseline, commit, tag, so its one name
      # finds the rest. Never a reason to fail a send that has already landed.
      try {
        $rd = ([IO.File]::ReadAllText($p) -replace '^\uFEFF', '') | ConvertFrom-Json
        if ($rd.PSObject.Properties['release'] -and $rd.release -and [string]$rd.release.id) {
          $r = $rd.release
          $f = @('id', 'channel', 'launcherVersion', 'packs', 'baseline', 'commit', 'tag') | ForEach-Object {
            if ($r.PSObject.Properties[$_]) { (@($r.$_) | ForEach-Object { [string]$_ }) -join ',' } else { '' }
          }
          $rel = Join-Path $dir 'releases.txt'
          $hadR = @(); if (Test-Path -LiteralPath $rel) { $hadR = @(Get-Content -LiteralPath $rel | ForEach-Object { ($_ -split "`t")[0] }) }
          if ($hadR -notcontains $f[0]) { Add-Content -LiteralPath $rel -Value ($f -join "`t") -Encoding ASCII }
        }
      } catch { }
    }
    'SENT|' + $n + '|' + (Sha $p)
  }
  'DONE'
  return
}
throw ('unknown op ' + $op)
'@

function New-FeedStoreScript([string]$root, [string]$prefix, [string]$op, [string[]]$names, [hashtable]$expect, [hashtable]$sizes) {
    function Q([string]$s) { return "'" + $s.Replace("'", "''") + "'" }
    $lines = @()
    $lines += ('$root = ' + (Q $root))
    $lines += ('$prefix = ' + (Q $prefix))
    $lines += ('$op = ' + (Q $op))
    $lines += ('$stamp = ' + (Q ((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))))
    $lines += ('$names = @(' + ((@($names) | ForEach-Object { Q $_ }) -join ', ') + ')')
    $e = @(); if ($expect) { foreach ($k in $expect.Keys) { $e += ((Q $k) + ' = ' + (Q ([string]$expect[$k]))) } }
    $lines += ('$expect = @{ ' + ($e -join '; ') + ' }')
    $s = @(); if ($sizes) { foreach ($k in $sizes.Keys) { $s += ((Q $k) + ' = ' + [int64]$sizes[$k]) } }
    $lines += ('$sizes = @{ ' + ($s -join '; ') + ' }')
    return (($lines -join "`r`n") + "`r`n" + $script:FeedStoreBody)
}

# Runs the one script, up there or on -SiteDir, and hands back its lines.
# Up there it goes through Send-Script.ps1 (Invoke-ThornswoodRemote, issue
# #1167, the same way as #1070): under the limit on the command line, over
# it as a file of its own name, removed whether the run worked or not, and
# the far side's exit code comes back. -SiteDir needs nothing of the VPS.
function Invoke-FeedStoreOp([string]$Channel, [string]$op, [string[]]$names, [hashtable]$expect, [hashtable]$sizes, [string]$SiteDir, [hashtable]$To) {
    $prefix = Get-FeedStorePrefix $Channel
    $sd = Get-FeedStoreSiteDir $SiteDir
    if ($sd) {
        $text = New-FeedStoreScript $sd $prefix $op $names $expect $sizes
        return @(& ([scriptblock]::Create($text)) | ForEach-Object { [string]$_ })
    }
    $v = Get-FeedStoreVps $To
    . (Join-Path $PSScriptRoot '..\vps\Vps.ps1')
    . (Join-Path $PSScriptRoot '..\vps\Send-Script.ps1')
    $text = New-FeedStoreScript ($v.Root.Replace('/', '\')) $prefix $op $names $expect $sizes
    $ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
    return @(Invoke-ThornswoodRemote -Target ($v.User + '@' + $v.Vps) -SshArgs $ssh -Script $text | Where-Object { $_ -is [string] })
}

function Copy-FeedStoreFile([string]$Channel, [string]$from, [string]$dest, [switch]$Up, [string]$SiteDir, [hashtable]$To) {
    $prefix = Get-FeedStorePrefix $Channel
    $sd = Get-FeedStoreSiteDir $SiteDir
    if ($sd) {
        $there = Join-Path (Join-Path $sd $prefix) $(if ($Up) { $dest } else { $from })
        if ($Up) { Copy-Item -LiteralPath $from -Destination $there -Force }
        else { Copy-Item -LiteralPath $there -Destination $dest -Force }
        return
    }
    $v = Get-FeedStoreVps $To
    . (Join-Path $PSScriptRoot '..\vps\Vps.ps1')
    $ssh = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes')
    $remote = $v.User + '@' + $v.Vps + ':' + $v.Root.TrimEnd('/') + '/' + $prefix + '/'
    if ($Up) { Invoke-ThornswoodNative { & scp @ssh $from ($remote + $dest) } 2>&1 | Out-Null }
    else { Invoke-ThornswoodNative { & scp @ssh ($remote + $from) $dest } 2>&1 | Out-Null }
    $rc = $LASTEXITCODE
    if ($rc -ne 0) { throw ("scp could not " + $(if ($Up) { "send $from" } else { "fetch $from" }) + " (exit $rc). Check the ssh key with scripts\vps\Setup-SshKey.ps1 -Test.") }
}

# What is up there now: a hashtable of name to sha256, '' for a file that is
# not there. Throws when the VPS did not answer, so a caller can never mistake
# no answer for no file.
# releases.json (#1050) is one of the store's own files, so every script that
# edits the feed receives it and every send checks it did not move meanwhile,
# the same as published.json.
function Get-FeedStoreThere([string]$Channel, [string[]]$Files = @('version.json', 'published.json', 'releases.json'), [string]$SiteDir, [hashtable]$To) {
    $lines = @(Invoke-FeedStoreOp $Channel 'look' $Files @{} @{} $SiteDir $To)
    if ($lines -notcontains 'DONE') {
        throw ("The VPS did not say what the " + (Get-FeedStorePrefix $Channel) + " store holds: " + (($lines | Select-Object -Last 3) -join ' ').Trim() +
               ". Check the ssh key with scripts\vps\Setup-SshKey.ps1 -Test.")
    }
    $o = @{}
    foreach ($l in $lines) {
        $p = $l.Split('|')
        if ($p[0] -eq 'HAVE' -and $p.Count -ge 4) { $o[$p[1]] = $p[2] }
        elseif ($p[0] -eq 'NONE' -and $p.Count -ge 2) { $o[$p[1]] = '' }
    }
    return $o
}

function Read-FeedStoreRead([string]$Dir) {
    $f = Join-Path $Dir 'read.json'
    $o = @{}
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try {
        $j = ([IO.File]::ReadAllText($f) -replace '^\uFEFF', '') | ConvertFrom-Json
        if ($j.PSObject.Properties['there'] -and $null -ne $j.there) {
            foreach ($p in $j.there.PSObject.Properties) { $o[$p.Name] = [string]$p.Value }
        }
    } catch { return $null }
    return $o
}

function Write-FeedStoreRead([string]$Dir, [string]$Channel, [hashtable]$there) {
    $t = [ordered]@{}
    foreach ($k in @($there.Keys | Sort-Object)) { $t[$k] = [string]$there[$k] }
    $o = [ordered]@{ channel = $Channel; at = (Get-Date).ToUniversalTime().ToString('s') + 'Z'; there = $t }
    [IO.File]::WriteAllText((Join-Path $Dir 'read.json'), ($o | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
}

# Every script that writes a channel's version.json writes it through here, so
# there is one shape for the file every launcher reads on every check (#1050).
#
# Compact: no indentation and no line breaks. ConvertTo-Json without -Compress
# indents each level, which was about 960 of main's 7,789 bytes on 12 Oct and
# meant nothing to the launcher, the site or any script, all of which parse
# it. -Depth 8 is the deepest any writer used, so no nested list is ever cut
# to its type name.
#
# No byte order mark: the launcher's reader stops on one and reports an
# unexpected character, which takes out the update check for everybody at
# once, including their route to a fix, and node refuses it too.
#
# tests\test-1050-feed-compact.ps1 holds every writer to this and parses what
# it writes with the launcher's own VersionDoc.Parse.
function ConvertTo-FeedJson($Doc) {
    return ($Doc | ConvertTo-Json -Depth 8 -Compress)
}

function Write-FeedVersionFile([string]$Path, $Doc) {
    if (-not $Path) { throw 'Write-FeedVersionFile needs the path of version.json.' }
    if ($null -eq $Doc) { throw "Write-FeedVersionFile was given no feed for $Path; nothing was written." }
    [IO.File]::WriteAllText($Path, (ConvertTo-FeedJson $Doc), (New-Object Text.UTF8Encoding($false)))
}

# Fetches the files into the working folder and writes down what they were.
# A file that is not up there is taken out of the folder too (a copy stays in
# backup\), so a baseline is never read from a stale local copy. Each file is
# checked against the sha256 the VPS gave for it, so a feed replaced halfway
# through the fetch is caught rather than half read. Returns the hashtable of
# what was read.
function Receive-FeedStore([string]$Channel, [string]$Dir, [string[]]$Files = @('version.json', 'published.json', 'releases.json'), [string]$SiteDir, [hashtable]$To) {
    if (-not $Dir) { $Dir = Get-FeedStoreDir $Channel }
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $there = Get-FeedStoreThere $Channel $Files $SiteDir $To
    $read = Read-FeedStoreRead $Dir
    if ($null -eq $read) { $read = @{} }
    $backup = Join-Path $Dir 'backup'
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    foreach ($n in $Files) {
        $local = Join-Path $Dir $n
        if (-not $there[$n]) {
            if (Test-Path -LiteralPath $local) {
                New-Item -ItemType Directory -Force -Path $backup | Out-Null
                Copy-Item -LiteralPath $local -Destination (Join-Path $backup ($stamp + '-gone-' + $n)) -Force
                Remove-Item -LiteralPath $local -Force
            }
            $read[$n] = ''
            continue
        }
        $down = $local + '.down'
        Copy-FeedStoreFile $Channel $n $down -SiteDir $SiteDir -To $To
        $got = Get-FeedStoreSha $down
        if ($got -ne $there[$n]) {
            Remove-Item -LiteralPath $down -Force -ErrorAction SilentlyContinue
            throw ("$n changed on the VPS while it was being read. Nothing was changed here; run it again.")
        }
        Move-Item -LiteralPath $down -Destination $local -Force
        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        Copy-Item -LiteralPath $local -Destination (Join-Path $backup ($stamp + '-' + $n)) -Force
        $read[$n] = $got
        # The last twenty of each, newest by name, which is the stamp.
        $old = @(Get-ChildItem -LiteralPath $backup -File -Filter ('*-' + $n) | Sort-Object Name -Descending | Select-Object -Skip 20)
        foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    }
    Write-FeedStoreRead $Dir $Channel $read
    return $read
}

# Sends the named files back, each only when it differs from what was read.
# Every file this folder has read is checked, not only the ones sent: a feed
# edit must not land on top of a baseline another Ship has just moved, and a
# baseline must not land beside a feed somebody else just wrote. -Expect
# replaces read.json as the answer to "what should be up there now"; Remirror
# passes what it saw itself when handed a folder that was never received.
# Returns @{ Sent = names; Same = names }. Throws, with nothing replaced, when
# anything moved up there or a file did not arrive whole.
function Send-FeedStore([string]$Channel, [string]$Dir, [string[]]$Files, [string]$SiteDir, [hashtable]$To, [hashtable]$Expect) {
    if (-not $Dir) { $Dir = Get-FeedStoreDir $Channel }
    $read = if ($null -ne $Expect) { $Expect } else { Read-FeedStoreRead $Dir }
    if ($null -eq $read) {
        throw ("$Dir was never received from the VPS, so there is nothing to say what this edit was made on top of. " +
               'Nothing was sent. Run the script again; it receives the feed first.')
    }
    foreach ($n in $Files) {
        if (-not (Test-Path -LiteralPath (Join-Path $Dir $n) -PathType Leaf)) { throw "No $n in $Dir to send. Nothing was sent." }
        if (-not $read.ContainsKey($n)) { throw "$n in $Dir was never received from the VPS, so there is nothing to check it against. Nothing was sent." }
    }
    $check = @($read.Keys | Sort-Object)
    $sizes = @{}
    foreach ($n in $Files) {
        $local = Join-Path $Dir $n
        if ((Get-FeedStoreSha $local) -eq [string]$read[$n]) { continue }
        Copy-FeedStoreFile $Channel $local ($n + '.part') -Up -SiteDir $SiteDir -To $To
        $sizes[$n] = (Get-Item -LiteralPath $local).Length
    }
    $lines = @(Invoke-FeedStoreOp $Channel 'swap' $check $read $sizes $SiteDir $To)
    $moved = @($lines | Where-Object { $_ -like 'MOVED|*' })
    if ($moved.Count) {
        throw ("The " + (Get-FeedStorePrefix $Channel) + " store changed on the VPS after this machine read it (" + $moved[0].Substring(6) +
               "): another Ship or feed edit went out meanwhile. Nothing was replaced. Run it again, so it starts from what is up there now.")
    }
    $short = @($lines | Where-Object { $_ -like 'SHORT|*' })
    if ($short.Count) { throw ("A file did not arrive whole (" + $short[0].Substring(6) + "). Nothing was replaced. Run it again.") }
    if ($lines -notcontains 'DONE') { throw ("The VPS did not confirm the send: " + (($lines | Select-Object -Last 3) -join ' ').Trim() + ". Nothing is known to have been replaced; run it again.") }
    $sent = @(); $same = @()
    foreach ($l in $lines) {
        $p = $l.Split('|')
        if ($p[0] -eq 'SENT') {
            if ($p[2] -ne (Get-FeedStoreSha (Join-Path $Dir $p[1]))) { throw ("$($p[1]) on the VPS does not hash to what was sent. Send it again.") }
            $read[$p[1]] = $p[2]; $sent += $p[1]
        } elseif ($p[0] -eq 'SAME') { $same += $p[1] }
    }
    Write-FeedStoreRead $Dir $Channel $read
    return @{ Sent = $sent; Same = @($same | Where-Object { $Files -contains $_ }) }
}

# Every launcher version this channel has ever published, oldest first. Ship
# climbs the dev number past all of them (Ship.ps1, the version block).
function Get-FeedStoreLaunchers([string]$Channel, [string]$SiteDir, [hashtable]$To) {
    $lines = @(Invoke-FeedStoreOp $Channel 'launchers' @() @{} @{} $SiteDir $To)
    if ($lines -notcontains 'DONE') { throw ("The VPS did not list the launchers " + (Get-FeedStorePrefix $Channel) + " has published.") }
    return @($lines | Where-Object { $_ -like 'L|*' } | ForEach-Object { $_.Substring(2) })
}

# Every release this channel's feed has named, oldest first, from releases.txt
# (#444): Id, Channel, LauncherVersion, Packs, Baseline, Commit, Tag.
function Get-FeedStoreReleases([string]$Channel, [string]$SiteDir, [hashtable]$To) {
    $lines = @(Invoke-FeedStoreOp $Channel 'releases' @() @{} @{} $SiteDir $To)
    if ($lines -notcontains 'DONE') { throw ("The VPS did not list the releases " + (Get-FeedStorePrefix $Channel) + " has named.") }
    return @($lines | Where-Object { $_ -like 'R|*' } | ForEach-Object {
        $f = @($_.Substring(2).Split("`t")) + @('', '', '', '', '', '', '')
        [pscustomobject]@{ Id = $f[0]; Channel = $f[1]; LauncherVersion = $f[2]; Packs = @($f[3].Split(',') | Where-Object { $_ })
                           Baseline = $f[4]; Commit = $f[5]; Tag = $f[6] }
    })
}

# Deletes /feed[-dev]/assets/<sha256> for each of $Shas (#1152). Nothing else
# here ever deletes an asset: an asset stays while any feed may name it. This is
# for Scrub-Feed.ps1, once it has replaced what must never have been published
# and worked out that no feed, baseline or record names these any more. $Expect
# is the sha256 of both channels' version.json as the caller read them
# (@{ main = <sha>; dev = <sha> }); if either has moved since, nothing is deleted
# and this throws, and a name either feed or either baseline still spells out is
# kept, as is anything that is not 64 hex digits. Returns @{ Gone; None; Named; Bad }.
function Remove-FeedStoreAssets([string]$Channel, [string[]]$Shas, [hashtable]$Expect, [string]$SiteDir, [hashtable]$To) {
    if (-not $Expect -or -not $Expect.ContainsKey('main') -or -not $Expect.ContainsKey('dev')) {
        throw 'Remove-FeedStoreAssets needs the sha256 of both feeds as they were read. Nothing was deleted.'
    }
    $e = @{ 'feed\version.json' = [string]$Expect['main']; 'feed-dev\version.json' = [string]$Expect['dev'] }
    $lines = @(Invoke-FeedStoreOp $Channel 'forget' @($Shas) $e @{} $SiteDir $To)
    $moved = @($lines | Where-Object { $_ -like 'MOVED|*' })
    if ($moved.Count) {
        throw ("A feed changed on the VPS after it was read (" + $moved[0].Substring(6) + "). Nothing was deleted. Run it again.")
    }
    if ($lines -notcontains 'DONE') { throw ("The VPS did not confirm what it deleted: " + (($lines | Select-Object -Last 3) -join ' ').Trim()) }
    $o = @{ Gone = @(); None = @(); Named = @(); Bad = @() }
    foreach ($l in $lines) {
        $p = $l.Split('|')
        if ($p[0] -eq 'GONE') { $o.Gone += $p[1] }
        elseif ($p[0] -eq 'NONE') { $o.None += $p[1] }
        elseif ($p[0] -eq 'NAMED') { $o.Named += $p[1] }
        elseif ($p[0] -eq 'BAD') { $o.Bad += $p[1] }
    }
    return $o
}

# The feed as a launcher reads it: https://thornswood.net/feed[-dev]/version.json,
# public, no ssh. With -SiteDir (or the test variable) the file in that folder.
# $null when there is none. Throws when the site does not answer.
function Read-SiteFeed([string]$Channel, [string]$SiteDir, [string]$SiteUrl = 'https://thornswood.net') {
    $prefix = Get-FeedStorePrefix $Channel
    $sd = Get-FeedStoreSiteDir $SiteDir
    if ($sd) {
        $f = Join-Path (Join-Path $sd $prefix) 'version.json'
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        return (ConvertFrom-ThornswoodJson ([IO.File]::ReadAllText($f)) $f)
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $wc = New-Object Net.WebClient
    $wc.Headers['User-Agent'] = 'Thornswood-Publish'
    $wc.Headers['Cache-Control'] = 'no-cache'
    try { $bytes = $wc.DownloadData($SiteUrl.TrimEnd('/') + '/' + $prefix + '/version.json') }
    finally { $wc.Dispose() }
    return (([Text.Encoding]::UTF8.GetString($bytes) -replace '^\uFEFF', '') | ConvertFrom-Json)
}
