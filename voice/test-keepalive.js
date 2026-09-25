// test-keepalive.js
//
// A quiet chat window used to lose the server.
//
// Patrick, 23 September, with it on his screen while the service was up the
// whole time and the game noticed nothing: "Chat lost the server. Trying
// again." The service answered pings and never sent one, so a socket that
// said nothing for long enough was closed by what sits between the two ends,
// which is Caddy. Voice traffic kept a talking socket busy and the position
// feed kept a peer busy; the sockets that died were the quiet ones.
//
// This spawns the real service with a short ping interval, opens a real
// websocket, and waits for the ping frame to arrive. It is a raw socket
// rather than the WebSocket class on purpose: the class answers pings itself
// and never tells anybody, which is exactly what made this invisible.
//
// Read only. Nothing outside the temp folder is touched.
const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

const PORT = 7903;
const PING_MS = 300;

let pass = 0, fail = 0;
function check(what, got, want) {
  if (String(got) === String(want)) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what + '\n      wanted [' + want + '] got [' + got + ']'); }
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-keepalive-'));
for (const f of ['voice-server.js']) {
  fs.copyFileSync(path.join(__dirname, f), path.join(dir, f));
}
const pub = path.join(dir, 'public');
try { fs.mkdirSync(pub); } catch (e) { }

const srv = spawn(process.execPath, ['voice-server.js'], {
  cwd: dir,
  env: Object.assign({}, process.env, {
    THORNSWOOD_VOICE_PORT: String(PORT),
    THORNSWOOD_VOICE_AUTH: 'off',
    THORNSWOOD_SITE: '',
    THORNSWOOD_VOICE_PING_MS: String(PING_MS),
  }),
});
let log = '';
srv.stdout.on('data', (d) => { log += d; });
srv.stderr.on('data', (d) => { log += d; });

/*
  Ended rather than exited.

  process.exit here crashed node outright with "Assertion failed:
  !(handle->flags & UV_HANDLE_CLOSING)" and an exit code of 127, because the
  killed child and the torn down socket were still closing underneath it. The
  counts had already printed, so it looked like a pass and was a crash. Set
  the code, let go of everything, and let node leave when it is ready.
*/
function done(code) {
  process.exitCode = code;
  try { srv.kill(); } catch (e) { }
  setTimeout(() => {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { }
  }, 300).unref();
}

async function ready() {
  for (let i = 0; i < 60; i++) {
    try {
      const r = await fetch('http://127.0.0.1:' + PORT + '/health');
      if (r.ok) { return await r.json(); }
    } catch (e) { }
    await new Promise((r) => setTimeout(r, 150));
  }
  throw new Error('the service never came up. log:\n' + log);
}

/* The handshake by hand, so the frames underneath can be read. */
function open() {
  return new Promise((resolve, reject) => {
    const key = crypto.randomBytes(16).toString('base64');
    const s = net.connect(PORT, '127.0.0.1', () => {
      s.write('GET / HTTP/1.1\r\n' +
              'Host: 127.0.0.1:' + PORT + '\r\n' +
              'Upgrade: websocket\r\n' +
              'Connection: Upgrade\r\n' +
              'Sec-WebSocket-Key: ' + key + '\r\n' +
              'Sec-WebSocket-Version: 13\r\n\r\n');
    });
    let head = '';
    const onData = (d) => {
      head += d.toString('binary');
      const at = head.indexOf('\r\n\r\n');
      if (at < 0) { return; }
      s.removeListener('data', onData);
      resolve({ sock: s, head: head.slice(0, at) });
    };
    s.on('data', onData);
    s.on('error', reject);
    setTimeout(() => reject(new Error('no handshake in four seconds')), 4000);
  });
}

/* The opcode of the next frame the service sends, and its length. */
function nextFrame(sock, ms) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => { sock.removeListener('data', on); resolve(null); }, ms);
    const on = (d) => {
      if (d.length < 2) { return; }
      clearTimeout(timer);
      sock.removeListener('data', on);
      resolve({ op: d[0] & 0x0f, fin: !!(d[0] & 0x80), len: d[1] & 0x7f });
    };
    sock.on('data', on);
  });
}

(async () => {
  const h = await ready();
  console.log('service up: build ' + h.build + ', ping every ' + PING_MS + 'ms for this run');
  console.log('');

  const { sock, head } = await open();
  check('the service upgrades a plain websocket request',
        /^HTTP\/1\.1 101/.test(head), true);

  /*
    THE WHOLE POINT. Nothing is sent and nothing is said: the socket just
    sits there, which is a chat window with nobody near it, and the ping has
    to arrive anyway.
  */
  const f = await nextFrame(sock, PING_MS * 8);
  check('a quiet socket is pinged rather than left to die', f && f.op, 9);
  check('and the ping is a whole frame with no body', f && f.fin && f.len === 0, true);

  // A second one, so it is a heartbeat and not a one-off at connect.
  const g = await nextFrame(sock, PING_MS * 8);
  check('and it keeps happening', g && g.op, 9);

  // Answering it the way a browser does must not upset anything: the service
  // reads the pong and carries on.
  sock.write(Buffer.from([0x8a, 0x80, 0, 0, 0, 0]));   // masked empty pong
  const after = await nextFrame(sock, PING_MS * 8);
  check('a pong back is taken quietly and the pings continue', after && after.op, 9);

  try { sock.destroy(); } catch (e) { }
  await new Promise((r) => setTimeout(r, 300));
  check('the service is still up after the socket goes',
        (await (await fetch('http://127.0.0.1:' + PORT + '/health')).json()).build === h.build, true);

  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  done(fail ? 1 : 0);
})().catch((e) => {
  console.error('FAILED: ' + e.message);
  console.error(log);
  done(1);
});
