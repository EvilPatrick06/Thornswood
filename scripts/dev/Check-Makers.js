// Check-Makers.js
//
// Everything the server itself puts into a pack has somebody who makes it or
// gathers it (#3132). Patrick, 22 Oct 2026, on his report page: everything in
// the world has a recipe except named uniques and quest items (docs/DECIDED.md,
// Items and coin). Before this nothing held a new loot row to that, so the
// dungeon table grew bread, ale, bows, gems, soul gems and every college tome
// that no trade could make, and two of its rows named a second record of a
// common item (an orichalcum ingot and a petty soul gem) that no bench asks
// for and no producer gives.
//
//   node scripts/dev/Check-Makers.js           check, exit 1 on any problem
//   node scripts/dev/Check-Makers.js --write   write the list page, then check
//
// WHAT THE SERVER HANDS OUT, read out of the repository, never typed here:
//   the dungeon and body loot in game/gamemode.js (GOODS, TOMES, EXCLUSIVE:
//     docs/systems/dungeon-loot.md; a chest, a boss chest and a searched body
//     all draw from these three);
//   the shift a new character starts in (game/data/chargen.json);
//   the tool a class pick hands over (TOOLS in game/gamemode.js, its give);
//   what an open-book recipe asks for, since that recipe is dead until
//     somebody can make or gather each of its inputs.
// Merchants are not on it: an NPC trader sells only stock somebody sold or
// hauled to it (the merchant ledger), so nothing there comes from nothing.
//
// WHO MAKES OR GATHERS AN ITEM:
//   a recipe in game/data/recipes.json that is in the open book: not cut
//     (docs/systems/cut-items.md) and not tempering, which the server never sees;
//   a class's own table: harvests and crops, hunts, ores, FISH_BY_BASE in
//     game/gamemode.js, and the scarce sources in game/data/merchant-scarce-*.json;
//   the producer the recipe table records on an input (the salt quarry and the
//     like, which have no table of their own);
//   an Alchemist at the lab for a potion or a poison (game/data/food.json),
//     because Skyrim has no alchemy recipe records: the lab is the work
//     (docs/systems/professions/alchemist.md).
//
// AN ITEM NOBODY MAKES YET is a failure unless Check-Makers.waiting.json names
// it with the open issue that gives it a maker. An entry that now has a maker,
// or that the world no longer hands out, is a failure too, so the file cannot
// grow stale. Named uniques and quest items go in its exempt list with why.
//
// Read only apart from docs/systems/lists/who-makes-it.md with --write.
// tests/test-3132-makers.js runs it on every pull request.
'use strict';
const fs = require('fs');
const path = require('path');

const TEMPER_BENCHES = ['CraftingSmithingSharpeningWheel', 'CraftingSmithingArmorTable'];
const PAGE = path.join('docs', 'systems', 'lists', 'who-makes-it.md');
const WAITING = path.join('scripts', 'dev', 'Check-Makers.waiting.json');
// Which class or profession works each scarce source, as SCARCE in gamemode.js gates it.
const SCARCE_WHO = {
  'merchant-scarce-fishing.json': 'Fisher',
  'merchant-scarce-geodes.json': 'Enchanter',
  'merchant-scarce-harvest.json': 'Gatherer'
};
// The halves whose work is a menu at their bench rather than recipe rows, so a
// count of 0 is not "nothing to do" (docs/systems/professions/alchemist.md and
// enchanter.md).
const MENU_WORK = {
  'Alchemist/Blightbrewer': 'brews poisons in the alchemy lab\'s menu, which has no recipe rows',
  'Alchemist/Physicker': 'also brews medicine in the alchemy lab\'s menu, which has no recipe rows',
  'Enchanter/Wardweaver': 'enchants armour and clothing in the arcane enchanter\'s menu, which has no recipe rows',
  'Enchanter/Bladebinder': 'also enchants in the arcane enchanter\'s menu'
};
const CLASS_NAME = { miner: 'Miner', gatherer: 'Gatherer', farmer: 'Farmer', fisher: 'Fisher', hunter: 'Hunter' };

