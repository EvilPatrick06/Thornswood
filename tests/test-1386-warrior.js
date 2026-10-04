// test-1386-warrior.js
//
// #1386. A kill's piece count is the band on the warrior page: a chicken and a
// dragon are not the same piece, a person killed by a person stays 0, and body
// loot is not a piece more. Bulwark and Berserker maneuvers use the stamina,
// lengths and waits on the page, the sister half and an outside trade get the
// novice row only, and each named maneuver does what the server can make it
// do. The numbers are read off docs/systems/professions/warrior.md and held
// against the code, so a change to either side shows here.
//
// Read only. Drives the real blocks out of gamemode.js over a fake mp.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.join(__dirname, '..');
const gm = fs.readFileSync(path.join(root, 'game', 'gamemode.js'), 'utf8').replace(/\r/g, '');
const page = fs.readFileSync(path.join(root, 'docs', 'systems', 'professions', 'warrior.md'), 'utf8').replace(/\r/g, '');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function slice(src, start, end) {
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b + end.length);
}
function cut(head) { return slice(gm, head, '\n}\n'); }

// ----------------------------------------------------------- the sources --
const progression = slice(gm, '// ==== thornswood progression ====', '// ==== end thornswood progression ====');
const maneuvers = slice(gm, '// ==== thornswood warrior maneuvers ====', '// ==== end thornswood warrior maneuvers ====');
const killTable = slice(gm, 'const WARRIOR_KILL = {', '\n};');
const kills = ['function warriorPieces(', 'function raceEdidOf(', 'function killPieces('].map(cut);
const hunts = slice(gm, 'var HUNTS_BY_BASE = {', '\n};');
const racesLine = /^const RACES = (\{.*\});$/m.exec(gm);
const onDeath = slice(gm, "mp.onDeath = guard('onDeath', function (actorId, killerId) {", '\n});');
const credit = cut('function creditWork(actorId, key, n) {');
const withManeuvers = slice(gm, '  function withManeuvers(actorId, base) {', '\n  }\n');
yes('the progression block, the maneuvers block and the kill band are in the gamemode',
  !!progression && !!maneuvers && !!killTable && kills.every(Boolean) && !!hunts && !!racesLine);
yes('mp.onDeath, creditWork and withManeuvers are in the gamemode', !!onDeath && !!credit && !!withManeuvers);
if (!(progression && maneuvers && killTable && kills.every(Boolean) && hunts && racesLine && onDeath && credit && withManeuvers)) {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(1);
}
const RACES = JSON.parse(racesLine[1]);
function raceDesc(edid) {
  for (const k in RACES.items) { if (RACES.items[k].e === edid) { return k; } }
  return null;
}

// --------------------------------------------------------- the kill band --
function killBox(mp) {
  const box = { mp: mp, console: { log: function () {} } };
  vm.createContext(box);
  vm.runInContext('const RACES = ' + racesLine[1] + ';\n' + hunts + '\n' + killTable + '\n' + kills.join('\n') +
    '\nthis.warriorPieces = warriorPieces; this.killPieces = killPieces; this.raceEdidOf = raceEdidOf;' +
    ' this.WARRIOR_KILL = WARRIOR_KILL; this.HUNTS_BY_BASE = HUNTS_BY_BASE;', box);
  return box;
}
const K = killBox({});

// The page's strength table, read off the page.
const strength = {};
page.split('\n').forEach(function (line) {
  const m = /^\| (Novice|Advanced|Expert|Master animal) \| [^|]+ \| (\d+) \|$/.exec(line);
  if (m) { strength[m[1].split(' ')[0].toLowerCase()] = Number(m[2]); }
});
yes('the page has the four strength rows', Object.keys(strength).length === 4);
yes('each hunter rank is the pieces the page gives it (' + JSON.stringify(strength) + ')',
  ['novice', 'advanced', 'expert', 'master'].every(function (r) { return K.WARRIOR_KILL.byRank[r] === strength[r]; }));

// The page's person-shaped table, read off the page, held against the race
// each word is in Skyrim.
const shaped = {};
page.split('\n').forEach(function (line) {
  const m = /^\| ([A-Za-z ,]+) \| (\d+) \|$/.exec(line);
  if (m && m[1] !== 'What died') {
    m[1].split(',').forEach(function (w) { shaped[w.trim().toLowerCase()] = Number(m[2]); });
  }
});
const RACE_OF = {
  bandit: 'NordRace', guard: 'ImperialRace', forsworn: 'BretonRace', skeleton: 'SkeletonRace',
  draugr: 'DraugrRace', falmer: 'FalmerRace', hagraven: 'HagravenRace',
  giant: 'GiantRace', 'dragon priest': 'DragonPriestRace', centurion: 'DwarvenCenturionRace',
  lurker: 'DLC2LurkerRace', dragon: 'DragonRace'
};
yes('the page names the twelve person-shaped kinds', Object.keys(shaped).length === 12 &&
  Object.keys(RACE_OF).every(function (w) { return shaped[w] > 0; }));
