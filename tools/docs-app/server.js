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

// ==== thornswood site log ====
//
// EVERYTHING THIS PROCESS WORKED OUT USED TO GO NOWHERE. The scheduled task
// ran node with no redirect at all, so stdout and stderr went into a handle
// nobody held and there was no file anywhere on the box. discordGet works out
// a plain sentence for every failure, because a dead bot token, a rate limit
// and somebody genuinely not in the Discord used to look identical and the
// site told all three of them the same wrong thing. Not one of those
// sentences had ever been readable. It cost most of an evening on 22
// September, and two wrong conclusions, to work out from outside what the
// site already knew.
//
// IN PROCESS RATHER THAN A REDIRECT ON THE TASK, and that is the whole
// design decision. The other three services are launched through cmd with
// >> log 2>&1, and a log held open that way cannot be rolled: Windows
// refuses to move or truncate a file another process has open for append,
// measured rather than assumed. A redirect would have fixed 'there is no
// log' and created 'the log grows until the disk goes', which is another
// entry on the list. Writing it here means this process owns the handle and
// can close, roll and reopen it whenever it likes.
//
// WHAT IS NOT IN IT: addresses. The privacy page says the sign-in log is the
// only thing here that holds one and that it is deleted after thirty days. A
// request log carrying addresses would quietly make that untrue, so this
// holds what the site says about itself and the method and path of anything
// that failed, and never who asked.
function makeLog(dir, name, maxBytes, keep) {
  const file = path.join(dir, name);
  let broken = false;

  function two(n) { return n < 10 ? '0' + n : String(n); }
  function stamp() {
    const d = new Date();
    return d.getFullYear() + '-' + two(d.getMonth() + 1) + '-' + two(d.getDate()) +
           ' ' + two(d.getHours()) + ':' + two(d.getMinutes()) + ':' + two(d.getSeconds());
  }

  // Oldest first, so nothing is overwritten on the way. site.log.5 goes,
  // site.log.4 becomes .5, and site.log becomes .1. Rolled, never deleted:
  // deleting a log is how the evidence for the last crash disappeared in the
  // first place.
  function roll() {
    try {
      const oldest = file + '.' + keep;
      if (fs.existsSync(oldest)) { fs.unlinkSync(oldest); }
      for (let i = keep - 1; i >= 1; i--) {
        const from = file + '.' + i;
        if (fs.existsSync(from)) { fs.renameSync(from, file + '.' + (i + 1)); }
      }
      if (fs.existsSync(file)) { fs.renameSync(file, file + '.1'); }
      return true;
    } catch (e) { return false; }
  }

  function write(line) {
    if (broken) { return false; }
    try {
      let big = false;
      try { big = fs.statSync(file).size >= maxBytes; } catch (e) { big = false; }
      if (big) { roll(); }
      fs.appendFileSync(file, stamp() + '  ' + line + '\n');
      return true;
    } catch (e) {
      // Once, and out loud. A log that throws on every line is worse than no
      // log, and one that goes quiet with no trace is worse than both.
      broken = true;
      try {
        process.stdout.write('[thornswood-docs] could not write ' + file +
                             ', carrying on with the console only: ' + e.message + '\n');
      } catch (e2) { }
      return false;
    }
  }

  return { file: file, write: write, roll: roll, broken: function () { return broken; } };
}

// Four megabytes is a few days of a closed playtest and opens in anything.
// Five kept, so a crash on Saturday night is still readable on Monday.
const siteLog = makeLog(ROOT, 'site.log', 4 * 1024 * 1024, 5);

// Said through the console as well, so running the site by hand is unchanged
// and so a person watching a deploy sees what they always saw. The console
// keeps its own arguments; the file gets one line.
['log', 'error', 'warn'].forEach(function (k) {
  const was = console[k].bind(console);
  console[k] = function () {
    const parts = Array.prototype.slice.call(arguments).map(function (a) {
      if (typeof a === 'string') { return a; }
      if (a instanceof Error) { return a.stack || a.message; }
      try { return JSON.stringify(a); } catch (e) { return String(a); }
    });
    siteLog.write((k === 'log' ? '' : k.toUpperCase() + ' ') + parts.join(' '));
    was.apply(null, arguments);
  };
});
// ==== end thornswood site log ====

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
// Who gets a third character slot at the game's main menu. Everybody gets
// two; a Patreon tier or a Gamemaster gets three, and so do the admin roles.
// Decided by Patrick on 20 September. The tier names are Build-Discord.py's.
if (!Array.isArray(cfg.access.slots3)) {
  cfg.access.slots3 = ['Thalmor Boot-Licker', 'Talos Worshiper', 'Milk Drinker', 'Gamemaster'];
}
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
  news: 'admin', link: 'admin', linked: 'admin', sessions: 'admin',
  active: 'admin', archive: 'admin', todo: 'admin', inbox: 'admin'
};

/* The public front lives at / and needs no password. The working area moved
   to /hub, because a server nobody can read about is a server nobody joins,
   and a login box was the first thing anybody saw. */
const PUBLIC_PAGES = ['/', '/world', '/rules', '/credits', '/join',
                      '/classes', '/roadmap', '/news', '/gallery',
                      '/downloads', '/report',
                      // Known Issues and Help are for the person whose install
                      // will not start or who cannot sign in, so they cannot
                      // sit behind the sign in. They are known.md and help.md
                      // in the data folder, read through /api/page like the
                      // site pages. The hub's own pages moved to /hub/known
                      // and /hub/help to make room.
                      '/known', '/help',
                      // What is kept about somebody and what they are
                      // agreeing to cannot sit behind a sign in, because
                      // the person deciding whether to sign up is the one
                      // who needs to read them.
                      '/privacy', '/terms'];
const PUBLIC_DOCS = ['known', 'help'];
/* The public pages are markdown on disk like everything else here, so the
   wording can be fixed from the site rather than by a deploy. */
const SITE = path.join(DATA, 'site');

/* What a link to each page says when it is pasted into Discord. Every address
   used to unfurl with the same generic home text, so a link to the rules and a
   link to the roadmap read identically in a channel. home.html carries the
   same list for the browser tab; this is the one a crawler sees, because a
   crawler does not run the page's script. */
