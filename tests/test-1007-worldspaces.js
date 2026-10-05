// test-1007-worldspaces.js
//
// #1007. DATA.worldspaces (game/data/data.json, installed as the DATA line of
// game/gamemode.js by scripts/dev/Install-GamemodeConsts.js) is the set
// resolveArrival and the stuck and arrival code read as "outdoors". It listed
// 3c, 1691d and 1b44a under Dragonborn.esm beside the Skyrim.esm entries with
// the same low ids. Measured on 5 October against the Main install's load
// order (101 plugins): no WRLD record in it has any of those three descs.
// Dragonborn.esm carries overrides of Skyrim.esm's Tamriel, WindhelmWorld and
// CWTestHold, which are 3c, 1691d and 1b44a:Skyrim.esm, and the old recovery
// pipeline counted the overrides as worldspaces of their own. The fourth the
// issue named, 1c0b2:Dragonborn.esm, is a WRLD record Dragonborn.esm defines,
// DLC2ApocryphaWorld, and it stays.
//
// MEASURED below is every entry with the editor id of the WRLD record it
// names, as read that day. The harness holds DATA.worldspaces to it. Given a
// Data folder and its plugins.txt (THORNSWOOD_DATA and THORNSWOOD_PLUGINS), it
// reads the WRLD records of that load order again and holds every entry to
// them; without them it says it did not.
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const ROOT = path.join(__dirname, '..');
const gm = fs.readFileSync(path.join(ROOT, 'game', 'gamemode.js'), 'utf8').split(String.fromCharCode(13)).join('');
const data = JSON.parse(fs.readFileSync(path.join(ROOT, 'game', 'data', 'data.json'), 'utf8'));

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const MEASURED = {
  "104217:Skyrim.esm": "LabyrinthianMazeWorld",
  "1691d:Skyrim.esm": "WindhelmWorld",
  "16bb4:Skyrim.esm": "RiftenWorld",
  "16d71:Skyrim.esm": "MarkarthWorld",
  "1a26f:Skyrim.esm": "WhiterunWorld",
  "1b44a:Skyrim.esm": "CWTestHold",
  "1c0b2:Dragonborn.esm": "DLC2ApocryphaWorld",
  "1cdd3:Skyrim.esm": "LabyrinthianWorld",
  "1cdd9:Skyrim.esm": "LabyrinthianWorld03",
  "1e49d:Skyrim.esm": "MossMotherCavernWorld",
  "1ee62:Skyrim.esm": "Blackreach",
  "1fae2:Skyrim.esm": "BloatedMansGrottoWorld",
  "204c7:Skyrim.esm": "FallowstoneCaveWorldEnd",
  "20bfe:Skyrim.esm": "SouthfringeWorld",
  "20dcb:Skyrim.esm": "BlindCliffCaveWorld",
  "21edb:Skyrim.esm": "LabyrinthianWorld04",
  "243de:Skyrim.esm": "FallowstoneCaveWorldStart",
  "278dd:Skyrim.esm": "SkuldafnWorld",
  "29ab7:Skyrim.esm": "DeepwoodRedoubtWorld",
  "2a9d8:Skyrim.esm": "ShadowgreenCavernWorld",
  "2b101:Skyrim.esm": "RedEagleRedoubtWorld",
  "2c965:Skyrim.esm": "DarkwaterWorld",
  "2ee41:Skyrim.esm": "Sovngarde",
  "34240:Skyrim.esm": "BluePalaceWingWorld",
  "35699:Skyrim.esm": "KarthspireRedoubtWorld",
  "37edf:Skyrim.esm": "SolitudeWorld",
  "3a9d6:Skyrim.esm": "EldergleamSanctuaryWorld",
  "3c:Skyrim.esm": "Tamriel",
  "419e1:Skyrim.esm": "CWSiegeTestWorld",
  "46033:Skyrim.esm": "WhiterunDragonsreachWorld",
  "4f838:Skyrim.esm": "EastEmpireWarehouse",
  "50015:Skyrim.esm": "BrinewaterGrottoWorld",
  "69857:Skyrim.esm": "AlftandWorld",
  "6ed38:Skyrim.esm": "FXLightWorldSpace",
  "800:Dragonborn.esm": "DLC2SolstheimWorld",
  "94b35:Skyrim.esm": "JaphetsFollyWorld",
  "c350d:Skyrim.esm": "KatariahWorld",
  "c97eb:Skyrim.esm": "FrostmereCryptWorld",
  "d45f0:Skyrim.esm": "WindhelmPitWorldspace"
};

