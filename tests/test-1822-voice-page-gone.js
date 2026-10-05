/*
  test-1822-voice-page-gone.js

      node tests\test-1822-voice-page-gone.js

  #1822. The voice service served a plain browser page of its own from
  voice\public at /, so https://thornswood.net/voice/ and /voice-dev/. It
  opened its socket with no join token and had no way to get one: it holds
  no Discord ticket and talks to no launcher. Since every join needs a token
  (#1303) it could never get in, and since #1337 its handshake was refused
  before it opened. Nothing linked to it. The two clients are the launcher's
  voice page and the game's overlay, both loaded off disk. So the page went,
  along with the route that served it and the Origin rule that let a page on
  this host open a socket.

  This starts the real service in a temp folder that still holds a public
  folder with both files in it, the way a box installed before this does,
  and proves:

    nothing is served at /, at the page's own address with its query, or at
    either file's name, and /health still answers;
    a socket opened the way the page opened it (Origin this host, through
    Caddy, no token) is refused before any 101, and so is one from a page on
    this host that does hold a good token;
    the two clients' way in (Origin null or file://, a good token) still
    joins;

  and, read from the tree: voice\public is gone, Install-Voice.ps1 neither
  packs nor sends nor checks for it, making the dev instance copies no page
  from live, the build parses no file there, no harness reads it, and the
  only files that open a socket to the service are the launcher's voice
  page and the game's chat overlay.

  VOICE points it at another copy of voice-server.js, which is how it was
  shown to fail on the code before the change. Writes only to a temp folder,
  on a loopback port the system hands out.
*/
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const os = require('os');
const path = require('path');
const net = require('net');
const http = require('http');
const crypto = require('crypto');
const { spawn, execFileSync } = require('child_process');

const CR = String.fromCharCode(13);
const VOICE = process.env.VOICE || path.join(REPO_DIR, 'voice', 'voice-server.js');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function read(rel) {
  try { return fs.readFileSync(path.join(REPO_DIR, rel), 'utf8').split(CR).join(''); } catch (e) { return ''; }
}

/* A port of this run's own (#1703): the system names one nothing holds. */
function freePort(host) {
  return new Promise((ok, bad) => {
    const s = net.createServer();
    s.on('error', bad);
    s.listen(0, host, () => { const p = s.address().port; s.close(() => ok(p)); });
  });
}
/* Waits for srv's own "listening on ...:port" line, or says why it stopped. */
function listening(srv, port) {
  return new Promise((ok, bad) => {
    let out = '';
    const said = (d) => {
      out += d;
      const m = /\[voice\] listening on \S+:(\d+)/.exec(out);
      if (m && Number(m[1]) === port) { end(null); }
    };
    const more = (d) => { out += d; };
    const gone = (code) => end(new Error((/EADDRINUSE/.test(out) ? 'something else already holds port ' + port + ', so ' : '') +
                                         'the voice service stopped (exit ' + code + ') before it was listening. It printed:\n' + out));
    const late = setTimeout(() => end(new Error('the voice service did not say it was listening on ' + port +
                                                ' within fifteen seconds. It printed:\n' + out)), 15000);
    function end(err) {
      clearTimeout(late);
      srv.stdout.removeListener('data', said);
      srv.stderr.removeListener('data', more);
      srv.removeListener('exit', gone);
      if (err) { bad(err); } else { ok(); }
    }
    srv.stdout.on('data', said);
    srv.stderr.on('data', more);
    srv.on('exit', gone);
  });
}

/* A token signed with the key beside the copy, the way the service signs
   them (#1303); one opens one connection (#1322, #1337). */
