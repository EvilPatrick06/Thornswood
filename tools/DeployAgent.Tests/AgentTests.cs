using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Thornswood.DeployAgent;
using Xunit;

namespace Thornswood.DeployAgent.Tests;

// ---- a stand-in GitHub, and the health address of a stand-in server ---------

sealed class FakeGitHub : HttpMessageHandler
{
    public const string Api = "https://gh.test";
    readonly object gate = new();
    long nextId = 1000;
    public readonly List<JsonObject> Deps = new();
    public readonly Dictionary<long, List<JsonObject>> StatusesById = new();
    public readonly Dictionary<string, JsonObject> Releases = new();
    public readonly Dictionary<long, byte[]> Files = new();
    public readonly Dictionary<long, string> Names = new();
    public readonly List<string> Downloaded = new();
    /// <summary>Tags with no published Release.</summary>
    public readonly List<string> BareTags = new();
    public Func<HttpRequestMessage, HttpResponseMessage>? Other { get; set; }

    public void AddRelease(string tag, Dictionary<string, byte[]> files)
    {
        lock (gate)
        {
            var assets = new JsonArray();
            foreach (var (name, b) in files)
            {
                var id = nextId++;
                Files[id] = b;
                Names[id] = name;
                assets.Add(new JsonObject { ["id"] = id, ["name"] = name, ["size"] = b.Length, ["url"] = $"{Api}/repos/O/R/releases/assets/{id}" });
            }
            Releases[tag] = new JsonObject { ["id"] = nextId++, ["tag_name"] = tag, ["draft"] = false, ["assets"] = assets };
        }
    }

    /// <summary>Changes one asset's bytes after the Release was made, the way
    /// somebody would tamper with it.</summary>
    public void Replace(string tag, string name, byte[] b)
    {
        lock (gate)
        {
            foreach (var a in Releases[tag]["assets"]!.AsArray())
            {
                if ((string)a!["name"]! != name) continue;
                Files[(long)a["id"]!] = b;
                a["size"] = b.Length;
            }
        }
    }

    public long AddDeployment(string env, string sha, string payloadJson)
    {
        lock (gate)
        {
            var id = nextId++;
            Deps.Insert(0, new JsonObject
            {
                ["id"] = id, ["sha"] = sha, ["task"] = "deploy", ["environment"] = env,
                ["payload"] = JsonNode.Parse(payloadJson), ["creator"] = new JsonObject { ["login"] = "github-actions[bot]" },
            });
            return id;
        }
    }

    public List<string> States(long id)
    {
        lock (gate)
        {
            if (!StatusesById.TryGetValue(id, out var l)) return new();
            return l.AsEnumerable().Reverse().Select(s => (string)s["state"]!).ToList();
        }
    }

    public JsonObject? Last(long id)
    {
        lock (gate) return StatusesById.TryGetValue(id, out var l) && l.Count > 0 ? l[0] : null;
    }

    static HttpResponseMessage Json(HttpStatusCode code, string body) =>
        new(code) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage r, CancellationToken ct)
    {
        if (r.RequestUri!.Host != "gh.test")
            return Other?.Invoke(r) ?? new HttpResponseMessage(HttpStatusCode.NotFound);
        var body = r.Content == null ? "" : await r.Content.ReadAsStringAsync(ct);
        var p = r.RequestUri.AbsolutePath;
        var q = System.Web.HttpUtility.ParseQueryString(r.RequestUri.Query);
        lock (gate)
        {
            const string dp = "/repos/O/R/deployments/";
            if (r.Method == HttpMethod.Get && p == "/repos/O/R/deployments")
            {
                var env = q["environment"];
                return Json(HttpStatusCode.OK, new JsonArray(Deps.Where(d => (string)d["environment"]! == env).Select(d => d.DeepClone()).ToArray()).ToJsonString());
            }
            if (p.StartsWith(dp) && p.EndsWith("/statuses"))
            {
                var id = long.Parse(p[dp.Length..^"/statuses".Length]);
                if (!StatusesById.TryGetValue(id, out var l)) StatusesById[id] = l = new();
                if (r.Method == HttpMethod.Post)
                {
                    l.Insert(0, JsonNode.Parse(body)!.AsObject());
                    return Json(HttpStatusCode.Created, "{}");
                }
                return Json(HttpStatusCode.OK, new JsonArray(l.Select(s => (JsonNode)new JsonObject { ["state"] = s["state"]!.DeepClone(), ["description"] = s["description"]!.DeepClone() }).ToArray()).ToJsonString());
            }
            if (p.StartsWith("/repos/O/R/releases/tags/"))
            {
                return Releases.TryGetValue(Uri.UnescapeDataString(p["/repos/O/R/releases/tags/".Length..]), out var rel)
                    ? Json(HttpStatusCode.OK, rel.ToJsonString())
                    : Json(HttpStatusCode.NotFound, "{\"message\":\"Not Found\"}");
            }
            // No list of Releases is served: GitHub's is one page in its own
            // order, so the agent finds the newest of a kind from the tags.
            const string mr = "/repos/O/R/git/matching-refs/tags/";
            if (p.StartsWith(mr))
            {
                var prefix = Uri.UnescapeDataString(p[mr.Length..]);
                return Json(HttpStatusCode.OK, new JsonArray(Releases.Keys.Concat(BareTags).Where(t => t.StartsWith(prefix, StringComparison.Ordinal))
                    .Select(t => (JsonNode)new JsonObject { ["ref"] = "refs/tags/" + t }).ToArray()).ToJsonString());
            }
            if (p.StartsWith("/repos/O/R/releases/assets/"))
            {
                if (r.Headers.Accept.ToString() != "application/octet-stream") return new HttpResponseMessage(HttpStatusCode.UnsupportedMediaType);
                var aid = long.Parse(p["/repos/O/R/releases/assets/".Length..]);
                Downloaded.Add(Names[aid]);
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(Files[aid]) };
            }
            return Json(HttpStatusCode.NotFound, $"{{\"message\":\"no such path in the stand-in: {p}\"}}");
        }
    }
}

// ---- a stand-in signer ------------------------------------------------------

/// <summary>"Signs" a catalog by holding the sha256 of the one file it covers,
/// so a manifest changed after signing does not hold.</summary>
sealed class FakeVerifier(bool badFile = false) : IVerifier
{
    public void Catalog(string cat, string dir)
    {
        var want = System.IO.File.ReadAllText(cat);
        var files = Directory.GetFiles(dir);
        if (files.Length != 1) throw new SignatureException($"the catalog covers one file and the folder has {files.Length}");
        if (ReleaseFetch.FileSha256(files[0]) != want) throw new SignatureException("the catalog does not hold the files as they are");
    }

    public void File(string path)
    {
        if (badFile) throw new SignatureException("the signature is NotSigned");
    }
}

// ---- a stand-in game server ------------------------------------------------

/// <summary>A server folder and an engine that, like the real one, loads
/// gamemode.js again when it changes and says how it went in server.log. A
/// change is new bytes or a new write time, as the engine's watcher sees a
/// file put over it (chokidar compares what stat gives). A gamemode that reads
/// tables (#5191), one carrying the line that names them, logs the tree of
/// the gamemode-tables folder it read; one from before #5191 logs no tree,
/// whatever folder sits beside it. A gamemode, or a table, holding BROKEN
/// does not load.</summary>
sealed class FakeServer : IDisposable
{
    public const string EngineSays = "[thornswood] gamemode did not load; the error is above";
    public readonly string Root;
    public volatile bool Healthy = true;
    /// <summary>Whether the process runs: a stopped server loads nothing.</summary>
    public volatile bool Running = true;
    readonly CancellationTokenSource stop = new();
    readonly Task engine;
    readonly object looked = new();
    long looks;

    public FakeServer(int port)
    {
        Root = Directory.CreateTempSubdirectory("tw-server-").FullName;
        Directory.CreateDirectory(Path.Combine(Root, "dist_back"));
        Directory.CreateDirectory(Path.Combine(Root, "data"));
        File.WriteAllText(Path.Combine(Root, "dist_back", "skymp5-server.js"), $"console.log('{EngineSays}')");
        File.WriteAllText(Path.Combine(Root, "server-settings.json"), $"{{\"port\":{port},\"dataDir\":\"data\"}}");
        File.WriteAllText(Path.Combine(Root, "gamemode.js"), "// old gamemode\r\n");
        File.WriteAllText(Path.Combine(Root, "thornswood-build.json"), "{\"commit\":\"old\"}");
        File.WriteAllText(Path.Combine(Root, "server.log"), "started\n");
        engine = Task.Run(Engine);
    }

    /// <summary>Asked at each health request: true answers 503. A test that
    /// needs a server sick only after a load says so here, from what is on
    /// disk, rather than flipping Healthy from a task of its own, which a
    /// 15.6 ms timer tick on Windows let the agent's health check overtake.</summary>
    public Func<bool>? SickWhen { get; set; }

