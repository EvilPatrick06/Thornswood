// test-staff-spells.js
//
// Issue #967. Patrick, 28 September: "Enchanters learn staff spells from spell
// tomes". Before this nobody could make a staff: 160 of the Bladebinder's 161
// recipes ask for the staff's own spell and an Enchanter starts with none.
//
// This runs the real blocks out of game/gamemode.js in a sandbox with a fake mp
// that keeps properties the way the server does (JSON in, JSON out):
//   the rules (thornswood progression), the character store (thornswood
//   character), THE STAFF SPELLS block with its mp.onReadBook, and the real
//   craftAnswer the craft gate asks.
// and proves:
//   A. the generated table: every staff row names a spell STAFF_SPELLS knows,
//      and the build opened the Bladebinder (issue's Done when)
//   B. an Enchanter who reads a tome of a staff spell has it recorded and is
//      told so in chat, and the book is never refused
//   C. a staff whose spell is not recorded is refused with a sentence saying
//      which tome to read, and allowed once it is
//   D. anybody who may not make staves reads the tome and gets the normal
//      effect only: nothing recorded, nothing said
//   E. what was learned survives a restart, in the character store
//
// Read only.
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const REPO = path.join(__dirname, '..');
const SRC = process.env.GM || path.join(REPO, 'game', 'gamemode.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function between(a, b) {
  const i = src.indexOf(a);
  const j = i < 0 ? -1 : src.indexOf(b, i);
  return (i >= 0 && j >= 0) ? src.slice(i, j) : null;
}
function take(start, end) {
  const i = src.indexOf(start);
  const j = i < 0 ? -1 : src.indexOf(end || '\n}\n', i);
  return (i >= 0 && j >= 0) ? src.slice(i, j + (end || '\n}\n').length) : null;
}

const RULES = between('// ==== thornswood progression ====', '// ==== end thornswood progression ====');
const CHARACTER = between('// ==== thornswood character ====', '// ==== end thornswood character ====');
const STAFF = between('// ==== thornswood staff spells ====', '// ==== end thornswood staff spells ====');
const GATE_PARTS = [
  take('function craftAnswer(actorId, row) {'),
  take('function raceGate(actorId, row) {'),
  take('var RACE_CALLED = {', '\n};\n'),
  take('function professionName(prof) {'),
  take('function aWord(name) {'),
  take('function rankWord(rank) {')
];
yes('the rules, the character store and the staff spells block are in the gamemode',
    RULES !== null && CHARACTER !== null && STAFF !== null);
yes('craftAnswer and what it calls are in the gamemode',
    GATE_PARTS.every(function (p) { return p !== null; }));
if (RULES === null || CHARACTER === null || STAFF === null ||
    !GATE_PARTS.every(function (p) { return p !== null; })) {
  console.log('\n' + pass + ' passed, ' + fail + ' failed');
  process.exit(1);
}

// The generated recipe table, read as it is.
const tableAt = src.indexOf('  var RECIPES_BY_ID = {');
const tableEnd = tableAt < 0 ? -1 : src.indexOf('\n  };\n', tableAt);
let TABLE = {};
try { TABLE = JSON.parse(src.slice(tableAt + '  var RECIPES_BY_ID = '.length, tableEnd + 4)); } catch (e) { TABLE = {}; }

// ------------------------------------------------------------- the server --

// A tome desc -> a number and back, the way mp.getDescFromId answers.
const IDS = {};
const DESCS = {};
let nextId = 0x100;
function idFor(desc) {
  if (!Object.prototype.hasOwnProperty.call(IDS, desc)) { IDS[desc] = ++nextId; DESCS[nextId] = desc; }
  return IDS[desc];
}

