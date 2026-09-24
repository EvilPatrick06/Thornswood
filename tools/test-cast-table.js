// test-cast-table.js
//
// The surviving cast, written down before anything is deleted.
//
// Entry 320, settled by Patrick on 17 September: "What survives: traders you
// can buy from and sell to through the custom economy in entry 214, and the
// carriage and ferry workers in entry 215. Everything else is either rebuilt as
// a custom character or removed." And: "Write the surviving cast down as a list
// before anything is deleted, because the deletion is the part that cannot be
// undone".
//
// tools/Build-CastTable.py writes that list into tools/cast.json. This drives
// the real script against a small load order built here, byte by byte, where
// every answer is known, and then reads the committed cast.json for the people
// the list has to get right in the real one.
//
// The load order built here carries each trap the script was written around:
//   - a compressed NPC_ record, which has to be inflated before it says anything
//   - a vendor faction at rank -1, which is not membership (Faendal)
//   - a job merchant faction at rank 0 with no vendor faction, which is not a
//     trader either
//   - a vendor-flagged faction with no buy and sell list, which is who owns an
//     inn rather than a shop
//   - IsGuardFaction alone, which the Companions carry and are not the watch
//   - a thin guard whose own race is a wolf and whose name, race and factions
//     all come from its template, and one whose template is a leveled list
//   - a placement switched off by its own flag, one switched off by its enable
//     parent, and one switched ON by an enable parent marked opposite
//   - a worldspace's persistent cell, which says it is at 0,0 and is not the
//     ground at 0,0
//   - a patch naming its master SKYRIM.ESM, which is the same file as Skyrim.esm
//     and must not make a second Bjorlam
//   - a patch deleting a placement and keeping nothing of it but the flag
//
// Read only apart from a folder in the temp directory, removed at the end.
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const { spawnSync } = require('child_process');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const TOOL = process.env.CAST_TOOL || path.join(__dirname, 'Build-CastTable.py');
yes('tools/Build-CastTable.py is in the repo', fs.existsSync(TOOL));

// ------------------------------------------------------------ plugin bytes
function u32(n) { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0, 0); return b; }
function f32(n) { const b = Buffer.alloc(4); b.writeFloatLE(n, 0); return b; }
function zstr(s) { return Buffer.from(s + '\0', 'utf8'); }
function sub(tag, body) {
  const h = Buffer.alloc(6);
  h.write(tag, 0, 'ascii');
  h.writeUInt16LE(body.length, 4);
  return Buffer.concat([h, body]);
}
function rec(tag, fid, subs, flags, compress) {
  let data = Buffer.concat(subs);
  flags = flags || 0;
  if (compress) {
    data = Buffer.concat([u32(data.length), zlib.deflateSync(data)]);
    flags |= 0x00040000;
  }
  const h = Buffer.alloc(24);
  h.write(tag, 0, 'ascii');
  h.writeUInt32LE(data.length, 4);
  h.writeUInt32LE(flags >>> 0, 8);
  h.writeUInt32LE(fid >>> 0, 12);
  return Buffer.concat([h, data]);
}
function grup(label, type, kids) {
  const body = Buffer.concat(kids);
  const h = Buffer.alloc(24);
  h.write('GRUP', 0, 'ascii');
  h.writeUInt32LE(24 + body.length, 4);
  label.copy(h, 8);
  h.writeUInt32LE(type, 12);
  return Buffer.concat([h, body]);
}
function top(tag, kids) { return grup(Buffer.from(tag, 'ascii'), 0, kids); }
function tes4(masters) {
  const subs = [sub('HEDR', Buffer.concat([f32(1.7), u32(0), u32(0x800)]))];
  masters.forEach(function (m) { subs.push(sub('MAST', zstr(m)), sub('DATA', Buffer.alloc(8))); });
  return rec('TES4', 0, subs, 1);
}
const edid = function (s) { return sub('EDID', zstr(s)); };
const full = function (s) { return sub('FULL', zstr(s)); };
const kwda = function (ids) { return sub('KWDA', Buffer.concat(ids.map(u32))); };
function snam(fid, rank) {
  const b = Buffer.alloc(8);
  b.writeUInt32LE(fid, 0);
  b.writeInt8(rank, 4);
  return sub('SNAM', b);
}
function acbs(flags, uses) {
  const b = Buffer.alloc(24);
  b.writeUInt32LE(flags >>> 0, 0);
  b.writeUInt16LE(uses, 18);
  return sub('ACBS', b);
}
function fdata(flags) { return sub('DATA', u32(flags)); }
function xesp(parent, flags) {
  const b = Buffer.alloc(8);
  b.writeUInt32LE(parent, 0);
  b[4] = flags;
  return sub('XESP', b);
}
function pos(x, y) { return sub('DATA', Buffer.concat([f32(x), f32(y), f32(0), f32(0), f32(0), f32(0)])); }
function xclc(x, y) {
  const b = Buffer.alloc(12);
  b.writeInt32LE(x, 0);
  b.writeInt32LE(y, 4);
  return sub('XCLC', b);
}
function achr(fid, base, more, flags) { return rec('ACHR', fid, [sub('NAME', u32(base))].concat(more || []), flags); }
function children(cell, kids) { return grup(u32(cell), 6, [grup(u32(cell), 8, kids)]); }

