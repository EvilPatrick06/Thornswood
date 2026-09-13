// Drive the real gamemode.js against a stubbed server API.
const PLUGIN = '/mnt/user-data/outputs/thornswood/gamemode.js';

const state = new Map(), inventories = new Map();
let nextId = 0xff000001;
const descToId = new Map(), idToDesc = new Map();
function id(desc) {
  if (!descToId.has(desc)) { const v = nextId++; descToId.set(desc, v); idToDesc.set(v, desc); }
  return descToId.get(desc);
}
const captured = { spawnPoints: new Map(), properties: new Set() };

const online = [];
const missingDescs = new Set();
captured.raceMenu = [];
captured.papyrus = [];
captured.teleports = new Map();

global.mp = {
  getIdFromDesc: (d) => {
    if (missingDescs.has(d)) throw new Error('no such form ' + d);
    return id(d);
  },
  getDescFromId: (i) => idToDesc.get(i),
  makeProperty: (n) => captured.properties.add(n),
  setRaceMenuOpen: (f, v) => captured.raceMenu.push([f, v]),
  callPapyrusFunction: (...a) => { captured.papyrus.push(a); },
  get(f, p) {
    if (p === 'onlinePlayers') return online.slice();
    if (p === 'inventory') return inventories.get(f) || { entries: [] };
    const o = state.get(f);
    if (!o) throw new Error('Form with id ' + f.toString(16) + " doesn't exist");
    return o[p];
  },
  set(f, p, v) {
    if (p === 'inventory') { inventories.set(f, v); return; }
    const o = state.get(f) || {}; o[p] = v; state.set(f, o);
    if (p === 'spawnPoint') captured.spawnPoints.set(f, v);
    if (p === 'locationalData') captured.teleports.set(f, v);
  },
};

// A clock the tests own. The chargen state machine deliberately leaves a joining
// client alone for ten seconds, so time has to be something the test can move.
let NOW = 1700000000000;
Date.now = () => NOW;
const advance = (ms) => { NOW += ms; };
const SETTLE = 11000;   // comfortably past the gamemode's own settle window

// The gamemode arms a real interval at load. Hold the callback instead, so the
// state machine can be stepped deterministically and the process can still exit.
let tickFn = null, liveTimers = 0;
global.setInterval = (fn) => { tickFn = fn; liveTimers++; return { __fake: liveTimers }; };
global.clearInterval = () => { liveTimers--; };
const tick = () => { logs = []; tickFn(); return logs.join(' | '); };

// keep capturing for the whole run, not just during require
const realLog = console.log, realErr = console.error;
let logs = [];
console.log = (...a) => logs.push(a.join(' '));
console.error = (...a) => logs.push('ERR ' + a.join(' '));
const say = (...a) => realLog(...a);

require(PLUGIN);

let pass = 0, fail = 0;
function check(name, got, want) {
  const ok = got === want; ok ? pass++ : fail++;
  say(`  ${ok ? 'ok  ' : 'FAIL'} ${name.padEnd(44)} ${ok ? String(got) : got + '   wanted ' + want}`);
}
function run(fn) { logs = []; const r = fn(); return { r, out: logs.join(' | ') }; }

const ACTOR = 0xff000000;
function die(desc, pos) {
  state.set(ACTOR, { worldOrCellDesc: desc, pos });
  captured.spawnPoints.delete(ACTOR);
  const { out } = run(() => mp.onDeath(ACTOR, 0));
  const m = out.match(/-> (\S+) \((\w+)\) hold=([^(]+)\(([^)]+)\) ground=(\S+)/);
  return { sp: captured.spawnPoints.get(ACTOR), out,
           dest: m && m[1], slot: m && m[2], hold: m && m[3], via: m && m[4], reason: m && m[5] };
}