Object.keys(RACE_OF).forEach(function (w) {
  yes('a ' + w + ' (' + RACE_OF[w] + ') is ' + shaped[w] + ' pieces, as the page says',
    !!raceDesc(RACE_OF[w]) && K.warriorPieces('', RACE_OF[w]) === shaped[w]);
});

const chicken = '10929f:Skyrim.esm';
const karhu = '291791:WindhelmSSE.esp';
yes('the chicken and Karhu are rows on the hunter list',
  K.HUNTS_BY_BASE[chicken] && K.HUNTS_BY_BASE[chicken].rank === 'novice' &&
  K.HUNTS_BY_BASE[karhu] && K.HUNTS_BY_BASE[karhu].rank === 'master');
yes('a chicken is 1 piece', K.warriorPieces(chicken, '') === 1);
yes('Karhu uses his own row, master, so 8, though a bear is 4', K.warriorPieces(karhu, '') === 8 &&
  K.warriorPieces('', 'BearBrownRace') === 4);
yes('a base on the hunter list is its row even when the race would say more',
  K.warriorPieces(chicken, 'DragonRace') === 1);
const anyRank = function (rank) {
  for (const k in K.HUNTS_BY_BASE) { if (K.HUNTS_BY_BASE[k].rank === rank) { return k; } }
  return null;
};
yes('an advanced body on the list is 2, an expert 4, a master 8',
  K.warriorPieces(anyRank('advanced'), '') === 2 && K.warriorPieces(anyRank('expert'), '') === 4 &&
  K.warriorPieces(anyRank('master'), '') === 8);
yes('a chicken and a dragon are not the same piece', K.warriorPieces(chicken, '') !== K.warriorPieces('', 'DragonRace') &&
  K.warriorPieces('', 'DragonRace') === 16);
yes('off the list, an animal uses its kind: a sabre cat 2, a mammoth 8, a grown netch 8, a netch calf 2',
  K.warriorPieces('', 'SabreCatRace') === 2 && K.warriorPieces('', 'MammothRace') === 8 &&
  K.warriorPieces('', 'DLC2NetchRace') === 8 && K.warriorPieces('', 'DLC2NetchCalfRace') === 2);
yes('a giant frostbite spider is a spider, 2, not a giant', K.warriorPieces('', 'FrostbiteSpiderRaceGiant') === 2);
yes('a werebear and a dwarven spider are not a bear or a spider: the novice line, 1',
  K.warriorPieces('', 'DLC2WerebearBeastRace') === 1 && K.warriorPieces('', 'DwarvenSpiderRace') === 1);
yes('an atronach, which the page does not name, is 1, and so is a race nobody can read',
  K.warriorPieces('', 'AtronachFlameRace') === 1 && K.warriorPieces('', '') === 1);
yes('a vampire of the people is still the people line, 2', K.warriorPieces('', 'ImperialRaceVampire') === 2);

// The engine read: the race comes from Actor.GetRace on the dead actor.
function engine(base, raceAnswer) {
  const asked = [];
  const mp = {
    get: function (id, prop) { if (prop === 'baseDesc') { return base; } throw new Error('no ' + prop); },
    getDescFromId: function (id) { return id.toString(16); },
    callPapyrusFunction: function (type, cls, fn, self, args) {
      asked.push(cls + '.' + fn);
      if (raceAnswer instanceof Error) { throw raceAnswer; }
      return raceAnswer;
    }
  };
  const box = killBox(mp);
  return { pieces: box.killPieces(0xff000201), asked: asked };
}
{
  const dragon = engine('dragonbase:Skyrim.esm', { type: 'espm', desc: raceDesc('DragonRace') });
  yes('a body off the list asks the engine its race and a dragon is 16',
    dragon.pieces === 16 && dragon.asked.join() === 'Actor.GetRace');
  const padded = engine('x:Skyrim.esm', { type: 'espm', desc: '00' + raceDesc('DraugrRace') });
  yes('a race descriptor written with leading zeroes is still found (a draugr, 4)', padded.pieces === 4);
  const wolf = engine(chicken, { type: 'espm', desc: raceDesc('DragonRace') });
  yes('a body on the hunter list never asks the engine', wolf.pieces === 1 && wolf.asked.length === 0);
  const broken = engine('x:Skyrim.esm', new Error('no race'));
  yes('a race the engine cannot give is the novice line, 1', broken.pieces === 1);
}

