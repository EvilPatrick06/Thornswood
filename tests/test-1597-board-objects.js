// test-1597-board-objects.js
//
// Every notice board the server has gets its message board object, in the
// cell or worldspace the server has it in. Issue #1597.
//
// WHY THIS EXISTS. The client put the object (ThornswoodMessageBoard, 0x593B
// in Thornswood-Content.esp) down at nine points in Tamriel written into
// game/plugins/thornswood-front.js, with no cell, the moment the page was
// ready. Raven Rock's board (#1374), seeded server side in The Retching
// Netch, had no object, nor did any board a steward walked indoors or to
// Solstheim. And placeAtMe puts the copy in the cell you are in, setPosition
// moves it within that cell: somebody who came in indoors had all nine put
// inside that room at Tamriel's numbers, and never had them outside.
//
// What changed, and what this holds: the server sends every board with its
// cell or worldspace and facing (boardsView's list, in the social view);
// the board page hands the list to the plugin as 'board:spots', once per
// change; the plugin puts a copy down for each board only while you are in
// that board's cell or worldspace, moves it when a steward moves the board
// within it, and takes it away when the board goes somewhere else.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function read(rel) { return fs.readFileSync(path.join(REPO_DIR, rel), 'utf8').split('\r\n').join('\n'); }

const front = read('game/plugins/thornswood-front.js');
const page = read('game/ui/thornswood-board.js');
const gm = read('game/gamemode.js');

// ---------------------------------------------------------- the old list
yes('front.js holds no list of board spots of its own (BOARD_SEEDS is gone)', front.indexOf('BOARD_SEEDS') < 0);

// ------------------------------------------------- the server sends them
{
  const a = gm.indexOf('  function boardsView(profileId) {');
  const b = a < 0 ? -1 : gm.indexOf('\n  }\n', a);
  const fn = b < 0 ? '' : gm.slice(a, b + 4);
  const boards = {
    whiterun: { cell: '3c:Skyrim.esm', pos: [23139.4, -7891.7, -3494.4], facing: 188.4, where: 'Whiterun', seed: 3 },
    ravenrock: { cell: '17ec0:Dragonborn.esm', pos: [-39, -178.2, 0], where: 'Raven Rock', seed: 3 },
    solitude: { cell: '16a0e:Skyrim.esm', pos: [1, 2, 3], where: 'Solitude', placed: 1 }
  };
  const SITES = { solitude: { facing: 9.9 }, whiterun: { facing: 188.4 } };
  let view = null;
  try {
    view = new Function('LEDGER_HOLDS', 'boards', 'boardReads', 'BOARD_SITES', 'wallOf', 'jobsOf',
      fn + '\nreturn boardsView;')(['whiterun', 'solitude', 'ravenrock'], boards, {}, SITES,
        function () { return { rows: [], older: 0 }; }, function () { return []; })(7);
  } catch (e) { console.log('      ' + e); }
  const list = view ? view.list : [];
  const by = {};
  list.forEach(function (t) { by[t.hold] = t; });
  yes('boardsView lists each board with its cell and point',
      !!by.whiterun && by.whiterun.cell === '3c:Skyrim.esm' && by.whiterun.x === 23139.4 &&
      by.whiterun.y === -7891.7 && by.whiterun.z === -3494.4 && by.whiterun.face === 188.4);
  yes('Raven Rock\'s, in The Retching Netch, with its interior cell',
      !!by.ravenrock && by.ravenrock.cell === '17ec0:Dragonborn.esm' && by.ravenrock.x === -39);
  yes('a board a steward walked keeps its town\'s facing, as the object did before',
      !!by.solitude && by.solitude.cell === '16a0e:Skyrim.esm' && by.solitude.face === 9.9);
  yes('and the J tab still has each town\'s name', by.ravenrock && by.ravenrock.where === 'Raven Rock');
}

