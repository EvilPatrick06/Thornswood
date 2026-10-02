// test-voice-reconnect.js
//
// Issues #409 and #519: how the two pages that hold a socket to the voice
// service lose it and find it again.
//
// On 21 September the launcher's voice page opened its socket 592 times, every
// two seconds, and launcher.log has both halves of why. From 19:09 the Wi-Fi
// was down and the machine slept at 19:39: 425 tries that never opened. It
// woke at 20:06 holding a join token that had expired at 20:02; the service
// refused it and closed, the page never read the refusal, and it came back
// with the same token every two seconds, 134 times, until the launcher's own
// renewal got through at 20:11.
//
// And a socket that went half open during a sleep or a change of network
// looked, to both pages, exactly like a quiet room: the service's pings are
// answered by the browser without the page ever hearing of them.
//
// This runs the REAL scripts of launcher/voice-host.html and
// game/ui/thornswood-chat.js in a sandbox, with a fake socket and a clock this
// file moves by hand, and replays both halves of that evening. Read only.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const CR = String.fromCharCode(13);
function read(rel) { return fs.readFileSync(path.join(__dirname, rel), 'utf8').split(CR).join(''); }

/* A clock and timers that only move when advance() says so. */
function clock() {
  let now = 1000000;
  let next = 1;
  const timers = [];
  function add(fn, ms, every) {
    const t = { id: next++, fn: fn, at: now + Math.max(0, ms || 0), every: every ? Math.max(1, ms) : 0 };
    timers.push(t);
    return t.id;
  }
  function clear(id) {
    const i = timers.findIndex((t) => t.id === id);
    if (i !== -1) { timers.splice(i, 1); }
  }
  function advance(ms) {
    const end = now + ms;
    for (;;) {
      let due = null;
      for (const t of timers) { if (t.at <= end && (!due || t.at < due.at)) { due = t; } }
      if (!due) { break; }
      now = due.at;
      if (due.every) { due.at += due.every; } else { clear(due.id); }
      due.fn();
    }
    now = end;
  }
  return {
    now: function () { return now; },
    setTimeout: function (fn, ms) { return add(fn, ms, false); },
    setInterval: function (fn, ms) { return add(fn, ms, true); },
    clear: clear,
    advance: advance
  };
}

/*
  The socket. open() and refuse() and vanish() are the three things the voice
  service can do to it; sent is what the page wrote.
*/
function sockets() {
  const made = [];
  function FakeSocket(url) {
    this.url = url; this.readyState = 0; this.sent = []; this.closed = false;
    made.push(this);
  }
  FakeSocket.prototype.send = function (s) { this.sent.push(JSON.parse(s)); };
  FakeSocket.prototype.close = function () {
    if (this.closed) { return; }
    this.closed = true; this.readyState = 3;
    if (this.onclose) { this.onclose({}); }
  };
  FakeSocket.prototype.open = function () { this.readyState = 1; if (this.onopen) { this.onopen({}); } };
  FakeSocket.prototype.say = function (obj) { if (this.onmessage) { this.onmessage({ data: JSON.stringify(obj) }); } };
  /* The network is down: it never opens, it just closes. */
  FakeSocket.prototype.fail = function () { this.close(); };
  /* The service refuses the join, as it does an expired token, and closes. */
  FakeSocket.prototype.refuse = function (why) { this.open(); this.say({ t: 'denied', why: why }); this.close(); };
  /* Let in. */
  FakeSocket.prototype.admit = function (peer) { this.open(); this.say({ t: 'welcome', peer: peer, profileId: 7 }); };
  return { FakeSocket: FakeSocket, made: made };
}

