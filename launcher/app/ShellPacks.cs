using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using System.Windows;
using System.Windows.Controls;

namespace Thornswood
{
    // The add-on rows and the collection card that names where the mods
    // come from. They live apart from Shell.cs because they are one
    // self-contained page slice, and Shell.cs was long enough (#500). Both
    // are drawn on Diagnostics, since nothing opens the Mods page (#1170).
    static partial class Shell
    {
        // Ids being installed or removed right now, so a second click on the
        // same row does not start the same download twice.
        static readonly List<string> packBusy = new List<string>();

        /// <summary>
        /// The add-ons tab. One row per optional pack, with a button that says
        /// what it will do.
        ///
        /// The list comes from the same version.json the update check already
        /// reads, so there is nothing extra to fetch and no second source that
        /// can disagree with the first.
        /// </summary>
        static void BuildPackRows()
        {
            // The mods do not come with the installer any more, so this is the
            // only thing in the launcher that tells anybody where they do come
            // from. It goes above the add-on list and shows whether or not the
            // add-ons have loaded, because somebody whose world looks like
            // plain Skyrim needs to read it before anything else.
            // BuildModList puts the card above every sub tab now, so adding it
            // here again would show it twice on this one.
            var have = pendingDoc == null ? null : pendingDoc.optional;

            if (have == null)
            {
                txtModCount.Text = "Add-ons load with the update check. Press " +
                                   "Check for add-ons above.";
                return;
            }

            string filter = (boxSearch.Text == SearchHint) ? "" : boxSearch.Text.Trim().ToLowerInvariant();
            int total = 0, shown = 0, on = 0;
            long free = 0;

            foreach (var p in have)
            {
                if (p == null || string.IsNullOrEmpty(p.id)) continue;
                total++;
                bool installed = Updater.IsInstalled(p.id);
                if (installed) on++; else free += p.bytes;
                if (filter.Length > 0 && p.Title.ToLowerInvariant().IndexOf(filter) < 0) continue;
                modList.Children.Add(PackRow(p, installed));
                shown++;
            }

            if (total == 0)
            {
                txtModCount.Text = "No add-ons published yet.";
                return;
            }

            txtModCount.Text = total + " add-on" + (total == 1 ? "" : "s") + "   ·   " +
                               on + " installed" +
                               (free > 0 ? "   ·   " + Bytes(free) + " more available" : "") +
                               (filter.Length > 0 ? "   ·   showing " + shown : "");

            if (shown == 0 && filter.Length > 0)
            {
                var none = new TextBlock();
                none.Text = "Nothing matches \"" + filter + "\".";
                none.Foreground = Res("Faint"); none.FontSize = 12.5;
                none.Margin = new Thickness(2, 10, 0, 0);
                modList.Children.Add(none);
            }
        }

        /// <summary>
        /// The optional packs on the Diagnostics page, under the collection
        /// card (#1170). Their only home was the Add-ons tab of the Mods page,
        /// and nothing has opened that page since #599 took it off the rail,
        /// so a published pack could not be installed from the launcher.
        ///
        /// The same rows, buttons and version.json list as that tab, so the
        /// two cannot disagree. Nothing is drawn until the feed lists a pack,
        /// which is before the update check answers and whenever none is
        /// published: a heading with nothing under it, on the page people
        /// open when something is wrong, reads as one more thing wrong.
        /// </summary>
        static void DrawAddons()
        {
            if (diagAddons == null) return;
            diagAddons.Children.Clear();

            var have = pendingDoc == null ? null : pendingDoc.optional;
            if (have == null) return;

            var rows = new List<UIElement>();
            foreach (var p in have)
            {
                if (p == null || string.IsNullOrEmpty(p.id)) continue;
                rows.Add(PackRow(p, Updater.IsInstalled(p.id)));
            }
            if (rows.Count == 0) return;

            var head = new TextBlock();
            head.Text = "Add-ons";
            head.Style = win.Resources["Eyebrow"] as Style;
            head.Margin = new Thickness(0, 22, 0, 11);
            diagAddons.Children.Add(head);

            var about = new TextBlock();
            about.Text = "Extras you can have if you want them and skip if you do not. " +
                         "These are textures, meshes, weather and shaders, never a plugin, " +
                         "which is why they are safe: the server compares plugin lists and " +
                         "never looks at anything in here. Nobody is at a disadvantage for " +
                         "leaving them off.";
            about.Style = win.Resources["Body"] as Style;
            about.Margin = new Thickness(0, 0, 8, 12);
            diagAddons.Children.Add(about);

            foreach (UIElement r in rows) diagAddons.Children.Add(r);
        }

