using System;
using System.IO;
using System.Text;
using System.Windows;

namespace Thornswood
{
    /// <summary>
    /// Menu theme for the launcher. WPF MediaPlayer needs Windows Media Player
    /// / the Media Feature Pack. On the ship PC that pack is missing, so Open
    /// succeeds and Play fails with "Windows Media Player version 10 or later
    /// is required." Mixer then shows no Thornswood.exe audio. Voice already
    /// works through WebView2 on the same machine, so the theme plays in a
    /// separate hidden WebView2 with HTML5 audio. Voice's host and WebView2
    /// instance are never touched.
    ///
    /// The page is a real file next to the track under Profile\Music. A
    /// NavigateToString document cannot load a file:// audio src (Chromium
    /// blocks it); that showed up in launcher.log as "HTML5 audio failed"
    /// after the ApplicationIdle deferral fixed the earlier event-loop error.
    /// Autoplay uses WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS so play() works in a hidden host.
    /// </summary>
    static class MenuMusic
    {
        const string HostFile = "menu-music-host.html";

        static Microsoft.Web.WebView2.Wpf.WebView2 view;
        static Window host;
        static bool ready;
        static bool wantPlay;
        static double wantVol = 0.5;
        static string trackPath;
        static Action<string> log;

        /// <summary>
        /// Bumped every time the browser is made or closed, so an answer from
        /// the browser that was closed (its environment arriving late, say)
        /// finds it is no longer the current one and does nothing.
        /// </summary>
        static int generation;

        /// <summary>
        /// How many times the browser has been made this session, and closed.
        /// For tests\test-963-perf-settings.ps1 and the log line.
        /// </summary>
        public static int Opened, Closed;

        /// <summary>
        /// Remembers the track and the volume. The browser itself is made the
        /// first time Decide asks for the music, not here: a launcher that
        /// starts while the game runs, or with the music off in Settings,
        /// never makes one at all.
        /// </summary>
        public static void Start(string file, double volume, Action<string> say)
        {
            log = say;
            trackPath = file;
            wantVol = Clamp(volume);
            try { Voice.Prepare(); }
            catch (Exception ex)
            {
                Stamp("Menu music: WebView2 path did not start (" + ex.Message + ")");
            }
        }

        static void Open()
        {
            try { Begin(); }
            catch (Exception ex)
            {
                Stamp("Menu music: WebView2 path did not start (" + ex.Message + ")");
            }
        }

        /// <summary>
        /// Closes the browser that plays the theme, which ends its own WebView2
        /// processes (it has a profile folder of its own, MusicBrowser, so none
        /// of voice's). Called when the game starts. Patrick, 28 September
        /// (#963): the paused browser stayed alive for the whole session, a
        /// second Chromium sitting beside the game doing nothing. Decide makes
        /// a new one when the music is wanted again after the game closes.
        /// Safe to call any time, as often as wanted.
        /// </summary>
        public static void Close()
        {
            wantPlay = false;
            if (view == null && host == null) return;
            generation++;
            ready = false;
            var v = view;
            var h = host;
            view = null;
            host = null;
            try { if (v != null) v.Dispose(); } catch (Exception ex) { Swallow.Note("MenuMusic.Close, view", ex); }
            try { if (h != null) h.Close(); } catch (Exception ex) { Swallow.Note("MenuMusic.Close, host", ex); }
            Closed++;
            Stamp("Menu music: closed its browser while the game runs");
        }

        static double Clamp(double v)
        {
            if (v < 0) return 0;
            if (v > 1) return 1;
            return v;
        }

        static void Stamp(string m)
        {
            try { if (log != null) log(m); } catch (Exception ex) { Swallow.Note("MenuMusic.Stamp", ex); }
        }

