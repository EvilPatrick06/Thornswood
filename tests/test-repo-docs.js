// test-repo-docs.js
//
// The documents a stranger meets first describe Thornswood, not the product
// this repository used to be.
//
// WHY THIS EXISTS. Entry 193 on the To Do List: README.md was the first page
// of the repository and still described Skyrim Together. It promised an
// install with "No Nexus account, no Vortex" while the join page says the
// collection in Vortex is required, told people the password was in Discord
// when the build carries it, described an F2 party menu that no plugin binds,
// sent problems to one named person, and broke the repo's own rule against em
// dashes five times. installer\READ ME FIRST.txt was worse, because it is not a
// leftover: Package-Thornswood.ps1 copies it into every installer, and it
// opened with "SKYRIM TOGETHER", named SkyrimTogether-Setup.exe and told a new
// customer to ask in the Discord for a password. config.example.json still
// pointed at the old box (192.135.119.166, port 25565) and the old product's
// update repository. SETUP.md walked a reader through making a repository
// called skyrim-together, a personal access token and a build script that
// does not exist, and CLAUDE.md and DEVELOPING.md both sent people to it.
//
// So this reads those three and fails on the old product, on the words the
// repo does not use, on a Google Drive link anywhere, and on an example config
// that has drifted away from what Config.cs actually defaults to. It also
// fails if SETUP.md comes back into the tree or either document lists it
// again.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.join(TOOLS_DIR, '..');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function read(rel) {
  try { return fs.readFileSync(path.join(ROOT, rel), 'utf8').replace(/^﻿/, ''); }
  catch (e) { return null; }
}

// What every document a person reads has to keep clear of.
const EM_DASH = /—/;
const OLD_NAME = /skyrim\s*together/i;
const PLAYER = /\bplayers?\b/i;
// A link, not the words: docs/archive/WORKING-NOTES.md quotes the search that looks for it.
const DRIVE = /:\/\/drive\.google\.com/i;
// Problems go to the Discord or the report page, never to one person by name.
const PERSON = /\b(Patrick|Gavin)\b/;

function where(text, rx) {
  const lines = text.split(/\r?\n/);
  const hits = [];
  for (let i = 0; i < lines.length; i++) if (rx.test(lines[i])) hits.push(':' + (i + 1));
  return hits.length ? ' (found at' + hits.join(',') + ')' : '';
}

function clean(label, text) {
  yes(label + ' does not name the old product' + where(text, OLD_NAME), !OLD_NAME.test(text));
  yes(label + ' has no em dash' + where(text, EM_DASH), !EM_DASH.test(text));
  yes(label + ' never says player' + where(text, PLAYER), !PLAYER.test(text));
  yes(label + ' carries no Google Drive link' + where(text, DRIVE), !DRIVE.test(text));
  yes(label + ' sends nobody to one person by name' + where(text, PERSON), !PERSON.test(text));
}

// ---------------------------------------------------------------- README.md
const readme = read('README.md');
yes('README.md is there', readme !== null);
if (readme !== null) {
  clean('README.md', readme);
  yes('README.md is titled Thornswood', /^# Thornswood\s*$/m.test(readme.split(/\r?\n/)[0]));
  // The install story is the site's job. The last one written here went
  // stale against join.md and nobody noticed, so this one points instead.
  yes('README.md points people who want to join at thornswood.net/join',
      /https:\/\/thornswood\.net\/join/.test(readme));
  yes('README.md points developers at CONTRIBUTING.md', /\]\(CONTRIBUTING\.md\)/.test(readme));
  yes('README.md points developers at CLAUDE.md', /\]\(CLAUDE\.md\)/.test(readme));
  yes('README.md points developers at DEVELOPING.md', /\]\(DEVELOPING\.md\)/.test(readme));
  yes('README.md does not send anybody to SETUP.md, which describes the old product' + where(readme, /SETUP\.md/),
      !/SETUP\.md/.test(readme));
  yes('README.md describes no F2 party menu, which nothing binds' + where(readme, /\bF2\b/),
      !/\bF2\b/.test(readme));
  yes('README.md does not tell anybody where a password is, since the build carries it' + where(readme, /password/i),
      !/password/i.test(readme));
  yes('README.md does not promise an install without Vortex' + where(readme, /no\s+vortex/i),
      !/no\s+vortex/i.test(readme));
  const n = readme.split(/\r?\n/).length;
  yes('README.md is short and points at the long form, ' + n + ' lines', n < 60);
}

// ------------------------------------------------------ READ ME FIRST.txt
// Shipped, so it is rewritten and never deleted. Package-Thornswood.ps1 only
// prints a yellow line when it is missing and carries on, which is an
// installer with no read me that nobody notices.
const RMF = 'installer/READ ME FIRST.txt';
const pkg = read('tools/Package-Thornswood.ps1');
yes('Package-Thornswood.ps1 still copies READ ME FIRST.txt into the installer',
    pkg !== null && /foreach\s*\(\$f in [^)]*'READ ME FIRST\.txt'/.test(pkg));

