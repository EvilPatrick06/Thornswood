'use strict';
/*
  Thornswood proximity voice, server side.

  Runs next to the SkyMP server. Two jobs and nothing else:

    1. Take position snapshots from the gamemode over plain HTTP on loopback,
       and tell each person connected where the people they could hear are.
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
  Where to check that a claim on a profile came from the person who owns it.

  Until 20 September this guarded /choose, the launcher's character creation
  choice, which is gone: creation happens in the game now, on K, and the
  server takes the picks off the command queue below under the profile id the
  join token proves. The check stays for the join itself and for the roster.

  THORNSWOOD_SITE off means no checking, which is how this behaved before and
  is still the behaviour when the site cannot be reached. That is deliberate:
  being unable to create a character is loud and total, and the thing being
  prevented is griefing rather than a breach. Every unverified choice is logged
  so it is visible rather than silent.
*/
const SITE = String(process.env.THORNSWOOD_SITE || '').replace(/\/+$/, '');
const HERE = __dirname;

/*
 * Stamped into /health so that "is the VPS running the copy I just sent it"
 * is one request rather than an afternoon.
 *
 * Node does not reload a file it has already required, so copying this up
 * changes nothing until the scheduled task is restarted, and every symptom of
 * a missed restart looks like a bug somewhere else. Slash commands echoing
 * into the room instead of reaching the game server was exactly that.
 *
 * Bump it whenever anything in this file changes behaviour.
 */
// Bumped whenever what this serves changes, because /health reports it and
// that string is the only way to tell from outside which copy is running. It
// stayed at owners-5 across the chat log going in on 22 September, so the
// health check answered identically before and after and proved nothing.
const BUILD = 'cull-1-command-ack-1-backpressure-1';

// How long a position snapshot stays believable. The gamemode pushes about
// five a second; if they stop, everybody is stale and goes quiet rather than
// hanging in the last place they were heard.
const STALE_MS = 3000;

// ---------------------------------------------------------------- state ----
let positions = new Map();   // profileId -> {pos:[x,y,z], angleZ, cell, name, party, at}
let nextPeer = 1;
const peers = new Map();     // peerId -> {ws, profileId, name}

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


// Chat lines beginning with a slash, waiting for the gamemode to collect them.
// Held in memory on purpose: a command nobody was there to run is not worth
// keeping across a restart.
const commands = [];

/*
  A COMMAND STAYS UNTIL THE GAMEMODE SAYS IT RAN.

  GET /commands used to empty this queue in one splice, before the gamemode
  had read a byte of the answer. Its poll() then parsed the body inside a
  catch that returned, so a batch that failed to parse, or an answer lost to
  its two second timeout, was gone from here and never run by anybody, with
  no word to whoever typed it.

  So a gamemode that asks with ?ack=1 is handed the queue without it being
  emptied, each command carrying an id, and takes away what it ran with
  POST /commands/ack. A plain GET /commands still empties the queue exactly
  as before, because a gamemode from before this change never acknowledges
  anything and would be handed the same commands on every poll.

  The id is a stamp made when this process starts, then a counter, so an id
  from before a restart can never be mistaken for one after it. The gamemode
  remembers the ids it has run and skips one that comes round again, which is
  what stops a lost acknowledgement turning into a second teleport.

  The retry is bounded: a command offered COMMAND_OFFERS times with no
  acknowledgement is given up on and logged here, rather than offered on
  every poll for as long as this process lives.
*/
const COMMANDS_BOOT = crypto.randomBytes(4).toString('hex');
let nextCommand = 1;
const COMMAND_OFFERS = 5;

/*
  AND A FULL QUEUE REFUSES THE NEWEST, AND SAYS SO.

  It used to shift the oldest off the front without a word, so a command that
  had already been taken, and that somebody had every reason to think would
  run, vanished to make room. Refusing the new one is the only way round that
  can tell anybody: the sender is still connected to be told. Two hundred is
  what the cap always was.

  One notice per connection every ten seconds, because the plugins report on
  this queue too, a swing of the axe once or twice a second, and a full queue
  would otherwise answer every one of them with a line in the chat.
*/
const COMMAND_CAP = 200;
const COMMAND_REFUSED_EVERY_MS = 10000;

// What the gamemode is handed. The offer count is this service's business.
function commandOut(c) {
  return { id: c.id, profileId: c.profileId, name: c.name, text: c.text, at: c.at };
}

/* ------------------------------------------------------------- chat log ---
 *
 * What people said, written down, so a report about somebody's behaviour can
 * be answered by reading it rather than by asking both of them and believing
 * whoever is more convincing.
 *
 * WHY IT LIVES HERE. Chat rides this socket, so this is the only process that
 * sees every line. The game server cannot: chat goes this way round precisely
 * because adding a packet type to skymp5-client would mean recompiling it.
 *
 * ONE FILE A DAY, ONE LINE A MESSAGE, APPENDED AND NEVER REWRITTEN. A log
 * that gets rewritten is not evidence, and an append is also the only shape
 * that survives this process being killed mid-write: the worst case is one
 * truncated last line rather than a file nobody can parse. The reader skips a
 * line it cannot read for exactly that reason.
 *
 * THE PROFILE ID COMES OFF THE TOKEN, not off the message. onJoin already
 * does that work and records whether it was proven, and that flag is written
 * with every line: a line from an unproven join is still worth keeping and is
 * not worth hanging anybody on.
 *
 * SLASH COMMANDS ARE KEPT TOO. They are queued for the game server rather
 * than broadcast, so nobody else sees them, but somebody typed them and
 * "what did they run" is the same kind of question as "what did they say".
 */
