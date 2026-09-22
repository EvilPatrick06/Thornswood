// Discord.cs
//
// Linking a copy of Thornswood to a Discord account, and asking the site
// whether that account is still allowed in.
//
// Why it exists: the server password used to live in version.json, which meant
// everybody who had ever installed the game kept a copy of it forever and
// there was no way to take it back off one person. Now the launcher holds a
// signed ticket instead, the site holds the password, and every launch asks
// whether this ticket is still somebody who is allowed in. Leaving the Discord
// or being given the Banned role stops the next launch, with nothing to
// remember to change anywhere else.
//
// Only the base class library, so it compiles against the same reference set
// the rest of the launcher already uses.
//
//   Discord.Folder  = profile folder, set once at startup
//   Discord.Ticket  != null  -> this copy is linked
//   Discord.Connect(...)     -> opens the browser, waits, saves the ticket
//   Discord.Join()           -> ask the site: allowed in, and the password
//   Discord.Forget()         -> unlink
//   Discord.NewSession()     -> one id for this Play
//   Discord.SessionStart/End -> both ends of a session, for the site's log

using System;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace Thornswood
{
    public class Standing
    {
        public bool Ok;
        public string Name = "";
        public string Password = "";
        public string Why = "";        // link, guild, banned, role, offline
        public string Message = "";
        public string Invite = "";
        public bool Admin;
        // Allowed on the dev build. The site decides: the Owner and Dev
        // roles unless its config widens it.
        public bool Dev;
        // Character slots at the game's main menu. Two, or three for a
        // Patreon tier or a Gamemaster; the site decides from the roles.
        public int Slots = 2;
    }

    public static class Discord
    {
        public const string Site = "https://thornswood.net";

        public static string Folder = @"C:\Thornswood\Profile";
        static string TicketFile { get { return Path.Combine(Folder, "discord.txt"); } }
        static string NameFile   { get { return Path.Combine(Folder, "discord-name.txt"); } }
        static string DevFile    { get { return Path.Combine(Folder, "dev-allowed.txt"); } }

        /// <summary>Which build is asking: "" for the main build, "dev" for the dev build. Set by the shell.</summary>
        public static string Channel = "";

        /// <summary>
        /// Whether the site last said this person may use the dev build. Kept
        /// on disk so the Settings card can show before the first check in of
        /// a session. False until the site has said yes once.
        /// </summary>
        public static bool DevAllowed
        {
            get { try { return File.Exists(DevFile); } catch { return false; } }
        }

        static void NoteDev(bool allowed)
        {
            try
            {
                if (allowed) { Directory.CreateDirectory(Folder); File.WriteAllText(DevFile, "yes"); }
                else if (File.Exists(DevFile)) File.Delete(DevFile);
            }
            catch { }
        }

        static string ticket;
        static string name;

        public static string Ticket
        {
            get
            {
                if (ticket == null)
                {
                    // Encrypted on the disk since 1.0.197. Unprotect hands an
                    // older plain one straight back, and the next Save writes
                    // it down encrypted.
                    try { ticket = File.Exists(TicketFile) ? Secrets.Unprotect(File.ReadAllText(TicketFile).Trim()) : ""; }
                    catch { ticket = ""; }
                }
                return ticket.Length == 0 ? null : ticket;
            }
        }

        public static string Name
        {
            get
            {
                if (name == null)
                {
                    try { name = File.Exists(NameFile) ? File.ReadAllText(NameFile).Trim() : ""; }
                    catch { name = ""; }
                }
                return name;
            }
        }

        public static bool Linked { get { return Ticket != null; } }

        public static void Forget()
        {
            try { if (File.Exists(TicketFile)) File.Delete(TicketFile); } catch { }
            try { if (File.Exists(NameFile)) File.Delete(NameFile); } catch { }
            ticket = ""; name = "";
        }

        static void Save(string t, string who)
        {
            try
            {
                Directory.CreateDirectory(Folder);
                File.WriteAllText(TicketFile, Secrets.Protect(t ?? ""));
                File.WriteAllText(NameFile, who ?? "");
                // The ticket is as good as the password: anything holding it
                // can ask the site for the real one. Nobody else on this PC
                // gets to read the file.
                Secrets.LockDown(TicketFile);
            }
            catch { }
            ticket = t ?? ""; name = who ?? "";
        }

        // ------------------------------------------------------------ link --
        //
        // The standard way a desktop program does this: listen on a spare port
        // on this machine only, send the browser out to the site, and let the
        // site send the answer back to that port. Nothing is typed, nothing is
        // pasted, and the ticket never goes through the clipboard.
        //
        // onDone is called on a thread pool thread. Marshal it yourself.
        public static void Connect(Action<bool, string> onDone)
        {
            HttpListener listener = null;
            int port = 0;

            // The loopback listener below is reachable from any browser tab and
            // from anything else running on this machine, and the port range is
            // twenty numbers wide, so it is guessable by definition. Without
            // this, a web page open at the wrong moment could fire a request at
            // all twenty ports carrying its own ticket, win the race against a
            // human finishing a Discord login, and quietly link this launcher to
            // somebody else's account. The nonce rides out with the request and
            // has to come back on the answer, so a request that did not start
            // here is dropped and the listener keeps waiting.
            string nonce;
            using (var rng = new RNGCryptoServiceProvider())
            {
                var nb = new byte[24];
                rng.GetBytes(nb);
                var sb = new StringBuilder();
                foreach (byte b in nb) sb.Append(b.ToString("x2"));
                nonce = sb.ToString();
            }

            for (int tryPort = 53120; tryPort < 53140 && listener == null; tryPort++)
            {
                try
                {
                    var l = new HttpListener();
                    l.Prefixes.Add("http://127.0.0.1:" + tryPort + "/");
                    l.Start();
                    listener = l;
                    port = tryPort;
                }
                catch { }
            }
            if (listener == null)
            {
                if (onDone != null) onDone(false, "Could not open a port to listen on.");
                return;
            }

            try
            {
                Process_Start(Site + "/auth/discord?back=%2Flink&port=" + port + "&nonce=" + nonce);
            }
            catch
            {
                try { listener.Stop(); } catch { }
                if (onDone != null) onDone(false, "Could not open your browser.");
                return;
            }

            var done = new ManualResetEvent(false);
            string gotTicket = null, gotName = null, error = null;

            // A loop rather than one shot, so a stray or hostile request is
            // answered and ignored instead of ending the attempt. The listener
            // being stopped below is what breaks it out.
            var worker = new Thread(delegate ()
            {
                while (true)
                {
                    HttpListenerContext ctx;
                    try { ctx = listener.GetContext(); }
                    catch { return; }

                    bool good = false;
                    try
                    {
                        var q = ctx.Request.QueryString;
                        var ep = ctx.Request.RemoteEndPoint;

                        bool local = ep != null && IPAddress.IsLoopback(ep.Address);
                        string sawNonce = q["nonce"] ?? "";
                        bool mine = string.Equals(sawNonce, nonce, StringComparison.Ordinal);
                        string t = q["ticket"];

                        good = local && mine && !string.IsNullOrEmpty(t);
                        if (good)
                        {
                            gotTicket = t;
                            gotName = q["name"];
                        }

                        string page = good
                            ? Page("Linked", "You can close this and go back to the launcher.")
                            : Page("Not this one", "That did not come from the Connect Discord button, so it was ignored. Close this and press it again.");
                        var bytes = Encoding.UTF8.GetBytes(page);
                        ctx.Response.StatusCode = good ? 200 : 400;
                        ctx.Response.ContentType = "text/html; charset=utf-8";
                        ctx.Response.ContentLength64 = bytes.Length;
                        ctx.Response.OutputStream.Write(bytes, 0, bytes.Length);
                        ctx.Response.Close();
                    }
                    catch (Exception e) { if (!good) error = e.Message; }

                    if (good) { done.Set(); return; }
                }
            });
            worker.IsBackground = true;
            worker.Start();

            // Two minutes is long enough to sign in to Discord and short enough
            // that a forgotten browser tab does not leave a port open all night.
            bool answered = done.WaitOne(TimeSpan.FromMinutes(2));
            try { listener.Stop(); } catch { }

            if (!answered)
            {
                if (onDone != null) onDone(false, "Timed out waiting for the browser.");
                return;
            }
            if (string.IsNullOrEmpty(gotTicket))
            {
                if (onDone != null) onDone(false, error ?? "No ticket came back.");
                return;
            }

            Save(gotTicket, gotName);
            if (onDone != null) onDone(true, gotName ?? "");
        }

        static void Process_Start(string url)
        {
            var psi = new System.Diagnostics.ProcessStartInfo(url);
            psi.UseShellExecute = true;
            System.Diagnostics.Process.Start(psi);
        }

        static string Page(string title, string line)
        {
            return "<!doctype html><meta charset=utf-8><title>Thornswood</title>" +
                   "<body style=\"background:#12150F;color:#DDE3D5;font:15px/1.6 " +
                   "system-ui;display:grid;place-items:center;height:100vh;margin:0;" +
                   "text-align:center\"><div><h1 style=\"color:#C9A24B;font-weight:600\">" +
                   title + "</h1><p>" + line + "</p></div></body>";
        }

        // ------------------------------------------------------------ join --
        //
        // Called before connecting. Returns whether this person is still
        // allowed in, and the password to connect with if they are.
        public static Standing Join()
        {
            // The profile id goes with the check in. The site keeps it against
            // the Discord account, and the game server's door reads that list
            // to decide who it lets connect. Without it the server has no way
            // to tell one person from another: it never sees a Discord account,
            // only a profile number.
            int pid = 0;
            try { pid = AutoJoin.GetProfileId(); } catch { pid = 0; }
            return Join(pid);
        }

        /// <summary>
        /// The same check in, for one particular id.
        ///
        /// Since 20 September the person picks their character at the game's
        /// menu, so before the game starts Shell checks in once for every id
        /// this install could pick, characters and the spare alike, and once
        /// more with the one that was picked. The version above sends whatever
        /// the settings file says, which is the id played last and no longer
        /// the whole story.
        /// </summary>
        public static Standing Join(int profileId)
        {
            var st = new Standing();
            if (!Linked)
            {
                st.Why = "link";
                st.Message = "This copy is not linked to a Discord account yet.";
                return st;
            }
            int pid = profileId;
            string body = "{\"ticket\":\"" + Escape(Ticket) + "\"" +
                          (pid > 0 ? ",\"profileId\":" + pid : "") +
                          (string.IsNullOrEmpty(Channel) ? "" : ",\"channel\":\"" + Escape(Channel) + "\"") + "}";
            string reply;
            int code = PostJson(Site + "/api/play/join", body, out reply);

            if (code == 0)
            {
                // The site could not be reached. Say so honestly rather than
                // implying the person is banned.
                st.Why = "offline";
                st.Message = "Could not reach thornswood.net to check you in.";
                return st;
            }

            st.Ok       = Field(reply, "ok") == "true";
            st.Name     = Field(reply, "name");
            st.Password = Field(reply, "password");
            st.Why      = Field(reply, "why");
            st.Message  = Field(reply, "message");
            st.Invite   = Field(reply, "invite");
            st.Admin    = Field(reply, "admin") == "true";
            st.Dev      = Field(reply, "dev") == "true";
            int slots;
            if (int.TryParse(Field(reply, "slots"), out slots) && slots > 0) st.Slots = slots;
            // Only an answer that carried the flag moves it. An older site
            // that says nothing about dev leaves the last answer standing.
            if (reply.Contains("\"dev\"")) NoteDev(st.Dev);

            if (st.Ok && st.Name.Length > 0 && st.Name != Name) Save(Ticket, st.Name);
            if (!st.Ok && st.Message.Length == 0) st.Message = "Not allowed in.";
            return st;
        }

        // -------------------------------------------------------- sessions --
        //
        // Both ends of a play session, so there is a record of who tested what
        // and for how long. /api/play/join is a last played stamp: it says
        // somebody pressed Play and nothing about when they stopped. Djinn
        // asked for a checking sheet on 20 September, and this is the half of
        // it the launcher can see.
        //
        // One id per Play, made here, sent with the start and again with the
        // end. The site matches the two up and the staff console reads them.
        //
        // Nothing in here is allowed to matter. A site that is down, a ticket
        // that has run out, an answer that never comes: each is a line in the
        // log and the game plays exactly the same.

        static string session = "";

        /// <summary>The id this session is logged under. "" before the first Play.</summary>
        public static string SessionId { get { return session; } }

        /// <summary>A fresh id for one session. Made once, as the game starts.</summary>
        public static string NewSession()
        {
            session = Guid.NewGuid().ToString("N");
            return session;
        }

        /// <summary>The game has just been started. Call it from a pool thread.</summary>
        public static void SessionStart(int profileId)
        {
            if (session.Length == 0) NewSession();
            MarkPending(session);
            Send("start", Site + "/api/play/start", Head(profileId) + "}");
        }

        /// <summary>
        /// The session whose logs have not been sent yet, or "".
        ///
        /// Written when a session starts and cleared when its logs are safely
        /// up. If the launcher is killed, or the machine goes down, or the
        /// game takes the launcher with it, SessionEnd never runs and the logs
        /// are still sitting on disk. This is what remembers them, so the next
        /// start can send them before anything wipes them.
        /// </summary>
        static string PendingFile { get { return Path.Combine(Folder, "logs-pending.txt"); } }

        static void MarkPending(string id)
        {
            try
            {
                Directory.CreateDirectory(Folder);
                File.WriteAllText(PendingFile, id);
            }
            catch { }
        }

        static void ClearPending()
        {
            try { if (File.Exists(PendingFile)) File.Delete(PendingFile); }
            catch { }
        }

        /// <summary>
        /// Logs from a session that ended without sending them, sent now.
        ///
        /// Called once as the launcher starts, BEFORE Play can run, because
        /// the game truncates its own logs at every game start and after that
        /// there is nothing left to send. The crash that took the launcher
        /// down is exactly the session somebody wants to read afterwards, and
        /// until now it was the one that was always lost.
        ///
        /// Call it from a pool thread.
        /// </summary>
        public static void SendPendingLogs()
        {
            try
            {
                if (!Linked) return;
                string id = "";
                try { if (File.Exists(PendingFile)) id = (File.ReadAllText(PendingFile) ?? "").Trim(); }
                catch { return; }
                if (id.Length < 8) { ClearPending(); return; }

                string was = session;
                session = id;
                try
                {
                    Note("The last session ended without sending its logs. Sending them now.");
                    SessionLogs();
                }
                finally { session = was; }
            }
            catch { }
        }

        /// <summary>
        /// The game has closed. minutes is how long it ran; why is "quit" when
        /// the person closed it and "update" when the launcher closed it for a
        /// release. Call it from a pool thread.
        /// </summary>
        public static void SessionEnd(int profileId, double minutes, string why)
        {
            // A launcher that took a running session over, or one that was
            // itself replaced mid session, has no id of its own. It makes one
            // and sends the end alone; the site records that as a session whose
            // start was never seen, which is the truth of it.
            if (session.Length == 0) NewSession();
            double m = minutes;
            if (m < 0 || m > 60 * 24 * 7 || double.IsNaN(m)) m = 0;
            string reason = why == "update" ? "update" : "quit";
            Send("end", Site + "/api/play/end",
                 Head(profileId) +
                 ",\"minutes\":" + m.ToString("F1", CultureInfo.InvariantCulture) +
                 ",\"why\":\"" + reason + "\"}");
        }

        /// <summary>
        /// The session's logs, up to the site, as the game closes.
        ///
        /// THIS MOMENT AND NO OTHER. The game truncates its own logs under
        /// Data\Platform every time it starts, so a log nobody collected here
        /// is gone for good. That is why every report so far has begun by
        /// asking the person to go and find four files and paste them, which
        /// they mostly cannot and reasonably do not want to.
        ///
        /// Sent once per session. The site writes a set once and refuses a
        /// second for the same id, because these are meant to stand up when
        /// somebody is suspended, and evidence the accused can overwrite is
        /// not evidence.
        ///
        /// Nothing here is read from the person: these are the launcher's own
        /// log and the game's own logs. Called from a pool thread, after
        /// SessionEnd so the row it attaches to exists.
        /// </summary>
        public static void SessionLogs()
        {
            try
            {
                if (!Linked || session.Length == 0) return;

                // Name, then where it is. The names are the ones the site
                // accepts; anything else it drops on the floor.
                string plat = Path.Combine(Paths.Game, "Data\\Platform");
                string[][] want = new string[][] {
                    new string[] { "launcher.log",               Path.Combine(Folder, "launcher.log") },
                    new string[] { "thornswood-front.log",       Path.Combine(plat, "thornswood-front.log") },
                    new string[] { "thornswood-voice.log",       Path.Combine(plat, "thornswood-voice.log") },
                    new string[] { "thornswood-emotes.log",      Path.Combine(plat, "thornswood-emotes.log") },
                    new string[] { "thornswood-input.log",       Path.Combine(plat, "thornswood-input.log") },
                    new string[] { "thornswood-dress.log",       Path.Combine(plat, "thornswood-dress.log") },
                    new string[] { "thornswood-loadorder.txt",   Path.Combine(plat, "thornswood-loadorder.txt") },
                    new string[] { "thornswood-plugins-light.txt", Path.Combine(plat, "thornswood-plugins-light.txt") }
                };

                var sb = new StringBuilder();
                sb.Append("{\"ticket\":\"").Append(Escape(Ticket)).Append("\"");
                sb.Append(",\"session\":\"").Append(Escape(session)).Append("\"");
                sb.Append(",\"logs\":{");
                int n = 0;
                for (int i = 0; i < want.Length; i++)
                {
                    string text = ReadLogTail(want[i][1]);
                    if (text.Length == 0) continue;
                    if (n > 0) sb.Append(",");
                    sb.Append("\"").Append(Escape(want[i][0])).Append("\":\"").Append(Escape(text)).Append("\"");
                    n++;
                }
                sb.Append("}}");
                if (n == 0) return;

                string reply;
                int code = PostJson(Site + "/api/play/logs", sb.ToString(), out reply);

                // 200 is stored, 409 is a set already there. Both mean there
                // is nothing still owed for this session, so the marker goes.
                // 404 means the site has no row for it and never will, so the
                // marker goes too rather than being retried at every start for
                // ever. Anything else is worth trying again next time.
                if (code == 200) { ClearPending(); Note("Sent " + n + " log(s) from this session to thornswood.net."); return; }
                if (code == 409) { ClearPending(); Note("This session's logs were already sent; the site kept the first set."); return; }
                if (code == 404) { ClearPending(); Note("The site has no record of that session, so its logs were not kept."); return; }
                Note("Could not send this session's logs: " +
                     (code == 0 ? "the site could not be reached" : "it answered " + code) +
                     ". They will be sent at the next start.");
            }
            catch (Exception ex)
            {
                Note("Could not send this session's logs: " + ex.Message);
            }
        }

        /// <summary>
        /// The last of a log, or "" when there is nothing worth sending.
        ///
        /// The tail, because a crash is at the end and the front of a long log
        /// is the same twenty lines of start-up every time. FileShare is
        /// everything: the game may still be letting go of these, and a log
        /// that cannot be opened is worth skipping rather than worth throwing.
        /// </summary>
        const int LogTailBytes = 192 * 1024;
        static string ReadLogTail(string path)
        {
            try
            {
                if (!File.Exists(path)) return "";
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read,
                                               FileShare.ReadWrite | FileShare.Delete))
                {
                    long len = fs.Length;
                    if (len == 0) return "";
                    int take = (int)Math.Min(len, LogTailBytes);
                    fs.Seek(len - take, SeekOrigin.Begin);
                    var buf = new byte[take];
                    int got = fs.Read(buf, 0, take);
                    string s = Encoding.UTF8.GetString(buf, 0, got);
                    // A tail almost always starts mid line. Drop the fragment
                    // so the first line in the file is a whole one.
                    if (len > take)
                    {
                        int nl = s.IndexOf('\n');
                        if (nl >= 0 && nl + 1 < s.Length) s = s.Substring(nl + 1);
                    }
                    return s;
                }
            }
            catch { return ""; }
        }

        /// <summary>Everything both ends send, without the closing brace.</summary>
        static string Head(int profileId)
        {
            return "{\"ticket\":\"" + Escape(Ticket) + "\"" +
                   ",\"session\":\"" + Escape(session) + "\"" +
                   (profileId > 0 ? ",\"profileId\":" + profileId : "") +
                   ",\"channel\":\"" + Escape(string.IsNullOrEmpty(Channel) ? "main" : Channel) + "\"" +
                   ",\"version\":\"" + Escape(Updater.Version) + "\"";
        }

        static void Send(string what, string url, string json)
        {
            try
            {
                if (!Linked)
                {
                    Note("Did not tell thornswood.net the session " + what +
                         ": this copy is not linked to a Discord account.");
                    return;
                }
                string reply;
                int code = PostJson(url, json, out reply);
                if (code == 200) return;
                Note("thornswood.net did not record the session " + what + ": " +
                     (code == 0 ? "the site could not be reached" : "it answered " + code) + ".");
            }
            catch (Exception ex)
            {
                Note("Could not tell thornswood.net the session " + what + ": " + ex.Message);
            }
        }

        /// <summary>
        /// Straight into launcher.log. Shell.Log writes the status line as well
        /// and has to be on the window's thread; these run on the pool.
        /// </summary>
        static void Note(string line)
        {
            try
            {
                Directory.CreateDirectory(Folder);
                File.AppendAllText(Path.Combine(Folder, "launcher.log"),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + line + Environment.NewLine);
            }
            catch { }
        }

        public static int PostJson(string url, string json, out string reply)
        {
            reply = "";
            try
            {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Method = "POST";
                req.ContentType = "application/json";
                req.Timeout = 15000;
                req.UserAgent = "Thornswood";
                var bytes = Encoding.UTF8.GetBytes(json);
                req.ContentLength = bytes.Length;
                using (var s = req.GetRequestStream()) s.Write(bytes, 0, bytes.Length);
                using (var res = (HttpWebResponse)req.GetResponse())
                using (var r = new StreamReader(res.GetResponseStream()))
                {
                    reply = r.ReadToEnd();
                    return (int)res.StatusCode;
                }
            }
            catch (WebException we)
            {
                // A refusal is an answer, not a failure. 403 with a reason in it
                // is exactly what this wants to read.
                var res = we.Response as HttpWebResponse;
                if (res != null)
                {
                    try
                    {
                        using (var r = new StreamReader(res.GetResponseStream())) reply = r.ReadToEnd();
                    }
                    catch { }
                    return (int)res.StatusCode;
                }
                return 0;
            }
            catch { return 0; }
        }

        // Small enough to not want a JSON library for. Flat objects only, which
        // is all either endpoint returns.
        static string Field(string json, string key)
        {
            if (string.IsNullOrEmpty(json)) return "";
            string needle = "\"" + key + "\"";
            int i = json.IndexOf(needle, StringComparison.Ordinal);
            if (i < 0) return "";
            i = json.IndexOf(':', i + needle.Length);
            if (i < 0) return "";
            i++;
            while (i < json.Length && (json[i] == ' ' || json[i] == '\t')) i++;
            if (i >= json.Length) return "";
            if (json[i] == '"')
            {
                var sb = new StringBuilder();
                for (i++; i < json.Length; i++)
                {
                    if (json[i] == '\\' && i + 1 < json.Length)
                    {
                        i++;
                        if (json[i] == 'n') sb.Append('\n');
                        else if (json[i] == 't') sb.Append('\t');
                        else if (json[i] == 'u' && i + 4 < json.Length)
                        {
                            sb.Append((char)Convert.ToInt32(json.Substring(i + 1, 4), 16));
                            i += 4;
                        }
                        else sb.Append(json[i]);
                        continue;
                    }
                    if (json[i] == '"') break;
                    sb.Append(json[i]);
                }
                return sb.ToString();
            }
            int end = i;
            while (end < json.Length && json[end] != ',' && json[end] != '}') end++;
            return json.Substring(i, end - i).Trim();
        }

        public static string Escape(string s)
        {
            return (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"");
        }
    }
}
