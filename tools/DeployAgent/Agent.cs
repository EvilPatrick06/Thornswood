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
    /// <summary>The apps beside the servers the agent looks after, by the
    /// environment's name: the site and the Discord bot (#5190, #5187).</summary>
    public Dictionary<string, App> Apps { get; set; } = new();
    /// <summary>Each server's voice service, by the server's environment
    /// (#5187): a Release's voice part goes in with that server's Deployment.</summary>
    public Dictionary<string, App> Voices { get; set; } = new();
    /// <summary>The deploy gate on this box (#2841), which the steps after a
    /// dev Deployment go through: the load order and plugins its records name,
    /// and the parity check. null leaves both out (a test, a deploy by tag).</summary>
    public IGate? Gate { get; set; }
    /// <summary>GitHub with a token that may open issues, for the parity
    /// check's rows; minted apart from the service's own (AppTokens.IssuesWrite).</summary>
    public GitHub? IssuesGh { get; set; }
    /// <summary>The environment the steps after a Deployment run for: the dev
    /// server, the one Deploy-DevGamemode.ps1 deploys to.</summary>
    public const string DevEnv = "dev";
    /// <summary>The files a dev server's load order and plugins are made from
    /// (Deploy-DevGamemode.ps1 -LoadOrder -FromRecord, #4069). A Deployment
    /// whose commit changes one of them moves dev's order and plugins too.</summary>
    public static readonly string[] LoadOrderPaths =
    [
        "records/collection-plugins.json",
        "records/collection-dropped.json",
        "game/data/last-plugin.json",
        "game/data/last-plugin.recipe",
        "game/content/Thornswood-Content.esp",
    ];
    public const string LoadOrderLine = "Deploy-DevGamemode -LoadOrder -FromRecord -ShipFollows";
    static readonly Regex ReviewRow = new(@"^REVIEW  (\S+) (.+?): expected (.*?), found (.*)$");
    static readonly Regex MainAt = new(@"^main at ([0-9a-f]{40})$");
    string StatePath => Path.Combine(cfg.Home, "state", "working.json");
    static readonly Regex BuildTag = new(@"^build-[A-Za-z0-9._-]{1,80}$");
    static readonly Regex AgentTag = new(@"^agent-v(\d+)\.(\d+)\.(\d+)$");

    // ---- one Release, applied -------------------------------------------------

    /// <summary>Fetches a build Release, holds it to its signature, and applies
    /// its gamemode to the environment's server: by a reload when the server
    /// runs the server build the Release records, and with that build by a
    /// stop, swap and start when it does not. expectCommit, when given, is
    /// the commit the Release must be (a Deployment's). With botPass, and a
    /// bot pass set up for the environment, nothing goes in until the bot
    /// pass passed on a throwaway copy of the server with this gamemode and
    /// the server build it goes onto (#5196). Writes the record on success.
    /// Every line goes to log.</summary>
    public async Task<Outcome> ApplyRelease(string env, string tag, string expectCommit, string workName, Action<string> logf, CancellationToken ct, bool botPass = false)
    {
        if (Apps.ContainsKey(env)) return await ApplyAppRelease(env, tag, expectCommit, workName, logf, ct);
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
            // The server build's zip is fetched only when dev does not run it
            // already: most Releases change the gamemode alone.
            try { f = await ReleaseFetch.Fetch(gh, verify, rel, dir, parts, logf, ct, optional: Voices.ContainsKey(env) ? ["server", AppKinds.Voice] : ["server"], later: IsServerZip); }
            catch (Exception e) when (e is InvalidDataException or IOException or HttpRequestException) { return new Outcome("failure", "not applied: " + e.Message); }
            var m = f.Manifest;
            // The name, not the owner: the repositories move to an
            // organization (#5184), and a Release from before the move is
            // still this repository's. The signature is what is trusted.
            if (!string.Equals(m.Repo.Split('/')[^1], cfg.Repo.Split('/')[^1], StringComparison.OrdinalIgnoreCase))
                return new Outcome("failure", $"not applied: the Release was built from {m.Repo}, not {cfg.Repo}");
            if (expectCommit != "" && m.Commit != expectCommit)
                return new Outcome("failure", $"not applied: the Release is commit {Short(m.Commit)} and the Deployment is {Short(expectCommit)}");
            var others = m.Parts.Keys.Where(k => !parts.Contains(k) && k != "server" && !(k == AppKinds.Voice && Voices.ContainsKey(env))).OrderBy(k => k, StringComparer.Ordinal).ToList();
            if (others.Count > 0) logf($"the Release also carries {string.Join(", ", others)}, which this agent does not apply yet; left alone");
            logf($"release {rel.TagName}, commit {m.Commit}");
            var who = $"the deploy agent, {workName}";
            // A Release carries the server build its commit records, so a
            // gamemode never goes onto an engine it was not written for, and
            // an engine pin reaches dev with the gamemode beside it. Which
            // build dev will run is settled first, so the bot pass checks the
            // gamemode on that build and not on the one it replaces.
            string? swapZip = null;
            byte[]? swapRecord = null;
            if (m.Parts.TryGetValue("server", out var serverPart))
            {
                if (!f.Files.TryGetValue("server-build.json", out var recPath)) return new Outcome("failure", "not applied: the Release's server part has no server-build.json");
                var zipMf = serverPart.Where(x => IsServerZip(x.Name)).ToList();
                if (zipMf.Count != 1) return new Outcome("failure", $"not applied: the Release's server part carries {zipMf.Count} server zips, not one");
                var record = File.ReadAllBytes(recPath);
                var running = srv.RunningRecordSum();
                ServerBuild.Record rec;
                try { rec = ServerBuild.Read(record); }
                catch (JsonException e) { return new Outcome("failure", "not applied: the Release's server-build.json does not read: " + e.Message); }
                if (running == ServerBuild.RecordSum(record))
                {
                    logf($"dev already runs server build {rec.Short}, the one this Release records, so only the gamemode is reloaded");
                }
                else
                {
                    logf(running == "" ? $"dev has no server-build.json, so it is given server build {rec.Short} with the gamemode"
                                       : $"dev runs another server build than {rec.Short}, the one this Release records, so the server is swapped with the gamemode under a hold");
                    try { swapZip = await ReleaseFetch.FetchFile(gh, rel, zipMf[0], f.Dir, ct); }
                    catch (Exception e) when (e is InvalidDataException or IOException or HttpRequestException) { return new Outcome("failure", "not applied: " + e.Message); }
                    logf($"server: {zipMf[0].Name}, held to the signed manifest");
                    swapRecord = record;
                }
            }
            if (pass)
            {
                logf(swapZip == null ? "the bot pass first, on a throwaway copy of the server with this gamemode (#5196)"
                                     : "the bot pass first, on a throwaway copy of the server with this gamemode and the new server build (#5196)");
                var bp = await (MakeBotPass?.Invoke(srv.Env) ?? new BotPass(srv.Env, Tasks)).Run(f.Files, logf, ct, swapZip);
                if (bp.State != "success") return bp;
                logf(bp.Summary);
            }
            else if (botPass)
            {
                logf("no bot pass: it is not set up on this box yet (Install-DeployAgent.ps1 sets it up)");
            }
            // Voice goes in before the gamemode that pushes positions to it,
            // after the bot pass, so a voice that does not answer leaves the
            // server as it was.
            var voiceIn = "";
            if (m.Parts.TryGetValue(AppKinds.Voice, out var voicePart) && Voices.TryGetValue(env, out var voice))
            {
                var vzip = AppKinds.ZipName(AppKinds.Voice);
                if (voicePart.Count != 1 || voicePart[0].Name != vzip || !f.Files.TryGetValue(vzip, out var vpath))
                    return new Outcome("failure", $"not applied: the Release's voice part is not the one file {vzip}");
                logf($"voice first, into {voice.Env.Root}");
                var vo = await voice.Apply(vpath, rel.TagName, m.Commit, $"deploy agent {version} on {Host}", logf, ct);
                if (vo.State != "success") return vo with { Summary = "voice: " + vo.Summary + "; the gamemode was not touched" };
                voiceIn = "; voice runs it too";
            }
            var outc = swapZip != null && swapRecord != null
                ? await srv.ApplyServerBuild(swapZip, swapRecord, f.Files, who, logf, ct)
                : await srv.ApplyGamemode(f.Files, who, logf, ct);
            if (outc.State != "success") return voiceIn == "" ? outc : outc with { Summary = outc.Summary + $"; voice already runs {rel.TagName}" };
            var gm = Path.Combine(srv.Env.Root, "gamemode.js");
            Records.Write(srv, new DeployRecord
            {
                Component = "gamemode",
                Name = rel.TagName,
                Commit = m.Commit,
                Sha256 = ReleaseFetch.FileSha256(gm),
                Size = new FileInfo(gm).Length,
                Files = Server.ReloadFiles.Length + (f.Files.ContainsKey(Tables.Zip) ? Tables.Count(Path.Combine(srv.Env.Root, Tables.Dir)) : 0),
                DeployedUtc = Records.UtcNow(),
                From = $"deploy agent {version} on {Host}",
            }, logf);
            return outc with { Summary = rel.TagName + ": " + outc.Summary + voiceIn };
        }
        finally
        {
            try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    /// <summary>Fetches a build Release, holds it to its signature, and puts the
    /// app's zip in (App.Apply): the site's or the Discord bot's part, one zip
    /// each (scripts/release/App-Part.ps1). expectCommit, when given, is the
    /// commit the Release must be (a Deployment's).</summary>
    public async Task<Outcome> ApplyAppRelease(string env, string tag, string expectCommit, string workName, Action<string> logf, CancellationToken ct)
    {
        var app = Apps[env];
        var kind = app.Env.Kind;
        if (!BuildTag.IsMatch(tag)) return new Outcome("failure", $"not applied: \"{tag}\" is not a build-<...> Release tag");
        Release rel;
        try { rel = await gh.ReleaseByTag(tag, ct); }
        catch (GitHubException e) when (e.Status == 404) { return new Outcome("failure", "not applied: there is no published Release " + tag); }
        catch (Exception e) when (e is GitHubException or HttpRequestException or TaskCanceledException) { return new Outcome("error", "the Release could not be read: " + e.Message); }
        var dir = Path.Combine(cfg.Home, "work", workName);
        try
        {
            var part = AppKinds.Part(kind);
            Fetched f;
            try { f = await ReleaseFetch.Fetch(gh, verify, rel, dir, [part], logf, ct); }
            catch (Exception e) when (e is InvalidDataException or IOException or HttpRequestException) { return new Outcome("failure", "not applied: " + e.Message); }
            var m = f.Manifest;
            if (!string.Equals(m.Repo.Split('/')[^1], cfg.Repo.Split('/')[^1], StringComparison.OrdinalIgnoreCase))
                return new Outcome("failure", $"not applied: the Release was built from {m.Repo}, not {cfg.Repo}");
            if (expectCommit != "" && m.Commit != expectCommit)
                return new Outcome("failure", $"not applied: the Release is commit {Short(m.Commit)} and the Deployment is {Short(expectCommit)}");
            var zipName = AppKinds.ZipName(kind);
            if (m.Parts[part].Count != 1 || !f.Files.TryGetValue(zipName, out var zip))
                return new Outcome("failure", $"not applied: the Release's {part} part is not the one file {zipName}");
            logf($"release {rel.TagName}, commit {m.Commit}");
            return await app.Apply(zip, rel.TagName, m.Commit, $"deploy agent {version} on {Host}", logf, ct);
        }
        finally
        {
            try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    /// <summary>Leaves a deploy's log where the outside can read it and hands
    /// back its address: a server's data folder, or an app's LogDir.</summary>
    string PublishLog(string env, string id, List<string> lines)
    {
        if (servers.TryGetValue(env, out var srv)) return Records.PublishLog(srv, id, lines);
        if (Apps.TryGetValue(env, out var app)) return Records.PublishLog(app.Env.LogDir, app.Env.LogBase, id, lines);
        return "";
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
        var url = PublishLog(env, id, lines);
        if (url != "") log("the log: " + url);
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

    /// <summary>The part a Deployment to an app's environment names, beside
    /// its Release (merge-release.yml); "" when it names none.</summary>
    public static string PayloadPart(JsonElement payload)
    {
        var p = payload;
        if (p.ValueKind == JsonValueKind.String)
        {
            using var d = JsonDocument.Parse(p.GetString() ?? "");
            p = d.RootElement.Clone();
        }
        return p.ValueKind == JsonValueKind.Object && p.TryGetProperty("part", out var r) && r.ValueKind == JsonValueKind.String ? r.GetString()! : "";
    }

    async Task Apply(string env, Deployment d, CancellationToken ct)
    {
        var lines = new List<string>();
        void Logf(string s) { lines.Add($"{DateTime.Now:h:mm:ss tt}  {s}"); log($"{env} deployment {d.Id}: {s}"); }
        Files.WriteWhole(StatePath, JsonSerializer.SerializeToUtf8Bytes(new Working(d.Id.ToString(), env, Records.UtcNow())));
        try
        {
            await gh.SetStatus(d.Id, "in_progress", "the deploy agent on the box is applying this", "", ct);
            Logf($"deploy agent {version} on {Host}, deployment {d.Id} of {Short(d.Sha)} by {d.Creator?.Name}");
            Outcome outc;
            var tag = "";
            if (d.Task != "" && d.Task != "deploy") outc = new Outcome("failure", $"not applied: the Deployment's task is {d.Task}, and the agent applies deploy only");
            else
            {
                try
                {
                    tag = PayloadRelease(d.Payload);
                    var part = PayloadPart(d.Payload);
                    if (Apps.TryGetValue(env, out var app) && part != "" && part != AppKinds.Part(app.Env.Kind))
                        outc = new Outcome("failure", $"not applied: the Deployment asks for the {part} part, and {env} takes {AppKinds.Part(app.Env.Kind)}");
                    else
                    {
                        outc = await ApplyRelease(env, tag, d.Sha, $"deployment-{d.Id}", Logf, ct, botPass: true);
                        if (outc.State == "success" && env == DevEnv && Gate != null) outc = await LoadOrder(env, d.Sha, outc, Logf, ct);
                    }
                }
                catch (Exception e) when (e is InvalidDataException or JsonException) { outc = new Outcome("failure", "not applied: " + e.Message); }
            }
            Logf(outc.State.ToUpperInvariant() + ": " + outc.Summary);
            var url = PublishLog(env, d.Id.ToString(), lines);
            await gh.SetStatus(d.Id, outc.State, outc.Summary, url, ct);
            if (outc.State == "success") await LeaveNews(env, tag, d, ct);
            // The parity check reads the box as it is now, so it runs once the
            // Deployment is in and said; what it finds never changes how the
            // Deployment went, and its lines join the same log.
            if (outc.State == "success" && env == DevEnv && Gate != null)
            {
                await Parity(tag, Logf, ct);
                PublishLog(env, d.Id.ToString(), lines);
            }
        }
        finally { File.Delete(StatePath); }
    }

    // ---- after a dev Deployment ------------------------------------------------

    /// <summary>A verb's lines go into the deploy log, which the dev server's
    /// resources port serves to anybody, so addresses are taken out first.</summary>
    static Action<string> Redacted(Action<string> logf) => l => logf(Server.Redact([l]).First());

    sealed record LoadOrderState(string Commit, string Moved);
    string LoadOrderPath(string env) => Path.Combine(cfg.Home, "state", $"load-order-{env}.json");

    /// <summary>The commit whose records dev's load order and plugins were
    /// last moved to by this agent, or "" when it has not done it yet.</summary>
    string LoadOrderCommit(string env)
    {
        try
        {
            var p = LoadOrderPath(env);
            return File.Exists(p) ? JsonSerializer.Deserialize<LoadOrderState>(File.ReadAllBytes(p))?.Commit ?? "" : "";
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException) { return ""; }
    }

    /// <summary>Dev's load order and plugins, moved to what the Deployment's
    /// commit records when that commit changed one of LoadOrderPaths since
    /// the last move (or when that cannot be told): the gate's
    /// Deploy-DevGamemode -LoadOrder -FromRecord, the tested path a person
    /// runs with Box-Run. The gamemode is already in when this runs, so a
    /// move that fails leaves it in and says the plugins are not.</summary>
    async Task<Outcome> LoadOrder(string env, string commit, Outcome applied, Action<string> logf, CancellationToken ct)
    {
        var since = LoadOrderCommit(env);
        if (since == commit) return applied;
        List<string>? changed = null;
        if (since != "")
        {
            try { changed = await gh.ChangedPaths(since, commit, ct); }
            catch (Exception e) when (e is GitHubException or HttpRequestException) { logf("load order: the change since " + Short(since) + " could not be read (" + e.Message + "), so it is moved to be sure"); }
        }
        var touched = changed?.Where(p => LoadOrderPaths.Contains(p, StringComparer.Ordinal)).Distinct().ToList();
        if (touched != null && touched.Count == 0)
        {
            logf($"load order: nothing it is made from changed since {Short(since)}; dev keeps its order and plugins");
            Files.WriteWhole(LoadOrderPath(env), JsonSerializer.SerializeToUtf8Bytes(new LoadOrderState(commit, Records.UtcNow())));
            return applied;
        }
        logf(since == "" ? "load order: this agent has not moved dev's order yet, so it is moved to this commit's records"
            : touched == null ? $"load order: what changed since {Short(since)} is not known in full, so dev's order and plugins are moved to this commit's records"
            : $"load order: {string.Join(", ", touched)} changed since {Short(since)}, so dev's order and plugins are moved to this commit's records");
        logf("load order: the gate's " + LoadOrderLine);
        // The gate runs one verb at a time; a verb already running is waited
        // for (up to its 45 minutes and a little more) by the connect.
        var run = await Gate!.Run(LoadOrderLine, TimeSpan.FromMinutes(50), Redacted(logf), ct);
        if (run.Code != 0)
            return new Outcome("failure", $"{applied.Summary}; but the plugins are not: the load order move ended with {run.Code}, the log says why");
        var at = run.Lines.Select(l => MainAt.Match(l)).FirstOrDefault(m => m.Success)?.Groups[1].Value ?? commit;
        if (at != commit) logf($"load order: the gate ran main at {Short(at)}, after this Deployment's {Short(commit)}; dev has that commit's order and gamemode until its own Deployment");
        Files.WriteWhole(LoadOrderPath(env), JsonSerializer.SerializeToUtf8Bytes(new LoadOrderState(at, Records.UtcNow())));
        return applied with { Summary = applied.Summary + "; load order moved" };
    }

    /// <summary>The parity check (Check-ProdParity through the gate) once dev
    /// has the Deployment, and one issue labelled parity for each row it
    /// says to review that has no open issue by the same title. What it
    /// finds is said in the log; it never changes how the Deployment went.</summary>
    async Task Parity(string tag, Action<string> logf, CancellationToken ct)
    {
        logf("parity: Check-ProdParity through the gate");
        var run = await Gate!.Run("Check-ProdParity", TimeSpan.FromMinutes(20), Redacted(logf), ct);
        if (run.Code != 0) { logf($"parity: Check-ProdParity ended with {run.Code}, so nothing was filed"); return; }
        var rows = run.Lines.Select(l => ReviewRow.Match(l)).Where(m => m.Success).ToList();
        if (rows.Count == 0) { logf("parity: every row is as records/prod-parity.json says"); return; }
        if (IssuesGh == null) { logf($"parity: {rows.Count} row(s) to review, and no token here that may open issues, so none was filed"); return; }
        try
        {
            await IssuesGh.EnsureLabel("parity", "c5def5", "Check-ProdParity found the box not as records/prod-parity.json says", ct);
            var open = new HashSet<string>(await IssuesGh.OpenIssueTitles("parity", ct), StringComparer.Ordinal);
            foreach (var m in rows)
            {
                var r = Server.Redact([m.Groups[1].Value, m.Groups[2].Value, m.Groups[3].Value, m.Groups[4].Value]).ToArray();
                var title = $"Parity: {r[0]} {r[1]} differs on the box";
                if (title.Length > 200) title = title[..197] + "...";
                if (!open.Add(title)) { logf("parity: already open: " + title); continue; }
                var body = $"Check-ProdParity, run by the deploy agent after {tag} reached dev, found {r[0]} {r[1]} on the box not as records/prod-parity.json says.\n" +
                           $"Expected: {r[2]}\nFound: {r[3]}\n" +
                           "Either the record is out of date (fix records/prod-parity.json) or the box needs the script that owns this run, never a hand edit.\n" +
                           "Done when Check-ProdParity no longer lists this row to review.";
                await IssuesGh.OpenIssue(title, body, "parity", ct);
                logf("parity: filed " + title);
            }
        }
        catch (Exception e) when (e is GitHubException or HttpRequestException or TaskCanceledException or InvalidOperationException or InvalidDataException or JsonException)
        {
            logf("parity: THE ROWS WERE NOT ALL FILED: " + e.Message);
        }
    }

    /// <summary>The news of the Release a Deployment put in, for the bot
    /// (News). Its notes are read again here: a Release's body is not part
    /// of what is signed, and is what GitHub shows as its notes now. A
    /// failure is said in the agent's log and changes nothing deployed.</summary>
    async Task LeaveNews(string env, string tag, Deployment d, CancellationToken ct)
    {
        var store = servers.TryGetValue(env, out var srv) ? srv.Env.Store : Apps.TryGetValue(env, out var app) ? app.Env.Store : "";
        void Logf(string s) => log($"{env} deployment {d.Id}: {s}");
        try { News.Write(store, env, await gh.ReleaseByTag(tag, ct), d.Sha, Logf); }
        catch (Exception e) when (e is GitHubException or HttpRequestException or TaskCanceledException or JsonException)
        {
            Logf($"THE NEWS OF {tag} WAS NOT LEFT FOR THE BOT: the Release could not be read again ({e.Message})");
        }
    }

    static string Short(string s) => s.Length > 12 ? s[..12] : s;

    /// <summary>The server build's zip, as ServerArtifact.ps1 names it: server-&lt;commit&gt;-&lt;sum&gt;.zip.</summary>
    static bool IsServerZip(string name) => name.StartsWith("server-", StringComparison.Ordinal) && name.EndsWith(".zip", StringComparison.Ordinal);

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
        string? newest = null;
        var bestV = own;
        foreach (var t in await gh.TagNames("agent-v", ct))
        {
            var m = AgentTag.Match(t);
            if (!m.Success) continue;
            var v = ParseVersion($"{m.Groups[1]}.{m.Groups[2]}.{m.Groups[3]}")!;
            if (Newer(v, bestV)) { newest = t; bestV = v; }
        }
        if (newest == null) return;
        // The tag lookup answers with published Releases only. A newer tag with
        // none (its Release taken down, or a tag somebody pushed by hand) is
        // said and left; this agent stays as it is.
        Release best;
        try { best = await gh.ReleaseByTag(newest, ct); }
        catch (GitHubException e) when (e.Status == 404)
        {
            log($"agent tag {newest} has no published Release; staying on {version}");
            return;
        }
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
            if (Apps.TryGetValue(env, out var app))
            {
                var down = await app.Unhealthy(ct);
                if (down != "") { log($"{env}: {down}"); ok = false; }
                else log($"{env}: " + (e.Kind == AppKinds.Discord ? $"the service {e.Service} is running" : $"{e.Health} answers"));
                continue;
            }
            var sick = await servers[env].Unhealthy(ct);
            if (sick != "") { log($"{env}: {sick}"); ok = false; }
            else log($"{env}: {e.Health} answers 200");
            if (Voices.TryGetValue(env, out var voice))
            {
                var hush = await voice.Unhealthy(ct);
                if (hush != "") { log($"{env} voice: {hush}"); ok = false; }
                else log($"{env} voice: {voice.Env.Health} answers with the build in {voice.Env.Root}");
            }
        }
        return ok;
    }
}