const CHAT_DIR = process.env.THORNSWOOD_CHAT_DIR || path.join(HERE, 'chat');
const CHAT_DAYS = Number(process.env.THORNSWOOD_CHAT_DAYS || 365);

/* Local time, because every other stamp on this box is local and an evening's
   argument that straddles midnight UTC should not straddle two files. */
function chatDay(at) {
  const d = new Date(at);
  const p = (n) => (n < 10 ? '0' : '') + n;
  return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate());
}

function chatWrite(kind, peerId, me, text) {
  try {
    if (!fs.existsSync(CHAT_DIR)) fs.mkdirSync(CHAT_DIR, { recursive: true });
    const at = Date.now();
    const line = JSON.stringify({
      at: at,
      kind: kind,                                   /* say or command */
      peer: peerId,
      profileId: me ? me.profileId : 0,
      name: (me && me.name) || '',
      proven: !!(me && me.proven),
      mode: (me && me.mode) || '',
      text: text
    });
    fs.appendFileSync(path.join(CHAT_DIR, chatDay(at) + '.jsonl'), line + '\n');
  } catch (e) {
    /* Never let writing the log stop the message going out. Somebody losing
       chat because a disk was full would be a worse fault than a gap here. */
    console.log('[voice] could not write the chat log: ' + (e && e.message));
  }
}

/* Whole days go, never lines out of a day, so a file is either all there or
   not there at all and nobody has to wonder whether it was edited. */
function chatPrune() {
  try {
    if (!fs.existsSync(CHAT_DIR)) return;
    const cutoff = Date.now() - CHAT_DAYS * 86400000;
    for (const f of fs.readdirSync(CHAT_DIR)) {
      const m = /^(\d{4})-(\d{2})-(\d{2})\.jsonl$/.exec(f);
      if (!m) continue;
      const at = new Date(+m[1], +m[2] - 1, +m[3]).getTime();
      if (at < cutoff) { try { fs.unlinkSync(path.join(CHAT_DIR, f)); } catch (e) { } }
    }
  } catch (e) { }
}
setInterval(chatPrune, 6 * 3600000);
chatPrune();

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

/*
  EVERY OPEN SOCKET, SO A QUIET ONE CAN BE KEPT ALIVE.

  Patrick, 23 September, with it on his screen: "Chat lost the server. Trying
  again." over and over while the service was up the whole time and the game
  never noticed anything.

  This service answered pings and never sent one. A websocket that says
  nothing for long enough is closed by whatever is between the two ends, and
  between these two ends is Caddy: the chat page reaches the service through
  wss://thornswood.net/voice/, which is a reverse proxy, and a proxy that
  sees no traffic eventually drops the connection. Voice traffic kept a
  speaking socket busy and the position feed kept a PEER busy, so the ones
  that died were the quiet ones: somebody standing about with the chat window
  open and nobody near them.

  A ping every twenty five seconds is under every default idle timeout worth
  naming, costs two bytes, and is the thing the protocol has for exactly
  this. It also gives a dead socket somewhere to fail, which is better than
  discovering it on the next thing somebody types.
*/
const live = new Set();
// Settable so a harness can watch one arrive without waiting half a minute.
const PING_EVERY = Number(process.env.THORNSWOOD_VOICE_PING_MS) || 25000;

setInterval(() => {
  for (const s of live) {
    try { s.ping(); } catch (e) { }
  }
}, PING_EVERY);

/*
  ONE SLOW CONNECTION MUST NOT GROW THIS PROCESS WITHOUT LIMIT.

  Every message went out through send(), which ignored what socket.write
  returns. When somebody's link cannot keep up, or their machine stops
  reading, node does not refuse a write: it keeps the bytes in memory and
  answers false. Nothing listened, so the position feed piled up behind that
  one socket five times a second. Measured on 24 September with a copy of
  this service on loopback and one websocket that joined and never read, at
  1,500 rows: once the loopback buffers were full the queue grew about
  0.75 MB a second, 15 MB after twenty seconds, and nothing ever gave it back.

  The To Do List entry: "For state that is superseded every tick, dropping is
  the correct answer and is what unreliable transport means." So a socket that
  has said false is marked backed until it drains, and the position tick skips
  it (sendLossy): the next tick carries newer positions anyway. Everything else
  stays on send, because welcome, chat, signalling and voice modes each say
  something that is not said again.

  The roster sits between the two (sendLatest). Every join and every leave
  sends the whole room to everybody, so when a room fills at once, as it does
  when the service restarts and every page reconnects, each socket is sent a
  roster per arrival: about 1.3 MB for the first in at two hundred people.
  Queued in full, that tripped the ceiling below for anybody slow to read,
  and those closed sockets would reconnect into another burst. On
  24 September test-cull.js, whose two hundred sockets join together, had 42
  of them closed that way in one run on a busy machine.

  Only the newest roster means anything, so a backed socket keeps just that
  one and is sent it when it drains, or ahead of the next message it is sent,
  so nothing arrives out of order.

  What is left to grow is that reliable traffic, for a socket that never
  reads. Past QUEUE_CEILING it is closed and left to reconnect, which all
  three pages already do: voice.js after five seconds, the launcher's voice
  host after two, the chat overlay on its own retry. The gamemode's rows come
  out about the size they went in, so the 200,000 byte /positions limit keeps
  one position message under about 200 KB, a fifth of the ceiling, and a
  single tick does not trip it. Since each person is sent only the people
  they could hear (viewsOf), most ticks are far smaller than that. Reaching
  the ceiling takes a couple of thousand chat lines, or hundreds of call
  offers, that nobody has read.
*/
const QUEUE_CEILING = 1024 * 1024;
let droppedPositions = 0;   // ticks not sent to a backed socket, for /health
let skippedRosters = 0;     // rosters replaced by a newer one unsent, for /health
let closedBacklogged = 0;   // sockets closed at the ceiling, for /health

