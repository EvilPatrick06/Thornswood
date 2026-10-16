'use strict';
/*
  test-2573-bonds.js

  #2573. Patrick, 16 October: A and B. A guard binds somebody, and they stay
  bound until a guard of the hold frees them; only a guard puts the
  Prisoner's Cuffs on somebody. Both are the Guard role's (#2551).

  The real bonds block runs over a pretend engine, with the property block's
  officeOf, the character block and the place lookup stood in by small
  fakes, and checks:
    - who binds: a guard of the hold the person stands in, next to them, in
      the same cell; nobody else, staff included, and nobody in a place no
      hold answers for;
    - who frees: a guard of the hold the bound person stands in now, or
      staff; the hold that bound them does not matter;
    - the cuffs: a pair the guard carries moves into the bound person's pack
      and the record says so; without one the binding is the same;
    - what bound adds: SPEED off the speed while bound and nothing after;
    - a blow or a cast from somebody bound is said to staff, once a minute;
    - the record is on the character, its owner's script hands it over once
      per change, and nothing in the block runs on a timer;
    - every hold location the load order names is one of the ten holds;
  and that the pieces are wired: the look prompt's near list, the chat
  commands, the staff /unbind, the speed fold, the hit and cast hooks, the
  front plugin's key, prompt and controls, the launcher's Controls row and
  Thornswood.ini, the help panel and the docs. Then the front plugin's own
  bound section runs over a pretend Skyrim Platform: the engine's controls
  are switched once per change and never again, the cuffs go on once with
  the flag that keeps them on, and the two watchdogs leave fighting off
  while bound.
*/
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const REPO_DIR = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
const read = function (p) { return fs.readFileSync(p, 'utf8').split(CR).join(''); };
const gm = read(path.join(REPO_DIR, 'game', 'gamemode.js'));
const front = read(path.join(REPO_DIR, 'game', 'plugins', 'thornswood-front.js'));
const help = read(path.join(REPO_DIR, 'game', 'ui', 'thornswood-help.js'));
const skills = read(path.join(REPO_DIR, 'game', 'ui', 'thornswood-skills.js'));
const keysCs = read(path.join(REPO_DIR, 'launcher', 'app', 'Keys.cs'));
const ini = read(path.join(REPO_DIR, 'launcher', 'Thornswood.ini'));
const offices = read(path.join(REPO_DIR, 'docs', 'systems', 'offices.md'));
const commands = read(path.join(REPO_DIR, 'docs', 'systems', 'commands.md'));
const guide = read(path.join(REPO_DIR, 'Developer-Guide.md'));
const systems = read(path.join(REPO_DIR, 'docs', 'SYSTEMS.md'));

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
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

const block = slice(gm, '// ==== thornswood bonds ====', '// ==== end thornswood bonds ====');
yes('the bonds block is in the gamemode', !!block);
if (!block) { done(); }

