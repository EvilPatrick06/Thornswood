// test-2573-cuffs.js
//
//     node tests/test-2573-cuffs.js
//
// #2573, Patrick 16 Oct 2026: A and B. A guard of a hold puts the
// Prisoner's Cuffs on from their own pack, facing a person: that person is
// bound (cuffs on, hands bound, fighting off, no weapon) until a guard puts
// a pair on facing them again; only guards put the cuffs on anybody. In the
// world only: no slash command, and not E on a person, which already hands
// over a letter (#1595).
//
// Root cause and design: issue #2573, issuecomment-6226678131.
//
// Runs the REAL cuffs block over a stand-in mp, packs, offices and places;
// its client scripts over a stand-in Skyrim Platform; the REAL front plugin
// watchdog helpers over a stand-in game (#2620); and reads the REAL wiring.
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const gm = fs.readFileSync(path.join(ROOT, 'game', 'gamemode.js'), 'utf8').split(String.fromCharCode(13)).join('');

let pass = 0, fail = 0;
function yes(what, ok) {
  if (ok) { pass++; console.log('PASS  ' + what); } else { fail++; console.log('FAIL  ' + what); }
}
function slice(a, b) {
  const i = gm.indexOf(a);
  const j = i < 0 ? -1 : gm.indexOf(b, i);
  return (i >= 0 && j >= 0) ? gm.slice(i, j + b.length) : null;
}
const block = slice('// ==== thornswood cuffs (#2573) ====', '// ==== end thornswood cuffs ====');
yes('the cuffs block is in the gamemode', !!block);
yes('...and runs no command: no slash line anywhere in it', !!block && !/['"]\/[a-z]+/i.test(block.replace(/\/\*[\s\S]*?\*\//g, '')));

const CUFFS = 0x10e039;
function idOf(d) { return d === '10e039:Skyrim.esm' ? CUFFS : 0; }

function rig(src, opts) {
  const clock = { now: Date.UTC(2026, 9, 16, 18, 0, 0) };
  const props = {}, said = [], made = {}, timers = [];
  const people = {};   // actorId -> { pid, place, inv: {baseId: n} }
  const guards = {};   // pid -> [holds]
  let far = 0;
  function person(id, pid, place) { far += 1000; people[id] = { pid: pid, place: place, inv: {}, pos: [far, far, 0], rot: 0 }; props[id] = {}; return id; }
  // a stands at the middle facing north; b one step in front; everybody else far off.
  function face(a, b, away) {
    let k = 0;
    for (const id of Object.keys(people)) { k += 1000; people[id].pos = [5000 + k, 5000 + k, 0]; }
    people[a].pos = [0, 0, 0]; people[a].rot = 0;
    if (b) { people[b].pos = away || [0, 100, 0]; }
  }
  const strengthAsked = [];
  const mp = {
    makeProperty: function (k, o) { made[k] = o; },
    getOnlinePlayers: function () { return Object.keys(people).map(Number); },
    get: function (id, key) {
      const p = people[id];
      if (!p) { throw new Error('no such form'); }
      if (key === 'profileId') { return p.pid; }
      if (key === 'locationalData') { return p.place ? { cellOrWorldDesc: p.place, pos: p.pos.slice(), rot: [0, 0, p.rot] } : null; }
      if (key === 'inventory') { return { entries: Object.keys(p.inv).map(function (b) { return { baseId: Number(b), count: p.inv[b] }; }) }; }
      return props[id][key];
    },
    set: function (id, key, v) { props[id][key] = JSON.parse(JSON.stringify(v)); },
    lookupEspmRecordById: function (id) { return id === 0x12eb7 ? { record: { type: 'WEAP' } } : (id === CUFFS ? { record: { type: 'ARMO' } } : null); },
    // The strength gate (#2262) already registered, as it would be on main.
    onEquipItemAttempt: function (a, b) { strengthAsked.push([a, b]); return b !== 0xdead; }
  };
  function count(id, b) { return people[id].inv[b] || 0; }
  function addItem(id, desc, n) { const b = idOf(desc); if (!b) { return false; } people[id].inv[b] = count(id, b) + n; return true; }
  function takeItemById(id, b, n) { if (count(id, b) < n) { return false; } people[id].inv[b] -= n; if (!people[id].inv[b]) { delete people[id].inv[b]; } return true; }
  function holdAt(place) { return ({ 'whiterunCell:T.esm': 'whiterun', 'riftenCell:T.esm': 'riften' })[place.desc] || null; }
  const g = {
    __thornswoodProperty: {
      officeOf: function (pid) { return { guardOf: (guards[pid] || []).slice() }; },
      HOLD_TOWN: { whiterun: 'Whiterun', riften: 'Riften' }
    }
  };
  if (opts && opts.before !== undefined) { if (opts.before === null) { delete mp.onEquipItemAttempt; } else { mp.onEquipItemAttempt = opts.before; } }
  function load() {
    return new Function('globalThis', 'mp', 'Date', 'setInterval', 'clearInterval', 'guard', 'notify', 'say', 'log',
      'idOf', 'addItem', 'takeItemById', 'holdAt', (src || block) + '\nreturn globalThis.__thornswoodCuffs;')(
      g, mp, { now: function () { return clock.now; } }, function (f, ms) { timers.push(ms); return 1; }, function () { },
      function (n, f) { return f; }, function () { }, function (id, line) { said.push([id, line]); }, function () { },
      idOf, addItem, takeItemById, holdAt);
  }
  const C = (opts && opts.noLoad) ? null : load();
  return { C: C, load: load, g: g, clock: clock, said: said, made: made, timers: timers, people: people, guards: guards,
           person: person, face: face, mp: mp, strengthAsked: strengthAsked, count: count, addItem: addItem, props: props,
           last: function (id) { for (let i = said.length - 1; i >= 0; i--) { if (said[i][0] === id) { return said[i][1]; } } return ''; } };
}

let r = null;
try { r = block ? rig() : null; } catch (e) { console.log('rig threw: ' + e.message); }
const C = r && r.C;
yes('the block loads and answers a pair put on', !!C && typeof C.used === 'function' && typeof C.mayLetGo === 'function' && typeof C.mayEquip === 'function');

if (C && typeof C.used === 'function') {
  const PROP = C.CUFF_PROPERTY;
  yes('the cuffed record is seen by its owner and by neighbours, with a script for each',
    !!r.made[PROP] && r.made[PROP].isVisibleByOwner && r.made[PROP].isVisibleByNeighbors &&
    !!r.made[PROP].updateOwner && !!r.made[PROP].updateNeighbor);
  yes('the issue record is the server\'s alone', !!r.made.thornswoodCuffsIssued && !r.made.thornswoodCuffsIssued.isVisibleByOwner);
  yes('guards are looked at for an issue on a timer', r.timers.length === 1 && r.timers[0] > 0);

  const G = r.person(0xff000001, 11, 'whiterunCell:T.esm');   // guard of Whiterun
  const P = r.person(0xff000002, 12, 'whiterunCell:T.esm');   // somebody
  const X = r.person(0xff000003, 13, 'whiterunCell:T.esm');   // not a guard
  const R = r.person(0xff000004, 14, 'whiterunCell:T.esm');   // guard of Riften
  const N = 0x1a2b3;                                          // an NPC, no profile
  r.people[N] = { pid: 0, place: 'whiterunCell:T.esm', inv: {} }; r.props[N] = {};
  r.guards[11] = ['whiterun']; r.guards[14] = ['riften'];

  // Issuing.
  yes('a guard with no cuffs is issued one pair', C.issue(G) === true && r.count(G, CUFFS) === 1 && /issued a pair/.test(r.last(G)));
  yes('...and not a second while they carry one', C.issue(G) === false && r.count(G, CUFFS) === 1);
  yes('somebody who is not a guard is issued nothing', C.issue(X) === false && r.count(X, CUFFS) === 0);
  C.tick();
  yes('the timer issues the Riften guard theirs too', r.count(R, CUFFS) === 1);

  const C_ = '10e039:Skyrim.esm';
  // Putting a pair on with nobody in front.
  r.face(X, 0);
  yes('a pair put on by somebody who is not a guard, with nobody in front, is clothing',
    (r.addItem(X, C_, 1), C.used(X) === false && r.last(X) === ''));
  r.face(G, 0);
  yes('a guard with nobody in front is told to face somebody, and keeps the pair',
    C.used(G) === true && r.count(G, CUFFS) === 1 && /Face the person/.test(r.last(G)));
  r.face(G, P, [0, -100, 0]);
  yes('...and somebody behind them is not in front of them', C.used(G) === true && !C.cuffedBy(P));
  r.face(G, P, [0, 400, 0]);
  yes('...nor somebody out of reach', C.used(G) === true && !C.cuffedBy(P));
  r.face(G, N);
  yes('...nor an NPC', C.used(G) === true && C.facing(G) === 0);

  // B: only guards put cuffs on somebody.
  r.face(X, P);
  yes('somebody who is not a guard, facing a person, cannot cuff them (B), and their pair is theirs to wear',
    C.used(X) === false && !C.cuffedBy(P) && r.count(X, CUFFS) === 1 && /Only a hold's guards/.test(r.last(X)));
  r.face(R, P);
  yes('a guard of another hold cannot cuff here',
    C.used(R) === true && !C.cuffedBy(P) && r.count(R, CUFFS) === 1 && /Riften/.test(r.last(R)) && /Whiterun/.test(r.last(R)));

  // A: cuffing.
  r.face(G, P);
  yes('a guard of the hold, facing somebody, puts a pair on and cuffs them', C.used(G) === true && !!C.cuffedBy(P));
  const rec = r.props[P][PROP];
  yes('...in that hold\'s name, by that guard, with the cuffs\' id for their game',
    rec.bound === true && rec.hold === 'whiterun' && rec.by === 11 && rec.item === CUFFS && rec.at > 0);
  yes('...and the pair moves from the guard\'s pack to theirs', r.count(G, CUFFS) === 0 && r.count(P, CUFFS) === 1);
  yes('...and both are told', /in the name of Whiterun/.test(r.last(G)) && /puts you in cuffs/.test(r.last(P)));
  yes('...and nobody is told to press E or type anything', !/press E|\//i.test(r.last(G) + r.last(P)));

  // Bound: the pair stays on, no weapon.
  yes('a bound person cannot drop the cuffs', C.mayLetGo(P, CUFFS, 1) === false && /locked on your wrists/.test(r.last(P)));
  yes('...or anything else of theirs is still theirs to drop', C.mayLetGo(P, 0xf, 5) === true);
  yes('somebody free drops cuffs as they like', C.mayLetGo(X, CUFFS, 1) === true);
  yes('a bound guard is issued nothing', (r.guards[12] = ['whiterun'], C.issue(P) === false));
  delete r.guards[12];
  yes('a bound person cannot put a weapon in their hands (onEquipItemAttempt)',
    r.mp.onEquipItemAttempt(P, 0x12eb7) === false && /hands are cuffed/.test(r.last(P)));
  yes('...but the cuffs themselves go on', r.mp.onEquipItemAttempt(P, CUFFS) === true);
  yes('...and somebody free wields what the strength gate allows, which is still asked',
    r.mp.onEquipItemAttempt(X, 0x12eb7) === true && r.strengthAsked.some(function (q) { return q[0] === X && q[1] === 0x12eb7; }));
  yes('...and the strength gate\'s own refusal still stands', r.mp.onEquipItemAttempt(X, 0xdead) === false);
  r.face(P, X);
  yes('a bound person putting on cuffs facing somebody binds nobody', C.used(P) === false && !C.cuffedBy(X));

  // Freeing: any guard of any hold (Patrick, 17 Oct). No hold rule, no switch.
  yes('one freeing rule, no switch and no hold: being a guard', !/FREE_BY|binder|freeingHold/.test(block) && typeof C.mayFree === 'function');
  r.addItem(X, C_, 1);
  r.face(X, P);
  yes('somebody who is not a guard cannot free them', C.used(X) === true && !!C.cuffedBy(P) && /only a guard can take them off/.test(r.last(X)));
  r.face(R, P);
  yes('a guard of another hold frees them, here in Whiterun, from Whiterun\'s cuffs', C.used(R) === true && !C.cuffedBy(P));
  yes('...and the prisoner\'s pair goes into that guard\'s pack', r.count(P, CUFFS) === 0 && r.count(R, CUFFS) === 2);
  const freed = r.props[P][PROP];
  yes('...and the record says free, with a new stamp for their game', freed.bound === false && freed.at > rec.at);
  yes('...and they are told a guard freed them', /A guard takes the cuffs off/.test(r.last(P)));
  yes('freed, they drop cuffs as they like again', C.mayLetGo(P, CUFFS, 1) === true);
  yes('freed, a weapon goes in their hands again', r.mp.onEquipItemAttempt(P, 0x12eb7) === true);
  const G2 = r.person(0xff000005, 15, 'whiterunCell:T.esm'); r.guards[15] = ['whiterun'];

  // Wherever they stand, any guard.
  {
    const r3 = rig(), C3 = r3.C;
    const g1 = r3.person(0xff000011, 21, 'whiterunCell:T.esm'), pr = r3.person(0xff000012, 22, 'whiterunCell:T.esm');
    const g2 = r3.person(0xff000013, 23, 'riftenCell:T.esm');
    r3.guards[21] = ['whiterun']; r3.guards[23] = ['riften'];
    r3.addItem(g1, C_, 1); r3.addItem(g2, C_, 1);
    r3.face(g1, pr); C3.used(g1);
    yes('cuffed in Whiterun', !!C3.cuffedBy(pr) && C3.cuffedBy(pr).hold === 'whiterun');
    r3.people[pr].place = 'nowhere:T.esm'; r3.people[g2].place = 'nowhere:T.esm';
    r3.face(g2, pr);
    yes('...and in a place with no hold, a guard of Riften frees them', C3.used(g2) === true && !C3.cuffedBy(pr));
    r3.people[pr].place = 'whiterunCell:T.esm'; r3.people[g1].place = 'whiterunCell:T.esm';
    r3.face(g1, pr); C3.used(g1);
    r3.people[pr].place = 'riftenCell:T.esm'; r3.people[g1].place = 'riftenCell:T.esm';
    r3.face(g1, pr);
    yes('...and in Riften, the Whiterun guard who cuffed them frees them too', C3.used(g1) === true && !C3.cuffedBy(pr));
  }

  // Place rules.
  r.addItem(G2, C_, 1);
  r.people[P].place = 'riftenCell:T.esm'; r.people[G2].place = 'riftenCell:T.esm';
  r.face(G2, P);
  yes('a Whiterun guard cannot cuff in Riften', C.used(G2) === true && !C.cuffedBy(P));
  r.people[P].place = 'nowhere:T.esm'; r.people[G2].place = 'nowhere:T.esm';
  r.face(G2, P);
  yes('where the data gives no hold, a guard of one hold cuffs in its name', C.used(G2) === true && C.cuffedBy(P).hold === 'whiterun');
  r.face(G2, P); C.used(G2);
  r.guards[15] = ['whiterun', 'riften'];
  r.face(G2, P);
  yes('...but not a guard of two, who would not know whose cuffs these are', C.used(G2) === true && !C.cuffedBy(P));
  r.face(G2, P, [0, 100, 0]);
  r.people[P].place = 'whiterunCell:T.esm';
  yes('somebody in another cell is not in front of you', C.facing(G2) === 0);

  // The engine without onEquipItemAttempt: the stored equipment.
  {
    const r4 = rig(), C4 = r4.C;
    const g = r4.person(0xff000021, 31, 'whiterunCell:T.esm'), p = r4.person(0xff000022, 32, 'whiterunCell:T.esm');
    r4.guards[31] = ['whiterun']; r4.addItem(g, C_, 1);
    const worn = { inv: { entries: [{ baseId: CUFFS, count: 1, worn: true }] } };
    const bare = { inv: { entries: [{ baseId: CUFFS, count: 1 }] } };
    r4.face(g, p);
    C4.equipped(g, worn);
    yes('the first look at somebody after they arrive only remembers, so a pair worn at logout does nothing', !C4.cuffedBy(p));
    C4.equipped(g, bare); C4.equipped(g, worn);
    yes('a pair newly worn, facing somebody, cuffs them through the stored equipment', !!C4.cuffedBy(p));
    yes('...and the guard\'s own game is told to take the pair back off', !!(r4.props[g][C4.USE_PROPERTY] && r4.props[g][C4.USE_PROPERTY].item === CUFFS));
    C4.equipped(g, worn);
    yes('...and the same equipment again does nothing more', !!C4.cuffedBy(p) && r4.count(p, CUFFS) === 1);
    C4.equipped(p, worn); C4.equipped(p, bare); C4.equipped(p, worn);
    yes('the prisoner\'s own locked pair is not a use', !C4.cuffedBy(g));
    yes('the use record is the owner\'s, with a script', !!r4.made[C4.USE_PROPERTY] && r4.made[C4.USE_PROPERTY].isVisibleByOwner && !r4.made[C4.USE_PROPERTY].isVisibleByNeighbors);
  }
  // With onEquipItemAttempt: the pair acts and stays in the pack.
  {
    const r5 = rig(), C5 = r5.C;
    const g = r5.person(0xff000031, 41, 'whiterunCell:T.esm'), p = r5.person(0xff000032, 42, 'whiterunCell:T.esm');
    r5.guards[41] = ['whiterun']; r5.addItem(g, C_, 1);
    r5.face(g, p);
    yes('with the fork event, the guard\'s pair is refused on the guard and cuffs the person in front',
      r5.mp.onEquipItemAttempt(g, CUFFS) === false && !!C5.cuffedBy(p));
    const x = r5.person(0xff000033, 43, 'whiterunCell:T.esm'); r5.addItem(x, C_, 1); r5.face(x, 0);
    yes('...and anybody else with nobody in front wears theirs', r5.mp.onEquipItemAttempt(x, CUFFS) === true);
  }

  // Sharing onEquipItemAttempt with the strength gate (#2621), both load orders.
  {
    const WEAK = 0x5eed;   // a stand-in heavy weapon only strength refuses
    // Stand-in strength gate, written to Waystone's pattern (f3e954cb): wraps
    // what is there, asks it first, says nothing when it refused, unwraps its
    // own wrapper on a reload.
    function loadStrength(m, told) {
      const SH = '__thornswoodStrengthHeld';
      let before = m.onEquipItemAttempt;
      if (typeof before === 'function' && Object.prototype.hasOwnProperty.call(before, SH)) { before = before[SH]; }
      if (typeof before !== 'function') { before = null; }
      const gate = function (a, b) {
        if (before && before(a, b) === false) { return false; }
        if (b === WEAK) { told.push('strength'); return false; }
        return true;
      };
      gate[SH] = before;
      m.onEquipItemAttempt = gate;
    }
    const answers = {};
    for (const order of ['cuffs then strength', 'strength then cuffs']) {
      const q = rig(null, { before: null, noLoad: true }), told = [];
      if (order === 'cuffs then strength') { q.load(); loadStrength(q.mp, told); } else { loadStrength(q.mp, told); q.load(); }
      const Q = q.g.__thornswoodCuffs;
      const cg = q.person(0xff000041, 51, 'whiterunCell:T.esm'), cp = q.person(0xff000042, 52, 'whiterunCell:T.esm');
      const fr = q.person(0xff000043, 53, 'whiterunCell:T.esm');
      q.guards[51] = ['whiterun']; q.addItem(cg, C_, 1); q.face(cg, cp); Q.used(cg);
      const tells = function (id) { return q.said.filter(function (x) { return x[0] === id; }).length; };
      const a = [];
      let n0 = tells(cp); told.length = 0;
      a.push(q.mp.onEquipItemAttempt(cp, 0x12eb7));
      yes(order + ': a cuffed person is refused a sword, told once', a[0] === false && tells(cp) - n0 === 1 && told.length === 0);
      n0 = tells(cp); told.length = 0;
      a.push(q.mp.onEquipItemAttempt(cp, WEAK));
      yes(order + ': a cuffed person is refused a heavy weapon, with one refusal only', a[1] === false && (tells(cp) - n0) + told.length === 1);
      told.length = 0; n0 = tells(fr);
      a.push(q.mp.onEquipItemAttempt(fr, WEAK));
      yes(order + ': somebody free is still refused the heavy weapon by strength, once', a[2] === false && told.length === 1 && tells(fr) === n0);
      a.push(q.mp.onEquipItemAttempt(fr, 0x12eb7));
      yes(order + ': somebody free wields a sword through both', a[3] === true);
      a.push(q.mp.onEquipItemAttempt(cp, CUFFS));
      yes(order + ': the cuffs go on the cuffed person through both', a[4] === true);
      answers[order] = a;
    }
    yes('the two load orders give the same answer for every case',
      JSON.stringify(answers['cuffs then strength']) === JSON.stringify(answers['strength then cuffs']));

    // Reloads: the file order is strength then cuffs, so a reload wraps the old cuffs gate in the new strength gate.
    const q = rig(null, { before: null, noLoad: true }), told = [];
    loadStrength(q.mp, told); q.load();
    loadStrength(q.mp, told); q.load();
    loadStrength(q.mp, told); q.load();
    q.load(); q.load();
    const Q = q.g.__thornswoodCuffs;
    const cg = q.person(0xff000051, 61, 'whiterunCell:T.esm'), cp = q.person(0xff000052, 62, 'whiterunCell:T.esm');
    q.guards[61] = ['whiterun']; q.addItem(cg, C_, 1); q.addItem(cg, C_, 1);
    q.face(cg, cp);
    const before = q.said.length;
    yes('after reloads in file order, a pair put on facing somebody cuffs them once', q.mp.onEquipItemAttempt(cg, CUFFS) === false && !!Q.cuffedBy(cp) && q.count(cg, CUFFS) === 1);
    yes('...and nobody is told twice', q.said.length - before === 2);
    const n1 = q.said.filter(function (x) { return x[0] === cp; }).length;
    yes('...and a cuffed person\'s sword is refused with one line, not one per load',
      q.mp.onEquipItemAttempt(cp, 0x12eb7) === false && q.said.filter(function (x) { return x[0] === cp; }).length - n1 === 1);
    const nx = q.person(0xff000053, 63, 'whiterunCell:T.esm'); q.addItem(nx, C_, 1);
    q.face(nx, cg);
    const n2 = q.said.filter(function (x) { return x[0] === nx; }).length;
    yes('...and somebody who is not a guard, putting cuffs on facing a person, is told once that only guards cuff, not once per load',
      q.mp.onEquipItemAttempt(nx, CUFFS) === true && q.said.filter(function (x) { return x[0] === nx; }).length - n2 === 1);
    const q2 = rig(null, { before: null, noLoad: true });
    q2.load(); q2.load(); q2.load();
    yes('reloaded alone, the cuffs gate holds what was there before the first load, not itself', q2.g.__thornswoodCuffs.equipBefore === null);
  }

  // Only a strict false from the gate held is a refusal (Codex to Waystone, 17 Oct).
  for (const v of [undefined, null, 0, '', NaN, true]) {
    const q = rig(null, { before: function () { return v; } });
    const Q = q.C;
    const qg = q.person(0xff000061, 71, 'whiterunCell:T.esm'), qp = q.person(0xff000062, 72, 'whiterunCell:T.esm');
    const qx = q.person(0xff000063, 73, 'whiterunCell:T.esm');
    q.guards[71] = ['whiterun']; q.addItem(qg, C_, 1); q.face(qg, qp);
    const name = 'the gate held answering ' + (typeof v === 'string' ? "''" : String(v));
    yes(name + ': not a refusal, so a pair put on facing somebody still cuffs them',
      q.mp.onEquipItemAttempt(qg, CUFFS) === false && !!Q.cuffedBy(qp) && q.count(qp, CUFFS) === 1);
    const n = q.said.filter(function (x) { return x[0] === qp; }).length;
    yes(name + ': the cuffs still refuse a cuffed person\'s sword, told once',
      q.mp.onEquipItemAttempt(qp, 0x12eb7) === false && q.said.filter(function (x) { return x[0] === qp; }).length - n === 1);
    yes(name + ': somebody free is not refused a sword', q.mp.onEquipItemAttempt(qx, 0x12eb7) !== false);
  }
  {
    const q = rig(null, { before: function () { return false; } });
    const Q = q.C;
    const qg = q.person(0xff000064, 74, 'whiterunCell:T.esm'), qp = q.person(0xff000065, 75, 'whiterunCell:T.esm');
    q.guards[74] = ['whiterun']; q.addItem(qg, C_, 1); q.face(qg, qp);
    yes('the gate held answering false: refused, the cuffs say nothing and cuff nobody',
      q.mp.onEquipItemAttempt(qg, CUFFS) === false && !Q.cuffedBy(qp) && q.count(qg, CUFFS) === 1 && q.said.length === 0);
  }

  // Waiting on the join pass (#410): onEquipItemAttempt is not in guard()'s ACTS_AS, so it reaches
  // the cuffs; they give no answer (a bare return), never a refusal, and cuff, free and issue nobody.
  yes('onEquipItemAttempt is not held back by guard() for the join pass (so the cuffs must not act or refuse themselves)',
    /const ACTS_AS = \{[^}]*\}/.test(gm) && !/onEquipItemAttempt/.test(gm.match(/const ACTS_AS = \{[^}]*\}/)[0]));
  yes('the cuffs gate returns nothing for somebody waiting', /if \(waiting\(actorId\)\) \{ return; \}/.test(block));
  {
    const q = rig();
    const Q = q.C;
    const held = {};
    q.g.__thornswoodPassHeld = function (pid) { return !!held[pid]; };
    const wg = q.person(0xff000071, 81, 'whiterunCell:T.esm'), wp = q.person(0xff000072, 82, 'whiterunCell:T.esm');
    const wx = q.person(0xff000073, 83, 'whiterunCell:T.esm'), wc = q.person(0xff000074, 84, 'whiterunCell:T.esm');
    const ok = q.person(0xff000075, 85, 'whiterunCell:T.esm');
    q.guards[81] = ['whiterun']; q.guards[85] = ['whiterun'];
    // wc is cuffed while nobody waits.
    q.addItem(ok, C_, 1); q.face(ok, wc); Q.used(ok);
    yes('(set-up) a cuffed person to free', !!Q.cuffedBy(wc));
    held[81] = held[83] = held[84] = true;
    const quiet = function (ids, from) { return q.said.slice(from).every(function (x) { return ids.indexOf(x[0]) === -1; }); };
    q.addItem(wg, C_, 2);
    let s0 = q.said.length;
    q.face(wg, wp);
    const a1 = q.mp.onEquipItemAttempt(wg, CUFFS);
    yes('a guard waiting on the pass, facing somebody with a pair: no answer (undefined), nobody cuffed, the pair stays, nobody told',
      a1 === undefined && !Q.cuffedBy(wp) && q.count(wg, CUFFS) === 2 && q.count(wp, CUFFS) === 0 && quiet([wg, wp], s0));
    s0 = q.said.length;
    q.face(wg, wc);
    const a2 = q.mp.onEquipItemAttempt(wg, CUFFS);
    yes('...facing a cuffed person: no answer, they stay cuffed, the pair stays where it is, nobody told',
      a2 === undefined && !!Q.cuffedBy(wc) && q.count(wc, CUFFS) === 1 && q.count(wg, CUFFS) === 2 && quiet([wg, wc], s0));
    s0 = q.said.length;
    yes('...with nobody in front: no answer and no "face the person" line', (q.face(wg, 0), q.mp.onEquipItemAttempt(wg, CUFFS) === undefined && quiet([wg], s0)));
    q.addItem(wx, C_, 1); q.face(wx, wp); s0 = q.said.length;
    yes('somebody waiting who is not a guard: no answer, no "only guards" line',
      q.mp.onEquipItemAttempt(wx, CUFFS) === undefined && !Q.cuffedBy(wp) && quiet([wx, wp], s0));
    s0 = q.said.length;
    yes('somebody waiting whose character carries a cuffed record: a sword gets no answer, not a refusal, and no line',
      q.mp.onEquipItemAttempt(wc, 0x12eb7) === undefined && quiet([wc], s0));
    q.face(wg, wp);
    yes('used() itself acts for nobody waiting', Q.used(wg) === false && !Q.cuffedBy(wp));
    q.people[wg].inv = {};
    yes('a guard waiting is issued nothing, directly or by the timer', Q.issue(wg) === false && (Q.tick(), q.count(wg, CUFFS) === 0));
    // The stored-equipment path, waiting then passed: nothing acts, and the first look after the pass is only a baseline.
    q.addItem(wg, C_, 1); q.face(wg, wp);
    const worn = function (on) { return { inv: { entries: [{ baseId: CUFFS, count: 1, worn: on }] } }; };
    Q.equipped(wg, worn(false)); Q.equipped(wg, worn(true));
    yes('the stored-equipment path does nothing for somebody waiting', !q.props[wg][Q.USE_PROPERTY]);
    delete held[81];
    Q.equipped(wg, worn(true));
    yes('...and once the pass is in, a pair worn from before is only the baseline', !q.props[wg][Q.USE_PROPERTY]);
    const pass = q.mp.onEquipItemAttempt(wg, CUFFS);
    yes('...and after the pass the same guard cuffs as usual', pass === false && !!Q.cuffedBy(wp));
    // No profile yet, and a pass check that throws: both treated as waiting.
    const np = 0xff000076; q.people[np] = { pid: 0, place: 'whiterunCell:T.esm', inv: {}, pos: [0, 0, 0], rot: 0 }; q.props[np] = {};
    yes('somebody with no profile on them yet gets no answer', q.mp.onEquipItemAttempt(np, 0x12eb7) === undefined && q.mp.onEquipItemAttempt(np, CUFFS) === undefined);
    q.g.__thornswoodPassHeld = function () { throw new Error('boom'); };
    yes('a pass check that throws counts as waiting: no answer, nobody freed', (q.face(ok, wp), q.addItem(ok, C_, 1), q.mp.onEquipItemAttempt(ok, CUFFS) === undefined && !!Q.cuffedBy(wp)));
  }
  // Waiting, with the stand-in strength gate in both load orders: the cuffs never add a refusal of their own.
  for (const order of ['cuffs then strength', 'strength then cuffs']) {
    const WEAK = 0x5eed;
    const q = rig(null, { before: null, noLoad: true }), told = [];
    const strength = function (m) {
      let before = m.onEquipItemAttempt;
      if (typeof before === 'function' && Object.prototype.hasOwnProperty.call(before, '__thornswoodStrengthHeld')) { before = before.__thornswoodStrengthHeld; }
      if (typeof before !== 'function') { before = null; }
      const gate = function (a, b) { if (before && before(a, b) === false) { return false; } if (b === WEAK) { told.push(a); return false; } return true; };
      gate.__thornswoodStrengthHeld = before; m.onEquipItemAttempt = gate;
    };
    if (order === 'cuffs then strength') { q.load(); strength(q.mp); } else { strength(q.mp); q.load(); }
    const Q = q.g.__thornswoodCuffs;
    q.g.__thornswoodPassHeld = function (pid) { return pid === 91; };
    const wg = q.person(0xff000081, 91, 'whiterunCell:T.esm'), wp = q.person(0xff000082, 92, 'whiterunCell:T.esm');
    q.guards[91] = ['whiterun']; q.addItem(wg, C_, 1); q.face(wg, wp);
    yes(order + ', waiting: the pair is not refused and cuffs nobody', q.mp.onEquipItemAttempt(wg, CUFFS) !== false && !Q.cuffedBy(wp) && q.said.length === 0);
    yes(order + ', waiting: a sword is not refused', q.mp.onEquipItemAttempt(wg, 0x12eb7) !== false);
    yes(order + ', waiting: only the strength gate\'s own refusal stands, once', q.mp.onEquipItemAttempt(wg, WEAK) === false && told.length === 1 && q.said.length === 0);
  }

  // Issue once a day.
  const G3 = r.person(0xff000006, 16, 'whiterunCell:T.esm'); r.guards[16] = ['whiterun'];
  C.issue(G3); r.people[G3].inv = {};
  yes('a guard whose pair went away is not issued another the same day', C.issue(G3) === false);
  r.clock.now += C.ISSUE_EVERY_MS + 1000;
  yes('...and is the next day', C.issue(G3) === true && r.count(G3, CUFFS) === 1);
  yes('...and is told how to use it, without E or a command', /put the cuffs on from your pack/.test(r.last(G3)) && !/press E/.test(r.last(G3)));

  // The client scripts.
  function sp(log) {
    const pc = {
      drawn: true, equipped: false, count: 1,
      isWeaponDrawn: function () { return this.drawn; }, sheatheWeapon: function () { this.drawn = false; log.push('sheathe'); },
      getItemCount: function () { return this.count; }, isEquipped: function () { return this.equipped; },
      equipItem: function (f, prevent) { this.equipped = true; log.push('equip ' + (prevent ? 'locked' : 'loose')); },
      unequipItem: function () { this.equipped = false; log.push('unequip'); }
    };
    return {
      pc: pc,
      sp: {
        storage: {},
        Game: {
          fighting: true,
          isFightingControlsEnabled: function () { return this.fighting; },
          getPlayer: function () { return pc; }, getFormEx: function (id) { return id === CUFFS ? { id: id } : null; },
          disablePlayerControls: function (m, f) { if (f) { this.fighting = false; } log.push('controls off move=' + m + ' fight=' + f); },
          enablePlayerControls: function (m, f) { if (f) { this.fighting = true; } log.push('controls on move=' + m + ' fight=' + f); }
        },
        Debug: { sendAnimationEvent: function (a, ev) { log.push('anim ' + ev); } },
        Actor: { from: function (x) { return x; } }
      }
    };
  }
  let own = null, near = null;
  try { own = new Function('ctx', C.ownerScript()); near = new Function('ctx', C.neighborScript()); } catch (e) { console.log(e.message); }
  yes('both client scripts parse', !!own && !!near);
  if (own && near) {
    const log = [], s = sp(log), st = {};
    const bound = { bound: true, hold: 'whiterun', at: 5, item: CUFFS };
    own({ value: bound, state: st, sp: s.sp });
    yes('their game: fighting off, walking left on', log.indexOf('controls off move=false fight=true') !== -1);
    yes('...the drawn weapon put away', log.indexOf('sheathe') !== -1);
    yes('...the cuffs equipped so they cannot be taken off', log.indexOf('equip locked') !== -1);
    yes('...and the bound hands idle played', log.indexOf('anim OffsetBoundStandingStart') !== -1);
    yes('...and fighting is named as held off by the server, for the front plugin\'s watchdog (#2620)',
      !!s.sp.storage.thornswoodControlsHeld && s.sp.storage.thornswoodControlsHeld.fighting === 'cuffed');
    log.length = 0;
    own({ value: bound, state: st, sp: s.sp });
    yes('the next frame with nothing new does nothing', log.length === 0);
    s.pc.equipped = false; s.pc.drawn = true;
    own({ value: bound, state: st, sp: s.sp });
    yes('cuffs that came off, or a weapon drawn, are put right while bound', log.indexOf('equip locked') !== -1 && log.indexOf('sheathe') !== -1);
    log.length = 0; s.sp.Game.fighting = true; delete s.sp.storage.thornswoodControlsHeld;
    own({ value: bound, state: st, sp: s.sp });
    yes('fighting switched back on by anything else is switched off again, and named held again',
      log.indexOf('controls off move=false fight=true') !== -1 && s.sp.storage.thornswoodControlsHeld.fighting === 'cuffed');
    log.length = 0;
    own({ value: { bound: false, hold: 'whiterun', at: 6, item: CUFFS }, state: st, sp: s.sp });
    yes('freed: cuffs off, idle ended, fighting back', log.indexOf('unequip') !== -1 && log.indexOf('anim OffsetStop') !== -1 &&
      log.indexOf('controls on move=false fight=true') !== -1);
    yes('...and fighting no longer named held', !s.sp.storage.thornswoodControlsHeld.fighting);
    let use = null;
    try { use = new Function('ctx', C.useScript()); } catch (e) { console.log(e.message); }
    const log4 = [], s4 = sp(log4), ust = {};
    s4.pc.equipped = true;
    if (use) { use({ value: { at: 7, item: CUFFS }, state: ust, sp: s4.sp }); }
    yes('the wearer\'s game takes back off a pair that was used on somebody', !!use && log4.indexOf('unequip') !== -1);
    log4.length = 0; s4.pc.equipped = true;
    use({ value: { at: 7, item: CUFFS }, state: ust, sp: s4.sp });
    yes('...once: the same use again leaves what they wear alone', log4.length === 0);
    const log2 = [], s2 = sp(log2);
    own({ value: { bound: false, at: 9, item: CUFFS }, state: {}, sp: s2.sp });
    yes('a free record in a new session touches nothing', log2.length === 0);
    const log3 = [], s3 = sp(log3), nst = {};
    near({ value: bound, state: nst, sp: s3.sp, refr: {} });
    yes('everybody else\'s game plays the bound idle on the prisoner', log3.indexOf('anim OffsetBoundStandingStart') !== -1);
    log3.length = 0;
    near({ value: { bound: false, at: 6 }, state: nst, sp: s3.sp, refr: {} });
    yes('...and ends it when they are freed', log3.indexOf('anim OffsetStop') !== -1);
  }
}

// The wiring.
function handler(name) {
  const i = gm.indexOf('mp.' + name + ' = guard(');
  return i < 0 ? '' : gm.slice(i, gm.indexOf('\n});', i));
}
const act = handler('onActivate');
yes('E on a person is not cuffing any more: mp.onActivate does not ask the cuffs (#1595 hands a letter over on E)',
  act !== '' && act.indexOf('__thornswoodCuffs') === -1);
yes('mp.onUpdateEquipmentAttempt hands the stored equipment to the cuffs, after the college',
  /cuffsEq && cuffsEq\.equipped\) \{ cuffsEq\.equipped\(actorId, equipment\); \}/.test(handler('onUpdateEquipmentAttempt')) &&
  handler('onUpdateEquipmentAttempt').indexOf('college.equipped') < handler('onUpdateEquipmentAttempt').indexOf('cuffsEq.equipped'));
yes('the cuffs answer onEquipItemAttempt and ask any handler already there, never replacing it',
  !!block && /var equipBefore = mp\.onEquipItemAttempt;/.test(block) &&
  /var before = equipBefore \? equipBefore\(actorId, baseId\) : undefined;\s*if \(before === false\) \{ return false; \}/.test(block) &&
  /mp\.onEquipItemAttempt = cuffsGate;/.test(block));
yes('mp.onDropItem refuses the pair on a prisoner\'s wrists', /cuffsDrop && !cuffsDrop\.mayLetGo\(actorId, baseId, count\)\) \{ return false; \}/.test(handler('onDropItem')));
yes('mp.onPutItem does too', /cuffsPut && !cuffsPut\.mayLetGo\(actorId, baseId, count\)\) \{ return false; \}/.test(handler('onPutItem')));

