'use strict';
/*
  Thornswood proximity voice, server side.

  Runs next to the SkyMP server. Two jobs and nothing else:

    1. Take position snapshots from the gamemode over plain HTTP on loopback,
       and fan them out to everyone connected.
    2. Relay WebRTC signalling between people so their browsers can talk to
       each other directly. The audio never comes through here.

  Deliberately dependency free, including the WebSocket implementation below.
  The VPS gets a zip and a node binary and nothing else: an npm install up
  there is one more thing that can be offline, out of date, or blocked when
  somebody is trying to get a server running at midnight.

  Positions come from the server rather than from anybody's game, because the
  server already knows them. That means voice does not depend on which SkyMP
  client build people run, and nobody can move their own voice around by
  editing a file.
*/

const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.THORNSWOOD_VOICE_PORT || 7778);

/*
  Where to check that a character creation choice came from the person who owns
  that profile.

  /choose cannot be locked to the loopback: every person's launcher calls it
  from their own machine, which is the whole point of it. So until now it took
  anybody's word for anything, and a stranger could set your profession, your
  half and your home town before you ever claimed them.

  THORNSWOOD_SITE off means no checking, which is how this behaved before and
  is still the behaviour when the site cannot be reached. That is deliberate:
  being unable to create a character is loud and total, and the thing being
  prevented is griefing rather than a breach. Every unverified choice is logged
  so it is visible rather than silent.
*/
const SITE = String(process.env.THORNSWOOD_SITE || '').replace(/\/+$/, '');
const HERE = __dirname;

// How long a position snapshot stays believable. The gamemode pushes about
// five a second; if they stop, everybody is stale and goes quiet rather than
// hanging in the last place they were heard.
const STALE_MS = 3000;

// ---------------------------------------------------------------- state ----
let positions = new Map();   // profileId -> {pos:[x,y,z], angleZ, cell, name, at}
let nextPeer = 1;
const peers = new Map();     // peerId -> {ws, profileId, name}

// Chat lines beginning with a slash, waiting for the gamemode to collect them.
// Held in memory on purpose: a command nobody was there to run is not worth
// keeping across a restart.
const commands = [];

// ------------------------------------------------------------ websocket ----
// RFC 6455, the parts a small JSON relay needs: the handshake, masked text
// frames from the client, unmasked text frames back, close and ping.
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

function accept(key) {
  return crypto.createHash('sha1').update(key + GUID).digest('base64');
}

function frame(payload) {
  const data = Buffer.from(payload, 'utf8');
  const len = data.length;
  let head;
  if (len < 126) {
    head = Buffer.alloc(2);
    head[1] = len;
  } else if (len < 65536) {
    head = Buffer.alloc(4);
    head[1] = 126;
    head.writeUInt16BE(len, 2);
  } else {
    head = Buffer.alloc(10);
    head[1] = 127;
    head.writeBigUInt64BE(BigInt(len), 2);
  }
  head[0] = 0x81;            // FIN + text
  return Buffer.concat([head, data]);
}

class Sock {
  constructor(socket) {
    this.socket = socket;
    this.buf = Buffer.alloc(0);
    this.onmessage = null;
    this.onclose = null;
    this.closed = false;

    socket.on('data', (d) => this.feed(d));
    socket.on('error', () => this.close());
    socket.on('close', () => {
      if (this.closed) return;
      this.closed = true;
      if (this.onclose) this.onclose();
    });
  }

  send(obj) {
    if (this.closed) return;
    try { this.socket.write(frame(JSON.stringify(obj))); } catch (e) { this.close(); }
  }

  close() {
    if (this.closed) return;
    this.closed = true;
    try { this.socket.destroy(); } catch (e) { }
    if (this.onclose) this.onclose();
  }

  feed(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    // A frame can arrive split across reads, and several can arrive in one, so
    // this loops until what is left is not a whole frame.
    for (;;) {
      if (this.buf.length < 2) return;
      const b0 = this.buf[0], b1 = this.buf[1];
      const op = b0 & 0x0f;
      const masked = (b1 & 0x80) !== 0;
      let len = b1 & 0x7f;
      let off = 2;

      if (len === 126) {
        if (this.buf.length < 4) return;
        len = this.buf.readUInt16BE(2); off = 4;
      } else if (len === 127) {
        if (this.buf.length < 10) return;
        const big = this.buf.readBigUInt64BE(2);
        if (big > 1000000n) { this.close(); return; }
        len = Number(big); off = 10;
      }

      let mask = null;
      if (masked) {
        if (this.buf.length < off + 4) return;
        mask = this.buf.slice(off, off + 4); off += 4;
      }
      if (this.buf.length < off + len) return;

      const body = Buffer.from(this.buf.slice(off, off + len));
      if (mask) for (let i = 0; i < body.length; i++) body[i] ^= mask[i & 3];
      this.buf = this.buf.slice(off + len);

      if (op === 0x8) { this.close(); return; }        // close
      if (op === 0x9) {                                 // ping -> pong
        try { this.socket.write(Buffer.concat([Buffer.from([0x8a, 0]), Buffer.alloc(0)])); } catch (e) { }
        continue;
      }
      if (op !== 0x1) continue;                         // only text is used

      let msg = null;
      try { msg = JSON.parse(body.toString('utf8')); } catch (e) { continue; }
      if (msg && this.onmessage) this.onmessage(msg);
    }
  }
}