// ------------------------------------------------------------ mp.onDeath --
const NPC = 0xff002001, HUMAN = 0xff000101, OTHER = 0xff000102, BANDIT = 0xff002002;
function deathBox(opts) {
  const states = new Map([
    [NPC, { profileId: -1, baseDesc: opts.base || 'dragonbase:Skyrim.esm' }],
    [BANDIT, { profileId: -1, baseDesc: 'bandit:Skyrim.esm' }],
    [HUMAN, { profileId: 17, baseDesc: 'person:Skyrim.esm' }],
    [OTHER, { profileId: 18, baseDesc: 'person:Skyrim.esm' }]
  ]);
  const credits = [];
  const box = {
    console: { log: function () {} },
    mp: {
      get: function (id, prop) { const s = states.get(id); if (!s) { throw new Error('no actor'); } return s[prop]; },
      set: function () {},
      getDescFromId: function (id) { return id.toString(16); },
      callPapyrusFunction: function () { return { type: 'espm', desc: raceDesc(opts.race || 'DragonRace') }; }
    },
    guard: function (n, fn) { return fn; },
    HUNT_TUNING: { bodySeconds: 300 },
    isCarcass: function () { return false; },
    creditWork: function (id, half, n) { credits.push({ id: id, half: half, n: n }); return null; },
    notify: function () {}, say: function () {}, log: function () {},
    resolveArrival: function () { return null; },
    setTimeout: function () {},
    __thornswoodCharacter: { stateOf: function (id) { return id === HUMAN ? { prof: 'warrior', half: 'berserker' } : { prof: 'cook', half: 'hearthcook' }; } },
    __thornswoodManeuvers: opts.blow ? { killerOf: function () { return opts.blow; } } : undefined
  };
  vm.createContext(box);
  vm.runInContext('const RACES = ' + racesLine[1] + ';\n' + hunts + '\n' + killTable + '\n' + kills.join('\n') + '\n' + onDeath, box);
  return { box: box, credits: credits };
}
{
  const d = deathBox({});
  d.box.mp.onDeath(NPC, HUMAN);
  yes('a warrior killing a dragon is credited 16 pieces, on the half they hold',
    d.credits.length === 1 && d.credits[0].id === HUMAN && d.credits[0].half === 'berserker' && d.credits[0].n === 16);
  const c = deathBox({ base: chicken });
  c.box.mp.onDeath(NPC, HUMAN);
  yes('a warrior killing a chicken is credited 1 piece', c.credits.length === 1 && c.credits[0].n === 1);
  const p = deathBox({});
  p.box.mp.onDeath(OTHER, HUMAN);
  yes('a person killed by a person is credited nothing', p.credits.length === 0);
  const n = deathBox({});
  n.box.mp.onDeath(NPC, BANDIT);
  yes('a kill by somebody who is not a person is credited nothing', n.credits.length === 0);
  const s = deathBox({});
  s.box.mp.onDeath(NPC, NPC);
  yes('a body that killed itself is credited nothing', s.credits.length === 0);
  const t = deathBox({});
  t.box.mp.onDeath(NPC, OTHER);
  yes('a killer who is not a warrior is credited nothing', t.credits.length === 0);
  const b = deathBox({ blow: HUMAN });
  b.box.mp.onDeath(NPC, 0);
  yes('a body the server\'s own maneuver blow killed is still the warrior\'s kill',
    b.credits.length === 1 && b.credits[0].id === HUMAN && b.credits[0].n === 16);
  const z = deathBox({});
  z.box.mp.onDeath(NPC, 0);
  yes('a death with no killer and no maneuver blow is credited nothing', z.credits.length === 0);
}

// ---------------------------------------------------------- creditWork n --
function creditBox(bonus) {
  const calls = { credit: 0, worked: 0 };
  const box = {
    console: { log: function () {} }, log: function () {}, notify: function () {}, say: function () {},
    __thornswoodNeeds: { worked: function () { calls.worked++; return null; } },
    __thornswoodSocial: { workBonus: function () { return bonus; } },
    __thornswoodCharacter: { credit: function () { calls.credit++; return calls.credit === 3 ? 'You are now an advanced Berserker.' : null; } }
  };
  vm.createContext(box);
  vm.runInContext('const PARTY_BANK = {};\n' + credit + '\nthis.creditWork = creditWork; this.PARTY_BANK = PARTY_BANK;', box);
  return { box: box, calls: calls };
}
{
  const one = creditBox(1);
  one.box.creditWork(5, 'berserker');
  yes('work with no count is one piece, as every trade passes it', one.calls.credit === 1 && one.calls.worked === 1);
  const dragon = creditBox(1);
  const line = dragon.box.creditWork(5, 'berserker', 16);
  yes('a 16 piece kill counts 16 pieces and costs one swing of rest', dragon.calls.credit === 16 && dragon.calls.worked === 1);
  yes('and the line about a rank reached on one of those pieces still comes back', line === 'You are now an advanced Berserker.');
  const party = creditBox(1.15);
  party.box.creditWork(5, 'berserker', 16);
  yes('with the party in the cell, 15% of 16 is two whole pieces paid and 0.4 banked',
    party.calls.credit === 18 && Math.abs(party.box.PARTY_BANK[5] - 0.4) < 1e-9);
}

