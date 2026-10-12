// test-1633-help-panel.js
//
// The help in the game is a panel on its own key, and nothing tells people
// to type a command (#1633).
//
// Patrick, 4 October: "no more commands for things [people] do, only for dev
// and staff commands; everything else takes buttons and GUI". /help was a
// menu and six topics typed into the chat, each written as commands. His
// answer on #1633: the suggested one, a help panel with its own key on the
// launcher's Controls page, and a Help button on the K, P and J panels. And
// later the same day: /stuck, /helpme and /report stay commands (#1682), and
// so do the ways of saying a line, /me, /do, /w, /s, /y and /ooc, and /roll
// (#1639). Those are what the help names, and nothing else.
//
// What is held here, each half run where it can be:
//
//   A. THE KEY. HelpKey, F7 (scan code 65): the plugin's default, the
//      shipped Thornswood.ini and the Controls row agree, and nothing else of
//      ours, the mods' on the Controls page, the client's, RaceMenu's or
//      Skyrim's answers to it, the way test-mold-key.js checks U.
//   B. THE PLUGIN. The page is one of the overlays, the cap can close it,
//      the key opens it only with the keyboard free, and it is handed every
//      key name it mentions, as bound.
//   C. THE PAGE, run in a stand-in document: six topics, Escape and its key
//      close it, a rebind is what it says, and every slash word it names is
//      one that stays.
//   D. HELP ON K, P AND J: each opens the help and puts itself down; K's is
//      not there while creating.
//   E. THE SERVER. The list named to everybody is exactly the commands that
//      stay; /help and a word nobody has say where the panel is; /where
//      answers dev and testers only.
//   F. THE PAGES THAT SAY SO: the launcher's Help, the Controls row for /,
//      and docs/systems/commands.md row by row.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);
function read(...bits) { return fs.readFileSync(path.join(REPO_DIR, ...bits), 'utf8').split(CR).join(''); }

const gm = process.env.GM ? fs.readFileSync(process.env.GM, 'utf8').split(CR).join('') : read('game', 'gamemode.js');
const front = read('game', 'plugins', 'thornswood-front.js');
const page = read('game', 'ui', 'thornswood-help.js');
const party = read('game', 'ui', 'thornswood-party.js');
const journal = read('game', 'ui', 'thornswood-journal.js');
const skills = read('game', 'ui', 'thornswood-skills.js');
const ini = read('launcher', 'Thornswood.ini');
const keysCs = read('launcher', 'app', 'Keys.cs');
const helpCs = read('launcher', 'app', 'Help.cs');
const commandsMd = read('docs', 'systems', 'commands.md');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function attempt(what, fn) {
  try { fn(); } catch (e) { yes(what + ' ran without throwing (' + e.message + ')', false); }
}

/* One function by its whole first line, only if that line is there once. */
function liftFrom(src, first, indent) {
  const from = '\n' + indent + first;
  const a = src.indexOf(from);
  if (a < 0 || src.indexOf(from, a + 1) >= 0) { return null; }
  const end = '\n' + indent + '}\n';
  const b = src.indexOf(end, a + 1);
  return b < 0 ? null : src.slice(a + 1, b + end.length);
}
function between(src, a, b) {
  const i = src.indexOf(a);
  const j = i < 0 ? -1 : src.indexOf(b, i + a.length);
  return (i >= 0 && j >= 0) ? src.slice(i, j) : null;
}
function arrayOf(name) {
  const m = new RegExp('^const ' + name + ' = (\\[[\\s\\S]*?\\]);$', 'm').exec(gm);
  try { return m ? new Function('return ' + m[1])() : null; } catch (e) { return null; }
}

// The commands that stay, as Patrick decided them on 4 October, and /needs,
// the needs bars as text, on 11 October (#2267).
const STAY = ['/stuck', '/helpme', '/report', '/me', '/do', '/w', '/s', '/y', '/ooc', '/roll', '/needs'];
const PLAYER_WORDS = arrayOf('PLAYER_WORDS') || [];
const WORDS = arrayOf('WORDS') || [];