say('\n=== respawn resolution ===');
say('  ' + 'death site'.padEnd(28) + 'wakes at'.padEnd(32) + 'hold'.padEnd(13) + 'hold found by'.padEnd(18) + 'ground');
const cases = [
  ['outdoors, Dawnstar',        '3c:Skyrim.esm', [32901, 102643, 0]],
  ['outdoors, Morthal',         '3c:Skyrim.esm', [-38741, 63380, 0]],
  ['outdoors, Winterhold',      '3c:Skyrim.esm', [109719, 101002, 0]],
  ['outdoors, Falkreath',       '3c:Skyrim.esm', [-29417, -87534, 0]],
  ['outdoors, far west Reach',  '3c:Skyrim.esm', [-176816, 4500, 0]],
  ['WhiterunWorld',             '1a26f:Skyrim.esm', [23280, -3368, 0]],
  ['Solstheim',                 '2000800:Dragonborn.esm', [0, 0, 0]],
  ['Morthal Highmoon Hall',     '138cc:Skyrim.esm', [0, 0, 0]],
  ['Winterhold Jarl longhouse', '13818:Skyrim.esm', [0, 0, 0]],
  ['Falkreath Jarl longhouse',  '13a79:Skyrim.esm', [0, 0, 0]],
  ['Whiterun Jorrvaskr',        '165b5:Skyrim.esm', [0, 0, 0]],
  ['Riften Mistveil Keep',      '16bd2:Skyrim.esm', [0, 0, 0]],
];
const results = {};
for (const [n, d, p] of cases) {
  const r = die(d, p); results[n] = r;
  const where = (r.dest || '?') + (r.slot === 'hallOfTheDead' ? ' (hall)' : '');
  say('  ' + n.padEnd(28) + where.padEnd(32) + (r.hold || '?').replace('HoldLocation','').padEnd(13) + (r.via || '?').padEnd(18) + (r.reason || '?'));
}

say('\n=== invariants ===');
check('spawnPoint set on every death', cases.every(([n]) => !!results[n].sp), true);
check('Solstheim never distance-matches', results['Solstheim'].via, 'solstheim');
check('Solstheim goes to Raven Rock', results['Solstheim'].dest, 'DLC2RRTemple');
check('Dawnstar is judged the Pale', results['outdoors, Dawnstar'].hold, 'PaleHoldLocation');
check('the Pale borrows, not owns', results['outdoors, Dawnstar'].reason, 'borrowed');
check('the Pale was found by coordinates', results['outdoors, Dawnstar'].via, 'nearest-capital');
check('Morthal interior resolves by cell', results['Morthal Highmoon Hall'].via, 'cell');
check('Morthal still has to borrow ground', results['Morthal Highmoon Hall'].reason, 'borrowed');
check('Morthal interior lands in Hjaalmarch', results['Morthal Highmoon Hall'].hold, 'HjaalmarchHoldLocation');
check('Falkreath takes the nearest ground', results['outdoors, Falkreath'].reason, 'borrowed');
check('Riften owns its temple', results['Riften Mistveil Keep'].dest, 'RiftenTempleofMara');
check('far west Reach picks Markarth', results['outdoors, far west Reach'].dest, 'MarkarthTempleofDibella');
check('interiors never use local coords', results['Winterhold Jarl longhouse'].hold, 'WinterholdHoldLocation');
check('custom property registered', captured.properties.has('thornswoodSkills'), true);

say('\n=== skills and stations ===');
const QUARRY = 0x0500dde4, KILN = 0x05001547;
state.set(QUARRY, { baseDesc: 'dde4ef:Thornswood-Content.esp' });
state.set(KILN,   { baseDesc: '1547e:Thornswood-Content.esp' });
state.set(ACTOR, {}); inventories.set(ACTOR, { entries: [] });
const salt = () => (inventories.get(ACTOR).entries.find(e => e.baseId === id('34cdf:Skyrim.esm')) || {}).count || 0;
const wood = () => (inventories.get(ACTOR).entries.find(e => e.baseId === id('6f993:Skyrim.esm')) || {}).count || 0;
const coal = () => !!inventories.get(ACTOR).entries.find(e => e.baseId === id('15481:Thornswood-Content.esp'));

