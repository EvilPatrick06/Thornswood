// test-fire-walk.js
//
// Walking into a new cell must not throw out of the place tick.
//
// WHAT WAS MEASURED. The dev client's front log for 23 September,
// C:\Thornswood-DevBuild\Game\Data\Platform\thornswood-front.log, has 80 lines
// of
//
//     place threw: ReferenceError: walked is not defined
//
// between 20:08 and 21:00, and not one "fires: N of ours in this cell" line.
// #184 moved the fire probe off Game.findClosestReferenceOfType and onto a
// walk of the cell, and the line fireSpotsHere logs at the end of that walk
// named `walked`, which was the counter inside the walk. Its own is
// fireWalked. So every cell change threw after the fires had been kept, the
// place tick died before it composed its line, and the /place report for that
// tick never reached the server. The tick after it read the kept list and got
// through, which is why nothing looked broken from the outside.
//
// test-temp.js reads this code as text, and text that names a variable which
// does not exist reads exactly as well as text that names one that does. So
// this RUNS it: the real CELL_TYPES, walkCellSlice, the fire state, fireIdList,
// fireSpotsHere and fireDistance, lifted out of the plugin, over a fake cell
// and a fake sp. The fire table is a stub of two real Skyrim.esm bases, because
// the table is data and the walk is what is under test.
//
// THE CLOCK IS THE HARNESS'S (#2581). The walk stops once FIRE_SLICE_MS (2 ms)
// has gone by performance.now, which is right in the game, where the slice is
// a frame's budget. Run on the real clock here, a busy machine spent the 2 ms
// before the walk had read the fake cell's four references, and S1 read a walk
// that had not finished: 11 passed 8 failed one run, 19 passed the next. So
// the lifted code is handed a performance of the harness's own, whose time
// moves only when the harness moves it. S1 to S4 test the walk on a clock that
// stands still; S5 moves it a millisecond for each reference read and checks
// that the slice does stop once its time is spent, and that the walk finishes
// over the next slices with the same answer.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const SRC = process.env.FRONT ||
            path.join(REPO_DIR, 'game', 'plugins', 'thornswood-front.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// From `from` to the end of the named function. The end is the first closing
// brace at the plugin's own indent after the function starts, and everything
// inside a function is indented further than that.
function lift(from, fnName) {
  const a = src.indexOf(from);
  if (a < 0) { return null; }
  const f = src.indexOf('function ' + fnName + '(', a);
  if (f < 0) { return null; }
  const END = '\n  }\n';
  const b = src.indexOf(END, f);
  return b < 0 ? null : src.slice(a, b + END.length);
}

const walk = lift('  const CELL_TYPES = [', 'walkCellSlice');
const fires = lift('  let fireBases = 0;', 'fireDistance');
const reach = /const FIRE_REACH = (\d+);/.exec(src);
const inside = /const FIRE_INSIDE = (\d+);/.exec(src);
yes('the cell walk is in the plugin', walk !== null);
yes('the fire probe is in the plugin', fires !== null);
yes('the fire reach is in the plugin', !!reach && !!inside);

const FXFIRE01 = 0x13b40;
const EMBERS_HEAVY = 0x33da4;
const NOT_A_FIRE = 0x999;

// The time the lifted code reads, in milliseconds. It starts well above zero,
// as performance.now does in a game that has been running, and moves only
// when a test moves it.
function standingClock() {
  const c = { t: 1000 };
  c.performance = { now: function () { return c.t; } };
  return c;
}

function harness(clock) {
  const logs = [];
  const log = function () { logs.push(Array.prototype.join.call(arguments, ' ')); };
  const time = clock || standingClock();
  const sp = {
    Game: {
      getFormEx: function (id) { return { id: id }; },
      getFormFromFile: function (id) { return { id: id }; }
    },
    Form: {
      from: function (raw) {
        return raw ? { getFormID: function () { return raw.id; } } : null;
      }
    }
  };
  const fn = new Function('sp', 'log', 'FIRE_BASES', 'FIRE_FILES',
    'FIRE_REACH', 'FIRE_INSIDE', 'performance', walk + fires +
    '\nreturn {' +
    '  spots: fireSpotsHere,' +
    '  distance: fireDistance,' +
    '  walked: function () { return fireWalked; },' +
    '  hits: function () { return fireHits; },' +
    '  threw: function () { return fireThrew; },' +
    '  bases: function () { return fireBases; },' +
    '  precise: SLICE_PRECISE,' +
    '  sliceMs: FIRE_SLICE_MS' +
    '};');
  const api = fn(sp, log,
    [['Skyrim.esm', FXFIRE01], ['Skyrim.esm', EMBERS_HEAVY]], ['Skyrim.esm'],
    Number(reach[1]), Number(inside[1]), time.performance);
  api.logs = logs;
  api.clock = time;
  api.sp = sp;
  return api;
}

function ref(base, x, y, z, off) {
  return {
    getBaseObject: function () { return { getFormID: function () { return base; } }; },
    getPositionX: function () { return x; },
    getPositionY: function () { return y; },
    getPositionZ: function () { return z; },
    isDisabled: function () { return !!off; }
  };
}

// A cell whose references are listed by form type. 'throw' makes asking for
// that type throw, the way a native call does on a bad cell.
// onRead, when given, runs at each reference read: S5 moves the clock there.
function cell(id, byType, calls, onRead) {
  return {
    getFormID: function () { return id; },
    getNumRefs: function (t) {
      calls.n++;
      if (byType[t] === 'throw') { throw new Error('no count for type ' + t); }
      return (byType[t] || []).length;
    },
    getNthRef: function (i, t) { if (onRead) { onRead(); } return byType[t][i]; }
  };
}

function standingIn(c) {
  return { getParentCell: function () { return c; } };
}

function tryIt(f) {
  try { return { value: f(), err: null }; }
  catch (e) { return { value: null, err: String((e && e.message) || e) }; }
}

if (walk !== null && fires !== null && reach && inside) {
  // S1: THE BUG. A cell nobody has been in yet, asked the way the place tick
  // asks, through fireDistance.
  {
    const h = harness();
    const calls = { n: 0 };
    const inn = cell(0x1605e, {
      24: [ref(FXFIRE01, 100, 0, 0), ref(NOT_A_FIRE, 0, 0, 0),
           ref(EMBERS_HEAVY, 10, 0, 0, true)],
      34: [ref(EMBERS_HEAVY, 1000, 0, 0)],
      36: 'throw',
      42: []
    }, calls);
    const me = standingIn(inn);

    const first = tryIt(function () { return h.distance(50, 0, 0, me); });
    yes('S1 walking into a new cell does not throw out of the place tick' +
        (first.err ? ' (it threw: ' + first.err + ')' : ''), first.err === null);
    yes('S1 the nearest lit fire is 50 away', first.value === 50);

    const spots = tryIt(function () { return h.spots(me); });
    yes('S1 it keeps the two lit fires of ours and nothing else',
        spots.err === null && spots.value.length === 2 &&
        spots.value[0][0] === 100 && spots.value[1][0] === 1000);
    yes('S1 the heartbeat counter says four things were looked at',
        h.walked() === 4);
    yes('S1 the log line says the same four',
        h.logs.indexOf('fires: 2 of ours in this cell, out of 4 thing(s) looked at') >= 0);
    yes('S1 the form type that threw is counted, not fatal', h.threw() === 1);
    yes('S1 both bases resolved', h.bases() === 2 && h.hits() === 2);

    // S2: the same cell again is the kept list, not a second walk.
    const asked = calls.n;
    const lines = h.logs.length;
    const again = tryIt(function () { return h.distance(1000, 0, 0, me); });
    yes('S2 the same cell is not walked twice', calls.n === asked);
    yes('S2 and says nothing new', h.logs.length === lines);
    yes('S2 standing at the far fire finds it', again.err === null && again.value === 0);

    // S3: the next cell is walked, and it is the one that used to throw
    // every time, because every cell change reached that line.
    const calls2 = { n: 0 };
    const yard = cell(0x9a7b, { 24: [ref(FXFIRE01, 0, 0, 0)] }, calls2);
    const next = tryIt(function () { return h.distance(400, 0, 0, standingIn(yard)); });
    yes('S3 the next cell does not throw either' +
        (next.err ? ' (it threw: ' + next.err + ')' : ''), next.err === null);
    yes('S3 and it was walked', calls2.n === 4);
    yes('S3 a fire past reach is no fire', next.value === -1);
    yes('S3 the counter moved to the new cell', h.walked() === 1);
    yes('S3 and the line says so',
        h.logs.indexOf('fires: 1 of ours in this cell, out of 1 thing(s) looked at') >= 0);
  }

  // S4: nowhere at all, which is the loading screen.
  {
    const h = harness();
    const r = tryIt(function () { return h.distance(0, 0, 0, standingIn(null)); });
    yes('S4 no cell is no fire and no throw', r.err === null && r.value === -1);
  }

  // S5: THE SLICE STOPS. Each reference read takes a millisecond of the
  // harness's clock, so a slice has time for FIRE_SLICE_MS of them. Five fires
  // take three slices, two, two and one, and a walk that ignored its slice
  // would read all five in the first.
  {
    const h = harness();
    yes('S5 the walk measures its slice on the clock the harness hands it',
        h.precise === true && h.sliceMs === 2);
    const fires5 = [];
    for (let k = 0; k < 5; k++) { fires5.push(ref(FXFIRE01, 100 * (k + 1), 0, 0)); }
    const calls = { n: 0 };
    const hall = cell(0x2a6f1, { 24: fires5 }, calls, function () { h.clock.t += 1; });
    const me = standingIn(hall);

    const first = tryIt(function () { return h.distance(100, 0, 0, me); });
    yes('S5 the first slice stops once its time is spent: ' + h.walked() + ' of 5 read, ' +
        h.sliceMs + ' fit', first.err === null && h.walked() === h.sliceMs);
    yes('S5 and a walk not finished is no fire yet, with nothing logged about it',
        first.value === -1 && h.logs.every(function (l) { return l.indexOf('in this cell') < 0; }));

    const read = [h.walked()];
    let last = first;
    while (last.err === null && last.value === -1 && read.length < 20) {
      last = tryIt(function () { return h.distance(100, 0, 0, me); });
      read.push(h.walked());
    }
    yes('S5 the next slices carry it on where it stopped, read so far after each: ' + read.join(', '),
        last.err === null && read.join(',') === '2,4,5');
    yes('S5 and it ends with every fire, each read once',
        last.value === 0 && h.walked() === 5 && h.hits() === 5 &&
        h.logs.indexOf('fires: 5 of ours in this cell, out of 5 thing(s) looked at') >= 0);
  }

  // S6: ONE SLICE FOR BOTH. Resolving the bases comes out of the same slice
  // as the walk. When asking for a base takes 3 ms, the first slice resolves
  // one base and stops, the second resolves the other and leaves the walk
  // nothing, and the walk starts in the third.
  {
    const h = harness();
    const ask = function (id) { h.clock.t += 3; return { id: id }; };
    // The lifted code holds the sp it was made with, so the stub is swapped
    // on that object.
    const calls = { n: 0 };
    const yard = cell(0x9a7c, { 24: [ref(EMBERS_HEAVY, 30, 0, 0)] }, calls);
    const me = standingIn(yard);
    h.sp.Game.getFormEx = ask;
    tryIt(function () { return h.distance(0, 0, 0, me); });
    yes('S6 a slice spent on one base resolves no more', h.bases() === 0 && calls.n === 0);
    tryIt(function () { return h.distance(0, 0, 0, me); });
    yes('S6 the slice that resolves the last base leaves the walk nothing', h.bases() === 2 && calls.n === 0);
    const third = tryIt(function () { return h.distance(0, 0, 0, me); });
    yes('S6 the walk has the next slice to itself', third.err === null && third.value === 30 && calls.n === 4);
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