function key(desc) { return String(desc).toLowerCase(); }

function readJson(root, rel) {
  return JSON.parse(fs.readFileSync(path.join(root, rel), 'utf8'));
}

/** The text between two markers of gamemode.js, or an error naming what moved. */
function between(src, start, end, what) {
  const a = src.indexOf(start);
  const b = a < 0 ? -1 : src.indexOf(end, a + start.length);
  if (a < 0 || b < 0) throw new Error('game/gamemode.js no longer has ' + what + ' where this check reads it (' + start + ')');
  return src.slice(a + start.length, b);
}

/** Every { desc: '...', name: '...' } row in a block of gamemode.js. */
function descRows(block) {
  const out = [];
  const rx = /desc: '([^']+)', name: '([^']+)'/g;
  let m;
  while ((m = rx.exec(block))) out.push({ desc: m[1], name: m[2] });
  return out;
}

function handouts(root, src) {
  const out = [];
  const loot = between(src, '  var GOODS = [', '  function clampTier(', 'the dungeon loot block');
  const goods = between(loot, '', '  var TOMES = {', 'GOODS');
  const tomes = between(loot, '  var TOMES = {', '  var EXCLUSIVE = [', 'TOMES');
  const exclusive = between(loot, '  var EXCLUSIVE = [', '];', 'EXCLUSIVE');
  for (const r of descRows(goods)) out.push({ desc: r.desc, name: r.name, by: 'Dungeon and body loot' });
  for (const r of descRows(tomes)) out.push({ desc: r.desc, name: r.name, by: 'Dungeon and body loot, tomes' });
  for (const r of descRows(exclusive)) out.push({ desc: r.desc, name: r.name, by: 'Dungeon exclusive' });
  const chargen = readJson(root, 'game/data/chargen.json');
  for (const list of ['shift', 'rieklingShift']) {
    for (const row of chargen[list] || []) out.push({ desc: row[0], name: '', by: 'A new character\'s clothes' });
  }
  // What an open-book recipe asks for is in the world too: nobody can make
  // that recipe until somebody can make or gather each thing it asks for.
  const rec = readJson(root, 'game/data/recipes.json');
  for (const row of Object.values(rec.recipes)) {
    if (TEMPER_BENCHES.indexOf(row.benchName) >= 0 || row.book === 'cut') continue;
    for (const it of row.inputItems || []) out.push({ desc: it.item, name: it.name, by: 'Asked for by a recipe', recipe: row.half + ': ' + row.name });
  }
  const tools = between(src, '\nconst TOOLS = {', '\n};', 'TOOLS');
  const rx = /give: '([^']+)'[\s\S]*?name: '((?:[^'\\]|\\.)+)'/g;
  let m;
  while ((m = rx.exec(tools))) out.push({ desc: m[1], name: m[2].replace(/\\'/g, '\''), by: 'A class pick\'s tool' });
  return out;
}

function makers(root, src) {
  const who = new Map();
  const names = new Map();
  const written = new Map();
  function add(desc, maker) {
    const k = key(desc);
    if (!written.has(k)) written.set(k, desc);
    if (!who.has(k)) who.set(k, new Set());
    who.get(k).add(maker);
  }
  function named(desc, name) {
    if (name && !names.has(key(desc))) names.set(key(desc), name);
  }
  const rec = readJson(root, 'game/data/recipes.json');
  for (const section of ['recipes', 'unowned']) {
    for (const row of Object.values(rec[section])) {
      named(row.out, row.name);
      for (const it of row.inputItems || []) {
        named(it.item, it.name);
        if (it.producedBy) add(it.item, (CLASS_NAME[it.producedBy] || it.producedBy) + ', ' + it.producedAt);
      }
      if (TEMPER_BENCHES.indexOf(row.benchName) >= 0 || row.book === 'cut') continue;
      const bench = String(row.benchName || '').replace(/^Crafting/, '');
      add(row.out, row.owner ? row.owner + '/' + row.half + ' at ' + bench : 'Whoever the ' + bench + ' opens for');
    }
  }
  const harvests = readJson(root, 'game/data/harvests.json');
  for (const v of Object.values(harvests.harvests)) { named(v.produce, v.name); add(v.produce, 'Gatherer, ' + v.rank); }
  for (const v of Object.values(harvests.crops)) { named(v.produce, v.name); add(v.produce, 'Farmer, ' + v.rank); }
  for (const v of Object.values(readJson(root, 'game/data/hunts.json').hunts)) {
    for (const g of v.gives || []) { named(g.item, g.name); add(g.item, 'Hunter, ' + v.rank); }
  }
  for (const v of Object.values(readJson(root, 'game/data/ores.json').ores)) { named(v.ore, v.name); add(v.ore, 'Miner, ' + v.rank); }
  const fish = JSON.parse(between(src, 'var FISH_BY_BASE = ', '// ==== end FISH_BY_BASE', 'FISH_BY_BASE').trim().replace(/;$/, ''));
  for (const v of Object.values(fish)) { named(v.produce, v.name); add(v.produce, 'Fisher, ' + v.rank); }
  for (const file of Object.keys(SCARCE_WHO)) {
    for (const s of readJson(root, 'game/data/' + file).sources) add(s.item, SCARCE_WHO[file] + ', ' + s.rank + ', scarce');
  }
  // food.json's potion and poison names did not survive as words (alchemist.md), so only its kind is read.
  for (const [desc, v] of Object.entries(readJson(root, 'game/data/food.json').items)) {
    if (v.kind === 'potion' || v.kind === 'poison') add(desc, 'Alchemist at the lab');
  }
  // The rest of the names, as the game writes them, from ITEM_NAMES and then ADMIN_ITEMS.
  const itemNames = between(src, '// ==== ITEM_NAMES ====', '// ==== end ITEM_NAMES ====', 'ITEM_NAMES') +
    between(src, 'var ADMIN_ITEMS = {', '\n  };', 'ADMIN_ITEMS');
  const rx = /^\s*"[^"]*": \["((?:[^"\\]|\\.)*)", "([^"]+)"\]/gm;
  let n;
  while ((n = rx.exec(itemNames))) named(n[2], JSON.parse('"' + n[1] + '"'));
  return { who: who, names: names, written: written };
}

function measure(root) {
  root = root || path.join(__dirname, '..', '..');
  const src = fs.readFileSync(path.join(root, 'game', 'gamemode.js'), 'utf8').split('\r').join('');
  const m = makers(root, src);
  const waiting = readJson(root, WAITING.split(path.sep).join('/'));
  const exempt = new Map((waiting.exempt || []).map(e => [key(e.desc), e]));
  const wait = new Map((waiting.items || []).map(e => [key(e.desc), e]));
  const rows = new Map();
  for (const h of handouts(root, src)) {
    const k = key(h.desc);
    // The name as the records write it, where the tables know it; the loot table writes its own in lower case.
    const row = rows.get(k) || { desc: h.desc, name: m.names.get(k) || h.name || h.desc, by: [], makers: [] };
    if (row.by.indexOf(h.by) < 0) row.by.push(h.by);
    if (h.recipe) { row.recipes = row.recipes || []; if (row.recipes.indexOf(h.recipe) < 0) row.recipes.push(h.recipe); }
    row.makers = Array.from(m.who.get(k) || []).sort();
    rows.set(k, row);
  }
  const madeByName = new Map();
  for (const [k, set] of m.who) {
    const n = (m.names.get(k) || '').toLowerCase();
    if (n && set.size && !madeByName.has(n)) madeByName.set(n, k);
  }
  const problems = [];
  for (const row of rows.values()) {
    const k = key(row.desc);
    if (row.makers.length) {
      if (wait.has(k)) problems.push(row.name + ' (' + row.desc + ') is in ' + WAITING + ' but ' + row.makers.join('; ') + ' makes it now. Take its entry out.');
      continue;
    }
    if (exempt.has(k)) { row.exempt = exempt.get(k); continue; }
    if (wait.has(k)) {
      const w = wait.get(k);
      if (!/^#\d+$/.test(String(w.issue || ''))) problems.push(row.name + ' (' + row.desc + ') waits in ' + WAITING + ' with no issue number.');
      row.waiting = w;
      continue;
    }
    // A same-named record somebody does make: the row names the wrong record.
    const twin = madeByName.get(String(row.name).toLowerCase());
    if (twin && twin !== k) {
      problems.push(row.name + ' (' + row.desc + '), from ' + row.by.join(', ') + ', is a record nobody makes. The trades make ' +
        m.names.get(twin) + ' as ' + m.written.get(twin) + ': name that record.');
      continue;
    }
    problems.push(row.name + ' (' + row.desc + '), from ' + row.by.join(', ') + ', has nobody who makes or gathers it. ' +
      'Give it a maker, or name it in ' + WAITING + ' with the issue that will.');
  }
  for (const [k, w] of wait) {
    if (!rows.has(k)) problems.push(w.name + ' (' + w.desc + ') is in ' + WAITING + ' but the world no longer hands it out. Take its entry out.');
  }
  for (const [k, e] of exempt) {
    if (!rows.has(k)) problems.push(e.name + ' (' + e.desc + ') is exempt in ' + WAITING + ' but the world no longer hands it out. Take its entry out.');
    if (!e.why) problems.push(e.name + ' (' + e.desc + ') is exempt with no reason.');
  }
  return { rows: Array.from(rows.values()), problems: problems, trades: trades(root, m) };
}

/** What each half and class makes or gathers, counted by distinct item. */
function trades(root, m) {
  const rec = readJson(root, 'game/data/recipes.json');
  const out = [];
  const byHalf = new Map();
  for (const row of Object.values(rec.recipes)) {
    if (TEMPER_BENCHES.indexOf(row.benchName) >= 0 || row.book === 'cut' || !row.owner) continue;
    const k = row.owner + '/' + row.half;
    if (!byHalf.has(k)) byHalf.set(k, new Set());
    byHalf.get(k).add(key(row.out));
  }
  for (const [p, info] of Object.entries(rec.professions)) {
    if (!info.halves) { out.push({ who: p, items: 0, note: info.why }); continue; }
    for (const h of info.halves) {
      const k = p + '/' + h;
      out.push({ who: k, items: (byHalf.get(k) || new Set()).size, note: info.craftsAtAll ? (MENU_WORK[k] || '') : info.why });
    }
  }
  const byClass = new Map();
  for (const [k, set] of m.who) {
    for (const w of set) {
      const c = w.split(',')[0];
      if (['Miner', 'Gatherer', 'Farmer', 'Fisher', 'Hunter'].indexOf(c) < 0) continue;
      if (!byClass.has(c)) byClass.set(c, new Set());
      byClass.get(c).add(k);
    }
  }
  for (const c of ['Farmer', 'Fisher', 'Gatherer', 'Hunter', 'Miner']) out.push({ who: c, items: (byClass.get(c) || new Set()).size, note: '', isClass: true });
  return out;
}

function cell(s) { return String(s == null ? '' : s).replace(/\|/g, '/').replace(/\r?\n/g, ' ').trim(); }

function page(result) {
  const rows = result.rows.slice().sort((a, b) => String((a.waiting || {}).issue || '').localeCompare(String((b.waiting || {}).issue || '')) ||
    a.by[0].localeCompare(b.by[0]) || a.name.localeCompare(b.name));
  const none = rows.filter(r => !r.makers.length);
  const L = [];
  L.push('# Who makes what the world hands out');
  L.push('');
  L.push('Generated by `scripts/dev/Check-Makers.js` from the server\'s own tables. Do not edit it by hand: run `node scripts/dev/Check-Makers.js --write`.');
  L.push('');
  L.push('Everything in the world has a recipe except named uniques and quest items (Patrick, 22 October 2026, #3132). ' +
    'The world here is what the server puts into a pack from nothing: the dungeon and body loot ([Dungeon loot](../dungeon-loot.md)), ' +
    'a new character\'s clothes, the tool a class pick hands over, and whatever a recipe in the open book asks for. A trader sells only what somebody sold or hauled to it, so traders are not on this page.');
  L.push('');
  L.push('A maker is a recipe in the open book (not cut and not tempering), a class that gathers the item, or an Alchemist at the lab for a potion or a poison. ' +
    'The build fails when the world hands out something with no maker that `scripts/dev/Check-Makers.waiting.json` does not name with the issue that will give it one.');
  L.push('');
  L.push(rows.length + ' items handed out. ' + (rows.length - none.length) + ' have a maker. ' + none.length + ' have none yet.');
  L.push('');
  L.push('## Nobody makes these yet');
  L.push('');
  if (!none.length) L.push('None.');
  else {
    L.push('| Item | Where the world has it | Recipes that wait on it | Waiting on | Why |');
    L.push('| --- | --- | --- | --- | --- |');
    for (const r of none) {
      const w = r.waiting || r.exempt || {};
      L.push('| ' + cell(r.name) + ' | ' + cell(r.by.join(', ')) + ' | ' + (r.recipes || []).length + ' | ' +
        cell(r.exempt ? 'exempt' : w.issue) + ' | ' + cell(w.why) + ' |');
    }
  }
  L.push('');
  L.push('## What each trade makes or gathers');
  L.push('');
  L.push('Distinct items, open book only. A profession half that makes nothing from a recipe row may still have work at its bench, which the note says.');
  L.push('');
  L.push('| Who | Items | Note |');
  L.push('| --- | --- | --- |');
  // A path in a note (scripts\\dev\\Build-SpellTable.ps1) is code, not prose.
  for (const t of result.trades) {
    L.push('| ' + cell(t.who) + ' | ' + t.items + ' | ' + cell(t.note).replace(/[\w.-]*\w(?:\\[\w.-]*\w)+/g, '`$&`') + ' |');
  }
  L.push('');
  L.push('## Every item and its maker');
  L.push('');
  L.push('| Item | Where the world has it | Who makes or gathers it | Id |');
  L.push('| --- | --- | --- | --- |');
  for (const r of rows) {
    if (!r.makers.length) continue;
    L.push('| ' + cell(r.name) + ' | ' + cell(r.by.join(', ')) + ' | ' + cell(r.makers.join('; ')) + ' | `' + r.desc + '` |');
  }
  L.push('');
  return L.join('\n');
}

function run(root, write) {
  root = root || path.join(__dirname, '..', '..');
  const result = measure(root);
  const want = page(result);
  const file = path.join(root, PAGE);
  if (write) fs.writeFileSync(file, want, 'utf8');
  const have = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').split('\r').join('') : '';
  if (have !== want) result.problems.push(PAGE.split(path.sep).join('/') + ' is out of date. Run node scripts/dev/Check-Makers.js --write and commit it.');
  return result;
}

module.exports = { measure: measure, page: page, run: run };

if (require.main === module) {
  const result = run(null, process.argv.indexOf('--write') >= 0);
  const none = result.rows.filter(r => !r.makers.length).length;
  console.log(result.rows.length + ' items handed out, ' + (result.rows.length - none) + ' with a maker, ' + none + ' waiting.');
  for (const p of result.problems) console.log('FAIL  ' + p);
  process.exit(result.problems.length ? 1 : 0);
}
