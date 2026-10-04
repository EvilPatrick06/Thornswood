// test-1384-condition.js
//
// #1384. Condition runs from 0% to 120%. Three kits, and who makes them, are
// on docs/systems/durability.md: the half that makes the kit repairs to 120%
// and anybody else to 100%. At 0% a worn piece has a 10% chance to break on a
// hit, and a piece in a chest does not roll it. A piece in a shop chest or a
// house container loses 5% a real day; a pack does not, worn gear does not,
// and opening the chest does not reset the day. Tempering is not repair and
// is not counted as work (test-recipeless-craft.js drives the refusal; this
// checks it is wired). Glass, ebony and stalhrim take the same kits as iron.
//
// The durability block is cut out of the gamemode as it is and run against a
// small world: packs, chests, records and a clock this file controls.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const REPO_DIR = process.env.REPO_DIR || path.join(__dirname, '..');
const CR = String.fromCharCode(13);
const gm = fs.readFileSync(path.join(REPO_DIR, 'game', 'gamemode.js'), 'utf8').split(CR).join('');
const page = fs.readFileSync(path.join(REPO_DIR, 'docs', 'systems', 'durability.md'), 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function slice(src, start, end) {
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b + end.length);
}

const block = slice(gm, '// ==== thornswood durability ====', '// ==== end thornswood durability ====');
yes('the durability block is in the gamemode', block !== null);
const box = { console: { log: function () {} } };
box.globalThis = box;
if (block) {
  // Without mp the block stops after handing over the factory, which is all
  // this needs.
  vm.runInNewContext(block, box);
}
const create = box.__thornswoodDurabilityCreate;
const KITS = box.__thornswoodDurabilityKits;
yes('the block hands over its factory and its kits', typeof create === 'function' && !!KITS);
if (typeof create !== 'function') {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(1);
}

// ------------------------------------------------------------------ records --

function le32(n) { return [n & 255, (n >>> 8) & 255, (n >>> 16) & 255, (n >>> 24) & 255]; }
function text(s) { return s.split('').map(function (c) { return c.charCodeAt(0); }).concat([0]); }
function weapon(edid) { return { type: 'WEAP', fields: [{ type: 'EDID', data: text(edid) }] }; }
function armo(edid, slots, armourType, keywords) {
  const f = [{ type: 'EDID', data: text(edid) }, { type: 'BOD2', data: le32(slots).concat(le32(armourType)) }];
  if (keywords) { f.push({ type: 'KWDA', data: [].concat.apply([], keywords.map(le32)) }); }
  return { type: 'ARMO', fields: f };
}
const BODY = 1 << 2, HANDS = 1 << 3, RING = 1 << 6, AMULET = 1 << 5, HEAD = 1;

const IRON_SWORD = 0x12eb7, GLASS_SWORD = 0x139a0, EBONY_ARMOR = 0x13961, STALHRIM = 0x2b6a6;
const STEEL_ARMOR = 0x13952, LEATHER = 0x3619e, ROBES = 0x10cee3, GLOVES = 0x261c1;
const GOLD_RING = 0x1cf2b, AMULET_OF = 0x9171b, PLAIN_RING = 0x5000001;
const PICKAXE = 0xe3c16, BREAD = 0x65c97, ARROW = 0x1397d;
const WEAPON_KIT = 0x5100001, ARMOR_KIT = 0x5100002, SEWING_KIT = 0x5100003;

const RECORDS = {};
RECORDS[IRON_SWORD] = weapon('IronSword');
RECORDS[GLASS_SWORD] = weapon('GlassSword');
RECORDS[EBONY_ARMOR] = armo('ArmorEbonyCuirass', BODY, 1);
RECORDS[STALHRIM] = armo('DLC2ArmorStalhrimHeavyCuirass', BODY, 1);
RECORDS[STEEL_ARMOR] = armo('ArmorSteelCuirassA', BODY, 1);
RECORDS[LEATHER] = armo('ArmorLeatherCuirass', BODY, 0);
RECORDS[ROBES] = armo('ClothesMGRobesAdept', BODY, 2);
RECORDS[GLOVES] = armo('ClothesFineGloves', HANDS, 2);
RECORDS[GOLD_RING] = armo('JewelryRingGold', RING, 2, [0x6bbe9, 0x10cd09]);
RECORDS[AMULET_OF] = armo('AmuletMara', AMULET, 2, [0x8f95a]);
RECORDS[PLAIN_RING] = armo('ModRing', RING, 2);
RECORDS[PICKAXE] = weapon('Pickaxe');
RECORDS[BREAD] = { type: 'ALCH', fields: [] };
RECORDS[ARROW] = { type: 'AMMO', fields: [] };
[WEAPON_KIT, ARMOR_KIT, SEWING_KIT].forEach(function (k) { RECORDS[k] = { type: 'MISC', fields: [] }; });

