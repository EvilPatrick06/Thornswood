// test-server-tick-cost.js
//
// Where the game server's own time goes, per timer, with the real gamemode.
// Issue #385: "Dev is laggy". The two suspects are the NPCs the server keeps
// alive and the position traffic it sends about every actor. Both of those
// live in the engine, not in this file, so the first thing to settle is
// whether the gamemode's own timers are a third cost hiding under them.
//
// This loads the WHOLE of game/gamemode.js in a sandbox with a stand-in mp:
// a set of people online, each with a position, a cell, a finished character
// and an appearance the size of a real one. Every setInterval the gamemode
// starts is caught, run many times, and timed. Every mp.get it makes is
// counted by property, because the count is exact whatever machine runs this,
// and on the real server each mp.get is a trip into the engine (an
// appearance is a JSON document the engine hands back parsed, every time).
//
// It prints one row per timer: how often it runs, milliseconds per run, the
// share of one core that comes to, and engine reads a second. Then it checks
// the voice feed, the one timer that runs five times a second:
//   - it reads each person's appearance at most once a second, not on every
//     200 ms pass (it read it twice a pass, ten times a second a person);
//   - it reads each person's profile id once a pass, not twice;
//   - what it sends the voice service is unchanged: the same rows, the same
//     fields, the same values, name and party included, and a new name is
//     picked up within a second.
//
// Read only. Nothing leaves the machine: http is a fake that records bodies.
// Files the gamemode writes (online.json and the like) land in a scratch
// folder, TICK_TMP or the system temp folder.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');

const SRC = path.resolve(process.env.GM || path.join(__dirname, '..', 'game', 'gamemode.js'));
const PEOPLE = Math.max(3, Number(process.env.PEOPLE || 20));
const QUIET = !process.env.VERBOSE;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// ------------------------------------------------------------ the scratch dir
const scratch = fs.mkdtempSync(path.join(process.env.TICK_TMP || os.tmpdir(), 'tick-cost-'));
['data', 'private', 'world'].forEach(function (d) { fs.mkdirSync(path.join(scratch, d)); });
fs.writeFileSync(path.join(scratch, 'server-settings.json'), JSON.stringify({
  dataDir: 'data', privDir: 'private', port: 7777, name: 'tick cost', loadOrder: []
}));
const home = process.cwd();
process.chdir(scratch);

// ----------------------------------------------------------- a real appearance
// The shape skymp5-client/src/sync/appearance.ts sends, at a size taken from a
// vanilla race: six head parts, nineteen morphs, four presets, forty tints.
function appearance(i) {
  const tints = [];
  for (let t = 0; t < 40; t++) {
    tints.push({ texturePath: 'Actors\\Character\\Character Assets\\TintMasks\\HumanTint' + t + '.dds',
                 argb: 0x40000000 + t * 977, type: t % 14 });
  }
  const options = []; for (let o = 0; o < 19; o++) { options.push(o / 19); }
  return JSON.stringify({ isFemale: !!(i % 2), raceId: 0x13746, weight: 50, skinColor: 0xffc0a080,
    hairColor: 0xff302010, headpartIds: [0x1f6c2, 0x1f6c3, 0x51622, 0x5c2c1, 0x6e6f5, 0x7a2bd],
    headTextureSetId: 0x2c3a1, options: options, presets: [1, 2, 3, 4], tints: tints,
    name: 'Person ' + i });
}

// ------------------------------------------------------------- the stand-in mp
const ids = [];
const store = new Map();
for (let i = 0; i < PEOPLE; i++) {
  const id = 0xff000800 + i;
  ids.push(id);
  store.set(id, {
    profileId: 1000 + i,
    pos: [1000 + i * 150, 2000, 64],
    angle: [0, 0, i * 10],
    worldOrCellDesc: i % 4 === 0 ? '165a7:Skyrim.esm' : '1a26f:Skyrim.esm',
    appearanceDump: appearance(i),
    isDead: false,
    thornswoodChargen: { stage: 'done', at: 1, legacy: true },
    thornswoodCharacter: { prof: 'smith', v: 1 },
    inventory: { entries: [] },
    baseDesc: '7:Skyrim.esm'
  });
}

