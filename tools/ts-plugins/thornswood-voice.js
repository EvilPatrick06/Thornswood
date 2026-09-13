(function () {
'use strict';

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
const VOICE_PORT = 7778;

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

/**
 * Whether to open the microphone at all.
 *
 * Granting the permission and opening the device are two different acts.
 * SkyrimPlatform now appends --enable-media-stream, so CEF will say yes, but
 * nothing happens until a page actually calls getUserMedia. This decides
 * whether it does.
 *
 * It exists because that is the only way to tell, in one run, whether a live
 * capture is what kills the keyboard in character creation. Flip the line, play,
 * compare. Without it the test means swapping a 15 MB DLL each time.
 */
let MIC_ON = true;

try {
  const ini = fsm ? fsm.readFileSync(INI, 'utf8') : '';
  const grab = function (key, fallback) {
    const m = ini.match(new RegExp('^\\s*' + key + '\\s*=\\s*(\\d+)', 'm'));
    return m ? Number(m[1]) : fallback;
  };
  PTT_KEY = grab('PushToTalk', PTT_KEY);
  MIC_ON = grab('Microphone', 1) !== 0;
} catch (e) {
  log('could not read Thornswood.ini, using the default keys');
}

log('profile', profileId, 'server', host || '(none)', 'ptt', PTT_KEY,
    'microphone', MIC_ON ? 'on' : 'off');

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

function configure() {
  const o = {
    host: host,
    port: VOICE_PORT,
    profileId: profileId,
    name: myName(),
    pushToTalk: true,
    microphone: MIC_ON
  };
  return js('try{window.thornswoodVoice&&window.thornswoodVoice.configure(' +
            JSON.stringify(o) + ');}catch(e){}');
}

let phase = 0;         // 0 waiting for the front, 1 configuring, 2 running
let at = 0;
let tries = 0;

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

  // Said more than once on purpose. The page fetches its own script, so there
  // is a window where the front is up and window.thornswoodVoice is not there
  // yet, and a single configure call landing in that window is silently lost.
  if (phase === 1 && now - at > 1200) {
    tries++;
    at = now;
    configure();
    if (tries >= 12) { phase = 2; log('configured'); }
    return;
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
sp.on('buttonEvent', guard('keys', (e) => {
  if (phase < 1) return;

  // While the chat box holds the keyboard the browser has focus, DirectInput
  // is withheld from the game, and this handler is not called at all. Nothing
  // to guard against there. This guards the other order: the box was opened
  // and the flag is still up on the tick the key arrives.
  const T = globalThis.Thornswood;
  if (T && T.isTyping && T.isTyping()) return;

  if (e.code !== PTT_KEY) { return; }

  if (e.isDown && !e.isUp) {
    js('try{window.thornswoodVoice&&window.thornswoodVoice.setTalking(true);}catch(e){}');
  } else if (e.isUp) {
    js('try{window.thornswoodVoice&&window.thornswoodVoice.setTalking(false);}catch(e){}');
  }
}));

sp.on('browserMessage', guard('browserMessage', (event) => {
  const a = event.arguments;
  if (!a || a[0] !== 'thornswood-voice') return;
  log(String(a[1]));
}));

log('loaded. browser:', typeof sp.browser);

})();