// ------------------------------------------------- the maneuvers, pure part --
const clock = { t: 1000000 };
const world = { actors: new Map(), calls: [], staggers: [], writes: [], timers: [] };
function desc(id) { return id.toString(16) + ':run'; }
function actor(id, o) {
  world.actors.set(id, Object.assign({ pid: id > 0xff000000 && id < 0xff001000 ? id - 0xff000000 : -1, dead: false,
    p: { health: 1, magicka: 1, stamina: 1 }, max: 100, pos: [0, 0, 0], cell: 'cell:Skyrim.esm', anim: null }, o || {}));
  return id;
}
const SPELL = 0x5ee;
const mpFake = {
  get: function (id, prop) {
    if (id === 0 && prop === 'onlinePlayers') {
      return Array.from(world.actors.keys()).filter(function (k) { return world.actors.get(k).pid > 0; });
    }
    const a = world.actors.get(id);
    if (!a) { throw new Error('no actor ' + id); }
    if (prop === 'percentages') { return Object.assign({}, a.p); }
    if (prop === 'pos') { return a.pos.slice(); }
    if (prop === 'worldOrCellDesc') { return a.cell; }
    if (prop === 'isDead') { return a.dead; }
    if (prop === 'profileId') { return a.pid; }
    if (prop === 'lastAnimEvent') { return a.anim; }
    throw new Error('no ' + prop);
  },
  set: function (id, prop, v) {
    const a = world.actors.get(id);
    if (prop === 'percentages') {
      a.p = { health: v.health, magicka: v.magicka, stamina: v.stamina };
      if (v.health === 0) { a.dead = true; }
    }
  },
  getDescFromId: desc,
  getIdFromDesc: function (d) { return parseInt(String(d).split(':')[0], 16); },
  lookupEspmRecordById: function (id) { return { record: { type: id === SPELL ? 'SPEL' : 'WEAP' } }; },
  callPapyrusFunction: function (type, cls, fn, self, args) {
    world.calls.push(cls + '.' + fn);
    if (fn === 'DamageActorValue') {
      const a = world.actors.get(parseInt(self.desc, 16));
      a.p.stamina = Math.max(0, a.p.stamina - args[1] / a.max);
    }
    if (fn === 'SendAnimationEvent') { world.staggers.push(parseInt(args[0].desc, 16)); }
    return null;
  }
};
const states = new Map();
const party = { leader: 1, members: [] };
const box = {
  console: { log: function () {} },
  mp: mpFake,
  guard: function (n, fn) { return fn; },
  setTimeout: function (fn, ms) { world.timers.push({ fn: fn, at: clock.t + (ms || 0) }); return world.timers.length; },
  setInterval: function () { return 1; },
  clearInterval: function () {},
  __thornswoodCharacter: {
    stateOf: function (id) { return states.get(id) || null; },
    writeState: function (id, s, redraw) { world.writes.push({ id: id, redraw: redraw, effects: box.__thornswoodManeuvers.effects(id) }); return s; }
  },
  __thornswoodSocial: {
    profileOf: function (id) { const a = world.actors.get(id); return a && a.pid > 0 ? a.pid : 0; },
    partyOf: function (pid) { return party.members.indexOf(pid) !== -1 ? party : null; },
    nameOfPerson: function (id) { return 'Person ' + (id - 0xff000000); }
  }
};
box.globalThis = box;
vm.createContext(box);
box.__clock = clock;
vm.runInContext('Date.now = function () { return __clock.t; };', box);
vm.runInContext(progression, box);
vm.runInContext(maneuvers, box);
const P = box.__thornswoodProgression;
const M = box.__thornswoodManeuvers;
yes('the maneuvers block registered', !!M && !!M.use && !!M.hit && !!M.held);
yes('and it registered the OnHit handler', typeof box.mp['onPapyrusEvent:OnHit'] === 'function');

