// test-roadmap.js
//
// The roadmap does not call something unstarted that ships, and what it says
// about the emote wheel is read off the files that decide it.
//
// WHY THIS EXISTS. The roadmap's Later section said "Emote wheel | Wanted
// since the start, never started", while game/plugins/thornswood-emotes.js,
// 593 lines, went out in every release and testers were asked to use it. From
// the To Do List: "Verified: it exists and works. Move it to Done. Also check
// the rest of Later the same way, because a roadmap that lists a shipped
// feature as not started is a roadmap nobody will trust on the items that
// really are unstarted".
//
// The one note that did record the wheel as done, in data/todo.md, was wrong
// twice over: "B opens it" and "twenty four emotes". B is the plugin's fallback
// for when the ini has no WheelKey line at all (thornswood-emotes.js,
// key('WheelKey', 48)); the ini that ships says 34, which is G. Twenty four was
// the count when the wheel was two rings of twelve; it is six categories and
// thirty four emotes now. Both numbers had been copied out of a note rather
// than out of the code, which is how a wrong one gets onto a page.
//
// So nothing below takes a key or a count on trust. The letter comes out of
// tools/emotes/Thornswood.ini, decoded with that file's own A to Z table, and
// the count comes out of the plugin's CATEGORIES array. A key that moves or a
// wheel that grows fails here until the words say so too.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);

function read(rel) {
  let t = fs.readFileSync(path.join(TOOLS_DIR, rel), 'utf8').split(CR).join('');
  if (t.charCodeAt(0) === 0xFEFF) { t = t.slice(1); }
  return t;
}

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/* Numbers as the site writes them: "thirty four", "thirty-four" or "34". */
const ONES = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven',
  'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen',
  'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty',
  'seventy', 'eighty', 'ninety'];
