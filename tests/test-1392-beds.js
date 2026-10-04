// test-1392-beds.js
//
// #1392. A holder sets the night's price, and /rest finds a bed.
//
// docs/systems/property.md, "What a home is for", and docs/systems/exhaustion.md,
// "Where you rest". /bed 20 at the building sets one night's gold, /bed - makes
// a night free for the people the holder allows and sells it to nobody else,
// /bed alone says the price. The gold is moved from the sleeper's pack to the
// holder's, never made. /rest bed counts only at a real bed the person may use,
// found by the bed the server saw them press and how far they stand from it.
// Once the night is paid it is the inn's 50; a bed you hold or were allowed is
// 80; a bedroll is the campfire's 35.
//
// The done-when: saying the word in the street does not count as a bed, and
// the holder receives the gold they set.
//
// This runs the REAL property block and the REAL needs block out of
// gamemode.js over a stand-in mp, a clock turned by hand and a temp folder,
// so the book can be read back after a pretend restart. The /rest branch of
// the chat commands is lifted and run as it stands.
//
// Read only, apart from its own temp folder.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const SRC = process.env.GM || path.join(__dirname, '..', 'game', 'gamemode.js');
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

const propBlock = slice('// ==== thornswood property ====', '// ==== end thornswood property ====');
const needsA = '// ==== thornswood needs: hunger, thirst and exhaustion ====';
const needsBlock = slice(needsA, '// ==== end thornswood needs ====');
const restBranch = slice("      if (word === '/rest') {\n", "\n      }\n");
yes('the property block, the needs block and the /rest branch are in the gamemode',
    !!propBlock && !!needsBlock && !!restBranch);
if (!propBlock || !needsBlock || !restBranch) { done(); }

// ------------------------------------------------------------ the wiring --

const onAct = slice("mp.onActivate = guard('onActivate', function (refrId, casterRefrId) {", '\n});\n');
yes('onActivate hands every press to the beds, with the bed and its base',
    !!onAct && /beds\.touched\(casterRefrId, refrId, baseDesc\)/.test(onAct));
yes('and does not refuse the press for it, so the engine still lays them down',
    !!onAct && /try \{ beds\.touched\(casterRefrId, refrId, baseDesc\); \} catch \(e\) \{ \}/.test(onAct));
function arrayOf(name) {
  const m = new RegExp('^const ' + name + ' = (\\[[\\s\\S]*?\\]);$', 'm').exec(gm);
  if (!m) { return null; }
  try { return new Function('return ' + m[1])(); } catch (e) { return null; }
}
const WORDS = arrayOf('WORDS');
const PLAYER_WORDS = arrayOf('PLAYER_WORDS');
yes('/bed is a word the server answers, and everybody is told of it',
    !!WORDS && WORDS.indexOf('/bed') !== -1 && !!PLAYER_WORDS && PLAYER_WORDS.indexOf('/bed') !== -1);
yes('the character block hands /bed to the property block with the other property words',
    /word === '\/rent' \|\| word === '\/bed' \|\|/.test(gm));
yes('the property block answers /bed',
    /if \(word === '\/bed'\) \{ return bedCmd\(parts, actorId, profileId, toProfile\); \}/.test(propBlock));
