'use strict';
/*
 * Thornswood gamemode
 * ===================
 *
 * Loaded by skymp5-server through requireTemp(), which copies this file to a
 * temp directory and requires it there. Relative requires would break, so
 * everything lives in this one file and all data is inlined. The server watches
 * the file and hot-reloads on change; mp.clear() runs first, so re-registering
 * handlers at load time is correct and expected.
 *
 * The event contract, read out of ScampServerListener::OnMpApiEvent:
 * the server looks up a function by name on the global `mp` object, calls it
 * with the event's arguments, and treats a returned `false` as "block this".
 * Returning undefined lets the event through. A handler that throws is logged
 * and the event proceeds, but do not rely on that: every handler here is
 * wrapped, because an exception on a hot path is a bad way to find a typo.
 *
 * Form ids cross the boundary as descriptors, "<low 24 bits in hex>:<plugin>",
 * so nothing here is baked to a load order position.
 */

const DATA = /*__DATA__*/null;
const STATIONS = /*__STATIONS__*/null;
const MANUALS = /*__MANUALS__*/null;
const ITEMS = /*__ITEMS__*/null;

const PREFER_SLOT = 'temple';
const FALLBACK_DESTINATION = 'whiterun';

const WORLDSPACES = new Set(DATA.worldspaces);

// ---------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------

function log() {
  const args = Array.prototype.slice.call(arguments);
  console.log('[thornswood] ' + args.join(' '));
}

/** Run fn, swallow and report anything it throws. Handlers must never escape. */
function guard(name, fn) {
  return function () {
    try {
      return fn.apply(null, arguments);
    } catch (e) {
      console.error('[thornswood] ' + name + ' threw: ' + (e && e.stack ? e.stack : e));
      return undefined;
    }
  };
}

/** Runtime form id for a descriptor, or 0 if the plugin is not loaded. */
function idOf(descriptor) {
  try {
    return mp.getIdFromDesc(descriptor);
  } catch (e) {
    return 0;
  }
}

/**
 * Try to put a line on somebody's screen. Debug.Notification is implemented on
 * the server, but it finds its target actor through the Papyrus stack, which is
 * empty when the call starts here rather than in a game event. So this may well
 * do nothing, and nothing is allowed to depend on it: the log line below is the
 * one that is guaranteed.
 */
function notify(actorId, text) {
  log('say', actorId.toString(16), text);
  try {
    mp.callPapyrusFunction('global', 'Debug', 'Notification', null, [text]);
  } catch (e) {
    // no stack actor, or the class is not registered. expected; ignore.
  }
}

function dist2(ax, ay, bx, by) {
  const dx = ax - bx;
  const dy = ay - by;
  return dx * dx + dy * dy;
}

// ---------------------------------------------------------------------------
// respawn resolution
//
// Port of respawnResolver.ts. Same five branches, same order. See
// respawn-holds.json for where the numbers come from; never hand-edit them.
// ---------------------------------------------------------------------------

function holdOfCell(cellDesc) {
  const h = DATA.cellToHold[cellDesc];
  return h || null;
}

function capitalPos(hold) {
  const c = DATA.capitals[hold];
  return c ? { x: c.pos[0], y: c.pos[1] } : null;
}

function nearestCapital(pos) {
  let best = null;
  let bestD = Infinity;
  for (const hold in DATA.capitals) {
    const c = DATA.capitals[hold];
    const d = dist2(c.pos[0], c.pos[1], pos.x, pos.y);
    if (d < bestD) { bestD = d; best = hold; }
  }
  return best;
}

/**
 * Nearest single consecrated entrance, weighing every temple and every Hall of
 * the Dead separately rather than picking a city first. Solstheim is excluded:
 * its coordinates are not in Tamriel's frame, so a distance to it is noise.
 */
function nearestEntrance(pos) {
  let best = null;
  let bestD = Infinity;
  for (const key in DATA.destinations) {
    const d = DATA.destinations[key];
    for (const slot in d) {
      const s = d[slot];
      if (!s.entrancePos) continue;
      if (s.entranceWorld && parseInt(s.entranceWorld, 16) === 0x02000800) continue;
      const dd = dist2(s.entrancePos[0], s.entrancePos[1], pos.x, pos.y);
      if (dd < bestD) { bestD = dd; best = { destination: key, slot: slot }; }
    }
  }
  return best;
}