        /// <summary>
        /// Writes the HTML5 host beside the track so the audio src is a same-
        /// folder relative name. Returns the host path, or null on failure.
        /// </summary>
        static string PlaceHost(string trackFile)
        {
            try
            {
                string dir = Path.GetDirectoryName(trackFile);
                if (string.IsNullOrEmpty(dir)) return null;
                Directory.CreateDirectory(dir);
                string name = Path.GetFileName(trackFile);
                // Attribute-safe: our track names are plain ASCII.
                string safe = name.Replace("&", "&amp;").Replace("\"", "&quot;").Replace("'", "&#39;");
                string html =
                    "<!doctype html><html><head><meta charset='utf-8'></head>" +
                    "<body style='background:#000;margin:0'>" +
                    "<audio id='a' loop preload='auto' src='" + safe + "'></audio>" +
                    "<script>" +
                    "const a=document.getElementById('a');" +
                    "window.chrome.webview.addEventListener('message',ev=>{" +
                    "try{const m=JSON.parse(ev.data);" +
                    "if(m.cmd==='vol')a.volume=Math.max(0,Math.min(1,+m.v||0));" +
                    "if(m.cmd==='play'){a.volume=Math.max(0,Math.min(1,+m.v||0));" +
                    "a.play().then(()=>{}).catch(err=>window.chrome.webview.postMessage('playfail:'+String(err&&err.message||err)));}" +
                    "if(m.cmd==='pause')a.pause();" +
                    "}catch(err){/*ignore*/}" +
                    "});" +
                    "a.addEventListener('error',()=>{" +
                    "var c=(a.error&&a.error.code)||0;" +
                    "window.chrome.webview.postMessage('err:'+c);" +
                    "});" +
                    "a.addEventListener('playing',()=>window.chrome.webview.postMessage('ok'));" +
                    "</script></body></html>";
                string path = Path.Combine(dir, HostFile);
                File.WriteAllText(path, html, new UTF8Encoding(false));
                return path;
            }
            catch (Exception ex)
            {
                Stamp("Menu music: could not write the host page (" + ex.Message + ")");
                return null;
            }
        }