// ================================================================ the server
const clock = { t: Date.UTC(2026, 9, 16, 20, 0, 0) };
class FakeDate extends Date { static now() { return clock.t; } }
const CUFFS_ID = 0x10e039;
const PLACE = {
  whiterun: { desc: 'wr-cell', loc: 'WhiterunHoldLocation' },
  riften: { desc: 'rf-cell', loc: 'RiftHoldLocation' },
  nowhere: { desc: 'no-cell', loc: null }
};
function holdAt(place) {
  for (const k in PLACE) { if (PLACE[k].desc === place.desc) { return PLACE[k].loc; } }
  return null;
}
const props = {};          // actorId -> { name: value }
const made = {};           // makeProperty calls
const actors = {};
function person(id, pid, name, place, pos, guards, pack) {
  actors[id] = { pid: pid, name: name, place: place, pos: pos || [0, 0, 0], guards: guards || [],
                 inv: pack || [] };
  return id;
}
const mp = {
  get: function (id, key) {
    const a = actors[id];
    if (!a) { throw new Error('no actor ' + id); }
    if (key === 'profileId') { return a.pid; }
    if (key === 'appearance') { return { name: a.name }; }
    if (key === 'worldOrCellDesc') { return PLACE[a.place].desc; }
    if (key === 'pos') { return a.pos.slice(); }
    if (key === 'inventory') { return { entries: a.inv.map(function (e) { return { baseId: e.baseId, count: e.count }; }) }; }
    return (props[id] || {})[key];
  },
  set: function (id, key, value) {
    const a = actors[id];
    if (!a) { throw new Error('no actor ' + id); }
    if (key === 'inventory') { a.inv = value.entries.map(function (e) { return { baseId: e.baseId, count: e.count }; }); return; }
    (props[id] = props[id] || {})[key] = JSON.parse(JSON.stringify(value));
  },
  makeProperty: function (name, opts) { made[name] = opts; },
  getServerSettings: function () { return { thornswoodServer: 'dev', forBotDir: forBot }; }
};
function idOf(desc) { return desc === '10e039:Skyrim.esm' ? CUFFS_ID : 0; }
function addItem(actorId, desc, count) {
  const id = idOf(desc); if (!id) { return false; }
  const inv = mp.get(actorId, 'inventory').entries;
  let found = false;
  for (const e of inv) { if (e.baseId === id) { e.count += count; found = true; } }
  if (!found) { inv.push({ baseId: id, count: count }); }
  mp.set(actorId, 'inventory', { entries: inv });
  return true;
}
function takeItem(actorId, desc, count) {
  const id = idOf(desc); if (!id) { return false; }
  const inv = mp.get(actorId, 'inventory').entries;
  for (let i = 0; i < inv.length; i++) {
    if (inv[i].baseId !== id) { continue; }
    if (inv[i].count < count) { return false; }
    inv[i].count -= count;
    if (inv[i].count <= 0) { inv.splice(i, 1); }
    mp.set(actorId, 'inventory', { entries: inv });
    return true;
  }
  return false;
}
const told = [];
const logged = [];
const redrawn = [];
const STAFF = { 900: true };
const forBot = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-2573-'));
const g = {
  __thornswoodToProfile: function (pid, text) { told.push({ pid: pid, text: text }); },
  __thornswoodProperty: {
    HOLD_TOWN: { whiterun: 'Whiterun', riften: 'Riften' },
    officeOf: function (pid) {
      for (const id in actors) { if (actors[id].pid === pid) { return { guardOf: actors[id].guards.slice() }; } }
      return { guardOf: [] };
    }
  },
  __thornswoodCharacter: {
    stateOf: function (id) { return { id: id }; },
    writeState: function (id) { redrawn.push(Number(id)); }
  },
  __thornswoodStaffTest: function (pid) { return !!STAFF[pid]; }
};
const ctx = {
  globalThis: g, mp: mp, Date: FakeDate, JSON: JSON, Math: Math, Object: Object, Number: Number,
  String: String, Array: Array, RegExp: RegExp, Error: Error, parseInt: parseInt, console: console,
  require: require, holdAt: holdAt, idOf: idOf, addItem: addItem, takeItem: takeItem,
  log: function () { logged.push(Array.prototype.slice.call(arguments).join(' ')); },
  setInterval: function () { throw new Error('the bonds block must not start a timer'); },
  setTimeout: function () { throw new Error('the bonds block must not start a timer'); }
};
vm.createContext(ctx);
try { vm.runInContext(block, ctx, { filename: 'bonds' }); }
catch (e) { yes('the bonds block runs: ' + e, false); done(); }
const B = g.__thornswoodBonds;
yes('it loads, makes its property for the owner only, and starts no timer',
    !!B && !!made.thornswoodBound && made.thornswoodBound.isVisibleByOwner === true &&
    made.thornswoodBound.isVisibleByNeighbors === false && !!made.thornswoodBound.updateOwner);

// The people.
const GW = person(0xff000503, 503, 'Hrongar', 'whiterun', [0, 0, 0], ['whiterun']);
const GR = person(0xff000505, 505, 'Maven', 'whiterun', [50, 0, 0], ['riften']);
const PR = person(0xff000504, 504, 'Lucan', 'whiterun', [100, 0, 0]);
const SOMEONE = person(0xff000506, 506, 'Ysolda', 'whiterun', [120, 0, 0]);
const STAFFER = person(0xff000900, 900, 'Aela', 'whiterun', [0, 100, 0]);
const FAR = person(0xff000507, 507, 'Faendal', 'whiterun', [1000, 0, 0]);
const hexOf = function (id) { return (id >>> 0).toString(16); };
function rec(id) { return (props[id] || {}).thornswoodBound; }
function lastTold(pid) { const t = told.filter(function (x) { return x.pid === pid; }); return t.length ? t[t.length - 1].text : ''; }
function rows() {
  const f = path.join(forBot, 'moderation.log');
  return fs.existsSync(f) ? fs.readFileSync(f, 'utf8').trim().split('\n').map(function (l) { return JSON.parse(l); }) : [];
}

