'use strict';
/*
  test-2352-gallery-removal.js

      node .\tests\test-2352-gallery-removal.js
      node .\tests\test-2352-gallery-removal.js <an older server.js>

  Issue #2352: a removed gallery submission could keep its file on disk,
  still served at /up/<name>, with nothing that ever deleted it, and a delete
  that failed was answered ok. site/data/site/privacy.md says a submission is
  removed on request.

  Against a real copy of site\server.js in a scratch folder on a spare port,
  as tests\test-gallery.js runs it, this proves:
    - removed with the file kept (the hub's Cancel, and the launcher's Delete
      and Take down, which never ask to delete it), the file is on disk, the
      answer says so, /up/<name> no longer serves it, and accepting it again by
      its name is refused;
    - removed with the file deleted, the file and its note are gone and
      /up/<name> answers no such file;
    - a delete that really fails (a folder where the file was) is answered
      500 with the error code and that the file is still there, the site's log
      says which file and the code, the entry is still off the queue, and
      /up/<name> does not serve it;
    - DELETE /api/upload/<name> says a failed delete the same way and keeps
      the file's note, and still deletes a file it can;
    - the hub's question says plainly what OK and Cancel do, and the hub shows
      the error when the site says the file could not be deleted.

  Give it the server.js from before #2352 to watch it fail. Nothing leaves the
  machine: no bot token, so standing() asks Discord nothing. Every copy is
  under the temp folder and removed at the end.
*/
const fs = require('fs');
const path = require('path');
const os = require('os');
const net = require('net');
const http = require('http');
const crypto = require('crypto');
const { spawn } = require('child_process');

const APP = path.join(__dirname, '..', 'site');
const SITE_SRC = process.argv[2] || path.join(APP, 'server.js');

let pass = 0, fail = 0;
function yes(what, cond, why) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what + (why ? '\n      ' + why : '')); }
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-2352-'));
const SECRET = crypto.randomBytes(32).toString('hex');
const PASSWORD = crypto.randomBytes(12).toString('hex');
const ADMIN_ID = '111111111111111111';

fs.copyFileSync(SITE_SRC, path.join(dir, 'server.js'));
fs.mkdirSync(path.join(dir, 'public'), { recursive: true });
fs.mkdirSync(path.join(dir, 'data'), { recursive: true });
fs.writeFileSync(path.join(dir, 'config.json'), JSON.stringify({
  password: PASSWORD,
  discord: { clientId: '', clientSecret: '', botToken: '', guildId: '', invite: '' },
  botKey: crypto.randomBytes(16).toString('hex'),
  admins: [ADMIN_ID],
  secret: SECRET,
  gameCheckPort: 1,
  onlineFile: path.join(dir, 'online.json')
}, null, 2));

const sign = (v) => crypto.createHmac('sha256', SECRET).update(String(v)).digest('hex').slice(0, 32);
const adminCookie = () => {
  const at = Date.now();
  const raw = ADMIN_ID + '|Admin|' + at + '|' + sign(ADMIN_ID + '|Admin|' + at);
  return 'twa=' + encodeURIComponent(raw);
};
const memberCookie = () =>
  'tw=' + crypto.createHash('sha256').update('thornswood:' + PASSWORD).digest('hex');

function freePort() {
  return new Promise((ok) => {
    const s = net.createServer();
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); });
  });
}
const wait = (ms) => new Promise((ok) => setTimeout(ok, ms));

let PORT = 0;
function ask(method, where, headers, body) {
  return new Promise((done) => {
    const data = body === undefined ? null : (Buffer.isBuffer(body) ? body : Buffer.from(body));
    const h = Object.assign({}, headers || {});
    if (data && h['content-length'] === undefined) h['content-length'] = data.length;
    // The site refuses a signed in write that names no page of its own (#1367).
    if (method !== 'GET' && h.origin === undefined &&
        Object.keys(h).some((k) => k.toLowerCase() === 'cookie')) h.origin = 'http://127.0.0.1:' + PORT;
    const req = http.request({ host: '127.0.0.1', port: PORT, method: method, path: where, headers: h, agent: false },
      (res) => {
        const chunks = [];
        res.on('data', (d) => { chunks.push(d); });
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let json = null;
          try { json = JSON.parse(text); } catch (e) { json = null; }
          done({ status: res.statusCode, body: text, json: json });
        });
      });
    req.on('error', (e) => done({ status: 0, body: String(e), json: null }));
    req.setTimeout(10000, () => req.destroy(new Error('timed out')));
    if (data) req.write(data);
    req.end();
  });
}

