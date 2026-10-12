// test-1382-water.js
//
// #1382, drink.md and Patrick's answers of 12 Oct 2026: water is collected at
// a source, then boiled at a fire before it is safe. A well, Frostreach ice
// water and boiled water are safe; a river, a lake, the sea and standing
// water are not until boiled. Once somebody fills at a well, that well is
// done for them for one in-game day; other wells and boiled water still work.
//
// Root cause (#1382, issuecomment-6127861218): nothing collected water,
// nothing on the server knew where water came from, nothing boiled it, and
// fouled water was never asked of the disease block.
//
// Runs the REAL needs block over a stand-in mp, inventory and clock, with the
// REAL WATERS and WELLS tables out of gamemode.js. Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
const gm = fs.readFileSync(path.join(ROOT, 'game', 'gamemode.js'), 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, ok) {
  if (ok) { pass++; console.log('PASS  ' + what); } else { fail++; console.log('FAIL  ' + what); }
}
function slice(a, b) {
  const i = gm.indexOf(a);
  const j = i < 0 ? -1 : gm.indexOf(b, i);
  return (i >= 0 && j >= 0) ? gm.slice(i, j + b.length) : null;
}
function table(name) {
  const m = new RegExp('^const ' + name + ' = (\\{.*\\});$', 'm').exec(gm);
  return m ? JSON.parse(m[1]) : null;
}
const needsBlock = slice('// ==== thornswood needs: hunger, thirst and exhaustion ====', '// ==== end thornswood needs ====');
const WATERS = table('WATERS');
const WELLS = table('WELLS');
yes('the needs block and the water table are in the gamemode', !!needsBlock && !!WATERS);
yes('the well table is in the gamemode, read out of the load order', !!WELLS && Array.isArray(WELLS.items) && WELLS.items.length > 0);

const EMPTY = 0xf2012, FULL = 0x13f598;
function idOf(d) { return d === 'f2012:Skyrim.esm' ? EMPTY : d === '13f598:WindhelmSSE.esp' ? FULL : 0; }

// A river cell, a deep cell, an ice cell, out of the real WATERS.
function cellOf(cls) {
  for (const k in (WATERS && WATERS.items) || {}) { if (WATERS.items[k] === cls) { return k; } }
  return null;
}
const RIVER = cellOf('river'), ICE = cellOf('ice'), MARSH = cellOf('marsh') || cellOf('puddle') || cellOf('still');
const SEA = 'sea-cell:Test.esm';
yes('the water table names a river, an ice water and a standing water', !!RIVER && !!ICE && !!MARSH);

function rig() {
  const clock = { now: Date.UTC(2026, 9, 12, 17, 0, 0) };
  const store = {}, where = {}, inv = {}, said = [], fouled = [];
  const mp = {
    getOnlinePlayers: function () { return []; },
    makeProperty: function () { },
    get: function (id, key) {
      if (key === 'worldOrCellDesc') { return where[id] ? where[id].desc : ''; }
      if (key === 'pos') { return where[id] ? where[id].pos : null; }
      return store[id];
    },
    set: function (id, key, v) { store[id] = JSON.parse(JSON.stringify(v)); }
  };
  function count(id, b) { return (inv[id] && inv[id][b]) || 0; }
  function addItem(id, desc, n) { const b = idOf(desc); if (!b) { return false; } inv[id] = inv[id] || {}; inv[id][b] = count(id, b) + n; return true; }
  function takeItemById(id, b, n) { if (count(id, b) < n) { return false; } inv[id][b] -= n; return true; }
  const g = { __thornswoodHurt: { exposed: function (id, kind, source) { fouled.push([id, kind, source]); return false; } } };
  const N = new Function('globalThis', 'mp', 'Date', 'console', 'setInterval', 'clearInterval',
    'guard', 'notify', 'say', 'idOf', 'addItem', 'takeItemById', 'WATERS', 'WELLS',
    needsBlock + '\nreturn globalThis.__thornswoodNeeds;')(
    g, mp, { now: function () { return clock.now; } }, { log: function () { } },
    function () { return 0; }, function () { }, function (n, f) { return f; },
    function () { }, function (id, line) { said.push(line); }, idOf, addItem, takeItemById, WATERS, WELLS);
  return {
    N: N, clock: clock, said: said, fouled: fouled, inv: inv, count: count, addItem: addItem,
    stand: function (id, desc, pos, kind, fire) {
      where[id] = { desc: desc, pos: pos || [0, 0, 0] };
      N.place(id, kind || 'outdoors', '-', '0', '0', '0', fire === undefined ? '-' : String(fire));
    },
    seed: function (id) { const n = N.fresh(); n.at = clock.now; n.drink = 30; store[id] = n; },
    water: function (id) { return (store[id] && store[id].water) || {}; },
    thirst: function (id) { return store[id].drink; }
  };
}

