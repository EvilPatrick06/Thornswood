// load-voice.js
//
// How many people the voice service holds, measured on this machine with no
// people at all (#481, step 6). Not a harness: nothing passes or fails, and
// the nightly does not run it. It prints what the service cost at each size.
//
//   node voice\load-voice.js                      25, 50, 100, 200 and 400 people
//   node voice\load-voice.js --people 30,60 --seconds 30 --crowd
//
// For each size it starts its own copy of voice/voice-server.js in a temp
// folder on a port the system hands out, as the harnesses do, with chat
// range on as Install-Voice.ps1 installs it, and plays an evening at it:
//
//   the feed     the gamemode's POST /positions five times a second, every
//                person in it, a fifth of them walking
//   two pages    each person holds two sockets with a join token each, the
//                launcher's voice page and the game's chat (voice: false),
//                which is what a person in the world holds
//   the storm    every socket opens at once, as when the service restarts
//                and every page comes back
//   signalling   once the room is in, every pair of voice pages trades what
//                a WebRTC connection costs through the relay: an offer and
//                an answer of about 3 KB, and six candidates each way,
//                timed from the first offer sent to the last candidate
//                arriving. This process sends all of it from its one
//                thread, so past a hundred or so people that is what sets
//                the time (#2390); load-signalling.js measures the
//                service's own cost
//   talk         each person says a plain line every --talk seconds
//
// People stand about twenty to a cell across as many cells as that takes,
// which is a busy town. --crowd puts everybody in one cell inside hearing
// range instead, the worst case for the position tick, since every person is
// then told about every other one.
//
// The service is started with a probe (-r) that prints its own processor
// time, memory and event loop delay every second; those are the numbers. The
// load is made by this process, so a machine with fewer free cores than
// sockets measures this process as well; the probe reads only the service.
//
// Never point it at the VPS: it starts its own copy and talks to nothing else.
const fs = require('fs');
const os = require('os');
const net = require('net');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  if (i < 0) return dflt;
  const v = process.argv[i + 1];
  return (v === undefined || v.startsWith('--')) ? true : v;
}
const SIZES = String(arg('people', '25,50,100,200,400')).split(',').map(Number).filter((n) => n > 0);
const SECONDS = Number(arg('seconds', 20));
const TALK_S = Number(arg('talk', 30));
const CROWD = arg('crowd', false) === true;
const SERVER = process.env.VOICE_SERVER || path.join(__dirname, 'voice-server.js');
const TICK_MS = 200;

let seed = 481;
function rand() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; }

const PROBE = `
const { monitorEventLoopDelay } = require('perf_hooks');
const h = monitorEventLoopDelay({ resolution: 5 });
h.enable();
let last = process.cpuUsage(), lastAt = process.hrtime.bigint();
setInterval(() => {
  const now = process.hrtime.bigint(), cpu = process.cpuUsage();
  const wall = Number(now - lastAt) / 1e3;
  const used = (cpu.user - last.user) + (cpu.system - last.system);
  last = cpu; lastAt = now;
  const m = process.memoryUsage();
  process.stdout.write('PROBE ' + JSON.stringify({ cores: used / wall, rss: m.rss, heap: m.heapUsed,
    p50: h.percentile(50) / 1e6, p99: h.percentile(99) / 1e6, max: h.max / 1e6 }) + '\\n');
  h.reset();
}, 1000).unref();
`;

function freePort() {
  return new Promise((ok, bad) => {
    const s = net.createServer();
    s.on('error', bad);
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); });
  });
}

function siteThatSaysYes() {
  return new Promise((ok) => {
    const site = http.createServer((req, res) => {
      req.resume();
      req.on('end', () => { res.writeHead(200, { 'content-type': 'application/json' }).end('{"ok":true}'); });
    });
    site.listen(0, '127.0.0.1', () => { site.unref(); ok('http://127.0.0.1:' + site.address().port); });
  });
}

