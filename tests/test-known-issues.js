// test-known-issues.js
//
// The Known Issues page stops calling roadmap work permanent, and every other
// place that describes the same rows says the same thing about them.
//
// From the To Do List, entry 296: "Pick one and say it once. If NPC behaviour
// is being worked on, it belongs under a heading that says so rather than one
// that tells people never to report it. The tester note repeats the permanent
// version, so three places currently disagree about whether this is a limit
// or a task".
//
// WHAT WAS MEASURED ON 24 SEPTEMBER. known.md opened its first table with
// "They are not going to change" over NPCs standing still and NPC behaviour
// differing, while board.json's roadmap carries Thinning the crowd and NPCs
// with their own work under Next. Patrick decided the NPC cut on 17 September
// (To Do entry 320), so the roadmap is the one that is right. It was not three
// places but six: the /known link preview in server.js and the same string in
// public/home.html both opened "Permanent limits", the hub's own copy of the
// board in board.json said "none are changing", the tester note listed NPCs
// under Do not report these, and the Help page listed them under "All of that
// is deliberate". The other three rows in that table are open To Do entries
// too (299 mod settings, 323 Papyrus events, 300 killmoves and stagger), so
// the fix is to the promise over the table rather than to two of its rows.
//
// HOW A SUBJECT IS MATCHED. A row and a roadmap item are about the same thing
// when the row's first cell and the roadmap item's title share a word once
// plurals and common words are taken out: "NPCs stand still" and "NPCs with
// their own work" share "npc". The roadmap is read out of board.json rather
// than copied in here, so a roadmap edit on the site is what this checks
// against the next time it runs.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const APP = process.env.DOCS_APP || path.join(REPO_DIR, 'site');
const CR = String.fromCharCode(13);
function read(rel) {
  try { return fs.readFileSync(path.join(APP, rel), 'utf8').split(CR).join(''); }
  catch (e) { return null; }
}

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/* Anything that tells a reader a row will stay the way it is. "Not all of it
   is permanent" is the opposite, so "permanent" on its own is not here; the
   phrases are the ones this site has actually used. */
const PROMISE = /not going to change|none are changing|are not changing|never going to change|will not change|won't change|permanent limits/i;

/* Words that say nothing about what a row is about. "launcher" is here because
   the roadmap's launcher item is about switching servers, and every row about
   getting in names the launcher without being about that. */
const STOP = ['the', 'and', 'for', 'with', 'their', 'own', 'you', 'your',
  'yours', 'into', 'from', 'through', 'run', 'make', 'real', 'worth', 'going',
  'actually', 'when', 'nobody', 'near', 'nearby', 'same', 'not', 'other',
  'most', 'never', 'show', 'does', 'every', 'between', 'people', 'all', 'any',
  'one', 'its', 'can', 'cannot', 'are', 'has', 'have', 'what', 'who', 'this',
  'that', 'them', 'they', 'out', 'off', 'get', 'where', 'how', 'but', 'still',
  'launcher'];
function words(s) {
  const out = [];
  String(s || '').toLowerCase().replace(/[^a-z]+/g, ' ').split(' ').forEach(function (w) {
    if (!w || STOP.indexOf(w) >= 0) { return; }
    const one = (w.length > 3 && /[^s]s$/.test(w)) ? w.slice(0, -1) : w;
    if (one.length >= 3 && STOP.indexOf(one) < 0 && out.indexOf(one) < 0) { out.push(one); }
  });
  return out;
}
function shared(a, b) { return a.filter(function (w) { return b.indexOf(w) >= 0; }); }

/* A markdown page as the text before the first heading and one entry per
   "## " heading: the words between the heading and its table, and the first
   cell of every row of that table. */
