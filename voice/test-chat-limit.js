/*
  test-chat-limit.js

  The To Do List, entry 149: "Chat is server-wide, unfiltered, has no rate
  limit anywhere". Every plain line went to every peer the moment it arrived,
  so one open console could fill every screen in the world.

  What it has to be done when, in the entry's own words: "a local harness
  connecting one socket and sending twenty chat lines in one second sees at
  most five broadcast and exactly one notice returned to the sender".

  This spawns the real voice-server.js in a scratch folder on a spare port,
  with its shipped numbers (five at once, one more every 1500ms), and drives
  it over two real WebSockets: one that floods and one that listens. Nothing
  here is a stand-in.

  And the part that is easy to get wrong while the limit still looks like it
  works: slash lines share this socket with the plugins' own reports, /chopped
  on every fall of the axe among them, so twenty of those sent by somebody who
  has just been slowed must all still reach the game server.

  Read only apart from its own temp folder.
*/
const { spawn } = require('child_process');
const fs = require('fs');
const crypto = require('crypto');
const net = require('net');
const path = require('path');
const os = require('os');

// Set by ready(), from the system. It was a fixed 7907 (#1703).
let PORT = 0;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-chatlimit-'));
fs.copyFileSync(path.join(__dirname, 'voice-server.js'), path.join(dir, 'voice-server.js'));
fs.copyFileSync(path.join(__dirname, 'headlines.js'), path.join(dir, 'headlines.js'));
// Every connection proves itself since #1303, so this harness signs its own
// join tokens with a key it puts beside its copy of the service. One token
// opens one connection and goes with the handshake since #1337 and #1322.
const KEY = crypto.randomBytes(32).toString('hex');
fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);
function tokenFor(pid) {
  const body = 'v2.' + pid + '.' + Date.now() + '.' + crypto.randomBytes(16).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return body + '.' + crypto.createHmac('sha256', KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
const CHAT_DIR = path.join(dir, 'chat');

let srv = null;
let log = '';

/*
  Ended rather than exited. process.exit while the killed child's pipes are
  still closing trips a libuv assertion on Windows, which looks like a failure
  and is not one. See test-keepalive.js.
*/
function done(code) {
  process.exitCode = code;
  try { srv.kill(); } catch (e) { }
  setTimeout(() => {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { }
  }, 300).unref();
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

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
async function ready() {
  PORT = await freePort('0.0.0.0');
  srv = spawn(process.execPath, ['voice-server.js'], {
    cwd: dir,
    env: Object.assign({}, process.env, {
      THORNSWOOD_VOICE_PORT: String(PORT),
      THORNSWOOD_SITE: '',
      THORNSWOOD_CHAT_DIR: CHAT_DIR,
      // The shipped numbers, not ones picked to make this pass. Cleared in
      // case the machine running this has them set.
      THORNSWOOD_CHAT_BURST: '',
      THORNSWOOD_CHAT_REFILL_MS: '',
    }),
  });
  srv.stdout.on('data', (d) => { log += d; });
  srv.stderr.on('data', (d) => { log += d; });
  await listening(srv, PORT);
  const r = await fetch('http://127.0.0.1:' + PORT + '/health');
  if (!r.ok) { throw new Error('the service answered /health with ' + r.status + '. log:\n' + log); }
  return await r.json();
}

/* A joined socket that keeps every chat message it is sent. */
function person(profileId, name) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket('ws://127.0.0.1:' + PORT + '/', ['thornswood', tokenFor(profileId)]);
    const me = { ws: ws, peer: 0, chat: [] };
    ws.onopen = () => ws.send(JSON.stringify({ t: 'join', profileId: profileId, name: name }));
    ws.onmessage = (ev) => {
      let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
      if (m.t === 'welcome') { me.peer = m.peer; resolve(me); return; }
      if (m.t === 'chat') { me.chat.push(m); }
    };
    ws.onerror = () => reject(new Error('socket error joining as ' + name));
    setTimeout(() => reject(new Error('no welcome for ' + name + ' in four seconds')), 4000);
  });
}

const say = (p, text) => p.ws.send(JSON.stringify({ t: 'chat', text: text }));
const from = (p, who) => p.chat.filter((m) => m.from === who.peer);
const notices = (p) => p.chat.filter((m) => m.from === 0);

