using System;
using System.Collections.Generic;
using System.IO;

namespace Thornswood
{
    class Entry
    {
        public string Name, Detail, FullPath;
        public DateTime When;
        public long Bytes;
    }

    static class Files
    {
        public static string SkseLogDir { get { return Path.Combine(Paths.LiveMyGames, "SKSE"); } }
        public static string SaveDir { get { return Path.Combine(Paths.LiveMyGames, "Saves"); } }

        static string Size(long b)
        {
            if (b < 1024) return b + " B";
            if (b < 1024 * 1024) return (b / 1024) + " KB";
            return (b / (1024.0 * 1024.0)).ToString("F1") + " MB";
        }

        static string Ago(DateTime t)
        {
            TimeSpan d = DateTime.Now - t;
            if (d.TotalMinutes < 90) return ((int)Math.Max(1, d.TotalMinutes)) + " min ago";
            if (d.TotalHours < 36) return ((int)d.TotalHours) + " hours ago";
            if (d.TotalDays < 14) return ((int)d.TotalDays) + " days ago";
            return t.ToString("d MMM yyyy");
        }

        /// <summary>Crash logs newest first, then the launcher's own log.</summary>
        public static List<Entry> Logs()
        {
            var l = new List<Entry>();
            try
            {
                if (Directory.Exists(SkseLogDir))
                {
                    var crashes = new List<FileInfo>();
                    foreach (string f in Directory.GetFiles(SkseLogDir, "crash-*.log")) crashes.Add(new FileInfo(f));
                    crashes.Sort(delegate(FileInfo a, FileInfo b) { return b.LastWriteTime.CompareTo(a.LastWriteTime); });
                    foreach (FileInfo fi in crashes)
                        l.Add(new Entry { Name = fi.Name, Detail = Ago(fi.LastWriteTime) + "   ·   " + Size(fi.Length), FullPath = fi.FullName, When = fi.LastWriteTime, Bytes = fi.Length });
                }
                if (File.Exists(Paths.LogFile))
                {
                    var fi = new FileInfo(Paths.LogFile);
                    l.Add(new Entry { Name = "launcher.log", Detail = "this launcher   ·   " + Size(fi.Length), FullPath = fi.FullName, When = fi.LastWriteTime, Bytes = fi.Length });
                }
            }
            catch (Exception ex) { Swallow.Note("Files.Logs", ex); }
            return l;
        }

        public static Entry NewestCrash()
        {
            foreach (Entry e in Logs()) if (e.Name.StartsWith("crash-")) return e;
            return null;
        }
    }
}
