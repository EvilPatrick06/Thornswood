using System;
using System.Globalization;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;

namespace Thornswood
{
    [DataContract]
    public class Config
    {
        [DataMember] public string ServerAddress = "192.135.112.23";
        // SkyMP's default. 25565 was Skyrim Together's, on the old box.
        [DataMember] public string ServerPort = "7777";

        /*
          The Nexus collection that installs the mods.

          The installer stopped carrying them: anything the collection provides
          is left out of it, which is what took it from fourteen gigabytes to
          something somebody will actually finish downloading. That trade only
          works if the launcher sends people to the collection, so a build with
          this empty and an installer built against a collection is a build
          nobody can play.

          It comes down with the update check like the server address does, so
          it can be set once and everybody has it.
        */
        [DataMember] public string CollectionUrl = Collection;

        // The one we ship with. The update check overwrites it, but a
        // launcher that has never reached the site still has to be able to
        // send somebody to the collection, because that is exactly the
        // state somebody installing for the first time is in.
        public const string Collection =
            "https://www.nexusmods.com/games/skyrimspecialedition/collections/ombo2a";

        // Where a server on this machine lives, when the address above is this
        // machine. Blank means look in the usual two places.
        [DataMember] public string ServerFolder = "";

        // Proximity voice runs beside the game server on its own port. The
        // audio goes straight between people; this is only where the browser
        // window connects for positions and signalling.
        [DataMember] public string VoicePort = "7778";

        /// <summary>
        /// Where the voice service is, when it is not simply the server address
        /// and a port. Empty means it is, which is how this has always worked.
        /// </summary>
        /// <remarks>
        /// Set this to https://thornswood.net/voice and everything voice does
        /// goes through Caddy on 443 instead of the raw port: one door with a
        /// certificate on it, and wss:// rather than ws://, so nobody's voice
        /// signalling crosses the internet in the clear.
        ///
        /// It stays empty until the launchers that understand it have gone out.
        /// A launcher that has never heard of this setting connects to the raw
        /// port, so the port has to keep answering until they are all replaced.
        /// </remarks>
        [DataMember] public string VoiceUrl = "";

        /// <summary>
        /// The voice service as a base address, with no trailing slash.
        /// </summary>
        public string VoiceBase()
        {
            string u = VoiceUrl == null ? "" : VoiceUrl.Trim();
            while (u.EndsWith("/")) { u = u.Substring(0, u.Length - 1); }
            if (u.Length > 0) { return u; }
            string p = VoicePort == null ? "" : VoicePort.Trim();
            if (p.Length == 0) { p = "7778"; }
            return "http://" + (ServerAddress == null ? "" : ServerAddress) + ":" + p;
        }

