// test-recipeless-craft.js
//
// Brewing and enchanting, which have no recipe record anywhere in the game.
//
// A potion is worked out from the effects the ingredients share, inside a menu,
// with nothing in the files to match against, and enchanting is the same shape.
// So the server's FindRecipe came back empty for both, and what happened next
// was a log line and nothing else: the inputs were never removed and the output
// was never added, so the potion somebody watched themselves make was undone by
// the next inventory the server sent. Check-Balance.ps1 found it in one line,
// "the Alchemist owns no recipe in this build at all", and two of the eight
// professions could be picked and could make nothing.
//
// The fork asks now instead of dropping it (commit 8bce01a0): recipeId 0, the
// workbench as a fifth argument. THIS SIDE DECIDES, and the thing worth testing
// is that it decides NO by default, because without a record the server is
// taking the client's word for what went in and what came out.
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

const START = 'var RECIPELESS = {';
const END = '\n}\n';
const a = src.indexOf(START);
const b = a < 0 ? -1 : src.indexOf(END, src.indexOf('function recipelessCraft', a));
const block = (a >= 0 && b >= 0) ? src.slice(a, b + END.length) : null;

yes('the recipeless gate is in the gamemode', block !== null);

const ALCH_POTION = 0x3eadd;
const A_SWORD = 0x12eb7;
const A_SHIELD = 0x1396b;
const A_ROCK = 0x6f;

/**
 * Drive the real function against one character and one thing being made.
 *
 * Only the four things that touch the world are replaced: the log, the two
 * ways of speaking to a person, and the record lookup.
 */
function run(opts) {
  const said = [];
  const logs = [];
  const kinds = opts.kinds || {};
  const spoils = opts.noSpoils ? null : {
    kindOf: function (id) {
      if (opts.kindThrows) { throw new Error('no record'); }
      return Object.prototype.hasOwnProperty.call(kinds, id) ? kinds[id] : '';
    }
  };
  const character = opts.noCharacter ? null : {
    stateOf: function () {
      if (opts.stateThrows) { throw new Error('no character'); }
      return opts.state;
    },
    nameOf: function (k) { return k.charAt(0).toUpperCase() + k.slice(1); }
  };
  const progression = {
    halvesOf: function (prof) {
      const m = {
        alchemist: ['blightbrewer', 'physicker'],
        enchanter: ['bladebinder', 'wardweaver'],
        smith: ['platewright', 'edgewright']
      };
      return m[prof] || [];
    }
  };
  const g = {
    __thornswoodSpoils: spoils,
    __thornswoodCharacter: character,
    __thornswoodProgression: progression
  };
  const fn = new Function(
    'log', 'notify', 'say', 'aWord', 'globalThis',
    block + '\nreturn recipelessCraft;');
  const call = fn(
    function () { logs.push(Array.prototype.join.call(arguments, ' ')); },
    function (id, m) { said.push(m); },
    function (id, m) { said.push(m); },
    function (n) { return /^[AEIOU]/i.test(n) ? 'an ' + n : 'a ' + n; },
    g);
  const out = call(0xff000058, opts.made, opts.bench || 0x1234);
  return { refused: out === false, said: said, logs: logs };
}

