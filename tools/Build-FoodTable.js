// Build-FoodTable.js
//
// Builds tools\food.json: every ALCH record in the load order that somebody
// can eat or drink, what kind it is, and whether it is alcohol.
//
// WHY THERE IS ANYTHING TO BUILD
//
// Patrick, 23 September: "I also just ate food and my food percentage didn't
// change", and then "Water percentage doesn't change".
//
// Nothing was broken. The only thing that has ever fed anybody on this server
// is typing /eat: eating in the game is the client consuming an item in its
// own inventory, the server has no eat hook, and by the time the inventory
// sync arrives the food is simply gone, which looks exactly like dropping it.
// The client watches the equip event now, because in Skyrim eating is
// equipping, and tells the server WHAT was eaten. What it is worth has to be
// the server's answer, or a client could fill its own meters by saying so,
// and this table is that answer.
//
// WHAT COUNTS, MEASURED RATHER THAN TYPED
//
//   1. IT HAS TO BE FOOD. The ALCH record's ENIT flags carry the food bit,
//      which is Bethesda's own answer to "is this a meal or a medicine". A
//      potion of healing is not a meal and does not move a meter.
//
//   2. FOOD OR DRINK IS THE NAME, AND THAT IS A JUDGEMENT. Nothing on the
//      record says which: ale, water and a sweet roll are all food items with
//      the same flag. So the rule is the name, the list is written out below,
//      and anything not matching is food, because most food is food.
//
//   3. ALCOHOL IS ALSO THE NAME, for the same reason, and it matters more:
//      Patrick asked for alcohol to be thirst-quenching, hunger-making and
//      progressively worse with each one, so the server has to know which
//      drinks are drink.
//
// Read only. It opens the plugins of the build and writes tools\food.json.
//
// Usage:
//   node tools\Build-FoodTable.js
//   node tools\Build-FoodTable.js --print
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const args = process.argv.slice(2);
function opt(name, def) {
  const at = args.indexOf('--' + name);
  return at >= 0 && args[at + 1] ? args[at + 1] : def;
}
const PRINT = args.indexOf('--print') !== -1;
const DATA = opt('data', 'C:\\Thornswood\\Game\\Data');
const OUT = opt('out', path.join(__dirname, 'food.json'));

/* The load order, the same way Build-FireTable reads it. */
function loadOrder() {
  const candidates = [
    path.join(DATA, '..', '..', 'Profile', 'Default', 'plugins.txt'),
    path.join(process.env.LOCALAPPDATA || '', 'Skyrim Special Edition', 'plugins.txt')
  ];
  for (const f of candidates) {
    if (!fs.existsSync(f)) { continue; }
    const names = fs.readFileSync(f, 'utf8').split(/\r?\n/)
      .map((l) => l.trim())
      .filter((l) => l.startsWith('*'))
      .map((l) => l.slice(1).trim())
      .filter(Boolean);
    if (names.length) {
      return ['Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm']
        .filter((n) => names.indexOf(n) === -1)
        .concat(names);
    }
  }
  return ['Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm'];
}

/*
  Rule 2 and rule 3, written out so they can be argued with.

  A drink is a thing you swallow without chewing. The list is the words
  Bethesda and the collection actually use on ALCH records; anything else with
  the food flag is food.
*/
const DRINK = /\b(ale|mead|wine|brandy|spirits?|grog|rum|liquor|beer|cider|water|milk|juice|tea|broth|soup|stew|nog|brew|flagon|bottle)\b/i;
const ALCOHOL = /\b(ale|mead|wine|brandy|spirits?|grog|rum|liquor|beer|cider|nog|firebrand|honningbrew|black-?briar)\b/i;

const FOOD_FLAG = 0x00000002;   // ENIT: this ALCH is a food item
const POISON_FLAG = 0x00020000; // ENIT: and this one is a poison

function subrecords(rec) {
  const got = { EDID: '', FULL: '', value: 0, flags: 0 };
  let k = 0, over = 0;
  while (k + 6 <= rec.length) {
    const sub = rec.toString('ascii', k, k + 4);
    let sz = rec.readUInt16LE(k + 4);
    k += 6;
    if (over > 0) { sz = over; over = 0; }
    if (sub === 'XXXX') { over = rec.readUInt32LE(k); k += sz; continue; }
    if ((sub === 'EDID' || sub === 'FULL') && sz > 1 && k + sz <= rec.length) {
      got[sub] = rec.toString('latin1', k, k + sz - 1);
    }
    // ENIT on an ALCH: value, flags, addiction, chance, sound.
    if (sub === 'ENIT' && sz >= 8 && k + sz <= rec.length) {
      got.value = rec.readUInt32LE(k);
      got.flags = rec.readUInt32LE(k + 4);
    }
    k += sz;
  }
  return got;
}

