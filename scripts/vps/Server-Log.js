'use strict';
/*
  Server-Log.js

  Writes the game server's log, server.log, and keeps nothing in it, or in any
  rolled copy of it, for longer than 30 days. It goes up beside the server as
  server-log.js, and the server's scheduled task runs the server under it:

      cmd /c "start "" /b /wait /high node server-log.js --log <root>\server.log dist_back/skymp5-server.js & call exit %^errorlevel%"

      node server-log.js --log <root>\server.log --roll     rolls it now and applies the 30 days, then exits (an install)

  WHY (#2349). The engine writes the address of every connection into its
  console ("Connecting a user N with ip ...", skymp5-server ts/systems/login.ts),
  beside the line that names the slot's Discord id. Until 12 Oct 2026 that
  console went to server.log through cmd's >> server.log 2>&1, and cmd holds
  that file open for as long as the server runs, so the only roll it could
  have was Roll-Log.ps1 in front of each start, by size, five kept. Nothing
  aged it: a server that was not restarted kept one file growing, and the
  five rolled ones held whatever they held, however old. Measured 12 Oct: the
  oldest connecting address on disk was from 21 Sep on live and 4 Oct on dev,
  while the privacy page said the 30-day sign-in log was the only thing
  holding an address. Decided by Patrick on 12 Oct (#2349, B and C): the
  server log is deleted after 30 days, and the privacy page says it holds the
  address for that long.

  HOW. This process starts the server as its child with both streams piped to
  it, and is the only thing that holds server.log. So it can roll the file
  whenever it needs to, which cmd's redirect never allowed:

    - at local midnight, so server.log only ever holds today's lines,
    - at 4 MB, the size Roll-Log.ps1 rolled at,
    - at a start, when the server.log there is from another day or full.

  A rolled file is server.log.<when it was rolled>, digits only, local time to
  the millisecond (server.log.20261012235959123). Nothing is renumbered, so a
  roll is one rename and no reader holding an older file can stop it.

  THE 30 DAYS. Every line the engine writes starts with its local time,
  "[2026-10-12 21:40:03.155]" (the site's serverLogSlice reads the same
  stamp); a line without one belongs to the line above it, which is what a
  stack trace is. At a start, at every roll and once an hour, each rolled file
  loses every line from before 30 days ago, with the unstamped lines that
  belong to them, and a file with nothing left is deleted. So no line older
  than 30 days and an hour is ever on disk, and the files Roll-Log.ps1 left
  (server.log.1 to .5, weeks in each) are cut the same way on the first start.
  A file with no stamped line at all goes by its last write.

  WHAT IS SAID. Each roll that deletes or cuts anything, and every failure, is
  a line in server.log itself, "[<time>] [server-log] ...", stamped like the
  engine's. A file that could not be cut or deleted is named with the error,
  and the next hourly pass is the next try (another program holding a file is
  the one failure here outside our control). A write that fails is said on
  stderr at once and in server.log as soon as a write works again, with how
  much was lost; the server is never stopped or slowed over its log.

  THE SERVER IS STILL WHAT THE TASK RUNS. Its exit code is this process's
  exit code, so call exit %^errorlevel% still hands it to the task. Started
  by start /high, this runs High, and the server is set to this process's own
  priority the moment it starts, because Windows starts a child of a High
  process at Normal (Install-ThornswoodServer.ps1, #2491). Node puts the child
  in a job that ends it when this process ends, so stopping either stops both
  (measured 12 Oct: the child was gone a second after its parent was killed).
  Measured the same day: 20,000 lines written by a child that then called
  process.exit all reached the parent, so the pipe loses nothing of a crash
  that cmd's file did not.
*/
const fs = require('fs');
const path = require('path');
const os = require('os');
const cp = require('child_process');

const KEEP_DAYS = 30;
const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_BYTES = 4 * 1024 * 1024;
const SWEEP_MS = 60 * 60 * 1000;
const HEAD_BYTES = 64 * 1024;
const STAMP = /^\[(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})/;

