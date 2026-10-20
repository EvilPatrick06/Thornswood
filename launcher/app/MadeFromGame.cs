using System;
using System.Collections.Generic;
using System.IO;

namespace Thornswood
{
    /// <summary>
    /// Puts the three files Thornswood makes from the person's own game into
    /// the game folder (#2827): the main menu with no Bethesda logo and the
    /// notice board's and drop box's meshes. FromGame.cs says why they are
    /// made here and not shipped, and makes them; this decides when, and
    /// writes them.
    ///
    /// Before every Play (ShellPlay, beside Thornswood.ini) and from Fix
    /// (Upkeep), only for a file that is missing or not the bytes Thornswood
    /// makes: a game folder that has them right is read and left as it is.
    /// The archives are read from Paths.Skyrim, the game the facts are read
    /// from, and the files go to Paths.Game.
    ///
    /// A game whose files differ from the ones the recipes were written
    /// against (another Skyrim build, or archives a mod replaced) makes
    /// nothing, and the line says which of the game's files differs. Nothing
    /// stands in for a file that could not be made: the game shows its own
    /// menu and the boards have no mesh until the game is on the build
    /// Thornswood pins, and Scan says so.
    ///
    /// Each file is written beside its place and moved in. The name in the
    /// game folder is taken off first, whatever the layout: in an own folder
    /// it may be a link into the Steam copy, and under the collection into
    /// Vortex's staging, and a write through either would change that copy
    /// too (OwnGame.Detach says why).
    /// </summary>
    static class MadeFromGame
    {
        /// <summary>The three, under the game folder, that are missing or not the bytes Thornswood makes.</summary>
        public static List<string> OutOfDate()
        {
            var l = new List<string>();
            foreach (string rel in FromGame.Files) if (!FromGame.IsCurrent(Paths.Game, rel)) l.Add(rel);
            return l;
        }

        /// <summary>Makes the three from this machine's game, without writing anything.</summary>
        public static List<FromGameFile> Make()
        {
            return FromGame.Build(Path.Combine(Paths.Skyrim, "Data"));
        }

        /// <summary>
        /// Makes and writes whichever of the three is out of date. Returns a
        /// line for the log, or null when all three were already right.
        /// Throws when a made file cannot be written.
        /// </summary>
        public static string Ensure()
        {
            List<string> off = OutOfDate();
            if (off.Count == 0) return null;
            var wrote = new List<string>();
            var not = new List<string>();
            foreach (FromGameFile f in Make())
            {
                if (!off.Contains(f.Rel)) continue;
                if (f.Problem != null) { not.Add(Path.GetFileName(f.Rel) + ": " + f.Problem.TrimEnd('.')); continue; }
                Write(Path.Combine(Paths.Game, f.Rel), f.Bytes);
                wrote.Add(Path.GetFileName(f.Rel));
            }
            var said = new List<string>();
            if (wrote.Count > 0) said.Add("Made " + string.Join(", ", wrote.ToArray()) + " from your game's own files.");
            if (not.Count > 0)
                said.Add("Could not make " + string.Join("; ", not.ToArray()) + ". Until that is put right the game shows its own main menu, and the notice boards have no mesh.");
            return string.Join(" ", said.ToArray());
        }

        static void Write(string dest, byte[] bytes)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(dest));
            string next = dest + ".thornswood-new";
            File.WriteAllBytes(next, bytes);
            if (File.Exists(dest)) OwnGame.DropName(dest);
            File.Move(next, dest);
        }
    }
}
