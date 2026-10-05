// Write-CutItems.js
//
// Builds docs/systems/cut-items.md and docs/systems/cut-items.json from the
// recipe table. It does not edit recipes.json. The markdown is the plan for
// what leaves the open craft book. The json is the same list, one row per
// reference, so a row can be put back for an event without hunting the plugin.
//
// A TABLE THAT IS ALREADY CUT (issue #1714). The rules below sorted the table
// once, before anything was cut (#1391), and wrote 3342 references. Since #1622
// Build-RecipeTable.ps1 reads cut-items.json and writes a table that is already
// cut: a cut row nobody owned is in the refused map, and the rows kept after the
// first pass have owners (the smelt and leather rows, #1400; the kits, #1384;
// the poles and the trap, #1379). The rules read that table wrongly. Measured
// on 5 October: 231 cut rows dropped out of the list because they are refused
// now, and 20 kept rows were cut because they are owned now, so a recipe build
// after this would have put 231 rows back in the open book and taken 20 out.
// So on a table that is already cut this starts from the cut file it has and
// writes both files from that list. The rules run only on a table with nothing
// cut, and that table only exists before the first cut.
//
//   node scripts/dev/Write-CutItems.js
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..', '..');
const recipes = JSON.parse(fs.readFileSync(path.join(ROOT, 'game', 'data', 'recipes.json'), 'utf8'));
const CUT_JSON = path.join(ROOT, 'docs', 'systems', 'cut-items.json');
const cutFile = fs.existsSync(CUT_JSON) ? JSON.parse(fs.readFileSync(CUT_JSON, 'utf8')) : null;

// Cut means the recipe build has applied a cut file to it: an owned row marked
// out of the open book or onto a roll, or a refused row the cut file names.
function tableIsCut() {
  const ids = {};
  ((cutFile && cutFile.items) || []).forEach(function (item) { ids[item.id] = true; });
  const owned = recipes.recipes || {};
  for (const id in owned) {
    if (owned[id].book === 'cut' || owned[id].roll) { return true; }
  }
  for (const id in (recipes.refused || {})) {
    if (ids[id]) { return true; }
  }
  return false;
}
const ALREADY_CUT = tableIsCut();
if (ALREADY_CUT && !cutFile) {
  console.log('STOP. game/data/recipes.json is already cut and there is no docs/systems/cut-items.json to start from.');
  console.log('The rules cannot sort a table that is already cut, so nothing was written.');
  process.exit(1);
}

function clean(s) {
  return String(s == null ? '' : s)
    .replace(/\u2014/g, ',')
    .replace(/\u2013/g, '-')
    .replace(/\|/g, '/')
    .replace(/\r?\n/g, ' ')
    .trim();
}

const BOOK_SPELLS = [
  'Flames', 'Frostbite', 'Sparks', 'Firebolt', 'Ice Spike', 'Lightning Bolt',
  'Ice Storm', 'Soul Trap', 'Turn Greater Undead', 'Icy Spear', 'Incinerate',
  'Thunderbolt', 'Turn Undead'
];
const bookFlat = {};
BOOK_SPELLS.forEach(function (name) {
  bookFlat[name.toLowerCase().replace(/[^a-z0-9]/g, '')] = name;
});

function spellEditor(row) {
  const needs = row.needs || [];
  for (let i = 0; i < needs.length; i++) {
    if (needs[i].ofType === 'SPEL') { return clean(needs[i].of); }
  }
  return '';
}

function inBook(editorId) {
  if (!editorId) { return ''; }
  const key = editorId.toLowerCase().replace(/[^a-z0-9]/g, '');
  return bookFlat[key] || '';
}