// The page's maneuver table, held against the block's.
function secondsOf(text) {
  const m = /^(\d+) (second|seconds|minute|minutes)$/.exec(text.trim());
  if (!m) { return null; }
  return Number(m[1]) * (m[2].indexOf('minute') === 0 ? 60 : 1);
}
const rows = [];
page.split('\n').forEach(function (line) {
  const c = line.split('|').slice(1, -1).map(function (x) { return x.trim(); });
  if (c.length === 6 && (c[0] === 'Bulwark' || c[0] === 'Berserker')) { rows.push(c); }
});
yes('the page has eight maneuver rows', rows.length === 8);
rows.forEach(function (c) {
  const key = c[2].toLowerCase();
  const m = M.MANEUVERS[key];
  const lasts = /(?:for|within) (\d+) seconds/.exec(c[3]);
  yes(c[2] + ' is ' + c[0] + ' at ' + c[1] + ', ' + c[4] + ' stamina, a ' + c[5] + ' wait' +
      (lasts ? ', ' + lasts[1] + ' seconds long' : ', waiting for its blow'),
    !!m && m.half === c[0].toLowerCase() && m.rank === c[1].toLowerCase() &&
    m.stamina === Number(c[4]) && m.cooldown === secondsOf(c[5]) &&
    m.seconds === (lasts ? Number(lasts[1]) : 0));
});
yes('there are no maneuvers past the table', Object.keys(M.MANEUVERS).length === 8 && M.ORDER.length === 8);
yes('Cover and Wall take 20% off, within 3 metres', M.MANEUVERS.cover.less === 0.2 && M.MANEUVERS.wall.less === 0.2 &&
  M.MANEUVERS.cover.metres === 3 && M.MANEUVERS.wall.metres === 3);
yes('Rush is +4 speed, Heavy 25% more, Wreck 50% more', M.MANEUVERS.rush.speed === 4 &&
  M.MANEUVERS.heavy.more === 0.25 && M.MANEUVERS.wreck.more === 0.5);

function warrior(half, rank, sisterRank) {
  const s = P.pickProfession(P.fresh(), 'warrior', half).state;
  s.ranks[half] = rank;
  if (sisterRank) { s.ranks[P.sisterOf('warrior', half)] = sisterRank; }
  return s;
}
function keys(o) { return Object.keys(o).sort().join(','); }
yes('a novice Bulwark holds Set', keys(M.held(warrior('bulwark', 'novice'), false)) === 'set');
yes('an expert Bulwark holds Set, Plant and Cover', keys(M.held(warrior('bulwark', 'expert'), false)) === 'cover,plant,set');
yes('a master Berserker holds Rush, Heavy, Break and Wreck',
  keys(M.held(warrior('berserker', 'master'), false)) === 'break,heavy,rush,wreck');
yes('the sister half has no maneuver until a Warlord has taken you on',
  keys(M.held(warrior('bulwark', 'master'), false)) === 'cover,plant,set,wall');
yes('once taken on, the sister half is the novice row only, even past novice',
  keys(M.held(warrior('bulwark', 'master', 'expert'), M.takenOn(warrior('bulwark', 'master', 'expert')))) === 'cover,plant,rush,set,wall');
yes('a sister half at novice reads as not taken on, past novice as taken on',
  M.takenOn(warrior('bulwark', 'novice')) === false && M.takenOn(warrior('bulwark', 'novice', 'advanced')) === true);
box.__thornswoodCharacter.masterFor = function (id, s, half) { return id === 77 && half === 'berserker' ? { ranks: { berserker: 'master' } } : null; };
yes('a sister half at novice whose Master\'s record stands (/apprentice, #1388) is taken on',
  M.takenOn(warrior('bulwark', 'novice'), 77) === true && M.takenOn(warrior('bulwark', 'novice'), 78) === false);
delete box.__thornswoodCharacter.masterFor;
const master = warrior('berserker', 'master');
const cookTaught = P.teach(P.pickProfession(P.fresh(), 'cook', 'hearthcook').state, master, 'berserker');
yes('a Warlord can teach a cook Berserker as an outside trade', cookTaught.ok);
yes('an outside trade is the novice row and no further', keys(M.held(cookTaught.state, false)) === 'rush');
yes('a cook nobody taught holds nothing', keys(M.held(P.pickProfession(P.fresh(), 'cook', 'hearthcook').state, false)) === '');

// ------------------------------------------------- the maneuvers, in use --
const BUL = actor(0xff000001), BER = actor(0xff000002, { pos: [3000, 0, 0] }), FRIEND = actor(0xff000003, { pos: [100, 0, 0] });
const STRANGER = actor(0xff000004, { pos: [0, 120, 0] });
const FAR = actor(0xff000005, { pos: [400, 0, 0] });
const COOK = actor(0xff000006, { pos: [5000, 0, 0] });
const WOLF = actor(0xff002101, { pid: -1, pos: [50, 50, 0] });
states.set(BUL, warrior('bulwark', 'master'));
states.set(BER, warrior('berserker', 'master'));
states.set(COOK, cookTaught.state);
states.set(FRIEND, P.pickProfession(P.fresh(), 'cook', 'hearthcook').state);
party.members = [1, 3, 5];

