// Write-SystemLists.js
//
// Turns the checked-in tables into the lists under docs/systems/lists.
// Read only apart from those markdown files. Run it after a recipe, harvest,
// ore or hunt table changes so the plan and the tables stay the same list.
//
//   node scripts/dev/Write-SystemLists.js
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const OUT = path.join(ROOT, 'docs', 'systems', 'lists');
const RECIPES = path.join(ROOT, 'game', 'data', 'recipes.json');
const HARVESTS = path.join(ROOT, 'game', 'data', 'harvests.json');
const ORES = path.join(ROOT, 'game', 'data', 'ores.json');
const HUNTS = path.join(ROOT, 'game', 'data', 'hunts.json');
const RACES = path.join(ROOT, 'game', 'data', 'races.json');

function clean(s) {
  return String(s == null ? '' : s)
    .replace(/\u2014/g, ',')
    .replace(/\u2013/g, '-')
    .replace(/\|/g, '/')
    .replace(/\r?\n/g, ' ')
    .trim();
}

function benchShort(name) {
  return clean(name).replace(/^Crafting/, '');
}

function inputsOf(row) {
  const items = row.inputItems || [];
  if (!items.length) { return ''; }
  return items.map(function (it) {
    return (it.count || 1) + ' ' + clean(it.name || it.item);
  }).join(', ');
}

function write(file, body) {
  fs.writeFileSync(path.join(OUT, file), body, 'utf8');
}

function head(title, from, what) {
  return '# ' + title + '\n\n' +
    'Generated from `' + from + '` by `scripts/dev/Write-SystemLists.js`. ' +
    what + '\n\n';
}

const recipes = JSON.parse(fs.readFileSync(RECIPES, 'utf8'));
const harvests = JSON.parse(fs.readFileSync(HARVESTS, 'utf8'));
const ores = JSON.parse(fs.readFileSync(ORES, 'utf8'));
const hunts = JSON.parse(fs.readFileSync(HUNTS, 'utf8'));
const races = JSON.parse(fs.readFileSync(RACES, 'utf8'));

fs.mkdirSync(OUT, { recursive: true });

const ranks = ['novice', 'advanced', 'expert', 'master'];
const byHalf = {};
const anybody = [];
const refused = [];
const raceRows = [];

Object.keys(recipes.recipes || {}).forEach(function (id) {
  const row = recipes.recipes[id];
  row._id = id;
  if (row.race) { raceRows.push(row); }
  if (!row.owner || !row.half) { anybody.push(row); return; }
  const key = row.owner + '/' + row.half;
  if (!byHalf[key]) { byHalf[key] = []; }
  byHalf[key].push(row);
});

Object.keys(recipes.unowned || {}).forEach(function (id) {
  const row = recipes.unowned[id];
  row._id = id;
  anybody.push(row);
});

Object.keys(recipes.refused || {}).forEach(function (id) {
  const row = recipes.refused[id];
  row._id = id;
  refused.push(row);
});

function recipeTable(rows) {
  const lines = ['| Item | Makes | Rank | Kind | Bench | Asks for | Gold | Race | Server asked | Id |',
    '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |'];
  rows.sort(function (a, b) {
    const ar = ranks.indexOf(a.rank);
    const br = ranks.indexOf(b.rank);
    if (ar !== br) { return ar - br; }
    const af = clean(a.family);
    const bf = clean(b.family);
    if (af !== bf) { return af < bf ? -1 : 1; }
    const an = clean(a.name);
    const bn = clean(b.name);
    if (an !== bn) { return an < bn ? -1 : 1; }
    return clean(a.editorId) < clean(b.editorId) ? -1 : 1;
  });
  rows.forEach(function (row) {
    lines.push('| ' + [
      clean(row.name || row.editorId),
      row.makes || 1,
      clean(row.rank),
      clean(row.family),
      benchShort(row.benchName),
      inputsOf(row),
      row.worth == null ? '' : row.worth,
      clean(row.race),
      row.fires === false ? 'no' : 'yes',
      '`' + clean(row._id) + '`'
    ].join(' | ') + ' |');
  });
  return lines.join('\n') + '\n';
}

const index = ['# Recipe and work lists', '',
  'Every row the recipe, harvest, ore and hunt tables currently hold. ' +
  'The pages that say what a profession or a class is are next to this folder. ' +
  'These lists are the items.',
  ''];

Object.keys(byHalf).sort().forEach(function (key) {
  const rows = byHalf[key];
  const file = key.toLowerCase().replace(/[^a-z0-9]+/g, '-') + '.md';
  const asked = rows.filter(function (r) { return r.fires !== false; }).length;
  let body = head(key, 'game/data/recipes.json',
    rows.length + ' recipes, ' + asked + ' of them reach the server. ' +
    'A row the server is not asked about is tempering: the armour table and the grindstone never call the server.');
  const byRank = {};
  rows.forEach(function (r) {
    const k = r.rank || 'unranked';
    byRank[k] = (byRank[k] || 0) + 1;
  });
  body += 'By rank: ' + ranks.map(function (r) {
    return r + ' ' + (byRank[r] || 0);
  }).join(', ') + '.\n\n';
  body += recipeTable(rows);
  write(file, body);
  index.push('- [' + key + '](' + file + ') (' + rows.length + ', ' + asked + ' reach the server)');
});

anybody.sort(function (a, b) { return clean(a.name) < clean(b.name) ? -1 : 1; });
write('anybody.md', head('Anybody may make these', 'game/data/recipes.json',
  anybody.length + ' recipes with no profession. Smelting and tanning live here.') +
  recipeTable(anybody));
