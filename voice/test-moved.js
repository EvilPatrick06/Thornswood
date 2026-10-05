// test-moved.js
//
// Issue #482: each person is sent only the positions of people near enough to
// hear, or in their party, and only when they changed.
//
// The cull (voice/test-cull.js) took the tick from every person's row to each
// person's view. That view was still sent whole five times a second whether
// anybody in it had moved or not, and most of an evening is people standing.
// Now the first tick after a join is the whole view, { t: 'pos' }, and after
// that { t: 'moved' } carries only rows that changed and the ids that left the
// view (gone), or nothing at all.
//
// This runs voice/voice-server.js in a temp folder on a spare port, feeds it
// two hundred people across ten cells, joins a real websocket for each, keeps
// each one's table the way the clients do, and counts every byte on the wire:
//
//   standing   nobody moves for three seconds
//   walking    forty of them walk, a step every 200 ms, for four seconds
//
// Before is what the tick sent until now: each person's whole view, every
// tick. It is worked out from the tables the sockets hold, which the checks
// below show are exactly the views. VOICE_SERVER points it at another copy of
// the service, which is how the numbers for the code before this were taken.
//
// Read only. Nothing outside the temp folder is touched.
const fs = require('fs');
const crypto = require('crypto');
const os = require('os');
const net = require('net');
const path = require('path');
const { spawn } = require('child_process');

const SERVER = process.env.VOICE_SERVER || path.join(__dirname, 'voice-server.js');
// Set by ready(), from the system. It was a fixed 7913 (#1703).
let PORT = 0;
const TICK_MS = 200;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

// ------------------------------------------------------------- the people
const CELLS = ['3c:Skyrim.esm', '1605e:Skyrim.esm', '16a0b:Skyrim.esm', '16bd9:Skyrim.esm',
               '13a8e:Skyrim.esm', '1a6ec:Skyrim.esm', '133c6:Skyrim.esm', '16779:Skyrim.esm',
               '15fc5:Skyrim.esm', '1c3b7:Skyrim.esm'];
const SPREAD = [120000, 4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000, 4000];
let seed = 482;
function rand() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }

// The game's own floats, which carry a dozen digits.
const people = [];
for (let c = 0; c < CELLS.length; c++) {
  for (let k = 0; k < 20; k++) {
    const pid = 5000 + c * 20 + k;
    people.push({
      profileId: pid, cell: CELLS[c], name: 'Person ' + pid, party: '',
      pos: [(rand() - 0.5) * SPREAD[c], (rand() - 0.5) * SPREAD[c], (rand() - 0.5) * 600],
      angleZ: rand() * 360
    });
  }
}
const byPid = {};
for (const p of people) { byPid[p.profileId] = p; }
// A party across three cells, which is who the party strip points at.
for (const pid of [5000, 5080, 5160]) { byPid[pid].party = 'p1'; }
// Two in the open world, 50 m apart, for the walking-away check.
byPid[5010].pos = [200000.123456, 200000.654321, 0.5];
byPid[5011].pos = [200000.123456 + 50 * 70, 200000.654321, 0.5];
// Somebody who logs off part way through.
const LEAVER = 5030;
let present = people.slice();

// Forty walkers, two from every cell, a step of about a metre a second.
const walkers = people.filter((p, i) => i % 5 === 0 && p.profileId !== 5010 && p.profileId !== 5011);
let walking = false;

function body() {
  return JSON.stringify({ who: present.map((p) => ({
    profileId: p.profileId, pos: p.pos, angleZ: p.angleZ, cell: p.cell, name: p.name, party: p.party
  })) });
}

// ---------------------------------------------------------------- service
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-moved-'));
fs.copyFileSync(SERVER, path.join(dir, 'voice-server.js'));
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
let srv = null;
let log = '';