function later(ms) {
  clock.t += ms;
  world.timers.sort(function (a, b) { return a.at - b.at; });
  while (world.timers.length && world.timers[0].at <= clock.t) { world.timers.shift().fn(); }
  M.tick();
}
function strike(by, target, took, opts) {
  opts = opts || {};
  box.mp['onPapyrusEvent:OnHit'](target, { type: 'form', desc: desc(by) },
    { type: 'espm', desc: (opts.spell ? SPELL : 0x1f4).toString(16) + ':Skyrim.esm' }, null,
    !!opts.power, false, false, !!opts.blocked);
  // The engine's own damage, after the event, the way OnWeaponHit runs.
  const a = world.actors.get(target);
  a.p.health = Math.max(0, a.p.health - took);
  if (a.p.health === 0) { a.dead = true; }
}
function settle() { later(0); }
function health(id) { return Math.round(world.actors.get(id).p.health * 10000) / 10000; }
function heal(id) { const a = world.actors.get(id); a.p.health = 1; a.dead = false; }

yes('/maneuver on its own lists what you hold', /^Your maneuvers: Rush \(15 stamina, ready\)/.test(M.use(BER, '')));
yes('a name that is not a maneuver is refused by name', /no maneuver by that name/.test(M.use(BER, 'fireball')));
yes('a cook taught Berserker is refused Heavy, and told the novice row is the whole of it',
  /outside trade, and that is its novice row and no further: Rush/.test(M.use(COOK, 'heavy')));
yes('a cook taught Berserker is refused a Bulwark maneuver', /Set is a Bulwark maneuver/.test(M.use(COOK, 'set')));
yes('a master Bulwark is refused Rush until a Warlord takes them on', /sister half\. Its novice maneuver opens when a Warlord takes you on/.test(M.use(BUL, 'rush')));
states.set(0xff000007, warrior('berserker', 'novice'));
actor(0xff000007, { pos: [9000, 0, 0] });
yes('a novice Berserker is refused Heavy by rank', M.use(0xff000007, 'heavy') === 'Heavy is for an advanced Berserker. You are a novice Berserker.');

// Stamina.
world.actors.get(BER).p.stamina = 0.1;
const callsBefore = world.calls.length;
const tooTired = M.use(BER, 'rush');
yes('without 15 stamina Rush does not start, and says so', /takes 15 stamina, and you do not have it\. Nothing happens\./.test(tooTired));
yes('and the stamina is put back exactly as it was', world.actors.get(BER).p.stamina === 0.1);
yes('and nothing is armed and no wait starts', !M.effects(BER) && /Rush \(15 stamina, ready\)/.test(M.use(BER, '')) &&
  world.calls.slice(callsBefore).indexOf('Actor.DamageActorValue') !== -1);
world.actors.get(BER).p.stamina = 1;
const rush = M.use(BER, 'rush');
yes('Rush starts: +4 speed for 5 seconds', rush === 'Rush: +4 speed for 5 seconds.');
yes('Rush spent 15 stamina through the engine', Math.abs(world.actors.get(BER).p.stamina - 0.85) < 1e-9);
yes('Rush puts +4 speed on the map the client sets, and redraws to send it',
  M.effects(BER) && M.effects(BER).speedMult === 4 && world.writes.length === 1 && world.writes[0].redraw === true &&
  world.writes[0].effects.speedMult === 4);
yes('Rush again at once waits its 30 seconds', /Rush is ready again in 30 seconds\./.test(M.use(BER, 'rush')));
later(5100);
yes('after 5 seconds the speed comes off and the client is told', !M.effects(BER) && world.writes.length === 2 && world.writes[1].effects === null);
later(25000);
yes('after the 30 seconds Rush can start again', M.use(BER, 'rush') === 'Rush: +4 speed for 5 seconds.');
later(6000);

