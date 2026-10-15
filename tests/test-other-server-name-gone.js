// test-other-server-name-gone.js
//
// The name of the SkyMP server Thornswood-Content.esp was salvaged from is in
// no tracked file: not in code, comments, tests, records, data, documents,
// docs\archive, the plugin itself, or any tracked file's path.
//
// WHY THIS EXISTS. Issue #400. Patrick, 12 October, answering the decision on
// the plugin's header description: "B and yes they can just don't mention
// [it] at all", and later the same day, "no records may keep it". The
// salvaged records stay in the plugin; the name goes from everything. On 15
// October it stood in 18 tracked files, the plugin's header among them, and
// they were reworded: "the other server" in prose, OtherServer in file,
// folder and code names, as #497 did for the old multiplayer mod
// (tests\test-old-name-gone.js). Git history is not rewritten.
//
// The name is written here as its code points, so that this file does not
// carry it either and needs no exception for itself. A spelling with one a
// fewer or an extra i (one quote in the archive had that) is caught too.
//
// Every tracked file is read whole. Text is searched in any case. A binary
// file (the plugin, art, video, fonts) is searched as single bytes and as
// UTF-16, because a plugin's header and a record's strings are single byte
// text inside a binary file, which is where the name last lived.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

const c = String.fromCharCode;
// k e i z a, then a, i, both or neither, then l.
const NAME = new RegExp(c(107, 101, 105, 122, 97) + '(?:' + c(97) + '?' + c(105) + '?)' + c(108), 'gi');
// The same four spellings, lower case, for the binary search.
const SPELLINGS = ['', c(97), c(105), c(97, 105)].map(function (mid) { return c(107, 101, 105, 122, 97) + mid + c(108); });

// The pattern itself works: the name and its misspelling, in any case, and
// not a word that only starts the same way.
const probe = c(75, 101, 105, 122, 97, 97, 108);
yes('the pattern finds the name, in any case',
    new RegExp(NAME.source, 'i').test('x ' + probe + ' y') && new RegExp(NAME.source, 'i').test(probe.toUpperCase()));
yes('  and the one misspelling the archive had',
    new RegExp(NAME.source, 'i').test(c(75, 101, 105, 122, 97, 97, 105, 108)));
yes('  and nothing that only starts the same way', !new RegExp(NAME.source, 'i').test('keizer'));

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
let text = 0, binary = 0;
tracked.forEach(function (rel) {
  NAME.lastIndex = 0;
  if (NAME.test(rel)) hits.push(rel + ' (its path)');

  let buf;
  try {
    const st = fs.statSync(path.join(ROOT, rel));
    if (!st.isFile()) return;
    buf = fs.readFileSync(path.join(ROOT, rel));
  } catch (e) { return; }
  let m;
  if (buf.indexOf(0) < 0) {
    text++;
    const s = buf.toString('utf8');
    NAME.lastIndex = 0;
    while ((m = NAME.exec(s)) !== null) hits.push(rel + ':' + lineOf(s, m.index) + '  ' + JSON.stringify(m[0]));
    return;
  }
  binary++;
  // Folded to lower case byte by byte (A to Z only), then searched natively
  // for every spelling, as single bytes and as UTF-16: a string of a large
  // video is slow to build and search with a regular expression.
  const low = Buffer.from(buf);
  for (let i = 0; i < low.length; i++) if (low[i] >= 65 && low[i] <= 90) low[i] += 32;
  SPELLINGS.forEach(function (sp) {
    if (low.indexOf(Buffer.from(sp, 'latin1')) >= 0) hits.push(rel + ' (binary, as bytes)');
    if (low.indexOf(Buffer.from(sp, 'utf16le')) >= 0) hits.push(rel + ' (binary, as UTF-16)');
  });
});

yes('read the tracked text files (' + text + ') and binary files (' + binary + ')', text > 100 && binary > 0);
hits.forEach(function (h) { console.log('      ' + h); });
yes('no tracked file names the server the content plugin was salvaged from (' + hits.length + ' found)', hits.length === 0);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