async function service(site) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-load-'));
  fs.copyFileSync(SERVER, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(__dirname, 'headlines.js'), path.join(dir, 'headlines.js'));
  fs.writeFileSync(path.join(dir, 'probe.js'), PROBE);
  const port = await freePort();
  const env = Object.assign({}, process.env, {
    THORNSWOOD_VOICE_PORT: String(port), THORNSWOOD_VOICE_BIND: '127.0.0.1', THORNSWOOD_SITE: site,
    THORNSWOOD_CHAT_RANGE: 'on', THORNSWOOD_CHAT_DIR: path.join(dir, 'chat')
  });
  delete env.THORNSWOOD_VOICE_MOST;
  const proc = spawn(process.execPath, ['-r', './probe.js', 'voice-server.js'], { cwd: dir, env: env });
  const s = { dir, port, proc, log: '', probes: [], badProbes: 0 };
  let line = '';
  proc.stdout.on('data', (d) => {
    line += d;
    let i;
    while ((i = line.indexOf('\n')) >= 0) {
      const l = line.slice(0, i); line = line.slice(i + 1);
      if (!l.startsWith('PROBE ')) { s.log += l + '\n'; continue; }
      // The probe writes each line whole, so one that will not parse is a
      // fault in the probe or a line cut by something else writing: counted
      // in the result, and kept in the log, rather than a second of numbers
      // quietly missing.
      try { s.probes.push(Object.assign({ at: Date.now() }, JSON.parse(l.slice(6)))); }
      catch (e) { s.badProbes++; s.log += 'unreadable probe line: ' + l + '\n'; }
    }
  });
  proc.stderr.on('data', (d) => { s.log += d; });
  await new Promise((ok, bad) => {
    const late = setTimeout(() => bad(new Error('the service did not start:\n' + s.log)), 15000);
    const look = setInterval(() => {
      if (new RegExp('listening on \\S+:' + port).test(s.log)) { clearTimeout(late); clearInterval(look); ok(); }
    }, 20);
    proc.on('exit', (c) => { clearTimeout(late); clearInterval(look); bad(new Error('the service stopped (exit ' + c + '):\n' + s.log)); });
  });
  return s;
}

const agent = new http.Agent({ keepAlive: true, maxSockets: 32 });
function post(port, p, body) {
  return new Promise((ok, bad) => {
    const req = http.request({ host: '127.0.0.1', port, path: p, method: 'POST', agent,
      headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) } }, (res) => {
      let b = ''; res.on('data', (d) => { b += d; }); res.on('end', () => ok({ status: res.statusCode, body: b }));
    });
    req.on('error', bad);
    req.end(body);
  });
}

async function token(port, pid) {
  const r = await post(port, '/token', JSON.stringify({ profileId: pid, ticket: 'load' }));
  if (r.status !== 200) throw new Error('no token for ' + pid + ': ' + r.status + ' ' + r.body);
  return JSON.parse(r.body).token;
}

function people(n) {
  const list = [];
  const cells = CROWD ? 1 : Math.max(1, Math.ceil(n / 20));
  for (let i = 0; i < n; i++) {
    const c = i % cells;
    list.push({ profileId: 10000 + i, cell: (0x3c + c).toString(16) + ':Skyrim.esm', name: 'Person ' + i, party: '',
                pos: [(rand() - 0.5) * 4000, (rand() - 0.5) * 4000, (rand() - 0.5) * 300], angleZ: rand() * 360,
                walks: rand() < 0.2 });
  }
  return list;
}

function avg(list, k) { return list.length ? list.reduce((a, p) => a + p[k], 0) / list.length : 0; }
function most(list, k) { return list.reduce((a, p) => Math.max(a, p[k]), 0); }

/* What one size has running, so a size that does not finish is cleaned up. */
const live = { s: null, socks: [], timers: [] };
async function cleanUp() {
  for (const t of live.timers) clearInterval(t);
  for (const x of live.socks) x.ws.close();   // close() with no code does not throw
  const s = live.s;
  live.s = null; live.socks = []; live.timers = [];
  if (s) {
    await new Promise((r) => { s.proc.once('exit', r); try { s.proc.kill(); } catch (e) { r(); } });
    // force already passes over a folder that is gone; anything else (a file
    // still open) leaves a copy of the service in the temp folder, so say where.
    try { fs.rmSync(s.dir, { recursive: true, force: true }); }
    catch (e) { console.log('could not remove ' + s.dir + ' (' + (e.code || e.message) + '): delete it by hand'); }
  }
}

