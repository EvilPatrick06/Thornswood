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
const tls    = require('tls');

/* NO eMUDHRA ROOT (#3111). Every request this process makes, discord.com with
   the bot token and the webhooks among them, verified against Node's bundled
   roots, which are Mozilla's from when this Node was built and carry all four
   of eMudhra's emSign roots. emSign ECC Root CA - G3 is the root of the eight
   intermediates found on 17 Oct 2026 with keys anyone could recover (Mozilla
   bug 2083449), and Node checks no revocation list, so a certificate made with
   one of those keys was enough to sit between this site and Discord. Mozilla
   still lists G1, and takes C1 and C3 out only in NSS 3.132, so a newer Node
   does not end it either. Nothing this site talks to chains to eMudhra, so
   its roots are what Node trusts by default less each one whose subject or
   issuer is eMudhra's, set once here before any connection is made, and
   bot\trust.py leaves out the same for the bot. Taking away is all this does:
   a root Node drops leaves with the next Node. */
const NOT_TRUSTED = /O=eMudhra/i;
const LEFT_OUT = [];
tls.setDefaultCACertificates(tls.getCACertificates('default').filter((pem) => {
  const c = new crypto.X509Certificate(pem);
  if (!NOT_TRUSTED.test(c.subject) && !NOT_TRUSTED.test(c.issuer)) return true;
  LEFT_OUT.push((c.subject.match(/^CN=(.*)$/m) || [null, c.subject])[1]);
  return false;
}));

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
/* And the other way round (issue #3140): what the bot writes for the site and
   nothing else, lists.json, the Known Issues page and the roadmap it builds
   from the issue board. The bot's account is given Modify on this folder only
   (Bot-Service.ps1), so it writes nothing else of the site's. */
const FROM_BOT = path.join(DATA, 'from-bot');
const LISTS = path.join(FROM_BOT, 'lists.json');

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
//
// BY AGE AS WELL AS BY SIZE (#2166). Until 17 Oct 2026 this rolled at 4 MB
// and kept five, and nothing aged it: a quiet site kept months in site.log,
// profile numbers and character names among them, while the privacy page
// said nothing about it. Patrick decided on 17 Oct (#2166, G5): the logs
// that name people go after 90 days. So with opts.liveDays and
// opts.copyDays, once an hour and once as the log is made, the live file is
// rolled once its first line is liveDays old, and a rolled copy is deleted
// once its last write is copyDays old. A copy's oldest line is at most
// liveDays older than its last write, so at 30 and 59 nothing in any of them
// is 90 days old (59 + 30 and the hour between passes). The count and the
// size stay the bound on disk. Each roll or delete it makes, and each one
// that fails, is one line here and on the console, naming the file and the
// error, never what the file held.
function makeLog(dir, name, maxBytes, keep, opts) {
  const file = path.join(dir, name);
  const retryMs = (opts && typeof opts.retryMs === 'number') ? opts.retryMs : 60000;
  const liveMs = (opts && opts.liveDays > 0) ? opts.liveDays * 86400000 : 0;
  const copyMs = (opts && opts.copyDays > 0) ? opts.copyDays * 86400000 : 0;
  const ceiling = maxBytes * 2;
  let broken = false;
  let rollError = null;      // the last roll's error, null when the last roll worked
  let rollFailures = 0;      // failed rolls since the last good one
  let nextRoll = 0;          // no retry before this (ms)
  let held = false;          // the ceiling line has been written
  // No try (#2736): a string written to stdout does not throw here, and a
  // pipe that has gone fails later as the stream's own error, which a catch
  // around the write never saw.
  function say(line) {
    process.stdout.write('[thornswood-docs] ' + line + '\n');
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
      say('could not write ' + file + ', carrying on with the console only: ' + e.message);
      return false;
    }
  }

  // The time of the live file's first line, from its stamp, or null.
  function firstLineAt() {
    let fd = null;
    try {
      fd = fs.openSync(file, 'r');
      const buf = Buffer.alloc(32);
      const n = fs.readSync(fd, buf, 0, 32, 0);
      const m = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/.exec(buf.toString('latin1', 0, n));
      return m ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime() : null;
    } catch (e) { return null; }
    finally {
      if (fd !== null) {
        try { fs.closeSync(fd); }
        catch (e) { say('could not close ' + file + ' after reading its first line (' + (e.code || e.message) + ')'); }
      }
    }
  }

  function age() {
    const out = { rolled: false, deleted: 0, failed: [] };
    if (!liveMs || !copyMs || broken) { return out; }
    const now = Date.now();
    for (let i = 1; i <= keep; i++) {
      const f = file + '.' + i;
      let st;
      try { st = fs.statSync(f); } catch (e) { continue; }
      if (now - st.mtimeMs < copyMs) { continue; }
      try { fs.unlinkSync(f); out.deleted++; }
      catch (e) { out.failed.push({ file: name + '.' + i, code: (e && e.code) || 'unknown' }); }
    }
    const first = firstLineAt();
    if (first !== null && now - first >= liveMs) {
      if (roll()) { out.rolled = true; }
      else { out.failed.push({ file: name, code: (rollError && (rollError.code || rollError.message)) || 'unknown' }); }
    }
    if (out.rolled || out.deleted || out.failed.length) {
      const line = name + ' by age: ' + (out.rolled ? 'rolled, its first line ' + (opts.liveDays) + ' days old; ' : '') +
        out.deleted + ' rolled cop' + (out.deleted === 1 ? 'y' : 'ies') + ' past ' + opts.copyDays + ' days deleted' +
        (out.failed.length ? '; could not change ' + out.failed.map(function (x) { return x.file + ' (' + x.code + ')'; }).join(', ') +
          ', tried again within the hour' : '');
      say(line);
      write(line);
    }
    return out;
  }
  if (liveMs && copyMs) {
    age();
    const t = setInterval(age, (opts && opts.ageEveryMs) || 3600000);
    if (t && t.unref) { t.unref(); }
  }

  return {
    file: file, write: write, roll: roll, ceiling: ceiling, age: age,
    broken: function () { return broken; },
    rolling: function () { return { failures: rollFailures, held: held, error: rollError ? (rollError.code || rollError.message) : null }; }
  };
}