const NAMES = {};
NAMES[IRON_SWORD] = 'Iron Sword'; NAMES[GLASS_SWORD] = 'Glass Sword';
NAMES[EBONY_ARMOR] = 'Ebony Armor'; NAMES[STALHRIM] = 'Stalhrim Armor';
NAMES[STEEL_ARMOR] = 'Steel Armor'; NAMES[ROBES] = 'Adept Robes'; NAMES[GLOVES] = 'Fine Gloves';

const KIT_DESC = { 'weapon-kit:Test.esp': WEAPON_KIT, 'armor-kit:Test.esp': ARMOR_KIT, 'sewing-kit:Test.esp': SEWING_KIT,
                   'iron-sword': IRON_SWORD };
function testKits(withItems) {
  const out = {};
  Object.keys(KITS).forEach(function (k) {
    const row = Object.assign({}, KITS[k]);
    if (withItems) {
      row.item = { weapon: 'weapon-kit:Test.esp', armour: 'armor-kit:Test.esp', clothing: 'sewing-kit:Test.esp' }[k];
    }
    out[k] = row;
  });
  return out;
}

// -------------------------------------------------------------------- world --

const PERSON = 0xff000058, OTHER = 0xff000059, NPC = 0x1a2b3, CHEST = 0x10ab1, CAVE_CHEST = 0x20cd2;
const DAY = 24 * 60 * 60 * 1000;

function world(opts) {
  opts = opts || {};
  const w = {
    t: opts.t || 1000000,
    packs: {}, worn: {}, held: {}, clocks: {}, states: {}, cells: {},
    rolls: (opts.rolls || []).slice(), said: [], logs: [], queue: [], writes: 0, refuseWrite: false
  };
  w.api = create({
    kits: testKits(opts.kitsMade !== false),
    now: function () { return w.t; },
    random: function () { return w.rolls.length ? w.rolls.shift() : 0.99; },
    later: function (fn) { w.queue.push(fn); },
    inventory: function (id) {
      return w.packs[id] ? w.packs[id].map(function (e) { return Object.assign({}, e); }) : null;
    },
    setInventory: function (id, entries) {
      if (w.refuseWrite) { return false; }
      w.writes++;
      w.packs[id] = entries.map(function (e) { return Object.assign({}, e); });
      return true;
    },
    worn: function (id) {
      if (w.worn[id]) { return w.worn[id]; }
      return (w.packs[id] || []).filter(function (e) { return e.worn || e.wornLeft; });
    },
    recordOf: function (id) { return RECORDS[id] || null; },
    nameOf: function (id) { return NAMES[id] || ''; },
    idOf: function (desc) { return KIT_DESC[desc] || (/^ff/.test(desc) ? parseInt(desc, 16) : 0) || Number(desc) || 0; },
    stateOf: function (id) { return w.states[id] || null; },
    isPerson: function (id) { return id >= 0xff000000; },
    isTool: function (id) { return id === PICKAXE; },
    held: function (id) { return !!w.held[id]; },
    isContainer: function (desc) { return desc === 'chest'; },
    cellOf: function (id) { return w.cells[id] || 'WhiterunBreezehome'; },
    clockOf: function (id) { return w.clocks[id] || null; },
    setClock: function (id, c) { if (c) { w.clocks[id] = Object.assign({}, c); } else { delete w.clocks[id]; } },
    say: function (id, m) { w.said.push(m); },
    log: function () { w.logs.push(Array.prototype.join.call(arguments, ' ')); }
  });
  w.flush = function () { const q = w.queue.splice(0); q.forEach(function (fn) { fn(); }); };
  w.count = function (id, baseId, name) {
    return (w.packs[id] || []).filter(function (e) {
      return e.baseId === baseId && (name === undefined || (e.name || '') === name);
    }).reduce(function (n, e) { return n + e.count; }, 0);
  };
  return w;
}
const D = world().api;

// ---------------------------------------------------------- the condition --