let tracked = null;
try {
  tracked = execSync('git ls-files -z', { cwd: ROOT, maxBuffer: 64 * 1024 * 1024 })
    .toString('utf8').split('\0').filter(Boolean);
} catch (e) {
  console.log('SKIP  git ls-files did not answer, so the tracked-file checks are left out: ' + e.message);
}
if (tracked) yes(RMF + ' is tracked, so a fresh clone can build the installer', tracked.indexOf(RMF) >= 0);

const rmf = read(RMF);
yes(RMF + ' is there', rmf !== null);
if (rmf !== null) {
  clean(RMF, rmf);
  yes(RMF + ' names the setup program Package-Thornswood.ps1 builds, Thornswood-Setup.exe',
      /Thornswood-Setup\.exe/.test(rmf) && /Thornswood-Setup\.exe/.test(pkg || ''));
  yes(RMF + ' says the collection comes through Vortex, as join.md does',
      /Vortex/.test(rmf) && /collection/i.test(rmf));
  yes(RMF + ' names build 1.6.1170 and the launcher\'s Downgrade button',
      /1\.6\.1170/.test(rmf) && /Downgrade/.test(rmf));
  yes(RMF + ' points at the join guide on the site', /https:\/\/thornswood\.net\/join/.test(rmf));
  yes(RMF + ' does not tell anybody to ask for a password' + where(rmf, /ask[^.]*password/i),
      !/ask[^.]*password/i.test(rmf));
}

// ------------------------------------------------------ config.example.json
// Either gone or the same as what the launcher defaults to. Config.cs is the
// one place those defaults live, so the example is read against it rather
// than against numbers copied into this file.
const cfgText = read('config.example.json');
if (cfgText === null) {
  yes('config.example.json is gone, so it cannot drift', true);
} else {
  let cfg = null;
  try { cfg = JSON.parse(cfgText); } catch (e) { cfg = null; }
  yes('config.example.json is valid JSON', cfg !== null);
  const cs = read('launcher/app/Config.cs') || '';
  const m1 = /public string ServerAddress = "([^"]+)"/.exec(cs);
  const m2 = /public string ServerPort = "([^"]+)"/.exec(cs);
  const m3 = /if \(string\.IsNullOrEmpty\(UpdateRepo\)\) UpdateRepo = "([^"]+)"/.exec(cs);
  yes('Config.cs defaults can be read (address, port, update repository)', !!(m1 && m2 && m3));
  if (cfg && m1 && m2 && m3) {
    yes('config.example.json ServerAddress ' + cfg.ServerAddress + ' is the launcher default ' + m1[1],
        cfg.ServerAddress === m1[1]);
    yes('config.example.json ServerPort ' + cfg.ServerPort + ' is the launcher default ' + m2[1],
        String(cfg.ServerPort) === m2[1]);
    yes('config.example.json UpdateRepo ' + cfg.UpdateRepo + ' is the launcher default ' + m3[1],
        cfg.UpdateRepo === m3[1]);
  }
  yes('config.example.json carries an empty UpdateToken, never a real one',
      cfg !== null && cfg.UpdateToken === '');
  yes('config.example.json does not name the old product or its box',
      !/skyrim-together|25565|192\.135\.119\.166/i.test(cfgText));
}

// ------------------------------------------------------------- repo wide
if (tracked) {
  yes('tools/Message to friends.txt is not tracked', tracked.indexOf('tools/Message to friends.txt') < 0);
  // SETUP.md is deleted rather than rewritten: a customer's install is the
  // join page and a developer's machine is DEVELOPING.md, so a third
  // copy of either would only drift again, the way this one did.
  yes('SETUP.md is not tracked', tracked.indexOf('SETUP.md') < 0);
  ['CLAUDE.md', 'DEVELOPING.md'].forEach(function (rel) {
    const t = read(rel);
    yes(rel + ' is there', t !== null);
    if (t !== null) {
      yes(rel + ' does not list SETUP.md, which is gone' + where(t, /SETUP\.md/), !/SETUP\.md/.test(t));
    }
  });
  const TEXT = /\.(js|mjs|cjs|ps1|psm1|psd1|py|cs|xaml|md|json|html|htm|css|txt|yml|yaml|toml|cmd|bat|sh|ini|xml)$/i;
  const drive = [];
  tracked.filter(function (f) { return TEXT.test(f); }).forEach(function (rel) {
    const t = read(rel);
    if (t !== null && DRIVE.test(t)) drive.push(rel);
  });
  drive.forEach(function (d) { console.log('      ' + d); });
  yes('no tracked text file carries a Google Drive link', drive.length === 0);

  // The folders under tools that explain themselves were given their READMEs
  // after this one was written. The front page names each, so a folder that
  // gains one later without a mention here shows up rather than going unread.
  if (readme !== null) {
    tracked.filter(function (f) { return /^tools\/[^\/]+\/README\.md$/.test(f); }).forEach(function (f) {
      const dir = f.replace(/\/README\.md$/, '');
      yes('README.md names ' + dir + ', which has a README of its own', readme.indexOf('`' + dir + '`') >= 0);
    });
  }
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