let t = run(() => mp.onActivate(QUARRY, ACTOR));
check('station blocks default activation', t.r, false);
check('quarry refuses without a manual', t.out.includes('Novice mining manual'), true);
check('refusal grants nothing', salt(), 0);

run(() => mp.onReadBook(ACTOR, id('b276:Thornswood-Content.esp')));
check('manual raises mining to tier 1', mp.get(ACTOR, 'thornswoodSkills').mining, 1);
run(() => mp.onReadBook(ACTOR, id('b276:Thornswood-Content.esp')));
check('re-reading grants nothing twice', mp.get(ACTOR, 'thornswoodSkills').mining, 1);

t = run(() => mp.onActivate(QUARRY, ACTOR));
check('quarry now yields salt', salt() > 0, true);
const after = salt();
t = run(() => mp.onActivate(QUARRY, ACTOR));
check('cooldown blocks the next strike', t.out.includes('more seconds'), true);
check('blocked strike yields nothing', salt(), after);

run(() => mp.onReadBook(ACTOR, id('15489:Thornswood-Content.esp')));
check('woodcutter manual applies', mp.get(ACTOR, 'thornswoodSkills').woodcutter, 1);
t = run(() => mp.onActivate(KILN, ACTOR));
check('kiln refuses without firewood', t.out.includes('needs 3 firewood'), true);
t = run(() => mp.onActivate(KILN, ACTOR));
check('a refused kiln did NOT start a cooldown', t.out.includes('needs 3 firewood'), true);

inventories.get(ACTOR).entries.push({ baseId: id('6f993:Skyrim.esm'), count: 5 });
t = run(() => mp.onActivate(KILN, ACTOR));
check('kiln consumes exactly 3 firewood', wood(), 2);
check('kiln yields charcoal', coal(), true);
t = run(() => mp.onActivate(KILN, ACTOR));
check('a successful kiln DOES start a cooldown', t.out.includes('still burning'), true);

say('\n=== robustness ===');
state.set(0x999, { baseDesc: '1ad6e:Skyrim.esm' });
check('unrelated activation falls through', run(() => mp.onActivate(0x999, ACTOR)).r, undefined);
check('missing form does not throw', run(() => mp.onActivate(0xdeadbeef, ACTOR)).r, undefined);
check('self-activation with no caster ignored', run(() => mp.onActivate(QUARRY, 0)).r, undefined);
t = run(() => mp.onDeath(0xdeadbeef, 0));
check('death of an unknown form is contained', t.out.includes('threw'), true);
check('unknown book is ignored', run(() => mp.onReadBook(ACTOR, 0x1234)).r, undefined);

say('\n=== character creation ===');

const WRIT_MINER = 'e80014:Thornswood-Content.esp';
const WRIT_MAGE  = 'e80012:Thornswood-Content.esp';
const PASS_RIFTEN = 'e80024:Thornswood-Content.esp';
const PASS_SOLITUDE = 'e80021:Thornswood-Content.esp';
const WELCOME = 'e80000:Thornswood-Content.esp';
const HALL = '19bad4:Skyrim Unbound.esp';

const NEW = 0xff00aa01, OLD = 0xff00aa02;
const has = (a, desc) => {
  const e = (inventories.get(a) || { entries: [] }).entries.find(x => x.baseId === id(desc));
  return e ? e.count : 0;
};
const stage = (a) => (mp.get(a, 'thornswoodChargen') || {}).stage;

check('chargen property registered', captured.properties.has('thornswoodChargen'), true);
check('the timer was armed at load', typeof tickFn, 'function');

// nobody online
online.length = 0;
check('an empty server ticks harmlessly', tick(), '');

// A brand new character: no appearance, no chargen state, and standing outside
// the hall so the move is visible.
state.set(NEW, { appearance: null, worldOrCellDesc: '1a26f:Skyrim.esm' });
inventories.set(NEW, { entries: [] });
online.push(NEW);