yes('a plain piece is at 100%', D.conditionOf({ baseId: IRON_SWORD, count: 1 }) === 100);
yes('the condition is the number on the end of the name',
    D.conditionOf({ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (85%)' }) === 85);
yes('it never reads past 120% or under 0%',
    D.conditionOf({ name: 'Iron Sword (180%)' }) === 120 && D.conditionOf({ name: 'Iron Sword (0%)' }) === 0);
yes('a name with a number in it that is not on the end is not a condition',
    D.conditionOf({ name: 'Sword (50%) of Fire' }) === 100);
yes('the page and the block agree on the ends: 0, 100 and 120',
    D.CONDITION.lowest === 0 && D.CONDITION.sound === 100 && D.CONDITION.highest === 120 &&
    /from 0% to 120%/.test(page));
{
  const at85 = D.withCondition({ baseId: IRON_SWORD, count: 2 }, 85);
  const back = D.withCondition(at85, 100);
  const named = D.withCondition({ baseId: GLASS_SWORD, count: 1, name: 'Shard of Morning' }, 40);
  yes('a piece below 100% says so in its name', at85.name === 'Iron Sword (85%)' && at85.count === 2);
  yes('back at 100% it is plain again, and stacks with plain ones', back.name === undefined);
  yes('a name somebody gave a piece is kept, with the condition after it',
      named.name === 'Shard of Morning (40%)' &&
      D.withCondition(named, 100).name === 'Shard of Morning');
}

// ---------------------------------------------------------- what has one --

yes('a weapon has a condition', D.pieceKind(IRON_SWORD) === 'weapon');
yes('heavy and light armour are armour',
    D.pieceKind(STEEL_ARMOR) === 'armour' && D.pieceKind(LEATHER) === 'armour');
yes('robes and gloves are clothing', D.pieceKind(ROBES) === 'clothing' && D.pieceKind(GLOVES) === 'clothing');
yes('a ring and an amulet are jewellery and have none, by keyword',
    D.pieceKind(GOLD_RING) === '' && D.pieceKind(AMULET_OF) === '');
yes('a ring a mod forgot to mark has none either, by its slot', D.pieceKind(PLAIN_RING) === '');
yes('the pickaxe wears by use and has no condition here', D.pieceKind(PICKAXE) === '');
yes('food, arrows and a kit have none',
    D.pieceKind(BREAD) === '' && D.pieceKind(ARROW) === '' && D.pieceKind(WEAPON_KIT) === '');
yes('a record that cannot be read has none', D.pieceKind(0x7777777) === '');
yes('glass, ebony and stalhrim are the same kinds as iron, so they take the same kits',
    D.pieceKind(GLASS_SWORD) === D.pieceKind(IRON_SWORD) &&
    D.pieceKind(EBONY_ARMOR) === 'armour' && D.pieceKind(STALHRIM) === 'armour');

// ---------------------------------------------------------- the kits -------

function pageKits() {
  const rows = {};
  page.split('\n').forEach(function (line) {
    const m = /^\| (Weapon Kit|Armor Kit|Sewing Kit) \| (\w+) \| (.+) \|$/.exec(line);
    if (m) { rows[m[1]] = m[2]; }
  });
  return rows;
}
{
  const rows = pageKits();
  yes('the three kits on the page are the three in the block, with the same makers',
      Object.keys(rows).length === 3 &&
      rows['Weapon Kit'] === KITS.weapon.maker && rows['Armor Kit'] === KITS.armour.maker &&
      rows['Sewing Kit'] === KITS.clothing.maker &&
      KITS.weapon.half === 'edgewright' && KITS.armour.half === 'platewright' &&
      KITS.clothing.half === 'haberdasher');
  yes('no kit has a record yet: the plugin does not carry one',
      KITS.weapon.item === null && KITS.armour.item === null && KITS.clothing.item === null);
}

const EDGE = { prof: 'smith', half: 'edgewright', ranks: { edgewright: 'novice', platewright: 'novice' } };
const PLATE = { prof: 'smith', half: 'platewright', ranks: { platewright: 'master', edgewright: 'novice' } };
const HABER = { prof: 'tailor', half: 'haberdasher', ranks: { haberdasher: 'novice' } };
const LIVERY = { prof: 'tailor', half: 'liverywright', ranks: { liverywright: 'master', haberdasher: 'novice' } };
const COOK = { prof: 'cook', half: 'hearthcook', ranks: { hearthcook: 'expert' } };

yes('the Edgewright mends with a Weapon Kit to 120%', D.repairTo(EDGE, 'weapon') === 120);
yes('the Platewright, the other half of the same profession, to 100%, even at master',
    D.repairTo(PLATE, 'weapon') === 100);
yes('the Platewright mends with an Armor Kit to 120%', D.repairTo(PLATE, 'armour') === 120);
yes('the Haberdasher mends with a Sewing Kit to 120%, the Liverywright to 100%',
    D.repairTo(HABER, 'clothing') === 120 && D.repairTo(LIVERY, 'clothing') === 100);
yes('anybody else, and somebody with no profession, to 100%',
    D.repairTo(COOK, 'weapon') === 100 && D.repairTo(null, 'armour') === 100 && D.repairTo({}, 'clothing') === 100);

// A repair, end to end.
{
  const w = world({ kitsMade: false });
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (40%)' }];
  w.states[PERSON] = EDGE;
  const r = w.api.repairWithKit(PERSON, 'iron sword');
  yes('with no kit record in the plugin, a repair is refused and says no kit has been made',
      !r.ok && /no Weapon Kit has been made/.test(r.line) && w.writes === 0);
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (40%)' }];
  w.states[PERSON] = EDGE;
  const r = w.api.repairWithKit(PERSON, 'iron sword');
  yes('without the kit in the pack it is refused, and says who makes them',
      !r.ok && /Weapon Kit, and you have none\. An Edgewright makes them\./.test(r.line) && w.writes === 0);
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (40%)' },
                     { baseId: WEAPON_KIT, count: 2 }];
  w.states[PERSON] = EDGE;
  const r = w.api.repairWithKit(PERSON, 'Iron Sword');
  yes('an Edgewright\'s Weapon Kit puts an iron sword at 120%',
      r.ok && r.to === 120 && r.from === 40 && w.count(PERSON, IRON_SWORD, 'Iron Sword (120%)') === 1 &&
      w.count(PERSON, IRON_SWORD, 'Iron Sword (40%)') === 0);
  yes('and uses up one kit', w.count(PERSON, WEAPON_KIT) === 1 && /Weapon Kit is used up/.test(r.line));
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (40%)' },
                     { baseId: IRON_SWORD, count: 2 },
                     { baseId: WEAPON_KIT, count: 1 }];
  w.states[PERSON] = PLATE;
  const r = w.api.repairWithKit(PERSON, 'iron');
  yes('a Platewright\'s repair with the same kit is 100%, and the sword stacks with the plain ones',
      r.ok && r.to === 100 && w.count(PERSON, IRON_SWORD, '') === 3 && w.packs[PERSON].length === 1);
  yes('and the last kit is gone from the pack', w.count(PERSON, WEAPON_KIT) === 0);
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (120%)' },
                     { baseId: WEAPON_KIT, count: 1 }];
  w.states[PERSON] = COOK;
  const r = w.api.repairWithKit(PERSON, 'iron sword');
  yes('a piece at 120% is not pulled down to 100% by somebody else\'s repair, and no kit is used',
      !r.ok && /at 120%/.test(r.line) && w.writes === 0);
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: GLASS_SWORD, count: 1, name: 'Glass Sword (75%)' },
                     { baseId: GLASS_SWORD, count: 2, name: 'Glass Sword (10%)' },
                     { baseId: WEAPON_KIT, count: 1 }];
  w.states[PERSON] = EDGE;
  const r = w.api.repairWithKit(PERSON, 'glass sword');
  yes('of several, the worst is mended first, one unit of the stack',
      r.ok && r.from === 10 && w.count(PERSON, GLASS_SWORD, 'Glass Sword (10%)') === 1 &&
      w.count(PERSON, GLASS_SWORD, 'Glass Sword (120%)') === 1 &&
      w.count(PERSON, GLASS_SWORD, 'Glass Sword (75%)') === 1);
  yes('a glass sword takes the Weapon Kit, the same as iron', r.kit === 'weapon');
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: EBONY_ARMOR, count: 1, name: 'Ebony Armor (30%)', worn: true },
                     { baseId: WEAPON_KIT, count: 3 }];
  w.states[PERSON] = PLATE;
  const r = w.api.repairWithKit(PERSON, 'ebony armor');
  yes('armour is not mended with a Weapon Kit', !r.ok && /Armor Kit, and you have none/.test(r.line) &&
      w.count(PERSON, WEAPON_KIT) === 3);
  w.packs[PERSON].push({ baseId: ARMOR_KIT, count: 1 });
  const r2 = w.api.repairWithKit(PERSON, 'ebony armor');
  const piece = w.packs[PERSON].filter(function (e) { return e.baseId === EBONY_ARMOR; })[0];
  yes('ebony takes the Armor Kit like iron, and the Platewright puts it at 120%',
      r2.ok && r2.to === 120 && piece && piece.name === 'Ebony Armor (120%)');
  yes('a worn piece mended stays worn', piece && piece.worn === true);
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: ROBES, count: 1, name: 'Adept Robes (55%)' },
                     { baseId: SEWING_KIT, count: 1 }];
  w.states[PERSON] = LIVERY;
  const r = w.api.repairWithKit(PERSON, 'robes');
  yes('robes take the Sewing Kit; the Liverywright mends them to 100%',
      r.ok && r.kit === 'clothing' && r.to === 100 && w.count(PERSON, ROBES, '') === 1);
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (40%)' },
                     { baseId: WEAPON_KIT, count: 1 }];
  w.states[PERSON] = EDGE;
  w.refuseWrite = true;
  const r = w.api.repairWithKit(PERSON, 'iron sword');
  yes('a repair that cannot be written takes nothing and says so',
      !r.ok && /Nothing was used/.test(r.line) && w.count(PERSON, WEAPON_KIT) === 1);
  w.refuseWrite = false;
  const r2 = w.api.repairWithKit(PERSON, 'gold ring');
  yes('a ring is not something a kit mends', !r2.ok && /not carrying a weapon, armour or clothing called/.test(r2.line));
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 2, name: 'Iron Sword (40%)' },
                     { baseId: STEEL_ARMOR, count: 1 },
                     { baseId: ROBES, count: 1, name: 'Adept Robes (120%)' },
                     { baseId: GOLD_RING, count: 1 },
                     { baseId: WEAPON_KIT, count: 2 }];
  const line = w.api.command(PERSON, '');
  yes('/repair on its own lists what is not at 100%, worst first, and the kits carried',
      line.indexOf('Iron Sword 40% (2), Adept Robes 120%.') === 0 &&
      /1 more piece is at 100%/.test(line) && /Kits: 2 Weapon Kits\./.test(line) && line.indexOf('Gold') === -1);
}