async function run(n, site) {
  const s = await service(site);
  live.s = s;
  const crowd = people(n);
  const feedBody = () => JSON.stringify({ who: crowd.map((p) => ({ profileId: p.profileId, pos: p.pos, angleZ: p.angleZ,
                                                                   cell: p.cell, name: p.name, party: p.party })) });
  let walking = false;
  // A feed the service refuses or does not answer is what this measures
  // going wrong, so each one is counted in the result, with the first reason.
  const feed = { sent: 0, failed: 0, first: '' };
  const feeder = setInterval(() => {
    if (walking) for (const p of crowd) if (p.walks) { p.pos = [p.pos[0] + 14, p.pos[1] + 8, p.pos[2]]; p.angleZ = (p.angleZ + 3) % 360; }
    feed.sent++;
    post(s.port, '/positions', feedBody()).then((r) => {
      if (r.status !== 204) { feed.failed++; if (!feed.first) feed.first = 'answered ' + r.status; }
    }, (e) => { feed.failed++; if (!feed.first) feed.first = String(e && e.code || e && e.message || e); });
  }, TICK_MS);
  live.timers.push(feeder);

  // Two tokens a person, asked as the launcher asks them, before the storm.
  const toks = [];
  for (let i = 0; i < crowd.length; i += 50) {
    toks.push(...await Promise.all(crowd.slice(i, i + 50).map(async (p) => [p, await token(s.port, p.profileId), await token(s.port, p.profileId)])));
  }

  const meter = { bytes: 0, msgs: 0, signals: 0 };
  const socks = live.socks;
  const voicePages = [];
  const stormFrom = Date.now();
  const mark = s.probes.length;
  await Promise.all(toks.map(([p, t1, t2]) => Promise.all([[t1, true], [t2, false]].map(([tok, voice]) => new Promise((ok, bad) => {
    const ws = new WebSocket('ws://127.0.0.1:' + s.port + '/', ['thornswood', tok]);
    const me = { ws, pid: p.profileId, peer: 0, voice, pos: false };
    socks.push(me);
    const late = setTimeout(() => bad(new Error('no welcome and view for ' + p.profileId + ' within 60 s')), 60000);
    ws.onopen = () => { ws.send(JSON.stringify(voice ? { t: 'join', profileId: p.profileId, name: p.name }
                                                     : { t: 'join', profileId: p.profileId, name: p.name, voice: false })); };
    ws.onmessage = (ev) => {
      const text = String(ev.data);
      meter.bytes += text.length; meter.msgs++;
      if (text.startsWith('{"t":"sdp"') || text.startsWith('{"t":"ice"')) meter.signals++;
      if (!me.peer && text.startsWith('{"t":"welcome"')) { me.peer = JSON.parse(text).peer; if (voice) voicePages.push(me); }
      if (!me.pos && text.startsWith('{"t":"pos"')) me.pos = true;
      if (me.peer && me.pos && late) { clearTimeout(late); ok(); }
    };
    // Refused at the handshake (error, never followed by close on Node 22,
    // #2818) or closed before its welcome and view: said now, not at 60 s.
    // Once welcomed and walking, the promise is settled and these change nothing.
    ws.onerror = () => { clearTimeout(late); bad(new Error('socket for ' + p.profileId + ' failed before its welcome and view')); };
    ws.onclose = (ev) => { clearTimeout(late); bad(new Error('socket for ' + p.profileId + ' closed with ' + ev.code + ' before its welcome and view')); };
  })))));
  const stormMs = Date.now() - stormFrom;
  await new Promise((r) => setTimeout(r, 1500));
  const storm = s.probes.slice(mark);

  // Every pair of voice pages trades what one WebRTC connection costs.
  const SDP = 'v=0\r\n' + 'a=x'.repeat(1000);
  const CAND = 'candidate:1 1 udp 2122260223 192.168.1.20 53413 typ host generation 0 ufrag abcd network-id 1';
  const sigFrom = Date.now();
  const sigMark = s.probes.length;
  voicePages.sort((a, b) => a.peer - b.peer);
  for (let i = 0; i < voicePages.length; i++) {
    const a = voicePages[i];
    for (let j = i + 1; j < voicePages.length; j++) {
      const b = voicePages[j];
      a.ws.send(JSON.stringify({ t: 'sdp', to: b.peer, sdp: { type: 'offer', sdp: SDP } }));
      b.ws.send(JSON.stringify({ t: 'sdp', to: a.peer, sdp: { type: 'answer', sdp: SDP } }));
      for (let k = 0; k < 6; k++) {
        a.ws.send(JSON.stringify({ t: 'ice', to: b.peer, candidate: { candidate: CAND, sdpMid: '0', sdpMLineIndex: 0 } }));
        b.ws.send(JSON.stringify({ t: 'ice', to: a.peer, candidate: { candidate: CAND, sdpMid: '0', sdpMLineIndex: 0 } }));
      }
    }
    if (i % 20 === 19) await new Promise((r) => setImmediate(r));
  }
  // Signalling is done when the last offer, answer and candidate has reached
  // the page it was sent to, not when this process has finished sending: the
  // service can still be working through them long after. A message that
  // never comes (a socket closed at the ceiling) is counted, not waited for.
  // Until #2390 this stopped three seconds after the last send, whatever had
  // arrived by then, so its number was mostly how long this process took.
  const sigSent = voicePages.length * (voicePages.length - 1) * 7;
  const sigBy = Date.now() + 300000;
  while (meter.signals < sigSent && Date.now() < sigBy) await new Promise((r) => setTimeout(r, 20));
  const sigMs = Date.now() - sigFrom;
  await new Promise((r) => setTimeout(r, 1000));
  const sig = s.probes.slice(sigMark);

  // The evening: walking, talking, for SECONDS.
  walking = true;
  const chatPages = socks.filter((x) => !x.voice);
  const talker = setInterval(() => {
    for (const c of chatPages) if (rand() < 1 / (TALK_S * 5)) c.ws.send(JSON.stringify({ t: 'chat', text: 'A line said at the fire, of the usual length.' }));
  }, TICK_MS);
  live.timers.push(talker);
  const evMark = s.probes.length;
  const b0 = meter.bytes, m0 = meter.msgs, t0 = Date.now();
  await new Promise((r) => setTimeout(r, SECONDS * 1000));
  const evening = s.probes.slice(evMark);
  const evBytes = (meter.bytes - b0) / ((Date.now() - t0) / 1000);
  const evMsgs = (meter.msgs - m0) / ((Date.now() - t0) / 1000);
  clearInterval(talker);
  clearInterval(feeder);
  walking = false;
  // An unread /health is said in the result, not printed as a row of blanks.
  let health = {};
  try {
    health = JSON.parse(await new Promise((ok, bad) => {
      http.get('http://127.0.0.1:' + s.port + '/health', (res) => {
        let b = ''; res.on('data', (d) => { b += d; }); res.on('end', () => ok(b));
      }).on('error', bad);
    }));
  } catch (e) { health = { unread: String(e && e.code || e && e.message || e) }; }

  const sockets = socks.length;
  await cleanUp();

  return {
    people: n, sockets: sockets, crowd: CROWD,
    storm: { ms: stormMs, cores: +most(storm, 'cores').toFixed(2), p99: +most(storm, 'p99').toFixed(1), max: +most(storm, 'max').toFixed(1) },
    signalling: { pairs: voicePages.length * (voicePages.length - 1) / 2, ms: sigMs, undelivered: sigSent - meter.signals, cores: +most(sig, 'cores').toFixed(2), p99: +most(sig, 'p99').toFixed(1), max: +most(sig, 'max').toFixed(1) },
    evening: { cores: +avg(evening, 'cores').toFixed(3), coresPeak: +most(evening, 'cores').toFixed(2), p99: +most(evening, 'p99').toFixed(1),
               max: +most(evening, 'max').toFixed(1), rssMB: Math.round(most(evening, 'rss') / 1048576),
               kbPerSecond: Math.round(evBytes / 1024), msgsPerSecond: Math.round(evMsgs) },
    health: health.unread ? { unread: health.unread }
      : { peers: health.peers, droppedPositions: health.droppedPositions, skippedRosters: health.skippedRosters,
          closedBacklogged: health.closedBacklogged },
    feed: feed,
    unreadableProbeLines: s.badProbes
  };
}

