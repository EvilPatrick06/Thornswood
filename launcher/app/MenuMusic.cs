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

        public static void Start(string file, double volume, Action<string> say)
        {
            log = say;
            trackPath = file;
            wantVol = Clamp(volume);
            try
            {
                Voice.Prepare();
                Begin();
            }
            catch (Exception ex)
            {
                Stamp("Menu music: WebView2 path did not start (" + ex.Message + ")");
            }
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

            string hostPath = PlaceHost(trackPath);
            if (hostPath == null) return;

            host = new Window
            {
                Width = 64,
                Height = 64,
                ShowInTaskbar = false,
                WindowStyle = WindowStyle.None,
                ShowActivated = false,
                Visibility = Visibility.Hidden,
                Title = "Thornswood music"
            };
            view = new Microsoft.Web.WebView2.Wpf.WebView2();
            host.Content = view;
            host.Left = -10000;
            host.Top = -10000;
            // Shown offscreen then hidden so the control actually creates its
            // browser (same pattern as Voice).
            host.Show();
            host.Hide();

            string pageUri = new Uri(hostPath).AbsoluteUri;

            view.CoreWebView2InitializationCompleted += delegate (
                object s,
                Microsoft.Web.WebView2.Core.CoreWebView2InitializationCompletedEventArgs e)
            {
                try
                {
                    if (!e.IsSuccess || view.CoreWebView2 == null)
                    {
                        string detail = e.InitializationException == null
                            ? "no reason given"
                            : e.InitializationException.Message;
                        Stamp("Menu music: WebView2 failed to initialise (" + detail + ")");
                        return;
                    }

                    var core = view.CoreWebView2;
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
                    host.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        try { view.EnsureCoreWebView2Async(); }
                        catch (Exception ex) { Stamp("Menu music: " + ex.Message); }
                    }));
                    return;
                }
                if (t.Result == null)
                {
                    Stamp("Menu music: WebView2 environment was empty; trying default");
                    host.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        try { view.EnsureCoreWebView2Async(); }
                        catch (Exception ex) { Stamp("Menu music: " + ex.Message); }
                    }));
                    return;
                }
                host.Dispatcher.BeginInvoke(new Action(delegate
                {
                    try { view.EnsureCoreWebView2Async(t.Result); }
                    catch (Exception ex) { Stamp("Menu music: " + ex.Message); }
                }));
            });
        }

        public static void Decide(bool play, double volume)
        {
            wantPlay = play;
            wantVol = Clamp(volume);
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