const VENDOR = 0x4000, DISABLED = 0x800, DELETED = 0x20;
const UNIQUE = 0x20;
const TRAITS = 0x1, FACTIONS = 0x4, BASE = 0x80;
const SQ = 4096;

// Skyrim.esm, the whole world in miniature. Every form id is its own (index 0).
const K = { hold: 0x100, npc: 0x101 };
const R = { nord: 0x200, wolf: 0x201, manakin: 0x202 };
const L = { whiterunHold: 0x300, whiterun: 0x301, riftHold: 0x302, belethors: 0x303 };
const F = {
  belethor: 0x400, follower: 0x401, carriage: 0x402, isGuard: 0x403, guardTalk: 0x404,
  guardWhiterun: 0x405, crimeWhiterun: 0x406, mareOwner: 0x407, jobMerchant: 0x408,
};
const N = {
  belethor: 0x500, faendal: 0x501, bjorlam: 0x502, guard: 0x503, thin: 0x504, wolf: 0x505,
  mannequin: 0x506, gjalund: 0x507, aela: 0x508, patron: 0x509, nazeem: 0x50A,
  leveled: 0x50B, hermit: 0x50C, riftTrader: 0x50D,
};
const LV = 0x600;
const C = { shop: 0x700, house: 0x701 };
const W = { tamriel: 0x900, persistent: 0x901, whiterunSq: 0x902, openSq: 0x903, riftSq: 0x904,
  farSq: 0x905, zeroSq: 0x906 };
const MARKER = 0x820;

function npc(fid, name, race, more, flags, compress) {
  return rec('NPC_', fid, [edid(name.replace(/[^A-Za-z0-9]/g, '')), full(name), sub('RNAM', u32(race))]
    .concat(more || []), flags, compress);
}

