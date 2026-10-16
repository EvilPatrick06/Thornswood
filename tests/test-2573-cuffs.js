// test-2573-cuffs.js
//
//     node tests/test-2573-cuffs.js
//
// #2573, Patrick 16 Oct 2026: A and B. A guard of a hold who carries
// Prisoner's Cuffs presses E on a person: they are bound (cuffs on, hands
// bound, no weapon or spell) until a guard of that hold presses E on them
// again; only guards put the cuffs on anybody. In the world only, no command.
//
// Root cause and design: issue #2573, issuecomment-6226678131. Nothing in the
// gamemode answered a press on a person, and nothing handed out or used the
// cuffs.
//
// Runs the REAL cuffs block over a stand-in mp, packs, offices and places;
// runs its two client scripts over a stand-in Skyrim Platform; and reads the
// REAL mp.onActivate, mp.onDropItem and mp.onPutItem wiring. Read only.
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

function rig() {
  const clock = { now: Date.UTC(2026, 9, 16, 18, 0, 0) };
  const props = {}, said = [], made = {}, timers = [];
  const people = {};   // actorId -> { pid, place, inv: {baseId: n} }
  const guards = {};   // pid -> [holds]
  function person(id, pid, place) { people[id] = { pid: pid, place: place, inv: {} }; props[id] = {}; return id; }
  const mp = {
    makeProperty: function (k, o) { made[k] = o; },
    getOnlinePlayers: function () { return Object.keys(people).map(Number); },
    get: function (id, key) {
      const p = people[id];
      if (!p) { throw new Error('no such form'); }
      if (key === 'profileId') { return p.pid; }
      if (key === 'locationalData') { return p.place ? { cellOrWorldDesc: p.place, pos: [0, 0, 0] } : null; }
      if (key === 'inventory') { return { entries: Object.keys(p.inv).map(function (b) { return { baseId: Number(b), count: p.inv[b] }; }) }; }
      return props[id][key];
    },
    set: function (id, key, v) { props[id][key] = JSON.parse(JSON.stringify(v)); }
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
  const C = new Function('globalThis', 'mp', 'Date', 'setInterval', 'clearInterval', 'guard', 'notify', 'say', 'log',
    'idOf', 'addItem', 'takeItemById', 'holdAt', block + '\nreturn globalThis.__thornswoodCuffs;')(
    g, mp, { now: function () { return clock.now; } }, function (f, ms) { timers.push(ms); return 1; }, function () { },
    function (n, f) { return f; }, function () { }, function (id, line) { said.push([id, line]); }, function () { },
    idOf, addItem, takeItemById, holdAt);
  return { C: C, g: g, clock: clock, said: said, made: made, timers: timers, people: people, guards: guards,
           person: person, count: count, addItem: addItem, props: props,
           last: function (id) { for (let i = said.length - 1; i >= 0; i--) { if (said[i][0] === id) { return said[i][1]; } } return ''; } };
}

let r = null;
try { r = block ? rig() : null; } catch (e) { console.log('rig threw: ' + e.message); }
const C = r && r.C;
yes('the block loads and answers presses', !!C && typeof C.activated === 'function' && typeof C.mayLetGo === 'function');

if (C) {
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

  // Presses that are not about cuffs.
  yes('a press by somebody with no cuffs is left alone', C.activated(P, X) === false && r.last(X) === '');
  yes('a press on an NPC is left alone', C.activated(N, G) === false && r.count(G, CUFFS) === 1);
  yes('a press on yourself is left alone', C.activated(G, G) === false);

  // B: only guards put cuffs on somebody.
  r.addItem(X, '10e039:Skyrim.esm', 1);
  yes('somebody who is not a guard, carrying cuffs, cannot cuff anybody (B)',
    C.activated(P, X) === true && !C.cuffedBy(P) && r.count(X, CUFFS) === 1 && /Only a hold's guards/.test(r.last(X)));
  yes('a guard of another hold cannot cuff here',
    C.activated(P, R) === true && !C.cuffedBy(P) && r.count(R, CUFFS) === 1 && /Riften/.test(r.last(R)) && /Whiterun/.test(r.last(R)));

  // A: cuffing.
  yes('a guard of the hold, carrying cuffs, cuffs somebody', C.activated(P, G) === true && !!C.cuffedBy(P));
  const rec = r.props[P][PROP];
  yes('...in that hold\'s name, by that guard, with the cuffs\' id for their game',
    rec.bound === true && rec.hold === 'whiterun' && rec.by === 11 && rec.item === CUFFS && rec.at > 0);
  yes('...and the pair moves from the guard\'s pack to theirs', r.count(G, CUFFS) === 0 && r.count(P, CUFFS) === 1);
  yes('...and both are told', /in the name of Whiterun/.test(r.last(G)) && /puts you in cuffs/.test(r.last(P)));

  // Bound: the pair stays on.
  yes('a bound person cannot drop the cuffs', C.mayLetGo(P, CUFFS, 1) === false && /locked on your wrists/.test(r.last(P)));
  yes('...or anything else of theirs is still theirs to drop', C.mayLetGo(P, 0xf, 5) === true);
  yes('somebody free drops cuffs as they like', C.mayLetGo(X, CUFFS, 1) === true);
  yes('a bound guard is issued nothing', (r.guards[12] = ['whiterun'], C.issue(P) === false));
  delete r.guards[12];

  // Freeing.
  r.addItem(X, '10e039:Skyrim.esm', 1);
  yes('nobody but a guard of that hold frees them', C.activated(P, X) === true && !!C.cuffedBy(P) && /only a guard of Whiterun/.test(r.last(X)));
  yes('...not a guard of another hold either', C.activated(P, R) === true && !!C.cuffedBy(P));
  const G2 = r.person(0xff000005, 15, 'riftenCell:T.esm'); r.guards[15] = ['whiterun'];
  yes('any guard of that hold frees them, wherever that guard stands', C.activated(P, G2) === true && !C.cuffedBy(P));
  yes('...and the pair goes into that guard\'s pack', r.count(P, CUFFS) === 0 && r.count(G2, CUFFS) === 1);
  const freed = r.props[P][PROP];
  yes('...and the record says free, with a new stamp for their game', freed.bound === false && freed.at > rec.at);
  yes('freed, they drop cuffs as they like again', C.mayLetGo(P, CUFFS, 1) === true);

  // Place rules.
  r.people[P].place = 'riftenCell:T.esm';
  yes('a Whiterun guard cannot cuff in Riften', C.activated(P, G2) === true && !C.cuffedBy(P));
  r.people[P].place = 'nowhere:T.esm';
  yes('where the data gives no hold, a guard of one hold cuffs in its name', C.activated(P, G2) === true && C.cuffedBy(P).hold === 'whiterun');
  C.activated(P, G2);
  r.guards[15] = ['whiterun', 'riften'];
  yes('...but not a guard of two, who would not know whose cuffs these are', C.activated(P, G2) === true && !C.cuffedBy(P));

  // Issue once a day.
  const G3 = r.person(0xff000006, 16, 'whiterunCell:T.esm'); r.guards[16] = ['whiterun'];
  C.issue(G3); r.people[G3].inv = {};
  yes('a guard whose pair went away is not issued another the same day', C.issue(G3) === false);
  r.clock.now += C.ISSUE_EVERY_MS + 1000;
  yes('...and is the next day', C.issue(G3) === true && r.count(G3, CUFFS) === 1);

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
        Game: {
          getPlayer: function () { return pc; }, getFormEx: function (id) { return id === CUFFS ? { id: id } : null; },
          disablePlayerControls: function (m, f) { log.push('controls off move=' + m + ' fight=' + f); },
          enablePlayerControls: function (m, f) { log.push('controls on move=' + m + ' fight=' + f); }
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
    log.length = 0;
    own({ value: bound, state: st, sp: s.sp });
    yes('the next frame with nothing new does nothing', log.length === 0);
    s.pc.equipped = false; s.pc.drawn = true;
    own({ value: bound, state: st, sp: s.sp });
    yes('cuffs that came off, or a weapon drawn, are put right while bound', log.indexOf('equip locked') !== -1 && log.indexOf('sheathe') !== -1);
    log.length = 0;
    own({ value: { bound: false, hold: 'whiterun', at: 6, item: CUFFS }, state: st, sp: s.sp });
    yes('freed: cuffs off, idle ended, fighting back', log.indexOf('unequip') !== -1 && log.indexOf('anim OffsetStop') !== -1 &&
      log.indexOf('controls on move=false fight=true') !== -1);
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
yes('mp.onActivate asks the cuffs first and ends the press when they answer it',
  /__thornswoodCuffs;\s*\n\s*if \(cuffs && cuffs\.activated\(refrId, casterRefrId\)\) \{ return false; \}/.test(act) &&
  act.indexOf('__thornswoodCuffs') < act.indexOf('benchGate('));
yes('mp.onDropItem refuses the pair on a prisoner\'s wrists', /cuffsDrop && !cuffsDrop\.mayLetGo\(actorId, baseId, count\)\) \{ return false; \}/.test(handler('onDropItem')));
yes('mp.onPutItem does too', /cuffsPut && !cuffsPut\.mayLetGo\(actorId, baseId, count\)\) \{ return false; \}/.test(handler('onPutItem')));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
