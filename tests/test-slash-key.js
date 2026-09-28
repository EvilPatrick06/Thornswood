// test-slash-key.js
//
// / opens the chat with a slash already in it, and the game's skill tree,
// which is also on /, stays shut.
//
// Patrick, 27 September: "can we also make / pull up the text chat and enter
// slash and not the vanilla skyrims skill tree thingg and only the chat".
//
// WHAT THIS RUNS. The real / block out of thornswood-front.js (STATS_MENU down
// to the key handler) over a pretend game that says which menus are up and
// records what was shut, in both orders the game can deliver the press and
// the tree opening. The key handler itself is read for its two lines. The
// chat page's focusInput is run in a stand-in page, because the slash has to
// be typed the way React hears it.
//
// Read only.
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);
function read(...bits) { return fs.readFileSync(path.join(ROOT, ...bits), 'utf8').split(CR).join(''); }
const front = read('game', 'plugins', 'thornswood-front.js');
const bridge = read('game', 'ui', 'thornswood-bridge.js');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const a = front.indexOf("  const STATS_MENU = 'StatsMenu';");
const b = front.indexOf("  sp.on('buttonEvent', guard('keys', (e) => {");
const block = a >= 0 && b > a ? front.slice(a, b) : null;
yes('the / block is in the plugin', block !== null);
yes('the plugin reads CommandKey, / by default',
    /const COMMAND_KEY = iniNumber\(ini, 'CommandKey', 53\);/.test(front));

// ------------------------------------------------------------ the handler
{
  const k = front.slice(b, front.indexOf('\n  }));\n', b));
  yes('the key handler sends / to the block, before the chat key',
      /if \(e\.code === COMMAND_KEY\) \{ commandKeyPressed\(e\); return; \}\s*\n\s*if \(e\.code !== CHAT_KEY\) return;/.test(k));
  yes('and every key going down ends a / press\'s claim on the next tree',
      /journalKeyDown\(e\);[\s\S]{0,120}statsPressAt = 0;/.test(k));
  const w = front.slice(front.indexOf('  function wantTyping(on, prefill) {'));
  yes('wantTyping hands what to type to the page\'s focusInput, both ways it asks',
      (w.slice(0, 3000).match(/focusInput\(' \+ fill \+ '\)/g) || []).length === 2);
}

// ------------------------------------------------------------ the block
function rig(opt) {
  opt = opt || {};
  const w = { now: 100000, menus: {}, shut: [], typed: [], said: [], handlers: {}, mapped: 53 };
  w.menus = Object.assign({}, opt.menus || {});
  const sp = {
    on: function (n, f) { (w.handlers[n] = w.handlers[n] || []).push(f); },
    Ui: { isMenuOpen: function (n) { return !!w.menus[n]; } },
    Input: { getMappedKey: function (name) { return name === 'Quick Stats' ? w.mapped : -1; } },
    TESModPlatform: { closeMenu: function (n) { w.shut.push(n); if (!opt.stuck) { w.menus[n] = false; } } }
  };
  const clock = { now: function () { return w.now; } };
  const claims = { chat: !!opt.typing };
  const body =
    "const KEYBOARD_MENUS = ['InventoryMenu', 'StatsMenu', 'TweenMenu'];\n" +
    'function busyMenuOpenNow() { for (const n of KEYBOARD_MENUS) { if (sp.Ui.isMenuOpen(n)) { return n; } } return ""; }\n' +
    'function wantTyping(on, prefill) { typed.push([on, prefill]); }\n' +
    block + '\nreturn { press: commandKeyPressed, statsPress: function () { return statsPressAt; } };';
  const api = new Function('sp', 'say', 'guard', 'claims', 'typed', 'Date', body)(
    sp, function (t) { w.said.push(t); }, function (n, f) { return f; }, claims, w.typed, clock);
  w.press = function (name) { api.press({ code: 53, userEventName: name === undefined ? 'Quick Stats' : name }); };
  w.opens = function (n) {
    w.menus[n] = true;
    (w.handlers.menuOpen || []).forEach(function (f) { f({ name: n }); });
  };
  w.tick = function (ms) { w.now += ms; (w.handlers.update || []).forEach(function (f) { f(); }); };
  w.api = api;
  return w;
}

