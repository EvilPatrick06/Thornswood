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
// event handlers
// ---------------------------------------------------------------------------

ensureProperties();

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

  log('station', baseDesc, 'by', casterRefrId, '-', message);
  return false;
});

log('gamemode loaded:',
    Object.keys(DATA.cellToHold).length + ' cells mapped,',
    Object.keys(MANUALS).length + ' manuals,',
    Object.keys(STATIONS).length + ' station types');