const reads = {};           // property -> count
let counting = false;
function count(k) { if (counting) { reads[k] = (reads[k] || 0) + 1; } }

const mpBase = {
  get: function (id, k) {
    count(k);
    if (id === 0 && k === 'onlinePlayers') { return ids.slice(); }
    const row = store.get(id);
    if (!row) { return undefined; }
    // The engine hands an appearance back parsed, a fresh object each time.
    if (k === 'appearance') { return row.appearanceDump ? JSON.parse(row.appearanceDump) : null; }
    const v = row[k];
    return (v && typeof v === 'object') ? JSON.parse(JSON.stringify(v)) : v;
  },
  set: function (id, k, v) {
    count('set:' + k);
    const row = store.get(id) || {};
    row[k] = v;
    store.set(id, row);
  },
  makeProperty: function () { },
  makeEventSource: function () { },
  getNeighborsByPosition: function () { return ids.slice(); },
  callPapyrusFunction: function () { return undefined; },
  getDescFromId: function (id) { return (id >>> 0).toString(16) + ':Skyrim.esm'; },
  getIdFromDesc: function () { return 0; },
  sendCustomPacket: function () { },
  findFormsByPropertyValue: function () { return []; },
  place: function () { return 0; },
  lookupEspmRecordById: function () { return { record: null }; },
  getEspmLoadOrder: function () { return ['Skyrim.esm', 'Update.esm']; },
  clear: function () { }
};
const unknown = {};
const mp = new Proxy(mpBase, {
  get: function (t, k) {
    if (k in t) { return t[k]; }
    if (typeof k === 'string' && !/^on/.test(k)) {
      unknown[k] = (unknown[k] || 0) + 1;
      return function () { return undefined; };
    }
    return undefined;
  },
  set: function (t, k, v) { t[k] = v; return true; }
});

// -------------------------------------------------------- timers and requires
const intervals = [];
let lineOf = function () { return 0; };
function where() {
  const s = String(new Error().stack).split('\n');
  for (let i = 0; i < s.length; i++) {
    const m = /gamemode\.js:(\d+)/.exec(s[i]);
    if (m) { return Number(m[1]); }
  }
  return 0;
}
function fakeSetInterval(fn, ms) {
  const row = { fn: fn, ms: Number(ms) || 0, line: where(), cleared: false };
  intervals.push(row);
  return row;
}
function fakeClearInterval(row) { if (row && typeof row === 'object') { row.cleared = true; } }

const sent = [];            // bodies the gamemode posted, by path
function fakeHttp() {
  return {
    request: function (opts, cb) {
      const chunks = [];
      const req = {
        on: function () { return req; }, setTimeout: function () { return req; },
        destroy: function () { }, write: function (b) { chunks.push(String(b)); },
        end: function (b) {
          if (b) { chunks.push(String(b)); }
          sent.push({ path: (opts && opts.path) || '', body: chunks.join('') });
          // Answer at once, so a sender that waits for the answer (the voice
          // feed never has two in flight) sends again on its next pass.
          if (typeof cb === 'function') {
            const res = { statusCode: 200, resume: function () { },
                          on: function (ev, fn) { if (ev === 'end') { fn(); } return res; },
                          setEncoding: function () { } };
            try { cb(res); } catch (e) { }
          }
        }
      };
      return req;
    },
    get: function () { const r = { on: function () { return r; }, setTimeout: function () { return r; }, destroy: function () { } }; return r; },
    createServer: function () { return { listen: function () { }, on: function () { } }; }
  };
}
function fakeRequire(name) {
  if (name === 'http' || name === 'https') { return fakeHttp(); }
  if (name === 'child_process') { return { exec: function () { }, spawn: function () { return { on: function () { } }; } }; }
  return require(name);
}