/**
 * `via` is how the hold was decided, `reason` is which destination branch fired.
 * Keep both: "Hjaalmarch, found from the cell, then borrowed Solitude's hall"
 * is a different story from "Hjaalmarch, guessed from coordinates". The first
 * time someone dies in Morthal and wakes somewhere surprising, this is the line
 * you will read.
 */
function arrive(dest, hold, reason, slotOverride, via) {
  const d = DATA.destinations[dest];
  if (!d) return null;
  let slot = slotOverride;
  if (!slot) slot = d[PREFER_SLOT] ? PREFER_SLOT : Object.keys(d)[0];
  const s = d[slot];
  if (!s) return null;
  return {
    destination: dest,
    slot: slot,
    cell: s.cell,
    desc: s.desc,
    pos: s.pos,
    rot: s.rot,
    hold: hold,
    crimeFaction: hold && DATA.holds[hold] ? DATA.holds[hold].crimeFaction : null,
    reason: reason,
    via: via,
  };
}

/**
 * site: { desc: worldOrCellDesc string, pos: [x,y,z] }
 */
function resolveArrival(site) {
  const low = site.desc.split(':')[0].toLowerCase();

  // 1. Solstheim, by worldspace. Must never reach a distance comparison.
  if (low === DATA.solstheim) {
    return arrive('ravenrock', 'DLC2SolstheimLocation', 'own-ground', null, 'solstheim');
  }

  const outdoors = WORLDSPACES.has(site.desc);
  const pos = { x: site.pos[0], y: site.pos[1] };

  // 2. Died indoors: the cell names the hold outright.
  let hold = outdoors ? null : holdOfCell(site.desc);
  let via = hold ? 'cell' : null;
  let reason = 'own-ground';

  // 3. Died outdoors: nearest of the nine hold capitals. Resolving the HOLD
  //    first is what keeps the mapping in charge. Dawnstar proves it: Solitude
  //    is closer as the crow flies, but the Pale answers to Windhelm.
  if (!hold) {
    hold = nearestCapital(pos);
    via = outdoors ? 'nearest-capital' : 'unmapped-interior';
  }

  if (hold) {
    const dest = DATA.holdToDestination[hold];
    if (dest) {
      const a = arrive(dest, hold, reason, null, via);
      if (a) return a;
    }
    // 4. Hold has no consecrated ground of its own: the Pale, Hjaalmarch,
    //    Winterhold, Falkreath. Measure from a position genuinely in Tamriel's
    //    frame. An interior's coordinates are local to that cell, so measuring
    //    from them would compare against the origin and pick whatever sits
    //    nearest [0,0]; use the hold's capital instead.
    const from = outdoors ? pos : (capitalPos(hold) || pos);
    const near = nearestEntrance(from);
    if (near) {
      const a = arrive(near.destination, hold, 'borrowed', near.slot, via);
      if (a) return a;
    }
  }

  return arrive(FALLBACK_DESTINATION, hold, 'fallback', null, via);
}

// ---------------------------------------------------------------------------
// skill tracks
//
// The manuals are plain BOOK records with no script attached, so reading one is
// only a signal. The tier it grants is stored per person and gates yields.
// ---------------------------------------------------------------------------

const SKILL_PROPERTY = 'thornswoodSkills';

function ensureProperties() {
  try {
    mp.makeProperty(SKILL_PROPERTY, {
      isVisibleByOwner: true,
      isVisibleByNeighbors: false,
      updateOwner: '',
      updateNeighbor: '',
    });
    mp.makeProperty(CHARGEN_PROPERTY, {
      isVisibleByOwner: false,
      isVisibleByNeighbors: false,
      updateOwner: '',
      updateNeighbor: '',
    });
  } catch (e) {
    // already made, or made by a previous load. harmless.
  }
}

