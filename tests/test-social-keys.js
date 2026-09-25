// test-social-keys.js
//
// G, H, L, P and J work in the open world and stay out of the game's menus.
//
// Djinn on dev, 24 September: "The party menu actually opens when hitting
// shift P during character creation while naming your character." The five
// social keys had no guard in the plugin's key handler, unlike K and Enter,
// so a letter typed into the character creation name box, or pressed over
// the inventory or the map, opened one of our panels on top of the game's
// menu.
//
// WHAT THIS RUNS. The real text of the key handler and of KEYBOARD_MENUS,
// lifted out of thornswood-front.js, over a pretend game that says which
// menus are up. The handler's other neighbours (the J block's two hooks, the
// mold key, the verbs, the page) are stand-ins that only record what they
// were asked to do.
//
// Run it against the code before the change with FRONT=<that file>: the
// menu cases fail there, because nothing stopped the keys.
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

function between(start, end) {
  const a = src.indexOf(start);
  if (a < 0) { return null; }
  const b = src.indexOf(end, a + start.length);
  return b < 0 ? null : src.slice(a, b);
}

const KEYS_OPEN = "  sp.on('buttonEvent', guard('keys', (e) => {";
const SHUT = '\n  }));\n';
const ka = src.indexOf(KEYS_OPEN);
const kb = ka < 0 ? -1 : src.indexOf(SHUT, ka);
const keys = (ka >= 0 && kb >= 0) ? src.slice(ka, kb + SHUT.length) : null;
const menus = between('  const KEYBOARD_MENUS = [', '\n  ];');

yes('the key handler is in the plugin', keys !== null);
yes('the list of menus that take the keyboard is in the plugin', menus !== null);
yes('the character creation screen is on that list', !!menus && menus.indexOf("'RaceSex Menu'") >= 0);
yes('and the plugin names the game\'s journal the way this does',
    src.indexOf("const JOURNAL_MENU = 'Journal Menu';") >= 0);

const G = 34, H = 35, L = 38, P = 25, J = 36, K = 37;

function rig(opts) {
  opts = opts || {};
  const w = { open: {}, js: [], verbs: [], logs: [], threw: [], handlers: {} };
  (opts.menus || []).forEach(function (m) { w.open[m] = true; });
  const claims = Object.assign({}, opts.claims || {});
  const sp = {
    on: function (ev, fn) { (w.handlers[ev] = w.handlers[ev] || []).push(fn); },
    Ui: { isMenuOpen: function (n) { return !!w.open[n]; } }
  };
  const T = {
    ready: true,
    js: function (s) { w.js.push(s); return true; },
    hasFocus: function (who) { return !!claims[who]; }
  };
  const guard = function (name, fn) {
    return function () {
      try { return fn.apply(null, arguments); }
      catch (err) { w.threw.push(name + ': ' + err); return undefined; }
    };
  };
  const prelude =
    'let keysSeen = 0, stuckKeys = 0, stuckMoveKeys = 0, sawAnyKey = true;\n' +
    // between() keeps its start marker, so this is the declaration itself.
    menus + '\n  ];\n' +
    "const JOURNAL_MENU = 'Journal Menu';\n" +
    'const ESC = 1, CHAT_KEY = 28, SKILLS_KEY = 37, PARTY_KEY = 25, JOURNAL_KEY = 36,\n' +
    '      FRIEND_KEY = 34, TRADE_KEY = 35, MUTE_KEY = 38, MOLD_KEY = 22;\n' +
    'function rememberKey() { }\n' +
    'function wantTyping() { }\n' +
    'function journalKeyDown() { }\n' +
    'function journalKeyPressed() { }\n' +
    'function moldPress() { return false; }\n' +
    'function busyMenuOpen() { for (const n of KEYBOARD_MENUS) { if (sp.Ui.isMenuOpen(n)) { return n; } } return ""; }\n' +
    'function lookVerb(v) { verbs.push(v); }\n';
  new Function('sp', 'T', 'claims', 'say', 'guard', 'verbs', prelude + keys)(
    sp, T, claims, function (t) { w.logs.push(String(t)); }, guard, w.verbs);
  w.press = function (code) {
    (w.handlers.buttonEvent || []).forEach(function (f) { f({ code: code, isDown: true, isUp: false }); });
  };
  w.opened = function (panel) {
    return w.js.filter(function (s) { return s.indexOf('thornswood' + panel + '.toggle') >= 0; }).length;
  };
  return w;
}

