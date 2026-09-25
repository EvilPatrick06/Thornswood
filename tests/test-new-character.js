// test-new-character.js
//
// A brand new character must be seen as new, and the starting purse must not
// be what stops that happening.
//
// MEASURED ON THE LIVE SERVER, 21 September, three sessions in a row and the
// same line every time:
//
//   15:19:54  chargen ff000058 profile 744947683 already has a character
//             carrying 1 thing, in the hall, no face, so creation is skipped
//
// In the hall, no face, and told they had already done this. The thing they
// were carrying was the forty gold the starting purse had handed them seconds
// earlier, on the same tick, from a loop that ran above the one that decides
// whether somebody is new. Creation was skipped and closeRaceMenu shut the
// race menu Spawn had correctly opened, so the person was left standing in the
// creation room with nothing. Djinn described exactly that from the other side.
//
// The decision reads a pack to answer "has this person played before". Gold the
// server hands out unprompted is the one thing in a pack that is no evidence of
// that, so it does not count. The purse also moved below the whole loop. Either
// fix alone is enough; both are here because the comment the old code leaned on
// said the ordering "cannot be wrong", and it was.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(TOOLS_DIR, 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// ---------------------------------------------------------------- the count
// A FAILURE AND NOT A THROW WHEN THE BLOCK IS NOT THERE. Pointed with GM at
// the version that was live on 21 September this has to give a verdict, not a
// stack trace: a harness that cannot report on the broken build is a harness
// nobody can use to prove the fix.
const START = '      const goldId = (globalThis.__thornswoodSpoils';
const END = '      } catch (e) { owns = 0; }\n';
const a = src.indexOf(START);
const b = a < 0 ? -1 : src.indexOf(END, a);
const block = (a >= 0 && b >= 0) ? src.slice(a, b + END.length) : null;

const GOLD = 0x0000000F;
const SWORD = 0x12eb7;

yes('the count knows about gold at all', block !== null);

/** Run the real block against a pack and hand back what it counted. */
function counts(entries) {
  if (block === null) { return null; }
  const mp = { get: function () { return { entries: entries }; } };
  const fn = new Function('mp', 'actorId', 'globalThis',
                          block + '\nreturn owns;');
  return fn(mp, 0xff000058, { __thornswoodSpoils: { GOLD: GOLD } });
}

yes('an empty pack owns nothing', counts([]) === 0);
yes('THE BUG: a pack holding only the starting purse owns nothing',
    counts([{ baseId: GOLD, count: 40 }]) === 0);
yes('a pack with a sword in it owns something',
    counts([{ baseId: SWORD, count: 1 }]) === 1);
yes('gold beside real things is not counted, the things are',
    counts([{ baseId: GOLD, count: 40 }, { baseId: SWORD, count: 1 }]) === 1);
yes('two real things count as two',
    counts([{ baseId: SWORD, count: 1 }, { baseId: 0x1397d, count: 2 }]) === 2);
yes('a hole in the pack is skipped rather than counted',
    counts([null, { baseId: GOLD, count: 40 }]) === 0);

// An inventory read that throws must count as nothing owned, because
// re-creating somebody who has played is the worse of the two mistakes and the
// doubt is supposed to go the other way.
if (block !== null) {
  const mp = { get: function () { throw new Error('no inventory'); } };
  const fn = new Function('mp', 'actorId', 'globalThis',
                          block + '\nreturn owns;');
  yes('a pack that cannot be read counts as nothing',
      fn(mp, 0xff000058, { __thornswoodSpoils: { GOLD: GOLD } }) === 0);
}

// The gold id comes from the spoils block, so the two can never drift apart,
// and there is still an answer if that block has not loaded.
if (block !== null) {
  const fn = new Function('mp', 'actorId', 'globalThis',
                          block + '\nreturn goldId;');
  const mp = { get: function () { return { entries: [] }; } };
  yes('the gold id is taken from the spoils block',
      fn(mp, 1, { __thornswoodSpoils: { GOLD: 0xABC } }) === 0xABC);
  yes('and falls back to Gold001 when that block is not there',
      fn(mp, 1, {}) === 0x0000000F);
}

