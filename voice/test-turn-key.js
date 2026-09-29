/*
  test-turn-key.js

  The TURN relay's key can sit in a file beside the voice service, and with no
  file nothing changes at all.

  From the To Do List, "Voice is a full peer-to-peer mesh with no relay and no
  cap, and the code already admits a pair that cannot connect is simply lost".
  Step one there is a relay, with its credentials minted by the service and
  the secret kept on the VPS, named by location only. The service could
  already make those credentials from THORNSWOOD_TURN_SECRET, but
  Install-Voice.ps1 puts the service's whole environment on the command line
  of the shell that starts it, so the only way in for the key was a place it
  could be read back out of. Now it can be turn-key.txt in the service's
  folder, the way token-key.txt already is.

  Nobody has stood up a relay, so what matters first is that this changes
  nothing while the file is not there. That is held here byte for byte: the
  /ice answer every page reads and its headers, the fields of /health, and the
  log, as the service wrote them before the file existed. The three pages each
  start from a list of their own and swap it for whatever /ice says, so the
  same answer means the same pages.

  Then the file itself: made into credentials the way coturn's REST scheme
  expects, read correctly whatever encoding a Windows box wrote it in, never
  logged, and beaten by the variable when both are set.

  Runs the real voice/voice-server.js in scratch folders on a spare
  port. Never connects to anything off this machine.
*/
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const vm = require('vm');
const crypto = require('crypto');

const PORT = 7921;
const BASE = 'http://127.0.0.1:' + PORT;
const TOOLS = path.resolve(__dirname, '..', 'tools');

// What /ice answered, to the byte, before any of this. The STUN server the
// pages had always had typed into them, and nothing else.
const STUN_ONLY = '{"iceServers":[{"urls":"stun:stun.l.google.com:19302"}]}';
// And /health's fields, in the order it wrote them. chatRange came in with
// local chat (voice/test-local-chat.js), and the five from backed on
// with the backpressure work (voice/test-backpressure.js), and closedSilent
// with the keepalive's other half (voice/test-keepalive.js), each separately
// from the relay key.
const HEALTH_FIELDS = ['ok', 'build', 'auth', 'uptimeSeconds', 'startedAt', 'bind', 'turn',
                       'chatRange', 'peers', 'tracked', 'queuedCommands',
                       'backed', 'largestQueueBytes', 'droppedPositions', 'skippedRosters',
                       'closedBacklogged', 'closedSilent'];
// The two lines every start wrote, with nothing configured.
const START_LOG = '[voice] listening on 0.0.0.0:' + PORT + '\n' +
                  '[voice] positions accepted from loopback at POST /positions\n';

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }
function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

/*
  The real service in a scratch folder, with the files given beside it. A file
  given as null is made as a folder of that name, which is a file that is there
  and cannot be read. Nothing from this machine's own THORNSWOOD_ settings is
  passed through, so a developer's environment cannot change the answer.
*/
async function run(env, files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'turnkey-'));
  fs.copyFileSync(path.join(__dirname, 'voice-server.js'), path.join(dir, 'voice-server.js'));
  fs.writeFileSync(path.join(dir, 'token-key.txt'), 'a join token key for this test only');
  for (const name of Object.keys(files || {})) {
    if (files[name] === null) fs.mkdirSync(path.join(dir, name));
    else fs.writeFileSync(path.join(dir, name), files[name]);
  }
  const clean = {};
  for (const k of Object.keys(process.env)) { if (!/^THORNSWOOD_/i.test(k)) clean[k] = process.env[k]; }
  const srv = spawn(process.execPath, ['voice-server.js'], {
    cwd: dir,
    env: Object.assign(clean, { THORNSWOOD_VOICE_PORT: String(PORT), THORNSWOOD_SITE: '' }, env)
  });
  const exited = new Promise((r) => srv.once('exit', r));
  let log = '';
  srv.stdout.on('data', (d) => { log += d; });
  srv.stderr.on('data', (d) => { log += d; });

  const out = { up: false, ice: null, iceText: '', iceHeaders: {}, health: null, healthText: '', log: '', dir: dir };
  for (let i = 0; i < 60 && !out.up; i++) {
    try { out.up = (await fetch(BASE + '/health')).ok; } catch (e) { }
    if (!out.up) { await sleep(150); }
  }
  if (out.up) {
    const r = await fetch(BASE + '/ice', { headers: { Origin: 'null' } });
    r.headers.forEach((v, k) => { if (k !== 'date') out.iceHeaders[k] = v; });
    out.iceText = await r.text();
    try { out.ice = JSON.parse(out.iceText).iceServers; } catch (e) { out.ice = null; }
    out.healthText = await (await fetch(BASE + '/health')).text();
    try { out.health = JSON.parse(out.healthText); } catch (e) { out.health = null; }
  }
  srv.kill();
  await exited;
  out.log = log.split(dir).join('<dir>');
  try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { }
  return out;
}