if (keys !== null && menus !== null) {
  // THE BUG. Typing a name at character creation.
  {
    const w = rig({ menus: ['RaceSex Menu'] });
    w.press(P);
    yes('S1 THE BUG: P in the character creation name box does not open the party panel', w.opened('Party') === 0);
    w.press(J);
    yes('S1 nor does J open the journal', w.opened('Journal') === 0);
    w.press(G); w.press(H); w.press(L);
    yes('S1 and G, H and L ask nothing of the server', w.verbs.length === 0);
    yes('S1 the log says which menu held them', w.logs.some(function (l) { return /RaceSex Menu is open/.test(l); }));
    yes('S1 nothing threw', w.threw.length === 0);
  }
  // Over the inventory, the map and the rest of the game's own menus.
  {
    ['InventoryMenu', 'MapMenu', 'ContainerMenu', 'Dialogue Menu', 'Console'].forEach(function (m) {
      const w = rig({ menus: [m] });
      w.press(P); w.press(J); w.press(G); w.press(H); w.press(L);
      yes('S2 over ' + m + ' none of the five opens a panel or asks the server',
          w.opened('Party') === 0 && w.opened('Journal') === 0 && w.verbs.length === 0 && w.threw.length === 0);
    });
  }
  // The open world, which is where they are for.
  {
    const w = rig();
    w.press(P);
    yes('S3 P in the world opens the party panel', w.opened('Party') === 1);
    w.press(J);
    yes('S3 J in the world opens the journal', w.opened('Journal') === 1);
    w.press(G); w.press(H); w.press(L);
    yes('S3 G, H and L ask for friend, trade and mute', w.verbs.join(',') === 'friend,trade,mute');
    yes('S3 nothing threw', w.threw.length === 0);
  }
  // J and the game's own book. J is the game's journal key too, and the book
  // may be up before the plugin sees the press.
  {
    const w = rig({ menus: ['Journal Menu'] });
    w.press(J);
    yes('S4 J still opens our journal when the game\'s book beat it up', w.opened('Journal') === 1);
    w.press(P);
    yes('S4 but the book counts for P: the System page is a menu', w.opened('Party') === 0);
  }
  // A panel of ours that holds the keyboard can be closed by its own key.
  {
    const w = rig({ menus: ['MessageBoxMenu'], claims: { party: true, journal: true } });
    w.press(P);
    yes('S5 P closes the party panel it opened, whatever else is up', w.opened('Party') === 1);
    w.press(J);
    yes('S5 and J closes the journal', w.opened('Journal') === 1);
    w.press(G);
    yes('S5 but G still waits for the world', w.verbs.length === 0);
  }
  // The chat box has the keyboard: every letter is typing.
  {
    const w = rig({ claims: { chat: true } });
    w.press(P); w.press(J); w.press(G);
    yes('S6 while chat has the keyboard none of them fires', w.opened('Party') === 0 && w.opened('Journal') === 0 && w.verbs.length === 0);
  }
  // K keeps the guard it always had.
  {
    const w = rig({ menus: ['RaceSex Menu'] });
    w.press(K);
    yes('S7 K over character creation still does nothing', w.opened('Skills') === 0);
    const v = rig();
    v.press(K);
    yes('S7 and K in the world still opens the skills panel', v.opened('Skills') === 1);
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