function getSkills(actorId) {
  let s = null;
  try {
    s = mp.get(actorId, SKILL_PROPERTY);
  } catch (e) {
    s = null;
  }
  if (!s || typeof s !== 'object') s = {};
  return s;
}

function setSkill(actorId, track, tier) {
  const s = getSkills(actorId);
  if ((s[track] || 0) >= tier) return false;
  s[track] = tier;
  mp.set(actorId, SKILL_PROPERTY, s);
  return true;
}

function tierOf(actorId, track) {
  const s = getSkills(actorId);
  return s[track] || 0;
}

// ---------------------------------------------------------------------------
// gathering stations
// ---------------------------------------------------------------------------

const COOLDOWN_MS = 20000;
const lastUse = new Map();   // "actorId:refrId" -> timestamp

/** Seconds still to wait, 0 if ready. Read only: a refused action must not
 *  start a cooldown, or walking up to a kiln without firewood locks you out. */
function cooldownLeft(actorId, refrId) {
  const prev = lastUse.get(actorId + ':' + refrId) || 0;
  const left = COOLDOWN_MS - (Date.now() - prev);
  return left > 0 ? Math.ceil(left / 1000) : 0;
}

/** Start the cooldown. Call this only once the yield has actually been given. */
function stampCooldown(actorId, refrId) {
  lastUse.set(actorId + ':' + refrId, Date.now());
}

function addItem(actorId, itemDesc, count) {
  const baseId = idOf(itemDesc);
  if (!baseId) return false;
  const inv = mp.get(actorId, 'inventory') || { entries: [] };
  const entries = inv.entries || [];
  let found = false;
  for (const e of entries) {
    if (e.baseId === baseId) { e.count += count; found = true; break; }
  }
  if (!found) entries.push({ baseId: baseId, count: count });
  mp.set(actorId, 'inventory', { entries: entries });
  return true;
}

function takeItem(actorId, itemDesc, count) {
  const baseId = idOf(itemDesc);
  if (!baseId) return false;
  const inv = mp.get(actorId, 'inventory') || { entries: [] };
  const entries = inv.entries || [];
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].baseId !== baseId) continue;
    if (entries[i].count < count) return false;
    entries[i].count -= count;
    if (entries[i].count <= 0) entries.splice(i, 1);
    mp.set(actorId, 'inventory', { entries: entries });
    return true;
  }
  return false;
}

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

/** Salt quarry: tier gates the yield and the chance of the rarer salts. */
function mineSalt(actorId, refrId) {
  const tier = tierOf(actorId, 'mining');
  if (tier < 1) return 'You need the Novice mining manual before you can work a quarry.';

  const wait = cooldownLeft(actorId, refrId);
  if (wait > 0) return 'The seam needs ' + wait + ' more seconds to be worth striking.';

  const yielded = randInt(1, 1 + tier);
  if (!addItem(actorId, ITEMS.saltPile, yielded)) return 'The seam yields nothing you can carry.';
  stampCooldown(actorId, refrId);
  let extra = '';
  if (tier >= 3 && Math.random() < 0.12 * (tier - 2)) {
    const rare = [ITEMS.fireSalts, ITEMS.frostSalts, ITEMS.voidSalts][randInt(0, 2)];
    addItem(actorId, rare, 1);
    extra = ' Something rarer came away with it.';
  }
  return 'You work ' + yielded + ' salt from the seam.' + extra;
}

/** Charcoal kiln: firewood in, graded charcoal out. Tier sets the grade. */
function burnCharcoal(actorId, refrId) {
  const tier = tierOf(actorId, 'woodcutter');
  if (tier < 1) return 'You need the Novice woodcutting manual before you can run a kiln.';

  const wait = cooldownLeft(actorId, refrId);
  if (wait > 0) return 'The kiln is still burning. ' + wait + ' seconds.';

  const cost = 3;
  if (!takeItem(actorId, ITEMS.firewood, cost)) {
    return 'The kiln needs ' + cost + ' firewood.';
  }
  const grade = ['charcoalT1', 'charcoalT1', 'charcoalT2', 'charcoalT3', 'charcoalT4'][tier] || 'charcoalT1';
  addItem(actorId, ITEMS[grade], 1);
  stampCooldown(actorId, refrId);
  return 'The kiln yields ' + grade.replace('charcoalT', 'grade ') + ' charcoal.';
}