// A client that has only just connected is mid save-load. Nothing may touch it.
tick();
check('a joining client is left alone at first', stage(NEW), undefined);
check('and is not teleported while it loads', captured.teleports.has(NEW), false);
advance(SETTLE);

tick();
check('after the settle window, creation opens', stage(NEW), 'appearance');
check('and they are moved into the hall',
      (captured.teleports.get(NEW) || {}).cellOrWorldDesc, HALL);
check('the race menu is left to the spawn system',
      captured.raceMenu.some(([f]) => f === NEW), false);
check('no books until the face is done', has(NEW, WELCOME), 0);

// ticking again before the race menu closes must not repeat itself
const moves = captured.teleports.size;
tick();
check('a second tick does not move them again', captured.teleports.size, moves);
check('still waiting on the appearance', stage(NEW), 'appearance');

// Somebody already standing in the hall is not teleported at all: startPoints
// put them there, and a needless teleport is the risky operation here.
const INHALL = 0xff00aa09;
state.set(INHALL, { appearance: null, worldOrCellDesc: HALL });
inventories.set(INHALL, { entries: [] });
online.push(INHALL);
tick(); advance(SETTLE); tick();
check('a character already in the hall enters creation', stage(INHALL), 'appearance');
check('and is not teleported', captured.teleports.has(INHALL), false);
online.splice(online.indexOf(INHALL), 1);

// a character that existed before this system shipped is left alone
state.set(OLD, { appearance: { isFemale: false } });
inventories.set(OLD, { entries: [] });
online.push(OLD);
tick(); advance(SETTLE); tick();
check('an existing character is not hijacked', stage(OLD), 'done');
check('and is not teleported', captured.teleports.has(OLD), false);
check('and gets no books', has(OLD, WELCOME), 0);

// race menu closed: the appearance turns up
mp.set(NEW, 'appearance', { isFemale: true });
tick();
check('appearance done moves to class', stage(NEW), 'class');
check('the welcome book arrives', has(NEW, WELCOME), 1);
check('and something to wear while choosing', has(NEW, '1be1a:Skyrim.esm'), 1);
check('all six writs arrive', has(NEW, WRIT_MINER) + has(NEW, WRIT_MAGE), 2);
check('no passages yet', has(NEW, PASS_RIFTEN), 0);

// reading a passage before a writ is out of turn
let o = run(() => mp.onReadBook(NEW, id(PASS_RIFTEN)));
check('a passage read out of turn is refused', o.out.includes('out of turn'), true);
check('and changes nothing', stage(NEW), 'class');

// choose a trade
run(() => mp.onReadBook(NEW, id(WRIT_MINER)));
check('reading a writ moves to destination', stage(NEW), 'destination');
check('the trade is recorded', mp.get(NEW, 'thornswoodChargen').class, 'miner');
check('the unread writs are gone', has(NEW, WRIT_MAGE), 0);
check('the read writ is gone too', has(NEW, WRIT_MINER), 0);
check('the pick arrives', has(NEW, 'e3c16:Skyrim.esm'), 1);
check('two torches arrive', has(NEW, '1d4ec:Skyrim.esm'), 2);
check('the novice manual arrives', has(NEW, 'b276:Thornswood-Content.esp'), 1);
check('fifty gold arrives', has(NEW, 'f:Skyrim.esm'), 50);
check('the six passages arrive', has(NEW, PASS_RIFTEN) + has(NEW, PASS_SOLITUDE), 2);
check('the welcome book is still readable', has(NEW, WELCOME), 1);

// a second writ cannot change the answer
o = run(() => mp.onReadBook(NEW, id(WRIT_MAGE)));
check('a second writ is refused', o.out.includes('out of turn'), true);
check('the trade is unchanged', mp.get(NEW, 'thornswoodChargen').class, 'miner');