    public HttpResponseMessage Health(HttpRequestMessage r) =>
        new(Healthy && !(SickWhen?.Invoke() ?? false) ? HttpStatusCode.OK : HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") };

    /// <summary>What a load says in server.log, as the gamemode says it.</summary>
    string LoadLines(string gm, byte[] b)
    {
        var dir = Path.Combine(Root, Tables.Dir);
        var reads = Encoding.UTF8.GetString(b).Contains(Tables.TreeSaid);
        var broken = Encoding.UTF8.GetString(b).Contains("BROKEN") ||
                     (reads && Directory.Exists(dir) && Directory.GetFiles(dir).Any(f => File.ReadAllText(f).Contains("BROKEN")));
        if (broken) return $"SyntaxError: Unexpected token at 10.1.2.3:7787\n{EngineSays}\n";
        var tree = reads ? Tables.Tree(dir) : "";
        return $"[thornswood] gamemode.js is git blob {Thornswood.DeployAgent.Files.GamemodeBlob(gm)}, {b.Length} bytes\n" +
               (tree != "" ? $"[thornswood] gamemode tables are git tree {tree}, {Tables.Count(dir)} files, in {dir}\n" : "") +
               "[thornswood] gamemode client scripts abc (3), changed since the last load\n";
    }

    async Task Engine()
    {
        var gm = Path.Combine(Root, "gamemode.js");
        var last = Thornswood.DeployAgent.Files.ReadShared(gm);
        var lastWrite = File.GetLastWriteTimeUtc(gm);
        while (!stop.IsCancellationRequested)
        {
            try { await Task.Delay(5, stop.Token); } catch (OperationCanceledException) { return; }
            try { Look(); } finally { Looked(); }
        }

        void Look()
        {
            if (!Running) { try { last = Thornswood.DeployAgent.Files.ReadShared(gm); lastWrite = File.GetLastWriteTimeUtc(gm); } catch (IOException) { } return; }
            byte[] b;
            DateTime w;
            try { b = Thornswood.DeployAgent.Files.ReadShared(gm); w = File.GetLastWriteTimeUtc(gm); } catch (IOException) { return; }
            if (b.AsSpan().SequenceEqual(last) && w == lastWrite) return;
            last = b;
            lastWrite = w;
            try { File.AppendAllText(Path.Combine(Root, "server.log"), LoadLines(gm, b)); } catch (IOException) { }
        }
    }

    void Looked() { lock (looked) { looks++; Monitor.PulseAll(looked); } }

    /// <summary>Puts a gamemode.js in place the way a test sets the scene, and
    /// returns once the engine has loaded it, so its load lines are written
    /// before the agent marks server.log. Without this the engine (a 5 ms
    /// poll, a 15.6 ms timer tick on Windows) could notice the scene's
    /// gamemode after the agent's mark, and its lines were read as the
    /// deploy's load: same blob, old tables (the gate failures of 1 Nov).</summary>
    public void WriteGamemode(string text)
    {
        long from;
        lock (looked) from = looks;
        File.WriteAllText(Path.Combine(Root, "gamemode.js"), text);
        // The look in hand may have read the file before the write; the one
        // after it began after the write, so two looks on is past it.
        lock (looked)
        {
            while (looks < from + 2)
                if (!Monitor.Wait(looked, TimeSpan.FromSeconds(30))) throw new TimeoutException("the stand-in engine stopped looking");
        }
    }

    public string Read(string rel) => File.ReadAllText(Path.Combine(Root, rel));

    /// <summary>The task started: an engine holding WONTSTART never answers;
    /// any other loads the gamemode there and says so, as a start does.</summary>
    public void Start()
    {
        if (Read(Path.Combine("dist_back", "skymp5-server.js")).Contains("WONTSTART")) return;
        var gm = Path.Combine(Root, "gamemode.js");
        File.AppendAllText(Path.Combine(Root, "server.log"), "server started\n" + LoadLines(gm, File.ReadAllBytes(gm)));
        Running = true;
    }

    public void Dispose()
    {
        stop.Cancel();
        try { engine.Wait(); } catch (AggregateException) { }
        try { Directory.Delete(Root, true); } catch (IOException) { }
    }
}

/// <summary>Stops and starts the stand-in server the way the box's task and
/// its UDP port would, and counts what it was asked.</summary>
sealed class FakeControl(FakeServer s) : IServerControl
{
    public int Stops, Starts;
    public List<int> UdpHolders(int port) => s.Running ? [4242] : [];
    public List<string> Stop(string task, IReadOnlyList<int> pids, TimeSpan within) { Stops++; s.Running = false; return []; }
    public void Start(string task) { Starts++; s.Start(); }
    public bool TcpAnswers(int port) => s.Running;
}

public sealed class AgentTests : IDisposable
{
    const string Commit = "0123456789abcdef0123456789abcdef01234567";
    readonly List<string> temp = new();
    readonly List<IDisposable> owned = new();
    readonly List<string> said = new();

    string Temp()
    {
        var d = Directory.CreateTempSubdirectory("tw-agent-").FullName;
        temp.Add(d);
        return d;
    }

    public void Dispose()
    {
        foreach (var o in owned) o.Dispose();
        foreach (var d in temp)
        {
            // git writes its object files read only, and Windows will not
            // delete a read-only file (TablesTreeIsGitsTreeId makes a repository).
            foreach (var f in Directory.EnumerateFiles(d, "*", SearchOption.AllDirectories))
                File.SetAttributes(f, File.GetAttributes(f) & ~FileAttributes.ReadOnly);
            try { Directory.Delete(d, true); } catch (IOException) { }
        }
    }

    static string Sha(byte[] b) => Convert.ToHexStringLower(SHA256.HashData(b));
    static byte[] B(string s) => Encoding.UTF8.GetBytes(s);

    /// <summary>A Release's files: the part files, manifest.json and its stand-in catalog.</summary>
    static Dictionary<string, byte[]> ReleaseFiles(string tag, string commit, string version, Dictionary<string, Dictionary<string, byte[]>> parts)
    {
        var m = new Manifest { Schema = 1, Repo = "O/R", Commit = commit, Tag = tag, Version = version };
        var outFiles = new Dictionary<string, byte[]>();
        foreach (var (part, files) in parts)
        {
            m.Parts[part] = files.Select(kv => new ManifestFile { Name = kv.Key, Sha256 = Sha(kv.Value), Size = kv.Value.Length }).ToList();
            foreach (var (n, b) in files) outFiles[n] = b;
        }
        var mb = JsonSerializer.SerializeToUtf8Bytes(m);
        outFiles["manifest.json"] = mb;
        outFiles["manifest.cat"] = B(Sha(mb));
        return outFiles;
    }

    static void GamemodeRelease(FakeGitHub gh, string tag, string body, Dictionary<string, string>? tables = null)
    {
        var part = new Dictionary<string, byte[]> { ["gamemode.js"] = B(body), ["thornswood-build.json"] = B("{\"commit\":\"new\"}") };
        if (tables != null) part[Tables.Zip] = TablesZip(tables);
        gh.AddRelease(tag, ReleaseFiles(tag, Commit, "", new() { ["gamemode"] = part, ["launcher"] = new() { ["Thornswood.exe"] = B("MZ") } }));
    }

    /// <summary>gamemode-tables.zip as the release workflow makes it: each table at the top.</summary>
    static byte[] TablesZip(Dictionary<string, string> tables)
    {
        using var ms = new MemoryStream();
        using (var za = new ZipArchive(ms, ZipArchiveMode.Create, true))
            foreach (var (n, t) in tables)
                using (var e = za.CreateEntry(n).Open()) e.Write(B(t));
        return ms.ToArray();
    }

    /// <summary>The Deployment's states, oldest first (or only its last one).
    /// When they are not the ones wanted, the failure carries the last
    /// description and the deploy log, so a run on the gate says why and not
    /// only that (1 Nov: a failure on the Windows gate gave "Expected success,
    /// Actual failure" and nothing more).</summary>
    static void HasStates(FakeGitHub gh, FakeServer s, long id, string want, bool last = false)
    {
        var got = last ? (string)gh.Last(id)!["state"]! : string.Join(",", gh.States(id));
        if (got == want) return;
        var log = Path.Combine(s.Root, "data", $"deploy-{id}.log");
        var said = (string?)gh.Last(id)?["description"] ?? "(no status)";
        Assert.Fail($"Deployment {id}: expected {want}, got {got}: {said}\n" + (File.Exists(log) ? File.ReadAllText(log) : "(no deploy log)"));
    }

    static void PutTables(FakeServer s, Dictionary<string, string> tables)
    {
        var d = Path.Combine(s.Root, Tables.Dir);
        Directory.CreateDirectory(d);
        foreach (var (n, t) in tables) File.WriteAllText(Path.Combine(d, n), t);
    }

    (Agent agent, FakeGitHub gh, FakeServer srv, Server server, Config cfg) Make(int port = 7787, IVerifier? v = null)
    {
        var gh = new FakeGitHub();
        var s = new FakeServer(port);
        owned.Add(s);
        gh.Other = s.Health;
        var http = new HttpClient(gh);
        var home = Temp();
        var env = Config.DefaultDev();
        env.Root = s.Root;
        env.Turn = Temp();
        env.Store = Path.Combine(home, "store");
        env.Health = "https://health.test/api/servers/thornswood/manifest.json";
        env.LogBase = "http://box.test:7788/";
        env.LoadSeconds = 10;
        env.TurnSeconds = 10;
        var cfg = new Config { Repo = "O/R", Api = FakeGitHub.Api, Home = home, Environments = { ["dev"] = env } };
        env.Watch = Temp();
        env.StartSeconds = 2;
        var server = new Server(env, http) { Tick = TimeSpan.FromMilliseconds(5), Control = new FakeControl(s) };
        var gh2 = new GitHub(FakeGitHub.Api, "O/R", new StaticToken("t"), http);
        var a = new Agent(cfg, gh2, v ?? new FakeVerifier(), new() { ["dev"] = server }, "1.0.0", "", l => { lock (said) said.Add(l); }) { Host = "box" };
        return (a, gh, s, server, cfg);
    }


    // ---- a new server build (an engine pin) ---------------------------------

    const string ForkA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const string ForkB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    /// <summary>A server build: its fork files and the record of them, the
    /// way records/server-build.json writes it.</summary>
    static (Dictionary<string, byte[]> files, byte[] record) Build(string fork, string engineExtra = "", string[]? scripts = null, string? lie = null)
    {
        var files = new Dictionary<string, byte[]>
        {
            ["scam_native.node"] = B("native " + fork),
            ["dist_back/skymp5-server.js"] = B($"console.log('{FakeServer.EngineSays}') // {fork} {engineExtra}"),
            ["dist_back/skymp5-server.js.map"] = B("map " + fork),
            ["package.json"] = B("{}"),
            ["yarn.lock"] = B("lock"),
            ["launch_server.bat"] = B("node dist_back/skymp5-server.js"),
        };
        foreach (var n in scripts ?? ["Actor.pex"]) files["data/scripts/" + n] = B("pex " + n + fork);
        var rec = new JsonObject
        {
            ["binary"] = "scam_native.node",
            ["sha256"] = Sha(files["scam_native.node"]),
            ["source"] = new JsonObject { ["commit"] = fork },
            ["files"] = new JsonObject(files.Select(kv => KeyValuePair.Create(kv.Key, (JsonNode?)new JsonObject
            {
                ["sha256"] = lie != null && kv.Key == lie ? new string('0', 64) : Sha(kv.Value),
                ["bytes"] = kv.Value.Length,
                ["commit"] = fork,
            }))),
        };
        return (files, B(rec.ToJsonString(new JsonSerializerOptions { WriteIndented = true }).Replace("\r\n", "\n")));
    }