const ARMOR_KEEP = new Set([
  'Iron Armor', 'Iron Boots', 'Iron Gauntlets', 'Iron Helmet', 'Iron Shield',
  'Hide Armor', 'Hide Boots', 'Hide Bracers', 'Hide Helmet', 'Hide Shield',
  'Leather Armor', 'Leather Boots', 'Leather Bracers', 'Leather Helmet',
  'Steel Armor', 'Steel Helmet', 'Steel Shield', 'Steel Imperial Gauntlets', 'Steel Shin Boots',
  'Steel Plate Armor', 'Steel Plate Boots', 'Steel Plate Gauntlets', 'Steel Plate Helmet',
  'Elven Armor', 'Elven Boots', 'Elven Gauntlets', 'Elven Helmet', 'Elven Shield',
  'Glass Armor', 'Glass Boots', 'Glass Gauntlets', 'Glass Helmet', 'Glass Shield',
  'Ebony Armor', 'Ebony Boots', 'Ebony Gauntlets', 'Ebony Helmet', 'Ebony Shield',
  'Orcish Armor', 'Orcish Boots', 'Orcish Gauntlets', 'Orcish Helmet', 'Orcish Shield',
  'Dwarven Armor', 'Dwarven Boots', 'Dwarven Gauntlets', 'Dwarven Helmet', 'Dwarven Shield',
  'Nordic Carved Armor', 'Nordic Carved Boots', 'Nordic Carved Gauntlets', 'Nordic Carved Helmet', 'Nordic Shield',
  'Stalhrim Armor', 'Stalhrim Boots', 'Stalhrim Gauntlets', 'Stalhrim Helmet',
  'Stalhrim Light Armor', 'Stalhrim Light Boots', 'Stalhrim Light Bracers', 'Stalhrim Light Helmet', 'Stalhrim Shield',
  'Ancient Nord Armor', 'Ancient Nord Boots', 'Ancient Nord Gauntlets', 'Ancient Nord Helmet',
  'Bonemold Armor', 'Bonemold Helmet', 'Bonemold Gauntlets', 'Bonemold Boots', 'Bonemold Shield',
  'Chitin Armor', 'Chitin Boots', 'Chitin Bracers', 'Chitin Helmet', 'Chitin Shield',
  'Chitin Heavy Armor', 'Chitin Heavy Boots', 'Chitin Heavy Gauntlets', 'Chitin Heavy Helmet',
  'Falmer Armor', 'Falmer Boots', 'Falmer Gauntlets', 'Falmer Helmet', 'Falmer Shield',
  'Falmer Heavy Armor', 'Falmer Heavy Boots', 'Falmer Heavy Gauntlets', 'Falmer Heavy Helm',
  'Scaled Armor', 'Scaled Helmet', 'Scaled Bracers', 'Scaled Boots',
  'Fur Armor', 'Fur Boots', 'Fur Bracers', 'Fur Helmet',
  'Wolf Armor', 'Wolf Boots', 'Wolf Gauntlets', 'Wolf Helmet', 'Wolf Shield',
  'Banded Iron Armor', 'Banded Iron Shield'
]);

const EMBASSY_KEEP = new Set([
  'Imperial Light Armor', 'Imperial Light Boots', 'Imperial Light Bracers', 'Imperial Light Helmet', 'Imperial Light Shield',
  'Imperial Soldier\'s Armor', 'Imperial Boots', 'Imperial Bracers', 'Imperial Helmet', 'Imperial Heavy Shield'
]);

const RIEKLING_KEEP = new Set([
  'Riekling Fur Armour', 'Riekling Fur Boots', 'Riekling Fur Gauntlets', 'Riekling Fur Cloak', 'Riekling Horned Helmet',
  'Riekling Chief Fur Iron Armour', 'Riekling Chief Helmet',
  'Riekling Spear', 'Riekling Bone Club'
]);

const ARROW_KEEP = new Set([
  'Iron Arrow', 'Steel Arrow', 'Dwarven Arrow', 'Elven Arrow', 'Orcish Arrow',
  'Glass Arrow', 'Ebony Arrow', 'Nordic Arrow', 'Stalhrim Arrow', 'Falmer Arrow',
  'Steel Bolt', 'Dwarven Bolt', 'Crossbow', 'Dwarven Crossbow'
]);

const WEAPON_METALS = [
  'Skyforge Steel', 'Ancient Nord', 'Nordic', 'Stalhrim', 'Dwarven', 'Orcish',
  'Elven', 'Ebony', 'Glass', 'Steel', 'Iron', 'Silver', 'Falmer'
];
const WEAPON_TYPE = {
  'Swords': 'Sword',
  'Greatswords': 'Greatsword',
  'Daggers': 'Dagger',
  'War axes': 'War Axe',
  'Battleaxes': 'Battleaxe',
  'Maces': 'Mace',
  'Warhammers': 'Warhammer',
  'Bows': 'Bow'
};

