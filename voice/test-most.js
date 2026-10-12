// test-most.js
//
// Issue #481: the voice service takes so many people at once and no more.
//
// THORNSWOOD_VOICE_MOST is the most profiles holding a socket at once. This
// runs voice/voice-server.js in a temp folder on a port the system hands out,
// with the number set to three, and joins real websockets with real join
// tokens (asked of the service, which asks a stand-in site that says yes):
//
//   three people join and are welcomed, and a second socket for one of them
//   (the launcher's voice page beside the game's chat) is let in as well;
//   a fourth person's socket is told why in one chat line and closed with
//   1013, never welcomed and never on the roster, and /health counts it;
//   once somebody leaves, the fourth gets in;
//   a person with two sockets is let go of only when both have closed;
//   a copy with no number set takes everybody, as the service always did.
//
// Read only. Nothing outside the temp folders is touched.
const fs = require('fs');
const os = require('os');
const net = require('net');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');

const SERVER = process.env.VOICE_SERVER || path.join(__dirname, 'voice-server.js');

let pass = 0, fail = 0;
function yes(what, cond, why) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what + (why ? '\n      ' + why : '')); }
}

const BOUND_MS = 15000;

/* The site, as far as the service asks it anything: every ticket owns its profile. */
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

/* A copy of the service in a folder of its own, up and listening. */
async function service(site, most) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-most-'));
  fs.copyFileSync(SERVER, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(__dirname, 'headlines.js'), path.join(dir, 'headlines.js'));
  const port = await freePort();
  const env = Object.assign({}, process.env, {
    THORNSWOOD_VOICE_PORT: String(port),
    THORNSWOOD_VOICE_BIND: '127.0.0.1',
    THORNSWOOD_SITE: site,
    THORNSWOOD_CHAT_DIR: path.join(dir, 'chat')
  });
  delete env.THORNSWOOD_VOICE_MOST;
  if (most !== null) env.THORNSWOOD_VOICE_MOST = String(most);
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: dir, env: env });
  const s = { dir: dir, port: port, proc: srv, log: '' };
  srv.stdout.on('data', (d) => { s.log += d; });
  srv.stderr.on('data', (d) => { s.log += d; });
  await listening(srv, port);
  return s;
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

async function health(s) {
  const r = await fetch('http://127.0.0.1:' + s.port + '/health');
  return await r.json();
}