// ---------------------------------------------------------- the dull clock --

function stocked(w) {
  w.held[CHEST] = true;
  w.packs[CHEST] = [{ baseId: IRON_SWORD, count: 3 },
                    { baseId: STEEL_ARMOR, count: 1, name: 'Steel Armor (120%)' },
                    { baseId: ROBES, count: 1, name: 'Adept Robes (3%)' },
                    { baseId: GLOVES, count: 1, name: 'Fine Gloves (0%)' },
                    { baseId: BREAD, count: 4 },
                    { baseId: GOLD_RING, count: 1 }];
}
{
  const w = world();
  stocked(w);
  w.api.pressed(PERSON, CHEST, 'chest');
  yes('the first opening of a stocked chest in a held building starts its clock and takes nothing',
      !!w.clocks[CHEST] && w.clocks[CHEST].at === w.t && w.writes === 0);
  const started = w.clocks[CHEST].at;
  w.t += DAY - 1000;
  w.api.pressed(PERSON, CHEST, 'chest');
  yes('before a whole day has turned, nothing is lost', w.writes === 0);
  w.t += 2000;
  w.api.pressed(PERSON, CHEST, 'chest');
  yes('a day on, every piece in it loses 5%',
      w.count(CHEST, IRON_SWORD, 'Iron Sword (95%)') === 3 &&
      w.count(CHEST, STEEL_ARMOR, 'Steel Armor (115%)') === 1);
  yes('a piece never goes under 0%', w.count(CHEST, ROBES, 'Adept Robes (0%)') === 1 &&
      w.count(CHEST, GLOVES, 'Fine Gloves (0%)') === 1);
  yes('food and a ring in the chest are not touched',
      w.count(CHEST, BREAD, '') === 4 && w.count(CHEST, GOLD_RING, '') === 1);
  const writes = w.writes;
  w.api.pressed(PERSON, CHEST, 'chest');
  w.api.pressed(OTHER, CHEST, 'chest');
  yes('opening it again the same day takes nothing more', w.writes === writes &&
      w.count(CHEST, IRON_SWORD, 'Iron Sword (95%)') === 3);
  yes('and opening it never moves the clock, so the day is not reset', w.clocks[CHEST].at === started);
  // Taken out and put back inside the day: the chest's day still turns on it.
  w.packs[CHEST] = w.packs[CHEST].filter(function (e) { return e.baseId !== IRON_SWORD; });
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 3, name: 'Iron Sword (95%)' }];
  w.t += DAY / 2;
  w.api.pressed(PERSON, CHEST, 'chest');
  w.packs[CHEST].push(w.packs[PERSON].pop());
  w.t += DAY / 2 + 1000;
  w.api.pressed(PERSON, CHEST, 'chest');
  yes('taking a piece out and putting it back does not reset its day either',
      w.count(CHEST, IRON_SWORD, 'Iron Sword (90%)') === 3);
  w.t += 3 * DAY;
  w.api.pressed(PERSON, CHEST, 'chest');
  yes('three days left alone are three times 5%, applied at the next opening',
      w.count(CHEST, IRON_SWORD, 'Iron Sword (75%)') === 3 && w.count(CHEST, STEEL_ARMOR, 'Steel Armor (95%)') === 1);
  w.t += 40 * DAY;
  w.api.pressed(PERSON, CHEST, 'chest');
  yes('and a chest left long enough holds pieces at 0%, no lower', w.count(CHEST, IRON_SWORD, 'Iron Sword (0%)') === 3);
  yes('the page and the block agree: 5% a real day', w.api.DULL_PER_DAY === 5 && w.api.DAY_MS === DAY &&
      /5% per real day/.test(page));
}
{
  const w = world();
  stocked(w);
  w.held[CHEST] = false;
  w.packs[CAVE_CHEST] = w.packs[CHEST];
  w.api.pressed(PERSON, CAVE_CHEST, 'chest');
  w.t += 10 * DAY;
  w.api.pressed(PERSON, CAVE_CHEST, 'chest');
  yes('a chest in no held building has no clock and never dulls', !w.clocks[CAVE_CHEST] && w.writes === 0);
}
{
  const w = world();
  stocked(w);
  w.api.pressed(PERSON, CHEST, 'chest');
  w.held[CHEST] = false;
  w.t += 5 * DAY;
  w.api.pressed(PERSON, CHEST, 'chest');
  yes('when the claim on the building lapses the chest\'s clock goes with it', !w.clocks[CHEST] && w.writes === 0);
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (60%)' },
                     { baseId: STEEL_ARMOR, count: 1, name: 'Steel Armor (60%)', worn: true }];
  w.api.pressed(PERSON, 0x33333, 'a door');
  w.t += 30 * DAY;
  w.api.pressed(PERSON, 0x33333, 'a door');
  w.api.hit(OTHER, PERSON, 0);
  yes('a pack does not dull, and worn gear does not dull on the clock',
      w.writes === 0 && w.count(PERSON, IRON_SWORD, 'Iron Sword (60%)') === 1 &&
      w.count(PERSON, STEEL_ARMOR, 'Steel Armor (60%)') === 1);
}
{
  const w = world();
  w.held[CHEST] = true;
  w.packs[CHEST] = [{ baseId: IRON_SWORD, count: 1 }];
  w.api.pressed(PERSON, CHEST, 'chest');
  w.t += 2 * DAY;
  w.refuseWrite = true;
  w.api.pressed(PERSON, CHEST, 'chest');
  yes('a dull that cannot be written leaves the clock where it was', w.clocks[CHEST].days === 0);
  w.refuseWrite = false;
  w.api.pressed(PERSON, CHEST, 'chest');
  yes('and the next opening takes the whole of it', w.count(CHEST, IRON_SWORD, 'Iron Sword (90%)') === 1);
}