const rows = [];
const here = { file: '' };
let scanned = 0;
let notFood = 0;

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
    if (type === 'ALCH') {
      scanned++;
      let rec = null;
      try {
        rec = b.slice(j + 24, j + 24 + dataSize);
        if (flags & 0x00040000) {                      // compressed
          rec = zlib.inflateSync(rec.slice(4));
        }
      } catch (e) { rec = null; }
      if (rec) {
        const s = subrecords(rec);
        if (!(s.flags & FOOD_FLAG)) {
          /*
            A POTION IS A LIQUID, which is Patrick on 23 September: "Potions
            and poisons should be counted towards thirst they are liquids".
            They are not a meal and they are not a pint, so they are their own
            kind and the server gives them a swallow's worth. A poison is one
            as well: smearing it on a blade fires the same equip event as
            drinking it and there is no way to tell the two apart from here,
            so it counts, and that is said out loud rather than pretended
            away.
          */
          notFood++;
          const pname = s.FULL || s.EDID;
          rows.push({
            file: here.file,
            local: '0x' + (formId & 0x00ffffff).toString(16),
            edid: s.EDID,
            name: pname,
            kind: (s.flags & POISON_FLAG) ? 'poison' : 'potion',
            gold: s.value
          });
        } else {
          const name = s.FULL || s.EDID;
          const drink = DRINK.test(name);
          const booze = ALCOHOL.test(name);
          rows.push({
            file: here.file,
            local: '0x' + (formId & 0x00ffffff).toString(16),
            edid: s.EDID,
            name: name,
            kind: booze ? 'ale' : (drink ? 'drink' : 'food'),
            gold: s.value
          });
        }
      }
    }
    j += 24 + dataSize;
  }
}

const order = loadOrder();
const missing = [];
for (const file of order) {
  const full = path.join(DATA, file);
  if (!fs.existsSync(full)) { missing.push(file); continue; }
  here.file = file;
  let buf = null;
  try { buf = fs.readFileSync(full); } catch (e) { continue; }
  try { walk(buf, 0, buf.length); } catch (e) {
    console.error('FAIL  ' + file + ' would not parse: ' + e.message);
    process.exitCode = 1;
  }
}

// Later plugins win, the way the game resolves them.
const byDesc = {};
for (const r of rows) {
  byDesc[r.local.replace(/^0x/, '') + ':' + r.file] = r;
}

const items = {};
for (const desc in byDesc) {
  const r = byDesc[desc];
  items[desc] = { k: r.kind };
}

const counts = { food: 0, drink: 0, ale: 0, potion: 0, poison: 0 };
for (const desc in items) { counts[items[desc].k]++; }

console.log(order.length + ' plugins in the order, ' + missing.length + ' not installed');
console.log(scanned + ' ALCH records read, ' + Object.keys(items).length +
            ' can be swallowed');
console.log('  food   ' + counts.food);
console.log('  drink  ' + counts.drink);
console.log('  ale    ' + counts.ale);
console.log('  potion ' + counts.potion);
console.log('  poison ' + counts.poison);

if (PRINT) {
  const all = Object.keys(byDesc).map((d) => byDesc[d])
    .sort((a, b) => (a.kind + a.name).localeCompare(b.kind + b.name));
  for (const r of all) {
    console.log('  ' + r.kind.padEnd(6) + r.local.padEnd(10) + (r.name || '').padEnd(34) + r.file);
  }
}

/*
  INSTALLED INTO gamemode.js AS WELL.

  food.json keeps the name and the editor id, because "why is this thing ale"
  has to be answerable. The server needs neither: it asks one question, which
  is what kind this is, so the line that goes into the gamemode is the kind
  and nothing else.
*/
function install() {
  const gm = path.join(__dirname, 'gamemode.js');
  let src;
  try { src = fs.readFileSync(gm, 'utf8'); } catch (e) {
    console.error('FAIL  no gamemode.js to install into');
    process.exitCode = 1;
    return;
  }
  const line = 'const FOODS = ' + JSON.stringify({ items: items }) + ';';
  const re = /^const FOODS = .*;$/m;
  const next = re.test(src)
    ? src.replace(re, line)
    : src.replace(/^(const WARMTH = .*;)$/m, '$1\n' + line);
  if (next === src) {
    console.error('FAIL  could not find anywhere in gamemode.js to put the table');
    process.exitCode = 1;
    return;
  }
  fs.writeFileSync(gm, next);
  console.log('installed ' + Object.keys(items).length + ' rows into tools\gamemode.js');
}

if (!Object.keys(items).length) {
  console.error('FAIL  nothing came out, so nothing is written');
  process.exitCode = 1;
} else if (!process.exitCode) {
  install();
  fs.writeFileSync(OUT, JSON.stringify({
    builtBy: 'tools\Build-FoodTable.js',
    builtAt: new Date().toISOString(),
    source: 'the ALCH records of the plugins in load order',
    readFrom: 'ENIT for the food and poison flags, FULL for the name',
    note: 'what a kind is WORTH is balance and lives in NEEDS in gamemode.js',
    count: Object.keys(items).length,
    byKind: counts,
    items: byDesc
  }, null, 1));
  console.log('wrote ' + OUT);
}
