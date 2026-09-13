// ---------------------------------------------------------------------------
// Thornswood emote wheel, game side.
//
// Why this can be a standalone plugin at all, rather than something welded into
// the SkyMP client: an arbitrary animation name triggered locally does reach
// everybody else. The whole chain takes any string.
//
//   send    AnimationSource hooks sendAnimationEvent and forwards whatever name
//           comes through, minus a short ignore list and a rename of anything
//           containing 'equip'. No whitelist.  (sync/animation.ts:258-285)
//   server  MpActor::SetLastAnimEvent stores it as-is. The only validator,
//           IsValidAnimEventName, guards the gamemode's JSON property, not the
//           relay.                                (MpActor.cpp:905-930)
//   receive applyAnimation calls Debug.sendAnimationEvent with the name it was
//           given. allowedAnims only ever gates *attack* animations on refs with
//           default anims disabled.               (sync/animation.ts:122-199)
//
// So: press the key, play the idle locally, and the client's own hook carries it
// to the server and out to the other four. Nothing here talks to the server
// directly and nothing here needs the gamemode to know it exists.
//
// Three names to avoid, from that same send path: anything containing 'equip'
// is rewritten to SkympFakeEquip, and SneakStart/SneakStop are swallowed
// outright. Every name in the table below was read out of an IDLE record's ENAM
// field in this setup's own Skyrim.esm and Dragonborn.esm, and none of them trip
// those rules.
//
// What changed: this used to call browser.loadUrl on a page of its own. There
// is one browser, so that threw away whatever was in it, which was the chat and
// the names above heads, and it always called last so it always won. The wheel
// is an overlay inside the front now (Data/Platform/UI/thornswood-emotes.js)
// and this file no longer loads a page, sets visibility, or sets focus. The
// front owns all three; focus is borrowed by name while the wheel is up.
// ---------------------------------------------------------------------------

