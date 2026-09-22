// test-offices.js
//
// The offices: a jarl names stewards, and a steward can end a claim.
//
// Patrick's design, 21 September. An admin gives an account the Jarl role, out
// of character, as world setup, and that is the ONLY out of character grant in
// the whole chain: nothing in the world can create the first office, so
// somebody has to place it. After that admins never grant anything again,
// because "admins only overlook the RP and not get involved on their admin
// characters". A jarl names stewards. A steward is NOT an admin and the only
// thing they can do that nobody else can is end a claim.
//
// WHAT ENDING A CLAIM MUST NOT DO is most of what is checked here. It does not
// touch what is in the house, because the alternative is a server that deletes
// people's possessions on somebody's say so. It does not take back a key,
// because nothing in the engine can change which key a door wants, so an
// evicted tenant who kept theirs can still walk in at night and the city's only
// answer is to deal with them like a person. That is the squatter story, and it
// falls out of the constraint rather than being written.
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

function lift(startsWith, endsWith) {
  const a = src.indexOf(startsWith);
  if (a < 0) { return null; }
  const b = src.indexOf(endsWith, a);
  return b < 0 ? null : src.slice(a, b + endsWith.length);
}

const cmdBlock = lift('  function stewardCmd(parts, profileId, toProfile) {', '\n  }\n');
const evictBlock = lift('  function evict(actorId, profileId, toProfile) {', '\n  }\n');

yes('the steward command is in the gamemode', cmdBlock !== null);
yes('and so is the eviction', evictBlock !== null);

const JARL = 1, ALICE = 101, BOB = 202;
const HOUSE = 'breezehome';

/** Drive /steward with a given list and caller. */
function steward(opts) {
  const told = [];
  const stewards = (opts.stewards || []).slice();
  const saved = { n: 0 };
  const fn = new Function(
    'parts', 'profileId', 'toProfile', 'stewards', 'isJarl', 'save', 'plog',
    cmdBlock + '\nreturn stewardCmd;');
  const call = fn(
    null, null, null, stewards,
    function (pid) { return pid === JARL; },
    function () { saved.n++; },
    function () { });
  call(opts.parts || ['/steward'], opts.by,
       function (pid, m) { told.push(m); });
  return { told: told, stewards: stewards, saves: saved.n };
}

/** Drive /evict with a given claim and caller. */
function evict(opts) {
  const told = [];
  const logs = [];
  const claims = {};
  if (opts.held) { claims[HOUSE] = opts.held; }
  const pushed = { n: 0 };
  const fn = new Function(
    'actorId', 'profileId', 'toProfile', 'isSteward', 'here', 'holderOf',
    'nameOf', 'claims', 'save', 'pushAll', 'plog',
    evictBlock + '\nreturn evict;');
  const call = fn(
    null, null, null,
    function (pid) { return (opts.stewards || []).indexOf(pid) !== -1; },
    function () { return opts.atDoor === false ? null : HOUSE; },
    function () { return claims[HOUSE] || null; },
    function () { return 'Breezehome'; },
    claims,
    function () { }, function () { pushed.n++; },
    function () { logs.push(Array.prototype.join.call(arguments, ' ')); });
  call(0xff000058, opts.by, function (pid, m) { told.push(m); });
  return { told: told, claims: claims, pushes: pushed.n };
}

