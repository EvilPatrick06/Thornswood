#nullable enable
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Thornswood.DeployAgent;

/// <summary>How an apply went, in the words a Deployment status takes:
/// success; failure (refused or did not take, and the server runs what it ran
/// before); error (the server may not run what it ran before, or the agent
/// could not finish).</summary>
public sealed record Outcome(string State, string Summary, string Blob = "", string Prev = "");

/// <summary>One game server folder the agent applies a gamemode to.</summary>
public sealed class Server(EnvConfig env, HttpClient http)
{
    public EnvConfig Env => env;
    public TimeSpan Tick { get; set; } = TimeSpan.FromMilliseconds(500);
    public Func<DateTime> Now { get; set; } = () => DateTime.Now;

    /// <summary>The files a reload puts in, in order: the stamp first, so the
    /// gamemode is never loaded beside a stamp naming the one before it.</summary>
    public static readonly string[] ReloadFiles = ["thornswood-build.json", "gamemode.js"];

    string Root => env.Root;

    JsonElement Settings()
    {
        var text = File.ReadAllText(Path.Combine(Root, "server-settings.json")).TrimStart('﻿');
        using var d = JsonDocument.Parse(text);
        return d.RootElement.Clone();
    }

    /// <summary>Where the server keeps what it serves on its resources port.</summary>
    public string DataDir()
    {
        var d = "data";
        try { if (Settings().TryGetProperty("dataDir", out var v) && v.GetString() is { Length: > 0 } s) d = s; } catch (Exception e) when (e is IOException or JsonException) { }
        return Path.IsPathRooted(d) ? d : Path.Combine(Root, d);
    }

