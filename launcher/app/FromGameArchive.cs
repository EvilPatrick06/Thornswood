using System;
using System.Collections.Generic;
using System.IO;

namespace Thornswood
{
    /// <summary>
    /// One of Skyrim Special Edition's archives (Skyrim - Meshes0.bsa and the
    /// like, BSA version 105), read only, for FromGame (#2827). It is the
    /// reader scripts\mods\Build-NoticeBoard.py has used since #2502, in C#:
    /// the folder and file records, the name block, the per file compression
    /// toggle, the names some archives embed before each file, and LZ4 frames.
    /// Nothing here writes, and an archive that is not version 105 or does not
    /// carry its folder and file names is refused by name.
    /// </summary>
    public sealed class GameArchive
    {
        public readonly string Path;
        readonly bool compressed, embed;
        readonly Dictionary<string, KeyValuePair<uint, uint>> files =
            new Dictionary<string, KeyValuePair<uint, uint>>(StringComparer.OrdinalIgnoreCase);

        public GameArchive(string path)
        {
            Path = path;
            using (var f = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var r = new BinaryReader(f))
            {
                byte[] magic = r.ReadBytes(4);
                uint ver = r.ReadUInt32(), foff = r.ReadUInt32(), flags = r.ReadUInt32();
                uint nfold = r.ReadUInt32(), nfile = r.ReadUInt32(), lfold = r.ReadUInt32(), lfile = r.ReadUInt32();
                r.ReadUInt16();
                if (magic.Length != 4 || magic[0] != 'B' || magic[1] != 'S' || magic[2] != 'A' || magic[3] != 0 || ver != 105)
                    throw new InvalidDataException(path + " is not a Skyrim Special Edition archive (BSA version 105).");
                if ((flags & 0x3) != 0x3)
                    throw new InvalidDataException(path + " does not carry its folder and file names, so nothing in it can be found by name.");
                compressed = (flags & 0x4) != 0;
                embed = (flags & 0x100) != 0;
                f.Position = foff;
                var counts = new uint[nfold];
                for (int i = 0; i < nfold; i++)
                {
                    r.ReadUInt64();
                    counts[i] = r.ReadUInt32();
                    r.ReadUInt32();
                    r.ReadUInt64();
                }
                var recs = new List<KeyValuePair<string, KeyValuePair<uint, uint>>>();
                foreach (uint cnt in counts)
                {
                    int n = r.ReadByte();
                    byte[] name = r.ReadBytes(n);
                    string folder = Latin(name, 0, Math.Max(0, n - 1));
                    for (int k = 0; k < cnt; k++)
                    {
                        r.ReadUInt64();
                        uint size = r.ReadUInt32(), off = r.ReadUInt32();
                        recs.Add(new KeyValuePair<string, KeyValuePair<uint, uint>>(folder, new KeyValuePair<uint, uint>(size, off)));
                    }
                }
                byte[] block = r.ReadBytes((int)lfile);
                int at = 0;
                foreach (var rec in recs)
                {
                    int end = Array.IndexOf(block, (byte)0, at);
                    if (end < 0) end = block.Length;
                    string leaf = Latin(block, at, end - at);
                    at = end + 1;
                    string key = rec.Key + "\\" + leaf;
                    files[key] = rec.Value;
                }
            }
        }

        public bool Has(string rel) { return files.ContainsKey(Norm(rel)); }

        // The archives' names are ASCII; one byte is one character, so no code
        // page has to be installed for this to read them.
        static string Latin(byte[] b, int at, int n)
        {
            var c = new char[n];
            for (int i = 0; i < n; i++) c[i] = (char)b[at + i];
            return new string(c);
        }

        static string Norm(string rel) { return rel.Replace('/', '\\'); }

