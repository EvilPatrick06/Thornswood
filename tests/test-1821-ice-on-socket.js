/*
  test-1821-ice-on-socket.js

      node tests\test-1821-ice-on-socket.js

  #1821. /ice handed the relay only to a page that POSTed a join token that
  checked out (#1307), and since #1322 a token is good for two minutes and
  opens one connection. The game's voice overlay sent the token its
  connection was opened with, so after its first two minutes it was handed
  STUN only for the rest of the session.

  Now the list rides every roster ({ t: 'peers', peers, iceServers }), which
  is when a page builds its connections, over the socket its token proved at
  the handshake. /ice reads no token. This starts the real service in a temp
  folder with a relay and its coturn secret set and a token life of one
  second, signs its own join tokens with a key it puts beside the service,
  and proves:

    1. a page's first roster carries the relay, with a credential coturn
       takes;
    2. a page connected for longer than a token lives still gets the relay,
       fresher, on the next roster;
    3. /ice hands a page the STUN list whatever token it sends, and the
       relay only to this machine;
    4. with no relay set, the roster carries the STUN list and nothing else;
    5. the pages: the game's chat socket keeps no token for anybody once its
       handshake has spent it, and the game's voice overlay and the
       launcher's voice page take the list from the roster and ask /ice for
       nothing.

  Writes only to a temp folder, on loopback ports the system hands out.
*/
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const os = require('os');
const path = require('path');
const net = require('net');
const http = require('http');
const vm = require('vm');
const crypto = require('crypto');
const { spawn } = require('child_process');

const CR = String.fromCharCode(13);
const VOICE = process.env.VOICE || path.join(REPO_DIR, 'voice', 'voice-server.js');
const SECRET = 'a shared secret for the relay';
const RELAY = 'turn:relay.example.net:3478';
const STUN = JSON.stringify([{ urls: 'stun:stun.l.google.com:19302' }]);

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
const read = (rel) => fs.readFileSync(path.join(REPO_DIR, rel), 'utf8').split(CR).join('');
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));

/* A port of this run's own (#1703), handed out by the system. */
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

const KEY = crypto.randomBytes(32).toString('hex');
// A join token as the service makes them since #1322, minted now or when told.
function tokenFor(pid, minted) {
  const body = 'v2.' + pid + '.' + (minted || Date.now()) + '.' + crypto.randomBytes(16).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return body + '.' + crypto.createHmac('sha256', KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/* The service in a temp folder, with what env adds. */
async function start(env) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1821-'));
  fs.copyFileSync(VOICE, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(path.dirname(VOICE), 'headlines.js'), path.join(dir, 'headlines.js'));
  fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);
  const port = await freePort('127.0.0.1');
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: dir,
    env: Object.assign({}, process.env, { THORNSWOOD_VOICE_PORT: String(port), THORNSWOOD_VOICE_BIND: '127.0.0.1',
                                          THORNSWOOD_SITE: '', THORNSWOOD_CHAT_DIR: path.join(dir, 'chat') }, env) });
  const s = { port: port, srv: srv, log: '' };
  srv.stdout.on('data', (d) => { s.log += d; });
  srv.stderr.on('data', (d) => { s.log += d; });
  await listening(srv, port);
  return s;
}
const stop = (s) => new Promise((ok) => { s.srv.once('exit', ok); s.srv.kill(); });

/*
  A page in the room: the token offered with the handshake, the join, and
  every message kept. rosters() is the peers messages so far.
*/
function page(port, token, pid) {
  return new Promise((done) => {
    const got = [];
    const ws = new WebSocket('ws://127.0.0.1:' + port + '/', ['thornswood', token]);
    const p = { ws: ws, got: got, rosters: () => got.filter((m) => m.t === 'peers') };
    ws.onopen = () => ws.send(JSON.stringify({ t: 'join', profileId: pid, name: 'tester ' + pid }));
    ws.onmessage = (ev) => {
      let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
      got.push(m);
      if (m.t === 'peers' && p.rosters().length === 1) { done(p); }
    };
    ws.onclose = () => done(p);
    setTimeout(() => done(p), 4000);
  });
}
async function until(cond) {
  for (let i = 0; i < 80 && !cond(); i++) { await sleep(50); }
  return cond();
}