class Sock {
  constructor(socket) {
    this.socket = socket;
    this.buf = Buffer.alloc(0);
    this.onmessage = null;
    this.onclose = null;
    this.closed = false;
    // True from a write that returned false until the socket drains.
    this.backed = false;
    // The newest roster not yet written, while backed. See sendLatest.
    this.latest = null;
    live.add(this);

    socket.on('drain', () => { this.backed = false; this.flushLatest(); });
    socket.on('data', (d) => this.feed(d));
    socket.on('error', () => this.close());
    socket.on('close', () => {
      live.delete(this);
      if (this.closed) return;
      this.closed = true;
      if (this.onclose) this.onclose();
    });
  }

  /* A ping frame: FIN, opcode 9, no body. See the note over `live`. */
  ping() {
    if (this.closed) return;
    try { this.write(Buffer.from([0x89, 0])); } catch (e) { this.close(); }
  }

  /* Where what socket.write says is heard. See the note over QUEUE_CEILING. */
  write(buf) {
    if (this.socket.write(buf) === false) this.backed = true;
    const queued = this.socket.writableLength;
    if (queued > QUEUE_CEILING) {
      closedBacklogged++;
      console.log('[voice] closed a connection whose queue passed ' + QUEUE_CEILING +
                  ' bytes (' + queued + ' waiting). It can reconnect.');
      this.close();
    }
  }

  send(obj) {
    if (this.closed) return;
    // A roster held back while this socket was backed goes out first, so
    // every message still arrives after the roster that was current when it
    // was sent, as it did before rosters were held back.
    this.flushLatest();
    if (this.closed) return;
    try { this.write(frame(JSON.stringify(obj))); } catch (e) { this.close(); }
  }

  /* For the position tick only: skipped while backed, and counted. */
  sendLossy(obj) {
    if (this.backed) { droppedPositions++; return; }
    this.send(obj);
  }

  /*
    For the roster only. Each one is the whole room, so while this socket is
    backed only the newest is worth keeping: it waits here, replacing any
    older one, and goes out when the socket drains or ahead of the next
    message sent to it, whichever comes first. Unlike a position it is never
    dropped, because the next roster only comes when somebody joins or
    leaves. See the note over QUEUE_CEILING.
  */
  sendLatest(obj) {
    if (this.closed) return;
    if (this.backed) {
      if (this.latest) skippedRosters++;
      this.latest = obj;
      return;
    }
    this.send(obj);
  }

  flushLatest() {
    if (!this.latest || this.closed) return;
    const obj = this.latest;
    this.latest = null;
    try { this.write(frame(JSON.stringify(obj))); } catch (e) { this.close(); }
  }

  close() {
    live.delete(this);
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

      /*
        A close is ANSWERED with a close, which RFC 6455 section 5.5.1 asks
        for: "the endpoint MUST send a Close frame in response". This used to
        drop the socket without one, so a well behaved client sat waiting for
        the reply until its own timeout.

        The body of a close frame is a two byte status code, big endian, and
        1000 is a normal closure. Written before the teardown so a write that
        throws cannot leave the socket open.
      */
      if (op === 0x8) {
        try {
          const bye = Buffer.from([0x88, 2, 0x03, 0xe8]);   // FIN+close, len 2, 1000
          this.socket.write(bye);
        } catch (e) { }
        this.close();
        return;
      }
      if (op === 0x9) {                                 // ping -> pong
        try { this.socket.write(Buffer.concat([Buffer.from([0x8a, 0]), Buffer.alloc(0)])); } catch (e) { }
        continue;
      }
      // A pong is the answer to OUR ping. Nothing to do with it: it has
      // already done its job by crossing the proxy in both directions.
      if (op === 0xa) { continue; }
      if (op !== 0x1) continue;                         // only text is used

      let msg = null;
      try { msg = JSON.parse(body.toString('utf8')); } catch (e) { continue; }
      if (msg && this.onmessage) this.onmessage(msg);
    }
  }
}

