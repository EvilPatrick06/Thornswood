<#
  test-1050-feed-split.ps1

      pwsh -NoProfile -File .\tests\test-1050-feed-split.ps1
      pwsh -NoProfile -File .\tests\test-1050-feed-split.ps1 -OldSrc <launcher\app of an older launcher>, <another>

  The launcher half of the split feed (#1050, Patrick's answer of 19 Oct).
  Once a channel's minLauncher reads it, the site answers version.json as the
  update fields alone, names the rest of the feed as one more asset,
  "settings": { sha256 }, and names every asset by its sha256 without its
  address (site\server.js feedView; tests\test-1050-feed-split.js holds the
  site to that). This proves, with the feed the site's own code makes from a
  whole feed of the 19 Oct shape:

    - the launcher (launcher\app\FeedSettings.cs, Updater.ReadFeed) reads the
      split feed whole: the settings from Profile\feed-settings.json, or
      downloaded from the feed's own assets folder, checked against their
      sha256 and kept; every asset's address is that folder plus its sha256
    - settings that cannot be had, or do not hash to their name, are a feed
      it cannot read, and nothing is kept
    - a feed that is not split reads exactly as before
    - Join-FeedSettings (scripts\release\Feed-Json.ps1), which every script
      that reads the site's feed goes through, gives back the whole feed
    - no launcher source at or past the split's first number lacks the reader
    - with -OldSrc, each older launcher reads the split version.json as a feed
      that is behind: no record to sync, no pack, and the launcher update it
      needs, which is all a launcher below minLauncher has to do

  HOW. Compiles launcher\app\*.cs with the compiler and references the build
  uses (tests\Launcher-Csc.ps1) and calls Updater.ReadFeed by reflection,
  with a server of its own on 127.0.0.1. Runs under Windows PowerShell 5.1
  and restarts itself there from pwsh, because the launcher runs on the .NET
  Framework. Nothing under C:\Thornswood is read or written.
#>
[CmdletBinding()]
param([string]$Src, [string[]]$OldSrc = @())

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')
$Here = Split-Path -Parent $PSScriptRoot
if (-not $Src) { $Src = Join-Path $Here 'launcher\app' }

if ($PSVersionTable.PSEdition -eq 'Core') {
    $winps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $winps)) {
        Write-Host 'FAIL  Windows PowerShell is here to run this on the .NET Framework the launcher runs on'
        Write-Host ''
        Write-Host '0 passed, 1 failed'
        exit 1
    }
    $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Src', $Src)
    if ($OldSrc.Count) { $relaunch += '-OldSrc'; $relaunch += ($OldSrc -join ',') }
    & $winps @relaunch
    exit $LASTEXITCODE
}
if ($OldSrc.Count -eq 1 -and $OldSrc[0] -match ',') { $OldSrc = @($OldSrc[0] -split ',') }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tsfeedsplit-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Force -Path $tmp

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public class TsSplitServer
{
    TcpListener listener;
    public int Port;
    public volatile byte[] Body = new byte[0];
    public readonly List<string> Seen = new List<string>();

    public void Start()
    {
        listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var t = new Thread(Loop);
        t.IsBackground = true;
        t.Start();
    }
    public void Stop() { try { listener.Stop(); } catch (Exception) { } }
    public int Count() { lock (Seen) { return Seen.Count; } }
    void Loop()
    {
        while (true)
        {
            TcpClient c;
            try { c = listener.AcceptTcpClient(); } catch (Exception) { return; }
            try { Serve(c); } catch (Exception) { }
            finally { c.Close(); }
        }
    }
    void Serve(TcpClient c)
    {
        var s = c.GetStream();
        var sb = new StringBuilder();
        int b;
        while ((b = s.ReadByte()) >= 0)
        {
            sb.Append((char)b);
            if (sb.Length >= 4 && sb.ToString(sb.Length - 4, 4) == "\r\n\r\n") break;
        }
        string path = sb.ToString().Split(' ')[1];
        byte[] body = Body;
        byte[] h = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\n\r\n");
        s.Write(h, 0, h.Length);
        if (body.Length > 0) s.Write(body, 0, body.Length);
        s.Flush();
        lock (Seen) Seen.Add(path);
    }
}
'@

