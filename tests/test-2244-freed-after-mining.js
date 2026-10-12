'use strict';
/*
  test-2244-freed-after-mining.js

  #2244: after the mining animation the player could not jump, sprint or use a
  forge until they re-equipped the pickaxe. The end of a spell sent the two
  exit events and put the pick back only if it had been worn when the spell
  started (#611); a pick that lived only in the pack got nothing, and
  re-equipping by hand was what freed people. The end now cycles that pick,
  equipped and straight off again, and only if it is really in the pack.

  THE FAKE GAME. The real swingScript string from game/gamemode.js is run as
  the client runs it, against a pretend Skyrim Platform that records calls.
*/
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(__dirname, '..', 'game', 'gamemode.js');
const src = fs.readFileSync(SRC, 'utf8').split(String.fromCharCode(13)).join('');
let pass = 0, fail = 0;
function yes(w, c) { if (c) { pass++; console.log('PASS  ' + w); } else { fail++; console.log('FAIL  ' + w); } }
function done() { console.log(''); console.log(pass + ' passed, ' + fail + ' failed'); process.exit(fail ? 1 : 0); }

const a = src.indexOf('function swingScript() {');
const b = a < 0 ? -1 : src.indexOf('\n}\n', a);
yes('S0 swingScript is in the gamemode', a >= 0 && b > a);
if (!(a >= 0 && b > a)) { done(); }
const m = /const SWING_SHEATHE_MS = (\d+);/.exec(src);
const script = new Function('SWING_SHEATHE_MS', src.slice(a, b + 2) + '\nreturn swingScript();')(m ? Number(m[1]) : 1000);
const run = new Function('ctx', script);

const PICK = 0xe3c16;
function game(opts) {
  const calls = [];
  const p = { worn: !!opts.worn, count: opts.count == null ? 1 : opts.count };
  const pc = {
    equipItem: function (f) { calls.push('equip'); if (p.count <= 0) { p.count = 1; calls.push('HANDED A PICK'); } p.worn = true; },
    unequipItem: function (f) { calls.push('unequip'); p.worn = false; },
    getItemCount: function () { return p.count; }
  };
  const actor = { isWeaponDrawn: function () { return false; }, sheatheWeapon: function () { }, isEquipped: function () { return p.worn; } };
  const sp = {
    Game: { getPlayer: function () { return pc; }, getFormEx: function (id) { return { id: id }; } },
    Form: { from: function (f) { return f; } },
    Actor: { from: function () { return actor; } },
    Debug: { sendAnimationEvent: function (w, ev) { calls.push('anim ' + ev); } },
    Utility: { wait: function () { return new Promise(function () { }); } }
  };
  const state = {};
  return { calls: calls, p: p, frame: function (v) { run({ value: v, state: state, sp: sp }); } };
}
const START = { at: 1, anim: 'IdlePickaxeEnter', stop: 'IdleChairExitStart', free: 'IdleForceDefaultState', hold: true, tool: PICK };
const END = { at: 2, end: true, stop: 'IdleChairExitStart', free: 'IdleForceDefaultState', tool: PICK };
function spell(opts) { const g = game(opts); g.frame(START); const n = g.calls.length; g.frame(END); g.frame(END); return { g: g, end: g.calls.slice(n) }; }

{
  const r = spell({ worn: false, count: 1 });
  yes('P1 the done-when: a pick only in the pack is equipped and taken off at the end: ' + r.end.join(', '),
      r.end.join(',') === 'anim IdleChairExitStart,anim IdleForceDefaultState,equip,unequip');
  yes('P2 and they end with nothing in their hands, as they started', r.g.p.worn === false && r.g.p.count === 1);
  yes('P3 the exits go first, then the cycle', r.end.indexOf('equip') > r.end.indexOf('anim IdleForceDefaultState'));
}
{
  const r = spell({ worn: true, count: 1 });
  yes('W1 a pick that was worn is put back and left on, as #611 does: ' + r.end.join(', '),
      r.end.join(',') === 'anim IdleChairExitStart,anim IdleForceDefaultState,equip' && r.g.p.worn === true);
}
{
  const r = spell({ worn: false, count: 0 });
  yes('N1 a pick they no longer carry (broke, dropped) is never equipped, so nobody is handed one: ' + r.end.join(', '),
      r.end.indexOf('equip') < 0 && r.end.indexOf('HANDED A PICK') < 0);
}
{
  const g = game({ worn: false, count: 1 });
  g.frame({ at: 2, end: true, stop: 'IdleChairExitStart', free: 'IdleForceDefaultState', tool: 0 });
  yes('T1 an end with no tool cycles nothing', g.calls.join(',') === 'anim IdleChairExitStart,anim IdleForceDefaultState');
}
{
  const r = spell({ worn: false, count: 1 });
  yes('F1 the same end message on the next frames does nothing more', r.end.filter(function (c) { return c === 'equip'; }).length === 1);
}
yes('M1 stopMining still hands the tool id to the end', /function stopMining\(actorId\) \{[\s\S]{0,260}swingEnd\(actorId, tool\);/.test(src));
done();
