// test-town-gate-claim.js
//
// City gates are claimable properties (#615).
//
// Build-DoorTable only maps doors into interiors, so town gates were never
// buildings. /claim at the Whiterun gate fell through to farming ("Only a
// farmer can bring a crop in"). Patrick decided gates SHOULD be claimable
// via the mold flow. This checks the tables and that openTheGates skips a
// property-shut gate.
//
//   node tests/test-town-gate-claim.js
'use strict';
const fs = require('fs');
const path = require('path');
const GM = path.join(__dirname, '..', 'game', 'gamemode.js');
const FRONT = path.join(__dirname, '..', 'game', 'plugins', 'thornswood-front.js');
const CR = String.fromCharCode(13);
const gm = fs.readFileSync(GM, 'utf8').split(CR).join('');
const front = fs.readFileSync(FRONT, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

yes('Whiterun outer gate maps to a building', /'1b1f1:Skyrim\.esm':\s*'gate:whiterun-main'/.test(gm));
yes('Whiterun inner gate maps to the same building', /'1b1f3:Skyrim\.esm':\s*'gate:whiterun-main'/.test(gm));
yes('Riften gates map to a building', /'42284:Skyrim\.esm':\s*'gate:riften-main'/.test(gm) && /'42286:Skyrim\.esm':\s*'gate:riften-main'/.test(gm));
yes('Whiterun gate has a plain name', /'gate:whiterun-main':\s*'Whiterun Main Gate'/.test(gm));
yes('Riften gate has a plain name', /'gate:riften-main':\s*'Riften Main Gate'/.test(gm));
yes('Whiterun inside leaf is a way out', /'1b1f3:Skyrim\.esm':\s*1/.test(gm) && /addTownGateProperties/.test(gm));
yes('lockScript publishes __thornswoodPropertyShut', /__thornswoodPropertyShut/.test(gm));
yes('openTheGates skips property-shut gates', /__thornswoodPropertyShut/.test(front) && /shut\[id\]/.test(front));

// Drive openTheGates with a pretend shut map.
{
  const a = front.indexOf('  const TOWN_GATES = [');
  const b = a < 0 ? -1 : front.indexOf('\n  }\n', front.indexOf('function openTheGates', a));
  const block = (a >= 0 && b >= 0) ? front.slice(a, b + 5) : null;
  yes('openTheGates block still extracts', !!block);
  if (block) {
    const world = {};
    function gate(locked) {
      return { state: !!locked, isLocked: function () { return this.state; },
               lock: function (on) { this.state = !!on; this.calls = (this.calls || 0) + 1; } };
    }
    const WHITERUN = 0x1b1f1;
    const g = gate(true);
    world[WHITERUN] = g;
    const said = [];
    const fn = new Function(
      'sp', 'say', 'Date', 'globalThis',
      block + '\nreturn { open: openTheGates, ids: TOWN_GATES };');
    const api = fn(
      { Game: { getFormEx: function (id) { return world[id] || null; } },
        ObjectReference: { from: function (f) { return f; } } },
      function (line) { said.push(line); },
      { now: function () { return 1; } },
      { __thornswoodPropertyShut: { [WHITERUN]: true } });
    api.open();
    yes('a property-shut Whiterun gate is left locked', g.state === true && !g.calls);
    // Clear shut map: should open.
    const g2 = gate(true);
    world[WHITERUN] = g2;
    const api2 = fn(
      { Game: { getFormEx: function (id) { return world[id] || null; } },
        ObjectReference: { from: function (f) { return f; } } },
      function (line) { said.push(line); },
      { now: function () { return 1; } },
      { __thornswoodPropertyShut: {} });
    api2.open();
    yes('an unclaimed Whiterun gate still opens', g2.state === false && g2.calls === 1);
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
