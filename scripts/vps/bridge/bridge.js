#!/usr/bin/env node
'use strict';
/*
  bridge.js

  The box's only way in over ssh. Built for cloud Claude threads (#2753,
  Patrick on 19 Oct 2026, #2750 C), whose proxy carries HTTPS only, so port
  22 never opens from there, but a WebSocket on 443 goes through (measured 19
  Oct). Since #2891 everybody comes this way, One and each person with box
  access too, so port 22 can be shut to every outside address and a home
  address that changes stops nothing. Caddy hands wss://thornswood.net/box/
  to this, on loopback, and this joins each WebSocket it accepts to the box's
  own sshd on 127.0.0.1:22. connect.js is the other end.

  WHO GETS THROUGH. Each one who may has a token of their own: tokens\<name>
  beside this file holds the SHA-256 of it, in hex, and nothing else, so the
  box never holds a token that works (Grant-BoxAccess.ps1 writes and removes
  them, one name at a time). A WebSocket opens only when the SHA-256 of what
  came in "Authorization: Bearer" is one of them, each compared in constant
  time; anything else is a 401 and closed, and a plain request is a 404. A
  token only reaches sshd's login: a shell still needs that person's key,
  which the box accepts only from 127.0.0.1 (the from= on its line), so a key
  is no use anywhere but through here. At most MAX_OPEN sessions at once.

  It writes one line per session to its log: whose token opened it, when,
  how it ended and how many bytes went each way. No address and no content:
  it never sees inside the ssh session, which is encrypted end to end.

  ONE WEBSOCKET IS NOT THE SESSION (#3214). Cloudflare stands between every
  machine and Caddy since #2995, and it ends a long WebSocket whenever it
  restarts the server holding it. Measured 27 Oct 2026 from a cloud thread:
  four silent 11-minute box runs, with and without standard input, each lost
  their WebSocket after 329 to 588 s, two at the same millisecond, and on 21
  Oct two Install-Runner -Remove runs from One lost theirs about 500 s in.
  Until then the ssh inside ended with it, while the box went on unseen. So
  a connect.js that asks for it ("X-Thornswood-Resume: new") gets a name for
  its session ("X-Thornswood-Session") and the session outlives its
  WebSocket: when that goes without a close frame, the bridge keeps sshd's
  side for RESUME_MS, and a new WebSocket with the same holder's token and
  "X-Thornswood-Resume: <name> <bytes it has>" takes it on. The answer says
  how many bytes the bridge has ("X-Thornswood-Got"), and each end sends
  again what the other does not have (ws.js Carry). Each end acks what it
  got in "ack <n>" text frames, and sshd is read no more while more than
  HOLD_MAX of what it said waits for an ack. A connect.js from before then
  asks for nothing, and its session ends with its WebSocket as before. The
  name opens nothing by itself: the token is checked first, and what flows
  is ssh, encrypted end to end, so it may sit in Caddy's box.log.

      node bridge.js                 listens on 127.0.0.1:7790
      THORNSWOOD_BRIDGE_PORT         another port
      THORNSWOOD_BRIDGE_TOKENS       the folder of token digests; tokens
                                     beside this file when unset
      THORNSWOOD_BRIDGE_TARGET       host:port to join to; 127.0.0.1:22
                                     when unset (the harness points it at
                                     an echo server)
      THORNSWOOD_BRIDGE_PING_MS      the ping interval, 25000 when unset
      THORNSWOOD_BRIDGE_RESUME_MS    how long a session is held for a new
                                     WebSocket, 60000 when unset

  Install-Bridge.ps1 puts it on the box as the task "Thornswood Bridge",
  LOCAL SERVICE with a SID of its own, like voice and the site (#2578).
*/
const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { OP, accept, encode, Reader, Carry } = require('./ws.js');