// ------------------------------------------------------------- signalling --
/*
  How loudly somebody is speaking, as a name rather than a distance.

  It belongs to the speaker and travels with them, because that is how it works
  in a room: you decide whether to whisper, and everyone else just hears the
  result at whatever range your choice carries. The listener's browser is what
  actually applies the falloff, so it has to be told, which is what this relay
  is for. Anything unrecognised becomes local rather than being rejected, so an
  older client that has never heard of modes still sounds normal to everyone.
*/
const MODES = ['whisper', 'local', 'yell'];
function cleanMode(v) {
  const m = String(v == null ? '' : v).toLowerCase();
  return MODES.indexOf(m) === -1 ? 'local' : m;
}

function roster() {
  const list = [];
  for (const [id, p] of peers) {
    list.push({ peer: id, profileId: p.profileId, name: p.name, mode: p.mode || 'local' });
  }
  return list;
}

function announce() {
  const list = roster();
  for (const [, p] of peers) p.ws.sendLatest({ t: 'peers', peers: list });
}

function onJoin(ws, msg) {
  const claimed = Number(msg.profileId) || 0;
  const tok = readToken(msg.token);
  let profileId = 0;
  let why = '';

  if (tok && !tok.expired) {
    // The only line here that decides who somebody is. Note that it reads the
    // token and not the message, even when the two agree.
    profileId = tok.profileId;
    if (claimed && claimed !== profileId) {
      console.log('[voice] join claimed profile ' + claimed + ' with a token for ' +
                  profileId + '. The token wins.');
    }
  } else {
    why = !msg.token ? 'no token' : (tok && tok.expired ? 'an expired token' : 'a token that does not check out');
    if (AUTH === 'on') {
      console.log('[voice] REFUSED a join for profile ' + claimed + ': ' + why);
      ws.send({ t: 'denied', why: why });
      try { ws.close(); } catch (e) { }
      return 0;
    }
    if (AUTH === 'log') {
      console.log('[voice] UNPROVEN join as profile ' + claimed + ': ' + why +
                  '. Allowed because THORNSWOOD_VOICE_AUTH is log.');
    }
    profileId = claimed;
  }

  const id = nextPeer++;
  const name = String(msg.name || '').slice(0, 40);
  peers.set(id, { ws, profileId, name, mode: cleanMode(msg.mode), proven: !!profileId && !why });

  ws.send({ t: 'welcome', peer: id, profileId: profileId });
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

/*
  WHO IS TOLD ABOUT WHOM.

  Every peer used to be sent the whole snapshot five times a second: every
  person's coordinates, facing, cell and name, wherever they were. That is two
  faults in one, and it is entry 282 on the To Do List. Anybody holding a
  socket learned where everybody in the world was standing. And the traffic
  grew with the square of the room, against a box that measured 93 Mbit/s and
  an 8 TB monthly cap. tools/voice/test-cull.js measures it on the wire with
  two hundred people across ten cells: 5,284,000 bytes a tick, 26 MB a
  second, 380 GB over a four hour evening, sent whole; 492,203 bytes a tick,
  2.5 MB a second, culled. Nine of those ten cells are interiors where all
  twenty can hear each other, so that is close to the floor voice needs.

  So each person is told about three kinds of people and nobody else:

    themselves, because every client places everybody against its own row
      and does nothing at all without it;
    anybody in the same cell within HEAR_UNITS, which is everybody any
      speaking mode on any client could reach;
    their own party, wherever they are, because the party strip draws an
      arrow and a distance to every member anywhere in the world off this
      same feed (ts-ui/thornswood-party.js), and gold on it means "somewhere
      else". The gamemode sends the party id with each row for this.

  A missing row is already silence on every client. The overlay
  (ts-ui/thornswood-voice.js), the launcher's voice host and the plain
  browser page all replace their table with each message and set the gain to
  nothing for a person with no row, exactly as for another cell. So no client
  changes, and nobody needs a "you left their range" message: the next view
  simply does not have them in it. Connections are still opened and closed by
  the roster, as they always were.

  NEVER TIGHTER THAN A CLIENT, because that cuts people off mid sentence.
  Another cell is silence on every client, and the longest reach any client
  has is the overlay's yell at 85 metres (thornswood-voice.js MODES).
  HEAR_UNITS is 100 metres, so a yell fading out at its edge is never cut
  before the client's own falloff reaches nothing. Raise this before raising
  a range there: tools/voice/test-cull.js reads the client range tables and
  fails when one outgrows it.
*/
const UNITS_PER_METRE = 70;
const HEAR_UNITS = 100 * UNITS_PER_METRE;

// The same straight line in three dimensions that the clients measure.
function inReach(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b)) return false;
  const dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
  return dx * dx + dy * dy + dz * dz <= HEAR_UNITS * HEAR_UNITS;
}

