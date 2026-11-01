using System.Diagnostics;
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
            if (p == "/repos/O/R/releases")
                return Json(HttpStatusCode.OK, new JsonArray(Releases.Values.Select(v => v.DeepClone()).ToArray()).ToJsonString());
            if (p.StartsWith("/repos/O/R/releases/assets/"))
            {
                if (r.Headers.Accept.ToString() != "application/octet-stream") return new HttpResponseMessage(HttpStatusCode.UnsupportedMediaType);
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(Files[long.Parse(p["/repos/O/R/releases/assets/".Length..])]) };
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
/// gamemode holding BROKEN does not load.</summary>
sealed class FakeServer : IDisposable
{
    public const string EngineSays = "[thornswood] gamemode did not load; the error is above";
    public readonly string Root;
    public volatile bool Healthy = true;
    readonly CancellationTokenSource stop = new();
    readonly Task engine;

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

    public HttpResponseMessage Health(HttpRequestMessage r) => new(Healthy ? HttpStatusCode.OK : HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") };

    async Task Engine()
    {
        var gm = Path.Combine(Root, "gamemode.js");
        var last = Thornswood.DeployAgent.Files.ReadShared(gm);
        while (!stop.IsCancellationRequested)
        {
            try { await Task.Delay(5, stop.Token); } catch (OperationCanceledException) { return; }
            byte[] b;
            try { b = Thornswood.DeployAgent.Files.ReadShared(gm); } catch (IOException) { continue; }
            if (b.AsSpan().SequenceEqual(last)) continue;
            last = b;
            var text = Encoding.UTF8.GetString(b);
            var lines = text.Contains("BROKEN")
                ? $"SyntaxError: Unexpected token at 10.1.2.3:7787\n{EngineSays}\n"
                : $"[thornswood] gamemode.js is git blob {Thornswood.DeployAgent.Files.GamemodeBlob(gm)}, {b.Length} bytes\n[thornswood] gamemode client scripts abc (3), changed since the last load\n";
            try { File.AppendAllText(Path.Combine(Root, "server.log"), lines); } catch (IOException) { }
        }
    }

    public string Read(string rel) => File.ReadAllText(Path.Combine(Root, rel));

    public void Dispose()
    {
        stop.Cancel();
        try { engine.Wait(); } catch (AggregateException) { }
        try { Directory.Delete(Root, true); } catch (IOException) { }
    }
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
        foreach (var d in temp) try { Directory.Delete(d, true); } catch (IOException) { }
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

    static void GamemodeRelease(FakeGitHub gh, string tag, string body) =>
        gh.AddRelease(tag, ReleaseFiles(tag, Commit, "", new()
        {
            ["gamemode"] = new() { ["gamemode.js"] = B(body), ["thornswood-build.json"] = B("{\"commit\":\"new\"}") },
            ["launcher"] = new() { ["Thornswood.exe"] = B("MZ") },
        }));

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
        env.LoadSeconds = 10;
        env.TurnSeconds = 10;
        var cfg = new Config { Repo = "O/R", Api = FakeGitHub.Api, Home = home, Environments = { ["dev"] = env } };
        var server = new Server(env, http) { Tick = TimeSpan.FromMilliseconds(5) };
        var gh2 = new GitHub(FakeGitHub.Api, "O/R", new StaticToken("t"), http);
        var a = new Agent(cfg, gh2, v ?? new FakeVerifier(), new() { ["dev"] = server }, "1.0.0", "", l => { lock (said) said.Add(l); }) { Host = "box" };
        return (a, gh, s, server, cfg);
    }

    [Fact]
    public async Task AppliesAGamemodeByReload()
    {
        var (a, gh, s, _, _) = Make();
        GamemodeRelease(gh, "build-1", "// new gamemode\n");
        var id = gh.AddDeployment("Dev server", Commit, "{\"release\":\"build-1\"}");
        await a.Pass("dev", default);
        Assert.Equal("in_progress,success", string.Join(",", gh.States(id)));
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
        var id = gh.AddDeployment("Dev server", Commit, "{\"release\":\"build-2\"}");
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
        var id = gh.AddDeployment("Dev server", Commit, "{\"release\":\"build-3\"}");
        // Healthy for the check before, sick after the load.
        using var stop = new CancellationTokenSource();
        var watch = Task.Run(async () =>
        {
            while (!stop.IsCancellationRequested)
            {
                try { if (s.Read("gamemode.js").Contains("sick")) { s.Healthy = false; return; } } catch (IOException) { }
                await Task.Delay(1);
            }
        });
        server.Tick = TimeSpan.FromMilliseconds(20);
        await a.Pass("dev", default);
        stop.Cancel();
        await watch;
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
        var id = gh.AddDeployment("Dev server", sha, payload);
        await a.Pass("dev", default);
        var last = gh.Last(id)!;
        Assert.Equal("failure", (string)last["state"]!);
        Assert.Contains(want, (string)last["description"]!);
        Assert.Equal("// old gamemode\r\n", s.Read("gamemode.js"));
    }

    [Fact]
    public async Task OnlyTheNewestIsAppliedAndRecordsAreLeftAlone()
    {
        var (a, gh, _, _, _) = Make();
        GamemodeRelease(gh, "build-1", "// new gamemode\n");
        var record = gh.AddDeployment("Dev", Commit, "{}");
        var older = gh.AddDeployment("Dev server", Commit, "{\"release\":\"build-1\"}");
        var newest = gh.AddDeployment("Dev server", Commit, "{\"release\":\"build-1\"}");
        await a.Pass("dev", default);
        Assert.Equal("inactive", string.Join(",", gh.States(older)));
        Assert.Equal("in_progress,success", string.Join(",", gh.States(newest)));
        Assert.Empty(gh.States(record));
    }

    [Fact]
    public async Task ADeploymentCutShortIsMarkedError()
    {
        var (a, gh, _, _, cfg) = Make();
        var id = gh.AddDeployment("Dev server", Commit, "{\"release\":\"build-1\"}");
        var state = Path.Combine(cfg.Home, "state", "working.json");
        Directory.CreateDirectory(Path.GetDirectoryName(state)!);
        File.WriteAllText(state, $"{{\"Deployment\":\"{id}\",\"Env\":\"dev\",\"Started\":\"then\"}}");
        await a.Start(default);
        Assert.Equal("error", (string)gh.Last(id)!["state"]!);
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
        Assert.Equal((60, @"C:\Thornswood-Server-Dev", "Dev server"), (e.LoadSeconds, e.Root, e.GitHubEnvironment));
        foreach (var bad in new[]
        {
            "{\"environments\":{\"dev\":{}}}",
            "{\"repo\":\"O/R\",\"environments\":{\"main\":{}}}",
            "{\"repo\":\"O/R\",\"environments\":{\"dev\":{\"githubEnvironment\":\"Dev\"}}}",
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
}

sealed class Stub(Func<HttpRequestMessage, Task<HttpResponseMessage>> f) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage r, CancellationToken ct) => f(r);
}