const skyrim = Buffer.concat([
  tes4([]),
  top('KYWD', [rec('KYWD', K.hold, [edid('LocTypeHold')]), rec('KYWD', K.npc, [edid('ActorTypeNPC')])]),
  top('RACE', [
    rec('RACE', R.nord, [edid('NordRace'), kwda([K.npc])]),
    rec('RACE', R.wolf, [edid('WolfRace')]),
    rec('RACE', R.manakin, [edid('ManakinRace'), kwda([K.npc])]),
  ]),
  top('LCTN', [
    rec('LCTN', L.whiterunHold, [edid('WhiterunHoldLocation'), full('Whiterun'), kwda([K.hold])]),
    rec('LCTN', L.whiterun, [edid('WhiterunLocation'), full('Whiterun city'), sub('PNAM', u32(L.whiterunHold))]),
    rec('LCTN', L.riftHold, [edid('RiftHoldLocation'), full('the Rift'), kwda([K.hold])]),
    rec('LCTN', L.belethors, [edid('BelethorsLocation'), sub('PNAM', u32(L.whiterun))]),
  ]),
  top('FACT', [
    rec('FACT', F.belethor, [edid('ServicesWhiterunBelethorsGoods'), fdata(VENDOR), sub('VEND', u32(0))]),
    rec('FACT', F.follower, [edid('CurrentFollowerFaction'), fdata(VENDOR), sub('VEND', u32(0))]),
    rec('FACT', F.carriage, [edid('CarriageSystemFaction'), fdata(0)]),
    rec('FACT', F.isGuard, [edid('IsGuardFaction'), fdata(0)]),
    rec('FACT', F.guardTalk, [edid('GuardDialogueFaction'), fdata(0)]),
    rec('FACT', F.guardWhiterun, [edid('GuardFactionWhiterun'), fdata(0)]),
    rec('FACT', F.crimeWhiterun, [edid('CrimeFactionWhiterun'), fdata(0)]),
    rec('FACT', F.mareOwner, [edid('WhiterunBanneredMareFaction'), fdata(VENDOR)]),
    rec('FACT', F.jobMerchant, [edid('JobMerchantFaction'), fdata(0)]),
  ]),
  top('NPC_', [
    // Compressed, so nothing about Belethor is known until it is inflated.
    npc(N.belethor, 'Belethor', R.nord, [snam(F.belethor, 0), snam(F.jobMerchant, -1),
      sub('CRIF', u32(F.crimeWhiterun)), acbs(UNIQUE, 0)], 0, true),
    npc(N.faendal, 'Faendal', R.nord, [snam(F.follower, -1), snam(F.jobMerchant, 0), acbs(UNIQUE, 0)]),
    npc(N.bjorlam, 'Bjorlam', R.nord, [snam(F.carriage, 0), acbs(UNIQUE, 0)]),
    npc(N.guard, 'Whiterun Guard', R.nord, [snam(F.guardWhiterun, 0), snam(F.isGuard, 0), snam(F.guardTalk, 0)]),
    // A thin record: its own race is a wolf and it names nobody. Everything
    // comes from the template, the way 6,521 real placements are built.
    rec('NPC_', N.thin, [edid('GuardThin'), sub('RNAM', u32(R.wolf)), sub('TPLT', u32(N.guard)),
      acbs(0, TRAITS | FACTIONS | BASE)]),
    npc(N.wolf, 'Wolf', R.wolf),
    npc(N.mannequin, 'Mannequin', R.manakin),
    rec('NPC_', N.gjalund, [edid('DLC2RRGjalundSaltSageWindhelm'), full('Gjalund Salt-Sage'),
      sub('RNAM', u32(R.nord)), acbs(UNIQUE, 0)]),
    npc(N.aela, 'Aela the Huntress', R.nord, [snam(F.isGuard, 0), acbs(UNIQUE, 0)]),
    npc(N.patron, 'Patron', R.nord, [snam(F.mareOwner, 0)]),
    npc(N.nazeem, 'Nazeem', R.nord, [sub('CRIF', u32(F.crimeWhiterun)), acbs(UNIQUE, 0)]),
    rec('NPC_', N.leveled, [edid('GuardLeveled'), sub('RNAM', u32(R.wolf)), sub('TPLT', u32(LV)),
      acbs(0, TRAITS | FACTIONS | BASE)]),
    npc(N.hermit, 'Hermit', R.nord),
    npc(N.riftTrader, 'Rift Peddler', R.nord, [snam(F.belethor, 0)]),
  ]),
  top('LVLN', [rec('LVLN', LV, [edid('LvlGuard'),
    sub('LVLO', Buffer.concat([Buffer.from([1, 0, 0, 0]), u32(N.guard), Buffer.from([1, 0, 0, 0])]))])]),
  top('CELL', [grup(u32(0), 2, [grup(u32(0), 3, [
    rec('CELL', C.shop, [edid('WhiterunBelethorsGeneralGoods'), full("Belethor's General Goods"),
      sub('DATA', Buffer.from([1, 0])), sub('XLCN', u32(L.belethors))]),
    children(C.shop, [
      achr(0x800, N.belethor),
      achr(0x801, N.faendal),
      achr(0x802, N.mannequin),
      achr(0x803, N.belethor, [], DISABLED),
      achr(0x804, N.patron),
      achr(0x807, N.nazeem),
      achr(0x80F, N.aela),
    ]),
    rec('CELL', C.house, [edid('NazeemsHouse'), sub('DATA', Buffer.from([1, 0]))]),
    children(C.house, [achr(0x805, N.nazeem), achr(0x806, N.hermit)]),
  ])])]),
  top('WRLD', [
    rec('WRLD', W.tamriel, [edid('Tamriel')]),
    grup(u32(W.tamriel), 1, [
      // The ground first and the persistent cell after it, so a pass that let
      // the persistent cell's 0,0 stand for the ground would lose the Rift.
      grup(u32(0), 4, [grup(u32(0), 5, [
        rec('CELL', W.whiterunSq, [sub('DATA', Buffer.from([0, 0])), xclc(6, -1), sub('XLCN', u32(L.whiterun))]),
        rec('CELL', W.openSq, [sub('DATA', Buffer.from([0, 0])), xclc(20, -20)]),
        rec('CELL', W.riftSq, [sub('DATA', Buffer.from([0, 0])), xclc(22, -20), sub('XLCN', u32(L.riftHold))]),
        rec('CELL', W.farSq, [sub('DATA', Buffer.from([0, 0])), xclc(25, -20), sub('XLCN', u32(L.whiterun))]),
        rec('CELL', W.zeroSq, [sub('DATA', Buffer.from([0, 0])), xclc(0, 0), sub('XLCN', u32(L.riftHold))]),
        children(W.openSq, [achr(0x817, N.riftTrader, [pos(20 * SQ + 5, -20 * SQ + 5)])]),
      ])]),
      rec('CELL', W.persistent, [sub('DATA', Buffer.from([0, 0])), xclc(0, 0)]),
      children(W.persistent, [
        achr(0x810, N.bjorlam, [pos(6 * SQ + 10, -1 * SQ + 10)]),
        achr(0x811, N.gjalund, [pos(-9000, 9000), sub('XLCN', u32(L.riftHold))]),
        achr(0x812, N.thin, [pos(6 * SQ + 20, -1 * SQ + 20)]),
        achr(0x813, N.leveled, [pos(6 * SQ + 30, -1 * SQ + 30)]),
        achr(0x814, N.wolf, [pos(6 * SQ + 40, -1 * SQ + 40)]),
        achr(0x815, N.thin, [pos(6 * SQ + 50, -1 * SQ + 50), xesp(MARKER, 0)]),
        achr(0x816, N.thin, [pos(6 * SQ + 60, -1 * SQ + 60), xesp(MARKER, 1)]),
        achr(0x818, N.belethor, [pos(6 * SQ + 70, -1 * SQ + 70)], DELETED),
        achr(0x819, N.hermit, [pos(100, 100)]),
        rec('REFR', MARKER, [sub('NAME', u32(0x999)), pos(6 * SQ, -1 * SQ)], DISABLED),
      ]),
    ]),
  ]),
]);

