/*
  Entry 6, step 6: drive the real voice service and assert what a join does.

  Runs the shipped voice-server.js in a scratch folder on a spare port, mints
  tokens through its own /token route, and joins over a real WebSocket. Nothing
  here is a stand-in: the file under test is voice/voice-server.js.

  THORNSWOOD_SITE is left unset on purpose, so owns() answers 'unchecked' and
  /token mints without the site. That is the same path a site outage takes, and
  it is the one worth proving works, because the alternative is voice dying
  whenever the website hiccups.
*/
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

// The repo this file sits in, so it runs from anywhere.
const REPO = path.resolve(__dirname, '..');
const PORT = 7901;
const AUTH = process.argv[2] || 'on';

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'voiceauth-'));
fs.copyFileSync(path.join(__dirname, 'voice-server.js'), path.join(dir, 'voice-server.js'));
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

const post = (route, body) => fetch('http://127.0.0.1:' + PORT + route, {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
});

/*
  What a join that cannot prove itself should get, for the mode under test.

  'on' refuses it. 'log' lets it in as whatever profile it claimed and writes a
  line. Both are correct; which one is correct depends entirely on the setting,
  so the expectation has to as well. Asserting the 'on' answers against 'log'
  was a fault in this file and not in the service.
*/
function refused(why, claimed) {
  return AUTH === 'on' ? { t: 'denied', why: why } : { t: 'welcome', profileId: claimed };
}

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

const srv = spawn(process.execPath, ['voice-server.js'], {
  cwd: dir,
  env: Object.assign({}, process.env, {
    THORNSWOOD_VOICE_PORT: String(PORT),
    THORNSWOOD_VOICE_AUTH: AUTH,
    THORNSWOOD_SITE: '',
  }),
});
let log = '';
srv.stdout.on('data', (d) => { log += d; });
srv.stderr.on('data', (d) => { log += d; });

async function ready() {
  for (let i = 0; i < 60; i++) {
    try { const r = await fetch('http://127.0.0.1:' + PORT + '/health'); if (r.ok) return await r.json(); } catch (e) {}
    await new Promise(r => setTimeout(r, 150));
  }
  throw new Error('the service never came up. log:\n' + log);
}

(async () => {
  const h = await ready();
  console.log('service up: build ' + h.build + ', auth ' + h.auth + ', secret ' + h.secret);
  console.log('');

  // A token for profile 4242, minted by the service itself.
  const r = await post('/token', { profileId: 4242, ticket: 'anything, there is no site to ask' });
  const minted = await r.json();
  check('/token mints without a site to ask', [r.status, minted.profileId, minted.checked], [200, 4242, false]);
  check('/token refuses a request with no profile', (await post('/token', { ticket: 'x' })).status, 400);

  console.log('');
  console.log('THE THREE CASES, with auth ' + AUTH + ':');
  check('a real token joins as its own profile',
        await join({ t: 'join', profileId: 4242, name: 'tester', token: minted.token }), { t: 'welcome', profileId: 4242 });

  check('no token at all is ' + (AUTH === 'on' ? 'refused' : 'allowed and written down'),
        await join({ t: 'join', profileId: 4242, name: 'stranger' }), refused('no token', 4242));

  check('somebody else\'s profile in the message loses to the token',
        await join({ t: 'join', profileId: 99, name: 'liar', token: minted.token }), { t: 'welcome', profileId: 4242 });

  console.log('');
  console.log('and the rest of the ways in:');
  check('a made up token is ' + (AUTH === 'on' ? 'refused' : 'allowed and written down'),
        await join({ t: 'join', profileId: 4242, token: 'v1.4242.' + (Date.now() + 60000) + '.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' }),
        refused('a token that does not check out', 4242));
  check('an expired token is ' + (AUTH === 'on' ? 'refused, and named as expired' : 'allowed and named as expired'),
        await join({ t: 'join', profileId: 7, token: sign(7, Date.now() - 1000) }),
        refused('an expired token', 7));
  check('a token signed with another key is ' + (AUTH === 'on' ? 'refused' : 'allowed and written down'),
        await join({ t: 'join', profileId: 4242, token: 'v1.4242.' + (Date.now() + 60000) + '.' +
          crypto.createHmac('sha256', 'a different key').update('4242.' + (Date.now() + 60000)).digest('base64')
            .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '') }),
        refused('a token that does not check out', 4242));

  console.log('');
  console.log('what the service wrote down:');
  for (const line of log.split('\n')) {
    if (/REFUSED|UNPROVEN|claimed profile|UNCHECKED/.test(line)) console.log('  ' + line.trim());
  }

  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  // Kill, then let the loop drain before exiting. Calling process.exit while
  // the child's pipes are still closing trips a libuv assertion on Windows,
  // which looks like a failure and is not one.
  process.exitCode = fail ? 1 : 0;
  srv.kill();
  setTimeout(() => {}, 150);
})().catch((e) => { console.error(e); srv.kill(); process.exitCode = 1; });
