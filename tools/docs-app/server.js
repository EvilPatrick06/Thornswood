/*
  Thornswood docs, downloads and issue boards.

  Two ways in, deliberately.

    The password lets anybody who has it read the site, run the tests, upload a
    log and report a bug. That is everyone playing.

    Discord makes you an admin: the boards become editable, and the pages that
    are only of interest to whoever is fixing things appear at all. Discord
    rather than a second password because the list of admins is then a list of
    Discord ids, which cannot be passed on by accident.

  Data is files, deliberately. A board is JSON, the two prose pages are
  markdown, uploads are the files themselves. A page can be fixed with a text
  editor when something goes wrong, the whole thing is backed up by copying a
  folder, and anyone with ssh can read a crash log without this process being
  involved at all.

  The member password crosses in clear on plain HTTP. Behind the certificate it
  does not. It guards a list of Skyrim bugs and a game installer, and should be
  treated as guarding exactly that much.
*/

'use strict';

const http   = require('http');
const net    = require('net');
const https  = require('https');
const fs     = require('fs');
const path   = require('path');
const crypto = require('crypto');

const PORT   = Number(process.env.THORNSWOOD_DOCS_PORT || 3001);
/* Once Caddy is in front, this should answer only to Caddy. Otherwise port
   3001 stays open as a plain HTTP way past the certificate, which makes the
   certificate decorative. Set THORNSWOOD_DOCS_LOCAL=1 then. */
const BIND   = process.env.THORNSWOOD_DOCS_LOCAL === '1' ? '127.0.0.1' : '0.0.0.0';
const ROOT   = __dirname;
const DATA   = path.join(ROOT, 'data');
const PUBLIC = path.join(ROOT, 'public');
const FILES  = path.join(ROOT, 'files');
const UP     = path.join(ROOT, 'uploads');

const CFGFILE = path.join(ROOT, 'config.json');
let cfg = {
  password: 'thornswood',
  discord: { clientId: '', clientSecret: '', botToken: '', guildId: '', invite: '' },
  patreon: '',           // the page link, once there is one to link at
  /* Both of these live on this same machine, so the site can just look. */
  gamePort: 7777,
  // What the site actually connects to when it asks whether the game is up.
  // NOT 7777: the game's own traffic there is UDP, and a TCP connect to a UDP
  // port cannot succeed, so probing it reported the server down every single
  // time whatever the server was doing. 3000 is the resources port the client
  // pulls from, it is TCP, and it is the same process, so if one is gone both
  // are. This is the port the service watcher has always used, for this reason.
  gameCheckPort: 3000,
  onlineFile: 'C:/Thornswood-Server/data/online.json',
  /* Discord roles decide everything. A role name here, not an id, because the
     names are what he maintains and the ids are what Discord hands back. */
  /*
    Member is NOT on the play list, and that is the whole closed playtest.
    Everybody who joins the Discord gets Member, so if Member let you into the
    game then anybody who found the invite could walk in, and the application
    would be decoration.

    Playtester is what being accepted means. When the server opens to
    everybody, add 'Member' to this list and that is the entire change.
  */
  access: {
    admin:  ['Owner', 'Dev'],
    play:   ['Owner', 'Dev', 'Moderator', 'Gamemaster', 'Loremaster',
             'Content Creator', 'Playtester'],
    banned: ['Banned']
  },
  botKey: '',            // shared secret the Discord bot signs /api/ticket with
  admins: [],            // discord ids, an override for when the bot is down
  serverPassword: '',    // what the launcher is handed once somebody checks out
  secret: ''
};
/* The byte order mark matters. Windows PowerShell puts one on the front of
   anything it writes with -Encoding UTF8, JSON.parse refuses a string that
   starts with it, and this used to be a bare catch that swallowed the error
   and carried on with the defaults. Which meant the site ran for days looking
   configured from the outside and holding nothing. Strip it, and remember
   whether the read actually worked. */
let cfgBroken = null;
try {
  cfg = Object.assign(cfg, JSON.parse(
    fs.readFileSync(CFGFILE, 'utf8').replace(/^\uFEFF/, '')));
} catch (e) {
  if (fs.existsSync(CFGFILE)) cfgBroken = e;
}
cfg.discord = Object.assign({ clientId:'', clientSecret:'', botToken:'', guildId:'', invite:'' },
                            cfg.discord || {});
cfg.access  = Object.assign({ admin:[], play:[], banned:[] }, cfg.access || {});
// Who may use the dev build and join the dev server. Left out of config.json
// it is the admin roles, Owner and Dev. Add role names here to widen it.
if (!Array.isArray(cfg.access.dev)) cfg.access.dev = cfg.access.admin.slice();
cfg.admins  = Array.isArray(cfg.admins) ? cfg.admins.map(String) : [];

/* Signs the admin cookie. Kept apart from the password so changing the
   password does not sign everybody out of Discord, and made once rather than
   shipped, so it is never a value that exists in the repository. */
/* Never write over a file that failed to parse. It is not empty, it is
   unreadable, and the difference is somebody's client secret. Writing the
   defaults back over it is how the whole Discord configuration disappeared
   once already. */
if (cfgBroken) {
  console.error('[thornswood] config.json is on disk but will not parse, so ' +
                'NOTHING in it is being used and it has been left untouched:');
  console.error('[thornswood]   ' + cfgBroken.message);
  // A throwaway one, so cookies still cannot be forged while it is broken.
  // Not written anywhere, so a restart invalidates every session, which is
  // the correct amount of unpleasant.
  cfg.secret = crypto.randomBytes(32).toString('hex');
} else if (!cfg.secret) {
  cfg.secret = crypto.randomBytes(32).toString('hex');
  try { fs.writeFileSync(CFGFILE, JSON.stringify(cfg, null, 2), 'utf8'); } catch (e) { }
}

for (const dir of [DATA, PUBLIC, FILES, UP]) {
  try { fs.mkdirSync(dir, { recursive: true }); } catch (e) { }
}

// --------------------------------------------------------------- content --
/* Prose pages. Markdown, because they are read start to finish and a table
   would be the wrong shape for either. */
const DOCS = {
  tests: 'Test These',
  help:  'Help'
};

/* Boards. A board is sections, each section a table with its own columns, so
   a column can be added to one without touching the rest. */
const BOARDS = {
  active:      'Active Issues',
  known:       'Known Issues',
  roadmap:     'Roadmap',
  suggestions: 'Suggestions',
  archive:     'Archive',
  todo:        'Patrick'
};

/* Who may see what. 'member' is the password, 'admin' is Discord. The server
   decides this, not the page: a section left out here is not sent at all,
   rather than sent and hidden. */
/* Everything behind /hub is admin now. The tester tier used to live in here,
   which meant anybody allowed into the game could open the same panel he does
   and read half of it. Downloads and Report a problem went to the public site
   instead, so a playtester never needs this page at all and the gate can be
   one role check rather than two tiers. */
const LEVEL = {
  tests: 'admin', help: 'admin', known: 'admin', roadmap: 'admin',
  suggestions: 'admin', files: 'admin', uploads: 'admin', report: 'admin',
  news: 'admin', link: 'admin', linked: 'admin',
  active: 'admin', archive: 'admin', todo: 'admin', inbox: 'admin'
};

/* The public front lives at / and needs no password. The working area moved
   to /hub, because a server nobody can read about is a server nobody joins,
   and a login box was the first thing anybody saw. */
const PUBLIC_PAGES = ['/', '/world', '/rules', '/credits', '/support', '/join',
                      '/classes', '/roadmap', '/news', '/gallery',
                      '/downloads', '/report'];
/* The public pages are markdown on disk like everything else here, so the
   wording can be fixed from the site rather than by a deploy. */