const m = /^const DATA = (.*);$/m.exec(gm);
let DATA = null;
try { DATA = m ? JSON.parse(m[1]) : null; } catch (e) { DATA = null; }
const ws = data.worldspaces || [];
yes('the gamemode\'s DATA line holds the same worldspaces as data.json (' + ws.length + ')',
  !!DATA && JSON.stringify(DATA.worldspaces) === JSON.stringify(ws));
yes('no entry is listed twice', new Set(ws).size === ws.length);
for (const d of ['3c:Dragonborn.esm', '1691d:Dragonborn.esm', '1b44a:Dragonborn.esm']) {
  yes(d + ', an override of ' + d.replace('Dragonborn', 'Skyrim') + ' and no WRLD record of its own, is not listed',
    ws.indexOf(d) < 0 && ws.indexOf(d.replace('Dragonborn', 'Skyrim')) >= 0);
}
yes('Solstheim and Apocrypha, the WRLD records Dragonborn.esm defines, are listed',
  ws.indexOf('800:Dragonborn.esm') >= 0 && ws.indexOf('1c0b2:Dragonborn.esm') >= 0);
const unknown = ws.filter(function (d) { return !Object.prototype.hasOwnProperty.call(MEASURED, d); });
yes('every entry is a WRLD record measured in the load order' + (unknown.length ? ' (not: ' + unknown.join(', ') + ')' : ''),
  unknown.length === 0);
yes('and every measured one is listed', Object.keys(MEASURED).every(function (d) { return ws.indexOf(d) >= 0; }));

// ---- again, against a load order on this machine ------------------------------
const DATA_DIR = process.env.THORNSWOOD_DATA, LIST = process.env.THORNSWOOD_PLUGINS;
if (DATA_DIR && LIST && fs.existsSync(DATA_DIR) && fs.existsSync(LIST)) {
  const order = ['Skyrim.esm', 'Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm'];
  for (const ln of fs.readFileSync(LIST, 'utf8').split(/\r?\n/)) {
    const t = ln.trim();
    if (!t || t[0] === '#' || t[0] !== '*') { continue; }
    const name = t.slice(1).trim();
    if (order.indexOf(name) < 0) { order.push(name); }
  }
  const wrld = {};
  for (const pl of order) {
    const p = path.join(DATA_DIR, pl);
    if (!fs.existsSync(p)) { continue; }
    const b = fs.readFileSync(p);
    const hs = b.readUInt32LE(4);
    const masters = [];
    for (let q = 24; q < 24 + hs;) {
      const sz = b.readUInt16LE(q + 4);
      if (b.toString('ascii', q, q + 4) === 'MAST') { masters.push(b.toString('latin1', q + 6, q + 6 + sz - 1)); }
      q += 6 + sz;
    }
    for (let i = 24 + hs; i + 24 <= b.length;) {
      if (b.toString('ascii', i, i + 4) !== 'GRUP') { break; }
      const gs = b.readUInt32LE(i + 4);
      if (b.toString('ascii', i + 8, i + 12) === 'WRLD') {
        for (let j = i + 24; j + 24 <= i + gs;) {
          const sz = b.readUInt32LE(j + 4);
          if (b.toString('ascii', j, j + 4) === 'GRUP') { j += sz; continue; }
          const flags = b.readUInt32LE(j + 8), fid = b.readUInt32LE(j + 12);
          let d = b.subarray(j + 24, j + 24 + sz);
          if (flags & 0x40000) { d = zlib.inflateSync(d.subarray(4)); }
          let edid = '';
          for (let k = 0; k + 6 <= d.length;) {
            const ss = d.readUInt16LE(k + 4);
            if (d.toString('ascii', k, k + 4) === 'EDID') { edid = d.toString('latin1', k + 6, k + 6 + ss - 1); break; }
            k += 6 + ss;
          }
          const mi = fid >>> 24;
          const owner = mi < masters.length ? masters[mi] : pl;
          wrld[(fid & 0xffffff).toString(16) + ':' + owner] = edid;
          j += 24 + sz;
        }
      }
      i += gs;
    }
  }
  const missing = ws.filter(function (d) { return !Object.prototype.hasOwnProperty.call(wrld, d); });
  yes('read again from ' + order.length + ' plugins: every entry is one of its ' + Object.keys(wrld).length +
      ' WRLD records' + (missing.length ? ' (not: ' + missing.join(', ') + ')' : ''), missing.length === 0);
  const renamed = ws.filter(function (d) { return wrld[d] !== undefined && wrld[d] !== MEASURED[d]; });
  yes('and each is the record MEASURED names' + (renamed.length ? ' (not: ' + renamed.join(', ') + ')' : ''), renamed.length === 0);
} else {
  console.log('      not read again: set THORNSWOOD_DATA to a Data folder and THORNSWOOD_PLUGINS to its plugins.txt');
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
