// test-one-mint.js
//
// Coin comes into the world in exactly one place. Everything else in the
// server only moves it from one pack to another or takes it away.
//
// Entry 326 on the To Do List is the economy with a bottom: traders who start
// with a purse and buy and sell against it, "so coin moves between people
// rather than appearing". The traders wait on a design Patrick and Djinn have
// not settled. The bottom is already built. Patrick, 21 September, as the
// spoils block in gamemode.js records it: "all weapons, armour, tools, and
// gold are not spawned in the world at all", and "everyone starts with 40
// gold, and we can add a job for gold later but that's just to start." So
// today the one mint is purse() in the spoils block: forty gold, once per
// character, with the mark on the character.
//
// An economy with a floor is only as good as that staying true, and nothing
// checked it. The entry's own check was Select-String for 'f:Skyrim\.esm'.
// Measured on 24 September, that pattern matches 1,099 descriptors on 228
// lines, frost salts (3ad5f:Skyrim.esm) among them, and not one of them is
// gold, because gold is not written as a descriptor anywhere in the file. So
// this reads the file properly instead:
//
//   1. purse() hands over forty once, and still says no after a restart. The
//      entry names the trap: a purse held in a Map "resets to full on every
//      server update, which is a money printer on a schedule".
//   2. Every write into a pack is in a function on the list below, with the
//      reason it cannot make a coin. A new one fails here until somebody has
//      read it and put it on the list.
//   3. No descriptor in the file names Gold001, so addItem, the shift, the
//      deed, the key, the mold and the testers' /give can never hand gold
//      over, and every addItem caller takes its descriptor out of a table.
//   4. A trade moves coin and never makes it: the total is the same after.
//   5. No recipe in the load order makes gold, and the gamemode never asks
//      Papyrus to AddItem.
//
// WHAT THIS CANNOT SEE. A mod that hands out gold on somebody's own machine
// loses the gold, which known.md says for Tavern Games; that is the engine's
// business and not this file's. And a recipe added to the collection after
// game/data/recipes.json was last built is not in it until Build-RecipeTable.ps1
// runs again.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const SRC = process.env.GM || path.join(TOOLS_DIR, '..', 'game', 'gamemode.js');
const RECIPES = process.env.RECIPES || path.join(TOOLS_DIR, '..', 'game', 'data', 'recipes.json');
const CR = String.fromCharCode(13);
const src = fs.readFileSync(SRC, 'utf8').split(CR).join('');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/* A check that throws is a failed check, not a harness that stops halfway. */
function attempt(what, f) {
  try { f(); } catch (e) { yes(what + ' threw: ' + (e && e.message ? e.message : e), false); }
}

function lift(from, to) {
  const a = src.indexOf(from);
  if (a < 0) { return null; }
  const b = src.indexOf(to, a);
  return b < 0 ? null : src.slice(a, b + to.length);
}

/* Gold001. The same number in every load order, which is why the spoils block
   writes it as a number rather than as a descriptor. */
const GOLD = 0x0000000F;

function goldIn(pack) {
  let n = 0;
  const entries = (pack && pack.entries) || [];
  for (let i = 0; i < entries.length; i++) {
    if (entries[i] && entries[i].baseId === GOLD) { n += entries[i].count; }
  }
  return n;
}

/*
  A fake mp over a plain store. mp.get hands back a COPY, the way the real
  server does: it converts the property into a fresh JavaScript value on every
  read. A rig that handed back the stored object would let a function change a
  pack without ever writing it, and pass tests the server would fail.
*/
function fakeMp(store, extra) {
  const mp = {
    makeProperty: function () { },
    get: function (id, key) {
      const row = store[id];
      if (!row) { return undefined; }
      if (row.broken === key) { throw new Error('cannot read ' + key); }
      const v = row[key];
      return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
    },
    set: function (id, key, v) {
      if (!store[id]) { store[id] = {}; }
      store[id][key] = JSON.parse(JSON.stringify(v));
    },
    lookupEspmRecordById: function () { return null; }
  };
  for (const k in (extra || {})) { mp[k] = extra[k]; }
  return mp;
}