// =================================================================== A. the key
const F7 = 65;
attempt('A', function () {
  const defM = /const HELP_KEY = iniNumber\(ini, 'HelpKey', (\d+)\);/.exec(front);
  yes('A1 the plugin reads HelpKey out of Thornswood.ini, F7 (scan code 65) by default',
      !!defM && Number(defM[1]) === F7);
  yes('A1 the shipped Thornswood.ini carries HelpKey = 65', /^HelpKey = 65$/m.test(ini));
  const row = /Dx\("help", "ThornsWood", "Help",\s*"([^"]*)",\s*ThornIni, "HelpKey", (\d+)\)\);/.exec(keysCs);
  yes('A2 the launcher\'s Controls page has a Help row on HelpKey, 65', !!row && Number(row[2]) === F7);
  yes('A2 and it says what the key opens, and that Help on K, P and J does too',
      !!row && /help panel/.test(row[1]) && /Help on the K, P and J panels/.test(row[1]));

  const taken = {};
  function take(code, who) { (taken[code] = taken[code] || []).push(who); }
  let m;
  const rxFront = /iniNumber\(ini, '(\w+)', (\d+)\)/g;
  while ((m = rxFront.exec(front)) !== null) {
    if (m[1] !== 'HelpKey' && m[1] !== 'VoicePort') { take(Number(m[2]), 'front ' + m[1]); }
  }
  const emotes = read('game', 'plugins', 'thornswood-emotes.js');
  const rxEm = /key\('(\w+)', (\d+)\)/g;
  while ((m = rxEm.exec(emotes)) !== null) { take(Number(m[2]), 'emotes ' + m[1]); }
  const voice = read('game', 'plugins', 'thornswood-voice.js');
  const rxVo = /^let (\w+_KEY) = (\d+);/gm;
  while ((m = rxVo.exec(voice)) !== null) { take(Number(m[2]), 'voice ' + m[1]); }
  const mark = read('game', 'plugins', 'thornswood-mark.js');
  const rxMk = /^let (\w+Key) = (\d+);/gm;
  while ((m = rxMk.exec(mark)) !== null) { take(Number(m[2]), 'mark ' + m[1]); }
  const rxIni = /^\s*(\w+)\s*=\s*(\d+)\s*$/gm;
  while ((m = rxIni.exec(ini)) !== null) {
    if (['HelpKey', 'VoicePort', 'Microphone'].indexOf(m[1]) === -1) { take(Number(m[2]), 'ini ' + m[1]); }
  }
  // Every row on the Controls page, ours and the mods' (SkyUI's favourite
  // groups are F1 to F4 there).
  const rxCs = /Dxd?\("(\w+)",[\s\S]*?, "(\w+)", (?:"\w+", )?(-?\d+)\)\);/g;
  let rows = 0;
  while ((m = rxCs.exec(keysCs)) !== null) { rows++; if (m[2] !== 'HelpKey') { take(Number(m[3]), 'Controls ' + m[2]); } }
  if (/string\.IsNullOrEmpty\(menu\) \? "F4"/.test(keysCs)) { take(62, 'Controls menu'); }
  // skymp5-client, compiled in: F1 names, F2 the overlay, F6 focus. Skyrim's
  // controlmap.txt: F5, F9, F12, the console, Tab, Escape and the letters
  // and numbers it uses. RaceMenu: F5, F9, Tab, Enter, Shift, Alt, Space.
  // Measured on 24 September; see test-creation-close.js.
  [59, 60, 64].forEach(function (c) { take(c, 'skymp5-client'); });
  [63, 67, 88, 1, 15, 41, 17, 30, 31, 32, 18, 19, 16, 44, 33, 20, 50, 23, 46, 45,
   36, 25, 24, 38, 57, 42, 56, 29, 58, 2, 3, 4, 5, 6, 7, 8, 9, 10].forEach(function (c) { take(c, 'Skyrim'); });
  [63, 67, 15, 28, 42, 56, 57].forEach(function (c) { take(c, 'RaceMenu'); });
  yes('A3 the other keys were found to compare against (' + Object.keys(taken).length + ' codes, ' +
      rows + ' Controls rows)', Object.keys(taken).length > 30 && rows >= 30);
  yes('A3 and nothing else of ours, the mods\', the client\'s, RaceMenu\'s or Skyrim\'s answers to F7' +
      (taken[F7] ? ' (' + taken[F7].join(', ') + ')' : ''), !taken[F7]);

  const kn = liftFrom(front, 'function keyName(code) {', '  ');
  const keyName = kn ? new Function(kn + '\nreturn keyName;')() : null;
  yes('A4 the plugin calls 65 F7, 28 Enter and 53 /, so the help names them',
      !!keyName && keyName(65) === 'F7' && keyName(28) === 'Enter' && keyName(53) === '/' && keyName(25) === 'P');
  yes('A4 and the server names the same F7 when it says where the help is',
      /'Help is a panel: F7 opens it, unless you moved it on the launcher\\'s ' \+/.test(gm));
});