const KEY = crypto.randomBytes(32).toString('hex');
function tokenFor(pid) {
  const body = 'v2.' + pid + '.' + Date.now() + '.' + crypto.randomBytes(16).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return body + '.' + crypto.createHmac('sha256', KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/* A masked text frame, the way a browser sends one. */
function textFrame(obj) {
  const data = Buffer.from(JSON.stringify(obj), 'utf8');
  const head = Buffer.from([0x81, 0x80 | data.length]);
  const key = crypto.randomBytes(4);
  const body = Buffer.from(data);
  for (let i = 0; i < body.length; i++) { body[i] ^= key[i & 3]; }
  return Buffer.concat([head, key, body]);
}

/* A raw handshake with the headers given, with a token or none:
   { status, joined }. */
function knock(port, headers, pid, withToken) {
  return new Promise((ok) => {
    const s = net.connect(port, '127.0.0.1');
    const me = { status: 0, joined: false };
    let buf = Buffer.alloc(0);
    s.on('connect', () => {
      let h = 'GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n' +
              'Sec-WebSocket-Key: ' + crypto.randomBytes(16).toString('base64') + '\r\n';
      if (withToken) { h += 'Sec-WebSocket-Protocol: thornswood, ' + tokenFor(pid) + '\r\n'; }
      for (const k of Object.keys(headers)) { h += k + ': ' + headers[k] + '\r\n'; }
      s.write(h + '\r\n');
    });
    s.on('data', (d) => {
      buf = Buffer.concat([buf, d]);
      if (!me.status) {
        const i = buf.indexOf('\r\n\r\n');
        if (i < 0) { return; }
        me.status = Number((/^HTTP\/1\.1 (\d+)/.exec(buf.slice(0, i).toString()) || [])[1] || 0);
        buf = buf.slice(i + 4);
        if (me.status === 101) { s.write(textFrame({ t: 'join', profileId: pid, name: 'P' + pid })); }
      }
      if (buf.indexOf('"welcome"') >= 0) { me.joined = true; }
    });
    s.on('error', () => { });
    setTimeout(() => { s.destroy(); ok(me); }, 400);
  });
}

/* A plain GET as Caddy passes it on: { status, body }. */
function get(port, route) {
  return new Promise((ok) => {
    const req = http.get({ host: '127.0.0.1', port, path: route,
                           headers: { Host: 'thornswood.net', 'X-Forwarded-For': '203.0.113.7' } }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (d) => { body += d; });
      res.on('end', () => ok({ status: res.statusCode, body }));
    });
    req.on('error', () => ok({ status: 0, body: '' }));
  });
}

