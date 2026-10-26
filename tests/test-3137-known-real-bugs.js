// test-3137-known-real-bugs.js
//
//     node tests/test-3137-known-real-bugs.js
//
// The Known Issues page lists only what is actually broken, every row of it is
// an issue on the board, and what works the way it does on purpose is on the
// Help page instead.
//
// Issue #3137, Patrick: "we need to add any of the known issues ion the discor
// or the website to the issues boards and get them fixed aswell as remove
// things that arent know issues like things that we removed how things work
// that we did on purpose etc and only put things that are actually
// broken/issues".
//
// WHAT WAS MEASURED ON 26 OCTOBER. The live page (/api/page/known) was the
// repo's known board but for one sentence #2703 had not deployed. It had
// fourteen rows and three prose sections. Read against the board and the code:
//   - real and on the board: mod scripts never fire (#503), killmoves (#2710);
//   - real with no open issue: the menus that still reset (#488 closed with
//     them left, now #3435); the tester note's instruments (#3434) and typing
//     in another window (#3436) were not on the page or the board at all;
//   - fixed: NPC behaviour differing near the same enemy (#504 closed, the
//     server runs the NPCs);
//   - no longer true: fishing "no rod needed" (the server asks for a pole);
//   - on purpose: the mods the collection took out, what the server owns, the
//     bare creation hall, leaving with no class, an old launcher, the load
//     order rule. Those went to help.md's Things that are normal here, or were
//     already there.
// The old harnesses for the sections that came off (test-known-npcs.js for the
// NPC section, test-known-page.js for the table of removed mods) went with
// them, since what they checked is no longer on the page by decision.
//
// A row records its issue as "issue" beside its cells. The page does not show
// it (testers have no GitHub); it is how anybody reading the board finds the
// fix, and what #3140 builds on.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const { knownPage } = require('./fixtures/known-page');

const ROOT = path.join(__dirname, '..');
let pass = 0, fail = 0;
function yes(what, cond) { if (cond) { pass++; console.log('PASS  ' + what); } else { fail++; console.log('FAIL  ' + what); } }
function read(rel) { try { return fs.readFileSync(path.join(ROOT, rel), 'utf8').replace(/\r\n/g, '\n'); } catch (e) { return null; } }

const board = JSON.parse(read('site/data/board.json') || '{}');
const known = board.known || {};
const page = knownPage() || '';
const help = read('site/data/help.md') || '';
const content = read('bot/content.py') || '';

// The rows a reader sees: not ticked done in the hub.
function shown(b) {
  const out = [];
  ((b && b.sections) || []).forEach(function (s) {
    ((s && s.rows) || []).forEach(function (r) { if (r && !r.done) { out.push({ section: s, row: r }); } });
  });
  return out;
}
// What is wrong with a board: rows with no issue, an issue twice, a section of
// prose alone (a section with nothing broken in it is explanation, which
// belongs on Help).
function problems(b) {
  const bad = [];
  const seen = {};
  shown(b).forEach(function (x) {
    const n = x.row.issue;
    const first = String(((x.row.cells || {})[(((x.section.columns || [])[0]) || {}).id]) || '').trim();
    if (!(Number.isInteger(n) && n > 0)) { bad.push('no issue: ' + (first || x.row.id)); return; }
    if (seen[n]) { bad.push('issue #' + n + ' twice'); }
    seen[n] = true;
    if (!first) { bad.push('#' + n + ' has no words'); }
  });
  ((b && b.sections) || []).forEach(function (s) {
    if (String(s.note || '').trim() && !shown({ sections: [s] }).length) { bad.push('prose only: ' + s.name); }
  });
  return bad;
}

// 1. Every row on the page is an issue on the board.
const rows = shown(known);
yes('the known board has rows, ' + rows.length + ' of them', rows.length >= 3);
const bad = problems(known);
if (bad.length) { console.log('      ' + bad.join('; ')); }
yes('every row names its board issue, each once, and no section is prose alone', bad.length === 0);
yes('the issues behind it include the five measured on 26 Oct',
    [503, 2710, 3434, 3435, 3436].every(function (n) { return rows.some(function (x) { return x.row.issue === n; }); }));
yes('the page does not show issue numbers to testers', !/#\d{2,}/.test(page));

// Planted boards.
yes('planted: a row typed in the hub with no issue is caught',
    problems({ sections: [{ name: 'S', columns: [{ id: 'a' }], rows: [{ id: 'r', cells: { a: 'x' } }] }] }).length === 1);
yes('planted: a row ticked done needs no issue (it is off the page)',
    problems({ sections: [{ name: 'S', columns: [{ id: 'a' }], rows: [{ id: 'r', done: true, cells: { a: 'x' } }, { id: 's', issue: 5, cells: { a: 'y' } }] }] }).length === 0);
yes('planted: a section of explanation with no rows is caught',
    problems({ sections: [{ name: 'The load order rule', note: 'Words.', columns: [], rows: [] }] }).length === 1);

// 2. What came off: fixed, untrue, or on purpose.
[
  ['the NPC row #504 fixed', /NPC behaviour differs|Hosting changes every/i],
  ['the fishing row that said no rod is needed', /no rod needed/i],
  ['the table of mods the collection took out', /What the collection took out|SunHelm|TavernGames|Respawn - Death/i],
  ['what the server owns', /What the server owns/i],
  ['the load order rule', /The load order rule|LOAD ORDER ERROR/],
  ['the creation hall rows', /creation hall|leave the hall/i],
  ['the old launcher row', /before 26 September/i]
].forEach(function (c) { yes('the page no longer has ' + c[0], !c[1].test(page)); });
yes('the opening sends what is on purpose to Help', /\[Help\]\(\/help\)/.test(page.split('\n## ')[0]) &&
    /on purpose/i.test(page.split('\n## ')[0]));

// 3. Help has what moved there.
const normal = (help.split('## Things that are normal here')[1] || '').split('\n## ')[0];
yes('Help has its Things that are normal here list', normal.length > 0);
yes('it says what the server owns', /server owns where you are/i.test(normal) && /put back/i.test(normal));
yes('it says fishing is the Fisher\'s trade, with a pole', /Fishing is the Fisher's trade/.test(normal) && /pole/.test(normal));
yes('it says mods come in batches because of the load order', /batches/.test(normal) && /load order/.test(normal));
yes('it no longer calls the menus that still reset deliberate', !/QuickLoot/.test(normal));
yes('and it ends by pointing at Known Issues for what is broken', /\[Known Issues\]\(\/known\)\s+lists what is broken right now/.test(normal));
yes('Help tells somebody with a launcher from before 26 September to take the installer again',
    /launcher last opened before 26 September/.test(help) && /\[Downloads\]\(\/downloads\)/.test(help));

// 4. The roadmap does not carry a bug as work to build.
yes('the roadmap no longer lists Bard instruments, a bug on the board now',
    !/Bard instruments/.test(JSON.stringify(board.roadmap || {})));

// 5. Discord says the same about the page.
yes('Discord no longer calls the known issues page broken on purpose', !/broken on purpose/i.test(content));
yes('the Discord questions no longer explain NPCs by who is nearest or hosting swaps',
    !/Whoever is nearest is the one running them/.test(content) && !/Hosting swaps/.test(content));
yes('and fast travel points at the help page, not Known Issues',
    /\*\*Fast travel\?\*\*[^*]*\*\*https:\/\/thornswood\.net\/help\*\*/.test(content));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
