// test-2262-strength-weapons.js
//
// #2262. Strength-based weapons. Patrick, 16 Oct 2026: Might (the skill tree
// sub-skill, 0 to 5) is strength; a weapon weighing 30 to 44 needs Might 3,
// and the Giant's Club or anything weighing 45 or more needs Might 5. Keyed
// off the weapon's weight, never a record id.
//
// The gate is the gamemode's handler for onEquipItemAttempt(actorId, baseId),
// the opt-in skymp event Codex adds on the fork (fires before the equip is
// saved; false drops that item and it stays in the pack). Until the pin
// carries the event, this harness stands in for it: a small engine below
// raises the event for each item newly worn and drops what is refused, the
// way the fork's OnUpdateEquipment will.
//
// The strength block is run as it stands, over a stand-in mp.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
function read() {
  return fs.readFileSync(path.join.apply(path, [ROOT].concat([].slice.call(arguments))), 'utf8').split(CR).join('');
}
const gm = read('game', 'gamemode.js');
const ui = read('game', 'ui', 'thornswood-skills.js');
const doc = read('docs', 'systems', 'skill-tree.md');

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
function slice(src, start, end) {
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b + end.length);
}

const block = slice(gm, '// ==== thornswood strength weapons ====', '// ==== end thornswood strength weapons ====');
yes('the strength weapons block is in the gamemode', !!block);
if (!block) { done(); }

// ------------------------------------------------------------ the world --

function weap(weight) {
  const b = new Uint8Array(10);
  new DataView(b.buffer).setFloat32(4, weight, true);
  return { record: { type: 'WEAP', fields: [{ type: 'DNAM', data: [6] }, { type: 'DATA', data: Array.from(b) }] } };
}
const RECORDS = {
  0x00012eb7: weap(9),       // Iron Sword
  0x00013982: weap(29.9),    // just under the first row
  0x00100001: weap(30),      // a playable maul
  0x00100002: weap(44),
  0x00100003: weap(45),      // a playable Giant's Club, as a collection mod would add it
  0x00100004: weap(60),
  0x00100005: { record: { type: 'WEAP', fields: [{ type: 'DATA', data: [1, 2] }] } },  // unreadable DATA
  0x00012e49: { record: { type: 'ARMO', fields: [{ type: 'DATA', data: Array.from(weap(90).record.fields[1].data) }] } }
};
const CHAR = 'thornswoodCharacter';
const props = {};
const said = [], notes = [];
const mp = {
  lookupEspmRecordById(id) { return RECORDS[id] || { record: null }; },
  get(id, key) { return (props[id] || {})[key]; }
};
const players = {};
function person(id, might) { props[id] = { [CHAR]: { v: 1 } }; players[id] = { tree: { might: might } }; }
person(0xff000001, 0);
person(0xff000002, 3);
person(0xff000003, 4);
person(0xff000004, 5);
const npc = 0x0001a6ba;

const sandbox = {
  mp, console: { log() {}, error() {} }, DataView, ArrayBuffer, Math, Number, String, Object, isFinite,
  guard: (name, fn) => function () { return fn.apply(null, arguments); },
  notify: (a, t) => notes.push([a, t]),
  say: (a, t) => said.push([a, t])
};
sandbox.globalThis = sandbox;
sandbox.__thornswoodCharacter = { PROPERTY: CHAR, stateOf: id => players[id] };
vm.createContext(sandbox);
vm.runInContext(block, sandbox, { filename: 'strength-block.js' });
const S = sandbox.__thornswoodStrength;

