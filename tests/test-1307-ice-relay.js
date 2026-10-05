/*
  test-1307-ice-relay.js

      node tests\test-1307-ice-relay.js

  #1307. /ice handed its whole list to anybody who asked, relay credential
  included: on 5 Oct, against main with a relay set, a stranger with no
  token was handed a working username and password for it. A relay carries
  its bandwidth bill for whoever holds one.

  This starts the real service in a temp folder with a relay and its
  coturn secret set, signs its own join tokens with a key it puts beside
  the service, and asks /ice the way Caddy carries a request (from
  127.0.0.1 with X-Forwarded-For) and straight from this machine. It proves:

    a stranger, GET or POST, with no token, a made up one or an expired
    one, is handed the STUN list and nothing else;
    a page that POSTs a join token that checks out is handed the relay too,
    with a credential coturn takes (HMAC-SHA1 of the expiry);
    this machine itself, which is how Install-Voice.ps1 reads the running
    relay before it reinstalls, is handed the relay by a plain GET;
    every answer may be read by a page on a null origin;
    the token never reaches the service's log;
    and the two pages that hold a token, the game's voice overlay and the
    launcher's voice page, POST it, the overlay taking the freshest one from
    the chat socket.

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
const { spawn } = require('child_process');

const CR = String.fromCharCode(13);
const VOICE = process.env.VOICE || path.join(REPO_DIR, 'voice', 'voice-server.js');
const SECRET = 'a shared secret for the relay';

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
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

const KEY = crypto.randomBytes(32).toString('hex');
function tokenFor(pid, until) {
  const body = String(pid) + '.' + String(until || Date.now() + 3600000);
  return 'v1.' + body + '.' + crypto.createHmac('sha256', KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

let PORT = 0;
/* /ice as a page asks it: a plain text body, so no preflight. */
function ice(method, body, forwarded) {
  return new Promise((ok) => {
    const headers = { origin: 'null' };
    if (body != null) { headers['content-type'] = 'text/plain;charset=UTF-8'; headers['content-length'] = Buffer.byteLength(body); }
    if (forwarded) { headers['x-forwarded-for'] = '203.0.113.7'; }
    const req = http.request({ host: '127.0.0.1', port: PORT, path: '/ice', method: method, headers: headers, agent: false }, (res) => {
      let b = '';
      res.on('data', (d) => { b += d; });
      res.on('end', () => {
        let doc = null;
        try { doc = JSON.parse(b); } catch (e) { }
        ok({ status: res.statusCode, cors: res.headers['access-control-allow-origin'], list: (doc && doc.iceServers) || null });
      });
    });
    req.on('error', () => ok({ status: 0, cors: null, list: null }));
    req.end(body == null ? undefined : body);
  });
}
const STUN = JSON.stringify([{ urls: 'stun:stun.l.google.com:19302' }]);
const stunOnly = (r) => r.status === 200 && JSON.stringify(r.list) === STUN;
const relayOf = (r) => (r.list || []).find((s) => [].concat(s.urls)[0] === 'turn:relay.example.net:3478');

(async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1307-'));
  fs.copyFileSync(VOICE, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(path.dirname(VOICE), 'headlines.js'), path.join(dir, 'headlines.js'));
  fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);
  PORT = await freePort('127.0.0.1');
  const srv = spawn(process.execPath, ['voice-server.js'], { cwd: dir,
    env: Object.assign({}, process.env, { THORNSWOOD_VOICE_PORT: String(PORT), THORNSWOOD_VOICE_BIND: '127.0.0.1',
                                          THORNSWOOD_SITE: '', THORNSWOOD_CHAT_DIR: path.join(dir, 'chat'),
                                          THORNSWOOD_TURN_URL: 'turn:relay.example.net:3478',
                                          THORNSWOOD_TURN_SECRET: SECRET, THORNSWOOD_TURN_TTL: '600' }) });
  let srvLog = '';
  srv.stdout.on('data', (d) => { srvLog += d; });
  srv.stderr.on('data', (d) => { srvLog += d; });
  await listening(srv, PORT);
  const good = tokenFor(41);

  console.log('a stranger, through Caddy:');
  let r = await ice('GET', null, true);
  yes('a plain GET is handed the STUN list and nothing else', stunOnly(r));
  r = await ice('POST', JSON.stringify({}), true);
  yes('a POST with no token is handed the STUN list', stunOnly(r));
  r = await ice('POST', JSON.stringify({ token: 'v1.41.' + (Date.now() + 3600000) + '.madeup' }), true);
  yes('a made up token is handed the STUN list', stunOnly(r));
  r = await ice('POST', JSON.stringify({ token: tokenFor(41, Date.now() - 1000) }), true);
  yes('an expired token is handed the STUN list', stunOnly(r));
  r = await ice('GET', null, true);
  yes('and every one of those may be read from a null origin', r.cors === '*');

  console.log('\na page that holds a join token that checks out:');
  r = await ice('POST', JSON.stringify({ token: good }), true);
  const relay = relayOf(r);
  yes('is handed STUN first', r.status === 200 && !!r.list && JSON.stringify(r.list[0]) === JSON.stringify(JSON.parse(STUN)[0]));
  yes('and the relay', !!relay);
  const until = relay ? Number(relay.username) : 0;
  const now = Math.floor(Date.now() / 1000);
  yes('with a username that is an expiry about ten minutes out', until > now + 500 && until < now + 700);
  yes('and a password coturn takes, HMAC-SHA1 of it',
      !!relay && relay.credential === crypto.createHmac('sha1', SECRET).update(relay.username).digest('base64'));
  yes('readable from a null origin', r.cors === '*');

  console.log('\nthis machine itself:');
  r = await ice('GET', null, false);
  yes('a plain GET is handed the relay, which is what Install-Voice.ps1 reads', !!relayOf(r));

  console.log('\nthe log and the pages:');
  yes('the token never reaches the service\'s log', srvLog.indexOf(good) < 0);
  const overlay = fs.readFileSync(path.join(REPO_DIR, 'game', 'ui', 'thornswood-voice.js'), 'utf8').split(CR).join('');
  const chat = fs.readFileSync(path.join(REPO_DIR, 'game', 'ui', 'thornswood-chat.js'), 'utf8').split(CR).join('');
  const host = fs.readFileSync(path.join(REPO_DIR, 'launcher', 'voice-host.html'), 'utf8').split(CR).join('');
  yes('the chat socket hands out the token it holds now',
      /token: function \(\) \{ return TOKEN; \}/.test(chat));
  yes('the game\'s voice overlay takes it from there and POSTs it to /ice',
      /n\.token\(\)/.test(overlay) && /'\/ice',\s*\{ method: 'POST', body: JSON\.stringify\(\{ token: tok \}\) \}/.test(overlay));
  yes('the launcher\'s voice page POSTs its own',
      /'\/ice', \{ method: 'POST', body: JSON\.stringify\(\{ token: \(cfg && cfg\.token\) \|\| '' \}\) \}/.test(host));
  yes('neither sets a header that would need a preflight',
      !/'\/ice'[^)]*headers/.test(overlay) && !/'\/ice'[^)]*headers/.test(host));

  await new Promise((ok) => { srv.once('exit', ok); srv.kill(); });
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.log('FAIL  the harness itself: ' + (e && e.stack || e)); process.exit(1); });
