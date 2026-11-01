#nullable enable
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Thornswood.DeployAgent;

/// <summary>The server build a Release carries, and the rules that hold it to
/// its record (records/server-build.json), the same rules
/// scripts/deploy/ServerBuild.ps1 holds a payload, a stage and the box's own
/// folder to, so the agent and the deploy scripts agree on which build a
/// server runs (#5219, plan part 8).</summary>
public static class ServerBuild
{
    /// <summary>Every one of these is in every record. data/scripts is by
    /// folder: the files in it are whatever the fork compiles.</summary>
    public static readonly string[] ForkFiles = ["scam_native.node", "dist_back/skymp5-server.js", "dist_back/skymp5-server.js.map", "package.json", "yarn.lock", "launch_server.bat"];
    static readonly string[] ForkFolders = ["dist_back", "data/scripts"];

    /// <summary>A path as the record writes it: forward slashes, no leading one.</summary>
    public static string Rel(string rel) => rel.Replace('\\', '/').TrimStart('/');

    /// <summary>Whether a file, by its path in the server folder, is one the
    /// fork's build makes and the record must name (Test-ThornswoodServerForkFile).</summary>
    public static bool IsForkFile(string rel)
    {
        var r = Rel(rel);
        if (ForkFiles.Contains(r)) return true;
        if (!r.Contains('/') && r.EndsWith(".node", StringComparison.OrdinalIgnoreCase)) return true;
        return ForkFolders.Any(f => r.StartsWith(f + "/", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>The record's sum, every CR LF read as LF, the way
    /// Get-ThornswoodRecordSum works it out: a record checked out with CR LF
    /// and one without are the same record.</summary>
    public static string RecordSum(byte[] bytes)
    {
        var l1 = Encoding.Latin1;
        var b = l1.GetBytes(l1.GetString(bytes).Replace("\r\n", "\n"));
        return Convert.ToHexStringLower(SHA256.HashData(b));
    }

    public sealed record Entry(string Sha256, string Commit);

    /// <summary>A parsed record: the fork commit, the binary's sum at the
    /// top, and every file it lists.</summary>
    public sealed record Record(string Commit, string Binary, Dictionary<string, Entry> Files)
    {
        public string Short => Commit.Length > 12 ? Commit[..12] : Commit;
    }

    public static Record Read(byte[] bytes)
    {
        var text = Encoding.UTF8.GetString(bytes).TrimStart('﻿');
        using var d = JsonDocument.Parse(text);
        var root = d.RootElement;
        string S(JsonElement e, string n) => e.ValueKind == JsonValueKind.Object && e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : "";
        var commit = root.TryGetProperty("source", out var src) ? S(src, "commit").ToLowerInvariant() : "";
        var files = new Dictionary<string, Entry>(StringComparer.Ordinal);
        if (root.TryGetProperty("files", out var fs) && fs.ValueKind == JsonValueKind.Object)
            foreach (var p in fs.EnumerateObject()) files[Rel(p.Name)] = new Entry(S(p.Value, "sha256").ToLowerInvariant(), S(p.Value, "commit").ToLowerInvariant());
        return new Record(commit, S(root, "sha256").ToLowerInvariant(), files);
    }

    /// <summary>Every way the files in sums (rel to sha256) are not the build
    /// the record names, as sentences; empty when they are. The checks of
    /// Get-ThornswoodServerBuildProblems, in its words.</summary>
    public static List<string> Problems(Record rec, IReadOnlyDictionary<string, string> sums, string where)
    {
        var o = new List<string>();
        if (rec.Files.Count == 0) { o.Add("server-build.json lists no server files, so nothing says which build the JavaScript half and the rest are"); return o; }
        if (rec.Commit == "") o.Add("server-build.json names no fork commit (source.commit)");
        foreach (var n in ForkFiles) if (!rec.Files.ContainsKey(n)) o.Add("server-build.json does not list " + n);
        if (rec.Files.TryGetValue("scam_native.node", out var bin) && bin.Sha256 != rec.Binary)
            o.Add("server-build.json names one scam_native.node at the top and another under files");
        foreach (var (rel, e) in rec.Files)
        {
            if (e.Sha256.Length != 64 || !e.Sha256.All(Uri.IsHexDigit)) { o.Add("server-build.json names no sha256 for " + rel); continue; }
            if (rec.Commit != "" && e.Commit != rec.Commit)
                o.Add($"server-build.json says {rel} was built from {(e.Commit == "" ? "no commit" : e.Commit[..Math.Min(8, e.Commit.Length)])}, and the server from {rec.Commit[..Math.Min(8, rec.Commit.Length)]}");
            if (!sums.TryGetValue(rel, out var have)) { o.Add($"{rel} is not in {where}"); continue; }
            if (have != e.Sha256) o.Add($"{rel} in {where} is not the build server-build.json records (it is {have[..12]}, the record says {e.Sha256[..12]})");
        }
        foreach (var rel in sums.Keys)
            if (IsForkFile(rel) && !rec.Files.ContainsKey(Rel(rel))) o.Add($"{Rel(rel)} in {where} is a server file server-build.json does not list, so it is from another build");
        return o;
    }

    /// <summary>The fork files of a server zip (ServerArtifact.ps1's shape)
    /// written into dir by their paths, with the record it carries as
    /// server-build.json. Returns rel to sha256 of every fork file written. A
    /// path that would leave dir is refused.</summary>
    public static Dictionary<string, string> Expand(string zip, string dir, out byte[] record)
    {
        var sums = new Dictionary<string, string>(StringComparer.Ordinal);
        byte[]? rec = null;
        var full = Path.GetFullPath(dir) + Path.DirectorySeparatorChar;
        using var za = ZipFile.OpenRead(zip);
        foreach (var ze in za.Entries)
        {
            if (ze.Name == "") continue;
            var rel = Rel(ze.FullName);
            if (rel == "server-build.json")
            {
                using var s = ze.Open();
                using var ms = new MemoryStream();
                s.CopyTo(ms);
                rec = ms.ToArray();
                continue;
            }
            if (!IsForkFile(rel)) continue;
            var to = Path.GetFullPath(Path.Combine(dir, rel.Replace('/', Path.DirectorySeparatorChar)));
            if (!to.StartsWith(full, StringComparison.Ordinal)) throw new InvalidDataException($"the server zip names {ze.FullName}, which is outside the server folder");
            Directory.CreateDirectory(Path.GetDirectoryName(to)!);
            using (var s = ze.Open())
            using (var f = new FileStream(to, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                s.CopyTo(f);
                f.Flush(true);
            }
            sums[rel] = ReleaseFetch.FileSha256(to);
        }
        record = rec ?? throw new InvalidDataException("the server zip carries no server-build.json, so nothing says which build it is");
        return sums;
    }

    /// <summary>The fork files in a server folder, by rel: the files at its
    /// top and those under dist_back and data/scripts, the only places a fork
    /// file can be, so the saves and the rest of data are never walked.</summary>
    public static List<string> FolderForkFiles(string root)
    {
        var o = new List<string>();
        if (!Directory.Exists(root)) return o;
        var found = Directory.EnumerateFiles(root).AsEnumerable();
        foreach (var f in ForkFolders)
        {
            var d = Path.Combine(root, f.Replace('/', Path.DirectorySeparatorChar));
            if (Directory.Exists(d)) found = found.Concat(Directory.EnumerateFiles(d, "*", SearchOption.AllDirectories));
        }
        foreach (var f in found)
        {
            var rel = Rel(Path.GetRelativePath(root, f));
            if (IsForkFile(rel)) o.Add(rel);
        }
        return o;
    }
}
