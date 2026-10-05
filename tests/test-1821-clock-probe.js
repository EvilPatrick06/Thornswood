/*
  test-1821-clock-probe.js

  Temporary, for #1867 / #1889 / #1897, and taken out again before the pull
  request merges. Measures on the build runner itself what this Linux
  machine cannot: how far apart two node processes read the wall clock on
  Windows, and how often a join token signed by a harness the moment the
  voice service says it is listening is refused as minted before the service
  started. Prints PROBE lines and always exits 0.
*/
const fs = require('fs');
const os = require('os');
const path = require('path');
const net = require('net');
const http = require('http');
const crypto = require('crypto');
const { spawn } = require('child_process');
const REPO_DIR = path.join(__dirname, '..');
const VOICE = path.join(REPO_DIR, 'voice', 'voice-server.js');
const KEY = crypto.randomBytes(32).toString('hex');
const b64 = (b) => b.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
function tokenFor(pid, minted) {
  const body = 'v2.' + pid + '.' + minted + '.' + b64(crypto.randomBytes(16));
  return body + '.' + b64(crypto.createHmac('sha256', KEY).update(body).digest());
}
function freePort() {
  return new Promise((ok, bad) => { const s = net.createServer(); s.on('error', bad);
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); }); });
}
let SITE = '';
function site() {
  return new Promise((ok) => { const s = http.createServer((q, r) => { q.resume(); q.on('end', () => r.end('{"ok":true}')); });
    s.listen(0, '127.0.0.1', () => ok('http://127.0.0.1:' + s.address().port)); });
}
async function start() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1821p-'));
  fs.copyFileSync(VOICE, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(path.dirname(VOICE), 'headlines.js'), path.join(dir, 'headlines.js'));
  fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);
  const port = await freePort();
  const own = {};
  for (const k of Object.keys(process.env)) { if (!/^THORNSWOOD_/i.test(k)) { own[k] = process.env[k]; } }
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: dir, env: Object.assign(own, {
    THORNSWOOD_VOICE_PORT: String(port), THORNSWOOD_VOICE_BIND: '127.0.0.1', THORNSWOOD_SITE: SITE,
    THORNSWOOD_CHAT_DIR: path.join(dir, 'chat') }) });
  const s = { port: port, srv: srv, log: '' };
  srv.stderr.on('data', (d) => { s.log += d; });
  await new Promise((ok, bad) => {
    srv.stdout.on('data', (d) => { s.log += d; if (/\[voice\] listening on \S+:\d+/.test(s.log)) { ok(); } });
    srv.on('exit', (c) => bad(new Error('exit ' + c + ': ' + s.log)));
  });
  return s;
}
const stop = (s) => new Promise((ok) => { s.srv.once('close', ok); s.srv.kill(); });
function knock(port, token) {
  return new Promise((ok) => {
    const req = http.request({ host: '127.0.0.1', port: port, path: '/', agent: false, headers: {
      connection: 'Upgrade', upgrade: 'websocket', 'sec-websocket-version': '13',
      'sec-websocket-key': crypto.randomBytes(16).toString('base64'), 'sec-websocket-protocol': 'thornswood, ' + token } });
    req.on('upgrade', (res, socket) => { socket.destroy(); ok('101'); });
    req.on('response', (res) => { let b = ''; res.on('data', (d) => { b += d; }); res.on('end', () => ok(res.statusCode + ' ' + b.trim())); });
    req.on('error', (e) => ok('error ' + e.message));
    req.end();
  });
}
function joinToken(s, pid) {
  return new Promise((ok) => {
    const body = JSON.stringify({ profileId: pid, ticket: 't' });
    const req = http.request({ host: '127.0.0.1', port: s.port, path: '/token', method: 'POST', agent: false,
      headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) } }, (res) => {
      let b = ''; res.on('data', (d) => { b += d; }); res.on('end', () => { try { ok(JSON.parse(b).token); } catch (e) { ok(''); } });
    });
    req.on('error', () => ok(''));
    req.end(body);
  });
}
const tally = (list) => { const t = {}; for (const x of list) { t[x] = (t[x] || 0) + 1; } return JSON.stringify(t); };

(async () => {
  console.log('PROBE node ' + process.version + ' on ' + process.platform + ' ' + os.release() + ', ' + os.cpus().length + ' cpus');
  // 1. The same instant read by two processes: this one, after a child's reading reached it.
  const ds = [];
  for (let i = 0; i < 100; i++) {
    const out = await new Promise((ok) => { let o = ''; const c = spawn(process.execPath, ['-e', 'process.stdout.write(String(Date.now()))']);
      c.stdout.on('data', (d) => { o += d; }); c.on('close', () => ok(o)); });
    ds.push(Date.now() - Number(out));
  }
  ds.sort((x, y) => x - y);
  console.log('PROBE clocks: here minus a child\'s reading it sent here, 100 children: min ' + ds[0] + ' ms, median ' + ds[50] +
              ', max ' + ds[99] + '; below zero, so the child's clock ahead of this one's, ' + ds.filter((d) => d < 0).length);
  console.log('PROBE clocks, the lowest ten: ' + ds.slice(0, 10).join(' '));
  SITE = await site();
  // 2. The old way: a token signed here the moment the service says it is listening.
  const oldWay = [];
  for (let i = 0; i < 50; i++) { const s = await start(); oldWay.push(await knock(s.port, tokenFor(43, Date.now()))); await stop(s); }
  console.log('PROBE signed here at once, 50 starts: ' + tally(oldWay));
  // 3. The new way: the service mints it (POST /token).
  const newWay = [];
  for (let i = 0; i < 50; i++) { const s = await start(); newWay.push(await knock(s.port, await joinToken(s, 43))); await stop(s); }
  console.log('PROBE minted by the service, 50 starts: ' + tally(newWay));
  // 4. This node's WebSocket on a refused handshake.
  const s = await start();
  const t0 = Date.now();
  const seen = await new Promise((ok) => { const ev = []; const ws = new WebSocket('ws://127.0.0.1:' + s.port + '/', ['thornswood', 'nope']);
    ws.onerror = () => ev.push('error ' + (Date.now() - t0));
    ws.onclose = (e) => { ev.push('close ' + e.code + ' ' + (Date.now() - t0)); ok(ev); };
    setTimeout(() => ok(ev.concat('no close by 3000')), 3000); });
  console.log('PROBE a refused handshake, as WebSocket reports it: ' + seen.join(', '));
  await stop(s);
  process.exit(0);
})().catch((e) => { console.log('PROBE the probe itself failed: ' + (e && e.stack || e)); process.exit(0); });