yes('/rest bed, /rest inn and /rest bedroll go to the beds, never straight to the meter',
    /where === 'bed' \|\| where === 'inn' \|\| where === 'bedroll'/.test(restBranch) &&
    /beds\.rest\(actorId/.test(restBranch));

// ------------------------------------------------------------ the world --

const HOUR = 3600000;
const clock = { t: Date.UTC(2026, 9, 4, 20, 0, 0) };
class FakeDate extends Date { static now() { return clock.t; } }

const INN = '1a2b3:Skyrim.esm';
const HOME = '16778:Skyrim.esm';
const HALL = '165a3:Skyrim.esm';
const TUNDRA = '3c:Skyrim.esm';
const BUILDING_NAME = {};
BUILDING_NAME[INN] = 'The Bannered Mare';
BUILDING_NAME[HOME] = 'Honeyside';
BUILDING_NAME[HALL] = 'Dragonsreach';
const BUILDING_BY_DOOR = { '1001:Skyrim.esm': INN, '1002:Skyrim.esm': HOME, '1003:Skyrim.esm': HALL };

const ids = {};
let nextId = 0x05000000;
function idOf(desc) {
  desc = String(desc || '');
  if (!desc) { return 0; }
  if (!ids[desc]) {
    const m = /^([0-9a-f]+):Skyrim\.esm$/i.exec(desc);
    ids[desc] = m ? parseInt(m[1], 16) : (nextId++);
  }
  return ids[desc];
}
function bytes(s) { const out = []; for (let i = 0; i < s.length; i++) { out.push(s.charCodeAt(i)); } out.push(0); return out; }

const BED = 'b001:Skyrim.esm';        // CommonBedDouble01
const BED_FIELDS = 'b006:Skyrim.esm'; // an editor id only in the EDID field
const ROLL = 'b002:Skyrim.esm';       // BedRoll01
const CHAIR = 'b003:Skyrim.esm';      // CommonChair01, a FURN that is not a bed
const SIDE = 'b004:Skyrim.esm';       // a FURN with bed in its name that is not one
const CHEST = 'b005:Skyrim.esm';      // a container called a bed chest
const RECORDS = {};
RECORDS[idOf(BED)] = { record: { type: 'FURN', editorId: 'CommonBedDouble01', fields: [] } };
RECORDS[idOf(BED_FIELDS)] = { record: { type: 'FURN', fields: [{ type: 'EDID', data: bytes('NobleBedSingle01') }] } };
RECORDS[idOf(ROLL)] = { record: { type: 'FURN', editorId: 'BedRoll01', fields: [] } };
RECORDS[idOf(CHAIR)] = { record: { type: 'FURN', editorId: 'CommonChair01', fields: [] } };
RECORDS[idOf(SIDE)] = { record: { type: 'FURN', editorId: 'NobleBedsideLean01', fields: [] } };
RECORDS[idOf(CHEST)] = { record: { type: 'CONT', editorId: 'NobleBedChest01', fields: [] } };

const GOLD = 0x0000000f;
// People: actor, profile, name.
const HULDA = { a: 0xff000101, pid: 101, name: 'Hulda' };   // holds the inn
const ALICE = { a: 0xff000202, pid: 202, name: 'Alice' };   // holds Honeyside
const BOB = { a: 0xff000303, pid: 303, name: 'Bob' };       // a stranger with coin
const CAROL = { a: 0xff000404, pid: 404, name: 'Carol' };   // carries a key to the inn
const DAVE = { a: 0xff000505, pid: 505, name: 'Dave' };     // a stranger with 5 gold
const EVE = { a: 0xff000606, pid: 606, name: 'Eve' };       // another stranger
const PEOPLE = [HULDA, ALICE, BOB, CAROL, DAVE, EVE];

// Placed things: the bed, its base, its cell and where it stands.
const INN_BED = 0x00a00001, INN_BED2 = 0x00a00002, INN_ROLL = 0x00a00003, HOME_BED = 0x00a00004;
const HALL_BED = 0x00a00005, ROAD_ROLL = 0x00a00006, ROAD_BED = 0x00a00007, INN_CHAIR = 0x00a00008;

function world(keyDesc) {
  const refs = {};
  function place(id, base, cell, pos) { refs[id] = { baseDesc: base, worldOrCellDesc: cell, pos: pos }; }
  place(INN_BED, BED, INN, [0, 0, 0]);
  place(INN_BED2, BED_FIELDS, INN, [1000, 0, 0]);
  place(INN_ROLL, ROLL, INN, [0, 1000, 0]);
  place(HOME_BED, BED, HOME, [0, 0, 0]);
  place(HALL_BED, BED, HALL, [0, 0, 0]);
  place(ROAD_ROLL, ROLL, TUNDRA, [50000, 50000, 0]);
  place(ROAD_BED, BED, TUNDRA, [60000, 50000, 0]);
  place(INN_CHAIR, CHAIR, INN, [40, 0, 0]);
  const gold = { 101: 0, 202: 0, 303: 100, 404: 0, 505: 5, 606: 50 };
  PEOPLE.forEach(function (p) {
    const entries = [];
    if (gold[p.pid]) { entries.push({ baseId: GOLD, count: gold[p.pid] }); }
    if (p === CAROL) { entries.push({ baseId: idOf(keyDesc), count: 1, name: 'Key to The Bannered Mare' }); }
    refs[p.a] = { profileId: p.pid, appearance: { name: p.name }, worldOrCellDesc: TUNDRA,
                  pos: [90000, 90000, 0], inventory: { entries: entries } };
  });
  return refs;
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ts-1392-beds-'));
fs.writeFileSync(path.join(dir, 'server-settings.json'), JSON.stringify({ dataDir: 'data', privDir: 'private' }));
fs.mkdirSync(path.join(dir, 'private'));
fs.writeFileSync(path.join(dir, 'private', 'property.json'), JSON.stringify({ claims: {
  [INN]: { by: HULDA.pid, name: 'Hulda', at: clock.t, touched: clock.t },
  [HOME]: { by: ALICE.pid, name: 'Alice', at: clock.t, touched: clock.t }
} }));
const KEY_DESC = (/var KEY = '([^']+:Thornswood-Content\.esp)';/.exec(propBlock) || [])[1];
yes('the key record is read out of the property block', !!KEY_DESC);

let refs = world(KEY_DESC);
let online = PEOPLE.map(function (p) { return p.a; });
let told = [];
let ticks = [];

function needsRig() {
  const store = {};
  const g = {};
  const fake = {
    getOnlinePlayers: function () { return online.slice(); },
    makeProperty: function () { },
    get: function (id, key) {
      if (key === 'worldOrCellDesc') { return refs[id] ? refs[id].worldOrCellDesc : ''; }
      return store[id];
    },
    set: function (id, key, v) { store[id] = v; }
  };
  const fn = new Function('globalThis', 'mp', 'Date', 'console', 'setInterval', 'clearInterval',
    'guard', 'notify', 'say', needsBlock + '\nreturn globalThis.__thornswoodNeeds;');
  return fn(g, fake, FakeDate, { log: function () { } }, function () { return 0; }, function () { },
            function (n, f) { return f; }, function () { }, function () { });
}

function boot(needs) {
  const mp = {
    makeProperty: function () { },
    get: function (id, key) {
      if (id === 0 && key === 'onlinePlayers') { return online.slice(); }
      if (!refs[id]) { throw new Error('no reference ' + id); }
      const v = refs[id][key];
      return (v && typeof v === 'object') ? JSON.parse(JSON.stringify(v)) : v;
    },
    set: function (id, key, v) {
      if (!refs[id]) { refs[id] = {}; }
      refs[id][key] = JSON.parse(JSON.stringify(v));
    },
    getDescFromId: function (id) { return id.toString(16) + ':Skyrim.esm'; },
    lookupEspmRecordById: function (id) { return RECORDS[id] || null; }
  };
  const box = {
    console: { log: function () { } }, require: require, mp: mp, Date: FakeDate,
    BUILDING_BY_DOOR: BUILDING_BY_DOOR, BUILDING_NAME: BUILDING_NAME, WAY_OUT: {},
    idOf: idOf,
    notify: function () { },
    say: function (id, text) { told.push({ id: id, text: text }); },
    guard: function (n, f) { return f; },
    setInterval: function (f, ms) { ticks.push({ f: f, ms: ms }); return ticks.length; },
    clearInterval: function () { },
    log: function () { },
    __thornswoodNeeds: needs
  };
  box.globalThis = box;
  const was = process.cwd();
  process.chdir(dir);
  try { vm.runInNewContext(propBlock, box, { filename: 'gamemode.js property' }); }
  finally { process.chdir(was); }
  return box;
}
function inDir(f) {
  const was = process.cwd();
  process.chdir(dir);
  try { return f(); } finally { process.chdir(was); }
}

let needs = needsRig();
let box = boot(needs);
// Always the beds and the register of the server running now: a restart
// below boots a second one.
const beds = {
  kindOf: function (b) { return box.__thornswoodBeds.kindOf(b); },
  book: function () { return box.__thornswoodBeds.book(); }
};
const prop = {
  command: function () { return box.__thornswoodProperty.command.apply(null, arguments); },
  claims: function () { return box.__thornswoodProperty.claims(); }
};
const first = box.__thornswoodBeds;
yes('the property block publishes the beds',
    !!first && typeof first.rest === 'function' && typeof first.command === 'function' && !!box.__thornswoodProperty);
if (!first || !box.__thornswoodProperty) { done(); }
beds.NIGHT_MS = first.NIGHT_MS;
yes('the beds watch on a timer of their own', ticks.some(function (t) { return t.ms === first.BED_EVERY_MS; }));

function standAt(p, cell, pos) { refs[p.a].worldOrCellDesc = cell; refs[p.a].pos = pos.slice(); }
function standBy(p, bedRef) { standAt(p, refs[bedRef].worldOrCellDesc, refs[bedRef].pos); }
function press(p, ref) { box.__thornswoodBeds.touched(p.a, ref, refs[ref].baseDesc); }
function rest(p, word) {
  const out = [];
  const run = new Function('globalThis', 'needs', 'parts', 'actorId', 'profileId', 'toProfile',
    'var word = "/rest";\n' + restBranch + '\nreturn false;');
  inDir(function () {
    run(box, needs, ['/rest'].concat(word ? [word] : []), p.a, p.pid, function (pid, m) { out.push(m); });
  });
  return out.join('\n');
}
function bed(p, arg) {
  const out = [];
  inDir(function () {
    prop.command('/bed', ['/bed'].concat(arg === undefined ? [] : [arg]), p.a, p.pid,
                 function (pid, m) { out.push(m); });
  });
  return out.join('\n');
}
function tick() { inDir(function () { box.__thornswoodBeds.tick(); }); }
function goldOf(p) {
  return (refs[p.a].inventory.entries || []).reduce(function (s, e) { return s + (e.baseId === GOLD ? e.count : 0); }, 0);
}
function allGold() { return PEOPLE.reduce(function (s, p) { return s + goldOf(p); }, 0); }
function restingOf(p) { return needs.settle(p.a).resting; }
function lastTold(p) {
  for (let i = told.length - 1; i >= 0; i--) { if (told[i].id === p.a) { return told[i].text; } }
  return '';
}
const every = [];
function heard(s) { every.push(s); return s; }

// --------------------------------------------------------------- a bed --

{
  yes('B1 a double bed is a bed, read off its editor id', beds.kindOf(BED) === 'bed');
  yes('B1 an editor id only in the EDID field still reads', beds.kindOf(BED_FIELDS) === 'bed');
  yes('B1 a bedroll is a bedroll', beds.kindOf(ROLL) === 'roll');
  yes('B1 a chair is not a bed', beds.kindOf(CHAIR) === '');
  yes('B1 a bedside piece is not a bed', beds.kindOf(SIDE) === '');
  yes('B1 a container is not a bed whatever it is called', beds.kindOf(CHEST) === '');
  yes('B1 a base the engine knows nothing of is not a bed', beds.kindOf('ffff:Skyrim.esm') === '');
}

// ----------------------------------------------------- THE DONE-WHEN, 1 --

{
  // Bob in the street, nothing pressed.
  standAt(BOB, TUNDRA, [90000, 90000, 0]);
  const said = heard(rest(BOB, 'bed'));
  yes('B2 /rest bed said in the street is refused (got "' + said + '")',
      /no bed here/i.test(said) && restingOf(BOB) === '');
  yes('B2 and /rest inn in the street is refused the same', /no bed here/i.test(heard(rest(BOB, 'inn'))) && restingOf(BOB) === '');
  yes('B2 and /rest bedroll in the street too', /no bed here/i.test(heard(rest(BOB, 'bedroll'))) && restingOf(BOB) === '');

  // A chair pressed is not a bed pressed.
  standBy(BOB, INN_CHAIR);
  press(BOB, INN_CHAIR);
  yes('B2 a chair pressed is not a bed', /no bed here/i.test(heard(rest(BOB, 'bed'))) && restingOf(BOB) === '');

  // A real bed pressed, then walked away from.
  standBy(HULDA, INN_BED);
  press(HULDA, INN_BED);
  standAt(HULDA, TUNDRA, [90000, 90000, 0]);
  yes('B2 a bed pressed and then walked away from does not count',
      /no bed here/i.test(heard(rest(HULDA, 'bed'))) && restingOf(HULDA) === '');
}

// ------------------------------------------------- the holder's own bed --

{
  standBy(HULDA, INN_BED);
  press(HULDA, INN_BED);
  const said = heard(rest(HULDA, 'bed'));
  yes('B3 the holder lies down in her own bed and rests (got "' + said + '")',
      restingOf(HULDA) === 'bed' && /rest/i.test(said));
  yes('B3 that is the bed rate on the page, 80 an hour', needs.NEEDS.recover.bed === 80);
  yes('B3 and it cost her nothing', goldOf(HULDA) === 0);
  rest(HULDA, 'up');
  heard(rest(HULDA, 'inn'));
  yes('B3 /rest inn in her own bed is still her own bed: the server says which, not the word',
      restingOf(HULDA) === 'bed');
  rest(HULDA, 'up');
}

// ---------------------------------------------------------- no price set --

{
  standBy(BOB, INN_BED);
  press(BOB, INN_BED);
  const said = heard(rest(BOB, 'bed'));
  yes('B4 a stranger in a bed with no price set is refused (got "' + said + '")',
      /not for sale/.test(said) && restingOf(BOB) === '' && goldOf(BOB) === 100);
  const asked = heard(bed(BOB));
  yes('B4 /bed says nights there are not for sale (got "' + asked + '")', /not for sale/.test(asked));
  const tried = heard(bed(BOB, '5'));
  yes('B4 somebody who does not hold it cannot set the price (got "' + tried + '")',
      /Only whoever holds The Bannered Mare/.test(tried) && /not for sale/.test(bed(BOB)));
}

// ------------------------------------------------------ the holder's price --

{
  standAt(HULDA, INN, [300, 300, 0]);
  ['abc', '2.5', '0', '-5'].forEach(function (bad) {
    const said = heard(bed(HULDA, bad));
    yes('B5 /bed ' + bad + ' is refused and sets nothing', /whole number/.test(said) && /not for sale/.test(bed(HULDA)));
  });
  const set = heard(bed(HULDA, '20'));
  yes('B5 /bed 20 standing in the inn sets one night at 20 (got "' + set + '")', /20 gold/.test(set));
  yes('B5 /bed then says 20 to the holder', /is 20 gold, and it comes to you/.test(heard(bed(HULDA))));
  yes('B5 and 20, handed to Hulda, to anybody else', /is 20 gold, handed to Hulda/.test(heard(bed(BOB))));
  standAt(BOB, TUNDRA, [90000, 90000, 0]);
  yes('B5 /bed out in the street asks for the building', /Stand in the building/.test(heard(bed(BOB))));
  // At the door, from outside, the door just opened is the building.
  refs[BOB.a].thornswoodDoor = { door: '1001:Skyrim.esm', at: clock.t, ground: null };
  yes('B5 /bed at the door just opened answers for that building', /is 20 gold, handed to Hulda/.test(bed(BOB)));
  delete refs[BOB.a].thornswoodDoor;
}

// ------------------------------------------------- THE DONE-WHEN, 2: paying --

{
  const before = allGold();
  standBy(BOB, INN_BED);
  press(BOB, INN_BED);
  const offer = heard(rest(BOB, 'bed'));
  yes('B6 lying down tells the price and takes nothing yet (got "' + offer + '")',
      /20 gold, handed to Hulda/.test(offer) && /again within a minute/.test(offer) &&
      goldOf(BOB) === 100 && goldOf(HULDA) === 0 && restingOf(BOB) === '');
  clock.t += 20000;
  const paid = heard(rest(BOB, 'bed'));
  yes('B6 saying it again pays (got "' + paid + '")', /You pay 20 gold to Hulda/.test(paid));
  yes('B6 the 20 left Bob\'s pack', goldOf(BOB) === 80);
  yes('B6 and the holder receives the gold she set', goldOf(HULDA) === 20);
  yes('B6 no gold was made or lost', allGold() === before);
  yes('B6 and she is told who paid', /Bob paid you 20 gold for a night at The Bannered Mare/.test(lastTold(HULDA)));
  yes('B6 Bob rests at the inn room\'s rate, 50 an hour', restingOf(BOB) === 'inn' && needs.NEEDS.recover.inn === 50);
  yes('B6 /bed says his night is paid', /Your night there is paid/.test(bed(BOB)));
  // Up and down again the same night: no second charge.
  rest(BOB, 'up');
  clock.t += HOUR;
  standBy(BOB, INN_BED2);
  press(BOB, INN_BED2);
  const again = heard(rest(BOB, 'bed'));
  yes('B6 another bed in the same inn the same night costs nothing more (got "' + again + '")',
      restingOf(BOB) === 'inn' && goldOf(BOB) === 80 && goldOf(HULDA) === 20);
}

// ------------------------------------------------- the offer, and no coin --

{
  standBy(DAVE, INN_BED);
  press(DAVE, INN_BED);
  heard(rest(DAVE, 'bed'));
  clock.t += 61000;
  const stale = heard(rest(DAVE, 'bed'));
  yes('B7 a second /rest bed after the minute is the price again, not a payment (got "' + stale + '")',
      /again within a minute/.test(stale) && goldOf(DAVE) === 5);
  const poor = heard(rest(DAVE, 'bed'));
  yes('B7 somebody without the gold is refused and keeps what they have (got "' + poor + '")',
      /not carrying that much/.test(poor) && goldOf(DAVE) === 5 && goldOf(HULDA) === 20 &&
      restingOf(DAVE) === '');
}

// ------------------------------------------------- allowed: a key or a deed --

{
  standBy(CAROL, INN_BED);
  press(CAROL, INN_BED);
  const said = heard(rest(CAROL, 'bed'));
  yes('B8 somebody carrying the key sleeps there free, at the bed rate (got "' + said + '")',
      restingOf(CAROL) === 'bed' && goldOf(CAROL) === 0 && !/gold/.test(said));
  yes('B8 /bed tells her she is allowed', /You are allowed, so yours is free/.test(bed(CAROL)));
  rest(CAROL, 'up');
}

// ------------------------------------------------------------- /bed - --

{
  standAt(HULDA, INN, [300, 300, 0]);
  const said = heard(bed(HULDA, '-'));
  yes('B9 /bed - makes a night free for the people she allows (got "' + said + '")',
      /free for the people you allow/.test(said));
  standBy(EVE, INN_BED);
  press(EVE, INN_BED);
  yes('B9 and sells it to nobody else', /not for sale/.test(heard(rest(EVE, 'bed'))) && goldOf(EVE) === 50);
  standBy(CAROL, INN_BED);
  press(CAROL, INN_BED);
  heard(rest(CAROL, 'bed'));
  yes('B9 the key holder still sleeps free', restingOf(CAROL) === 'bed');
  rest(CAROL, 'up');
  // Bob's night is still paid, so he still rests.
  tick();
  yes('B9 a night already paid stays paid', restingOf(BOB) === 'inn');
}

// --------------------------------------------------- while the place is true --

{
  standAt(BOB, TUNDRA, [90000, 90000, 0]);
  tick();
  yes('B10 walking away from the bed stops the rest', restingOf(BOB) === '');
  yes('B10 and he is told why', /left the bed/.test(lastTold(BOB)));

  // Back in, the night still good, then it runs out.
  standBy(BOB, INN_BED);
  press(BOB, INN_BED);
  heard(rest(BOB, 'bed'));
  yes('B10 back in the bed with the night still paid', restingOf(BOB) === 'inn');
  clock.t += beds.NIGHT_MS;
  tick();
  yes('B10 when the night runs out the rest stops', restingOf(BOB) === '');
  yes('B10 and he is told the night is over', /night at The Bannered Mare is over/.test(heard(lastTold(BOB))));

  // A rest somewhere else is never taken off by the bed watch.
  standBy(CAROL, INN_BED);
  press(CAROL, INN_BED);
  heard(rest(CAROL, 'bed'));
  rest(CAROL, 'sit');
  standAt(CAROL, TUNDRA, [90000, 90000, 0]);
  tick();
  yes('B10 /rest sit after a bed is left alone by the bed watch', restingOf(CAROL) === 'sit');
  rest(CAROL, 'up');
  // /rest with a word that means nothing does not let go of a bed.
  standBy(CAROL, INN_BED);
  press(CAROL, INN_BED);
  heard(rest(CAROL, 'bed'));
  rest(CAROL, 'cloud');
  standAt(CAROL, TUNDRA, [90000, 90000, 0]);
  tick();
  yes('B10 an unknown word does not leave a bed rest unwatched', restingOf(CAROL) === '');
}

// --------------------------------------------------- the holder not in the world --

{
  standAt(HULDA, INN, [300, 300, 0]);
  bed(HULDA, '20');
  online = online.filter(function (a) { return a !== HULDA.a; });
  const before = allGold();
  standBy(EVE, INN_BED);
  press(EVE, INN_BED);
  rest(EVE, 'bed');
  const paid = heard(rest(EVE, 'bed'));
  yes('B11 a night can be paid while the holder is away (got "' + paid + '")',
      /You pay 20 gold to Hulda/.test(paid) && goldOf(EVE) === 30 && restingOf(EVE) === 'inn');
  yes('B11 the gold is kept for her, not lost and not in her pack yet',
      goldOf(HULDA) === 20 && beds.book().takings[HULDA.pid] === 20 && allGold() === before - 20);
  const file = JSON.parse(fs.readFileSync(path.join(dir, 'private', 'beds.json'), 'utf8'));
  yes('B11 and it is written down in beds.json beside the register', file.takings[HULDA.pid] === 20);
}

// ---------------------------------------------------------- a restart --

{
  needs = needsRig();
  // The meters live on the character, so a restart keeps Eve's.
  told = [];
  ticks = [];
  const eveWas = 'inn';
  needs.resting(EVE.a, eveWas);
  const firstBox = box;
  box = boot(needs);
  const b2 = box.__thornswoodBeds;
  yes('B12 the restart is a second server, not the first one still answering',
      b2 !== firstBox.__thornswoodBeds && box.__thornswoodProperty !== firstBox.__thornswoodProperty);
  yes('B12 after a restart the price is still 20', /is 20 gold, handed to Hulda/.test(bed(BOB)));
  yes('B12 Eve\'s night is still paid', b2.book().nights[INN] && b2.book().nights[INN][EVE.pid] > 0);
  yes('B12 Hulda\'s kept gold is still kept', b2.book().takings[HULDA.pid] === 20);

  // Eve was lying down when it went; the server did not see her lie down in
  // this run, so she gets up and lies down again.
  tick();
  yes('B12 somebody resting in a bed nobody saw them lie down in gets up', restingOf(EVE) === '');
  standBy(EVE, INN_BED);
  press(EVE, INN_BED);
  heard(rest(EVE, 'bed'));
  yes('B12 lying down again costs nothing, the night is paid', restingOf(EVE) === 'inn' && goldOf(EVE) === 30);

  // Hulda comes back into the world and is handed what was kept.
  const before = allGold();
  online.push(HULDA.a);
  tick();
  yes('B12 the holder coming in is handed the gold kept for her', goldOf(HULDA) === 40);
  yes('B12 the book no longer holds it', !b2.book().takings[HULDA.pid]);
  yes('B12 no gold was made: what was kept is what arrived', allGold() === before + 20);
  yes('B12 and she is told', /20 gold was paid for nights in your beds/.test(heard(lastTold(HULDA))));
  tick();
  yes('B12 and it is not handed twice', goldOf(HULDA) === 40);
  rest(EVE, 'up');
}

// ------------------------------------------------- a bed nobody holds, and bedrolls --

{
  standBy(BOB, HALL_BED);
  press(BOB, HALL_BED);
  const hall = heard(rest(BOB, 'bed'));
  yes('B13 a bed in a building nobody holds is nobody\'s to lend (got "' + hall + '")',
      /Nobody holds Dragonsreach/.test(hall) && restingOf(BOB) === '');
  standBy(BOB, ROAD_BED);
  press(BOB, ROAD_BED);
  yes('B13 a bed out on the road is nobody\'s either', /nobody's to lend/.test(heard(rest(BOB, 'bed'))) && restingOf(BOB) === '');
  standBy(BOB, ROAD_ROLL);
  press(BOB, ROAD_ROLL);
  heard(rest(BOB, 'bed'));
  yes('B13 a bedroll on the road is the campfire\'s 35', restingOf(BOB) === 'bedroll' &&
      needs.NEEDS.recover.bedroll === 35 && needs.NEEDS.recover.campfire === 35);
  rest(BOB, 'up');
  standBy(HULDA, INN_ROLL);
  press(HULDA, INN_ROLL);
  heard(rest(HULDA, 'bed'));
  yes('B13 a bedroll in her own inn is still a bedroll', restingOf(HULDA) === 'bedroll');
  rest(HULDA, 'up');
}

// ------------------------------------------------- a building changing hands --

{
  // Alice sets a price on Honeyside, then the claim moves to Bob.
  standAt(ALICE, HOME, [0, 0, 0]);
  standAt(BOB, HOME, [100, 0, 0]);
  bed(ALICE, '15');
  yes('B14 Alice sets a night at Honeyside', /is 15 gold, handed to Alice/.test(heard(bed(BOB))));
  prop.claims()[HOME] = { by: BOB.pid, name: 'Bob', at: clock.t, touched: clock.t, locked: false };
  const after = heard(bed(ALICE));
  yes('B14 a building that changes hands does not keep the last holder\'s price (got "' + after + '")',
      /not for sale/.test(after));
  standBy(ALICE, HOME_BED);
  press(ALICE, HOME_BED);
  const was = heard(rest(ALICE, 'bed'));
  yes('B14 and Alice is no longer the holder there (got "' + was + '")', /not for sale/.test(was) && restingOf(ALICE) === '');
  standBy(BOB, HOME_BED);
  press(BOB, HOME_BED);
  heard(rest(BOB, 'bed'));
  yes('B14 the new holder sleeps in it at the bed rate', restingOf(BOB) === 'bed');
  rest(BOB, 'up');
}

// ----------------------------------------------------------- the writing --

{
  const bad = every.filter(function (s) {
    return s.indexOf(String.fromCharCode(0x2014)) !== -1 || /\bplayers?\b/i.test(s);
  });
  yes('B15 every line said keeps the writing rules (no em dash, no banned word)', every.length > 20 && bad.length === 0);
}

done();
