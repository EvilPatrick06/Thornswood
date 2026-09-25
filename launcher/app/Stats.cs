using System;
using System.Globalization;
using System.IO;

namespace Thornswood
{
    /// <summary>How much this build has actually been played. Local only.</summary>
    static class Stats
    {
        public static int Sessions;
        public static double Minutes;
        public static DateTime LastPlayed = DateTime.MinValue;
        public static string LastUpdate = "";

        static string File_ { get { return Path.Combine(Paths.ProfileDir, "stats.txt"); } }

        public static void Load()
        {
            try
            {
                if (!File.Exists(File_)) return;
                foreach (string line in File.ReadAllLines(File_))
                {
                    int eq = line.IndexOf('=');
                    if (eq < 1) continue;
                    string k = line.Substring(0, eq).Trim(), v = line.Substring(eq + 1).Trim();
                    if (k == "sessions") int.TryParse(v, out Sessions);
                    else if (k == "minutes") double.TryParse(v, NumberStyles.Any, CultureInfo.InvariantCulture, out Minutes);
                    else if (k == "lastPlayed") DateTime.TryParse(v, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out LastPlayed);
                    else if (k == "lastUpdate") LastUpdate = v;
                }
            }
            catch { }
        }

        public static void Save()
        {
            try
            {
                Directory.CreateDirectory(Paths.ProfileDir);
                File.WriteAllText(File_,
                    "sessions=" + Sessions + Environment.NewLine +
                    "minutes=" + Minutes.ToString("F1", CultureInfo.InvariantCulture) + Environment.NewLine +
                    "lastPlayed=" + (LastPlayed == DateTime.MinValue ? "" : LastPlayed.ToString("o")) + Environment.NewLine +
                    "lastUpdate=" + LastUpdate + Environment.NewLine);
            }
            catch { }
        }

        public static void StartedPlaying()
        {
            Sessions++;
            LastPlayed = DateTime.Now;
            Save();
        }

        public static void StoppedPlaying(DateTime startedAt)
        {
            double m = (DateTime.Now - startedAt).TotalMinutes;
            if (m > 0 && m < 60 * 24) Minutes += m;
            Save();
        }

        public static string PlayedText
        {
            get
            {
                // "not yet" beside a session count that says otherwise reads as a
                // bug, so a played build never claims it has not been played.
                if (Minutes < 1) return Sessions > 0 ? "under a minute" : "not yet";
                if (Minutes < 60) return ((int)Minutes) + " min";
                double h = Minutes / 60.0;
                return h.ToString(h < 10 ? "F1" : "F0", CultureInfo.InvariantCulture) + " hours";
            }
        }

        public static string LastPlayedText
        {
            get
            {
                if (LastPlayed == DateTime.MinValue) return "never";
                TimeSpan ago = DateTime.Now - LastPlayed;
                if (ago.TotalMinutes < 90) return ((int)Math.Max(1, ago.TotalMinutes)) + " min ago";
                if (ago.TotalHours < 36) return ((int)ago.TotalHours) + " hours ago";
                if (ago.TotalDays < 14) return ((int)ago.TotalDays) + " days ago";
                return LastPlayed.ToString("d MMM");
            }
        }
    }
}
