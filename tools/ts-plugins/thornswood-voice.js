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
    let when = Number(first);         // unix milliseconds from the launcher
    if (!isFinite(when) || when < 1e12) { when = Date.parse(first); }
    if (isFinite(when) && Math.abs(Date.now() - when) < 24 * 3600 * 1000) { return true; }
    try { skyrimPlatform.printConsole('[thornswood] the launcher\'s session note is stale, so this is another server\'s session. Plugin idle.'); } catch (e) { }
  } catch (e) {
    try { skyrimPlatform.printConsole('[thornswood] the launcher left no session note, so this is another server\'s session. Plugin idle.'); } catch (e2) { }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Thornswood proximity voice, game side.
//
// The page cannot work any of this out for itself. Loaded from file:// it has
// no host to read a server address out of, no way to know which character you
// are, and no keyboard, because the game's browser does not hold focus while
// you are playing. So everything it needs is pushed in from here:
//
//   who you are      from Data/Platform/Plugins/skymp5-client-settings.txt
//   where to call    the same file's server-ip, voice runs beside the server
//   push to talk     a real game key, read from Thornswood.ini, forwarded
//
// Push to talk being a game key rather than a browser key is the whole point.
// It is why there is no second window to alt-tab to and nothing to click.
// ---------------------------------------------------------------------------

const sp = skyrimPlatform;

const SETTINGS  = 'Data/Platform/Plugins/skymp5-client-settings.txt';
const INI       = 'Data/SKSE/Plugins/Thornswood.ini';
const LOG_FILE  = 'Data/Platform/thornswood-voice.log';
// The voice server's port. 7778 is the main build's; the dev build's
// launcher writes its own into Thornswood.ini at every Play, so the game
// talks to the same voice server the launcher does.
let VOICE_PORT = 7778;

/*
  Where the launcher writes the loopback port it is listening on for push to
  talk. Relative to the game folder, which is where this process runs, and the
  Profile folder is that folder's sibling.
*/
const PORT_FILE = 'voice-port.txt';

/*
  The other half of the conversation with the launcher.

  Push to talk reaches it over loopback today and that still works, so it is
  left alone. Nothing coming back the other way ever did. The page asking the
  launcher for its state is a fetch from a file:// origin into 127.0.0.1, which
  the browser is free to refuse, and when it refuses it does so silently: the
  promise rejects into an empty catch and the microphone indicator sits on
  LISTENING ONLY all session while voice itself is working.

  So the state comes through the file system instead, which is this plugin's
  strong suit rather than the page's. Reading voice-port.txt out of this exact
  folder is the one part of this that has never failed.

  voice-status.txt   written by the launcher   "<mic> <peers> <talking> <mode>"
  voice-ptt.txt      written by us             "<on> <mode>"
*/
const STATUS_FILE = 'voice-status.txt';
const PTT_FILE    = 'voice-ptt.txt';

/*
  Where those three files are. Data/Platform inside the game folder first,
  then ../Profile.

  ../Profile was the only place, and it is right when the game folder is
  Root\Game and nowhere else. On a collection install the game is the Steam
  copy, ../Profile from there does not exist, and this plugin never found the
  port or the status: the page ran its own voice, asked the browser for a
  microphone NirnLab's Chromium cannot grant, and sat on LISTENING ONLY while
  the launcher was connected with the microphone open. Push to talk went into
  a file nothing read. Data/Platform is the one folder both ends can find, and
  the launcher writes its two files there as well from 1.1.33.
*/
const CHANNEL_DIRS = ['Data/Platform/', '../Profile/'];

function readChannel(name) {
  for (const d of CHANNEL_DIRS) {
    try {
      const raw = fsm ? fsm.readFileSync(d + name, 'utf8') : '';
      if (String(raw).trim()) { return String(raw).trim(); }
    } catch (e) { }
  }
  return '';
}

function writeChannel(name, text) {
  let wrote = false;
  for (const d of CHANNEL_DIRS) {
    try { if (fsm) { fsm.writeFileSync(d + name, text); wrote = true; } } catch (e) { }
  }
  return wrote;
}

let fsm = null;
try { fsm = require('fs'); fsm.writeFileSync(LOG_FILE, ''); } catch (e) { fsm = null; }

function log() {
  const line = '[voice] ' + Array.prototype.slice.call(arguments).join(' ');
  try { sp.printConsole(line); } catch (e) { }
  if (fsm) { try { fsm.appendFileSync(LOG_FILE, line + '\n'); } catch (e) { fsm = null; } }
}

function guard(name, fn) {
  return function () {
    try { return fn.apply(null, arguments); }
    catch (e) { log(name, 'threw:', e && e.stack ? e.stack : e); return undefined; }
  };
}

// ------------------------------------------------------------- who and where --
let profileId = 0;
let host = '';

try {
  const raw = fsm ? fsm.readFileSync(SETTINGS, 'utf8') : '';
  const text = raw.charCodeAt(0) === 0xFEFF ? raw.slice(1) : raw;
  const doc = JSON.parse(text);
  profileId = Number(doc && doc.gameData && doc.gameData.profileId) || 0;
  host = String((doc && doc['server-ip']) || '');
} catch (e) {
  log('could not read the client settings:', e);
}

// ------------------------------------------------------------------- keys ----
// A scan code, the same numbering the launcher's Controls page writes. 47 is
// V, but the number is whatever it was rebound to.
//
// Push to talk and nothing else. There used to be a mute key as well, which
// was a control for shutting a microphone that is already shut: push to talk
// means the mic is closed unless V is held, so mute could only ever repeat
// what not pressing V already does.
let PTT_KEY = 47;

/* Steps whisper -> local -> yell -> whisper. B, which the emote wheel used to
 * sit on before it moved to G. */
let MODE_KEY = 48;

/*
 * Which microphone, by name.
 *
 * getUserMedia with no device asked for takes whatever the browser calls the
 * default, and the browser's default is not Windows' default. It picked the
 * Anker, which is a pair of speakers with an input on it, over the Fifine that
 * Windows is set to record from. There is no way to ask for "whatever Windows
 * would use", so the only honest fix is to name the one you want.
 *
 * Matched loosely and case insensitively against the device label, so "fifine"
 * finds "Microphone (FIFINE K669B)". Left empty means take the default and
 * hope, which is what it did before.
 */
let MIC_NAME = '';

/**
 * Whether to open the microphone at all.
 *
 * Granting the permission and opening the device are two different acts.
 * SkyrimPlatform now appends --enable-media-stream, so CEF will say yes, but
 * nothing happens until a page actually calls getUserMedia. This decides
 * whether it does.
 *
 * It was added as a control: with everything else identical, one run with a
 * live capture and one without, to find out whether the capture was what killed
 * the keyboard in character creation. It was. This has been sitting at 0 ever
 * since, which is why the overlay has said listening only for days.
 *
 * Back on now, with the capture held until the creation hall is behind you.
 * See HALL below. That is not a workaround dressed up as a feature: there is
 * nobody to talk to in the hall, it is a room you stand in alone for half a
 * minute, so the only thing the capture could do there is the one thing it was
 * proved to do.
 */
let MIC_ON = true;

try {
  const ini = fsm ? fsm.readFileSync(INI, 'utf8') : '';
  const grab = function (key, fallback) {
    const m = ini.match(new RegExp('^\\s*' + key + '\\s*=\\s*(\\d+)', 'm'));
    return m ? Number(m[1]) : fallback;
  };
  PTT_KEY = grab('PushToTalk', PTT_KEY);
  VOICE_PORT = grab('VoicePort', VOICE_PORT);
  MODE_KEY = grab('VoiceModeKey', MODE_KEY);
  MIC_ON = grab('Microphone', 1) !== 0;
  // Spaces and tabs only around the value, never \s: with the value left
  // empty, \s* ran over the line break and (.+?) took the next line of the
  // file, a comment, as the microphone's name. The shipped ini leaves the
  // value empty on purpose, so every launcher fills in its own machine's.
  const named = ini.match(/^[ \t]*MicrophoneName[ \t]*=[ \t]*(\S.*?)[ \t]*$/m);
  if (named) { MIC_NAME = named[1]; }
} catch (e) {
  log('could not read Thornswood.ini, using the default keys');
}

log('profile', profileId, 'server', host || '(none)', 'voice port', VOICE_PORT, 'ptt', PTT_KEY,
    'mode key', MODE_KEY, 'microphone', MIC_ON ? 'on' : 'off',
    'wanted device', MIC_NAME || '(default)');

// ------------------------------------------------------------ the page -------
function js(src) {
  var T = globalThis.Thornswood;
  if (T && T.js) return T.js(src);
  try { sp.browser.executeJavaScript(src); return true; }
  catch (e) { log('executeJavaScript failed:', e); return false; }
}

/** Game.getPlayer throws at the main menu rather than returning null. */
function myName() {
  try {
    const pc = sp.Game.getPlayer();
    const n = pc ? pc.getName() : '';
    return (typeof n === 'string' && n.trim()) ? n.trim() : '';
  } catch (e) {
    return '';
  }
}

/* The creation hall, the one place the microphone stays shut. Resolved through
 * getFormFromFile so it does not depend on a load order position. */
const HALL_LOCAL_ID = 0x19BAD4;
const HALL_PLUGIN = 'Skyrim Unbound.esp';
let hallId = null;

/**
 * True only when we are certain it is safe to open a capture device.
 *
 * The first version of this asked one question, are you standing in the hall,
 * and trusted the answer. That was wrong in the one direction that matters.
 * While the game is still loading there is a player, and its cell is not the
 * hall yet, so "not in the hall" came back for a character who was about to
 * spend the next minute in the race menu:
 *
 *     [voice] mic | not asking yet
 *     [voice] mic | asking          <- 1.2 seconds later, still in creation
 *     [front] chat key seen, but RaceSex Menu is open
 *
 * A live capture during creation is what takes the keyboard away, which is how
 * somebody loads in and cannot move or swing. So this asks for proof of the
 * opposite: a resolved hall, a player, a cell that is not the hall, no menu of
 * any kind, and the race menu specifically shut. Anything it cannot answer is
 * a no.
 *
 * Absence of evidence is the failure mode here, so it is treated as evidence
 * of absence on purpose. The cost of waiting is a few seconds of listening
 * only. The cost of guessing wrong is somebody stuck in their own character.
 */
function safeToOpenMic() {
  try {
    if (sp.Utility.isInMenuMode()) { return false; }
  } catch (e) { return false; }

  try {
    if (sp.Ui.isMenuOpen('RaceSex Menu')) { return false; }
    if (sp.Ui.isMenuOpen('Loading Menu')) { return false; }
    if (sp.Ui.isMenuOpen('Main Menu')) { return false; }
  } catch (e) { return false; }

  try {
    if (hallId === null) {
      const form = sp.Game.getFormFromFile(HALL_LOCAL_ID, HALL_PLUGIN);
      hallId = form ? form.getFormID() : 0;
    }
    const pc = sp.Game.getPlayer();
    if (!pc) { return false; }
    const cell = pc.getParentCell();
    // No cell is a character who is not really anywhere yet.
    if (!cell) { return false; }
    // hallId of 0 means Unbound is not loaded, so there is no creation room to
    // be stuck in and the other checks above are enough.
    if (hallId && cell.getFormID() === hallId) { return false; }
    return true;
  } catch (e) {
    return false;
  }
}

function configure(micWanted) {
  const o = {
    host: host,
    port: VOICE_PORT,
    profileId: profileId,
    name: myName(),
    pushToTalk: true,
    microphone: !!micWanted,
    micName: MIC_NAME
  };
  return js('try{window.thornswoodVoice&&window.thornswoodVoice.configure(' +
            JSON.stringify(o) + ');}catch(e){}');
}

let phase = 0;         // 0 waiting for the front, 1 configuring, 2 running
let at = 0;
let tries = 0;
let micOpened = false; // whether the page has been told it may open a capture
let clear = 0;         // consecutive checks that said it is safe to

sp.on('update', guard('tick', () => {
  const now = Date.now();

  // thornswood-front.js loads the page and pulls thornswood-voice.js into it.
  // All this waits for is that being done.
  if (phase === 0) {
    var T = globalThis.Thornswood;
    if (!T || !T.ready) return;
    if (!host) {
      log('no server address in the client settings, voice cannot connect');
      phase = 9;
      return;
    }
    phase = 1; at = now;
    return;
  }

  /*
   * Said more than once on purpose, but three times rather than twelve.
   *
   * The page fetches its own script, so there is a window where the front is up
   * and window.thornswoodVoice is not there yet, and a configure call landing
   * in that window is silently lost. Repeating covers that. Always with the
   * microphone off, whatever the ini says.
   *
   * Twelve of them, 1200 ms apart, was fourteen and a half seconds before the
   * watcher below was even allowed to start looking. The line under it said
   * there was no hurry. There was: that was most of the wait between loading in
   * and being able to talk, and none of it was buying anything. The page is
   * fetching a file off the same disk, and if one of these is still lost the
   * configure sent when the microphone opens carries the whole thing again.
   */
  if (phase === 1 && now - at > 1200) {
    tries++;
    at = now;
    configure(false);
    if (tries >= 12) { phase = 2; log('configured'); }
    return;
  }

  /*
   * The only place a capture is ever opened.
   *
   * Every number in this file is back to what it was, and none of them should
   * be touched again without a reason better than wanting voice sooner.
   *
   * Opening a capture device takes the foreground for a moment. Windows hands
   * back a foreground acquired DirectInput device when that happens, and the
   * hook now asks for it back on every read, so the lock is no longer
   * permanent. What decides whether it costs nothing or costs a minute is how
   * settled the foreground is when that moment lands, and early in a launch it
   * is not settled at all.
   *
   * These numbers were tuned down from here twice, to nine seconds and then to
   * eleven, and both brought the lock back: fifteen seconds the first time and
   * over a minute the second. They are the configuration that was reported
   * working and they stay that way until something measures what takes the
   * foreground.
   *
   * Eight looks two seconds apart.
   *
   * This was cut to one second on the reasoning that the old wait existed only
   * to mask a keyboard loss, and that the loss was really DirectInput never
   * being re-acquired. Half of that was right. The hook does re-acquire now and
   * the permanent version of the lock is gone. The other half was wrong: at one
   * second the keyboard went away for fifteen seconds again.
   *
   * So there are two separate things here and the fix for one is not the fix
   * for the other. Opening a capture device takes the foreground for a moment,
   * which is what loses the device, and the re-acquire gets it back as soon as
   * the foreground comes back. During the game's own startup the foreground
   * does not come back promptly, so the same moment costs fifteen seconds
   * instead of none.
   *
   * Waiting until the world has been quietly up for eight seconds puts that
   * moment somewhere the foreground is settled. It is not certainty, it is
   * distance from the noisiest part of a launch.
   *
   * The page's configure handles arriving twice. Its start() has long since run
   * by now, so the second call is only the microphone, and everything already
   * standing (the audio context, the shared socket, the peer list) is left
   * alone.
   */
  if (phase === 2 && MIC_ON && !micOpened && now - at > 2000) {
    at = now;
    if (!safeToOpenMic()) {
      // Back to nothing rather than counting down from where it got to. A run
      // of clear checks interrupted by a menu is not most of a run of clear
      // checks, it is the start of a new one.
      if (clear) { log('back in a menu, waiting again before opening the microphone'); }
      clear = 0;
      return;
    }
    clear++;

    /*
     * Two clear checks, about two seconds.
     *
     * This was eight checks at two seconds each, sixteen seconds of standing
     * in an inn before anybody could talk, and the reason given for it was
     * that opening a capture device "puts its stall" into the arrival. That
     * was true and the cause was somewhere else entirely.
     *
     * Opening the microphone takes the foreground for an instant. Windows
     * hands back a foreground acquired DirectInput device when that happens,
     * and SkyrimPlatform's hook never asked for it again, so the keyboard died
     * and stayed dead. Waiting sixteen seconds did not fix that. It only moved
     * it to a moment when somebody had stopped pressing keys long enough not
     * to notice for a while.
     *
     * The hook re acquires now, so the stall it was hiding from is gone, and
     * the wait goes back to what it is actually for: not opening a capture in
     * the middle of a load screen or a menu. Two seconds of being genuinely in
     * the world is enough to know that.
     */
    if (clear >= 8) {
      micOpened = true;
      configure(true);
      log('in the world and settled, opening the microphone');
    }
  }
}));

// There is no keyDown and no keyUp.
//
// SkyrimPlatform has one keyboard event, 'buttonEvent', carrying isDown and
// isUp on the same object. The two names this file used to listen for were
// never emitted by anything, so every registration succeeded and no key ever
// arrived: push to talk was dead from the first build, silently, which is the
// worst way for a thing to be broken. Check Data/Platform/Modules/skyrimPlatform.ts
// before adding another one; it declares every event there is.
/*
 * Said once each, the first time it happens.
 *
 * Push to talk and the mode key both did nothing, and from the outside that has
 * three possible causes that look identical: the key never reached this file,
 * it reached it and was turned away by a guard, or it got through and the page
 * did not act on it. Nothing in the log could tell them apart. Now it can.
 */
/*
  Handing push to talk to the launcher.

  The audio moved out of the game: the in-game browser has no permission
  prompt, an autoplay policy nobody in a game can satisfy, and a focus flag
  that takes the keyboard away when raised. The launcher has a real browser and
  none of those problems. What it does not have is a keyboard, because it is
  not the window anybody is looking at.

  So the one thing the game keeps is the key, and this carries it across. The
  port is read from disk rather than agreed in advance, because the launcher
  takes whichever loopback port was free.

  Sent repeatedly rather than once: the page may still be parsing when the
  launcher is already up, and the launcher may be started after the game. The
  page ignores a port it already has, so repeating costs nothing, and the first
  one that lands is what switches the page out of running its own voice.
*/
let launcherPort = 0;
let portCheckedAt = 0;

/*
  Our half: written the instant a key moves rather than on the next poll, so
  the only delay push to talk picks up is the launcher noticing, which it does
  every 100ms.
*/
let myMode = 'local';
let pttHeld = false;
const MODE_ORDER = ['whisper', 'local', 'yell'];
let lastPttWritten = '';

function writePtt(on) {
  const line = (on ? '1' : '0') + ' ' + myMode;
  if (line === lastPttWritten) { return; }
  lastPttWritten = line;
  writeChannel(PTT_FILE, line);
}

/*
  Their half. Pushed straight into the page, which is the same route the push
  to talk key already takes and the only one that has ever arrived.
*/
let lastStatusSeen = '';
let statusCheckedAt = 0;

function readStatusFile() {
  return readChannel(STATUS_FILE);
}

sp.on('update', guard('status', () => {
  const now = Date.now();
  if (now - statusCheckedAt < 400) { return; }
  statusCheckedAt = now;

  const line = readStatusFile();
  if (!line || line === lastStatusSeen) { return; }
  lastStatusSeen = line;

  const bits = line.split(' ');
  const mic     = bits[0] === '1';
  const peers   = Number(bits[1]) || 0;
  const talking = bits[2] === '1';
  const mode    = bits[3] || 'local';

  js('try{window.thornswoodVoice&&window.thornswoodVoice.setLauncherStatus(' +
     (mic ? 'true' : 'false') + ',' + peers + ',' +
     (talking ? 'true' : 'false') + ',"' + mode + '");}' +
     'catch(e){window.skyrimPlatform.sendMessage("thornswood-voice",' +
     '"launcher status threw | "+e);}');

  once('status-first', 'the launcher is reporting its own state, the indicator ' +
       'is drawing from that now');
}));

function readLauncherPort() {
  const n = Number(readChannel(PORT_FILE).replace(/[^0-9]/g, ''));
  return (n > 0 && n < 65536) ? n : 0;
}

sp.on('update', guard('launcher', () => {
  const now = Date.now();
  if (now - portCheckedAt < 3000) { return; }
  portCheckedAt = now;

  const p = readLauncherPort();
  if (!p) { return; }

  js('try{window.thornswoodVoice&&window.thornswoodVoice.setLauncherPort(' + p + ');}catch(e){}');

  if (p !== launcherPort) {
    launcherPort = p;
    log('the launcher has the microphone, push to talk goes to 127.0.0.1:' + p);
  }
}));

const said = {};
function once(what, line) {
  if (said[what]) { return; }
  said[what] = true;
  log(line);
}

sp.on('buttonEvent', guard('keys', (e) => {
  if (e.code === PTT_KEY || e.code === MODE_KEY) {
    once('arrived-' + e.code,
         'key ' + e.code + ' reached the plugin' +
         (e.code === PTT_KEY ? ' (push to talk)' : ' (voice mode)'));
  }

  if (phase < 1) {
    if (e.code === PTT_KEY || e.code === MODE_KEY) {
      once('early-' + e.code, 'key ' + e.code + ' arrived before voice was ready');
    }
    return;
  }

  // While the chat box holds the keyboard the browser has focus, DirectInput
  // is withheld from the game, and this handler is not called at all. Nothing
  // to guard against there. This guards the other order: the box was opened
  // and the flag is still up on the tick the key arrives.
  const T = globalThis.Thornswood;
  if (T && T.isTyping && T.isTyping()) {
    if (e.code === PTT_KEY || e.code === MODE_KEY) {
      once('typing-' + e.code, 'key ' + e.code + ' ignored, the chat box has the keyboard');
    }
    return;
  }

  // Whisper, local, yell. On the way down only: a key that cycled on press and
  // again on release would land back where it started.
  if (e.code === MODE_KEY) {
    if (e.isDown && !e.isUp) {
      // Written first. The page telling the launcher was the part that never
      // arrived, which is why every mode change since the audio moved has gone
      // nowhere and everybody stayed on local.
      const at = MODE_ORDER.indexOf(myMode);
      myMode = MODE_ORDER[(at + 1) % MODE_ORDER.length];
      lastPttWritten = '';
      writePtt(pttHeld);

      const ok = js('try{window.thornswoodVoice&&window.thornswoodVoice.setMode("' + myMode + '");}' +
                    'catch(e){window.skyrimPlatform.sendMessage("thornswood-voice",' +
                    '"mode key threw | "+e);}');
      log('voice mode is now ' + myMode + (ok ? '' : ', but telling the page failed'));
    }
    return;
  }

  if (e.code !== PTT_KEY) { return; }

  if (e.isDown && !e.isUp) {
    pttHeld = true;
    writePtt(true);
    const ok = js('try{window.thornswoodVoice&&window.thornswoodVoice.setTalking(true);}' +
                  'catch(e){window.skyrimPlatform.sendMessage("thornswood-voice",' +
                  '"talk on threw | "+e);}');
    once('talk-sent', 'push to talk sent to the page' + (ok ? '' : ', but the send failed'));
  } else if (e.isUp) {
    pttHeld = false;
    writePtt(false);
    js('try{window.thornswoodVoice&&window.thornswoodVoice.setTalking(false);}' +
       'catch(e){window.skyrimPlatform.sendMessage("thornswood-voice",' +
       '"talk off threw | "+e);}');
  }
}));

sp.on('browserMessage', guard('browserMessage', (event) => {
  const a = event.arguments;
  if (!a || a[0] !== 'thornswood-voice') return;
  log(String(a[1]));
}));

log('loaded. browser:', typeof sp.browser);

})();
