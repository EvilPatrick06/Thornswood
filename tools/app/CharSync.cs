using System;
using System.Collections.Generic;

namespace Thornswood
{
    // The half of Chars that talks to the server.
    //
    // In its own file for a boring reason worth writing down: Chars.cs is the
    // one file where a bad edit costs somebody their character list, and it was
    // already overwritten once from a stale copy during this work. Nothing here
    // needs to be in there, so nothing here is.
    static partial class Chars
    {
        /// <summary>
        /// Line the local character list up with what the server has for this
        /// Steam account.
        ///
        /// This is what makes a character survive a reinstall or a different
        /// computer. The character itself never moved: it is a change form the
        /// game server holds, keyed by a profile id. The id is the fragile
        /// part, because it lived only in profiles.txt in this folder, so
        /// losing that file lost the only thing on earth that knew which
        /// character on the server was yours.
        ///
        /// Two directions, and what is already here decides which runs:
        ///
        ///     nothing here    take the server's list. A fresh install, or a
        ///                     machine this person has never played on, and
        ///                     their characters come back.
        ///     something here  send it up. This machine is the one being
        ///                     played, so it is the truth and the server is
        ///                     told rather than asked. That is also what
        ///                     carries characters made before any of this
        ///                     existed: nothing about them changes, their ids
        ///                     just stop being known only to one hard drive.
        ///
        /// A slot the server knows and this machine does not is filled in
        /// either way, so making a second character on a laptop and then
        /// playing on a desktop brings it along.
        ///
        /// Returns something worth showing the person, or null when the answer
        /// was "nothing to do", which is almost every launch. Never throws: the
        /// server being unreachable has to leave the launcher working exactly
        /// as it did before, because the alternative is a bad night for the VPS
        /// standing between somebody and their game.
        /// </summary>
        /*
          Raised once Sync has finished, however it finished.

          Pressing Play before the server has answered is not a hypothetical.
          Claim in Chars.cs hands slot one profile id 1 when there is no local
          list yet, and every install on earth would pick that same 1, which is
          the shared character bug that cost months. Restore is what stops a
          fresh install ever being in that state, so Play has to be willing to
          wait a moment for it rather than race it.

          Starts raised and is lowered by Sync itself, so a launcher where this
          never runs at all never waits on it.
        */
        static readonly System.Threading.ManualResetEvent synced =
            new System.Threading.ManualResetEvent(true);

        /// <summary>
        /// Hold until the server has been heard from, or the wait runs out.
        ///
        /// Only worth calling when there is no local character list, because
        /// that is the only case where the answer changes what happens next.
        /// Returns false when it gave up, which is not an error: the launcher
        /// carries on exactly as it did before any of this existed.
        /// </summary>
        public static bool WaitForSync(int ms)
        {
            try { return synced.WaitOne(ms); } catch { return true; }
        }

        /// <summary>True when this machine has no character list of its own.</summary>
        public static bool Blank()
        {
            try { return Rows().Count == 0; } catch { return false; }
        }

        public static string Sync(Config cfg)
        {
            try { synced.Reset(); } catch { }
            try { return SyncInner(cfg); }
            finally { try { synced.Set(); } catch { } }
        }

        static string SyncInner(Config cfg)
        {
            string steam;
            try { steam = Steam.Id(); } catch { return null; }
            if (string.IsNullOrEmpty(steam)) return null;

            List<Row> local = Rows();
            List<Account.Entry> mine;
            try { mine = Account.Whoami(cfg, steam); } catch { return null; }
            if (mine == null) mine = new List<Account.Entry>();

            // ---- anything the server knows about a slot we have never heard of
            bool grew = false;
            foreach (Account.Entry e in mine)
            {
                if (e.Slot < 1 || e.Slot > Slots) continue;
                if (e.ProfileId <= 0) continue;
                if (Find(local, e.Slot) != null) continue;

                var r = new Row();
                r.Slot = e.Slot;
                r.Id = e.ProfileId;

                // A played date is kept because the slot list uses it to decide
                // whether anybody is in a slot. A restored character with no
                // date reads as empty and gets offered up to be written over,
                // which would be this feature handing back a character and then
                // inviting you to destroy it.
                try { if (e.Played > 0) r.Played = new DateTime(e.Played); }
                catch { r.Played = DateTime.Now; }
                if (r.Played == DateTime.MinValue) r.Played = DateTime.Now;

                // The rest of what the launcher shows. Without these a
                // restored character sits in the list with no trade, no town
                // and no hours against it, which looks like a restore that
                // half worked rather than one that worked.
                r.Seconds = e.Seconds;
                r.Trade = e.Trade ?? "";
                r.Town = e.Town ?? "";

                local.Add(r);
                grew = true;
            }

            if (grew)
            {
                Save(local);
                return "Your character list came back from the server.";
            }

            // ---- otherwise tell the server what this machine has
            if (local.Count == 0) return null;

            var list = new List<Account.Entry>();
            foreach (Row r in local)
            {
                if (r.Id <= 0) continue;
                var e = new Account.Entry();
                e.Slot = r.Slot;
                e.ProfileId = r.Id;
                e.Played = r.Played.Ticks;
                e.Seconds = r.Seconds;
                e.Trade = r.Trade ?? "";
                e.Town = r.Town ?? "";

                // Only so the wipe tool shows a name instead of a number. It
                // reads a save header off disk, so it is allowed to fail.
                try { Who w = Read(r.Slot); if (w != null && w.Name != null) e.Name = w.Name; }
                catch { }

                list.Add(e);
            }
            if (list.Count == 0) return null;

            try { Account.Claim(cfg, steam, list); } catch { }
            return null;
        }
    }
}
