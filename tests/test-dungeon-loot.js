// test-dungeon-loot.js
//
// A chest in a dungeon pays from the tier of the place.
// Gold, ordinary goods, a spell tome, and a short exclusive list.
// The world's own coin is still stripped. This pile is created on the open.
//
// Read only.
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

const A = '// ==== thornswood dungeon loot ====';
const B = '// ==== end thornswood dungeon loot ====';
const a = src.indexOf(A);
const b = a < 0 ? -1 : src.indexOf(B, a);
const block = (a >= 0 && b >= 0) ? src.slice(a, b) : null;
yes('the dungeon loot block is in the gamemode', block !== null);

function edidRecord(text) {
  const data = [];
  for (let i = 0; i < text.length; i++) data.push(text.charCodeAt(i));
  data.push(0);
  return { record: { fields: [{ type: 'EDID', data: data }] } };
}

function rig() {
  const store = {};
  const records = {};
  const given = [];
  const said = [];
  let clock = 1000000000000;
  const ids = {};
  let nextId = 0x200;
  let saved={version:1,entries:{}};
  const storage={load:()=>JSON.parse(JSON.stringify(saved)),save:next=>{saved=JSON.parse(JSON.stringify(next));}};

  function idOf(desc) {
    if (!ids[desc]) { ids[desc] = nextId++; }
    return ids[desc];
  }
  const mp = {
    getServerSettings:()=>({thornswoodServer:'dev'}),
    getNpcAIState:()=>({isHuman:true,profileId:1,isDead:false,isDisabled:false}),
    getDescFromId:id=>id.toString(16)+':Skyrim.esm',
    get: function (id, key) {
      const row = store[id] || {};
      return row[key];
    },
    set: function (id, key, v) {
      if (!store[id]) { store[id] = {}; }
      store[id][key] = v;
    },
    lookupEspmRecordById: function (baseId) {
      return records[baseId] || null;
    }
  };
  function addItem(actorId, desc, count) {
    given.push({ actorId: actorId, desc: desc, count: count });
    return true;
  }
  function addItemsAtomic(actorId,goods) {
    for(const good of goods) given.push({actorId,desc:good.item,count:good.count});
    return true;
  }
  function say(actorId, text) { said.push(String(text)); }
  const FakeDate = { now: function () { return clock; } };
  const fn = new Function(
    'globalThis', 'mp', 'console', 'idOf', 'addItem', 'say',
    'Math', 'Date', 'Number', 'String', 'Object', 'Array', 'RegExp',
    'require','createPrivateEconomyLedger','withinResourceReach','addItemsAtomic',
    block + '\nreturn globalThis.__thornswoodDungeonLoot;');
  const g = {};
  const api = fn(
    g, mp, { log: function () { } }, idOf, addItem, say,
    Math, FakeDate, Number, String, Object, Array, RegExp,
    require,()=>storage,()=>true,addItemsAtomic);
  api.given = given;
  api.said = said;
  api.idOf = idOf;
  api.clock = function (n) { if (n !== undefined) clock = n; return clock; }
  api.advance = function (ms) { clock += ms; };
  api.putActor = function (id, cell) {
    store[id] = { worldOrCellDesc: cell };
  };
  api.putChest = function (id, edid) {
    const desc = edid + ':Skyrim.esm';
    store[id] = { baseDesc: desc };
    records[idOf(desc)] = edidRecord(edid);
  };
  api.mark = function (id) { return (store[id] || {}).thornswoodDungeonLoot || 0; };
  return api;
}