// ---------------------------------------------------------------------------
// character creation
//
// SkyMP has no connect event for the gamemode, and callPapyrusFunction runs on
// the server's own VM: Debug.Notification and Message.Show both resolve their
// target actor from the Papyrus stack, which is empty when the call comes from
// here. So there is no reliable way to put words on somebody's screen from this
// file, and a menu that asks a question and waits for the answer is out of the
// question entirely.
//
// What does work, on mechanisms already proven in this build: the inventory can
// be set from the server, and reading a book from the inventory comes back as
// onReadBook(actorId, baseId). So the books are the interface. Each one says
// what it does in its own text, which the game renders in its own book UI, and
// reading it is the choice. Nothing here depends on a message arriving.
//
// The state machine is driven by a timer rather than an event, because there is
// no event. It is cheap: a property read per online person every few seconds.
// ---------------------------------------------------------------------------

const CHARGEN_PROPERTY = 'thornswoodChargen';
const CHARGEN_TICK_MS = 3000;

/**
 * How long to leave a client completely alone after it turns up online.
 *
 * A joining client is mid save-load: SkyrimPlatform writes a TESMODPLATFORM
 * save, loads it, and the game rebuilds the player's facegen from the TESNPC
 * record on the way through. Anything the server does to that actor lands in
 * the middle of it. SkyMP's own SpSnippetService already treats this as
 * dangerous, wrapping ShowRaceMenu in a one second delay and switching off form
 * view updates around it.
 */
const SETTLE_MS = 10000;

const firstSeen = new Map();   // actorId -> when it first appeared online

/* Skyrim Unbound's own character generation room, which is where a new game
 * already puts everybody, and the marker it stands them on. Falling back to the
 * configured start point is deliberate: if Unbound is ever removed from the load
 * order the flow should still run, just in a less tidy place. */
const HALL = {
  desc: '19bad4:Skyrim Unbound.esp',
  pos: [3755.7, -495.7, -207.7],
  rot: [0, 0, 180],
};

const WELCOME_BOOK = 'e80000:Thornswood-Content.esp';

/* Something to wear while choosing. The race menu hands you back with an empty
 * inventory, and standing naked in a stone room reading a writ is nobody's idea
 * of a first morning. The client side menu plugin puts these on for you; without
 * it they are simply in your pack. */
const SHIFT = [
  ['1be1a:Skyrim.esm', 1],   // farm clothes
  ['1be1b:Skyrim.esm', 1],   // boots
];

/* Reading a writ settles the trade and hands over the gear. Counts are small on
 * purpose: this is a first morning, not a reward. */
