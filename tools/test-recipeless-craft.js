// test-recipeless-craft.js
//
// Brewing, enchanting and tempering: the three things that reach the craft
// event with no recipe behind them.
//
// THE FIRST VERSION OF THIS GATE DECIDED ON THE OUTPUT'S RECORD TYPE AND ALL
// THREE OF ITS FAULTS CAME FROM THAT. The audit of 21 September found them:
//
//   * a brewed potion HAS NO RECORD. Mixing a potion and enchanting an item
//     both MAKE A NEW FORM, so the id is above 0xff000000 and kindOf, which
//     reads plugin records, answers nothing. The gate refused every brew: the
//     change written to let the Alchemist work was the thing stopping it.
//   * TEMPERING ARRIVES HERE NOW. CraftService throws out the armour table and
//     the sharpening wheel before it considers a recipe, which leaves the
//     recipe list EMPTY, and an empty list is what the fork patch reports
//     rather than drops. A tempered sword is a WEAP, so it read as an
//     enchantment and was refused to every smith in the world.
//   * NOTHING CREDITED THE WORK, so an Alchemist could brew for ever and stay
//     a novice: creditWork is the only road to rankUp.
//
// So the runtime line is the discriminator. Above it something was made from
// nothing and the BENCH says which trade. Below it the item already existed,
// which is tempering, and this gate has no business in it.
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

const START = 'function recipelessCraft(actorId, craftedItemBaseId, workbenchId) {';
const END = '\n}\n';
const a = src.indexOf(START);
const b = a < 0 ? -1 : src.indexOf(END, a);
const block = (a >= 0 && b >= 0) ? src.slice(a, b + END.length) : null;

yes('the recipeless gate is in the gamemode', block !== null);

// A potion or an enchanted item: made at runtime, so above the line.
const BREWED = 0xff001234;
// A tempered sword: the same record it always was, so below it.
const TEMPERED = 0x12eb7;

/** Drive the real function. */
function run(opts) {
  const said = [];
  const logs = [];
  const credited = [];
  const fn = new Function(
    'actorId', 'craftedItemBaseId', 'workbenchId',
    'globalThis', 'log', 'notify', 'say', 'aWord', 'mp', 'idOf', 'Number',
    block + '\nreturn recipelessCraft;');

  const character = opts.noCharacter ? null : {
    stateOf: function () {
      if (opts.stateThrows) { throw new Error('no character'); }
      return opts.state;
    },
    nameOf: function (k) { return k.charAt(0).toUpperCase() + k.slice(1); },
    credit: function (id, half) { credited.push(half); }
  };

  const g = {
    __thornswoodCharacter: character,
    __thornswoodProgression: {
      halvesOf: function (prof) {
        const m = {
          alchemist: ['blightbrewer', 'physicker'],
          enchanter: ['bladebinder', 'wardweaver'],
          smith: ['platewright', 'edgewright']
        };
        return m[prof] || [];
      }
    }
  };

  const call = fn(
    null, null, null, g,
    function () { logs.push(Array.prototype.join.call(arguments, ' ')); },
    function (id, m) { said.push(m); },
    function (id, m) { said.push(m); },
    function (n) { return /^[AEIOU]/i.test(n) ? 'an ' + n : 'a ' + n; },
    { get: function () { return 'bench'; },
      lookupEspmRecordById: function () {
        if (opts.benchThrows) { throw new Error('no bench record'); }
        return opts.bench === null ? null
          : { record: { editorId: opts.bench || 'AlchemyWorkbench' } };
      } },
    function () { return 1; },
    Number);

  const out = call(0xff000058, opts.made, 0x1234);
  return { refused: out === false, said: said, logs: logs, credited: credited };
}