(async () => {
  // ------------------------------------------------------- from the tree
  console.log('the tree:');
  let tracked = [];
  try {
    tracked = execFileSync('git', ['-C', REPO_DIR, 'ls-files'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
      .split('\n').filter(Boolean);
  } catch (e) { tracked = []; }
  yes('git lists the tree (' + tracked.length + ' files)', tracked.length > 100);
  yes('nothing is left in voice/public', !tracked.some((f) => f.indexOf('voice/public/') === 0) &&
      !fs.existsSync(path.join(REPO_DIR, 'voice', 'public', 'index.html')) &&
      !fs.existsSync(path.join(REPO_DIR, 'voice', 'public', 'voice.js')));

  const inst = read('scripts/deploy/Install-Voice.ps1');
  const paths = /New-ThornswoodArtifact -Component voice [^\n]*-Paths ([^\n`]*)/.exec(inst);
  yes('Install-Voice.ps1 packs the service and headlines.js and nothing else',
      !!paths && /'voice\/voice-server\.js', 'voice\/headlines\.js'\s*$/.test(paths[1]));
  yes('and neither checks for, stages nor sends a file in public',
      inst.length > 0 && !/public\\(index\.html|voice\.js)|\$send\['public|\\public'/.test(inst));

  const dev = read('scripts/vps/vps-dev-instance.ps1');
  yes('making the dev instance copies the voice program and no page from live',
      /robocopy \$liveVoice \$devVoice voice-server\.js/.test(dev) && !/Join-Path \$liveVoice 'public'/.test(dev));

  const build = read('.github/workflows/build.yml');
  yes('the build parses the service and no file in voice\\public',
      /Get-ChildItem -Path site\\server\.js, voice\\voice-server\.js -File/.test(build) && build.indexOf('voice\\public') < 0);

  const readers = tracked.filter((f) => /^(tests|voice)\/test-[^/]+\.(js|ps1)$/.test(f) && !/test-1822-/.test(f))
    .filter((f) => {
      const src = read(f);
      // A path to the repository's copy, from anywhere; a public folder made
      // beside a scratch copy of the service, from the voice harnesses.
      return /voice[\\/]public|'voice', 'public'|'public', 'voice\.js'/.test(src) ||
             (f.indexOf('voice/') === 0 && /join\(dir, 'public'\)/.test(src));
    });
  yes('no other harness reads or makes a public folder for the service (' + (readers.join(', ') || 'none') + ')',
      readers.length === 0);

  const words = read('scripts/dev/Check-Words.ps1');
  yes('the writing check reads the site\'s public pages and no voice page',
      /\$rel -match '\^site\/public\/\[\^\/\]\+\\\.html\$'/.test(words) && !/\(site\|voice\)\/public/.test(words));

  const opens = tracked.filter((f) => /\.(js|html)$/.test(f) && !/^(tests|voice|docs|engine|site\/node_modules)\//.test(f) &&
                               f !== 'game/gamemode.js')
    .filter((f) => /new WebSocket\(/.test(read(f)));
  yes('the only files that open a socket are the launcher\'s voice page and the game\'s chat overlay (' + opens.join(', ') + ')',
      opens.length === 2 && opens.indexOf('launcher/voice-host.html') >= 0 && opens.indexOf('game/ui/thornswood-chat.js') >= 0);

  // ------------------------------------------------------- the service
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1822-'));
  fs.copyFileSync(VOICE, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(path.dirname(VOICE), 'headlines.js'), path.join(dir, 'headlines.js'));
  fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);
  // What a box installed before this still holds.
  fs.mkdirSync(path.join(dir, 'public'));
  fs.writeFileSync(path.join(dir, 'public', 'index.html'), '<!doctype html><title>Thornswood Voice</title><p>the old page</p>');
  fs.writeFileSync(path.join(dir, 'public', 'voice.js'), "'use strict'; // the old page's script");
  const PORT = await freePort('127.0.0.1');
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: dir,
    env: Object.assign({}, process.env, { THORNSWOOD_VOICE_PORT: String(PORT), THORNSWOOD_VOICE_BIND: '127.0.0.1',
                                          THORNSWOOD_SITE: '', THORNSWOOD_CHAT_DIR: path.join(dir, 'chat') }) });
  srv.stdout.on('data', () => { });
  srv.stderr.on('data', () => { });
  let stopped = false;
  try {
    await listening(srv, PORT);
    const HOST = '127.0.0.1:' + PORT;

    console.log('\nwhat the service answers, with an old public folder beside it:');
    for (const route of ['/', '/index.html', '/voice.js', '/?profile=2&name=Tester', '/public/index.html']) {
      const r = await get(PORT, route);
      yes('GET ' + route + ' is not found (' + r.status + '), and nothing of the old page comes back',
          r.status === 404 && r.body.indexOf('old page') < 0 && r.body.indexOf('Thornswood Voice') < 0);
    }
    const health = await get(PORT, '/health');
    yes('/health still answers (' + health.status + ')', health.status === 200 && /"build"/.test(health.body));

    console.log('\nthe page\'s way in, and the clients\':');
    let pid = 300;
    const caddy = { Host: 'thornswood.net', Origin: 'https://thornswood.net', 'X-Forwarded-For': '203.0.113.7' };
    let r = await knock(PORT, caddy, ++pid, false);
    yes('a socket opened the way the page opened it (this host, through Caddy, no token) is refused (' + r.status + ')',
        r.status === 403 && !r.joined);
    r = await knock(PORT, caddy, ++pid, true);
    yes('a page on this host is refused even with a good token (' + r.status + ')', r.status === 403 && !r.joined);
    r = await knock(PORT, { Host: HOST, Origin: 'http://' + HOST }, ++pid, true);
    yes('and so is one asked straight, not through Caddy (' + r.status + ')', r.status === 403 && !r.joined);
    r = await knock(PORT, { Host: HOST, Origin: 'null' }, ++pid, true);
    yes('a page off disk that says null, with a good token, joins (' + r.status + ')', r.status === 101 && r.joined);
    r = await knock(PORT, { Host: HOST, Origin: 'file://' }, ++pid, true);
    yes('and so does one that says file:// (' + r.status + ')', r.status === 101 && r.joined);
    r = await knock(PORT, { Host: HOST, Origin: 'null' }, ++pid, false);
    yes('a page off disk with no token is still refused (' + r.status + ')', r.status !== 101 && !r.joined);

    await new Promise((ok) => { srv.once('exit', ok); srv.kill(); });
    stopped = true;
  } finally {
    if (!stopped) { try { srv.kill(); } catch (e) { } }
    await wait(100);
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { }
  }

  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('FAIL  the harness itself: ' + (e && e.stack || e)); process.exit(1); });