const PNG = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da6360000002000154a24f0e0000000049454e44ae426082', 'hex');
const readJson = (f) => { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { return null; } };
const UPDIR = path.join(dir, 'uploads');
const meta = () => readJson(path.join(UPDIR, 'uploads.json')) || {};
const pending = () => readJson(path.join(dir, 'data', 'gallery-pending.json')) || [];
const asJson = (cookie) => ({ cookie: cookie, 'content-type': 'application/json' });
/* A real failed delete on every system: a folder, with something in it, where
   the file was. unlink refuses a folder. */
function blockDelete(name) {
  const f = path.join(UPDIR, name);
  fs.unlinkSync(f);
  fs.mkdirSync(path.join(f, 'inside'), { recursive: true });
}

(async () => {
  PORT = await freePort();
  const srv = spawn(process.execPath, ['server.js'], {
    cwd: dir,
    env: Object.assign({}, process.env, {
      THORNSWOOD_DOCS_PORT: String(PORT),
      THORNSWOOD_DOCS_LOCAL: '1',
      THORNSWOOD_CHAT_DIR: path.join(dir, 'chat')
    })
  });
  let out = '';
  srv.stdout.on('data', (d) => { out += d; });
  srv.stderr.on('data', (d) => { out += d; });

  try {
    let up = false;
    for (let i = 0; i < 100 && !up; i++) {
      if (out.indexOf('listening on ') >= 0) { up = true; break; }
      if (srv.exitCode !== null) break;
      await wait(50);
    }
    if (!up) throw new Error('the scratch site never came up:\n' + out);

    const submit = async (name) => {
      const r = await ask('POST', '/api/gallery/submit?name=' + encodeURIComponent(name) + '&by=Someone',
                          { 'content-type': 'image/png', cookie: memberCookie() }, PNG);
      return r.json && r.json.name;
    };
    const remove = (name, deleteFile) => ask('DELETE', '/api/gallery/approved', asJson(adminCookie()),
      JSON.stringify(deleteFile === undefined ? { name: name } : { name: name, deleteFile: deleteFile }));
    const open = (name) => ask('GET', '/up/' + encodeURIComponent(name), { cookie: memberCookie() });

    // ---- kept: the hub's Cancel --------------------------------------------
    const a = await submit('kept.png');
    let r = await open(a);
    yes('a waiting submission is served at /up/<name> to a member, as before (' + r.status + ')', r.status === 200);
    r = await remove(a, false);
    yes('removed with the file kept, the answer is ok and says the file was not deleted',
        r.status === 200 && r.json && r.json.ok === true && r.json.removedPending === 1 && r.json.fileDeleted === false,
        r.status + ' ' + r.body);
    yes('  the file is still on disk, which is what staff chose', fs.existsSync(path.join(UPDIR, a)));
    yes('  and uploads.json marks it removed', !!(meta()[a] && meta()[a].removed));
    r = await open(a);
    yes('  and /up/<name> no longer serves it (' + r.status + ' ' + r.body + ')', r.status === 404 && /removed/.test(r.body));
    r = await ask('POST', '/api/gallery/approve', asJson(adminCookie()), JSON.stringify({ name: a }));
    yes('  and accepting it again by its name is refused (' + r.status + ')', r.status === 409);
    const pub = await ask('GET', '/shot/' + encodeURIComponent(a));
    yes('  and /shot does not serve it either (' + pub.status + ')', pub.status === 404);

    // ---- kept: the launcher's Take down, which never sends deleteFile -------
    const b = await submit('taken-down.png');
    await ask('POST', '/api/gallery/approve', asJson(adminCookie()), JSON.stringify({ name: b }));
    r = await ask('GET', '/shot/' + encodeURIComponent(b));
    yes('an accepted submission is public at /shot (' + r.status + ')', r.status === 200);
    r = await remove(b);
    yes('taken down the launcher way, with no deleteFile, it comes off the gallery',
        r.status === 200 && r.json && r.json.removedApproved === 1);
    r = await ask('GET', '/shot/' + encodeURIComponent(b));
    const r2 = await open(b);
    yes('  and neither /shot nor /up/<name> serves it (' + r.status + ', ' + r2.status + ')', r.status === 404 && r2.status === 404);

    // ---- deleted -------------------------------------------------------------
    const c = await submit('deleted.png');
    r = await remove(c, true);
    yes('removed with the file deleted, the answer says the file was deleted',
        r.status === 200 && r.json && r.json.ok === true && r.json.fileDeleted === true, r.status + ' ' + r.body);
    yes('  the file and its note are gone', !fs.existsSync(path.join(UPDIR, c)) && !meta()[c]);
    r = await open(c);
    yes('  and /up/<name> answers no such file (' + r.status + ')', r.status === 404);

    // ---- a delete that fails -------------------------------------------------
    const d = await submit('stuck.png');
    blockDelete(d);
    const logFrom = out.length;
    r = await remove(d, true);
    yes('a delete that fails is answered 500, not ok (' + r.status + ')', r.status === 500 && r.json && r.json.ok === false);
    yes('  saying the file is still there and the error code (' + (r.json && r.json.code) + ')',
        !!r.json && r.json.fileKept === true && typeof r.json.code === 'string' && r.json.code.length > 0 &&
        /could not be deleted/.test(String(r.json.error || '')));
    yes('  the entry is still off the queue', !pending().some((x) => x.name === d));
    const line = out.slice(logFrom).split('\n').find((l) => l.indexOf('gallery-retention') >= 0) || '';
    let doc = null;
    try { doc = JSON.parse(line.slice(line.indexOf('{'))); } catch (e) { }
    yes('  the site\'s log says which file and the code, and nothing it holds (' + line.trim() + ')',
        !!doc && doc.event === 'delete-failed' && doc.file === d && doc.code === r.json.code &&
        Object.keys(doc).sort().join(',') === 'code,event,file');
    r = await open(d);
    yes('  and /up/<name> does not serve it (' + r.status + ')', r.status === 404 && /removed/.test(r.body));

    // ---- DELETE /api/upload/<name> ---------------------------------------------
    const upload = async (name) => {
      const x = await ask('POST', '/api/upload?name=' + encodeURIComponent(name), { 'content-type': 'text/plain', cookie: memberCookie() },
                          'a log line\n');
      return x.json && x.json.name;
    };
    const e = await upload('stuck.log');
    blockDelete(e);
    r = await ask('DELETE', '/api/upload/' + encodeURIComponent(e), { cookie: adminCookie() });
    yes('DELETE /api/upload/<name> answers a failed delete 500 with its code (' + r.status + ')',
        r.status === 500 && r.json && r.json.ok === false && r.json.fileKept === true && typeof r.json.code === 'string');
    yes('  and keeps the file\'s note, so the uploads list still shows what is on disk', !!meta()[e]);
    const f = await upload('fine.log');
    r = await ask('DELETE', '/api/upload/' + encodeURIComponent(f), { cookie: adminCookie() });
    yes('  and still deletes a file it can (' + r.status + ')', r.status === 200 && !fs.existsSync(path.join(UPDIR, f)) && !meta()[f]);

    // ---- the hub's words ------------------------------------------------------
    const hub = fs.readFileSync(path.join(APP, 'public', 'hub.js'), 'utf8');
    yes('the hub says plainly what OK and Cancel do with the file',
        /OK deletes it\./.test(hub) && /Cancel keeps the file on the site\\'s disk\. It is not shown anywhere/.test(hub) &&
        hub.indexOf('Cancel keeps the file on disk.') < 0);
    yes('and shows the site\'s error when the file could not be deleted',
        /if \(a && a\.ok === false\) alert\(a\.error/.test(hub));
  } catch (err) {
    fail++;
    console.log('FAIL  the harness itself threw: ' + (err && err.stack ? err.stack : err));
  }

  await new Promise((ok) => {
    srv.on('exit', ok);
    try { srv.kill(); } catch (e) { ok(); }
    setTimeout(ok, 3000);
  });
  try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { }
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})();