    static byte[] Zip(Dictionary<string, byte[]> files, byte[] record)
    {
        using var ms = new MemoryStream();
        using (var za = new System.IO.Compression.ZipArchive(ms, System.IO.Compression.ZipArchiveMode.Create, true))
        {
            foreach (var (n, b) in files.Append(KeyValuePair.Create("server-build.json", record)).OrderBy(kv => kv.Key, StringComparer.Ordinal))
            {
                using var e = za.CreateEntry(n, System.IO.Compression.CompressionLevel.NoCompression).Open();
                e.Write(b);
            }
        }
        return ms.ToArray();
    }

    /// <summary>Puts a server build into the stand-in's folder as if a deploy had.</summary>
    static void Install(FakeServer s, Dictionary<string, byte[]> files, byte[] record)
    {
        foreach (var (rel, b) in files)
        {
            var p = Path.Combine(s.Root, rel);
            Directory.CreateDirectory(Path.GetDirectoryName(p)!);
            File.WriteAllBytes(p, b);
        }
        File.WriteAllBytes(Path.Combine(s.Root, "server-build.json"), record);
    }

    static void PinRelease(FakeGitHub gh, string tag, string gamemode, Dictionary<string, byte[]> files, byte[] record, byte[]? zip = null,
        Dictionary<string, string>? tables = null)
    {
        var zipName = "server-" + Sha(record)[..12] + "-" + Sha(zip ?? Zip(files, record))[..16] + ".zip";
        var part = new Dictionary<string, byte[]> { ["gamemode.js"] = B(gamemode), ["thornswood-build.json"] = B("{\"commit\":\"new\"}") };
        if (tables != null) part[Tables.Zip] = TablesZip(tables);
        gh.AddRelease(tag, ReleaseFiles(tag, Commit, "", new()
        {
            ["gamemode"] = part,
            ["server"] = new() { ["server-build.json"] = record, [zipName] = zip ?? Zip(files, record) },
        }));
    }

    [Fact]
    public async Task AnEnginePinSwapsTheServerWithTheGamemodeUnderAHold()
    {
        var (a, gh, s, _, cfg) = Make();
        var (oldFiles, oldRec) = Build(ForkA, scripts: ["Actor.pex", "Gone.pex"]);
        Install(s, oldFiles, oldRec);
        var (newFiles, newRec) = Build(ForkB);
        PinRelease(gh, "build-7", "// gamemode for B\n", newFiles, newRec);
        File.WriteAllText(Path.Combine(s.Root, "data", "restart.json"), "{}");
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-7\"}");
        await a.Pass("dev", default);
        var last = gh.Last(id)!;
        Assert.Equal("success", (string)last["state"]!);
        Assert.Contains("server build bbbbbbbbbbbb", (string)last["description"]!);
        Assert.True(s.Running);
        foreach (var (rel, b) in newFiles) Assert.Equal(Sha(b), Sha(File.ReadAllBytes(Path.Combine(s.Root, rel))));
        Assert.Equal(newRec, File.ReadAllBytes(Path.Combine(s.Root, "server-build.json")));
        Assert.Equal("// gamemode for B\n", s.Read("gamemode.js"));
        Assert.False(File.Exists(Path.Combine(s.Root, "data", "scripts", "Gone.pex")), "a fork file of the old build was left beside the new one");
        Assert.False(File.Exists(Path.Combine(s.Root, "data", "restart.json")), "a restart.json the old process never read was left for the new one");
        var prev = Assert.Single(Directory.GetDirectories(s.Root, ".prev-*"));
        Assert.Equal(oldRec, File.ReadAllBytes(Path.Combine(prev, "server-build.json")));
        Assert.True(File.Exists(Path.Combine(prev, "data", "scripts", "Gone.pex")));
        Assert.Empty(Directory.GetDirectories(s.Root, ".agent-stage-*"));
        var log = s.Read(Path.Combine("data", $"deploy-{id}.log"));
        Assert.Contains("held Thornswood Dev Server", log);
        Assert.Contains("the hold on Thornswood Dev Server is taken away", log);
        Assert.Empty(Directory.GetFiles(Path.Combine(cfg.Environments["dev"].Watch, "holds")));
        Assert.Contains("server-", string.Join(",", gh.Downloaded));
    }

    [Fact]
    public async Task TheSameServerBuildIsNotFetchedAndOnlyTheGamemodeReloads()
    {
        var (a, gh, s, server, _) = Make();
        var (files, rec) = Build(ForkA);
        Install(s, files, rec);
        // The box's copy was checked out with CR LF: the same record.
        File.WriteAllText(Path.Combine(s.Root, "server-build.json"), Encoding.UTF8.GetString(rec).Replace("\n", "\r\n"));
        PinRelease(gh, "build-8", "// only the gamemode\n", files, rec);
        Assert.Equal("success", (await a.DeployTag("dev", "build-8", default)).State);
        Assert.Equal("// only the gamemode\n", s.Read("gamemode.js"));
        var ctl = (FakeControl)server.Control;
        Assert.Equal((0, 0), (ctl.Stops, ctl.Starts));
        Assert.DoesNotContain(gh.Downloaded, n => n.EndsWith(".zip"));
    }

    [Fact]
    public async Task ANewEngineThatDoesNotStartIsPutBackAndTheOldOneStarted()
    {
        var (a, gh, s, server, _) = Make();
        var (oldFiles, oldRec) = Build(ForkA);
        Install(s, oldFiles, oldRec);
        var (newFiles, newRec) = Build(ForkB, engineExtra: "WONTSTART");
        PinRelease(gh, "build-9", "// gamemode for B\n", newFiles, newRec);
        var outc = await a.DeployTag("dev", "build-9", default);
        Assert.Equal("failure", outc.State);
        Assert.Contains("previous server build is back", outc.Summary);
        Assert.True(s.Running);
        Assert.Equal(oldRec, File.ReadAllBytes(Path.Combine(s.Root, "server-build.json")));
        Assert.Equal(Sha(oldFiles["dist_back/skymp5-server.js"]), Sha(File.ReadAllBytes(Path.Combine(s.Root, "dist_back", "skymp5-server.js"))));
        Assert.Equal("// old gamemode\r\n", s.Read("gamemode.js"));
        Assert.Equal((2, 2), (((FakeControl)server.Control).Stops, ((FakeControl)server.Control).Starts));
        Assert.Empty(Directory.GetDirectories(s.Root, ".prev-*"));
        Assert.Empty(Directory.GetDirectories(s.Root, ".agent-stage-*"));
    }

    [Fact]
    public async Task AGamemodeThatDoesNotLoadOnTheNewEngineIsPutBackWithIt()
    {
        var (a, gh, s, _, _) = Make();
        var (oldFiles, oldRec) = Build(ForkA);
        Install(s, oldFiles, oldRec);
        var (newFiles, newRec) = Build(ForkB);
        PinRelease(gh, "build-10", "BROKEN gamemode\n", newFiles, newRec);
        var outc = await a.DeployTag("dev", "build-10", default);
        Assert.Equal("failure", outc.State);
        Assert.Contains("did not take", outc.Summary);
        Assert.Equal(oldRec, File.ReadAllBytes(Path.Combine(s.Root, "server-build.json")));
        Assert.Equal("// old gamemode\r\n", s.Read("gamemode.js"));
    }

    [Fact]
    public async Task AnEnginePinSwapsTheTablesWithTheServerAndPutsThemBack()
    {
        var (a, gh, s, _, _) = Make();
        var (oldFiles, oldRec) = Build(ForkA);
        Install(s, oldFiles, oldRec);
        PutTables(s, OldTables);
        var oldTree = Tables.Tree(Path.Combine(s.Root, Tables.Dir));
        var (newFiles, newRec) = Build(ForkB);
        PinRelease(gh, "build-11", Reading("gamemode for B"), newFiles, newRec, tables: new() { ["DATA.json"] = "{\"a\":3}\n" });
        var outc = await a.DeployTag("dev", "build-11", default);
        Assert.Equal("success", outc.State);
        Assert.Contains("with tables tree", outc.Summary);
        Assert.Equal(new[] { "DATA.json" }, Directory.GetFiles(Path.Combine(s.Root, Tables.Dir)).Select(Path.GetFileName).ToArray());
        var prev = Assert.Single(Directory.GetDirectories(s.Root, ".prev-*"));
        Assert.Equal(oldTree, Tables.Tree(Path.Combine(prev, Tables.Dir)));

        // A table that stops the load on the new engine goes back with it.
        var (b2Files, b2Rec) = Build(ForkA);
        var before = Tables.Tree(Path.Combine(s.Root, Tables.Dir));
        PinRelease(gh, "build-12", Reading("gamemode for A"), b2Files, b2Rec, tables: new() { ["DATA.json"] = "BROKEN\n" });
        var bad = await a.DeployTag("dev", "build-12", default);
        Assert.Equal("failure", bad.State);
        Assert.Equal(before, Tables.Tree(Path.Combine(s.Root, Tables.Dir)));
        Assert.Equal(newRec, File.ReadAllBytes(Path.Combine(s.Root, "server-build.json")));
        Assert.True(s.Running);
    }

    [Theory]
    [InlineData("a file is not its record", "lie", "is not the build server-build.json records")]
    [InlineData("the zip's record is another", "otherzip", "not the one the signed manifest names")]
    [InlineData("no task named", "notask", "no scheduled task is named")]
    public async Task AServerBuildIsRefusedBeforeAnythingStops(string name, string how, string want)
    {
        _ = name;
        var (a, gh, s, server, cfg) = Make();
        var (oldFiles, oldRec) = Build(ForkA);
        Install(s, oldFiles, oldRec);
        var (newFiles, newRec) = Build(ForkB, lie: how == "lie" ? "yarn.lock" : null);
        byte[]? zip = null;
        if (how == "otherzip") zip = Zip(newFiles, Build(ForkB, engineExtra: "x").record);
        if (how == "notask") cfg.Environments["dev"].Task = "";
        PinRelease(gh, "build-11", "// gamemode for B\n", newFiles, newRec, zip);
        var outc = await a.DeployTag("dev", "build-11", default);
        Assert.Equal("failure", outc.State);
        Assert.Contains(want, outc.Summary);
        Assert.Equal((0, 0), (((FakeControl)server.Control).Stops, ((FakeControl)server.Control).Starts));
        Assert.Equal(oldRec, File.ReadAllBytes(Path.Combine(s.Root, "server-build.json")));
        Assert.Empty(Directory.GetDirectories(s.Root, ".agent-stage-*"));
    }

