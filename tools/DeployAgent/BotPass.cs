#nullable enable
// The bot pass a dev Deployment waits on (#5196). Before the agent puts a
// new gamemode on dev, it makes a throwaway copy of the dev server with that
// gamemode, in a folder of its own on ports of its own, and starts the
// scheduled task "Thornswood Bot Pass", which runs scripts/bot/Bot-Pass.js
// from the same signed Release in that copy. The task runs as LOCAL SERVICE
// with a SID of its own and rights in its own folder only, like the game
// servers (scripts/deploy/ServiceAccount.ps1), at below normal priority, so
// the gamemode and the engine run there with no more reach than dev's own
// server has, and the agent itself never runs node or loads the engine. The
// agent only reads the result the task wrote. A FAIL there, or a pass that
// does not end in time, fails the Deployment and dev keeps what it runs.
//
// What goes into the copy, and what never does:
//  - the engine (dist_back, scam_native.node, package.json, the DLLs beside
//    it) from dev's folder, and gamemode.js and its stamp from the Release,
//    with the gamemode's tables folder (#5191): the Release's, else dev's;
//  - dev's data folder, which the server serves to anybody on its resources
//    port, so nothing in it is private; but not the plugins and archives,
//    which are read where they are kept for the bot pass (plugins\, copied
//    from dev's only when they change) by their full paths;
//  - dev's settings with the keys that reach outside taken out
//    (discordAuth, metricsAuth, masterKey, additionalServerSettings), no
//    master server, offline login, no join pass hold, a password of its own,
//    and ports from 7900 that nothing else holds;
//  - never dev's world, its private folder (door.json and the join pass key),
//    its logs or its deploy records. The world starts empty.
// docs/DEPLOY-AGENT.md has the whole design.
using System.Diagnostics;
using System.Net.NetworkInformation;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Thornswood.DeployAgent;

/// <summary>What Task Scheduler says about a task.</summary>
public sealed record TaskInfo(string State, DateTime LastRun, int LastResult);

/// <summary>Starts and reads a scheduled task. On the box it is WindowsTasks;
/// a test stands one in.</summary>
public interface ITasks
{
    void Start(string name);
    TaskInfo Info(string name);
    void End(string name);
}