(async () => {
  console.log('node ' + process.version + ' on ' + os.cpus().length + ' logical processors, ' + os.cpus()[0].model.trim() +
              (CROWD ? ', everybody in one cell' : ', about twenty to a cell'));
  const site = await siteThatSaysYes();
  const out = [];
  for (const n of SIZES) {
    let r;
    try { r = await run(n, site); }
    catch (e) {
      // A size the service could not take is a result too, and the sizes after it are bigger.
      await cleanUp();
      console.log(JSON.stringify({ people: n, crowd: CROWD, didNotFinish: String(e && e.message || e) }));
      break;
    }
    out.push(r);
    console.log(JSON.stringify(r));
  }
  console.log('');
  console.log('people  sockets  storm ms  storm cores  storm p99 ms  signalling ms  sig p99 ms  evening cores  peak  p99 ms  max ms  rss MB  KB/s out');
  for (const r of out) {
    console.log([r.people, r.sockets, r.storm.ms, r.storm.cores, r.storm.p99, r.signalling.ms, r.signalling.p99,
                 r.evening.cores, r.evening.coresPeak, r.evening.p99, r.evening.max, r.evening.rssMB, r.evening.kbPerSecond]
                .map((v, i) => String(v).padStart(i ? [8, 9, 12, 13, 14, 11, 14, 5, 7, 7, 7, 9][i - 1] : 6)).join(' '));
  }
  agent.destroy();
})().catch(async (e) => { console.log('stopped: ' + (e && e.stack || e)); process.exitCode = 1; await cleanUp(); agent.destroy(); });