// Heavy.
world.actors.get(BER).p.stamina = 1;
yes('Heavy starts', /Heavy\. Your next power attack in the next 8 seconds deals 25% more\./.test(M.use(BER, 'heavy')));
strike(BER, WOLF, 0.2, {});
settle();
yes('a hit that is not a power attack is not Heavy and does not spend it', health(WOLF) === 0.8);
strike(BER, WOLF, 0.2, { power: true, spell: true });
settle();
yes('a spell is not a power attack either', health(WOLF) === 0.6);
heal(WOLF);
strike(BER, WOLF, 0.2, { power: true });
settle();
yes('the power attack takes a quarter again of what it took: 0.2 becomes 0.25', health(WOLF) === 0.75);
strike(BER, WOLF, 0.2, { power: true });
settle();
yes('and Heavy is spent: the next power attack is only itself', health(WOLF) === 0.55);
heal(WOLF);
later(45000);
M.use(BER, 'heavy');
strike(BER, WOLF, 0, { power: true });
settle();
strike(BER, WOLF, 0.2, { power: true });
settle();
yes('a power attack the engine threw away (it took nothing) leaves Heavy armed for the next', health(WOLF) === 0.75);
heal(WOLF);
later(45000);
M.use(BER, 'heavy');
later(8100);
strike(BER, WOLF, 0.2, { power: true });
settle();
yes('after 8 seconds Heavy has run out', health(WOLF) === 0.8);
heal(WOLF);

// Two hits on one body in one turn: each is measured on its own.
later(45000);
M.use(BER, 'heavy');
strike(BER, WOLF, 0.2, { power: true });
strike(FRIEND, WOLF, 0.2, {});
settle();
yes('a Heavy blow and somebody else\'s blow in the same moment: only the Heavy one is a quarter again', health(WOLF) === 0.55);
heal(WOLF);

// Wreck and Break, and the stagger.
world.actors.get(BER).p.stamina = 1;
yes('Wreck starts', /^Wreck\. Your next power attack deals 50% more/.test(M.use(BER, 'wreck')));
strike(BER, STRANGER, 0.2, { power: true });
settle();
yes('the Wreck power attack takes a half again: 0.2 becomes 0.3', health(STRANGER) === 0.7);
yes('and staggers the person it lands on, in their own game', world.staggers.length === 1 && world.staggers[0] === STRANGER);
heal(STRANGER);
world.actors.get(BER).p.stamina = 1;
M.use(BER, 'break');
strike(BER, WOLF, 0.1, {});
settle();
yes('Break: the next hit on a creature does its damage and no stagger is sent', world.staggers.length === 1 && health(WOLF) === 0.9);
heal(WOLF);
later(60000);
world.actors.get(BER).p.stamina = 1;
M.use(BER, 'break');
strike(BER, STRANGER, 0.1, {});
settle();
yes('Break: the next hit on a person staggers them', world.staggers.length === 2 && world.staggers[1] === STRANGER);
heal(STRANGER);

// Plant refuses the stagger the server sends.
world.actors.get(BUL).p.stamina = 1;
world.actors.get(BER).p.stamina = 1;
later(60000);
yes('Plant starts and says which staggers it stops', /^Plant, for 8 seconds\. A Break or a Wreck does not stagger you\./.test(M.use(BUL, 'plant')));
M.use(BER, 'break');
strike(BER, BUL, 0.1, {});
settle();
yes('a Break on a planted Bulwark sends no stagger', world.staggers.length === 2);
heal(BUL);

// A Wreck blow that kills is still the berserker's kill.
later(120000);
world.actors.get(BER).p.stamina = 1;
M.use(BER, 'wreck');
world.actors.get(WOLF).p.health = 0.3;
strike(BER, WOLF, 0.2, { power: true });
settle();
yes('a Wreck half again that takes health to nothing kills', world.actors.get(WOLF).dead === true && health(WOLF) === 0);
yes('and mp.onDeath is told whose blow it was', M.killerOf(WOLF) === BER && M.killerOf(WOLF) === 0);
heal(WOLF);

// Wall.
later(200000);
world.actors.get(BUL).p.stamina = 1;
yes('Wall starts', /^Wall, for 10 seconds\./.test(M.use(BUL, 'wall')));
yes('Wall spent 40 stamina', Math.abs(world.actors.get(BUL).p.stamina - 0.6) < 1e-9);
strike(WOLF, BUL, 0.5, {});
settle();
yes('the Bulwark takes 20% less: 0.5 becomes 0.4', health(BUL) === 0.6);
strike(WOLF, FRIEND, 0.5, {});
settle();
yes('a party member within 3 metres takes 20% less', health(FRIEND) === 0.6);
strike(WOLF, STRANGER, 0.5, {});
settle();
yes('somebody within 3 metres who is not in the party does not', health(STRANGER) === 0.5);
strike(WOLF, FAR, 0.5, {});
settle();
yes('a party member further than 3 metres does not', health(FAR) === 0.5);
[BUL, FRIEND, STRANGER, FAR].forEach(heal);
later(10100);
strike(WOLF, BUL, 0.5, {});
settle();
yes('after 10 seconds the Wall is down', health(BUL) === 0.5);
heal(BUL);

