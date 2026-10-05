/*
  test-1351-unmasked-frames.js

      node tests\test-1351-unmasked-frames.js

  #1351. RFC 6455 section 5.1: "The server MUST close the connection upon
  receiving a frame that is not masked." The voice service's frame reader
  (Sock.feed in voice/voice-server.js) unmasked a frame when the mask bit was
  set and read it as it was when not: on 5 Oct, against main, a join sent
  unmasked was answered with a welcome.

  This starts the real service in a temp folder, talks to it over raw
  sockets that write their own frames, and proves:

    a masked join is welcomed, as a browser's is;
    an unmasked join is answered with a close frame carrying 1002, a
    protocol error, the socket is closed, and nobody is welcomed;
    somebody already in the room who sends one unmasked frame is closed the
    same way, leaves the room, and that frame reaches nobody;
    an unmasked ping gets no pong, only the close;
    and the browser's own WebSocket, which masks everything, still joins
    and talks.

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

/* A text frame, masked the way a browser sends one, or not. */
function textFrame(obj, masked) {
  const data = Buffer.from(JSON.stringify(obj), 'utf8');
  const head = data.length < 126 ? Buffer.from([0x81, (masked ? 0x80 : 0) | data.length])
                                 : Buffer.from([0x81, (masked ? 0x80 : 0) | 126, data.length >> 8, data.length & 255]);
  if (!masked) { return Buffer.concat([head, data]); }
  const key = crypto.randomBytes(4);
  const body = Buffer.from(data);
  for (let i = 0; i < body.length; i++) { body[i] ^= key[i & 3]; }
  return Buffer.concat([head, key, body]);
}

/* A raw socket that has done the handshake as pid, with every frame it is
   sent. */
function raw(port, pid) {
  return new Promise((ok, bad) => {
    const s = net.connect(port, '127.0.0.1');
    const me = { sock: s, frames: [], msgs: [], closed: false };
    let buf = Buffer.alloc(0), up = false;
    s.on('connect', () => {
      s.write('GET / HTTP/1.1\r\nHost: 127.0.0.1:' + port + '\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
              'Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ' + crypto.randomBytes(16).toString('base64') + '\r\n' +
              'Sec-WebSocket-Protocol: thornswood, ' + tokenFor(pid) + '\r\n\r\n');
    });
    s.on('data', (d) => {
      buf = Buffer.concat([buf, d]);
      if (!up) {
        const i = buf.indexOf('\r\n\r\n');
        if (i < 0) { return; }
        if (!/^HTTP\/1\.1 101/.test(buf.slice(0, i).toString())) { bad(new Error('no 101')); return; }
        buf = buf.slice(i + 4); up = true; ok(me);
      }
      for (;;) {
        if (buf.length < 2) { return; }
        let len = buf[1] & 0x7f, off = 2;
        if (len === 126) { if (buf.length < 4) { return; } len = buf.readUInt16BE(2); off = 4; }
        else if (len === 127) { if (buf.length < 10) { return; } len = Number(buf.readBigUInt64BE(2)); off = 10; }
        if (buf.length < off + len) { return; }
        const op = buf[0] & 0x0f;
        const body = buf.slice(off, off + len);
        buf = buf.slice(off + len);
        me.frames.push({ op: op, body: body });
        if (op === 1) { try { me.msgs.push(JSON.parse(body.toString('utf8'))); } catch (e) { } }
      }
    });
    s.on('close', () => { me.closed = true; });
    s.on('error', () => { });
  });
}
const closeCode = (c) => {
  const f = c.frames.find((x) => x.op === 8);
  return f && f.body.length >= 2 ? f.body.readUInt16BE(0) : 0;
};