const SITE = path.join(DATA, 'site');

const PAGES = {
  '/hub':         'home',
  '/help':        'help',
  '/known':       'known',
  '/roadmap':     'roadmap',
  '/suggestions': 'suggestions',
  '/news':        'news',
  '/testthese':   'tests',
  '/uploads':     'uploads',
  '/link':        'link',
  '/linked':      'linked',
  '/active':      'active',
  '/patrick':     'todo',
  '/archive':     'archive',
  '/inbox':       'inbox'
};

/*
  Whether the game server is up, and how many people are in it.

  Two different questions with two different answers. The gamemode already
  writes data/online.json whenever the count moves, so that is where the number
  comes from. But it only writes on a CHANGE, so a quiet server has an old
  timestamp and that file cannot tell you whether anything is running. For that
  the site opens a socket to the game's resources port on this same machine,
  which is the only answer that is never stale.

  The port matters. This used to connect to 7777, which is where the game's
  own traffic goes, and that traffic is UDP. Opening a TCP socket to a UDP port
  fails every time, so the front page said Server offline for as long as this
  code has existed, including while the server was up with people in it.

  Checked every ten seconds rather than per request, because the front page is
  the most requested thing here and none of this changes that fast.
*/
let gameStatus = { up: false, online: 0, at: 0 };
function pollGame() {
  const sock = new net.Socket();
  let done = false;
  const finish = (up) => {
    if (done) return;
    done = true;
    try { sock.destroy(); } catch (e) { }
    let online = 0;
    try {
      const o = JSON.parse(fs.readFileSync(cfg.onlineFile, 'utf8'));
      if (o && typeof o.now === 'number') online = o.now;
    } catch (e) { }
    gameStatus = { up, online: up ? online : 0, at: Date.now() };
  };
  sock.setTimeout(1500);
  sock.once('connect', () => finish(true));
  sock.once('timeout', () => finish(false));
  sock.once('error', () => finish(false));
  try { sock.connect(Number(cfg.gameCheckPort) || 3000, '127.0.0.1'); }
  catch (e) { finish(false); }
}
pollGame();
setInterval(pollGame, 10000).unref?.();

const jsonFile = (p, fallback) => {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (e) { return fallback; }
};
const putJson = (p, o) => {
  try { fs.writeFileSync(p, JSON.stringify(o, null, 2), 'utf8'); return true; }
  catch (e) { return false; }
};

const docPath = (n) => Object.prototype.hasOwnProperty.call(DOCS, n)
  ? path.join(DATA, n + '.md') : null;

function readDoc(n) {
  const p = docPath(n);
  if (!p) return null;
  try { return fs.readFileSync(p, 'utf8'); } catch (e) { return ''; }
}

function writeDoc(n, text) {
  const p = docPath(n);
  if (!p) return false;
  try {
    try { if (fs.existsSync(p)) fs.copyFileSync(p, p + '.bak'); } catch (e) { }
    fs.writeFileSync(p, text, 'utf8');
    return true;
  } catch (e) { return false; }
}

const BOARDFILE = path.join(DATA, 'board.json');
const readBoard = () => jsonFile(BOARDFILE, {});
function writeBoardOne(name, value) {
  if (!Object.prototype.hasOwnProperty.call(BOARDS, name)) return false;
  const all = readBoard();
  all[name] = value;
  // One board at a time, so two people on two boards never overwrite each
  // other. Two people on the SAME board still do, and last save wins.
  try { fs.copyFileSync(BOARDFILE, BOARDFILE + '.bak'); } catch (e) { }
  return putJson(BOARDFILE, all);
}

const RESULTS = path.join(DATA, 'results.json');
const INBOX   = path.join(DATA, 'inbox.json');
/* Written by Publish-News.ps1 at the end of every release: the same feed the
   launcher shows, stripped of the server password before it leaves his
   machine. Nothing here writes it. */
const NEWS    = path.join(DATA, 'news.json');

// ------------------------------------------------------------- downloads --
function listFiles() {
  const meta = jsonFile(path.join(FILES, 'files.json'), {});
  const out = [];
  let names = [];
  try { names = fs.readdirSync(FILES); } catch (e) { }
  for (const name of names) {
    if (name === 'files.json') continue;
    let st;
    try { st = fs.statSync(path.join(FILES, name)); } catch (e) { continue; }
    if (!st.isFile()) continue;
    const m = meta[name] || {};
    // hidden has to survive the trip. The payload zip is marked hidden by
    // Publish-Installer because the setup program fetches it itself, and the
    // page hides it on that flag. Dropping it here put the old two file
    // instructions back on the downloads page and a 527 MB button next to
    // them that does nothing on its own.
    out.push({ name, size: st.size, at: st.mtimeMs, hidden: !!m.hidden,
      label: m.label || name, version: m.version || '', note: m.note || '' });
  }
  out.sort((a, b) => b.at - a.at);
  return out;
}

// --------------------------------------------------------------- uploads --
/* Somewhere to put a screenshot or a papyrus log without a share link and
   three permission prompts in the way. They land in uploads/ under a stamped
   name, and anyone with ssh reads that folder directly, which is the point: a
   log nobody can fetch is a log nobody reads. */
const UPMETA = path.join(UP, 'uploads.json');
const KIND = {
  '.png':'image/png', '.jpg':'image/jpeg', '.jpeg':'image/jpeg', '.gif':'image/gif',
  '.webp':'image/webp', '.bmp':'image/bmp',
  '.txt':'text/plain; charset=utf-8', '.log':'text/plain; charset=utf-8',
  '.json':'text/plain; charset=utf-8', '.ini':'text/plain; charset=utf-8',
  '.md':'text/plain; charset=utf-8', '.cfg':'text/plain; charset=utf-8'
};

function listUploads() {
  const meta = jsonFile(UPMETA, {});
  const out = [];
  let names = [];
  try { names = fs.readdirSync(UP); } catch (e) { }
  for (const name of names) {
    if (name === 'uploads.json') continue;
    let st;
    try { st = fs.statSync(path.join(UP, name)); } catch (e) { continue; }
    if (!st.isFile()) continue;
    const m = meta[name] || {};
    const ext = path.extname(name).toLowerCase();
    out.push({
      name, size: st.size, at: m.at || st.mtimeMs,
      orig: m.orig || name, by: m.by || '', note: m.note || '',
      image: /^image\//.test(KIND[ext] || ''),
      text: (KIND[ext] || '').indexOf('text/') === 0
    });
  }
  out.sort((a, b) => b.at - a.at);
  return out;
}

// ------------------------------------------------------------------ auth --
const COOKIE = 'tw';
const ADMIN  = 'twa';

const memberToken = () => crypto.createHash('sha256')
  .update('thornswood:' + String(cfg.password || '')).digest('hex');

function sign(v) {
  return crypto.createHmac('sha256', cfg.secret).update(String(v)).digest('hex').slice(0, 32);
}

function sameSecret(a, b) {
  const x = Buffer.from(String(a).padEnd(96).slice(0, 96));
  const y = Buffer.from(String(b).padEnd(96).slice(0, 96));
  return crypto.timingSafeEqual(x, y);
}

function cookies(req) {
  const out = {};
  for (const part of (req.headers.cookie || '').split(';')) {
    const [k, ...v] = part.trim().split('=');
    if (k) out[k] = v.join('=');
  }
  return out;
}

const discordReady = () =>
  !!(cfg.discord.clientId && cfg.discord.clientSecret);

/* The password is a bootstrap, not a door. It exists so the one person who can
   configure Discord can get in to do it, and it stops existing the moment they
   have. Old cookies die with it, which is the point: a password that was
   passed around before is still passed around now. */
