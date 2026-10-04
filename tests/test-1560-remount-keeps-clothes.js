// test-1560-remount-keeps-clothes.js
//
// The Riekling and Goblin clothes remount never leaves somebody undressed
// (#1560). Patrick, 4 October, on a Riekling on dev: out of creation with no
// clothes on, and "I just walked out a door and it unequipped my clothes".
// The dev client log had "remounted 2 worn armour for spawn+2500" a second
// after the race menu closed and "remounted 2 worn armour for cell" after the
// Bannered Mare door, and nothing worn after either one.
//
// The remount took a piece off and put it back on inside one call. This lifts
// the real remount out of the front plugin (raceNeedsClothesRemount through
// clothesRemountTick) and runs it against fake games on a fake clock:
//
//   - one where an unequip lands at the start of the next frame and an equip
//     of a piece that still reads as worn does nothing, which is what the log
//     looks like. The remount before this fix fails here.
//   - one where both land at once.
//   - one that drops the first two equips it is asked for.
//
// and checks that the clothes are back on afterwards, that nothing is put on
// in the frame it was taken off, that a piece gone from the pack is not put
// on, that a second remount waits for the first, that a piece taken off by
// hand after it was seen back on stays off, that a game that cannot wait is
// left dressed, and that an ordinary race is never touched.
//
//   node tests/test-1560-remount-keeps-clothes.js
//   FRONT=<another copy of thornswood-front.js> node tests/test-1560-remount-keeps-clothes.js
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const SRC = process.env.FRONT || path.join(__dirname, '..', 'game', 'plugins', 'thornswood-front.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const a = src.indexOf('  function raceNeedsClothesRemount(ac) {');
const b = a < 0 ? -1 : src.indexOf('  function scheduleSpawnClothesRemount() {', a);
yes('the plugin still has its clothes remount', a >= 0 && b > a);
if (!(a >= 0 && b > a)) {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(1);
}

const FRAME_MS = 16;

/*
  A fake game. opts:
    race            the race's name
    deferUnequip    an unequip lands at the start of the next frame
    noopWhileOn     an equip of a piece that reads as worn does nothing
    dropEquips      this many equips are taken and then ignored
    noWait          Utility.wait throws
*/
function game(opts) {
  const clock = { now: 1700000000000 };
  const st = {
    frame: 0,
    on: {}, pack: {}, pendingOff: [],
    calls: [],        // [kind, frame, id]
    lines: [],
    drops: opts.dropEquips || 0
  };
  const forms = [];
  function piece(id) {
    const f = { id: id, getFormID: function () { return id; } };
    forms.push(f);
    st.on[id] = true;
    st.pack[id] = 1;
    return f;
  }
  const tunic = piece(0x1be1a);
  const boots = piece(0x1be1b);
  const race = { getName: function () { return opts.race || 'Riekling Blue'; } };
  const cell = { id: 0x2d19bad4 };
  const pc = {
    getRace: function () { return race; },
    getParentCell: function () { return { getFormID: function () { return cell.id; } }; },
    getNumItems: function () { return forms.length; },
    getNthForm: function (i) { return forms[i]; },
    getItemCount: function (f) { return st.pack[f.id] || 0; },
    isEquipped: function (f) { return !!st.on[f.id]; },
    unequipItem: function (f) {
      st.calls.push(['off', st.frame, f.id]);
      if (!st.on[f.id]) { return; }
      if (opts.deferUnequip) { st.pendingOff.push(f.id); } else { st.on[f.id] = false; }
    },
    equipItem: function (f) {
      st.calls.push(['on', st.frame, f.id]);
      if (!(st.pack[f.id] > 0)) { return; }
      if (st.on[f.id] && opts.noopWhileOn) { return; }
      if (st.drops > 0) { st.drops--; return; }
      st.on[f.id] = true;
      // An equip of a piece whose unequip has not landed cancels nothing
      // in this fake; the unequip still lands.
    },
    queueNiNodeUpdate: function () { st.calls.push(['ninode', st.frame, 0]); }
  };
  const timers = [];
  const sp = {
    Game: { getPlayer: function () { return pc; } },
    Actor: { from: function (x) { return x; } },
    Armor: { from: function (f) { return f; } },
    Utility: {
      wait: function (s) {
        if (opts.noWait) { throw new Error('no virtual machine here'); }
        return { then: function (fn) { timers.push({ at: clock.now + s * 1000, fn: fn }); } };
      }
    }
  };
  function guard(name, fn) {
    return function () {
      try { return fn.apply(null, arguments); }
      catch (e) { st.lines.push(name + ' threw: ' + e); return undefined; }
    };
  }
  function log() { st.lines.push(Array.prototype.slice.call(arguments).join(' ')); }
  const FakeDate = { now: function () { return clock.now; } };
  const lifted = new Function('sp', 'guard', 'log', 'Date',
    src.slice(a, b) + '\nreturn { remount: remountWornClothes, tick: clothesRemountTick };')(sp, guard, log, FakeDate);

  // One frame: the engine lands what it deferred, then due timers fire.
  function frame() {
    st.frame++;
    clock.now += FRAME_MS;
    const off = st.pendingOff;
    st.pendingOff = [];
    for (const id of off) { st.on[id] = false; }
    const due = timers.filter(function (t) { return t.at <= clock.now; });
    for (const t of due) { timers.splice(timers.indexOf(t), 1); }
    for (const t of due) { t.fn(); }
    lifted.tick();
  }
  function run(seconds) {
    const n = Math.ceil(seconds * 1000 / FRAME_MS);
    for (let i = 0; i < n; i++) { frame(); }
  }
  return {
    st: st, tunic: tunic, boots: boots, cell: cell, run: run, frame: frame,
    remount: lifted.remount,
    bothOn: function () { return !!st.on[tunic.id] && !!st.on[boots.id]; },
    sameFrame: function () {
      // A piece put on in the frame it was taken off.
      const offAt = {};
      for (const c of st.calls) {
        if (c[0] === 'off') { offAt[c[2]] = c[1]; }
        if (c[0] === 'on' && offAt[c[2]] === c[1]) { return true; }
      }
      return false;
    },
    count: function (kind, id) {
      return st.calls.filter(function (c) { return c[0] === kind && (id === undefined || c[2] === id); }).length;
    }
  };
}

// 1. What the log looks like: the unequip lands a frame later and an equip
//    of a piece still reading as worn does nothing.
{
  const g = game({ deferUnequip: true, noopWhileOn: true });
  g.frame();
  g.remount('cell');
  g.run(6);
  yes('an unequip that lands a frame later leaves the clothes on, not off', g.bothOn());
  yes('and nothing is put on in the frame it was taken off', !g.sameFrame());
}

// 2. Both land at once.
{
  const g = game({});
  g.frame();
  g.remount('cell');
  g.run(6);
  yes('an unequip and an equip that land at once leave the clothes on', g.bothOn());
  yes('each piece comes off once', g.count('off', g.tunic.id) === 1 && g.count('off', g.boots.id) === 1);
  yes('and goes back on once', g.count('on', g.tunic.id) === 1 && g.count('on', g.boots.id) === 1);
  yes('in a later frame than it came off', !g.sameFrame());
  yes('the body is rebuilt after', g.count('ninode') >= 1);
}

// 3. The first two equips are dropped.
{
  const g = game({ dropEquips: 2 });
  g.frame();
  g.remount('cell');
  g.run(6);
  yes('equips that are dropped are asked again until the clothes are on', g.bothOn());
  yes('and the log says it was asked more than once',
      g.st.lines.some(function (l) { return /remounted 2 worn armour for cell/.test(l) && /[3-9] ask/.test(l); }));
}

// 4. A piece leaves the pack while it is off.
{
  const g = game({ deferUnequip: true });
  g.frame();
  g.remount('cell');
  g.st.pack[g.boots.id] = 0;      // dropped or sold in the same breath
  const onBefore = g.count('on', g.boots.id);
  g.run(6);
  yes('a piece gone from the pack is not put back on', g.count('on', g.boots.id) === onBefore);
  yes('and the rest still is', !!g.st.on[g.tunic.id]);
}

// 5. A second remount while the first is running waits for it.
{
  const g = game({ deferUnequip: true, noopWhileOn: true });
  g.frame();
  g.remount('spawn+2500');
  g.frame();
  g.remount('cell');
  g.run(10);
  yes('two remounts asked together both finish with the clothes on', g.bothOn());
  yes('and never take a piece off while it is waiting to go back on', !g.sameFrame());
  const offs = g.st.calls.filter(function (c) { return c[0] === 'off' && c[2] === g.tunic.id; });
  const ons = g.st.calls.filter(function (c) { return c[0] === 'on' && c[2] === g.tunic.id; });
  yes('the second runs after the first is back on',
      offs.length === 2 && ons.length >= 1 && offs[1][1] > ons[0][1]);
}

// 6. Taken off by hand after it was seen back on.
{
  const g = game({});
  g.frame();
  g.remount('cell');
  let n = 0;
  const said = function () { return g.st.lines.some(function (l) { return /^remounted 2 worn armour for cell/.test(l); }); };
  while (!said()) { g.frame(); if (++n > 600) { break; } }
  g.st.on[g.boots.id] = false;    // the person takes their boots off
  const before = g.count('on', g.boots.id);
  g.run(6);
  yes('boots taken off by hand after the remount stay off', !g.st.on[g.boots.id] && g.count('on', g.boots.id) === before);
}

// 7. A game that cannot wait right now.
{
  const g = game({ noWait: true });
  g.frame();
  const took = g.remount('cell-now');
  yes('a game that cannot wait is left dressed', took === 0 && g.count('off') === 0 && g.bothOn());
}

// 8. An ordinary race.
{
  const g = game({ race: 'Nord' });
  g.frame();
  g.remount('cell');
  g.run(2);
  yes('an ordinary race is never touched', g.count('off') === 0 && g.count('on') === 0);
}

// 9. Walking through a door: the cell watcher starts it and it ends dressed.
{
  const g = game({ deferUnequip: true, noopWhileOn: true });
  g.run(1);                       // first cell seen
  g.cell.id = 0x1605e;            // through the door
  g.run(6);
  yes('a Riekling through a door comes out dressed', g.bothOn() && g.count('off') === 2);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