function pad(n, w) { return String(n).padStart(w || 2, '0'); }
function stampOf(d) {
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' +
    pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds()) + '.' + pad(d.getMilliseconds(), 3);
}
function dayKey(t) { const d = new Date(t); return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate(); }
function lineTime(text) {
  const m = STAMP.exec(text);
  return m ? new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]).getTime() : null;
}

// Every rolled copy beside the log: server.log.<digits>, the numbered ones
// Roll-Log.ps1 made as well as the dated ones made here.
function rolledFiles(log) {
  const dir = path.dirname(log), base = path.basename(log);
  let names = [];
  try { names = fs.readdirSync(dir); } catch (e) { return []; }
  return names.filter((n) => n.length > base.length + 1 && n.slice(0, base.length + 1).toLowerCase() === (base + '.').toLowerCase() &&
    /^\d+$/.test(n.slice(base.length + 1))).map((n) => path.join(dir, n));
}

function rolledName(log, at) {
  const d = new Date(at);
  const s = '' + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + pad(d.getHours()) + pad(d.getMinutes()) +
    pad(d.getSeconds()) + pad(d.getMilliseconds(), 3);
  let name = log + '.' + s, n = 0;
  while (fs.existsSync(name)) { n++; name = log + '.' + s + n; }
  return name;
}

// The time of the first stamped line in a buffer, or null.
function firstStamp(buf) {
  let at = 0;
  while (at < buf.length) {
    const t = lineTime(buf.toString('latin1', at, Math.min(buf.length, at + 24)));
    if (t !== null) return t;
    const nl = buf.indexOf(10, at);
    if (nl < 0) break;
    at = nl + 1;
  }
  return null;
}

function readHead(file) {
  const fd = fs.openSync(file, 'r');
  try {
    const buf = Buffer.alloc(HEAD_BYTES);
    const n = fs.readSync(fd, buf, 0, HEAD_BYTES, 0);
    return buf.subarray(0, n);
  } finally { fs.closeSync(fd); }
}

/*
  One rolled file brought inside the window. Returns what happened:
  'kept', 'cut' or 'deleted'. Throws on a file it could not change, and the
  caller says so.
*/
function trimFile(file, cutoff) {
  const st = fs.statSync(file);
  const head = readHead(file);
  const first = firstStamp(head);
  if (first !== null && first >= cutoff) return 'kept';
  const buf = (head.length < HEAD_BYTES) ? head : fs.readFileSync(file);
  let at = 0, cut = -1, stamped = false;
  while (at < buf.length) {
    const t = lineTime(buf.toString('latin1', at, Math.min(buf.length, at + 24)));
    if (t !== null) {
      stamped = true;
      if (t >= cutoff) { cut = at; break; }
    }
    const nl = buf.indexOf(10, at);
    if (nl < 0) break;
    at = nl + 1;
  }
  if (!stamped) {
    if (st.mtimeMs >= cutoff) return 'kept';
    fs.unlinkSync(file);
    return 'deleted';
  }
  if (cut < 0) { fs.unlinkSync(file); return 'deleted'; }
  if (cut === 0) return 'kept';
  const tmp = file + '.cut-' + process.pid;
  try {
    fs.writeFileSync(tmp, buf.subarray(cut));
    fs.utimesSync(tmp, st.atime, st.mtime);
    fs.renameSync(tmp, file);
  } catch (e) {
    if (fs.existsSync(tmp)) {
      try { fs.unlinkSync(tmp); } catch (e2) { e.message += '; and its part copy ' + path.basename(tmp) + ' is left: ' + e2.code; }
    }
    throw e;
  }
  return 'cut';
}

// Every rolled file brought inside the window. Returns the lines to say.
function sweep(log, now) {
  const cutoff = now - KEEP_DAYS * DAY_MS;
  const said = [];
  let deleted = 0, cut = 0;
  for (const f of rolledFiles(log)) {
    try {
      const r = trimFile(f, cutoff);
      if (r === 'deleted') deleted++;
      if (r === 'cut') cut++;
    } catch (e) {
      said.push('could not take the lines older than ' + KEEP_DAYS + ' days out of ' + path.basename(f) +
        ': ' + e.message + '. The next pass, within the hour, tries it again.');
    }
  }
  if (deleted || cut) {
    said.unshift('older than ' + KEEP_DAYS + ' days: ' + deleted + ' rolled log' + (deleted === 1 ? '' : 's') + ' deleted, ' +
      cut + ' cut to the last ' + KEEP_DAYS + ' days');
  }
  return said;
}