const BLURB = {
  '/':          ['Thornswood', 'A Skyrim roleplay server set fifty years after the civil war. The world still has people in it.'],
  '/world':     ['The world', 'Fifty years after the Stormcloaks won. A free Skyrim, an Empire with an embassy and no soldiers, and the White Harbour Accord.'],
  '/rules':     ['Rules', 'Nine rules, short on purpose. Nobody dies without agreeing to, play a person rather than a legend, and staff decide.'],
  '/join':      ['How to join', 'What you need, how to apply, and what happens between pressing Play and waking up in an inn.'],
  '/credits':   ['Credits', 'Everyone whose work Thornswood is built on.'],
  '/classes':   ['Professions and classes', 'One profession, one half of it, one class. An Edgewright cannot make armour, so you find somebody who can.'],
  '/known':     ['Known issues', 'What is limited or broken right now and why, and which of it is on the roadmap. Read this before reporting anything.'],
  '/help':      ['Help', 'Installing, the collection, LOAD ORDER ERROR, and where the logs are.'],
  '/downloads': ['Download', 'What you need, the installer, and the collection in Vortex.'],
  '/roadmap':   ['Roadmap', 'What is being worked on and roughly in what order.'],
  '/news':      ['Every release', 'What changed, newest first. The same list the launcher shows.'],
  '/report':    ['Report a problem', 'Something broken, or an idea. No account needed.'],
  '/gallery':   ['From the world', 'Pictures taken by people playing.'],
  '/privacy':   ['Privacy', 'What Thornswood keeps about you, why, and how to have it deleted. No advertising tag and no analytics.'],
  '/terms':     ['Terms', 'Eighteen and over, play by the rules, your account is yours, and nothing here is charged for or promised.']
};
const escAttr = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;')
  .replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const PAGES = {
  '/hub':         'home',
  '/hub/help':    'help',
  '/hub/known':   'known',
  '/roadmap':     'roadmap',
  '/suggestions': 'suggestions',
  '/news':        'news',
  '/testthese':   'tests',
  '/uploads':     'uploads',
  '/link':        'link',
  '/linked':      'linked',
  '/sessions':    'sessions',
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
    //
    // A script is never something a visitor is offered. A read only
    // diagnostic for one machine once sat in this folder and so on the
    // Downloads page as a file to take, naming a staff member and the game
    // server's address. Anything with a script extension is hidden whatever
    // files.json says about it.
    const script = /[.](ps1|psm1|cmd|bat|py|sh)$/i.test(name);
    // The installer's SHA-256, which Publish-Installer writes, so the Downloads
    // page can print it beside the size and date and link VirusTotal's report
    // on it (To Do entry 176). Only a well formed hash goes out, in lower case
    // because Get-FileHash writes upper and the page builds an address from it.
    const sha256 = String(m.sha256 || '').toLowerCase();
    out.push({ name, size: st.size, at: st.mtimeMs, hidden: !!m.hidden || script,
      label: m.label || name, version: m.version || '', note: m.note || '',
      sha256: /^[0-9a-f]{64}$/.test(sha256) ? sha256 : '' });
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

/*
  One byte range, when a client asks for one. Answers 206 or 416 and returns
  true, or returns false when there is no range to honour and the caller sends
  its own 200.

  The static files had this and /file/ did not. /file/ is where the installer
  gets its payload, and Bootstrap.cs asks for the rest of a half downloaded zip
  with a Range header and appends whatever a 206 brings. The site answered
  every such request 200 with the whole file and no Accept-Ranges, so a
  connection that dropped at 300 MB started again from nothing, while the Join
  page promises it carries on. The To Do List has it measured live: a Range
  request for the payload came back 200 with the full length.

  A 206 that starts anywhere but the byte asked for is written onto the end of
  the partial file and corrupts it with nothing to notice, so the start is
  exactly the number in the header and test-file-range.js holds it there.

  headers are the ones this file is served with (content-type, and on /file/
  the attachment name and its validators), lower case so none is sent twice.
  When they carry an etag or last-modified, an If-Range that names neither is
  a client resuming a file that has since changed, and it gets the whole new
  file rather than the tail of it. head is a HEAD: headers only, and a HEAD
  with a range on the installer does not read half a gigabyte to throw away.
*/
function rangeReply(req, res, file, size, headers, head) {
  const range = req.headers.range;
  const m = range && /^bytes=(\d*)-(\d*)$/.exec(String(range).trim());
  if (!m) return false;
  const ifRange = req.headers['if-range'];
  if (ifRange && (headers.etag || headers['last-modified']) &&
      ifRange !== headers.etag && ifRange !== headers['last-modified']) return false;
  let start = m[1] === '' ? null : parseInt(m[1], 10);
  let end = m[2] === '' ? null : parseInt(m[2], 10);
  // bytes=-500 means the LAST 500, not "from 0 to 500".
  if (start === null && end !== null) { start = Math.max(0, size - end); end = size - 1; }
  if (start !== null && end === null) { end = size - 1; }
  if (start === null || start > end || start >= size) {
    res.writeHead(416, {
      'content-range': 'bytes */' + size,
      'accept-ranges': 'bytes',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff'
    });
    res.end();
    return true;
  }
  end = Math.min(end, size - 1);
  // send() puts the last two on every other answer; a range must not be the
  // one reply that quietly goes out without them.
  res.writeHead(206, Object.assign({}, headers, {
    'content-range': 'bytes ' + start + '-' + end + '/' + size,
    'content-length': (end - start) + 1,
    'accept-ranges': 'bytes',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff'
  }));
  if (head) { res.end(); return true; }
  fs.createReadStream(file, { start: start, end: end }).pipe(res);
  return true;
}

function body(req, cap) {
  return new Promise((resolve) => {
    let out = '';
    req.on('data', (d) => { out += d; if (out.length > (cap || 4000000)) req.destroy(); });
    req.on('end', () => resolve(out));
  });
}

/*
  What each extension is served as. Anything not named here falls through to
  text/plain, which is right for robots.txt and wrong for everything binary.

  .jpg and .mp4 were both missing on 20 September and both were needed the same
  day: the front page's hero became a video with a still as its poster, and the
  site served them as text/plain. A browser will not play a video it is told is
  text, so the hero was simply blank and the reasonable reading from the outside
  was that the wrong picture had been published. It had not; it was unplayable.

  Wrong Content-Type is a bad failure because nothing errors. The file arrives,
  200, the right bytes, and the browser quietly declines to do anything with it.
*/
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp',
  '.gif': 'image/gif', '.avif': 'image/avif',
  '.mp4': 'video/mp4', '.webm': 'video/webm', '.m4v': 'video/mp4',
  '.woff2': 'font/woff2', '.woff': 'font/woff'
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
/*
  Who is banned, by Discord id, beside the people who are linked.

  THE ROLE WAS THE ONLY THING A BAN RESTED ON and the role did not exist: the
  builder makes eighteen roles and Banned was not among them until 23
  September, so every ban depended on somebody making it by hand and spelling
  it the way cfg.access.banned spells it. A capital letter in the wrong place
  was the difference between a ban and nothing at all, silently.

  This is the other half. A file of ids is not spelled, cannot be renamed by
  somebody tidying the Discord, and works when the bot is not in the guild,
  when the guild lookup fails and when the bot has not been configured at all,
  which is the branch that used to hand play to everybody.

  Shape: {"<discord id>": {"at": <unix ms>, "by": "<id or name>", "why": "..."}}
  Nothing here writes it yet. It is read on every standing() and a missing file
  means nobody is banned, which is what an empty server looks like.
*/
const BANS = path.join(DATA, 'bans.json');
// The game server's character roster, pushed here by the gamemode with the
// door key (POST /api/roster) and handed back per person (POST /api/play/roster).
// Keyed by profile id; live and dev both push into it, their ids never meet.
const ROSTER = path.join(DATA, 'roster.json');

/* How many character slots this person gets at the game's main menu. */
function slotsFor(st) {
  if (!st) return 2;
  if (st.admin || st.dev) return 3;
  const roles = Array.isArray(st.roles) ? st.roles : [];
  return (cfg.access.slots3 || []).some((n) => roles.indexOf(n) >= 0) ? 3 : 2;
}

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

// ==== thornswood signin ageing ====
//
// A COUNT IS NOT A RETENTION RULE. This was capped at 500 rows and nothing
// else, so on a quiet closed playtest a row could sit here for a year: a
// Discord id, a handle, a display name and the address it was reached from.
// The reason the log exists is to answer "has anybody been poking at the
// admin panel", and that question is about the last few weeks, not about
// last spring.
//
// So it is aged by time as well as by count, and the ageing runs on the way
// OUT as well as the way in. Ageing only on write means a month with no
// sign-ins leaves everything sitting there, and the file that is meant to
// have emptied itself has not.
//
// Thirty days, and the privacy page says so, which is the point: a promise
// about what is kept is worth nothing if nothing enforces it.
//
// A row with no usable time is kept rather than dropped. It is a corrupt
// row either way, and throwing away the record of somebody being refused at
// the door because its timestamp would not parse is the wrong way to be
// wrong.
const ATTEMPTS_KEEP = 500;
const ATTEMPTS_DAYS = 30;
function freshSignIns(rows, now) {
  const list = Array.isArray(rows) ? rows : [];
  const cut = (Number(now) || Date.now()) - (ATTEMPTS_DAYS * 24 * 60 * 60 * 1000);
  const kept = [];
  for (const r of list) {
    if (!r || typeof r !== 'object') continue;
    const at = Number(r.at);
    if (isFinite(at) && at > 0 && at < cut) continue;
    kept.push(r);
  }
  return kept.slice(0, ATTEMPTS_KEEP);
}
// ==== end thornswood signin ageing ====

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
    putJson(ATTEMPTS, freshSignIns(rows, Date.now()));
  } catch (e) { }
}

/* Who played, when they started, when they stopped, and on which build.
 *
 * linked.json holds a last played stamp, which answers "has this person ever
 * pressed Play" and nothing else: not how long they were in, not whether they
 * are still in now, not which build it was. Djinn asked on 20 September for a
 * sheet testers are logged in and out of, and this is the record behind it.
 *
 * One row a session. Newest LAST, the way a log is written, and capped so the
 * file cannot grow without bound on the VPS. Two thousand sessions is years of
 * a closed playtest. */
const SESSIONS = path.join(DATA, 'sessions.json');
const SESSIONS_KEEP = 2000;

function sessionRows() {
  const list = jsonFile(SESSIONS, []);
  return Array.isArray(list) ? list : [];
}
function putSessions(rows) {
  return putJson(SESSIONS, rows.slice(-SESSIONS_KEEP));
}

/* The id the launcher made for one session: its characters only, so nothing
   sent from outside can carry a path or punctuation into the file, and long
   enough to be a real id rather than a stub somebody typed. */
function sessionKey(v) {
  const s = String(v == null ? '' : v).replace(/[^A-Za-z0-9-]/g, '').slice(0, 64);
  return s.length >= 8 ? s : '';
}