// What coturn's use-auth-secret scheme accepts for a username.
function coturnPass(key, user) { return crypto.createHmac('sha1', key).update(user).digest('base64'); }

// A key shaped like a real static-auth-secret, made fresh every run, so a
// line that leaks it cannot pass by luck.
const KEY = crypto.randomBytes(24).toString('hex');
const URL1 = 'turn:relay.example.net:3478';
const KEY_AT = '<dir>' + path.sep + 'turn-key.txt';

function leaks(r, key) {
  return r.log.indexOf(key) >= 0 || r.healthText.indexOf(key) >= 0 || r.iceText.indexOf(key) >= 0;
}

(async () => {
  // ---------------------------------------------------------------------------
  console.log('no file and nothing set, which is every box today:');
  let r = await run({}, {});
  yes('the service came up', r.up);
  yes('/ice answers the same bytes it always did: ' + STUN_ONLY, r.iceText === STUN_ONLY);
  yes('with the same headers, including the one a page on a file:// origin needs',
      r.iceHeaders['content-type'] === 'application/json' &&
      r.iceHeaders['cache-control'] === 'no-store' &&
      r.iceHeaders['access-control-allow-origin'] === '*');
  yes('/health has the same fields in the same order', !!r.health && same(Object.keys(r.health), HEALTH_FIELDS));
  yes('and still says there is no relay', !!r.health && r.health.turn === 'none');
  yes('the log is the two lines every start writes, and nothing about a relay', r.log === START_LOG);

  // Each page starts from its own list and swaps in whatever /ice answers, so
  // an unchanged answer leaves every page exactly where it started.
  const pages = [
    ['the in-game page', path.join(TOOLS, '..', 'game', 'ui', 'thornswood-voice.js')],
    ['the launcher overlay', path.join(TOOLS, '..', 'launcher', 'voice-host.html')],
    ['the plain page the service serves', path.join(__dirname, 'public', 'voice.js')]
  ];
  for (const p of pages) {
    let text = '';
    try { text = fs.readFileSync(p[1], 'utf8'); } catch (e) { text = ''; }
    const m = /(?:var|let) ICE = (\[[^\n]*?\]);/.exec(text);
    let start = null;
    try { start = m ? vm.runInNewContext('(' + m[1] + ')') : null; } catch (e) { start = null; }
    yes(p[0] + ' starts from the very list /ice hands it, so reading it changes nothing',
        !!start && !!r.ice && same(start, r.ice));
  }

  // ---------------------------------------------------------------------------
  console.log('\nno file, and a relay address with no key, which was already refused:');
  r = await run({ THORNSWOOD_TURN_URL: URL1 }, {});
  yes('/ice still answers STUN only', r.iceText === STUN_ONLY);
  yes('/health still calls it misconfigured', !!r.health && r.health.turn === 'MISCONFIGURED');
  yes('the log says what it always said and nothing about a key file',
      /is set but no credentials/.test(r.log) && r.log.indexOf('turn-key.txt') < 0);

  // ---------------------------------------------------------------------------
  console.log('\nthe key in turn-key.txt, written in Notepad, with the address set:');
  r = await run({ THORNSWOOD_TURN_URL: URL1 }, { 'turn-key.txt': KEY + '\r\n' });
  yes('/health says the credential is ephemeral', !!r.health && r.health.turn === 'ephemeral');
  const t = (r.ice || [])[1] || {};
  yes('STUN is still first and the relay is second',
      !!r.ice && same(r.ice[0], { urls: 'stun:stun.l.google.com:19302' }) && same(t.urls, [URL1]));
  const now = Math.floor(Date.now() / 1000);
  yes('the username is an expiry about an hour out', Number(t.username) > now + 3500 && Number(t.username) < now + 3700);
  yes('the credential is HMAC-SHA1 of it under the key in the file, as coturn expects',
      typeof t.username === 'string' && t.credential === coturnPass(KEY, t.username));
  yes('the log says where the key was read from', r.log.indexOf('[voice] relay key read from ' + KEY_AT + '\n') >= 0);
  yes('and the key itself is nowhere: not the log, not /health, not /ice', !leaks(r, KEY));

  // ---------------------------------------------------------------------------
  // Windows PowerShell's > and Out-File write UTF-16 with a byte order mark.
  // Read as UTF-8 that is a different key, the relay refuses every credential,
  // and nothing says why.
  console.log('\nthe key written by Windows PowerShell\'s >, which is UTF-16:');
  const utf16 = Buffer.concat([Buffer.from([0xFF, 0xFE]), Buffer.from(KEY + '\r\n', 'utf16le')]);
  r = await run({ THORNSWOOD_TURN_URL: URL1 }, { 'turn-key.txt': utf16 });
  let u = (r.ice || [])[1] || {};
  yes('the credential is made from the key, not from the bytes around it',
      typeof u.username === 'string' && u.credential === coturnPass(KEY, u.username));

  console.log('\nthe key written by Set-Content -Encoding UTF8, which puts a byte order mark first:');
  const bom8 = Buffer.concat([Buffer.from([0xEF, 0xBB, 0xBF]), Buffer.from(KEY + '\r\n', 'utf8')]);
  r = await run({ THORNSWOOD_TURN_URL: URL1 }, { 'turn-key.txt': bom8 });
  u = (r.ice || [])[1] || {};
  yes('the credential is made from the key, not from the mark',
      typeof u.username === 'string' && u.credential === coturnPass(KEY, u.username));

  // ---------------------------------------------------------------------------
  console.log('\nthe key and no address:');
  r = await run({}, { 'turn-key.txt': KEY });
  yes('no relay is offered: /ice is STUN only, to the byte', r.iceText === STUN_ONLY);
  yes('/health says none', !!r.health && r.health.turn === 'none');
  yes('the log says the key is there but the address is not',
      r.log.indexOf('[voice] relay key read from ' + KEY_AT +
                    ', but THORNSWOOD_TURN_URL is not set, so no relay is offered\n') >= 0);
  yes('and the key itself is nowhere', !leaks(r, KEY));

  // ---------------------------------------------------------------------------
  console.log('\nthe variable and the file both set:');
  const FROM_ENV = crypto.randomBytes(24).toString('hex');
  r = await run({ THORNSWOOD_TURN_URL: URL1, THORNSWOOD_TURN_SECRET: FROM_ENV }, { 'turn-key.txt': KEY });
  u = (r.ice || [])[1] || {};
  yes('the variable wins', typeof u.username === 'string' && u.credential === coturnPass(FROM_ENV, u.username));
  yes('the file is not read at all, so the log does not name it', r.log.indexOf('turn-key.txt') < 0);
  yes('and neither key is anywhere', !leaks(r, KEY) && !leaks(r, FROM_ENV));

  // ---------------------------------------------------------------------------
  console.log('\na file with nothing in it:');
  r = await run({ THORNSWOOD_TURN_URL: URL1 }, { 'turn-key.txt': '  \r\n' });
  yes('is the same as no file: STUN only and misconfigured',
      r.iceText === STUN_ONLY && !!r.health && r.health.turn === 'MISCONFIGURED');
  yes('and the log does not name it', r.log.indexOf('turn-key.txt') < 0);

  console.log('\na turn-key.txt that is there and cannot be read:');
  r = await run({ THORNSWOOD_TURN_URL: URL1 }, { 'turn-key.txt': null });
  yes('the service still comes up', r.up);
  yes('serves no relay', r.iceText === STUN_ONLY && !!r.health && r.health.turn === 'MISCONFIGURED');
  yes('and says it could not read the file, by where it is',
      r.log.indexOf('[voice] could not read ' + KEY_AT + ' (') >= 0);

  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exitCode = fail ? 1 : 0;
})();