// Moves the live log aside. Returns the rolled name, or null for nothing to roll.
function rollFile(log, now) {
  let st;
  try { st = fs.statSync(log); } catch (e) { if (e.code === 'ENOENT') return null; throw e; }
  if (!st.size) return null;
  const to = rolledName(log, now);
  fs.renameSync(log, to);
  return to;
}

// Whether the server.log found at a start is appended to (today's, under the
// size) or rolled first.
function rollAtStart(log, now) {
  let st;
  try { st = fs.statSync(log); } catch (e) { return false; }
  if (!st.size) return false;
  if (st.size >= MAX_BYTES) return true;
  const first = firstStamp(readHead(log));
  const t = first === null ? st.mtimeMs : first;
  return dayKey(t) !== dayKey(now);
}

function parseArgs(argv) {
  const o = { log: path.resolve('server.log'), roll: false, program: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!o.program.length && a === '--log') { o.log = path.resolve(argv[++i] || 'server.log'); continue; }
    if (!o.program.length && a === '--roll') { o.roll = true; continue; }
    o.program.push(a);
  }
  return o;
}

// --roll: an install's roll. Whatever the size, so the run the install starts
// has a file of its own, and the 30 days applied. Says what it did and exits 0.
function rollNow(log, now) {
  const out = [];
  try {
    const to = rollFile(log, now);
    out.push(to ? 'rolled ' + path.basename(log) + ' to ' + path.basename(to) : path.basename(log) + ' was empty or not there, nothing to roll');
  } catch (e) {
    out.push('could not roll ' + path.basename(log) + ': ' + (e.code || e.message) + '. It is appended to, and rolled at midnight.');
  }
  return out.concat(sweep(log, now));
}

