// test-launcher-help.js
//
// The launcher's Help page says what this build does, and nothing it stopped
// doing.
//
// From the To Do List, entry 164: "The launcher Help page is the old project's
// help page with edits: a dead address, a password box that does not exist,
// and an explanation of parties." And: "Delete every entry that starts from
// the old engine. It currently tells people to type 192.135.119.166:25565
// into a screen that does not exist, and explains a password error the
// software cannot raise."
//
// Two halves. The first is the entry's own check, widened to everything that
// was found wrong on the page on 24 September: nothing from the old engine,
// nothing about kits that went on 20 September, no SunHelm, and every section
// printed once. The second is why the page went wrong in the first place: it
// was prose nobody compared with the code. So every number, key, command,
// group, class, profession and town the page names is read out of the file
// that decides it, and a change there that the page does not follow fails
// here.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);
function read() {
  const bits = Array.prototype.slice.call(arguments);
  return fs.readFileSync(path.join.apply(path, [TOOLS_DIR].concat(bits)), 'utf8').split(CR).join('');
}

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const helpSrc = process.env.HELP
  ? fs.readFileSync(process.env.HELP, 'utf8').split(CR).join('')
  : read('..', 'launcher', 'app', 'Help.cs');
const gm      = read('..', 'game', 'gamemode.js');
const emotes  = read('..', 'game', 'plugins', 'thornswood-emotes.js');
const front   = read('..', 'game', 'plugins', 'thornswood-front.js');
const vplug   = read('..', 'game', 'plugins', 'thornswood-voice.js');
const vpage   = read('..', 'game', 'ui', 'thornswood-voice.js');
const vserver = read('..', 'voice', 'voice-server.js');
const vinstall = read('Install-Voice.ps1');
const keys    = read('..', 'launcher', 'app', 'Keys.cs');
const shell   = read('..', 'launcher', 'app', 'Shell.cs');
const enforce = read('..', 'launcher', 'app', 'Enforce.cs');
const ini     = read('..', 'launcher', 'Thornswood.ini');

