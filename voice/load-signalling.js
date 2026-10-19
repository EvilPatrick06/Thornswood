// load-signalling.js
//
// How fast the voice service relays the WebRTC signalling of a full room,
// measured on this machine with no people at all (#2390). Not a harness:
// nothing passes or fails, and the nightly does not run it.
//
//   node voice\load-signalling.js                 100, 200 and 400 people
//   node voice\load-signalling.js --people 200
//
// load-voice.js plays the same signalling, but through one WebSocket client
// per socket in its own one thread, and on 19 Oct that thread was what set
// its signalling time: its profile at 200 people spent 2.7 s writing its own
// 278,600 messages one at a time, while the service sat idle between them.
// Two hundred people are two hundred machines, so the service's own cost is
// what this measures instead. Each voice page is a plain socket, joined with
// a real join token, and every frame it will send is built before the clock
// starts: for every pair, an offer and an answer of about 3 KB and six
// candidates each way, as load-voice.js sends. Then every page writes all of
// its frames at once, and the clock stops when the last candidate has
// reached the page it was sent to. The readers only count frames.
//
// It prints, for each size, how long that took, how long the service's one
// thread was busy in it (event loop utilisation, from a probe loaded into
// the service), and anything that did not arrive or a socket the service
// closed at its queue ceiling. VOICE_SERVER points it at another copy of
// voice-server.js, to compare two.
//
// It holds every frame in memory first: about 800 MB at 400 people.
// Never point it at the VPS: it starts its own copy and talks to nothing else.
const fs = require('fs');
const os = require('os');
const net = require('net');
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i < 0 || process.argv[i + 1] === undefined ? dflt : process.argv[i + 1];
}
const SIZES = String(arg('people', '100,200,400')).split(',').map(Number).filter((n) => n > 0);
const SERVER = process.env.VOICE_SERVER || path.join(__dirname, 'voice-server.js');

// The service's one thread: how long it has been busy, ten times a second.
const PROBE = `
const { performance } = require('perf_hooks');
setInterval(() => { process.stdout.write('BUSY ' + performance.eventLoopUtilization().active + '\\n'); }, 100).unref();
`;

function freePort() {
  return new Promise((ok, bad) => {
    const s = net.createServer();
    s.on('error', bad);
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); });
  });
}

function post(port, p, body) {
  return new Promise((ok, bad) => {
    const req = http.request({ host: '127.0.0.1', port, path: p, method: 'POST',
      headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) } }, (res) => {
      let b = ''; res.on('data', (d) => { b += d; }); res.on('end', () => ok({ status: res.statusCode, body: b }));
    });
    req.on('error', bad);
    req.end(body);
  });
}

function getJson(port, p) {
  return new Promise((ok, bad) => {
    http.get({ host: '127.0.0.1', port, path: p }, (res) => {
      let b = ''; res.on('data', (d) => { b += d; }); res.on('end', () => { try { ok(JSON.parse(b)); } catch (e) { bad(e); } });
    }).on('error', bad);
  });
}

/* A client frame: text, masked, as a browser sends it. */
function frameOf(obj) {
  const data = Buffer.from(JSON.stringify(obj), 'utf8');
  const len = data.length;
  let head;
  if (len < 126) head = Buffer.from([0x81, 0x80 | len]);
  else { head = Buffer.alloc(4); head[0] = 0x81; head[1] = 0x80 | 126; head.writeUInt16BE(len, 2); }
  const key = crypto.randomBytes(4);
  for (let i = 0; i < len; i++) data[i] ^= key[i & 3];
  return Buffer.concat([head, key, data]);
}