function sections(md) {
  const lines = md.split('\n');
  const out = { intro: '', list: [] };
  let cur = null, header = false;
  lines.forEach(function (line) {
    if (/^## /.test(line)) {
      cur = { heading: line.slice(3).trim(), lead: '', rows: [], items: [], text: '' };
      out.list.push(cur); header = false; return;
    }
    if (!cur) { if (!/^# /.test(line)) { out.intro += line + '\n'; } return; }
    cur.text += line + '\n';
    if (/^\|/.test(line)) {
      if (!header) { header = true; return; }
      if (/^\|\s*-/.test(line)) { return; }
      cur.rows.push(line.split('|')[1].trim());
      return;
    }
    if (/^- /.test(line)) { cur.items.push(line.slice(2).trim()); }
    if (!cur.rows.length) { cur.lead += line + '\n'; }
  });
  return out;
}

// -------------------------------------------------------------- the roadmap
const boardText = read(path.join('data', 'board.json'));
let board = null;
try { board = JSON.parse(boardText); } catch (e) { board = null; }
yes('board.json reads as JSON', !!board);

/* Work that is not done: every roadmap row outside the Done section. */
const work = [];
if (board && board.roadmap && board.roadmap.sections) {
  board.roadmap.sections.forEach(function (s) {
    if (/^\s*done\s*$/i.test(s.name || '')) { return; }
    const what = (s.columns || []).filter(function (c) { return /^what$/i.test(c.name); })[0] ||
                 (s.columns || [])[0];
    (s.rows || []).forEach(function (r) {
      if (r.done === true || !what) { return; }
      const title = String((r.cells || {})[what.id] || '');
      if (title) { work.push({ title: title, words: words(title), section: s.name }); }
    });
  });
}
yes('the roadmap has work on it that is not done, ' + work.length + ' items', work.length > 0);
function workFor(text) {
  const w = words(text);
  return work.filter(function (r) { return shared(w, r.words).length > 0; });
}

// ---------------------------------------------------------- the known page
// The page is the known board, written out the way /known writes it (#2414).
const known = require('./fixtures/known-page').knownPage();
yes('the Known Issues page is there, written from the known board', known !== null);
const page = sections(known || '');
const skymp = page.list[0] || { heading: '', lead: '', rows: [] };
yes('its first table is the group that follows from SkyMP, with its rows',
    /shared Skyrim/i.test(skymp.heading) && skymp.rows.length >= 3);

/* The subjects the SkyMP table shares with the roadmap. Worked out rather than
   written down, so the checks below follow whatever the roadmap says. */
const onRoadmap = [];
page.list.forEach(function (s) {
  s.rows.forEach(function (row) {
    workFor(row).forEach(function (r) {
      shared(words(row), r.words).forEach(function (w) {
        if (onRoadmap.indexOf(w) < 0) { onRoadmap.push(w); }
      });
    });
  });
});
console.log('INFO  subjects the Known Issues rows share with the roadmap: ' +
            (onRoadmap.join(', ') || 'none'));

/*
  THE DEFECT ITSELF. The page's own opening said the first group "is not
  going to change", and the table under it said it again, over two rows the
  roadmap lists as work under Next.
*/
yes('the page opening no longer promises the first group will not change',
    !PROMISE.test(page.intro));
{
  const bad = [];
  page.list.forEach(function (s, i) {
    const promises = PROMISE.test(s.lead) || (i === 0 && PROMISE.test(page.intro));
    if (!promises) { return; }
    s.rows.forEach(function (row) {
      workFor(row).forEach(function (r) { bad.push(row + ' / ' + r.title); });
    });
  });
  if (bad.length) { console.log('      under a promise and on the roadmap: ' + bad.join('; ')); }
  yes('no row under a heading that says it will not change is roadmap work', bad.length === 0);
}

/* "It belongs under a heading that says so." A row that is roadmap work sits
   in a section that says so, and names the roadmap item by the title a reader
   will find on /roadmap. */
{
  const bad = [];
  page.list.forEach(function (s) {
    s.rows.forEach(function (row) {
      const items = workFor(row);
      if (!items.length) { return; }
      const lead = s.lead.toLowerCase();
      const named = items.some(function (r) { return lead.indexOf(r.title.toLowerCase()) >= 0; });
      if (lead.indexOf('roadmap') < 0 || !named) { bad.push(s.heading + ': ' + row); }
    });
  });
  if (bad.length) { console.log('      roadmap work under a section that does not say so: ' + bad.join('; ')); }
  yes('every row that is roadmap work sits under words that say it is, by the roadmap title',
      bad.length === 0);
}

/* "Rather than one that tells people never to report it." The section still
   tells people when a report is worth making. */
yes('the SkyMP table says what is still worth reporting',
    /report[^.]*only if|only report|worth reporting|worth a report/i.test(skymp.lead));

// ------------------------------------------------------------ the preview
/* What a link to /known says when it is pasted into Discord. server.js is the
   one a crawler reads, the home page's script the one the browser tab reads,
   and they are meant to be the same list. That script moved out of home.html
   into home.js in #1479 (no inline script under the content security policy). */
function blurb(rel) {
  const src = read(rel) || '';
  const m = src.match(/'\/known':\s*\[\s*'([^']*)',\s*'([^']*)'\s*\]/);
  return m ? m[2] : null;
}
const serverBlurb = blurb('server.js');
const homeBlurb = blurb(path.join('public', 'home.js'));
yes('server.js has a /known preview', serverBlurb !== null);
yes('home.js has a /known preview', homeBlurb !== null);
yes('the preview a crawler reads no longer calls the page permanent',
    serverBlurb !== null && !/permanent/i.test(serverBlurb) && !PROMISE.test(serverBlurb));
yes('nor does the one the browser tab reads',
    homeBlurb !== null && !/permanent/i.test(homeBlurb) && !PROMISE.test(homeBlurb));
yes('and the two say the same thing', serverBlurb !== null && serverBlurb === homeBlurb);

// ------------------------------------------------------- the tester note
const tests = read(path.join('data', 'tests.md'));
yes('tests.md is there', tests !== null);
{
  const s = sections(tests || '').list.filter(function (x) { return /do not report/i.test(x.heading); })[0];
  yes('it still has its Do not report these list', !!s);
  const said = s ? s.text.replace(/\s+/g, ' ').trim().split(/(?:\.)\s+/) : [];
  const bad = [];
  said.forEach(function (line, i) {
    if (!shared(words(line), onRoadmap).length) { return; }
    const here = line + '. ' + (said[i + 1] || '');
    if (!/roadmap/i.test(here) || !/report[^.]*only|only report|worth reporting|worth a report/i.test(here)) {
      bad.push(line);
    }
  });
  if (bad.length) { console.log('      listed as never to report: ' + bad.join('; ')); }
  yes('anything on the roadmap in that list says so, and says what is worth reporting',
      bad.length === 0);
}

// ------------------------------------------------------------ the Help page
/* help.md lists things that are normal here and closes "All of that is
   deliberate. None of it is worth reporting." Roadmap work is not
   deliberate. */
const help = read(path.join('data', 'help.md'));
yes('help.md is there', help !== null);
{
  const s = sections(help || '').list.filter(function (x) { return /deliberate/i.test(x.text); })[0];
  yes('it still has the list it calls deliberate', !!s && s.items.length > 0);
  const bad = (s ? s.items : []).filter(function (it) { return shared(words(it), onRoadmap).length > 0; });
  if (bad.length) { console.log('      called deliberate and on the roadmap: ' + bad.join('; ')); }
  yes('nothing in it is roadmap work', bad.length === 0);
}

// ---------------------------------------------------- one copy only (#2414)
/* The text was kept twice, known.md for the page and a known board nothing
   showed, and the board went stale: its intro said "Permanent limits of how
   this server works. None are bugs, none are changing." over NPC rows #504
   made untrue. Patrick, 12 October: the hub board is the one copy. The page
   above is that board, and tests/test-2414-known-one-copy.js keeps a second
   copy from coming back. */
yes('there is no known.md beside the board', read(path.join('data', 'known.md')) === null);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