// A patch that spells its master SKYRIM.ESM. It repeats Bjorlam and his
// placement word for word, and deletes Nazeem's second placement keeping only
// the flag. Read with the spelling as written, that is a second Bjorlam and a
// Nazeem nobody deleted.
const patch = Buffer.concat([
  tes4(['SKYRIM.ESM']),
  top('NPC_', [npc(N.bjorlam, 'Bjorlam', R.nord, [snam(F.carriage, 0), acbs(UNIQUE, 0)])]),
  top('CELL', [grup(u32(0), 2, [grup(u32(0), 3, [
    rec('CELL', C.shop, [edid('WhiterunBelethorsGeneralGoods'), full("Belethor's General Goods"),
      sub('DATA', Buffer.from([1, 0])), sub('XLCN', u32(L.belethors))]),
    children(C.shop, [rec('ACHR', 0x807, [], DELETED)]),
  ])])]),
  top('WRLD', [
    rec('WRLD', W.tamriel, [edid('Tamriel')]),
    grup(u32(W.tamriel), 1, [
      rec('CELL', W.persistent, [sub('DATA', Buffer.from([0, 0])), xclc(0, 0)]),
      children(W.persistent, [achr(0x810, N.bjorlam, [pos(6 * SQ + 10, -1 * SQ + 10)])]),
    ]),
  ]),
]);

function findPython() {
  const tries = [['python', []], ['py', ['-3']], ['python3', []]];
  for (let i = 0; i < tries.length; i++) {
    const r = spawnSync(tries[i][0], tries[i][1].concat(['--version']), { encoding: 'utf8' });
    if (r.status === 0) { return tries[i]; }
  }
  return null;
}

