using System;
using System.IO;

namespace Thornswood
{
    // Everything the launcher touches, resolved once from the exe location.
    static class Paths
    {
        public static string Root, Game, LauncherDir, ProfileDir, MyGames, LocalAD, Golden, Personal;
        // Where another server's files go when they are moved aside. Never deleted.
        public static string Isolated;
        public static string StateFile, PlayedFile, CfgFile, AppliedFile, LogFile;
        // One file per installed optional pack, listing what it put on disk.
        public static string PacksDir;
        public static string WinMyGames, WinLocalAD;

        // Where Skyrim really reads its plugin list and settings from for this
        // install. Two answers, because there are two kinds of install.
        public static string Live, LiveMyGames;

        /// <summary>
        /// True when the mods come from the Nexus collection, deployed by
        /// Vortex into the person's own Skyrim, rather than from a copy of the
        /// game this launcher installed for itself.
        ///
        /// Decided by looking, not by a setting. An install made before 1.1
        /// has its own Game folder sitting next to the launcher and keeps
        /// working exactly as it did. A fresh install has no such folder,
        /// because the installer stopped shipping one, so the game is the
        /// Steam copy and the mods are Vortex's.
        ///
        /// Anything that behaves differently between the two reads this, and
        /// nothing else has to know which kind of install it is in.
        /// </summary>
        public static bool Collection;

        public static void Init(string rootOverride)
        {
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
            Root = string.IsNullOrEmpty(rootOverride) ? Path.GetDirectoryName(exeDir) : rootOverride;

            string own = Path.Combine(Root, "Game");
            string steam = "";
            try { steam = Steam.SkyrimPath(); } catch { }

            // The launcher's own copy wins whenever it is there, so an upgrade
            // never moves somebody's game out from under them mid-session.
            // Only an install that has no copy of its own goes to Steam.
            Collection = !Directory.Exists(own) && !string.IsNullOrEmpty(steam);
            Game        = Collection ? steam : own;
            LauncherDir = Path.Combine(Root, "Launcher");
            ProfileDir  = Path.Combine(Root, "Profile");
            MyGames     = Path.Combine(ProfileDir, "MyGames");
            LocalAD     = Path.Combine(ProfileDir, "LocalAppData");
            Golden      = Path.Combine(ProfileDir, "Default");
            Personal    = Path.Combine(Root, "Your Mods");
            Isolated    = Path.Combine(ProfileDir, "Isolated");
            StateFile   = Path.Combine(ProfileDir, "swap.json");
            PlayedFile  = Path.Combine(ProfileDir, "played.flag");
            AppliedFile = Path.Combine(ProfileDir, "applied.txt");
            PacksDir    = Path.Combine(ProfileDir, "Packs");
            LogFile     = Path.Combine(ProfileDir, "launcher.log");
            CfgFile     = Path.Combine(Root, "config.json");

            WinMyGames = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                "My Games\\Skyrim Special Edition");
            WinLocalAD = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Skyrim Special Edition");

            // Under the collection the launcher redirects nothing, so the live
            // files are the Windows ones and Vortex's active profile is what
            // writes them. In an older install they are the redirected copies
            // under Profile, which is what the junction points at.
            Live        = Collection ? WinLocalAD : LocalAD;
            LiveMyGames = Collection ? WinMyGames : MyGames;
        }

        // SkyMP has no client executable of its own. MpClientPlugin.dll is an
        // SKSE plugin, so the game is started by the script extender's loader
        // exactly as a single player session would be, and the multiplayer
        // layer comes up inside it.
        public static string Loader { get { return Path.Combine(Game, "skse64_loader.exe"); } }

        // What to look for to decide the multiplayer layer is actually
        // installed. Used by the status checks rather than by anything that
        // launches.
        public static string MpClient
        {
            get { return Path.Combine(Game, "Data\\SKSE\\Plugins\\MpClientPlugin.dll"); }
        }
        public static string Exe { get { return Path.Combine(Game, "SkyrimSE.exe"); } }
    }
}
