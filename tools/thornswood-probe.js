// ---------------------------------------------------------------------------
// Thornswood browser probe
//
// One question, asked properly: will the game's own browser give us a
// microphone? Everything about in-game voice depends on the answer, and no
// amount of reading CEF source settles it for THIS build with THIS backend.
//
// So: load a page in the game's browser, ask the browser about itself, and
// write the answers where they can be read without the game running.
//
// It also answers a second question we have been guessing at: whether the
// front (chat, names, the dice) loads at all. SkyrimPlatform's default UI url
// is the bare string 'file:///Data/Platform/UI/index.html', which CEF reads as
// the filesystem root: on this machine that is C:\Data\Platform\UI, which does
// not exist. So the front has never been loaded even when the files were
// there. This loads it from an absolute path built off the working directory,
// the same way the emote wheel already does.
//
// Delete this file when the answer is known. It does nothing for the game.
// ---------------------------------------------------------------------------

const sp = skyrimPlatform;

const LOG_FILE = 'Data/Platform/thornswood-probe.log';
const UI_PATH = 'Data/Platform/UI/index.html';

const UI_URL = (function () {
  try {
    var root = process.cwd().replace(/\\/g, '/').replace(/\/+$/, '');
    return encodeURI('file:///' + root + '/' + UI_PATH);
  } catch (e) {
    return 'file:///' + UI_PATH;
  }
})();

let logFs = null;
try {
  logFs = require('fs');
  logFs.writeFileSync(LOG_FILE, '');
} catch (e) {
  logFs = null;
}

function log() {
  const line = '[probe] ' + Array.prototype.slice.call(arguments).join(' ');
  try { sp.printConsole(line); } catch (e) { }
  if (logFs) {
    try { logFs.appendFileSync(LOG_FILE, line + '\n'); } catch (e) { logFs = null; }
  }
}

function guard(name, fn) {
  return function () {
    try { return fn.apply(null, arguments); }
    catch (e) { log(name, 'threw:', e && e.stack ? e.stack : e); return undefined; }
  };
}

log('url:', UI_URL);
try {
  log('file present:', require('fs').existsSync(UI_PATH) ? 'yes' : 'NO');
} catch (e) {
  log('file present: could not check:', e);
}

// The probe itself, as source text run inside the page. Written as one
// expression tree with no template literals, because it is handed to CEF as a
// string and the quoting only has to survive one trip.
const PROBE_JS = [
  '(function () {',
  '  function say(stage, detail) {',
  '    try { window.skyrimPlatform.sendMessage("thornswood-probe", stage + " | " + detail); }',
  '    catch (e) { }',
  '  }',
  '  try {',
  '    say("origin", location.href);',
  '    say("secure", String(window.isSecureContext));',
  '    say("mediaDevices", String(!!navigator.mediaDevices));',
  '    say("getUserMedia", String(!!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia)));',
  '    say("RTCPeerConnection", String(typeof window.RTCPeerConnection));',
  '    say("AudioContext", String(typeof (window.AudioContext || window.webkitAudioContext)));',
  '    say("root", document.getElementById("root") ? "present" : "MISSING");',
  '    say("reactMounted", (document.getElementById("root") && document.getElementById("root").children.length) ? "yes" : "no");',
  '    try {',
  '      var AC = window.AudioContext || window.webkitAudioContext;',
  '      if (AC) { var c = new AC(); say("audioState", c.state); }',
  '    } catch (e) { say("audioState", "threw: " + e); }',
  '    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {',
  '      navigator.mediaDevices.getUserMedia({ audio: true }).then(function (s) {',
  '        var t = s.getAudioTracks()[0];',
  '        say("mic", "GRANTED, track=" + (t ? t.label || "(no label)" : "none"));',
  '        try { s.getTracks().forEach(function (x) { x.stop(); }); } catch (e) { }',
  '      }).catch(function (err) {',
  '        say("mic", "DENIED " + (err && err.name ? err.name : "?") + ": " + (err && err.message ? err.message : err));',
  '      });',
  '    } else {',
  '      say("mic", "unavailable, no getUserMedia on this page");',
  '    }',
  '  } catch (e) {',
  '    say("probe", "threw: " + e);',
  '  }',
  '})();'
].join('\n');

sp.on('browserMessage', guard('browserMessage', (event) => {
  const a = event.arguments;
  if (!a || a[0] !== 'thornswood-probe') return;
  log(String(a[1]));
}));

// The page needs a moment to exist before it can be asked anything, and the
// browser needs the game to have finished starting before loadUrl sticks.
let started = false;
let firedAt = 0;
let asked = 0;

sp.on('update', guard('tick', () => {
  const now = Date.now();

  if (!started) {
    started = true;
    firedAt = now;
    try {
      sp.browser.setVisible(false);
      sp.browser.setFocused(false);
      sp.browser.loadUrl(UI_URL);
      log('asked the browser to load the front');
    } catch (e) {
      log('browser is not available:', e);
    }
    return;
  }

  // Ask three times over twelve seconds. The first may land before the page
  // has parsed; the later ones catch a slow React mount, and the answers are
  // labelled with their attempt so a change between them is visible.
  if (asked < 3 && now - firedAt > 4000 * (asked + 1)) {
    asked++;
    log('--- attempt', asked, '---');
    try {
      sp.browser.executeJavaScript(PROBE_JS);
    } catch (e) {
      log('executeJavaScript failed:', e);
    }
  }
}));

log('loaded. browser:', typeof sp.browser);
