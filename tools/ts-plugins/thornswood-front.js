// ---------------------------------------------------------------------------
// Thornswood front: the one plugin that owns the browser.
//
// There is exactly one browser and three things wanted it. The emote wheel
// called loadUrl on a page of its own, which replaced the chat and the names
// above heads; whichever called loadUrl last won, and since the wheel opens
// later than the front starts, the wheel always won. That is why the chat never
// appeared even after the files were installed.
//
// So one page is loaded, once, by this file, and everything else mounts itself
// into it as an overlay. Nobody else calls loadUrl, nobody else sets visible,
// and nobody else sets focused.
//
// It also fixes the address. SkyrimPlatform's default is the bare string
// 'file:///Data/Platform/UI/index.html', which CEF reads from the filesystem
// root: C:\Data\Platform\UI, which does not exist on any install. Plugins run
// in the game's own Node instance with the game folder as the working
// directory, so cwd is the anchor.
//
// Plugins share a global scope. A top level `function log()` becomes a property
// of that shared object and the last plugin loaded silently replaces everybody
// else's. Every plugin here is wrapped so nothing leaks, and anything
// deliberately shared goes on globalThis.Thornswood by name.
// ---------------------------------------------------------------------------

(function () {
  'use strict';

  // ------------------------------------------------------------ whose game ----
  // Skyrim Platform loads every plugin in Data/Platform/Plugins, whichever server
  // skymp5-client is about to join. Somebody who also plays Keizaal Online starts
  // it from this same Skyrim, so on 2026-09-16 Thornswood's voice indicator sat
  // on top of Keizaal's menu. Whichever launcher ran last wrote
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
      let when = Number(first);           // unix milliseconds from the launcher
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
  if (T.front) return;      // already loaded, do not load the page twice
  T.front = true;

  const UI_PATH = 'Data/Platform/UI/index.html';
  const OVERLAYS = ['thornswood-chat.js', 'thornswood-emotes.js', 'thornswood-voice.js',
                    'thornswood-skills.js'];
  const LOG_FILE = 'Data/Platform/thornswood-front.log';
  const INI = 'Data/SKSE/Plugins/Thornswood.ini';
  const CLIENT_SETTINGS = 'Data/Platform/Plugins/skymp5-client-settings.txt';

  const UI_URL = (function () {
    try {
      var root = process.cwd().replace(/\\/g, '/').replace(/\/+$/, '');
      return encodeURI('file:///' + root + '/' + UI_PATH);
    } catch (e) {
      return 'file:///' + UI_PATH;
    }
  })();

  // Not under Data/Platform/Plugins. SkyrimPlatform watches that folder and
  // reloads every plugin whenever anything in it changes, so a log file written
  // there is a plugin reload per line: a black screen and a dead keyboard.
  let fsm = null;
  try { fsm = require('fs'); fsm.writeFileSync(LOG_FILE, ''); } catch (e) { fsm = null; }

  function log() {
    const line = '[front] ' + Array.prototype.slice.call(arguments).join(' ');
    try { sp.printConsole(line); } catch (e) { }
    if (fsm) { try { fsm.appendFileSync(LOG_FILE, line + '\n'); } catch (e) { fsm = null; } }
  }

  function guard(name, fn) {
    return function () {
      try { return fn.apply(null, arguments); }
      catch (e) { log(name, 'threw:', e && e.stack ? e.stack : e); return undefined; }
    };
  }

  T.log = log;

  /**
   * A line in the log.
   *
   * This used to also put every line in the corner of the screen, on the
   * reasoning that a log somebody has to go and find is a round trip and if
   * enter does nothing the reason should be on screen at that moment. That was
   * true while one key was being chased and false the rest of the time, and
   * the rest of the time is what people actually play in. A pulse every five
   * seconds counting keystrokes is not something anybody should be reading
   * over their own game, next to notifications from their actual mods.
   *
   * So the log takes everything and the screen takes nothing, unless somebody
   * deliberately calls the one below.
   */
  function say(text) {
    log(text);
  }
  T.say = say;

  /**
   * A line in the corner of the screen, for the handful of things a person
   * needs to be told rather than a log needs to record.
   */
  function note(text) {
    try { sp.Debug.notification('ThornsWood: ' + text); } catch (e) { }
    log(text);
  }
  T.note = note;

  T.js = function (src) {
    try { sp.browser.executeJavaScript(src); return true; }
    catch (e) { log('executeJavaScript failed:', e); return false; }
  };

  T.ready = false;

  // ------------------------------------------------------------- settings --
  function readText(p) {
    try { return require('fs').readFileSync(p, 'utf8'); } catch (e) { return ''; }
  }

  function iniNumber(text, key, fallback) {
    const m = text.match(new RegExp('^\\s*' + key + '\\s*=\\s*(\\d+)', 'm'));
    return m ? (Number(m[1]) || fallback) : fallback;
  }

  const ini = readText(INI);
  const CHAT_KEY = iniNumber(ini, 'ChatKey', 28);       // Enter
  /*
    Profession, Class and Skill Tree. K, which was the minimap's settings
    panel until 20 September; that moved to F10 in Keys.cs and this took the
    letter, because a panel somebody opens once is worth less than the menu
    the whole progression system lives in.
  */
  const SKILLS_KEY = iniNumber(ini, 'SkillsKey', 37);   // K
  const VOICE_PORT = iniNumber(ini, 'VoicePort', 7778);
  /*
    Where voice lives when it is not just a port on the server address.
    Written by the launcher at every Play, the same way VoicePort is.
    Empty is the normal case and means the raw port, which is how this
    worked before Caddy carried /voice/.
  */
  const VOICE_URL = (function () {
    const m = ini.match(/^\s*VoiceUrl\s*=\s*(\S+)/m);
    return m ? String(m[1]).replace(/\/+$/, '') : '';
  })();
  const ESC = 1;

  const client = (function () {
    try { return JSON.parse(readText(CLIENT_SETTINGS)) || {}; } catch (e) { return {}; }
  })();
  const HOST = String(client['server-ip'] || '');

  /*
    The token that says which profile may join the voice room.

    Fetched by the launcher, which is the only thing here holding a Discord
    ticket, and left in the same folder it already uses for the push to talk
    state. Read at every injection rather than once, because a token is good
    for five minutes and this page can be rebuilt later in a session.

    Empty is not an error to report here. The service decides what to do
    with a join it cannot check, and says so in its own log.
  */
  function joinToken() {
    for (const d of ['Data/Platform/', '../Profile/']) {
      const raw = readText(d + 'voice-token.txt').trim();
      if (raw) { return raw; }
    }
    return '';
  }
  const PROFILE = Number((client.gameData || {}).profileId) || 0;

  // ---------------------------------------------------------------- focus --
  // One arbiter, because focus is the thing that kept going wrong.
  //
  // browser.setFocused(true) raises DInputHook::ChromeFocus, and while that is
  // up the game gets no keyboard and no mouse at all. skymp5-client binds Enter
  // and F6 to raise it whenever none of its own menus are open, and binds only
  // Escape to lower it, which is why an Enter pressed in the world used to
  // leave you standing in Riften unable to move.
  //
  // So nothing sets it directly. Everything that wants the mouse claims it by
  // name, and this puts the flag where the claims say it should be, every
  // frame, in both directions.
  const claims = {};

  function anyClaim() {
    for (const k in claims) { if (claims[k]) return true; }
    return false;
  }

  /**
   * True while character creation is on screen.
   *
   * The one place focus is never touched. setFocused(false) also sends a hide
   * to the game's own CursorMenu whenever the matching setFocused(true) is what
   * opened it, and that hide landing on the race menu's cursor is how the
   * cursor kept disappearing mid creation. skymp5-client already refuses to
   * raise focus there, so there is nothing to lower either.
   */
  function raceMenuOpen() {
    try { return !!sp.Ui.isMenuOpen('RaceSex Menu'); } catch (e) { return false; }
  }

  function gameMenuOpen() {
    try { return sp.Utility.isInMenuMode(); } catch (e) { return true; }
  }

  /**
   * A menu that owns the keyboard, asked for by name.
   *
   * Utility.isInMenuMode was the gate on the chat key and it is the wrong
   * question. Your log said so four times:
   *
   *     [front] chat key seen, but the game says a menu is open
   *
   * while you were standing in the world. It answers yes for things that are
   * not in anybody's way, the browser's own CursorMenu among them, which is
   * raised and lowered by the very focus handling this file does. So enter was
   * being swallowed by a menu that exists because of the chat.
   *
   * This asks about the menus that actually mean something instead. The list is
   * skymp5-client's own badMenus, which it uses for the same purpose, plus the
   * few that take text.
   *
   * Every name here is Skyrim's own, and Skyrim is not consistent about the
   * space: some have one and some do not, and Ui.isMenuOpen answers no to a
   * name that is off by a character rather than saying it has never heard of
   * it. 'Favorites Menu' was such a name. The quick favourites menu, the one
   * on Q, is 'FavoritesMenu', so for as long as somebody had it open this file
   * believed no menu was open at all: the chat key, the emote wheel, the stuck
   * watchdog and the controls watchdog all treated it as open world. The magic
   * menu was simply missing. Both are what skymp5-client's own isBadMenuShown
   * asks for, spelled the way it spells them.
   */
  const KEYBOARD_MENUS = [
    'Console', 'Crafting Menu', 'ContainerMenu', 'Dialogue Menu', 'FavoritesMenu',
    'GiftMenu', 'InventoryMenu', 'Journal Menu', 'Lockpicking Menu', 'Loading Menu',
    'MagicMenu', 'MapMenu', 'RaceSex Menu', 'StatsMenu', 'TweenMenu', 'Main Menu',
    'MessageBoxMenu', 'Book Menu', 'Sleep/Wait Menu', 'Barter Menu', 'Training Menu',
  ];

  /*
    Asked at most four times a second, not thirty times a frame.

    busyMenuOpen walks twenty menus and calls into the game for each one, and
    three update handlers call it every frame, so the real cost was about sixty
    native calls per frame for an answer that cannot change between two frames
    in any way a person could act on. A menu opening a quarter of a second
    later than it might have is not something anybody can see; sixty calls a
    frame is.
  */
  const MENU_CACHE_MS = 250;
  let menuCachedAt = 0;
  let menuCached = '';

  function busyMenuOpenNow() {
    let asked = false;
    for (const name of KEYBOARD_MENUS) {
      try {
        if (sp.Ui.isMenuOpen(name)) { return name; }
        asked = true;
      } catch (e) { }
    }
    // Ui.isMenuOpen answered nothing at all, so fall back to the blunt test
    // rather than handing the keyboard over blind.
    if (!asked) { return gameMenuOpen() ? 'a menu' : ''; }
    return '';
  }

  function busyMenuOpen() {
    const now = Date.now();
    if (now - menuCachedAt < MENU_CACHE_MS) { return menuCached; }
    menuCachedAt = now;
    menuCached = busyMenuOpenNow();
    return menuCached;
  }

  // Menus the game can raise while the browser holds the keyboard, which is
  // to say the ones that need no key press: a load screen, a quit, a forced
  // message box, somebody talking to you.
  const SELF_OPENING_MENUS = [
    'Loading Menu', 'Main Menu', 'MessageBoxMenu', 'Dialogue Menu', 'RaceSex Menu',
  ];

  function interrupted() {
    for (const name of SELF_OPENING_MENUS) {
      try { if (sp.Ui.isMenuOpen(name)) { return name; } } catch (e) { }
    }
    return '';
  }

  // Focus that is up while nothing here claimed it, and since when.
  let strayFocusSince = 0;

  /**
   * Put the focus flag where the claims say it should be.
   *
   * The line that used to be here said: if nothing wants focus and the race
   * menu is open, leave it alone. That was to protect the cursor, because
   * setFocused(false) also sends a hide to the game's own CursorMenu. What it
   * actually built was a trap with no way out.
   *
   * Something raised focus during character creation. While focus is up
   * DirectInput is withheld from the game, so escape, enter and every other
   * key did nothing, and the one thing that could have put it back refused to,
   * for as long as the race menu was open, which was forever because you
   * cannot finish a race menu you cannot press a key in. Your log shows it
   * exactly: one line saying keys work, and then nothing ever again.
   *
   * So the guard is now a pause rather than a veto. A second of grace, which
   * covers the flicker it was written for, and then the keyboard comes back
   * whatever is on screen. A cursor that blinks is a cosmetic problem. A
   * keyboard that never returns is somebody closing the game through the task
   * manager.
   */
  function applyFocus() {
    let up;
    try { up = !!sp.browser.isFocused(); } catch (e) { return; }
    const want = anyClaim();

    if (up === want) { strayFocusSince = 0; return; }

    if (!want) {
      if (!strayFocusSince) { strayFocusSince = Date.now(); }
      const waited = Date.now() - strayFocusSince;
      if (raceMenuOpen() && waited < 1200) { return; }
      if (waited >= 1200) {
        say('something took the keyboard and nothing here asked for it, taking it back');
      }
    }

    try { sp.browser.setFocused(want); } catch (e) { }
    strayFocusSince = 0;
  }

  T.claimFocus = function (who, on) {
    if (!!claims[who] === !!on) return;
    claims[who] = !!on;
    // Logged every time, because a claim that goes up and does not come down is
    // indistinguishable from the game freezing: focus withholds DirectInput,
    // so the keyboard stops reaching the game AND stops reaching every plugin
    // that would otherwise notice something was wrong. When somebody says a
    // key locked everything up, this line is the only place the answer lives.
    say('focus ' + (on ? 'claimed by ' : 'released by ') + who +
        ' (holding: ' + (Object.keys(claims).filter(function (k) { return claims[k]; })
                          .join(', ') || 'nobody') + ')');
    applyFocus();
  };
  T.hasFocus = function (who) { return !!claims[who]; };

  // ---------------------------------------------------------------- typing --
  // Asked for, not taken.
  //
  // The keyboard is only handed over once the page has said it has a box to
  // type into, and it is handed back on a message from the page.
  //
  // This used to say that a plugin cannot watch for the key that would undo
  // what it just did, because raising focus withholds DirectInput and
  // buttonEvent is built from the game's own input. That is half right and the
  // wrong half mattered. DInputHook::GetDeviceData reads the keyboard, calls
  // ProcessKeyboardData, which is what feeds buttonEvent, and only THEN checks
  // ChromeFocus and zeroes the length:
  //
  //     if (hr == DI_OK) { ProcessKeyboardData(rawData); ... }
  //     if (DInputHook::ChromeFocus()) { *outDataLen = 0; return result; }
  //
  // So the game is starved and the plugins are not. Escape below is reachable
  // the whole time focus is up, and the cap further down does not need any key
  // at all. Both exist because everything that routes through the page is one
  // stopPropagation away from leaving somebody frozen.
  //
  // Which is exactly what went wrong. Enter raised focus whether or not
  // anything had drawn a chat box, and when there was no box there was nothing
  // on screen and nothing listening: a cursor, no movement, and a fight to get
  // back out.
  let asked = 0;        // when we last asked the page to take the keyboard
  let beat = 0;         // when the page last said it still has it
  let heldSince = 0;    // when the keyboard was handed over, for the hard cap
  let boxReady = false; // the page has said, once, that it has a chat box

  function wantTyping(on) {
    if (on) {
      if (claims.chat) return;

      // Once the page has reported a box, the keyboard goes over immediately
      // and the page is told afterwards. Waiting for the answer first was
      // correct and slow: a round trip through executeJavaScript, the page's
      // reply, and the next update tick, during which enter did nothing and a
      // second press did nothing either, because `asked` was set.
      //
      // The safety that made the wait worth it is still here and does not need
      // the wait: the heartbeat below takes the keyboard back on its own if the
      // page stops answering, and typing-fail takes it back at once.
      if (boxReady) {
        beat = Date.now();
        heldSince = Date.now();
        T.claimFocus('chat', true);
        T.js('try{if(window.thornswoodChat){window.thornswoodChat.focusInput();window.thornswoodChat.state();}else{window.skyrimPlatform.sendMessage("thornswood-front","the page has no chat object, so there is nothing to type into");}}catch(e){try{window.skyrimPlatform.sendMessage("thornswood-front","focusInput threw "+e);}catch(e2){}}');
        return;
      }

      if (asked) return;
      asked = Date.now();
      T.js('try{if(window.thornswoodChat){window.thornswoodChat.focusInput();window.thornswoodChat.state();}else{window.skyrimPlatform.sendMessage("thornswood-front","the page has no chat object, so there is nothing to type into");}}catch(e){try{window.skyrimPlatform.sendMessage("thornswood-front","focusInput threw "+e);}catch(e2){}}');
      return;
    }
    asked = 0;
    heldSince = 0;
    if (!claims.chat) return;
    T.js('try{window.thornswoodChat&&window.thornswoodChat.blurInput();}catch(e){}');
    // Not waiting for the answer. If the page is in a state where it cannot
    // reply, the keyboard has to come back anyway.
    T.claimFocus('chat', false);
  }

  T.setTyping = wantTyping;
  T.isTyping = function () { return !!claims.chat; };

  // Said once, so a log with nothing in it can be told apart from a log that
  // never had anything to say. If this line is missing, the plugin is not being
  // given key events at all and nothing below it can possibly work.
  let sawAnyKey = false;

  /*
   * A pulse, so a lock can be told apart from the two things it looks like.
   *
   * When the keyboard dies the moment the microphone opens, there are two
   * completely different worlds and no way to tell them apart from the chair:
   *
   *   keys still arriving here  the game is being starved on purpose, which
   *                             means something has raised browser focus and
   *                             DInputHook is zeroing the game's read while
   *                             still feeding plugins.
   *   keys stop here too        DirectInput itself is gone, which is the game
   *                             losing the device rather than anybody taking
   *                             it, and nothing in this build can cause that
   *                             by raising a flag.
   *
   * Every fix so far has been aimed at the first world on the assumption it
   * was that one. This says which it is. Five seconds is often enough to see
   * the gap and rare enough to read.
   */
  let keysSeen = 0;

  /*
   * The last twenty key presses, so the thing that opens the console has to
   * say which key it is on.
   *
   * The console opening is the lock. Two config changes aimed at the two mods
   * whose hotkeys collide with keys held while playing did not stop it, which
   * means the opener is a third thing and guessing at mod lists one at a time
   * is not converging. Every key press passes through this file already, so
   * the cheapest possible answer is to remember the recent ones and print them
   * the moment the console appears. Whatever scan code is sitting at the end
   * of that list is the hotkey, and the hotkey names the mod.
   *
   * Twenty entries of two numbers. It costs nothing and it is only ever read
   * on the one event that matters.
   */
  const recentKeys = [];

  function rememberKey(code) {
    recentKeys.push([code, Date.now()]);
    if (recentKeys.length > 20) { recentKeys.shift(); }
  }

  function recentKeysText() {
    if (!recentKeys.length) { return 'nothing at all'; }
    const now = Date.now();
    const parts = [];
    for (let i = 0; i < recentKeys.length; i++) {
      parts.push(recentKeys[i][0] + ' (' + (now - recentKeys[i][1]) + 'ms ago)');
    }
    return parts.join(', ');
  }
  let lastPulse = 0;

  /*
   * The console opens by itself, and while it is open the game ignores you.
   *
   * That is the whole lockup. The pulse caught it:
   *
   *     input: 173 keys in 5s, browser focus no, menu yes [Console Native UI Menu]
   *
   * 173 keys means the keyboard is fine and the plugin is getting every press.
   * The game is not, because a menu has the input, and the menu is the
   * console. Stuck running follows from the same thing: the last movement the
   * game saw is the last one it will ever see, so the character keeps going.
   *
   * Nobody opened it. It appears on its own, and so far only ever within a
   * second or two of the browser opening a capture device, which is why this
   * looked like a microphone problem for most of a day.
   *
   * Shut it. TESModPlatform.CloseMenu queues a hide for a menu by name, and it
   * is bound in the VM even though the generated type declarations predate it,
   * which is why this goes through the proxy rather than a typed call.
   *
   * Deliberately not conditional on anything. There is no legitimate way for
   * this menu to be open on this build: the console is not how anybody plays
   * here, and a console somebody opened on purpose being shut is a smaller
   * problem than a console nobody opened taking the keyboard.
   */
  /*
   * The client switching itself to single player, said out loud.
   *
   * skymp5-client used to do that whenever a loadGame event arrived that it did
   * not believe it caused: message box, connection closed, syncing stopped.
   * Both halves were invisible from here. The modal took the keyboard, and the
   * disconnect is why the character carried on running with nothing correcting
   * them.
   *
   * It fired on every launch, because Skyrim has no command line for loading a
   * save and this build uses po3_StartOnSave to walk into the right character.
   * That load is real and SkyMP did not cause it, so the guard was right about
   * the facts and wrong about what they meant.
   *
   * The disconnect is patched out in skymp5-client.js and the count is kept
   * here instead, because how often this happens is worth knowing even now
   * that it costs nothing.
   */
  let saidSingle = 0;
  let saidMove = 0;

  sp.on('update', guard('singleplayer', () => {
    let n = 0;
    try { n = Number(globalThis.__thornswoodUncausedLoad) || 0; } catch (e) { return; }
    if (n <= saidSingle) { return; }
    saidSingle = n;
    say('a save was loaded that SkyMP did not cause (' + n + ' so far). ' +
        'still connected; this used to disconnect and lock the keyboard.');
  }));

  /*
   * Which of the two spawn paths put the character in the world.
   *
   * skymp5-client has two and they race on one flag. One moves the character
   * with moveRefrToPosition. The other writes a save on the spot and loads it,
   * which on this build means reverting the save po3_StartOnSave just finished
   * loading and never coming back out of it. That is the infinite loading
   * screen, and the second path is now told to stand down whenever there is
   * already a game to be in.
   *
   * Worth a line in the log either way. If this stops appearing, the spawn went
   * back through the load and the loading screen is the next thing to expect.
   */
  sp.on('update', guard('spawnpath', () => {
    let n = 0;
    try { n = Number(globalThis.__thornswoodSpawnedByMove) || 0; } catch (e) { return; }
    if (n <= saidMove) { return; }
    saidMove = n;
    say('spawn: the save reload stood down, moving the character instead (' +
        n + ' so far)');
  }));

  /*
   * Every activation, said out loud.
   *
   * Handles, levers and cages do nothing when pressed, and taking the
   * activation block off activators did not change it, which makes sense now:
   * dealWithRef only ever runs on refs the server already knows about, and a
   * lever in a dungeon is not one of those. So it was never blocked by us and
   * something else is eating it.
   *
   * There are only three things it can be and this tells them apart in one
   * press. No line at all means the game never registered an activation, so
   * the press is being lost before anything here sees it. A line with blocked
   * yes means something set blockActivation on that ref and it is still set. A
   * line with blocked no, followed by nothing happening on screen, means the
   * activation ran and the Papyrus script behind it did not, which is a
   * different problem in a different place.
   */
  // Set while we are re-activating something, so our own call does not come
  // back through this handler and recurse.
  let reActivating = false;
  let lastActivateAt = 0;
  const lastForced = {};

  /*
    Bases the server answers for, so they are not activated twice.

    Every ACTI below is re-activated with default processing off, because some
    vanilla handle and lever scripts never start under SkyMP. The client
    forwards that second activation too, so anything the server handles ran
    twice per press: a quarry strike and then "the seam needs 20 more seconds".

    The gamemode writes the list into the same folder this file already probes,
    as runtime form ids. Until it arrives the set is empty, which is exactly
    the behaviour this file had before, so a server that has not been deployed
    yet changes nothing.
  */
  const serverBases = {};
  let serverBasesAsked = 0;
  /* target -> when its activation was last written down. See the log line
     in the activate handler: one per press was one per door in the town. */
  const lastLogged = {};

  /*
   * Which browser backend is actually running.
   *
   * SkyrimPlatform has two: tilted, which is the original CEF stack living in
   * src/tilted and is where DInputHook, ChromeFocus and every input bug chased
   * in this file comes from, and nirnlab, which replaces it with the NirnLab UI
   * Platform SKSE plugin. BrowserApi.cpp picks between them from
   * SkyrimPlatform.ini, and "auto" is NOT a choice: it logs "Auto mode not
   * implemented yet" and falls back to tilted, which upstream's own source
   * calls legacy.
   *
   * Worth one line at startup, because the difference decides whether
   * BrowserApiTilted::SetFocused exists at all, and that function is the only
   * writer of the flag that zeroes every keyboard read.
   */
  try {
    const b = sp.browser.getBackend();
    say('browser backend: ' + ((b && b.name) || 'unknown'));
  } catch (e) {
    say('browser backend: could not ask (' + e + ')');
  }

  sp.on('activate', guard('activate', (e) => {
    // Declared here, once, for the whole handler. It used to be declared
    // further down, after the door block, and a const is not usable
    // before its line: every door press threw "Cannot access 'now'
    // before initialization" and the door rescue below never ran.
    const now = Date.now();
    lastActivateAt = now;
    if (reActivating) { return; }

    let target = 0, base = 0, type = -1, blocked = 'unknown', name = '';
    try { target = e.target ? e.target.getFormID() : 0; } catch (err) { }
    try {
      const b = e.target ? e.target.getBaseObject() : null;
      if (b) { base = b.getFormID(); type = b.getType(); name = b.getName() || ''; }
    } catch (err) { }
    try { blocked = e.target.isActivationBlocked() ? 'yes' : 'no'; } catch (err) { }
    /*
      Not a line per press.

      This wrote a line, and appended it to a file, for every activation
      anywhere in the loaded area, which in a town is every door an NPC opens
      and every crate anybody walks past. The same target within two seconds
      is the same person pressing the same thing, and is the case this was
      written to watch, so it is still logged; the rest is not.
    */
    if (!lastLogged[target] || now - lastLogged[target] > 2000) {
      lastLogged[target] = now;
      say('activate: ' + (name || 'something') +
          ' target ' + target.toString(16) +
          ' base ' + base.toString(16) +
          ' type ' + type +
          ' blocked ' + blocked);
    }

    /*
      Activators get one real activation, asked for explicitly.

      The log settled what was happening and ruled out everything cheap. The
      event fires, the ref is not blocked, and the handle still does nothing,
      and no handle or lever script appears anywhere in the Papyrus log. So the
      game registers the press and the script behind it never starts.

      This asks for the activation again with abDefaultProcessingOnly FALSE,
      which is the argument that says run the attached script rather than only
      the built in behaviour. If something upstream is consuming the press
      before the script sees it, this is the press the script gets.

      Only ACTI, because that is what a handle, a lever, a chain and a cage bar
      are. Doors and containers are left alone: their state is shared and the
      server owns it, and this would open them twice. Once every two seconds
      per ref, so holding the key down does not toggle a lever back and forth.

      If a handle starts working, that was it. If a handle now works twice, the
      script was running all along and the problem is what it is linked to. Both
      are answers.
    */
    /*
      A door the server never answers gets activated anyway, eventually.

      Cage Gate came back "type 29 blocked yes". Doors are the one thing still
      blocked on purpose, because their open state is shared and the server is
      supposed to be the one that opens them: press, the block holds, an Activate
      goes up, the server replies, the client activates. That works for a door
      somebody walks through. It cannot work for a cage gate, because what opens
      a cage gate is a chain running a Papyrus script, and the server has no
      scripts, so the reply never comes and the press is simply lost.

      So the server gets first refusal, and then this asks. A second and a half
      later, if the ref is still there, still within reach, and still in the
      same open state it was in, nothing answered and the door is activated
      properly. A load door is gone from under this long before then, and the
      distance check is the second guard against acting on one.
    */
    if (type === 29) {
      /*
        The rescue below is OFF, and it has to stay off until it can tell a
        press from an echo.

        The activate event does not only fire for the person's own press. It
        also fires when the server answers that press and the client
        activates the door on its behalf, and for whatever the game activates
        on its own while a cell loads. This code cannot tell those apart, so
        on 2026-09-16, the first day it actually ran (a misplaced const had
        thrown on its first line until then), it saw the server's own
        activation of the inn door as an unanswered press, waited a second
        and a half, and activated the door itself. That door is a load door,
        so the person was sent through it, which fired activate again, and
        they were pulled through the same door every three seconds for as
        long as they stood within reach of it: "loads in, loads in again,
        then keeps flashing".

        Cage gates stay unsolved for now. A rescue for them needs a signal
        that only a real key press produces, not the activate event.
      */
      return;
      const id = target;
      let openWas = -1;
      try { openWas = e.target.getOpenState(); } catch (err) { return; }
      if (lastForced[id] && now - lastForced[id] < 3000) { return; }
      lastForced[id] = now;

      sp.Utility.wait(1.5).then(guard('doorrescue', () => {
        const refr = sp.ObjectReference.from(sp.Game.getFormEx(id));
        if (!refr) { return; }
        let openNow = -1;
        try { openNow = refr.getOpenState(); } catch (err) { return; }
        if (openNow !== openWas) { return; }

        const pc = sp.Game.getPlayer();
        if (!pc) { return; }
        const dx = refr.getPositionX() - pc.getPositionX();
        const dy = refr.getPositionY() - pc.getPositionY();
        const dz = refr.getPositionZ() - pc.getPositionZ();
        if (Math.sqrt(dx * dx + dy * dy + dz * dz) > 400) { return; }

        try {
          reActivating = true;
          try { refr.activate(pc, false); } finally { reActivating = false; }
          say('  nothing answered for ' + (name || 'that door') +
              ', activated it here instead');
        } catch (err) {
          reActivating = false;
          say('  rescuing ' + (name || 'that door') + ' threw: ' + err);
        }
      }));
      return;
    }

    if (type !== 24) { return; }

    // The server already answers for this one, and the client forwards the
    // re-activation too, so asking again is what made every press count twice.
    if (base && serverBases[base]) { return; }

    if (lastForced[target] && now - lastForced[target] < 2000) { return; }
    lastForced[target] = now;

    try {
      const pc = sp.Game.getPlayer();
      if (!pc) { return; }
      reActivating = true;
      try {
        e.target.activate(pc, false);
        say('  asked ' + (name || 'it') + ' to run its own script');
      } finally {
        reActivating = false;
      }
    } catch (err) {
      reActivating = false;
      say('  re-activating ' + (name || 'it') + ' threw: ' + err);
    }
  }));

  /*
    A lock that has just been opened is handed straight back to the server.

    While a door or a chest is locked the client deliberately does not block it,
    so Skyrim runs its own handling and the mini game appears. The bundle does
    put the block back once the thing is no longer locked, but only the next time
    it builds a view of that reference, which is long after the pick. In between,
    the press that finishes the mini game is handled entirely by Skyrim: the chest
    swings open here and nowhere else, so the server never made this person its
    occupant and never sent the contents, and every item taken out of it is thrown
    away on arrival. That is the chest that cannot be looted.

    So the block goes back on the moment the lock opens rather than whenever the
    view is next made. This is the same flag the bundle would set itself, set
    earlier, so it is not fighting it.

    Containers and doors only. An unlocked display case is still Skyrim's.
  */
  sp.on('lockChanged', guard('lockchanged', (e) => {
    const ref = e ? e.lockedObject : null;
    if (!ref) { return; }

    let locked = true;
    try { locked = ref.isLocked(); } catch (err) { return; }
    if (locked) { return; }

    let type = -1;
    try {
      const b = ref.getBaseObject();
      type = b ? b.getType() : -1;
    } catch (err) { }
    if (type !== 28 && type !== 29) { return; }

    let id = 0;
    try { id = ref.getFormID(); } catch (err) { }

    try {
      ref.blockActivation(true);
      say('lock opened on ' + id.toString(16) + ', handed it back to the server');
    } catch (err) {
      say('could not hand ' + id.toString(16) + ' back to the server: ' + err);
    }
  }));

  /*
    A lockpick that broke is reported to the server, because the server owns
    the pack and Skyrim only destroyed it here.

    Breaking a pick is a local event. The server's copy of the inventory still
    holds it, and the re-apply a few seconds later hands it straight back, so
    picks never ran out and a lock could be worked forever.

    There is no message for this. All 34 message types in the protocol were
    read and none of them say an item was destroyed. The only ones that shrink
    a pack are put, take, drop, craft and a bow shot, and upstream solved the
    same problem for arrows by adding a message type, which needs a client we
    do not build. So this rides the one channel that already exists: the chat
    overlay's socket to the voice service, which queues any line starting with
    a slash for the gamemode to collect. It arrives a second or two late.

    A destroyed item is the one with no destination. The shipped bundle reads
    it the same way in its own drop handler, which is where the shape comes
    from.
  */
  const LOCKPICK = 0xa;
  const toServer = [];

  function tellServer(line) {
    if (line) { toServer.push(line); }
    if (toServer.length > 20) { toServer.splice(0, toServer.length - 20); }
    if (!T.ready) { return; }
    while (toServer.length) {
      const sent = T.js('try{window.thornswoodNet&&window.thornswoodNet.say(' +
                        JSON.stringify(toServer[0]) + ');}catch(e){}');
      if (!sent) { return; }
      toServer.shift();
    }
  }

  sp.on('containerChanged', guard('picks', (e) => {
    if (!e) { return; }

    let base = 0;
    try { base = e.baseObj ? e.baseObj.getFormID() : 0; } catch (err) { return; }
    if (base !== LOCKPICK) { return; }

    // Nothing received it, so it was destroyed rather than moved.
    let gone = false;
    try { gone = !e.newContainer || e.newContainer.getFormID() === 0; } catch (err) { gone = true; }
    if (!gone) { return; }

    // And it came off this person, not out of a chest somewhere.
    let mine = 0;
    try { mine = sp.Game.getPlayer().getFormID(); } catch (err) { return; }
    let from = 0;
    try { from = e.oldContainer ? e.oldContainer.getFormID() : 0; } catch (err) { return; }
    if (!mine || from !== mine) { return; }

    const n = Math.max(1, Math.min(20, Number(e.numItems) || 1));
    say('lockpick broke x' + n + ', asking the server to spend it');
    tellServer('/tspicks ' + n);
  }));

  const CONSOLE_MENUS = ['Console Native UI Menu', 'Console'];
  let consoleSince = 0;

  function shutConsole(which) {
    // Printed before the close, so it is in the log even if closing throws.
    say('the ' + which + ' is open. Keys just before it, newest last: ' +
        recentKeysText());
    try {
      sp.TESModPlatform.closeMenu(which);
      say('the ' + which + ' opened on its own and has been shut');
      return true;
    } catch (e) {
      say('the ' + which + ' opened on its own and closeMenu threw: ' + e);
      return false;
    }
  }

  sp.on('update', guard('console', () => {
    let open = '';
    for (const name of CONSOLE_MENUS) {
      try { if (sp.Ui.isMenuOpen(name)) { open = name; break; } } catch (e) { }
    }
    if (!open) { consoleSince = 0; return; }

    // A moment's grace, so a console opened and closed inside one frame is not
    // chased, and so the log records how long it was actually up.
    const now = Date.now();
    if (!consoleSince) { consoleSince = now; return; }
    if (now - consoleSince < 400) { return; }

    consoleSince = 0;
    shutConsole(open);
  }));

  /*
   * Whether the game is letting the character be driven at all.
   *
   * This is the last way the game can ignore the keyboard, and the only one
   * left standing. The pulse has now shown a lock with keys arriving here at
   * six hundred every five seconds, no menu open, and browser focus off. So
   * the keys are reaching the process, nothing is holding them, and the game
   * is deciding to do nothing with them.
   *
   * Skyrim has exactly one switch for that. EnablePlayerControls and its
   * opposite take eight flags, and with movement and looking off the character
   * stands there ignoring you while everything else in the process carries on
   * normally. Its cousin SetPlayerAIDriven hands the character to the AI, which
   * is the same silence plus the character walking off on its own, which is the
   * other half of what has been reported for days.
   *
   * Both are switched on by somebody and switched back off by the same
   * somebody, so anything that throws, disconnects or is simply never told to
   * finish leaves them stuck. There is no getter for AI driven and no way to
   * ask who did it, so this does not try to find out. It waits five seconds,
   * says which ones are off, and turns them back on.
   *
   * Five seconds because a real one is momentary. Menus are excluded outright:
   * the game switches controls off for its own menus and race creation, and
   * those turn themselves back on.
   */
  const CONTROLS = [
    ['movement', 'isMovementControlsEnabled'],
    ['fighting', 'isFightingControlsEnabled'],
    ['camera', 'isCamSwitchControlsEnabled'],
    ['looking', 'isLookingControlsEnabled'],
    ['sneaking', 'isSneakingControlsEnabled'],
    ['menus', 'isMenuControlsEnabled'],
    ['activate', 'isActivateControlsEnabled'],
    ['journal', 'isJournalControlsEnabled']
  ];

  let controlsOffNow = [];
  let controlsSince = 0;

  /*
    Two states where controls being off is the game doing its job.

    Death, and sitting in anything. The watchdog turns every control back on
    and takes the character off the AI after five seconds with no menu open,
    and neither dying nor riding a carriage opens a menu, so it fought the
    death camera and the respawn wait every time somebody was killed and it
    stood people up out of chairs, beds and carriages.

    Both answers are cheap and both are wrapped, because a build without one
    of these natives must not take the watchdog down with it.
  */
  function notOurs() {
    let pc = null;
    try { pc = sp.Game.getPlayer(); } catch (e) { return ''; }
    if (!pc) { return ''; }
    try { if (pc.isDead()) { return 'dead'; } } catch (e) { }
    try {
      const f = pc.getFurnitureReference();
      if (f) { return 'in furniture'; }
    } catch (e) { }
    return '';
  }

  /* Same reason as the menu cache above: nine native calls a frame for an
     answer that only matters once it has held for five seconds. */
  const CONTROLS_CACHE_MS = 250;
  let controlsCachedAt = 0;
  let controlsCached = [];

  function readControlsNow() {
    const off = [];
    for (const pair of CONTROLS) {
      try {
        const fn = sp.Game[pair[1]];
        if (typeof fn !== 'function') { continue; }
        if (!fn.call(sp.Game)) { off.push(pair[0]); }
      } catch (e) { }
    }
    return off;
  }

  function readControls() {
    const now = Date.now();
    if (now - controlsCachedAt < CONTROLS_CACHE_MS) { return controlsCached; }
    controlsCachedAt = now;
    controlsCached = readControlsNow();
    return controlsCached;
  }

  sp.on('update', guard('controls', () => {
    let pc = null;
    try { pc = sp.Game.getPlayer(); } catch (e) { pc = null; }
    if (!pc || busyMenuOpen()) { controlsOffNow = []; controlsSince = 0; return; }
    // Dying and sitting both switch controls off on purpose and open no menu.
    const theirs = notOurs();
    if (theirs) { controlsOffNow = []; controlsSince = 0; return; }

    const off = readControls();
    controlsOffNow = off;
    if (!off.length) { controlsSince = 0; return; }

    const now = Date.now();
    if (!controlsSince) { controlsSince = now; return; }
    if (now - controlsSince < 5000) { return; }
    controlsSince = 0;

    try {
      // Nine, not eight. Special Edition added abFastTravel to the end of both
      // EnablePlayerControls and DisablePlayerControls, and the binding counts
      // them. Passing eight threw every single time this ran, so the watchdog
      // has been reporting the problem and never once fixing it.
      sp.Game.enablePlayerControls(true, true, true, true, true, true, true, true, true);
      try { sp.Game.setPlayerAIDriven(false); } catch (e) { }
      say('the game had controls switched off with no menu open (' +
          off.join(', ') + '). turned them back on.');
    } catch (e) {
      say('tried to turn controls back on and it threw: ' + e);
    }
  }));

  /*
   * Keys arriving and the character not moving. The lock, finally stated as
   * something that can be measured.
   *
   * Every check in this file has now come back clean during a lock: keys reach
   * the plugin at four hundred every five seconds, no menu is open, the browser
   * does not have focus, all eight control flags read enabled, and DirectInput
   * reports a healthy device on every read. The console turning up is not the
   * cause either; the log shows it appearing AFTER two pulses of four hundred
   * keys, which is somebody mashing an unresponsive game and eventually hitting
   * the console key themselves.
   *
   * What is left is SetPlayerAIDriven. It hands the character to the AI, and
   * while it is on the character ignores every key with all eight control flags
   * still reading enabled, because they are enabled: they are just not what is
   * driving anybody. It is the one state in this whole search with NO getter,
   * which is exactly why it has survived every check written so far. Anything
   * that turns it on and then throws, disconnects, or is never told to finish
   * leaves it on.
   *
   * So this measures the symptom instead of the state. Somebody pressing forty
   * keys in five seconds while standing perfectly still, with no menu open and
   * not typing in chat, is not playing: they are stuck. That is the moment to
   * switch the controls back on and take the character off the AI, both of
   * which are harmless when nothing was wrong.
   *
   * Cart rides are the one legitimate AI driven moment on this server, and they
   * survive: forty key presses in five seconds is mashing, not the occasional
   * press of somebody sitting still watching the scenery.
   */
  let stuckKeys = 0;
  let stuckMoveKeys = 0;
  let stuckAt = 0;
  let stuckPos = null;
  let lastRescue = 0;

  sp.on('update', guard('stuck', () => {
    const now = Date.now();
    if (!stuckAt) { stuckAt = now; stuckKeys = 0; return; }
    if (now - stuckAt < 5000) { return; }

    const keys = stuckKeys;
    const moveKeys = stuckMoveKeys;
    stuckKeys = 0;
    stuckMoveKeys = 0;
    stuckAt = now;

    let pc = null;
    try { pc = sp.Game.getPlayer(); } catch (e) { pc = null; }

    const was = stuckPos;
    let pos = null;
    try {
      pos = pc ? [pc.getPositionX(), pc.getPositionY(), pc.getPositionZ()] : null;
    } catch (e) { pos = null; }
    stuckPos = pos;

    if (!pc || !pos || !was) { return; }

    const dx0 = pos[0] - was[0];
    const dy0 = pos[1] - was[1];
    const dz0 = pos[2] - was[2];
    const movedNow = Math.sqrt(dx0 * dx0 + dy0 * dy0 + dz0 * dz0);

    /*
      Say why this did not fire, every time it nearly did.
      A run where somebody reports being stuck and this file says nothing at
      all is a wasted run. If the conditions are wrong they can only be fixed
      by seeing which one said no.
    */
    if (keys >= 40 && movedNow <= 8) {
      const why = [];
      if (moveKeys < 2) { why.push('only ' + moveKeys + ' movement keys'); }
      if (now - lastActivateAt < 3000) { why.push('activated something ' + (now - lastActivateAt) + 'ms ago'); }
      if (claims.chat) { why.push('typing in chat'); }
      const busyName = busyMenuOpen();
      if (busyName) { why.push(busyName + ' is open'); }
      const why2 = notOurs();
      if (why2) { why.push('they are ' + why2); }
      if (lastRescue && now - lastRescue < 15000) { why.push('rescued ' + (now - lastRescue) + 'ms ago'); }
      if (why.length) {
        say('not calling it stuck: ' + keys + ' keys, ' + moveKeys +
            ' movement, moved ' + movedNow.toFixed(1) + ' units, but ' +
            why.join(' and '));
      }
    }

    if (keys < 40) { return; }
    // Somebody trying to walk, not somebody standing at something pressing E.
    if (moveKeys < 2) { return; }
    // And not somebody mid interaction: an activation in the last three
    // seconds means the game is doing something, whatever it looks like.
    if (now - lastActivateAt < 3000) { return; }
    if (claims.chat) { return; }
    if (busyMenuOpen()) { return; }
    // Somebody dead, or sitting in something, is not stuck. They are dead or
    // sitting in something, and standing them up is the bug.
    const notMine = notOurs();
    if (notMine) { return; }

    const dx = pos[0] - was[0];
    const dy = pos[1] - was[1];
    const dz = pos[2] - was[2];
    const moved = Math.sqrt(dx * dx + dy * dy + dz * dz);
    if (moved > 8) { return; }

    // Not more than once every fifteen seconds, so a genuine stuck moment does
    // not turn into something that fights the game every frame.
    if (lastRescue && now - lastRescue < 15000) { return; }
    lastRescue = now;

    say('stuck: ' + keys + ' keys in 5s (' + moveKeys +
        ' of them movement) and the character moved ' +
        moved.toFixed(1) + ' units. controls ' +
        (controlsOffNow.length ? 'off [' + controlsOffNow.join(', ') + ']' : 'on') +
        ', browser focus ' + (function () {
          try { return sp.browser.isFocused() ? 'yes' : 'no'; } catch (e) { return 'unknown'; }
        })() +
        '. Switching controls on and taking the character back off the AI.');

    try {
      sp.Game.enablePlayerControls(true, true, true, true, true, true, true, true, true);
    } catch (e) {
      say('enablePlayerControls threw: ' + e);
    }
    try {
      sp.Game.setPlayerAIDriven(false);
    } catch (e) {
      say('setPlayerAIDriven threw: ' + e);
    }
  }));

  /*
   * Jump and sprint.
   *
   * The probe that used to sit here wrote one line per press saying whether
   * the game sent the animation, whether a hook blanked it on the way, or
   * whether the behaviour graph turned it down. It has run, and the answer on
   * 19 September is the same on every press, in Data\Platform\thornswood-
   * front.log:
   *
   *   probe jump: refused, JumpDirectionalStart went through and the
   *   animation graph turned it down. stamina 100 (100%, base 100), speed
   *   369, running yes, in the air no, encumbered no, sneaking no, swimming
   *   no, mounted no, controls on
   *
   *   probe sprint: refused, SprintStart went through and the animation
   *   graph turned it down. stamina 100 (100%, base 100), running yes ...
   *
   * So the key arrives, the game sends the event, nothing blanks it, and the
   * graph says no with full stamina and every control enabled. That is the end
   * of WORKING-NOTES entry 212's diagnosis, which was SunHelm and the server
   * fighting over stamina. Stamina was never the problem.
   *
   * It is not the behaviour files either. The shipped graph was read against
   * the vanilla one it was generated from, Nemesis_0_master.xml, which sits
   * beside it: the two jump transitions, events 637 and 639, carry no
   * condition in either, and the only condition on the sprint transition,
   * event 12, is bSprintOK == 1 in both. A Nemesis patch that gated jump would
   * show up as a condition string in 0_master.hkx that the vanilla file does
   * not have, and the only one there is Precision's, about collision.
   *
   * What is left is the state of the character when the key is pressed, and
   * two states make the graph refuse both events while leaving walking and
   * running working. Neither is ever right for the person's own character:
   *
   *   AI driven   the character is handed to the AI, which walks it where the
   *               keys say and has no jump and no sprint in it. There is no
   *               getter, which is why it has survived every check in this
   *               file, and whoever turns it on is the one meant to turn it
   *               off, so anything that throws or disconnects leaves it on.
   *   IsNPC       a graph variable. Set, the graph takes the branch written
   *               for everybody who is not the person playing, and that branch
   *               has no jump or sprint transition to take.
   *
   * Both are put back where they belong on a two second heartbeat. The
   * watchdog above already did the first one, but only after somebody had
   * pressed forty keys in five seconds without moving, and a person who can
   * walk and run perfectly well never looks stuck, so it never ran for this.
   *
   * THAT WAS NOT IT, and this is written here rather than tidied away because
   * the next person will otherwise have the same idea. 1.1.53 shipped the two
   * corrections above and jump and sprint are exactly as broken. The probe
   * lines from that build say why they cannot have been the cause:
   *
   *   jump: refused, JumpDirectionalStart went through and the animation graph
   *   turned it down. stamina 100 (100%), speed 369, running yes, in the air
   *   no, bSprintOK yes, IsNPC no, bIsSynced no, bAnimationDriven no,
   *   controls on
   *
   * Every gate reads clear and both events are still refused. The corrections
   * stay because AI driven has no getter and nothing else keeps it off, but
   * they are not a fix for this and must not be reported as one.
   *
   * The useful part is bSprintOK. It is the ONLY condition on the sprint
   * transition, in 0_master and mt_behavior both. A transition being evaluated
   * cannot refuse with its only condition satisfied, so that transition is not
   * being evaluated at all: the state machine holding it is not the active one,
   * and the jump transitions live in the same place. Which is why the state
   * line now carries bIsInMT, IsFirstPerson, bAttached and currentDefaultState,
   * the four things the shipped graph uses to decide which branch is live.
   *
   * One thing ruled out cheaply and worth not repeating: the behaviour files
   * in the Thornswood game folder are byte for byte the ones in the Steam copy
   * Vortex deploys into, so this is not the folder the launcher builds.
   *
   * That does NOT mean go and try it in Skyrim through Steam. Steam updates
   * its copy on launch and every one of these servers runs a downgraded exe,
   * so that test costs the install, a re-downgrade and an Anniversary upgrade
   * nobody asked for. It was suggested here once and it was wrong.
   *
   * The four variables above answer the same question from an ordinary
   * session. bIsInMT reading no while running means the character is not in
   * the branch that holds jump and sprint, which makes this the graph. All
   * four reading normal while both events are still refused means the graph is
   * in the right place and something between the key and the graph is doing
   * it, which makes it this server. If an offline run is ever genuinely
   * needed, it is this folder's own skse64_loader.exe with MpClientPlugin.dll
   * moved aside under Checks.OffSuffix, and never Steam's copy.
   *
   * bSprintOK is held open separately, while the sprint key is down and
   * Skyrim's own rule says it should be: it is the whole of the game's
   * decision about sprinting and the one condition the graph actually reads.
   *
   * Dying, sitting in anything and riding are left alone. A cart ride is the
   * one time the AI is supposed to have the character, and it is furniture, so
   * notOurs() already names it.
   *
   * The probe stays, quieter. A press that jumps writes nothing; a press the
   * graph still refuses writes one line with the gates beside it, so a fix
   * that stops working says so instead of going quiet.
   */
  const PROBE_WINDOW_MS = 800;    // how long a key press waits for its animation
  const PROBE_GAP_MS = 1500;      // one line per action this often, however hard it is mashed
  const probeSeen = [];           // { name, out, ok, at }, from the hook
  const probePresses = [];        // { kind, at, state }, from the keys
  const probeLast = { jump: 0, sprint: 0 };
  const probeKeys = { jump: -1, sprint: -1, at: 0 };
  // A hook that never runs or always throws would make every press read
  // "no event", which is a verdict. So every line says how the hook is doing.
  let probeHookCalls = 0;
  let probeHookErrors = 0;
  /*
    And whether the flag the whole verdict rests on is ever true.

    "refused" means animationSucceeded came back false. A build where that
    property was not wired would answer false for every event in the game and
    every press would read "refused", which is a diagnosis made of nothing. The
    string is in SkyrimPlatformImpl.dll on this build, so it is real here, but
    a count costs one integer and settles it from the log instead of from a
    grep over a DLL that ships from somewhere else and can change under us.

    Any event at all counts, not only jump and sprint: JumpLand and JumpFall
    come through constantly and those succeed in a game where anything works.
    All-false across thousands is the instrument lying, not the graph refusing.
  */
  let probeHookOk = 0;
  let probeHookNo = 0;
  let probeTallyAt = 0;

  let sprintHeldSince = 0;   // while the sprint key is down, and only then
  let ownedAt = 0;           // last heartbeat that put the character back
  let saidIsNpc = false;     // each of these is worth saying once, not every tick
  let saidSprintGate = false;
  let saidNpcStuck = false;  // the readback disagreeing with the write
  let saidNpcThrew = false;

  function probeStart(kind, name) {
    return kind === 'jump' ? /^Jump(Standing|Directional)Start/i.test(name) : name === 'SprintStart';
  }

  try {
    // 0x14 to 0x14 is your own character and nobody else's.
    sp.hooks.sendAnimationEvent.add({
      enter: function (ctx) {
        probeHookCalls++;
        try {
          const name = String(ctx.animEventName || '');
          // Empty means a hook before this one already blanked it.
          if (name === '' || /^Jump/i.test(name) || name === 'SprintStart') {
            ctx.storage.set('thornswoodProbe', name);
          }
        } catch (e) { probeHookErrors++; }
      },
      leave: function (ctx) {
        try {
          // Every event that passes through, not only the ones kept below: the
          // tally is about whether the flag answers at all.
          if (ctx.animationSucceeded) { probeHookOk++; } else { probeHookNo++; }
          if (!ctx.storage.has('thornswoodProbe')) { return; }
          probeSeen.push({
            name: ctx.storage.get('thornswoodProbe'),
            out: String(ctx.animEventName || ''),
            ok: !!ctx.animationSucceeded,
            at: Date.now()
          });
          if (probeSeen.length > 32) { probeSeen.shift(); }
        } catch (e) { probeHookErrors++; }
      }
    }, 0x14, 0x14);
  } catch (e) {
    log('probe: could not hook animation events:', e);
  }

  function probeVerdict(p) {
    let blanked = false;
    for (const s of probeSeen) {
      if (s.at < p.at - 100 || s.at > p.at + PROBE_WINDOW_MS) { continue; }
      if (probeStart(p.kind, s.name)) {
        if (s.out === '') { return 'cancelled, a hook blanked ' + s.name; }
        if (!s.ok) { return 'refused, ' + s.name + ' went through and the animation graph turned it down'; }
        return 'played ' + s.name;
      }
      if (s.name === '') { blanked = true; }
    }
    if (blanked) { return 'cancelled, an animation was blanked before this file saw its name'; }
    return 'no event, the game never sent the ' + p.kind + ' animation';
  }

  /* A graph variable a build might not have must not take the caller down
     with it. False is the answer that makes everything below do nothing. */
  function varBool(pc, name) {
    try { return !!pc.getAnimationVariableBool(name); } catch (e) { return false; }
  }

  /* The same read for the log, where "not in this build" and "no" are not the
     same answer and telling them apart is the whole point of the line. */
  function varText(pc, name) {
    try { return pc.getAnimationVariableBool(name) ? 'yes' : 'no'; } catch (e) { return 'unknown'; }
  }

  function varInt(pc, name) {
    try { return String(pc.getAnimationVariableInt(name)); } catch (e) { return 'unknown'; }
  }

  /**
   * The character is the person's to drive.
   *
   * Both of these are switched on by somebody and switched back off by the
   * same somebody, so anything that throws, disconnects or is never told it
   * has finished leaves them on, and AI driven has no getter to ask. Setting
   * them off when they were already off is not a state change and costs a
   * native call, so this runs on a timer rather than trying to find out who
   * did it.
   */
  function ownTheCharacter(pc) {
    // The game switches controls off for its own menus, and race creation
    // hands the character over on purpose.
    if (busyMenuOpen()) { return; }
    // Dead or sitting in something, which includes the cart.
    if (notOurs()) { return; }
    try { if (pc.isOnMount()) { return; } } catch (e) { }

    try { sp.Game.setPlayerAIDriven(false); } catch (e) { }

    if (varBool(pc, 'IsNPC')) {
      try {
        pc.setAnimationVariableBool('IsNPC', false);
        if (!saidIsNpc) {
          saidIsNpc = true;
          say('jump and sprint: the character was flagged IsNPC, which is what takes both out of the graph. Cleared.');
        }
      } catch (e) { }
    }
  }

  /**
   * Hold the sprint gate open while the key is down.
   *
   * bSprintOK is the only condition on the sprint transition, in 0_master and
   * in mt_behavior both, so with it shut SprintStart is refused however much
   * stamina there is. Skyrim's own rule is repeated here rather than
   * overridden: no sprinting while over encumbered, out of stamina, swimming
   * or on a horse. Only while the key is actually down, so nothing is held
   * open for somebody who is not asking for it.
   */
  function holdSprintGate(pc) {
    if (!sprintHeldSince) { return; }
    // A release this file never saw, because a menu or the wheel took the
    // keyboard mid press. Eight seconds is longer than anybody sprints in one
    // hold and short enough that it cannot stay stuck.
    if (Date.now() - sprintHeldSince > 8000) { sprintHeldSince = 0; return; }
    if (anyClaim() || busyMenuOpen() || notOurs()) { return; }
    try {
      if (pc.isOverEncumbered()) { return; }
      if (pc.isSwimming() || pc.isOnMount()) { return; }
      if (pc.getActorValue('Stamina') <= 0) { return; }
    } catch (e) { return; }
    if (varBool(pc, 'bSprintOK')) { return; }
    try {
      pc.setAnimationVariableBool('bSprintOK', true);
      if (!saidSprintGate) {
        saidSprintGate = true;
        say('jump and sprint: bSprintOK was shut with stamina left, which is what refuses SprintStart. Held open while the key is down.');
      }
    } catch (e) { }
  }

  /**
   * Clear IsNPC on the frame the graph reads it, rather than every two seconds.
   *
   * ownTheCharacter() above already clears this on the heartbeat and that is
   * not enough. On 20 September seven presses in a row were refused with
   * IsNPC reading yes, in the same session whose log says the heartbeat had
   * already found it set and cleared it. So it comes back, and a clear that
   * runs up to two seconds before the press is a clear that is not there when
   * it counts.
   *
   * This is the same reason bSprintOK is held every frame just above rather
   * than polled: the graph reads the variable on the frame it handles the
   * event. A variable the graph reads on the event frame has to be written on
   * the event frame.
   *
   * The readback is the measurement the last session could not make, and it
   * splits the two remaining answers without anybody having to be in the
   * world twice. If it reads true immediately after being written false, the
   * write is not taking and no amount of timing will help. If it reads false
   * here and yes again at the press, something re-sets it in between and the
   * question becomes what.
   */
  function holdNpcClear(pc) {
    /* The same three ownTheCharacter refuses on, and for the same reasons. The
       first one matters most here: race creation hands the character over on
       purpose, and this runs on every heartbeat frame rather than only while
       somebody is asking to jump, so without it this would be writing to the
       graph all the way through a face being made. Nobody jumps while dead,
       sitting or mounted either, so none of them costs a press. */
    if (busyMenuOpen()) { return; }
    if (notOurs()) { return; }
    try { if (pc.isOnMount()) { return; } } catch (e) { }
    if (!varBool(pc, 'IsNPC')) { return; }
    try {
      pc.setAnimationVariableBool('IsNPC', false);
      if (!saidNpcStuck && varBool(pc, 'IsNPC')) {
        saidNpcStuck = true;
        say('jump and sprint: IsNPC was written false and read back true on the same frame. ' +
            'The write is not taking, so this is not the heartbeat being too slow.');
      }
    } catch (e) {
      if (!saidNpcThrew) {
        saidNpcThrew = true;
        say('jump and sprint: clearing IsNPC threw, which the heartbeat has been swallowing: ' + e);
      }
    }
  }

  function probeState() {
    let pc = null;
    try { pc = sp.Game.getPlayer(); } catch (e) { pc = null; }
    if (!pc) { return 'no character'; }
    const bits = [];
    const yn = (b) => (b ? 'yes' : 'no');
    function ask(label, fn) {
      try { bits.push(label + ' ' + fn()); } catch (e) { bits.push(label + ' unknown'); }
    }
    ask('stamina', () => Math.round(pc.getActorValue('Stamina')) + ' (' +
      Math.round(pc.getActorValuePercentage('Stamina') * 100) + '%, base ' +
      Math.round(pc.getBaseActorValue('Stamina')) + ')');
    ask('regen', () => pc.getActorValue('StaminaRate') + ' x ' + pc.getActorValue('StaminaRateMult') + '%');
    ask('speed', () => Math.round(pc.getAnimationVariableFloat('Speed')));
    ask('running', () => yn(pc.isRunning()));
    ask('sprinting', () => yn(pc.isSprinting()));
    ask('in the air', () => yn(pc.getAnimationVariableBool('bInJumpState')));
    ask('encumbered', () => yn(pc.isOverEncumbered()));
    ask('sneaking', () => yn(pc.isSneaking()));
    ask('swimming', () => yn(pc.isSwimming()));
    ask('mounted', () => yn(pc.isOnMount()));
    ask('weapon out', () => yn(pc.isWeaponDrawn()));
    // The gates themselves, so a line that says "refused" also says which one
    // said no rather than leaving the next reader to run the whole thing again.
    ask('bSprintOK', () => varText(pc, 'bSprintOK'));
    ask('IsNPC', () => varText(pc, 'IsNPC'));
    ask('bIsSynced', () => varText(pc, 'bIsSynced'));
    ask('bAnimationDriven', () => varText(pc, 'bAnimationDriven'));
    /*
      Which branch of the graph the character is actually in.

      Those four above all came back clear on 19 September and both events were
      still refused, with bSprintOK yes and SprintStart turned down anyway. That
      is the interesting part: bSprintOK is the ONLY condition on the sprint
      transition, in 0_master and in mt_behavior both, so a transition that is
      being evaluated cannot refuse with it set. It follows that the transition
      is not being evaluated, which means the state machine holding it is not the
      active one, and the jump transitions live in the same place.

      These four are what decide that. bIsInMT is a condition in the shipped
      graph in as many words. bAttached and currentDefaultState gate the attach
      of the sub-behaviours in four separate conditions. IsFirstPerson picks
      between two whole branches. None of them is forced here: they belong to
      the graph and writing them would be lying to it. They are read so the next
      line says which branch the character was in when it said no.
    */
    ask('bIsInMT', () => varText(pc, 'bIsInMT'));
    ask('IsFirstPerson', () => varText(pc, 'IsFirstPerson'));
    ask('bAttached', () => varInt(pc, 'bAttached'));
    ask('currentDefaultState', () => varInt(pc, 'currentDefaultState'));
    const theirs = notOurs();
    if (theirs) { bits.push(theirs); }
    const off = readControlsNow();
    bits.push(off.length ? 'controls off [' + off.join(', ') + ']' : 'controls on');
    return bits.join(', ');
  }

  sp.on('buttonEvent', guard('jump and sprint keys', (e) => {
    // By the game's own name for the control, so a rebound key still counts.
    // The key codes are the fallback for an event that arrives without one.
    let kind = '';
    if (e.userEventName === 'Jump' || (!e.userEventName && e.code === probeKeys.jump)) { kind = 'jump'; }
    if (e.userEventName === 'Sprint' || (!e.userEventName && e.code === probeKeys.sprint)) { kind = 'sprint'; }
    if (!kind) return;

    // Sprint is a hold, not a press, and the gate is only worth holding open
    // for as long as somebody is holding the key.
    if (kind === 'sprint') {
      if (e.isUp) { sprintHeldSince = 0; }
      else if (e.isDown && !sprintHeldSince) { sprintHeldSince = Date.now(); }
    }

    if (!e.isDown || e.isUp) return;
    // The chat or the wheel has the keyboard, or a menu does: not a jump.
    if (anyClaim() || busyMenuOpen()) return;

    // The earliest point in the frame this file gets. buttonEvent runs from
    // the input handler, before the graph updates, so a flag cleared here is
    // clear when the graph reads it. The heartbeat two seconds ago was not.
    try {
      const pressPc = sp.Game.getPlayer();
      if (pressPc) { holdNpcClear(pressPc); }
    } catch (e2) { }
    const now = Date.now();
    if (now - probeLast[kind] < PROBE_GAP_MS) return;
    probeLast[kind] = now;
    probePresses.push({ kind: kind, at: now, state: '', moving: true });
  }));

  sp.on('update', guard('jump and sprint', () => {
    const now = Date.now();
    if (now - probeKeys.at > 30000) {
      const first = !probeKeys.at;
      probeKeys.at = now;
      try { probeKeys.jump = sp.Input.getMappedKey('Jump', 0); } catch (e) { }
      try { probeKeys.sprint = sp.Input.getMappedKey('Sprint', 0); } catch (e) { }
      if (first) {
        say('jump and sprint: jump is key ' + probeKeys.jump + ', sprint is key ' +
            probeKeys.sprint + '. Every press writes a line now, the one that worked as ' +
            'well as the one that did not, with which branch of the graph the character ' +
            'was in and how many animations have succeeded at all.');
      }
    }

    // The character is only fetched on a frame that has something to do with
    // it. Three handlers in this file already ask for it every frame and that
    // is three too many.
    const heartbeat = now - ownedAt >= 2000;
    let pc = null;
    if (heartbeat || sprintHeldSince || probePresses.length) {
      try { pc = sp.Game.getPlayer(); } catch (e) { pc = null; }
    }
    if (pc) {
      // Two seconds, because this is a state that has to be wrong for a whole
      // key press to matter and nothing here is worth a native call a frame.
      if (heartbeat) { ownedAt = now; ownTheCharacter(pc); }
      // Every frame, but only while the key is down: the graph reads the gate
      // on the frame it handles the event, so a timer would miss it.
      holdSprintGate(pc);
      // Same reasoning, and this block only runs on a frame that already has
      // the character in hand: a heartbeat, a held sprint key, or a press
      // still being resolved. Sprint is a hold, so the frame the graph acts
      // on is not always the frame the key arrived.
      holdNpcClear(pc);
    }

    if (!probePresses.length) return;
    for (const p of probePresses) {
      if (!p.state) {
        p.state = probeState();
        try { p.moving = pc ? pc.getAnimationVariableFloat('Speed') > 1 : true; } catch (e) { p.moving = true; }
      }
    }
    while (probePresses.length && now - probePresses[0].at >= PROBE_WINDOW_MS) {
      const p = probePresses.shift();
      const verdict = probeVerdict(p);
      /*
        A press that worked is written down too, and it was a mistake to hide
        it. The last run wrote nothing but "refused", which reads as a graph
        turning everything down, and it was impossible to tell from the log
        whether this file had ever seen a jump succeed on any machine. One line
        per action per 1.5 s is already the limit, so it is not much noise and
        it is the difference between a measurement and an assumption.
      */
      // A sprint key pressed standing still is Skyrim saying no, not a bug, and
      // it is most of what anybody presses. That one still goes unsaid.
      if (p.kind === 'sprint' && !p.moving && verdict.indexOf('no event') === 0) { continue; }
      say(p.kind + ': ' + verdict + '. ' + p.state + '. hook saw ' +
          probeHookCalls + ' events, ' + probeHookOk + ' of them succeeded and ' +
          probeHookNo + ' did not' +
          (probeHookErrors ? ', and threw ' + probeHookErrors + ' times' : ''));
    }
  }));

  /*
   * Guards that never stop trying to kill you.
   *
   * A bounty is not what makes a guard murderous. Arrest dialogue, the pay a
   * fine or go to jail choice, is what a guard offers somebody with a bounty.
   * What turns that off is the crime faction's player enemy flag, which is set
   * when you resist arrest or fight back, and from then on they attack on
   * sight and never speak to you again.
   *
   * In a single player game that flag is cleared by dying, because dying means
   * loading a save made before any of it happened. Nobody here ever loads a
   * save. So the flag is set once, survives death, survives respawn, survives
   * logging out, and the hold is hostile forever.
   *
   * So it is cleared by hand on respawn. The bounty is deliberately left
   * alone: the crime happened and should still cost something. What comes back
   * is the guard's willingness to arrest instead of swing, which is what dying
   * is supposed to buy.
   *
   * Every hold they might belong to is covered rather than just the current
   * one, because the guards chasing you across a border belong to the hold you
   * offended, not the one you died in.
   */
  let wasDead = false;

  function calmTheGuards() {
    let pc = null;
    try { pc = sp.Game.getPlayer(); } catch (e) { return; }
    if (!pc) return;

    let cleared = 0;
    const seen = {};

    function forgive(faction) {
      if (!faction) return;
      try {
        const id = faction.getFormID();
        if (seen[id]) return;
        seen[id] = true;
        faction.setPlayerEnemy(false);
        cleared++;
      } catch (e) { }
    }

    // Stop whatever is in progress first, or they simply re-enter combat and
    // set it again a second later.
    try { pc.stopCombatAlarm(); } catch (e) { }
    try { pc.stopCombat(); } catch (e) { }

    try { forgive(pc.getCrimeFaction()); } catch (e) { }

    /*
      Whoever is actually nearby, because the faction that matters is the one
      whose guards are swinging, not the one whose land this is. There is no
      way to list actors, so this samples: findRandomActor a few dozen times
      covers everything in range long before it runs out of tries.
    */
    try {
      const x = pc.getPositionX(), y = pc.getPositionY(), z = pc.getPositionZ();
      for (let i = 0; i < 40; i++) {
        const ac = sp.Game.findRandomActor(x, y, z, 8192);
        if (!ac || ac.getFormID() === 0x14) continue;
        try { ac.stopCombatAlarm(); } catch (e) { }
        try { ac.stopCombat(); } catch (e) { }
        try { forgive(ac.getCrimeFaction()); } catch (e) { }
      }
    } catch (e) { }

    say('died and came back: cleared the resisted arrest flag on ' + cleared +
        (cleared === 1 ? ' crime faction' : ' crime factions') +
        '. Bounties are untouched, so guards will offer the fine again.');
  }

  sp.on('update', guard('guards', () => {
    let dead = false;
    try {
      const pc = sp.Game.getPlayer();
      if (!pc) return;
      dead = !!pc.isDead();
    } catch (e) { return; }

    if (dead) { wasDead = true; return; }
    if (!wasDead) { return; }

    // Alive again after being dead. Once, on the edge.
    wasDead = false;
    calmTheGuards();
  }));

  sp.on('update', guard('pulse', () => {
    const now = Date.now();
    if (!lastPulse) { lastPulse = now; return; }
    if (now - lastPulse < 5000) { return; }
    lastPulse = now;

    let focused = 'unknown';
    try { focused = sp.browser.isFocused() ? 'yes' : 'no'; } catch (e) { }
    let menu = 'unknown';
    try { menu = sp.Utility.isInMenuMode() ? 'yes' : 'no'; } catch (e) { }

    // Which menu, when there is one.
    //
    // isInMenuMode says a menu is open and says nothing about what. The last
    // run showed it turning on at the exact moment the keyboard died, which
    // rules out everything focus related and makes the name of that menu the
    // whole question: a menu the game opened deliberately is a different bug
    // from a menu that is an artefact of the window losing foreground.
    let names = '';
    if (menu === 'yes') {
      const probe = [
        'Console', 'Console Native UI Menu', 'Loading Menu', 'Main Menu',
        'MessageBoxMenu', 'Dialogue Menu', 'RaceSex Menu', 'InventoryMenu',
        'MagicMenu', 'MapMenu', 'StatsMenu', 'ContainerMenu', 'Journal Menu',
        'Sleep/Wait Menu', 'Crafting Menu', 'Book Menu', 'Lockpicking Menu',
        'Barter Menu', 'FavoritesMenu', 'TweenMenu', 'Fader Menu',
        'LoadWaitSpinner', 'Training Menu', 'GiftMenu', 'Quantity Menu',
        'Tutorial Menu', 'Credits Menu', 'TitleSequence Menu'
      ];
      const open = [];
      for (const n of probe) {
        try { if (sp.Ui.isMenuOpen(n)) { open.push(n); } } catch (e) { }
      }
      names = open.length ? (' [' + open.join(', ') + ']') : ' [none of the usual ones]';
    }

    const controls = controlsOffNow.length
      ? ', controls off [' + controlsOffNow.join(', ') + ']'
      : ', controls on';

    /*
      Which window Windows is sending the keys to.
     
      This is the last thing the pulse could not see, and it is the difference
      between a bug and somebody alt tabbing. Both look identical from in here:
      no menu, no browser focus, controls on, and either no keys arriving at all
      or keys arriving that the game does nothing with. DirectInput hands the
      keyboard back the instant the window stops being the foreground one, so
      the game goes deaf either way.
     
      So it is asked outright, and the answer is named in the log. The game
      being behind one of our own windows is a bug and gets fixed below. The
      game being behind Discord is a person who alt tabbed and gets left alone.
    */
    let fg = null;
    try {
      if (sp.win32 && typeof sp.win32.foregroundWindow === 'function') {
        fg = sp.win32.foregroundWindow();
      }
    } catch (e) { fg = null; }

    let where = '';
    if (fg && !fg.isGame) {
      const who = fg.ourProcess
        ? 'one of our own windows'
        : ((fg.exe || 'another app') + ', not ours');
      const named = fg.title || fg.className || '';
      where = ', keyboard is going to ' + who + (named ? ' (' + named + ')' : '');
    }

    say('input: ' + keysSeen + ' keys in 5s, browser focus ' + focused +
        ', menu ' + menu + names + controls + where);
    keysSeen = 0;

    /*
      This reports and does nothing else, deliberately.

      It used to call SetForegroundWindow on the game whenever the foreground
      was one of our own windows, on the reasoning that Windows would refuse
      the call in the only case where it would be unwelcome. That was a guess
      dressed up as a safeguard, and it was shipped on a session where the game
      was already freezing. A frozen game holding the cursor clip is bad enough
      on its own; a five second timer repeatedly shoving that window back in
      front took a stuck game and made the whole desktop unusable, mouse
      included.

      Nothing here acts on the keyboard again until the log has actually named
      what takes it. Diagnosing first and acting second is the order that
      should have been used the first time.
    */
  }));

  sp.on('buttonEvent', guard('keys', (e) => {
    keysSeen++;
    // Before the isDown guard, not after it.
    //
    // The threshold on this was sized against the pulse's number, which counts
    // every button event including the repeats a held key produces each frame.
    // Counting only key downs here made those two numbers mean different
    // things: the ring shows twenty key downs across twenty five seconds while
    // the pulse was reporting three hundred in five, so forty was never once
    // reached and the detector could not fire.
    stuckKeys++;
    if (!e.isDown || e.isUp) return;

    rememberKey(e.code);
    // 17 30 31 32 are W A S D. Somebody standing at a handle pressing E is not
    // stuck, they are using something, and that is what the one and only
    // firing of this detector actually caught.
    if (e.code === 17 || e.code === 30 || e.code === 31 || e.code === 32) {
      stuckMoveKeys++;
    }

    if (!sawAnyKey) {
      sawAnyKey = true;
      // The one fact that decides everything else. If this never appears, no
      // plugin in this build is being given keys and the wheel, the chat and
      // the mark key are all dead for the same reason.
      say('keys work, first one was scan code ' + e.code);
    }

    if (!T.ready) return;

    // Reachable only while focus is down, which is the only time it is needed.
    if (e.code === ESC) { wantTyping(false); return; }

    /*
      The skills panel. Not while the chat has the keyboard, because the key
      would be a letter somebody is typing, and not while a real menu is up.
      The panel is asked to toggle; whether it actually opened comes back as
      a browserMessage, and that is what moves the focus claim. The page can
      close itself on Escape, so it is the one that knows.
    */
    if (e.code === SKILLS_KEY) {
      if (claims.chat) { return; }
      const busyNow = busyMenuOpen();
      if (!T.hasFocus('skills') && busyNow) {
        say('skills key seen, but ' + busyNow + ' is open');
        return;
      }
      T.js('try{window.thornswoodSkills&&window.thornswoodSkills.toggle();}catch(e){}');
      return;
    }

    if (e.code !== CHAT_KEY) return;

    // Not while a real menu is up: Enter means something to every one of them.
    const busy = busyMenuOpen();
    if (!claims.chat && busy) {
      say('chat key seen, but ' + busy + ' is open');
      return;
    }
    say(claims.chat ? 'chat key seen, closing the box' : 'chat key seen, asking the page');
    wantTyping(!claims.chat);
  }));

  // ------------------------------------------------------------- overlays --
  // Each overlay is fetched by the page rather than pasted in as source, so it
  // stays a file that can be edited without touching any plugin.
  function inject(file) {
    const id = 'ts-' + file.replace(/[^a-z0-9]/gi, '-');
    return T.js(
      '(function(){' +
      'if(document.getElementById("' + id + '")){return;}' +
      'var s=document.createElement("script");' +
      's.id="' + id + '";' +
      's.src="' + file + '";' +
      's.onerror=function(){try{window.skyrimPlatform.sendMessage("thornswood-front","could not fetch ' + file + '");}catch(e){}};' +
      's.onload=function(){try{window.skyrimPlatform.sendMessage("thornswood-front","' + file + ' is in");}catch(e){}};' +
      '(document.head||document.documentElement).appendChild(s);' +
      '})();'
    );
  }

  function myName() {
    try {
      const pc = sp.Game.getPlayer();
      if (!pc) return '';
      let n = '';
      try { n = pc.getDisplayName() || ''; } catch (e) { n = ''; }
      if (!n) { try { n = pc.getBaseObject().getName() || ''; } catch (e) { n = ''; } }
      return String(n).trim();
    } catch (e) { return ''; }
  }

  // ------------------------------------------------------------------ tick --
  let phase = 0;
  let at = 0;
  let sentName = '';
  // What the browser was last told its join token is, and when that was last
  // checked. Voice.cs refreshes voice-token.txt on its own clock; this is what
  // notices and passes the new one along, on the same 5 minute rhythm as the
  // name check below, well inside the token's own half-life.
  let lastToken = '';
  let tokenAt = 0;

  sp.on('update', guard('tick', () => {
    const now = Date.now();

    // Not at the first tick. The Tilted backend draws through a D3D11 render
    // hook, and early on the game is still tearing its swap chain down and
    // rebuilding it around every load screen. Loading a page into that is how
    // you get a wheel painted over the loading screen.
    if (phase === 0) {
      let pc = null;
      try { pc = sp.Game.getPlayer(); } catch (e) { pc = null; }
      if (gameMenuOpen() || !pc) return;

      /*
        Left where anything without a virtual machine can read it.

        skymp5-client decides whether to spawn somebody by reloading a save or
        by moving them, and it decides from a tick handler, where every call
        into the game throws. So it cannot ask the game anything. This runs in
        update, where the calls work, and the answer to the only question it
        needs is already settled right here: there is a character and no menu,
        so there is a game to be in.
      */
      try { globalThis.__thornswoodInWorld = true; } catch (e) { }
      // Cleared again on the way out, below. Nothing in the shipped client
      // bundle reads this today, so it costs nothing either way, but a flag
      // that is only ever set true is a flag that lies the moment anything
      // does start reading it.

      phase = 1; at = now;
      try {
        sp.browser.loadUrl(UI_URL);
        sp.browser.setVisible(true);
        sp.browser.setFocused(false);
        log('loading', UI_URL);
      } catch (e) {
        log('no browser backend:', e);
        phase = 9;
      }
      return;
    }

    /*
      The focus arbiter waits until our own overlays are in.

      It used to start the moment the browser existed, to cover the few seconds
      between the world loading and the overlays going in, because skymp5-client
      bound Enter to raise focus and nothing lowered it. That binding is gone
      now, and running early costs something real instead.

      The login widget is skymp5-client's page in this same browser, and it
      needs focus to be typed into. Nothing here claims focus on its behalf, so
      the arbiter saw focus up with no claim and took it back after a second,
      every second. From the outside that is a login box that accepts a few
      characters and then goes dead with the game already holding the keyboard,
      which is the freeze at character creation that has to be alt tabbed out
      of.

      Phase two is our overlays being in, which is after login, in the world,
      and is the first moment anything here has any business deciding who gets
      the keyboard.
    */
    if (phase >= 2) {
      applyFocus();
    }

    // Give the page time to parse before asking it to fetch anything. It is a
    // file on the same disk, so this is a pause, not a download.
    if (phase === 1 && now - at > 1200) {
      phase = 2; at = now;
      sentName = myName() || 'Traveller';
      lastToken = joinToken();
      T.js('window.THORNSWOOD=' + JSON.stringify({
        host: HOST, port: VOICE_PORT, profileId: PROFILE, name: sentName,
        token: lastToken, base: VOICE_URL
      }) + ';');
      OVERLAYS.forEach(inject);
      // The token itself is never logged. It is what somebody would need to
      // join as this person, and this log is a file on disk.
      log('overlays injected. host', HOST + ':' + VOICE_PORT, 'profile', PROFILE,
          'as', sentName, 'join token', joinToken() ? 'yes' : 'NONE');
      return;
    }

    if (phase === 2 && now - at > 600) {
      phase = 3; at = now;
      T.ready = true;
      T.js('try{window.thornswoodChat&&window.thornswoodChat.show();}catch(e){}');
      log('ready');
      return;
    }

    if (phase !== 3) return;

    try {
      // ---- visible --------------------------------------------------------
      // Visible is not only about what is drawn. TPInputService injects every
      // mouse move, click and key into CEF whenever the render handler reports
      // itself visible, asking nothing about focus. So it is held on while you
      // are playing, because that is when the chat and the names have to be on
      // screen, and held off in every game menu, because that is when CEF
      // answering a mouse move takes the cursor away from the menu that needs
      // it. Tilted's visibility is a plain bool other code flips, so both
      // directions have to be held rather than set.
      //
      // Never hidden while this file is the reason a menu is open. Raising
      // focus opens the game's own CursorMenu, so asking isInMenuMode here
      // would hide the browser at the exact moment somebody was handed the
      // chat box: the box vanishes, and because TPInputService only injects
      // input while the render handler reports itself visible, every letter
      // typed after that goes nowhere. That is the chat that draws, takes the
      // cursor, and then will not accept a word.
      const hide = !anyClaim() && gameMenuOpen();
      if (sp.browser.isVisible() === hide) { sp.browser.setVisible(!hide); }

      // A menu opening while the chat box has the keyboard would leave the
      // caret in the box and the menu unusable, so the box is closed for it.
      //
      // Only these, and not busyMenuOpen's whole list. While focus is up the
      // game has no keyboard and no mouse, so nobody can open an inventory or
      // a map; the only menus that can appear are the ones the game raises by
      // itself. Asking the wide question here is how the box kept being taken
      // away half a second after it was given.
      if (claims.chat) {
        const over = interrupted();
        if (over) {
          say('closing the chat box, ' + over + ' opened');
          wantTyping(false);
        }
      }

      applyFocus();
    } catch (e) { }

    // Two watchdogs, because the worst outcome here is somebody standing in a
    // town unable to move and unable to say so.
    //
    // The first: a request the page never answered. Four seconds and the ask
    // is dropped, so enter simply did nothing.
    if (asked && now - asked > 4000) {
      asked = 0;
      say('asked the page for the keyboard and it never answered');
    }
    // The second: the page took it and then stopped talking, which is what a
    // crashed or reloaded front looks like from here. The keyboard comes back
    // whether or not anybody asks for it.
    if (claims.chat && beat && now - beat > 12000) {
      beat = 0;
      T.claimFocus('chat', false);
      log('the chat box went quiet, taking the keyboard back');
    }

    // The third, and the only one that does not trust the page at all.
    //
    // The heartbeat above catches a page that died. It cannot catch a page that
    // is perfectly healthy and simply never closes the box, which is what a
    // swallowed keystroke looks like: the beat keeps coming, typing=yes
    // forever, and the person cannot move. Holding the keyboard is capped
    // outright. Two minutes is far longer than anybody spends writing one line
    // and far shorter than giving up on the game.
    if (claims.chat && heldSince && now - heldSince > 120000) {
      heldSince = 0;
      T.js('try{window.thornswoodChat&&window.thornswoodChat.blurInput();}catch(e){}');
      T.claimFocus('chat', false);
      log('the chat box has held the keyboard for two minutes, taking it back');
    }

    checkServer(now);
    askServerBases(now);

    // Five seconds between saying so and doing it, so the line is readable and
    // so a server that comes straight back up is not made into an outage.
    if (leaving && now - leaving > 5000) {
      leaving = now + 3600000;   // never twice
      // No longer in the world, and said so before the quit rather than after,
      // because after it there is no tick to say it in.
      try { globalThis.__thornswoodInWorld = false; } catch (e) { }
      try {
        sp.Game.quitToMainMenu();
      } catch (e) {
        log('could not quit to the main menu:', e);
        say('the server is down. Close the game and press Play again.');
      }
    }

    // The name is a guess until the race menu has been through, so it is
    // checked now and then rather than once. setName reconnects, which is
    // cheap and is the only way the service will take a new one.
    if (now - at > 5000) {
      at = now;
      const n = myName();
      if (n && n !== sentName) {
        sentName = n;
        T.js('try{window.thornswoodNet&&window.thornswoodNet.setName(' +
             JSON.stringify(n) + ');}catch(e){}');
        log('name is now', n);
      }
    }

    /*
      The join token goes stale, and nothing else in this file notices.

      It is read once, at injection, and this browser page is not reloaded for
      the length of a normal session. Voice.cs on this machine rewrites
      voice-token.txt at half the token's life, so a five minute check here is
      well inside that and never the thing standing between a fresh token and
      an expired one.

      setToken only updates the value the page holds; it does not reconnect.
      The socket already open was let in and is never rechecked, so this only
      matters the next time it has to open on its own, which a long session,
      a network blip or the voice service restarting all eventually ask for.
    */
    if (now - tokenAt > 300000) {
      tokenAt = now;
      const tok = joinToken();
      if (tok && tok !== lastToken) {
        lastToken = tok;
        T.js('try{window.thornswoodNet&&window.thornswoodNet.setToken(' +
             JSON.stringify(tok) + ');}catch(e){}');
        // Never the token itself, same as at injection.
        log('join token refreshed in the browser');
      }
    }
  }));

  // ------------------------------------------------------------ the server --
  // A black screen is not an answer.
  //
  // When the server stops, which it does on purpose every time an update is
  // published, the client does not say so and does not put anybody back
  // anywhere. It sits there, and after a moment the screen goes black, and the
  // only way out is the task manager.
  //
  // There is nothing in the client to hook for this, so it is asked directly.
  // The resources folder on 3000 is the same HTTP the load order manifest comes
  // from: if it answers, the server is up; if it stops answering several times
  // in a row, it is not. Several, because one slow reply is not an outage and
  // throwing somebody out of Windhelm over a dropped packet is worse than the
  // thing being fixed.
  const PROBE_MS = 10000;
  /*
    Twelve, not four.

    Four strikes is forty seconds, and a server deploy takes longer than that.
    So did a restart people had been told to sit through: the countdown said
    stay, the process went down for a minute, and everybody who did as they
    were told was dropped to the main menu anyway. Two minutes is longer than
    any restart this server has taken and still short enough that a real
    outage is not a black screen forever.

    And a countdown is not an outage at all. The gamemode writes "restarting"
    into online.json while one is running, so the answer that arrives just
    before the process stops says what is about to happen, and the strikes
    that follow are ignored until it comes back.
  */
  const PROBE_STRIKES = 12;
  /* How long a "restarting" seen in online.json keeps the probe patient.
     Longer than any restart so far, and it only ever delays a quit. */
  const RESTART_GRACE_MS = 600000;

  let probe = null;
  try { probe = HOST ? new sp.HttpClient('http://' + HOST + ':3000') : null; } catch (e) { probe = null; }

  // Asked for once, and again every ten minutes in case the server was
  // deployed while somebody was playing. Failure is silent and harmless.
  function askServerBases(now) {
    if (!probe) { return; }
    if (serverBasesAsked && now - serverBasesAsked < 600000) { return; }
    serverBasesAsked = now;
    try {
      probe.get('/server-bases.json', undefined, guard('bases', (res) => {
        if (!res || res.status < 200 || res.status >= 300) { return; }
        let list = [];
        try { list = (JSON.parse(String(res.body || '{}')) || {}).bases || []; }
        catch (e) { return; }
        let n = 0;
        for (const id of list) {
          const num = Number(id);
          if (num > 0 && !serverBases[num]) { serverBases[num] = true; n++; }
        }
        if (n) { log('the server answers for', n, 'more bases, not re-activating those'); }
      }));
    } catch (e) { }
  }

  let strikes = 0;
  let probing = false;
  let lastProbe = 0;
  let leaving = 0;
  /* When the server last said a countdown was running. See PROBE_STRIKES. */
  let toldRestarting = 0;

  function checkServer(now) {
    if (!probe || probing || leaving) return;
    if (now - lastProbe < PROBE_MS) return;
    lastProbe = now;
    probing = true;
    try {
      probe.get('/online.json', undefined, guard('probe', (res) => {
        probing = false;
        const ok = res && res.status >= 200 && res.status < 500;
        if (ok) {
          // The server said it is going down on purpose. Remember that, so
          // the silence that follows is read as a restart and not an outage.
          try {
            const body = JSON.parse(String(res.body || '{}'));
            if (body && body.restarting) {
              if (!toldRestarting) {
                log('the server says it is restarting, staying put');
              }
              toldRestarting = Date.now();
            } else {
              toldRestarting = 0;
            }
          } catch (e) { }
          if (strikes) { log('the server is answering again'); }
          strikes = 0;
          return;
        }
        strikes++;
        onStrike();
      }));
    } catch (e) {
      probing = false;
      strikes++;
      onStrike();
    }
  }

  function onStrike() {
    if (leaving) return;
    // Told to expect this. A restart is not an outage, and the whole point of
    // warning people was so they would not be thrown out for it.
    if (toldRestarting && Date.now() - toldRestarting < RESTART_GRACE_MS) {
      log('the server did not answer,', strikes, 'of', PROBE_STRIKES +
          ', but it said it was restarting, so waiting');
      return;
    }
    if (strikes < PROBE_STRIKES) {
      log('the server did not answer,', strikes, 'of', PROBE_STRIKES);
      return;
    }
    leaving = Date.now();
    say('the server has gone down, going back to the menu');
    log('server unreachable', PROBE_STRIKES, 'times running, quitting to the main menu');
  }

  sp.on('browserMessage', guard('browserMessage', (event) => {
    const a = event.arguments;
    if (!a || a[0] !== 'thornswood-front') return;
    const what = String(a[1]);

    /*
      The skills panel says when it opens and closes rather than being
      assumed. It can close itself on Escape, and a focus claim left up after
      that is a keyboard that never comes back, which is the failure
      claimFocus logs every single time for exactly this reason.
    */
    if (what === 'skills:opened') { T.claimFocus('skills', true); return; }
    if (what === 'skills:closed') { T.claimFocus('skills', false); return; }
    if (what === 'skills:ready') { log('the skills panel is in'); return; }
    if (what.indexOf('skills:pick ') === 0) {
      // Recorded and nothing else. The server owns every rule in the
      // rulebook and none of it is built yet; a client that acted on this
      // would be a client anybody could edit.
      log('skills: picked', what.slice(12));
      return;
    }

    if (what === 'typing') { beat = Date.now(); return; }
    if (what === 'typing-idle') {
      log('nobody typed for a while, the box is giving the keyboard back');
      return;
    }

    if (what === 'typing-on') {
      asked = 0;
      beat = Date.now();
      T.claimFocus('chat', true);
      return;
    }

    if (what === 'typing-off') {
      asked = 0;
      T.claimFocus('chat', false);
      return;
    }

    if (what === 'typing-fail') {
      asked = 0;
      boxReady = false;
      T.claimFocus('chat', false);
      say('the page has no chat box, so the keyboard stays with the game');
      return;
    }

    if (what === 'chat is up') {
      boxReady = true;
      log('chat box is ready, enter is immediate from here');
      return;
    }

    /*
      The page can be reloaded out from under us, and on some machines it is.
     
      The bridge announces itself once per page load. Seeing it again after the
      overlays have gone in does not mean the bridge restarted, it means the
      page did, and everything our scripts built went with it: the chat box, the
      microphone indicator, the wheel. The scripts themselves are gone too.
     
      Nothing noticed, because by then this file has reached its last phase and
      stops injecting. One machine's log is the whole story:
     
          overlays injected
          thornswood-voice.js is in
          ready
          bridge is up            <- the page went away here
     
      followed by a session of "the page has no chat box" and a voice log that
      never gets past being told to open a microphone. Same files as everybody
      else, same build, and nothing on screen, because the browser was showing
      a page our overlays had already been removed from.
     
      Whoever reloads it, the answer from here is the same: go back and put them
      in again. Injection already refuses to add a script twice, so a spurious
      one costs nothing.
    */
    if (what === 'bridge is up') {
      if (phase >= 2) {
        say('the page reloaded after the overlays went in, putting them back');
        phase = 1;
        at = Date.now();
        boxReady = false;
        T.ready = false;
        try { T.claimFocus('chat', false); } catch (e) { }
      }
      return;
    }

    log(what);
  }));

  /*
    Write the game's real load order to disk, once, on the first update.

    The server compares its own list against this one POSITIONALLY, by name and
    size and crc32, and refuses the session on any disagreement. Working out
    what the game actually loaded from plugins.txt is guesswork: Skyrim puts
    masters first, then light plugins, then the rest, and plugins.txt records
    none of that ordering. Game.getModName walks the real thing in the real
    order, so it is the only honest source for what the server's loadOrder has
    to be set to.

    One file, written once per session, so the two lists can be reconciled from
    ground truth instead of from a best guess.

    getModCount COUNTS REGULAR PLUGINS ONLY. Light ones live in their own index
    behind getLightModCount, and leaving them out is correct for this file,
    because the server's list drops them too and this file has to match it
    positionally. It was not correct for the sentence underneath, which called
    60 of 102 plugins the real load order. On 20 September that read as a
    collection with 42 mods missing from it and sent somebody looking through
    Vortex for a fault that was not there: every one of the 42 was loaded and
    light, confirmed by reading bit 0x200 out of each TES4 header.

    So the light ones are written beside it rather than into it. Nothing that
    consumes the first file sees any change, and the question "where are the
    other 42" now has an answer sitting next to it instead of needing a header
    parser to work out.
  */
  let dumpedOrder = false;
  sp.on('update', guard('loadorder', () => {
    if (dumpedOrder) { return; }
    dumpedOrder = true;
    try {
      const fs = require('fs');

      const names = [];
      const n = sp.Game.getModCount();
      for (let i = 0; i < n; i++) {
        const name = sp.Game.getModName(i);
        if (name) { names.push(name); }
      }
      fs.writeFileSync('Data/Platform/thornswood-loadorder.txt',
                       names.join('\n') + '\n');

      /* A build without the light index must still get the file above, so this
         is separate and its failure is not the other one's. */
      const light = [];
      try {
        const ln = sp.Game.getLightModCount();
        for (let i = 0; i < ln; i++) {
          const name = sp.Game.getLightModName(i);
          if (name) { light.push(name); }
        }
        fs.writeFileSync('Data/Platform/thornswood-plugins-light.txt',
                         light.join('\n') + '\n');
      } catch (e2) {
        log('could not write the light plugin list:', e2);
      }

      say('wrote ' + names.length + ' regular plugins, in load order, to ' +
          'Data/Platform/thornswood-loadorder.txt, and ' + light.length +
          ' light plugins to thornswood-plugins-light.txt. That is ' +
          (names.length + light.length) + ' loaded in total. The first file is ' +
          'the one the server reconciles against and it holds regular plugins ' +
          'only, on purpose. A mod in neither file is genuinely not loaded; a ' +
          'mod in the second one is loaded.');
    } catch (e) {
      log('could not write the load order:', e);
    }
  }));

  /*
    Field of view, from the launcher.

    Skyrim's own fDefaultWorldFOV is not enough here. The game rewrites it at
    various points, mods fight over it, and a value in an ini only lands when
    the game reads that ini. Setting it at runtime and putting it back whenever
    the camera changes is the only version that holds, which is why the working
    RP servers carry a service to do exactly this.

    Read from Thornswood.ini, the same file the voice keys come from, so the
    launcher writes one place and everything reads it. Absent or nonsense
    leaves the game alone entirely rather than forcing a default on anybody.
  */
  const FOV_INI = 'Data/SKSE/Plugins/Thornswood.ini';
  const FOV_MIN = 60;
  const FOV_MAX = 140;
  // Skyrim's own. A setting equal to this is the same as no setting, and the
  // launcher does not write it at all, but checking here as well means a file
  // edited by hand costs nothing either.
  const FOV_DEFAULT = 65;

  let wantedFov = 0;
  try {
    const fsf = require('fs');
    const text = fsf.readFileSync(FOV_INI, 'utf8');
    const m = text.match(/^\s*Fov\s*=\s*(\d+(?:\.\d+)?)\s*$/m);
    if (m) {
      const v = Number(m[1]);
      if (v === FOV_DEFAULT) {
        log('fov is set to Skyrim\'s own ' + FOV_DEFAULT + ', leaving the camera alone');
      } else if (v >= FOV_MIN && v <= FOV_MAX) {
        wantedFov = v;
      } else {
        log('fov ' + v + ' is outside ' + FOV_MIN + ' to ' + FOV_MAX + ', ignoring it');
      }
    }
  } catch (e) { }

  function applyFov() {
    if (!wantedFov) { return; }
    try {
      if (typeof sp.Game.setCameraFOV === 'function') {
        sp.Game.setCameraFOV(wantedFov, wantedFov);
      } else if (typeof sp.setCameraFOV === 'function') {
        sp.setCameraFOV(wantedFov, wantedFov);
      } else {
        log('this build has no setCameraFOV, leaving the field of view alone');
        wantedFov = 0;
      }
    } catch (e) { }
  }

  if (wantedFov) {
    let fovAt = 0;
    sp.on('update', guard('fov', () => {
      // Cheap, and it has to be repeated: loading, a menu, mounting a horse
      // and anything that swaps the camera all put it back to the game's own
      // number. Once a second is under the noise floor and is not noticeable
      // when something else has just reset it.
      const now = Date.now();
      if (now - fovAt < 1000) { return; }
      fovAt = now;
      applyFov();
    }));
    try { sp.on('cameraStateChanged', guard('fovcam', () => { applyFov(); })); } catch (e) { }
    say('field of view set to ' + wantedFov);
  }

  log('loaded. browser:', typeof sp.browser, 'chat key', CHAT_KEY);
})();
