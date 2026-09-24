// test-audit-handlers.js
//
// What a client can ask the server, written down, and the two handlers that
// watch a take and a drop without ever refusing one.
//
// The To Do List entry "The gamemode registers four event handlers, so nothing
// server-side watches for griefing": "Establish what the client is allowed to
// ask the server to do and block the rest at the handler level, then log what
// was allowed." Which take to refuse is Patrick's decision and it has not been
// made. This checks the list and the log, which is the half that can be done
// without him.
//
// WHAT MATTERS MOST IS THAT THEY ANSWER NOTHING. ScampServerListener reads
// undefined as "let it through" and false as "refuse", so a watcher that
// answered false on any path would shut chests for everybody at once. Every
// case below checks the answer is exactly undefined, including the ones where
// every read the handler makes throws, and checks nothing was written.
//
// It drives the REAL guard() and the REAL watchers out of gamemode.js over a
// fake mp, the way test-coffers.js drives putIn. Where the fork is on this
// machine it also checks the list against the fork itself; on a machine
// without it those checks say SKIP.
//
// Read only.
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(__dirname, 'gamemode.js');
const FORK = process.env.SKYMP || 'C:/Thornswood-Dev/skymp';
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function skip(what) { console.log('SKIP  ' + what); }

function lift(from, to) {
  const a = src.indexOf(from);
  if (a < 0) { return null; }
  const b = src.indexOf(to, a);
  return b < 0 ? null : src.slice(a, b + to.length);
}

// From `from`, past `anchor`, to the first `to` after the anchor.
function liftThrough(from, anchor, to) {
  const a = src.indexOf(from);
  if (a < 0) { return null; }
  const b = src.indexOf(anchor, a);
  if (b < 0) { return null; }
  const c = src.indexOf(to, b);
  return c < 0 ? null : src.slice(a, c + to.length);
}

// Every event the fork raises, read out of
// skymp5-server/cpp/server_guest_lib/gamemode_events on 24 September.
const EVENTS = ['onActivate', 'onCraft', 'onDeath', 'onDropItem', 'onEatItem',
                'onPutItem', 'onReadBook', 'onRespawn', 'onTakeItem',
                'onUpdateAppearanceAttempt', 'onUpdateEquipmentAttempt'];
// The console commands the client forwards, consoleCommandsService.ts.
const CONSOLE = ['additem', 'equipitem', 'placeatme', 'disable', 'mp'];

const guardSrc = lift('function guard(name, fn) {', '\n}\n');
const auditSrc = liftThrough('function auditProfile(refrId) {', 'mp.onDropItem = guard(', '\n});');
const handlersSrc = liftThrough('mp.onTakeItem = guard(', 'mp.onDropItem = guard(', '\n});');
const listSrc = lift('  WHAT A CLIENT CAN ASK THIS SERVER, AND WHAT IT IS TOLD.', '*/');

yes('guard() is in the gamemode', guardSrc !== null);
yes('the take and drop watchers are in the gamemode', auditSrc !== null && handlersSrc !== null);
yes('and so is the list of what a client can ask', listSrc !== null);

// ------------------------------------------------------------ the handlers --

// Every handler this file registers, by the line that registers it.
const registered = [];
src.split('\n').forEach(function (line) {
  const m = /^mp\.(on[A-Za-z]+)\s*=\s*(.*)$/.exec(line);
  if (m) { registered.push({ name: m[1], rest: m[2] }); }
});

yes('more than the four handlers the entry counted, ' + registered.length + ' of them',
    registered.length > 4);
yes('every one of them is built with guard() under its own name',
    registered.length > 0 && registered.every(function (h) {
      return h.rest.indexOf("guard('" + h.name + "', function") === 0;
    }));
yes('every one is an event the fork actually raises, so none of them is a handler that never fires',
    registered.every(function (h) { return EVENTS.indexOf(h.name) !== -1; }));