const isMember = (req) =>
  !discordReady() && sameSecret(cookies(req)[COOKIE] || '', memberToken());

/* The Discord cookie carries the id and a signature of it, and proves only who
   somebody is. What they may do is asked of Discord, so that removing a role
   or removing a person takes effect here without anybody editing a list. */
function identity(req) {
  const raw = cookies(req)[ADMIN] || '';
  const [id, name, sig] = decodeURIComponent(raw).split('|');
  if (!id || !sig) return null;
  if (!sameSecret(sig, sign(id + '|' + (name || '')))) return null;
  return { id: String(id), name: name || '' };
}

/* A minute of memory, so clicking around the site is not forty calls to
   Discord, and a ban still lands within a minute. */
const standCache = new Map();
async function standingCached(id) {
  const hit = standCache.get(id);
  if (hit && Date.now() - hit.at < 60000) return hit.v;
  const v = await standing(id);
  standCache.set(id, { at: Date.now(), v });
  return v;
}

async function who(req) {
  const me = identity(req);
  if (!me) return { member: isMember(req), admin: false, name: '', id: '', play: false };
  const st = await standingCached(me.id);
  return {
    // "member" is now "may use the hub", and only staff may. Being allowed
    // into the GAME is st.play, and that is asked separately by the launcher.
    member: st.admin || isMember(req),
    admin: st.admin,
    play: st.play,
    banned: st.banned,
    inGuild: st.inGuild,
    id: me.id,
    name: st.name || me.name
  };
}

const allowed = (key, w) =>
  LEVEL[key] === 'admin' ? w.admin : w.member;

// ----------------------------------------------------------------- plumb --
function send(res, code, payload, type, extra) {
  res.writeHead(code, Object.assign({
    'Content-Type': type || 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff'
  }, extra || {}));
  res.end(payload);
}
const sendJson = (res, code, obj) => send(res, code, JSON.stringify(obj));

function body(req, cap) {
  return new Promise((resolve) => {
    let out = '';
    req.on('data', (d) => { out += d; if (out.length > (cap || 4000000)) req.destroy(); });
    req.on('end', () => resolve(out));
  });
}

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon'
};

const origin = (req) => {
  const proto = (req.headers['x-forwarded-proto'] || '').split(',')[0].trim() ||
                'http';
  return proto + '://' + (req.headers.host || 'localhost');
};
const secureHere = (req) =>
  (req.headers['x-forwarded-proto'] || '').split(',')[0].trim() === 'https';

const setCookie = (req, name, value, days) =>
  name + '=' + value + '; Path=/; Max-Age=' + (days * 86400) +
  '; HttpOnly; SameSite=Lax' + (secureHere(req) ? '; Secure' : '');

// --------------------------------------------------------------- discord --
function post(url, form) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const data = new URLSearchParams(form).toString();
    const r = https.request({
      hostname: u.hostname, path: u.pathname, method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded',
                 'Content-Length': Buffer.byteLength(data) }
    }, (res) => {
      let out = '';
      res.on('data', (d) => out += d);
      res.on('end', () => { try { resolve(JSON.parse(out)); } catch (e) { reject(e); } });
    });
    r.on('error', reject);
    r.end(data);
  });
}

/* Asking Discord who somebody is in the server. Needs the bot, because a
   person's OAuth login only proves who they are, not that they are in the
   Thornswood Discord or what roles they carry there. */
/* Returns { ok, status, body }. It used to return null for everything that was
   not a 200, which meant a dead bot token, a rate limit and a person who really
   is not in the server all came back identical, and the site told all three of
   them they were not in the Discord. The one person that never affected was
   whoever is on the hand written admin list, because that is checked first, so
   it looked fine from the only account that could have noticed. */
function discordGet(path) {
  return new Promise((resolve) => {
    if (!cfg.discord.botToken) {
      return resolve({ ok: false, status: 0, body: null, why: 'no bot token set' });
    }
    const req = https.get({
      hostname: 'discord.com', path: '/api/v10' + path,
      headers: { Authorization: 'Bot ' + cfg.discord.botToken }
    }, (res) => {
      let out = '';
      res.on('data', (d) => out += d);
      res.on('end', () => {
        if (res.statusCode === 200) {
          try { return resolve({ ok: true, status: 200, body: JSON.parse(out) }); }
          catch (e) { return resolve({ ok: false, status: 200, body: null, why: 'unreadable answer' }); }
        }
        if (res.statusCode === 404) {
          return resolve({ ok: false, status: 404, body: null, why: 'not found' });
        }
        let msg = 'Discord answered ' + res.statusCode;
        if (res.statusCode === 401) msg = 'the bot token is wrong or has been reset';
        else if (res.statusCode === 403) msg = 'the bot is in the server but not allowed to read members';
        else if (res.statusCode === 429) msg = 'rate limited by Discord';
        console.error('[thornswood] discord ' + path + ': ' + msg);
        resolve({ ok: false, status: res.statusCode, body: null, why: msg });
      });
    });
    req.setTimeout(10000, () => { try { req.destroy(); } catch (e) { } });
    req.on('error', (e) => resolve({ ok: false, status: 0, body: null, why: 'could not reach Discord: ' + e.message }));
  });
}

/* Role ids mean nothing on their own, so they are turned back into names once
   every five minutes and matched by name. */
let roleCache = { at: 0, byId: {} };
async function roleNames() {
  if (Date.now() - roleCache.at < 300000 && Object.keys(roleCache.byId).length) {
    return roleCache.byId;
  }
  const got = await discordGet('/guilds/' + cfg.discord.guildId + '/roles');
  if (!got.ok || !Array.isArray(got.body)) return roleCache.byId;
  const byId = {};
  got.body.forEach((r) => { byId[r.id] = r.name; });
  roleCache = { at: Date.now(), byId };
  return byId;
}

const LINKED = path.join(DATA, 'linked.json');

/* Every attempt to sign in, whether it worked or not.
 *
 * linked.json only records people who got through, which means somebody
 * refused at the door leaves no trace at all: not that they tried, not who
 * they were, not what they were reaching for. That is exactly the record
 * worth having for /hub, where the answer to "has anybody been poking at the
 * admin panel" should be a list rather than a shrug.
 *
 * Newest first, capped, so it can never grow without limit on the VPS. */
const ATTEMPTS = path.join(DATA, 'signins.json');
const ATTEMPTS_KEEP = 500;

function noteSignIn(req, me, st, back) {
  try {
    const list = jsonFile(ATTEMPTS, []);
    const rows = Array.isArray(list) ? list : [];

    let outcome = 'allowed';
    if (st.lookupFailed) outcome = 'could not check';
    else if (st.banned) outcome = 'banned';
    else if (!st.inGuild) outcome = 'not in the Discord';
    else if (!st.play) outcome = 'no role';

    rows.unshift({
      at: Date.now(),
      id: String(me.id || ''),
      handle: String(me.username || ''),
      name: String(st.name || me.global_name || me.username || ''),
      wanted: String(back || '/'),
      admin: !!st.admin,
      outcome: outcome,
      roles: Array.isArray(st.roles) ? st.roles.slice(0, 12) : [],
      ip: String((req.headers['x-forwarded-for'] || '').split(',')[0].trim() ||
                 (req.socket && req.socket.remoteAddress) || '')
    });
    putJson(ATTEMPTS, rows.slice(0, ATTEMPTS_KEEP));
  } catch (e) { }
}

/* What this person is allowed to do, decided by their roles in the Discord and
   nothing else. Leaving the server, or being given the Banned role, takes
   everything away at once, which is the whole reason for doing it this way. */