if (block !== null) {
  const alchemist = { prof: 'alchemist', half: 'physicker', taught: [] };
  const enchanter = { prof: 'enchanter', half: 'bladebinder', taught: [] };
  const smith = { prof: 'smith', half: 'edgewright', taught: [] };

  // S1: THE FAULT THAT BROKE BREWING. A potion is a runtime form with no
  //     record at all, so nothing can be learned from its type.
  {
    const r = run({ made: BREWED, bench: 'AlchemyWorkbench', state: alchemist });
    yes('S1 an Alchemist may brew, and the output having no record does not stop it',
        !r.refused);
    yes('S1 and nothing is said to them', r.said.length === 0);
  }

  // S2: AND THE WORK COUNTS, or the half can never leave novice.
  {
    const r = run({ made: BREWED, bench: 'AlchemyWorkbench', state: alchemist });
    yes('S2 brewing credits the half they hold', r.credited.length === 1 &&
        r.credited[0] === 'physicker');
    const e = run({ made: BREWED, bench: 'CraftingEnchantingTable', state: enchanter });
    yes('S2 and enchanting credits theirs', e.credited[0] === 'bladebinder');
  }

  // S3: THE BENCH DECIDES, NOT THE ITEM. Same runtime output, two benches.
  {
    yes('S3 an Alchemist at an enchanting table is refused',
        run({ made: BREWED, bench: 'CraftingEnchantingTable', state: alchemist }).refused);
    yes('S3 an Enchanter at an alchemy lab is refused',
        run({ made: BREWED, bench: 'AlchemyWorkbench', state: enchanter }).refused);
    const r = run({ made: BREWED, bench: 'AlchemyWorkbench', state: smith });
    yes('S3 a Smith at an alchemy lab is refused and told whose work it is',
        r.refused && r.said[0].indexOf('Alchemist') !== -1);
  }

  // S4: TEMPERING. The item already existed, so the id is below the runtime
  //     line and this gate has no business in it. A smith must not be refused
  //     at a grindstone, which is what deciding on the output type did.
  {
    const r = run({ made: TEMPERED, bench: 'CraftingSmithingSharpeningWheel',
                    state: smith });
    yes('S4 tempering is allowed, whoever is doing it', !r.refused);
    yes('S4 and nothing is said', r.said.length === 0);
    yes('S4 and it is not credited as a brew', r.credited.length === 0);
    yes('S4 an Alchemist tempering is also allowed, because it is not this gate\'s business',
        !run({ made: TEMPERED, bench: 'CraftingSmithingArmorTable',
               state: alchemist }).refused);
  }

  // S5: a half taught by a Master of another profession counts, at novice.
  {
    const taughtBrewer = { prof: 'smith', half: 'edgewright', taught: ['physicker'] };
    const r = run({ made: BREWED, bench: 'AlchemyWorkbench', state: taughtBrewer });
    yes('S5 a taught half may do the work', !r.refused);
    yes('S5 and the taught half is what gets credited',
        r.credited[0] === 'physicker');
    yes('S5 a taught half of another profession does not',
        run({ made: BREWED, bench: 'AlchemyWorkbench',
              state: { prof: 'smith', half: 'edgewright', taught: ['hearthcook'] } }).refused);
  }

  // S6: nobody is stranded on their first evening.
  {
    yes('S6 a character with no profession yet is let through',
        !run({ made: BREWED, bench: 'AlchemyWorkbench',
               state: { prof: null, taught: [] } }).refused);
  }

  // S7: A BENCH NOBODY HAS CLASSIFIED IS NOT A REFUSAL. That is a hole in our
  //     table, and it must not cost somebody their materials.
  {
    yes('S7 an unknown bench lets an Alchemist work',
        !run({ made: BREWED, bench: 'SomeModdedThing', state: alchemist }).refused);
    yes('S7 and an Enchanter too',
        !run({ made: BREWED, bench: 'SomeModdedThing', state: enchanter }).refused);
    yes('S7 but still refuses somebody who holds neither trade',
        run({ made: BREWED, bench: 'SomeModdedThing', state: smith }).refused);
    yes('S7 and a bench lookup that throws is treated the same way',
        !run({ made: BREWED, benchThrows: true, state: alchemist }).refused);
  }

  // S8: it fails OPEN on the server's own faults. A character the server
  //     cannot read must not cost somebody their ingredients.
  {
    yes('S8 a character block that is not loaded lets the craft through',
        !run({ made: BREWED, bench: 'AlchemyWorkbench', state: alchemist,
               noCharacter: true }).refused);
    yes('S8 a character read that throws lets it through',
        !run({ made: BREWED, bench: 'AlchemyWorkbench', state: alchemist,
               stateThrows: true }).refused);
  }
}

// ---------------------------------------------------------------- structure
{
  const code = src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ');
  yes('onCraft takes the workbench the fork sends',
      /function \(actorId, craftedItemBaseId, count, recipeId, workbenchId\)/.test(code));
  yes('and a craft with no recipe goes to the gate',
      /if \(!recipeId\) \{/.test(code) &&
      /return recipelessCraft\(actorId, craftedItemBaseId, workbenchId\);/.test(code));
  yes('the runtime line is what splits made-from-nothing from tempering',
      /0xff000000/.test(code) && /madeFromNothing/.test(code));
  yes('and the output record type is no longer consulted',
      !/RECIPELESS\[kind\]/.test(code));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