// Four megabytes is a few days of a closed playtest and opens in anything.
// Five kept, so a crash on Saturday night is still readable on Monday.
// Nothing in it, or in a rolled copy, reaches 90 days (#2166).
const siteLog = makeLog(ROOT, 'site.log', 4 * 1024 * 1024, 5, { liveDays: 30, copyDays: 59 });

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

    LOCKED 12 Oct and 15 Oct (Patrick via Smeagle on #428): closed playtest /
    alpha stays. Do not flip public mode. open stays false until Patrick ends
    the alpha and Discord onboarding grants Member with the 18+ and rules
    answers. The switch below is built; leaving it off is the requirement.

    The day the world opens to everybody, "open": true in config.json is the
    one switch (#428). It puts Member on the play list at load (playRoles),
    tells the bot and the pages through /api/public, and they follow: the
    bot drops the application from its panel, and the join, help, rules and
    home wording change with it. Off unless config.json says true. It only
    opens the world to everybody if everybody in the Discord has Member.
  */
  open: false,
  access: {
    // #3317 (Patrick, 22 Oct): every staff role plays the main build, with
    // Playtester; the site's admin pages are Owner, Co-Owner and the Dev rank.
    admin:  ['Owner', 'Co-Owner', 'Lead Dev', 'Dev'],
    play:   ['Owner', 'Co-Owner', 'Lead Dev', 'Lead Gamemaster', 'Lead Loremaster',
             'Lead Moderator', 'Lead Content Creator', 'Lead Support', 'Dev',
             'Gamemaster', 'Trial Gamemaster', 'Loremaster', 'Moderator',
             'Content Creator', 'Support', 'Playtester'],
    banned: ['Banned']
  },
  botKey: '',            // shared secret the Discord bot signs /api/ticket with
  admins: [],            // discord ids, an override for when the bot is down
  secret: '',
  passKey: '',           // signs join passes; the game servers hold a copy (#937)
  /* Cloudflare Turnstile on the report form (#3216). The site key goes to the
     page and is public; the secret is what the site checks a pass with, and
     lives only here. Both are set on the box by Set-Turnstile.ps1. Either one
     empty, as on a copy on your machine, means no widget and no check. */
  turnstileSiteKey: '',
  turnstileSecret: ''
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
// dev, company and slots3 get their defaults below. The hold offices are not
// a list here: they are read from the roles' own names (OFFICE_ROLE, #2551).
cfg.access  = Object.assign({ admin:[], play:[], banned:[] }, cfg.access || {});
// The one switch (#428). Only a real true opens it: "true", 1 or a typo does not.
cfg.open = cfg.open === true;
cfg.access.play = playRoles(cfg.access.play, cfg.open);
// Who is staff in the game: the staff seats over the most the world holds,
// the game's staff powers (devProfiles), and the uploads queue. Since #3317
// (Patrick, 22 Oct) it is the staff who work in the world: Owner and
// Co-Owner, and the Dev, Gamemaster and Loremaster ranks with their leads.
// Moderators moderate the Discord only, and Content Creator and Support work
// in the Discord, so none of them is staff in the game. It folds access.admin
// in through out.dev below, so widening admin still widens it.
if (!Array.isArray(cfg.access.dev)) {
  cfg.access.dev = ['Owner', 'Co-Owner', 'Lead Dev', 'Dev', 'Lead Gamemaster',
                    'Gamemaster', 'Trial Gamemaster', 'Lead Loremaster', 'Loremaster'];
}
// Who may use the dev build and join the dev server (#605, the install gate).
// Patrick, 22 Oct (#3317): "Dev build: Owner, Co-Owner, Dev and the leads
// only". Every lead of the council is in it, a lead whose rank is not staff
// in the game included. It folds access.admin in through out.devBuild below.
if (!Array.isArray(cfg.access.devBuild)) {
  cfg.access.devBuild = ['Owner', 'Co-Owner', 'Lead Dev', 'Lead Gamemaster',
                         'Lead Loremaster', 'Lead Moderator', 'Lead Content Creator',
                         'Lead Support', 'Dev'];
}
// Who the Free Skyrim Trading Company has taken on (#1393): an application in
// Discord, the same shape as a Jarl's, and a person gives the role. The game
// lets them handle a company sale.
if (!Array.isArray(cfg.access.company)) {
  cfg.access.company = ['Free Skyrim Trading Company'];
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
  // Said when it cannot be kept (#2736): the secret then lives only in this
  // run, so every restart signs everybody out until config.json can be written.
  try { fs.writeFileSync(CFGFILE, JSON.stringify(cfg, null, 2), 'utf8'); }
  catch (e) {
    console.error('[thornswood] could not keep the new cookie secret in config.json (' + (e.code || e.message) +
                  '), so a restart signs everybody out');
  }
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

// A folder that cannot be made is said (#2736), by its path and the error
// code; every read and write under it fails after this, and the line here is
// the one that says why.
for (const dir of [DATA, FOR_BOT, FROM_BOT, PUBLIC, FILES, UP]) {
  try { fs.mkdirSync(dir, { recursive: true }); }
  catch (e) { console.error('[thornswood-docs] could not make ' + dir + ' (' + (e.code || e.message) + ')'); }
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
   a column can be added to one without touching the rest.

   KNOWN ISSUES AND THE ROADMAP ARE NOT BOARDS ANY MORE (#3140). Both were
   typed here, and both went stale: the known board kept NPC behaviour #504
   had fixed, and the roadmap called the emote wheel unstarted while it
   shipped. Patrick: build them from the board's labels. The bot, which reads
   the issue board for #known-issues, writes both into data/from-bot/lists.json
   and the site draws them from there (THE KNOWN ISSUES PAGE AND THE ROADMAP,
   below). */
const BOARDS = {
  active:      'Active Issues',
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
                      // sit behind the sign in. Help is help.md in the data
                      // folder and Known Issues is written from the issue
                      // board (#3140), both read through /api/page like the
                      // site pages.
                      '/known', '/help',
                      // What is kept about somebody and what they are
                      // agreeing to cannot sit behind a sign in, because
                      // the person deciding whether to sign up is the one
                      // who needs to read them.
                      '/privacy', '/terms', '/cookies'];
const PUBLIC_DOCS = ['help'];
/* The public pages are markdown on disk like everything else here, so the
   wording can be fixed from the site rather than by a deploy. */
const SITE = path.join(DATA, 'site');

/* What a link to each page says when it is pasted into Discord. Every address
   used to unfurl with the same generic home text, so a link to the rules and a
   link to the roadmap read identically in a channel. This is the only copy:
   the page is sent with its title, description and og tags already written
   from it (publicDiscovery and the route below), so the browser tab and a
   crawler read the same words. home.js kept a second list for the tab until
   #3138, and the two had drifted apart on two pages. */
const BLURB = {
  '/':          ['Thornswood', 'A Skyrim roleplay server set fifty years after the civil war. The world still has people in it.'],
  '/world':     ['The world', 'Fifty years after the Stormcloaks won. A free Skyrim, an Empire with an embassy and no soldiers, and the White Harbour Accord.'],
  '/rules':     ['Rules', 'Nine rules, short on purpose. Nobody dies without agreeing to, play a person rather than a legend, and staff decide.'],
  '/join':      ['How to join', 'What you need, how to apply, and what happens between pressing Play and arriving in your town.'],
  '/credits':   ['Credits', 'Everyone whose work Thornswood is built on.'],
  '/classes':   ['Professions and classes', 'One profession, one half of it, one class. An Edgewright cannot make steel armour, so you find somebody who can.'],
  '/known':     ['Known issues', 'What is broken right now that the team already knows about, each one on the board to be fixed. Read this before reporting anything.'],
  '/help':      ['Help', 'Installing, the collection, LOAD ORDER ERROR, and where the logs are.'],
  '/downloads': ['Download', 'What you need, the installer, and the collection in Vortex.'],
  '/roadmap':   ['Roadmap', 'What is being worked on and roughly in what order.'],
  '/news':      ['Every release', 'What changed, newest first. The same list the launcher shows.'],
  '/report':    ['Report a problem', 'Something broken, or an idea, with no account needed. Or somebody behaving badly, signed in.'],
  '/gallery':   ['From the world', 'Pictures taken by people playing.'],
  '/privacy':   ['Privacy', 'What Thornswood keeps about you, why, and how to have it deleted. No advertising tag and no tracking cookie.'],
  '/terms':     ['Terms', 'Eighteen and over, play by the rules, your account is yours, and nothing here is charged for or promised.'],
  '/cookies':   ['Cookies', 'Every cookie and piece of browser storage this site uses: sign-in and the eighteen-and-over gate. No advertising cookie.']
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
/*
  THE KNOWN ISSUES PAGE AND THE ROADMAP, FROM THE ISSUE BOARD (#3140).

  Both used to be boards typed into board.json, and both went stale. Now the
  bot builds them from the board each time it reads it for #known-issues
  (bot.py, "the site's known issues and roadmap") and writes them into
  data/from-bot/lists.json:

    { at: when the bot read the board,
      known: [{ title, text, where: ['Main', 'Dev'] }],
      roadmap: { lanes: [{ name, rows: [{ title, text }] }] } }

  known is the #known-issues forum's list, word for word: an open issue
  labelled Main Findings or Dev Findings whose fix has not landed, in the
  words of its last "Known issue:" comment. roadmap is every open issue
  labelled roadmap: now, next or later, in that lane, in the words of its
  last "Roadmap:" comment; there is no Done lane (Patrick, 26 Oct).

  These two turn the file into what /known (and /api/page/known) and /roadmap
  (and /api/roadmap) serve. A part the file does not hold, or a file that is
  not there or will not read, is said on the page as not read, never drawn as
  an empty list: an empty list says nothing is broken. The time of the read is
  on both pages, so a bot that stopped writing shows as an old date.
*/
// ==== thornswood lists ====
const KNOWN_INTRO = 'What is broken right now that the team already knows about. Each one is\n' +
  'on the issue board to be fixed, and comes off this page as soon as work on\n' +
  'it is merged.\n\n' +
  'What works the way it does on purpose, such as no saving, no fast travel\n' +
  'and the load order rule, is on the [Help](/help) page under Things that\n' +
  'are normal here, not here.';
const ROADMAP_INTRO = 'What is being built and roughly in what order. Nothing here has a date on it, because a date would be a guess.\n\n' +
  'Things move up this list when somebody starts on them, not when they are announced.';
const LIST_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
// "26 Oct 2026, 8:05 AM UTC", or null for a time that will not read.
function listTime(at) {
  const d = new Date(String(at || ''));
  if (!at || isNaN(d.getTime())) return null;
  const h = d.getUTCHours(), m = d.getUTCMinutes();
  return d.getUTCDate() + ' ' + LIST_MONTHS[d.getUTCMonth()] + ' ' + d.getUTCFullYear() + ', ' +
    (h % 12 || 12) + ':' + (m < 10 ? '0' : '') + m + (h < 12 ? ' AM' : ' PM') + ' UTC';
}
function listText(v) { return String(v == null ? '' : v).replace(/\r\n/g, '\n').trim(); }
// Where a known issue was found, in words.
function knownWhere(where) {
  const w = (Array.isArray(where) ? where : []).map(String);
  const words = [];
  if (w.indexOf('Main') >= 0) words.push('main');
  if (w.indexOf('Dev') >= 0) words.push('the dev server');
  return words.length ? 'Found on ' + words.join(' and ') + '.' : '';
}
// The Known Issues page's markdown out of lists.json's contents (or null).
function knownMarkdown(lists) {
  const out = ['# Known Issues', '', KNOWN_INTRO, ''];
  const at = listTime(lists && lists.at);
  const known = lists && Array.isArray(lists.known) ? lists.known : null;
  if (!known || !at) {
    out.push('The list could not be read from the issue board just now. Try again in a few', 'minutes, and report a problem as usual in the meantime.');
    return out.join('\n') + '\n';
  }
  const rows = known.filter((k) => k && listText(k.title));
  out.push('## Broken right now', '');
  if (!rows.length) out.push('Nothing is listed right now.', '');
  else out.push('Report one of these only if it does something this page does not describe.', '');
  for (const k of rows) {
    out.push('### ' + listText(k.title).replace(/\s*\n\s*/g, ' '), '');
    if (listText(k.text)) out.push(listText(k.text), '');
    const where = knownWhere(k.where);
    if (where) out.push('*' + where + '*', '');
  }
  out.push('*Read from the issue board ' + at + '.*');
  return out.join('\n') + '\n';
}
// The roadmap as /api/roadmap hands it to the front page and /roadmap draws
// it: its intro, a section per lane (columns What and Where it stands, so a
// lane reads like the board it replaced), when it was read, and unread when
// the file held no roadmap.
function roadmapBoard(lists) {
  const at = listTime(lists && lists.at);
  const rm = lists && lists.roadmap && Array.isArray(lists.roadmap.lanes) ? lists.roadmap : null;
  const board = { intro: ROADMAP_INTRO, sections: [], at: at || '', unread: !rm || !at };
  if (board.unread) return board;
  rm.lanes.forEach((lane, i) => {
    if (!lane || !listText(lane.name)) return;
    board.sections.push({
      id: 'lane' + i, name: listText(lane.name), note: '',
      columns: [{ id: 'what', name: 'What' }, { id: 'where', name: 'Where it stands' }],
      rows: (Array.isArray(lane.rows) ? lane.rows : []).filter((r) => r && listText(r.title)).map((r, j) => ({
        id: 'lane' + i + 'r' + j, done: false,
        cells: { what: listText(r.title), where: listText(r.text) } }))
    });
  });
  return board;
}
// ==== end thornswood lists ====

// A written page's markdown, or null. Help lives in the data folder with the
// other documents, not under site; Known Issues is written from the issue
// board, by way of the bot's lists.json (#3140).
function pageMarkdown(name) {
  if (name === 'known') {
    try { return forMode(knownMarkdown(readLists()), cfg.open); } catch (e) { return null; }
  }
  const dir = PUBLIC_DOCS.indexOf(name) >= 0 ? DATA : SITE;
  const file = path.join(dir, name + '.md');
  if (!file.startsWith(dir + path.sep) || !fs.existsSync(file)) return null;
  try { return forMode(fs.readFileSync(file, 'utf8'), cfg.open); } catch (e) { return null; }
}

// The hints and lore lines (#3147): data\site\lines.md is the one copy of
// them. The front page's lore line comes out of it as the page is served,
// and /api/public hands the lot out, which is where the Discord bot reads its
// status lines. The file's own comment says its rules, and
// tests\test-3147-lines.js holds them, so nothing here checks a line again.
// ==== thornswood lines ====
function parseLines(md) {
  const out = { hints: [], lore: [] };
  let list = null, last = null;
  String(md == null ? '' : md).replace(/<!--[\s\S]*?-->/g, '').split(/\r?\n/).forEach(function (l) {
    const head = /^##\s+(.*?)\s*$/.exec(l);
    if (head) {
      list = /^hints$/i.test(head[1]) ? 'hints' : /^lore lines$/i.test(head[1]) ? 'lore' : null;
      last = null;
      return;
    }
    if (!list) return;
    const item = /^- (.*?)\s*$/.exec(l);
    if (item) {
      if (list === 'hints') { out.hints.push(item[1]); last = null; }
      else { last = { text: item[1], from: '' }; out.lore.push(last); }
      return;
    }
    // The source of a lore line, on the line under it.
    const from = /^ {2}(\S.*?)\s*$/.exec(l);
    if (from && last && !last.from) last.from = from[1];
  });
  return out;
}

// home.html's lore line, the empty quote under The World, filled with one
// line picked at pick (0 to 1, Math.random() when served). With no lore line
// to show it stays empty and hidden.
function fillLoreLine(html, lore, pick) {
  const esc = function (s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  };
  const list = Array.isArray(lore) ? lore : [];
  if (!list.length) return html;
  const one = list[Math.min(list.length - 1, Math.floor(pick * list.length))];
  return html.replace('<blockquote class="chron" id="loreLine" hidden></blockquote>', () =>
    '<blockquote class="chron" id="loreLine">' + esc(one.text) +
    (one.from ? '<cite>' + esc(one.from) + '</cite>' : '') + '</blockquote>');
}
// ==== end thornswood lines ====

function readLines() {
  try {
    return parseLines(forMode(fs.readFileSync(path.join(SITE, 'lines.md'), 'utf8'), cfg.open));
  } catch (e) {
    console.error('[thornswood-docs] could not read data/site/lines.md, so the front page shows ' +
                  'no lore line and /api/public no lines: ' + e.message);
    return { hints: [], lore: [] };
  }
}

// The credits page says which engine each server runs. That is a fact of the
// box, not of the repo, so a hand edit went stale with every deploy (the
// source-offer test caught 3a32e961 that way). Deploy-Server.ps1 and
// Publish-Server.ps1 write data/deployed-build.json after a server deploy on
// either channel (scripts/deploy/DeployedBuild.ps1), and the feeds this site
// serves carry the client commit. fillCreditsCommits puts both into the page
// at serve time. The markdown keeps its hand text, which names no commit for
// either server or either feed, and is what goes out when the record or a
// feed cannot be read.
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
  // Either server alone is enough to say something true (#2303). Until then
  // a record with only live in it, which is what the box held on 11 Oct after
  // the dev engine went up through Publish-Server, kept the hand text, and the
  // hand text named the engine the main server had left behind.
  if (live || dev) {
    const rec = /built from one commit,\s+\[`[0-9a-f]{7,40}`\]\(https:\/\/github\.com\/EvilPatrick06\/skymp\/tree\/([0-9a-f]{40})\)/.exec(out);
    const recorded = rec ? rec[1] : '';
    let said;
    if (live && dev && live === dev) {
      said = live === recorded ? 'Both servers run it, ' + link(live) + '.'
                               : 'The recorded build has not been deployed yet. Both servers run ' + link(live) + '.';
    } else if (live && dev) {
      said = (live !== recorded && dev !== recorded ? 'The recorded build has not been deployed yet. ' : '') +
             'The test server runs ' + link(dev) + ' and the main server runs ' + link(live) + '.';
    } else {
      // Only the server the record names is spoken for; the other is left
      // unsaid rather than guessed.
      const one = live || dev;
      const who = live ? 'The main server' : 'The test server';
      said = one === recorded ? who + ' runs it, ' + link(one) + '.' : who + ' runs ' + link(one) + '.';
    }
    // The hand text is the rest of the paragraph after "then to the main
    // server.", whatever it says (#2098, #2303).
    out = out.replace(/(then to the main server\.\s+)(?:(?!\n\s*\n)[\s\S])+?(?=\n\s*\n|$)/,
                      function (m, lead) { return lead + said; });
  }
  // A channel row's last cell is hand text that names no commit (#421: a
  // hash typed there went stale with every Ship), and the feed's commit takes
  // its place, whatever it says.
  for (const row of [['Public', 'feed/version.json', 'public'], ['Dev', 'feed-dev/version.json', 'dev']]) {
    const c = feeds && typeof feeds === 'object' ? String(feeds[row[2]] || '') : '';
    if (!SOME.test(c)) continue;
    const re = new RegExp('(^|\\n)(\\|\\s*' + row[0] + '\\s*\\|\\s*`' + row[1].replace(/[./]/g, '\\$&') +
                          '`\\s*\\|[ \\t]*)[^|\\n]*?([ \\t]*\\|[ \\t\\r]*(?=\\n|$))');
    out = out.replace(re, function (m, a, b, end) { return a + b + link(c) + end; });
  }
  return out;
}
// ==== end thornswood credits fill ====
const DEPLOYED_BUILD = path.join(DATA, 'deployed-build.json');
/* THE FEED'S GENERATIONS (#2727). The store never replaces version.json: each
   feed a Ship or feed edit sends is a new file, <channel>\version\<8 digits>.json,
   one past the newest, and none is ever replaced or deleted
   (scripts\release\Feed-Store.ps1). Windows has no way to put one file in place
   of another by name without a moment where the name is missing: measured on
   the VPS, every way of doing it left opens finding nothing, so a launcher's
   check, a /watch tick or a join pass that landed in a Ship's swap found no
   feed. A generation's name only ever appears, and the one before it stays, so
   the newest one is always there to read. The folder is listed once; after
   that each call only asks whether the newest is still there (a folder put back
   by hand lists again) and whether the next number has appeared. Null while a
   channel has no feed. */
const feedNewest = {};
function feedGeneration(n) { return String(n).padStart(8, '0') + '.json'; }
/* THE FEED LAUNCHERS READ, IN TWO (#1050, Patrick's answer of 19 Oct). The
   store keeps every generation whole, and every script, backup and page reads
   it whole. What /feed[-dev]/version.json answers is feedView's: once the
   feed's minLauncher is at or above FEED_SPLIT_LAUNCHER, the first launcher
   that reads it this way (launcher\app\FeedSettings.cs), version.json holds
   only what the update check needs, FEED_TOP, and names everything else as
   one more asset, "settings": { sha256 }, the rest of the feed as one line
   of JSON, answered at /feed[-dev]/assets/<sha256> from here. And every asset
   the feed names is named by its sha256 alone: the launcher finds it in the
   feed's own assets folder. A launcher reads the feed on every check, every
   thirty seconds in a session, and on 19 Oct main's was 4,928 bytes, almost
   none of which moves between releases. Below that minLauncher the file is
   answered as the store holds it, byte for byte. The launcher fields, and
   "packs" and "news" as the empty lists every launcher has read, stay in
   version.json either way, so a launcher from before this can still read
   that it is behind and update itself. Kept beside the generations because
   everything that answers the feed reads through both. */
const FEED_SPLIT_LAUNCHER = '1.2.6';
const FEED_TOP = ['launcherVersion', 'minLauncher', 'launcherUrl', 'launcherSha256', 'baseline', 'newsFile', 'packs', 'news'];
const feedViews = {};
function feedAtLeast(v, min) {
  const a = String(v || '').trim().split('.'), b = min.split('.');
  if (a.some((x) => !/^\d+$/.test(x))) return false;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const x = Number(a[i] || 0), y = Number(b[i] || 0);
    if (x !== y) return x > y;
  }
  return true;
}
function feedHashOnly(o, keys) {
  if (!o || typeof o !== 'object' || Array.isArray(o)) return;
  for (const pair of keys) {
    if (/^[0-9a-f]{64}$/.test(String(o[pair[1]] || ''))) delete o[pair[0]];
  }
}
function feedSplit(doc) {
  const top = {}, rest = {};
  for (const k of Object.keys(doc)) (FEED_TOP.indexOf(k) >= 0 ? top : rest)[k] = doc[k];
  feedHashOnly(top.baseline, [['url', 'sha256']]);
  feedHashOnly(top.newsFile, [['url', 'sha256']]);
  feedHashOnly(rest.clientRuntime, [['url', 'sha256']]);
  feedHashOnly(rest.signedManifest, [['url', 'sha256'], ['catalogUrl', 'catalogSha256']]);
  const settings = Buffer.from(JSON.stringify(rest), 'utf8');
  const sha = require('crypto').createHash('sha256').update(settings).digest('hex');
  top.settings = { sha256: sha };
  return { body: Buffer.from(JSON.stringify(top), 'utf8'), sha: sha, settings: settings };
}
/* The answer for one generation file: { body, tag, sha, settings }, sha and
   settings null when it is answered whole. The tag is the file's size and
   time, as it always was, with "-split" on a split one, so turning the split
   on gives every launcher a new document once. The last four are kept per
   channel, so a launcher that read version.json just before a Ship still
   finds the settings it names. Throws when the file is gone. */
function feedView(channel, file) {
  const st = fs.statSync(file);
  const list = feedViews[channel] || (feedViews[channel] = []);
  for (const v of list) if (v.file === file && v.size === st.size && v.mtimeMs === st.mtimeMs) return v;
  const raw = fs.readFileSync(file);
  const v = { file: file, size: st.size, mtimeMs: st.mtimeMs, body: raw, sha: null, settings: null,
              tag: '"' + st.size.toString(16) + '-' + Math.floor(st.mtimeMs).toString(16) + '"' };
  let doc = null;
  try { doc = JSON.parse(raw.toString('utf8').replace(/^﻿/, '')); } catch (e) { doc = null; }
  if (doc && typeof doc === 'object' && !Array.isArray(doc) && feedAtLeast(doc.minLauncher, FEED_SPLIT_LAUNCHER)) {
    const s = feedSplit(doc);
    v.body = s.body; v.sha = s.sha; v.settings = s.settings;
    v.tag = v.tag.slice(0, -1) + '-split"';
  }
  list.unshift(v);
  if (list.length > 4) list.length = 4;
  return v;
}
/* The settings a view of this channel names, or null. The newest generation
   is looked at first, for a site that restarted since the feed was read. */
function feedSettings(channel, sha) {
  const newest = feedFile(channel);
  if (newest) feedView(channel, newest);
  for (const v of feedViews[channel] || []) if (v.sha === sha) return v.settings;
  return null;
}
function feedFile(channel) {
  const dir = path.join(ROOT, channel, 'version');
  let n = feedNewest[channel] || 0;
  if (n && !fs.existsSync(path.join(dir, feedGeneration(n)))) n = 0;
  if (!n) {
    if (!fs.existsSync(dir)) return null;
    for (const name of fs.readdirSync(dir)) {
      if (/^\d{8}\.json$/.test(name)) n = Math.max(n, Number(name.slice(0, 8)));
    }
    if (!n) return null;
  }
  while (fs.existsSync(path.join(dir, feedGeneration(n + 1)))) n++;
  feedNewest[channel] = n;
  return path.join(dir, feedGeneration(n));
}
function readJsonQuiet(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); } catch (e) { return null; }
}
function creditsFacts() {
  const feeds = {};
  for (const pair of [['public', 'feed'], ['dev', 'feed-dev']]) {
    const f = feedFile(pair[1]);
    const v = f ? readJsonQuiet(f) : null;
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
    // Same roadmap as /api/roadmap, built from the issue board (#3140).
    const rm = roadmapBoard(readLists());
    if (rm.intro) body += pageHtml(rm.intro).replace(/<h1\b/g, '<h2').replace(/<\/h1>/g, '</h2>');
    let count = 0;
    for (const section of (rm.sections || [])) {
      // Every lane the bot wrote is drawn, in its order, none filtered by
      // name (#2560); the bot writes no Done lane since 26 Oct.
      if (!(section.rows || []).length) continue;
      body += '<section class="lane"><h2>' + escAttr(section.name || '') + '</h2><ul>';
      for (const row of section.rows) {
        const text = (section.columns || []).map(col => (row.cells || {})[col.id]).filter(Boolean).join(' · ');
        body += '<li>' + escAttr(text) + '</li>'; count++;
      }
      body += '</ul></section>';
    }
    if (rm.unread) body += '<p>The roadmap could not be read from the issue board just now. Try again in a few minutes.</p>';
    else if (!count) body += '<p>No upcoming work is listed here yet. See <a href="/known">known issues</a> for current limits.</p>';
    if (rm.at) body += '<p><em>Read from the issue board ' + escAttr(rm.at) + '.</em></p>';
  } else if (route === '/gallery') {
    const shots = publicJson(GALLERY, []);
    const approved = (Array.isArray(shots) ? shots : []).slice(0, 24);
    body += '<p>Only pictures approved by staff appear here. <a href="/privacy">How submissions are used</a>.</p><div class="gallery">';
    for (const g of approved) {
      if (!/^\/shot\/[^?#]+$/.test(g.url || '')) continue;
      const alt = g.alt || 'Skyrim scene shared by ' + (g.by || 'the Thornswood community');
      const media = /\.(mp4|webm)$/i.test(g.name || '')
        ? '<video controls preload="metadata" aria-label="' + escAttr(alt) + '"><source src="' + escAttr(g.url) + '"></video>'
        : '<img src="' + escAttr(g.url) + '"' +
          (g.srcset ? ' srcset="' + escAttr(g.srcset) + '" sizes="(max-width: 620px) calc(100vw - 48px), 34vw"' : '') +
          ' alt="' + escAttr(alt) + '" loading="lazy">';
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
/*
  EVERY FILE A PAGE NAMES CARRIES ITS OWN HASH, SO IT CAN BE KEPT FOR A YEAR
  (#3218).

  Only home.js and home.css had a ?v= written on, and the static branch below
  never read it, so those two were kept for an hour like everything else, and
  the fonts, the logo, the banner and the video were fetched again after every
  hour (Cloudflare stretched it to four). A Lighthouse run on 21 Oct 2026 put
  826 KiB of a repeat visit on it.

  Now every "/name" a page names in src, href, poster or srcset, and every
  url(/name) a stylesheet names, is written out as /name?v=<hash of what is
  served>, and the static branch sends a name asked for with the hash it has
  now as immutable for a year. A deploy that changes a file changes its hash,
  so the page names a new address and nothing old is shown. A stylesheet's
  hash is of the stylesheet as served, its fonts' hashes included, so a new
  font file moves fonts.css's address with it. Asked for with no hash, or an
  old one, a file is the hour and its ETag, as before.

  The hash of a stylesheet is kept against its own file and the hashes of what
  it names; any other file's against its size and times, which every deploy
  changes.
*/
const publicAssetVersions = new Map();
const ASSET_NAME = /^[A-Za-z0-9._-]+\.(?:js|css|png|jpe?g|webp|avif|gif|svg|ico|woff2?|mp4|webm)$/i;
function publicAssetVersion(asset) {
  if (!ASSET_NAME.test(asset)) return null;
  const file = path.join(PUBLIC, asset);
  try {
    const st = fs.statSync(file), key = st.size + ':' + st.mtimeMs + ':' + st.ctimeMs;
    const cached = publicAssetVersions.get(asset);
    const named = (refs) => refs.map(publicAssetVersion).join(',');
    if (cached && cached.key === key && named(cached.refs) === cached.named) return cached.version;
    const body = publicAssetBody(asset);
    const refs = /\.css$/i.test(asset) ? assetRefs(fs.readFileSync(file, 'utf8')) : [];
    const version = crypto.createHash('sha256').update(body).digest('hex').slice(0, 16);
    publicAssetVersions.set(asset, {key, version, refs, named: named(refs)}); return version;
  } catch (e) { return null; }
}
// The bytes the static branch sends for a file of public/: a stylesheet with
// its url()s versioned, anything else as it is on disk.
function publicAssetBody(asset) {
  const raw = fs.readFileSync(path.join(PUBLIC, asset));
  return /\.css$/i.test(asset) ? Buffer.from(versionAssets(raw.toString('utf8')), 'utf8') : raw;
}
const ASSET_ATTR = /(\s(?:src|href|poster)=")\/([A-Za-z0-9._-]+)"/g;
const ASSET_SRCSET = /(\ssrcset=")([^"]*)"/g;
const ASSET_URL = /url\((["']?)\/([A-Za-z0-9._-]+)\1\)/g;
function assetRefs(text) {
  const out = [];
  String(text).replace(ASSET_URL, (all, q, name) => { out.push(name); return all; });
  return out;
}
function versionAssets(text) {
  const tag = (name) => { const v = publicAssetVersion(name); return v ? '/' + name + '?v=' + v : '/' + name; };
  return String(text)
    .replace(ASSET_ATTR, (all, attr, name) => attr + tag(name) + '"')
    .replace(ASSET_SRCSET, (all, attr, list) => attr +
      list.replace(/(^|,\s*)\/([A-Za-z0-9._-]+)/g, (m, lead, name) => lead + tag(name)) + '"')
    .replace(ASSET_URL, (all, q, name) => 'url(' + q + tag(name) + q + ')');
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
  // The ?v= on every file the page names is send()'s (versionAssets).
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

   LOCKED closed (Patrick, 12 Oct option B + 15 Oct via Smeagle): do not set
   open true and do not ship a public-mode flip from this card. Alpha / apply
   for Playtester stays the door. Public flip waits on Discord onboarding that
   grants Member and records 18+ and rules, after Patrick ends the alpha.

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
  server's own number into the same file as max, so the page says "3 of 30"
  and /api/play/join can say the world is full before the game starts. max
  is every seat, the staff seats too (Patrick, 12 Oct: "the real cap is 30
  but 25 for people with non staff roles I still want it to say of 30
  awake"); full says whether somebody without a staff role would wait.
*/
/*
  And how many wait at the menu for a seat (line), and whether somebody
  picking now would wait too (full), which the gamemode's seats block works
  out and writes beside the count.
*/
let gameStatus = { up: false, online: 0, max: 0, line: 0, full: false, at: 0 };
/* online.json that is there and cannot be read is said (#2736), once, and
   again only after a read has worked, since this runs every ten seconds. No
   file is the normal case while the game server is down, and is tested for
   rather than thrown. */
let onlineUnread = '';
function pollGame() {
  const sock = new net.Socket();
  let done = false;
  const finish = (up) => {
    if (done) return;
    done = true;
    sock.destroy();
    let online = 0, max = 0, line = 0, full = false;
    let o = null, why = '';
    if (fs.existsSync(cfg.onlineFile)) {
      try { o = JSON.parse(fs.readFileSync(cfg.onlineFile, 'utf8')); }
      catch (e) { why = e.code || 'not JSON'; }
    }
    if (why && why !== onlineUnread) {
      console.error('[thornswood-docs] could not read the online count in ' + cfg.onlineFile + ' (' + why +
                    '), so the site shows nobody on until it reads again');
    }
    onlineUnread = why;
    if (o && typeof o.now === 'number') online = o.now;
    if (o && typeof o.max === 'number' && o.max > 0) max = o.max;
    if (o && typeof o.line === 'number' && o.line > 0) line = o.line;
    if (o && o.full === true) full = true;
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
function worldFull(online) {
  // The people in the world now, not max: max counts the staff seats, which
  // somebody told to wait cannot take, so "30 are in the world" at 25 is wrong.
  return 'Thornswood is full right now' + (online > 0 ? ': ' + online + ' people are in the world, the most it holds' : '') +
    ' at once during the alpha. Pick your character anyway: you will wait at the menu with your ' +
    'place in line on screen, and join by yourself when a seat frees.';
}

/*
  The most the world holds, for the home page and /api/public, when the
  server has not said (#481). Patrick, 29 Sep: "I still want it to say N of
  25 anyway"; 12 Oct, it is every seat, the staff seats too, "of 30".
  records\most-online.json is the one place the number lives: read here
  when the site runs from the repository (main's people and staffSeats), and
  otherwise the main feed's maxOnline, which Publish-Update.ps1 writes from
  that same file as the same seats and which the site on the VPS already
  serves. The server's own max still wins.
*/
const MOST_ONLINE_RECORD = path.join(ROOT, '..', 'records', 'most-online.json');
let mostOnlineSeen = { file: '', mtime: -1, size: -1, v: 0 };
function mostOnlineFallback() {
  for (const file of [MOST_ONLINE_RECORD, feedFile('feed')]) {
    if (!file) continue;
    let st;
    try { st = fs.statSync(file); } catch (e) { continue; }
    if (mostOnlineSeen.file === file && mostOnlineSeen.mtime === st.mtimeMs && mostOnlineSeen.size === st.size) {
      if (mostOnlineSeen.v > 0) return mostOnlineSeen.v;
      continue;
    }
    let v = 0;
    try {
      const doc = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, '')) || {};
      const n = file === MOST_ONLINE_RECORD
        ? Number(doc.people) + (Number(doc.staffSeats) > 0 ? Number(doc.staffSeats) : 0)
        : Number(doc.maxOnline);
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
    // existsSync answers false rather than throwing, so no try (#2736). The
    // error's name or code and never its message: a newer Node puts a piece
    // of the text in a parse error's message, and these files hold Discord
    // ids and addresses.
    if (fs.existsSync(p)) {
      console.error('[thornswood-docs] JSON will not parse, using fallback for ' + p + ': ' + ((e && (e.code || e.name)) || 'unknown'));
    }
    return fallback;
  }
};
const putJson = (p, o) => putFile(p, () => JSON.stringify(o, null, 2));
const putFile = (p, text) => {
  // Same-folder temp + rename so a crash mid-write cannot leave truncated
  // JSON that jsonFile would then quietly replace with the empty fallback
  // (bans, linked accounts, inbox, and the rest of putJson callers), or a
  // moderation.log cut short by its keeping time (#2353). text is the body,
  // or a function that makes it, so a body that will not stringify is a
  // failed write like any other.
  // A temp file that will not go is said, by its name and the error code
  // (#2736): it holds a whole copy of the file, and a folder full of them is
  // otherwise found by somebody wondering where the disk went. One that was
  // never made is not there to go, and is tested for.
  // A held file that is there and will not read is never written over
  // (#2180, heldNow says it on the log): the write it would be is the empty
  // fallback plus one row, which is every other row gone.
  if (heldShape(p) && heldNow(p).broken) return false;
  const tmp = path.join(path.dirname(p), '.' + path.basename(p) + '.' + process.pid + '.tmp');
  const dropTmp = () => {
    if (!fs.existsSync(tmp)) return;
    try { fs.unlinkSync(tmp); }
    catch (e2) { console.error('[thornswood-docs] could not remove ' + tmp + ' (' + (e2.code || e2.message) + ')'); }
  };
  try {
    const body = typeof text === 'function' ? text() : String(text);
    fs.writeFileSync(tmp, body, 'utf8');
    try { fs.renameSync(tmp, p); }
    catch (e) {
      // Windows: rename onto an existing file can fail; replace then drop tmp.
      try { fs.copyFileSync(tmp, p); } finally { dropTmp(); }
    }
    return true;
  } catch (e) {
    dropTmp();
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
    // The page is still saved when its .bak cannot be made, and that is said
    // (#2736), so the undo that is not there is not found out when it is
    // needed.
    if (fs.existsSync(p)) {
      try { fs.copyFileSync(p, p + '.bak'); }
      catch (e) { console.error('[thornswood-docs] could not keep ' + path.basename(p) + '.bak before saving it (' + (e.code || e.message) + ')'); }
    }
    fs.writeFileSync(p, text, 'utf8');
    return true;
  } catch (e) { return false; }
}

const BOARDFILE = path.join(DATA, 'board.json');
const readBoard = () => jsonFile(BOARDFILE, {});
// The bot's lists (#3140), or null when there is no file yet or it will not
// read (jsonFile says which).
const readLists = () => jsonFile(LISTS, null);
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
  // No boards file yet is the first save and has nothing to keep; one that is
  // there and cannot be copied is said, and the save goes ahead (#2736).
  if (fs.existsSync(BOARDFILE)) {
    try { fs.copyFileSync(BOARDFILE, BOARDFILE + '.bak'); }
    catch (e) { console.error('[thornswood-docs] could not keep ' + path.basename(BOARDFILE) + '.bak before saving a board (' + (e.code || e.message) + ')'); }
  }
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
// NO ADDRESS IS KEPT. privacy.md says the sign-in log is the only thing on
// the site holding one. This table holds a hash of it under a key made fresh at every
// start and never written anywhere, and forgets it after a day. That is also
// why the cap per sender lives here at the door rather than in inbox.json:
// capping the file per sender would mean writing who sent each report into it.
//
// TICKETS AND REPORTS ARE TRIMMED APART. Each kind keeps the newest 2000 the
// shared list used to keep, so nothing posted to the public page can push a
// ticket out, and a pile of tickets cannot push a report out either.
//
// AND KEPT FOR INBOX_DAYS, THEN DROPPED (#2353). The count was the only rule,
// so on a quiet server a report, a call for help or an application lived for
// as long as fewer than 2000 came after it, which could be years, and the
// privacy page gave no time at all. Decided by Patrick on 12 October: a
// keeping time for each store, enforced in code. 365 days, the same as
// session records and chat, so a report has the session and the chat it is
// about behind it for exactly as long as they exist. A row's time is its at;
// a row with no usable time is kept, as the sign-in log keeps one, because
// a guess that deletes a report is the wrong way to be wrong. The ageing runs
// on every write, on the hub's read (so nothing past the window is shown),
// and in the hourly retention sweep (sweepInbox), with nothing sent needed.
const REPORT_HOUR = 5;
const REPORT_DAY = 20;
const INBOX_KEEP = 2000;
const INBOX_DAYS = 365;
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

/* CLOUDFLARE TURNSTILE ON THE REPORT FORM (#3216). The report form is the one
   form anybody can send without signing in, on purpose, so it is the one a
   script can fill from anywhere. The gallery's forms and the hub need a
   Discord sign in with a role, which a script does not have, and the member
   password's form is off once Discord sign in is set up. Patrick's answer on
   22 Oct 2026 was to put Turnstile on the site's forms; this is the form that
   needs it.

   The page draws the widget with the site key (/api/report/form), and the
   widget gives it a one-time pass that goes with the report. The site asks
   Cloudflare whether that pass is good, with the secret and the sender's
   address, before it keeps anything. Both keys empty, as on a copy on your
   machine, is no widget and no check, never one without the other: a page
   that drew no widget would otherwise have every report refused. */
const TURNSTILE_VERIFY = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';
function turnstileOn() {
  return typeof cfg.turnstileSiteKey === 'string' && cfg.turnstileSiteKey.length > 0 &&
         typeof cfg.turnstileSecret === 'string' && cfg.turnstileSecret.length > 0;
}
/* 'yes', 'no', or 'unasked' when Cloudflare did not answer inside the same
   ten seconds every other outside question gets (post()). The action is the
   one the page draws the widget with, so a pass made on another page of
   another site with the same key would not do. */
async function turnstilePasses(token, addr) {
  const t = String(token || '');
  if (!t || t.length > 2048) return 'no';
  let said;
  try {
    said = await post(TURNSTILE_VERIFY, { secret: cfg.turnstileSecret, response: t, remoteip: addr || '' });
  } catch (e) {
    // post() is the Discord helper and names Discord when nothing came back.
    console.error('[thornswood] turnstile: Cloudflare did not answer the check (' +
                  (e && e.discordSilent ? 'no answer in ten seconds' : (e && e.name) || 'error') + ')');
    return 'unasked';
  }
  if (said && said.success === true && said.action === 'report') return 'yes';
  // The error codes say why (timeout-or-duplicate, invalid-input-response);
  // never the pass itself or the secret.
  console.log('[thornswood] turnstile: a report was refused, Cloudflare said ' +
              JSON.stringify((said && said['error-codes']) || []) +
              (said && said.success === true ? ' with action ' + JSON.stringify(String(said.action || '')) : ''));
  return 'no';
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

function trimInbox(rows, now) {
  const cut = (Number(now) || Date.now()) - INBOX_DAYS * 86400000;
  let tickets = 0, reports = 0;
  return (Array.isArray(rows) ? rows : []).filter((r) => {
    const at = Number(r && r.at);
    if (isFinite(at) && at > 0 && at < cut) return false;
    return (r && r.kind === 'ticket') ? ++tickets <= INBOX_KEEP : ++reports <= INBOX_KEEP;
  });
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
  // No downloads folder is no downloads. One that is there and cannot be
  // listed is said (#2736), since the page then offers nothing and the log
  // is the only place that says it is the folder and not the build.
  if (fs.existsSync(FILES)) {
    try { names = fs.readdirSync(FILES); }
    catch (e) { console.error('[thornswood-docs] could not list the downloads in ' + FILES + ' (' + (e.code || e.message) + ')'); }
  }
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
  galleryPendingWrite = run.catch(() => {
    /* Not dropped: the caller has run, and hears the failure there (the
       upload answers it through failed). This only keeps the next write from
       waiting on a broken one. */
  });
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

/*
  SMALLER COPIES OF A GALLERY PICTURE (#3218). Every picture went out as it
  was uploaded: the first on the front page was 1.15 MB at 2563 by 1440 and
  drawn at about 1229 by 514. The site cannot make a smaller copy, because
  node reads and writes no pictures and the site installs nothing, so the
  one that sends the picture makes them (Patrick's answer on the report
  page, 22 Oct 2026, option B): the upload page and the launcher's gallery
  button each send an 800 and a 1600 pixel wide copy after the picture, one
  for each width the picture is wider than, over POST /api/gallery/copy.

  WHAT GOES PUBLIC IS WHAT STAFF SAW. The site cannot look at a picture, so
  it cannot tell that a copy shows the same thing as the picture it is a
  copy of. What it can read is the width and height a file says it has
  (pictureSize), and a copy is refused unless it is exactly its width and
  the picture's shape. The rest is staff: the hub and the launcher show the
  copies on the waiting card beside the picture, and Accept says which
  copies it showed (copies on /api/gallery/approve). Only those go on the
  gallery. A launcher from before this sends no copies on Accept, so a
  picture it accepts goes out at full size, as every picture did.

  The sender may send each copy once, and only while the picture waits, so
  a copy cannot change between staff looking at it and accepting it. Staff
  may send or replace one at any time from the hub, made in their own
  browser from the picture they are looking at; that is how a picture
  accepted at full size gets its copies.

  A copy lives in uploads/small as <picture>.w<width>.webp or .jpg, is
  served at /shot/<picture>?w=<width> once the picture is on the gallery and
  at /up/<picture>?w=<width> to staff while it waits, and goes when the
  picture's file goes: deleteUpload takes the copies with it, so every door
  and sweep that deletes a picture deletes them too. gallery.json names the
  copies in the item's srcset, so /api/public and /api/gallery hand them
  out with nothing worked out per request.
*/
const SMALL_WIDTHS = [800, 1600];
const SMALL_KINDS = ['.webp', '.jpg'];
const SMALL_CAP = 8 * 1024 * 1024;
const UP_SMALL = path.join(UP, 'small');
function smallFile(name, width, ext) {
  return path.join(UP_SMALL, String(name) + '.w' + width + ext);
}
// The copy at that width on disk, or '' when there is none.
function smallCopy(name, width) {
  for (const ext of SMALL_KINDS) {
    const file = smallFile(name, width, ext);
    if (file.startsWith(UP_SMALL + path.sep) && fs.existsSync(file)) return file;
  }
  return '';
}
/* The width and height a PNG, JPEG, GIF or WebP file is shown at, read off
   its header, or null when the header cannot be read. A JPEG's size is in
   its frame header, after any metadata, so the markers are walked; a camera
   JPEG may say in its Exif that it is turned a quarter, and is then shown
   with width and height the other way round, as browsers show it and as a
   copy of it is made. */
function pictureSize(file) {
  let b;
  try {
    const fd = fs.openSync(file, 'r');
    try {
      b = Buffer.alloc(Math.min(fs.fstatSync(fd).size, 1048576));
      fs.readSync(fd, b, 0, b.length, 0);
    } finally { fs.closeSync(fd); }
  } catch (e) {
    console.error('[thornswood-docs] could not read the size of ' + path.basename(String(file)) + ' (' + (e.code || e.message) + ')');
    return null;
  }
  const size = (w, h) => (w > 0 && h > 0 ? { w: w, h: h } : null);
  if (b.length >= 24 && b.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))) {
    return size(b.readUInt32BE(16), b.readUInt32BE(20));
  }
  if (b.length >= 10 && /^GIF8[79]a$/.test(b.subarray(0, 6).toString('ascii'))) {
    return size(b.readUInt16LE(6), b.readUInt16LE(8));
  }
  if (b.length >= 30 && b.subarray(0, 4).toString('ascii') === 'RIFF' && b.subarray(8, 12).toString('ascii') === 'WEBP') {
    const chunk = b.subarray(12, 16).toString('ascii');
    if (chunk === 'VP8 ') return size(b.readUInt16LE(26) & 0x3fff, b.readUInt16LE(28) & 0x3fff);
    if (chunk === 'VP8L') {
      const bits = b.readUInt32LE(21);
      return size((bits & 0x3fff) + 1, ((bits >>> 14) & 0x3fff) + 1);
    }
    if (chunk === 'VP8X') return size(b.readUIntLE(24, 3) + 1, b.readUIntLE(27, 3) + 1);
    return null;
  }
  if (b.length >= 4 && b[0] === 0xff && b[1] === 0xd8) {
    let i = 2, turned = false;
    while (i + 9 < b.length) {
      if (b[i] !== 0xff) return null;
      const m = b[i + 1];
      if (m === 0xff) { i++; continue; }
      // SOF0 to SOF15 hold the size; C4, C8 and CC are other tables.
      if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) {
        const w = b.readUInt16BE(i + 7), h = b.readUInt16BE(i + 5);
        return turned ? size(h, w) : size(w, h);
      }
      if (m === 0xe1 && i + 4 + 14 <= b.length && b.subarray(i + 4, i + 10).toString('latin1') === 'Exif\0\0') {
        turned = exifTurned(b, i + 10, Math.min(b.length, i + 2 + b.readUInt16BE(i + 2)));
      }
      if (m === 0xd8 || m === 0x01 || (m >= 0xd0 && m <= 0xd7)) { i += 2; continue; }
      i += 2 + b.readUInt16BE(i + 2);
    }
  }
  return null;
}
// Whether the Exif block at start (its TIFF header) to end says the picture
// is turned a quarter: orientation 5 to 8, tag 0x0112 in the first IFD.
function exifTurned(b, start, end) {
  const order = b.subarray(start, start + 2).toString('latin1');
  if (order !== 'II' && order !== 'MM') return false;
  const u16 = (at) => (order === 'II' ? b.readUInt16LE(at) : b.readUInt16BE(at));
  const u32 = (at) => (order === 'II' ? b.readUInt32LE(at) : b.readUInt32BE(at));
  const ifd = start + u32(start + 4);
  if (ifd + 2 > end) return false;
  const count = u16(ifd);
  for (let k = 0; k < count; k++) {
    const at = ifd + 2 + k * 12;
    if (at + 12 > end) return false;
    if (u16(at) === 0x0112) {
      const turn = u16(at + 8);
      return turn >= 5 && turn <= 8;
    }
  }
  return false;
}
// The widths a waiting picture has copies of, as the queue lists them.
function pendingCopies(entry) {
  return (Array.isArray(entry && entry.copies) ? entry.copies : [])
    .map(Number).filter((n) => SMALL_WIDTHS.indexOf(n) >= 0);
}
/* The srcset gallery.json keeps for a picture: each copy listed, then the
   picture itself at its own width, which the site reads off its header. ''
   with no copy, or when the picture's width cannot be read. */
function shotSrcset(name, widths) {
  const listed = SMALL_WIDTHS.filter((n) => widths.indexOf(n) >= 0 && smallCopy(name, n));
  if (!listed.length) return '';
  const full = pictureSize(path.join(UP, String(name)));
  if (!full) return '';
  // Escaped, because a srcset is split on spaces and a name may hold one.
  const url = '/shot/' + encodeURIComponent(String(name));
  return listed.map((n) => url + '?w=' + n + ' ' + n + 'w').concat(url + ' ' + full.w + 'w').join(', ');
}
// The copy widths a gallery item's srcset names.
function srcsetWidths(srcset) {
  const out = [];
  for (const m of String(srcset || '').matchAll(/\?w=(\d+) /g)) {
    if (SMALL_WIDTHS.indexOf(Number(m[1])) >= 0) out.push(Number(m[1]));
  }
  return out;
}

/*
  Deleting an upload, said truthfully (#2352, #2354). Both doors that delete a
  file used to catch the failure and answer ok, so a picture somebody asked
  to have removed could stay on disk with staff told it had gone. This
  answers { ok } or { ok: false, code } and writes one line to the site's
  log for a failure: the file's name and the error code, never what it holds.
  A file already gone is gone, which is what was asked.

  A gallery picture's smaller copies go with it (#3218), first, so a copy is
  never left behind a picture that went. One that will not go is said the
  same way and the picture stays, so the next sweep asks again for both.
*/
function deleteUpload(name) {
  const file = path.join(UP, String(name));
  if (!file.startsWith(UP + path.sep)) return { ok: false, code: 'BADNAME' };
  const files = [];
  for (const width of SMALL_WIDTHS) {
    for (const ext of SMALL_KINDS) files.push(smallFile(name, width, ext));
  }
  files.push(file);
  for (const one of files) {
    try {
      fs.unlinkSync(one);
    } catch (e) {
      const code = (e && e.code) || 'unknown';
      if (code === 'ENOENT') continue;
      retentionSay('gallery', { event: 'delete-failed', file: path.relative(UP, one), code: code });
      return { ok: false, code: code };
    }
  }
  return { ok: true };
}

/* A gallery submission staff removed and whose file stayed on disk: marked
   on uploads.json by DELETE /api/gallery/approved, and never served again. */
function uploadRemoved(name) {
  const m = jsonFile(UPMETA, {})[String(name)];
  return !!(m && m.removed);
}

/*
  HOW LONG A REMOVED SUBMISSION'S FILE STAYS (#2352). Decided by Patrick on
  12 October, option C: removing a submission deletes its file, and a picture
  taken down after a report is kept, unshown, for GALLERY_HOLD_DAYS so staff
  can look into the report, then deleted. "After a report" is read off the
  site's own record rather than off whichever button was pressed: a
  submission with an open report against it in gallery-reports.json when it
  is removed is held, with those reports beside it on uploads.json, and every
  other removal deletes the file there and then. The hub, the launcher's
  Delete and its Take down all reach the same door, so the rule is the same
  whichever one staff use.

  pruneRemovedUploads is the other half, run by the retention timer: a
  removed file whose hold has ended, or that was never held (one kept by the
  hub's old Cancel, or one whose delete failed at the time), is deleted, and
  a delete that fails is said in the site's log by deleteUpload, file and
  code, never what it holds. Failing to delete a file that the nightly backup
  or a virus scan has open is outside our control; the next hour asks again
  and says so again, rather than going quiet.
*/
const GALLERY_HOLD_DAYS = 30;
function pruneRemovedUploads(now) {
  const at = Number(now) || Date.now();
  const meta = jsonFile(UPMETA, {});
  const out = { deleted: 0, held: 0, failed: [] };
  let changed = false;
  for (const name of Object.keys(meta)) {
    const m = meta[name];
    if (!m || !m.removed) continue;
    if (Number(m.heldUntil) > at) { out.held++; continue; }
    const gone = deleteUpload(name);
    if (gone.ok) { delete meta[name]; changed = true; out.deleted++; }
    else out.failed.push({ file: name, code: gone.code });
  }
  if (changed && !putJson(UPMETA, meta)) {
    retentionSay('gallery', { event: 'note-write-failed', deleted: out.deleted });
  }
  return out;
}

function listUploads() {
  const meta = jsonFile(UPMETA, {});
  const out = [];
  let names = [];
  // As listFiles (#2736): no folder is no uploads, a folder that cannot be
  // listed is said.
  if (fs.existsSync(UP)) {
    try { names = fs.readdirSync(UP); }
    catch (e) { console.error('[thornswood-docs] could not list the uploads in ' + UP + ' (' + (e.code || e.message) + ')'); }
  }
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
      removed: !!m.removed,
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
   and /gallery/submit write different things once the bytes are down. A
   smaller copy of a gallery picture (copy true, #3218) counts its bytes
   against the hour and not its file, so sending a picture and its two
   copies is one of the 40 files an hour, as the picture alone was. */
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
function receiveUpload(req, res, asked, cap, allow, saved, copy) {
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
  if (!copy) budget.count++;
  budget.active++;
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
  // The write's own error code is kept, so the 500 below can say it (#2736).
  out.on('error', (e) => { broke = (e && e.code) || 'unknown'; });
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
      // The half file goes. It was made above with wx, so it is there; one
      // that will not go is said, by its name and the code (#2736).
      let removed = false;
      try { fs.unlinkSync(dest); removed = true; }
      catch (e) { console.error('[thornswood-docs] could not remove the half upload ' + name + ' (' + (e.code || e.message) + ')'); }
      if (timedOut) return send(res, 408, JSON.stringify({error:'That upload took too long. Try again with a smaller file.'}), null, {Connection:'close'});
      if (quotaExceeded) return send(res, 429, JSON.stringify({error:'This connection has uploaded 500 MB in the last hour. Try again later.'}),
        null, {'Retry-After':String(Math.max(1, Math.ceil((budget.start + 3600000 - Date.now()) / 1000))), Connection:'close'});
      if (invalid) return sendJson(res, 415, {error:'The file contents do not match its image or recording type.'});
      if (over) return send(res, 413, JSON.stringify({ error: 'that file is over ' + Math.round(cap / 1048576) + ' MB' }),
                            null, { Connection: 'close' });
      // destroy() does not throw, so no try (#2736). A sender that went has
      // nobody left to answer, so the log is the only record it leaves
      // (#3062), said once the half file is gone.
      if (cut) {
        if (removed) console.log('[thornswood-docs] upload cut off after ' + got + ' bytes on ' +
                                 JSON.stringify(String(req.url || '').split('?')[0].slice(0, 200)) + ', the half file is removed');
        res.destroy();
        return;
      }
      console.error('[thornswood-docs] could not write the upload ' + name + ' (' + broke + ')');
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
  const nowBans = bansNow();
  const stale = hit && hit.v && (nowBans.broken ? !hit.v.bansBroken
    : (hit.v.byFile && !banActive(nowBans.table[String(id)] || null, Date.now())));
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
    // "dev" is staff in the game (access.dev: Owner, Co-Owner, and the Dev,
    // Gamemaster and Loremaster ranks with their leads, #3317), used by the
    // gallery queue and reports. Not the admin pair alone.
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
/* Who is sending something to the gallery: a picture, a report, or a
   picture's smaller copies (#3218). A signed-in Discord account that may
   play, or the hub member cookie (password bootstrap / staff). Hub "member"
   alone used to be the only web door, and with Discord live that meant only
   admins could submit from the site. Otherwise a launcher ticket verified
   the way the door verifies it: read it, ask Discord for the standing, and
   hold it to the same answers /api/play/join gives, so a banned or departed
   account cannot put a picture in the queue. signIn is what a caller with
   neither is told. dev is whether the account holds a staff role. */
async function gallerySender(url, w, signIn) {
  if (w.play || w.member) return { ok: true, from: 'web', discordId: w.id || '', dev: !!w.dev };
  const t = readTicket(url.searchParams.get('ticket'));
  // Signed in, and Discord did not answer in time (#467): say that.
  if (!t && w.id && w.lookupFailed) return { ok: false, code: 503, body: { ok: false, why: 'could not ask Discord', error:
    'Thornswood could not ask Discord about your account just now. Try again in a minute.' } };
  if (!t) return { ok: false, code: 401, body: { ok: false, why: 'link', error: signIn } };
  const st = await within(standing(t.d), PLAY_ANSWER_MS, () => standingLate(t.d));
  standCache.delete(String(t.d));
  if (st.lookupFailed && !st.admin) return { ok: false, code: 503, body: discordUnasked() };
  // Banned before the guild check (#1022). standing() leaves inGuild false
  // when bans.json already refused the account.
  if (st.banned) return { ok: false, code: 403, body: { ok: false, why: 'banned', error:
    'That Discord account is banned from Thornswood.' } };
  if (!st.inGuild) return { ok: false, code: 403, body: { ok: false, why: 'guild', error:
    'That Discord account is not in the Thornswood Discord.' } };
  if (!st.play) return { ok: false, code: 403, body: { ok: false, why: 'role', error:
    'That Discord account has no role that lets it in yet.' } };
  return { ok: true, from: 'launcher', discordId: String(t.d), dev: !!st.dev };
}

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
   same-origin files, so style-src needs only 'self'. Keep this string in one
   place so send(), Range replies, and the request-level setHeader cannot
   drift.

   The one other site in it is Cloudflare Web Analytics (#3218, Patrick's
   answer on 22 Oct 2026). Cloudflare writes its beacon into every page it
   carries, so the page never names it: the script comes from
   static.cloudflareinsights.com and posts what it measured to
   cloudflareinsights.com. With script-src 'self' alone every page raised a
   CSP error in the console and Cloudflare counted nothing. The privacy page
   names it. It sets no cookie and keeps nothing on the visitor's machine.

   The third is Cloudflare Turnstile on the report form (#3216, Patrick's
   answer on 22 Oct 2026): its script and the frame it draws the check in
   both come from challenges.cloudflare.com. The privacy page names it. */
const CSP_HEADER = "default-src 'self'; script-src 'self' https://static.cloudflareinsights.com https://challenges.cloudflare.com; style-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; font-src 'self'; connect-src 'self' https://cloudflareinsights.com; frame-src https://challenges.cloudflare.com; frame-ancestors 'self'; base-uri 'self'; form-action 'self'; object-src 'none'";
/* A NONCE ON EVERY ANSWER (#3216). Bot Fight Mode, on by Patrick's answer on
   22 Oct 2026, turns on Cloudflare's JavaScript Detections, which cannot be
   turned off on its own and writes a small inline script into every page
   Cloudflare carries. script-src 'self' refuses any inline script, so every
   page would raise a CSP error and the detection would never run. Cloudflare
   reads a nonce out of this header and puts it on the script it writes in, so
   each answer gets a fresh one (handle() makes it). The site's own pages
   carry no inline script and never use it; a nonce is only good for the one
   answer it came with, so it opens nothing to anybody else. */
function cspFor(res) {
  const n = res && res.cspNonce;
  return n ? CSP_HEADER.replace("script-src 'self'", "script-src 'self' 'nonce-" + n + "'") : CSP_HEADER;
}
function send(res, code, payload, type, extra) {
  // Defense in depth (#1366 / #1474): conservative CSP (this page and the hub
  // name nothing on other sites, and CSS and JS are external same-origin
  // files; the analytics beacon Cloudflare adds is the one exception, above),
  // frame-ancestors self so the hub cannot be iframed for clickjacking, and a
  // referrer policy that does not leak path on cross-origin navigations.
  // A page names its files with their hashes (versionAssets, #3218), here so
  // that no page sent can miss it.
  if (/^text\/html\b/.test(String(type || '')) && payload) payload = versionAssets(payload);
  res.writeHead(code, Object.assign({
    'Content-Type': type || 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': cspFor(res),
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
      'content-security-policy': cspFor(res),
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
    'content-security-policy': cspFor(res),
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
      // destroy() does not throw, so no try (#2736).
      if (req) req.destroy();
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
  // Only a body that is a JSON object is read for it (#2736). Cloudflare in
  // front of Discord answers some 429s with a page, which has no wait in it
  // and falls through to -1; a body that looks like JSON and is not is said.
  if (!(s >= 0) && /^\s*\{/.test(String(text || ''))) {
    try { s = parseFloat(JSON.parse(text).retry_after); }
    catch (e) { console.error('[thornswood] discord rate limit answer is not readable JSON (' + e.name + '), so it names no wait'); }
  }
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
      req.destroy();
    }, DISCORD_ASK_MS);
    req.on('error', (e) => settle({ ok: false, status: 0, body: null, why: 'could not reach Discord: ' + e.message }));
  });
}

/*
  The one write the site makes to Discord (#2551): give or take a member's
  role, for a Jarl's office change made in the game (changeOffice). PUT or
  DELETE on the member's role, with the reason Discord's audit log shows.
  Discord answers 204 when it is done. A 429 sets the same quiet time
  discordGet keeps, so no request is sent into a rate limit; nothing here
  retries, and the Jarl is told to try again.
*/
function discordWrite(method, path, reason) {
  return new Promise((resolve) => {
    if (!cfg.discord.botToken || !cfg.discord.guildId) {
      return resolve({ ok: false, status: 0, why: 'no bot token set' });
    }
    if (discordQuietMs() > 0) {
      return resolve({ ok: false, status: 429, why: 'rate limited by Discord' });
    }
    let settled = false;
    let timer = null;
    const settle = (v) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (!v.ok) console.error('[thornswood] discord ' + method + ' ' + path + ': ' + v.why);
      resolve(v);
    };
    const req = https.request({
      hostname: 'discord.com', path: '/api/v10' + path, method: method,
      headers: { Authorization: 'Bot ' + cfg.discord.botToken, 'Content-Length': 0,
                 'X-Audit-Log-Reason': encodeURIComponent(String(reason || '').slice(0, 400)) }
    }, (res) => {
      let out = '';
      res.on('data', (d) => out += d);
      res.on('error', () => settle({ ok: false, status: 0, why: 'Discord stopped partway through its answer' }));
      res.on('end', () => {
        const hdr = res.headers || {};
        if (res.statusCode === 429) {
          const wait = discordWaitMs(hdr, out);
          discordQuietUntil = Math.max(discordQuietUntil, Date.now() + (wait >= 0 ? wait : 1000));
        }
        if (res.statusCode === 204 || res.statusCode === 200) return settle({ ok: true, status: res.statusCode });
        let why = 'Discord answered ' + res.statusCode;
        if (res.statusCode === 401) why = 'the bot token is wrong or has been reset';
        else if (res.statusCode === 403) why = 'the bot may not change that role';
        else if (res.statusCode === 404) why = 'Discord does not know that member or role';
        else if (res.statusCode === 429) why = 'rate limited by Discord';
        settle({ ok: false, status: res.statusCode, why });
      });
    });
    timer = setTimeout(() => {
      settle({ ok: false, status: 0, why: 'Discord did not answer inside ten seconds' });
      req.destroy();
    }, DISCORD_ASK_MS);
    req.on('error', (e) => settle({ ok: false, status: 0, why: 'could not reach Discord: ' + e.message }));
    req.end();
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
/* THE BAN LIST FAILS CLOSED (#2186), AND SO DOES EVERY FILE PLAY AND
   IDENTITY REST ON (#2180). jsonFile() hands back its fallback for a file
   that is there but will not parse. So a bans.json cut short by a crash read
   as no bans at all and let every banned account in; a pk.json read as
   nobody dead for good; and a pk.json, linked.json, sessions.json or
   signins.json read as empty was written straight back as empty plus one
   row at the next PK, Play, session or sign-in, and every row it held was
   gone. These five are read through readHeld(): a missing file is the
   normal empty one, and a file that is there but will not read in its shape
   is BROKEN. While one is broken:
     - putFile writes nothing over it, so it is still there to repair;
     - bans.json, pk.json or linked.json broken lets nobody in to play
       (standing says banned for bans.json, characterBar bars every
       character, /api/allowed lists nobody), because who is banned, who is
       dead for good and who holds which character are not known;
     - the site says so on its log once each time it breaks and mends, and
       /api/ready answers 503 naming it, asked once at start too.
   The pages stay up. A broken file is repaired by hand on the box, from the
   backup, and the next request reads it again. */
function heldShape(p) {
  if (p === BANS || p === PK || p === LINKED) return 'table';
  if (p === SESSIONS || p === ATTEMPTS) return 'list';
  return '';
}
function heldGatesPlay(p) { return p === BANS || p === PK || p === LINKED; }
function readHeld(p) {
  const shape = heldShape(p);
  const empty = shape === 'list' ? [] : {};
  let text;
  try { text = fs.readFileSync(p, 'utf8'); }
  catch (e) { return (e && e.code === 'ENOENT') ? { doc: empty, broken: '' } : { doc: empty, broken: 'cannot be read (' + ((e && e.code) || 'unknown') + ')' }; }
  let doc;
  try { doc = JSON.parse(text.replace(/^\uFEFF/, '')); } catch (e) { return { doc: empty, broken: 'will not parse' }; }
  if (shape === 'list' ? !Array.isArray(doc) : (!doc || typeof doc !== 'object' || Array.isArray(doc))) {
    return { doc: empty, broken: shape === 'list' ? 'is not a list' : 'is not a table' };
  }
  return { doc, broken: '' };
}
const heldSaid = new Map();
function heldNow(p) {
  const r = readHeld(p);
  const was = heldSaid.get(p) || '';
  if (r.broken && was !== r.broken) {
    if (p === BANS) console.error('[thornswood-docs] BANS BROKEN: ' + BANS + ' ' + r.broken + '. Nobody is let in to play until it is repaired (#2186).');
    else console.error('[thornswood-docs] STATE BROKEN: ' + p + ' ' + r.broken + '. ' +
                       (heldGatesPlay(p) ? 'Nobody is let in to play, and nothing is written over it,' : 'Nothing is written over it') +
                       ' until it is repaired (#2180).');
  } else if (!r.broken && was) {
    console.log('[thornswood-docs] ' + path.basename(p) + ' reads again' + (p === BANS ? '; play is open to those not banned.' : '.'));
  }
  heldSaid.set(p, r.broken);
  return r;
}
/* Every held file that is broken now, by name and why, for /api/ready. */
function heldBroken() {
  const out = [];
  for (const p of [BANS, PK, LINKED, SESSIONS, ATTEMPTS]) {
    const r = heldNow(p);
    if (r.broken) out.push({ file: path.basename(p), why: r.broken, play: heldGatesPlay(p) });
  }
  return out;
}
function bansNow() {
  const r = heldNow(BANS);
  return { table: r.doc, broken: r.broken };
}
const BANS_BROKEN_WHY = 'the ban list cannot be read, so nobody can be let in until staff repair it';
const STATE_BROKEN_WHY = 'the site cannot read who holds which character or who is dead for good, so nobody can be let in until staff repair it';
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
// The game servers write their own (for-bot\moderation.log beside each, #2321).
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
  // Who is dead for good and who holds which character, unknown while
  // pk.json or linked.json will not read (#2180): no character is let in.
  const readP = heldNow(PK), readL = heldNow(LINKED);
  if (readP.broken || readL.broken) return { pk: false, shut: true, why: STATE_BROKEN_WHY, until: 0 };
  const pk = readP.doc;
  if (pkActive(pk[String(n)])) {
    return { pk: true, at: Number((pk[String(n)] || {}).at) || 0 };
  }
  const readB = bansNow();
  if (readB.broken) return { pk: false, why: BANS_BROKEN_WHY, until: 0 };
  const byChar = readB.table;
  const b = byChar && byChar['p:' + n];
  if (banActive(b, now)) return { pk: false, why: String(b.why || ''), until: Number(b.until) || 0 };
  return null;
}
/* Whether a pk.json row is a PK that holds: there, and not undone by an admin. */
function pkActive(row) {
  return !!row && typeof row === 'object' && !row.undone;
}
/* Every profile staff have killed for good, as numbers. A pk.json that will
   not read carries broken on the list, and the door lets nobody in (#2180). */
function pkProfiles() {
  const readP = heldNow(PK);
  const table = readP.doc;
  const out = Object.keys(table).filter((k) => pkActive(table[k])).map(Number).filter((n) => n > 0);
  if (readP.broken) Object.defineProperty(out, 'broken', { value: 'pk.json ' + readP.broken });
  return out;
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
  const readB = bansNow();
  const table = readB.table;
  // An account's ban covers the characters linked.json gives it, so with
  // linked.json unreadable no account ban can be applied (#2180).
  const readL = heldNow(LINKED);
  const linked = readL.doc;
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
  // Carried on the list, not sent: the door reads it to let nobody in (#2186).
  const broken = readB.broken ? 'bans.json ' + readB.broken : (readL.broken ? 'linked.json ' + readL.broken : '');
  if (broken) Object.defineProperty(out, 'broken', { value: broken });
  return out;
}
/* A ban, made or replaced. The account's standing is asked again at once. */
function putBan(key, row) {
  const readB = bansNow();
  if (readB.broken) return false;
  // Through the keeping time on the way in (#2353), so a write never puts
  // back a ban that ran out more than STAFF_DAYS ago.
  const table = freshBans(readB.table, Date.now());
  const had = table[key] || {};
  const profiles = new Set([].concat(had.profiles || [], row.profiles || []).map(Number).filter((n) => n > 0));
  table[key] = Object.assign({}, row, { profiles: Array.from(profiles) });
  const ok = putJson(BANS, table);
  standCache.delete(key);
  return ok;
}
function dropBan(keys) {
  const readB = bansNow();
  if (readB.broken) return { was: false, ok: false };
  const table = freshBans(readB.table, Date.now());
  let was = false;
  for (const k of keys) {
    if (k && Object.prototype.hasOwnProperty.call(table, k)) { delete table[k]; was = true; standCache.delete(k); }
  }
  return { was, ok: !was || putJson(BANS, table) };
}
function putNote(key, row) {
  const notes = freshNotes(jsonFile(NOTES, {}), Date.now());
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
  const table = freshPk(jsonFile(PK, {}), Date.now());
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
  const now = freshPk(jsonFile(PK, {}), Date.now());
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
  // Nothing past its keeping time is shown (#2353), sweep or no sweep.
  const table = freshBans(jsonFile(BANS, {}), now);
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
  return { bans: out, notes: freshNotes(jsonFile(NOTES, {}), now), pk: freshPk(jsonFile(PK, {}), now), names };
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
/* The hourly sweep ages the file too. Rows went only when somebody signed in
   or opened the list, so on 18 Oct 41 rows holding an address sat past the
   30 days the privacy page gives them, two days after the last sign-in. */
function sweepSignIns(now) {
  const raw = jsonFile(ATTEMPTS, []);
  const rows = Array.isArray(raw) ? raw : [];
  const kept = freshSignIns(rows, now);
  const out = { rows: rows.length, kept: kept.length, written: false };
  if (kept.length === rows.length) return out;
  out.written = putJson(ATTEMPTS, kept);
  if (!out.written) retentionSay('signin', { event: 'write-failed', rows: rows.length, kept: kept.length });
  return out;
}
// ==== end thornswood signin ageing ====

function noteSignIn(req, me, st, back) {
  /* No try around the whole (#2736). The one failure the record can have,
     the write, is said below (#2354), and nothing else in here throws on
     what the callback hands it; a bug that does is the handler's 500 and
     its stack in site.log, not a sign in that is quietly not recorded. */
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
  // A write that fails leaves rows past thirty days in the file, so it is
  // said rather than dropped (#2354): the count, never what they hold.
  const kept = freshSignIns(rows, Date.now());
  if (!putJson(ATTEMPTS, kept)) {
    retentionSay('signin', { event: 'write-failed', rows: rows.length, kept: kept.length });
  }
}

/* Who played, when they started, when they stopped, and on which build.
 *
 * linked.json holds a last played stamp, which answers "has this person ever
 * pressed Play" and nothing else: not how long they were in, not whether they
 * are still in now, not which build it was. Djinn asked on 20 September for a
 * sheet testers are logged in and out of, and this is the record behind it.
 *
 * One row a session. Newest LAST, the way a log is written.
 *
 * KEPT FOR SESSIONS_DAYS, THEN DROPPED (#2350). The privacy page says session
 * records are kept for 365 days. Until 12 October the rows were only capped
 * by count, the newest 2000, so on a quiet server a row lived as long as
 * fewer than 2000 sessions came after it, which could be years. Decided by
 * Patrick on 12 October: age the rows by time, keep a row marked kept, and
 * run the ageing on a timer as well as when a session ends.
 *
 * A row's time is the later of its start and its end. A row with neither is
 * a corrupt row and is kept rather than guessed at, the way the sign-in log
 * keeps one. A row marked kept is evidence somebody chose to hold, and it is
 * never aged and never pushed out by the count either: before this, 2000
 * newer sessions pushed a kept row off the front and its logs lost their hold
 * with it.
 *
 * The count stays as a bound on the file's size: past 2000 rows the oldest
 * unkept ones go first, which is only ever sooner than the page says.
 *
 * The ageing runs on the way in (putSessions), on the way out (sessionRows,
 * so the hub never shows a row past the window), at start and every hour
 * (retentionSweep), with no session ending needed. */
const SESSIONS = path.join(DATA, 'sessions.json');
const SESSIONS_KEEP = 2000;
const SESSIONS_DAYS = 365;

function freshSessions(rows, now) {
  const cut = (Number(now) || Date.now()) - SESSIONS_DAYS * 86400000;
  const kept = (Array.isArray(rows) ? rows : []).filter((r) => {
    if (!r || typeof r !== 'object') return false;
    if (r.keep) return true;
    const at = Math.max(Number(r.end) || 0, Number(r.start) || 0);
    return !(at > 0 && at < cut);
  });
  let over = kept.length - SESSIONS_KEEP;
  if (over <= 0) return kept;
  return kept.filter((r) => {
    if (over > 0 && !r.keep) { over--; return false; }
    return true;
  });
}
function sessionRows() {
  const list = jsonFile(SESSIONS, []);
  return freshSessions(list, Date.now());
}
function putSessions(rows) {
  return putJson(SESSIONS, freshSessions(rows, Date.now()));
}
/* The timer's half for the rows. Writes only when something aged out, and a
   write that fails is said, the count and never what the rows hold (#2354).
   A file that is there and cannot be read is left alone: jsonFile answers []
   for it, and an empty list never writes over anything. */
function sweepSessions(now) {
  const raw = jsonFile(SESSIONS, []);
  const rows = Array.isArray(raw) ? raw : [];
  const kept = freshSessions(rows, now);
  const out = { rows: rows.length, kept: kept.length, written: false };
  if (kept.length === rows.length) return out;
  out.written = putJson(SESSIONS, kept);
  if (!out.written) retentionSay('session', { event: 'write-failed', rows: rows.length, kept: kept.length });
  return out;
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

/*
  A CRASH STAFF HAVE LOOKED AT (#2319, decided by Patrick on 12 Oct).

  A crash snapshot is every byte of the game's memory, 3.7 to 9.7 GB, and it
  never leaves the PC it was written on. Until this, the launcher kept only
  the newest, so the next crash on that install deleted the one before it
  whether anybody had read it or not: none of the four written from 29 Sep to
  6 Oct was. Now staff mark a crashed session looked at on the sessions page
  (/api/session-looked), and the launcher, which remembers which session each
  snapshot it holds crashed in, asks at its next check in which of those are
  marked (/api/play/join, snapshots in and lookedAt out) and deletes only
  those, or the oldest past two.

  Only a crash can be marked: a session whose trouble came from its crash.log
  (crashOf). The mark says who and when, like keep.
*/
function crashedRow(row) {
  return !!(row && row.troubleFile === 'crash.log');
}
function markLooked(row, on, by, now) {
  if (on) { row.looked = true; row.lookedBy = String(by || ''); row.lookedAt = Number(now) || Date.now(); }
  else { delete row.looked; delete row.lookedBy; delete row.lookedAt; }
  return row;
}
/* The most snapshot sessions one check in may ask about; the launcher
   remembers eight. */
const SNAPSHOTS_ASKED = 8;
/* Of the session ids a launcher asked about, the ones that are THIS account's
   and marked looked at. Another account's session is never answered for, so
   a check in cannot learn anything about somebody else's crashes. */
function lookedAtFor(rows, who, asked) {
  const list = Array.isArray(asked) ? asked : String(asked == null ? '' : asked).split(',');
  const out = [];
  for (const one of list.slice(0, SNAPSHOTS_ASKED)) {
    const key = sessionKey(one);
    if (!key || out.indexOf(key) >= 0) continue;
    const at = findSession(rows, key, who);
    if (at >= 0 && rows[at].looked) out.push(key);
  }
  return out;
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

  KEPT BY AGE, NOT BY THE ROLLING LIST. sessions.json is aged by
  SESSIONS_DAYS and also bounded at two thousand rows. Tying the logs to the
  rows would quietly delete the evidence for an old incident the moment two
  thousand newer sessions had happened, which on a public server is weeks.
  They are kept for SLOG_DAYS instead, the same 365 days, and a session whose
  row is marked kept is never pruned at all.

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

/* Written once. Returns 'saved', 'already', 'nothing' (no log in it worth
   keeping) or 'failed' (it could not be written, and that has been said). */
function putSessionLogs(key, who, logs) {
  try {
    if (!fs.existsSync(SLOGS)) fs.mkdirSync(SLOGS, { recursive: true });
    const file = slogFile(key);

    /* Write once. A second set for the same session is not written over the
       first; the attempt is recorded on the original so a replay shows up as
       what it is rather than as nothing.

       The one exception is a set that holds only a kept session's chat
       (#2166): the session was kept before the launcher had sent anything,
       so the file is there but the logs are not. Those logs are the first
       set, not a second one, and they go in beside the chat. */
    /* A first set that is there and will not read, or a replay that cannot
       be marked on it, is said in the site's log (#2736), the session key
       and the error and never what the set holds. Both used to be caught
       and dropped, so a replay of a set that had gone bad left no trace. A
       set that will not read is never written over: it is the evidence. */
    let keptChat = null;
    let first = null;
    const there = fs.existsSync(file);
    if (there) {
      try { first = JSON.parse(fs.readFileSync(file, 'utf8')) || null; }
      catch (e) {
        console.error('[thornswood-docs] session-logs ' + JSON.stringify({ event: 'set-unreadable', session: key, code: e.code || e.name }));
      }
      if (first && first.chatOnly && isObjectLike(first.chat)) keptChat = first.chat;
    }
    if (there && !keptChat) {
      if (first && typeof first === 'object') {
        first.resent = (Number(first.resent) || 0) + 1;
        first.resentAt = Date.now();
        try { fs.writeFileSync(file, JSON.stringify(first)); }
        catch (e) {
          console.error('[thornswood-docs] session-logs ' + JSON.stringify({ event: 'resend-unmarked', session: key, code: e.code || e.name }));
        }
      }
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

    const set = {
      session: key,
      who: String(who),      /* off the ticket, never off the body */
      at: Date.now(),
      bytes: total,
      sha256: hash,
      logs: keep
    };
    if (keptChat) set.chat = keptChat;
    fs.writeFileSync(file, JSON.stringify(set));
    return 'saved';
  } catch (e) {
    /* 'failed', not 'nothing' (#2736). A set the folder would not take was
       answered 200 stored false, the same as a set with no logs in it, so
       the launcher dropped the logs it had kept for the site and nothing
       was said. Now it is said, and /api/play/logs answers 500, which the
       launcher keeps the logs for and sends again at its next start. */
    console.error('[thornswood-docs] session-logs ' + JSON.stringify({ event: 'write-failed', session: key, code: e.code || e.name }));
    return 'failed';
  }
}

/*
  Old log sets go, by age.

  NOT by whether the session is still in sessions.json. That file is also
  bounded at two thousand rows, so tying the logs to it would delete the
  evidence for an old incident the moment two thousand newer sessions had
  happened, and on a public server that is weeks. A row marked kept is never
  pruned, and never pushed out of sessions.json by the count (#2350), so
  anything an argument rests on can be held indefinitely by marking it.
*/
/*
  A LOG SET THAT WILL NOT GO IS SAID (#2354). Each delete that fails used to
  be caught and dropped, and the whole prune was wrapped twice more, so a set
  past SLOG_DAYS that would not delete stayed with nothing said, against what
  site/data/site/privacy.md promises. Now each failure is one line in the
  site's log, the file's name and the error code and never what it holds,
  the same shape the voice service's chat days use (#2191), and the answer
  says how many went and which would not, for the harness.
*/
// No try (#2736): o is a plain object of codes and counts, which stringify
// does not throw on, and console.error goes to the site log, which says its
// own failure once and never throws.
function retentionSay(what, o) {
  console.error('[thornswood-docs] ' + what + '-retention ' + JSON.stringify(o));
}
function pruneSessionLogs() {
  const out = { deleted: 0, failed: [] };
  let names;
  try {
    if (!fs.existsSync(SLOGS)) return out;
    names = fs.readdirSync(SLOGS);
  } catch (e) {
    out.error = (e && e.code) || 'unknown';
    retentionSay('session-log', { event: 'prune-failed', code: out.error });
    return out;
  }
  const cutoff = Date.now() - SLOG_DAYS * 86400000;
  const held = new Set(sessionRows().filter(r => r && r.keep).map(r => String(r.session)));
  for (const f of names) {
    if (!f.endsWith('.json')) continue;
    const key = f.slice(0, -5);
    if (held.has(key)) continue;
    const full = path.join(SLOGS, f);
    // When the set was saved: its own stamp, else the file's time. A set
    // whose time cannot be read either way is not aged, because a guess
    // that deletes evidence is the wrong way to be wrong.
    let at = 0;
    try { at = Number((JSON.parse(fs.readFileSync(full, 'utf8')) || {}).at) || 0; } catch (e) { at = 0; }
    if (!at) { try { at = fs.statSync(full).mtimeMs; } catch (e) { at = Date.now(); } }
    if (at >= cutoff) continue;
    try {
      fs.unlinkSync(full);
      out.deleted++;
    } catch (e) {
      const code = (e && e.code) || 'unknown';
      out.failed.push({ file: f, code: code });
      retentionSay('session-log', { event: 'delete-failed', file: f, code: code,
                                    daysPastRetention: Math.floor((cutoff - at) / 86400000) });
    }
  }
  return out;
}

// ==== thornswood keeping times ====
//
// A KEEPING TIME FOR EVERY STORE THE PRIVACY PAGE NAMES (#2353). The page
// said what the site keeps and gave a time only for the stores that had a
// rule: reports, staff records, the moderation log and the gallery queue had
// none, and nothing in the code ever aged them. Decided by Patrick on 12
// October: "write a keeping time for each store and enforce it in code;
// Claude picks sensible times". The times, each on the page in the same
// words:
//
//   STAFF_DAYS, 365. A ban is kept for as long as it holds; one that ran out
//   is kept STAFF_DAYS past its end, then dropped, and lifting one already
//   deletes it. A PK that holds is kept, because the character stays dead
//   for good; one an admin undid is kept STAFF_DAYS past the undoing, and
//   each earlier PK in a row's history by the same rule. A staff note is
//   kept STAFF_DAYS from when it was written. A ban has to outlive any
//   window while it holds; once it does not, a year is the history staff
//   read a person by, the same year as their sessions and chat.
//   MODLOG_DAYS, 365. One line of moderation.log (every staff action on the
//   hub, for the bot's staff channel), the same as the game servers' own.
//   GREPORTS_DAYS, 365. A report against a gallery picture, like every
//   other report (INBOX_DAYS in the report limits).
//   PENDING_DAYS, 90. A gallery submission staff have neither accepted nor
//   deleted in 90 days is taken off the queue and its file deleted, the
//   same way a removed one is (pruneRemovedUploads), so the queue cannot
//   become a store of pictures nobody looked at.
//
// A time that cannot be read is kept rather than guessed at, as the sign-in
// log keeps one: a row or a line with no usable time is a corrupt one, and
// deleting a ban because its date would not parse is the wrong way to be
// wrong. These are pure functions over what was read, so the harness drives
// them on their own (tests\test-2353-keeping-times.js); the sweeps after the
// block do the reading and writing, at start and every hour, and the writes
// and the hub's reads go through the same functions.
const STAFF_DAYS = 365;
const MODLOG_DAYS = 365;
const GREPORTS_DAYS = 365;
const PENDING_DAYS = 90;
function keptCut(days, now) { return (Number(now) || Date.now()) - days * 86400000; }
// A usable time that is before the cut. Numbers are milliseconds; the logs
// write an ISO string.
function pastCut(at, cut) {
  const t = typeof at === 'string' ? Date.parse(at) : Number(at);
  return isFinite(t) && t > 0 && t < cut;
}
function isRecord(v) { return !!v && typeof v === 'object' && !Array.isArray(v); }

function freshBans(table, now) {
  const cut = keptCut(STAFF_DAYS, now);
  const out = {};
  for (const k of Object.keys(isRecord(table) ? table : {})) {
    const b = table[k];
    if (isRecord(b) && Number(b.until) > 0 && pastCut(b.until, cut)) continue;
    out[k] = b;
  }
  return out;
}
// An earlier PK in a row's history ages from its undoing, or, replaced by a
// new PK without one, from when it was made.
function freshPk(table, now) {
  const cut = keptCut(STAFF_DAYS, now);
  const out = {};
  for (const k of Object.keys(isRecord(table) ? table : {})) {
    const row = table[k];
    if (!isRecord(row)) { out[k] = row; continue; }
    if (isRecord(row.undone) && pastCut(row.undone.at, cut)) continue;
    if (!Array.isArray(row.history)) { out[k] = row; continue; }
    const history = row.history.filter((h) => !(isRecord(h) &&
      pastCut(isRecord(h.undone) ? h.undone.at : h.at, cut)));
    out[k] = history.length === row.history.length ? row : Object.assign({}, row, { history });
  }
  return out;
}
function freshNotes(notes, now) {
  const cut = keptCut(STAFF_DAYS, now);
  const out = {};
  for (const k of Object.keys(isRecord(notes) ? notes : {})) {
    const list = notes[k];
    if (!Array.isArray(list)) { out[k] = list; continue; }
    const kept = list.filter((n) => !(isRecord(n) && pastCut(n.at, cut)));
    if (kept.length) out[k] = kept;
  }
  return out;
}
// moderation.log as text: every line inside MODLOG_DAYS, and every line whose
// time cannot be read, in the order they were written.
function freshModLog(text, now) {
  const cut = keptCut(MODLOG_DAYS, now);
  const lines = String(text || '').split('\n');
  const last = lines.pop();
  let dropped = 0;
  const kept = lines.filter((l) => {
    let row = null;
    try { row = JSON.parse(l); } catch (e) { return true; }
    if (isRecord(row) && pastCut(row.at, cut)) { dropped++; return false; }
    return true;
  });
  return { text: kept.map((l) => l + '\n').join('') + last, dropped };
}
function freshGalleryReports(list, now) {
  const cut = keptCut(GREPORTS_DAYS, now);
  return (Array.isArray(list) ? list : []).filter((r) => !(isRecord(r) && pastCut(r.at, cut)));
}
// The gallery queue split into what stays and what has waited too long.
function stalePending(list, now) {
  const cut = keptCut(PENDING_DAYS, now);
  const left = [], expired = [];
  for (const e of (Array.isArray(list) ? list : [])) {
    (isRecord(e) && pastCut(e.at, cut) ? expired : left).push(e);
  }
  return { left, expired };
}
// ==== end thornswood keeping times ====

/* The timer's half for each store above, and for the inbox. Each writes only
   when something aged out, never writes over a file that is there and will
   not read (jsonFile answers its empty fallback for one, and an empty table
   changes nothing), and says a write that fails: the store and the counts,
   never what the rows hold (#2354). */
function sweepInbox(now) {
  const raw = jsonFile(INBOX, []);
  const rows = Array.isArray(raw) ? raw : [];
  const kept = trimInbox(rows, now);
  const out = { rows: rows.length, kept: kept.length, written: false };
  if (kept.length === rows.length) return out;
  out.written = putJson(INBOX, kept);
  if (!out.written) retentionSay('inbox', { event: 'write-failed', rows: rows.length, kept: kept.length });
  return out;
}
function sweepStaffRecords(now) {
  const out = { bans: 0, pk: 0, notes: 0 };
  // A ban list that is there and will not read is never written over (#2186).
  const readB = bansNow();
  if (!readB.broken) {
    const kept = freshBans(readB.table, now);
    const n = Object.keys(readB.table).length - Object.keys(kept).length;
    if (n && putJson(BANS, kept)) out.bans = n;
    else if (n) retentionSay('bans', { event: 'write-failed', dropped: n });
  }
  for (const [what, file, fresh] of [['pk', PK, freshPk], ['notes', NOTES, freshNotes]]) {
    const raw = jsonFile(file, {});
    if (!isRecord(raw)) continue;
    const kept = fresh(raw, now);
    if (JSON.stringify(kept) === JSON.stringify(raw)) continue;
    if (putJson(file, kept)) out[what] = 1;
    else retentionSay(what, { event: 'write-failed' });
  }
  return out;
}
function sweepModLog(now) {
  let text;
  try { text = fs.readFileSync(MODLOG, 'utf8'); }
  catch (e) {
    if (e && e.code === 'ENOENT') return { dropped: 0 };
    retentionSay('moderation-log', { event: 'read-failed', code: (e && e.code) || 'unknown' });
    return { dropped: 0, error: (e && e.code) || 'unknown' };
  }
  const kept = freshModLog(text, now);
  if (!kept.dropped) return { dropped: 0 };
  if (putFile(MODLOG, kept.text)) return { dropped: kept.dropped };
  retentionSay('moderation-log', { event: 'write-failed', dropped: kept.dropped });
  return { dropped: 0, error: 'write-failed' };
}
function sweepGalleryReports(now) {
  const raw = jsonFile(GREPORTS, []);
  const rows = Array.isArray(raw) ? raw : [];
  const kept = freshGalleryReports(rows, now);
  if (kept.length === rows.length) return { dropped: 0 };
  if (putJson(GREPORTS, kept)) return { dropped: rows.length - kept.length };
  retentionSay('gallery-reports', { event: 'write-failed', rows: rows.length, kept: kept.length });
  return { dropped: 0, error: 'write-failed' };
}
/* A submission past PENDING_DAYS is marked removed on uploads.json first, so
   pruneRemovedUploads, run after this in the same sweep, deletes its file
   and its note, and a delete that fails is said and asked again each hour
   the way a removed one is. Off the queue only once the mark is written:
   the other way round, a failed mark would leave a file nobody lists. */
function expirePending(now) {
  const raw = jsonFile(GPENDING, []);
  if (!Array.isArray(raw)) return { expired: 0 };
  const split = stalePending(raw, now);
  if (!split.expired.length) return { expired: 0 };
  const meta = jsonFile(UPMETA, {});
  const at = Number(now) || Date.now();
  for (const e of split.expired) {
    const name = String(e.name || '');
    if (!/^[A-Za-z0-9._ -]+$/.test(name) || name === 'uploads.json') continue;
    meta[name] = Object.assign({}, isRecord(meta[name]) ? meta[name] : {}, { removed: at });
  }
  if (!putJson(UPMETA, meta)) {
    retentionSay('gallery-pending', { event: 'note-write-failed', expired: split.expired.length });
    return { expired: 0, error: 'note-write-failed' };
  }
  if (!putJson(GPENDING, split.left)) {
    retentionSay('gallery-pending', { event: 'write-failed', expired: split.expired.length });
    return { expired: 0, error: 'write-failed' };
  }
  return { expired: split.expired.length };
}

/*
  THE RETENTION TIMER (#2350). Both prunes used to run only when a session
  ended, so a quiet stretch with nobody playing left rows and log sets past
  365 days on disk, against what the privacy page says. Decided by Patrick
  on 12 October: run them on a timer too. Once as the site comes up and then
  every hour; each says its own failures (retentionSay) and neither throws.
  The rows go first, so the log prune reads which rows are still kept from
  the file as it now stands. The failed-session alerts in trouble.json age
  in the same pass by the same 365 days (#2166, sweepTrouble), and removed
  gallery files whose hold has ended go too (#2352, pruneRemovedUploads),
  and sign-in rows past their 30 days (sweepSignIns). Since #2353 so do the
  inbox, the staff records, the site's moderation.log, the gallery reports
  and the gallery queue, each by its keeping time (the keeping times block).
*/
const RETENTION_EVERY_MS = 60 * 60 * 1000;
/*
  A KEPT SESSION KEEPS ITS CHAT (#2166 G1). Keeping a session used to hold
  its row and its launcher logs and nothing else. What the person said in it
  was read live, every time, out of the voice service's day files
  (chatSlice), and the voice service deletes a whole day 365 days on
  (voice-server.js chatPrune) without knowing which sessions staff kept, so
  the words a suspension rests on went a year later while the page said the
  session was held.

  So keeping a session copies its chat, the same window /api/session-logs
  reads, into the session's own log set (session-logs/<session>.json, a
  "chat" field), which is already what a kept session holds past
  SLOG_DAYS: pruneSessionLogs skips kept sets and Delete-Person.ps1 leaves
  them alone. A session kept before the launcher sent anything gets a set
  holding only the chat (chatOnly), and putSessionLogs fills the logs in
  beside it when they come.

  The day files stay the voice service's, pruned whole by date: the copy is
  what outlives them, not an edit to them, and the site never writes in the
  voice service's folder.

  A copy is made only from day files that are there. A copy already made is
  never written over by a read that found no day files, because that read
  would be an empty list standing in for words that were said. A session
  kept while it was still open is copied again once it has ended and the
  copy is short of its end. Letting the session go drops the copy, so it
  cannot outlive the hold it was made for.
*/
function isObjectLike(v) { return !!v && typeof v === 'object' && !Array.isArray(v); }
function sessionWindow(row, now) {
  return { from: (Number(row.start) || Number(row.end) || 0) - 60000,
           to: (Number(row.end) || now || Date.now()) + 60000 };
}
function readSlogSet(key) {
  try {
    const f = slogFile(key);
    if (!fs.existsSync(f)) return { there: false, set: null };
    return { there: true, set: JSON.parse(fs.readFileSync(f, 'utf8')) };
  } catch (e) { return { there: true, set: null, code: (e && e.code) || 'unreadable' }; }
}
function keptChatCurrent(row, chat) {
  if (!isObjectLike(chat) || !Array.isArray(chat.lines)) return false;
  if (!Number(row.end)) return true;
  return (Number(chat.to) || 0) >= Number(row.end) + 60000;
}
function copyKeptChat(row, now) {
  now = now || Date.now();
  const key = sessionKey(row && row.session);
  if (!key) return 'no-session';
  /* A row with neither a start nor an end has no window to copy. */
  if (!Number(row.start) && !Number(row.end)) return 'no-window';
  const had = readSlogSet(key);
  if (had.there && !isObjectLike(had.set)) {
    retentionSay('kept-chat', { event: 'copy-failed', session: key, code: had.code || 'unreadable' });
    return 'failed';
  }
  if (had.set && keptChatCurrent(row, had.set.chat)) return 'already';
  const w = sessionWindow(row, now);
  const slice = chatSlice(row.profile, w.from, w.to, row.channel);
  if (slice.why) return had.set && had.set.chat ? 'already' : 'no-chat-log';
  const text = JSON.stringify(slice.lines);
  const chat = {
    copiedAt: now, from: w.from, to: w.to,
    channel: row.channel === 'dev' ? 'dev' : 'main',
    lines: slice.lines,
    sha256: crypto.createHash('sha256').update(text, 'utf8').digest('hex')
  };
  const set = had.set || { session: key, who: String(row.who || ''), at: now, bytes: 0,
                           sha256: {}, logs: {}, chatOnly: true };
  set.chat = chat;
  try {
    if (!fs.existsSync(SLOGS)) fs.mkdirSync(SLOGS, { recursive: true });
    fs.writeFileSync(slogFile(key), JSON.stringify(set));
    return 'copied';
  } catch (e) {
    retentionSay('kept-chat', { event: 'copy-failed', session: key, code: (e && e.code) || 'unknown' });
    return 'failed';
  }
}
function dropKeptChat(key) {
  key = sessionKey(key);
  if (!key) return 'no-session';
  const had = readSlogSet(key);
  if (!had.set || !had.set.chat) return 'none';
  try {
    if (had.set.chatOnly) fs.unlinkSync(slogFile(key));
    else { delete had.set.chat; fs.writeFileSync(slogFile(key), JSON.stringify(had.set)); }
    return 'dropped';
  } catch (e) {
    retentionSay('kept-chat', { event: 'drop-failed', session: key, code: (e && e.code) || 'unknown' });
    return 'failed';
  }
}
/* Every kept session has its copy: the ones kept before this existed, and
   the ones kept while still open. Hourly with the rest of the retention
   sweep, so a day file is copied long before its 365 days are up. */
function copyKeptChats(now) {
  const out = { copied: 0, failed: 0, noChatLog: 0 };
  let rows;
  try { rows = sessionRows(); } catch (e) { return out; }
  for (const r of rows) {
    if (!r || !r.keep) continue;
    const got = copyKeptChat(r, now);
    if (got === 'copied') out.copied++;
    else if (got === 'failed') out.failed++;
    else if (got === 'no-chat-log') out.noChatLog++;
  }
  return out;
}

function retentionSweep() {
  const now = Date.now();
  const sessions = sweepSessions(now);
  /* Copies before the prune, so a kept session's chat is in its set before
     anything goes. */
  const keptChat = copyKeptChats(now);
  /* In this order, an object literal's own: the queue's expired submissions
     are marked removed before the prune, so their files go in this same pass
     (#2353). */
  return { sessions, keptChat, sessionLogs: pruneSessionLogs(),
           trouble: sweepTrouble(now), pending: expirePending(now),
           removedUploads: pruneRemovedUploads(now),
           signIns: sweepSignIns(now), inbox: sweepInbox(now),
           staff: sweepStaffRecords(now), moderationLog: sweepModLog(now),
           galleryReports: sweepGalleryReports(now) };
}
setInterval(retentionSweep, RETENTION_EVERY_MS).unref?.();

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

/*
  A CRASH LOG IN THE SET IS A CRASH (#2319). The launcher sends crash.log only
  when Crash Logger wrote one during this session (CrashLogSince picks it by
  the session's start), so its being there is the crash, whatever it holds.
  Until #2319 a session was marked only when a line in some log matched
  TROUBLE_BAD, and a crash that hung inside the crash handler left an empty
  log, which the launcher did not send at all: three dev crashes from 29 Sep
  to 6 Oct reached the site with no crash.log, no colour and no staff alert.
  The launcher now sends a first line of its own on crash.log naming the
  log, its size and the snapshot beside it, so an empty one arrives too.

  The line kept with it is the crash's own (the first TROUBLE_BAD line, which
  for Crash Logger is "Unhandled exception ..."), or the launcher's line when
  the log has none, which says the log is empty.
*/
const CRASH_EMPTY_MARK = 'and it is empty: 0 bytes';
function crashOf(logs) {
  const text = String((logs || {})['crash.log'] || '');
  if (!text.trim()) return null;
  const empty = text.indexOf(CRASH_EMPTY_MARK) >= 0;
  const why = empty ? 'the game crashed, and its crash log is empty' : 'the game crashed';
  const own = scanFor({ 'crash.log': text }, TROUBLE_BAD, 'bad');
  if (own) return { level: 'bad', why, file: 'crash.log', line: own.line };
  const first = text.split('\n').map(l => l.trim()).filter(Boolean)[0] || '';
  return { level: 'bad', why, file: 'crash.log', line: first.slice(0, 300) };
}

/* Red before yellow: a session that crashed AND complained about its load
   order is a crash, and the crash is the thing worth waking somebody for.
   A crash log first (crashOf, #2319), then the other red lines, then the
   server's word on the load order, then the rest. */
function readTrouble(logs, serverLines, profile) {
  const mine = {};
  for (const name of Object.keys(logs || {})) mine[name] = thisSessionOf(name, logs[name]);
  return crashOf(mine) ||
         scanFor(mine, TROUBLE_BAD, 'bad') ||
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
/* 3: a crash log in the set is a crash (crashOf, #2319). */
const TROUBLE_RULES = 3;
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

/* True when the bot's row is written, or was already there. A write that
   fails is said and answers false (#2736): the whole of this sat in a try
   with an empty catch, and the putJson below was never looked at, so a crash
   whose note could not be written reached nobody in Discord and nothing said
   so. jsonFile and freshTrouble do not throw. */
function noteTrouble(row, found) {
  const list = jsonFile(TROUBLE_FILE, []);
  const all = Array.isArray(list) ? list : [];
  if (all.some(t => t && t.session === row.session)) return true;
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
  if (putJson(TROUBLE_FILE, freshTrouble(all, Date.now()).slice(-TROUBLE_KEEP))) return true;
  console.error('[thornswood-docs] trouble ' + JSON.stringify({ event: 'write-failed', session: row.session, file: path.basename(TROUBLE_FILE) }));
  return false;
}

/*
  TROUBLE ROWS AGE LIKE THE SESSION THEY ARE ABOUT (#2166). Each row is a copy
  of a session record (who, the name, the profile, the session's window) with
  one line out of its launcher log, so the privacy page's 365 days for session
  records and launcher logs is its rule too. It was kept by count only, the
  last TROUBLE_KEEP, so on a quiet server a row outlived both the session row
  and the log set it was read from.

  A row's time is the latest of the session's start, its end and when its
  logs arrived, the same stamp the log set itself is aged by. A row with no
  usable time is kept rather than guessed at, the way the session rows keep
  one. A row whose session staff marked kept stays, because its row and its
  log set stay (pruneSessionLogs), and the alert is part of what was held.
  The count stays as the bound on the file's size.
*/
function freshTrouble(rows, now, held) {
  const cut = (Number(now) || Date.now()) - SESSIONS_DAYS * 86400000;
  const keep = held || new Set(sessionRows().filter((r) => r && r.keep).map((r) => String(r.session)));
  return (Array.isArray(rows) ? rows : []).filter((t) => {
    if (!t || typeof t !== 'object') return false;
    if (keep.has(String(t.session))) return true;
    const at = Math.max(Number(t.start) || 0, Number(t.end) || 0, Number(t.at) || 0);
    return !(at > 0 && at < cut);
  });
}
/* The timer's half. Writes only when something aged out, and a write that
   fails is said, the count and never what the rows hold (#2354). An
   unreadable file reads as [] and an empty list never writes over it. */
function sweepTrouble(now) {
  const raw = jsonFile(TROUBLE_FILE, []);
  const rows = Array.isArray(raw) ? raw : [];
  const kept = freshTrouble(rows, now);
  const out = { rows: rows.length, kept: kept.length, written: false };
  if (kept.length === rows.length) return out;
  out.written = putJson(TROUBLE_FILE, kept);
  if (!out.written) retentionSay('trouble', { event: 'write-failed', rows: rows.length, kept: kept.length });
  return out;
}

/*
  The game server's log between two moments.

  Its lines start "[2026-09-22 10:02:10.155]", which is local time on this box
  and the same clock the session's start and end were stamped with, so they
  compare directly. A line with no stamp belongs to the line above it, which is
  what a stack trace is, so it is kept whenever the last stamped line was.

  dev and main are different servers with different logs; the session says
  which it was on.

  ROLLED LOGS ARE READ TOO, entry 220. Since #2349 the server runs under
  server-log.js, which rolls server.log at midnight, at 4 MB and at a start
  from another day into server.log.<when>, and keeps no line in any of them
  past 30 days (an install rolls it whatever the size). Reading server.log
  alone, a restart after a crash would leave every session before it with no
  server lines at all, the crash session included, which is the one this
  page is opened for. So when server.log is shorter than the window, the rest
  of the window is taken off the end of the rolled ones, newest first
  (serverLogGenerations), and the read is never more than the 4 MB it always
  was. A session older than 30 days has no server lines left, which is the
  privacy page's promise rather than a fault.
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
                 name: String(o.name || ''), proven: !!o.proven, text: String(o.text || ''),
                 via: o.via === 'press' ? 'press' : '' });
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

/* The server's log and the rolled copies behind it, newest first (#2349).
   server-log.js rolls server.log at midnight and at 4 MB into
   server.log.<when it was rolled>, and the numbered ones Roll-Log.ps1 left
   (server.log.1 to .5) are still there until their lines pass 30 days. Both
   are server.log.<digits>, ordered by their last write, which is when each
   stopped being the live file. */
function serverLogGenerations(file) {
  const dir = path.dirname(file), base = path.basename(file).toLowerCase() + '.';
  let names = [];
  try { names = fs.readdirSync(dir); } catch (e) { names = []; }
  const rolled = [];
  for (const n of names) {
    if (n.toLowerCase().indexOf(base) !== 0 || !/^\d+$/.test(n.slice(base.length))) continue;
    /* A copy deleted by the age rule between the listing and this look is
       gone, and is left out. Any other failure is said, by its name and the
       code (#2736), since the copy is then left out of what staff read. */
    try { rolled.push({ f: path.join(dir, n), t: fs.statSync(path.join(dir, n)).mtimeMs }); }
    catch (e) {
      if (e.code !== 'ENOENT') console.error('[thornswood-docs] could not look at ' + n + ' beside ' + path.basename(file) + ' (' + (e.code || e.message) + ')');
    }
  }
  rolled.sort((a, b) => b.t - a.t);
  return [file].concat(rolled.map((r) => r.f));
}

function serverLogSlice(channel, from, to) {
  const file = SERVER_LOGS[channel === 'dev' ? 'dev' : 'main'];
  /* Only the tail is read, 4 MB across the live file and the rolled ones
     behind it, newest first. These grow, and a session is minutes long. */
  let left = 4 * 1024 * 1024;
  const parts = [];
  let found = 0;
  try {
    for (const f of serverLogGenerations(file)) {
      if (left <= 0) break;
      /* server.log itself can be missing for a moment, between the roll and
         the writer opening a new one. */
      if (!fs.existsSync(f)) continue;
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
  } catch (e) { return { ok: false, why: String(e.message || e), code: e.code || e.name, lines: [] }; }
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
  const readB = bansNow();
  if (readB.broken) {
    out.banned = true; out.reason = BANS_BROKEN_WHY; out.until = 0; out.byFile = true; out.bansBroken = true;
    return out;
  }
  const bans = readB.table;
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
    out.admin = true; out.play = true; out.inGuild = true; out.dev = true; out.devBuild = true;
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
        out.leads = leaderRoles(out.roles);
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
  out.devBuild = out.admin || has(cfg.access.devBuild);
  out.company = has(cfg.access.company);
  out.staffRole = holdsStaffRole(out.roles);
  out.businessOwner = holdsNamedRole(out.roles, 'Business Owner');
  out.leads = leaderRoles(out.roles);
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
  THE FACTION LEADER ROLES HELD (#3317). Every faction's Leader role is its
  name and " Leader" (bot/Build-Discord.py FACTION_LEADERS), and a faction
  that comes in through the application as Other gets one the same way, so
  the site reads them by that shape rather than keeping a second list of the
  factions. Whoever holds one owns that faction's book in the game (Patrick,
  22 Oct, page card q-3317-faction-books, A).
*/
function leaderRoles(roles) {
  const mine = Array.isArray(roles) ? roles : [];
  return mine.filter((n) => typeof n === 'string' && /^[^\n]{1,96} Leader$/.test(n));
}

/*
  THE HOLD OFFICES, FROM THE ROLES (#2551). Patrick, 15 Oct: a Jarl's hold
  comes from their "Jarl of <Hold>" Discord role, and each hold has a Court,
  a Steward and Guards, which are Discord roles too ("<Hold> Court",
  "Steward of <Hold>", "Guard of <Hold>", made by bot\Build-Discord.py and
  never hoisted). The role is the one truth: the game keeps no list of who
  holds what, it reads this, through /api/allowed.

  The key is the hold as the game names it (its ledger holds); the town is
  how the role names it. Raven Rock is here although Build-Discord.py makes
  no roles for it, so roles made for it by hand are read the same way.

  OFFICE_ROLE says, for one office and one hold, the role's exact name. Only
  the four offices are read, by exact name: a role somebody calls "Jarl of
  Whiterun's dog" is nobody's office.
*/
const OFFICE_HOLDS = {
  whiterun: 'Whiterun', solitude: 'Solitude', riften: 'Riften', markarth: 'Markarth',
  windhelm: 'Windhelm', falkreath: 'Falkreath', morthal: 'Morthal', dawnstar: 'Dawnstar',
  winterhold: 'Winterhold', ravenrock: 'Raven Rock'
};
const OFFICE_KINDS = ['jarl', 'court', 'steward', 'guard'];
function OFFICE_ROLE(office, hold) {
  const town = Object.prototype.hasOwnProperty.call(OFFICE_HOLDS, hold) ? OFFICE_HOLDS[hold] : '';
  if (!town) return '';
  if (office === 'jarl') return 'Jarl of ' + town;
  if (office === 'court') return town + ' Court';
  if (office === 'steward') return 'Steward of ' + town;
  if (office === 'guard') return 'Guard of ' + town;
  return '';
}
/* { jarl: [holds], court: [...], steward: [...], guard: [...] } for these role names. */
function officesOf(roles) {
  const mine = Array.isArray(roles) ? roles : [];
  const out = { jarl: [], court: [], steward: [], guard: [] };
  for (const office of OFFICE_KINDS) {
    for (const hold of Object.keys(OFFICE_HOLDS)) {
      if (mine.indexOf(OFFICE_ROLE(office, hold)) >= 0) out[office].push(hold);
    }
  }
  return out;
}
/* Whether these offices hold anything at all. */
function holdsAnOffice(o) {
  return !!o && OFFICE_KINDS.some((k) => Array.isArray(o[k]) && o[k].length > 0);
}

/*
  Who holds each hold's Jarl role, over the whole Discord: { hold: Map(id ->
  name) }, or null when the member list cannot be read (guildMembers needs
  the Server Members intent, and says null without it). Over the whole
  Discord because a second holder who has never played still holds the role.
*/
async function jarlRoleHolders() {
  const all = await guildMembers();
  if (!all) return null;
  const names = await roleNames();
  const out = {};
  for (const id of Object.keys(all)) {
    const m = all[id] || {};
    const o = officesOf((m.roles || []).map((r) => names[r]).filter(Boolean));
    for (const h of o.jarl) {
      if (!out[h]) out[h] = new Map();
      out[h].set(String(id), m.nick || (m.user && (m.user.global_name || m.user.username)) || '');
    }
  }
  return out;
}

/*
  ONE JARL A HOLD, BY THE ROLE (#2551). Patrick, 15 Oct: "If two accounts hold
  the same hold's Jarl role, neither acts as Jarl until staff fix it, and
  staff are told which accounts clash."

  Counted over the whole Discord when its member list can be read, and over
  the accounts the door just asked about (answers, from standingsForDoor)
  when it cannot. Each clash is { hold, people: [{ id, name }], profiles }:
  profiles are every profile of those accounts that linked.json knows, so the
  game can tell each of them why. The hold comes off those profiles' offices
  in out (a copy: the offices in out are the cached standings' own), so
  neither acts as its Jarl, in the game or anywhere that reads this.

  Staff are told in the staff channel, through moderation.log, which the bot
  says (bot.py, moderation_text): once when a clash starts and once when it
  ends, not at every refresh. What was last said is kept in memory, so a
  restart of the site says the clashes that stand once more.
*/
let clashSaid = {};       // hold -> the accounts last said to staff, joined
let clashLast = [];       // the clashes last found, for an office change made when the list cannot be read
async function jarlClashes(out, answers, linked) {
  let holders = await jarlRoleHolders();
  if (!holders) {
    holders = {};
    for (const [id, st] of (answers || new Map())) {
      if (!st || st.lookupFailed || st.banned) continue;
      for (const h of officesOf(st.roles).jarl) {
        if (!holders[h]) holders[h] = new Map();
        holders[h].set(String(id), st.name || '');
      }
    }
  }
  const clashes = [];
  for (const hold of Object.keys(OFFICE_HOLDS)) {
    const by = holders[hold];
    if (!by || by.size < 2) continue;
    const ids = Array.from(by.keys()).sort();
    const profiles = [];
    for (const id of ids) {
      for (const n of (Array.isArray((linked[id] || {}).profiles) ? linked[id].profiles : [])) {
        const p = Number(n);
        if (p > 0 && profiles.indexOf(p) < 0) profiles.push(p);
      }
    }
    clashes.push({ hold, people: ids.map((id) => ({ id, name: by.get(id) })), profiles });
  }
  if (out && out.offices) {
    for (const c of clashes) {
      for (const p of c.profiles) {
        const o = out.offices[String(p)];
        if (!o || o.jarl.indexOf(c.hold) < 0) continue;
        const left = Object.assign({}, o, { jarl: o.jarl.filter((h) => h !== c.hold) });
        if (holdsAnOffice(left)) out.offices[String(p)] = left;
        else delete out.offices[String(p)];
      }
    }
  }
  clashLast = clashes;
  const now = {};
  for (const c of clashes) {
    now[c.hold] = c.people.map((x) => x.id).join(',');
    if (clashSaid[c.hold] !== now[c.hold]) {
      modLog({ did: 'jarlclash', hold: c.hold, role: OFFICE_ROLE('jarl', c.hold), people: c.people });
    }
  }
  for (const hold of Object.keys(clashSaid)) {
    if (!Object.prototype.hasOwnProperty.call(now, hold)) {
      modLog({ did: 'jarlclear', hold, role: OFFICE_ROLE('jarl', hold) });
    }
  }
  clashSaid = now;
  return clashes;
}

/*
  out.offices for /api/allowed: each profile of every account the route let
  in (out.people) gets its account's offices, read from the roles the door's
  answer holds for it, and the clashes come off (jarlClashes). Answers the
  clashes, for out.jarlClash.
*/
async function officesForDoor(out, answers, linked) {
  for (const p of (out.people || [])) {
    const st = answers.get(String(p.id)) || answers.get(p.id);
    if (!st || st.lookupFailed || st.banned) continue;
    const o = officesOf(st.roles);
    if (!holdsAnOffice(o)) continue;
    for (const n of p.profiles) out.offices[String(n)] = o;
  }
  return jarlClashes(out, answers, linked);
}

/* The Discord account a profile is linked to, or ''. */
function accountOfProfile(linked, pid) {
  const n = Number(pid) || 0;
  if (n <= 0) return '';
  for (const d of Object.keys(linked || {})) {
    const ps = Array.isArray((linked[d] || {}).profiles) ? linked[d].profiles : [];
    if (ps.some((x) => Number(x) === n)) return String(d);
  }
  return '';
}

/*
  A JARL GIVES OR TAKES AN OFFICE FROM THE GAME (#2551). Patrick, 15 Oct:
  "They still do it in game tho", and the game asks the site, and the bot
  sets the Discord role, so the role stays the one truth.

  The site asks Discord with the bot's own token (discord.botToken is the
  same token as the bot's, Developer-Guide.md, the secrets table), so the
  role is set by the bot's account, with the bot's Manage Roles, and Discord's
  audit log names the bot and the reason. Nothing in the game or here keeps a
  copy: the next /api/allowed reads the role back, and the game asks for that
  at once after a change.

  o: { by, byName, who, whoName, office, hold, give } from the game server,
  by and who profiles. Answers { ok, said }: said is the sentence for the
  Jarl, already in plain words. Every rule is checked here again, whatever
  the game checked: the asker holds that hold's Jarl role, alone, and the
  office is one of the three a Jarl gives.
*/
async function changeOffice(o, server) {
  const office = String((o && o.office) || '');
  const hold = String((o && o.hold) || '');
  const give = !!(o && o.give === true);
  const role = (office === 'court' || office === 'steward' || office === 'guard') ? OFFICE_ROLE(office, hold) : '';
  if (!role) return { ok: false, said: 'A Jarl gives the Court, a Steward and Guards of a hold, and nothing else.' };
  const town = OFFICE_HOLDS[hold];
  const byName = String((o && o.byName) || '').slice(0, 60) || 'somebody';
  const whoName = String((o && o.whoName) || '').slice(0, 60) || 'them';
  const linked = jsonFile(LINKED, {});
  const byAcct = accountOfProfile(linked, o && o.by);
  const whoAcct = accountOfProfile(linked, o && o.who);
  if (!byAcct) return { ok: false, said: 'Your character is not linked to a Discord account, so nobody can tell whether you are Jarl.' };
  if (!whoAcct) return { ok: false, said: whoName + ' is not linked to a Discord account, so the role has nobody to go to.' };
  // Asked fresh: a Jarl role taken a minute ago is taken now.
  standCache.delete(byAcct);
  const st = await standingCached(byAcct);
  if (st.lookupFailed) return { ok: false, said: 'Discord could not be asked just now. Try again in a minute.' };
  if (st.banned || officesOf(st.roles).jarl.indexOf(hold) < 0) {
    return { ok: false, said: 'Only the Jarl of ' + town + ' gives its offices.' };
  }
  const holders = await jarlRoleHolders();
  const twice = holders ? (holders[hold] ? holders[hold].size > 1 : false)
    : clashLast.some((c) => c.hold === hold);
  if (twice) {
    return { ok: false, said: 'Two Discord accounts hold the Jarl of ' + town + ' role, so neither acts as Jarl until staff fix it. Staff have been told.' };
  }
  const names = await roleNames();
  const roleId = Object.keys(names).filter((id) => names[id] === role)[0] || '';
  if (!roleId) return { ok: false, said: 'There is no ' + role + ' role in the Discord yet. Staff make it with the Discord builder.' };
  const m = await memberOf(whoAcct);
  if (!m.ok) {
    return { ok: false, said: m.status === 404 ? whoName + ' is not in the Discord, so the role has nobody to go to.'
      : 'Discord could not be asked just now. Try again in a minute.' };
  }
  const has = (m.body.roles || []).map(String).indexOf(String(roleId)) >= 0;
  if (give && has) return { ok: false, said: whoName + ' already holds ' + role + '.' };
  if (!give && !has) return { ok: false, said: whoName + ' does not hold ' + role + '.' };
  const reason = (give ? 'Given' : 'Taken') + ' by ' + byName + ', Jarl of ' + town + ', in the game';
  const w = await discordWrite(give ? 'PUT' : 'DELETE',
    '/guilds/' + cfg.discord.guildId + '/members/' + whoAcct + '/roles/' + roleId, reason);
  if (!w.ok) {
    return { ok: false, said: w.status === 403
      ? 'The bot may not change ' + role + ': its own role has to sit above it in the Discord. Staff fix that.'
      : 'Discord did not take the change (' + w.why + '). Try again in a minute.' };
  }
  // The next read of either account, and of the member list, is Discord's new answer.
  standCache.delete(whoAcct);
  standGood.delete(whoAcct);
  membersCache = { at: 0, byId: null };
  modLog({ did: 'office', from: server || 'main', give, office, hold, role,
           by: Number(o.by) || 0, byName, byAccount: byAcct, who: Number(o.who) || 0, whoName, whoAccount: whoAcct });
  return { ok: true, said: give ? whoName + ' holds ' + role + ' now. The role is set in Discord.'
                                : whoName + ' no longer holds ' + role + '. The role is taken in Discord.' };
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

/*
  THE PASS'S OWN KEY (#1320). The login rides the game's own port, which is not
  encrypted, so a pass alone in it could be seen and shown again on another
  connection. With the fork's login challenge (skymp5-server's
  thornswoodLogin.ts) the game sends each login a fresh nonce, and the client
  answers with the pass and HMAC-SHA256 of "jlp1." + nonce under this key. The
  key goes to the launcher here, over https, beside the pass, and never on the
  game's port; the game server derives the same one from passKey and the pass
  (the join pass block in gamemode.js). base64url HMAC-SHA256 of "jpk1." and
  the pass's own mac, keyed on cfg.passKey.
*/
function passLoginKey(key, pass) {
  const mac = String(pass || '').split('.')[2] || '';
  return b64u(crypto.createHmac('sha256', key).update('jpk1.' + mac).digest());
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
  const file = feedFile(dir);
  if (!file) return null;
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
    // failed() must not throw: it is the last catch on the request, and a
    // throw from here is an unhandled rejection, which stops the site. An
    // answer that cannot be written is said instead of dropped (#2736).
    try {
      if (!e.status || res.headersSent || res.destroyed) { if (!res.writableEnded) res.destroy(); return; }
      send(res, e.status, JSON.stringify({ ok: false, why: e.why, error: e.words, message: e.words }),
           null, { Connection: 'close' });
    } catch (e2) {
      console.error('[thornswood-docs] could not answer the body ' + e.why + ' (' + (e2.code || e2.name) + ')');
    }
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
  // carry the same policy as ordinary pages. The nonce is this answer's own
  // (cspFor, #3216).
  res.cspNonce = crypto.randomBytes(16).toString('base64');
  res.setHeader('Content-Security-Policy', cspFor(res));
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
  // No try (#2736): setHeader throws only once the headers are sent, and
  // nothing has been sent at the top of the handler.
  if (secureHere(req)) {
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
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

  // ------------------------------------------------------- security.txt
  /* Where somebody who finds a hole in the site says so (RFC 9116, #3216,
     Patrick's answer on 22 Oct 2026). The contact is the report page: open
     to anybody without an account, read by staff and nobody else, and the
     place staff already read every day, so a finding is never waiting in a
     mailbox nobody opens.

     Expires is written as the file is asked for, 180 days on, inside the
     year RFC 9116 asks for. The file says what this site answers, and the
     site answering is the proof somebody still keeps it: a date written by
     hand into a file would run out by itself one day while the contact
     still worked, and a check that a person has to remember to move is the
     kind that gets forgotten. */
  if (p === '/.well-known/security.txt' && req.method === 'GET') {
    const until = new Date(Date.now() + 180 * 24 * 60 * 60 * 1000);
    until.setUTCHours(0, 0, 0, 0);
    return send(res, 200, [
      'Contact: ' + PUBLIC_ORIGIN + '/report',
      'Expires: ' + until.toISOString(),
      'Preferred-Languages: en',
      'Canonical: ' + PUBLIC_ORIGIN + '/.well-known/security.txt',
      ''
    ].join('\n'), 'text/plain; charset=utf-8', { 'Cache-Control': 'public, max-age=86400' });
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
    // No try (#2736): Buffer.from skips what is not base64url rather than
    // throwing, and the state is ours, checked against its signature first.
    if (state.length === 2 && sameSecret(state[1], sign(state[0]))) {
      const bits = Buffer.from(state[0], 'base64url').toString().split('\u0000');
      back = bits[0] || '/';
      port = (bits[1] || '').replace(/[^0-9]/g, '').slice(0, 5);
      nonce = (bits[2] || '').replace(/[^A-Za-z0-9]/g, '').slice(0, 64);
      attempt = (bits[3] || '').replace(/[^0-9a-f]/g, '').slice(0, 32);
      began = Number(bits[4]) || 0;
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

    /* Only twa (#2166). The member cookie tw is the password door's, and
       the privacy page calls it the fallback for a site with no Discord
       sign-in: isMember ignores it whenever Discord is configured, and this
       callback only runs then. It used to be set here as well, so every
       Discord sign-in left a year-long cookie that granted nothing and that
       the page said was not set. Now it is cleared instead, which also ends
       the ones earlier sign-ins left behind, the way sign-out clears it. */
    const cookies2 = [setCookie(req, ADMIN, value, ADMIN_DAYS),
                      COOKIE + '=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax', spent];

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
    if (Array.isArray(rows) && live.length !== rows.length && !putJson(ATTEMPTS, live)) {
      retentionSay('signin', { event: 'write-failed', rows: rows.length, kept: live.length });
    }
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
      // One lore line from lines.md under The World (#3147), a new pick each
      // time a page is served. Every page, not only /: the front is in each
      // one, for the page's script to show when it goes back to /. After the
      // invite link, for the same reason as the written pages below.
      html = fillLoreLine(html, readLines().lore, Math.random());
      // The og tags a crawler reads are the ones in the file, so the page
      // actually being served is written into them here. The browser tab reads
      // the same tags; home.js keeps no list of its own (#3138).
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
      /* no-cache, not send()'s no-store (#3218). A public page is the same for
         everybody: nothing in it says who is asking. no-store kept every one
         of them out of the browser's back and forward cache, so Back from
         the rules to the front page fetched and drew the whole page again.
         no-cache still asks the site each time the page is opened anew. */
      return send(res, 200, html, TYPES['.html'], { 'Cache-Control': 'no-cache' });
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
    // no-cache for the same reason as the public pages: the same answer for
    // everybody, and a no-store answer to the page's own fetch kept the page
    // out of the back and forward cache as well (#3218).
    return send(res, 200, JSON.stringify({
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
      news: (feed.news || []).slice(0, 6).map((n) => ({ date:n.date, title:n.title })),
      // The hints and lore lines (#3147): the Discord bot's status lines.
      lines: readLines()
    }), 'application/json; charset=utf-8', { 'Cache-Control': 'no-cache' });
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
    /* A downloads folder that is there and cannot be read answered as if no
       zip was there, so the installer said the site was not offering a
       download when the site could not look (#2736). Now it is said and
       answered 500. No folder is still no zip, tested for; a zip deleted by a
       publish between the listing and the look at it is left out. */
    let best = null;
    try {
      const names = fs.existsSync(FILES) ? fs.readdirSync(FILES) : [];
      for (const name of names) {
        if (!/^Thornswood-Setup(?:-\d{8}-\d{4})?\.zip$/i.test(name)) continue;
        let st;
        try { st = fs.statSync(path.join(FILES, name)); }
        catch (e) { if (e.code === 'ENOENT') continue; throw e; }
        if (!st.isFile()) continue;
        if (!best || st.mtimeMs > best.at) best = { name, at: st.mtimeMs, size: st.size };
      }
    } catch (e) {
      console.error('[thornswood-docs] could not read the downloads in ' + FILES + ' for /api/payload (' + (e.code || e.message) + ')');
      return sendJson(res, 500, { error: 'the site could not look at its downloads' });
    }
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
  // What the report page needs to draw the form: the Turnstile site key, or
  // nothing when the check is off (#3216). Public, like the key itself.
  if (route === '/api/report/form' && req.method === 'GET') {
    return sendJson(res, 200, { turnstile: turnstileOn() ? cfg.turnstileSiteKey : '' });
  }

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
    // Turnstile's pass (#3216), asked before the limit is read again below,
    // because it waits on Cloudflare and nothing may wait between that read
    // and reportTaken. A refused pass is not counted against the sender.
    if (turnstileOn()) {
      const ts = await turnstilePasses(o.turnstile, requestAddr(req));
      if (ts === 'unasked') {
        return sendJson(res, 503, { error: 'Cloudflare did not answer the check that you are a person, so nothing was sent. Try again in a minute.' });
      }
      if (ts !== 'yes') {
        return sendJson(res, 403, { error: 'The check that you are a person did not pass. Wait for the tick under the form, then send it again.' });
      }
    }
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
    // Built from the issue board by the bot (#3140). The intro is markdown,
    // and it is rendered here like the written pages so the front page needs
    // no markdown library of its own.
    const rm = roadmapBoard(readLists());
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
    const item = jsonFile(GALLERY, [])
      .find((g) => String(g.name).toLowerCase() === shot[1]);
    // ?w= is one of its smaller copies (#3218), and only one its srcset names.
    // The file by the name gallery.json keeps, since the address is lower
    // cased and a name may not be: the same file on the box's Windows, and
    // none at all on a copy of the site on Linux.
    const wide = url.searchParams.get('w');
    const file = !item ? ''
      : wide === null ? path.join(UP, String(item.name))
      : srcsetWidths(item.srcset).indexOf(Number(wide)) >= 0 ? smallCopy(item.name, Number(wide)) : '';
    if (!file || !file.startsWith(UP + path.sep) || !fs.existsSync(file)) {
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
        How long it may be kept. A name asked for with the hash it has now
        (versionAssets, #3218) is that file and no other for good, so a year
        and immutable. Anything else is the hour and an ETag: a browser
        reuses it for the hour and then asks, and the answer to that
        question is 25 bytes rather than 1.8 MB.

        send() puts Cache-Control: no-store on everything, which is right for
        a page that holds who somebody is and wrong for a picture. no-store
        also means a browser cannot even answer with a 304, so before this a
        page reload was a full download of all of public/.

        The ETag is the hash of what is served, so it changes the moment a
        deploy writes a new file, a stylesheet's when one of its fonts does.
      */
      const name = p.slice(1);
      const version = publicAssetVersion(name);
      const cache = version && url.searchParams.get('v') === version
        ? 'public, max-age=31536000, immutable' : 'public, max-age=3600';
      /*
        A byte range when one is asked for, because video needs it.

        Safari and iOS do not play a video from a plain 200 with the whole file
        in it: they ask for a range first and give up if the answer ignores the
        header. Chrome tolerates it, which is exactly how this ships broken for
        half the people and fine for whoever tested it.

        A stylesheet is sent as versionAssets writes it, which is not the file
        on disk byte for byte, so it is never sent in pieces. The range carries
        the same cache line as the whole file; it went out no-store, which kept
        the banner video from being kept at all. No Range header means the
        whole file, with Accept-Ranges added so a client knows it may ask.
      */
      if (!/\.css$/i.test(name) &&
          rangeReply(req, res, file, fs.statSync(file).size, { 'content-type': type, 'cache-control': cache }, head)) return;
      const etag = '"' + (version || crypto.createHash('sha256').update(publicAssetBody(name)).digest('hex').slice(0, 16)) + '"';
      if (String(req.headers['if-none-match'] || '') === etag) {
        res.writeHead(304, {
          'etag': etag,
          'cache-control': cache,
          'x-content-type-options': 'nosniff'
        });
        return res.end();
      }
      const extra = { 'Cache-Control': cache, 'ETag': etag };
      if (!/\.css$/i.test(name)) extra['Accept-Ranges'] = 'bytes';
      return send(res, 200, publicAssetBody(name), type, extra);
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
    // The newest of the feed's generations (feedFile), never a name a Ship
    // replaces (#2727).
    const file = feedFile(feedVer[1]);
    if (!file) return send(res, 404, 'no such file', 'text/plain');
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
      branches use, so every new generation of the feed changes it.
    */
    // What the launcher is answered: the whole generation, or once the
    // feed's minLauncher reads it, the update fields alone (feedView, #1050).
    const view = feedView(feedVer[1], file);
    const vtag = view.tag;
    if (String(req.headers['if-none-match'] || '') === vtag) {
      res.writeHead(304, {
        'etag': vtag,
        'cache-control': 'no-cache',
        'x-content-type-options': 'nosniff'
      });
      return res.end();
    }
    return send(res, 200, view.body, 'application/json; charset=utf-8',
      { 'Cache-Control': 'no-cache', 'ETag': vtag });
  }


  // --------------------------------------------------------------- feed watch (#2440)
  // Long-poll tip for open launchers. A launcher holding the ETag of its last
  // version.json waits here until the file changes (or the wait times out),
  // then runs one ordinary conditional feed check. Anonymous, same /feed and
  // /feed-dev folders as version.json. No new timer on the launcher that
  // hammers the document: the tip is quiet until a Ship writes the feed.
  const feedWatch = p.match(/^\/(feed(?:-dev)?)\/watch$/);
  if (feedWatch && req.method === 'GET') {
    const channel = feedWatch[1];
    if (!feedFile(channel)) return send(res, 404, 'no such file', 'text/plain');
    const have = String(req.headers['if-none-match'] || '');
    const WAIT_MS = 50000;
    const started = Date.now();
    const tick = () => {
      if (res.writableEnded || res.destroyed) return;
      // Each tick the newest generation: a Ship's send is a new one (#2727).
      // Generations are never deleted, so only a feed folder taken away by
      // hand ends the wait, with the 404 a channel with no feed answers.
      const file = feedFile(channel);
      let view;
      try { view = feedView(channel, file); }
      catch (e) {
        if (!res.headersSent) return send(res, 404, 'no such file', 'text/plain');
        return;
      }
      // The tag version.json answers with, split or whole (feedView, #1050).
      const tag = view.tag;
      if (!have || have !== tag) {
        if (res.headersSent) return;
        res.writeHead(200, {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
          'etag': tag,
          'x-content-type-options': 'nosniff'
        });
        return res.end(JSON.stringify({ etag: tag }));
      }
      if (Date.now() - started >= WAIT_MS) {
        if (res.headersSent) return;
        res.writeHead(204, {
          'cache-control': 'no-store',
          'etag': tag,
          'x-content-type-options': 'nosniff'
        });
        return res.end();
      }
      const t = setTimeout(tick, 500);
      if (t && typeof t.unref === 'function') t.unref();
    };
    tick();
    return;
  }
  const feedAsset = p.match(/^\/(feed(?:-dev)?)\/assets\/([0-9a-f]{64})$/);
  if (feedAsset && req.method === 'GET') {
    const dir = path.join(ROOT, feedAsset[1], 'assets');
    const file = path.join(dir, feedAsset[2]);
    if (!file.startsWith(dir + path.sep) || !fs.existsSync(file)) {
      // The rest of the feed, which version.json names as "settings" and
      // which is only ever here (feedView, #1050). Small, so no Range.
      const settings = feedSettings(feedAsset[1], feedAsset[2]);
      if (settings) {
        res.writeHead(200, {
          'content-type': 'application/json; charset=utf-8',
          'content-length': settings.length,
          'cache-control': 'public, max-age=31536000, immutable',
          'x-content-type-options': 'nosniff'
        });
        return res.end(head ? undefined : settings);
      }
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
    // ?w= is a waiting picture's smaller copy (#3218), for the staff card.
    const wide = url.searchParams.get('w');
    const file = wide === null ? path.join(UP, up[1])
      : SMALL_WIDTHS.indexOf(Number(wide)) >= 0 ? smallCopy(up[1], Number(wide)) : '';
    if (!file || !file.startsWith(UP + path.sep) || !fs.existsSync(file)) {
      return send(res, 404, 'no such file', 'text/plain');
    }
    /* A gallery submission that staff removed is not served to anybody
       (#2352), whether its file is still on disk because staff chose to keep
       it, because its delete failed, or because the launcher's buttons never
       ask to delete it. The removal marks it on uploads.json (removedUpload). */
    if (uploadRemoved(up[1])) {
      return send(res, 404, 'removed from the gallery', 'text/plain');
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
    // A delete that fails is said, not answered ok (#2352, #2354), and the
    // file's note stays so the uploads list still shows what is on disk.
    const gone = deleteUpload(rm[1]);
    if (!gone.ok) return sendJson(res, 500, { ok: false, name: rm[1], fileKept: true, code: gone.code,
                                              error: 'The file could not be deleted (' + gone.code + '). It is still on the site.' });
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
    const who = await gallerySender(url, w, 'Sign in to the hub, or send a valid launcher ticket.');
    if (!who.ok) return sendJson(res, who.code, who.body);
    const from = who.from, discordId = who.discordId;

    const asked = (url.searchParams.get('name') || 'shot.png').split(/[\\/]/).pop();
    const by = (url.searchParams.get('by') || '').slice(0, 40);
    const note = (url.searchParams.get('note') || '').slice(0, 300);
    return receiveUpload(req, res, asked, GALLERY_CAP, GALLERY_ALLOW, (name) => {
      // The uploads.json note too, so this shot reads the same as any other
      // file in the uploads listing (the orig name, who by, the note). With
      // the account that sent it (#2351): gallery.json keeps no account for a
      // shot once it is approved, because /api/public hands that file out, so
      // this note is how a deletion request finds an approved picture. It is
      // never in the listing (listUploads names its own fields).
      const meta = jsonFile(UPMETA, {});
      meta[name] = { orig: asked, by: by, note: note, at: Date.now() };
      if (discordId) meta[name].discordId = discordId;
      // Neither write was looked at (#2736): a queue that could not be
      // written answered ok, and the shot never reached staff. The note that
      // will not write is said, since a deletion request needs it; the queue
      // that will not write is said and answered, so the sender knows.
      if (!putJson(UPMETA, meta)) console.error('[thornswood-docs] gallery ' + JSON.stringify({ event: 'note-write-failed' }));

      withGalleryPending(() => {
        const pending = jsonFile(GPENDING, []);
        const entry = { name: name, by: by, note: note, at: Date.now(), from: from };
        if (discordId) entry.discordId = discordId;
        pending.push(entry);
        if (!putJson(GPENDING, pending)) {
          console.error('[thornswood-docs] gallery ' + JSON.stringify({ event: 'pending-write-failed' }));
          return sendJson(res, 500, { ok: false, error: 'the site could not put that in the queue for staff. Try again in a minute.' });
        }
        sendJson(res, 200, { ok: true, name: name });
      }).catch((e) => failed(req, res, e));
    });
  }

  /*
    A picture's smaller copies (#3218, SMALL_WIDTHS says why). The body IS
    the copy, a WebP or a JPEG named by its Content-Type, the /api/upload
    way; the picture's name and the copy's width ride in the query, with the
    launcher's ticket as on submit. Whoever sent the picture may send each
    width once while it waits; staff may send or replace one at any time.
    The copy has to be exactly that width and the picture's shape, both read
    off the files' own headers, and the picture has to be wider than it. A
    copy staff send for a picture already on the gallery goes out at once,
    since staff made it from the picture they were looking at; any other
    copy waits for an Accept that showed it.
  */
  if (p === '/api/gallery/copy' && req.method === 'POST') {
    const who = await gallerySender(url, w, 'Sign in to the hub, or send a valid launcher ticket.');
    if (!who.ok) return sendJson(res, who.code, who.body);
    const name = String(url.searchParams.get('name') || '');
    const width = Number(url.searchParams.get('w'));
    if (!/^[A-Za-z0-9._ -]+$/.test(name) || name === 'uploads.json') return sendJson(res, 400, { error: 'Say which picture this is a copy of.' });
    if (SMALL_WIDTHS.indexOf(width) < 0) return sendJson(res, 400, { error: 'A copy is ' + SMALL_WIDTHS.join(' or ') + ' pixels wide.' });
    const entry = jsonFile(GPENDING, []).find((x) => String(x.name) === name);
    const shown = jsonFile(GALLERY, []).find((g) => String(g.name) === name);
    if (!entry && !shown) return sendJson(res, 404, { error: 'That picture is not waiting for staff or on the gallery.' });
    const owner = !!(entry && who.discordId && String(entry.discordId || '') === who.discordId);
    if (!who.dev && !owner) return sendJson(res, 403, { error: 'Only whoever sent that picture, or staff, can send its smaller copies.' });
    if (!who.dev && pendingCopies(entry).indexOf(width) >= 0) {
      return sendJson(res, 409, { error: 'That copy is already in. Staff look at the copies before they Accept, so a copy is not changed once it is sent.' });
    }
    if (uploadRemoved(name)) return sendJson(res, 409, { error: 'That picture was removed from the gallery.' });
    const full = pictureSize(path.join(UP, name));
    if (!full) return sendJson(res, 422, { error: 'The site could not read the size of that picture, so it takes no copy of it.' });
    if (full.w <= width) return sendJson(res, 400, { error: 'That picture is ' + full.w + ' pixels wide, so it needs no ' + width + ' copy.' });
    const type = String(req.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
    const ext = type === 'image/webp' ? '.webp' : type === 'image/jpeg' ? '.jpg' : '';
    if (!ext) return sendJson(res, 415, { error: 'A copy is a WebP or a JPEG.' });
    const tall = Math.round(full.h * width / full.w);
    return receiveUpload(req, res, 'copy' + ext, SMALL_CAP, SMALL_KINDS, (temp) => {
      const sent = path.join(UP, temp);
      const got = pictureSize(sent);
      if (!got || got.w !== width || Math.abs(got.h - tall) > 1) {
        // The file goes, and one that will not go is said by deleteUpload.
        deleteUpload(temp);
        return sendJson(res, 422, { error: 'That copy is ' + (got ? got.w + ' by ' + got.h : 'not a picture the site can read') +
                                           ', and a ' + width + ' copy of this picture is ' + width + ' by ' + tall + '.' });
      }
      // Kept and noted in the queue's turn, so two copies at one width sent
      // together cannot both get in: the second is told it is already in.
      withGalleryPending(() => {
        const pending = jsonFile(GPENDING, []);
        const hit = pending.find((x) => String(x.name) === name);
        if (!who.dev && (!hit || pendingCopies(hit).indexOf(width) >= 0)) {
          deleteUpload(temp);
          return sendJson(res, 409, { error: hit ? 'That copy is already in.' : 'That picture is no longer waiting for staff.' });
        }
        try {
          fs.mkdirSync(UP_SMALL, { recursive: true });
          fs.renameSync(sent, smallFile(name, width, ext));
          // The other kind at this width, if one was sent before, goes, or
          // smallCopy could go on finding it.
          for (const other of SMALL_KINDS) {
            if (other === ext) continue;
            try { fs.unlinkSync(smallFile(name, width, other)); }
            catch (e) { if (!e || e.code !== 'ENOENT') throw e; }
          }
        } catch (e) {
          console.error('[thornswood-docs] could not keep the ' + width + ' copy of ' + name + ' (' + (e.code || e.message) + ')');
          deleteUpload(temp);
          return sendJson(res, 500, { error: 'The site could not keep that copy (' + (e.code || 'unknown') + '). Try again in a minute.' });
        }
        if (hit) {
          const have = pendingCopies(hit).concat(width);
          hit.copies = SMALL_WIDTHS.filter((n) => have.indexOf(n) >= 0);
          if (!putJson(GPENDING, pending)) {
            console.error('[thornswood-docs] gallery ' + JSON.stringify({ event: 'pending-write-failed' }));
            return sendJson(res, 500, { ok: false, error: 'The site kept the copy but could not note it on the queue. Send it again in a minute.' });
          }
        }
        if (who.dev) {
          const gallery = jsonFile(GALLERY, []);
          const item = gallery.find((g) => String(g.name) === name);
          if (item) {
            const srcset = shotSrcset(name, srcsetWidths(item.srcset).concat(width));
            if (srcset) item.srcset = srcset;
            if (!putJson(GALLERY, gallery)) {
              console.error('[thornswood-docs] gallery ' + JSON.stringify({ event: 'gallery-write-failed' }));
              return sendJson(res, 500, { ok: false, error: 'The site kept the copy but could not put it on the gallery. Send it again in a minute.' });
            }
          }
        }
        sendJson(res, 200, { ok: true, name: name, w: width });
      }).catch((e) => failed(req, res, e));
    }, true);
  }

  // The queue, for staff (access.dev) to look through. Never public, so it is
  // its own door rather than a field on /api/public. galleryStaff takes the hub
  // cookie or a launcher ticket for a staff account; everything below it does
  // the same, so the six staff doors have one gate between them.
  if (p === '/api/gallery/pending' && req.method === 'GET') {
    const gs = await galleryStaff(url, w);
    if (!gs.ok) return sendJson(res, gs.code, gs.body);
    // A submission past PENDING_DAYS is not offered while it waits for the
    // sweep to delete it (#2353).
    return sendJson(res, 200, { pending: stalePending(jsonFile(GPENDING, []), Date.now()).left });
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
    // A removed submission does not come back by its name (#2352).
    if (uploadRemoved(name)) return sendJson(res, 409, { error: 'That picture was removed from the gallery, so it cannot be accepted.' });

    const pending = jsonFile(GPENDING, []);
    const hit = pending.find((x) => String(x.name) === name);
    // "by" from the call wins, then the pending entry's, then empty. The url is
    // built here so gallery.json holds exactly the shape /api/public hands out.
    const by = (o.by !== undefined && o.by !== null) ? String(o.by).slice(0, 40)
             : (hit ? String(hit.by || '') : '');

    // The smaller copies the card showed (#3218): those go out with it and
    // no others, so what is public is what staff saw. A caller that names
    // none (a launcher from before the copies) puts it up at full size.
    const showed = Array.isArray(o.copies) ? o.copies.map(Number) : [];
    const copies = pendingCopies(hit).filter((n) => showed.indexOf(n) >= 0);
    const srcset = copies.length ? shotSrcset(name, copies) : '';

    const gallery = jsonFile(GALLERY, []);
    const already = gallery.find((g) => String(g.name) === name);
    if (already) {
      already.url = '/shot/' + name;
      if (by) already.by = by;
      if (srcset) already.srcset = srcset;
    } else {
      const item = { name: name, url: '/shot/' + name, by: by };
      if (srcset) item.srcset = srcset;
      gallery.push(item);
    }
    putJson(GALLERY, gallery);

    const left = pending.filter((x) => String(x.name) !== name);
    if (left.length !== pending.length) putJson(GPENDING, left);
    return sendJson(res, 200, { ok: true, name: name, approved: true, copies: srcsetWidths(srcset) });
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
  // way; there is no separate Reject door. Whether the file goes now or is
  // held for a report is the site's to decide (#2352), not the caller's.
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
    const itsReports = reports.filter((r) => String(r.name) === name);
    if (kept.length !== reports.length) putJson(GREPORTS, kept);

    /*
      The file (#2352, option C). Deleted, unless the submission had an open
      report against it: then it is taken down after a report, and its file
      stays on the site's disk, unshown, for GALLERY_HOLD_DAYS with those
      reports beside it on uploads.json, and pruneRemovedUploads deletes it
      once that time is up. deleteFile from a client is no longer read: the
      hub asked it as a second question and the launcher never sent it, so
      the same removal kept or deleted the file depending on the button.
      Either way the file is marked removed while it is on disk, which
      /up/<name> refuses, so a removed submission is not served to anybody.
      A delete that fails is said, never answered ok: the entry is still off
      both lists, the file is marked removed so it is not served, the answer
      and the site's log say it is still there, and the retention timer
      deletes it once it can.
    */
    const answer = {
      ok: true,
      name: name,
      removed: removedGal + removedPend,
      removedApproved: removedGal,
      removedPending: removedPend,
      fileDeleted: false
    };
    const file = path.join(UP, name);
    if (file.startsWith(UP + path.sep) && fs.existsSync(file)) {
      const now = Date.now();
      const hold = itsReports.length > 0;
      const gone = hold ? { ok: false, code: '' } : deleteUpload(name);
      const meta = jsonFile(UPMETA, {});
      if (gone.ok) {
        delete meta[name];
        answer.fileDeleted = true;
      } else {
        meta[name] = Object.assign({}, meta[name] || {}, { removed: now });
        if (hold) {
          meta[name].heldUntil = now + GALLERY_HOLD_DAYS * 86400000;
          meta[name].heldReports = itsReports.slice(-20);
          answer.heldForReport = true;
          answer.heldUntil = meta[name].heldUntil;
        }
      }
      if (!putJson(UPMETA, meta)) {
        // Unmarked, a kept file would still be served at /up/<name>.
        retentionSay('gallery', { event: 'note-write-failed', file: name });
        answer.ok = false;
        answer.fileKept = !gone.ok;
        answer.error = 'Taken off the gallery, but the site could not record that, so ' +
                       (gone.ok ? 'its note is still listed.' : 'its file can still be opened by staff. Try again.');
        return sendJson(res, 500, answer);
      }
      if (!hold && !gone.ok) {
        answer.ok = false;
        answer.fileKept = true;
        answer.code = gone.code;
        answer.error = 'Taken off the gallery, but its file could not be deleted (' + gone.code +
                       '). It is no longer shown anywhere, and the site deletes it within the hour once it can.';
        return sendJson(res, 500, answer);
      }
    }
    return sendJson(res, 200, answer);
  }

  // Report an approved shot. Any signed-in play-capable member, or the
  // launcher with the same ticket /api/gallery/submit takes. The report sits
  // in gallery-reports.json for staff; it does not take the shot down.
  if (p === '/api/gallery/report' && req.method === 'POST') {
    const who = await gallerySender(url, w, 'Sign in, or send a valid launcher ticket.');
    if (!who.ok) return sendJson(res, who.code, who.body);
    const from = who.from, discordId = who.discordId;

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
    // Keep the newest 500 so a flood cannot grow the file forever, and none
    // past GREPORTS_DAYS (#2353).
    putJson(GREPORTS, freshGalleryReports(reports, Date.now()).slice(-500));
    return sendJson(res, 200, { ok: true, id: id });
  }

  if (p === '/api/gallery/reports' && req.method === 'GET') {
    const gs = await galleryStaff(url, w);
    if (!gs.ok) return sendJson(res, gs.code, gs.body);
    return sendJson(res, 200, { reports: freshGalleryReports(jsonFile(GREPORTS, []), Date.now()) });
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
    // access.devBuild (Owner, Co-Owner, Dev and the leads, #3317, unless
    // config.json says otherwise); anyone else is sent back to the main build
    // with a plain reason.
    const wantsDev = String(o.channel || '') === 'dev';
    if (wantsDev && !st.devBuild) return sendJson(res, 403, { ok:false, why:'dev', dev: false, message:
      'The dev build is for the ' + andList(cfg.access.devBuild) + ' roles. Play on the main build.' });
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
    /* Not recorded is not let in: the door lists only what linked.json holds.
       It used to answer yes whatever the write did, and a linked.json that
       will not read is never written over (#2180), so the launcher went on
       to a door that would turn the character away with no reason given. */
    if (!putJson(LINKED, linked)) {
      console.error('[thornswood-docs] check in for Discord ' + t.d + ' not recorded: linked.json was not written');
      return sendJson(res, 503, { ok: false, why: 'not recorded', message:
        'The site could not record this character against your account, so the game would not let it in. ' +
        'Try again later, and tell staff if it keeps happening.' });
    }

    return sendJson(res, 200, {
      ok: true,
      id: st.id,
      name: st.name || t.n,
      avatar: st.avatar || '',
      admin: st.admin,
      dev: !!st.dev,
      // Whether this account may install and play the dev build
      // (access.devBuild, #3317). dev above is staff in the game.
      devBuild: !!st.devBuild,
      roles: st.roles,
      slots: slotsFor(st),
      // Whether the profile id sent is now against this account. False when
      // none was sent, and when another account already holds it, in which
      // case it was left off this one and the door still said yes.
      claimed: claimed,
      // The world is full: in, but there may be a wait at the menu (#481).
      wait: wait,
      message: wait ? worldFull(gameStatus.online) : '',
      online: gameStatus.online,
      max: gameStatus.max || mostOnlineFallback(),
      line: gameStatus.line,
      // Which crashes behind the snapshots this launcher holds staff have
      // marked looked at (#2319, lookedAtFor): those it may delete.
      lookedAt: lookedAtFor(sessionRows(), t.d, o.snapshots).join(',')
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
    // pruneSessionLogs says its own failures and never throws (#2354).
    if (ending) pruneSessionLogs();
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
    // putSessionLogs has said why in the site's log. 500 is what the launcher
    // keeps the logs for and sends again at its next start (#2736).
    if (what === 'failed') return sendJson(res, 500, { ok: false, why: 'could not save' });

    /* Read them once, now, so the page can colour this one session and the
       bot can say so in Discord. Done here rather than when somebody opens
       the page, because the point is that nobody has to open the page for
       anybody to find out.

       The launcher's own blockers and warnings come with the logs, already
       structured, and they carry more than the launcher's window shows: which
       plugin, whether it is absent or merely wrong, and the size, CRC and
       manifest index the server wanted. Those are kept whole.

       NOT IN A TRY (#2736). All of this sat in a try whose catch was empty, so
       a failure stored the logs, answered ok, and the session's trouble
       colour and the bot's crash note never happened with nothing said. What
       can fail here is said where it fails, the session key and the error
       code and never what the logs hold: the server log that will not read,
       the row that will not write, the note for the bot that will not write
       (noteTrouble says its own). The logs are stored by now, so the answer
       stays 200 stored, and says read false or noted false for what did not
       happen. Nothing else here throws on what JSON.parse hands it; a bug
       that does is failed()'s 500 and its stack in site.log. */
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
       order (#945). No server log on this box is the dev machine and says
       nothing; one that is there and will not read is said. */
    const row = rows[at];
    const from = (Number(row.start) || Number(row.end) || 0) - 60000;
    const to = (Number(row.end) || Date.now()) + 60000;
    const server = serverLogSlice(row.channel, from, to);
    if (!server.ok && server.code) {
      console.error('[thornswood-docs] session-logs ' + JSON.stringify({ event: 'server-log-unread', session: key, code: server.code }));
    }

    const found = readTrouble(logs, server.lines, row.profile);
    applyTrouble(row, found);
    row.troubleRules = TROUBLE_RULES;

    const answer = { ok: true, stored: true };
    if (!putSessions(rows)) {
      console.error('[thornswood-docs] session-logs ' + JSON.stringify({ event: 'row-write-failed', session: key }));
      answer.read = false;
    }
    /* Only a crash is worth saying out loud. */
    if (found && found.level === 'bad' && !noteTrouble(rows[at], found)) answer.noted = false;

    return sendJson(res, 200, answer);
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
  /* Whether the files play and identity rest on read (#2180): 200, or 503
     naming each one that is there and will not read, and whether it shuts
     play. Deploy-Docs asks it after every swap. Names and reasons only,
     never what a file holds. */
  if (route === '/api/ready' && req.method === 'GET') {
    const broken = heldBroken();
    return sendJson(res, broken.length ? 503 : 200, { ok: !broken.length, broken });
  }
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
    const out = { profiles: [], devProfiles: [], adminProfiles: [], offices: {}, jarlClash: [], staffRoleProfiles: [], businessOwnerProfiles: [], factionLeaderProfiles: {}, factionLeaderClash: [], devRoleProfiles: [], companyProfiles: [], people: [], lookupFailed: false, lookupFailedWhy: '', failedProfiles: [], at: Date.now() };
    const seen = new Set();
    const seenDev = new Set();
    const seenAdmin = new Set();
    const seenStaffRole = new Set();
    const seenBusiness = new Set();
    // Leader role -> account -> that account's profiles, so a Leader role two
    // accounts hold can come off both below.
    const leaderAccounts = new Map();
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
      if (devDoor && !st.devBuild) continue;
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
      // A Discord staff role itself, not the hand written admins list, for
      // the staff seats over the most the world holds (#481).
      if (st.staffRole) {
        for (const n of profiles) if (!seenStaffRole.has(n)) { seenStaffRole.add(n); out.staffRoleProfiles.push(n); }
      }
      if (st.businessOwner) {
        for (const n of profiles) if (!seenBusiness.has(n)) { seenBusiness.add(n); out.businessOwnerProfiles.push(n); }
      }
      for (const role of (st.leads || [])) {
        if (!leaderAccounts.has(role)) leaderAccounts.set(role, new Map());
        leaderAccounts.get(role).set(String(d), profiles);
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
    /* THE HOLD OFFICES (#2551), by profile, for every account let in above
       (out.people), read from its roles: the game reads every office through
       this and nothing else. And one Jarl a hold: a hold's Jarl role two
       accounts hold comes off both, and staff are told (officesForDoor). */
    out.jarlClash = await officesForDoor(out, answers, linked);
    /* THE FACTION BOOKS (#3317): each faction's Leader role and the profiles
       of the account that holds it. One Leader a faction, like one Jarl a
       hold: a Leader role two accounts hold goes to neither, so the book
       stays with nobody new until staff fix it, and the bot's faction panel
       refuses both the same way (bot.py leader_held_twice). */
    for (const [role, accounts] of leaderAccounts) {
      if (accounts.size > 1) { out.factionLeaderClash.push(role); continue; }
      for (const pl of accounts.values()) out.factionLeaderProfiles[role] = pl.slice();
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
    // A broken ban list lets nobody through the door (#2186), and so does a
    // pk.json or linked.json that will not read (#2180): every list is
    // emptied and the door is told why.
    const shut = out.bans.broken || out.pk.broken;
    if (shut) {
      out.bansBroken = !!out.bans.broken;
      out.stateBroken = shut;
      for (const k of ['profiles', 'devProfiles', 'adminProfiles', 'staffRoleProfiles', 'failedProfiles']) {
        if (Array.isArray(out[k])) out[k] = [];
      }
      if (Array.isArray(out.people)) out.people = [];
      out.offices = {};
      out.factionLeaderProfiles = {};
    }
    const barred = new Set(out.pk);
    for (const b of out.bans) for (const n of b.profiles) barred.add(Number(n));
    if (barred.size) {
      for (const k of ['profiles', 'devProfiles', 'adminProfiles', 'staffRoleProfiles', 'failedProfiles']) {
        out[k] = out[k].filter((n) => !barred.has(Number(n)));
      }
      for (const n of Object.keys(out.offices)) if (barred.has(Number(n))) delete out.offices[n];
      for (const k of ['businessOwnerProfiles', 'devRoleProfiles', 'companyProfiles']) {
        out[k] = out[k].filter((n) => !barred.has(Number(n)));
      }
      for (const role of Object.keys(out.factionLeaderProfiles)) {
        out.factionLeaderProfiles[role] = out.factionLeaderProfiles[role].filter((n) => !barred.has(Number(n)));
        if (!out.factionLeaderProfiles[role].length) delete out.factionLeaderProfiles[role];
      }
      out.people = out.people.map((p) => Object.assign({}, p, { profiles: p.profiles.filter((n) => !barred.has(Number(n))) }))
        .filter((p) => p.profiles.length);
    }
    return sendJson(res, 200, out);
  }

  /*
    A Jarl's office change, from the game (#2551): the Office page of K, sent
    by the game server with the door's key, the same key /api/allowed takes,
    in the same header. Only a game server can ask. changeOffice checks every
    rule again and sets the role in Discord; the game reads it back through
    /api/allowed. The dev server's door names the site with /dev, so its
    question lands on /dev/api/office: the roles are the same Discord's, so a
    change made on dev is a real role.
  */
  if ((route === '/api/office' || route === '/dev/api/office') && req.method === 'POST') {
    if (!cfg.botKey) return sendJson(res, 404, { error: 'not set up' });
    const given = req.headers['x-thornswood-key'];
    if (given === undefined || !sameSecret(String(given), String(cfg.botKey))) {
      return sendJson(res, 401, { error: 'no' });
    }
    let o = {};
    try { o = JSON.parse(await body(req, 4096)) || {}; } catch (e) {
      return sendJson(res, 400, { ok: false, said: 'The site could not read that request.' });
    }
    return sendJson(res, 200, await changeOffice(o, route === '/dev/api/office' ? 'dev' : 'main'));
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
    if (server === 'dev' && !st.devBuild) return sendJson(res, 403, { ok: false, why: 'dev', message:
      'The dev build is for the ' + andList(cfg.access.devBuild) + ' roles. Play on the main build.' });

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
    if (bar && bar.shut) return sendJson(res, 503, { ok: false, why: 'state broken', message:
      'The site cannot read its list of characters right now, so nobody can join until staff repair it. Try again later.' });
    if (bar && bar.pk) return sendJson(res, 403, { ok: false, why: 'pk', message:
      'That character has died for good and cannot be played again. ' +
      'Pick another character at the menu, or make a new one.' });
    if (bar) return sendJson(res, 403, { ok: false, why: 'banned character', until: bar.until, message:
      'Staff have banned that character ' + banUntilText(bar.until) +
      (bar.why ? ': ' + bar.why : '') + '. Pick another character at the menu.' });
    const pass = makePass(cfg.passKey, { p: pid, s: server, v: said, d: String(t.d), i: now, x: now + PASS_MS });
    return sendJson(res, 200, { ok: true, pass: pass, key: passLoginKey(cfg.passKey, pass), until: now + PASS_MS, server: server });
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
        inbox: w.admin ? trimInbox(jsonFile(INBOX, []), Date.now()) : []
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
      let keptChat = null;
      try {
        const f = slogFile(key);
        if (fs.existsSync(f)) {
          const set = JSON.parse(fs.readFileSync(f, 'utf8')) || {};
          client = set.logs || {};
          if (row.keep && isObjectLike(set.chat) && Array.isArray(set.chat.lines)) keptChat = set.chat;
          /* The provenance, so the page can show where this came from and
             whether anybody tried to send a second set over it. A set that
             holds only a kept session's chat was not sent by anybody. */
          if (!set.chatOnly) sent = {
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
      const { from, to } = sessionWindow(row);
      const server = serverLogSlice(row.channel, from, to);
      /* A kept session's chat is its copy (#2166), which outlives the voice
         service's day files; otherwise the day files, read now. */
      const chat = keptChat ? { why: '', lines: keptChat.lines } : chatSlice(row.profile, from, to, row.channel);

      return sendJson(res, 200, {
        session: key,
        channel: row.channel,
        client,
        sent,
        /* What they said, in this session only. The page shows it beside the
           logs rather than on a page of its own. */
        chat: chat.lines,
        chatWhy: chat.why,
        chatKept: !!keptChat,
        chatCopiedAt: keptChat ? Number(keptChat.copiedAt) || 0 : 0,
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
      /* The chat it rests on is held with it (#2166), or let go with it. */
      const chatCopy = on ? copyKeptChat(rows[at]) : dropKeptChat(key);
      return sendJson(res, 200, { ok: true, keep: on, chatCopy });
    }

    /* Mark a crash looked at, or take the mark off again (#2319, crashedRow
       and markLooked). The person's launcher deletes that crash's snapshot
       at a Play after its next check in, so the mark is the word that
       nobody needs it any more. Admins only, like the page, and it records
       who and when. */
    if (p === '/api/session-looked' && req.method === 'PUT') {
      let obj;
      try { obj = JSON.parse(await body(req)); }
      catch (e) { passBodyFailure(e); return sendJson(res, 400, { error: 'bad json' }); }
      const key = sessionKey(obj && obj.session);
      const rows = sessionRows();
      const at = key ? findSession(rows, key, obj.who) : -1;
      if (at < 0) return sendJson(res, 404, { error: 'no such session' });
      if (!crashedRow(rows[at])) return sendJson(res, 400, { error: 'not a crash',
        message: 'Only a session that crashed can be marked looked at.' });
      markLooked(rows[at], !!(obj && obj.looked), w.name, Date.now());
      if (!putSessions(rows)) return sendJson(res, 500, { error: 'could not save' });
      const row = rows[at];
      return sendJson(res, 200, { ok: true, looked: !!row.looked, lookedBy: row.lookedBy || '', lookedAt: row.lookedAt || 0 });
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
      // The whole list, back from the hub, through the same keeping time as
      // every other write (#2353), so a list the hub read before a row aged
      // out cannot write that row back.
      if (!Array.isArray(obj)) return sendJson(res, 400, { error: 'the inbox is a list' });
      if (!putJson(INBOX, trimInbox(obj, Date.now()))) return sendJson(res, 500, { error: 'could not save' });
      return sendJson(res, 200, { ok: true });
    }

    return sendJson(res, 404, { error: 'no such endpoint' });
  }

  // The site's own look for a person, the same four characters for anything
  // that did not ask for HTML. See notFoundPage above.
  if (wantsHtml(req)) { return send(res, 404, notFoundPage(), TYPES['.html']); }
  send(res, 404, 'not here', 'text/plain');
}

// ==== thornswood deletion requests ====
/*
  A DELETION REQUEST IS TAKEN OUT OF THE SITE'S FILES AS IT STARTS (#2758).

  Patrick, 18 Oct 2026, after the first real deletion on his own account: "it
  should not restart everytime we want to delete a person it should just fully
  apply the rest upon a server restart". scripts\vps\Delete-Person.ps1 stops
  nothing: it writes the request into data\deletion-requests.json, and the
  site takes it out of its own files here, before it listens, so nothing it
  serves can write one of them back while it goes:

      { "people": [ { "discordId": "111111111111111111", "profiles": [ 5001 ] } ] }

  The profiles are the characters Delete-Person.ps1 found were theirs alone;
  the ones linked.json holds for them now, and no other account holds, are
  added, so a character made since the request goes too.

  What goes, the same as Delete-Person.ps1 removes from a copy of this folder
  that nothing runs from: their Discord link, their answer to the rules, their
  sign-in rows, their session rows with the launcher logs and failed-session
  alerts about them, their characters' roster rows, the tickets, applications
  and calls for help they sent, and their gallery pictures, waiting or
  approved, with the file. What stays: a session staff marked kept with its
  logs and alerts, reports they made or that were made about them, and a
  picture held while a report about it is looked into (#2352). Staff's own
  records (bans, notes, PKs, the staff log) are never read here.

  Every file is read before any is written; one that is there and will not
  parse leaves the request where it is, and the start goes on. A write that
  does not take is said and the request waits for the next start; running it
  again finds what is already gone gone. When every part took, the request is
  deleted. The log says counts and never a Discord id, a profile id or a name.
*/
function applyDeletionRequests() {
  const FILE = path.join(DATA, 'deletion-requests.json');
  const say = (m) => console.log('[thornswood-docs] deletion requests: ' + m);
  const isObj = (v) => !!v && typeof v === 'object' && !Array.isArray(v);
  const has = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
  // { v } for a file that read, { v: fallback, missing } for one not there,
  // null (said) for one that is there and will not read or parse.
  const read = (p, fallback) => {
    let t;
    try { t = fs.readFileSync(p, 'utf8'); }
    catch (e) {
      if (e.code === 'ENOENT') return { v: fallback, missing: true };
      say(path.basename(p) + ' could not be read (' + e.code + ')');
      return null;
    }
    try { return { v: JSON.parse(t.replace(/^\uFEFF/, '')) }; }
    catch (e) { say(path.basename(p) + ' will not parse'); return null; }
  };
  const req = read(FILE, null);
  if (!req || req.missing) return;
  const people = req.v && Array.isArray(req.v.people) ? req.v.people : null;
  if (!people || !people.every((x) => isObj(x) && /^\d{17,20}$/.test(String(x.discordId)) && Array.isArray(x.profiles))) {
    say(path.basename(FILE) + ' is not a list of deletion requests, so nothing was removed and it is left as it is');
    return;
  }

  const SPEC = [
    ['linked', LINKED, {}], ['rules', RULES_OK, {}], ['signins', ATTEMPTS, []], ['sessions', SESSIONS, []],
    ['trouble', TROUBLE_FILE, []], ['roster', ROSTER, {}], ['inbox', INBOX, []], ['pending', GPENDING, []],
    ['gallery', GALLERY, []], ['reports', GREPORTS, []], ['umeta', UPMETA, {}]
  ];
  const f = {};
  for (const [k, p, fallback] of SPEC) {
    const r = read(p, fallback);
    if (!r) { say('nothing was removed, and the request waits for the next start'); return; }
    if (Array.isArray(fallback) !== Array.isArray(r.v) || !(Array.isArray(r.v) || isObj(r.v))) {
      say(path.basename(p) + ' is not the shape it should be, so nothing was removed, and the request waits for the next start');
      return;
    }
    f[k] = { p, v: r.v, dirty: false };
  }
  const counts = {};
  const gone = (k, n) => { if (n) counts[k] = (counts[k] || 0) + n; };
  const unlinks = new Set();
  const now = Date.now();

  for (const person of people) {
    const id = String(person.discordId);
    const L = f.linked.v;
    const P = new Set(person.profiles.map(Number).filter((n) => Number.isSafeInteger(n) && n > 0));
    if (isObj(L[id]) && Array.isArray(L[id].profiles)) {
      for (const n of L[id].profiles) {
        const pid = Number(n);
        const other = Object.keys(L).some((o) => o !== id && isObj(L[o]) && Array.isArray(L[o].profiles) && L[o].profiles.map(Number).includes(pid));
        if (pid > 0 && !other) P.add(pid);
      }
    }
    const mine = (v) => P.has(Number(v));
    if (has(L, id)) { delete L[id]; f.linked.dirty = true; gone('Discord link', 1); }
    if (has(f.rules.v, id)) { delete f.rules.v[id]; f.rules.dirty = true; gone('answer to the rules', 1); }
    const filter = (k, keepIt, label) => {
      const keep = f[k].v.filter(keepIt);
      if (keep.length !== f[k].v.length) { gone(label, f[k].v.length - keep.length); f[k].v = keep; f[k].dirty = true; }
    };
    filter('signins', (x) => !(isObj(x) && String(x.id) === id), 'sign-in rows');
    const kept = new Set(), ended = new Set();
    filter('sessions', (x) => {
      if (!(isObj(x) && String(x.who) === id)) return true;
      if (x.keep) { kept.add(String(x.session)); return true; }
      ended.add(String(x.session));
      return false;
    }, 'session rows');
    let logs = [];
    try { logs = fs.readdirSync(SLOGS).filter((n) => /\.json$/i.test(n)); }
    catch (e) { if (e.code !== 'ENOENT') { say('the launcher logs could not be listed (' + e.code + '), so nothing was removed, and the request waits for the next start'); return; } }
    for (const n of logs) {
      const p = path.join(SLOGS, n);
      const r = read(p, null);
      if (!r || !isObj(r.v)) continue;
      if (String(r.v.who) !== id && !ended.has(String(r.v.session))) continue;
      if (!kept.has(String(r.v.session))) unlinks.add(p);
    }
    filter('trouble', (x) => {
      const theirs = isObj(x) && (String(x.who) === id || mine(x.profile) || ended.has(String(x.session)));
      return !theirs || kept.has(String(x.session));
    }, 'failed-session alerts');
    const R = f.roster.v;
    if (isObj(R.who)) for (const k of Object.keys(R.who)) if (mine(k)) { delete R.who[k]; f.roster.dirty = true; gone('roster rows', 1); }
    if (isObj(R.servers)) {
      for (const sv of Object.values(R.servers)) {
        if (!isObj(sv)) continue;
        for (const k of ['checked', 'held']) {
          if (!Array.isArray(sv[k])) continue;
          const keep = sv[k].filter((n) => !mine(n));
          if (keep.length !== sv[k].length) { sv[k] = keep; f.roster.dirty = true; }
        }
      }
    }
    filter('inbox', (x) => {
      if (!isObj(x)) return true;
      const sent = String(x.discordId || '') === id || mine(x.profileId);
      return !sent || x.kind === 'report' || x.ticket === 'report';
    }, 'tickets, applications and calls for help');
    const ok = (name) => /^[A-Za-z0-9._ -]+$/.test(name) && name !== 'uploads.json';
    filter('pending', (x) => {
      if (!(isObj(x) && String(x.discordId || '') === id)) return true;
      const name = String(x.name || '');
      if (ok(name)) {
        unlinks.add(path.join(UP, name));
        if (has(f.umeta.v, name)) { delete f.umeta.v[name]; f.umeta.dirty = true; }
      }
      return false;
    }, 'gallery submissions waiting for staff');
    const reported = new Set(f.reports.v.filter(isObj).map((x) => String(x.name)));
    for (const name of Object.keys(f.umeta.v)) {
      const m = f.umeta.v[name];
      if (!isObj(m) || String(m.discordId || '') !== id || !ok(name)) continue;
      if (reported.has(name) || (m.removed && Number(m.heldUntil) > now)) continue;
      const before = f.gallery.v.length;
      f.gallery.v = f.gallery.v.filter((g) => !(isObj(g) && String(g.name) === name));
      if (f.gallery.v.length !== before) { f.gallery.dirty = true; gone('approved gallery pictures', 1); }
      else gone('other gallery files they sent', 1);
      unlinks.add(path.join(UP, name));
      delete f.umeta.v[name];
      f.umeta.dirty = true;
    }
  }

  let whole = true;
  for (const k of Object.keys(f)) {
    if (f[k].dirty && !putJson(f[k].p, f[k].v)) { say(path.basename(f[k].p) + ' could not be written'); whole = false; }
  }
  for (const p of unlinks) {
    try { fs.unlinkSync(p); gone(path.dirname(p) === SLOGS ? 'launcher logs' : 'gallery files', 1); }
    catch (e) { if (e.code !== 'ENOENT') { say(path.basename(p) + ' could not be deleted (' + e.code + ')'); whole = false; } }
  }
  const said = Object.keys(counts).map((k) => k + ' ' + counts[k]).join(', ') || 'nothing of theirs';
  if (!whole) { say(people.length + ' person(s): ' + said + '; the rest waits for the next start'); return; }
  try { fs.unlinkSync(FILE); say(people.length + ' person(s): ' + said + '; done, and the request is gone'); }
  catch (e) { say(people.length + ' person(s): ' + said + '; the request could not be deleted (' + e.code + '), so it runs again at the next start'); }
}
// ==== end thornswood deletion requests ====
applyDeletionRequests();

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
  console.log('[thornswood-docs] trusting ' + tls.getCACertificates('default').length +
              ' root certificates, leaving out ' + (LEFT_OUT.join(', ') || 'none'));
  rereadTrouble();
  // The first retention pass, then every hour (#2350).
  retentionSweep();
  // The files play and identity rest on, read once on the way up (#2180).
  // Each broken one has said STATE BROKEN or BANS BROKEN above this line.
  const notReady = heldBroken();
  console.log('[thornswood-docs] ' + (notReady.length
    ? 'NOT READY: ' + notReady.map((b) => b.file).join(', ') + ' will not read, /api/ready answers 503'
    : 'ready: bans, pk, linked, sessions and signins read'));
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
    }).catch((e) => {
      // Said rather than dropped (#2736): a failure here is the roles read, and
      // without this line nobody learns the check on the way up never finished.
      console.error('[thornswood-docs] could not finish asking Discord on the way up: ' + ((e && (e.code || e.message)) || e));
    });
  }
});