if (block) {
  const api = rig();
  yes('Bleak Falls Temple is tier 1', api.tierOf('371de:Skyrim.esm') === 1);
  yes('the lookup ignores case', api.tierOf('371DE:Skyrim.esm') === 1);
  yes('Temple of Miraak is tier 4', api.tierOf('142f0:Dragonborn.esm') === 4);
  yes('a town temple is not a dungeon', api.tierOf('165a7:Skyrim.esm') === 0);
  yes('more than a hundred interiors are on the table', (function () {
    const n = (block.match(/': [1-4],/g) || []).length;
    return n > 100;
  })());

  yes('tier 1 tomes are novice only', api.ranksFor(1).join(',') === 'novice');
  yes('tier 2 stops at apprentice', api.ranksFor(2).join(',') === 'novice,apprentice');
  yes('tier 3 stops at adept', api.ranksFor(3).join(',') === 'novice,apprentice,adept');
  yes('tier 4 reaches master', api.ranksFor(4).indexOf('master') >= 0);

  const low = api.goodsFor(1).map(function (g) { return g.name; });
  yes('a tier 1 chest can hold a lockpick', low.indexOf('lockpick') >= 0);
  yes('a tier 1 chest cannot hold ebony', low.indexOf('ebony ingot') < 0);
  const high = api.goodsFor(4).map(function (g) { return g.name; });
  yes('a tier 4 chest can hold ebony', high.indexOf('ebony ingot') >= 0);

  const excl = api.exclusiveFor(4).map(function (g) { return g.name; });
  const goods = api.goodsFor(4).map(function (g) { return g.name; });
  yes('the exclusive list is not the ordinary pile', excl.every(function (n) {
    return goods.indexOf(n) < 0;
  }));
  yes('tier 1 exclusive is only the amulet', api.exclusiveFor(1).length === 1
    && api.exclusiveFor(1)[0].name === 'Ancient Nord Amulet');
  yes('a black soul gem waits for tier 4', api.exclusiveFor(3).every(function (g) {
    return g.name !== 'Black Soul Gem';
  }) && api.exclusiveFor(4).some(function (g) { return g.name === 'Black Soul Gem'; }));

  // rng order: gold, goods, goods, tome, rank, which, exclusive, which
  const amulet = api.roll(1, (function () {
    const seq = [0, 0.99, 0.99, 0.99, 0, 0];
    let i = 0;
    return function () { return seq[Math.min(i++, seq.length - 1)]; };
  })());
  yes('a quiet tier 1 roll is the minimum gold and the amulet',
    amulet.gold === 5 && amulet.items.length === 1
    && amulet.items[0].name === 'Ancient Nord Amulet');
  yes('the line names the gold and the amulet',
    api.heldLine(amulet) === 'The chest held 5 gold and an Ancient Nord Amulet.');

  const storm = api.roll(4, (function () {
    const seq = [0, 0.99, 0.99, 0, 0.95, 0, 0.99];
    let i = 0;
    return function () { return seq[Math.min(i++, seq.length - 1)]; };
  })());
  yes('a tier 4 roll can be a master tome',
    storm.gold === 50 && storm.items.length === 1
    && storm.items[0].name === 'Spell Tome: Fire Storm'
    && storm.items[0].rank === 'master');

  let noviceOnly = true;
  for (let n = 0; n < 80; n++) {
    const rolled = api.roll(1, Math.random);
    if (rolled.gold < 5 || rolled.gold > 15) noviceOnly = false;
    for (let k = 0; k < rolled.items.length; k++) {
      const it = rolled.items[k];
      if (it.rank && it.rank !== 'novice') noviceOnly = false;
      if (it.exclusive && it.name !== 'Ancient Nord Amulet') noviceOnly = false;
    }
  }
  yes('eighty tier 1 rolls stay in the novice band', noviceOnly);

  const actor = 1;
  const chest = 0x1000;
  const barrel = 0x1001;
  const made = 0xff000010;
  api.putActor(actor, '371de:Skyrim.esm');
  api.putChest(chest, 'TreasureChestLarge');
  api.putChest(barrel, 'BarrelEmpty');
  api.putChest(made, 'TreasureChestLarge');

  const paid = api.onChest(actor, chest);
  yes('opening a dungeon chest pays', paid && paid.gold >= 5);
  yes('the gold goes into the pack as coin', api.given.some(function (g) {
    return g.desc === 'f:Skyrim.esm' && g.count === paid.gold;
  }));
  yes('the chest says what it held', api.said.length === 1 && api.said[0].indexOf('The chest held ') === 0);
  yes('the chest remembers the pay', api.mark(chest) === api.clock());

  const before = api.given.length;
  yes('the same chest does not pay twice inside the rest', api.onChest(actor, chest) === null);
  yes('nothing else was handed over', api.given.length === before);

  api.advance(29 * 60 * 1000);
  yes('twenty nine minutes is still the same rest', api.onChest(actor, chest) === null);
  api.advance(2 * 60 * 1000);
  const again = api.onChest(actor, chest);
  yes('thirty minutes later the chest pays again', again && again.gold >= 5);

  const mid = api.given.length;
  yes('a barrel in the same place does not pay', api.onChest(actor, barrel) === null);
  yes('a container somebody placed does not pay', api.onChest(actor, made) === null);
  api.putActor(2, '165a7:Skyrim.esm');
  api.putChest(0x1002, 'TreasureChestLarge');
  yes('a chest in a temple that is not a dungeon does not pay', api.onChest(2, 0x1002) === null);
  yes('those three opens handed nothing', api.given.length === mid);

  const act = src.slice(src.indexOf('function activate(actorId, refrId, baseDesc)'),
                        src.indexOf('// ------------------------------------------------- where gold comes from --'));
  yes('opening a container asks the dungeon table',
    /dungeonLoot\.onChest\(actorId, refrId\)/.test(act));
}

console.log(pass + ' passed, ' + fail + ' failed');
if (fail) process.exit(1);