        static string Bytes(long n)
        {
            if (n >= 1073741824L) return (n / 1073741824.0).ToString("0.0") + " GB";
            if (n >= 1048576L) return (n / 1048576.0).ToString("0") + " MB";
            return (n / 1024.0).ToString("0") + " KB";
        }

        static UIElement PackRow(Pack p, bool installed)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var left = new StackPanel();
            Grid.SetColumn(left, 0); g.Children.Add(left);

            var name = new TextBlock();
            name.Text = p.Title;
            name.FontSize = 13.5;
            name.Foreground = Res("Ink");
            name.TextTrimming = TextTrimming.CharacterEllipsis;
            left.Children.Add(name);

            var note = new TextBlock();
            string size = p.Size;
            string body = p.notes == null ? "" : p.notes.Trim();
            note.Text = (size.Length > 0 ? size : "") +
                        (size.Length > 0 && body.Length > 0 ? "   ·   " : "") + body;
            note.FontSize = 11.5;
            note.Foreground = Res(installed ? "Muted" : "Faint");
            note.TextWrapping = TextWrapping.Wrap;
            note.Margin = new Thickness(0, 3, 12, 0);
            if (note.Text.Length > 0) left.Children.Add(note);

            var b = new Button();
            bool busy = packBusy.Contains(p.id);
            b.Content = busy ? "Working..." : (installed ? "Remove" : "Install");
            b.Style = (Style)win.Resources[installed ? "Ghost" : "Solid"];
            b.IsEnabled = !busy;
            b.VerticalAlignment = VerticalAlignment.Center;
            b.MinWidth = 96;
            Grid.SetColumn(b, 1); g.Children.Add(b);

            // C# 4 closures capture the loop variable itself, so the pack has
            // to be copied to a local before the handler can be trusted.
            Pack mine = p;
            bool wasOn = installed;
            b.Click += delegate { PackAction(mine, wasOn); };

            var card = new Border();
            card.Padding = new Thickness(14, 12, 14, 12);
            card.Background = Res("Panel");
            card.Margin = new Thickness(0, 0, 8, 4);
            card.Child = g;
            return card;
        }

        /// <summary>
        /// Where the mods come from, and a way to get there.
        ///
        /// Built here rather than in ui.xaml on purpose: a named control the
        /// C# looks up and the xaml does not have comes back null and takes
        /// the whole page with it, and this is the one row that must not be
        /// the thing that breaks.
        /// </summary>
        static UIElement CollectionCard()
        {
            return CollectionCard("The mods",
                "Thornswood's mods are installed by Vortex from the collection, " +
                "not by this launcher. If the world looks like plain Skyrim, or " +
                "the server turns you away when you press Play, the collection is " +
                "what is missing.");
        }