// ------------------------------------------------------------- signalling --
function roster() {
  const list = [];
  for (const [id, p] of peers) list.push({ peer: id, profileId: p.profileId, name: p.name });
  return list;
}

function announce() {
  const list = roster();
  for (const [, p] of peers) p.ws.send({ t: 'peers', peers: list });
}

function onJoin(ws, msg) {
  const id = nextPeer++;
  const profileId = Number(msg.profileId) || 0;
  const name = String(msg.name || '').slice(0, 40);
  peers.set(id, { ws, profileId, name });

  ws.send({ t: 'welcome', peer: id });
  announce();
  return id;
}

// ------------------------------------------------------------- positions ---
function snapshot() {
  const now = Date.now();
  const out = {};
  for (const [pid, v] of positions) {
    if (now - v.at > STALE_MS) continue;
    out[pid] = { pos: v.pos, angleZ: v.angleZ, cell: v.cell, name: v.name };
  }
  return out;
}

setInterval(() => {
  if (peers.size === 0) return;
  const snap = snapshot();
  for (const [, p] of peers) p.ws.send({ t: 'pos', at: Date.now(), who: snap });
}, 200);

// --------------------------------------------------------------- choices ---
// What somebody picked in the launcher, waiting for their character to exist.
//
// Character creation used to happen inside the game: the server put sixteen
// books in your pack, your client resolved each one's form id, drew a message
// box, and reported back which one you equipped. Fourteen steps, each able to
// fail without saying anything, and every one of them dependent on the two
// load orders agreeing.
//
// So the choice is made in the launcher, before the game starts, and left here
// for the server to pick up. This service is the only thing both of them can
// reach: the launcher over the internet, the gamemode over loopback.
//
// Kept on disk as well as in memory, because a restart between somebody
// pressing Play and their character spawning would otherwise lose it.
const CHOICES_FILE = path.join(HERE, 'choices.json');
let choices = {};

try {
  choices = JSON.parse(fs.readFileSync(CHOICES_FILE, 'utf8')) || {};
} catch (e) {
  choices = {};
}

function saveChoices() {
  try { fs.writeFileSync(CHOICES_FILE, JSON.stringify(choices, null, 2)); }
  catch (e) { console.log('[voice] could not write choices.json: ' + e.message); }
}

function isLoopback(req) {
  const ra = req.socket.remoteAddress || '';
  return ra === '127.0.0.1' || ra === '::1' || ra === '::ffff:127.0.0.1';
}

function readBody(req, res, limit, then) {
  let body = '';
  req.on('data', (d) => { body += d; if (body.length > limit) req.destroy(); });
  req.on('end', () => {
    let doc;
    try { doc = JSON.parse(body); }
    catch (e) { res.writeHead(400).end('bad json'); return; }
    then(doc);
  });
}

// ------------------------------------------------------------------ http ---
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' };


/*
  Ask the site whether this ticket owns this profile.

  Answers 'yes', 'no', or 'unchecked' when there is nobody to ask. Never throws
  and never hangs: a three second timeout, and anything unexpected counts as
  unchecked rather than as a refusal, because refusing on a hiccup would stop
  somebody creating a character for no reason they could understand.
*/
function owns(ticket, profileId, then) {
  if (!SITE || !ticket) { then('unchecked'); return; }
  let mod;
  try { mod = SITE.startsWith('https:') ? require('https') : require('http'); }
  catch (e) { then('unchecked'); return; }

  const payload = JSON.stringify({ ticket: ticket, profileId: profileId });
  let done = false;
  const finish = (v) => { if (!done) { done = true; then(v); } };

  let req2;
  try {
    req2 = mod.request(SITE + '/api/play/owns', {
      method: 'POST',
      headers: { 'content-type': 'application/json',
                 'content-length': Buffer.byteLength(payload) }
    }, (resp) => {
      let buf = '';
      resp.on('data', (d) => { buf += d; });
      resp.on('end', () => {
        if (resp.statusCode !== 200) { finish('unchecked'); return; }
        let doc;
        try { doc = JSON.parse(buf); } catch (e) { finish('unchecked'); return; }
        finish(doc && doc.ok === true ? 'yes' : 'no');
      });
    });
  } catch (e) { finish('unchecked'); return; }

  req2.setTimeout(3000, () => { try { req2.destroy(); } catch (e) { } finish('unchecked'); });
  req2.on('error', () => finish('unchecked'));
  req2.write(payload);
  req2.end();
}

