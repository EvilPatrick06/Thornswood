// test-cooldown-sweep.js
//
// A map that only ever grew, and a book that could be torn in half.
//
// From the To Do List: "Any cache keyed by something unbounded gets an
// eviction rule: a size cap, an age sweep, or removal when the session ends."
//
// lastUse holds one row per character and per reference for every press that
// gave something, and nothing ever took one out. The sweep drops a row once it
// is older than the longest wait any caller asks about, which is exactly when
// the row stops changing any answer, so this checks both halves of that: the
// map stays bounded, and no answer anybody gets is different after a sweep.
//
// characters.json was written in place, and writeFileSync empties a file
// before it fills it, so a server stopped halfway left a book the next start
// could not read, and every row for somebody offline was lost. It is written
// beside and renamed over now; this tears a write halfway and restarts.
//
// Reads the gamemode. Writes only into a scratch folder under the system
// temp folder, which it removes. GM=<path> reads another copy of the file.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const os = require('os');
const SRC = process.env.GM || path.join(TOOLS_DIR, '..', 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/* Comments in this repo quote old code on purpose, so a check that reads them
   as code is a check that punishes writing them. */
function codeOf(s) {
  return s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
}
const code = codeOf(src);

/** From a line to the close of the function it opens, or null. */
function fnBody(s, head) {
  const a = s.indexOf(head);
  if (a < 0) return null;
  const b = s.indexOf('\n}\n', a);
  return b < 0 ? null : s.slice(a, b + 3);
}

/** A top level `const NAME = ...;`, an object literal or one line. */
function constOf(name) {
  const head = 'const ' + name + ' = ';
  const a = src.indexOf(head);
  if (a < 0) return null;
  if (src.charAt(a + head.length) === '{') {
    const b = src.indexOf('\n};', a);
    return b < 0 ? null : src.slice(a, b + 3);
  }
  const b = src.indexOf(';', a);
  return b < 0 ? null : src.slice(a, b + 1);
}

// ================================================================ lastUse ===

const startAt = src.indexOf('const COOLDOWN_MS = 20000;');
const stampFn = startAt < 0 ? null : fnBody(src.slice(startAt), 'function stampCooldown(');
const block = (startAt >= 0 && stampFn)
  ? src.slice(startAt, src.indexOf(stampFn, startAt) + stampFn.length) : null;
const tables = ['HARVEST_COOLDOWN_MS', 'FISH_TUNING', 'GAME_TUNING', 'HUNT_TUNING'].map(constOf);

yes('the cooldown block is in the gamemode', block !== null);
yes('and so are the four tables of waits it reads', tables.every(function (t) { return t !== null; }));

/* The real block, with a clock, and a Map that counts how often it is walked. */
function rig(start) {
  const clock = { now: start || 1700000000000 };
  const walks = { n: 0 };
  class CountingMap extends Map {
    forEach(f, t) { walks.n++; return super.forEach(f, t); }
    [Symbol.iterator]() { walks.n++; return super[Symbol.iterator](); }
    entries() { walks.n++; return super.entries(); }
  }
  const fn = new Function('Date', 'Map',
    block + '\n' + tables.join('\n') + '\n' +
    'return { left: cooldownLeft, stamp: stampCooldown, map: lastUse,\n' +
    '  longest: typeof longestWaitMs === "function" ? longestWaitMs : null,\n' +
    '  mark: function () { return typeof lastUseSweepAt === "undefined" ? null : lastUseSweepAt; } };');
  const api = fn({ now: function () { return clock.now; } }, CountingMap);
  api.clock = clock;
  api.walks = walks;
  return api;
}

const HOUR = 3600000;

if (block !== null && tables.every(function (t) { return t !== null; })) {

  // C1: the longest wait comes off the tables, and today it is four hours.
  {
    const r = rig();
    yes('C1 the longest wait is worked out, not typed', r.longest !== null);
    yes('C1 and it is the four hours on a master spot', r.longest !== null && r.longest() === 4 * HOUR);
  }

  // C2: every table a cooldown is read against is one longestWaitMs reads.
  // A new source with a longer wait than any of these would otherwise have
  // its rows swept while they were still waiting.
  {
    const named = {};
    const re = /cooldownLeft\(|lastUse\.get\(/g;
    let m;
    while ((m = re.exec(code)) !== null) {
      const a = code.lastIndexOf('\nfunction ', m.index);
      const b = code.indexOf('\n}\n', m.index);
      if (a < 0 || b < 0) continue;
      const body = code.slice(a, b);
      const names = /\b([A-Z][A-Z0-9_]*)\.cooldownMs\b|\b((?:[A-Z][A-Z0-9_]*_)?COOLDOWN_MS)\b/g;
      let n;
      while ((n = names.exec(body)) !== null) named[n[1] || n[2]] = true;
    }
    const list = Object.keys(named).sort();
    console.log('      waits a cooldown is read against: ' + list.join(', '));
    yes('C2 the scan finds the quarry, the plants, the rivers, the game and the carcasses',
        ['COOLDOWN_MS', 'HARVEST_COOLDOWN_MS', 'FISH_TUNING', 'GAME_TUNING', 'HUNT_TUNING']
          .every(function (k) { return named[k]; }));
    const longestBody = fnBody(code, 'function longestWaitMs(');
    const missing = list.filter(function (k) {
      return !longestBody || !new RegExp('\\b' + k + '\\b').test(longestBody);
    });
    yes('C2 and longestWaitMs reads every one of them' +
        (missing.length ? ' (missing: ' + missing.join(', ') + ')' : ''), missing.length === 0);
  }

  // C3: one way in. The plants used to set their row directly, past the rule.
  {
    const sets = code.match(/lastUse\.set\(/g) || [];
    const stampBody = fnBody(code, 'function stampCooldown(') || '';
    yes('C3 there is one place a row is written into lastUse', sets.length === 1);
    yes('C3 and it is stampCooldown', stampBody.indexOf('lastUse.set(') >= 0);
  }

  // C4: THE POINT. Fifty thousand presses over fifty hours, one every 3.6
  // seconds, each on a different reference. Without the rule the map ends at
  // fifty thousand rows; with it, it never holds much more than two four hour
  // windows' worth.
  {
    const r = rig();
    let most = 0;
    for (let i = 0; i < 50000; i++) {
      r.clock.now += 3600;
      r.stamp(0xff000800 + (i % 20), 0x100000 + i);
      if (r.map.size > most) most = r.map.size;
    }
    console.log('      after 50,000 presses the map holds ' + r.map.size + ', at most ' + most);
    yes('C4 fifty hours of presses do not leave fifty thousand rows', r.map.size < 10000);
    yes('C4 and it never held more than two windows of four hours', most < 10000);
  }

  // C5: no answer changes across a sweep. Rows of every age from nothing to
  // six hours, asked about with every wait in the tables, before and after.
  {
    const r = rig();
    const T0 = r.clock.now;
    const spans = [20000, 600000, 1800000, 3600000, 4 * HOUR];
    const rows = [];
    for (let i = 0; i < 360; i++) {
      r.clock.now = T0 + i * 60000;           // one a minute for six hours
      r.stamp(0xff000900, 0x200000 + i);
      rows.push(0x200000 + i);
    }
    const askAt = T0 + 6 * HOUR;
    r.clock.now = askAt;
    function answers() {
      return rows.map(function (ref) {
        return spans.map(function (s) { return r.left(0xff000900, ref, s); }).join(',');
      }).join(';');
    }
    const before = answers();
    const stale = rows.filter(function (ref, i) { return askAt - (T0 + i * 60000) > 4 * HOUR; }).length;
    let filler = 0;
    while (r.map.has('4278192384:' + rows[0]) && filler < 20000) {
      r.stamp(0xff000a00, 0x300000 + filler);  // same moment, so the answers still match
      filler++;
    }
    const after = answers();
    const gone = rows.filter(function (ref) { return !r.map.has('4278192384:' + ref); }).length;
    yes('C5 a sweep ran once the map passed the mark', gone > 0);
    yes('C5 it took exactly the rows older than four hours (' + gone + ' of ' + stale + ')', gone === stale);
    yes('C5 and every answer for every wait is the same after it as before', before === after);
    // The one Patrick's economy leans on: a master spot three hours and
    // fifty-nine minutes into its four hours is still refused.
    const master = rows[121];                  // stamped at T0 + 2:01, six hours on is 3:59 later
    yes('C5 a master spot stamped 3h59m ago still has a minute to go',
        r.left(0xff000900, master, 4 * HOUR) === 60);
  }

  // C6: the press that pushes the map past the mark keeps its own row.
  {
    const r = rig();
    for (let i = 0; i < 4999; i++) { r.stamp(0xff000b00, 0x400000 + i); }
    r.clock.now += 5 * HOUR;                   // everything so far is stale
    r.stamp(0xff000b00, 0x4fffff);             // the 5000th row, and the sweep
    yes('C6 the stale rows went', r.map.size === 1);
    yes('C6 and the row that set it off is kept and counts', r.left(0xff000b00, 0x4fffff) === 20);
  }

  // C7: a map full of rows that are all still waiting is not walked on every
  // press. Twenty thousand in the same minute: walked at 5,000, 10,000 and
  // 20,000, and not the fifteen thousand times in between.
  {
    const r = rig();
    for (let i = 0; i < 20000; i++) { r.stamp(0xff000c00 + (i % 20), 0x500000 + i); }
    console.log('      twenty thousand live rows were walked ' + r.walks.n + ' time(s)');
    yes('C7 the sweep does run', r.walks.n >= 1);
    yes('C7 but only once per doubling, not once per press', r.walks.n <= 3);
    yes('C7 and nothing that was still waiting was dropped', r.map.size === 20000);
    yes('C7 and the next mark is twice what is there', r.mark() === 40000);
  }
}

// ============================================================ the roster ===

const rosterA = src.indexOf('// ==== thornswood character roster ====');
const rosterB = src.indexOf('// ==== end thornswood character roster ====');
const roster = (rosterA >= 0 && rosterB > rosterA) ? src.slice(rosterA, rosterB) : null;
yes('the roster block is in the gamemode', roster !== null);

/*
  The real block, over a real folder, with fs watched. tear makes the next
  write stop halfway through and throw, the way a server stopped mid-write
  leaves a file. refuse makes the next rename throw EPERM, the way Windows
  answers while something else holds the file open.
*/
function book(dir, online) {
  const spy = { writes: [], renames: [], tear: false, refuse: false };
  const wrapped = Object.assign({}, fs, {
    readFileSync: function (p, enc) {
      if (p === 'server-settings.json') return JSON.stringify({ privDir: dir, dataDir: dir });
      return fs.readFileSync(p, enc);
    },
    writeFileSync: function (p, data) {
      spy.writes.push(String(p));
      if (spy.tear) {
        spy.tear = false;
        fs.writeFileSync(p, String(data).slice(0, Math.floor(String(data).length / 2)));
        throw new Error('the server stopped');
      }
      return fs.writeFileSync(p, data);
    },
    renameSync: function (a, b) {
      spy.renames.push([String(a), String(b)]);
      if (spy.refuse) {
        spy.refuse = false;
        const e = new Error('EPERM: operation not permitted, rename'); e.code = 'EPERM';
        throw e;
      }
      return fs.renameSync(a, b);
    }
  });
  const people = {
    1: { pid: 42, name: 'Ada', raceId: 0x013746, female: true, prof: 'miner' },
    2: { pid: 43, name: 'Bram', raceId: 0x013741, female: false, prof: 'hunter' }
  };
  const mp = {
    get: function (id, key) {
      if (key === 'onlinePlayers') return online.slice();
      const p = people[id];
      if (!p) return null;
      if (key === 'profileId') return p.pid;
      if (key === 'appearance') return { name: p.name, raceId: p.raceId, isFemale: p.female };
      if (key === 'thornswoodCharacter') return { prof: p.prof };
      if (key === 'worldOrCellDesc') return '';
      return null;
    },
    lookupEspmRecordById: function () { return null; },
    getIdFromDesc: function () { return 0; }
  };
  let tick = null;
  const fn = new Function('require', 'mp', 'chargenOf', 'setInterval', 'setTimeout',
                          'clearInterval', 'globalThis', 'console', roster);
  fn(function (name) {
       if (name === 'fs') return wrapped;
       if (name === 'path') return path;
       throw new Error('not in this harness: ' + name);
     },
     mp,
     function () { return { class: '', destination: 'Whiterun' }; },
     function (f) { tick = f; return 1; },
     function () { return 0; },
     function () { },
     {},
     { log: function () { } });
  spy.tick = function () { if (tick) tick(); };
  return spy;
}

function readBook(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')).who || null; } catch (e) { return null; }
}

if (roster !== null) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-roster-'));
  const FILE = path.join(dir, 'characters.json');
  try {
    // R1: an ordinary write.
    const online = [1];
    const s = book(dir, online);
    s.tick();
    const whole = readBook(FILE);
    yes('R1 the book is written and has Ada in it', !!(whole && whole['42'] && whole['42'].name === 'Ada'));
    yes('R1 characters.json itself is never opened to be written into',
        s.writes.indexOf(FILE) === -1);
    yes('R1 it is written beside and renamed over',
        s.renames.some(function (r) { return r[0] === FILE + '.tmp' && r[1] === FILE; }));
    yes('R1 and nothing is left beside it', !fs.existsSync(FILE + '.tmp'));

    // R2: THE POINT. Bram comes on, and the server stops halfway through
    // writing him down.
    online.length = 0; online.push(2);
    s.tear = true;
    s.tick();
    const after = readBook(FILE);
    yes('R2 a write that stops halfway leaves the last whole book on disk',
        !!(after && after['42'] && after['42'].name === 'Ada'));

    // And the server starts again, with Bram still on.
    const again = book(dir, [2]);
    again.tick();
    const restarted = readBook(FILE);
    yes('R2 after the restart Ada, who was offline, is still in the book',
        !!(restarted && restarted['42'] && restarted['42'].name === 'Ada'));
    yes('R2 and Bram is written in beside her',
        !!(restarted && restarted['43'] && restarted['43'].name === 'Bram'));

    // R3: Windows refuses the rename while something else holds the file.
    fs.rmSync(FILE, { force: true });
    fs.rmSync(FILE + '.tmp', { force: true });
    const held = book(dir, [1]);
    held.refuse = true;
    held.tick();
    const inPlace = readBook(FILE);
    yes('R3 a refused rename still gets the book written, in place as before',
        !!(inPlace && inPlace['42'] && inPlace['42'].name === 'Ada'));
    yes('R3 and the file beside it is taken away', !fs.existsSync(FILE + '.tmp'));
  } finally {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { }
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