async function standing(discordId) {
  const out = { id: String(discordId), inGuild: false, banned: false,
                admin: false, play: false, dev: false, roles: [], name: '' };

  /* The hand written admin list is an override, not a hint. It is the way back
     in when the bot is not in the server yet, has been kicked, or Discord is
     having a bad morning, so it cannot be gated behind a guild lookup that
     needs all three of those to be fine. */
  if (cfg.admins.indexOf(String(discordId)) >= 0) {
    out.admin = true; out.play = true; out.inGuild = true; out.dev = true;
    if (cfg.discord.botToken && cfg.discord.guildId) {
      const r = await discordGet('/guilds/' + cfg.discord.guildId + '/members/' + discordId);
      if (r.ok) {
        const me = r.body;
        out.name = (me.nick || (me.user && (me.user.global_name || me.user.username)) || '');
        const names = await roleNames();
        out.roles = (me.roles || []).map((id) => names[id]).filter(Boolean);
      } else if (r.status !== 404) {
        out.lookupFailed = r.why;
      }
    }
    return out;
  }

  if (!cfg.discord.botToken || !cfg.discord.guildId) {
    // No bot configured yet, so the manual admin list is all there is and
    // everybody else is treated as an ordinary member.
    out.inGuild = true;
    out.play = true;
    return out;
  }
  const r = await discordGet('/guilds/' + cfg.discord.guildId + '/members/' + discordId);
  if (!r.ok) {
    // A real 404 is the only one that means "not in the server". Everything
    // else is the site's problem and has to say so, or somebody who IS in the
    // server spends an evening being told they are not.
    if (r.status !== 404) out.lookupFailed = r.why;
    return out;
  }
  const m = r.body;
  out.inGuild = true;
  out.name = (m.nick || (m.user && (m.user.global_name || m.user.username)) || '');
  const names = await roleNames();
  out.roles = (m.roles || []).map((id) => names[id]).filter(Boolean);
  const has = (list) => (list || []).some((n) => out.roles.indexOf(n) >= 0);
  out.banned = has(cfg.access.banned);
  if (out.banned) { out.admin = false; out.play = false; return out; }
  if (has(cfg.access.admin)) out.admin = true;
  out.play = out.admin || has(cfg.access.play);
  out.dev = out.admin || has(cfg.access.dev);
  return out;
}

/* The ticket the launcher keeps. Signed rather than stored, so a restart does
   not sign everybody out, and short enough lived that leaving the Discord
   stops mattering within the month even if nothing checks. Every use is
   re-checked against Discord anyway; the expiry is only for when it cannot be. */
function makeTicket(id, name) {
  const body = Buffer.from(JSON.stringify({
    d: String(id), n: String(name || ''), x: Date.now() + 30 * 86400000
  })).toString('base64url');
  return 'tk1.' + body + '.' + sign('ticket:' + body);
}

function readTicket(t) {
  const parts = String(t || '').split('.');
  if (parts.length !== 3 || parts[0] !== 'tk1') return null;
  if (!sameSecret(parts[2], sign('ticket:' + parts[1]))) return null;
  let o;
  try { o = JSON.parse(Buffer.from(parts[1], 'base64url').toString()); }
  catch (e) { return null; }
  if (!o || !o.d || !o.x || o.x < Date.now()) return null;
  return o;
}

function getWithToken(url, token) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    https.get({ hostname: u.hostname, path: u.pathname,
      headers: { Authorization: 'Bearer ' + token } }, (res) => {
      let out = '';
      res.on('data', (d) => out += d);
      res.on('end', () => { try { resolve(JSON.parse(out)); } catch (e) { reject(e); } });
    }).on('error', reject);
  });
}

/* Refused at the door. It says which of the three reasons it was and what the
   person's own Discord id is, because "you are not allowed" with no reason is
   a support ticket and this is the answer to it. */
function notAllowedPage(me, st) {
  const nm = String(me.username || '').replace(/[<>&]/g, '');
  const id = String(me.id).replace(/[^0-9]/g, '');
  const esc = (t) => String(t == null ? '' : t).replace(/[<>&]/g, '');
  let why;
  if (st.lookupFailed) {
    // Not the person's fault and not a role problem. Saying "you are not in
    // the Discord" here is how somebody who IS in it loses an evening.
    why = '<p>Thornswood could not ask Discord about that account, so it cannot ' +
          'let anybody in right now. This is the site, not you.</p>' +
          '<p style="color:#8D9682;font-size:13px">' + esc(st.lookupFailed) + '</p>' +
          '<p>Tell Gavin and try again in a minute.</p>';
  } else if (st.banned) {
    why = '<p>That account is banned from Thornswood.</p>';
  } else if (!st.inGuild) {
    why = '<p>That account is not in the Thornswood Discord.</p>' +
      (cfg.discord.invite
        ? '<p><a style="color:#C9A24B" href="' + cfg.discord.invite + '">Join it here</a>, then try again.</p>'
        : '');
  } else {
    why = '<p>That account is in the Discord but has no role that lets it in yet. ' +
          'Ask in there and somebody will sort it.</p>' +
          '<p style="color:#8D9682;font-size:13px">Roles Thornswood can see on it: ' +
          (st.roles && st.roles.length ? '<b>' + st.roles.map(esc).join(', ') + '</b>' : 'none') +
          '.<br>It needs one of: <b>' + (cfg.access.play || []).map(esc).join(', ') + '</b>.</p>';
  }
  return '<!doctype html><meta charset=utf-8><title>Not allowed in</title>' +
    '<body style="background:#12150F;color:#DDE3D5;font:15px/1.6 system-ui;' +
    'display:grid;place-items:center;height:100vh;margin:0;text-align:center;padding:20px">' +
    '<div style="max-width:32em"><h1 style="color:#C9A24B;font-weight:600">Not allowed in</h1>' +
    why +
    '<p style="color:#8D9682;font-size:13px">Signed in to Discord as <b>' + nm +
    '</b>, id <code>' + id + '</code>. Quote that id if you ask about it.</p>' +
    '<p><a href="/" style="color:#C9A24B">Back to the site</a></p></div></body>';
}