        /// <summary>
        /// The same address as a WebSocket url, so a secure base gives wss.
        /// </summary>
        public string VoiceSocket()
        {
            string b = VoiceBase();
            if (b.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                return "wss://" + b.Substring(8) + "/";
            }
            if (b.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
            {
                return "ws://" + b.Substring(7) + "/";
            }
            return b + "/";
        }

        /*
          Which microphone to record from, by name, or empty for whatever
          Windows is set to.

          It lives here rather than in Thornswood.ini because the ini is a mod
          file: an update replaces it wholesale, so anything set in it by hand
          is gone the next time the build changes. The launcher copies this
          into the ini at every launch, which also means somebody who never
          touches it still gets their own machine's default written in rather
          than whoever built the release.
        */
        [DataMember] public string MicrophoneName = "";

        [DataMember(Name = "VoiceAuto")] public bool? VoiceAutoSetting = true;

        public bool VoiceAuto
        {
            get { return VoiceAutoSetting != false; }
            set { VoiceAutoSetting = value; }
        }
        // How many the server seats. Shipped with the build so the Play page
        // can say something useful even when the server does not announce itself.
        [DataMember] public int MaxOnline = 25;

        // Skyrim Together took a password on its join screen and the launcher
        // typed it in for people. SkyMP has no such screen: the client reads an
        // address and a port and connects. Kept so an older config.json still
        // loads, and as somewhere to put one if a gate is added later.
        [DataMember] public long ExpectedExeBytes = 37157144;

        // Set these to turn on updates. Leave blank and the launcher never
        // talks to the network beyond a ping.
        // UpdateToken is a problem worth naming rather than leaving implicit.
        // It is written into config.json in plaintext and that file ships to
        // every machine that installs the build, so it is only ever as private
        // as the least careful person holding it, and revoking it breaks
        // updates for all of them at once. A read-only fine-grained PAT limits
        // the damage without fixing the shape. The real fix is a release
        // channel that needs no credential, at which point this field goes.
        [DataMember] public string UpdateRepo = "";    // "owner/name"
        [DataMember] public string UpdateToken = "";   // read-only fine-grained PAT
        [DataMember] public string UpdateBranch = "main";

        [DataMember] public string Theme = "Forge";

        /*
          Which build this install follows. Empty is the main build, the one
          everybody plays on. "dev" is the second launcher, installed beside
          the main one from its Settings page, that reads version.json off
          the dev branch and joins the dev server. New work lands there
          first and gets broken there, so the main build stays playable
          while it is being tested.
        */
        [DataMember] public string Channel = "";

        public bool IsDev
        {
            get { return string.Equals(Channel, "dev", StringComparison.OrdinalIgnoreCase); }
        }

        /// <summary>What this build is called in titles, shortcuts and Discord.</summary>
        public string BuildName
        {
            get { return IsDev ? "Thornswood Dev" : "Thornswood"; }
        }

        // The Thornswood application on Discord, the same one the sign in
        // goes through. The presence card ("Playing Thornswood") is set under
        // it, so it carries that application's name and art. Application ids
        // are public, this is not a secret.
        [DataMember] public string DiscordAppId = "1549251507361292418";

        // Where the Download button on the presence card goes, and the root
        // the Discord button is built from (SiteUrl + /discord).
        [DataMember] public string SiteUrl = "https://thornswood.net";

        // The picture on the presence card. A public https image; Discord
        // fetches it itself. Empty turns the picture off.
        [DataMember] public string PresenceImage = "https://thornswood.net/presence.png";

        // Set the first time the launcher matches the game to this screen, so
        // it never does it again and never argues with a choice made since.
        // A plain bool is right here: absent means it has not happened, which
        // is exactly what false means.
        [DataMember] public bool DisplaySet = false;

        [DataMember] public bool KeepLauncherOpen = false;

        // Ticked, the launcher stops matching the game's resolution to the
        // screen when you press Play. For anyone deliberately running the game
        // at something other than what the monitor is set to.
        [DataMember] public bool LockResolution = false;

        // The launcher's music: off, or a volume from 0 to 100. Asked for by
        // Patrick on 20 September, the day the dev test track went in
        // (Shell.StartMenuMusic). Nothing plays on the main build yet.
        //
        // Stored the way round that makes ABSENT mean on and half: the
        // deserializer skips field initialisers (see AfterLoad), so a bool
        // that was not in the file is false and an int is 0, and the first
        // config.json with no music fields in it came up switched off and
        // silent. A false MusicOff is on; a null MusicLevel is 50.
        [DataMember] public bool MusicOff = false;
        [DataMember] public string MusicLevel = "50";

        public bool MusicOn
        {
            get { return !MusicOff; }
            set { MusicOff = !value; }
        }

        public int MusicVolume
        {
            get
            {
                int v;
                if (!int.TryParse(MusicLevel, out v)) return 50;
                return Math.Max(0, Math.Min(100, v));
            }
            set { MusicLevel = Math.Max(0, Math.Min(100, value)).ToString(); }
        }

        // The Skyrim folder Vortex deploys into, which Thornswood's own folder is
        // made from (see OwnGame). Blank means the Steam copy. Set it when Vortex
        // has been moved to a folder of its own so the Steam copy can stay clean.
        [DataMember] public string VortexGame = "";

        // These two default to ON, which a plain bool cannot express here: the
        // serializer skips field initialisers, and false and absent look the
        // same afterwards. So an older config.json, which has neither key,
        // would quietly come back with both switched off. Nullable tells the
        // two apart, and only an explicit false counts as off.
        // Ticked, a server this launcher started is stopped again when the
        // launcher closes, so it is not left holding the port.
        [DataMember(Name = "StopServerOnExit")] public bool? StopServerSetting = true;

        public bool StopServerOnExit
        {
            get { return StopServerSetting != false; }
            set { StopServerSetting = value; }
        }

        [DataMember(Name = "AutoUpdate")] public bool? AutoUpdateSetting = true;
        [DataMember(Name = "AutoJoin")]   public bool? AutoJoinSetting = true;

        public bool AutoUpdate
        {
            get { return AutoUpdateSetting != false; }
            set { AutoUpdateSetting = value; }
        }

        public bool AutoJoin
        {
            get { return AutoJoinSetting != false; }
            set { AutoJoinSetting = value; }
        }

        // DataContractSerializer builds the object without running field
        // initialisers, so anything absent from the file comes back null or 0.
        [OnDeserialized]
        void AfterLoad(StreamingContext ctx)
        {
            if (string.IsNullOrEmpty(ServerAddress)) ServerAddress = "192.135.112.23";
            if (string.IsNullOrEmpty(ServerPort)) ServerPort = "7777";
            if (ServerFolder == null) ServerFolder = "";
            if (string.IsNullOrEmpty(CollectionUrl)) CollectionUrl = Collection;
            if (string.IsNullOrEmpty(VoicePort)) VoicePort = "7778";
            if (VoiceUrl == null) VoiceUrl = "";
            VoiceUrl = VoiceUrl.Trim();
            while (VoiceUrl.EndsWith("/")) { VoiceUrl = VoiceUrl.Substring(0, VoiceUrl.Length - 1); }

            // The old build ran Skyrim Together Reborn on 25565, on a different
            // box. SkyMP does not listen there and that machine is not running
            // anything, so a config carried over from then points everyone at
            // nothing and the launcher would report "not answering" forever
            // without ever saying why. Only these two exact values are moved:
            // anything else is a choice somebody made.
            if (ServerPort == "25565") ServerPort = "7777";
            if (ServerAddress == "192.135.119.166") ServerAddress = "192.135.112.23";
            if (ExpectedExeBytes <= 0) ExpectedExeBytes = 37157144;
            // The releases repo is public now, so there is a right answer here
            // and no reason to make a fresh install go looking for it. A blank
            // one used to mean a launcher that could never update itself and
            // never said why.
            if (string.IsNullOrEmpty(UpdateRepo)) UpdateRepo = "EvilPatrick06/Thornswood-Releases";
            if (UpdateToken == null) UpdateToken = "";
            if (string.IsNullOrEmpty(UpdateBranch)) UpdateBranch = "main";
            if (string.IsNullOrEmpty(Theme)) Theme = "Forge";
            if (Channel == null) Channel = "";
            if (string.IsNullOrEmpty(DiscordAppId)) DiscordAppId = "1549251507361292418";
            if (string.IsNullOrEmpty(SiteUrl)) SiteUrl = "https://thornswood.net";
            if (PresenceImage == null) PresenceImage = "https://thornswood.net/presence.png";
            if (VortexGame == null) VortexGame = "";
        }

        public static Config Load(string path)
        {
            try
            {
                if (File.Exists(path))
                {
                    // Notepad and PowerShell both like to write a UTF-8 byte order
                    // mark, and the JSON reader refuses to parse past one. Losing
                    // the config here would silently turn updates off, so it goes.
                    byte[] raw = File.ReadAllBytes(path);
                    int skip = (raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) ? 3 : 0;
                    using (var ms = new MemoryStream(raw, skip, raw.Length - skip))
                    {
                        var ser = new DataContractJsonSerializer(typeof(Config));
                        var c = (Config)ser.ReadObject(ms);
                        if (c != null)
                        {
                            // On the disk these two are DPAPI blobs. Everywhere
                            // else in the launcher they are ordinary strings, so
                            // they get turned back here and nowhere else.
                            // Anything written before this existed is plain text
                            // and comes back through unchanged, then gets
                            // encrypted by the next Save.
                            c.UpdateToken    = Secrets.Unprotect(c.UpdateToken);
                            return c;
                        }
                    }
                }
            }
            catch { }
            return new Config();
        }

                public void Save(string path)
        {
            string tk = UpdateToken;
            try
            {
                UpdateToken = Secrets.Protect(tk);
                using (var ms = new MemoryStream())
                {
                    new DataContractJsonSerializer(typeof(Config)).WriteObject(ms, this);
                    File.WriteAllBytes(path, ms.ToArray());
                }
                Secrets.LockDown(path);
            }
            // Still no throw, so every caller behaves as it did, but a Save
            // that failed now says so in launcher.log. It used to be the
            // tester saying the Save button did nothing, and nothing else.
            catch (Exception ex) { Swallow.Note("Config.Save, writing " + path, ex); }
            finally
            {
                UpdateToken = tk;
            }
        }
    }

