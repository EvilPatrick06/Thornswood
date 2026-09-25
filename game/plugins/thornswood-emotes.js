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

/*
 * Six categories, then the emotes inside one.
 *
 * This was two flat rings of twelve, paged with Tab, and it had two problems.
 * Twenty four is not many, and finding one meant remembering which ring it was
 * on. Categories carry more without the ring getting denser, and "Revelry"
 * narrows to six things you can read at a glance.
 *
 * Every event below was pulled out of an IDLE record's ENAM field in this
 * setup's own Skyrim.esm and Dragonborn.esm, filtered to animations under
 * Actors\Character\Behaviors so they apply to a person, and checked against
 * that extract again before shipping. The name on the wheel is mine; the
 * string in `event` is the game's.
 *
 * Three to avoid, from skymp5-client's send path: anything containing 'equip'
 * is rewritten to SkympFakeEquip, and SneakStart and SneakStop are swallowed
 * outright. Nothing here trips those.
 */
const CATEGORIES = [
  { name: 'Greeting', items: [
    { name: 'Wave',        event: 'IdleWave' },
    { name: 'Salute',      event: 'IdleSalute' },
    { name: 'Bow',         event: 'IdleSilentBow' },
    { name: 'At ease',     event: 'IdleHandsBehindBack' },
    { name: 'Come here',   event: 'IdleComeThisWay' },
  ]},
  { name: 'Praise', items: [
    { name: 'Applaud',     event: 'IdleApplaud2' },
    { name: 'Ovation',     event: 'IdleApplaud4' },
    { name: 'Slow clap',   event: 'IdleApplaudSarcastic' },
    { name: 'Cheer',       event: 'IdleCivilWarCheer' },
    { name: 'Laugh',       event: 'IdleLaugh' },
  ]},
  { name: 'Gesture', items: [
    { name: 'Point',       event: 'IdlePointClose' },
    { name: 'Point yonder',event: 'IdlePointFar_01' },
    { name: 'Examine',     event: 'IdleExamine' },
    { name: 'Lean',        event: 'IdleWallLeanStart' },
    { name: 'Surrender',   event: 'IdleSurrender' },
    { name: 'Nervous',     event: 'IdleNervous' },
  ]},
  { name: 'Devotion', items: [
    { name: 'Pray',        event: 'IdlePray' },
    { name: 'Kneel',       event: 'IdleKneelingEnter' },
    { name: 'Blessing',    event: 'IdleBlessingKneelEnter' },
  ]},
  { name: 'Labour', items: [
    { name: 'Warm hands',  event: 'IdleWarmHandsStanding' },
    { name: 'Warm arms',   event: 'IdleWarmArms' },
    { name: 'Sweep',       event: 'idleLooseSweepingStart' },
    { name: 'Clean blade', event: 'IdleCleanSword' },
    { name: 'Chop wood',   event: 'IdleWoodChopStart' },
    { name: 'Write',       event: 'IdleWriteTableStandingEnter' },
    { name: 'Read',        event: 'IdleNoteRead' },
    { name: 'Drink',       event: 'idleDrinkingStandingStart' },
    { name: 'Eat',         event: 'idleEatingStandingStart' },
  ]},
  { name: 'Revelry', items: [
    { name: 'Dance',       event: 'IdleCiceroDance1' },
    { name: 'Jig',         event: 'IdleCiceroDance2' },
    { name: 'Reel',        event: 'IdleCiceroDance3' },
    { name: 'Lute',        event: 'IdleLuteStart' },
    { name: 'Flute',       event: 'IdleFluteStart' },
    { name: 'Drum',        event: 'IdleDrumStart' },
  ]},
];
/* The creation room. While you are standing in it the wheel refuses to open:
 * you are picking a face and a trade, not waving. Resolved through
 * getFormFromFile so it does not depend on a load order position. */
const HALL_LOCAL_ID = 0x19BAD4;
const HALL_PLUGIN = 'Skyrim Unbound.esp';

let open = false;
let hallId = null;

/* Which level the wheel is showing, and which category is open on the second.
 * Held here rather than in the page: the page draws a list and says which
 * wedge was clicked, and everything about what that means lives on this side. */
let level = 'cats';   // 'cats' | 'items'
let at = 0;           // index into CATEGORIES while level is 'items'

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
 * The letter a scan code prints, so the page can swallow the key that opened
 * the wheel instead of typing it into whatever has focus.
 *
 * It used to close the wheel on that key as well, because the comment here
 * said this file stops hearing the keyboard once the wheel raises browser
 * focus. That was wrong. DInputHook feeds plugins from the keyboard snapshot
 * and only withholds the buffer from the game, so buttonEvent keeps arriving
 * the whole time the wheel is up. With both ends deciding, one tap opened the
 * wheel and shut it again before it was drawn.
 *
 * Opening and closing is decided here now, in one place, by the end that knows
 * whether the wheel is already up.
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

