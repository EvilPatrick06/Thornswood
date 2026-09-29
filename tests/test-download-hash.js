// test-download-hash.js
//
// The Downloads page prints the installer's SHA-256 beside its size and date.
// VirusTotal report links, over-cap waiting copy, and the SmartScreen /
// publisher warn above the button are gone: Setup is Authenticode-signed,
// and the site no longer promises a VT report or a Downloads warn block.
//
// THREE HALVES, AND THIS RUNS ALL THREE, because the value has to survive the
// whole trip and a field name spelt differently at any one stop drops it
// silently:
//
//   Publish-Installer.ps1 hashes the exe and writes sha256 into files.json.
//     Its own lines are lifted and run in PowerShell against a temp file.
//   server.js listFiles() passes it on to /api/public. Lifted and run against
//     a temp folder with a files.json in it.
//   home.html builds the download block from /api/public. The whole /downloads
//     branch of the page script is lifted and run with the fetch stubbed.
//
// Read only. Writes to a temp folder and nowhere else.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

const CR = String.fromCharCode(13);
const read = (p) => fs.readFileSync(path.join(REPO_DIR, p), 'utf8').split(CR).join('');
const publisher = read('scripts/release/Publish-Installer.ps1');
const server = read(path.join('site', 'server.js'));
const page = read(path.join('site', 'public', 'home.html'));

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-download-hash-'));
const sha = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