// Every hold location in the load order's table is one of the ten holds.
const dataLine = gm.split('\n').filter(function (l) { return l.indexOf('const DATA = ') === 0; })[0];
const DATA = JSON.parse(dataLine.slice(dataLine.indexOf('{'), dataLine.lastIndexOf('}') + 1));
const TEN = ['whiterun', 'solitude', 'riften', 'markarth', 'windhelm', 'falkreath', 'morthal', 'dawnstar', 'winterhold', 'ravenrock'];
const locs = Array.from(new Set(Object.values(DATA.cellToHold).concat(Object.keys(DATA.capitals))));
yes('H1 every hold location the load order names is one of the ten holds (' + locs.length + ')',
    locs.length >= 10 && locs.every(function (l) { return TEN.indexOf(B.LOCATION_HOLD[l]) !== -1; }) &&
    TEN.every(function (h) { return Object.values(B.LOCATION_HOLD).indexOf(h) !== -1; }));
yes('H2 the place a person stands answers its hold, and a place no hold answers for answers none',
    B.holdHere(PR) === 'whiterun' && (actors[PR].place = 'nowhere', B.holdHere(PR) === '') &&
    (actors[PR].place = 'whiterun', true));

// Who is offered what.
yes('O1 a guard of Whiterun looking at somebody in Whiterun is offered Bind', B.mark(GW, 503, PR) === 1);
yes('O2 a guard of Riften standing in Whiterun is offered nothing', B.mark(GR, 505, PR) === 0);
yes('O3 nor is somebody who guards nothing, nor staff, who do not bind',
    B.mark(SOMEONE, 506, PR) === 0 && B.mark(STAFFER, 900, PR) === 0);

// Binding refused.
let said = B.press(SOMEONE, 506, [hexOf(PR)]);
yes('R1 somebody who guards nothing is refused, and nothing is written',
    /Only a guard of Whiterun/.test(said) && !rec(PR));
said = B.press(GR, 505, [hexOf(PR)]);
yes('R2 a guard of another hold is told which hold they guard', /You guard Riften, not Whiterun/.test(said) && !rec(PR));
said = B.press(STAFFER, 900, [hexOf(PR)], function () { return true; });
yes('R3 staff do not bind', !!said && !rec(PR));
said = B.press(GW, 503, [hexOf(FAR)]);
yes('R4 too far away is refused', /too far away/.test(said) && !rec(FAR));
actors[PR].place = 'riften';
said = B.press(GW, 503, [hexOf(PR)]);
yes('R5 another cell is refused', /too far away/.test(said) && !rec(PR));
actors[PR].place = 'nowhere'; actors[GW].place = 'nowhere';
said = B.press(GW, 503, [hexOf(PR)]);
yes('R6 a place no hold answers for binds nobody', /No hold answers/.test(said) && !rec(PR));
actors[PR].place = 'whiterun'; actors[GW].place = 'whiterun';
said = B.press(GW, 503, [hexOf(GW)]);
yes('R7 nobody binds themselves', !!said && !rec(GW));
said = B.press(GW, 503, ['zz']);
yes('R8 a line that names nobody is refused', !!said && !rec(PR));
const NPC = person(0xff000777, -1, 'Gerdur', 'whiterun', [60, 0, 0]);
said = B.press(GW, 503, [hexOf(NPC)]);
yes('R9 an NPC, whose profile is -1, is not bound', /Only a person/.test(said) && !rec(NPC));

// Binding.
said = B.press(GW, 503, [hexOf(PR)]);
let r = rec(PR);
yes('B1 a guard of Whiterun binds somebody next to them in Whiterun',
    said === '' && !!r && r.hold === 'whiterun' && r.by === 503 && r.byName === 'Hrongar' && r.at === clock.t && r.cuffs === 0);