// ---------------------------------------------------------- the break chance --

yes('the page and the block agree: a 10% chance at 0%', w0BreakChance() === 0.10 && /10% chance to break on a hit/.test(page));
function w0BreakChance() { return D.BREAK_CHANCE; }
{
  const w = world({ rolls: [0.05] });
  w.packs[PERSON] = [{ baseId: STEEL_ARMOR, count: 1, name: 'Steel Armor (0%)', worn: true },
                     { baseId: IRON_SWORD, count: 1 }];
  const gone = w.api.hit(PERSON, NPC, IRON_SWORD);
  yes('worn armour at 0% breaks on a hit when the roll is under 10%',
      gone.length === 1 && w.count(PERSON, STEEL_ARMOR) === 0 && /Steel Armor broke/.test(w.said[0]));
}
{
  const w = world({ rolls: [0.5, 0.5, 0.5] });
  w.packs[PERSON] = [{ baseId: STEEL_ARMOR, count: 1, name: 'Steel Armor (0%)', worn: true }];
  w.api.hit(PERSON, NPC, IRON_SWORD);
  yes('and holds when it is not', w.count(PERSON, STEEL_ARMOR) === 1 && w.writes === 0);
}
{
  const w = world({ rolls: [0, 0, 0, 0] });
  w.packs[PERSON] = [{ baseId: STEEL_ARMOR, count: 1, name: 'Steel Armor (1%)', worn: true },
                     { baseId: ROBES, count: 1, name: 'Adept Robes (0%)' }];
  w.api.hit(PERSON, NPC, IRON_SWORD);
  yes('a worn piece above 0% never breaks, and a piece at 0% in the pack and not worn never rolls',
      w.writes === 0 && w.rolls.length === 4);
}
{
  const w = world({ rolls: [0, 0] });
  w.packs[CHEST] = [{ baseId: STEEL_ARMOR, count: 1, name: 'Steel Armor (0%)' }];
  w.held[CHEST] = true;
  w.api.hit(CHEST, PERSON, 0);
  yes('a piece at 0% sitting in a chest does not roll', w.count(CHEST, STEEL_ARMOR) === 1 && w.rolls.length === 2);
}
{
  const w = world({ rolls: [0.01, 0.01] });
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (0%)', worn: true }];
  w.packs[OTHER] = [{ baseId: GLASS_SWORD, count: 1, name: 'Glass Sword (0%)', worn: true }];
  w.api.hit(OTHER, PERSON, IRON_SWORD);
  yes('the weapon a hit is landed with rolls, at 0%', w.count(PERSON, IRON_SWORD) === 0);
  yes('the weapon of the person hit does not', w.count(OTHER, GLASS_SWORD) === 1);
}
{
  const w = world({ rolls: [0, 0] });
  w.packs[NPC] = [{ baseId: STEEL_ARMOR, count: 1, name: 'Steel Armor (0%)', worn: true }];
  w.api.hit(NPC, PERSON, 0);
  yes('only people\'s gear rolls', w.count(NPC, STEEL_ARMOR) === 1);
}
{
  const w = world({ rolls: [0.02] });
  w.packs[PERSON] = [{ baseId: STEEL_ARMOR, count: 1 },
                     { baseId: STEEL_ARMOR, count: 1, name: 'Steel Armor (0%)', worn: true }];
  // The equipment names the base and says nothing of the name.
  w.worn[PERSON] = [{ baseId: STEEL_ARMOR, count: 1, worn: true }];
  w.api.hit(PERSON, NPC, 0);
  yes('worn read off the equipment is matched to the stack the pack has worn',
      w.count(PERSON, STEEL_ARMOR, '') === 1 && w.count(PERSON, STEEL_ARMOR, 'Steel Armor (0%)') === 0);
}

