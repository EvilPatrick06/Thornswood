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
// RETIRED 20 September. The kits it was written to put on are gone (the
// server hands out one shift, worn, and skymp5-client equips a worn entry on
// its own through pushWornState), so all it had left to do was dress people
// in whatever they picked up: a helmet or a circlet on an empty head, since
// the mask it skipped, 0x2, is slot 31 (hair) and not slot 30 (head), and
// anything else into any empty slot five seconds after a pack change. That
// is Patrick's "it is auto equipping things sometimes, like a hat". The
// file stays until the install and revert scripts that name it are changed;
// it does nothing now.
//
// Wrapped, because plugins share one global scope. A top level `function log()`
// becomes a property of that shared object, so the last plugin loaded silently
// replaces every other plugin's log, and a top level `const sp` in two files is
// a redeclaration that stops one of them loading at all.
// ---------------------------------------------------------------------------

(function () {
'use strict';

// ------------------------------------------------------------ whose game ----
// Skyrim Platform loads every plugin in Data/Platform/Plugins, whichever server
// skymp5-client is about to join. Somebody who also plays another server starts
// it from this same Skyrim, so on 2026-09-16 Thornswood's voice indicator sat
// on top of that server's menu. Whichever launcher ran last wrote
// skymp5-client-settings.txt, and its server-ip says whose game this is. Not
// ours: this file does nothing at all. Unreadable: carry on, as before.
//
// Ours is the address in Thornswood.ini's ServerAddress line when there is
// one, so a server move is an ini edit, and the fixed address below when
// there is not.
if (!thornswoodGame()) { return; }
try { skyrimPlatform.printConsole('[thornswood dress] retired: nothing is put on anybody'); } catch (e) { }
return;
function thornswoodGame() {
  const ours = ['192.135.112.23'];
  let ip = '';
  try {
    const fs = require('fs');
    try {
      const m = fs.readFileSync('Data/SKSE/Plugins/Thornswood.ini', 'utf8')
        .match(/^\s*ServerAddress\s*=\s*([^\s;]+)/m);
      if (m) { ours.push(m[1]); }
    } catch (e) { }
    let raw = fs.readFileSync('Data/Platform/Plugins/skymp5-client-settings.txt', 'utf8');
    if (raw.charCodeAt(0) === 0xFEFF) { raw = raw.slice(1); }
    ip = String((JSON.parse(raw) || {})['server-ip'] || '').trim();
  } catch (e) { return true; }
  if (ip && ours.indexOf(ip) < 0) {
    try { skyrimPlatform.printConsole('[thornswood] the client points at ' + ip + ', not this server. Plugin idle.'); } catch (e) { }
    return false;
  }
  // The client can point at us and this still not be our session: another
  // server's launcher that never rewrites the client settings leaves our
  // address in them. So the launcher leaves a note when it starts the game
  // and takes it away when the game closes. No fresh note, not our session.
  try {
    const note = String(require('fs').readFileSync('Data/Platform/thornswood-session.txt', 'utf8')).trim();
    const first = note.split(/\s+/)[0];
    let when = Number(first);         // unix milliseconds from the launcher
    if (!isFinite(when) || when < 1e12) { when = Date.parse(first); }
    if (isFinite(when) && Math.abs(Date.now() - when) < 24 * 3600 * 1000) { return true; }
    try { skyrimPlatform.printConsole('[thornswood] the launcher\'s session note is stale, so this is another server\'s session. Plugin idle.'); } catch (e) { }
  } catch (e) {
    try { skyrimPlatform.printConsole('[thornswood] the launcher left no session note, so this is another server\'s session. Plugin idle.'); } catch (e2) { }
  }
  return false;
}

const sp = skyrimPlatform;

/*
 * Equipping anything pins your weapon drawn, and nothing ever unpins it.
 *
 * Not a Skyrim bug and not this plugin's. skymp5-client hooks every animation
 * event the game sends, and in sync/animation.ts any name containing "equip"
 * that is not an unequip and not a torch becomes "SkympFakeEquip". Whoever
 * receives that calls applyWeapDrawn(actor, true), which calls
 * TESModPlatform.setWeaponDrawnMode(actor, 1), and that writes
 * share.weapDrawnMode[formId] = 1 and leaves it there. There is no expiry.
 *
 * Mode 1 is not a suggestion. FridaHooks hooks DrawSheatheWeaponPC and
 * DrawSheatheWeaponActor, and while the mode is 1 it rewrites the sheathe
 * argument into a draw on every single call. So the hands cannot go down, by
 * anybody's action, for the rest of the session.
 *
 * Which is what putting clothes on somebody does: they arrive, this equips
 * two items, and they spend the evening running around with their fists up
 * unable to hit anything.
 *
 * So the pin is taken off after dressing. -1 is WEAP_DRAWN_MODE_DEFAULT, which
 * is not "sheathed", it is "stop overriding this", and normal behaviour comes
 * back. Sheathing afterwards is what actually puts the hands down, and it also
 * makes the next outgoing movement report weapon-not-drawn, which stops the
 * server echoing the old state back and pinning it again.
 */
let pinned = false;
let pinnedAt = 0;

function unpin() {
  if (!pinned) { return; }
  pinned = false;
  const pc = player();
  if (!pc) { return; }
  try {
    sp.TESModPlatform.setWeaponDrawnMode(pc, -1);
    if (pc.isWeaponDrawn && pc.isWeaponDrawn()) {
      try { pc.sheatheWeapon(); } catch (e) { }
    }
    log('took the weapon-drawn pin back off after dressing');
  } catch (e) {
    log('could not clear the weapon-drawn pin:', e);
  }
}

// Not under Data/Platform/Plugins. SkyrimPlatform watches that folder and
// reloads every plugin whenever anything in it changes, so a log written there
// is a plugin reload per line: a black screen and a dead keyboard.
const LOG_FILE = 'Data/Platform/thornswood-dress.log';

const EVERY_MS = 5000;
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
  for (const item of wearable) {
    if (item.mask & taken) { continue; }
    try {
      pc.equipItem(item.form, false, true);
      pinned = true;
      pinnedAt = Date.now();
      taken |= item.mask;
      put++;
    } catch (e) { }
  }

  if (put) { log('put on', put, put === 1 ? 'thing' : 'things'); }
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

  // Ahead of the throttle on purpose. The pin is put on by the game a frame or
  // two after equipItem returns, so this has to be looked at every tick rather
  // than every few seconds, and it is one boolean when there is nothing to do.
  if (pinned && now - pinnedAt > 1500) { unpin(); }

  if (now - lastRun < EVERY_MS) { return; }

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
