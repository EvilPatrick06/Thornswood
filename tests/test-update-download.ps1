<#
  test-update-download.ps1

      pwsh -NoProfile -File .\tests\test-update-download.ps1

  The Launcher's update path between the feed and the files: the parts no
  harness ran. From launcher\app\Updater.cs:

      Download / Fetch      checksum is mandatory, a wrong, short or broken
                            download is rejected and its part file deleted,
                            the url is checked before a byte is asked for
      ApplyPack             a pack already in is not fetched twice, a release
                            record syncs instead of downloading, the zip is
                            deleted whether Install worked or threw
      SelfUpdate            a launcher that fails its checksum or its signer
                            check never reaches Thornswood.exe.new, and the
                            download it refused is not left in %TEMP%
      WriteCache/ReadCache  the feed cache round-trips, and a copy from an
                            older shape, cut short, or with a body that does
                            not parse is not believed
      WrapFeedFail          what a failed feed check says
      Applied/Skip/MarkApplied/Unapply/IsInstalled/PackListFile/Requeue
                            the applied.txt bookkeeping the rollback leans on

  Each method is lifted out of the real Updater.cs (the brace-matched body,
  the way test-play-stuck-game.ps1 does it) and compiled with the .NET
  Framework csc as C# 5, the way Build-Launcher.ps1 compiles the launcher,
  beside stand-ins for Paths, PlayProgress, Swallow, Signature, VersionDoc,
  Install and SyncRecord. Downloads come from a stand-in WebClient that hands
  back scripted bytes, so nothing touches the network, and TMP points at a
  scratch folder so what a download leaves behind can be counted.

  No process is started apart from the compiled driver. Writes only to its own
  temp folder.
#>
[CmdletBinding()]
param([string]$AppDir)

$ErrorActionPreference = 'Stop'
$Here = $PSScriptRoot
if (-not $Here) { $Here = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$Repo = Split-Path -Parent $Here
if (-not $AppDir) { $AppDir = Join-Path $Repo 'launcher\app' }

$script:pass = 0
$script:fail = 0
function Yes([string]$what, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "PASS  $what" }
    else { $script:fail++; Write-Host "FAIL  $what" }
}
function Done {
    Write-Host ''
    Write-Host "$script:pass passed, $script:fail failed"
    exit $(if ($script:fail) { 1 } else { 0 })
}
function Body([string]$src, [string]$start) {
    $at = $src.IndexOf($start)
    if ($at -lt 0) { return '' }
    $open = $src.IndexOf('{', $at)
    $depth = 0
    for ($i = $open; $i -lt $src.Length; $i++) {
        if ($src[$i] -eq '{') { $depth++ }
        elseif ($src[$i] -eq '}') { $depth--; if ($depth -eq 0) { return $src.Substring($at, $i - $at + 1) } }
    }
    return ''
}

$upPath = Join-Path $AppDir 'Updater.cs'
Yes 'Updater.cs is in the launcher source' (Test-Path -LiteralPath $upPath)
if (-not (Test-Path -LiteralPath $upPath)) { Done }
$up = [IO.File]::ReadAllText($upPath, [Text.Encoding]::UTF8)

$sigs = @(
    'static string CacheFile',
    'static void WriteCache(Cached c, byte[] body)',
    'static string OneLine(string s)',
    'static Cached ReadCache()',
    'static bool NotChanged(WebException wex)',
    'static Exception WrapFeedFail(Exception ex, bool fromHost)',
    'public static HashSet<string> Applied()',
    'public static void Skip(string id)',
    'static void MarkApplied(string id)',
    'static void Unapply(string id)',
    'public static bool IsInstalled(string id)',
    'static string PackListFile(string id)',
    'static string Sha256(string file)',
    'public static string Fetch(Config cfg, string url, string expectSha, Action<string> log)',
    'static string Download(Config cfg, string url, string expectSha, Action<string> log)',
    'public static void ApplyPack(Config cfg, Pack p, Action<string> log)',
    'public static int Requeue()',
    'static void CheckSigner(string path, Action<string> log)',
    'public static void SelfUpdate(Config cfg, VersionDoc v, Action<string> log)'
)
$bodies = @()
foreach ($sig in $sigs) {
    $b = Body $up $sig
    Yes "lifted $sig" ($b.Length -gt 0)
    $bodies += $b
}
foreach ($c in @('const string CacheMagic', 'const string ListHeader')) {
    $m = [regex]::Match($up, [regex]::Escape($c) + '\s*=\s*"[^"]*";')
    Yes "lifted $c" $m.Success
    $bodies += $m.Value
}
if ($script:fail) { Done }