function isDragon(name) {
  const n = name.toLowerCase();
  return n.indexOf('dragonbone') !== -1 || n.indexOf('dragon bone') !== -1 ||
    n.indexOf('dragonscale') !== -1 || n.indexOf('dragon scale') !== -1 ||
    n.indexOf('dragonplate') !== -1 || n.indexOf('dragon plate') !== -1 ||
    n.indexOf('dragonsteel') !== -1 || n.indexOf('dragon steel') !== -1 ||
    n.indexOf('dragonhide') !== -1 || n.indexOf('dragon hide') !== -1 ||
    n.indexOf('alduin') !== -1 || n.indexOf('dragon armor') !== -1 ||
    n.indexOf('dragon armour') !== -1;
}

function isDaedra(name) {
  const n = name.toLowerCase();
  return n.indexOf('daedric') !== -1 || n.indexOf('daedra') !== -1 ||
    n.indexOf('aether') !== -1 || n.indexOf('boethiah') !== -1 ||
    n.indexOf('mehrunes') !== -1 || n.indexOf('azura') !== -1 ||
    n.indexOf('molag') !== -1 || n.indexOf('vaermina') !== -1 ||
    n.indexOf('nocturnal') !== -1 || n.indexOf('clavicus') !== -1 ||
    n.indexOf('sheogorath') !== -1 || n.indexOf('sanguine') !== -1 ||
    n.indexOf('namira') !== -1 || n.indexOf('meridia') !== -1 ||
    n.indexOf('peryite') !== -1 || n.indexOf('hircine') !== -1 ||
    n.indexOf('mephala') !== -1 || n.indexOf('malacath') !== -1 ||
    n.indexOf('hermaeus') !== -1;
}

function isThalmor(name) {
  const n = name.toLowerCase();
  return n.indexOf('thalmor') !== -1 || n.indexOf('justiciar') !== -1;
}

function isImperial(name) {
  return name.indexOf('Imperial') !== -1 || name.indexOf('Penitus') !== -1;
}

function isRiekling(name) {
  return name.toLowerCase().indexOf('riekling') !== -1;
}

function isCloak(name) {
  const n = name.toLowerCase();
  return n.indexOf('cloak') !== -1 || n.indexOf('cape') !== -1;
}

const CULTURE_KEEP = new Set([
  'Bosmer Cuirass', 'Bosmer Boots', 'Bosmer Bracers', 'Bosmer Helmet',
  'Stormcloak Cuirass', 'Stormcloak Helmet',
  'Forsworn Armor', 'Forsworn Boots', 'Forsworn Gauntlets', 'Forsworn Headdress',
  'Forsworn Sword', 'Forsworn Axe',
  'Dawnguard Armor', 'Dawnguard Boots', 'Dawnguard Gauntlets', 'Dawnguard Full Helmet', 'Dawnguard Shield',
  'Dawnguard Heavy Armor', 'Dawnguard Heavy Boots', 'Dawnguard Heavy Gauntlets',
  'Tribunal Heavy Robe Black', 'Tribunal Heavy Hood Black', 'Tribunal Heavy Gloves Black', 'Tribunal Heavy Boots Black',
  'Tribunal Light Robe Black', 'Tribunal Light Hood Black', 'Tribunal Light Gloves Black', 'Tribunal Light Boots Black',
  'Wolf Sword'
]);

const GOODS_KEEP = new Set([
  'Woodcutter\'s Axe', 'Shovel', 'Pickaxe',
  'Fishing Pole - Crude', 'Fishing Pole - Fine', 'Fishing Pole - Master',
  'Drum', 'Flute', 'Lute', 'Key', 'Key Mold'
]);

function plainWeapon(name, family) {
  const type = WEAPON_TYPE[family];
  if (!type) { return false; }
  for (let i = 0; i < WEAPON_METALS.length; i++) {
    if (name === WEAPON_METALS[i] + ' ' + type) { return true; }
  }
  return false;
}

// On a table that is already cut the rules have nothing to read: see the top.
const owned = [];
if (!ALREADY_CUT) {
  Object.keys(recipes.recipes).forEach(function (id) {
    const row = recipes.recipes[id];
    row._id = id;
    owned.push(row);
  });
}

const cuts = [];
const kept = [];
const seen = {};

