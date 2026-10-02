using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Thornswood
{
    // The news list page. It lives apart from Shell.cs because it is one
    // self-contained page slice, and Shell.cs was long enough (#500).
    static partial class Shell
    {
        static StackPanel newsList;

        // ------------------------------------------------------------- news
        static void BuildNews()
        {
            newsList.Children.Clear();
            NewsItem[] items = (pendingDoc != null && pendingDoc.news != null) ? pendingDoc.news : new NewsItem[0];

            if (items.Length == 0)
            {
                var empty = new TextBlock();
                empty.Text = "Nothing posted yet. Anything Patrick writes to the update feed turns up here.";
                empty.Foreground = Res("Faint"); empty.FontSize = 12.5;
                empty.TextWrapping = TextWrapping.Wrap;
                newsList.Children.Add(empty);
                return;
            }

            // What this build has that main does not.
            //
            // The dev feed is main's whole history with the dev notes on top,
            // so the tab used to read as one long list with no seam in it. The
            // seam is the useful part: it is the difference between the build
            // in front of you and the build everybody plays, which is the list
            // of what wants testing before this one becomes that one.
            int ahead = 0;
            for (int i = 0; i < items.Length; i++) { if (items[i].IsDev) ahead++; }

            if (cfg.IsDev)
            {
                string mine = (pendingDoc != null) ? pendingDoc.launcherVersion : "";
                string theirs = (pendingDoc != null) ? pendingDoc.mainVersion : "";

                var head = new StackPanel();

                var ht = new TextBlock();
                ht.Text = string.IsNullOrEmpty(theirs)
                    ? "This is the dev build."
                    : "This is the dev build, on " + mine + ". Main is on " + theirs + ".";
                ht.FontSize = 13.5; ht.FontWeight = FontWeights.SemiBold;
                ht.Foreground = Res("Ink"); ht.TextWrapping = TextWrapping.Wrap;
                head.Children.Add(ht);

                var hb = new TextBlock();
                if (ahead == 0)
                {
                    hb.Text = "Nothing below is dev only. Everything here has gone out on main as well, so there is nothing waiting to be tested.";
                }
                else
                {
                    hb.Text = (ahead == 1 ? "One note below is marked DEV. It is" : ahead + " notes below are marked DEV. They are")
                            + " on this build and not on main yet, so that is what wants testing before dev goes over.";
                }
                hb.FontSize = 12; hb.Foreground = Res("Muted");
                hb.TextWrapping = TextWrapping.Wrap; hb.LineHeight = 18;
                hb.Margin = new Thickness(0, 6, 0, 0);
                head.Children.Add(hb);

                var hc = new Border();
                hc.Background = Res("Card");
                hc.BorderBrush = Res("Accent");
                hc.BorderThickness = new Thickness(2, 0, 0, 0);
                hc.Padding = new Thickness(16, 14, 16, 14);
                hc.Margin = new Thickness(0, 0, 0, 24);
                hc.Child = head;
                newsList.Children.Add(hc);
            }

            foreach (NewsItem n in items)
            {
                var sp = new StackPanel();

                if (!string.IsNullOrEmpty(n.DateText) || n.IsDev)
                {
                    var stamp = new StackPanel();
                    stamp.Orientation = Orientation.Horizontal;
                    stamp.Margin = new Thickness(0, 0, 0, 6);

                    if (!string.IsNullOrEmpty(n.DateText))
                    {
                        var d = new TextBlock();
                        d.Text = n.DateText.ToUpperInvariant();
                        d.FontSize = 9.5; d.FontWeight = FontWeights.SemiBold;
                        d.Foreground = Res("Accent");
                        d.VerticalAlignment = VerticalAlignment.Center;
                        stamp.Children.Add(d);
                    }

                    // Only a dev feed ever carries one of these, and inside a
                    // dev feed only the notes main has not had yet.
                    if (n.IsDev)
                    {
                        var ct = new TextBlock();
                        ct.Text = "DEV";
                        ct.FontSize = 8.5; ct.FontWeight = FontWeights.Bold;
                        ct.Foreground = Res("Warn");

                        var chip = new Border();
                        chip.BorderBrush = Res("Warn");
                        chip.BorderThickness = new Thickness(1);
                        chip.CornerRadius = new CornerRadius(3);
                        chip.Padding = new Thickness(5, 1, 5, 1);
                        chip.Margin = new Thickness(string.IsNullOrEmpty(n.DateText) ? 0 : 8, 0, 0, 0);
                        chip.VerticalAlignment = VerticalAlignment.Center;
                        chip.Child = ct;
                        stamp.Children.Add(chip);
                    }

                    sp.Children.Add(stamp);
                }

                var t = new TextBlock();
                t.Text = n.title; t.FontSize = 15; t.FontWeight = FontWeights.SemiBold;
                t.Foreground = Res("Ink"); t.TextWrapping = TextWrapping.Wrap;
                sp.Children.Add(t);

                if (!string.IsNullOrEmpty(n.body))
                {
                    var bd = new TextBlock();
                    bd.Text = n.body; bd.FontSize = 12.5; bd.Foreground = Res("Muted");
                    bd.TextWrapping = TextWrapping.Wrap; bd.LineHeight = 20;
                    bd.Margin = new Thickness(0, 7, 0, 0);
                    sp.Children.Add(bd);
                }

                if (n.details != null && n.details.Length > 0)
                {
                    var box = new StackPanel();
                    box.Margin = new Thickness(0, 12, 0, 0);
                    for (int i = 0; i < n.details.Length; i++)
                    {
                        string line = n.details[i];
                        if (string.IsNullOrEmpty(line)) continue;

                        var row = new StackPanel();
                        row.Orientation = Orientation.Horizontal;
                        row.Margin = new Thickness(0, 0, 0, 4);

                        var dot = new TextBlock();
                        dot.Text = "\u2022";
                        dot.FontSize = 12;
                        dot.Foreground = Res("Accent");
                        dot.Margin = new Thickness(0, 0, 8, 0);
                        row.Children.Add(dot);

                        var dt = new TextBlock();
                        dt.Text = line;
                        dt.FontSize = 11.5;
                        dt.Foreground = Res("Faint");
                        dt.TextWrapping = TextWrapping.Wrap;
                        dt.MaxWidth = 520;
                        row.Children.Add(dt);

                        box.Children.Add(row);
                    }
                    if (box.Children.Count > 0) sp.Children.Add(box);
                }

                if (n.files != null && n.files.Length > 0)
                {
                    var toggle = new Button();
                    toggle.Style = (Style)win.Resources["Ghost"];
                    toggle.Content = "Show the " + n.files.Length + " file" + (n.files.Length == 1 ? "" : "s");
                    toggle.HorizontalAlignment = HorizontalAlignment.Left;
                    toggle.Margin = new Thickness(0, 12, 0, 0);

                    var filesBox = new StackPanel();
                    filesBox.Visibility = Visibility.Collapsed;
                    filesBox.Margin = new Thickness(0, 10, 0, 0);
                    for (int i = 0; i < n.files.Length; i++)
                    {
                        var ft = new TextBlock();
                        ft.Text = n.files[i];
                        ft.FontSize = 10.5;
                        ft.FontFamily = new FontFamily("Cascadia Mono, Consolas");
                        ft.Foreground = Res(n.files[i].StartsWith("- ") ? "Warn" : "Faint");
                        ft.TextWrapping = TextWrapping.Wrap;
                        ft.Margin = new Thickness(0, 0, 0, 2);
                        filesBox.Children.Add(ft);
                    }

                    StackPanel captured = filesBox;
                    Button capturedButton = toggle;
                    string[] capturedFiles = n.files;
                    toggle.Click += delegate
                    {
                        bool open = captured.Visibility == Visibility.Visible;
                        captured.Visibility = open ? Visibility.Collapsed : Visibility.Visible;
                        capturedButton.Content = (open ? "Show the " : "Hide the ") + capturedFiles.Length
                                               + " file" + (capturedFiles.Length == 1 ? "" : "s");
                    };

                    sp.Children.Add(toggle);
                    sp.Children.Add(filesBox);
                }

                var b = new Border();
                b.BorderBrush = Res("Line");
                b.BorderThickness = new Thickness(0, 0, 0, 1);
                b.Padding = new Thickness(0, 0, 0, 20);
                b.Margin = new Thickness(0, 0, 0, 20);
                b.Child = sp;
                newsList.Children.Add(b);
            }
        }
    }
}