/*
  Every person's view of one snapshot, as a function of their profile id.

  Grouped by cell first, so distance is only ever worked out between people
  who share one: two hundred people across ten cells is two hundred times
  twenty comparisons a tick, not two hundred times two hundred. Kept per
  profile for the tick, because the same person can be connected twice, the
  chat window and the launcher's voice host, and the answer is the same.
*/
function viewsOf(snap) {
  const byCell = new Map();
  const byParty = new Map();
  for (const pid of Object.keys(snap)) {
    const cell = snap[pid].cell;
    if (!byCell.has(cell)) byCell.set(cell, []);
    byCell.get(cell).push(pid);
    const v = positions.get(Number(pid));
    const party = v ? v.party : '';
    if (!party) continue;
    if (!byParty.has(party)) byParty.set(party, []);
    byParty.get(party).push(pid);
  }
  const made = new Map();
  return function (profileId) {
    const key = String(profileId);
    if (made.has(key)) return made.get(key);
    const out = {};
    const me = snap[key];
    // Nobody with no row of their own is told about anybody: there is
    // nothing to measure a distance from, and no client could use it.
    if (me) {
      out[key] = me;
      for (const pid of byCell.get(me.cell)) {
        if (pid !== key && inReach(me.pos, snap[pid].pos)) out[pid] = snap[pid];
      }
      const v = positions.get(Number(key));
      const party = v ? v.party : '';
      for (const pid of (party && byParty.get(party)) || []) out[pid] = snap[pid];
    }
    made.set(key, out);
    return out;
  };
}

setInterval(() => {
  if (peers.size === 0) return;
  const viewOf = viewsOf(snapshot());
  for (const [, p] of peers) p.ws.sendLossy({ t: 'pos', at: Date.now(), who: viewOf(p.profileId) });
}, 200);

function isLoopback(req) {
  const ra = req.socket.remoteAddress || '';
  return ra === '127.0.0.1' || ra === '::1' || ra === '::ffff:127.0.0.1';
}

