// test-1382-ale-help-hangover.js
//
//     node tests/test-1382-ale-help-hangover.js
//
// #1382: the first two ales give +0.05 melee damage for 5 real minutes and
// the third does not; three or more and a logout without a bed leaves you
// hung over, rest read as weary, until a night in a bed. docs/systems/drink.md.
// Drives the real needs block.
// Drives the real needs block out of game/gamemode.js.
const REPO_DIR = require('path').join(__dirname, '..');
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(REPO_DIR, 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const A = '// ==== thornswood needs: hunger, thirst and exhaustion ====';
const B = '// ==== end thornswood needs ====';
const a = src.indexOf(A);
const b = a < 0 ? -1 : src.indexOf(B, a);
let block = (a >= 0 && b >= 0) ? src.slice(a, b) : null;

function rig(startAt) {
  const store = {};
  const online = [];
  const clock = { now: startAt || 1000000000000 };
  const said = [];
  const g = {};
  const Fake = {
    getOnlinePlayers: function () { return online.slice(); },
    makeProperty: function () { },
    getDescFromId: function () { return ''; },
    get: function (id, key) {
      if (key === 'worldOrCellDesc') { return (store[id] && store[id].cell) || 'cell:X.esm'; }
      return store[id] ? store[id].v : undefined;
    },
    set: function (id, key, v) {
      if (!store[id]) { store[id] = {}; }
      store[id].v = v;
    }
  };
  const FakeDate = { now: function () { return clock.now; } };
  const fn = new Function(
    'globalThis', 'mp', 'Date', 'console', 'setInterval', 'clearInterval',
    'guard', 'notify', 'say', 'Math', 'Number', 'String', 'Object', 'isFinite',
    'var FOODS = { items: { "34c5e:Skyrim.esm": { k: "ale" } } }; function idOf(d) { return parseInt(d, 16); }\n' +
    block + '\nreturn globalThis.__thornswoodNeeds;');
  const api = fn(
    g, Fake, FakeDate, { log: function () { } },
    function () { return 0; }, function () { },
    function (n, f) { return f; },
    function (id, line) { said.push(line); },
    function (id, line) { said.push(line); },
    Math, Number, String, Object, isFinite);
  api.clock = clock;
  api.said = said;
  api.seed = function (id) { Fake.set(id, 'x', api.fresh()); };
  api.__set = function (id, n) { Fake.set(id, 'x', n); };
  api.hurt = [];
  api.online = online;
  g.__thornswoodHurt = { exposed: function (id, kind, source) { api.hurt.push([id, kind, source]); return false; } };
  return api;
}

let smoke = null;
if (block !== null) {
  try { smoke = rig(); } catch (e) { console.log('  (' + e.message + ')'); block = null; }
}
yes('the needs block is in the gamemode and runs', block !== null && !!smoke);

if (block !== null && smoke) {
  const MIN = 60000;
  const ME = 0xff000001;
  const ALE = 0x34c5e;
  const A = smoke.NEEDS.ale;
  yes('ale help is +0.05 for 5 minutes through the second, hangover from 3',
      A.help === 0.05 && A.helpMinutes === 5 && A.helpThrough === 2 && A.hangoverFrom === 3);
  function rigAle() { const r = rig(); r.online.push(ME); r.seed(ME); r.settle(ME); return r; }
  const dmg = (r) => r.effects(ME, r.read(ME)).attackDamageMult || 0;
  {
    const r = rigAle();
    const base = dmg(r);
    r.consumed(ME, ALE);
    yes('the first ale gives +0.05 melee damage', Math.abs(dmg(r) - base - 0.05) < 1e-9);
    r.clock.now += 4 * MIN;
    yes('still there at 4 minutes', Math.abs(dmg(r) - base - 0.05) < 1e-9);
    r.clock.now += 1 * MIN + 1000;
    yes('gone after 5 minutes', Math.abs(dmg(r) - base) < 1e-9);
  }
  {
    const r = rigAle();
    const base = dmg(r);
    r.consumed(ME, ALE); r.clock.now += 1000;
    r.consumed(ME, ALE); r.clock.now += 1000;
    const until2 = r.read(ME).aleHelpUntil;
    r.consumed(ME, ALE);
    yes('the second ale renews it, the third does not', r.read(ME).aleHelpUntil === until2 && until2 > 0);
    yes('the help does not stack', Math.abs(dmg(r) - base - 0.05) < 1e-9);
  }
  function restCost(r) { return r.effects(ME, r.read(ME)).stamina || 0; }
  {
    const r = rigAle();
    r.consumed(ME, ALE); r.consumed(ME, ALE); r.consumed(ME, ALE);
    const n = r.read(ME); n.rest = 100; r.__set(ME, n);
    const sober = r.effects(ME, r.read(ME));
    // Log out on the road, not in a bed, and come back an hour later.
    r.online.length = 0; r.tick();
    r.clock.now += 60 * MIN;
    r.online.push(ME);
    r.settle(ME);
    yes('three ales and no bed: hung over next time in the world', r.read(ME).hangover === true);
    const hung = r.effects(ME, r.read(ME));
    const weary = r.effects(ME, Object.assign(r.read(ME), { hangover: false, rest: 40 }));
    yes('rest is read as weary while the meter is full', JSON.stringify(hung) === JSON.stringify(weary) && JSON.stringify(hung) !== JSON.stringify(sober));
  }
  {
    const r = rigAle();
    r.consumed(ME, ALE); r.consumed(ME, ALE);
    r.online.length = 0; r.tick(); r.clock.now += 60 * MIN; r.online.push(ME); r.settle(ME);
    yes('two ales do not hang you over', r.read(ME).hangover === false);
  }
  {
    const r = rigAle();
    r.consumed(ME, ALE); r.consumed(ME, ALE); r.consumed(ME, ALE);
    const n = r.read(ME); n.resting = 'bed'; r.__set(ME, n);
    r.online.length = 0; r.tick(); r.clock.now += 60 * MIN; r.online.push(ME); r.settle(ME);
    yes('three ales then a bed: no hangover', r.read(ME).hangover === false);
  }
}
console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
