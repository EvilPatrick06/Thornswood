/*
  test-known-page.js

  The known issues page says what the collection actually carries, and names
  every mod on it by its plugin file as well as by its name.

  WHY THIS EXISTS. To Do List entry 280: "Four mods your own documentation
  calls broken are in the live load order right now". By the time anybody came
  to fix it, revision 5 of the collection (22 September) had already taken
  SunHelm Survival, SunHelm Diseases, the Embers XD patch for SunHelm,
  Respawn - Death Overhaul and Tavern Games out, and swapped Immersive Armors
  for the script free version. known.md still listed all of them under "Mods
  that do not work as installed" and said what to do about them was "not
  settled yet". The page was wrong the other way round from the entry's title.

  The entry's own audit was wrong once too, and this is the half worth a
  harness: "Immersive Armors ships as Hothtrooper44_ArmorCompilation.esp,
  which is why searching plugins.txt for the words Immersive Armors found
  nothing and I wrongly called it removed. Record plugin filenames beside
  friendly names on the known issues page so that check cannot go wrong
  again." So every row carries its file, and this checks that it does.

  Where the reference list is on this machine (Profile\Default\plugins.txt,
  which the launcher calls Golden in Paths.cs), every file the page says is
  out has to be absent from both lists and from Game\Data, and every file it
  says is in has to be enabled and present. Measured on 24 September against
  revision 5: none of the five is in plugins.txt, loadorder.txt or Game\Data;
  plugins.txt.rev4.bak still has all five, so the collection is what took them
  out; Game\Data\Hothtrooper44_ArmorCompilation.esp is 1,121,002 bytes, the
  Script Free and Skypatched copy, where the standard 8.1 copy is 1,722,345;
  and AZ_IADistribution.esp is enabled. The next revision that moves any of
  this fails here until the page says so. On the build runner, or any machine
  without the game, that half says SKIP and the page half still runs.

  Read only.
*/
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');

// The page is the known board, written out the way /known writes it (#2414),
// unless KNOWN names a saved copy of the page.
const CR = String.fromCharCode(13);
const text = process.env.KNOWN
  ? fs.readFileSync(process.env.KNOWN, 'utf8').split(CR).join('')
  : (require('./fixtures/known-page').knownPage(REPO_DIR) || '');
const lines = text.split('\n');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// ------------------------------------------------------------ the table
const head = lines.findIndex(function (l) {
  return /^\|\s*Mod\s*\|\s*Plugin file\s*\|\s*Where it stands\s*\|\s*$/.test(l);
});
yes('the page has a table of mods with a plugin file column', head >= 0);

const rows = [];
if (head >= 0) {
  for (let i = head + 2; i < lines.length && lines[i].indexOf('|') === 0; i++) {
    const cells = lines[i].split('|').slice(1, -1).map(function (s) { return s.trim(); });
    rows.push({
      line: i + 1,
      cells: cells.length,
      mod: cells[0] || '',
      files: (cells[1] || '').split(',').map(function (s) { return s.trim(); })
                             .filter(function (s) { return s.length > 0; }),
      stands: cells[2] || ''
    });
  }
}
function isOut(r) { return /^Out\./.test(r.stands); }
function isIn(r) { return /^In[.,]/.test(r.stands); }

yes('and the table has rows', rows.length > 0);
yes('every row has a mod, a file and where it stands',
    rows.length > 0 && rows.every(function (r) { return r.cells === 3; }));
yes('every row names the mod',
    rows.length > 0 && rows.every(function (r) { return r.mod.length > 0; }));
yes('every row names at least one plugin file',
    rows.length > 0 && rows.every(function (r) { return r.files.length > 0; }));
yes('every file named is a plugin file name, not a friendly name',
    rows.length > 0 && rows.every(function (r) {
      return r.files.every(function (f) { return /\.(esp|esm|esl)$/i.test(f); });
    }));
yes('every row says Out or In before anything else',
    rows.length > 0 && rows.every(function (r) { return isOut(r) || isIn(r); }));

function rowFor(file) {
  return rows.filter(function (r) { return r.files.indexOf(file) >= 0; })[0] || null;
}

// Five, not four. The audit's trap: "missing the Embers XD SunHelm patch
// leaves a plugin whose master has gone".
const OUT = [
  'SunHelmSurvival.esp',
  'SunHelmDiseases.esp',
  'Embers XD - Patch - SunHelm Survival.esp',
  'Respawn - Death Overhaul.esp',
  'TavernGames.esp'
];
OUT.forEach(function (f) {
  const r = rowFor(f);
  yes(f + ' is on the page, by its file, as out', r !== null && isOut(r));
});

