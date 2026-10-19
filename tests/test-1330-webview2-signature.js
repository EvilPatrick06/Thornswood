// test-1330-webview2-signature.js
//
// #1330. With no WebView2 runtime on the machine, Voice downloads Microsoft's
// WebView2 installer (MicrosoftEdgeWebview2Setup.exe) and runs it. Until #1330
// it ran whatever the download handed it, so whoever could change that file
// on the way, or at the server it came from, chose what ran on the machine.
// Now Voice.Bootstrap runs it only when Signature.MicrosoftRefusal says
// Microsoft signed it: Windows verifies the signature (WinVerifyTrust), the
// chain Windows built ends at Microsoft Root Certificate Authority 2011, and
// the certificate is Microsoft Corporation's, for signing programs.
//
// The C# cannot run here (WinVerifyTrust is Windows', and the launcher is the
// .NET Framework), so this checks:
//
//   A. Voice.Bootstrap: the check sits between the download and the start,
//      on the same file, and a refusal deletes the file unrun and says so;
//      nothing else in the launcher or the installer fetches or runs it.
//   B. Signature.MicrosoftRefusal: Windows' verdict first, the pinned root,
//      the exact name, the code signing usage, and success only after all.
//   C. The pins against the real chain: tests/fixtures/webview2-setup-chain.txt
//      holds the certificates of the installer the link handed out on 5 Oct,
//      read out of its signature, and the root from the address its issuer
//      names. The root's thumbprint has to be MicrosoftRoot as written in
//      Signature.cs, each certificate has to be signed by the next, and the
//      signing certificate has to carry MicrosoftSigner and code signing.
//
// tests\test-signer-check.ps1 runs the class itself on Windows against real
// unsigned, self-signed, changed and other publishers' files.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const CR = String.fromCharCode(13);
function read() {
  return fs.readFileSync(path.join.apply(path, [REPO_DIR].concat([].slice.call(arguments))), 'utf8').split(CR).join('');
}

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function done() {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}
/* One C# method by its declaration line, to the closing brace at its indent. */
function method(src, decl, indent) {
  const a = src.indexOf('\n' + indent + decl);
  if (a < 0 || src.indexOf('\n' + indent + decl, a + 1) >= 0) { return null; }
  const end = '\n' + indent + '}\n';
  const b = src.indexOf(end, a + 1);
  return b < 0 ? null : src.slice(a + 1, b + end.length);
}
/* The code alone: no // comments, no /// docs. */
function code(src) {
  return src.split('\n').map(function (l) { return l.replace(/^\s*\/\/.*$/, ''); }).join('\n');
}

const voiceCs = read('launcher', 'app', 'Voice.cs');
const sigCs = read('launcher', 'app', 'Signature.cs');
const updCs = read('launcher', 'app', 'Updater.cs');

// ============================================================ A. Voice.Bootstrap
const boot = method(voiceCs, 'static void Bootstrap()', '        ');
yes('A0 Voice.Bootstrap is in Voice.cs, once', boot !== null);
if (!boot) { done(); }
const b = code(boot);
const at = {
  download: b.indexOf('web.DownloadFile("https://go.microsoft.com/fwlink/p/?LinkId=2124703", exe);'),
  ask: b.indexOf('string why = Signature.MicrosoftRefusal(exe, out said);'),
  refused: b.indexOf('if (why.Length > 0)'),
  psi: b.indexOf('new ProcessStartInfo(exe, "/silent /install")'),
  start: b.indexOf('Process.Start(psi)')
};
yes('A1 it downloads the installer to exe, then asks Signature.MicrosoftRefusal about that same file',
    at.download > 0 && at.ask > at.download);
yes('A2 and only after that builds the start of exe and starts it',
    at.refused > at.ask && at.psi > at.refused && at.start > at.psi);
