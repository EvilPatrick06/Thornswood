using System;
using System.IO;
using System.Reflection;
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

        public static BitmapImage Emblem()
        {
            if (tried) return cached;
            tried = true;
            cached = Load("logo.png");
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
