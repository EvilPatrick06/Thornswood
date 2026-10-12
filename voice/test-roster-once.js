// test-roster-once.js
//
// Issue #2332: a room that fills at once is sent one roster, not one per
// arrival.
//
// announce() used to send the whole roster to every socket the moment
// anybody joined or left, so when the service restarted and every page came
// back together, N people cost each of N sockets N rosters, each the size of
// the room. Measured on One on 11 Oct with voice/load-voice.js: 200 people
// took 20 s to get back in and 400 never did. Now the joins and leaves one
// turn of the event loop handles share one roster (sendRoster).
//
// This runs voice/voice-server.js in a temp folder on a port the system hands
// out, as the other harnesses do, with real join tokens from a stand-in site
// that says yes, and measures on the wire:
//
//   PEOPLE sockets that are already open send their joins together; every one
//   is welcomed, then sent a roster naming all of them, and no socket is sent
//   anywhere near one roster per arrival (the first in used to get PEOPLE);
//   the welcome still comes before the first roster on every socket;
//   half of them close together, and the rest are sent a roster without them,
//   again not one per departure;
//   one person joining alone afterwards is still one roster to each socket,
//   straight away, as before.
//
// VOICE_SERVER=<path> runs it against another copy (the one before #2332
// fails the counts). Read only. Nothing outside the temp folder is touched.
const fs = require('fs');
const os = require('os');
const net = require('net');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');

const SERVER = process.env.VOICE_SERVER || path.join(__dirname, 'voice-server.js');
const PEOPLE = 60;
// The most rosters any one socket may be sent while PEOPLE joins (or half
// that many leaves) arrive together. One per turn of the event loop that
// handled some of them; a quarter of PEOPLE leaves room for a busy build
// runner splitting the arrivals across turns, and is still far under the
// PEOPLE the first socket was sent before.
const MOST_ROSTERS = Math.floor(PEOPLE / 4);
const BOUND_MS = 20000;

let pass = 0, fail = 0;
function yes(what, cond, why) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what + (why ? '\n      ' + why : '')); }
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(cond, ms) {
  const end = Date.now() + (ms || BOUND_MS);
  while (Date.now() < end) { if (cond()) return true; await sleep(20); }
  return cond();
}

function siteThatSaysYes() {
  return new Promise((ok) => {
    const site = http.createServer((req, res) => {
      req.resume();
      req.on('end', () => {
        if (req.method === 'POST' && req.url === '/api/play/owns') {
          res.writeHead(200, { 'content-type': 'application/json' }).end('{"ok":true}');
        } else {
          res.writeHead(404).end();
        }
      });
    });
    site.listen(0, '127.0.0.1', () => { site.unref(); ok('http://127.0.0.1:' + site.address().port); });
  });
}

function freePort() {
  return new Promise((ok, bad) => {
    const s = net.createServer();
    s.on('error', bad);
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); });
  });
}

let svc = null;
async function service(site) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-roster-'));
  fs.copyFileSync(SERVER, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(__dirname, 'headlines.js'), path.join(dir, 'headlines.js'));
  const port = await freePort();
  const env = Object.assign({}, process.env, {
    THORNSWOOD_VOICE_PORT: String(port), THORNSWOOD_VOICE_BIND: '127.0.0.1', THORNSWOOD_SITE: site,
    THORNSWOOD_CHAT_DIR: path.join(dir, 'chat')
  });
  delete env.THORNSWOOD_VOICE_MOST;
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: dir, env: env });
  svc = { dir: dir, port: port, proc: srv, log: '' };
  srv.stdout.on('data', (d) => { svc.log += d; });
  srv.stderr.on('data', (d) => { svc.log += d; });
  await listening(srv, port);
  return svc;
}

/* Waits for srv's own "listening on ...:port" line, as voice/test-most.js
   does. If it stops first, something took the port or it could not start,
   and the error says which, with what it printed. */
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

function token(port, pid) {
  return new Promise((ok, bad) => {
    const body = JSON.stringify({ profileId: pid, ticket: 'a ticket the stand-in site takes' });
    const req = http.request({ host: '127.0.0.1', port: port, path: '/token', method: 'POST', agent: false,
                               headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) } }, (res) => {
      let b = '';
      res.on('data', (d) => { b += d; });
      res.on('end', () => {
        let doc = null;
        try { doc = JSON.parse(b); } catch (e) { }
        if (res.statusCode === 200 && doc && typeof doc.token === 'string') { ok(doc.token); return; }
        bad(new Error('no token for profile ' + pid + ': ' + res.statusCode + ' ' + b.slice(0, 200)));
      });
    });
    req.on('error', bad);
    req.end(body);
  });
}