    [DataContract]
    public class Pack
    {
        [DataMember] public string id = "";
        [DataMember] public string url = "";
        [DataMember] public string sha256 = "";
        [DataMember] public string notes = "";

        // Only the optional packs use these two. A required update pack is
        // applied without anybody being asked, so it has nothing to show and
        // no download size worth warning about. An optional one sits on a page
        // with a button next to it and needs both.
        [DataMember] public string name = "";
        [DataMember] public long bytes;

        public string Title { get { return string.IsNullOrEmpty(name) ? id : name; } }

        public string Size
        {
            get
            {
                if (bytes <= 0) return "";
                if (bytes >= 1073741824L) return (bytes / 1073741824.0).ToString("0.0") + " GB";
                if (bytes >= 1048576L) return (bytes / 1048576.0).ToString("0") + " MB";
                return (bytes / 1024.0).ToString("0") + " KB";
            }
        }
    }

    [DataContract]
    public class NewsItem
    {
        [DataMember] public string date = "";
        [DataMember] public string title = "";
        [DataMember] public string body = "";
        // What actually moved in that release, one line each. Written by
        // Publish-Update from the diff rather than by hand, so it says the
        // same thing whether or not anyone remembered to write a good note.
        [DataMember] public string[] details = null;
        // Every file that moved in that release, so a release can be read
        // rather than taken on trust. Capped by the publisher.
        [DataMember] public string[] files = null;

