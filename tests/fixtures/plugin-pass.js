// tests/fixtures/plugin-pass.js
//
// What Skyrim Platform does with a plugin, for a harness that runs one of
// game/plugins in a vm sandbox (issue #485).
//
// thornswood-front.js owns the whose-game check and publishes it as
// globalThis.Thornswood.whoseGame, only when it says ours. The other plugins
// run nothing at load: they ask that check on the first tick, which Skyrim
// Platform sends after it has run every plugin file (TickImpl in the fork's
// skyrim-platform SkyrimPlatform.cpp). So a harness that loads one of them
// alone has to do what the game does around it:
//
//   1. run front's own check, lifted out of thornswood-front.js, in the
//      sandbox, against whatever fake files the harness gives it, and publish
//      it on the sandbox's Thornswood object when it says ours, as front does;
//   2. run the plugin file;
//   3. send the first tick to whatever the plugin asked once('tick') for.
//
// The check is front's real code, never a stand-in, so a harness that gives
// the plugin another server's address or no session note still sees it idle.
//
//   const pass = require('./fixtures/plugin-pass');
//   pass.load(box, source, { filename: 'thornswood-voice.js' });
//
// box is the vm context's global object, already holding skyrimPlatform and
// require. Thornswood on it is used when there is one and made when not.
// Without opts.front, nothing is published: front did not load.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const FRONT = path.join(__dirname, '..', '..', 'game', 'plugins', 'thornswood-front.js');
const HEAD = 'function thornswoodGame() {';

/* front's thornswoodGame, braces balanced, or null. */
function frontCheck(src) {
  src = src || fs.readFileSync(FRONT, 'utf8');
  const a = src.indexOf(HEAD);
  if (a < 0) { return null; }
  let depth = 0;
  for (let j = src.indexOf('{', a); j < src.length; j++) {
    if (src[j] === '{') { depth++; }
    else if (src[j] === '}') { depth--; if (!depth) { return src.slice(a, j + 1); } }
  }
  return null;
}

/*
  Runs the load pass. opts.front: false leaves front out, as when it failed to
  load. opts.filename names the plugin for vm's stack traces. Returns what
  front's check said (or null without front) and how many once('tick')
  callbacks the plugin left.
*/
function load(box, source, opts) {
  opts = opts || {};
  const sp = box.skyrimPlatform;
  const once = [];
  // Wrap whatever once the harness gave, so its own tick store still sees it.
  const theirs = typeof sp.once === 'function' ? sp.once : null;
  sp.once = function (name, fn) {
    if (name === 'tick') { once.push(fn); return; }
    if (theirs) { return theirs.call(sp, name, fn); }
  };
  let said = null;
  if (opts.front !== false) {
    const fn = vm.runInContext('(function () {\n' + frontCheck() + '\nreturn thornswoodGame;\n})()', box);
    said = fn();
    if (said) {
      box.Thornswood = box.Thornswood || {};
      box.Thornswood.whoseGame = fn;
    }
  }
  vm.runInContext(source, box, opts.filename ? { filename: opts.filename } : undefined);
  const left = once.length;
  once.splice(0).forEach(function (fn) { fn(); });
  if (theirs) { sp.once = theirs; }
  return { ours: said, tickWaiters: left };
}

module.exports = { load: load, frontCheck: frontCheck, FRONT: FRONT };
