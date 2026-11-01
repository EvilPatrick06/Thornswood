#nullable enable
// The box deploy agent (#5180): a Windows service on the box that asks
// GitHub, on its own, whether a Deployment is waiting for a server it looks
// after, applies that Deployment's signed Release, checks the server is
// healthy, and says how it went on the Deployment. It only ever calls out.
//
// This first slice looks after the dev server only. It applies the gamemode
// by the reload Deploy-DevGamemode.ps1 already uses (Reload.ps1, #3196), and
// a new server build (an engine pin) by a stop, swap and start under a hold,
// the way Swap.ps1 does (#5219). The same code also deploys one Release by its tag for the deploy
// gate's Deploy-Release verb, which comes first (Patrick, 31 Oct 2026).
// docs/DEPLOY-AGENT.md has the whole design.
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Thornswood.DeployAgent;

/// <summary>agent.json in the agent's home folder. The installer writes it
/// (scripts/deploy/Install-DeployAgent.ps1) with the repository the box's
/// checkout came from, so no account name is built in (the repositories move
/// to an organization, #5184).</summary>
public sealed class Config
{
    /// <summary>owner/name of the repository whose Deployments and Releases are read.</summary>
    [JsonPropertyName("repo")] public string Repo { get; set; } = "";
    /// <summary>GitHub's REST address. A test points it at a stand-in.</summary>
    [JsonPropertyName("api")] public string Api { get; set; } = "https://api.github.com";
    /// <summary>The box admin App's state folder (app.json, key.pem; scripts/vps/admin/admin.js).</summary>
    [JsonPropertyName("adminState")] public string AdminState { get; set; } = @"C:\Thornswood-Admin\state";
    /// <summary>The agent's own folder: the program, agent.json, logs, work and state.</summary>
    [JsonPropertyName("home")] public string Home { get; set; } = @"C:\Thornswood-Agent";
    [JsonPropertyName("pollSeconds")] public int PollSeconds { get; set; } = 60;
    [JsonPropertyName("updateMinutes")] public int UpdateMinutes { get; set; } = 15;
    [JsonPropertyName("environments")] public Dictionary<string, EnvConfig> Environments { get; set; } = new();

    public static EnvConfig DefaultDev() => new()
    {
        GitHubEnvironment = "Dev server",
        Root = @"C:\Thornswood-Server-Dev",
        Turn = @"C:\Thornswood-Backup",
        Store = @"C:\Thornswood-Deploys",
        Health = "http://127.0.0.1:7788/api/servers/thornswood/manifest.json",
        // Written by the installer from scripts/vps/vps.json, the one place
        // the box's address lives; "" leaves a Deployment without a log link.
        LogBase = "",
        LoadSeconds = 300,
        TurnSeconds = 1200,
        LivePort = 7777,
        Task = "Thornswood Dev Server",
        Watch = @"C:\Thornswood-Watch",
        // ServerReadyWait.ps1: the slower of the measured starts (dev, 113 s)
        // and half again, the wait every swap gives a started server (#1938).
        StartSeconds = 170,
    };

    static readonly Regex RepoShape = new(@"^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$");

    /// <summary>Reads agent.json. Each environment it names starts from that
    /// environment's default, so the file can change one field of dev.</summary>
    public static Config Load(string path)
    {
        var c = new Config();
        using (var doc = JsonDocument.Parse(File.ReadAllText(path)))
        {
            var root = doc.RootElement;
            string Str(string name, string dflt) => root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : dflt;
            int Int(string name, int dflt) => root.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt32() : dflt;
            c.Repo = Str("repo", c.Repo);
            c.Api = Str("api", c.Api);
            c.AdminState = Str("adminState", c.AdminState);
            c.Home = Str("home", c.Home);
            c.PollSeconds = Int("pollSeconds", c.PollSeconds);
            c.UpdateMinutes = Int("updateMinutes", c.UpdateMinutes);
            if (root.TryGetProperty("environments", out var envs) && envs.ValueKind == JsonValueKind.Object)
            {
                foreach (var e in envs.EnumerateObject())
                {
                    var baseEnv = e.Name == "dev" ? DefaultDev() : new EnvConfig();
                    c.Environments[e.Name] = baseEnv.Overlay(e.Value);
                }
            }
            else
            {
                c.Environments["dev"] = DefaultDev();
            }
        }
        c.Validate();
        return c;
    }

