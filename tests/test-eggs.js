// test-eggs.js
//
// #628: a chicken nest is the farmer's; a gatherer must not get the egg.
//
// ChickenNest stayed in HARVESTS_BY_BASE because Chicken's Egg is an INGR,
// and the food rule only pulled ALCH food. plantAt refuses the nest; collectEgg
// answers it for a farmer. Wild bird eggs stay on the gatherer ladder.
//
// Read only against game/gamemode.js.
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(__dirname, '..', 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function liftFn(name) {
  const a = src.indexOf('\nfunction ' + name + '(');
  if (a < 0) { return null; }
  const open = src.indexOf('{', a);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') { depth++; }
    else if (src[i] === '}') { depth--; if (!depth) { return src.slice(a + 1, i + 1); } }
  }
  return null;
}

function liftHandler() {
  const head = "mp.onActivate = guard('onActivate', function (refrId, casterRefrId) {";
  const a = src.indexOf(head);
  if (a < 0) { return null; }
  const f = a + head.indexOf('function');
  const open = src.indexOf('{', f);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') { depth++; }
    else if (src[i] === '}') { depth--; if (!depth) { return src.slice(f, i + 1); } }
  }
  return null;
}

function constLine(name) {
  const m = new RegExp('^const ' + name + ' = [^;\\n]*;', 'm').exec(src);
  return m ? m[0] : null;
}

function constBlock(name) {
  const a = src.indexOf('\nconst ' + name + ' = {');
  if (a < 0) { return null; }
  const open = src.indexOf('{', a);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') { depth++; }
    else if (src[i] === '}') {
      depth--;
      if (!depth) {
        const end = src.indexOf(';', i);
        return src.slice(a + 1, end + 1);
      }
    }
  }
  return null;
}

function coolBlock() {
  const a = src.indexOf('\nconst COOLDOWN_MS = ');
  const s = liftFn('stampCooldown');
  if (a < 0 || !s) { return null; }
  const b = src.indexOf(s, a);
  return b < 0 ? null : src.slice(a + 1, b + s.length);
}

const NEST = '1062d1:Skyrim.esm';
const EGG = '23d77:Skyrim.esm';
const FLOWER = '134aa:Skyrim.esm'; // not a nest

const itemsLine = constLine('ITEMS');
let ITEMS = {};
try { ITEMS = JSON.parse(/^const ITEMS = (\{.*\});$/.exec(itemsLine)[1]); } catch (e) { ITEMS = {}; }
yes('ITEMS carries Chicken\'s Egg as chickenEgg, 23d77:Skyrim.esm', ITEMS.chickenEgg === EGG);

const parts = {
  nestsLine: constBlock('CHICKEN_NESTS'),
  waitLine: constLine('HARVEST_COOLDOWN_MS'),
  coolBlock: coolBlock(),
  isChickenNest: liftFn('isChickenNest'),
  collectEgg: liftFn('collectEgg'),
  plantAt: liftFn('plantAt'),
  waitWord: liftFn('waitWord'),
  handler: liftHandler()
};
yes('collectEgg() is in the gamemode', !!parts.collectEgg);
yes('and isChickenNest() and CHICKEN_NESTS beside it', !!parts.isChickenNest && !!parts.nestsLine);
yes('the nest waits HARVEST_COOLDOWN_MS',
    !!parts.collectEgg && /cooldownLeft\(actorId, refrId, HARVEST_COOLDOWN_MS\)/.test(parts.collectEgg) &&
    !!parts.waitLine);
yes('collectEgg logs the nest press for the #628 measurement',
    !!parts.collectEgg && /egg: chicken nest press/.test(parts.collectEgg));
yes('a non-farmer gets a refusal string, not null (FLOR must not fall through)',
    !!parts.collectEgg && /if \(refusal\) return refusal;/.test(parts.collectEgg));
yes('success toast starts with You take so putBack leaves the nest empty',
    !!parts.collectEgg && /You take 1 Chicken's Egg/.test(parts.collectEgg));
yes('plantAt refuses a chicken nest',
    !!parts.plantAt && /isChickenNest\(baseDesc\)\) return null/.test(parts.plantAt));
yes('the activate handler calls collectEgg before the plants',
    !!parts.handler && /isChickenNest\(baseDesc\)/.test(parts.handler) &&
    parts.handler.indexOf('collectEgg(') < parts.handler.indexOf('isPlant(baseDesc)'));