const CLASSES = {
  'e80010:Thornswood-Content.esp': {
    key: 'warrior',
    gear: [
      ['12e49:Skyrim.esm', 1], ['12e4b:Skyrim.esm', 1],
      ['12e46:Skyrim.esm', 1], ['12e4d:Skyrim.esm', 1],
      ['12eb7:Skyrim.esm', 1], ['12eb6:Skyrim.esm', 1],
      ['3eadd:Skyrim.esm', 2], ['f:Skyrim.esm', 50],
    ],
  },
  'e80011:Thornswood-Content.esp': {
    key: 'ranger',
    gear: [
      ['13911:Skyrim.esm', 1], ['13910:Skyrim.esm', 1],
      ['13912:Skyrim.esm', 1], ['13913:Skyrim.esm', 1],
      ['13985:Skyrim.esm', 1], ['1397d:Skyrim.esm', 60],
      ['1397e:Skyrim.esm', 1], ['3eae5:Skyrim.esm', 2],
      ['f:Skyrim.esm', 50],
    ],
  },
  'e80012:Thornswood-Content.esp': {
    key: 'mage',
    gear: [
      ['10710a:Skyrim.esm', 1], ['d1921:Skyrim.esm', 1],
      ['9cd51:Skyrim.esm', 1], ['9e2af:Skyrim.esm', 1],
      ['2e4e2:Skyrim.esm', 2], ['3eae0:Skyrim.esm', 2],
      ['f:Skyrim.esm', 50],
    ],
  },
  'e80013:Thornswood-Content.esp': {
    key: 'smith',
    gear: [
      ['5b69f:Skyrim.esm', 1], ['5b69e:Skyrim.esm', 1],
      ['5ace4:Skyrim.esm', 5], ['5ace5:Skyrim.esm', 2],
      ['800e4:Skyrim.esm', 10], ['b27b:Thornswood-Content.esp', 1],
      ['f:Skyrim.esm', 50],
    ],
  },
  'e80014:Thornswood-Content.esp': {
    key: 'miner',
    gear: [
      ['80697:Skyrim.esm', 1], ['80699:Skyrim.esm', 1],
      ['e3c16:Skyrim.esm', 1], ['1d4ec:Skyrim.esm', 2],
      ['b276:Thornswood-Content.esp', 1], ['f:Skyrim.esm', 50],
    ],
  },
  'e80015:Thornswood-Content.esp': {
    key: 'forager',
    gear: [
      ['4223c:Skyrim.esm', 1], ['4223d:Skyrim.esm', 1],
      ['2f2f4:Skyrim.esm', 1], ['15489:Thornswood-Content.esp', 1],
      ['e80001:Thornswood-Content.esp', 1], ['65c97:Skyrim.esm', 3],
      ['f:Skyrim.esm', 50],
    ],
  },
};

/* Each passage names a town whose arrival point the respawn table already
 * carries, so a starting location and a resurrection point are the same kind of
 * thing and there is only one table to keep right. */
const PASSAGES = {
  'e80020:Thornswood-Content.esp': 'whiterun',
  'e80021:Thornswood-Content.esp': 'solitude',
  'e80022:Thornswood-Content.esp': 'windhelm',
  'e80023:Thornswood-Content.esp': 'markarth',
  'e80024:Thornswood-Content.esp': 'riften',
  'e80025:Thornswood-Content.esp': 'ravenrock',
};

function chargenOf(actorId) {
  let s = null;
  try {
    s = mp.get(actorId, CHARGEN_PROPERTY);
  } catch (e) {
    s = null;
  }
  if (!s || typeof s !== 'object') return null;
  return s;
}

function setChargen(actorId, state) {
  mp.set(actorId, CHARGEN_PROPERTY, state);
}

/** Add or remove a set of [descriptor, count] pairs in one inventory write. */
function giveItems(actorId, pairs, sign) {
  const inv = mp.get(actorId, 'inventory') || { entries: [] };
  const entries = (inv.entries || []).slice();
  for (const pair of pairs) {
    const baseId = idOf(pair[0]);
    if (!baseId) {
      log('chargen: no form for', pair[0], '- skipped');
      continue;
    }
    const want = pair[1] * sign;
    let at = -1;
    for (let i = 0; i < entries.length; i++) {
      if (entries[i].baseId === baseId) { at = i; break; }
    }
    if (at === -1) {
      if (want > 0) entries.push({ baseId: baseId, count: want });
      continue;
    }
    entries[at].count += want;
    if (entries[at].count <= 0) entries.splice(at, 1);
  }
  mp.set(actorId, 'inventory', { entries: entries });
}

/** Every writ, or every passage, as [descriptor, 1] pairs. */
function oneOfEach(table) {
  const out = [];
  for (const d in table) out.push([d, 1]);
  return out;
}

/** Put somebody in the creation hall. Once, at the moment the stage opens. */
function sendToHall(actorId) {
  const cell = idOf(HALL.desc);
  if (!cell) {
    log('chargen: the creation hall is not in this load order, staying put');
    return false;
  }
  mp.set(actorId, 'locationalData', {
    cellOrWorldDesc: HALL.desc,
    pos: HALL.pos,
    rot: HALL.rot,
  });
  return true;
}

/**
 * Open the creation stage. Deliberately does NOT touch the race menu.
 *
 * The Spawn system already calls setRaceMenuOpen, in both of its branches: on
 * the create path for a brand new character, and on the load path for one whose
 * appearance has been cleared. Calling it again from here was a second
 * ShowRaceMenu landing across the client's save load, on top of a teleport, and
 * it is the only new thing in the neighbourhood of the crash we saw. Watching
 * for the appearance to arrive is all this needs to do.
 */
