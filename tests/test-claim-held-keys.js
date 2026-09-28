// test-claim-held-keys.js
//
// A panel that opens while a key is down takes the keyboard only once that
// key is up, so the game sees the key come up and does not hold it for ever.
//
// WHAT WAS WRONG. Issue 528. Djinn on dev, 24 September: after picking a
// character F and the mouse wheel stopped at a very close third person view
// and Tab did not open the Tween Menu. His platform log: the party window
// claimed focus at 14:59:41.108 while Shift and P were down for the P in his
// name, and from then on the game repeated two held keys every frame, 1800
// button events every five seconds at 180 frames a second, with no menu open
// and the controls on. While focus is up DInputHook.cpp in the fork reads the
// keyboard buffer and hands the game none of it, so a key up in that time is
// gone and the game keeps the key down.
//
// THE PRETEND GAME. Every frame the keyboard changes are read first. The game
// hears a change only while focus is down; SKSE's Input count, which
// applyFocus asks, hears every change. Then this plugin's update runs.
//
// Run against the text before the change (FRONT=<old file>), the Shift P and
// K checks fail: the game is left holding the keys.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const SRC = process.env.FRONT ||
            path.join(TOOLS_DIR, '..', 'game', 'plugins', 'thornswood-front.js');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function done() {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
}

function between(start, end) {
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b);
}

// The claims, the menu questions and applyFocus, as test-f6-focus.js takes them.
const arbiter = between('  const claims = {};', '  /*\n    WHEN EACH CLAIM WENT UP');
yes('the focus arbiter is in the plugin', arbiter !== null);
if (!arbiter) { done(); }

const SHIFT = 42;
const P = 25;
const K = 37;
const FRAME_MS = 6;       // 180 frames a second, as in Djinn's log

function rig() {
  const clock = { t: 1000000 };
  const game = {
    focused: false,
    menus: new Set(),
    fingers: new Set(),    // what is under the fingers: SKSE's count
    held: new Set()        // what the game believes is down
  };
  const said = [];
  const T = { ready: true };
  const sp = {
    browser: {
      isFocused: function () { return game.focused; },
      setFocused: function (v) { game.focused = !!v; }
    },
    Ui: { isMenuOpen: function (n) { return game.menus.has(n); } },
    Utility: { isInMenuMode: function () { return game.menus.size > 0 || game.focused; } },
    Input: {
      getNumKeysPressed: function () { return game.fingers.size; },
      isKeyPressed: function (k) { return game.fingers.has(k); }
    }
  };
  const say = function (t) { said.push(String(t)); };
  const DateFake = { now: function () { return clock.t; } };
  const fn = new Function('sp', 'say', 'Date', 'ESC', 'wantTyping', 'T',
    arbiter + '\nreturn { claims: claims, applyFocus: applyFocus };');
  const api = fn(sp, say, DateFake, 1, function () { }, T);

  const queued = [];
  const r = { clock: clock, game: game, said: said, api: api };
  r.frame = function () {
    while (queued.length) {
      const c = queued.shift();
      if (c.down) { game.fingers.add(c.code); } else { game.fingers.delete(c.code); }
      if (!game.focused) {
        if (c.down) { game.held.add(c.code); } else { game.held.delete(c.code); }
      }
    }
    api.applyFocus();
    clock.t += FRAME_MS;
  };
  r.frames = function (n) { for (let i = 0; i < n; i++) { r.frame(); } };
  r.down = function (code) { queued.push({ code: code, down: true }); };
  r.up = function (code) { queued.push({ code: code, down: false }); };
  return r;
}

// ------------------------------------------ Shift P, as in Djinn's session
{
  const r = rig();
  r.down(SHIFT);
  r.frames(10);
  r.down(P);
  r.frame();
  r.api.claims.party = true;     // P opened the party window and it said so
  r.frames(3);
  yes('Shift P: the party window does not take the keyboard while both keys are down',
      !r.game.focused);
  r.frames(12);
  r.up(P);
  r.frames(5);
  r.up(SHIFT);
  r.frames(2);
  yes('Shift P: it takes the keyboard once both are up', r.game.focused);
  yes('Shift P: and the game is not left holding Shift or P',
      !r.game.held.has(SHIFT) && !r.game.held.has(P));
  r.api.claims.party = false;
  r.frames(2);
  yes('Shift P: closing the window gives the keyboard back', !r.game.focused);
  yes('Shift P: and nothing waited long enough to be logged', r.said.length === 0);
}

// ----------------------------------------------------- K, as in Blade's
{
  const r = rig();
  r.down(K);
  r.frame();
  r.api.claims.skills = true;
  r.frames(15);
  r.up(K);
  r.frames(2);
  yes('K: the skills panel has the keyboard once K is up', r.game.focused);
  yes('K: and the game did not keep K down', !r.game.held.has(K));
}

// ------------------------------------------------- nothing held, no wait
{
  const r = rig();
  r.api.claims.journal = true;
  r.frame();
  yes('a claim with no key down takes the keyboard on the same frame', r.game.focused);
}

// ------------------------------------------------ a key held on and on
{
  const r = rig();
  r.down(K);
  r.frame();
  r.api.claims.skills = true;
  r.frames(Math.floor(900 / FRAME_MS));
  yes('a key held for most of a second still holds the panel back', !r.game.focused);
  r.frames(Math.ceil(300 / FRAME_MS));
  yes('a key held past the wait does not keep the panel from the keyboard for ever',
      r.game.focused);
  yes('and the log names the key that was still down',
      r.said.some(function (s) { return /held key/.test(s) && /\b37\b/.test(s); }));
  r.up(K);
  r.api.claims.skills = false;
  r.frames(2);
  // A second panel later, with a key down again, waits again from nothing.
  r.said.length = 0;
  r.down(P);
  r.frame();
  r.api.claims.party = true;
  r.frames(3);
  yes('the wait starts over for the next claim', !r.game.focused);
  r.up(P);
  r.frames(2);
  yes('and ends when that key comes up', r.game.focused && !r.game.held.has(P));
}

// ------------------------------------------- letting go is never held back
{
  const r = rig();
  r.api.claims.skills = true;
  r.frames(2);
  r.down(K);                      // K again, to close it
  r.frame();
  r.api.claims.skills = false;
  r.frames(1);
  yes('a claim that goes away gives the keyboard back even with a key down',
      !r.game.focused);
}

// ------------------------------------------------------------- the wiring
{
  const code = src.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/[^\n]*/g, ' ');
  yes('applyFocus holds a claim back until the keys are up',
      /if \(want && claimed && !keysUpForClaim\(\)\) \{ return; \}/.test(code));
  yes('the wait is a second or two, not minutes',
      /const CLAIM_WAIT_MS = (\d+);/.test(code) &&
      +/const CLAIM_WAIT_MS = (\d+);/.exec(code)[1] >= 250 &&
      +/const CLAIM_WAIT_MS = (\d+);/.exec(code)[1] <= 2000);
}

done();