function record(row, disposition, why) {
  if (seen[row._id]) { return; }
  seen[row._id] = true;
  const item = {
    id: row._id,
    name: clean(row.name || row.editorId || ''),
    plugin: clean(row.plugin || ''),
    half: clean(row.half || ''),
    owner: clean(row.owner || ''),
    family: clean(row.family || ''),
    rank: clean(row.rank || ''),
    fires: row.fires === false ? false : true,
    disposition: disposition,
    why: why
  };
  if (disposition === 'keep') { kept.push(item); }
  else { cuts.push(item); }
}

owned.forEach(function (row) {
  if (row.fires === false) {
    const bench = String(row.benchName || '');
    if (bench.indexOf('SharpeningWheel') !== -1 || bench.indexOf('ArmorTable') !== -1) {
      record(row, 'cut', 'Temper on the grindstone or the armour table. Repair is a kit. Not found and not made. The reference stays here so it can come back for an event.');
    }
    return;
  }
  const name = row.name || '';

  if (isThalmor(name)) {
    record(row, 'thalmor', 'Thalmor or Justiciar. Not found in the world. Only someone on the remnant roll may craft it.');
    return;
  }
  if (isRiekling(name)) {
    if (RIEKLING_KEEP.has(name)) {
      record(row, 'keep', 'Riekling set that stays: race locked, and a company ware.');
    } else {
      record(row, 'cut', 'Extra Riekling copy of someone else\'s gear, or a spare piece. Not found and not made.');
    }
    return;
  }
  if (isDragon(name) || isDaedra(name)) {
    record(row, 'cut', 'Dragon, Daedric, or Aetherium. Not found and not made. The reference stays here so it can come back for an event.');
    return;
  }
  if (isImperial(name)) {
    if (EMBASSY_KEEP.has(name) || name.indexOf('Penitus') !== -1 || isCloak(name)) {
      record(row, 'embassy', 'Empire gear. Not found in Skyrim. Only the embassy roll may craft it.');
    } else {
      record(row, 'cut', 'Extra Imperial shape beyond one heavy set and one light set. Not found and not made.');
    }
    return;
  }
  if (row.half === 'Bladebinder') {
    const spell = spellEditor(row);
    const book = inBook(spell);
    if (book) {
      record(row, 'keep', 'Staff whose spell is in the college book: ' + book + '.');
    } else {
      record(row, 'cut', 'Staff whose spell is not in the college book' + (spell ? ' (' + spell + ')' : '') + '. Not found and not made.');
    }
    return;
  }
  if (isCloak(name)) {
    record(row, 'keep', 'Cloak or cape. They stay craftable. A second plugin row of the same name is dropped below.');
    return;
  }
  if (ARMOR_KEEP.has(name) || CULTURE_KEEP.has(name) || plainWeapon(name, row.family) || ARROW_KEEP.has(name)) {
    record(row, 'keep', 'The one piece kept for this material, culture, or type.');
    return;
  }
  if (row.family === 'Arrows and bolts' || name === 'Crossbow' || name.indexOf('Bolt') !== -1 && row.half === 'Woodwright') {
    record(row, 'cut', 'Extra ammunition or an extra crossbow. Plain arrows, plain bolts, and one crossbow per metal stay.');
    return;
  }
  if (row.owner === 'Cook') {
    record(row, 'cook', 'Cook row, sorted into keep or duplicate below.');
    return;
  }
  if (row.half === 'Charburner' || GOODS_KEEP.has(name)) {
    record(row, 'keep', 'Kiln good, tool, fishing pole, or instrument. The job stays.');
    return;
  }
  if (row.owner === 'Tailor') {
    record(row, 'keep', 'Clothing, a robe, or a tailor good. The tailor book stays. Extra armour is a smith row, not this one.');
    return;
  }
  if (row.owner === 'Smith' || row.owner === 'Woodworker' || row.owner === 'Enchanter') {
    record(row, 'cut', 'Extra suit, extra weapon shape, or a named unique. One piece per material and type stays in the open book. This one does not. Not found and not made.');
    return;
  }
  record(row, 'keep', 'Not covered by a cut rule.');
});