// ------------------------------------------------------------- the items
/*
  new HelpItem("Section", "Title", "Body"), as C# regular string literals.
  Counted as well as parsed: an item written some other way (a verbatim
  string, a concatenation) would otherwise walk past every check below.
*/
function unescape(s) {
  return s.replace(/\\(.)/g, function (m, c) {
    if (c === 'n') { return '\n'; }
    if (c === 't') { return '\t'; }
    return c;
  });
}
const LIT = '"((?:[^"\\\\]|\\\\.)*)"';
const itemRx = new RegExp('new HelpItem\\(\\s*' + LIT + '\\s*,\\s*' + LIT + '\\s*,\\s*' + LIT + '\\s*\\)', 'g');
const items = [];
let m;
while ((m = itemRx.exec(helpSrc)) !== null) {
  items.push({ section: unescape(m[1]), title: unescape(m[2]), body: unescape(m[3]) });
}
const written = (helpSrc.match(/new HelpItem\(/g) || []).length;
yes('the page has items, ' + items.length + ' of them', items.length > 20);
yes('and every one of them could be read (' + items.length + ' of ' + written + ')',
    items.length === written);

function all() {
  return items.map(function (i) { return i.title + '\n' + i.body; }).join('\n');
}
function item(section, title) {
  for (let i = 0; i < items.length; i++) {
    if (items[i].section === section && items[i].title === title) { return items[i].body; }
  }
  return '';
}
function sectionText(section) {
  return items.filter(function (i) { return i.section === section; })
    .map(function (i) { return i.title + '\n' + i.body; }).join('\n');
}
const page = all();

// ------------------------------------------------ what the entry says went
/*
  The entry's own check is Select-String for 'Skyrim Together|192.135.119.166|
  password you entered'. The rest are what the page still said on 24 September
  once it was read against the code, each with the reason it is wrong.
*/
const DEAD = [
  [/Skyrim Together|\bTogether\b/, 'the old engine by name'],
  [/192\.135\.119\.166|25565/, 'the old engine\'s address and port'],
  [/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, 'any server address at all: it arrives with the update'],
  [/password you entered/i, 'a password error this client cannot raise'],
  [/no party system/i, 'parties, when /party runs in the gamemode'],
  [/no text chat box/i, 'no chat box, when Enter opens one'],
  [/SunHelm/i, 'SunHelm, which is out of the load order'],
  [/50 to 150 gold|Fifty to a hundred/i, 'the old purse, when it is 40 gold once'],
  [/Carried:|Plus what everyone gets/, 'the sixteen starting kits, gone on 20 September'],
  [/A, S, D, F/, 'a flute played on the keyboard'],
  [/two fifths of the gold/i, 'the death penalty of a mod that is out'],
  [/twelve gestures|second ring/i, 'a wheel of twelve, when it is six groups'],
  [/switch for it in Settings|change it in Settings/i, 'an address switch Settings no longer has'],
  [/every half minute/i, 'a reminder in the chat, which is silent now unless the panel failed'],
  [/after yourself/i, 'naming the character after yourself (entry 163)'],
  [/once every \d+ hours|hands you one/i, 'a free tool at the seam, which toolGate stopped handing over on 21 September'],
  [/Profile\\+MyGames\\+Saves/i, 'a saves folder, when the character lives on the server']
];
DEAD.forEach(function (d) {
  const hit = d[0].exec(page);
  yes('gone: ' + d[1] + (hit ? ' (still says "' + hit[0] + '")' : ''), !hit);
});
yes('gone: a "Starting out" section of kits',
    !items.some(function (i) { return i.section === 'Starting out'; }));
yes('gone: a "Playing together" section about parties that did not exist',
    !items.some(function (i) { return i.section === 'Playing together'; }));

// --------------------------------------------------------------- the words
{
  const player = /\bplayers?\b/i.exec(helpSrc);
  yes('the file never says "player"' + (player ? ' (says "' + player[0] + '")' : ''), !player);
  // Built from its code, the way CR is above, so a search of the repository
  // for the character itself finds only the places that say it.
  yes('and has no em dash', helpSrc.indexOf(String.fromCharCode(0x2014)) === -1);
}

// ------------------------------------------------------------ the sections
/*
  Shell.cs BuildHelp draws a heading every time the section CHANGES, so a
  section that comes back later is printed twice. "If it breaks" was: two of
  its items had been added after Tips.
*/
{
  const seen = [];
  let broken = '';
  for (let i = 0; i < items.length; i++) {
    const s = items[i].section;
    if (i > 0 && items[i - 1].section === s) { continue; }
    if (seen.indexOf(s) !== -1) { broken = s; break; }
    seen.push(s);
  }
  yes('every section is one run, so its heading is drawn once' +
      (broken ? ' ("' + broken + '" comes back)' : ''), !broken);
  ['Joining', 'Character', 'Chat and commands', 'Emotes', 'The mods',
   'In game', 'If it breaks', 'Tips'].forEach(function (s) {
    yes('there is a "' + s + '" section', seen.indexOf(s) !== -1);
  });
  const titles = {};
  let dup = '';
  items.forEach(function (i) {
    const k = i.section + '/' + i.title;
    if (titles[k]) { dup = k; }
    titles[k] = true;
  });
  yes('no two items share a title' + (dup ? ' (' + dup + ')' : ''), !dup);
}

// -------------------------------------------------------- the commands
/*
  Every command the page names is one the server answers, for everybody.
  PLAYER_WORDS is the gamemode's own list of what a person who is not a
  playtester is told about; naming /tp here would be the same invitation
  /help was fixed for.
*/
function arrayLiteral(src, name) {
  const at = src.indexOf('const ' + name + ' = [');
  if (at < 0) { return null; }
  const end = src.indexOf('];', at);
  const body = src.slice(src.indexOf('[', at), end + 1)
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  try { return JSON.parse(body.replace(/'/g, '"').replace(/,\s*\]/, ']')); }
  catch (e) { return null; }
}
const everybody = arrayLiteral(gm, 'PLAYER_WORDS');
yes('the gamemode\'s list of everybody\'s commands can be read', Array.isArray(everybody) && everybody.length > 10);
{
  const named = {};
  const rx = /(^|[\s(,;])(\/[a-z]+)\b/g;
  let c;
  while ((c = rx.exec(page)) !== null) { named[c[2]] = true; }
  const words = Object.keys(named);
  yes('the page names commands, ' + words.length + ' of them', words.length >= 10);
  const unknown = words.filter(function (w) { return (everybody || []).indexOf(w) === -1; });
  yes('and every one is on the gamemode\'s list for everybody' +
      (unknown.length ? ' (not: ' + unknown.join(', ') + ')' : ''), unknown.length === 0);
  ['/tp', '/give', '/spawn', '/goto', '/restart'].forEach(function (w) {
    yes('it does not name the playtester command ' + w, !named[w]);
  });

  const a = gm.indexOf("if (word === '/help' || word === '/commands') {");
  const b = a < 0 ? -1 : gm.indexOf('// Anything else beginning with a slash', a);
  const helpBlock = (a >= 0 && b > a) ? gm.slice(a, b) : '';
  const topics = [];
  // A topic is the word after /help in a list: "/help talking, /help land or
  // /help staff for one topic each". Not "/help in the chat".
  const tr = /\/help ([a-z]+)(?=[,.]| or | for )/g;
  let t;
  while ((t = tr.exec(page)) !== null) { if (topics.indexOf(t[1]) === -1) { topics.push(t[1]); } }
  yes('the page points at /help topics, ' + topics.length + ' of them', topics.length >= 6);
  const missing = topics.filter(function (x) { return helpBlock.indexOf("topic === '" + x + "'") === -1; });
  yes('and /help answers every one' + (missing.length ? ' (not: ' + missing.join(', ') + ')' : ''),
      helpBlock && missing.length === 0);
}

// ---------------------------------------------------------- the chat box
/*
  The chat box is server wide as it ships: the voice service sends every plain
  line to every peer. Entry 150 reached main as a setting, THORNSWOOD_CHAT_RANGE,
  that keeps a line to the people near and ships off, so the old loop is still
  there for the off case and finding it proves nothing on its own. What the
  page stands on is the default: off in the voice service when nothing sets
  it, and off in Install-Voice.ps1, which is what sets it on the box. Turn
  either default on and this fails, and the page has to change with it rather
  than going on saying the old thing. Turning it on by hand for one install is
  Patrick's call and is not in the repository, so no harness can see it.
*/
{
  const c = vserver.indexOf("if (msg.t === 'chat') {");
  const block = c < 0 ? '' : vserver.slice(c, vserver.indexOf('ws.onclose', c));
  let rangeOf = null;
  const fr = /function chatRangeOf\(v\) \{[\s\S]*?\n\}/.exec(vserver);
  try { rangeOf = fr ? new Function(fr[0] + '\nreturn chatRangeOf;')() : null; } catch (e) { rangeOf = null; }
  yes('the voice service reads its chat range from THORNSWOOD_CHAT_RANGE',
      /const CHAT_RANGE = chatRangeOf\(process\.env\.THORNSWOOD_CHAT_RANGE\);/.test(vserver) && !!rangeOf);
  yes('and an unset or off range is no range at all, so every line goes to everybody',
      !!rangeOf && rangeOf(undefined) === 0 && rangeOf('') === 0 && rangeOf('off') === 0);
  yes('Install-Voice.ps1 installs the voice service with the range off',
      /\[string\]\$ChatRange = 'off'/.test(vinstall) &&
      /set THORNSWOOD_CHAT_RANGE=\$ChatRange/.test(vinstall));
  yes('the voice service still sends a plain chat line to every peer when the range is off',
      /for \(const \[, p\] of peers\) p\.ws\.send\(out\);/.test(block));
  yes('so the page says a chat line goes to everybody connected',
      /goes to everybody connected/.test(item('Chat and commands', 'The chat box')));
  yes('and that a slash line is a command, which the voice service holds back',
      /text\.charAt\(0\) === '\/'/.test(block) &&
      /starts with a slash is a command/.test(item('Chat and commands', 'The chat box')));
  yes('the console is switched off in the plugin, and the page says so',
      /The console is switched off/.test(front) &&
      /console opens for a moment and shuts again/.test(item('Chat and commands', 'The console is switched off')));
}

// ------------------------------------------------------------- the ranges
/*
  Metres the way the voice page counts them, UNITS_PER_METRE, so the page and
  the overlay agree on what a metre is.
*/
function num(src, rx) { const r = rx.exec(src); return r ? Number(r[1]) : NaN; }
const UPM = num(vpage, /var UNITS_PER_METRE = (\d+);/);
yes('the voice page says how many units are a metre (' + UPM + ')', UPM > 0);
{
  const range = num(gm, /var OOC_RANGE = (\d+);/);
  const metres = Math.round(range / UPM / 10) * 10;
  yes('/ooc reaches ' + range + ' units, and the page says about ' + metres + ' metres',
      range > 0 && item('Chat and commands', 'Out of character').indexOf('within about ' + metres + ' metres') !== -1);
  yes('and it is the same room first, as the page says',
      /if \(oCell !== myCell\) \{ continue; \}/.test(gm) &&
      /in the same place as you/.test(item('Chat and commands', 'Out of character')));
  const sides = num(gm, /var ROLL_MAX_SIDES = (\d+);/);
  const dice = num(gm, /var ROLL_MAX_DICE = (\d+);/);
  yes('the dice limits are the server\'s, ' + sides + ' sides and ' + dice + ' dice',
      item('Chat and commands', 'Dice').indexOf('Up to ' + sides + ' sides and ' + dice + ' dice') !== -1);
}
{
  const voice = item('Chat and commands', 'Voice');
  ['whisper', 'local', 'yell'].forEach(function (mode) {
    const max = num(vpage, new RegExp(mode + ':\\s*\\{[^}]*max:\\s*(\\d+)'));
    yes('the ' + mode + ' range is ' + max + ' metres on the voice page, and on this one',
        max > 0 && voice.indexOf('about ' + max + ' metres') !== -1);
  });
}

// ----------------------------------------------------------------- the keys
/*
  A key named on the page has to be the key a fresh install has. That is the
  template's value where the template sets one (ThornIni.Ensure writes it on a
  machine with no file), and the plugin's fallback where it does not. When the
  two disagree, the page must not name a letter at all: the emote wheel is G
  in the template and B in the code, so the page sends people to the Controls
  page for it.
*/
const LETTER = {
  30: 'A', 48: 'B', 46: 'C', 32: 'D', 18: 'E', 33: 'F', 34: 'G', 35: 'H', 23: 'I',
  36: 'J', 37: 'K', 38: 'L', 50: 'M', 49: 'N', 24: 'O', 25: 'P', 16: 'Q', 19: 'R',
  31: 'S', 20: 'T', 22: 'U', 47: 'V', 17: 'W', 45: 'X', 21: 'Y', 44: 'Z', 28: 'Enter'
};
function templateKey(name) {
  const r = new RegExp('^\\s*' + name + '\\s*=\\s*(\\d+)', 'm').exec(ini);
  return r ? Number(r[1]) : null;
}
function keysFallback(name) {
  const r = new RegExp('ThornIni, "' + name + '", (\\d+)\\)').exec(keys);
  return r ? Number(r[1]) : null;
}
function freshKey(name) {
  const t = templateKey(name);
  return t !== null ? t : keysFallback(name);
}
[
  ['SkillsKey', 'Character', 'K is your character', function (k) { return k + ' opens your profession'; }],
  ['ChatKey', 'Chat and commands', 'The chat box', function (k) { return k + ' opens it'; }],
  // The party wording is test-help-parties.js's, from main (entry 336), and
  // that harness holds the rest of the two party items to the code.
  ['PartyKey', 'Chat and commands', 'Parties', function (k) { return k + ', unless you have moved it on the Controls page, opens your friends and your party'; }],
  ['JournalKey', 'Chat and commands', 'Journals', function (k) { return k + ' opens your journals'; }],
  ['FriendKey', 'Chat and commands', 'Friends and trading', function (k) { return 'press ' + k + ' to ask them to be friends'; }],
  ['TradeWithKey', 'Chat and commands', 'Friends and trading', function (k) { return k + ' to offer a trade'; }],
  ['MuteThemKey', 'Chat and commands', 'Friends and trading', function (k) { return k + ' to stop hearing them'; }],
  ['StopKey', 'Emotes', 'Getting out of one', function (k) { return k + ' stands you up'; }],
  ['PushToTalk', 'Chat and commands', 'Voice', function (k) { return 'Hold ' + k + ' to talk'; }]
].forEach(function (row) {
  const code = freshKey(row[0]);
  const t = templateKey(row[0]);
  const f = keysFallback(row[0]);
  const agree = t === null || f === null || t === f;
  const letter = LETTER[code];
  yes(row[0] + ' is ' + letter + ' on a fresh install, and the page says ' + JSON.stringify(row[3](letter)),
      !!letter && agree && item(row[1], row[2]).indexOf(row[3](letter)) !== -1);
});
{
  const t = templateKey('WheelKey');
  const f = num(emotes, /const OPEN_KEY\s*=\s*key\('WheelKey', (\d+)\)/);
  const wheel = item('Emotes', 'The wheel');
  yes('the wheel key differs between the template (' + LETTER[t] + ') and the code (' + LETTER[f] +
      '), so the page names no letter for it and sends people to the Controls page',
      t !== f ? (/Controls page/.test(wheel) && !/\b[A-Z]\b/.test(wheel)) : true);
  const mode = num(vplug, /let MODE_KEY = (\d+);/);
  yes('the voice mode key is ' + LETTER[mode] + ' in the plugin and not in the template, and the page says so',
      templateKey('VoiceModeKey') === null && item('Chat and commands', 'Voice').indexOf(LETTER[mode] + ' steps your voice') !== -1);
}

// --------------------------------------------------------------- the wheel
{
  const cats = [];
  const cr = /\{ name: '([^']+)', items: \[/g;
  let c;
  while ((c = cr.exec(emotes)) !== null) { cats.push(c[1]); }
  const count = (emotes.slice(emotes.indexOf('const CATEGORIES'), emotes.indexOf('];', emotes.indexOf('const CATEGORIES')))
    .match(/event: '/g) || []).length;
  const wheel = item('Emotes', 'The wheel');
  yes('the wheel has groups (' + cats.join(', ') + ')', cats.length >= 4);
  const unnamed = cats.filter(function (x) { return wheel.indexOf(x) === -1; });
  yes('and the page names every one of them' + (unnamed.length ? ' (not: ' + unnamed.join(', ') + ')' : ''),
      unnamed.length === 0);
  yes('the page says ' + count + ' emotes, which is how many the wheel carries',
      count > 0 && wheel.indexOf(count + ' emotes') !== -1);
}

// ---------------------------------------------------- classes, towns, purse
function tableNames(src, name) {
  const at = src.indexOf('var ' + name + ' = {');
  if (at < 0) { return []; }
  let depth = 0, i = src.indexOf('{', at), end = -1;
  for (; i < src.length; i++) {
    if (src[i] === '{') { depth++; }
    else if (src[i] === '}') { depth--; if (depth === 0) { end = i; break; } }
  }
  const body = src.slice(at, end);
  const out = [];
  const rx = /^\s{4}[a-z]+:\s*\{ name: '([^']+)'/gm;
  let r;
  while ((r = rx.exec(body)) !== null) { out.push(r[1]); }
  return out;
}
{
  const character = sectionText('Character');
  const classes = tableNames(gm, 'CLASSES');
  const profs = tableNames(gm, 'PROFESSIONS');
  yes('the gamemode has ' + classes.length + ' classes and ' + profs.length + ' professions',
      classes.length === 5 && profs.length === 8);
  const lostC = classes.filter(function (x) { return character.indexOf(x) === -1; });
  const lostP = profs.filter(function (x) { return character.indexOf(x) === -1; });
  yes('the Character section names every class' + (lostC.length ? ' (not: ' + lostC.join(', ') + ')' : ''), lostC.length === 0);
  yes('and every profession' + (lostP.length ? ' (not: ' + lostP.join(', ') + ')' : ''), lostP.length === 0);

  let towns = [];
  try {
    const cg = /const CHARGEN = (\{.*\});/.exec(gm);
    const t = JSON.parse(cg[1]).towns;
    towns = Object.keys(t).map(function (k) { return t[k].town; });
  } catch (e) { towns = []; }
  yes('the gamemode has ' + towns.length + ' towns to wake up in', towns.length > 0);
  const lostT = towns.filter(function (x) { return item('Character', 'Where you wake up').indexOf(x) === -1; });
  yes('and the page names every one' + (lostT.length ? ' (not: ' + lostT.join(', ') + ')' : ''), lostT.length === 0);

  const purse = num(gm, /var PURSE = (\d+);/);
  yes('the purse is ' + purse + ' gold, and the page says so',
      purse > 0 && item('Character', 'What you start with').indexOf(purse + ' gold, once') !== -1);

  const tools = [];
  const tr = /^  (miner|woodworker|farmer): \{\n    give: '[^']+',\n    accept: [\s\S]*?name: '((?:[^'\\]|\\.)*)'/gm;
  let r;
  while ((r = tr.exec(gm)) !== null) { tools.push(r[2].replace(/\\'/g, '\'')); }
  yes('the gamemode hands out ' + tools.length + ' tools (' + tools.join(', ') + ')', tools.length === 3);
  const lostTool = tools.filter(function (x) { return item('Character', 'The tools come with the pick').indexOf(x) === -1; });
  yes('and the page names every one' + (lostTool.length ? ' (not: ' + lostTool.join(', ') + ')' : ''), lostTool.length === 0);
  /*
    What happens once the tool is gone, read from what the code DOES rather
    than from a constant. TOOL_AGAIN_HOURS is still defined, and the first
    version of this check passed on it while the page promised a free tool at
    the seam that toolGate had stopped handing over (Patrick, 21 September:
    "Don't let p[eople chop wood, mine, or farm without a pickaxe, shovel, or
    woodcutters axe"). So: toolGate refuses and hands nothing over, nothing
    calls offerTool, and every refusal sends people to a smith. The day a
    handout comes back, the first two fail and the page has to follow.
  */
  const gateAt = gm.indexOf('function toolGate(actorId, key) {');
  const gate = gateAt < 0 ? '' : gm.slice(gateAt, gm.indexOf('\n}\n', gateAt))
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  yes('toolGate refuses somebody with no tool and hands nothing over',
      /return 'You need a ' \+ tool\.name \+ ' in your pack for that\. ' \+ tool\.where;/.test(gate) &&
      !/\b(offerTool|handTool|giveTool)\(/.test(gate));
  const offerCalls = (gm.match(/\bofferTool\(/g) || []).length;
  yes('nothing calls offerTool, so no seam, block, kiln or plot gives a tool away (' +
      (offerCalls - 1) + ' callers)', offerCalls === 1 && /function offerTool\(/.test(gm));
  const toolsAt = gm.indexOf('const TOOLS = {');
  const toolsBlock = toolsAt < 0 ? '' : gm.slice(toolsAt, gm.indexOf('\n};\n', toolsAt));
  const wheres = toolsBlock.match(/where: '[^']*/g) || [];
  yes('every refusal names a smith as the way to another (' + wheres.length + ' of 3)',
      wheres.length === 3 && wheres.every(function (w) { return /a smith forges them/i.test(w); }));
  const toolItem = item('Character', 'The tools come with the pick');
  yes('and the page says a smith forges the next one and nothing hands one out',
      /a smith forges the next one/.test(toolItem) && /nothing in the world hands one out/.test(toolItem) &&
      !/once every \d+ hours|hands you one/.test(toolItem));

  const remind = num(gm, /const CHOOSE_REMIND_MS = (\d+);/) / 1000;
  const later = num(gm, /const CHOOSE_LATER_MS = (\d+);/) / 60000;
  const panel = item('Character', 'If the panel does not appear');
  yes('the panel comes back every ' + remind + ' seconds, and after ' + later + ' minutes once closed, as the page says',
      panel.indexOf('every ' + remind + ' seconds') !== -1 && panel.indexOf(later + ' minutes') !== -1);
  yes('and the server only says so in the chat when the panel did not open',
      /if \(!openCreation\(actorId\)\) \{\s*say\(actorId, 'The starting panel did not open/.test(gm) &&
      /only says so in the chat if it could not/.test(panel));
  yes('the town is the pick that ends creation, as the page says',
      /The home is the one pick that ends creation/.test(gm) &&
      /The town is the choice that ends creation/.test(item('Character', 'Where you wake up')));
}

// --------------------------------------------------------- dying, address
{
  yes('a death sends a person to a temple, as the page says',
      /const PREFER_SLOT = 'temple';/.test(gm) && /temple of the hold you died in/.test(item('In game', 'When you die')));
  yes('and Solstheim to Raven Rock',
      /return arrive\('ravenrock'/.test(gm) && /Solstheim sends you to Raven Rock/.test(item('In game', 'When you die')));
  yes('the address arrives with the update, which is what the page says',
      /v\.serverAddress != cfg\.ServerAddress\) \{ cfg\.ServerAddress = v\.serverAddress;/.test(shell) &&
      /address arrives with the launcher's updates/.test(item('Joining', 'There is nothing to type')));
  yes('auto join is forced in Settings, so the page offers no switch for it',
      /if \(!cfg\.AutoJoin\) \{ cfg\.AutoJoin = true;/.test(shell));

  // Three modes, and only the restart puts everybody out. The update closes
  // the game only where the launcher still needs it (Patrick, 23 September:
  // "The server never actually kicked me").
  const r = item('In game', 'Restarts and updates are announced');
  yes('a notice does not close the game, as the page says',
      /Your game does not close\./.test(gm) && /your game does not close/.test(r));
  yes('an update closes it only when the launcher still needs it, as the page says',
      /unless your launcher already has it/.test(gm) && /unless it already has it/.test(r));
}

// --------------------------------------------------------- held settings
{
  const held = item('Tips', 'A few settings are held in place for you');
  yes('the settings held for you are the ones Enforce.cs writes',
      /"bFavoritesMenu"/.test(enforce) && /"bTweenMenu"/.test(enforce) &&
      /OpenAnimationReplacer\.ini/.test(enforce) &&
      /favourites menu/.test(held) && /Tab menu/.test(held) && /animation replacer/.test(held));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
