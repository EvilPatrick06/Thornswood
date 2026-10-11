// test-voice-mute.js
//
// A muted person is silent in the page that actually plays the audio.
//
// ENTRY 151 ON THE TO DO LIST, "Voice has no mute and no block". The mute was
// built in #133: L while looking at somebody, or /mute <name>, keeps a list on
// the character, and the server hands it to window.thornswoodVoice.setMuted in
// the game's own page, whose place() sets that person's gain to 0.
//
// A reviewer measured on 23 September that the list stopped there. Once the
// launcher reports in, the game's page goes into relay mode and drops every
// connection it had, and the audio plays in the launcher's voice page,
// launcher/voice-host.html, hosted by Voice.cs in WebView2. That page's
// place() set the gain from levelFor(...) and never looked at a mute: profile
// 123 muted in the game, in the same cell at zero distance, was played at
// gain 1. A muted person was still heard.
//
// The list now goes the whole way: the game's page sends it to the voice
// plugin, the plugin writes voice-muted.txt where the launcher already reads
// push to talk, Voice.cs hands the line to its page as a 'muted' message, and
// that page's place() silences them before distance is considered.
//
// This runs the REAL pages and the REAL plugin in a sandbox with a fake
// browser, a fake file system and a fake audio graph, rather than reading
// their text, because the defect was a thing that read like working code.
// Voice.cs is C# and is checked by text here and by the launcher compile.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const pluginPass = require('./fixtures/plugin-pass'); // front's whose-game check and the first tick, as the game does (#485)
// The box's address from the one place that holds it (#459), which is what the
// plugin's own list is kept equal to by Set-Vps.ps1.
const OUR_ADDRESS = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'scripts', 'vps', 'vps.json'), 'utf8')).address;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const CR = String.fromCharCode(13);
function read(rel) {
  return fs.readFileSync(path.join(REPO_DIR, rel), 'utf8').split(CR).join('');
}

/* A gain node that records what it was set to, whether ramped or assigned. */
function gainNode() {
  return {
    gain: { value: 1, setTargetAtTime: function (v) { this.value = v; } },
    connect: function (x) { return x; }
  };
}
function pannerNode() {
  return {
    positionX: { value: 0 }, positionY: { value: 0 }, positionZ: { value: 0 },
    connect: function (x) { return x; }
  };
}

// ------------------------------------------ the launcher's voice page, loaded
/*
  One fresh copy of voice-host.html's script, with a fake WebView2 bridge, a
  fake socket to the voice service and a fake audio graph. Returns the handles
  a test needs: tell() is the launcher posting a message, serve() is the voice
  service sending one, gains lists every gain node the page made, in order.
*/
function hostPage() {
  const html = read('launcher/voice-host.html');
  const m = /<script>([\s\S]*)<\/script>/.exec(html);
  if (!m) { throw new Error('voice-host.html has no script'); }

  const gains = [];
  const sockets = [];
  let onMessage = null;

  function FakeSocket(url) {
    this.url = url; this.readyState = 1; this.sent = [];
    sockets.push(this);
  }
  FakeSocket.prototype.send = function (s) { this.sent.push(s); };
  FakeSocket.prototype.close = function () { };

  function FakePc() { this.signalingState = 'stable'; }
  FakePc.prototype.addTrack = function () { };
  FakePc.prototype.addTransceiver = function () { };
  FakePc.prototype.close = function () { };
  FakePc.prototype.setLocalDescription = function () { return Promise.resolve(); };
  FakePc.prototype.setRemoteDescription = function () { return Promise.resolve(); };
  FakePc.prototype.addIceCandidate = function () { return Promise.resolve(); };

  function FakeAudio() {
    this.currentTime = 0; this.state = 'running'; this.destination = {};
  }
  FakeAudio.prototype.createGain = function () { const g = gainNode(); gains.push(g); return g; };
  FakeAudio.prototype.createPanner = function () { return pannerNode(); };

  const win = {
    chrome: { webview: {
      addEventListener: function (kind, fn) { if (kind === 'message') { onMessage = fn; } },
      postMessage: function () { }
    } },
    AudioContext: FakeAudio
  };
  const sandbox = {
    window: win,
    document: { getElementById: function () { return { textContent: '' }; } },
    navigator: { mediaDevices: { getUserMedia: function () { return new Promise(function () { }); } } },
    WebSocket: FakeSocket,
    RTCPeerConnection: FakePc,
    fetch: function () { return Promise.reject(new Error('no network here')); },
    setTimeout: function () { return 0; }, clearTimeout: function () { },
    setInterval: function () { return 0; }, clearInterval: function () { },
    console: console, Promise: Promise, Map: Map, Math: Math, Number: Number, String: String,
    JSON: JSON, Date: Date, Object: Object, Array: Array, isFinite: isFinite
  };
  vm.createContext(sandbox);
  vm.runInContext(m[1], sandbox);

  function tell(obj) { onMessage({ data: JSON.stringify(obj) }); }
  function serve(obj) {
    const ws = sockets[sockets.length - 1];
    ws.onmessage({ data: JSON.stringify(obj) });
  }
  return { tell: tell, serve: serve, gains: gains, sockets: sockets,
           listening: function () { return !!onMessage; } };
}

