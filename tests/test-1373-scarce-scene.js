'use strict';
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.join(__dirname, '..');
const gmPath = path.join(root, 'game', 'gamemode.js');
const pagePath = path.join(root, 'docs', 'systems', 'quests.md');
const gm = fs.readFileSync(gmPath, 'utf8').replace(/\r/g, '');
const page = fs.readFileSync(pagePath, 'utf8').replace(/\r/g, '');
const startMark = '// ==== thornswood custom quests ====';
const endMark = '// ==== end thornswood custom quests ====';
const start = gm.indexOf(startMark);
const end = gm.indexOf(endMark);
if (start < 0 || end < 0 || end < start) {
  console.log('FAIL custom quest block is not in gamemode.js');
  process.exit(1);
}

function firstNumber(text) {
  const found = String(text).match(/(\d+)/);
  return found ? Number(found[1]) : null;
}
function hoursOf(text) {
  const found = String(text).match(/(\d+)\s+hours?/);
  return found ? Number(found[1]) : null;
}
function tables(md) {
  let mode = null;
  const scarce = [];
  const scene = [];
  md.split('\n').forEach(function (line) {
    if (line.indexOf('| Quest | Who |') === 0) mode = 'scarce';
    else if (line.indexOf('| Quest | What the server checks |') === 0) mode = 'scene';
    else if (line.indexOf('|') !== 0) mode = null;
    else if (line.indexOf('| ---') === 0) return;
    else if (mode) {
      const cells = line.split('|').slice(1, -1).map(function (cell) { return cell.trim(); });
      (mode === 'scarce' ? scarce : scene).push(cells);
    }
  });
  return { scarce: scarce, scene: scene };
}
function killCount(check) {
  if (!/^You kill/i.test(check)) return 0;
  return /three/i.test(check) ? 3 : 1;
}
function killMatch(check) {
  if (check.indexOf('sabre cat') >= 0) return 'sabre cat';
  if (check.indexOf('bandit') >= 0) return 'bandit';
  if (check.indexOf('draugr') >= 0) return 'draugr';
  if (check.indexOf('wolf') >= 0) return 'wolf';
  if (check.indexOf('bear') >= 0) return 'bear';
  if (check.indexOf('giant') >= 0) return 'giant';
  return null;
}

const doc = tables(page);
assert.equal(doc.scarce.length, 10, 'scarce table');
assert.equal(doc.scene.length, 13, 'scene table');

const block = gm.slice(start, end + endMark.length);
const ctx = {
  console: console, Map: Map, Set: Set, Date: Date, Math: Math, Number: Number,
  String: String, Buffer: Buffer, JSON: JSON, Object: Object, Array: Array,
  RegExp: RegExp, Error: Error
};
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(block, ctx);
const create = ctx.__thornswoodCustomQuestsCreate;
assert.equal(typeof create, 'function');

const docNames = doc.scarce.map(function (row) { return row[0]; })
  .concat(doc.scene.map(function (row) { return row[0]; }));
assert.ok(docNames.indexOf('Supply') < 0 && docNames.indexOf('A dragon') < 0);