/* The row this session id made FOR THIS ACCOUNT. Both halves matter: a ticket
   is only ever allowed to write its own rows, so an id that somebody else
   started is not this account's to start, end or annotate. Newest first,
   because a re-used id should find the row still open. */
function findSession(rows, key, who) {
  for (let i = rows.length - 1; i >= 0; i--) {
    if (rows[i] && rows[i].session === key && String(rows[i].who) === String(who)) return i;
  }
  return -1;
}

/* ------------------------------------------------------- session logs -- */
/*
  The logs from one session, so a report can be read without asking the person
  to find four files and paste them.

  The client half is sent by the launcher when the game closes, which is the
  only moment it can be: the game wipes its own logs at every start, so by the
  time anybody asks for them they are gone. One file per session id.

  The server half is not stored at all. It is sliced out of the game server's
  own log on demand, by the session's start and end, because that log is
  already on this box and copying lines out of it into another file would be
  two copies of the same thing going stale against each other.

  THIS IS EVIDENCE, and it is written to be usable as evidence when somebody
  is suspended or banned. Three things follow from that and none of them is
  optional.

  WRITE ONCE. A session's logs can be sent once. A second upload for the same
  id is refused and the refusal is recorded. Without that, anybody who knew the
  endpoint could play, do something worth banning for, and then post a clean
  set over the top from the same launcher; the evidence would be whatever the
  accused chose to send last, which is no evidence at all.

  PROVENANCE IN THE FILE. Each set records the Discord id off the TICKET, not
  off the body, when it arrived, and a sha256 of every log. The hash is not
  security theatre: it is so that a copy pasted into a Discord argument months
  later can be held against the one on the box and shown to be the same text.

  KEPT BY AGE, NOT BY THE ROLLING LIST. sessions.json keeps the last two
  thousand rows. Tying the logs to that would quietly delete the evidence for
  an old incident the moment two thousand newer sessions had happened, which
  on a public server is weeks. They are kept for SLOG_DAYS instead, and a
  session whose row is marked kept is never pruned at all.

  WHAT THIS DOES NOT COVER, and it matters for the ban case: nothing here is a
  record of what anybody SAID. Chat and voice are not logged anywhere, so an
  argument about behaviour between two people is still one person's word
  against another's. That is its own piece of work and this is not it.

  Caps, because this accepts a body from every launcher: one log is trimmed to
  its last 256 KB (the end is the part with the fault in it) and a whole set to
  1 MB.
*/
const SLOGS = path.join(DATA, 'session-logs');
const SLOG_ONE = 256 * 1024;
const SLOG_ALL = 1024 * 1024;
const SLOG_DAYS = 365;

/* The names the launcher may send. Anything else is dropped rather than
   written: this is a path coming from outside, and a file name is the shortest
   way into a folder nobody meant to write. */
const SLOG_NAMES = [
  'launcher.log', 'thornswood-front.log', 'thornswood-voice.log',
  'thornswood-emotes.log', 'thornswood-input.log', 'thornswood-dress.log',
  'thornswood-loadorder.txt', 'thornswood-plugins-light.txt'
];

function slogFile(key) { return path.join(SLOGS, key + '.json'); }

/* The tail of a log, never the head. A crash is at the end. */
function slogTrim(s, cap) {
  const t = String(s == null ? '' : s);
  if (t.length <= cap) return t;
  return '... the first ' + (t.length - cap) + ' characters are not kept ...\n' +
         t.slice(t.length - cap);
}

/* Written once. Returns 'saved', 'already' or 'nothing'. */
function putSessionLogs(key, who, logs) {
  try {
    if (!fs.existsSync(SLOGS)) fs.mkdirSync(SLOGS, { recursive: true });
    const file = slogFile(key);

    /* Write once. A second set for the same session is not written over the
       first; the attempt is recorded on the original so a replay shows up as
       what it is rather than as nothing. */
    if (fs.existsSync(file)) {
      try {
        const had = JSON.parse(fs.readFileSync(file, 'utf8')) || {};
        had.resent = (Number(had.resent) || 0) + 1;
        had.resentAt = Date.now();
        fs.writeFileSync(file, JSON.stringify(had));
      } catch (e) { }
      return 'already';
    }

    const keep = {};
    const hash = {};
    let total = 0;
    for (const name of SLOG_NAMES) {
      if (!Object.prototype.hasOwnProperty.call(logs, name)) continue;
      const text = slogTrim(logs[name], SLOG_ONE);
      if (!text.trim()) continue;
      if (total + text.length > SLOG_ALL) continue;
      total += text.length;
      keep[name] = text;
      hash[name] = crypto.createHash('sha256').update(text, 'utf8').digest('hex');
    }
    if (!Object.keys(keep).length) return 'nothing';

    fs.writeFileSync(file, JSON.stringify({
      session: key,
      who: String(who),      /* off the ticket, never off the body */
      at: Date.now(),
      bytes: total,
      sha256: hash,
      logs: keep
    }));
    return 'saved';
  } catch (e) { return 'nothing'; }
}

/*
  Old log sets go, by age.

  NOT by whether the session is still in sessions.json. That file keeps the
  last two thousand rows, so tying the logs to it would delete the evidence
  for an old incident the moment two thousand newer sessions had happened, and
  on a public server that is weeks. A row marked kept is never pruned, so
  anything an argument rests on can be held indefinitely by marking it.
*/
function pruneSessionLogs() {
  try {
    if (!fs.existsSync(SLOGS)) return;
    const cutoff = Date.now() - SLOG_DAYS * 86400000;
    const held = new Set(sessionRows().filter(r => r && r.keep).map(r => String(r.session)));
    for (const f of fs.readdirSync(SLOGS)) {
      if (!f.endsWith('.json')) continue;
      const key = f.slice(0, -5);
      if (held.has(key)) continue;
      const full = path.join(SLOGS, f);
      let at = 0;
      try { at = Number((JSON.parse(fs.readFileSync(full, 'utf8')) || {}).at) || 0; } catch (e) { at = 0; }
      if (!at) { try { at = fs.statSync(full).mtimeMs; } catch (e) { at = Date.now(); } }
      if (at < cutoff) { try { fs.unlinkSync(full); } catch (e) { } }
    }
  } catch (e) { }
}

/*
  Did this session go wrong, and how badly?

  Decided by reading the logs it sent, once, as they arrive, rather than by
  asking somebody to go and look.

  TWO LEVELS, because they want two different things done about them.

  BAD is a crash or a throw: the session broke under the person and there was
  nothing they could have done. That colours the session red and the bot says
  so in the staff channel, because somebody should go and look now.

  WARN is the session failing for a reason that is already understood and has
  a known fix: an update that did not install, a load order that does not
  match, a mod missing or in the wrong place. That colours the session yellow
  and says NOTHING in Discord. These are common, they are self-inflicted by a
  machine rather than by the code, and a message for each one would make the
  staff channel unreadable, which is the same as having no channel.

  THE MARKERS ARE DELIBERATELY FEW. A test that matches "error" anywhere turns
  every session red, and a page where everything is red says exactly as much
  as a page where nothing is.

  Red is looked for first, so a session that both crashed AND had a load order
  complaint is red. First match wins and the line is kept with it, because
  "which session went wrong" is only half the question and "what did it say"
  is the other half.
*/
const TROUBLE_BAD = [
  ['Unhandled exception', 'something threw and nothing caught it'],
  ['Unhandled Exception', 'something threw and nothing caught it'],
  ['Uncaught ',           'a script threw and nothing caught it'],
  ['TypeError:',          'a script hit a TypeError'],
  ['ReferenceError:',     'a script hit a ReferenceError'],
  ['has crashed',         'the game crashed'],
  ['crashed with',        'the game crashed'],
  ['FATAL',               'something fatal']
];

const TROUBLE_WARN = [
  ['Update failed',                 'an update did not install'],
  ['being used by another process', 'an update could not write a file something else had open'],
  ['LOAD ORDER ERROR',              'the game refused them over the load order'],
  ['load order is not the server',  'their load order did not match the server'],
  ['does not match the server',     'their load order did not match the server'],
  ['is missing, install it in Vortex', 'a mod is not installed'],
  ['skymp5-client.js is missing',   'the client is not in place'],
  ['plugins.txt is missing',        'their plugin list was missing'],
  ['did not answer, so it is not known whether this build is current',
                                    'the update feed did not answer, so Play stayed shut']
];

function lineAround(text, at) {
  const from = text.lastIndexOf('\n', at) + 1;
  let to = text.indexOf('\n', at);
  if (to < 0) to = text.length;
  return text.slice(from, to).trim().slice(0, 300);
}