// Cover.
later(200000);
world.actors.get(BUL).p.stamina = 1;
const cover = M.use(BUL, 'cover');
yes('Cover is on the nearest person within 3 metres', cover === 'Cover on Person 3, for 8 seconds. While you block within 3 metres of them, they take 20% less damage.');
strike(WOLF, FRIEND, 0.5, {});
settle();
yes('while the Bulwark is not blocking, Cover gives nothing', health(FRIEND) === 0.5);
heal(FRIEND);
world.actors.get(BUL).anim = 'blockStart';
later(100);
world.actors.get(BUL).anim = null;
strike(WOLF, FRIEND, 0.5, {});
settle();
yes('while the Bulwark blocks, the covered person takes 20% less, and moving does not forget the block', health(FRIEND) === 0.6);
strike(WOLF, STRANGER, 0.5, {});
settle();
yes('Cover is for one person: somebody else beside them gets nothing', health(STRANGER) === 0.5);
heal(FRIEND); heal(STRANGER);
world.actors.get(BUL).anim = 'blockStop';
later(100);
strike(WOLF, FRIEND, 0.5, {});
settle();
yes('once the block drops, Cover gives nothing again', health(FRIEND) === 0.5);
heal(FRIEND);
world.actors.get(BUL).p.stamina = 1;
later(100000);
const alone = actor(0xff000008, { pos: [20000, 0, 0] });
states.set(alone, warrior('bulwark', 'expert'));
const staminaAlone = world.actors.get(alone).p.stamina;
yes('Cover with nobody within 3 metres is refused before any stamina is spent',
  M.use(alone, 'cover') === 'Cover is for one person within 3 metres of you, and nobody is.' &&
  world.actors.get(alone).p.stamina === staminaAlone);

// Set says what it is and what is not in the game.
yes('Set spends the stamina and says the half-cost block is not in the game yet',
  /^Set, for 8 seconds\. Halving what a block costs is not in the game yet/.test(M.use(BUL, 'set')));
world.actors.get(BUL).dead = true;
later(50000);
yes('nobody starts a maneuver while down', M.use(BUL, 'set') === 'Not while you are down.');
world.actors.get(BUL).dead = false;

// The sister half through /apprentice.
box.__thornswoodCharacter.masterFor = function (id, s, half) { return id === BUL && half === 'berserker' ? {} : null; };
later(100000);
world.actors.get(BUL).p.stamina = 1;
yes('once a Warlord has taken a Bulwark on (/apprentice), Rush, the sister half\'s novice row, starts',
  M.use(BUL, 'rush') === 'Rush: +4 speed for 5 seconds.');
yes('and Heavy, past the novice row, does not',
  /sister half, and a sister half has its novice row and no more: Rush/.test(M.use(BUL, 'heavy')));
delete box.__thornswoodCharacter.masterFor;
later(6000);

// ------------------------------------------------ the panel's effects map --
{
  const fn = new Function('g', withManeuvers + '\nreturn withManeuvers;')({ __thornswoodManeuvers: { effects: function (id) { return id === 1 ? { speedMult: 4 } : null; } } });
  const out = fn(1, { speedMult: 2, health: 10 });
  yes('Rush adds to the speed the tree already sends rather than replacing it', out.speedMult === 6 && out.health === 10);
  yes('with nothing running the map is left as it was', fn(2, { speedMult: 2 }).speedMult === 2);
  yes('the panel view folds the maneuvers in', /effects: withManeuvers\(actorId, withNeeds\(actorId, P\.treeApplies\(s\)\)\),/.test(gm));
}

// ------------------------------------------------------ words and handlers --
{
  const words = /^const WORDS = (\[[\s\S]*?\]);$/m.exec(gm);
  const W = words ? new Function('return ' + words[1])() : [];
  yes('/maneuver is a word the server answers', W.indexOf('/maneuver') !== -1);
  const pw = /const PLAYER_WORDS = (\[[\s\S]*?\]);/.exec(gm);
  const PW = pw ? new Function('return ' + pw[1])() : [];
  yes('and one everybody is told about', PW.indexOf('/maneuver') !== -1);
  yes('the chat router hands /maneuver to the maneuvers block', /if \(word === '\/maneuver'\) \{[\s\S]{0,400}mvs\.use\(actorId, parts\[1\]\)/.test(gm));
  const reg = gm.split('\n').filter(function (l) { return /^mp\['onPapyrusEvent:OnHit'\]\s*=/.test(l); });
  yes('OnHit is registered once, through guard()', reg.length === 1 && reg[0].indexOf("guard('onPapyrusEvent:OnHit', function") !== -1);
  const body = slice(gm, "mp['onPapyrusEvent:OnHit'] = guard(", '\n});');
  yes('and it never answers false', !!body && !/\breturn\s+false\b/.test(body));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
