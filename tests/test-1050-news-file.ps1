<#
  test-1050-news-file.ps1

      pwsh -NoProfile -File .\tests\test-1050-news-file.ps1

  The launcher reads the news from a file of its own when the feed names one
  (#1050), so the publisher can take the news out of version.json once every
  launcher it lets in reads that file.

  WHY THIS EXISTS. Measured 12 Oct, the news was 31,282 of main's 95,085 bytes
  of version.json and 19,980 of dev's 111,305, read on every check, every
  thirty seconds while the game runs. Every launcher up to 1.2.3 reads the
  News tab only out of "news" in version.json, so the news can leave the feed
  only once the launcher the feed lets in (minLauncher) reads it from
  elsewhere. This is that reader, launcher\app\FeedNews.cs, and what it proves
  against a server of its own on 127.0.0.1:
    - VersionDoc.Parse reads "newsFile" apart from the rest of the feed, and a
      newsFile of any other shape costs only itself, never the feed
    - the file is downloaded, checked against its sha256, kept in
      Profile\news.json, then read from memory and, after a restart, from disk
      without asking again
    - bytes that do not hash to the name, or a url not stored under its own
      sha256, are refused and nothing is kept
    - the notes the feed carries come first and the file's follow, each note
      once
    - a news file that cannot be had leaves the feed's notes and the check
      goes on, with one line in launcher.log
    - the update check on the launcher's own thread fills the news before the
      window reads it (ShellUpdate.cs), and the address a real launcher asks is
      still fenced by CheckUrl

  HOW. Compiles launcher\app\*.cs into a library with the same compiler and
  the same references the build uses (tests\Launcher-Csc.ps1), as
  test-feed-conditional.ps1 does, and calls Updater.NewsFile by reflection;
  that is what FillNews does after CheckUrl, which only lets https to
  thornswood.net through. Paths points at a temp folder. Nothing under
  C:\Thornswood is read or written, and nothing leaves 127.0.0.1.

  Runs under Windows PowerShell 5.1 and restarts itself there from pwsh,
  because the launcher runs on the .NET Framework.
#>
[CmdletBinding()]
param([string]$Src)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Here = Split-Path -Parent $Here
if (-not $Src) { $Src = Join-Path $Here 'launcher\app' }

if ($PSVersionTable.PSEdition -eq 'Core') {
    $winps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $winps)) {
        Write-Host 'FAIL  Windows PowerShell is here to run this on the .NET Framework the launcher runs on'
        Write-Host ''
        Write-Host '0 passed, 1 failed'
        exit 1
    }
    & $winps -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Src $Src
    exit $LASTEXITCODE
}

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}

# ---- the compiler and the references the build uses (Launcher-Csc.ps1) ------

$needed = @($LauncherNeeded)
$wv2 = @($LauncherWv2Managed)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tsnewsfile-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Force -Path $tmp

# ---- a server of its own, on 127.0.0.1 ---------------------------------------
# Answers every request with Body, and writes down each path it was asked for.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public class TsNewsServer
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

    public void Stop()
    {
        try { listener.Stop(); } catch (Exception) { }
    }

    public int Count()
    {
        lock (Seen) { return Seen.Count; }
    }

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
        byte[] h = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\n\r\n");
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
function Utf8([string]$s) { return ,([byte[]][Text.Encoding]::UTF8.GetBytes($s)) }
# A note the way Publish-Update writes one.
function Note([string]$date, [string]$title, [string]$channel = '') {
    return ('{"date":"' + $date + '","title":"' + $title + '","body":"","details":["A line about it."],"channel":"' + $channel + '"}')
}

