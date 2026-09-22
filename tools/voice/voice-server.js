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
const BUILD = 'chat-1';

// How long a position snapshot stays believable. The gamemode pushes about
// five a second; if they stop, everybody is stale and goes quiet rather than
// hanging in the last place they were heard.
const STALE_MS = 3000;

// ---------------------------------------------------------------- state ----
let positions = new Map();   // profileId -> {pos:[x,y,z], angleZ, cell, name, at}
let nextPeer = 1;
const peers = new Map();     // peerId -> {ws, profileId, name}

/*
  Who owns which characters.

  A character under SkyMP is a change form the game server holds, keyed by a
  profile id, and the id used to exist in exactly one place: a fifty byte
  profiles.txt on the machine that made it. Reinstall, or move to another
  computer, and that file is gone. The launcher rolls a fresh random id, the
  server has never seen it, and creation runs from the top while the real
  character sits up here forever with nothing left that knows its number.

  Nothing about the character needs to move. It is already on the server. What
  was missing is a way to prove who you are, so this is that: Steam account to
  profile ids, written by the launcher every time somebody plays and read back
  when their profiles.txt is missing.

  Rebuilt by use rather than guarded. Every launch re-registers, so if this file
  is ever lost each person restores their own entry the next time they play.

  The shared secret is the game server's own password, out of version.json in
  a private repo. So it is not public, but it is not a purpose made secret
  either: everyone who plays here holds it, because holding it is what playing
  here means.

  That is the right bar for what this guards. A Steam id is close to public,
  so without a second thing to know, anyone could ask the server which profile
  ids belong to a friend and then connect as them. With it, reading the
  register is exactly as hard as being allowed on the server at all, and no
  harder. It is not protection from the people already here.
*/
const OWNERS_FILE = path.join(HERE, 'owners.json');
let owners = {};
try {
  owners = JSON.parse(fs.readFileSync(OWNERS_FILE, 'utf8')) || {};
} catch (e) {
  owners = {};
}

/* The password, if the installer left one next to us. Without it every account
   route is switched off rather than left open. */
let SECRET = '';
try {
  SECRET = String(fs.readFileSync(path.join(HERE, 'secret.txt'), 'utf8')).trim();
} catch (e) {
  SECRET = '';
}

let ownersDirty = false;
function saveOwners() {
  if (!ownersDirty) return;
  ownersDirty = false;
  const tmp = OWNERS_FILE + '.tmp';
  try {
    // Written beside and renamed over, never truncated in place. A power cut
    // halfway through a plain write leaves an empty file, and an empty file
    // here means everybody is a stranger.
    fs.writeFileSync(tmp, JSON.stringify(owners, null, 2));
    fs.renameSync(tmp, OWNERS_FILE);
  } catch (e) { }
}
setInterval(saveOwners, 4000);

function steamOf(v) {
  const s = String(v == null ? '' : v).trim();
  return /^[0-9]{5,20}$/.test(s) ? s : '';
}

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
  for (const [, p] of peers) p.ws.send({ t: 'peers', peers: list });
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

setInterval(() => {
  if (peers.size === 0) return;
  const snap = snapshot();
  for (const [, p] of peers) p.ws.send({ t: 'pos', at: Date.now(), who: snap });
}, 200);

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

  /*
    Which characters belong to this Steam account.

    Answered over the internet rather than loopback, because the launcher asks
    it from somebody's house before the game has started.
  */
  if (req.method === 'POST' && route === '/whoami') {
    readBody(req, res, 2000, (doc) => {
      if (!SECRET || String(doc.password || '') !== SECRET) {
        res.writeHead(403).end('no');
        return;
      }
      const steam = steamOf(doc.steamId);
      if (!steam) { res.writeHead(400).end('no steam id'); return; }
      const rec = owners[steam];
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ steamId: steam, profiles: (rec && rec.profiles) || [] }));
    });
    return;
  }

  /*
    This Steam account owns these profile ids.

    Sent on every launch, so the record follows a character that was made
    before any of this existed: nothing about the id changes, it just stops
    being a secret held only by one hard drive.
  */
  if (req.method === 'POST' && route === '/claim') {
    readBody(req, res, 4000, (doc) => {
      if (!SECRET || String(doc.password || '') !== SECRET) {
        res.writeHead(403).end('no');
        return;
      }
      const steam = steamOf(doc.steamId);
      if (!steam) { res.writeHead(400).end('no steam id'); return; }

      const list = Array.isArray(doc.profiles) ? doc.profiles : [];
      const clean = [];
      for (const p of list.slice(0, 12)) {
        const slot = Number(p.slot) || 0;
        const profileId = Number(p.profileId) || 0;
        if (slot <= 0 || profileId <= 0) continue;
        clean.push({
          slot: slot,
          profileId: profileId,
          name: String(p.name || '').slice(0, 40),
          played: Number(p.played) || 0,
          // The launcher's own notes about the character. The game server has
          // none of this: it knows a change form, not that the person playing
          // it calls themselves a bard from Winterhold with two hours in.
          seconds: Number(p.seconds) || 0,
          trade: String(p.trade || '').slice(0, 24),
          town: String(p.town || '').slice(0, 24)
        });
      }
      if (!clean.length) { res.writeHead(400).end('nothing to claim'); return; }

      /*
        Current list replaced, history only ever added to.

        The list is what a fresh install gets handed back, so it has to be
        whatever the machine in front of the person actually has. History is
        the safety net under that: if somebody reinstalls, makes a character
        before this has had a chance to hand theirs back, and then claims the
        new id, the old one is still written down here rather than gone. A
        character nobody can name is a character nobody can recover.
      */
      const was = owners[steam] || {};
      const seen = Array.isArray(was.seen) ? was.seen.slice(0, 200) : [];
      for (const p of clean) {
        if (seen.indexOf(p.profileId) === -1) { seen.push(p.profileId); }
      }

      owners[steam] = { profiles: clean, seen: seen, at: Date.now() };
      ownersDirty = true;
      res.writeHead(204).end();
    });
    return;
  }

  /* The whole book, for the admin script. Same secret, and a POST so the
     password never lands in a URL or a log line. */
  if (req.method === 'POST' && route === '/owners') {
    readBody(req, res, 2000, (doc) => {
      if (!SECRET || String(doc.password || '') !== SECRET) {
        res.writeHead(403).end('no');
        return;
      }
      if (doc.forget) {
        const steam = steamOf(doc.forget);
        if (steam && owners[steam]) {
          delete owners[steam];
          ownersDirty = true;
          saveOwners();
        }
      }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ owners: owners }));
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
    res.writeHead(200, { 'content-type': 'application/json',
                         'cache-control': 'no-store' });
    res.end(JSON.stringify({ iceServers: iceServers() }));
    return;
  }

  if (route === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, build: BUILD, auth: AUTH,
                            bind: BIND,
                            turn: TURN_URL ? (TURN_SECRET ? 'ephemeral' : (TURN_USER ? 'static' : 'MISCONFIGURED')) : 'none',
                            peers: peers.size, tracked: positions.size,
                            queuedCommands: commands.length,
                            accounts: Object.keys(owners).length,
                            secret: SECRET ? 'set' : 'MISSING' }));
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
        commands.push({
          profileId: me ? me.profileId : 0,
          name: (me && me.name) || '',
          text: text,
          at: Date.now()
        });
        while (commands.length > 200) commands.shift();
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
