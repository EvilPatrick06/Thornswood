say('\n=== character creation ===');

const WRIT_MINER = 'e80014:Thornswood-Content.esp';
const WRIT_MAGE  = 'e80012:Thornswood-Content.esp';
const PASS_RIFTEN = 'e80024:Thornswood-Content.esp';
const PASS_SOLITUDE = 'e80021:Thornswood-Content.esp';
const WELCOME = 'e80000:Thornswood-Content.esp';
const HALL = '19bad4:Skyrim Unbound.esp';

const NEW = 0xff00aa01, OLD = 0xff00aa02;
const has = (a, desc) => {
  const e = (inventories.get(a) || { entries: [] }).entries.find(x => x.baseId === id(desc));
  return e ? e.count : 0;
};
const stage = (a) => (mp.get(a, 'thornswoodChargen') || {}).stage;

check('chargen property registered', captured.properties.has('thornswoodChargen'), true);
check('the timer was armed at load', typeof tickFn, 'function');

// nobody online
online.length = 0;
check('an empty server ticks harmlessly', tick(), '');

// A brand new character: no appearance, no chargen state, and standing outside
// the hall so the move is visible.
state.set(NEW, { appearance: null, worldOrCellDesc: '1a26f:Skyrim.esm' });
inventories.set(NEW, { entries: [] });
online.push(NEW);

// A client that has only just connected is mid save-load. Nothing may touch it.
tick();
check('a joining client is left alone at first', stage(NEW), undefined);
check('and is not teleported while it loads', captured.teleports.has(NEW), false);
advance(SETTLE);

tick();
check('after the settle window, creation opens', stage(NEW), 'appearance');
check('and they are moved into the hall',
      (captured.teleports.get(NEW) || {}).cellOrWorldDesc, HALL);
check('the race menu is left to the spawn system',
      captured.raceMenu.some(([f]) => f === NEW), false);
check('no books until the face is done', has(NEW, WELCOME), 0);

// ticking again before the race menu closes must not repeat itself
const moves = captured.teleports.size;
tick();
check('a second tick does not move them again', captured.teleports.size, moves);
check('still waiting on the appearance', stage(NEW), 'appearance');

// Somebody already standing in the hall is not teleported at all: startPoints
// put them there, and a needless teleport is the risky operation here.
const INHALL = 0xff00aa09;
state.set(INHALL, { appearance: null, worldOrCellDesc: HALL });
inventories.set(INHALL, { entries: [] });
online.push(INHALL);
tick(); advance(SETTLE); tick();
check('a character already in the hall enters creation', stage(INHALL), 'appearance');
check('and is not teleported', captured.teleports.has(INHALL), false);
online.splice(online.indexOf(INHALL), 1);

// a character that existed before this system shipped is left alone
state.set(OLD, { appearance: { isFemale: false } });
inventories.set(OLD, { entries: [] });
online.push(OLD);
tick(); advance(SETTLE); tick();
check('an existing character is not hijacked', stage(OLD), 'done');
check('and is not teleported', captured.teleports.has(OLD), false);
check('and gets no books', has(OLD, WELCOME), 0);

// race menu closed: the appearance turns up
mp.set(NEW, 'appearance', { isFemale: true });
tick();
check('appearance done moves to class', stage(NEW), 'class');
check('the welcome book arrives', has(NEW, WELCOME), 1);
check('and something to wear while choosing', has(NEW, '1be1a:Skyrim.esm'), 1);
check('all six writs arrive', has(NEW, WRIT_MINER) + has(NEW, WRIT_MAGE), 2);
check('no passages yet', has(NEW, PASS_RIFTEN), 0);

// reading a passage before a writ is out of turn
let o = run(() => mp.onReadBook(NEW, id(PASS_RIFTEN)));
check('a passage read out of turn is refused', o.out.includes('out of turn'), true);
check('and changes nothing', stage(NEW), 'class');

// choose a trade
run(() => mp.onReadBook(NEW, id(WRIT_MINER)));
check('reading a writ moves to destination', stage(NEW), 'destination');
check('the trade is recorded', mp.get(NEW, 'thornswoodChargen').class, 'miner');
check('the unread writs are gone', has(NEW, WRIT_MAGE), 0);
check('the read writ is gone too', has(NEW, WRIT_MINER), 0);
check('the pick arrives', has(NEW, 'e3c16:Skyrim.esm'), 1);
check('two torches arrive', has(NEW, '1d4ec:Skyrim.esm'), 2);
check('the novice manual arrives', has(NEW, 'b276:Thornswood-Content.esp'), 1);
check('fifty gold arrives', has(NEW, 'f:Skyrim.esm'), 50);
check('the six passages arrive', has(NEW, PASS_RIFTEN) + has(NEW, PASS_SOLITUDE), 2);
check('the welcome book is still readable', has(NEW, WELCOME), 1);