yes('B2 both are told, the bound person that a relog does not end it',
    /has bound your hands/.test(lastTold(504)) && /Logging out does not end it/.test(lastTold(504)) &&
    /You bind Lucan/.test(lastTold(503)));
yes('B3 their character is redrawn, so the speed reaches their game', redrawn.indexOf(PR) !== -1);
let mod = rows();
yes('B4 staff are told: a bind row naming the guard, the person and where',
    mod.length === 1 && mod[0].did === 'bind' && mod[0].by === 503 && mod[0].who === 504 &&
    mod[0].server === 'dev' && /Whiterun/.test(mod[0].why));
yes('B5 being bound takes SPEED off the speed', JSON.stringify(B.effects(PR)) === JSON.stringify({ speedMult: B.SPEED }) &&
    B.SPEED < 0 && B.effects(SOMEONE) === null);
actors[PR].guards = ['whiterun'];
yes('B6 a bound person cannot bind anybody, a guard included', B.mark(PR, 504, SOMEONE) === 0 &&
    /Your own hands are bound/.test(B.press(PR, 504, [hexOf(SOMEONE)])) && !B.boundOf(SOMEONE));
actors[PR].guards = [];
yes('B7 nor frees anybody: hands that are bound bind and free nobody, staff included',
    B.markOf({ pid: 900, bound: true, guards: ['whiterun'] }, { bound: true, hold: 'whiterun' }) === 0);
let engineReads = 0;
const realGet = mp.get;
mp.get = function (id, key) { if (key === 'thornswoodBound') { engineReads++; } return realGet(id, key); };
for (let i = 0; i < 50; i++) { B.boundOf(PR); B.boundOf(SOMEONE); }
mp.get = realGet;
yes('B8 the record is read from the engine once a character and kept, so the near list costs no read a pass',
    engineReads === 0 && !!B.boundOf(PR));

// Freeing.
yes('F1 a guard of the hold they stand in is offered Free, staff too, and a guard of another hold nothing',
    B.mark(GW, 503, PR) === 2 && B.mark(STAFFER, 900, PR) === 2 && B.mark(GR, 505, PR) === 0 &&
    B.mark(SOMEONE, 506, PR) === 0);
actors[PR].place = 'riften'; actors[GW].place = 'riften';
yes('F2 walked to Riften, Whiterun\'s guard frees them no longer', B.mark(GW, 503, PR) === 0 &&
    /Only a guard of Riften frees/.test(B.press(GW, 503, [hexOf(PR)])) && !!B.boundOf(PR));
actors[GR].place = 'riften';
said = B.press(GR, 505, [hexOf(PR)]);
r = rec(PR);
yes('F3 and Riften\'s guard does, though Whiterun bound them', said === '' && r && r.free === true && r.by === 505 &&
    !B.boundOf(PR) && B.effects(PR) === null);
mod = rows();
yes('F4 staff are told who freed whom, and who had bound them',
    mod.length === 2 && mod[1].did === 'unbind' && mod[1].by === 505 && /bound in Whiterun by Hrongar/.test(mod[1].why));
yes('F5 the freed person is told they can fight and run again', /freed your hands/.test(lastTold(504)));

// Staff, and a place with no hold.
actors[PR].place = 'whiterun'; actors[GW].place = 'whiterun'; actors[GR].place = 'whiterun';
B.press(GW, 503, [hexOf(PR)]);
actors[PR].place = 'nowhere'; actors[STAFFER].place = 'nowhere'; actors[GW].place = 'nowhere';
yes('S1 somewhere no hold answers for, no guard frees them', B.mark(GW, 503, PR) === 0 &&
    /only staff free/.test(B.press(GW, 503, [hexOf(PR)])));
said = B.press(STAFFER, 900, [hexOf(PR)]);
yes('S2 staff free them there with the same key', said === '' && !B.boundOf(PR) &&
    /Staff have freed your hands/.test(lastTold(504)) && /as staff/.test(rows().slice(-1)[0].why));
actors[PR].place = 'whiterun'; actors[GW].place = 'whiterun'; actors[STAFFER].place = 'whiterun';
B.press(GW, 503, [hexOf(PR)]);
yes('S3 /unbind from the staff block frees them wherever they are', B.staffFree(900, 'Aela', PR) === '' && !B.boundOf(PR));
yes('S4 and says when there is nobody bound', /is not bound/.test(B.staffFree(900, 'Aela', PR)));