yes('the block registers mp.onEquipItemAttempt', typeof mp.onEquipItemAttempt === 'function');
yes('it goes through guard() like every other engine event', /mp\.onEquipItemAttempt = guard\('onEquipItemAttempt'/.test(block));
yes('the thresholds are Patrick\'s: 45 needs 5, 30 needs 3',
    JSON.stringify(S.STRENGTH.tiers) === JSON.stringify([{ weight: 45, might: 5 }, { weight: 30, might: 3 }]));
yes('no record id is named in the rule', !/0x[0-9a-f]{5,}/i.test(block) && !/\.esp/i.test(block));
yes('no slash command anywhere in the block', !/['"]\/[a-z]/.test(block));

// ------------------------------------------------------------- weights --
yes('weight is read from WEAP DATA (9)', Math.abs(S.weightOf(0x00012eb7) - 9) < 1e-6);
yes('a weight of 44 reads 44', S.weightOf(0x00100002) === 44);
yes('an unreadable DATA reads null and is never refused', S.weightOf(0x00100005) === null && S.needOf(0x00100005) === 0);
yes('armour, however heavy, is not a weapon', S.weightOf(0x00012e49) === null && S.needOf(0x00012e49) === 0);
yes('an unknown form is not refused', S.needOf(0x00999999) === 0);

const table = [
  [0x00012eb7, 0], [0x00013982, 0], [0x00100001, 3], [0x00100002, 3], [0x00100003, 5], [0x00100004, 5]
];
table.forEach(([id, need]) => yes('weight ' + S.weightOf(id) + ' needs Might ' + need, S.needOf(id) === need));

// ------------------------------------------------------- the decisions --
const cases = [
  [0xff000001, 0x00012eb7, true], [0xff000001, 0x00013982, true],
  [0xff000001, 0x00100001, false], [0xff000001, 0x00100003, false],
  [0xff000002, 0x00100001, true], [0xff000002, 0x00100002, true], [0xff000002, 0x00100003, false],
  [0xff000003, 0x00100004, false],
  [0xff000004, 0x00100003, true], [0xff000004, 0x00100004, true],
  [npc, 0x00100004, true]
];
cases.forEach(([a, b, want]) => {
  const m = a === npc ? 'an NPC' : 'Might ' + players[a].tree.might;
  yes(m + ', weight ' + S.weightOf(b) + ': ' + (want ? 'allowed' : 'refused'), mp.onEquipItemAttempt(a, b) === want);
});

notes.length = 0; said.length = 0;
mp.onEquipItemAttempt(0xff000002, 0x00100003);
yes('a refusal says "You are not strong enough to wield this."', notes.some(n => n[1] === 'You are not strong enough to wield this.'));
yes('and "Needs Might 5"', notes.some(n => n[1] === 'Needs Might 5'));
yes('and puts the same in the chat', said.length === 1 && said[0][1] === 'You are not strong enough to wield this. Needs Might 5.');
notes.length = 0; said.length = 0;
mp.onEquipItemAttempt(0xff000001, 0x00100001);
yes('a 30 weight weapon says Needs Might 3', notes.some(n => n[1] === 'Needs Might 3'));
notes.length = 0; said.length = 0;
mp.onEquipItemAttempt(0xff000004, 0x00100003);
mp.onEquipItemAttempt(0xff000001, 0x00012eb7);
yes('an allowed equip says nothing', notes.length === 0 && said.length === 0);

// --------------------------------- the engine event, stood in for here --
// What the fork's OnUpdateEquipment does once the event is in: ask for every
// item newly worn, drop the refused ones, save the rest, keep the pack.
function engineEquip(actorId, saved, update) {
  const was = new Set(saved.inventory.filter(e => e.worn).map(e => e.baseId));
  const kept = update.inventory.filter(e => {
    if (!e.worn || was.has(e.baseId) || typeof mp.onEquipItemAttempt !== 'function') { return true; }
    return mp.onEquipItemAttempt(actorId, e.baseId) !== false;
  });
  const unequip = update.inventory.filter(e => kept.indexOf(e) < 0).map(e => e.baseId);
  return { saved: { inventory: kept }, unequip: unequip, pack: update.inventory.map(e => e.baseId) };
}
const r1 = engineEquip(0xff000002, { inventory: [] },
  { inventory: [{ baseId: 0x00100003, worn: true }, { baseId: 0x00012eb7, worn: true }] });
yes('Might 3 equipping a club and a sword: the club is dropped, the sword is saved',
    r1.saved.inventory.length === 1 && r1.saved.inventory[0].baseId === 0x00012eb7);
yes('the client is told to unequip the club', r1.unequip.length === 1 && r1.unequip[0] === 0x00100003);
yes('the club stays in the pack', r1.pack.indexOf(0x00100003) >= 0);
const r2 = engineEquip(0xff000004, { inventory: [] }, { inventory: [{ baseId: 0x00100003, worn: true }] });
yes('Might 5 equips the club and it is saved', r2.saved.inventory.length === 1 && !r2.unequip.length);
const r3 = engineEquip(0xff000001, { inventory: [] }, { inventory: [{ baseId: 0x00100004, worn: true }] });
yes('a login with a heavy weapon already worn is refused through the same event (first report after spawn)',
    r3.saved.inventory.length === 0);

// ---------------------------------------------------------- the K panel --
const might = /\{ key: 'might',[\s\S]*?gate: (\[[^\]]*\])/.exec(ui);
let gate = null;
try { gate = might ? vm.runInNewContext('(' + might[1] + ')') : null; } catch (e) { gate = null; }
yes('the K panel Might row carries the weapon thresholds', !!gate);
yes('and they are the server\'s, row for row', !!gate && JSON.stringify(gate) === JSON.stringify(S.STRENGTH.tiers));
const lineSrc = slice(ui, '  function gateLine(gate, have) {', '\n  }\n');
yes('the K panel draws the Might row\'s weapon line', !!lineSrc && /if \(s\.gate\) row\.appendChild\(el\('div', 'sd gate', gateLine\(s\.gate, have\)\)\)/.test(ui));
if (lineSrc && gate) {
  const gl = vm.runInNewContext('(' + lineSrc.trim().replace(/^function gateLine/, 'function') + ')');
  const l0 = gl(gate, 0), l3 = gl(gate, 3), l5 = gl(gate, 5);
  yes('the panel line names both rows', /weighing 30 to 44 need Might 3/.test(l0) && /weighing 45 or more need Might 5/.test(l0));
  yes('Might 0 can wield neither', /neither/.test(l0));
  yes('Might 3 can wield the first only', /first, not the second/.test(l3));
  yes('Might 5 can wield any', /any of them/.test(l5));
}

// ------------------------------------------------------------- the rest --
yes('docs/systems/skill-tree.md says what Might unlocks', /30 to 44 needs Might 3/.test(doc.replace(/\n/g, ' ')) && /45 or more/.test(doc));
yes('onUpdateEquipmentAttempt is not used to gate (it fires after the save)', !/onUpdateEquipmentAttempt\s*=/.test(block));
for (const wf of ['build.yml', 'build-pr.yml']) {
  const y = read('.github', 'workflows', wf);
  yes(wf + ' runs this harness', y.indexOf("'test-2262-strength-weapons.js'") >= 0);
}
yes('no em dash in the block or this harness', block.indexOf('\u2014') < 0 && fs.readFileSync(__filename, 'utf8').indexOf('\u2014') < 0);

done();
