/*
  Entry 6, step 6: drive the real voice service and assert what a join does.

  Runs the shipped voice-server.js in a scratch folder on a spare port, mints
  tokens through its own /token route, and joins over a real WebSocket. Nothing
  here is a stand-in but the site: the file under test is voice/voice-server.js,
  and a small site in this process answers /api/play/owns the way site/server.js
  does, so every answer it can give is driven.

  Since #1315 only a yes from the site mints a token: no answer, a 500, a body
  that is not JSON, a site that never answers and a service with no
  THORNSWOOD_SITE all get 503 and no token. Since #1303 a join that cannot
  prove itself is refused whatever THORNSWOOD_VOICE_AUTH says; the service
  here is started with it set to off to show it is not read.
*/
const { spawn } = require('child_process');
const fs = require('fs');
const net = require('net');
const http = require('http');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

// The repo this file sits in, so it runs from anywhere.
const REPO = path.resolve(__dirname, '..');
// Set by ready(), from the system. It was a fixed 7901 (#1703).
let PORT = 0;
// The second service, with no THORNSWOOD_SITE at all.
let BARE = 0;

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'voiceauth-'));
fs.copyFileSync(path.join(__dirname, 'voice-server.js'), path.join(dir, 'voice-server.js'));
fs.copyFileSync(path.join(__dirname, 'headlines.js'), path.join(dir, 'headlines.js'));
fs.writeFileSync(path.join(dir, 'secret.txt'), 'a test secret, not the real one');
const KEY = crypto.randomBytes(32).toString('hex');
fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);

let pass = 0, fail = 0;
function check(what, got, want) {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? '  ok   ' : '  FAIL ') + what + (ok ? '' : '\n         got ' + JSON.stringify(got) + '\n         want ' + JSON.stringify(want)));
  ok ? pass++ : fail++;
}

const sign = (profileId, until) => {
  const body = String(profileId) + '.' + String(until);
  const mac = crypto.createHmac('sha256', KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return 'v1.' + body + '.' + mac;
};

const post = (route, body, port) => fetch('http://127.0.0.1:' + (port || PORT) + route, {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
});

// What a join that cannot prove itself gets, whatever any setting says (#1303).
function refused(why) { return { t: 'denied', why: why }; }

/*
  The site's half: POST /api/play/owns, answered by the ticket. good owns
  every profile, other owns none (200, ok false, as site/server.js answers a
  ticket that is not theirs), boom is the 503 the site gives when it could not
  ask Discord, garbage is a 200 that is not JSON, and slow never answers, so
  the service's three second timeout is what ends it.
*/
const asked = [];
const site = http.createServer((req, res) => {
  let b = '';
  req.on('data', (d) => { b += d; });
  req.on('end', () => {
    let o = {};
    try { o = JSON.parse(b); } catch (e) { o = {}; }
    asked.push(req.url + ' ' + o.ticket + ' ' + o.profileId);
    if (req.url !== '/api/play/owns') { res.writeHead(404).end(); return; }
    if (o.ticket === 'good') { res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ ok: true, why: 'theirs' })); return; }
    if (o.ticket === 'other') { res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ ok: false, why: 'not theirs' })); return; }
    if (o.ticket === 'boom') { res.writeHead(503, { 'content-type': 'application/json' }).end(JSON.stringify({ ok: false, why: 'could not ask Discord' })); return; }
    if (o.ticket === 'garbage') { res.writeHead(200, { 'content-type': 'text/html' }).end('<html>a login page</html>'); return; }
    if (o.ticket === 'slow') { return; }
    res.writeHead(500).end('no');
  });
});

/* Join, and report what the room said back. 'denied' or the welcome. */
function join(msg) {
  return new Promise((done) => {
    const ws = new WebSocket('ws://127.0.0.1:' + PORT + '/');
    let answered = false;
    const finish = (v) => { if (!answered) { answered = true; try { ws.close(); } catch (e) {} done(v); } };
    ws.onopen = () => ws.send(JSON.stringify(msg));
    ws.onmessage = (ev) => {
      let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
      if (m.t === 'denied') return finish({ t: 'denied', why: m.why });
      if (m.t === 'welcome') return finish({ t: 'welcome', profileId: m.profileId });
    };
    ws.onerror = () => finish({ t: 'error' });
    ws.onclose = () => finish({ t: 'closed with nothing said' });
    setTimeout(() => finish({ t: 'nothing came back' }), 4000);
  });
}

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
let srv = null;
let bare = null;
let log = '';
let bareLog = '';
async function ready() {
  await new Promise((ok) => site.listen(0, '127.0.0.1', ok));
  PORT = await freePort('0.0.0.0');
  srv = spawn(process.execPath, ['voice-server.js'], {
    cwd: dir,
    env: Object.assign({}, process.env, {
      THORNSWOOD_VOICE_PORT: String(PORT),
      // Not read since #1303. Off was the old behaviour, every join let in.
      THORNSWOOD_VOICE_AUTH: 'off',
      THORNSWOOD_SITE: 'http://127.0.0.1:' + site.address().port,
    }),
  });
  srv.stdout.on('data', (d) => { log += d; });
  srv.stderr.on('data', (d) => { log += d; });
  await listening(srv, PORT);
  // A second copy in its own folder, with no site to ask (#1315).
  const bareDir = fs.mkdtempSync(path.join(os.tmpdir(), 'voiceauth-bare-'));
  for (const n of ['voice-server.js', 'headlines.js']) fs.copyFileSync(path.join(__dirname, n), path.join(bareDir, n));
  BARE = await freePort('0.0.0.0');
  bare = spawn(process.execPath, ['voice-server.js'], {
    cwd: bareDir,
    env: Object.assign({}, process.env, { THORNSWOOD_VOICE_PORT: String(BARE), THORNSWOOD_VOICE_AUTH: 'log', THORNSWOOD_SITE: '' }),
  });
  bare.stdout.on('data', (d) => { bareLog += d; });
  bare.stderr.on('data', (d) => { bareLog += d; });
  await listening(bare, BARE);
  const r = await fetch('http://127.0.0.1:' + PORT + '/health');
  if (!r.ok) throw new Error('the service answered /health with ' + r.status + '. log:\n' + log);
  return await r.json();
}