function world(ranks) {
  const inv = new Map();
  const adds = [];
  let purseTouches = 0;
  const purse = { touch: function () { purseTouches++; throw new Error('purse'); } };
  // Each person's quests are kept on the character (#1621).
  const kept = new Map();
  const svc = create({
    now: function () { return clock; },
    goldDesc: 'f:Skyrim.esm',
    load: function (actor) { return kept.has(actor) ? JSON.parse(kept.get(actor)) : undefined; },
    save: function (actor, rec) { kept.set(actor, JSON.stringify(rec)); },
    identity: function (actor) {return 'actor:'+actor;},
    commit: function (actor, expected, next, changes) {
      assert.deepEqual(kept.has(actor)?JSON.parse(kept.get(actor)):null,expected);
      const pack=new Map(inv);
      for (const change of changes) {
        const key=actor+'|'+change.item,count=(pack.get(key)||0)+change.count;
        if(count<0)return {ok:false};
        pack.set(key,count);
      }
      for (const [key,count] of pack) inv.set(key,count);
      kept.set(actor,JSON.stringify(next));
      changes.filter(change=>change.count>0).forEach(change=>adds.push({actor,item:change.item,count:change.count}));
      return {ok:true};
    },
    addItem: function (actor, item, count) {
      const key = actor + '|' + item;
      inv.set(key, (inv.get(key) || 0) + count);
      adds.push({ actor: actor, item: item, count: count });
      return true;
    },
    takeItem: function (actor, item, count) {
      const key = actor + '|' + item;
      if ((inv.get(key) || 0) < count) return false;
      inv.set(key, inv.get(key) - count);
      return true;
    },
    rankOf: function (actor, key) { return (ranks && ranks[actor + ':' + key]) || ''; },
    creatureName: function (id) { return names[id] || ''; },
    cellOf: function (id) { return cells[id] || ''; },
    traderHold: function (id) { return holds[id] || ''; },
    debitPurse: function () { purseTouches++; throw new Error('purse'); },
    classGate: function () { return null; },
    toolGate: function () { return null; },
    mining: function () { return false; },
    stopMining: function () {},
    swinging: function () { return false; },
    toolIdIn: function () { return 1; },
    swing: function (actor, anim, done) { done(); },
    swingAnim: 'mine',
    notify: function () {},
    say: function () {},
    creditWork: function () { return null; },
    wearTool: function () { return null; }
  });
  return { svc: svc, inv: inv, adds: adds, purse: purse, touches: function () { return purseTouches; } };
}
let clock = 1000;
const names = {};
const cells = {};
const holds = {};
const box = world({
  '1:miner': 'master', '1:fisher': 'novice', '1:gatherer': 'novice',
  '1:hunter': 'master', '1:farmer': 'expert', '1:wardweaver': 'novice',
  '2:miner': 'advanced', '3:miner': 'master', '4:bladebinder': 'novice'
});
const svc = box.svc;
const line = svc.lineup();
assert.equal(line.supply, undefined);
assert.equal(typeof svc.supply, 'undefined');
assert.equal(JSON.stringify(line.scarce.map(function (row) { return row.name; })), JSON.stringify(doc.scarce.map(function (row) { return row[0]; })));
assert.equal(JSON.stringify(line.scene.map(function (row) { return row.name; })), JSON.stringify(doc.scene.map(function (row) { return row[0]; })));
doc.scarce.forEach(function (cellsRow, index) {
  const row = line.scarce[index];
  assert.equal(row.who, cellsRow[1], row.name);
  assert.equal(row.ask, firstNumber(cellsRow[2]), row.name);
  assert.equal(row.holds, firstNumber(cellsRow[3]), row.name);
  assert.equal(row.hours, hoursOf(cellsRow[4]), row.name);
});
doc.scene.forEach(function (cellsRow, index) {
  const row = line.scene[index];
  assert.equal(row.check, cellsRow[1], row.name);
  assert.equal(row.gold, Number(cellsRow[2]), row.name);
  assert.equal(row.hours, hoursOf(cellsRow[3]), row.name);
  assert.equal(row.count, killCount(cellsRow[1]), row.name);
  assert.equal(row.match, killMatch(cellsRow[1]), row.name);
  assert.equal(row.kind, killCount(cellsRow[1]) ? 'kill' : 'retrieval');
});
assert.ok(line.scene.every(function (row) { return row.gold !== 250; }));
assert.equal(svc.offer(1, 'supply').ok, false);

const ebony = line.scarce[0];
assert.equal(svc.offer(2, 'ebony').ok, false, 'advanced miner cannot take a master scarce quest');
assert.equal(svc.offer(1, 'heartstone').ok, true);
assert.equal(svc.mineRare(1, 'heart-a', { name: 'Heart Stone', ore: 'heart' }), 'This place is shut.');
svc.walkAway(1, 'heartstone');
assert.equal(svc.offer(1, 'gem').why, 'gem');
assert.equal(svc.offer(1, 'gem', { gem: 'Diamond' }).ok, false);
assert.equal(svc.offer(1, 'gem', { gem: 'Emerald' }).ok, true);
svc.bindPlace('gem', { cells: { Emerald: 'barrow-1' } });
cells['em-1'] = 'barrow-1';
cells['em-2'] = 'tower-1';
assert.equal(svc.mineRare(1, 'em-2', { name: 'Emerald', ore: 'em' }), 'This place is shut.');
assert.equal(svc.mineRare(1, 'em-1', { name: 'Ruby', ore: 'ruby' }), 'This place is shut.');
assert.equal(svc.mineRare(1, 'em-1', { name: 'Emerald', ore: 'em' }), '');
assert.equal(box.inv.get('1|em'), 1);
svc.walkAway(1, 'gem');
assert.equal(box.inv.get('1|em') || 0, 0);
assert.equal(svc.offer(1, 'gem', { gem: 'Emerald' }).ok, true, 'walking away does not start the cooldown');

