using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;

namespace Thornswood
{
    /// <summary>
    /// Proximity voice, moved out of the game and into the launcher.
    ///
    /// Everything here exists because of where the audio used to run. The voice
    /// page lived inside SkyrimPlatform's in-game CEF overlay, which is a
    /// browser with no permission UI, an autoplay policy that refuses to start
    /// playback without a click nobody can give it, and a focus flag that takes
    /// the keyboard away from the game. Positions, names and distances all
    /// worked there, because that is signalling. Audio never once did.
    ///
    /// another server does not do it that way. Their in-game voice service only tracks
    /// push to talk, the socket and the HUD, and reports a launcher status of
    /// connected / micOk / talking. The microphone and the audio pipeline live
    /// in their launcher, which is Electron and therefore a real browser.
    ///
    /// This launcher is WPF, so it has no browser at all. WebView2 is the way
    /// in: it is Edge's Chromium, it is already installed on this machine as
    /// part of Windows, and it does getUserMedia and WebRTC the way any browser
    /// does. The window is never shown. It exists to hold an audio pipeline
    /// that outlives the game's own browser and is not subject to any of its
    /// restrictions.
    ///
    /// The three WebView2 files ride inside this exe as embedded resources
    /// rather than sitting beside it. That is not tidiness: the update system
    /// publishes exactly one asset, the exe, and SelfUpdate replaces exactly
    /// that one file. Loose sidecar DLLs would mean changing the publisher, the
    /// version document and the updater together, and would leave everybody's
    /// launcher broken in between.
    /// </summary>
    static class Voice
    {
        const string CoreDll   = "Microsoft.Web.WebView2.Core.dll";
        const string WpfDll    = "Microsoft.Web.WebView2.Wpf.dll";
        const string LoaderDll = "WebView2Loader.dll";
        const string PageFile  = "voice-host.html";

        static Microsoft.Web.WebView2.Wpf.WebView2 view;
        static Window hostWindow;
        static Action<string> logger = delegate { };

        /// <summary>
        /// Every line goes through here, and this is not tidiness.
        ///
        /// The launcher's Log writes to a WPF control, so calling it from any
        /// thread but the UI one throws. Two things here run off the UI thread:
        /// the WebView2 environment callback and the push to talk listener. An
        /// unhandled exception on a threadpool thread does not show a dialog or
        /// write a line, it takes the whole process down without a word, which
        /// is a launcher that opens and vanishes a few seconds later with a log
        /// that simply stops.
        /// </summary>
        /// <summary>
        /// Straight to launcher.log, never to the status line.
        ///
        /// The voice page reports things that matter when voice is broken and
        /// matter to nobody the rest of the time: which stage of the connection
        /// each pair of people is at, several times a minute, named by peer id.
        /// That belongs in the file somebody sends me when it goes wrong, not on
        /// the one line they are actually reading.
        /// </summary>
        static void Quiet(string m)
        {
            try
            {
                File.AppendAllText(Paths.LogFile,
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + m + Environment.NewLine);
            }
            catch (Exception ex) { Swallow.Note("Voice.Quiet, log", ex); }
        }

        static void Say(string m)
        {
            try
            {
                var app = System.Windows.Application.Current;
                var d = app == null ? null : app.Dispatcher;
                if (d != null && !d.CheckAccess())
                {
                    d.BeginInvoke(new Action(delegate
                    {
                        try { logger(m); } catch (Exception ex) { Swallow.Note("Voice.Say, invoke logger", ex); }
                    }));
                    return;
                }
                logger(m);
            }
            catch (Exception ex) { Swallow.Note("Voice.Say", ex); }
        }

        // Held by reference, not copied. The launcher rewrites these in place
        // when version.json says the server moved, and voice should follow.
        static Config conf;
        static string lastPeers = "", lastStatus = "";

        // What the game's indicator asks about. It has no microphone and no
        // peer connections any more, so the only honest answer comes from here.
        static volatile bool micOk;
        static volatile bool talking;
        static volatile int peerCount;
        static volatile string voiceMode = "local";

        static bool hooked;
        static bool started;

        /// <summary>
        /// Shuts the hidden window down on the way out.
        ///
        /// This window is the reason the launcher would not reopen. WPF's
        /// default ShutdownMode is OnLastWindowClose, and this is a real
        /// Window that is deliberately never shown, so closing the launcher
        /// left Application.Run still running with an invisible window and
        /// nothing on screen. The process stayed up, it kept holding the
        /// ThornswoodLauncher mutex, and the next launch saw an instance
        /// already running and exited without a word.
        ///
        /// Shell sets ShutdownMode to OnMainWindowClose now, which is the real
        /// fix. This is the tidy-up that goes with it: WebView2 holds a browser
        /// process of its own, and letting it go quietly beats leaving it to be
        /// torn down with the app.
        /// </summary>
        public static void Stop()
        {
            try
            {
                if (view != null) { view.Dispose(); view = null; }
            }
            catch (Exception ex) { Swallow.Note("Voice.Stop, dispose view", ex); }
            try
            {
                if (hostWindow != null) { hostWindow.Close(); hostWindow = null; }
            }
            catch (Exception ex) { Swallow.Note("Voice.Stop, close host", ex); }
        }

        /// <summary>
        /// Called once, as early as possible, and before anything touches a
        /// WebView2 type. Installing the resolver late is the same as not
        /// installing it: the CLR binds an assembly the first time a method
        /// using it is compiled, not when it is called.
        /// </summary>
        public static void Prepare()
        {
            if (hooked) return;
            hooked = true;

            AppDomain.CurrentDomain.AssemblyResolve += delegate (object s, ResolveEventArgs e)
            {
                string want = new AssemblyName(e.Name).Name;
                string file = null;
                if (want == "Microsoft.Web.WebView2.Core") file = CoreDll;
                else if (want == "Microsoft.Web.WebView2.Wpf") file = WpfDll;
                if (file == null) return null;

                byte[] bytes = Resource(file);
                if (bytes == null) return null;
                return Assembly.Load(bytes);
            };
        }