// The front plugin's two rescues and what the server holds off (#2620).
const front = fs.readFileSync(path.join(ROOT, 'game', 'plugins', 'thornswood-front.js'), 'utf8').split(String.fromCharCode(13)).join('');
function frontSlice(a, b) { const i = front.indexOf(a); const j = i < 0 ? -1 : front.indexOf(b, i); return (i >= 0 && j >= 0) ? front.slice(i, j + b.length) : null; }
const helpers = frontSlice('  function heldOff() {', '      on(\'sneaking\'), on(\'menus\'), on(\'activate\'), on(\'journal\'), true);\n  }');
yes('the front plugin reads what the server holds off', !!helpers);
if (helpers) {
  const calls = [];
  const fsp = { storage: {}, Game: { enablePlayerControls: function () { calls.push([].slice.call(arguments)); } } };
  const H = new Function('sp', helpers + '\nreturn { heldOff: heldOff, enableAllBut: enableAllBut };')(fsp);
  yes('nothing held: nothing named', H.heldOff().length === 0);
  fsp.storage.thornswoodControlsHeld = { fighting: 'cuffed' };
  yes('cuffed: fighting is named', H.heldOff().join() === 'fighting');
  H.enableAllBut(H.heldOff());
  yes('...and switching controls on leaves fighting off and turns the rest on, nine arguments',
    calls.length === 1 && calls[0].length === 9 && calls[0][1] === false && calls[0][0] === true && calls[0][7] === true);
}
const tickSrc = frontSlice('  function controlsTick() {', '\n  }\n');
yes('the controls watchdog does not count a held control as off, and switches on all but the held ones',
  !!tickSrc && /readControls\(\)\.filter\(\(name\) => held\.indexOf\(name\) === -1\)/.test(tickSrc) && /enableAllBut\(held\)/.test(tickSrc) &&
  !/enablePlayerControls\(true, true/.test(tickSrc));
yes('no rescue anywhere in the front plugin switches every control on regardless',
  !/enablePlayerControls\(true, true, true, true, true, true, true, true, true\)/.test(front) &&
  (front.match(/enableAllBut\(heldOff\(\)\)/g) || []).length === 1);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