const PORT = Number(process.env.THORNSWOOD_BRIDGE_PORT) || 7790;
const TOKENS = process.env.THORNSWOOD_BRIDGE_TOKENS || path.join(__dirname, 'tokens');
const TARGET = process.env.THORNSWOOD_BRIDGE_TARGET || '127.0.0.1:22';
const MAX_OPEN = 8;
// A ping when nothing has gone either way for this long, and the session is
// let go after three unanswered (voice-server.js says why, #519).
const PING_EVERY = Number(process.env.THORNSWOOD_BRIDGE_PING_MS) || 25000;
// A session connect.js can carry over (#3214, the header's ONE WEBSOCKET IS
// NOT THE SESSION): how long it is held once its WebSocket has gone, how
// much of what sshd said may wait for connect.js to ack it before sshd is
// read no more, and how often what came in is acked.
const RESUME_MS = Number(process.env.THORNSWOOD_BRIDGE_RESUME_MS) || 60000;
const HOLD_MAX = 8 * 1024 * 1024;
const ACK_BYTES = 128 * 1024;
const ACK_MS = 1000;

// Server-Log.js --stamp puts the time on each line, as it does for voice.
function log(line) {
  console.log(line);
}

// The folder is read at every upgrade, so a token Grant-BoxAccess.ps1 adds
// counts at once and one it removes refuses that person at once, everybody
// else untouched. Each file is named for its holder and holds the SHA-256 of
// the token in hex. The digest of what was sent is compared with every one,
// each in constant time, so how long it takes says nothing about which came
// close. Returns the holder's name, or '' when it is nobody's.
const NAME = /^[a-z0-9][a-z0-9-]{0,31}$/;
function tokenHolder(sent) {
  if (!sent) return '';
  const got = crypto.createHash('sha256').update(sent).digest();
  let names;
  try { names = fs.readdirSync(TOKENS); } catch (e) { return ''; }
  let who = '';
  for (const name of names.sort()) {
    if (!NAME.test(name)) continue;
    let hex;
    try { hex = fs.readFileSync(path.join(TOKENS, name), 'utf8').trim().toLowerCase(); } catch (e) { continue; }
    if (!/^[0-9a-f]{64}$/.test(hex)) continue;
    if (crypto.timingSafeEqual(got, Buffer.from(hex, 'hex')) && !who) who = name;
  }
  return who;
}

