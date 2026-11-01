using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;

namespace Thornswood
{
    /// <summary>
    /// EVERY FILE IN AN UPDATE PACKAGE, CHECKED BEFORE IT IS APPLIED (#4825).
    ///
    /// The package Velopack downloaded (or rebuilt from the one before and its
    /// deltas) is opened and each file Velopack would put in place is held to
    /// one of two things, so nothing reaches this PC that nobody vouched for:
    ///   - a game file (lib/app/Game/...) must be in the signed release's
    ///     game-files.json with the same size and sha256, and every file that
    ///     list names must be in the package. A file that does not match is
    ///     refused, as the feed's record sync refuses one (Sync.cs).
    ///   - every program (.exe, .dll) anywhere else, the launcher itself,
    ///     the native libraries beside it and Velopack's own Update.exe and
    ///     starter, must pass Signature.Refusal for ExpectedSigner: Windows
    ///     verifies the signature and its chain, and it is Thornswood's own
    ///     identity from Microsoft's Artifact Signing (Signature.cs says why
    ///     each). This is the signer check the old self update made on the
    ///     downloaded exe before the swap (#912), on every program now.
    /// Nothing else may be under lib/app but Velopack's own version file.
    /// The package's NuGet bookkeeping outside lib/app is never put on disk.
    ///
    /// Checked on the package's contents, not its bytes, because a package
    /// rebuilt from deltas is not byte for byte the one the Release carries;
    /// its contents are.
    /// </summary>
    static class VeloPackage
    {
        const string App = "lib/app/";
        const string GameDir = "lib/app/Game/";

        /// <summary>
        /// Empty when every file in the package at <paramref name="nupkg"/>
        /// is vouched for (above); otherwise why not, as the rest of a
        /// sentence starting "The update package". <paramref name="said"/> is
        /// the line for launcher.log when it passed. Reports how far it has
        /// got to <paramref name="files"/> (done, total).
        /// </summary>
        public static string Refusal(string nupkg, VeloRecord.GameList list, string expectedSigner,
                                     Action<long, long> files, out string said)
        {
            said = "";
            var want = new Dictionary<string, VeloRecord.GameFile>(StringComparer.OrdinalIgnoreCase);
            foreach (VeloRecord.GameFile f in list.Files)
            {
                if (f == null || string.IsNullOrEmpty(f.Path) || string.IsNullOrEmpty(f.Sha256)) return "names a game file the list gives no path or checksum for.";
                string p = f.Path.Replace('\\', '/');
                if (want.ContainsKey(p)) return "lists the game file " + p + " twice.";
                want[p] = f;
            }

            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            int programs = 0;
            string signerSaid = "";
            using (ZipArchive zip = ZipFile.OpenRead(nupkg))
            {
                long total = zip.Entries.Count, done = 0;
                foreach (ZipArchiveEntry e in zip.Entries)
                {
                    done++;
                    if (files != null && (done % 50 == 0 || done == total)) files(done, total);
                    if (e.FullName.EndsWith("/", StringComparison.Ordinal)) continue;
                    // NuGet writes each name escaped, a space as %20; Velopack
                    // reads them back the same way (NugetUtil.GetPath).
                    string name = Uri.UnescapeDataString(e.FullName.Replace('\\', '/')).TrimStart('/');
                    if (name.Contains("../", StringComparison.Ordinal) || name.Contains("/..", StringComparison.Ordinal))
                        return "carries " + name + ", a path that climbs out of its folder.";

                    if (name.StartsWith(GameDir, StringComparison.OrdinalIgnoreCase))
                    {
                        string rel = name.Substring(GameDir.Length);
                        VeloRecord.GameFile f;
                        if (!want.TryGetValue(rel, out f))
                            return "carries the game file " + rel + ", which the signed release's game-files.json does not list.";
                        if (e.Length != f.Size)
                            return "carries " + rel + " at " + e.Length + " bytes, and the signed list says " + f.Size + ".";
                        string sha;
                        using (Stream s = e.Open()) sha = VeloRecord.Sha256(s);
                        if (!string.Equals(sha, f.Sha256, StringComparison.OrdinalIgnoreCase))
                            return "carries " + rel + " with the checksum " + sha + ", and the signed list says " + f.Sha256 + ".";
                        seen.Add(rel);
                        continue;
                    }

                    bool program = name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
                                   name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase);
                    if (program)
                    {
                        string tmp = Path.Combine(Path.GetTempPath(), "thornswood-velo-" + Guid.NewGuid().ToString("N") + Path.GetExtension(name));
                        try
                        {
                            e.ExtractToFile(tmp, true);
                            string why = Signature.Refusal(tmp, expectedSigner, out signerSaid);
                            if (why.Length > 0) return "carries the program " + name + ", which " + why;
                        }
                        finally
                        {
                            try { File.Delete(tmp); } catch (Exception ex) { Swallow.Note("VeloPackage.Refusal, delete " + tmp, ex); }
                        }
                        programs++;
                        continue;
                    }

                    // Outside lib/app: the package's own NuGet bookkeeping,
                    // which Velopack reads and never puts on disk.
                    if (!name.StartsWith(App, StringComparison.OrdinalIgnoreCase)) continue;
                    if (string.Equals(name, App + "sq.version", StringComparison.OrdinalIgnoreCase)) continue;
                    return "carries " + name + ", which is neither a signed program nor a game file the signed release lists.";
                }
            }

            var missing = new List<string>();
            foreach (string p in want.Keys) if (!seen.Contains(p)) missing.Add(p);
            if (missing.Count > 0)
                return "lacks " + missing.Count + " of the game files the signed release lists, " + missing[0] + (missing.Count > 1 ? " among them." : ".");
            if (programs == 0) return "carries no program at all, so there is no launcher in it.";

            said = "Every file in the update package checked: " + seen.Count + " game files match the signed release's list, and " +
                   programs + (programs == 1 ? " program is" : " programs are") + " signed by Thornswood. " + signerSaid;
            return "";
        }
    }
}
