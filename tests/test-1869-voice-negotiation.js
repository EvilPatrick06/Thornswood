/*
  test-1869-voice-negotiation.js

      node tests\test-1869-voice-negotiation.js

  #1869. voice/test-one-way.js drove the negotiation of the service's own
  browser page, which went in #1822, and nothing drove the two clients that
  are left: the launcher's voice page (launcher\voice-host.html) and the
  game's voice overlay (game\ui\thornswood-voice.js, riding the chat's socket
  in game\ui\thornswood-chat.js). Both begin onSdp and onIce with
  `if (!rec) return;`, so an offer or a candidate from somebody they have not
  opened is dropped. This measures whether that can happen, and runs both
  clients' own code, unchanged, against the real service. It cannot happen
  to a page that reads its own socket (1, 2): the service writes the roster
  that names somebody first, and the launcher's page opens everybody on a
  roster before it reads the next message. It did happen to the overlay,
  which shares the chat's socket and can start listening after the room
  has already offered to it (3).

  1. The service, over raw sockets. A socket that has stopped reading is
     backed up with a heavy position feed, two people join (so its roster is
     held, newest only), and the second sends it an offer and a candidate.
     When it reads again, the roster naming the sender comes before both,
     and the older roster never comes at all. So no socket is sent anything
     from somebody before the roster that names them.

  2. Two launcher pages. They join, negotiate, and then both microphones
     open in the same moment and each offers before it reads the other's
     (glare). The lower peer id is impolite and ignores the offer that
     crossed its own; the higher is polite, rolls back and answers. Both
     hear each other.

  3. The order that dropped. The game's chat socket joins the room as soon
     as it has a token, at the character choice for somebody waiting in
     line (#481, #1142), and the overlay only gets on it when the voice
     plugin configures it, so it can get on late. A launcher page already
     in the room and one that joins after the chat both send that socket
     their offers before the overlay is listening. On main that roster and
     those offers went to nobody: the overlay opened nobody until the next
     join, and then its offer to the launcher that was there first met a
     peer still waiting on the answer to its own, which the impolite side
     ignores, so that pair never connected. Now the chat keeps them and
     hands them over when the overlay gets on, every pair connects, and
     when every microphone opens at once every pair's offers cross and
     settle, the overlay polite in one pair and impolite in the others.

  4. The overlay on before its socket has joined, then the socket joins
     again under a new name (setName), which is a new peer id: everybody
     drops the old one and connects to the new.

  5. What the chat keeps for voice, on its own: the newest roster first,
     then signalling in order, nothing from somebody who left, at most a
     hundred from one peer, nothing once voice is on, nothing across a new
     connection.

  6. The rules in the pages' source the rest relies on.

  The pages run in node's vm with their own sources. The network is a real
  WebSocket to the real voice-server.js; the browser is stood in for by a
  fake RTCPeerConnection (signalling states, implicit rollback, an answer
  that must answer the current offer, candidates refused before a remote
  description or for another session, negotiationneeded only when stable),
  a fake AudioContext that records which streams were played, and a
  microphone each test opens when it chooses. A pair counts as connected
  when both connections are stable, each holds the other's current
  description, and at least one of them has taken the other's candidates,
  which is all ICE needs. One person hears another when that is so, the
  other's side of the last negotiation sends audio, and the page fed that
  stream to its audio.

  VOICE_SERVER, VOICE_HOST, VOICE_OVERLAY and VOICE_CHAT point it at other
  copies, which is how it is shown to fail on the code before #1869.
  Writes only to a temp folder, on loopback ports the system hands out.
*/
'use strict';
const fs = require('fs');
const os = require('os');
const net = require('net');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');
const { spawn } = require('child_process');

