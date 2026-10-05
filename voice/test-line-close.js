/*
  test-line-close.js

  The line at the menu (#481), the relay's half. Patrick, 29 Sep: "they
  shouldn't need to check in while waiting in the queue ... just have it
  automatically lose a player's spot when they disconnect."

  The menu waits in line over its chat socket to this service. When the
  socket that said "/line" closes, and no other socket of the same profile is
  waiting, the game server has to hear of it at once: "/line gone" under that
  profile, marked relay, which nobody can send by typing it. And GET
  /commands carries this process's boot stamp, so the gamemode can tell a
  restart (whose sockets die without a word) and give every menu a minute to
  ask again.

  This spawns the real voice-server.js in a scratch folder on a spare port
  and drives it over real WebSockets, then restarts it. Nothing here is a
  stand-in.

  Read only apart from its own temp folder.
*/
const { spawn } = require('child_process');
const fs = require('fs');
const crypto = require('crypto');
const net = require('net');
const path = require('path');
const os = require('os');

// Set by start(), from the system, each time the service starts. It was a
// fixed 7911, the same as test-cull.js and tests/test-command-ack.js (#1703).
let PORT = 0;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-lineclose-'));
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
let log = '';
async function start() {
  PORT = await freePort('0.0.0.0');
  srv = spawn(process.execPath, ['voice-server.js'], {
    cwd: dir,
    env: Object.assign({}, process.env, {
      THORNSWOOD_VOICE_PORT: String(PORT),
      THORNSWOOD_SITE: '',
      THORNSWOOD_CHAT_DIR: path.join(dir, 'chat'),
    }),
  });
  srv.stdout.on('data', (d) => { log += d; });
  srv.stderr.on('data', (d) => { log += d; });
  await listening(srv, PORT);
}

/* Ended rather than exited; see test-keepalive.js. */
function done(code) {
  process.exitCode = code;
  try { srv.kill(); } catch (e) { }
  setTimeout(() => {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { }
  }, 300).unref();
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

async function ready() {
  const r = await fetch('http://127.0.0.1:' + PORT + '/health');
  if (!r.ok) { throw new Error('the service answered /health with ' + r.status + '. log:\n' + log); }
  return await r.json();
}

function person(profileId, name) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket('ws://127.0.0.1:' + PORT + '/', ['thornswood', tokenFor(profileId)]);
    const me = { ws: ws, peer: 0 };
    ws.onopen = () => ws.send(JSON.stringify({ t: 'join', profileId: profileId, name: name }));
    ws.onmessage = (ev) => {
      let m; try { m = JSON.parse(ev.data); } catch (e) { return; }
      if (m.t === 'welcome') { me.peer = m.peer; resolve(me); }
    };
    ws.onerror = () => reject(new Error('socket error joining as ' + name));
    setTimeout(() => reject(new Error('no welcome for ' + name + ' in four seconds')), 4000);
  });
}
const say = (p, text) => p.ws.send(JSON.stringify({ t: 'chat', text: text }));
async function commands() {
  return (await (await fetch('http://127.0.0.1:' + PORT + '/commands')).json());
}
async function shut(p) { p.ws.close(); await wait(300); }

(async () => {
  await start();
  const h = await ready();
  console.log('service up: build ' + h.build);
  yes('the build says it has the line close', /line-close-1/.test(h.build));

  // ---- a waiting menu closes -------------------------------------------------
  const waiter = await person(501, 'Waiter');
  say(waiter, '/line');
  await wait(200);
  let got = await commands();
  const boot1 = got.boot;
  yes('GET /commands carries the boot stamp', typeof boot1 === 'string' && boot1.length >= 8);
  yes('the "/line" went to the game server as an ordinary command, not marked relay',
      got.commands.length === 1 && got.commands[0].text === '/line' && got.commands[0].relay === false);
  await shut(waiter);
  got = await commands();
  const gone = got.commands.filter((c) => c.text === '/line gone');
  yes('the waiting socket closing tells the game server at once: "/line gone" under that profile',
      gone.length === 1 && gone[0].profileId === 501);
  yes('marked relay, so the gamemode knows it is the service and not a person', gone[0] && gone[0].relay === true);
  yes('and the service log says so', /profile 501 was waiting in line and its connection closed/.test(log));

  // ---- somebody who never waited, or stopped waiting ---------------------------
  const walker = await person(502, 'Walker');
  say(walker, 'hello');
  say(walker, '/roll 20');
  await wait(200);
  await commands();
  await shut(walker);
  got = await commands();
  yes('a socket that never said "/line" closes without a word to the game server',
      got.commands.filter((c) => c.text === '/line gone').length === 0);
  const leaver = await person(503, 'Leaver');
  say(leaver, '/line');
  say(leaver, '/line leave');
  await wait(200);
  await commands();
  await shut(leaver);
  got = await commands();
  yes('one that said "/line leave" closes without one either (the leave already said it)',
      got.commands.filter((c) => c.text === '/line gone').length === 0);

  // ---- two sockets of one profile ------------------------------------------------
  const a = await person(504, 'Twice');
  const b = await person(504, 'Twice');
  say(a, '/line'); say(b, '/line');
  await wait(200);
  await commands();
  await shut(a);
  got = await commands();
  yes('while another socket of the same profile still waits, one closing says nothing',
      got.commands.filter((c) => c.text === '/line gone').length === 0);
  await shut(b);
  got = await commands();
  yes('the last one closing does', got.commands.filter((c) => c.text === '/line gone' && c.profileId === 504).length === 1);

  // ---- moved out for being idle ---------------------------------------------------
  const idle = await person(505, 'Idle');
  say(idle, '/afk out');
  await wait(200);
  await commands();
  await shut(idle);
  got = await commands();
  yes('a game moved out for being idle waits from its "/afk out", so its close is told too',
      got.commands.filter((c) => c.text === '/line gone' && c.profileId === 505).length === 1);

  // ---- a typed "/line gone" -------------------------------------------------------
  const typer = await person(506, 'Typer');
  say(typer, '/line gone');
  await wait(200);
  got = await commands();
  yes('a person typing "/line gone" is not marked relay, so the gamemode does not take it',
      got.commands.filter((c) => c.text === '/line gone').every((c) => c.relay === false));
  await shut(typer);

  // ---- a restart -------------------------------------------------------------------
  // The first service is waited out, and the second is on a port of its own,
  // so nothing below can be answered by the one that was stopped.
  await new Promise((r) => { srv.once('exit', r); srv.kill(); });
  await start();
  await ready();
  got = await commands();
  yes('after a restart the boot stamp is new, which is how the gamemode knows to give the line a minute',
      typeof got.boot === 'string' && got.boot !== boot1);

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
