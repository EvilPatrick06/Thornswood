'use strict';
/*
  test-2479-cut-outs.js

  #2479. The spoils block's cut-out list (Dragon Bone and the two Riekling
  spear spell tomes, cut by #1511) was never read: isCutOut had no caller, so
  a chest and the floor both handed all three out. isSpoil now asks it.

  Drives the REAL spoils block out of gamemode.js over a fake mp, the way
  test-spoils.js does, and checks:
    - each of the three is a spoil, with no record kind that would make it one;
    - a chest holds none of them, because the world fills no chest
      (forbiddenBaseContainer, #3078; tests\test-spoils.js);
    - each placed by the world on the floor is refused;
    - one a person dropped is left alone, like any spoil;
    - while the load order is still coming in, nothing is refused by mistake,
      and once it is in, the cut rows are;
    - isCutOut has a caller in the block, so it cannot sit unread again.

  Read only.
*/
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(REPO_DIR, 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function done() {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}

const A = '// ==== thornswood spoils ====';
const B = '// ==== end thornswood spoils ====';
const a = src.indexOf(A);
const b = a < 0 ? -1 : src.indexOf(B, a);
const block = (a >= 0 && b >= 0) ? src.slice(a, b) : null;
yes('the spoils block is in the gamemode', block !== null);
if (!block) { done(); }

const CUTS = ['3ada4:Skyrim.esm', 'bff20:Playable Rieklings.esp', 'bff21:Playable Rieklings.esp'];
const m = /var CUT_OUTS = (\[[^\]]*\]);/.exec(block);
let listed = null;
try { listed = m ? JSON.parse(m[1]) : null; } catch (e) { listed = null; }
yes('the cut-out list is Dragon Bone and the two Riekling tomes',
    !!listed && JSON.stringify(listed.slice().sort()) === JSON.stringify(CUTS.slice().sort()));

const calls = block.split('isCutOut(').length - 1;
yes('isCutOut is called, not only defined (' + (calls - 1) + ' caller(s))', calls >= 2);

/** The block over a fake mp. ready() says whether a descriptor has an id yet. */
function rig(ready) {
  const store = {}, kinds = {}, timers = [], ids = {};
  let nextId = 0x100;
  function idOf(desc) {
    if (ready && !ready(desc)) { return 0; }
    if (!ids[desc]) { ids[desc] = nextId++; }
    return ids[desc];
  }
  const Fake = {
    makeProperty: function () { },
    get: function (id, key) {
      const row = store[id] || {};
      if (key === 'inventory') { return { entries: (row.inventory || []).slice() }; }
      return row[key];
    },
    set: function (id, key, v) {
      if (!store[id]) { store[id] = {}; }
      if (key === 'inventory') { store[id].inventory = (v && v.entries) || []; return; }
      store[id][key] = v;
    },
    lookupEspmRecordById: function (baseId) {
      const t = kinds[baseId];
      return t ? { record: { type: t } } : null;
    }
  };
  const fn = new Function(
    'globalThis', 'mp', 'console', 'idOf', 'TOOLS', 'setTimeout', 'putBack',
    'Math', 'Number', 'String', 'Object', 'Array', 'Date',
    block + '\nreturn globalThis.__thornswoodSpoils;');
  const api = fn({}, Fake, { log: function () { } }, idOf, {},
    function (f, ms) { timers.push({ f: f, ms: ms }); return timers.length; },
    function () { }, Math, Number, String, Object, Array, Date);
  api.idOf = idOf;
  api.kind = function (desc, type) { const id = idOf(desc); kinds[id] = type; return id; };
  api.put = function (refrId, entries) { store[refrId] = store[refrId] || {}; store[refrId].inventory = entries; };
  api.inv = function (refrId) { return (store[refrId] || {}).inventory || []; };
  return api;
}

// ------------------------------------------------------------ what counts
{
  const g = rig();
  // A misc item and two books: no record kind makes any of them a spoil.
  const ids = [g.kind(CUTS[0], 'MISC'), g.kind(CUTS[1], 'BOOK'), g.kind(CUTS[2], 'BOOK')];
  const bread = g.kind('bread:Skyrim.esm', 'FOOD');
  const book = g.kind('book:Skyrim.esm', 'BOOK');
  yes('C1 Dragon Bone is a spoil', g.isSpoil(ids[0]));
  yes('C2 the first Riekling tome is a spoil', g.isSpoil(ids[1]));
  yes('C3 the second Riekling tome is a spoil', g.isSpoil(ids[2]));
  yes('C4 bread still is not', !g.isSpoil(bread));
  yes('C5 nor is any other book', !g.isSpoil(book));
}

// ------------------------------------------------------------ the floor
{
  const g = rig();
  CUTS.forEach(function (d) { g.kind(d, d.indexOf('3ada4') === 0 ? 'MISC' : 'BOOK'); });
  const placed = 0x00012345, dropped = 0xff000123;
  CUTS.forEach(function (d, i) {
    const said = g.activate(1, placed + i, d);
    yes('F' + (i + 1) + ' ' + d + ' placed by the world is refused off the floor', typeof said === 'string' && said.length > 0);
  });
  yes('F4 one a person dropped is left alone, like any spoil', g.activate(1, dropped, CUTS[0]) === null);
}

// ------------------------------------------------------------ load order
{
  let rieklingsIn = false;
  const g = rig(function (d) { return rieklingsIn || d.indexOf('Rieklings') < 0; });
  const bone = g.kind(CUTS[0], 'MISC');
  const bread = g.kind('bread:Skyrim.esm', 'FOOD');
  yes('L1 before the load order is in, bread is still not a spoil', !g.isSpoil(bread));
  rieklingsIn = true;
  const tome = g.kind(CUTS[1], 'BOOK');
  yes('L2 once it is in, Dragon Bone is', g.isSpoil(bone));
  yes('L3 and so is the Riekling tome', g.isSpoil(tome));
}

done();