if (block) {
  // S1: the press first, then the tree.
  {
    const w = rig();
    w.press();
    yes('S1 / opens the chat with a slash in it', w.typed.length === 1 && w.typed[0][0] === true && w.typed[0][1] === '/');
    w.now += 30;
    w.opens('StatsMenu');
    yes('S1 and the skill tree that opens after it is shut', w.shut.join() === 'StatsMenu');
    w.tick(500);
    yes('S1 and once it is gone nothing more is asked', w.shut.length === 1);
  }
  // S2: the tree first, then the press.
  {
    const w = rig();
    w.opens('StatsMenu');
    yes('S2 a tree opening with no / before it is left alone', w.shut.length === 0);
    w.now += 20;
    w.press();
    yes('S2 / heard a moment after its tree opened shuts that tree', w.shut.join() === 'StatsMenu');
    yes('S2 and opens the chat with a slash', w.typed.length === 1 && w.typed[0][1] === '/');
  }
  // S3: the tree was already up: this / is the game's, to close it.
  {
    const w = rig();
    w.opens('StatsMenu');
    w.now += 5000;
    w.press();
    yes('S3 / in a tree that was already open does not open the chat', w.typed.length === 0);
    yes('S3 and does not shut the tree either: the game closes it on /', w.shut.length === 0);
  }
  // S4: Quick Stats moved to another key. / still opens the chat; the tree is theirs.
  {
    const w = rig();
    w.mapped = 48;
    w.press('');
    w.now += 30;
    w.opens('StatsMenu');
    yes('S4 with Quick Stats moved off /, / still opens the chat', w.typed.length === 1);
    yes('S4 and the tree opened by their own key is left alone', w.shut.length === 0);
  }
  // S5 and S6: not while typing, not over another menu.
  {
    const w = rig({ typing: true });
    w.press();
    yes('S5 while the chat has the keyboard, / does nothing here', w.typed.length === 0 && w.shut.length === 0);
  }
  {
    const w = rig({ menus: { InventoryMenu: true } });
    w.press();
    w.now += 30;
    w.opens('StatsMenu');
    yes('S6 over the inventory, / neither opens the chat nor shuts anything', w.typed.length === 0 && w.shut.length === 0);
  }
  // S7: a tree that will not go.
  {
    const w = rig({ stuck: true });
    w.press();
    w.now += 30;
    w.opens('StatsMenu');
    w.tick(1200);
    yes('S7 a tree still up a second after the shut is asked once more', w.shut.length === 2);
    w.tick(1000);
    yes('S7 and after two seconds it is said in the log and left',
        w.shut.length === 2 && w.said.some(function (s) { return /still open/.test(s); }));
    w.tick(1000);
    yes('S7 and not asked again', w.shut.length === 2);
  }
  // S8: a press long before the tree does not count.
  {
    const w = rig();
    w.press();
    w.now += 1500;
    w.opens('StatsMenu');
    yes('S8 a tree opening well after the press is not taken for it', w.shut.length === 0);
  }
}

// ------------------------------------------------------------ the page
{
  const s = bridge.indexOf('  function focusInput(prefill) {');
  const e = bridge.indexOf('\n  }\n', s);
  const fn = s >= 0 && e > s ? bridge.slice(s, e + 4) : null;
  yes('the page\'s focusInput takes what to type', fn !== null);
  if (fn) {
    function page(text) {
      const el = { innerText: text, focused: false, focus: function () { this.focused = true; } };
      const doc = {
        inserted: [],
        execCommand: function (cmd, ui, v) { if (cmd === 'insertText') { this.inserted.push(v); el.innerText += v; } return true; }
      };
      const win = {};
      const run = new Function('window', 'document', 'input', 'tell', 'unfade', 'startBeat',
        'var openedAt = 0, lastKey = 0;\n' + fn + '\nreturn focusInput;')(
        win, doc, function () { return el; }, function () { }, function () { }, function () { });
      return { el: el, doc: doc, win: win, run: run };
    }
    const p1 = page('');
    p1.run('/');
    yes('an empty box gets the slash, typed with insertText so React hears it',
        p1.el.focused && p1.doc.inserted.join() === '/' && p1.el.innerText === '/');
    const p2 = page('half a line');
    p2.run('/');
    yes('a box that already has words in it is left as it is', p2.doc.inserted.length === 0);
    const p3 = page('');
    p3.run();
    yes('Enter, which asks for nothing, types nothing', p3.doc.inserted.length === 0 && p3.el.focused);
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
