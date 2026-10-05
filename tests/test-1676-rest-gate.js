// test-1676-rest-gate.js
//
// #1676. exhaustion.md: "Under 15, crafting is refused. Mining, chopping,
// fishing and the other class verbs still happen." The needs block has held
// the number (CRAFT_REST) and the answer (tooTiredToCraft) since the first
// commit of this repository, and nothing asked it: mp.onCraft never did, so a
// person at rest 0 crafted as freely as one at 100.
//
// Now the needs block answers the line (craftRefusal), and every way of
// making something asks it before anything is taken: a bench's own menu
// (mp.onCraft, brews and tempering included), a key cut at a forge, and a
// kiln burned by pressing it. Both sides of 15 are run.
//
// The REAL needs block runs over a stand-in mp and a clock turned by hand.
// mp.onCraft, burnCharcoal and the property block's cutKey are lifted out of
// the gamemode as they stand and run with small stand-ins for what they call.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const SRC = process.env.GM || path.join(ROOT, 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const gm = fs.readFileSync(SRC, 'utf8').split(CR).join('');

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
function slice(start, end) {
  const a = gm.indexOf(start);
  if (a < 0) { return null; }
  const b = gm.indexOf(end, a + start.length);
  return b < 0 ? null : gm.slice(a, b + end.length);
}

const needsBlock = slice('// ==== thornswood needs: hunger, thirst and exhaustion ====', '// ==== end thornswood needs ====');
const onCraftSrc = slice("mp.onCraft = guard('onCraft', function (actorId, craftedItemBaseId, count, recipeId, workbenchId, effects) {", '\n});\n');
const kilnSrc = slice('function burnCharcoal(actorId, refrId) {', '\n}\n');
const cutKeySrc = slice('  function cutKey(actorId, profileId, toProfile, parts) {', '\n  }\n');
yes('the needs block, mp.onCraft, burnCharcoal and cutKey are in the gamemode',
    !!needsBlock && !!onCraftSrc && !!kilnSrc && !!cutKeySrc);
if (!needsBlock || !onCraftSrc || !kilnSrc || !cutKeySrc) { done(); }

const ME = 0xff000001;

/* The real needs block, with one person whose rest is what this file says. */
function needsAt(rest) {
  const store = {};
  const clock = { now: Date.UTC(2026, 9, 4, 20, 0, 0) };
  const g = {};
  const N = new Function('globalThis', 'mp', 'Date', 'console', 'setInterval', 'clearInterval',
    'guard', 'notify', 'say', needsBlock + '\nreturn globalThis.__thornswoodNeeds;')(
    g, {
      getOnlinePlayers: function () { return [ME]; },
      makeProperty: function () { },
      get: function (id, key) { return key === 'worldOrCellDesc' ? 'cell:X.esm' : store[id]; },
      set: function (id, key, v) { store[id] = JSON.parse(JSON.stringify(v)); }
    }, { now: function () { return clock.now; } }, { log: function () { } },
    function () { return 0; }, function () { }, function (n, f) { return f; },
    function () { }, function () { });
  // Already in the world and settled a moment ago, so nothing moves the meter.
  N.settle(ME);
  const n = N.fresh();
  n.rest = rest;
  n.at = clock.now;
  store[ME] = n;
  return N;
}

// ------------------------------------------------------- the needs block --

