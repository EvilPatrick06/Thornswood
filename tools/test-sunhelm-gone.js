// test-sunhelm-gone.js
//
// Nothing a customer reads still sends them to a mod that has left the
// collection, and what the launcher says about the needs is what the server
// actually does.
//
// WHY THIS EXISTS. To Do List entry 133. Settled by Patrick on 17 September,
// in the entry's words: the mod does not matter, the three needs do. So
// SunHelm Survival and SunHelm Diseases came out, and hunger, thirst, rest and
// temperature were built on the server instead. Respawn - Death Overhaul and
// Tavern Games came out in the same release, and Immersive Armors became its
// script free build.
//
// The removal was done and the server half was live, and the words were not.
// On 24 September the launcher's Help page still said "The needs display is
// configurable in the SunHelm MCM" and promised that "a bedroll or a hot
// drink" warms you, which nothing on the server counts. The Controls page
// said "SunHelm and the older mods live here". known.md listed all five mods
// as "in the collection". Add-CartTravel.ps1 said fast travel was switched off
// by SunHelm, when it is the SkyMP client that does it. Every one of those
// sends somebody looking for a thing that is not there.
//
// So this reads the text people read and checks it two ways: it names no mod
// that has gone as though it were still here, and where it describes the
// needs, everything it promises is something gamemode.js does. On a machine
// with the game built it also checks the entry's doneWhen: no SunHelm in the
// reference plugin list, the game folder or the client's load order, and the
// script free Immersive Armors in its place. On a runner with no game folder
// those say SKIP.
//
// Read only.
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);
const BS = String.fromCharCode(92);

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function skip(what) { console.log('SKIP  ' + what); }

function read(parts) {
  return fs.readFileSync(path.join.apply(path, [__dirname].concat(parts)), 'utf8').split(CR).join('');
}

// The mods that left. Matched loosely, because people write them with and
// without the space.
const GONE = [
  { name: 'SunHelm', re: /sun\s*helm/i },
  { name: 'Respawn - Death Overhaul', re: /respawn\s*-\s*death\s*overhaul/i },
  { name: 'Tavern Games', re: /tavern\s*games/i }
];
function goneIn(text) {
  const hit = [];
  GONE.forEach(function (g) { if (g.re.test(text)) { hit.push(g.name); } });
  return hit;
}

/*
  Every string literal in a C# file, and nothing from its comments. The
  comments over the changed lines say SunHelm on purpose, to say why they
  changed, and a customer never reads a comment.
*/
function csStrings(src) {
  const out = [];
  const n = src.length;
  let i = 0;
  while (i < n) {
    const c = src[i], d = src[i + 1];
    if (c === '/' && d === '/') { const e = src.indexOf('\n', i); i = e < 0 ? n : e; continue; }
    if (c === '/' && d === '*') { const e = src.indexOf('*/', i + 2); i = e < 0 ? n : e + 2; continue; }
    if (c === '@' && d === '"') {
      let j = i + 2, s = '';
      while (j < n) {
        if (src[j] === '"' && src[j + 1] === '"') { s += '"'; j += 2; continue; }
        if (src[j] === '"') { break; }
        s += src[j]; j++;
      }
      out.push(s); i = j + 1; continue;
    }
    if (c === '"') {
      let j = i + 1, s = '';
      while (j < n && src[j] !== '"' && src[j] !== '\n') {
        if (src[j] === BS) { s += src[j] + src[j + 1]; j += 2; continue; }
        s += src[j]; j++;
      }
      out.push(s); i = j + 1; continue;
    }
    if (c === "'") {
      // A char literal, so that '"' never opens a string.
      let j = i + 1;
      j += (src[j] === BS) ? 2 : 1;
      if (src[j] === "'") { i = j + 1; continue; }
      i++; continue;
    }
    i++;
  }
  return out;
}

// ---------------------------------------------------------- the gamemode
const GM = read(['gamemode.js']);
const nA = GM.indexOf('// ==== thornswood needs');
const nB = GM.indexOf('// ==== end thornswood needs ====');
const needs = (nA >= 0 && nB > nA) ? GM.slice(nA, nB) : '';
yes('the needs block is in the gamemode', needs.length > 1000);

const hA = GM.indexOf('function hudScript()');
const hud = hA >= 0 ? GM.slice(hA, hA + 12000) : '';
yes('the HUD script is in the gamemode', hud.length > 0);

const pA = GM.indexOf('const PLAYER_WORDS = [');
const pB = pA >= 0 ? GM.indexOf('];', pA) : -1;
const playerWords = (pA >= 0 && pB > pA) ? GM.slice(pA, pB) : '';
yes('PLAYER_WORDS is in the gamemode', playerWords.length > 0);

// ---------------------------------------------------------- the Help page
const helpStrings = csStrings(read(['app', 'Help.cs']));
yes('the Help page has text to read, ' + helpStrings.length + ' strings', helpStrings.length > 50);
const helpGone = [];
helpStrings.forEach(function (s) {
  goneIn(s).forEach(function (g) { helpGone.push(g + ' in "' + s.slice(0, 60) + '"'); });
});
yes('the Help page names no mod that has left' + (helpGone.length ? ': ' + helpGone.join('; ') : ''),
    helpGone.length === 0);

