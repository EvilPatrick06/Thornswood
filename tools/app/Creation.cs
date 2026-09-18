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
        /// <summary>A profession and the two halves of it you must pick between.</summary>
        public class Trade
        {
            public Option O;
            public Option[] Halves;
            public int Pick;          // how many halves to choose, 1 normally, 2 for the mage
            public bool NoKit;        // no starter kit in the content yet
            public Trade(Option o, int pick, bool noKit, params Option[] halves)
            { O = o; Pick = pick; NoKit = noKit; Halves = halves; }
        }

        /*
          Three choices now instead of one, and they do different jobs.

            Profession   what you make, or how you fight
            Half         which side of it you are able to do at all
            Class        where raw material comes from

          The key sent to the server is still the PROFESSION's, because the
          starter kits are form ids in Thornswood-Content.esp keyed by that and
          nothing else. Tailor and Gatherer have no kit yet, which is said on
          the card rather than left to be discovered on the first morning.

          The class does not fire a kit either. A smith who mines starts with a
          smith's kit and no pickaxe until the kits carry tools for the class as
          well as the profession.
        */
        public static readonly Trade[] Professions = new Trade[] {
            new Trade(new Option("warrior", "Warrior",
                "Fighting work. Guarding a shop, walking goods between holds, clearing a cellar out. Starts in iron with 75 gold."), 1, false,
                new Option("tank",    "Bulwark",      "You are what stands between it and everybody else. Shields, heavy plate, holding a doorway."),
                new Option("brawler", "Berserker",    "You are what it has to deal with. Two weapons, or none, and getting there first.")),

            new Trade(new Option("mage", "Mage",
                "Spells for hire. Robes, a couple of tomes and soul gems. 75 gold."), 2, false,
                new Option("destruction",  "Destruction",  "Fire, frost and shock. The loud one."),
                new Option("restoration",  "Restoration",  "Healing, wards, and turning what should not be walking."),
                new Option("alteration",   "Alteration",   "Armour out of nothing, water breathing, and opening what is shut."),
                new Option("illusion",     "Illusion",     "Fear, calm, fury and not being seen."),
                new Option("conjuration",  "Conjuration",  "Calling things up, and binding a weapon out of air.")),

            new Trade(new Option("alchemist", "Alchemist",
                "Potions and poisons. Starts with a full satchel of ingredients and 75 gold."), 1, false,
                new Option("harm",    "Blightbrewer", "What goes on a blade. Damage, paralysis, lingering things."),
                new Option("mend",    "Physicker",    "What goes in a cup. Healing, cures, stamina, keeping people upright.")),

            new Trade(new Option("cook", "Cook",
                "Cooked food, with a week of stock to sell on day one. 75 gold."), 1, false,
                new Option("dinner",  "Hearthcook",   "Stews, roasts, soups. What a hold eats after a day's work."),
                new Option("dessert", "Confectioner", "Sweet rolls, pies, honey. What people buy when they are already fed.")),

            new Trade(new Option("smith", "Smith",
                "Weapons, armour and repairs. Starts with ingots and leather to work, and 100 gold."), 1, false,
                new Option("armour",  "Platewright",  "Cuirasses, helms, shields. You cannot make a sword."),
                new Option("weapons", "Edgewright",   "Blades, axes, bows. You cannot make a cuirass.")),

            new Trade(new Option("enchanter", "Enchanter",
                "Putting enchantments on other people's gear. Starts with six soul gems and 75 gold."), 1, false,
                new Option("weapon",  "Bladebinder",  "What a blade does when it lands."),
                new Option("apparel", "Wardweaver",   "What a person walks around wearing.")),

            new Trade(new Option("tailor", "Tailor",
                "Cloth rather than steel. No starter kit built yet, so you begin with only what everybody gets."), 1, true,
                new Option("robes",  "Liverywright", "Mage robes, temple vestments, what a guild wants its people seen in."),
                new Option("common", "Haberdasher",  "What everybody wears, and what the ones with money wear.")),
        };

        /// <summary>
        /// The professions as a flat list of Options.
        ///
        /// Two places turn a saved trade key back into a label for display, and
        /// neither cares about halves. Renaming the old array away broke the
        /// build in exactly those two places, so the name stays.
        /// </summary>
        public static Option[] Trades { get { return ToOptions(Professions); } }

        /// <summary>
        /// Where raw material comes from. Each one owns a verb that nobody else
        /// in the game has.
        ///
        /// A class carries no starter kit and is not meant to. The kit comes
        /// from the profession, and the tool comes from the world: a miner buys
        /// or is given a pickaxe like anybody else would have to. Handing one
        /// out at creation would make the class a bag of items rather than a
        /// thing only you can do.
        /// </summary>
        public static readonly Option[] Classes = new Option[] {
            new Option("hunter",   "Hunter",   "The only one who can loot an animal body. Everybody else walks past the carcass and gets nothing."),
            new Option("fisher",   "Fisher",   "The only one who can fish. Every cook and every alchemist eventually needs one of you."),
            new Option("miner",    "Miner",    "The only one who can mine. Ore is what every smith in Skyrim runs on."),
            new Option("farmer",   "Farmer",   "The only one who can farm. Crops feed the cooks, and the cooks feed everybody."),
            new Option("gatherer", "Gatherer", "The only one who can gather material out of the world. Flowers, fungus, wood, reagents."),
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
            string half, cls;
            return Ask(owner, who, out trade, out half, out cls, out town);
        }

        public static bool Ask(Window owner, string who, out string trade,
                               out string half, out string cls, out string town)
        {
            trade = null;
            half = null;
            cls = null;
            town = null;

            // In the launcher window rather than a window of its own, when the
            // XAML has somewhere to put it. A second top level window is a
            // second thing to alt tab past, it opens wherever Windows decides,
            // and anybody capturing the launcher window on a stream loses the
            // whole of character creation off the side of their capture.
            //
            // The separate window is kept as a fallback so an older ui.xaml,
            // or one somebody has edited, still gets a working dialog.
            Grid overlay = null; Border host = null;
            try
            {
                overlay = owner.FindName("Overlay") as Grid;
                host    = owner.FindName("OverlayHost") as Border;
            }
            catch { }
            bool inWindow = overlay != null && host != null;

            Window dlg = null;
            if (!inWindow)
            {
                dlg = new Window();
                dlg.Owner = owner;
                dlg.WindowStyle = WindowStyle.None;
                dlg.WindowStartupLocation = WindowStartupLocation.CenterOwner;
                dlg.ResizeMode = ResizeMode.NoResize;
                dlg.ShowInTaskbar = false;
                // Four columns now rather than two, so it needs the room.
                // Still inside 1280 wide, the smallest screen anybody here has.
                dlg.Width = 1180;
                dlg.Height = 640;
                dlg.Background = Brushes.Transparent;
                dlg.AllowsTransparency = true;

                // The theme lives in the main window's resources and is swapped
                // there at runtime, so borrowing the dictionary is what makes
                // this follow whichever one is on.
                dlg.Resources = owner.Resources;
            }

            var shell = new Border();
            shell.Background = B(owner, "Bg", Brushes.Black);
            shell.BorderBrush = B(owner, "Line", Brushes.DimGray);
            shell.BorderThickness = new Thickness(1);

            var rows = new Grid();
            rows.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            rows.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            shell.Child = rows;

            // Bounded rather than fixed, because the launcher can be as small
            // as 1020 by 670 and a 1180 wide panel inside that would have its
            // last column off the edge.
            shell.MaxWidth = 1180;
            shell.MaxHeight = 660;
            shell.HorizontalAlignment = HorizontalAlignment.Center;
            shell.VerticalAlignment = VerticalAlignment.Center;
            shell.Margin = new Thickness(14);
            if (!inWindow) dlg.Content = shell;

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
            for (int c = 0; c < 7; c++)
            {
                cols.ColumnDefinitions.Add(new ColumnDefinition {
                    Width = (c % 2 == 1) ? new GridLength(14) : new GridLength(1, GridUnitType.Star) });
            }
            Grid.SetRow(cols, 1);
            root.Children.Add(cols);

            var tradePicks = new List<Pick>();
            var halfPicks  = new List<Pick>();
            var classPicks = new List<Pick>();
            var townPicks  = new List<Pick>();

            // The halves column is empty until a profession is picked, and is
            // rebuilt every time one is. Built first so the profession column's
            // handler has something to fill.
            StackPanel halfCol;
            var halfHost = Column(cols, 2, "Which half", new Option[0], owner, halfPicks,
                                  1, null, null, out halfCol);

            var halfLabel = new TextBlock();
            halfLabel.FontSize = 11.5;
            halfLabel.TextWrapping = TextWrapping.Wrap;
            halfLabel.Margin = new Thickness(2, 7, 0, 0);
            halfLabel.Foreground = B(owner, "Faint", Brushes.Gray);
            halfLabel.Text = "Pick a profession first.";
            // Under the halves column, which is the only place it means anything.
            if (halfCol != null) halfCol.Children.Add(halfLabel);

            Trade[] prof = { null };

            Action rebuildHalves = delegate
            {
                string key = Chosen(tradePicks);
                prof[0] = null;
                foreach (Trade t in Professions) if (t.O.Key == key) prof[0] = t;
                if (prof[0] == null)
                {
                    halfHost.Children.Clear();
                    halfPicks.Clear();
                    halfLabel.Text = "Pick a profession first.";
                    return;
                }
                Column(cols, 2, "Which half", prof[0].Halves, owner, halfPicks,
                       prof[0].Pick, halfHost, null);
                halfLabel.Text = prof[0].Pick > 1
                    ? "Pick " + prof[0].Pick + ". Both from one school is allowed, and leaves the other one to come back to."
                    : "Pick one. It decides what you are able to make at all, not what you are better at.";
            };

            Column(cols, 0, "Profession", ToOptions(Professions), owner, tradePicks, 1, null, rebuildHalves);
            Column(cols, 4, "Class", Classes, owner, classPicks);
            Column(cols, 6, "Where you wake up", Towns, owner, townPicks);

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

            // A nested dispatcher frame is what ShowDialog does underneath, so
            // Ask still blocks and returns a bool and every caller is unchanged.
            var frame = new System.Windows.Threading.DispatcherFrame();
            System.Windows.Input.KeyEventHandler esc = null;
            Action shut = delegate
            {
                if (inWindow)
                {
                    if (esc != null) owner.PreviewKeyDown -= esc;
                    overlay.Visibility = Visibility.Collapsed;
                    host.Child = null;
                    frame.Continue = false;
                }
                else dlg.Close();
            };

            cancel.Click += delegate { shut(); };
            esc = delegate(object sender, System.Windows.Input.KeyEventArgs e)
            {
                if (e.Key == System.Windows.Input.Key.Escape) shut();
            };
            if (inWindow) owner.PreviewKeyDown += esc;
            else dlg.KeyDown += esc;
            ok.Click += delegate
            {
                if (Chosen(tradePicks) == null) { warn.Text = "Pick a profession."; return; }
                int need = prof[0] == null ? 1 : prof[0].Pick;
                if (AllChosen(halfPicks).Count != need)
                {
                    warn.Text = need > 1
                        ? "Pick " + need + " in the second column."
                        : "Pick which half of it you do.";
                    return;
                }
                if (Chosen(classPicks) == null) { warn.Text = "Pick a class. It is where your material comes from."; return; }
                if (Chosen(townPicks) == null)  { warn.Text = "Pick where you wake up."; return; }
                done = true;
                shut();
            };

            if (inWindow)
            {
                host.Child = shell;
                overlay.Visibility = Visibility.Visible;
                System.Windows.Threading.Dispatcher.PushFrame(frame);
            }
            else dlg.ShowDialog();
            if (!done) return false;

            trade = Chosen(tradePicks);
            half  = string.Join("+", AllChosen(halfPicks).ToArray());
            cls   = Chosen(classPicks);
            town  = Chosen(townPicks);
            return trade != null && town != null && cls != null && half.Length > 0;
        }

        class Pick
        {
            public Option O;
            public Border Card;
            public bool On;
        }

        static Option[] ToOptions(Trade[] t)
        {
            var o = new Option[t.Length];
            for (int i = 0; i < t.Length; i++) o[i] = t[i].O;
            return o;
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
            Column(parent, col, heading, items, owner, picks, 1, null, null);
        }

        /// <summary>
        /// max is how many may be on at once. One behaves as it always did:
        /// picking clears the rest. Two or more toggles instead, and refuses to
        /// go past max, which is what the mage's pair of schools needs.
        ///
        /// host, when given, is an existing panel to fill rather than a new
        /// column to make. That is how the halves column is rebuilt when the
        /// profession beside it changes.
        /// </summary>
        static StackPanel Column(Grid parent, int col, string heading, Option[] items,
                                 Window owner, List<Pick> picks, int max,
                                 StackPanel host, Action onChange)
        {
            StackPanel outer;
            return Column(parent, col, heading, items, owner, picks, max, host, onChange, out outer);
        }

        static StackPanel Column(Grid parent, int col, string heading, Option[] items,
                                 Window owner, List<Pick> picks, int max,
                                 StackPanel host, Action onChange, out StackPanel outer)
        {
            outer = null;
            if (host != null)
            {
                host.Children.Clear();
                picks.Clear();
                FillList(host, items, owner, picks, max, onChange);
                return host;
            }

            var stack = new StackPanel();
            outer = stack;

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

            FillList(list, items, owner, picks, max, onChange);

            stack.Children.Add(frame);
            Grid.SetColumn(stack, col);
            parent.Children.Add(stack);
            return list;
        }

        static void FillList(StackPanel list, Option[] items, Window owner,
                             List<Pick> picks, int max, Action onChange)
        {
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
                    if (max <= 1)
                    {
                        foreach (Pick other in picks)
                        {
                            other.On = false;
                            other.Card.Background = card;
                            other.Card.BorderBrush = line;
                        }
                        pick.On = true;
                    }
                    else if (pick.On)
                    {
                        pick.On = false;
                    }
                    else
                    {
                        int on = 0;
                        foreach (Pick q in picks) if (q.On) on++;
                        // Full already, so the oldest one gives way rather than
                        // the click doing nothing and looking broken.
                        if (on >= max)
                        {
                            foreach (Pick q in picks) { if (q.On) { q.On = false; break; } }
                        }
                        pick.On = true;
                    }

                    foreach (Pick q in picks)
                    {
                        q.Card.Background = q.On ? soft : card;
                        q.Card.BorderBrush = q.On ? accent : line;
                    }
                    if (onChange != null) onChange();
                };

                list.Children.Add(box);
            }
        }

        static List<string> AllChosen(List<Pick> picks)
        {
            var got = new List<string>();
            foreach (Pick p in picks) if (p.On) got.Add(p.O.Key);
            return got;
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
            return Send(cfg, profileId, trade, "", "", town, name);
        }

        public static string Send(Config cfg, int profileId, string trade,
                                  string half, string cls, string town, string name)
        {
            if (profileId <= 0) return "no profile id";
            if (string.IsNullOrEmpty(cfg.ServerAddress)) return "no server address";

            // Through Caddy when one is configured, the raw port otherwise.
            // The port is inside VoiceBase now, so it is not picked apart here.
            string url = cfg.VoiceBase() + "/choose";

            // The ticket proves this profile belongs to the Discord account
            // sending the choice. Without it /choose takes anybody's word for
            // anything, and a stranger could set your profession and home town
            // before you ever claimed them.
            string ticket = "";
            try { ticket = Discord.Ticket ?? ""; } catch { ticket = ""; }

            string body = "{\"profileId\":" + profileId +
                          ",\"ticket\":\"" + Esc(ticket) + "\"" +
                          ",\"trade\":\"" + Esc(trade) + "\"" +
                          ",\"half\":\"" + Esc(half ?? "") + "\"" +
                          ",\"cls\":\"" + Esc(cls ?? "") + "\"" +
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
