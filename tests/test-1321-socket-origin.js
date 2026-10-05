/*
  test-1321-socket-origin.js

      node tests\test-1321-socket-origin.js

  #1321. The voice service never read a socket's Origin, so any website
  could open sockets to it from its visitors' browsers: on 5 Oct, against
  main, a handshake with Origin https://evil.example was answered 101 and
  its join welcomed.

  This starts the real service in a temp folder and makes raw handshakes
  with the Origin and Host a browser would send, proving:

    a page on another website is refused with 403, before any 101, and the
    socket is closed;
    so is a page on this host at another port, a look-alike host, and an
    Origin that is not an address at all;
    the service's own page is let in, asked straight (Host 127.0.0.1:port)
    and through Caddy (Host thornswood.net, Origin https://thornswood.net,
    X-Forwarded-For set);
    the game's pages and the launcher's voice page, loaded off disk, say
    null or file:// and are let in, and join;
    a client that sends no Origin, which is not a browser, is let in and
    joins, as every harness does;
    the refusal is in the log once, not once per socket;
    and the page this service serves opens its socket to the host it was
    loaded from.

  VOICE points it at another copy of voice-server.js, which is how it was
  shown to fail on the code before the change. Writes only to a temp folder,
  on a loopback port the system hands out.
*/
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const os = require('os');
const path = require('path');
const net = require('net');
const crypto = require('crypto');
const { spawn } = require('child_process');

const CR = String.fromCharCode(13);
const VOICE = process.env.VOICE || path.join(REPO_DIR, 'voice', 'voice-server.js');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

/*
  A port of this run's own (#1703). Builds run side by side on the VPS, and
  with a fixed number one run's requests can be answered by another run's
  service. The system names a port nothing holds, the service is started on
  it, and nothing is asked of the port until this service has said it is
  listening there.
*/
function freePort(host) {
  return new Promise((ok, bad) => {
    const s = net.createServer();
    s.on('error', bad);
    s.listen(0, host, () => { const p = s.address().port; s.close(() => ok(p)); });
  });
}
/* Waits for srv's own "listening on ...:port" line. If it stops first,
   something took the port in between or it could not start, and the error
   says which, with what it printed. */
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