// ------------------------------------------------------ reading the file
/*
  TWO COPIES OF THE FILE, EACH THE SAME LENGTH AS IT, so a position in one is
  the same position in the other and the same line.

    code  comments blanked and strings kept, because 'inventory' is a string.
    bare  comments, strings and regular expressions blanked, so every brace
          left is a brace in the code and a function's body can be matched
          from its first brace to its last.

  A reader that lost its place would put a function's end in the wrong place,
  and every answer below would be about the wrong function. So the first check
  is that what is left balances.
*/
function blankOut(s) {
  const n = s.length;
  const code = s.split('');
  const bare = s.split('');
  function wipe(arr, a, b) {
    for (let k = a; k < b && k < n; k++) { if (arr[k] !== '\n') { arr[k] = ' '; } }
  }
  const WORD = /[A-Za-z0-9_$]/;
  const BEFORE_REGEX = '(,=:[!&|?{};+-*%<>~^';
  const KEYWORD = /^(return|typeof|case|in|of|new|delete|void|throw|instanceof|do|else|yield|await)$/;
  let prev = '', word = '';
  let i = 0;
  while (i < n) {
    const c = s[i], d = s[i + 1];
    if (c === '/' && d === '/') {
      let j = s.indexOf('\n', i);
      if (j < 0) { j = n; }
      wipe(code, i, j); wipe(bare, i, j);
      i = j;
      continue;
    }
    if (c === '/' && d === '*') {
      let j = s.indexOf('*/', i + 2);
      j = (j < 0) ? n : j + 2;
      wipe(code, i, j); wipe(bare, i, j);
      i = j;
      continue;
    }
    if (c === '\'' || c === '"' || c === '`') {
      let j = i + 1;
      while (j < n && s[j] !== c) { j += (s[j] === '\\') ? 2 : 1; }
      wipe(bare, i + 1, j);
      i = j + 1; prev = c; word = '';
      continue;
    }
    if (c === '/' && (word ? KEYWORD.test(word)
                           : (prev === '' || BEFORE_REGEX.indexOf(prev) !== -1))) {
      let j = i + 1, inClass = false;
      while (j < n && s[j] !== '\n') {
        if (s[j] === '\\') { j += 2; continue; }
        if (s[j] === '[') { inClass = true; }
        else if (s[j] === ']') { inClass = false; }
        else if (s[j] === '/' && !inClass) { break; }
        j++;
      }
      j++;
      while (j < n && /[a-z]/i.test(s[j])) { j++; }
      wipe(bare, i + 1, j);
      i = j; prev = '/'; word = '';
      continue;
    }
    if (c === ' ' || c === '\n' || c === '\t') { i++; continue; }
    if (WORD.test(c)) {
      let j = i;
      while (j < n && WORD.test(s[j])) { j++; }
      word = s.slice(i, j); prev = s[j - 1]; i = j;
      continue;
    }
    prev = c; word = ''; i++;
  }
  return { code: code.join(''), bare: bare.join('') };
}

const read = blankOut(src);
const code = read.code;
const bare = read.bare;
{
  const count = function (ch) { return bare.split(ch).length - 1; };
  yes('the reader kept its place: braces, brackets and parentheses balance',
      code.length === src.length && bare.length === src.length &&
      count('{') === count('}') && count('(') === count(')') &&
      count('[') === count(']'));
}

const lineStarts = [0];
for (let i = 0; i < src.length; i++) {
  if (src.charCodeAt(i) === 10) { lineStarts.push(i + 1); }
}
function lineOf(p) {
  let lo = 0, hi = lineStarts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (lineStarts[mid] <= p) { lo = mid; } else { hi = mid - 1; }
  }
  return lo + 1;
}

