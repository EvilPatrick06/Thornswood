using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace Thornswood
{
    // Two characters, and what actually keeps them apart is the profile id.
    //
    // Under SkyMP a character is not a save file. It is a change form held by
    // the server, and which one you get is decided by gameData.profileId in
    // skymp5-client-settings.txt: connect on profile 1 and the server hands
    // back profile 1's body, inventory and face, whatever Skyrim's own menu
    // says. That is why New Game never produced a new character.
    //
    // So a slot owns a profile id. Playing slot two writes that slot's id into
    // the client settings before the game starts. Making a new character takes
    // an id nobody has used, which the server has never seen, so it runs
    // creation from the top. Nothing has to be deleted anywhere and nothing on
    // the server has to be reachable for any of it, which matters because the
    // server is not on this machine.
    //
    // The save folder still gets swapped per slot. SkyrimPlatform writes its
    // own .ess as it works and there is no reason for two characters to share
    // one pile of them.
    //
    // Skyrim has no command line that says "load this save", so the launcher
    // cannot reach past the main menu on its own. What it can do is make the
    // choice before the game starts: swap in one character's saves, then let
    // Start On Save walk in and load the newest one. Starting fresh is the
    // same trick with an empty folder, which leaves nothing to load and sends
    // the game into character creation instead.
    // partial only so that Sync lives in CharSync.cs, which keeps the file
    // that holds everything else out of the blast radius.
    static partial class Chars
    {
        public const int Slots = 2;

        public static string Home { get { return Path.Combine(Paths.ProfileDir, "Characters"); } }
        public static string SlotDir(int slot) { return Path.Combine(Home, slot.ToString()); }
        static string Bin { get { return Path.Combine(Home, "_deleted"); } }
        static string ActiveFile { get { return Path.Combine(Home, "active.txt"); } }

        // One line per slot:
        //
        //     slot  profileId  lastPlayedTicks  playedSeconds  trade  town
        //
        // Deliberately not JSON. The launcher's only serializer is the data
        // contract one, which cannot round trip a shape it was not told about in
        // advance, and this file has to survive being read by a version that
        // adds a field. Everything past the first two is optional on the way in,
        // so a file written before a field existed still reads.
        //
        // A dash stands for an empty trade or town. Space separated fields and
        // empty strings do not mix.
        static string ProfileFile { get { return Path.Combine(Home, "profiles.txt"); } }
        static string StartIni
        {
            get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\po3_StartOnSave.ini"); }
        }

        public class Who
        {
            public int Slot;
            public bool Empty = true;
            public string Name = "";
            public string Race = "";
            public int Level;
            public string Played = "";
            public DateTime When;
            public int Saves;
            public int ProfileId;
            public DateTime LastPlayed;
            // Seconds this slot has actually been in the game, added up by
            // the launcher across every session. Skyrim keeps its own figure
            // but it is inside the save, and under SkyMP the character is on
            // the server, so there is often no save here to read it out of.
            public long PlaySeconds;
            // What was picked in the launcher when this character was made.
            // Gamemode keys, not labels. The server is the authority on this
            // once somebody has played; this is what to show before then.
            public string Trade = "";
            public string Town = "";
        }

        // ------------------------------------------------------------ reading

        /*
          The header of a Skyrim save is a fixed run of fields before anything
          compressed starts, so the interesting parts can be read without
          unpacking the save itself.

          Except that on this build they are not the character's. Every save in
          these folders is written by SkyrimPlatform as scaffolding, named
          TESMODPLATFORM-<guid>.ess, and its header is filled in with the
          defaults SkyMP ships rather than anything about the person playing:

              name     CF EB E5 ED ED E8 EA   "Пленник" in Windows-1251,
                                              Russian for Prisoner
              level    1
              location "Солстейм", Solstheim

          Read as UTF-8 that name comes out as seven replacement characters,
          which is how a card that said "Patrick" started saying ???????: the
          moment a save existed, this header was preferred over the server,
          and the server is the only thing here that actually knows.

          So a synthetic save contributes nothing but its timestamp. The race
          is kept because NordRace in that header did match, and it is the one
          field SkyMP writes from the real character.
        */
        static Who Header(string file, int slot)
        {
            var w = new Who();
            w.Slot = slot;
            bool synthetic = System.IO.Path.GetFileName(file)
                .StartsWith("TESMODPLATFORM", StringComparison.OrdinalIgnoreCase);
            using (var fs = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (var br = new BinaryReader(fs, Encoding.UTF8))
            {
                byte[] magic = br.ReadBytes(13);
                if (Encoding.ASCII.GetString(magic) != "TESV_SAVEGAME") throw new Exception("not a Skyrim save");
                br.ReadUInt32();              // header size
                br.ReadUInt32();              // save format version
                br.ReadUInt32();              // save number
                string name = Str(br);
                int level = (int)br.ReadUInt32();
                Str(br);                      // location, shown in game but not here
                string played = Str(br);      // in game date, however the game chose to write it
                string race = Pretty(Str(br));

                if (!synthetic)
                {
                    w.Name = name;
                    w.Level = level;
                    w.Played = played;
                }
                w.Race = race;
            }
            w.Empty = false;
            w.When = File.GetLastWriteTime(file);
            return w;
        }

        /*
          Strings in a save header are length prefixed bytes with no encoding
          recorded anywhere, and they are not always UTF-8. SkyMP's scaffolding
          saves carry Windows-1251, so decoding everything as UTF-8 turned a
          name into a row of replacement characters rather than failing in any
          way that could be noticed.

          Strict UTF-8 first, so anything genuinely UTF-8 is read correctly.
          Windows-1252 second, because it maps every byte to something and can
          therefore never produce a replacement character. Better a name that
          is transliterated oddly than one that is seven black diamonds.
        */
        static readonly Encoding StrictUtf8 = new UTF8Encoding(false, true);
        static Encoding fallback;

        static string Str(BinaryReader br)
        {
            int n = br.ReadUInt16();
            if (n <= 0 || n > 4096) return "";
            byte[] raw = br.ReadBytes(n);

            try { return StrictUtf8.GetString(raw); }
            catch (DecoderFallbackException) { }

            if (fallback == null)
            {
                try { fallback = Encoding.GetEncoding(1252); }
                catch { fallback = Encoding.Default; }
            }
            try { return fallback.GetString(raw); }
            catch { return ""; }
        }

        // Race ids read like NordRace or HighElfRace. Nobody says that out loud.
        static string Pretty(string editorId)
        {
            if (string.IsNullOrEmpty(editorId)) return "";
            string s = editorId;
            if (s.EndsWith("Race", StringComparison.OrdinalIgnoreCase)) s = s.Substring(0, s.Length - 4);
            var sb = new StringBuilder();
            for (int i = 0; i < s.Length; i++)
            {
                if (i > 0 && char.IsUpper(s[i]) && !char.IsUpper(s[i - 1])) sb.Append(' ');
                sb.Append(s[i]);
            }
            return sb.ToString();
        }

        // ------------------------------------------------------- profile ids

        class Row
        {
            public int Slot;
            public int Id;
            public DateTime Played;
            public long Seconds;
            public string Trade = "";
            public string Town = "";
        }

        static List<Row> Rows()
        {
            var l = new List<Row>();
            try
            {
                if (!File.Exists(ProfileFile)) return l;
                foreach (string line in File.ReadAllLines(ProfileFile))
                {
                    string[] p = line.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                    if (p.Length < 2) continue;
                    var r = new Row();
                    if (!int.TryParse(p[0], out r.Slot)) continue;
                    if (!int.TryParse(p[1], out r.Id)) continue;
                    long ticks;
                    if (p.Length > 2 && long.TryParse(p[2], out ticks))
                    {
                        try { r.Played = new DateTime(ticks); } catch { }
                    }
                    long secs;
                    if (p.Length > 3 && long.TryParse(p[3], out secs) && secs >= 0) r.Seconds = secs;
                    if (p.Length > 4 && p[4] != "-") r.Trade = p[4];
                    if (p.Length > 5 && p[5] != "-") r.Town = p[5];
                    l.Add(r);
                }
            }
            catch { }
            return l;
        }

        static void Save(List<Row> rows)
        {
            try
            {
                Directory.CreateDirectory(Home);
                var sb = new StringBuilder();
                foreach (Row r in rows)
                {
                    sb.AppendLine(r.Slot + " " + r.Id + " " + r.Played.Ticks + " " + r.Seconds +
                                  " " + Dash(r.Trade) + " " + Dash(r.Town));
                }
                File.WriteAllText(ProfileFile, sb.ToString());
            }
            catch { }
        }

        static string Dash(string s)
        {
            if (string.IsNullOrEmpty(s)) return "-";
            // Whitespace would split into two fields and shift everything after
            // it. No gamemode key has any, but this file is also written by hand
            // when somebody is poking at it.
            return s.Replace(' ', '_');
        }

        static Row Find(List<Row> rows, int slot)
        {
            foreach (Row r in rows) if (r.Slot == slot) return r;
            return null;
        }

        /// <summary>The profile id a slot plays as, or 0 when it has none yet.</summary>
        public static int ProfileOf(int slot)
        {
            Row r = Find(Rows(), slot);
            return r == null ? 0 : r.Id;
        }

        /// <summary>
        /// An id the server has never seen, and nobody else's launcher will
        /// ever pick either.
        ///
        /// This used to count: the highest id in this machine's own list, plus
        /// one. Every launcher did exactly the same from exactly the same
        /// starting point, so everybody's second character was profile 2 and
        /// their third was profile 3. The server stores one character per
        /// profile id, so two people on two different machines both connected
        /// as profile 2 and both loaded the same character:
        ///
        ///     Connecting a user 1 with ip 216.82.9.54   -> 1 logged as 2
        ///     Connecting a user 2 with ip 24.168.10.118 -> 2 logged as 2
        ///     Loading character ff000000                (the same one, twice)
        ///
        /// Which also meant creation never ran for either of them: the server
        /// found a character that already existed and quite correctly left it
        /// alone. Months of "the trade menu never appears" was this.
        ///
        /// So the id is random over the whole positive range instead. With five
        /// people and a handful of characters each, a collision is not worth
        /// the arithmetic to describe. Ids are still never reused inside one
        /// install, because a returning id would hand back a deleted character.
        /// </summary>
        static int NextProfileId()
        {
            var taken = new List<int>();
            foreach (Row r in Rows()) taken.Add(r.Id);

            var bytes = new byte[4];
            using (var rng = System.Security.Cryptography.RandomNumberGenerator.Create())
            {
                for (int attempt = 0; attempt < 64; attempt++)
                {
                    rng.GetBytes(bytes);
                    long v = BitConverter.ToInt32(bytes, 0) & 0x7FFFFFFF;
                    int id = (int)(1000 + (v % 2000000000L));
                    if (!taken.Contains(id)) return id;
                }
            }

            // Sixty-four collisions in a row does not happen, but returning
            // something that might already be in use is worse than anything,
            // so walk up from the highest rather than guess again.
            int high = 1000;
            foreach (int t in taken) if (t > high) high = t;
            return high + 1;
        }

        static int Claim(int slot, bool fresh)
        {
            List<Row> rows = Rows();
            Row r = Find(rows, slot);

            if (r == null)
            {
                r = new Row();
                r.Slot = slot;
                // Always a new id. This used to hand slot one profile 1 when it
                // had no row, meaning "whoever has been playing up to now", and
                // that is how every fresh install with old single player saves
                // logged in as one shared character (17 Sep): Adopt moved the
                // saves into slot one, the card read them as a character and
                // said Play, and Claim(1, false) returned 1. Nobody legitimate
                // is on profile 1; it is the stale shared character.
                r.Id = NextProfileId();
                rows.Add(r);
            }
            else if (fresh)
            {
                r.Id = NextProfileId();
            }

            r.Played = DateTime.Now;
            Save(rows);
            return r.Id;
        }

        public static Who Read(int slot)
        {
            var w = new Who();
            w.Slot = slot;

            Row row = Find(Rows(), slot);
            if (row != null)
            {
                w.ProfileId = row.Id;
                w.LastPlayed = row.Played;
                w.PlaySeconds = row.Seconds;
                w.Trade = row.Trade;
                w.Town = row.Town;
                // A slot that has been played has a character on the server
                // even when there is no save file here to read, which is the
                // normal case after a fresh install or on somebody else's
                // machine. Calling that an empty slot would quietly offer to
                // make a second character over the top of it.
                if (row.Played != DateTime.MinValue) w.Empty = false;
            }

            try
            {
                string dir = SlotDir(slot);
                if (!Directory.Exists(dir)) return w;
                string[] saves = Directory.GetFiles(dir, "*.ess");
                w.Saves = saves.Length;
                if (saves.Length == 0) return w;

                string newest = saves[0];
                DateTime best = File.GetLastWriteTime(newest);
                for (int i = 1; i < saves.Length; i++)
                {
                    DateTime t = File.GetLastWriteTime(saves[i]);
                    if (t > best) { best = t; newest = saves[i]; }
                }
                var got = Header(newest, slot);
                // A save file alone is not a character. Under SkyMP the
                // character lives on the server and the profiles.txt row is
                // what says a slot has one. A slot with saves and no row is
                // holding somebody's old single player saves, and calling
                // that a character is what put Play over them.
                if (row == null) got.Empty = true;
                got.Saves = saves.Length;
                got.ProfileId = w.ProfileId;
                got.LastPlayed = w.LastPlayed;
                got.PlaySeconds = w.PlaySeconds;
                got.Trade = w.Trade;
                got.Town = w.Town;
                return got;
            }
            catch { return w; }
        }

        public static List<Who> All()
        {
            var l = new List<Who>();
            for (int i = 1; i <= Slots; i++) l.Add(Read(i));
            return l;
        }

        /// <summary>
        /// Add a finished session to a slot's total.
        ///
        /// Counted here rather than read out of the save, because under SkyMP
        /// the character lives on the server and there is frequently no save on
        /// this machine at all. Anything under a minute is dropped: a launch
        /// that crashed on the way in is not play time, and the crash log folder
        /// says there have been a few of those.
        /// </summary>
        public static void AddPlaytime(int slot, TimeSpan span)
        {
            if (slot <= 0) return;
            long secs = (long)span.TotalSeconds;
            if (secs < 60) return;
            // A session longer than a day is a clock change or a launcher left
            // open over a reboot, not somebody playing.
            if (secs > 86400) return;

            List<Row> rows = Rows();
            Row r = Find(rows, slot);
            if (r == null) return;
            r.Seconds += secs;
            r.Played = DateTime.Now;
            Save(rows);
        }

        /// <summary>Remember what the launcher asked for when this character was made.</summary>
        public static void SetChoice(int slot, string trade, string town)
        {
            List<Row> rows = Rows();
            Row r = Find(rows, slot);
            if (r == null) return;
            r.Trade = trade ?? "";
            r.Town = town ?? "";
            Save(rows);
        }

        /// <summary>"3h 12m", or empty when nobody has played long enough to count.</summary>
        public static string PlayedText(long seconds)
        {
            if (seconds < 60) return "";
            long h = seconds / 3600;
            long m = (seconds % 3600) / 60;
            if (h > 0) return h + "h " + m + "m played";
            return m + "m played";
        }

        public static int Active()
        {
            try { if (File.Exists(ActiveFile)) return int.Parse(File.ReadAllText(ActiveFile).Trim()); }
            catch { }
            return 0;
        }

        // ------------------------------------------------------------ moving

        static bool IsLink(string p) { return Junction.IsLink(p); }

        /// <summary>
        /// First run on a build that already has saves in it. Those belong to
        /// somebody, so they become character one rather than being stranded.
        /// </summary>
        public static void Adopt()
        {
            // Only the slot folders are made here now. This used to move the
            // saves in the real Saves folder into character one so they would
            // not be stranded, which was right when a save was the character.
            // Under SkyMP a save on this disk is nobody's character, and moving
            // somebody's single player saves into slot one made the card read
            // them as a Thornswood character (see Read and Claim). Use sets the
            // real folder aside whole instead, and nothing is moved into a slot.
            Directory.CreateDirectory(Home);
            for (int i = 1; i <= Slots; i++) Directory.CreateDirectory(SlotDir(i));
        }

        /// <summary>
        /// Point Skyrim's save folder at one character and tell Start On Save
        /// what to do. Returns a line for the log when the folder could not be
        /// pointed and the plain one is in use instead, otherwise null.
        ///
        /// This used to throw, and Play stopped, with one line in the log and
        /// no reason (a tester on 1.1.36: "Could not point the save folder at
        /// character 1."). Under SkyMP nothing on this disk decides who the
        /// character is (see WriteStartIni), so a save folder that cannot be
        /// redirected is not a reason to keep anybody out of the game.
        /// </summary>
        public static string Use(int slot, bool fresh)
        {
            Directory.CreateDirectory(Home);
            Directory.CreateDirectory(SlotDir(slot));

            string live = Files.SaveDir;
            Directory.CreateDirectory(Path.GetDirectoryName(live));

            string trouble = null;
            string setAside = null;
            if (IsLink(live))
            {
                try { Directory.Delete(live); }
                catch (Exception ex) { trouble = "the old link would not come off: " + ex.Message; }
            }
            else if (Directory.Exists(live))
            {
                // A real folder here is somebody's own Skyrim saves, and they
                // are never deleted. This used to Adopt them into slot one and
                // then Directory.Delete the folder recursively; Adopt declined
                // whenever slot one already had a save, and the delete took the
                // person's saves with it. A folder with anything in it is set
                // aside whole, next to where it was, under a name that says
                // what it is. Only an empty one is removed.
                bool empty = false;
                try { empty = Directory.GetFileSystemEntries(live).Length == 0; } catch { }
                if (empty)
                {
                    try { Directory.Delete(live); }
                    catch (Exception ex) { trouble = "the empty Saves folder would not come off: " + ex.Message; }
                }
                else
                {
                    string aside = live + "-before-Thornswood-" + DateTime.Now.ToString("yyyyMMdd-HHmmss");
                    try
                    {
                        Directory.Move(live, aside);
                        setAside = "Your own Skyrim saves were set aside whole in " + aside + ". Nothing was deleted.";
                    }
                    catch (Exception ex2)
                    {
                        trouble = "the Saves folder has files in it and would not move aside (" + ex2.Message.TrimEnd('.') + ")";
                    }
                }
            }

            string note = null;
            string why = null;
            bool linked = trouble == null && Junction.Create(live, SlotDir(slot), out why);
            if (linked)
            {
                Scrub(SlotDir(slot));
            }
            else
            {
                try { Directory.CreateDirectory(live); } catch { }
                Scrub(live);
                note = "Could not point the save folder at character " + slot + ": " + (trouble ?? why) +
                       ". Skyrim is using the ordinary Saves folder on this computer instead. Your character lives on the server, so nothing is lost." +
                       (live.IndexOf("\\OneDrive", StringComparison.OrdinalIgnoreCase) >= 0 ? " (That folder is inside OneDrive.)" : "");
            }

            // The part that actually decides who you are. Everything above this
            // line only moves save files about.
            int id = Claim(slot, fresh);
            AutoJoin.SetProfileId(id);

            // Read it back rather than trust the write. SetProfileId answers
            // false both when it could not write the file and when the file
            // already held this id, so its answer cannot tell those apart, and
            // the file is the only thing that decides which character the
            // client asks the server for. A read only settings file, or one
            // holding the id as "3" in quotes where the edit does not match it,
            // keeps the number the last slot left there and the game walks in
            // as that character. Stop here instead: StartAs logs this and never
            // reaches Play, which beats handing somebody another character.
            int wrote = AutoJoin.GetProfileId();
            if (wrote != id)
                throw new Exception(
                    "Character " + slot + "'s id could not be written into the client settings: they still say " +
                    (wrote > 0 ? "profile " + wrote : "no profile") + " instead of profile " + id + ". " +
                    "Skyrim would have connected as the character before this one, so it was not started. " +
                    "Check that Data\\Platform\\Plugins\\skymp5-client-settings.txt is not read only.");

            // Voice read the old id out of the settings file at startup and has
            // been using it ever since. The line above just changed it.
            Voice.Reconfigure();

            try { File.WriteAllText(ActiveFile, slot.ToString()); } catch { }
            WriteStartIni(fresh);
            WriteBrowserBackend();
            if (setAside != null) note = (note == null ? "" : note + " ") + setAside;
            return note;
        }

        /// <summary>
        /// Throw away SkyrimPlatform's scaffolding saves.
        ///
        /// When SkyMP spawns somebody by loading a save it does not use one of
        /// theirs. It writes one on the spot, TESMODPLATFORM-&lt;guid&gt;.ess, fills
        /// the header with placeholder text and loads that. The file is a
        /// stepping stone and it is finished with the moment the load completes.
        ///
        /// It is also left lying in the save folder, four and a half megabytes
        /// of it per spawn, and it is now the newest file in there. Anything
        /// that reaches for "the most recent save" finds it, and it is not a
        /// save: it is a shell with no world behind it. Loading one gets you a
        /// black screen if you are lucky and a null pointer thirty seconds into
        /// startup if you are not, which is the crash sitting in
        /// crash-2026-09-13-17-45-02.log with po3_StartOnSave's hook on the
        /// stack and rcx at zero.
        ///
        /// This machine's save folder had nothing else left in it. Two
        /// scaffolding files and no real save, each one written by the spawn
        /// before it and loaded by the launch after it.
        ///
        /// So they go, every launch, before the game can see them. Nothing is
        /// lost: a character on this server lives in the server's world file,
        /// and these were never anybody's.
        /// </summary>
        static void Scrub(string dir)
        {
            try
            {
                if (!Directory.Exists(dir)) return;
                foreach (string f in Directory.GetFiles(dir, "TESMODPLATFORM-*.ess"))
                {
                    try { File.Delete(f); } catch { }
                }
                // The .skse companion Skyrim writes beside each save.
                foreach (string f in Directory.GetFiles(dir, "TESMODPLATFORM-*.skse"))
                {
                    try { File.Delete(f); } catch { }
                }
            }
            catch { }
        }

        // Written fresh every launch, and what it writes is "do nothing".
        //
        // Start On Save used to be how the launcher reached past the main menu:
        // point the save folder at one character, set bStartNewGame, and let it
        // load the newest save or start a new game when there was none.
        //
        // Under SkyMP that job is already taken. When the server sends
        // CreateActor for your own character the client calls
        //
        //     loadGameService.loadGame(pos, rot, worldOrCell, appearance, loadOrder)
        //
        // which walks you from the main menu to wherever the server says you
        // are, with the body and the face the server holds. Nothing here has to
        // press anything, and a character that lives on the server has nothing
        // on this disk worth loading anyway.
        //
        // Leaving bStartNewGame true meant Start On Save pressed New Game at the
        // main menu, Skyrim Unbound's alternate start began, and SkyMP's own
        // load landed on top of a game that was still loading. Two loads through
        // one BGSSaveLoadManager, about thirty seconds in, every single launch:
        //
        //   crash-2026-09-13-01-20-50   uptime 33s   po3_StartOnSave.dll frame 4
        //   crash-2026-09-13-01-14-07   uptime 30s   po3_StartOnSave.dll frame 11
        //   crash-2026-09-12-18-53-41   uptime 42s   inside the allocator's free
        //
        // It is also why creation flashed up for a moment and then teleported
        // somebody who had not finished making a face: Unbound's start was being
        // interrupted part way through.
        //
        // The mod stays installed, because the build ships it and Verify checks
        // the file list. It is simply told to stand still.
        //
        // Standing still takes more than bStartNewGame false. Read from the
        // mod's own source (powerof3/Start-On-Save, Hooks.cpp): when the load
        // spinner first opens it builds the save list, and if that list is
        // not empty and sSaveFile names nothing, it loads the newest save in
        // it, full stop. bStartNewGame only decides what happens when the
        // list is EMPTY. The list is empty on a machine whose slot folder
        // holds nothing, which is most of them. It is not empty on a fresh
        // install where Skyrim had been played before: Adopt moves that
        // person's own saves into character one, the junction points Saves
        // at that folder, and the newest of those saves was loaded at the
        // main menu while SkyMP was loading its own. That is the install on
        // 17 Sep whose slot showed a level 21 from single player and whose
        // game closed after 0 minutes, and it is the thirty second crashes
        // above with a different lever.
        //
        // The one filter the mod applies before loading is sCharacterName:
        // the save's character has to carry that exact name. No save does
        // carry the one below, so nothing qualifies and nothing is loaded,
        // whatever is in the folder.
        static void WriteStartIni(bool fresh)
        {
            try
            {
                string dir = Path.GetDirectoryName(StartIni);
                Directory.CreateDirectory(dir);
                var sb = new StringBuilder();
                sb.AppendLine("; Written by the Thornswood launcher every time you press Play.");
                sb.AppendLine("; Editing it by hand will not stick.");
                sb.AppendLine(";");
                sb.AppendLine("; This file tells Start On Save to load nothing. SkyMP loads you into");
                sb.AppendLine("; the world itself once the server has made your character, and a second");
                sb.AppendLine("; load running at the same time crashes the game about thirty seconds in.");
                sb.AppendLine(";");
                sb.AppendLine("; bStartNewGame false is not enough for that: with sSaveFile blank the mod");
                sb.AppendLine("; loads the newest save in the Saves folder whenever there is one. The");
                sb.AppendLine("; character name below is the one filter it applies first. No save");
                sb.AppendLine("; carries that name, so nothing qualifies.");
                sb.AppendLine("[Settings]");
                sb.AppendLine("sSaveFile =");
                sb.AppendLine("sCharacterName = Thornswood-Nobody");
                sb.AppendLine("iSaveType = 0");
                sb.AppendLine("bStartNewGame = false");
                sb.AppendLine("iSkipAutoLoadHotkey = 16");
                sb.AppendLine("bDisableMissingContentWarning = true");
                File.WriteAllText(StartIni, sb.ToString());
            }
            catch { }
        }

        static string PlatformIni
        {
            get { return Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\SkyrimPlatform.ini"); }
        }

        /// <summary>
        /// Which in game browser SkyrimPlatform uses. Ours, wherever ours is
        /// present, which is everywhere.
        ///
        /// There are two backends. tilted is the CEF stack built into
        /// SkyrimPlatform. Its runtime lives in Data\Platform\Distribution,
        /// it goes out inside the installer, it draws inside the game's own
        /// process, and there is no executable anywhere in that folder.
        /// nirnlab is the NirnLab UI Platform SKSE plugin and it draws out of
        /// process: Data\NirnLabUIPlatform\CEFSubprocess.exe is a
        /// second program, so the first time it runs Windows Firewall stops
        /// the game to ask about a name nobody recognises.
        ///
        /// NirnLab is not ours. Package-Thornswood lists NirnLabUIPlatform
        /// among the folders that never go into the installer, and
        /// Clean-OtherServers names it as another roleplay server's interface
        /// framework. Machines that have it got it from that server's
        /// collection. Every other part of this repo treats it as somebody
        /// else's. This method used to be the one place that went looking for
        /// it and handed our own interface to it, firewall prompt and all, on
        /// the machines unlucky enough to have both installed.
        ///
        /// So the folder decides, and NirnLab wins where it is present. Not
        /// because it is better but because tilted will not run beside it:
        /// NirnLab puts its own directory on the process PATH and
        /// SkyrimPlatform stops on that before the game draws anything. A
        /// machine with NirnLab in the folder has one working answer.
        ///
        /// Which means the firewall prompt is not fixable from here. It goes
        /// when NirnLab is not in the folder, and Thornswood only controls
        /// that in the game folder it builds itself.
        ///
        /// The file is edited, never rewritten. It also carries the log level,
        /// the console window geometry and the plugin folder list, none of
        /// which are ours to invent.
        /// </summary>
        static void WriteBrowserBackend()
        {
            try
            {
                if (!File.Exists(PlatformIni)) return;

                // One file, and it is not in SKSE\Plugins.
                //
                // NirnLab is not loaded by the script extender. SkyrimPlatform
                // loads it itself, which is why skse64.log shows SkyrimPlatform
                // registering a listener called NirnLabUIPlatform and no plugin
                // of that name in its own scan. Nexus 125447 deploys exactly
                // Data\NirnLabUIPlatform\NirnLabUIPlatform.dll and nothing into
                // SKSE\Plugins, so testing for a NirnLabUIPlugin.dll there is
                // testing for a file that never exists and pins everybody to
                // tilted no matter what they have installed.
                bool nirnlab = File.Exists(Path.Combine(
                    Paths.Game, "Data\\NirnLabUIPlatform\\NirnLabUIPlatform.dll"));

                // nirnlab wins whenever NirnLab is on disk, and this is not a
                // preference. SkyrimPlatform refuses to start on tilted while
                // NirnLab is in the folder: NirnLab puts its own directory on
                // the process PATH, its libcef.dll would be loaded instead of
                // the one in Distribution, and SkyrimPlatform stops with a
                // box reading "Your PATH environment variable contains
                // incompatible entries" before the game draws anything.
                //
                // Measured on 17 Sep. This method was changed to prefer
                // tilted, a launcher carrying that change wrote tilted into
                // a game folder that had NirnLab in it, and the next Play
                // produced exactly that box. Choosing tilted here is not a
                // way to get rid of the CEFSubprocess.exe firewall prompt.
                // The only way to get rid of that is for NirnLab not to be
                // in the folder at all, which is New-GameFolder's job when
                // Thornswood builds a folder of its own.
                string want = nirnlab ? "nirnlab" : "tilted";

                string text = File.ReadAllText(PlatformIni);
                var rx = new System.Text.RegularExpressions.Regex(
                    @"(?im)^[ \t]*BackendName[ \t]*=.*$");

                string next;
                if (rx.IsMatch(text))
                {
                    next = rx.Replace(text, "BackendName = " + want);
                }
                else
                {
                    // No [Browser] section at all, which is how a stock
                    // SkyrimPlatform.ini arrives. Adding one is the whole fix.
                    next = text.TrimEnd() + Environment.NewLine + Environment.NewLine +
                           "[Browser]" + Environment.NewLine +
                           "BackendName = " + want + Environment.NewLine;
                }

                if (next == text) return;

                // The file arrives with a byte order mark and SkyrimPlatform
                // reads it happily, so keep one rather than quietly changing
                // the encoding of a file this launcher does not own.
                File.WriteAllText(PlatformIni, next, new UTF8Encoding(true));
            }
            catch { }
        }

        /// <summary>Moves a character aside rather than destroying them.</summary>
        public static string Delete(int slot)
        {
            string dir = SlotDir(slot);
            if (!Directory.Exists(dir)) return null;

            Directory.CreateDirectory(Bin);
            string stamp = DateTime.Now.ToString("yyyyMMdd-HHmmss");
            string dest = Path.Combine(Bin, slot + "-" + stamp);

            // If this character is the one currently linked, let go first.
            string live = Files.SaveDir;
            if (IsLink(live) && Active() == slot) { try { Directory.Delete(live); } catch { } }

            Directory.Move(dir, dest);
            Directory.CreateDirectory(dir);

            // Forget the profile id too, or the slot would come back looking
            // empty and then reconnect as the character that was just deleted.
            // The id itself is retired rather than freed: NextProfileId only
            // ever counts upwards.
            List<Row> rows = Rows();
            Row r = Find(rows, slot);
            if (r != null) { rows.Remove(r); Save(rows); }

            if (Active() == slot) { try { File.Delete(ActiveFile); } catch { } }
            return dest;
        }
    }
}
