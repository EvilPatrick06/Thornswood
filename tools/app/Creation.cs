using System;
using System.Collections.Generic;
using System.Net;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Thornswood
{
    /// <summary>
    /// Choosing a trade and a town, before the game starts.
    ///
    /// This used to happen inside Skyrim. The server put sixteen books in your
    /// pack, the client resolved each one's form id against its own load order,
    /// drew a message box, and reported back which one you equipped; then the
    /// same again for the town. Fourteen steps, every one able to fail without
    /// printing anything, and all of them resting on the client and the server
    /// numbering their plugins identically. When it broke, which was most of the
    /// time, what you saw was a room with no menus in it.
    ///
    /// None of that is needed to ask somebody two questions. So they are asked
    /// here, where the answer can be checked before anything else happens, and
    /// the choice is left with the voice service for the server to collect. The
    /// books still exist server side as a fallback for a launcher too old to
    /// send anything.
    /// </summary>
    static class Creation
    {
        public class Option
        {
            public string Key;
            public string Label;
            public string Blurb;
            public Option(string k, string l, string b) { Key = k; Label = l; Blurb = b; }
        }

        // The keys match the gamemode's own, which are the stable half of its
        // records: a descriptor carries the plugin name and moves whenever the
        // content is rebuilt, a key does not.
        // The gold is read straight off the gamemode's gear tables, which is
        // the one number worth knowing before you pick and the one that
        // actually differs. The rest describes the work rather than listing
        // items: the kits are built from form ids, and a list written here
        // would be a second copy of them, free to drift and wrong the moment
        // somebody edits the table.
        public static readonly Option[] Trades = new Option[] {
            new Option("warrior",    "Warrior",     "Fighting work. Guarding a shop, walking goods between holds, clearing a cellar out. Starts in iron with 75 gold."),
            new Option("hunter",     "Hunter",      "Meat, hides and horns, which the cooks and tanners buy. Bow and arrows, 75 gold."),
            new Option("mage",       "Mage",        "Spells for hire. Robes, a couple of tomes and soul gems. 75 gold."),
            new Option("smith",      "Smith",       "Weapons, armour and repairs. Starts with ingots and leather to work, and 100 gold."),
            new Option("miner",      "Miner",       "Ore out of the ground, which is what the smiths run on. Pickaxe and 75 gold."),
            new Option("woodworker", "Woodworker",  "Firewood and timber. An axe, work clothes and 75 gold."),
            new Option("alchemist",  "Alchemist",   "Potions and poisons. Starts with a full satchel of ingredients and 75 gold."),
            new Option("bard",       "Bard",        "Playing the inns for coin. Starts with a lute, a flute and a drum, good clothes and 200 gold, second most of any trade."),
            new Option("cook",       "Cook",        "Cooked food, with a week of stock to sell on day one. 75 gold."),
            new Option("enchanter",  "Enchanter",   "Putting enchantments on other people's gear. Starts with six soul gems and 75 gold."),
            new Option("farmer",     "Farmer",      "Crops and produce, which feeds everyone else. Tools, food and 75 gold."),
            new Option("fisher",     "Fisher",      "Fish from the lakes and the coast. Starts with a rod, a net and a filleting kit, work clothes, a catch to sell and 75 gold."),
            new Option("merchant",   "Merchant",    "Buying and selling whatever moves. 400 gold, by far the most, fine clothes to be taken seriously in, and an amulet of Zenithar."),
            new Option("priest",     "Priest",      "Healing and rites. Vestments, amulets of Arkay and Mara, cure disease and 75 gold."),
            new Option("scholar",    "Scholar",     "Books, research and writing for hire. Robes, tomes and 75 gold."),
            new Option("thief",      "Thief",       "Locks and pockets. Leather, fifteen lockpicks and 75 gold."),
        };

        // Each one names the inn you actually wake up in, because that is where
        // the server puts you and it is the thing you will be looking for.
        //
        // Raven Rock is deliberately not here. It is on Solstheim, across the
        // sea, with no road to the mainland, and somebody starting there is cut
        // off from everybody else on their first day.
        public static readonly Option[] Towns = new Option[] {
            new Option("whiterun",   "Whiterun",    "Middle of Skyrim, on the plains. You wake in the Bannered Mare. Busiest roads and the shortest trip to anywhere else."),
            new Option("riften",     "Riften",      "The Rift, south east. The Bee and Barb. Built on wood over the lake, with the Thieves Guild underneath it."),
            new Option("solitude",   "Solitude",    "Haafingar, north west. The Winking Skeever. The capital, the docks and the Empire's seat."),
            new Option("windhelm",   "Windhelm",    "Eastmarch, north east. Candlehearth Hall. The oldest city in Skyrim and the coldest."),
            new Option("markarth",   "Markarth",    "The Reach, west. The Silver-Blood Inn. Dwemer stone, silver money and the Forsworn outside the gates."),
            new Option("falkreath",  "Falkreath",   "Falkreath Hold, south. Dead Man's Drink. Pine forest, lumber and a very large graveyard."),
            new Option("morthal",    "Morthal",     "Hjaalmarch, north. Moorside Inn. Small, quiet and built on a swamp. Few customers."),
            new Option("dawnstar",   "Dawnstar",    "The Pale, north coast. The Windpeak Inn. A mining town on the ice, so ore is close."),
            new Option("winterhold", "Winterhold",  "Far north east. The Frozen Hearth. Four houses left and the College of Winterhold."),
        };

        /// <summary>
        /// The label for a key, or empty when nothing matches.
        ///
        /// The gamemode and the roster both speak in keys, because a key is the
        /// stable half of a record: a descriptor carries the plugin name and
        /// moves whenever the content is rebuilt. Nobody wants to read "smith"
        /// on a card, so the two lists above are also the one place a key turns
        /// back into a word.
        /// </summary>
        public static string LabelOf(Option[] list, string key)
        {
            if (list == null || string.IsNullOrEmpty(key)) return "";
            foreach (Option o in list)
            {
                if (string.Equals(o.Key, key, StringComparison.OrdinalIgnoreCase)) return o.Label;
            }
            return "";
        }

        /// <summary>
        /// Shows the two questions. Returns false when the person backed out,
        /// in which case nothing at all should happen: no slot claimed, no game
        /// started.
        /// </summary>
        /// <summary>
        /// Shows the two questions. Returns false when the person backed out,
        /// in which case nothing at all should happen: no slot claimed, no game
        /// started.
        ///
        /// Built out of the launcher's own brushes and styles rather than
        /// stock WPF controls. A ListBox draws itself white whatever you set
        /// its background to, because the white is on the item template, not
        /// the box; and a Window with normal chrome gets whatever title bar
        /// colour Windows feels like. Both of those landed in the middle of a
        /// dark launcher looking like a different program.
        /// </summary>
        public static bool Ask(Window owner, string who, out string trade, out string town)
        {
            trade = null;
            town = null;

            var dlg = new Window();
            dlg.Owner = owner;
            dlg.WindowStyle = WindowStyle.None;
            dlg.WindowStartupLocation = WindowStartupLocation.CenterOwner;
            dlg.ResizeMode = ResizeMode.NoResize;
            dlg.ShowInTaskbar = false;
            dlg.Width = 820;
            dlg.Height = 600;
            dlg.Background = Brushes.Transparent;
            dlg.AllowsTransparency = true;

            // The theme lives in the main window's resources and the themes are
            // swapped there at runtime, so borrowing the dictionary is what
            // makes this follow whichever one is on.
            dlg.Resources = owner.Resources;

            var shell = new Border();
            shell.Background = B(owner, "Bg", Brushes.Black);
            shell.BorderBrush = B(owner, "Line", Brushes.DimGray);
            shell.BorderThickness = new Thickness(1);

            var rows = new Grid();
            rows.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            rows.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            shell.Child = rows;
            dlg.Content = shell;

            // ------------------------------------------------------- title --
            var bar = new Border();
            bar.Background = B(owner, "Panel", Brushes.Black);
            bar.Height = 38;
            var barRow = new Grid();
            var barText = new TextBlock();
            barText.Text = "THORNSWOOD";
            barText.FontSize = 11;
            barText.Margin = new Thickness(16, 0, 0, 0);
            barText.VerticalAlignment = VerticalAlignment.Center;
            barText.Foreground = B(owner, "Faint", Brushes.Gray);
            try { barText.SetValue(TextBlock.FontFamilyProperty, new FontFamily("Segoe UI")); } catch { }
            barRow.Children.Add(barText);
            bar.Child = barRow;
            bar.MouseLeftButtonDown += delegate { try { dlg.DragMove(); } catch { } };
            Grid.SetRow(bar, 0);
            rows.Children.Add(bar);

            // -------------------------------------------------------- body --
            var root = new Grid();
            root.Margin = new Thickness(26, 20, 26, 22);
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            Grid.SetRow(root, 1);
            rows.Children.Add(root);

            var head = new StackPanel();
            var h1 = new TextBlock();
            h1.Text = string.IsNullOrEmpty(who) ? "A new character" : who;
            h1.FontSize = 22;
            h1.FontWeight = FontWeights.SemiBold;
            h1.Foreground = B(owner, "Ink", Brushes.White);
            head.Children.Add(h1);

            var h2 = new TextBlock();
            h2.Text = "What you did before, and where you are starting. Your face is chosen in the game, once it loads.";
            h2.Margin = new Thickness(0, 5, 0, 16);
            h2.TextWrapping = TextWrapping.Wrap;
            h2.FontSize = 12.5;
            h2.Foreground = B(owner, "Muted", Brushes.Gray);
            head.Children.Add(h2);
            Grid.SetRow(head, 0);
            root.Children.Add(head);

            var cols = new Grid();
            cols.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            cols.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
            cols.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetRow(cols, 1);
            root.Children.Add(cols);

            var tradePicks = new List<Pick>();
            var townPicks = new List<Pick>();
            Column(cols, 0, "Starter class", Trades, owner, tradePicks);
            Column(cols, 2, "Starter location", Towns, owner, townPicks);

            // ------------------------------------------------------- footer --
            var foot = new Grid();
            foot.Margin = new Thickness(0, 18, 0, 0);
            foot.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            foot.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var warn = new TextBlock();
            warn.VerticalAlignment = VerticalAlignment.Center;
            warn.FontSize = 12.5;
            warn.Foreground = B(owner, "Warn", Brushes.Goldenrod);
            Grid.SetColumn(warn, 0);
            foot.Children.Add(warn);

            var buttons = new StackPanel();
            buttons.Orientation = Orientation.Horizontal;
            buttons.HorizontalAlignment = HorizontalAlignment.Right;

            var cancel = new Button();
            cancel.Content = "Back";
            cancel.Margin = new Thickness(0, 0, 8, 0);
            try { cancel.Style = (Style)owner.FindResource("Ghost"); } catch { }

            var ok = new Button();
            ok.Content = "Start";
            try { ok.Style = (Style)owner.FindResource("Solid"); } catch { }

            buttons.Children.Add(cancel);
            buttons.Children.Add(ok);
            Grid.SetColumn(buttons, 1);
            foot.Children.Add(buttons);
            Grid.SetRow(foot, 2);
            root.Children.Add(foot);

            bool done = false;
            cancel.Click += delegate { dlg.Close(); };
            dlg.KeyDown += delegate(object sender, System.Windows.Input.KeyEventArgs e)
            {
                if (e.Key == System.Windows.Input.Key.Escape) dlg.Close();
            };
            ok.Click += delegate
            {
                if (Chosen(tradePicks) == null || Chosen(townPicks) == null)
                {
                    warn.Text = "Pick one of each.";
                    return;
                }
                done = true;
                dlg.Close();
            };

            dlg.ShowDialog();
            if (!done) return false;

            trade = Chosen(tradePicks);
            town = Chosen(townPicks);
            return trade != null && town != null;
        }

        class Pick
        {
            public Option O;
            public Border Card;
            public bool On;
        }

        static string Chosen(List<Pick> picks)
        {
            foreach (Pick p in picks) { if (p.On) return p.O.Key; }
            return null;
        }

        static Brush B(Window owner, string key, Brush fallback)
        {
            try
            {
                var b = owner.FindResource(key) as Brush;
                return b == null ? fallback : b;
            }
            catch { return fallback; }
        }

        static void Column(Grid parent, int col, string heading, Option[] items,
                           Window owner, List<Pick> picks)
        {
            var stack = new StackPanel();

            var lbl = new TextBlock();
            lbl.Text = heading.ToUpperInvariant();
            lbl.FontSize = 11;
            lbl.Margin = new Thickness(2, 0, 0, 8);
            lbl.Foreground = B(owner, "Faint", Brushes.Gray);
            stack.Children.Add(lbl);

            var frame = new Border();
            frame.Background = B(owner, "Deep", Brushes.Black);
            frame.BorderBrush = B(owner, "Line", Brushes.DimGray);
            frame.BorderThickness = new Thickness(1);
            frame.Height = 352;

            var scroll = new ScrollViewer();
            scroll.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            scroll.HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
            scroll.Padding = new Thickness(7);
            frame.Child = scroll;

            var list = new StackPanel();
            scroll.Content = list;

            Brush card = B(owner, "Card", Brushes.Black);
            Brush hover = B(owner, "CardHover", Brushes.Black);
            Brush line = B(owner, "Line", Brushes.DimGray);
            Brush accent = B(owner, "Accent", Brushes.Orange);
            Brush soft = B(owner, "AccentSoft", Brushes.Transparent);
            Brush ink = B(owner, "Ink", Brushes.White);
            Brush muted = B(owner, "Muted", Brushes.Gray);

            foreach (Option o in items)
            {
                var pick = new Pick();
                pick.O = o;

                var box = new Border();
                box.Background = card;
                box.BorderBrush = line;
                box.BorderThickness = new Thickness(1);
                box.CornerRadius = new CornerRadius(4);
                box.Padding = new Thickness(11, 9, 11, 9);
                box.Margin = new Thickness(0, 0, 0, 6);
                box.Cursor = System.Windows.Input.Cursors.Hand;

                var sp = new StackPanel();

                var name = new TextBlock();
                name.Text = o.Label;
                name.FontSize = 14.5;
                name.Foreground = ink;
                sp.Children.Add(name);

                var blurb = new TextBlock();
                blurb.Text = o.Blurb;
                blurb.FontSize = 11.5;
                blurb.TextWrapping = TextWrapping.Wrap;
                blurb.Margin = new Thickness(0, 2, 0, 0);
                blurb.Foreground = muted;
                sp.Children.Add(blurb);

                box.Child = sp;
                pick.Card = box;
                picks.Add(pick);

                box.MouseEnter += delegate { if (!pick.On) box.Background = hover; };
                box.MouseLeave += delegate { if (!pick.On) box.Background = card; };
                box.MouseLeftButtonDown += delegate
                {
                    foreach (Pick other in picks)
                    {
                        other.On = false;
                        other.Card.Background = card;
                        other.Card.BorderBrush = line;
                    }
                    pick.On = true;
                    box.Background = soft;
                    box.BorderBrush = accent;
                };

                list.Children.Add(box);
            }

            stack.Children.Add(frame);
            Grid.SetColumn(stack, col);
            parent.Children.Add(stack);
        }

        /// <summary>
        /// Leaves the choice where the server will find it.
        ///
        /// The voice service is the only thing both sides can reach: this over
        /// the internet, the gamemode over loopback on the same box. Returns
        /// null when it worked, or why it did not.
        ///
        /// A failure here is not fatal. The server still has the books, so
        /// somebody whose choice never arrived gets the old flow rather than
        /// nothing at all.
        /// </summary>
        public static string Send(Config cfg, int profileId, string trade, string town, string name)
        {
            if (profileId <= 0) return "no profile id";
            if (string.IsNullOrEmpty(cfg.ServerAddress)) return "no server address";

            int port = 7778;
            int.TryParse(cfg.VoicePort, out port);
            if (port <= 0) port = 7778;

            string url = "http://" + cfg.ServerAddress + ":" + port + "/choose";
            string body = "{\"profileId\":" + profileId +
                          ",\"trade\":\"" + Esc(trade) + "\"" +
                          ",\"town\":\"" + Esc(town) + "\"" +
                          ",\"name\":\"" + Esc(name) + "\"}";

            try
            {
                var req = (HttpWebRequest)WebRequest.Create(url);
                req.Method = "POST";
                req.ContentType = "application/json";
                req.Timeout = 5000;
                req.ReadWriteTimeout = 5000;
                byte[] raw = Encoding.UTF8.GetBytes(body);
                req.ContentLength = raw.Length;
                using (var s = req.GetRequestStream()) { s.Write(raw, 0, raw.Length); }
                using (var resp = (HttpWebResponse)req.GetResponse())
                {
                    int code = (int)resp.StatusCode;
                    if (code >= 200 && code < 300) return null;
                    return "the server answered " + code;
                }
            }
            catch (Exception ex) { return ex.Message; }
        }

        static string Esc(string s)
        {
            if (s == null) return "";
            var sb = new StringBuilder();
            foreach (char c in s)
            {
                if (c == '"' || c == '\\') { sb.Append('\\').Append(c); }
                else if (c >= ' ') { sb.Append(c); }
            }
            return sb.ToString();
        }
    }
}
