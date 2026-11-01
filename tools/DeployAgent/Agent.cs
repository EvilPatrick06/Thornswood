#nullable enable
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Thornswood.DeployAgent;

/// <summary>A newer agent is in place; the service ends so the service
/// manager starts it (Install-DeployAgent.ps1 sets the service to be started
/// again when it ends with an error code).</summary>
public sealed class RestartException() : Exception("a newer signed agent is in place; ending so the service starts it");

/// <summary>The agent: applying one Release by its tag (the gate's
/// Deploy-Release verb), applying each environment's newest Deployment (the
/// service), and updating itself.</summary>
public sealed class Agent(Config cfg, GitHub gh, IVerifier verify, Dictionary<string, Server> servers, string version, string exe, Action<string> log)
{
    public string Host { get; set; } = System.Environment.MachineName;
    /// <summary>Task Scheduler, for the bot pass's task. A test stands one in.</summary>
    public ITasks Tasks { get; set; } = new WindowsTasks();
    /// <summary>Makes the bot pass for a server. A test stands in its ports.</summary>
    public Func<EnvConfig, BotPass>? MakeBotPass { get; set; }
    string StatePath => Path.Combine(cfg.Home, "state", "working.json");
    static readonly Regex BuildTag = new(@"^build-[A-Za-z0-9._-]{1,80}$");
    static readonly Regex AgentTag = new(@"^agent-v(\d+)\.(\d+)\.(\d+)$");

    // ---- one Release, applied -------------------------------------------------