/*
  AN OVERSIZED BODY IS ANSWERED, NOT DROPPED.

  This used to call req.destroy() the moment the body went over the limit,
  which closes the connection with no status at all. From the other end that
  is indistinguishable from the service being down, so a client with a body
  one byte too big retries forever against a service that is working fine.
  413 says what happened.
*/
function readBody(req, res, limit, then) {
  let body = '';
  let tooBig = false;
  req.on('data', (d) => {
    if (tooBig) { return; }
    body += d;
    if (body.length > limit) {
      tooBig = true;
      try { res.writeHead(413, { 'content-type': 'text/plain' }).end('too big'); } catch (e) { }
      req.destroy();
    }
  });
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
  Who is allowed to connect at all, and who they are once they have.

  The room used to take a stranger's word for everything. join carried a
  profileId, nothing checked it, and that one number is the whole of somebody's
  identity here: send theirs and you are them. You heard every conversation in
  the world, your voice arrived as them, and because the roster carries
  positions you learned where every person lives. The port was open on every
  interface, so none of this needed the game, an account, or the mod list.

  So identity comes from a token now, and never from the message. The launcher
  proves who it is to /token with the Discord ticket it already holds, the site
  answers whether that ticket owns that profile, and what comes back is signed
  by this service and good for five minutes. join carries the token; the
  profileId in the message is ignored.

  The key is this service's own, made on first run and kept beside it. Not the
  server password: everybody who plays here holds that, which is right for
  reading the character register and useless for telling two of them apart.

  Five minutes because a token is only ever carried from pressing Play to the
  socket opening, and a connection that is already up is not rechecked. It is
  not a session, and nothing renews it.

  THORNSWOOD_VOICE_AUTH says what to do with a connection that cannot prove
  itself:

    on     refuse it
    log    let it in and write down that it could not, which is how to find
           out who would be locked out before locking anybody out
    off    the old behaviour, for working out what is broken

  It ships as log for one release. Read the UNPROVEN lines out of the service
  log, confirm the only ones left are yours, then set it to on. Turning it on
  while an older launcher is still out there takes voice away from whoever is
  running it, and they will not know why.
*/
const AUTH = String(process.env.THORNSWOOD_VOICE_AUTH || 'log').toLowerCase();
/*
  How long a token is good for.

  This was five minutes, on the reasoning that a token is only carried from
  pressing Play to the socket opening. That reasoning was wrong, and the first
  real join proved it: an expired token, from somebody who had just made a
  character. Between minting and joining sits Skyrim loading, the mod list, the
  main menu, character creation and the world loading in. Five minutes does not
  cover a fast session, let alone a new character on a slow disk.

  An hour covers a session's start with room to spare, and the launcher renews
  it on its own tick while the game runs, so a long evening is covered too.

  The shorter window was also buying less than it looked. The token sits in
  voice-token.txt in the game folder for the whole session either way, so
  anybody who can read that file can read it at minute four as easily as at
  minute fifty. What the expiry actually guards against is a token that leaks
  out of that machine being useful forever, and an hour is a perfectly good
  answer to that.
*/
const TOKEN_LIFETIME_MS = Number(process.env.THORNSWOOD_TOKEN_MINUTES || 60) * 60 * 1000;

const TOKEN_KEY_FILE = path.join(HERE, 'token-key.txt');
let TOKEN_KEY = '';
try {
  TOKEN_KEY = String(fs.readFileSync(TOKEN_KEY_FILE, 'utf8')).trim();
} catch (e) {
  TOKEN_KEY = '';
}
if (!TOKEN_KEY) {
  try {
    TOKEN_KEY = crypto.randomBytes(32).toString('hex');
    fs.writeFileSync(TOKEN_KEY_FILE, TOKEN_KEY);
    console.log('[voice] made a signing key for join tokens at ' + TOKEN_KEY_FILE);
  } catch (e) {
    // Without somewhere to keep it, one that lasts as long as this process is
    // still better than none: everybody reconnects on a restart anyway.
    TOKEN_KEY = crypto.randomBytes(32).toString('hex');
    console.log('[voice] could not write ' + TOKEN_KEY_FILE +
                ', using a key that lasts until this service restarts');
  }
}

function signToken(profileId, until) {
  const body = String(profileId) + '.' + String(until);
  const mac = crypto.createHmac('sha256', TOKEN_KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return 'v1.' + body + '.' + mac;
}

/*
  What a token says, or null.

  Checked with timingSafeEqual on equal length buffers rather than ===, so how
  long this takes says nothing about how nearly right a guess was.
*/
function readToken(raw) {
  const s = String(raw == null ? '' : raw);
  const parts = s.split('.');
  if (parts.length !== 4 || parts[0] !== 'v1') return null;
  const profileId = Number(parts[1]) || 0;
  const until = Number(parts[2]) || 0;
  if (profileId <= 0 || until <= 0) return null;
  const want = signToken(profileId, until);
  const a = Buffer.from(want);
  const b = Buffer.from(s);
  if (a.length !== b.length) return null;
  let ok = false;
  try { ok = crypto.timingSafeEqual(a, b); } catch (e) { return null; }
  if (!ok) return null;
  // Expiry last. A token that is genuinely ours but stale is a different thing
  // from one that was made up, and the log should be able to say which.
  if (Date.now() > until) return { profileId: profileId, expired: true };
  return { profileId: profileId, expired: false };
}

/*
  Where everybody's browser should look to find each other.

  Three pages build an RTCPeerConnection and all three had the same Google STUN
  server typed into them. STUN alone only works when both ends can be reached
  once they know where to look. Behind a symmetric NAT, some mobile networks and
  a lot of corporate ones, they cannot, and those two people simply never hear
  each other while everybody else sounds fine. That is the worst shape a fault
  can take: it is not down, it is down for one pair.

  TURN is the answer to that, and TURN needs a server to relay through, which is
  not something that can be typed into a web page. So the list lives here and
  the pages ask for it. Adding TURN later is then a setting on the VPS and a
  restart, rather than editing three files and shipping a release.

  THORNSWOOD_TURN_URL     turn:voice.thornswood.net:3478 or similar
  THORNSWOOD_TURN_SECRET  the static-auth-secret from the TURN server
  THORNSWOOD_TURN_TTL     how long an issued credential lasts, seconds

  With a secret set, each browser is handed its own credential that expires,
  built the way coturn's REST scheme expects: the username is an expiry
  timestamp and the password is an HMAC of it. Nobody gets a standing password
  to a relay, which matters because that relay would carry their bandwidth bill.

  A plain username and password are supported too, for a service that does not
  do the REST scheme, but the ephemeral one is better and is what to prefer.
*/
const TURN_URL = String(process.env.THORNSWOOD_TURN_URL || '').trim();
const TURN_SECRET = String(process.env.THORNSWOOD_TURN_SECRET || '').trim();
const TURN_USER = String(process.env.THORNSWOOD_TURN_USER || '').trim();
const TURN_PASS = String(process.env.THORNSWOOD_TURN_PASS || '').trim();
const TURN_TTL = Number(process.env.THORNSWOOD_TURN_TTL || 3600) || 3600;

// The public STUN that has always been here. Kept as the floor so that a box
// with nothing configured behaves exactly as it does today.
const STUN = [{ urls: 'stun:stun.l.google.com:19302' }];

function iceServers() {
  const list = STUN.slice();
  if (!TURN_URL) return list;
  const urls = TURN_URL.split(',').map((s) => s.trim()).filter(Boolean);
  if (TURN_SECRET) {
    // coturn's use-auth-secret scheme: username is <expiry unix seconds>, and
    // the password is base64 of HMAC-SHA1 over that username.
    const until = Math.floor(Date.now() / 1000) + TURN_TTL;
    const user = String(until);
    const pass = crypto.createHmac('sha1', TURN_SECRET).update(user).digest('base64');
    list.push({ urls: urls, username: user, credential: pass });
  } else if (TURN_USER && TURN_PASS) {
    list.push({ urls: urls, username: TURN_USER, credential: TURN_PASS });
  } else {
    // A relay nobody can authenticate to is worse than none: the browser spends
    // its gathering time on it and gives up. Say so rather than serving it.
    console.log('[voice] THORNSWOOD_TURN_URL is set but no credentials are, so it is being ignored');
    return list;
  }
  return list;
}

/*
  THE CHARACTER REGISTER IS GONE, 23 September.

  It was three routes, /whoami, /claim and /owners, a file called owners.json
  and a shared secret in secret.txt. All three refused every real caller with
  403, because each required doc.password to equal that secret and the launcher
  deliberately sent none: Account.cs and CharSync.cs were written that way and
  were themselves deleted on 20 September. So owners.json was never written by
  any launcher and never read by one, and CharSync.Sync returned null on every
  launch, including the seven second wait it cost at Play.

  The identity that actually flows is the site's linked.json, keyed by Discord
  id. Two registers were never wanted and one of them never worked.

  Taken out rather than left refusing, because a route that answers 403 to
  every real caller is a thing somebody will one day try to fix instead of
  delete. tools\Characters.ps1, which existed only to read /owners, went with
  it; its own header already said the register had not been fed since
  20 September.
*/
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
    let tooBig = false;
    // Answered rather than dropped; see readBody for why.
    req.on('data', (d) => {
      if (tooBig) { return; }
      body += d;
      if (body.length > 200000) {
        tooBig = true;
        try { res.writeHead(413, { 'content-type': 'text/plain' }).end('too big'); } catch (e) { }
        req.destroy();
      }
    });
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
            cell: String(row.cell || ''), name: String(row.name || ''),
            // Kept here and never sent on: it only decides who is told about
            // whom. See WHO IS TOLD ABOUT WHOM.
            party: String(row.party || ''), at: now
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

  /*
    A token to join the room with.

    Answered over the internet, because the launcher asks it from somebody's
    house before the game has started. The ticket is what proves anything; the
    profileId on its own proves nothing, which was the whole problem.
  */
  if (req.method === 'POST' && route === '/token') {
    readBody(req, res, 4000, (doc) => {
      const pid = Number(doc.profileId) || 0;
      if (pid <= 0) { res.writeHead(400).end('no profileId'); return; }
      owns(String(doc.ticket || ''), pid, (verdict) => {
        if (verdict === 'no') {
          console.log('[voice] REFUSED a token for profile ' + pid +
                      ': the ticket does not own it');
          res.writeHead(403).end('not your profile');
          return;
        }
        if (verdict === 'unchecked') {
          // The site is the only thing that can answer this. Minting anyway
          // keeps a site outage from taking voice down with it, and the line
          // below is what says the check did not really happen.
          console.log('[voice] UNCHECKED token for profile ' + pid +
                      (SITE ? ' (could not reach ' + SITE + ')' : ' (THORNSWOOD_SITE not set)'));
        }
        const until = Date.now() + TOKEN_LIFETIME_MS;
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ token: signToken(pid, until), until: until,
                                 profileId: pid, checked: verdict === 'yes' }));
      });
    });
    return;
  }

  // /choose, /choices and /claimed lived here until 20 September: the
  // launcher's creation choice, waiting for the gamemode to collect it. Gone
  // with the launcher's selector; the picks ride the command queue below.

  // The gamemode's end of the command queue. A command handled twice is a
  // second teleport somebody did not ask for, which is why this was read and
  // emptied in one go, and why ?ack=1 needs the gamemode to remember what it
  // ran. See the note over COMMANDS_BOOT.
  if (req.method === 'GET' && route === '/commands') {
    if (!isLoopback(req)) { res.writeHead(403).end('no'); return; }
    let out;
    if (/(^|&)ack=1(&|$)/.test((req.url || '').split('?')[1] || '')) {
      for (let i = commands.length - 1; i >= 0; i--) {
        if (commands[i].offers < COMMAND_OFFERS) continue;
        const c = commands.splice(i, 1)[0];
        // The id and who, not the text: a journal page can be a command.
        console.log('[voice] gave up on command ' + c.id + ' from profile ' + c.profileId +
                    ' after ' + c.offers + ' offers with no acknowledgement');
      }
      for (const c of commands) c.offers++;
      out = commands.map(commandOut);
    } else {
      out = commands.splice(0, commands.length).map(commandOut);
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ commands: out }));
    return;
  }

  // What the gamemode has run, by id, so it is not offered again.
  if (req.method === 'POST' && route === '/commands/ack') {
    if (!isLoopback(req)) { res.writeHead(403).end('no'); return; }
    readBody(req, res, 20000, (doc) => {
      const ids = new Set((doc && Array.isArray(doc.ids) ? doc.ids : []).map(String));
      let removed = 0;
      for (let i = commands.length - 1; i >= 0; i--) {
        if (ids.has(commands[i].id)) { commands.splice(i, 1); removed++; }
      }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ removed: removed }));
    });
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

  /*
    The ICE list, for whichever page is about to build a peer connection.

    Answered to anyone who asks. It carries no secret: with the REST scheme the
    credential is derived and short lived, and it is no use without also being
    able to reach the relay. The pages that ask are the same pages this service
    already serves.
  */
  if (route === '/ice') {
    /*
      AND A PAGE ON A file:// ORIGIN CAN READ IT.

      The in-game page is loaded off disk, so its Origin is the literal string
      null, and a fetch with no Access-Control-Allow-Origin on the answer is
      refused by the browser before the page ever sees the body. It logged
      "Access to fetch at .../voice-dev/ice from origin null has been blocked
      by CORS policy" once a second, on live and on dev alike, and retried
      forever.

      This gives away nothing that was not already public. CORS is a rule about
      what a PAGE may read, not about who may ask: anything that can make an
      HTTP request to this service could already read this route, header or no
      header. What the route hands out is the STUN list plus, when a relay is
      configured, a credential that is derived and short lived under the REST
      scheme. The static credential case is the one to keep an eye on, and it
      is no more exposed by this line than it was by curl.
    */
    res.writeHead(200, { 'content-type': 'application/json',
                         'cache-control': 'no-store',
                         'access-control-allow-origin': '*' });
    res.end(JSON.stringify({ iceServers: iceServers() }));
    return;
  }

  if (route === '/health') {
    /*
      uptime is here so a watchdog can tell a RESTART from a HANG. Everything
      else in this payload looks identical either way: a service that has just
      come back up and a service that has been wedged for an hour both answer
      with the same counts. A number that resets is the only thing that says
      which.
    */
    // How far behind the slowest connections are, so a backlog can be seen
    // from outside rather than only as the process growing.
    let backed = 0, largestQueue = 0;
    for (const s of live) {
      if (s.backed) backed++;
      if (s.socket.writableLength > largestQueue) largestQueue = s.socket.writableLength;
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, build: BUILD, auth: AUTH,
                            uptimeSeconds: Math.round(process.uptime()),
                            startedAt: new Date(Date.now() - process.uptime() * 1000).toISOString(),
                            bind: BIND,
                            turn: TURN_URL ? (TURN_SECRET ? 'ephemeral' : (TURN_USER ? 'static' : 'MISCONFIGURED')) : 'none',
                            peers: peers.size, tracked: positions.size,
                            queuedCommands: commands.length,
                            backed: backed, largestQueueBytes: largestQueue,
                            droppedPositions: droppedPositions,
                            skippedRosters: skippedRosters,
                            closedBacklogged: closedBacklogged }));
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
  // When this connection was last told the command queue is full.
  let refusedAt = 0;

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

    // How loudly this person is speaking. Held on the peer so that the next
    // roster carries it to anybody who joins later, and passed on at once so
    // that a mode change is heard on the very next word rather than on the
    // next time somebody connects.
    if (msg.t === 'vmode') {
      const me = peers.get(myId);
      if (!me) return;
      const mode = cleanMode(msg.mode);
      if (me.mode === mode) return;
      me.mode = mode;
      const out = { t: 'vmode', from: myId, profileId: me.profileId, mode: mode };
      for (const [, p] of peers) p.ws.send(out);
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
      // this service over loopback for the position feed, so it collects
      // commands on the same trip.
      //
      // This is also the only teleport there is. SkyMP's client forwards
      // exactly five console commands to the server (additem, equipitem,
      // placeatme, disable, mp) and coc is not one of them, so a coc moves you
      // in your own game and the server puts you straight back.
      if (text.charAt(0) === '/') {
        chatWrite('command', myId, me, text);
        // Full: the newest is refused and its sender told, and everything
        // already taken stays. See the note over COMMAND_CAP.
        if (commands.length >= COMMAND_CAP) {
          const now = Date.now();
          if (now - refusedAt >= COMMAND_REFUSED_EVERY_MS) {
            refusedAt = now;
            console.log('[voice] the command queue is full at ' + COMMAND_CAP +
                        ', so a command from profile ' + (me ? me.profileId : 0) +
                        ' was refused and they were told');
            ws.send({ t: 'chat', from: 0, profileId: 0, name: 'Thornswood',
                      text: 'The server is not taking commands right now, so that one was not run. ' +
                            'Try again in a minute.',
                      at: now });
          }
          return;
        }
        commands.push({
          id: COMMANDS_BOOT + ':' + (nextCommand++),
          profileId: me ? me.profileId : 0,
          name: (me && me.name) || '',
          text: text,
          at: Date.now(),
          offers: 0
        });
        return;
      }

      /* Written before it is sent, so a line that reached the room is always
         in the log. The other way round loses the last thing somebody said
         before this process went down, which is exactly the line an argument
         turns on. */
      chatWrite('say', myId, me, text);

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

/*
  Which addresses the service answers on.

  It has always been every interface, because the launcher and everybody's
  browser reach it from their own house. That also means the port is open to
  the whole internet, which entry 6 is about.

  Behind Caddy it does not need to be. Caddy already holds 443 for the site, it
  can carry /voice/ through to here, and then this can listen on loopback only:
  one door instead of two, with a certificate on it, and wss:// instead of ws://
  so nobody's voice traffic crosses the internet in the clear.

  It is a setting rather than a rewrite because the two halves cannot land at
  the same instant. Every launcher already out there connects to the raw port.
  Bind this to loopback before those are replaced and none of them can reach it,
  and no server side change brings them back, because the address they try is
  compiled into the copy on their machine. So: ship the clients that can use
  wss first, let them go out, then set this.

  THORNSWOOD_VOICE_BIND=127.0.0.1 is the whole switch, and unsetting it is the
  whole rollback.
*/
const BIND = String(process.env.THORNSWOOD_VOICE_BIND || '0.0.0.0').trim() || '0.0.0.0';

server.listen(PORT, BIND, () => {
  console.log('[voice] listening on ' + BIND + ':' + PORT +
              (BIND === '127.0.0.1' ? ' (loopback only, so something must be proxying to it)' : ''));
  console.log('[voice] positions accepted from loopback at POST /positions');
});
