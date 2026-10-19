using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Json;
using System.Security.Cryptography;

namespace Thornswood
{
    /// <summary>
    /// The signed release manifest, phase C of docs\SIGNED-RELEASES.md (#2163).
    ///
    /// Since #2808 every Ship lists the sha256 of each asset of a release that
    /// carries code or names files (the launcher, the client runtime, each
    /// pack and optional pack, the baseline record) in release.json, and signs
    /// a Windows catalog over it with ThornswoodRelease. The feed names both as
    /// "signedManifest". A checksum alone never says who released a file:
    /// whoever writes version.json writes the hashes too. A file the manifest
    /// lists was released by someone holding the signing right.
    ///
    /// Phase C only WARNS. Refusal says whether a feed's assets are all vouched
    /// for, and the caller writes the answer to launcher.log, which reaches the
    /// site with a session's logs. Nothing here stops an update or Play; phase
    /// D does that, once the warnings have been read for one main and several
    /// dev releases.
    ///
    /// Kept apart, with nothing in it but the framework and Signature, so that
    /// tests\test-2163-manifest-check.ps1 can compile the two on their own and
    /// point them at a catalog ThornswoodRelease really signed.
    /// </summary>
    public static class ReleaseManifest
    {
        [DataContract]
        public class Doc
        {
            [DataMember] public int schema;
            [DataMember] public string release = "";
            [DataMember] public string channel = "";
            [DataMember] public string commit = "";
            [DataMember] public Asset[] assets = null;
        }

        [DataContract]
        public class Asset
        {
            [DataMember] public string what = "";
            [DataMember] public string sha256 = "";
        }

        /// <summary>
        /// Empty when the catalog at catalogPath is signed by Thornswood
        /// (Signature.Refusal, the check the self update makes), lists the
        /// sha256 of the file at jsonPath, and that file names every asset
        /// in assets (what, sha256). Otherwise the reason, as the rest of a
        /// sentence starting "The release manifest". said is the line for the
        /// log when it passed. Never throws.
        /// </summary>
        public static string Refusal(string catalogPath, string jsonPath, IList<KeyValuePair<string, string>> assets,
                                     string expectedSigner, out string said)
        {
            said = "";
            try
            {
                string signedSaid;
                string why = Signature.Refusal(catalogPath, expectedSigner, out signedSaid);
                if (why.Length > 0) return "catalog " + why;

                string jsonSha = Sha256(jsonPath);
                HashSet<string> members = CatalogDigests(catalogPath);
                if (!members.Contains(jsonSha))
                    return "catalog is signed, but does not list release.json as it arrived (" + jsonSha + "), so the list was changed after it was signed.";

                Doc doc;
                using (var fs = File.OpenRead(jsonPath))
                    doc = (Doc)new DataContractJsonSerializer(typeof(Doc)).ReadObject(fs);
                if (doc == null || doc.assets == null) return "release.json lists no assets.";

                var listed = new HashSet<string>(StringComparer.Ordinal);
                foreach (var a in doc.assets)
                    if (a != null && a.sha256 != null) listed.Add(a.sha256.ToLowerInvariant());

                var missing = new List<string>();
                foreach (var kv in assets)
                    if (!listed.Contains((kv.Value ?? "").ToLowerInvariant())) missing.Add(kv.Key + " (" + kv.Value + ")");
                if (missing.Count > 0)
                    return "for release " + doc.release + " does not list " + string.Join(", ", missing.ToArray()) +
                           ", so the feed names " + (missing.Count == 1 ? "a file" : "files") + " nobody signed for.";

                said = "The release manifest for " + doc.release + " lists all " + assets.Count +
                       " of the feed's assets, signed. " + signedSaid;
                return "";
            }
            catch (Exception ex)
            {
                return "could not be checked: " + ex.Message;
            }
        }

        public static string Sha256(string path)
        {
            using (var sha = SHA256.Create())
            using (var fs = File.OpenRead(path))
                return BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "").ToLowerInvariant();
        }

        // ---- the catalog's members, through wintrust ------------------------

        const uint CRYPTCAT_OPEN_EXISTING = 0x00000004;
        const uint CRYPTCAT_VERSION_1 = 0x100;
        const uint CRYPTCAT_VERSION_2 = 0x200;
        const uint ENCODING = 0x00010001; // X509_ASN_ENCODING | PKCS_7_ASN_ENCODING

        [StructLayout(LayoutKind.Sequential)]
        struct BLOB
        {
            public uint cbData;
            public IntPtr pbData;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct CRYPTCATMEMBER
        {
            public uint cbStruct;
            public IntPtr pwszReferenceTag;
            public IntPtr pwszFileName;
            public Guid gSubjectType;
            public uint fdwMemberFlags;
            public IntPtr pIndirectData;
            public uint dwCertVersion;
            public uint dwReserved;
            public IntPtr hReserved;
            public BLOB sEncodedIndirectData;
            public BLOB sEncodedMemberInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct SIP_INDIRECT_DATA
        {
            public IntPtr DataObjId;
            public BLOB DataValue;
            public IntPtr DigestAlgorithmObjId;
            public BLOB DigestAlgorithmParameters;
            public BLOB Digest;
        }

        [DllImport("wintrust.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern IntPtr CryptCATOpen(string fileName, uint openFlags, IntPtr hProv, uint publicVersion, uint encodingType);

        [DllImport("wintrust.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool CryptCATClose(IntPtr hCatalog);

        [DllImport("wintrust.dll")]
        static extern IntPtr CryptCATEnumerateMember(IntPtr hCatalog, IntPtr prevMember);

        /// <summary>
        /// The digest of every member of the catalog, lowercase hex. For a
        /// file that is not a program (release.json) that is its sha256. Read
        /// from the catalog itself; Signature.Refusal is what says the catalog
        /// is ours. Throws when the catalog cannot be opened.
        /// </summary>
        public static HashSet<string> CatalogDigests(string catalogPath)
        {
            string full = Path.GetFullPath(catalogPath);
            IntPtr cat = CryptCATOpen(full, CRYPTCAT_OPEN_EXISTING, IntPtr.Zero, CRYPTCAT_VERSION_2, ENCODING);
            if (cat == IntPtr.Zero || cat == new IntPtr(-1))
                cat = CryptCATOpen(full, CRYPTCAT_OPEN_EXISTING, IntPtr.Zero, CRYPTCAT_VERSION_1, ENCODING);
            if (cat == IntPtr.Zero || cat == new IntPtr(-1))
                throw new Exception("Windows could not open the catalog (error " + Marshal.GetLastWin32Error() + ").");
            var digests = new HashSet<string>(StringComparer.Ordinal);
            try
            {
                IntPtr m = IntPtr.Zero;
                while ((m = CryptCATEnumerateMember(cat, m)) != IntPtr.Zero)
                {
                    var member = (CRYPTCATMEMBER)Marshal.PtrToStructure(m, typeof(CRYPTCATMEMBER));
                    if (member.pIndirectData == IntPtr.Zero) continue;
                    var ind = (SIP_INDIRECT_DATA)Marshal.PtrToStructure(member.pIndirectData, typeof(SIP_INDIRECT_DATA));
                    if (ind.Digest.cbData == 0 || ind.Digest.pbData == IntPtr.Zero) continue;
                    var b = new byte[ind.Digest.cbData];
                    Marshal.Copy(ind.Digest.pbData, b, 0, b.Length);
                    digests.Add(BitConverter.ToString(b).Replace("-", "").ToLowerInvariant());
                }
            }
            finally
            {
                CryptCATClose(cat);
            }
            return digests;
        }
    }
}
