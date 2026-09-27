using System;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Thornswood
{
    /// <summary>
    /// The emblem and the picture behind the title band, compiled into the exe
    /// as resources.
    ///
    /// They live inside the executable rather than beside it so that the update
    /// which replaces the launcher carries its own artwork. A loose image file
    /// would need its own line in the packager, its own line in the publisher,
    /// and would eventually go missing on somebody's machine.
    /// </summary>
    static class Art
    {
        static BitmapImage cached;
        static bool tried;

        static ImageBrush header;
        static bool triedHeader;

        static string headerVideo;
        static bool triedHeaderVideo;

        /// <summary>
        /// True in the dev build. Set by Shell as soon as the config is read,
        /// before anything asks for the emblem or the shortcut icon.
        /// </summary>
        public static bool Dev;

        /// <summary>
        /// The emblem: logo.png on the main build, logo-dev.png on the dev
        /// build (Djinn, 25 Sep: the new emblem is the dev launcher's only,
        /// main keeps its own). A dev build without logo-dev.png falls back
        /// to logo.png.
        /// </summary>
        public static BitmapImage Emblem()
        {
            if (tried) return cached;
            tried = true;
            if (Dev) cached = Load("logo-dev.png");
            if (cached == null) cached = Load("logo.png");
            return cached;
        }

        /// <summary>
        /// The strip of landscape behind the title on the Play page, as a brush
        /// that fills the band and crops what does not fit, the way a desktop
        /// wallpaper does. Null when this build carries no picture, and the band
        /// then keeps its pattern.
        /// </summary>
        public static ImageBrush Header()
        {
            if (triedHeader) return header;
            triedHeader = true;
            try
            {
                BitmapImage bi = Load("launcher-header.jpg");
                if (bi == null) return null;
                var b = new ImageBrush(bi);
                b.Stretch = Stretch.UniformToFill;
                b.AlignmentX = AlignmentX.Center;
                b.AlignmentY = AlignmentY.Center;
                b.Freeze();
                header = b;
            }
            catch { header = null; }
            return header;
        }

        /// <summary>
        /// The same strip moving, as a file on disk, because WPF plays video
        /// from a file and not from a stream. It is written beside the exe once,
        /// under a name taken from its own contents the way the icon is, so the
        /// next start finds it already there and a build with a new video writes
        /// a new file rather than trusting an old one. Null when this build
        /// carries no video or the file cannot be written, and the band then
        /// keeps the still picture.
        /// </summary>
        public static string HeaderVideo()
        {
            if (triedHeaderVideo) return headerVideo;
            triedHeaderVideo = true;
            try
            {
                byte[] bytes = Bytes("launcher-header.mp4");
                if (bytes == null || bytes.Length == 0) return null;
                if (!Directory.Exists(Paths.LauncherDir)) return null;

                string hash;
                using (SHA256 sha = SHA256.Create())
                    hash = BitConverter.ToString(sha.ComputeHash(bytes), 0, 4).Replace("-", "").ToLowerInvariant();

                string want = Path.Combine(Paths.LauncherDir, "header-" + hash + ".mp4");
                if (!File.Exists(want) || new FileInfo(want).Length != bytes.Length)
                    File.WriteAllBytes(want, bytes);

                // The one an older build wrote is only taking up room now.
                foreach (string f in Directory.GetFiles(Paths.LauncherDir, "header-*.mp4"))
                    if (!string.Equals(f, want, StringComparison.OrdinalIgnoreCase))
                        try { File.Delete(f); } catch (Exception ex) { Swallow.Note("Art.HeaderVideo, deleting old " + f, ex); }

                headerVideo = want;
            }
            catch { headerVideo = null; }
            return headerVideo;
        }

        static byte[] Bytes(string name)
        {
            Assembly asm = Assembly.GetExecutingAssembly();
            string pick = null;
            foreach (string n in asm.GetManifestResourceNames())
                if (n.EndsWith(name, StringComparison.OrdinalIgnoreCase)) { pick = n; break; }
            if (pick == null) return null;

            using (Stream st = asm.GetManifestResourceStream(pick))
            {
                if (st == null) return null;
                var ms = new MemoryStream();
                st.CopyTo(ms);
                return ms.ToArray();
            }
        }

        static BitmapImage Load(string name)
        {
            try
            {
                Assembly asm = Assembly.GetExecutingAssembly();
                string pick = null;
                foreach (string n in asm.GetManifestResourceNames())
                    if (n.EndsWith(name, StringComparison.OrdinalIgnoreCase)) { pick = n; break; }
                if (pick == null) return null;

                using (Stream st = asm.GetManifestResourceStream(pick))
                {
                    if (st == null) return null;
                    var ms = new MemoryStream();
                    st.CopyTo(ms);
                    ms.Position = 0;

                    var bi = new BitmapImage();
                    bi.BeginInit();
                    // OnLoad, or the stream is read lazily and the image is
                    // blank once this using block has closed it.
                    bi.CacheOption = BitmapCacheOption.OnLoad;
                    bi.StreamSource = ms;
                    bi.EndInit();
                    bi.Freeze();
                    return bi;
                }
            }
            catch { return null; }
        }
    }
}