        static void Begin()
        {
            if (view != null) return;
            if (string.IsNullOrEmpty(trackPath)) return;

            string hostPath = PlaceHost(trackPath);
            if (hostPath == null) return;

            // This browser's own handles. Everything below that runs later
            // (the environment arriving, the page loading) checks it is still
            // the current one first: Close may have come in between.
            int gen = ++generation;
            Opened++;
            var h = new Window
            {
                Width = 64,
                Height = 64,
                ShowInTaskbar = false,
                WindowStyle = WindowStyle.None,
                ShowActivated = false,
                Visibility = Visibility.Hidden,
                Title = "Thornswood music"
            };
            var v = new Microsoft.Web.WebView2.Wpf.WebView2();
            host = h;
            view = v;
            h.Content = v;
            h.Left = -10000;
            h.Top = -10000;
            // Shown offscreen then hidden so the control actually creates its
            // browser (same pattern as Voice).
            h.Show();
            h.Hide();

            string pageUri = new Uri(hostPath).AbsoluteUri;

            v.CoreWebView2InitializationCompleted += delegate (
                object s,
                Microsoft.Web.WebView2.Core.CoreWebView2InitializationCompletedEventArgs e)
            {
                try
                {
                    if (gen != generation) return;
                    if (!e.IsSuccess || v.CoreWebView2 == null)
                    {
                        string detail = e.InitializationException == null
                            ? "no reason given"
                            : e.InitializationException.Message;
                        Stamp("Menu music: WebView2 failed to initialise (" + detail + ")");
                        return;
                    }

                    var core = v.CoreWebView2;
                    core.WebMessageReceived += delegate (
                        object s2,
                        Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs a)
                    {
                        try
                        {
                            string msg = a.TryGetWebMessageAsString();
                            if (msg == null) return;
                            if (msg == "ok")
                                Stamp("Menu music: the theme is on (WebView2), from " + trackPath);
                            else if (msg.StartsWith("err", StringComparison.Ordinal))
                                Stamp("Menu music: HTML5 audio failed for " + trackPath + " (" + msg + ")");
                            else if (msg.StartsWith("playfail", StringComparison.Ordinal))
                                Stamp("Menu music: play() refused (" + msg + ")");
                        }
                        catch (Exception ex) { Swallow.Note("MenuMusic.WebMessageReceived", ex); }
                    };

                    // Apply only after the page script is listening; a play
                    // message posted during Navigate is dropped.
                    core.NavigationCompleted += delegate (
                        object s3,
                        Microsoft.Web.WebView2.Core.CoreWebView2NavigationCompletedEventArgs nav)
                    {
                        try
                        {
                            if (gen != generation) return;
                            if (!nav.IsSuccess)
                            {
                                Stamp("Menu music: host page did not load");
                                return;
                            }
                            ready = true;
                            Apply();
                        }
                        catch (Exception ex) { Swallow.Note("MenuMusic.NavigationCompleted", ex); }
                    };

                    core.Navigate(pageUri);
                }
                catch (Exception ex)
                {
                    Stamp("Menu music: " + ex.Message);
                }
            };

            if (!Voice.EnsureLoader(Stamp))
            {
                Stamp("Menu music: WebView2Loader.dll is not beside the exe");
                return;
            }

            string profile = Path.Combine(Paths.ProfileDir, "MusicBrowser");
            try { Directory.CreateDirectory(profile); } catch (Exception ex) { Swallow.Note("MenuMusic.CreateProfile", ex); }

            // Hidden host has no user gesture. CoreWebView2EnvironmentOptions
            // with AdditionalBrowserArguments makes CreateAsync fault on the
            // ship PC (launcher.log: "no WebView2 runtime") while Voice's
            // null-options CreateAsync succeeds on the same run. Set the
            // documented WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS env var instead,
            // then create the environment the same way Voice does.
            try
            {
                string key = "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS";
                string cur = Environment.GetEnvironmentVariable(key);
                string flag = "--autoplay-policy=no-user-gesture-required";
                if (string.IsNullOrEmpty(cur))
                    Environment.SetEnvironmentVariable(key, flag);
                else if (cur.IndexOf("autoplay-policy", StringComparison.OrdinalIgnoreCase) < 0)
                    Environment.SetEnvironmentVariable(key, cur + " " + flag);
            }
            catch (Exception ex)
            {
                Stamp("Menu music: could not set autoplay env (" + ex.Message + ")");
            }

            var envTask = Microsoft.Web.WebView2.Core.CoreWebView2Environment.CreateAsync(
                null, profile, null);

            envTask.ContinueWith(delegate (
                System.Threading.Tasks.Task<Microsoft.Web.WebView2.Core.CoreWebView2Environment> t)
            {
                if (t.IsFaulted)
                {
                    string why = "unknown";
                    try
                    {
                        if (t.Exception != null)
                            why = t.Exception.GetBaseException().Message;
                    }
                    catch (Exception ex) { Swallow.Note("MenuMusic.CreateAsyncFault", ex); }
                    Stamp("Menu music: WebView2 environment failed (" + why + "); trying default");
                    h.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        if (gen != generation) return;
                        try { v.EnsureCoreWebView2Async(); }
                        catch (Exception ex) { Stamp("Menu music: " + ex.Message); }
                    }));
                    return;
                }
                if (t.Result == null)
                {
                    Stamp("Menu music: WebView2 environment was empty; trying default");
                    h.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        if (gen != generation) return;
                        try { v.EnsureCoreWebView2Async(); }
                        catch (Exception ex) { Stamp("Menu music: " + ex.Message); }
                    }));
                    return;
                }
                h.Dispatcher.BeginInvoke(new Action(delegate
                {
                    // Closed before the environment arrived: nothing to put
                    // it in, and the browser it would start is not wanted.
                    if (gen != generation) return;
                    try { v.EnsureCoreWebView2Async(t.Result); }
                    catch (Exception ex) { Stamp("Menu music: " + ex.Message); }
                }));
            });
        }

        /// <summary>
        /// Plays or pauses the theme. A pause keeps the browser, so coming
        /// back from a minimised window is instant; only Close ends it. When
        /// the music is wanted and there is no browser (the first time, or
        /// after the game closed), one is made and plays once its page is up.
        /// </summary>
        public static void Decide(bool play, double volume)
        {
            wantPlay = play;
            wantVol = Clamp(volume);
            if (play && view == null) { Open(); return; }
            Apply();
        }

        static void Apply()
        {
            if (!ready || view == null || view.CoreWebView2 == null) return;
            try
            {
                string v = wantVol.ToString(System.Globalization.CultureInfo.InvariantCulture);
                if (wantPlay)
                    view.CoreWebView2.PostWebMessageAsString("{\"cmd\":\"play\",\"v\":" + v + "}");
                else
                    view.CoreWebView2.PostWebMessageAsString("{\"cmd\":\"pause\",\"v\":" + v + "}");
            }
            catch (Exception ex) { Swallow.Note("MenuMusic.Apply", ex); }
        }
    }
}