/*
  Every join proves itself with a token (#1303), so this signs its own with
  a key it puts beside its copy of the service, the way voice-server.js
  signs them. One token opens one connection and goes with the handshake,
  after 'thornswood' (#1337, #1322).
*/
const KEY = crypto.randomBytes(32).toString('hex');
function tokenFor(pid) {
  const body = 'v2.' + pid + '.' + Date.now() + '.' + crypto.randomBytes(16).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return body + '.' + crypto.createHmac('sha256', KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

(async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1351-'));
  fs.copyFileSync(VOICE, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(path.dirname(VOICE), 'headlines.js'), path.join(dir, 'headlines.js'));
  fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);
  const PORT = await freePort('127.0.0.1');
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: dir,
    env: Object.assign({}, process.env, { THORNSWOOD_VOICE_PORT: String(PORT), THORNSWOOD_VOICE_BIND: '127.0.0.1',
                                          THORNSWOOD_SITE: '',
                                          THORNSWOOD_CHAT_DIR: path.join(dir, 'chat') }) });
  let srvLog = '';
  srv.stdout.on('data', (d) => { srvLog += d; });
  srv.stderr.on('data', (d) => { srvLog += d; });
  await listening(srv, PORT);

  console.log('masked, as a browser sends it:');
  const a = await raw(PORT, 1);
  a.sock.write(textFrame({ t: 'join', profileId: 1, name: 'Alva' }, true));
  await wait(200);
  yes('a masked join is welcomed', a.msgs.some((m) => m.t === 'welcome'));

  console.log('\nunmasked:');
  const b = await raw(PORT, 2);
  b.sock.write(textFrame({ t: 'join', profileId: 2, name: 'Brand' }, false));
  await wait(300);
  yes('an unmasked join is not welcomed', !b.msgs.some((m) => m.t === 'welcome'));
  yes('it is answered with a close frame carrying 1002, a protocol error (' + closeCode(b) + ')', closeCode(b) === 1002);
  yes('and the socket is closed', b.closed);
  const last = a.msgs.filter((m) => m.t === 'peers').pop();
  yes('nobody in the room ever saw it join', !!last && last.peers.length === 1 &&
      !a.msgs.some((m) => m.t === 'peers' && m.peers.some((p) => p.profileId === 2)));

  console.log('\nsomebody already in the room who sends one unmasked frame:');
  const c = await raw(PORT, 3);
  c.sock.write(textFrame({ t: 'join', profileId: 3, name: 'Cyra' }, true));
  await wait(200);
  yes('joins masked and is in the room', c.msgs.some((m) => m.t === 'welcome') &&
      a.msgs.some((m) => m.t === 'peers' && m.peers.some((p) => p.profileId === 3)));
  const mark = a.msgs.length;
  c.sock.write(textFrame({ t: 'chat', text: 'unmasked words' }, false));
  await wait(300);
  yes('is closed with 1002 (' + closeCode(c) + ')', closeCode(c) === 1002 && c.closed);
  yes('and the line reaches nobody', !a.msgs.slice(mark).some((m) => m.t === 'chat' && m.text === 'unmasked words'));
  const after = a.msgs.slice(mark).filter((m) => m.t === 'peers').pop();
  yes('and leaves the room', !!after && !after.peers.some((p) => p.profileId === 3));

  console.log('\nan unmasked ping:');
  const d = await raw(PORT, 5);
  d.sock.write(Buffer.from([0x89, 0x00]));
  await wait(300);
  yes('gets no pong', !d.frames.some((f) => f.op === 0xa));
  yes('only the close, 1002 (' + closeCode(d) + ')', closeCode(d) === 1002 && d.closed);

  console.log('\nthe browser\'s own WebSocket, which masks everything:');
  const got = [];
  const ws = new WebSocket('ws://127.0.0.1:' + PORT + '/', ['thornswood', tokenFor(4)]);
  ws.onmessage = (e) => { try { got.push(JSON.parse(e.data)); } catch (x) { } };
  await new Promise((ok) => { ws.onopen = ok; ws.onerror = ok; });
  ws.send(JSON.stringify({ t: 'join', profileId: 4, name: 'Dagny' }));
  await wait(200);
  ws.send(JSON.stringify({ t: 'chat', text: 'masked words' }));
  await wait(300);
  yes('joins', got.some((m) => m.t === 'welcome'));
  yes('and its line reaches the room', a.msgs.some((m) => m.t === 'chat' && m.text === 'masked words'));

  try { ws.close(); a.sock.destroy(); } catch (e) { }
  await new Promise((ok) => { srv.once('exit', ok); srv.kill(); });
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('FAIL  the harness itself: ' + (e && e.stack || e)); process.exit(1); });