const server = http.createServer((req, res) => {
  if (req.method === 'POST' && req.url === '/positions') {
    // Loopback only. This is the gamemode talking to the service on the same
    // machine, and nothing outside has any business writing where people are.
    const ra = req.socket.remoteAddress || '';
    if (!(ra === '127.0.0.1' || ra === '::1' || ra === '::ffff:127.0.0.1')) {
      res.writeHead(403).end('no');
      return;
    }
    let body = '';
    req.on('data', (d) => { body += d; if (body.length > 200000) req.destroy(); });
    req.on('end', () => {
      try {
        const doc = JSON.parse(body);
        const now = Date.now();
        const seen = new Set();
        for (const row of (doc.who || [])) {
          const pid = Number(row.profileId);
          if (!pid) continue;
          seen.add(pid);
          positions.set(pid, {
            pos: row.pos, angleZ: Number(row.angleZ) || 0,
            cell: String(row.cell || ''), name: String(row.name || ''), at: now
          });
        }
        for (const pid of Array.from(positions.keys())) if (!seen.has(pid)) positions.delete(pid);
        res.writeHead(204).end();
      } catch (e) {
        res.writeHead(400).end('bad json');
      }
    });
    return;
  }

  // The path, with any query string cut off. This has to happen before the
  // comparisons below: the launcher opens the page as /?profile=2&ptt=... and
  // a plain req.url === '/' test does not match that, so the old code fell
  // through to the file reader, asked the disk for a file named '/', and
  // answered every single person with 'not found'.
  const route = (req.url || '/').split('?')[0];

  // The launcher, from wherever the person is. Deliberately not restricted to
  // loopback: that is the whole point of it.
  if (req.method === 'POST' && route === '/choose') {
    readBody(req, res, 4000, (doc) => {
      const pid = Number(doc.profileId);
      if (!pid) { res.writeHead(400).end('no profileId'); return; }

      owns(String(doc.ticket || ''), pid, (verdict) => {
        if (verdict === 'no') {
          console.log('[voice] REFUSED a choice for profile ' + pid +
                      ': the ticket does not own it');
          res.writeHead(403).end('not your profile');
          return;
        }
        if (verdict === 'unchecked') {
          console.log('[voice] UNVERIFIED choice for profile ' + pid +
                      (SITE ? ' (could not reach ' + SITE + ')' : ' (THORNSWOOD_SITE not set)'));
        }
        // Not validated against a list here on purpose. The gamemode holds the
        // trades and the towns and checks them against the records it actually
        // has; a second copy of that list here could only ever drift from it.
        choices[String(pid)] = {
          // trade is the PROFESSION key, and stays called trade because it is
          // what keys the starter kits and what every older launcher sends.
          trade: String(doc.trade || ''),
          // Which half of it. One key, or two joined by + for the mage's schools.
          half: String(doc.half || ''),
          // Where raw material comes from. Carries no kit of its own.
          cls: String(doc.cls || ''),
          town: String(doc.town || ''),
          name: String(doc.name || ''),
          at: Date.now()
        };
        saveChoices();
        console.log('[voice] choice stored for profile ' + pid +
                    ': ' + choices[String(pid)].trade +
                    (choices[String(pid)].half ? '/' + choices[String(pid)].half : '') +
                    (choices[String(pid)].cls ? ', ' + choices[String(pid)].cls : '') +
                    ' in ' + choices[String(pid)].town);
        res.writeHead(204).end();
      });
    });
    return;
  }

  // The gamemode, on the same machine.
  if (route === '/choices') {
    if (!isLoopback(req)) { res.writeHead(403).end('no'); return; }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify(choices));
    return;
  }

  // Applied, so it should not be applied again next time they connect.
  if (req.method === 'POST' && route === '/claimed') {
    if (!isLoopback(req)) { res.writeHead(403).end('no'); return; }
    readBody(req, res, 1000, (doc) => {
      const pid = String(Number(doc.profileId) || 0);
      if (choices[pid]) {
        delete choices[pid];
        saveChoices();
        console.log('[voice] choice claimed for profile ' + pid);
      }
      res.writeHead(204).end();
    });
    return;
  }

  // The gamemode's end of the command queue. Read and emptied in one go: a
  // command handled twice is a second teleport somebody did not ask for.
  if (req.method === 'GET' && route === '/commands') {
    if (!isLoopback(req)) { res.writeHead(403).end('no'); return; }
    const out = commands.splice(0, commands.length);
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ commands: out }));
    return;
  }

  // And the way back. The gamemode answers a command by writing a line into
  // the chat, either to one person or to the room.
  if (req.method === 'POST' && route === '/say') {
    if (!isLoopback(req)) { res.writeHead(403).end('no'); return; }
    readBody(req, res, 4000, (doc) => {
      const text = String(doc.text == null ? '' : doc.text).slice(0, 400);
      const to = Number(doc.profileId) || 0;
      if (text) {
        const out = {
          t: 'chat',
          from: 0,
          profileId: 0,
          name: String(doc.name || 'Thornswood'),
          text: text,
          at: Date.now()
        };
        for (const [, p] of peers) {
          if (to && Number(p.profileId) !== to) continue;
          p.ws.send(out);
        }
      }
      res.writeHead(204).end();
    });
    return;
  }

  if (route === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, peers: peers.size, tracked: positions.size,
                            waitingChoices: Object.keys(choices).length,
                            queuedCommands: commands.length }));
    return;
  }

  let file = (route === '/' || route === '') ? '/index.html' : route;
  if (file.indexOf('..') !== -1) { res.writeHead(400).end('no'); return; }
  const full = path.join(HERE, 'public', file);
  fs.readFile(full, (err, data) => {
    if (err) { res.writeHead(404).end('not found'); return; }
    res.writeHead(200, { 'content-type': TYPES[path.extname(full)] || 'application/octet-stream' });
    res.end(data);
  });
});

