// #2753: ssh from a cloud thread reaches the box inside a WebSocket.
//
// A cloud Claude thread's proxy carries HTTPS only, so ssh goes through
// scripts/vps/bridge: connect.js (ssh's ProxyCommand in the cloud) opens a
// WebSocket through the proxy to bridge.js (on the box behind Caddy), which
// joins it to sshd. This runs both for real on loopback:
//   1. ws.js frames: every length form, masked and not, fragments, pieces of
//      one byte, and the frames a peer must never send;
//   2. bridge.js, spawned with a token file and an echo server in sshd's
//      place: a plain request is a 404, an upgrade with no token, a wrong one
//      or none on the box is a 401, a ninth session is a 503, and with the
//      token bytes go there and back intact, 3 MB included;
//   3. connect.js, spawned the way ssh spawns it, through a stand-in for the
//      cloud proxy that answers CONNECT: what goes in on standard input comes
//      back on standard output, and a wrong token or a proxy that refuses the
//      tunnel exits 1 saying which.
//
// Read only. Nothing outside the temp folder is touched, and nothing leaves
// loopback.
'use strict';
const fs = require('fs');
const os = require('os');
const net = require('net');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

const REPO = path.join(__dirname, '..');
const DIR = path.join(REPO, 'scripts', 'vps', 'bridge');
let pass = 0, fail = 0;
function yes(what, ok) { if (ok) { pass++; console.log('  ok   ' + what); } else { fail++; console.log('  FAIL ' + what); } }

const ws = require(path.join(DIR, 'ws.js'));
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-bridge-'));
const tokenFile = path.join(tmp, 'token.txt');
const TOKEN = crypto.randomBytes(32).toString('base64url');
fs.writeFileSync(tokenFile, TOKEN + '\n');

// ---- 1. frames ---------------------------------------------------------------
function roundTrip(len, mask) {
  const data = crypto.randomBytes(len);
  const r = new ws.Reader({ masked: mask });
  const out = r.push(ws.encode(ws.OP.BINARY, data, mask));
  return out.length === 1 && out[0].op === ws.OP.BINARY && out[0].data.equals(data);
}
for (const len of [0, 1, 125, 126, 65535, 65536, 300000]) {
  yes('a ' + len + ' byte frame comes back whole, masked and not', roundTrip(len, true) && roundTrip(len, false));
}
{
  const data = crypto.randomBytes(5000);
  const f = ws.encode(ws.OP.BINARY, data, true);
  const r = new ws.Reader({ masked: true });
  let got = [];
  for (let i = 0; i < f.length; i++) got = got.concat(r.push(f.subarray(i, i + 1)));
  yes('a frame handed over one byte at a time comes out once, whole', got.length === 1 && got[0].data.equals(data));
}
{
  const a = Buffer.from('part one '), b = Buffer.from('and two');
  const f1 = ws.encode(ws.OP.BINARY, a, true); f1[0] &= 0x7f;          // not FIN
  const f2 = ws.encode(ws.OP.CONT, b, true);
  const ping = ws.encode(ws.OP.PING, Buffer.from('p'), true);
  const r = new ws.Reader({ masked: true });
  const got = r.push(Buffer.concat([f1, ping, f2]));
  yes('a fragmented message comes back as one, with a ping between its parts let through',
    got.length === 2 && got[0].op === ws.OP.PING && got[1].op === ws.OP.BINARY && got[1].data.toString() === 'part one and two');
}
function throws(what, fn) { let t = false; try { fn(); } catch (e) { t = true; } yes(what, t); }
throws('a server refuses an unmasked frame', () => new ws.Reader({ masked: true }).push(ws.encode(ws.OP.BINARY, Buffer.from('x'), false)));
throws('a client refuses a masked frame', () => new ws.Reader({ masked: false }).push(ws.encode(ws.OP.BINARY, Buffer.from('x'), true)));
throws('a frame that says it is over a megabyte is refused before it is held', () => {
  const h = Buffer.alloc(14); h[0] = 0x82; h[1] = 0x80 | 127; h.writeBigUInt64BE(BigInt(ws.MAX_FRAME + 1), 2);
  new ws.Reader({ masked: true }).push(h);
});
throws('a control frame over 125 bytes is refused', () => new ws.Reader({ masked: true }).push(ws.encode(ws.OP.PING, Buffer.alloc(126), true)));
throws('a continuation with nothing to continue is refused', () => new ws.Reader({ masked: true }).push(ws.encode(ws.OP.CONT, Buffer.from('x'), true)));
yes('the handshake answer is the one RFC 6455 gives for its own example key', ws.accept('dGhlIHNhbXBsZSBub25jZQ==') === 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=');

// ---- helpers -----------------------------------------------------------------
function freePort() {
  return new Promise((resolve) => { const s = net.createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); }); });
}
function waitFor(fn, ms) {
  return new Promise((resolve) => {
    const until = Date.now() + ms;
    (function poll() { if (fn()) return resolve(true); if (Date.now() > until) return resolve(false); setTimeout(poll, 20); })();
  });
}
// A raw upgrade, so the answer is read exactly as it came.
function upgrade(port, headers) {
  return new Promise((resolve) => {
    const s = net.connect(port, '127.0.0.1');
    let got = '';
    s.on('data', (d) => { got += d.toString('latin1'); if (got.indexOf('\r\n\r\n') >= 0) { s.destroy(); resolve(got.split('\r\n')[0]); } });
    s.on('error', () => resolve(''));
    s.on('close', () => resolve(got.split('\r\n')[0]));
    const lines = ['GET / HTTP/1.1', 'Host: x'].concat(headers);
    s.write(lines.join('\r\n') + '\r\n\r\n');
  });
}
const WS_HEADERS = ['Upgrade: websocket', 'Connection: Upgrade', 'Sec-WebSocket-Version: 13', 'Sec-WebSocket-Key: ' + crypto.randomBytes(16).toString('base64')];