function ShaOf([byte[]]$b) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($h.ComputeHash($b) | ForEach-Object { $_.ToString('x2') })) } finally { $h.Dispose() }
}
function Hex([string]$c) { return ($c * 64) }

# A whole feed of the shape main's had on 19 Oct, every field it carries.
$A = 'https://thornswood.net/feed/assets/'
$whole = [ordered]@{
    launcherVersion = '1.2.6'; launcherUrl = $A + (Hex '1'); launcherSha256 = (Hex '1')
    serverAddress = '203.0.113.7'; serverPort = '7777'; message = ''; packs = @(); news = @(); voicePort = '7778'
    collectionUrl = 'https://www.nexusmods.com/games/skyrimspecialedition/collections/x'; maxOnline = 30; mainVersion = ''
    voiceUrl = ''; discordAppId = '123456789012345678'; siteUrl = 'https://thornswood.net'; presenceImage = 'https://thornswood.net/i.png'
    collectionRevision = 4
    clientRuntime = [ordered]@{ url = $A + (Hex '2'); sha256 = (Hex '2'); bytes = 6607137; forkCommit = '0714e444'; notice = 1 }
    updateFeedUrl = 'https://thornswood.net/feed/version.json'; expectedExeBytes = '37157144'; newerExeBytes = '37691928'
    depots = @([ordered]@{ id = '489831'; manifest = '8442952117333549665' }, [ordered]@{ id = '489832'; manifest = '8042843504692938467' })
    baseline = [ordered]@{ id = '20261017-205912'; sha256 = (Hex '3'); url = $A + (Hex '3'); entries = 743; notes = 'The holds, the boards' }
    launcherInputs = (Hex '4'); minLauncher = '1.2.6'
    release = [ordered]@{ id = '20261017-205912'; channel = 'main'; launcherVersion = '1.2.6'; packs = @(); baseline = '20261017-205912' }
    signedManifest = [ordered]@{ url = $A + (Hex '5'); sha256 = (Hex '5'); catalogUrl = $A + (Hex '6'); catalogSha256 = (Hex '6') }
    newsFile = [ordered]@{ url = $A + (Hex '7'); sha256 = (Hex '7'); count = 40 }
}
$wholeJson = ([pscustomobject]$whole | ConvertTo-Json -Depth 8 -Compress)
$wholePath = Join-Path $tmp 'whole.json'
[IO.File]::WriteAllText($wholePath, $wholeJson, (New-Object Text.UTF8Encoding($false)))

