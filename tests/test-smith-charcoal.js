// test-smith-charcoal.js
//
// #613: forge crafts burn charcoal. Same shape as the wooden-handle rule:
// not a CNTO on the COBJ, taken in onCraft when the craft is allowed.
//
// Read only.
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(__dirname, '..', 'game', 'gamemode.js');
const src = fs.readFileSync(SRC, 'utf8').split(String.fromCharCode(13)).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

yes('wantsCharcoal is in the gamemode', src.indexOf('function wantsCharcoal(row)') >= 0);
yes('takeCharcoal is in the gamemode', src.indexOf('function takeCharcoal(actorId)') >= 0);
yes('onCraft asks for charcoal before the handle', (() => {
  const a = src.indexOf('if (!answer.refusal && wantsCharcoal(row))');
  const b = src.indexOf('if (!answer.refusal && wantsAHandle(row))');
  return a >= 0 && b >= 0 && a < b;
})());
yes('forge benches are named',
  src.indexOf('CraftingSmithingForge: true') >= 0 &&
  src.indexOf('CraftingSmithingSkyforge: true') >= 0);
yes('charcoal grades prefer the kiln tiers then vanilla', (() => {
  const i = src.indexOf('const CHARCOAL_DESCS = [');
  if (i < 0) return false;
  const block = src.slice(i, src.indexOf('];', i) + 2);
  const order = ['ITEMS.charcoalT1', 'ITEMS.charcoalT2', 'ITEMS.charcoalT3', 'ITEMS.charcoalT4', 'ITEMS.charcoal\n', 'ITEMS.charcoal\r'];
  // Last entry is bare ITEMS.charcoal (not T1-T4). Match the closing line.
  const t1 = block.indexOf('ITEMS.charcoalT1');
  const t4 = block.indexOf('ITEMS.charcoalT4');
  const last = block.lastIndexOf('ITEMS.charcoal');
  return t1 >= 0 && t4 > t1 && last > t4 && !/ITEMS\.charcoalT\d/.test(block.slice(last));
})());

const start = src.indexOf('function wantsCharcoal(row) {');
const end = src.indexOf('\n}\n', start);
yes('wantsCharcoal body was cut out', start >= 0 && end > start);
const benchesStart = src.indexOf('const CHARCOAL_BENCHES = {');
const benchesEnd = src.indexOf('\n};', benchesStart);
const fn = new Function(
  src.slice(benchesStart, benchesEnd + 3) + '\n' +
  src.slice(start, end + 3) + '\n' +
  'return wantsCharcoal;'
);
const wantsCharcoal = fn();
yes('a forge recipe wants charcoal', wantsCharcoal({ benchName: 'CraftingSmithingForge' }) === true);
yes('a skyforge recipe wants charcoal', wantsCharcoal({ benchName: 'CraftingSmithingSkyforge' }) === true);
yes('a smelter recipe does not', wantsCharcoal({ benchName: 'CraftingSmelter' }) === false);
yes('an armour table recipe does not', wantsCharcoal({ benchName: 'CraftingSmithingArmorTable' }) === false);
yes('a missing row does not', wantsCharcoal(null) === false);
yes('recipe book has a race-aware index', src.indexOf('function recipeRaceMatches(actorId, row)') >= 0 &&
  src.indexOf('function recipeIndex(actorId)') >= 0);
yes('race-locked rows are excluded from the recipe book index',
  src.indexOf('if (!recipeRaceMatches(actorId, row)) { continue; }') >= 0);
yes('recipe book cache is separated by race',
  src.indexOf('var bookIndexes = {};') >= 0 && src.indexOf('bookIndexes[cacheKey] = out;') >= 0);
yes('panel passes actor race into the recipe book',
  src.indexOf('var book = bookView(s, actorId);') >= 0 &&
  src.indexOf("bookHalf(own, 'own', P.rankOf(s, own) || 'novice', actorId)") >= 0);

console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
