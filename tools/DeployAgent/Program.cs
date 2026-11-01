#nullable enable
using System.Reflection;
using System.ServiceProcess;

namespace Thornswood.DeployAgent;

/// <summary>thornswood-agent.exe. Exit codes: 0 done, 1 failed or refused,
/// 2 a usage mistake, 3 a newer signed agent is in place and the service
/// manager should start it.</summary>
public static class Program
{
    public const string ServiceName = "ThornswoodDeployAgent";

    const string Usage = """
        thornswood-agent version
        thornswood-agent check   [--config <agent.json>]
        thornswood-agent deploy  --environment dev --tag <build-...> [--config <agent.json>]
        thornswood-agent once    [--config <agent.json>]
        thornswood-agent service [--config <agent.json>]

        deploy  applies one signed Release by its tag (the deploy gate's
                Deploy-Release verb; a rollback is the Release before)
        once    one look at each environment's newest Deployment
        check   says whether the agent can do its job, and changes nothing
        service what the Windows service runs (Install-DeployAgent.ps1)
        """;

    public static string Version =>
        typeof(Program).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? "0.0.0";

    public static int Main(string[] args)
    {
        if (args.Length == 0 || args[0] is "-h" or "--help" or "help") { Console.WriteLine(Usage); return args.Length == 0 ? 2 : 0; }
        var verb = args[0];
        var opts = new Dictionary<string, string>();
        for (int i = 1; i < args.Length; i++)
        {
            if (!args[i].StartsWith("--") || i + 1 >= args.Length) { Console.Error.WriteLine($"not understood: {args[i]}\n\n{Usage}"); return 2; }
            opts[args[i][2..]] = args[++i];
        }
        foreach (var k in opts.Keys)
        {
            if (k is not ("config" or "environment" or "tag")) { Console.Error.WriteLine($"no option --{k}\n\n{Usage}"); return 2; }
        }
        if (verb == "version") { Console.WriteLine(Version); return 0; }
        if (verb is not ("check" or "deploy" or "once" or "service")) { Console.Error.WriteLine($"no command {verb}\n\n{Usage}"); return 2; }

        var exe = System.Environment.ProcessPath ?? "";
        var cfgPath = opts.GetValueOrDefault("config") ?? Path.Combine(AppContext.BaseDirectory, "agent.json");
        Config cfg;
        try { cfg = Config.Load(cfgPath); }
        catch (Exception e) when (e is ConfigException or IOException or System.Text.Json.JsonException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine($"REFUSED: {cfgPath}: {e.Message}");
            return 1;
        }

        using var logFile = new LogFile(Path.Combine(cfg.Home, "logs", "agent.log"));
        void Log(string s)
        {
            Console.WriteLine(s);
            logFile.Write(s);
        }
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(100) };
        // A deploy by tag reads Releases only, so it asks for nothing more and
        // works before the App holds Deployments (Patrick's step on the App).
        var asks = verb == "deploy" ? AppTokens.ReleasesOnly : AppTokens.Permissions;
        var gh = new GitHub(cfg.Api, cfg.Repo, new AppTokens(cfg.Api, cfg.Repo, cfg.AdminState, http, permissions: asks), http);
        var servers = cfg.Environments.ToDictionary(kv => kv.Key, kv => new Server(kv.Value, http));
        var agent = new Agent(cfg, gh, new WindowsVerifier(WindowsVerifier.BuiltInSigner), servers, Version, exe, Log);

        switch (verb)
        {
            case "check":
                return agent.Check(CancellationToken.None).GetAwaiter().GetResult() ? 0 : 1;
            case "deploy":
                {
                    var env = opts.GetValueOrDefault("environment") ?? "";
                    var tag = opts.GetValueOrDefault("tag") ?? "";
                    if (env == "" || tag == "") { Console.Error.WriteLine($"deploy needs --environment and --tag\n\n{Usage}"); return 2; }
                    var o = agent.DeployTag(env, tag, CancellationToken.None).GetAwaiter().GetResult();
                    return o.State == "success" ? 0 : 1;
                }
            case "once":
                {
                    var ok = true;
                    foreach (var env in cfg.Environments.Keys.OrderBy(k => k, StringComparer.Ordinal))
                    {
                        try { agent.Pass(env, CancellationToken.None).GetAwaiter().GetResult(); }
                        catch (Exception e) when (e is GitHubException or HttpRequestException or InvalidDataException or IOException or InvalidOperationException)
                        {
                            Log($"{env}: {e.Message}");
                            ok = false;
                        }
                    }
                    return ok ? 0 : 1;
                }
            default:
                if (!OperatingSystem.IsWindows()) { Console.Error.WriteLine("service runs on Windows only; use once to look a single time"); return 2; }
                var svc = new AgentService(agent, Log);
                ServiceBase.Run(svc);
                return svc.ExitCode;
        }
    }
}

/// <summary>The Windows service. Its work is Agent.Run on a task of its own;
/// stopping the service cancels it. When the agent has put a newer copy of
/// itself in place, the service ends with exit code 3, which the service
/// manager answers by starting it again (the failure actions
/// Install-DeployAgent.ps1 sets, with failureflag 1 so an end with an error
/// code counts).</summary>
sealed class AgentService : ServiceBase
{
    readonly Agent agent;
    readonly Action<string> log;
    readonly CancellationTokenSource stop = new();
    Task? work;

    public AgentService(Agent agent, Action<string> log)
    {
        this.agent = agent;
        this.log = log;
        ServiceName = Program.ServiceName;
        CanStop = true;
        CanShutdown = true;
    }

    protected override void OnStart(string[] args)
    {
        log($"deploy agent {Program.Version} started");
        work = Task.Run(async () =>
        {
            try
            {
                await agent.Run(stop.Token);
            }
            catch (RestartException e)
            {
                log(e.Message);
                ExitCode = 3;
                Stop();
            }
            catch (Exception e) when (e is not OperationCanceledException)
            {
                log("STOPPED: " + e);
                ExitCode = 1;
                Stop();
            }
        });
    }

    protected override void OnStop()
    {
        stop.Cancel();
        // Waiting for the loop is waiting for a deploy in hand to reach a
        // point where the server runs a gamemode that loaded; the service
        // manager is asked for that time rather than cutting it short.
        while (work != null && !work.Wait(TimeSpan.FromSeconds(20))) RequestAdditionalTime(30_000);
        log($"deploy agent stopped (exit code {ExitCode})");
    }

    protected override void OnShutdown() => OnStop();
}

/// <summary>Home\logs\agent.log, a line per thing done, with the time. At
/// 5 MB it becomes agent.log.1 and a new one starts, so it never fills the
/// disk. Two runs (the service and a gate deploy) may write at once.</summary>
sealed class LogFile : IDisposable
{
    readonly string path;
    readonly object gate = new();
    public LogFile(string path)
    {
        this.path = path;
        try { Directory.CreateDirectory(Path.GetDirectoryName(path)!); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    public void Write(string s)
    {
        lock (gate)
        {
            try
            {
                var fi = new FileInfo(path);
                if (fi.Exists && fi.Length > 5 << 20) File.Move(path, path + ".1", true);
                using var f = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
                using var w = new StreamWriter(f);
                w.Write($"{DateTime.Now:yyyy-MM-dd h:mm:ss tt}  {s}\r\n");
            }
            // The console still has the line; a log that cannot be written
            // never stops a deploy.
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    public void Dispose() { }
}