function beginAppearance(actorId) {
  const state = { stage: 'appearance', at: Date.now() };

  // startPoints already puts a new character in the hall, so the common case
  // moves nobody. This is for a character whose appearance was cleared while
  // they were standing somewhere else.
  let where = null;
  try {
    where = mp.get(actorId, 'worldOrCellDesc');
  } catch (e) {
    where = null;
  }
  if (where && where !== HALL.desc) {
    if (sendToHall(actorId)) {
      state.moved = true;
    }
  }

  setChargen(actorId, state);
  log('chargen', actorId.toString(16), '-> appearance',
      state.moved ? '(moved to the hall)' : '(already in the hall)');
}

function beginClass(actorId, state) {
  giveItems(actorId, SHIFT.concat([[WELCOME_BOOK, 1]]).concat(oneOfEach(CLASSES)), +1);
  state.stage = 'class';
  state.at = Date.now();
  setChargen(actorId, state);
  log('chargen', actorId.toString(16), '-> class');
}

function chooseClass(actorId, state, desc) {
  const cls = CLASSES[desc];
  giveItems(actorId, oneOfEach(CLASSES), -1);
  giveItems(actorId, cls.gear.concat(oneOfEach(PASSAGES)), +1);
  state.stage = 'destination';
  state.class = cls.key;
  state.at = Date.now();
  setChargen(actorId, state);
  log('chargen', actorId.toString(16), 'class =', cls.key, '-> destination');
}

function chooseDestination(actorId, state, desc) {
  const town = PASSAGES[desc];
  const arrival = arrive(town, null, 'chargen', PREFER_SLOT, 'chosen');
  giveItems(actorId, oneOfEach(PASSAGES).concat([[WELCOME_BOOK, 1]]), -1);

  if (!arrival) {
    log('chargen', actorId.toString(16), 'no arrival for', town, '- staying in the hall');
    return;
  }
  mp.set(actorId, 'spawnPoint', {
    cellOrWorldDesc: arrival.desc,
    pos: arrival.pos,
    rot: arrival.rot,
  });
  mp.set(actorId, 'locationalData', {
    cellOrWorldDesc: arrival.desc,
    pos: arrival.pos,
    rot: arrival.rot,
  });
  state.stage = 'done';
  state.destination = town;
  state.at = Date.now();
  setChargen(actorId, state);
  log('chargen', actorId.toString(16), 'destination =', town,
      '(' + arrival.cell + ') -> done');
}

/**
 * One pass over everybody online.
 *
 * The only transition the timer owns is appearance -> class, because the race
 * menu closing is not an event either: the appearance simply turns up on the
 * change form, and this notices. The rest is driven by onReadBook.
 */
function chargenTick() {
  let online;
  try {
    online = mp.get(0, 'onlinePlayers');
  } catch (e) {
    return;
  }
  if (!Array.isArray(online)) return;

  const now = Date.now();

  // Anyone who has gone offline should not keep a slot in the settle table.
  const here = new Set(online);
  for (const id of Array.from(firstSeen.keys())) {
    if (!here.has(id)) {
      firstSeen.delete(id);
    }
  }

  for (const actorId of online) {
    if (!firstSeen.has(actorId)) {
      firstSeen.set(actorId, now);
    }
    if (now - firstSeen.get(actorId) < SETTLE_MS) {
      continue;
    }

    let state, appearance;
    try {
      state = chargenOf(actorId);
      appearance = mp.get(actorId, 'appearance');
    } catch (e) {
      continue;
    }

    if (!state) {
      // Somebody who was already playing before this existed keeps their
      // character. Only a blank appearance means a genuinely new one.
      if (appearance) {
        setChargen(actorId, { stage: 'done', at: now, legacy: true });
        continue;
      }
      beginAppearance(actorId);
      continue;
    }

    if (state.stage === 'appearance' && appearance) {
      beginClass(actorId, state);
    }
  }
}

