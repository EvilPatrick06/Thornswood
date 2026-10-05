using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;

namespace Thornswood
{
    /// <summary>
    /// Whether a file is really signed by Thornswood, through Microsoft's
    /// Artifact Signing (issue #912).
    ///
    /// Until #912 the self update read the Subject of the certificate embedded
    /// in the download (X509Certificate.CreateFromSignedFile) and looked for
    /// the signer's name (Updater.ExpectedSigner) in it. That call only reads the certificate: it proves
    /// nothing about who issued it, or that the signature covers the file. A
    /// certificate anybody can make on their own machine with that name
    /// passed, and so did a signed file with its bytes changed afterwards.
    ///
    /// Now a file passes only when all of this holds:
    ///
    ///   1. Windows says the signature is good: WinVerifyTrust with
    ///      WINTRUST_ACTION_GENERIC_VERIFY_V2, the call behind
    ///      Get-AuthenticodeSignature's "Valid". That covers every byte the
    ///      signature is over (a changed file fails), and a chain to a root
    ///      Windows trusts (a self-made certificate fails). Revocation is
    ///      checked for the whole chain but the root. When Windows cannot
    ///      reach Microsoft to ask, it is asked again without revocation and
    ///      the log says so: a revoked certificate is still refused whenever
    ///      Microsoft answers, and whoever can change the feed cannot stop a
    ///      person's own machine reaching Microsoft.
    ///   2. The signature is timestamped. Artifact Signing certificates last
    ///      three days; the timestamp is what keeps a signature good after.
    ///   3. The chain Windows built ends at Root, Microsoft Identity
    ///      Verification Root Certificate Authority 2020, the root every
    ///      Artifact Signing certificate is issued under, and the certificate
    ///      was issued by one of Microsoft's "ID Verified CS" authorities.
    ///   4. The certificate carries the Artifact Signing public trust usage
    ///      (ArtifactSigning) and one of Identities: the durable identity
    ///      value Microsoft puts in every certificate of one certificate
    ///      profile. The certificate itself changes every few days, so its
    ///      thumbprint cannot be pinned; this value stays the same across
    ///      every renewal of the profile, and only Microsoft's authorities
    ///      put it in a certificate, only for the identity it validated.
    ///   5. The Subject still has the expected signer in it (Updater's
    ///      ExpectedSigner, a fragment, because renewals reorder fields).
    ///
    /// MEASURED 28 SEP on dev 1.1.101.34 (C:\Thornswood-DevBuild\Launcher):
    /// CN and O the name on the certificate (Updater.ExpectedSigner), three days
    /// (27 to 30 Sep), issued by Microsoft ID Verified CS AOC CA 04, under
    /// Microsoft ID Verified Code Signing PCA 2021, under Microsoft Identity
    /// Verification Root Certificate Authority 2020 (F40042E2...BFA2, to
    /// 2045). Usages: 1.3.6.1.4.1.311.97.1.0, code signing, and
    /// 1.3.6.1.4.1.311.97.203948530.216998690.847558466.123546472.
    ///
    /// IF THE PROFILE CHANGES. A new certificate profile or a new identity
    /// validation in Azure gets a new durable identity value. Add it to
    /// Identities and Ship that launcher, signed with the OLD profile, before
    /// anything is signed with the new one, or every installed launcher
    /// refuses the update. scripts\release\Assert-PublishSigned.ps1 runs this
    /// same class on every launcher and setup program before a Ship
    /// publishes, so a Ship signed by anything else stops there first.
    ///
    /// MicrosoftRefusal, at the end, asks the same question of a program
    /// Microsoft signed itself: the WebView2 installer Voice downloads and
    /// runs (issue #1330).
    ///
    /// Kept apart from Updater, with nothing in it but the framework, so that
    /// tests\test-signer-check.ps1 can compile it on its own and point it at
    /// real signed, unsigned, self-signed and changed files.
    /// </summary>
    public static class Signature
    {
        /// <summary>Thumbprint of Microsoft Identity Verification Root Certificate Authority 2020.</summary>
        public const string Root = "F40042E2E5F7E8EF8189FED15519AECE42C3BFA2";

        /// <summary>How the Issuer of an Artifact Signing certificate starts
        /// ("Microsoft ID Verified CS AOC CA 04" on 28 Sep; the number and the
        /// AOC / EOC part change as Microsoft rotates them).</summary>
        public const string IssuerStart = "CN=Microsoft ID Verified CS ";