// ------------------------------------------------ the page hands them on
{
  const told = [];
  // An element that takes anything: the page builds its panel on setData, and only what it tells matters here.
  function el() {
    const own = function () { return el(); };
    own.style = {};
    own.classList = { add: function () { }, remove: function () { }, toggle: function () { }, contains: function () { return false; } };
    return new Proxy(own, {
      get: function (t, k) {
        if (k in t && k !== 'name' && k !== 'length') { return t[k]; }
        if (k === 'querySelector' || k === 'getElementById') { return function () { return null; }; }
        if (k === 'querySelectorAll') { return function () { return []; }; }
        if (k === Symbol.toPrimitive) { return function () { return ''; }; }
        return el();
      },
      set: function (t, k, v) { t[k] = v; return true; }
    });
  }
  const win = {
    skyrimPlatform: { sendMessage: function (to, what) { told.push([to, what]); } },
    document: el()
  };
  win.window = win;
  vm.createContext(win);
  let threw = '';
  try { vm.runInContext(page, win, { filename: 'thornswood-board.js' }); } catch (e) { threw = String(e); }
  yes('the board page loads in a bare window', !threw && !!win.thornswoodBoard);
  if (threw) { console.log('      ' + threw); }
  const LIST = [
    { hold: 'whiterun', where: 'Whiterun', cell: '3c:Skyrim.esm', x: 1, y: 2, z: 3, face: 4 },
    { hold: 'ravenrock', where: 'Raven Rock', cell: '17ec0:Dragonborn.esm', x: -39, y: -178.2, z: 0, face: 0 },
    { hold: 'morthal', where: 'Morthal' }
  ];
  const spotsSaid = function () {
    return told.filter(function (t) { return t[0] === 'thornswood-front' && String(t[1]).indexOf('board:spots ') === 0; });
  };
  if (win.thornswoodBoard) {
    win.thornswoodBoard.setData({ boards: { list: LIST } });
    const first = spotsSaid();
    let sent = null;
    try { sent = first.length ? JSON.parse(first[0][1].slice('board:spots '.length)) : null; } catch (e) { sent = null; }
    yes('the page tells the plugin every board with a cell, as board:spots',
        first.length === 1 && Array.isArray(sent) && sent.length === 2 &&
        sent[1].hold === 'ravenrock' && sent[1].cell === '17ec0:Dragonborn.esm' && sent[1].y === -178.2);
    win.thornswoodBoard.setData({ boards: { list: LIST }, party: [] });
    yes('and not again while the list is the same', spotsSaid().length === 1);
    win.thornswoodBoard.setData({ boards: { list: [LIST[0], Object.assign({}, LIST[1], { cell: '800:Dragonborn.esm' })] } });
    yes('and again when a board moves', spotsSaid().length === 2);
  }
}

// ---------------------------------------------------- the plugin puts them down
const a = front.indexOf('  const BOARD_REACH = 400;');
const b = a < 0 ? -1 : front.indexOf('  /*\n    A CARRIAGE OR FERRY DRIVER OPENS HIS PANEL', a);
const block = b < 0 ? '' : front.slice(a, b);
yes('the board block is in front.js where this harness lifts it', !!block);

const TAMRIEL = 0x3c, NETCH = 0x04017ec0, MARE = 0x1605e, SOLSTHEIM = 0x04000800;
const FILES = {
  '3c:Skyrim.esm': TAMRIEL, '1605e:Skyrim.esm': MARE,
  '17ec0:Dragonborn.esm': NETCH, '800:Dragonborn.esm': SOLSTHEIM
};
const WORLDSPACES = [TAMRIEL, SOLSTHEIM];