let r = null;
try { r = needsBlock ? rig() : null; } catch (e) { console.log('rig threw: ' + e.message); }
const N = r && r.N;
const ready = !!N && typeof N.fillWater === 'function' && typeof N.boilWater === 'function';
yes('the needs block hands out fillWater and boilWater', ready);

if (ready) {
  const A = 7;
  r.seed(A);
  r.stand(A, RIVER, [0, 0, 0], 'water');
  yes('no empty bottle, no fill', /empty bottle/.test(N.fillWater(A)));
  r.addItem(A, 'f2012:Skyrim.esm', 5);
  yes('a river fills, and says to boil it', /Boil it/.test(N.fillWater(A)) && r.water(A).river === 1);
  yes('the bottle is swapped for water', r.count(A, EMPTY) === 4 && r.count(A, FULL) === 1);

  r.stand(A, RIVER, [0, 0, 0], 'outdoors');
  yes('out of the water, nothing to fill from', /no water here/.test(N.fillWater(A)));

  // Drink the river water unboiled: 20 thirst and the river's chance of fouling.
  let before = r.thirst(A);
  N.consumed(A, FULL);
  yes('unboiled river water quenches 20', Math.round(r.thirst(A) - before) === 20);
  yes('and is asked of the disease block as fouled river water',
    r.fouled.length === 1 && r.fouled[0][1] === 'fouled' && r.fouled[0][2] === 'river');

  // Standing water, then the sea: worst first.
  r.stand(A, MARSH, [0, 0, 0], 'shallow');
  N.fillWater(A);
  r.stand(A, SEA, [0, 0, 0], 'water');
  N.fillWater(A);
  r.fouled.length = 0;
  before = r.thirst(A);
  N.consumed(A, FULL);
  yes('drinking takes the worst first: standing water, 15', Math.round(r.thirst(A) - before) === 15 &&
    r.fouled.length === 1 && r.fouled[0][2] === 'standing');

  // Boil the sea water: a minute at a fire.
  r.stand(A, 'camp:Test.esm', [0, 0, 0], 'outdoors');
  yes('boiling needs a fire', /at a fire/.test(N.boilWater(A)));
  r.stand(A, 'camp:Test.esm', [0, 0, 0], 'outdoors', 100);
  yes('at a fire the water goes on', /over the fire/.test(N.boilWater(A)));
  r.clock.now += 30 * 1000;
  r.stand(A, 'camp:Test.esm', [0, 0, 0], 'outdoors', 400);
  yes('walking away from the fire loses the boil', r.water(A).sea === 1 && !r.water(A).boiled &&
    r.said.some(function (l) { return /did not boil/.test(l); }));
  r.stand(A, 'camp:Test.esm', [0, 0, 0], 'outdoors', 100);
  N.boilWater(A);
  r.clock.now += 61 * 1000;
  r.stand(A, 'camp:Test.esm', [0, 0, 0], 'outdoors', 90);
  yes('a minute at the fire boils it', r.water(A).boiled === 1 && !r.water(A).sea);
  r.fouled.length = 0;
  before = r.thirst(A);
  N.consumed(A, FULL);
  yes('boiled water is 20 and safe', Math.round(r.thirst(A) - before) === 20 && r.fouled.length === 0);

  // Frostreach ice water is safe without boiling.
  r.stand(A, ICE, [0, 0, 0], 'water');
  N.fillWater(A);
  r.fouled.length = 0;
  N.consumed(A, FULL);
  yes('Frostreach ice water is safe without boiling', r.fouled.length === 0 && !r.water(A).ice);

  // A bottle bought at an inn was never counted: safe.
  r.addItem(A, '13f598:WindhelmSSE.esp', 1);
  r.fouled.length = 0;
  N.consumed(A, FULL);
  yes('a bottle the server never saw filled is safe', r.fouled.length === 0);

  // Wells: safe, and one in-game day per well per person.
  r.addItem(A, 'f2012:Skyrim.esm', 10);
  const w0 = WELLS.items[0], w1 = WELLS.items.find(function (w) { return w[0] !== w0[0] || Math.abs(w[1] - w0[1]) > 1000; });
  r.stand(A, w0[0], [w0[1] + 50, w0[2], w0[3]], 'outdoors');
  yes('beside a well, it fills clean', /clean/.test(N.fillWater(A)) && r.water(A).well === 1);
  yes('the same well again is on cooldown, and says for how long', /drawn from this well today/.test(N.fillWater(A)) &&
    /72 minutes/.test(N.fillWater(A)));
  const B = 8; r.seed(B); r.addItem(B, 'f2012:Skyrim.esm', 1);
  r.stand(B, w0[0], [w0[1], w0[2], w0[3]], 'outdoors');
  yes('the cooldown is that person\'s alone', /clean/.test(N.fillWater(B)));
  r.stand(A, w1[0], [w1[1], w1[2], w1[3]], 'outdoors');
  yes('another well still works', /clean/.test(N.fillWater(A)));
  r.stand(A, w0[0], [w0[1], w0[2], w0[3]], 'outdoors');
  r.clock.now += 71 * 60000;
  yes('still on cooldown inside the day', /drawn from this well today/.test(N.fillWater(A)));
  r.clock.now += 61 * 1000;
  yes('after one in-game day the well works again', /clean/.test(N.fillWater(A)));
  yes('the cooldown is one number: 72 real minutes, a game day at twenty times',
    N.NEEDS.wellCooldownMinutes === 72);
  r.fouled.length = 0;
  N.consumed(A, FULL);
  yes('well water is safe without boiling', r.fouled.length === 0);

  // What is carried survives a read (the needs record rebuilds field by field).
  r.stand(A, RIVER, [0, 0, 0], 'water');
  N.fillWater(A);
  N.settle(A);
  yes('water carried survives the next read', r.water(A).river === 1);
}

