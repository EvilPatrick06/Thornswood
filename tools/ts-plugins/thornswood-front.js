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

  const sp = skyrimPlatform;

  const T = (globalThis.Thornswood = globalThis.Thornswood || {});
  if (T.front) return;      // already loaded, do not load the page twice
  T.front = true;

  const UI_PATH = 'Data/Platform/UI/index.html';
  const OVERLAYS = ['thornswood-chat.js', 'thornswood-emotes.js', 'thornswood-voice.js'];
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
   * A line in the corner of the screen.
   *
   * Because a log file somebody has to go and find is a round trip, and three
   * of those have now been spent on one key. If enter does nothing, the reason
   * should be on screen at the moment it does nothing.
   */
  function say(text) {
    try { sp.Debug.notification('Thornswood: ' + text); } catch (e) { }
    log(text);
  }
  T.say = say;

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
  const VOICE_PORT = iniNumber(ini, 'VoicePort', 7778);
  const ESC = 1;

  const client = (function () {
    try { return JSON.parse(readText(CLIENT_SETTINGS)) || {}; } catch (e) { return {}; }
  })();
  const HOST = String(client['server-ip'] || '');
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
   */
  const KEYBOARD_MENUS = [
    'Console', 'Crafting Menu', 'ContainerMenu', 'Dialogue Menu', 'Favorites Menu',
    'GiftMenu', 'InventoryMenu', 'Journal Menu', 'Lockpicking Menu', 'Loading Menu',
    'MapMenu', 'RaceSex Menu', 'StatsMenu', 'TweenMenu', 'Main Menu',
    'MessageBoxMenu', 'Book Menu', 'Sleep/Wait Menu', 'Barter Menu', 'Training Menu',
  ];

  function busyMenuOpen() {
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

  function applyFocus() {
    const want = anyClaim();
    try {
      if (sp.browser.isFocused() === want) return;
      if (!want && raceMenuOpen()) return;
      sp.browser.setFocused(want);
    } catch (e) { }
  }

  T.claimFocus = function (who, on) {
    if (!!claims[who] === !!on) return;
    claims[who] = !!on;
    applyFocus();
  };
  T.hasFocus = function (who) { return !!claims[who]; };

  // ---------------------------------------------------------------- typing --
  // Asked for, not taken.
  //
  // The keyboard is only handed over once the page has said it has a box to
  // type into, and it is handed back on a message from the page rather than on
  // a key. Both halves of that are forced by the same fact: raising focus
  // withholds DirectInput from the game, and SkyrimPlatform's buttonEvent is
  // built out of the game's own input, so the instant focus goes up this
  // handler stops being called. A plugin cannot wait for the escape key that
  // would undo what it just did.
  //
  // Which is exactly what went wrong. Enter raised focus whether or not
  // anything had drawn a chat box, and when there was no box there was nothing
  // on screen and nothing listening: a cursor, no movement, and a fight to get
  // back out.
  let asked = 0;        // when we last asked the page to take the keyboard
  let beat = 0;         // when the page last said it still has it
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

  sp.on('buttonEvent', guard('keys', (e) => {
    if (!e.isDown || e.isUp) return;

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

    // From here on the browser exists, so the focus flag is watched whatever
    // phase the page is in. Without this there is a window of a few seconds
    // between the world loading and the overlays being in during which
    // skymp5-client's Enter binding could raise focus and nothing would lower
    // it, which is the lockout all over again on a shorter fuse.
    applyFocus();

    // Give the page time to parse before asking it to fetch anything.
    if (phase === 1 && now - at > 2500) {
      phase = 2; at = now;
      sentName = myName() || 'Traveller';
      T.js('window.THORNSWOOD=' + JSON.stringify({
        host: HOST, port: VOICE_PORT, profileId: PROFILE, name: sentName
      }) + ';');
      OVERLAYS.forEach(inject);
      log('overlays injected. host', HOST + ':' + VOICE_PORT, 'profile', PROFILE, 'as', sentName);
      return;
    }

    if (phase === 2 && now - at > 1500) {
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

    checkServer(now);

    // Five seconds between saying so and doing it, so the line is readable and
    // so a server that comes straight back up is not made into an outage.
    if (leaving && now - leaving > 5000) {
      leaving = now + 3600000;   // never twice
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
  const PROBE_STRIKES = 4;

  let probe = null;
  try { probe = HOST ? new sp.HttpClient('http://' + HOST + ':3000') : null; } catch (e) { probe = null; }

  let strikes = 0;
  let probing = false;
  let lastProbe = 0;
  let leaving = 0;

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

    if (what === 'typing') { beat = Date.now(); return; }

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

    log(what);
  }));

  log('loaded. browser:', typeof sp.browser, 'chat key', CHAT_KEY);
})();