        /// <summary>The file's bytes as the game reads them, unpacked.</summary>
        public byte[] Read(string rel)
        {
            KeyValuePair<uint, uint> e = files[Norm(rel)];
            uint size = e.Key, off = e.Value;
            bool packed = compressed ^ ((size & 0x40000000) != 0);
            size &= 0x3FFFFFFF;
            using (var f = new FileStream(Path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            {
                f.Position = off;
                if (embed)
                {
                    int n = f.ReadByte();
                    f.Position += n;
                    size -= (uint)(n + 1);
                }
                byte[] raw = new byte[size];
                int got = 0;
                while (got < raw.Length)
                {
                    int k = f.Read(raw, got, raw.Length - got);
                    if (k <= 0) throw new EndOfStreamException(Path + " ends inside " + rel + ".");
                    got += k;
                }
                if (!packed) return raw;
                uint original = BitConverter.ToUInt32(raw, 0);
                byte[] data = Lz4Frame.Decode(raw, 4, raw.Length - 4);
                if (data.Length != original)
                    throw new InvalidDataException(rel + " in " + Path + " unpacks to " + data.Length + " bytes, not the " + original + " the archive says.");
                return data;
            }
        }
    }

    /// <summary>The archives a game's Data folder has, asked in order, the way Build-NoticeBoard.py's Vanilla asks them.</summary>
    public sealed class GameArchives
    {
        readonly List<GameArchive> archives = new List<GameArchive>();

        /// <summary>Opens each named archive in <paramref name="data"/>; one that is missing is refused by name.</summary>
        public GameArchives(string data, IEnumerable<string> names)
        {
            foreach (string name in names)
            {
                string path = System.IO.Path.Combine(data, name);
                if (!File.Exists(path)) throw new FileNotFoundException(name + " is not in " + data + ".", path);
                archives.Add(new GameArchive(path));
            }
        }

        public bool Has(string rel)
        {
            foreach (GameArchive a in archives) if (a.Has(rel)) return true;
            return false;
        }

        public byte[] Read(string rel)
        {
            foreach (GameArchive a in archives) if (a.Has(rel)) return a.Read(rel);
            throw new FileNotFoundException(rel + " is not in the game's archives.");
        }
    }

    /// <summary>LZ4 frames (the format the Special Edition's archives pack files in), decoded.</summary>
    public static class Lz4Frame
    {
        public static byte[] Decode(byte[] src, int at, int count)
        {
            int end = at + count;
            var outp = new List<byte>(count * 3);
            if (BitConverter.ToUInt32(src, at) != 0x184D2204) throw new InvalidDataException("not an LZ4 frame");
            at += 4;
            byte flg = src[at++];
            at++; // BD
            bool blockSum = (flg & 0x10) != 0, contentSize = (flg & 0x08) != 0, dict = (flg & 0x01) != 0;
            if ((flg >> 6) != 1) throw new InvalidDataException("an LZ4 frame of an unknown version");
            if (contentSize) at += 8;
            if (dict) at += 4;
            at++; // header checksum
            while (at < end)
            {
                uint size = BitConverter.ToUInt32(src, at);
                at += 4;
                if (size == 0) break;
                bool raw = (size & 0x80000000) != 0;
                int n = (int)(size & 0x7FFFFFFF);
                if (raw) { for (int i = 0; i < n; i++) outp.Add(src[at + i]); }
                else Block(src, at, n, outp);
                at += n;
                if (blockSum) at += 4;
            }
            return outp.ToArray();
        }

        static void Block(byte[] s, int at, int n, List<byte> o)
        {
            int end = at + n;
            while (at < end)
            {
                int token = s[at++];
                int lit = token >> 4;
                if (lit == 15) { int b; do { b = s[at++]; lit += b; } while (b == 255); }
                for (int i = 0; i < lit; i++) o.Add(s[at + i]);
                at += lit;
                if (at >= end) break;
                int offset = s[at] | (s[at + 1] << 8);
                at += 2;
                int len = token & 15;
                if (len == 15) { int b; do { b = s[at++]; len += b; } while (b == 255); }
                len += 4;
                int from = o.Count - offset;
                if (offset == 0 || from < 0) throw new InvalidDataException("an LZ4 block that points before its start");
                for (int i = 0; i < len; i++) o.Add(o[from + i]);
            }
        }
    }
}
