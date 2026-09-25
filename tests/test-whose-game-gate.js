// test-whose-game-gate.js
//
// Every copy of the whose-game gate in tools/ts-plugins is the same code, and
// the address it calls ours is the one Set-Vps.ps1 moves.
//
// WHY THIS EXISTS. To Do List entry 293, "The same thirty-four lines are
// copied verbatim into five plugins". The gate is what keeps the plugins idle
// unless the client points at this server and the launcher left a fresh
// session note, which is a settled design line in CLAUDE.md. Five copies is
// five places for one of them to drift, and a drifted copy is invisible: it
// parses, it loads, and it only shows when somebody plays another server from
// the same Skyrim and one of our plugins wakes up on top of it.
//
// Why it is still a copy in every plugin (four since entry 127 deleted the
// retired thornswood-chargen.js). The entry's plan was to keep the body in
// front.js, publish it on globalThis.Thornswood, and have the others call
// it and return true when it is not there. That fails open. SkyrimPlatform
// builds its load list with std::filesystem::directory_iterator (GetPathsToLoad
// in the fork's skyrim-platform/src/platform_se/skyrim_platform/SkyrimPlatform.cpp),
// NTFS hands the names back in name order, so thornswood-emotes.js loads
// before thornswood-front.js. It would find nothing published and run
// ungated in another server's session, the one thing the
// gate is for. front.js itself only creates globalThis.Thornswood after its
// own gate. The gate is settled design, so whether and how it becomes one
// copy is for Patrick and Djinn in #dev. Until then this holds the copies
// together, and CI runs it on every pull request.
//
// What it checks, for every .js in tools/ts-plugins (Ship.ps1 sends every one
// of them to Data/Platform/Plugins, so a sixth plugin is checked too):
//   - the gate is the first statement inside the plugin's wrapper, and
//     nothing sits outside the wrapper, so nothing the plugin does runs first;
//   - thornswoodGame() and the comment above the gate are the same text as
//     front.js's once indentation and runs of spaces are set aside (front.js
//     is indented two spaces deeper and lines its trailing comment up to match);
//   - run for real against a fake file system, every copy gives the same,
//     right answer: no settings, another server, ours with a fresh, stale or
//     missing session note, an address from Thornswood.ini;
//   - the one fixed address in `ours` is the ServerAddress default in
//     tools/app/Config.cs, which is where Set-Vps.ps1 reads the old address
//     from, and Set-Vps.ps1's walk over the repo reaches the plugin. Then
//     Set-Vps's replacement is applied to the source and the gate is run again
//     against the new address, so a server move is proven to reach it.
// And that the comparison has teeth: a copy with its one-day note window made
// two days is caught as different text and answers differently.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const TOOLS = TOOLS_DIR;
const PLUGINS = path.join(TOOLS, 'ts-plugins');
const REFERENCE = 'thornswood-front.js';
const GUARD = 'if (!thornswoodGame()) { return; }';
const HEAD = 'function thornswoodGame() {';
const MARKER = '// ------------------------------------------------------------ whose game ----';

const INI = 'Data/SKSE/Plugins/Thornswood.ini';
const SETTINGS = 'Data/Platform/Plugins/skymp5-client-settings.txt';
const NOTE = 'Data/Platform/thornswood-session.txt';

/* Lift a function out of a source by name, braces balanced. */
function lift(src, head) {
  const a = src.indexOf(head);
  if (a < 0) { return null; }
  let depth = 0, i = src.indexOf('{', a);
  if (i < 0) { return null; }
  for (let j = i; j < src.length; j++) {
    if (src[j] === '{') { depth++; }
    else if (src[j] === '}') { depth--; if (!depth) { return src.slice(a, j + 1); } }
  }
  return null;
}

/* The comment block from the whose-game marker down to the guard itself. */
function header(src) {
  const lines = src.split(/\r?\n/);
  const a = lines.findIndex(function (l) { return l.trim() === MARKER; });
  if (a < 0) { return null; }
  for (let i = a; i < lines.length; i++) {
    if (lines[i].trim() === GUARD) { return lines.slice(a, i + 1).join('\n'); }
  }
  return null;
}

/* Indentation and runs of spaces set aside, blank lines dropped. */
function normalise(text) {
  return text.split(/\r?\n/)
    .map(function (l) { return l.trim().replace(/\s+/g, ' '); })
    .filter(function (l) { return l; })
    .join('\n');
}