        /// <summary>In every Artifact Signing public trust certificate.</summary>
        public const string ArtifactSigning = "1.3.6.1.4.1.311.97.1.0";

        /// <summary>Code signing, in every code signing certificate.</summary>
        public const string CodeSigning = "1.3.6.1.5.5.7.3.3";

        /// <summary>
        /// The durable identity value of the ThornswoodRelease certificate
        /// profile. More than one only while moving to a new profile.
        /// </summary>
        public static readonly string[] Identities = {
            "1.3.6.1.4.1.311.97.203948530.216998690.847558466.123546472",
        };

        /// <summary>
        /// Empty when the file at path is signed by Thornswood; otherwise the
        /// rest of a sentence that starts with the file's name, saying which
        /// check it failed. said is the line for the log when it passed.
        /// </summary>
        public static string Refusal(string path, string expectedSigner, out string said)
        {
            return Refusal(path, expectedSigner, Identities, out said);
        }

        public static string Refusal(string path, string expectedSigner, string[] identities, out string said)
        {
            said = "";
            if (String.IsNullOrEmpty(expectedSigner) || identities == null || identities.Length == 0)
                return "cannot be checked, because this build names no signer to expect.";

            FileStream fs;
            try { fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read); }
            catch (Exception ex) { return "could not be opened to check its signature: " + ex.Message; }

            // Held open, sharing only reads, from the first check to the last,
            // so the file checked is the file the chain was read from.
            using (fs)
            {
                var chain = new List<X509Certificate2>();
                bool stamped;
                bool revocation = true;
                uint rc = Trust(fs, path, true, chain, out stamped);
                if (rc == CERT_E_REVOCATION_FAILURE || rc == CRYPT_E_REVOCATION_OFFLINE ||
                    rc == CRYPT_E_NO_REVOCATION_CHECK)
                {
                    revocation = false;
                    chain.Clear();
                    rc = Trust(fs, path, false, chain, out stamped);
                }
                if (rc != 0) return Said(rc);

                if (chain.Count < 3)
                    return "has a signature Windows accepts, but not through Microsoft's Artifact Signing (a chain of " +
                           chain.Count + " certificate" + (chain.Count == 1 ? "" : "s") + ").";
                X509Certificate2 leaf = chain[0];
                X509Certificate2 root = chain[chain.Count - 1];
                if (!String.Equals(root.Thumbprint, Root, StringComparison.OrdinalIgnoreCase))
                    return "is signed under " + root.Subject + ", not under Microsoft's Artifact Signing root.";
                if (!leaf.Issuer.StartsWith(IssuerStart, StringComparison.Ordinal))
                    return "is signed with a certificate from " + leaf.Issuer + ", not from Microsoft's Artifact Signing.";
                if (!stamped)
                    return "is signed but not timestamped, so its signature stops being good when the certificate runs out.";

                var usages = new List<string>();
                foreach (X509Extension e in leaf.Extensions)
                {
                    var eku = e as X509EnhancedKeyUsageExtension;
                    if (eku == null) continue;
                    foreach (System.Security.Cryptography.Oid o in eku.EnhancedKeyUsages) usages.Add(o.Value);
                }
                if (!usages.Contains(CodeSigning) || !usages.Contains(ArtifactSigning))
                    return "is signed with a certificate that is not an Artifact Signing code signing certificate.";
                bool ours = false;
                foreach (string id in identities)
                    if (!String.IsNullOrEmpty(id) && usages.Contains(id)) ours = true;
                if (!ours)
                    return "is signed through Artifact Signing, but for somebody else's identity (" + leaf.Subject + ").";
                if (leaf.Subject.IndexOf(expectedSigner, StringComparison.OrdinalIgnoreCase) < 0)
                    return "is signed for Thornswood's identity, but its Subject (" + leaf.Subject +
                           ") does not name " + expectedSigner + ".";

                said = "Signed by " + leaf.GetNameInfo(X509NameType.SimpleName, false) +
                       " through Microsoft's Artifact Signing (" + leaf.GetNameInfo(X509NameType.SimpleName, true) +
                       "), timestamped, " +
                       (revocation ? "and Windows checked it is not revoked."
                                   : "but Microsoft could not be reached to check it is not revoked.");
                return "";
            }
        }

        // ---- WinVerifyTrust -----------------------------------------------------