/*
  Every join proves itself with a token (#1303), so this signs its own with
  a key it puts beside its copy of the service, the way voice-server.js
  signs them.
*/
const KEY = crypto.randomBytes(32).toString('hex');
function tokenFor(pid) {
  const body = String(pid) + '.' + String(Date.now() + 3600000);
  return 'v1.' + body + '.' + crypto.createHmac('sha256', KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/* A masked text frame, the way a browser sends one. */
function textFrame(obj) {
  const data = Buffer.from(JSON.stringify(obj), 'utf8');
  const head = data.length < 126 ? Buffer.from([0x81, 0x80 | data.length])
                                 : Buffer.from([0x81, 0x80 | 126, data.length >> 8, data.length & 255]);
  const key = crypto.randomBytes(4);
  const body = Buffer.from(data);
  for (let i = 0; i < body.length; i++) { body[i] ^= key[i & 3]; }
  return Buffer.concat([head, key, body]);
}

/* A raw handshake with the headers given: { status, joined, closed }. */
function knock(port, headers, pid) {
  return new Promise((ok) => {
    const s = net.connect(port, '127.0.0.1');
    const me = { status: 0, joined: false, closed: false };
    let buf = Buffer.alloc(0);
    s.on('connect', () => {
      let h = 'GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n' +
              'Sec-WebSocket-Key: ' + crypto.randomBytes(16).toString('base64') + '\r\n';
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
        if (me.status === 101) { s.write(textFrame({ t: 'join', profileId: pid, name: 'P' + pid, token: tokenFor(pid) })); }
      }
      if (buf.indexOf('"welcome"') >= 0) { me.joined = true; }
    });
    s.on('close', () => { me.closed = true; });
    s.on('error', () => { });
    setTimeout(() => { s.destroy(); ok(me); }, 400);
  });
}

(async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1321-'));
  fs.copyFileSync(VOICE, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(path.dirname(VOICE), 'headlines.js'), path.join(dir, 'headlines.js'));
  fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);
  const PORT = await freePort('127.0.0.1');
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: dir,
    env: Object.assign({}, process.env, { THORNSWOOD_VOICE_PORT: String(PORT), THORNSWOOD_VOICE_BIND: '127.0.0.1',
                                          THORNSWOOD_SITE: '', THORNSWOOD_CHAT_DIR: path.join(dir, 'chat') }) });
  let srvLog = '';
  srv.stdout.on('data', (d) => { srvLog += d; });
  srv.stderr.on('data', (d) => { srvLog += d; });
  await listening(srv, PORT);
  const HOST = '127.0.0.1:' + PORT;
  let pid = 100;

  console.log('a page somewhere else:');
  for (const [what, origin, host] of [
    ['another website', 'https://evil.example', HOST],
    ['this host at another port', 'http://127.0.0.1:' + (PORT === 65535 ? 1 : PORT + 1), HOST],
    ['a look-alike of the site', 'https://thornswood.net.evil.example', 'thornswood.net'],
    ['another website through Caddy', 'https://evil.example', 'thornswood.net'],
    ['an Origin that is not an address', 'not an origin', HOST]
  ]) {
    const h = { Host: host, Origin: origin };
    if (host === 'thornswood.net') { h['X-Forwarded-For'] = '203.0.113.7'; }
    const r = await knock(PORT, h, ++pid);
    yes(what + ' (' + origin + ') is refused with 403 (' + r.status + '), not joined, and closed',
        r.status === 403 && !r.joined && r.closed);
  }

  console.log('\nthis service\'s own page, the game\'s and the launcher\'s:');
  for (const [what, origin, host] of [
    ['the page asked straight', 'http://' + HOST, HOST],
    ['the page through Caddy', 'https://thornswood.net', 'thornswood.net'],
    ['the page through Caddy, written in capitals', 'HTTPS://Thornswood.net', 'thornswood.net'],
    ['a page off disk that says null', 'null', HOST],
    ['a page off disk that says file://', 'file://', HOST]
  ]) {
    const h = { Host: host, Origin: origin };
    if (host === 'thornswood.net') { h['X-Forwarded-For'] = '203.0.113.7'; }
    const r = await knock(PORT, h, ++pid);
    yes(what + ' (' + origin + ') is let in and joins (' + r.status + ')', r.status === 101 && r.joined);
  }
  const bare = await knock(PORT, { Host: HOST }, ++pid);
  yes('no Origin at all, which is not a browser, is let in and joins (' + bare.status + ')', bare.status === 101 && bare.joined);
  const node = new WebSocket('ws://' + HOST + '/');
  let welcomed = false;
  node.onmessage = (e) => { if (/"welcome"/.test(String(e.data))) { welcomed = true; } };
  await new Promise((ok) => { node.onopen = ok; node.onerror = ok; });
  node.send(JSON.stringify({ t: 'join', profileId: ++pid, name: 'Harness', token: tokenFor(pid) }));
  await wait(200);
  yes('and so is node\'s own WebSocket, as every harness uses', welcomed);
  try { node.close(); } catch (e) { }

  console.log('\nthe log and the page:');
  const said = srvLog.split('\n').filter((l) => /refused a socket opened by a page on/.test(l));
  yes('the refusal is in the log once, not once per socket (' + said.length + ')', said.length === 1 &&
      /"https:\/\/evil\.example"/.test(said[0]));
  const page = fs.readFileSync(path.join(REPO_DIR, 'voice', 'public', 'voice.js'), 'utf8').split(CR).join('');
  yes('the page this service serves opens its socket to the host it was loaded from',
      /new WebSocket\(proto \+ ':\/\/' \+ location\.host\)/.test(page));

  await new Promise((ok) => { srv.once('exit', ok); srv.kill(); });
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('FAIL  the harness itself: ' + (e && e.stack || e)); process.exit(1); });