const sockets = [];
let feeder = null;
/* Ended rather than exited; see test-keepalive.js for the crash that avoids. */
function done(code) {
  process.exitCode = code;
  if (feeder) { clearInterval(feeder); }
  for (const s of sockets) { try { s.close(); } catch (e) { } }
  const rm = () => { try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { } };
  if (srv) { srv.once('exit', rm); try { srv.kill(); } catch (e) { } }
  setTimeout(rm, 300).unref();
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
async function ready() {
  PORT = await freePort('127.0.0.1');
  srv = spawn(process.execPath, ['voice-server.js'], {
    cwd: dir,
    env: Object.assign({}, process.env, {
      THORNSWOOD_VOICE_PORT: String(PORT),
      THORNSWOOD_VOICE_BIND: '127.0.0.1',
      THORNSWOOD_SITE: '',
      THORNSWOOD_CHAT_DIR: path.join(dir, 'chat')
    })
  });
  srv.stdout.on('data', (d) => { log += d; });
  srv.stderr.on('data', (d) => { log += d; });
  await listening(srv, PORT);
  const r = await fetch('http://127.0.0.1:' + PORT + '/health');
  if (!r.ok) { throw new Error('the service answered /health with ' + r.status + '. log:\n' + log); }
  return await r.json();
}

function feed() {
  if (walking) {
    for (const w of walkers) { w.pos = [w.pos[0] + 14.3, w.pos[1] + 7.7, w.pos[2]]; w.angleZ = (w.angleZ + 3.3) % 360; }
  }
  return fetch('http://127.0.0.1:' + PORT + '/positions', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: body()
  }).then((r) => r.status).catch(() => 0);
}

/* A text frame's bytes on the wire: the header the service writes, then the body. */
function frameBytes(text) {
  const n = Buffer.byteLength(text);
  return n + (n < 126 ? 2 : (n < 65536 ? 4 : 10));
}

/* One person's socket, holding its table the way every client does. */
function join(pid) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket('ws://127.0.0.1:' + PORT + '/', ['thornswood', tokenFor(pid)]);
    const me = { pid: pid, ws: ws, table: null, bytes: 0, msgs: 0, moved: 0, firstAt: 0, at: 0 };
    sockets.push(ws);
    const late = setTimeout(() => reject(new Error('no welcome for ' + pid)), 20000);
    ws.onopen = () => { ws.send(JSON.stringify({ t: 'join', profileId: pid, name: 'Person ' + pid })); };
    ws.onmessage = (ev) => {
      const text = String(ev.data);
      if (text.startsWith('{"t":"peers"')) { return; }
      let m = null;
      try { m = JSON.parse(text); } catch (e) { return; }
      if (m.t === 'welcome') { clearTimeout(late); resolve(me); return; }
      if (m.t === 'pos') {
        me.table = m.who || {}; me.at = m.at; if (!me.firstAt) { me.firstAt = m.at; }
        me.bytes += frameBytes(text); me.msgs++;
      }
      if (m.t === 'moved' && me.table) {
        for (const k of Object.keys(m.who || {})) { me.table[k] = m.who[k]; }
        for (const id of (m.gone || [])) { delete me.table[id]; }
        me.at = m.at; me.bytes += frameBytes(text); me.msgs++; me.moved++;
      }
    };
    ws.onerror = () => { clearTimeout(late); reject(new Error('socket for ' + pid + ' failed')); };
  });
}

/* A table as text with its keys in order, to compare two of them. */
function canon(t) {
  const out = {};
  for (const k of Object.keys(t || {}).sort()) { out[k] = t[k]; }
  return JSON.stringify(out);
}

/* What the tick used to send everybody: their whole view, every tick. */
function wholeTick(joined) {
  let b = 0;
  for (const j of joined) { b += frameBytes(JSON.stringify({ t: 'pos', at: j.at, who: j.table || {} })); }
  return b;
}

function counters(joined) { return joined.reduce((a, j) => ({ bytes: a.bytes + j.bytes, msgs: a.msgs + j.msgs }), { bytes: 0, msgs: 0 }); }

