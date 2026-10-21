// test-spoils.js
//
// Nothing is spawned in the world: no weapons, no armour, no tools, no gold.
//
// Patrick, 21 September: "all weapons, armour, tools, and gold are not spawned
// in the world at all. Not on the ground, not in containers, or display cases,
// not anywhere in the world unless made by someone or from the starter ones for
// Farmer, Miner, and Woodworker".
//
// And then, 22 September, having played it: "goldf, weaops, and armor are
// propley not able to be picked up off the ground but are still found in chests
// and able to be looted when they shouoldnt be."
//
// THE GROUND HALF ALWAYS WORKED AND THE CHEST HALF NEVER DID, for a reason
// that is invisible from the JavaScript: a container's contents are copied out
// of the plugin lazily, by EnsureBaseContainerAdded, and the engine's own
// Activate calls that AFTER this hook has run and returned. So the read came
// back empty every time, nothing was taken, and the chest then opened with
// everything Bethesda put in it.
//
// So the thing this file checks hardest is the SHAPE OF THE PRESS, not the
// classification: what happens when the inventory is empty at the moment of
// the press and full a moment later, which is every chest in Skyrim.
//
// It drives the REAL spoils block out of gamemode.js over a fake mp and a fake
// clock, the way test-needs.js does.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
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

const A = '// ==== thornswood spoils ====';
const B = '// ==== end thornswood spoils ====';
const a = src.indexOf(A);
const b = a < 0 ? -1 : src.indexOf(B, a);
const block = (a >= 0 && b >= 0) ? src.slice(a, b) : null;
yes('the spoils block is in the gamemode', block !== null);

