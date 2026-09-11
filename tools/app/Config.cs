using System;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Text;

namespace SkyrimTogether
{
    [DataContract]
    public class Config
    {
        [DataMember] public string ServerAddress = "192.135.119.166";
        [DataMember] public string ServerPort = "25565";
        [DataMember] public long ExpectedExeBytes = 37157144;

        // Set these to turn on updates. Leave blank and the launcher never
        // talks to the network beyond a ping.
        [DataMember] public string UpdateRepo = "";    // "owner/name"
        [DataMember] public string UpdateToken = "";   // read-only fine-grained PAT
        [DataMember] public string UpdateBranch = "main";

        [DataMember] public string Theme = "Nightfall";
        [DataMember] public bool AutoUpdate = true;

        // DataContractSerializer builds the object without running field
        // initialisers, so anything absent from the file comes back null or 0.
        [OnDeserialized]
        void AfterLoad(StreamingContext ctx)
        {
            if (string.IsNullOrEmpty(ServerAddress)) ServerAddress = "192.135.119.166";
            if (string.IsNullOrEmpty(ServerPort)) ServerPort = "25565";
            if (ExpectedExeBytes <= 0) ExpectedExeBytes = 37157144;
            if (UpdateRepo == null) UpdateRepo = "";
            if (UpdateToken == null) UpdateToken = "";
            if (string.IsNullOrEmpty(UpdateBranch)) UpdateBranch = "main";
            if (string.IsNullOrEmpty(Theme)) Theme = "Nightfall";
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
    public class VersionDoc
    {
        [DataMember] public string launcherVersion = "";
        [DataMember] public string launcherUrl = "";
        [DataMember] public string launcherSha256 = "";
        [DataMember] public string serverAddress = "";
        [DataMember] public string serverPort = "";
        [DataMember] public string message = "";
        [DataMember] public Pack[] packs = new Pack[0];

        public static VersionDoc Parse(byte[] raw)
        {
            using (var ms = new MemoryStream(raw))
                return (VersionDoc)new DataContractJsonSerializer(typeof(VersionDoc)).ReadObject(ms);
        }
    }
}