        /// <summary>
        /// The collection card for the Diagnostics page (Djinn, 2 Oct): the
        /// same card and button as the Mods page's, saying what the launcher
        /// found. Since #599 took the Mods page off the rail, its card was the
        /// only way to the collection and nobody could reach it.
        /// </summary>
        static UIElement CollectionStatusCard()
        {
            int have = 0;
            try { have = Checks.CollectionRevision(cfg); }
            catch (Exception ex) { Swallow.Note("Shell.CollectionStatusCard", ex); }
            int wants = Updater.FeedCollectionRevision;
            if (have <= 0)
                return CollectionCard("Your mods: not confirmed",
                    "The launcher could not read which revision of the Thornswood collection " +
                    "Vortex has installed, so it cannot confirm your mods. If you have not " +
                    "installed the collection, or are not sure, open it and let Vortex install " +
                    "or update it.");
            if (wants > 0 && have < wants)
                return CollectionCard("Your mods need updating",
                    "Vortex has collection revision " + have + " and the server was built against " +
                    "revision " + wants + ". Open the collection and let Vortex bring it up to date.");
            if (wants > 0 && have > wants)
                return CollectionCard("Your mods are ahead of the server",
                    "Vortex has collection revision " + have + " and the server was built against " +
                    "revision " + wants + ". Nothing is wrong with your install; the server has " +
                    "not caught up yet.");
            return CollectionCard("Your mods: collection revision " + have,
                "Vortex has the Thornswood collection installed" +
                (wants > 0 ? ", the same revision the server was built against."
                           : ". The server's revision was not known just now, so it was not compared."));
        }

        static UIElement CollectionCard(string title, string body)
        {
            var g = new Grid();
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var left = new StackPanel();
            Grid.SetColumn(left, 0); g.Children.Add(left);

            var name = new TextBlock();
            name.Text = title;
            name.FontSize = 13.5;
            name.Foreground = Res("Ink");
            left.Children.Add(name);

            var note = new TextBlock();
            note.Text = body;
            note.FontSize = 11.5;
            note.Foreground = Res("Faint");
            note.TextWrapping = TextWrapping.Wrap;
            note.Margin = new Thickness(0, 3, 12, 0);
            left.Children.Add(note);

            var b = new Button();
            b.Content = "Open the collection";
            b.Style = (Style)win.Resources["Solid"];
            b.VerticalAlignment = VerticalAlignment.Center;
            b.MinWidth = 96;
            Grid.SetColumn(b, 1); g.Children.Add(b);

            string url = cfg.CollectionUrl;
            b.Click += delegate
            {
                try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); }
                catch (Exception ex) { Log("Could not open the collection: " + ex.Message); }
            };

            // Open to everybody (#428): anyone can download in the alpha, and
            // the same link is on the public Downloads page. It used to say
            // "Apply first" until Discord was linked, which kept nothing from
            // anybody. The application in the Discord unlocks Play, not this.

            var card = new Border();
            card.Padding = new Thickness(14, 12, 14, 12);
            card.Background = Res("Panel");
            card.Margin = new Thickness(0, 0, 8, 10);
            card.Child = g;
            return card;
        }

        static void PackAction(Pack p, bool installed)
        {
            if (p == null || packBusy.Contains(p.id)) return;

            if (Checks.GameRunning())
            {
                Log("Close Skyrim first. Files it has open cannot be changed.");
                return;
            }

            packBusy.Add(p.id);
            BuildModList();
            DrawAddons();

            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    // An add-on writes into the game folder and Profile\Packs,
                    // which a refresh reads, so one writer at a time (#2210).
                    OwnGame.Alone(delegate
                    {
                        if (installed) Updater.RemovePack(cfg, p, SafeLog);
                        else Updater.ApplyPack(cfg, p, SafeLog);
                    }, delegate { SafeLog("The game folder is being prepared or updated. " + p.Title + " goes " + (installed ? "out" : "in") + " as soon as that is done."); });
                }
                catch (Exception ex)
                {
                    SafeLog((installed ? "Could not remove " : "Could not install ") +
                            p.Title + ": " + ex.Message);
                }
                finally
                {
                    win.Dispatcher.BeginInvoke(new Action(delegate
                    {
                        packBusy.Remove(p.id);
                        BuildModList();
                        DrawAddons();
                        DrawStatus();
                    }));
                }
            });
        }

    }
}
