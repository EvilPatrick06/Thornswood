// test-1909-own-worlds.js
//
//     node .\tests\test-1909-own-worlds.js
//
// A death in a worldspace with coordinates of its own wakes in the nearest
// hall of the dead, temple or inn in that worldspace (#1909). resolveArrival
// measured every death out of doors against the nine hold capitals and the
// mainland's temple doors, which are in Tamriel's coordinates, so a death in
// the Soul Cairn, Blackreach or an arena floor got whichever hold its own
// numbers fell nearest on the mainland's map (all 171 Soul Cairn spots in
// npc-population.json woke in Whiterun), and Solstheim, the one worldspace it
// did catch, always woke in the Raven Rock temple whatever was nearer.
// Patrick, 5 Oct: the nearest hall of the dead, temple or inn in that
// worldspace.
//
// What it checks:
//   1. DATA.ownWorlds (game\data\data.json and the DATA line, written by
//      scripts\dev\Build-WakeTable.js) gives every worldspace of DATA.worldspaces
//      one answer: laid out in Tamriel's coordinates (Tamriel and the five
//      walled cities among them) or a key with its places; each place is
//      whole; Solstheim has the Raven Rock temple, at the respawn point it
//      always had, and the Retching Netch;
//   2. resolveArrival, sliced out of gamemode.js and run on DATA: a death on
//      Solstheim wakes at whichever of the two has the nearer door, measured
//      in Solstheim's own coordinates; a death in Blackreach, the Soul Cairn
//      or any worldspace of its own with none of the three is never measured
//      against the capitals; a death in Tamriel, in a walled city, in a small
//      worldspace laid out in Tamriel's coordinates, or in a room is resolved
//      as it was;
//   3. given a Data folder and its plugins.txt (THORNSWOOD_DATA and
//      THORNSWOOD_PLUGINS), the builder reads the load order again and the
//      table must be what it reads; without them it says it did not.
//
// GAMEMODE=<path> runs 1 and 2 against another copy of gamemode.js and its
// DATA line, which is how it was shown to fail on origin/main.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
const GM = process.env.GAMEMODE || path.join(ROOT, 'game', 'gamemode.js');
const gm = fs.readFileSync(GM, 'utf8').split(CR).join('');
const data = JSON.parse(fs.readFileSync(path.join(ROOT, 'game', 'data', 'data.json'), 'utf8'));

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function has(o, k) { return !!o && Object.prototype.hasOwnProperty.call(o, k); }

const m = /^const DATA = (.*);$/m.exec(gm);
let DATA = null;
try { DATA = m ? JSON.parse(m[1]) : null; } catch (e) { DATA = null; }
yes('gamemode.js has a DATA line', !!DATA);
if (!DATA) { done(); }

// ---- 1. the table -----------------------------------------------------------
const SOLSTHEIM = '800:Dragonborn.esm';
const TAMRIEL = ['3c:Skyrim.esm', '1a26f:Skyrim.esm', '37edf:Skyrim.esm', '1691d:Skyrim.esm', '16d71:Skyrim.esm', '16bb4:Skyrim.esm'];
const own = DATA.ownWorlds;
yes('DATA has ownWorlds, the places to wake in each worldspace with coordinates of its own', !!own && typeof own === 'object');
yes('and it is the same in data.json', !!own && JSON.stringify(data.ownWorlds) === JSON.stringify(own));
const ws = DATA.worldspaces || [];
const stray = Object.keys(own || {}).filter(function (k) { return ws.indexOf(k) < 0; });
yes('every key is a worldspace of the load order' + (stray.length ? ' (not: ' + stray.join(', ') + ')' : ''), !!own && stray.length === 0);
yes('Tamriel and the five walled cities are in Tamriel\'s coordinates, not keys',
  !!own && TAMRIEL.every(function (d) { return ws.indexOf(d) >= 0 && !has(own, d); }));
const ownCount = Object.keys(own || {}).length;
yes('every one of the ' + ws.length + ' worldspaces has one answer: ' + (ws.length - ownCount) + ' in Tamriel\'s coordinates, ' + ownCount + ' with their own',
  !!own && ownCount > 0 && ownCount < ws.length);