/// <summary>Task Scheduler through Windows PowerShell's ScheduledTasks
/// module, the way the installers register the tasks.</summary>
public sealed class WindowsTasks : ITasks
{
    static string Ps(string command, string task)
    {
        var ps = Path.Combine(System.Environment.GetFolderPath(System.Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
        var psi = new ProcessStartInfo(ps, ["-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference = 'Stop'; " + command])
        { RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false };
        psi.Environment["TW_TASK"] = task;
        using var p = Process.Start(psi) ?? throw new InvalidOperationException("Windows PowerShell did not start");
        var outText = p.StandardOutput.ReadToEnd().Trim();
        var err = p.StandardError.ReadToEnd().Trim();
        p.WaitForExit();
        if (p.ExitCode != 0) throw new InvalidOperationException($"the task {task}: {(err != "" ? err : outText)}");
        return outText;
    }

    public void Start(string name) => Ps("Start-ScheduledTask -TaskName $env:TW_TASK", name);

    public void End(string name) => Ps("Stop-ScheduledTask -TaskName $env:TW_TASK", name);

    public TaskInfo Info(string name)
    {
        var said = Ps("$t = Get-ScheduledTask -TaskName $env:TW_TASK; $i = $t | Get-ScheduledTaskInfo; " +
                      "'{0}|{1}|{2}' -f $t.State, $i.LastRunTime.ToUniversalTime().ToString('o'), $i.LastTaskResult", name);
        var p = said.Split('|');
        if (p.Length != 3) throw new InvalidOperationException($"the task {name}: Task Scheduler said \"{said}\"");
        var last = DateTime.TryParse(p[1], null, System.Globalization.DateTimeStyles.RoundtripKind, out var t) ? t.ToUniversalTime() : DateTime.MinValue;
        return new TaskInfo(p[0], last, int.TryParse(p[2], out var r) ? r : -1);
    }
}

/// <summary>One line of a pass, as Bot-Pass.js wrote it.</summary>
public sealed class PassLine
{
    public string Step { get; set; } = "";
    public bool Ok { get; set; }
    public string Detail { get; set; } = "";
}

public sealed class PassResult
{
    public int Schema { get; set; }
    public bool Ok { get; set; }
    public List<PassLine> Lines { get; set; } = new();
    public string Blob { get; set; } = "";
    public List<string> Tail { get; set; } = new();
}

public sealed class BotPass(EnvConfig env, ITasks tasks)
{
    /// <summary>The file of the bot part the task runs. The rest of the part
    /// is whatever that file needs beside it, and the copy takes the part
    /// whole, so the bot can carry more (the voice service it joins, #5196)
    /// without this agent having to know each file by name.</summary>
    public const string Runs = "Bot-Pass.js";

    /// <summary>Settings that reach outside the box or hold a secret, which a
    /// throwaway copy has no use for.</summary>
    public static readonly string[] Dropped = ["discordAuth", "metricsAuth", "masterKey", "additionalServerSettings", "gamemodePath"];

    static readonly string[] FiveMasters = ["Skyrim.esm", "Update.esm", "Dawnguard.esm", "HearthFires.esm", "Dragonborn.esm"];
    static readonly string[] GameFileKinds = [".esm", ".esp", ".esl", ".bsa"];
    /// <summary>What the agent and the server write in a data folder, which
    /// the copy makes for itself or has no use for.</summary>
    static bool AgentOrServerMade(string name) =>
        name.Equals("manifest.json", StringComparison.OrdinalIgnoreCase) ||
        name.Equals("thornswood-deploy.json", StringComparison.OrdinalIgnoreCase) ||
        (name.StartsWith("deploy-", StringComparison.OrdinalIgnoreCase) && name.EndsWith(".log", StringComparison.OrdinalIgnoreCase));

    public TimeSpan Tick { get; set; } = TimeSpan.FromSeconds(2);
    /// <summary>The ports in use on this machine: UDP, then TCP. A test stands one in.</summary>
    public Func<(HashSet<int> udp, HashSet<int> tcp)> InUse { get; set; } = () =>
    {
        var ip = IPGlobalProperties.GetIPGlobalProperties();
        return (ip.GetActiveUdpListeners().Select(e => e.Port).ToHashSet(), ip.GetActiveTcpListeners().Select(e => e.Port).ToHashSet());
    };

    public string Root => env.BotPassRoot;
    public string RunDir => Path.Combine(Root, "run");
    public string ServerDir => Path.Combine(RunDir, "server");
    public string BotDir => Path.Combine(RunDir, "bot");
    public string ResultPath => Path.Combine(RunDir, "result.json");
    public string PluginDir => Path.Combine(Root, "plugins");

    /// <summary>Makes the copy, runs the task, reads what it wrote. files are
    /// the Release's gamemode and bot parts, each held to the signed manifest;
    /// bot names the files of the bot part, which go into the copy's bot
    /// folder, every one of them.
    /// serverZip, when given, is the server build the Deployment swaps dev
    /// onto (#5219), held to the signed manifest too: the copy runs that
    /// engine and not dev's, so the pass checks what dev will run.</summary>
    public async Task<Outcome> Run(IReadOnlyDictionary<string, string> files, IReadOnlyCollection<string> bot, Action<string> log, CancellationToken ct, string? serverZip = null)
    {
        if (!bot.Contains(Runs)) return new Outcome("failure", $"not applied: the Release's bot part has no {Runs}, and dev's deploys wait on the bot pass");
        foreach (var n in bot.Concat(Server.ReloadFiles))
            if (!files.ContainsKey(n)) return new Outcome("failure", $"not applied: the Release has no {n}, and dev's deploys wait on the bot pass");
        string why;
        using (var turn = TakeTurn(log, out why))
        {
            if (turn == null) return new Outcome("failure", "not applied: " + why);
            try { why = Prepare(files, bot, log, serverZip); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException) { why = e.Message; }
        }
        if (why != "") return new Outcome("failure", "not applied: the bot pass copy could not be made: " + why);

        var started = DateTime.UtcNow;
        try { tasks.Start(env.BotPassTask); }
        catch (InvalidOperationException e) { return new Outcome("failure", "not applied: the bot pass did not start: " + e.Message); }
        log($"the task {env.BotPassTask} started; waiting up to {env.BotPassSeconds} s for it to end");

        var deadline = started + TimeSpan.FromSeconds(env.BotPassSeconds);
        TaskInfo info;
        while (true)
        {
            try { info = tasks.Info(env.BotPassTask); }
            catch (InvalidOperationException e) { return new Outcome("failure", "not applied: the bot pass could not be read: " + e.Message); }
            // Ended: Task Scheduler has a run that began at or after the start
            // (its times are to the second) and it is not running now.
            if (info.State is not ("Running" or "Queued") && info.LastRun >= started.AddSeconds(-1)) break;
            if (DateTime.UtcNow > deadline)
            {
                try { tasks.End(env.BotPassTask); log("the bot pass was still running at its time limit and was stopped"); }
                catch (InvalidOperationException e) { log("the bot pass was still running at its time limit and could not be stopped: " + e.Message); }
                return new Outcome("failure", $"not applied: the bot pass did not end within {env.BotPassSeconds} s");
            }
            try { await Task.Delay(Tick, ct); } catch (OperationCanceledException) { tasks.End(env.BotPassTask); throw; }
        }

        PassResult? r = null;
        try
        {
            var fi = new FileInfo(ResultPath);
            if (fi.Exists && fi.Length <= 1 << 20) r = JsonSerializer.Deserialize<PassResult>(Files.ReadShared(ResultPath), new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            else if (fi.Exists) why = "its result.json is over 1 MB";
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { why = "its result.json does not read: " + e.Message; }
        if (r == null || r.Schema != 1)
        {
            why = why != "" ? why : r == null ? "it wrote no result.json" : $"its result.json is schema {r.Schema}, and this agent reads 1";
            return new Outcome("failure", $"not applied: the bot pass ended (Task Scheduler says {info.LastResult}) and {why}; its log is {Path.Combine(ServerDir, "bot-pass-server.log")}");
        }
        // Network addresses stay on the box, as in a server log (Server.Redact).
        foreach (var l in r.Lines) l.Detail = Server.Redact([l.Detail]).First();
        foreach (var l in r.Lines) log($"  {(l.Ok ? "PASS" : "FAIL")}  {l.Step}: {l.Detail}");
        var bad = r.Lines.FirstOrDefault(l => !l.Ok);
        if (r.Ok && bad == null && r.Lines.Count > 0)
            return new Outcome("success", $"bot pass: {r.Lines.Count} of {r.Lines.Count} passed");
        log("--- the copy's server said, last lines ---");
        foreach (var l in Server.Redact(r.Tail)) log("  " + l);
        return new Outcome("failure", bad != null ? $"not applied: the bot pass failed at {bad.Step}: {bad.Detail}" : "not applied: the bot pass says it failed and names no step");
    }

    Turn? TakeTurn(Action<string> log, out string why)
    {
        why = "";
        try { return Turn.Take(env.Turn, "the deploy agent's bot pass copy", TimeSpan.FromSeconds(env.TurnSeconds), log); }
        catch (Exception e) when (e is TimeoutException or IOException or UnauthorizedAccessException) { why = e.Message; return null; }
    }

    /// <summary>The copy, made fresh: "" when it is ready, else why not.</summary>
    public string Prepare(IReadOnlyDictionary<string, string> files, IReadOnlyCollection<string> bot, Action<string> log, string? serverZip = null)
    {
        if (!Directory.Exists(RunDir)) return $"{RunDir} is not there; Install-DeployAgent.ps1 makes it with the task";
        // The folder stays, with the rights the installer gave the task on it;
        // what is in it is the last pass's and goes.
        foreach (var d in Directory.EnumerateDirectories(RunDir)) Directory.Delete(d, true);
        foreach (var f in Directory.EnumerateFiles(RunDir)) File.Delete(f);

        var dev = env.Root;
        var settings = JsonNode.Parse(File.ReadAllText(Path.Combine(dev, "server-settings.json")).TrimStart('﻿'))?.AsObject()
            ?? throw new InvalidDataException("dev's server-settings.json is not an object");

        // The engine: dev's, or the server build the Deployment swaps dev
        // onto, whose fork files (data\scripts among them) go in after the
        // data folder below.
        if (serverZip == null)
        {
            foreach (var name in new[] { "scam_native.node", "package.json" })
            {
                var at = Path.Combine(dev, name);
                if (File.Exists(at)) Files.Copy(at, Path.Combine(ServerDir, name));
                else if (name == "scam_native.node") return "dev has no scam_native.node";
            }
            var back = Path.Combine(dev, "dist_back");
            if (!File.Exists(Path.Combine(back, "skymp5-server.js"))) return "dev has no dist_back\\skymp5-server.js";
            CopyTree(back, Path.Combine(ServerDir, "dist_back"), _ => true);
        }
        foreach (var dll in Directory.EnumerateFiles(dev, "*.dll")) Files.Copy(dll, Path.Combine(ServerDir, Path.GetFileName(dll)));
        foreach (var n in Server.ReloadFiles) Files.Copy(files[n], Path.Combine(ServerDir, n));
        foreach (var n in bot) Files.Copy(files[n], Path.Combine(BotDir, n));
        // The tables the gamemode reads beside it (#5191): the Release's, or,
        // when it carries none, dev's own, which the Deployment leaves in place.
        var devTables = Path.Combine(dev, Tables.Dir);
        if (files.TryGetValue(Tables.Zip, out var tablesZip)) Tables.Expand(tablesZip, Path.Combine(ServerDir, Tables.Dir));
        else if (Directory.Exists(devTables)) Tables.CopyDir(devTables, Path.Combine(ServerDir, Tables.Dir));

        // The data folder, without the game files, which are read where the
        // bot pass keeps them.
        var dataSetting = settings["dataDir"]?.GetValue<string>() ?? "data";
        var devData = Path.IsPathRooted(dataSetting) ? dataSetting : Path.Combine(dev, dataSetting);
        if (!Directory.Exists(devData)) return $"dev's data folder {devData} is not there";
        var devScripts = Path.Combine(devData, "scripts") + Path.DirectorySeparatorChar;
        CopyTree(devData, Path.Combine(ServerDir, "data"), f =>
            !GameFileKinds.Contains(Path.GetExtension(f).ToLowerInvariant()) && !AgentOrServerMade(Path.GetFileName(f)) &&
            !(serverZip != null && f.StartsWith(devScripts, StringComparison.OrdinalIgnoreCase)));
        if (serverZip != null)
        {
            var sums = ServerBuild.Expand(serverZip, ServerDir, out _);
            if (!sums.ContainsKey("scam_native.node") || !sums.ContainsKey("dist_back/skymp5-server.js"))
                return "the new server build has no scam_native.node or dist_back\\skymp5-server.js";
            log($"the copy runs the new server build ({sums.Count} fork file(s)), not dev's");
        }

        string Resolve(string entry) => Path.IsPathRooted(entry) || entry.Contains(":\\") ? entry : Path.Combine(devData, entry);
        var order = settings["loadOrder"] is JsonArray lo ? lo.Select(x => x!.GetValue<string>()).ToList() : FiveMasters.ToList();
        var copied = 0;
        var placed = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        string Cache(string entry, string what)
        {
            var from = Resolve(entry);
            var name = Path.GetFileName(from.Replace('\\', '/').TrimEnd('/'));
            if (!File.Exists(from)) throw new InvalidDataException($"{entry} is in dev's {what} but not on disk at {from}");
            if (placed.TryGetValue(name, out var other) && !string.Equals(other, from, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"dev's {what} names two files called {name} ({other} and {from})");
            placed[name] = from;
            var to = Path.Combine(PluginDir, name);
            var src = new FileInfo(from);
            var have = new FileInfo(to);
            if (!have.Exists || have.Length != src.Length || have.LastWriteTimeUtc != src.LastWriteTimeUtc)
            {
                Files.Copy(from, to);
                File.SetLastWriteTimeUtc(to, src.LastWriteTimeUtc);
                copied++;
            }
            return to;
        }
        var newOrder = new JsonArray();
        foreach (var p in order) newOrder.Add(Cache(p, "load order"));
        settings["loadOrder"] = newOrder;
        if (settings["archives"] is JsonArray ar)
        {
            var newAr = new JsonArray();
            foreach (var a in ar) newAr.Add(Cache(a!.GetValue<string>(), "archives"));
            settings["archives"] = newAr;
        }
        log($"the copy reads {placed.Count} plugin and archive file(s) from {PluginDir}; {copied} were new or changed on dev");

        // Its ports, away from every server's and from what is in use now.
        var (udp, tcp) = InUse();
        var reserved = new HashSet<int> { 7777, 7778, 3000, 7787, 7788, 7789 };
        foreach (var k in new[] { "port", "thornswoodVoicePort" })
            if (settings[k] is JsonValue v && v.TryGetValue<int>(out var n)) { reserved.Add(n); reserved.Add(n + 1); }
        int port = 0, voice = 0;
        for (var c = 7900; c <= 7996 && port == 0; c++)
        {
            if (reserved.Contains(c) || reserved.Contains(c + 1) || udp.Contains(c) || tcp.Contains(c) || tcp.Contains(c + 1)) continue;
            port = c;
        }
        if (port == 0) return "no free port from 7900 to 7996 for the copy";
        for (var c = port + 2; c <= 7998 && voice == 0; c++)
            if (!reserved.Contains(c) && !tcp.Contains(c)) voice = c;
        if (voice == 0) return $"no free voice port above {port}";

        foreach (var k in Dropped) settings.Remove(k);
        settings["port"] = port;
        settings["thornswoodVoicePort"] = voice;
        settings["thornswoodRequirePass"] = false;
        settings["offlineMode"] = true;
        settings["master"] = "";
        settings["password"] = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(16));
        settings["name"] = (settings["name"]?.GetValue<string>() ?? "Thornswood") + " (bot pass)";
        settings["dataDir"] = "data";
        settings["privDir"] = "private";
        settings["databaseDriver"] = "file";
        settings["databaseName"] = "world";
        Directory.CreateDirectory(Path.Combine(ServerDir, "private"));
        Files.WriteWhole(Path.Combine(ServerDir, "server-settings.json"),
            JsonSerializer.SerializeToUtf8Bytes(settings, new JsonSerializerOptions { WriteIndented = true }));
        log($"the copy is ready in {ServerDir}: game port {port}, resources {port + 1}, voice {voice}, an empty world, no private folder of dev's");
        return "";
    }

    static void CopyTree(string from, string to, Func<string, bool> take)
    {
        Directory.CreateDirectory(to);
        foreach (var f in Directory.EnumerateFiles(from))
            if (take(f)) Files.Copy(f, Path.Combine(to, Path.GetFileName(f)));
        foreach (var d in Directory.EnumerateDirectories(from))
            CopyTree(d, Path.Combine(to, Path.GetFileName(d)), take);
    }
}
