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

  // ------------------------------------------------------ the ground
  {
    const placed = 0x00012345;   // below 0xff000000: a plugin put it there
    const dropped = 0xff000123;  // above it: a person put it there
    const swordNo = api.activate(1, placed, 'sword:Skyrim.esm');
    yes('a sword Bethesda left on a table does not come up',
        /put here by the world, not left by a person/.test(swordNo || '') && /not off the ground/.test(swordNo || ''));
    yes('a sword somebody dropped does', api.activate(1, dropped, 'sword:Skyrim.esm') === null);
    yes('and bread on a table is still bread',
        api.activate(1, placed, 'bread:Skyrim.esm') === null);
  }

  /*
    ------------------------------------------------------ COIN PURSES

    Patrick, 24 September, after a playtest: "people can pick up coin pocuhes
    off the ground that was supposed to be included in no gold lol". A purse is
    a FLOR whose produce is a leveled list of gold, and the engine rolls it and
    adds the coin itself, so the press is the only place to stop it.
  */
  {
    const g5 = rig();
    const flower = g5.kind('flower:Skyrim.esm', 'FLOR');
    const placed = 0x0001a2b3;
    let all = Array.isArray(g5.PURSES) && g5.PURSES.length === 6;
    for (const d of (g5.PURSES || [])) {
      g5.kind(d, 'FLOR');
      if (!g5.isSpoil(g5.idOf(d)) || !g5.isPurse || !g5.isPurse(g5.idOf(d))) { all = false; }
    }
    yes('all six coin purses are spoils', all);
    yes('a flower is not a purse and not a spoil', !!g5.isPurse && !g5.isPurse(flower) && !g5.isSpoil(flower));

    const no = g5.activate(7, placed, 'd790c:Skyrim.esm');
    yes('a coin purse in the world does not come up',
        /coin purse/.test(no || '') && /put here by the world, not left by a person/.test(no || '') &&
        /not off the ground/.test(no || ''));
    yes('and it is put back on the screen of the person who pressed it',
        g5.putBacks.length === 1 && g5.putBacks[0][0] === 7 && g5.putBacks[0][1] === placed);
    yes('a Thieves Guild purse does not come up either',
        /coin purse/.test(g5.activate(7, placed + 1, 'd8e8c:Skyrim.esm') || ''));
    const before = g5.putBacks.length;
    yes('a flower still picks', g5.activate(7, placed + 2, 'flower:Skyrim.esm') === null);
    yes('and nothing is put back for it', g5.putBacks.length === before);

    // The same block with no putBack in reach still refuses rather than
    // throwing.
    const bare = new Function('globalThis', 'mp', 'console', 'idOf', 'TOOLS', 'setTimeout',
      block + '\nreturn globalThis.__thornswoodSpoils;')(
      {}, { makeProperty: function () { }, get: function () { }, set: function () { },
            lookupEspmRecordById: function () { return { record: { type: 'FLOR' } }; } },
      { log: function () { } }, function (d) { return d === 'd790c:Skyrim.esm' ? 0xd790c : 0x999; },
      {}, function () { });
    let threw = false, ans = null;
    try { ans = bare.activate(7, placed, 'd790c:Skyrim.esm'); } catch (e) { threw = true; }
    yes('with no putBack about, a purse is still refused and nothing throws', !threw && /coin purse/.test(ans || ''));

    // #627: idOf answering 0 on the first press must not freeze an empty map.
    {
      const placed2 = 0x0002c3d4;
      const store = {};
      const kinds = {};
      const timers = [];
      const putBacks = [];
      const said = [];
      const ids = {};
      let nextId = 0x500;
      let ready = false;
      function realId(desc) {
        if (!ids[desc]) { ids[desc] = nextId++; }
        return ids[desc];
      }
      function lazyId(desc) {
        if (!ready) { return 0; }
        return realId(desc);
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
      const lazy = new Function(
        'globalThis', 'mp', 'console', 'idOf', 'TOOLS', 'setTimeout', 'putBack',
        'Math', 'Number', 'String', 'Object', 'Array', 'Date',
        block + '\nreturn globalThis.__thornswoodSpoils;')(
        {}, Fake, { log: function (s) { said.push(String(s)); } },
        lazyId,
        { pick: { accept: ['pick:X.esm'] }, shovel: { accept: ['shovel:X.esm'] } },
        function (f, ms) { timers.push({ f: f, ms: ms }); return timers.length; },
        function (actorId, refrId) { putBacks.push([actorId, refrId]); },
        Math, Number, String, Object, Array, Date);
      const first = lazy.activate(3, placed2, 'd790c:Skyrim.esm');
      yes('a purse pressed before the load order is ready is not yet known as a purse',
          first === null);
      ready = true;
      for (const d of (lazy.PURSES || [])) { kinds[realId(d)] = 'FLOR'; }
      const second = lazy.activate(3, placed2, 'd790c:Skyrim.esm');
      yes('the same purse pressed after idOf works is refused as a purse no person left',
          /coin purse/.test(second || '') && /put here by the world, not left by a person/.test(second || ''));
    }
  }

  /*
    The list is every FLOR in the load order whose produce is coin, as
    game\data\harvests.json has them. A rebuilt table with a purse this list lacks
    is a purse that pays out again, so that fails here.
  */
  {
    const hv = path.join(path.dirname(SRC), 'data', 'harvests.json');
    if (fs.existsSync(hv)) {
      const h = JSON.parse(fs.readFileSync(hv, 'utf8'));
      const un = h.unranked || {};
      const coin = Object.keys(un).filter(k => {
        const r = un[k] || {};
        return /coin/i.test(r.name || '') || /gold/i.test(r.produceName || '') || /purse/i.test(r.editorId || '');
      }).sort();
      const listed = (rig().PURSES || []).slice().sort();
      yes('every coin-giving flora in harvests.json is on the purse list (' + coin.length + ')',
          coin.length > 0 && coin.every(k => listed.indexOf(k) >= 0));
      yes('and every purse on the list is in harvests.json', listed.length > 0 && listed.every(k => coin.indexOf(k) >= 0));
    } else {
      yes('game\\data\\harvests.json is there to check the purse list against', false);
    }
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
