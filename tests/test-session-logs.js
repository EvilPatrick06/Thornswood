/*
  test-session-logs.js

  The logs kept against one session, which are meant to stand up when somebody
  is suspended or banned.

  Asked for by Patrick on 22 September: collect the logs so he never has to ask
  for them, and so they can be used as evidence later. Three things follow from
  "evidence" and each of them is a check here, because each can be quietly
  wrong while the feature still looks like it works:

    WRITE ONCE. A second set for the same session must not overwrite the
    first. Without that, anybody who knew the endpoint could do something worth
    banning for and then post a clean set over the top from the same launcher,
    and the evidence would be whatever the accused chose to send last.

    PROVENANCE. The Discord id is taken off the TICKET, never off the body, and
    a sha256 of every log is recorded, so a copy pasted into an argument months
    later can be held against the one on the box.

    KEPT BY AGE, NOT BY THE ROLLING LIST. sessions.json keeps the last two
    thousand rows. Tying the logs to it would delete the evidence for an old
    incident the moment two thousand newer sessions had happened.

  It also checks what the endpoint REFUSES to store, because this is a body
  from every launcher and a file name is the shortest way into a folder nobody
  meant to write.

  This lifts the real functions out of server.js by text, so a rename fails
  loudly rather than testing a copy. Read only apart from its own temp folder.
*/
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const SRC = path.join(TOOLS_DIR, '..', 'site', 'server.js');
const src = fs.readFileSync(SRC, 'utf8');

function grab(name) {
  const at = src.indexOf('function ' + name);
  if (at < 0) throw new Error('site/server.js has no function ' + name);
  const b = src.indexOf('{', at);
  let d = 0;
  for (let i = b; i < src.length; i++) {
    if (src[i] === '{') d++;
    else if (src[i] === '}') { d--; if (d === 0) return src.slice(at, i + 1); }
  }
  throw new Error('unbalanced braces reading ' + name);
}

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'thornswood-slogs-'));
const SLOGS = path.join(TMP, 'session-logs');

/* The same values server.js declares. If they change there, they change here,
   and the caps check below is what notices. */
const SLOG_ONE = 256 * 1024;
const SLOG_ALL = 1024 * 1024;
const SLOG_DAYS = 365;
/* The list itself is lifted, not copied: a copy here kept passing on 24
   September while the site had no place for the crash log at all. */
const SLOG_NAMES = eval(grabConst('SLOG_NAMES'));
const SERVER_LOGS = {
  main: path.join(TMP, 'server.log'),
  dev:  path.join(TMP, 'server-dev.log')
};
let ROWS = [];
function sessionRows() { return ROWS; }

eval([
  grab('slogFile'), grab('slogTrim'), grab('putSessionLogs'),
  grab('pruneSessionLogs'), grab('serverLogSlice')
].join('\n'));

let pass = 0, fail = 0;
const yes = (w, c) => {
  if (c) { pass++; console.log('PASS  ' + w); }
  else { fail++; console.log('FAIL  ' + w); }
};

// ---- write once ------------------------------------------------------------
const K = 'aaaaaaaabbbbbbbb';
yes('a first set is saved',
    putSessionLogs(K, '111', { 'launcher.log': 'hello\nworld\n' }) === 'saved');
yes('a second set for the same session is refused',
    putSessionLogs(K, '111', { 'launcher.log': 'CLEAN LOGS, NOTHING HAPPENED\n' }) === 'already');

const set = JSON.parse(fs.readFileSync(slogFile(K), 'utf8'));
yes('the FIRST set is what is still on disk', set.logs['launcher.log'] === 'hello\nworld\n');
yes('the replay attempt is recorded rather than ignored', set.resent === 1);
yes('the Discord id off the ticket is recorded', set.who === '111');
yes('a sha256 is recorded for each log',
    set.sha256['launcher.log'] ===
    crypto.createHash('sha256').update('hello\nworld\n', 'utf8').digest('hex'));

// ---- what it will not store ------------------------------------------------
yes('a file name not on the allowed list is dropped',
    putSessionLogs('ccccccccdddddddd', '111',
      { '../../evil.txt': 'x', 'secrets.env': 'y', 'bot.env.json': 'z' }) === 'nothing');
yes('and nothing at all was written for it',
    !fs.existsSync(slogFile('ccccccccdddddddd')));
yes('an empty log is not stored',
    putSessionLogs('eeeeeeeeffffffff', '111', { 'launcher.log': '   \n  ' }) === 'nothing');