// ================================================================ B. the plugin
attempt('B', function () {
  yes('B1 the help page is one of the overlays the plugin fetches',
      /const OVERLAYS = \[[\s\S]*?'thornswood-help\.js'[\s\S]*?\];/.test(front));
  yes('B1 and the cap can close it by name', /help: 'thornswoodHelp'/.test(between(front, 'const CAP_CLOSES = {', '};') || ''));
  yes('B2 the help key goes to helpKeyPressed', /if \(e\.code === HELP_KEY\) \{ helpKeyPressed\(\); return; \}/.test(front));
  yes('B2 the page\'s opened and closed move the help claim, and ready hands it the keys',
      /if \(what === 'help:opened'\) \{ T\.claimFocus\('help', true\); return; \}/.test(front) &&
      /if \(what === 'help:closed'\) \{ T\.claimFocus\('help', false\); return; \}/.test(front) &&
      /if \(what === 'help:ready'\) \{ log\('the help panel is in'\); helpToPage\(\); return; \}/.test(front));

  const pieces = ['function iniNumber(text, key, fallback) {', 'function keyName(code) {',
                  'function helpKeys() {', 'function helpToPage() {', 'function helpKeyPressed() {']
    .map(function (f) { return liftFrom(front, f, '  '); });
  yes('B3 the pieces of the help key are in the plugin', pieces.every(Boolean));
  if (!pieces.every(Boolean)) { return; }
  function rig(iniText) {
    const w = { js: [], said: [], claims: {}, busy: '' };
    const consts =
      'const ini = ' + JSON.stringify(iniText || '') + ';\n' +
      'const CHAT_KEY = iniNumber(ini, "ChatKey", 28), COMMAND_KEY = iniNumber(ini, "CommandKey", 53),' +
      ' SKILLS_KEY = iniNumber(ini, "SkillsKey", 37), JOURNAL_KEY = iniNumber(ini, "JournalKey", 36);\n' +
      'const HELP_KEY = iniNumber(ini, "HelpKey", 65), TALK_KEY = iniNumber(ini, "PushToTalk", 47),' +
      ' VOICE_MODE_KEY = iniNumber(ini, "VoiceModeKey", 48), WHEEL_KEY = iniNumber(ini, "WheelKey", 34);\n' +
      'const HELP_NAME = keyName(HELP_KEY), PARTY_NAME = keyName(iniNumber(ini, "PartyKey", 25)),' +
      ' FRIEND_NAME = keyName(21), TRADE_NAME = keyName(35), MUTE_NAME = keyName(38), MOLD_NAME = keyName(22),' +
      ' LOCK_NAME = keyName(45), MANEUVER_NAME = keyName(10);\n' +
      'function deliverName() { return "E"; }\n';
    const api = new Function('T', 'claims', 'say', 'busyMenuOpen',
      pieces.join('\n') + consts + 'return { press: helpKeyPressed, keys: helpKeys };')(
      { js: function (s) { w.js.push(s); }, hasFocus: function (who) { return !!w.claims[who]; } }, w.claims,
      function (t) { w.said.push(String(t)); }, function () { return w.busy; });
    w.api = api;
    return w;
  }
  {
    const w = rig(read('launcher', 'Thornswood.ini'));
    w.api.press();
    const sent = w.js.join('\n');
    const kj = /setKeys\((\{[^)]*\})\)/.exec(sent);
    let k = null;
    try { k = kj ? JSON.parse(kj[1]) : null; } catch (e) { k = null; }
    yes('B4 the key hands the page every key name it mentions, then opens it',
        w.js.length === 2 && !!k && /thornswoodHelp\.open\(\)/.test(w.js[1]));
    yes('B4 as a fresh install has them: F7, Enter, /, K, P, J, Y, H, L, U, X, 9, V, B, G and E',
        !!k && k.help === 'F7' && k.chat === 'Enter' && k.command === '/' && k.skills === 'K' &&
        k.party === 'P' && k.journal === 'J' && k.friend === 'Y' && k.trade === 'H' && k.mute === 'L' &&
        k.mold === 'U' && k.lock === 'X' && k.maneuver === '9' && k.talk === 'V' && k.voiceMode === 'B' &&
        k.wheel === 'G' && k.activate === 'E');
  }
  {
    const w = rig('HelpKey = 67\nSkillsKey = 16\n');
    w.api.press();
    const k = w.api.keys();
    yes('B5 a rebind in Thornswood.ini is the name the page is given (F9, Q)', k.help === 'F9' && k.skills === 'Q');
  }
  {
    const w = rig('');
    w.claims.chat = true;
    w.api.press();
    yes('B6 not while the chat has the keyboard', w.js.length === 0);
    w.claims.chat = false;
    w.busy = 'InventoryMenu';
    w.api.press();
    yes('B6 nor over one of the game\'s own menus, and the log says which',
        w.js.length === 0 && w.said.some(function (s) { return /help key seen, but InventoryMenu is open/.test(s); }));
    w.busy = '';
    w.claims.help = true;
    w.api.press();
    yes('B7 with the help up and the key reaching the plugin, it closes the help',
        w.js.length === 1 && /thornswoodHelp\.close\(\)/.test(w.js[0]));
  }
});