function rig() {
  const w = { place: TAMRIEL, refs: {}, next: 0xff000800, said: [], clock: 0 };
  function form(id) { return { getFormID: function () { return id; } }; }
  function placeOf(id) { return { getFormID: function () { return id; } }; }
  const pc = {
    getWorldSpace: function () { return WORLDSPACES.indexOf(w.place) >= 0 ? placeOf(w.place) : null; },
    getParentCell: function () { return placeOf(w.place); },
    placeAtMe: function (base) {
      if (!base || base.getFormID() !== 0x0b00593b) { return null; }
      const id = w.next++;
      const r = { id: id, place: w.place, pos: null, face: null, enabled: false, deleted: false };
      w.refs[id] = r;
      return {
        getFormID: function () { return id; },
        setPosition: function (x, y, z) { r.pos = [x, y, z]; return Promise.resolve(); },
        setAngle: function (ax, ay, az) { r.face = az; return Promise.resolve(); },
        enable: function () { r.enabled = true; return Promise.resolve(); },
        disable: function () { r.enabled = false; return Promise.resolve(); },
        delete: function () { r.deleted = true; return Promise.resolve(); }
      };
    }
  };
  const handles = {};
  const sp = {
    Game: {
      getPlayer: function () { return pc; },
      getFormFromFile: function (local, file) {
        if (local === 0x593B && file === 'Thornswood-Content.esp') { return form(0x0b00593b); }
        const id = FILES[local.toString(16) + ':' + file];
        return id ? form(id) : null;
      },
      getFormEx: function (id) {
        const r = w.refs[id];
        if (!r || r.deleted) { return null; }
        return handles[id] || (handles[id] = {
          getFormID: function () { return id; },
          setPosition: function (x, y, z) { r.pos = [x, y, z]; return Promise.resolve(); },
          setAngle: function (ax, ay, az) { r.face = az; return Promise.resolve(); },
          disable: function () { r.enabled = false; return Promise.resolve(); },
          delete: function () { r.deleted = true; return Promise.resolve(); }
        });
      }
    },
    ObjectReference: { from: function (f) { return f; } }
  };
  const T = { ready: true };
  const say = function (m) { w.said.push(String(m)); };
  const DateNow = { now: function () { return w.clock; } };
  const api = new Function('sp', 'T', 'say', 'Date', block +
    '\nreturn { set: boardsSet, ensure: ensureBoards, aim: boardAimSpot, here: boardObjectHere, refs: boardRefs, ' +
    'near: function (n) { boardNear = n; } };')(sp, T, say, DateNow);
  w.api = api;
  w.T = T;
  w.pc = pc;
  w.tick = function () { w.clock += 2500; api.ensure(); };
  w.live = function () {
    return Object.keys(w.refs).map(function (k) { return w.refs[k]; }).filter(function (r) { return !r.deleted && r.enabled; });
  };
  return w;
}

const NINE = [
  ['solitude', -64867, 104407.2, -8405.9, 9.9], ['whiterun', 23139.4, -7891.7, -3494.4, 188.4],
  ['riften', 174559.5, -94337, 11130.2, 38], ['windhelm', 134265.1, 35842.3, -12397.5, 85.8],
  ['markarth', -173494.7, 5049.1, -3447.6, 72], ['falkreath', -30342.2, -87022.7, -3119.1, 56.6],
  ['morthal', -38766.1, 64411.9, -13920.9, 251.2], ['dawnstar', 32216.4, 102314, -13263, 110],
  ['winterhold', 109969.6, 100594.4, -9033, 241.4]
].map(function (r) { return { hold: r[0], cell: '3c:Skyrim.esm', x: r[1], y: r[2], z: r[3], face: r[4] }; });
const RAVEN = { hold: 'ravenrock', cell: '17ec0:Dragonborn.esm', x: -39, y: -178.2, z: 0, face: 0 };
const TEN = NINE.concat([RAVEN]);