    /// <summary>Fetches a build Release, holds it to its signature, and applies
    /// its gamemode to the environment's server. expectCommit, when given, is
    /// the commit the Release must be (a Deployment's). With botPass, and a
    /// bot pass set up for the environment, the gamemode goes in only after
    /// the bot pass passed on a throwaway copy of the server (#5196). Writes
    /// the record on success. Every line goes to log.</summary>
    public async Task<Outcome> ApplyRelease(string env, string tag, string expectCommit, string workName, Action<string> logf, CancellationToken ct, bool botPass = false)
    {
        if (!servers.TryGetValue(env, out var srv)) return new Outcome("failure", $"not applied: this agent does not look after {env}");
        if (!BuildTag.IsMatch(tag)) return new Outcome("failure", $"not applied: \"{tag}\" is not a build-<...> Release tag");
        Release rel;
        try { rel = await gh.ReleaseByTag(tag, ct); }
        catch (GitHubException e) when (e.Status == 404) { return new Outcome("failure", "not applied: there is no published Release " + tag); }
        catch (Exception e) when (e is GitHubException or HttpRequestException or TaskCanceledException) { return new Outcome("error", "the Release could not be read: " + e.Message); }
        var dir = Path.Combine(cfg.Home, "work", workName);
        try
        {
            Fetched f;
            var pass = botPass && srv.Env.BotPassRoot != "";
            string[] parts = pass ? ["gamemode", "bot"] : ["gamemode"];
            try { f = await ReleaseFetch.Fetch(gh, verify, rel, dir, parts, logf, ct); }
            catch (Exception e) when (e is InvalidDataException or IOException or HttpRequestException) { return new Outcome("failure", "not applied: " + e.Message); }
            var m = f.Manifest;
            // The name, not the owner: the repositories move to an
            // organization (#5184), and a Release from before the move is
            // still this repository's. The signature is what is trusted.
            if (!string.Equals(m.Repo.Split('/')[^1], cfg.Repo.Split('/')[^1], StringComparison.OrdinalIgnoreCase))
                return new Outcome("failure", $"not applied: the Release was built from {m.Repo}, not {cfg.Repo}");
            if (expectCommit != "" && m.Commit != expectCommit)
                return new Outcome("failure", $"not applied: the Release is commit {Short(m.Commit)} and the Deployment is {Short(expectCommit)}");
            var others = m.Parts.Keys.Where(k => !parts.Contains(k)).OrderBy(k => k, StringComparer.Ordinal).ToList();
            if (others.Count > 0) logf($"the Release also carries {string.Join(", ", others)}, which this agent does not apply yet; left alone");
            logf($"release {rel.TagName}, commit {m.Commit}");
            if (pass)
            {
                logf("the bot pass first, on a throwaway copy of the server with this gamemode (#5196)");
                var bp = await (MakeBotPass?.Invoke(srv.Env) ?? new BotPass(srv.Env, Tasks)).Run(f.Files, logf, ct);
                if (bp.State != "success") return bp;
                logf(bp.Summary);
            }
            else if (botPass)
            {
                logf("no bot pass: it is not set up on this box yet (Install-DeployAgent.ps1 sets it up)");
            }
            var outc = await srv.ApplyGamemode(f.Files, $"the deploy agent, {workName}", logf, ct);
            if (outc.State != "success") return outc;
            var gm = Path.Combine(srv.Env.Root, "gamemode.js");
            Records.Write(srv, new DeployRecord
            {
                Component = "gamemode",
                Name = rel.TagName,
                Commit = m.Commit,
                Sha256 = ReleaseFetch.FileSha256(gm),
                Size = new FileInfo(gm).Length,
                Files = Server.ReloadFiles.Length,
                DeployedUtc = Records.UtcNow(),
                From = $"deploy agent {version} on {Host}",
            }, logf);
            return outc with { Summary = rel.TagName + ": " + outc.Summary };
        }
        finally
        {
            try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    /// <summary>The gate's Deploy-Release verb: one Release by its tag, with no
    /// Deployment to report on. Rollback is this with the Release before. It
    /// does not wait on a bot pass: a rollback puts back a gamemode dev has
    /// already run, and is wanted at once.</summary>
    public async Task<Outcome> DeployTag(string env, string tag, CancellationToken ct)
    {
        var id = $"{tag}-{DateTime.Now:yyyyMMdd-HHmmss}";
        var lines = new List<string>();
        void Logf(string s) { lines.Add($"{DateTime.Now:h:mm:ss tt}  {s}"); log(s); }
        Logf($"deploy agent {version} on {Host}: {tag} to {env}, by the deploy gate");
        var outc = await ApplyRelease(env, tag, "", "tag-" + id, Logf, ct);
        Logf(outc.State.ToUpperInvariant() + ": " + outc.Summary);
        if (servers.TryGetValue(env, out var srv))
        {
            var url = Records.PublishLog(srv, id, lines);
            if (url != "") log("the log: " + url);
        }
        return outc;
    }

    // ---- the service --------------------------------------------------------------

    sealed record Working(string Deployment, string Env, string Started);

    /// <summary>Once as the service starts. A Deployment it was part way
    /// through when it last stopped gets an error status naming that, and a
    /// program an update left behind is removed.</summary>
    public async Task Start(CancellationToken ct)
    {
        if (exe != "" && File.Exists(exe + ".old"))
        {
            try { File.Delete(exe + ".old"); log("removed the agent an update replaced"); } catch (IOException) { }
        }
        if (!File.Exists(StatePath)) return;
        try
        {
            var w = JsonSerializer.Deserialize<Working>(File.ReadAllText(StatePath));
            if (w != null && long.TryParse(w.Deployment, out var id))
            {
                await gh.SetStatus(id, "error", $"the deploy agent stopped part way through this (started {w.Started}); its log on the box says how far it got", "", ct);
                log($"deployment {id} was cut short when the agent last stopped; marked error");
            }
        }
        catch (Exception e) when (e is JsonException or GitHubException or HttpRequestException or InvalidOperationException)
        {
            log("a deployment was cut short and its status could not be set: " + e.Message);
            return;
        }
        File.Delete(StatePath);
    }

    /// <summary>The service's loop. A pass that fails is said in the log (once
    /// for each new reason) and the next pass looks again from GitHub's record,
    /// which is the desired state: nothing is tried again from memory.</summary>
    public async Task Run(CancellationToken ct)
    {
        await Start(ct);
        var nextUpdate = DateTime.MinValue;
        var lastSaid = new Dictionary<string, string>();
        void Once(string key, string s) { if (!lastSaid.TryGetValue(key, out var was) || was != s) { lastSaid[key] = s; log(s); } }
        while (!ct.IsCancellationRequested)
        {
            foreach (var env in cfg.Environments.Keys.OrderBy(k => k, StringComparer.Ordinal))
            {
                try { await Pass(env, ct); lastSaid.Remove(env); }
                catch (Exception e) when (e is not OperationCanceledException) { Once(env, $"{env}: {e.Message}"); }
            }
            if (DateTime.UtcNow > nextUpdate)
            {
                nextUpdate = DateTime.UtcNow.AddMinutes(cfg.UpdateMinutes);
                try { await SelfUpdate(ct); lastSaid.Remove("update"); }
                catch (RestartException) { throw; }
                catch (Exception e) when (e is not OperationCanceledException) { Once("update", "update check: " + e.Message); }
            }
            try { await Task.Delay(TimeSpan.FromSeconds(cfg.PollSeconds), ct); } catch (OperationCanceledException) { return; }
        }
    }

    /// <summary>The environment's newest Deployment, applied when nobody has
    /// said anything on it yet. Older ones with no status are marked inactive:
    /// the newest is the desired state, and applying the ones before it first
    /// would only put in what is about to be replaced.</summary>
    public async Task Pass(string env, CancellationToken ct)
    {
        var deps = await gh.Deployments(cfg.Environments[env].GitHubEnvironment, 10, ct);
        if (deps.Count == 0) return;
        var newest = deps[0];
        if ((await gh.Statuses(newest.Id, ct)).Count > 0) return;
        foreach (var d in deps.Skip(1))
        {
            if ((await gh.Statuses(d.Id, ct)).Count > 0) continue;
            await gh.SetStatus(d.Id, "inactive", $"not applied: deployment {newest.Id} came after it and is applied instead", "", ct);
            log($"{env}: deployment {d.Id} is older than {newest.Id} and was never applied; marked inactive");
        }
        await Apply(env, newest, ct);
    }

    /// <summary>Reads the payload a Deployment carries: the Release tag. GitHub
    /// hands it back as the object it was given or as a string holding it.</summary>
    public static string PayloadRelease(JsonElement payload)
    {
        var p = payload;
        if (p.ValueKind == JsonValueKind.String)
        {
            using var d = JsonDocument.Parse(p.GetString() ?? "");
            p = d.RootElement.Clone();
        }
        if (p.ValueKind != JsonValueKind.Object || !p.TryGetProperty("release", out var r) || r.ValueKind != JsonValueKind.String)
            throw new InvalidDataException("the Deployment has no payload naming a Release");
        return r.GetString()!;
    }

    async Task Apply(string env, Deployment d, CancellationToken ct)
    {
        var srv = servers[env];
        var lines = new List<string>();
        void Logf(string s) { lines.Add($"{DateTime.Now:h:mm:ss tt}  {s}"); log($"{env} deployment {d.Id}: {s}"); }
        Files.WriteWhole(StatePath, JsonSerializer.SerializeToUtf8Bytes(new Working(d.Id.ToString(), env, Records.UtcNow())));
        try
        {
            await gh.SetStatus(d.Id, "in_progress", "the deploy agent on the box is applying this", "", ct);
            Logf($"deploy agent {version} on {Host}, deployment {d.Id} of {Short(d.Sha)} by {d.Creator?.Name}");
            Outcome outc;
            if (d.Task != "" && d.Task != "deploy") outc = new Outcome("failure", $"not applied: the Deployment's task is {d.Task}, and the agent applies deploy only");
            else
            {
                string tag;
                try { tag = PayloadRelease(d.Payload); outc = await ApplyRelease(env, tag, d.Sha, $"deployment-{d.Id}", Logf, ct, botPass: true); }
                catch (Exception e) when (e is InvalidDataException or JsonException) { outc = new Outcome("failure", "not applied: " + e.Message); }
            }
            Logf(outc.State.ToUpperInvariant() + ": " + outc.Summary);
            var url = Records.PublishLog(srv, d.Id.ToString(), lines);
            await gh.SetStatus(d.Id, outc.State, outc.Summary, url, ct);
        }
        finally { File.Delete(StatePath); }
    }

    static string Short(string s) => s.Length > 12 ? s[..12] : s;

    // ---- self-update ------------------------------------------------------------

    public static int[]? ParseVersion(string v)
    {
        var parts = v.Split('.');
        if (parts.Length != 3) return null;
        var o = new int[3];
        for (int i = 0; i < 3; i++) if (!int.TryParse(parts[i], out o[i]) || o[i] < 0) return null;
        return o;
    }

    static bool Newer(int[] a, int[] b)
    {
        for (int i = 0; i < 3; i++) if (a[i] != b[i]) return a[i] > b[i];
        return false;
    }

    /// <summary>Puts a newer signed agent in place of this one and throws
    /// RestartException; returns when this is the newest. A local build
    /// (0.0.0) never updates itself. The new program is held to its Release's
    /// signed manifest and to its own signature first; the running one is
    /// renamed aside (Windows lets a running program be renamed) and removed at
    /// the next start.</summary>
    public async Task SelfUpdate(CancellationToken ct)
    {
        var own = ParseVersion(version);
        if (own == null || own.All(x => x == 0) || exe == "") return;
        Release? best = null;
        var bestV = own;
        foreach (var r in await gh.Releases(30, ct))
        {
            var m = AgentTag.Match(r.TagName);
            if (!m.Success || r.Draft) continue;
            var v = ParseVersion($"{m.Groups[1]}.{m.Groups[2]}.{m.Groups[3]}")!;
            if (Newer(v, bestV)) { best = r; bestV = v; }
        }
        if (best == null) return;
        log($"agent {best.TagName} is out (this is {version}); fetching it");
        var dir = Path.Combine(cfg.Home, "work", "update");
        try
        {
            var f = await ReleaseFetch.Fetch(gh, verify, best, dir, ["agent"], log, ct);
            var want = best.TagName["agent-v".Length..];
            if (f.Manifest.Version != want) throw new InvalidDataException($"release {best.TagName}: its manifest says version \"{f.Manifest.Version}\"");
            if (!f.Files.TryGetValue("thornswood-agent.exe", out var newExe)) throw new InvalidDataException($"release {best.TagName} carries no thornswood-agent.exe");
            try { verify.File(newExe); }
            catch (SignatureException e) { throw new InvalidDataException($"release {best.TagName}: the program's own signature does not hold: {e.Message}"); }
            var old = exe + ".old";
            if (File.Exists(old)) File.Delete(old);
            File.Move(exe, old);
            try { File.Move(newExe, exe); }
            catch (IOException e)
            {
                File.Move(old, exe);
                throw new IOException("the new agent could not go in, and the old one is back: " + e.Message);
            }
            log($"agent {want} is in place of {version}");
        }
        finally
        {
            try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch (IOException) { }
        }
        throw new RestartException();
    }

    /// <summary>Whether the agent can do its job: a token from the App with
    /// what it asks for, each environment's Deployments readable, each server
    /// answering. Changes nothing.</summary>
    public async Task<bool> Check(CancellationToken ct)
    {
        var ok = true;
        try { await gh.Tokens.TokenAsync(ct); log($"the box admin App gives a token with Deployments write and Contents read on {cfg.Repo}"); }
        catch (Exception e) when (e is InvalidOperationException or GitHubException or HttpRequestException) { log("NOT YET: " + e.Message); ok = false; }
        foreach (var (env, e) in cfg.Environments)
        {
            if (ok)
            {
                var deps = await gh.Deployments(e.GitHubEnvironment, 1, ct);
                if (deps.Count == 0) log($"{env}: no Deployment to \"{e.GitHubEnvironment}\" yet");
                else
                {
                    var sts = await gh.Statuses(deps[0].Id, ct);
                    log($"{env}: newest Deployment {deps[0].Id} ({Short(deps[0].Sha)}), " + (sts.Count > 0 ? $"{sts[0].State}: {sts[0].Description}" : "no status yet"));
                }
            }
            var sick = await servers[env].Unhealthy(ct);
            if (sick != "") { log($"{env}: {sick}"); ok = false; }
            else log($"{env}: {e.Health} answers 200");
        }
        return ok;
    }
}