    /// <summary>Asks the health address once. The game server serves it from
    /// the process that loads the gamemode, so a 200 says that process runs and
    /// answers (Watch-Services.ps1 asks the same address).</summary>
    public async Task<string> Unhealthy(CancellationToken ct)
    {
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(15));
            using var res = await http.GetAsync(env.Health, cts.Token);
            return (int)res.StatusCode == 200 ? "" : $"{env.Health} answered HTTP {(int)res.StatusCode}";
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            return $"{env.Health} did not answer: {e.Message}";
        }
    }

    /// <summary>Why this server cannot take a reload, touching nothing, or ""
    /// when it can. The checks Reload.ps1 and Deploy-DevGamemode.ps1 make.</summary>
    async Task<string> Refusal(Action<string> log, CancellationToken ct)
    {
        JsonElement st;
        try { st = Settings(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return "the server's settings do not read: " + e.Message; }
        var port = st.TryGetProperty("port", out var p) && p.ValueKind == JsonValueKind.Number ? p.GetInt32() : 0;
        if (env.LivePort != 0 && port == env.LivePort) return $"{Root} is on port {port}, which is the live server";
        var gp = "gamemode.js";
        if (Directory.Exists(Path.Combine(Root, "skymp5-gamemode"))) gp = Path.Combine("skymp5-gamemode", "gamemode.js");
        if (st.TryGetProperty("gamemodePath", out var g) && g.GetString() is { Length: > 0 } gs) gp = gs;
        if (!Path.IsPathRooted(gp)) gp = Path.Combine(Root, gp);
        if (Path.GetFullPath(gp) != Path.GetFullPath(Path.Combine(Root, "gamemode.js")))
            return $"the server loads its gamemode from {gp}, not {Path.Combine(Root, "gamemode.js")}";
        var engine = Path.Combine(Root, "dist_back", "skymp5-server.js");
        try
        {
            if (!File.ReadAllText(engine).Contains("[thornswood] gamemode did not load; the error is above"))
                return "the engine on the box does not say how a gamemode load went (it needs the fork from Thornswood #3196)";
        }
        catch (IOException e) { return $"the engine at {engine} does not read: {e.Message}"; }
        var sick = await Unhealthy(ct);
        if (sick != "")
        {
            log("health: " + sick);
            return "the server does not answer its health address, so it is not running; the agent reloads a running server only";
        }
        return "";
    }

    /// <summary>Puts a new gamemode.js and its stamp into a running server and
    /// holds the server to loading it, the way Reload.ps1 does:
    ///  - the server folders' turn first (#3247), held to the end;
    ///  - what it replaces is copied into &lt;root&gt;\.prev-&lt;stamp&gt; (gamemode.js,
    ///    thornswood-build.json, server-settings.json and the deploy record),
    ///    the set a swap keeps, so Deploy-DevGamemode.ps1 -PutBack puts it back;
    ///  - each new file is staged in &lt;root&gt;\.agent-stage-&lt;stamp&gt; and moved
    ///    over the old one in one rename, stamp first;
    ///  - server.log has to say the new blob loaded, then the health address
    ///    has to answer;
    ///  - when either does not happen the old files go back the same way and
    ///    the old blob has to load again. Only if that fails too is the server
    ///    left for a restart, which this slice does not make, and it says so.</summary>
    public async Task<Outcome> ApplyGamemode(IReadOnlyDictionary<string, string> files, string who, Action<string> log, CancellationToken ct)
    {
        foreach (var n in ReloadFiles)
            if (!files.ContainsKey(n)) return new Outcome("failure", "the Release's gamemode part has no " + n);
        var why = await Refusal(log, ct);
        if (why != "") return new Outcome("failure", "not applied: " + why);
        Turn turn;
        try { turn = Turn.Take(env.Turn, who, TimeSpan.FromSeconds(env.TurnSeconds), log); }
        catch (Exception e) when (e is TimeoutException or IOException or UnauthorizedAccessException) { return new Outcome("failure", "not applied: " + e.Message); }
        using var _ = turn;

        var stamp = Now().ToString("yyyyMMdd-HHmmss");
        var prevName = ".prev-" + stamp;
        var prev = Path.Combine(Root, prevName);
        // Not .stage-*: Deploy-DevGamemode.ps1 clears every .stage-* it finds
        // before it takes the turn. Inside the root, so a file moved in carries
        // the root's permissions, which the server's account reads.
        var stage = Path.Combine(Root, ".agent-stage-" + stamp);
        var gm = Path.Combine(Root, "gamemode.js");

        try
        {
            foreach (var rel in ReloadFiles.Append("server-settings.json"))
            {
                var at = Path.Combine(Root, rel);
                if (File.Exists(at)) Files.Copy(at, Path.Combine(prev, rel));
            }
            var rec = Path.Combine(DataDir(), "thornswood-deploy.json");
            var relRec = Path.GetRelativePath(Root, rec);
            if (!relRec.StartsWith("..") && File.Exists(rec)) Files.Copy(rec, Path.Combine(prev, relRec));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            TryDelete(prev);
            return new Outcome("failure", $"not applied: the running files could not be kept in {prevName}: {e.Message}");
        }
        try
        {
            foreach (var rel in ReloadFiles) Files.Copy(files[rel], Path.Combine(stage, rel));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            TryDelete(stage);
            return new Outcome("failure", "not applied: the new files could not be staged: " + e.Message, Prev: prevName);
        }

        var oldBlob = Files.GamemodeBlob(gm);
        var newBlob = Files.GamemodeBlob(Path.Combine(stage, "gamemode.js"));
        var changes = oldBlob != newBlob;
        log($"the running gamemode is git blob {oldBlob}; it and its stamp are kept in {prevName}");

        var sl = new ServerLog(Root);
        sl.Mark();
        var placed = new List<string>();
        why = "";
        foreach (var rel in ReloadFiles)
        {
            try { File.Move(Path.Combine(stage, rel), Path.Combine(Root, rel), true); placed.Add(rel); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { why = $"could not put the new {rel} in place: {e.Message}"; break; }
        }
        var wait = TimeSpan.FromSeconds(env.LoadSeconds);
        if (why == "" && !changes) log($"the server already runs git blob {newBlob}, so it has nothing to load; the stamp is the new one");
        if (why == "" && changes)
        {
            log($"put in git blob {newBlob}, waiting up to {env.LoadSeconds} seconds for server.log to say it loaded");
            var (got, said) = sl.AwaitLoad(newBlob, wait, Tick);
            foreach (var l in Redact(said)) log("  " + l);
            if (got != "") why = "the new gamemode did not take: " + got;
        }
        if (why == "")
        {
            var sick = await Unhealthy(ct);
            if (sick != "") why = "the health check failed after the load: " + sick;
            else log($"health: {env.Health} answers 200");
        }
        if (why == "")
        {
            TryDelete(stage);
            PruneOld(log);
            return new Outcome("success", $"dev runs gamemode blob {newBlob[..12]}, reloaded with nobody dropped", newBlob, prevName);
        }

        // The way back: the old files from their copies in .prev, through the
        // stage, in the reverse order, and the old gamemode has to load again.
        log(why);
        if (changes && placed.Count > 0)
        {
            log("--- server.log since the new gamemode went in, last lines ---");
            foreach (var l in Redact(sl.Tail)) log("  " + l);
        }
        log("putting the previous files back");
        var clean = true;
        sl.Mark();
        for (int i = placed.Count - 1; i >= 0; i--)
        {
            var rel = placed[i];
            var kept = Path.Combine(prev, rel);
            if (!File.Exists(kept)) continue;
            try
            {
                Files.Copy(kept, Path.Combine(stage, rel));
                File.Move(Path.Combine(stage, rel), Path.Combine(Root, rel), true);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                log($"COULD NOT PUT THE OLD {rel} BACK: {e.Message}");
                clean = false;
            }
        }
        TryDelete(stage);
        if (clean)
        {
            var now = Files.GamemodeBlob(gm);
            if (now != oldBlob) { log($"gamemode.js is git blob {now} after the put-back, not the old {oldBlob}"); clean = false; }
            else if (changes && placed.Contains("gamemode.js"))
            {
                log($"the old gamemode is back on disk, waiting up to {env.LoadSeconds} seconds for the server to load it");
                var (got, said) = sl.AwaitLoad(oldBlob, wait, Tick);
                foreach (var l in Redact(said)) log("  " + l);
                if (got != "") { log("the old gamemode did not take either: " + got); clean = false; }
            }
        }
        return clean
            ? new Outcome("failure", Trim(why) + "; the previous gamemode is back and loaded", oldBlob, prevName)
            : new Outcome("error", Trim(why) + "; putting the old one back did not take either, so dev needs Deploy-DevGamemode.ps1 -PutBack", Prev: prevName);
    }

    static string Trim(string s) => s.Length > 90 ? s[..87] + "..." : s;

    static void TryDelete(string dir)
    {
        try { if (Directory.Exists(dir)) Directory.Delete(dir, true); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    /// <summary>Keeps the newest two .prev and .undone folders, as a swap and a reload do.</summary>
    void PruneOld(Action<string> log)
    {
        foreach (var kind in new[] { ".prev-", ".undone-" })
        {
            var names = Directory.EnumerateDirectories(Root).Select(Path.GetFileName).Where(n => n!.StartsWith(kind))
                .OrderByDescending(n => n, StringComparer.Ordinal).Skip(2);
            foreach (var n in names)
            {
                try { Directory.Delete(Path.Combine(Root, n!), true); }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException) { log($"PRUNE FAILED: could not remove {n}, one of the old copies past the newest 2: {e.Message}"); }
            }
        }
    }

    static readonly Regex Ipv4 = new(@"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d+)?\b");

    /// <summary>Takes network addresses out of server.log lines before they go
    /// in a log anybody can read: who connects from where stays on the box.</summary>
    public static IEnumerable<string> Redact(IEnumerable<string> lines) => lines.Select(l => Ipv4.Replace(l, "<address>"));
}