    /// <summary>Refuses a config this slice cannot run safely.</summary>
    public void Validate()
    {
        if (!RepoShape.IsMatch(Repo)) throw new ConfigException($"repo \"{Repo}\" is not owner/name");
        if (!Api.StartsWith("https://") && !Api.StartsWith("http://127.0.0.1")) throw new ConfigException($"api \"{Api}\" is not https (only a stand-in on 127.0.0.1 may be plain http)");
        if (PollSeconds < 15) throw new ConfigException($"pollSeconds {PollSeconds} is under 15");
        if (UpdateMinutes < 1) throw new ConfigException($"updateMinutes {UpdateMinutes} is under 1");
        if (Home == "" || AdminState == "") throw new ConfigException("home and adminState must be named");
        if (Environments.Count == 0) throw new ConfigException("no environment is named, so there is nothing to look after");
        foreach (var (name, e) in Environments)
        {
            // The first slice is dev alone. Main waits on the Main environment
            // with Patrick's approval (#5181), Bot and Site on their own slices.
            if (name != "dev") throw new ConfigException($"environment \"{name}\": this agent applies dev only so far (#5180 first slice)");
            if (e.GitHubEnvironment is "" or "Dev" or "Main")
                throw new ConfigException($"environment {name}: githubEnvironment \"{e.GitHubEnvironment}\" must be named, and not Dev or Main, which hold the release records");
            if (e.Root == "" || !(Path.IsPathRooted(e.Root) || e.Root.Contains(@":\"))) throw new ConfigException($"environment {name}: root \"{e.Root}\" is not a full path");
            if (e.Health == "") throw new ConfigException($"environment {name}: no health address");
            if (e.LoadSeconds < 10 || e.TurnSeconds < 10 || e.StartSeconds < 10) throw new ConfigException($"environment {name}: loadSeconds, turnSeconds and startSeconds must be 10 or more");
            if (e.BotPassRoot != "")
            {
                if (!(Path.IsPathRooted(e.BotPassRoot) || e.BotPassRoot.Contains(@":\"))) throw new ConfigException($"environment {name}: botPassRoot \"{e.BotPassRoot}\" is not a full path");
                if (string.Equals(e.BotPassRoot.TrimEnd('\\', '/'), e.Root.TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase))
                    throw new ConfigException($"environment {name}: botPassRoot is the server's own folder, and the bot pass is a throwaway copy");
                if (e.BotPassTask == "") throw new ConfigException($"environment {name}: a bot pass needs botPassTask");
                if (e.BotPassSeconds < 60) throw new ConfigException($"environment {name}: botPassSeconds must be 60 or more");
            }
        }
    }
}

/// <summary>One server the agent looks after.</summary>
public sealed class EnvConfig
{
    /// <summary>The Deployment environment applied for this server. Not "Dev":
    /// Deployments to Dev and Main are written after a release goes out, as a
    /// record (scripts/release/Record-Deployment.ps1), and already carry a
    /// success. The agent's say what should run, so they have an environment
    /// of their own until the release workflow (#5179) makes one Deployment
    /// both and Record-Deployment retires.</summary>
    public string GitHubEnvironment { get; set; } = "";
    /// <summary>The game server's folder.</summary>
    public string Root { get; set; } = "";
    /// <summary>The folder holding server-folders.turn (#3247).</summary>
    public string Turn { get; set; } = "";
    /// <summary>The deploy record store (scripts/deploy/Artifact.ps1): current\&lt;part&gt;.json and history.log.</summary>
    public string Store { get; set; } = "";
    /// <summary>Asked over HTTP before and after a load; 200 is healthy (the watchdog's address).</summary>
    public string Health { get; set; } = "";
    /// <summary>Where the outside world reads the server's data folder, for a Deployment's log_url.</summary>
    public string LogBase { get; set; } = "";
    public int LoadSeconds { get; set; }
    public int TurnSeconds { get; set; }
    /// <summary>The live server's port: a root whose settings name it is refused.</summary>
    public int LivePort { get; set; }
    /// <summary>The bot pass's folder (#5196, BotPass.cs). "" until
    /// Install-DeployAgent.ps1 has registered its task and made the folder;
    /// from then on every Deployment waits on a bot pass.</summary>
    public string BotPassRoot { get; set; } = "";
    /// <summary>The scheduled task that runs the bot pass in that folder.</summary>
    public string BotPassTask { get; set; } = "Thornswood Bot Pass";
    /// <summary>How long a bot pass may run before it is stopped and fails.</summary>
    public int BotPassSeconds { get; set; } = 1800;
    /// <summary>The server's scheduled task, which a server build swap stops
    /// and starts (Install-ThornswoodServer.ps1 registers it). "" refuses
    /// every swap, so only a gamemode reload is done.</summary>
    public string Task { get; set; } = "";
    /// <summary>The watchdog's folder, whose holds\ a swap writes its hold in
    /// (#5155, ServerHold.ps1). "" when no watchdog runs.</summary>
    public string Watch { get; set; } = "";
    /// <summary>How long a started server has to answer on both its ports
    /// before a swap puts the old build back.</summary>
    public int StartSeconds { get; set; } = 170;

    internal EnvConfig Overlay(JsonElement e)
    {
        string S(string n, string d) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : d;
        int I(string n, int d) => e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt32() : d;
        GitHubEnvironment = S("githubEnvironment", GitHubEnvironment);
        Root = S("root", Root);
        Turn = S("turn", Turn);
        Store = S("store", Store);
        Health = S("health", Health);
        LogBase = S("logBase", LogBase);
        LoadSeconds = I("loadSeconds", LoadSeconds);
        TurnSeconds = I("turnSeconds", TurnSeconds);
        LivePort = I("livePort", LivePort);
        BotPassRoot = S("botPassRoot", BotPassRoot);
        BotPassTask = S("botPassTask", BotPassTask);
        BotPassSeconds = I("botPassSeconds", BotPassSeconds);
        Task = S("task", Task);
        Watch = S("watch", Watch);
        StartSeconds = I("startSeconds", StartSeconds);
        return this;
    }
}

public sealed class ConfigException(string message) : Exception(message);