function startChargenTimer() {
  // Hot reload runs this file again in a fresh module, but the Node process and
  // its timers survive. Without this the ticks stack up one per save.
  const g = globalThis;
  if (g.__thornswoodChargenTimer) {
    clearInterval(g.__thornswoodChargenTimer);
  }
  g.__thornswoodChargenTimer = setInterval(guard('chargenTick', chargenTick),
                                           CHARGEN_TICK_MS);
}

/** Returns true if the book was a chargen book and has been dealt with. */
function chargenReadBook(actorId, baseId) {
  const state = chargenOf(actorId);

  for (const desc in CLASSES) {
    if (idOf(desc) !== baseId) continue;
    if (!state || state.stage !== 'class') {
      log('chargen', actorId.toString(16), 'read a writ out of turn, ignoring');
      return true;
    }
    chooseClass(actorId, state, desc);
    return true;
  }

  for (const desc in PASSAGES) {
    if (idOf(desc) !== baseId) continue;
    if (!state || state.stage !== 'destination') {
      log('chargen', actorId.toString(16), 'read a passage out of turn, ignoring');
      return true;
    }
    chooseDestination(actorId, state, desc);
    return true;
  }

  return false;
}

// ---------------------------------------------------------------------------
// event handlers
// ---------------------------------------------------------------------------

ensureProperties();
startChargenTimer();

/**
 * Set the arrival point at the moment of death, while we still know where the
 * body fell. The engine reads spawnPoint when the respawn timer expires.
 */
mp.onDeath = guard('onDeath', function (actorId, killerId) {
  const site = {
    desc: mp.get(actorId, 'worldOrCellDesc'),
    pos: mp.get(actorId, 'pos'),
  };
  const arrival = resolveArrival(site);
  if (!arrival) {
    log('onDeath', actorId, 'no arrival resolved for', site.desc, '- leaving default spawn point');
    return;
  }
  mp.set(actorId, 'spawnPoint', {
    cellOrWorldDesc: arrival.desc,
    pos: arrival.pos,
    rot: arrival.rot,
  });
  log('death', actorId, 'in', site.desc,
      '-> ' + arrival.cell + ' (' + arrival.slot + ')',
      'hold=' + arrival.hold + '(' + arrival.via + ')',
      'ground=' + arrival.reason,
      killerId ? 'killer=' + killerId : '');
});

mp.onRespawn = guard('onRespawn', function (actorId) {
  const sp = mp.get(actorId, 'spawnPoint');
  log('respawn', actorId, 'at', sp && sp.cellOrWorldDesc);
});

/**
 * Reading a manual raises the track. Books are not consumed, so re-reading is
 * harmless and grants nothing twice.
 */
mp.onReadBook = guard('onReadBook', function (actorId, baseId) {
  if (chargenReadBook(actorId, baseId)) return;

  for (const d in MANUALS) {
    if (idOf(d) !== baseId) continue;
    const m = MANUALS[d];
    if (setSkill(actorId, m.track, m.tier)) {
      log('skill', actorId, m.track, '-> tier', m.tier);
    }
    return;
  }
});

/**
 * Stations. Returning false blocks the default activation, which is what keeps
 * the furniture from playing its own idle while the server hands out the yield.
 */
mp.onActivate = guard('onActivate', function (refrId, casterRefrId) {
  if (!casterRefrId) return;
  let baseDesc;
  try {
    baseDesc = mp.get(refrId, 'baseDesc');
  } catch (e) {
    return;
  }

  let message = null;
  if (baseDesc === STATIONS.saltQuarry) message = mineSalt(casterRefrId, refrId);
  else if (baseDesc === STATIONS.charcoalKiln) message = burnCharcoal(casterRefrId, refrId);
  else return;

  notify(casterRefrId, message);
  return false;
});

log('gamemode loaded:',
    Object.keys(DATA.cellToHold).length + ' cells mapped,',
    Object.keys(MANUALS).length + ' manuals,',
    Object.keys(STATIONS).length + ' station types,',
    Object.keys(CLASSES).length + ' trades,',
    Object.keys(PASSAGES).length + ' starting towns');