if (cmdBlock !== null) {
  // S1: anybody may ask who holds the office. A hold's steward is not a secret.
  {
    const r = steward({ by: BOB, stewards: [ALICE] });
    yes('S1 anybody may ask who the stewards are',
        r.told.length === 1 && r.told[0].indexOf(String(ALICE)) !== -1);
    const none = steward({ by: BOB, stewards: [] });
    yes('S1 and with none it says how one is named',
        none.told[0].indexOf('A jarl names one') !== -1);
  }

  // S2: only a jarl names one. THE WHOLE POINT OF THE OFFICE.
  {
    const r = steward({ by: BOB, stewards: [], parts: ['/steward', String(ALICE)] });
    yes('S2 somebody who is not a jarl cannot name a steward',
        r.stewards.length === 0);
    yes('S2 and is told why', r.told[0] === 'Only a jarl names a steward.');
  }

  // S3: a jarl names one, and it is written down.
  {
    const r = steward({ by: JARL, stewards: [], parts: ['/steward', String(ALICE)] });
    yes('S3 a jarl names a steward', r.stewards.indexOf(ALICE) !== -1);
    yes('S3 and the register is written', r.saves === 1);
    const again = steward({ by: JARL, stewards: [ALICE],
                            parts: ['/steward', String(ALICE)] });
    yes('S3 and naming the same person twice does not double them',
        again.stewards.length === 1 && again.saves === 0);
  }

  // S4: and takes it back with a minus.
  {
    const r = steward({ by: JARL, stewards: [ALICE, BOB],
                        parts: ['/steward', '-' + ALICE] });
    yes('S4 a jarl takes the office back', r.stewards.indexOf(ALICE) === -1);
    yes('S4 and leaves the other one alone', r.stewards.indexOf(BOB) !== -1);
    const missing = steward({ by: JARL, stewards: [BOB],
                              parts: ['/steward', '-' + ALICE] });
    yes('S4 and taking it from somebody who never had it changes nothing',
        missing.stewards.length === 1 && missing.saves === 0);
  }

  // S5: a word that is not a number is not a profile id.
  {
    const r = steward({ by: JARL, stewards: [], parts: ['/steward', 'Alice'] });
    yes('S5 a name is refused, because two characters can share one',
        r.stewards.length === 0 && r.told[0].indexOf('not a profile id') !== -1);
  }
}

if (evictBlock !== null) {
  const alicesHouse = { by: ALICE, name: 'Alice', at: 1, touched: 1,
                        locked: true, ground: 'the field' };

  // S6: only a steward ends a claim.
  {
    const r = evict({ by: BOB, stewards: [], held: alicesHouse });
    yes('S6 somebody who is not a steward cannot end a claim',
        r.claims[HOUSE] && r.claims[HOUSE].by === ALICE);
    yes('S6 and is told the rule', r.told[0] === 'Only a steward ends a claim.');
  }

  // S7: a steward does, and the claim goes.
  {
    const r = evict({ by: BOB, stewards: [BOB], held: alicesHouse });
    yes('S7 a steward ends the claim', !r.claims[HOUSE]);
    yes('S7 and the view is pushed, so shut doors are right at once',
        r.pushes === 1);
    yes('S7 and the person who lost it is named to the steward',
        r.told[0].indexOf('Alice') !== -1);
  }

  // S8: AND IT SAYS WHAT IT DID NOT DO. Both of these are promises to the
  //     person being evicted as much as to the steward.
  {
    const r = evict({ by: BOB, stewards: [BOB], held: alicesHouse });
    yes('S8 it says belongings are untouched',
        r.told[0].indexOf('untouched') !== -1);
    yes('S8 and that a key they hold still works',
        r.told[0].indexOf('key') !== -1 && r.told[0].indexOf('still works') !== -1);
  }

  // S9: nothing to end, and nowhere to end it from.
  {
    yes('S9 a steward at a door nobody holds is told so',
        evict({ by: BOB, stewards: [BOB], held: null })
          .told[0].indexOf('Nobody holds') !== -1);
    yes('S9 and away from a door is told to go to one',
        evict({ by: BOB, stewards: [BOB], held: alicesHouse, atDoor: false })
          .told[0].indexOf('Stand at the door') !== -1);
  }
}

// ---------------------------------------------------------------- structure
{
  const code = src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ');
  yes('both words are in the one list every command is registered in',
      /'\/steward', '\/evict',/.test(code));
  yes('and the dispatcher hands them to the property block',
      /word === '\/steward' \|\| word === '\/evict'/.test(code));
  yes('a jarl is read from outside and never set in here',
      /__thornswoodIsJarl/.test(code) && !/stewards\.push\(.*jarl/i.test(code));
  // What matters is that the stewards go in the same file as the claims, not
  // the exact shape of that object: the box, the funds and the notices joined
  // it the same evening and an exact match broke on all three.
  yes('the stewards are written to the register beside the claims',
      /JSON\.stringify\(\{ claims: claims, stewards: stewards[,}]/.test(code));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
