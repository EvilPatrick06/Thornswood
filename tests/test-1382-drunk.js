// test-1382-drunk.js
//
//     node tests/test-1382-drunk.js
//
// #1382, docs/systems/drink.md: "Drunk, from the third ale until you sleep or
// the 45 minutes pass: the client draws a sway and a soft edge." Patrick,
// 12 Oct 2026, decision 3: a small drunk screen effect of our own in the
// content plugin.
//
// Root cause: nothing kept whether somebody was drunk, nothing told the
// client, and no record drew it. The server keeps drunk on the needs record
// (NEEDS.ale.drunkFrom), the needs HUD script hands it to the front plugin's
// globalThis.thornswoodDrunk, and the front plugin applies the content
// plugin's ThornswoodDrunkImod.
//
// Drives the real needs block and the real HUD script, and reads the
// committed plugin and front plugin. Read only.
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(path.join(ROOT, 'game', 'gamemode.js'), 'utf8').split(CR).join('');
const front = fs.readFileSync(path.join(ROOT, 'game', 'plugins', 'thornswood-front.js'), 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const A = '// ==== thornswood needs: hunger, thirst and exhaustion ====';
const B = '// ==== end thornswood needs ====';
const a = src.indexOf(A);
const b = a < 0 ? -1 : src.indexOf(B, a);
const block = (a >= 0 && b >= 0) ? src.slice(a, b) : null;

function rig() {
  const store = {};
  const online = [];
  const clock = { now: 1000000000000 };
  const g = {};
  const Fake = {
    getOnlinePlayers: function () { return online.slice(); },
    makeProperty: function () { },
    getDescFromId: function () { return ''; },
    get: function (id, key) {
      if (key === 'worldOrCellDesc') { return 'cell:X.esm'; }
      return store[id];
    },
    set: function (id, key, v) { store[id] = JSON.parse(JSON.stringify(v)); }
  };
  const api = new Function(
    'globalThis', 'mp', 'Date', 'console', 'setInterval', 'clearInterval', 'guard', 'notify', 'say',
    'var FOODS = { items: { "34c5e:Skyrim.esm": { k: "ale" } } }; function idOf(d) { return parseInt(d, 16); }\n' +
    block + '\nreturn globalThis.__thornswoodNeeds;')(
    g, Fake, { now: function () { return clock.now; } }, { log: function () { } },
    function () { return 0; }, function () { }, function (n, f) { return f; }, function () { }, function () { });
  g.__thornswoodHurt = { exposed: function () { return false; }, careChanged: function () { } };
  api.clock = clock;
  api.online = online;
  api.store = store;
  return api;
}

const MIN = 60000;
const ME = 0xff000001;
const ALE = 0x34c5e;
let r = null;
try { r = block ? rig() : null; } catch (e) { console.log('  (' + e.message + ')'); }
yes('the needs block runs', !!r);

if (r) {
  yes('drunk is from the third ale', r.NEEDS.ale.drunkFrom === 3);
  r.online.push(ME); r.store[ME] = r.fresh(); r.settle(ME);
  r.consumed(ME, ALE); r.consumed(ME, ALE);
  yes('two ales are not drunk', r.store[ME].drunk === false);
  r.consumed(ME, ALE);
  yes('the third is', r.store[ME].drunk === true);
  yes('and a read keeps it', r.read(ME).drunk === true);
  r.clock.now += 30 * MIN; r.settle(ME);
  yes('still drunk 30 minutes on', r.store[ME].drunk === true);
  r.clock.now += 16 * MIN; r.settle(ME);
  yes('and not once the 45 minutes pass', r.store[ME].drunk === false);

  // A night in a bed ends it: three ales, lie down, log out, come back after a night.
  const r2 = rig();
  r2.online.push(ME); r2.store[ME] = r2.fresh(); r2.settle(ME);
  r2.consumed(ME, ALE); r2.consumed(ME, ALE); r2.consumed(ME, ALE);
  const n = r2.read(ME); n.resting = 'bed'; r2.store[ME] = n;
  r2.online.length = 0; r2.tick(); r2.clock.now += 30 * MIN; r2.online.push(ME); r2.settle(ME);
  yes('a night in a bed, back inside the 45 minutes: not drunk, and the count starts over',
    r2.store[ME].drunk === false && r2.store[ME].ale === 0);
}

// The HUD script hands drunk to the front plugin, once per change.
function lift(name) {
  const at = src.indexOf('function ' + name + '()', a);
  if (at < 0) { return null; }
  const end = src.indexOf('\n  }', at);
  return end > 0 ? src.slice(at, end + 4) : null;
}
const hud = lift('hudScript');
yes('the needs HUD script is in the needs block', !!hud && src.indexOf('function hudScript()', a) < b);
if (hud) {
  const made = new Function(hud + '\nreturn hudScript();')();
  const told = [];
  const state = {};
  const ctx = function (v) {
    return { value: Object.assign({ food: 60, drink: 60, rest: 60, temp: 50 }, v), state: state,
             sp: { browser: { executeJavaScript: function () { } }, Debug: { notification: function () { } } } };
  };
  delete globalThis.thornswoodDrunk;
  new Function('ctx', made)(ctx({ drunk: true }));
  yes('with no hook yet, nothing is marked as handed over', state.thornswoodDrunk === undefined);
  globalThis.thornswoodDrunk = function (on) { told.push(on); };
  new Function('ctx', made)(ctx({ drunk: true }));
  new Function('ctx', made)(ctx({ drunk: true }));
  yes('once the hook is there it is told drunk, once', told.length === 1 && told[0] === true);
  new Function('ctx', made)(ctx({ drunk: false }));
  yes('and told when it ends', told.length === 2 && told[1] === false);
  delete globalThis.thornswoodDrunk;
}

// The front plugin applies the content plugin's own record.
const m = /const DRUNK_IMOD = 0x([0-9a-fA-F]+);/.exec(front);
yes('the front plugin defines the hook', front.indexOf('globalThis.thornswoodDrunk = function') !== -1);
yes('and draws with applyCrossFade and takes it off with removeCrossFade',
  front.indexOf('mod.applyCrossFade(DRUNK_FADE)') !== -1 && front.indexOf('ImageSpaceModifier.removeCrossFade(DRUNK_FADE)') !== -1);
const esp = fs.readFileSync(path.join(ROOT, 'game', 'content', 'Thornswood-Content.esp'));
let imad = null;
{
  let p = 24 + esp.readUInt32LE(4);
  while (p + 24 <= esp.length) {
    const size = esp.readUInt32LE(p + 4);
    const isGroup = esp.toString('latin1', p, p + 4) === 'GRUP';
    if (isGroup && esp.toString('latin1', p + 8, p + 12) === 'IMAD') {
      let q = p + 24;
      while (q < p + size) {
        const rs = esp.readUInt32LE(q + 4);
        if (m && esp.readUInt32LE(q + 12) === ((5 << 24) | parseInt(m[1], 16))) { imad = esp.slice(q + 24, q + 24 + rs); }
        q += 24 + rs;
      }
    }
    p += isGroup ? size : 24 + size;
  }
}
yes('the record it names is the plugin\'s ThornswoodDrunkImod', !!imad && imad.indexOf('ThornswoodDrunkImod') === 6);
if (imad) {
  const at = imad.indexOf('DNAM');
  yes('and it is not animatable, so it holds while applied', at > 0 && imad.readUInt32LE(at + 6) === 0);
  const tnam = imad.indexOf('TNAM');
  yes('and it tints nothing', tnam > 0 && imad.readFloatLE(tnam + 6 + 16) === 0 && imad.readFloatLE(tnam + 6 + 36) === 0);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