const py = findPython();
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-cast-'));
try {
  if (!py) {
    console.log('SKIP  no python on this machine, so the script could not be driven');
  } else if (fs.existsSync(TOOL)) {
    fs.writeFileSync(path.join(dir, 'Skyrim.esm'), skyrim);
    ['Update.esm', 'Dawnguard.esm', 'HearthFires.esm', 'Dragonborn.esm'].forEach(function (m) {
      fs.writeFileSync(path.join(dir, m), tes4([]));
    });
    fs.writeFileSync(path.join(dir, 'Patch.esp'), patch);
    fs.writeFileSync(path.join(dir, 'plugins.txt'), '# a load order of one patch\r\n*Patch.esp\r\n');
    const out = path.join(dir, 'cast.json');
    const run = spawnSync(py[0], py[1].concat([TOOL, '--data', dir, '--plugins',
      path.join(dir, 'plugins.txt'), '--out', out]), { encoding: 'utf8' });
    yes('the script runs to the end on a load order it has never seen', run.status === 0);
    if (run.status !== 0) { console.log(run.stdout + run.stderr); }

    const check = spawnSync(py[0], py[1].concat([TOOL, '--data', dir, '--plugins',
      path.join(dir, 'plugins.txt'), '--out', path.join(dir, 'not-written.json'), '--check']),
      { encoding: 'utf8' });
    yes('--check says what it found and writes nothing',
      check.status === 0 && !fs.existsSync(path.join(dir, 'not-written.json')));

    let j = null;
    try { j = JSON.parse(fs.readFileSync(out, 'utf8')); } catch (e) { j = null; }
    yes('and writes cast.json', j !== null);
    j = j || { counts: {}, holds: {} };
    const hold = function (name) { return j.holds[name] || { traders: [], transport: [], guards: {}, everyoneElse: {}, offAtStart: [], offAtStartBy: {} }; };
    const wr = hold('Whiterun'), rift = hold('the Rift'), none = hold('no hold');
    const named = function (rows, name) { return rows.filter(function (r) { return r.name === name; }); };

    yes('nothing was lost to a record that would not inflate', j.counts.failedToInflate === 0);
    yes('19 placements read, 2 of them deleted, one by a patch that kept only the flag',
      j.counts.placed === 19 && j.counts.deleted === 2);
    yes('a wolf and a mannequin are counted, not listed as people', j.counts.notPeople === 2);

    const bel = named(wr.traders, 'Belethor');
    yes('Belethor is a trader in Whiterun, out of a compressed record',
      bel.length === 1 && bel[0].unique === true);
    yes('because of his vendor faction, and not his job faction at rank -1',
      bel.length === 1 && bel[0].because.join() === 'ServicesWhiterunBelethorsGoods');
    yes('his hold came up from the shop he stands in, through the city to the hold',
      bel.length === 1 && bel[0].holdFrom === 'the cell it stands in');
    yes('his second placement, switched off by its own flag, is named apart and not counted as cast',
      wr.offAtStart.some(function (r) { return r.name === 'Belethor' && r.offBy === 'its own flag'; }));
    yes('Faendal, in a vendor faction at rank -1 and a job faction at rank 0, is not a trader',
      named(wr.traders, 'Faendal').length === 0 && wr.everyoneElse.Faendal === 1);
    yes('a vendor-flagged faction with no buy and sell list makes nobody a trader',
      named(wr.traders, 'Patron').length === 0 && wr.everyoneElse.Patron === 1);
    yes('only Belethor trades in Whiterun', wr.traders.length === 1);

    const bj = named(wr.transport, 'Bjorlam');
    yes('Bjorlam is transport in Whiterun, once, though a patch spells the master SKYRIM.ESM',
      bj.length === 1 && wr.transport.length === 1);
    yes('placed from the persistent cell by the ground under him', bj.length === 1 && bj[0].holdFrom === 'the ground it stands on');
    const gj = named(rift.transport, 'Gjalund Salt-Sage');
    yes('Gjalund, the Solstheim ferry in no faction, is transport by his record',
      gj.length === 1 && gj[0].because.join() === 'DLC2RRGjalundSaltSageWindhelm' && gj[0].holdFrom === 'its own location');

    yes('the guards are counted through their templates: a thin one, a leveled one, and one switched on by an opposite parent',
      wr.guards['Whiterun Guard'] === 3 && Object.keys(wr.guards).length === 1);
    yes('the guard behind a switched-off enable parent is counted off, not as a guard', wr.offAtStartBy.guards === 1);
    yes('IsGuardFaction alone does not make a guard', wr.everyoneElse['Aela the Huntress'] === 1);

    yes('Nazeem, in a house that names no place, is placed by whose law he answers to', wr.everyoneElse.Nazeem === 1);
    yes('and his deleted second placement is gone', j.counts.everyoneElse === 6);
    yes('a person on open ground takes the hold of the nearest named place, the Rift two cells off and not Whiterun five off',
      named(rift.traders, 'Rift Peddler').length === 1 && named(rift.traders, 'Rift Peddler')[0].holdFrom === 'the nearest named place');
    yes('the persistent cell at 0,0 is not taken for the ground at 0,0', rift.everyoneElse.Hermit === 1);
    yes('and somebody nothing places is under no hold', none.everyoneElse.Hermit === 1);
    yes('the totals add up: 2 traders, 2 transport, 3 guards, 6 everyone else, 2 off, 15 people',
      j.counts.traders === 2 && j.counts.transport === 2 && j.counts.guards === 3 &&
      j.counts.offAtStart === 2 && j.counts.people === 15);
  }
} catch (e) {
  yes('the load order built here was driven without throwing: ' + e.message, false);
} finally {
  // A scanner may still hold a file it was just handed, so this retries, and
  // a folder left behind in the temp directory is a note rather than a failure.
  try {
    fs.rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
  } catch (e) {
    console.log('NOTE  could not remove ' + dir + ': ' + e.message);
  }
}