function run(o) {
  const log = o.log;
  const state = { fd: null, bytes: 0, day: 0, atLineStart: true, rollAfter: 0, lost: 0, lostSince: 0, lostWhy: '' };
  const pending = [];
  const sayLine = (msg) => Buffer.from('[' + stampOf(new Date()) + '] [server-log] ' + msg + '\n');

  // The day a file belongs to is the day of its first line, so one that
  // could not be rolled stays due until it is, whoever opens it again.
  function open(now) {
    state.fd = fs.openSync(log, 'a');
    const st = fs.fstatSync(state.fd);
    state.bytes = st.size;
    let first = null;
    if (st.size) { try { first = firstStamp(readHead(log)); } catch (e) { first = null; } }
    state.day = dayKey(first !== null ? first : (st.size ? st.mtimeMs : now));
    state.atLineStart = true;
  }
  function raw(buf) {
    if (state.fd === null) {
      try { open(Date.now()); } catch (e) { lose(buf, e); return; }
    }
    try {
      fs.writeSync(state.fd, buf);
      state.bytes += buf.length;
      state.atLineStart = buf.length ? buf[buf.length - 1] === 10 : state.atLineStart;
    } catch (e) { lose(buf, e); return; }
    if (state.lost) {
      const lost = state.lost, since = state.lostSince, why = state.lostWhy;
      state.lost = 0;
      raw(sayLine(lost + ' bytes of the server\'s output could not be written here from ' + stampOf(new Date(since)) +
        ' until now: ' + why));
    }
  }
  function lose(buf, e) {
    if (!state.lost) {
      state.lostSince = Date.now();
      state.lostWhy = e.code || e.message;
      process.stderr.write('[server-log] could not write ' + log + ': ' + state.lostWhy + '\n');
    }
    state.lost += buf.length;
    // The handle that failed is let go so the next write opens the file
    // afresh; a handle that will not even close has nothing more to say.
    if (state.fd !== null) { try { fs.closeSync(state.fd); } catch (e2) { state.lostWhy += ', and its handle would not close: ' + e2.code; } state.fd = null; }
  }
  function say(msg) { raw(sayLine(msg)); }

  function due(now) {
    return now >= state.rollAfter && (dayKey(now) !== state.day || state.bytes >= MAX_BYTES);
  }
  function roll(now) {
    const lines = [];
    if (state.fd !== null) {
      try { fs.closeSync(state.fd); }
      catch (e) { lines.push('could not let go of ' + path.basename(log) + ' to roll it: ' + (e.code || e.message)); }
      state.fd = null;
    }
    const wasDay = state.day;
    let rolled = true;
    try { rollFile(log, now); } catch (e) {
      // Another program holding server.log without letting it be renamed
      // (Get-Content over ssh does): outside our control, so it is said and
      // tried again a minute later, writing on in the same file meanwhile.
      rolled = false;
      state.rollAfter = now + 60 * 1000;
      lines.push('could not roll ' + path.basename(log) + ': ' + (e.code || e.message) +
        '. Something else has it open; writing on in it, and trying again in a minute.');
    }
    try { open(now); } catch (e) { lose(Buffer.alloc(0), e); }
    // Not rolled, it is still the earlier day's file, so the roll stays due
    // (the size is counted from the file itself either way).
    if (!rolled) state.day = wasDay;
    for (const l of lines.concat(sweep(log, now))) say(l);
  }
  function write(buf) {
    const now = Date.now();
    if (due(now)) {
      if (state.atLineStart) { roll(now); }
      else {
        const nl = buf.indexOf(10);
        if (nl >= 0) { raw(buf.subarray(0, nl + 1)); roll(now); buf = buf.subarray(nl + 1); }
      }
    }
    if (buf.length) raw(buf);
  }

  // The start: the files Roll-Log.ps1 or an earlier run left cut to the
  // window, then today's server.log appended to or a new one begun.
  const now = Date.now();
  if (rollAtStart(log, now)) {
    try { rollFile(log, now); } catch (e) {
      pending.push('could not roll ' + path.basename(log) + ' at start: ' + (e.code || e.message) +
        '. Something else has it open; writing on in it, and trying again with the next line, then once a minute.');
    }
  }
  pending.push(...sweep(log, now));
  try { open(now); } catch (e) { lose(Buffer.alloc(0), e); }
  for (const l of pending) say(l);

  if (!o.program.length) {
    say('nothing to run: server-log.js was started with no program after its own switches');
    process.exit(2);
  }

  const child = cp.spawn(process.execPath, o.program, { cwd: process.cwd(), stdio: ['inherit', 'pipe', 'pipe'], windowsHide: true });
  if (child.pid) {
    try { os.setPriority(child.pid, os.getPriority()); }
    catch (e) { say('could not give the server this process\'s priority: ' + (e.code || e.message)); }
  }
  child.stdout.on('data', write);
  child.stderr.on('data', write);
  const tick = setInterval(() => {
    const t = Date.now();
    if (due(t) && state.atLineStart) roll(t);
    else for (const l of sweep(log, t)) say(l);
  }, SWEEP_MS);
  child.on('error', (e) => {
    say('could not start ' + o.program.join(' ') + ': ' + (e.code || e.message));
    clearInterval(tick);
    process.exit(1);
  });
  child.on('close', (code, signal) => {
    clearInterval(tick);
    if (!state.atLineStart) raw(Buffer.from('\n'));
    say('the server ended, ' + (signal ? 'stopped by ' + signal : 'exit code ' + code));
    process.exit(code === null ? 1 : code);
  });
}

if (require.main === module) {
  const o = parseArgs(process.argv.slice(2));
  if (o.roll) {
    for (const l of rollNow(o.log, Date.now())) console.log(l);
    process.exit(0);
  }
  run(o);
} else {
  module.exports = { KEEP_DAYS, MAX_BYTES, rolledFiles, trimFile, sweep, rollFile, rollAtStart, rollNow, lineTime, parseArgs };
}
