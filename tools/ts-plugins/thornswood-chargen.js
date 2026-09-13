// ---------------------------------------------------------------------------
// Thornswood: get dressed.
//
// This file used to hold the trade and location menus, drawn over books the
// server put in your pack. The launcher asks both questions now, before the
// game is even started, so the menus are gone.
//
// What went with them, by accident, was getDressed. The server puts a trade's
// kit in your inventory and nothing equips it, because equipping is a client
// side act: the server's own equipment property is what other people see you
// wearing, not what your game puts on you. So the books went and everybody
// started arriving in Windhelm with no clothes on.
//
// Hence this. It looks at what is actually in the pack and fills any empty
// armour slot with the best thing available for it, which dresses every trade
// without this file needing to know what any of them were given.
//
// Head is deliberately left alone. You have just spent time on a face.
//
// Wrapped, because plugins share one global scope. A top level `function log()`
// becomes a property of that shared object, so the last plugin loaded silently
// replaces every other plugin's log, and a top level `const sp` in two files is
// a redeclaration that stops one of them loading at all.
// ---------------------------------------------------------------------------

(function () {
'use strict';

const sp = skyrimPlatform;

// Not under Data/Platform/Plugins. SkyrimPlatform watches that folder and
// reloads every plugin whenever anything in it changes, so a log written there
// is a plugin reload per line: a black screen and a dead keyboard.
const LOG_FILE = 'Data/Platform/thornswood-dress.log';

// Quick while the kit is still arriving, slow once it has. The server defers
// the trade's gear until several seconds after the teleport, so the first
// minute is when this matters and the rest of the session is a formality.
const EVERY_MS = 2500;
const SETTLED_MS = 8000;
const BUSY_FOR_MS = 120000;
const HEAD = 0x2;            // slot 30, the face you just made
const BODY = 0x4;            // slot 32, which is what "dressed" means

let fsm = null;
try { fsm = require('fs'); fsm.writeFileSync(LOG_FILE, ''); } catch (e) { fsm = null; }

function log() {
  const line = '[dress] ' + Array.prototype.slice.call(arguments).join(' ');
  try { sp.printConsole(line); } catch (e) { }
  if (fsm) { try { fsm.appendFileSync(LOG_FILE, line + '\n'); } catch (e) { fsm = null; } }
}

/**
 * SkyrimPlatform dispatches all plugins' handlers for an event together, so a
 * handler that throws can take the rest of that dispatch with it, and the rest
 * of that dispatch includes skymp5-client's own update loop. That loop is what
 * loads you into the world. An unguarded throw in here is not a bug in this
 * plugin, it is the whole client failing to start.
 */
function guard(name, fn) {
  return function () {
    try { return fn.apply(null, arguments); }
    catch (e) { log(name, 'threw:', e && e.stack ? e.stack : e); return undefined; }
  };
}

function player() {
  try { return sp.Game.getPlayer() || null; } catch (e) { return null; }
}

function busy() {
  try { return sp.Utility.isInMenuMode(); } catch (e) { return true; }
}

let lastRun = 0;
let lastCount = -1;
let firstRun = 0;

/**
 * One pass. Only ever fills an empty slot, so somebody who takes their boots
 * off on purpose does not get them put back on, and somebody already dressed
 * is left exactly as they are.
 */
function dress(pc) {
  let n = 0;
  try { n = pc.getNumItems(); } catch (e) { return; }
  if (!n) { return; }         // nothing in the pack yet, the kit is still coming

  const wearable = [];
  let taken = 0;              // slot bits already covered

  for (let i = 0; i < n; i++) {
    let form = null;
    try { form = pc.getNthForm(i); } catch (e) { continue; }
    if (!form) { continue; }

    let armor = null;
    try { armor = sp.Armor.from(form); } catch (e) { armor = null; }
    if (!armor) { continue; }

    let mask = 0;
    try { mask = armor.getSlotMask() || 0; } catch (e) { mask = 0; }
    if (!mask) { continue; }
    if (mask & HEAD) { continue; }

    let worn = false;
    try { worn = !!pc.isEquipped(form); } catch (e) { worn = false; }
    if (worn) { taken |= mask; continue; }

    let rating = 0;
    try { rating = armor.getArmorRating() || 0; } catch (e) { rating = 0; }

    wearable.push({ form: form, mask: mask, rating: rating });
  }

  // Best first, so a smith in a steel cuirass does not end up in the farm
  // tunic that happened to come out of the list earlier.
  wearable.sort(function (a, b) { return b.rating - a.rating; });

  let put = 0;
  const names = [];
  for (const item of wearable) {
    if (item.mask & taken) { continue; }
    try {
      pc.equipItem(item.form, false, true);
      taken |= item.mask;
      put++;
      let what = '';
      try { what = item.form.getName() || ''; } catch (e) { what = ''; }
      names.push((what || '0x' + item.form.getFormID().toString(16)) +
                 ' [slots 0x' + item.mask.toString(16) + ']');
    } catch (e) { }
  }

  // Named, because "put on 2 things" was true and told us nothing: two boots
  // and two boots plus a cuirass look identical in a log and completely
  // different on a character.
  if (put) {
    log('put on', put + ':', names.join(', '));
    log('  slots now covered: 0x' + taken.toString(16),
        (taken & BODY) ? '(body is covered)' : '(BODY IS STILL BARE)');
  } else {
    log('nothing to put on.', n, 'items in the pack, slots covered: 0x' + taken.toString(16),
        (taken & BODY) ? '' : '- BODY IS STILL BARE');
  }
}

/**
 * Never stop.
 *
 * The old version declared itself finished after one pass that covered the
 * body and changed nothing, and that is exactly what the first pass looks
 * like: it runs five seconds after the character exists, which is while you
 * are still standing in the creation hall wearing whatever the start put you
 * in, long before the server has sent your trade's kit. So it said "dressed,
 * nothing more to do", switched itself off, and then skymp's own
 * applyEquipment stripped everything on the way through, which is why people
 * arrived in Windhelm with no clothes on and a log that claimed success.
 *
 * There is no state worth keeping here. Filling empty slots is idempotent:
 * running it on somebody already dressed does nothing and costs one walk of
 * the inventory. So it just keeps running, and skips the walk entirely while
 * the pack has not changed and the body is covered, which is almost always.
 */
sp.on('update', guard('tick', () => {
  const now = Date.now();
  if (!firstRun) { firstRun = now; }
  const every = (now - firstRun < BUSY_FOR_MS) ? EVERY_MS : SETTLED_MS;
  if (now - lastRun < every) { return; }

  const pc = player();
  if (!pc || busy()) { return; }
  lastRun = now;

  let n = 0;
  try { n = pc.getNumItems(); } catch (e) { return; }

  // Nothing has come in or gone out and there is something on your back, so
  // there is nothing this could usefully do.
  if (n === lastCount && wearingBody(pc)) { return; }
  lastCount = n;

  dress(pc);
}));

/**
 * Is there actually something in the body slot.
 *
 * Asked of the character rather than worked out from the inventory. The old
 * code inferred it from isEquipped while walking the pack, which answers a
 * different question and answered it about the starting clothes.
 */
function wearingBody(pc) {
  try {
    const worn = pc.getWornForm(BODY);
    if (worn) { return true; }
  } catch (e) {
    // getWornForm is SKSE and may not be there. Fall through to the slower
    // test rather than assuming either answer.
  }
  try {
    const n = pc.getNumItems();
    for (let i = 0; i < n; i++) {
      const form = pc.getNthForm(i);
      if (!form) { continue; }
      if (!pc.isEquipped(form)) { continue; }
      const armor = sp.Armor.from(form);
      if (!armor) { continue; }
      if ((armor.getSlotMask() || 0) & BODY) { return true; }
    }
  } catch (e) { }
  return false;
}

log('loaded');

})();
