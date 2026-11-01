#nullable enable
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Thornswood.DeployAgent;

/// <summary>The record every deploy leaves (scripts/deploy/Artifact.ps1,
/// New-ThornswoodDeployRecord), in the same shape, so the site's /api/deploys
/// and http://&lt;box&gt;:7788/thornswood-deploy.json say what the agent put in
/// exactly as they say what a deploy script put in.</summary>
public sealed class DeployRecord
{
    [JsonPropertyName("part")] public string Part { get; set; } = "";
    [JsonPropertyName("component")] public string Component { get; set; } = "";
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    [JsonPropertyName("commit")] public string Commit { get; set; } = "";
    [JsonPropertyName("sha256")] public string Sha256 { get; set; } = "";
    [JsonPropertyName("size")] public long Size { get; set; }
    [JsonPropertyName("files")] public int Files { get; set; }
    [JsonPropertyName("root")] public string Root { get; set; } = "";
    [JsonPropertyName("deployedUtc")] public string DeployedUtc { get; set; } = "";
    [JsonPropertyName("from")] public string From { get; set; } = "";
}

public static class Records
{
    static readonly Regex PartShape = new(@"^[A-Za-z0-9][A-Za-z0-9._-]*$");
    static readonly Regex LogName = new(@"^deploy-([A-Za-z0-9._-]+)\.log$");

    /// <summary>The folder's leaf in lower case, as Get-ThornswoodArtifactPart names a part.</summary>
    public static string PartName(string root)
    {
        var leaf = root.Replace('\\', '/').TrimEnd('/').Split('/')[^1];
        if (!PartShape.IsMatch(leaf)) throw new ArgumentException($"cannot name a part after the folder {root}");
        return leaf.ToLowerInvariant();
    }

    /// <summary>Leaves the record beside what the server runs, in the store's
    /// current\&lt;part&gt;.json and a line in history.log. The server already runs
    /// the new gamemode by then, so a record that cannot be written is said in
    /// the log and does not undo the deploy.</summary>
    public static void Write(Server s, DeployRecord rec, Action<string> log)
    {
        try
        {
            rec.Part = PartName(s.Env.Root);
            rec.Root = s.Env.Root.Replace('\\', '/');
            var b = JsonSerializer.SerializeToUtf8Bytes(rec, new JsonSerializerOptions { WriteIndented = true });
            Files.WriteWhole(Path.Combine(s.DataDir(), "thornswood-deploy.json"), b);
            if (s.Env.Store == "") return;
            Files.WriteWhole(Path.Combine(s.Env.Store, "current", rec.Part + ".json"), b);
            File.AppendAllText(Path.Combine(s.Env.Store, "history.log"), $"{rec.DeployedUtc} {rec.Part} {rec.Name} from {rec.From}\r\n");
            log($"the box records {rec.Part} as {rec.Name}");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException)
        {
            log("RECORD NOT WRITTEN: " + e.Message);
        }
    }

    /// <summary>Leaves a deploy's log in the server's data folder, served on
    /// its resources port, as deploy-&lt;id&gt;.log, the newest ten kept, and
    /// hands back the address a Deployment's log_url names ("" when none).
    /// Addresses in server.log lines are taken out before they reach it.</summary>
    public static string PublishLog(Server s, string id, IEnumerable<string> lines)
    {
        var dir = s.DataDir();
        var name = $"deploy-{id}.log";
        try
        {
            Files.WriteWhole(Path.Combine(dir, name), Encoding.UTF8.GetBytes(string.Join("\r\n", lines) + "\r\n"));
            var old = new DirectoryInfo(dir).EnumerateFiles("deploy-*.log").Where(f => LogName.IsMatch(f.Name))
                .OrderByDescending(f => f.LastWriteTimeUtc).Skip(10);
            foreach (var f in old) f.Delete();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return ""; }
        return s.Env.LogBase == "" ? "" : s.Env.LogBase.TrimEnd('/') + "/" + name;
    }

    public static string UtcNow() => DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ");
}
