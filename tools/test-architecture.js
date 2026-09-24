// test-architecture.js
//
// tools\app\ARCHITECTURE.md is the launcher's one architecture page, the two
// long-form documents point at it, and every step it names is still where it
// says and in the order it says.
//
// WHY THIS EXISTS. To Do List entry 256: "There is no launcher architecture
// document, because the one that is pointed at is a finished to-do note".
// CLAUDE.md and SECOND-DEVELOPER.md both sent a newcomer to
// tools\app\HOOKUP.md for "how the launcher classes hang together", and that
// file was 108 lines titled "Wiring Discord.cs into the launcher": finished
// work. Play, the flow every person hits, could not be followed from the
// written record at all. The entry's own trap is the reason for the checks
// below: "leaving a stale one behind is exactly how this problem started".
//
// What it checks:
//   1. the page is there and the old note is gone;
//   2. CLAUDE.md and SECOND-DEVELOPER.md point at the page, and no tracked
//      document still points at the old note (WORKING-NOTES.md is exempt:
//      it is the dated 17 September audit, a record of what was true then);
//   3. Shell.cs carries a class summary that names the page;
//   4. every `File.cs:123 Name` reference on the page resolves: the file is in
//      tools\app and the name is still in it, as a declaration when it ends
//      in () and as code (not a comment, not a string) otherwise;
//   5. under each heading, references into the same method are in the order
//      the code runs them, so a step moved in Play is a step moved on the page;
//   6. the page has the four sections the entry asked for, says which
//      install it describes, and lists every file CLAUDE.md's #dev rule names.
//
// A line that has only moved is reported, not failed: every edit above it
// moves it, and the name is the anchor the page tells people to search for.
// Each NOTE says where the line is now, so updating the page is a copy.
//
// Read only.
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const APP = path.join(__dirname, 'app');
const PAGE = path.join(APP, 'ARCHITECTURE.md');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function note(m) { console.log('NOTE  ' + m); }
function read(p) { try { return fs.readFileSync(p, 'utf8'); } catch (e) { return null; } }
function esc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }

// ------------------------------------------------------------ 1. the files
const page = read(PAGE);
yes('tools/app/ARCHITECTURE.md exists', page !== null);
yes('tools/app/HOOKUP.md, the finished Discord wiring note, is gone',
    !fs.existsSync(path.join(APP, 'HOOKUP.md')));

// ------------------------------------------------------------ 2. the pointers
['CLAUDE.md', 'SECOND-DEVELOPER.md'].forEach(function (doc) {
  const t = read(path.join(ROOT, doc)) || '';
  yes(doc + ' points at tools\\app\\ARCHITECTURE.md', t.indexOf('tools\\app\\ARCHITECTURE.md') >= 0);
  yes(doc + ' no longer names HOOKUP.md', !/HOOKUP/i.test(t));
});

let tracked = null;
try {
  tracked = execSync('git ls-files -z', { cwd: ROOT, maxBuffer: 64 * 1024 * 1024 })
    .toString('utf8').split('\0').filter(Boolean);
} catch (e) {
  note('git ls-files did not answer, so only the two documents above were searched: ' + e.message);
}
if (tracked) {
  const pointing = tracked.filter(function (f) {
    if (!/\.md$/i.test(f)) return false;
    if (/^WORKING-NOTES\.md$/i.test(f)) return false;
    if (/^tools\/app\/ARCHITECTURE\.md$/i.test(f)) return false;
    const t = read(path.join(ROOT, f));
    return t !== null && /HOOKUP\.md/i.test(t);
  });
  pointing.forEach(function (f) { console.log('      still names HOOKUP.md: ' + f); });
  yes('no tracked document outside the dated audit still points at HOOKUP.md', pointing.length === 0);
}

// ------------------------------------------------------------ 3. Shell.cs
{
  const shellSrc = (read(path.join(APP, 'Shell.cs')) || '').replace(/\r\n/g, '\n');
  const at = shellSrc.search(/^[ \t]*static partial class Shell\b/m);
  const before = at > 0 ? shellSrc.slice(0, at) : '';
  const m = before.match(/((?:[ \t]*\/\/\/[^\n]*\n)+)$/);
  const summary = m ? m[1] : '';
  yes('Shell.cs has a /// summary directly above the class', /<summary>/.test(summary) && /<\/summary>/.test(summary));
  yes('that summary names tools\\app\\ARCHITECTURE.md', summary.indexOf('tools\\app\\ARCHITECTURE.md') >= 0);
}

if (page === null) {
  console.log('');
  console.log(pass + ' passed, ' + fail + ' failed');
  process.exit(1);
}