/*
  One server process. store is the properties on every actor, kept as JSON the
  way the engine keeps them in the change form, so handing the same store to a
  second server() is a restart: nothing in memory survives, only the store.
*/
function server(store) {
  const said = [];
  const mp = {
    makeProperty: function () { },
    get: function (id, key) {
      if (key === 'profileId') { return 1000 + (id & 0xff); }
      const p = store[id] || {};
      return Object.prototype.hasOwnProperty.call(p, key) ? JSON.parse(p[key]) : undefined;
    },
    set: function (id, key, value) {
      (store[id] = store[id] || {})[key] = JSON.stringify(value);
    },
    getDescFromId: function (n) { return DESCS[n] || ('unknown' + n + ':Nowhere.esp'); }
  };
  const ctx = {
    mp: mp, JSON: JSON, Object: Object, Array: Array, String: String, Number: Number, Math: Math,
    console: { log: function () { }, error: function () { } },
    guard: function (name, fn) { return fn; },
    notify: function (id, m) { said.push({ id: id, text: m, how: 'notify' }); },
    say: function (id, m) { said.push({ id: id, text: m, how: 'chat' }); },
    log: function () { }
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(RULES, ctx, { filename: 'gamemode.js rules' });
  vm.runInContext(CHARACTER, ctx, { filename: 'gamemode.js character' });
  vm.runInContext(GATE_PARTS[4], ctx, { filename: 'gamemode.js aWord' });
  vm.runInContext(STAFF, ctx, { filename: 'gamemode.js staff spells' });
  const gate = new Function('globalThis', 'log', 'toldCraftingIsComing', 'raceOf',
                            GATE_PARTS.join('\n') + '\nreturn craftAnswer;')(
    ctx, function () { }, {}, function () { return ''; });
  return {
    ctx: ctx, mp: mp, said: said,
    C: ctx.__thornswoodCharacter, P: ctx.__thornswoodProgression, S: ctx.__thornswoodStaffSpells,
    read: function (actor, tomeDesc) { return ctx.mp.onReadBook(actor, idFor(tomeDesc)); },
    craft: function (actor, row) { return gate(actor, row); }
  };
}

/** A character with this class and profession, written into the store. */
function make(srv, actor, cls, prof, half, rank) {
  let s = srv.C.stateOf(actor);
  let r = srv.P.pickClass(s, cls);
  if (r.ok) { s = r.state; }
  if (prof) {
    r = srv.P.pickProfession(s, prof, half);
    if (r.ok) { s = r.state; }
    if (rank) { s.ranks[half] = rank; }
  }
  srv.C.writeState(actor, s);
  return srv.C.stateOf(actor);
}

// ---------------------------------------------------------- A. the table --

const store0 = {};
const first = server(store0);
const SPELLS = (first.S && first.S.STAFF_SPELLS) || {};
const spellKeys = Object.keys(SPELLS);
yes('the staff spells block exports its table (' + spellKeys.length + ' spells)', spellKeys.length > 100);

const staffRows = Object.keys(TABLE).filter(function (k) { return TABLE[k].half === 'Bladebinder'; });
const withSpell = staffRows.filter(function (k) { return !!TABLE[k].spell; });
yes('160 of the Bladebinder rows name the spell they bind (' + withSpell.length + ' of ' + staffRows.length + ')',
    withSpell.length === 160);
yes('every spell a staff row names is in STAFF_SPELLS',
    withSpell.every(function (k) { return Object.prototype.hasOwnProperty.call(SPELLS, TABLE[k].spell); }));
const taughtSpells = spellKeys.filter(function (k) { return (SPELLS[k].tomes || []).length > 0; });
const untaught = spellKeys.filter(function (k) { return (SPELLS[k].tomes || []).length === 0; });
yes('most staff spells are taught by a tome (' + taughtSpells.length + ' of ' + spellKeys.length + ')',
    taughtSpells.length > 100);
yes('every spell has a name', spellKeys.every(function (k) { return typeof SPELLS[k].name === 'string' && SPELLS[k].name.length > 0; }));

// Thunderbolt, measured in Build-RecipeTable's header: SpellTomeThunderbolt's
// BOOK DATA reads 4, 0x10f7ee.
const THUNDERBOLT = '10f7ee:Skyrim.esm';
yes('Thunderbolt is a staff spell and a tome teaches it',
    !!SPELLS[THUNDERBOLT] && SPELLS[THUNDERBOLT].name === 'Thunderbolt' && SPELLS[THUNDERBOLT].tomes.length > 0);
const thunderRow = staffRows.map(function (k) { return TABLE[k]; })
  .filter(function (r) { return r.spell === THUNDERBOLT; })[0];
yes('the Staff of Thunderbolts row binds Thunderbolt', !!thunderRow && thunderRow.name === 'Staff of Thunderbolts');
const openStaves = withSpell.filter(function (k) { return TABLE[k].open === true; });
yes('ISSUE DONE WHEN: staff recipes are open now that a tome teaches their spell (' + openStaves.length + ')',
    openStaves.length > 0 && openStaves.every(function (k) { return (SPELLS[TABLE[k].spell].tomes || []).length > 0; }));
yes('and a staff whose spell no tome teaches stays closed',
    withSpell.filter(function (k) { return (SPELLS[TABLE[k].spell].tomes || []).length === 0; })
      .every(function (k) { return TABLE[k].open === false; }));

// The build's own record agrees: the Bladebinder is out of HALVES_NOBODY_CAN_START.
const buildSrc = fs.readFileSync(path.join(REPO, 'scripts', 'dev', 'Build-RecipeTable.ps1'), 'utf8');
const knob = /\$HALVES_NOBODY_CAN_START = \[ordered\]@\{([\s\S]*?)\n\}/.exec(buildSrc);
yes('Build-RecipeTable no longer names the Bladebinder in HALVES_NOBODY_CAN_START',
    !!knob && knob[1].indexOf('Enchanter/Bladebinder') === -1);
let recipesJson = null;
try { recipesJson = JSON.parse(fs.readFileSync(path.join(REPO, 'game', 'data', 'recipes.json'), 'utf8')); } catch (e) { recipesJson = null; }
const bb = recipesJson && recipesJson.halves && recipesJson.halves['Enchanter/Bladebinder'];
yes('recipes.json counts Bladebinder rows a new Enchanter can reach (' + (bb ? bb.canBeMadeOnDayOne : '?') + ')',
    !!bb && bb.canBeMadeOnDayOne > 0 && !bb.nothingToMakeOnDayOne);
const thunderJson = recipesJson && recipesJson.recipes && recipesJson.recipes['17773:Dragonborn.esm'];
const thunderNeed = thunderJson && (thunderJson.needs || [])[0];
yes('recipes.json says which record the HasSpell names and which tomes teach it',
    !!thunderNeed && thunderNeed.ofDesc === THUNDERBOLT && Array.isArray(thunderNeed.taughtBy) &&
    thunderNeed.taughtBy.length > 0);

// ------------------------------------------------- B. learning from a tome --

const ENCH = 0xff000011;
const WARD = 0xff000012;
const SMITH = 0xff000013;
const NOBODY = 0xff000014;
const TOME = SPELLS[THUNDERBOLT] ? SPELLS[THUNDERBOLT].tomes[0] : 'none:None.esp';
{
  const srv = server(store0);
  make(srv, ENCH, 'miner', 'enchanter', 'bladebinder', 'master');
  const before = srv.C.stateOf(ENCH);
  yes('a new Enchanter knows no staff spell', srv.S.known(before).length === 0);

  const back = srv.read(ENCH, TOME);
  yes('reading the tome is never refused: the handler returns nothing, so the engine teaches the spell and spends the tome',
      back === undefined);
  const after = srv.C.stateOf(ENCH);
  yes('the Enchanter now has Thunderbolt recorded for staves', srv.S.knows(after, THUNDERBOLT));
  const chat = srv.said.filter(function (s) { return s.id === ENCH && s.how === 'chat'; });
  yes('and is told in chat, by the spell\'s name, that it can go into a staff now',
      chat.length === 1 && chat[0].text.indexOf('Thunderbolt') !== -1 && /staff/.test(chat[0].text));
  yes('the line has no em dash and no word player',
      chat.length === 1 && chat[0].text.indexOf('—') === -1 && !/player/i.test(chat[0].text));

  srv.said.length = 0;
  srv.read(ENCH, TOME);
  yes('reading it again records nothing twice and says nothing',
      srv.S.known(srv.C.stateOf(ENCH)).length === 1 && srv.said.length === 0);

  // A Wardweaver has the Bladebinder's novice as the sister half, so may make
  // novice staves and so learns their spells.
  make(srv, WARD, 'miner', 'enchanter', 'wardweaver');
  srv.read(WARD, TOME);
  yes('a Wardweaver, who makes novice staves as the sister half, learns it too',
      srv.S.knows(srv.C.stateOf(WARD), THUNDERBOLT));
}

// ------------------------------------------------ D. anybody else reading --
{
  const srv = server(store0);
  make(srv, SMITH, 'miner', 'smith', 'edgewright', 'master');
  srv.said.length = 0;
  const back = srv.read(SMITH, TOME);
  yes('a Smith reading the tome gets the normal effect only: not refused', back === undefined);
  yes('  nothing recorded', srv.S.known(srv.C.stateOf(SMITH)).length === 0);
  yes('  and nothing said', srv.said.length === 0);

  make(srv, NOBODY, 'miner', null);
  srv.read(NOBODY, TOME);
  yes('somebody with no profession yet: nothing recorded, nothing said',
      srv.S.known(srv.C.stateOf(NOBODY)).length === 0 && srv.said.length === 0);

  srv.read(ENCH, '12345:Skyrim.esm');
  yes('a book that is not a tome of a staff spell: nothing said, nothing changed',
      srv.said.length === 0 && srv.S.known(srv.C.stateOf(ENCH)).length === 1);
}

// -------------------------------------------- C. the staff gate, and E. a restart --
{
  // A restart: a second server over the same store and nothing else.
  const srv = server(JSON.parse(JSON.stringify(store0)));
  yes('AFTER A RESTART the Enchanter still has Thunderbolt recorded, out of the character store',
      srv.S.knows(srv.C.stateOf(ENCH), THUNDERBOLT));

  const ok = srv.craft(ENCH, thunderRow);
  yes('a master Bladebinder who learned Thunderbolt may make the Staff of Thunderbolts, and the work is credited',
      !ok.refusal && ok.credit === 'bladebinder');

  const other = withSpell.map(function (k) { return TABLE[k]; }).filter(function (r) {
    return r.spell !== THUNDERBOLT && (SPELLS[r.spell].tomes || []).length > 0;
  })[0];
  const no = srv.craft(ENCH, other);
  yes('a staff whose spell they have not learned is refused', !!no.refusal);
  yes('  and the refusal names the spell and says to read its tome',
      !!no.refusal && no.refusal.indexOf(SPELLS[other.spell].name) !== -1 && /spell tome/.test(no.refusal));
  yes('  with no em dash and no word player',
      !!no.refusal && no.refusal.indexOf('—') === -1 && !/player/i.test(no.refusal));

  if (untaught.length) {
    const closed = withSpell.map(function (k) { return TABLE[k]; })
      .filter(function (r) { return r.spell === untaught[0]; })[0];
    const n = srv.craft(ENCH, closed);
    yes('a staff whose spell no tome teaches is refused and says nobody can learn it here yet',
        !!n.refusal && /no spell tome here teaches it/.test(n.refusal));
  }

  // The spell known some other way does not open a staff: only the record does.
  const fresh = 0xff000015;
  make(srv, fresh, 'miner', 'enchanter', 'bladebinder', 'master');
  const s = srv.C.stateOf(fresh);
  s.spells = { points: 0, known: ['Thunderbolt'] };
  srv.C.writeState(fresh, s);
  yes('a spell in the mage book but not learned from a tome does not open the staff',
      !!srv.craft(fresh, thunderRow).refusal);

  // The staff gate asks after rank and half, so the old answers stand.
  const smith = srv.craft(SMITH, thunderRow);
  yes('a Smith is still refused as a Smith, not told about tomes',
      !!smith.refusal && !/spell tome/.test(smith.refusal));
  const low = 0xff000016;
  make(srv, low, 'miner', 'enchanter', 'bladebinder', 'novice');
  const lowRow = withSpell.map(function (k) { return TABLE[k]; }).filter(function (r) {
    return r.rank !== 'novice' && r.spell === THUNDERBOLT;
  })[0] || null;
  if (lowRow) {
    const lr = srv.craft(low, lowRow);
    yes('a novice Bladebinder at a higher staff hears about rank first', !!lr.refusal && /Rank comes from/.test(lr.refusal));
  }
  const rowless = srv.craft(ENCH, { name: 'Iron Dagger', half: 'Bladebinder', owner: 'Enchanter', rank: 'novice' });
  yes('a row with no spell is untouched by the staff gate', !rowless.refusal);
}

// ------------------------------------------------------- the handler itself --
{
  const lines = src.split('\n').filter(function (l) { return /^mp\.onReadBook\s*=/.test(l); });
  yes('mp.onReadBook is registered once, through guard under its own name',
      lines.length === 1 && lines[0].indexOf("guard('onReadBook', function") !== -1);
  const body = take("mp.onReadBook = guard('onReadBook', function", '\n});');
  yes('and it never returns false, so no book is ever refused',
      !!body && !/\breturn\s+false\b/.test(body));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