/* The first line of code inside the wrapper, or why there is none. */
function firstStatement(src) {
  const lines = src.split(/\r?\n/);
  let i = 0;
  for (; i < lines.length; i++) {
    const t = lines[i].trim();
    if (t === '(function () {') { break; }
    if (t && t.indexOf('//') !== 0) { return 'code outside the wrapper: ' + t; }
  }
  if (i >= lines.length) { return 'no (function () { wrapper'; }
  for (i = i + 1; i < lines.length; i++) {
    const t = lines[i].trim();
    if (!t || t === "'use strict';" || t.indexOf('//') === 0) { continue; }
    return t;
  }
  return 'nothing inside the wrapper';
}

/* The first line two normalised texts disagree on, for the log. */
function firstDifference(a, b) {
  const x = a.split('\n'), y = b.split('\n');
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    if (x[i] !== y[i]) { return 'line ' + (i + 1) + ': "' + (x[i] || '') + '" against "' + (y[i] || '') + '"'; }
  }
  return '';
}

// A fixed clock, so a stale note is stale by the same amount every run.
const NOW = Date.UTC(2026, 8, 24, 20, 0, 0);
const HOUR = 3600 * 1000;
const DAY = 24 * HOUR;

/* Run a lifted thornswoodGame against a fake game folder. */
function run(fnText, files) {
  const said = [], read = [];
  const fakeFs = {
    readFileSync: function (p) {
      read.push(p);
      if (!Object.prototype.hasOwnProperty.call(files, p)) {
        const e = new Error('ENOENT: no such file, open \'' + p + '\'');
        e.code = 'ENOENT';
        throw e;
      }
      return files[p];
    }
  };
  const fakeRequire = function (name) {
    if (name === 'fs') { return fakeFs; }
    throw new Error('the gate asked for ' + name);
  };
  const fakeSp = { printConsole: function (m) { said.push(String(m)); } };
  const fakeDate = { now: function () { return NOW; }, parse: Date.parse };
  let answer;
  try {
    const make = new Function('require', 'skyrimPlatform', 'Date',
      "'use strict';\n" + fnText + '\nreturn thornswoodGame;');
    answer = make(fakeRequire, fakeSp, fakeDate)();
  } catch (e) {
    answer = 'threw: ' + e.message;
  }
  return { answer: answer, said: said, read: read };
}

function settings(ip, bom) {
  return (bom ? String.fromCharCode(0xFEFF) : '') + JSON.stringify({ 'server-ip': ip, 'server-port': 7777 }, null, 2);
}
// As Keep.LeaveNote writes it: unix milliseconds, a space, the build name.
function note(ms) { return ms + ' Thornswood Dev'; }

// ------------------------------------------------ the address Set-Vps moves
const configCs = fs.readFileSync(path.join(TOOLS, 'app', 'Config.cs'), 'utf8');
const setVps = fs.readFileSync(path.join(TOOLS, 'Set-Vps.ps1'), 'utf8');
const OLD_RX = 'public\\s+string\\s+ServerAddress\\s*=\\s*"([^"]+)"';

yes('Set-Vps.ps1 still takes the address it moves from the ServerAddress default in app\\Config.cs',
    setVps.indexOf("Join-Path $Here 'app\\Config.cs'") >= 0 && setVps.indexOf("'" + OLD_RX + "'") >= 0);
const cfgMatch = new RegExp(OLD_RX).exec(configCs);
yes('app\\Config.cs has a ServerAddress default', !!cfgMatch);
const OURS = cfgMatch ? cfgMatch[1] : '';
console.log('      the address Set-Vps.ps1 moves: ' + OURS);

function quoted(list) {
  const out = [];
  const rx = /'([^']*)'/g;
  let m;
  while ((m = rx.exec(list))) { out.push(m[1]); }
  return out;
}
const skipMatch = /\$skipDirs\s*=\s*@\(([^)]*)\)/.exec(setVps);
const extMatch = /\$f\.Extension\s+-notin\s+@\(([^)]*)\)/.exec(setVps);
yes('Set-Vps.ps1 still has a list of folders it skips and of extensions it reads', !!skipMatch && !!extMatch);
const SKIP = skipMatch ? quoted(skipMatch[1]) : [];
const EXTS = extMatch ? quoted(extMatch[1]) : [];
const sizeMatch = /\$f\.Length\s+-gt\s+(\d+)MB/.exec(setVps);
const MAX = sizeMatch ? Number(sizeMatch[1]) * 1024 * 1024 : 0;