yes('and puts the nest back only when floraHanded says no',
    !!parts.handler && /collectEgg\(/.test(parts.handler) &&
    /!floraHanded\(message\)/.test(parts.handler.slice(parts.handler.indexOf('collectEgg('),
      parts.handler.indexOf('isChurn(baseDesc)'))));

const FARMER = 0x14a, GATHERER = 0x14b, NOCLASS = 0x14c, FARMER2 = 0x14d;
const FARM_NO = 'Only a farmer can bring a crop in. Ask one.';
const NO_CLASS = 'You have not chosen a class yet. Press K and choose one.';

function world(opts) {
  const o = opts || {};
  const clock = { now: 1700000000000 };
  const rec = { gates: [], given: [], credited: [], putBack: [], told: [], branch: [], logs: [] };
  const bases = o.bases || {};
  const classGate = function (actorId, verb) {
    rec.gates.push(verb);
    if (actorId === FARMER || actorId === FARMER2) { return null; }
    if (actorId === NOCLASS) { return NO_CLASS; }
    return FARM_NO;
  };
  const addItem = function (actorId, desc, n) {
    if (o.unloadable) { return false; }
    rec.given.push({ actorId: actorId, desc: desc, n: n });
    return true;
  };
  const creditWork = function (actorId, key) { rec.credited.push(key); return o.rankLine || null; };
  const putBack = function (actorId, refrId) { rec.putBack.push({ actorId: actorId, refrId: refrId }); };
  const mp = {
    get: function (id, key) {
      if (key === 'baseDesc') {
        if (!Object.prototype.hasOwnProperty.call(bases, id)) { throw new Error('no such reference'); }
        return bases[id];
      }
      return null;
    },
    getDescFromId: function () { return null; }
  };
  const tag = function (name) {
    return function () { rec.branch.push(name); return 'answered by ' + name; };
  };
  const never = function () { return false; };
  const loot = function () { rec.branch.push('loot'); return null; };
  const names = ['classGate', 'addItem', 'creditWork', 'putBack', 'Date', 'benchGate',
    'notify', 'say', 'globalThis', 'mp', 'kindIsContainer', 'STATIONS', 'mineSalt',
    'burnCharcoal', 'isChoppingBlock', 'chopWood', 'SHRINES', 'bless', 'isCrop',
    'farmActivate', 'isFish', 'fish', 'isGame', 'game', 'isPlant', 'harvest', 'ALLOW',
    'isVein', 'mineOre', 'loot', 'milk', 'log', 'ITEMS', 'floraHanded', 'isChurn', 'churn',
    'HARVESTS_BY_BASE', 'HARVESTS', 'isStation'];
  const body = "'use strict';\n" +
    [parts.coolBlock, parts.waitLine, parts.nestsLine,
     parts.waitWord, parts.isChickenNest, parts.collectEgg, parts.plantAt].filter(Boolean).join('\n') + '\n' +
    'const onActivate = ' + (parts.handler || 'null') + ';\n' +
    'return { collectEgg: typeof collectEgg === "function" ? collectEgg : null,\n' +
    '         isChickenNest: typeof isChickenNest === "function" ? isChickenNest : null,\n' +
    '         plantAt: typeof plantAt === "function" ? plantAt : null,\n' +
    '         onActivate: onActivate };';
  let api = null;
  try {
    api = new Function(names.join(','), body).apply(null, [
      classGate, addItem, creditWork, putBack, { now: function () { return clock.now; } },
      function () { return null; },
      function (id, text) { rec.told.push(text); },
      function () { },
      {},
      mp, never, {},
      tag('mineSalt'), tag('burnCharcoal'), never, tag('chopWood'), {}, tag('bless'),
      never, tag('farmActivate'),
      never, tag('fish'), never, tag('game'),
      function (d) { return d === FLOWER; }, tag('harvest'),
      { thornswoodAllow: true }, never, tag('mineOre'), loot,
      function () { return null; },
      function () { rec.logs.push(Array.prototype.slice.call(arguments).join(' ')); },
      ITEMS,
      function (message) {
        return typeof message === 'string' && /^(You pick |You take )/.test(message);
      },
      never, function () { return null; },
      { '1062d1:Skyrim.esm': { produce: EGG, name: "Chicken's Egg", rank: 'advanced' } },
      {},
      never
    ]);
  } catch (e) {
    console.log('      the world would not build: ' + e.message);
    api = null;
  }
  return { api: api, rec: rec, clock: clock };
}

{
  const w = world();
  yes('collectEgg and the handler compile together', !!w.api && typeof w.api.onActivate === 'function');
  const collectEgg = w.api && w.api.collectEgg;
  const isChickenNest = w.api && w.api.isChickenNest;
  const plantAt = w.api && w.api.plantAt;
  const REF = 0xB001;

  if (isChickenNest) {
    yes('isChickenNest is true for ChickenNest and false for a flower and __proto__',
        isChickenNest(NEST) === true && isChickenNest(FLOWER) === false &&
        isChickenNest('__proto__') === false);
  }
  if (plantAt) {
    yes('plantAt returns null for the chicken nest so harvest never sees it',
        plantAt(NEST) === null);
  }

  if (collectEgg) {
    const first = collectEgg(FARMER, REF, NEST);
    yes('a farmer at the nest is told they took one Chicken\'s Egg',
        first === "You take 1 Chicken's Egg.");
    yes('and is handed exactly one of 23d77:Skyrim.esm', w.rec.given.length === 1 &&
        w.rec.given[0].actorId === FARMER && w.rec.given[0].desc === EGG && w.rec.given[0].n === 1);
    yes('the gate asked was the farm verb', w.rec.gates.length === 1 && w.rec.gates[0] === 'farm');
    yes('and the work is counted under the farm verb', w.rec.credited.join() === 'farm');
    yes('the nest press was logged', w.rec.logs.some(function (l) { return /egg: chicken nest press/.test(l); }));

    w.clock.now += 60000;
    const again = collectEgg(FARMER, REF, NEST);
    yes('the same farmer a minute later is told how long is left',
        again === 'You have taken from this nest for now. 9 minutes to go.');
    yes('and gets nothing more', w.rec.given.length === 1);

    const gather = collectEgg(GATHERER, REF + 1, NEST);
    yes('a gatherer is refused with the farm gate sentence', gather === FARM_NO);
    yes('and is handed nothing', w.rec.given.length === 1);

    const none = collectEgg(NOCLASS, REF + 2, NEST);
    yes('somebody with no class is refused', none === NO_CLASS);

    yes('a flower is not a nest, so collectEgg answers null',
        collectEgg(FARMER, REF + 3, FLOWER) === null);

    const other = collectEgg(FARMER2, REF, NEST);
    yes('a second farmer is not held by the first one\'s wait',
        other === "You take 1 Chicken's Egg." && w.rec.given.length === 2);
  }
}

// onActivate: farmer nest success empties (no putBack); gatherer putBack
{
  const REF = 0xC010;
  const w = world({ bases: { [REF]: NEST } });
  if (w.api && w.api.onActivate) {
    const ans = w.api.onActivate(REF, FARMER);
    yes('onActivate on a nest for a farmer returns false (blocks the engine)', ans === false);
    yes('and tells them they took the egg', w.rec.told.some(function (t) {
      return t === "You take 1 Chicken's Egg.";
    }));
    yes('and does not put the nest back after a real take', w.rec.putBack.length === 0);
    yes('and handed one egg', w.rec.given.length === 1 && w.rec.given[0].desc === EGG);
  }
}
{
  const REF = 0xC011;
  const w = world({ bases: { [REF]: NEST } });
  if (w.api && w.api.onActivate) {
    w.api.onActivate(REF, GATHERER);
    yes('onActivate on a nest for a gatherer puts the nest back',
        w.rec.putBack.length === 1 && w.rec.putBack[0].refrId === REF);
    yes('and hands them nothing', w.rec.given.length === 0);
    yes('and tells them the farm gate sentence', w.rec.told.indexOf(FARM_NO) >= 0);
  }
}

// Nest still listed in harvests.json (generated) but plantAt is the live gate
{
  const hv = path.join(path.dirname(SRC), 'data', 'harvests.json');
  if (fs.existsSync(hv)) {
    const h = JSON.parse(fs.readFileSync(hv, 'utf8'));
    const plants = h.plants || h;
    // plants map may be under a key; also check generated block presence in src
    yes('ChickenNest is still in the generated HARVESTS_BY_BASE (pass has not moved it)',
        /"1062d1:Skyrim.esm"/.test(src) && /Chicken's Egg/.test(src));
    yes('and plantAt is what keeps the gatherer off it',
        /isChickenNest\(baseDesc\)\) return null/.test(src));
  } else {
    yes('game/data/harvests.json is there', false);
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