// The cuffs (B).
actors[GW].inv = [{ baseId: CUFFS_ID, count: 2 }];
B.press(GW, 503, [hexOf(PR)]);
r = rec(PR);
const cuffsOn = function (id) { const e = actors[id].inv.filter(function (x) { return x.baseId === CUFFS_ID; })[0]; return e ? e.count : 0; };
yes('C1 a guard carrying Prisoner\'s Cuffs hands one pair over with the binding',
    r.cuffs === 1 && cuffsOn(GW) === 1 && cuffsOn(PR) === 1 && /Prisoner's Cuffs/.test(lastTold(504)) &&
    /with a pair of Prisoner's Cuffs/.test(rows().slice(-1)[0].why));
B.press(GW, 503, [hexOf(PR)]);
yes('C2 freed, the pair stays in their pack and the record says they are free', cuffsOn(PR) === 1 && !B.boundOf(PR) &&
    /cuffs come off and stay in your pack/.test(lastTold(504)));
actors[GW].inv = [];
B.press(GW, 503, [hexOf(PR)]);
yes('C3 without a pair the binding is the same, with no cuffs', B.boundOf(PR) && rec(PR).cuffs === 0);
yes('C4 wearing a pair yourself binds nothing: only the record binds, and the block hears no equipping',
    !B.boundOf(SOMEONE) && !/onUpdateEquipmentAttempt|OnObjectEquipped/.test(block));

// A blow or a cast from somebody bound.
const before = rows().length;
yes('W1 a blow from somebody bound is said to staff', B.fought(PR, 'A blow') === true &&
    rows().length === before + 1 && rows().slice(-1)[0].did === 'boundfought');
B.fought(PR, 'A spell');
yes('W2 once a minute a person, not every blow', rows().length === before + 1);
clock.t += 61000;
B.fought(PR, 'A spell');
yes('W3 and again after the minute', rows().length === before + 2 && /A spell while bound/.test(rows().slice(-1)[0].why));
yes('W4 nothing from somebody who is not bound', B.fought(SOMEONE, 'A blow') === false && rows().length === before + 2);

// The owner's script: once per change.
const script = made.thornswoodBound.updateOwner;
const client = {};
const sctx = { ctx: { value: rec(PR), state: {} }, globalThis: client };
vm.createContext(sctx);
let handed = 0;
Object.defineProperty(client, 'thornswoodBound', { set: function (v) { handed++; this._b = v; }, get: function () { return this._b; } });
for (let i = 0; i < 5; i++) { vm.runInContext(script, sctx); }
yes('P1 the owner\'s script hands the record over once, not every frame', handed === 1 && client._b.hold === 'whiterun');
sctx.ctx.value = { v: 1, free: true, at: clock.t + 5 };
vm.runInContext(script, sctx); vm.runInContext(script, sctx);
yes('P2 and the freeing once', handed === 2 && client._b.free === true);
yes('P3 no timer anywhere in the block', !/setInterval|setTimeout/.test(block));

// ============================================================ the wiring
const near = slice(gm, '  function nearTick() {', '\n  }\n');
yes('N1 the near list reads each person\'s binding, place and guard holds once a pass',
    !!near && /bonds\.boundOf\(id\)/.test(near) && /bonds\.holdOfPlace\(cell, pos\)/.test(near) && /bonds\.guardsOf\(/.test(near));
yes('N2 and offers the bind key (k) and says who is bound (b)',
    /markOf\(me, them\)/.test(near) && /\]\.k = kb/.test(near) && /\]\.b = 1/.test(near));
yes('N3 markOf answers the same as mark', B.markOf({ pid: 503, bound: false, guards: ['whiterun'] }, { bound: false, hold: 'whiterun' }) === 1 &&
    B.markOf({ pid: 506, bound: false, guards: [] }, { bound: true, hold: 'whiterun' }) === 0 &&
    B.markOf({ pid: 900, bound: false, guards: [] }, { bound: true, hold: '' }) === 2);
const words = slice(gm, 'const WORDS = [', '];');
yes('K1 /bind and /unbind are words the server answers, and neither is named to people',
    /'\/bind'/.test(words) && /'\/unbind'/.test(words) &&
    !!slice(gm, 'const PLAYER_WORDS = [', '];') && !/'\/bind'|'\/unbind'/.test(slice(gm, 'const PLAYER_WORDS = [', '];')));
