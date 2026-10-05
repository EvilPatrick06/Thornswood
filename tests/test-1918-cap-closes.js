// test-1918-cap-closes.js
//
// The front's two minute cap closes what it takes the keyboard from (#1918).
//
// The cap closes the window of a claim that has held the keyboard two
// minutes, by the name CAP_CLOSES gives it, then takes the claim back. For
// the emote wheel that name was thornswoodEmotes, and nothing defines
// window.thornswoodEmotes, so the claim went with the wheel still drawn and
// the emote plugin still holding it open: 1 to 8 played nothing, and the
// next G shut a wheel instead of opening one. The cap now closes the wheel
// through the emote plugin, which puts its close in T.capCloses.
//
//   A. Every name in CAP_CLOSES is a window global that a page the front
//      loads defines, with a close.
//   B. Every claim any plugin makes is closed by the cap one way or the
//      other: by a name in CAP_CLOSES, or by the plugin's own close in
//      T.capCloses. The chat has caps of its own and is not one of them.
//   C. The real cap, lifted out of thornswood-front.js, run over the real
//      emote plugin and page: two minutes after G opened the wheel, the cap
//      hides the wheel, takes the claim back, and the plugin's open follows,
//      so 1 plays the first quick slot and the next G opens the wheel again.
//
// FRONT=<file> or PLUGIN=<file> runs another copy, for instance the one
// before this fix.
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
function read(p) {
  return fs.readFileSync(path.isAbsolute(p) ? p : path.join(ROOT, p), 'utf8').split(CR).join('');
}
const front = read(process.env.FRONT || path.join('game', 'plugins', 'thornswood-front.js'));
const plugin = read(process.env.PLUGIN || path.join('game', 'plugins', 'thornswood-emotes.js'));
const page = read(path.join('game', 'ui', 'thornswood-emotes.js'));
const indexHtml = read(path.join('game', 'ui', 'index.html'));
const serverAddress = JSON.parse(read(path.join('scripts', 'vps', 'vps.json'))).address;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function attempt(what, fn) {
  try { fn(); } catch (e) { yes(what + ' ran without throwing (' + (e && e.stack || e) + ')', false); }
}

/* The object literal that starts at the first { at or after i, braces matched. */
function objectAt(src, i) {
  const a = src.indexOf('{', i);
  if (a < 0) { return null; }
  let depth = 0;
  for (let j = a; j < src.length; j++) {
    const c = src[j];
    if (c === '{') { depth++; }
    else if (c === '}') { depth--; if (depth === 0) { return src.slice(a, j + 1); } }
  }
  return null;
}

const capM = /const CAP_CLOSES = (\{[\s\S]*?\});/.exec(front);
const CAP_CLOSES = capM ? new Function('return ' + capM[1])() : null;
yes('the front\'s CAP_CLOSES is read (' + (CAP_CLOSES ? Object.keys(CAP_CLOSES).length : 0) + ' claims)',
    !!CAP_CLOSES && Object.keys(CAP_CLOSES).length >= 10);
const ovM = /const OVERLAYS = (\[[\s\S]*?\]);/.exec(front);
const OVERLAYS = ovM ? new Function('return ' + ovM[1])() : [];
const PAGES = OVERLAYS.concat((indexHtml.match(/src="(thornswood-[\w-]+\.js)"/g) || [])
  .map(function (s) { return s.slice(5, -1); }));