{
  const w = world({ rolls: [0.01] });
  w.packs[OTHER] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (0%)', worn: true }];
  w.api.onHit(PERSON, { type: 'form', desc: 'ff000059' }, { type: 'espm', desc: 'iron-sword' });
  yes('a hit as the engine sends it, the aggressor and weapon as descriptors, is read the same way',
      w.count(OTHER, IRON_SWORD) === 0);
}

// ---------------------------------------------------------- a drop ---------

const DROPPED = 0xff00a001;
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (40%)' }];
  w.api.dropped(PERSON, IRON_SWORD, 1);
  w.packs[PERSON] = [];
  w.cells[DROPPED] = 'WhiterunBreezehome';
  w.packs[OTHER] = [{ baseId: IRON_SWORD, count: 1 }];
  w.api.pressed(OTHER, DROPPED, 'iron-sword');
  w.packs[OTHER] = [{ baseId: IRON_SWORD, count: 2 }];
  w.flush();
  yes('a piece dropped at 40% and picked up again is at 40%, not 100%',
      w.count(OTHER, IRON_SWORD, 'Iron Sword (40%)') === 1 && w.count(OTHER, IRON_SWORD, '') === 1);
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (40%)' },
                     { baseId: IRON_SWORD, count: 1, name: 'Iron Sword (90%)' }];
  w.api.dropped(PERSON, IRON_SWORD, 1);
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (40%)' }];
  w.flush();
  w.api.pressed(PERSON, DROPPED, 'iron-sword');
  w.packs[PERSON].push({ baseId: IRON_SWORD, count: 1 });
  w.flush();
  yes('of two conditions, the one that went down is the one that comes back',
      w.count(PERSON, IRON_SWORD, 'Iron Sword (90%)') === 1 && w.count(PERSON, IRON_SWORD, '') === 0);
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (40%)' }];
  w.api.dropped(PERSON, IRON_SWORD, 1);
  w.cells[DROPPED] = 'SomewhereElse';
  w.packs[OTHER] = [];
  w.api.pressed(OTHER, DROPPED, 'iron-sword');
  w.packs[OTHER] = [{ baseId: IRON_SWORD, count: 1 }];
  w.flush();
  yes('a sword picked up in another place is not matched to it', w.count(OTHER, IRON_SWORD, '') === 1);
  w.cells[DROPPED] = 'WhiterunBreezehome';
  w.t += 4 * 60 * 1000;
  w.api.pressed(OTHER, DROPPED, 'iron-sword');
  w.packs[OTHER] = [{ baseId: IRON_SWORD, count: 2 }];
  w.flush();
  yes('and the drop is forgotten once the engine has cleared the ground', w.count(OTHER, IRON_SWORD, '') === 2);
}
{
  const w = world();
  w.packs[PERSON] = [{ baseId: IRON_SWORD, count: 1, name: 'Iron Sword (40%)' }];
  w.api.dropped(PERSON, IRON_SWORD, 1);
  w.packs[OTHER] = [{ baseId: IRON_SWORD, count: 1 }];
  w.api.pressed(OTHER, DROPPED, 'iron-sword');
  w.flush();
  yes('a pickup that added nothing leaves a plain sword already in the pack alone',
      w.count(OTHER, IRON_SWORD, '') === 1 && w.writes === 0);
}