const KINDS = ['hallOfTheDead', 'temple', 'inn'];
function num(a, n) { return Array.isArray(a) && a.length === n && a.every(function (x) { return typeof x === 'number' && isFinite(x); }); }
const bad = [];
for (const w in own || {}) {
  if (!Array.isArray(own[w])) { bad.push(w + ' is not a list'); continue; }
  for (const p of own[w]) {
    if (KINDS.indexOf(p.kind) < 0 || !/^[0-9a-f]+:.+$/.test(p.desc || '') || !num(p.door, 2) || !num(p.pos, 3) || !num(p.rot, 3)) {
      bad.push(w + ' ' + JSON.stringify(p));
    }
  }
}
yes('every place is a hall of the dead, a temple or an inn, with its room, its door and where it wakes you' +
  (bad.length ? ' (not: ' + bad.join('; ') + ')' : ''), !!own && bad.length === 0);
const sol = (own && own[SOLSTHEIM]) || [];
const rrTemple = sol.filter(function (p) { return p.kind === 'temple' && p.cell === 'DLC2RRTemple'; })[0];
const netch = sol.filter(function (p) { return p.kind === 'inn' && p.cell === 'DLC2RRTheRetchingNetch'; })[0];
yes('Solstheim has the Raven Rock temple and the Retching Netch (' + sol.map(function (p) { return p.kind + ' ' + p.cell; }).join(', ') + ')',
  sol.length === 2 && !!rrTemple && !!netch);
const marker = data.destinations && data.destinations.ravenrock && data.destinations.ravenrock.temple;
yes('the temple wakes you at the respawn point Raven Rock always had',
  !!rrTemple && !!marker && rrTemple.desc === marker.desc && JSON.stringify(rrTemple.pos) === JSON.stringify(marker.pos) &&
  JSON.stringify(rrTemple.rot) === JSON.stringify(marker.rot) && rrTemple.destination === 'ravenrock');
yes('both are in Raven Rock\'s hold, so its crime faction', sol.every(function (p) { return p.hold === 'DLC2SolstheimLocation'; }) && sol.length === 2);
for (const w of ['1ee62:Skyrim.esm', '1408:Dawnguard.esm', '2ee41:Skyrim.esm', '1c0b2:Dragonborn.esm', 'bb5:Dawnguard.esm']) {
  yes(w + ' has coordinates of its own', has(own, w));
}

// ---- 2. the resolver ---------------------------------------------------------
function sliceFn(src, start, end) {
  const a = src.indexOf(start);
  const b = a < 0 ? -1 : src.indexOf(end, a);
  return a < 0 || b < 0 ? null : src.slice(a, b);
}
const arrivalSrc = sliceFn(gm, '\nfunction dist2(', '\nfunction ensureProperties(');
yes('resolveArrival and the helpers it calls are sliced out of gamemode.js', !!arrivalSrc);
if (!arrivalSrc) { done(); }
const resolve = new Function('DATA', 'WORLDSPACES', 'PREFER_SLOT', 'FALLBACK_DESTINATION',
  arrivalSrc + '\nreturn resolveArrival;')(DATA, new Set(DATA.worldspaces), 'temple', 'whiterun');
function d2(a, b) { return (a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]); }

// Solstheim. The two doors, read out of the load order (Build-WakeTable.js).
const netchDoor = netch ? netch.door : [30193.7, 36873.6];
const templeDoor = rrTemple ? rrTemple.door : [32848.4, 35142];
let a = resolve({ desc: SOLSTHEIM, pos: [netchDoor[0] + 120, netchDoor[1] - 80, 437] });
yes('a death on Solstheim at the Retching Netch\'s door wakes in the Retching Netch (got ' + a.cell + ', ' + a.slot + ')',
  a.cell === 'DLC2RRTheRetchingNetch' && a.slot === 'inn' && a.desc === '17ec0:Dragonborn.esm' && a.via === 'own-world' &&
  a.hold === 'DLC2SolstheimLocation');
yes('  where the Retching Netch\'s door puts anybody who walks in', !!netch && JSON.stringify(a.pos) === JSON.stringify(netch.pos) && JSON.stringify(a.rot) === JSON.stringify(netch.rot));
a = resolve({ desc: SOLSTHEIM, pos: [templeDoor[0] - 60, templeDoor[1] + 40, 896] });
yes('a death on Solstheim at the temple\'s door wakes in the Raven Rock temple, at its respawn point (got ' + a.cell + ')',
  a.desc === '17ec3:Dragonborn.esm' && a.slot === 'temple' && !!marker && JSON.stringify(a.pos) === JSON.stringify(marker.pos));
