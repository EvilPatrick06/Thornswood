using System;
using System.IO;

namespace Thornswood
{
    /// <summary>
    /// The one question the ship root tool asks OwnGame that the launcher does
    /// not: is this folder made from Vortex's deployment as it is now, to the
    /// rules this build has (#2019)? Part of OwnGame in the tool's build only
    /// (scripts\release\ShipRoot\ShipRoot.csproj compiles it beside
    /// launcher\app), so it reads OwnGame's own record and its own numbers and
    /// never a copy of them. The launcher does not carry it.
    /// </summary>
    static partial class OwnGame
    {
        /// <summary>
        /// Null when the folder is made, on record as made from the folder
        /// Vortex deploys into now, from that folder's deployment as it is now,
        /// to this build's Rules, with every file sorted into the three kinds.
        /// Otherwise one sentence saying which of those is not so.
        /// </summary>
        public static string ShipRootCurrent(Config cfg)
        {
            if (!Active)
                return Folder + " is not a folder OwnGame made (" + FilesList + " is not there), so what in it came from Vortex is not on record.";
            string src = DeploysInto(cfg);
            if (string.IsNullOrEmpty(src) || !HasRecord(src))
                return "Vortex has nothing deployed that this machine can find (no Data\\vortex.deployment.json in " + (string.IsNullOrEmpty(src) ? "any Steam library" : src) +
                       "), so the folder cannot be held to it. Deploy the Thornswood profile in Vortex.";
            string madeFrom = RecordedText("source");
            if (madeFrom.Length == 0 || !SameFolder(madeFrom, src))
                return Folder + " was made from " + (madeFrom.Length == 0 ? "a folder its record does not name" : madeFrom) +
                       ", and Vortex deploys into " + src + " now, so it is not the collection as deployed.";
            long rules = Recorded("rules");
            if (rules != Rules)
                return Folder + " is on OwnGame's rules " + rules + " and this build's are " + Rules + ".";
            if (Recorded("deployment") != DeploymentStamp(src))
                return "Vortex has deployed into " + src + " since " + Folder + " was last brought up to date.";
            if (Recorded("kinds") < 1)
                return Folder + " still has files that are not sorted into Skyrim's own, Vortex's and Thornswood's (made.txt kinds=0), so it may hold a mod put into the Steam copy by hand.";
            return null;
        }

        /// <summary>made.txt, the lines as they are, for the tool to print.</summary>
        public static string[] MadeLines()
        {
            try { return File.Exists(MadeFile) ? File.ReadAllLines(MadeFile) : new string[0]; }
            catch (Exception ex) { Swallow.Note("OwnGame.MadeLines", ex); return new string[0]; }
        }
    }
}