const ia = rowFor('Hothtrooper44_ArmorCompilation.esp');
yes('Immersive Armors is named by the file a search would actually find',
    ia !== null && /Immersive Armors/.test(ia.mod));
yes('and it is in', ia !== null && isIn(ia));
yes('along with the plugin that hands its armour out without a script',
    ia !== null && ia.files.indexOf('AZ_IADistribution.esp') >= 0);

// Nothing else on the page talks about the removed mods as if they ship.
const OLD = /SunHelm|Tavern ?Games|Respawn - Death/;
const loose = [];
lines.forEach(function (l, i) {
  if (!OLD.test(l)) { return; }
  const r = rows.filter(function (x) { return x.line === i + 1; })[0];
  if (!r || !isOut(r)) { loose.push(i + 1); }
});
yes('the mods that came out are named nowhere else on the page', loose.length === 0);
if (loose.length) { console.log('      Known Issues page lines ' + loose.join(', ')); }
yes('there is no section of mods that do not work as installed',
    !/do not work as installed/i.test(text));
yes('and nothing says what to do about them is not settled yet',
    !/not\s+settled\s+yet/i.test(text));

// ------------------------------------------------ this machine, if it can
const ROOT = process.env.THORNSWOOD_ROOT || 'C:\\Thornswood';
const LIST = path.join(ROOT, 'Profile', 'Default', 'plugins.txt');
const ORDER = path.join(ROOT, 'Profile', 'Default', 'loadorder.txt');
const DATA = path.join(ROOT, 'Game', 'Data');

function names(file) {
  const all = new Set(), enabled = new Set();
  if (!fs.existsSync(file)) { return { all: all, enabled: enabled }; }
  fs.readFileSync(file, 'utf8').split(CR).join('').split('\n').forEach(function (l) {
    let t = l.trim();
    if (!t || t.indexOf('#') === 0) { return; }
    const on = t.indexOf('*') === 0;
    if (on) { t = t.slice(1).trim(); }
    all.add(t.toLowerCase());
    if (on) { enabled.add(t.toLowerCase()); }
  });
  return { all: all, enabled: enabled };
}

if (fs.existsSync(LIST) && fs.existsSync(DATA)) {
  const list = names(LIST);
  const order = names(ORDER);
  const outs = [], ins = [];
  rows.forEach(function (r) {
    r.files.forEach(function (f) { (isOut(r) ? outs : ins).push(f); });
  });

  const listed = outs.filter(function (f) {
    return list.all.has(f.toLowerCase()) || order.all.has(f.toLowerCase());
  });
  yes('every file the page calls out is in neither plugin list', listed.length === 0);
  if (listed.length) { console.log('      still listed: ' + listed.join(', ')); }

  const onDisk = outs.filter(function (f) { return fs.existsSync(path.join(DATA, f)); });
  yes('and none of them is in Game\\Data', onDisk.length === 0);
  if (onDisk.length) { console.log('      still in Game\\Data: ' + onDisk.join(', ')); }

  const off = ins.filter(function (f) { return !list.enabled.has(f.toLowerCase()); });
  yes('every file the page calls in is enabled in the reference list', off.length === 0);
  if (off.length) { console.log('      not enabled: ' + off.join(', ')); }

  const gone = ins.filter(function (f) { return !fs.existsSync(path.join(DATA, f)); });
  yes('and is in Game\\Data', gone.length === 0);
  if (gone.length) { console.log('      missing from Game\\Data: ' + gone.join(', ')); }

  // The standard Immersive Armors 8.1 plugin is 1,722,345 bytes. Anything
  // else in its place is the script free copy the page says ships.
  const iaFile = path.join(DATA, 'Hothtrooper44_ArmorCompilation.esp');
  const iaSize = fs.existsSync(iaFile) ? fs.statSync(iaFile).size : -1;
  yes('the Immersive Armors plugin in Game\\Data is not the standard scripted one',
      iaSize > 0 && iaSize !== 1722345);
  if (!(iaSize > 0 && iaSize !== 1722345)) { console.log('      it is ' + iaSize + ' bytes'); }
} else {
  console.log('SKIP  the reference plugin list is not on this machine: ' + LIST);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