$csc = @("$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Yes 'the .NET Framework 4 compiler is here' ($null -ne $csc)
if (-not $csc) { Done }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('ts-update-dl-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$scratchTemp = Join-Path $tmp 'temp'
$profile = Join-Path $tmp 'profile'
New-Item -ItemType Directory -Path $scratchTemp, $profile, (Join-Path $profile 'packs') | Out-Null

$driver = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
namespace Thornswood
{
    class Config { }
    class RecordRef { }
    class Pack { public string id, url, sha256; public RecordRef Record; public VersionDoc Doc; }
    class VersionDoc
    {
        public string launcherVersion, launcherUrl, launcherSha256, said;
        public static VersionDoc Parse(byte[] b)
        {
            string s = Encoding.UTF8.GetString(b);
            if (!s.StartsWith("{") || !s.EndsWith("}")) return null;
            var d = new VersionDoc(); d.said = s; return d;
        }
    }
    static class Paths
    {
        public static string ProfileDir, AppliedFile, PacksDir;
        public static bool Collection;
    }
    static class SelfSwap { public static int Scripts; public static string Script(string exe, string neu, int pid) { Scripts++; return ""; } }
    static class Swallow { public static int Notes; public static void Note(string w, Exception e) { Notes++; } }
    static class PlayProgress
    {
        public static long LastGot = -9, LastLen = -9; public static int Done;
        public static void Part(long got, long len) { LastGot = got; LastLen = len; }
        public static void PartDone() { Done++; }
    }
    static class Signature
    {
        public static string Why = "";
        public static string Refusal(string path, string expectedSigner, out string said)
        { said = "Signed by " + expectedSigner + "."; return Why; }
    }

    // Scripted downloads: bytes to hand back, a Content-Length to claim, and
    // a point at which the stream breaks.
    static class Net
    {
        public static byte[] Body = new byte[0];
        public static long Claim = -1;
        public static int BreakAt = -1;
        public static int Opens;
        public static List<string> UrlsChecked = new List<string>();
        public static string RefuseUrl;
    }
    class BreakingStream : MemoryStream
    {
        int left;
        public BreakingStream(byte[] b, int breakAt) : base(b) { left = breakAt; }
        public override int Read(byte[] buf, int off, int count)
        {
            if (left >= 0)
            {
                if (left == 0) throw new IOException("connection reset");
                count = Math.Min(count, left);
                int n = base.Read(buf, off, count); left -= n; return n;
            }
            return base.Read(buf, off, count);
        }
    }
    class FakeResponse : WebResponse
    {
        WebHeaderCollection h = new WebHeaderCollection();
        public FakeResponse() { if (Net.Claim >= 0) h["Content-Length"] = Net.Claim.ToString(); }
        public override WebHeaderCollection Headers { get { return h; } }
        public override Stream GetResponseStream() { return new BreakingStream(Net.Body, Net.BreakAt); }
        public override void Close() { }
    }
    class FakeRequest : WebRequest
    {
        Uri u; public FakeRequest(Uri u) { this.u = u; }
        public override Uri RequestUri { get { return u; } }
        public override WebResponse GetResponse() { return new FakeResponse(); }
    }
    class FakeClient : WebClient
    {
        protected override WebRequest GetWebRequest(Uri a) { Net.Opens++; return new FakeRequest(a); }
        protected override WebResponse GetWebResponse(WebRequest r) { return r.GetResponse(); }
    }

    static partial class Updater
    {
        public const string ExpectedSigner = "Test Signer"; // a stand-in: the real name lives only in Updater.cs (#1052)
        class Cached { public string Url, Etag, LastModified; public VersionDoc Doc; }

        static WebClient Client(Config cfg, bool octet, string url) { return new FakeClient(); }
        static void CheckUrl(string url)
        {
            Net.UrlsChecked.Add(url);
            if (url == Net.RefuseUrl) throw new Exception("The update feed pointed at elsewhere. Refused.");
        }

        public static int Installs, Syncs; public static string InstalledFrom; public static bool InstallThrows, ZipThereDuringInstall;
        public static void Install(string zip, Pack p, Action<string> log)
        {
            Installs++; InstalledFrom = zip; ZipThereDuringInstall = File.Exists(zip);
            if (InstallThrows) throw new InvalidDataException("not a zip");
            MarkApplied(p.id);
        }
        public static void SyncRecord(Config cfg, RecordRef r, VersionDoc v, Action<string> log) { Syncs++; }

/*BODIES*/
    }

    static class Drive
    {
        static int pass, fail;
        static void Yes(string what, bool c) { Console.WriteLine((c ? "PASS  " : "FAIL  ") + what); if (c) pass++; else fail++; }
        static List<string> logged = new List<string>();
        static void Log(string s) { logged.Add(s); }
        static Config cfg = new Config();

        static string Hex(byte[] b)
        {
            using (var h = SHA256.Create())
            {
                var sb = new StringBuilder();
                foreach (byte x in h.ComputeHash(b)) sb.Append(x.ToString("x2"));
                return sb.ToString();
            }
        }
        static int Parts() { return Directory.GetFiles(Path.GetTempPath(), "thornswood-*.bin").Length; }
        static void Clear()
        {
            foreach (string f in Directory.GetFiles(Path.GetTempPath(), "thornswood-*")) File.Delete(f);
            Net.Body = new byte[0]; Net.Claim = -1; Net.BreakAt = -1; Net.Opens = 0; Net.UrlsChecked.Clear(); Net.RefuseUrl = null;
            PlayProgress.LastGot = -9; PlayProgress.LastLen = -9; PlayProgress.Done = 0;
            logged.Clear(); Signature.Why = "";
            Installs = 0; Syncs = 0; InstalledFrom = null; InstallThrows = false; ZipThereDuringInstall = false;
            if (File.Exists(Paths.AppliedFile)) File.Delete(Paths.AppliedFile);
        }
        static int Installs { get { return Updater.Installs; } set { Updater.Installs = value; } }
        static int Syncs { get { return Updater.Syncs; } set { Updater.Syncs = value; } }
        static string InstalledFrom { get { return Updater.InstalledFrom; } set { Updater.InstalledFrom = value; } }
        static bool InstallThrows { get { return Updater.InstallThrows; } set { Updater.InstallThrows = value; } }
        static bool ZipThereDuringInstall { get { return Updater.ZipThereDuringInstall; } set { Updater.ZipThereDuringInstall = value; } }

        static Exception Try(Action a) { try { a(); return null; } catch (Exception e) { return e; } }

        static int Main(string[] args)
        {
            Paths.ProfileDir = args[0];
            Paths.AppliedFile = Path.Combine(args[0], "applied.txt");
            Paths.PacksDir = Path.Combine(args[0], "packs");
            byte[] body = new byte[200000];
            new Random(7).NextBytes(body);
            string sha = Hex(body);
            const string url = "https://github.com/EvilPatrick06/Thornswood-Releases/releases/download/x/pack.zip";

            // ---------- Download ----------
            Clear(); Net.Body = body; Net.Claim = body.Length;
            string got = null;
            Exception e = Try(() => got = Updater.Fetch(cfg, url, sha, Log));
            Yes("download: right checksum hands back the file", e == null && got != null && File.Exists(got));
            Yes("download: the file holds exactly the bytes sent", got != null && File.Exists(got) && Hex(File.ReadAllBytes(got)) == sha);
            Yes("download: the url is checked before the fetch", Net.UrlsChecked.Count == 1 && Net.UrlsChecked[0] == url);
            Yes("download: says the checksum was verified", logged.Contains("Checksum verified."));
            Yes("download: progress ends at the full length and is closed", PlayProgress.LastGot == body.Length && PlayProgress.LastLen == body.Length && PlayProgress.Done == 1);

            Clear(); Net.Body = body;
            e = Try(() => got = Updater.Fetch(cfg, url, sha.ToUpperInvariant(), Log));
            Yes("download: an upper-case checksum still matches", e == null);
            Yes("download: no Content-Length reads as unknown length (-1)", PlayProgress.LastLen == -1);

            Clear(); Net.Body = body; Net.Claim = body.Length;
            string wrong = sha.Substring(0, 63) + (sha[63] == '0' ? "1" : "0");
            e = Try(() => Updater.Fetch(cfg, url, wrong, Log));
            Yes("download: wrong checksum is rejected", e != null && e.Message.Contains("Checksum did not match"));
            Yes("download: the rejected file is deleted", Parts() == 0);
            Yes("download: a rejected file never says verified", !logged.Contains("Checksum verified."));

            Clear(); Net.Body = body;
            e = Try(() => Updater.Fetch(cfg, url, "", Log));
            Yes("download: no checksum refuses before asking for a byte", e != null && e.Message.Contains("without a checksum") && Net.Opens == 0);
            Clear();
            e = Try(() => Updater.Fetch(cfg, url, null, Log));
            Yes("download: a null checksum is refused the same way", e != null && Net.Opens == 0 && Parts() == 0);

            Clear(); Net.Body = body; Net.RefuseUrl = url;
            e = Try(() => Updater.Fetch(cfg, url, sha, Log));
            Yes("download: an address the url check refuses fetches nothing", e != null && e.Message.Contains("Refused") && Net.Opens == 0 && Parts() == 0);

            Clear(); Net.Body = body; Net.Claim = body.Length; Net.BreakAt = 100000;
            e = Try(() => Updater.Fetch(cfg, url, sha, Log));
            Yes("download: a connection that breaks mid-file throws", e is IOException);
            Yes("download: the part file is deleted after the break", Parts() == 0);
            Yes("download: progress is not closed as done after a break", PlayProgress.Done == 0);

            Clear(); Net.Body = new byte[150000]; Buffer.BlockCopy(body, 0, Net.Body, 0, 150000); Net.Claim = body.Length;
            e = Try(() => Updater.Fetch(cfg, url, sha, Log));
            Yes("download: a file cut short with no error fails its checksum", e != null && e.Message.Contains("Checksum did not match"));
            Yes("download: and the short file is deleted", Parts() == 0);

            Clear(); Net.Body = (byte[])body.Clone(); Net.Body[1234] ^= 0xFF;
            e = Try(() => Updater.Fetch(cfg, url, sha, Log));
            Yes("download: one flipped byte is rejected and deleted", e != null && Parts() == 0);

            Clear(); Net.Body = new byte[0];
            e = Try(() => Updater.Fetch(cfg, url, sha, Log));
            Yes("download: an empty answer is rejected and deleted", e != null && Parts() == 0);

            // ---------- ApplyPack ----------
            var p = new Pack(); p.id = "pack-a"; p.url = url; p.sha256 = sha;
            Clear(); Net.Body = body; File.WriteAllText(Paths.AppliedFile, "PACK-A\r\n");
            e = Try(() => Updater.ApplyPack(cfg, p, Log));
            Yes("apply: a pack already in (any case) is not fetched again", e == null && Net.Opens == 0 && Installs == 0 && logged.Contains("pack-a is already in."));

            Clear(); Net.Body = body;
            e = Try(() => Updater.ApplyPack(cfg, p, Log));
            Yes("apply: a new pack is downloaded and installed", e == null && Installs == 1 && ZipThereDuringInstall);
            Yes("apply: the zip is deleted after a good install", InstalledFrom != null && !File.Exists(InstalledFrom) && Parts() == 0);
            Yes("apply: and the pack reads as installed", Updater.IsInstalled("pack-a"));

            Clear(); Net.Body = body; InstallThrows = true;
            e = Try(() => Updater.ApplyPack(cfg, p, Log));
            Yes("apply: an install that throws passes the error up", e is InvalidDataException);
            Yes("apply: the zip is deleted after a failed install", InstalledFrom != null && !File.Exists(InstalledFrom) && Parts() == 0);
            Yes("apply: a failed install is not written as applied", !Updater.IsInstalled("pack-a"));

            Clear(); Net.Body = body;
            e = Try(() => Updater.ApplyPack(cfg, new Pack { id = "pack-b", url = url, sha256 = wrong }, Log));
            Yes("apply: a pack failing its checksum is not installed or applied", e != null && Installs == 0 && !Updater.IsInstalled("pack-b"));

            Clear();
            e = Try(() => Updater.ApplyPack(cfg, new Pack { id = "release-9", Record = new RecordRef() }, Log));
            Yes("apply: a release record syncs and downloads nothing", e == null && Syncs == 1 && Net.Opens == 0 && Installs == 0);

            // ---------- SelfUpdate ----------
            string exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
            var v = new VersionDoc(); v.launcherVersion = "9.9.9"; v.launcherUrl = url; v.launcherSha256 = sha;
            Clear(); Net.Body = body; Signature.Why = "is not signed.";
            e = Try(() => Updater.SelfUpdate(cfg, v, Log));
            Yes("self-update: a launcher failing the signer check is refused", e != null && e.Message.Contains("Nothing has been replaced"));
            Yes("self-update: nothing is put at Thornswood.exe.new", !File.Exists(exe + ".new"));
            Yes("self-update: no swap script is written", Directory.GetFiles(Path.GetTempPath(), "thornswood-update-*.cmd").Length == 0);
            Yes("self-update: the refused download is not left in TEMP", Parts() == 0);

            Clear(); Net.Body = body; v.launcherSha256 = wrong;
            e = Try(() => Updater.SelfUpdate(cfg, v, Log));
            Yes("self-update: a launcher failing its checksum is refused", e != null && e.Message.Contains("Checksum did not match"));
            Yes("self-update: nothing at .new and nothing in TEMP", !File.Exists(exe + ".new") && Parts() == 0);

            Clear(); Net.Body = body; v.launcherSha256 = "";
            e = Try(() => Updater.SelfUpdate(cfg, v, Log));
            Yes("self-update: a launcher with no checksum is never fetched", e != null && Net.Opens == 0 && !File.Exists(exe + ".new"));

            // ---------- Feed cache ----------
            string cacheFile = Path.Combine(Paths.ProfileDir, "feed-cache.txt");
            var c = new Updater_Cached();
            byte[] doc = Encoding.UTF8.GetBytes("{\"version\":\"1.2.1\",\"packs\":[]}");
            Updater_Cache.Write("https://thornswood.net/feed/version.json", "W/\"abc\"\r\nX-Evil: 1", "Sat, 10 Oct 2026 00:00:00 GMT", doc);
            Yes("cache: the copy is written to Profile\\feed-cache.txt", File.Exists(cacheFile));
            Yes("cache: no .tmp is left beside it", Directory.GetFiles(Paths.ProfileDir, "feed-cache.txt.*.tmp").Length == 0);
            string[] r = Updater_Cache.Read();
            Yes("cache: reads back the url", r != null && r[0] == "https://thornswood.net/feed/version.json");
            Yes("cache: a tag with a line break in it is kept on one line", r != null && r[1] == "W/\"abc\"X-Evil: 1");
            Yes("cache: reads back Last-Modified and the document", r != null && r[2] == "Sat, 10 Oct 2026 00:00:00 GMT" && r[3] == Encoding.UTF8.GetString(doc));

            File.WriteAllText(cacheFile, "Thornswood feed cache 0\nu\ne\nl\n{}");
            Yes("cache: an older shape is not believed", Updater_Cache.Read() == null);
            File.WriteAllText(cacheFile, "Thornswood feed cache 1\nu\ne");
            Yes("cache: a header cut short is not believed", Updater_Cache.Read() == null);
            File.WriteAllText(cacheFile, "Thornswood feed cache 1\nu\ne\nl\n");
            Yes("cache: a header with no document is not believed", Updater_Cache.Read() == null);
            File.WriteAllText(cacheFile, "Thornswood feed cache 1\nu\ne\nl\n{\"version\":\"1.2");
            Yes("cache: a document cut short is not believed", Updater_Cache.Read() == null);
            File.WriteAllText(cacheFile, "Thornswood feed cache 1\r\nu\r\ne\r\nl\r\n{}");
            r = Updater_Cache.Read();
            Yes("cache: CRLF line ends still read", r != null && r[0] == "u" && r[1] == "e" && r[2] == "l");
            File.Delete(cacheFile);
            Yes("cache: no file reads as no cache", Updater_Cache.Read() == null);
            string keep = Paths.ProfileDir; Paths.ProfileDir = null;
            Updater_Cache.Write("u", "e", "l", doc);
            Yes("cache: no Profile folder writes nothing and reads null", Updater_Cache.Read() == null && !File.Exists(cacheFile));
            Paths.ProfileDir = keep;

            // ---------- WrapFeedFail / NotChanged ----------
            Exception w = Updater_Wrap.Wrap(new WebException("t", WebExceptionStatus.Timeout), true);
            Yes("feed fail: a timeout says the site feed did not answer in time", w.Message.StartsWith("the site update feed did not answer in time"));
            w = Updater_Wrap.Wrap(new WebException("t", WebExceptionStatus.Timeout), false);
            Yes("feed fail: a GitHub timeout names GitHub", w.Message.StartsWith("GitHub did not answer in time"));
            var own = new Exception("The update feed gave an address that is not an address.");
            Yes("feed fail: the launcher's own message passes through untouched", Object.ReferenceEquals(Updater_Wrap.Wrap(own, true), own));
            w = Updater_Wrap.Wrap(new WebException("The remote name could not be resolved: 'thornswood.net'"), true);
            Yes("feed fail: anything else says could not reach the site feed", w.Message == "could not reach the site update feed");
            Yes("feed fail: a WebException with no response is not a 304", !Updater_Wrap.NotChanged(new WebException("x")));

            // ---------- applied.txt bookkeeping ----------
            Clear();
            Updater.Skip(""); Updater.Skip(null);
            Yes("bookkeeping: skipping no id writes nothing", !File.Exists(Paths.AppliedFile));
            Updater.Skip("dead-pack");
            Yes("bookkeeping: a skipped pack reads as applied", Updater.IsInstalled("dead-pack") && Updater.IsInstalled("DEAD-PACK"));
            Yes("bookkeeping: an empty id is never installed", !Updater.IsInstalled("") && !Updater.IsInstalled(null));
            File.WriteAllText(Paths.AppliedFile, "a\r\n  Pack-X  \r\n\r\nb\r\npack-x\r\n");
            Updater_Book.Unapply("PACK-X");
            var left = Updater.Applied();
            Yes("bookkeeping: Unapply takes out every copy of the id, any case", !left.Contains("pack-x") && left.Contains("a") && left.Contains("b") && left.Count == 2);
            Updater_Book.Unapply("not-there");
            Yes("bookkeeping: Unapply of an id that is not there keeps the rest", Updater.Applied().Count == 2);
            Yes("bookkeeping: a pack list name has no characters Windows refuses", Path.GetFileName(Updater_Book.ListOf("a/b:c*d?")) == "a_b_c_d_.files");

            // Requeue
            Clear();
            File.WriteAllText(Paths.AppliedFile, "headed\r\nbare\r\nseeded\r\n");
            File.WriteAllText(Updater_Book.ListOf("headed"), "\r\n# fence=game\r\nN|game\\x.esp\r\n");
            File.WriteAllText(Updater_Book.ListOf("bare"), "N|profile\\x.ini\r\n");
            Paths.Collection = false;
            Yes("requeue: does nothing off a collection install", Updater.Requeue() == 0 && Updater.Applied().Count == 3);
            Paths.Collection = true;
            int n = Updater.Requeue();
            var after = Updater.Applied();
            Yes("requeue: a list without the fence header is applied again", n == 1 && !after.Contains("bare") && !File.Exists(Updater_Book.ListOf("bare")));
            Yes("requeue: a headed list and a seeded pack with no list are kept", after.Contains("headed") && after.Contains("seeded") && File.Exists(Updater_Book.ListOf("headed")));
            Yes("requeue: a second run finds nothing", Updater.Requeue() == 0);
            Paths.Collection = false;

            Console.WriteLine("DRIVER " + pass + " " + fail);
            return fail == 0 ? 0 : 1;
        }
    }

    // Windows into the private members, so the cases above read plainly.
    class Updater_Cached { }
    static partial class Updater
    {
        internal static void CacheWrite(string u, string e, string l, byte[] b) { var c = new Cached(); c.Url = u; c.Etag = e; c.LastModified = l; WriteCache(c, b); }
        internal static string[] CacheRead() { var c = ReadCache(); return c == null ? null : new[] { c.Url, c.Etag, c.LastModified, c.Doc.said }; }
        internal static Exception WrapX(Exception e, bool h) { return WrapFeedFail(e, h); }
        internal static bool NotChangedX(WebException w) { return NotChanged(w); }
        internal static void UnapplyX(string id) { Unapply(id); }
        internal static string ListOfX(string id) { return PackListFile(id); }
    }
    static class Updater_Cache
    {
        public static void Write(string u, string e, string l, byte[] b) { Updater.CacheWrite(u, e, l, b); }
        public static string[] Read() { return Updater.CacheRead(); }
    }
    static class Updater_Wrap
    {
        public static Exception Wrap(Exception e, bool h) { return Updater.WrapX(e, h); }
        public static bool NotChanged(WebException w) { return Updater.NotChangedX(w); }
    }
    static class Updater_Book
    {
        public static void Unapply(string id) { Updater.UnapplyX(id); }
        public static string ListOf(string id) { return Updater.ListOfX(id); }
    }
}
'@

$src = Join-Path $tmp 'drive.cs'
[IO.File]::WriteAllText($src, $driver.Replace('/*BODIES*/', ($bodies -join "`r`n`r`n")), (New-Object Text.UTF8Encoding($false)))
$exe = Join-Path $tmp 'drive.exe'
$out = & $csc /nologo /langversion:5 /target:exe "/out:$exe" $src 2>&1
Yes 'the lifted methods compile as C# 5 beside the stand-ins' ($LASTEXITCODE -eq 0)
if ($LASTEXITCODE -ne 0) { $out | ForEach-Object { Write-Host "    $_" }; Remove-Item -LiteralPath $tmp -Recurse -Force; Done }

$oldTmp = $env:TMP; $oldTemp = $env:TEMP
try {
    $env:TMP = $scratchTemp; $env:TEMP = $scratchTemp
    $lines = & $exe $profile
    $code = $LASTEXITCODE
} finally { $env:TMP = $oldTmp; $env:TEMP = $oldTemp }
foreach ($l in $lines) {
    if ($l -match '^PASS  (.*)$') { Yes $Matches[1] $true }
    elseif ($l -match '^FAIL  (.*)$') { Yes $Matches[1] $false }
}
Yes 'the driver ran to the end' (($lines | Where-Object { $_ -like 'DRIVER *' }).Count -eq 1)

# Order in the real SelfUpdate: the signer check comes before anything is put
# at .new, and the swap script is only written after the copy.
$self = Body $up 'public static void SelfUpdate(Config cfg, VersionDoc v, Action<string> log)'
$iSign = $self.IndexOf('CheckSigner(tmp'); $iCopy = $self.IndexOf('File.Copy(tmp, neu'); $iBat = $self.IndexOf('SelfSwap.Script(')
Yes 'SelfUpdate checks the signer before the copy to .new' ($iSign -gt 0 -and $iCopy -gt $iSign)
Yes 'SelfUpdate writes the swap script only after the copy' ($iBat -gt $iCopy)

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Done