// ------------------------------------------------- the launcher's voice page
function hostPage() {
  const html = read('../launcher/voice-host.html');
  const m = /<script>([\s\S]*)<\/script>/.exec(html);
  if (!m) { throw new Error('voice-host.html has no script'); }
  const c = clock();
  const s = sockets();
  const posted = [];
  let onMessage = null;
  function FakePc() { this.signalingState = 'stable'; }
  FakePc.prototype.addTrack = function () { };
  FakePc.prototype.addTransceiver = function () { };
  FakePc.prototype.close = function () { };
  function FakeAudio() { this.currentTime = 0; this.state = 'running'; this.destination = {}; }
  const sandbox = {
    window: {
      chrome: { webview: {
        addEventListener: function (kind, fn) { if (kind === 'message') { onMessage = fn; } },
        postMessage: function (raw) { posted.push(JSON.parse(raw)); }
      } },
      AudioContext: FakeAudio
    },
    document: { getElementById: function () { return { textContent: '' }; } },
    navigator: {},
    WebSocket: s.FakeSocket,
    RTCPeerConnection: FakePc,
    fetch: function () { return Promise.reject(new Error('no network here')); },
    setTimeout: c.setTimeout, clearTimeout: c.clear,
    setInterval: c.setInterval, clearInterval: c.clear,
    console: console, Promise: Promise, Map: Map, Math: Math, Number: Number, String: String,
    JSON: JSON, Date: { now: c.now }, Object: Object, Array: Array, isFinite: isFinite
  };
  vm.createContext(sandbox);
  vm.runInContext(m[1], sandbox);
  function tell(obj) { onMessage({ data: JSON.stringify(obj) }); }
  return { clock: c, made: s.made, posted: posted, tell: tell };
}

{
  const p = hostPage();
  p.tell({ t: 'config', host: 'h', port: '1', profileId: 7, name: '', token: 'old',
           base: 'https://example.invalid/voice', socket: 'wss://example.invalid/voice/' });
  yes('the page opens a socket once it is configured', p.made.length === 1);

  /*
    19:09 to 19:39: the network is down, so no try ever opens. Thirty minutes
    of it, which at two seconds was 425 tries in the log.
  */
  const start = p.clock.now();
  for (let i = 0; i < 30 * 60; i++) {
    const last = p.made[p.made.length - 1];
    if (!last.closed && last.readyState === 0) { last.fail(); }
    p.clock.advance(1000);
  }
  const offline = p.made.length - 1;
  console.log('      thirty minutes with no network: ' + offline + ' tries (the old page made about 900)');
  yes('thirty minutes offline is a few dozen tries, not hundreds', offline > 10 && offline <= 60);
  yes('and it keeps trying at least once a minute',
      (p.clock.now() - start) / Math.max(1, offline) <= 60000);

  /*
    20:06: back, with a token that expired while the machine slept. The
    service refuses it. The page must not come straight back with the same
    token: it tells the launcher, and waits.
  */
  // The next try after the network is back, whenever the backoff makes it.
  for (let i = 0; i < 120 && p.made[p.made.length - 1].closed; i++) { p.clock.advance(1000); }
  const refusedAt = p.made.length;
  const w = p.made[p.made.length - 1];
  w.refuse('an expired token');
  yes('a refusal is passed to the launcher, which fetches a fresh token',
      p.posted.some((m) => m.t === 'denied' && /expired/.test(m.text)));
  p.clock.advance(5000);
  yes('and the page does not come straight back with the token it was refused',
      p.made.length === refusedAt);

  // The launcher's fresh token arrives: the page tries at once with it.
  p.tell({ t: 'token', token: 'fresh' });
  p.clock.advance(10);
  yes('a fresh token after a refusal is tried at once', p.made.length === refusedAt + 1);
  const retried = p.made[p.made.length - 1];
  retried.admit(3);
  const join = retried.sent.filter((m) => m.t === 'join')[0];
  yes('with the fresh token', !!join && join.token === 'fresh');

  /*
    Five minutes of a refused token, the old page's 134 tries, with no fresh
    token ever coming: the backoff alone has to hold it down.
  */
  const q = hostPage();
  q.tell({ t: 'config', host: 'h', port: '1', profileId: 7, name: '', token: 'dead',
           base: 'https://example.invalid/voice', socket: 'wss://example.invalid/voice/' });
  for (let i = 0; i < 300; i++) {
    const last = q.made[q.made.length - 1];
    if (!last.closed) { last.refuse('an expired token'); }
    q.clock.advance(1000);
  }
  console.log('      five minutes of refusals and no fresh token: ' + q.made.length + ' tries (the old page made 134 in the same five minutes)');
  yes('five minutes of refusals is a handful of tries', q.made.length <= 12);

  // Once in, the next loss starts again from about two seconds.
  const r = hostPage();
  r.tell({ t: 'config', host: 'h', port: '1', profileId: 7, name: '', token: 't',
           base: 'https://example.invalid/voice', socket: 'wss://example.invalid/voice/' });
  for (let i = 0; i < 6; i++) { r.made[r.made.length - 1].fail(); r.clock.advance(70000); }
  r.made[r.made.length - 1].admit(4);
  const n = r.made.length;
  r.made[r.made.length - 1].close();
  r.clock.advance(2100);
  yes('once let in, a later loss is retried within two seconds again', r.made.length === n + 1);

  /*
    #519. Joined, and then nothing: the socket has gone half open. The page
    pings every twenty five seconds, and seventy seconds of silence is a lost
    server even though the socket never said it closed.
  */
  const h = hostPage();
  h.tell({ t: 'config', host: 'h', port: '1', profileId: 7, name: '', token: 't',
           base: 'https://example.invalid/voice', socket: 'wss://example.invalid/voice/' });
  const live = h.made[0];
  live.admit(5);
  h.clock.advance(26000);
  yes('a joined page pings the service', live.sent.some((m) => m.t === 'ping'));
  // Answered: kept, however long.
  for (let i = 0; i < 20; i++) { h.clock.advance(25000); live.say({ t: 'pong' }); }
  yes('a page whose pings are answered keeps its socket', h.made.length === 1 && !live.closed);
  // Then nothing comes back at all.
  h.clock.advance(75000);
  yes('seventy seconds with nothing from the service and the page looks for it again',
      live.closed && h.made.length >= 1 && (h.clock.advance(3000), h.made.length === 2));
}

