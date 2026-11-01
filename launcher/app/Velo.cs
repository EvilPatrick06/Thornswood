using System;
using System.IO;
using Velopack;
using Velopack.Locators;

namespace Thornswood
{
    /// <summary>
    /// VELOPACK INSTALLS AND UPDATES THE LAUNCHER (#4825). Decided by Patrick
    /// on 27 Oct 2026 (docs/studies/launcher-stack/README.md, Decided 4 and 5):
    /// the install is Velopack's Setup, and the launcher updates through
    /// Velopack reading this repository's GitHub Releases directly. Every merge
    /// that changes the launcher or the game files publishes one Velopack
    /// package of both (.github/workflows/merge-release.yml, #5305).
    ///
    /// THE LAYOUT. Velopack keeps an app in one folder of its own: Update.exe,
    /// a small Thornswood.exe that starts the real one, current\ with the
    /// package's files, and packages\ with the package it came from. The
    /// install puts that folder at Root\Launcher (Setup.exe --installto), so
    /// Root\Launcher\Thornswood.exe is still what every shortcut starts, and
    /// the launcher itself runs from Root\Launcher\current. InstallRoot is
    /// Root worked out from Velopack's own answer, not from where this exe
    /// sits, which is one folder deeper than it used to be.
    ///
    /// The update itself, with every check made before it is applied, is
    /// VeloUpdate.cs; the signed release record it is held to, VeloRecord.cs;
    /// what is checked in the package, VeloPackage.cs.
    /// </summary>
    static class Velo
    {
        /// <summary>The repository whose Releases carry the packages.</summary>
        public const string Repo = "ThornswoodRP/Thornswood";
        public const string RepoUrl = "https://github.com/" + Repo;

        // The arguments this launcher was started with, handed back to it when
        // Velopack restarts it after an update.
        static string[] startArgs = new string[0];

        /// <summary>
        /// Velopack's start: the first line of Main, before the mutex, any
        /// window or anything is read from disk. When Velopack runs the exe to
        /// tell it about an install, an update or an uninstall, this answers
        /// and ends the process; otherwise it returns at once.
        ///
        /// Auto apply is off. A package that was downloaded and not yet applied
        /// (a launcher that closed before its update went in) would otherwise
        /// be applied here, at the next start, before the checks in
        /// VeloUpdate.cs have passed it. Left off, the next update check finds
        /// it on disk and checks it like any other.
        /// </summary>
        public static void Start(string[] args)
        {
            startArgs = args ?? new string[0];
            VelopackApp.Build()
                .SetArgs(startArgs)
                .SetAutoApplyOnStartup(false)
                .OnRestarted(delegate { Restarted = true; })
                .Run();
        }

        /// <summary>
        /// True when Velopack started this launcher straight after applying an
        /// update to it. Shell runs the rest of the update then (the icon pass
        /// and Fix, #3201), the way it did when the swap script's
        /// Thornswood.exe.old said so before #4825.
        /// </summary>
        public static bool Restarted { get; private set; }

        /// <summary>Velopack's answer about this install, or null before Start.</summary>
        public static IVelopackLocator Locator
        {
            get { return VelopackLocator.IsCurrentSet ? VelopackLocator.Current : null; }
        }

        /// <summary>
        /// True when Velopack installed this launcher. A launcher started from
        /// a build folder (a developer's Build-Launcher.ps1 into a test root)
        /// is not, and never updates itself.
        /// </summary>
        public static bool Installed
        {
            get
            {
                IVelopackLocator l = Locator;
                return l != null && l.CurrentlyInstalledVersion != null && !string.IsNullOrEmpty(l.RootAppDir);
            }
        }

        /// <summary>
        /// Root, the folder that holds Launcher, Profile and Game, when
        /// Velopack installed this launcher into Root\Launcher; null when it
        /// did not. Paths.Init and the single-instance lock read it before
        /// they fall back on the folder above the exe's.
        /// </summary>
        public static string InstallRoot
        {
            get
            {
                if (!Installed) return null;
                string app = Locator.RootAppDir.TrimEnd('\\', '/');
                return Path.GetDirectoryName(app);
            }
        }

        /// <summary>
        /// The Velopack channel this install reads: "dev" for the dev server's
        /// launcher, "main" for the live one. The same answer the update feed
        /// goes by (Updater.FeedUrl): config.json's Channel or UpdateBranch.
        ///
        /// Every merge release packs on "dev" (merge-release.yml). Main is the
        /// same package after Patrick approves it (#5181), published with a
        /// releases.main.json of its own; until that exists a main launcher
        /// finds no update and says so.
        /// </summary>
        public static string ChannelFor(Config cfg)
        {
            bool dev = cfg != null &&
                       (string.Equals(cfg.Channel, "dev", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(cfg.UpdateBranch, "dev", StringComparison.OrdinalIgnoreCase));
            return dev ? "dev" : "main";
        }

        // The update that goes in when this launcher exits (ApplyOnExit).
        static readonly object stageGate = new object();
        static UpdateManager stagedBy;
        static VelopackAsset staged;

        /// <summary>
        /// Holds a downloaded and checked update to be applied once this
        /// launcher has closed. The caller closes the window; ExitApply, the
        /// last thing the process does, hands it to Velopack.
        /// </summary>
        public static void ApplyOnExit(UpdateManager by, VelopackAsset what)
        {
            lock (stageGate) { stagedBy = by; staged = what; }
        }

        /// <summary>True while an update waits for the launcher to close.</summary>
        public static bool Staged { get { lock (stageGate) return staged != null; } }

        /// <summary>
        /// The last line of Main, after the window has closed and everything
        /// the close puts back (the swapped settings, the hold, the parked
        /// files, the client) is done. Velopack's Update.exe waits for this
        /// process to end, sixty seconds at most, puts the new launcher in and
        /// starts it with the arguments this one had. Called that late so the
        /// wait covers only the process ending: the close itself can take
        /// longer than Velopack waits. Does nothing when no update is staged.
        /// </summary>
        public static void ExitApply()
        {
            UpdateManager by;
            VelopackAsset what;
            lock (stageGate) { by = stagedBy; what = staged; staged = null; stagedBy = null; }
            if (by == null || what == null) return;
            by.WaitExitThenApplyUpdates(what, false, true, startArgs);
        }
    }
}
