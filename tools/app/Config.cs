using System;
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

        // Where a server on this machine lives, when the address above is this
        // machine. Blank means look in the usual two places.
        [DataMember] public string ServerFolder = "";

        // Proximity voice runs beside the game server on its own port. The
        // audio goes straight between people; this is only where the browser
        // window connects for positions and signalling.
        [DataMember] public string VoicePort = "7778";

        [DataMember(Name = "VoiceAuto")] public bool? VoiceAutoSetting = true;

        public bool VoiceAuto
        {
            get { return VoiceAutoSetting != false; }
            set { VoiceAutoSetting = value; }
        }
        // How many the server seats. Shipped with the build so the Play page
        // can say something useful even when the server does not announce itself.
        [DataMember] public int MaxOnline = 5;

        // Skyrim Together took a password on its join screen and the launcher
        // typed it in for people. SkyMP has no such screen: the client reads an
        // address and a port and connects. Kept so an older config.json still
        // loads, and as somewhere to put one if a gate is added later.
        [DataMember] public string ServerPassword = "";
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

        // Set the first time the launcher matches the game to this screen, so
        // it never does it again and never argues with a choice made since.
        // A plain bool is right here: absent means it has not happened, which
        // is exactly what false means.
        [DataMember] public bool DisplaySet = false;

        // Where the minimap goes. Written into the mod's ini every launch,
        // because the mod overwrites its own ini when Skyrim exits.
        [DataMember] public string MiniMapSpot = "Top right";

        // The minimap used to default to the bottom left corner, where it sat
        // under the compass mods and the needs widget. Moved once, for
        // everybody, rather than only for people installing fresh. Anyone who
        // liked it where it was only has to put it back.
        [DataMember] public bool MiniMapMoved = false;
        [DataMember] public bool KeepLauncherOpen = false;

        // Ticked, the launcher stops matching the game's resolution to the
        // screen when you press Play. For anyone deliberately running the game
        // at something other than what the monitor is set to.
        [DataMember] public bool LockResolution = false;

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
            if (string.IsNullOrEmpty(VoicePort)) VoicePort = "7778";

            // The old build ran Skyrim Together Reborn on 25565, on a different
            // box. SkyMP does not listen there and that machine is not running
            // anything, so a config carried over from then points everyone at
            // nothing and the launcher would report "not answering" forever
            // without ever saying why. Only these two exact values are moved:
            // anything else is a choice somebody made.
            if (ServerPort == "25565") ServerPort = "7777";
            if (ServerAddress == "192.135.119.166") ServerAddress = "192.135.112.23";
            if (ServerPassword == null) ServerPassword = "";
            if (ExpectedExeBytes <= 0) ExpectedExeBytes = 37157144;
            if (UpdateRepo == null) UpdateRepo = "";
            if (UpdateToken == null) UpdateToken = "";
            if (string.IsNullOrEmpty(UpdateBranch)) UpdateBranch = "main";
            if (string.IsNullOrEmpty(Theme)) Theme = "Forge";
            if (string.IsNullOrEmpty(MiniMapSpot)) MiniMapSpot = "Bottom left";
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
                        if (c != null) return c;
                    }
                }
            }
            catch { }
            return new Config();
        }

        public void Save(string path)
        {
            try
            {
                using (var ms = new MemoryStream())
                {
                    new DataContractJsonSerializer(typeof(Config)).WriteObject(ms, this);
                    File.WriteAllBytes(path, ms.ToArray());
                }
            }
            catch { }
        }
    }

    [DataContract]
    public class Pack
    {
        [DataMember] public string id = "";
        [DataMember] public string url = "";
        [DataMember] public string sha256 = "";
        [DataMember] public string notes = "";
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
    }

    [DataContract]
    public class VersionDoc
    {
        [DataMember] public string launcherVersion = "";
        [DataMember] public string launcherUrl = "";
        [DataMember] public string launcherSha256 = "";
        [DataMember] public string serverAddress = "";
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

        [DataMember] public string message = "";
        [DataMember] public Pack[] packs = new Pack[0];
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
