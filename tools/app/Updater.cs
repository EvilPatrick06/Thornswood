using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;

namespace SkyrimTogether
{
    static class Updater
    {
        public const string Version = "1.0.0";

        static WebClient Client(Config cfg, bool octet, string url)
        {
            var wc = new WebClient();
            wc.Headers["User-Agent"] = "SkyrimTogetherLauncher/" + Version;
            // The token only ever goes to GitHub's own API, never to whatever
            // host an asset URL happens to point at.
            bool github = false;
            try { github = new Uri(url).Host.Equals("api.github.com", StringComparison.OrdinalIgnoreCase); }
            catch { }
            if (github && !string.IsNullOrEmpty(cfg.UpdateToken))
                wc.Headers["Authorization"] = "Bearer " + cfg.UpdateToken;
            wc.Headers["Accept"] = octet ? "application/octet-stream" : "application/vnd.github.raw";
            return wc;
        }

        public static bool Enabled(Config cfg)
        {
            // A private repo answers 404 rather than 403 when the request is not
            // authenticated, so without a token there is nothing worth asking.
            return !string.IsNullOrEmpty(cfg.UpdateRepo)
                   && cfg.UpdateRepo.Contains("/")
                   && !string.IsNullOrEmpty(cfg.UpdateToken);
        }

        public static string WhyDisabled(Config cfg)
        {
            if (string.IsNullOrEmpty(cfg.UpdateRepo) || !cfg.UpdateRepo.Contains("/")) return "no update source set";
            if (string.IsNullOrEmpty(cfg.UpdateToken)) return cfg.UpdateRepo + "  (needs an access token)";
            return cfg.UpdateRepo;
        }

        /// <summary>Reads version.json from the repo. Returns null if updates are off or unreachable.</summary>
        public static VersionDoc Check(Config cfg)
        {
            if (!Enabled(cfg)) return null;
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; // Tls12
            string url = "https://api.github.com/repos/" + cfg.UpdateRepo +
                         "/contents/version.json?ref=" + (string.IsNullOrEmpty(cfg.UpdateBranch) ? "main" : cfg.UpdateBranch);
            try
            {
                using (var wc = Client(cfg, false, url))
                    return VersionDoc.Parse(wc.DownloadData(url));
            }
            catch (WebException wex)
            {
                var r = wex.Response as HttpWebResponse;
                if (r != null)
                {
                    int code = (int)r.StatusCode;
                    if (code == 404) throw new Exception("the repo or the branch could not be read, check UpdateRepo and that the token still has access");
                    if (code == 401 || code == 403) throw new Exception("the access token was refused, it may have expired");
                }
                throw new Exception("could not reach GitHub");
            }
        }

        public static HashSet<string> Applied()
        {
            var s = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try { if (File.Exists(Paths.AppliedFile)) foreach (string l in File.ReadAllLines(Paths.AppliedFile)) if (l.Trim().Length > 0) s.Add(l.Trim()); }
            catch { }
            return s;
        }

        static void MarkApplied(string id)
        {
            try { File.AppendAllText(Paths.AppliedFile, id + Environment.NewLine); } catch { }
        }

        public static List<Pack> Pending(VersionDoc v)
        {
            var done = Applied();
            var list = new List<Pack>();
            if (v == null || v.packs == null) return list;
            foreach (var p in v.packs)
                if (p != null && !string.IsNullOrEmpty(p.id) && !done.Contains(p.id)) list.Add(p);
            return list;
        }

