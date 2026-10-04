// test-clothes-remount-cost.js
//
// The clothes remount watcher stops calling into the game on every frame.
// Issue #963: less lag with the NPCs on.
//
// MEASURED 28 September on the dev front log: "clothes remount" was the
// costliest handler in the frame, 599 ms in 30 s over 1274 frames, because it
// read the character, its race and the race's name every frame for everybody,
// goblin or not. It now looks four times a second.
//
// This lifts the real watcher out of the plugin (raceNeedsClothesRemount
// through clothesRemountTick) and runs it on a fake clock and a fake game. It
// counts the calls into the game over a second at sixty frames, and checks
// that a goblin walking into a new cell is still remounted, and only once.
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
yes('the plugin still has its clothes remount watcher', a >= 0 && b > a);

function world(raceName) {
  const clock = { now: 1700000000000 };
  let calls = 0;
  const state = { cell: 0x1000, remounts: 0, on: true };
  const race = { getName: function () { calls++; return raceName; } };
  const shirt = { id: 1 };
  const pc = {
    getRace: function () { calls++; return race; },
    getParentCell: function () { calls++; return { getFormID: function () { calls++; return state.cell; } }; },
    getNumItems: function () { return 1; },
    getNthForm: function () { return shirt; },
    // Worn until the remount takes it off, and on again once it is put back
    // (#1560: the remount now looks at both before it is done).
    isEquipped: function () { return state.on; },
    getItemCount: function () { return 1; },
    unequipItem: function () { state.on = false; },
    equipItem: function () { state.on = true; state.remounts++; },
    queueNiNodeUpdate: function () { }
  };
  const waits = [];
  const sp = {
    Game: { getPlayer: function () { calls++; return pc; } },
    Actor: { from: function (x) { calls++; return x; } },
    Armor: { from: function (f) { return f; } },
    Utility: { wait: function () { return { then: function (fn) { waits.push(fn); } }; } }
  };
  function guard(name, fn) { return fn; }
  function log() { }
  const FakeDate = { now: function () { return clock.now; } };
  const tick = new Function('sp', 'guard', 'log', 'Date', src.slice(a, b) + '\nreturn clothesRemountTick;')(sp, guard, log, FakeDate);
  return {
    clock: clock, state: state, tick: tick,
    calls: function () { return calls; }, reset: function () { calls = 0; },
    settle: function () { while (waits.length) { waits.shift()(); } }
  };
}

if (a >= 0 && b > a) {
  // A person of an ordinary race, one second at sixty frames.
  const w = world('Nord');
  w.reset();
  for (let i = 0; i < 60; i++) { w.clock.now += 16; w.tick(); }
  yes('a second of frames calls into the game about four times over, not sixty (' + w.calls() + ' calls)',
      w.calls() <= 5 * 4);

  // A goblin changing cell is still remounted, once.
  const g = world('Goblin');
  for (let i = 0; i < 30; i++) { g.clock.now += 16; g.tick(); }   // first cell seen
  g.state.cell = 0x2000;                                            // walks through a door
  for (let i = 0; i < 30; i++) { g.clock.now += 16; g.tick(); }   // half a second
  g.settle();
  yes('a goblin who walks into a new cell has their clothes remounted within half a second',
      g.state.remounts === 1);
  for (let i = 0; i < 120; i++) { g.clock.now += 16; g.tick(); }
  g.settle();
  yes('and only once while they stay there', g.state.remounts === 1);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
