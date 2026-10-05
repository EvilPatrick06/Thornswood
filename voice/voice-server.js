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
const net = require('net');
const fs = require('fs');
const path = require('path');
const headlines = require('./headlines');

const PORT = Number(process.env.THORNSWOOD_VOICE_PORT || 7778);
/*
  Where to check that a claim on a profile came from the person who owns it.

  Until 20 September this guarded /choose, the launcher's character creation
  choice, which is gone: creation happens in the game now, on K, and the
  server takes the picks off the command queue below under the profile id the
  join token proves. The check stays for the join itself and for the roster.

  Without THORNSWOOD_SITE, or while the site cannot be reached, nobody can
  say whose a profile is, so /token mints nothing (#1315). It used to mint
  anyway and log the token as unchecked, which meant any ticket at all, or
  none, got a token during a site outage or on a box with the setting left
  off.
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
const BUILD = 'cull-1-command-ack-1-chat-limit-1-chat-local-1-turn-key-1-backpressure-1-keepalive-2-moved-1-deploy-1-line-close-1-head-1-hush-1-auth-on-1-owns-limit-1-masked-1-relay-shapes-1-origin-1-doors-1-ice-relay-1-proxied-1-token-once-1';

// ==== thornswood deploy record ====
// Which commit this copy came from (#459): Install-Voice.ps1 leaves the deploy
// artifact's record beside this file as thornswood-deploy.json once the files
// are in place, and /health hands back its commit, zip and hash. null when no
// deploy has written one, which is every copy sent before the artifacts.
function deployRecord(dir) {
  try {
    const r = JSON.parse(fs.readFileSync(path.join(dir, 'thornswood-deploy.json'), 'utf8').replace(/^﻿/, ''));
    return { name: String(r.name || ''), commit: String(r.commit || ''), edited: r.edited === true,
             sha256: String(r.sha256 || ''), deployedUtc: String(r.deployedUtc || '') };
  } catch (e) { return null; }
}
// ==== end thornswood deploy record ====

// How long a position snapshot stays believable. The gamemode pushes about
// five a second; if they stop, everybody is stale and goes quiet rather than
// hanging in the last place they were heard.
const STALE_MS = 3000;

// ---------------------------------------------------------------- state ----
let positions = new Map();   // profileId -> {pos:[x,y,z], angleZ, cell, name, party, at}
let nextPeer = 1;
const peers = new Map();     // peerId -> {ws, profileId, name}

/*
  The name a line or the roster shows (#410): for a proven connection, the
  character name the game server has for that profile (the /positions feed),
  so nobody chooses the name their words go out under; the name the page sent
  only while the game server has none (the menu), or for a connection that is
  not proven, whose profile is a claim anyway.
*/
function peerName(p) {
  if (p && p.proven) {
    const at = positions.get(p.profileId);
    if (at && at.name) return String(at.name).slice(0, 40);
  }
  return (p && p.name) || '';
}