(async () => {
  const h = await ready();
  console.log('      the service under test answers build ' + h.build);
  yes('the service takes the feed', await feed() === 204);
  feeder = setInterval(() => { feed(); }, TICK_MS);

  const joined = [];
  for (let i = 0; i < people.length; i += 50) {
    joined.push(...await Promise.all(people.slice(i, i + 50).map((p) => join(p.profileId))));
    console.log('      ' + joined.length + ' joined');
  }
  const of = {};
  for (const j of joined) { of[j.pid] = j; }
  for (let i = 0; i < 50 && !joined.every((j) => j.table); i++) { await wait(100); }
  yes('every one of them was sent their whole view', joined.every((j) => j.table));
  await wait(600);

  yes('rows are sent in whole units and whole degrees',
      joined.every((j) => Object.keys(j.table).every((k) => {
        const r = j.table[k];
        return Array.isArray(r.pos) && r.pos.every(Number.isInteger) && Number.isInteger(r.angleZ);
      })));

  // ------------------------------------------------------------ standing
  const s0 = counters(joined);
  await wait(3000);
  const s1 = counters(joined);
  const standTicks = 3000 / TICK_MS;
  const standAfter = (s1.bytes - s0.bytes) / standTicks;
  const standBefore = wholeTick(joined);
  console.log('      standing: ' + (s1.msgs - s0.msgs) + ' messages in 3 s');
  yes('two hundred people standing still are sent nothing after their first view',
      s1.msgs - s0.msgs === 0);

  // ------------------------------------------------------------- walking
  walking = true;
  await wait(TICK_MS * 2);
  const w0 = counters(joined);
  await wait(4000);
  const w1 = counters(joined);
  walking = false;
  const walkTicks = 4000 / TICK_MS;
  const walkAfter = (w1.bytes - w0.bytes) / walkTicks;
  const walkBefore = wholeTick(joined);
  yes('people who can hear a walker are told they moved',
      joined.filter((j) => j.moved > 0).length > walkers.length);
  await wait(TICK_MS * 3);

  // ------------------------------------------- walking away, logging off
  const a = of[5010], b = of[5011];
  yes('two in the open world 50 m apart see each other', !!(a.table[5011] && b.table[5010]));
  byPid[5011].pos = [200000 + 400 * 70, 200000, 0];
  await wait(TICK_MS * 4);
  yes('walking 400 m away takes them out of each other\'s view', !a.table[5011] && !b.table[5010]);
  yes('and each still has their own row', !!(a.table[5010] && b.table[5011]));

  const hadLeaver = joined.filter((j) => j.pid !== LEAVER && j.table[LEAVER]);
  present = present.filter((p) => p.profileId !== LEAVER);
  await wait(TICK_MS * 4);
  yes('somebody who logs off leaves the view of everybody who had them (' + hadLeaver.length + ')',
      hadLeaver.length > 0 && hadLeaver.every((j) => !j.table[LEAVER]));

  // ------------------------------------ the tables are exactly the views
  /*
    A second socket for the same person is sent the whole view on its first
    tick. With nobody moving, it has to match the table the first socket
    built up out of a whole view and every change since.
  */
  await wait(TICK_MS * 3);
  const sample = joined.filter((j, i) => i % 10 === 0 && j.pid !== LEAVER);
  const fresh = await Promise.all(sample.map((j) => join(j.pid)));
  for (let i = 0; i < 30 && !fresh.every((f) => f.table); i++) { await wait(100); }
  const mismatched = sample.filter((j, i) => canon(j.table) !== canon(fresh[i].table));
  yes('what each socket holds after the changes is exactly its whole view (' +
      mismatched.length + ' of ' + sample.length + ' differ)', mismatched.length === 0);
  yes('the party strip still gets the party across cells',
      !!(of[5000].table[5080] && of[5000].table[5160] && of[5160].table[5000]));

  // ------------------------------------------------------------ the bill
  const mbs = (x) => (x * (1000 / TICK_MS) / 1e6).toFixed(3);
  const gbEvening = (x) => (x * (1000 / TICK_MS) * 4 * 3600 / 1e9).toFixed(1);
  console.log('');
  console.log('      two hundred people across ten cells, bytes a tick on the wire:');
  console.log('        standing, whole view every tick: ' + standBefore + ' (' + mbs(standBefore) + ' MB/s, ' +
              gbEvening(standBefore) + ' GB over four hours)');
  console.log('        standing, only what changed:     ' + Math.round(standAfter) + ' (' + mbs(standAfter) + ' MB/s)');
  console.log('        forty walking, whole view every tick: ' + walkBefore + ' (' + mbs(walkBefore) + ' MB/s, ' +
              gbEvening(walkBefore) + ' GB over four hours)');
  console.log('        forty walking, only what changed:     ' + Math.round(walkAfter) + ' (' + mbs(walkAfter) + ' MB/s, ' +
              gbEvening(walkAfter) + ' GB over four hours)');
  console.log('');
  yes('with a fifth of them walking a tick costs under a third of the whole view', walkAfter * 3 < walkBefore);

  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  done(fail ? 1 : 0);
})().catch((e) => {
  console.log('FAIL  ' + (e && e.message));
  fail++;
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  done(1);
});