if (block !== null) {
  const kinds = {};
  kinds[ALCH_POTION] = 'ALCH';
  kinds[A_SWORD] = 'WEAP';
  kinds[A_SHIELD] = 'ARMO';
  kinds[A_ROCK] = 'MISC';

  const alchemist = { prof: 'alchemist', half: 'physicker', taught: [] };
  const enchanter = { prof: 'enchanter', half: 'bladebinder', taught: [] };
  const smith = { prof: 'smith', half: 'edgewright', taught: [] };

  // S1: THE WHOLE POINT. An Alchemist can brew, and could not before.
  {
    const r = run({ made: ALCH_POTION, kinds: kinds, state: alchemist });
    yes('S1 an Alchemist may brew a potion', !r.refused);
    yes('S1 and is not told anything about it', r.said.length === 0);
  }

  // S2: and an Enchanter may enchant, both a weapon and a piece of armour.
  {
    yes('S2 an Enchanter may enchant a weapon',
        !run({ made: A_SWORD, kinds: kinds, state: enchanter }).refused);
    yes('S2 and a piece of armour',
        !run({ made: A_SHIELD, kinds: kinds, state: enchanter }).refused);
  }

  // S3: somebody else may not, and is told whose work it is.
  {
    const r = run({ made: ALCH_POTION, kinds: kinds, state: smith });
    yes('S3 a Smith may not brew', r.refused);
    yes('S3 and is told it is Alchemist work',
        r.said.length > 0 && r.said[0].indexOf('Alchemist') !== -1);
    yes('S3 an Alchemist may not enchant a weapon',
        run({ made: A_SWORD, kinds: kinds, state: alchemist }).refused);
  }

  // S4: THE DEFENCE. Anything that is not a potion, a weapon or armour has no
  //     record saying what it is, and nothing legitimate reaches this path,
  //     so it is refused whoever asks.
  {
    yes('S4 a thing of another kind is refused even from an Alchemist',
        run({ made: A_ROCK, kinds: kinds, state: alchemist }).refused);
    yes('S4 and a kind the lookup cannot answer at all is refused',
        run({ made: 0xdead, kinds: kinds, state: alchemist }).refused);
    yes('S4 and a lookup that throws is refused rather than allowed',
        run({ made: ALCH_POTION, kinds: kinds, state: alchemist,
              kindThrows: true }).refused);
  }

  // S5: a Master of another profession taught you, so it is yours at novice.
  //     The halves come from the rulebook, not from a second copy of the list.
  {
    const taughtBrewer = { prof: 'smith', half: 'edgewright',
                           taught: ['physicker'] };
    yes('S5 a taught half of the profession may do the work',
        !run({ made: ALCH_POTION, kinds: kinds, state: taughtBrewer }).refused);
    const taughtElse = { prof: 'smith', half: 'edgewright',
                         taught: ['hearthcook'] };
    yes('S5 and a taught half of some other profession may not',
        run({ made: ALCH_POTION, kinds: kinds, state: taughtElse }).refused);
  }

  // S6: nobody is stranded on their first evening, the same rule the recipe
  //     gate keeps: no profession chosen yet is let through.
  {
    yes('S6 a character with no profession yet is let through',
        !run({ made: ALCH_POTION, kinds: kinds,
               state: { prof: null, taught: [] } }).refused);
  }

  // S7: IT FAILS OPEN ON ITS OWN FAULTS AND SHUT ON THE CLIENT'S. A character
  //     the server cannot read is the server's problem and must not cost
  //     somebody their ingredients; a claim the server cannot check is the
  //     client's and must not be believed. S4 is the other half of this.
  {
    yes('S7 a character block that is not loaded lets the craft through',
        !run({ made: ALCH_POTION, kinds: kinds, state: alchemist,
               noCharacter: true }).refused);
    yes('S7 a character read that throws lets it through',
        !run({ made: ALCH_POTION, kinds: kinds, state: alchemist,
               stateThrows: true }).refused);
    yes('S7 but a missing record lookup still refuses',
        run({ made: ALCH_POTION, kinds: kinds, state: alchemist,
              noSpoils: true }).refused);
  }
}

// ---------------------------------------------------------------- structure
{
  const code = src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ');
  yes('onCraft takes the workbench the fork now sends',
      /function \(actorId, craftedItemBaseId, count, recipeId, workbenchId\)/.test(code));
  yes('and a craft with no recipe goes to the gate',
      /if \(!recipeId\) \{/.test(code) &&
      /return recipelessCraft\(actorId, craftedItemBaseId, workbenchId\);/.test(code));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