// ------------------------------------------------------------------ serve --
http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const p = decodeURIComponent(url.pathname);
  const route = p.replace(/\/+$/, '').toLowerCase() || '/';
  const w = await who(req);

  // ---------------------------------------------------------- member login
  if (p === '/api/login' && req.method === 'POST') {
    if (discordReady()) {
      return sendJson(res, 403, { error: 'Discord sign in only. The password is off.' });
    }
    let given = '';
    try { given = (JSON.parse(await body(req, 4096)) || {}).password || ''; }
    catch (e) { }
    if (!sameSecret(given, String(cfg.password || ''))) {
      return sendJson(res, 401, { error: 'wrong password' });
    }
    return send(res, 200, JSON.stringify({ ok: true }),
      'application/json; charset=utf-8',
      { 'Set-Cookie': setCookie(req, COOKIE, memberToken(), 365) });
  }

  if (p === '/api/logout' && req.method === 'POST') {
    return send(res, 200, JSON.stringify({ ok: true }),
      'application/json; charset=utf-8',
      { 'Set-Cookie': [
          COOKIE + '=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax',
          ADMIN  + '=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax'
        ] });
  }

  // --------------------------------------------------------- discord login
  // An invite link that never goes stale in six places at once.
  if (route === '/discord' && req.method === 'GET') {
    if (!cfg.discord.invite) return send(res, 404, 'No invite link set yet.', 'text/plain');
    return send(res, 302, '', 'text/plain', { Location: cfg.discord.invite });
  }

  // ----------------------------------------------------------- domain proof
  // Discord's Connections > Domain check fetches /.well-known/discord and
  // wants its dh= line back as plain text. Anything dropped into
  // public\.well-known is served here by name; the static block below only
  // serves single-segment paths, so this needs its own route. No sign in,
  // Discord is not a member.
  const proof = p.match(/^\/\.well-known\/([A-Za-z0-9._-]+)$/);
  if (proof && req.method === 'GET') {
    const dir = path.join(PUBLIC, '.well-known');
    const file = path.join(dir, proof[1]);
    if (file.startsWith(dir + path.sep) && fs.existsSync(file)) {
      return send(res, 200, fs.readFileSync(file), 'text/plain; charset=utf-8',
        { 'Cache-Control': 'no-store' });
    }
    return send(res, 404, 'no such file', 'text/plain');
  }

  if (p === '/auth/discord' && req.method === 'GET') {
    if (!cfg.discord.clientId) {
      return send(res, 500, 'Discord login is not set up on this server yet.', 'text/plain');
    }
    // back is where the browser lands afterwards; port is the launcher waiting
    // on the loopback address for its ticket. Both are signed into the state so
    // neither can be swapped on the way through Discord.
    const back = url.searchParams.get('back') || '/';
    const askedPort = String(url.searchParams.get('port') || '').replace(/[^0-9]/g, '').slice(0, 5);
    // The launcher's own nonce. It rides through Discord inside the signed
    // state and comes back on the loopback redirect, which is how the launcher
    // knows the ticket it just caught belongs to the button its owner pressed
    // and not to a web page that guessed the port.
    const nonce = String(url.searchParams.get('nonce') || '').replace(/[^A-Za-z0-9]/g, '').slice(0, 64);
    const raw = Buffer.from(back + '\u0000' + askedPort + '\u0000' + nonce).toString('base64url');
    const state = raw + '.' + sign(raw);
    const go = 'https://discord.com/api/oauth2/authorize' +
      '?client_id=' + encodeURIComponent(cfg.discord.clientId) +
      '&redirect_uri=' + encodeURIComponent(origin(req) + '/auth/discord/callback') +
      '&response_type=code&scope=identify' +
      '&state=' + encodeURIComponent(state);
    return send(res, 302, '', 'text/plain', { Location: go });
  }

  if (p === '/auth/discord/callback' && req.method === 'GET') {
    const code = url.searchParams.get('code') || '';
    const state = (url.searchParams.get('state') || '').split('.');
    let back = '/', port = '', nonce = '';
    if (state.length === 2 && sameSecret(state[1], sign(state[0]))) {
      try {
        const bits = Buffer.from(state[0], 'base64url').toString().split('\u0000');
        back = bits[0] || '/';
        port = (bits[1] || '').replace(/[^0-9]/g, '').slice(0, 5);
        nonce = (bits[2] || '').replace(/[^A-Za-z0-9]/g, '').slice(0, 64);
      } catch (e) { }
    }
    if (!/^\/[A-Za-z0-9/_-]*$/.test(back)) back = '/';
    if (!code) return send(res, 302, '', 'text/plain', { Location: '/?discord=cancelled' });

    let me;
    try {
      const tok = await post('https://discord.com/api/oauth2/token', {
        client_id: cfg.discord.clientId,
        client_secret: cfg.discord.clientSecret,
        grant_type: 'authorization_code',
        code,
        redirect_uri: origin(req) + '/auth/discord/callback'
      });
      if (!tok || !tok.access_token) throw new Error('no token');
      me = await getWithToken('https://discord.com/api/users/@me', tok.access_token);
    } catch (e) {
      return send(res, 302, '', 'text/plain', { Location: '/?discord=failed' });
    }
    if (!me || !me.id) {
      return send(res, 302, '', 'text/plain', { Location: '/?discord=failed' });
    }
    const st = await standing(me.id);
    standCache.delete(String(me.id));

    // Written before the decision, so a refusal is recorded as surely as a
    // success. The one somebody wants to look up later is always the refusal.
    noteSignIn(req, me, st, back);

    if (!st.inGuild || st.banned || !st.play) {
      return send(res, 200, notAllowedPage(me, st), TYPES['.html']);
    }
    const name = String(st.name || me.global_name || me.username || '').replace(/[|;]/g, '');
    const value = encodeURIComponent(me.id + '|' + name + '|' + sign(me.id + '|' + name));

    // Remembered so there is a list of who has linked, when, and under what
    // name, which is what makes a ban traceable to a person later.
    const linked = jsonFile(LINKED, {});
    const was = linked[me.id] || {};
    linked[me.id] = Object.assign(was, {
      id: String(me.id), name: name,
      handle: String(me.username || ''),
      first: was.first || Date.now(), seen: Date.now(),
      roles: st.roles
    });
    putJson(LINKED, linked);

    const cookies2 = [setCookie(req, ADMIN, value, 30),
                      setCookie(req, COOKIE, memberToken(), 365)];

    // The launcher asked, so hand the ticket back to it on the loopback
    // address rather than leaving it in the browser.
    if (port) {
      return send(res, 302, '', 'text/plain', {
        Location: 'http://127.0.0.1:' + port + '/thornswood?ticket=' +
                  encodeURIComponent(makeTicket(me.id, name)) +
                  '&name=' + encodeURIComponent(name) +
                  (nonce ? '&nonce=' + encodeURIComponent(nonce) : ''),
        'Set-Cookie': cookies2
      });
    }
    return send(res, 302, '', 'text/plain', { Location: back, 'Set-Cookie': cookies2 });
  }

  /* Who has tried to sign in. Admins only, because it is a list of people. */
  if (p === '/api/signins' && req.method === 'GET') {
    if (!w.admin) return sendJson(res, 403, { error: 'admins only' });
    const rows = jsonFile(ATTEMPTS, []);
    return sendJson(res, 200, { signins: Array.isArray(rows) ? rows : [] });
  }

  if (p === '/api/hello') {
    return sendJson(res, w.member ? 200 : 401, {
      ok: w.member, admin: w.admin, name: w.name,
      discord: discordReady(),
      invite: cfg.discord.invite || ''
    });
  }

  // ---------------------------------------------------------- public front
  if (req.method === 'GET' && PUBLIC_PAGES.indexOf(route) >= 0) {
    try {
      let html = fs.readFileSync(path.join(PUBLIC, 'home.html'), 'utf8');
      // One place holds the invite link, so it cannot go stale in nine.
      // /join, never /hub. Somebody clicking Apply wants to know how to apply,
      // and sending them to the admin panel is the worst possible answer.
      html = html.split('DISCORD_URL').join(cfg.discord.invite || '/join');
      return send(res, 200, html, TYPES['.html']);
    } catch (e) { return send(res, 500, 'no home.html', 'text/plain'); }
  }

  // Everything the front page needs and nothing that is anybody's business.
  if (route === '/api/public' && req.method === 'GET') {
    const feed = jsonFile(NEWS, { news: [] });
    return sendJson(res, 200, {
      invite: cfg.discord.invite || '',
      patreon: cfg.patreon || '',
      status: { up: gameStatus.up, online: gameStatus.online },
      gallery: jsonFile(path.join(DATA, 'gallery.json'), []),
      launcher: feed.launcher || '',
      collection: feed.collection || '',
      files: listFiles(),
      news: (feed.news || []).slice(0, 6).map((n) => ({ date:n.date, title:n.title }))
    });
  }

  /*
    What the setup program fetches. It is a small exe with the mods beside it,
    so on startup it asks here for the name, the address and the size of the
    payload, then downloads it with a Range header so a dropped connection
    carries on rather than starting over.

    This route did not exist. Every request for it fell through to the admin
    API block below, which answers 401 sign in first to anybody not logged in,
    and the installer showed "Could not reach https://thornswood.net to get the
    mods ... (401) Unauthorized" to every new person. It has to stay above that
    gate and stay public, because an installer cannot sign in.

    The reply is read by Bootstrap.cs with plain string searches for "name":",
    "url":" and "size":, so the shape matters more than the field order.
  */
  if (route === '/api/payload' && req.method === 'GET') {
    let best = null;
    try {
      for (const name of fs.readdirSync(FILES)) {
        if (!/^Thornswood-Setup-.*\.zip$/i.test(name)) continue;
        const st = fs.statSync(path.join(FILES, name));
        if (!st.isFile()) continue;
        if (!best || st.mtimeMs > best.at) best = { name, at: st.mtimeMs, size: st.size };
      }
    } catch (e) { }
    // No zip means a one file build, where the payload rides inside the exe
    // and nothing should be fetched. Bootstrap turns an empty url into "The
    // site is not offering a download right now", which is the truth.
    if (!best) return sendJson(res, 200, {});
    return sendJson(res, 200, {
      name: best.name,
      url: '/file/' + encodeURIComponent(best.name),
      size: best.size
    });
  }

  /* Reporting a problem is public on purpose. Somebody whose install will not
     start cannot sign in to say so, and making them ask in Discord first is
     how a bug turns into nobody bothering. Held to one short message at a
     time, and the inbox is capped so it cannot be used to fill the disk. */
  if (route === '/api/report' && req.method === 'POST') {
    let o;
    try { o = JSON.parse(await body(req, 20000)); }
    catch (e) { return sendJson(res, 400, { error: 'bad json' }); }
    const title = String(o.title || '').trim().slice(0, 200);
    if (!title) return sendJson(res, 400, { error: 'say what happened in the first box' });
    const list = jsonFile(INBOX, []);
    list.unshift({
      id: 'i' + Date.now().toString(36) + crypto.randomBytes(2).toString('hex'),
      kind: o.kind === 'idea' ? 'idea' : 'bug',
      title,
      detail: String(o.detail || '').slice(0, 8000),
      by: String(o.by || '').slice(0, 40),
      at: Date.now(),
      state: 'new',
      from: 'the public page'
    });
    if (!putJson(INBOX, list.slice(0, 2000))) {
      return sendJson(res, 500, { error: 'could not save' });
    }
    return sendJson(res, 200, { ok: true });
  }

  if (route === '/api/ticket' && req.method === 'POST') {
    if (!cfg.botKey) return sendJson(res, 404, { error: 'not set up' });
    let o;
    try { o = JSON.parse(await body(req, 40000)); }
    catch (e) { return sendJson(res, 400, { error: 'bad json' }); }
    if (!sameSecret(String(o.key || ''), String(cfg.botKey))) {
      return sendJson(res, 401, { error: 'no' });
    }
    const title = String(o.title || '').trim().slice(0, 200);
    if (!title) return sendJson(res, 400, { error: 'no title' });
    const list = jsonFile(INBOX, []);
    list.unshift({
      id: 'i' + Date.now().toString(36) + crypto.randomBytes(2).toString('hex'),
      kind: 'ticket',
      ticket: String(o.kind || '').slice(0, 20),
      title,
      detail: String(o.detail || '').slice(0, 20000),
      by: String(o.by || '').slice(0, 60),
      discordId: String(o.discordId || '').replace(/[^0-9]/g, '').slice(0, 20),
      at: Date.now(),
      state: 'new',
      from: 'the Discord bot'
    });
    if (!putJson(INBOX, list.slice(0, 2000))) {
      return sendJson(res, 500, { error: 'could not save' });
    }
    return sendJson(res, 200, { ok: true });
  }

  if (route === '/api/roadmap' && req.method === 'GET') {
    const all = readBoard();
    return sendJson(res, 200, all.roadmap || { intro:'', sections:[] });
  }

  if (route === '/api/releases' && req.method === 'GET') {
    const feed = jsonFile(NEWS, { launcher:'', news: [] });
    // PowerShell writes a one item list as a bare string, so entries with a
    // single detail line arrived here as text rather than a list. The page then
    // called .map on a string, threw, and the catch around the fetch told
    // everybody the whole news page could not load. Take either shape and hand
    // out one of them, so no writer upstream can blank the page again.
    const asList = (v) => (Array.isArray(v)
      ? v.filter((x) => x !== null && x !== undefined && x !== '').map(String)
      : (v === null || v === undefined || v === '' ? [] : [String(v)]));
    return sendJson(res, 200, {
      launcher: feed.launcher || '',
      news: (feed.news || []).slice(0, 60).map((n) => ({
        date: n.date, title: n.title, body: n.body || '',
        details: asList(n.details), files: asList(n.files).length
      }))
    });
  }

  const pg = route.match(/^\/api\/page\/([a-z-]+)$/);
  if (pg && req.method === 'GET') {
    const file = path.join(SITE, pg[1] + '.md');
    if (!file.startsWith(SITE + path.sep) || !fs.existsSync(file)) {
      return sendJson(res, 404, { error: 'no such page' });
    }
    return sendJson(res, 200, { md: fs.readFileSync(file, 'utf8') });
  }

  // Pictures chosen for the gallery are public. Everything else in uploads is
  // not, which is why this is a separate door with its own list.
  const shot = route.match(/^\/shot\/([a-z0-9._ -]+)$/);
  if (shot && req.method === 'GET') {
    const ok = jsonFile(path.join(DATA, 'gallery.json'), [])
      .some((g) => String(g.name).toLowerCase() === shot[1]);
    const file = path.join(UP, shot[1]);
    if (!ok || !file.startsWith(UP + path.sep) || !fs.existsSync(file)) {
      return send(res, 404, 'no such picture', 'text/plain');
    }
    const st = fs.statSync(file);
    res.writeHead(200, {
      'Content-Type': KIND[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Content-Length': st.size,
      'Cache-Control': 'public, max-age=86400',
      'X-Content-Type-Options': 'nosniff'
    });
    return fs.createReadStream(file).pipe(res);
  }

  // ---------------------------------------------------------------- static
  if (req.method === 'GET' &&
      (p === '/index.html' || Object.prototype.hasOwnProperty.call(PAGES, route))) {
    try { return send(res, 200, fs.readFileSync(path.join(PUBLIC, 'index.html')), TYPES['.html']); }
    catch (e) { return send(res, 500, 'no index.html', 'text/plain'); }
  }
  if (req.method === 'GET' && /^\/[A-Za-z0-9._-]+$/.test(p)) {
    const file = path.join(PUBLIC, p.slice(1));
    if (file.startsWith(PUBLIC + path.sep) && fs.existsSync(file)) {
      return send(res, 200, fs.readFileSync(file), TYPES[path.extname(file)] || 'text/plain');
    }
  }

  // ------------------------------------------------------------- downloads
  // Streamed, not read into memory. The installer is most of a gigabyte and
  // reading it up front would hold all of that per person downloading.
  const dl = p.match(/^\/file\/([A-Za-z0-9._ -]+)$/);
  if (dl && req.method === 'GET') {
    const file = path.join(FILES, dl[1]);
    if (!file.startsWith(FILES + path.sep) || !fs.existsSync(file)) {
      return send(res, 404, 'no such file', 'text/plain');
    }
    const st = fs.statSync(file);
    res.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Content-Length': st.size,
      'Content-Disposition': 'attachment; filename="' + path.basename(file) + '"'
    });
    return fs.createReadStream(file).pipe(res);
  }

  // --------------------------------------------------------------- uploads
  const up = p.match(/^\/up\/([A-Za-z0-9._ -]+)$/);
  if (up && req.method === 'GET') {
    if (!w.member) return send(res, 401, 'sign in first', 'text/plain');
    const file = path.join(UP, up[1]);
    if (!file.startsWith(UP + path.sep) || !fs.existsSync(file)) {
      return send(res, 404, 'no such file', 'text/plain');
    }
    const st = fs.statSync(file);
    const kind = KIND[path.extname(file).toLowerCase()];
    const inline = kind && !url.searchParams.get('dl');
    res.writeHead(200, {
      'Content-Type': inline ? kind : 'application/octet-stream',
      'Content-Length': st.size,
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Content-Disposition': (inline ? 'inline' : 'attachment') +
        '; filename="' + path.basename(file) + '"'
    });
    return fs.createReadStream(file).pipe(res);
  }

  if (p === '/api/upload' && req.method === 'POST') {
    if (!w.member) return sendJson(res, 401, { error: 'sign in first' });
    const CAP = 200 * 1024 * 1024;
    if (Number(req.headers['content-length'] || 0) > CAP) {
      return sendJson(res, 413, { error: 'that file is over 200 MB' });
    }
    const asked = (url.searchParams.get('name') || 'file').split(/[\\/]/).pop();
    const safe = asked.replace(/[^A-Za-z0-9._ -]/g, '_').replace(/^[. ]+/, '')
                      .slice(0, 90) || 'file';
    const d = new Date();
    const two = (n) => String(n).padStart(2, '0');
    const stamp = d.getFullYear() + two(d.getMonth() + 1) + two(d.getDate()) + '-' +
                  two(d.getHours()) + two(d.getMinutes());
    let name = stamp + '-' + safe, n = 2;
    while (fs.existsSync(path.join(UP, name))) { name = stamp + '-' + n + '-' + safe; n++; }
    const dest = path.join(UP, name);

    let got = 0, over = false;
    const out = fs.createWriteStream(dest);
    req.on('data', (c) => { got += c.length; if (got > CAP) { over = true; req.destroy(); out.destroy(); } });
    req.on('error', () => { over = true; });
    req.pipe(out);
    return out.on('close', () => {
      if (over) {
        try { fs.unlinkSync(dest); } catch (e) { }
        return sendJson(res, 413, { error: 'that file is over 200 MB' });
      }
      const meta = jsonFile(UPMETA, {});
      meta[name] = {
        orig: asked,
        by:   (url.searchParams.get('by')   || '').slice(0, 40),
        note: (url.searchParams.get('note') || '').slice(0, 300),
        at:   Date.now()
      };
      putJson(UPMETA, meta);
      sendJson(res, 200, { ok: true, name });
    });
  }

  const rm = p.match(/^\/api\/upload\/([A-Za-z0-9._ -]+)$/);
  if (rm && req.method === 'DELETE') {
    if (!w.admin) return sendJson(res, 403, { error: 'admins only' });
    const file = path.join(UP, rm[1]);
    if (!file.startsWith(UP + path.sep)) return sendJson(res, 400, { error: 'no' });
    try { fs.unlinkSync(file); } catch (e) { }
    const meta = jsonFile(UPMETA, {});
    delete meta[rm[1]];
    putJson(UPMETA, meta);
    return sendJson(res, 200, { ok: true });
  }

  // -------------------------------------------------------------- the door
  /*
    What the launcher talks to. The person links Discord once, the launcher
    keeps a signed ticket, and every launch it asks here whether that ticket is
    still somebody who is allowed in. The answer carries the server password,
    so the password is no longer a thing written in version.json for anybody
    who has ever installed the game to keep forever.

    Every call re-asks Discord. Leaving the server, or being handed the Banned
    role, stops the next launch working, with nothing to remember to do.
  */
  if (p === '/api/play/join' && req.method === 'POST') {
    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { }
    const t = readTicket(o.ticket);
    if (!t) return sendJson(res, 401, { ok:false, why:'link', message:
      'This copy is not linked to a Discord account yet.' });

    const st = await standing(t.d);
    standCache.delete(String(t.d));
    if (!st.inGuild) return sendJson(res, 403, { ok:false, why:'guild', message:
      'That Discord account is not in the Thornswood Discord.',
      invite: cfg.discord.invite || '' });
    if (st.banned) return sendJson(res, 403, { ok:false, why:'banned', message:
      'That Discord account is banned from Thornswood.' });
    if (!st.play) return sendJson(res, 403, { ok:false, why:'role', message:
      'That Discord account has no role that lets it in yet.',
      invite: cfg.discord.invite || '' });
    // The dev build checks in as channel dev. It is for the roles in
    // access.dev (Owner and Dev unless config.json says otherwise); anyone
    // else is sent back to the main build with a plain reason.
    const wantsDev = String(o.channel || '') === 'dev';
    if (wantsDev && !st.dev) return sendJson(res, 403, { ok:false, why:'dev', dev: false, message:
      'The dev build is for the ' + (cfg.access.dev || []).join(' and ') + ' roles. Play on the main build.' });

    const linked = jsonFile(LINKED, {});
    const was = linked[t.d] || {};
    // The launcher sends the profile id it is about to play as. The game
    // server never sees a Discord account, only this number, so this is the
    // one place the two get tied together, and /api/allowed hands the numbers
    // back to the server's door. A person has a couple of character slots, so
    // it is a short list rather than one value.
    const pid = Number(o.profileId) || 0;
    const profiles = Array.isArray(was.profiles) ? was.profiles.slice() : [];
    if (pid > 0 && profiles.indexOf(pid) < 0) profiles.push(pid);
    linked[t.d] = Object.assign(was, {
      id: String(t.d), name: st.name || t.n,
      first: was.first || Date.now(), seen: Date.now(),
      played: Date.now(), roles: st.roles,
      profiles: profiles.slice(-8)
    });
    putJson(LINKED, linked);

    return sendJson(res, 200, {
      ok: true,
      id: st.id,
      name: st.name || t.n,
      admin: st.admin,
      dev: !!st.dev,
      roles: st.roles,
      password: cfg.serverPassword || ''
    });
  }

  /*
    What the game server's door asks for, every five minutes, with the bot key:
    the profile ids of everyone currently allowed in. Everyone who has ever
    checked in through the launcher is re-asked of Discord, so leaving the
    server or picking up the Banned role drops their numbers off the list
    within a refresh. If any lookup failed the answer says so and the door
    keeps the list it had, because a short list built while Discord was down
    would turn away everybody missing from it.
  */
  // The dev server's door.json names the site as https://thornswood.net/dev,
  // so its question lands here and gets only the people the dev build is
  // for. Same key, same shape, shorter list.
  const devDoor = (route === '/dev/api/allowed');
  if ((route === '/api/allowed' || devDoor) && req.method === 'GET') {
    if (!cfg.botKey) return sendJson(res, 404, { error: 'not set up' });
    if (!sameSecret(String(url.searchParams.get('key') || ''), String(cfg.botKey))) {
      return sendJson(res, 401, { error: 'no' });
    }
    const linked = jsonFile(LINKED, {});
    const out = { profiles: [], people: [], lookupFailed: false, at: Date.now() };
    const seen = new Set();
    for (const d of Object.keys(linked)) {
      const row = linked[d] || {};
      const profiles = (Array.isArray(row.profiles) ? row.profiles : [])
        .map(Number).filter((n) => n > 0);
      if (!profiles.length) continue;
      let st;
      try { st = await standingCached(String(d)); } catch (e) { st = { lookupFailed: String(e) }; }
      if (st.lookupFailed) { out.lookupFailed = true; continue; }
      if (!st.play || st.banned) continue;
      if (devDoor && !st.dev) continue;
      for (const n of profiles) if (!seen.has(n)) { seen.add(n); out.profiles.push(n); }
      out.people.push({ id: String(d), name: st.name || row.name || '', profiles });
    }
    return sendJson(res, 200, out);
  }

  /*
    Does this ticket own this profile number?

    The voice service asks, because /choose cannot be locked to the loopback:
    every person's launcher posts their character creation choice to it from
    their own machine. Without an answer here it took anybody's word for
    anything, and a stranger could set your profession, your half and your
    home town before you ever claimed them.

    This route did not exist. voice-server.js has been posting here since it
    was written, every call fell through to the sign in gate below and came
    back 401, owns() reads anything that is not a 200 as "unchecked", and the
    service stored the choice anyway and logged UNVERIFIED. So the check has
    never once run, and the ticket the launcher sends to the voice port in
    clear was being spent on nothing.

    Claimed, not registered. A profile number that nobody has ever checked in
    with belongs to whoever asks for it first, which is the launcher that just
    made the character: refusing those would break character creation for
    every new character, which is the one case this runs in. A number already
    against somebody else's Discord account is theirs, and that is the case
    worth refusing.
  */
  if (p === '/api/play/owns' && req.method === 'POST') {
    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { }
    const t = readTicket(o.ticket);
    if (!t) return sendJson(res, 200, { ok: false, why: 'ticket' });
    const pid = Number(o.profileId) || 0;
    if (pid <= 0) return sendJson(res, 200, { ok: false, why: 'profile' });

    // Still has to be somebody who is allowed in at all. A ticket from an
    // account that has been banned or has left owns nothing.
    const st = await standingCached(t.d);
    if (!st.play || st.banned) return sendJson(res, 200, { ok: false, why: 'role' });

    const linked = jsonFile(LINKED, {});
    const mine = (linked[t.d] && Array.isArray(linked[t.d].profiles))
      ? linked[t.d].profiles.map(Number) : [];
    if (mine.indexOf(pid) >= 0) return sendJson(res, 200, { ok: true, why: 'theirs' });

    for (const d of Object.keys(linked)) {
      if (String(d) === String(t.d)) continue;
      const theirs = (linked[d] && Array.isArray(linked[d].profiles))
        ? linked[d].profiles.map(Number) : [];
      if (theirs.indexOf(pid) >= 0) {
        return sendJson(res, 200, { ok: false, why: 'somebody else' });
      }
    }
    // Nobody has it. The launcher that just made the character is the one
    // asking, and it checks in with this number a moment later anyway.
    return sendJson(res, 200, { ok: true, why: 'unclaimed' });
  }

  // The same question without asking for the password, for the launcher to
  // show who it is linked as without pretending it is about to connect.
  if (p === '/api/play/who' && req.method === 'POST') {
    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { }
    const t = readTicket(o.ticket);
    if (!t) return sendJson(res, 401, { ok:false, why:'link' });
    const st = await standingCached(t.d);
    return sendJson(res, st.play && !st.banned ? 200 : 403, {
      ok: st.play && !st.banned, id: st.id, name: st.name || t.n,
      admin: st.admin, dev: !!st.dev, banned: st.banned, inGuild: st.inGuild, roles: st.roles
    });
  }

  // ------------------------------------------------------------------- api
  if (p.startsWith('/api/')) {
    if (!w.member) return sendJson(res, 401, { error: 'sign in first' });

    if (p === '/api/all' && req.method === 'GET') {
      const docs = {}, boards = {};
      for (const n of Object.keys(DOCS))   if (allowed(n, w)) docs[n]   = readDoc(n);
      const all = readBoard();
      for (const n of Object.keys(BOARDS)) if (allowed(n, w)) boards[n] = all[n] || { intro:'', sections:[] };
      return sendJson(res, 200, {
        me: w,
        titles: Object.assign({}, DOCS, BOARDS),
        level: LEVEL,
        docs, boards,
        results: jsonFile(RESULTS, {}),
        files: listFiles(),
        uploads: listUploads(),
        news: jsonFile(NEWS, { launcher:'', news: [] }),
        invite: cfg.discord.invite || '',
        linked: w.admin ? Object.values(jsonFile(LINKED, {})) : [],
        inbox: w.admin ? jsonFile(INBOX, []) : []
      });
    }

    if (p === '/api/results' && req.method === 'PUT') {
      let obj;
      try { obj = JSON.parse(await body(req)); }
      catch (e) { return sendJson(res, 400, { error: 'bad json' }); }
      if (!putJson(RESULTS, obj)) return sendJson(res, 500, { error: 'could not save' });
      return sendJson(res, 200, { ok: true });
    }

    // ------------------------------------------------------- admins only --
    if (!w.admin) return sendJson(res, 403, { error: 'admins only' });

    const md = p.match(/^\/api\/doc\/([a-z]+)$/);
    if (md && req.method === 'PUT') {
      if (!writeDoc(md[1], await body(req))) return sendJson(res, 400, { error: 'no such doc' });
      return sendJson(res, 200, { ok: true });
    }

    const mb = p.match(/^\/api\/board\/([a-z]+)$/);
    if (mb && req.method === 'PUT') {
      let obj;
      try { obj = JSON.parse(await body(req)); }
      catch (e) { return sendJson(res, 400, { error: 'bad json' }); }
      if (!writeBoardOne(mb[1], obj)) return sendJson(res, 400, { error: 'no such board' });
      return sendJson(res, 200, { ok: true });
    }

    if (p === '/api/inbox' && req.method === 'PUT') {
      let obj;
      try { obj = JSON.parse(await body(req)); }
      catch (e) { return sendJson(res, 400, { error: 'bad json' }); }
      if (!putJson(INBOX, obj)) return sendJson(res, 500, { error: 'could not save' });
      return sendJson(res, 200, { ok: true });
    }

    return sendJson(res, 404, { error: 'no such endpoint' });
  }

  send(res, 404, 'not here', 'text/plain');
}).listen(PORT, BIND, () => {
  console.log('[thornswood-docs] listening on ' + BIND + ':' + PORT);
  console.log('[thornswood-docs] documents in ' + DATA);
  console.log('[thornswood-docs] downloads in ' + FILES);
  console.log('[thornswood-docs] uploads in ' + UP);
  console.log('[thornswood-docs] watching the game on 127.0.0.1:' +
    (cfg.gameCheckPort || 3000) + ' (the game plays on UDP ' +
    (cfg.gamePort || 7777) + ', which cannot be probed), count from ' + cfg.onlineFile);
  console.log('[thornswood-docs] discord login ' +
    (cfg.discord.clientId ? 'ready' : 'NOT SET UP') +
    ', guild check ' + (cfg.discord.botToken && cfg.discord.guildId ? 'on' : 'OFF') +
    ', server password ' + (cfg.serverPassword ? 'held' : 'NOT SET'));

  /* Ask Discord once on the way up, and say so loudly if it will not answer.
     Without this a dead bot token is invisible from here and shows up as every
     person except the hand written admins being told they are not in the
     server, which is the least useful way to find out. */
  if (cfg.discord.botToken && cfg.discord.guildId) {
    discordGet('/guilds/' + cfg.discord.guildId).then((r) => {
      if (r.ok) {
        console.log('[thornswood-docs] discord bot can read "' +
          String(r.body && r.body.name || '?') + '"');
        return roleNames().then((names) => {
          const n = Object.keys(names || {}).length;
          console.log('[thornswood-docs] ' + n + ' roles visible to the bot');
          if (!n) console.error('[thornswood-docs] NO ROLES VISIBLE. Nobody but the admin list will get in.');
        });
      }
      console.error('[thornswood-docs] THE BOT CANNOT READ THE SERVER: ' + r.why);
      console.error('[thornswood-docs] Until this is fixed everybody except the ids in ' +
                    '"admins" is turned away, and the page tells them so.');
    }).catch(() => { });
  }
});