yes('K2 /bind hands the bonds block the character, the id and the staff test',
    /if \(word === '\/bind'\) \{[\s\S]{0,400}bonds\.press\(actorId, profileId, parts\.slice\(1\), isStaff\)/.test(gm));
yes('K3 /unbind is a staff word, gated, and frees through the bonds block',
    /var WORDS_STAFF = \[[\s\S]*?'\/unbind'\]/.test(gm) && /var GATED_WORDS = \[[\s\S]*?'\/unbind'\]/.test(gm) &&
    /if \(word === '\/unbind'\) \{[\s\S]{0,400}bonds\.staffFree\(pid, me, them\.actorId\)/.test(gm));
yes('K4 the chat block hands its staff test to the bonds block', /g\.__thornswoodStaffTest = isStaff;/.test(gm));
yes('E1 the speed is folded into both the map the client applies and the panel',
    /return withBonds\(actorId, withCollege\(/.test(gm) && /view\.effects = withBonds\(actorId, view\.effects\);/.test(gm));
yes('E2 a blow and a cast from somebody bound reach fought',
    /bonds\.fought\(idOf\(aggressor\.desc\), 'A blow'\)/.test(gm) && /bonds\.fought\(casterId, 'A spell'\)/.test(gm));
yes('E3 a guard is told on the Office page and when named that the bind key is theirs',
    /you bind and free people in/.test(gm) && /the bind key under your crosshair binds/.test(skills));

// The front plugin, the launcher and the help.
yes('F1 BindKey is 0 in the plugin, the Controls row and Thornswood.ini',
    /const BIND_KEY = iniNumber\(ini, 'BindKey', 11\);/.test(front) && /ThornIni, "BindKey", 11\)\);/.test(keysCs) &&
    /^BindKey = 11$/m.test(ini));
yes('F2 the prompt names it, Bind or Free, from the near list\'s k, and says who is bound',
    /row\.k \? keyRow\(BIND_NAME, row\.k === 2 \? 'Free their hands' : 'Bind their hands'/.test(front) &&
    /\(row\.k \|\| 0\)/.test(front) && /row\.b \? '<span[^>]*> &middot; bound/.test(front));
yes('F3 the key sends /bind with the id only while the prompt offers it',
    /function bindPress\(\) \{[\s\S]{0,400}if \(!row \|\| !row\.k\) \{ return false; \}[\s\S]{0,40}return lookVerb\('bind'\);/.test(front) &&
    /if \(e\.code === BIND_KEY && bindPress\(\)\) \{ return; \}/.test(front));
yes('F4 the help panel names the key as this machine has it, and what bound means',
    /bind: BIND_NAME/.test(front) && /bind: '0'/.test(help) && /binds their hands with ' \+ k\.bind/.test(help) &&
    /wearing a pair yourself does nothing/.test(help));
yes('F5 no other key of ours defaults to 0', (front.match(/iniNumber\(ini, '\w+', 11\)/g) || []).length === 1 &&
    (keysCs.match(/ThornIni, "\w+", 11\)\);/g) || []).length === 1);

// The docs.
yes('D1 offices.md says what bound is, who binds and frees, the cuffs, and what the server cannot hold',
    /## Binding/.test(offices) && /Prisoner's Cuffs/.test(offices) && /cannot refuse/.test(offices) &&
    !/There are no handcuffs/.test(offices));
yes('D2 commands.md lists /bind as a key\'s line and /unbind as staff\'s',
    /`\/bind <id>`/.test(commands) && /`\/unbind`/.test(commands));
yes('D3 the guide\'s staff table has /unbind', /\| `\/unbind <person>` \|/.test(guide));
yes('D4 SYSTEMS.md names the bind key on the look prompt', /0 to bind or free/.test(systems));

// ===================================================== the front's bound section
const sect = slice(front, '  const CUFFS_FORM = 0x10e039;', '  const CONTROLS = [');
yes('the front plugin\'s bound section is there', !!sect);
if (sect) {
  const calls = [];
  const handlers = {};
  let weaponOut = true, cuffsInPack = 0, cuffsWorn = false;
  const cuffsForm = { getFormID: function () { return 0x10e039; } };
  const pc = {
    getFormID: function () { return 0x14; },
    isWeaponDrawn: function () { return weaponOut; },
    sheatheWeapon: function () { calls.push('sheathe'); weaponOut = false; },
    getItemCount: function () { return cuffsInPack; },
    equipItem: function (f, keep, silent) { calls.push('equip ' + keep + ' ' + silent); cuffsWorn = true; },
    isEquipped: function () { return cuffsWorn; },
    unequipItem: function (f, a, b) { calls.push('unequip'); cuffsWorn = false; }
  };
  const fsp = {
    on: function (name, fn) { (handlers[name] = handlers[name] || []).push(fn); },
    Game: {
      getPlayer: function () { return pc; },
      getFormEx: function (id) { return id === 0x10e039 ? cuffsForm : null; },
      disablePlayerControls: function () { calls.push('disable ' + Array.prototype.slice.call(arguments).join(',')); },
      enablePlayerControls: function () { calls.push('enable ' + Array.prototype.slice.call(arguments).join(',')); }
    }
  };
  const fg = { thornswoodBound: null };
  const fctx = { sp: fsp, globalThis: fg, say: function () { }, guard: function (n, fn) { return fn; },
                 String: String, Number: Number, Array: Array };
  vm.createContext(fctx);
  vm.runInContext(sect.slice(0, -'  const CONTROLS = ['.length) + '\n;globalThis.__test = { controlsBackOn: controlsBackOn, bound: function () { return boundOn; } };', fctx);
  const frame = function (n) { for (let i = 0; i < (n || 1); i++) { handlers.update.forEach(function (h) { h(); }); } };
  frame(10);
  yes('C0 nothing is switched while nobody is bound', calls.length === 0);
  fg.thornswoodBound = { v: 1, hold: 'whiterun', byName: 'Hrongar', at: 1, cuffs: 1 };
  frame(30);
  yes('C1 bound: fighting off, and only fighting, once in thirty frames',
      calls.filter(function (c) { return c.indexOf('disable') === 0; }).length === 1 &&
      calls.indexOf('disable false,true,false,false,false,false,false,false,0') !== -1);
  yes('C2 a drawn weapon is sheathed, once', calls.filter(function (c) { return c === 'sheathe'; }).length === 1);
  yes('C3 the cuffs not in the pack yet are not put on, and not looked for every frame',
      calls.filter(function (c) { return c.indexOf('equip') === 0; }).length === 0);
  cuffsInPack = 1;
  handlers.containerChanged.forEach(function (h) { h({ baseObj: cuffsForm, newContainer: pc, oldContainer: null }); });
  handlers.containerChanged.forEach(function (h) { h({ baseObj: cuffsForm, newContainer: pc, oldContainer: null }); });
  yes('C4 they go on when they arrive, once, with the flag that keeps them on',
      calls.filter(function (c) { return c === 'equip true true'; }).length === 1);
  fctx.__test = fg.__test;
  fg.__test.controlsBackOn();
  yes('C5 the watchdogs turn controls back on with fighting left off while bound',
      calls.slice(-1)[0] === 'enable true,false,true,true,true,true,true,true,true');
  yes('C6 the controls watchdog does not count fighting off while bound as stuck',
      /readControls\(\)\.filter\(\(c\) => !\(boundOn && c === 'fighting'\)\)/.test(front) &&
      (front.match(/controlsBackOn\(\);/g) || []).length === 2 &&
      !/enablePlayerControls\(true, true, true, true, true, true, true, true, true\)/.test(front));
  const n0 = calls.length;
  fg.thornswoodBound = { v: 1, free: true, at: 2 };
  frame(30);
  yes('C7 freed: fighting back on and the cuffs off, once each',
      calls.length === n0 + 2 && calls[n0] === 'enable false,true,false,false,false,false,false,false,0' &&
      calls[n0 + 1] === 'unequip' && fg.__test.bound() === false);
  fg.__test.controlsBackOn();
  yes('C8 after that the watchdogs turn fighting on like the rest',
      calls.slice(-1)[0] === 'enable true,true,true,true,true,true,true,true,true');
  yes('C9 nothing in the section runs on a timer', !/setInterval|setTimeout/.test(sect));
}

try { fs.rmSync(forBot, { recursive: true, force: true }); } catch (e) { }
done();
