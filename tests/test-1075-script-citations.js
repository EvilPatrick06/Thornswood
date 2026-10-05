// test-1075-script-citations.js
//
//     node tests/test-1075-script-citations.js
//
// The pages under docs\ cite a PowerShell script as `Script.ps1:<what it
// says>`: the script, a colon, and the thing in it that holds what the
// sentence says, in the script's own words. Never a line number.
//
// WHY THIS EXISTS. Issue #1075: docs\SYSTEM.md, GAMEMODE.md and FEED.md cited
// script lines (`Deploy-Server.ps1:39`, `Publish-Server.ps1:415-520`) that
// held something else by the time anybody followed them, and #1067 found the
// Watchdog row on SYSTEM.md pointing at a header sentence and the inside of
// BackupProblem. Every edit above a cited line moves it, so a page that cites
// line numbers is wrong after the next merge into that script, and nothing
// said so. A name moves with its line. It goes wrong only when the thing
// itself is renamed or taken out, and then this fails, in the pull request
// that did it.
//
// What it checks, in every tracked .md under docs\ outside docs\archive (the
// dated record of what was true then):
//   1. no code span cites a .ps1 by line number;
//   2. every `Script.ps1:<name>` names a script there is: by its path when the
//      span gives one (`scripts\deploy\Deploy-Server.ps1:...`), otherwise by a
//      file name only one tracked script has;
//   3. the script still holds the thing named:
//        Name or Verb-Noun   a function of that name is declared in it
//        $name ...           (alone) the variable is given a value in it
//        anything else       those words are in it, runs of spaces and line
//                            breaks read as one space, so a sentence of its
//                            header may wrap where it likes;
//   4. each of those refuses what it should, against made-up scripts.
//
// Read only.
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.join(__dirname, '..');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function read(p) { try { return fs.readFileSync(p, 'utf8'); } catch (e) { return null; } }
function esc(s) { return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
function squash(s) { return s.replace(/\s+/g, ' '); }

// ------------------------------------------------------------ the files
let tracked = null;
try {
  // Once each: in the middle of a merge, git lists a file with a conflict
  // once for each side.
  tracked = Array.from(new Set(execSync('git ls-files -z', { cwd: ROOT, maxBuffer: 64 * 1024 * 1024 })
    .toString('utf8').split('\0').filter(Boolean)));
} catch (e) {
  console.log('NOTE  git ls-files did not answer, so the folders were walked instead: ' + e.message);
}
function walk(dir, out) {
  let names = [];
  try { names = fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true }); } catch (e) { return out; }
  names.forEach(function (d) {
    const rel = dir ? dir + '/' + d.name : d.name;
    if (d.isDirectory()) walk(rel, out); else out.push(rel);
  });
  return out;
}
const files = tracked || walk('docs', []).concat(walk('scripts', []));
const pages = files.filter(function (f) { return /^docs\/.*\.md$/i.test(f) && !/^docs\/archive\//i.test(f); });
const scripts = files.filter(function (f) { return /\.ps1$/i.test(f); });
yes('there are pages under docs to read, ' + pages.length + ' of them', pages.length > 0);
yes('there are scripts to read them against, ' + scripts.length + ' of them', scripts.length > 0);

// ------------------------------------------------------------ the rules
// A span that cites a script: an optional folder path, the file, a colon, and
// what follows it.
const CITE = /^((?:[\w.-]+[\\/])*)([\w.-]+\.ps1):([\s\S]+)$/i;
const LINES = /^\s*\d[\d\s,-]*$/;

// Where a cited script is, or why it cannot be said.
function locate(dir, file, list) {
  if (dir) {
    const rel = (dir + file).replace(/\\/g, '/');
    const hit = list.filter(function (f) { return f.toLowerCase() === rel.toLowerCase(); });
    return hit.length ? { path: hit[0] } : { why: rel + ' is not a tracked script' };
  }
  const hit = list.filter(function (f) { return f.split('/').pop().toLowerCase() === file.toLowerCase(); });
  if (hit.length === 1) return { path: hit[0] };
  if (hit.length === 0) return { why: 'no tracked script is called ' + file };
  return { why: file + ' is the name of ' + hit.length + ' scripts (' + hit.join(', ') + '), so the span has to give the folder' };
}

// '' when the script holds the thing, else what is missing.
function holds(text, what) {
  const name = what.trim();
  if (/^[A-Za-z][\w]*(-[\w]+)*$/.test(name)) {
    return new RegExp('^\\s*function\\s+' + esc(name) + '(?![\\w-])', 'im').test(text)
      ? '' : 'no function called ' + name + ' is declared in it';
  }
  if (/^\$[A-Za-z_][\w]*$/.test(name)) {
    return new RegExp(esc(name) + '(?!\\w)\\s*=(?!=)', 'i').test(text)
      ? '' : name + ' is never given a value in it';
  }
  return squash(text).indexOf(squash(name)) >= 0 ? '' : 'it no longer says "' + squash(name) + '"';
}

// Every problem with one page's citations, as sentences. A fenced block is
// blanked first, line count kept: its three backticks would otherwise pair
// with the next span's and put every span after it out of step.
function unfence(t) {
  return t.replace(/^[ \t]*(```|~~~)[^\n]*\n[\s\S]*?^[ \t]*\1[^\n]*$/gm, function (b) { return b.replace(/[^\n]/g, ''); });
}
function check(pageText, where, list, textOf) {
  const found = [];
  let count = 0;
  pageText = unfence(pageText);
  const spanRx = /`([^`]+)`/g;
  let m;
  while ((m = spanRx.exec(pageText)) !== null) {
    const body = m[1];
    const c = body.match(CITE);
    if (!c) continue;
    count++;
    const at = where + ':' + pageText.slice(0, m.index).split('\n').length;
    if (LINES.test(c[3])) {
      found.push(at + ' `' + squash(body) + '` cites line numbers; cite what the script says there instead, as `' + c[2] + ':<function, $variable or its own words>`');
      continue;
    }
    const loc = locate(c[1], c[2], list);
    if (!loc.path) { found.push(at + ' `' + squash(body) + '`: ' + loc.why); continue; }
    const text = textOf(loc.path);
    if (text === null) { found.push(at + ' `' + squash(body) + '`: ' + loc.path + ' could not be read'); continue; }
    const why = holds(text, c[3]);
    if (why) found.push(at + ' `' + squash(body) + '`: ' + why + ' (' + loc.path + ')');
  }
  // And a line number written outside a span, in a sentence or a comment.
  const bare = pageText.replace(/`[^`]+`/g, function (s) { return s.replace(/[^\n]/g, ' '); });
  const bareRx = /[\w.-]+\.ps1:\d[\d,-]*/gi;
  while ((m = bareRx.exec(bare)) !== null) {
    count++;
    found.push(where + ':' + bare.slice(0, m.index).split('\n').length + ' ' + m[0] + ' cites line numbers outside a span; cite what the script says there instead');
  }
  return { found: found, count: count };
}

// ------------------------------------------------------------ 1-3. the pages
const cache = {};
function textOf(rel) {
  if (!(rel in cache)) cache[rel] = read(path.join(ROOT, rel));
  return cache[rel];
}
let total = 0;
pages.forEach(function (p) {
  const t = read(path.join(ROOT, p));
  if (t === null) { yes(p + ' can be read', false); return; }
  const r = check(t.replace(/\r\n/g, '\n'), p, scripts, textOf);
  total += r.count;
  r.found.forEach(function (f) { console.log('      ' + f); });
  if (r.count) yes(p + ': every one of its ' + r.count + ' script citations names what the script still holds, by name', r.found.length === 0);
});
yes('the pages cite scripts this way at least 50 times, ' + total + ' of them', total >= 50);

// ------------------------------------------------------------ 4. teeth
{
  const fake = {
    'scripts/deploy/Make-Thing.ps1': [
      '<#',
      '  Make-Thing.ps1',
      '',
      '  Puts the thing on the box, five times a',
      '  second, over loopback.',
      '#>',
      'param(',
      "  [string]$Root = 'C:\\Thornswood-Thing',",
      '  [int]$Port    = 7790',
      ')',
      'function Get-ThingAddress { return $Root }',
      '$checks = @()',
      'if ($checks == $null) { }'
    ].join('\n'),
    'scripts/vps/Same.ps1': 'function A { }',
    'scripts/deploy/Same.ps1': 'function B { }'
  };
  const list = Object.keys(fake);
  function run(span) { return check('x `' + span + '` y', 'page.md', list, function (r) { return fake[r]; }).found; }
  function refused(span) { return run(span).length === 1; }

  yes('a line number is refused: `Make-Thing.ps1:9`', refused('Make-Thing.ps1:9'));
  yes('so is a range with a list: `Make-Thing.ps1:9-10,12`', refused('Make-Thing.ps1:9-10,12'));
  yes('a function that is declared passes: `Make-Thing.ps1:Get-ThingAddress`', run('Make-Thing.ps1:Get-ThingAddress').length === 0);
  yes('one renamed away fails: `Make-Thing.ps1:Get-ThingAddr`', refused('Make-Thing.ps1:Get-ThingAddr'));
  yes('a variable given a value passes: `Make-Thing.ps1:$checks`', run('Make-Thing.ps1:$checks').length === 0);
  yes('one only compared, never given a value, fails: `Make-Thing.ps1:$null`', refused('Make-Thing.ps1:$null'));
  yes("its own words pass, with the spaces as the page has them: `Make-Thing.ps1:$Root = 'C:\\Thornswood-Thing'`",
      run("Make-Thing.ps1:$Root = 'C:\\Thornswood-Thing'").length === 0 && run('Make-Thing.ps1:$Port = 7790').length === 0);
  yes('and a header sentence that wraps there passes on one line here: `Make-Thing.ps1:five times a second, over loopback`',
      run('Make-Thing.ps1:five times a second, over loopback').length === 0);
  yes("a value the script no longer has fails: `Make-Thing.ps1:$Root = 'C:\\Thornswood-Other'`",
      refused("Make-Thing.ps1:$Root = 'C:\\Thornswood-Other'"));
  yes('a script that is not there fails: `Gone.ps1:Get-ThingAddress`', refused('Gone.ps1:Get-ThingAddress'));
  yes('a file name two scripts have fails without its folder: `Same.ps1:A`', refused('Same.ps1:A'));
  yes('and passes with it: `scripts\\vps\\Same.ps1:A`', run('scripts\\vps\\Same.ps1:A').length === 0);
  yes('with the wrong folder it fails: `scripts\\deploy\\Same.ps1:A`', refused('scripts\\deploy\\Same.ps1:A'));
  yes('a span that runs a script is not a citation: `Make-Thing.ps1 -Install`', run('Make-Thing.ps1 -Install').length === 0);
  {
    const r = check('a\n<!-- address: Make-Thing.ps1:39, Same.ps1:2 -->\n', 'page.md', list, function (x) { return fake[x]; });
    yes('line numbers outside a span are refused too, each one: ' + r.found.length, r.found.length === 2 && r.found[0].indexOf('page.md:2 ') === 0);
  }
  {
    const fenced = 'a\n```powershell\n.\\Make-Thing.ps1 `\n  -Root x\n```\nb `Make-Thing.ps1:9` c\n';
    const r = check(fenced, 'page.md', list, function (x) { return fake[x]; });
    yes('a fenced block with a backtick in it does not hide the span after it, and the line is right: ' + r.found.join(' | '),
        r.count === 1 && r.found.length === 1 && r.found[0].indexOf('page.md:6 ') === 0);
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