// Cook: one row per dish name. Prefer the row that makes 1.
const cookRows = [];
cuts.forEach(function (item) {
  if (item.disposition !== 'cook') { return; }
  cookRows.push(item);
});
const cookByName = {};
cookRows.forEach(function (item) {
  const row = recipes.recipes[item.id];
  if (!cookByName[item.name]) { cookByName[item.name] = []; }
  cookByName[item.name].push(row);
});
Object.keys(cookByName).forEach(function (name) {
  const rows = cookByName[name];
  rows.sort(function (a, b) {
    const am = a.makes || 1;
    const bm = b.makes || 1;
    if (am !== bm) { return am - bm; }
    return a._id < b._id ? -1 : 1;
  });
  rows.forEach(function (row, index) {
    const item = cuts.filter(function (c) { return c.id === row._id; })[0];
    if (index === 0) {
      item.disposition = 'keep';
      item.why = 'The one row kept for this dish.';
      kept.push(item);
    } else {
      item.disposition = 'cut';
      item.why = 'Duplicate of the same dish. The other row stays. This reference is here if the second portion is wanted back.';
    }
  });
});

function dedupeScore(item) {
  const id = item.id || '';
  if (id.indexOf('MoreCraftableEquipment_CloaksandCapes') !== -1) { return 2; }
  if (id.indexOf('Cloaks&Capes.esp') !== -1) { return 0; }
  if (id.indexOf('Skyrim.esm') !== -1) { return 0; }
  return 1;
}

function shouldDedupe(item) {
  if (item.disposition !== 'keep') { return false; }
  if (isCloak(item.name)) { return true; }
  if (ARMOR_KEEP.has(item.name) || CULTURE_KEEP.has(item.name) || ARROW_KEEP.has(item.name)) { return true; }
  return false;
}

const dupeGroups = {};
kept.forEach(function (item) {
  if (!shouldDedupe(item)) { return; }
  if (!dupeGroups[item.name]) { dupeGroups[item.name] = []; }
  dupeGroups[item.name].push(item);
});
Object.keys(dupeGroups).forEach(function (name) {
  const rows = dupeGroups[name];
  if (rows.length < 2) { return; }
  rows.sort(function (a, b) {
    const as = dedupeScore(a);
    const bs = dedupeScore(b);
    if (as !== bs) { return as - bs; }
    return a.id < b.id ? -1 : 1;
  });
  rows.forEach(function (item, index) {
    if (index === 0) { return; }
    item.disposition = 'cut';
    item.why = 'Duplicate row of ' + name + '. One row stays. This reference is here if the second copy is wanted back.';
    cuts.push(item);
  });
});

// Unowned ingots and leather: one row per name, dragon and daedra cut entirely.
const unowned = [];
if (!ALREADY_CUT) {
  Object.keys(recipes.unowned || {}).forEach(function (id) {
    const row = recipes.unowned[id];
    row._id = id;
    unowned.push(row);
  });
}

function isSmelt(name) {
  if (!name) { return false; }
  if (name.indexOf('Ingot') !== -1) { return true; }
  if (name === 'Refined Malachite' || name === 'Refined Moonstone') { return true; }
  if (name === 'Leather' || name === 'Leather Strips') { return true; }
  if (name === 'Dragon Bone' || name === 'Dragon Scales') { return true; }
  return false;
}

const smeltByName = {};
unowned.forEach(function (row) {
  const name = row.name || '';
  if (!isSmelt(name)) { return; }
  if (!smeltByName[name]) { smeltByName[name] = []; }
  smeltByName[name].push(row);
});
Object.keys(smeltByName).forEach(function (name) {
  const rows = smeltByName[name];
  if (isDragon(name) || isDaedra(name)) {
    rows.forEach(function (row) {
      record(row, 'cut', 'Dragon or Daedric material. Not smelted. Not found and not made.');
    });
    return;
  }
  rows.sort(function (a, b) {
    const as = (a._id || '').indexOf('Skyrim.esm') !== -1 ? 0 : 1;
    const bs = (b._id || '').indexOf('Skyrim.esm') !== -1 ? 0 : 1;
    if (as !== bs) { return as - bs; }
    return a._id < b._id ? -1 : 1;
  });
  rows.forEach(function (row, index) {
    if (index === 0) {
      record(row, 'keep', 'The one smelt or tan row kept for this material. It belongs to a smith half, not to anybody.');
    } else {
      record(row, 'cut', 'Duplicate smelt or tan row for ' + name + '. One row stays.');
    }
  });
});

const outCuts = ALREADY_CUT ? cutFile.items.slice() :
  cuts.filter(function (item) { return item.disposition !== 'keep' && item.disposition !== 'cook'; });