        const uint TRUST_E_NOSIGNATURE = 0x800B0100;
        const uint TRUST_E_SUBJECT_FORM_UNKNOWN = 0x800B0003;
        const uint TRUST_E_PROVIDER_UNKNOWN = 0x800B0001;
        const uint TRUST_E_BAD_DIGEST = 0x80096010;
        const uint TRUST_E_EXPLICIT_DISTRUST = 0x800B0111;
        const uint TRUST_E_SUBJECT_NOT_TRUSTED = 0x800B0004;
        const uint CERT_E_UNTRUSTEDROOT = 0x800B0109;
        const uint CERT_E_CHAINING = 0x800B010A;
        const uint CERT_E_EXPIRED = 0x800B0101;
        const uint CERT_E_REVOKED = 0x800B010C;
        const uint CERT_E_WRONG_USAGE = 0x800B0110;
        const uint CERT_E_REVOCATION_FAILURE = 0x800B010E;
        const uint CRYPT_E_REVOKED = 0x80092010;
        const uint CRYPT_E_NO_REVOCATION_CHECK = 0x80092012;
        const uint CRYPT_E_REVOCATION_OFFLINE = 0x80092013;
        const uint CRYPT_E_FILE_ERROR = 0x80092003;

        static string Said(uint rc)
        {
            switch (rc)
            {
                case TRUST_E_NOSIGNATURE:
                case TRUST_E_SUBJECT_FORM_UNKNOWN:
                case TRUST_E_PROVIDER_UNKNOWN:
                    return "is not signed.";
                case TRUST_E_BAD_DIGEST:
                    return "has been changed since it was signed.";
                case CERT_E_UNTRUSTEDROOT:
                case CERT_E_CHAINING:
                case TRUST_E_SUBJECT_NOT_TRUSTED:
                    return "is signed with a certificate Windows does not trust, one anybody could have made.";
                case TRUST_E_EXPLICIT_DISTRUST:
                    return "is signed with a certificate Windows has been told to distrust.";
                case CERT_E_REVOKED:
                case CRYPT_E_REVOKED:
                    return "is signed with a certificate that has been revoked.";
                case CERT_E_EXPIRED:
                    return "is signed with a certificate that has run out, and the signature has no timestamp.";
                case CERT_E_WRONG_USAGE:
                    return "is signed with a certificate that is not for signing programs.";
                case CRYPT_E_FILE_ERROR:
                    return "could not be read to check its signature.";
            }
            return "failed Windows' signature check (0x" + rc.ToString("X8") + ").";
        }

        static readonly Guid GenericVerifyV2 = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

        const uint WTD_UI_NONE = 2;
        const uint WTD_REVOKE_NONE = 0;
        const uint WTD_REVOKE_WHOLECHAIN = 1;
        const uint WTD_CHOICE_FILE = 1;
        const uint WTD_STATEACTION_VERIFY = 1;
        const uint WTD_STATEACTION_CLOSE = 2;
        const uint WTD_REVOCATION_CHECK_NONE = 0x10;
        const uint WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT = 0x80;

        [StructLayout(LayoutKind.Sequential)]
        struct WINTRUST_FILE_INFO
        {
            public uint cbStruct;
            public IntPtr pcwszFilePath;
            public IntPtr hFile;
            public IntPtr pgKnownSubject;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct WINTRUST_DATA
        {
            public uint cbStruct;
            public IntPtr pPolicyCallbackData;
            public IntPtr pSIPClientData;
            public uint dwUIChoice;
            public uint fdwRevocationChecks;
            public uint dwUnionChoice;
            public IntPtr pFile;
            public uint dwStateAction;
            public IntPtr hWVTStateData;
            public IntPtr pwszURLReference;
            public uint dwProvFlags;
            public uint dwUIContext;
            public IntPtr pSignatureSettings;
        }

        // The start of CRYPT_PROVIDER_SGNR, as far as the fields read here.
        [StructLayout(LayoutKind.Sequential)]
        struct CRYPT_PROVIDER_SGNR
        {
            public uint cbStruct;
            public uint sftVerifyAsOfLow;
            public uint sftVerifyAsOfHigh;
            public uint csCertChain;
            public IntPtr pasCertChain;
            public uint dwSignerType;
            public IntPtr psSigner;
            public uint dwError;
            public uint csCounterSigners;
            public IntPtr pasCounterSigners;
            public IntPtr pChainContext;
        }

