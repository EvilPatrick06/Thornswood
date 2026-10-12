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
/* LOOPBACK UNLESS ASKED (#2185). Caddy holds 443 and hands everything on from
   127.0.0.1, so this answers only there. Listening on every address put port
   3001 open as a plain HTTP way past the certificate, cookies and passwords
   included, on any box where THORNSWOOD_DOCS_LOCAL had not been set, and the
   unsafe answer was the default. Now a plain listener on every address takes
   THORNSWOOD_DOCS_EXPOSE=1, for a box with no proxy in front, and says so
   loudly at every start. THORNSWOOD_DOCS_LOCAL=1 still means loopback and
   wins over EXPOSE. */
const EXPOSED = process.env.THORNSWOOD_DOCS_EXPOSE === '1' && process.env.THORNSWOOD_DOCS_LOCAL !== '1';
const BIND   = EXPOSED ? '0.0.0.0' : '127.0.0.1';
const ROOT   = __dirname;
const DATA   = path.join(ROOT, 'data');
const PUBLIC = path.join(ROOT, 'public');
const FILES  = path.join(ROOT, 'files');
const UP     = path.join(ROOT, 'uploads');
/* What the site writes for the bot and nothing else: trouble.json, inbox.json
   and moderation.log (issue #1102). The bot runs as its own account, which is
   granted read on this folder only (scripts\vps\Bot-Service.ps1), so it never
   reaches the site's own records beside it, sessions.json among them. */