        static byte[] Resource(string name)
        {
            try
            {
                Assembly me = Assembly.GetExecutingAssembly();
                using (Stream s = me.GetManifestResourceStream(name))
                {
                    if (s == null) return null;
                    byte[] b = new byte[s.Length];
                    int read = 0;
                    while (read < b.Length)
                    {
                        int n = s.Read(b, read, b.Length - read);
                        if (n <= 0) break;
                        read += n;
                    }
                    return b;
                }
            }
            catch { return null; }
        }

        /// <summary>
        /// The native loader cannot be loaded from memory, so it is written
        /// beside the exe. Only when it is missing or a different size, because
        /// this runs on every start and the file may be locked by a previous
        /// run that has not fully exited.
        /// </summary>
        static bool PlaceLoader(out string why)
        {
            why = "";
            try
            {
                byte[] want = Resource(LoaderDll);
                if (want == null) { why = LoaderDll + " is not embedded in this build"; return false; }

                string dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
                string path = Path.Combine(dir, LoaderDll);

                if (File.Exists(path) && new FileInfo(path).Length == want.Length) return true;

                File.WriteAllBytes(path, want);
                return true;
            }
            catch (Exception ex)
            {
                why = ex.Message;
                return false;
            }
        }

        /// <summary>
        /// Bring the audio side up. Safe to call more than once.
        /// Returns quietly on any failure: a launcher that will not open
        /// because voice did not start is a worse outcome than silent voice.
        /// </summary>

        /// <summary>
        /// Places WebView2Loader.dll beside the exe. Menu music needs this
        /// before CreateAsync; Voice.Start already calls it, but music can be
        /// queued first at ApplicationIdle.
        /// </summary>
        public static bool EnsureLoader(Action<string> say)
        {
            Prepare();
            string why;
            if (PlaceLoader(out why)) return true;
            if (say != null) say("Voice: could not place " + LoaderDll + ": " + why);
            return false;
        }
        public static void Start(Action<string> log, Config config)
        {
            if (started) return;
            started = true;
            conf = config;
            logger = log;

            try
            {
                Prepare();

                string why;
                if (!PlaceLoader(out why))
                {
                    Say("Voice: could not place " + LoaderDll + ": " + why);
                    return;
                }

                if (RuntimeVersion() == null)
                {
                    Say("Voice: WebView2 runtime is not installed on this machine. Fetching it.");
                    Bootstrap();
                    return;
                }

                Begin(log);
            }
            catch (Exception ex)
            {
                Say("Voice: did not start: " + ex.Message);
            }
        }

        /// <summary>
        /// Split out so that the WebView2 types are only touched from a method
        /// the CLR compiles after Prepare has run.
        /// </summary>
        static void Begin(Action<string> log)
        {
            var host = new Window
            {
                Width = 320,
                Height = 200,
                ShowInTaskbar = false,
                WindowStyle = WindowStyle.None,
                ShowActivated = false,
                Visibility = Visibility.Hidden,
                Title = "ThornsWood voice"
            };

            view = new Microsoft.Web.WebView2.Wpf.WebView2();
            logger = log;
            host.Content = view;

            // A window with no content never creates its browser, and a window
            // that is never shown has no content. So it is shown offscreen and
            // hidden, which costs one frame and nothing else.
            host.Left = -10000;
            host.Top = -10000;
            host.Show();
            host.Hide();
            hostWindow = host;

            view.CoreWebView2InitializationCompleted += delegate (
                object s,
                Microsoft.Web.WebView2.Core.CoreWebView2InitializationCompletedEventArgs e)
            {
                try
                {
                    if (!e.IsSuccess)
                    {
                        string detail = e.InitializationException == null
                            ? "no reason given"
                            : e.InitializationException.Message;
                        Say("Voice: WebView2 failed to initialise: " + detail);
                        return;
                    }

                    var core = view.CoreWebView2;
                    if (core == null) { Say("Voice: WebView2 came up with no core"); return; }

                    // Grant the microphone without asking. There is nobody to
                    // ask: this window is never on screen. This is the thing
                    // the game's own browser could not do, and half of why
                    // voice never carried audio from in there.
                    core.PermissionRequested += delegate (
                        object s2,
                        Microsoft.Web.WebView2.Core.CoreWebView2PermissionRequestedEventArgs args)
                    {
                        try
                        {
                            args.State = Microsoft.Web.WebView2.Core.CoreWebView2PermissionState.Allow;
                            args.Handled = true;
                        }
                        catch (Exception ex) { Swallow.Note("Voice.Begin, new window", ex); }
                    };

                    // The page reports back: status, peer count, talking,
                    // and its own log lines. Everything voice knows about
                    // itself now lands in launcher.log rather than in a log
                    // file inside the game that nobody reads until it breaks.
                    core.WebMessageReceived += delegate (
                        object s3,
                        Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs a)
                    {
                        try { OnPageMessage(a.TryGetWebMessageAsString(), log); }
                        catch (Exception ex) { Swallow.Note("Voice.Begin, page message", ex); }
                    };

                    core.NavigationCompleted += delegate { Configure(log); };

                    string page = PlacePage(log);
                    if (page == null) return;
                    core.Navigate(new Uri(page).AbsoluteUri);

                    Say("Voice: WebView2 is up, runtime " + core.Environment.BrowserVersionString);
                    StartPttListener(log);
                    StartFileChannel(log);
                }
                catch (Exception ex)
                {
                    Say("Voice: WebView2 came up but could not be configured: " + ex.Message);
                }
            };

            string profile = Path.Combine(Paths.ProfileDir, "VoiceBrowser");
            try { Directory.CreateDirectory(profile); } catch (Exception ex) { Swallow.Note("Voice.Begin, create profile", ex); }

            // No mDNS responder in the voice browser, so nothing in it listens
            // on the network and Windows Firewall has nothing to ask about,
            // even on a WebView2 installed for one account, which comes with
            // no rule (#911). The environment variable, not
            // CoreWebView2EnvironmentOptions: see MenuMusic for why options
            // made CreateAsync fault on the shipping machine. It is read when
            // the environment is created, which is the next line.
            try
            {
                string key = "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS";
                Environment.SetEnvironmentVariable(key,
                    BrowserArgs.DisableFeature(Environment.GetEnvironmentVariable(key), BrowserArgs.NoMdns));
            }
            catch (Exception ex) { Swallow.Note("Voice.Begin, browser arguments", ex); }

            var envTask = Microsoft.Web.WebView2.Core.CoreWebView2Environment.CreateAsync(
                null, profile, null);

            envTask.ContinueWith(delegate (System.Threading.Tasks.Task<Microsoft.Web.WebView2.Core.CoreWebView2Environment> t)
            {
                if (t.IsFaulted || t.Result == null)
                {
                    Say("Voice: no WebView2 runtime on this machine, voice is off");
                    return;
                }
                host.Dispatcher.BeginInvoke(new Action(delegate
                {
                    try { view.EnsureCoreWebView2Async(t.Result); }
                    catch (Exception ex) { Say("Voice: could not start WebView2: " + ex.Message); }
                }));
            });
        }