// ------------------------------------------------ the game's chat overlay
function chatPage() {
  const src = read('../game/ui/thornswood-chat.js');
  const c = clock();
  const s = sockets();
  const lines = [];
  const win = {
    THORNSWOOD: { host: 'h', port: 1, profileId: 7, name: 'Tester', token: 't',
                  base: 'https://example.invalid/voice' },
    thornswoodChat: { add: function (parts) { lines.push(parts.map((p) => p.text).join('')); } },
    skyrimPlatform: { sendMessage: function () { } }
  };
  const sandbox = {
    window: win, WebSocket: s.FakeSocket,
    setTimeout: c.setTimeout, clearTimeout: c.clear,
    setInterval: c.setInterval, clearInterval: c.clear,
    console: console, Math: Math, Number: Number, String: String, JSON: JSON,
    Date: { now: c.now }, Object: Object, Array: Array, isFinite: isFinite, parseInt: parseInt
  };
  vm.createContext(sandbox);
  vm.runInContext(src, sandbox);
  return { clock: c, made: s.made, lines: lines, net: win.thornswoodNet };
}

{
  const p = chatPage();
  yes('the chat overlay opens its socket', p.made.length === 1);
  const ws = p.made[0];
  ws.admit(9);
  p.clock.advance(26000);
  yes('a joined chat overlay pings the service', ws.sent.some((m) => m.t === 'ping'));
  for (let i = 0; i < 10; i++) { p.clock.advance(25000); ws.say({ t: 'pong' }); }
  yes('and keeps its socket while the pings are answered', !ws.closed && p.made.length === 1);
  yes('a pong is not a chat line', !p.lines.some((l) => /pong/.test(l)));
  p.clock.advance(75000);
  yes('seventy seconds of silence is said as a lost server',
      ws.closed && p.lines.some((l) => /lost the server/.test(l)));
  p.clock.advance(3000);
  yes('and it tries again', p.made.length === 2);

  // A refused join opens and closes at once; that must not reset the backoff.
  const q = chatPage();
  for (let i = 0; i < 300; i++) {
    const last = q.made[q.made.length - 1];
    if (!last.closed) { last.refuse('an expired token'); }
    q.clock.advance(1000);
  }
  console.log('      chat overlay, five minutes of refusals: ' + q.made.length +
              ' tries (it reset its backoff on every open, so a refused join came back every second)');
  yes('the chat overlay does not retry a refused join every second', q.made.length <= 25);
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exitCode = fail ? 1 : 0;