const TITLE = 'You will get hungry, thirsty and cold';
const tAt = helpStrings.indexOf(TITLE);
const body = tAt >= 0 ? (helpStrings[tAt + 1] || '') : '';
yes('the needs item is on the Help page', body.length > 0);
yes('it sends nobody to an MCM, which went with SunHelm', !/\bMCM\b/.test(body));

// Where the needs are shown, checked against the thing that draws them.
yes('it names /needs', body.indexOf('/needs') >= 0);
yes('and /needs is a command the gamemode answers', GM.indexOf("if (word === '/needs')") >= 0);
yes('and one everybody is told about, not only a playtester', playerWords.indexOf("'/needs'") >= 0);

yes('it says the bars are bottom left', /bottom left/i.test(body));
yes('and the HUD is anchored bottom left',
    /position:fixed;left:\d+px;bottom:\d+px/.test(hud));
[['food', 'Hunger'], ['drink', 'Thirst'], ['rest', 'Rest'], ['temp', 'Temp']].forEach(function (k) {
  yes('it names the ' + k[1] + ' bar, and the HUD draws one by that name',
      body.indexOf(k[1]) >= 0 && hud.indexOf('row("' + k[0] + '", "' + k[1] + '"') >= 0);
});

/*
  What warms you. Every source the item promises has to be one the needs
  block counts, and the ones SunHelm had and the server does not must not be
  promised. That is the half of the old text that was wrong without naming
  SunHelm at all.
*/
const lowBody = body.toLowerCase();
const lowNeeds = needs.toLowerCase();
['bedroll', 'hot drink', 'hot food', 'hot meal'].forEach(function (w) {
  yes('it promises no ' + w + ' unless the needs block counts one',
      lowBody.indexOf(w) < 0 || lowNeeds.indexOf(w) >= 0);
});
yes('it says a fire warms you, and the needs block has a fire',
    /fire warms you/i.test(body) && /\bfire:\s*\{\s*at:/.test(needs));
yes('it says standing in one burns you, and the needs block has a burn',
    /burns you/i.test(body) && /\bburn:\s*\{\s*spread:/.test(needs));
yes('it says a roof keeps the weather off, and the needs block reads a roof',
    /roof/i.test(body) && /\broof\b/.test(needs));

const mat = /material:\s*\{([^}]*)\}/.exec(needs);
const worth = {};
if (mat) {
  mat[1].replace(/(\w+):\s*([\d.]+)/g, function (all, k, v) { worth[k] = Number(v); return all; });
}
const kinds = Object.keys(worth).filter(function (k) { return k !== 'none'; });
const best = kinds.slice().sort(function (a, b) { return worth[b] - worth[a]; })[0];
const worst = kinds.slice().sort(function (a, b) { return worth[a] - worth[b]; })[0];
yes('the needs block says what each material is worth, ' + kinds.length + ' of them', kinds.length >= 4);
yes('it says fur is the warmest, and fur is the best material there (' + best + ')',
    /fur is the warmest/i.test(body) && best === 'fur');
yes('it says metal is the worst, and heavy armour is the worst material there (' + worst + ')',
    /metal the worst|metal is the worst/i.test(body) && worst === 'heavy');

// ------------------------------------------------------ the Controls page
const pagesStrings = csStrings(read(['app', 'Pages.cs']));
yes('the Controls page has text to read, ' + pagesStrings.length + ' strings', pagesStrings.length > 20);
const pagesGone = [];
pagesStrings.forEach(function (s) {
  goneIn(s).forEach(function (g) { pagesGone.push(g + ' in "' + s.slice(0, 60) + '"'); });
});
yes('the Controls page names no mod that has left' + (pagesGone.length ? ': ' + pagesGone.join('; ') : ''),
    pagesGone.length === 0);

const mAt = pagesStrings.indexOf('Esc,  Mod Configuration');
const mcmRow = mAt >= 0 ? (pagesStrings[mAt + 1] || '') : '';
yes('the Mod Configuration row is on the Controls page', mcmRow.length > 0);

// The MCM page each example stands for, as a script in the build.
const MCM_PAGES = { 'QuickLoot': 'QuickLootIEMCM.pex', 'Skyrim Unbound': 'SkyrimUnboundMCMScript.pex' };
const named = Object.keys(MCM_PAGES).filter(function (k) { return mcmRow.indexOf(k) >= 0; });
yes('the row gives an example of a mod whose page is there', named.length > 0);

const KNOWN = read(['docs-app', 'data', 'known.md']);
yes('the row does not say the choices are kept in your save, when known.md says menus reset',
    !(/reset every session/i.test(KNOWN) && /kept in your save/i.test(mcmRow)));

// ------------------------------------------------------------- known.md
/*
  A section may name a mod that has gone only if its heading says it was
  taken out. The old heading was "Mods that do not work as installed" and it
  opened with "These are in the collection".
*/
const sections = KNOWN.split(/\n(?=## )/);
const misplaced = [];
let takenOut = '';
sections.forEach(function (sec) {
  const head = sec.split('\n')[0];
  const names = goneIn(sec);
  if (/Immersive Armors, standard/i.test(sec)) { names.push('Immersive Armors, standard version'); }
  if (/taken out/i.test(head)) { takenOut = sec; return; }
  names.forEach(function (nm) { misplaced.push(nm + ' under "' + head + '"'); });
});
yes('known.md names a mod that has gone only under a heading that says it was taken out' +
    (misplaced.length ? ': ' + misplaced.join('; ') : ''), misplaced.length === 0);
yes('known.md has that section', takenOut.length > 0);
yes('and it does not say those mods are in the collection', !/are in the collection/i.test(takenOut));
yes('and it says where the needs went: the server, the bars and /needs',
    /on the server/i.test(takenOut) && /bottom left/i.test(takenOut) && takenOut.indexOf('/needs') >= 0);

// ------------------------------------------------------- Add-CartTravel.ps1
const CART = read(['Add-CartTravel.ps1']);
const says = [];
CART.split('\n').forEach(function (line) {
  const m = /^\s*Say\s+'((?:[^']|'')*)'/.exec(line) || /^\s*Say\s+"([^"]*)"/.exec(line);
  if (m) { says.push(m[1]); }
});
yes('Add-CartTravel.ps1 has lines it prints, ' + says.length + ' of them', says.length > 5);
const cartGone = says.filter(function (s) { return goneIn(s).length > 0; });
yes('none of them names a mod that has left' + (cartGone.length ? ': ' + cartGone.join(' | ') : ''),
    cartGone.length === 0);