const FOR_BOT = path.join(DATA, 'for-bot');

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
//
// WHEN ROLLING FAILS (#2189). Until 11 October a failed roll was swallowed
// and the line was appended anyway, so one rotated file held open (an editor,
// a tail, a backup) or a folder that lost delete rights let site.log grow
// past its four megabytes for as long as the site ran, with nothing said.
// Now: the failure is said ONCE on the console and in the log itself, naming
// the file, the error and what usually causes it. The roll is retried every
// retryMs (a minute), not on every line. And the active file has an
// EMERGENCY CEILING of twice maxBytes (8 MB for site.log): past it one line
// says so and the file stops growing, lines carry on to the console only,
// until a roll succeeds, which is said once too. Disk space for this folder
// as a whole is #2178's storage alerts, not this.
function makeLog(dir, name, maxBytes, keep, opts) {
  const file = path.join(dir, name);
  const retryMs = (opts && typeof opts.retryMs === 'number') ? opts.retryMs : 60000;
  const ceiling = maxBytes * 2;
  let broken = false;
  let rollError = null;      // the last roll's error, null when the last roll worked
  let rollFailures = 0;      // failed rolls since the last good one
  let nextRoll = 0;          // no retry before this (ms)
  let held = false;          // the ceiling line has been written
  function say(line) {
    try { process.stdout.write('[thornswood-docs] ' + line + '\n'); } catch (e) { }
  }

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
      rollError = null;
      return true;
    } catch (e) { rollError = e; return false; }
  }

  function write(line) {
    if (broken) { return false; }
    try {
      let size = 0;
      try { size = fs.statSync(file).size; } catch (e) { size = 0; }
      if (size >= maxBytes && Date.now() >= nextRoll) {
        if (roll()) {
          if (rollFailures) {
            const was = rollFailures;
            rollFailures = 0; held = false;
            say('rolled ' + file + ' again after ' + was + ' failed tr' + (was === 1 ? 'y' : 'ies'));
            fs.appendFileSync(file, stamp() + '  log rolled again after ' + was + ' failed tr' + (was === 1 ? 'y' : 'ies') + '\n');
          }
          size = 0;
        } else {
          rollFailures++;
          nextRoll = Date.now() + retryMs;
          if (rollFailures === 1) {
            const why = 'could not roll ' + file + ' (' + ((rollError && (rollError.code || rollError.message)) || 'unknown') +
              ': ' + ((rollError && rollError.message) || '') + '). Usually ' + name + '.1 to .' + keep +
              ' is held open by an editor, a tail or a backup, or the folder lost delete rights. ' +
              'Retrying every ' + Math.round(retryMs / 1000) + ' s; past ' + ceiling + ' bytes ' + name +
              ' stops growing and lines go to the console only.';
            say(why);
            fs.appendFileSync(file, stamp() + '  ERROR ' + why + '\n');
            size += why.length;
          }
        }
      }
      if (size >= ceiling) {
        if (!held) {
          held = true;
          const stop = name + ' reached its emergency ceiling of ' + ceiling + ' bytes with rolling still failing; ' +
            'lines go to the console only until a roll works';
          say(stop);
          fs.appendFileSync(file, stamp() + '  ERROR ' + stop + '\n');
        }
        return false;
      }
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

  return {
    file: file, write: write, roll: roll, ceiling: ceiling,
    broken: function () { return broken; },
    rolling: function () { return { failures: rollFailures, held: held, error: rollError ? (rollError.code || rollError.message) : null }; }
  };
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
  password: '',
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
    Patrick, 28 Sep: "we are in alpha so the world is open by application".
    Anyone can download it; getting in is an application in the Discord.
    Staff give Member after an application is accepted. Discord has no
    default-role setting, so joining does not hand Member out. Playtester
    (access.play) is what opens the game, and Member is not on that list.
    The application, and the age and rules questions it asks (#428), is the
    way into the world.

    The day the world opens to everybody, "open": true in config.json is the
    one switch (#428). It puts Member on the play list at load (playRoles),
    tells the bot and the pages through /api/public, and they follow: the
    bot drops the application from its panel, and the join, help, rules and
    home wording change with it. Off unless config.json says true. It only
    opens the world to everybody if everybody in the Discord has Member.
  */
  open: false,
  access: {
    admin:  ['Owner', 'Dev'],
    play:   ['Owner', 'Dev', 'Moderator', 'Gamemaster', 'Loremaster',
             'Content Creator', 'Playtester'],
    banned: ['Banned']
  },
  botKey: '',            // shared secret the Discord bot signs /api/ticket with
  admins: [],            // discord ids, an override for when the bot is down
  secret: '',
  passKey: ''            // signs join passes; the game servers hold a copy (#937)
};
/* The byte order mark matters. Windows PowerShell puts one on the front of
   anything it writes with -Encoding UTF8, JSON.parse refuses a string that
   starts with it, and this used to be a bare catch that swallowed the error
   and carried on with the defaults. Which meant the site ran for days looking
   configured from the outside and holding nothing. Strip it, and remember
   whether the read actually worked. */
let cfgBroken = null;
let fileHadPassword = false;
try {
  const parsedCfg = JSON.parse(
    fs.readFileSync(CFGFILE, 'utf8').replace(/^\uFEFF/, ''));
  if (parsedCfg && typeof parsedCfg === 'object' && !Array.isArray(parsedCfg) &&
      typeof parsedCfg.password === 'string' && parsedCfg.password.length > 0) {
    fileHadPassword = true;
  }
  cfg = Object.assign(cfg, parsedCfg);
} catch (e) {
  if (fs.existsSync(CFGFILE)) cfgBroken = e;
}
cfg.discord = Object.assign({ clientId:'', clientSecret:'', botToken:'', guildId:'', invite:'' },
                            cfg.discord || {});
// No jarl here: an empty list seeded here is an array, so the Jarl default
// below never applied and a config.json without access.jarl let nobody hold
// the office (#905). dev, jarl and slots3 get their defaults below.
cfg.access  = Object.assign({ admin:[], play:[], banned:[] }, cfg.access || {});
// The one switch (#428). Only a real true opens it: "true", 1 or a typo does not.
cfg.open = cfg.open === true;
cfg.access.play = playRoles(cfg.access.play, cfg.open);
// Who may use the dev build and join the dev server. Left out of config.json
// it is the Discord staff roles, the same set the bot's STAFF_ROLES names
// (Owner, Dev, Gamemaster, Moderator, Loremaster; Content Creator is not
// staff, bot.py). Patrick's call on 27 September for the dev-build install gate
// (#605): the dev build is for staff, not the admin pair alone. It folds
// access.admin in through out.dev below, so widening admin still widens dev.
// Add role names here to widen it further.
if (!Array.isArray(cfg.access.dev)) {
  cfg.access.dev = ['Owner', 'Dev', 'Gamemaster', 'Moderator', 'Loremaster'];
}
// Who may hold a Jarl office in the world. Discord role eligibility only;
// the office itself sits on one named character (#397).
if (!Array.isArray(cfg.access.jarl)) {
  cfg.access.jarl = ['Jarl'];
}
// Who the Free Skyrim Trading Company has taken on (#1393): an application in
// Discord, the same shape as a Jarl's, and a person gives the role. The game
// lets them handle a company sale.
if (!Array.isArray(cfg.access.company)) {
  cfg.access.company = ['Trading Company'];
}
// Who gets a third character slot at the game's main menu. Everybody gets
// two; a Patreon tier or a Gamemaster gets three, and so do the admin roles.
// Decided by Patrick on 20 September. The tier names are Build-Discord.py's.
if (!Array.isArray(cfg.access.slots3)) {
  cfg.access.slots3 = ['Thalmor Boot-Licker', 'Talos Worshiper', 'Milk Drinker', 'Gamemaster'];
}
cfg.admins  = Array.isArray(cfg.admins) ? cfg.admins.map(String) : [];

// A list of role names for a sentence: "Owner, Dev and Gamemaster" rather than
// "Owner and Dev and Gamemaster", so the dev-role refusal reads plainly once
// access.dev holds more than the old admin pair (#605).
function andList(names) {
  const a = (names || []).filter(Boolean);
  if (a.length === 0) return '';
  if (a.length === 1) return a[0];
  return a.slice(0, -1).join(', ') + ' and ' + a[a.length - 1];
}

/* The member password is a bootstrap for a site that has no Discord sign in
   yet (#1305). It is not a word shipped in the repository. A config that
   already has a password keeps it, and that password is not printed again.
   A fresh config, or one with none, gets a random password. It is saved with
   the other keys and printed once, for the operator. A file that will not
   parse is left untouched; the password held in memory is still random, so
   an empty one cannot sign in. */
let tellPassword = false;
if (!fileHadPassword) {
  cfg.password = crypto.randomBytes(24).toString('hex');
  tellPassword = !cfgBroken;
}

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
/* The join pass key (#937). Made here once and kept in config.json, never in
   the repository; Set-Door.ps1 -Connect copies it into each game server's
   door.json, which is how the two ends share it without anybody handling it.
   A key that could not be kept is no key at all: a pass signed with one that
   dies with this process would be refused by every game server, so /api/play/pass
   answers 503 instead, which is the safe side. */
if (cfgBroken) {
  cfg.passKey = '';
} else if (!cfg.passKey) {
  cfg.passKey = crypto.randomBytes(32).toString('hex');
  try { fs.writeFileSync(CFGFILE, JSON.stringify(cfg, null, 2), 'utf8'); }
  catch (e) {
    cfg.passKey = '';
    console.error('[thornswood] could not keep a join pass key in config.json, so no join ' +
                  'passes are issued: ' + e.message);
  }
}

if (tellPassword) {
  try {
    fs.writeFileSync(CFGFILE, JSON.stringify(cfg, null, 2), 'utf8');
    console.log('[thornswood] member bootstrap password (shown once): ' + cfg.password);
  } catch (e) {
    console.error('[thornswood] could not keep a member bootstrap password in config.json, ' +
                  'so it was not printed: ' + e.message);
  }
}

for (const dir of [DATA, FOR_BOT, PUBLIC, FILES, UP]) {
  try { fs.mkdirSync(dir, { recursive: true }); } catch (e) { }
}
/* A site from before #1102 kept those three directly in data. Each is moved
   into for-bot once: copied, so the copy takes that folder's rules rather
   than keeping the old file's, then removed. One already in for-bot is never
   written over, and the old one is then left where it is and said. */
for (const n of ['trouble.json', 'inbox.json', 'moderation.log']) {
  const from = path.join(DATA, n);
  const to = path.join(FOR_BOT, n);
  try {
    if (!fs.existsSync(from)) continue;
    if (fs.existsSync(to)) {
      console.log('[thornswood-docs] ' + n + ' is in data and in data\\for-bot; the one in for-bot is used, the other is left for a look');
      continue;
    }
    fs.copyFileSync(from, to);
    fs.unlinkSync(from);
    console.log('[thornswood-docs] moved ' + n + ' into data\\for-bot, where the bot reads it');
  } catch (e) { console.log('[thornswood-docs] could not move ' + n + ' into data\\for-bot: ' + e.message); }
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

/* Who may see what. 'member' is the password, 'admin' is Discord (the
   access.admin pair), 'staff' is every access.dev role. The server decides
   this, not the page: a section left out here is not sent at all, rather than
   sent and hidden. */
/* Everything behind /hub is admin now. The tester tier used to live in here,
   which meant anybody allowed into the game could open the same panel he does
   and read half of it. Downloads and Report a problem went to the public site
   instead, so a playtester never needs this page at all and the gate can be
   one role check rather than two tiers. */
/* Hub trimmed (#433): Gallery (uploads), Sessions, Linked Accounts, Inbox.
   Issue boards, tests, help, roadmap, news, link, archive, todo left the hub.
   Public /known /help /roadmap /news stay as PUBLIC_PAGES. */
/* The Gallery page is 'staff' rather than 'admin' (#742). Every gallery door
   it calls asks for w.dev, so a Gamemaster, Moderator or Loremaster could
   approve and delete by API while the page that does it sent them back to the
   hub home, and the launcher's Manage on the site button opens this address.
   The page now matches the doors behind it. The linked accounts are 'staff'
   since #1010, because that page is where staff ban, PK and write notes, and
   every staff role may. The other two stay 'admin': the play sessions and
   the report inbox. */
const LEVEL = {
  uploads: 'staff', linked: 'staff', sessions: 'admin', inbox: 'admin'
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
                      '/privacy', '/terms', '/cookies'];
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
  '/terms':     ['Terms', 'Eighteen and over, play by the rules, your account is yours, and nothing here is charged for or promised.'],
  '/cookies':   ['Cookies', 'The cookies this site sets: sign-in and the eighteen-and-over gate. No advertising cookie.']
};
const escAttr = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;')
  .replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// ==== thornswood page render ====
//
// THE WRITTEN PAGES GO OUT AS HTML. Until entry 247 the rules, the world, how
// to join and the rest were an empty page that the browser filled in: it
// fetched the markdown and turned it into HTML with marked, loaded from
// cdnjs.cloudflare.com with no integrity check, in fonts from Google. So the
// rules page was blank to anything that does not run the page's script (a
// search engine, a link preview), it was blank whenever cdnjs could not be
// reached, and every visitor's address went to two other companies for
// opening it. The same marked, 12.0.2, now sits in public/ and runs here, and
// the page leaves this server with its words already in it.
//
// NO HTML THROUGH, BY CONSTRUCTION. Help is edited in the hub and the rest are
// files anybody with the box can change. Rendered in the browser, a line of
// HTML in one of them ran on the page; rendered here it would be written into
// the public front as served. So the renderer never recognises HTML at all: a
// tag in the markdown is text and comes out escaped, a link or a picture only
// goes somewhere if its address is http, https, mailto or on this site, and
// every attribute it writes is one it built and escaped itself. That is an
// allowlist in the renderer rather than a regex over its output afterwards,
// and it needs no package: the site has no package.json and Deploy-Docs sends
// files, not node_modules.
//
// The one piece of HTML any page used is the empty anchor world.md puts above
// the Accord, which the footer's /world#accord points at. An empty anchor with
// an id and nothing else is the one shape let through.
function makePageRenderer(lib) {
  const esc = (s) => String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  // marked escapes a title and a picture's words while it reads them, so this
  // leaves a finished entity alone rather than showing "&amp;quot;".
  const escOnce = (s) => String(s == null ? '' : s)
    .replace(/&(?!#\d{1,7};|#[Xx][0-9A-Fa-f]{1,6};|\w+;)/g, '&amp;')
    .replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  // An address as it goes into href or src, or null when it is not one this
  // site hands out. encodeURI is what marked itself does to it. After that
  // anything before a colon, with no slash, ? or # ahead of it, is a scheme,
  // and only three are allowed. The & is escaped on the way out, so
  // javascript&#58; reaches the browser as those characters and not as a
  // colon.
  function address(href) {
    let h;
    try { h = encodeURI(String(href == null ? '' : href)).replace(/%25/g, '%'); }
    catch (e) { return null; }
    const scheme = /^([^:/?#]*):/.exec(h);
    if (scheme && !/^(https?|mailto)$/i.test(scheme[1])) return null;
    return esc(h);
  }
  const m = new lib.Marked({ gfm: true, breaks: false });
  m.use({
    // Undefined is "not this", so marked goes on to read it as text, which it
    // escapes. A tag never becomes an html token and never switches marked
    // into the raw mode that stops it escaping what follows.
    tokenizer: {
      html() { return undefined; },
      tag() { return undefined; }
    },
    extensions: [{
      name: 'emptyAnchor',
      level: 'inline',
      start(src) { const i = src.indexOf('<a id='); return i < 0 ? undefined : i; },
      tokenizer(src) {
        const a = /^<a id=(["'])([A-Za-z][A-Za-z0-9_-]{0,63})\1\s*><\/a>/.exec(src);
        return a ? { type: 'emptyAnchor', raw: a[0], id: a[2] } : undefined;
      },
      renderer(t) { return '<a id="' + t.id + '"></a>'; }
    }],
    renderer: {
      // Nothing above produces one. Escaped anyway, so a later marked that
      // does is still safe.
      html(text, block) { return block ? '<p>' + esc(text) + '</p>\n' : esc(text); },
      link(href, title, text) {
        const to = address(href);
        if (to === null) return text;
        return '<a href="' + to + '"' + (title ? ' title="' + escOnce(title) + '"' : '') +
               '>' + text + '</a>';
      },
      image(href, title, text) {
        const to = address(href);
        if (to === null) return escOnce(text);
        return '<img src="' + to + '" alt="' + escOnce(text) + '"' +
               (title ? ' title="' + escOnce(title) + '"' : '') + '>';
      }
    }
  });
  return (md) => m.parse(String(md == null ? '' : md));
}

// home.html with a written page put into it: the page shown, the front hidden,
// and the tab named after the page's first heading. Each marker is replaced
// once with a function, so a $ in somebody's text is a dollar and not a
// replacement pattern. A home.html without the markers comes back unchanged,
// and its own script fetches the page instead.
function fillPage(html, body) {
  const h1 = /<h1[^>]*>([\s\S]*?)<\/h1>/.exec(body);
  const name = h1 ? h1[1].replace(/<[^>]*>/g, '').trim() : '';
  return html
    .replace(/<div id="landing">[\s\S]*?<\/div><!-- \/landing -->/,
             () => '<div id="landing" hidden></div><!-- /landing -->')
    .replace('<div class="page" id="page" hidden><div class="wrap" id="pagebody"></div></div>',
             () => '<div class="page" id="page"><div class="wrap" id="pagebody">' + body + '</div></div>')
    .replace('<title>Thornswood</title>',
             () => '<title>' + (name ? name + ' · Thornswood' : 'Thornswood') + '</title>');
}
// ==== end thornswood page render ====

/* The addresses that are a markdown page. The same list as PAGES in
   home.html, and tools/test-site-render.js checks that the two agree. */
const MD_PAGES = ['/world', '/rules', '/join', '/credits', '/classes',
                  '/known', '/help', '/privacy', '/terms', '/cookies'];
const MARKED = 'marked-12.0.2.min.js';
let renderMd = null;
try { renderMd = makePageRenderer(require(path.join(PUBLIC, MARKED))); }
catch (e) {
  console.error('[thornswood-docs] ' + MARKED + ' did not load, so the written ' +
                'pages go out as plain text until it does: ' + e.message);
}
// Plain text rather than no page, if the library is missing or a page will
// not render, so one bad edit to Help cannot turn /help into an error.
function pageHtml(md) {
  if (renderMd) {
    try { return renderMd(md); }
    catch (e) {
      console.error('[thornswood-docs] a page would not render, sent as plain text: ' + e.message);
    }
  }
  return '<pre class="pre-wrap">' + escAttr(md) + '</pre>';
}
// A written page's markdown, or null. Known Issues and Help live in the data
// folder with the other documents (Help is edited in the hub), not under site.
function pageMarkdown(name) {
  const dir = PUBLIC_DOCS.indexOf(name) >= 0 ? DATA : SITE;
  const file = path.join(dir, name + '.md');
  if (!file.startsWith(dir + path.sep) || !fs.existsSync(file)) return null;
  try { return forMode(fs.readFileSync(file, 'utf8'), cfg.open); } catch (e) { return null; }
}

// The credits page says which engine each server runs. That is a fact of the
// box, not of the repo, so a hand edit went stale with every deploy (the
// source-offer test caught 3a32e961 that way). Deploy-Server.ps1 writes
// data/deployed-build.json after a server deploy (scripts/deploy/
// DeployedBuild.ps1), and the feeds this site serves carry the client commit.
// fillCreditsCommits puts both into the page at serve time. The markdown keeps
// its hand text, which is what goes out when either source is missing.
// ==== thornswood credits fill ====
function fillCreditsCommits(md, deployed, feeds) {
  const FULL = /^[0-9a-f]{40}$/;
  const SOME = /^[0-9a-f]{7,40}$/;
  const tree = 'https://github.com/EvilPatrick06/skymp/tree/';
  const link = function (c) { return '[`' + c.slice(0, 8) + '`](' + tree + c + ')'; };
  const pick = function (ch) {
    const e = deployed && typeof deployed === 'object' ? deployed[ch] : null;
    const c = e && typeof e === 'object' ? String(e.commit || '') : '';
    return FULL.test(c) ? c : null;
  };
  let out = String(md);
  const live = pick('live');
  const dev = pick('dev');
  if (live && dev) {
    const rec = /built from one commit,\s+\[`[0-9a-f]{7,40}`\]\(https:\/\/github\.com\/EvilPatrick06\/skymp\/tree\/([0-9a-f]{40})\)/.exec(out);
    const recorded = rec ? rec[1] : '';
    let said;
    if (live === dev) {
      said = live === recorded ? 'Both servers run it, ' + link(live) + '.'
                               : 'The recorded build has not been deployed yet. Both servers run ' + link(live) + '.';
    } else {
      said = (live !== recorded && dev !== recorded ? 'The recorded build has not been deployed yet. ' : '') +
             'The test server runs ' + link(dev) + ' and the main server runs ' + link(live) + '.';
    }
    // The hand sentence runs from "then to the main server." to "the earlier
    // engine ...", whatever it says about which server runs what (#2098).
    out = out.replace(/(then to the main server\.\s+)((?:(?!\n\s*\n)[\s\S])*?)\[`[0-9a-f]{7,40}`\]\([^)\s]*\),\s+the earlier engine[^.]*\./,
                      function (m, lead) { return lead + said; });
  }
  for (const row of [['Public', 'feed/version.json', 'public'], ['Dev', 'feed-dev/version.json', 'dev']]) {
    const c = feeds && typeof feeds === 'object' ? String(feeds[row[2]] || '') : '';
    if (!SOME.test(c)) continue;
    const re = new RegExp('(^|\\n)(\\|\\s*' + row[0] + '\\s*\\|\\s*`' + row[1].replace(/[./]/g, '\\$&') +
                          '`\\s*\\|\\s*)\\[`[0-9a-f]{7,40}`\\]\\([^)\\s]*\\)');
    out = out.replace(re, function (m, a, b) { return a + b + link(c); });
  }
  return out;
}
// ==== end thornswood credits fill ====
const DEPLOYED_BUILD = path.join(DATA, 'deployed-build.json');
function readJsonQuiet(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); } catch (e) { return null; }
}
function creditsFacts() {
  const feeds = {};
  for (const pair of [['public', 'feed'], ['dev', 'feed-dev']]) {
    const v = readJsonQuiet(path.join(ROOT, pair[1], 'version.json'));
    const c = v && v.clientRuntime && v.clientRuntime.forkCommit;
    if (typeof c === 'string') feeds[pair[0]] = c;
  }
  return { deployed: readJsonQuiet(DEPLOYED_BUILD), feeds: feeds };
}

// Public discovery uses the configured project domain, never a request's Host.
const PUBLIC_ORIGIN = 'https://thornswood.net';
function singlePageHeading(body, title) {
  let seen = false;
  body = body.replace(/<h1\b([^>]*)>([\s\S]*?)<\/h1>/gi, (whole, attrs, text) => {
    if (!seen) { seen = true; return whole; }
    return '<h2' + attrs + '>' + text + '</h2>';
  });
  return seen ? body : '<h1>' + escAttr(title) + '</h1>' + body;
}
function publicPageBody(route) {
  const b = BLURB[route];
  let body = '<h1>' + escAttr(b[0]) + '</h1><p>' + escAttr(b[1]) + '</p>';
  if (route === '/news') {
    const feed = publicJson(NEWS, {news:[]});
    const news = (Array.isArray(feed.news) ? feed.news : []).slice(0, 60);
    if (feed.launcher) body += '<p>Launcher <b>' + escAttr(feed.launcher) + '</b> is current.</p>';
    for (const n of news) {
      const details = Array.isArray(n.details) ? n.details : (n.details ? [n.details] : []);
      body += '<article class="rel"><div class="when">' + escAttr(n.date || '') + '</div><h2>' +
        escAttr(n.title || '') + '</h2>' + (n.body ? '<p>' + escAttr(n.body) + '</p>' : '') +
        (details.length ? '<ul>' + details.map(d => '<li>' + escAttr(d) + '</li>').join('') + '</ul>' : '') + '</article>';
    }
    if (!news.length) body += '<p>No release notes are available yet.</p>';
  } else if (route === '/roadmap') {
    // Same public board as /api/roadmap; staff boards never enter this HTML.
    const rm = readBoard().roadmap || {sections:[]};
    if (rm.intro) body += pageHtml(rm.intro).replace(/<h1\b/g, '<h2').replace(/<\/h1>/g, '</h2>');
    let count = 0;
    for (const section of (rm.sections || [])) {
      if (/^\s*done\s*$/i.test(section.name || '') || !(section.rows || []).length) continue;
      body += '<section class="lane"><h2>' + escAttr(section.name || '') + '</h2><ul>';
      for (const row of section.rows) {
        const text = (section.columns || []).map(col => (row.cells || {})[col.id]).filter(Boolean).join(' · ');
        body += '<li>' + escAttr(text) + '</li>'; count++;
      }
      body += '</ul></section>';
    }
    if (!count) body += '<p>No upcoming work is listed here yet. See <a href="/known">known issues</a> for current limits.</p>';
  } else if (route === '/gallery') {
    const shots = publicJson(GALLERY, []);
    const approved = (Array.isArray(shots) ? shots : []).slice(0, 24);
    body += '<p>Only pictures approved by staff appear here. <a href="/privacy">How submissions are used</a>.</p><div class="gallery">';
    for (const g of approved) {
      if (!/^\/shot\/[^?#]+$/.test(g.url || '')) continue;
      const alt = g.alt || 'Skyrim scene shared by ' + (g.by || 'the Thornswood community');
      const media = /\.(mp4|webm)$/i.test(g.name || '')
        ? '<video controls preload="metadata" aria-label="' + escAttr(alt) + '"><source src="' + escAttr(g.url) + '"></video>'
        : '<img src="' + escAttr(g.url) + '" alt="' + escAttr(alt) + '" loading="lazy">';
      body += '<figure class="shot-card"><div class="shot">' + media + '</div><figcaption>' + escAttr(g.by || 'Thornswood community') + '</figcaption></figure>';
    }
    body += '</div>';
    if (!approved.length) body += '<p>No approved pictures are available yet.</p>';
  } else if (route === '/downloads') {
    body += '<p>You need to own Skyrim Special Edition on Steam and be eighteen or older.</p>' +
      '<p><a href="/join">Read the installation and application steps</a>. ' +
      '<a href="/help">Get installation help</a>.</p>' +
      '<p>The download controls appear after the age statement. JavaScript is needed for those controls.</p>';
  } else if (route === '/report') {
    body += '<p>Reports are private. Your Discord name is optional for game faults and ideas. ' +
      'A report about a person requires Discord sign-in.</p>' +
      '<p>Do not include passwords, access tokens, payment details, or unrelated personal information. ' +
      '<a href="/privacy">Read how reports are stored and used</a>.</p>' +
      '<p>The report form needs JavaScript. You can also ask for help in the Discord linked above.</p>';
  }
  return body;
}
const publicAssetVersions = new Map();
function publicAssetVersion(asset) {
  const file = path.join(PUBLIC, asset);
  try {
    const st = fs.statSync(file), key = st.size + ':' + st.mtimeMs + ':' + st.ctimeMs;
    const cached = publicAssetVersions.get(asset);
    if (cached && cached.key === key) return cached.version;
    const version = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').slice(0, 16);
    publicAssetVersions.set(asset, {key, version}); return version;
  } catch (e) { return null; }
}
function publicDiscovery(html, route) {
  const blurb = BLURB[route], canonical = PUBLIC_ORIGIN + route;
  const title = route === '/' ? blurb[0] : blurb[0] + ' · Thornswood';
  const graph = [
    {'@type':'Organization', '@id':PUBLIC_ORIGIN+'/#community', name:'Thornswood', url:PUBLIC_ORIGIN+'/',
      logo:PUBLIC_ORIGIN+'/logo.png', description:'A free Skyrim roleplay fan project and online community.'},
    {'@type':'WebSite', '@id':PUBLIC_ORIGIN+'/#website', url:PUBLIC_ORIGIN+'/', name:'Thornswood',
      publisher:{'@id':PUBLIC_ORIGIN+'/#community'}},
    {'@type':'WebPage', '@id':canonical+'#page', url:canonical, name:title, description:blurb[1],
      isPartOf:{'@id':PUBLIC_ORIGIN+'/#website'}, inLanguage:'en'}
  ];
  if (route !== '/') {
    graph[2].breadcrumb = {'@id':canonical+'#breadcrumb'};
    graph.push({'@type':'BreadcrumbList', '@id':canonical+'#breadcrumb', itemListElement:[
      {'@type':'ListItem', position:1, name:'Thornswood', item:PUBLIC_ORIGIN+'/'},
      {'@type':'ListItem', position:2, name:blurb[0], item:canonical}
    ]});
    html = html.replace('<main id="main" tabindex="-1">', () => '<main id="main" tabindex="-1"><nav class="wrap breadcrumbs" aria-label="Breadcrumb">' +
      '<ol><li><a href="/">Thornswood</a></li><li aria-current="page">' + escAttr(blurb[0]) + '</li></ol></nav>');
  }
  // Escape the HTML script terminator even if metadata becomes editable later.
  const ld = JSON.stringify({'@context':'https://schema.org', '@graph':graph}).replace(/</g, '\\u003c');
  const head = '<link rel="canonical" href="' + canonical + '">\n' +
    '<meta property="og:url" content="' + canonical + '">\n' +
    '<meta property="og:image:alt" content="Thornswood emblem over a painted Skyrim landscape">\n' +
    '<meta name="twitter:image:alt" content="Thornswood emblem over a painted Skyrim landscape">\n' +
    '<meta name="twitter:title" content="' + escAttr(title) + '">\n' +
    '<meta name="twitter:description" content="' + escAttr(blurb[1]) + '">\n' +
    '<script type="application/ld+json">' + ld + '</script>\n';
  for (const asset of ['home.js', 'home.css']) {
    const version = publicAssetVersion(asset);
    if (!version) continue;
    html = html.replace('"/' + asset + '"', () => '"/' + asset + '?v=' + version + '"');
  }
  return html.replace(/<title>[\s\S]*?<\/title>/, () => '<title>' + escAttr(title) + '</title>')
    .replace('</head>', () => head + '</head>');
}


// ==== thornswood page versions ====
/* SHA-256 of a page's text as /api/page serves it, the same bytes the
   installer writes into Profile\accepted.json. public/page-versions.json
   lists every wording that has been on main, so a hash already accepted
   can be read back to the day that wording last changed. */
const PAGE_VERSIONS = path.join(PUBLIC, 'page-versions.json');
function pageSha256(md) {
  return crypto.createHash('sha256').update(String(md), 'utf8').digest('hex');
}
function pageVersionRows() {
  try {
    const doc = JSON.parse(fs.readFileSync(PAGE_VERSIONS, 'utf8'));
    return doc && doc.pages && typeof doc.pages === 'object' ? doc.pages : {};
  } catch (e) { return {}; }
}
function findPageVersion(sha) {
  const want = String(sha || '').toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(want)) return null;
  const pages = pageVersionRows();
  for (const name of Object.keys(pages)) {
    const rows = Array.isArray(pages[name]) ? pages[name] : [];
    for (const row of rows) {
      if (row && String(row.sha256 || '').toLowerCase() === want) {
        return { page: name, sha256: want, changed: String(row.changed || '') };
      }
    }
  }
  return null;
}
// ==== end thornswood page versions ====

// ==== thornswood open switch ====
/* The one switch (#428), cfg.open, off unless config.json says true.

   playRoles is the play list with Member added when the world is open to
   everybody. Staff give Member after an application is accepted. Discord
   has no default-role setting. Playtester (access.play) is what opens the
   game while the switch is off. With the switch off the list is left
   exactly as it was.

   forMode is how the written pages follow the same switch. A page marks its
   alpha wording with <!-- alpha --> ... <!-- /alpha --> lines and its open
   wording with <!-- open --> ... <!-- /open -->, and only the one that
   applies is served. bot/content.py reads join.md through the same markers
   for #start-here, so the site and the Discord cannot disagree. */
function playRoles(play, open) {
  const list = Array.isArray(play) ? play.slice() : [];
  if (open === true && list.indexOf('Member') < 0) list.push('Member');
  return list;
}

function forMode(md, open) {
  const drop = open === true ? 'alpha' : 'open';
  return String(md)
    .replace(new RegExp('^<!-- ' + drop + ' -->[ \\t]*\\r?\\n[\\s\\S]*?^<!-- /' + drop +
                        ' -->[ \\t]*(?:\\r?\\n|$)', 'gm'), '')
    .replace(/^<!-- \/?(?:alpha|open) -->[ \t]*(?:\r?\n|$)/gm, '');
}
/* What somebody in the Discord without a play role is told, by the launcher's
   door, the join pass and the sign in page. In the alpha that is an
   application; with the switch on it is only the Member role. With inner, the
   words that follow "That account is in the Discord, but". */
function notAcceptedYet(inner) {
  const open = cfg.open === true;
  const how = open
    ? 'Ask in the Discord and somebody will sort it.'
    : 'Apply in the Discord: open a ticket and pick Apply to be an alpha playtester.';
  if (inner) {
    return (open ? 'it does not have the Member role yet. '
                 : 'it has not been accepted into the alpha yet. ') + how;
  }
  return (open ? 'That Discord account does not have the Member role yet. '
               : 'That Discord account has not been accepted into the alpha yet. ') + how;
}
// ==== end thornswood open switch ====

const PAGES = {
  '/hub':         'home',
  '/uploads':     'uploads',
  '/linked':      'linked',
  '/sessions':    'sessions',
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
/*
  And the most the world holds at once (#481): the gamemode writes the
  server's own number into the same file as max, so the page says "3 of 25"
  and /api/play/join can say the world is full before the game starts.
*/
/*
  And how many wait at the menu for a seat (line), and whether somebody
  picking now would wait too (full), which the gamemode's seats block works
  out and writes beside the count.
*/
let gameStatus = { up: false, online: 0, max: 0, line: 0, full: false, at: 0 };
function pollGame() {
  const sock = new net.Socket();
  let done = false;
  const finish = (up) => {
    if (done) return;
    done = true;
    try { sock.destroy(); } catch (e) { }
    let online = 0, max = 0, line = 0, full = false;
    try {
      const o = JSON.parse(fs.readFileSync(cfg.onlineFile, 'utf8'));
      if (o && typeof o.now === 'number') online = o.now;
      if (o && typeof o.max === 'number' && o.max > 0) max = o.max;
      if (o && typeof o.line === 'number' && o.line > 0) line = o.line;
      if (o && o.full === true) full = true;
    } catch (e) { }
    gameStatus = { up, online: up ? online : 0, max: up ? max : 0, line: up ? line : 0,
                   full: up && full, at: Date.now() };
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

/*
  Whether somebody pressing Play now would wait for a seat, and what they are
  told (#481). Nobody is refused for numbers any more: Patrick, 29 Sep, a
  full world lets them into the game's menu, where they wait in line and join
  by themselves when it is their turn. The gamemode keeps the line.
*/
function seatsFull(st) {
  return !!(st && st.up && (st.full === true || (st.max > 0 && st.online >= st.max)));
}
function worldFull(max) {
  return 'Thornswood is full right now: ' + max + ' people are in the world, the most it holds ' +
    'at once during the alpha. Pick your character anyway: you will wait at the menu with your ' +
    'place in line on screen, and join by yourself when a seat frees.';
}

/*
  The most the world holds, for the home page and /api/public, when the
  server has not said (#481). Patrick, 29 Sep: "I still want it to say N of
  25 anyway". records\most-online.json is the one place the number lives:
  read here when the site runs from the repository, and otherwise the main
  feed's maxOnline, which Publish-Update.ps1 writes from that same file and
  which the site on the VPS already serves. The server's own max still wins.
*/
const MOST_ONLINE_RECORD = path.join(ROOT, '..', 'records', 'most-online.json');
let mostOnlineSeen = { file: '', mtime: -1, size: -1, v: 0 };
function mostOnlineFallback() {
  for (const file of [MOST_ONLINE_RECORD, path.join(ROOT, 'feed', 'version.json')]) {
    let st;
    try { st = fs.statSync(file); } catch (e) { continue; }
    if (mostOnlineSeen.file === file && mostOnlineSeen.mtime === st.mtimeMs && mostOnlineSeen.size === st.size) {
      if (mostOnlineSeen.v > 0) return mostOnlineSeen.v;
      continue;
    }
    let v = 0;
    try {
      const doc = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, '')) || {};
      const n = Number(file === MOST_ONLINE_RECORD ? doc.people : doc.maxOnline);
      if (n > 0 && Math.floor(n) === n) v = n;
    } catch (e) { v = 0; }
    mostOnlineSeen = { file, mtime: st.mtimeMs, size: st.size, v };
    if (v > 0) return v;
  }
  return 0;
}

const jsonFile = (p, fallback) => {
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); }
  catch (e) {
    // A missing file is the normal empty case. A file that exists but will
    // not parse usually means a crash mid-write left truncated JSON; shout
    // so bans / linked / inbox do not silently become the empty fallback.
    try {
      if (fs.existsSync(p)) {
        console.error('[thornswood-docs] JSON will not parse, using fallback for ' + p + ': ' + (e && e.message || e));
      }
    } catch (e2) { }
    return fallback;
  }
};
const putJson = (p, o) => {
  // Same-folder temp + rename so a crash mid-write cannot leave truncated
  // JSON that jsonFile would then quietly replace with the empty fallback
  // (bans, linked accounts, inbox, and the rest of putJson callers).
  try {
    const body = JSON.stringify(o, null, 2);
    const dir = path.dirname(p);
    const tmp = path.join(dir, '.' + path.basename(p) + '.' + process.pid + '.tmp');
    fs.writeFileSync(tmp, body, 'utf8');
    try { fs.renameSync(tmp, p); }
    catch (e) {
      // Windows: rename onto an existing file can fail; replace then drop tmp.
      try { fs.copyFileSync(tmp, p); } finally { try { fs.unlinkSync(tmp); } catch (e2) { } }
    }
    return true;
  } catch (e) {
    try { fs.unlinkSync(path.join(path.dirname(p), '.' + path.basename(p) + '.' + process.pid + '.tmp')); } catch (e2) { }
    return false;
  }
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
// EVERY BOARD HAS A REVISION (#2188). One board is saved at a time, so two
// people on two boards never overwrite each other, but until 11 October two
// people on the SAME board did, silently: last save won and the other edit
// was gone. Now board.json keeps _rev, a number per board, bumped on every
// save. /api/all hands the hub each board's number as boardRevs, the hub
// sends back the one it last saw in X-Board-Rev, and a save made from an
// older copy is refused with 409 and a sentence saying to reload, rather
// than written over somebody else's change. A save with no X-Board-Rev at
// all (a hub page opened before this went live) is refused with 428 for the
// same reason: it cannot say which copy it was made from. The check and the
// write are one synchronous step in one process, so two saves cannot both
// pass it.
function boardRev(all, name) {
  const r = all && all._rev && all._rev[name];
  return (typeof r === 'number' && r >= 0 && Math.floor(r) === r) ? r : 0;
}
function writeBoardOne(name, value, seenRev) {
  if (!Object.prototype.hasOwnProperty.call(BOARDS, name)) return { ok: false, status: 400, error: 'no such board' };
  const all = readBoard();
  const now = boardRev(all, name);
  if (seenRev === undefined || seenRev === null || seenRev === '') {
    return { ok: false, status: 428, error: 'no revision', rev: now,
      message: 'This page was opened before boards checked for clashing saves. Reload it, then make your change again.' };
  }
  if (String(seenRev) !== String(now)) {
    return { ok: false, status: 409, error: 'conflict', rev: now,
      message: 'Somebody else saved this board since you opened it, so your change was not saved over theirs. Reload to see their change, then make yours again.' };
  }
  all[name] = value;
  all._rev = Object.assign({}, all._rev && typeof all._rev === 'object' ? all._rev : {});
  all._rev[name] = now + 1;
  try { fs.copyFileSync(BOARDFILE, BOARDFILE + '.bak'); } catch (e) { }
  if (!putJson(BOARDFILE, all)) return { ok: false, status: 500, error: 'could not save' };
  return { ok: true, status: 200, rev: now + 1 };
}

const RESULTS = path.join(DATA, 'results.json');
const INBOX   = path.join(FOR_BOT, 'inbox.json');

// ==== thornswood rules accepted ====
/* Who accepted the rules, by Discord id (#428). Before this nobody ever did:
   somebody could join for the invite, be let in and press Play having agreed
   to nothing. The alpha application in the Discord asks, the bot sends the
   answer with the ticket, and it is kept here rather than only in the inbox,
   because the inbox is trimmed and this record should not be.

   One row per Discord id: the latest answer, its time and their words, and
   the time of their first yes, which a later answer never moves. A file that
   is there and cannot be read is never written over, so a bad read cannot
   throw everybody else's answers away. */
const RULES_OK = path.join(DATA, 'rules-accepted.json');

function noteRules(file, discordId, rules, by, now) {
  const id = String(discordId || '').replace(/[^0-9]/g, '').slice(0, 20);
  if (!id || !rules || typeof rules !== 'object') return false;
  let book = {};
  if (fs.existsSync(file)) {
    try { book = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, '')); }
    catch (e) { return false; }
    if (!book || typeof book !== 'object' || Array.isArray(book)) return false;
  }
  const had = (book[id] && typeof book[id] === 'object') ? book[id] : {};
  const yes = rules.yes === true;
  book[id] = {
    yes: yes,
    at: now,
    said: String(rules.said || '').slice(0, 200),
    by: String(by || '').slice(0, 60),
    firstYes: had.firstYes || (yes ? now : null)
  };
  return putJson(file, book);
}
// ==== end thornswood rules accepted ====

/* Written by Publish-News.ps1 at the end of every release: the same feed the
   launcher shows, stripped of the server password before it leaves his
   machine. Nothing here writes it. */
const NEWS    = path.join(DATA, 'news.json');

// Cache only immutable public reads, invalidated by file changes. Never reuse
// authorization, bans, account records, or a staff board through this cache.
const publicJsonCache = new Map();
function publicJson(file, fallback) {
  if (file !== NEWS && file !== GALLERY) throw new Error('not a public cache file');
  let st;
  try { st = fs.statSync(file); } catch (e) { publicJsonCache.delete(file); return fallback; }
  const key = st.size + ':' + st.mtimeMs + ':' + st.ctimeMs;
  const old = publicJsonCache.get(file);
  if (old && old.key === key) return old.value;
  const value = jsonFile(file, fallback);
  publicJsonCache.set(file, {key, value});
  return value;
}
function galleryPage(offset, limit) {
  const raw = publicJson(GALLERY, []), shots = Array.isArray(raw) ? raw : [];
  return {gallery:shots.slice(offset, offset + limit), total:shots.length,
    next:offset + limit < shots.length ? offset + limit : null};
}

// In-memory, salted connection keys expire after a minute and are never logged.
// This is a single-process service; multiple replicas would need a shared cap.
const publicApiReads = new Map();
const PUBLIC_API_WINDOW = 60000, PUBLIC_API_CAP = 120;
function publicApiWait(req, now) {
  for (const [key, row] of publicApiReads) if (now - row.start >= PUBLIC_API_WINDOW) publicApiReads.delete(key);
  const key = reportFrom(req);
  let row = publicApiReads.get(key);
  if (!row) {
    if (publicApiReads.size >= 4096) return 1;
    row = {start:now, count:0}; publicApiReads.set(key, row);
  }
  if (row.count >= PUBLIC_API_CAP) return Math.max(1, Math.ceil((row.start + PUBLIC_API_WINDOW - now) / 1000));
  row.count++; return 0;
}

// ==== thornswood report limits ====
//
// THE PUBLIC REPORT FORM TOOK ANYTHING FROM ANYBODY, AS OFTEN AS THEY LIKED.
// No limit, nothing to tell a person from a script, and one list shared with
// the bot's tickets and trimmed to its newest 2000 rows. So 2000 posts from
// anywhere pushed every ticket and every real report off the end of
// inbox.json, on a page that tells the person "Somebody will read it".
//
// FIVE AN HOUR AND TWENTY A DAY FROM ONE PLACE. Somebody with a real problem
// sends one or two. Past that the answer is a 429 with a sentence saying when
// to try again, never a quiet drop: a limiter that swallows a report and says
// Sent breaks that promise worse than the flood did. Only reports that were
// taken count, so a script hammering on a refusal does not keep somebody on
// the same connection locked out for ever.
//
// WHERE A REQUEST COMES FROM. Caddy holds 443 and hands everything on from
// 127.0.0.1, so behind it every request looks like it came from here, and
// keyed on that the form would lock for everybody after five reports. The
// forwarded header is believed only when the socket really is loopback, which
// is Caddy, and only its LAST hop, which is the one Caddy wrote; anything
// before it is whatever the sender typed. A request that reached 3001 straight
// (THORNSWOOD_DOCS_LOCAL not set) is keyed by its own socket and its header is
// ignored. An IPv6 address counts as its /64, because one home connection is
// handed a whole /64 and would otherwise be millions of senders.
//
// NO ADDRESS IS KEPT. privacy.md says the sign-in log is the only thing here
// holding one. This table holds a hash of it under a key made fresh at every
// start and never written anywhere, and forgets it after a day. That is also
// why the cap per sender lives here at the door rather than in inbox.json:
// capping the file per sender would mean writing who sent each report into it.
//
// TICKETS AND REPORTS ARE TRIMMED APART. Each kind keeps the newest 2000 the
// shared list used to keep, so nothing posted to the public page can push a
// ticket out, and a pile of tickets cannot push a report out either.
const REPORT_HOUR = 5;
const REPORT_DAY = 20;
const INBOX_KEEP = 2000;
const reportSalt = crypto.randomBytes(32);
const reportSeen = new Map();

// THE ONE TRUSTED-PROXY BOUNDARY (#2187). requestAddr is the address a request
// came from, and both the report limit below and the sign-in log use it, so
// there is one rule rather than two. The socket is the truth. X-Forwarded-For
// is believed only when the socket is a proxy we run: loopback, which is
// Caddy, or an address listed in THORNSWOOD_TRUSTED_PROXIES (comma separated,
// for a proxy on another box; empty by default). Even then only the LAST hop
// is taken, the one that proxy wrote: anything before it is whatever the
// sender typed. A direct caller's header is ignored entirely. Until 11
// October the sign-in log took the FIRST hop from anybody, so any caller could
// write any address into signins.json.
const TRUSTED_PROXIES = new Set(String(process.env.THORNSWOOD_TRUSTED_PROXIES || '')
  .split(',').map((s) => s.trim().toLowerCase().replace(/^::ffff:(?=\d+\.\d+\.\d+\.\d+$)/, ''))
  .filter(Boolean));

function requestAddr(req) {
  const plain = (a) => String(a || '').trim().toLowerCase()
    .replace(/^::ffff:(?=\d+\.\d+\.\d+\.\d+$)/, '');
  const sock = plain(req.socket && req.socket.remoteAddress);
  let addr = sock;
  if (/^(127\.|::1$)/.test(sock) || TRUSTED_PROXIES.has(sock)) {
    const hops = String((req.headers && req.headers['x-forwarded-for']) || '').split(',')
      .map((s) => s.trim()).filter(Boolean);
    const last = hops.length ? plain(hops[hops.length - 1]) : '';
    if (last && net.isIP(last)) addr = last;
  }
  return addr;
}

function clientAddr(req) {
  let addr = requestAddr(req);
  if (net.isIPv6(addr)) {
    const halves = addr.split('%')[0].split('::');
    const head = halves[0] ? halves[0].split(':') : [];
    const tail = halves.length > 1 && halves[1] ? halves[1].split(':') : [];
    const gap = halves.length > 1 ? Math.max(0, 8 - head.length - tail.length) : 0;
    addr = head.concat(new Array(gap).fill('0'), tail).slice(0, 4)
      .map((g) => (parseInt(g, 16) || 0).toString(16)).join(':') + '::/64';
  }
  return addr;
}

function reportFrom(req) {
  return crypto.createHmac('sha256', reportSalt).update(clientAddr(req)).digest('hex').slice(0, 32);
}

function reportRefusal(key, now, whose) {
  const from = whose || 'your connection';
  const HOUR = 60 * 60 * 1000, DAY = 24 * HOUR;
  const at = Number(now) || Date.now();
  const day = (reportSeen.get(key) || []).filter((t) => t > at - DAY);
  const hour = day.filter((t) => t > at - HOUR);
  const wait = (ms) => Math.max(1, Math.ceil(ms / 1000));
  const said = (s) => s >= 5400 ? 'about ' + Math.round(s / 3600) + ' hours'
    : 'about ' + Math.max(1, Math.ceil(s / 60)) + (s > 60 ? ' minutes' : ' minute');
  if (hour.length >= REPORT_HOUR) {
    const s = wait(hour[0] + HOUR - at);
    return { wait: s, error: 'That is five reports from ' + from + ' in the last hour, ' +
      'which is as many as this page takes. Try again in ' + said(s) +
      ', or open a ticket in the Discord if it cannot wait.' };
  }
  if (day.length >= REPORT_DAY) {
    const s = wait(day[0] + DAY - at);
    return { wait: s, error: 'That is twenty reports from ' + from + ' today, ' +
      'which is as many as this page takes in a day. Try again in ' + said(s) +
      ', or open a ticket in the Discord if it cannot wait.' };
  }
  return null;
}

function reportTaken(key, now) {
  const list = reportSeen.get(key) || [];
  list.push(Number(now) || Date.now());
  reportSeen.set(key, list.slice(-REPORT_DAY));
}

function reportPrune(now) {
  const cut = (Number(now) || Date.now()) - 24 * 60 * 60 * 1000;
  for (const [key, list] of reportSeen) {
    const kept = list.filter((t) => t > cut);
    if (kept.length) reportSeen.set(key, kept); else reportSeen.delete(key);
  }
}

function trimInbox(rows) {
  let tickets = 0, reports = 0;
  return (Array.isArray(rows) ? rows : []).filter((r) =>
    (r && r.kind === 'ticket') ? ++tickets <= INBOX_KEEP : ++reports <= INBOX_KEEP);
}
// ==== end thornswood report limits ====
setInterval(() => reportPrune(Date.now()), 10 * 60 * 1000).unref?.();

// ==== thornswood login limits ====
// POST /api/login only (#1305). The issue names no numbers, so this is a
// small fixed window: eight attempts from one address in ten minutes, then
// 429 until the oldest of those falls out of the window. Past that window
// a member-password guess waits longer each time (#1308). Nothing else on
// the site reads these tables. The address rules are the report form's: the
// last forwarded hop, and only when the socket is loopback (Caddy). The
// address is hashed under a key made at this start and never written.
const LOGIN_MAX = 8;
const LOGIN_WINDOW_MS = 10 * 60 * 1000;
const loginSalt = crypto.randomBytes(32);
const loginSeen = new Map();

function loginKey(req) {
  return crypto.createHmac('sha256', loginSalt).update(clientAddr(req)).digest('hex').slice(0, 32);
}

function loginWait(key, now) {
  const at = Number(now) || Date.now();
  const list = (loginSeen.get(key) || []).filter((t) => t > at - LOGIN_WINDOW_MS);
  if (list.length) loginSeen.set(key, list); else loginSeen.delete(key);
  if (list.length < LOGIN_MAX) return 0;
  return Math.max(1, Math.ceil((list[0] + LOGIN_WINDOW_MS - at) / 1000));
}

function loginNote(key, now) {
  const at = Number(now) || Date.now();
  const list = (loginSeen.get(key) || []).filter((t) => t > at - LOGIN_WINDOW_MS);
  list.push(at);
  loginSeen.set(key, list);
}

// Once the window is full, each further member-password guess waits longer
// than the one before it (#1308). The extra starts at 30 seconds and doubles,
// up to an hour. It is added only when Discord OAuth is not configured, which
// is the only time this route reads a password. A correct password clears it.
// An address that has been quiet for a whole window is dropped.
const LOGIN_BACKOFF_CAP_S = 60 * 60;
const loginBackoff = new Map();

function loginBackoffBump(key, now, windowWait) {
  const at = Number(now) || Date.now();
  const prev = loginBackoff.get(key) || { n: 0 };
  const n = (prev.n || 0) + 1;
  const shift = Math.min(Math.max(n - 1, 0), 10);
  const extra = Math.min(LOGIN_BACKOFF_CAP_S, 30 * (1 << shift));
  const wait = Math.max(1, (Number(windowWait) || 0) + extra);
  loginBackoff.set(key, { n, until: at + wait * 1000 });
  return wait;
}

function loginPrune(now) {
  const at = Number(now) || Date.now();
  const cut = at - LOGIN_WINDOW_MS;
  for (const [key, list] of loginSeen) {
    const kept = list.filter((t) => t > cut);
    if (kept.length) loginSeen.set(key, kept); else loginSeen.delete(key);
  }
  for (const [key, rec] of loginBackoff) {
    if (!rec || rec.until < cut) loginBackoff.delete(key);
  }
}
setInterval(() => loginPrune(Date.now()), 10 * 60 * 1000).unref?.();
// ==== end thornswood login limits ====

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
    // page can print it beside the size and date (To Do entry 176). Only a well
    // formed hash goes out, in lower case because Get-FileHash writes upper and
    // the page builds an address from it.
    const sha256 = String(m.sha256 || '').toLowerCase();
    const hash = /^[0-9a-f]{64}$/.test(sha256) ? sha256 : '';
    out.push({ name, size: st.size, at: st.mtimeMs, hidden: !!m.hidden || script,
      label: m.label || name, version: m.version || '', note: m.note || '',
      sha256: hash });
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
// The two lists the gallery keeps in data/, deployed by the same rule as every
// other data JSON (Deploy-Docs sends a data JSON only when the VPS is missing
// it, so neither is ever overwritten once it exists there). gallery.json is the
// approved list /api/public and /shot read; gallery-pending.json is what is
// waiting for staff to Accept, and is never public. Unaccepted items sit
// in the staff Gallery until Accept or Delete; there is no Reject.
const GALLERY = path.join(DATA, 'gallery.json');
const GPENDING = path.join(DATA, 'gallery-pending.json');
/* Serialise gallery-pending.json writes. The site form can POST several files
   back to back; without this, two read-modify-write callbacks can drop one. */
let galleryPendingWrite = Promise.resolve();
function withGalleryPending(fn) {
  const run = galleryPendingWrite.then(() => fn());
  galleryPendingWrite = run.catch(() => {});
  return run;
}
// Reports against approved shots. Same deploy rule as the queue: starts [],
// and Deploy-Docs only sends it when the VPS is missing it.
const GREPORTS = path.join(DATA, 'gallery-reports.json');
// What the gallery accepts and how big. Images and screen recordings (mp4,
// webm). /shot honours a byte range the same way public/ and /file do, so
// Safari and iOS can play an approved recording. Cap is 100 MB for
// recordings. The launcher AllowExt must match this list.
const GALLERY_ALLOW = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.mp4', '.webm'];
const GALLERY_CAP = 100 * 1024 * 1024;
const KIND = {
  '.png':'image/png', '.jpg':'image/jpeg', '.jpeg':'image/jpeg', '.gif':'image/gif',
  '.webp':'image/webp', '.bmp':'image/bmp',
  '.mp4':'video/mp4', '.webm':'video/webm',
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

/* One place that takes a file off a request and lands it in uploads/ under a
   stamped name, so /api/upload and /api/gallery/submit stamp and cap the same
   way and a change to either is a change to both. The request body IS the file,
   the way /api/upload has always worked, so the name and any note ride in the
   query. asked is the name the caller offered; cap is the byte ceiling; allow
   is null for any kind or a list of lower case extensions (with the dot) when a
   route only wants some. It answers 413 or 415 itself and returns; on a good
   file it calls saved(name) and leaves the reply to the route, because /upload
   and /gallery/submit write different things once the bytes are down. */
// ==== thornswood upload guard ====
const uploadBudgets = new Map();
function mediaSignature(ext, bytes) {
  if (ext === '.png') return bytes.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex'));
  if (ext === '.jpg' || ext === '.jpeg') return bytes.subarray(0,3).equals(Buffer.from('ffd8ff','hex'));
  if (ext === '.gif') return /^GIF8[79]a$/.test(bytes.subarray(0,6).toString('ascii'));
  if (ext === '.webp') return bytes.subarray(0,4).toString('ascii') === 'RIFF' && bytes.subarray(8,12).toString('ascii') === 'WEBP';
  if (ext === '.mp4') return bytes.subarray(4,8).toString('ascii') === 'ftyp';
  if (ext === '.webm') return bytes.subarray(0,4).equals(Buffer.from('1a45dfa3','hex'));
  return false;
}
function receiveUpload(req, res, asked, cap, allow, saved) {
  if (Number(req.headers['content-length'] || 0) > cap) {
    return sendJson(res, 413, { error: 'that file is over ' + Math.round(cap / 1048576) + ' MB' });
  }
  const offered = String(asked || 'file').split(/[\\/]/).pop();
  const safe = offered.replace(/[^A-Za-z0-9._ -]/g, '_').replace(/^[. ]+/, '')
                      .slice(0, 90) || 'file';
  if (allow) {
    const ext = path.extname(safe).toLowerCase();
    if (allow.indexOf(ext) < 0) {
      req.resume();
      return sendJson(res, 415, { error: 'that kind of file is not allowed here', allowed: allow });
    }
  }
  const now = Date.now(), key = reportFrom(req);
  for (const [k, row] of uploadBudgets) if (!row.active && now - row.start >= 3600000) uploadBudgets.delete(k);
  let budget = uploadBudgets.get(key);
  if (!budget) {
    if (uploadBudgets.size >= 4096) return sendJson(res, 503, {error:'Uploads are busy. Try again shortly.'});
    budget = {start:now, count:0, bytes:0, active:0}; uploadBudgets.set(key, budget);
  }
  if (budget.active >= 2 || budget.count >= 40 || budget.bytes >= 500 * 1048576) {
    req.resume();
    return send(res, 429, JSON.stringify({error:'This connection has reached its upload limit. Try again later.'}),
      null, {'Retry-After':String(Math.max(1, Math.ceil((budget.start + 3600000 - now) / 1000))), Connection:'close'});
  }
  budget.count++; budget.active++;
  const d = new Date();
  const two = (n) => String(n).padStart(2, '0');
  const stamp = d.getFullYear() + two(d.getMonth() + 1) + two(d.getDate()) + '-' +
                two(d.getHours()) + two(d.getMinutes());
  const name = stamp + '-' + crypto.randomBytes(6).toString('hex') + '-' + safe;
  const dest = path.join(UP, name);
  let descriptor;
  try { descriptor = fs.openSync(dest, 'wx'); }
  catch (e) {
    budget.active--;
    return sendJson(res, 500, {error:'The site could not reserve an upload file. Try again shortly.'});
  }

  /* Over the cap or cut off partway, the half file goes (#1095). Over the cap
     it destroyed the request, so the 413 went to a socket already closed, and
     a sender that dropped partway never ended the pipe, so the half file sat
     open on disk and the route never answered. Now too big is answered 413
     and the rest read and thrown away, and a connection that went is closed
     with nothing left to say. */
  let got = 0, over = false, cut = false, broke = false, timedOut = false, quotaExceeded = false, prefix = Buffer.alloc(0);
  const out = fs.createWriteStream(dest, {fd:descriptor, autoClose:true});
  const deadline = setTimeout(() => {
    timedOut = true; req.unpipe(out); out.destroy(); req.resume();
  }, 300000);
  out.on('error', () => { broke = true; });
  req.on('data', (c) => {
    got += c.length;
    budget.bytes += c.length;
    if (budget.bytes > 500 * 1048576) quotaExceeded = true;
    if (prefix.length < 12) prefix = Buffer.concat([prefix, c.subarray(0, 12 - prefix.length)]);
    if ((got > cap || budget.bytes > 500 * 1048576) && !over) { over = true; req.unpipe(out); out.destroy(); }
  });
  const drop = () => { if (!req.complete && !over && !cut) { cut = true; req.unpipe(out); out.destroy(); } };
  req.on('error', drop);
  req.on('aborted', drop);
  req.on('close', drop);
  req.pipe(out);
  out.on('close', () => {
    clearTimeout(deadline); budget.active--;
    const invalid = !over && !cut && !broke && !timedOut && allow && !mediaSignature(path.extname(safe).toLowerCase(), prefix);
    if (over || cut || broke || timedOut || invalid) {
      try { fs.unlinkSync(dest); } catch (e) { }
      if (timedOut) return send(res, 408, JSON.stringify({error:'That upload took too long. Try again with a smaller file.'}), null, {Connection:'close'});
      if (quotaExceeded) return send(res, 429, JSON.stringify({error:'This connection has uploaded 500 MB in the last hour. Try again later.'}),
        null, {'Retry-After':String(Math.max(1, Math.ceil((budget.start + 3600000 - Date.now()) / 1000))), Connection:'close'});
      if (invalid) return sendJson(res, 415, {error:'The file contents do not match its image or recording type.'});
      if (over) return send(res, 413, JSON.stringify({ error: 'that file is over ' + Math.round(cap / 1048576) + ' MB' }),
                            null, { Connection: 'close' });
      if (cut) { try { res.destroy(); } catch (e) { } return; }
      return sendJson(res, 500, { error: 'the site could not save that file. Try again in a minute.' });
    }
    saved(name);
  });
}

// ==== end thornswood upload guard ====
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
   or removing a person takes effect here without anybody editing a list.

   It carries when it was made as well, inside the signature, and anything
   older than ADMIN_DAYS reads as signed out. Max-Age is the browser promising
   to throw the cookie away; nothing held the site to it, so a value copied out
   of a browser was good forever, because all this checked was that the site
   had signed it. Entry 248. A cookie made before that has three parts rather
   than four and reads as signed out once. That only costs staff a sign in,
   because only staff may use the hub; the launcher's ticket is not this. */
const ADMIN_DAYS = 30;
function identity(req) {
  const raw = cookies(req)[ADMIN] || '';
  const [id, name, at, sig] = decodeURIComponent(raw).split('|');
  if (!id || !at || !sig) return null;
  if (!sameSecret(sig, sign(id + '|' + (name || '') + '|' + at))) return null;
  // A minute of slack the other way, for a clock that stepped back.
  const age = Date.now() - Number(at);
  if (!(age > -60000 && age < ADMIN_DAYS * 86400000)) return null;
  return { id: String(id), name: name || '' };
}

/* A minute of memory, so clicking around the site is not forty calls to
   Discord, and a ban still lands within a minute. */
const standCache = new Map();
async function standingCached(id) {
  const hit = standCache.get(id);
  // A staff ban (#412) is this site's own file, so a remembered one is asked
  // again: one that ran out or was lifted lets them in now, not in a minute.
  const stale = hit && hit.v && hit.v.byFile &&
    !banActive(jsonFile(BANS, {})[String(id)] || null, Date.now());
  if (hit && !stale && Date.now() - hit.at < 60000) return hit.v;
  const v = await standing(id);
  standCache.set(id, { at: Date.now(), v });
  if (!v.lookupFailed) standGood.set(id, { at: Date.now(), v });
  return v;
}
/* The last answer Discord actually gave for each account, kept past the
   minute above for STAND_STALE_MS so a page load can use it while Discord is
   slow (#1096). Only page loads read it (who() with staleOk); a failed lookup
   never lands here. */
const standGood = new Map();
const STAND_STALE_MS = 10 * 60000;

/* Every linked account's standing, for /api/allowed, inside the door's time.

   The route asked one account at a time. The door gives up after ten
   seconds (req.setTimeout in the gamemode's refresh), and when the bulk
   member list is refused each account is its own request to Discord: at
   100ms a call, a hundred linked accounts is ten seconds and the door never
   hears an answer at all (issue #415).

   So four at a time, and all of it inside DOOR_BUDGET_MS. An account not
   answered by then, or not asked because Discord said to wait longer than
   the time left, comes back as a failed lookup, which the route names in
   failedProfiles and the door keeps exactly as it was. A wait that ends
   inside the time left is waited out once, not once per account. */
const DOOR_BUDGET_MS = 7000;
const DOOR_LANES = 4;
async function standingsForDoor(ids) {
  const got = new Map();
  const started = Date.now();
  let timer = null;
  const late = new Promise((r) => { timer = setTimeout(() => r(null), DOOR_BUDGET_MS); });
  let next = 0;
  async function lane() {
    while (next < ids.length) {
      const id = ids[next++];
      const left = DOOR_BUDGET_MS - (Date.now() - started);
      const quiet = discordQuietMs();
      if (left <= 0) { got.set(id, { lookupFailed: 'ran out of time asking Discord' }); continue; }
      if (quiet >= left) { got.set(id, { lookupFailed: 'rate limited by Discord' }); continue; }
      if (quiet > 0) await new Promise((r) => setTimeout(r, quiet));
      let st;
      try { st = await Promise.race([standingCached(String(id)), late]); }
      catch (e) { st = { lookupFailed: String(e) }; }
      got.set(id, st || { lookupFailed: 'ran out of time asking Discord' });
    }
  }
  const lanes = [];
  for (let i = 0; i < Math.min(DOOR_LANES, ids.length); i++) lanes.push(lane());
  await Promise.all(lanes);
  clearTimeout(timer);
  return got;
}

/*
  How long a Submit waits on Discord before answering anyway (#467).

  who() asks Discord who a signed in visitor is before any route looks at what
  they sent, and discordGet gives Discord ten seconds a question, two
  questions when the guild list is refused. So with Discord slow or not
  answering, a signed in visitor pressing Send it on the report page watched
  the button for ten to twenty seconds, and a report about a person was then
  told to sign in, which they had.

  On the doors below, who() now waits this long and no longer. The question
  keeps going, one at a time per account (standAsking), and lands in
  standCache as before, so the next press has the answer. Until then the
  visitor counts as signed in with the lookup failed, which each door turns
  into words: a problem or an idea goes anyway, and anything that needs
  their roles says Discord could not be asked. A ban in the site's own file
  and the hand written admin list need no Discord, so they still count.
*/
const SUBMIT_WAIT_MS = 700;
/* Play's two doors, /api/play/join and /api/play/pass, answer inside
   PLAY_ANSWER_MS of the question, well inside the launcher's fifteen seconds
   (Discord.cs PostJson), with 503 "could not ask Discord" when Discord has
   not answered by then, which the launcher treats as a site that could not
   vouch (#1094). What the launcher sends is small and sent at once, so it
   gets PLAY_BODY_MS of that. */
const PLAY_ANSWER_MS = 10000;
const PLAY_BODY_MS = 5000;
const SUBMIT_DOORS = new Set(['/api/report', '/api/gallery/submit', '/api/gallery/report']);
// Shared for at most STAND_ASKING_MS: three questions of ten seconds is the
// longest a lookup should take, and one that never settles must not hold
// every later request for that account behind it.
const STAND_ASKING_MS = 35000;
const standAsking = new Map();
/* What an account counts as when Discord has not answered in time: the hand
   written admin list, which needs no Discord, and otherwise signed in with
   no roles and the lookup failed, which each door turns into words. */
function standingLate(id) {
  const listed = cfg.admins.indexOf(String(id)) >= 0;
  return { id: String(id), inGuild: listed, banned: false, admin: listed, play: listed, dev: listed,
           roles: [], name: '', lookupFailed: 'Discord did not answer in time' };
}
/* The 503 /api/play/join sends when Discord did not answer (#1094). Every
   other launcher door sends this same object (#1164). error is what the
   gallery launcher reads; message is what Play reads. */
function discordUnasked() {
  const message = 'Thornswood could not ask Discord about your account just now. Try again in a minute.';
  return { ok: false, why: 'could not ask Discord', message: message, error: message };
}
// p's answer, or late()'s once ms has passed without one.
function within(p, ms, late) {
  let timer = null;
  const LATE = {};
  const t = new Promise((r) => { timer = setTimeout(() => r(LATE), Math.max(0, ms)); });
  return Promise.race([p, t]).then((v) => { clearTimeout(timer); return v === LATE ? late() : v; });
}
function standingSoon(id, waitMs, staleOk) {
  let ask = standAsking.get(id);
  if (!ask || Date.now() - ask.at > STAND_ASKING_MS) {
    const mine = { p: standingCached(id), at: Date.now() };
    standAsking.set(id, mine);
    const done = () => { if (standAsking.get(id) === mine) standAsking.delete(id); };
    mine.p.then(done, done);
    ask = mine;
  }
  if (!(waitMs > 0)) return ask.p;
  // A page load uses the last answer Discord gave when this one is late or
  // failed, while the question above carries on and lands in the cache for
  // the next one (#1096).
  return within(ask.p, waitMs, () => standingLate(id)).then((st) => {
    const good = staleOk && st.lookupFailed && standGood.get(id);
    if (good && Date.now() - good.at < STAND_STALE_MS) return Object.assign({}, good.v, { stale: true });
    return st;
  });
}

/*
  PAGE LOADS WAIT NO LONGER THAN A SUBMIT (#1096). A GET or HEAD from a
  signed in visitor asked Discord in full before anything was sent back, so
  with Discord slow the gallery, the report page's sign in check and the hub
  took ten to twenty seconds to show. They get SUBMIT_WAIT_MS too, and then
  the last answer Discord gave for that account (up to STAND_STALE_MS old)
  or, with none, signed in with the lookup failed. Anything else waits at
  most PLAY_ANSWER_MS (#1164), the same deadline Play uses, and then counts
  as signed in with the lookup failed. One lookup can be three Discord
  questions, and the launcher gives up at fifteen seconds.
*/
async function who(req, waitMs, staleOk) {
  const me = identity(req);
  if (!me) return { member: isMember(req), admin: false, dev: false, name: '', id: '', play: false };
  const st = await standingSoon(me.id, waitMs, staleOk);
  return {
    // "member" is now "may use the hub", and only staff may. Being allowed
    // into the GAME is st.play, and that is asked separately by the launcher.
    // "dev" is staff (access.dev: Owner, Dev, Gamemaster, Moderator,
    // Loremaster), used by the gallery queue and reports. Not the Owner/Dev
    // admin pair alone.
    member: st.admin || isMember(req),
    admin: st.admin,
    dev: !!st.dev,
    play: st.play,
    banned: st.banned,
    inGuild: st.inGuild,
    lookupFailed: st.lookupFailed || '',
    id: me.id,
    name: st.name || me.name
  };
}

/*
  Why this visitor cannot report a person from the report page, or null when
  they can. /api/report answers with it, and /api/gallery/who hands it to the
  page, so the page says the same words before Send it as the site would
  after (#1097). Signed in already is never told to sign in (#467), and
  Discord not answering in time is said as that.
*/
function personReportRefusal(w) {
  if (!w.id) return { code: 401, why: 'sign in', error: 'Sign in with Discord to report somebody, ' +
    'so staff can come back to you about it.' };
  if (w.banned) return { code: 403, why: 'banned', error: 'That Discord account is banned from Thornswood.' };
  if (!w.play && w.lookupFailed) return { code: 503, why: 'could not ask Discord', error:
    'Thornswood could not ask Discord who you are just now, so a report about a person cannot go yet. ' +
    'Try again in a minute. A problem or an idea goes without it.' };
  if (!w.play) return { code: 403, why: 'role', error: 'Your Discord account is not let into Thornswood ' +
    'yet, so it cannot report somebody from here. Ask staff in the Discord instead.' };
  return null;
}

/* 'staff' is w.dev, which already folds admin in, so widening access.dev
   widens the pages marked staff with it. Anything with no level named is the
   hub member cookie, as it always was. */
const allowed = (key, w) =>
  LEVEL[key] === 'admin' ? !!w.admin
  : LEVEL[key] === 'staff' ? !!w.dev
  : !!w.member;

/*
  Staff at a gallery door, by either of the two things that can prove it (#743).

  The hub's twa cookie is one: who(req) reads it and w.dev is the access.dev
  roles. The launcher has no cookie to offer, because the Discord callback
  mints the cookie on the browser and hands the launcher a signed ticket
  instead, so every staff door answered a launcher 403 however senior the
  account behind it was.

  So a ticket in the query is the other, read and re-checked against Discord
  exactly the way /api/gallery/submit and /api/gallery/report read theirs, with
  one bar higher: st.dev rather than st.play, because these doors Accept
  and Delete rather than send something in.

  It answers { ok: true, from, discordId } or { ok: false, code, body }. With
  neither cookie nor ticket the refusal is the 403 'staff only' these doors
  have always sent, so nothing about the hub page changes.
*/
async function galleryStaff(url, w) {
  if (w.dev) return { ok: true, from: 'web', discordId: w.id || '' };
  // Signed in, and Discord did not answer in time (#1164): say that, rather
  // than 'staff only', which would tell a Gamemaster they are not staff.
  if (w.id && w.lookupFailed && !w.admin) return { ok: false, code: 503, body: discordUnasked() };
  const t = readTicket(url.searchParams.get('ticket'));
  if (!t) return { ok: false, code: 403, body: { error: 'staff only' } };
  const st = await within(standing(t.d), PLAY_ANSWER_MS, () => standingLate(t.d));
  standCache.delete(String(t.d));
  if (st.lookupFailed && !st.admin) return { ok: false, code: 503, body: discordUnasked() };
  // A bans.json hit returns before Discord is asked, with inGuild left false
  // (#1022). Banned has to be said first, or the door claims they are not in
  // the Discord.
  if (st.banned) return { ok: false, code: 403, body: { ok: false, why: 'banned', error:
    'That Discord account is banned from Thornswood.' } };
  if (!st.inGuild) return { ok: false, code: 403, body: { ok: false, why: 'guild', error:
    'That Discord account is not in the Thornswood Discord.' } };
  if (!st.dev) return { ok: false, code: 403, body: { ok: false, why: 'role', error:
    'That Discord account has no staff role, so it cannot work the gallery queue.' } };
  return { ok: true, from: 'launcher', discordId: String(t.d) };
}

// ----------------------------------------------------------------- plumb --
/* One CSP for every answer (#1474). home.html and the hub load CSS/JS as
   same-origin files, so script-src and style-src need only 'self'. Keep this
   string in one place so send(), Range replies, and the request-level
   setHeader cannot drift. */
const CSP_HEADER = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; font-src 'self'; connect-src 'self'; frame-ancestors 'self'; base-uri 'self'; form-action 'self'; object-src 'none'";
function send(res, code, payload, type, extra) {
  // Defense in depth (#1366 / #1474): conservative CSP (this page and the hub
  // load nothing from other sites; CSS and JS are external same-origin files),
  // frame-ancestors self so the hub cannot be iframed for clickjacking, and a
  // referrer policy that does not leak path on cross-origin navigations.
  res.writeHead(code, Object.assign({
    'Content-Type': type || 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': CSP_HEADER,
    'Referrer-Policy': 'strict-origin-when-cross-origin'
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
      'x-content-type-options': 'nosniff',
      'content-security-policy': CSP_HEADER,
      'referrer-policy': 'strict-origin-when-cross-origin'
    });
    res.end();
    return true;
  }
  end = Math.min(end, size - 1);
  // send() puts the security headers on every other answer; a range must not
  // be the one reply that quietly goes out without them.
  res.writeHead(206, Object.assign({}, headers, {
    'content-range': 'bytes ' + start + '-' + end + '/' + size,
    'content-length': (end - start) + 1,
    'accept-ranges': 'bytes',
    'cache-control': headers['cache-control'] || 'no-store',
    'x-content-type-options': 'nosniff',
    'content-security-policy': CSP_HEADER,
    'referrer-policy': 'strict-origin-when-cross-origin'
  }));
  if (head) { res.end(); return true; }
  fs.createReadStream(file, { start: start, end: end }).pipe(res);
  return true;
}

/*
  What was sent with a request, settled on every path (#1095).

  It resolved on 'end' and nothing else. Over the cap it destroyed the
  request, after which 'end' never came, and a connection that dropped or a
  sender that stopped halfway left it waiting too, so the route never went
  on and the visitor got a dropped connection instead of words.

  Now it rejects with a BodyFailed, which failed() below turns into an
  answer: 413 with the most the route takes when it is too big, 408 when it
  took longer than waitMs to arrive (by default ten seconds, plus a second
  for every 64 KB the route allows), and nothing when the connection has
  already gone, because nobody is left to read it. Over the cap the rest is
  read and thrown away rather than the socket cut, so the answer can reach
  the sender. The routes pass a BodyFailed on (passBodyFailure) rather than
  reading it as a body that was not JSON.
*/
class BodyFailed extends Error {
  constructor(status, why, words) { super(why); this.status = status; this.why = why; this.words = words; }
}
function passBodyFailure(e) { if (e instanceof BodyFailed) throw e; }
function body(req, cap, waitMs) {
  const max = cap || 4000000;
  const wait = waitMs > 0 ? waitMs : 10000 + Math.ceil(max / 65536) * 1000;
  return new Promise((resolve, reject) => {
    const parts = [];
    let size = 0, settled = false;
    const settle = (e, v) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (e) reject(e); else resolve(v);
    };
    const timer = setTimeout(() => settle(new BodyFailed(408, 'slow',
      'That took too long to arrive, so it was not read. Try again.')), wait);
    const gone = () => settle(new BodyFailed(0, 'closed', ''));
    req.on('data', (d) => {
      if (settled) return;
      size += d.length;
      if (size > max) {
        return settle(new BodyFailed(413, 'too big', 'That was too big to send here: the most this takes is ' +
          (max >= 1048576 ? Math.round(max / 1048576) + ' MB' : Math.max(1, Math.round(max / 1024)) + ' KB') + '.'));
      }
      parts.push(Buffer.isBuffer(d) ? d : Buffer.from(String(d)));
    });
    req.on('end', () => settle(null, Buffer.concat(parts).toString('utf8')));
    req.on('error', gone);
    req.on('aborted', gone);
    req.on('close', () => { if (!req.complete) gone(); });
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

/*
  A request that changes something comes from a page of this site, or from
  something that is not a browser at all (#1367).

  The sign in cookies are SameSite=Lax, and until this that attribute was all
  that stood between another site and every write here. Lax keeps the cookies
  off a POST, PUT or DELETE that another site starts, in a browser that knows
  the attribute. A browser too old to know it sends them, and every route
  reads its body as JSON whatever the Content-Type says, so a plain form with
  enctype="text/plain" on any page could send a signed in admin to
  /api/staff/pk with a body that parses. Lax also counts every name under
  thornswood.net as the same site, so a page on any other name under it would
  carry the cookies as well.

  So anything but GET (a HEAD is a GET by the time this is asked) is held to
  where it came from. A browser names the page that sent it in Origin on every
  such request, and an old one that leaves Origin off still sends Referer.
  Either naming another origin is refused, and Origin "null" is another origin
  (a sandboxed frame, a page that turned the referrer off). With neither, it
  is the launcher, a game server, the bot or the voice service: none of them
  holds a sign in cookie, and each proves itself another way (a ticket, the
  bot's key). A request with neither that does carry one of the sign in
  cookies is a browser with both taken off, and is refused too.

  This site's origin is the one the request was sent to, read the way the
  Discord callback builds its redirect address (origin above). A page on
  another site cannot make a browser send this site's Origin, so it cannot
  match.

  GET changes nothing here that a page elsewhere can choose: /auth/discord
  starts a sign in tied to this browser, its callback finishes only the
  attempt this browser began (ATTEMPT below), and /api/signins drops rows
  past their age. tests/test-1367-cross-site.js holds every write route to
  this.

  Answers '' when the request may go on, or which of the three it failed:
  'origin', 'referer', or 'neither' (a sign in cookie and no page named).
*/
function crossSite(req) {
  if (req.method === 'GET') return '';
  const own = origin(req).toLowerCase();
  const said = req.headers.origin;
  if (said !== undefined) {
    return String(said).toLowerCase() === own ? '' : 'origin';
  }
  const ref = req.headers.referer;
  if (ref !== undefined) {
    let from = '';
    try { from = new URL(String(ref)).origin.toLowerCase(); } catch (e) { from = ''; }
    return from === own ? '' : 'referer';
  }
  const c = cookies(req);
  return (c[COOKIE] || c[ADMIN]) ? 'neither' : '';
}

/*
  One Discord sign in attempt, tied to the browser that started it. Entry 248.

  The OAuth state was the same string for every attempt that asked for the
  same page: signed, and nothing else. Anybody holding one could hand it to
  somebody else's browser, or use it again, and the callback took it. Now
  every press of the button makes a random value that goes two ways, inside
  the signed state out through Discord and back, and into a short cookie in
  this browser only. The callback wants the two to match, once, inside ten
  minutes, and refuses before Discord is asked anything.

  The launcher's nonce is a different thing and rides alongside unchanged. It
  proves the ticket landed on the port of the button that was pressed; this
  proves the callback is finishing an attempt this browser began.

  Named per attempt, so two tabs signing in at once do not overwrite each
  other. The path keeps it off every other request. The launcher waits two
  minutes for its ticket (Discord.cs), so ten is room to spare.
*/
const ATTEMPT = 'twst_';
const ATTEMPT_MS = 10 * 60000;
const attemptsSpent = new Map();
const attemptCookie = (req, attempt, value, seconds) =>
  ATTEMPT + attempt.slice(0, 8) + '=' + value + '; Path=/auth/discord; Max-Age=' + seconds +
  '; HttpOnly; SameSite=Lax' + (secureHere(req) ? '; Secure' : '');

/* Which doors have been answered with the key in the address, so site.log
   says once, and without the key, that a game server still runs a gamemode
   from before the key moved into a header. When neither door has said it
   since both servers were redeployed, the address form can go. */
const keyInAddress = new Set();

// --------------------------------------------------------------- discord --
/* THE SIGN-IN CALLBACK'S TWO QUESTIONS (#1163). post exchanges the
   code and getWithToken reads who the person is. Both used to listen only
   for data, end and the request's error. Discord sending its headers and
   then stalling, never answering, or dropping halfway left the promise
   unsettled, so the browser sat on a blank page and the launcher waited
   out its two minutes. The same ten seconds as discordGet, and a response
   that fails, is cut off or closes before its end settles the question
   once. The callback turns that into words. */
function discordSilent() {
  const e = new Error('Discord did not answer');
  e.discordSilent = true;
  return e;
}
function readDiscordBody(res, h) {
  let out = '';
  res.on('data', (d) => out += d);
  res.on('error', h.giveUp);
  res.on('aborted', h.giveUp);
  // complete is false until a whole answer has arrived. A stub that is not
  // a real response leaves it unset, and that one is finished on end.
  res.on('close', () => { if (res.complete === false) h.giveUp(); });
  res.on('end', () => {
    if (res.complete === false) return h.giveUp();
    try { h.done(JSON.parse(out)); }
    catch (e) { h.fail(e); }
  });
}
function boundDiscord(open) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let timer = null;
    let req = null;
    const finish = (fn, v) => {
      if (settled) return;
      settled = true;
      if (timer) clearTimeout(timer);
      fn(v);
    };
    const giveUp = () => finish(reject, discordSilent());
    timer = setTimeout(() => {
      giveUp();
      try { if (req) req.destroy(); } catch (e) { }
    }, DISCORD_ASK_MS);
    req = open({
      giveUp: giveUp,
      done: (v) => finish(resolve, v),
      fail: (e) => finish(reject, e)
    });
    if (req && req.on) req.on('error', (e) => finish(reject, e));
  });
}
function post(url, form) {
  const u = new URL(url);
  const data = new URLSearchParams(form).toString();
  return boundDiscord((h) => {
    const r = https.request({
      hostname: u.hostname, path: u.pathname, method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded',
                 'Content-Length': Buffer.byteLength(data) }
    }, (res) => readDiscordBody(res, h));
    r.end(data);
    return r;
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
/* QUIET UNTIL. discordGet recognised a 429 and then asked again straight
   away, for the next person on the list, so one rate limit became a run of
   them. Discord says how long to wait: Retry-After or x-ratelimit-reset-after
   on the 429, and x-ratelimit-remaining 0 with x-ratelimit-reset-after on the
   last answer before one. That time is kept here, once for the whole site,
   and until it passes discordGet answers "rate limited" without asking. It
   is not a sleep: a sleep here would be paid once per linked account and
   blow the door's ten seconds (issue #415). Capped at a minute, so a strange
   header cannot shut the site out of Discord for longer than that. */
let discordQuietUntil = 0;
function discordQuietMs() { return Math.max(0, discordQuietUntil - Date.now()); }
function discordWaitMs(headers, text) {
  const h = headers || {};
  let s = parseFloat(h['retry-after']);
  if (!(s >= 0) && h['retry-after']) {
    // Retry-After may also be a date (RFC 9110); Discord sends seconds.
    const at = Date.parse(h['retry-after']);
    if (at) s = (at - Date.now()) / 1000;
  }
  if (!(s >= 0)) s = parseFloat(h['x-ratelimit-reset-after']);
  if (!(s >= 0)) { try { s = parseFloat(JSON.parse(text).retry_after); } catch (e) { } }
  if (!(s >= 0)) return -1;
  return Math.min(60000, Math.ceil(s * 1000));
}
/* TEN SECONDS FOR THE WHOLE ANSWER (#1094). The limit was req.setTimeout,
   which only watches for a quiet socket and then destroys the request. When
   Discord sent its headers and stalled, the response never ended, nothing
   listened for it failing, and the promise never settled, so the visitor or
   launcher waiting on it never heard back. Now one timer runs from the
   question to the last byte, and a response that fails, is cut off or closes
   before its end settles the question too, once. */
const DISCORD_ASK_MS = 10000;
function discordGet(path) {
  return new Promise((resolve) => {
    if (!cfg.discord.botToken) {
      return resolve({ ok: false, status: 0, body: null, why: 'no bot token set' });
    }
    if (discordQuietMs() > 0) {
      return resolve({ ok: false, status: 429, body: null, why: 'rate limited by Discord' });
    }
    let settled = false;
    let timer = null;
    const settle = (v) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (!v.ok && v.status === 0 && v.why) console.error('[thornswood] discord ' + path + ': ' + v.why);
      resolve(v);
    };
    const req = https.get({
      hostname: 'discord.com', path: '/api/v10' + path,
      headers: { Authorization: 'Bot ' + cfg.discord.botToken }
    }, (res) => {
      let out = '';
      const cut = () => settle({ ok: false, status: 0, body: null, why: 'Discord stopped partway through its answer' });
      res.on('data', (d) => out += d);
      res.on('error', cut);
      res.on('aborted', cut);
      res.on('close', () => { if (!res.complete) cut(); });
      res.on('end', () => {
        const hdr = res.headers || {};
        if (res.statusCode === 429 || String(hdr['x-ratelimit-remaining']) === '0') {
          const wait = discordWaitMs(res.statusCode === 429 ? hdr : { 'x-ratelimit-reset-after': hdr['x-ratelimit-reset-after'] }, out);
          // A 429 with no readable wait still backs off for a second.
          const ms = wait >= 0 ? wait : (res.statusCode === 429 ? 1000 : 0);
          discordQuietUntil = Math.max(discordQuietUntil, Date.now() + ms);
        }
        if (res.statusCode === 200) {
          try { return settle({ ok: true, status: 200, body: JSON.parse(out) }); }
          catch (e) { return settle({ ok: false, status: 200, body: null, why: 'unreadable answer' }); }
        }
        if (res.statusCode === 404) {
          return settle({ ok: false, status: 404, body: null, why: 'not found' });
        }
        let msg = 'Discord answered ' + res.statusCode;
        if (res.statusCode === 401) msg = 'the bot token is wrong or has been reset';
        else if (res.statusCode === 403) msg = 'the bot is in the server but not allowed to read members';
        else if (res.statusCode === 429) msg = 'rate limited by Discord';
        console.error('[thornswood] discord ' + path + ': ' + msg);
        settle({ ok: false, status: res.statusCode, body: null, why: msg });
      });
    });
    timer = setTimeout(() => {
      settle({ ok: false, status: 0, body: null, why: 'Discord did not answer inside ten seconds' });
      try { req.destroy(); } catch (e) { }
    }, DISCORD_ASK_MS);
    req.on('error', (e) => settle({ ok: false, status: 0, body: null, why: 'could not reach Discord: ' + e.message }));
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
  It is read on every standing() and a missing file means nobody is banned,
  which is what an empty server looks like.

  WRITTEN BY STAFF SINCE #412 (Patrick, 28 September: "put the bans and notes
  on the site"), from the game's /ban and from the hub. A ban now also carries
  until (unix ms, 0 or missing for good), byId, name and profiles, and one
  made in the game against a profile no Discord account holds is kept under
  "p:<profile>" instead of an id. An old row with no until is a ban for good,
  as it always was.

  ONE CHARACTER OR THE WHOLE ACCOUNT (#1010, Patrick, 28 September: "staff
  can ban either one character or a whole account"). The key says which: a
  Discord id is the account (every character on it, and any new one, because
  standing() reads it and /api/play/join and /api/play/pass refuse the
  account), and "p:<profile>" is that one character and nothing else. scope
  on the row says the same in words. The game's /ban is a character now and
  /banaccount the account; the hub offers both.
*/
const BANS = path.join(DATA, 'bans.json');
/*
  Characters staff have killed for good (#1010, PK). Keyed by profile id:
  {"<profile>": {"at", "by", "byId", "why", "name", "account", "from"}}.
  Patrick, 28 September: the character "can never be played or selected
  again, but it is kept, not deleted, so staff can run events with PKed
  characters", it is quiet, and the account can make a new character. So
  nothing here or in the game server deletes anything: the join pass refuses
  the character, the door's lists leave it out, the launcher's menu shows it
  as dead in no slot, and staff read the row.

  UNDONE BY AN ADMIN (Patrick, 29 September: a PK made by mistake can be
  undone, by the admin role only, from the hub and with the game's /unpk,
  with a reason). The row is never deleted: undoing it adds "undone" {"at",
  "by", "byId", "why", "from"}, and a row with "undone" is not a PK any more
  (pkActive). A later PK of the same character moves the old row into
  "history" first, so every PK and every undo stays readable. The character
  comes back only into a free slot: undoPk refuses while every slot on the
  account holds a living character, and says so.
*/
const PK = path.join(DATA, 'pk.json');
// Staff notes against a person, keyed the same way as bans. Staff read them.
const NOTES = path.join(DATA, 'notes.json');
// What staff did on the hub, one JSON line each, for the bot's staff channel.
// The game servers write their own (private\moderation.log).
const MODLOG = path.join(FOR_BOT, 'moderation.log');
const NOTES_KEEP = 200;
const BAN_MOST_MIN = 10 * 365 * 24 * 60;

/* Whose Discord account holds this profile, from linked.json, or ''. */
function accountOf(pid) {
  const n = Number(pid) || 0;
  if (!(n > 0)) return '';
  const linked = jsonFile(LINKED, {});
  for (const d of Object.keys(linked)) {
    const ps = Array.isArray((linked[d] || {}).profiles) ? linked[d].profiles : [];
    if (ps.map(Number).indexOf(n) >= 0) return String(d);
  }
  return '';
}
/* Where a note about this profile is kept: the account, or the profile. */
function recordKey(pid) { return accountOf(pid) || ('p:' + (Number(pid) || 0)); }
function banActive(b, now) {
  return !!b && typeof b === 'object' && (!(Number(b.until) > 0) || Number(b.until) > now);
}
/*
  Why this one character may not be played, or null (#1010): killed for good
  by staff (pk), or under a ban on the character itself. A ban on the whole
  account is standing()'s, asked before this. Read from the files every time,
  so a ban that runs out lets the character back at once.
*/
function characterBar(pid, now) {
  const n = Number(pid) || 0;
  if (!(n > 0)) return null;
  const pk = jsonFile(PK, {});
  if (pk && pkActive(pk[String(n)])) {
    return { pk: true, at: Number((pk[String(n)] || {}).at) || 0 };
  }
  const byChar = jsonFile(BANS, {});
  const b = byChar && byChar['p:' + n];
  if (banActive(b, now)) return { pk: false, why: String(b.why || ''), until: Number(b.until) || 0 };
  return null;
}
/* Whether a pk.json row is a PK that holds: there, and not undone by an admin. */
function pkActive(row) {
  return !!row && typeof row === 'object' && !row.undone;
}
/* Every profile staff have killed for good, as numbers. */
function pkProfiles() {
  const table = jsonFile(PK, {}) || {};
  return Object.keys(table).filter((k) => pkActive(table[k])).map(Number).filter((n) => n > 0);
}
/* A ban's end in words, for the people told about it. */
function banUntilText(until) {
  return Number(until) > 0
    ? 'until ' + new Date(Number(until)).toISOString().slice(0, 16).replace('T', ' ') + ' UTC'
    : 'for good';
}
/* What a banned account is told at Play: until when and why for a staff ban
   (the file), the plain sentence for the Banned role. */
function accountBanned(st) {
  return 'That Discord account is banned from Thornswood' +
    (st && st.byFile ? ' ' + banUntilText(st.until) + (st.reason ? ': ' + st.reason : '') : '') + '.';
}
/* Every profile an active ban covers, with why and until, for the door. */
function activeBans(now) {
  const table = jsonFile(BANS, {});
  const linked = jsonFile(LINKED, {});
  const out = [];
  for (const k of Object.keys(table || {})) {
    const b = table[k];
    if (!banActive(b, now)) continue;
    const set = new Set((Array.isArray(b.profiles) ? b.profiles : []).map(Number).filter((n) => n > 0));
    if (k.indexOf('p:') === 0) set.add(Number(k.slice(2)));
    else for (const n of ((linked[k] || {}).profiles || [])) if (Number(n) > 0) set.add(Number(n));
    set.delete(0);
    // scope tells the game server what to say to them: one character, or the
    // whole account (#1010).
    if (set.size) out.push({ profiles: Array.from(set), why: String(b.why || ''), until: Number(b.until) || 0,
                             scope: k.indexOf('p:') === 0 ? 'character' : 'account' });
  }
  return out;
}
/* A ban, made or replaced. The account's standing is asked again at once. */
function putBan(key, row) {
  const table = jsonFile(BANS, {});
  const had = table[key] || {};
  const profiles = new Set([].concat(had.profiles || [], row.profiles || []).map(Number).filter((n) => n > 0));
  table[key] = Object.assign({}, row, { profiles: Array.from(profiles) });
  const ok = putJson(BANS, table);
  standCache.delete(key);
  return ok;
}
function dropBan(keys) {
  const table = jsonFile(BANS, {});
  let was = false;
  for (const k of keys) {
    if (k && Object.prototype.hasOwnProperty.call(table, k)) { delete table[k]; was = true; standCache.delete(k); }
  }
  return { was, ok: !was || putJson(BANS, table) };
}
function putNote(key, row) {
  const notes = jsonFile(NOTES, {});
  const list = Array.isArray(notes[key]) ? notes[key] : [];
  list.unshift(row);
  notes[key] = list.slice(0, NOTES_KEEP);
  return putJson(NOTES, notes);
}
function modLog(row) {
  try { fs.appendFileSync(MODLOG, JSON.stringify(Object.assign({ at: new Date().toISOString(), server: 'site' }, row)) + '\n'); }
  catch (e) { console.log('[thornswood-docs] could not write moderation.log: ' + e.message); }
}
/* A PK, kept for good. A row an admin undid goes into the new row's history. */
function putPk(pid, row) {
  const table = jsonFile(PK, {});
  const had = table[String(Number(pid))];
  if (had && typeof had === 'object') {
    const old = Object.assign({}, had);
    delete old.history;
    row = Object.assign({}, row, { history: (Array.isArray(had.history) ? had.history : []).concat([old]) });
  }
  table[String(Number(pid))] = row;
  return putJson(PK, table);
}
/*
  How many character slots a Discord account has, for bringing a character
  back (#1010): its standing's, or, when Discord cannot be asked, the roles
  linked.json kept from its last Play.
*/
async function slotsOfAccount(account) {
  let st = null;
  try { st = await standingCached(String(account)); } catch (e) { st = null; }
  if (st && !st.lookupFailed) return slotsFor(st);
  const roles = (jsonFile(LINKED, {})[String(account)] || {}).roles;
  const list = Array.isArray(roles) ? roles : [];
  const has = (names) => (names || []).some((n) => list.indexOf(n) >= 0);
  return slotsFor({ roles: list, admin: has(cfg.access.admin), dev: has(cfg.access.dev) });
}
/*
  An admin undoes a PK made by mistake (#1010, Patrick, 29 September). The
  row stays, with "undone" saying who, when and why. The character comes
  back into a free slot: every other character on the account the game
  server has a character for, that is not dead for good, holds one, and when
  they fill the account's slots nothing changes and the answer says so.
  Answers { status, body } for the route to send.
*/
async function undoPk(pid, by, byId, why, from) {
  const table = jsonFile(PK, {});
  const row = table[String(pid)];
  if (!pkActive(row)) return { status: 200, body: { ok: true, was: false } };
  const account = String(row.account || accountOf(pid) || '');
  const name = String(row.name || '') || ('profile ' + pid);
  if (account) {
    const slots = await slotsOfAccount(account);
    const who = (jsonFile(ROSTER, { who: {} }) || {}).who || {};
    const held = ((jsonFile(LINKED, {})[account] || {}).profiles || []).map(Number)
      .filter((n, i, a) => n > 0 && n !== Number(pid) && a.indexOf(n) === i && who[String(n)] && !pkActive(table[String(n)]));
    if (held.length >= slots) {
      return { status: 409, body: { ok: false, error: 'every slot is taken', slots, held: held.length,
        message: 'Every character slot on that account is taken (' + held.length + ' of ' + slots + '), so ' +
                 name + ' is still dead for good and nothing changed. Its owner can forget a character in ' +
                 'the launcher to free a slot, then undo the PK again.' } };
    }
  }
  // Read again after the wait above, so a write in between is not lost.
  const now = jsonFile(PK, {});
  const cur = now[String(pid)];
  if (!pkActive(cur)) return { status: 200, body: { ok: true, was: false } };
  cur.undone = { at: Date.now(), by, byId, why, from };
  if (!putJson(PK, now)) return { status: 500, body: { error: 'could not save' } };
  return { status: 200, body: { ok: true, was: true, name: String(cur.name || ''), account } };
}
/*
  The dead character the game's /unpk names (#1010): o.profileId, exact; or
  o.personProfileId, somebody in the world, whose account's one dead
  character it is; or o.words, the start of a dead character's name, or of
  the name of the account that holds it. Answers { pid, rest } or
  { message } saying who it could not tell apart.
*/
function findDead(o) {
  const table = jsonFile(PK, {}) || {};
  const dead = Object.keys(table).filter((k) => pkActive(table[k])).map(Number).filter((n) => n > 0);
  const linked = jsonFile(LINKED, {});
  const nameOf = (n) => String((table[String(n)] || {}).name || '') || ('profile ' + n);
  const listed = (ps) => ps.map((n) => nameOf(n) + ' (profile ' + n + ')').join(', ');
  const ofAccount = (acc, label) => {
    const ps = dead.filter((n) => String((table[String(n)] || {}).account || accountOf(n)) === String(acc));
    if (ps.length === 1) return { pid: ps[0] };
    if (!ps.length) return { message: label + ' has no character that is dead for good.' };
    return { message: label + ' has ' + ps.length + ' characters dead for good: ' + listed(ps) +
                      '. Name the character, or its profile number.' };
  };
  const words = (Array.isArray(o.words) ? o.words : []).map((w) => String(w || '').trim()).filter(Boolean).slice(0, 40);
  const pid = Number(o.profileId) || 0;
  if (pid > 0) {
    if (pkActive(table[String(pid)])) return { pid, rest: words };
    const acc = accountOf(pid);
    if (!acc) return { message: 'Profile ' + pid + ' is not dead for good.' };
    const r = ofAccount(acc, 'Profile ' + pid + '\'s account');
    return r.pid ? { pid: r.pid, rest: words } : r;
  }
  const person = Number(o.personProfileId) || 0;
  if (person > 0) {
    if (pkActive(table[String(person)])) return { pid: person, rest: words };
    const acc = accountOf(person);
    if (!acc) return { message: 'Nobody\'s account holds profile ' + person + '.' };
    const r = ofAccount(acc, String(o.personName || '').slice(0, 60) || ('Profile ' + person));
    return r.pid ? { pid: r.pid, rest: words } : r;
  }
  for (let n = words.length; n >= 1; n--) {
    const want = words.slice(0, n).join(' ').toLowerCase();
    const exact = dead.filter((k) => nameOf(k).toLowerCase() === want);
    const hits = exact.length ? exact : dead.filter((k) => nameOf(k).toLowerCase().indexOf(want) === 0);
    if (hits.length === 1) return { pid: hits[0], rest: words.slice(n) };
    if (hits.length > 1) {
      return { message: 'More than one character dead for good starts with "' + words.slice(0, n).join(' ') +
                        '": ' + listed(hits) + '. Name one, or its profile number.' };
    }
    const accs = Object.keys(linked).filter((d) => {
      const u = linked[d] || {};
      return [u.name, u.handle].some((s) => s && String(s).toLowerCase().indexOf(want) === 0);
    });
    if (accs.length === 1) {
      const r = ofAccount(accs[0], String(linked[accs[0]].name || linked[accs[0]].handle || 'That account'));
      return r.pid ? { pid: r.pid, rest: words.slice(n) } : r;
    }
  }
  return { message: 'No character dead for good goes by that name. Use its name, its owner\'s name or its profile number.' };
}
/*
  Every ban (with whether it still holds), every note and every PK, for staff,
  and the character names the game server's roster has for every linked
  profile, so the Linked accounts page can say which character is which.
*/
function staffRecords(now) {
  const table = jsonFile(BANS, {});
  const out = {};
  for (const k of Object.keys(table || {})) {
    out[k] = Object.assign({}, table[k] || {}, { active: banActive(table[k] || {}, now) });
  }
  const roster = (jsonFile(ROSTER, { who: {} }) || {}).who || {};
  const names = {};
  const linked = jsonFile(LINKED, {});
  for (const d of Object.keys(linked || {})) {
    for (const n of ((linked[d] || {}).profiles || [])) {
      const r = roster[String(Number(n))];
      if (r && r.name) names[String(Number(n))] = String(r.name);
    }
  }
  return { bans: out, notes: jsonFile(NOTES, {}), pk: jsonFile(PK, {}), names };
}
/* Minutes as a ban length: 0 is for good, anything else is capped. */
function banMinutes(v) {
  const n = Math.floor(Number(v) || 0);
  return n > 0 ? Math.min(n, BAN_MOST_MIN) : 0;
}
// The game server's character roster, pushed here by the gamemode with the
// door key (POST /api/roster) and handed back per person (POST /api/play/roster).
// Keyed by profile id; live and dev both push into it, their ids never meet.
const ROSTER = path.join(DATA, 'roster.json');
// How old a server's report of which characters it holds may be and still be
// passed on (#955). It is sent every five minutes; an hour covers a restart.
const ROSTER_HELD_FRESH_MS = 60 * 60 * 1000;

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
      ip: requestAddr(req)
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

  CHAT is kept elsewhere: the voice service writes one JSON line per message
  under its chat folder and ages whole days past THORNSWOOD_CHAT_DAYS
  (default 365). This block is only the launcher session logs. A session
  marked kept never loses its logs to the age prune; its chat lines still
  live in the voice folder and age with that window unless copied first.

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
   way into a folder nobody meant to write.

   In the order a set too big for SLOG_ALL keeps them. crash.log is the SKSE
   crash log from that session, if it crashed, and it goes second because it
   is the one that settles a crash with no message (entry 105).
   skyrim-platform.log is the tail of Skyrim Platform's own log, and it goes
   last because it is the biggest and the noisiest. */
const SLOG_NAMES = [
  'launcher.log', 'crash.log', 'thornswood-front.log', 'thornswood-voice.log',
  'thornswood-emotes.log', 'thornswood-input.log', 'thornswood-dress.log',
  'thornswood-loadorder.txt', 'thornswood-plugins-light.txt',
  'skyrim-platform.log'
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

/* The load order lines are the game's own check, as it writes them to Skyrim
   Platform's log (loadOrderVerificationService in the client), not the words
   LOAD ORDER ERROR. Those words are only ever painted on the game's screen,
   never logged by the game; the one log that carries them is the launcher's,
   inside its own Scan sentences ("The game shows that as LOAD ORDER ERROR"),
   which say what WOULD happen and stop Play until Fix. Matching them labelled
   42 of the 53 sessions from 25 to 28 Sep "refused over the load order" when
   the game's check had passed in every one it could be read for (#945). */
const TROUBLE_WARN = [
  ['Update failed',                 'an update did not install'],
  ['being used by another process', 'an update could not write a file something else had open'],
  ['Load order check failed',       'the game showed LOAD ORDER ERROR: its plugins are not the server\'s'],
  ['Missing some server mods',      'the game showed LOAD ORDER ERROR: it has fewer plugins than the server'],
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

/*
  ONLY THIS SESSION'S PART OF launcher.log (#945).

  The launcher sends the last 256 KB of its own log, which is days of it:
  every Scan, Fix, update and game it has run. The game's logs start afresh
  each run, so they are this session's; launcher.log is not. Read whole, a
  line from two days earlier coloured every session after it. Measured on
  28 Sep: all 42 sessions labelled "refused over the load order" since 25 Sep
  took the label from a Scan line written half an hour to 65 hours BEFORE the
  session started, which Fix had since put right, and the Scan just before
  each Play said 0 issues. An "Update failed" from 19 Sep did the same.

  So launcher.log is read from the last "Starting the game on launcher" line,
  which Shell writes as it starts the game for this session, to its end. A
  log with no such line has nothing that can be placed in this session, and
  none of it is read.
*/
const SESSION_START_MARK = 'Starting the game on launcher ';

function thisSessionOf(name, text) {
  const s = String(text || '');
  if (name !== 'launcher.log') return s;
  const at = s.lastIndexOf(SESSION_START_MARK);
  if (at < 0) return '';
  return s.slice(s.lastIndexOf('\n', at) + 1);
}

/*
  What the game server said about this person's load order in this session,
  from its own log (the load order refusal block in gamemode.js, #402 and
  #873). serverLines is the server log sliced to the session; the profile is
  the character's, which the lines name. A refusal outranks anything the
  client logs say about the load order, because it is the one that ended the
  session.
*/
function serverRefusal(serverLines, profile) {
  const p = Number(profile) || 0;
  if (!p || !Array.isArray(serverLines)) return null;
  const refused = 'refusing profile ' + p + ':';
  const would = 'WOULD REFUSE profile ' + p + ':';
  let watched = null;
  for (const raw of serverLines) {
    const line = String(raw);
    if (line.indexOf(refused) >= 0) {
      return {
        level: 'warn', file: 'server', line: line.trim().slice(0, 300),
        why: line.indexOf('no load order report') >= 0
          ? 'the server ended the session: their game never said which plugins it loaded'
          : 'the server ended the session: their load order is not the server\'s'
      };
    }
    if (!watched && line.indexOf(would) >= 0) {
      watched = {
        level: 'warn', file: 'server', line: line.trim().slice(0, 300),
        why: 'the server found their load order is not its own and let them stay'
      };
    }
  }
  return watched;
}

/* Red before yellow: a session that crashed AND complained about its load
   order is a crash, and the crash is the thing worth waking somebody for.
   Then the server's word on the load order, then the rest. */
function readTrouble(logs, serverLines, profile) {
  const mine = {};
  for (const name of Object.keys(logs || {})) mine[name] = thisSessionOf(name, logs[name]);
  return scanFor(mine, TROUBLE_BAD, 'bad') ||
         serverRefusal(serverLines, profile) ||
         scanFor(mine, TROUBLE_WARN, 'warn');
}

/*
  Sets the row's trouble from what readTrouble found, or from the launcher's
  own issues when the logs said nothing, and clears it when neither says
  anything. Returns true when the row changed.
*/
function applyTrouble(row, found) {
  const before = [row.trouble, row.troubleAt, row.troubleFile, row.troubleLine].join('\u0001');
  delete row.trouble; delete row.troubleAt; delete row.troubleFile; delete row.troubleLine;
  if (found) {
    row.trouble = found.why;
    row.troubleAt = found.level;     /* 'bad' is red, 'warn' is yellow */
    row.troubleFile = found.file;
    row.troubleLine = found.line;
  } else {
    const issues = Array.isArray(row.issues) ? row.issues : [];
    const checks = Array.isArray(row.checks) ? row.checks : [];
    if (issues.length || checks.length) {
      /* No crash, but the launcher was unhappy. Yellow, and never a message
         in Discord: these are common, understood, and have a known fix. */
      const blocking = issues.filter(i => i && i.blocking).length;
      row.trouble = blocking
        ? (blocking + ' thing(s) would have stopped them connecting')
        : (issues.length + checks.length) + ' thing(s) the launcher was unhappy about';
      row.troubleAt = 'warn';
    }
  }
  return [row.trouble, row.troubleAt, row.troubleFile, row.troubleLine].join('\u0001') !== before;
}

/*
  Every row read again once under the rules above, because the rows written
  before #945 keep the label the whole launcher.log gave them, and the
  sessions page counts those. Only the stored client logs are read, not the
  server log (a session's server lines may have rolled away by now, and the
  old rule never read them either). TROUBLE_RULES moves when the rules do, so
  the next change reads them again too; a row already read under these rules
  is left alone. Nothing is said in Discord: these are old sessions.
*/
const TROUBLE_RULES = 2;
function rereadTrouble() {
  try {
    const rows = sessionRows();
    let changed = 0, read = 0;
    for (const row of rows) {
      if (!row || row.troubleRules === TROUBLE_RULES) continue;
      const key = sessionKey(row.session);
      if (!key) continue;
      let logs = null;
      try {
        const f = slogFile(key);
        if (fs.existsSync(f)) logs = (JSON.parse(fs.readFileSync(f, 'utf8')) || {}).logs || null;
      } catch (e) { logs = null; }
      row.troubleRules = TROUBLE_RULES;
      if (!logs) continue;
      read++;
      if (applyTrouble(row, readTrouble(logs))) changed++;
    }
    if (read || changed) putSessions(rows);
    console.log('[thornswood-docs] read ' + read + ' stored session log sets again under the current trouble rules; ' +
                changed + ' session(s) changed colour or reason');
  } catch (e) {
    console.log('[thornswood-docs] could not read the stored session logs again: ' + (e && e.message || e));
  }
}

/*
  The short list of sessions that went wrong, for the bot to read.

  A file rather than an endpoint, because the bot runs on this same box and a
  file needs no ticket, no port and nothing to keep in step. Newest last, the
  last 200, so it cannot grow without bound.
*/
const TROUBLE_FILE = path.join(FOR_BOT, 'trouble.json');
const TROUBLE_KEEP = 200;

function noteTrouble(row, found) {
  try {
    const list = jsonFile(TROUBLE_FILE, []);
    const all = Array.isArray(list) ? list : [];
    if (all.some(t => t && t.session === row.session)) return;
    /* start and end are the session's own window, in the same unix ms the
       row was stamped with. at is when the logs arrived. They are kept apart
       because a backlog uploaded by a newer launcher lands long after the
       session ended: a 401 held Patrick's 23 September logs until 14:09 the
       next day, and the alert read as a fresh crash. With the session's start
       named and the arrival called out when it is later than the end, a late
       upload no longer looks like a new failure (issue #532). */
    all.push({
      session: row.session,
      who: String(row.who),
      name: String(row.name || ''),
      channel: String(row.channel || ''),
      profile: Number(row.profile) || 0,
      version: String(row.version || ''),
      start: Number(row.start) || 0,
      end: Number(row.end) || 0,
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

  ROLLED LOGS ARE READ TOO, entry 220. roll-log.ps1 runs in front of the game
  server on every start, and a server.log of 4 MB or more becomes server.log.1
  (an install rolls it whatever the size). Reading server.log alone, a restart
  after a crash would leave every session before it with no server lines at
  all, the crash session included, which is the one this page is opened for.
  So when server.log is shorter than the window, the rest of the window is
  taken off the end of server.log.1, then .2, and so on, oldest text first,
  and the read is never more than the 4 MB it always was.
*/
const SERVER_LOGS = {
  main: 'C:\\Thornswood-Server\\server.log',
  dev:  'C:\\Thornswood-Server-Dev\\server.log'
};

// ==== thornswood deploy records ====
/* What each part on this box runs, for /api/deploys (#459). Every deploy
   (scripts\deploy\Artifact.ps1) leaves one record per folder a part runs
   from in DEPLOYS_DIR: which zip, which commit, whether it carried edits,
   when. Only those fields go out; where it runs and which machine sent it
   stay on the box. A record that will not read is named and skipped, so one
   bad file does not hide the rest. Deploy-Docs grants the site's account
   read on this folder. The door is staff only since #1359. */
const DEPLOYS_DIR = process.env.THORNSWOOD_DEPLOYS_DIR || 'C:\\Thornswood-Deploys\\current';
function readDeploys(dir) {
  const parts = {};
  let names = [];
  try { names = fs.readdirSync(dir); } catch (e) { return parts; }
  for (const n of names.sort()) {
    if (!/^[a-z0-9][a-z0-9._-]*\.json$/.test(n)) continue;
    const part = n.slice(0, -5);
    try {
      const r = JSON.parse(fs.readFileSync(path.join(dir, n), 'utf8').replace(/^\uFEFF/, ''));
      parts[part] = {
        component: String(r.component || ''),
        name: String(r.name || ''),
        commit: String(r.commit || ''),
        edited: r.edited === true,
        sha256: String(r.sha256 || ''),
        deployedUtc: String(r.deployedUtc || '')
      };
    } catch (e) {
      parts[part] = { unreadable: true };
    }
  }
  return parts;
}
// ==== end thornswood deploy records ====

/* Where the voice service writes what people said. Its folder, not this one:
   it owns the file and this only reads it, so there is one writer and no
   question about which copy is the real one.

   dev and main are different voice services with different folders, the same
   way they are different game servers with different logs, and the session
   says which it was on. This used to be one folder, the live one, for every
   session. So a dev session showed nothing, or worse, showed what the same
   profile number said on the live server in that window, which is somebody
   else's words in a report about behaviour.

   The dev folder is where the dev service actually writes. voice-server.js
   puts chat in its own folder unless THORNSWOOD_CHAT_DIR is set. Neither
   Install-Voice.ps1 nor vps-dev-instance.ps1 sets it, and the dev service's
   folder is C:\Thornswood-Voice-Dev (voice\README.md, vps-dev-instance.ps1).
   Measured 23 September: Get-Logs -Dev read that folder's voice.log and it
   says "listening on 127.0.0.1:7789", which is the dev port.
   tools\test-session-chat.js checks both defaults against those scripts. */
const CHAT_DIRS = {
  main: process.env.THORNSWOOD_CHAT_DIR || 'C:\\Thornswood-Voice\\chat',
  dev:  process.env.THORNSWOOD_DEV_CHAT_DIR || 'C:\\Thornswood-Voice-Dev\\chat'
};

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
   must not cost the rest.

   channel picks the voice service by the same rule serverLogSlice picks the
   game server's log, so the chat and the server log under one session always
   come from the same server. */
function chatSlice(profileId, from, to, channel) {
  const want = Number(profileId) || 0;
  if (!want) return { ok: true, why: '', lines: [] };
  const dev = channel === 'dev';
  const dir = CHAT_DIRS[dev ? 'dev' : 'main'];
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
    try { raw = fs.readFileSync(path.join(dir, day + '.jsonl'), 'utf8'); }
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
  return { ok: true, why: read ? '' : 'no chat log for those days on this box' +
           (dev ? ' from the dev voice service' : ''), lines: out };
}

function serverLogSlice(channel, from, to) {
  const file = SERVER_LOGS[channel === 'dev' ? 'dev' : 'main'];
  /* Only the tail is read, 4 MB across the live file and the rolled ones
     behind it. These grow, and a session is minutes long. Five rolled ones is
     what roll-log.ps1 keeps. */
  const keep = 5;
  let left = 4 * 1024 * 1024;
  const parts = [];
  let found = 0;
  try {
    for (let g = 0; g <= keep && left > 0; g++) {
      const f = g === 0 ? file : file + '.' + g;
      if (!fs.existsSync(f)) {
        /* server.log itself can be missing for a moment, between the roll and
           the server opening a new one, with last night's run in .1. A
           missing rolled one means there are none older. */
        if (g === 0) continue;
        break;
      }
      found++;
      const size = fs.statSync(f).size;
      const fd = fs.openSync(f, 'r');
      try {
        const start = Math.max(0, size - left);
        const buf = Buffer.alloc(Math.min(size, left));
        fs.readSync(fd, buf, 0, buf.length, start);
        let text = buf.toString('utf8');
        if (start > 0) text = text.slice(text.indexOf('\n') + 1);
        /* A run killed mid-line leaves no newline at the end of its file, and
           the next file's first line must not be glued onto it. */
        if (text.length && !text.endsWith('\n')) text += '\n';
        parts.unshift(text);
        left -= buf.length;
      } finally { fs.closeSync(fd); }
    }
  } catch (e) { return { ok: false, why: String(e.message || e), lines: [] }; }
  if (!found) return { ok: false, why: 'no server log on this box', lines: [] };
  const text = parts.join('');

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
                admin: false, play: false, dev: false, roles: [], name: '', avatar: '' };

  /*
    THE FILE FIRST, AND BEFORE EVERY OTHER BRANCH.

    A ban read off a role only works when the bot is in the guild, the guild
    lookup succeeds and somebody spelled the role right. The branch below for
    "no bot configured yet" hands play to everybody, which is correct for an
    ordinary member and wrong for somebody who has been thrown out.

    So the list is read here, where nothing can route around it, and it wins.
  */
  // A ban with an end (#412) stops counting once it has passed.
  const bans = jsonFile(BANS, {});
  if (bans && Object.prototype.hasOwnProperty.call(bans, String(discordId)) &&
      !(Number((bans[String(discordId)] || {}).until) > 0 &&
        Number((bans[String(discordId)] || {}).until) <= Date.now())) {
    out.banned = true;
    out.reason = String((bans[String(discordId)] || {}).why || '');
    out.until = Number((bans[String(discordId)] || {}).until) || 0;
    out.byFile = true;
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
        if (me.user && me.user.avatar) out.avatar = String(me.user.avatar);
        const names = await roleNames();
        out.roles = (me.roles || []).map((id) => names[id]).filter(Boolean);
        out.staffRole = holdsStaffRole(out.roles);
        out.businessOwner = holdsNamedRole(out.roles, 'Business Owner');
        out.factionOwner = holdsNamedRole(out.roles, 'Faction Owner');
        out.devRole = holdsNamedRole(out.roles, 'Dev');
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
  if (m.user && m.user.avatar) out.avatar = String(m.user.avatar);
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
  out.jarl = out.admin || has(cfg.access.jarl);
  out.company = has(cfg.access.company);
  out.staffRole = holdsStaffRole(out.roles);
  out.businessOwner = holdsNamedRole(out.roles, 'Business Owner');
  out.factionOwner = holdsNamedRole(out.roles, 'Faction Owner');
  out.devRole = holdsNamedRole(out.roles, 'Dev');
  return out;
}

/*
  Whether these Discord roles include a staff role (#481): access.admin or
  access.dev, by name. For the staff seats over the most the world holds,
  which Patrick keeps for "the discord roles" (29 Sep), so it reads the roles
  alone. st.dev is not the same thing: the hand written admins list sets it
  for an account that holds no role at all.
*/
function holdsStaffRole(roles) {
  const mine = Array.isArray(roles) ? roles : [];
  const staff = [].concat(cfg.access.admin || [], cfg.access.dev || []);
  return staff.some((n) => mine.indexOf(n) >= 0);
}

function holdsNamedRole(roles, name) {
  const mine = Array.isArray(roles) ? roles : [];
  return mine.indexOf(name) >= 0;
}

/*
  Has this account left the Thornswood Discord, so that nothing it holds in
  linked.json is anybody's any more?

  Added reviewing To Do List entry 142 on 24 September. /api/play/join stopped
  writing a profile id against a second account once a first one holds it,
  because that is how somebody took an id they learned off the voice service.
  It also stopped a person who moved to a new Discord account from ever having
  the characters their install made under the old one filed under the new, and
  a reviewer measured what that cost: voice refused the new account on all of
  them, and once the old account left the Discord /api/allowed dropped them and
  the game's door turned that person away from every character made before the
  switch, with a hand edit of linked.json on the VPS the only way back. On main
  before this, the new account simply took them at its first Play.

  An account that has left cannot play anything, so there is nobody left to
  keep those ids for, and /api/play/join moves them to whoever checks in with
  one next. Left means all of these, and anything short of them is the safe
  side, still holding:
    - Discord says the account is not in the server: a 404, which is the only
      failure standing() takes as certain. A lookup that failed is not left.
    - It is not banned in bans.json, which standing() reads before anything.
    - It is not on Discord's own ban list. A ban from inside Discord takes
      somebody out of the server as well, so it reads as a 404 here, and must
      not hand their characters to the second account they come back on. The
      ban list needs the bot to be allowed to ban members; when it cannot be
      read the account counts as still holding its ids.
  An account still in the Discord keeps its ids with or without the play role,
  because taking a role away is not leaving.
*/
async function hasLeft(discordId) {
  let st;
  try { st = await standingCached(String(discordId)); } catch (e) { return false; }
  if (!st || st.inGuild || st.banned || st.lookupFailed) return false;
  if (!cfg.discord.botToken || !cfg.discord.guildId) return false;
  const ban = await discordGet('/guilds/' + cfg.discord.guildId + '/bans/' +
                               encodeURIComponent(String(discordId)));
  return !!ban && !ban.ok && ban.status === 404;
}

/*
  The accounts other than the caller's that hold this profile id and have
  left the Discord (hasLeft above), as a set of Discord ids. Empty when the
  caller holds it already, so checking in with your own id never asks Discord
  about anybody else.

  Handed the table rather than reading it, and the join route reads the file
  again after this for the copy it writes back, because asking Discord waits
  and a wait between reading linked.json and writing it would write over
  whatever another launcher checked in meanwhile.
*/
async function departed(linked, pid, caller, by) {
  const out = new Set();
  const table = linked || {};
  const n = Number(pid) || 0;
  if (n <= 0) return out;
  const own = (table[caller] && Array.isArray(table[caller].profiles))
    ? table[caller].profiles.map(Number) : [];
  if (own.indexOf(n) >= 0) return out;
  for (const d of Object.keys(table)) {
    if (String(d) === String(caller)) continue;
    const theirs = (table[d] && Array.isArray(table[d].profiles))
      ? table[d].profiles.map(Number) : [];
    if (theirs.indexOf(n) < 0) continue;
    // Past the deadline (by, when the door has one) an account counts as
    // still holding, the safe side (#1094).
    const left = by ? await within(hasLeft(d), by - Date.now(), () => false) : await hasLeft(d);
    if (left) out.add(String(d));
  }
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

/*
  THE JOIN PASS (#937). Patrick, 28 Sep: "People should not be allowed in at all
  if they don't join from our launcher." The game server only ever sees a
  profile number the client picked, so it cannot tell our launcher from Skyrim
  started by hand, from another launcher, or from one of ours that is out of
  date. The launcher asks /api/play/pass for this with the Discord ticket it
  already holds, the game's front plugin hands it to the game server, and the
  game server checks it with its own copy of the key (gamemode.js, the join pass
  block) and ends a session that has none.

      jp1.<body>.<mac>

  body is base64url JSON: p the profile number, s the server ("main" or "dev"),
  v the launcher version, d the Discord id, i when it was issued and x when it
  runs out, both unix milliseconds. mac is base64url HMAC-SHA256 over "jp1." and
  the body, keyed on cfg.passKey. tests\test-join-pass-site.js and
  tests\test-join-pass-game.js hold one pass in common, so the two ends cannot
  drift apart. Ten minutes, though the game server lets a pass prove one
  session only, and start one only in the minute and a half after i (#1320),
  so the launcher renews it every minute while the game runs.
*/
const PASS_MS = 10 * 60000;

function b64u(buf) {
  return Buffer.from(buf).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function makePass(key, o) {
  const body = b64u(JSON.stringify({ p: o.p, s: o.s, v: o.v, d: o.d, i: o.i, x: o.x }));
  const mac = b64u(crypto.createHmac('sha256', key).update('jp1.' + body).digest());
  return 'jp1.' + body + '.' + mac;
}

/* Digits and dots, an optional leading v, nine digits a part at most: the
   same rule FeedNotice.IsVersion keeps in the launcher. Null for anything else. */
function versionParts(v) {
  const t = String(v == null ? '' : v).trim().replace(/^v/i, '');
  if (!/^\d{1,9}(\.\d{1,9})*$/.test(t)) return null;
  return t.split('.').map(Number);
}

function versionCompare(a, b) {
  const n = Math.max(a.length, b.length);
  for (let i = 0; i < n; i++) {
    const x = a[i] || 0, y = b[i] || 0;
    if (x !== y) return x < y ? -1 : 1;
  }
  return 0;
}

/* Which launchers a channel lets into the game: from minLauncher (Publish-Update
   writes it as the launcher it published) up to launcherVersion, both read from
   this site's own copy of the feed. With no minLauncher the floor is the current
   launcher. Null when the feed cannot be read, which refuses the pass. Read again
   only when the file changes. */
const feedLaunchersSeen = {};
function feedLaunchers(server) {
  const dir = server === 'dev' ? 'feed-dev' : 'feed';
  const file = path.join(ROOT, dir, 'version.json');
  let st;
  try { st = fs.statSync(file); } catch (e) { return null; }
  const hit = feedLaunchersSeen[dir];
  if (hit && hit.mtime === st.mtimeMs && hit.size === st.size) return hit.v;
  let doc = null;
  try { doc = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, '')); } catch (e) { doc = null; }
  let v = null;
  if (doc && versionParts(doc.launcherVersion)) {
    const current = String(doc.launcherVersion).trim().replace(/^v/i, '');
    const min = versionParts(doc.minLauncher) ? String(doc.minLauncher).trim().replace(/^v/i, '') : current;
    v = { current: current, min: min };
  }
  feedLaunchersSeen[dir] = { mtime: st.mtimeMs, size: st.size, v: v };
  return v;
}

function getWithToken(url, token) {
  const u = new URL(url);
  return boundDiscord((h) => https.get({
    hostname: u.hostname, path: u.pathname,
    headers: { Authorization: 'Bearer ' + token }
  }, (res) => readDiscordBody(res, h)));
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
  return '<!doctype html><html lang="en"><head><meta charset=utf-8><title>' + esc(title) + ' | Thornswood</title>' +
    '<meta name="description" content="Find your way back to Thornswood, the Skyrim roleplay community.">' +
    '<meta name="robots" content="noindex"><link rel="icon" href="/favicon.ico">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<link rel="stylesheet" href="/door.css">' +
    '</head><body class="door">' +
    '<main class="door-box">' +
    '<h1>' + esc(title) + '</h1>' +
    lines.map((t) => '<p>' + esc(t) + '</p>').join('') +
    '<p><a href="/">Back to Thornswood</a> · <a href="/help">Get help</a></p>' +
    '</main></body></html>';
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
          '<p class="door-note">' + esc(st.lookupFailed) + '</p>' +
          '<p>Tell Patrick and try again in a minute.</p>';
  } else if (st.banned) {
    why = '<p>That account is banned from Thornswood.</p>';
  } else if (!st.inGuild) {
    why = '<p>That account is not in the Thornswood Discord.</p>' +
      (cfg.discord.invite
        ? '<p><a href="' + cfg.discord.invite + '">Join it here</a>, then try again.</p>'
        : '');
  } else {
    why = '<p>That account is in the Discord, but ' + esc(notAcceptedYet(true)) + '</p>' +
          '<p class="door-note">Roles Thornswood can see on it: ' +
          (st.roles && st.roles.length ? '<b>' + st.roles.map(esc).join(', ') + '</b>' : 'none') +
          '.<br>It needs one of: <b>' + (cfg.access.play || []).map(esc).join(', ') + '</b>.</p>';
  }
  return '<!doctype html><meta charset=utf-8><title>Not allowed in</title>' +
    '<link rel="stylesheet" href="/door.css">' +
    '<body class="door">' +
    '<div class="door-box"><h1>Not allowed in</h1>' +
    why +
    '<p class="door-note">Signed in to Discord as <b>' + nm +
    '</b>, id <code>' + id + '</code>. Quote that id if you ask about it.</p>' +
    '<p><a href="/">Back to the site</a></p></div></body>';
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
  // What was sent could not be read (body() above, #1095): too big or too
  // slow is answered in words, and a connection already gone gets nothing.
  // Closed after, so the rest of a body too big is not read for nothing.
  if (e instanceof BodyFailed) {
    console.error('[thornswood-docs] body ' + e.why + ' on ' +
                  JSON.stringify(String(req.url || '').split('?')[0].slice(0, 200)));
    try {
      if (!e.status || res.headersSent || res.destroyed) { if (!res.writableEnded) res.destroy(); return; }
      send(res, e.status, JSON.stringify({ ok: false, why: e.why, error: e.words, message: e.words }),
           null, { Connection: 'close' });
    } catch (e2) { }
    return;
  }
  const bad = e instanceof URIError;
  // The path and never the query. A caller that puts a key or a ticket in the
  // address would have it copied into site.log, which Get-Logs brings down
  // off the VPS. Entry 248.
  console.error('[thornswood-docs] ' + (bad ? 'malformed request ' : 'handler threw on ') +
                JSON.stringify(String(req.url || '').split('?')[0].slice(0, 200)) + ': ' +
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
  the catch above. After an uncaught exception Node says the process is in an
  unknown state, so carrying on can hand out corrupt answers or half-written
  files (#1358). Log it, then exit, and let the process manager start a clean
  one. How the process is hosted and the three restarts an hour are entry 105.

  An unhandled rejection is different: the process is still defined, so it is
  logged and the site keeps answering.
*/
process.on('unhandledRejection', (e) => {
  console.error('[thornswood-docs] unhandled rejection, carrying on: ' +
                (e && e.stack ? e.stack : e));
});
process.on('uncaughtException', (e) => {
  console.error('[thornswood-docs] uncaught exception, exiting: ' +
                (e && e.stack ? e.stack : e));
  process.exit(1);
});

async function handle(req, res) {
  // Apply before parsing the address, so streamed and malformed responses
  // carry the same policy as ordinary pages.
  res.setHeader('Content-Security-Policy', CSP_HEADER);
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'SAMEORIGIN');
  /* The address is a path on this site, so it is read as one (#929).

     new URL(req.url, 'http://x') read an address that starts with two slashes
     as a scheme relative one, //host/path, so the first segment became a host
     name rather than part of the path. // and /// have no host at all and
     threw Invalid URL, which answered 500. //rules, //config.json and ///x
     came out as the path "/" and were all answered with the front page. A
     backslash counts as a slash there, so /\ did the same. Putting the origin
     in front of a path keeps every slash of it in the path. An address that
     is not a path (the absolute form a proxy sends, or *) is read as before,
     and one that still cannot be read is the request's fault: 400, like a
     bad percent sign, never 500. */
  const raw = String(req.url || '/');
  let url;
  try { url = new URL(raw.charAt(0) === '/' ? 'http://x' + raw : raw, 'http://x'); }
  catch (e) { return failed(req, res, new URIError('not an address: ' + e.message)); }
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

     CSP and Referrer-Policy (#1366) ride the same path so a Range answer or a
     piped file is not the one reply without them. send() also sets them for
     the ordinary answers.

     Only on an answer that came in over the certificate. Caddy holds 443 and
     the plain to secure redirect already works, so this is the part that stops
     a browser trying the plain one again. On plain HTTP it means nothing and
     is left off. */
  if (secureHere(req)) {
    try { res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains'); } catch (e) { }
  }

  /* Two slashes together are one (#929). The site already reads /rules/ and
     /rules// as /rules, so //rules, /feed//version.json and // itself are
     sent to the same address with one slash, by the same 301 that sends
     /download to /downloads. Slashes only at the end are left to the routes
     below, exactly as before. The address sent is the one the URL parser
     already read, with its dot segments resolved and every backslash made a
     slash, and every run of slashes is one after this, so it always starts
     with exactly one slash and can never name another site. Where it lands is
     asked for again and goes through every check below, the /feed assets'
     64 hex name included. Only GET and HEAD: a POST to //api/login is not a
     door, and falls to the 404 at the bottom. */
  if (req.method === 'GET' && (/\/\/(?!\/*$)/.test(url.pathname) || /^\/\/+$/.test(url.pathname))) {
    return send(res, 301, '', 'text/plain', { Location: url.pathname.replace(/\/{2,}/g, '/') + url.search });
  }

  if (req.method === 'GET' && PUBLIC_PAGES.includes(route) &&
      /^www\.thornswood\.net(?::\d+)?$/i.test(req.headers.host || '')) {
    return send(res, 301, '', 'text/plain', {Location:PUBLIC_ORIGIN + route + url.search});
  }
  // These contain only public addresses. They never require a Discord lookup.
  if (req.method === 'GET' && route === '/sitemap.xml') {
    return send(res, 200, '<?xml version="1.0" encoding="UTF-8"?>\n' +
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' +
      PUBLIC_PAGES.map(page => '<url><loc>' + PUBLIC_ORIGIN + page + '</loc></url>').join('') + '</urlset>',
      'application/xml; charset=utf-8');
  }
  if (req.method === 'GET' && route === '/robots.txt') {
    return send(res, 200, fs.readFileSync(path.join(PUBLIC, 'robots.txt')), 'text/plain; charset=utf-8',
      {'Cache-Control':'public, max-age=3600'});
  }
  if (req.method === 'GET' && route === '/llms.txt') {
    const pages = ['/world','/rules','/join','/classes','/known','/help','/news','/roadmap','/privacy','/terms','/cookies','/credits'];
    return send(res, 200, '# Thornswood\n\n> A free Skyrim roleplay fan project and online community. Eighteen and over.\n\n' +
      'The site describes an evolving game. Consult Known issues for current limits and News for released changes.\n\n## Public pages\n\n' +
      pages.map(page => '- [' + BLURB[page][0] + '](' + PUBLIC_ORIGIN + page + '): ' + BLURB[page][1]).join('\n') + '\n',
      'text/plain; charset=utf-8');
  }

  if (req.method === 'GET' && (/^\/api\/(?:public|gallery|releases|roadmap)$/.test(route) || /^\/api\/page\/[a-z-]+$/.test(route))) {
    const retry = publicApiWait(req, Date.now());
    if (retry) return send(res, 429, JSON.stringify({error:'Too many requests. Try again shortly.'}),
      'application/json; charset=utf-8', {'Retry-After':String(retry)});
  }

  // Nothing is changed for a page on another site (#1367, crossSite above).
  // Asked before anything else is, Discord included, so a refused request
  // costs nothing and every route below it is covered.
  const foreign = crossSite(req);
  if (foreign) {
    const named = String(req.headers.origin || req.headers.referer || 'no page named');
    console.log('[thornswood-docs] refused a ' + req.method + ' to ' + route.slice(0, 80) +
                ' from another site (' + foreign + ': ' + named.replace(/[^\x20-\x7e]/g, '?').slice(0, 120) + ')');
    return sendJson(res, 403, { ok: false, why: 'cross-site', error: foreign === 'neither'
      ? 'Your browser did not say which page sent that, so it was not done. Do it from a page on this site, in a browser that says so.'
      : 'That was sent from a page on another site, so it was not done. Do it from a page on this site.' });
  }

  // A page load (GET, HEAD was made GET above) waits SUBMIT_WAIT_MS and may
  // use the last answer Discord gave (#1096). A Submit waits that same short
  // time (#467). Every other request that is signed in, including a staff
  // POST from the hub, waits no longer than Play (#1164).
  const pageLoad = req.method === 'GET';
  const submitDoor = req.method === 'POST' && SUBMIT_DOORS.has(route);
  const w = await who(req, (pageLoad || submitDoor) ? SUBMIT_WAIT_MS : PLAY_ANSWER_MS, pageLoad);

  // ---------------------------------------------------------- member login
  if (p === '/api/login' && req.method === 'POST') {
    const from = loginKey(req);
    const wait = loginWait(from, Date.now());
    if (wait) {
      // The window above is the cap (#1305). While the member password is
      // the door, each further guess waits longer than the last (#1308).
      // Discord sign-in keeps the flat window and does not grow this wait.
      const retry = discordReady() ? wait : loginBackoffBump(from, Date.now(), wait);
      return send(res, 429, JSON.stringify({
        error: 'Too many sign-in attempts from this connection. Try again in ' + retry + ' seconds.'
      }), 'application/json; charset=utf-8', { 'Retry-After': String(retry) });
    }
    loginNote(from, Date.now());
    if (discordReady()) {
      return sendJson(res, 403, { error: 'Discord sign in only. The password is off.' });
    }
    let given = '';
    try { given = (JSON.parse(await body(req, 4096)) || {}).password || ''; }
    catch (e) { passBodyFailure(e); }
    if (!cfg.password || !sameSecret(given, String(cfg.password))) {
      return sendJson(res, 401, { error: 'wrong password' });
    }
    loginBackoff.delete(from);
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
    // This attempt's own value and the time it began, after the three above,
    // and the same value in a cookie for this browser. See ATTEMPT.
    const attempt = crypto.randomBytes(16).toString('hex');
    const raw = Buffer.from(back + '\u0000' + askedPort + '\u0000' + nonce + '\u0000' +
                            attempt + '\u0000' + Date.now()).toString('base64url');
    const state = raw + '.' + sign(raw);
    const go = 'https://discord.com/api/oauth2/authorize' +
      '?client_id=' + encodeURIComponent(cfg.discord.clientId) +
      '&redirect_uri=' + encodeURIComponent(origin(req) + '/auth/discord/callback') +
      '&response_type=code&scope=identify' +
      '&state=' + encodeURIComponent(state);
    return send(res, 302, '', 'text/plain', {
      Location: go, 'Set-Cookie': attemptCookie(req, attempt, attempt, ATTEMPT_MS / 1000) });
  }

  if (p === '/auth/discord/callback' && req.method === 'GET') {
    const code = url.searchParams.get('code') || '';
    const state = (url.searchParams.get('state') || '').split('.');
    let back = '/', port = '', nonce = '', attempt = '', began = 0;
    if (state.length === 2 && sameSecret(state[1], sign(state[0]))) {
      try {
        const bits = Buffer.from(state[0], 'base64url').toString().split('\u0000');
        back = bits[0] || '/';
        port = (bits[1] || '').replace(/[^0-9]/g, '').slice(0, 5);
        nonce = (bits[2] || '').replace(/[^A-Za-z0-9]/g, '').slice(0, 64);
        attempt = (bits[3] || '').replace(/[^0-9a-f]/g, '').slice(0, 32);
        began = Number(bits[4]) || 0;
      } catch (e) { }
    }
    // Refused here, before Discord is asked anything: a state with no attempt
    // in it, one this browser did not start, one already used, or one older
    // than ten minutes. A signature alone used to be enough, and it is the
    // same for everybody who asked for the same page.
    const now = Date.now();
    for (const [k, t] of attemptsSpent) { if (now - t > ATTEMPT_MS) attemptsSpent.delete(k); }
    const age = now - began;
    if (attempt.length !== 32 || attemptsSpent.has(attempt) ||
        !(age > -60000 && age < ATTEMPT_MS) ||
        !sameSecret(cookies(req)[ATTEMPT + attempt.slice(0, 8)] || '', attempt)) {
      return send(res, 302, '', 'text/plain', { Location: '/?discord=expired' });
    }
    // Spent whatever happens next, and the cookie cleared on every answer
    // below. The one that sets cookies of its own carries this in its list.
    attemptsSpent.set(attempt, now);
    const spent = attemptCookie(req, attempt, '', 0);
    res.setHeader('Set-Cookie', spent);
    // Two slashes is another host to a browser (//2130706433), so back has to
    // start with exactly one.
    if (!/^\/(?!\/)[A-Za-z0-9/_-]*$/.test(back)) back = '/';
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
      // Discord never finished (#1163). Words on this answer, not a blank
      // wait and not a redirect the page has to interpret.
      if (e && e.discordSilent) {
        return send(res, 200, plainPage('Discord did not answer', [
          'Discord did not answer.',
          'Try again.'
        ]), TYPES['.html']);
      }
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
    // When it was made goes inside the signature, so identity() can refuse
    // it once it is older than ADMIN_DAYS whatever the browser kept.
    const at = String(Date.now());
    const value = encodeURIComponent(me.id + '|' + name + '|' + at + '|' +
                                     sign(me.id + '|' + name + '|' + at));

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

    const cookies2 = [setCookie(req, ADMIN, value, ADMIN_DAYS),
                      setCookie(req, COOKIE, memberToken(), 365), spent];

    // The launcher asked, so hand the ticket back to it on the loopback
    // address rather than leaving it in the browser.
    if (port) {
      return send(res, 302, '', 'text/plain', {
        Location: 'http://127.0.0.1:' + port + '/thornswood?ticket=' +
                  encodeURIComponent(makeTicket(me.id, name)) +
                  '&name=' + encodeURIComponent(name) +
                  (me.avatar ? '&avatar=' + encodeURIComponent(String(me.avatar)) : '') +
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
      ok: w.member, admin: w.admin, dev: !!w.dev, play: !!w.play,
      name: w.name,
      discord: discordReady(),
      invite: cfg.discord.invite || ''
    });
  }

  // ---------------------------------------------------------- public front
  if (req.method === 'GET' && PUBLIC_PAGES.indexOf(route) >= 0) {
    try {
      // The one switch (#428): only the alpha or the open wording goes out.
      let html = forMode(fs.readFileSync(path.join(PUBLIC, 'home.html'), 'utf8'), cfg.open);
      // One place holds the invite link, so it cannot go stale in nine.
      // /join, never /hub. Somebody clicking Apply wants to know how to apply,
      // and sending them to the admin panel is the worst possible answer.
      html = html.split('DISCORD_URL').join(cfg.discord.invite || '/join');
      // The og tags a crawler reads are the ones in the file, so the page
      // actually being served is written into them here. home.html rewrites
      // the same tags for the browser tab.
      const blurb = BLURB[route];
      let pageTitle = null;
      if (blurb) {
        pageTitle = blurb[0] === 'Thornswood' ? blurb[0] : blurb[0] + ' · Thornswood';
        html = html.replace(
          /(<meta property="og:title" id="ogTitle" content=")[^"]*(")/,
          '$1' + escAttr(pageTitle) + '$2');
        for (const re of [/(<meta property="og:description" id="ogDesc" content=")[^"]*(")/,
                          /(<meta name="description" content=")[^"]*(")/]) {
          html = html.replace(re, '$1' + escAttr(blurb[1]) + '$2');
        }
      }
      // A written page goes out with its words in it. After the invite link
      // above, so nothing anybody typed is mistaken for DISCORD_URL.
      if (MD_PAGES.indexOf(route) >= 0) {
        let md = pageMarkdown(route.slice(1));
        if (md !== null && route === '/credits') {
          const facts = creditsFacts();
          md = fillCreditsCommits(md, facts.deployed, facts.feeds);
        }
        if (md === null) return send(res, 404, notFoundPage(), TYPES['.html']);
        html = fillPage(html, singlePageHeading(pageHtml(md), blurb[0]));
      } else if (route !== '/') {
        // The remaining public pages draw themselves after an API fetch. Do not
        // paint the home landing while that request is in flight.
        html = fillPage(html, publicPageBody(route));
        // MD pages get <title> from fillPage (the page's h1). Non-MD routes
        // used to keep the home title until the page's script ran, so a crawler
        // or a slow tab saw only Thornswood. Set it from BLURB here.
        if (pageTitle) {
          html = html.replace('<title>Thornswood</title>',
            () => '<title>' + escAttr(pageTitle) + '</title>');
        }
      }
      html = publicDiscovery(html, route);
      return send(res, 200, html, TYPES['.html']);
    } catch (e) { return send(res, 500, 'no home.html', 'text/plain'); }
  }

  // Two addresses people type, or paste out of an old message. Both mean the
  // Downloads page, and both answered 404.
  if ((route === '/download' || route === '/install') && req.method === 'GET') {
    return send(res, 301, '', 'text/plain', { Location: '/downloads' });
  }

  // The template the front route fills in. Served as a file it still says
  // DISCORD_URL and shows both the alpha wording and the open wording (#997).
  if (route === '/home.html' && req.method === 'GET') {
    return send(res, 301, '', 'text/plain', { Location: '/' });
  }

  // Everything the front page needs and nothing that is anybody's business.
  if (route === '/api/public' && req.method === 'GET') {
    const feed = publicJson(NEWS, { news: [] });
    // Installed launchers read the original full array. The website opts into
    // pagination until those clients can follow a continuation themselves.
    const gallery = galleryPage(0, url.searchParams.get('galleryLimit') === '24' ? 24 : Number.MAX_SAFE_INTEGER);
    return sendJson(res, 200, {
      // The one switch (#428), for the pages and the Discord bot.
      open: cfg.open === true,
      invite: cfg.discord.invite || '',
      patreon: cfg.patreon || '',
      // max is always the number when one is known anywhere, so the page
      // says "N of 25" whether or not the server has said it (#481).
      status: { up: gameStatus.up, online: gameStatus.online, max: gameStatus.max || mostOnlineFallback(),
                line: gameStatus.line, full: seatsFull(gameStatus) },
      gallery: gallery.gallery,
      galleryTotal: gallery.total,
      galleryNext: gallery.next,
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
    "url":", "size": and "sha256":", so the shape matters more than the field
    order.
  */
  if (route === '/api/payload' && req.method === 'GET') {
    let best = null;
    try {
      for (const name of fs.readdirSync(FILES)) {
        if (!/^Thornswood-Setup(?:-\d{8}-\d{4})?\.zip$/i.test(name)) continue;
        const st = fs.statSync(path.join(FILES, name));
        if (!st.isFile()) continue;
        if (!best || st.mtimeMs > best.at) best = { name, at: st.mtimeMs, size: st.size };
      }
    } catch (e) { }
    // No zip means a one file build, where the payload rides inside the exe
    // and nothing should be fetched. Bootstrap turns an empty url into "The
    // site is not offering a download right now", which is the truth.
    if (!best) return sendJson(res, 200, {});
    // The SHA-256 Publish-Installer measured on the zip it sent, kept in
    // files.json beside its name. best is built from a stat and has no hash on
    // it, so it is looked up here. Only a well formed one goes out: anything
    // else would make every install delete a good download. An empty value is
    // what an installer from before this sees when the field is missing; an
    // installer from #1365 on stops on it rather than fetching half a
    // gigabyte it has no way to measure, so a publish without files.json
    // beside the zip is an install nobody can run.
    const meta = jsonFile(path.join(FILES, 'files.json'), {});
    const sha = String((meta[best.name] || {}).sha256 || '');
    return sendJson(res, 200, {
      name: best.name,
      url: '/file/' + encodeURIComponent(best.name),
      size: best.size,
      sha256: /^[0-9a-f]{64}$/i.test(sha) ? sha.toLowerCase() : ''
    });
  }

  /* Reporting a problem is public on purpose. Somebody whose install will not
     start cannot sign in to say so, and making them ask in Discord first is
     how a bug turns into nobody bothering. Held to one short message at a
     time, five an hour from one place, and the inbox is capped so it cannot
     be used to fill the disk. See thornswood report limits above. */
  if (route === '/api/report' && req.method === 'POST') {
    const sender = reportFrom(req);
    const refuse = (no) => send(res, 429, JSON.stringify({ error: no.error }), null,
                                { 'Retry-After': String(no.wait) });
    // Asked before the body is read, so a sender already past the limit is
    // turned away without the site reading 20 KB from them first.
    const early = reportRefusal(sender, Date.now());
    if (early) return refuse(early);
    let o;
    try { o = JSON.parse(await body(req, 20000)); }
    catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
    // The form's hidden field. A person never sees it, so anything in it was
    // put there by a script filling in every box it found. Answered as if it
    // worked, so the script has nothing to learn from, and nothing is kept.
    if (o && String(o.homepage || '').trim()) return sendJson(res, 200, { ok: true });
    const title = String(o.title || '').trim().slice(0, 200);
    if (!title) return sendJson(res, 400, { error: 'say what happened in the first box' });
    // And asked again now the body is in, because the answer above is stale.
    // A script that opens thirty connections, sends every set of headers and
    // then every body gets all thirty past the first check before any of
    // them is counted, and Caddy passes headers on before it has the body, so
    // that works through it. From here to reportTaken nothing awaits, so no
    // other request can run in between and each one sees the last one's count.
    const late = reportRefusal(sender, Date.now());
    if (late) return refuse(late);
    /* A REPORT ABOUT A PERSON IS NEVER ANONYMOUS (#414). A problem or an idea
       needs no account, because somebody whose install will not start cannot
       sign in. A report naming somebody does: it is kept against the Discord
       account that sent it, so staff can come back to the reporter and so a
       made up grudge cannot fill the queue from a hundred browsers. It is
       counted per account as well as per connection. */
    let person = null;
    if (o.kind === 'report') {
      const no = personReportRefusal(w);
      if (no) return sendJson(res, no.code, { error: no.error });
      const about = String(o.about || '').trim().slice(0, 60);
      if (!about) return sendJson(res, 400, { error: 'say who it is about in the Who box' });
      const acct = 'acct:' + w.id;
      const mine = reportRefusal(acct, Date.now(), 'your account');
      if (mine) return refuse(mine);
      person = { about, acct };
    }
    const list = jsonFile(INBOX, []);
    list.unshift(Object.assign({
      id: 'i' + Date.now().toString(36) + crypto.randomBytes(2).toString('hex'),
      kind: person ? 'report' : (o.kind === 'idea' ? 'idea' : 'bug'),
      title,
      detail: String(o.detail || '').slice(0, 8000),
      by: person ? String(w.name || '').slice(0, 40) : String(o.by || '').slice(0, 40),
      at: Date.now(),
      state: 'new',
      from: person ? 'the public page, signed in' : 'the public page'
    }, person ? { about: person.about, discordId: String(w.id) } : {}));
    if (!putJson(INBOX, trimInbox(list))) {
      return sendJson(res, 500, { error: 'could not save' });
    }
    reportTaken(sender, Date.now());
    if (person) reportTaken(person.acct, Date.now());
    return sendJson(res, 200, { ok: true });
  }

  /*
    From inside the game: /helpme and /report (#414, gamemode.js, the asking
    staff block). Keyed with the door's key in a header, the same key and the
    same header /api/allowed takes, so nothing but a game server can write
    one. The dev server's door.json names the site with /dev on the end, so
    its reports come in on /dev/api/report/game and say so.

    Counted per profile on the same limits as the public page, as a backstop
    behind the game's own tighter ones. The profile id is what the game
    server was told by the client, a claim rather than a proof, and the row
    says so in words staff read.
  */
  if ((route === '/api/report/game' || route === '/dev/api/report/game') && req.method === 'POST') {
    if (!cfg.botKey) return sendJson(res, 404, { error: 'not set up' });
    if (!sameSecret(String(req.headers['x-thornswood-key'] || ''), String(cfg.botKey))) {
      return sendJson(res, 401, { error: 'no' });
    }
    let o;
    try { o = JSON.parse(await body(req, 8000)) || {}; }
    catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
    const dev = route.indexOf('/dev/') === 0;
    const kind = o.kind === 'report' ? 'report' : (o.kind === 'help' ? 'help' : '');
    const pid = Number(o.profileId) || 0;
    if (!kind || !(pid > 0)) return sendJson(res, 400, { error: 'no kind or no profile' });
    const key = 'game:' + (dev ? 'dev:' : '') + pid;
    const no = reportRefusal(key, Date.now(), 'that profile');
    if (no) return send(res, 429, JSON.stringify({ error: no.error }), null, { 'Retry-After': String(no.wait) });
    const name = String(o.name || '').trim().slice(0, 60) || 'Somebody';
    const about = String(o.about || '').trim().slice(0, 60);
    if (kind === 'report' && !about) return sendJson(res, 400, { error: 'a report names somebody' });
    const said = String(o.said || '').trim().slice(0, 300);
    const cell = String(o.cell || '').slice(0, 120);
    const pos = (Array.isArray(o.pos) ? o.pos : []).slice(0, 3).map((n) => Math.round((Number(n) || 0) * 10) / 10);
    const aboutPid = Number(o.aboutProfileId) || 0;
    const list = jsonFile(INBOX, []);
    list.unshift({
      id: 'i' + Date.now().toString(36) + crypto.randomBytes(2).toString('hex'),
      kind,
      title: kind === 'help' ? (said || 'Asked for help and said nothing more') : said,
      about: kind === 'report' ? about : '',
      aboutProfileId: kind === 'report' && aboutPid > 0 ? aboutPid : 0,
      detail: 'At ' + (cell || 'an unknown place') + (pos.length === 3 ? ', ' + pos.join(', ') : '') + '. ' +
        'Profile ' + pid + (kind === 'report' && aboutPid > 0 ? ', about profile ' + aboutPid : '') +
        ': the game takes these numbers from the client, so they are a claim, not proof. ' +
        (Number(o.staffTold) > 0 ? Number(o.staffTold) + ' of staff in the world were told in game.'
                                 : 'Nobody from staff was in the world.'),
      by: name,
      profileId: pid,
      cell,
      pos,
      at: Date.now(),
      state: 'new',
      from: dev ? 'in game on the dev server' : 'in game'
    });
    if (!putJson(INBOX, trimInbox(list))) {
      return sendJson(res, 500, { error: 'could not save' });
    }
    reportTaken(key, Date.now());
    return sendJson(res, 200, { ok: true });
  }

  /*
    Bans and notes from staff in the game (#412): /ban, /unban and /note in
    the gamemode's staff block. Keyed with the door's key in the header, like
    /api/report/game above, and /dev on the front from the dev server.

    The game server has already checked that the one asking holds a staff
    role and proved who they are (join token and join pass). This checks the
    role again here, on the Discord account that holds their profile, so a
    game server cannot make somebody staff by saying so.

    One character or the whole account (#1010): ban and unban are the one
    character, kept under "p:<profile>"; banaccount and unbanaccount are the
    Discord account holding the profile, so every character on it is covered,
    and a new one too, and the door leaves them all out. A profile no account
    holds has no account to ban, and says so. minutes 0 is for good. pk kills
    the character for good (see PK): it is kept, never played again. Staff
    may do any of these to staff; the game refuses only doing it to yourself.
    unpk (/unpk) undoes a PK made by mistake, for the admin role only (see
    PK); the character is found by findDead, and o.why is required.
  */
  const staffGame = /^(\/dev)?\/api\/staff\/game\/(ban|unban|banaccount|unbanaccount|pk|unpk|note)$/.exec(route);
  if (staffGame && req.method === 'POST') {
    if (!cfg.botKey) return sendJson(res, 404, { error: 'not set up' });
    if (!sameSecret(String(req.headers['x-thornswood-key'] || ''), String(cfg.botKey))) {
      return sendJson(res, 401, { error: 'no' });
    }
    let o;
    try { o = JSON.parse(await body(req, 8000)) || {}; }
    catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
    const from = staffGame[1] ? 'the dev server' : 'the live server';
    const byPid = Number(o.byProfileId) || 0;
    if (staffGame[2] === 'unpk' && byPid > 0) {
      const byIdU = accountOf(byPid);
      if (!byIdU) return sendJson(res, 403, { error: 'the staff profile is not linked to a Discord account' });
      const stU = await standingCached(byIdU);
      if (stU.lookupFailed && !stU.admin) return sendJson(res, 503, { error: 'could not ask Discord' });
      if (!stU.admin || stU.banned) {
        return sendJson(res, 403, { error: 'admins only', message: 'Only an admin can undo a PK.' });
      }
      const hit = findDead(o);
      if (!hit.pid) return sendJson(res, 404, { error: 'no such dead character', message: hit.message });
      const whyU = String(o.why || (hit.rest || []).join(' ')).trim().slice(0, 500);
      if (!whyU) {
        return sendJson(res, 400, { error: 'an undo says why',
          message: 'Say why: /unpk ' + (String((jsonFile(PK, {})[String(hit.pid)] || {}).name || '') || hit.pid) +
                   ' made by mistake.' });
      }
      const byNameU = String(o.byName || stU.name || '').slice(0, 60);
      const u = await undoPk(hit.pid, byNameU, byIdU, whyU, from);
      return sendJson(res, u.status, Object.assign({ profileId: hit.pid, why: whyU }, u.body));
    }
    const pid = Number(o.profileId) || 0;
    if (!(pid > 0) || !(byPid > 0)) return sendJson(res, 400, { error: 'no profile' });
    const byId = accountOf(byPid);
    if (!byId) return sendJson(res, 403, { error: 'the staff profile is not linked to a Discord account' });
    const st = await standingCached(byId);
    if (st.lookupFailed && !st.admin) return sendJson(res, 503, { error: 'could not ask Discord' });
    if (!st.dev || st.banned) return sendJson(res, 403, { error: 'that Discord account holds no staff role' });
    const byName = String(o.byName || st.name || '').slice(0, 60);
    const name = String(o.name || '').slice(0, 60);
    const key = recordKey(pid);
    const account = accountOf(pid);
    const now = Date.now();
    const what = staffGame[2];

    if (what === 'ban' || what === 'banaccount') {
      const why = String(o.why || '').trim().slice(0, 500);
      if (!why) return sendJson(res, 400, { error: 'a ban says why' });
      if (what === 'banaccount' && !account) {
        return sendJson(res, 404, { error: 'no Discord account holds that character, so ban the character' });
      }
      const minutes = banMinutes(o.minutes);
      const until = minutes ? now + minutes * 60000 : 0;
      const whole = what === 'banaccount';
      const banKey = whole ? account : 'p:' + pid;
      if (!putBan(banKey, { at: now, until, why, by: byName, byId, name, profiles: [pid], from,
                            scope: whole ? 'account' : 'character', account })) {
        return sendJson(res, 500, { error: 'could not save' });
      }
      // Every character the ban covers, so the game server can end each one
      // that is online now rather than at its next list.
      const covers = whole
        ? Array.from(new Set([pid].concat(((jsonFile(LINKED, {})[account] || {}).profiles || [])
                                            .map(Number).filter((n) => n > 0))))
        : [pid];
      return sendJson(res, 200, { ok: true, until, account: whole, profiles: covers });
    }
    if (what === 'unban' || what === 'unbanaccount') {
      if (what === 'unbanaccount' && !account) {
        return sendJson(res, 404, { error: 'no Discord account holds that character' });
      }
      const r = dropBan([what === 'unbanaccount' ? account : 'p:' + pid]);
      if (!r.ok) return sendJson(res, 500, { error: 'could not save' });
      const freed = what === 'unbanaccount'
        ? Array.from(new Set([pid].concat(((jsonFile(LINKED, {})[account] || {}).profiles || [])
                                            .map(Number).filter((n) => n > 0))))
        : [pid];
      return sendJson(res, 200, { ok: true, was: r.was, profiles: freed });
    }
    if (what === 'pk') {
      const why = String(o.why || '').trim().slice(0, 500);
      if (!why) return sendJson(res, 400, { error: 'a PK says why' });
      const had = jsonFile(PK, {})[String(pid)];
      if (pkActive(had)) return sendJson(res, 200, { ok: true, was: true, at: Number(had.at) || 0 });
      if (!putPk(pid, { at: now, by: byName, byId, why, name, account, from })) {
        return sendJson(res, 500, { error: 'could not save' });
      }
      return sendJson(res, 200, { ok: true, was: false, at: now });
    }
    const text = String(o.text || '').trim().slice(0, 1000);
    if (!text) return sendJson(res, 400, { error: 'a note says something' });
    if (!putNote(key, { at: now, by: byName, byId, text, profileId: pid, name, from })) {
      return sendJson(res, 500, { error: 'could not save' });
    }
    return sendJson(res, 200, { ok: true });
  }

  if (route === '/api/ticket' && req.method === 'POST') {
    if (!cfg.botKey) return sendJson(res, 404, { error: 'not set up' });
    let o;
    try { o = JSON.parse(await body(req, 40000)); }
    catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
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
    if (!putJson(INBOX, trimInbox(list))) {
      return sendJson(res, 500, { error: 'could not save' });
    }
    // An application's answer to the rules question (#428), kept against the
    // Discord id. The ticket is already saved, so a failure here is logged
    // rather than handed back as a failed ticket.
    if (o.rules && !noteRules(RULES_OK, o.discordId, o.rules, o.by, Date.now())) {
      console.error('[thornswood-docs] could not write down the rules answer for ' +
                    String(o.discordId || '').replace(/[^0-9]/g, '').slice(0, 20));
    }
    return sendJson(res, 200, { ok: true });
  }

  if (route === '/api/roadmap' && req.method === 'GET') {
    const all = readBoard();
    // The intro is markdown, and it is rendered here like the written pages
    // so the front page needs no markdown library of its own.
    const rm = all.roadmap || { intro:'', sections:[] };
    return sendJson(res, 200, Object.assign({}, rm,
      { introHtml: rm.intro ? pageHtml(rm.intro) : '' }));
  }

  if (route === '/api/releases' && req.method === 'GET') {
    const feed = publicJson(NEWS, { launcher:'', news: [] });
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

  const verRoute = route.match(/^\/api\/page-version\/([0-9a-fA-F]{64})$/);
  if (verRoute && req.method === 'GET') {
    const hit = findPageVersion(verRoute[1]);
    if (!hit) return sendJson(res, 404, { error: 'no such version' });
    return sendJson(res, 200, hit);
  }

  const pg = route.match(/^\/api\/page\/([a-z-]+)$/);
  if (pg && req.method === 'GET') {
    // The same page the front route renders, for a home.html that was served
    // without it. html is the one to show; md is kept for anything reading it.
    // sha256 is what the installer stores. changed is the day that wording last changed,
    // or null when the list has no row for this text.
    const md = pageMarkdown(pg[1]);
    if (md === null) return sendJson(res, 404, { error: 'no such page' });
    const sha = pageSha256(md);
    const ver = findPageVersion(sha);
    return sendJson(res, 200, {
      md: md, html: pageHtml(md), sha256: sha, changed: ver ? ver.changed : null
    });
  }

  // Pictures chosen for the gallery are public. Everything else in uploads is
  // not, which is why this is a separate door with its own list.
  if (route === '/api/gallery' && req.method === 'GET') {
    const offset = Number(url.searchParams.get('offset') || 0), limit = Number(url.searchParams.get('limit') || 24);
    if (!Number.isSafeInteger(offset) || offset < 0 || !Number.isSafeInteger(limit) || limit < 1 || limit > 60) {
      return sendJson(res, 400, {error:'Use a nonnegative offset and a limit from 1 to 60.'});
    }
    return sendJson(res, 200, galleryPage(offset, limit));
  }
  const shot = route.match(/^\/shot\/([a-z0-9._ -]+)$/);
  if (shot && req.method === 'GET') {
    const ok = jsonFile(GALLERY, [])
      .some((g) => String(g.name).toLowerCase() === shot[1]);
    const file = path.join(UP, shot[1]);
    if (!ok || !file.startsWith(UP + path.sep) || !fs.existsSync(file)) {
      return send(res, 404, 'no such picture', 'text/plain');
    }
    const st = fs.statSync(file);
    const shotKind = {
      'content-type': KIND[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'cache-control': 'public, max-age=86400',
      'x-content-type-options': 'nosniff'
    };
    // Byte range when asked: a recording will not play in Safari/iOS without it,
    // the same reason public/ and /file already call rangeReply.
    if (rangeReply(req, res, file, st.size, shotKind, head)) return;
    res.writeHead(200, Object.assign({}, shotKind, {
      'content-length': st.size,
      'accept-ranges': 'bytes'
    }));
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
    if (/\.map$/i.test(p)) return send(res, 404, 'not here', 'text/plain');
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

  // --------------------------------------------------------------- ship feed
  // Anonymous version.json and content-addressed packs for the launcher.
  // Live at /feed/, preclear at /feed-dev/. Assets are named by lowercase
  // sha256 only so a path cannot walk outside the folder. #649.
  const feedVer = p.match(/^\/(feed(?:-dev)?)\/version\.json$/);
  if (feedVer && req.method === 'GET') {
    const dir = path.join(ROOT, feedVer[1]);
    const file = path.join(dir, 'version.json');
    if (!file.startsWith(dir + path.sep) || !fs.existsSync(file)) {
      return send(res, 404, 'no such file', 'text/plain');
    }
    /*
      AN ETAG, AND 304 FOR A LAUNCHER THAT ALREADY HAS THIS ONE. #445.

      Every launcher asks for this file every thirty seconds while somebody is
      in a session, because the countdown that closes the game for an update
      has to land inside the server's five minute window. The document is about
      ninety kilobytes and only changes when somebody ships, so nearly ten
      megabytes an hour per launcher was the same bytes over again.

      no-cache stays as it is. It means "ask before reusing this", not "do not
      keep it", which is exactly what a feed wants: the launcher still asks
      every thirty seconds and hears about a release straight away, and the
      answer is a few bytes when nothing has moved.

      The tag is size and modified time, the same shape the static and asset
      branches use, so whatever writes a new version.json changes it.
    */
    const vst = fs.statSync(file);
    const vtag = '"' + vst.size.toString(16) + '-' + Math.floor(vst.mtimeMs).toString(16) + '"';
    if (String(req.headers['if-none-match'] || '') === vtag) {
      res.writeHead(304, {
        'etag': vtag,
        'cache-control': 'no-cache',
        'x-content-type-options': 'nosniff'
      });
      return res.end();
    }
    return send(res, 200, fs.readFileSync(file), 'application/json; charset=utf-8',
      { 'Cache-Control': 'no-cache', 'ETag': vtag });
  }

  const feedAsset = p.match(/^\/(feed(?:-dev)?)\/assets\/([0-9a-f]{64})$/);
  if (feedAsset && req.method === 'GET') {
    const dir = path.join(ROOT, feedAsset[1], 'assets');
    const file = path.join(dir, feedAsset[2]);
    if (!file.startsWith(dir + path.sep) || !fs.existsSync(file)) {
      return send(res, 404, 'no such file', 'text/plain');
    }
    const st = fs.statSync(file);
    /* Same Range resume as /file/: packs are tens of megabytes and a drop
       must carry on. Cache-Control is long and immutable because the name
       is the bytes; a new pack is a new name. */
    const kind = {
      'content-type': 'application/octet-stream',
      'etag': '"' + st.size.toString(16) + '-' + Math.floor(st.mtimeMs).toString(16) + '"',
      'last-modified': new Date(st.mtimeMs).toUTCString(),
      'cache-control': 'public, max-age=31536000, immutable'
    };
    if (rangeReply(req, res, file, st.size, kind, head)) return;
    res.writeHead(200, Object.assign({}, kind, {
      'content-length': st.size,
      'accept-ranges': 'bytes',
      'x-content-type-options': 'nosniff'
    }));
    if (head) return res.end();
    return fs.createReadStream(file).pipe(res);
  }
  // --------------------------------------------------------------- uploads
  /*
    The files themselves. The hub member cookie is the door for all of them, as
    it always was, with one opening: a picture still waiting in the gallery
    queue is read by staff as well (#755).

    The queue page, /uploads, opens for the access.dev roles and its doors take
    the hub cookie or a launcher ticket (#742, #743). The picture beside each
    row in that queue is this address, and it asked w.member, so a Loremaster,
    Gamemaster or Moderator was shown a page of broken pictures and asked to
    decide on shots they could not see. The launcher has no cookie to offer at
    all, so it could not show one either.

    A name on gallery-pending.json therefore goes through galleryStaff, the one
    gate the six staff doors already share, rather than a second check written
    here that would drift from them: st.dev, so being allowed into the game
    (st.play) is not enough. Everything else in uploads is the member cookie
    exactly as before, and an approved shot leaves the queue and is public at
    /shot, so this opening is only what is waiting on a decision.
  */
  const up = p.match(/^\/up\/([A-Za-z0-9._ -]+)$/);
  if (up && req.method === 'GET') {
    if (!w.member) {
      // Nobody who has offered neither a staff cookie nor a ticket is told
      // anything new: they get the 'sign in first' every other name gets,
      // whether that name is in the queue or not.
      const staffAsking = w.dev || url.searchParams.get('ticket');
      const waiting = staffAsking &&
        jsonFile(GPENDING, []).some((x) => String(x.name) === up[1]);
      const gs = waiting ? await galleryStaff(url, w) : null;
      if (!gs) return send(res, 401, 'sign in first', 'text/plain');
      if (!gs.ok) {
        return send(res, gs.code,
                    String((gs.body && gs.body.error) || 'staff only'), 'text/plain');
      }
    }
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
    const asked = (url.searchParams.get('name') || 'file').split(/[\\/]/).pop();
    return receiveUpload(req, res, asked, 200 * 1024 * 1024, null, (name) => {
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

  // ------------------------------------------------------------- gallery --
  /*
    Somebody sends a picture in, staff decide whether it goes on the public
    gallery. Two doors in: a signed-in Discord account that may play (or the
    hub member cookie), or the launcher with the same signed Discord ticket it
    uses at /api/play/join, so a person can send a shot from the game without
    a site sign in.

    The staff side takes the same two, through galleryStaff, and asks st.dev of
    the ticket rather than st.play (#743).

    The body IS the file, the /api/upload way, so the ticket and the note ride in
    the query, not in the body. The file lands in uploads/ under a stamped name
    through the shared helper, exactly as an /api/upload file does, and an entry
    goes on gallery-pending.json. Nothing here touches gallery.json: a submission
    is not public until an admin approves it, and /api/public and /shot read only
    gallery.json, so a pending shot is not reachable by either.

    The site may send several pictures from one form (multi-select or drop). Each
    file is still one POST to this door, body = the file, so the launcher ticket
    path and the single-file path stay the same. A short queue serialises the
    pending.json write so two rapid submits cannot drop an entry.
  */
  if (p === '/api/gallery/submit' && req.method === 'POST') {
    // Who is asking. A hub member, or a launcher ticket verified the way the
    // door verifies it: read it, ask Discord for the standing, and hold it to
    // the same answers /api/play/join gives, so a banned or departed account
    // cannot put a picture in the queue.
    let from = '', discordId = '';
    // A signed-in Discord account that may play, or the hub member cookie
    // (password bootstrap / staff). Hub "member" alone used to be the only
    // web door, and with Discord live that meant only admins could submit
    // from the site. Play-capable signed-in people submit too.
    if (w.play || w.member) {
      from = 'web';
      discordId = w.id || '';
    } else {
      const t = readTicket(url.searchParams.get('ticket'));
      // Signed in, and Discord did not answer in time (#467): say that.
      if (!t && w.id && w.lookupFailed) return sendJson(res, 503, { ok: false, why: 'could not ask Discord', error:
        'Thornswood could not ask Discord about your account just now. Try again in a minute.' });
      if (!t) return sendJson(res, 401, { ok: false, why: 'link', error:
        'Sign in to the hub, or send a valid launcher ticket.' });
      const st = await within(standing(t.d), PLAY_ANSWER_MS, () => standingLate(t.d));
      standCache.delete(String(t.d));
      if (st.lookupFailed && !st.admin) return sendJson(res, 503, discordUnasked());
      // Banned before the guild check (#1022). standing() leaves inGuild false
      // when bans.json already refused the account.
      if (st.banned) return sendJson(res, 403, { ok: false, why: 'banned', error:
        'That Discord account is banned from Thornswood.' });
      if (!st.inGuild) return sendJson(res, 403, { ok: false, why: 'guild', error:
        'That Discord account is not in the Thornswood Discord.' });
      if (!st.play) return sendJson(res, 403, { ok: false, why: 'role', error:
        'That Discord account has no role that lets it in yet.' });
      from = 'launcher';
      discordId = String(t.d);
    }

    const asked = (url.searchParams.get('name') || 'shot.png').split(/[\\/]/).pop();
    const by = (url.searchParams.get('by') || '').slice(0, 40);
    const note = (url.searchParams.get('note') || '').slice(0, 300);
    return receiveUpload(req, res, asked, GALLERY_CAP, GALLERY_ALLOW, (name) => {
      // The uploads.json note too, so this shot reads the same as any other
      // file in the uploads listing (the orig name, who by, the note).
      const meta = jsonFile(UPMETA, {});
      meta[name] = { orig: asked, by: by, note: note, at: Date.now() };
      putJson(UPMETA, meta);

      withGalleryPending(() => {
        const pending = jsonFile(GPENDING, []);
        const entry = { name: name, by: by, note: note, at: Date.now(), from: from };
        if (discordId) entry.discordId = discordId;
        pending.push(entry);
        putJson(GPENDING, pending);
        sendJson(res, 200, { ok: true, name: name });
      });
    });
  }

  // The queue, for staff (access.dev) to look through. Never public, so it is
  // its own door rather than a field on /api/public. galleryStaff takes the hub
  // cookie or a launcher ticket for a staff account; everything below it does
  // the same, so the six staff doors have one gate between them.
  if (p === '/api/gallery/pending' && req.method === 'GET') {
    const gs = await galleryStaff(url, w);
    if (!gs.ok) return sendJson(res, gs.code, gs.body);
    return sendJson(res, 200, { pending: jsonFile(GPENDING, []) });
  }

  // Approve: take it off the queue and put it on the public list. Idempotent,
  // so approving the same name twice is a 200 that changed nothing the second
  // time, and a name already on the gallery is left where it is.
  if (p === '/api/gallery/approve' && req.method === 'POST') {
    const gs = await galleryStaff(url, w);
    if (!gs.ok) return sendJson(res, gs.code, gs.body);
    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { passBodyFailure(e); }
    const name = String(o.name || '');
    if (!name) return sendJson(res, 400, { error: 'no name' });

    const pending = jsonFile(GPENDING, []);
    const hit = pending.find((x) => String(x.name) === name);
    // "by" from the call wins, then the pending entry's, then empty. The url is
    // built here so gallery.json holds exactly the shape /api/public hands out.
    const by = (o.by !== undefined && o.by !== null) ? String(o.by).slice(0, 40)
             : (hit ? String(hit.by || '') : '');

    const gallery = jsonFile(GALLERY, []);
    const already = gallery.find((g) => String(g.name) === name);
    if (already) {
      already.url = '/shot/' + name;
      if (by) already.by = by;
    } else {
      gallery.push({ name: name, url: '/shot/' + name, by: by });
    }
    putJson(GALLERY, gallery);

    const left = pending.filter((x) => String(x.name) !== name);
    if (left.length !== pending.length) putJson(GPENDING, left);
    return sendJson(res, 200, { ok: true, name: name, approved: true });
  }


  // Who may submit or moderate on the public gallery page. Always 200: the
  // page needs to know whether to show Sign in, Submit, or the staff tools
  // without treating a play-capable signed-in person as signed out the way
  // /api/hello does for the hub.
  /* Answered inside SUBMIT_WAIT_MS with Discord slow or silent (#1096), like
     any page load. asked is false when Discord could not be asked and there
     was no earlier answer to use, so a page says that rather than offering a
     sign in to somebody who is signed in. personWhy is what the report page
     shows under "about a person": /api/report's own words (#1097). */
  if (p === '/api/gallery/who' && req.method === 'GET') {
    const no = personReportRefusal(w);
    return sendJson(res, 200, {
      signed: !!(w.id || w.member),
      canSubmit: !!(w.play || w.member),
      staff: !!w.dev,
      admin: !!w.admin,
      name: w.name || '',
      asked: !(w.id && w.lookupFailed),
      personWhy: no ? no.why : '',
      personSays: no ? no.error : ''
    });
  }

  // Delete: take a shot off the public gallery and/or the pending queue.
  // Staff only (access.dev). Pending items that staff do not want go this
  // way; there is no separate Reject door. Same deleteFile option as before.
  if (p === '/api/gallery/approved' && req.method === 'DELETE') {
    const gs = await galleryStaff(url, w);
    if (!gs.ok) return sendJson(res, gs.code, gs.body);
    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { passBodyFailure(e); }
    const name = String(o.name || '');
    if (!name) return sendJson(res, 400, { error: 'no name' });

    const gallery = jsonFile(GALLERY, []);
    const leftGal = gallery.filter((x) => String(x.name) !== name);
    const removedGal = gallery.length - leftGal.length;
    if (removedGal) putJson(GALLERY, leftGal);

    const pending = jsonFile(GPENDING, []);
    const leftPend = pending.filter((x) => String(x.name) !== name);
    const removedPend = pending.length - leftPend.length;
    if (removedPend) putJson(GPENDING, leftPend);

    // Drop open reports against this name too, so the reports list does not
    // keep asking about a picture that is already gone.
    const reports = jsonFile(GREPORTS, []);
    const kept = reports.filter((r) => String(r.name) !== name);
    if (kept.length !== reports.length) putJson(GREPORTS, kept);

    if (o.deleteFile) {
      const file = path.join(UP, name);
      if (file.startsWith(UP + path.sep)) {
        try { fs.unlinkSync(file); } catch (e) { }
        const meta = jsonFile(UPMETA, {});
        delete meta[name];
        putJson(UPMETA, meta);
      }
    }
    return sendJson(res, 200, {
      ok: true,
      name: name,
      removed: removedGal + removedPend,
      removedApproved: removedGal,
      removedPending: removedPend
    });
  }

  // Report an approved shot. Any signed-in play-capable member, or the
  // launcher with the same ticket /api/gallery/submit takes. The report sits
  // in gallery-reports.json for staff; it does not take the shot down.
  if (p === '/api/gallery/report' && req.method === 'POST') {
    let from = '', discordId = '';
    if (w.play || w.member) {
      from = 'web';
      discordId = w.id || '';
    } else {
      const t = readTicket(url.searchParams.get('ticket'));
      // Signed in, and Discord did not answer in time (#467): say that.
      if (!t && w.id && w.lookupFailed) return sendJson(res, 503, { ok: false, why: 'could not ask Discord', error:
        'Thornswood could not ask Discord about your account just now. Try again in a minute.' });
      if (!t) return sendJson(res, 401, { ok: false, why: 'link', error:
        'Sign in, or send a valid launcher ticket.' });
      const st = await within(standing(t.d), PLAY_ANSWER_MS, () => standingLate(t.d));
      standCache.delete(String(t.d));
      if (st.lookupFailed && !st.admin) return sendJson(res, 503, discordUnasked());
      // Same order as submit (#1022): a file ban is not "not in the Discord".
      if (st.banned) return sendJson(res, 403, { ok: false, why: 'banned', error:
        'That Discord account is banned from Thornswood.' });
      if (!st.inGuild) return sendJson(res, 403, { ok: false, why: 'guild', error:
        'That Discord account is not in the Thornswood Discord.' });
      if (!st.play) return sendJson(res, 403, { ok: false, why: 'role', error:
        'That Discord account has no role that lets it in yet.' });
      from = 'launcher';
      discordId = String(t.d);
    }

    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { passBodyFailure(e); }
    const name = String(o.name || '');
    if (!name) return sendJson(res, 400, { error: 'no name' });
    const why = String(o.why || '').slice(0, 500);

    const gallery = jsonFile(GALLERY, []);
    if (!gallery.find((g) => String(g.name) === name)) {
      return sendJson(res, 404, { error: 'not on the gallery' });
    }

    const reports = jsonFile(GREPORTS, []);
    const id = crypto.randomBytes(8).toString('hex');
    const entry = { id: id, name: name, why: why, at: Date.now(), from: from };
    if (discordId) entry.discordId = discordId;
    reports.push(entry);
    // Keep the newest 500 so a flood cannot grow the file forever.
    putJson(GREPORTS, reports.slice(-500));
    return sendJson(res, 200, { ok: true, id: id });
  }

  if (p === '/api/gallery/reports' && req.method === 'GET') {
    const gs = await galleryStaff(url, w);
    if (!gs.ok) return sendJson(res, gs.code, gs.body);
    return sendJson(res, 200, { reports: jsonFile(GREPORTS, []) });
  }

  if (p === '/api/gallery/report/dismiss' && req.method === 'POST') {
    const gs = await galleryStaff(url, w);
    if (!gs.ok) return sendJson(res, gs.code, gs.body);
    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { passBodyFailure(e); }
    const id = String(o.id || '');
    if (!id) return sendJson(res, 400, { error: 'no id' });
    const reports = jsonFile(GREPORTS, []);
    const left = reports.filter((r) => String(r.id) !== id);
    putJson(GREPORTS, left);
    return sendJson(res, 200, { ok: true, id: id, removed: reports.length - left.length });
  }


  // -------------------------------------------------------------- the door
  /*
    What the launcher talks to. The person links Discord once, the launcher
    keeps a signed ticket, and every launch it asks here whether that ticket is
    still somebody who is allowed in. The answer used to carry the server
    password as well, so the password stopped being a thing written in
    version.json for anybody who has ever installed the game to keep forever.
    It has not carried one since 18 September, when the site stopped reading
    the password at all: a yes now says who the account is and what it may
    do, and nothing more.

    Every call re-asks Discord. Leaving the server, or being handed the Banned
    role, stops the next launch working, with nothing to remember to do.
  */
  if (p === '/api/play/join' && req.method === 'POST') {
    const by = Date.now() + PLAY_ANSWER_MS;
    let o = {};
    try { o = JSON.parse(await body(req, 8192, PLAY_BODY_MS)) || {}; } catch (e) { passBodyFailure(e); }
    const t = readTicket(o.ticket);
    if (!t) return sendJson(res, 401, { ok:false, why:'link', message:
      'This copy is not linked to a Discord account yet.' });

    const st = await within(standing(t.d), by - Date.now(), () => standingLate(t.d));
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
    if (st.lookupFailed && !st.admin) return sendJson(res, 503, discordUnasked());
    // Banned before the guild (#1010): a staff ban answers from the file and
    // says nothing about the guild, so asked the other way round a banned
    // account was told it was not in the Discord.
    if (st.banned) return sendJson(res, 403, { ok:false, why:'banned', message: accountBanned(st) });
    if (!st.inGuild) return sendJson(res, 403, { ok:false, why:'guild', message:
      'That Discord account is not in the Thornswood Discord.',
      invite: cfg.discord.invite || '' });
    if (!st.play) return sendJson(res, 403, { ok:false, why:'role', message:
      notAcceptedYet(),
      invite: cfg.discord.invite || '' });
    // The dev build checks in as channel dev. It is for the roles in
    // access.dev (the staff roles by default, Patrick 27 Sep #605, unless
    // config.json says otherwise); anyone else is sent back to the main build
    // with a plain reason.
    const wantsDev = String(o.channel || '') === 'dev';
    if (wantsDev && !st.dev) return sendJson(res, 403, { ok:false, why:'dev', dev: false, message:
      'The dev build is for the ' + andList(cfg.access.dev) + ' roles. Play on the main build.' });
    /*
      The world is full (#481). Not a no any more: Patrick, 29 Sep, a full
      world lets people into the game's menu to wait in line. The yes below
      carries wait and a sentence saying so, and the launcher logs it on the
      Play page. A Discord staff role is not told: the gamemode gives them a
      staff seat ahead of the line. The dev build is staff only.
    */
    const wait = !wantsDev && seatsFull(gameStatus) && !st.staffRole;

    // The launcher sends the profile id it is about to play as. The game
    // server never sees a Discord account, only this number, so this is the
    // one place the two get tied together, and /api/allowed hands the numbers
    // back to the server's door. A person has a couple of character slots, so
    // it is a short list rather than one value.
    const pid = Number(o.profileId) || 0;
    // Which accounts holding this id have left the Discord, asked off a copy
    // of the file before the one written back is read. Nothing may wait
    // between that read and putJson below; departed() says why.
    const left = await departed(jsonFile(LINKED, {}), pid, t.d, by);
    const linked = jsonFile(LINKED, {});
    const was = linked[t.d] || {};
    const profiles = Array.isArray(was.profiles) ? was.profiles.slice() : [];
    /*
      A number already against somebody else's Discord account is theirs, and
      this used to write it against the caller's account anyway.

      Found reading the code for To Do List entry 142, identity on the game
      server being a number the client picks. voice-server.js sends every
      profile id to every voice peer five times a second, so any account with
      the play role could learn somebody's id, check in with it here, and
      from then on /api/play/owns below answered "theirs" and the voice
      service minted a proven token for it. /owns already refuses somebody
      else's number; this is the same loop, run before anything is written.

      The caller's own list is read first, the way /owns reads it, so a
      person checking in again with an id they already hold is always
      claimed, even if an older file also has that id against a second
      account. An id nobody holds still belongs to whoever checks in with it
      first, which is the launcher that just made the character.

      Not written, and NOT refused. The first cut of this answered 409, and
      that locked out a tester who had done nothing wrong. The launcher's
      character list is kept per install, not per Discord account, and the
      door check (Door.Check, before Chars.Prepare) sends the id played last.
      So an install that had played under one account and was then linked to
      another with the launcher's own Unlink and Connect Discord (a second
      person on a shared PC, an alt, somebody who changed accounts) got a 409
      on every Play, a warning box, and no game, with no way to reach New
      character at the menu. Refusing protected nothing either: the yes below
      carries no password, and nothing in it is about the character, only
      about the account that asked. What needed protecting is linked.json,
      and leaving the id off the caller's list is the whole of that. The
      caller is still stamped as seen, because they did check in. claimed
      false says the id was left off, for whoever wants to read it.

      Such an install's spare, the id the menu's New character uses, was
      checked in under the first account too, and this route cannot tell it
      from an id somebody took. So the launcher mints the relinked account a
      fresh spare before it checks anything in (Chars.EnsureSpare), and the
      new character is filed under the account that made it.

      WHAT THIS COSTS SOMEBODY WHO CHANGED ACCOUNTS, which is new with this
      rule and not something main did. Measured by a reviewer on 24 September
      running this route, /owns and /api/allowed from main and from here: an
      install with characters 700 and 701 made under A, relinked to B. On main
      B took both at its first Play. Here they stay A's. While A is in the
      Discord the game's door still lets them in on A's standing, but /owns
      calls them somebody else's, so the voice service refuses B a token on
      either. Whether that is the right price for stopping id theft is
      Patrick's to decide; an admin action that moves an id between accounts
      is the other half of it and is not built.
      What is not a price worth paying is the rest of what the reviewer
      found: once A left the Discord, /api/allowed dropped 700 and 701 and
      the door turned B away from both, with a hand edit of linked.json on the
      VPS the only way back. So an id held only by accounts that have left the
      Discord, and are not banned (hasLeft), is free: it is taken off them and
      claimed by whoever checks in with it, which for that install is B at its
      next Play.
    */
    let claimed = pid > 0 && profiles.map(Number).indexOf(pid) >= 0;
    /*
      An id the caller already holds goes to the end of their list, so the
      eight kept below are the eight checked in most recently.

      Found reviewing this route for entry 142 on 24 September. The list was
      kept in the order ids first arrived and cut to its last eight, and an id
      already on it never moved. Every Play checks the characters in before
      the spare, and a relinked install mints a new spare each time it goes
      back to an account, so that account's list grew by one spare per switch
      while its characters sat at the front. On the ninth id its oldest
      character fell off, and the other account's next Play checked it in
      with nobody holding it and claimed it for good, which is the same harm
      the holder rule below exists to stop. Measured with test-play-join.js:
      one character, A to B to A each round, off A's list after round seven
      and B's from round eight. Moved to the end, an install's own ids are
      always the newest, and a spare the launcher retired is what drops off.
    */
    if (claimed) {
      for (let i = profiles.length - 1; i >= 0; i--) {
        if (Number(profiles[i]) === pid) profiles.splice(i, 1);
      }
      profiles.push(pid);
    }
    if (pid > 0 && !claimed) {
      let holder = '';
      const gone = [];
      for (const d of Object.keys(linked)) {
        if (String(d) === String(t.d)) continue;
        const theirs = (linked[d] && Array.isArray(linked[d].profiles))
          ? linked[d].profiles.map(Number) : [];
        if (theirs.indexOf(pid) < 0) continue;
        // An account that holds it and was not asked about above (it took the
        // id since) counts as still holding it, which is the safe side.
        if (left.has(String(d))) { gone.push(String(d)); continue; }
        holder = d;
        break;
      }
      if (holder) {
        console.log('[thornswood-docs] join kept profile ' + pid + ' off Discord ' + t.d +
                    ': it is held by Discord ' + holder);
      } else {
        // Off the accounts that have left, so one id has one holder and the
        // rule above keeps working for the account that has it now.
        for (const d of gone) {
          linked[d].profiles = linked[d].profiles.filter((n) => Number(n) !== pid);
          console.log('[thornswood-docs] join moved profile ' + pid + ' to Discord ' + t.d +
                      ' from Discord ' + d + ', which has left the Thornswood Discord');
        }
        profiles.push(pid);
        claimed = true;
      }
    }
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
      avatar: st.avatar || '',
      admin: st.admin,
      dev: !!st.dev,
      roles: st.roles,
      slots: slotsFor(st),
      // Whether the profile id sent is now against this account. False when
      // none was sent, and when another account already holds it, in which
      // case it was left off this one and the door still said yes.
      claimed: claimed,
      // The world is full: in, but there may be a wait at the menu (#481).
      wait: wait,
      message: wait ? worldFull(gameStatus.max || mostOnlineFallback()) : '',
      online: gameStatus.online,
      max: gameStatus.max || mostOnlineFallback(),
      line: gameStatus.line
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
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { passBodyFailure(e); }
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
    try { o = JSON.parse(await body(req, SLOG_ALL + 64 * 1024)) || {}; } catch (e) { passBodyFailure(e); }
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

      /* The server's half of this session, the same window the View more
         button reads, for what the server said about this person's load
         order (#945). */
      const row = rows[at];
      const from = (Number(row.start) || Number(row.end) || 0) - 60000;
      const to = (Number(row.end) || Date.now()) + 60000;
      const server = serverLogSlice(row.channel, from, to);

      const found = readTrouble(logs, server.lines, row.profile);
      applyTrouble(row, found);
      row.troubleRules = TROUBLE_RULES;

      putSessions(rows);
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
  // The dev server's door.json names the site as https://thornswood.net/dev,
  // so its roster lands on /dev/api/roster (#955). Until that route was here
  // the dev server's pushes had no door to come in by.
  if ((route === '/api/roster' || route === '/dev/api/roster') && req.method === 'POST') {
    if (!cfg.botKey) return sendJson(res, 404, { error: 'not set up' });
    let o = {};
    try { o = JSON.parse(await body(req, 4 * 1024 * 1024)) || {}; } catch (e) { passBodyFailure(e); }
    if (!sameSecret(String(o.key || ''), String(cfg.botKey))) return sendJson(res, 401, { error: 'no' });
    const who = (o.who && typeof o.who === 'object') ? o.who : {};
    const store = jsonFile(ROSTER, { who: {} });
    if (!store.who || typeof store.who !== 'object') store.who = {};
    // Which of the profiles it looked at that server holds a character for,
    // kept per server (#955). /api/play/roster reads it back as "gone".
    if (Array.isArray(o.checked) && Array.isArray(o.held)) {
      const srv = (String(o.server || '') === 'dev' || route.indexOf('/dev/') === 0) ? 'dev' : 'main';
      const ints = (a) => a.map(Number).filter((x) => x > 0 && Number.isInteger(x)).slice(0, 100000);
      if (!store.servers || typeof store.servers !== 'object') store.servers = {};
      store.servers[srv] = { at: Date.now(), checked: ints(o.checked), held: ints(o.held) };
    }
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
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { passBodyFailure(e); }
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
    /* This account's characters that the asking launcher's server looked up
       and does not hold (#955), from its last report if that is recent. The
       launcher marks them on the menu; it trusts the answer only for a
       character last played before goneAt. */
    const srv = String(o.channel || '') === 'dev' ? 'dev' : 'main';
    const rep = store.servers && store.servers[srv];
    let gone = [], goneAt = 0;
    if (rep && Array.isArray(rep.checked) && Array.isArray(rep.held) &&
        Date.now() - (Number(rep.at) || 0) < ROSTER_HELD_FRESH_MS) {
      const looked = new Set(rep.checked.map(Number));
      const held = new Set(rep.held.map(Number));
      gone = mine.filter((pid) => looked.has(pid) && !held.has(pid));
      goneAt = Number(rep.at) || 0;
    }
    /* This account's characters staff have killed for good, and the ones
       under a ban of their own (#1010). The launcher's menu shows a dead one
       in no slot, so the account can make a new character, and neither can
       be picked. Only the ids: why and who are staff's. */
    const now = Date.now();
    const pk = [], barred = [];
    for (const pid of mine) {
      const bar = characterBar(pid, now);
      if (bar && bar.pk) pk.push(pid);
      else if (bar) barred.push(pid);
    }
    /* And the ones an admin brought back from a PK (#1010), so the launcher
       puts a character it had moved out of its slots back into a free one. */
    const pkRows = jsonFile(PK, {}) || {};
    const revived = mine.filter((pid) => pkRows[String(pid)] && !pkActive(pkRows[String(pid)]));
    return sendJson(res, 200, { ok: true, rows, gone, goneAt, pk, banned: barred, revived });
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
    // The key comes in the X-Thornswood-Key header. In the address it was
    // written down by anything that logs a request line, this site's own
    // failed() included. Entry 248. The address form stays for one release,
    // for a game server still running a gamemode from before 24 September,
    // and only when there is no header at all; keyInAddress says when a door
    // still uses it.
    const inHeader = req.headers['x-thornswood-key'];
    const given = inHeader !== undefined ? inHeader : (url.searchParams.get('key') || '');
    if (!sameSecret(String(given), String(cfg.botKey))) {
      return sendJson(res, 401, { error: 'no' });
    }
    if (inHeader === undefined && !keyInAddress.has(route)) {
      keyInAddress.add(route);
      console.log('[thornswood-docs] ' + route + ' answered a door that sent its key in ' +
                  'the address, so that game server runs a gamemode from before 24 ' +
                  'September. The address form goes once no door says this.');
    }
    const linked = jsonFile(LINKED, {});
    const out = { profiles: [], devProfiles: [], adminProfiles: [], jarlProfiles: [], staffRoleProfiles: [], businessOwnerProfiles: [], factionOwnerProfiles: [], devRoleProfiles: [], companyProfiles: [], people: [], lookupFailed: false, lookupFailedWhy: '', failedProfiles: [], at: Date.now() };
    const seen = new Set();
    const seenDev = new Set();
    const seenAdmin = new Set();
    const seenJarl = new Set();
    const seenStaffRole = new Set();
    const seenBusiness = new Set();
    const seenFaction = new Set();
    const seenDevRole = new Set();
    const seenCompany = new Set();
    const seenFailed = new Set();
    const hasProfiles = (d) => (Array.isArray((linked[d] || {}).profiles) ? linked[d].profiles : [])
      .map(Number).some((n) => n > 0);
    const answers = await standingsForDoor(Object.keys(linked).filter(hasProfiles));
    for (const d of Object.keys(linked)) {
      const row = linked[d] || {};
      const profiles = (Array.isArray(row.profiles) ? row.profiles : [])
        .map(Number).filter((n) => n > 0);
      if (!profiles.length) continue;
      const st = answers.get(d) || { lookupFailed: 'not asked' };
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
      if (st.jarl) {
        for (const n of profiles) if (!seenJarl.has(n)) { seenJarl.add(n); out.jarlProfiles.push(n); }
      }
      // A Discord staff role itself, not the hand written admins list, for
      // the staff seats over the most the world holds (#481).
      if (st.staffRole) {
        for (const n of profiles) if (!seenStaffRole.has(n)) { seenStaffRole.add(n); out.staffRoleProfiles.push(n); }
      }
      if (st.businessOwner) {
        for (const n of profiles) if (!seenBusiness.has(n)) { seenBusiness.add(n); out.businessOwnerProfiles.push(n); }
      }
      if (st.factionOwner) {
        for (const n of profiles) if (!seenFaction.has(n)) { seenFaction.add(n); out.factionOwnerProfiles.push(n); }
      }
      if (st.devRole) {
        for (const n of profiles) if (!seenDevRole.has(n)) { seenDevRole.add(n); out.devRoleProfiles.push(n); }
      }
      // The trading company's role (#1393), for a company sale in the game.
      if (st.company) {
        for (const n of profiles) if (!seenCompany.has(n)) { seenCompany.add(n); out.companyProfiles.push(n); }
      }
      out.people.push({ id: String(d), name: st.name || row.name || '', profiles });
    }
    /* STAFF BANS (#412), which are this site's own file and need no Discord.
       Every profile under an active ban is left out of every list, including
       a profile no account holds and one Discord could not be asked about,
       and the bans go to the door with why and until, so the game server can
       end the session of anybody banned who is online and tell them both. */
    out.bans = activeBans(Date.now());
    /* And every character staff have killed for good (#1010), left out the
       same way and sent as pk, so the game server ends it quietly if it is
       in the world. */
    out.pk = pkProfiles();
    const barred = new Set(out.pk);
    for (const b of out.bans) for (const n of b.profiles) barred.add(Number(n));
    if (barred.size) {
      for (const k of ['profiles', 'devProfiles', 'adminProfiles', 'jarlProfiles', 'staffRoleProfiles', 'failedProfiles']) {
        out[k] = out[k].filter((n) => !barred.has(Number(n)));
      }
      for (const k of ['businessOwnerProfiles', 'factionOwnerProfiles', 'devRoleProfiles', 'companyProfiles']) {
        out[k] = out[k].filter((n) => !barred.has(Number(n)));
      }
      out.people = out.people.map((p) => Object.assign({}, p, { profiles: p.profiles.filter((n) => !barred.has(Number(n))) }))
        .filter((p) => p.profiles.length);
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
    worth refusing, unless that account has left the Discord without being
    banned: see hasLeft.
  */
  if (p === '/api/play/owns' && req.method === 'POST') {
    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { passBodyFailure(e); }
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

    // The same rule /api/play/join keeps: an account that has left the
    // Discord and is not banned (hasLeft) holds nothing, so somebody whose
    // old account has gone has voice on their characters before their next
    // Play moves the ids across.
    const left = await departed(linked, pid, t.d);
    let gone = false;
    for (const d of Object.keys(linked)) {
      if (String(d) === String(t.d)) continue;
      const theirs = (linked[d] && Array.isArray(linked[d].profiles))
        ? linked[d].profiles.map(Number) : [];
      if (theirs.indexOf(pid) < 0) continue;
      if (left.has(String(d))) { gone = true; continue; }
      return sendJson(res, 200, { ok: false, why: 'somebody else' });
    }
    if (gone) return sendJson(res, 200, { ok: true, why: 'left' });
    // Nobody has it. The launcher that just made the character is the one
    // asking, and it checks in with this number a moment later anyway.
    return sendJson(res, 200, { ok: true, why: 'unclaimed' });
  }

  /*
    A join pass for one character (#937; the format is over makePass).

    The launcher asks when a character is picked at the game's menu and again
    every four minutes while the game runs. Every no names what to do, because
    the launcher shows the message as it stands.

    REFUSED, NOT GUESSED, whenever this cannot be sure: no key, a feed it cannot
    read, a launcher version that is not a version, or Discord not answering
    (the hand written admin list aside, as at /api/play/join). A refusal here
    means that session is ended by the game server, which is the point.

    THE VERSION IS THE LAUNCHER'S OWN WORD, checked against the channel's feed
    both ways: below minLauncher is an old launcher and is told to update, and
    above launcherVersion is a number Thornswood never published. So an old
    launcher cannot get in, and neither can a request that simply claims to be a
    new one. A person who writes their own request with their own ticket gets a
    pass only for their own characters, which is all the game server lets it
    prove.

    WHOSE CHARACTER, the rule /api/play/owns keeps: the caller's own, one that
    nobody holds yet (the launcher checks every id in at Play), or one held only
    by an account that has left the Discord. Somebody else's is refused.
  */
  if (p === '/api/play/pass' && req.method === 'POST') {
    const by = Date.now() + PLAY_ANSWER_MS;
    let o = {};
    try { o = JSON.parse(await body(req, 8192, PLAY_BODY_MS)) || {}; } catch (e) { passBodyFailure(e); }
    const t = readTicket(o.ticket);
    if (!t) return sendJson(res, 401, { ok: false, why: 'link', message:
      'This copy is not linked to a Discord account yet.' });
    const pid = Number(o.profileId) || 0;
    if (!(pid > 0) || Math.floor(pid) !== pid) return sendJson(res, 400, { ok: false, why: 'profile', message:
      'No character was named.' });
    const server = String(o.channel || '') === 'dev' ? 'dev' : 'main';
    if (!cfg.passKey) return sendJson(res, 503, { ok: false, why: 'no key', message:
      'Thornswood cannot let anybody into the game right now. Tell Patrick.' });

    const feed = feedLaunchers(server);
    if (!feed) return sendJson(res, 503, { ok: false, why: 'feed', message:
      'Thornswood could not read its own update feed just now. Try again in a minute.' });
    const said = String(o.version == null ? '' : o.version).trim().slice(0, 40);
    const have = versionParts(said);
    if (!have || versionCompare(have, versionParts(feed.min)) < 0) {
      return sendJson(res, 403, { ok: false, why: 'update', need: feed.min, message:
        'This launcher is ' + (said || 'too old to say') + ' and Thornswood needs ' + feed.min +
        ' or newer. Update the launcher, then press Play again.' });
    }
    if (versionCompare(have, versionParts(feed.current)) > 0) {
      return sendJson(res, 403, { ok: false, why: 'unknown launcher', need: feed.current, message:
        'This launcher says it is ' + said + ', which Thornswood never published. ' +
        'Install the launcher from thornswood.net, then press Play again.' });
    }

    const st = await within(standingCached(t.d), by - Date.now(), () => standingLate(t.d));
    if (st.lookupFailed && !st.admin) return sendJson(res, 503, discordUnasked());
    // Banned before the guild, as at /api/play/join (#1010).
    if (st.banned) return sendJson(res, 403, { ok: false, why: 'banned', message: accountBanned(st) });
    if (!st.inGuild) return sendJson(res, 403, { ok: false, why: 'guild', message:
      'That Discord account is not in the Thornswood Discord.' });
    if (!st.play) return sendJson(res, 403, { ok: false, why: 'role', message:
      notAcceptedYet() });
    if (server === 'dev' && !st.dev) return sendJson(res, 403, { ok: false, why: 'dev', message:
      'The dev build is for the ' + andList(cfg.access.dev) + ' roles. Play on the main build.' });

    const linked = jsonFile(LINKED, {});
    const mine = (linked[t.d] && Array.isArray(linked[t.d].profiles))
      ? linked[t.d].profiles.map(Number) : [];
    if (mine.indexOf(pid) < 0) {
      const left = await departed(linked, pid, t.d, by);
      for (const d of Object.keys(linked)) {
        if (String(d) === String(t.d)) continue;
        const theirs = (linked[d] && Array.isArray(linked[d].profiles))
          ? linked[d].profiles.map(Number) : [];
        if (theirs.indexOf(pid) < 0 || left.has(String(d))) continue;
        console.log('[thornswood-docs] no join pass for profile ' + pid + ' to Discord ' + t.d +
                    ': it is held by Discord ' + d);
        return sendJson(res, 403, { ok: false, why: 'somebody else', message:
          'That character belongs to another Discord account.' });
      }
    }

    const now = Date.now();
    /* This one character (#1010): killed for good by staff, or banned by
       itself. The account is fine, so the answer says to pick another. */
    const bar = characterBar(pid, now);
    if (bar && bar.pk) return sendJson(res, 403, { ok: false, why: 'pk', message:
      'That character has died for good and cannot be played again. ' +
      'Pick another character at the menu, or make a new one.' });
    if (bar) return sendJson(res, 403, { ok: false, why: 'banned character', until: bar.until, message:
      'Staff have banned that character ' + banUntilText(bar.until) +
      (bar.why ? ': ' + bar.why : '') + '. Pick another character at the menu.' });
    const pass = makePass(cfg.passKey, { p: pid, s: server, v: said, d: String(t.d), i: now, x: now + PASS_MS });
    return sendJson(res, 200, { ok: true, pass: pass, until: now + PASS_MS, server: server });
  }

  // The same question without asking for the password, for the launcher to
  // show who it is linked as without pretending it is about to connect.
  if (p === '/api/play/who' && req.method === 'POST') {
    const by = Date.now() + PLAY_ANSWER_MS;
    let o = {};
    try { o = JSON.parse(await body(req, 8192)) || {}; } catch (e) { passBodyFailure(e); }
    const t = readTicket(o.ticket);
    if (!t) return sendJson(res, 401, { ok:false, why:'link' });
    const st = await within(standingCached(t.d), by - Date.now(), () => standingLate(t.d));
    if (st.lookupFailed && !st.admin) return sendJson(res, 503, discordUnasked());
    return sendJson(res, st.play && !st.banned ? 200 : 403, {
      ok: st.play && !st.banned, id: st.id, name: st.name || t.n,
      admin: st.admin, dev: !!st.dev, banned: st.banned, inGuild: st.inGuild, roles: st.roles
    });
  }

  // ------------------------------------------------------------------- api
  if (p.startsWith('/api/')) {
    // Staff as well as hub members, so the Gallery page can boot (#742). What
    // they get is still decided by LEVEL below: for staff who are not admins
    // that is the pages marked 'staff' and nothing else.
    // A staff POST from the hub already stopped waiting on Discord (#1164).
    // Not being staff because Discord did not answer is not 'sign in first'.
    if (req.method !== 'GET' && w.id && w.lookupFailed && !w.admin) return sendJson(res, 503, discordUnasked());
    if (!w.member && !w.dev) return sendJson(res, 401, { error: 'sign in first' });

    if (p === '/api/all' && req.method === 'GET') {
      const docs = {}, boards = {};
      for (const n of Object.keys(DOCS))   if (allowed(n, w)) docs[n]   = readDoc(n);
      const all = readBoard();
      const boardRevs = {};
      for (const n of Object.keys(BOARDS)) if (allowed(n, w)) { boards[n] = all[n] || { intro:'', sections:[] }; boardRevs[n] = boardRev(all, n); }
      return sendJson(res, 200, {
        me: w,
        titles: Object.assign({}, DOCS, BOARDS),
        level: LEVEL,
        docs, boards, boardRevs,
        // Member and admin material, held back from staff who are neither.
        // They are here for the Gallery page, which reads none of these: the
        // queue and the live list are their own doors.
        results: w.member ? jsonFile(RESULTS, {}) : {},
        files: w.member ? listFiles() : [],
        uploads: w.member ? listUploads() : [],
        news: jsonFile(NEWS, { launcher:'', news: [] }),
        invite: cfg.discord.invite || '',
        // The Linked accounts page is every staff role's since #1010 (Patrick,
        // 28 September: all staff can ban and PK, and the site's staff pages
        // can do it), so the accounts and the records go to staff (w.dev,
        // which folds admin in). Notes, bans and PKs are staff's to read and
        // nobody else's: a hub member without a staff role gets none.
        linked: w.dev ? Object.values(jsonFile(LINKED, {})) : [],
        records: w.dev ? staffRecords(Date.now()) : { bans: {}, notes: {}, pk: {}, names: {} },
        sessions: w.admin ? sessionRows() : [],
        inbox: w.admin ? jsonFile(INBOX, []) : []
      });
    }

    if (p === '/api/results' && req.method === 'PUT') {
      // A hub door, not a staff one: the gate above now lets staff in as far
      // as the pages LEVEL marks 'staff', and this writes the test marks.
      if (!w.member) return sendJson(res, 403, { error: 'hub members only' });
      let obj;
      try { obj = JSON.parse(await body(req)); }
      catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
      if (!putJson(RESULTS, obj)) return sendJson(res, 500, { error: 'could not save' });
      return sendJson(res, 200, { ok: true });
    }

    /*
      Bans and notes from the hub (#412), for staff (the access.dev roles).
      Keyed by Discord id, the rows the Linked accounts page lists. Staff only
      to read, because a note is staff's view of a person. What is done here
      goes to moderation.log for the bot to say in the staff channel; the
      game's /ban and /note are said from the game server's own log.
    */
    if (p === '/api/staff/records' && req.method === 'GET') {
      if (!w.dev) return sendJson(res, 403, { error: 'staff only' });
      return sendJson(res, 200, staffRecords(Date.now()));
    }

    /*
      Which commit each part on this box runs (#459), for staff (#1359).

      It sat above with /api/public, open to anybody, because a commit, a zip
      name and a hash were read as telling a stranger nothing. They tell a
      stranger plenty: the commit says which source is live to the hour, and
      the stamp says when each part last went out, which is what somebody
      looking for a way in reads first. Nothing in the repo fetches it and no
      page draws it, so the only caller is a person asking what is deployed.
      That person signs in.

      The same gate as the other staff doors, so widening access.dev widens
      this with them: the block above answers 401 'sign in first' to anybody
      with neither cookie, and a hub member who is not staff gets the 403
      'staff only' every staff door sends. No record is read before the
      refusal, so nothing leaks in the body or the timing.
    */
    if (p === '/api/deploys' && req.method === 'GET') {
      if (!w.dev) return sendJson(res, 403, { error: 'staff only' });
      return sendJson(res, 200, { parts: readDeploys(DEPLOYS_DIR) });
    }

    /*
      One character or the whole account (#1010). With a profileId (one of
      this account's characters) ban and unban are that character alone and
      pk kills it for good; without one, ban and unban are the account, every
      character on it and any new one. Staff may do these to staff, but not
      to their own account: a ban would lock them out of the page that lifts
      it.
    */
    const staffHub = /^\/api\/staff\/(ban|unban|note|pk|unpk)$/.exec(p);
    if (staffHub && req.method === 'POST') {
      if (!w.dev) return sendJson(res, 403, { error: 'staff only' });
      // Undoing a PK is the admin role's alone (Patrick, 29 September).
      if (staffHub[1] === 'unpk' && !w.admin) {
        return sendJson(res, 403, { error: 'admins only', message: 'Only an admin can undo a PK.' });
      }
      let o;
      try { o = JSON.parse(await body(req, 8000)) || {}; }
      catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
      const id = String(o.id || '').trim();
      const linked = jsonFile(LINKED, {});
      if (!/^\d{5,25}$/.test(id) || !linked[id]) return sendJson(res, 404, { error: 'nobody linked with that id' });
      const whoName = String(linked[id].name || linked[id].handle || '').slice(0, 60);
      const profiles = (Array.isArray(linked[id].profiles) ? linked[id].profiles : []).map(Number).filter((n) => n > 0);
      const now = Date.now();
      const act = staffHub[1];
      const pid = Number(o.profileId) || 0;
      if (pid && profiles.indexOf(pid) < 0) return sendJson(res, 404, { error: 'that character is not on this account' });
      if ((act === 'pk' || act === 'unpk') && !pid) return sendJson(res, 400, { error: 'a PK names the character' });
      if ((act === 'ban' || act === 'pk') && String(w.id) === id) {
        return sendJson(res, 400, { error: 'that is your own account' });
      }
      const charName = pid ? String(((jsonFile(ROSTER, { who: {} }).who || {})[String(pid)] || {}).name || '').slice(0, 60) : '';
      const whoChar = pid ? (charName ? charName + ' (' + whoName + ')' : whoName) : whoName;
      if (act === 'ban') {
        const why = String(o.why || '').trim().slice(0, 500);
        if (!why) return sendJson(res, 400, { error: 'a ban says why' });
        const minutes = banMinutes(o.minutes);
        const until = minutes ? now + minutes * 60000 : 0;
        const row = { at: now, until, why, by: w.name, byId: w.id, from: 'the hub', account: id };
        const ok = pid
          ? putBan('p:' + pid, Object.assign(row, { name: charName || whoName, profiles: [pid], scope: 'character' }))
          : putBan(id, Object.assign(row, { name: whoName, profiles, scope: 'account' }));
        if (!ok) return sendJson(res, 500, { error: 'could not save' });
        const said = banUntilText(until) + ': ' + why;
        if (pid) modLog({ did: 'ban', byName: w.name, whoName: whoChar, who: pid, why: said });
        else modLog({ did: 'banaccount', byName: w.name, whoName: whoChar, why: said });
        return sendJson(res, 200, { ok: true, until, account: !pid });
      }
      if (act === 'unban') {
        const r = dropBan([pid ? 'p:' + pid : id]);
        if (!r.ok) return sendJson(res, 500, { error: 'could not save' });
        if (r.was && pid) modLog({ did: 'unban', byName: w.name, whoName: whoChar, who: pid });
        else if (r.was) modLog({ did: 'unbanaccount', byName: w.name, whoName: whoChar });
        return sendJson(res, 200, { ok: true, was: r.was });
      }
      if (act === 'pk') {
        const why = String(o.why || '').trim().slice(0, 500);
        if (!why) return sendJson(res, 400, { error: 'a PK says why' });
        const had = jsonFile(PK, {})[String(pid)];
        if (pkActive(had)) return sendJson(res, 200, { ok: true, was: true, at: Number(had.at) || 0 });
        if (!putPk(pid, { at: now, by: w.name, byId: w.id, why, name: charName, account: id, from: 'the hub' })) {
          return sendJson(res, 500, { error: 'could not save' });
        }
        modLog({ did: 'pk', byName: w.name, whoName: whoChar, who: pid, why });
        return sendJson(res, 200, { ok: true, was: false, at: now });
      }
      if (act === 'unpk') {
        const why = String(o.why || '').trim().slice(0, 500);
        if (!why) return sendJson(res, 400, { error: 'an undo says why', message: 'Say why the PK is undone.' });
        const u = await undoPk(pid, w.name, w.id, why, 'the hub');
        if (u.body.ok && u.body.was) {
          const deadName = String(u.body.name || '') || charName;
          modLog({ did: 'unpk', byName: w.name, whoName: deadName ? deadName + ' (' + whoName + ')' : whoName, who: pid, why });
        }
        return sendJson(res, u.status, u.body);
      }
      const text = String(o.text || '').trim().slice(0, 1000);
      if (!text) return sendJson(res, 400, { error: 'a note says something' });
      if (!putNote(id, { at: now, by: w.name, byId: w.id, text, profileId: 0, name: whoName, from: 'the hub' })) {
        return sendJson(res, 500, { error: 'could not save' });
      }
      modLog({ did: 'note', byName: w.name, whoName, why: text });
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
      catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
      const saved = writeBoardOne(mb[1], obj, req.headers['x-board-rev']);
      if (!saved.ok) {
        if (saved.status === 409) console.warn('board ' + mb[1] + ': a save from revision ' + req.headers['x-board-rev'] + ' was refused, the board is at ' + saved.rev);
        return sendJson(res, saved.status, { error: saved.error, message: saved.message, rev: saved.rev });
      }
      return sendJson(res, 200, { ok: true, rev: saved.rev });
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
      const chat = chatSlice(row.profile, from, to, row.channel);

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
      catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
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
      catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
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
      catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
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
  if (EXPOSED) {
    console.log('[thornswood-docs] WARNING: plain HTTP on every address (THORNSWOOD_DOCS_EXPOSE=1). ' +
                'Sign-ins, cookies and uploads reach ' + PORT + ' unencrypted from anywhere the firewall lets in. ' +
                'Put Caddy in front and unset it (#2185).');
  }
  console.log('[thornswood-docs] writing this to ' + siteLog.file +
              ', rolled at 4 MB, five kept');
  console.log('[thornswood-docs] documents in ' + DATA);
  rereadTrouble();
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
