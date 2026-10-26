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
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);
function read() {
  const bits = Array.prototype.slice.call(arguments);
  return fs.readFileSync(path.join.apply(path, [REPO_DIR].concat(bits)), 'utf8').split(CR).join('');
}

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const helpSrc = process.env.HELP
  ? fs.readFileSync(process.env.HELP, 'utf8').split(CR).join('')
  : read('launcher', 'app', 'Help.cs');
const gm      = read('game', 'gamemode.js');
const emotes  = read('game', 'plugins', 'thornswood-emotes.js');
const front   = read('game', 'plugins', 'thornswood-front.js');
const vplug   = read('game', 'plugins', 'thornswood-voice.js');
const vpage   = read('game', 'ui', 'thornswood-voice.js');
const vserver = read('voice', 'voice-server.js');
const vinstall = read('scripts/deploy/Install-Voice.ps1');
const keys    = read('launcher', 'app', 'Keys.cs');
// Shell is one partial class across Shell.cs and the Shell*.cs files since
// the split (#500), so the update code the address check reads is in
// ShellUpdate.cs now. All of them, read as the one class they compile to.
const shell   = fs.readdirSync(path.join(REPO_DIR, 'launcher', 'app'))
  .filter(function (f) { return /^Shell\w*\.cs$/.test(f); })
  .sort()
  .map(function (f) { return read('launcher', 'app', f); })
  .join('\n');
const enforce = read('launcher', 'app', 'Enforce.cs');
const ini     = read('launcher', 'Thornswood.ini');

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
  The entry's own check is Select-String for the old multiplayer mod's name,
  192.135.119.166 and 'password you entered'. The rest are what the page still said on 24 September
  once it was read against the code, each with the reason it is wrong.
