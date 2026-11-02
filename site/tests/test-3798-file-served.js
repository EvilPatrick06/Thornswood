/*
  test-3798-file-served.js

      node .\site\tests\test-3798-file-served.js

  The site's /file/ route served any name in its downloads folder. A read only
  diagnostic script put there by hand on the box, naming a staff
  member and the game server's address, went to anyone who asked for it by
  name: hidden only kept it off the Downloads page (#3798).

  Now files.json is the list of what is published. /file/ serves a name only
  when files.json lists it and does not mark it hidden, or it is a listed
  payload zip (hidden because the setup program fetches it itself), plus
  files.json itself, which Ship's installer gate reads. Anything else answers
  404, and the Downloads list and /api/payload hold to the same rule, so
  neither offers a name that 404s.

  The real /file/ route, listFiles and /api/payload are lifted out of
  site\server.js by text and run against a temp downloads folder with a stray
  script in it. Nothing is read from or written to the site's own folders.
*/
const REPO_DIR = require('path').join(__dirname, '..', '..'); // this harness is in site\tests\, the repository is two folders up
const fs = require('fs');
const path = require('path');
const os = require('os');
const http = require('http');
const crypto = require('crypto');
const siteFiles = require('../../tests/site-files');

const CR = String.fromCharCode(13);
const src = siteFiles.source().split(CR).join('');
const CSP_HEADER = JSON.parse(src.match(/const CSP_HEADER = ("[^"\r\n]*");/)[1]);
// send() names it beside the CSP (#2762).
const PERMISSIONS_POLICY = src.match(/const PERMISSIONS_POLICY = '([^'\r\n]*)';/)[1];

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// From the first '{' at or after `at` to the brace that closes it.
function block(at) {
  const b = src.indexOf('{', at);
  let d = 0;
  for (let i = b; i < src.length; i++) {
    if (src[i] === '{') d++;
    else if (src[i] === '}') { d--; if (d === 0) return i + 1; }
  }
  throw new Error('unbalanced braces in site/server.js');
}
function grab(head) {
  const at = src.indexOf(head);
  return at < 0 ? '' : src.slice(at, block(at));
}
// A route inside handle(): from `first` to the end of the if block `guard`.
function route(first, guard) {
  const at = src.indexOf(first);
  if (at < 0) return '';
  const g = src.indexOf(guard, at);
  return g < 0 ? '' : src.slice(at, block(g));
}

// ---- what the lifted code expects to find around it ------------------------
const FILES = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-3798-files-'));
const JSON_AT = src.indexOf('const jsonFile = (p, fallback) => {');
yes('server.js still has jsonFile', JSON_AT >= 0);
const jsonFile = eval('(' + src.slice(src.indexOf('(', JSON_AT), block(JSON_AT)) + ')');
const servedSrc = grab('function payloadZip(') + '\n' + grab('function downloadServed(');
yes('server.js has the one rule for what is served, downloadServed', /function downloadServed\(/.test(servedSrc));
eval(servedSrc);
eval(grab('function cspFor('));
eval(grab('function send('));
eval(grab('function rangeReply('));
// The exe's Release copy is #3686's and has its own harness; no copy here.
function releaseInstallerCopy() { return ''; }

const fileSrc = route('const dl = p.match(', "if (dl && req.method === 'GET')");
yes('the /file/ route is where this expects it', !!fileSrc);
yes('and asks downloadServed before it serves anything', /downloadServed\(dl\[1\], meta\)/.test(fileSrc));
const fileRoute = eval('(function (p, req, res, head) {\n' + fileSrc + '\n})');

const lf = grab('function listFiles(');
yes('listFiles is in server.js', !!lf);
eval(lf);

const payloadSrc = route("if (route === '/api/payload' && req.method === 'GET') {",
                         "if (route === '/api/payload' && req.method === 'GET') {");
yes('the /api/payload route is where this expects it', !!payloadSrc);
function payload() {
  let sent = null;
  const sendJson = (r, code, obj) => { sent = obj; return true; };
  eval('(function (route, req, res) {\n' + payloadSrc + '\n})')('/api/payload', { method: 'GET' }, {});
  return sent;
}

// ---- the folder: what a publish leaves, and a stray beside it --------------
const STRAY = 'Check-One-Machine.ps1';
const strayBody = '# Give the whole output to a staff member\n$box = "203.0.113.7"\n';
const exe = Buffer.from('the exe');
const zip = Buffer.from('the payload zip');
const notes = Buffer.from('a listed download people may take');
const hiddenNote = Buffer.from('listed, hidden, not the payload');
fs.writeFileSync(path.join(FILES, STRAY), strayBody);
fs.writeFileSync(path.join(FILES, 'Thornswood-Setup.exe'), exe);
fs.writeFileSync(path.join(FILES, 'Thornswood-Setup.zip'), zip);
fs.writeFileSync(path.join(FILES, 'Notes.txt'), notes);
fs.writeFileSync(path.join(FILES, 'Staff-Only.txt'), hiddenNote);
fs.writeFileSync(path.join(FILES, 'Thornswood-Setup-20260901-0900.zip'), Buffer.from('an unlisted older zip'));
fs.mkdirSync(path.join(FILES, 'Listed-Folder'));
const zipSha = crypto.createHash('sha256').update(zip).digest('hex');
const meta = {
  'Thornswood-Setup.exe': { label: 'Thornswood installer', version: '10-26-2026 6:24 PM' },
  'Thornswood-Setup.zip': { label: 'payload', hidden: true, sha256: zipSha.toUpperCase() },
  'Notes.txt': { label: 'Notes' },
  'Staff-Only.txt': { label: 'Staff only', hidden: true },
  'Listed-Folder': { label: 'a folder is never a download' }
};
fs.writeFileSync(path.join(FILES, 'files.json'), JSON.stringify(meta));

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = decodeURIComponent(url.pathname);
  const head = req.method === 'HEAD';
  if (head) req.method = 'GET';
  try { fileRoute(p, req, res, head); }
  catch (e) {
    if (!res.headersSent) { res.writeHead(500); res.end(String(e && e.message)); }
    return;
  }
  if (!res.headersSent) { res.writeHead(404); res.end(); }
});