function scanFor(logs, marks, level) {
  for (const name of Object.keys(logs || {})) {
    const text = String(logs[name] || '');
    for (const [mark, why] of marks) {
      const at = text.indexOf(mark);
      if (at < 0) continue;
      return { level, why, file: name, line: lineAround(text, at) };
    }
  }
  return null;
}

/* Red before yellow: a session that crashed AND complained about its load
   order is a crash, and the crash is the thing worth waking somebody for. */
function readTrouble(logs) {
  return scanFor(logs, TROUBLE_BAD, 'bad') || scanFor(logs, TROUBLE_WARN, 'warn');
}

/*
  The short list of sessions that went wrong, for the bot to read.

  A file rather than an endpoint, because the bot runs on this same box and a
  file needs no ticket, no port and nothing to keep in step. Newest last, the
  last 200, so it cannot grow without bound.
*/
const TROUBLE_FILE = path.join(DATA, 'trouble.json');
const TROUBLE_KEEP = 200;

function noteTrouble(row, found) {
  try {
    const list = jsonFile(TROUBLE_FILE, []);
    const all = Array.isArray(list) ? list : [];
    if (all.some(t => t && t.session === row.session)) return;
    all.push({
      session: row.session,
      who: String(row.who),
      name: String(row.name || ''),
      channel: String(row.channel || ''),
      profile: Number(row.profile) || 0,
      version: String(row.version || ''),
      at: Date.now(),
      why: found.why,
      file: found.file,
      line: found.line
    });
    putJson(TROUBLE_FILE, all.slice(-TROUBLE_KEEP));
  } catch (e) { }
}

/*
  The game server's log between two moments.

  Its lines start "[2026-09-22 10:02:10.155]", which is local time on this box
  and the same clock the session's start and end were stamped with, so they
  compare directly. A line with no stamp belongs to the line above it, which is
  what a stack trace is, so it is kept whenever the last stamped line was.

  dev and main are different servers with different logs; the session says
  which it was on.
*/
const SERVER_LOGS = {
  main: 'C:\\Thornswood-Server\\server.log',
  dev:  'C:\\Thornswood-Server-Dev\\server.log'
};

/* Where the voice service writes what people said. Its folder, not this one:
   it owns the file and this only reads it, so there is one writer and no
   question about which copy is the real one. */
const CHAT_DIR = process.env.THORNSWOOD_CHAT_DIR || 'C:\\Thornswood-Voice\\chat';

/* What this person said during THIS session, and nothing else.

   There used to be a page of its own for the chat log, a day at a time for
   everybody at once. Answering "what did this person do" meant reading a
   session on one page, working out when it ran, then going to another page,
   picking the day and filtering by name, and holding the two together in your
   head. Patrick, 22 September: put it under each person on /sessions, split
   per session. So the page is gone and this is where it lives.

   The split is the profile number and the session's own window. A chat line
   carries profileId and at; a session carries profile, start and end. The
   caller passes the same window it already widened by a minute either side
   for the server log, because the launcher stamps the session and the voice
   service stamps the line, and those moments are not the same moment.

   A session that runs over midnight is in two files, so both days are read.
   A line that will not parse is skipped rather than thrown: an append-only
   log killed mid-write has a truncated last line by design, and one bad line
   must not cost the rest. */
function chatSlice(profileId, from, to) {
  const want = Number(profileId) || 0;
  if (!want) return { ok: true, why: '', lines: [] };
  const days = {};
  for (const at of [from, to]) {
    const d = new Date(at);
    const p = (n) => (n < 10 ? '0' : '') + n;
    days[d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate())] = 1;
  }
  const out = [];
  let read = 0;
  for (const day of Object.keys(days).sort()) {
    let raw = '';
    try { raw = fs.readFileSync(path.join(CHAT_DIR, day + '.jsonl'), 'utf8'); }
    catch (e) { continue; }
    read++;
    for (const l of raw.split('\n')) {
      if (!l.trim()) continue;
      let o;
      try { o = JSON.parse(l); } catch (e) { continue; }
      if (!o) continue;
      if (Number(o.profileId) !== want) continue;
      const at = Number(o.at) || 0;
      if (at < from || at > to) continue;
      out.push({ at: at, kind: String(o.kind || ''), mode: String(o.mode || ''),
                 name: String(o.name || ''), proven: !!o.proven, text: String(o.text || '') });
      if (out.length > 4000) break;
    }
    if (out.length > 4000) break;
  }
  out.sort((a, b) => a.at - b.at);
  /* "Nothing was said" and "the chat log is not on this box" look identical
     once both are an empty list, and only one of them is a fault. */
  return { ok: true, why: read ? '' : 'no chat log for those days on this box', lines: out };
}

function serverLogSlice(channel, from, to) {
  const file = SERVER_LOGS[channel === 'dev' ? 'dev' : 'main'];
  let text = '';
  try {
    if (!fs.existsSync(file)) return { ok: false, why: 'no server log on this box', lines: [] };
    /* Only the tail is read. These grow, and a session is minutes long. */
    const size = fs.statSync(file).size;
    const want = 4 * 1024 * 1024;
    const fd = fs.openSync(file, 'r');
    try {
      const start = Math.max(0, size - want);
      const buf = Buffer.alloc(Math.min(size, want));
      fs.readSync(fd, buf, 0, buf.length, start);
      text = buf.toString('utf8');
      if (start > 0) text = text.slice(text.indexOf('\n') + 1);
    } finally { fs.closeSync(fd); }
  } catch (e) { return { ok: false, why: String(e.message || e), lines: [] }; }

  const out = [];
  let keeping = false;
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\[(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/);
    if (m) {
      const at = new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime();
      keeping = at >= from && at <= to;
    }
    if (keeping && line.length) out.push(line);
    if (out.length > 4000) break;
  }
  return { ok: true, lines: out };
}

/* One row, from whatever the launcher sent and the ticket it sent it with.
   The Discord id and the name come from the ticket and the linked file, never
   from the body: the body is the launcher's, and the ticket is the only part
   of it the site signed. */
function sessionRow(t, o, key) {
  const known = jsonFile(LINKED, {})[t.d] || {};
  return {
    session: key,
    who: String(t.d),
    name: String(known.name || t.n || ''),
    profile: Number(o.profileId) || 0,
    /*
      dev, main, or "" when the launcher did not say.

      This used to read `=== 'dev' ? 'dev' : 'main'`, which turned "nothing was
      sent" into "main" and threw away the difference. That matters on the
      sessions page: a session that never reached a world is shown as Main
      Launcher or Dev Launcher when we know which build it was, and as plain
      Launcher when we genuinely do not, so the two cases can be told apart
      rather than the second quietly claiming the live server.
    */
    channel: (function (c) {
      const s = String(c == null ? '' : c).trim().toLowerCase();
      return (s === 'dev' || s === 'main') ? s : '';
    })(o.channel),
    version: String(o.version || '').slice(0, 32),
    start: 0, end: 0, minutes: 0, why: '', note: ''
  };
}

/* The whole member list in ONE request instead of one request per person.

   /api/allowed walks every linked account and asked Discord about each one
   separately. standingCached holds an answer for sixty seconds and both doors
   ask every five minutes, so the cache was always cold by the time they came
   back: about forty lookups per door, two doors, every five minutes, in a
   burst. The live server's log read "the site could not reach Discord, keeping
   the list as it was: rate limited by Discord" at 16:44, 16:49, 16:54, 16:59,
   17:04 and 17:09 on 22 September, once per refresh, which is what that burst
   looks like from the other end.

   One request answers for everybody. Cached the same sixty seconds, so a page
   that asks about several people in a row still only asks Discord once.

   It needs the Server Members intent, which is a switch in the Discord
   developer portal and may be off. A 403 comes back, byId stays null, and
   every caller falls through to the single lookup it used before, so this can
   only make things better or leave them exactly as they were. */
let membersCache = { at: 0, byId: null };
async function guildMembers() {
  /* Keyed on WHEN it was asked, not on what came back. Testing byId meant a
     failure was never remembered, because a failure stores null and null is
     falsy, so a guild with the intent switched off asked for the whole list
     once per person: ten people, ten refused list requests, on top of their
     ten single lookups. That is worse than not having this at all, and the
     comment below claimed the opposite until test-discord-members.js was run
     against it. */
  if (membersCache.at && Date.now() - membersCache.at < 60000) return membersCache.byId;
  if (!cfg.discord.botToken || !cfg.discord.guildId) return null;
  const r = await discordGet('/guilds/' + cfg.discord.guildId + '/members?limit=1000');
  if (!r.ok || !Array.isArray(r.body)) {
    // Remembered as a failure for the same sixty seconds. Without this, a
    // guild with the intent switched off asks for the whole list once per
    // person and doubles the very thing this is here to stop.
    membersCache = { at: Date.now(), byId: null };
    return null;
  }
  const byId = {};
  r.body.forEach(function (m) { if (m && m.user && m.user.id) byId[String(m.user.id)] = m; });
  membersCache = { at: Date.now(), byId: byId };
  return byId;
}

