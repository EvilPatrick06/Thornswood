'use strict';
/*
  test-2516-server-boards.js

      node tests/test-2516-server-boards.js

  #2516. Each game used to put the notice boards down itself and, two seconds
  later, could no longer find a copy it had moved into a cell that was not
  loaded, so it put another down at the person, for every far town, for ever
  (Patrick on dev, 12 Oct). Now the server stands one board and one drop box
  per hold, as its own references every game is sent, and answers E on them.

  The real property block runs over a pretend engine that keeps references,
  places them (mp.place, at Tamriel's 0, 0, 0) and runs the two Papyrus calls
  the block makes, MoveTo and SetAngle, the way the fork's
  PapyrusObjectReference does for an object: MoveTo puts it in the target's
  cell, at the target's point plus the offset. It checks:
    - a tick stands every board in Tamriel at its spot, turned to its facing,
      and its box at BOX_AT turned with it; a board in another cell (Raven
      Rock's inn) waits for somebody to be in that cell, then stands there;
    - a second tick places nothing more, and one that finds a board gone
      stands it again, once;
    - a steward's move takes the cell or worldspace, the point and the facing
      where they stand, and moves the same two references there;
    - E on the board opens only the board, E on the box only the box, and E
      on anything else is not theirs;
    - after a restart the same references are used, not new ones;
    - each of the nine sites carries its own worldspace, and the five walled
      cities say plainly that theirs is unmeasured.
*/
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const CR = String.fromCharCode(13);
const read = function (p) { return fs.readFileSync(p, 'utf8').split(CR).join(''); };
const gm = read(path.join(REPO_DIR, 'game', 'gamemode.js'));
let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); } else { fail++; console.log('FAIL  ' + what); }
}
function done() {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}
function slice(src, start, end) {
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b + end.length);
}
const propBlock = slice(gm, '// ==== thornswood property ====', '// ==== end thornswood property ====');
yes('the property block is in the gamemode', !!propBlock);
if (!propBlock) { done(); }

const TAMRIEL = '3c:Skyrim.esm';
const NETCH = '17ec0:Dragonborn.esm';
const WHITERUN_WORLD = '1a26d:Skyrim.esm';
const BOARD_BASE = 0x0B00593B, BOX_BASE = 0x0B0154D0;
const STEWARD = { a: 0xff000606, pid: 606, name: 'Proventus' };
const ALICE = { a: 0xff000303, pid: 303, name: 'Alice' };
const BOB = { a: 0xff000404, pid: 404, name: 'Bob' };
const PEOPLE = [STEWARD, ALICE, BOB];

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-2516-'));
fs.writeFileSync(path.join(dir, 'server-settings.json'), JSON.stringify({ dataDir: 'data', privDir: 'private' }));
fs.mkdirSync(path.join(dir, 'private'));
fs.writeFileSync(path.join(dir, 'private', 'property.json'), JSON.stringify({
  claims: {}, stewards: [STEWARD.pid], boxes: {}, funds: {}, notices: {},
  boards: {
    whiterun: { cell: TAMRIEL, pos: [23139.4, -7891.7, -3494.4], facing: 188.4, where: 'Whiterun', placed: 1 },
    ravenrock: { cell: NETCH, pos: [-39, -178.2, 0], where: 'Raven Rock', placed: 1 }
  }
}));
function inDir(f) {
  const was = process.cwd();
  process.chdir(dir);
  try { return f(); } finally { process.chdir(was); }
}

// ------------------------------------------------------------- the engine
const world = {};          // id -> { baseDesc, worldOrCellDesc, pos, angle, ... }
let next = 0xff00f000;
let placed = [];
PEOPLE.forEach(function (p) {
  world[p.a] = { profileId: p.pid, appearance: { name: p.name }, worldOrCellDesc: 'somewhere else',
                 pos: [0, 0, 0], angle: [0, 0, 0], inventory: { entries: [] } };
});
const sets = [];
function idOfDesc(desc) {
  const m = /^([0-9a-f]+)(:.*)?$/i.exec(String(desc || ''));
  return m ? parseInt(m[1], 16) : 0;
}
const mp = {
  makeProperty: function () { },
  get: function (id, key) {
    if (id === 0 && key === 'onlinePlayers') { return PEOPLE.map(function (p) { return p.a; }); }
    if (!world[id]) { throw new Error('no reference ' + id.toString(16)); }
    const v = world[id][key];
    return (v && typeof v === 'object') ? JSON.parse(JSON.stringify(v)) : v;
  },
  set: function (id, key, v) {
    sets.push({ id: id, key: key, v: JSON.parse(JSON.stringify(v)) });
    if (!world[id]) { world[id] = {}; }
    world[id][key] = JSON.parse(JSON.stringify(v));
  },
  getDescFromId: function (id) { return (id >>> 0).toString(16) + (id >= 0xff000000 ? '' : ':Skyrim.esm'); },
  getIdFromDesc: function (desc) {
    const d = String(desc).toLowerCase();
    if (d === '593b:thornswood-content.esp') { return BOARD_BASE; }
    if (d === '154d0:thornswood-content.esp') { return BOX_BASE; }
    return 0;
  },
  lookupEspmRecordById: function (id) { return (id === BOARD_BASE || id === BOX_BASE) ? { record: { type: 'ACTI' } } : {}; },
  getNeighborsByPosition: function () { return []; },
  place: function (base) {
    const id = next++;
    world[id] = { baseDesc: base === BOARD_BASE ? '593b:Thornswood-Content.esp' : '154d0:Thornswood-Content.esp',
                  worldOrCellDesc: TAMRIEL, pos: [0, 0, 0], angle: [0, 0, 0] };
    placed.push(id);
    return id;
  },
  callPapyrusFunction: function (kind, cls, fn, self, args) {
    if (kind !== 'method' || cls !== 'ObjectReference') { throw new Error('unexpected call ' + cls + '.' + fn); }
    const id = idOfDesc(self.desc);
    const me = world[id];
    if (!me) { throw new Error('no self ' + self.desc); }
    if (fn === 'MoveTo') {
      const target = world[idOfDesc(args[0].desc)];
      if (!target) { throw new Error('MoveTo - target object reference was nullptr'); }
      me.worldOrCellDesc = target.worldOrCellDesc;
      me.pos = [target.pos[0] + args[1], target.pos[1] + args[2], target.pos[2] + args[3]];
      if (args[4]) { me.angle = target.angle.slice(); }
      return null;
    }
    if (fn === 'SetAngle') { me.angle = [args[0], args[1], args[2]]; return null; }
    throw new Error('unexpected Papyrus ' + fn);
  }
};