yes('A2 it starts nothing else: one Process.Start, one ProcessStartInfo',
    (b.match(/Process\.Start\(/g) || []).length === 1 && (b.match(/new ProcessStartInfo\(/g) || []).length === 1);

// The refusal branch, from its if to the line before the start.
const branch = at.refused > 0 && at.psi > at.refused ? b.slice(at.refused, at.psi) : '';
const close = branch.indexOf('\n                }\n');
const refusal = close > 0 ? branch.slice(0, close) : '';
yes('A3 a refusal says why, in the log, and that it was not run',
    /Say\("Voice: the WebView2 installer that was downloaded " \+ why \+\s*" It was not run, and voice is off until the next start\."\);/.test(refusal));
yes('A3 deletes the downloaded file and returns before anything is started',
    /File\.Delete\(exe\)/.test(refusal) && /return;\s*$/.test(refusal) && !/Process|Begin\(/.test(refusal));
yes('A3 and the delete failing is noted, not silent',
    /catch \(Exception ex\) \{ Swallow\.Note\("Voice\.Bootstrap, delete refused installer", ex\); \}/.test(refusal));
yes('A4 a pass is logged with what was checked before it runs',
    /Say\("Voice: the WebView2 installer is Microsoft's\. " \+ said\);/.test(b.slice(at.refused, at.psi)));

// Nothing else fetches or runs the installer (code, not the comments that
// say where it comes from).
const app = path.join(REPO_DIR, 'launcher', 'app');
const fetchers = fs.readdirSync(app).filter(function (f) {
  if (!/\.cs$/.test(f)) { return false; }
  const t = code(fs.readFileSync(path.join(app, f), 'utf8').split(CR).join(''));
  return /LinkId=2124703|MicrosoftEdgeWebview2Setup|EdgeWebView2Setup|WebView2RuntimeInstaller/i.test(t);
});
yes('A5 Voice.cs is the one launcher file that fetches the installer (' + fetchers.join(', ') + ')',
    fetchers.length === 1 && fetchers[0] === 'Voice.cs');
const installer = ['Setup-Thornswood.ps1', 'Install.bat', 'Setup.bat'].map(function (f) { return read('installer', f); })
  .concat([read('installer', 'setup', 'Bootstrap.cs')]).join('\n');
yes('A5 and the installer fetches and runs none of it',
    !/LinkId=2124703|MicrosoftEdgeWebview2Setup|go\.microsoft\.com\/fwlink/i.test(installer));

// =============================================== B. Signature.MicrosoftRefusal
const mr = method(sigCs, 'public static string MicrosoftRefusal(string path, out string said)', '        ');
yes('B0 Signature.MicrosoftRefusal(path, out said) is in Signature.cs, once', mr !== null);
if (!mr) { done(); }
const m = code(mr);
const pos = function (s) { return m.indexOf(s); };
const root = (/public const string MicrosoftRoot = "([0-9A-F]{40})";/.exec(sigCs) || [])[1] || '';
const signer = (/public const string MicrosoftSigner = "([^"]+)";/.exec(sigCs) || [])[1] || '';
const ours = (/public const string Root = "([0-9A-F]{40})";/.exec(sigCs) || [])[1] || '';
yes('B1 the pinned root is Microsoft Root Certificate Authority 2011, the name Microsoft Corporation',
    root === '8F43288AD272F3103B6FB1428485EA3014C0BCFE' && signer === 'Microsoft Corporation');
yes('B1 and not the Artifact Signing root, which signs for anybody with an account',
    ours.length === 40 && root !== ours);

yes('B2 the file is held open sharing only reads while it is checked',
    pos('new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)') > 0 && pos('using (fs)') > 0);
const trust = pos('uint rc = Trust(fs, path, true, chain, out stamped);');
const said = pos('if (rc != 0) return Said(rc);');
yes('B3 Windows decides first: WinVerifyTrust through Trust, revocation asked, and any no is a refusal',
    trust > 0 && said > trust);
yes('B3 revocation is dropped only when Microsoft cannot be reached, as Refusal does',
    /if \(rc == CERT_E_REVOCATION_FAILURE \|\| rc == CRYPT_E_REVOCATION_OFFLINE \|\|\s*rc == CRYPT_E_NO_REVOCATION_CHECK\)\s*\{\s*revocation = false;\s*chain\.Clear\(\);\s*rc = Trust\(fs, path, false, chain, out stamped\);\s*\}/.test(m));
const checks = {
  chain: pos('if (chain.Count < 2)'),
  root: pos('if (!String.Equals(root.Thumbprint, MicrosoftRoot, StringComparison.OrdinalIgnoreCase))'),
  name: pos('if (!String.Equals(leaf.GetNameInfo(X509NameType.SimpleName, false), MicrosoftSigner, StringComparison.Ordinal))'),
  usage: pos('if (!programs)')
};
yes('B4 then the chain Windows built: its last certificate must be MicrosoftRoot',
    checks.chain > said && checks.root > checks.chain &&
    pos('X509Certificate2 root = chain[chain.Count - 1];') > checks.chain &&
    pos('X509Certificate2 leaf = chain[0];') > checks.chain);
yes('B5 the signing certificate\'s own name must be exactly MicrosoftSigner, not merely contain it',
    checks.name > checks.root && !/IndexOf\(|Contains\(MicrosoftSigner|StartsWith\(MicrosoftSigner/.test(m));
yes('B6 and it must be for signing programs',
    checks.usage > checks.name && /if \(o\.Value == CodeSigning\) programs = true;/.test(m) &&
    /public const string CodeSigning = "1\.3\.6\.1\.5\.5\.7\.3\.3";/.test(sigCs));
const ok = m.indexOf('return "";');
yes('B7 it says yes in one place, after every check',
    ok > checks.usage && m.indexOf('return "";', ok + 1) < 0 &&
    (m.match(/return "[^"]/g) || []).length >= 5);
yes('B8 each refusal names what failed',
    /"is signed under " \+ root\.Subject \+ ", not under Microsoft's own root\."/.test(m) &&
    /"is signed under Microsoft's own root, but for " \+ leaf\.Subject \+ ", not for " \+ MicrosoftSigner \+ "\."/.test(m) &&
    /"is signed with a Microsoft certificate that is not for signing programs\."/.test(m));

yes('B9 the update check is untouched: Updater still asks Refusal for Thornswood\'s own signer',
    /Signature\.Refusal\(path, ExpectedSigner, out said\)/.test(updCs) && !/MicrosoftRefusal/.test(updCs));
yes('B9 and Refusal still pins the Artifact Signing root and Thornswood\'s identity',
    ours === 'F40042E2E5F7E8EF8189FED15519AECE42C3BFA2' &&
    /if \(!String\.Equals\(root\.Thumbprint, Root, StringComparison\.OrdinalIgnoreCase\)\)/.test(sigCs));
// Signature.cs stays C# 5 after #498's switch: Assert-PublishSigned.ps1
// compiles it with Add-Type, and C# inside PowerShell keeps the Framework
// compiler's C# 5 (Developer-Guide.md, Settled design). Voice.Bootstrap is
// launcher code, built by MSBuild at C# 13, so it is no longer held to C# 5.
yes('B10 C# 5 in Signature.cs, which Assert-PublishSigned.ps1 compiles with Add-Type: no $"", no ?., no nameof, no out var',
    !/\$"|\?\.[A-Za-z]|nameof\(|out var /.test(code(sigCs)));

// =========================================== C. the pins against the real chain
let pem = '';
try { pem = read('tests', 'fixtures', 'webview2-setup-chain.txt'); } catch (e) { pem = ''; }
const blocks = pem.match(/-----BEGIN CERTIFICATE-----[\s\S]*?-----END CERTIFICATE-----/g) || [];
yes('C0 the fixture holds the three certificates: signer, issuer, root', blocks.length === 3);
if (blocks.length !== 3 || typeof crypto.X509Certificate !== 'function') { done(); }
const certs = blocks.map(function (p) { return new crypto.X509Certificate(p); });
const leaf = certs[0], pca = certs[1], top = certs[2];
const cn = function (dn) { return ((/(?:^|\n)CN=([^\n]*)/.exec(dn) || [])[1] || ''); };
yes('C1 the root\'s SHA-1 thumbprint is MicrosoftRoot as Signature.cs writes it',
    top.fingerprint.replace(/:/g, '') === root);
yes('C1 and it is Microsoft Root Certificate Authority 2011, its own issuer',
    cn(top.subject) === 'Microsoft Root Certificate Authority 2011' && top.subject === top.issuer &&
    top.verify(top.publicKey));
yes('C2 the root signed the issuer (' + cn(pca.subject) + ')',
    pca.checkIssued(top) && pca.verify(top.publicKey));
yes('C2 and the issuer signed the signing certificate',
    leaf.checkIssued(pca) && leaf.verify(pca.publicKey));
yes('C3 the signing certificate\'s own name is MicrosoftSigner',
    cn(leaf.subject) === signer && /(?:^|\n)O=Microsoft Corporation(?:\n|$)/.test(leaf.subject));
yes('C3 and it is for signing programs', (leaf.keyUsage || []).indexOf('1.3.6.1.5.5.7.3.3') !== -1);
yes('C4 the Artifact Signing root is nowhere in this chain',
    certs.every(function (c) { return c.fingerprint.replace(/:/g, '') !== ours; }));

done();