function Run {
    Yes 'the compiler the build runs is on this machine (the Roslyn csc beside MSBuild)' (Test-Path -LiteralPath $LauncherCsc)
    if (-not (Test-Path -LiteralPath $LauncherCsc) -or $needed.Count -eq 0) { Yes 'Thornswood.csproj names the references' $false; return }
    $refs = @(); $missing = @()
    foreach ($n in $needed) { $p = Find-LauncherRef $n; if ($p) { $refs += $p } else { $missing += $n } }
    foreach ($n in $wv2) {
        $p = Join-Path $Here ('launcher\lib\webview2\' + $n)
        if (Test-Path -LiteralPath $p) { $refs += $p } else { $missing += $n }
    }
    Yes ('every reference is on this machine' + $(if ($missing.Count) { ', missing ' + ($missing -join ', ') } else { '' })) ($missing.Count -eq 0)
    if ($missing.Count) { return }

    $cs = @(Get-ChildItem (Join-Path $Src '*.cs') -File)
    $dll = Join-Path $tmp 'Thornswood.dll'
    $cscArgs = @('/noconfig', '/nologo', '/target:library', '/platform:anycpu', "/langversion:$LauncherLangVersion", "/out:$dll")
    foreach ($r in $refs) { $cscArgs += "/reference:$r" }
    foreach ($f in $cs) { $cscArgs += $f.FullName }
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $said = & $LauncherCsc @cscArgs 2>&1
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $old
    $built = ($rc -eq 0) -and (Test-Path -LiteralPath $dll)
    Yes ('the launcher''s {0} source files compile with the compiler the build runs' -f $cs.Count) $built
    if (-not $built) {
        foreach ($l in @($said | Where-Object { "$_" -match 'error' } | Select-Object -First 20)) { Write-Host "      $l" }
        return
    }

    $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
    $U = $asm.GetType('Thornswood.Updater')
    $P = $asm.GetType('Thornswood.Paths')
    $C = $asm.GetType('Thornswood.Config')
    $V = $asm.GetType('Thornswood.VersionDoc')
    $NR = $asm.GetType('Thornswood.NewsRef')
    $NI = $asm.GetType('Thornswood.NewsItem')
    $flags = [Reflection.BindingFlags]'Static, Public, NonPublic'
    $mFile = $U.GetMethod('NewsFile', $flags)
    $mFill = $U.GetMethod('FillNews', $flags)
    $mMerge = $U.GetMethod('MergeNews', $flags)
    $mParseNews = $U.GetMethod('ParseNews', $flags)
    $mParse = $V.GetMethod('Parse', $flags)
    $fItems = $U.GetField('newsItems', $flags)
    $fHeld = $U.GetField('newsHeld', $flags)
    Yes 'Updater.NewsFile, FillNews, MergeNews, ParseNews and VersionDoc.newsRef are in the build' (
        $null -ne $mFile -and $null -ne $mFill -and $null -ne $mMerge -and $null -ne $mParseNews -and $null -ne $NR -and $null -ne $V.GetField('newsRef'))
    if ($null -eq $mFile -or $null -eq $NR) { return }

    $profile = Join-Path $tmp 'Profile'
    $null = New-Item -ItemType Directory -Force -Path $profile
    $P.GetField('ProfileDir').SetValue($null, $profile)
    $P.GetField('LogFile').SetValue($null, (Join-Path $profile 'launcher.log'))
    $cfg = [Activator]::CreateInstance($C)
    function Parse-Feed([string]$json) { return $mParse.Invoke($null, @(, (Utf8 $json))) }
    function Titles($items) { return (@($items | ForEach-Object { [string]$_.title }) -join ',') }
    function Restart { $fItems.SetValue($null, $null); $fHeld.SetValue($null, '') }

    # ---- 1. the feed names it, read apart from the rest -------------------------
    $fileJson = '[' + (Note '10-11-2026 10:13 PM' 'Keys, deeds and forges' 'dev') + ',' + (Note '10-11-2026 5:51 PM' 'Worn gear updates at once') + ',' + (Note '10-10-2026 9:00 AM' 'An older note') + ']'
    $fileBytes = Utf8 $fileJson
    $sha = ShaOf $fileBytes
    $feed = '{"launcherVersion":"1.2.4","packs":[],"news":[],"newsFile":{"url":"https://thornswood.net/feed-dev/assets/' + $sha + '","sha256":"' + $sha.ToUpperInvariant() + '","count":3}}'
    $v = Parse-Feed $feed
    Yes 'VersionDoc.Parse reads newsFile: its url, and its sha256 in lower case' ($null -ne $v.newsRef -and $v.newsRef.sha256 -eq $sha -and $v.newsRef.url -like "*/feed-dev/assets/$sha")
    foreach ($bad in @('"newsFile":"a string"', '"newsFile":{"url":"https://thornswood.net/feed/assets/x","sha256":"not a hash"}', '"newsFile":5', ('"newsFile":{"sha256":"' + $sha + '"}'))) {
        $vb = Parse-Feed ('{"launcherVersion":"1.2.4","packs":[],"news":[' + (Note '1-1-2026' 'Kept') + '],' + $bad + '}')
        Yes ("  a newsFile of another shape ({0}) costs only itself: no newsRef, and the feed and its news are read" -f $bad.Substring(11, [Math]::Min(20, $bad.Length - 11))) (
            $null -ne $vb -and $null -eq $vb.newsRef -and [string]$vb.launcherVersion -eq '1.2.4' -and (Titles $vb.news) -eq 'Kept')
    }
    $vn = Parse-Feed '{"launcherVersion":"1.2.3","packs":[],"news":[]}'
    Yes '  a feed that names none has no newsRef' ($null -eq $vn.newsRef)

    # ---- 2. the file, downloaded, checked, kept --------------------------------
    $srv = New-Object TsNewsServer
    $srv.Start()
    try {
        $srv.Body = $fileBytes
        $r = [Activator]::CreateInstance($NR)
        $r.sha256 = $sha
        $r.url = "http://127.0.0.1:$($srv.Port)/feed-dev/assets/$sha"
        $items = $mFile.Invoke($null, @($cfg, $r))
        Yes 'the file is downloaded and read: three notes, in the order the file has them' ((Titles $items) -eq 'Keys, deeds and forges,Worn gear updates at once,An older note' -and $srv.Count() -eq 1)
        Yes '  with the DEV mark it carries' ([string]@($items)[0].channel -eq 'dev' -and [bool]@($items)[0].IsDev)
        $kept = Join-Path $profile 'news.json'
        Yes '  and kept in Profile\news.json, the same bytes' ((Test-Path -LiteralPath $kept) -and (ShaOf ([IO.File]::ReadAllBytes($kept))) -eq $sha)
        $items = $mFile.Invoke($null, @($cfg, $r))
        Yes 'asked again for the same file, it comes from memory and nothing is fetched' ((Titles $items) -like 'Keys*' -and $srv.Count() -eq 1)
        Restart
        $items = $mFile.Invoke($null, @($cfg, $r))
        Yes 'after a restart it comes from Profile\news.json and nothing is fetched' ((Titles $items) -like 'Keys*' -and $srv.Count() -eq 1)

        # ---- 3. refusals ----------------------------------------------------------
        Restart
        Remove-Item -LiteralPath $kept -Force
        $srv.Body = Utf8 ($fileJson.Replace('An older note', 'Someone else''s note'))
        $threw = ''
        try { [void]$mFile.Invoke($null, @($cfg, $r)) } catch { $threw = $_.Exception.InnerException.Message }
        Yes ('bytes that do not hash to the name are refused: ' + $threw) ($threw -match 'did not match its checksum' -and -not (Test-Path -LiteralPath $kept) -and $null -eq $fItems.GetValue($null))
        $r2 = [Activator]::CreateInstance($NR)
        $r2.sha256 = $sha
        $r2.url = "http://127.0.0.1:$($srv.Port)/feed-dev/assets/news.json"
        $n0 = $srv.Count()
        $threw = ''
        try { [void]$mFile.Invoke($null, @($cfg, $r2)) } catch { $threw = $_.Exception.InnerException.Message }
        Yes ('a url not stored under its own sha256 is refused before anything is fetched: ' + $threw) ($threw -match 'not stored under its own checksum' -and $srv.Count() -eq $n0)
        $ok = $false
        $withMark = [byte[]](@(0xEF, 0xBB, 0xBF) + @($fileBytes))
        try { $ok = (Titles ($mParseNews.Invoke($null, @(, $withMark)))) -like 'Keys*' } catch { $ok = $false }
        Yes 'a news file with a byte order mark reads the same' $ok
    } finally { $srv.Stop() }

    # ---- 4. merged with the feed's own --------------------------------------------
    $feedItems = $mParseNews.Invoke($null, @(, (Utf8 ('[' + (Note '10-12-2026 1:00 AM' 'A note only the feed has') + ',' + (Note '10-11-2026 10:13 PM' 'Keys, deeds and forges' 'dev') + ']'))))
    $fileItems = $mParseNews.Invoke($null, @(, $fileBytes))
    $m = $mMerge.Invoke($null, @($feedItems, $fileItems))
    Yes 'the feed''s notes come first, then the file''s it does not carry, each once' ((Titles $m) -eq 'A note only the feed has,Keys, deeds and forges,Worn gear updates at once,An older note')
    $m = $mMerge.Invoke($null, @($null, $fileItems))
    Yes '  and a feed with no notes shows the file''s alone' ((Titles $m) -eq 'Keys, deeds and forges,Worn gear updates at once,An older note')

    # ---- 5. FillNews never fails the check ------------------------------------------
    Restart
    $vf = Parse-Feed ('{"launcherVersion":"1.2.4","packs":[],"news":[' + (Note '1-1-2026' 'Kept') + '],"newsFile":{"url":"http://thornswood.net/feed/assets/' + $sha + '","sha256":"' + $sha + '"}}')
    $threw = ''
    try { [void]$mFill.Invoke($null, @($cfg, $vf)) } catch { $threw = $_.Exception.Message }
    $log = if (Test-Path -LiteralPath (Join-Path $profile 'launcher.log')) { [IO.File]::ReadAllText((Join-Path $profile 'launcher.log')) } else { '' }
    Yes 'a news file a launcher may not fetch (not https) leaves the feed''s notes, throws nothing, and says why once in launcher.log' (
        $threw -eq '' -and (Titles $vf.news) -eq 'Kept' -and $log -match 'Swallowed in Updater\.FillNews')
    $vz = Parse-Feed '{"launcherVersion":"1.2.4","packs":[],"news":[]}'
    [void]$mFill.Invoke($null, @($cfg, $vz))
    Yes 'a feed that names no file is left as it is' (@($vz.news).Count -eq 0)

    # ---- 6. where it is called, and the fence ---------------------------------------
    $su = Get-Content -LiteralPath (Join-Path $Src 'ShellUpdate.cs') -Raw
    Yes 'the update check fills the news on its own thread, before the window reads the document' (
        # The signed manifest's line (#2163) is worked out between the two, on the same thread.
        $su -match '(?s)static void CheckUpdatesBackground\(bool loud\).*?VersionDoc v = Updater\.Check\(cfg\);.*?Updater\.FillNews\(cfg, v\);(\s*//[^\n]*)*\s*(string manifest = Updater\.ManifestLine\(cfg, v\);\s*)?win\.Dispatcher\.BeginInvoke\(new Action\(delegate\s*\{[^}]*?OnVersionDoc\(v, loud\);\s*\}\)\);')
    $fn = Get-Content -LiteralPath (Join-Path $Src 'FeedNews.cs') -Raw
    Yes 'FillNews runs CheckUrl on the file''s address before NewsFile fetches it' ($fn -match '(?s)public static void FillNews\(Config cfg, VersionDoc v\).*?CheckUrl\(v\.newsRef\.url\);.*?NewsFile\(cfg, v\.newsRef\)')
}

try {
    try { Run }
    catch { Yes ('the harness ran to the end, and stopped on: ' + $_.Exception.Message) $false }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("{0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail) { exit 1 }
exit 0