/* Me as profile 1, in cell c, at the origin, facing north. */
const ME = 1;
function here(extra) {
  const who = {};
  who[ME] = { pos: [0, 0, 0], angleZ: 0, cell: 'c' };
  for (const k in extra) { who[k] = extra[k]; }
  return who;
}
const BESIDE = { pos: [0, 0, 0], angleZ: 0, cell: 'c' };

/* A page configured as profile 1 and joined, with one other person, 123. */
function joined(others) {
  const p = hostPage();
  p.tell({ t: 'config', host: 'voice.test', port: '7778', profileId: ME, token: 't', base: 'https://voice.test/voice' });
  const ws = p.sockets[p.sockets.length - 1];
  ws.onopen();
  p.serve({ t: 'welcome', peer: 1 });
  p.serve({ t: 'peers', peers: [{ peer: 1, profileId: ME, name: 'Me' }].concat(others) });
  return p;
}

// --------------------------------------- the page that plays the audio
{
  const p = joined([{ peer: 2, profileId: 123, name: 'Sera', mode: 'local' }]);
  yes('the launcher\'s voice page listens for the launcher', p.listening());
  yes('and made a gain node for the person beside you', p.gains.length === 1);
  const g = p.gains[0] && p.gains[0].gain;

  p.serve({ t: 'pos', who: here({ 123: BESIDE }) });
  yes('before any mute, somebody in your cell at zero distance is heard',
      g && g.value > 0);

  /*
    THE CHECK THE REVIEWER'S MEASUREMENT FAILED. Profile 123, muted, in the
    same cell at zero distance: this page used to leave them at gain 1.
  */
  p.tell({ t: 'muted', list: '123' });
  yes('muted, the same person at zero distance is silent', g && g.value === 0);
  p.serve({ t: 'pos', who: here({ 123: BESIDE }) });
  yes('and stays silent as positions keep arriving', g && g.value === 0);

  p.tell({ t: 'muted', list: '' });
  yes('an empty list unmutes them, and they are heard again', g && g.value > 0);

  // Only the listed person. Somebody else muted is nothing to do with 123.
  p.tell({ t: 'muted', list: '456' });
  yes('muting somebody else leaves them heard', g && g.value > 0);

  // Anything that is not a profile id is dropped rather than trusted.
  p.tell({ t: 'muted', list: '123abc -123 1.5 "); x' });
  yes('a line that names nobody properly mutes nobody', g && g.value > 0);
  p.tell({ t: 'muted', list: '  456   123 ' });
  yes('extra spaces around the ids do not matter', g && g.value === 0);
}

// ------------------------------------ before anybody's position has arrived
{
  const p = joined([{ peer: 2, profileId: 123, name: 'Sera', mode: 'local' }]);
  const g = p.gains[0] && p.gains[0].gain;
  // Positions for them but not for me: the page has nowhere to measure from.
  p.serve({ t: 'pos', who: { 123: BESIDE } });
  p.tell({ t: 'muted', list: '123' });
  yes('a mute does not wait for your own position to arrive', g && g.value === 0);
}