async function main() {
  // -------------------------------------------------- Publish-Installer.ps1
  const hashLine = (/^\$(\w+) = \(Get-FileHash -LiteralPath \$exeItem\.FullName -Algorithm SHA256\)\.Hash$/m
    .exec(publisher) || [])[0];
  yes('Publish-Installer hashes the exe it publishes', !!hashLine);

  const from = publisher.indexOf('if ($single) {\n  $meta = @{');
  const to = publisher.indexOf('\n$b64 = ', from);
  const metaBlock = (from >= 0 && to > from) ? publisher.slice(from, to) : '';
  yes('the files.json entries are built in one block that can be lifted', !!metaBlock);

  const exeBlocks = metaBlock.match(/\$exeOut = @\{[^}]*\}/g) || [];
  yes('there is an exe entry for the one file build and one for the pair',
      exeBlocks.length === 2);
  const hashVar = hashLine ? /^\$(\w+)/.exec(hashLine)[1] : '(none)';
  yes('and both of them carry the hash as sha256',
      exeBlocks.length === 2 && exeBlocks.every((b) =>
        new RegExp('\\bsha256\\s*=\\s*\\$' + hashVar + '\\b').test(b)));

  if (hashLine && metaBlock) {
    /*
      Run for real rather than read, so the key survives ConvertTo-Json the way
      the script sends it and the value is the hash of the file and not of its
      name. Both builds, one file and the pair, in one PowerShell start.
    */
    const exe = path.join(tmp, 'Thornswood-Setup.exe');
    const bytes = Buffer.from('not really an installer, but bytes all the same\n');
    fs.writeFileSync(exe, bytes);
    const ps = path.join(tmp, 'run.ps1');
    fs.writeFileSync(ps, [
      "$ErrorActionPreference = 'Stop'",
      "$exeItem = Get-Item -LiteralPath '" + exe.replace(/'/g, "''") + "'",
      hashLine,
      "$Version = 'launcher 1.2.3'",
      "$exeOut = 'Thornswood-Setup.exe'",
      "$zipOut = 'Thornswood-Setup.zip'",
      'foreach ($single in @($true, $false)) {',
      metaBlock,
      '  $meta | ConvertTo-Json -Depth 4 -Compress',
      '}',
      ''
    ].join('\r\n'));
    // Without PSModulePath, each shell finds its own modules. Started from a
    // pwsh 7 session, Windows PowerShell inherits pwsh's module folders and
    // then cannot find Get-FileHash at all, which is a fault in the harness and
    // not in the script.
    const env = Object.assign({}, process.env);
    for (const k of Object.keys(env)) if (k.toLowerCase() === 'psmodulepath') delete env[k];
    let run = null;
    for (const shell of ['pwsh', 'powershell']) {
      run = spawnSync(shell, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', ps], { encoding: 'utf8', env: env });
      if (!run.error) break;
    }
    if (run.error) {
      console.log('SKIP  no PowerShell here to run Publish-Installer\'s lines');
    } else {
      const lines = String(run.stdout || '').split(/\r?\n/).filter((l) => l.trim().startsWith('{'));
      yes('the lifted lines ran', run.status === 0 && lines.length === 2);
      if (run.status !== 0) console.log(run.stderr);
      const want = sha(bytes);
      for (let i = 0; i < lines.length; i++) {
        let meta = {};
        try { meta = JSON.parse(lines[i]); } catch (e) { }
        const e = meta['Thornswood-Setup.exe'] || {};
        const kind = i === 0 ? 'one file build' : 'pair';
        yes(kind + ': files.json gets the exe\'s SHA-256 under sha256',
            String(e.sha256 || '').toLowerCase() === want);
        yes(kind + ': and the label, version and note are still there',
            e.label === 'Thornswood installer' && e.version === 'launcher 1.2.3' && !!e.note);
      }
    }
  }

  // ---------------------------------------------------- server.js listFiles
  const lf = /\nfunction listFiles\(\) \{\n[\s\S]*?\n\}\n/.exec(server);
  yes('listFiles is in server.js', !!lf);
  if (lf) {
    const files = path.join(tmp, 'files');
    fs.mkdirSync(files);
    const exeBytes = Buffer.from('the exe');
    const good = sha(exeBytes);
    fs.writeFileSync(path.join(files, 'Thornswood-Setup.exe'), exeBytes);
    fs.writeFileSync(path.join(files, 'Thornswood-Setup.zip'), 'the zip');
    fs.writeFileSync(path.join(files, 'notes.txt'), 'no entry in files.json');
    const meta = {
      // Get-FileHash writes upper case.
      'Thornswood-Setup.exe': { label: 'Thornswood installer',
        version: 'launcher 1.2.3', sha256: good.toUpperCase() },
      'Thornswood-Setup.zip': { label: 'payload', hidden: true,
        sha256: '"><img src=x onerror=alert(1)>' }
    };
    fs.writeFileSync(path.join(files, 'files.json'), JSON.stringify(meta));
    const jsonFile = (p, fb) => { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return fb; } };
    const listFiles = new Function('fs', 'path', 'FILES', 'jsonFile',
      lf[0] + '\nreturn listFiles;')(fs, path, files, jsonFile);
    const list = () => {
      const by = {};
      for (const f of listFiles()) by[f.name] = f;
      return by;
    };
    const by = list();
    const e = by['Thornswood-Setup.exe'] || {};
    yes('/api/public carries the exe\'s sha256', e.sha256 === good);
    yes('in lower case', e.sha256 === good.toLowerCase());
    yes('a value that is not a SHA-256 does not go out',
        (by['Thornswood-Setup.zip'] || {}).sha256 === '');
    yes('a file files.json says nothing about gets an empty one',
        (by['notes.txt'] || {}).sha256 === '');
    yes('and nothing that was there before is lost',
        e.label === 'Thornswood installer' && e.version === 'launcher 1.2.3' &&
        e.size === exeBytes.length && e.hidden === false &&
        (by['Thornswood-Setup.zip'] || {}).hidden === true);

    // VirusTotal fields no longer go out on /api/public.
    yes('listFiles does not emit vt', !('vt' in e));
    yes('listFiles does not emit vtSkipped', !('vtSkipped' in e));
    yes('listFiles has no VT_CAP constant any more', !/VT_CAP/.test(lf[0]));

    // Stale vtUrl / vtSkipped in files.json must not leak onto the API.
    const withMeta = (extra) => {
      const m = JSON.parse(JSON.stringify(meta));
      Object.assign(m['Thornswood-Setup.exe'], extra);
      fs.writeFileSync(path.join(files, 'files.json'), JSON.stringify(m));
      return list()['Thornswood-Setup.exe'] || {};
    };
    const leaked = withMeta({
      vtUrl: 'https://www.virustotal.com/gui/file/' + good,
      vtSubmittedAt: '2026-09-27 03:10',
      vtSkipped: true,
      vtSkipReason: 'key out of quota'
    });
    yes('stale vtUrl in files.json does not appear on the API', !('vt' in leaked) && leaked.sha256 === good);
    yes('stale vtSkipped in files.json does not appear on the API', !('vtSkipped' in leaked));
    yes('and a skip-reason string never goes out either',
        !('vtSkipReason' in leaked) && !JSON.stringify(leaked).includes('quota'));
    fs.writeFileSync(path.join(files, 'files.json'), JSON.stringify(meta));
  }

  // ------------------------------------------------ home.html /downloads
  const a = page.indexOf("} else if (here === '/downloads') {");
  const b = page.indexOf("} else if (here === '/report') {", a);
  const body = (a >= 0 && b > a) ? page.slice(a + "} else if (here === '/downloads') {".length, b) : '';
  const escSrc = (/function esc\(s\)\{[\s\S]*?\}\); \}/.exec(page) || [''])[0];
  yes('the downloads builder and esc are both on the page', !!body && !!escSrc);
  if (body && escSrc) {
    const esc = new Function(escSrc + '\nreturn esc;')();
    function render(payload) {
      let html = null;
      const fetch = () => Promise.resolve({ json: () => payload });
      new Function('fetch', 'show', 'esc', body)(fetch, (h) => { html = h; }, esc);
      return new Promise((r) => setImmediate(() => r(html || '')));
    }
    const H = sha(Buffer.from('thornswood'));
    const exe = (size, hash, extra) => Object.assign({ name: 'Thornswood-Setup.exe', size: size,
      at: 2, hidden: false, label: 'Thornswood installer', version: '2026-09-24 01:00',
      note: '', sha256: hash }, extra || {});
    const zip = (hidden) => ({ name: 'Thornswood-Setup.zip', size: 385154603,
      at: 1, hidden: hidden, label: 'payload', version: '', note: '', sha256: '' });
    const SIZE = /\d (KB|MB|GB)\b/;
    const small = (html) => {
      const m = html.match(/<p class="also faintly">[\s\S]*?<\/p>/g) || [];
      return m.filter((p) => SIZE.test(p))[0] || '';
    };

    const cases = [
      ['one file build', [exe(560000000, H)]],
      ['stub with a hidden payload, which is what the site serves now',
        [exe(400000, H), zip(true)]],
      ['stub with the payload beside it', [exe(400000, H), zip(false)]]
    ];
    for (const c of cases) {
      const html = await render({ files: c[1] });
      const p = small(html);
      yes(c[0] + ': the page renders', !!html && !/Could not load it/.test(html));
      yes(c[0] + ': the SHA-256 is printed', p.indexOf('SHA-256') >= 0 && p.indexOf(H) >= 0);
      yes(c[0] + ': beside the size and the date',
          SIZE.test(p) && p.indexOf('9-24-2026 1:00 AM') >= 0 && p.indexOf(H) > p.indexOf('9-24-2026'));
      yes(c[0] + ': with no VirusTotal report line',
          !/virustotal/i.test(html) && !/VirusTotal report/.test(html));
      yes(c[0] + ': and no SmartScreen / publisher warn above the button',
          !/SmartScreen/i.test(html) && !/Why this happens/.test(html) &&
          !/signed as /.test(html) && !/Unknown publisher/i.test(html));
    }

    const none = await render({ files: [exe(560000000, '')] });
    yes('no hash on the site: the size and date still show', / MB/.test(small(none)));
    yes('and no SHA-256 line and nothing about VirusTotal at all',
        none.indexOf('SHA-256') < 0 && !/virustotal/i.test(none));
    const old = await render({ files: [exe(560000000, undefined)] });
    yes('a site older than this, with no sha256 field at all, shows no hash either',
        old.indexOf('SHA-256') < 0 && !/virustotal/i.test(old) && / MB/.test(small(old)));
    const bad = await render({ files: [exe(560000000, '"><img src=x onerror=alert(1)>')] });
    yes('a value that is not a SHA-256 is never put in the page',
        bad.indexOf('<img') < 0 && bad.indexOf('SHA-256') < 0 && !/virustotal/i.test(bad));

    // Stale vt fields from an older API must not paint a report on the page.
    const staleVt = await render({ files: [exe(560000000, H, {
      vt: 'https://www.virustotal.com/gui/file/' + H,
      vtSkipped: true
    })] });
    yes('a stale vt field on the payload is ignored',
        staleVt.indexOf(H) >= 0 && !/virustotal\.com/i.test(staleVt) &&
        !/VirusTotal report/.test(staleVt));

    yes('the page has no VT_CAP constant any more', !/VT_CAP/.test(body));
    yes('and does not mention VirusTotal\'s 650 MB upload cap',
        !/650 MB upload cap/.test(body) && !/VirusTotal/i.test(body));
  }

  // ----------------------------------------------- what the entry ruled out
  yes('the detection name appears at most once on the page',
      (page.match(/Wacatac/g) || []).length <= 1);
  yes('nobody is told to upload the file to VirusTotal themselves',
      !/(put|upload|drop) (the|this) file (in)?to VirusTotal/i.test(page));
  yes('nobody is told to switch Defender off',
      !/(switch|turn)(ing)? off[^.<]{0,40}Defender|Defender[^.<]{0,40}(switch|turn)(ed)? off/i.test(page));
  yes('the page does not claim the installer is unsigned',
      !/not signed yet/i.test(page) && !/publisher Unknown/i.test(page));
}

main().catch((e) => { fail++; console.log('FAIL  ' + (e && e.stack || e)); }).then(() => {
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { }
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
});
