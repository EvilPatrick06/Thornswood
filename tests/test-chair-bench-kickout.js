// test-chair-bench-kickout.js
//
// Chair/bench kick-out (#843).
//
// Sitting turns player controls off with no menu. The controls watchdog,
// stuck rescue and ownTheCharacter used to fight that by calling
// enablePlayerControls / setPlayerAIDriven(false), which stands people up.
// notOurs() already treated getFurnitureReference as intentional; the ref
// can still flicker null while seated. The fix adds a furnitureEnter/Exit
// seated flag and getSitState, so any one signal keeps the rescues off.
//
//   node tests/test-chair-bench-kickout.js
'use strict';
const fs = require('fs');
const path = require('path');
const FRONT = process.env.FRONT ||
  path.join(__dirname, '..', 'game', 'plugins', 'thornswood-front.js');
const CR = String.fromCharCode(13);
const front = fs.readFileSync(FRONT, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

yes('front names the chair/bench kick-out work', /Chair\/bench kick-out \(#843\)/.test(front));
yes('front keeps a seatedInFurniture flag', /let seatedInFurniture = false;/.test(front));
yes('furnitureEnter sets seated for any player furniture',
    /seatedInFurniture = true;/.test(front) &&
    /furnitureEnter/.test(front));
yes('furnitureExit clears seated', /seatedInFurniture = false;/.test(front) &&
    /furnitureExit/.test(front));
yes('notOurs checks the seated flag',
    /typeof seatedInFurniture !== 'undefined' && seatedInFurniture/.test(front));
yes('notOurs still checks getFurnitureReference',
    /getFurnitureReference\(\)/.test(front));
yes('notOurs checks getSitState',
    /getSitState/.test(front) && /if \(sit\) \{ return 'in furniture'; \}/.test(front));

// Drive the real notOursNow / controlsTick out of the plugin.
const START = '  const CONTROLS = [';
const END_MARK = "  sp.on('update', guard('controls', controlsTick));";
const a = front.indexOf(START);
const b = a < 0 ? -1 : front.indexOf(END_MARK, a);
// While bound (#2573) the watchdog leaves fighting off: boundOn and
// controlsBackOn sit just above the extract in the plugin, so they are lifted
// with it, as the plugin has them, nobody bound.
const BOUND_FROM = front.indexOf('  function controlsBackOn() {');
const BOUND_PIECE = BOUND_FROM < 0 ? '' : front.slice(BOUND_FROM, front.indexOf('\n  }\n', BOUND_FROM) + 4);
const block = (a >= 0 && b >= 0 && BOUND_PIECE) ? 'let boundOn = false;\n' + BOUND_PIECE + front.slice(a, b) : null;
yes('controls watchdog block still extracts', !!block);

function harness(opts) {
  opts = opts || {};
  const clock = { t: 0 };
  const counts = { enable: 0, setAI: 0, getSit: 0, getFurn: 0 };
  const said = [];
  const flags = Object.assign({
    isMovementControlsEnabled: true,
    isFightingControlsEnabled: true,
    isCamSwitchControlsEnabled: true,
    isLookingControlsEnabled: true,
    isSneakingControlsEnabled: true,
    isMenuControlsEnabled: true,
    isActivateControlsEnabled: true,
    isJournalControlsEnabled: true
  }, opts.flags || {});
  const player = {
    isDead: function () { return !!opts.dead; },
    getFurnitureReference: function () {
      counts.getFurn++;
      return opts.furniture || null;
    },
    getSitState: function () {
      counts.getSit++;
      return opts.sitState || 0;
    }
  };
  const sp = {
    Game: {
      getPlayer: function () { return opts.noPlayer ? null : player; },
      enablePlayerControls: function () { counts.enable++; },
      setPlayerAIDriven: function () { counts.setAI++; }
    },
    Ui: { isMenuOpen: function () { return false; } }
  };
  Object.keys(flags).forEach(function (k) {
    sp.Game[k] = function () { return flags[k]; };
  });
  function busyMenuOpen() { return ''; }
  const say = function (t) { said.push(t); };
  const FakeDate = { now: function () { return clock.t; } };
  // seatedInFurniture is declared outside the CONTROLS extract in the plugin.
  // Mirror it here so the typeof-guard path can be driven.
  const prelude = 'var seatedInFurniture = ' + (opts.seated ? 'true' : 'false') + ';\n';
  const fn = new Function('sp', 'busyMenuOpen', 'say', 'Date',
    prelude + block +
    '\nreturn { tick: controlsTick, notOurs: notOurs, setSeated: function (v) { seatedInFurniture = v; } };');
  const api = fn(sp, busyMenuOpen, say, FakeDate);
  api.counts = counts;
  api.said = said;
  api.run = function (from, to, step) {
    step = step || 16;
    for (let t = from; t <= to; t += step) { clock.t = t; api.tick(); }
  };
  return api;
}

if (block) {
  // Controls off for 6s while standing: still rescued once.
  const standing = harness({
    flags: { isMovementControlsEnabled: false },
    sitState: 0,
    furniture: null,
    seated: false
  });
  standing.run(0, 6000, 16);
  yes('standing + controls off: still enables once', standing.counts.enable === 1);

  // Furniture ref present: never stand them up.
  const withRef = harness({
    flags: { isMovementControlsEnabled: false },
    furniture: { id: 1 },
    sitState: 0,
    seated: false
  });
  withRef.run(0, 6000, 16);
  yes('furniture ref: does not enable controls', withRef.counts.enable === 0);
  yes('furniture ref: does not clear AI driven', withRef.counts.setAI === 0);
  yes('furniture ref: notOurs says in furniture', withRef.notOurs() === 'in furniture');

  // Sit state alone (ref flickered null): still protected.
  const sitOnly = harness({
    flags: { isMovementControlsEnabled: false },
    furniture: null,
    sitState: 3,
    seated: false
  });
  sitOnly.run(0, 6000, 16);
  yes('getSitState 3 alone: does not enable controls', sitOnly.counts.enable === 0);
  yes('getSitState 3 alone: notOurs says in furniture', sitOnly.notOurs() === 'in furniture');

  // Enter/exit seated flag alone (ref and sit state both empty): still protected.
  const flagOnly = harness({
    flags: { isMovementControlsEnabled: false },
    furniture: null,
    sitState: 0,
    seated: true
  });
  flagOnly.run(0, 6000, 16);
  yes('seated flag alone: does not enable controls', flagOnly.counts.enable === 0);
  yes('seated flag alone: notOurs says in furniture', flagOnly.notOurs() === 'in furniture');

  // Getting up (sit state 4) must also be left alone.
  const standingUp = harness({
    flags: { isMovementControlsEnabled: false },
    furniture: null,
    sitState: 4,
    seated: false
  });
  standingUp.run(0, 6000, 16);
  yes('getSitState 4 (standing up): does not enable', standingUp.counts.enable === 0);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