// --------------------------------------- somebody already muted connects
{
  const p = hostPage();
  p.tell({ t: 'config', host: 'voice.test', port: '7778', profileId: ME, token: 't', base: 'https://voice.test/voice' });
  p.sockets[0].onopen();
  p.tell({ t: 'muted', list: '123' });
  p.serve({ t: 'welcome', peer: 1 });
  p.serve({ t: 'peers', peers: [{ peer: 2, profileId: 123, name: 'Sera', mode: 'yell' }] });
  const g = p.gains[0] && p.gains[0].gain;
  yes('a connection to somebody already muted starts silent, before any position',
      g && g.value === 0);
}

// ------------------------------------------------ the game's own page
/*
  Loaded whole, with a line added before its last close so the harness can
  reach the connections and the positions it keeps inside its closure. The
  file on disk is not touched.
*/
function gamePage() {
  let src = read('game/ui/thornswood-voice.js');
  const end = src.lastIndexOf('})();');
  const hook = '  window.__t = { conns: conns, setWho: function (w) { lastWho = w; }, ' +
               'cfg: cfg, place: place, setCtx: function (c) { ctx = c; } };\n';
  src = src.slice(0, end) + hook + src.slice(end);
  const sent = [];
  const el = function () {
    return { style: {}, appendChild: function () { }, setAttribute: function () { } };
  };
  const win = { skyrimPlatform: { sendMessage: function () { sent.push([].slice.call(arguments)); } } };
  const sandbox = {
    window: win,
    document: { getElementById: function () { return null; }, createElement: el,
                body: { appendChild: function () { } }, head: { appendChild: function () { } },
                querySelector: function () { return null; } },
    navigator: {}, location: { href: 'file:///x' },
    setInterval: function () { return 0; }, clearInterval: function () { },
    setTimeout: function () { return 0; }, clearTimeout: function () { },
    console: { log: function () { } },
    fetch: function () { return Promise.reject(new Error('no')); },
    Promise: Promise, Map: Map, Math: Math, Number: Number, String: String, JSON: JSON,
    Date: Date, Object: Object, Array: Array, isFinite: isFinite
  };
  vm.createContext(sandbox);
  vm.runInContext(src, sandbox);
  return { V: win.thornswoodVoice, t: win.__t, sent: sent };
}

function mutedSent(sent) {
  const m = sent.filter(function (a) { return a[0] === 'thornswood-voice-muted'; });
  return m.length ? m[m.length - 1] : null;
}

{
  const g = gamePage();
  yes('the game\'s page loads', !!(g.V && g.t));

  // The shape the server sends: profile id -> the name, or true.
  g.V.setMuted({ 123: 'Sera', 456: true });
  const last = mutedSent(g.sent);
  yes('the server\'s list is handed on for the launcher',
      !!last && last[1].split(' ').sort().join(' ') === '123 456');

  g.V.setMuted({});
  yes('and so is an empty one, so an unmute reaches the launcher too',
      !!mutedSent(g.sent) && mutedSent(g.sent)[1] === '');

  /*
    THE ENTRY'S doneWhen, as written: setMuted(123, true), then the placement
    loop with profile 123 in the same cell at zero distance leaves the gain at
    0. The reviewer measured this call doing nothing, because setMuted took
    only a whole list and a number is not one.
  */
  g.t.cfg.profileId = ME;
  g.t.setCtx({ currentTime: 0 });
  const rec = { profileId: 123, gain: gainNode(), panner: pannerNode(), mode: 'local', dist: 0 };
  g.t.conns.set(9, rec);
  g.t.setWho(here({ 123: BESIDE }));
  g.V.setMuted(123, true);
  g.t.place();
  yes('setMuted(123, true) mutes profile 123', g.V.isMuted(123));
  yes('and the loop leaves their gain at 0 in your cell at zero distance',
      rec.gain.gain.value === 0);
  yes('and the launcher is told', !!mutedSent(g.sent) && mutedSent(g.sent)[1] === '123');

  g.V.setMuted(123, false);
  g.t.place();
  yes('setMuted(123, false) unmutes them', !g.V.isMuted(123) && rec.gain.gain.value > 0);
  yes('and the launcher is told that as well',
      !!mutedSent(g.sent) && mutedSent(g.sent)[1] === '');

  // The server's whole list replaces whatever was there.
  g.V.setMuted(123, true);
  g.V.setMuted({ 456: 'Thora' });
  yes('a list from the server replaces a single mute', !g.V.isMuted(123) && g.V.isMuted(456));
}