const opened = [];
/* A socket that is open and has not joined yet. Records what it is sent, in order. */
async function openPage(port, pid) {
  const tok = await token(port, pid);
  return new Promise((ok, bad) => {
    const ws = new WebSocket('ws://127.0.0.1:' + port + '/', ['thornswood', tok]);
    opened.push(ws);
    const me = { pid: pid, ws: ws, peer: 0, got: [], closed: false };
    const late = setTimeout(() => bad(new Error('socket for ' + pid + ' did not open')), BOUND_MS);
    ws.onopen = () => { clearTimeout(late); ok(me); };
    ws.onmessage = (ev) => {
      let m = null;
      try { m = JSON.parse(String(ev.data)); } catch (e) { return; }
      me.got.push(m);
      if (m.t === 'welcome') me.peer = m.peer;
    };
    ws.onclose = () => { me.closed = true; };
    ws.onerror = () => { };
  });
}
const rosters = (me) => me.got.filter((m) => m.t === 'peers');
const lastRoster = (me) => { const r = rosters(me); return r.length ? r[r.length - 1].peers : null; };
const names = (list, peers) => !!list && peers.every((id) => list.some((row) => row.peer === id));

(async () => {
  const site = await siteThatSaysYes();
  const s = await service(site);

  // ------------------------------------------------------- all in at once
  const pages = [];
  for (let i = 0; i < PEOPLE; i += 20) {
    pages.push(...await Promise.all(Array.from({ length: Math.min(20, PEOPLE - i) }, (_, k) => openPage(s.port, 5000 + i + k))));
  }
  yes(PEOPLE + ' sockets are open before anybody joins', pages.length === PEOPLE && pages.every((p) => !p.closed));

  for (const p of pages) p.ws.send(JSON.stringify({ t: 'join', profileId: p.pid, name: 'Person ' + p.pid }));
  const allIn = await until(() => pages.every((p) => p.peer) &&
                                  pages.every((p) => names(lastRoster(p), pages.map((q) => q.peer))));
  yes('every one is welcomed and sent a roster naming all ' + PEOPLE, allIn,
      pages.filter((p) => !p.peer).length + ' not welcomed, ' +
      pages.filter((p) => !names(lastRoster(p), pages.map((q) => q.peer))).length + ' without the whole room');
  await sleep(300);

  const counts = pages.map((p) => rosters(p).length);
  const most = Math.max.apply(null, counts);
  const total = counts.reduce((a, b) => a + b, 0);
  console.log('      rosters per socket for ' + PEOPLE + ' joins together: most ' + most + ', all sockets ' + total +
              ' (one per arrival would be ' + PEOPLE + ' to the first in and ' + (PEOPLE * (PEOPLE + 1) / 2) + ' in all)');
  yes('no socket is sent more than ' + MOST_ROSTERS + ' rosters for ' + PEOPLE + ' joins that arrive together',
      most <= MOST_ROSTERS, 'most ' + most + ', counts ' + counts.join(','));
  yes('every socket is welcomed before it is sent its first roster',
      pages.every((p) => { const w = p.got.findIndex((m) => m.t === 'welcome'); const r = p.got.findIndex((m) => m.t === 'peers');
                           return w >= 0 && r > w; }));
  yes('every roster still carries the ice list and each row its peer, profile, name and mode',
      pages.every((p) => rosters(p).every((m) => Array.isArray(m.iceServers) &&
        m.peers.every((row) => row.peer && row.profileId && typeof row.name === 'string' && row.mode === 'local'))));

  // ------------------------------------------------- half leave at once
  const going = pages.slice(0, PEOPLE / 2);
  const staying = pages.slice(PEOPLE / 2);
  const before = staying.map((p) => rosters(p).length);
  for (const p of going) p.ws.close();
  const goneIds = going.map((p) => p.peer);
  const left = await until(() => staying.every((p) => { const l = lastRoster(p);
    return l && l.length === staying.length && !l.some((row) => goneIds.indexOf(row.peer) >= 0); }));
  yes('when half close together, the rest are sent a roster without them', left);
  await sleep(300);
  const leaveMost = Math.max.apply(null, staying.map((p, i) => rosters(p).length - before[i]));
  console.log('      rosters per remaining socket for ' + going.length + ' leaving together: most ' + leaveMost);
  yes('and not one per departure (at most ' + MOST_ROSTERS + ' for ' + going.length + ')', leaveMost <= MOST_ROSTERS,
      'most ' + leaveMost);

  // --------------------------------------------------- one alone, as ever
  const mark = staying.map((p) => rosters(p).length);
  const late = await openPage(s.port, 9000);
  late.ws.send(JSON.stringify({ t: 'join', profileId: 9000, name: 'Late' }));
  const named = await until(() => late.peer && staying.every((p) => names(lastRoster(p), [late.peer])) &&
                                  names(lastRoster(late), staying.map((p) => p.peer).concat([late.peer])));
  yes('somebody joining alone is sent the room, and the room is sent them', named);
  await sleep(200);
  yes('with exactly one roster to each socket for that one join',
      staying.every((p, i) => rosters(p).length - mark[i] === 1) && rosters(late).length === 1,
      staying.map((p, i) => rosters(p).length - mark[i]).join(',') + ' / ' + rosters(late).length);

  finish();
})().catch((err) => {
  fail++;
  console.log('FAIL  the harness stopped: ' + (err && err.stack || err));
  finish();
});

function finish() {
  for (const ws of opened) { try { ws.close(); } catch (e) { } }
  if (svc) {
    const dir = svc.dir;
    const rm = () => { try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { } };
    svc.proc.once('exit', rm);
    try { svc.proc.kill(); } catch (e) { }
    setTimeout(rm, 300).unref();
  }
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exitCode = fail ? 1 : 0;
}