if (block) {
  {
    const w = rig();
    w.tick();
    yes('before the server has sent a list, nothing is put down', w.live().length === 0);
    w.api.set(TEN);
    w.T.ready = false; w.tick();
    yes('nor before the page is ready', w.live().length === 0);
    w.T.ready = true; w.tick();
    const live = w.live();
    yes('in Tamriel the nine mainland boards are put down, each in Tamriel', live.length === 9 &&
        live.every(function (r) { return r.place === TAMRIEL; }));
    const wr = live.filter(function (r) { return r.pos && r.pos[0] === 23139.4; })[0];
    yes('at the same point and facing as before, Whiterun\'s for one',
        !!wr && wr.pos[1] === -7891.7 && wr.pos[2] === -3494.4 && wr.face === 188.4);
    yes('and Raven Rock\'s is not put down outside its inn', !live.some(function (r) { return r.pos && r.pos[0] === -39; }));
    w.tick();
    yes('the next look puts nothing down twice', w.live().length === 9);

    w.place = NETCH; w.tick();
    const rr = w.live().filter(function (r) { return r.place === NETCH; });
    yes('walking into The Retching Netch puts Raven Rock\'s board down there, at its spot',
        rr.length === 1 && rr[0].pos[0] === -39 && rr[0].pos[1] === -178.2 && rr[0].pos[2] === 0);
    yes('and the nine stay where they were', w.live().filter(function (r) { return r.place === TAMRIEL; }).length === 9);
    yes('the object there counts as the board when it is under the crosshair',
        w.api.here({ getFormID: function () { return rr[0].id; } }));
    yes('aiming at it from the counter finds Raven Rock\'s', (w.api.aim(w.pc, -39, -100, 0) || {}).hold === 'ravenrock');
    w.place = TAMRIEL;
    yes('the same numbers in Tamriel aim at nothing: a board is matched by its cell too', w.api.aim(w.pc, -39, -100, 0) === null);
  }
  {
    const w = rig();
    w.place = MARE;
    w.api.set(TEN);
    w.tick();
    yes('somebody who comes in inside the Bannered Mare has no board put inside that room (the old fault)', w.live().length === 0);
    w.place = TAMRIEL; w.tick();
    yes('and the nine go down in Tamriel when they step out', w.live().length === 9 &&
        w.live().every(function (r) { return r.place === TAMRIEL; }));
  }
  {
    const w = rig();
    w.api.set(TEN); w.tick();
    const before = Object.keys(w.refs).length;
    const moved = TEN.map(function (s) { return s.hold === 'whiterun' ? Object.assign({}, s, { x: 23000, y: -7800 }) : s; });
    w.api.set(moved); w.tick();
    const wr = w.live().filter(function (r) { return r.pos[0] === 23000; });
    yes('a steward moving Whiterun\'s board within Tamriel moves the same object', wr.length === 1 &&
        wr[0].pos[1] === -7800 && Object.keys(w.refs).length === before);
    const inside = moved.map(function (s) { return s.hold === 'whiterun' ? Object.assign({}, s, { cell: '1605e:Skyrim.esm', x: 10, y: 20, z: 30 }) : s; });
    w.api.set(inside); w.tick();
    yes('moving it indoors takes the outdoor object away', w.live().length === 8 && wr.length === 1 && w.refs[wr[0].id].deleted);
    yes('and says so in the log', w.said.some(function (m) { return /took the notice board in whiterun away/.test(m); }));
    w.place = MARE; w.tick();
    const mare = w.live().filter(function (r) { return r.place === MARE; });
    yes('and it goes down in the Bannered Mare when somebody is there', mare.length === 1 && mare[0].pos[0] === 10);
    const solstheim = inside.map(function (s) { return s.hold === 'ravenrock' ? Object.assign({}, s, { cell: '800:Dragonborn.esm', x: -1000, y: 2000, z: 50 }) : s; });
    w.api.set(solstheim);
    w.place = SOLSTHEIM; w.tick();
    const sol = w.live().filter(function (r) { return r.place === SOLSTHEIM; });
    yes('a board walked out onto Solstheim goes down on Solstheim', sol.length === 1 && sol[0].pos[0] === -1000);
  }
  {
    const w = rig();
    w.api.set([{ hold: 'x', cell: 'nonsense', x: 1, y: 2, z: 3 }, { hold: 'y', cell: '3c:Skyrim.esm', x: 'a', y: 2, z: 3 }, null]);
    w.tick();
    yes('a spot with a cell the game does not have, or no point, puts nothing down', w.live().length === 0);
  }
}

// --------------------------------------------------- the message on the way
yes('front.js reads board:spots from the page and hands it to the board block',
    (function () {
      const at = front.indexOf("if (what.indexOf('board:spots ') === 0) {");
      const branch = at < 0 ? '' : front.slice(at, front.indexOf('\n    }', at));
      return branch.indexOf("JSON.parse(what.slice('board:spots '.length))") >= 0 && branch.indexOf('boardsSet(list);') >= 0;
    })());

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