        [DllImport("wintrust.dll", ExactSpelling = true)]
        static extern uint WinVerifyTrust(IntPtr hwnd, [In] ref Guid action, ref WINTRUST_DATA data);

        [DllImport("wintrust.dll", ExactSpelling = true)]
        static extern IntPtr WTHelperProvDataFromStateData(IntPtr state);

        [DllImport("wintrust.dll", ExactSpelling = true)]
        static extern IntPtr WTHelperGetProvSignerFromChain(IntPtr provData, uint signer,
            [MarshalAs(UnmanagedType.Bool)] bool counterSigner, uint counterSignerIndex);

        [DllImport("wintrust.dll", ExactSpelling = true)]
        static extern IntPtr WTHelperGetProvCertFromChain(IntPtr sgnr, uint cert);

        /// <summary>
        /// WinVerifyTrust on the file, and on success the chain it built,
        /// leaf first, root last, and whether the signature is timestamped.
        /// The chain comes from Windows' own verification, so it is the chain
        /// that was checked and not one built again afterwards.
        /// </summary>
        static uint Trust(FileStream fs, string path, bool revocation, List<X509Certificate2> chain, out bool stamped)
        {
            stamped = false;
            IntPtr name = Marshal.StringToHGlobalUni(Path.GetFullPath(path));
            IntPtr info = IntPtr.Zero;
            var data = new WINTRUST_DATA();
            bool opened = false;
            Guid action = GenericVerifyV2;
            try
            {
                var fi = new WINTRUST_FILE_INFO();
                fi.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_FILE_INFO));
                fi.pcwszFilePath = name;
                fi.hFile = fs.SafeFileHandle.DangerousGetHandle();
                info = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(WINTRUST_FILE_INFO)));
                Marshal.StructureToPtr(fi, info, false);

                data.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_DATA));
                data.dwUIChoice = WTD_UI_NONE;
                data.fdwRevocationChecks = revocation ? WTD_REVOKE_WHOLECHAIN : WTD_REVOKE_NONE;
                data.dwProvFlags = revocation ? WTD_REVOCATION_CHECK_CHAIN_EXCLUDE_ROOT : WTD_REVOCATION_CHECK_NONE;
                data.dwUnionChoice = WTD_CHOICE_FILE;
                data.pFile = info;
                data.dwStateAction = WTD_STATEACTION_VERIFY;

                uint rc = WinVerifyTrust(IntPtr.Zero, ref action, ref data);
                opened = true;
                if (rc != 0) return rc;

                IntPtr prov = WTHelperProvDataFromStateData(data.hWVTStateData);
                IntPtr sgnr = prov == IntPtr.Zero ? IntPtr.Zero : WTHelperGetProvSignerFromChain(prov, 0, false, 0);
                if (sgnr == IntPtr.Zero) return TRUST_E_NOSIGNATURE;
                var s = (CRYPT_PROVIDER_SGNR)Marshal.PtrToStructure(sgnr, typeof(CRYPT_PROVIDER_SGNR));
                stamped = s.csCounterSigners > 0;
                for (uint i = 0; i < s.csCertChain; i++)
                {
                    IntPtr pc = WTHelperGetProvCertFromChain(sgnr, i);
                    if (pc == IntPtr.Zero) break;
                    // CRYPT_PROVIDER_CERT: a DWORD, then the certificate context,
                    // at the next pointer boundary.
                    IntPtr ctx = Marshal.ReadIntPtr(pc, IntPtr.Size);
                    if (ctx == IntPtr.Zero) break;
                    chain.Add(new X509Certificate2(ctx));
                }
                return 0;
            }
            finally
            {
                if (opened)
                {
                    data.dwStateAction = WTD_STATEACTION_CLOSE;
                    WinVerifyTrust(IntPtr.Zero, ref action, ref data);
                }
                if (info != IntPtr.Zero)
                {
                    Marshal.DestroyStructure(info, typeof(WINTRUST_FILE_INFO));
                    Marshal.FreeHGlobal(info);
                }
                Marshal.FreeHGlobal(name);
            }
        }

        // ---- Microsoft's own programs (issue #1330) -----------------------------

        /// <summary>Thumbprint of Microsoft Root Certificate Authority 2011,
        /// the root Microsoft signs its own programs under.</summary>
        public const string MicrosoftRoot = "8F43288AD272F3103B6FB1428485EA3014C0BCFE";

        /// <summary>The name (CN) on the certificate Microsoft signs its own
        /// programs with.</summary>
        public const string MicrosoftSigner = "Microsoft Corporation";

        /// <summary>
        /// Empty when the file at path is a program Microsoft signed itself;
        /// otherwise the rest of a sentence that starts with the file's name,
        /// as Refusal returns it. said is the line for the log when it passed.
        ///
        /// Voice.Bootstrap asks this before it runs the WebView2 installer it
        /// has just downloaded. Until #1330 it ran whatever the download
        /// handed it, so whoever could change that file on the way, or at the
        /// server it came from, chose what ran on this machine.
        ///
        /// A file passes only when all of this holds:
        ///
        ///   1. Windows says the signature is good, exactly as in Refusal
        ///      (WinVerifyTrust, the same revocation rule), so a changed file
        ///      or a certificate Windows does not trust fails.
        ///   2. The chain Windows built ends at MicrosoftRoot. Any certificate
        ///      authority Windows trusts can sign a certificate that says
        ///      Microsoft Corporation; only Microsoft issues under its own root.
        ///   3. The certificate is named MicrosoftSigner and is for signing
        ///      programs.
        ///
        /// No hash is pinned: the link always hands out Microsoft's latest
        /// installer, so its bytes change with every release of it.
        ///
        /// MEASURED 5 OCT on what https://go.microsoft.com/fwlink/p/?LinkId=2124703
        /// handed out (MicrosoftEdgeWebview2Setup.exe, 1,850,576 bytes):
        /// CN=Microsoft Corporation, O=Microsoft Corporation, issued by
        /// Microsoft Code Signing PCA 2024, under Microsoft Root Certificate
        /// Authority 2011 (8F43288A...BCFE, to 2036), with a timestamp. It also
        /// carries a nested second signature from a self-made EdgeBuild
        /// certificate; WinVerifyTrust checks the first signature, the one
        /// pinned here.
        ///
        /// IF MICROSOFT MOVES its signing to another root, this refuses the new
        /// installer and the log names the root it is signed under. Measure
        /// the new chain and add that root here; never take the check out.
        /// </summary>
        public static string MicrosoftRefusal(string path, out string said)
        {
            said = "";
            FileStream fs;
            try { fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read); }
            catch (Exception ex) { return "could not be opened to check its signature: " + ex.Message; }

            using (fs)
            {
                var chain = new List<X509Certificate2>();
                bool stamped;
                bool revocation = true;
                uint rc = Trust(fs, path, true, chain, out stamped);
                if (rc == CERT_E_REVOCATION_FAILURE || rc == CRYPT_E_REVOCATION_OFFLINE ||
                    rc == CRYPT_E_NO_REVOCATION_CHECK)
                {
                    revocation = false;
                    chain.Clear();
                    rc = Trust(fs, path, false, chain, out stamped);
                }
                if (rc != 0) return Said(rc);

                if (chain.Count < 2)
                    return "has a signature Windows accepts, but not Microsoft's (a chain of " +
                           chain.Count + " certificate" + (chain.Count == 1 ? "" : "s") + ").";
                X509Certificate2 leaf = chain[0];
                X509Certificate2 root = chain[chain.Count - 1];
                if (!String.Equals(root.Thumbprint, MicrosoftRoot, StringComparison.OrdinalIgnoreCase))
                    return "is signed under " + root.Subject + ", not under Microsoft's own root.";
                if (!String.Equals(leaf.GetNameInfo(X509NameType.SimpleName, false), MicrosoftSigner, StringComparison.Ordinal))
                    return "is signed under Microsoft's own root, but for " + leaf.Subject + ", not for " + MicrosoftSigner + ".";

                bool programs = false;
                foreach (X509Extension e in leaf.Extensions)
                {
                    var eku = e as X509EnhancedKeyUsageExtension;
                    if (eku == null) continue;
                    foreach (System.Security.Cryptography.Oid o in eku.EnhancedKeyUsages)
                        if (o.Value == CodeSigning) programs = true;
                }
                if (!programs)
                    return "is signed with a Microsoft certificate that is not for signing programs.";

                said = "Signed by " + MicrosoftSigner + " (" + leaf.GetNameInfo(X509NameType.SimpleName, true) +
                       ", under " + root.GetNameInfo(X509NameType.SimpleName, false) + "), " +
                       (revocation ? "and Windows checked it is not revoked."
                                   : "but Microsoft could not be reached to check it is not revoked.");
                return "";
            }
        }
    }
}