        static string Sha256(string file)
        {
            using (var s = File.OpenRead(file))
            using (var h = SHA256.Create())
            {
                byte[] d = h.ComputeHash(s);
                var sb = new StringBuilder();
                foreach (byte b in d) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        static string Download(Config cfg, string url, string expectSha, Action<string> log)
        {
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
            string tmp = Path.Combine(Path.GetTempPath(), "st-" + Guid.NewGuid().ToString("N") + ".bin");
            using (var wc = Client(cfg, true, url)) wc.DownloadFile(url, tmp);
            if (!string.IsNullOrEmpty(expectSha))
            {
                string got = Sha256(tmp);
                if (!string.Equals(got, expectSha, StringComparison.OrdinalIgnoreCase))
                {
                    try { File.Delete(tmp); } catch { }
                    throw new Exception("Checksum did not match. Download rejected.");
                }
                log("Checksum verified.");
            }
            return tmp;
        }

        /// <summary>
        /// A pack is a zip holding game/ and profile/ trees, plus an optional
        /// delete.txt listing paths under Game to remove.
        /// </summary>
        public static void ApplyPack(Config cfg, Pack p, Action<string> log)
        {
            log("Downloading " + p.id + "...");
            string zip = Download(cfg, p.url, p.sha256, log);
            try
            {
                int files = 0;
                using (var ar = ZipFile.OpenRead(zip))
                {
                    var del = ar.GetEntry("delete.txt");
                    if (del != null)
                    {
                        using (var sr = new StreamReader(del.Open()))
                        {
                            string line;
                            while ((line = sr.ReadLine()) != null)
                            {
                                line = line.Trim();
                                if (line.Length == 0 || line.StartsWith("#")) continue;
                                string target = Path.Combine(Paths.Game, line.Replace('/', '\\'));
                                if (!target.StartsWith(Paths.Game, StringComparison.OrdinalIgnoreCase)) continue;
                                try { if (File.Exists(target)) { File.Delete(target); log("removed " + line); } } catch { }
                            }
                        }
                    }

                    foreach (var e in ar.Entries)
                    {
                        if (string.IsNullOrEmpty(e.Name)) continue;           // directory entry
                        string rel = e.FullName.Replace('/', '\\');
                        string dest = null;

                        if (rel.StartsWith("game\\", StringComparison.OrdinalIgnoreCase))
                            dest = Path.Combine(Paths.Game, rel.Substring(5));
                        else if (rel.StartsWith("profile\\", StringComparison.OrdinalIgnoreCase))
                            dest = Path.Combine(Paths.Golden, Path.GetFileName(rel));
                        else if (rel.Equals("delete.txt", StringComparison.OrdinalIgnoreCase))
                            continue;
                        else
                            continue;

                        string full = Path.GetFullPath(dest);
                        if (!full.StartsWith(Paths.Root, StringComparison.OrdinalIgnoreCase)) continue;
                        Directory.CreateDirectory(Path.GetDirectoryName(full));
                        e.ExtractToFile(full, true);
                        files++;
                    }
                }

                // Settings that shipped with the pack become the new baseline
                // and are pushed into the live profile too.
                Swap.RepairConfigs();
                MarkApplied(p.id);
                log(p.id + " applied, " + files + " files.");
            }
            finally { try { File.Delete(zip); } catch { } }
        }

        /// <summary>Replaces the running exe and restarts, via a short detached script.</summary>
        public static void SelfUpdate(Config cfg, VersionDoc v, Action<string> log)
        {
            log("Downloading launcher " + v.launcherVersion + "...");
            string tmp = Download(cfg, v.launcherUrl, v.launcherSha256, log);
            string exe = System.Reflection.Assembly.GetExecutingAssembly().Location;
            string neu = exe + ".new";
            File.Copy(tmp, neu, true);
            try { File.Delete(tmp); } catch { }

            string bat = Path.Combine(Path.GetTempPath(), "st-update.cmd");
            File.WriteAllText(bat,
                "@echo off\r\n" +
                "ping 127.0.0.1 -n 3 >nul\r\n" +
                "move /y \"" + neu + "\" \"" + exe + "\" >nul\r\n" +
                "start \"\" \"" + exe + "\"\r\n" +
                "del \"%~f0\"\r\n");

            var psi = new System.Diagnostics.ProcessStartInfo(bat);
            psi.WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden;
            psi.CreateNoWindow = true;
            psi.UseShellExecute = true;
            System.Diagnostics.Process.Start(psi);
        }
    }
}
