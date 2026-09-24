'use strict';
// test-readme-words.js
//
// The front page of the repository is called Thornswood, keeps the words
// rules, and leaves the Bethesda disclaimer where it is. Entry 319 on the To
// Do List.
//
// WHY THIS EXISTS. The entry was "the README still says Skyrim Together". The
// heading had been fixed on 18 September (c98238e) and the entry was nearly
// closed on that. A second read measured the rest of its done-when on main on
// 24 September and found it still false: README.md line 3 opened with a head
// count and the one word the project never uses for the people in the world,
// and five em dashes sat at lines 37, 55, 69, 72 and 78. README.md is
// the first page anybody opening the repository reads, so the words rules
// hold over the whole file and not only the heading.
//
// The opening sentence is held to the site's own description, read out of
// home.html, because the entry names thornswood.net as "the public front the
// README should agree with". Five was also not the number any more: the
// launcher's Play page tells people 25, its MaxOnline (entry 281,
// test-max-online.ps1). If the site's description changes, this fails, and
// the README's first sentence is what to change to match.
//
// The disclaimer half is the entry's own check, kept as it wrote it: the
// Bethesda search over credits.md and home.html returns three lines, two and
// one. The entry says it is "the one legally useful sentence on the site";
// this makes sure nobody tidying the README tidies that away, and that nobody
// puts a trademark mark on a name that is not registered.
//
// Entry 193 is the full README rewrite (the stale install text, the zip flow,
// F2). This checks only what 319 asked for, so it does not stand in 193's way.
//
// Read only.
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const CR = String.fromCharCode(13);

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function read(rel) {
  try { return fs.readFileSync(path.join(ROOT, rel), 'utf8').split(CR).join(''); }
  catch (e) { return null; }
}
// Select-String matches line by line and ignores case by default; so does this.
function lines(t, re) {
  return (t || '').split('\n').map(function (l, i) { return { n: i + 1, l: l }; })
    .filter(function (x) { return re.test(x.l); });
}
function at(hits) {
  return hits.map(function (x) { return x.n; }).join(', ');
}

const readme = read('README.md');
yes('README.md is there', readme !== null);
const t = readme || '';
const all = t.split('\n');

// ------------------------------------------------------------- the name --
yes('its first line is # Thornswood (it is "' + all[0] + '")', all[0] === '# Thornswood');
const old = lines(t, /skyrim together/i);
yes('it never says Skyrim Together' + (old.length ? ' (line ' + at(old) + ')' : ''), old.length === 0);
// U+2122, U+00AE, or a (TM) or (R) typed out. The name is not registered.
const mark = lines(t, /™|®|\((TM|R)\)/i);
yes('it puts no trademark mark on anything' + (mark.length ? ' (line ' + at(mark) + ')' : ''),
    mark.length === 0);

// ------------------------------------------------------------ the words --
const who = lines(t, /\bplayers?\b/i);
yes('it never says player' +(who.length ? ' (line ' + at(who) + ')' : ''), who.length === 0);
const em = lines(t, /—/);
yes('no em dash anywhere in it' + (em.length ? ' (line ' + at(em) + ')' : ''), em.length === 0);
const en = lines(t, /–/);
yes('and no en dash standing in for one' + (en.length ? ' (line ' + at(en) + ')' : ''), en.length === 0);

// -------------------------------------------- the opening, and the site --
let s = 1;
while (s < all.length && all[s].trim() === '') { s++; }
let e = s;
while (e < all.length && all[e].trim() !== '') { e++; }
const opening = all.slice(s, e).join(' ').replace(/\s+/g, ' ').trim();
const home = read('tools/docs-app/public/home.html');
const desc = (/<meta name="description" content="([^"]+)"/.exec(home || '') || [])[1] || '';
const first = (/^[^.]+\./.exec(desc) || [])[0] || '';
yes('home.html has a description to hold the README to ("' + first + '")', first.length > 0);
yes('the README opens with that same sentence (it opens "' + opening.slice(0, 60) + '")',
    first.length > 0 && opening.indexOf(first) === 0);
yes('and gives no head count the launcher no longer keeps to', !/\b(five|5)\b/i.test(opening));

// --------------------------------------------------- the disclaimer stays --
const credits = read('tools/docs-app/data/site/credits.md');
yes('credits.md and home.html are both there', credits !== null && home !== null);
const bc = lines(credits, /bethesda/i);
const bh = lines(home, /bethesda/i);
yes('the Bethesda search returns three lines, two in credits.md (' + at(bc) + ') and one in home.html (' +
    at(bh) + ')', bc.length === 2 && bh.length === 1);
function flat(x) { return (x || '').replace(/<br>/g, ' ').replace(/\s+/g, ' '); }
const line = 'not affiliated with or endorsed by Bethesda Softworks. The Elder Scrolls and Skyrim are their trademarks';
yes('credits.md still carries the disclaimer word for word', flat(credits).indexOf(line) >= 0);
yes('and so does the foot of home.html', flat(home).indexOf(line) >= 0);

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