(async () => {
  const h = await ready();
  console.log('service up: build ' + h.build + ', auth ' + h.auth);
  check('/health says auth on, with THORNSWOOD_VOICE_AUTH set to off', h.auth, 'on');
  console.log('');

  console.log('WHAT /token MINTS (#1315):');
  // A token for profile 4242, minted by the service itself on the site's yes.
  const r = await post('/token', { profileId: 4242, ticket: 'good' });
  const minted = await r.json();
  check('the site says the ticket owns it: a token', [r.status, minted.profileId, typeof minted.token], [200, 4242, 'string']);
  check('  and the site was asked about that profile with that ticket', asked.indexOf('/api/play/owns good 4242') >= 0, true);
  check('the site says it does not: 403 and no token', (await post('/token', { profileId: 4242, ticket: 'other' })).status, 403);
  const boom = await post('/token', { profileId: 4242, ticket: 'boom' });
  check('the site could not answer (its 503): 503 and no token', [boom.status, /"token"/.test(await boom.text())], [503, false]);
  check('the site answered with something that is not JSON: 503', (await post('/token', { profileId: 4242, ticket: 'garbage' })).status, 503);
  check('the site answered 500 to a ticket it did not know: 503', (await post('/token', { profileId: 4242, ticket: 'nobody' })).status, 503);
  const t0 = Date.now();
  const slow = await post('/token', { profileId: 4242, ticket: 'slow' });
  check('the site never answered: 503 once the service gave up on it', [slow.status, Date.now() - t0 >= 2500], [503, true]);
  check('no ticket at all: 400, and the site is not asked', [(await post('/token', { profileId: 4243 })).status,
        asked.some((a) => / 4243$/.test(a))], [400, false]);
  check('no profile: 400', (await post('/token', { ticket: 'good' })).status, 400);
  const none = await post('/token', { profileId: 4242, ticket: 'good' }, BARE);
  check('a service with no THORNSWOOD_SITE mints nothing: 503', none.status, 503);
  check('  and says why in its log', /NO TOKEN for profile 4242: THORNSWOOD_SITE is not set/.test(bareLog), true);

  console.log('');
  console.log('WHO GETS IN (#1303), with THORNSWOOD_VOICE_AUTH off on one service and log on the other:');
  check('a real token joins as its own profile',
        await join({ t: 'join', profileId: 4242, name: 'tester', token: minted.token }), { t: 'welcome', profileId: 4242 });

  check('no token at all is refused',
        await join({ t: 'join', profileId: 4242, name: 'stranger' }), refused('no token'));

  check('somebody else\'s profile in the message loses to the token',
        await join({ t: 'join', profileId: 99, name: 'liar', token: minted.token }), { t: 'welcome', profileId: 4242 });

  check('a made up token is refused',
        await join({ t: 'join', profileId: 4242, token: 'v1.4242.' + (Date.now() + 60000) + '.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' }),
        refused('a token that does not check out'));
  check('an expired token is refused, and named as expired',
        await join({ t: 'join', profileId: 7, token: sign(7, Date.now() - 1000) }),
        refused('an expired token'));
  check('a token signed with another key is refused',
        await join({ t: 'join', profileId: 4242, token: 'v1.4242.' + (Date.now() + 60000) + '.' +
          crypto.createHmac('sha256', 'a different key').update('4242.' + (Date.now() + 60000)).digest('base64')
            .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '') }),
        refused('a token that does not check out'));
  const was = PORT;
  PORT = BARE;
  check('the service with THORNSWOOD_VOICE_AUTH log refuses a join with no token too',
        await join({ t: 'join', profileId: 4242, name: 'stranger' }), refused('no token'));
  PORT = was;
  check('nothing was let in unproven', /UNPROVEN|UNCHECKED/.test(log + bareLog), false);

  console.log('');
  console.log('what the service wrote down:');
  for (const line of (log + bareLog).split('\n')) {
    if (/REFUSED|NO TOKEN|claimed profile/.test(line)) console.log('  ' + line.trim());
  }

  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  // Kill, then let the loop drain before exiting. Calling process.exit while
  // the child's pipes are still closing trips a libuv assertion on Windows,
  // which looks like a failure and is not one.
  process.exitCode = fail ? 1 : 0;
  srv.kill();
  bare.kill();
  site.close();
  setTimeout(() => {}, 150);
})().catch((e) => { console.error(e); if (srv) srv.kill(); if (bare) bare.kill(); site.close(); process.exitCode = 1; });