(async () => {
  const h = await ready();
  console.log('service up: build ' + h.build);
  console.log('');

  const loud = await person(11, 'Loud');
  const quiet = await person(12, 'Quiet');
  await wait(200);

  // ---- twenty lines at once ------------------------------------------------
  const t0 = Date.now();
  for (let i = 1; i <= 20; i++) { say(loud, 'line ' + i); }
  await wait(600);

  const heard = from(quiet, loud).map((m) => m.text);
  console.log('  the room heard ' + heard.length + ' of twenty: ' + JSON.stringify(heard));
  yes('twenty lines sent at once put at most five in the room', heard.length <= 5);
  yes('and the first five do get through, in order, so a quick back and forth is not refused',
      JSON.stringify(heard) === JSON.stringify(['line 1', 'line 2', 'line 3', 'line 4', 'line 5']));
  yes('the sender sees the same five, and not the fifteen that were dropped',
      from(loud, loud).length === heard.length);

  const told = notices(loud);
  yes('the sender is told exactly once, not fifteen times', told.length === 1);
  const text = told.length ? String(told[0].text) : '';
  console.log('  what they are told: ' + JSON.stringify(text));
  yes('the notice says to slow down', /slow down/i.test(text));
  yes('and reads as the service, the way the gamemode\'s own lines do',
      told.length === 1 && told[0].name === 'Thornswood' && told[0].profileId === 0);
  yes('the notice follows the house words: no "player", no em dash',
      text.length > 0 && !/player/i.test(text) && text.indexOf(String.fromCharCode(0x2014)) < 0);
  yes('nobody else is told anything about it', notices(quiet).length === 0);

  // ---- slash lines are never throttled ---------------------------------------
  /* Emptied first, so what is read below is only what this sends. */
  await fetch('http://127.0.0.1:' + PORT + '/commands');
  for (let i = 1; i <= 20; i++) { say(loud, '/chopped'); }
  await wait(400);
  const cmds = (await (await fetch('http://127.0.0.1:' + PORT + '/commands')).json()).commands;
  yes('twenty slash lines from somebody slowed all reach the game server (' + cmds.length + ')',
      cmds.length === 20 && cmds.every((c) => c.text === '/chopped' && c.profileId === 11));
  yes('and they do not bring a second notice with them', notices(loud).length === 1);

  // ---- one person's flood slows nobody else ----------------------------------
  for (let i = 1; i <= 3; i++) { say(quiet, 'quiet ' + i); }
  await wait(300);
  yes('somebody else still gets their three lines out while the first is slowed',
      from(loud, quiet).length === 3 && from(quiet, quiet).length === 3);

  // ---- the log holds what reached the room -----------------------------------
  const logFile = path.join(CHAT_DIR, fs.existsSync(CHAT_DIR) ? (fs.readdirSync(CHAT_DIR)[0] || '') : '');
  let lines = [];
  try {
    lines = fs.readFileSync(logFile, 'utf8').split('\n').filter((l) => l.trim()).map((l) => JSON.parse(l));
  } catch (e) { }
  const saidByLoud = lines.filter((l) => l.kind === 'say' && l.profileId === 11);
  yes('the chat log has the five lines that reached the room as said, not the fifteen that did not',
      saidByLoud.length === 5);
  yes('and every slash line is still in it',
      lines.filter((l) => l.kind === 'command' && l.profileId === 11).length === 20);
  yes('the service log says who was slowed, once', (log.match(/slowed peer/g) || []).length === 1);

  // ---- the bucket refills ------------------------------------------------------
  /*
    One line comes back every 1500ms. 1800ms after the flood there is one, and
    only one, whatever else happened in between. Eleven sent then: the first
    goes, the other ten are dropped, and because a line went through this is a
    new time of being slowed, so they are told again, once.
  */
  const until = t0 + 1800 - Date.now();
  if (until > 0) { await wait(until); }
  const before = from(quiet, loud).length;
  const sentAt = Date.now() - t0;
  for (let i = 1; i <= 11; i++) { say(loud, 'again ' + i); }
  await wait(400);
  const after = from(quiet, loud).slice(before).map((m) => m.text);
  console.log('  eleven more sent ' + sentAt + 'ms after the flood, and the room heard: ' + JSON.stringify(after));
  yes('a second and a half later one line gets through again', JSON.stringify(after) === JSON.stringify(['again 1']));
  yes('and a new flood after that is told once more, so the notice is per time slowed',
      notices(loud).length === 2);

  try { loud.ws.close(); } catch (e) { }
  try { quiet.ws.close(); } catch (e) { }
  await wait(200);
  yes('the service is still up', (await (await fetch('http://127.0.0.1:' + PORT + '/health')).json()).ok === true);

  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  done(fail ? 1 : 0);
})().catch((e) => {
  console.error('FAILED: ' + e.message);
  console.error(log);
  console.log('');
  console.log(pass + ' passed, ' + (fail + 1) + ' failed');
  done(1);
});
