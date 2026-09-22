// test-deposit.js
//
// A seam holds twenty, gives one a swing, and comes back on a clock.
//
// Patrick, 21 September, after playing it: "make each quarry have up to 20 ore
// and not skip the animation ... you get an ore each time you hit it you know
// not all at omce so you can stay for a little and get a little or stay andd
// get all 20", with ten minutes for iron, gold, corundum and silver and thirty
// for moonstone, quicksilver, orichalcum, ebony and malachite.
//
// WHAT IT REPLACED: one press handed over the whole yield and then refused
// everybody for between ten minutes and four hours. A seam was a vending
// machine with a long queue. And every branch of the activate chain ends at
// `return false`, which blocks the engine's own handover, so the mining
// animation was thrown away by our own code.
//
// Read only.
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(__dirname, 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const a = src.indexOf('const DEPOSIT_SIZE = 20;');
const b = a < 0 ? -1 : src.indexOf('\n}\n', src.indexOf('function depositBackIn', a));
const block = (a >= 0 && b >= 0) ? src.slice(a, b + 3) : null;

yes('the deposit is in the gamemode', block !== null);

/** The real functions, with one reference's property in a box and a clock. */
function rig(startAt) {
  const store = {};
  const clock = { now: startAt || 1000000 };
  const logs = [];
  const fn = new Function(
    'mp', 'log', 'Date', 'Number', 'Math', 'String',
    block + '\nreturn { left: depositLeft, take: takeFromDeposit, ' +
            'backMs: depositBackMs, backIn: depositBackIn, SIZE: DEPOSIT_SIZE };');
  const api = fn(
    { get: function (id, key) { return store[key]; },
      set: function (id, key, v) { store[key] = v; } },
    function () { logs.push(Array.prototype.join.call(arguments, ' ')); },
    { now: function () { return clock.now; } },
    Number, Math, String);
  api.clock = clock;
  api.store = store;
  return api;
}

if (block !== null) {
  const REF = 0xabc;

  // S1: twenty in a fresh seam, one at a time.
  {
    const r = rig();
    yes('S1 a seam nobody has touched holds twenty', r.left(REF, 600000) === r.SIZE);
    yes('S1 twenty is the number Patrick asked for', r.SIZE === 20);
    const first = r.take(REF, 600000);
    yes('S1 one swing takes one', first === 20 && r.left(REF, 600000) === 19);
  }

  // S2: THE WHOLE POINT. Stay and work it down, or take a little and go.
  {
    const r = rig();
    let got = 0;
    for (let i = 0; i < 20; i++) { if (r.take(REF, 600000)) { got++; } }
    yes('S2 twenty swings give twenty ore', got === 20);
    yes('S2 and the twenty-first gives nothing', r.take(REF, 600000) === 0);
    yes('S2 and the seam reads as empty', r.left(REF, 600000) === 0);
  }

  // S3: and it comes back on its own clock, for everybody at once.
  {
    const r = rig();
    for (let i = 0; i < 20; i++) { r.take(REF, 600000); }
    yes('S3 still empty a minute later',
        (r.clock.now += 60000, r.left(REF, 600000) === 0));
    yes('S3 full again after ten minutes',
        (r.clock.now += 600000, r.left(REF, 600000) === 20));
    yes('S3 and can be worked again', r.take(REF, 600000) === 20);
  }

  // S4: PATRICK'S TWO NUMBERS, by name.
  {
    const r = rig();
    const quick = ['Iron Ore', 'Gold Ore', 'Corundum Ore', 'Silver Ore'];
    const slow = ['Moonstone Ore', 'Quicksilver Ore', 'Orichalcum Ore',
                  'Ebony Ore', 'Malachite Ore'];
    let allQuick = true, allSlow = true;
    quick.forEach(function (n) { if (r.backMs(n) !== 10 * 60000) { allQuick = false; } });
    slow.forEach(function (n) { if (r.backMs(n) !== 30 * 60000) { allSlow = false; } });
    yes('S4 iron, gold, corundum and silver come back in ten minutes', allQuick);
    yes('S4 moonstone, quicksilver, orichalcum, ebony and malachite in thirty', allSlow);
    yes('S4 and an ore nobody named takes the LONGER one, not the shorter',
        r.backMs('Some Modded Ore') === 30 * 60000);
    yes('S4 and so does one with no name at all', r.backMs('') === 30 * 60000);
  }

  // S5: a deposit read while it is refilling does not half-refill.
  {
    const r = rig();
    for (let i = 0; i < 20; i++) { r.take(REF, 1800000); }
    r.clock.now += 1799000;
    yes('S5 a second short of its time it is still empty', r.left(REF, 1800000) === 0);
    r.clock.now += 2000;
    yes('S5 and a second past it is whole again', r.left(REF, 1800000) === 20);
  }

  // S6: a property read that throws is a full seam, not a dead one. Failing
  //     shut here would take every seam in the province out of the game.
  {
    const fn = new Function(
      'mp', 'log', 'Date', 'Number', 'Math', 'String',
      block + '\nreturn depositLeft;');
    const left = fn(
      { get: function () { throw new Error('no property'); }, set: function () { } },
      function () { }, { now: function () { return 1; } }, Number, Math, String);
    yes('S6 a seam the server cannot read is workable, not broken',
        left(REF, 600000) === 20);
  }
}

// ---------------------------------------------------------------- structure
{
  const code = src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ');
  yes('mining answers ALLOW so the press is not blocked',
      /return ALLOW;/.test(code));
  yes('and the chain lets an ALLOW through without saying anything',
      /if \(message === ALLOW\) \{ return; \}/.test(code));
  yes('a swing takes one rather than the whole pair',
      /const yielded = 1;/.test(code));
  // Specific to mining: fishing has its own cooldown and keeps it.
  const mineBody = code.slice(code.indexOf('function mineOre'),
                              code.indexOf('function chopWood'));
  yes('and mining no longer refuses the press with a per-person cooldown',
      mineBody.indexOf('cooldownLeft(') === -1);
  yes('quicksilver is on the thirty minute clock rather than silver\'s ten',
      /DEPOSIT_SLOW/.test(code) &&
      code.indexOf('DEPOSIT_SLOW') < code.indexOf('DEPOSIT_QUICK[j]'));

  /*
    THE CHECK THIS HARNESS DID NOT HAVE, AND THE REASON IT PASSED ALL EVENING
    WHILE PATRICK TOOK A HUNDRED ORE OUT OF ONE VEIN.

    Everything above drives the real functions over a pretend mp whose get and
    set work. On the live server they did not. DEPOSIT_PROPERTY was the only
    property in gamemode.js never registered with mp.makeProperty, so every
    read threw, depositLeft's fail-open answered a full seam, and every write
    threw as well. The arithmetic was perfect and there was nowhere to keep it.

    A harness that supplies its own storage can never find that. So it asks the
    file instead, which is the one question a stub cannot answer.
  */
  yes('the deposit property is registered, or nothing it counts is ever stored',
      /mp\.makeProperty\(DEPOSIT_PROPERTY/.test(code));
  yes('and a seam that cannot be written says so rather than never running out',
      src.indexOf('CANNOT BE WRITTEN') !== -1);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