// ------------------------------------------------------ a page to run it in
/*
  The stand-in document test-party-trade-theme.js uses: elements made from
  the markup the page writes, found again by id or by tag and attribute.
*/
function unesc(s) {
  return String(s).replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&amp;/g, '&');
}
function makeEl(tag) {
  const e = {
    tagName: String(tag).toLowerCase(), attrs: {}, kids: [], children: [], html: '', style: {},
    id: '', className: '', textContent: '', value: '', onclick: null,
    appendChild(c) { this.children.push(c); return c; },
    getAttribute(n) { return Object.prototype.hasOwnProperty.call(this.attrs, n) ? this.attrs[n] : null; },
    focus() { },
    querySelectorAll(sel) {
      const tests = sel.split(',').map(function (s) { return matcher(s.trim()); });
      const out = [];
      (function walk(list) {
        list.forEach(function (k) {
          if (tests.some(function (t) { return t(k); })) { out.push(k); }
          walk(k.kids);
        });
      })(this.kids.concat(this.children));
      return out;
    },
    querySelector(sel) { return this.querySelectorAll(sel)[0] || null; }
  };
  Object.defineProperty(e, 'innerHTML', {
    get() { return this.html; },
    set(h) { this.html = h; this.kids = parse(h); }
  });
  return e;
}
function matcher(sel) {
  const m = /^([a-z0-9]*)(?:#([\w-]+))?(?:\[([\w-]+)\])?$/i.exec(sel);
  if (!m) { throw new Error('the stand-in page cannot read the selector ' + sel); }
  return function (el) {
    if (m[1] && el.tagName !== m[1].toLowerCase()) { return false; }
    if (m[2] && el.attrs.id !== m[2]) { return false; }
    if (m[3] && !Object.prototype.hasOwnProperty.call(el.attrs, m[3])) { return false; }
    return true;
  };
}
function parse(html) {
  const out = [];
  const tag = /<([a-z0-9]+)((?:\s+[a-z-]+(?:="[^"]*")?)*)\s*\/?>/gi;
  let m;
  while ((m = tag.exec(html))) {
    const el = makeEl(m[1]);
    const attr = /([a-z-]+)(?:="([^"]*)")?/gi;
    let a;
    while ((a = attr.exec(m[2]))) { el.attrs[a[1]] = a[2] == null ? '' : unesc(a[2]); }
    el.id = el.attrs.id || '';
    el.className = el.attrs['class'] || '';
    const shut = html.indexOf('</' + m[1] + '>', tag.lastIndex);
    if ((el.tagName === 'button' || el.tagName === 'p') && shut > 0) { el.textContent = unesc(html.slice(tag.lastIndex, shut)); }
    out.push(el);
  }
  return out;
}
function load(src, initial) {
  const pg = { told: [], sent: [], keys: {} };
  const doc = {
    head: makeEl('head'), body: makeEl('body'), activeElement: null, createElement: makeEl,
    addEventListener(type, fn) { pg.keys[type] = fn; }
  };
  const win = {
    skyrimPlatform: { sendMessage(to, what) { pg.told.push(to + ' ' + what); } },
    thornswoodNet: { say(line) { pg.sent.push(line); return true; } },
    innerWidth: 1920, innerHeight: 1080,
    addEventListener() { }
  };
  Object.assign(win, initial || {});
  new Function('window', 'document', src)(win, doc);
  pg.win = win;
  pg.doc = doc;
  pg.root = doc.body.children[0];
  return pg;
}
function key(pg, k) { pg.keys.keydown({ key: k, preventDefault() { } }); }

// =================================================================== C. the page
let allText = '';
attempt('C', function () {
  const h = load(page);
  const help = h.win.thornswoodHelp;
  yes('C1 the page loads and says it is ready', !!help && h.told.indexOf('thornswood-front help:ready') !== -1);
  const root = h.root;
  yes('C1 and is shut until something opens it', !!root && !help.isOpen() && root.className === '');
  help.open();
  yes('C2 opening shows it and tells the plugin, which takes the keyboard for it',
      root.className === 'on' && help.isOpen() && h.told.indexOf('thornswood-front help:opened') !== -1);
  const nav = root.querySelector('#ts-help-nav').querySelectorAll('button[data-topic]');
  const titles = nav.map(function (b) { return b.textContent; });
  yes('C2 six topics, the ones /help had: ' + titles.join(', '),
      titles.join('|') === 'Talking|People|Living|Work|Land|Getting help');
  function body() { return root.querySelector('#ts-help-body').querySelectorAll('p').map(function (p) { return p.textContent; }).join(' '); }
  yes('C2 it opens on Talking, with the keys somebody looks for first above it',
      /^K is your profession and skills, P your friends and party, J your journals/.test(body()) &&
      /Enter opens the chat box/.test(body()) && /The server rolls it, so nobody can make a number up\./.test(body()));
  const texts = {};
  nav.forEach(function (b) { b.onclick.call(b); texts[b.getAttribute('data-topic')] = body(); });
  yes('C3 a topic\'s button shows that topic',
      /Office page on K/.test(texts.land) && /\/stuck/.test(texts.help) && /maneuvers open on 9/.test(texts.work));
  allText = Object.keys(texts).map(function (t) { return texts[t]; }).join(' ');
  yes('C3 and the one shown is marked', root.querySelector('#ts-help-nav').html.indexOf('data-topic="help" class="go"') !== -1);

  const named = (allText.match(/(^|[\s(])\/[a-z]+\b/g) || []).map(function (w) { return w.trim().replace(/^\(/, ''); })
    .filter(function (w, i, all) { return all.indexOf(w) === i; });
  const other = named.filter(function (w) { return STAY.indexOf(w) === -1; });
  yes('C4 every command the help names is one that stays (' + named.join(', ') + ')' +
      (other.length ? ' (not: ' + other.join(', ') + ')' : ''), named.length > 0 && other.length === 0);
  const unnamed = STAY.filter(function (w) { return named.indexOf(w) === -1; });
  yes('C4 and it names every one of them' + (unnamed.length ? ' (not: ' + unnamed.join(', ') + ')' : ''),
      unnamed.length === 0);
  yes('C4 nobody is told to type /help', !/\/help\b(?!me)/.test(allText));
  yes('C5 the words: no em dash, and never the word the house rules forbid',
      allText.indexOf(String.fromCharCode(0x2014)) === -1 && !/\bplayers?\b/i.test(page));

  key(h, 'Escape');
  yes('C6 Escape closes it and tells the plugin', !help.isOpen() && root.className === '' &&
      h.told.indexOf('thornswood-front help:closed') !== -1);
  help.open('land');
  yes('C6 open(topic) opens on that topic', /At a door you just opened/.test(body()));
  key(h, 'k');
  yes('C6 another key leaves it up', help.isOpen());
  key(h, 'F7');
  yes('C6 and its own key closes it', !help.isOpen());

  help.setKeys({ help: 'F9', skills: 'Q', lock: 'Z', nonsense: 'x' });
  help.open('land');
  yes('C7 a rebind is what it says: Q for K and Z for X',
      /Office page on Q\./.test(body()) && /a line names Z:/.test(body()) && !/ on K\b/.test(body()));
  yes('C7 and the foot names the help key as bound',
      root.querySelector('#ts-help-foot').textContent === 'Escape or F9 closes this.');
  key(h, 'F7');
  yes('C7 F7 is no longer it', help.isOpen());
  key(h, 'F9');
  yes('C7 F9 is', !help.isOpen());
  help.open();
  const close = root.querySelector('#ts-help-close');
  close.onclick.call(close);
  yes('C8 Close closes it', !help.isOpen());
  yes('C8 and it sends the server nothing at all', h.sent.length === 0);

  // The look is the P panel's, value for value where both have the rule.
  const style = h.doc.head.children[0].textContent;
  const p = load(party);
  const pstyle = p.doc.head.children[0].textContent;
  function rule(css, sel) {
    const at = css.indexOf(sel + '{');
    return at < 0 ? '' : css.slice(at + sel.length, css.indexOf('}', at)).replace(/\s+/g, '');
  }
  yes('C9 its buttons, its gold button and its foot are the P panel\'s, which are the K panel\'s',
      ['button', 'button.go', '.foot'].every(function (s) {
        const mine = rule(style, '#ts-help ' + s);
        return !!mine && mine === rule(pstyle, '#ts-party ' + s);
      }));
  yes('C9 and, like them, no :hover and no transitions', !/:hover|transition/.test(style));
});

// ================================================== D. Help on K, P and J
attempt('D', function () {
  function fakeHelp() {
    const asked = [];
    return { asked: asked, api: { open: function (t) { asked.push(t); }, isOpen: function () { return false; } } };
  }
  {
    const f = fakeHelp();
    const p = load(party, { thornswoodHelp: f.api });
    p.win.thornswoodParty.open();
    const b = p.root.querySelector('#ts-party-help');
    yes('D1 the P panel has Help beside Close', !!b && b.textContent === 'Help' &&
        p.root.html.indexOf('ts-party-help') < p.root.html.indexOf('ts-party-close'));
    if (b) { b.onclick.call(b); }
    yes('D1 and it opens the help on People and puts the P panel down',
        f.asked.join() === 'people' && !p.win.thornswoodParty.isOpen() &&
        p.told.indexOf('thornswood-front party:closed') !== -1);
  }
  {
    const f = fakeHelp();
    const j = load(journal, { thornswoodHelp: f.api });
    j.win.thornswoodJournal.open();
    const b = j.root.querySelector('#ts-journal-help');
    yes('D2 the J panel has Help beside Close', !!b && b.textContent === 'Help');
    if (b) { b.onclick.call(b); }
    yes('D2 and it opens the help on People, which has journals, and puts J down',
        f.asked.join() === 'people' && !j.win.thornswoodJournal.isOpen() &&
        j.told.indexOf('thornswood-front journal:closed') !== -1);
  }
  {
    yes('D3 the K panel has Help beside Close',
        skills.indexOf("'<div class=\"tsbtn ghost\" data-act=\"help\">Help</div>' +\n        '<div class=\"tsbtn ghost\" data-act=\"close\">") !== -1);
    yes('D3 and hides it while creating, where this panel is all there is to do',
        /elHelp\.style\.display = cr \? 'none' : '';/.test(between(skills, '  function drawFoot() {', '\n  }\n') || ''));
    const click = between(skills, '  elHelp.onclick = function () {', '\n  };\n');
    function press(isCreating) {
      const f = fakeHelp();
      const api = { closed: 0, close: function () { this.closed++; } };
      const elHelp = {};
      new Function('creating', 'api', 'window', 'elHelp', (click || '') + '\n  };')(
        function () { return isCreating; }, api, { thornswoodHelp: f.api }, elHelp);
      if (elHelp.onclick) { elHelp.onclick(); }
      return { asked: f.asked, closed: api.closed };
    }
    const inWorld = press(false), making = press(true);
    yes('D3 pressed, it opens the help on Work and puts K down',
        !!click && inWorld.asked.join() === 'work' && inWorld.closed === 1);
    yes('D3 and while creating it does nothing', making.asked.length === 0 && making.closed === 0);
  }
});

// ================================================================ E. the server
attempt('E', function () {
  const sorted = function (a) { return a.slice().sort().join(' '); };
  yes('E1 the list named to everybody is exactly the commands that stay (' + PLAYER_WORDS.join(' ') + ')',
      sorted(PLAYER_WORDS) === sorted(STAY));
  yes('E1 /help, /where and /merchant are out of it, and still answered',
      ['/help', '/where', '/merchant'].every(function (w) { return PLAYER_WORDS.indexOf(w) === -1 && WORDS.indexOf(w) !== -1; }));
  yes('E1 the help panel names every word on the list', allText.length > 0 &&
      PLAYER_WORDS.every(function (w) { return allText.indexOf(w + ' ') !== -1 || allText.indexOf(w + ',') !== -1; }));

  const helpLine = liftFrom(gm, 'function helpLine(profileId) {', '  ');
  const helpBranch = between(gm, "    if (word === '/help' || word === '/commands') {", '\n    // Anything else beginning with a slash');
  const fallback = between(gm, "    toProfile(profileId, 'No command called ' + word", '\n');
  yes('E2 helpLine, the /help branch and the reply to a word nobody has are in the gamemode',
      !!helpLine && !!helpBranch && !!fallback);
  function say(body, word, tester) {
    const out = [];
    new Function('word', 'parts', 'toProfile', 'isPlaytester', 'roleOf', 'profileId', 'PLAYER_WORDS',
      helpLine + '\n' + body)(
      word, [word], function (p, t) { out.push(t); }, function () { return tester; },
      function () { return 'playtester'; }, 7, PLAYER_WORDS);
    return out;
  }
  const plain = say(helpBranch, '/help', false)[0] || '';
  yes('E2 /help says where the panel is: "' + plain.slice(0, 70) + '..."', /^Help is a panel: F7 opens it/.test(plain) &&
      /Help on the K, P or J panel/.test(plain));
  const fishes = say(fallback, '/fish', false)[0] || '';
  yes('E2 a word nobody has gets the same, after saying so', fishes === 'No command called /fish. ' + plain);
  const said = (plain.match(/\/[a-z]+/g) || []);
  yes('E2 and neither names a command to a person beyond the list',
      said.length > 0 && said.every(function (w) { return PLAYER_WORDS.indexOf(w) !== -1; }));
  const tester = say(helpBranch, '/help', true)[0] || '';
  yes('E2 a tester is told /tp, /give, /spawn and /where as well', /\/tp <place>/.test(tester) &&
      /\/give and \/spawn/.test(tester) && /\/where says where you stand/.test(tester));
  const lits = (gm.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '').match(/'[^'\n]*\/help(?!me|-me)[^'\n]*'/g) || [])
    .filter(function (l, i, all) { return all.indexOf(l) === i && l !== "'/help'"; });
  yes('E3 no line in the gamemode tells anybody to type /help' + (lits.length ? ' (' + lits.join(', ') + ')' : ''),
      lits.length === 0);

  // /where: a dev's and a tester's tool, refused to everybody else.
  const where = between(gm, "    if (word === '/where') {", "\n    /*\n      Staff: /kick");
  yes('E4 the /where branch is in handle()', !!where);
  function whereFor(isTester) {
    const out = [];
    let asked = false;
    new Function('word', 'profileId', 'actorId', 'toProfile', 'isPlaytester', 'needCharacter', 'mp', 'round1', 'log',
      where)(
      '/where', 7, 0xff000001, function (p, t) { out.push(t); }, function () { return isTester; },
      function () { asked = true; return true; },
      { get: function (id, k) { return k === 'pos' ? [1.04, 2, 3] : k === 'angle' ? [0, 0, 90] : 'WhiterunBanneredMare'; } },
      function (v) { return Math.round(Number(v) * 10) / 10; }, function () { });
    return { out: out, asked: asked };
  }
  const nobody = whereFor(false), them = whereFor(true);
  yes('E4 /where is refused to somebody who is not dev or a tester, before anything is looked up',
      nobody.out.length === 1 && /^\/where is not yours to run\./.test(nobody.out[0]) && !nobody.asked);
  yes('E4 and answers a tester with where they stand',
      them.out.length === 1 && /^WhiterunBanneredMare  pos 1, 2, 3  facing 90$/.test(them.out[0]));
});

// ======================================================= F. the pages that say so
attempt('F', function () {
  const lit = '"((?:[^"\\\\]|\\\\.)*)"';
  const re = new RegExp('new HelpItem\\(\\s*' + lit + '\\s*,\\s*' + lit + '\\s*,\\s*' + lit + '\\s*\\)', 'g');
  const items = [];
  let m;
  while ((m = re.exec(helpCs)) !== null) { items.push({ section: m[1], title: m[2], body: m[3] }); }
  const chat = items.filter(function (i) { return i.section === 'Chat and commands'; })
    .map(function (i) { return i.title + '. ' + i.body; }).join(' ');
  const named = (chat.match(/(^|[\s(,;])\/[a-z]+\b/g) || []).map(function (w) { return w.replace(/^[\s(,;]/, ''); })
    .filter(function (w, i, all) { return all.indexOf(w) === i; });
  const other = named.filter(function (w) { return STAY.indexOf(w) === -1; });
  yes('F1 the Help page\'s Chat and commands names no command but the ones that stay' +
      (other.length ? ' (not: ' + other.join(', ') + ')' : ''), named.length >= 5 && other.length === 0);
  yes('F1 and sends people to the help panel on F7, not to /help',
      /F7, unless you have moved it on the Controls page, opens the help in the game/.test(chat) && !/\/help\b(?!me)/.test(chat));
  const slash = /Dx\("command", "ThornsWood", "Type a command",\s*"([^"]*)"/.exec(keysCs);
  yes('F2 the Controls row for / says what is still typed there, and that the rest is staff\'s and dev\'s',
      !!slash && /staff and dev commands/.test(slash[1]) && /\/stuck, \/helpme and \/report/.test(slash[1]));
  yes('F2 and so does Thornswood.ini', /^; \/ooc\), \/roll, \/needs for the needs bars as text, and staff and dev$/m.test(ini) &&
      /^; commands\. The game's skill tree/m.test(ini));

  // docs/systems/commands.md, row by row: a row says "The list" where
  // people are told exactly when it stays a command.
  const at = commandsMd.indexOf('## Commands for people');
  const end = commandsMd.indexOf('\n## ', at + 5);
  const rows = commandsMd.slice(at, end).split('\n').filter(function (l) { return /^\| `/.test(l); })
    .map(function (l) { return l.split(' | '); });
  const listed = rows.filter(function (r) { return /^The list\b/.test(r[4] || ''); });
  const stays = rows.filter(function (r) { return /Stays a command/.test(r[5] || ''); });
  yes('F3 commands.md: the rows that say the list are the rows that stay (' + listed.length + ' rows)',
      listed.length > 0 && listed.length === stays.length &&
      listed.every(function (r) { return stays.indexOf(r) !== -1; }));
  const words = listed.map(function (r) { return r[0]; }).join(' ');
  const missing = STAY.filter(function (w) { return words.indexOf('`' + w) === -1; });
  yes('F3 and between them they name every word on the list' + (missing.length ? ' (not: ' + missing.join(', ') + ')' : ''),
      missing.length === 0);
  yes('F3 /where is with the testers\' commands now, and /help says where the panel is',
      !rows.some(function (r) { return /^\| `\/where`/.test(r[0]); }) &&
      /^\| `\/where` \| Testers and dev/m.test(commandsMd) &&
      rows.some(function (r) { return /^\| `\/help`, `\/commands`/.test(r[0]) && /^Nowhere\./.test(r[4]); }));
});

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
