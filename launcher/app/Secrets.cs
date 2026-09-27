using System;
using System.IO;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;

namespace Thornswood
{
    /// <summary>
    /// Wraps the two or three strings on this machine that are worth stealing:
    /// the server password, the update token, and the Discord ticket.
    ///
    /// DPAPI with CurrentUser scope, which means Windows ties the ciphertext to
    /// this Windows account on this machine. Another account on the same PC
    /// cannot read it, and copying config.json onto a different machine gets
    /// you a file that will not open. That is the whole ambition. It does not
    /// defend against something already running as this person, because nothing
    /// short of a password prompt on every launch would, and nobody wants that
    /// to start a game.
    ///
    /// Everything is tagged so an old plaintext file still loads. Unprotect
    /// hands back anything without the tag unchanged, which is what makes this
    /// safe to drop into an install that already exists: the next Save writes
    /// it back encrypted and the plaintext is gone.
    /// </summary>
    public static class Secrets
    {
        const string Tag = "dpapi:";
        static readonly byte[] Extra = Encoding.UTF8.GetBytes("Thornswood");

        public static string Protect(string plain)
        {
            if (string.IsNullOrEmpty(plain)) return "";
            if (plain.StartsWith(Tag, StringComparison.Ordinal)) return plain;
            try
            {
                byte[] b = ProtectedData.Protect(Encoding.UTF8.GetBytes(plain),
                                                 Extra, DataProtectionScope.CurrentUser);
                return Tag + Convert.ToBase64String(b);
            }
            catch
            {
                // Better a working launcher holding a plaintext password than a
                // launcher that will not start. It still gets the locked-down
                // file permissions below.
                return plain;
            }
        }

        public static string Unprotect(string stored)
        {
            if (string.IsNullOrEmpty(stored)) return "";
            if (!stored.StartsWith(Tag, StringComparison.Ordinal)) return stored;
            try
            {
                byte[] b = Convert.FromBase64String(stored.Substring(Tag.Length));
                return Encoding.UTF8.GetString(
                    ProtectedData.Unprotect(b, Extra, DataProtectionScope.CurrentUser));
            }
            catch
            {
                // Written by a different Windows account, or the profile was
                // rebuilt. Nothing to recover: the launcher asks for it again.
                return "";
            }
        }

        /// <summary>
        /// Takes inherited permissions off a file and leaves this account as the
        /// only one on it. Belt to the DPAPI's braces, and the thing that stops
        /// a file appearing in somebody's zipped-up folder being readable.
        /// </summary>
        public static void LockDown(string path)
        {
            try
            {
                if (!File.Exists(path)) return;
                var acl = File.GetAccessControl(path);
                acl.SetAccessRuleProtection(true, false);
                foreach (FileSystemAccessRule r in
                         acl.GetAccessRules(true, false, typeof(NTAccount)))
                {
                    acl.RemoveAccessRule(r);
                }
                acl.AddAccessRule(new FileSystemAccessRule(
                    WindowsIdentity.GetCurrent().Name,
                    FileSystemRights.FullControl,
                    AccessControlType.Allow));
                File.SetAccessControl(path, acl);
            }
            catch (Exception ex) { Swallow.Note("Secrets.LockDown, " + path, ex); }
        }
    }
}
