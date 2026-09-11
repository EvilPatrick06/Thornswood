using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;

namespace SkyrimTogether
{
    class Check
    {
        public string Name, Detail;
        public bool Ok;
        public Check(string n, bool ok, string d) { Name = n; Ok = ok; Detail = d; }
    }

    static class Checks
    {
        public static int EnabledPlugins()
        {
            try
            {
                string p = Path.Combine(Paths.LocalAD, "plugins.txt");
                if (!File.Exists(p)) return 0;
                int n = 0;
                foreach (string line in File.ReadAllLines(p))
                    if (line.StartsWith("*")) n++;
                return n;
            }
            catch { return 0; }
        }

        public static List<Check> All(Config cfg)
        {
            long bytes = 0;
            try { if (File.Exists(Paths.Exe)) bytes = new FileInfo(Paths.Exe).Length; } catch { }
            int plugins = EnabledPlugins();

            var l = new List<Check>();
            l.Add(new Check("Game build", bytes == cfg.ExpectedExeBytes, bytes == 0 ? "missing" : "1.6.1170"));
            l.Add(new Check("Script Extender", File.Exists(Path.Combine(Paths.Game, "skse64_1_6_1170.dll")), "skse64 2.2.6"));
            l.Add(new Check("Multiplayer", File.Exists(Paths.Str), "client"));
            l.Add(new Check("Mods", plugins > 40, plugins + " plugins"));

            // The server does not police plugin lists, so this does. A list that
            // does not match the one this build shipped with desyncs everyone,
            // which is worse than a blocked button with a one click fix.
            int blocking = 0;
            try { foreach (Issue i in Verify.Run()) if (i.Blocking) blocking++; } catch { }
            l.Add(new Check("Mod list",
                            blocking == 0,
                            blocking == 0 ? "matches the server"
                                          : (blocking == 1 ? "1 problem, open Mods" : blocking + " problems, open Mods")));

            l.Add(new Check("Steam", Process.GetProcessesByName("steam").Length > 0, "running"));
            return l;
        }

        public static bool GameRunning()
        {
            string[] names = { "SkyrimSE", "SkyrimTogether", "skse64_loader" };
            foreach (string n in names)
                if (Process.GetProcessesByName(n).Length > 0) return true;
            return false;
        }
    }
}