        // Which build this note came out on. Empty is main, the build
        // everybody plays. "dev" is a dev release, and only the dev
        // launcher ever sees one: its feed carries main's whole history
        // with the dev notes sitting on top, so without this there is no
        // way to look at the News tab and tell which is which.
        //
        // Written by the publisher on every dev release, over the whole
        // list rather than only the new entry, by asking main's feed what
        // it has. So it corrects itself: a note marked dev that reaches
        // main loses the mark on the next dev release without anybody
        // editing anything.
        [DataMember] public string channel = "";

        public bool IsDev
        {
            get { return channel == "dev"; }
        }

        /// <summary>
        /// The date as it is shown, month first and with the time on it.
        ///
        /// The publisher writes this field, and what it writes has changed:
        /// entries from before carry a bare "17 Sep 2026" with no time at all.
        /// Rewriting the feed to match would be rewriting history for the sake
        /// of a format, so the reading end converts instead, exactly as the
        /// site does with the stamp under its download button.
        ///
        /// A date that arrives in none of the shapes below is shown as it came,
        /// because a note with an odd date is still a note worth reading.
        /// </summary>
        public string DateText
        {
            get
            {
                if (string.IsNullOrEmpty(date)) return "";

                string[] withTime = { "M-d-yyyy h:mm tt", "yyyy-MM-dd HH:mm", "d MMM yyyy HH:mm" };
                string[] dateOnly = { "d MMM yyyy", "M-d-yyyy", "yyyy-MM-dd" };
                DateTime t;

                if (DateTime.TryParseExact(date, withTime, CultureInfo.InvariantCulture,
                                           DateTimeStyles.None, out t))
                    return t.ToString("M-d-yyyy h:mm tt", CultureInfo.InvariantCulture);

                if (DateTime.TryParseExact(date, dateOnly, CultureInfo.InvariantCulture,
                                           DateTimeStyles.None, out t))
                    return t.ToString("M-d-yyyy", CultureInfo.InvariantCulture);

                return date;
            }
        }
    }

    /// <summary>
    /// Where to get the SkyMP client runtime, as one download.
    ///
    /// The six files in client-build.json are the only ones a person cannot
    /// get from anywhere else: they are built from the fork, and the folder
    /// build refuses to take them from the Steam copy. A pack carries only
    /// what CHANGED and they change a few times a month, so before this
    /// existed the launcher had to walk back through the update feed hoping to
    /// find a release where they had moved. Published by Publish-Update when
    /// the recorded build is not already on the feed, and named by fork
    /// commit so an unchanged build is never uploaded twice.
    /// </summary>
    [DataContract]
    public class ClientRuntimeRef
    {
        [DataMember] public string url = "";
        [DataMember] public string sha256 = "";
        [DataMember] public long bytes;
        [DataMember] public string forkCommit = "";
    }

    [DataContract]
    public class VersionDoc
    {
        [DataMember] public string launcherVersion = "";
        [DataMember] public string launcherUrl = "";
        [DataMember] public string launcherSha256 = "";
        [DataMember] public string serverAddress = "";
        [DataMember] public string collectionUrl = "";

        /// <summary>The client runtime download. Null on a feed written before
        /// this existed, which is why every use of it is guarded.</summary>
        [DataMember] public ClientRuntimeRef clientRuntime = null;

