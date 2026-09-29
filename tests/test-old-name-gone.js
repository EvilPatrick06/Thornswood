// test-old-name-gone.js
//
// The name of the multiplayer mod this build replaced, and the names of its
// add-ons, are nowhere in the repository: not in code, fallbacks, launcher
// checks, installer steps, zip or folder names, settings, docs, site pages,
// bot text, tests or CI, and not in any tracked file's path.
//
// WHY THIS EXISTS. Issue #497. Patrick, 28 Sep, asked for all of the old
// mod's things out that night: "we were supposed to have finished this
// awhile ago."
// Before that night the old name sat in about seventy files, most of them
// fallbacks for installs and folders that stopped existing weeks earlier, and
// each clean up found more because nothing failed when one came back.
//
// The one place it may stay is the update path. A launcher installed before
// the rename still runs under the old exe file name, and an update is what
// renames it to Thornswood.exe and repoints its shortcuts
// (launcher\app\SelfSwap.cs, driven by tests\test-self-update.ps1). So in
// those two files, and only there, the old exe file name itself (the name
// followed by ".exe") is allowed. Nothing else is, in them or anywhere.
//
// Not the old mod: "tilted" is SkyrimPlatform's own browser backend, a value
// SkyrimPlatform.ini takes, and TiltedUI, TiltedCore, TiltedHooks and
// TiltedReverse are libraries compiled into the SkyMP fork whose notice
// THIRD-PARTY.md must carry by their own terms. Those are SkyMP's, and stay.
//
// Every tracked text file is read whole, so a name split over a line break
// ("Skyrim" at the end of one comment line, "Together" at the start of the
// next) is caught too.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(TOOLS_DIR, '..');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// Each written so that its own source text does not match it, so this file
// needs no exception for itself.
// Between the words of a name: nothing, a space, a hyphen or underscore, a
// path separator, or a line break with a comment marker (//, #, ;, *).
const SEP = '[\\s\\-_.\\/\\\\#;*]*';
function words() {
  return new RegExp(Array.prototype.slice.call(arguments).join(SEP), 'gi');
}
const NAMES = [
  // The mod, in any spelling: two words, one word, hyphenated, or split over
  // a comment line.
  words('skyrim', 'together'),
  // The same run together with a leading s, as a short form.
  /(?<![a-z])s(?:together)/gi,
  // Its source repository and its company's projects.
  words('tilted', '(?:evolution|online)'),
  // Its add-ons: the trade menu, the body sync and the messaging plugin.
  words('trade', 'together'),
  words('morph', 'sync', 'together'),
  words('\\bSTR', 'plugin', 'messaging'),
  // Its server's name, and the folder the SkyMP switch parked its files in.
  /\bST(?:Server)\b/g,
  /_removed(?:ST)\b/g,
  // Its initials where they named our own things: the installer's payload
  // marker and the launcher's temporary update files, until 28 September.
  /\bST(?:SFX)/g,
  /(?<![\w-])st-(?:update-)/gi,
  /"s(?:t)-"/g,
];

// The update path, and nothing else. Only the exe file name is allowed there.
const UPDATE_PATH = ['launcher/app/SelfSwap.cs', 'tests/test-self-update.ps1'];
function allowed(rel, text, at, hit) {
  if (UPDATE_PATH.indexOf(rel) < 0) return false;
  if (!/^skyrim(?:together)$/i.test(hit)) return false;
  return text.substr(at + hit.length, 4).toLowerCase() === '.exe';
}

let tracked = [];
try {
  tracked = execFileSync('git', ['ls-files', '-z'], { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })
    .split('\0').filter(Boolean);
} catch (e) {
  console.log('git ls-files failed: ' + e.message);
}
yes('git lists the tracked files (' + tracked.length + ')', tracked.length > 100);

function lineOf(text, at) {
  let n = 1;
  for (let i = 0; i < at; i++) if (text.charCodeAt(i) === 10) n++;
  return n;
}

const hits = [];
let read = 0, allowedCount = 0;
const allowedIn = {};
tracked.forEach(function (rel) {
  NAMES.forEach(function (rx) {
    rx.lastIndex = 0;
    const m = rx.exec(rel);
    if (m) hits.push(rel + ' (its path: ' + m[0] + ')');
  });

  const full = path.join(ROOT, rel);
  let buf;
  try {
    const st = fs.statSync(full);
    if (!st.isFile() || st.size > 32 * 1024 * 1024) return;
    buf = fs.readFileSync(full);
  } catch (e) { return; }
  // Binary files (art, video, fonts) carry no words.
  if (buf.indexOf(0) >= 0) return;
  read++;
  const text = buf.toString('utf8');
  NAMES.forEach(function (rx) {
    rx.lastIndex = 0;
    let m;
    while ((m = rx.exec(text)) !== null) {
      if (allowed(rel, text, m.index, m[0])) { allowedCount++; allowedIn[rel] = true; continue; }
      hits.push(rel + ':' + lineOf(text, m.index) + '  ' + JSON.stringify(m[0]));
    }
  });
});

yes('read the tracked text files (' + read + ')', read > 100);
// --all lists every one; otherwise the first 200, which is plenty to start on.
const show = process.argv.indexOf('--all') >= 0 ? hits.length : 200;
hits.slice(0, show).forEach(function (h) { console.log('      ' + h); });
if (hits.length > show) console.log('      ... and ' + (hits.length - show) + ' more (--all lists them)');
yes('no tracked file names the old multiplayer mod or its add-ons (' + hits.length + ' found)', hits.length === 0);

// The exception stays honest: it is the update path, so the file that renames
// an old install has to be there and has to be where the old exe name lives.
const swap = (function () { try { return fs.readFileSync(path.join(ROOT, 'launcher/app/SelfSwap.cs'), 'utf8'); } catch (e) { return ''; } })();
yes('SelfSwap.cs still renames an install that runs under the old exe name, which is why it is allowed there',
    /public const string OldName = "[A-Za-z]+\.exe";/.test(swap) && /public static string Target\(string exe\)/.test(swap));
yes('the old exe name is allowed in ' + Object.keys(allowedIn).length + ' file(s), both on the update path (' + allowedCount + ' uses)',
    Object.keys(allowedIn).every(function (r) { return UPDATE_PATH.indexOf(r) >= 0; }));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