    [Fact]
    public void RecordSumReadsCrLfAsLf()
    {
        Assert.Equal(ServerBuild.RecordSum(B("{\n\"a\": 1\n}\n")), ServerBuild.RecordSum(B("{\r\n\"a\": 1\r\n}\r\n")));
        Assert.NotEqual(ServerBuild.RecordSum(B("{\"a\": 1}")), ServerBuild.RecordSum(B("{\"a\": 2}")));
    }

    [Fact]
    public async Task AppliesAGamemodeByReload()
    {
        var (a, gh, s, _, _) = Make();
        GamemodeRelease(gh, "build-1", "// new gamemode\n");
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-1\"}");
        await a.Pass("dev", default);
        HasStates(gh, s, id, "in_progress,success");
        Assert.Equal("// new gamemode\n", s.Read("gamemode.js"));
        Assert.Equal("{\"commit\":\"new\"}", s.Read("thornswood-build.json"));
        var rec = JsonSerializer.Deserialize<DeployRecord>(s.Read(Path.Combine("data", "thornswood-deploy.json")))!;
        Assert.Equal(("build-1", Commit, "gamemode"), (rec.Name, rec.Commit, rec.Component));
        Assert.EndsWith($"/deploy-{id}.log", (string)gh.Last(id)!["log_url"]!);
        Assert.Contains("launcher, which this agent does not apply yet", s.Read(Path.Combine("data", $"deploy-{id}.log")));
        var prevs = Directory.GetDirectories(s.Root, ".prev-*");
        Assert.Single(prevs);
        Assert.Equal("// old gamemode\r\n", File.ReadAllText(Path.Combine(prevs[0], "gamemode.js")));
        Assert.Empty(Directory.GetDirectories(s.Root, ".agent-stage-*"));
        // Applied once: the next pass sees its status and does nothing.
        await a.Pass("dev", default);
        Assert.Equal(2, gh.States(id).Count);
    }

    // ---- voice, with dev's Deployment (#5187) -------------------------------

    static readonly Dictionary<string, string> OldVoice = new()
    {
        ["voice-server.js"] = "const BUILD = 'old-1';\n", ["headlines.js"] = "// headlines\n", ["server-log.js"] = "// log writer\n",
        ["token-key.txt"] = "the service's own key",
    };

    /// <summary>Dev with its voice service beside it, running OldVoice.</summary>
    (Agent agent, FakeGitHub gh, FakeServer srv, FakeAppControl voice, string voiceRoot) MakeWithVoice()
    {
        var (a, gh, s, _, cfg) = Make();
        var vroot = Temp();
        foreach (var (n, t) in OldVoice) File.WriteAllText(Path.Combine(vroot, n), t);
        var vc = new FakeAppControl(vroot);
        var venv = Config.DefaultDevVoice();
        venv.Root = vroot;
        venv.Store = cfg.Environments["dev"].Store;
        venv.Watch = cfg.Environments["dev"].Watch;
        venv.Health = "https://voice.test/health";
        venv.WaitSeconds = 1;
        vc.Start(venv);
        var server = gh.Other!;
        gh.Other = r => r.RequestUri!.Host == "voice.test" ? vc.Health(r) : server(r);
        a.Voices["dev"] = new App(venv, new HttpClient(gh), vc) { Tick = TimeSpan.FromMilliseconds(5) };
        return (a, gh, s, vc, vroot);
    }

    static void VoiceRelease(FakeGitHub gh, string tag, string gamemode, string voiceServer)
    {
        var voice = TablesZip(new() { ["headlines.js"] = "// headlines\n", ["server-log.js"] = "// log writer\n", ["voice-server.js"] = voiceServer });
        gh.AddRelease(tag, ReleaseFiles(tag, Commit, "", new()
        {
            ["gamemode"] = new() { ["gamemode.js"] = B(gamemode), ["thornswood-build.json"] = B("{\"commit\":\"new\"}") },
            ["voice"] = new() { ["voice.zip"] = voice },
        }));
    }

    [Fact]
    public async Task VoiceGoesInWithDevsDeploymentAndAnswersWithItsNewBuild()
    {
        var (a, gh, s, vc, vroot) = MakeWithVoice();
        VoiceRelease(gh, "build-21", "// new gamemode\n", "const BUILD = 'new-2';\n");
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-21\"}");
        await a.Pass("dev", default);
        HasStates(gh, s, id, "in_progress,success");
        Assert.Contains("voice runs it too", (string)gh.Last(id)!["description"]!);
        Assert.Equal("const BUILD = 'new-2';\n", File.ReadAllText(Path.Combine(vroot, "voice-server.js")));
        Assert.Equal("new-2", vc.RunningBuild);
        Assert.Equal("the service's own key", File.ReadAllText(Path.Combine(vroot, "token-key.txt")));
        Assert.Equal("// new gamemode\n", s.Read("gamemode.js"));
        Assert.Contains("voice-server.js", vc.Parsed);
        var rec = JsonSerializer.Deserialize<DeployRecord>(File.ReadAllText(Path.Combine(vroot, "thornswood-deploy.json")))!;
        Assert.Equal(("build-21", Commit, "voice"), (rec.Name, rec.Commit, rec.Component));
        var log = s.Read(Path.Combine("data", $"deploy-{id}.log"));
        Assert.Contains("voice first", log);
        Assert.DoesNotContain("voice, which this agent does not apply yet", log);
    }

    [Fact]
    public async Task AVoiceThatKeepsAnsweringWithTheOldBuildIsPutBackAndTheGamemodeIsNotTouched()
    {
        var (a, gh, s, vc, vroot) = MakeWithVoice();
        VoiceRelease(gh, "build-22", "// new gamemode\n", "const BUILD = 'new-3'; // DEAD\n");
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-22\"}");
        await a.Pass("dev", default);
        HasStates(gh, s, id, "in_progress,failure");
        var why = (string)gh.Last(id)!["description"]!;
        Assert.StartsWith("voice: ", why);
        Assert.Equal("const BUILD = 'old-1';\n", File.ReadAllText(Path.Combine(vroot, "voice-server.js")));
        Assert.Equal("old-1", vc.RunningBuild);
        Assert.Equal("// old gamemode\r\n", s.Read("gamemode.js"));
        Assert.Contains("says build old-1, not the new-3 in the folder", s.Read(Path.Combine("data", $"deploy-{id}.log")));
    }

    [Fact]
    public async Task AReleaseWithVoiceOnABoxWithNoVoiceNamedLeavesItAlone()
    {
        var (a, gh, s, _, _) = Make();
        VoiceRelease(gh, "build-23", "// new gamemode\n", "const BUILD = 'new-4';\n");
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-23\"}");
        await a.Pass("dev", default);
        HasStates(gh, s, id, "in_progress,success");
        Assert.Contains("voice, which this agent does not apply yet; left alone", s.Read(Path.Combine("data", $"deploy-{id}.log")));
        Assert.DoesNotContain("voice.zip", gh.Downloaded);
    }

    // ---- the gamemode's tables (#5191) --------------------------------------

    static readonly Dictionary<string, string> OldTables = new() { ["DATA.json"] = "{\n\"a\":1\n}\n", ["WELLS.json"] = "[]\n" };

    /// <summary>A gamemode that reads its tables, as game/gamemode.js does from #5191.</summary>
    static string Reading(string name) => $"// {name}\nlog('{Tables.TreeSaid}' + t.tree);\n";

    [Fact]
    public async Task ATablesOnlyChangeIsReloadedAndHeldToItsTree()
    {
        var (a, gh, s, _, _) = Make();
        PutTables(s, OldTables);
        s.WriteGamemode(Reading("tables gamemode"));
        var oldTree = Tables.Tree(Path.Combine(s.Root, Tables.Dir));
        // The same gamemode.js the server runs: only a table changed.
        GamemodeRelease(gh, "build-1", Reading("tables gamemode"), new() { ["DATA.json"] = "{\n\"a\":2\n}\n", ["WELLS.json"] = "[]\n" });
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-1\"}");
        await a.Pass("dev", default);
        HasStates(gh, s, id, "in_progress,success");
        Assert.Equal("{\n\"a\":2\n}\n", s.Read(Path.Combine(Tables.Dir, "DATA.json")));
        var newTree = Tables.Tree(Path.Combine(s.Root, Tables.Dir));
        Assert.NotEqual(oldTree, newTree);
        Assert.Contains($"with tables tree {newTree[..12]}", (string)gh.Last(id)!["description"]!);
        var log = s.Read(Path.Combine("data", $"deploy-{id}.log"));
        Assert.Contains($"gamemode tables are git tree {newTree}", log);
        var prevs = Directory.GetDirectories(s.Root, ".prev-*");
        Assert.Single(prevs);
        Assert.Equal("{\n\"a\":1\n}\n", File.ReadAllText(Path.Combine(prevs[0], Tables.Dir, "DATA.json")));
        Assert.Empty(Directory.GetDirectories(s.Root, ".agent-stage-*"));
        Assert.Equal(2 + 2, JsonSerializer.Deserialize<DeployRecord>(s.Read(Path.Combine("data", "thornswood-deploy.json")))!.Files);
    }

    [Fact]
    public async Task ATableThatStopsTheLoadIsPutBackWithTheOldTables()
    {
        var (a, gh, s, _, _) = Make();
        PutTables(s, OldTables);
        // The old gamemode reads tables too, so its load after the put-back
        // reads the folder, which has to be the old one by then.
        s.WriteGamemode(Reading("old tables gamemode"));
        var oldTree = Tables.Tree(Path.Combine(s.Root, Tables.Dir));
        GamemodeRelease(gh, "build-2", Reading("new gamemode"), new() { ["DATA.json"] = "BROKEN\n", ["WELLS.json"] = "[]\n" });
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-2\"}");
        await a.Pass("dev", default);
        var last = gh.Last(id)!;
        Assert.Equal("failure", (string)last["state"]!);
        Assert.Contains("previous gamemode is back", (string)last["description"]!);
        Assert.Equal(Reading("old tables gamemode"), s.Read("gamemode.js"));
        Assert.Equal(oldTree, Tables.Tree(Path.Combine(s.Root, Tables.Dir)));
        Assert.Empty(Directory.GetDirectories(s.Root, ".agent-stage-*"));
    }

    [Fact]
    public async Task AReleaseFromBeforeTheTablesLeavesTheFolderAlone()
    {
        var (a, gh, s, _, _) = Make();
        PutTables(s, OldTables);
        var tree = Tables.Tree(Path.Combine(s.Root, Tables.Dir));
        GamemodeRelease(gh, "build-0", "// a gamemode with its tables inside\n");
        Assert.Equal("success", (await a.DeployTag("dev", "build-0", default)).State);
        Assert.Equal(tree, Tables.Tree(Path.Combine(s.Root, Tables.Dir)));
    }

    [Fact]
    public async Task ARollBackAcrossTheTablesLoadsTheOldGamemodeBesideTheFolder()
    {
        var (a, gh, s, _, _) = Make();
        GamemodeRelease(gh, "build-20", "// a gamemode with its tables inside\n");
        GamemodeRelease(gh, "build-21", Reading("tables gamemode"), OldTables);
        Assert.Equal("success", (await a.DeployTag("dev", "build-21", default)).State);
        Assert.True(Directory.Exists(Path.Combine(s.Root, Tables.Dir)));
        // Back to a Release from before #5191: it logs no tree and is not held to one.
        var back = await a.DeployTag("dev", "build-20", default);
        Assert.Equal("success", back.State);
        Assert.Equal("// a gamemode with its tables inside\n", s.Read("gamemode.js"));
    }

    [Fact]
    public async Task APutBackToAGamemodeFromBeforeTheTablesIsNotHeldToTheFolder()
    {
        var (a, gh, s, _, _) = Make();
        // A gamemode from before #5191 runs beside a folder a later one left.
        PutTables(s, OldTables);
        var tree = Tables.Tree(Path.Combine(s.Root, Tables.Dir));
        GamemodeRelease(gh, "build-22", Reading("new gamemode"), new() { ["DATA.json"] = "BROKEN\n" });
        var outc = await a.DeployTag("dev", "build-22", default);
        Assert.True(outc.State == "failure", outc.State + ": " + outc.Summary);
        Assert.Contains("previous gamemode is back", outc.Summary);
        Assert.Equal("// old gamemode\r\n", s.Read("gamemode.js"));
        Assert.Equal(tree, Tables.Tree(Path.Combine(s.Root, Tables.Dir)));
    }

    [Fact]
    public void AGamemodeReadsTablesOnlyWhenItNamesThem()
    {
        var dir = Temp();
        var gm = Path.Combine(dir, "gamemode.js");
        File.WriteAllText(gm, "// a gamemode with its tables inside\n");
        Assert.False(Tables.Reads(gm));
        File.WriteAllText(gm, Reading("tables gamemode"));
        Assert.True(Tables.Reads(gm));
        Assert.False(Tables.Reads(Path.Combine(dir, "none.js")));
    }

    [Theory]
    [InlineData("sub/DATA.json")]
    [InlineData("../DATA.json")]
    [InlineData("data.json")]
    [InlineData("DATA.js")]
    public void ATablesZipWithAnythingButTablesIsRefused(string name)
    {
        var zip = Path.Combine(Temp(), Tables.Zip);
        File.WriteAllBytes(zip, TablesZip(new() { [name] = "{}" }));
        var e = Assert.Throws<InvalidDataException>(() => Tables.Expand(zip, Path.Combine(Temp(), "out")));
        Assert.Contains("not a table named like its constant", e.Message);
    }

    [Fact]
    public void TablesTreeIsGitsTreeId()
    {
        var dir = Temp();
        var t = Path.Combine(dir, Tables.Dir);
        Directory.CreateDirectory(t);
        File.WriteAllText(Path.Combine(t, "B_TABLE.json"), "[1]\n");
        File.WriteAllText(Path.Combine(t, "A.json"), "{}\n");
        File.WriteAllText(Path.Combine(t, "notes.txt"), "not a table\n");
        string Git(params string[] args)
        {
            var psi = new ProcessStartInfo("git", args) { RedirectStandardOutput = true, WorkingDirectory = dir };
            using var proc = Process.Start(psi)!;
            var o = proc.StandardOutput.ReadToEnd().Trim();
            proc.WaitForExit();
            return o;
        }
        string want;
        try
        {
            Git("init", "-q");
            Git("add", "--", Path.Combine(Tables.Dir, "A.json"), Path.Combine(Tables.Dir, "B_TABLE.json"));
            want = Git("write-tree", "--prefix=" + Tables.Dir + "/");
        }
        catch (System.ComponentModel.Win32Exception) { return; } // no git here
        Assert.Equal(want, Tables.Tree(t));
        Assert.Equal("", Tables.Tree(Path.Combine(dir, "none")));
        // An empty folder is git's empty tree, the id the gamemode works out for one too.
        var empty = Path.Combine(dir, "empty");
        Directory.CreateDirectory(empty);
        Assert.Equal("4b825dc642cb6eb9a060e54bf8d69288fbee4904", Tables.Tree(empty));
    }

    [Fact]
    public async Task TheGateVerbDeploysATagAndRollsBackToTheOneBefore()
    {
        var (a, gh, s, _, _) = Make();
        GamemodeRelease(gh, "build-1", "// first\n");
        GamemodeRelease(gh, "build-2", "// second\n");
        Assert.Equal("success", (await a.DeployTag("dev", "build-2", default)).State);
        Assert.Equal("// second\n", s.Read("gamemode.js"));
        // A rollback is the Release before, deployed the same way.
        Assert.Equal("success", (await a.DeployTag("dev", "build-1", default)).State);
        Assert.Equal("// first\n", s.Read("gamemode.js"));
        Assert.Equal("build-1", JsonSerializer.Deserialize<DeployRecord>(s.Read(Path.Combine("data", "thornswood-deploy.json")))!.Name);
        Assert.Equal(2, Directory.GetFiles(Path.Combine(s.Root, "data"), "deploy-build-*.log").Length);
        Assert.Equal("failure", (await a.DeployTag("main", "build-1", default)).State);
    }

    [Fact]
    public async Task AGamemodeThatDoesNotLoadIsPutBack()
    {
        var (a, gh, s, _, _) = Make();
        GamemodeRelease(gh, "build-2", "BROKEN gamemode\n");
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-2\"}");
        await a.Pass("dev", default);
        var last = gh.Last(id)!;
        Assert.Equal("failure", (string)last["state"]!);
        Assert.Contains("previous gamemode is back", (string)last["description"]!);
        Assert.Equal("// old gamemode\r\n", s.Read("gamemode.js"));
        var log = s.Read(Path.Combine("data", $"deploy-{id}.log"));
        Assert.DoesNotContain("10.1.2.3", log);
        Assert.Contains("<address>", log);
        Assert.False(File.Exists(Path.Combine(s.Root, "data", "thornswood-deploy.json")), "a record was written for a deploy that did not take");
    }

    [Fact]
    public async Task AFailedHealthCheckPutsTheOldOneBack()
    {
        var (a, gh, s, server, _) = Make();
        GamemodeRelease(gh, "build-3", "// new but sick\n");
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-3\"}");
        // Healthy for the check before, sick while the new gamemode is in.
        s.SickWhen = () => Encoding.UTF8.GetString(Thornswood.DeployAgent.Files.ReadShared(Path.Combine(s.Root, "gamemode.js"))).Contains("sick");
        server.Tick = TimeSpan.FromMilliseconds(20);
        await a.Pass("dev", default);
        var last = gh.Last(id)!;
        Assert.Equal("failure", (string)last["state"]!);
        Assert.Contains("health check failed", (string)last["description"]!);
        Assert.Equal("// old gamemode\r\n", s.Read("gamemode.js"));
    }

    [Theory]
    [InlineData("live port", "{\"release\":\"build-1\"}", Commit, 7777, false, false, "which is the live server")]
    [InlineData("commit differs", "{\"release\":\"build-1\"}", "ffffffffffffffffffffffffffffffffffffffff", 7787, false, false, "the Release is commit")]
    [InlineData("no release", "{\"release\":\"build-9\"}", Commit, 7787, false, false, "no published Release build-9")]
    [InlineData("not a build tag", "{\"release\":\"v1.2.3\"}", Commit, 7787, false, false, "not a build-")]
    [InlineData("manifest changed after signing", "{\"release\":\"build-1\"}", Commit, 7787, true, false, "the signature does not hold")]
    [InlineData("server not running", "{\"release\":\"build-1\"}", Commit, 7787, false, true, "reloads a running server only")]
    [InlineData("payload as a string", "\"{\\\"release\\\":\\\"build-9\\\"}\"", Commit, 7787, false, false, "no published Release build-9")]
    [InlineData("no payload", "{}", Commit, 7787, false, false, "no payload naming a Release")]
    public async Task Refusals(string name, string payload, string sha, int port, bool tamper, bool sick, string want)
    {
        _ = name;
        var (a, gh, s, _, _) = Make(port);
        GamemodeRelease(gh, "build-1", "// new gamemode\n");
        if (tamper)
        {
            var asset = gh.Releases["build-1"]["assets"]!.AsArray().First(x => (string)x!["name"]! == "manifest.json")!;
            var text = Encoding.UTF8.GetString(gh.Files[(long)asset["id"]!]);
            gh.Replace("build-1", "manifest.json", B(text.Replace("\"schema\":1", "\"schema\":1 ")));
        }
        if (sick) s.Healthy = false;
        var id = gh.AddDeployment("Dev", sha, payload);
        await a.Pass("dev", default);
        var last = gh.Last(id)!;
        Assert.Equal("failure", (string)last["state"]!);
        Assert.Contains(want, (string)last["description"]!);
        Assert.Equal("// old gamemode\r\n", s.Read("gamemode.js"));
    }

    [Fact]
    public async Task OnlyTheNewestIsAppliedAndOtherEnvironmentsAreLeftAlone()
    {
        var (a, gh, _, _, _) = Make();
        GamemodeRelease(gh, "build-1", "// new gamemode\n");
        var record = gh.AddDeployment("Dev server", Commit, "{}");
        var older = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-1\"}");
        var newest = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-1\"}");
        await a.Pass("dev", default);
        Assert.Equal("inactive", string.Join(",", gh.States(older)));
        Assert.Equal("in_progress,success", string.Join(",", gh.States(newest)));
        Assert.Empty(gh.States(record));
    }

    // Record-Deployment.ps1 wrote Deployments to Dev with a success straight
    // away (#5179 retired it). The newest of them is not applied again, and
    // the unapplied older ones under it are left as they are.
    [Fact]
    public async Task AnOldRecordWithASuccessIsNotAppliedAgain()
    {
        var (a, gh, s, _, _) = Make();
        GamemodeRelease(gh, "build-1", "// new gamemode\n");
        var before = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-1\"}");
        var record = gh.AddDeployment("Dev", Commit, "{}");
        lock (gh.StatusesById) gh.StatusesById[record] = new() { new JsonObject { ["state"] = "success", ["description"] = "Live on the dev feed" } };
        await a.Pass("dev", default);
        Assert.Equal("success", string.Join(",", gh.States(record)));
        Assert.Empty(gh.States(before));
        Assert.Equal("// old gamemode\r\n", s.Read("gamemode.js"));
    }

    [Fact]
    public async Task ADeploymentCutShortIsMarkedError()
    {
        var (a, gh, s, _, cfg) = Make();
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-1\"}");
        var state = Path.Combine(cfg.Home, "state", "working.json");
        Directory.CreateDirectory(Path.GetDirectoryName(state)!);
        File.WriteAllText(state, $"{{\"Deployment\":\"{id}\",\"Env\":\"dev\",\"Started\":\"then\"}}");
        await a.Start(default);
        HasStates(gh, s, id, "error", last: true);
        Assert.False(File.Exists(state));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task SelfUpdate(bool badSignature)
    {
        var (_, gh, _, server, cfg) = Make();
        var exe = Path.Combine(cfg.Home, "thornswood-agent.exe");
        File.WriteAllText(exe, "old program");
        var a = new Agent(cfg, new GitHub(FakeGitHub.Api, "O/R", new StaticToken("t"), new HttpClient(gh)), new FakeVerifier(badSignature),
            new() { ["dev"] = server }, "1.0.0", exe, _ => { });
        foreach (var v in new[] { "0.9.9", "1.0.2", "1.0.1" })
            gh.AddRelease("agent-v" + v, ReleaseFiles("agent-v" + v, Commit, v, new() { ["agent"] = new() { ["thornswood-agent.exe"] = B("program " + v) } }));
        if (badSignature)
        {
            await Assert.ThrowsAsync<InvalidDataException>(() => a.SelfUpdate(default));
            Assert.Equal("old program", File.ReadAllText(exe));
            return;
        }
        await Assert.ThrowsAsync<RestartException>(() => a.SelfUpdate(default));
        Assert.Equal("program 1.0.2", File.ReadAllText(exe));
        Assert.Equal("old program", File.ReadAllText(exe + ".old"));
        await a.Start(default);
        Assert.False(File.Exists(exe + ".old"), "the old program was not removed at the next start");
    }

    [Fact]
    public async Task ANewerTagWithNoPublishedReleaseLeavesTheAgentAsItIs()
    {
        var (_, gh, _, server, cfg) = Make();
        var exe = Path.Combine(cfg.Home, "thornswood-agent.exe");
        File.WriteAllText(exe, "old program");
        gh.AddRelease("agent-v1.0.1", ReleaseFiles("agent-v1.0.1", Commit, "1.0.1", new() { ["agent"] = new() { ["thornswood-agent.exe"] = B("program 1.0.1") } }));
        gh.BareTags.Add("agent-v1.0.2");
        var lines = new List<string>();
        var a = new Agent(cfg, new GitHub(FakeGitHub.Api, "O/R", new StaticToken("t"), new HttpClient(gh)), new FakeVerifier(),
            new() { ["dev"] = server }, "1.0.0", exe, lines.Add);
        await a.SelfUpdate(default);
        Assert.Equal("old program", File.ReadAllText(exe));
        Assert.Contains(lines, l => l.Contains("agent-v1.0.2 has no published Release"));
    }

    // ---- the service's end ---------------------------------------------------

    [Theory]
    [InlineData("update", 3)]
    [InlineData("failure", 1)]
    [InlineData("loop ended", 1)]
    public async Task WorkThatEndsByItselfStopsTheServiceWithoutWaitingOnItself(string how, int code)
    {
        Func<CancellationToken, Task> run = how switch
        {
            "update" => _ => throw new RestartException(),
            "failure" => _ => throw new InvalidOperationException("broken"),
            _ => _ => Task.CompletedTask,
        };
        var life = new Lifetime(run, _ => { });
        var stopped = new TaskCompletionSource<(int, int)>(TaskCreationOptions.RunContinuationsAsynchronously);
        // What AgentService does: the end calls ServiceBase.Stop(), which runs
        // OnStop on the same thread, and OnStop waits for the work.
        var ended = life.Start(c => stopped.SetResult((c, life.StopAndWait(() => { }))));
        var first = await Task.WhenAny(stopped.Task, Task.Delay(TimeSpan.FromSeconds(30)));
        Assert.True(first == stopped.Task, "the stop waited on the work that asked for it");
        Assert.Equal((code, code), await stopped.Task);
        await ended;
    }

    [Fact]
    public async Task AStopThatWasAskedForEndsWithZeroAndIsNotReportedAsAnEnd()
    {
        var life = new Lifetime(ct => Task.Delay(Timeout.Infinite, ct), _ => { });
        var called = false;
        var ended = life.Start(_ => called = true);
        Assert.Equal(0, life.StopAndWait(() => { }));
        await ended;
        Assert.False(called);
    }

    [Fact]
    public async Task ALocalBuildNeverUpdatesItself()
    {
        var (_, gh, _, server, cfg) = Make();
        gh.AddRelease("agent-v9.0.0", ReleaseFiles("agent-v9.0.0", Commit, "9.0.0", new() { ["agent"] = new() { ["thornswood-agent.exe"] = B("x") } }));
        var a = new Agent(cfg, new GitHub(FakeGitHub.Api, "O/R", new StaticToken("t"), new HttpClient(gh)), new FakeVerifier(),
            new() { ["dev"] = server }, "0.0.0", Path.Combine(cfg.Home, "x.exe"), _ => { });
        await a.SelfUpdate(default);
    }

    [Fact]
    public void GamemodeBlobIsGitsBlobId()
    {
        var dir = Temp();
        var p = Path.Combine(dir, "gamemode.js");
        File.WriteAllText(p, "a\nb\n");
        string want;
        try
        {
            var psi = new ProcessStartInfo("git", ["hash-object", p]) { RedirectStandardOutput = true };
            using var proc = Process.Start(psi)!;
            want = proc.StandardOutput.ReadToEnd().Trim();
            proc.WaitForExit();
        }
        catch (System.ComponentModel.Win32Exception) { return; } // no git here
        File.WriteAllText(p, "a\r\nb\r\n");
        Assert.Equal(want, Thornswood.DeployAgent.Files.GamemodeBlob(p));
    }

    [Fact]
    public void ServerLogFollowsARoll()
    {
        var dir = Temp();
        var log = Path.Combine(dir, "server.log");
        File.WriteAllText(log, "before\n");
        var sl = new ServerLog(dir);
        sl.Mark();
        File.AppendAllText(log, "one\ntw");
        Assert.Equal("one", string.Join("|", sl.Lines()));
        File.AppendAllText(log, "o\nthree\n");
        File.Move(log, log + ".20261101");
        File.WriteAllText(log, "four\n");
        Assert.Equal("two|three|four", string.Join("|", sl.Lines()));
    }

    [Fact]
    public void TheTurnIsWaitedForAndRefusedInTime()
    {
        var dir = Temp();
        var held = Turn.Take(dir, "the nightly backup", TimeSpan.FromSeconds(1), _ => { });
        var told = "";
        var e = Assert.Throws<TimeoutException>(() => Turn.Take(dir, "agent", TimeSpan.FromMilliseconds(50), s => told = s));
        Assert.Contains("the nightly backup", e.Message);
        Assert.Contains("the nightly backup", told);
        held.Dispose();
        Turn.Take(dir, "agent", TimeSpan.FromSeconds(1), _ => { }).Dispose();
    }

    [Theory]
    [InlineData(false, "{\"repositories\":[\"R\"],\"permissions\":{\"contents\":\"read\",\"deployments\":\"write\"}}")]
    [InlineData(true, "{\"repositories\":[\"R\"],\"permissions\":{\"contents\":\"read\"}}")]
    public async Task AppTokensAskForOnlyWhatTheAgentNeeds(bool releasesOnly, string want)
    {
        using var key = RSA.Create(2048);
        var state = Temp();
        File.WriteAllText(Path.Combine(state, "key.pem"), key.ExportRSAPrivateKeyPem());
        File.WriteAllText(Path.Combine(state, "app.json"), "{\"id\":42,\"slug\":\"box-admin\"}");
        string asked = "";
        var calls = 0;
        var problems = new List<string>();
        var handler = new Stub(async r =>
        {
            var parts = r.Headers.Authorization!.Parameter!.Split('.');
            static byte[] Un(string s) => Convert.FromBase64String(s.Replace('-', '+').Replace('_', '/').PadRight((s.Length + 3) / 4 * 4, '='));
            var claims = Encoding.UTF8.GetString(Un(parts[1]));
            if (!claims.Contains("\"iss\":\"42\"")) problems.Add("claims " + claims);
            if (!key.VerifyData(Encoding.ASCII.GetBytes(parts[0] + "." + parts[1]), Un(parts[2]), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) problems.Add("signature");
            switch (r.RequestUri!.AbsolutePath)
            {
                case "/repos/O/R/installation":
                    return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"id\":7}") };
                case "/app/installations/7/access_tokens":
                    calls++;
                    asked = await r.Content!.ReadAsStringAsync();
                    return new HttpResponseMessage(HttpStatusCode.Created) { Content = new StringContent($"{{\"token\":\"tok\",\"expires_at\":\"{DateTime.UtcNow.AddHours(1):yyyy-MM-ddTHH:mm:ssZ}\"}}") };
            }
            return new HttpResponseMessage(HttpStatusCode.NotFound);
        });
        var src = new AppTokens(FakeGitHub.Api, "O/R", state, new HttpClient(handler), permissions: releasesOnly ? AppTokens.ReleasesOnly : null);
        Assert.Equal("tok", await src.TokenAsync(default));
        Assert.Equal("tok", await src.TokenAsync(default));
        Assert.Empty(problems);
        Assert.Equal(1, calls);
        Assert.Equal(want, asked);
    }

    [Fact]
    public async Task AppTokensSayWhatIsMissing()
    {
        var src = new AppTokens(FakeGitHub.Api, "O/R", Temp(), new HttpClient(new Stub(_ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound)))));
        var e = await Assert.ThrowsAsync<InvalidOperationException>(() => src.TokenAsync(default));
        Assert.Contains("not set up here", e.Message);
    }

    [Fact]
    public void ConfigReadsDevAndRefusesTheRest()
    {
        var p = Path.Combine(Temp(), "agent.json");
        File.WriteAllText(p, "{\"repo\":\"O/R\",\"environments\":{\"dev\":{\"loadSeconds\":60}}}");
        var e = Config.Load(p).Environments["dev"];
        Assert.Equal((60, @"C:\Thornswood-Server-Dev", "Dev"), (e.LoadSeconds, e.Root, e.GitHubEnvironment));
        foreach (var bad in new[]
        {
            "{\"environments\":{\"dev\":{}}}",
            "{\"repo\":\"O/R\",\"environments\":{\"main\":{}}}",
            "{\"repo\":\"O/R\",\"environments\":{\"dev\":{\"githubEnvironment\":\"\"}}}",
            "{\"repo\":\"O/R\",\"environments\":{\"dev\":{\"githubEnvironment\":\"Main\"}}}",
            "{\"repo\":\"O/R\",\"api\":\"http://example.com\"}",
            "{\"repo\":\"O/R\",\"pollSeconds\":1}",
        })
        {
            File.WriteAllText(p, bad);
            Assert.Throws<ConfigException>(() => Config.Load(p));
        }
    }

    [Fact]
    public async Task ADescriptionIsCutToWhatGitHubKeeps()
    {
        var bodies = new List<string>();
        var gh = new GitHub(FakeGitHub.Api, "O/R", new StaticToken(""), new HttpClient(new Stub(async r =>
        {
            bodies.Add(await r.Content!.ReadAsStringAsync());
            return new HttpResponseMessage(HttpStatusCode.Created) { Content = new StringContent("{}") };
        })));
        await gh.SetStatus(1, "failure", new string('x', 200), "", default);
        var d = JsonNode.Parse(bodies[0])!["description"]!.GetValue<string>();
        Assert.Equal(140, d.Length);
    }
    // ---- the bot pass (#5196) --------------------------------------------------

    static readonly Dictionary<string, byte[]> BotPart = new()
    {
        ["Bot-Pass.js"] = B("// the pass"), ["bot.js"] = B("// the bot"), ["character.js"] = B("// the character"),
    };

    static void BotRelease(FakeGitHub gh, string tag, string body, bool withBot = true, Dictionary<string, string>? tables = null)
    {
        var parts = new Dictionary<string, Dictionary<string, byte[]>>
        {
            ["gamemode"] = new() { ["gamemode.js"] = B(body), ["thornswood-build.json"] = B("{\"commit\":\"new\"}") },
        };
        if (tables != null) parts["gamemode"][Tables.Zip] = TablesZip(tables);
        if (withBot) parts["bot"] = BotPart;
        gh.AddRelease(tag, ReleaseFiles(tag, Commit, "", parts));
    }

    /// <summary>A dev folder the way the box has one: an engine, settings
    /// with a load order, secrets and ports, a data folder with plugins and an
    /// archive, a world and a private folder that must never be copied.</summary>
    (Agent a, FakeGitHub gh, FakeServer s, BotPass bp) MakeWithPass(Func<BotPass, string?> work)
    {
        var (a, gh, s, server, cfg) = Make();
        var env = cfg.Environments["dev"];
        env.BotPassRoot = Temp();
        env.BotPassSeconds = 5;
        Directory.CreateDirectory(Path.Combine(env.BotPassRoot, "run"));
        File.WriteAllText(Path.Combine(s.Root, "scam_native.node"), "the engine");
        File.WriteAllText(Path.Combine(s.Root, "server-settings.json"), """
            {"port":7787,"thornswoodVoicePort":7789,"dataDir":"data","name":"Thornswood Dev","password":"dev-secret-pw",
             "loadOrder":["Skyrim.esm","Thornswood.esp"],"archives":["Thornswood.bsa"],
             "discordAuth":{"botToken":"SECRET-TOKEN"},"masterKey":"SECRET-KEY","metricsAuth":{"user":"u","password":"SECRET-METRICS"},
             "additionalServerSettings":[{"type":"github","repo":"x"}],"thornswoodRequirePass":true,"offlineMode":false,
             "startPoints":[{"pos":[1,2,3],"worldOrCell":"0x3c","angleZ":0}]}
            """);
        foreach (var n in new[] { "Skyrim.esm", "Thornswood.esp", "Thornswood.bsa", "Unused.esp" })
            File.WriteAllText(Path.Combine(s.Root, "data", n), "plugin " + n);
        Directory.CreateDirectory(Path.Combine(s.Root, "data", "scripts"));
        File.WriteAllText(Path.Combine(s.Root, "data", "scripts", "ActiveMagicEffect.pex"), "pex");
        File.WriteAllText(Path.Combine(s.Root, "data", "manifest.json"), "{}");
        File.WriteAllText(Path.Combine(s.Root, "data", "thornswood-deploy.json"), "{}");
        Directory.CreateDirectory(Path.Combine(s.Root, "private"));
        File.WriteAllText(Path.Combine(s.Root, "private", "door.json"), "{\"passKey\":\"SECRET-DOOR\"}");
        Directory.CreateDirectory(Path.Combine(s.Root, "world", "changeForms"));
        File.WriteAllText(Path.Combine(s.Root, "world", "changeForms", "1.json"), "{\"profileId\":5}");
        BotPass? made = null;
        var tasks = new FakeTasks(() => work(made!));
        var bp = made = new BotPass(env, tasks) { Tick = TimeSpan.FromMilliseconds(20), InUse = () => (new() { 7900 }, new() { 7904 }) };
        a.Tasks = tasks;
        a.MakeBotPass = _ => bp;
        return (a, gh, s, bp);
    }

    static string? WriteResult(BotPass bp, bool ok, string failAt = "")
    {
        var lines = new[] { "loads", "login", "new", "face", "saved", "restart", "loads back" }
            .Select(st => new JsonObject { ["step"] = st, ["ok"] = st != failAt, ["detail"] = st == failAt ? "it went wrong at 10.0.0.5:7901" : "fine" });
        var doc = new JsonObject { ["schema"] = 1, ["ok"] = ok, ["lines"] = new JsonArray(lines.ToArray<JsonNode>()), ["tail"] = new JsonArray("the server said 10.0.0.5") };
        File.WriteAllText(bp.ResultPath, doc.ToJsonString());
        return null;
    }

    [Fact]
    public async Task ADeploymentWaitsOnTheBotPassAndGoesInWhenItPasses()
    {
        JsonObject? seen = null;
        string? copyTree = null;
        var (a, gh, s, bp) = MakeWithPass(bp =>
        {
            seen = JsonNode.Parse(File.ReadAllText(Path.Combine(bp.ServerDir, "server-settings.json")))!.AsObject();
            copyTree = string.Join("\n", Directory.GetFiles(bp.RunDir, "*", SearchOption.AllDirectories).Select(f => Path.GetRelativePath(bp.RunDir, f).Replace('\\', '/')).Order(StringComparer.Ordinal));
            return WriteResult(bp, true);
        });
        BotRelease(gh, "build-1", "// new gamemode\n");
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-1\"}");
        await a.Pass("dev", default);
        HasStates(gh, s, id, "in_progress,success");
        Assert.Equal("// new gamemode\n", s.Read("gamemode.js"));
        Assert.Contains("bot pass: 7 of 7 passed", s.Read(Path.Combine("data", $"deploy-{id}.log")));

        // The copy: the new gamemode and the engine, the bot, dev's data
        // without its game files, nothing private, no world.
        Assert.NotNull(copyTree);
        Assert.Equal(string.Join("\n", new[] {
            "bot/Bot-Pass.js", "bot/bot.js", "bot/character.js",
            "server/data/scripts/ActiveMagicEffect.pex", "server/dist_back/skymp5-server.js",
            "server/gamemode.js", "server/scam_native.node", "server/server-settings.json", "server/thornswood-build.json",
        }.Order(StringComparer.Ordinal)), copyTree);
        Assert.Equal("// new gamemode\n", File.ReadAllText(Path.Combine(bp.ServerDir, "gamemode.js")));

        // Its settings: its own ports, offline, no hold, no secrets, game files by full path.
        var st = seen!;
        Assert.Equal(7901, st["port"]!.GetValue<int>());
        Assert.Equal(7903, st["thornswoodVoicePort"]!.GetValue<int>());
        Assert.False(st["thornswoodRequirePass"]!.GetValue<bool>());
        Assert.True(st["offlineMode"]!.GetValue<bool>());
        Assert.Equal("", st["master"]!.GetValue<string>());
        Assert.Equal("Thornswood Dev (bot pass)", st["name"]!.GetValue<string>());
        Assert.NotEqual("dev-secret-pw", st["password"]!.GetValue<string>());
        Assert.Equal(("data", "private", "file", "world"), (st["dataDir"]!.GetValue<string>(), st["privDir"]!.GetValue<string>(), st["databaseDriver"]!.GetValue<string>(), st["databaseName"]!.GetValue<string>()));
        foreach (var k in BotPass.Dropped) Assert.False(st.ContainsKey(k), k + " was copied");
        Assert.DoesNotContain("SECRET", st.ToJsonString());
        Assert.Equal(new[] { Path.Combine(bp.PluginDir, "Skyrim.esm"), Path.Combine(bp.PluginDir, "Thornswood.esp") }, st["loadOrder"]!.AsArray().Select(x => x!.GetValue<string>()));
        Assert.Equal(Path.Combine(bp.PluginDir, "Thornswood.bsa"), st["archives"]![0]!.GetValue<string>());
        Assert.False(File.Exists(Path.Combine(bp.PluginDir, "Unused.esp")), "a plugin dev does not load was copied");
        // Dev's own folder is as it was.
        Assert.Contains("SECRET-DOOR", s.Read(Path.Combine("private", "door.json")));
        Assert.Contains("dev-secret-pw", s.Read("server-settings.json"));
    }

    [Fact]
    public async Task WithAnEnginePinTheBotPassRunsTheNewServerBuild()
    {
        string? native = null, scripts = null;
        var (a, gh, s, bp) = MakeWithPass(bp =>
        {
            native = File.ReadAllText(Path.Combine(bp.ServerDir, "scam_native.node"));
            scripts = string.Join(",", Directory.GetFiles(Path.Combine(bp.ServerDir, "data", "scripts")).Select(Path.GetFileName).Order(StringComparer.Ordinal));
            return WriteResult(bp, true);
        });
        var (oldFiles, oldRec) = Build(ForkA);
        Install(s, oldFiles, oldRec);
        var (newFiles, newRec) = Build(ForkB, scripts: ["Actor.pex", "New.pex"]);
        var zip = Zip(newFiles, newRec);
        var zipName = "server-" + Sha(newRec)[..12] + "-" + Sha(zip)[..16] + ".zip";
        gh.AddRelease("build-9", ReleaseFiles("build-9", Commit, "", new()
        {
            ["gamemode"] = new() { ["gamemode.js"] = B("// gamemode for B\n"), ["thornswood-build.json"] = B("{\"commit\":\"new\"}") },
            ["bot"] = BotPart,
            ["server"] = new() { ["server-build.json"] = newRec, [zipName] = zip },
        }));
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-9\"}");
        await a.Pass("dev", default);
        HasStates(gh, s, id, "success", last: true);
        // The copy ran the build dev was about to get, with its own scripts
        // and none of dev's, and then dev got it.
        Assert.Equal("native " + ForkB, native);
        Assert.Equal("Actor.pex,New.pex", scripts);
        Assert.Equal(newRec, File.ReadAllBytes(Path.Combine(s.Root, "server-build.json")));
        Assert.Equal("// gamemode for B\n", s.Read("gamemode.js"));
        var log = s.Read(Path.Combine("data", $"deploy-{id}.log"));
        Assert.Contains("the copy runs the new server build", log);
        Assert.True(log.IndexOf("bot pass: 7 of 7 passed") < log.IndexOf("held Thornswood Dev Server"), "dev was swapped before the bot pass passed");
    }

    [Theory]
    [InlineData("face", "the bot pass failed at face: it went wrong at")]
    [InlineData("hang", "the bot pass did not end within 5 s")]
    [InlineData("nothing", "it wrote no result.json")]
    [InlineData("nobot", "carries no bot")]
    public async Task AFailedBotPassLeavesDevAsItWas(string how, string want)
    {
        var (a, gh, s, bp) = MakeWithPass(bp => how switch
        {
            "hang" => "hang",
            "nothing" => null,
            _ => WriteResult(bp, false, how),
        });
        BotRelease(gh, "build-1", "// new gamemode\n", withBot: how != "nobot");
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-1\"}");
        await a.Pass("dev", default);
        var last = gh.Last(id)!;
        Assert.Equal("failure", (string)last["state"]!);
        Assert.Contains(want, (string)last["description"]!);
        Assert.Equal("// old gamemode\r\n", s.Read("gamemode.js"));
        Assert.Empty(Directory.GetDirectories(s.Root, ".prev-*"));
        var log = s.Read(Path.Combine("data", $"deploy-{id}.log"));
        Assert.DoesNotContain("10.0.0.5", log);
        if (how == "hang") Assert.Equal(1, ((FakeTasks)a.Tasks).Ends);
        if (how == "face") Assert.Contains("FAIL  face", log);
    }

    [Fact]
    public async Task TheGateVerbDoesNotWaitOnABotPass()
    {
        var (a, gh, s, _) = MakeWithPass(bp => throw new InvalidOperationException("a rollback started a bot pass"));
        BotRelease(gh, "build-1", "// rolled back\n", withBot: false);
        Assert.Equal("success", (await a.DeployTag("dev", "build-1", default)).State);
        Assert.Equal("// rolled back\n", s.Read("gamemode.js"));
        Assert.Equal(0, ((FakeTasks)a.Tasks).Starts);
    }

    [Fact]
    public async Task WithNoBotPassSetUpADeploymentGoesInAndSaysSo()
    {
        var (a, gh, s, _, _) = Make();
        GamemodeRelease(gh, "build-1", "// new gamemode\n");
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-1\"}");
        await a.Pass("dev", default);
        HasStates(gh, s, id, "success", last: true);
        Assert.Contains("no bot pass: it is not set up on this box yet", s.Read(Path.Combine("data", $"deploy-{id}.log")));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task TheBotPassCopyHasTheTablesTheGamemodeReads(bool inRelease)
    {
        // A gamemode from #5191 on reads gamemode-tables beside it, and stops
        // loading without it, so the copy carries the folder dev will have:
        // the Release's, or dev's own when the Release carries none.
        Dictionary<string, string>? copied = null;
        var (a, gh, s, bp) = MakeWithPass(bp =>
        {
            var d = Path.Combine(bp.ServerDir, Tables.Dir);
            copied = Directory.Exists(d) ? Directory.GetFiles(d).ToDictionary(f => Path.GetFileName(f), File.ReadAllText) : new();
            return WriteResult(bp, true);
        });
        PutTables(s, new() { ["FOODS.json"] = "[\"dev\"]" });
        BotRelease(gh, "build-1", Reading("new gamemode"), tables: inRelease ? new() { ["FOODS.json"] = "[\"new\"]", ["DATA.json"] = "{}" } : null);
        var id = gh.AddDeployment("Dev", Commit, "{\"release\":\"build-1\"}");
        await a.Pass("dev", default);
        HasStates(gh, s, id, "success", last: true);
        Assert.NotNull(copied);
        Assert.Equal(inRelease ? "DATA.json={},FOODS.json=[\"new\"]" : "FOODS.json=[\"dev\"]",
            string.Join(",", copied!.OrderBy(kv => kv.Key, StringComparer.Ordinal).Select(kv => kv.Key + "=" + kv.Value)));
    }

    [Fact]
    public void ThePluginsAreCopiedOnlyWhenTheyChange()
    {
        var (_, _, s, bp) = MakeWithPass(_ => null);
        var files = new Dictionary<string, string>();
        var dir = Temp();
        foreach (var (n, b) in BotPart.Concat(new Dictionary<string, byte[]> { ["gamemode.js"] = B("// g"), ["thornswood-build.json"] = B("{}") }))
        {
            files[n] = Path.Combine(dir, n);
            File.WriteAllBytes(files[n], b);
        }
        var said = new List<string>();
        Assert.Equal("", bp.Prepare(files, said.Add));
        Assert.Contains(said, l => l.Contains("3 were new or changed on dev"));
        said.Clear();
        Assert.Equal("", bp.Prepare(files, said.Add));
        Assert.Contains(said, l => l.Contains("0 were new or changed on dev"));
        File.WriteAllText(Path.Combine(s.Root, "data", "Thornswood.esp"), "plugin Thornswood.esp, changed");
        said.Clear();
        Assert.Equal("", bp.Prepare(files, said.Add));
        Assert.Contains(said, l => l.Contains("1 were new or changed on dev"));
        Assert.Equal("plugin Thornswood.esp, changed", File.ReadAllText(Path.Combine(bp.PluginDir, "Thornswood.esp")));
        // A load order naming a file that is not there stops the copy.
        File.Delete(Path.Combine(s.Root, "data", "Skyrim.esm"));
        Assert.Throws<InvalidDataException>(() => bp.Prepare(files, said.Add));
    }

    [Fact]
    public void ABotPassFolderMustBeAFullPathAndNotTheServers()
    {
        var p = Path.Combine(Temp(), "agent.json");
        foreach (var bad in new[]
        {
            "{\"repo\":\"O/R\",\"environments\":{\"dev\":{\"botPassRoot\":\"relative\"}}}",
            "{\"repo\":\"O/R\",\"environments\":{\"dev\":{\"botPassRoot\":\"C:\\\\Thornswood-Server-Dev\"}}}",
            "{\"repo\":\"O/R\",\"environments\":{\"dev\":{\"botPassRoot\":\"C:\\\\Thornswood-BotPass\",\"botPassSeconds\":5}}}",
        })
        {
            File.WriteAllText(p, bad);
            Assert.Throws<ConfigException>(() => Config.Load(p));
        }
        File.WriteAllText(p, "{\"repo\":\"O/R\",\"environments\":{\"dev\":{\"botPassRoot\":\"C:\\\\Thornswood-BotPass\"}}}");
        var c = Config.Load(p).Environments["dev"];
        Assert.Equal((@"C:\Thornswood-BotPass", "Thornswood Bot Pass", 1800), (c.BotPassRoot, c.BotPassTask, c.BotPassSeconds));
    }
}


/// <summary>Task Scheduler with one task: Start runs what the test gives it
/// (Bot-Pass.js's part, writing result.json) on a task of its own, and Info
/// says Running until that has finished.</summary>
sealed class FakeTasks(Func<string?> work) : ITasks
{
    public int Starts, Ends;
    public string? LastName;
    volatile bool running;
    DateTime last = DateTime.MinValue;
    public void Start(string name)
    {
        Starts++;
        LastName = name;
        running = true;
        last = DateTime.UtcNow;
        Task.Run(() => { var w = work(); if (w != "hang") running = false; });
    }
    public TaskInfo Info(string name) => new(running ? "Running" : "Ready", last, 0);
    public void End(string name) { Ends++; running = false; }
}

sealed class Stub(Func<HttpRequestMessage, Task<HttpResponseMessage>> f) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage r, CancellationToken ct) => f(r);
}