// ===================================================== A. names and pages
attempt('A', function () {
  Object.keys(CAP_CLOSES || {}).forEach(function (claim) {
    const name = CAP_CLOSES[claim];
    let where = '', obj = null;
    PAGES.forEach(function (file) {
      let src;
      try { src = read(path.join('game', 'ui', file)); } catch (e) { return; }
      // The last one in the file: the note at the top of a page writes the
      // contract out the same way, in shorthand.
      const rx = new RegExp('\\n\\s*window\\.' + name + ' = (\\{|(\\w+);)', 'g');
      let at = null, m;
      while ((m = rx.exec(src))) { at = m; }
      if (!at) { return; }
      where = file;
      if (at[1] === '{') { obj = objectAt(src, at.index); }
      else {
        const v = new RegExp('\\n\\s*var ' + at[2] + ' = \\{').exec(src);
        obj = v ? objectAt(src, v.index) : null;
      }
    });
    yes('A1 ' + claim + ': window.' + name + ' is defined by a page the front loads' + (where ? ' (' + where + ')' : ''), !!where);
    yes('A2 ' + claim + ': and it has a close', !!obj && /(^|[{,\s])close\s*:/.test(obj));
  });
});

// ========================================================= B. every claim
attempt('B', function () {
  const plugins = fs.readdirSync(path.join(ROOT, 'game', 'plugins')).filter(function (f) { return /\.js$/.test(f); });
  const claims = {}, own = {};
  plugins.forEach(function (f) {
    const src = f === 'thornswood-front.js' ? front : f === 'thornswood-emotes.js' ? plugin :
                read(path.join('game', 'plugins', f));
    let m;
    const rx = /claimFocus\('(\w+)', true\)/g;
    while ((m = rx.exec(src))) { (claims[m[1]] = claims[m[1]] || []).push(f); }
    const ro = /\(T\.capCloses = T\.capCloses \|\| \{\}\)\.(\w+) = function/g;
    while ((m = ro.exec(src))) { own[m[1]] = f; }
  });
  yes('B0 the claims are read (' + Object.keys(claims).join(', ') + ')', Object.keys(claims).length >= 10);
  Object.keys(claims).forEach(function (c) {
    if (c === 'chat') { return; }
    const by = own[c] ? 'its plugin\'s close (' + own[c] + ')' : (CAP_CLOSES && CAP_CLOSES[c] ? 'window.' + CAP_CLOSES[c] : '');
    yes('B1 the cap closes the ' + c + ' claim\'s window' + (by ? ', by ' + by : ''), !!by);
    yes('B2 and by one way only', !(own[c] && CAP_CLOSES && CAP_CLOSES[c]));
  });
  yes('B3 the wheel is closed through the emote plugin', own.wheel === 'thornswood-emotes.js');
  yes('B4 the cap calls a plugin\'s own close before the page\'s', /T\.capCloses && T\.capCloses\[who\]/.test(front));
});

// ================================================ C. the real cap, run
/*
  The page and the plugin, the way test-1852-wheel-keys.js wires them: the
  plugin's executeJavaScript runs in the page, and the page's sendMessage
  reaches the plugin.
*/
function world() {
  const w = { claims: {}, focus: false, played: [], sent: [], logged: [] };
  const byId = {};
  const d = {};
  function el(tag, id) {
    return {
      tagName: String(tag).toUpperCase(), id: id || '', className: '', style: {}, children: [],
      attrs: {}, textContent: '', value: '', innerHTML: '', parentNode: null,
      appendChild(c) { this.children.push(c); c.parentNode = this; return c; },
      removeChild(c) { const i = this.children.indexOf(c); if (i >= 0) { this.children.splice(i, 1); } return c; },
      get firstChild() { return this.children[0] || null; },
      setAttribute(k, v) { this.attrs[k] = String(v); },
      getAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k) ? this.attrs[k] : null; },
      addEventListener() { },
      querySelectorAll() { return []; },
      focus() { }, blur() { }
    };
  }
  d.head = el('head'); d.documentElement = el('html'); d.body = el('body');
  d.activeElement = d.body;
  d.createElement = function (t) { return el(t); };
  d.createElementNS = function (ns, t) { return el(t); };
  d.getElementById = function (id) { return byId[id] || (byId[id] = el('div', id)); };
  d.addEventListener = function () { };
  const pageBox = { window: { skyrimPlatform: { sendMessage(a, b) { w.sent.push([a, b]); } } }, document: d, console: { log() { } } };
  vm.createContext(pageBox);
  vm.runInContext(page, pageBox);
  const host = d.body.children.filter(function (c) { return c.id === 'thornswood-wheel'; })[0] || null;
  w.shown = function () { return !!host && String(host.className).indexOf('gone') === -1; };
  w.pageBox = pageBox;

  const handlers = {};
  const io = {
    readFileSync(file) {
      if (/Thornswood\.ini$/.test(file)) { return '[Emotes]\n'; }
      if (/skymp5-client-settings\.txt$/.test(file)) { return JSON.stringify({ 'server-ip': serverAddress }); }
      if (/thornswood-session\.txt$/.test(file)) { return String(Date.now()); }
      throw new Error('absent');
    },
    appendFileSync() { }, writeFileSync() { }
  };
  const T = {
    ready: true, isTyping: function () { return false; }, setTyping() { },
    claimFocus(who, on) {
      w.claims[who] = !!on;
      w.claimedAt[who] = on ? w.now : 0;
      w.focus = Object.keys(w.claims).some(function (k) { return w.claims[k]; });
    },
    js(src) { vm.runInContext(src, pageBox); return true; }
  };
  w.T = T;
  w.now = 1000000;
  w.claimedAt = {};
  const actor = { getFormID: () => 0x14, isWeaponDrawn: () => false, sheatheWeapon() { },
                  getParentCell: () => null, getItemCount: () => 1 };
  const sp = {
    on(name, fn) { (handlers[name] = handlers[name] || []).push(fn); },
    printConsole(l) { w.logged.push(String(l)); },
    Game: { getPlayer: () => actor, getFormFromFile: () => null },
    Utility: { isInMenuMode: () => false },
    browser: { isFocused: () => w.focus },
    TESModPlatform: { setWeaponDrawnMode() { } },
    hooks: { sendAnimationEvent: { add() { } } },
    Debug: { notification() { }, sendAnimationEvent(pc, ev) { w.played.push(ev); } }
  };
  const box = { skyrimPlatform: sp, Thornswood: T, require: () => io, Date: Date, JSON: JSON, Math: Math, Number: Number };
  box.globalThis = box;
  vm.createContext(box);
  vm.runInContext(plugin, box);
  w.emit = function (name, ev) { (handlers[name] || []).forEach(function (fn) { fn(ev); }); };
  w.update = function () {
    w.sent.splice(0).forEach(function (m) { w.emit('browserMessage', { arguments: [m[0], m[1]] }); });
    w.emit('update');
  };
  // A key the game hears: only while the browser does not hold the keyboard.
  w.press = function (code) {
    if (w.focus) { return; }
    w.emit('buttonEvent', { device: 0, code: code, isDown: true, isUp: false, isRepeating: false, isHeld: false, heldDuration: 0 });
    w.emit('buttonEvent', { device: 0, code: code, isDown: false, isUp: true, isRepeating: false, isHeld: false, heldDuration: 0 });
    w.update();
  };

  // The cap, from the front, run as the front's update runs it.
  const a = front.indexOf('    for (const who in claimedAt) {');
  const b = a < 0 ? -1 : front.indexOf('\n    }\n', a);
  w.capFound = a >= 0 && b > a;
  const cap = w.capFound ? new Function('claimedAt', 'claims', 'CAP_CLOSES', 'T', 'log', 'choiceUp', 'now',
    front.slice(a, b + 6)) : null;
  w.cap = function (at) {
    cap(w.claimedAt, w.claims, CAP_CLOSES, T, function (s) { w.logged.push(s); }, function () { return false; }, at);
  };
  return w;
}

const G = 34, ONE = 2;
attempt('C', function () {
  const w = world();
  yes('C0 the cap is lifted out of the front', w.capFound);
  w.update();
  w.press(G);
  yes('C1 G opens the wheel and the wheel takes the keyboard', w.shown() && w.claims.wheel && w.focus);
  w.cap(w.now + 60000);
  yes('C1 a minute on, the cap leaves it alone', w.shown() && w.claims.wheel);
  w.cap(w.now + 121000);
  w.update();
  yes('C2 two minutes on, the cap says so in the log', w.logged.some(function (s) { return /wheel claim has held the keyboard for two minutes/.test(s); }));
  yes('C2 and the wheel is hidden', !w.shown());
  yes('C2 and the claim is taken back', !w.claims.wheel && !w.focus);
  w.press(ONE);
  yes('C3 the plugin no longer has it open, so 1 plays the first quick slot',
      w.logged.some(function (s) { return /^\[emotes\] slot 1 /.test(s); }));
  w.press(G);
  yes('C4 and the next G opens the wheel again, not shuts one', w.shown() && w.claims.wheel);
});

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