yes('onTakeItem is registered', registered.some(function (h) { return h.name === 'onTakeItem'; }));
yes('onDropItem is registered', registered.some(function (h) { return h.name === 'onDropItem'; }));
yes('and each event is registered once, so a later line cannot quietly replace an earlier one',
    registered.every(function (h, i) {
      return registered.findIndex(function (o) { return o.name === h.name; }) === i;
    }));

if (handlersSrc !== null) {
  // Not a single return in either watcher. A return with nothing after it
  // would be harmless today and is the line somebody turns into a refusal.
  yes('neither watcher has a return statement in it', !/\breturn\b/.test(handlersSrc));
}

// ---------------------------------------------------------------- the list --

if (listSrc !== null) {
  yes('the list names all eleven events',
      EVENTS.every(function (e) { return listSrc.indexOf(e) !== -1; }));
  yes('the list names all five console commands',
      CONSOLE.every(function (c) { return new RegExp('\\b' + c + '\\b').test(listSrc); }));
  yes('the list says where item creation is refused', /EnsureAdmin/.test(listSrc));
  yes('the list says which decision is still Patrick\'s', /decision Patrick has not made/.test(listSrc));
}

// ------------------------------------------------------------- the fork --

function readFork(rel) {
  try { return fs.readFileSync(path.join(FORK, rel), 'utf8'); } catch (e) { return null; }
}

const eventsDir = path.join(FORK, 'skymp5-server', 'cpp', 'server_guest_lib', 'gamemode_events');
let forkEvents = null;
try {
  forkEvents = [];
  fs.readdirSync(eventsDir).forEach(function (f) {
    if (!/\.cpp$/.test(f)) { return; }
    const body = fs.readFileSync(path.join(eventsDir, f), 'utf8');
    const m = /return\s+"(on[A-Za-z]+)"\s*;/.exec(body);
    if (m) { forkEvents.push(m[1]); }
  });
  forkEvents.sort();
} catch (e) {
  forkEvents = null;
}
if (forkEvents === null) {
  skip('the fork is not on this machine, so the event list is not checked against it');
} else {
  yes('the eleven events are exactly the ones the fork raises (' + forkEvents.join(', ') + ')',
      JSON.stringify(forkEvents) === JSON.stringify(EVENTS.slice().sort()));
}