const REPO = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
const SERVER = process.env.VOICE_SERVER || path.join(REPO, 'voice', 'voice-server.js');
const HOST_PAGE = process.env.VOICE_HOST || path.join(REPO, 'launcher', 'voice-host.html');
const OVERLAY = process.env.VOICE_OVERLAY || path.join(REPO, 'game', 'ui', 'thornswood-voice.js');
const CHAT = process.env.VOICE_CHAT || path.join(REPO, 'game', 'ui', 'thornswood-chat.js');
const read = (f) => fs.readFileSync(f, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
const sleep = (ms) => new Promise((ok) => setTimeout(ok, ms));
async function until(cond, ms) {
  const from = Date.now();
  while (Date.now() - from < (ms || 5000)) {
    if (cond()) return true;
    await sleep(20);
  }
  return !!cond();
}

// ------------------------------------------------------------ the service --
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1869-'));
fs.copyFileSync(SERVER, path.join(dir, 'voice-server.js'));
fs.copyFileSync(path.join(path.dirname(SERVER), 'headlines.js'), path.join(dir, 'headlines.js'));
const KEY = crypto.randomBytes(32).toString('hex');
fs.writeFileSync(path.join(dir, 'token-key.txt'), KEY);
function tokenFor(pid) {
  const b64 = (buf) => buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const body = 'v2.' + pid + '.' + Date.now() + '.' + b64(crypto.randomBytes(16));
  return body + '.' + b64(crypto.createHmac('sha256', KEY).update(body).digest());
}

/* A port of this run's own (#1703), and nothing asked of it until the
   service has said it is listening there. */
function freePort(host) {
  return new Promise((ok, bad) => {
    const s = net.createServer();
    s.on('error', bad);
    s.listen(0, host, () => { const p = s.address().port; s.close(() => ok(p)); });
  });
}
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
let PORT = 0, BASE = '', srv = null, srvLog = '';
async function start() {
  PORT = await freePort('127.0.0.1');
  BASE = 'http://127.0.0.1:' + PORT;
  srv = spawn(process.execPath, ['voice-server.js'], {
    cwd: dir,
    env: Object.assign({}, process.env, {
      THORNSWOOD_VOICE_PORT: String(PORT), THORNSWOOD_VOICE_BIND: '127.0.0.1',
      THORNSWOOD_SITE: '', THORNSWOOD_CHAT_DIR: path.join(dir, 'chat'), THORNSWOOD_CHAT_RANGE: '',
    }),
  });
  srv.stdout.on('data', (d) => { srvLog += d; });
  srv.stderr.on('data', (d) => { srvLog += d; });
  await listening(srv, PORT);
}
async function health() { return (await fetch(BASE + '/health')).json(); }

// ------------------------------------------------- raw sockets, for part 1 --
const raw = [];
/* The handshake by hand, so a socket can be left paused, which is a
   machine that has stopped reading. */
function openRaw(pid) {
  return new Promise((resolve, reject) => {
    const key = crypto.randomBytes(16).toString('base64');
    const s = net.connect(PORT, '127.0.0.1', () => {
      s.write('GET / HTTP/1.1\r\nHost: 127.0.0.1:' + PORT + '\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
              'Sec-WebSocket-Key: ' + key + '\r\nSec-WebSocket-Protocol: thornswood, ' + tokenFor(pid) + '\r\n' +
              'Sec-WebSocket-Version: 13\r\n\r\n');
    });
    raw.push(s);
    let head = Buffer.alloc(0);
    const onData = (d) => {
      head = Buffer.concat([head, d]);
      const at = head.indexOf('\r\n\r\n');
      if (at < 0) { return; }
      s.removeListener('data', onData);
      s.pause();
      s.rest = head.slice(at + 4);
      resolve(s);
    };
    s.on('data', onData);
    s.on('error', () => { });
    setTimeout(() => reject(new Error('no handshake in four seconds')), 4000);
  });
}
/* A masked text frame, the way a browser sends one. */
function sendRaw(s, obj) {
  const data = Buffer.from(JSON.stringify(obj), 'utf8');
  const len = data.length;
  let head;
  if (len < 126) { head = Buffer.from([0x81, 0x80 | len]); }
  else { head = Buffer.alloc(4); head[0] = 0x81; head[1] = 0x80 | 126; head.writeUInt16BE(len, 2); }
  const mask = crypto.randomBytes(4);
  const body = Buffer.alloc(len);
  for (let i = 0; i < len; i++) body[i] = data[i] ^ mask[i & 3];
  s.write(Buffer.concat([head, mask, body]));
}
/* Every JSON frame the service sends, in the order it sent them. */
function readRaw(s, onMsg) {
  let buf = s.rest || Buffer.alloc(0);
  const drain = () => {
    for (;;) {
      if (buf.length < 2) return;
      const op = buf[0] & 0x0f;
      let len = buf[1] & 0x7f;
      let off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      if (buf.length < off + len) return;
      const body = buf.slice(off, off + len);
      buf = buf.slice(off + len);
      if (op !== 1) continue;
      let m = null;
      try { m = JSON.parse(body.toString('utf8')); } catch (e) { }
      if (m) onMsg(m);
    }
  };
  s.on('data', (d) => { buf = Buffer.concat([buf, d]); drain(); });
  drain();
  s.resume();
}

// ------------------------------------------------ the browser, stood in for --
function failure(name, message) { const e = new Error(message || name); e.name = name; return e; }
const descOf = (d) => { try { return d ? JSON.parse(d.sdp) : null; } catch (e) { return null; } };
let UID = 0;

/*
  RTCPeerConnection, as far as these pages lean on it. A description's sdp
  is JSON naming the connection that made it, its version, whether that
  side sends audio, its ICE session and, for an answer, which offer it
  answers. Every method goes on one chain, as the browser's operations
  chain does, and negotiationneeded fires only while stable with nothing on
  the chain, once for each change that needs it.
*/
function rtcFor(page) {
  function PC(cfg) {
    this.uid = ++UID;
    this.page = page;
    page.pcs.push(this);
    this.iceServers = cfg && cfg.iceServers;
    this.signalingState = 'stable';
    this.iceConnectionState = 'new';
    this.localDescription = null;
    this.remoteDescription = null;
    this.currentLocalDescription = null;
    this.currentRemoteDescription = null;
    this.onicecandidate = this.onnegotiationneeded = this.ontrack = this.oniceconnectionstatechange = null;
    this.senders = 0;
    this.media = 0;
    this.ver = 0;
    this.ufrag = 'u' + this.uid;
    this.gathered = false;
    this.negotiated = false;
    this.sending = false;
    this.fired = false;
    this.busy = 0;
    this.chain = Promise.resolve();
    this.closed = false;
    this.rollbacks = 0;
    this.offersTaken = [];
    this.applied = {};
    this.iceRefused = 0;
    this.hearing = {};
  }
  PC.prototype.op = function (fn) {
    const self = this;
    self.busy++;
    const p = self.chain.then(fn);
    self.chain = p.catch(() => { }).then(() => {
      self.busy--;
      if (!self.busy) setTimeout(() => self.check(), 0);
    });
    return p;
  };
  PC.prototype.needed = function () {
    return this.media > 0 && (!this.negotiated || (this.senders > 0) !== this.sending);
  };
  PC.prototype.check = function () {
    if (this.closed || this.busy || this.signalingState !== 'stable' || this.fired || !this.needed()) return;
    this.fired = true;
    if (this.onnegotiationneeded) this.onnegotiationneeded({});
  };
  PC.prototype.changed = function () { this.fired = false; setTimeout(() => this.check(), 0); };
  PC.prototype.addTrack = function () { this.senders++; this.media++; this.changed(); return {}; };
  PC.prototype.addTransceiver = function () { this.media++; this.changed(); return {}; };
  PC.prototype.gather = function () {
    const self = this, u = self.ufrag;
    [1, 2].forEach((n) => setTimeout(() => {
      if (self.closed || !self.onicecandidate) return;
      self.onicecandidate({ candidate: { candidate: 'candidate:' + n + ' 1 udp 2122260223 192.0.2.' + (self.uid % 250) +
                                                    ' ' + (50000 + n) + ' typ host', sdpMid: '0', sdpMLineIndex: 0,
                                         usernameFragment: u } });
    }, n));
    setTimeout(() => { if (!self.closed && self.onicecandidate) self.onicecandidate({ candidate: null }); }, 4);
  };
  PC.prototype.hear = function (body) {
    if (!body.send || this.hearing[body.pc]) return;
    this.hearing[body.pc] = true;
    const track = { kind: 'audio', enabled: true, from: body.pc };
    const stream = { id: 'from-' + body.pc, from: body.pc, getAudioTracks: () => [track], getTracks: () => [track] };
    if (this.ontrack) this.ontrack({ track: track, streams: [stream] });
  };
  PC.prototype.stableNow = function () {
    this.signalingState = 'stable';
    this.currentLocalDescription = this.localDescription;
    this.currentRemoteDescription = this.remoteDescription;
    this.negotiated = true;
    this.sending = !!descOf(this.localDescription).send;
    this.fired = false;
  };
  PC.prototype.setLocalDescription = function (d) {
    const self = this;
    return self.op(() => {
      if (self.closed) throw failure('InvalidStateError', 'closed');
      const st = self.signalingState;
      const type = (d && d.type) || (st === 'have-remote-offer' ? 'answer' : 'offer');
      if (type === 'offer' && st !== 'stable' && st !== 'have-local-offer') throw failure('InvalidStateError', 'an offer in ' + st);
      if (type === 'answer' && st !== 'have-remote-offer') throw failure('InvalidStateError', 'an answer in ' + st);
      const body = { pc: self.uid, v: ++self.ver, send: self.senders > 0, ufrag: self.ufrag };
      if (type === 'answer') body.answers = descOf(self.remoteDescription).v;
      self.localDescription = { type: type, sdp: JSON.stringify(body) };
      if (type === 'offer') { self.signalingState = 'have-local-offer'; self.fired = false; }
      else { self.stableNow(); }
      if (!self.gathered) { self.gathered = true; self.gather(); }
    });
  };
  PC.prototype.setRemoteDescription = function (d) {
    const self = this;
    return self.op(() => {
      if (self.closed) throw failure('InvalidStateError', 'closed');
      const body = descOf(d);
      if (!body || typeof body.pc !== 'number') throw failure('OperationError', 'not a description');
      const st = self.signalingState;
      if (d.type === 'offer') {
        if (st === 'have-local-offer') {
          // The implicit rollback: the polite side's own offer is withdrawn.
          self.rollbacks++;
          self.localDescription = self.currentLocalDescription;
        } else if (st !== 'stable' && st !== 'have-remote-offer') {
          throw failure('InvalidStateError', 'an offer in ' + st);
        }
        self.remoteDescription = { type: 'offer', sdp: d.sdp };
        self.signalingState = 'have-remote-offer';
        self.offersTaken.push(body.pc + '/' + body.v);
        self.hear(body);
        return;
      }
      if (d.type === 'answer') {
        if (st !== 'have-local-offer') throw failure('InvalidStateError', 'an answer in ' + st);
        if (body.answers !== descOf(self.localDescription).v) throw failure('InvalidAccessError', 'an answer to an offer this connection no longer has');
        self.remoteDescription = { type: 'answer', sdp: d.sdp };
        self.stableNow();
        self.hear(body);
        return;
      }
      throw failure('TypeError', 'no type');
    });
  };
  PC.prototype.addIceCandidate = function (c) {
    const self = this;
    return self.op(() => {
      if (self.closed) throw failure('InvalidStateError', 'closed');
      if (!self.remoteDescription) { self.iceRefused++; throw failure('InvalidStateError', 'no remote description yet'); }
      const r = descOf(self.remoteDescription);
      if (!c || c.usernameFragment !== r.ufrag) { self.iceRefused++; throw failure('OperationError', 'a candidate for another session'); }
      self.applied[r.pc] = (self.applied[r.pc] || 0) + 1;
    });
  };
  PC.prototype.restartIce = function () { this.ufrag = 'u' + this.uid + 'r' + (++this.ver); this.gathered = false; this.changed(); };
  PC.prototype.getReceivers = function () {
    return Object.keys(this.hearing).map(() => ({ track: { kind: 'audio', enabled: true } }));
  };
  PC.prototype.close = function () { this.closed = true; this.signalingState = 'closed'; };
  return PC;
}

function param(v) { return { value: v, setTargetAtTime: function (x) { this.value = x; } }; }
function audioNode() {
  return { connect: (to) => to, disconnect: () => { }, gain: param(1), positionX: param(0), positionY: param(0),
           positionZ: param(0), setPosition: () => { }, panningModel: '', distanceModel: '', refDistance: 1,
           rolloffFactor: 1, maxDistance: 10000 };
}
/* An AudioContext that remembers which streams it was handed to play. */
function audioFor(page) {
  return function AudioContext() {
    this.state = 'running';
    this.currentTime = 0;
    this.destination = audioNode();
    this.listener = { forwardX: param(0), forwardY: param(0), forwardZ: param(-1), upX: param(0), upY: param(1),
                      upZ: param(0), setOrientation: () => { }, setPosition: () => { } };
    this.createGain = audioNode;
    this.createPanner = audioNode;
    this.createMediaStreamSource = (stream) => { page.played.push(stream); return audioNode(); };
    this.resume = () => Promise.resolve();
  };
}
function FakeAudio() { this.muted = false; this.srcObject = null; }
FakeAudio.prototype.play = function () { return Promise.resolve(); };
FakeAudio.prototype.pause = function () { };

/* A microphone that opens when the test says so: page.mic(). */
function mediaFor(page) {
  let open = null;
  const gate = new Promise((ok) => { open = ok; });
  page.mic = () => open();
  const track = { kind: 'audio', enabled: true, label: 'Microphone (test)', stop: () => { } };
  const stream = { id: 'mic-' + page.name, getAudioTracks: () => [track], getTracks: () => [track] };
  return {
    getUserMedia: () => gate.then(() => stream),
    enumerateDevices: () => Promise.resolve([{ kind: 'audioinput', deviceId: 'default', label: track.label }]),
  };
}
function element() {
  return { style: {}, className: '', innerHTML: '', textContent: '', id: '', setAttribute: () => { }, appendChild: () => { } };
}
/* Timers the page sets, cleared when its test is done. */
function timersFor(page) {
  return {
    setTimeout: (f, ms) => { const h = setTimeout(f, ms); page.timers.push(h); return h; },
    clearTimeout: (h) => clearTimeout(h),
    setInterval: (f, ms) => { const h = setInterval(f, ms); page.timers.push(h); return h; },
    clearInterval: (h) => clearInterval(h),
  };
}
/*
  The network. The pages ask for wss://thornswood.test/voice/, which Caddy
  carries to the service; here a real WebSocket goes straight to it on
  loopback. Everything the service sends is kept on page.wire as well.
  page.hold() keeps what arrives until page.release(), so a test can have
  two pages make their offers before either reads the other's: the glare
  a slow link makes, every time rather than when the timing falls that way.
*/
function socketFor(page) {
  return function WebSocketToService(url, protocols) {
    page.urls.push(url);
    const real = new WebSocket('ws://127.0.0.1:' + PORT + '/', protocols);
    page.sockets.push(real);
    const self = this;
    self.onopen = self.onmessage = self.onclose = self.onerror = null;
    Object.defineProperty(self, 'readyState', { get: () => real.readyState });
    real.onopen = () => { if (self.onopen) self.onopen({}); };
    const deliver = (data) => {
      let m = null;
      try { m = JSON.parse(data); } catch (e) { }
      if (m) page.wire.push(m);
      if (self.onmessage) self.onmessage({ data: data });
    };
    real.onmessage = (ev) => {
      if (page.held) { page.held.push(() => deliver(ev.data)); return; }
      deliver(ev.data);
    };
    real.onclose = () => { if (self.onclose) self.onclose({}); };
    real.onerror = () => { if (self.onerror) self.onerror({}); };
    self.send = (d) => real.send(d);
    self.close = () => { try { real.close(); } catch (e) { } };
  };
}
function newPage(name, pid, kind) {
  const page = { name: name, pid: pid, kind: kind, pcs: [], played: [], said: [], wire: [], urls: [], timers: [],
                 sockets: [], held: null };
  page.hold = () => { page.held = page.held || []; };
  page.release = () => { const q = page.held || []; page.held = null; q.forEach((f) => f()); };
  return page;
}
const pages = [];
function closePage(page) {
  for (const h of page.timers) { clearTimeout(h); clearInterval(h); }
  for (const s of page.sockets) { try { s.onclose = null; s.close(); } catch (e) { } }
  for (const pc of page.pcs) pc.close();
}

const HOST_SRC = (function () {
  const html = read(HOST_PAGE);
  const a = html.indexOf('<script>');
  const b = html.lastIndexOf('</script>');
  return a >= 0 && b > a ? html.slice(a + 8, b) : '';
})();
const CHAT_SRC = read(CHAT);
const OVERLAY_SRC = read(OVERLAY);

/* The launcher's voice page, as WebView2 runs it, with the launcher's config. */
function launcherPage(name, pid) {
  const page = newPage(name, pid, 'launcher');
  const heard = [];
  const box = Object.assign({
    document: { getElementById: () => element() },
    navigator: { mediaDevices: mediaFor(page) },
    AudioContext: audioFor(page),
    RTCPeerConnection: rtcFor(page),
    Audio: FakeAudio,
    WebSocket: socketFor(page),
    console: { log: (l) => page.said.push('console: ' + l) },
  }, timersFor(page));
  box.window = box;
  box.chrome = { webview: {
    addEventListener: (kind, fn) => heard.push(fn),
    postMessage: (s) => { let m = {}; try { m = JSON.parse(s); } catch (e) { } page.said.push(m.t + ': ' + m.text); },
  } };
  vm.createContext(box);
  vm.runInContext(HOST_SRC, box, { filename: 'voice-host.html' });
  page.box = box;
  page.peer = () => Number(box.myPeer) || 0;
  page.start = () => heard.forEach((fn) => fn({ data: JSON.stringify({
    t: 'config', host: 'thornswood.test', port: 443, profileId: pid, name: name, token: tokenFor(pid),
    base: 'https://thornswood.test/voice', socket: 'wss://thornswood.test/voice/' }) }));
  pages.push(page);
  return page;
}

/*
  The game's page: the chat file, which holds the socket and joins as soon
  as it has a token, and the voice overlay, which gets on it when the voice
  plugin configures it (page.configure).
*/
function gamePage(name, pid, withToken) {
  const page = newPage(name, pid, 'game');
  const doc = { createElement: () => element(), body: element(), head: element() };
  const box = Object.assign({
    THORNSWOOD: { host: 'thornswood.test', port: 443, profileId: pid, name: name, token: withToken ? tokenFor(pid) : '',
                  base: 'https://thornswood.test/voice' },
    skyrimPlatform: { sendMessage: (to, line) => page.said.push(to + ': ' + line) },
    document: doc,
    navigator: { mediaDevices: mediaFor(page) },
    location: { href: 'file:///Data/Platform/UI/index.html' },
    isSecureContext: true,
    AudioContext: audioFor(page),
    RTCPeerConnection: rtcFor(page),
    Audio: FakeAudio,
    WebSocket: socketFor(page),
    fetch: () => Promise.reject(new Error('no launcher here')),
    console: { log: (l) => page.said.push('console: ' + l) },
  }, timersFor(page));
  box.window = box;
  vm.createContext(box);
  vm.runInContext(CHAT_SRC, box, { filename: 'thornswood-chat.js' });
  vm.runInContext(OVERLAY_SRC, box, { filename: 'thornswood-voice.js' });
  page.box = box;
  page.peer = () => Number(box.thornswoodNet.peer()) || 0;
  page.configure = (mic) => box.thornswoodVoice.configure({ host: 'thornswood.test', port: 443, profileId: pid, name: name,
                                                             pushToTalk: true, microphone: !!mic, micName: '' });
  pages.push(page);
  return page;
}

// ---------------------------------------------------------------- reading --
/* The two connections that make a pair between P and Q, when they agree. */
function link(P, Q) {
  for (const a of P.pcs) {
    for (const b of Q.pcs) {
      if (a.closed || b.closed || a.signalingState !== 'stable' || b.signalingState !== 'stable') continue;
      const al = descOf(a.currentLocalDescription), ar = descOf(a.currentRemoteDescription);
      const bl = descOf(b.currentLocalDescription), br = descOf(b.currentRemoteDescription);
      if (!al || !ar || !bl || !br) continue;
      if (ar.pc !== b.uid || br.pc !== a.uid || ar.v !== bl.v || br.v !== al.v) continue;
      // One side holding the other's candidates is enough for ICE: its
      // checks reach the other, which learns where they came from.
      if (!a.applied[b.uid] && !b.applied[a.uid]) continue;
      return { a: a, b: b, al: al, bl: bl };
    }
  }
  return null;
}
/* Each side of the pair took candidates the other sent. */
function bothTook(P, Q) {
  const l = link(P, Q);
  return !!l && !!l.a.applied[l.b.uid] && !!l.b.applied[l.a.uid];
}
/* P hears Q. */
function hears(P, Q) {
  const l = link(P, Q);
  return !!l && !!l.bl.send && P.played.some((s) => s.from === l.b.uid);
}
/* The page's own lines that say a negotiation went wrong. */
function troubles(page) {
  return page.said.filter((l) => /offer failed|sdp failed|could not offer|listener threw|threw/i.test(l));
}
/* The offers page P was sent that connection pc made, as connection/version. */
function offersBy(P, pc) {
  return P.wire.filter((m) => m.t === 'sdp' && m.sdp && m.sdp.type === 'offer' && (descOf(m.sdp) || {}).pc === pc.uid)
               .map((m) => { const d = descOf(m.sdp); return d.pc + '/' + d.v; });
}
/*
  The roles in one pair. The lower peer id is impolite: it never rolls back,
  and an offer that crosses its own is ignored. The higher is polite.
*/
function roles(P, Q) {
  const l = link(P, Q);
  if (!l) return null;
  const pFirst = P.peer() < Q.peer();
  return { rude: pFirst ? l.a : l.b, polite: pFirst ? l.b : l.a,
           rudePage: pFirst ? P : Q, politePage: pFirst ? Q : P };
}

// ----------------------------------------------------------------- part 1 --
/*
  Fifteen hundred people walking, a unit further each feed, so every tick
  carries every row and a socket that does not read backs up. The one that
  stops reading is among them, so it is sent all of it.
*/
const ROWS = 1500;
let step = 0;
function feed() {
  const who = Array.from({ length: ROWS }, (_, i) => ({ profileId: 100000 + i, pos: [12345 + i, -2345 + step, 1234],
                                                       angleZ: 90, cell: '0x0001a26f', name: 'Walker ' + i }));
  step++;
  return fetch(BASE + '/positions', { method: 'POST', body: JSON.stringify({ who: who }) }).catch(() => { });
}

async function partOne() {
  console.log('1. the service, on a socket that has stopped reading:');
  const E = await openRaw(100000);
  const got = [];
  readRaw(E, (m) => got.push(m));
  sendRaw(E, { t: 'join', profileId: 100000, name: 'stops reading' });
  await until(() => got.some((m) => m.t === 'peers'));
  const eId = (got.find((m) => m.t === 'welcome') || {}).peer;
  E.pause();
  const before = got.length;

  // Backed (#2144) is only "a write the kernel has not taken yet": one tick of
  // 1500 rows is past the socket's high-water mark the moment it is written,
  // so health says backed until the kernel takes it, even while the reader's
  // kernel buffers still have room. Seen once is not enough. On the build
  // runner the feed stopped on such a moment, the kernel then took the tick,
  // drain cleared backed, and the joins were measured on a socket that was not
  // backed. So the feed stops only once backed has held for a whole second
  // with nothing being fed, which is a socket whose kernel buffers are full.
  // voice/test-backpressure.js waits the same way (two probes in a row).
  const t0 = Date.now();
  const timeline = [];
  let feeding = setInterval(feed, 200);
  let backed = false;
  while (!backed && Date.now() - t0 < 30000) {
    await sleep(200);
    if ((await health()).backed < 1) continue;
    timeline.push('backed at ' + (Date.now() - t0) + ' ms');
    clearInterval(feeding);
    backed = true;
    for (let k = 0; k < 5 && backed; k++) {
      await sleep(200);
      const hh = await health();
      if (hh.backed < 1) { backed = false; timeline.push('drained at ' + (Date.now() - t0) + ' ms (queue was a tick in flight)'); }
    }
    if (!backed) feeding = setInterval(feed, 200);
  }
  clearInterval(feeding);
  console.log('      the feed: ' + timeline.join(', ') + (backed ? ', held for 1 s with nothing fed' : ', never held'));
  yes('a socket that does not read is backed up, so what follows is measured on one', backed);
  if (!backed) { return; }
  const skipped0 = (await health()).skippedRosters;

  const N1 = await openRaw(100001);
  const n1 = [];
  readRaw(N1, (m) => n1.push(m));
  sendRaw(N1, { t: 'join', profileId: 100001, name: 'first in' });
  await until(() => n1.some((m) => m.t === 'peers'));
  const n1Id = (n1.find((m) => m.t === 'welcome') || {}).peer;

  const N2 = await openRaw(100002);
  const n2 = [];
  readRaw(N2, (m) => n2.push(m));
  sendRaw(N2, { t: 'join', profileId: 100002, name: 'second in' });
  await until(() => n2.some((m) => m.t === 'peers'));
  const n2Id = (n2.find((m) => m.t === 'welcome') || {}).peer;
  // skippedRosters moves only inside sendLatest while the socket is backed,
  // so it rising is the proof the second roster replaced the first on a
  // backed socket. Whether health says backed at the instant after is not:
  // backed is a write the kernel has not taken yet, and a reader that has
  // stopped still has its kernel take more as the receive window grows (seen
  // on GitHub's hosted Windows runner, 11 Oct: 0 to 1, backed 0 here, backed
  // again 300 ms later). A drain there flushes the newest roster, which the
  // order checks below still hold to, so asking for backed at this instant
  // only measured the kernel's timing.
  const h = await health();
  yes('two people join while it is backed, and the first roster is replaced unsent (skippedRosters ' +
      skipped0 + ' to ' + h.skippedRosters + ', backed ' + h.backed + ' just after)', h.skippedRosters > skipped0);

  // The newcomer offers to it at once, off its own roster, and sends a candidate.
  const theirs = n2.find((m) => m.t === 'peers');
  yes('the newcomer\'s roster names the backed socket, which is who it offers to',
      !!theirs && theirs.peers.some((p) => p.peer === eId));
  sendRaw(N2, { t: 'sdp', to: eId, sdp: { type: 'offer', sdp: 'measured offer' } });
  sendRaw(N2, { t: 'ice', to: eId, candidate: { candidate: 'candidate:1 1 udp 1 192.0.2.9 50000 typ host', sdpMid: '0', sdpMLineIndex: 0 } });
  await sleep(300);
  yes('and it is still backed when they are relayed to it', (await health()).backed >= 1);

  E.resume();
  const heard = await until(() => got.slice(before).some((m) => m.t === 'ice' && m.from === n2Id), 15000);
  yes('when it reads again, the offer and the candidate reach it', heard);
  const after = got.slice(before).filter((m) => m.t === 'peers' || m.t === 'sdp' || m.t === 'ice');
  const names = (m, id) => m.t === 'peers' && m.peers.some((p) => p.peer === id);
  const rosterAt = after.findIndex((m) => names(m, n2Id));
  const sdpAt = after.findIndex((m) => m.t === 'sdp' && m.from === n2Id);
  const iceAt = after.findIndex((m) => m.t === 'ice' && m.from === n2Id);
  console.log('      what it read, in order: ' + after.map((m) => m.t === 'peers'
    ? 'roster[' + m.peers.map((p) => p.peer).join(',') + ']' : m.t + ' from ' + m.from).join(', '));
  yes('the roster naming the sender comes before its offer', rosterAt >= 0 && sdpAt > rosterAt);
  yes('and before its candidate', rosterAt >= 0 && iceAt > rosterAt);
  yes('and the roster that named only the first newcomer never comes at all, as sendLatest says',
      !after.some((m) => names(m, n1Id) && !names(m, n2Id)));
  for (const s of [E, N1, N2]) { try { s.destroy(); } catch (e) { } }
  await sleep(300);
}

/* Every pair among these pages connected, or the ones that are not. */
function unlinked(list) {
  const out = [];
  for (let i = 0; i < list.length; i++) {
    for (let j = i + 1; j < list.length; j++) {
      if (!link(list[i], list[j])) out.push(list[i].name + ' and ' + list[j].name);
    }
  }
  return out;
}
function deaf(list) {
  const out = [];
  for (const P of list) for (const Q of list) { if (P !== Q && !hears(P, Q)) out.push(P.name + ' cannot hear ' + Q.name); }
  return out;
}
/* The roles held in every pair, from the first offer to the last. */
function checkRoles(list, label) {
  let bad = [];
  for (let i = 0; i < list.length; i++) {
    for (let j = i + 1; j < list.length; j++) {
      const r = roles(list[i], list[j]);
      if (!r) { bad.push(list[i].name + ' and ' + list[j].name + ' are not connected'); continue; }
      if (r.rude.rollbacks) bad.push(r.rudePage.name + ' (impolite) rolled back');
      const sent = offersBy(r.politePage, r.rude);
      const dropped = sent.filter((o) => r.polite.offersTaken.indexOf(o) < 0);
      if (dropped.length) bad.push(r.politePage.name + ' (polite) left ' + dropped.length + ' offer(s) from ' + r.rudePage.name + ' unanswered');
    }
  }
  yes(label + ': in every pair the lower peer id never rolls back and the higher takes every offer it is sent' +
      (bad.length ? ' (' + bad.join('; ') + ')' : ''), !bad.length);
}

// ----------------------------------------------------------------- part 2 --
async function partTwo() {
  console.log('\n2. two launcher pages, and both microphones opening at once:');
  const P = launcherPage('Aela', 201);
  P.start();
  await until(() => P.peer() > 0);
  const Q = launcherPage('Brynjolf', 202);
  Q.start();
  yes('both pages ask for the address the launcher gave them, through Caddy',
      await until(() => Q.urls.length > 0) && P.urls[0] === 'wss://thornswood.test/voice/' && Q.urls[0] === P.urls[0]);
  yes('they negotiate through the relay before either has a microphone, each taking the other\'s candidates',
      await until(() => bothTook(P, Q)));
  yes('and nobody is heard yet, because nobody sends', !hears(P, Q) && !hears(Q, P));
  const r = roles(P, Q);
  const rolled = r ? r.polite.rollbacks : 0;
  const offered = r ? offersBy(r.rudePage, r.polite).length : 0;

  // Both in the same moment, each making its offer before it reads the
  // other's, so the two offers cross.
  P.hold(); Q.hold();
  P.mic();
  Q.mic();
  yes('both microphones open and both pages offer at once',
      await until(() => [P, Q].every((x) => x.pcs.every((pc) => pc.signalingState === 'have-local-offer'))));
  P.release(); Q.release();
  yes('once both microphones open, each hears the other', await until(() => hears(P, Q) && hears(Q, P)));
  const r2 = roles(P, Q);
  yes('the offers crossed: the polite side (' + (r2 && r2.politePage.name) + ') rolled its own back',
      !!r2 && r2.polite.rollbacks > rolled);
  const ignored = r2 ? offersBy(r2.rudePage, r2.polite).slice(offered)
                         .filter((o) => r2.rude.offersTaken.indexOf(o) < 0) : [];
  yes('and the impolite side (' + (r2 && r2.rudePage.name) + ') ignored the one that crossed its own', ignored.length >= 1);
  checkRoles([P, Q], 'launcher and launcher');
  const pcs = P.pcs.concat(Q.pcs);
  yes('no candidate was refused, early or for another session', pcs.every((pc) => !pc.iceRefused));
  yes('and neither page said anything failed', !troubles(P).length && !troubles(Q).length);
  if (troubles(P).length || troubles(Q).length) console.log('      ' + troubles(P).concat(troubles(Q)).join('\n      '));
  closePage(P);
  closePage(Q);
  await sleep(200);
}

// ----------------------------------------------------------------- part 3 --
async function partThree() {
  console.log('\n3. the order that dropped: the game\'s overlay gets on a socket that joined first:');
  const L = launcherPage('Lydia', 301);
  L.start();
  await until(() => L.peer() > 0);
  // At the character choice: the chat joins with the token it was handed.
  const G = gamePage('Gerdur', 302, true);
  yes('the game\'s chat socket joins on its own, before voice is configured',
      await until(() => G.peer() > 0 && G.box.thornswoodNet.isUp()));
  const M = launcherPage('Mjoll', 303);
  M.start();
  await until(() => M.peer() > 0);
  const offeredTo = (from) => G.wire.some((m) => m.t === 'sdp' && m.from === from.peer() && m.sdp.type === 'offer') &&
                              G.wire.some((m) => m.t === 'ice' && m.from === from.peer());
  yes('the launcher already in the room, and the one that joined after the chat, both send that socket an offer ' +
      'and candidates before the overlay is listening', await until(() => offeredTo(L) && offeredTo(M)));
  yes('the launcher that was there first is the impolite one in that pair, waiting on its answer',
      L.peer() < G.peer() && L.pcs.some((pc) => pc.signalingState === 'have-local-offer'));
  yes('and the overlay has opened nobody yet', G.pcs.length === 0);

  // In the world: the voice plugin configures the overlay, with the
  // microphone held shut as it does at first.
  G.configure(false);
  const N = launcherPage('Njada', 304);
  N.start();
  const room = [L, G, M, N];
  yes('once the overlay is on, every pair in the room connects', await until(() => !unlinked(room).length));
  const still = unlinked(room);
  if (still.length) console.log('      not connected: ' + still.join(', '));
  yes('the overlay and the launcher that was there first connect', !!link(G, L));
  yes('the overlay and the launcher that joined before it was on connect', !!link(G, M));
  yes('the overlay and the launcher that joined after it was on connect', !!link(G, N));
  yes('and the overlay took the candidates both launchers sent before it was on, as they took its own',
      bothTook(G, L) && bothTook(G, M));

  // Every microphone at once: the plugin's second configure opens the
  // overlay's, and every page offers before it reads anybody else's, so in
  // every pair the two offers cross.
  const pairs = [];
  for (let i = 0; i < room.length; i++) {
    for (let j = i + 1; j < room.length; j++) {
      const r = roles(room[i], room[j]);
      if (r) pairs.push({ r: r, rolled: r.polite.rollbacks, offered: offersBy(r.rudePage, r.polite).length });
    }
  }
  room.forEach((x) => x.hold());
  L.mic(); M.mic(); N.mic();
  G.configure(true);
  G.mic();
  yes('every page offers to everybody at once',
      await until(() => room.every((x) => x.pcs.filter((pc) => !pc.closed).every((pc) => pc.signalingState === 'have-local-offer'))));
  room.forEach((x) => x.release());
  yes('and with every microphone open, everybody hears everybody', await until(() => !deaf(room).length));
  const unheard = deaf(room);
  if (unheard.length) console.log('      ' + unheard.join(', '));
  yes('the overlay hears the launcher that was there first, and it hears the overlay', hears(G, L) && hears(L, G));
  const crossed = pairs.filter((x) => x.r.polite.rollbacks > x.rolled &&
                                      offersBy(x.r.rudePage, x.r.polite).slice(x.offered)
                                        .some((o) => x.r.rude.offersTaken.indexOf(o) < 0));
  yes('in all six pairs the offers crossed, the polite side rolled back and the impolite side ignored the other\'s, ' +
      'the overlay on both sides of it', pairs.length === 6 && crossed.length === 6 &&
      crossed.some((x) => x.r.politePage === G) && crossed.some((x) => x.r.rudePage === G));
  checkRoles(room, 'overlay and launchers');
  const pcs = [].concat(L.pcs, G.pcs, M.pcs, N.pcs);
  yes('no candidate was refused, early or for another session', pcs.every((pc) => !pc.iceRefused));
  const said = [].concat(troubles(L), troubles(G), troubles(M), troubles(N));
  yes('and no page said anything failed', !said.length);
  if (said.length) console.log('      ' + said.join('\n      '));
  room.forEach(closePage);
  await sleep(200);
}

// ----------------------------------------------------------------- part 4 --
async function partFour() {
  console.log('\n4. the overlay on before its socket joins, then that socket joining again as a new peer:');
  const K = launcherPage('Kodlak', 401);
  K.start();
  K.mic();
  await until(() => K.peer() > 0);
  // No token yet, so the chat asks the front for one and waits.
  const H = gamePage('Hulda', 402, false);
  H.configure(true);
  H.mic();
  const asked = () => H.said.filter((l) => /^thornswood-front: token\? 402$/.test(l)).length;
  yes('the chat asks for a token', await until(() => asked() >= 1));
  H.box.thornswoodNet.setToken(tokenFor(402));
  yes('and once it has one, the overlay that was already on connects and both hear each other',
      await until(() => hears(H, K) && hears(K, H)));
  const firstId = H.peer();
  const firstPcs = H.pcs.slice();

  // A new name closes the connection and opens another, which is a new peer.
  const n = asked();
  H.box.thornswoodNet.setName('Hulda Brightmane');
  yes('a new name makes the chat ask for a fresh token', await until(() => asked() > n, 8000));
  H.box.thornswoodNet.setToken(tokenFor(402));
  yes('and it joins again as a new peer', await until(() => H.peer() > 0 && H.peer() !== firstId));
  yes('after which both hear each other again', await until(() => hears(H, K) && hears(K, H)));
  yes('the overlay closed every connection it had on the old socket', firstPcs.every((pc) => pc.closed));
  yes('and the launcher closed its connection to the old peer', await until(() => K.pcs.filter((pc) => !pc.closed).length === 1));
  checkRoles([K, H], 'overlay and launcher after the rejoin');
  const said = [].concat(troubles(K), troubles(H));
  yes('no page said anything failed', !said.length);
  if (said.length) console.log('      ' + said.join('\n      '));
  closePage(K);
  closePage(H);
}

// ----------------------------------------------------------------- part 5 --
/*
  What the chat keeps for voice, on its own, with a socket that records:
  the newest roster, signalling from the people on it in the order it
  came, nothing from somebody who left, a limit for one peer, and nothing
  at all once voice is on.
*/
function partFive() {
  console.log('\n5. what the chat keeps until voice is on:');
  /* The chat file on its own, with a socket that records and a log. */
  function chatAlone() {
    const made = [];
    function FakeSocket() { made.push(this); this.readyState = 0; this.sent = []; }
    FakeSocket.prototype.send = function (m) { this.sent.push(m); };
    FakeSocket.prototype.close = function () { this.readyState = 3; };
    const logged = [];
    const box = { WebSocket: FakeSocket, console: { log: (l) => logged.push(l) },
                  THORNSWOOD: { host: 'thornswood.test', port: 443, profileId: 7, name: 'tester', token: 'v2.7.1.x',
                                base: 'https://thornswood.test/voice' },
                  skyrimPlatform: { sendMessage: () => { } },
                  setTimeout: () => 0, clearTimeout: () => { }, setInterval: () => 0, clearInterval: () => { } };
    box.window = box;
    vm.createContext(box);
    vm.runInContext(CHAT_SRC, box, { filename: 'thornswood-chat.js' });
    const ws = made[0];
    ws.readyState = 1;
    ws.onopen();
    return { n: box.thornswoodNet, ws: ws, logged: logged, say: (m) => ws.onmessage({ data: JSON.stringify(m) }) };
  }
  const c = chatAlone();
  const n = c.n, say = c.say;
  yes('the chat has a way for voice to get on', !!n && typeof n.board === 'function');
  if (!n || typeof n.board !== 'function') return;
  say({ t: 'welcome', peer: 10, profileId: 7 });
  say({ t: 'peers', peers: [{ peer: 4 }, { peer: 5 }, { peer: 10 }], iceServers: [] });
  say({ t: 'sdp', from: 4, sdp: { type: 'offer', sdp: 'four' } });
  say({ t: 'ice', from: 4, candidate: { candidate: 'c4a' } });
  say({ t: 'sdp', from: 5, sdp: { type: 'offer', sdp: 'five' } });
  say({ t: 'pos', who: {} });
  say({ t: 'peers', peers: [{ peer: 4 }, { peer: 10 }, { peer: 11 }], iceServers: [] });
  say({ t: 'ice', from: 4, candidate: { candidate: 'c4b' } });
  say({ t: 'sdp', from: 11, sdp: { type: 'offer', sdp: 'eleven' } });
  for (let i = 0; i < 150; i++) say({ t: 'ice', from: 11, candidate: { candidate: 'flood ' + i } });
  const got = [];
  n.board((m) => got.push(m));
  // The position view is handed over too, after the roster (#1924); the
  // order of the signalling is what this part reads.
  const shape = got.filter((m) => m.t === 'peers' || m.t === 'sdp' || m.t === 'ice')
                   .map((m) => m.t === 'peers' ? 'peers ' + m.peers.map((p) => p.peer).join(',')
                                               : m.t + ' ' + m.from + ' ' + (m.sdp ? m.sdp.sdp : m.candidate.candidate));
  yes('voice gets the newest roster first', shape[0] === 'peers 4,10,11');
  yes('then what the people on it sent, in the order it came',
      JSON.stringify(shape.slice(1, 5)) === JSON.stringify(['sdp 4 four', 'ice 4 c4a', 'ice 4 c4b', 'sdp 11 eleven']));
  yes('and nothing from somebody the newest roster no longer names', !shape.some((l) => / 5 /.test(l)));
  yes('and the whole position view right after the roster, since the next tick carries only what moved (#1924)',
      !!got[1] && got[1].t === 'pos' && got.filter((m) => m.t === 'pos').length === 1);
  yes('a hundred from one peer is the most kept, and the log says so once',
      got.filter((m) => m.from === 11).length === 100 && c.logged.filter((l) => /peer 11 sent 100/.test(l)).length === 1);
  say({ t: 'sdp', from: 4, sdp: { type: 'offer', sdp: 'live' } });
  yes('after that it hears everything live', !!got[got.length - 1].sdp && got[got.length - 1].sdp.sdp === 'live');
  const late = [];
  n.board((m) => late.push(m));
  yes('and nothing more is kept for anybody once voice is on', late.length === 0);

  // A connection that closes takes what it was sent with it.
  const d = chatAlone();
  d.say({ t: 'welcome', peer: 20, profileId: 7 });
  d.say({ t: 'peers', peers: [{ peer: 3 }, { peer: 20 }], iceServers: [] });
  d.say({ t: 'sdp', from: 3, sdp: { type: 'offer', sdp: 'old socket' } });
  d.ws.onclose();
  const got2 = [];
  d.n.board((m) => got2.push(m));
  yes('a connection that closed hands voice nothing it was sent', got2.length === 0);

  // And one that joins again starts from its own welcome.
  const e = chatAlone();
  e.say({ t: 'welcome', peer: 30, profileId: 7 });
  e.say({ t: 'peers', peers: [{ peer: 2 }, { peer: 30 }], iceServers: [] });
  e.say({ t: 'sdp', from: 2, sdp: { type: 'offer', sdp: 'to 30' } });
  e.say({ t: 'welcome', peer: 31, profileId: 7 });
  e.say({ t: 'peers', peers: [{ peer: 2 }, { peer: 31 }], iceServers: [] });
  const got3 = [];
  e.n.board((m) => got3.push(m));
  yes('and a new welcome starts over: only the roster since it', got3.length === 1 && got3[0].t === 'peers' &&
      got3[0].peers.some((p) => p.peer === 31));
}

// -------------------------------------------------------------- the source --
function partSix() {
  console.log('\n6. the pages\' own rules:');
  yes('the launcher\'s page: the lower peer id offers and is impolite',
      /open\(p\.peer, p, myPeer < p\.peer\)/.test(HOST_SRC) && /polite: !initiator/.test(HOST_SRC));
  yes('the overlay: the same rule', /open\(id, p, myPeer < id\)/.test(OVERLAY_SRC) && /polite: !initiator/.test(OVERLAY_SRC));
  yes('both ignore a colliding offer only when impolite',
      /if \(collision && !rec\.polite\) return;/.test(HOST_SRC) && /if \(collision && !rec\.polite\) \{\s*return;\s*\}/.test(OVERLAY_SRC));
  yes('the overlay gets on the chat\'s socket with board', /n\.board\(onNet\);/.test(OVERLAY_SRC) && !/n\.on\(onNet\);/.test(OVERLAY_SRC));
}

(async () => {
  await start();
  await partOne();
  await partTwo();
  await partThree();
  await partFour();
  partFive();
  partSix();
})().catch((e) => {
  fail++;
  console.log('FAIL  the harness itself: ' + (e && e.stack || e));
}).then(() => {
  pages.forEach(closePage);
  for (const s of raw) { try { s.destroy(); } catch (e) { } }
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  const rm = () => { try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { } };
  if (srv && srv.exitCode === null) { srv.once('exit', () => { rm(); process.exit(fail ? 1 : 0); }); srv.kill(); }
  else { rm(); process.exit(fail ? 1 : 0); }
  setTimeout(() => { rm(); process.exit(fail ? 1 : 0); }, 2000).unref();
});