outCuts.sort(function (a, b) {
  if (a.disposition !== b.disposition) { return a.disposition < b.disposition ? -1 : 1; }
  if (a.why !== b.why) { return a.why < b.why ? -1 : 1; }
  if (a.name !== b.name) { return a.name < b.name ? -1 : 1; }
  return a.id < b.id ? -1 : 1;
});

function countBy(list, key) {
  const bag = {};
  list.forEach(function (item) {
    const k = item[key] || '';
    bag[k] = (bag[k] || 0) + 1;
  });
  return bag;
}

const byDisp = countBy(outCuts, 'disposition');
const keptCraft = kept.filter(function (item) { return item.disposition === 'keep'; });
// The rows the first pass left in the open book. That pass is the one the count
// describes, so a table that is already cut keeps the number the file has.
const keptCount = ALREADY_CUT ? cutFile.counts.kept : keptCraft.length;

let md = '';
md += '# Cut items\n\n';
md += 'What leaves the open craft book. Nothing in `game/data/recipes.json` is deleted by this page. ';
md += 'Every reference listed here can be put back for an event, or if the cut was wrong, without hunting the plugin for the form id.\n\n';
md += 'The same rows are in [cut-items.json](cut-items.json), one object per reference.\n\n';
md += 'An item in this file is not found in the world and not made at a public bench. ';
md += 'The test server is wiped, so what is already sitting in chests does not have to be stripped by hand. ';
md += 'After that, a thing that is no longer made simply stops appearing.\n\n';
md += '## How a row is marked\n\n';
md += '| Mark | Meaning |\n| --- | --- |\n';
md += '| cut | Not found and not made. Held here. |\n';
md += '| embassy | Not found in Skyrim. The embassy roll may craft it. |\n';
md += '| thalmor | Not found. Someone on the Thalmor remnant roll may craft it. |\n\n';
md += 'Counts in this file: cut ' + (byDisp.cut || 0) + ', embassy ' + (byDisp.embassy || 0) + ', thalmor ' + (byDisp.thalmor || 0) + '. ';
md += 'Rows this pass left in the open book, or on a lock that is not a cut: ' + keptCount + '.\n\n';
md += 'The rules below sorted the recipe table once, before anything was cut. The recipe build ';
md += '(`scripts/dev/Build-RecipeTable.ps1`) reads [cut-items.json](cut-items.json), so the table it writes is already cut, ';
md += 'and `scripts/dev/Write-CutItems.js` run on that table writes this page from the list it has instead of sorting the table again.\n\n';
md += '## Rules that built the lists\n\n';
md += 'One suit per material. Where a material has a heavy set and a light set, both stay. ';
md += 'A suit is body, head, hands, and feet. Shields are fewer than suits: one shield named Shield, not the buckler and not the painted variants.\n\n';
md += 'One weapon per type per metal. The type is sword, greatsword, dagger, war axe, battleaxe, mace, warhammer, or bow. ';
md += 'The name that stays is the plain one, such as Iron Sword. Cutlass, katana, scimitar, and the other shapes of that same metal are cut. ';
md += 'None of those shapes are standing company wares. A company event can bring one named shape back for that event, and then it leaves again.\n\n';
md += 'One set per culture. Bosmer keeps the plain set, not the engraved or the reinforced. Stormcloak keeps the plain cuirass and helmet. Forsworn keeps one set, a sword and an axe. Dawnguard keeps one light set and one heavy set. Tribunal keeps the black heavy set and the black light set. Wolf keeps the wolf set and the Wolf Sword. The other colors and the officer and heroic variants are cut.\n\n';
md += 'Named uniques, Chillrend and Dawnbreaker and the rest, are cut. They are not found either. A piece named for a Daedric prince is cut with the Daedric.\n\n';
md += 'The kiln stays: poor charcoal, the tool handle, charcoal, briquette, and coke. The woodcutter\'s axe, the shovel, the fishing poles, and the drum, flute and lute stay.\n\n';
md += 'Dragonbone, dragonscale, dragonplate, dragonsteel, Alduin scale, Daedric, and Aetherium are cut, including the ingots.\n\n';
md += 'Glass, ebony, and stalhrim stay craftable. They are the scarce metals. Stalhrim keeps both the heavy set and the light set.\n\n';
md += 'Cloaks and capes stay, all of them. A second plugin row of the same cloak is a duplicate and is cut. Clothing, robes, hats, shoes, gloves and aprons stay with the tailor. They are not extra armour. That includes the five colors of Tribunal unarmored clothes. Those are garments, not a second suit of plate.\n\n';
md += 'Arrows and bolts stay when they are the plain stack for a metal that stays. Exploding bolts are cut. ';
md += 'A woodwright still makes ammunition. That is the job.\n\n';
md += 'Cook dishes stay. A second row of the same dish, the two-portion copy, is cut.\n\n';
md += 'Staves stay only when the spell the menu asks for is in the college book. The others are cut. The Aetherial Staff is cut with the Aetherium.\n\n';
md += 'Riekling gear that is a copy of a human suit is cut. What stays is one light fur set, one chief set, a spear, and a bone club. ';
md += 'Those stay race locked, and they are company wares: the company may haul them, and a riekling may make them.\n\n';
md += 'Imperial and Penitus pieces are not in the open book. One heavy set and one light set, plus Penitus pieces, are embassy craft. The knight, legate, and captain variants are cut.\n\n';
md += 'Thalmor robes and Justiciar weapons are not found. The remnant roll may craft them.\n\n';
md += 'Smelting and tanning are not anybody\'s work. One row per ingot and one row for leather stay, and they belong to the smith halves. Duplicate ingot rows are cut. ';
md += 'The Hearthfire building rows, 487 of them in the unowned list, are not in this file. A house is a place already standing. They are not company wares and they are not cut.\n\n';
md += 'Tempering rows, the grindstone and the armour table, are in this file. Repair is the kit system on [Durability](durability.md). The references stay so a temper can come back for an event.\n\n';
md += '## Riekling pieces that stay\n\n';
md += 'Race locked, and company wares. Not cut.\n\n';
RIEKLING_KEEP.forEach(function (name) {
  md += '- ' + name + '\n';
});
md += '\n';

