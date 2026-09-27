using System;
using System.IO;
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
    /// </summary>
    static class MenuMusic
    {
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

        static void Begin()
        {
            if (view != null) return;

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
            host.Show();
            host.Hide();

            view.CoreWebView2InitializationCompleted += delegate (
                object s,
                Microsoft.Web.WebView2.Core.CoreWebView2InitializationCompletedEventArgs e)
            {
                try
                {
                    if (!e.IsSuccess || view.CoreWebView2 == null)
                    {
                        Stamp("Menu music: WebView2 failed to initialise");
                        return;
                    }
                    string uri = new Uri(trackPath).AbsoluteUri.Replace("'", "%27");
                    string html =
                        "<!doctype html><html><body style='background:#000'>" +
                        "<audio id='a' loop preload='auto' src='" + uri + "'></audio>" +
                        "<script>" +
                        "const a=document.getElementById('a');" +
                        "window.chrome.webview.addEventListener('message',ev=>{" +
                        "try{const m=JSON.parse(ev.data);" +
                        "if(m.cmd==='vol')a.volume=Math.max(0,Math.min(1,+m.v||0));" +
                        "if(m.cmd==='play'){a.volume=Math.max(0,Math.min(1,+m.v||0));a.play().catch(()=>{/*ignore*/});}" +
                        "if(m.cmd==='pause')a.pause();" +
                        "}catch(err){/*ignore*/}" +
                        "});" +
                        "a.addEventListener('error',()=>window.chrome.webview.postMessage('err'));" +
                        "a.addEventListener('playing',()=>window.chrome.webview.postMessage('ok'));" +
                        "</script></body></html>";
                    view.CoreWebView2.WebMessageReceived += delegate (
                        object s2,
                        Microsoft.Web.WebView2.Core.CoreWebView2WebMessageReceivedEventArgs a)
                    {
                        try
                        {
                            string msg = a.TryGetWebMessageAsString();
                            if (msg == "err") Stamp("Menu music: HTML5 audio failed for " + trackPath);
                            else if (msg == "ok") Stamp("Menu music: the theme is on (WebView2), from " + trackPath);
                        }
                        catch (Exception ex) { Swallow.Note("MenuMusic.WebMessageReceived", ex); }
                    };
                    view.CoreWebView2.NavigateToString(html);
                    ready = true;
                    Apply();
                }
                catch (Exception ex)
                {
                    Stamp("Menu music: " + ex.Message);
                }
            };

            try
            {
                view.EnsureCoreWebView2Async();
            }
            catch (Exception ex)
            {
                Stamp("Menu music: " + ex.Message);
            }
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