// Far from Raven Rock, by the Skaal village side of the island: whichever
// door is nearer, measured in Solstheim's own numbers.
const north = [-40000, 60000, 500];
const want = d2(netchDoor, north) < d2(templeDoor, north) ? 'DLC2RRTheRetchingNetch' : 'DLC2RRTemple';
a = resolve({ desc: SOLSTHEIM, pos: north });
yes('a death far across Solstheim wakes at the nearer door of the two (' + want + ', got ' + a.cell + ')', a.cell === want && a.via === 'own-world');
a = resolve({ desc: '800:dragonborn.esm', pos: [netchDoor[0], netchDoor[1], 0] });
yes('the worldspace is matched whole and without case, as the Solstheim branch it replaced was', a.cell === 'DLC2RRTheRetchingNetch');

// Worldspaces of their own with nowhere to wake: never the capitals.
const none = [
  ['Blackreach', { desc: '1ee62:Skyrim.esm', pos: [30000, 60000, -8000] }],
  ['the Soul Cairn', { desc: '1408:Dawnguard.esm', pos: [11694.0, -3113.3, 941.1] }],
  ['Sovngarde', { desc: '2ee41:Skyrim.esm', pos: [-20000, 10000, 2000] }],
  ['an arena floor', { desc: '1a654:Solitude Arena.esp', pos: [1576, 2038, 2304] }]
];
for (const n of none) {
  a = resolve(n[1]);
  yes('a death in ' + n[0] + ', which has no hall, temple or inn, is not measured against the mainland (' + a.via + ', ' + a.reason + ')',
    a.via === 'own-world-none' && a.reason === 'fallback' && a.destination === 'whiterun' && a.hold === null);
}
const measured = Object.keys(own || {}).filter(function (w) {
  const r = resolve({ desc: w, pos: [50000, 50000, 0] });
  return r.via !== 'own-world' && r.via !== 'own-world-none';
});
yes('no worldspace of its own reaches the capitals or the mainland\'s doors' + (measured.length ? ' (do: ' + measured.join(', ') + ')' : ''),
  !!own && measured.length === 0);

// Tamriel's coordinates, as before.
a = resolve({ desc: '3c:Skyrim.esm', pos: [22000, -4000, 0] });
yes('a death outside Whiterun wakes in Whiterun\'s temple, by the nearest capital (' + a.destination + ', ' + a.via + ')',
  a.destination === 'whiterun' && a.slot === 'temple' && a.via === 'nearest-capital');
a = resolve({ desc: '16bb4:Skyrim.esm', pos: [176000, -97000, 11000] });
yes('a death inside Riften\'s walls wakes in the Temple of Mara (' + a.destination + ')', a.destination === 'riften' && a.via === 'nearest-capital');
a = resolve({ desc: '1cdd3:Skyrim.esm', pos: [-12404, 44258, 1711] });
yes('a death in LabyrinthianWorld, laid out in Tamriel\'s coordinates, is still the hold it stands in (' + a.hold + ', ' + a.reason + ')',
  a.hold === 'HjaalmarchHoldLocation' && a.reason === 'borrowed');
a = resolve({ desc: '165a7:Skyrim.esm', pos: [1056.2, 254.9, 63] });
yes('a death in a room is still the hold the room names (' + a.hold + ', ' + a.via + ')', a.via === 'cell' && a.destination === 'whiterun');

// ---- 3. against the load order ----------------------------------------------
const DATA_DIR = process.env.THORNSWOOD_DATA, LIST = process.env.THORNSWOOD_PLUGINS;
if (DATA_DIR && LIST && fs.existsSync(DATA_DIR) && fs.existsSync(LIST) && !process.env.GAMEMODE) {
  const Build = require(path.join(ROOT, 'scripts', 'dev', 'Build-WakeTable.js'));
  const code = Build.main(['--data', DATA_DIR, '--plugins', LIST, '--check']);
  yes('Build-WakeTable.js reads the same table out of ' + DATA_DIR, code === 0);
} else {
  console.log('      not read again: set THORNSWOOD_DATA to a Data folder and THORNSWOOD_PLUGINS to its plugins.txt');
}

done();
function done() {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}