// Runs connect.js the way ssh does: bytes on stdin, bytes back on stdout.
function runClient(env, input, waitMs) {
  return new Promise((resolve) => {
    const e = Object.assign({}, process.env, env);
    delete e.HTTPS_PROXY; delete e.https_proxy;
    if (env.HTTPS_PROXY) e.HTTPS_PROXY = env.HTTPS_PROXY;
    const c = spawn(process.execPath, [path.join(DIR, 'connect.js')], { env: e });
    const out = []; let err = '';
    c.stdout.on('data', (d) => out.push(d));
    c.stderr.on('data', (d) => { err += d; });
    let expect = input.length;
    c.stdout.on('data', () => { if (Buffer.concat(out).length >= expect) c.stdin.end(); });
    c.on('close', (code) => resolve({ code, out: Buffer.concat(out), err }));
    c.stdin.on('error', () => {});
    c.stdin.write(input);
    if (!input.length) c.stdin.end();
    setTimeout(() => c.kill(), waitMs || 10000);
  });
}

(async () => {
  const echo = net.createServer((s) => { s.on('error', () => {}); s.pipe(s); });
  await new Promise((r) => echo.listen(0, '127.0.0.1', r));
  const echoPort = echo.address().port;
  const port = await freePort();
  let log = '';
  const bridge = spawn(process.execPath, [path.join(DIR, 'bridge.js')], {
    env: Object.assign({}, process.env, {
      THORNSWOOD_BRIDGE_PORT: String(port),
      THORNSWOOD_BRIDGE_TOKEN_FILE: tokenFile,
      THORNSWOOD_BRIDGE_TARGET: '127.0.0.1:' + echoPort,
    }),
  });
  bridge.stdout.on('data', (d) => { log += d; });
  bridge.stderr.on('data', (d) => { log += d; });
  // A stand-in for the cloud proxy: answers CONNECT and pipes, or refuses.
  let connects = [];
  let refuseTunnel = false;
  const proxy = net.createServer((s) => {
    s.on('error', () => {});
    s.once('data', (d) => {
      const line = d.toString('latin1').split('\r\n')[0];
      connects.push(line);
      if (refuseTunnel) { s.end('HTTP/1.1 403 Forbidden\r\n\r\n'); return; }
      const m = /^CONNECT ([^:]+):(\d+) HTTP\/1\.1$/.exec(line);
      const up = net.connect(Number(m[2]), m[1] === 'localhost' ? '127.0.0.1' : m[1], () => {
        s.write('HTTP/1.1 200 Connection established\r\n\r\n');
        s.pipe(up); up.pipe(s);
      });
      up.on('error', () => s.destroy());
    });
  });
  await new Promise((r) => proxy.listen(0, '127.0.0.1', r));
  const proxyUrl = 'http://127.0.0.1:' + proxy.address().port;

  try {
    yes('the bridge starts on loopback and says where it joins to', await waitFor(() => /listening on 127\.0\.0\.1:\d+, joining to 127\.0\.0\.1:\d+/.test(log), 5000));

    // ---- 2. the bridge -----------------------------------------------------
    const plain = await new Promise((resolve) => http.get({ host: '127.0.0.1', port, path: '/' }, (res) => { let b = ''; res.setEncoding('utf8'); res.on('data', (d) => { b += d; }); res.on('end', () => resolve({ code: res.statusCode, body: b.trim() })); }).on('error', () => resolve({ code: 0, body: '' })));
    yes('a plain request is a 404', plain.code === 404);
    // #2875: the site's own 404 says "not here", so the bridge's line has to
    // be one the site never sends, or a check through Caddy takes the site
    // for the bridge.
    yes('  saying "box bridge: not here", the line Install-Bridge.ps1 looks for', plain.body === 'box bridge: not here');
    const siteSays = fs.readFileSync(path.join(REPO, 'site', 'server.js'), 'utf8');
    yes('  which the site never says', siteSays.indexOf('box bridge') < 0);
    yes('an upgrade with no token is a 401', /^HTTP\/1\.1 401/.test(await upgrade(port, WS_HEADERS)));
    yes('an upgrade with a wrong token is a 401', /^HTTP\/1\.1 401/.test(await upgrade(port, WS_HEADERS.concat(['Authorization: Bearer ' + TOKEN + 'x']))));
    yes('the token as a bare header, without "Bearer", is a 401', /^HTTP\/1\.1 401/.test(await upgrade(port, WS_HEADERS.concat(['Authorization: ' + TOKEN]))));
    yes('an upgrade with the token but no WebSocket key is a 400', /^HTTP\/1\.1 400/.test(await upgrade(port, ['Upgrade: websocket', 'Connection: Upgrade', 'Sec-WebSocket-Version: 13', 'Authorization: Bearer ' + TOKEN])));
    yes('with the token it switches protocols', /^HTTP\/1\.1 101/.test(await upgrade(port, WS_HEADERS.concat(['Authorization: Bearer ' + TOKEN]))));
    yes('  and the log names no address and no token', log.indexOf(TOKEN) < 0 && !/127\.0\.0\.1:\d+\)/.test(log.split('\n').filter((l) => /session|refused/.test(l)).join('\n')));

    // Nine at once: the ninth is refused while eight are open.
    const held = [];
    for (let i = 0; i < 8; i++) {
      const s = net.connect(port, '127.0.0.1');
      s.on('error', () => {});
      s.write(['GET / HTTP/1.1', 'Host: x'].concat(WS_HEADERS, ['Authorization: Bearer ' + TOKEN]).join('\r\n') + '\r\n\r\n');
      held.push(s);
    }
    yes('eight sessions open at once', await waitFor(() => /session 9 opened \(8 open\)/.test(log), 3000));
    yes('a ninth session while eight are open is a 503', /^HTTP\/1\.1 503/.test(await upgrade(port, WS_HEADERS.concat(['Authorization: Bearer ' + TOKEN]))));
    held.forEach((s) => s.destroy());
    yes('a session whose cloud end goes away is let go and logged with its bytes', await waitFor(() => (log.match(/session \d+ ended: the WebSocket closed, \d+ s, \d+ bytes in, \d+ bytes out/g) || []).length >= 9, 3000));

    // ---- 3. connect.js through the stand-in proxy ----------------------------
    const url = 'ws://localhost:' + port + '/';
    const small = Buffer.from('SSH-2.0-OpenSSH_9.6 a line ssh would send\r\n');
    let r = await runClient({ THORNSWOOD_BOX_URL: url, THORNSWOOD_BOX_TOKEN: TOKEN, HTTPS_PROXY: proxyUrl }, small);
    yes('through the proxy, what goes in comes back out (exit ' + r.code + ')' + (r.err ? ': ' + r.err.trim() : ''), r.code === 0 && r.out.equals(small));
    yes('  and the proxy was asked to CONNECT to the bridge\'s host and port', connects.indexOf('CONNECT localhost:' + port + ' HTTP/1.1') >= 0);

    const big = crypto.randomBytes(3 * 1024 * 1024);
    r = await runClient({ THORNSWOOD_BOX_URL: url, THORNSWOOD_BOX_TOKEN: TOKEN, HTTPS_PROXY: proxyUrl }, big, 30000);
    yes('3 MB there and back arrives byte for byte (exit ' + r.code + ', ' + r.out.length + ' bytes)', r.code === 0 && r.out.equals(big));

    r = await runClient({ THORNSWOOD_BOX_URL: url, THORNSWOOD_BOX_TOKEN: 'not-it', HTTPS_PROXY: proxyUrl }, Buffer.alloc(0));
    yes('a wrong token exits 1 and says the bridge refused the token', r.code === 1 && /box bridge: the bridge refused the token \(401\)/.test(r.err));

    refuseTunnel = true;
    r = await runClient({ THORNSWOOD_BOX_URL: url, THORNSWOOD_BOX_TOKEN: TOKEN, HTTPS_PROXY: proxyUrl }, Buffer.alloc(0));
    yes('a proxy that refuses the tunnel exits 1 and says so', r.code === 1 && /box bridge: the proxy refused the tunnel to localhost:\d+ \(HTTP\/1\.1 403 Forbidden\)/.test(r.err));
    refuseTunnel = false;

    r = await runClient({ THORNSWOOD_BOX_URL: 'http://localhost:' + port + '/', THORNSWOOD_BOX_TOKEN: TOKEN }, Buffer.alloc(0));
    yes('an address that is not ws:// or wss:// exits 1', r.code === 1 && /must be a ws:\/\/ or wss:\/\/ address/.test(r.err));

    // listen.js, the loopback port ssh-keyscan asks through: two clients at
    // once, each carried to the far end by a connect.js of its own.
    // Both spellings out first, as runClient does: Windows names are one
    // whatever their case, so setting both would leave either.
    const lisEnv = Object.assign({}, process.env, { THORNSWOOD_BOX_URL: url, THORNSWOOD_BOX_TOKEN: TOKEN });
    delete lisEnv.HTTPS_PROXY; delete lisEnv.https_proxy;
    lisEnv.HTTPS_PROXY = proxyUrl;
    const lis = spawn(process.execPath, [path.join(DIR, 'listen.js')], { env: lisEnv, stdio: ['pipe', 'pipe', 'pipe'] });
    try {
      const lport = await new Promise((resolve, reject) => {
        let got = '';
        lis.stdout.on('data', (d) => { got += d; const m = /^(\d+)\n/.exec(got); if (m) resolve(Number(m[1])); });
        lis.on('exit', () => reject(new Error('listen.js ended before it printed a port')));
      });
      yes('listen.js prints the loopback port it took', lport > 0);
      const viaListener = (payload) => new Promise((resolve) => {
        const c = net.connect(lport, '127.0.0.1');
        let back = Buffer.alloc(0);
        c.on('data', (d) => { back = Buffer.concat([back, d]); if (back.length >= payload.length) c.end(); });
        c.on('close', () => resolve(back));
        c.on('error', () => resolve(back));
        c.write(payload);
      });
      const one = crypto.randomBytes(5000);
      const two = crypto.randomBytes(7000);
      const [b1, b2] = await Promise.all([viaListener(one), viaListener(two)]);
      yes('  and two connections at once each come back byte for byte through the bridge', b1.equals(one) && b2.equals(two));
      lis.stdin.end();
      const ended = await waitFor(() => lis.exitCode !== null, 3000);
      yes('  and it stops when its standard input closes', ended);
    } finally {
      if (lis.exitCode === null) lis.kill();
    }

    fs.unlinkSync(tokenFile);
    yes('with the token file gone the bridge refuses even the right token', /^HTTP\/1\.1 401/.test(await upgrade(port, WS_HEADERS.concat(['Authorization: Bearer ' + TOKEN]))));
  } finally {
    bridge.kill();
    echo.close();
    proxy.close();
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('  FAIL ' + e.stack); process.exit(1); });