server.on('upgrade', (req, socket, head) => {
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    'Sec-WebSocket-Accept: ' + accept(key) + '\r\n\r\n');

  const ws = new Sock(socket);
  let myId = 0;

  ws.onmessage = (msg) => {
    if (msg.t === 'join') { myId = onJoin(ws, msg); return; }
    if (!myId) return;

    // Signalling is passed through untouched. The server never inspects an
    // offer or a candidate, it only decides who is allowed to hear it.
    if (msg.t === 'sdp' || msg.t === 'ice') {
      const to = peers.get(Number(msg.to));
      if (!to) return;
      to.ws.send(Object.assign({}, msg, { from: myId }));
      return;
    }

    // Text chat rides the socket that is already here.
    //
    // It could have gone through the game server instead, but that would mean
    // a custom packet type in skymp5-client, which is compiled, and this is
    // not. Everyone with the game open already holds this connection for
    // voice, the server already knows who they are and where they stand, and
    // the front is already in the browser: chat is the one piece that was
    // missing, not a reason to build a second channel.
    if (msg.t === 'chat') {
      const me = peers.get(myId);
      const text = String(msg.text == null ? '' : msg.text).slice(0, 400);
      if (!text) return;

      // A line beginning with a slash is for the game server, not for the
      // room, so it is queued rather than broadcast.
      //
      // It goes this way round because the game server cannot see chat: chat
      // rides this socket precisely because adding a packet type to
      // skymp5-client would mean recompiling it. The gamemode already talks to
      // this service over loopback for the launcher's choices, so it collects
      // commands on the same trip.
      //
      // This is also the only teleport there is. SkyMP's client forwards
      // exactly five console commands to the server (additem, equipitem,
      // placeatme, disable, mp) and coc is not one of them, so a coc moves you
      // in your own game and the server puts you straight back.
      if (text.charAt(0) === '/') {
        commands.push({
          profileId: me ? me.profileId : 0,
          name: (me && me.name) || '',
          text: text,
          at: Date.now()
        });
        while (commands.length > 200) commands.shift();
        return;
      }

      const out = {
        t: 'chat',
        from: myId,
        profileId: me ? me.profileId : 0,
        name: (me && me.name) || '',
        text: text,
        at: Date.now()
      };
      for (const [, p] of peers) p.ws.send(out);
      return;
    }
  };

  ws.onclose = () => {
    if (myId) { peers.delete(myId); announce(); }
  };
});

server.listen(PORT, () => {
  console.log('[voice] listening on ' + PORT);
  console.log('[voice] positions accepted from loopback at POST /positions');
});
