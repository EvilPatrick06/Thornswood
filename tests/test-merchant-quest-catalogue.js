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
const recipes = JSON.parse(read('game/data/recipes.json')).recipes;
const tables = JSON.parse(read('game/data/merchant-role-tables.json')).tables;
const proofFields = ['owner', 'half', 'rank', 'out', 'makes', 'bench', 'inputItems', 'needs'];

function validate(catalogue, source = {recipes, tables}) {
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
    assert.ok(['kill', 'commission'].includes(row.kind), 'Unknown objective kind');
    const fields = ['id', 'name', 'text', 'tier', 'gate', 'merchant', 'kind', 'cooldownHours'];
    assert.deepEqual(Object.keys(row).sort(), fields.concat(row.kind === 'kill' ?
      ['count', 'targets', 'rewardGold'] : ['goods', 'reward']).sort());
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
    assert.ok(Number.isSafeInteger(row.cooldownHours) && row.cooldownHours > 0);
    assert.ok(!gm.includes("'" + row.id + "'") && !gm.includes('"' + row.id + '"'), 'No bundled draft definition');
    if (row.kind === 'commission') {
      assert.equal(row.tier, 'novice', 'Higher commissions need their own producer/cadence review');
      assert.equal(row.cooldownHours, 6);
      assert.equal(gate.profession, row.merchant.role.toLowerCase());
      assert.deepEqual(row.reward, {source: 'merchant-purse', pricing: 'submitted-hold-price'});
      assert.ok(Array.isArray(row.goods) && row.goods.length > 0 && row.goods.length <= 5);
      const items = new Set();
      for (const good of row.goods) {
        assert.deepEqual(Object.keys(good).sort(), ['count', 'item', 'recipe']);
        assert.ok(typeof good.item === 'string' && !items.has(good.item)); items.add(good.item);
        assert.ok(Number.isSafeInteger(good.count) && good.count > 0 && good.count <= 255, 'Commission quantity');
        assert.deepEqual(Object.keys(good.recipe).sort(), ['reference', ...proofFields].sort());
        const recipe = source.recipes[good.recipe.reference];
        assert.ok(recipe && recipe.fires === true && recipe.book !== 'cut' &&
          recipe.roll === undefined && recipe.race === '', 'Commission needs a public firing recipe');
        assert.equal(recipe.owner, row.merchant.role);
        assert.equal(recipe.rank, row.tier);
        assert.equal(gate.half, recipe.half.toLowerCase());
        assert.equal(good.item, recipe.out);
        assert.ok(source.tables[row.merchant.role].buy.includes(good.item), 'Commission output needs ordinary buy permission too');
        for (const field of proofFields) assert.deepEqual(good.recipe[field], recipe[field], 'Recipe evidence/' + field);
        assert.ok(recipe.inputItems.length > 0 && recipe.inputItems.every(input =>
          input.suppliedAt === 'novice' && (Object.keys(P.TABLE.classes).includes(input.suppliedBy) ||
            Object.keys(P.TABLE.professions).includes(input.suppliedBy))), 'Novice supply provenance');
      }
      const signature = JSON.stringify(['commission', [...items].sort()]);
      assert.ok(!objectives.has(signature), 'A name or quantity change alone is not a new commission');
      objectives.add(signature);
      continue;
    }
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
  return {ids, firstFinishGold, dailyBound};
}
const {ids, firstFinishGold, dailyBound} = validate(catalogue);
const docs = read('docs/systems/merchant-quest-catalogue.md');
assert.ok(docs.includes('**' + catalogue.quests.length + ' authored draft definitions**'));
assert.ok(docs.includes('**' + firstFinishGold + ' gold**'));
assert.ok(docs.includes('**' + dailyBound + ' gold**'));
function proof(ref) {
  return {reference: ref, ...Object.fromEntries(proofFields.map(key => [key, recipes[ref][key]]))};
}
const commission = {id: 'q-whiterun-smith-straps', name: 'Straps for the forge',
  text: 'Bring six pieces of leather for the forge.', tier: 'novice',
  gate: {profession: 'smith', rank: 'novice', half: 'platewright'},
  merchant: roster.merchants.find(m => m.bookHold === 'whiterun' && m.role === 'Smith'),
  kind: 'commission', goods: [{item: 'db5d2:Skyrim.esm', count: 6, recipe: proof('1033de:Skyrim.esm')}],
  reward: {source: 'merchant-purse', pricing: 'submitted-hold-price'}, cooldownHours: 6};
const one = row => ({version: 1, active: false, complete: false, quests: [row]});
assert.doesNotThrow(() => validate(one(commission)), 'A source-bound inactive commission needs its own exact validation');
const clone = value => JSON.parse(JSON.stringify(value));
let refusals = 0;
function rejects(edit, expected) {
  const row = clone(commission); edit(row);
  assert.throws(() => validate(one(row)), expected); refusals++;
}
rejects(row => {row.kind = 'supply';}, /Unknown objective kind/);
rejects(row => {row.id += '\n';});
rejects(row => {row.gate.half = 'edgewright';});
rejects(row => {row.goods[0].item = '5ace4:Skyrim.esm';});
rejects(row => {row.goods[0].recipe.needs = [];}, /Recipe evidence\/needs/);
rejects(row => {row.goods[0].count = 0;}, /Commission quantity/);
rejects(row => {row.goods[0].count = 256;}, /Commission quantity/);
rejects(row => {row.goods[0].count = 1.5;}, /Commission quantity/);
rejects(row => {row.reward.source = 'mint';});
rejects(row => {row.reward.gold = 20;});
rejects(row => {row.goods.push(clone(row.goods[0]));});
rejects(row => {row.merchant.base = '13b9c:Skyrim.esm';});
for (const change of [{fires: false}, {book: 'cut'}, {roll: true}, {race: 'Nord'}]) {
  const source = {...recipes, '1033de:Skyrim.esm': {...recipes['1033de:Skyrim.esm'], ...change}};
  assert.throws(() => validate(one(commission), {recipes: source, tables}), /public firing recipe/); refusals++;
}
for (const change of [{suppliedAt: 'advanced'}, {suppliedBy: '__proto__'}, {suppliedBy: 'unknown'}]) {
  const row = clone(commission), recipe = clone(recipes['1033de:Skyrim.esm']);
  Object.assign(recipe.inputItems[0], change); row.goods[0].recipe.inputItems = clone(recipe.inputItems);
  assert.throws(() => validate(one(row), {recipes: {...recipes, '1033de:Skyrim.esm': recipe}, tables}), /Novice supply provenance/);
  refusals++;
}
const forbidden = clone(tables); forbidden.Smith.buy = forbidden.Smith.buy.filter(item => item !== 'db5d2:Skyrim.esm');
assert.throws(() => validate(one(commission), {recipes, tables: forbidden}), /buy permission/); refusals++;
const repeated = clone(commission); repeated.id = 'q-another-name'; repeated.goods[0].count++;
assert.throws(() => validate({...one(commission), quests: [commission, repeated]}), /quantity change alone/); refusals++;
console.log('PASS ' + ids.size + ' inactive quest candidates, exact source bindings and real gates; ' + dailyBound + ' gold cooldown-only 24h bound, 0 enabled');
console.log('PASS explicit commission source authority and ' + refusals + ' malformed-source/permission/quantity/bundle refusals');