function makeBlock() {
  const box = {
    console: { log: function () { } },
    require: require, mp: mp, Date: Date,
    BUILDING_BY_DOOR: {}, BUILDING_NAME: {}, WAY_OUT: {}, BENCH_BY_BASE: {},
    idOf: function () { return 0; }, notify: function () { }, say: function () { },
    guard: function (n, f) { return f; },
    setInterval: function () { return 1; }, clearInterval: function () { },
    log: function () { },
    __thornswoodCharacter: { stateOf: function () { return {}; }, writeState: function () { } }
  };
  box.globalThis = box;
  inDir(function () { vm.runInNewContext(propBlock, box, { filename: 'gamemode.js property' }); });
  return box.__thornswoodProperty;
}
let W = makeBlock();
yes('the property block runs, with the server\'s boards in it', !!W && typeof W.boardTick === 'function' &&
    typeof W.standBoard === 'function' && typeof W.boardActivated === 'function');
if (!W) { done(); }
function tick() { inDir(function () { W.boardTick(); }); }
function near(a, b, eps) { return a.every(function (v, i) { return Math.abs(v - b[i]) < (eps || 0.01); }); }

// ------------------------------------------------------------ a tick stands them
tick();
const wr = W.boards().whiterun;
const boardW = world[wr.ref], boxW = world[wr.boxRef];
yes('S1 a tick stands Whiterun\'s board, in Tamriel, at its spot', !!boardW && boardW.worldOrCellDesc === TAMRIEL &&
    near(boardW.pos, [23139.4, -7891.7, -3494.4]) && boardW.baseDesc === '593b:Thornswood-Content.esp');
yes('  turned to its facing', near(boardW.angle, [0, 0, 188.4]));
const off = W.boxOffset(188.4);
yes('  and its drop box on the shelf, turned with it', !!boxW && boxW.worldOrCellDesc === TAMRIEL &&
    near(boxW.pos, [23139.4 + off[0], -7891.7 + off[1], -3494.4 + off[2]]) && near(boxW.angle, [0, 0, 188.4]) &&
    boxW.baseDesc === '154d0:Thornswood-Content.esp');
yes('  Raven Rock\'s, indoors, waits for somebody to be in its cell', !W.boards().ravenrock.ref && placed.length === 2);

tick();
yes('S2 a second tick places nothing more', placed.length === 2);

world[BOB.a].worldOrCellDesc = NETCH;
world[BOB.a].pos = [100, 50, 0];
tick();
const rr = W.boards().ravenrock;
yes('S3 once Bob is in The Retching Netch, its board stands there, at its spot', !!rr.ref &&
    world[rr.ref].worldOrCellDesc === NETCH && near(world[rr.ref].pos, [-39, -178.2, 0]) && placed.length === 4);
yes('  and its box beside it, in the same cell', !!rr.boxRef && world[rr.boxRef].worldOrCellDesc === NETCH);

const goneRef = wr.ref;
delete world[goneRef];
tick();
yes('S4 a board that is gone is stood again, once, and its box with it',
    !!world[W.boards().whiterun.ref] && W.boards().whiterun.ref !== goneRef && placed.length === 5 &&
    near(world[W.boards().whiterun.boxRef].pos, [23139.4 + off[0], -7891.7 + off[1], -3494.4 + off[2]]));
tick();
yes('  and the next tick places nothing', placed.length === 5);