/** The list that should be on screen right now, given the level. */
function showing() {
  if (level === 'cats') {
    return CATEGORIES.map(function (c) {
      return { name: c.name + '  (' + c.items.length + ')' };
    });
  }
  return CATEGORIES[at].items;
}

function pushRing() {
  const cats = level === 'cats';
  const title = cats ? 'Emotes' : CATEGORIES[at].name;
  const hub = cats ? 'STOP' : 'BACK';
  const hint = cats
    ? 'click, or press 1\u20136 \u00b7 Esc to close'
    : 'click, or press 1\u20139 \u00b7 Esc or the middle for the categories';

  js('window.thornswoodSetRing && window.thornswoodSetRing(' +
     JSON.stringify(showing()) + ',' +
     JSON.stringify(title) + ',' +
     JSON.stringify(hub) + ',' +
     JSON.stringify(hint) + ',' +
     JSON.stringify(LETTERS[OPEN_KEY] || '') + ')');
}

/**
 * Up one level, or shut if there is nowhere up to go.
 *
 * The one thing this must never do is close the wheel from inside a category,
 * because then opening the wrong category costs you the whole wheel and four
 * more keypresses to get back to where you were.
 */
function back() {
  if (level === 'items') { level = 'cats'; pushRing(); return; }
  setOpen(false);
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
  // Logged both ways. The last run's log had two closes in it and no opens,
  // which is what finally showed the wheel was appearing and shutting itself,
  // but only because closes happened to be logged and opens were not.
  log(v ? 'opening the wheel' : 'closing the wheel');
  if (v) {
    if (T.setTyping) { T.setTyping(false); }
    // Always from the top. Reopening into whichever category was last used is
    // a small convenience that costs you knowing where you are.
    level = 'cats';
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
/*
 * Queued on purpose, never played on the spot.
 *
 * Every Papyrus native SkyrimPlatform exposes needs a live VM and stack, and it
 * only has one for the length of a game update. main.cpp's OnUpdate sets
 * g_nativeCallRequirements.vm, runs JsTick(env, true), and nulls it again;
 * CallNativeApi throws "<name> can't be called in this context" whenever that
 * pointer is null.
 *
 * A click on the wheel does not arrive inside one of those updates. The page's
 * message comes off a CEF thread and is handed over with AddTickTask, and tick
 * tasks run under JsTick(env, false), where there is no VM. So calling
 * Debug.sendAnimationEvent straight from the browserMessage handler threw every
 * single time, which is exactly what the log showed:
 *
 *   [emotes] clicked Wave
 *   [emotes] sendAnimationEvent threw on IdleWave: Error:
 *     'Debug.sendAnimationEvent' can't be called in this context
 *
 * The keyboard shortcuts failed for the same reason by a longer road: opening
 * the wheel raises browser focus, DirectInput stops reaching the game, so
 * buttonEvent goes quiet and the page handles the digits instead, sending them
 * back down the same message path.
 *
 * Parking the name here and playing it from the update handler puts the call
 * where the VM is. The wait is at most one frame.
 */
const queued = [];

function play(event) {
  if (typeof event !== 'string' || !event.length) { return; }
  // One emote at a time. Holding a key or double clicking should not stack up
  // a dozen idles to fire on consecutive frames.
  if (queued.length) { queued.length = 0; }
  queued.push(event);
}

/**
 * Runs inside a game update, so the natives below have a VM to run on.
 *
 * Two events, a frame apart, not one.
 *
 * The call was already succeeding. The log said 'played IdleWave' with no
 * throw and nothing happened on screen, which rules out the whole message and
 * context chain and leaves Skyrim's own behaviour graph. These idles only play
 * from the default standing state: with a weapon out or fists up, the graph is
 * in a combat state that has no transition to IdleWave, so the event arrives,
 * is refused, and nobody is told.
 *
 * So the stance is dropped first and the emote follows on the next tick.
 * IdleForceDefaultState is the vanilla way out of any of those states and is
 * what the stop key already used. Sheathing as well, because a drawn weapon
 * puts the graph straight back.
 */
function drain() {
  if (!queued.length) { return; }
  const pc = player();
  if (!pc) { queued.length = 0; log('no character yet, nothing to animate'); return; }

  const event = queued.shift();

  if (event !== STOP) {
    try {
      // Only when something is actually drawn. Sheathing an empty hand is
      // harmless, but the animation it plays is not, and it would show up as
      // a small hitch before every single emote.
      if (pc.isWeaponDrawn && pc.isWeaponDrawn()) {
        sp.Debug.sendAnimationEvent(pc, STOP);
        // Put it back at the front and take it next tick, once the graph has
        // had a frame to leave the combat state.
        queued.unshift(event);
        log('dropping the ready stance first, then', event);
        return;
      }
    } catch (e) { }
  }

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
  drain();
  if (open && gameIsBusy()) { setOpen(false); }
}));