        /// <summary>
        /// The installed runtime, or null when there isn't one.
        /// Asked through the SDK rather than by poking at Program Files,
        /// because the evergreen runtime moves and the per-user copy lives
        /// somewhere else entirely.
        /// </summary>
        static string RuntimeVersion()
        {
            try
            {
                string v = Microsoft.Web.WebView2.Core.CoreWebView2Environment
                                    .GetAvailableBrowserVersionString(null);
                return string.IsNullOrEmpty(v) ? null : v;
            }
            catch { return null; }
        }

        /// <summary>
        /// Install the WebView2 runtime, once, in the background.
        ///
        /// This ships with Windows 11 and most of Windows 10, so for nearly
        /// everybody RuntimeVersion already answered and none of this runs. For
        /// the one person it doesn't, the alternative is telling them to go and
        /// find an installer themselves, which is how a feature quietly never
        /// reaches half the people it was built for.
        ///
        /// Microsoft's evergreen bootstrapper is a permanent link and a tiny
        /// download that fetches the real thing itself. Its manifest asks for
        /// asInvoker (read 28 Sep), and started from this launcher, which is
        /// not elevated, it installs the runtime for this Windows account
        /// only, with no administrator prompt. That copy comes without
        /// Microsoft's mDNS firewall rule, which is why Begin turns mDNS off.
        ///
        /// The download is run only when Windows says Microsoft signed it
        /// (Signature.MicrosoftRefusal, #1330); anything else is deleted
        /// unrun and the log says why.
        ///
        /// Failure is not fatal anywhere. Voice stays off, the launcher is
        /// untouched, and it tries again next start.
        /// </summary>
        static void Bootstrap()
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                string exe = Path.Combine(Path.GetTempPath(), "MicrosoftEdgeWebview2Setup.exe");
                try
                {
                    // TLS 1.2, because .NET Framework 4 defaults to versions
                    // Microsoft's servers stopped accepting years ago and the
                    // failure looks like a network outage rather than a policy.
                    try { ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; } catch (Exception ex) { Swallow.Note("Voice.Bootstrap, TLS", ex); }

                    using (var web = new WebClient())
                    {
                        web.DownloadFile("https://go.microsoft.com/fwlink/p/?LinkId=2124703", exe);
                    }
                }
                catch (Exception ex)
                {
                    Say("Voice: could not download the WebView2 runtime: " + ex.Message);
                    return;
                }

                // Only a program Microsoft signed is run (#1330). The file came
                // over the network, so without this whoever could change it on
                // the way, or at the server it came from, chose what ran here.
                // Signature.MicrosoftRefusal says what it checks and why.
                string said;
                string why = Signature.MicrosoftRefusal(exe, out said);
                if (why.Length > 0)
                {
                    Say("Voice: the WebView2 installer that was downloaded " + why +
                        " It was not run, and voice is off until the next start.");
                    try { File.Delete(exe); } catch (Exception ex) { Swallow.Note("Voice.Bootstrap, delete refused installer", ex); }
                    return;
                }
                Say("Voice: the WebView2 installer is Microsoft's. " + said);

                try
                {
                    var psi = new ProcessStartInfo(exe, "/silent /install");
                    psi.UseShellExecute = true;
                    var proc = Process.Start(psi);
                    if (proc != null) proc.WaitForExit(10 * 60 * 1000);
                }
                catch (Exception ex)
                {
                    Say("Voice: the WebView2 installer would not run: " + ex.Message);
                    return;
                }
                finally
                {
                    try { File.Delete(exe); } catch (Exception ex) { Swallow.Note("Voice.Bootstrap, delete installer", ex); }
                }

                string v = RuntimeVersion();
                if (v == null)
                {
                    Say("Voice: the WebView2 runtime still is not there. Voice is off until the next start.");
                    return;
                }

