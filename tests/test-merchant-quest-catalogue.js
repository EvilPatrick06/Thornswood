'use strict';
// Inactive authored candidates only. This reads source, not a game or world.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.join(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8').replace(/\r/g, '');
const catalogue = JSON.parse(read('game/data/merchant-quests.json'));
const roster = JSON.parse(read('game/data/merchant-roster.json'));
const population = JSON.parse(read('game/data/npc-population.json'));
const gm = read('game/gamemode.js');
const begin = gm.indexOf('// ==== thornswood progression ====');
const end = gm.indexOf('// ==== end thornswood progression ====');
assert.ok(begin >= 0 && end > begin);
const context = {};
vm.createContext(context);
vm.runInContext(gm.slice(begin, end), context);
const P = context.__thornswoodProgression;
const rules = require('../game/quest-eligibility').createQuestEligibility({table: P.TABLE, spellIds: P.SPELL_IDS});

assert.deepEqual(Object.keys(catalogue).sort(), ['active', 'complete', 'quests', 'version']);
assert.equal(catalogue.version, 1);
assert.equal(catalogue.active, false, 'Draft data cannot activate work');
assert.equal(catalogue.complete, false, 'The full catalogue and runtime prerequisites remain unfinished');
assert.ok(Array.isArray(catalogue.quests) && catalogue.quests.length > 0);
assert.ok(!read('scripts/dev/Build-MerchantGamemode.js').includes('merchant-quests.json'), 'No draft runtime import');

// Compare actual objective identities, not titles or merchant/hold labels.
const killSource = read('game/kill-contracts.js');
const specStart = killSource.indexOf('var SPEC=[');
const specEnd = killSource.indexOf('\n];', specStart);
assert.ok(specStart >= 0 && specEnd > specStart);
const legacy = vm.runInNewContext(killSource.slice(specStart, specEnd + 3) + '\nSPEC');
const objective = (count, refs) => JSON.stringify(['kill', count, refs.slice().sort()]);
const objectives = new Set(legacy.map(row => objective(row.count, Object.keys(row.refs).map(ref => ref + ':Skyrim.esm'))));
const ids = new Set();
const targets = ['ref', 'base', 'cell', 'world', 'pos', 'leash', 'role', 'species',
  'location', 'locationName', 'hold', 'habitat', 'tier', 'returnMinutes'];
let firstFinishGold = 0, dailyBound = 0;
for (const row of catalogue.quests) {
  assert.deepEqual(Object.keys(row).sort(), ['id', 'name', 'text', 'tier', 'gate', 'merchant', 'kind',
    'count', 'targets', 'rewardGold', 'cooldownHours'].sort());
  assert.match(row.id, /^q-[a-z0-9]+(?:-[a-z0-9]+)*$/);
  assert.ok(row.id.length <= 48 && !ids.has(row.id));
  ids.add(row.id);
  assert.ok(typeof row.name === 'string' && row.name.trim().length > 0);
  assert.ok(typeof row.text === 'string' && row.text.trim().length > 0);
  assert.ok(P.TABLE.ranks.includes(row.tier));
  const gate = rules.validate(row.gate);
  assert.notEqual(gate.open, true, 'New work needs its real class/profession gate');
  assert.equal(gate.rank, row.tier);
  const merchants = roster.merchants.filter(m => m.reference === row.merchant.reference);
  assert.equal(merchants.length, 1);
  assert.deepEqual(row.merchant, merchants[0]);
  const sourceMerchant = population.npcs.find(n => n.ref === row.merchant.reference);
  assert.ok(sourceMerchant && sourceMerchant.keep && sourceMerchant.role === 'trader');
  assert.equal(sourceMerchant.base, row.merchant.base);
  assert.equal(row.kind, 'kill', 'Other objective kinds need their own source validation');
  assert.ok(Array.isArray(row.targets) && row.targets.length > 0);
  assert.ok(Number.isSafeInteger(row.count) && row.count > 0 && row.count <= row.targets.length);
  const refs = new Set();
  for (const target of row.targets) {
    assert.deepEqual(Object.keys(target).sort(), targets.slice().sort());
    assert.ok(!refs.has(target.ref)); refs.add(target.ref);
    const source = population.npcs.find(n => n.ref === target.ref);
    assert.ok(source && source.keep && ['enemy', 'animal'].includes(source.role));
    assert.notEqual(source.habitat, 'city');
    for (const field of targets) assert.deepEqual(target[field], source[field], target.ref + '/' + field);
    assert.ok(typeof (target.world || target.cell) === 'string');
    assert.ok(target.pos.length === 3 && target.pos.every(Number.isFinite));
    assert.ok(Number.isFinite(target.leash) && target.leash > 0);
  }
  const signature = objective(row.count, [...refs]);
  assert.ok(!objectives.has(signature), 'Renaming an existing objective is not new work');
  objectives.add(signature);
  assert.ok(Number.isSafeInteger(row.rewardGold) && row.rewardGold > 0 && row.rewardGold <= 2147483647);
  assert.ok(Number.isSafeInteger(row.cooldownHours) && row.cooldownHours > 0);
  firstFinishGold += row.rewardGold;
  dailyBound += Math.ceil(24 / row.cooldownHours) * row.rewardGold;
  assert.ok(!gm.includes("'" + row.id + "'") && !gm.includes('"' + row.id + '"'), 'No bundled draft definition');
}
const docs = read('docs/systems/merchant-quest-catalogue.md');
assert.ok(docs.includes('**' + catalogue.quests.length + ' authored draft definitions**'));
assert.ok(docs.includes('**' + firstFinishGold + ' gold**'));
assert.ok(docs.includes('**' + dailyBound + ' gold**'));
console.log('PASS ' + ids.size + ' inactive quest candidates, exact source bindings and real gates; ' + dailyBound + ' gold cooldown-only 24h bound, 0 enabled');
