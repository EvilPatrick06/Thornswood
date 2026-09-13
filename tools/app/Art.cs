using System;
using System.IO;
using System.Reflection;
using System.Windows.Media.Imaging;

namespace Thornswood
{
    /// <summary>
    /// The emblem, compiled into the exe as a resource.
    ///
    /// It lives inside the executable rather than beside it so that the update
    /// which replaces the launcher carries its own artwork. A loose image file
    /// would need its own line in the packager, its own line in the publisher,
    /// and would eventually go missing on somebody's machine.
    /// </summary>
    static class Art
    {
        static BitmapImage cached;
        static bool tried;

        public static BitmapImage Emblem()
        {
            if (tried) return cached;
            tried = true;
            try
            {
                Assembly asm = Assembly.GetExecutingAssembly();
                string pick = null;
                foreach (string n in asm.GetManifestResourceNames())
                    if (n.EndsWith("logo.png", StringComparison.OrdinalIgnoreCase)) { pick = n; break; }
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
                    cached = bi;
                }
            }
            catch { cached = null; }
            return cached;
        }
    }
}
