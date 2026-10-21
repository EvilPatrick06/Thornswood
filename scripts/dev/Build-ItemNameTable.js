// Build-ItemNameTable.js
//
// Writes the ITEM_NAMES block in game\gamemode.js: every item name the recipe
// table knows, as a maker or as an ingredient, with the record it names.
//
// WHY
//
// Patrick, 25 September: "Everytime I do /give Iron Ingot it says Nothing
// called that ... I think the table is missing Alot of items". /give finds
// things by name in tables that were generated for other reasons, and the
// recipes it reads, RECIPES_BY_ID, hold only the recipes a profession owns
// (1888 of them). Iron Ingot, Steel Ingot and Leather Strips come from
// recipes nobody owns and anybody may make, which are left out of that
// table on purpose, and ingredients were never read at all. This block is
// every output and every ingredient in game\data\recipes.json, owned or not.
//
// WHEN TWO RECORDS SHARE A NAME the one from the earliest plugin wins, in the
// order Skyrim.esm, Update.esm, Dawnguard.esm, HearthFires.esm, Dragonborn.esm,
// then any other plugin by name. That is the record people mean when they
// type the vanilla name. The rest are counted in the block's header.
//
// Read only except for gamemode.js, which it rewrites between the markers.
// It adds the markers after RECIPES_BY_ID the first time.
//
// Usage:
//   node scripts\dev\Build-ItemNameTable.js
//   node scripts\dev\Build-ItemNameTable.js --recipes <file> --gamemode <file>
'use strict';
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
function arg(name, dflt) { const i = args.indexOf(name); return i >= 0 && args[i + 1] ? args[i + 1] : dflt; }
const ROOT = path.join(__dirname, '..', '..');
const RECIPES = arg('--recipes', path.join(ROOT, 'game', 'data', 'recipes.json'));
const GM = arg('--gamemode', path.join(ROOT, 'game', 'gamemode.js'));

const FIRST = ['skyrim.esm', 'update.esm', 'dawnguard.esm', 'hearthfires.esm', 'dragonborn.esm'];
function pluginRank(desc) {
  const p = String(desc).split(':').slice(1).join(':').toLowerCase();
  const i = FIRST.indexOf(p);
  return i >= 0 ? [0, String(i).padStart(2, '0')] : [1, p];
}
function better(a, b) {
  const ra = pluginRank(a), rb = pluginRank(b);
  if (ra[0] !== rb[0]) return ra[0] < rb[0];
  if (ra[1] !== rb[1]) return ra[1] < rb[1];
  return a < b;
}

const data = JSON.parse(fs.readFileSync(RECIPES, 'utf8').replace(/^﻿/, ''));
const rows = data.recipes || {};
const byName = {};
let seen = 0;
const clashed = {};
function add(name, desc) {
  if (!name || !desc || typeof name !== 'string') return;
  const clean = name.replace(/\s+/g, ' ').trim();
  if (!clean) return;
  const key = clean.toLowerCase();
  seen++;
  const had = byName[key];
  if (!had) { byName[key] = { name: clean, desc: desc }; return; }
  if (had.desc === desc) return;
  clashed[key] = true;
  if (better(desc, had.desc)) byName[key] = { name: clean, desc: desc };
}
for (const id of Object.keys(rows)) {
  const r = rows[id];
  add(r.name, r.out);
  for (const i of (r.inputItems || [])) add(i.name, i.item);
}

const keys = Object.keys(byName).sort();
const clashes = Object.keys(clashed).length;
const NL = '\n';
const lines = [];
lines.push('  // ==== ITEM_NAMES ====');
lines.push('  /* Built by scripts\\dev\\Build-ItemNameTable.js out of game\\data\\recipes.json. Do not hand edit.');
lines.push('     ' + keys.length + ' item names: every recipe output and every ingredient, owned or not,');
lines.push('     out of ' + Object.keys(rows).length + ' recipes. ' + clashes + ' name(s) belong to more than one record; each went to the earliest plugin');
lines.push('     (Skyrim.esm, Update.esm, Dawnguard.esm, HearthFires.esm, Dragonborn.esm, then by name).');
lines.push('     Lower-case name -> [name as written, record]. /give reads it through buildThings. */');
lines.push('  var ITEM_NAMES = {');
keys.forEach(function (k, n) {
  lines.push('    ' + JSON.stringify(k) + ': [' + JSON.stringify(byName[k].name) + ', ' + JSON.stringify(byName[k].desc) + ']' + (n < keys.length - 1 ? ',' : ''));
});
lines.push('  };');
lines.push('  // ==== end ITEM_NAMES ====');

let src = fs.readFileSync(GM, 'utf8');
src = src.split('\r\n').join('\n');
const block = lines.join(NL);
const re = /  \/\/ ==== ITEM_NAMES ====[\s\S]*?  \/\/ ==== end ITEM_NAMES ====/;
if (re.test(src)) {
  src = src.replace(re, function () { return block; });
} else {
  const anchor = '  // ==== end RECIPES_BY_ID ====';
  if (src.indexOf(anchor) === -1) { console.error('no RECIPES_BY_ID end marker in ' + GM); process.exit(1); }
  src = src.replace(anchor, function () { return anchor + NL + NL + block; });
}
fs.writeFileSync(GM, src);
console.log('ITEM_NAMES: ' + keys.length + ' names from ' + Object.keys(rows).length + ' recipes, ' + clashes + ' shared name(s), written to ' + GM);