{
  const N = needsAt(100);
  yes('N1 the gate is 15, the page\'s number', N.CRAFT_REST === 15);
  yes('N1 the needs block hands out the line every craft asks', typeof N.craftRefusal === 'function');
  if (typeof N.craftRefusal !== 'function') { done(); }
  yes('N2 at 15 nothing is refused', needsAt(15).craftRefusal(ME) === '' && needsAt(15).tooTiredToCraft(ME) === false);
  yes('N2 at 100 nothing is refused', needsAt(100).craftRefusal(ME) === '');
  const line = needsAt(14.9).craftRefusal(ME);
  yes('N3 just under 15 is refused, and the line says why: too tired, Rest under 15 (' + line + ')',
      /too tired to make anything/i.test(line) && /Rest is under 15/.test(line) && needsAt(14.9).tooTiredToCraft(ME) === true);
  yes('N3 at 0 too', needsAt(0).craftRefusal(ME) === line);
  yes('N3 the line tells nobody to type anything, and says no banned word',
      !/\//.test(line) && !/player/i.test(line) && line.indexOf(String.fromCharCode(0x2014)) === -1);
}

// --------------------------------------------------- a bench's own menu --

/*
  mp.onCraft as it stands. Everything after the gates is a stand-in that
  records it was reached, so "the craft went on" is that record, and nothing
  taken from the pack is that no write to the inventory happened.
*/
function craftAt(rest, recipeId, hurtLine) {
  const said = [];
  const reached = [];
  const writes = [];
  const G = { __thornswoodNeeds: needsAt(rest) };
  if (hurtLine !== undefined) { G.__thornswoodHurt = { craftRefusal: function () { return hurtLine; } }; }
  const mp = {
    getDescFromId: function (id) { reached.push('desc'); return 'abc:Skyrim.esm'; },
    set: function (id, key) { writes.push(key); },
    get: function () { return null; }
  };
  const handler = new Function('globalThis', 'mp', 'guard', 'notify', 'say', 'log',
    'recipelessCraft', 'craftRow', 'craftAnswer',
    'var onCraft;\n' + onCraftSrc.replace('mp.onCraft = guard(', 'onCraft = guard(') + '\nreturn onCraft;')(
    G, mp, function (n, f) { return f; },
    function (id, line) { said.push(line); }, function (id, line) { said.push(line); }, function () { },
    function () { reached.push('recipeless'); return undefined; },
    function () { reached.push('row'); return null; },
    function () { reached.push('answer'); return {}; });
  const out = handler(ME, 0x12, 1, recipeId, 0x0a01, undefined);
  return { out: out, said: said, reached: reached, writes: writes };
}

{
  const tired = craftAt(14.9, 0x1234);
  yes('C1 a craft at a bench just under 15 is refused: the engine is told no',
      tired.out === false);
  yes('C1 with the line that says why', tired.said.length >= 1 && /too tired to make anything/i.test(tired.said[0]));
  yes('C1 and nothing past the gate ran, so nothing was taken: the materials stay in the pack',
      tired.reached.length === 0 && tired.writes.length === 0);
  const rested = craftAt(15, 0x1234);
  yes('C2 at 15 the same craft goes on to the recipe', rested.out !== false && rested.reached.indexOf('desc') !== -1 &&
      !rested.said.some(function (l) { return /too tired/i.test(l); }));
  const brewTired = craftAt(3, 0);
  yes('C3 a craft with no recipe (a brew, an enchantment, tempering) is refused too under 15',
      brewTired.out === false && brewTired.reached.indexOf('recipeless') === -1);
  const brew = craftAt(50, 0);
  yes('C3 and goes on at 50', brew.out !== false && brew.reached.indexOf('recipeless') !== -1);
  const both = craftAt(3, 0x1234, 'Your arm is broken.');
  yes('C4 the injury check is still asked first, and only its line is said',
      both.out === false && both.said.length > 0 && both.said.every(function (l) { return l === 'Your arm is broken.'; }));
  const hurtOnly = craftAt(80, 0x1234, '');
  yes('C4 a fit, rested person is not refused by either', hurtOnly.out !== false);
}

// ------------------------------------------------ a kiln, by pressing it --

function kilnAt(rest) {
  const took = [];
  const gave = [];
  const run = new Function('globalThis', 'halfGate', 'toolGate', 'cooldownLeft', 'KILN_ARMED', 'KILN_ARM_MS',
    'rankStep', 'takeItem', 'addItem', 'ITEMS', 'stampCooldown', 'creditWork', 'wearTool',
    kilnSrc + '\nreturn burnCharcoal;')(
    { __thornswoodNeeds: needsAt(rest) },
    function () { return null; }, function () { return null; }, function () { return 0; },
    {}, 15000, function () { return 0; },
    function (id, item, n) { took.push(n); return true; },
    function (id, item, n) { gave.push(n); return true; },
    { firewood: 'fw', charcoalT1: 'c1', charcoalT2: 'c2', charcoalT3: 'c3', charcoalT4: 'c4' },
    function () { }, function () { return null; }, function () { return null; });
  const first = run(ME, 0x77);
  const second = run(ME, 0x77);
  return { first: first, second: second, took: took, gave: gave };
}

{
  const tired = kilnAt(10);
  yes('K1 pressing a kiln under 15 is refused with the line, both presses',
      /too tired to make anything/i.test(tired.first) && /too tired to make anything/i.test(tired.second));
  yes('K1 and no firewood is taken, no charcoal given', tired.took.length === 0 && tired.gave.length === 0);
  const rested = kilnAt(15);
  yes('K2 at 15 the kiln asks, then burns: firewood taken and charcoal given',
      /Press it again/.test(rested.first) && /kiln yields/.test(rested.second) &&
      rested.took.length === 1 && rested.gave.length === 1);
}

// ------------------------------------------------ a key cut at a forge --

function keyAt(rest) {
  const told = [];
  const took = [];
  const gave = [];
  const run = new Function('g', 'isSmith', 'forgeHere', 'moldInHand', 'heldBy', 'here', 'takeItem',
    'giveNamed', 'addItem', 'KEY_INGOT', 'KEY', 'keyLabel', 'nameOf', 'plog',
    cutKeySrc + '\nreturn cutKey;')(
    { __thornswoodNeeds: needsAt(rest) },
    function () { return true; }, function () { return true; },
    function () { return 'home:Skyrim.esm'; }, function () { return []; }, function () { return ''; },
    function (id, item, n) { took.push(n); return true; },
    function () { gave.push(1); return true; }, function () { },
    'ingot', 'key', function () { return 'Key to Honeyside'; }, function () { return 'Honeyside'; },
    function () { });
  const out = run(ME, 202, function (pid, m) { told.push(m); }, ['/key']);
  return { out: out, told: told, took: took, gave: gave };
}

{
  const tired = keyAt(5);
  yes('F1 cutting a key at a forge under 15 is refused with the line',
      tired.out === true && tired.told.length === 1 && /too tired to make anything/i.test(tired.told[0]));
  yes('F1 and the iron ingot stays in the pack, no key is made', tired.took.length === 0 && tired.gave.length === 0);
  const rested = keyAt(15);
  yes('F2 at 15 the key is cut from one ingot', rested.took.length === 1 && rested.gave.length === 1 &&
      /You cut a key/.test(rested.told.join(' ')));
}

// ------------------------------------------------------------ the wiring --

{
  const code = gm.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
  const asks = code.match(/needs\.craftRefusal\(actorId\)/g) || [];
  yes('W1 three crafts ask the gate: a bench\'s menu, a kiln pressed, a key at a forge', asks.length === 3);
  function body(start) {
    const a = code.indexOf(start);
    if (a < 0) { return ''; }
    const b = code.indexOf('\n}\n', a);
    return code.slice(a, b);
  }
  const verbs = ['function mineSalt(', 'function chopWood(', 'function harvest('];
  yes('W2 mining, chopping and gathering do not ask it: the page keeps the class verbs going',
      verbs.every(function (v) { const b = body(v); return !!b && b.indexOf('craftRefusal') === -1; }));
  yes('W3 the gate is asked before anything is taken in each',
      onCraftSrc.indexOf('craftRefusal') < onCraftSrc.indexOf('recipelessCraft(') &&
      kilnSrc.indexOf('craftRefusal') < kilnSrc.indexOf('takeItem(') &&
      cutKeySrc.indexOf('craftRefusal') < cutKeySrc.indexOf('takeItem('));
}

done();