                Say("Voice: WebView2 runtime " + v + " installed. Starting voice.");
                try
                {
                    var app = System.Windows.Application.Current;
                    if (app == null) return;
                    app.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        try { Begin(delegate { }); } catch (Exception ex) { Say("Voice: " + ex.Message); }
                    }));
                }
                catch (Exception ex) { Swallow.Note("Voice.Bootstrap", ex); }
            });
        }

        /// <summary>The voice page rides in the exe too, and is written out beside it.</summary>
        static string PlacePage(Action<string> log)
        {
            try
            {
                byte[] want = Resource(PageFile);
                if (want == null) { Say("Voice: " + PageFile + " is not embedded in this build"); return null; }
                string dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
                string path = Path.Combine(dir, PageFile);
                if (!File.Exists(path) || new FileInfo(path).Length != want.Length)
                {
                    File.WriteAllBytes(path, want);
                }
                return path;
            }
            catch (Exception ex) { Say("Voice: could not place " + PageFile + ": " + ex.Message); return null; }
        }

        /// <summary>
        /// The profile id has to be the one the game uses or nobody is matched
        /// to their own character, so it is read from the same file the game
        /// reads rather than worked out again here.
        ///
        /// Unless Reconfigure(int) has said otherwise. Since 20 September the
        /// settings file holds the id played last and the person picks at the
        /// game's menu, so once the choice file names somebody the file is
        /// stale and the number Shell hands over is the truth. The file is
        /// never rewritten while the game runs (it hot reloads every plugin),
        /// which is why this cannot simply read it again.
        /// </summary>
        static long profileOverride;

        static long ProfileId()
        {
            if (profileOverride > 0) return profileOverride;
            try
            {
                string f = Path.Combine(Paths.Game, "Data\\Platform\\Plugins\\skymp5-client-settings.txt");
                if (!File.Exists(f)) return 0;
                Match m = Regex.Match(File.ReadAllText(f), "\"profileId\"\\s*:\\s*(\\d+)");
                if (!m.Success) return 0;
                return long.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
            }
            catch { return 0; }
        }

        static void Post(string json)
        {
            try
            {
                if (view == null) return;
                view.Dispatcher.BeginInvoke(new Action(delegate
                {
                    try { view.CoreWebView2.PostWebMessageAsString(json); } catch (Exception ex) { Swallow.Note("Voice.Post, web message", ex); }
                }));
            }
            catch (Exception ex) { Swallow.Note("Voice.Post", ex); }
        }

        /// <summary>
        /// A short lived token saying which profile this launcher may join as.
        /// </summary>
        /// <remarks>
        /// The voice port used to believe whatever the join message said its
        /// profile was, and that number is the whole of somebody's identity
        /// here. Anybody who could reach the port was anybody they liked: they
        /// heard every conversation in the world, spoke as somebody else, and
        /// read every person's position off the roster.
        ///
        /// The Discord ticket is what proves anything. The voice service asks
        /// the site whether that ticket owns this profile and signs the answer,
        /// and the page sends what comes back instead of a bare number.
        ///
        /// Empty on any failure, deliberately. While the service is set to log
        /// rather than refuse, a token that could not be fetched means voice
        /// still works and a line lands in the service log. When it is set to
        /// refuse, this is the difference between voice and no voice, and the
        /// person needs to be told which, so the caller says so.
        /// </remarks>
        static string FetchToken(string host, string port, long profile, Action<string> log)
        {
            string ticket = "";
            try { ticket = Discord.Ticket; } catch { ticket = ""; }
            if (ticket == null) ticket = "";
            if (ticket.Length == 0)
            {
                if (log != null) log("Voice: not linked to Discord, so no join token. Voice may be refused.");
                return "";
            }

            // Through Caddy when one is configured, the raw port otherwise.
            string url = (conf == null ? ("http://" + host + ":" + port) : conf.VoiceBase()) + "/token";

            // The ticket only ever goes over https (To Do 144). It is a thirty
            // day credential, as good as this person's Discord account to the
            // site, and it sits under DPAPI on disk; every other place that
            // sends it goes to Discord.Site, which is https. This one follows
            // VoiceBase, and VoiceBase falls back to http://address:port
            // whenever VoiceUrl is empty: a new install until its first
            // update check has filled it in, and the rollback the feed can
            // order by sending voiceUrl empty. Both posted the ticket here in
            // the clear. No token means an unproven join, which the service
            // lets through while THORNSWOOD_VOICE_AUTH is log and refuses
            // when it is on. A failed fetch is retried by the renewal five minutes later, so
            // a session that started before the update check gets its token
            // once the feed has filled the https address in.
            if (!url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                if (log != null) log("Voice: no join token, because the voice address is not https and the Discord ticket only goes over https. Voice may be refused.");
                return "";
            }

            string body = "{\"profileId\":" + profile.ToString(CultureInfo.InvariantCulture) +
                          ",\"ticket\":\"" + JsonEscape(ticket) + "\"}";
            try
            {
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Method = "POST";
                req.ContentType = "application/json";
                req.Timeout = 5000;
                req.ReadWriteTimeout = 5000;
                byte[] rawBody = Encoding.UTF8.GetBytes(body);
                req.ContentLength = rawBody.Length;
                using (var s = req.GetRequestStream()) { s.Write(rawBody, 0, rawBody.Length); }
                using (var resp = (HttpWebResponse)req.GetResponse())
                {
                    string text;
                    using (var r = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
                    {
                        text = r.ReadToEnd();
                    }
                    Match m = Regex.Match(text, "\"token\"\\s*:\\s*\"([^\"]+)\"");
                    if (!m.Success)
                    {
                        if (log != null) log("Voice: the service answered without a token.");
                        return "";
                    }
                    // Never the token itself. It is what somebody would need to
                    // join as this person, and the log is a file on disk.
                    if (log != null) log("Voice: got a join token for profile " + profile);
                    return m.Groups[1].Value;
                }
            }
            catch (WebException we)
            {
                var hr = we.Response as HttpWebResponse;
                if (hr != null && (int)hr.StatusCode == 403)
                {
                    if (log != null) log("Voice: the server says this Discord account does not own profile " + profile + ".");
                }
                else if (log != null)
                {
                    log("Voice: could not get a join token (" + we.Message + ").");
                }
                return "";
            }
            catch (Exception e)
            {
                if (log != null) log("Voice: could not get a join token (" + e.Message + ").");
                return "";
            }
        }

        /// <summary>Quote anything that would end a JSON string early.</summary>
        static string JsonEscape(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            var b = new StringBuilder(s.Length + 8);
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (c == '"' || c == '\\') { b.Append('\\'); b.Append(c); }
                else if (c < ' ') { b.Append(' '); }
                else { b.Append(c); }
            }
            return b.ToString();
        }

        /*
          When the join token was last fetched, and what it was for.

          A token expires; the host, port and profile it was fetched for do not.
          Configure() returns early when those three are unchanged, which is
          almost always, so without this the token was minted once when the
          voice page loaded and never again. The first real join after shipping
          was refused as expired for exactly that reason.
        */
        static DateTime tokenGot = DateTime.MinValue;
        static string tokenHost = "";
        static string tokenPort = "";
        static long tokenProfile = 0;

        /// <summary>
        /// Fetch a fresh join token and hand it to both ends, if the last one
        /// is old enough to be worth replacing.
        /// </summary>
        /// <remarks>
        /// Renewed at half its life rather than at the end of it, so a token is
        /// never nearly expired when somebody needs it. The service issues them
        /// for an hour, so this is every thirty minutes, and it costs one small
        /// request to a service already on the other end of the voice socket.
        ///
        /// Quiet on failure. The old token is still in the file and is still
        /// good for another half hour, which is far better than clearing it.
        /// </remarks>
        static void RenewToken()
        {
            RenewToken(false);
        }

        /*
          The token fields are read and written from three threads now: the
          file channel's tick, the config sent when the page loads, and a
          refusal passed up by the page. One at a time, and a caller that finds
          another already fetching goes away rather than queueing a second
          request behind it.
        */
        static readonly object tokenLock = new object();
        static DateTime forcedAt = DateTime.MinValue;

        /// <summary>
        /// As above, or at once when the voice service has just refused the
        /// page's token (force), at most every thirty seconds.
        /// </summary>
        /// <remarks>
        /// Issue #409. On 21 September the machine woke at 20:06 with a token
        /// from 19:02, an hour old and expired. The tick tried to renew it at
        /// once, while the Wi-Fi was still coming back, failed, and dated
        /// itself five minutes on, so for five minutes the page offered the
        /// dead token every two seconds and was refused 134 times. A refusal
        /// is now what asks for the new token, and the page waits for it.
        /// </remarks>
        static void RenewToken(bool force)
        {
            if (!Monitor.TryEnter(tokenLock)) return;
            try
            {
                if (tokenProfile <= 0 || tokenHost.Length == 0) return;
                if (force)
                {
                    if ((DateTime.UtcNow - forcedAt).TotalSeconds < 30) return;
                    forcedAt = DateTime.UtcNow;
                }
                else
                {
                    if (tokenGot == DateTime.MinValue) return;
                    if ((DateTime.UtcNow - tokenGot).TotalMinutes < 30) return;
                }

                string fresh = FetchToken(tokenHost, tokenPort, tokenProfile, null);
                if (fresh.Length == 0)
                {
                    // Try again on the next pass rather than every 100ms.
                    tokenGot = DateTime.UtcNow.AddMinutes(-25);
                    return;
                }
                tokenGot = DateTime.UtcNow;
                try { WriteChannel("voice-token.txt", fresh); } catch (Exception ex) { Swallow.Note("Voice.RenewToken, write channel", ex); }
                Post("{\"t\":\"token\",\"token\":\"" + JsonEscape(fresh) + "\"}");
                Say("Voice: join token renewed");
            }
            finally { Monitor.Exit(tokenLock); }
        }

        // The last config the page was given, as host, port and profile.
        static string lastConfig = "";

        // A page that has just loaded knows nothing of what it was sent before,
        // so that path asks for a config whatever this says.
        static void Configure(Action<string> log)
        {
            // Nor who is muted, so the file channel hands that over again.
            mutedSeen = null;
            Configure(log, true);
        }

        static void Configure(Action<string> log, bool force)
        {
            long profile = ProfileId();
            string host = conf == null ? "" : conf.ServerAddress;
            string port = conf == null ? "" : conf.VoicePort;
            if (string.IsNullOrEmpty(port)) port = "7778";

            if (string.IsNullOrEmpty(host) || profile == 0)
            {
                Say("Voice: not configured yet (host '" + host + "', profile " + profile + ")");
                return;
            }

            // The page opens a socket for every config it is handed and the
            // voice service keeps a peer for every socket. Pressing Play twice
            // in one session on the same character is the same config again,
            // and all the second one leaves behind is a ghost on the roster
            // announcing where the last slot was standing. Only a config that
            // changed something is worth sending.
            string want = host + ":" + port + ":" + profile;
            if (!force && want == lastConfig)
            {
                // Worded as the working state it is. This used to read
                // "already configured for ...", one word away from the
                // success line below, and a tester on 21 September reported
                // it as a fault. Nothing is wrong here: voice is up for this
                // profile and there was nothing left to send it.
                Say("Voice: on for " + host + ":" + port + " as profile " + profile);
                return;
            }
            lastConfig = want;

            /*
              The rest waits on a network, so it never runs on the window's
              thread. The page's NavigationCompleted calls this on that thread,
              and the token fetch below is a web request with five second
              timeouts and a name lookup that can take fifteen seconds
              whatever the timeout says, so a slow network at startup could
              hold the launcher window that long (issue #409). Numbered, so
              that when two configs are in flight only the newest reaches the
              page.
            */
            int seq = Interlocked.Increment(ref configSeq);
            ThreadPool.QueueUserWorkItem(delegate
            {
                try { SendConfig(seq, host, port, profile); }
                catch (Exception ex) { Swallow.Note("Voice.Configure, send", ex); }
            });
        }

        static int configSeq;

        static void SendConfig(int seq, string host, string port, long profile)
        {
            // Fetched here rather than in the page, because the ticket lives in
            // this process and has no business being handed to a browser.
            string token = FetchToken(host, port, profile, Say);
            if (seq != Thread.VolatileRead(ref configSeq)) return;

            // What the renewal fetches for, whether or not this fetch worked.
            // These used to move only on success, so a config for a new id
            // whose first fetch failed left the renewal minting tokens for the
            // previous id, and voice-token.txt with them. A failed fetch is
            // dated so the renewal tries again in five minutes rather than
            // thirty.
            lock (tokenLock)
            {
                tokenHost = host;
                tokenPort = port;
                tokenProfile = profile;
                tokenGot = token.Length > 0 ? DateTime.UtcNow : DateTime.UtcNow.AddMinutes(-25);
            }

            // The game's overlay joins the same room on its own socket and holds
            // no ticket, so it reads the token out of the folder the two already
            // share for push to talk. Short lived on purpose: five minutes, for
            // one profile, and worth nothing to anybody who is not already on
            // this machine as this person.
            try { WriteChannel("voice-token.txt", token); } catch (Exception ex) { Swallow.Note("Voice.Configure, write token", ex); }

            // base and socket are what the page should use. host and port stay on
            // the message so an older page, or one that has not been rebuilt,
            // carries on building the url the way it always did.
            string vbase = conf == null ? ("http://" + host + ":" + port) : conf.VoiceBase();
            string vsock = conf == null ? ("ws://" + host + ":" + port + "/") : conf.VoiceSocket();
            Post("{\"t\":\"config\",\"host\":\"" + host + "\",\"port\":\"" + port +
                 "\",\"profileId\":" + profile + ",\"name\":\"\"" +
                 ",\"base\":\"" + JsonEscape(vbase) + "\"" +
                 ",\"socket\":\"" + JsonEscape(vsock) + "\"" +
                 ",\"token\":\"" + JsonEscape(token) + "\"}");
            Say("Voice: configured for " + host + ":" + port + " as profile " + profile +
                (token.Length == 0 ? " with no join token" : ""));
        }

        /// <summary>
        /// Send the voice page its config again.
        ///
        /// Voice is configured once, when its page finishes loading, and that
        /// happens while the launcher is still starting up. Pressing Play on a
        /// new character rolls a new profile id well after that, so voice went
        /// on announcing itself as whoever last held the slot and nobody was
        /// matched to their own character. The launch at 2026-09-16 02:25 had
        /// voice on 950724594 while the game was handed 579810940.
        ///
        /// Chars.Prepare calls this before the game starts with the id played
        /// last, and Shell calls it again with whoever the person picked at
        /// the game's menu (20 September; until then Chars.Use called the
        /// parameterless version the moment a slot's id was written). The id
        /// is passed rather than read back out of the settings file because
        /// the file is not rewritten while the game runs. Safe to call before
        /// the page exists: Post does nothing without a view, and Configure
        /// says so and returns when there is no id yet.
        ///
        /// A config the page already has is not sent twice. Every one it is
        /// handed opens a socket, and the service keeps a peer per socket, so a
        /// second Play on the same character used to leave a ghost peer behind
        /// announcing the previous slot.
        /// </summary>
        public static void Reconfigure(int profileId)
        {
            if (profileId > 0) profileOverride = profileId;
            try { Configure(null, false); } catch (Exception ex) { Swallow.Note("Voice.Reconfigure", ex); }
        }

        static void OnPageMessage(string raw, Action<string> log)
        {
            if (string.IsNullOrEmpty(raw)) return;
            Match t = Regex.Match(raw, "\"t\"\\s*:\\s*\"([^\"]*)\"");
            Match x = Regex.Match(raw, "\"text\"\\s*:\\s*\"(.*)\"\\s*}\\s*$");
            string kind = t.Success ? t.Groups[1].Value : "log";
            string text = x.Success ? x.Groups[1].Value : raw;
            // Push to talk flips many times a minute and the peer count
            // repeats itself constantly. Neither belongs in a log a person
            // reads, and an unlabelled "Voice: 0" belongs there least of all.
            if (kind == "talking") { talking = text == "1"; PublishStatus(); return; }

            if (kind == "debug") { Quiet("Voice: " + text); return; }

            // The service refused the page's token. A fresh one, now and off
            // this thread, which the page waits for before trying again. The
            // page says what happened on the status line; this is the file.
            if (kind == "denied")
            {
                Quiet("Voice: the voice server refused the join token (" + text + "), fetching a fresh one");
                ThreadPool.QueueUserWorkItem(delegate
                {
                    try { RenewToken(true); } catch (Exception ex) { Swallow.Note("Voice.OnPageMessage, renew", ex); }
                });
                return;
            }

            if (kind == "peers")
            {
                int n; int.TryParse(text, out n); peerCount = n;
                PublishStatus();
                if (text == lastPeers) return;
                lastPeers = text;
                Say("Voice: " + text + (text == "1" ? " peer connected" : " peers connected"));
                return;
            }

            if (kind == "status")
            {
                if (text == "mic ready") micOk = true;
                if (text == "no microphone") micOk = false;
                PublishStatus();
                if (text == lastStatus) return;
                lastStatus = text;
                Say("Voice: " + text);
                return;
            }

            Say("Voice: " + text);
        }


        // ------------------------------------------------------------------
        // The file channel.
        //
        // The loopback listener above was the only way the game could see any
        // of this, and it has one failure mode that costs nothing to hit and
        // gives nothing back. The game's voice page is loaded from file://,
        // which is an opaque origin; a fetch from there to 127.0.0.1 is a
        // cross-origin request into the local address space, and Chromium is
        // within its rights to refuse it outright. When it does, the page's
        // fetch rejects, and a rejected fetch is silent. No line in any log on
        // either side, no error anywhere, and a microphone indicator that sits
        // on LISTENING ONLY for the rest of the session while voice itself
        // works perfectly, because the audio does not run in that page any
        // more and never needed the page's permission.
        //
        // That is not a thing to diagnose twice. Two small files in the
        // profile folder do the same job with no origin, no port to discover
        // and no silent branch:
        //
        //   voice-status.txt   written here, read by the game
        //                      "<mic> <peers> <talking> <mode>"
        //   voice-ptt.txt      written by the game, read here
        //                      "<on> <mode>"
        //   voice-muted.txt    written by the game, read here
        //                      "<profileId> <profileId> ...", who is muted
        //
        // The game plugin already reads voice-port.txt out of this same folder
        // every three seconds and has never once failed to, which is the whole
        // argument for using it. The listener stays where it is: push to talk
        // works through it today and there is no reason to take a working path
        // away. Whichever arrives first wins, and they both say the same
        // thing, so there is nothing for them to disagree about.
        // ------------------------------------------------------------------

        /// <summary>
        /// Where the three voice files live: Data\Platform inside the game
        /// folder first, then the Profile folder.
        ///
        /// The Profile folder was the only home, and the game plugin reached
        /// it as "../Profile" from the game folder. That is right when the
        /// game is Root\Game and nowhere else. On a collection install the
        /// game is the Steam copy, "../Profile" from there does not exist, and
        /// the plugin never found voice-port.txt or voice-status.txt: the page
        /// in the game ran its own voice, asked NirnLab's browser for a
        /// microphone it has no way to grant, and sat on LISTENING ONLY while
        /// this launcher was connected with the microphone open. Push to talk
        /// went the same way, into a file nothing read.
        ///
        /// Data\Platform is the one place both ends find without knowing
        /// anything about the other: the plugin runs with the game folder as
        /// its working directory, and this side knows Paths.Game. Both are
        /// written, so an older plugin on the old layout still works.
        /// </summary>
        static string[] ChannelDirs()
        {
            string game = "";
            try { game = Path.Combine(Paths.Game, "Data\\Platform"); } catch (Exception ex) { Swallow.Note("Voice.ChannelDirs, game path", ex); }
            if (game.Length > 0 && Directory.Exists(game)) return new string[] { game, Paths.ProfileDir };
            return new string[] { Paths.ProfileDir };
        }

        static void WriteChannel(string name, string text)
        {
            foreach (string d in ChannelDirs())
            {
                try { File.WriteAllText(Path.Combine(d, name), text); } catch (Exception ex) { Swallow.Note("Voice.WriteChannel, write", ex); }
            }
        }

        static string lastStatusLine = "";

        /// <summary>
        /// Puts the current state where the game can read it. Cheap enough to
        /// call on every change, and it writes nothing when nothing moved.
        /// </summary>
        static void PublishStatus()
        {
            try
            {
                string line = (micOk ? "1" : "0") + " " +
                              peerCount.ToString(CultureInfo.InvariantCulture) + " " +
                              (talking ? "1" : "0") + " " +
                              (voiceMode ?? "local");
                if (line == lastStatusLine) return;
                lastStatusLine = line;
                WriteChannel("voice-status.txt", line);
            }
            catch (Exception ex) { Swallow.Note("Voice.PublishStatus", ex); }
        }

        /// <summary>
        /// The slow tick's half of PublishStatus: puts the line back in any
        /// folder whose copy is missing or says something else, and writes
        /// nothing when both already say it. It used to write both copies
        /// every two seconds whatever they said (#963, #977); a read of an
        /// eleven byte file is all an unchanged one costs now.
        /// </summary>
        static void RepublishIfLost()
        {
            string line = lastStatusLine;
            if (string.IsNullOrEmpty(line)) { PublishStatus(); return; }
            foreach (string d in ChannelDirs())
            {
                string f = Path.Combine(d, "voice-status.txt");
                string there = null;
                try { if (File.Exists(f)) there = File.ReadAllText(f).Trim(); }
                catch (Exception ex) { Swallow.Note("Voice.RepublishIfLost, read", ex); there = null; }
                if (there == line) continue;
                try { File.WriteAllText(f, line); } catch (Exception ex) { Swallow.Note("Voice.RepublishIfLost, write", ex); }
            }
        }

        /// <summary>
        /// The last mute line handed to the voice page, or null when the page
        /// has not been given one. Written from the UI thread when the page
        /// loads and from the file channel's thread, hence volatile.
        /// </summary>
        static volatile string mutedSeen;

        /// <summary>
        /// Set when a read of a file the game writes met it mid-write, so the
        /// file channel looks again in 100 ms instead of waiting for a change.
        /// </summary>
        static volatile bool readAgain;

        /// <summary>
        /// Who this person has muted, from the game to the page that plays
        /// the audio.
        ///
        /// The mute from #133 reached the game's own page and stopped there.
        /// That page carries no audio once the launcher has it, so the voice
        /// page here went on playing a muted person at full level: measured on
        /// 23 September, profile 123 muted in the game and beside you, gain 1
        /// here. The server's list reaches the game's page, the voice plugin
        /// writes it into voice-muted.txt, and this passes it on whenever it
        /// changes. The page reads the ids out of the line itself and drops
        /// anything that is not one.
        /// </summary>
        static void PassMuted(string[] dirs)
        {
            string now = null;
            foreach (string d in dirs)
            {
                string f = Path.Combine(d, "voice-muted.txt");
                if (!File.Exists(f)) continue;
                try { now = File.ReadAllText(f).Trim(); }
                catch { now = null; readAgain = true; }   // mid-write, try again in 100ms
                if (now != null) break;
            }
            if (now == null || now == mutedSeen) return;
            mutedSeen = now;
            Post("{\"t\":\"muted\",\"list\":\"" + JsonEscape(now) + "\"}");
            int n = Regex.Matches(now, "\\d+").Count;
            Quiet("Voice: the game says " + n + (n == 1 ? " person is" : " people are") + " muted");
        }

        /// <summary>
        /// Watches for push to talk and mode changes written by the game, and
        /// republishes our own state on a slow tick so a game that starts late
        /// still finds something to read.
        /// </summary>
        static void StartFileChannel(Action<string> log)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                string[] dirs = ChannelDirs();
                string seen = null;
                DateTime republished = DateTime.UtcNow;

                // Clear anything left behind by the last session, or a key held
                // down when the game was closed would be read back as held.
                WriteChannel("voice-ptt.txt", "0 local");

                lastStatusLine = "";
                PublishStatus();

                // Woken by the game writing push to talk or the mute list,
                // not by a 100 ms poll (#977). See ChannelWait.
                ChannelWait wake = new ChannelWait(dirs, "voice-ptt.txt", "voice-muted.txt");
                Say("Voice: talking to the game through " + string.Join(" and ", dirs) +
                    (wake.Watching ? ", woken when the game writes" : ", read every " + ChannelWait.Poll + " ms"));

                while (true)
                {
                    try
                    {
                        // Push to talk is read the moment Windows says the
                        // file changed. The two second timeout is the slow
                        // tick below; with no watcher this is the old 100 ms
                        // sleep. A read that met the game mid-write is tried
                        // again in 100 ms, as before, rather than waiting on
                        // a change Windows has already reported.
                        bool again = readAgain;
                        readAgain = false;
                        wake.Wait(again ? ChannelWait.Poll : 2000);

                        // Republished on a slow tick as well as on change,
                        // because the game may have started after the last
                        // change and a file it never sees is no better than no
                        // file. Two seconds, and only a copy that is missing
                        // or says something else is written: this used to
                        // rewrite both copies every two seconds, and before
                        // that ten times a second, game or no game.
                        if ((DateTime.UtcNow - republished).TotalMilliseconds >= 2000)
                        {
                            republished = DateTime.UtcNow;
                            RepublishIfLost();
                            // On the same slow tick, not on every wake.
                            RenewToken();
                        }
                        PublishStatus();

                        // Before push to talk, whose unchanged line ends the
                        // pass with a continue.
                        PassMuted(dirs);

                        // The game folder copy is read first: it is the one a
                        // plugin on a collection install can write.
                        string now = null;
                        foreach (string d in dirs)
                        {
                            string f = Path.Combine(d, "voice-ptt.txt");
                            if (!File.Exists(f)) continue;
                            try { now = File.ReadAllText(f).Trim(); }
                            catch { now = null; readAgain = true; }   // mid-write, try again in 100ms
                            if (now != null) break;
                        }
                        if (now == null || now.Length == 0 || now == seen) continue;
                        seen = now;

                        string[] bits = now.Split(' ');
                        bool on = bits.Length > 0 && bits[0] == "1";
                        Post("{\"t\":\"ptt\",\"on\":" + (on ? "true" : "false") + "}");

                        if (bits.Length > 1 && bits[1].Length > 0 && bits[1] != voiceMode)
                        {
                            voiceMode = bits[1];
                            Post("{\"t\":\"mode\",\"mode\":\"" + voiceMode + "\"}");
                        }
                    }
                    catch (Exception ex) { Swallow.Note("Voice.StartFileChannel", ex); }
                }
            });
        }

        /// <summary>
        /// Push to talk arrives from the game, which cannot reach this process
        /// any other way. A loopback listener on a port nobody else wants, and
        /// the port written where the game plugin can find it.
        /// </summary>
        static void StartPttListener(Action<string> log)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                HttpListener http = null;
                int port = 0;
                for (int p = 47780; p < 47800; p++)
                {
                    try
                    {
                        http = new HttpListener();
                        http.Prefixes.Add("http://127.0.0.1:" + p + "/");
                        http.Start();
                        port = p;
                        break;
                    }
                    catch { http = null; }
                }
                if (http == null) { Say("Voice: no free loopback port for push to talk"); return; }

                try
                {
                    WriteChannel("voice-port.txt", port.ToString(CultureInfo.InvariantCulture));
                }
                catch (Exception ex) { Swallow.Note("Voice.StartPttListener, write port", ex); }
                Say("Voice: listening for push to talk on 127.0.0.1:" + port);

                while (true)
                {
                    HttpListenerContext c;
                    try { c = http.GetContext(); } catch { return; }
                    try
                    {
                        string q = c.Request.Url.Query;
                        if (c.Request.Url.AbsolutePath == "/ptt")
                        {
                            bool on = q.IndexOf("on=1", StringComparison.Ordinal) >= 0;
                            Post("{\"t\":\"ptt\",\"on\":" + (on ? "true" : "false") + "}");
                        }
                        else if (c.Request.Url.AbsolutePath == "/mode")
                        {
                            Match m = Regex.Match(q, "mode=([a-z]+)");
                            if (m.Success)
                            {
                                voiceMode = m.Groups[1].Value;
                                Post("{\"t\":\"mode\",\"mode\":\"" + m.Groups[1].Value + "\"}");
                            }
                        }
                        // Every reply carries the state, so the game's
                        // indicator has something true to draw. It owns no
                        // microphone and no connections now, and asking it
                        // about either only ever returned no.
                        string body = "{\"mic\":" + (micOk ? "true" : "false") +
                                      ",\"peers\":" + peerCount +
                                      ",\"talking\":" + (talking ? "true" : "false") + "}";

                        // The game's page is a file:// origin, so it needs this.
                        //
                        // And more than this. A file:// page has an opaque
                        // origin, which Chromium files under the public
                        // address space, and a request from there to
                        // 127.0.0.1 is a private network request: it is
                        // preflighted, and the preflight is refused unless the
                        // reply says in as many words that a public page may
                        // reach this machine. Without these three headers the
                        // request never arrives, there is nothing in any log
                        // to say so, and the only symptom is an indicator that
                        // never lights and a push to talk key that does
                        // nothing. They are cheap, so they are here, but
                        // nothing depends on them any more: the status the
                        // game draws and the mode it sets travel by file now,
                        // through StartFileChannel below.
                        c.Response.AddHeader("Access-Control-Allow-Origin", "*");
                        c.Response.AddHeader("Access-Control-Allow-Private-Network", "true");
                        c.Response.AddHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
                        c.Response.AddHeader("Access-Control-Allow-Headers", "*");
                        c.Response.ContentType = "application/json";
                        byte[] ok = Encoding.UTF8.GetBytes(body);
                        c.Response.ContentLength64 = ok.Length;
                        c.Response.OutputStream.Write(ok, 0, ok.Length);
                        c.Response.OutputStream.Close();
                    }
                    catch (Exception ex) { Swallow.Note("Voice.StartPttListener, request", ex); }
                }
            });
        }
    }
}