// ------------------------------------------------------------ reading C#
// Comments and the insides of string and char literals blanked out, line
// count kept, so a name mentioned in a comment or a log sentence does not
// count as the code still doing it.
function strip(src) {
  let out = '';
  let st = 0; // 0 code, 1 // comment, 2 /* comment, 3 "string", 4 @"verbatim", 5 'char'
  for (let i = 0; i < src.length; i++) {
    const c = src[i], d = src[i + 1];
    if (st === 0) {
      if (c === '/' && d === '/') { st = 1; out += '  '; i++; continue; }
      if (c === '/' && d === '*') { st = 2; out += '  '; i++; continue; }
      if (c === '@' && d === '"') { st = 4; out += '@"'; i++; continue; }
      if (c === '"') { st = 3; out += c; continue; }
      if (c === '\'') { st = 5; out += c; continue; }
      out += c; continue;
    }
    if (c === '\n') {
      out += '\n';
      if (st === 1 || st === 3 || st === 5) st = 0;
      continue;
    }
    if (st === 1) { out += ' '; continue; }
    if (st === 2) {
      if (c === '*' && d === '/') { st = 0; out += '  '; i++; continue; }
      out += ' '; continue;
    }
    if (st === 3 || st === 5) {
      if (c === '\\' && d !== '\n') { out += '  '; i++; continue; }
      if ((st === 3 && c === '"') || (st === 5 && c === '\'')) { st = 0; out += c; continue; }
      out += ' '; continue;
    }
    if (st === 4) {
      if (c === '"' && d === '"') { out += '  '; i++; continue; }
      if (c === '"') { st = 0; out += c; continue; }
      out += ' '; continue;
    }
  }
  return out.split('\n');
}

const MODS = '(?:(?:public|private|internal|protected|static|override|virtual|sealed|extern|abstract|unsafe|new)\\s+)+';
function declRx(name) { return new RegExp('^\\s*' + MODS + '[\\w<>\\[\\],.?]+\\s+' + esc(name) + '\\s*\\('); }
// A method declared at class depth: eight spaces in, the way every file here
// is laid out (namespace, class, member).
const MEMBER = new RegExp('^ {8}' + MODS + '[\\w<>\\[\\],.?]+\\s+(\\w+)\\s*\\(');
function refRx(name) { return new RegExp('(^|[^\\w])' + esc(name) + '(?!\\w)'); }

const sources = {};
function source(file) {
  if (!(file in sources)) {
    const t = read(path.join(APP, file));
    sources[file] = t === null ? null : strip(t.replace(/\r\n/g, '\n'));
  }
  return sources[file];
}

// The member a line sits inside: the nearest method declared at class depth
// at or above it. A delegate wired inside Wire belongs to Wire.
function enclosing(lines, at) {
  for (let i = at - 1; i >= 0; i--) {
    const m = lines[i].match(MEMBER);
    if (m) return (i + 1) + ':' + m[1];
  }
  return '0:';
}