// ----------------------------------------------------- what it may not do
{
  const src = fs.existsSync(TOOL) ? fs.readFileSync(TOOL, 'utf8') : '';
  const writes = (src.match(/io\.open\([^)]*'w'/g) || []).length;
  yes('the script writes one file and one file only', writes === 1);
  yes('and never opens the gamemode or a plugin to write', !/gamemode/.test(src) && !/\.esp'\s*,\s*'w/.test(src));
}

// ------------------------------------------------ the committed list, by eye
{
  const CAST = path.join(__dirname, 'cast.json');
  let j = null;
  try { j = JSON.parse(fs.readFileSync(CAST, 'utf8')); } catch (e) { j = null; }
  yes('tools/cast.json is in the repo, written by the script', j !== null && j.builtBy === 'tools/Build-CastTable.py');
  j = j || { holds: {}, counts: {} };
  const rows = function (h, col) { return ((j.holds[h] || {})[col]) || []; };
  const bel = rows('Whiterun', 'traders').filter(function (r) { return r.name === 'Belethor'; });
  yes('Belethor sells in Whiterun, through ServicesWhiterunBelethorsGoods',
    bel.length === 1 && bel[0].because.indexOf('ServicesWhiterunBelethorsGoods') !== -1);
  yes('Bjorlam drives the Whiterun carriage, once, as CFTO placed him',
    rows('Whiterun', 'transport').filter(function (r) { return r.name === 'Bjorlam'; }).length === 1);
  yes('the vanilla Bjorlam CFTO switched off is named apart',
    rows('Whiterun', 'offAtStart').some(function (r) { return r.name === 'Bjorlam' && r.base === '13669:Skyrim.esm'; }));
  yes('Gjalund Salt-Sage runs the Solstheim ferry from both ends',
    rows('Eastmarch', 'transport').some(function (r) { return r.name === 'Gjalund Salt-Sage'; }) &&
    rows('Solstheim', 'transport').some(function (r) { return r.name === 'Gjalund Salt-Sage'; }));
  yes('Faendal is not a trader anywhere', Object.keys(j.holds).every(function (h) {
    return rows(h, 'traders').every(function (r) { return r.name !== 'Faendal'; });
  }));
  const holds = ['Whiterun', 'Haafingar', 'Falkreath', 'Hjaalmarch', 'the Pale', 'the Rift',
    'Winterhold', 'Eastmarch', 'the Reach', 'Solstheim'];
  yes('all nine holds and Solstheim have traders and guards counted', holds.every(function (h) {
    const c = (j.holds[h] || {}).counts || {};
    return c.traders > 0 && c.guards > 0;
  }));
  yes('the Companions are not counted as guards', Object.keys(j.holds).every(function (h) {
    return !((j.holds[h] || {}).guards || {})['Aela the Huntress'];
  }));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