/*
  Ask the site whether this ticket owns this profile.

  Answers 'yes', 'no', or 'unchecked' when there is nobody to ask or no
  answer came. Never throws and never hangs: a three second timeout. Only
  'yes' gets a token (#1315); 'unchecked' is not a refusal, so /token says
  the question went unanswered rather than that the profile is not theirs.

  AND THE ANSWER IS READ TO A LIMIT, IN SIZE AND IN TIME (#1352). The site
  answers about thirty bytes ({"ok":true,"why":"theirs"}), and its own limit
  on the question is 8 KB. This used to add every byte that came back to one
  string. Measured on 5 October: a site answering 400 MB took this service
  from 47 MB to 534 MB, and one answering more than about 512 MB stopped it
  outright (RangeError: Invalid string length), the longest string node
  holds. And the three seconds were req2.setTimeout, which counts only time
  with nothing arriving, so a site sending a byte a second held /token open
  for as long as it kept sending. So reading stops past OWNS_REPLY_MAX, and
  the whole exchange has OWNS_WAIT_MS from the moment it is asked; either is
  unchecked, like anything else unexpected here.
*/
const OWNS_REPLY_MAX = 64 * 1024;
const OWNS_WAIT_MS = 3000;
function owns(ticket, profileId, then) {
  if (!SITE || !ticket) { then('unchecked'); return; }
  let mod;
  try { mod = SITE.startsWith('https:') ? require('https') : require('http'); }
  catch (e) { then('unchecked'); return; }

  const payload = JSON.stringify({ ticket: ticket, profileId: profileId });
  let done = false;
  let late = null;
  const finish = (v) => { if (!done) { done = true; clearTimeout(late); then(v); } };

  let req2;
  try {
    req2 = mod.request(SITE + '/api/play/owns', {
      method: 'POST',
      headers: { 'content-type': 'application/json',
                 'content-length': Buffer.byteLength(payload) }
    }, (resp) => {
      let buf = '';
      let size = 0;
      resp.on('data', (d) => {
        if (done) return;
        size += d.length;
        if (size > OWNS_REPLY_MAX) {
          console.log('[voice] the site\'s answer to the ownership check passed ' + OWNS_REPLY_MAX +
                      ' bytes, so the rest was not read');
          try { req2.destroy(); } catch (e) { }
          finish('unchecked');
          return;
        }
        buf += d;
      });
      resp.on('end', () => {
        if (resp.statusCode !== 200) { finish('unchecked'); return; }
        let doc;
        try { doc = JSON.parse(buf); } catch (e) { finish('unchecked'); return; }
        finish(doc && doc.ok === true ? 'yes' : 'no');
      });
    });
  } catch (e) { finish('unchecked'); return; }

  late = setTimeout(() => { try { req2.destroy(); } catch (e) { } finish('unchecked'); }, OWNS_WAIT_MS);
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
// proven says this connection's join token checked out, which the gamemode's
// staff commands require (#412).
function commandOut(c) {
  return { id: c.id, profileId: c.profileId, name: c.name, text: c.text, at: c.at, proven: c.proven === true,
           relay: c.relay === true };
}

/*
  A PLACE IN LINE GOES WITH THE CONNECTION THAT ASKED FOR IT (#481).

  Patrick, 29 Sep: "they shouldn't need to check in while waiting in the
  queue ... just have it automatically lose a player's spot when they
  disconnect." The character choice at the menu waits in line over this
  socket: its "/line" marks the connection as waiting ("/afk out" too, since
  a game moved out for being idle waits from that moment), and "/line leave"
  unmarks it. When a waiting connection closes and no other connection of the
  same profile is waiting, the game server is told at once, as "/line gone"
  under that profile with relay set, which no person can send: the gamemode
  takes "/line gone" only with that mark. A restart of this service tells
  nobody anything, because the sockets die with it; the gamemode sees the new
  boot stamp on GET /commands instead and gives every waiting menu a minute to
  ask again.
*/
function lineMark(me, text) {
  if (!me) return;
  if (/^\/line\s*$/i.test(text) || /^\/afk\s+out\b/i.test(text)) me.inLine = true;
  else if (/^\/line\s+leave\b/i.test(text)) me.inLine = false;
}
function lineClosed(me) {
  if (!me || !me.inLine || !me.profileId) return false;
  for (const [, p] of peers) {
    if (p !== me && p.profileId === me.profileId && p.inLine) return false;
  }
  commands.push({
    id: COMMANDS_BOOT + ':' + (nextCommand++),
    profileId: me.profileId,
    name: me.name || '',
    text: '/line gone',
    at: Date.now(),
    offers: 0,
    proven: !!me.proven,
    relay: true
  });
  console.log('[voice] profile ' + me.profileId + ' was waiting in line and its connection closed; the game server is told');
  return true;
}

/*
  Who staff have silenced, profile -> until (ms), set whole by the gamemode's
  /silence over loopback (POST /silenced, #412). Their plain lines, /me, /do,
  /w and /s reach nobody until then; their slash commands still go to the game
  server, which refuses /ooc and /roll from them itself. The same list closes
  the microphone: every connection is told {t:'hush'}, and the position row
  carries hush so a client that joins later still hears nothing. Kept in this
  process only: the gamemode sends the whole list again every thirty seconds.
*/
const silenced = new Map();
/* Personal text mutes: listener profile -> set of speaker profiles. The
   whole map arrives from the gamemode (POST /textmute). A listener who has
   turned somebody's text off does not get that person's lines. */
const textOff = new Map();

function textBlocked(listener, speaker) {
  const set = textOff.get(Number(listener) || 0);
  return !!(speaker && set && set.has(Number(speaker)));
}
const SILENCED_TOLD_EVERY_MS = 10000;
function silencedLeft(profileId, now) {
  const pid = Number(profileId) || 0;
  const until = silenced.get(pid);
  if (!until || now >= until) return 0;
  return until - now;
}

/* Staff silence is a moderation tool, so every connection is told, including
   people who are not in earshot: a connection opened earlier still carries
   sound until the microphone is closed and the listener's level is nothing. */
function tellHush(profileId, on) {
  const msg = { t: 'hush', profileId: Number(profileId) || 0, on: !!on };
  if (!msg.profileId) return;
  for (const [, p] of peers) {
    try { p.ws.send(msg); } catch (e) { }
  }
}

function sweepSilenced(now) {
  for (const [pid, until] of Array.from(silenced.entries())) {
    if (now >= until) {
      silenced.delete(pid);
      tellHush(pid, false);
    }
  }
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
      name: peerName(me),
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

/* ------------------------------------------------------ who hears a line ---
 *
 * Entry 150 on the To Do List: "Two people robbing a traveller on the
 * Whiterun road are currently read by a smith in Markarth." Every plain line
 * went to every socket on the server, and /ooc, the one line that is meant to
 * step out of the scene, was the only one kept to the people near it.
 *
 * THORNSWOOD_CHAT_RANGE decides who a PLAIN line in the box reaches:
 *
 *   unset, off, 0   a plain line goes to every socket. Install-Voice.ps1
 *                   installs live and dev with on since 4 Oct (Patrick:
 *                   local chat should have gone to live with the rest), so
 *                   this is only a service started by hand without it.
 *   on              the same cell and 4000 units
 *   a number        the same cell and that many units
 *
 * Anything that is not on or a positive number counts as off, so a typo
 * leaves a plain line reaching everybody rather than silencing the room.
 * /health says which it is.
 *
 * /me, /do, /w, /s and /ooc are local either way. They are not queued for
 * the game server. The line above the head uses those same distances even
 * while a plain line in the box still goes to everybody. Other slashes,
 * including /roll, are still queued.
 */
function chatRangeOf(v) {
  const s = String(v == null ? '' : v).trim().toLowerCase();
  if (s === 'on') return 4000;
  const n = Number(s);
  return (s && isFinite(n) && n > 0) ? n : 0;
}
const CHAT_RANGE = chatRangeOf(process.env.THORNSWOOD_CHAT_RANGE);

/*
 * /me and /do are how an attempt gets said as an attempt: "/me swings at
 * the guard" leaves whether it lands to the other person, which a plain
 * line cannot. Whisper and shout are their own distances in headlines.js
 * (1000 and 12000). chatReach below is only the box while the range is on,
 * and it is a quarter and three times that range, near the voice modes
 * (7, 30 and 85 metres in thornswood-voice.js). The head does not use it.
 */
const CHAT_VERBS = {
  '/me': 'me', '/do': 'do',
  '/whisper': 'whisper', '/w': 'whisper',
  '/shout': 'shout', '/s': 'shout', '/yell': 'shout', '/y': 'shout'
};
const CHAT_USAGE = {
  me: 'Say /me and then what your character does, like /me draws a sword.',
  do: 'Say /do and then what there is to see, like /do The door is barred.',
  whisper: 'Say /w and then what you whisper.',
  shout: 'Say /s and then what you shout.'
};

/* The verb a line starts with and the rest of it, or null for a plain line
   and for every other slash, which still goes to the game server. */
function chatVerb(text) {
  const m = /^(\/[a-z]+)(?:\s+([\s\S]*))?$/i.exec(String(text == null ? '' : text));
  if (!m) return null;
  const kind = CHAT_VERBS[m[1].toLowerCase()];
  if (!kind) return null;
  return { kind: kind, text: String(m[2] || '').trim() };
}

function chatReach(kind) {
  if (kind === 'whisper') return CHAT_RANGE / 4;
  if (kind === 'shout') return CHAT_RANGE * 3;
  return CHAT_RANGE;
}

/*
 * Who a line reaches: { to, placed }, or null for everybody.
 *
 * Measured the way /ooc measures in gamemode.js: the same cell first, because
 * two people at the same coordinates either side of a loading door are not in
 * earshot, then a straight line. The positions are the ones the gamemode
 * posts here five times a second, and one older than STALE_MS does not count,
 * the same rule voice goes quiet by.
 *
 * Two cases nobody has decided yet, so each takes the side that loses least:
 *
 *   NO FRESH POSITION FOR ANYBODY, which is the gamemode's feed stopped or not
 *   installed. Range cannot be judged for anyone, and taking chat off the
 *   whole server because of a fault somewhere else is worse than an hour of
 *   the old global chat, so it is everybody, as before.
 *
 *   THE SENDER HAS NONE while other people do: at the menu, loading, between
 *   worlds. The line goes back to them alone, and placed says so, rather than
 *   to the whole server, which is the thing this exists to stop.
 *
 * The sender's own socket always gets the line, because the chat page only
 * shows what comes back from here.
 */
function hearers(myId, me, reach) {
  const now = Date.now();
  const fresh = (pid) => {
    const v = positions.get(Number(pid) || 0);
    return (v && now - v.at <= STALE_MS && Array.isArray(v.pos)) ? v : null;
  };
  let any = false;
  for (const [, v] of positions) { if (now - v.at <= STALE_MS) { any = true; break; } }
  if (!any) return null;

  const mine = me ? fresh(me.profileId) : null;
  const to = [];
  for (const [id, p] of peers) {
    if (id === myId) { to.push(p); continue; }
    if (!mine) continue;
    const them = fresh(p.profileId);
    if (!them || them.cell !== mine.cell) continue;
    const dx = (Number(them.pos[0]) || 0) - (Number(mine.pos[0]) || 0);
    const dy = (Number(them.pos[1]) || 0) - (Number(mine.pos[1]) || 0);
    const dz = (Number(them.pos[2]) || 0) - (Number(mine.pos[2]) || 0);
    if (dx * dx + dy * dy + dz * dz > reach * reach) continue;
    to.push(p);
  }
  return { to: to, placed: !!mine };
}

/* ----------------------------------------------------------- chat limit ---
 *
 * HOW FAST ONE CONNECTION CAN TALK TO THE ROOM. The To Do List, entry 149:
 * "Chat is server-wide, unfiltered, has no rate limit anywhere". Every plain
 * line went to every peer the moment it arrived, and the only limit was the
 * 400 character cap, so one open console could fill every screen in the
 * world faster than anybody could read it, let alone answer it.
 *
 * A TOKEN BUCKET ON THE PEER RECORD. Five lines at once, then one more every
 * second and a half, which is forty a minute: more than anybody types, and
 * the five cover a quick back and forth. It lives on the peer that onJoin
 * writes rather than in the broadcast, because the broadcast is the part
 * that changes when chat goes local, and a limit written into it would go
 * with it.
 *
 * SAID LINES ONLY. The handler asks after the slash branch, never before.
 * The plugins report gameplay down this same socket as slash lines: /chopped
 * on every fall of the axe, /place as somebody walks about, /ate, /burn, the
 * journal, the party and the trade window. A limit ahead of that branch
 * would lose somebody's firewood for talking too much.
 *
 * DROPPED, AND THE SENDER IS TOLD ONCE. A held line is not queued, because a
 * flood that is queued is still a flood, only later. The notice goes to the
 * sender alone, the first time a line of theirs is dropped, and not again
 * until one of their lines has gone through, so the notice cannot become a
 * flood of its own. A dropped line is not in the chat log as said, because
 * it never reached the room; the service log says who was slowed.
 *
 * PER CONNECTION, NOT PER ACCOUNT. This was on purpose while
 * THORNSWOOD_VOICE_AUTH could be log, when the profile id on a join was
 * whatever the message claimed and a bucket keyed on it would have let
 * anybody empty somebody else's; since #1303 every join is proven.
 * A reconnect starts with a full bucket; it costs a join and a roster to
 * everybody, so it slows a flood rather than stopping a determined one.
 *
 * Both numbers are settable so they can be tuned on the box without a
 * release.
 */
const CHAT_BURST = Number(process.env.THORNSWOOD_CHAT_BURST) || 5;
const CHAT_REFILL_MS = Number(process.env.THORNSWOOD_CHAT_REFILL_MS) || 1500;
const CHAT_SLOW = 'Slow down: lines sent this quickly are not going out. ' +
                  'Wait a few seconds, then say it again.';

/* Whether this peer's line may go to the room. Tells them the first time it
   may not. A record without a bucket starts full rather than silenced, and a
   clock that steps backwards refills nothing rather than locking anybody
   out. */
function chatAllow(me, peerId, now) {
  if (!me) return true;
  if (typeof me.chatTokens !== 'number') { me.chatTokens = CHAT_BURST; me.chatAt = now; }
  const since = Math.max(0, now - me.chatAt);
  me.chatTokens = Math.min(CHAT_BURST, me.chatTokens + since / CHAT_REFILL_MS);
  me.chatAt = now;
  if (me.chatTokens >= 1) {
    me.chatTokens -= 1;
    me.chatSlowed = false;
    return true;
  }
  if (!me.chatSlowed) {
    me.chatSlowed = true;
    console.log('[voice] slowed peer ' + peerId + ' (profile ' + me.profileId + ', ' +
                (me.name || 'no name') + '): more than ' + CHAT_BURST +
                ' lines at once, or more than one every ' + CHAT_REFILL_MS + 'ms');
    me.ws.send({ t: 'chat', from: 0, profileId: 0, name: 'Thornswood', text: CHAT_SLOW, at: now });
  }
  return false;
}

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

/*
  AND A SOCKET THAT ANSWERS NOTHING IS LET GO. Issue #519.

  The ping kept whatever sits in between from closing a quiet socket, and did
  nothing about a socket whose other end had gone. A browser answers every
  ping with a pong without being asked, so anything still there says
  something at least once a ping. A laptop that sleeps, or a Wi-Fi link that
  drops, says nothing at all, and its socket sat in the room as a peer until
  TCP gave up on it, which can be many minutes: everybody near that person
  kept a connection open to nobody. Measured on 21 September, the launcher's
  own log: the machine slept at 19:39 and woke at 20:06 with its socket long
  dead at this end.

  Three pings unanswered is gone. The Caddyfile in scripts\deploy sets no
  stream_timeout and Caddy has none by default, so what closes a quiet socket
  is a router or a mobile network, and those wait longer than the twenty five
  seconds between pings.
*/
const SILENT_AFTER = Number(process.env.THORNSWOOD_VOICE_SILENT_MS) || PING_EVERY * 3;
let closedSilent = 0;         // sockets closed for answering nothing, for /health

setInterval(() => {
  const now = Date.now();
  for (const s of live) {
    if (now - s.heard > SILENT_AFTER) {
      closedSilent++;
      console.log('[voice] closed a connection that answered nothing for ' +
                  Math.round((now - s.heard) / 1000) + ' s. It can reconnect.');
      s.close();
      continue;
    }
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
    // When the log last said this one is behind. See sendLossy.
    this.saidBehind = 0;
    // When anything last arrived from the other end: a pong, a message, a
    // ping of its own. See SILENT_AFTER.
    this.heard = Date.now();
    live.add(this);

    socket.on('drain', () => { this.backed = false; this.flushLatest(); });
    socket.on('data', (d) => { this.heard = Date.now(); this.feed(d); });
    /*
      The other end has shut its side without a close frame: a process
      killed, a tab gone, a raw socket ended. The HTTP server hands the
      socket over half open, so nothing here closed it, and it stayed a peer
      until the next write to it failed. That write was the position tick
      five times a second; for a socket sent nothing, it is the next ping.
    */
    socket.on('end', () => this.close());
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

  /* For the position tick only: skipped while backed, and counted. Says
     whether it went, because the tick sends only what changed and has to
     start again from the whole view after one that did not. */
  sendLossy(obj) {
    if (this.backed) {
      droppedPositions++;
      /*
        Said in the log, once a minute at most per connection, so a person
        whose voice goes stale can be matched to a line here (issue #483).
        The ceiling says it again if it closes one.
      */
      const now = Date.now();
      if (now - this.saidBehind > 60000) {
        this.saidBehind = now;
        console.log('[voice] a connection is behind (' + this.socket.writableLength +
                    ' bytes waiting), so its position updates are skipped until it catches up');
      }
      return false;
    }
    this.send(obj);
    return true;
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
      /*
        And stops the moment the socket is closed, whatever is left. The
        ceiling closes a socket from inside write, so a message that comes
        back to its own sender (their chat line, an offer addressed to
        themselves, a notice) can close it partway through this loop. The
        frames after that belong to somebody onclose has already taken out
        of the room: they used to be handled anyway, and chat from them went
        past the chat limit to the room and the log as profile 0 with no
        name. voice/test-backpressure.js sends exactly that.
      */
      if (this.closed) return;
      if (this.buf.length < 2) return;
      const b0 = this.buf[0], b1 = this.buf[1];
      const op = b0 & 0x0f;
      const masked = (b1 & 0x80) !== 0;
      /*
        A frame from the client that is not masked ends the connection
        (#1351). RFC 6455 section 5.1: "The server MUST close the connection
        upon receiving a frame that is not masked", and it may say why with
        1002, a protocol error. This used to read such a frame as it was.
        Every browser masks every frame, and so do the harnesses that write
        their own (voice/test-backpressure.js, voice/test-keepalive.js), so
        nothing that talks to this service sends one.
      */
      if (!masked) {
        try { this.socket.write(Buffer.from([0x88, 2, 0x03, 0xea])); } catch (e) { }   // FIN+close, len 2, 1002
        this.close();
        return;
      }
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
      /*
        A ping is answered with a pong, but not while this socket is backed.

        The pong used to be written straight to the socket, past write and
        so past the ceiling, and each one is a separate two byte write that
        node holds as its own queued request. On 24 September a socket that
        never read sent 9 MB of pings in one go: 1.4 million pongs queued,
        2.8 MB by writableLength, and the service went from 50 MB to 447 MB
        before the next position tick reached the ceiling and closed it.

        RFC 6455 section 5.5.3 allows answering only the most recent of
        several pings, and a socket that is backed is not reading its pongs
        anyway, so while it is backed they are not written. Through write,
        the first one the kernel refuses marks it backed, which caps what a
        flood of pings can queue at one buffer's worth.
      */
      if (op === 0x9) {
        if (!this.backed) {
          try { this.write(Buffer.from([0x8a, 0])); } catch (e) { this.close(); }
        }
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

/*
  WHAT A PAGE'S SIGNALLING MAY CARRY TO ANOTHER PAGE (#1350).

  It used to be passed on as it came, with only from set here, so any field
  a page added reached the other page, and an sdp message with no
  description reached the handlers in thornswood-voice.js, voice-host.html
  and voice.js, which read m.sdp.type and threw. Every page sends
  { t: 'sdp', to, sdp: pc.localDescription } and
  { t: 'ice', to, candidate: e.candidate }, which arrive as an offer or answer
  ({ type, sdp }) and as RTCIceCandidate's own fields, and every page reads
  only from, sdp and candidate. So that is what goes on, rebuilt here, and a
  message that is not that shape goes nowhere. Who may signal whom stays the
  room: every page builds a connection to everybody on the roster.
*/
const SDP_TYPES = ['offer', 'answer', 'pranswer'];
function signal(msg) {
  const to = Number(msg.to);
  if (msg.t === 'sdp') {
    const d = msg.sdp;
    if (!d || typeof d !== 'object' || SDP_TYPES.indexOf(d.type) === -1 || typeof d.sdp !== 'string') return null;
    return { t: 'sdp', to: to, sdp: { type: d.type, sdp: d.sdp } };
  }
  const c = msg.candidate;
  if (!c || typeof c !== 'object' || typeof c.candidate !== 'string') return null;
  const out = { candidate: c.candidate };
  if (typeof c.sdpMid === 'string' || c.sdpMid === null) out.sdpMid = c.sdpMid;
  if (Number.isInteger(c.sdpMLineIndex) || c.sdpMLineIndex === null) out.sdpMLineIndex = c.sdpMLineIndex;
  if (typeof c.usernameFragment === 'string' || c.usernameFragment === null) out.usernameFragment = c.usernameFragment;
  return { t: 'ice', to: to, candidate: out };
}

function roster() {
  const list = [];
  for (const [id, p] of peers) {
    list.push({ peer: id, profileId: p.profileId, name: peerName(p), mode: p.mode || 'local' });
  }
  return list;
}

function announce() {
  const list = roster();
  for (const [, p] of peers) p.ws.sendLatest({ t: 'peers', peers: list });
}

/*
  A NAME AS A PAGE SENT IT, CLEANED ONCE WHERE IT COMES IN (#1349).

  It was kept as sent, cut to forty characters, and from here it goes out in
  the roster and on chat lines other people's pages draw, beside each command
  to the gamemode, and into the chat limit's log line. Measured on 5 October:
  a name holding a line break and "[voice] REFUSED a join for profile 1"
  printed a log line this service never wrote. No character name holds a
  control character, a line or paragraph separator, or a mark that turns the
  direction of the text round, so those go before the cap. The gamemode never
  reads the name off a command (dispatch reads the text, the profile and the
  proven and relay marks), so no name can change the command it rides with.
*/
function cleanName(v) {
  return String(v == null ? '' : v)
    .replace(/[\u0000-\u001f\u007f-\u009f\u061c\u200e\u200f\u2028\u2029\u202a-\u202e\u2066-\u2069]/g, '')
    .trim()
    .slice(0, 40);
}

/*
  profileId is the one the handshake's token proved (#1337): nothing gets a
  socket to send a join on without one, so there is nothing left to refuse
  here. A token in the message is not read, and the profileId in it is only
  compared, so a page that says one thing and proved another is written down.
*/
function onJoin(ws, msg, profileId) {
  const claimed = Number(msg.profileId) || 0;
  if (claimed && claimed !== profileId) {
    console.log('[voice] join claimed profile ' + claimed + ' on a connection whose token is for ' +
                profileId + '. The token wins.');
  }

  const id = nextPeer++;
  const name = cleanName(msg.name);
  peers.set(id, { ws, profileId, name, mode: cleanMode(msg.mode), proven: true,
                  chatTokens: CHAT_BURST, chatAt: Date.now(), chatSlowed: false });

  ws.send({ t: 'welcome', peer: id, profileId: profileId });
  if (profileId && silencedLeft(profileId, Date.now())) {
    try { ws.send({ t: 'hush', profileId: profileId, on: true }); } catch (e) { }
  }
  announce();
  return id;
}

// ------------------------------------------------------------- positions ---
/*
  Whole units and whole degrees. A unit is a seventieth of a metre and a
  degree is finer than any ear can place a voice, and the game's own floats
  carry a dozen digits each: rounded, a row is about a third shorter, and a
  person standing still sends the same row every tick, which is what lets the
  tick below leave them out (issue #482).
*/
function whole(n) { return Math.round(Number(n) || 0); }

function voiceOf(profileId) {
  let talk = false;
  let mode = 'local';
  const pid = Number(profileId) || 0;
  for (const [, p] of peers) {
    if (Number(p.profileId) !== pid) continue;
    if (p.talking) talk = true;
    if (p.mode) mode = p.mode;
  }
  if (silencedLeft(pid, Date.now())) talk = false;
  return { talk: talk, mode: mode };
}

function actorOf(profileId) {
  const v = positions.get(Number(profileId) || 0);
  return v && v.actor ? v.actor : 0;
}

/* Same cell, then a straight line. The speaker is always inside their own
   reach, so they see the line above their own head. */
function inSpeech(aPid, bPid, reach) {
  if (Number(aPid) && Number(aPid) === Number(bPid)) return true;
  const now = Date.now();
  const a = positions.get(Number(aPid) || 0);
  const b = positions.get(Number(bPid) || 0);
  if (!a || !b || now - a.at > STALE_MS || now - b.at > STALE_MS) return false;
  return headlines.sameCellWithin(a, b, reach);
}

function snapshot() {
  const now = Date.now();
  const out = {};
  for (const [pid, v] of positions) {
    if (now - v.at > STALE_MS) continue;
    const pos = Array.isArray(v.pos) ? [whole(v.pos[0]), whole(v.pos[1]), whole(v.pos[2])] : v.pos;
    const voice = voiceOf(Number(pid));
    out[pid] = {
      pos: pos, angleZ: whole(v.angleZ), cell: v.cell, name: v.name,
      actor: v.actor || 0, talk: voice.talk ? 1 : 0, mode: voice.mode
    };
    /* Only while silenced, so a room where nobody is silenced does not grow
       the position tick. Clients close that microphone and hear nothing. */
    if (silencedLeft(Number(pid), now)) out[pid].hush = 1;
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
  an 8 TB monthly cap. voice/test-cull.js measures it on the wire with
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
  a range there: voice/test-cull.js reads the client range tables and
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

/*
  AND ONLY WHAT CHANGED. Issue #482.

  After the cull each person was still sent their whole view five times a
  second, whether anybody in it had moved or not: a room of twenty standing
  round a fire was twenty rows to each of them, every 200 ms, all evening.
  Most of an evening is people standing, so most of that said nothing new.

  So each peer keeps what it was last sent, row by row, as the text of the
  row. The first tick after a join is the whole view, { t: 'pos' }, which is
  what every tick used to be. After that a tick sends { t: 'moved' }, with
  only the rows that differ from what that peer holds and the ids that have
  left its view in gone (out of range, another cell, gone stale, logged
  off), and nothing at all when neither. Every client applies moved on top of
  the table the last pos gave it: launcher/voice-host.html,
  game/ui/thornswood-voice.js and voice/public/voice.js.

  A tick skipped for a backed socket (sendLossy) leaves that peer holding
  something older than this side thinks, so its record is dropped and the
  next tick it is sent is the whole view again. voice/test-moved.js measures
  the bill before and after on the wire.

  A quiet socket is no longer sent something five times a second, which is
  why the pages keep their own ping (SILENT_AFTER, above).
*/
setInterval(() => {
  sweepSilenced(Date.now());
  if (peers.size === 0) return;
  const snap = snapshot();
  const viewOf = viewsOf(snap);
  const text = {};
  const rowText = (pid) => text[pid] || (text[pid] = JSON.stringify(snap[pid]));
  const at = Date.now();
  for (const [, p] of peers) {
    const view = viewOf(p.profileId);
    const now = new Map();
    for (const pid of Object.keys(view)) now.set(pid, rowText(pid));
    let msg;
    if (!p.sent) {
      msg = { t: 'pos', at: at, who: view };
    } else {
      const moved = {};
      let any = false;
      for (const [pid, t] of now) {
        if (p.sent.get(pid) !== t) { moved[pid] = view[pid]; any = true; }
      }
      const gone = [];
      for (const pid of p.sent.keys()) if (!now.has(pid)) gone.push(Number(pid));
      if (!any && gone.length === 0) continue;
      msg = { t: 'moved', at: at, who: moved, gone: gone };
    }
    p.sent = p.ws.sendLossy(msg) ? now : null;
  }
}, 200);

/*
  THIS MACHINE, AND NOT SOMETHING CADDY CARRIED IN (#1797).

  The gamemode's routes (/positions, /commands, /commands/ack, /silenced,
  /textmute, /say) are kept to the gamemode by asking whether the socket
  came from loopback. Caddy carries https://thornswood.net/voice/ and
  /voice-dev/ to this service from 127.0.0.1, so everything it forwarded
  passed that test too: on 5 Oct a POST from outside to
  /voice-dev/positions got "bad json", not "no". Caddy sets
  X-Forwarded-For, X-Forwarded-Proto and X-Forwarded-Host on every request
  it forwards, whatever the client sent, and the gamemode's own requests
  to 127.0.0.1 carry none of them, so a request with any of these headers
  came from somewhere else, whatever its socket says.
*/
function proxied(req) {
  const h = req.headers || {};
  return h['x-forwarded-for'] !== undefined || h['x-forwarded-proto'] !== undefined ||
         h['x-forwarded-host'] !== undefined || h['forwarded'] !== undefined;
}

function isLoopback(req) {
  const ra = req.socket.remoteAddress || '';
  return (ra === '127.0.0.1' || ra === '::1' || ra === '::ffff:127.0.0.1') && !proxied(req);
}

/*
  HOW OFTEN ONE PLACE MAY ASK FOR A TOKEN OR OPEN A SOCKET (#1323).

  Neither door counted anything. Measured on 5 October: sixty POST /token and
  sixty socket handshakes from one address, one after another, were every one
  answered. Each /token is an HMAC and a request to the site, and each socket
  is a peer, a roster sent to everybody, and a place in every position tick.

  So each door takes so many a minute from one place, and past that answers
  429 with Retry-After, never a quiet drop. The rules are the site's own
  limiters' (site/server.js, the report and login limits). A place is the
  socket's address or, behind Caddy, the last X-Forwarded-For hop, which is
  the one Caddy wrote, believed only when the socket is loopback. An IPv6
  address counts as its /64, because one home is handed a whole /64. The
  table holds only a hash of it, under a key made at each start. Only what
  was let in counts, so a script hammering on a refusal does not keep the
  people behind the same address locked out. This machine itself, loopback
  with nobody's address forwarded, is not counted: the box's own scripts and
  the harnesses.

  The launcher asks for a token whenever its voice page or the game's chat
  is about to connect, since a token opens one connection (#1322): one each
  when Play is pressed, then one per try after a loss, the tries spaced as
  below, so twenty a minute is a few people behind one address reconnecting
  at once. A page that lost its
  socket tries again after one to thirty seconds (thornswood-chat.js) or two
  to sixty (voice-host.html), so sixty sockets a minute is several people
  reconnecting at once. Both are settings, so they can be tuned on the box
  without a release.
*/
const TOKEN_PER_MINUTE = Number(process.env.THORNSWOOD_TOKEN_PER_MINUTE) || 20;
const SOCKETS_PER_MINUTE = Number(process.env.THORNSWOOD_SOCKETS_PER_MINUTE) || 60;
const doorSalt = crypto.randomBytes(32);
const tokenDoor = { name: 'token requests', max: TOKEN_PER_MINUTE, seen: new Map(), saidAt: 0 };
const socketDoor = { name: 'sockets', max: SOCKETS_PER_MINUTE, seen: new Map(), saidAt: 0 };

/* Where a request comes from, the way site/server.js clientAddr reads it. */
function clientAddr(req) {
  const sock = String((req.socket && req.socket.remoteAddress) || '');
  let addr = sock;
  if (/^(127\.|::1$|::ffff:127\.)/i.test(sock)) {
    const hops = String(req.headers['x-forwarded-for'] || '').split(',')
      .map((s) => s.trim()).filter(Boolean);
    if (hops.length) addr = hops[hops.length - 1];
  }
  return addr.toLowerCase().replace(/^::ffff:(?=\d+\.\d+\.\d+\.\d+$)/, '');
}

/* This machine itself: loopback, with nobody's address forwarded. Caddy
   always writes the sender in X-Forwarded-For, so what it carries in is the
   sender, not here. */
function fromHere(req) {
  return /^(127\.|::1$)/.test(clientAddr(req));
}

/* Seconds to wait before this one may come in, or 0 when it is let in, and
   then it is counted. */
function doorWait(door, req, now) {
  if (fromHere(req)) return 0;
  let addr = clientAddr(req);
  if (net.isIPv6(addr)) {
    const halves = addr.split('%')[0].split('::');
    const head = halves[0] ? halves[0].split(':') : [];
    const tail = halves.length > 1 && halves[1] ? halves[1].split(':') : [];
    const gap = halves.length > 1 ? Math.max(0, 8 - head.length - tail.length) : 0;
    addr = head.concat(new Array(gap).fill('0'), tail).slice(0, 4)
      .map((g) => (parseInt(g, 16) || 0).toString(16)).join(':') + '::/64';
  }
  const key = crypto.createHmac('sha256', doorSalt).update(addr).digest('hex').slice(0, 32);
  const list = (door.seen.get(key) || []).filter((t) => t > now - 60000);
  if (list.length >= door.max) {
    door.seen.set(key, list);
    if (now - door.saidAt > 60000) {
      door.saidAt = now;
      console.log('[voice] one address passed ' + door.max + ' ' + door.name +
                  ' in a minute, so it is answered 429 until the minute is up');
    }
    return Math.max(1, Math.ceil((list[0] + 60000 - now) / 1000));
  }
  list.push(now);
  door.seen.set(key, list);
  return 0;
}
// Places whose minute is over are forgotten.
setInterval(() => {
  const cut = Date.now() - 60000;
  for (const door of [tokenDoor, socketDoor]) {
    for (const [key, list] of door.seen) {
      const kept = list.filter((t) => t > cut);
      if (kept.length) door.seen.set(key, kept); else door.seen.delete(key);
    }
  }
}, 60000);

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
  by this service. The token goes with the WebSocket handshake, in
  Sec-WebSocket-Protocol, and opens that one connection and no other: see
  WHO THIS IS, BEFORE THE SOCKET OPENS over the upgrade handler. The
  profileId in the join message is ignored.

  The key is this service's own, made on first run and kept beside it. Not the
  server password: everybody who plays here holds that, which is right for
  reading the character register and useless for telling two of them apart.

  A connection that cannot prove itself is refused, always (#1303).
  THORNSWOOD_VOICE_AUTH used to choose: on refused it, log let it in and
  wrote a line, off was the old behaviour. log was meant for the one release
  the tokens took to go out and stayed the default for every service started
  without the setting. Live and dev were already on; nothing reads the
  setting now, and /health says auth on so the scripts that read it still
  can.
*/
/*
  HOW LONG A TOKEN IS GOOD FOR, AND FOR HOW MANY CONNECTIONS (#1322).

  It was good for an hour and for any number of connections. The launcher
  minted one at Play, wrote it to voice-token.txt, handed the same string to
  its own voice page and to the game, renewed it every half hour, and every
  reconnect presented it again. So it was a bearer pass: whoever read it, off
  that file, out of a pack it should never have been in (19 September), or
  off the wire, joined as that person beside them for up to an hour, and
  nothing could tell the copy from the real one.

  Now a token opens one connection. The handshake that presents it spends it,
  and a second handshake with it is refused and written down, because a token
  used twice was copied. Nobody carries one any more: the launcher's page and
  the game each ask the launcher for a fresh token at the moment they connect,
  so two minutes is plenty, and the hour it once needed (Skyrim loading
  between Play and the first join) is no longer anywhere in the path.

  And it is good only to the copy of this service that made it. The list of
  spent tokens lives in this process, so a token minted before it started is
  refused rather than trusted to be unspent.

  THORNSWOOD_TOKEN_SECONDS sets the two minutes.
*/
const TOKEN_LIFETIME_MS = (Number(process.env.THORNSWOOD_TOKEN_SECONDS) || 120) * 1000;
const STARTED_AT = Date.now();

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

/*
  v2.<profile>.<minted, ms>.<nonce>.<mac>. The nonce is what makes each one
  its own, so spending one spends nothing else; the mac covers the v2 as well,
  so nothing signed for v1 can be read as one of these. v1 tokens, the hour
  long passes, are not read at all.
*/
function signToken(profileId, minted, nonce) {
  const body = 'v2.' + String(profileId) + '.' + String(minted) + '.' + String(nonce);
  const mac = crypto.createHmac('sha256', TOKEN_KEY).update(body).digest('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return body + '.' + mac;
}

function mintToken(profileId) {
  const minted = Date.now();
  const nonce = crypto.randomBytes(16).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return { token: signToken(profileId, minted, nonce), until: minted + TOKEN_LIFETIME_MS };
}

/*
  What a token says, or null.

  Checked with timingSafeEqual on equal length buffers rather than ===, so how
  long this takes says nothing about how nearly right a guess was.
*/
function readToken(raw) {
  const s = String(raw == null ? '' : raw);
  const parts = s.split('.');
  if (parts.length !== 5 || parts[0] !== 'v2') return null;
  const profileId = Number(parts[1]) || 0;
  const minted = Number(parts[2]) || 0;
  const nonce = parts[3];
  if (profileId <= 0 || minted <= 0 || !/^[A-Za-z0-9_-]{16,64}$/.test(nonce)) return null;
  const want = signToken(profileId, minted, nonce);
  const a = Buffer.from(want);
  const b = Buffer.from(s);
  if (a.length !== b.length) return null;
  let ok = false;
  try { ok = crypto.timingSafeEqual(a, b); } catch (e) { return null; }
  if (!ok) return null;
  // Expiry last. A token that is genuinely ours but stale is a different thing
  // from one that was made up, and the log should be able to say which.
  return { profileId: profileId, minted: minted, nonce: nonce,
           expired: Date.now() > minted + TOKEN_LIFETIME_MS };
}

/*
  Spent tokens, nonce -> { until, profileId, at }, kept only while the token
  could still be presented: one past its two minutes is refused as expired
  anyway, so it is dropped from here then.
*/
const spent = new Map();

/* The token a handshake presented, spent: { profileId } when it opens this
   connection, { why, profileId } when it does not. */
function spendToken(raw, now) {
  if (!raw) return { why: 'no token', profileId: 0 };
  const tok = readToken(raw);
  if (!tok) return { why: 'a token that does not check out', profileId: 0 };
  if (tok.expired) return { why: 'an expired token', profileId: tok.profileId };
  if (tok.minted < STARTED_AT) return { why: 'a token from before this service started', profileId: tok.profileId };
  for (const [n, s] of spent) { if (now > s.until) spent.delete(n); }
  const was = spent.get(tok.nonce);
  // When it was first used is for the log, not for whoever presented it now.
  if (was) return { why: 'a token that was already used', profileId: tok.profileId, copiedAt: was.at };
  spent.set(tok.nonce, { until: tok.minted + TOKEN_LIFETIME_MS, profileId: tok.profileId, at: now });
  return { profileId: tok.profileId };
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
/*
  AND THE SECRET CAN SIT IN A FILE, turn-key.txt beside this one.

  From the To Do List, "Voice is a full peer-to-peer mesh with no relay": step
  one is a relay, with its credentials minted here and the secret kept on the
  VPS, named by location only. Install-Voice.ps1 writes this service's whole
  environment into the command line of the shell that starts it, which the
  same script reads back out of the process list, so THORNSWOOD_TURN_SECRET
  would put the relay's key wherever that line is shown. The join token key
  already lives in a file here, token-key.txt above, and this is the same
  idea: the relay's static-auth-secret goes in turn-key.txt in the service's
  folder on the VPS, put there by hand, and is read once at start. The
  variable still wins when it is set.

  No file, which is every box today, changes nothing: nothing is logged, /ice
  answers the same bytes, and /health the same fields, with only the build name
  moved so an install can tell this copy is the one running.
  voice/test-turn-key.js holds it to that. The key itself is never logged,
  only where it was read from.

  Written by hand on Windows, so it may arrive as UTF-16 with a byte order
  mark, which is what Windows PowerShell's > and Out-File write, or as UTF-8
  with one, which is what its Set-Content -Encoding UTF8 writes. Read as plain
  UTF-8 either one is a different key, the relay refuses every credential made
  from it, and the only symptom is the same pair of people still not hearing
  each other.

  Not settled by this: which relay. Who may have its credential is settled
  at /ice (#1307): somebody whose join token checks out, and this machine.
*/
const TURN_KEY_FILE = path.join(HERE, 'turn-key.txt');
function readTurnKey(file) {
  let buf;
  try {
    buf = fs.readFileSync(file);
  } catch (e) {
    // Absent is the ordinary case and says nothing. Anything else is a file
    // somebody put there on purpose that cannot be read, which is worth a line.
    if (!e || e.code !== 'ENOENT') {
      console.log('[voice] could not read ' + file + ' (' + (e && e.code) + '), so there is no relay key');
    }
    return '';
  }
  const text = (buf.length >= 2 && buf[0] === 0xFF && buf[1] === 0xFE) ? buf.toString('utf16le') : buf.toString('utf8');
  // trim takes the byte order mark off too: U+FEFF is white space to it.
  return text.trim();
}
const TURN_SECRET_SET = String(process.env.THORNSWOOD_TURN_SECRET || '').trim();
const TURN_SECRET = TURN_SECRET_SET || readTurnKey(TURN_KEY_FILE);
if (TURN_SECRET && !TURN_SECRET_SET) {
  console.log('[voice] relay key read from ' + TURN_KEY_FILE +
              (TURN_URL ? '' : ', but THORNSWOOD_TURN_URL is not set, so no relay is offered'));
}
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
    // The same test as the other gamemode routes, so a request Caddy carried
    // in is refused here too (#1797).
    if (!isLoopback(req)) {
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
            actor: Number(row.actor) || 0,
            // Kept here and never sent on: it only decides who is told about
            // whom. See WHO IS TOLD ABOUT WHOM.
            party: String(row.party || ''), at: now
          });
        }
        for (const pid of Array.from(positions.keys())) if (!seen.has(pid)) positions.delete(pid);
        // doc.requirePass, the game server's join pass switch (#410), is not
        // read here any more: it refused unproven joins while it was on, and
        // since #1303 every unproven join is refused whatever it says.
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
    // So many a minute from one place (#1323); see doorWait.
    const tokenWait = doorWait(tokenDoor, req, Date.now());
    if (tokenWait) {
      res.writeHead(429, { 'content-type': 'text/plain', 'retry-after': String(tokenWait) });
      res.end('Too many token requests from this address. Try again in ' + tokenWait + ' seconds.');
      return;
    }
    readBody(req, res, 4000, (doc) => {
      const pid = Number(doc.profileId) || 0;
      if (pid <= 0) { res.writeHead(400).end('no profileId'); return; }
      const ticket = String(doc.ticket || '');
      if (!ticket) { res.writeHead(400).end('no ticket'); return; }
      owns(ticket, pid, (verdict) => {
        if (verdict === 'no') {
          console.log('[voice] REFUSED a token for profile ' + pid +
                      ': the ticket does not own it');
          res.writeHead(403).end('not your profile');
          return;
        }
        /*
          A token only when the site said yes (#1315). Unchecked used to mint
          one anyway, so that a site outage did not take voice down with it,
          and a token minted that way proved nothing about who asked. 503
          rather than 403: nothing was refused, the question went unanswered,
          and the launcher asks again on its next try.
        */
        if (verdict !== 'yes') {
          console.log('[voice] NO TOKEN for profile ' + pid + ': ' +
                      (SITE ? 'no answer from ' + SITE : 'THORNSWOOD_SITE is not set, so nobody can be asked'));
          res.writeHead(503, { 'content-type': 'text/plain' }).end('nobody could check this profile, so no token');
          return;
        }
        const t = mintToken(pid);
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ token: t.token, until: t.until, profileId: pid }));
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
    // boot: a new stamp tells the gamemode this service restarted (see lineClosed).
    res.end(JSON.stringify({ commands: out, boot: COMMANDS_BOOT }));
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

  // Staff's silences, the whole list each time (#412). See silenced above.
  if (req.method === 'POST' && route === '/silenced') {
    if (!isLoopback(req)) { res.writeHead(403).end('no'); return; }
    readBody(req, res, 20000, (doc) => {
      const list = (doc && doc.profiles && typeof doc.profiles === 'object') ? doc.profiles : {};
      const now = Date.now();
      const before = new Set(silenced.keys());
      silenced.clear();
      for (const k of Object.keys(list)) {
        const pid = Number(k) || 0;
        const until = Number(list[k]) || 0;
        if (pid && until > now) silenced.set(pid, until);
      }
      for (const pid of silenced.keys()) {
        const clear = { t: 'headclear', profileId: pid };
        const hush = { t: 'hush', profileId: Number(pid), on: true };
        for (const [, p] of peers) {
          try { p.ws.send(clear); p.ws.send(hush); } catch (e) { }
        }
      }
      for (const pid of before) {
        if (!silenced.has(pid)) tellHush(pid, false);
      }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ silenced: silenced.size }));
    });
    return;
  }

  if (req.method === 'POST' && route === '/textmute') {
    if (!isLoopback(req)) { res.writeHead(403).end('no'); return; }
    readBody(req, res, 200000, (doc) => {
      const by = (doc && doc.by && typeof doc.by === 'object') ? doc.by : {};
      textOff.clear();
      for (const k of Object.keys(by)) {
        const listener = Number(k) || 0;
        const raw = Array.isArray(by[k]) ? by[k] : [];
        const set = new Set();
        for (let i = 0; i < raw.length; i++) {
          const speaker = Number(raw[i]) || 0;
          if (speaker) set.add(speaker);
        }
        if (listener && set.size) textOff.set(listener, set);
      }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ listeners: textOff.size }));
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

    THE RELAY ONLY TO SOMEBODY WHO HAS PROVED WHO THEY ARE (#1307). This was
    answered whole to anyone who asked, relay credential included: measured
    on 5 October, a stranger with no token was handed a working username and
    password for the relay, and a relay carries its bandwidth bill for
    whoever holds one. Now the STUN list goes to anybody, as it always did,
    and the relay entry only to a page that sends the join token it already
    holds (POST, {"token": ...}, in the body so it is never in an address),
    or to this machine itself, which is how Install-Voice.ps1 reads the relay
    that is running before it reinstalls. A plain GET from anywhere else is
    the STUN list, which is what every box has served while no relay is set.
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
      header. What decides whether the answer holds a relay credential is the
      token, above, not the page. A POST whose body is plain text is a simple
      request, so the page's fetch needs no preflight either.
    */
    const answer = (relay) => {
      res.writeHead(200, { 'content-type': 'application/json',
                           'cache-control': 'no-store',
                           'access-control-allow-origin': '*' });
      res.end(JSON.stringify({ iceServers: relay ? iceServers() : STUN.slice() }));
    };
    if (req.method === 'POST') {
      readBody(req, res, 4000, (doc) => {
        const tok = readToken(doc && doc.token);
        answer(fromHere(req) || !!(tok && !tok.expired));
      });
      return;
    }
    answer(fromHere(req));
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
    res.end(JSON.stringify({ ok: true, build: BUILD, deploy: deployRecord(HERE), auth: 'on',
                            uptimeSeconds: Math.round(process.uptime()),
                            startedAt: new Date(Date.now() - process.uptime() * 1000).toISOString(),
                            bind: BIND,
                            turn: TURN_URL ? (TURN_SECRET ? 'ephemeral' : (TURN_USER ? 'static' : 'MISCONFIGURED')) : 'none',
                            chatRange: CHAT_RANGE,
                            peers: peers.size, tracked: positions.size,
                            queuedCommands: commands.length,
                            backed: backed, largestQueueBytes: largestQueue,
                            droppedPositions: droppedPositions,
                            skippedRosters: skippedRosters,
                            closedBacklogged: closedBacklogged,
                            closedSilent: closedSilent }));
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

/*
  WHICH PAGES MAY OPEN A SOCKET HERE (#1321).

  A browser names the page that opens a socket in Origin, and the page cannot
  change it. Nothing read it, so any website could open sockets to this
  service from its visitors' browsers: measured on 5 October, a handshake with
  Origin https://evil.example was answered 101 and its join welcomed. This
  service sets no cookie and a join proves itself with its own token, so such
  a socket borrows nothing of the visitor's; what it gets is each visitor's
  browser, from that visitor's address, as a client for free.

  So a browser's socket must come from this service's own page: an Origin
  that names the host the request was made to, straight or through Caddy,
  which passes Host on as it came. The game's pages and the launcher's voice
  page are loaded off disk and say null (file:// in older Chromium), and are
  let in. No Origin at all is not a browser (a harness, a script), which this
  was never meant to stop. Anything else is refused before the handshake.

  What this cannot close: a sandboxed frame on any website also says null,
  and nothing in the request tells it apart from the game's own page.
*/
function originAllowed(req) {
  const o = req.headers.origin;
  if (o === undefined) return true;
  const s = String(o).trim().toLowerCase();
  if (s === 'null' || s === 'file://') return true;
  let page, asked;
  try { page = new URL(s); asked = new URL(page.protocol + '//' + String(req.headers.host || '')); }
  catch (e) { return false; }
  return !!asked.host && page.host === asked.host;
}
let originRefused = 0;
let originSaidAt = 0;

/*
  WHO THIS IS, BEFORE THE SOCKET OPENS (#1337, #1322).

  The handshake used to be answered for anybody, and who they were was the
  first message after it. So anybody could hold a socket open and send it
  whatever they liked without a credential at all, and the token, once it
  came, was the same hour long string on every connection.

  A browser cannot set a header on a WebSocket, but it can offer protocols,
  and those travel as Sec-WebSocket-Protocol: the pages offer 'thornswood'
  and their token. Before anything is answered the token is read and spent.
  A handshake without one, with one that does not check out, or with one
  that has already opened a connection is answered 403 and closed, and never
  becomes a socket. The 101 names 'thornswood', which is what a browser needs
  to hear back to keep the connection; the token is never echoed.
*/
const PROTOCOL = 'thornswood';

function refuseUpgrade(socket, why) {
  const body = 'no: ' + why + '\n';
  try {
    socket.on('error', () => { });
    socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Type: text/plain\r\n' +
               'Content-Length: ' + Buffer.byteLength(body) + '\r\n\r\n' + body);
  } catch (e) {
    try { socket.destroy(); } catch (x) { }
  }
}

server.on('upgrade', (req, socket, head) => {
  if (!originAllowed(req)) {
    originRefused++;
    // Once a minute at most, so a busy website cannot fill the log.
    if (Date.now() - originSaidAt > 60000) {
      originSaidAt = Date.now();
      console.log('[voice] refused a socket opened by a page on ' + JSON.stringify(String(req.headers.origin).slice(0, 100)) +
                  ' (' + originRefused + ' refused so far): only this service\'s own page and the game\'s may open one');
    }
    // The HTTP server took its own error listener off this socket when it
    // handed the upgrade over, so without one a refused page that has
    // already gone (a reset as the answer is written) stops the whole
    // service. The socket is being closed either way.
    socket.on('error', () => { });
    socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
    return;
  }
  // So many a minute from one place (#1323); see doorWait.
  const socketWait = doorWait(socketDoor, req, Date.now());
  if (socketWait) {
    // An error listener for the reason given over the 403 just above.
    socket.on('error', () => { });
    socket.end('HTTP/1.1 429 Too Many Requests\r\nRetry-After: ' + socketWait +
               '\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
    return;
  }
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }
  const offered = String(req.headers['sec-websocket-protocol'] || '').split(',')
    .map((s) => s.trim()).filter(Boolean);
  const pass = offered.indexOf(PROTOCOL) === -1
    ? { why: 'no token', profileId: 0 }
    : spendToken(offered.filter((p) => p !== PROTOCOL)[0] || '', Date.now());
  if (!pass.profileId || pass.why) {
    // The profile only when the token named one, and never the token itself.
    console.log('[voice] REFUSED a connection' + (pass.profileId ? ' for profile ' + pass.profileId : '') +
                ': ' + pass.why + (pass.copiedAt ? ', by another connection at ' + new Date(pass.copiedAt).toISOString() +
                ', so it was copied. A token opens one connection (#1322).' : ''));
    refuseUpgrade(socket, pass.why);
    return;
  }
  const proven = pass.profileId;
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    'Sec-WebSocket-Accept: ' + accept(key) + '\r\n' +
    'Sec-WebSocket-Protocol: ' + PROTOCOL + '\r\n\r\n');

  const ws = new Sock(socket);
  let myId = 0;
  // When this connection was last told the command queue is full.
  let refusedAt = 0;

  ws.onmessage = (msg) => {
    // One join per connection, as the profile its token proved. A second
    // join on the same socket was a second peer for the one connection.
    if (msg.t === 'join') { if (!myId) { myId = onJoin(ws, msg, proven); } return; }
    if (!myId) return;

    /*
      A page's own keepalive, answered. Issue #519.

      The ping above is a control frame, and a browser answers it without the
      page ever hearing of it, so a page cannot tell from it whether this end
      is still there. A socket that has gone half open, after a sleep or a
      change of network, looks exactly like a quiet room. So the launcher's
      voice page and the chat overlay send this every twenty five seconds and
      go looking for the server again when nothing at all has come back for
      seventy. The answer is the whole of it.
    */
    if (msg.t === 'ping') { ws.send({ t: 'pong' }); return; }

    // Signalling is passed on as signalling and nothing else (#1350). The
    // server never inspects what an offer or a candidate says, it only
    // decides who is allowed to hear it; see signal for the shape.
    if (msg.t === 'sdp' || msg.t === 'ice') {
      const to = peers.get(Number(msg.to));
      if (!to) return;
      const out = signal(msg);
      if (!out) return;
      out.from = myId;
      to.ws.send(out);
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
      for (const [, p] of peers) {
        if (Number(p.profileId) === Number(me.profileId)) p.mode = mode;
        p.ws.send(out);
      }
      return;
    }

    // The microphone opened or closed. Kept on every connection for this
    // profile, because the launcher and the game can each hold one. The
    // position tick is what the game reads, so a person who walks into
    // range still sees the mark.
    if (msg.t === 'talk') {
      const me = peers.get(myId);
      if (!me) return;
      const on = !!msg.on;
      for (const [, p] of peers) {
        if (Number(p.profileId) === Number(me.profileId)) p.talking = on;
      }
      return;
    }

    // An emote's name, on the same one line as typed speech. It does not
    // also print in the box. The reach is a plain line's reach.
    if (msg.t === 'emote') {
      const me = peers.get(myId);
      const name = headlines.emoteHead(msg.name);
      if (!name) return;
      const hush = me ? silencedLeft(me.profileId, Date.now()) : 0;
      if (hush) {
        if (me && (!me.hushTold || Date.now() - me.hushTold >= SILENCED_TOLD_EVERY_MS)) {
          me.hushTold = Date.now();
          const mins = Math.max(1, Math.ceil(hush / 60000));
          ws.send({ t: 'chat', from: 0, profileId: 0, name: 'Thornswood', at: Date.now(),
                    text: 'Staff have silenced you for another ' + mins +
                          (mins === 1 ? ' minute' : ' minutes') + ', so that did not reach anybody.' });
        }
        return;
      }
      chatWrite('emote', myId, me, name);
      const actor = actorOf(me && me.profileId);
      const line = {
        t: 'head', kind: 'emote', text: name,
        profileId: me ? me.profileId : 0, actor: actor, at: Date.now()
      };
      const heard = hearers(myId, me, headlines.SPEECH);
      const targets = heard ? heard.to : [me].filter(Boolean);
      for (const p of targets) {
        if (!p || !p.ws) continue;
        if (p !== me && textBlocked(p.profileId, line.profileId)) continue;
        p.ws.send(line);
      }
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

      // /me, /do, /w, /s and /ooc are speech. They float, and the box for
      // them is local, whether or not the plain-line switch is on. Every
      // other slash is still a command for the game server.
      const floated = headlines.floatLine(text);
      if (floated && floated.empty) {
        ws.send({ t: 'chat', from: 0, profileId: 0, name: 'Thornswood',
                  text: floated.usage, at: Date.now() });
        return;
      }
      if (floated && floated.local) {
        const hush = me ? silencedLeft(me.profileId, Date.now()) : 0;
        if (hush) {
          chatWrite('silenced', myId, me, text);
          if (!me.hushTold || Date.now() - me.hushTold >= SILENCED_TOLD_EVERY_MS) {
            me.hushTold = Date.now();
            const mins = Math.max(1, Math.ceil(hush / 60000));
            ws.send({ t: 'chat', from: 0, profileId: 0, name: 'Thornswood', at: Date.now(),
                      text: 'Staff have silenced you for another ' + mins +
                            (mins === 1 ? ' minute' : ' minutes') + ', so that did not reach anybody.' });
          }
          return;
        }
        if (!chatAllow(me, myId, Date.now())) return;
        chatWrite('say', myId, me, text);
        const actor = actorOf(me && me.profileId);
        const out = {
          t: 'chat', from: myId, profileId: me ? me.profileId : 0, name: peerName(me),
          text: floated.words, kind: floated.kind, head: floated.head, actor: actor,
          at: Date.now()
        };
        const heard = hearers(myId, me, floated.reach);
        const targets = heard ? heard.to : [me].filter(Boolean);
        let sent = 0;
        for (const p of targets) {
          if (!p || !p.ws) continue;
          if (p !== me && textBlocked(p.profileId, out.profileId)) continue;
          p.ws.send(out);
          sent++;
        }
        if (sent <= 1) {
          ws.send({ t: 'chat', from: 0, profileId: 0, name: 'Thornswood', at: Date.now(),
                    text: heard && heard.placed ? 'Nobody near enough to hear that.'
                                                : 'Your character is not in the world yet, so nobody heard that.' });
        }
        return;
      }

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
        // A join pass is good for ten minutes to whoever holds it, so the
        // chat log keeps that one was sent and never the pass itself (#937).
        chatWrite('command', myId, me, /^\/joinpass\b/i.test(text) ? '/joinpass [pass]' : text);
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
        lineMark(me, text);
        commands.push({
          id: COMMANDS_BOOT + ':' + (nextCommand++),
          profileId: me ? me.profileId : 0,
          name: (me && me.name) || '',
          text: text,
          at: Date.now(),
          offers: 0,
          proven: !!(me && me.proven)
        });
        return;
      }

      // Silenced by staff: said to nobody, and they are told why (#412).
      const hush = me ? silencedLeft(me.profileId, Date.now()) : 0;
      if (hush) {
        chatWrite('silenced', myId, me, text);
        if (!me.hushTold || Date.now() - me.hushTold >= SILENCED_TOLD_EVERY_MS) {
          me.hushTold = Date.now();
          const mins = Math.max(1, Math.ceil(hush / 60000));
          ws.send({ t: 'chat', from: 0, profileId: 0, name: 'Thornswood', at: Date.now(),
                    text: 'Staff have silenced you for another ' + mins +
                          (mins === 1 ? ' minute' : ' minutes') + ', so that did not reach anybody.' });
        }
        return;
      }

      // After the slash branch and never before it; see the chat limit note
      // above the websocket code.
      if (!chatAllow(me, myId, Date.now())) return;

      /* Written before it is sent, so a line that reached the room is always
         in the log. The other way round loses the last thing somebody said
         before this process went down, which is exactly the line an argument
         turns on. */
      chatWrite('say', myId, me, text);

      const profileId = me ? me.profileId : 0;
      const actor = actorOf(profileId);
      const head = floated && floated.head;
      const out = {
        t: 'chat',
        from: myId,
        profileId: profileId,
        name: peerName(me),
        text: text,
        kind: 'say',
        at: Date.now()
      };
      // The box stays worldwide while the range switch is off, and local
      // while it is on. The line above the head is local either way, and
      // you always get your own.
      function deliver(p) {
        if (!p || !p.ws) return;
        if (p !== me && textBlocked(p.profileId, profileId)) return;
        const copy = Object.assign({}, out);
        if (head && inSpeech(profileId, p.profileId, headlines.SPEECH)) {
          copy.head = head;
          copy.actor = actor;
        }
        p.ws.send(copy);
      }
      if (CHAT_RANGE) {
        const heard = hearers(myId, me, chatReach('say'));
        if (heard) {
          for (const p of heard.to) deliver(p);
          if (heard.to.length <= 1) {
            ws.send({ t: 'chat', from: 0, profileId: 0, name: 'Thornswood', at: Date.now(),
                      text: heard.placed ? 'Nobody near enough to hear that.'
                                         : 'Your character is not in the world yet, so nobody heard that.' });
          }
          return;
        }
      }
      for (const [, p] of peers) deliver(p);
      return;
    }
  };

  ws.onclose = () => {
    if (!myId) return;
    const me = peers.get(myId);
    peers.delete(myId);
    announce();
    lineClosed(me);
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