// ------------------------------------------------------------ 4. references
// Read across line breaks: a reference wrapped onto two lines is still a
// reference, and one the check must not skip.
const pageText = page.replace(/\r\n/g, '\n');
const pageLines = pageText.split('\n');
const headings = [];
{
  let off = 0;
  pageLines.forEach(function (l) { if (/^#/.test(l)) headings.push({ at: off, text: l }); off += l.length + 1; });
}
function headingAt(at) {
  let h = '';
  headings.forEach(function (x) { if (x.at <= at) h = x.text; });
  return h;
}
const refs = [];
const malformed = [];
{
  const spanRx = /`([^`]+)`/g;
  let sm;
  while ((sm = spanRx.exec(pageText)) !== null) {
    const body = sm[1].replace(/[ \t]*\n[ \t]*/g, ' ');
    if (!/^[A-Za-z]+\.cs:\d/.test(body)) continue;
    const at = pageText.slice(0, sm.index).split('\n').length;
    const m = body.match(/^([A-Za-z]+\.cs):(\d+) ([A-Za-z_][A-Za-z0-9_.]*)(\(\))?$/);
    if (!m) { malformed.push('page line ' + at + ': `' + body + '`'); continue; }
    refs.push({ file: m[1], line: +m[2], name: m[3], decl: !!m[4], heading: headingAt(sm.index), pageLine: at, text: body });
  }
}
malformed.forEach(function (b) { console.log('      not in the File.cs:line Name form: ' + b); });
yes('every file:line reference on the page is in the File.cs:line Name form', malformed.length === 0);
yes('the page makes at least 100 file:line references, ' + refs.length + ' of them', refs.length >= 100);

const gone = [];
let exact = 0, moved = 0;
refs.forEach(function (r) {
  const lines = source(r.file);
  if (lines === null) { gone.push(r.text + ' (page line ' + r.pageLine + '): tools/app/' + r.file + ' does not exist'); return; }
  const rx = r.decl ? declRx(r.name.split('.').pop()) : refRx(r.name);
  const hits = [];
  lines.forEach(function (l, i) { if (rx.test(l)) hits.push(i + 1); });
  if (hits.length === 0) {
    gone.push(r.text + ' (page line ' + r.pageLine + '): ' +
      (r.decl ? 'no method of that name is declared in ' : 'that name is no longer in the code of ') + r.file);
    return;
  }
  if (hits.indexOf(r.line) >= 0) { r.now = r.line; exact++; }
  else {
    let best = hits[0];
    hits.forEach(function (h) { if (Math.abs(h - r.line) < Math.abs(best - r.line)) best = h; });
    r.now = best; moved++;
    note(r.text + ' has moved to ' + r.file + ':' + best + ' (page line ' + r.pageLine + ')');
  }
  r.member = r.file + '|' + enclosing(lines, r.now);
});
gone.forEach(function (m) { console.log('      ' + m); });
yes('every name the page gives is still in the file it names', gone.length === 0);
if (moved > 0) note(moved + ' of ' + (exact + moved) + ' references have moved; the page wants those line numbers updated');
else console.log('      all ' + exact + ' references land on their line');

// ------------------------------------------------------------ 5. order
// Under one heading, a reference into a method comes after the previous
// reference into the same method, because that is the order the page tells
// people the steps happen in.
function outOfOrder(list) {
  const found = [];
  let lastHeading = null, lastIn = {};
  list.forEach(function (r) {
    if (r.heading !== lastHeading) { lastHeading = r.heading; lastIn = {}; }
    if (r.now === undefined) return;
    const prev = lastIn[r.member];
    if (prev && r.now <= prev.now && !(r.now === prev.now && r.text === prev.text)) {
      found.push(prev.text + ' then ' + r.text + ' under "' + r.heading.replace(/^#+\s*/, '') +
        '": the code has them at ' + prev.now + ' and ' + r.now);
    }
    lastIn[r.member] = r;
  });
  return found;
}
const disorder = outOfOrder(refs);
disorder.forEach(function (m) { console.log('      ' + m); });
yes('the steps the page lists inside each method are in the order the code runs them', disorder.length === 0);

// Proof the order check has teeth: the steps the page walks inside Play(),
// read backwards, have to be caught.
{
  const inPlay = refs.filter(function (r) {
    return r.now !== undefined && r.heading === '### Pressing it' && /\|\d+:Play$/.test(r.member || '');
  });
  yes('the page walks at least ten steps inside Play(), ' + inPlay.length + ' of them', inPlay.length >= 10);
  yes('and the same steps listed backwards would be caught as out of order',
      outOfOrder(inPlay.slice().reverse()).length > 0);
}

// ------------------------------------------------------------ 6. shape
['## Which install this describes', '## 1. Starting up', '## 2. What each part owns',
 '## 3. The Play sequence', '## 4. The six shared files'].forEach(function (h) {
  yes('the page has the heading "' + h.replace(/^#+\s*/, '') + '"', pageLines.indexOf(h) >= 0);
});
{
  const top = page.slice(0, Math.max(0, page.indexOf('## 1. Starting up')));
  yes('before section 1 it says the game runs from <Root>\\Game, Thornswood\'s own folder',
      top.indexOf('<Root>\\Game') >= 0 && /Paths\.Collection/.test(top));
}

// The subsystems the entry named, each with its paragraph. "Creation" has no
// class; the page says so, and Chars.cs is where it lives.
{
  const s2 = page.slice(page.indexOf('## 2. What each part owns'), page.indexOf('## 3. The Play sequence'));
  ['Paths', 'Config', 'Keep', 'Hold', 'Swap', 'Verify', 'Updater', 'Door', 'Voice', 'Chars', 'OwnGame', 'Uninstall', 'Register']
    .forEach(function (c) {
      yes('section 2 has a paragraph for ' + c + ' (' + c + '.cs)',
          new RegExp('^\\*\\*' + c + '\\b[^\\n]*\\n?[^\\n]*\\(' + c + '\\.cs').test(s2) ||
          new RegExp('^\\*\\*[^*\\n]*\\b' + c + '\\b[^*\\n]*\\*\\* \\([^)]*\\b' + c + '\\.cs', 'm').test(s2));
    });
  yes('section 2 says there is no class called Creation', /no class called Creation/.test(s2));
}

// Every class in tools\app named somewhere on the page. Reported rather than
// failed: a new file is a new line on the page, and the NOTE says which.
{
  const unnamed = [];
  try {
    fs.readdirSync(APP).filter(function (f) { return /\.cs$/.test(f); }).forEach(function (f) {
      if (page.indexOf(f) < 0) unnamed.push(f);
    });
  } catch (e) { }
  if (unnamed.length) note('not named on the page yet: ' + unnamed.join(', '));
  else console.log('      every .cs file in tools/app is named on the page');
}

// The six shared files, as CLAUDE.md names them today.
{
  const claude = (read(path.join(ROOT, 'CLAUDE.md')) || '').replace(/\s+/g, ' ');
  const m = claude.match(/Do not edit (.+?) without a line in #dev/);
  const s4 = page.slice(Math.max(0, page.indexOf('## 4. The six shared files')));
  if (!m) note('CLAUDE.md no longer words its #dev rule as "Do not edit ... without a line in #dev", so section 4 was not compared with it');
  else {
    const named = m[1].match(/[\w-]+\.(?:cs|ps1)/g) || [];
    yes('CLAUDE.md\'s #dev rule names files, ' + named.length + ' of them', named.length > 0);
    named.forEach(function (f) { yes('section 4 lists ' + f, s4.indexOf(f) >= 0); });
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