const route = slice("    if (word === '/water') {", '\n      return true;\n    }');
yes('/water fill and /water boil reach the needs block', !!route && /needsWater\.fillWater\(actorId\)/.test(route) &&
  /needsWater\.boilWater\(actorId\)/.test(route));
const wm = /^const WORDS = (\[[\s\S]*?\]);$/m.exec(gm), pm = /^const PLAYER_WORDS = (\[[\s\S]*?\]);$/m.exec(gm);
yes('/water is a word the server answers, and not one the help lists',
  !!wm && wm[1].indexOf("'/water'") >= 0 && !!pm && pm[1].indexOf("'/water'") < 0);

// The buttons on the Body page (#1382, Patrick via Smeagle, 12 Oct): Fill
// water and Boil water send what /water fill and /water boil send.
const UI = fs.readFileSync(path.join(ROOT, 'game', 'ui', 'thornswood-skills.js'), 'utf8').split(CR).join('');
const needsDraw = (function () {
  const i = UI.indexOf('  function drawNeeds() {');
  const j = i < 0 ? -1 : UI.indexOf('\n  }\n', i);
  return (i >= 0 && j >= 0) ? UI.slice(i, j) : '';
})();
yes('the Body page has a Fill water button that sends /water fill',
  /el\('span', 'act', 'Fill water'\)/.test(needsDraw) && /fill\.onclick = [^\n]*officeSay\('\/water fill'\)/.test(needsDraw));
yes('and a Boil water button that sends /water boil',
  /el\('span', 'act', 'Boil water'\)/.test(needsDraw) && /boil\.onclick = [^\n]*officeSay\('\/water boil'\)/.test(needsDraw));
yes('the buttons send through the chat line every panel uses',
  /function officeSay\(line\) \{\n\s+if \(window\.thornswoodNet && window\.thornswoodNet\.say\) window\.thornswoodNet\.say\(line\);/.test(UI));

console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