// choose a town
captured.spawnPoints.delete(NEW);
run(() => mp.onReadBook(NEW, id(PASS_SOLITUDE)));
check('reading a passage finishes creation', stage(NEW), 'done');
check('the town is recorded', mp.get(NEW, 'thornswoodChargen').destination, 'solitude');
check('they are moved to the temple',
      (captured.teleports.get(NEW) || {}).cellOrWorldDesc, '16a02:Skyrim.esm');
check('the respawn point matches the start',
      (captured.spawnPoints.get(NEW) || {}).cellOrWorldDesc, '16a02:Skyrim.esm');
check('start and respawn are the same spot',
      JSON.stringify(captured.teleports.get(NEW).pos),
      JSON.stringify(captured.spawnPoints.get(NEW).pos));
check('the passages are gone', has(NEW, PASS_RIFTEN) + has(NEW, PASS_SOLITUDE), 0);
check('the welcome book is gone', has(NEW, WELCOME), 0);
check('the gear survives', has(NEW, 'e3c16:Skyrim.esm'), 1);

// and they are left alone from now on
const tp = JSON.stringify(captured.teleports.get(NEW));
tick(); tick();
check('a finished character is never touched again',
      JSON.stringify(captured.teleports.get(NEW)), tp);

// the chargen hook must not swallow the skill manuals
inventories.set(NEW, { entries: [] });
state.get(NEW).thornswoodSkills = {};
run(() => mp.onReadBook(NEW, id('b277:Thornswood-Content.esp')));
check('skill manuals still reach their handler',
      mp.get(NEW, 'thornswoodSkills').mining, 2);
check('the new alchemy novice manual works',
      (run(() => mp.onReadBook(NEW, id('e80001:Thornswood-Content.esp'))),
       mp.get(NEW, 'thornswoodSkills').alchemy), 1);

// a trade that gives spell tomes gives tomes, not spells
const M = 0xff00aa03;
state.set(M, { appearance: { isFemale: false }, thornswoodChargen: { stage: 'class' } });
inventories.set(M, { entries: [] });
run(() => mp.onReadBook(M, id(WRIT_MAGE)));
check('the mage gets the Flames tome', has(M, '9cd51:Skyrim.esm'), 1);
check('the mage gets the Healing tome', has(M, '9e2af:Skyrim.esm'), 1);

// hot reload must not stack timers. The server reloads by requiring the file
// again in a fresh module while the Node process, and its timers, live on.
const before = liveTimers;
delete require.cache[require.resolve(PLUGIN)];
logs = [];
require(PLUGIN);
check('a hot reload leaves exactly one timer', liveTimers, before);
check('and rearms the tick', typeof tickFn, 'function');

// with the hall missing the flow still runs, just in place
const F = 0xff00aa04;
missingDescs.add(HALL);
state.set(F, { appearance: null, worldOrCellDesc: '1a26f:Skyrim.esm' });
inventories.set(F, { entries: [] });
online.length = 0; online.push(F);
tick(); advance(SETTLE);
o = { out: tick() };
check('a missing hall is reported, not fatal', o.out.includes('not in this load order'), true);
check('and creation starts anyway', stage(F), 'appearance');
missingDescs.delete(HALL);

// Arrival facings are degrees, not the radians a marker record stores. Read them
// back through a death, which is the only way out of the module.
const rots = [];
for (const [d, p] of [['165a7:Skyrim.esm', [0,0,0]], ['16a02:Skyrim.esm', [0,0,0]],
                      ['16785:Skyrim.esm', [0,0,0]], ['16bd7:Skyrim.esm', [0,0,0]]]) {
  state.set(ACTOR, { worldOrCellDesc: d, pos: p });
  captured.spawnPoints.delete(ACTOR);
  run(() => mp.onDeath(ACTOR, 0));
  const sp = captured.spawnPoints.get(ACTOR);
  if (sp) rots.push(sp.rot[2]);
}
check('some arrival facing exceeds 2pi, so they are degrees',
      rots.some(r => Math.abs(r) > 2 * Math.PI), true);
check('and none exceeds a full turn', rots.every(r => Math.abs(r) <= 360), true);

say(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
