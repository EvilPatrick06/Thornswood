<#
  test-feed-conditional.ps1

      pwsh -NoProfile -File .\tests\test-feed-conditional.ps1

  The launcher asks the update feed whether anything changed, and a repeat
  check, including the first one after a restart, is a 304 and not the whole
  document again (issue #443).

  WHY THIS EXISTS. Every launcher checks the feed at start and every thirty
  seconds while the game runs (CheckUpdatesInPlay). The feed is the whole
  history of packs, around ninety kilobytes on main and a hundred on dev,
  measured 28 September, and it only changes when somebody ships. Since #445
  the ETag of the last copy was kept in memory, so the in play checks were
  304s, but every start of the launcher downloaded the whole feed again.
  Updater now keeps the tag and the document together in Profile\feed-cache.txt.

  What it proves, against a feed server of its own on 127.0.0.1:
    - the first check downloads, and keeps the tag and the document in Profile
    - a repeat check sends If-None-Match, is answered 304, and reads the copy
    - a check after a restart (the in memory copy gone) does the same off disk
    - a machine many packs behind is still offered every pack it is missing,
      out of the copy the 304 left it with, in the order the feed lists them
    - a feed that changed is downloaded, and the new tag replaces the old
    - a copy from another feed address (the other channel) is never used
    - a copy cut short on disk is not believed
    - a server that sends only Last-Modified gets If-Modified-Since and a 304
    - a server that sends neither is simply downloaded every time, the way a
      launcher always read a feed
    - the feed is asked for compressed and read the same

  HOW. Compiles launcher\app\*.cs into a library with the same csc and the same
  references Build-Launcher.ps1 uses, as test-updater.ps1 does, and calls
  Updater.Conditional by reflection. That is the request FromSite makes after
  CheckUrl, which only lets https to thornswood.net through, so the local
  server is reached without loosening what a real launcher accepts. Paths
  points at a temp folder. Nothing under C:\Thornswood is read or written, and
  nothing leaves 127.0.0.1.

  Runs under Windows PowerShell 5.1 and restarts itself there from pwsh,
  because the launcher runs on the .NET Framework.
#>
[CmdletBinding()]
param([string]$Src)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Launcher-Csc.ps1')   # the build's compiler and C# version (#498)
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
# The tests are in tests\, the repository is one folder up.
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

# ---- the compiler and the references, the way Build-Launcher.ps1 finds them --
$csc = @(
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$refDirs = @(
    "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8"
    "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.7.2"
    "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.6.1"
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\WPF"
    "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\WPF"
    "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319"
) | Where-Object { Test-Path $_ }

function Find-Ref([string]$name) {
    foreach ($d in $refDirs) {
        $p = Join-Path $d $name
        if (Test-Path $p) { return $p }
    }
    $stem = [IO.Path]::GetFileNameWithoutExtension($name)
    foreach ($gacRoot in 'GAC_MSIL', 'GAC_64', 'GAC_32', 'GAC') {
        $gac = Join-Path "$env:WINDIR\Microsoft.NET\assembly\$gacRoot" $stem
        if (Test-Path $gac) {
            $hit = Get-ChildItem $gac -Filter $name -Recurse -File -EA SilentlyContinue |
                   Sort-Object FullName -Descending | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        }
    }
    $null
}

$needed = @($LauncherNeeded)
$wv2 = @($LauncherWv2Managed)

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tsfeedcond-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Force -Path $tmp

# ---- a feed server of its own, on 127.0.0.1 ---------------------------------
#
# Answers like the site's Caddy does, measured 28 September: an ETag on every
# answer, 304 with no body to a matching If-None-Match, gzip when asked with
# "-gzip" on the tag, and either tag accepted back. It can also be told to send
# only Last-Modified, or nothing at all, the way an older or another server
# would. Every request is written down so the test can say what was asked.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public class TsFeedServer
{
    TcpListener listener;
    public int Port;
    public volatile byte[] Body;
    public volatile string Etag;
    public volatile string LastModified;
    public volatile bool GzipOk;
    public readonly List<string[]> Seen = new List<string[]>();

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

    public string[] Last()
    {
        lock (Seen) { return Seen.Count == 0 ? null : Seen[Seen.Count - 1]; }
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

    static string Header(string[] lines, string name)
    {
        foreach (string l in lines)
        {
            int colon = l.IndexOf(':');
            if (colon > 0 && string.Equals(l.Substring(0, colon).Trim(), name, StringComparison.OrdinalIgnoreCase))
                return l.Substring(colon + 1).Trim();
        }
        return null;
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
        string[] lines = sb.ToString().Split(new[] { "\r\n" }, StringSplitOptions.None);
        string path = lines[0].Split(' ')[1];
        string inm = Header(lines, "If-None-Match");
        string ims = Header(lines, "If-Modified-Since");
        string ae = Header(lines, "Accept-Encoding") ?? "";

        byte[] body = Body;
        string etag = Etag, lm = LastModified;
        bool gz = GzipOk && ae.IndexOf("gzip", StringComparison.OrdinalIgnoreCase) >= 0;
        string gzTag = etag == null ? null : etag.TrimEnd('"') + "-gzip\"";
        string sendTag = gz ? gzTag : etag;

        bool notModified = false;
        if (etag != null && inm != null) notModified = inm == etag || inm == gzTag;
        else if (lm != null && ims != null)
        {
            DateTime a, m;
            if (DateTime.TryParse(ims, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal, out a) &&
                DateTime.TryParse(lm, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal, out m))
                notModified = a >= m;
        }

        var head = new StringBuilder();
        byte[] send = new byte[0];
        int status;
        if (notModified)
        {
            status = 304;
            head.Append("HTTP/1.1 304 Not Modified\r\n");
        }
        else
        {
            status = 200;
            send = body;
            if (gz)
            {
                using (var ms = new MemoryStream())
                {
                    using (var z = new GZipStream(ms, CompressionMode.Compress, true)) z.Write(body, 0, body.Length);
                    send = ms.ToArray();
                }
            }
            head.Append("HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\n");
            if (gz) head.Append("Content-Encoding: gzip\r\nVary: Accept-Encoding\r\n");
        }
        if (sendTag != null) head.Append("ETag: " + sendTag + "\r\n");
        if (lm != null) head.Append("Last-Modified: " + lm + "\r\n");
        head.Append("Cache-Control: no-cache\r\nContent-Length: " + send.Length + "\r\nConnection: close\r\n\r\n");
        byte[] h = Encoding.ASCII.GetBytes(head.ToString());
        s.Write(h, 0, h.Length);
        if (send.Length > 0) s.Write(send, 0, send.Length);
        s.Flush();
        lock (Seen) Seen.Add(new[] { path, inm ?? "", ims ?? "", ae, status.ToString(), send.Length.ToString() });
    }
}
'@

# A feed shaped like the live one: every pack in order, each with an address
# and notes, and news, so the document is the size a real one is.
function New-Feed([int]$packs, [string]$launcher = '1.1.101') {
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('{"launcherVersion":"' + $launcher + '","updateRepo":"EvilPatrick06/Thornswood-Releases","packs":[')
    for ($i = 1; $i -le $packs; $i++) {
        if ($i -gt 1) { [void]$sb.Append(',') }
        $sha = ('{0:x64}' -f $i)
        [void]$sb.Append('{"id":"pack-' + $i.ToString('000') + '","url":"https://thornswood.net/feed/assets/' + $sha +
                         '","sha256":"' + $sha + '","notes":"Release ' + $i + ' notes, a line or two about what changed for the people playing."}')
    }
    [void]$sb.Append('],"optional":[{"id":"opt-hd","url":"https://thornswood.net/feed/assets/' + ('{0:x64}' -f 9999) + '"}],"news":[')
    for ($i = 1; $i -le 40; $i++) {
        if ($i -gt 1) { [void]$sb.Append(',') }
        [void]$sb.Append('{"title":"News ' + $i + '","body":"' + ('Something happened. ' * 30) + '"}')
    }
    [void]$sb.Append(']}')
    return [Text.Encoding]::UTF8.GetBytes($sb.ToString())
}

function Run {
    Yes 'the .NET Framework 4 compiler is here' ($null -ne $csc)
    if (-not $csc -or $needed.Count -eq 0) { Yes 'Thornswood.csproj names the references' $false; return }

    $refs = @(); $missing = @()
    foreach ($n in $needed) {
        $p = Find-Ref $n
        if ($p) { $refs += $p } else { $missing += $n }
    }
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
    Yes ('the launcher''s {0} source files compile as C# 5' -f $cs.Count) $built
    if (-not $built) {
        foreach ($l in @($said | Where-Object { "$_" -match 'error' } | Select-Object -First 20)) { Write-Host "      $l" }
        return
    }

    $asm = [Reflection.Assembly]::Load([IO.File]::ReadAllBytes($dll))
    $U = $asm.GetType('Thornswood.Updater')
    $P = $asm.GetType('Thornswood.Paths')
    $C = $asm.GetType('Thornswood.Config')
    $flags = [Reflection.BindingFlags]'Static, Public, NonPublic'
    $cond = $U.GetMethod('Conditional', $flags)
    $pending = $U.GetMethod('Pending', $flags)
    $cachedF = $U.GetField('cached', $flags)
    $readF = $U.GetField('cacheRead', $flags)
    $notModF = $U.GetField('LastNotModified', $flags)
    Yes 'Updater.Conditional, Pending and the cache fields are in the build' (
        $null -ne $cond -and $null -ne $pending -and $null -ne $cachedF -and $null -ne $readF -and $null -ne $notModF)
    if ($null -eq $cond -or $null -eq $pending -or $null -eq $cachedF -or $null -eq $readF) { return }

    $profile = Join-Path $tmp 'Profile'
    $null = New-Item -ItemType Directory -Force -Path $profile
    $P.GetField('ProfileDir').SetValue($null, $profile)
    $P.GetField('AppliedFile').SetValue($null, (Join-Path $profile 'applied.txt'))
    $P.GetField('PacksDir').SetValue($null, (Join-Path $profile 'Packs'))
    $P.GetField('LogFile').SetValue($null, (Join-Path $profile 'launcher.log'))
    $cacheFile = Join-Path $profile 'feed-cache.txt'
    $cfg = [Activator]::CreateInstance($C)

    $srv = New-Object TsFeedServer
    $srv.Start()
    try {
        $base = "http://127.0.0.1:$($srv.Port)"
        $url = "$base/feed/version.json"

        function Check([string]$u) {
            $script:threw = $null
            $notModF.SetValue($null, $false)
            try { return $cond.Invoke($null, [object[]]@($cfg, $u)) }
            catch {
                $e = $_.Exception
                while ($null -ne $e.InnerException) { $e = $e.InnerException }
                $script:threw = $e.Message
                return $null
            }
        }
        function Restart { $cachedF.SetValue($null, $null); $readF.SetValue($null, $false) }
        function Ids($doc) {
            if ($null -eq $doc -or $null -eq $doc.packs) { return @() }
            return @($doc.packs | ForEach-Object { $_.id })
        }
        function PendingIds($doc) { return @(($pending.Invoke($null, [object[]]@($doc))) | ForEach-Object { $_.id }) }

        # ---- 1. the first check downloads and keeps the copy ------------------
        $v1 = New-Feed 200
        $srv.Body = $v1
        $srv.Etag = '"30d4-1a0e500fd32"'
        $srv.GzipOk = $true
        $d = Check $url
        $r = $srv.Last()
        Yes ('first check: a document with all 200 packs came back' + $(if ($script:threw) { ", threw $($script:threw)" } else { '' })) (
            (Ids $d).Count -eq 200)
        Yes 'first check: nothing conditional was asked, there was nothing to ask with' ($r[1] -eq '' -and $r[2] -eq '')
        Yes 'first check: answered 200 with the body' ($r[4] -eq '200' -and [int]$r[5] -gt 0)
        Yes 'first check: asked for it compressed' ($r[3] -match 'gzip')
        Yes ('first check: the compressed body was {0} bytes against {1} plain, and read the same' -f $r[5], $v1.Length) (
            [int]$r[5] -lt ($v1.Length / 2))
        Yes 'first check: not counted as unchanged' (-not [bool]$notModF.GetValue($null))
        Yes 'first check: the tag and the document are kept in Profile\feed-cache.txt' (Test-Path -LiteralPath $cacheFile)
        $lines = @()
        if (Test-Path -LiteralPath $cacheFile) { $lines = @([IO.File]::ReadAllLines($cacheFile) | Select-Object -First 4) }
        Yes 'the cache file says what it is, the feed address and the tag it arrived with' (
            $lines.Count -eq 4 -and $lines[0] -eq 'Thornswood feed cache 1' -and $lines[1] -eq $url -and $lines[2] -eq '"30d4-1a0e500fd32-gzip"')
        Yes 'no temp file is left beside it' (@(Get-ChildItem -LiteralPath $profile -Filter '*.tmp').Count -eq 0)

        # ---- 2. a repeat check is a 304 -------------------------------------
        $d = Check $url
        $r = $srv.Last()
        Yes 'repeat check: asked with If-None-Match and the tag it was given' ($r[1] -eq '"30d4-1a0e500fd32-gzip"')
        Yes ('repeat check: answered 304 with {0} bytes of body' -f $r[5]) ($r[4] -eq '304' -and $r[5] -eq '0')
        Yes 'repeat check: counted as unchanged' ([bool]$notModF.GetValue($null))
        Yes 'repeat check: the same 200 packs, read out of the copy' ((Ids $d).Count -eq 200 -and (Ids $d)[199] -eq 'pack-200')
        Yes 'repeat check: the optional list the Mods page reads is still there' ($null -ne $d.optional -and $d.optional.Count -eq 1 -and $d.optional[0].id -eq 'opt-hd')

        # ---- 3. the first check after a restart is a 304 too -----------------
        Restart
        $before = $srv.Count()
        $d = Check $url
        $r = $srv.Last()
        Yes 'after a restart: one request, no more' ($srv.Count() -eq $before + 1)
        Yes 'after a restart: asked with the tag kept in Profile' ($r[1] -eq '"30d4-1a0e500fd32-gzip"')
        Yes 'after a restart: answered 304, nothing downloaded' ($r[4] -eq '304' -and $r[5] -eq '0' -and [bool]$notModF.GetValue($null))
        Yes 'after a restart: all 200 packs, read off disk' ((Ids $d).Count -eq 200)

        # ---- 4. a machine many packs behind gets every one --------------------
        [IO.File]::WriteAllLines((Join-Path $profile 'applied.txt'), [string[]]@('pack-001', 'pack-002', 'pack-003'))
        $want = @(PendingIds $d)
        Yes ('many packs behind: out of the copy a 304 left, {0} of the 197 missing packs are offered' -f $want.Count) ($want.Count -eq 197)
        Yes 'many packs behind: from pack-004, in the order the feed lists them, to pack-200' (
            $want.Count -eq 197 -and $want[0] -eq 'pack-004' -and $want[196] -eq 'pack-200' -and (($want -join ',') -eq ((4..200 | ForEach-Object { 'pack-' + $_.ToString('000') }) -join ',')))

        # ---- 5. a feed that changed is downloaded -----------------------------
        $v2 = New-Feed 201 '1.1.102'
        $srv.Body = $v2
        $srv.Etag = '"30e1-1a0e6589dae"'
        $d = Check $url
        $r = $srv.Last()
        Yes 'after a Ship: asked with the old tag' ($r[1] -eq '"30d4-1a0e500fd32-gzip"')
        Yes 'after a Ship: answered 200, the new document came down' ($r[4] -eq '200' -and -not [bool]$notModF.GetValue($null))
        Yes 'after a Ship: it carries the new pack and the new launcher' ((Ids $d).Count -eq 201 -and $d.launcherVersion -eq '1.1.102')
        $want = @(PendingIds $d)
        Yes ('after a Ship: a machine many packs behind is offered {0}, every one it is missing including the new one' -f $want.Count) (
            $want.Count -eq 198 -and $want[197] -eq 'pack-201')
        Restart
        $d = Check $url
        $r = $srv.Last()
        Yes 'after a Ship and a restart: the new tag was kept, and the answer is 304 with the new document' (
            $r[1] -eq '"30e1-1a0e6589dae-gzip"' -and $r[4] -eq '304' -and (Ids $d).Count -eq 201)

        # ---- 6. another channel's copy is never used -------------------------
        $dev = "$base/feed-dev/version.json"
        $d = Check $dev
        $r = $srv.Last()
        Yes 'another feed address: asked with nothing, the copy belongs to the other channel' ($r[0] -eq '/feed-dev/version.json' -and $r[1] -eq '' -and $r[4] -eq '200')
        Restart
        $d = Check $url
        $r = $srv.Last()
        Yes 'and back again after a restart: the copy on disk is the dev one now, so main asks with nothing' ($r[1] -eq '' -and $r[4] -eq '200')

        # ---- 7. a copy cut short is not believed -----------------------------
        $raw = [IO.File]::ReadAllBytes($cacheFile)
        [IO.File]::WriteAllBytes($cacheFile, $raw[0..($raw.Length - 500)])
        Restart
        $d = Check $url
        $r = $srv.Last()
        Yes 'a copy cut short on disk: asked with nothing, downloaded, read' ($r[1] -eq '' -and $r[4] -eq '200' -and (Ids $d).Count -eq 201)
        [IO.File]::WriteAllText($cacheFile, 'something else entirely')
        Restart
        $d = Check $url
        $r = $srv.Last()
        Yes 'a file that is not a cache at all: asked with nothing, downloaded, read' ($r[1] -eq '' -and $r[4] -eq '200' -and (Ids $d).Count -eq 201)
        Restart
        $d = Check $url
        Yes 'and the copy written over it works again after a restart' ($srv.Last()[4] -eq '304' -and (Ids $d).Count -eq 201)

        # ---- 8. Last-Modified only -------------------------------------------
        $srv.Etag = $null
        $srv.GzipOk = $false
        $srv.LastModified = 'Mon, 28 Sep 2026 06:51:12 GMT'
        Restart
        Remove-Item -LiteralPath $cacheFile -Force
        $d = Check $url
        $d = Check $url
        $r = $srv.Last()
        Yes ('a server with only Last-Modified: the repeat asks If-Modified-Since, got "{0}"' -f $r[2]) ($r[1] -eq '' -and $r[2] -eq 'Mon, 28 Sep 2026 06:51:12 GMT')
        Yes 'a server with only Last-Modified: answered 304 and read the copy' ($r[4] -eq '304' -and (Ids $d).Count -eq 201)
        Restart
        $d = Check $url
        Yes 'a server with only Last-Modified: and after a restart too' ($srv.Last()[4] -eq '304' -and (Ids $d).Count -eq 201)

        # ---- 9. neither: read the way a launcher always did -------------------
        $srv.LastModified = $null
        Restart
        Remove-Item -LiteralPath $cacheFile -Force
        $d = Check $url
        $d = Check $url
        $r = $srv.Last()
        Yes 'a server that sends no tag and no date: every check downloads, asking nothing, and reads' (
            $r[1] -eq '' -and $r[2] -eq '' -and $r[4] -eq '200' -and (Ids $d).Count -eq 201)
        Yes 'a server that sends no tag and no date: nothing is kept on disk, there is nothing to ask with' (-not (Test-Path -LiteralPath $cacheFile))

        # ---- 10. a feed that fails still fails --------------------------------
        $srv.Stop()
        Restart
        $d = Check $url
        Yes ('a feed that does not answer throws, so Check falls back to GitHub as before: ' + $script:threw) ($null -eq $d -and $null -ne $script:threw)
    }
    finally { $srv.Stop() }

    # ---- the address a real launcher asks is still fenced --------------------
    $src = Get-Content -LiteralPath (Join-Path $Src 'Updater.cs') -Raw
    Yes 'FromSite still runs CheckUrl on the feed address before the request' (
        $src -match '(?s)static VersionDoc FromSite\(Config cfg, string feedUrl\)\s*\{\s*CheckUrl\(feedUrl\);\s*return Conditional\(cfg, feedUrl\);')
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