assert.equal(svc.offer(1, ebony.id).ok, true);
assert.equal(svc.offer(1, ebony.id).why, 'open');
assert.equal(svc.offer(3, ebony.id).ok, true, 'another person can hold the same quest');
svc.bindPlace('ebony', { cell: 'mine-1' });
cells['vein-a'] = 'mine-1';
cells['vein-b'] = 'cave-1';
const seam = { name: 'Ebony Ore', ore: 'ebony-ore' };
assert.equal(svc.mineRare(1, 'vein-b', seam), 'This place is shut.');
assert.equal(box.inv.get('1|ebony-ore') || 0, 0, 'an extra vein gives nothing');
for (let i = 0; i < ebony.holds; i++) assert.equal(svc.mineRare(1, 'vein-a', seam), '');
assert.notEqual(svc.mineRare(1, 'vein-a', seam), '');
assert.equal(box.inv.get('1|ebony-ore'), ebony.holds);
assert.equal(svc.turnIn(3, ebony.id).ok, false, 'the other copy is not this person');
const turned = svc.turnIn(1, 'ebony');
assert.equal(turned.ok, true);
assert.equal(box.inv.get('1|ebony-ore'), ebony.holds - ebony.ask, 'the extra stays');
assert.ok(!box.adds.some(function (row) { return row.item === 'f:Skyrim.esm'; }), 'scarce does not mint gold');
assert.equal(svc.offer(1, 'ebony').why, 'cooldown');
clock += (ebony.hours * 60 * 60 * 1000) - 1;
assert.equal(svc.offer(1, 'ebony').why, 'cooldown');
clock += 1;
assert.equal(svc.offer(1, 'ebony').ok, true);
svc.walkAway(1, 'ebony');

const satchel = line.scene.find(function (row) { return row.name === 'The satchel'; });
svc.bindPlace('satchel', { ref: 'sack-1', cell: 'road-1', item: 'satchel-item' });
assert.equal(svc.offer(1, 'satchel').ok, true);
assert.equal(svc.noteContainer(1, 'sack-2', 'road-1'), null);
assert.equal(svc.noteContainer(1, 'sack-1', 'other'), null);
assert.ok(svc.noteContainer(1, 'sack-1', 'road-1'));
assert.equal(svc.noteContainer(1, 'sack-1', 'road-1'), null, 'a retrieval is one item');
assert.equal(box.inv.get('1|satchel-item'), 1);
const beforeGold = box.adds.length;
assert.equal(svc.walkAway(1, 'satchel').ok, true);
assert.equal(box.inv.get('1|satchel-item') || 0, 0);
assert.equal(box.adds.length, beforeGold, 'walking away does not mint');
assert.equal(svc.offer(1, 'satchel').ok, true);
svc.noteContainer(1, 'sack-1', 'road-1');
const sceneTurn = svc.turnIn(1, 'satchel', 'trader-1');
assert.equal(sceneTurn.ok, true);
assert.equal(box.inv.get('1|satchel-item') || 0, 0);
const minted = box.adds.filter(function (row) { return row.item === 'f:Skyrim.esm'; });
assert.equal(minted.length, 1);
assert.equal(minted[0].count, satchel.gold);
assert.equal(box.touches(), 0, 'scene gold never touches a purse');
assert.equal(svc.offer(1, 'satchel').why, 'cooldown');

const wolf = line.scene.find(function (row) { return row.name === 'A wolf'; });
svc.bindPlace('wolf', { cell: 'pad-1' });
assert.equal(svc.offer(1, 'wolf').ok, true);
names[10] = 'Dragon'; cells[10] = 'pad-1';
svc.noteKill(1, 10);
names[11] = 'Wolf'; cells[11] = 'elsewhere';
svc.noteKill(1, 11);
assert.equal(svc.turnIn(1, 'wolf').ok, false);
assert.equal(box.adds.filter(function (row) { return row.count === wolf.gold; }).length, 0);
names[12] = 'Wolf'; cells[12] = 'pad-1';
svc.noteKill(1, 12);
assert.equal(svc.turnIn(1, 'wolf').ok, true);
assert.equal(box.adds.filter(function (row) { return row.item === 'f:Skyrim.esm' && row.count === wolf.gold; }).length, 1);

const camp = line.scene.find(function (row) { return row.name === 'The camp'; });
svc.bindPlace('camp', { cell: 'camp-1' });
assert.equal(svc.offer(1, 'camp').ok, true);
names[21] = 'Bandit'; names[22] = 'Bandit Outlaw'; names[23] = 'Bandit';
cells[21] = cells[22] = cells[23] = 'camp-1';
svc.noteKill(1, 21);
svc.noteKill(1, 22);
assert.equal(svc.turnIn(1, 'camp').ok, false);
svc.noteKill(1, 23);
assert.equal(svc.turnIn(1, 'camp').ok, true);
assert.equal(box.adds.filter(function (row) { return row.count === camp.gold; }).length, 1);

assert.equal(svc.offer(4, 'geode').ok, true, 'either Enchanter half may take the geode');
assert.equal(svc.offer(1, 'longfin').ok, true, 'a fisher of any rank may take the longfin');
assert.equal(svc.offer(3, 'longfin').ok, false, 'a miner is not a fisher');

const mineBody = gm.slice(gm.indexOf('function mineOre'), gm.indexOf('function chopWood'));
assert.ok(mineBody.indexOf('isRareSeam') >= 0, 'mineOre sends a rare seam to the scarce place');
assert.ok(gm.indexOf('noteKill(killerId, actorId)') >= 0, 'a death can count for a scene kill');
assert.equal(box.touches(), 0);
console.log('PASS scarce and scene quests match docs/systems/quests.md');
