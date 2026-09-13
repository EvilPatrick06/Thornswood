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