// ---------------------------------------------------------- a steward's move
const before = { ref: W.boards().whiterun.ref, box: W.boards().whiterun.boxRef };
world[STEWARD.a].worldOrCellDesc = WHITERUN_WORLD;
world[STEWARD.a].pos = [100, 200, -50];
world[STEWARD.a].angle = [3, 0, 90];
const said = [];
inDir(function () { W.command('/board', ['/board', 'move', 'whiterun'], STEWARD.a, STEWARD.pid, function (p, m) { said.push(m); }); });
const moved = W.boards().whiterun;
yes('S5 a steward\'s move records the worldspace, the point and the facing where they stand',
    moved.cell === WHITERUN_WORLD && near(moved.pos, [100, 200, -50]) && moved.facing === 90 && moved.placed);
yes('  and moves the same board there, inside the walls, turned their way',
    moved.ref === before.ref && world[moved.ref].worldOrCellDesc === WHITERUN_WORLD &&
    near(world[moved.ref].pos, [100, 200, -50]) && near(world[moved.ref].angle, [0, 0, 90]));
const off90 = W.boxOffset(90);
yes('  and the same box with it', moved.boxRef === before.box && world[moved.boxRef].worldOrCellDesc === WHITERUN_WORLD &&
    near(world[moved.boxRef].pos, [100 + off90[0], 200 + off90[1], -50 + off90[2]]) && placed.length === 5);
yes('  and says so', /whiterun's board is here now/.test(said.join(' ')));

// -------------------------------------------------------------- the click
world[ALICE.a].worldOrCellDesc = WHITERUN_WORLD;
world[ALICE.a].pos = [150, 200, -50];
sets.length = 0;
let r = '';
inDir(function () { r = W.boardActivated(moved.ref, ALICE.a); });
const openedBoard = sets.filter(function (s) { return s.id === ALICE.a && s.key === 'thornswoodBoardOpen'; });
const openedBox = sets.filter(function (s) { return s.id === ALICE.a && s.key === 'thornswoodBoxView'; });
yes('S6 E on the board opens the board for her, and not the box', r === 'board' && openedBoard.length === 1 && openedBox.length === 0);
sets.length = 0;
inDir(function () { r = W.boardActivated(moved.boxRef, ALICE.a); });
const boxView = sets.filter(function (s) { return s.id === ALICE.a && s.key === 'thornswoodBoxView'; });
yes('  E on the box opens the box for her, and not the board', r === 'box' && boxView.length === 1 &&
    boxView[0].v.open === true && boxView[0].v.hold === 'whiterun' &&
    sets.filter(function (s) { return s.key === 'thornswoodBoardOpen'; }).length === 0);
inDir(function () { r = W.boardActivated(0xff00aaaa, ALICE.a); });
yes('  and E on anything else is not theirs', r === '');
const onActivate = slice(gm, "mp.onActivate = guard('onActivate', function (refrId, casterRefrId) {", 'WATER (#1382)') || '';
yes('  and onActivate asks it first, and stops there when it answered',
    /if \(propBoard && propBoard\.boardActivated && propBoard\.boardActivated\(refrId, casterRefrId\)\) \{\s*return false;\s*\}/.test(onActivate));

// --------------------------------------------------------------- a restart
const ids = JSON.stringify([W.boards().whiterun.ref, W.boards().whiterun.boxRef, W.boards().ravenrock.ref]);
W = makeBlock();
tick();
yes('S7 after a restart the same references stand, and none is placed again',
    JSON.stringify([W.boards().whiterun.ref, W.boards().whiterun.boxRef, W.boards().ravenrock.ref]) === ids &&
    placed.length === 5);

// ---------------------------------------------------------------- the sites
{
  const a = gm.indexOf('  var BOARD_SITES = {');
  const b = gm.indexOf('\n  };\n', a);
  const sites = new Function('return ' + gm.slice(a + '  var BOARD_SITES = '.length, b + 4).replace(/;\s*$/, ''))();
  const nine = Object.keys(sites);
  yes('S8 each of the nine sites carries its own cell or worldspace', nine.length === 9 &&
      nine.every(function (h) { return typeof sites[h].cell === 'string' && sites[h].cell; }));
  yes('  and there is no single BOARD_CELL for all of them', gm.indexOf('BOARD_CELL') < 0);
  // Measured 15 Oct (#2516): the five walled cities in their own worldspaces, the four open towns in Tamriel.
  yes('  the five walled cities stand in their own worldspaces, as measured',
      sites.solitude.cell === '37edf:Skyrim.esm' && sites.whiterun.cell === '1a26f:Skyrim.esm' &&
      sites.riften.cell === '16bb4:Skyrim.esm' && sites.windhelm.cell === '1691d:Skyrim.esm' &&
      sites.markarth.cell === '16d71:Skyrim.esm');
  yes('  and the four open towns in Tamriel',
      ['falkreath', 'morthal', 'dawnstar', 'winterhold'].every(function (h) { return sites[h].cell === TAMRIEL; }));
  const seed = /var BOARD_SEED = (\d+);/.exec(gm);
  yes('  in a new seeding, so a saved board no steward moved follows on the next deploy', !!seed && Number(seed[1]) >= 4);
}

done();