function joinToken(s, pid) {
  return new Promise((ok, bad) => {
    const body = JSON.stringify({ profileId: pid, ticket: 'a ticket the stand-in site takes' });
    const req = http.request({ host: '127.0.0.1', port: s.port, path: '/token', method: 'POST', agent: false,
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
/*
  One page's socket. Resolves once it is welcomed or closed, whichever comes
  first, with what it was sent: { welcomed, closed, code, reason, chat, rosters, ws }.
*/
async function page(s, pid) {
  const token = await joinToken(s, pid);
  return new Promise((ok) => {
    const ws = new WebSocket('ws://127.0.0.1:' + s.port + '/', ['thornswood', token]);
    opened.push(ws);
    const me = { pid: pid, ws: ws, token: token, welcomed: false, closed: false, code: 0, reason: '', chat: [], roster: null };
    const late = setTimeout(() => ok(me), BOUND_MS);
    ws.onopen = () => { ws.send(JSON.stringify({ t: 'join', profileId: pid, name: 'Person ' + pid })); };
    ws.onmessage = (ev) => {
      let m = null;
      try { m = JSON.parse(String(ev.data)); } catch (e) { return; }
      if (m.t === 'welcome') { me.welcomed = true; clearTimeout(late); ok(me); }
      if (m.t === 'chat') { me.chat.push(m); }
      if (m.t === 'peers') { me.roster = m.peers || []; }
    };
    ws.onclose = (ev) => { me.closed = true; me.code = ev.code; me.reason = ev.reason; clearTimeout(late); ok(me); };
    ws.onerror = () => { };
  });
}

function closed(me) {
  return new Promise((ok) => {
    if (me.closed) { ok(); return; }
    const prev = me.ws.onclose;
    me.ws.onclose = (ev) => { if (prev) prev(ev); ok(); };
    me.ws.close();
  });
}

/* Asks /health until test(h) holds or BOUND_MS passes; the last answer. */
async function healthUntil(s, test) {
  const end = Date.now() + BOUND_MS;
  let h = await health(s);
  while (!test(h) && Date.now() < end) {
    await new Promise((r) => setTimeout(r, 50));
    h = await health(s);
  }
  return h;
}

const services = [];
function finish() {
  for (const ws of opened) { try { ws.close(); } catch (e) { } }
  for (const s of services) {
    const rm = () => { try { fs.rmSync(s.dir, { recursive: true, force: true }); } catch (e) { } };
    s.proc.once('exit', rm);
    try { s.proc.kill(); } catch (e) { }
    setTimeout(rm, 300).unref();
  }
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exitCode = fail ? 1 : 0;
}

(async () => {
  const site = await siteThatSaysYes();

  // ------------------------------------------------------------ three, set
  const s = await service(site, 3);
  services.push(s);
  let h = await health(s);
  yes('/health says the most it takes and how many are in', h.most === 3 && h.people === 0 && h.refusedFull === 0,
      JSON.stringify({ most: h.most, people: h.people, refusedFull: h.refusedFull }));

  const a = await page(s, 101);
  const b = await page(s, 102);
  const c = await page(s, 103);
  yes('three people join and are welcomed', a.welcomed && b.welcomed && c.welcomed);
  const b2 = await page(s, 102);
  yes('a second socket for somebody already in is let in at the number', b2.welcomed);
  h = await health(s);
  yes('and the second socket is the same person, so three are in, on four sockets', h.people === 3 && h.peers === 4,
      'people ' + h.people + ', peers ' + h.peers);

  // ----------------------------------------------------------- the fourth
  const d = await page(s, 104);
  yes('a fourth person is not welcomed', !d.welcomed);
  yes('their socket is closed with 1013, try again later', d.closed && d.code === 1013, 'code ' + d.code + ' reason ' + d.reason);
  const said = d.chat.map((m) => String(m.text)).join(' | ');
  yes('and told why first, in one chat line from the service', d.chat.length === 1 && !Number(d.chat[0].from) &&
      /full: 3 people are connected/.test(said) && /tries again by itself/.test(said), said);
  yes('the line has no em dash in it', said.indexOf('—') < 0);
  h = await health(s);
  yes('/health counts the one turned away, and still three in', h.refusedFull === 1 && h.people === 3,
      'refusedFull ' + h.refusedFull + ', people ' + h.people);
  yes('the log says so', /\[voice\] full: 3 people are connected/.test(s.log), s.log.slice(-400));
  yes('the people in the room were never sent a roster with the fourth on it',
      [a, b, c, b2].every((p) => !(p.roster || []).some((r) => Number(r.profileId) === 104)));

  // The token the fourth came with was spent on that handshake, as any is.
  const again = await new Promise((ok) => {
    const ws = new WebSocket('ws://127.0.0.1:' + s.port + '/', ['thornswood', d.token]);
    opened.push(ws);
    let opened2 = false;
    ws.onopen = () => { opened2 = true; };
    ws.onclose = () => ok(opened2);
    ws.onerror = () => { };
  });
  yes('the token the turned away socket carried does not open a second one', again === false);

  // ---------------------------------------------------- somebody leaves
  await closed(c);
  h = await healthUntil(s, (x) => x.people === 2);
  yes('when somebody leaves, the count goes down', h.people === 2, 'people ' + h.people);
  const d2 = await page(s, 104);
  yes('and the fourth gets in', d2.welcomed);

  // -------------------------------------------- two sockets, let go of once
  await closed(b);
  h = await healthUntil(s, (x) => x.peers === 3);
  yes('one of two sockets closing keeps that person counted', h.people === 3 && h.peers === 3,
      'people ' + h.people + ', peers ' + h.peers);
  const e = await page(s, 105);
  yes('so the room is still full for somebody new', !e.welcomed && e.code === 1013, 'code ' + e.code);
  await closed(b2);
  h = await healthUntil(s, (x) => x.people === 2);
  yes('and the person is let go of when their last socket closes', h.people === 2, 'people ' + h.people);
  const e2 = await page(s, 105);
  yes('which makes room for one more', e2.welcomed);

  // ----------------------------------------------------- no number at all
  const open = await service(site, null);
  services.push(open);
  h = await health(open);
  yes('a copy with no number set says 0, no cap', h.most === 0, 'most ' + h.most);
  const many = [];
  for (let pid = 201; pid <= 206; pid++) many.push(await page(open, pid));
  yes('and takes everybody, six people where the other took three', many.every((p) => p.welcomed));

  const junk = await service(site, 'many');
  services.push(junk);
  h = await health(junk);
  yes('a number that is not a whole number above zero is no cap, said on /health as 0', h.most === 0, 'most ' + h.most);

  finish();
})().catch((err) => {
  fail++;
  console.log('FAIL  the harness stopped: ' + (err && err.stack || err));
  finish();
});