/*
  The rig.

  Four things only a live server has: the espm lookup that says what kind of
  record a form is, the descriptor to id resolution, the tool table, and
  setTimeout. The timers are CAUGHT rather than run, so a test can decide
  whether the engine got round to filling the container before they fire, which
  is the whole question.
*/
function rig() {
  const store = {};       // refrId -> { inventory, stripped }
  const kinds = {};       // baseId -> record type
  const timers = [];
  const said = [];
  const ids = {};
  let nextId = 0x100;

  function idOf(desc) {
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

  const putBacks = [];
  const fn = new Function(
    'globalThis', 'mp', 'console', 'idOf', 'TOOLS', 'setTimeout', 'putBack',
    'Math', 'Number', 'String', 'Object', 'Array', 'Date',
    block + '\nreturn globalThis.__thornswoodSpoils;');
  const g = {};
  const api = fn(
    g, Fake, { log: function (s) { said.push(String(s)); } },
    idOf,
    { pick: { accept: ['pick:X.esm'] }, shovel: { accept: ['shovel:X.esm'] } },
    function (f, ms) { timers.push({ f: f, ms: ms }); return timers.length; },
    function (actorId, refrId) { putBacks.push([actorId, refrId]); },
    Math, Number, String, Object, Array, Date);
  api.putBacks = putBacks;

  api.idOf = idOf;
  api.said = said;
  api.store = store;
  /** Declare what kind of record a descriptor is. */
  api.kind = function (desc, type) { kinds[idOf(desc)] = type; return idOf(desc); };
  api.put = function (refrId, entries) {
    if (!store[refrId]) { store[refrId] = {}; }
    store[refrId].inventory = entries;
  };
  api.inv = function (refrId) { return (store[refrId] || {}).inventory || []; };
  api.timers = timers;
  /** Run every timer due at or before ms, in order, once. */
  api.fire = function (ms) {
    const due = timers.filter(t => t.ms <= ms);
    timers.length = 0;
    due.forEach(t => t.f());
    return due.length;
  };
  return api;
}

if (block) {
  const api = rig();
  const CHEST = api.kind('chest:Skyrim.esm', 'CONT');
  const SWORD = api.kind('sword:Skyrim.esm', 'WEAP');
  const HELM = api.kind('helm:Skyrim.esm', 'ARMO');
  const ARROW = api.kind('arrow:Skyrim.esm', 'AMMO');
  const BREAD = api.kind('bread:Skyrim.esm', 'FOOD');
  const GOLD = api.GOLD;
  const PICK = api.idOf('pick:X.esm');

  // ------------------------------------------------------ what counts
  {
    yes('a weapon is a spoil', api.isSpoil(SWORD));
    yes('armour is a spoil', api.isSpoil(HELM));
    yes('ammunition is a spoil', api.isSpoil(ARROW));
    yes('gold is a spoil', api.isSpoil(GOLD));
    yes('a tool off the TOOLS table is a spoil', api.isSpoil(PICK));
    yes('bread is not', !api.isSpoil(BREAD));
    // Not knowing has to mean not touching. One unreadable record would
    // otherwise empty every chest that held one.
    yes('a form the engine cannot name is left alone', !api.isSpoil(0xdead));
  }

  /*
    ------------------------------------------------------ THE FLOOR

    Patrick, 21 Oct 2026 (#3077): "don't spawn floor items anymore at all no
    matter what they are". Nothing a plugin placed lies on the floor any more:
    Thornswood-Last.esp switches every one off (tests/test-3077-floor-items.js
    holds the plugin to that). So a press on anything that is not a container
    is never refused here, whoever placed it, and the block carries no floor
    refusal and no coin purse rule to fall back on.
  */
  {
    const placed = 0x00012345;   // below 0xff000000: a plugin put it there
    const dropped = 0xff000123;  // above it: a person put it there
    yes('a press on a sword is never refused here, placed or dropped',
        api.activate(1, placed, 'sword:Skyrim.esm') === null && api.activate(1, dropped, 'sword:Skyrim.esm') === null);
    const flower = api.kind('flower:Skyrim.esm', 'FLOR');
    yes('nor on a flora of any kind, and nothing is put back for one',
        api.activate(7, placed, 'd790c:Skyrim.esm') === null && api.activate(7, placed, 'flower:Skyrim.esm') === null &&
        api.putBacks.length === 0 && flower > 0);
    yes('the block has no floor refusal line and no coin purse rule left in it',
        !/put here by the world/.test(block) && !/isPurse|PURSES|putBack\(/.test(block) &&
        api.isPurse === undefined && api.PURSES === undefined);
  }

  /*
    ------------------------------------------------------ THE CHEST

    This is the one that was wrong, and the shape is the whole of it. On the
    press the container is EMPTY, because the engine has not copied the
    plugin's contents in yet. It does that immediately afterwards, inside its
    own Activate, and then the chest opens on somebody's screen.
  */
  {
    const chest = 0x00055555;
    const g2 = rig();
    const C = g2.kind('chest:Skyrim.esm', 'CONT');
    g2.kind('sword:Skyrim.esm', 'WEAP');
    g2.kind('bread:Skyrim.esm', 'FOOD');
    const sword = g2.idOf('sword:Skyrim.esm'), bread = g2.idOf('bread:Skyrim.esm');

    g2.put(chest, []);                       // empty at the moment of the press
    g2.activate(1, chest, 'chest:Skyrim.esm');

    yes('an empty read takes nothing and records nothing',
        g2.inv(chest).length === 0 && !g2.alreadyStripped(chest));
    yes('but it asks to be looked at again', g2.timers.length >= 1);
    yes('and the first of those is immediate, not a quarter of a second later',
        g2.timers.some(t => t.ms === 0));

    // The engine fills it, the way EnsureBaseContainerAdded does.
    g2.put(chest, [
      { baseId: sword, count: 1 },
      { baseId: g2.GOLD, count: 60 },
      { baseId: bread, count: 2 }
    ]);
    g2.fire(0);

    const left = g2.inv(chest);
    yes('the second look empties it, on the same press',
        left.length === 1 && left[0].baseId === bread);
    yes('and the chest is marked so nobody comes back to it', g2.alreadyStripped(chest));
  }

  // A chest somebody has since put their own swords in is theirs.
  {
    const chest = 0x00066666;
    const g3 = rig();
    g3.kind('chest:Skyrim.esm', 'CONT');
    g3.kind('sword:Skyrim.esm', 'WEAP');
    const sword = g3.idOf('sword:Skyrim.esm');
    g3.put(chest, [{ baseId: sword, count: 1 }]);
    g3.activate(1, chest, 'chest:Skyrim.esm');
    yes('the first press empties a chest that was already full', g3.inv(chest).length === 0);
    // Now somebody stores their own work in it.
    g3.put(chest, [{ baseId: sword, count: 3 }]);
    g3.activate(1, chest, 'chest:Skyrim.esm');
    g3.fire(1000);
    yes('and a smith who stores their own swords in it keeps them',
        g3.inv(chest).length === 1 && g3.inv(chest)[0].count === 3);
  }

  // A chest that is genuinely empty is never recorded as done, or the first
  // empty chest anybody opened would become a chest nobody could ever be
  // stopped from filling with Bethesda's loot later.
  {
    const chest = 0x00077777;
    const g4 = rig();
    g4.kind('chest:Skyrim.esm', 'CONT');
    g4.activate(1, chest, 'chest:Skyrim.esm');
    g4.fire(1000);
    yes('an empty chest is still not marked after the second look',
        !g4.alreadyStripped(chest));
  }

  // The timers are the fix. A change that removes them puts the hole back.
  {
    const act = src.slice(src.indexOf('function activate(actorId, refrId, baseDesc)'),
                          src.indexOf('// ------------------------------------------------- where gold comes from --'));
    yes('the empty read is followed up rather than left to a second press',
        /strip\(refrId\) === 0/.test(act) && /setTimeout\(again, 0\)/.test(act));
    yes('and the reason is written next to it',
        /EnsureBaseContainerAdded/.test(act));
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