function says(text, n) {
  const t = ' ' + String(text || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ') + ' ';
  const forms = [String(n)];
  if (n < 20) { forms.push(ONES[n]); }
  else if (n < 100) { forms.push(TENS[Math.floor(n / 10)] + (n % 10 ? ' ' + ONES[n % 10] : '')); }
  return forms.some(function (f) { return t.indexOf(' ' + f + ' ') !== -1; });
}

// ------------------------------------------------------------- the board ----
let board = null;
try { board = JSON.parse(read('../site/data/board.json')); }
catch (e) { console.log('      board.json: ' + e.message); }
yes('board.json parses', !!board);

const sections = (board && board.roadmap && board.roadmap.sections) || [];
function section(name) {
  return sections.filter(function (s) {
    return String(s.name || '').trim().toLowerCase() === name;
  })[0] || null;
}
const later = section('later');
const done = section('done');
yes('the roadmap has a Later section and a Done section', !!later && !!done);

/*
  A row carries its cells keyed by its own section's column ids. A row moved
  from Later to Done and left on Later's ids draws with no title and no text,
  because the page reads c[cols[0].id] (public/home.html, the /roadmap route)
  and the hub does the same. So every row is checked, not only the one moved.
*/
const strays = [];
sections.forEach(function (s) {
  const ids = (s.columns || []).map(function (c) { return c.id; });
  (s.rows || []).forEach(function (r) {
    const keys = Object.keys(r.cells || {});
    const wrong = keys.filter(function (k) { return ids.indexOf(k) < 0; });
    const titled = ids.length && String((r.cells || {})[ids[0]] || '').trim();
    if (wrong.length || !titled) { strays.push(s.name + '/' + r.id + (wrong.length ? ' ' + wrong.join(',') : ' untitled')); }
  });
});
yes('every roadmap row is keyed by its own section\'s columns and has a title' +
    (strays.length ? ' (not: ' + strays.join('; ') + ')' : ''), sections.length && !strays.length);

/* Every row id once. A move that copied instead of moved shows up here. */
const seen = {}, twice = [];
sections.forEach(function (s) {
  (s.rows || []).forEach(function (r) { if (seen[r.id]) { twice.push(r.id); } seen[r.id] = true; });
});
yes('no roadmap row id appears twice' + (twice.length ? ' (' + twice.join(', ') + ')' : ''), !twice.length);

function title(s, r) {
  const first = (s.columns || [])[0];
  return first ? String((r.cells || {})[first.id] || '') : '';
}
function whole(r) {
  const c = r.cells || {};
  return Object.keys(c).map(function (k) { return String(c[k] || ''); }).join(' | ');
}

const wheel = [];
sections.forEach(function (s) {
  (s.rows || []).forEach(function (r) {
    if (/emote wheel/i.test(title(s, r))) { wheel.push({ section: s, row: r }); }
  });
});
yes('the emote wheel is on the roadmap exactly once, found ' + wheel.length, wheel.length === 1);
const w = wheel.length === 1 ? wheel[0] : null;
yes('and it is under Done' + (w && w.section !== done ? ', not "' + w.section.name + '"' : ''),
    !!w && w.section === done);
yes('Later no longer holds it', !!later && !(later.rows || []).some(function (r) {
  return /emote wheel/i.test(title(later, r));
}));
const text = w ? whole(w.row) : '';
yes('the row does not say it was never started', !!w && !/never started/i.test(text));
yes('the row keeps done false like every other roadmap row, since Done is the section',
    !!w && w.row.done === false);

// -------------------------------------------------------------- the keys ----
const ini = read('emotes/Thornswood.ini');
function iniKey(name) {
  const m = ini.match(new RegExp('^\\s*' + name + '\\s*=\\s*(\\d+)', 'm'));
  return m ? parseInt(m[1], 10) : NaN;
}
/* The ini's own comment is the scan code table, so the decoding here cannot
   drift from what the file tells somebody editing it by hand. */
const notes = ini.split('\n').filter(function (l) { return /^\s*;/.test(l); })
  .map(function (l) { return l.replace(/^\s*;\s?/, ''); }).join(' ');
const az = notes.match(/A-Z are ([\d,\s]+?)\s*for A\.\.Z/);
const codes = az ? az[1].split(',').map(function (x) { return parseInt(x.trim(), 10); }) : [];
yes('the ini\'s own A to Z table has 26 scan codes, found ' + codes.length, codes.length === 26);
function letter(code) {
  const at = codes.indexOf(code);
  return at < 0 ? '' : String.fromCharCode(65 + at);
}
yes('that table decodes scan code 34 as G and 48 as B, so the decoding is right',
    letter(34) === 'G' && letter(48) === 'B');
const tab = notes.match(/\bTab (\d+)/);

const WHEEL = iniKey('WheelKey'), PAGE = iniKey('PageKey'), STOP = iniKey('StopKey');
const wheelLetter = letter(WHEEL), stopLetter = letter(STOP);
yes('WheelKey (' + WHEEL + ') and StopKey (' + STOP + ') are letters: ' +
    (wheelLetter || '?') + ' and ' + (stopLetter || '?'), !!wheelLetter && !!stopLetter);
yes('PageKey (' + PAGE + ') is Tab by the ini\'s table', !!tab && parseInt(tab[1], 10) === PAGE);

function opens(t, l) { return new RegExp('(^|[^A-Za-z])' + l + ' opens').test(t); }
function stops(t, l) { return new RegExp('(^|[^A-Za-z])' + l + ' stops').test(t); }
yes('the row says ' + wheelLetter + ' opens it, as the ini does', !!wheelLetter && opens(text, wheelLetter));
yes('the row says Tab moves on, as the ini does', /\bTab\b/.test(text));
yes('the row says ' + stopLetter + ' stops, as the ini does', !!stopLetter && stops(text, stopLetter));

/* "The launcher's Controls page moves any of those keys" is a claim too. */
const keys = read('app/Keys.cs');
yes('the launcher\'s Controls page does list WheelKey, PageKey and StopKey, as the row says',
    ['WheelKey', 'PageKey', 'StopKey'].every(function (k) {
      return keys.indexOf('ThornIni, "' + k + '"') !== -1;
    }));

// ------------------------------------------------------------ the emotes ----
const plugin = read('../game/plugins/thornswood-emotes.js');
const a = plugin.indexOf('const CATEGORIES = [');
const b = a < 0 ? -1 : plugin.indexOf('\n];', a);
let cats = null;
try {
  if (a >= 0 && b >= 0) {
    cats = new Function('return ' + plugin.slice(a + 'const CATEGORIES = '.length, b + 2) + ';')();
  }
} catch (e) { console.log('      CATEGORIES: ' + e.message); }
yes('the plugin\'s CATEGORIES array evaluates', Array.isArray(cats) && cats.length > 0);
const nCats = cats ? cats.length : 0;
const nEmotes = cats ? cats.reduce(function (n, c) { return n + (c.items || []).length; }, 0) : 0;
const events = (a >= 0 && b >= 0) ? (plugin.slice(a, b).match(/event: '/g) || []).length : -1;
yes('and it agrees with a plain count of its event lines, ' + nEmotes + ' and ' + events,
    nEmotes > 0 && nEmotes === events);
yes('the row gives the plugin\'s count, ' + nEmotes + ' emotes', !!w && says(text, nEmotes));
yes('and its ' + nCats + ' categories', !!w && says(text, nCats));

// ----------------------------------------------------------------- words ----
yes('the row has no em dash in it', text.indexOf(String.fromCharCode(0x2014)) === -1);
yes('the row never says player', !/\bplayers?\b/i.test(text));

// -------------------------------------------------- the note in todo.md ----
/* The note the wrong numbers were copied from, so the next copy is right. */
const todo = read('../site/data/todo.md');
const t0 = todo.indexOf('- Emote wheel.');
const t1 = t0 < 0 ? -1 : todo.indexOf('\n- ', t0 + 1);
const note = t0 < 0 ? '' : todo.slice(t0, t1 < 0 ? todo.length : t1).replace(/\s+/g, ' ');
yes('todo.md still records the wheel as done', t0 >= 0);
yes('and no longer says B opens it', !/(^|[^A-Za-z])B opens/.test(note));
yes('it says ' + wheelLetter + ' opens it', !!wheelLetter && opens(note, wheelLetter));
yes('and gives the plugin\'s count, ' + nEmotes, says(note, nEmotes));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
