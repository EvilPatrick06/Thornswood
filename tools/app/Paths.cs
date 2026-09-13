using System;
using System.IO;

namespace Thornswood
{
    // Everything the launcher touches, resolved once from the exe location.
    static class Paths
    {
        public static string Root, Game, LauncherDir, ProfileDir, MyGames, LocalAD, Golden, Personal;
        public static string StateFile, PlayedFile, CfgFile, AppliedFile, LogFile;
        public static string WinMyGames, WinLocalAD;

        public static void Init(string rootOverride)
        {
            string exeDir = Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location);
            Root = string.IsNullOrEmpty(rootOverride) ? Path.GetDirectoryName(exeDir) : rootOverride;

            Game        = Path.Combine(Root, "Game");
            LauncherDir = Path.Combine(Root, "Launcher");
            ProfileDir  = Path.Combine(Root, "Profile");
            MyGames     = Path.Combine(ProfileDir, "MyGames");
            LocalAD     = Path.Combine(ProfileDir, "LocalAppData");
            Golden      = Path.Combine(ProfileDir, "Default");
            Personal    = Path.Combine(Root, "Your Mods");
            StateFile   = Path.Combine(ProfileDir, "swap.json");
            PlayedFile  = Path.Combine(ProfileDir, "played.flag");
            AppliedFile = Path.Combine(ProfileDir, "applied.txt");
            LogFile     = Path.Combine(ProfileDir, "launcher.log");
            CfgFile     = Path.Combine(Root, "config.json");

            WinMyGames = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                "My Games\\Skyrim Special Edition");
            WinLocalAD = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Skyrim Special Edition");
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