// ------------------------------------------------------------- the copies
const names = fs.readdirSync(PLUGINS).filter(function (n) { return /\.js$/i.test(n); }).sort();
yes('tools/ts-plugins has the four plugins left of the five the entry names, ' + names.length + ' .js in all',
    ['thornswood-emotes.js', 'thornswood-front.js', 'thornswood-mark.js', 'thornswood-voice.js']
      .every(function (n) { return names.indexOf(n) >= 0; }));

const copies = {};
names.forEach(function (n) {
  const full = path.join(PLUGINS, n);
  const src = fs.readFileSync(full, 'utf8');
  copies[n] = { src: src, fn: lift(src, HEAD), head: header(src), size: fs.statSync(full).size };
});

const ref = copies[REFERENCE];
yes('front.js has the gate to compare against', !!(ref && ref.fn && ref.head));
const refFn = ref && ref.fn ? normalise(ref.fn) : '';
const refHead = ref && ref.head ? normalise(ref.head) : '';

names.forEach(function (n) {
  const c = copies[n];
  const first = firstStatement(c.src);
  yes(n + ': the gate is the first thing its wrapper runs', first === GUARD);
  if (first !== GUARD) { console.log('      found instead: ' + first); }

  yes(n + ': has thornswoodGame(), ' + (c.fn ? c.fn.split(/\r?\n/).length : 0) + ' lines', !!c.fn);
  if (!c.fn) { return; }

  if (n !== REFERENCE) {
    const same = normalise(c.fn) === refFn;
    yes(n + ': thornswoodGame() is the same code as front.js\'s', same);
    if (!same) { console.log('      ' + firstDifference(normalise(c.fn), refFn)); }

    const sameHead = !!c.head && normalise(c.head) === refHead;
    yes(n + ': the comment above the gate says the same as front.js\'s', sameHead);
    if (c.head && !sameHead) { console.log('      ' + firstDifference(normalise(c.head), refHead)); }
  }

  const ours = /const ours = \[([^\]]*)\];/.exec(c.fn);
  const list = ours ? quoted(ours[1]) : [];
  yes(n + ': the one fixed address it calls ours is ' + OURS + ', the one Set-Vps.ps1 moves',
      !!OURS && list.length === 1 && list[0] === OURS);
  if (list.length !== 1 || list[0] !== OURS) { console.log('      ours is [' + list.join(', ') + ']'); }

  const rel = ['tools', 'ts-plugins', n];
  const reached = EXTS.indexOf(path.extname(n)) >= 0 &&
    rel.every(function (p) { return SKIP.indexOf(p) < 0; }) &&
    MAX > 0 && c.size <= MAX;
  yes(n + ': Set-Vps.ps1 reads it on a server move (extension, folder, size)', reached);
});

// ------------------------------------------------------ what every copy says
const FRESH = note(NOW - 5 * 60 * 1000);
const CASES = [
  { what: 'no client settings to read: carry on, as before', files: {}, want: true },
  { what: 'client settings that are not JSON: carry on, as before',
    files: { [SETTINGS]: 'not json' }, want: true },
  { what: 'the client points at another server, even with a fresh note',
    files: { [SETTINGS]: settings('10.1.2.3'), [NOTE]: FRESH }, want: false },
  { what: 'ours, with the note the launcher leaves when it starts the game',
    files: { [SETTINGS]: settings(OURS), [NOTE]: FRESH }, want: true },
  { what: 'ours, the settings written with a byte order mark',
    files: { [SETTINGS]: settings(OURS, true), [NOTE]: FRESH }, want: true },
  { what: 'ours, a note written as a date rather than milliseconds',
    files: { [SETTINGS]: settings(OURS), [NOTE]: new Date(NOW - HOUR).toISOString() + ' Start-Thornswood' }, want: true },
  { what: 'ours, a note a few seconds ahead of this clock',
    files: { [SETTINGS]: settings(OURS), [NOTE]: note(NOW + 5000) }, want: true },
  { what: 'ours, a note a day and a minute old',
    files: { [SETTINGS]: settings(OURS), [NOTE]: note(NOW - DAY - 60000) }, want: false },
  { what: 'ours, a note thirty hours old',
    files: { [SETTINGS]: settings(OURS), [NOTE]: note(NOW - 30 * HOUR) }, want: false },
  { what: 'ours, and no note, as another server\'s launcher leaves it',
    files: { [SETTINGS]: settings(OURS) }, want: false },
  { what: 'ours, a note with nothing readable in it',
    files: { [SETTINGS]: settings(OURS), [NOTE]: 'soon' }, want: false },
  { what: 'no address in the settings, with a fresh note',
    files: { [SETTINGS]: settings(''), [NOTE]: FRESH }, want: true },
  { what: 'no address in the settings and no note',
    files: { [SETTINGS]: settings('') }, want: false },
  { what: 'an address Thornswood.ini names, with a fresh note',
    files: { [INI]: '[Server]\nServerAddress = 10.9.8.7 ; the test box\n', [SETTINGS]: settings('10.9.8.7'), [NOTE]: FRESH }, want: true },
  { what: 'Thornswood.ini names a box and the client points at a third',
    files: { [INI]: '[Server]\nServerAddress = 10.9.8.7\n', [SETTINGS]: settings('10.1.2.3'), [NOTE]: FRESH }, want: false }
];