// ---- caps ------------------------------------------------------------------
putSessionLogs('11111111aaaaaaaa', '222', { 'launcher.log': 'x'.repeat(SLOG_ONE + 50000) });
const capped = JSON.parse(fs.readFileSync(slogFile('11111111aaaaaaaa'), 'utf8'));
yes('one log is trimmed to its cap', capped.logs['launcher.log'].length <= SLOG_ONE + 200);
yes('the trim keeps the END, where a crash is, and says what it dropped',
    capped.logs['launcher.log'].indexOf('are not kept') >= 0 &&
    capped.logs['launcher.log'].endsWith('x'));

const many = {};
for (const n of SLOG_NAMES) many[n] = 'y'.repeat(SLOG_ONE);
putSessionLogs('22222222bbbbbbbb', '222', many);
const all = JSON.parse(fs.readFileSync(slogFile('22222222bbbbbbbb'), 'utf8'));
yes('a whole set is held under the total cap', all.bytes <= SLOG_ALL);

// ---- retention -------------------------------------------------------------
function age(key, days) {
  const f = slogFile(key);
  const o = JSON.parse(fs.readFileSync(f, 'utf8'));
  o.at = Date.now() - days * 86400000;
  fs.writeFileSync(f, JSON.stringify(o));
}
putSessionLogs('old11111old11111', '333', { 'launcher.log': 'old\n' });
putSessionLogs('keep1111keep1111', '333', { 'launcher.log': 'evidence\n' });
age('old11111old11111', SLOG_DAYS + 5);
age('keep1111keep1111', SLOG_DAYS + 5);

/* Neither session is in the rolling list. Under the old rule that alone would
   have deleted both; under this one only age decides, and a row marked kept
   is held whatever its age. */
ROWS = [{ session: 'keep1111keep1111', who: '333', keep: true }];
pruneSessionLogs();
yes('an old set with nothing holding it is pruned',
    !fs.existsSync(slogFile('old11111old11111')));
yes('an old set on a row marked kept survives, because it is evidence',
    fs.existsSync(slogFile('keep1111keep1111')));
yes('a recent set survives even though it is not in the rolling list',
    fs.existsSync(slogFile(K)));

// ---- the server log slice --------------------------------------------------
fs.writeFileSync(SERVER_LOGS.main,
  '[2026-09-22 10:00:00.000] [console] [info] before the session\n' +
  '[2026-09-22 10:05:00.000] [console] [info] inside the window\n' +
  '    a continuation line carrying no stamp of its own\n' +
  '[2026-09-22 10:30:00.000] [console] [info] after the session\n');

const from = new Date(2026, 8, 22, 10, 4, 0).getTime();
const to   = new Date(2026, 8, 22, 10, 6, 0).getTime();
const slice = serverLogSlice('main', from, to);
yes('the slice reads the log', slice.ok);
yes('it keeps the line inside the window',
    slice.lines.some(l => l.indexOf('inside the window') >= 0));
yes('it drops the line before the window',
    !slice.lines.some(l => l.indexOf('before the session') >= 0));
yes('it drops the line after the window',
    !slice.lines.some(l => l.indexOf('after the session') >= 0));
yes('a continuation line with no stamp stays with the line above it',
    slice.lines.some(l => l.indexOf('continuation line') >= 0));

const missing = serverLogSlice('dev', from, to);
yes('a server log that is not on this box says so rather than throwing',
    missing.ok === false && missing.lines.length === 0 && String(missing.why).length > 0);

// ---- the server log slice after a roll (entry 220) -------------------------
/*
  roll-log.ps1 runs in front of the game server on every start, and moves a
  server.log of 4 MB or more to server.log.1. Found in review, measured: a
  crash with the log past 4 MB, the watcher's restart rolled it, and the page
  then showed nothing for the crash session, because the slice read
  server.log and nothing else. So this builds that log, rolls it with the
  real Roll-Log.ps1 the way the task line runs it, and asks again.
*/
const { spawnSync } = require('child_process');
const ROLLER = path.join(TOOLS_DIR, '..', 'scripts', 'vps', 'Roll-Log.ps1');
const WINPS = path.join(process.env.SystemRoot || 'C:\\Windows',
                        'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
let rolledBy = 'Roll-Log.ps1';
function rollLog(file, force) {
  if (fs.existsSync(WINPS)) {
    const args = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                  '-File', ROLLER, '-Path', file];
    if (force) args.push('-Force');
    const r = spawnSync(WINPS, args, { encoding: 'utf8' });
    return String(r.stdout || '') + String(r.stderr || '');
  }
  /* No Windows PowerShell here, so the roll is done the way the roller does
     it, and the run says so rather than passing as if the real one ran. */
  rolledBy = 'a stand-in for Roll-Log.ps1';
  if (!force && fs.statSync(file).size < 4 * 1024 * 1024) return '';
  if (fs.existsSync(file + '.5')) fs.unlinkSync(file + '.5');
  for (let i = 4; i >= 1; i--) {
    if (fs.existsSync(file + '.' + i)) fs.renameSync(file + '.' + i, file + '.' + (i + 1));
  }
  fs.renameSync(file, file + '.1');
  return 'rolled';
}
const has = (s, what) => s.lines.some(l => l.indexOf(what) >= 0);
const at = (h, m) => new Date(2026, 8, 22, h, m, 0).getTime();