// ------------------------------------------------------------- the ordering
//
// A source order check, because the fault was never in a value. Both fixes were
// made, and this is the one that says the second is still true.
{
  const code = src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ');
  const decision = code.indexOf('const returning = owns > 0');
  const handout = code.indexOf('spoilsBlock.purse(who)');
  yes('the returning decision is still in the file', decision > 0);
  yes('the purse handout is still in the file', handout > 0);
  yes('THE BUG: the purse is handed out AFTER the decision that reads a pack',
      decision > 0 && handout > decision);
  yes('and it is handed out exactly once',
      (code.match(/spoilsBlock\.purse\(who\)/g) || []).length === 1);
}

// --------------------------------------------------- and somebody puts it on
/*
  THE SHIFT ARRIVED AND NOBODY EVER PUT IT ON.

  Reported 21 September and again on the 23rd: "Still spawned in with no
  clothes on". giveShift has always written the worn flag onto the INVENTORY
  entry, which is the only field a gamemode can write; the client dresses
  itself out of the EQUIPMENT record, whose property binding in the fork has a
  Get and no Set. So the clothes sat in the pack.

  That is also half of why clothes never moved the temperature: the equipment
  update the client sends is what fills the server's record, and a client that
  was never asked to wear anything sends nothing to record.

  These hold the ask: that it exists, that the shift uses it, that arrival
  uses it, and that it is taken back afterwards, because a property left on a
  character is handed to the owner again at the next login and would re-dress
  somebody in clothes they had deliberately taken off.
*/
{
  const code = src
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ');
  yes('there is a way to ask somebody to put something on',
      /function wearThese\(actorId, baseIds\)/.test(code) &&
      /mp\.makeProperty\(WEAR_PROPERTY/.test(code));
  yes('the ask is edge triggered like the swing, through ctx.state',
      /st\.thornswoodWearAt === v\.at/.test(code));
  yes('and it equips rather than granting anything',
      /pc\.equipItem\(it, false, true\)/.test(code));
  yes('the shift asks for itself to be worn', /wearThese\(actorId, toWear\)/.test(code));
  yes('arriving puts back whatever the server believes is worn',
      /function wearWhatIsWorn\(actorId\)/.test(code) &&
      /wearWhatIsWorn\(actorId\)/.test(code.slice(code.indexOf('grantKnown(actorId)'))));
  yes('nothing is invented: only worn things already in the pack',
      /if \(e && e\.worn && e\.baseId\) \{ ids\.push\(e\.baseId\); \}/.test(code));
  yes('and the ask is taken back, so it cannot fire again at the next login',
      /mp\.set\(actorId, WEAR_PROPERTY, \{ ids: \[\], at: 0 \}\)/.test(code));

  /*
    AND NOBODY HAS TO WALK THROUGH A DOOR TO GET DRESSED.

    Patrick, on being told a relog would show it: "your clothes should be
    fucking on if you left them". Dressing at the door only helps the person
    who arrives afterwards; anybody already standing in the world in their
    skin stayed that way until they quit.

    The server can READ the equipment record even though it cannot write one,
    so it can see somebody wearing nothing beside a pack that says otherwise.
    That is the only state it acts on: taking your boots off is a decision,
    and this must never argue with one.
  */
  yes('somebody already standing there undressed is put right where they are',
      /function dressIfBare\(actorId\)/.test(code) && /dressIfBare\(actorId\)/.test(
        code.slice(code.indexOf('function dressIfBare'))));
  yes('it reads what they actually have on rather than assuming',
      /function wornNow\(actorId\)/.test(code) && /mp\.get\(actorId, 'equipment'\)/.test(code));
  yes('an equipment record it cannot read is left alone, because unreadable is not empty',
      /if \(on === null\) \{ return ''; \}/.test(code));
  yes('and it only ever acts on somebody wearing nothing at all',
      /if \(on\.length\) \{/.test(code));
  yes('it gives up rather than arguing forever',
      /DRESS_TRIES/.test(code) && /if \(\(dressTried\[actorId\] \|\| 0\) >= DRESS_TRIES\) \{ return ''; \}/.test(code));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