// a second writ cannot change the answer
o = run(() => mp.onReadBook(NEW, id(WRIT_MAGE)));
check('a second writ is refused', o.out.includes('out of turn'), true);
check('the trade is unchanged', mp.get(NEW, 'thornswoodChargen').class, 'miner');

// choose a town
captured.spawnPoints.delete(NEW);
run(() => mp.onReadBook(NEW, id(PASS_SOLITUDE)));
check('reading a passage finishes creation', stage(NEW), 'done');
check('the town is recorded', mp.get(NEW, 'thornswoodChargen').destination, 'solitude');
check('they are moved to the temple',
      (captured.teleports.get(NEW) || {}).cellOrWorldDesc, '16a02:Skyrim.esm');
check('the respawn point matches the start',
      (captured.spawnPoints.get(NEW) || {}).cellOrWorldDesc, '16a02:Skyrim.esm');
check('start and respawn are the same spot',
      JSON.stringify(captured.teleports.get(NEW).pos),
      JSON.stringify(captured.spawnPoints.get(NEW).pos));
check('the passages are gone', has(NEW, PASS_RIFTEN) + has(NEW, PASS_SOLITUDE), 0);
check('the welcome book is gone', has(NEW, WELCOME), 0);
check('the gear survives', has(NEW, 'e3c16:Skyrim.esm'), 1);

// and they are left alone from now on
const tp = JSON.stringify(captured.teleports.get(NEW));
tick(); tick();
check('a finished character is never touched again',
      JSON.stringify(captured.teleports.get(NEW)), tp);

// the chargen hook must not swallow the skill manuals
inventories.set(NEW, { entries: [] });
state.get(NEW).thornswoodSkills = {};
run(() => mp.onReadBook(NEW, id('b277:Thornswood-Content.esp')));
check('skill manuals still reach their handler',
      mp.get(NEW, 'thornswoodSkills').mining, 2);
check('the new alchemy novice manual works',
      (run(() => mp.onReadBook(NEW, id('e80001:Thornswood-Content.esp'))),
       mp.get(NEW, 'thornswoodSkills').alchemy), 1);

// a trade that gives spell tomes gives tomes, not spells
const M = 0xff00aa03;
state.set(M, { appearance: { isFemale: false }, thornswoodChargen: { stage: 'class' } });
inventories.set(M, { entries: [] });
run(() => mp.onReadBook(M, id(WRIT_MAGE)));
check('the mage gets the Flames tome', has(M, '9cd51:Skyrim.esm'), 1);
check('the mage gets the Healing tome', has(M, '9e2af:Skyrim.esm'), 1);

// hot reload must not stack timers. The server reloads by requiring the file
// again in a fresh module while the Node process, and its timers, live on.
const before = liveTimers;
delete require.cache[require.resolve(PLUGIN)];
logs = [];
require(PLUGIN);
check('a hot reload leaves exactly one timer', liveTimers, before);
check('and rearms the tick', typeof tickFn, 'function');

// with the hall missing the flow still runs, just in place
const F = 0xff00aa04;
missingDescs.add(HALL);
state.set(F, { appearance: null, worldOrCellDesc: '1a26f:Skyrim.esm' });
inventories.set(F, { entries: [] });
online.length = 0; online.push(F);
tick(); advance(SETTLE);
o = { out: tick() };
check('a missing hall is reported, not fatal', o.out.includes('not in this load order'), true);
check('and creation starts anyway', stage(F), 'appearance');
missingDescs.delete(HALL);

// Arrival facings are degrees, not the radians a marker record stores. Read them
// back through a death, which is the only way out of the module.
const rots = [];
for (const [d, p] of [['165a7:Skyrim.esm', [0,0,0]], ['16a02:Skyrim.esm', [0,0,0]],
                      ['16785:Skyrim.esm', [0,0,0]], ['16bd7:Skyrim.esm', [0,0,0]]]) {
  state.set(ACTOR, { worldOrCellDesc: d, pos: p });
  captured.spawnPoints.delete(ACTOR);
  run(() => mp.onDeath(ACTOR, 0));
  const sp = captured.spawnPoints.get(ACTOR);
  if (sp) rots.push(sp.rot[2]);
}
check('some arrival facing exceeds 2pi, so they are degrees',
      rots.some(r => Math.abs(r) > 2 * Math.PI), true);
check('and none exceeds a full turn', rots.every(r => Math.abs(r) <= 360), true);