/* /ice as a page asks it through Caddy, or as this machine asks it. */
function ice(port, method, body, viaCaddy) {
  return new Promise((ok) => {
    const headers = { origin: 'null' };
    if (body != null) { headers['content-type'] = 'text/plain;charset=UTF-8'; headers['content-length'] = Buffer.byteLength(body); }
    if (viaCaddy) { headers['x-forwarded-for'] = '203.0.113.7'; headers['x-forwarded-proto'] = 'https'; }
    const req = http.request({ host: '127.0.0.1', port: port, path: '/ice', method: method, headers: headers, agent: false }, (res) => {
      let b = '';
      res.on('data', (d) => { b += d; });
      res.on('end', () => {
        let doc = null;
        try { doc = JSON.parse(b); } catch (e) { }
        ok({ status: res.statusCode, list: (doc && doc.iceServers) || null });
      });
    });
    req.on('error', () => ok({ status: 0, list: null }));
    req.end(body == null ? undefined : body);
  });
}
const relayOf = (list) => (list || []).find((s) => [].concat(s.urls)[0] === RELAY);
const coturnTakes = (r) => !!r && r.credential === crypto.createHmac('sha1', SECRET).update(String(r.username)).digest('base64');

/* The brace matched body of a named function in a page's source. */
function lift(src, name) {
  const i = src.indexOf('function ' + name + '(');
  if (i < 0) { return null; }
  let d = 0, s = false;
  for (let j = i; j < src.length; j++) {
    if (src[j] === '{') { d++; s = true; } else if (src[j] === '}') { d--; if (s && d === 0) { return src.slice(i, j + 1); } }
  }
  return null;
}

