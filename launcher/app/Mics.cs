using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace Thornswood
{
    /// <summary>
    /// Which microphone Windows is set to record from.
    ///
    /// The game's browser is what actually opens a capture device, and asking
    /// it for nothing in particular gets whatever Chromium calls the default.
    /// That is not the same as the one in Windows' own sound settings: on this
    /// machine it took a pair of speakers with an input on them over the
    /// microphone that was actually selected.
    ///
    /// The browser has no way to ask for "whatever Windows would use", so it
    /// has to be told a name. The name cannot be a setting that ships with the
    /// build, because a build goes to everybody and everybody owns a different
    /// microphone. So the launcher reads it off this machine at launch and
    /// writes it into that machine's own ini, which makes it right for each
    /// person without anybody being asked anything.
    ///
    /// Read through the MMDevice COM API, which is the documented way to ask.
    /// The registry holds the same information, but which endpoint currently
    /// holds a role is recorded in undocumented binary values that have moved
    /// between Windows versions, and guessing at those would trade a hundred
    /// lines of interop for a thing that silently breaks on somebody else's
    /// machine.
    /// </summary>
    static class Mics
    {
        // eCapture, and the communications role first: that is the one Windows
        // means by "the microphone apps should use for voice", and it is set
        // separately from the console default in the same dialog.
        const int eCapture = 1;
        const int eConsole = 0;
        const int eCommunications = 2;
        const int DEVICE_STATE_ACTIVE = 0x1;

        /// <summary>
        /// The friendly name of the default recording device, or "" if it
        /// cannot be read. Never throws.
        /// </summary>
        public static string Default()
        {
            string s = "";
            try { s = Endpoint(eCommunications); } catch (Exception ex) { Swallow.Note("Mics.Default, communications endpoint", ex); }
            if (s.Length == 0) { try { s = Endpoint(eConsole); } catch (Exception ex) { Swallow.Note("Mics.Default, console endpoint", ex); } }
            return s;
        }

        /// <summary>Every active recording device, for the log and for a picker.</summary>
        public static List<string> All()
        {
            var outp = new List<string>();
            IMMDeviceEnumerator en = null;
            IMMDeviceCollection col = null;
            try
            {
                en = (IMMDeviceEnumerator)new MMDeviceEnumerator();
                if (en.EnumAudioEndpoints(eCapture, DEVICE_STATE_ACTIVE, out col) != 0 || col == null)
                    return outp;

                int count;
                if (col.GetCount(out count) != 0) return outp;
                for (int i = 0; i < count; i++)
                {
                    IMMDevice dev = null;
                    try
                    {
                        if (col.Item(i, out dev) != 0 || dev == null) continue;
                        string n = NameOf(dev);
                        if (n.Length > 0) outp.Add(n);
                    }
                    catch (Exception ex) { Swallow.Note("Mics.All, reading one device", ex); }
                    finally { Release(dev); }
                }
            }
            catch (Exception ex) { Swallow.Note("Mics.All, enumerating devices", ex); }
            finally { Release(col); Release(en); }
            return outp;
        }

        /// <summary>
        /// Put this machine's microphone name into this machine's ini.
        ///
        /// An explicit choice in the launcher's own settings wins, because a
        /// person who went looking for this meant it. That choice lives in the
        /// launcher's config rather than in the ini, on purpose: the ini is a
        /// mod file, so it is replaced wholesale by an update, and anything
        /// somebody set in it by hand is gone the next time the build changes.
        ///
        /// Returns the name written, or "" when nothing was.
        /// </summary>
        public static string Apply(Config cfg)
        {
            string want = cfg == null ? "" : (cfg.MicrophoneName ?? "").Trim();
            if (want.Length == 0) want = Default();
            // The voice server's port travels the same way. The dev build's
            // launcher talks to the dev voice server, and the plugin in the
            // shared game folder has to be told which one every launch, or a
            // dev session would put its positions on the main server.
            string port = cfg == null ? "" : (cfg.VoicePort ?? "").Trim();
            // And where voice lives. The game overlay opens its own socket and
            // has no other way to be told. VoiceBase, not the raw setting, so
            // the game always gets the https address the launcher uses (#1304).
            string vurl = cfg == null ? "" : cfg.VoiceBase();
            if (want.Length == 0 && port.Length == 0 && vurl.Length == 0) return "";

            string ini = Path.Combine(Paths.Game, "Data\\SKSE\\Plugins\\Thornswood.ini");
            if (!File.Exists(ini)) return "";

            try
            {
                var lines = new List<string>(File.ReadAllLines(ini));
                bool done = false;
                bool vurlDone = false;
                for (int i = 0; i < lines.Count; i++)
                {
                    string t = lines[i].TrimStart();
                    int eq = t.IndexOf('=');
                    if (eq < 0) continue;
                    if (want.Length > 0 && t.StartsWith("MicrophoneName", StringComparison.OrdinalIgnoreCase))
                    {
                        lines[i] = "MicrophoneName = " + want;
                        done = true;
                    }
                    else if (port.Length > 0 && t.StartsWith("VoicePort", StringComparison.OrdinalIgnoreCase))
                    {
                        lines[i] = "VoicePort = " + port;
                    }
                    else if (t.StartsWith("VoiceUrl", StringComparison.OrdinalIgnoreCase))
                    {
                        // Written even when empty, so clearing it here clears
                        // it in the game too rather than leaving a stale one.
                        lines[i] = "VoiceUrl = " + vurl;
                        vurlDone = true;
                    }
                }
                // No line to rewrite, so one is added rather than the name being
                // dropped. The shipped template has never carried this key, so
                // on every machine the name was read off Windows at Play and
                // then written nowhere: the voice plugin found no
                // MicrophoneName, passed an empty name to the page, and the page
                // opened whatever Chromium calls the default, which is the
                // device this class exists to get away from. It goes under
                // [Voice] with the rest of the voice settings, or at the end of
                // the file when there is no such section.
                if (want.Length > 0 && !done)
                {
                    int at = -1;
                    for (int i = 0; i < lines.Count; i++)
                    {
                        if (!lines[i].Trim().Equals("[Voice]", StringComparison.OrdinalIgnoreCase)) continue;
                        at = i + 1;
                        break;
                    }
                    if (at < 0) lines.Add("MicrophoneName = " + want);
                    else lines.Insert(at, "MicrophoneName = " + want);
                    done = true;
                }
                // The shipped template has never carried VoiceUrl, so on every
                // machine there is no line to rewrite and it has to be added or the
                // game would never learn about Caddy at all.
                if (!vurlDone && vurl.Length > 0) { lines.Add("VoiceUrl = " + vurl); }

                File.WriteAllLines(ini, lines.ToArray(), new UTF8Encoding(false));
                return done ? want : "";
            }
            catch { return ""; }
        }

        // ------------------------------------------------------------- interop

        static string Endpoint(int role)
        {
            IMMDeviceEnumerator en = null;
            IMMDevice dev = null;
            try
            {
                en = (IMMDeviceEnumerator)new MMDeviceEnumerator();
                if (en.GetDefaultAudioEndpoint(eCapture, role, out dev) != 0 || dev == null)
                    return "";
                return NameOf(dev);
            }
            finally { Release(dev); Release(en); }
        }

        static string NameOf(IMMDevice dev)
        {
            IPropertyStore store = null;
            try
            {
                // STGM_READ
                if (dev.OpenPropertyStore(0, out store) != 0 || store == null) return "";

                var key = new PROPERTYKEY();
                // PKEY_Device_FriendlyName. The one that reads
                // "Microphone (FIFINE K669B)" rather than just the driver's
                // idea of the hardware.
                key.fmtid = new Guid("a45c254e-df1c-4efd-8020-67d146a850e0");
                key.pid = 14;

                PROPVARIANT v;
                if (store.GetValue(ref key, out v) != 0) return "";
                try
                {
                    // VT_LPWSTR
                    if (v.vt != 31 || v.pointerValue == IntPtr.Zero) return "";
                    return Marshal.PtrToStringUni(v.pointerValue) ?? "";
                }
                finally { try { PropVariantClear(ref v); } catch (Exception ex) { Swallow.Note("Mics.NameOf, PropVariantClear", ex); } }
            }
            catch { return ""; }
            finally { Release(store); }
        }

        static void Release(object o)
        {
            if (o == null) return;
            try { if (Marshal.IsComObject(o)) Marshal.ReleaseComObject(o); } catch (Exception ex) { Swallow.Note("Mics.Release", ex); }
        }

        [DllImport("ole32.dll")]
        static extern int PropVariantClear(ref PROPVARIANT pvar);

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
        class MMDeviceEnumerator { }

        [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
         Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
        interface IMMDeviceEnumerator
        {
            int EnumAudioEndpoints(int dataFlow, int stateMask, out IMMDeviceCollection devices);
            int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
            // The rest of the interface is not called, but the slots have to be
            // here or the vtable lines up wrong and the two above land on the
            // wrong functions.
            int GetDevice(string id, out IMMDevice device);
            int RegisterEndpointNotificationCallback(IntPtr client);
            int UnregisterEndpointNotificationCallback(IntPtr client);
        }

        [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
         Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E")]
        interface IMMDeviceCollection
        {
            int GetCount(out int count);
            int Item(int index, out IMMDevice device);
        }

        [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
         Guid("D666063F-1587-4E43-81F1-B948E807363F")]
        interface IMMDevice
        {
            int Activate(ref Guid iid, int clsCtx, IntPtr activationParams,
                         [MarshalAs(UnmanagedType.IUnknown)] out object iface);
            int OpenPropertyStore(int access, out IPropertyStore properties);
            int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
            int GetState(out int state);
        }

        [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown),
         Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
        interface IPropertyStore
        {
            int GetCount(out int count);
            int GetAt(int index, out PROPERTYKEY key);
            int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
            int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
            int Commit();
        }

        [StructLayout(LayoutKind.Sequential)]
        struct PROPERTYKEY
        {
            public Guid fmtid;
            public int pid;
        }

        // Only the shape matters, and only the first union member is read. The
        // real thing is bigger than this on paper, which is why the explicit
        // size is here rather than left to the marshaller.
        [StructLayout(LayoutKind.Explicit, Size = 16)]
        struct PROPVARIANT
        {
            [FieldOffset(0)] public short vt;
            [FieldOffset(8)] public IntPtr pointerValue;
        }
    }
}