function section(title, disposition, blurb) {
  const rows = outCuts.filter(function (item) { return item.disposition === disposition; });
  let body = '## ' + title + '\n\n' + blurb + '\n\n';
  body += rows.length + ' references.\n\n';
  body += '| Item | Id | Half | Why |\n| --- | --- | --- | --- |\n';
  rows.forEach(function (item) {
    body += '| ' + item.name + ' | `' + item.id + '` | ' + (item.half || item.owner || '') + ' | ' + item.why + ' |\n';
  });
  body += '\n';
  return body;
}

md += section('Embassy craft', 'embassy',
  'Not found on a body, in a chest, or at a public forge. The embassy roll is who may make them.');
md += section('Thalmor remnant craft', 'thalmor',
  'Not found. A person on the remnant roll may make them. Wearing them is still the hostile marker.');
md += section('Cut', 'cut',
  'Not found and not made. Held here so the reference can come back.');

const json = {
  builtFrom: 'game/data/recipes.json',
  note: 'References held out of the open craft book. recipes.json is not edited by the script that writes this file.',
  counts: { cut: byDisp.cut || 0, embassy: byDisp.embassy || 0, thalmor: byDisp.thalmor || 0, kept: keptCount },
  rieklingKept: Array.from(RIEKLING_KEEP),
  items: outCuts
};

// Each file keeps the line ending it already has (LF for a new one), so a run
// that changes nothing writes the same bytes on a Windows checkout too.
const dir = path.join(ROOT, 'docs', 'systems');
function writeKeepingEol(file, text) {
  const had = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
  const eol = had.indexOf('\r\n') !== -1 ? '\r\n' : '\n';
  fs.writeFileSync(file, eol === '\n' ? text : text.split('\n').join(eol), 'utf8');
}
writeKeepingEol(path.join(dir, 'cut-items.md'), md);
writeKeepingEol(path.join(dir, 'cut-items.json'), JSON.stringify(json, null, 2) + '\n');
if (ALREADY_CUT) {
  console.log('the recipe table is already cut, so the list is the one docs/systems/cut-items.json has');
}
console.log('cut', byDisp.cut || 0, 'embassy', byDisp.embassy || 0, 'thalmor', byDisp.thalmor || 0, 'kept', keptCount);
console.log('wrote docs/systems/cut-items.md and cut-items.json');