const cmds = readFork('skymp5-client/src/services/services/consoleCommandsService.ts');
if (cmds === null) {
  skip('the fork\'s client is not on this machine, so the console commands are not checked against it');
} else {
  const m = /type\s+CmdName\s*=\s*([^;]+);/.exec(cmds);
  const named = m ? (m[1].match(/"([a-z]+)"/g) || []).map(function (s) { return s.replace(/"/g, ''); }).sort() : [];
  yes('the five console commands are exactly the ones the client forwards (' + named.join(', ') + ')',
      JSON.stringify(named) === JSON.stringify(CONSOLE.slice().sort()));
}

const forms = readFork('skymp5-server/cpp/server_guest_lib/MpChangeForms.h');
if (forms === null) {
  skip('the fork is not on this machine, so the -1 profile id is not checked against it');
} else {
  yes('an actor nobody plays starts at profile id -1 in the fork, which is why a person is above zero',
      /int32_t\s+profileId\s*=\s*-1\s*;/.test(forms));
}

// ----------------------------------------------------------- driving them --

const ALICE = 0xff000058;
const BOB = 0xff000060;
const CHEST = 0x000a1b2c;
const BANDIT = 0x0001a2b3;
const BOX = 0x0000aaaa;
const ORE = 0x00071cf3;
const GOLD = 0x0000000f;
const BREEZEHOME = '165a7:Skyrim.esm';

function world(opts) {
  opts = opts || {};
  const lines = [], errors = [], writes = [];
  const refs = {};
  refs[ALICE] = { profileId: 101, appearance: { name: 'Alice' }, worldOrCellDesc: BREEZEHOME };
  refs[BOB] = { profileId: 202, appearance: { name: 'Bob' }, worldOrCellDesc: BREEZEHOME };
  // What the engine answers for a container: no profile id at all.
  refs[CHEST] = { profileId: undefined, baseDesc: 'd9f2:Skyrim.esm' };
  // And for an NPC: -1, straight out of its change form.
  refs[BANDIT] = { profileId: -1, appearance: null, baseDesc: '1e7d5:Skyrim.esm' };
  refs[BOX] = { profileId: undefined, baseDesc: 'd9f2:Skyrim.esm' };
  const descs = {};
  descs[ORE] = '71cf3:Skyrim.esm';
  descs[GOLD] = 'f:Skyrim.esm';

  const mp = {
    get: function (id, prop) {
      if (opts.everyReadThrows) { throw new Error('no such reference'); }
      if (!Object.prototype.hasOwnProperty.call(refs, id)) { throw new Error('no reference ' + id); }
      return refs[id][prop];
    },
    getDescFromId: function (id) {
      if (opts.everyReadThrows) { throw new Error('no descriptor'); }
      return descs[id] || '';
    },
    set: function () { writes.push(Array.prototype.slice.call(arguments)); }
  };
  const fakeLog = function () {
    if (opts.logThrows) { throw new Error('disk full'); }
    lines.push(Array.prototype.slice.call(arguments).join(' '));
  };
  const fakeConsole = {
    log: function () { },
    error: function (m) { errors.push(String(m)); }
  };
  const g = {};
  if (opts.prop) { g.__thornswoodProperty = opts.prop; }
  const make = new Function('mp', 'log', 'console', 'globalThis',
                            guardSrc + '\n' + auditSrc + '\nreturn mp;');
  make(mp, fakeLog, fakeConsole, g);
  return {
    take: function () { return mp.onTakeItem.apply(null, arguments); },
    drop: function () { return mp.onDropItem.apply(null, arguments); },
    lines: lines, errors: errors, writes: writes
  };
}

const whiterunBox = {
  holdOfBox: function (id) { return id === BOX ? 'whiterun' : null; }
};

if (guardSrc !== null && auditSrc !== null) {
  // T1: an ordinary chest, which is what nearly every take is.
  {
    const w = world({ prop: whiterunBox });
    const out = w.take(CHEST, ALICE, ORE, 3);
    yes('T1 a take from a chest answers exactly undefined, so it goes through', out === undefined);
    yes('T1 and leaves one line', w.lines.length === 1);
    const l = w.lines[0] || '';
    yes('T1 the line starts with take: so it can be found', l.indexOf('take: ') === 0);
    yes('T1 it names the person by profile and character', l.indexOf('profile 101 (Alice, 0xff000058)') !== -1);
    yes('T1 it names the count and the item by its descriptor', l.indexOf('took 3 71cf3:Skyrim.esm') !== -1);
    yes('T1 it names the chest by reference and base', l.indexOf('from 0xa1b2c (d9f2:Skyrim.esm)') !== -1);
    yes('T1 and the cell they were standing in', l.indexOf('in ' + BREEZEHOME) !== -1);
    yes('T1 and nothing was written to anybody', w.writes.length === 0);
    yes('T1 and nothing threw', w.errors.length === 0);
  }

  // T2: another person's body, the take rule 3 and rule 4 are about.
  {
    const w = world({ prop: whiterunBox });
    const out = w.take(BOB, ALICE, GOLD, 40);
    yes('T2 a take from another person\'s body goes through', out === undefined);
    yes('T2 and says whose body it was',
        (w.lines[0] || '').indexOf('from the body of profile 202 (Bob, 0xff000060)') !== -1);
  }

  // T3: an NPC's body. Its profile id is -1, not 0, and a check written as
  //     "is it zero" would call every dead bandit a person.
  {
    const w = world({ prop: whiterunBox });
    const out = w.take(BANDIT, ALICE, GOLD, 12);
    const l = w.lines[0] || '';
    yes('T3 a take from an NPC\'s body goes through', out === undefined);
    yes('T3 and is not called anybody\'s body', l.indexOf('the body of') === -1);
    yes('T3 and never says profile -1', l.indexOf('profile -1') === -1);
    yes('T3 it names the body by reference and base', l.indexOf('from 0x1a2b3 (1e7d5:Skyrim.esm)') !== -1);
  }

  // T4: a hold's box, which is money a steward will ask about.
  {
    const w = world({ prop: whiterunBox });
    const out = w.take(BOX, ALICE, GOLD, 100);
    yes('T4 a take from a hold\'s box goes through', out === undefined);
    yes('T4 and names the hold', (w.lines[0] || '').indexOf('from whiterun\'s box 0xaaaa') !== -1);
  }

  // T5: the property block missing, or throwing, changes nothing but the line.
  {
    const w = world({ prop: { holdOfBox: function () { throw new Error('boxes not loaded'); } } });
    const out = w.take(BOX, ALICE, GOLD, 100);
    yes('T5 a property block that throws still lets the take through', out === undefined);
    yes('T5 and the take is still logged', w.lines.length === 1 && w.errors.length === 0);
    const w2 = world({});
    yes('T5 no property block at all lets it through too', w2.take(CHEST, ALICE, ORE, 1) === undefined);
  }

  // T6: a drop.
  {
    const w = world({ prop: whiterunBox });
    const out = w.drop(ALICE, ORE, 2);
    const l = w.lines[0] || '';
    yes('T6 a drop answers exactly undefined, so it goes through', out === undefined);
    yes('T6 the line starts with drop: so it can be found', l.indexOf('drop: ') === 0);
    yes('T6 it names the person, the count, the item and the cell',
        l.indexOf('profile 101 (Alice, 0xff000058)') !== -1 &&
        l.indexOf('dropped 2 71cf3:Skyrim.esm') !== -1 &&
        l.indexOf('in ' + BREEZEHOME) !== -1);
    yes('T6 and nothing was written to anybody', w.writes.length === 0);
  }

  // T7: every read the server can make throws. The press still goes through
  //     and the line says what it could.
  {
    const w = world({ everyReadThrows: true, prop: whiterunBox });
    const t = w.take(CHEST, ALICE, ORE, 3);
    const d = w.drop(ALICE, ORE, 1);
    yes('T7 with every read throwing, a take still goes through', t === undefined);
    yes('T7 and a drop still goes through', d === undefined);
    yes('T7 and both are still logged, by id', w.lines.length === 2 &&
        w.lines[0].indexOf('0xff000058') !== -1 && w.lines[0].indexOf('0x71cf3') !== -1 &&
        w.lines[1].indexOf('0x71cf3') !== -1);
    yes('T7 and nothing escaped to the engine', w.errors.length === 0);
  }

  // T8: the log itself failing. guard() is what stands between that and the
  //     engine, and it answers undefined.
  {
    const w = world({ logThrows: true, prop: whiterunBox });
    const t = w.take(CHEST, ALICE, ORE, 3);
    const d = w.drop(ALICE, ORE, 1);
    yes('T8 a log that throws still lets a take through', t === undefined);
    yes('T8 and a drop', d === undefined);
    yes('T8 and guard() reports it under the handler\'s name',
        w.errors.length === 2 && w.errors[0].indexOf('onTakeItem threw') !== -1 &&
        w.errors[1].indexOf('onDropItem threw') !== -1);
  }

  // T9: arguments that are not what the engine promises.
  {
    const w = world({ prop: whiterunBox });
    yes('T9 no arguments at all still answers undefined', w.take() === undefined && w.drop() === undefined);
    yes('T9 and a missing count is written as nought rather than NaN',
        w.lines.length === 2 && w.lines[0].indexOf('NaN') === -1 && w.lines[0].indexOf('took 0') !== -1);
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