const quiet = { log: function () { }, error: function () { }, warn: function () { }, info: function () { } };
const sandbox = {
  mp: mp, require: fakeRequire, console: QUIET ? quiet : console, process: process, Buffer: Buffer,
  setInterval: fakeSetInterval, clearInterval: fakeClearInterval,
  setTimeout: function () { return { unref: function () { } }; }, clearTimeout: function () { },
  setImmediate: function () { }, Date: Date, URL: URL, TextEncoder: TextEncoder, TextDecoder: TextDecoder
};
sandbox.globalThis = sandbox;
vm.createContext(sandbox);

const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');
let loadErr = null;
try { vm.runInContext(src, sandbox, { filename: 'gamemode.js' }); }
catch (e) { loadErr = e; }
yes('the whole gamemode loads against the stand-in' + (loadErr ? ' (it threw: ' + loadErr.message + ')' : ''), !loadErr);

// Each timer's name: the guard name if it has one, else the nearest block
// marker above its line.
const lines = src.split('\n');
function nameOf(row) {
  const at = row.line - 1;
  const own = /guard\('([A-Za-z]+)'/.exec(lines[at] || '');
  if (own) { return own[1]; }
  const g = /__thornswood([A-Za-z]+)\s*=\s*(\{\s*timer:\s*)?setInterval/.exec(lines[at] || '');
  if (g) { return g[1]; }
  for (let i = at; i > 0 && i > at - 4000; i--) {
    const m = /^\/\/ ==== thornswood ([a-z0-9 ,'-]+?) ====$/.exec(lines[i]);
    if (m && !/^end /.test(m[1])) { return m[1]; }
  }
  return 'line ' + row.line;
}

// ------------------------------------------------------------------- measure
function time(fn, runs) {
  const t0 = process.hrtime.bigint();
  for (let i = 0; i < runs; i++) { try { fn(); } catch (e) { } }
  return Number(process.hrtime.bigint() - t0) / 1e6;
}

const live = intervals.filter(function (r) { return !r.cleared && r.ms > 0; });
yes('the gamemode starts its timers (' + live.length + ' found)', live.length >= 10);

const table = [];
live.forEach(function (row) {
  for (let w = 0; w < 5; w++) { try { row.fn(); } catch (e) { } }   // warm
  for (const k in reads) { delete reads[k]; }
  const runs = Math.max(20, Math.min(400, Math.round(20000 / row.ms)));
  counting = true;
  const ms = time(row.fn, runs);
  counting = false;
  let got = 0;
  for (const k in reads) { got += reads[k]; }
  const perSec = 1000 / row.ms;
  table.push({ name: nameOf(row), line: row.line, every: row.ms, msRun: ms / runs,
               coreShare: (ms / runs) * perSec / 10, readsSec: got / runs * perSec,
               reads: Object.assign({}, reads), runs: runs });
});
table.sort(function (a, b) { return b.coreShare - a.coreShare; });

console.log('');
console.log('The gamemode\'s timers with ' + PEOPLE + ' people on, costliest first:');
console.log('  ' + 'timer'.padEnd(26) + 'every'.padStart(8) + 'ms/run'.padStart(9) +
            '% core'.padStart(8) + 'reads/s'.padStart(9) + '   line');
table.forEach(function (t) {
  console.log('  ' + t.name.slice(0, 25).padEnd(26) + (t.every + 'ms').padStart(8) +
              t.msRun.toFixed(3).padStart(9) + t.coreShare.toFixed(2).padStart(8) +
              Math.round(t.readsSec).toString().padStart(9) + '   ' + t.line);
});
const total = table.reduce(function (s, t) { return s + t.coreShare; }, 0);
const totalReads = table.reduce(function (s, t) { return s + t.readsSec; }, 0);
console.log('  ' + 'all of them'.padEnd(26) + ''.padStart(17) + total.toFixed(2).padStart(8) +
            Math.round(totalReads).toString().padStart(9));
const heaviest = table.slice().sort(function (a, b) { return b.readsSec - a.readsSec; })[0];
console.log('  most engine reads: ' + heaviest.name + ', ' + Math.round(heaviest.readsSec) +
            ' a second: ' + Object.keys(heaviest.reads).sort(function (a, b) {
              return heaviest.reads[b] - heaviest.reads[a];
            }).map(function (k) {
              return k + ' ' + Math.round(heaviest.reads[k] / heaviest.runs * 1000 / heaviest.every) + '/s';
            }).join(', '));
if (Object.keys(unknown).length) { console.log('  (stand-in answered nothing for: ' + Object.keys(unknown).join(', ') + ')'); }
console.log('');

// ------------------------------------------------------------ one timer's pass
function passOf(row) {
  for (const k in reads) { delete reads[k]; }
  sent.length = 0;
  counting = true; try { row.fn(); } catch (e) { } counting = false;
  return Object.assign({}, reads);
}
function byName(n) { return table.filter(function (t) { return t.name === n; })[0]; }
function rowFor(n) {
  return live.filter(function (r) { return nameOf(r) === n; })[0];
}

// ----------------------------------------------------------- the social tick
// The costliest timer before #385: every person's panel asked the engine for
// every other person's name, profile id and journals, each pass.
const social = rowFor('socialTick');
yes('the social tick is found', !!social);
if (social) {
  const r = passOf(social);
  console.log('  social tick, one pass: ' + (r.appearance || 0) + ' appearance, ' +
              (r.profileId || 0) + ' profile id, ' + (r.thornswoodSocial || 0) + ' journal reads, ' +
              (r.onlinePlayers || 0) + ' online lists');
  yes('it reads each person\'s appearance once a pass (' + (r.appearance || 0) + ' for ' + PEOPLE + ')',
      (r.appearance || 0) <= PEOPLE);
  yes('and each profile id once (' + (r.profileId || 0) + ')', (r.profileId || 0) <= PEOPLE);
  yes('and each person\'s journals once (' + (r.thornswoodSocial || 0) + ')', (r.thornswoodSocial || 0) <= PEOPLE);
  yes('and the online list once (' + (r.onlinePlayers || 0) + ')', (r.onlinePlayers || 0) <= 1);
  const t = byName('socialTick');
  yes('its engine reads a second stay under ten a person (' + Math.round(t.readsSec) + ' for ' + PEOPLE + ')',
      t.readsSec < PEOPLE * 10);

  // Nothing is held between passes: a rename shows on the next pass, and a
  // command between passes (outside the tick) reads fresh.
  const S = sandbox.__thornswoodSocial;
  const target = store.get(ids[2]);
  const d = JSON.parse(target.appearanceDump); d.name = 'Newname';
  target.appearanceDump = JSON.stringify(d);
  // Make person 2 a friend of person 0 so person 0's panel names them.
  store.get(ids[0]).thornswoodSocial = { friends: {}, muted: {}, journals: [], at: 1 };
  store.get(ids[0]).thornswoodSocial.friends[target.profileId] = { name: '' };
  const was = {};
  const origSet = mpBase.set;
  mpBase.set = function (id, k, v) { if (k === 'thornswoodSocialView') { was[id] = v; } return origSet(id, k, v); };
  try { social.fn(); } finally { mpBase.set = origSet; }
  const panel = was[ids[0]];
  const named = panel && panel.friends && panel.friends.filter(function (f) { return f.name === 'Newname'; })[0];
  yes('a renamed friend shows by the new name on the next pass', !!named && named.on === true);
  const found = S && S.findPerson ? S.findPerson('Newname') : null;
  yes('outside the tick, finding somebody by name reads fresh', !S || !S.findPerson || (found && found.actorId === ids[2]));
}

// ---------------------------------------------------------- the voice feed
const feed = live.filter(function (r) { return r.ms === 200; })[0];
yes('the voice feed is a 200 ms timer', !!feed);
if (feed) {
  function pass1() {
    const r = passOf(feed);
    const last = sent.filter(function (s) { return s.path === '/positions'; }).pop();
    return { reads: r, body: last ? JSON.parse(last.body) : null };
  }
  const p = pass1();
  console.log('  voice feed, one pass: ' + (p.reads.appearance || 0) + ' appearance and ' +
              (p.reads.profileId || 0) + ' profile id reads for ' + PEOPLE + ' people');
  yes('the voice feed reads each appearance once a pass, not twice (' + (p.reads.appearance || 0) + ')',
      (p.reads.appearance || 0) <= PEOPLE);
  yes('and each profile id once, not twice (' + (p.reads.profileId || 0) + ')',
      (p.reads.profileId || 0) <= PEOPLE);
  const b = p.body;
  yes('it still sends a row for every person', !!b && b.who && b.who.length === PEOPLE);
  const r1 = b && b.who && b.who[1];
  const want = store.get(ids[1]);
  yes('each row carries profile id, position, facing, cell, name and party',
      !!r1 && r1.profileId === want.profileId && JSON.stringify(r1.pos) === JSON.stringify(want.pos) &&
      r1.angleZ === want.angle[2] && r1.cell === want.worldOrCellDesc &&
      r1.name === 'Person 1' && r1.party === '');
  want.pos = [9, 8, 7];
  const q = pass1();
  const moved = q.body && q.body.who && q.body.who[1];
  yes('the position is read fresh on every pass', !!moved && JSON.stringify(moved.pos) === '[9,8,7]');
}

// ------------------------------------------------------------ the minute line
const beat = sandbox.__thornswoodServerBeat;
yes('the server\'s minute line is running', !!beat && typeof beat.beat === 'function');
if (beat) {
  const logged = [];
  const logFile = path.join(scratch, 'thornswood.log');
  let before = '';
  try { before = fs.readFileSync(logFile, 'utf8'); } catch (e) { before = ''; }
  // A handler that takes 5 ms, run ten times through guard(), shows as 50 ms.
  const slow = vm.runInContext("guard('slowOne', function () { var t = Date.now(); while (Date.now() - t < 5) { } })", sandbox);
  for (let i = 0; i < 10; i++) { slow(); }
  beat.beat();
  let after = '';
  try { after = fs.readFileSync(logFile, 'utf8'); } catch (e) { after = ''; }
  const line = after.slice(before.length).split('\n').filter(function (l) { return / server: /.test(l); })[0] || '';
  console.log('  ' + line.replace(/^\S+ \S+ /, ''));
  yes('it says how many are on and the process\'s share of a core', /\d+ on, process \d+(\.\d)?% of one core/.test(line));
  yes('and how late the event loop ran', /loop late p50 [\d.]+ms p99 [\d.]+ms worst \d+ms/.test(line));
  const m = /slowOne (\d+)ms\/10 worst ([\d.]+)ms/.exec(line);
  yes('and the costliest handlers: slowOne took about 50 ms over 10 runs, worst about 5',
      !!m && Number(m[1]) >= 48 && Number(m[1]) <= 70 && Number(m[2]) >= 4.9);
  const handler = vm.runInContext("guard('answers', function (a) { return a * 2; })", sandbox);
  yes('guard still hands back what the handler returns', handler(21) === 42);
  const thrower = vm.runInContext("guard('throws', function () { throw new Error('x'); })", sandbox);
  let escaped = false;
  try { yes('and undefined when it throws, never letting it out', thrower() === undefined); }
  catch (e) { escaped = true; }
  yes('nothing a handler throws escapes guard', !escaped);
}

process.chdir(home);
try { fs.rmSync(scratch, { recursive: true, force: true }); } catch (e) { }
console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
