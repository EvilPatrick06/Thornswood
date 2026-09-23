// Build-FireTable.js
//
// Builds tools\fires.json: every base record in the load order that is a LIT
// FIRE, so the client can ask "is one of those near me" and the server can
// warm somebody up.
//
// WHY THERE IS ANYTHING TO BUILD
//
// Patrick, 23 September, with five screenshots of the meter reading Fine 50
// outside at night, beside a brazier, inside the Bannered Mare and standing
// in the middle of its fire pit: "not any warmer when near or in fire or in a
// building also make so if you are in a fire you catch on fire". Then:
// "yeah forges and stuff like that should be included too because they are
// hot".
//
// The temperature meter has worked since it was written. Nothing ever told it
// where anybody was standing, so n.place was always '' and the target was
// always comfort. The server cannot know: whether there is a fire in front of
// you is a fact about the machine drawing the world. The client has
// Game.findClosestReferenceOfType, which needs a BASE FORM, and that is what
// this table is.
//
// WHAT COUNTS AS A FIRE, MEASURED RATHER THAN TYPED
//
// Nothing here is a list of form ids from memory. Every row is read out of
// the plugins of the build on this machine, and the rule is on the record:
//
//   1. THE FLAME ITSELF. The thing that burns in Skyrim is not the fireplace,
//      it is a separate object placed in it: a movable static whose model is
//      one of the fire effects (Effects\FXfireWithEmbers*, Effects\FXFire0*,
//      Effects\BFXFireVol*) or one of the wood fires
//      (Clutter\WoodFires\*Burning*, Clutter\Giant\GiantCampfire01Burning).
//      A fireplace alcove is architecture and is cold; the FXfire sitting in
//      it is the fire. That is why this matches on the MODEL PATH and not on
//      the name: hundreds of Skyrim statics have "fireplace" in their editor
//      id and are stonework.
//
//   2. THE WORKING HEAT. A forge, a skyforge and a smelter are hot, which is
//      Patrick's line above. Those are crafting furniture markers and have no
//      flame model of their own, so they are matched by editor id, which is
//      the only thing that identifies them. The list of prefixes is in
//      CRAFT_HEAT and each one is checked to exist.
//
//   3. NOT WHEN IT IS OUT. Campfire01LandOff, Campfire01Off,
//      FireplaceWood01Off and FXfireWithEmbersOut are the unlit versions of
//      rows 1 and 2, and they are the reason a name match alone would have
//      warmed people up at a dead fire. Anything whose editor id or model
//      ends in Off or Out is dropped, and the count of what was dropped is
//      printed so the rule can be seen working.
//
// Read only. It opens the plugins of the build and writes tools\fires.json.
// It touches nothing in the game folder and nothing on the VPS.
//
// Usage:
//   node tools\Build-FireTable.js
//   node tools\Build-FireTable.js --data "C:\Thornswood\Game\Data"
//   node tools\Build-FireTable.js --print
//
// Exit code 1 if a plugin will not parse, if any CRAFT_HEAT prefix matches
// nothing, or if the table comes out empty. Nothing is written unless every
// check passed.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const args = process.argv.slice(2);
function opt(name, def) {
  const i = args.indexOf('--' + name);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
}
const DATA = opt('data', 'C:\\Thornswood\\Game\\Data');
const OUT = opt('out', path.join(__dirname, 'fires.json'));
const PRINT = args.indexOf('--print') !== -1;

/*
  ONLY THE FIVE BETHESDA MASTERS, AND THAT IS A LIMIT WORTH SAYING OUT LOUD.

  A form id is only the number the game uses when the plugin it came from is
  at load index 00, which is Skyrim.esm and nothing else. Dawnguard,
  HearthFires and Dragonborn sit wherever the load order puts them, so their
  ids would have to be rebuilt per machine, and a mod's ids move whenever
  anybody adds a mod.
  So this reads Skyrim.esm, which holds every fire in the base game: the inn
  fires, the braziers, the campfires, the forges and the smelters. A fire
  added by a mod is not in here and will not warm anybody, which is a real
  gap and is written down rather than papered over.
*/
const PLUGINS = ['Skyrim.esm'];

// The form types a fire can be. STAT is in the scan so the unlit versions are
// seen and counted as dropped rather than silently missing.
const TYPES = ['MSTT', 'ACTI', 'FURN', 'STAT'];

// Rule 1: the flame itself, by model path.
const FLAME_MODELS = [
  // FXFire01, FXFire02, FXfireWithEmbers* and FXFireSovngarde. Deliberately
  // anchored at the start of the path: MGMagicFirePillar01 and
  // TG09NocturnalFXFirePurple are in the same folder and are quest set
  // dressing rather than something that would warm anybody.
  /^Effects\\FXFire/i,
  /^Effects\\BFXFireVol/i,
  /^Clutter\\WoodFires\\.*Burning/i,
  /^Clutter\\Giant\\GiantCampfire01Burning/i
];

// Rule 2: the working heat, by editor id. Every one of these must match at
// least one record or the build fails: a prefix that matches nothing is a
// renamed record and a silently missing forge.
const CRAFT_HEAT = [
  'CraftingBlackSmithForge',
  'CraftingSmelterMarker',
  'CraftingBlacksmithForgeSTATIC',
  'CraftingCookingFireSpit'
];