const ROLLDIR = path.join(TMP, 'rolled');
fs.mkdirSync(path.join(ROLLDIR, 'dev'), { recursive: true });
SERVER_LOGS.main = path.join(ROLLDIR, 'server.log');
SERVER_LOGS.dev = path.join(ROLLDIR, 'dev', 'server.log');

/* A day's run past 4 MB, the crash at the end of it. */
const filler = '[2026-09-22 09:00:00.000] [console] [info] an ordinary line of engine noise\n';
const CRASHED =
  filler.repeat(Math.ceil((4 * 1024 * 1024 + 4096) / filler.length)) +
  '[2026-09-22 22:00:00.000] [console] [info] the crash session begins\n' +
  '[2026-09-22 22:05:00.000] [console] [error] FATAL the server went down\n' +
  '    at a stack line carrying no stamp of its own\n';
fs.writeFileSync(SERVER_LOGS.main, CRASHED);

const crashFrom = at(21, 59), crashTo = at(22, 6);
yes('before the restart, the crash session is on the page',
    has(serverLogSlice('main', crashFrom, crashTo), 'FATAL the server went down'));

const said = rollLog(SERVER_LOGS.main, false);
yes('the roller moved the 4 MB log aside, as it does in front of every start',
    said.indexOf('rolled') >= 0 && !fs.existsSync(SERVER_LOGS.main) &&
    fs.existsSync(SERVER_LOGS.main + '.1'));

const between = serverLogSlice('main', crashFrom, crashTo);
yes('in the moment before the server opens a new server.log, the crash session is still found',
    between.ok && has(between, 'FATAL the server went down'));

/* The restart, writing a fresh server.log the way cmd's >> does. */
fs.writeFileSync(SERVER_LOGS.main,
  '[2026-09-22 22:07:00.000] [console] [info] the server is up again\n' +
  '[2026-09-22 22:30:00.000] [console] [info] a session after the restart\n');

const after = serverLogSlice('main', crashFrom, crashTo);
yes('after the restart, the crash session is still on the page', after.ok && has(after, 'FATAL the server went down'));
yes('with the stack line under it', has(after, 'a stack line carrying no stamp'));
yes('and without the restart, which is outside its window', !has(after, 'the server is up again'));

const later = serverLogSlice('main', at(22, 29), at(22, 31));
yes('a session after the restart comes out of the new server.log',
    has(later, 'a session after the restart') && !has(later, 'FATAL'));

const across = serverLogSlice('main', at(22, 4), at(22, 8));
const fi = across.lines.findIndex(l => l.indexOf('FATAL') >= 0);
const ui = across.lines.findIndex(l => l.indexOf('the server is up again') >= 0);
yes('a session across the restart has both halves, oldest first', fi >= 0 && ui > fi);

/* An install rolls whatever the size, so the run before it can be a small .1
   with the crash a generation further back in .2. */
rollLog(SERVER_LOGS.main, true);
fs.writeFileSync(SERVER_LOGS.main, '[2026-09-22 23:00:00.000] [console] [info] installed\n');
yes('an install roll put the crash in server.log.2', fs.existsSync(SERVER_LOGS.main + '.2'));
yes('and the crash session is still found there',
    has(serverLogSlice('main', crashFrom, crashTo), 'FATAL the server went down'));

/* The read stays the 4 MB it always was: a server.log that fills the window
   is all that is read, so a busy week cannot make the page read five files. */
fs.writeFileSync(SERVER_LOGS.main, CRASHED.replace(/FATAL the server went down/, 'a later crash'));
const capped2 = serverLogSlice('main', crashFrom, crashTo);
yes('a server.log that fills the 4 MB window is read alone',
    has(capped2, 'a later crash') && !has(capped2, 'FATAL the server went down'));