async function service(site) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-signalling-'));
  fs.copyFileSync(SERVER, path.join(dir, 'voice-server.js'));
  fs.copyFileSync(path.join(__dirname, 'headlines.js'), path.join(dir, 'headlines.js'));
  fs.writeFileSync(path.join(dir, 'probe.js'), PROBE);
  const port = await freePort();
  const env = Object.assign({}, process.env, {
    THORNSWOOD_VOICE_PORT: String(port), THORNSWOOD_VOICE_BIND: '127.0.0.1', THORNSWOOD_SITE: site,
    THORNSWOOD_CHAT_DIR: path.join(dir, 'chat')
  });
  delete env.THORNSWOOD_VOICE_MOST;
  const proc = spawn(process.execPath, ['-r', './probe.js', 'voice-server.js'], { cwd: dir, env: env });
  const s = { dir, port, proc, log: '', busy: 0 };
  let line = '';
  proc.stdout.on('data', (d) => {
    line += d;
    let i;
    while ((i = line.indexOf('\n')) >= 0) {
      const l = line.slice(0, i); line = line.slice(i + 1);
      if (l.startsWith('BUSY ')) s.busy = Number(l.slice(5)); else s.log += l + '\n';
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

/* A voice page: a plain socket, upgraded with a join token, joined. */
function page(s, pid, counter) {
  return post(s.port, '/token', JSON.stringify({ profileId: pid, ticket: 'load' })).then((r) => new Promise((ok, bad) => {
    if (r.status !== 200) { bad(new Error('no token for ' + pid + ': ' + r.status + ' ' + r.body)); return; }
    const token = JSON.parse(r.body).token;
    const me = { pid, peer: 0, sock: null };
    const sock = net.connect(s.port, '127.0.0.1', () => {
      sock.write('GET / HTTP/1.1\r\nHost: 127.0.0.1:' + s.port + '\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
                 'Sec-WebSocket-Key: ' + crypto.randomBytes(16).toString('base64') + '\r\n' +
                 'Sec-WebSocket-Protocol: thornswood, ' + token + '\r\nSec-WebSocket-Version: 13\r\n\r\n');
    });
    me.sock = sock;
    sock.on('error', () => { });
    const late = setTimeout(() => bad(new Error('no welcome for ' + pid + ' within 60 s')), 60000);
    let buf = Buffer.alloc(0), upgraded = false;
    sock.on('data', (d) => {
      buf = buf.length ? Buffer.concat([buf, d]) : d;
      if (!upgraded) {
        const at = buf.indexOf('\r\n\r\n');
        if (at < 0) return;
        upgraded = true;
        buf = buf.subarray(at + 4);
        sock.write(frameOf({ t: 'join', profileId: pid, name: 'Person ' + pid }));
      }
      let off = 0;
      for (;;) {
        if (buf.length - off < 2) break;
        let len = buf[off + 1] & 0x7f, h = 2;
        if (len === 126) { if (buf.length - off < 4) break; len = buf.readUInt16BE(off + 2); h = 4; }
        else if (len === 127) { if (buf.length - off < 10) break; len = Number(buf.readBigUInt64BE(off + 2)); h = 10; }
        if (buf.length - off < h + len) break;
        const b = off + h;
        // {"t":"sdp" and {"t":"ice" are what is counted; the welcome gives the peer id.
        const kind = buf.toString('latin1', b + 6, b + 9);
        if (kind === 'sdp' || kind === 'ice') counter.got++;
        else if (!me.peer && kind === 'wel') {
          me.peer = JSON.parse(buf.toString('utf8', b, b + len)).peer;
          clearTimeout(late);
          ok(me);
        }
        off = b + len;
      }
      buf = buf.subarray(off);
    });
  }));
}

async function run(n, site) {
  const s = await service(site);
  const counter = { got: 0 };
  const pages = [];
  try {
    for (let i = 0; i < n; i += 50) {
      pages.push(...await Promise.all(Array.from({ length: Math.min(50, n - i) }, (_, k) => page(s, 30000 + i + k, counter))));
    }
    // The rosters of the joins, sent and read before the clock starts.
    await new Promise((r) => setTimeout(r, 1000));

    const SDP = 'v=0\r\n' + 'a=x'.repeat(1000);
    const CAND = 'candidate:1 1 udp 2122260223 192.168.1.20 53413 typ host generation 0 ufrag abcd network-id 1';
    // Each page's frames, joined as they are made, so only one page's loose
    // frames are held at a time: the lower of a pair offers, the higher answers.
    const whole = pages.map((me, i) => {
      const mine = [];
      for (let j = 0; j < n; j++) {
        if (j === i) continue;
        const to = pages[j].peer;
        mine.push(frameOf({ t: 'sdp', to: to, sdp: { type: i < j ? 'offer' : 'answer', sdp: SDP } }));
        for (let k = 0; k < 6; k++) mine.push(frameOf({ t: 'ice', to: to, candidate: { candidate: CAND, sdpMid: '0', sdpMLineIndex: 0 } }));
      }
      return Buffer.concat(mine);
    });
    const sent = n * (n - 1) * 7;

    const busy0 = s.busy;
    const from = Date.now();
    pages.forEach((p, i) => p.sock.write(whole[i]));
    // A message that never comes (a socket closed at the ceiling) is counted,
    // not waited for.
    const by = from + 300000;
    while (counter.got < sent && Date.now() < by) await new Promise((r) => setTimeout(r, 5));
    const ms = Date.now() - from;
    // The probe's next line, so the busy time covers the last of it.
    await new Promise((r) => setTimeout(r, 250));
    const busyMs = s.busy - busy0;
    const health = await getJson(s.port, '/health');
    return { people: n, pairs: n * (n - 1) / 2, messages: sent, ms: ms, serviceBusyMs: Math.round(busyMs),
             undelivered: sent - counter.got, closedBacklogged: health.closedBacklogged };
  } finally {
    for (const p of pages) p.sock.destroy();
    await new Promise((r) => { s.proc.once('exit', r); try { s.proc.kill(); } catch (e) { r(); } });
    try { fs.rmSync(s.dir, { recursive: true, force: true }); }
    catch (e) { console.log('could not remove ' + s.dir + ' (' + (e.code || e.message) + '): delete it by hand'); }
  }
}

(async () => {
  console.log('node ' + process.version + ' on ' + os.cpus().length + ' logical processors, ' + os.cpus()[0].model.trim() +
              ', ' + path.relative(process.cwd(), SERVER));
  const site = http.createServer((req, res) => {
    req.resume();
    req.on('end', () => { res.writeHead(200, { 'content-type': 'application/json' }).end('{"ok":true}'); });
  });
  await new Promise((r) => site.listen(0, '127.0.0.1', r));
  site.unref();
  const out = [];
  for (const n of SIZES) {
    const r = await run(n, 'http://127.0.0.1:' + site.address().port);
    out.push(r);
    console.log(JSON.stringify(r));
  }
  console.log('');
  console.log('people    pairs  messages  signalling ms  service busy ms  undelivered  closed');
  for (const r of out) {
    console.log([r.people, r.pairs, r.messages, r.ms, r.serviceBusyMs, r.undelivered, r.closedBacklogged]
                .map((v, i) => String(v).padStart([6, 8, 9, 14, 16, 12, 7][i])).join(' '));
  }
})().catch((e) => { console.log('stopped: ' + (e && e.stack || e)); process.exitCode = 1; });