/* Every named function, from its first brace to its last. */
const fns = [];
{
  const re = /\bfunction\s+([A-Za-z_$][\w$]*)\s*\(/g;
  let m;
  while ((m = re.exec(bare)) !== null) {
    let k = m.index + m[0].length - 1, depth = 0;
    for (; k < bare.length; k++) {
      if (bare[k] === '(') { depth++; }
      else if (bare[k] === ')') { depth--; if (depth === 0) { break; } }
    }
    const open = bare.indexOf('{', k);
    let end = -1;
    depth = 0;
    for (let q = open; q >= 0 && q < bare.length; q++) {
      if (bare[q] === '{') { depth++; }
      else if (bare[q] === '}') { depth--; if (depth === 0) { end = q; break; } }
    }
    fns.push({ name: m[1], open: open, end: end });
  }
}

/* Every hand written block between its ==== markers, by its short name. */
const blocks = [];
{
  const re = /^\/\/ ==== thornswood ([a-z ]+?)(?:[:,][^\n]*)? ====$/gm;
  let m;
  while ((m = re.exec(src)) !== null) {
    const endAt = src.indexOf('// ==== end thornswood ' + m[1] + ' ====', m.index);
    blocks.push({ name: m[1], start: m.index, end: endAt < 0 ? src.length : endAt });
  }
}

/* Where a position is: the block, then the innermost named function. */
function where(p) {
  let block = 'outer';
  for (const b of blocks) { if (p >= b.start && p < b.end) { block = b.name; } }
  let fn = null;
  for (const f of fns) {
    if (f.open <= p && p <= f.end && (!fn || f.open > fn.open)) { fn = f; }
  }
  return block + '/' + (fn ? fn.name : '(top)');
}

/* A function's body, out of code by default or out of bare when a check must
   not be fooled by a word inside a string. */
function bodyOf(key, text) {
  for (const f of fns) {
    if (f.end > f.open && where(f.open) === key) { return (text || code).slice(f.open, f.end + 1); }
  }
  return null;
}

// ------------------------------------------------------------ 1. the mint
/*
  purse(), driven out of the real spoils block over a fake mp.

  THE RESTART IS THE CHECK THAT MATTERS. A fresh copy of the block over the
  same store is what the server coming back up looks like, and a deploy of the
  gamemode is the same thing. A purse that remembered who had been paid in a
  Map would pay everybody again every time; the mark on the character is what
  stops it.
*/
const spoils = lift('// ==== thornswood spoils ====', '// ==== end thornswood spoils ====');
yes('the spoils block is in the gamemode', spoils !== null);

function spoilsOver(store) {
  try {
    const fn = new Function(
      'globalThis', 'mp', 'console', 'idOf', 'TOOLS', 'setTimeout',
      spoils + '\nreturn globalThis.__thornswoodSpoils;');
    const api = fn({}, fakeMp(store), { log: function () { } },
                   function () { return 0; }, {}, function () { });
    return (api && typeof api.purse === 'function') ? api : null;
  } catch (e) {
    return null;
  }
}

const packs = {};
const first = spoils !== null ? spoilsOver(packs) : null;
yes('and it hands out a purse', first !== null);
if (first !== null) {
  const A = 0xff000058, B = 0xff000059;
  packs[A] = { inventory: { entries: [] } };

  yes('the purse is forty, the number Patrick gave', first.PURSE === 40);
  yes('a character nobody has paid is handed it', first.purse(A) === true);
  yes('and it is forty gold, as Gold001', goldIn(packs[A].inventory) === 40);
  yes('a second time they are handed nothing',
      first.purse(A) === false && goldIn(packs[A].inventory) === 40);

  const afterRestart = spoilsOver(packs);
  yes('AFTER A RESTART they are still handed nothing, because the mark is on the character',
      afterRestart !== null && afterRestart.purse(A) === false &&
      goldIn(packs[A].inventory) === 40);

  packs[B] = { inventory: { entries: [] }, broken: first.PURSE_PROPERTY };
  yes('when the mark cannot be read, nothing is handed over',
      first.purse(B) === false && goldIn(packs[B].inventory) === 0);
}

// ---------------------------------------------- 2. every write into a pack
/*
  Every mp.set of 'inventory' in the file, by the function it is in, and the
  number of them there. Each is here with the reason it cannot make a coin.

  THIS LIST IS THE CHECK. Measured on 24 September: thirteen functions write a
  pack, fourteen writes between them. A function that is not on it fails until
  somebody has read it and added it with its reason, and one that has stopped
  writing a pack fails too, so that a new function which happens to take its
  name is read rather than waved through.
*/
const WRITERS = {
  'outer/addItem': [1, 'adds by descriptor, and section 3 says no descriptor in this file is gold'],
  'outer/takeItem': [1, 'only takes things away'],
  'outer/takeItemById': [1, 'only takes things away'],
  'outer/giveShift': [1, 'the shift, out of CHARGEN.shift'],
  'outer/giveItems': [1, 'descriptor pairs, and nothing calls it (checked below)'],
  'outer/packAsServerHasIt': [1, 'the take limit sends back the pack the server already holds, so it adds nothing'],
  'property/giveDeed': [1, 'one deed, DEED'],
  'property/giveNamed': [1, 'one named key or mold, KEY or MOLD'],
  'property/takeBlankMold': [1, 'only takes a mold away'],
  'property/nameFreshKey': [1, 'names one key off a stack, and the count is the same after'],
  'property/takeGold': [1, 'takes a notice or job fee out and never puts any in (checked below)'],
  'spoils/strip': [1, 'only takes things out of a container the world stocked'],
  'spoils/purse': [1, 'THE MINT: forty gold, once per character'],
  'trade/moveById': [2, 'moves a pile from one pack to the other, one write each (section 4)']
};

const writes = {};
{
  const re = /\bmp\.set\(\s*[^,()]+,\s*(['"])inventory\1/g;
  let m;
  while ((m = re.exec(code)) !== null) {
    const at = where(m.index);
    (writes[at] = writes[at] || []).push(lineOf(m.index));
  }
}
yes('the writes into a pack were found at all', Object.keys(writes).length >= 10);
for (const at of Object.keys(writes).sort()) {
  const lines = writes[at];
  const known = WRITERS[at];
  if (!known) {
    yes(at + ' writes a pack at line ' + lines.join(', ') + ' and is not on the list. Read it for ' +
        'whether it can put a coin in a pack, then add it to WRITERS with the reason', false);
  } else if (known[0] !== lines.length) {
    yes(at + ' writes a pack ' + lines.length + ' time(s), at line ' + lines.join(', ') +
        ', and the list says ' + known[0] + '. Read the new one', false);
  } else {
    yes(at + ' writes a pack: ' + known[1], true);
  }
}
for (const at of Object.keys(WRITERS)) {
  if (!writes[at]) {
    yes(at + ' is on the list and no longer writes a pack. Take it off', false);
  }
}

{
  // Every 'inventory' in the code is read or written through mp.get or
  // mp.set by name, so no pack is written under a name the list cannot see.
  const re = /(['"])inventory\1/g;
  const loose = [];
  let m;
  while ((m = re.exec(code)) !== null) {
    const before = code.slice(Math.max(0, m.index - 80), m.index);
    if (!/\bmp\.(get|set)\(\s*[^,()]+,\s*$/.test(before)) { loose.push(lineOf(m.index)); }
  }
  yes('every inventory in the code goes through mp.get or mp.set by name' +
      (loose.length ? ', and line ' + loose.join(', ') + ' does not' : ''), loose.length === 0);
}

{
  // Of all the writers, only two name gold: the mint that hands it out and
  // the fee that takes it. A third one naming gold is a second mint until
  // somebody has read it.
  const namesGold = /\b(GOLD|GOLD_ID|goldId)\b|\b0x0*[fF]\b/;
  const naming = [];
  for (const at of Object.keys(WRITERS)) {
    const body = bodyOf(at, bare);
    if (body !== null && namesGold.test(body)) { naming.push(at); }
  }
  naming.sort();
  yes('of the writers, only purse and takeGold name gold' +
      (naming.length ? ' (' + naming.join(', ') + ')' : ''),
      naming.join(',') === 'property/takeGold,spoils/purse');
}

{
  // giveItems adds whatever pairs it is handed, with a sign. Nothing calls it
  // today; the day something does, what it is handed has to be read.
  const calls = (code.match(/\bgiveItems\(/g) || []).length;
  yes('nothing calls giveItems', calls === 1);
}

{
  /*
    takeGold only ever takes. Driven out of the property block: it takes the
    fee from a pack that has it, refuses one that does not, and in neither
    case is there more gold afterwards than before.

    It does not refuse a negative amount, and a negative amount would add.
    Nothing hands it one: its one caller passes a fee that is one of two
    positive constants, which is checked here rather than trusted.
  */
  const take = lift('  function takeGold(actorId, amount) {', '\n  }\n');
  yes('the fee taker is in the gamemode', take !== null);
  if (take !== null) {
    attempt('driving takeGold', function () {
      const A = 0xff000058;
      const store = {};
      store[A] = { inventory: { entries: [{ baseId: GOLD, count: 50 }] } };
      const takeGold = new Function('mp', 'GOLD_ID', take + '\nreturn takeGold;')(fakeMp(store), GOLD);
      yes('a fee comes out of a pack that has it',
          takeGold(A, 20) === true && goldIn(store[A].inventory) === 30);
      yes('the last of it clears the pack of gold',
          takeGold(A, 30) === true && goldIn(store[A].inventory) === 0 &&
          store[A].inventory.entries.length === 0);
      store[A].inventory.entries.push({ baseId: GOLD, count: 10 });
      yes('a fee a pack cannot pay takes nothing',
          takeGold(A, 20) === false && goldIn(store[A].inventory) === 10);
    });
  }
  const callers = [];
  const re = /\btakeGold\(\s*[^,()]+,\s*([^()]+?)\)/g;
  let m;
  while ((m = re.exec(code)) !== null) {
    if (code.slice(Math.max(0, m.index - 9), m.index) === 'function ') { continue; }
    callers.push(m[1].trim());
  }
  const notice = /\bvar NOTICE_FEE = (\d+);/.exec(code);
  const job = /\bvar JOB_FEE = (\d+);/.exec(code);
  yes('its one caller passes the fee, and the fee is NOTICE_FEE or JOB_FEE',
      callers.join(',') === 'fee' &&
      /\bvar fee = isJob \? JOB_FEE : NOTICE_FEE;/.test(code));
  yes('and both fees are more than nothing',
      !!notice && !!job && Number(notice[1]) > 0 && Number(job[1]) > 0);
}

// ------------------------------------- 3. no descriptor in the file is gold
/*
  addItem, giveShift, giveDeed and giveNamed take a descriptor and hand over
  that form. Every descriptor they are ever given is a string in this file:
  the ore, plant, crop, fish, game and hunt tables, the recipe outputs, ITEMS,
  CHARGEN, TOOLS, and the deed, key and mold. So if no string in the file
  names Gold001, none of them can hand gold over.

  PARSED, NOT MATCHED. A descriptor is a hex number, a colon and a plugin.
  Gold is the number fifteen in Skyrim.esm however it is written: f, F, 0f,
  0000000F. Frost salts are 3ad5f and are not gold, which is the difference
  between this and the entry's Select-String.
*/
function goldDescriptors(text) {
  const re = /(["'])([0-9a-f]{1,8}):([^"'\n]+?\.es[mpl])\1/gi;
  const out = { seen: 0, all: new Set(), gold: [] };
  let m;
  while ((m = re.exec(text)) !== null) {
    out.seen++;
    out.all.add(m[2] + ':' + m[3]);
    if (parseInt(m[2], 16) === GOLD && m[3].toLowerCase() === 'skyrim.esm') { out.gold.push(m[0]); }
  }
  return out;
}

{
  const planted = goldDescriptors('a = "f:Skyrim.esm"; b = \'0000000F:skyrim.esm\'; c = "3ad5f:Skyrim.esm";');
  yes('the reader finds gold however it is written, and does not take frost salts for it',
      planted.seen === 3 && planted.gold.length === 2);

  /*
    EXCEPT THE TESTERS' TWO TABLES. Patrick, 27 September: "/give is an
    admin/tester command I should be able /give any item I like". So
    ITEM_NAMES and ADMIN_NAMES, which only /give and /spawn read, name gold
    like any other item. That is a tester's tool behind the playtester gate,
    not a mint anybody playing can reach, and the checks after this one hold
    both halves of that: nothing else reads those tables, and /give stays
    behind the gate. Everything outside them still names no gold.
  */
  function cut(text, start, end) {
    const a = text.indexOf(start);
    const b = a < 0 ? -1 : text.indexOf(end, a);
    return a < 0 || b < 0 ? null : text.slice(0, a) + text.slice(b + end.length);
  }
  const noItems = cut(src, '  // ==== ITEM_NAMES ====', '  // ==== end ITEM_NAMES ====');
  const outside = noItems && cut(noItems, '  // ==== ADMIN_NAMES ====', '  // ==== end ADMIN_NAMES ====');
  yes('the testers\' two tables were found and set aside', !!outside);
  const inside = goldDescriptors(src);
  yes('and they do name gold, so /give gold works for a tester', inside.gold.length > 0);
  const real = goldDescriptors(outside || src);
  yes('it read ' + real.seen + ' descriptors out of the gamemode', real.seen > 10000);
  yes('including the tables that hand things over: the wolf pelt a body gives, corundum ore, ' +
      'a salt pile, the shift and an armour recipe\'s output',
      real.all.has('3ad74:Skyrim.esm') && real.all.has('5acdb:Skyrim.esm') &&
      real.all.has('34cdf:Skyrim.esm') && real.all.has('1be1a:Skyrim.esm') &&
      real.all.has('d62:Hothtrooper44_ArmorCompilation.esp'));
  yes('and outside the testers\' tables not one of them is gold' +
      (real.gold.length ? ': ' + real.gold.slice(0, 5).join(', ') : ''),
      real.gold.length === 0);
  if (outside) {
    const outCode = blankOut(outside).code;
    const refs = function (name) { return (outCode.match(new RegExp('\\b' + name + '\\b', 'g')) || []).length; };
    const build = bodyOf('chat commands/buildThings') || '';
    const beasts = bodyOf('chat commands/buildBeasts') || '';
    yes('ITEM_NAMES and ADMIN_ITEMS are read by the /give index and nothing else',
        refs('ITEM_NAMES') === (build.match(/\bITEM_NAMES\b/g) || []).length &&
        refs('ADMIN_ITEMS') === (build.match(/\bADMIN_ITEMS\b/g) || []).length &&
        refs('ADMIN_ITEMS') > 0);
    yes('ADMIN_ACTORS is read by the /spawn index and nothing else',
        refs('ADMIN_ACTORS') > 0 && refs('ADMIN_ACTORS') === (beasts.match(/\bADMIN_ACTORS\b/g) || []).length);
    yes('and /give and /spawn still refuse anybody who is not a playtester',
        /if \(word === '\/give' \|\| word === '\/spawn'\) \{\s*if \(!isPlaytester\(profileId\)\) \{/.test(src));
  }
}

{
  /*
    Every addItem caller, by what it hands over. Each is a row out of a table
    or a constant in this file, which section 3 has already read. A caller
    handing over something worked out at runtime, a form id turned back into
    a descriptor for instance, could name anything, gold included, so a new
    one fails here until somebody has read where its descriptor comes from.
  */
  const ADD_FROM = {
    'tool.give': 'a starting tool, TOOLS',
    'ITEMS.saltPile': 'a salt pile, ITEMS',
    'rare': 'fire, frost or void salts, ITEMS',
    'seam.ore': 'ore, ORES_BY_BASE',
    'ITEMS.firewood': 'firewood, ITEMS',
    'ITEMS[grade]': 'charcoal, ITEMS',
    'ITEMS.butter': 'butter off the churn, ITEMS',
    'plant.produce': 'a plant, HARVESTS_BY_BASE',
    'caught.produce': 'a fish, FISH_BY_BASE',
    'hung.produce': 'game, GAME_BY_BASE',
    'g.item': 'what a body gives, HUNTS_BY_BASE',
    'crop.produce': 'a crop, CROPS',
    'CROPS[d].produce': 'starting seeds, CROPS',
    'hit.desc': 'the testers\' /give, out of the index built from these same tables'
  };
  const re = /\baddItem\(\s*[^,()]+,\s*([^,]+?),/g;
  const unknown = [];
  let calls = 0;
  let m;
  while ((m = re.exec(code)) !== null) {
    if (code.slice(Math.max(0, m.index - 9), m.index) === 'function ') { continue; }
    calls++;
    const arg = m[1].trim();
    if (!Object.prototype.hasOwnProperty.call(ADD_FROM, arg)) {
      unknown.push(arg + ' at line ' + lineOf(m.index));
    }
  }
  yes('every one of the ' + calls + ' addItem calls hands over a row of a table in this file' +
      (unknown.length ? ', and these do not: ' + unknown.join('; ') : ''),
      calls > 10 && unknown.length === 0);

  // The testers' /give can only hand over what its index holds, and the index
  // is built out of this file's own tables and nothing the engine is asked.
  // Patrick decided on 27 September that /give reaches every item, gold
  // included; section 3 says where that is allowed and holds the gate.
  const build = bodyOf('chat commands/buildThings');
  yes('the /give index is built out of this file\'s tables and never asks the engine for a form',
      build !== null && /ORES_BY_BASE/.test(build) && /RECIPES_BY_ID/.test(build) &&
      !/\bmp\./.test(build));
}

// --------------------------------------------- 4. a trade moves, never makes
/*
  Driven out of the real trade block over a fake mp. The total gold across
  the two packs is the same after a trade as before it, whichever way the
  coin goes, and a trade that can no longer be paid moves nothing.

  A TRADE WITH YOURSELF. moveById reads both packs before it writes either,
  so a pile moved from somebody to themselves is written back with the pile
  added and nothing taken away. Measured on 24 September: moveById(A, A) with
  forty gold turned a pack of 100 into 140, and begin(A, A) opens a trade.
  Two things stop that ever reaching a pack, and both are checked here: the
  command refuses to offer a trade to yourself ("That is you."), and a trade
  whose two sides are the same person can never have both sides agreed,
  because the second agreement lands on the first side.
*/
const tradeBlock = lift('// ==== thornswood trade ====', '// ==== end thornswood trade ====');
yes('the trade block is in the gamemode', tradeBlock !== null);

function tradeWorld() {
  const store = {};
  const g = {};
  const mp = fakeMp(store, {
    lookupEspmRecordById: function (baseId) {
      const name = baseId === GOLD ? 'Gold' : 'Leek';
      return { record: { type: 'MISC', editorId: name, fields: [{ type: 'FULL', data: name }] } };
    }
  });
  new Function(
    'globalThis', 'mp', 'console', 'setInterval', 'clearInterval', 'guard', 'say', 'notify',
    tradeBlock)(
    g, mp, { log: function () { } }, function () { return 1; }, function () { },
    function (n, f) { return f; }, function () { }, function () { });
  return {
    trade: g.__thornswoodTrade,
    store: store,
    person: function (id, pack) {
      store[id] = { worldOrCellDesc: 'town:X.esm', pos: [0, 0, 0], inventory: { entries: pack } };
      return id;
    },
    gold: function (id) { return goldIn(store[id].inventory); }
  };
}

const LEEK = 0x901;
if (tradeBlock !== null) {
  attempt('a trade both ways', function () {
    const w = tradeWorld();
    const A = w.person(0xff000001, [{ baseId: GOLD, count: 100 }]);
    const B = w.person(0xff000002, [{ baseId: GOLD, count: 5 }, { baseId: LEEK, count: 3 }]);
    w.trade.begin(A, B);
    w.trade.gold(A, 40);
    w.trade.gold(B, 5);
    w.trade.add(B, 'Leek', 3);
    w.trade.confirm(A);
    w.trade.confirm(B);
    yes('coin going both ways in one trade lands where it was sent',
        w.gold(A) === 65 && w.gold(B) === 40);
    yes('and there is exactly as much gold after the trade as before it',
        w.gold(A) + w.gold(B) === 105);
  });
  attempt('a trade that can no longer be paid', function () {
    const w = tradeWorld();
    const A = w.person(0xff000001, [{ baseId: GOLD, count: 100 }]);
    const B = w.person(0xff000002, [{ baseId: LEEK, count: 1 }]);
    w.trade.begin(A, B);
    w.trade.gold(A, 40);
    w.trade.add(B, 'Leek', 1);
    w.trade.confirm(A);
    w.store[A].inventory = { entries: [{ baseId: GOLD, count: 10 }] };   // spent it meanwhile
    w.trade.confirm(B);
    yes('coin that is gone by the time both agree moves nothing at all',
        w.gold(A) === 10 && w.gold(B) === 0);
  });
  attempt('moving a pile', function () {
    const w = tradeWorld();
    const A = w.person(0xff000001, [{ baseId: GOLD, count: 30 }, { baseId: GOLD, count: 30 }]);
    const B = w.person(0xff000002, []);
    yes('a pile taken across two stacks arrives whole and the total holds',
        w.trade.moveById(A, B, [[GOLD, 50]]) === true &&
        w.gold(A) === 10 && w.gold(B) === 50);
    yes('and a pile bigger than the pack is refused with nothing written',
        w.trade.moveById(A, B, [[GOLD, 500]]) === false &&
        w.gold(A) === 10 && w.gold(B) === 50);
  });
  attempt('a trade with yourself', function () {
    const w = tradeWorld();
    const A = w.person(0xff000001, [{ baseId: GOLD, count: 100 }]);
    // Refusing it outright would be better still, and passes too. What may
    // never happen is that it opens and then swaps, which closes it.
    const opened = w.trade.begin(A, A) === '';
    if (opened) {
      w.trade.gold(A, 40);
      w.trade.confirm(A);
      w.trade.confirm(A);
    }
    yes('a trade with yourself can never have both sides agreed, so nothing moves',
        w.gold(A) === 100 && (!opened || !!w.trade.tradeOf(A)));
  });
}
{
  const guard = code.indexOf('if (them === actorId) { toProfile(profileId, \'That is you.\'); return true; }');
  const offer = code.indexOf('var refused = soc.offer(kind, actorId, them);');
  yes('and nobody can offer a trade to themselves in the first place',
      guard !== -1 && offer !== -1 && guard < offer);
}

// ---------------------------------------------- 5. and nothing else makes it
{
  /*
    CRAFTING IS THE ENGINE'S, AND IT IS THE ONE WAY IN THIS FILE CANNOT SEE.
    A recipe hands over its output without the gamemode writing anything, and
    a recipe nobody owns may be made by anybody. game/data/recipes.json is every
    COBJ record in the load order, so a recipe that made gold would be a mint
    open to everybody. None does. Twenty one take gold as an input, measured
    on 24 September, Immersive Armors and Immersive Weapons, and that is coin
    leaving the world rather than coin coming into it.
  */
  let book = null;
  try { book = JSON.parse(fs.readFileSync(RECIPES, 'utf8')); } catch (e) { book = null; }
  yes('game/data/recipes.json is there to read', book !== null);
  if (book !== null) {
    let rows = 0;
    const makes = [];
    for (const part of ['recipes', 'unowned', 'refused']) {
      const table = book[part] || {};
      for (const k of Object.keys(table)) {
        rows++;
        const out = String((table[k] && table[k].out) || '');
        const hit = /^([0-9a-f]{1,8}):(.+)$/i.exec(out);
        if (hit && parseInt(hit[1], 16) === GOLD && hit[2].toLowerCase() === 'skyrim.esm') {
          makes.push(k + ' ' + (table[k].editorId || ''));
        }
      }
    }
    yes('it holds every recipe in the load order, ' + rows + ' of them', rows > 4000);
    yes('and not one of them makes gold' + (makes.length ? ': ' + makes.slice(0, 5).join(', ') : ''),
        makes.length === 0);
  }
}

yes('the gamemode never asks Papyrus to AddItem', !/(['"])AddItem\1/.test(code));

{
  const spoil = bodyOf('spoils/isSpoil');
  yes('and the world does not hand gold over: it is the first thing isSpoil refuses',
      spoil !== null && /if \(baseId === GOLD\) \{ return true; \}/.test(spoil));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
