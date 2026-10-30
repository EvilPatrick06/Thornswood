// test-roadmap.js
//
// What the emote wheel's notes say about it is read off the files that decide
// it. This began as a check on the roadmap's wheel row; since #3140 the
// roadmap is built from the issue board, so that row is the "Roadmap:"
// comment on the wheel's issue and is no longer a file here. The ini, the
// plugin and the todo.md note it was held to still are.
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
// the count when the wheel was two rings of twelve, and again when it was
// six categories and thirty four emotes. Both numbers had been copied out of
// a note rather than out of the code, which is how a wrong one gets onto a
// page. The wheel is one list now, with eight quick slots.
//
// So nothing below takes a key or a count on trust. The letter comes out of
// launcher/Thornswood.ini, decoded with that file's own A to Z table, and
// the count comes out of the plugin's EMOTES array. A key that moves or a
// wheel that grows fails here until the words say so too.
//
// Read only.
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const CR = String.fromCharCode(13);

function read(rel) {
  let t = fs.readFileSync(path.join(REPO_DIR, rel), 'utf8').split(CR).join('');
  if (t.charCodeAt(0) === 0xFEFF) { t = t.slice(1); }
  return t;
}

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

/* Numbers as the site writes them: "fifty nine", "fifty-nine" or "59". */
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

// ------------------------------------------------------------ the roadmap --
/* Since #3140 the roadmap is built from the issue board: the wheel's row is
   the "Roadmap:" comment on its issue, and an issue that is closed as done is
   under Done by itself, so the row this harness held to the ini and the
   plugin is no longer a file here. What it was checked against still is, and
   so is the note in todo.md the wrong numbers came from. */

// -------------------------------------------------------------- the keys ----
const ini = read('launcher/Thornswood.ini');
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

/* "The launcher's Controls page moves any of those keys" is a claim too. */
const keys = read('launcher/app/Keys.cs');
yes('the launcher\'s Controls page does list WheelKey, PageKey and StopKey',
    ['WheelKey', 'PageKey', 'StopKey'].every(function (k) {
      return keys.indexOf('ThornIni, "' + k + '"') !== -1;
    }));

// ------------------------------------------------------------ the emotes ----
const plugin = read('game/plugins/thornswood-emotes.js');
const a = plugin.indexOf('const EMOTES = [');
const b = a < 0 ? -1 : plugin.indexOf('\n];', a);
let list = null;
try {
  if (a >= 0 && b >= 0) {
    list = new Function('return ' + plugin.slice(a + 'const EMOTES = '.length, b + 2) + ';')();
  }
} catch (e) { console.log('      EMOTES: ' + e.message); }
yes('the plugin\'s EMOTES array evaluates', Array.isArray(list) && list.length > 0);
const nEmotes = list ? list.length : 0;
const events = (a >= 0 && b >= 0) ? (plugin.slice(a, b).match(/event: '/g) || []).length : -1;
yes('and it agrees with a plain count of its event lines, ' + nEmotes + ' and ' + events,
    nEmotes > 0 && nEmotes === events);

// -------------------------------------------------- the note in todo.md ----
/* The note the wrong numbers were copied from, so the next copy is right. */
const todo = read('site/data/todo.md');
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
