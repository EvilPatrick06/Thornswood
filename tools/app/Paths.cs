using System;
using System.IO;

namespace SkyrimTogether
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

        public static string Str { get { return Path.Combine(Game, "Data\\SkyrimTogetherReborn\\SkyrimTogether.exe"); } }
        public static string Exe { get { return Path.Combine(Game, "SkyrimSE.exe"); } }
    }
}