yes('and the fast travel line says the SkyMP client turns it off',
    says.some(function (s) { return /fast travel/i.test(s) && /SkyMP client/i.test(s); }));

// ------------------------------------------------------- this machine
const ROOT = process.env.TS_ROOT || ('C:' + BS + 'Thornswood');
const PLUGINS = path.join(ROOT, 'Profile', 'Default', 'plugins.txt');
const DATA = path.join(ROOT, 'Game', 'Data');
const ORDER = path.join(DATA, 'Platform', 'thornswood-loadorder.txt');
const CLIENT = path.join(DATA, 'Platform', 'Plugins', 'skymp5-client.js');
const SCRIPTS = path.join(DATA, 'Scripts');
const IA = 'Hothtrooper44_ArmorCompilation.esp';
const GONE_FILES = /sun\s*helm|respawn - death overhaul|taverngames/i;

if (fs.existsSync(PLUGINS)) {
  const lines = fs.readFileSync(PLUGINS, 'utf8').split(/\r?\n/);
  const left = lines.filter(function (l) { return GONE_FILES.test(l); });
  yes('the reference plugin list carries none of the mods that left' + (left.length ? ': ' + left.join(', ') : ''),
      left.length === 0);
  yes('and it has the script free Immersive Armors, ' + IA, lines.indexOf('*' + IA) >= 0);
} else {
  skip('no reference plugin list at ' + PLUGINS);
}

if (fs.existsSync(DATA)) {
  const there = fs.readdirSync(DATA).filter(function (f) { return /sun\s*helm/i.test(f); });
  yes('the game folder has no SunHelm file' + (there.length ? ': ' + there.join(', ') : ''), there.length === 0);
  const esp = path.join(DATA, IA);
  if (fs.existsSync(esp)) {
    // The scripted build hands armour out through quests. Measured 24
    // September: the one in the game folder has no QUST record at all.
    yes('the Immersive Armors plugin carries no quest record, so it is the script free build',
        fs.readFileSync(esp).indexOf('QUST', 0, 'latin1') < 0);
  } else {
    skip('no ' + IA + ' in ' + DATA);
  }
} else {
  skip('no game folder at ' + DATA);
}

if (fs.existsSync(ORDER)) {
  const order = fs.readFileSync(ORDER, 'utf8');
  yes('the client load order names no SunHelm plugin', !/sun\s*helm/i.test(order));
  yes('and names the script free Immersive Armors', order.indexOf(IA) >= 0);
} else {
  skip('no client load order at ' + ORDER);
}

if (fs.existsSync(CLIENT)) {
  yes('the SkyMP client in the game folder turns fast travel off itself',
      fs.readFileSync(CLIENT, 'utf8').indexOf('enableFastTravel(false)') >= 0);
} else {
  skip('no skymp5-client.js at ' + CLIENT);
}

if (fs.existsSync(SCRIPTS)) {
  named.forEach(function (k) {
    yes('the page the Controls row names for ' + k + ' is in the build, ' + MCM_PAGES[k],
        fs.existsSync(path.join(SCRIPTS, MCM_PAGES[k])));
  });
} else {
  skip('no Scripts folder at ' + SCRIPTS);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