(async () => {
  const svc = await start({ THORNSWOOD_TURN_URL: RELAY, THORNSWOOD_TURN_SECRET: SECRET,
                            THORNSWOOD_TURN_TTL: '600', THORNSWOOD_TOKEN_SECONDS: '1' });

  console.log('1. the first roster:');
  const mintedA = Date.now();
  const tokA = tokenFor(41, mintedA);
  const a = await page(svc.port, tokA, 41);
  const first = a.rosters()[0];
  yes('a page that joined is sent a roster', !!first);
  const r1 = relayOf(first && first.iceServers);
  yes('it carries the ICE list, STUN first', !!first && Array.isArray(first.iceServers) &&
      JSON.stringify(first.iceServers[0]) === JSON.stringify(JSON.parse(STUN)[0]));
  yes('and the relay', !!r1);
  const now1 = Math.floor(Date.now() / 1000);
  yes('with a username that is an expiry about ten minutes out', !!r1 && Number(r1.username) > now1 + 500 && Number(r1.username) < now1 + 700);
  yes('and a password coturn takes, HMAC-SHA1 of it', coturnTakes(r1));

  console.log('\n2. longer in the room than a token lives:');
  await sleep(2200);
  const knock = await new Promise((ok) => {
    const ws = new WebSocket('ws://127.0.0.1:' + svc.port + '/', ['thornswood', tokenFor(41, mintedA)]);
    ws.onopen = () => { ws.close(); ok('open'); };
    ws.onerror = () => ok('refused');
  });
  yes('a token as old as the one this page joined with is refused now (expired)',
      knock === 'refused' && /REFUSED a connection for profile 41: an expired token/.test(svc.log));
  const b = await page(svc.port, tokenFor(42), 42);
  yes('somebody else joins', b.rosters().length >= 1);
  yes('and the page that has been in the room all along is sent the next roster', await until(() => a.rosters().length >= 2));
  const second = a.rosters()[a.rosters().length - 1];
  const r2 = relayOf(second && second.iceServers);
  yes('that roster names the newcomer', !!second && second.peers.some((p) => p.profileId === 42));
  yes('and still carries the relay', !!r2);
  yes('with a credential coturn takes', coturnTakes(r2));
  yes('minted for this roster, not the first one', !!r1 && !!r2 && Number(r2.username) > Number(r1.username));
  yes('the newcomer\'s first roster carries it too', !!relayOf((b.rosters()[0] || {}).iceServers));

  console.log('\n3. /ice reads no token:');
  let r = await ice(svc.port, 'POST', JSON.stringify({ token: tokenFor(41) }), true);
  yes('a page that POSTs a join token that checks out is handed the STUN list and no relay',
      r.status === 200 && JSON.stringify(r.list) === STUN);
  r = await ice(svc.port, 'POST', JSON.stringify({ token: tokA }), true);
  yes('and so is one that POSTs the token its connection was opened with', r.status === 200 && JSON.stringify(r.list) === STUN);
  r = await ice(svc.port, 'GET', null, true);
  yes('a plain GET through Caddy is handed the STUN list', r.status === 200 && JSON.stringify(r.list) === STUN);
  r = await ice(svc.port, 'GET', null, false);
  yes('this machine is handed the relay, which is what Install-Voice.ps1 reads', !!relayOf(r.list));
  r = await ice(svc.port, 'POST', JSON.stringify({ token: 'not a token' }), false);
  yes('by POST too, whatever the body says', !!relayOf(r.list));
  yes('no token reaches the service\'s log', svc.log.indexOf(tokA) < 0 && !/v2\.4[12]\.\d+\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{20,}/.test(svc.log));
  try { a.ws.close(); } catch (e) { }
  try { b.ws.close(); } catch (e) { }
  await stop(svc);

  console.log('\n4. no relay set, which is every box today:');
  const bare = await start({});
  const c = await page(bare.port, tokenFor(43), 43);
  const cr = c.rosters()[0];
  yes('the roster carries the STUN list and nothing else', !!cr && JSON.stringify(cr.iceServers) === STUN);
  try { c.ws.close(); } catch (e) { }
  await stop(bare);

  console.log('\n5. the pages:');
  // The game's chat socket, run as it ships, with a socket that records.
  const made = [];
  function FakeSocket(url, protocols) { made.push(this); this.protocols = protocols; this.readyState = 0; this.sent = []; }
  FakeSocket.prototype.send = function (m) { this.sent.push(m); };
  FakeSocket.prototype.close = function () { this.readyState = 3; };
  const win = {
    THORNSWOOD: { host: '127.0.0.1', port: 7778, profileId: 4242, name: 'tester', token: 'v2.4242.1.injected',
                  base: 'https://thornswood.net/voice' },
    skyrimPlatform: { sendMessage: () => { } },
  };
  const box = { window: win, WebSocket: FakeSocket, console: console,
                setTimeout: () => 0, clearTimeout: () => { }, setInterval: () => 0, clearInterval: () => { } };
  vm.createContext(box);
  vm.runInContext(read('game/ui/thornswood-chat.js'), box);
  yes('the chat spends the token it was handed on its handshake', !!made[0] &&
      JSON.stringify(made[0].protocols) === JSON.stringify(['thornswood', 'v2.4242.1.injected']));
  yes('and leaves no copy in the page\'s settings', win.THORNSWOOD.token === '');
  const chat = read('game/ui/thornswood-chat.js');
  yes('and hands no token to anything else on the page', !!win.thornswoodNet && !('token' in win.thornswoodNet) &&
      !/return (TOKEN|SPENT)\b/.test(chat));

  // The game's voice overlay.
  const overlay = read('game/ui/thornswood-voice.js');
  const reported = [];
  const ov = new Function('report', 'var ICE = ' + STUN + ';\n' + lift(overlay, 'takeIce') +
                          '\nreturn { take: takeIce, ice: function () { return ICE; } };')((st, d) => reported.push(st + ' | ' + d));
  ov.take(undefined);
  ov.take([]);
  yes('the overlay keeps its list when a roster carries none', JSON.stringify(ov.ice()) === STUN);
  ov.take(second.iceServers);
  yes('and takes the roster\'s list, relay and all', !!relayOf(ov.ice()) && reported.some((l) => /relay yes/.test(l)));
  yes('before it builds anything from that roster',
      /if \(m\.t === 'peers'\) \{ takeIce\(m\.iceServers\); reconcile\(m\.peers\); return; \}/.test(overlay));
  yes('and it asks /ice for nothing and holds no token', !/\/ice'/.test(overlay) && !/\.token\(\)/.test(overlay) &&
      !/THORNSWOOD \|\| \{\}\)\.token/.test(overlay));
  yes('every peer connection is built from that list', /new RTCPeerConnection\(\{ iceServers: ICE \}\)/.test(overlay));

  // The launcher's voice page.
  const host = read('launcher/voice-host.html');
  const said = [];
  const hp = new Function('say', 'var ICE = ' + STUN + '; var iceSaid = "";\n' + lift(host, 'takeIce') +
                          '\nreturn { take: takeIce, ice: function () { return ICE; } };')((l) => said.push(l));
  hp.take(null);
  yes('the launcher\'s page keeps its list when a roster carries none', JSON.stringify(hp.ice()) === STUN);
  hp.take(second.iceServers);
  hp.take(second.iceServers);
  yes('and takes the roster\'s list, relay and all', !!relayOf(hp.ice()));
  yes('saying so in the launcher log once, not on every roster', said.length === 1 && /relay yes/.test(said[0]));
  yes('before it builds anything from that roster',
      /if \(m\.t === 'peers'\) \{ takeIce\(m\.iceServers\); onPeers\(m\.peers \|\| \[\]\); return; \}/.test(host));
  yes('and it asks /ice for nothing, so its token goes only with the handshake',
      !/\/ice'/.test(host) && (host.match(/cfg\.token/g) || []).length > 0 && !/token: \(cfg && cfg\.token\)/.test(host));
  yes('every peer connection is built from that list', /new RTCPeerConnection\(\{ iceServers: ICE \}\)/.test(host));

  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('FAIL  the harness itself: ' + (e && e.stack || e)); process.exit(1); });
