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
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const SRC = path.join(__dirname, 'docs-app', 'server.js');
const src = fs.readFileSync(SRC, 'utf8');

function grab(name) {
  const at = src.indexOf('function ' + name);
  if (at < 0) throw new Error('docs-app/server.js has no function ' + name);
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
const SLOG_NAMES = [
  'launcher.log', 'thornswood-front.log', 'thornswood-voice.log',
  'thornswood-emotes.log', 'thornswood-input.log', 'thornswood-dress.log',
  'thornswood-loadorder.txt', 'thornswood-plugins-light.txt'
];
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
  if (at < 0) throw new Error('docs-app/server.js has no const ' + name);
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

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
try { fs.rmSync(TMP, { recursive: true, force: true }); } catch (e) { }
process.exit(fail ? 1 : 0);
