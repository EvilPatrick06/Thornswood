using System;

namespace Thornswood
{
    /// <summary>
    /// Command line switches for the launcher's WebView2 browsers, merged
    /// rather than stacked.
    ///
    /// Chromium keeps only the LAST copy of a switch it is given twice, so a
    /// second --disable-features would silently switch back on whatever the
    /// first one turned off. Anything that adds a feature to the off list goes
    /// through here and lands inside the one switch that is already there.
    ///
    /// No dependencies on the rest of the launcher, so a test can compile this
    /// file by itself (tests\test-browser-args.ps1).
    /// </summary>
    public static class BrowserArgs
    {
        /// <summary>
        /// Chromium's WebRTC hides a machine's own address behind a random
        /// .local name, and answers for that name with an mDNS responder bound
        /// to UDP 5353 on every network. That responder is a listener Windows
        /// Firewall asks about (#911). Microsoft's machine-wide WebView2 comes
        /// with a rule for it, "Microsoft Edge (mDNS-In)"; a copy installed for
        /// one Windows account does not, so it would ask. Turning the feature
        /// off leaves nothing listening.
        /// </summary>
        public const string NoMdns = "WebRtcHideLocalIpsWithMdns";

        /// <summary>
        /// The switches in <paramref name="current"/> with <paramref name="feature"/>
        /// added to --disable-features: into the existing switch when there is
        /// one, as a new switch otherwise, and unchanged when it is already off.
        /// </summary>
        public static string DisableFeature(string current, string feature)
        {
            string cur = current == null ? "" : current.Trim();
            if (string.IsNullOrEmpty(feature)) return cur;

            const string key = "--disable-features=";
            int at = cur.IndexOf(key, StringComparison.OrdinalIgnoreCase);
            if (at < 0)
                return cur.Length == 0 ? key + feature : cur + " " + key + feature;

            int start = at + key.Length;
            int end = cur.IndexOf(' ', start);
            if (end < 0) end = cur.Length;
            string list = cur.Substring(start, end - start);

            foreach (string f in list.Split(','))
                if (string.Equals(f.Trim(), feature, StringComparison.OrdinalIgnoreCase)) return cur;

            string merged = list.Length == 0 ? feature : list + "," + feature;
            return cur.Substring(0, start) + merged + cur.Substring(end);
        }
    }
}