        /// <summary>
        /// Which revision of the collection the SERVER was built against.
        ///
        /// Written by Publish-Update from the shipping machine's own Vortex
        /// install, because that is the deployment the server's load order and
        /// the reference plugin list were both derived from. So this is not an
        /// opinion about which revision is newest on Nexus; it is a statement
        /// of which one this release agrees with.
        ///
        /// The launcher compares it with its own installed revision and says
        /// behind or ahead. Before 22 September there was no number at all: it
        /// guessed from whether one named file existed, and that file was not
        /// even in the collection, so Patrick sat two revisions behind his own
        /// collection with nothing on screen saying so.
        ///
        /// 0 from an older feed, which means say nothing rather than guess.
        /// </summary>
        [DataMember] public int collectionRevision;

        [DataMember] public string serverPort = "";
        [DataMember] public int maxOnline;
        [DataMember] public string serverPassword = "";

        // Where updates come from, and where voice lives. These used to be
        // boxes on the Settings page, which was wrong twice over: they are not
        // choices anybody makes, and a launcher old enough to have the wrong
        // one is exactly the launcher that cannot be told. Shipping them in the
        // update means a rename or a moved port reaches every copy by itself.
        //
        // updateRepo is the interesting one: publish it under the OLD name
        // pointing at the new, then rename. Every stale copy reads it once and
        // finds its way home.
        [DataMember] public string updateRepo = "";
        [DataMember] public string voicePort = "";

        /// <summary>
        /// Where voice lives, when that is not the server address and a port.
        /// </summary>
        /// <remarks>
        /// NULL BY DEFAULT, and that is the whole point of it. Every other
        /// field here is picked up only when it arrives non-empty, which can
        /// set a value and can never clear one. That is fine for an address
        /// that only ever changes to another address.
        ///
        /// This one has to be clearable. Pointing everybody at Caddy and then
        /// finding a fault in it has to be undoable in one release, and the way
        /// back is an empty value reaching every machine. Null means the feed
        /// did not mention it; empty means the feed said to clear it. Those are
        /// different answers and the reader below tells them apart.
        /// </remarks>
        [DataMember] public string voiceUrl = null;
        [DataMember] public string discordAppId = "";
        [DataMember] public string siteUrl = "";
        [DataMember] public string presenceImage = "";

        [DataMember] public string message = "";

        // Entry 262: hold Play for maintenance, or below a launcher version.
        // Set by hand in the releases repo and read by FeedNotice, which says
        // what each one does.
        //
        // maintenance is a string although it means yes or no. Measured on 24
        // September with this serializer on the .NET Framework: a bool field
        // given "yes" or null throws, and a throw here is not one field lost,
        // it is the whole document unread. Every launcher then says there was
        // no answer from the update source and shuts Play, which would turn a
        // typo in a switch meant for one afternoon into a lockout for
        // everybody. As a string, true, "true", 1, null and "yes" all read
        // without a word, and FeedNotice.On decides what counts as on.
        //
        // Both are null on a feed written before this existed: the serializer
        // does not run field initialisers, which the same measurement showed
        // for message too.
        [DataMember] public string maintenance;
        [DataMember] public string minLauncher;

        [DataMember] public Pack[] packs = new Pack[0];

        // Packs nobody has to have. These are never applied on their own: they
        // sit on the Mods page with an Install button, and they are safe only
        // because the publisher refuses to build one that contains a plugin.
        // The server compares plugin lists and nothing else, so a pack of
        // textures and meshes cannot put anybody out of step with it.
        [DataMember] public Pack[] optional = new Pack[0];
        // What the main build was on when this feed was written. Only a dev
        // feed carries it, and it is the other half of the answer to the
        // question the News tab could not answer before: this build is on
        // one number, main is on another, and these notes in between are the
        // difference. Which is also the list of what wants testing before a
        // dev release becomes a main one.
        [DataMember] public string mainVersion = "";
        [DataMember] public NewsItem[] news = new NewsItem[0];

        public static VersionDoc Parse(byte[] raw)
        {
            // A UTF-8 byte order mark is not JSON. The serializer stops on it and
            // reports an unexpected character, which would break the update
            // check for everyone at once, and with it their route to a fix.
            int at = 0;
            if (raw.Length >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) at = 3;
            using (var ms = new MemoryStream(raw, at, raw.Length - at))
                return (VersionDoc)new DataContractJsonSerializer(typeof(VersionDoc)).ReadObject(ms);
        }
    }
}