// ----------------------------------------------------------- the plugin
/*
  The real plugin, with a fake Skyrim Platform and a fake file system. It
  runs only once front's whose-game check says ours (#485), which
  fixtures/plugin-pass.js runs for real, so the fake client settings point
  at our server and the launcher's session note is fresh.
*/
function plugin() {
  const files = {};
  files['Data/Platform/Plugins/skymp5-client-settings.txt'] =
    JSON.stringify({ 'server-ip': OUR_ADDRESS, gameData: { profileId: ME } });
  files['Data/Platform/thornswood-session.txt'] = String(Date.now());
  const fakeFs = {
    readFileSync: function (p) {
      if (!Object.prototype.hasOwnProperty.call(files, p)) { throw new Error('ENOENT ' + p); }
      return files[p];
    },
    writeFileSync: function (p, text) { files[p] = String(text); },
    appendFileSync: function (p, text) { files[p] = (files[p] || '') + String(text); }
  };
  const handlers = {};
  const sp = {
    on: function (name, fn) { (handlers[name] = handlers[name] || []).push(fn); },
    printConsole: function () { },
    browser: { executeJavaScript: function () { } }
  };
  const sandbox = {
    skyrimPlatform: sp,
    require: function (name) { if (name === 'fs') { return fakeFs; } throw new Error(name); },
    console: console, Date: Date, JSON: JSON, Number: Number, String: String,
    Math: Math, Array: Array, Object: Object, RegExp: RegExp, isFinite: isFinite
  };
  vm.createContext(sandbox);
  pluginPass.load(sandbox, read('game/plugins/thornswood-voice.js'), { filename: 'thornswood-voice.js' });
  function page() {
    const args = [].slice.call(arguments);
    (handlers.browserMessage || []).forEach(function (fn) { fn({ arguments: args }); });
  }
  return { files: files, page: page };
}

{
  const pl = plugin();
  const GAME = 'Data/Platform/voice-muted.txt';
  const PROFILE = '../Profile/voice-muted.txt';

  pl.page('thornswood-voice-muted', '123 456');
  yes('the plugin writes the list where the launcher reads push to talk',
      pl.files[GAME] === '123 456' && pl.files[PROFILE] === '123 456');

  pl.page('thornswood-voice-muted', '');
  yes('and writes an empty list over it on an unmute', pl.files[GAME] === '');

  pl.page('thornswood-voice-muted', '12;del 3"\n');
  yes('only digits and single spaces reach the file', pl.files[GAME] === '12 3');

  pl.page('thornswood-voice', 'mode | yell');
  yes('its ordinary log lines are not taken for a mute list', pl.files[GAME] === '12 3');

  /*
    A list left behind by another character is replaced by this session's
    first one, even when that one is empty.
  */
  const fresh = plugin();
  fresh.files[GAME] = '999';
  fresh.page('thornswood-voice-muted', '');
  yes('the first list of a session is always written, even an empty one',
      fresh.files[GAME] === '');
}

// ------------------------------------------------------ the launcher side
{
  const cs = read('launcher/app/Voice.cs');
  yes('Voice.cs reads voice-muted.txt from the channel folders',
      /Path\.Combine\(d, "voice-muted\.txt"\)/.test(cs) && /foreach \(string d in dirs\)/.test(cs));
  yes('and hands the line to its page as a muted message',
      cs.indexOf('Post("{\\"t\\":\\"muted\\",\\"list\\":\\"" + JsonEscape(now) + "\\"}");') >= 0);
  yes('on every pass of the file channel, ahead of push to talk\'s continue',
      /PassMuted\(dirs\);[\s\S]*?string\[\] bits = now\.Split/.test(cs));
  yes('and again whenever the page loads, which starts it with nobody muted',
      /static void Configure\(Action<string> log\)\s*\{\s*\/\/[^\n]*\n\s*mutedSeen = null;/.test(cs));

  const rules = read('scripts/release/Ship-Rules.ps1');
  const machine = /\$ShipMachineFiles = @\(([\s\S]*?)\n\)/.exec(rules);
  yes('and one person\'s mute list never rides in a pack',
      !!machine && machine[1].indexOf("'Data\\Platform\\voice-muted.txt'") >= 0);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