/* One member, out of the cached list when it is there and by name when it is
   not. Answers in the same shape discordGet does, so callers do not change. */
async function memberOf(discordId) {
  const all = await guildMembers();
  if (all) {
    const hit = all[String(discordId)];
    if (hit) return { ok: true, status: 200, body: hit };
    /* Absent from a COMPLETE list means not in the server, which is a 404 and
       is the one answer callers treat as certain. A list of exactly 1000 is
       the page limit rather than the whole guild, so it proves nothing about
       who is missing and the single lookup has to be asked. */
    if (Object.keys(all).length < 1000) {
      return { ok: false, status: 404, body: null, why: 'not found' };
    }
  }
  return await discordGet('/guilds/' + cfg.discord.guildId + '/members/' + discordId);
}

/* What this person is allowed to do, decided by their roles in the Discord and
   nothing else. Leaving the server, or being given the Banned role, takes
   everything away at once, which is the whole reason for doing it this way. */
async function standing(discordId) {
  const out = { id: String(discordId), inGuild: false, banned: false,
                admin: false, play: false, dev: false, roles: [], name: '' };

  /*
    THE FILE FIRST, AND BEFORE EVERY OTHER BRANCH.

    A ban read off a role only works when the bot is in the guild, the guild
    lookup succeeds and somebody spelled the role right. The branch below for
    "no bot configured yet" hands play to everybody, which is correct for an
    ordinary member and wrong for somebody who has been thrown out.

    So the list is read here, where nothing can route around it, and it wins.
  */
  const bans = jsonFile(BANS, {});
  if (bans && Object.prototype.hasOwnProperty.call(bans, String(discordId))) {
    out.banned = true;
    out.reason = String((bans[String(discordId)] || {}).why || '');
    return out;
  }

  /* The hand written admin list is an override, not a hint. It is the way back
     in when the bot is not in the server yet, has been kicked, or Discord is
     having a bad morning, so it cannot be gated behind a guild lookup that
     needs all three of those to be fine. */
  if (cfg.admins.indexOf(String(discordId)) >= 0) {
    out.admin = true; out.play = true; out.inGuild = true; out.dev = true;
    if (cfg.discord.botToken && cfg.discord.guildId) {
      const r = await memberOf(discordId);
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
  const r = await memberOf(discordId);
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
  // The role as well as the file. Either one is a ban, because the role is
  // what a moderator reaches for in Discord and the file is what survives
  // somebody renaming it.
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
/*
  A PAGE RATHER THAN FOUR CHARACTERS.

  A wrong address answered "not here" as plain text, which for the second
  somebody reads it makes the whole site look unfinished or broken. The same
  shape as the Not allowed in page below: the site's colours, a sentence, and a
  way back, because a dead end with no way out of it is the actual fault.

  BROWSERS ONLY. An API caller asking for JSON must not be handed HTML: it
  cannot read it and the error it then reports is a parse failure rather than a
  404, which is how a wrong address becomes an hour of somebody's evening. The
  Accept header decides, and anything that does not say text/html keeps the
  plain text it has always had.
*/
function wantsHtml(req) {
  return String((req && req.headers && req.headers.accept) || '').indexOf('text/html') >= 0;
}

function plainPage(title, lines) {
  const esc = (t) => String(t == null ? '' : t).replace(/[<>&]/g, '');
  return '<!doctype html><meta charset=utf-8><title>' + esc(title) + ' | Thornswood</title>' +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<body style="background:#12150F;color:#DDE3D5;font:15px/1.6 system-ui;' +
    'display:grid;place-items:center;height:100vh;margin:0;text-align:center;padding:20px">' +
    '<div style="max-width:32em">' +
    '<h1 style="color:#C9A24B;font-weight:600">' + esc(title) + '</h1>' +
    lines.map((t) => '<p>' + esc(t) + '</p>').join('') +
    '<p><a style="color:#C9A24B" href="/">Back to Thornswood</a></p>' +
    '</div>';
}

function notFoundPage() {
  return plainPage('Not here', [
    'That address does not exist on this site.',
    'If a link brought you here, say so in the Discord and it will be fixed.'
  ]);
}

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
          '<p>Tell Patrick and try again in a minute.</p>';
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
/*
  One malformed request used to take the whole site down, and the game's login
  with it.

  The handler is async, so anything it throws becomes a rejected promise rather
  than an exception, and an unhandled rejection ends the process. A request for
  /% is enough on its own: decodeURIComponent throws URIError on a percent sign
  that is not followed by two hex digits, and that is the third line of the
  handler, before any route has been looked at. Nobody has to be attacking
  anything. A scanner walking the address space does it without meaning to.

  Deploy-Docs.ps1 restarts the process three times an hour and then gives up,
  so a few seconds of a bored scanner took the site off the internet until
  somebody noticed, and with it /api/play/allowed, which is what the launcher
  asks before it will let anybody connect. The site being down meant nobody
  could start the game.

  So the handler is a named function now and nothing calls it without a catch.
  A bad URL is the request's fault and gets 400; anything else is ours and gets
  500, logged with a stack so it can be fixed rather than quietly swallowed.
*/
function failed(req, res, e) {
  const bad = e instanceof URIError;
  console.error('[thornswood-docs] ' + (bad ? 'malformed request ' : 'handler threw on ') +
                JSON.stringify(String(req.url || '').slice(0, 200)) + ': ' +
                (e && e.stack ? e.stack : e));
  try {
    // Half an answer is already on the wire and cannot be taken back. Cutting
    // the connection is the only honest end to it.
    if (res.headersSent) { res.destroy(); return; }
    res.writeHead(bad ? 400 : 500, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(bad ? 'bad request' : 'server error');
  } catch (e2) {
    // The socket went away while we were answering. Nothing left to tell.
  }
}

/*
  The last net, under everything rather than around one handler.

  A throw inside a setTimeout, or a promise nobody waited for, never reaches
  the catch above and would end the process exactly the way a bad URL used to.
  Logged and carried on with instead. A site answering most requests is worth
  more than a site that is gone, and the log line is the thing that says
  something here needs fixing.

  How the process is hosted and the three restarts an hour are entry 105; this
  is only about not needing them.
*/
process.on('unhandledRejection', (e) => {
  console.error('[thornswood-docs] unhandled rejection, carrying on: ' +
                (e && e.stack ? e.stack : e));
});
process.on('uncaughtException', (e) => {
  console.error('[thornswood-docs] uncaught exception, carrying on: ' +
                (e && e.stack ? e.stack : e));
});

async function handle(req, res) {
  const url = new URL(req.url, 'http://x');
  const p = decodeURIComponent(url.pathname);
  const route = p.replace(/\/+$/, '').toLowerCase() || '/';
  // HEAD is GET without a body. Every route below asks for GET by name, so a
  // HEAD fell through to the 404 at the bottom, and an uptime monitor or a
  // link checker that uses HEAD reported every address on the site as gone.
  // Node drops the body of a HEAD answer on its own, so routing it as GET is
  // the whole fix for the small answers. The streamed ones skip the read as
  // well: a HEAD for the installer is a question about its size, not a
  // download.
  const head = req.method === 'HEAD';
  if (head) req.method = 'GET';

  /* Set once, here, rather than inside send(): the streamed answers below
     write their own headers and never go through it. Node keeps a setHeader
     value through a later writeHead, so one line covers every route.

     Only on an answer that came in over the certificate. Caddy holds 443 and
     the plain to secure redirect already works, so this is the part that stops
     a browser trying the plain one again. On plain HTTP it means nothing and
     is left off. */
  if (secureHere(req)) {
    try { res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains'); } catch (e) { }
  }

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
    // Aged here too, and written back when anything went, so a month with no
    // sign-ins still empties the file rather than only the answer.
    if (!w.admin) return sendJson(res, 403, { error: 'admins only' });
    const rows = jsonFile(ATTEMPTS, []);
    const live = freshSignIns(rows, Date.now());
    if (Array.isArray(rows) && live.length !== rows.length) { putJson(ATTEMPTS, live); }
    return sendJson(res, 200, { signins: live });
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
      // The og tags a crawler reads are the ones in the file, so the page
      // actually being served is written into them here. home.html rewrites
      // the same tags for the browser tab.
      const blurb = BLURB[route];
      if (blurb) {
        const title = blurb[0] === 'Thornswood' ? blurb[0] : blurb[0] + ' · Thornswood';
        html = html.replace(
          /(<meta property="og:title" id="ogTitle" content=")[^"]*(")/,
          '$1' + escAttr(title) + '$2');
        for (const re of [/(<meta property="og:description" id="ogDesc" content=")[^"]*(")/,
                          /(<meta name="description" content=")[^"]*(")/]) {
          html = html.replace(re, '$1' + escAttr(blurb[1]) + '$2');
        }
      }
      return send(res, 200, html, TYPES['.html']);
    } catch (e) { return send(res, 500, 'no home.html', 'text/plain'); }
  }

  // Two addresses people type, or paste out of an old message. Both mean the
  // Downloads page, and both answered 404.
  if ((route === '/download' || route === '/install') && req.method === 'GET') {
    return send(res, 301, '', 'text/plain', { Location: '/downloads' });
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
    // Known Issues and Help live in the data folder with the other documents
    // (Help is edited in the hub), not under site. Same read, other folder.
    const dir = PUBLIC_DOCS.indexOf(pg[1]) >= 0 ? DATA : SITE;
    const file = path.join(dir, pg[1] + '.md');
    if (!file.startsWith(dir + path.sep) || !fs.existsSync(file)) {
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
    if (head) return res.end();
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
      const type = TYPES[path.extname(file).toLowerCase()] || 'text/plain';
      /*
        A byte range when one is asked for, because video needs it.

        Safari and iOS do not play a video from a plain 200 with the whole file
        in it: they ask for a range first and give up if the answer ignores the
        header. Chrome tolerates it, which is exactly how this ships broken for
        half the people and fine for whoever tested it.

        Everything else is unaffected. No Range header means the old path, byte
        for byte, with Accept-Ranges added so a client knows it may ask.
      */
      if (rangeReply(req, res, file, fs.statSync(file).size, { 'content-type': type }, head)) return;
      /*
        AND A CACHE HEADER, BECAUSE A LOGO IS NOT SOMEBODY'S PRIVATE DATA.

        send() puts Cache-Control: no-store on everything, which is right for a
        page that holds who somebody is and wrong for a picture. Every visit
        was re-downloading the whole of public/: the favicon, the fonts, the
        backdrop, the video. no-store also means a browser cannot even answer
        with a 304, so a page reload is a full download of all of it.

        An asset here is a file in public/ that a page asks for by name, and
        the honest way to cache one that is NOT fingerprinted is a short
        max-age plus an ETag: a browser reuses it for the hour and then asks,
        and the answer to that question is 25 bytes rather than 1.8 MB.

        The ETag is size and modified time, which is what a static file server
        does. It changes the moment a deploy writes a new file, so a changed
        picture is picked up on the next ask rather than after the hour.

        The pages themselves are untouched: they go through send() and keep
        no-store, which this branch never handles.
      */
      const st = fs.statSync(file);
      const etag = '"' + st.size.toString(16) + '-' + Math.floor(st.mtimeMs).toString(16) + '"';
      if (String(req.headers['if-none-match'] || '') === etag) {
        res.writeHead(304, {
          'etag': etag,
          'cache-control': 'public, max-age=3600',
          'x-content-type-options': 'nosniff'
        });
        return res.end();
      }
      return send(res, 200, fs.readFileSync(file), type, {
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'public, max-age=3600',
        'ETag': etag
      });
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
    /* Resumable, because the payload is hundreds of megabytes and the Join
       page says a dropped connection carries on. Accept-Ranges on the 200 so
       a client knows before it starts. The ETag and Last-Modified are what a
       browser needs before it will resume at all, and what If-Range is
       checked against, so a one file installer taken in the browser resumes
       too and never onto a different build. */
    const kind = {
      'content-type': 'application/octet-stream',
      'content-disposition': 'attachment; filename="' + path.basename(file) + '"',
      'etag': '"' + st.size.toString(16) + '-' + Math.floor(st.mtimeMs).toString(16) + '"',
      'last-modified': new Date(st.mtimeMs).toUTCString()
    };
    if (rangeReply(req, res, file, st.size, kind, head)) return;
    res.writeHead(200, Object.assign({}, kind, {
      'content-length': st.size,
      'accept-ranges': 'bytes'
    }));
    if (head) return res.end();
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
    if (head) return res.end();
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
    /*
      Could not ask Discord is not the same answer as not in the Discord.

      standing() leaves inGuild false on every failed lookup and sets
      lookupFailed to say why, because only a 404 means "not in the server".
      This door tested inGuild alone, so a rate limit or a Discord outage came
      back as 403 why 'guild', and the launcher writes a 'guild' down as a
      remembered no, which erased the 72 hour grace it keeps for exactly the
      day the site cannot vouch for anybody. The restart wave after every
      release is when Discord rate limits the site, and a stranger told they
      are not in a Discord they joined ten minutes ago assumes the thing is
      broken and leaves.

      So it answers 503 with the same why /api/play/owns already uses, and
      Door.cs treats that like a site that did not answer: a yes from the last
      few days still opens the door. The hand written admin list is left out
      of this, because standing() already let them in and it is the way back
      in on exactly this kind of morning.
    */
    if (st.lookupFailed && !st.admin) return sendJson(res, 503, { ok:false, why:'could not ask Discord', message:
      'Thornswood could not ask Discord about your account just now. Try again in a minute.' });
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
      slots: slotsFor(st)
    });
  }

  /*
    Both ends of a play session, from the launcher.

    Start when the game is started, end when it has closed, the same id on
    both. The ticket is read the same way the door reads it, and the row is
    written against the Discord id INSIDE that ticket, so a ticket can only
    ever write its own rows: one person's launcher cannot start, end or fill
    in a session belonging to somebody else, whatever id it sends.

    A row with no end is a session still open, not a fault. A row with no
    start is a session whose start was never seen, which is what a launcher
    that was replaced or restarted mid session produces, and it is recorded
    rather than dropped.
  */
  if ((p === '/api/play/start' || p === '/api/play/end') && req.method === 'POST') {
    const ending = (p === '/api/play/end');
    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { }
    const t = readTicket(o.ticket);
    if (!t) return sendJson(res, 401, { ok: false, why: 'link' });
    const key = sessionKey(o.session);
    if (!key) return sendJson(res, 400, { ok: false, why: 'no session id' });

    /* A ticket outlives a ban by up to a month, so a ban Discord confirms
       refuses here too. A lookup that failed records the session, because
       losing an evening's testing to a bad minute at Discord is the worse of
       the two. This is not what keeps the log from being scrubbed: any
       linked account could post starts until the rolling cap took every real
       session off the front with them, and the count below is what stops
       that. */
    const st = await standingCached(t.d);
    if (st.banned) return sendJson(res, 403, { ok: false, why: 'banned' });

    const rows = sessionRows();
    const at = findSession(rows, key, t.d);
    const now = Date.now();

    /* Nobody plays thirty times an hour. Past that from one account it is a
       fault or somebody pushing, and either way the row is not written. An
       end is never refused: an end only fills in a row that is already
       there. */
    if (!ending) {
      const hourAgo = now - 3600000;
      let mine = 0;
      for (let i = rows.length - 1; i >= 0; i--) {
        const r = rows[i];
        if (!r || !(Number(r.start) >= hourAgo)) continue;
        if (String(r.who) === String(t.d)) mine++;
      }
      if (mine >= 30 && at < 0) return sendJson(res, 429, { ok: false, why: 'too many' });
    }

    if (!ending) {
      // A second start on the same id is the same session said twice, not
      // another one, so it fills the row in rather than adding to it.
      if (at >= 0) {
        const was = rows[at];
        was.start = was.start || now;
        if (Number(o.profileId) > 0) was.profile = Number(o.profileId);
        if (o.version) was.version = String(o.version).slice(0, 32);
        was.channel = String(o.channel || '') === 'dev' ? 'dev' : 'main';
      } else {
        const row = sessionRow(t, o, key);
        row.start = now;
        rows.push(row);
      }
    } else {
      let m = Number(o.minutes);
      if (!isFinite(m) || m < 0) m = 0;
      m = Math.round(m * 10) / 10;
      const why = String(o.why || '') === 'update' ? 'update' : 'quit';
      if (at >= 0) {
        const was = rows[at];
        was.end = now;
        was.minutes = m;
        was.why = why;
        // The character is picked at the game's menu, so the start went out
        // not knowing it and the end is the first that does.
        if (Number(o.profileId) > 0) was.profile = Number(o.profileId);
        if (o.version) was.version = String(o.version).slice(0, 32);
      } else {
        const row = sessionRow(t, o, key);
        row.end = now;
        row.minutes = m;
        row.why = why;
        rows.push(row);   // start stays 0: it was never seen
      }
    }
    if (!putSessions(rows)) return sendJson(res, 500, { ok: false, why: 'could not save' });
    if (ending) { try { pruneSessionLogs(); } catch (e) { } }
    return sendJson(res, 200, { ok: true });
  }

  /*
    The logs from one session, sent by the launcher as the game closes.

    That moment and no other: the game wipes its own logs at every start, so a
    log nobody collected then is gone, which is why every report has had to
    begin by asking the person to go and find four files.

    Written once. A second set for the same session is refused and the attempt
    recorded on the first, because these are meant to stand up when somebody is
    suspended and evidence that the accused can overwrite is not evidence. The
    Discord id is taken off the ticket, never off the body.

    A bigger body than the rest of the API accepts, because it is carrying
    logs, and still capped: putSessionLogs trims each log and the set.
  */
  if (p === '/api/play/logs' && req.method === 'POST') {
    let o = {};
    try { o = JSON.parse(await body(req, SLOG_ALL + 64 * 1024)) || {}; } catch (e) { }
    const t = readTicket(o.ticket);
    if (!t) return sendJson(res, 401, { ok: false, why: 'link' });
    const key = sessionKey(o.session);
    if (!key) return sendJson(res, 400, { ok: false, why: 'no session id' });

    /* Only for a session this account actually has a row for. Without this
       anybody linked could write a log set against any id they invented, and
       the folder would fill with sets belonging to no session. */
    const rows = sessionRows();
    const at = findSession(rows, key, t.d);
    if (at < 0) return sendJson(res, 404, { ok: false, why: 'no such session' });

    const logs = (o.logs && typeof o.logs === 'object') ? o.logs : {};
    const what = putSessionLogs(key, t.d, logs);
    if (what === 'already') return sendJson(res, 409, { ok: false, why: 'already sent' });
    if (what === 'nothing') return sendJson(res, 200, { ok: true, stored: false });

    /* Read them once, now, so the page can colour this one session and the
       bot can say so in Discord. Done here rather than when somebody opens
       the page, because the point is that nobody has to open the page for
       anybody to find out.

       The launcher's own blockers and warnings come with the logs, already
       structured, and they carry more than the launcher's window shows: which
       plugin, whether it is absent or merely wrong, and the size, CRC and
       manifest index the server wanted. Those are kept whole. */
    try {
      const issues = Array.isArray(o.issues) ? o.issues.slice(0, 100).map(i => ({
        text: String((i && i.text) || '').slice(0, 400),
        blocking: !!(i && i.blocking),
        absent: !!(i && i.absent),
        plugin: String((i && i.plugin) || '').slice(0, 160),
        wantSize: Number(i && i.wantSize) || 0,
        wantCrc: Number(i && i.wantCrc) || 0,
        wantIndex: Number(i && i.wantIndex) || 0
      })).filter(i => i.text) : [];

      const checks = Array.isArray(o.checks) ? o.checks.slice(0, 40).map(c => ({
        name: String((c && c.name) || '').slice(0, 120),
        detail: String((c && c.detail) || '').slice(0, 400)
      })).filter(c => c.name) : [];

      if (issues.length) rows[at].issues = issues;
      if (checks.length) rows[at].checks = checks;

      const found = readTrouble(logs);
      if (found) {
        rows[at].trouble = found.why;
        rows[at].troubleAt = found.level;     /* 'bad' is red, 'warn' is yellow */
        rows[at].troubleFile = found.file;
        rows[at].troubleLine = found.line;
      } else if (issues.length || checks.length) {
        /* No crash, but the launcher was unhappy. Yellow, and never a message
           in Discord: these are common, understood, and have a known fix. */
        const blocking = issues.filter(i => i.blocking).length;
        rows[at].trouble = blocking
          ? (blocking + ' thing(s) would have stopped them connecting')
          : (issues.length + checks.length) + ' thing(s) the launcher was unhappy about';
        rows[at].troubleAt = 'warn';
      }

      if (rows[at].trouble) putSessions(rows);
      /* Only a crash is worth saying out loud. */
      if (found && found.level === 'bad') noteTrouble(rows[at], found);
    } catch (e) { }

    return sendJson(res, 200, { ok: true, stored: true });
  }

  /*
    The character roster, in from the game server and out to each person.

    In: the gamemode posts its whole book with the door key whenever it
    changes, {key, who: {"<profileId>": {name, race, female, trade, town,
    where, at}}}. Merged by profile id, so the live and the dev server share
    the file without treading on each other.

    Out: a launcher posts its ticket and gets the rows for the profile ids
    linked to that Discord account, and no others. This is how a card at the
    game's main menu knows its own name; until 20 September the launcher read
    characters.json off the resource port, which has been a 404 since the
    file moved into the private folder on the 18th.
  */
  if (p === '/api/roster' && req.method === 'POST') {
    if (!cfg.botKey) return sendJson(res, 404, { error: 'not set up' });
    let o = {};
    try { o = JSON.parse(await body(req, 4 * 1024 * 1024)) || {}; } catch (e) { }
    if (!sameSecret(String(o.key || ''), String(cfg.botKey))) return sendJson(res, 401, { error: 'no' });
    const who = (o.who && typeof o.who === 'object') ? o.who : {};
    const store = jsonFile(ROSTER, { who: {} });
    if (!store.who || typeof store.who !== 'object') store.who = {};
    let n = 0;
    for (const pid of Object.keys(who)) {
      if (!/^\d+$/.test(pid)) continue;
      const row = who[pid];
      if (!row || typeof row !== 'object') continue;
      store.who[pid] = {
        name: String(row.name || '').slice(0, 64), race: String(row.race || '').slice(0, 32),
        female: !!row.female, trade: String(row.trade || '').slice(0, 32),
        town: String(row.town || '').slice(0, 32), where: String(row.where || '').slice(0, 80),
        at: Number(row.at) || Date.now()
      };
      n++;
    }
    store.at = Date.now();
    putJson(ROSTER, store);
    return sendJson(res, 200, { ok: true, merged: n, total: Object.keys(store.who).length });
  }

  if (p === '/api/play/roster' && req.method === 'POST') {
    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { }
    const t = readTicket(o.ticket);
    if (!t) return sendJson(res, 401, { ok: false, why: 'link' });
    const linked = jsonFile(LINKED, {});
    const mine = ((linked[t.d] || {}).profiles || []).map(Number).filter((x) => x > 0);
    const store = jsonFile(ROSTER, { who: {} });
    const rows = {};
    for (const pid of mine) {
      const row = store.who && store.who[String(pid)];
      if (row) rows[String(pid)] = row;
    }
    return sendJson(res, 200, { ok: true, rows });
  }

  /*
    What the game server's door asks for, every five minutes, with the bot key:
    the profile ids of everyone currently allowed in. Everyone who has ever
    checked in through the launcher is re-asked of Discord, so leaving the
    server or picking up the Banned role drops their numbers off the list
    within a refresh. If any lookup failed the answer says so and names the
    profiles it could not check in failedProfiles, and the door keeps those
    as they were, because a short list built while Discord was down would
    turn away everybody missing from it.

    devProfiles rides along in the same answer: the subset of the same people
    who also hold the dev or admin role, whichever server they connect to.
    st.dev already folds admin in (out.dev = out.admin || has(cfg.access.dev)
    up in standing()), so this is free, and it is what lets the game server
    tell a tester apart from anybody else without a second question to Discord
    for every command somebody types.
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
    const out = { profiles: [], devProfiles: [], adminProfiles: [], people: [], lookupFailed: false, lookupFailedWhy: '', failedProfiles: [], at: Date.now() };
    const seen = new Set();
    const seenDev = new Set();
    const seenAdmin = new Set();
    const seenFailed = new Set();
    for (const d of Object.keys(linked)) {
      const row = linked[d] || {};
      const profiles = (Array.isArray(row.profiles) ? row.profiles : [])
        .map(Number).filter((n) => n > 0);
      if (!profiles.length) continue;
      let st;
      try { st = await standingCached(String(d)); } catch (e) { st = { lookupFailed: String(e) }; }
      if (st.lookupFailed) {
        /* WHY, NOT JUST THAT. This reduced a specific reason to a boolean, so
           the game server could only ever say "the site could not reach
           Discord" and the door log on 22 September said exactly that and no
           more. discordGet already works the reason out in plain words: a
           wrong token, a bot that may not read members, a rate limit, no token
           at all. Those are four different fixes and the difference was being
           thrown away one line after it was known. The first one seen is
           enough; a list where every lookup fails fails for one reason. */
        out.lookupFailed = true;
        if (!out.lookupFailedWhy) { out.lookupFailedWhy = String(st.lookupFailed); }
        /* AND WHOSE. lookupFailed alone makes one rate limited lookup throw
           the whole list away, so the door kept a stale list for everybody
           because one person could not be checked. Naming the profiles lets a
           door that knows this field keep just those as they were and take
           everybody else's fresh answer. lookupFailed and lookupFailedWhy stay
           exactly as they were, so a door older than this still keeps the
           whole list, which is what it did before. */
        for (const n of profiles) if (!seenFailed.has(n)) { seenFailed.add(n); out.failedProfiles.push(n); }
        continue;
      }
      if (!st.play || st.banned) continue;
      if (devDoor && !st.dev) continue;
      for (const n of profiles) if (!seen.has(n)) { seen.add(n); out.profiles.push(n); }
      if (st.dev) {
        for (const n of profiles) if (!seenDev.has(n)) { seenDev.add(n); out.devProfiles.push(n); }
      }
      // The admin roles (access.admin: Owner and Dev unless config.json says
      // otherwise), so the game server can hold an Owner's new character to
      // the same standing as the one profile number in its own settings.
      if (st.admin) {
        for (const n of profiles) if (!seenAdmin.has(n)) { seenAdmin.add(n); out.adminProfiles.push(n); }
      }
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
    /*
      Could not ask Discord is not the same answer as not allowed.

      standing() leaves play false on any lookup that failed, and sets
      lookupFailed to say why, because a 404 is the only failure that really
      means "not in the server". Answering 200 with ok false here would turn a
      Discord outage into every new character being refused their profession
      and home town, and voice-server.js reads a non-200 as unchecked and
      stores the choice anyway, which is exactly the behaviour a failed lookup
      should get. /api/allowed a few routes down already does this.
    */
    if (st.lookupFailed) {
      return sendJson(res, 503, { ok: false, why: 'could not ask Discord' });
    }
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
        sessions: w.admin ? sessionRows() : [],
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

    /* Everything from one session, for the View more button on /sessions.
       Admins only, like everything below the line above.

       The client half is what the launcher sent when the game closed. The
       server half is sliced out of the game server's own log now, by this
       session's start and end, rather than having been copied anywhere. A
       session still open has no end yet, so the slice runs to now.

       The row is found by the session id AND the Discord id it belongs to, so
       a stray id cannot read somebody else's session. */
    if (p === '/api/session-logs' && req.method === 'GET') {
      const key = sessionKey(url.searchParams.get('session'));
      const rows = sessionRows();
      const at = key ? findSession(rows, key, url.searchParams.get('who')) : -1;
      if (at < 0) return sendJson(res, 404, { error: 'no such session' });
      const row = rows[at];

      let client = {};
      let sent = null;
      try {
        const f = slogFile(key);
        if (fs.existsSync(f)) {
          const set = JSON.parse(fs.readFileSync(f, 'utf8')) || {};
          client = set.logs || {};
          /* The provenance, so the page can show where this came from and
             whether anybody tried to send a second set over it. */
          sent = {
            who: String(set.who || ''),
            at: Number(set.at) || 0,
            bytes: Number(set.bytes) || 0,
            sha256: set.sha256 || {},
            resent: Number(set.resent) || 0
          };
        }
      } catch (e) { client = {}; sent = null; }

      /* A minute either side, because the launcher stamps the session and the
         server stamps its own lines, and the two clocks are the same clock but
         the moments are not: the start is sent as the game launches and the
         server sees the connection a little after. */
      const from = (Number(row.start) || Number(row.end) || 0) - 60000;
      const to = (Number(row.end) || Date.now()) + 60000;
      const server = serverLogSlice(row.channel, from, to);
      const chat = chatSlice(row.profile, from, to);

      return sendJson(res, 200, {
        session: key,
        channel: row.channel,
        client,
        sent,
        /* What they said, in this session only. The page shows it beside the
           logs rather than on a page of its own. */
        chat: chat.lines,
        chatWhy: chat.why,
        /* Whether this one is held past the retention rule, so the button
           beside the provenance shows the right state. */
        keep: !!row.keep,
        keptBy: String(row.keptBy || ''),
        server: server.lines,
        serverWhy: server.ok ? '' : server.why,
        clientSent: Object.keys(client).length > 0
      });
    }

    /* /api/chat was here: the whole chat log, a day at a time, for everybody
       at once, behind a page of its own. It is gone, and so is that page.
       Answering "what did this person do" meant reading a session on one page,
       working out when it ran, then going to another page, picking the day and
       filtering by name, and holding the two together in your head. What it
       did is now chatSlice, and the lines come back inside /api/session-logs
       under the session they were said in, beside that session's other files.
       Decided by Patrick on 22 September. */

    /* Hold one session's logs indefinitely, or let them age out again.

       Everything else is pruned after SLOG_DAYS. This is the switch for the
       set that an argument rests on, so a suspension is not quietly undone a
       year later by the retention rule. Admins only, and it records who held
       it and when, because "who decided to keep this" is part of the evidence
       rather than separate from it. */
    if (p === '/api/session-keep' && req.method === 'PUT') {
      let obj;
      try { obj = JSON.parse(await body(req)); }
      catch (e) { return sendJson(res, 400, { error: 'bad json' }); }
      const key = sessionKey(obj && obj.session);
      const rows = sessionRows();
      const at = key ? findSession(rows, key, obj.who) : -1;
      if (at < 0) return sendJson(res, 404, { error: 'no such session' });
      const on = !!(obj && obj.keep);
      rows[at].keep = on;
      if (on) { rows[at].keptBy = String(w.name || ''); rows[at].keptAt = Date.now(); }
      else { delete rows[at].keptBy; delete rows[at].keptAt; }
      if (!putSessions(rows)) return sendJson(res, 500, { error: 'could not save' });
      return sendJson(res, 200, { ok: true, keep: on });
    }

    /* The sheet part: what a staff member writes against one session.
       Admins only, like everything below the line above, and one row at a
       time rather than the whole file, so two people with the page open do
       not write over each other's notes. The row is found by the session id
       AND the Discord id it belongs to, so a stray id cannot land a note on
       somebody else's session. */
    if (p === '/api/session-note' && req.method === 'PUT') {
      let obj;
      try { obj = JSON.parse(await body(req)); }
      catch (e) { return sendJson(res, 400, { error: 'bad json' }); }
      const key = sessionKey(obj && obj.session);
      const rows = sessionRows();
      const at = key ? findSession(rows, key, obj.who) : -1;
      if (at < 0) return sendJson(res, 404, { error: 'no such session' });
      rows[at].note = String(obj.note == null ? '' : obj.note).slice(0, 2000);
      rows[at].noteBy = String(w.name || '');
      rows[at].noteAt = Date.now();
      if (!putSessions(rows)) return sendJson(res, 500, { error: 'could not save' });
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

  // The site's own look for a person, the same four characters for anything
  // that did not ask for HTML. See notFoundPage above.
  if (wantsHtml(req)) { return send(res, 404, notFoundPage(), TYPES['.html']); }
  send(res, 404, 'not here', 'text/plain');
}

http.createServer((req, res) => {
  // Both halves matter. A throw before the first await arrives here as an
  // exception, and one after it arrives as a rejected promise.
  let done;
  try {
    done = handle(req, res);
  } catch (e) {
    failed(req, res, e);
    return;
  }
  if (done && typeof done.catch === 'function') {
    done.catch((e) => failed(req, res, e));
  }
}).listen(PORT, BIND, () => {
  console.log('[thornswood-docs] listening on ' + BIND + ':' + PORT);
  console.log('[thornswood-docs] writing this to ' + siteLog.file +
              ', rolled at 4 MB, five kept');
  console.log('[thornswood-docs] documents in ' + DATA);
  console.log('[thornswood-docs] downloads in ' + FILES);
  console.log('[thornswood-docs] uploads in ' + UP);
  console.log('[thornswood-docs] watching the game on 127.0.0.1:' +
    (cfg.gameCheckPort || 3000) + ' (the game plays on UDP ' +
    (cfg.gamePort || 7777) + ', which cannot be probed), count from ' + cfg.onlineFile);
  console.log('[thornswood-docs] discord login ' +
    (cfg.discord.clientId ? 'ready' : 'NOT SET UP') +
    ', guild check ' + (cfg.discord.botToken && cfg.discord.guildId ? 'on' : 'OFF'));

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