index.push('- [Anybody](anybody.md) (' + anybody.length + ')');

let refusedBody = head('Refused', 'game/data/recipes.json',
  refused.length + ' recipes the server refuses. House nails, hinges, locks and fittings.');
refusedBody += '| Item | Bench | Why | Id |\n| --- | --- | --- | --- |\n';
refused.forEach(function (row) {
  refusedBody += '| ' + clean(row.name) + ' | ' + benchShort(row.benchName) + ' | ' +
    clean(row.why) + ' | `' + clean(row._id) + '` |\n';
});
write('refused.md', refusedBody);
index.push('- [Refused](refused.md) (' + refused.length + ')');

raceRows.sort(function (a, b) {
  if (clean(a.race) !== clean(b.race)) { return clean(a.race) < clean(b.race) ? -1 : 1; }
  return clean(a.name) < clean(b.name) ? -1 : 1;
});
let raceBody = head('Race locked recipes', 'game/data/recipes.json',
  raceRows.length + ' recipes carry a race. Only the named race can make them. ' +
  'A material named for a people, such as Elven or Orcish or Nordic Carved, is not in this list.');
let lastRace = '';
raceRows.forEach(function (row) {
  if (row.race !== lastRace) {
    lastRace = row.race;
    raceBody += '\n## ' + clean(row.race) + '\n\n';
  }
  raceBody += '- ' + clean(row.name) + ' (' + clean(row.rank) + ', ' +
    clean(row.owner || 'anybody') + '/' + clean(row.half || 'none') + ', `' +
    clean(row._id) + '`)\n';
});
write('race-locks.md', raceBody);
index.push('- [Race locks](race-locks.md) (' + raceRows.length + ')');

const playable = [];
Object.keys(races.items || {}).forEach(function (id) {
  const r = races.items[id];
  if (r.p) { playable.push(clean(r.n || r.e) + ' (`' + id + '`)'); }
});
playable.sort();
write('playable-races.md', head('Races a person can be', 'game/data/races.json',
  playable.length + ' races have the playable bit set.') +
  playable.map(function (n) { return '- ' + n; }).join('\n') + '\n');
index.push('- [Playable races](playable-races.md) (' + playable.length + ')');

function distinctWork(title, from, bag, extra) {
  const groups = {};
  Object.keys(bag).forEach(function (id) {
    const row = bag[id];
    const name = clean(row.name || id);
    if (!groups[name]) {
      groups[name] = { name: name, rank: row.rank, n: 0, gives: {}, yield: row.yield };
    }
    groups[name].n++;
    (row.gives || []).forEach(function (g) {
      groups[name].gives[clean(g.name)] = true;
    });
  });
  const rows = Object.keys(groups).map(function (k) { return groups[k]; });
  rows.sort(function (a, b) {
    const ar = ranks.indexOf(a.rank);
    const br = ranks.indexOf(b.rank);
    if (ar !== br) { return ar - br; }
    return a.name < b.name ? -1 : 1;
  });
  let body = head(title, from, rows.length + ' distinct names, ' +
    Object.keys(bag).length + ' placed records. ' + (extra || ''));
  body += '| Name | Rank | Records | Gives | Yield novice, advanced, expert, master |\n| --- | --- | --- | --- | --- |\n';
  rows.forEach(function (row) {
    const gives = Object.keys(row.gives).sort().join(', ');
    let y = '';
    if (row.yield) {
      y = row.yield.map(function (pair) { return pair[0] + '-' + pair[1]; }).join(', ');
    }
    body += '| ' + row.name + ' | ' + clean(row.rank) + ' | ' + row.n + ' | ' +
      gives + ' | ' + y + ' |\n';
  });
  return { body: body, names: rows.length, records: Object.keys(bag).length };
}

const classFiles = [
  ['miner.md', 'Miner', 'game/data/ores.json', ores.ores,
    'A pair of zeroes means that rank cannot work the seam. Yield is least-most per swing.'],
  ['gatherer.md', 'Gatherer', 'game/data/harvests.json', harvests.harvests,
    'Reagents. Food plants are the farmer\'s unless the harvest table keeps them here.'],
  ['farmer.md', 'Farmer', 'game/data/harvests.json', harvests.crops,
    'Ranked by how hard the crop is to grow, not by what it sells for.'],
  ['fisher.md', 'Fisher', 'game/data/harvests.json', harvests.fish,
    'Pressed at the water. No rod.'],
  ['hunter.md', 'Hunter', 'game/data/hunts.json', hunts.hunts,
    'Only a hunter loots the body. Yield is least-most of each part.']
];

classFiles.forEach(function (spec) {
  const got = distinctWork(spec[1], spec[2], spec[3] || {}, spec[4]);
  write(spec[0], got.body);
  index.push('- [' + spec[1] + '](' + spec[0] + ') (' + got.names + ' names, ' + got.records + ' records)');
});

if (harvests.game) {
  const got = distinctWork('Eggs and wild food', 'game/data/harvests.json', harvests.game,
    'The harvest table\'s game list, separate from a hunter\'s carcass.');
  write('wild-food.md', got.body);
  index.push('- [Eggs and wild food](wild-food.md) (' + got.names + ')');
}
if (harvests.unranked) {
  const got = distinctWork('Unranked world plants', 'game/data/harvests.json', harvests.unranked,
    'In the harvest table and not on a class ladder.');
  write('unranked.md', got.body);
  index.push('- [Unranked](unranked.md) (' + got.names + ')');
}

index.push('');
write('README.md', index.join('\n') + '\n');
console.log('wrote ' + fs.readdirSync(OUT).length + ' files to ' + OUT);