/* dev is its own server with its own rolled logs, and a dev session reads
   only those. */
fs.writeFileSync(SERVER_LOGS.dev + '.1',
  '[2026-09-22 22:05:00.000] [console] [error] only on dev\n');
fs.writeFileSync(SERVER_LOGS.dev, '[2026-09-22 22:40:00.000] [console] [info] dev up again\n');
yes('a dev session reads the dev server\'s rolled log',
    has(serverLogSlice('dev', crashFrom, crashTo), 'only on dev'));
yes('and a live session never does',
    !has(serverLogSlice('main', crashFrom, crashTo), 'only on dev'));
console.log('       (rolled by ' + rolledBy + ')');

// ---- red against yellow ----------------------------------------------------
/*
  Two levels, because they want two different things done about them. Red is a
  crash or a throw and the bot says so out loud. Yellow is a session that
  failed for a reason already understood with a known fix, and says nothing in
  Discord, because there are a lot of those and a channel full of them is a
  channel nobody reads.
*/
/* The two marker lists, lifted whole, so the checks below run against the
   real ones rather than a copy that drifts. */
function grabConst(name) {
  const at = src.indexOf('const ' + name);
  if (at < 0) throw new Error('site/server.js has no const ' + name);
  const open = src.indexOf('[', at);
  let d = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '[') d++;
    else if (src[i] === ']') { d--; if (d === 0) return src.slice(open, i + 1); }
  }
  throw new Error('unbalanced brackets reading ' + name);
}
const TROUBLE_BAD = eval(grabConst('TROUBLE_BAD'));
const TROUBLE_WARN = eval(grabConst('TROUBLE_WARN'));
eval([grab('lineAround'), grab('scanFor'), grab('readTrouble')].join('\n'));

yes('the red list and the yellow list are both real and separate',
    TROUBLE_BAD.length > 0 && TROUBLE_WARN.length > 0 &&
    !TROUBLE_BAD.some(b => TROUBLE_WARN.some(w => w[0] === b[0])));

const crash = readTrouble({ 'thornswood-front.log': 'fine\nUncaught TypeError: x is not a function\nmore\n' });
yes('a throw in a game log is red', crash && crash.level === 'bad');
yes('and the line it sat on is kept',
    crash && crash.line.indexOf('Uncaught TypeError') >= 0);

const upd = readTrouble({ 'launcher.log': 'fine\n2026-09-22 10:00:00  Update failed: the file was locked\n' });
yes('an update that did not install is yellow, not red', upd && upd.level === 'warn');
yes('it says what went wrong in plain words', upd && upd.why === 'an update did not install');

const lo = readTrouble({ 'thornswood-front.log': 'LOAD ORDER ERROR\n' });
yes('a load order refusal is yellow, not red', lo && lo.level === 'warn');

const both = readTrouble({
  'launcher.log': 'Update failed: locked\n',
  'thornswood-front.log': 'Unhandled exception in the plugin\n'
});
yes('a session that both crashed and had a load order complaint is RED',
    both && both.level === 'bad');

yes('a clean session is neither', readTrouble({ 'launcher.log': 'started\nplayed\nclosed\n' }) === null);
yes('no logs at all is neither', readTrouble({}) === null);

/* The thing that would make this useless: a marker so loose that ordinary
   lines match it. The word "error" appears in healthy logs all the time. */
yes('the word error on its own does not colour a session',
    readTrouble({ 'launcher.log': 'checked for errors, found none\n' }) === null);

// ---- the crash evidence (entry 105) ----------------------------------------
/*
  Entry 105: the game went down with the creation panel open and an alt tab,
  and left no message. What settles a native crash is the SKSE crash log and
  Skyrim Platform's own log. Until 24 September the launcher sent neither and
  the site would have dropped both. These check that the two ends agree, by
  reading the launcher's list out of Discord.cs rather than keeping a copy of
  it here. The launcher's own half is test-log-upload.ps1.
*/
const CS = fs.readFileSync(path.join(TOOLS_DIR, '..', 'launcher', 'app', 'Discord.cs'), 'utf8');
const sends = (function () {
  const at = CS.indexOf('public static void SessionLogs()');
  const end = at < 0 ? -1 : CS.indexOf('};', at);
  const block = end < 0 ? '' : CS.slice(at, end);
  const out = [];
  const re = /new string\[\] \{ "([^"]+)",/g;
  let m;
  while ((m = re.exec(block))) out.push(m[1]);
  return out;
})();
yes('the launcher list reads out of Discord.cs', sends.length >= 8);
yes('the launcher sends the SKSE crash log', sends.indexOf('crash.log') >= 0);
yes("the launcher sends Skyrim Platform's own log", sends.indexOf('skyrim-platform.log') >= 0);
yes('every log the launcher sends is one the site keeps',
    sends.length > 0 && sends.every(n => SLOG_NAMES.indexOf(n) >= 0));