function ask(method, p) {
  return new Promise((resolve) => {
    const req = http.request({ host: '127.0.0.1', port: server.address().port, path: p,
                               method: method, agent: false }, (res) => {
      const parts = [];
      res.on('data', (d) => parts.push(d));
      res.on('end', () => resolve({ code: res.statusCode, h: res.headers, body: Buffer.concat(parts) }));
    });
    req.on('error', (e) => resolve({ code: 0, h: {}, body: Buffer.alloc(0), error: e.message }));
    req.end();
  });
}
const at = (name) => '/file/' + encodeURIComponent(name);

async function main() {
  await new Promise((r) => server.listen(0, '127.0.0.1', r));

  // ---- the issue's done-when ---------------------------------------------
  const stray = await ask('GET', at(STRAY));
  yes('a file files.json does not list answers 404 (the stray script)', stray.code === 404);
  yes('  and not one byte of it goes out', !stray.body.toString().includes('203.0.113.7'));
  yes('  a HEAD for it is 404 too', (await ask('HEAD', at(STRAY))).code === 404);
  yes('  and so is its name in another case', (await ask('GET', at(STRAY.toUpperCase()))).code === 404);

  // Listed but hidden, and not the payload: what a stray would become if
  // somebody listed it to keep it off the page. Still not served.
  yes('a listed file marked hidden that is not the payload answers 404',
      (await ask('GET', at('Staff-Only.txt'))).code === 404);
  yes('an unlisted payload zip answers 404', (await ask('GET', at('Thornswood-Setup-20260901-0900.zip'))).code === 404);
  yes('a listed folder answers 404', (await ask('GET', at('Listed-Folder'))).code === 404);
  yes('a name with a path in it answers 404', (await ask('GET', '/file/..%2Fserver.js')).code === 404);

  // ---- what a publish puts there is still served --------------------------
  const e = await ask('GET', at('Thornswood-Setup.exe'));
  yes('the installer files.json lists is served', e.code === 200 && e.body.equals(exe));
  const z = await ask('GET', at('Thornswood-Setup.zip'));
  yes('the payload zip is served though files.json hides it, for the setup program', z.code === 200 && z.body.equals(zip));
  const n = await ask('GET', at('Notes.txt'));
  yes('any other listed, visible download is served', n.code === 200 && n.body.equals(notes));
  const list = await ask('GET', at('files.json'));
  yes('files.json itself is served, where Read-SiteDownloads reads it',
      list.code === 200 && JSON.parse(list.body.toString())['Thornswood-Setup.exe'].label === 'Thornswood installer');

  // ---- the Downloads list holds to the same rule --------------------------
  const by = {};
  for (const f of listFiles()) by[f.name] = f;
  yes('the Downloads list leaves the stray out entirely', !(STRAY in by));
  yes('  and the listed hidden file that is not served', !('Staff-Only.txt' in by));
  yes('  and the unlisted zip, and the folder, and files.json',
      !('Thornswood-Setup-20260901-0900.zip' in by) && !('Listed-Folder' in by) && !('files.json' in by));
  yes('it still lists the installer, shown', by['Thornswood-Setup.exe'] && by['Thornswood-Setup.exe'].hidden === false);
  yes('  the payload, hidden', by['Thornswood-Setup.zip'] && by['Thornswood-Setup.zip'].hidden === true);
  yes('  and the other listed download, shown', by['Notes.txt'] && by['Notes.txt'].hidden === false);

  // ---- and so does /api/payload ------------------------------------------
  const pay = payload() || {};
  yes('/api/payload names the listed zip, not the unlisted one', pay.name === 'Thornswood-Setup.zip' &&
      pay.url === '/file/Thornswood-Setup.zip' && pay.sha256 === zipSha);
  fs.unlinkSync(path.join(FILES, 'Thornswood-Setup.zip'));
  const none = payload() || {};
  yes('with only an unlisted zip there, it names none, so no setup program is sent to a 404',
      JSON.stringify(none) === '{}');

  server.close();
  try { fs.rmSync(FILES, { recursive: true, force: true }); } catch (e) { }
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}

main().catch((e) => {
  console.log('FAIL  ' + (e && e.stack || e));
  process.exit(1);
});
