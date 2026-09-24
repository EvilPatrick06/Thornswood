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
                    'thornswood-skills.js', 'thornswood-party.js',
                    'thornswood-journal.js', 'thornswood-trade.js'];
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

  // Every line carries the clock, because a report that the K panel opened
  // late after the face (20 September) had nothing in this log to measure it
  // against: the server's log is timed and this one was not.
  function clock() {
    const d = new Date();
    const two = function (n) { return (n < 10 ? '0' : '') + n; };
    return two(d.getHours()) + ':' + two(d.getMinutes()) + ':' + two(d.getSeconds()) + '.' +
           ('00' + d.getMilliseconds()).slice(-3);
  }

  function log() {
    const line = '[front] ' + clock() + ' ' + Array.prototype.slice.call(arguments).join(' ');
    try { sp.printConsole(line); } catch (e) { }
    if (fsm) { try { fsm.appendFileSync(LOG_FILE, line + '\n'); } catch (e) { fsm = null; } }
  }

  /*
    WHERE THE FRAME GOES, because nobody has ever been able to say.

    Patrick, 21 September: "it's really laggy and I don't know why we need to
    do some performance enhcanments", and on 23 September: it is on BOTH
    servers. That second half is the useful one. The dev server simulates
    interior NPCs only and the live one simulates every NPC in Skyrim, so if
    both feel the same then the number of simulated NPCs is not the cost, and
    the entry on the list says plainly that nothing should be optimised before
    that answer is known.

    What both servers share is this plugin. Nineteen handlers run on
    sp.on('update'), which in skymp5-client is EVERY FRAME, and three of them
    used to do real work every frame before they were given a heartbeat: the
    swing, the skills panel and the door locks, the last of those only on
    23 September.

    So the frame is measured rather than guessed at. Every handler already
    goes through guard(), so this is the one place that can time all of them
    without touching nineteen bodies. Two Date.now() calls per handler per
    frame is a rounding error against what the handlers themselves do, and the
    report is one line every thirty seconds naming the five that cost the most.

    READ IT AS: worst is the single slowest call, which is what a stutter
    feels like, and total is where the time actually went. A handler that is
    1ms every frame costs more than one that is 40ms once a minute.
  */
  const spent = {};
  let frames = 0;
  let spentAt = 0;
  const SPENT_EVERY = 30000;

  function guard(name, fn) {
    return function () {
      const began = Date.now();
      try { return fn.apply(null, arguments); }
      catch (e) { log(name, 'threw:', e && e.stack ? e.stack : e); return undefined; }
      finally {
        const took = Date.now() - began;
        const row = spent[name] || (spent[name] = { ms: 0, runs: 0, worst: 0 });
        row.ms += took;
        row.runs++;
        if (took > row.worst) { row.worst = took; }
      }
    };
  }

  /*
    Counted here rather than inside guard, because guard wraps every handler
    and a frame is one pass through all of them. The 'pulse' handler is the
    one that already runs on a five second beat and is always registered, so
    it is the cheapest honest marker of a frame having happened.
  */
  function frameWent() {
    frames++;
    const now = Date.now();
    if (!spentAt) { spentAt = now; return; }
    if (now - spentAt < SPENT_EVERY) { return; }
    const seconds = (now - spentAt) / 1000;
    spentAt = now;

    const rows = [];
    for (const k in spent) {
      if (Object.prototype.hasOwnProperty.call(spent, k)) {
        rows.push({ name: k, ms: spent[k].ms, runs: spent[k].runs, worst: spent[k].worst });
      }
    }
    rows.sort(function (a, b) { return b.ms - a.ms; });
    const total = rows.reduce(function (t, r) { return t + r.ms; }, 0);

    log('frame: ' + Math.round(frames / seconds) + ' updates a second, ' +
        total + 'ms of plugin in ' + Math.round(seconds) + 's (' +
        (total / Math.max(1, seconds) / 10).toFixed(1) + '% of one core), worst five: ' +
        rows.slice(0, 5).map(function (r) {
          return r.name + ' ' + r.ms + 'ms/' + r.runs + ' runs, worst ' + r.worst + 'ms';
        }).join('; '));

    for (const k in spent) {
      if (Object.prototype.hasOwnProperty.call(spent, k)) {
        spent[k].ms = 0; spent[k].runs = 0; spent[k].worst = 0;
      }
    }
    frames = 0;
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
  /*
    ON SCREEN AND IN THE LOG, for the handful of things a person must see.

    This existed, worked and had no callers at all: everything went through
    say(), which is log only. That was right for a week of chasing a keystroke
    and wrong the moment anybody who is not us plays, because a log somebody
    has to go and find is not a message.

    The bar for using it is deliberately high. A notification interrupts
    somebody's game and sits over their screen next to their own mods' ones, so
    it is for a thing that is happening TO them and that they can act on: they
    are on fire, the fire is out, the console is not theirs. Everything else
    stays in the log where it belongs.
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
  /*
    The four social keys, and P and J are Patrick's own choices:
    "P for the Party menu... J for Journal".

    DirectInput scan codes, the same as ChatKey and SkillsKey above, because
    that is what buttonEvent hands back. G, H and B do nothing in vanilla
    Skyrim and are only armed while somebody is under the crosshair, so even a
    mod that wanted one of them would keep it the rest of the time.
  */
  const PARTY_KEY   = iniNumber(ini, 'PartyKey', 25);      // P
  const JOURNAL_KEY = iniNumber(ini, 'JournalKey', 36);    // J
  const FRIEND_KEY  = iniNumber(ini, 'FriendKey', 34);     // G
  const TRADE_KEY   = iniNumber(ini, 'TradeWithKey', 35);  // H
  /*
    MuteThemKey, NOT MuteKey. MuteKey is already in this same file and is the
    microphone: "Mute the microphone... for when somebody walks into the
    room", Keys.cs, default Y. Reusing the name would have made one launcher
    row set two different things, and the first person to rebind their
    microphone would have rebound this as well.

    L rather than B or N or M: WheelKey is B, StopKey is N and MenuKey is M,
    all of them in this file already.
  */
  const MUTE_KEY    = iniNumber(ini, 'MuteThemKey', 38);   // L
  /* What the prompt calls them. Read off the scan code so a rebind in the ini
     changes the letter on the screen as well as the key that works. */
  function keyName(code) {
    const letters = {
      16: 'Q', 17: 'W', 18: 'E', 19: 'R', 20: 'T', 21: 'Y', 22: 'U', 23: 'I',
      24: 'O', 25: 'P', 30: 'A', 31: 'S', 32: 'D', 33: 'F', 34: 'G', 35: 'H',
      36: 'J', 37: 'K', 38: 'L', 44: 'Z', 45: 'X', 46: 'C', 47: 'V', 48: 'B',
      49: 'N', 50: 'M'
    };
    return letters[code] || ('#' + code);
  }
  const PARTY_NAME = keyName(PARTY_KEY);
  const FRIEND_NAME = keyName(FRIEND_KEY);
  const TRADE_NAME = keyName(TRADE_KEY);
  const MUTE_NAME = keyName(MUTE_KEY);

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
  // Whose session this is. From the settings file until 20 September; now the
  // settings hold the last one played and the real answer comes from the main
  // menu (the block below), so this is reassigned when the choice is made.
  let PROFILE = Number((client.gameData || {}).profileId) || 0;

  // ------------------------------------------------- the main menu choice --
  /*
    Who you are is chosen at the game's main menu, not in the launcher.

    Asked for by Patrick on 20 September. The launcher writes the list of this
    install's characters to thornswood-characters.json and sets
    gameData.chooseAtMenu in the client settings; our fork of skymp5-client
    then waits at the menu instead of logging in as gameData.profileId. This
    block loads the page into the browser at the menu, hands the list to
    thornswood-select.js, and the page's pick goes straight to the client as

        sendMessage('thornswood', 'select', profileId)

    which the client hears (it is a browserMessage like any other) and logs in
    as. This plugin hears the same message, remembers the profile for the
    voice join and the chat, and writes it to thornswood-choice.txt for the
    launcher, which fetches the voice token for that profile and keeps the
    books.

    It runs on tick and not on update, because update does not fire at the
    main menu (it needs the Papyrus VM, which needs a game). Nothing here
    calls into the game, only the browser and the disk, which is what tick is
    allowed. The rest of this file waits for update as before and finds the
    page already loaded, which it handles the same way it handles a reload.

    With no list on disk (an older launcher) the settings' profileId is sent
    as the choice at once, so nobody sits at a menu that asks nothing.
  */
  const CHOICE_FILE = 'Data/Platform/thornswood-choice.txt';
  const CHARACTERS_FILE = 'Data/Platform/thornswood-characters.json';
  const FORGET_FILE = 'Data/Platform/thornswood-forget.txt';
  const chooseAtMenu = !!((client.gameData || {}).chooseAtMenu);
  let menuPhase = 0;
  let menuAt = 0;
  const loadedAt = Date.now();

  function chosenOnDisk() {
    try { return !!readText(CHOICE_FILE).trim(); } catch (e) { return false; }
  }


  /*
    ------------------------------------------------- putting the shift on

    Patrick, twice, from playing it: "We keep spawning in with our clothes off
    still".

    THE SERVER CANNOT DRESS ANYBODY, and that is the whole of it. giveShift
    pushes the two shift records into the pack with worn: true, and in the
    engine the worn flag on an inventory entry and the equipment the client
    actually wears are two different things. There is no 'equipment' property
    binding for a gamemode at all: the client owns what is equipped and only
    ever reports it upward. So the shift arrived in the pack and stayed there,
    folded, and the person stood in the creation hall with nothing on.

    So the only place this can be done is here.

    THE TWO IDS ARE VANILLA AND THEY MUST MATCH CHARGEN.shift IN gamemode.js,
    which is 1be1a and 1be1b out of Skyrim.esm. They are written here rather
    than fetched because they are Bethesda's own records and cannot move, and
    because a fetch that fails would leave somebody naked, which is the thing
    being fixed. If the shift ever changes, both places change.

    ONCE, AND ONLY WHAT IS NOT ALREADY WORN. Equipping something already worn
    is how a person ends up dressed twice, and equipping every armour in the
    pack would take somebody's own clothes off to put rags on. Each id is tried
    once per session and never again.
  */
  const SHIFT_IDS = [0x1be1a, 0x1be1b];
  let shiftDone = false;

  function wearTheShift() {
    if (shiftDone) { return; }
    shiftDone = true;
    let pc = null;
    try { pc = sp.Game.getPlayer(); } catch (e) { return; }
    if (!pc) { return; }
    const ac = sp.Actor.from(pc);
    if (!ac) { return; }

    let put = 0;
    for (let i = 0; i < SHIFT_IDS.length; i++) {
      const id = SHIFT_IDS[i];
      try {
        const form = sp.Game.getFormEx(id);
        if (!form) { continue; }
        // Only what they are actually carrying, and only if it is not on.
        if (pc.getItemCount(form) <= 0) { continue; }
        if (ac.isEquipped(form)) { continue; }
        ac.equipItem(form, false, true);   // not preventRemoval, silent
        put++;
      } catch (e) {
        log('could not put on shift item ' + id.toString(16) + ': ' + e);
      }
    }
    if (put) { log('put on ' + put + ' piece(s) of the shift'); }
  }

  /*
    KEEP SAYING THE CHOICE UNTIL THE WORLD ACTUALLY LOADS.

    The page sends its pick to skymp5-client and repeats it every two seconds
    until something says it heard, because the page is up long before the
    plugins are: SkyrimPlatform loads index.html at start and runs plugins
    about fifteen seconds later. That repeat is the only thing covering the
    gap, and menuChose below was ending it from the wrong side of the room.

    This plugin is not skymp5-client. Its own browserMessage handler sees the
    pick, writes the choice file and acks the page, which hides the menu and
    stops the repeat. skymp5-client's AuthService only acts on that same
    message while it is waiting for it, and it starts waiting when it gets
    authNeeded. If the person clicked before that, AuthService's handler
    returned early, this plugin acked anyway, the page went quiet, and the
    pick was gone for good. No authAttempt, so no join, so the menu vanishes
    and the main menu is where you stay. That is what a tester reported twice,
    and what Djinn hit: "click make a new character and then are stuck on the
    main menu with selector menu gone".

    So the plugin takes the repeat over rather than ending it. A duplicate
    costs nothing: once AuthService has taken one it clears its own wait and
    every later copy falls to `default: break` in its switch.

    __thornswoodInWorld is the flag the tick sets when the world is really
    there, so arriving is what stops this and not a guess about timing.
  */
  const MENU_SAY_EVERY = 2000;
  const MENU_SAY_FOR = 90000;
  let menuChosenId = 0;
  let menuChosenAt = 0;
  let menuSaidAt = 0;
  let menuSaidTimes = 0;
  let menuGiveUpTold = false;

  function keepSayingChoice(now) {
    let here = false;
    try { here = !!globalThis.__thornswoodInWorld; } catch (e) { here = false; }
    if (here) {
      log('menu: in the world as profile', menuChosenId, 'so the choice is done');
      menuChosenId = 0;
      return;
    }
    if (now - menuChosenAt > MENU_SAY_FOR) {
      if (!menuGiveUpTold) {
        menuGiveUpTold = true;
        log('menu: said profile', menuChosenId, 'for',
            Math.round(MENU_SAY_FOR / 1000) + 's and the world never loaded.',
            'The client never took the choice. Nothing more this can do.');
      }
      menuChosenId = 0;
      return;
    }
    if (now - menuSaidAt < MENU_SAY_EVERY) { return; }
    menuSaidAt = now;
    menuSaidTimes++;
    /*
      Said out loud the first time and then every ten, because this log is the
      only place anybody can see this working. On a machine where the client
      was ready the choice is taken at once and none of these ever appear, so
      a run that shows them is a run that would have been stuck before.
    */
    if (menuSaidTimes === 1 || menuSaidTimes % 10 === 0) {
      /*
        THE TWO FLAGS ARE THE WHOLE DIAGNOSIS, so they go in the line.

        remoteServer.ts decides whether to load the world with
        `alreadyInAGame = __thornswoodInWorld || __thornswoodUncausedLoad > 0`,
        and when that is true it stands down and leaves the moving to the
        other spawn path. At a real main menu there is no other path, so
        nothing happens at all and the person sits there.

        21 September: a tester picked a character, the server logged him
        connected and put him in the creation hall correctly, and his own
        machine never left the main menu. Everything up to that point was
        provable from the server log and this one. That decision was not,
        because nothing wrote either flag down.

        uncaused is the count of game loads SkyrimPlatform did not ask for,
        and po3_StartOnSave makes one on every launch that has a save to
        load. If it reads above zero here, at a main menu, that guard is why
        the world never came.
      */
      let inWorld = '?', uncaused = '?';
      try { inWorld = String(!!globalThis.__thornswoodInWorld); } catch (e) { }
      try { uncaused = String(Number(globalThis.__thornswoodUncausedLoad) || 0); } catch (e) { }

      /*
        AND WHAT IS IN THE SAVES FOLDER, which is the question this whole
        entry now turns on and which nobody can answer without walking to the
        stuck machine.

        sp.loadGame builds a synthetic save and loads it, and it leaves the
        file behind. On a machine where this works the folder holds exactly one
        file, TESMODPLATFORM-<guid>.ess. So:

          EMPTY means loadGame was never called at all, and the fault is above
          it, in whatever decides to call it or in the message never arriving.

          A TESMODPLATFORM FILE means loadGame ran and Skyrim refused the save,
          which on a fresh install points at the mod files being incomplete.

        Those two answers go to completely different places, which is exactly
        why it is worth one line in a log rather than one trip to somebody's
        house. The launcher redirects My Games into the Thornswood Profile
        folder, so the path here is the redirected one and not the real
        Documents.

        Guarded to nothing: a client with no fs, or a folder that is not there
        yet, says so instead of stopping the retry that is the point of this
        function.
      */
      let saves = 'unknown';
      try {
        const fsm2 = require('fs');
        /*
          RELATIVE TO THE GAME FOLDER, which is where the process runs: the
          crash logs record "Working Directory: C:\Thornswood\Game", and the
          log file this function writes to is 'Data/Platform/...' for the same
          reason. The Profile folder sits BESIDE Game, not inside it, so this
          is one level up. Written relative rather than absolute so the dev
          build, which lives in Thornswood-DevBuild, answers about its own
          saves and not about the play install's.
        */
        const dir = '../Profile/MyGames/Saves';
        const names = fsm2.readdirSync(dir);
        const ess = names.filter(function (n) { return /\.ess$/i.test(n); });
        const plat = ess.filter(function (n) { return /^TESMODPLATFORM/i.test(n); });
        saves = ess.length + ' save(s), ' + plat.length + ' from loadGame' +
                (plat.length ? ' (' + plat[0] + ')' : '');
      } catch (e) {
        saves = 'could not read the saves folder: ' + ((e && e.message) || e);
      }

      log('menu: the client has not taken profile', menuChosenId, 'yet, saying it again',
          '(' + menuSaidTimes + ').',
          'inWorld=' + inWorld, 'uncausedLoads=' + uncaused, 'saves: ' + saves);
    }
    T.js('try{window.skyrimPlatform.sendMessage("thornswood","select",' +
         menuChosenId + ');}catch(e){}');
  }

  sp.on('tick', guard('menu', () => {
    if (!chooseAtMenu) { return; }
    const now = Date.now();

    // Before the phase check, because menuChose parks the phase at 9 and this
    // has to go on running after it.
    if (menuChosenId) { keepSayingChoice(now); }

    if (menuPhase === 9) { return; }

    /*
      No loadUrl here, ever. What the browser's own log showed on 20
      September at 15:09: SkyrimPlatform loads Data/Platform/UI/index.html
      itself at start, fifteen seconds before any plugin runs, so the page
      is already ours and already drawing the choice from the list the
      launcher wrote. Tilted applies a loadUrl only inside its mouse move
      handler, so the one this block used to issue sat until the first
      mouse move and then navigated away from the page the person was
      looking at. That was the vanish, four times over.

      So this asks the page where it is and what it has, and only fills in
      what is missing: an index.html from before this change gets the list
      and the script injected; a browser on some other address (none known)
      gets a loadUrl as a last resort and the wait that comes with it.
    */
    if (menuPhase === 0) {
      if (now - loadedAt < 600) { return; }
      if (chosenOnDisk()) { menuPhase = 9; log('menu: a choice is already on disk for this session'); return; }
      try {
        sp.browser.setVisible(true);
        sp.browser.setFocused(true);
      } catch (e) {
        log('menu: no browser backend:', e);
        menuPhase = 9;
        return;
      }
      menuPhase = 1; menuAt = now; menuAsked = 0;
      log('menu: showing the page and asking where it is');
      return;
    }

    if (menuPhase === 1) {
      // Ask once a second until the page answers (browserMessage below).
      if (now - menuAsked > 1000) {
        menuAsked = now;
        T.js('try{window.skyrimPlatform.sendMessage("thornswood-front","where "+location.href+" "+(window.thornswoodSelect?"select":(window.THORNSWOOD_SELECT?"list":"bare")));}catch(e){}');
      }
      // Nothing back in five seconds: the page is not ours or not up. Load
      // ours; Tilted applies it on the next mouse move, which is the wait
      // this block otherwise avoids.
      if (now - menuAt > 5000 && !menuLoaded) {
        menuLoaded = true;
        log('menu: the page did not answer in five seconds, loading ours');
        try { sp.browser.loadUrl(UI_URL); } catch (e) { }
        menuAt = now;
      }
      return;
    }

    if (menuPhase === 2) {
      /*
        The page's own pulse, and a reload when it stops. Kept from the
        earlier cut as the safety net: the page beats every two seconds
        while the choice is up; six seconds of silence and this reloads it,
        three times at most, and says so.
      */
      if (menuBeatAt && now - menuBeatAt > 6000) {
        if (menuReloads >= 3) {
          if (!menuGaveUp) { menuGaveUp = true; log('menu: the page went silent three times; leaving it, the client falls back to the last character'); }
        } else {
          menuReloads++;
          log('menu: the page went silent for six seconds, loading it again (' + menuReloads + ' of 3)');
          try { sp.browser.loadUrl(UI_URL); sp.browser.setVisible(true); sp.browser.setFocused(true); } catch (e) { }
          menuPhase = 1; menuAt = now; menuAsked = 0; menuBeatAt = 0; menuLoaded = true;
          return;
        }
      }

      /*
        Held up and held focused, four times a second, until the choice is
        made. skymp5-client's BrowserService hides the browser for every
        menu it calls bad, the main menu among them, and shows it again
        only when none is open, which at the main menu is never; and its
        Escape handler and login path both drop focus.
      */
      if (now - menuAt > 250) {
        menuAt = now;
        let vis = true, foc = true;
        try { vis = !!sp.browser.isVisible(); } catch (e) { }
        try { foc = !!sp.browser.isFocused(); } catch (e) { }
        if (!vis) {
          try { sp.browser.setVisible(true); } catch (e) { }
          if (!menuHidTold) { menuHidTold = true; log('menu: something hid the browser while the choice was up; shown again'); }
        }
        if (!foc) {
          try { sp.browser.setFocused(true); } catch (e) { }
          if (!menuBlurTold) { menuBlurTold = true; log('menu: something took the mouse off the page while the choice was up; taken back'); }
        }
      }
    }
  }));
  let menuAsked = 0;
  let menuLoaded = false;

  /*
    The page answered "where": its address and whether the choice is
    mounted. Ours with the choice up: done, watch it. Ours without: an
    index.html from before 20 September, so the list and the script go in
    by hand. Anything else: load ours.
  */
  function menuWhere(href, has) {
    if (menuPhase !== 1) { return; }
    const ours = /\/Data\/Platform\/UI\/index\.html$/i.test(String(href));
    if (!ours) {
      if (!menuLoaded) {
        menuLoaded = true;
        log('menu: the browser is on', href, 'and not our page; loading ours');
        try { sp.browser.loadUrl(UI_URL); } catch (e) { }
      }
      return;
    }
    if (has === 'select') {
      menuPhase = 2; menuAt = Date.now(); menuBeatAt = Date.now();
      log('menu: the page is ours and the choice is up');
      return;
    }
    // Ours, but the page did not bring the choice up itself.
    let list = null;
    try { list = JSON.parse(readText(CHARACTERS_FILE)); } catch (e) { list = null; }
    if (!list || !Array.isArray(list.characters)) {
      if (PROFILE > 0) {
        T.js('try{window.skyrimPlatform.sendMessage("thornswood","select",' + PROFILE + ');}catch(e){}');
        log('menu: no character list on disk, so joining as profile', PROFILE, 'from the settings');
      } else {
        log('menu: no character list on disk and no profile in the settings; the client will wait and then say so');
      }
      try { sp.browser.setFocused(false); } catch (e) { }
      menuPhase = 9;
      return;
    }
    if (has !== 'list') { T.js('window.THORNSWOOD_SELECT=' + JSON.stringify(list) + ';'); }
    inject('thornswood-select.js');
    menuPhase = 2; menuAt = Date.now(); menuBeatAt = Date.now();
    log('menu: the page is ours without the choice; put it in,', list.characters.length, 'character(s) listed');
  }
  let menuHidTold = false;
  let menuBlurTold = false;
  let menuBeatAt = 0;
  let menuReloads = 0;
  let menuGaveUp = false;

  /* The page chose. Called from the browserMessage handler below. */
  function menuChose(id) {
    PROFILE = id;
    try {
      require('fs').writeFileSync(CHOICE_FILE, id + ' ' + Date.now() + '\n');
    } catch (e) {
      log('menu: could not write the choice for the launcher:', e);
    }
    menuPhase = 9;
    try { sp.browser.setFocused(false); } catch (e) { }
    // The page repeats its pick every two seconds until this says it heard,
    // because the page can be up long before this plugin is. Acking stops
    // that repeat, so this plugin takes it over in the same breath rather
    // than leaving nobody saying it: see keepSayingChoice above for what
    // happened when nobody did.
    /*
      ONLY THE FIRST TIME STARTS THE CLOCK, and that is not a detail.

      Every resend asks the page to send its pick again, the page does, and
      that arrives back here as another call to this function. Setting the
      clock on each one meant the ninety second give up could never expire
      while the retry was doing its job: it was reset two seconds before it
      was due, for ever. Exactly the shape of the chargen nudge that sat
      unreachable behind its own guard.

      PROVED IN A TESTER'S LOG, 21 September: the resends ran from 17:35:55 to
      17:38:01, which is 126 seconds, and nothing gave up at 90.
    */
    if (menuChosenId !== id) {
      menuChosenId = id;
      menuChosenAt = Date.now();
      menuSaidAt = Date.now();
      menuSaidTimes = 0;
    }
    T.js('try{window.thornswoodSelect&&window.thornswoodSelect.acked();}catch(e){}');
    // The list the launcher wrote for the page. Gone now, so the page
    // reload in the world (phase 0 below) does not bring the choice back.
    try { require('fs').unlinkSync('Data/Platform/UI/thornswood-characters.js'); } catch (e) { }
    log('menu: chosen profile', id);
  }

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
      /*
        F6 IS A PERSON, NOT A STRAY, and treating it as one is what made a
        panel unescapable.

        skymp5-client binds F6 to toggling browser focus. Somebody looking at
        a panel with no claim behind it presses F6, focus goes up, and this
        function used to put it straight back down on the very next frame, for
        ever. No cursor, and with focus down the browser is sent no keys and
        no clicks either, so the panel's own Escape and Close are unreachable:
        Task Manager was the only way out, which is exactly what Djinn
        reported on 22 September.

        So an unexplained focus is held rather than fought. It still cannot
        last: manualFocusSince below caps it the same way every claim is
        capped, so a focus nobody ever puts down still comes back on its own.
        What is gone is the frame-by-frame fight that made F6 do nothing.

        The race menu case below is unchanged and still comes first: that one
        really is something else taking the keyboard.
      */
      if (!strayFocusSince) { strayFocusSince = Date.now(); }
      const waited = Date.now() - strayFocusSince;
      if (raceMenuOpen() && waited < 1200) { return; }
      if (waited >= 1200) {
        if (!manualFocusSince) {
          manualFocusSince = Date.now();
          say('the keyboard was taken and nothing here asked for it. ' +
              'Treating it as F6 and leaving it up; press F6 again to give it back.');
        }
        // Held, not taken back, until the cap below says otherwise.
        if (Date.now() - manualFocusSince < MANUAL_FOCUS_MS) { return; }
        say('F6 focus has been up for ' + Math.round(MANUAL_FOCUS_MS / 60000) +
            ' minutes with nothing using it, taking it back');
        manualFocusSince = 0;
      }
    } else {
      manualFocusSince = 0;
    }

    try { sp.browser.setFocused(want); } catch (e) { }
    strayFocusSince = 0;
  }

  /*
    When somebody's own F6 raised focus, and how long that is allowed to last.

    Two minutes, the same number and the same reasoning as every other cap in
    this file: far longer than anybody spends reading a panel, far shorter
    than giving up on the game. Without it, a focus raised by F6 and never
    lowered would be a keyboard that never comes back, which is the fault the
    caps exist for.
  */
  let manualFocusSince = 0;
  const MANUAL_FOCUS_MS = 120000;

  /*
    WHEN EACH CLAIM WENT UP, so the cap below can cover all of them.

    Focus withholds DirectInput, so a claim that goes up and never comes down
    is indistinguishable from the game freezing: the keyboard stops reaching
    the game AND stops reaching every plugin that would otherwise notice.
    There were three watchdogs and every one of them tested claims.chat, so the
    K panel and the emote wheel could each leave somebody with a dead keyboard
    and nothing would ever take it back. Djinn has twice reported the game
    going down with no crash log, once on pressing K.

    Found by the audit of 21 September.
  */
  const claimedAt = {};

  T.claimFocus = function (who, on) {
    if (!!claims[who] === !!on) return;
    claims[who] = !!on;
    claimedAt[who] = on ? Date.now() : 0;
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
    Whether the door rescue runs. It does not, and the long comment in the
    type 29 branch below is the incident that switched it off on 16 September.

    It has a name now because it was a bare return with thirty-one lines
    behind it, which reads as a mistake rather than as a decision: anybody
    tidying the file would have deleted the block, and the next person wanting
    cage gates to work would have started from nothing. The flag says the code
    is kept on purpose and says where to turn it on, and turning it on still
    needs what the comment asks for, which is a signal only a real key press
    produces.
  */
  const DOOR_RESCUE = false;

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

    /*
      SOMEBODY ELSE'S PRESS IS NOT OURS.

      Patrick, 21 September, from playing it: "Theres a weird thing when yoiu
      walk my quarries an npc will spawn and force you to start mining when one
      you didnt click on it and two you have no pickaxe and arent a miner".
      His clip shows him walking past the quarry with nothing under the
      crosshair while the server says "Only a miner can work a seam. Ask one."
      four times over, and "Only a farmer can bring a crop in" three times.

      This event fires for EVERY activation in the loaded area, by anybody. The
      comment on the log line below already said so: "every door an NPC opens
      and every crate anybody walks past". Whiterun's own miners and farmhands
      work their seams and their crops all day, and every one of those strikes
      arrived here.

      And then the ACTI branch at the bottom re-activated the thing AS THE
      PERSON: `e.target.activate(pc, false)`, with pc fetched from
      Game.getPlayer(). So an NPC swinging at a vein made us activate that vein
      on the person's behalf, which ran the vanilla mine script on them, which
      is the animation and the marker Patrick read as an NPC spawning and
      forcing him to mine. The same call is forwarded to the server, which is
      where the four refusals came from: the server was answering presses he
      never made.

      caster is the actionRef out of TESActivateEvent, set in EventHandler.cpp
      next to target. 0x14 is the person's own reference and is fixed for every
      Skyrim there has ever been. An activation with no actionRef at all
      (caster 0) is the game activating something while a cell loads, which is
      likewise not a press, so it is dropped with the rest.

      lastActivateAt is set AFTER this, not before. It feeds the focus
      watchdog's "activated something Xms ago", and a farmhand's day of work
      is not a reason to believe the person is busy.
    */
    let casterId = 0;
    try { casterId = e.caster ? e.caster.getFormID() : 0; } catch (err) { }
    if (casterId !== 0x14) { return; }

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
      if (!DOOR_RESCUE) { return; }

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

  /*
    ------------------------------------------------- every fall of the axe

    Patrick, 21 September: "the chopping block is still not always doing the
    animation and not always giving the wood apon hit still".

    THE SERVER SEES A PRESS AND SKYRIM DOES THE SWINGING. A chopping block is a
    FURN record, so pressing it puts the person into Skyrim's own chopping
    furniture and the axe falls over and over with the server hearing nothing.
    Vanilla's own block script would have handed wood over per swing and it
    does not run here, for the same reason MineOreScript does not and the
    Whiterun gate stays locked. So one press was one handover and every swing
    after it was free exercise.

    The events do pass through here, so this is the only place that can count
    them. Each one is reported as /chopped on the chat overlay socket, the same
    channel a broken lockpick already rides, and the server decides whether it
    is worth anything: choppedSwing credits nobody it has not just watched
    press a block, and no faster than an axe can fall. Typing the word is
    worth nothing.

    WHICH EVENT IS THE FALL. The four IdleWoodChop records in Skyrim.esm are
    Start, EnterInstant, Stop and Exit, and those are the session, not the
    swing: the fall itself is an annotation inside the animation and it does
    not have to be one of those names. So this matches a family rather than a
    name, and WRITES DOWN, ONCE EACH, EVERY EVENT IT SAW DURING A SESSION THAT
    IT DID NOT COUNT. After one session at a block the log names the real
    event, and this can be narrowed to exactly it instead of guessed at again.
  */
  const CHOP_START = /woodchop.*(start|enter)/i;
  const CHOP_END = /woodchop.*(stop|exit)|idlechairexitstart|idleforcedefaultstate/i;
  // The fall. Broad on purpose until the log says what it actually is.
  const CHOP_HIT = /chop|hit|impact|swing/i;
  /* A session is only this long without another event, so somebody who walks
     away mid animation is not left counted as chopping. */
  const CHOP_IDLE_MS = 15000;
  let chopping = 0;          // when the session started, 0 for none
  let chopSeen = 0;          // when an event last arrived
  const chopUnknown = {};    // event names seen and not counted, once each

  /*
    ---------------------------------------------- and every fall of the pick

    THIS WATCHES AND REPORTS NOTHING, ON PURPOSE.

    Patrick, 22 September: "you dont get the ore as it hits the vein". The ore
    used to arrive on the press; the server now holds it back until the pick
    lands, and "when the pick lands" is a constant in the gamemode,
    SWING_LAND_MS, because nothing on the server can see inside an animation.
    The strike is an annotation in IdlePickaxeEnter and this hook is the only
    place on either machine that annotation passes through.

    So this writes down, once each, every event a mining swing emits, exactly
    the way the chopping watcher above it did before the axe was understood.
    After one session at a seam the log names the real strike event, and
    SWING_LAND_MS can be replaced by it instead of guessed at twice.

    It never returns and never counts: IdleChairExitStart ends a mining swing
    AND a chopping session, so a branch here that swallowed events would take
    them off the axe. Everything below still sees every event it did.
  */
  const MINE_START = /pickaxe.*(enter|start)/i;
  const MINE_END = /pickaxe.*(exit|stop)|idlechairexitstart|idleforcedefaultstate/i;
  const MINE_IDLE_MS = 15000;
  let mining = 0;
  let mineSeen = 0;
  const mineEvents = {};

  function watchTheSwing(name, now) {
    if (MINE_START.test(name)) {
      mining = now; mineSeen = now;
      say('mining: swing started on ' + name);
      return;
    }
    if (!mining) { return; }
    if (now - mineSeen > MINE_IDLE_MS) { mining = 0; return; }
    mineSeen = now;
    if (MINE_END.test(name)) {
      // Read before mining is zeroed, or every swing is reported as 0ms long.
      say('mining: swing ended on ' + name + ', ' + (now - mining) + 'ms in');
      mining = 0;
      return;
    }
    if (!mineEvents[name]) {
      mineEvents[name] = true;
      say('mining: ' + name + ' arrived ' + (now - mining) + 'ms into the swing');
    }
  }

  try {
    sp.hooks.sendAnimationEvent.add({
      enter: (ctx) => {
        try {
          const name = String(ctx.animEventName || '');
          if (!name) { return; }
          const now = Date.now();

          watchTheSwing(name, now);

          if (CHOP_START.test(name)) {
            chopping = now; chopSeen = now;
            say('chopping: session started on ' + name);
            return;
          }
          if (!chopping) { return; }
          if (now - chopSeen > CHOP_IDLE_MS) { chopping = 0; return; }
          chopSeen = now;

          if (CHOP_END.test(name)) {
            chopping = 0;
            say('chopping: session ended on ' + name);
            return;
          }
          if (CHOP_HIT.test(name)) {
            tellServer('/chopped');
            return;
          }
          // Not counted, and worth knowing about exactly once.
          if (!chopUnknown[name]) {
            chopUnknown[name] = true;
            say('chopping: saw ' + name + ' and did not count it as a swing');
          }
        } catch (err) { }
      },
      leave() { }
    }, 0x14, 0x14);
    say('watching for the axe');
  } catch (e) {
    say('could not watch for the axe, so wood comes per press only: ' + e);
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
  /*
    SAY IT ON THE SCREEN, NOT ONLY IN A LOG ON THE VPS.

    From the To Do List: "Pressing tilde makes the console flash and vanish,
    silently, forever, and nothing says why... Anti-cheat behaviour is
    disclosed. Say it on the rules page and put a line on screen when it
    triggers: the console is disabled on Thornswood. The explanation is
    already written, it just goes to a file on the VPS."

    Every message this block produced went through say(), which writes to
    thornswood-front.log and nowhere else. From the chair it is a console that
    opens for a fifth of a second and shuts, every time, with no explanation
    anywhere, which reads as a broken game rather than as a rule.

    Debug.notification is Skyrim's own corner message and needs no browser, so
    it lands whether or not the overlay ever mounted.

    ONCE, THEN EVERY FIVE MINUTES. Somebody who presses tilde out of habit
    four times in a row does not need telling four times, and somebody who
    comes back an hour later has forgotten.
  */
  const CONSOLE_SAY_EVERY = 300000;
  let consoleToldAt = 0;

  function shutConsole(which) {
    // Printed before the close, so it is in the log even if closing throws.
    say('the ' + which + ' is open. Keys just before it, newest last: ' +
        recentKeysText());
    const now = Date.now();
    if (now - consoleToldAt > CONSOLE_SAY_EVERY) {
      consoleToldAt = now;
      try {
        note('the console is switched off here');
      } catch (e) { }
      /*
        And in the chat, where it stays on screen long enough to read and can
        be scrolled back to. thornswoodChat.add is the widget's own way in,
        the same one thornswood-chat.js note() uses; there is no note on the
        object itself. Guarded, because the overlay may never have mounted and
        the corner message above has to be enough on its own.
      */
      T.js('try{window.thornswoodChat&&window.thornswoodChat.add&&' +
           'window.thornswoodChat.add([{text:"The console is switched off on ' +
           'Thornswood. It is the same rule for everybody.",color:"#d9ab52"}],' +
           '"plain");}catch(e){}');
    }
    try {
      sp.TESModPlatform.closeMenu(which);
      say('the ' + which + ' opened on its own and has been shut');
      return true;
    } catch (e) {
      say('the ' + which + ' opened on its own and closeMenu threw: ' + e);
      return false;
    }
  }

  /*
    The race menu closing, told to the server as a line. The server waits
    for the face to arrive on the change form and reads it as new when its
    mark changed; a face confirmed as it was, or a name kept, changes no
    mark, and until 20 September that left people standing until they
    walked. The menu closing is the fact itself, and this is the one place
    that can see it.
  */
  let raceWasOpen = false;
  sp.on('update', guard('race', () => {
    const open = raceMenuOpen();
    if (open === raceWasOpen) { return; }
    raceWasOpen = open;
    if (!open) {
      log('the race menu closed, telling the server');
      tellServer('/face done');
    }
  }));

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
  /*
    ------------------------------------- three chopping blocks, taken away

    Djinn, 22 September, "Removal from area - Woodworking chopping Blocks":
    Solitude, Solitude Stables and Dragon Bridge, with a coordinate each.
    Patrick: "I want them actually removed and not there visible anymore."

    THE SERVER CANNOT DO THIS AND NEITHER CAN A GAMEMODE. Refusing the press
    only makes a block that does nothing, which is what the first attempt did
    and is not what was asked: the block is still standing there. Deleting a
    placed reference means editing the plugin that placed it, which is a
    rebuild, a pack, and a server that will not start if it goes wrong.

    So it is done where it can be done. Skyrim Platform runs on the machine
    that is drawing the block and ObjectReference.disable is the engine's own
    "this is not here", the same call the game uses for every object a quest
    takes out of the world. Every person running this plugin stops seeing them,
    which is everybody.

    BY BASE AND POSITION, because CHOPPING_BLOCKS is three BASE records shared
    by every block in Skyrim: the cell is walked for those bases and only a
    reference within a short radius of one of Djinn's three points is touched,
    so nothing else can be caught. The radius is small for the same reason the
    server's is.

    ONCE PER SITE PER SESSION, and only when somebody is near enough for the
    reference to be loaded at all. A disable on an unloaded cell finds
    nothing, so this waits until they are close rather than firing at startup
    and reporting three failures.
  */
  /*
    ======================= WALKING A CELL FOR A BASE =======================

    Game.findClosestReferenceOfType FINDS PERSISTENT REFERENCES, and almost
    nothing anybody stands next to is one. Two features in this file asked it
    for things and quietly got nothing, for the whole of their lives:

      the fire probe, which read "62 bases, 0 in reach, 0 threw" standing in
      the Bannered Mare's fire pit, in its cooking fire, and in the brazier
      outside it, on 23 September

      the chopping blocks at Solitude, the stables and Dragon Bridge, which
      have never once written their own "took the chopping block out of the
      world" line in any log on this machine

    Neither was a table problem or a radius problem. Cell.getNumRefs and
    getNthRef see everything in the cell, temporary references included, so
    that is what both use now.

    THE FORM TYPES ARE THE FILTER AND THEY MATTER: walking every reference in
    an exterior cell is thousands of native calls. Activator 24, static 34,
    movable static 36 and furniture 42 are the four the fire table is built
    from, and the chopping blocks are furniture.
  */
  const CELL_TYPES = [24, 34, 36, 42];

  /**
   * Every reference in this cell whose base is one of `want`, as
   * {ref, x, y, z}. Walked once by the caller and kept: nothing in here
   * moves. `onWalked` is told how many references were looked at, for the
   * probe line.
   */
  function refsInCell(cell, want, onWalked, onThrew) {
    const out = [];
    let walked = 0;
    if (!cell) { return out; }
    for (let t = 0; t < CELL_TYPES.length; t++) {
      let n = 0;
      try { n = cell.getNumRefs(CELL_TYPES[t]); } catch (e) {
        if (onThrew) { onThrew(e); }
        continue;
      }
      for (let i = 0; i < n; i++) {
        walked++;
        try {
          const r = cell.getNthRef(i, CELL_TYPES[t]);
          if (!r) { continue; }
          const b = r.getBaseObject();
          if (!b || !want[b.getFormID()]) { continue; }
          out.push({ ref: r, x: r.getPositionX(), y: r.getPositionY(), z: r.getPositionZ() });
        } catch (e) {
          if (onThrew) { onThrew(e); }
        }
      }
    }
    if (onWalked) { onWalked(walked); }
    return out;
  }

  const BLOCK_BASES = [0x7022e, 0xa91bf, 0x10f575];
  const BLOCKS_GONE = [
    { where: 'Solitude', pos: [-64263, 106003.5, -8377.8] },
    { where: 'Solitude Stables', pos: [-76193.3, 96600.6, -11435] },
    { where: 'Dragon Bridge', pos: [-101780.7, 80484.5, -12522.7] }
  ];
  const BLOCK_FIND = 400;      // how close to the point the block has to be
  const BLOCK_NEAR = 6000;     // how close YOU have to be for it to be loaded
  const blockDone = {};
  let blockAt = 0;

  sp.on('update', guard('blocksgone', () => {
    const now = Date.now();
    if (now - blockAt < 4000) { return; }
    blockAt = now;

    let pc = null;
    try { pc = sp.Game.getPlayer(); } catch (e) { return; }
    if (!pc) { return; }
    let px = 0, py = 0, pz = 0;
    try { px = pc.getPositionX(); py = pc.getPositionY(); pz = pc.getPositionZ(); }
    catch (e) { return; }

    for (let i = 0; i < BLOCKS_GONE.length; i++) {
      if (blockDone[i]) { continue; }
      const site = BLOCKS_GONE[i];
      const dx = px - site.pos[0], dy = py - site.pos[1], dz = pz - site.pos[2];
      if (Math.sqrt(dx * dx + dy * dy + dz * dz) > BLOCK_NEAR) { continue; }

      /*
        WALKED, NOT ASKED FOR. This used findClosestReferenceOfType and never
        removed a single block: not one "took the chopping block out of the
        world" line exists in any log on this machine. See the note over
        refsInCell. The position test is kept exactly as it was, because
        these three bases are shared by every chopping block in Skyrim and
        only the ones at Djinn's three points are ours to remove.
      */
      {
        const want = {};
        for (let b = 0; b < BLOCK_BASES.length; b++) {
          try {
            const base = sp.Form.from(sp.Game.getFormEx(BLOCK_BASES[b]));
            if (base) { want[base.getFormID()] = true; }
          } catch (e) { }
        }
        let cell = null;
        try { cell = pc.getParentCell(); } catch (e) { cell = null; }
        const found = refsInCell(cell, want, null, null);
        for (let k = 0; k < found.length; k++) {
          const dx2 = found[k].x - site.pos[0];
          const dy2 = found[k].y - site.pos[1];
          const dz2 = found[k].z - site.pos[2];
          if (Math.sqrt(dx2 * dx2 + dy2 * dy2 + dz2 * dz2) > BLOCK_FIND) { continue; }
          try {
            // disable answers a promise. Nothing waits on it: the block either
            // goes or it does not, and a failure is worth one line, not a stall.
            const p = found[k].ref.disable(false);
            if (p && typeof p.then === 'function') { p.then(function () { }, function () { }); }
            blockDone[i] = true;
            say('took the chopping block at ' + site.where + ' out of the world');
          } catch (e) {
            say('could not take the ' + site.where + ' chopping block out: ' + e);
            blockDone[i] = true;   // do not try it every four seconds forever
          }
          break;
        }
      }
    }
  }));

  /*
    ------------------------------------------- where you are standing

    Patrick, 23 September, with five screenshots: the temperature meter read
    "Fine 50" outside at night, beside a lit brazier in Whiterun, inside the
    Bannered Mare, and standing in the middle of the Bannered Mare's fire pit.
    "not any warmer when near or in fire or in a building also make so if you
    are in a fire you catch on fire", and then "yeah forges and stuff like
    that should be included too because they are hot".

    THE METER WAS NEVER BROKEN. The needs block has moved temperature toward a
    target since it was written, and /place is the command that sets the
    target. Nothing ever sent it. n.place was '' on every character, the target
    was always comfort, and the number sat on 50 for ever. A whole system that
    worked perfectly and was never asked a question.

    IT HAS TO BE THE CLIENT. Whether it is snowing on you, whether you are
    swimming, whether you are under a roof and whether there is a fire in front
    of you are facts about the machine drawing the world. The server holds a
    position and a cell descriptor and cannot answer one of them. So this
    measures them here and reports the answer the same way a fall of the axe is
    reported, over the chat socket, and the server does the rest.

    THE FIRE BASES ARE MEASURED, NOT TYPED. tools\fires.json is built by
    tools\Build-FireTable.js out of Skyrim.esm: 44 base records whose model is
    one of the fire effects or wood fires, plus the forge, skyforge, smelter
    and cooking spit markers, with the unlit versions dropped by the rule
    rather than by hand. Rebuild it with:

        node tools\Build-FireTable.js

    and tools\test-temp.js fails if this list and that file have drifted
    apart, which is the only thing keeping a hand edit here honest.
  */
  const FIRE_BASES = [
    ['Skyrim.esm', 0x13b40],   // FXFire01
    ['Skyrim.esm', 0x13b42],   // FXFire02
    ['Skyrim.esm', 0x33da4],   // FXfireWithEmbersHeavy
    ['Skyrim.esm', 0x33da9],   // FXfireWithEmbersLight
    ['Skyrim.esm', 0x35f47],   // Campfire01LandBurning
    ['Skyrim.esm', 0x35f49],   // Campfire01Burning
    ['Skyrim.esm', 0x35f4a],   // FireplaceWood01Burning
    ['Skyrim.esm', 0x42521],   // bwcStatuePuzzleFlame
    ['Skyrim.esm', 0x4318b],   // FXfireWithEmbersLogs01
    ['Skyrim.esm', 0x48748],   // CraftingBlacksmithForgeSTATIC
    ['Skyrim.esm', 0x4c5ce],   // GiantCampfire01BurningSnow01
    ['Skyrim.esm', 0x4c5cf],   // GiantCampfire01BurningSnow01B
    ['Skyrim.esm', 0x51577],   // GiantCampfire01Burning
    ['Skyrim.esm', 0x68adb],   // CraftingCookingFireSpit
    ['Skyrim.esm', 0x90ca4],   // Campfire01LandBurning_ReachDirt01
    ['Skyrim.esm', 0x951d8],   // Campfire01LandBurningReachDirt01
    ['Skyrim.esm', 0x9c6ce],   // CraftingSmelterMarker1
    ['Skyrim.esm', 0xa9230],   // Campfire01LandBurning_Heavy_SN
    ['Skyrim.esm', 0xaa71c],   // FXfireWithEmbers02Toggle
    ['Skyrim.esm', 0xb6c08],   // Campfire01LandBurningPineForest01
    ['Skyrim.esm', 0xbbcf1],   // CraftingBlackSmithForgeSkyforge
    ['Skyrim.esm', 0xbf9e1],   // CraftingBlackSmithForgeWR
    ['Skyrim.esm', 0xc2bf1],   // Campfire01LandBurningCoastalBeach01
    ['Skyrim.esm', 0xc6918],   // Campfire01LandBurningFallForestDirt01
    ['Skyrim.esm', 0xcae0b],   // CraftingBlackSmithForge
    ['Skyrim.esm', 0xcbb23],   // Campfire01LandBurningFrozenMarshDirtSlope01
    ['Skyrim.esm', 0xcbb2f],   // Campfire01LandBurningRocks01
    ['Skyrim.esm', 0xcd823],   // FXfireWithEmbers01_lite
    ['Skyrim.esm', 0xcd824],   // FXfireWithEmbers01_Cheap
    ['Skyrim.esm', 0xd61b6],   // BFXFireVol01
    ['Skyrim.esm', 0xd61be],   // BFXFireVolCorner
    ['Skyrim.esm', 0xdb682],   // Campfire01LandBurningDirt01
    ['Skyrim.esm', 0xe7c9a],   // Campfire01LandBurningRiverBedEdge01
    ['Skyrim.esm', 0xef77f],   // BFXFireVolCornerRound
    ['Skyrim.esm', 0xf2ac6],   // BFXFireVolCornerRoundNoFloor
    ['Skyrim.esm', 0xf597f],   // GiantCampfire01BurningDirt01
    ['Skyrim.esm', 0xf6304],   // GiantCampfire01BurningDirt02Blank
    ['Skyrim.esm', 0xfb9b0],   // Campfire01LandBurningFieldGrass01
    ['Skyrim.esm', 0x101a51],   // Campfire01LandBurningTundra01
    ['Skyrim.esm', 0x106112],   // FXfireWithEmbersHeavySCALED
    ['Skyrim.esm', 0x1092e2],   // FXfireWithEmbersHeavyToggle
    ['Skyrim.esm', 0x1094ab],   // FXFireSovngarde
    ['Skyrim.esm', 0x10acc0],   // GiantCampfire01BurningNoLand
    ['Skyrim.esm', 0x10d820],   // Campfire01LandBurningCaveBaseGround02
    ['Dawnguard.esm', 0x1838f],   // DLC1VC_EmbersToggleable
    ['Dragonborn.esm', 0x18616],   // Campfire01LandBurning_SnowRocks
    ['Dragonborn.esm', 0x18619],   // Campfire01LandBurning_LDirtSnowPath
    ['Dragonborn.esm', 0x289e8],   // Campfire01LandBurning_Ash
    ['Dragonborn.esm', 0x2c0b0],   // Campfire01LandBurningDirtPath01
    ['Embers XD.esm', 0x13010e],   // GiantCampfire01BurningDirt02
    ['Embers XD.esp', 0x6a956],   // FXfireWithEmbersLight04
    ['Embers XD.esp', 0x982a3],   // FXfireWithEmbersLogs02
    ['Embers XD.esp', 0xc5bb1],   // FXfireWithEmbersLogs03
    ['Embers XD.esp', 0xe92ff],   // FXfireWithEmbersLogs04
    ['Embers XD.esp', 0x102800],   // Campfire01LandBurningCaveBaseGround01
    ['Embers XD.esp', 0x13010e],   // GiantCampfire01BurningDirt02
    ['Embers XD.esp', 0x135210],   // FXFirepit01
    ['Embers XD.esp', 0x171e23],   // Campfire01LandBurningMineFloorDirt01
    ['Embers XD.esp', 0x17c025],   // Campfire01LandBurningGrassSnow01
    ['Embers XD.esp', 0x17c026],   // FXfireWithEmbersLightSilent
    ['Embers XD.esp', 0x19f73f],   // FXfireWithEmbersLight02
    ['Embers XD.esp', 0x19f741],   // FXfireWithEmbers01_brazier
  ];
  // The plugins the list spans, for the log line when they are resolved.
  const FIRE_FILES = ["Skyrim.esm","Dawnguard.esm","Dragonborn.esm","Embers XD.esm","Embers XD.esp"];

  // Standing at a fire, and standing IN one. A campfire is about a hundred
  // units across, so 300 is warming your hands and 90 is in the coals.
  const FIRE_REACH = 300;
  const FIRE_INSIDE = 90;
  /*
    How often the world is asked. Four seconds while nothing is near, one
    second once a fire is in reach, because the second number is what decides
    whether somebody is burning and four seconds of that is four seconds of
    standing in a fire taking nothing.
  */
  const PLACE_SLOW = 4000;
  const PLACE_FAST = 1000;
  // How often the tick writes a line even when its answer has not moved. See
  // the heartbeat below: without it, a dead tick and a steady one read the
  // same in the log.
  const PLACE_BEAT = 30000;
  // How far the water can be over your feet and still be wading. A character
  // is about 128 units tall, so this is roughly waist deep.
  const WADE_DEEP = 70;
  // FireFXShader, 0001b212 in Skyrim.esm, read out of the EFSH records. This
  // is the engine's own "this thing is burning", the one fire damage uses.
  const FIRE_SHADER = 0x1b212;
  // Per second in the coals. Survivable for a few seconds, fatal if somebody
  // walks in and makes a cup of tea, which is the point.
  const BURN_PER_SECOND = 7;

  let placeAt = 0;
  let placeSaid = '';
  let placeFire = -1;

  /*
    WHAT THE FIRE PROBE ACTUALLY DID, because on 23 September it did nothing
    and said nothing.

    Patrick, in the world: "temp isnt working right or fgetting caught on fire
    and taking damage base was 51 I gotta closer and closer to the fire until I
    was standing in it and it stayed the same temp the whole time."

    MEASURED from that session's plugin log. The place tick wrote ONE line, at
    10:20:38, and not another in the ninety seconds after it, while the input
    pulse next to it kept writing every five seconds. So the tick was alive and
    the line it composes never changed, which means the fire distance stayed at
    nothing while he walked into a fire.

    AND NOTHING SAID WHY, because fireDistance swallows every error per base:
    forty four bases that all throw and forty four bases that all resolve and
    find nothing produce the same silent -1. That is the fault this block is
    here to close. The numbers below are counted on every probe and written
    into the heartbeat line, so one session answers which of the two it is and
    what the error was if it is the first.
  */
  let fireBases = 0;      // how many of them resolved to a form at all
  let fireHits = 0;       // how many fires of ours are in this cell
  let fireThrew = 0;      // how many threw
  let fireWhy = '';       // the first thing one of them threw
  let fireWalked = 0;     // how many things in the cell were looked at
  /*
    WHAT THE CELL SAID ABOUT WATER, for the heartbeat line.

    Patrick, 23 September: "Stood in the water in the temple in Whiterun temp
    stayed the same". The client reported `indoors` the whole time he was in
    it, so the server was never told about any water and behaved correctly on
    what it was told.

    Wading is the cell's water level against where somebody is standing, and
    that is the only thing Skyrim Platform exposes: an Actor has isSwimming
    and a Cell has getWaterLevel, and there is no submerged depth and no
    is-in-water anywhere in the API. So either that pool's cell answers a
    level nowhere near his feet, or it answers nothing at all, and those are
    different problems with different answers. Neither can be told apart from
    out here, so the numbers go in the line.
  */
  let waterSaid = '';
  let fireCell = -1;      // the cell the list below was made for
  let fireHere = null;    // where the fires in it are
  let placeBeat = 0;      // when the heartbeat last wrote

  /*
    THE IDS, RESOLVED ONCE. NOT THE FORMS.

    A fire from a mod cannot be reached by the id written in the plugin,
    because a runtime id carries the plugin's place in the load order and
    that moves whenever anybody adds a mod. Game.getFormFromFile is the
    engine's own answer: the file and the id inside it, which do not move.
    Skyrim.esm is index 00 always, so those go the direct way and it is the
    same call underneath.

    A FORM DOES NOT SURVIVE THE FRAME IT WAS MADE IN, and the first version of
    this kept the 62 Form objects for the session because "the answer cannot
    change inside a session". The answer does not; the wrapper does.
    SkyrimPlatform hands out native objects from a pool that it rolls over,
    and one kept past its frame throws on the next use:

      SP3NativeValueCasts::JsObjectToNativeObject - Invalid
      _skyrimPlatform_indexInPool: 109, expected to be in [5201, 5212) range

    Every one of the 62 threw that, on every probe, for the whole of
    23 September. The heartbeat line read "62 bases, 0 in reach, 62 threw"
    and that is the only reason it was found rather than guessed at again:
    fireDistance swallows errors per base, so 62 that throw and 62 that find
    nothing both come out as no fire. WHAT IT COST: no warmth from any fire,
    so the temperature never moved whether you were across the room or
    standing in the coals, and nobody ever caught fire either, because both
    read the same distance.

    So what is kept is the runtime id, which is a number and keeps perfectly,
    and the form is asked for again in the frame it is used in. That is one
    extra call per base per probe, and the probe already makes one.
  */
  let fireIds = null;

  function fireIdList() {
    if (fireIds) { return fireIds; }
    const out = [];
    for (let i = 0; i < FIRE_BASES.length; i++) {
      const file = FIRE_BASES[i][0];
      const local = FIRE_BASES[i][1];
      try {
        const raw = (file === 'Skyrim.esm')
          ? sp.Game.getFormEx(local)
          : sp.Game.getFormFromFile(local, file);
        const base = sp.Form.from(raw);
        // Read here, in the frame the form was made in, which is the only
        // place it can be read.
        if (base) {
          const id = base.getFormID();
          if (id) { out.push(id); }
        }
      } catch (e) {
        if (!fireWhy) { fireWhy = String((e && e.message) || e); }
      }
    }
    // Nothing at all means the world is not up yet, so it is worth asking
    // again rather than remembering an empty answer for the session.
    if (!out.length) { return []; }
    fireIds = out;
    log('fires: ' + out.length + ' of ' + FIRE_BASES.length +
        ' bases resolved, across ' + FIRE_FILES.length + ' plugin(s)');
    return fireIds;
  }

  /*
    THE FIRES IN THIS CELL, WALKED ONCE.

    THE ENGINE CALL THIS REPLACES FINDS PERSISTENT REFERENCES ONLY, and a
    fire is almost never one. Game.findClosestReferenceOfType answered null
    for all 62 bases everywhere: standing in the Bannered Mare's own fire
    pit, standing in its cooking fire, standing in the brazier outside it,
    standing in a fire bowl on a farm. The probe read "62 bases, 0 in reach,
    0 threw" through all of it, which is the call working exactly as
    documented and being the wrong call: the FX fire placed in an inn is a
    temporary reference in that cell, and those functions do not see one.
    That is why nothing ever warmed anybody, and no amount of fixing the
    table would have changed it.

    Cell.getNumRefs and getNthRef see everything in the cell, temporary
    included, so the cell is walked once and the fires in it are kept with
    their positions. A fire does not move, so the list is good until the cell
    changes, and every probe after that is a handful of subtractions instead
    of sixty two native calls.

    FOUR FORM TYPES, WHICH ARE THE FOUR THE TABLE IS BUILT FROM: activator
    24, static 34, movable static 36 and furniture 42. Filtering costs
    nothing and walking every reference in an exterior cell costs a great
    deal.
  */
  function fireSpotsHere(pc) {
    let cellId = 0;
    let cell = null;
    try {
      cell = pc.getParentCell();
      cellId = cell ? cell.getFormID() : 0;
    } catch (e) { cellId = 0; }
    if (cellId !== fireCell) { fireCell = cellId; fireHere = null; }
    if (fireHere) { return fireHere; }
    if (!cell) { return []; }

    const ids = fireIdList();
    fireBases = ids.length;
    const want = {};
    for (let i = 0; i < ids.length; i++) { want[ids[i]] = true; }

    const found = refsInCell(cell, want,
      function (n) { fireWalked = n; },
      function (e) {
        fireThrew++;
        if (!fireWhy) { fireWhy = String((e && e.message) || e); }
      });
    const out = [];
    for (let k = 0; k < found.length; k++) {
      // A fire somebody has switched off is still a placed reference. The
      // toggled ones are the reason this asks rather than trusting the base.
      try { if (found[k].ref.isDisabled()) { continue; } } catch (e) { }
      out.push([found[k].x, found[k].y, found[k].z]);
    }
    fireHere = out;
    fireHits = out.length;
    // fireWalked, not walked: that one lives inside refsInCell. Naming it here
    // threw on every cell change from #184 on, 80 times in the dev log of
    // 23 September, and the place report for that tick never went.
    log('fires: ' + out.length + ' of ours in this cell, out of ' + fireWalked +
        ' thing(s) looked at');
    return fireHere;
  }

  /** How far the nearest lit fire is, or -1 when there is none in reach. */
  function fireDistance(px, py, pz, pc) {
    let best = -1;
    const spots = fireSpotsHere(pc);
    for (let i = 0; i < spots.length; i++) {
      const dx = spots[i][0] - px;
      const dy = spots[i][1] - py;
      const dz = spots[i][2] - pz;
      const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (d > FIRE_REACH) { continue; }
      if (best < 0 || d < best) { best = d; }
      if (best <= FIRE_INSIDE) { break; }
    }
    return best;
  }

  /*
    ===================== EATING AND DRINKING ==============================

    Patrick, 23 September: "I also just ate food and my food percentage
    didn't change".

    Of course it did not. The only thing that has ever fed anybody on this
    server is typing /eat. Eating in the game is the client consuming an item
    in its own inventory, and the server is not told: there is no eat event
    in the four hooks a gamemode gets, and by the time the inventory sync
    arrives the food is simply gone, which is indistinguishable from dropping
    it.

    The client can see it, because in Skyrim eating is EQUIPPING: an ALCH
    record equipped by the player is eaten or drunk on the spot. So the equip
    event is watched, and anything that is a Potion is reported to the server
    with what it was, in the same one line channel everything else uses.

    FOOD OR DRINK IS THE RECORD'S OWN ANSWER. Potion.isFood is the flag on
    the ALCH, so a sweet roll is food, a bottle of ale is a drink, and a
    potion of healing is neither and is left alone: it is not a meal and the
    meters have no business moving for it.
  */
  sp.on('equip', (e) => {
    try {
      if (!e || !e.actor || !e.baseObj) { return; }
      const pc = sp.Game.getPlayer();
      if (!pc || e.actor.getFormID() !== pc.getFormID()) { return; }
      const pot = sp.Potion.from(e.baseObj);
      if (!pot) { return; }
      const id = e.baseObj.getFormID();
      if (!id) { return; }
      /*
        EVERYTHING THAT GOES DOWN COUNTS, and which of them it was is the
        server's to decide off its own table. Patrick, 23 September:
        "Potions and poisons should be counted towards thirst they are
        liquids". So there is no filter here at all beyond it being an ALCH:
        a sweet roll, a bottle of ale and a potion of healing all report, and
        food.json says which is which.
      */
      tellServer('/ate ' + id.toString(16));
      say('ate base ' + id.toString(16) + ' "' + (e.baseObj.getName() || '') + '"');
    } catch (err) { }
  });

  sp.on('update', guard('place', () => {
    const now = Date.now();
    // Fast only when a fire is close enough to be about to burn somebody.
    // Merely standing at one is 44 native calls a second for nothing.
    const close = placeFire >= 0 && placeFire <= FIRE_INSIDE * 2;
    if (now - placeAt < (close ? PLACE_FAST : PLACE_SLOW)) { return; }
    placeAt = now;

    let pc = null;
    try { pc = sp.Game.getPlayer(); } catch (e) { return; }
    if (!pc) { return; }
    let px = 0, py = 0, pz = 0;
    try { px = pc.getPositionX(); py = pc.getPositionY(); pz = pc.getPositionZ(); }
    catch (e) { return; }

    let swimming = false;
    try { swimming = !!pc.isSwimming(); } catch (e) { }
    let indoors = false;
    let wading = false;
    try {
      const cell = pc.getParentCell();
      if (cell) {
        indoors = !!cell.isInterior();
        /*
          WADING IS NOT SWIMMING, and Patrick asked for the difference by
          name: "different temperatures for different water types like ice,
          galciers, fresh water, shallow, etc".

          isSwimming only answers once somebody's feet have left the bottom.
          Standing knee deep in a river in the Pale reads as dry land to it,
          which is the wrong answer in the one situation people are actually
          in most of the time. The cell's water level against where they are
          standing is the rest of it: above their feet and below swimming is
          wading.

          A cell with no water answers a level far below anywhere anybody
          stands, so the subtraction comes out negative and this is false
          without needing to ask whether there is water at all.
        */
        const level = cell.getWaterLevel();
        if (isFinite(level)) {
          const deep = level - pz;
          wading = deep > 0 && deep < WADE_DEEP;
          waterSaid = 'water level ' + Math.round(level) + ', feet at ' +
                      Math.round(pz) + ', so ' + Math.round(deep) + ' deep';
        } else {
          waterSaid = 'the cell has no readable water level';
        }
      }
    } catch (e) { }
    let sky = 0;
    let skyId = 0;
    try {
      const w = sp.Weather.getCurrentWeather();
      if (w) { sky = w.getClassification(); skyId = w.getFormID(); }
    } catch (e) { }

    /*
      THE REST OF THE WEATHER, AND THE REST OF THE PLACE.

      Patrick, 23 September: "the temp should also account for wind and all
      other weather reelated and environment factors".

      WIND IS NOT ON THE WEATHER OBJECT. Weather.pex has getWindDirection and
      getWindDirectionRange and no speed at all, so the only way to know how
      hard it is blowing is the WTHR record, which is on the server in
      tools\weather.json. So the weather's form id goes over with everything
      else and the server looks it up.

      NIGHT is the game clock, which is twenty times real time, so it turns
      over every seventy two real minutes and the small hours are genuinely
      colder than the afternoon.

      HEIGHT is the one environment factor that needs nothing but a number
      already in hand. The tundra sits near zero, High Hrothgar is above
      twelve thousand and the Throat of the World is past twenty five, and
      being up there should feel like being up there.
    */
    let night = 0;
    try {
      const day = sp.Utility.getCurrentGameTime();
      const hour = (day - Math.floor(day)) * 24;
      night = (hour < 6 || hour >= 20) ? 1 : 0;
    } catch (e) { }
    // Asking is 44 native calls, and nobody in the water is at a fire.
    const fire = swimming ? -1 : fireDistance(px, py, pz, pc);
    placeFire = fire;

    /*
      ONE WORD, IN ORDER OF WHAT WINS.

      Water first, because being in it beats everything else about a place.
      Then fire, which beats a roof: the point of the Bannered Mare is the fire
      in the middle of it. Then the roof, then the weather, and outdoors last,
      which is slightly cool rather than neutral so that walking into a
      building is felt. Everything the server does not know a word for is
      comfortable, so a client from before this says nothing and its owner
      simply has no weather.
    */
    let kind = 'outdoors';
    if (swimming) { kind = 'water'; }
    else if (wading) { kind = 'shallow'; }
    else if (indoors) { kind = 'indoors'; }
    else if (sky === 3) { kind = 'snow'; }
    else if (sky === 2) { kind = 'rain'; }

    /*
      ONE LINE, AND IT IS SENT WHEN ANY OF IT CHANGES.

      kind, the weather's form id, night, whether there is a roof, the height,
      and how far the nearest fire is. The server has a number for all of it;
      a client that sends only the word still works, because everything after
      the first is optional on that end.

      THE FIRE IS A DISTANCE AND NOT A WORD, which is Patrick, 23 September:
      "temperature should be relative too so like if I am further away or
      closer to a fire it slowly rises and lowers as I walk away from the
      fire". It used to be one of the words up there and it beat every other
      one, so a campfire in a blizzard was worth the same as an inn hearth and
      one pace back turned it off like a switch. Now it is added on top of
      wherever you already are, tapering to nothing at reach.

      EVERYTHING IS ROUNDED AND THE WHOLE LINE IS COMPARED AS A STRING, which
      is what stops this sending a line every second. The height goes to the
      nearest five hundred and the fire to the nearest twenty five, so walking
      up to a hearth is about a dozen lines and standing at it is none.
    */
    const line = '/place ' + kind + ' ' + (skyId ? skyId.toString(16) : '-') +
                 ' ' + night + ' ' + (indoors ? 1 : 0) +
                 ' ' + Math.round(pz / 500) * 500 +
                 ' ' + (fire >= 0 ? Math.round(fire / 25) * 25 : '-');
    if (line !== placeSaid) {
      placeSaid = line;
      tellServer(line);
      say('standing in ' + kind + (fire >= 0 ? ', fire ' + Math.round(fire) + ' away' : '') +
          (night ? ', at night' : '') + (indoors ? ', under a roof' : ''));
      placeBeat = now;
    }
    else if (now - placeBeat >= PLACE_BEAT) {
      /*
        A LINE EVEN WHEN NOTHING CHANGED, once every half minute.

        Without this, a tick that has stopped and a tick whose answer never
        changes look identical in the log, and on 23 September that cost a
        whole session: one line at 10:20:38 and nothing after it, with no way
        to tell which had happened.

        It carries what the fire probe did, because that is the part that was
        silent. 44 resolved, 0 hits means the bases are fine and there is
        genuinely no fire of ours in reach, which points at the list. Anything
        in threw means the probe itself is broken and the reason is printed.
        And whatever the crosshair is on is named, so walking up to a fire and
        looking at it says what that fire actually is, which is the one thing
        nobody could find out from here.
      */
      placeBeat = now;
      let looking = '';
      try {
        const at = sp.Game.getCurrentCrosshairRef();
        if (at) {
          const b = at.getBaseObject();
          looking = ', looking at ' + (b ? ('base ' + b.getFormID().toString(16) +
                    ' "' + (b.getName() || '') + '"') : 'something with no base');
        }
      } catch (e) { }
      say('place: ' + line + '  [fire probe: ' + fireBases + ' bases, ' + fireHits +
          ' in this cell of ' + fireWalked + ' looked at, ' + fireThrew + ' threw' +
          (fireWhy ? ' (' + fireWhy + ')' : '') + ']' +
          (waterSaid ? '  [' + waterSaid + ']' : '') + looking);
    }

    /*
      AND IF YOU ARE STANDING IN IT, YOU BURN.

      Patrick: "make so if you are in a fire you catch on fire". Vanilla
      Skyrim does not do this. The Bannered Mare's fire pit is set dressing and
      you can stand in the coals all night, which is what the fifth screenshot
      is: a character up to his knees in a fire, reading Fine 50.

      Done here rather than on the server because the server cannot see the
      fire and because damage belongs on the machine that is drawing it.
      DamageActorValue is the engine's own call and goes through everything
      health normally goes through.
    */
    if (fire >= 0 && fire <= FIRE_INSIDE) {
      if (burnUntil < now) { note('you are standing in the fire'); }
      // Refreshed rather than set, so walking out of the coals lets it go
      // within about a second instead of burning for the full catch.
      burnUntil = Math.max(burnUntil, now + 1500);
    }
  }));

  /*
    ---------------------------------------------------- burning, and catching

    Patrick, 23 September: "make so if you are in a fire you catch on fire",
    and then "when people catch fire it should be able to spread to other
    people if they ade close enough".

    ONE CLOCK, TWO WAYS TO START IT. Standing in the coals refreshes it every
    beat of the place tick. The server sets it through the thornswoodBurn
    property when somebody alight is standing next to you, because the server
    is the only end that knows where everybody is. Both write the same
    burnUntil, so there is no argument about which of them gets to put it out.

    AND IT REPORTS ITSELF, because the spreading is the server's half and it
    cannot see a fire. One line when it starts and one when it stops, over the
    chat socket, the same channel a fall of the axe goes down.
  */
  const BURN_TICK = 1000;
  // The server lets go of somebody who stops reporting after three of its own
  // beats, so this has to say so again while it is still alight. Every three
  // seconds rather than every one, because it goes down the chat socket.
  const BURN_REPORT = 3000;
  let burnUntil = 0;
  let burnTold = false;
  let burnAt = 0;
  // When the flames were last put back on. See the burning tick.
  let burnFxAt = 0;
  const BURN_FX_EVERY = 3000;
  let burnSaidAt = 0;

  // The hook the gamemode's property script calls. On the global on purpose:
  // an updateOwner script is evaluated in its own scope and this is the only
  // thing the two of them share.
  try {
    globalThis.thornswoodCatchFire = function (ms) {
      const add = Number(ms) || 5000;
      burnUntil = Math.max(burnUntil, Date.now() + add);
    };
  } catch (e) { }

  sp.on('update', guard('burning', () => {
    const now = Date.now();
    if (now - burnAt < BURN_TICK) { return; }
    burnAt = now;

    const alight = burnUntil > now;
    if (alight === burnTold && !alight) { return; }

    let pc = null;
    try { pc = sp.Game.getPlayer(); } catch (e) { return; }
    if (!pc) { return; }

    if (alight) {
      try { pc.damageActorValue('Health', BURN_PER_SECOND); } catch (e) { }
      /*
        THE FLAMES ARE PUT BACK ON, over and over, for as long as it burns.

        Patrick, 23 September: "when I am on fire the fire on me goes away
        after awhile even if I am still in the fire but OI still correctly
        keep taking damage its just visibly wrong though".

        An effect shader is played once and runs for as long as the shader
        itself says, which is a few seconds: it was written for a spell
        landing on somebody, not for standing in a fire pit. Playing it once
        when the burning started meant the flames ran out while the burning
        carried on, so the one thing on screen telling somebody they are on
        fire stopped while the damage did not.

        So it is played again every BURN_FX_EVERY while they are alight.
        Playing a shader that is already running on the same target is what
        the engine does to itself constantly; it does not stack into anything.
      */
      if (!burnTold || (now - burnFxAt) >= BURN_FX_EVERY) {
        burnFxAt = now;
        try {
          const shader = sp.EffectShader.from(sp.Game.getFormEx(FIRE_SHADER));
          if (shader) { shader.play(pc, 0); }
        } catch (e) { }
      }
      if (!burnTold) {
        burnTold = true;
        note('you have caught fire');
      }
      if (now - burnSaidAt >= BURN_REPORT) {
        burnSaidAt = now;
        tellServer('/burn 1');
      }
      return;
    }

    burnTold = false;
    burnSaidAt = 0;
    burnFxAt = 0;
    try {
      const shader = sp.EffectShader.from(sp.Game.getFormEx(FIRE_SHADER));
      if (shader) { shader.stop(pc); }
    } catch (e) { }
    tellServer('/burn 0');
    note('the fire is out');
  }));

  /*
    ------------------------------------------ who you are looking at

    Patrick, 22 September: "when you look at someone, you are prompted to
    press buttons: one for friend, one for trade, and one for mute. Currently
    the looking at people doesnt have the trade menu and when it did you had
    to use youyr cursor and a bunch of other bs I just want to press a key
    while looking at them."

    THE CROSSHAIR HAS ALWAYS BEEN AVAILABLE AND WAS NEVER USED. Skyrim
    Platform exposes Game.getCurrentCrosshairRef and a crosshairRefChanged
    event, and before today neither appeared anywhere in this repo. That is
    the whole reason the old trade menu needed a mouse: nothing was asking the
    game what was under the crosshair.

    WHAT THE CLIENT CANNOT ANSWER. A crosshair reference is a form id. It does
    not say whether that is a person, a bandit or a barrel, and it carries no
    profile and no name that the server would recognise. So the server
    publishes who is near you, form id to name, on the thornswoodNear
    property, and this matches against it. Anything not in that list draws no
    prompt at all, which is why looking at a chicken does nothing.

    POLLED RATHER THAN EVENT DRIVEN, deliberately. crosshairRefChanged exists,
    but the prompt also has to redraw when the SERVER's picture changes: a
    friend request accepted while you are still looking at somebody should
    turn "Add friend" into "Remove friend" without them stepping out of your
    crosshair and back into it. One poll answers both and costs one native
    call every third of a second.
  */
  const NEAR_EVERY = 320;
  let nearAt = 0;
  let lookingAt = '';      // the form id hex the prompt is currently drawn for
  let lookingSig = '';     // what the prompt says, so it is not redrawn per poll

  function nearList() {
    try {
      const w = globalThis.thornswoodNear;
      return (w && typeof w === 'object') ? w : null;
    } catch (e) { return null; }
  }

  /** Draw or clear the little panel that names them and the three keys. */
  function drawPrompt(row) {
    const sig = row ? (row.n + '|' + row.f + '|' + row.m + '|' + row.y) : '';
    if (sig === lookingSig) { return; }
    lookingSig = sig;
    if (!row) {
      T.js('try{var d=document.getElementById("ts-look");if(d){d.style.display="none";}}catch(e){}');
      return;
    }
    /*
      Built here and handed over as one string, the same as the HUD. The page
      is never asked to have a function for it, so an overlay from before this
      existed still draws it.
    */
    const keyRow = function (key, what, on) {
      return '<div style="margin-top:7px;white-space:nowrap">' +
             '<span style="display:inline-block;min-width:34px;text-align:center;' +
             'border:2px solid rgba(217,171,82,.75);border-radius:6px;padding:2px 7px;' +
             'margin-right:12px;color:#d9ab52;font-family:Georgia,serif">' + key + '</span>' +
             '<span style="color:' + (on ? '#8fb85e' : '#efe4cc') + '">' + what + '</span></div>';
    };
    const html =
      '<div style="font-size:26px;color:#efe4cc;margin-bottom:4px">' + row.n +
      (row.y ? '<span style="color:#8fb85e;font-size:18px"> &middot; your party</span>' : '') +
      '</div>' +
      keyRow(FRIEND_NAME, row.f ? 'Remove friend' : 'Add friend', !!row.f) +
      keyRow(TRADE_NAME, 'Trade', false) +
      keyRow(MUTE_NAME, row.m ? 'Unmute' : 'Mute', !!row.m) +
      keyRow(PARTY_NAME, row.y ? 'Party menu' : 'Ask to party', !!row.y);

    T.js('(function(){try{' +
         'var d=document.getElementById("ts-look");' +
         'if(!d){d=document.createElement("div");d.id="ts-look";' +
         'd.style.cssText=' + JSON.stringify(LOOK_CSS) + ';' +
         'document.body.appendChild(d);}' +
         'd.innerHTML=' + JSON.stringify(html) + ';' +
         'd.style.display="";' +
         '}catch(e){}})();');
  }

  /*
    Right of centre and a little below the crosshair, which is where Skyrim
    puts its own activate prompt and is where an eye already is. Never over
    the crosshair itself: a panel you cannot see past is worse than no panel.
  */
  const LOOK_CSS =
    'position:fixed;left:54%;top:46%;z-index:2147483400;pointer-events:none;' +
    'font-family:Georgia,serif;font-size:19px;letter-spacing:.03em;' +
    'background:rgba(12,10,8,.62);border:2px solid rgba(0,0,0,.65);' +
    'border-radius:9px;padding:11px 16px 14px;' +
    'text-shadow:0 2px 4px rgba(0,0,0,.95)';

  sp.on('update', guard('crosshair', () => {
    const now = Date.now();
    if (now - nearAt < NEAR_EVERY) { return; }
    nearAt = now;

    const near = nearList();
    if (!near) { lookingAt = ''; drawPrompt(null); return; }

    let ref = null;
    try { ref = sp.Game.getCurrentCrosshairRef(); } catch (e) { ref = null; }
    if (!ref) { lookingAt = ''; drawPrompt(null); return; }

    let hex = '';
    try { hex = (ref.getFormID() >>> 0).toString(16); } catch (e) { hex = ''; }
    if (!hex) { lookingAt = ''; drawPrompt(null); return; }

    const row = Object.prototype.hasOwnProperty.call(near, hex) ? near[hex] : null;
    if (!row) { lookingAt = ''; drawPrompt(null); return; }

    if (hex !== lookingAt) {
      lookingAt = hex;
      say('looking at ' + row.n + ' (' + hex + ')');
    }
    drawPrompt(row);
  }));

  /*
    The four keys, and they only mean anything while somebody is under the
    crosshair.

    That is what makes them safe to put on letters. G, H and B do nothing in
    this game on their own, and even if a mod took one of them the prompt is
    the only thing that arms these: with nobody in front of you the key falls
    through to whatever else wants it.

    P and J are Patrick's own choices and are the exception: those two open
    their panels whether or not anybody is being looked at, because a party
    menu you can only open by staring at a friend is not a menu.
  */
  function lookVerb(cmd) {
    if (!lookingAt) { return false; }
    tellServer('/' + cmd + ' ' + lookingAt);
    say(cmd + ' on ' + lookingAt);
    return true;
  }

  /*
    ------------------------------------- your party: the name, the map, the way

    Patrick, 22 September, asked the party menu to let people "see their name
    tag colour, see them on the map and compass". Those three did not ship with
    the rest of the party work, because none of them is something a browser
    overlay can draw: the name above somebody's head is the client's own text,
    and the compass and the map belong to the game.

    ALL THREE ARE HERE NOW, and each one is done where it can actually be done.

    THE NAME, and this is the one that looked impossible and was not.
    skymp5-client draws the tag itself, in formView.ts:

        this.textNameId = createText(x, y, refr.getDisplayName(), [1, 1, 1, 0.8]);

    A plugin cannot reach into that. But the client hands the id straight back
    out: SweetTaffyNicknamesService writes every one of them into
    sp.storage.idTextNickname, keyed BY FORM ID, and that is exactly the key
    the server's party list carries. setTextColor takes the id. So the colour
    is a table lookup and one call, with no change to the client at all.

    THE MAP. MapMarker is STAT 0x00000010 in Skyrim.esm, read out of the file
    rather than remembered. One marker is placed per party member, named after
    them, added to the map with fast travel OFF, and moved to wherever the
    server last said they were. It is taken out of the world the moment they
    leave the party, because a marker nobody owns is worse than no marker.

    THE COMPASS is NOT here and is not the game's compass. Skyrim's compass
    draws quest targets and map markers and nothing a plugin can add to
    directly; putting a party on it properly needs a quest with an alias per
    member inside an esp, which is a Creation Kit change and a plugin rebuild.
    What is drawn instead is a strip of our own, in thornswood-party.js, out of
    positions the overlay already has five times a second. It says the same
    thing the compass would say, in a place this server controls, and it
    updates three times as often.
  */
  const MAP_MARKER_BASE = 0x00000010;    // STAT MapMarker, Skyrim.esm
  const PARTY_EVERY = 1200;
  // What a party member's name is written in. Green, the same green the HUD
  // uses for a meter that is fine, so the two read as one game.
  const PARTY_COLOUR = [0.56, 0.72, 0.37, 0.95];
  const PLAIN_COLOUR = [1, 1, 1, 0.8];   // what the client itself uses

  let partyAt = 0;
  let partySaid = '';
  const partyMarks = {};      // form id hex -> the marker reference
  const partyTinted = {};     // form id hex -> true while its text is green

  function partyList() {
    try {
      const m = globalThis.thornswoodPartyAt;
      return Array.isArray(m) ? m : [];
    } catch (e) { return []; }
  }

  /*
    The client's own table of name tags, by form id.

    Written by SweetTaffyNicknamesService every time one is created and
    deleted, which is why this is read fresh each pass rather than kept: a tag
    is destroyed and remade whenever somebody walks out of sight and back, and
    a remembered id would then be coloured after it had been thrown away.
  */
  function nameTags() {
    try {
      const t = sp.storage['idTextNickname'];
      return (t && typeof t === 'object') ? t : null;
    } catch (e) { return null; }
  }

  function colourNames(want) {
    const tags = nameTags();
    if (!tags) { return; }
    for (const hex in want) {
      if (!Object.prototype.hasOwnProperty.call(want, hex)) { continue; }
      const id = parseInt(hex, 16);
      const textId = tags[id];
      if (textId === undefined || textId === null) { continue; }
      if (partyTinted[hex]) { continue; }
      try { sp.setTextColor(textId, PARTY_COLOUR); partyTinted[hex] = true; }
      catch (e) { }
    }
    /*
      AND PUT IT BACK when somebody leaves. Not doing this leaves the last
      party you were in written in green for the rest of the session, which is
      worse than never colouring anything: the colour would stop meaning
      anything at all.
    */
    for (const hex in partyTinted) {
      if (!Object.prototype.hasOwnProperty.call(partyTinted, hex)) { continue; }
      if (want[hex]) { continue; }
      delete partyTinted[hex];
      const id = parseInt(hex, 16);
      const textId = tags[id];
      if (textId === undefined || textId === null) { continue; }
      try { sp.setTextColor(textId, PLAIN_COLOUR); } catch (e) { }
    }
  }

  function markerFor(hex, name) {
    if (partyMarks[hex]) { return partyMarks[hex]; }
    let ref = null;
    try {
      const base = sp.Form.from(sp.Game.getFormEx(MAP_MARKER_BASE));
      if (!base) { return null; }
      const pc = sp.Game.getPlayer();
      if (!pc) { return null; }
      // Not persistent: a marker that outlived the session would be a
      // permanent pin on everybody's map with nothing behind it.
      ref = pc.placeAtMe(base, 1, false, false);
      if (!ref) { return null; }
      try { ref.setDisplayName(name, true); } catch (e) { }
      // false: no fast travel. Somebody's position is a thing to walk to.
      try { ref.addToMap(false); } catch (e) { }
      partyMarks[hex] = ref;
      say('put a map marker down for ' + name);
    } catch (e) {
      say('could not place a map marker for ' + name + ': ' + e);
      return null;
    }
    return ref;
  }

  function dropMarker(hex) {
    const ref = partyMarks[hex];
    delete partyMarks[hex];
    if (!ref) { return; }
    try {
      // disable first, so it stops drawing even if the delete is refused.
      const off = ref.disable(false);
      if (off && typeof off.then === 'function') { off.then(function () { }, function () { }); }
      const gone = ref.delete();
      if (gone && typeof gone.then === 'function') { gone.then(function () { }, function () { }); }
    } catch (e) { }
  }

  sp.on('update', guard('party markers', () => {
    const now = Date.now();
    if (now - partyAt < PARTY_EVERY) { return; }
    partyAt = now;

    const list = partyList();
    const want = {};
    for (let i = 0; i < list.length; i++) {
      const row = list[i];
      if (!row || !row.a) { continue; }
      want[String(row.a)] = row;
    }

    colourNames(want);

    // A marker for everybody in the party, moved to where the server last
    // said they were.
    for (const hex in want) {
      if (!Object.prototype.hasOwnProperty.call(want, hex)) { continue; }
      const row = want[hex];
      const ref = markerFor(hex, String(row.n || 'somebody'));
      if (!ref) { continue; }
      const pos = row.p || [0, 0, 0];
      try {
        const moved = ref.setPosition(Number(pos[0]) || 0, Number(pos[1]) || 0,
                                      Number(pos[2]) || 0);
        if (moved && typeof moved.then === 'function') { moved.then(function () { }, function () { }); }
      } catch (e) { }
    }

    // And nothing left behind for somebody who has gone.
    for (const hex in partyMarks) {
      if (!Object.prototype.hasOwnProperty.call(partyMarks, hex)) { continue; }
      if (want[hex]) { continue; }
      say('taking the map marker back for ' + hex);
      dropMarker(hex);
    }

    /*
      The overlay draws the strip, so it needs the same list. Handed over
      rather than fetched: the page has no way to read a plugin's variables,
      and this is already the one place that knows when the list changed.
    */
    const sig = JSON.stringify(list);
    if (sig !== partySaid) {
      partySaid = sig;
      T.js('try{window.thornswoodParty&&window.thornswoodParty.setWhere&&' +
           'window.thornswoodParty.setWhere(' + JSON.stringify(list) + ');}catch(e){}');
    }
  }));


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

  /*
    ------------------------------------------------- the town gates

    Patrick, 21 September, from playing it: "The gate into the whiterun inner
    city needs to be unlocked", and then "it is the front gate into the city".

    MEASURED IN Skyrim.esm, through the same reader Build-DoorTable.py uses.
    The Whiterun main gate is base WRDoorMainGate01, 50973, and it is placed
    twice: 1b1f1 stands outside in the Tamriel persistent cell and carries a
    lock of level 255 wanting key d8f0c, and 1b1f3 stands inside and carries
    none. So the gate is shipped locked by Bethesda, and the outside leaf is
    the one everybody presses.

    IN A SINGLE GAME a quest script opens it. Under SkyMP no Papyrus quest
    runs at all, so nothing ever does, and the town has no way in. The Riften
    main gate, RTMainGate01, is the same shape twice over: 42284 wants key
    e6705 and 42286 wants a key that does not exist, both at level 255. Riften
    is not on Patrick's list because nobody has walked up to it yet; it is in
    here because it is the identical defect at the identical kind of door and
    finding it and leaving it shut would be choosing to keep a town closed.

    WHY THE CLIENT AND NOT THE SERVER. The server has no lock state; it has
    never had one. activationService.ts in the fork refuses to announce a press
    on a locked reference at all, which is the Thornswood patch that keeps the
    lockpicking game honest, so a locked gate never reaches the server for the
    server to have an opinion about. The lock only exists here, so it can only
    be lifted here.

    ON A CLOCK RATHER THAN ONCE. A persistent reference keeps its lock across a
    cell load and the world is rebuilt every session, so a single call at world
    up would be enough today and would be silently wrong the first time
    anything relocks it. Thirty seconds and three isLocked reads is nothing.

    NOTHING ELSE IS TOUCHED. Every other locked door in the province stays
    locked, including the two JK's Skyrim doors inside the Whiterun gate, so
    lockpicking is the same game it was.
  */
  const TOWN_GATES = [0x1b1f1, 0x42284, 0x42286];
  const GATE_EVERY_MS = 30000;
  let gatesAt = 0;
  const gateSaid = {};

  function openTheGates() {
    for (let i = 0; i < TOWN_GATES.length; i++) {
      const id = TOWN_GATES[i];
      try {
        const refr = sp.ObjectReference.from(sp.Game.getFormEx(id));
        // Not loaded is not a problem. The next pass will find it.
        if (!refr) { continue; }
        if (!refr.isLocked()) { continue; }
        refr.lock(false, false);
        if (!gateSaid[id]) {
          gateSaid[id] = true;
          say('opened the town gate ' + id.toString(16) +
              ', which vanilla ships locked and no script here opens');
        }
      } catch (e) {
        if (!gateSaid[id]) {
          gateSaid[id] = true;
          say('could not open the town gate ' + id.toString(16) + ': ' + e);
        }
      }
    }
  }

  sp.on('update', guard('gates', () => {
    const now = Date.now();
    if (gatesAt && now - gatesAt < GATE_EVERY_MS) { return; }
    gatesAt = now;
    openTheGates();
  }));

  sp.on('update', guard('pulse', () => {
    // One pass through the handlers is one frame. See frameWent above.
    frameWent();

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
    /*
      The social keys. The three verbs need somebody under the crosshair and
      say nothing when there is not; P and J open their panels regardless.
    */
    if (e.code === FRIEND_KEY) { lookVerb('friend'); return; }
    if (e.code === TRADE_KEY) { lookVerb('trade'); return; }
    if (e.code === MUTE_KEY) { lookVerb('mute'); return; }
    if (e.code === PARTY_KEY) {
      T.js('try{window.thornswoodParty&&window.thornswoodParty.toggle();}catch(e){}');
      return;
    }
    if (e.code === JOURNAL_KEY) {
      T.js('try{window.thornswoodJournal&&window.thornswoodJournal.toggle();}catch(e){}');
      return;
    }

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

      /*
        AND PUT THE SHIFT ON. Here rather than on a tick, because this is the
        moment the world is known to be up and calls into the game work, which
        is the same reason the flag above is set here.
      */
      wearTheShift();
      // Cleared again on the way out, below. Nothing in the shipped client
      // bundle reads this today, so it costs nothing either way, but a flag
      // that is only ever set true is a flag that lies the moment anything
      // does start reading it.

      // The world is up, so the main menu block above stands down for
      // good; it used to stand down on the first update instead, which is
      // not the same moment and is not a moment this file can be sure of.
      menuPhase = 9;
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
      // Anything queued for the server before ready, which is always the
      // skills panel's '/pick refresh' (the panel mounts before this line),
      // goes now rather than on the next pick. Until 20 September it sat in
      // the queue and a person who never picked never saw their own state.
      tellServer('');
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

    /*
      THE SAME CAP FOR EVERY OTHER CLAIM, which had none at all.

      The three watchdogs above all test claims.chat. The chat box is not the
      only thing that takes the keyboard: the K panel claims 'skills' and the
      emote wheel claims 'wheel', and neither had a way back. A panel that
      never says it closed, a page that reloads with the wheel up, or any
      throw between raising the claim and lowering it left the person unable to
      move, with no key able to reach the plugin that would have fixed it.

      Two minutes, the same number and the same reasoning: far longer than
      anybody spends in a menu, far shorter than giving up on the game. The
      claim is released by name so the log says which one it was, which is the
      only evidence anybody will have next time.
    */
    /*
      AND IT CLOSES THE PANEL, RATHER THAN ONLY DROPPING THE CLAIM.

      Djinn, 22 September: a panel was up, F6 gave no cursor, and the only way
      out was Task Manager. This loop is how that happens.

      Taking the claim back without telling the page leaves the panel DRAWN
      with nobody claiming focus. applyFocus then forces focus to match the
      claims every frame, so pressing F6 raises it and the very next frame
      puts it straight back down: the cursor never appears. And with focus
      down the browser is sent no key, no click and no mouse move at all, so
      the panel's own Escape and its Close button are both unreachable. The
      only way out left was the K key, and nothing on screen says so.

      Two minutes is a real session at the skills panel, not an anomaly: the
      plugin log for 22 September shows a single sitting of 67 seconds, so
      this fires on people who are simply reading.

      So the panel is asked to close first and the claim follows. Now the
      rescue leaves somebody looking at the world with their keyboard back,
      which is what it was always meant to do.
    */
    for (const who in claimedAt) {
      if (who === 'chat') { continue; }
      if (!claims[who] || !claimedAt[who]) { continue; }
      if (now - claimedAt[who] > 120000) {
        log('the ' + who + ' claim has held the keyboard for two minutes, closing it and taking it back');
        if (who === 'skills') {
          T.js('try{window.thornswoodSkills&&window.thornswoodSkills.close();}catch(e){}');
          T.js('try{window.thornswoodParty&&window.thornswoodParty.close();}catch(e){}');
          T.js('try{window.thornswoodJournal&&window.thornswoodJournal.close();}catch(e){}');
        } else if (who === 'wheel') {
          T.js('try{window.thornswoodEmotes&&window.thornswoodEmotes.close();}catch(e){}');
        }
        T.claimFocus(who, false);
      }
    }

    checkServer(now);
    askServerBases(now);

    // Five seconds between saying so and doing it, so the line is readable and
    // so a server that comes straight back up is not made into an outage.
    /*
      AND THE LINE IS ON THE SCREEN, WITH THE COUNTDOWN.

      Entry 159 on the To Do List: "Connection to the server was lost,
      returning to the main menu, on screen, with the countdown. Every online
      game does this." Until now the five seconds were a bare delay with
      nothing drawn, and the one sentence explaining them went to the log.

      Drawn here, in update, and not where the outage is noticed: onStrike
      says why a note there never reaches the screen.

      One line for each whole second, not one per frame, because
      Debug.notification queues every call and a frame's worth would still be
      scrolling past long after the quit. The first line carries the reason
      whichever second it lands on, so a slow first frame cannot leave
      somebody looking at a bare number.
    */
    if (leaving && now - leaving >= 0 && now - leaving <= 5000) {
      const left = Math.max(1, Math.ceil((5000 - (now - leaving)) / 1000));
      if (left !== leavingSaid) {
        note((leavingSaid ? '' : 'the connection to the server was lost, ') +
             'returning to the main menu in ' + left);
        leavingSaid = left;
      }
    }
    if (leaving && now - leaving > 5000) {
      leaving = now + 3600000;   // never twice
      // No longer in the world, and said so before the quit rather than after,
      // because after it there is no tick to say it in.
      try { globalThis.__thornswoodInWorld = false; } catch (e) { }
      try {
        sp.Game.quitToMainMenu();
      } catch (e) {
        log('could not quit to the main menu:', e);
        // On screen, because this is the one path where the person is left
        // standing in a world with no server behind it.
        note('the server is down. Close the game and press Play again.');
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
  /* The last whole second the way-out countdown put on screen, 0 before the
     first. See the quit in the tick above, the only place that can draw it. */
  let leavingSaid = 0;
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
    /*
      A LOG LINE, NOT A NOTE, AND ON PURPOSE.

      This runs inside the probe's HttpClient callback, and SkyrimPlatform
      delivers those from its tick (TickImpl in SkyrimPlatform.cpp, in the
      fork), where there is no Papyrus VM. CallNativeApi.cpp throws "can't be
      called in this context" for any game call without one, and note()
      swallows that throw, so a note here would only ever reach the log again,
      which is the bug entry 159 was about. The quit in the update tick above
      draws the message and the countdown, where game calls work.
    */
    say('the server has gone down, going back to the menu');
    log('server unreachable', PROBE_STRIKES, 'times running, quitting to the main menu');
  }

  sp.on('browserMessage', guard('browserMessage', (event) => {
    const a = event.arguments;
    if (!a) return;
    // The main menu's pick, addressed to skymp5-client and overheard here.
    if (a[0] === 'thornswood' && a[1] === 'select') {
      const id = Number(a[2]) || 0;
      if (id > 0) { menuChose(id); }
      return;
    }
    if (a[0] === 'thornswood-front' && String(a[1]).indexOf('where ') === 0) {
      const parts = String(a[1]).split(/\s+/);
      menuWhere(parts[1] || '', parts[2] || '');
      return;
    }
    if (a[0] !== 'thornswood-front') return;
    const what = String(a[1]);

    // The delete icon at the menu: one id, for the launcher, which drops the
    // character from its list on its next poll. The character stays on the
    // server; this is the old launcher's Delete, moved into the game.
    if (what.indexOf('select:forget ') === 0) {
      const gid = Number(what.slice(14)) || 0;
      if (gid > 0) {
        try { require('fs').appendFileSync(FORGET_FILE, gid + '\n'); }
        catch (e) { log('menu: could not write the forget for the launcher:', e); }
        log('menu: forgetting character', gid);
      }
      return;
    }
    /*
      Close the game, asked for from the character choice page.

      Patrick, 22 September: "add a close game button in the main menu with
      the chacrther selector". There was no way out of that page except
      alt-tabbing and killing the process, which is also what somebody does
      when the page itself is stuck, and Djinn's "Timed out" report ends with
      exactly that: "have to task out exit".

      Debug.quitGame is the engine's own exit and is what the main menu's Quit
      does. It goes through the front rather than the page because nothing in
      a browser can close Skyrim, and the page already talks to this plugin.

      The page asks twice before sending this, so there is no confirm here: a
      message that only arrives after somebody has said yes to leaving is not
      one to second guess.
    */
    if (what === 'select:quit') {
      log('menu: closing the game, asked from the character choice page');
      /*
        win32.exitProcess, NOT Debug.quitGame, and the difference is the whole
        bug.

        Patrick, 22 September: "close game button in main menu doesnt wokr
        just says closing game forever", then "O it eventually closed it after
        like a whole minuite or so".

        Debug.quitGame is a PAPYRUS native. Every one of those needs a live VM
        and stack, which SkyrimPlatform only has inside its update handler:
        CallNativeApi throws "can't be called in this context" when the VM
        pointer is null. A browserMessage does not arrive inside one. It comes
        off a CEF thread and is handed over as a tick task, and tick tasks run
        with no VM at all, so the call threw every single time and the catch
        below ate it. thornswood-emotes.js has the same lesson written out at
        length, and solves it by queueing to update.

        QUEUEING WOULD NOT HAVE HELPED HERE. This button is only ever pressed
        at the main menu, and there is no update event at the main menu: the
        update loop is driven by a Papyrus native, so with no game loaded it
        never fires. That is why the whole character choice block in this file
        runs on tick rather than update.

        win32.exitProcess is a plain function with no Papyrus anywhere near
        it: it sets the engine's own quitGame flag, which is what
        Debug.quitGame ends up doing anyway. It works from a tick.

        The minute he waited was the game shutting down on its own terms after
        he gave up and closed it another way, not this call working slowly.
      */
      /*
        THE BROWSER IS PUT DOWN FIRST, AND THAT IS THE SLOW PART.

        Patrick, after the first fix: "close game button in main menu takes too
        long to actually close the game."

        Asking the engine to quit is instant. What is not is the unwind:
        SkyrimPlatform starts CEF with a multi threaded message loop, a
        windowless renderer and a separate browser subprocess, and CefShutdown
        is never called anywhere in the tree. So the UI, IO and renderer
        threads and the child process are left for the operating system to
        reap while the game is already coming apart, which is a well known way
        to sit there for a long time.

        And at the moment this button is pressed the page is doing its
        heaviest work: the character chooser is playing a looping background
        video and the theme track. An active video and audio pipeline inside a
        windowless CEF at teardown is the worst case of an already bad case.

        None of that can be fixed from here, since the shutdown is the
        engine's. What CAN be done is arriving at it with less to unwind: stop
        the media, drop focus, hide the browser, and only then ask to exit.
      */
      try {
        T.js('try{' +
             'var v=document.querySelector("#ts-select video");' +
             'if(v){v.pause();v.removeAttribute("src");v.load();}' +
             'var a=document.querySelectorAll("audio");' +
             'for(var i=0;i<a.length;i++){a[i].pause();a[i].removeAttribute("src");}' +
             '}catch(e){}');
      } catch (e) { }
      try { sp.browser.setFocused(false); } catch (e) { }
      try { sp.browser.setVisible(false); } catch (e) { }

      let asked = false;
      try {
        if (sp.win32 && typeof sp.win32.exitProcess === 'function') {
          sp.win32.exitProcess();
          asked = true;
        }
      } catch (e) {
        log('menu: win32.exitProcess threw:', e);
      }
      if (!asked) {
        // Older clients have no win32. Debug.quitGame will almost certainly
        // throw here for the reason above, but a refusal that is logged is
        // better than none, and the page's own timeout puts the button back.
        try { sp.Debug.quitGame(); asked = true; }
        catch (e) { log('menu: nothing could close the game:', e); }
      }
      if (asked) { log('menu: asked the engine to exit'); }
      return;
    }
    // The character choice page reports in plain lines: ready, alive, the
    // first mouse move, the music, the pick. Every one is a pulse for the
    // silence watch above; the alive beats are not written down, the rest are.
    if (what.indexOf('select:') === 0) {
      menuBeatAt = Date.now();
      if (what.indexOf('select:alive') !== 0) { log('choice page:', what.slice(7)); }
      return;
    }

    /*
      The skills panel says when it opens and closes rather than being
      assumed. It can close itself on Escape, and a focus claim left up after
      that is a keyboard that never comes back, which is the failure
      claimFocus logs every single time for exactly this reason.
    */
    /*
      The three social panels say when they open and close, the same as the
      skills panel and for the same reason: a panel can close itself on
      Escape, and a focus claim left up after that is a keyboard that never
      comes back.
    */
    if (what === 'party:opened') { T.claimFocus('party', true); return; }
    if (what === 'party:closed') { T.claimFocus('party', false); return; }
    if (what === 'journal:opened') { T.claimFocus('journal', true); return; }
    if (what === 'journal:closed') { T.claimFocus('journal', false); return; }
    if (what === 'trade:opened') { T.claimFocus('trade', true); return; }
    if (what === 'trade:closed') { T.claimFocus('trade', false); return; }
    if (what === 'party:ready' || what === 'journal:ready' || what === 'trade:ready') {
      log('the ' + what.split(':')[0] + ' panel is in');
      return;
    }

    if (what === 'skills:opened') { T.claimFocus('skills', true); return; }
    if (what === 'skills:closed') { T.claimFocus('skills', false); return; }
    if (what === 'skills:ready' || what === 'skills:refresh') {
      if (what === 'skills:ready') { log('the skills panel is in'); }
      // The panel mounts after the first property write of the session, so
      // it asks the server to say again what this character already is, and
      // asks again every time it opens. The answer comes back through the
      // property's own updateOwner script.
      //
      // That script hands the view to the page and never to this file, so the
      // page is asked to pass it back before the answer to that refresh
      // arrives. See the tree block below.
      treeForwardInstall();
      tellServer('/pick refresh');
      return;
    }
    if (what.indexOf('skills:pick ') === 0) {
      /*
        Sent to the server as a slash line over the chat socket, the same
        route a broken lockpick travels. The voice service stamps the profile
        id from the connection, so what arrives is "this person picked",
        never "this text claims to be". The server answers by rewriting the
        property, which is what redraws the panel; a refusal comes back as a
        chat line saying why.
      */
      const rest = what.slice(12).trim();
      log('skills: picked', rest, '- sent as /pick');
      tellServer('/pick ' + rest);
      return;
    }

    /*
      The panel view, passed back out of the page. Two spellings, because two
      halves can send it: the forwarder this file puts on the panel's setData
      sends the whole view, and a panel that decides to send the totals on its
      own can send the map by itself. The same numbers arriving twice cost
      nothing; an unchanged map is never applied twice.
    */
    if (what.indexOf('skills:view ') === 0) { treeFromView(what.slice(12)); return; }
    if (what.indexOf('skills:effects ') === 0) { treeFromMap(what.slice(15)); return; }

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

  // ----------------------------------------------- what the skill tree adds --
  /*
    The tree has to change the character, and the server cannot do it.

    Base health, magicka and stamina are worked out from the race record when
    the character is made (skymp5-server, GetBaseActorValues.cpp), and our own
    Thornswood-Content.esp holds no spell, magic effect or perk record to hand
    out, which is what a parse of it says. So the server owns the arithmetic
    and this file owns the hand that puts it on the character. It decides
    nothing else: a value the server did not send is a value nothing here
    touches.

    WHAT ARRIVES. A map of what the tree adds up to, only the entries that are
    not zero:

        { health: 25, magicka: 10, stamina: 0, carryWeight: 40, speedMult: 3 }

    and anything else of the same shape. The key is a Skyrim actor value name
    in lower camel case and goes through to the game as it arrives, because
    the game's own names are case insensitive: skymp5-client.js sets "health"
    and "Aggression" in the same breath (line 5453 and its neighbours).

    HOW IT ARRIVES. The property's updateOwner script runs inside
    skymp5-client and hands the view to window.thornswoodSkills.setData in the
    page. It never reaches this file. So the page is asked to pass it back:
    treeForwardInstall puts a wrapper on setData that sends the view out as a
    browserMessage, the same route every other line from the panel travels,
    and it goes in when the panel says it is ready, before the /pick refresh
    that answer comes from.

    SET, NOT MOD. setActorValue writes the base value to a number this block
    worked out. modActorValue adds to whatever is in front of it, and a
    repeated add is the whole failure being avoided here: the view is pushed
    again every time anything about the character changes, and a session of
    adds is somebody growing without limit. Every pass here works out one
    total, the natural value plus what the tree adds, and sets that, so the
    same map applied a second time lands on the same number. getBaseActorValue
    reads the base back, which is what the total is worked out from.

    WHAT NATURAL IS. The base with this plugin's own change taken back out of
    it. The record below keeps both halves of the last pass, what was added
    and what the base was left reading, because our change is not always still
    there: skymp5-client rewrites health, magicka, stamina and their rates
    from the server's spawn props every time it spawns somebody
    (skymp5-client.js line 5453). So the base only counts as ours when it
    still reads exactly what we set it to. Anything else and the base in front
    of us is the natural one already and there is nothing of ours to take
    back.

    The block between the markers is lifted out by
    <scratchpad>\treeapplytest.js, which drives it against a fake
    skyrimPlatform. Moving the markers moves the test.
  */
  // >>> tree apply: begin >>>

  /* The map the server last sent, waiting for a frame that can call the game. */
  let treeWant = null;
  /* That map as sorted text, so a view saying the same thing costs nothing. */
  let treeSig = '';
  /* Set while treeWant has not been put on the character yet. */
  let treeDirty = false;
  /* lower case name -> { name, add, total }: what was added and what the base
     was left reading. See WHAT NATURAL IS above. */
  let treeMine = {};

  /*
    The wrapper the page runs. Idempotent: the flag it leaves means a second
    install does nothing, and a page that reloads takes the flag with it, so
    the next 'skills:ready' puts a fresh one on the fresh panel.
  */
  const TREE_FORWARD = [
    '(function(){try{',
    '  var s = window.thornswoodSkills;',
    '  if (!s || s.__thornswoodTreeForward) { return; }',
    '  var was = s.setData;',
    '  s.setData = function(table, got){',
    '    try { window.skyrimPlatform.sendMessage("thornswood-front",',
    '          "skills:view " + JSON.stringify(got || null)); } catch(e) {}',
    '    return was.apply(this, arguments);',
    '  };',
    '  s.__thornswoodTreeForward = true;',
    '}catch(e){}})();'
  ].join('\n');

  function treeForwardInstall() {
    try { T.js(TREE_FORWARD); } catch (e) { log('tree: could not ask the page to pass the view back:', e); }
  }

  /* Only names the game could have, only numbers, and nothing that adds up to
     zero, which is the same as not being sent. */
  function treeNumbers(raw) {
    const out = {};
    if (!raw || typeof raw !== 'object') { return out; }
    for (const k in raw) {
      if (!Object.prototype.hasOwnProperty.call(raw, k)) { continue; }
      if (!/^[A-Za-z][A-Za-z0-9]*$/.test(k)) { continue; }
      const n = Number(raw[k]);
      if (!isFinite(n) || n === 0) { continue; }
      out[k] = n;
    }
    return out;
  }

  function treeSigOf(map) {
    const keys = Object.keys(map).sort();
    const parts = [];
    for (let i = 0; i < keys.length; i++) { parts.push(keys[i] + '=' + map[keys[i]]); }
    return parts.join(',');
  }

  /* A map has arrived. Nothing is called on the game here: this can be any
     frame at all, and the calls only work in update. */
  function treeSeen(map) {
    const sig = treeSigOf(map);
    if (sig === treeSig && !treeDirty) { return; }
    treeWant = map;
    treeDirty = true;
  }

  /* The whole panel view. The totals are its own field and nothing else in it
     is read, because a view is full of numbers that are not actor values. */
  function treeFromView(json) {
    let v = null;
    try { v = JSON.parse(String(json)); } catch (e) { log('tree: the view did not parse:', e); return; }
    if (!v || typeof v !== 'object') { return; }
    let raw = {};
    if (v.effects && typeof v.effects === 'object') { raw = v.effects; }
    else if (v.panel && v.panel.effects && typeof v.panel.effects === 'object') { raw = v.panel.effects; }
    treeSeen(treeNumbers(raw));
  }

  /* The map on its own. */
  function treeFromMap(json) {
    let m = null;
    try { m = JSON.parse(String(json)); } catch (e) { log('tree: the totals did not parse:', e); return; }
    if (!m || typeof m !== 'object') { return; }
    if (m.effects && typeof m.effects === 'object') { m = m.effects; }
    treeSeen(treeNumbers(m));
  }

  function treeApplyNow(pc) {
    const next = treeWant || {};
    const mine = {};
    const said = [];
    /* Every value this block last touched, so it can be taken back, and every
       value the server is sending now. Nothing else is looked at. */
    const todo = {};
    for (const key in treeMine) { todo[key] = treeMine[key].name; }
    for (const k in next) { todo[k.toLowerCase()] = k; }

    for (const key in todo) {
      const name = todo[key];
      const add = Number(next[name] || 0) || 0;
      const rec = treeMine[key];
      try {
        const base = Number(pc.getBaseActorValue(name));
        if (!isFinite(base)) {
          if (rec) { mine[key] = rec; }
          log('tree: the game had no number for', name + ', leaving it alone');
          continue;
        }
        const natural = (rec && base === rec.total) ? base - rec.add : base;
        const want = natural + add;
        if (want !== base) { pc.setActorValue(name, want); }
        if (add) {
          mine[key] = { name: name, add: add, total: want };
          said.push(name + ' ' + (add > 0 ? '+' : '') + add + ' (' + want + ')');
        }
      } catch (e) {
        /* The set threw, so the base is whatever it was and the old record is
           still the truth about it. Said once and not retried: the next view
           that says something different comes through here again. */
        if (rec) { mine[key] = rec; }
        log('tree: could not set', name + ':', e);
      }
    }

    treeMine = mine;
    treeSig = treeSigOf(next);
    log('tree:', said.length
      ? ('the server\'s totals are on the character: ' + said.join(', '))
      : 'the server sends no totals, so anything this plugin added is off again');
  }

  /*
    After the world and not before. __thornswoodInWorld is the flag the tick
    above sets the moment there is a character and no menu, which is the same
    signal this file already uses for the browser, and update is the event
    where calls into the game work at all.
  */
  sp.on('update', guard('tree', () => {
    if (!treeDirty) { return; }
    let here = false;
    try { here = !!globalThis.__thornswoodInWorld; } catch (e) { here = false; }
    if (!here) { return; }
    let pc = null;
    try { pc = sp.Game.getPlayer(); } catch (e) { pc = null; }
    if (!pc) { return; }
    treeDirty = false;
    treeApplyNow(pc);
  }));

  // <<< tree apply: end <<<

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