yes('in the same order, so both ends leave out the same ones first',
    JSON.stringify(sends) === JSON.stringify(SLOG_NAMES));

/* The launcher leaves a log out rather than send a body the site cuts off,
   because a body past the cap is dropped whole, every log in it. */
const product = s => s.split('*').reduce((a, b) => a * Number(b.trim()), 1);
const lm = /const int LogBodyMax = ([0-9 *]+);/.exec(CS);
const bm = /body\(req, SLOG_ALL \+ ([0-9 *]+)\)/.exec(src);
yes('the launcher never sends a body bigger than the site reads',
    !!lm && !!bm && product(lm[1]) > 0 && product(lm[1]) <= SLOG_ALL + product(bm[1]));

/* The head of a real CrashLogger file, Patrick's machine, 22 September, cut
   to the lines that matter here. */
const CRASH = [
  'CRASH TIME: 2026-09-22 20:48:59',
  'Skyrim SSE v1.6.1170',
  'CrashLoggerSSE v1-24-0-0 Jun 28 2026 00:14:22',
  '',
  'Unhandled exception "EXCEPTION_ACCESS_VIOLATION" at 0x7FF7C52AF7EF SkyrimSE.exe+01AF7EF\tcmp [rdi], eax',
  'Exception Flags: 0x00000000 (Continuable)',
  ''
].join('\n');
/* Ordinary lines out of skyrim-platform.log from a clean session on the same
   machine, 23 September. */
const PLATFORM = [
  '[10:19:48:897] platform_se v2.9.0',
  '[10:19:49:178] Failed to register messaging listener for NirnLabUIPlatform',
  '[10:20:30:775] [Script] Trace in ServerJsVerificationService: Empty server JS, skipping verification',
  '[10:21:31:854] [Script] Trace in AuthService: onBrowserMessage: ["thornswood-front","skills:closed"]',
  '[10:21:37:330] onResult called',
  '[10:21:37:341] Latent callback called',
  '[10:22:03:307] [Script] [front] 10:22:03.306 the Console Native UI Menu opened on its own and has been shut',
  ''
].join('\n');

yes('a set carrying both is saved',
    putSessionLogs('crash105crash105', '444', { 'crash.log': CRASH, 'skyrim-platform.log': PLATFORM }) === 'saved');
const readSet = key => fs.existsSync(slogFile(key))
  ? JSON.parse(fs.readFileSync(slogFile(key), 'utf8')) : { logs: {}, sha256: {} };
const ev = readSet('crash105crash105');
yes('the crash log is kept whole', ev.logs['crash.log'] === CRASH);
yes('the platform log is kept', ev.logs['skyrim-platform.log'] === PLATFORM);
yes('each with its sha256', !!ev.sha256['crash.log'] && !!ev.sha256['skyrim-platform.log']);

const big = {};
for (const n of SLOG_NAMES) big[n] = 'z'.repeat(SLOG_ONE);
big['crash.log'] = CRASH;
putSessionLogs('crash106crash106', '444', big);
const kept = readSet('crash106crash106');
yes('in a set too big for the site, the crash log is still kept', kept.logs['crash.log'] === CRASH);
yes('and the platform log, last on the list, is what goes', !('skyrim-platform.log' in kept.logs));

const cr = readTrouble({ 'launcher.log': 'started\nclosed\n', 'crash.log': CRASH });
yes('a session that sent a crash log is red', !!cr && cr.level === 'bad' && cr.file === 'crash.log');
yes('and the line it points at is the exception',
    !!cr && cr.line.indexOf('EXCEPTION_ACCESS_VIOLATION') >= 0);
yes('the ordinary platform log of a clean session does not colour it',
    readTrouble({ 'launcher.log': 'started\nclosed\n', 'skyrim-platform.log': PLATFORM }) === null);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
try { fs.rmSync(TMP, { recursive: true, force: true }); } catch (e) { }
process.exit(fail ? 1 : 0);