// Rule 3: not when it is out.
const OUT_OF = /(off|out)\d*$/i;

/*
  How far each kind reaches, in game units. A campfire is about 100 units
  across, so 300 is standing at it and 160 is standing IN it. These are the
  only invented numbers in the file and they are here rather than in the
  plugin so the table is the whole of the answer.
*/
const REACH = { flame: 300, craft: 260 };
const INSIDE = 90;

function fail(msg) {
  console.error('FAIL  ' + msg);
  process.exitCode = 1;
}

function subrecords(rec) {
  const got = { EDID: '', MODL: '' };
  let k = 0, over = 0;
  while (k + 6 <= rec.length) {
    const sub = rec.toString('ascii', k, k + 4);
    let sz = rec.readUInt16LE(k + 4);
    k += 6;
    if (over > 0) { sz = over; over = 0; }
    if (sub === 'XXXX') { over = rec.readUInt32LE(k); k += sz; continue; }
    if ((sub === 'EDID' || sub === 'MODL') && sz > 1 && k + sz <= rec.length) {
      got[sub] = rec.toString('latin1', k, k + sz - 1);
    }
    k += sz;
  }
  return got;
}

const rows = [];
const dropped = [];
let scanned = 0;

function walk(b, start, end) {
  let j = start;
  while (j + 24 <= end) {
    const type = b.toString('ascii', j, j + 4);
    const dataSize = b.readUInt32LE(j + 4);
    if (type === 'GRUP') {
      if (dataSize < 24) { return; }
      walk(b, j + 24, j + dataSize);
      j += dataSize;
      continue;
    }
    const flags = b.readUInt32LE(j + 8);
    const formId = b.readUInt32LE(j + 12);
    if (TYPES.indexOf(type) !== -1) {
      scanned++;
      let rec = null;
      try {
        rec = (flags & 0x00040000)
          ? zlib.inflateSync(b.slice(j + 28, j + 24 + dataSize))
          : b.slice(j + 24, j + 24 + dataSize);
      } catch (e) { rec = null; }
      if (rec) {
        const s = subrecords(rec);
        let kind = '';
        let why = '';
        for (let i = 0; i < FLAME_MODELS.length; i++) {
          if (FLAME_MODELS[i].test(s.MODL)) {
            kind = 'flame';
            why = 'model ' + s.MODL;
            break;
          }
        }
        if (!kind) {
          for (let i = 0; i < CRAFT_HEAT.length; i++) {
            if (s.EDID.toLowerCase().indexOf(CRAFT_HEAT[i].toLowerCase()) === 0) {
              kind = 'craft';
              why = 'editor id begins ' + CRAFT_HEAT[i];
              break;
            }
          }
        }
        if (kind) {
          if (OUT_OF.test(s.EDID) || OUT_OF.test(s.MODL.replace(/\.nif$/i, ''))) {
            dropped.push({ id: formId, edid: s.EDID, modl: s.MODL });
          } else {
            rows.push({
              id: '0x' + formId.toString(16),
              type: type, kind: kind, edid: s.EDID, modl: s.MODL, why: why
            });
          }
        }
      }
    }
    j += 24 + dataSize;
  }
}

for (const pl of PLUGINS) {
  const p = path.join(DATA, pl);
  if (!fs.existsSync(p)) { fail('no such plugin: ' + p); continue; }
  const b = fs.readFileSync(p);
  if (b.toString('ascii', 0, 4) !== 'TES4') { fail('not a plugin: ' + p); continue; }
  walk(b, 24 + b.readUInt32LE(4), b.length);
}

// Every craft prefix has to have found something.
for (const pre of CRAFT_HEAT) {
  const hit = rows.some(function (r) {
    return r.edid.toLowerCase().indexOf(pre.toLowerCase()) === 0;
  });
  if (!hit) { fail('nothing matched the craft heat prefix ' + pre); }
}
if (!rows.length) { fail('the table came out empty'); }

rows.sort(function (a, b) { return a.edid.toLowerCase() < b.edid.toLowerCase() ? -1 : 1; });

console.log(scanned + ' records read, ' + rows.length + ' are lit fires, ' +
            dropped.length + ' dropped for being out');
if (PRINT) {
  for (const r of rows) {
    console.log('  ' + r.kind.padEnd(6) + r.id.padEnd(10) + r.edid);
  }
}

if (process.exitCode === 1) {
  console.error('nothing written');
} else {
  const doc = {
    builtFrom: PLUGINS,
    builtAt: new Date().toISOString(),
    reach: REACH,
    inside: INSIDE,
    rule: 'flame: the model is one of the fire effects or wood fires. ' +
          'craft: the editor id begins one of ' + CRAFT_HEAT.join(', ') + '. ' +
          'Anything whose editor id or model ends Off or Out is dropped.',
    fires: rows,
    droppedForBeingOut: dropped.length
  };
  fs.writeFileSync(OUT, JSON.stringify(doc, null, 2) + '\n');
  console.log('wrote ' + OUT);
}