sp.on('browserMessage', guard('browserMessage', (event) => {
  const a = event.arguments;
  if (!a || a[0] !== 'thornswood-emote') { return; }
  const what = a[1];
  if (typeof what !== 'string') { return; }

  if (what === '__ready') { log('overlay is up'); return; }
  if (what === '__close') { log('the page asked to close'); setOpen(false); return; }
  if (what === '__back') { back(); return; }

  // The middle: stop whatever is playing while the categories are up, step
  // back out of a category while one is open. One target, and it always means
  // the least destructive thing available from where you are.
  if (what === '__hub') {
    if (level === 'items') { back(); return; }
    setOpen(false);
    play(STOP);
    return;
  }

  // Tab, kept as a way to walk the categories without going back up first.
  if (what === '__next') {
    if (level === 'items') { at = (at + 1) % CATEGORIES.length; pushRing(); }
    return;
  }

  if (what.indexOf('__pick ') === 0) {
    const rest = what.slice(7);
    const sp2 = rest.indexOf(' ');
    const idx = parseInt(sp2 === -1 ? rest : rest.slice(0, sp2), 10);
    const name = sp2 === -1 ? '' : rest.slice(sp2 + 1);
    if (isNaN(idx) || idx < 0) { return; }

    if (level === 'cats') {
      if (!CATEGORIES[idx]) { return; }
      at = idx;
      level = 'items';
      log('opened', CATEGORIES[idx].name);
      pushRing();
      return;
    }

    const item = CATEGORIES[at].items[idx];
    if (!item) { return; }
    log('picked', name || item.name);
    setOpen(false);
    play(item.event);
    return;
  }
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
  if (e.code === CLOSE_KEY) { back(); return; }
  if (e.code === PAGE_KEY) {
    if (level === 'items') { at = (at + 1) % CATEGORIES.length; pushRing(); }
    return;
  }
  // 1 to 9, then 0, into whichever list is showing.
  const digits = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
  const pick = digits.indexOf(e.code);
  if (pick < 0) { return; }

  if (level === 'cats') {
    if (!CATEGORIES[pick]) { return; }
    at = pick;
    level = 'items';
    pushRing();
    return;
  }
  const item = CATEGORIES[at].items[pick];
  if (item) { setOpen(false); play(item.event); }
}));

// A way out of an idle that has no natural end. Works whether or not the wheel
// is open, because the usual reason you want it is that you are stuck in one.
sp.on('buttonEvent', guard('stopKey', (e) => {
  if (e.isDown && !e.isUp && e.code === STOP_KEY && !open &&
      !(T.isTyping && T.isTyping()) &&
      !gameIsBusy() && !inCreationRoom()) {
    play(STOP);

    /*
     * The same key also takes off a stuck weapon-drawn pin, because the two
     * problems feel identical from the chair: you are locked into something
     * and want out.
     *
     * skymp5-client turns any animation event with "equip" in its name into
     * SkympFakeEquip, and whoever receives that calls
     * TESModPlatform.setWeaponDrawnMode(actor, 1). That value is stored and
     * never expires, and while it is 1 a Frida hook rewrites every sheathe
     * into a draw, so the hands cannot go down again by any means the game
     * offers. Putting clothes on is enough to trigger it.
     *
     * -1 is WEAP_DRAWN_MODE_DEFAULT, which means stop overriding rather than
     * sheathe, so the sheathe below is what actually lowers the hands.
     */
    const pc = player();
    if (pc) {
      try {
        sp.TESModPlatform.setWeaponDrawnMode(pc, -1);
        if (pc.isWeaponDrawn && pc.isWeaponDrawn()) { pc.sheatheWeapon(); }
        log('cleared the weapon-drawn pin');
      } catch (err) {
        log('could not clear the weapon-drawn pin:', err);
      }
    }
  }
}));

log('plugin loaded,', CATEGORIES.length, 'categories,',
    CATEGORIES.reduce(function (n, c) { return n + c.items.length; }, 0), 'emotes -',
    '- wheel on scan code', OPEN_KEY, '(' + (LETTERS[OPEN_KEY] || '?') + ')',
    'stop on', STOP_KEY);

})();