function Run {
    # ---- what the site answers for it, from the site's own code -------------
    $out = Join-Path $tmp 'served'
    $node = Get-Command node -ErrorAction SilentlyContinue
    Yes 'node is here, to make the feed the way the site does' ($null -ne $node)
    if (-not $node) { return }
    & $node.Source (Join-Path $PSScriptRoot 'test-1050-feed-split.js') --emit $wholePath $out
    $topBytes = [IO.File]::ReadAllBytes((Join-Path $out 'version.json'))
    $setPath = Join-Path $out 'settings.json'
    Yes 'the site''s feedView splits a feed whose minLauncher is 1.2.6' (Test-Path -LiteralPath $setPath)
    if (-not (Test-Path -LiteralPath $setPath)) { return }
    $setBytes = [IO.File]::ReadAllBytes($setPath)
    $setSha = ShaOf $setBytes
    $top = [Text.Encoding]::UTF8.GetString($topBytes) | ConvertFrom-Json
    Yes ('version.json names the settings by their sha256 ({0} bytes; the whole feed is {1})' -f $topBytes.Length, $wholeJson.Length) ([string]$top.settings.sha256 -eq $setSha)

    # ---- the launcher -------------------------------------------------------
    Yes 'the compiler the build runs is on this machine' (Test-Path -LiteralPath $LauncherCsc)
    $refs = @(); $missing = @()
    foreach ($n in @($LauncherNeeded)) { $p = Find-LauncherRef $n; if ($p) { $refs += $p } else { $missing += $n } }
    foreach ($n in @($LauncherWv2Managed)) {
        $p = Join-Path $Here ('launcher\lib\webview2\' + $n)
        if (Test-Path -LiteralPath $p) { $refs += $p } else { $missing += $n }
    }
    Yes ('every reference is on this machine' + $(if ($missing.Count) { ', missing ' + ($missing -join ', ') } else { '' })) ($missing.Count -eq 0)
    if ($missing.Count -or -not (Test-Path -LiteralPath $LauncherCsc)) { return }

    function Build([string]$from, [string]$name) {
        $dll = Join-Path $tmp ($name + '.dll')
        $cscArgs = @('/noconfig', '/nologo', '/target:library', '/platform:anycpu', "/langversion:$LauncherLangVersion", "/out:$dll")
        foreach ($r in $refs) { $cscArgs += "/reference:$r" }
        foreach ($f in @(Get-ChildItem (Join-Path $from '*.cs') -File)) { $cscArgs += $f.FullName }
        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $said = & $LauncherCsc @cscArgs 2>&1
        $rc = $LASTEXITCODE
        $ErrorActionPreference = $old
        if ($rc -ne 0 -or -not (Test-Path -LiteralPath $dll)) {
            foreach ($l in @($said | Where-Object { "$_" -match 'error' } | Select-Object -First 20)) { Write-Host "      $l" }
            return $null
        }
        return [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
    }
    $asm = Build $Src 'Thornswood'
    Yes 'the launcher compiles with the compiler the build runs' ($null -ne $asm)
    if ($null -eq $asm) { return }
    $U = $asm.GetType('Thornswood.Updater'); $P = $asm.GetType('Thornswood.Paths'); $C = $asm.GetType('Thornswood.Config')
    $flags = [Reflection.BindingFlags]'Static, Public, NonPublic'
    $mRead = $U.GetMethod('ReadFeed', $flags)
    $fBytes = $U.GetField('settingsBytes', $flags); $fHeld = $U.GetField('settingsHeld', $flags)
    Yes 'Updater.ReadFeed and Updater.AssetsOf are in the build' ($null -ne $mRead -and $null -ne $U.GetMethod('AssetsOf', $flags))
    if ($null -eq $mRead) { return }
    $profile = Join-Path $tmp 'Profile'
    $null = New-Item -ItemType Directory -Force -Path $profile
    $P.GetField('ProfileDir').SetValue($null, $profile)
    $cfg = [Activator]::CreateInstance($C)
    $cache = Join-Path $profile 'feed-settings.json'
    function Restart { $fBytes.SetValue($null, $null); $fHeld.SetValue($null, '') }
    function Read-Feed([byte[]]$body, [string]$url, $with) { return $mRead.Invoke($null, @($body, $url, $with)) }
    function Threw([scriptblock]$b) { try { & $b; return '' } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; return $e.Message } }

    Yes 'AssetsOf is the folder beside the feed plus assets/' (
        $U.GetMethod('AssetsOf', $flags).Invoke($null, @('https://thornswood.net/feed-dev/version.json')) -eq 'https://thornswood.net/feed-dev/assets/')

    # 1. from Profile, as after a restart
    [IO.File]::WriteAllBytes($cache, $setBytes)
    Restart
    $v = Read-Feed $topBytes 'https://thornswood.net/feed/version.json' $null
    Yes 'the split feed reads whole, with its settings from Profile' ($null -ne $v -and $v.serverAddress -eq '203.0.113.7' -and $v.serverPort -eq '7777' -and
        $v.maxOnline -eq 30 -and $v.collectionRevision -eq 4 -and @($v.depots).Count -eq 2 -and $v.discordAppId -eq '123456789012345678' -and $v.voiceUrl -eq '')
    Yes '  with the update fields from version.json' ($v.launcherVersion -eq '1.2.6' -and $v.minLauncher -eq '1.2.6' -and $v.launcherUrl -eq ($A + (Hex '1')) -and
        $null -ne $v.packs -and @($v.packs).Count -eq 0 -and $null -ne $v.news)
    Yes '  the record, the news file and the client runtime at the assets folder plus their sha256' (
        $v.record.url -eq ($A + (Hex '3')) -and $v.record.notes -eq 'The holds, the boards' -and $v.newsRef.url -eq ($A + (Hex '7')) -and $v.clientRuntime.url -eq ($A + (Hex '2')))
    Yes '  and the signed manifest and its catalog the same way' ($v.manifestRef.url -eq ($A + (Hex '5')) -and $v.manifestRef.catalogUrl -eq ($A + (Hex '6')))

    # 2. not on disk and nothing to fetch with: the copy kept on disk is not believed
    Remove-Item -LiteralPath $cache
    Restart
    $why = Threw { Read-Feed $topBytes 'https://thornswood.net/feed/version.json' $null }
    Yes ('without the settings on this machine the kept copy does not read: ' + $why) ($why -match 'not on this machine')

    # 3. downloaded from the feed's own folder, checked and kept
    $srv = New-Object TsSplitServer
    $srv.Start()
    try {
        $feedUrl = 'http://127.0.0.1:' + $srv.Port + '/feed/version.json'
        $srv.Body = $setBytes
        $v = Read-Feed $topBytes $feedUrl $cfg
        Yes 'the settings are downloaded from the feed''s assets folder by their sha256' ($srv.Count() -eq 1 -and $srv.Seen[0] -eq ('/feed/assets/' + $setSha))
        Yes '  read whole, every address beside the feed' ($v.serverAddress -eq '203.0.113.7' -and $v.record.url -eq ('http://127.0.0.1:' + $srv.Port + '/feed/assets/' + (Hex '3')))
        Yes '  and kept in Profile\feed-settings.json' ((Test-Path -LiteralPath $cache) -and (ShaOf ([IO.File]::ReadAllBytes($cache))) -eq $setSha)
        [void](Read-Feed $topBytes $feedUrl $cfg)
        Yes '  the next check asks for nothing more' ($srv.Count() -eq 1)

        Remove-Item -LiteralPath $cache
        Restart
        $srv.Body = [Text.Encoding]::UTF8.GetBytes('{"serverAddress":"6.6.6.6"}')
        $why = Threw { Read-Feed $topBytes $feedUrl $cfg }
        Yes ('settings that do not hash to their name are refused: ' + $why) ($why -match 'did not match its checksum')
        Yes '  and nothing is kept' (-not (Test-Path -LiteralPath $cache))
    }
    finally { $srv.Stop() }

    # 4. a feed that is not split, and one whose settings say nothing usable
    Restart
    $v = Read-Feed ([Text.Encoding]::UTF8.GetBytes($wholeJson)) 'https://thornswood.net/feed/version.json' $cfg
    Yes 'a feed that is not split reads as before, with the addresses it spells out' ($v.serverAddress -eq '203.0.113.7' -and $v.record.url -eq ($A + (Hex '3')) -and $null -eq $v.settingsRef)
    $why = Threw { Read-Feed ([Text.Encoding]::UTF8.GetBytes('{"launcherVersion":"1.2.6","packs":[],"settings":{"sha256":"x"}}')) 'https://thornswood.net/feed/version.json' $cfg }
    Yes ('settings named without a sha256 are a feed it cannot read: ' + $why) ($why -match 'without a checksum')

    # ---- Join-FeedSettings, for every script that reads the site's feed -----
    . (Join-Path $Here 'scripts\release\Feed-Json.ps1')
    $doc = [Text.Encoding]::UTF8.GetString($topBytes) | ConvertFrom-Json
    $joined = Join-FeedSettings $doc 'https://thornswood.net/feed/version.json' { param($u) if ($u -ne ($A + $setSha)) { throw "asked $u" }; return , $setBytes }
    function Sorted($x) {
        if ($x -is [Array]) { return , @($x | ForEach-Object { Sorted $_ }) }
        if ($x -is [pscustomobject]) { $o = [ordered]@{}; foreach ($n in @($x.PSObject.Properties.Name | Sort-Object)) { $o[$n] = Sorted $x.$n }; return $o }
        return $x
    }
    $joinedJson = (Sorted $joined) | ConvertTo-Json -Depth 10 -Compress
    $storeJson = (Sorted ($wholeJson | ConvertFrom-Json)) | ConvertTo-Json -Depth 10 -Compress
    Yes 'Join-FeedSettings gives back the whole feed the store holds' ($joinedJson -eq $storeJson)
    $why = Threw { Join-FeedSettings $doc 'https://thornswood.net/feed/version.json' { param($u) return , ([Text.Encoding]::UTF8.GetBytes('{}')) } }
    Yes ('  and refuses settings that do not hash to their name: ' + $why) ($why -match 'did not hash')
    $plain = $wholeJson | ConvertFrom-Json
    Yes '  a feed with no settings comes back as it is' ([object]::ReferenceEquals((Join-FeedSettings $plain 'https://thornswood.net/feed/version.json'), $plain))

    # ---- no launcher at or past the split without the reader ----------------
    # Its own name: PowerShell names are not case sensitive, so a $src here
    # would replace the -Src folder with Updater.cs's text, and the
    # FeedSettings.cs check below would throw once the launcher reached the split.
    $updaterText = [IO.File]::ReadAllText((Join-Path $Src 'Updater.cs'))
    $ver = [regex]::Match($updaterText, 'public const string Version = "([^"]+)"').Groups[1].Value
    $site = [IO.File]::ReadAllText((Join-Path $Here 'site\server.js'))
    $gate = [regex]::Match($site, "const FEED_SPLIT_LAUNCHER = '([^']+)'").Groups[1].Value
    . (Join-Path $Here 'scripts\release\Release-Baseline.ps1')
    $cmp = Compare-FeedVersion $ver $gate
    Yes ("this launcher source ({0}) is below the split's {1}, or reads the settings file" -f $ver, $gate) (
        $gate -and $null -ne $cmp -and ($cmp -lt 0 -or (Test-Path -LiteralPath (Join-Path $Src 'FeedSettings.cs'))))

    # ---- older launchers: behind, and able to update themselves -------------
    foreach ($o in @($OldSrc | Where-Object { $_ })) {
        $oa = Build $o ('old-' + [Guid]::NewGuid().ToString('N'))
        $ov = [regex]::Match([IO.File]::ReadAllText((Join-Path $o 'Updater.cs')), 'public const string Version = "([^"]+)"').Groups[1].Value
        Yes "launcher $ov compiles" ($null -ne $oa)
        if ($null -eq $oa) { continue }
        $oDoc = $oa.GetType('Thornswood.VersionDoc'); $oUpd = $oa.GetType('Thornswood.Updater'); $oPaths = $oa.GetType('Thornswood.Paths')
        $oProfile = Join-Path $tmp ('p-' + $ov); $null = New-Item -ItemType Directory -Force -Path $oProfile
        $oPaths.GetField('ProfileDir').SetValue($null, $oProfile)
        foreach ($f in 'AppliedFile') { $fi = $oPaths.GetField($f); if ($fi) { $fi.SetValue($null, (Join-Path $oProfile 'applied.txt')) } }
        $d = $oDoc.GetMethod('Parse', $flags, $null, @([byte[]]), $null).Invoke($null, @(, $topBytes))
        $rec = $oDoc.GetField('record'); $recV = if ($rec) { $rec.GetValue($d) } else { $null }
        Yes "  $ov reads the split version.json: launcher 1.2.6 at its address, no record to sync, packs and news empty" (
            $null -ne $d -and $d.launcherVersion -eq '1.2.6' -and $d.launcherUrl -eq ($A + (Hex '1')) -and $null -eq $recV -and
            $null -ne $d.packs -and @($d.packs).Count -eq 0 -and $null -ne $d.news)
        $pend = $oUpd.GetMethod('Pending', $flags).Invoke($null, @($d))
        $newer = $oUpd.GetMethod('IsNewer', $flags).Invoke($null, @('1.2.6', $ov))
        Yes "  and is offered only the launcher update" (@($pend).Count -eq 0 -and $newer)
    }
    if (-not $OldSrc.Count) { Write-Host '      (no -OldSrc: older launchers not checked here)' }
}

try { Run }
catch { $script:fail++; Write-Host "FAIL  the harness itself threw: $($_.Exception.Message)" }
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host "$($script:pass) passed, $($script:fail) failed"
if ($script:fail) { exit 1 }
exit 0