(function () {
'use strict';

const sp = skyrimPlatform;
const T = (globalThis.Thornswood = globalThis.Thornswood || {});

/**
 * Keys come out of Data/SKSE/Plugins/Thornswood.ini rather than living here.
 *
 * Not for the sake of a config file: it is so the launcher's Controls page can
 * show and rebind them next to every other key in the build. That page reads
 * the real ini files at the moment you open it, which is why it cannot drift,
 * and a key hardcoded in here would be invisible to it. Values are DirectInput
 * scan codes, which is already what buttonEvent reports, so nothing has to be
 * translated.
 */
const INI = 'Data/SKSE/Plugins/Thornswood.ini';

function readIni(path) {
  const out = {};
  try {
    const fs = require('fs');
    const text = fs.readFileSync(path, 'utf8');
    for (const line of text.split(/\r?\n/)) {
      const t = line.trim();
      if (!t || t[0] === ';' || t[0] === '#' || t[0] === '[') { continue; }
      const at = t.indexOf('=');
      if (at < 0) { continue; }
      out[t.slice(0, at).trim().toLowerCase()] = t.slice(at + 1).trim();
    }
  } catch (e) {
    // no file, or unreadable. the defaults below stand.
  }
  return out;
}

const ini = readIni(INI);

function key(name, fallback) {
  const raw = ini[name.toLowerCase()];
  const n = raw === undefined ? NaN : parseInt(raw, 10);
  return isNaN(n) ? fallback : n;
}

const OPEN_KEY  = key('WheelKey', 48);   // B
const PAGE_KEY  = key('PageKey', 15);    // Tab, while the wheel is open
const CLOSE_KEY = key('CloseKey', 1);    // Escape
const STOP_KEY  = key('StopKey', 49);    // N
const CHAT_KEY  = key('ChatKey', 28);    // Enter, owned by the front
const STOP = 'IdleForceDefaultState';

// Two rings of twelve. Titles are what the wheel shows; the event is what the
// game plays. Keep each ring at twelve: the page lays them out by index.
const RINGS = [
  [
    { name: 'Wave',       event: 'IdleWave' },
    { name: 'Applaud',    event: 'IdleApplaud2' },
    { name: 'Salute',     event: 'IdleSalute' },
    { name: 'Laugh',      event: 'IdleLaugh' },
    { name: 'Cheer',      event: 'IdleCivilWarCheer' },
    { name: 'Point',      event: 'IdlePointClose' },
    { name: 'Come here',  event: 'IdleComeThisWay' },
    { name: 'Pray',       event: 'IdlePray' },
    { name: 'Warm hands', event: 'IdleWarmHandsStanding' },
    { name: 'Examine',    event: 'IdleExamine' },
    { name: 'Surrender',  event: 'IdleSurrender' },
    { name: 'Dance',      event: 'IdleCiceroDance1' },
  ],
  [
    { name: 'Drink',      event: 'IdleDrink' },
    { name: 'Eat',        event: 'idleEatingStandingStart' },
    { name: 'Lean',       event: 'IdleWallLeanStart' },
    { name: 'Sweep',      event: 'idleLooseSweepingStart' },
    { name: 'Chop wood',  event: 'IdleWoodChopStart' },
    { name: 'Write',      event: 'IdleWriteTableStandingEnter' },
    { name: 'Read',       event: 'IdleNoteRead' },
    { name: 'Flute',      event: 'IdleFluteStart' },
    { name: 'Lute',       event: 'IdleLuteStart' },
    { name: 'Drum',       event: 'IdleDrumStart' },
    { name: 'Nervous',    event: 'IdleNervous' },
    { name: 'Cough',      event: 'IdleUncontrollableCough' },
  ],
];

/* The creation room. While you are standing in it the wheel refuses to open:
 * you are picking a face and a trade, not waving. Resolved through
 * getFormFromFile so it does not depend on a load order position. */
const HALL_LOCAL_ID = 0x19BAD4;
const HALL_PLUGIN = 'Skyrim Unbound.esp';

let open = false;
let ring = 0;
let hallId = null;

// Not under Data/Platform/Plugins. SkyrimPlatform watches that folder and
// reloads every plugin whenever anything in it changes, so a log written there
// is a plugin reload per line.
const LOG_FILE = 'Data/Platform/thornswood-emotes.log';

let fsm = null;
try { fsm = require('fs'); fsm.writeFileSync(LOG_FILE, ''); } catch (e) { fsm = null; }

function log() {
  const line = '[emotes] ' + Array.prototype.slice.call(arguments).join(' ');
  try { sp.printConsole(line); } catch (e) { }
  if (fsm) { try { fsm.appendFileSync(LOG_FILE, line + '\n'); } catch (e) { fsm = null; } }
}

/**
 * The letter a scan code prints, so the page can close the wheel on the same
 * key that opened it.
 *
 * The page has to do that itself: opening the wheel raises browser focus, and
 * that withholds DirectInput from the game, so from then on buttonEvent is
 * never called and this file cannot see the key being pressed again.
 */
const LETTERS = {
  30: 'a', 48: 'b', 46: 'c', 32: 'd', 18: 'e', 33: 'f', 34: 'g', 35: 'h',
  23: 'i', 36: 'j', 37: 'k', 38: 'l', 50: 'm', 49: 'n', 24: 'o', 25: 'p',
  16: 'q', 19: 'r', 31: 's', 20: 't', 22: 'u', 47: 'v', 17: 'w', 45: 'x',
  21: 'y', 44: 'z'
};

/**
 * Every handler this plugin registers goes through here.
 *
 * SkyrimPlatform dispatches all plugins' handlers for an event together, so a
 * handler that throws can take the rest of that dispatch with it, and the rest
 * of that dispatch includes skymp5-client's own update loop. That loop is what
 * loads you into the world past the main menu. An unguarded throw in here is
 * not a bug in this plugin, it is the whole client failing to start.
 */
function guard(name, fn) {
  return function () {
    try { return fn.apply(null, arguments); }
    catch (e) { log(name, 'threw:', e && e.stack ? e.stack : e); return undefined; }
  };
}

/** Game.getPlayer throws at the main menu rather than returning null. */
function player() {
  try { return sp.Game.getPlayer() || null; } catch (e) { return null; }
}

function js(src) {
  if (T.js) { return T.js(src); }
  try { sp.browser.executeJavaScript(src); return true; }
  catch (e) { log('executeJavaScript failed:', e); return false; }
}

function pushRing() {
  js('window.thornswoodSetRing && window.thornswoodSetRing(' +
     JSON.stringify(RINGS[ring]) + ',' + ring + ',' + RINGS.length + ',' +
     JSON.stringify(LETTERS[OPEN_KEY] || '') + ')');
}

/** True while the game is showing anything of its own: a menu, or a load screen. */
function gameIsBusy() {
  try { return sp.Utility.isInMenuMode(); }
  catch (e) { return true; }   // cannot tell, so keep the wheel shut
}

/** True while the person is still in character creation. */
function inCreationRoom() {
  try {
    if (hallId === null) {
      const form = sp.Game.getFormFromFile(HALL_LOCAL_ID, HALL_PLUGIN);
      hallId = form ? form.getFormID() : 0;
    }
    if (!hallId) { return false; }   // Unbound is not loaded, so no room to be in
    const pc = player();
    const cell = pc ? pc.getParentCell() : null;
    return !!cell && cell.getFormID() === hallId;
  } catch (e) { return false; }
}

/**
 * Show or hide the wheel.
 *
 * Nothing here touches browser visibility or focus. The front holds visibility
 * on while you are playing and off in every game menu, and the focus flag is
 * claimed by name so that the chat and the wheel cannot take it from each other
 * and neither can leave it raised by accident. That flag is the one that
 * withholds DirectInput from the game, so a plugin setting it directly is a
 * plugin that can lock somebody out of their own character.
 */
function setOpen(v) {
  if (open === v) { return; }
  open = v;
  if (v) {
    if (T.setTyping) { T.setTyping(false); }
    pushRing();
    if (T.claimFocus) { T.claimFocus('wheel', true); }
  } else {
    js('window.thornswoodHideWheel && window.thornswoodHideWheel()');
    if (T.claimFocus) { T.claimFocus('wheel', false); }
  }
}

/**
 * Play an idle on the local character. The client's own sendAnimationEvent hook
 * picks it up from here; there is nothing to send by hand.
 */
function play(event) {
  const pc = player();
  if (!pc) { log('no character yet, nothing to animate'); return; }
  try {
    sp.Debug.sendAnimationEvent(pc, event);
    log('played', event);
  } catch (e) {
    log('sendAnimationEvent threw on', event + ':', e);
  }
}

// The front closes the wheel for us in a menu, but only for focus. The overlay
// itself has to be told, or it stays drawn over the inventory.
sp.on('update', guard('hold', () => {
  if (open && gameIsBusy()) { setOpen(false); }
}));

sp.on('browserMessage', guard('browserMessage', (event) => {
  const a = event.arguments;
  if (!a || a[0] !== 'thornswood-emote') { return; }
  const what = a[1];
  if (what === '__ready') { log('overlay is up'); return; }
  if (what === '__close') { log('the page asked to close'); setOpen(false); return; }
  if (typeof what === 'string' && what.indexOf('__clicked ') === 0) {
    // Proof the mouse is reaching the page. If an emote does nothing and this
    // line is missing, the click never arrived and the problem is input, not
    // animation.
    log('clicked', what.slice(10));
    return;
  }
  if (what === '__page') {
    ring = (ring + 1) % RINGS.length;
    pushRing();
    return;
  }
  setOpen(false);
  if (typeof what === 'string' && what.length) { play(what); }
}));

sp.on('buttonEvent', guard('keys', (e) => {
  if (!e.isDown || e.isUp) { return; }
  if (!T.ready) { return; }
  // While somebody is typing, every key belongs to the chat box.
  if (T.isTyping && T.isTyping()) { return; }
  if (e.code === CHAT_KEY && !open) { return; }
  if (!open && gameIsBusy()) { return; }

  if (e.code === OPEN_KEY) {
    if (open) { setOpen(false); return; }
    if (gameIsBusy()) { return; }
    if (inCreationRoom()) {
      log('still in character creation, the wheel stays shut');
      return;
    }
    setOpen(true);
    return;
  }
  if (!open) { return; }
  if (e.code === CLOSE_KEY) { setOpen(false); return; }
  if (e.code === PAGE_KEY) {
    ring = (ring + 1) % RINGS.length;
    pushRing();
    return;
  }
  // 1 to 9, then 0, as a shortcut into the ring that is showing.
  const digits = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  const at = digits.indexOf(e.code);
  if (at >= 0 && RINGS[ring][at]) {
    setOpen(false);
    play(RINGS[ring][at].event);
  }
}));

// A way out of an idle that has no natural end. Works whether or not the wheel
// is open, because the usual reason you want it is that you are stuck in one.
sp.on('buttonEvent', guard('stopKey', (e) => {
  if (e.isDown && !e.isUp && e.code === STOP_KEY && !open &&
      !(T.isTyping && T.isTyping()) &&
      !gameIsBusy() && !inCreationRoom()) {
    play(STOP);
  }
}));

log('plugin loaded,', RINGS.length, 'rings of', RINGS[0].length,
    '- wheel on scan code', OPEN_KEY, '(' + (LETTERS[OPEN_KEY] || '?') + ')',
    'stop on', STOP_KEY);

})();