*/
const DEAD = [
  [/Skyrim\s*Together|\bTogether\b/, 'the old engine by name'],
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
  [/twelve gestures|second ring|six groups/i, 'an old wheel of twelve, or of six groups'],
  [/switch for it in Settings|change it in Settings/i, 'an address switch Settings no longer has'],
  [/every half minute/i, 'a reminder in the chat, which is silent now unless the panel failed'],
  [/after yourself/i, 'naming the character after yourself (entry 163)'],
  [/once every \d+ hours|hands you one/i, 'a free tool at the seam, which toolGate stopped handing over on 21 September'],
  [/Profile\\+MyGames\\+Saves/i, 'a saves folder, when the character lives on the server'],
  // Issue #418, 28 September: the update feed is thornswood.net since #907,
  // so GitHub's hourly limit and an access token are gone with it.
  [/access token|too many update checks/i, 'a GitHub update token or rate limit, when updates come from thornswood.net']
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
  ['Joining', 'Character', 'Keys', 'Chat and commands', 'Emotes', 'The mods',
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
yes('the gamemode\'s list of everybody\'s commands can be read', Array.isArray(everybody) && everybody.indexOf('/helpme') !== -1);
{
  const named = {};
  const rx = /(^|[\s(,;])(\/[a-z]+)\b/g;
  let c;
  while ((c = rx.exec(page)) !== null) { named[c[2]] = true; }
  const words = Object.keys(named);
  // Fewer every week since 4 Oct, when Patrick ruled that what people do is
  // keys and panels and not commands: #1603 took /rest off. Enough that the
  // scan above is known to read the page.
  yes('the page names commands, ' + words.length + ' of them', words.length >= 5);
  const unknown = words.filter(function (w) { return (everybody || []).indexOf(w) === -1; });
  yes('and every one is on the gamemode\'s list for everybody' +
      (unknown.length ? ' (not: ' + unknown.join(', ') + ')' : ''), unknown.length === 0);
  ['/tp', '/give', '/spawn', '/goto', '/restart'].forEach(function (w) {
    yes('it does not name the playtester command ' + w, !named[w]);
  });

  /*
    The help in the game is a panel since #1633, and the page sends people to
    it rather than to /help. Its topics are the panel's own titles, read out
    of game/ui/thornswood-help.js; its key is HelpKey, held below with the
    others.
  */
  yes('the page tells nobody to type /help', !/\/help\b(?!me)/.test(page));
  const helpPanel = read('game', 'ui', 'thornswood-help.js');
  const titles = [];
  const tr = /\{ id: '[a-z]+', title: '([^']+)'/g;
  let t;
  while ((t = tr.exec(helpPanel)) !== null) { titles.push(t[1].toLowerCase()); }
  yes('the help panel has its six topics (' + titles.join(', ') + ')', titles.length === 6);
  const panelItem = item('Chat and commands', 'Everything else is on the help panel');
  const missing = titles.filter(function (x) { return panelItem.indexOf(x) === -1; });
  yes('and the page names every one' + (missing.length ? ' (not: ' + missing.join(', ') + ')' : ''),
      titles.length === 6 && missing.length === 0);
}

// ---------------------------------------------------------- the chat box
/*
  The chat box is local as it ships since 4 Oct: Install-Voice.ps1 sets
  THORNSWOOD_CHAT_RANGE on for live and dev (Patrick: local chat "should have
  went out with the other changes to live"), and the voice service then sends a
  plain line only to the people hearers() finds in the same cell and within
  the range. The old loop to every peer is still there for a service with the
  setting off, so finding it proves nothing on its own. What the page stands
  on is the default Install-Voice.ps1 installs with, and that a later install
  keeps what is running. Turn the default off and this fails, and the page has
  to change with it rather than going on saying the old thing.
*/
{
  const c = vserver.indexOf("if (msg.t === 'chat') {");
  const block = c < 0 ? '' : vserver.slice(c, vserver.indexOf('ws.onclose', c));
  let rangeOf = null;
  const fr = /function chatRangeOf\(v\) \{[\s\S]*?\n\}/.exec(vserver);
  try { rangeOf = fr ? new Function(fr[0] + '\nreturn chatRangeOf;')() : null; } catch (e) { rangeOf = null; }
  yes('the voice service reads its chat range from THORNSWOOD_CHAT_RANGE',
      /const CHAT_RANGE = chatRangeOf\(process\.env\.THORNSWOOD_CHAT_RANGE\);/.test(vserver) && !!rangeOf);
  yes('and on is the same 4000 units /ooc uses, while unset or off is no range at all',
      !!rangeOf && rangeOf('on') === 4000 && rangeOf(undefined) === 0 && rangeOf('') === 0 && rangeOf('off') === 0);
  yes('Install-Voice.ps1 installs the voice service with the range on',
      /\[string\]\$ChatRange = 'on'/.test(vinstall) &&
      /set THORNSWOOD_CHAT_RANGE=\$ChatRange/.test(vinstall));
  // Since #1406 a plain line goes out through deliver(), which also puts the
  // line above the head for those close enough and skips anybody who has
  // blocked the sender. With the range off it is still every peer.
  const everyone = block.indexOf('for (const [, p] of peers) deliver(p);');
  yes('a plain line goes out through deliver(), and to every peer only when the range is off',
      everyone > block.indexOf('if (CHAT_RANGE) {') && block.indexOf('if (CHAT_RANGE) {') >= 0 &&
      /function deliver\(p\) \{[\s\S]*?p\.ws\.send\(copy\);/.test(block));
  yes('and a later install keeps whatever range is running, off included',
      /\$chatExplicit -and "\$current" -match ';chat=\(\\d\+\)'/.test(vinstall) &&
      /if \(\$ChatRange -eq '0'\) \{ \$ChatRange = 'off' \}/.test(vinstall));
  yes('with a range, a plain chat line goes only to the people hearers() finds near',
      /if \(CHAT_RANGE\) \{\s*const heard = hearers\(myId, me, chatReach\('say'\)\);/.test(block) &&
      /them\.cell !== mine\.cell/.test(vserver) && /> reach \* reach\) continue;/.test(vserver));
  yes('so the page says a chat line reaches the people near you, in the same place and within about 60 metres',
      /reaches the people near you, in the same place and within about 60 metres/.test(item('Chat and commands', 'The chat box')) &&
      !/everybody connected/.test(item('Chat and commands', 'The chat box')));
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
  31: 'S', 20: 'T', 22: 'U', 47: 'V', 17: 'W', 45: 'X', 21: 'Y', 44: 'Z', 28: 'Enter', 53: '/',
  65: 'F7'
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
  ['PushToTalk', 'Chat and commands', 'Voice', function (k) { return 'Hold ' + k + ' to talk'; }],
  ['VoiceLockKey', 'Chat and commands', 'Voice', function (k) { return 'press ' + k + ' to keep the microphone open until you press ' + k + ' again'; }],
  ['CommandKey', 'Chat and commands', 'The chat box', function (k) { return k + ' opens it with the slash already typed'; }],
  // The help panel's own key (#1633).
  ['HelpKey', 'Chat and commands', 'Everything else is on the help panel', function (k) { return k + ', unless you have moved it on the Controls page, opens the help in the game'; }]
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
  // Since #529 they agree (G), and then the page names it.
  yes('and when they agree the wheel item names that key (' + LETTER[t] + ')',
      t === f ? wheel.indexOf(LETTER[t] + ' opens a wheel') === 0 : true);
  const mode = num(vplug, /let MODE_KEY = (\d+);/);
  yes('the voice mode key is ' + LETTER[mode] + ' in the plugin, the template agrees, and the page says so',
      (templateKey('VoiceModeKey') === null || templateKey('VoiceModeKey') === mode) &&
      item('Chat and commands', 'Voice').indexOf(LETTER[mode] + ' steps your voice') !== -1);
}

// --------------------------------------------------------------- the wheel
{
  const start = emotes.indexOf('const EMOTES = [');
  const end = start < 0 ? -1 : emotes.indexOf('\n];', start);
  const body = (start >= 0 && end >= 0) ? emotes.slice(start, end) : '';
  const count = (body.match(/event: '/g) || []).length;
  const wheel = item('Emotes', 'The wheel');
  yes('the wheel lists ' + count + ' emotes', count >= 8);
  yes('the page says ' + count + ' emotes, which is how many the wheel carries',
      count > 0 && wheel.indexOf(count + ' emotes') !== -1);
  yes('the page names the quick slots and the search',
      /quick slots/.test(wheel) && /search/.test(wheel));
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
  yes('the gamemode has ' + towns.length + ' towns to start in', towns.length > 0);
  const lostT = towns.filter(function (x) { return item('Character', 'Where you start').indexOf(x) === -1; });
  yes('and the page names every one' + (lostT.length ? ' (not: ' + lostT.join(', ') + ')' : ''), lostT.length === 0);

  const purse = num(gm, /var PURSE = (\d+);/);
  yes('the purse is ' + purse + ' gold, and the page says so',
      purse > 0 && item('Character', 'What you start with').indexOf(purse + ' gold, once') !== -1);

  const tools = [];
  // Every TOOLS row with a give, which is handed over at the pick: the
  // miner's, woodworker's and farmer's, and the fisher's pole since #1379.
  const tr = /^  (\w+): \{\n    give: '[^']+',\n    accept: [\s\S]*?name: '((?:[^'\\]|\\.)*)'/gm;
  let r;
  while ((r = tr.exec(gm)) !== null) { tools.push(r[2].replace(/\\'/g, '\'')); }
  yes('the gamemode hands out ' + tools.length + ' tools (' + tools.join(', ') + ')', tools.length >= 4);
  const lostTool = tools.filter(function (x) { return item('Character', 'The tools come with the pick').indexOf(x) === -1; });
  yes('and the page names every one' + (lostTool.length ? ' (not: ' + lostTool.join(', ') + ')' : ''), lostTool.length === 0);
  /*
    What happens once the tool is gone, read from what the code DOES rather
    than from a constant. TOOL_AGAIN_HOURS stayed defined until #1038, and the
    first version of this check passed on it while the page promised a free
    tool at the seam that toolGate had stopped handing over (Patrick, 21
    September: "Don't let p[eople chop wood, mine, or farm without a pickaxe,
    shovel, or woodcutters axe"). So: toolGate refuses and hands nothing over,
    there is no offerTool and handTool is called only by giveTool at the pick,
    and every refusal sends people to a smith. The day a handout comes back,
    the first two fail and the page has to follow.
  */
  const gateAt = gm.indexOf('function toolGate(actorId, key) {');
  const gate = gateAt < 0 ? '' : gm.slice(gateAt, gm.indexOf('\n}\n', gateAt))
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  yes('toolGate refuses somebody with no tool and hands nothing over',
      /return 'You need ' \+ aWord\(tool\.name\) \+ ' in your pack for that\. ' \+ tool\.where;/.test(gate) &&
      !/\b(offerTool|handTool|giveTool)\(/.test(gate));
  // #1038: offerTool, the free replacement nothing called, is gone, and the
  // one way a tool is handed over is giveTool at a starting class's pick.
  const gmCode = gm.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  const handCalls = (gmCode.match(/\bhandTool\(/g) || []).length;
  yes('there is no offerTool, and handTool is called only by giveTool, so no seam, block, kiln or plot gives a tool away (' +
      (handCalls - 1) + ' caller)', !/\bofferTool\b/.test(gmCode) && !/\bTOOL_AGAIN_HOURS\b/.test(gmCode) &&
      handCalls === 2 && /function giveTool\(actorId, key\) \{\s*const tool = handTool\(actorId, key\);/.test(gmCode));
  const toolsAt = gm.indexOf('const TOOLS = {');
  const toolsBlock = toolsAt < 0 ? '' : gm.slice(toolsAt, gm.indexOf('\n};\n', toolsAt));
  const wheres = toolsBlock.match(/where: '[^']*/g) || [];
  // Four tools since the fisher's pole (#1379): a smith forges the pickaxe,
  // the axe and the shovel, and a woodwright makes the pole.
  const names = (toolsBlock.match(/name: '(?:[^'\\]|\\.)*'/g) || []).map(function (n) {
    return n.slice(7, -1).replace(/\\'/g, "'");
  });
  yes('every refusal names who makes another, a smith or for the pole a woodwright (' + wheres.length + ' tools)',
      wheres.length >= 4 && wheres.length === names.length &&
      wheres.every(function (w) { return /a smith forges them|a woodwright makes them/i.test(w); }));
  const toolItem = item('Character', 'The tools come with the pick');
  yes('and the page names every tool the gamemode asks for (' + names.join(', ') + ')',
      names.length >= 4 && names.every(function (n) { return toolItem.indexOf(n) >= 0; }));
  yes('and says a smith forges the next one, a woodwright the next pole, and nothing hands one out',
      /a smith forges the next one/.test(toolItem) && /a woodwright makes the next pole/.test(toolItem) &&
      /nothing in the world hands one out/.test(toolItem) &&
      !/once every \d+ hours|hands you one/.test(toolItem));

  const remind = num(gm, /const CHOOSE_REMIND_MS = (\d+);/) / 1000;
  const later = num(gm, /const CHOOSE_LATER_MS = (\d+);/) / 60000;
  const panel = item('Character', 'If the panel does not appear');
  yes('the panel comes back every ' + remind + ' seconds, and after ' + later + ' minutes once closed, as the page says',
      panel.indexOf('every ' + remind + ' seconds') !== -1 && panel.indexOf(later + ' minutes') !== -1);
  // Said once since #416 (tellOnce, which calls say), so either is the chat.
  yes('and the server only says so in the chat when the panel did not open',
      /if \(!openCreation\(actorId\)\) \{\s*(?:say\(actorId, |tellOnce\(actorId, 'choosing', )'The starting panel did not open/.test(gm) &&
      /only says so in the chat if it could not/.test(panel));
  yes('the town is the pick that ends creation, as the page says',
      /The home is the one pick that ends creation/.test(gm) &&
      /The town is the choice that ends creation/.test(item('Character', 'Where you start')));
}

// --------------------------------------------------------- dying, address
{
  yes('a death sends a person to a temple, as the page says',
      /const PREFER_SLOT = 'temple';/.test(gm) && /temple of the hold you died in/.test(item('In game', 'When you die')));
  // Since #1909 Solstheim wakes at the nearest of its own places in
  // DATA.ownWorlds, the temple or the Retching Netch, and both are in Raven
  // Rock (their rooms are DLC2RR...), so the page's line still holds.
  let ownSol = null;
  try { ownSol = JSON.parse(/^const DATA = (.*);$/m.exec(gm)[1]).ownWorlds['800:Dragonborn.esm']; } catch (e) { ownSol = null; }
  yes('and Solstheim to Raven Rock',
      /const own = ownWorldOf\(site\.desc\);/.test(gm) && Array.isArray(ownSol) && ownSol.length > 0 &&
      ownSol.every(function (p) { return /^DLC2RR/.test(p.cell); }) &&
      /Solstheim sends you to Raven Rock/.test(item('In game', 'When you die')));
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

// ================================================ issue #418, 28 September
/*
  The second rebuild: what somebody needs today to get in, find a key, reach
  staff and send a log, read from the files that decide each of them.
*/
const xaml    = read('launcher', 'ui.xaml');
const discord = read('launcher', 'app', 'Discord.cs');
const verify  = read('launcher', 'app', 'Verify.cs');
const diag    = read('launcher', 'app', 'Diag.cs');
const paths   = read('launcher', 'app', 'Paths.cs');
const site    = read('site', 'server.js');

// ------------------------------------------------------------ getting in
{
  const alpha = item('Joining', 'Thornswood is in alpha');
  yes('the launcher asks https://thornswood.net, and the page names thornswood.net',
      /public const string Site = "https:\/\/thornswood\.net";/.test(discord) &&
      /^thornswood\.net has the installer/.test(item('Joining', 'The site')));
  const playAt = site.indexOf('play:   [');
  const playList = playAt < 0 ? '' : site.slice(playAt, site.indexOf(']', playAt));
  yes('the site lets the Playtester role in, and the page says that role unlocks Play',
      /'Playtester'/.test(playList) && /Playtester role, and that role is what unlocks Play/.test(alpha));
  yes('the page says to apply in a Discord ticket, as the join page does',
      /open a ticket/.test(alpha) &&
      /open a ticket/.test(read('site', 'data', 'site', 'join.md')));
  yes('the site answers "no role that lets it in yet", and the page uses the same words',
      /has no role that lets it in yet/.test(site) &&
      /no role that lets it in yet/.test(item('Joining', 'Connect Discord once')));
}

// ------------------------------------------------------------------ keys
/*
  One item lists every Thornswood key a fresh install has. Each phrase below
  is checked against the template and Keys.cs, the same way the per-item key
  checks above are, so a key that moves fails here too.
*/
{
  const all = item('Keys', 'The keys on a fresh install');
  [
    ['ChatKey', function (k) { return k + ' opens the chat'; }],
    ['CommandKey', function (k) { return k + ' opens it with the slash already typed'; }],
    ['SkillsKey', function (k) { return k + ' is your character panel'; }],
    ['PartyKey', function (k) { return k + ' your friends and party'; }],
    ['JournalKey', function (k) { return k + ' your journals'; }],
    ['FriendKey', function (k) { return k + ' asks them to be friends'; }],
    ['TradeWithKey', function (k) { return k + ' offers a trade'; }],
    ['MuteThemKey', function (k) { return k + ' stops you hearing them'; }],
    ['PushToTalk', function (k) { return 'Hold ' + k + ' to talk'; }],
    ['VoiceLockKey', function (k) { return k + ' keeps the microphone open'; }],
    ['VoiceModeKey', function (k) { return k + ' steps between a whisper'; }],
    ['WheelKey', function (k) { return k + ' opens the emote wheel'; }],
    ['StopKey', function (k) { return k + ' stands you up'; }],
    ['MoldKey', function (k) { return k + ' presses a blank key mold into the lock'; }],
    ['HelpKey', function (k) { return k + ' opens the help in the game'; }]
  ].forEach(function (row) {
    const t = templateKey(row[0]);
    const f = keysFallback(row[0]);
    const letter = LETTER[t !== null ? t : f];
    yes('the key list: ' + row[0] + ' is ' + letter + ' in the template and on the Controls page, and the page says ' +
        JSON.stringify(row[1](letter)),
        !!letter && t !== null && f !== null && t === f && all.indexOf(row[1](letter)) !== -1);
  });
  yes('the Controls page item says keys are changed there', /Press Change/.test(item('Keys', 'The Controls page changes them')));
}

// ----------------------------------------------------------- asking staff
{
  const staff = item('Chat and commands', 'Getting staff: /helpme and /report');
  yes('the gamemode answers /helpme and /report for everybody',
      /if \(word === '\/helpme' \|\| word === '\/help-me' \|\| word === '\/report'\)/.test(gm) &&
      (everybody || []).indexOf('/helpme') !== -1 && (everybody || []).indexOf('/report') !== -1);
  yes('the page names both', /\/helpme\b/.test(staff) && /\/report\b/.test(staff));
  yes('a report goes to staff and nobody else, as the page says',
      /It goes to staff and nobody else\./.test(gm) && /reaches staff and nobody else/.test(staff));
  yes('staff in the world are told and it goes to the staff channel, as the page says',
      /in the staff channel in the Discord/.test(gm) &&
      /staff in the world is told/.test(staff) && /staff channel in the Discord/.test(staff));
  yes('and when it cannot get through the game says to open a ticket, as the page does',
      /Open a ticket in the Discord/.test(gm) && /open a ticket in the Discord/.test(staff));

  // /stuck (#414, #1006): the page says what the stuck block does, with its
  // numbers read out of the block rather than typed here.
  const sa = gm.indexOf('// ==== thornswood stuck ====');
  const sz = sa < 0 ? -1 : gm.indexOf('// ==== end thornswood stuck ====', sa);
  const stuckBlock = (sa >= 0 && sz > sa) ? gm.slice(sa, sz) : '';
  const again = num(stuckBlock, /var AGAIN_MS = (\d+) \* 60 \* 1000;/);
  const wait = num(stuckBlock, /var WAIT_MS = (\d+);/) / 1000;
  const stuckItem = item('Chat and commands', 'Stuck in the world: /stuck');
  yes('the gamemode answers /stuck for everybody, and the page has an item for it',
      /if \(word === '\/stuck'\)/.test(gm) && (everybody || []).indexOf('/stuck') !== -1 && stuckItem.length > 0);
  yes('it says /stuck takes you back a few steps, or to the nearest temple',
      /back a few steps/.test(stuckItem) && /nearest temple/.test(stuckItem));
  yes('once every ' + again + ' minutes and a ' + wait + ' second wait in a fight, as the stuck block has them',
      again > 0 && wait > 0 && stuckItem.indexOf('once every ' + again + ' minutes') !== -1 &&
      stuckItem.indexOf('waits ' + wait + ' seconds') !== -1);
  yes('not while dead, and every use is logged for staff, as the stuck block does',
      /refused outright while you are dead/.test(stuckBlock) && /not while you are dead/.test(stuckItem) &&
      /every use is logged for staff/.test(stuckItem));
}

// -------------------------------------------------------- Scan, Fix, logs
function between(src, from, to) {
  const a = src.indexOf(from);
  const b = a < 0 ? -1 : src.indexOf(to, a);
  return (a >= 0 && b > a) ? src.slice(a, b) : '';
}
{
  const diagPage = between(xaml, '<Grid x:Name="PageDiag"', '<Grid x:Name="PageGallery"');
  const fixItem = item('If it breaks', 'What Scan and Fix do');
  yes('Scan and Fix are buttons on the Diagnostics page, and the page sends people there',
      /x:Name="BtnScan"/.test(diagPage) && /x:Name="BtnFix"/.test(diagPage) &&
      /on the Diagnostics page/.test(fixItem) &&
      /open Diagnostics, press Scan and then Fix/.test(item('If it breaks', '"LOAD ORDER ERROR", or Play is refused')));
  const fix = between(verify, 'public static int Fix(Config cfg, Action<string> say)', '\n        }\n');
  yes('Fix puts the list in the server\'s order, and the page says so',
      /PutInServerOrder\(/.test(fix) && /in the server's order/.test(fixItem));
  yes('Fix moves another server\'s files and Creation Club plugins aside, and the page says so',
      /IsolateForeign\(/.test(fix) && /IsolateCreations\(/.test(fix) &&
      /another server's files and stray Creation Club plugins aside, never deleting them/.test(fixItem));
  yes('Fix puts missing plugins back from Vortex, and the page says so',
      /restoring missing plugins from Vortex/.test(fix) && /puts back plugins Vortex has/.test(fixItem));
  // #1180: the server hands out Thornswood's own plugin and nobody else's.
  yes('Fix fetches the server\'s copy of our own plugin, names the Vortex mod for another author\'s, and the page says so',
      /The server's copy of our own plugin when its bytes are not the/.test(fix) &&
      /if \(!i\.Served\)[\s\S]{0,200}FromVortex\(cfg, i\.Plugin\)/.test(verify) &&
      /downloads the server's copy of Thornswood's own plugin when its bytes differ/.test(fixItem) &&
      /names the mod to update or reinstall in Vortex when another author's plugin differs/.test(fixItem));

  const logs = item('If it breaks', 'Sending your logs');
  yes('Build the report is on the Diagnostics page, and the page names it',
      /x:Name="BtnDiagBundle"[^>]*Content="Build the report"/.test(diagPage) && /Build the report/.test(logs));
  yes('the report carries the launcher log and the script extender log, as the page says',
      /Grab\(work, Paths\.LogFile\)|Paths\.LogFile/.test(diag) && /skse64\.log/.test(diag) &&
      /the launcher log/.test(logs) && /script extender log/.test(logs));
  yes('the launcher log is Profile\\launcher.log, and the page gives that path',
      /LogFile\s*= Path\.Combine\(ProfileDir, "launcher\.log"\);/.test(paths) &&
      logs.indexOf('C:\\Thornswood\\Profile\\launcher.log') !== -1);
  yes('Settings has Open log, as the page says',
      /x:Name="BtnOpenLog"[^>]*Content="Open log"/.test(xaml) && /Settings, Open log/.test(logs));
}

// ----------------------------------------------- pages the rail no longer shows
/*
  Shell.cs hides five pages from the rail (#599). Sending somebody to one of
  them is sending them nowhere, which is what the Logs, Server and Mods
  mentions on this page were doing until 28 September.
*/
{
  const hm = /int\[\] hiddenNav = \{([^}]*)\};/.exec(shell);
  const hidden = hm ? hm[1].split(',').map(function (s) { return s.trim(); }) : [];
  const LABEL = { PageSaves: 'Saves', PageServer: 'Server', PageMods: 'Mods', PageBuild: 'What is installed', PageLogs: 'Logs' };
  yes('Shell.cs hides pages from the rail (' + hidden.join(', ') + ')', hidden.length > 0);
  hidden.forEach(function (p) {
    const label = LABEL[p];
    if (!label) { yes('a hidden page this harness knows the name of: ' + p, false); return; }
    const rx = new RegExp('(the|open|on the) ' + label + ' page\\b|\\b' + label + ', (then )?(Scan|Fix|Your own|Copy newest|Click)|in the launcher[^.]*\\b' + label + ' page', 'i');
    const hit = rx.exec(page);
    yes('the page sends nobody to the ' + label + ' page, which the rail no longer shows' +
        (hit ? ' (says "' + hit[0] + '")' : ''), !hit);
  });
}

// ------------------------------------------------ the site's help agrees
/*
  site/data/help.md is the same help on thornswood.net/help. It told people
  to use the Logs page and that Fix only downloads a plugin; it has to say
  what this page says about getting in, staff, Fix and the logs.
*/
{
  const md = read('site', 'data', 'help.md').replace(/\*\*/g, '');
  yes('help.md says the Playtester role unlocks Play', /Playtester role, and that role is what unlocks Play/.test(md));
  yes('help.md names /helpme and /report', /\/helpme\b/.test(md) && /\/report\b/.test(md));
  yes('help.md sends people to Diagnostics for Scan and Fix', /open Diagnostics in the launcher and press Scan/.test(md));
  yes('help.md says what Fix does, in the same words as the page',
      /puts your plugin list in the server's order/.test(md) &&
      /downloads the server's copy of\s+Thornswood's own plugin when its bytes differ/.test(md) &&
      /names the mod to update or\s+reinstall in Vortex when another author's plugin differs/.test(md));
  yes('help.md says to send the logs with Build the report', /Diagnostics and press\s+Build the report/.test(md));
  const logsPage = /\bLogs page\b|\bServer page\b/.exec(md);
  yes('help.md sends nobody to a page the rail no longer shows' + (logsPage ? ' (says "' + logsPage[0] + '")' : ''), !logsPage);
  const keysMd = /## Keys\n([\s\S]*?)\n## /.exec(md);
  const k = keysMd ? keysMd[1].replace(/\s+/g, ' ') : '';
  yes('help.md lists the same keys: / chat, K, P, J, Y, H, L, V, O, B, G, N, U, F7',
      ['/ opens it with the slash', 'K your character panel', 'P your friends and party', 'J your journals',
       'Y asks them to be friends', 'H offers a trade', 'L stops you hearing them', 'V held to talk',
       'O keeps the microphone open', 'B steps between a whisper', 'G opens the emote wheel',
       'N stands you up', 'U presses a blank key mold',
       'F7 opens the help in the game'].every(function (p) { return k.indexOf(p) !== -1; }));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