// ---------------------------------------------------------- the wiring ------

const code = gm.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
function between(src, start, end) { return slice(src, start, end) || ''; }
const onActivate = between(code, "mp.onActivate = guard('onActivate'", '\n});');
const onDrop = between(code, "mp.onDropItem = guard('onDropItem'", '\n});');
const recipeless = between(code, 'function recipelessCraft(actorId, craftedItemBaseId, workbenchId, effects) {', '\n}\n');
yes('a press reaches the durability block, after the box is remembered',
    /wear\.pressed\(casterRefrId, refrId, baseDesc\)/.test(onActivate) &&
    onActivate.indexOf('touchedBox(casterRefrId, refrId)') < onActivate.indexOf('wear.pressed('));
yes('a drop reaches it, and the drop watcher still returns nothing',
    /wear\.dropped\(actorId, Number\(baseId\) \|\| 0, count\)/.test(onDrop) && !/\breturn\b/.test(onDrop));
const onHitLines = gm.split('\n').filter(function (l) { return /^mp\['onPapyrusEvent:OnHit'\] = guard\('onPapyrusEvent:OnHit', function/.test(l); });
yes('a hit reaches it through the one OnHit handler, under guard(), beside the warrior maneuvers',
    onHitLines.length === 1 &&
    /wear\.onHit\(targetId, aggressor, source\)/.test(between(code, "mp['onPapyrusEvent:OnHit']", '\n});')));
const temper = recipeless.indexOf('if (tempering) {');
yes('a temper at the wheel or the armour table is refused before anything is credited',
    temper !== -1 && /if \(tempering\) \{[\s\S]*?return false;\s*\}/.test(recipeless) &&
    (recipeless.indexOf('credit') === -1 || recipeless.indexOf('credit') > temper));
const wordsLine = /^const WORDS = (\[[\s\S]*?\]);$/m.exec(gm);
const playerLine = /^const PLAYER_WORDS = (\[[\s\S]*?\]);$/m.exec(gm);
let WORDS = [], PLAYER = [];
try { WORDS = new Function('return ' + wordsLine[1])(); PLAYER = new Function('return ' + playerLine[1])(); } catch (e) { }
yes('/repair is a word the server answers, and everybody is told about it',
    WORDS.indexOf('/repair') !== -1 && PLAYER.indexOf('/repair') !== -1 &&
    /if \(word === '\/repair'\) \{[\s\S]*?wear\.command\(actorId, parts\.slice\(1\)\.join\(' '\)\)/.test(code));
yes('the cut list still holds the temper rows, so an event can bring one back',
    /Tempering rows, the grindstone and the armour table, are in this file/.test(
      fs.readFileSync(path.join(REPO_DIR, 'docs', 'systems', 'cut-items.md'), 'utf8')));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