const lifted = names.filter(function (n) { return copies[n].fn; });
let saidWhy = true, quietWhenOurs = true, readOnlyThree = true;
CASES.forEach(function (k) {
  const wrong = [];
  lifted.forEach(function (n) {
    const r = run(copies[n].fn, k.files);
    if (r.answer !== k.want) { wrong.push(n + ' said ' + r.answer); }
    if (k.want === false && !r.said.some(function (s) { return /Plugin idle\.$/.test(s); })) { saidWhy = false; }
    if (k.want === true && r.said.length) { quietWhenOurs = false; }
    if (r.read.some(function (p) { return p !== INI && p !== SETTINGS && p !== NOTE; })) { readOnlyThree = false; }
  });
  yes('every copy, ' + k.what + ': ' + (k.want ? 'runs' : 'idle'), lifted.length === names.length && wrong.length === 0);
  wrong.forEach(function (w) { console.log('      ' + w); });
});
yes('every copy says in the console why it went idle, every time it does', saidWhy);
yes('and says nothing when the session is ours', quietWhenOurs);
yes('and reads nothing but Thornswood.ini, the client settings and the session note', readOnlyThree);

// ---------------------------------------------------- a server move reaches it
// Set-Vps.ps1 rewrites every file it reads with $text.Replace($Old, $Address).
// Do the same to each plugin and ask the gate again. 203.0.113.9 is a
// documentation address, never a real box.
const NEW = '203.0.113.9';
let movedAll = !!OURS, oldIsForeign = !!OURS;
lifted.forEach(function (n) {
  const moved = lift(copies[n].src.split(OURS).join(NEW), HEAD);
  const toNew = moved ? run(moved, { [SETTINGS]: settings(NEW), [NOTE]: FRESH }).answer : 'no function';
  const toOld = moved ? run(moved, { [SETTINGS]: settings(OURS), [NOTE]: FRESH }).answer : 'no function';
  if (toNew !== true) { movedAll = false; console.log('      ' + n + ' after the move, pointed at the new box, said ' + toNew); }
  if (toOld !== false) { oldIsForeign = false; console.log('      ' + n + ' after the move, pointed at the old box, said ' + toOld); }
});
yes('after Set-Vps.ps1\'s replacement every copy runs for the new box', movedAll);
yes('and treats the old box as somebody else\'s', oldIsForeign);

// ------------------------------------------------------ the check has teeth
{
  const drifted = ref && ref.fn ? ref.fn.replace('24 * 3600 * 1000', '48 * 3600 * 1000') : '';
  yes('a copy with its note window made two days is a real edit', !!drifted && drifted !== ref.fn);
  yes('and the comparison above calls it different', !!drifted && normalise(drifted) !== refFn);
  const thirty = { [SETTINGS]: settings(OURS), [NOTE]: note(NOW - 30 * HOUR) };
  yes('and it runs on a thirty hour old note where front.js stays idle',
      !!drifted && run(drifted, thirty).answer === true && run(ref.fn, thirty).answer === false);
  const reindented = ref && ref.fn ? ref.fn.split('\n').map(function (l) { return '    ' + l; }).join('\n') : '';
  yes('while indentation alone is not called a difference', !!reindented && normalise(reindented) === refFn);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