function refuse(socket, status, why) {
  socket.end('HTTP/1.1 ' + status + '\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
  log('refused: ' + why);
}

let open = 0;
let seq = 0;

// A plain request gets a 404 with a line nothing else on the box says. The
// site's own 404 is "not here", so Install-Bridge.ps1's checks look for this
// whole line, and an answer from the site is never taken for the bridge (#2875).
const PLAIN = 'box bridge: not here';

const server = http.createServer((req, res) => {
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end(PLAIN + '\n');
});

// Every session connect.js may carry over to a new WebSocket (#3214), by the
// name the bridge gave it, while it is open or held.
const carried = new Map();

server.on('upgrade', (req, socket, head) => {
  socket.on('error', () => {});
  const auth = String(req.headers['authorization'] || '');
  const sent = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (req.method !== 'GET' || String(req.headers['upgrade'] || '').toLowerCase() !== 'websocket') return refuse(socket, '400 Bad Request', 'not a WebSocket upgrade');
  if (req.headers['sec-websocket-version'] !== '13' || !req.headers['sec-websocket-key']) return refuse(socket, '400 Bad Request', 'no WebSocket key or version 13');
  const who = tokenHolder(sent);
  if (!who) return refuse(socket, '401 Unauthorized', sent ? 'a token that is nobody\'s' : 'no token');
  const resume = String(req.headers['x-thornswood-resume'] || '').trim();
  if (resume && resume !== 'new') return goOn(req, socket, head, who, resume);
  if (open >= MAX_OPEN) return refuse(socket, '503 Service Unavailable', MAX_OPEN + ' sessions already open');
  start(req, socket, head, who, resume === 'new');
});

function switching(req, extra) {
  return 'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    'Sec-WebSocket-Accept: ' + accept(req.headers['sec-websocket-key']) + '\r\n' +
    extra.map((l) => l + '\r\n').join('') + '\r\n';
}

// A new WebSocket for a session the bridge holds: "<name> <n>", where n is
// how many of the session's bytes connect.js has. Only the holder whose
// token opened it may take it on. The name alone opens nothing: the token
// is checked first, and what flows is ssh, encrypted end to end, so the name
// may sit in Caddy's box.log beside the request.
function goOn(req, socket, head, who, resume) {
  const m = /^([0-9a-f]{32}) (\d{1,15})$/.exec(resume);
  if (!m) return refuse(socket, '400 Bad Request', 'a resume that is not a session and a byte count');
  const s = carried.get(m[1]);
  if (!s || s.who !== who) return refuse(socket, '410 Gone', 'a resume of a session the bridge does not hold');
  s.goOn(req, socket, head, Number(m[2]));
}

function start(req, socket, head, who, resumable) {
  const [host, port] = TARGET.split(':');
  const ssh = net.connect({ host, port: Number(port) });
  const id = ++seq;
  const name = resumable ? crypto.randomBytes(16).toString('hex') : '';
  const carry = resumable ? new Carry() : null;
  const started = Date.now();
  let up = 0;
  let down = 0;
  let ended = '';
  let ws = null;          // the WebSocket the session rides now, null while held
  let reader = null;
  let heard = Date.now();
  let unanswered = 0;
  let waitDrain = false;
  let heldSince = 0;
  let holdTimer = null;
  let carriedOver = 0;
  let sshdDone = false;
  open++;
  const s = { who, goOn: goOnHere };
  if (resumable) carried.set(name, s);

  function finish(why) {
    if (ended) return;
    ended = why;
    open--;
    if (resumable) carried.delete(name);
    clearInterval(pinger);
    clearInterval(acker);
    clearTimeout(holdTimer);
    log('session ' + id + ' ended: ' + why + ', ' + Math.round((Date.now() - started) / 1000) + ' s, ' + up + ' bytes in, ' + down + ' bytes out' +
      (carriedOver ? ', carried over to ' + carriedOver + ' new WebSocket' + (carriedOver > 1 ? 's' : '') : ''));
    if (ws && !ws.destroyed) {
      try { ws.end(encode(OP.CLOSE, Buffer.from([0x03, 0xe8]), false)); } catch (e) { ws.destroy(); }
    }
    ssh.destroy();
  }

  // sshd is read only while what it said can go somewhere: the WebSocket
  // takes more, and what connect.js has not acked stays under HOLD_MAX.
  function flow() {
    if (ended) return;
    if (waitDrain || (carry && carry.keptBytes > HOLD_MAX)) ssh.pause();
    else ssh.resume();
  }

  function sendAck() {
    if (!ws || !carry.owed) return;
    carry.told = carry.got;
    ws.write(encode(OP.TEXT, Buffer.from('ack ' + carry.got), false));
  }

  // The session's WebSocket went without a close. One connect.js cannot
  // carry over ends with it, as before #3214; any other is held for
  // RESUME_MS for connect.js to come back on a new one.
  function lost(why) {
    if (ended) return;
    if (!resumable) return finish(why);
    const old = ws;
    ws = null;
    reader = null;
    waitDrain = false;
    if (old) old.destroy();
    heldSince = Date.now();
    log('session ' + id + ' lost its WebSocket: ' + why + ', after ' + Math.round((heldSince - started) / 1000) + ' s; held ' + Math.round(RESUME_MS / 1000) + ' s for connect.js to come back');
    holdTimer = setTimeout(() => finish(why + ', and connect.js did not come back within ' + Math.round(RESUME_MS / 1000) + ' s'), RESUME_MS);
    flow();
  }

  // Joins the session to a WebSocket. Events from one it rode before are
  // not this one's: they are dropped, so nothing is counted or sent twice.
  function attach(sock, rest) {
    ws = sock;
    reader = new Reader({ masked: true });
    heard = Date.now();
    unanswered = 0;
    waitDrain = false;
    const mine = () => ws === sock;
    sock.on('data', (chunk) => { if (mine()) take(chunk); });
    // The HTTP server keeps its sockets half open, so a far end that goes
    // away says so with 'end', and 'close' would wait for this end forever.
    sock.on('end', () => { if (mine()) lost('the WebSocket closed'); });
    sock.on('close', () => { if (mine()) lost('the WebSocket closed'); });
    sock.on('drain', () => { if (mine() && waitDrain) { waitDrain = false; flow(); } });
    if (rest && rest.length) take(rest);
    flow();
  }

  function allSaid() {
    if (sshdDone && ws && carry.acked === carry.sent) finish('sshd closed it');
  }

  function toClient(chunk) {
    if (carry) carry.out(chunk);
    if (ws && !ws.write(encode(OP.BINARY, chunk, false))) waitDrain = true;
    flow();
  }

  function goOnHere(req2, sock, rest, got) {
    if (ended) return refuse(sock, '410 Gone', 'a resume of a session that has ended');
    let again;
    try { again = carry.since(got); } catch (e) {
      refuse(sock, '409 Conflict', 'a resume from a byte the bridge no longer holds');
      return finish('connect.js asked to go on from ' + e.message);
    }
    const away = heldSince ? Math.round((Date.now() - heldSince) / 1000) + ' s after it was lost' : 'before the old one was seen to go';
    if (ws) { const old = ws; ws = null; old.destroy(); }
    clearTimeout(holdTimer);
    holdTimer = null;
    heldSince = 0;
    carriedOver++;
    sock.write(switching(req2, ['X-Thornswood-Got: ' + carry.got]));
    let bytes = 0;
    for (const c of again) { sock.write(encode(OP.BINARY, c, false)); bytes += c.length; }
    log('session ' + id + ' carried over to a new WebSocket ' + away + ', ' + bytes + ' bytes sent again');
    attach(sock, rest);
    allSaid();
  }

  // A WebSocket that goes before sshd has taken the session never carried it.
  socket.once('close', () => { if (!ws && !heldSince) finish('the WebSocket closed before sshd took it'); });
  ssh.once('connect', () => {
    if (ended) return;
    socket.write(switching(req, resumable ? ['X-Thornswood-Session: ' + name] : []));
    // How long sshd took to take it, which is part of what connect.js
    // counts as waiting for the answer to the upgrade (#3297).
    log('session ' + id + ' opened for ' + who + ' (' + open + ' open), sshd took ' + (Date.now() - started) + ' ms' + (resumable ? ', can be carried over' : ''));
    attach(socket, head);
  });
  ssh.on('error', (e) => finish('sshd: ' + e.message));
  // sshd's last bytes (the exit status ssh waits for) may still be on their
  // way when it ends, or kept for a WebSocket that has gone, so a session
  // that can be carried over ends once connect.js has acked all of them.
  ssh.on('end', () => {
    sshdDone = true;
    if (!carry) return finish('sshd closed it');
    allSaid();
  });
  ssh.on('data', (chunk) => {
    down += chunk.length;
    toClient(chunk);
  });

  function take(chunk) {
    heard = Date.now();
    unanswered = 0;
    let msgs;
    try { msgs = reader.push(chunk); } catch (e) { return finish('a bad frame: ' + e.message); }
    for (const m of msgs) {
      if (m.op === OP.BINARY) {
        up += m.data.length;
        if (carry) carry.took(m.data.length);
        if (!ssh.write(m.data)) {
          const sock = ws;
          sock.pause();
          ssh.once('drain', () => sock.resume());
        }
        if (carry && carry.owed >= ACK_BYTES) sendAck();
      } else if (m.op === OP.PING) {
        ws.write(encode(OP.PONG, m.data, false));
      } else if (m.op === OP.CLOSE) {
        return finish('the far end closed it');
      } else if (m.op === OP.TEXT) {
        const a = carry ? /^ack (\d{1,15})$/.exec(m.data.toString('latin1')) : null;
        if (!a) return finish('a text frame that is not an ack, which ssh never sends');
        try { carry.ack(Number(a[1])); } catch (e) { return finish('connect.js sent ' + e.message); }
        flow();
        allSaid();
      }
    }
  }

  const pinger = setInterval(() => {
    if (!ws || Date.now() - heard < PING_EVERY) return;
    if (++unanswered > 3) return lost('the far end answered nothing for ' + Math.round((Date.now() - heard) / 1000) + ' s');
    ws.write(encode(OP.PING, Buffer.alloc(0), false));
  }, PING_EVERY);
  // What came in is acked at least this often, so connect.js lets it go.
  const acker = resumable ? setInterval(sendAck, ACK_MS) : null;
}

server.listen(PORT, '127.0.0.1', () => {
  log('box bridge listening on 127.0.0.1:' + PORT + ', joining to ' + TARGET + ', tokens from ' + TOKENS);
});
