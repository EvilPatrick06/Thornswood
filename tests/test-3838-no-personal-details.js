// test-3838-no-personal-details.js
//
//     node tests/test-3838-no-personal-details.js
//
// No tracked file names a personal mail address or a Windows profile
// account name.
//
// WHY THIS EXISTS. Issue #3838, found by the #3684 history scan on 26 Oct
// 2026. Files written on One carried the real paths and addresses they were
// written with: a personal Gmail as Caddy's ACME contact, a profile path in
// a doc, in a provenance record and in two tests' data, and two sign-in
// addresses in Developer-Guide.md. The repository is going public (#3721),
// and the history rewrite (#3684) cleans these out of old versions only once
// main itself is clean. Nothing on main refused them, so each one was fixed
// by hand after somebody happened to look, and the next file written on One
// would have brought one back.
//
// WHAT COUNTS. Read off every tracked text file:
//   - an address at a personal mail provider (Gmail, Outlook, Hotmail, Live,
//     Yahoo, iCloud, Proton, AOL) or a school (.edu);
//   - a Microsoft tenant name (<name>.onmicrosoft.com), which is made from
//     the address of whoever opened the tenant;
//   - a profile path, C:\Users\<account>\ in any of its spellings
//     (C:/Users/, C:\\Users\\, /c/Users/, /mnt/c/Users/, and a Mac's
//     /Users/), whose account is not a placeholder or one of the box's own
//     service accounts.
// Write C:\Users\<you>\..., %USERPROFILE%, $env:USERPROFILE or a role
// address instead.
//
// WHAT IS LEFT ALONE, AND WHY.
//   - records/client-licences/ and records/front-licences/: third-party
//     licence texts keep their authors' notices word for word, as the
//     licences require.
//   - the same notice lines copied into our own source: a line that is,
//     past its comment marks, word for word a line of one of those texts
//     that holds an address. zlib's licence says its notice "may not be
//     removed or altered from any source distribution", and
//     launcher/app/FromGameDeflate.cs, zlib translated into C#, carries it
//     with its authors' addresses (#3668). Any other address in that file,
//     or the same address on a line of its own, is still found.
//   - tests/fixtures/ui-front-build.js: a third-party webpack build, kept
//     as its authors built it (#3761); the profile path in it is one of
//     theirs, from their own machine.
//   - WAITING below: files that already hold one and leave main or change
//     by the issue named beside them. An entry whose file is clean or gone
//     fails this check, so the list only gets shorter: take the line out in
//     the same change that cleans the file.
//
// Read only. Runs on Windows and Linux.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const REPO_DIR = path.join(__dirname, '..'); // the tests are in tests\, the repository is one folder up

const WAITING = [];
const LEFT_ALONE = [/^records\/client-licences\//, /^records\/front-licences\//, /^tests\/fixtures\/ui-front-build\.js$/];

// Every line of a recorded licence text (the client's and the site's
// front build's) that holds an address, with its
// spacing collapsed, so a notice copied into a source comment is known.
const LIC_DIRS = ['client-licences', 'front-licences'].map((d) => path.join(REPO_DIR, 'records', d));
const flatLine = (l) => l.replace(/^\s*(?:\/\/+|#+|\*+|;+|--)?/, '').replace(/\s+/g, ' ').trim();
const NOTICE_LINES = new Set();
for (const dir of LIC_DIRS) {
  for (const n of (fs.existsSync(dir) ? fs.readdirSync(dir) : [])) {
    for (const l of fs.readFileSync(path.join(dir, n), 'utf8').split(/\r?\n/)) if (/@/.test(l)) NOTICE_LINES.add(flatLine(l));
  }
}

const MAIL_DOMAIN = /^(?:gmail\.com|googlemail\.com|outlook\.[a-z.]+|hotmail\.[a-z.]+|live\.[a-z.]+|msn\.com|yahoo\.[a-z.]+|ymail\.com|icloud\.com|me\.com|mac\.com|proton\.me|protonmail\.[a-z.]+|aol\.com|(?:[a-z0-9-]+\.)+edu)$/i;
const MAIL = /[A-Za-z0-9._%+-]+@((?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,})/g;
const TENANT = /\b[A-Za-z0-9-]+\.onmicrosoft\.com\b/gi;
// The drive (or Git Bash's /c, WSL's /mnt/c), a separator, Users, a
// separator, then the account, up to the next separator, quote or space;
// or a Mac's /Users/<account>, with a capital U, so a web API's /users/@me
// is not one.
const ACCOUNT = '([^\\\\/\\s"\'`<>|:*?,;()\\[\\]{}@]+)';
const PROFILE = [
  new RegExp('(?:\\b[A-Za-z]:|/mnt/[a-z]|(?:^|[\\s"\'`(=])/[a-z])(?:\\\\\\\\|\\\\|/)[Uu]sers(?:\\\\\\\\|\\\\|/)' + ACCOUNT, 'g'),
  new RegExp('(?:^|[\\s"\'`(=])/Users/' + ACCOUNT, 'g'),
];
// Accounts every Windows machine has, the box's own service and runner
// accounts (scripts\vps\Install-Runner.ps1, ServiceAccount.ps1), the two
// made-up names tests use (x, tester), and %USERNAME% or $env:USERNAME.
// <you> and <account> never match the account pattern above at all.
const ACCOUNT_OK = /^(?:you|Public|Default|Default User|All Users|Administrator|runneradmin|x|tester|thornswood-[A-Za-z0-9.<>-]*|[$%].*)$/i;

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// The findings in one file's text: what kind, the line and the column. The
// value itself is not printed, so a finding never reaches a build log.
function findings(text) {
  const out = [];
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    let m;
    MAIL.lastIndex = 0;
    const notice = NOTICE_LINES.has(flatLine(l));
    while ((m = MAIL.exec(l))) if (MAIL_DOMAIN.test(m[1]) && !notice) out.push({ kind: 'a personal mail address', line: i + 1, col: m.index + 1 });
    TENANT.lastIndex = 0;
    while ((m = TENANT.exec(l))) out.push({ kind: 'a Microsoft tenant name', line: i + 1, col: m.index + 1 });
    for (const re of PROFILE) {
      re.lastIndex = 0;
      while ((m = re.exec(l))) if (!ACCOUNT_OK.test(m[1])) out.push({ kind: 'a profile account name', line: i + 1, col: m.index + 1 });
    }
  }
  return out;
}

// ------------------------------------------------- the patterns themselves ---
// Planted lines, each built from pieces so this file holds no value itself.
const at = '@';
const bs = String.fromCharCode(92);
const ms = '.onmicro' + 'soft.com';
const U = 'Users';
const plant = (s) => findings(s).length;
yes('a Gmail address is found', plant('email someone' + at + 'gmail.com') === 1);
yes('  and an Outlook one', plant('it names someone' + at + 'outlook.com and') === 1);
yes('  and a school one', plant('a' + at + 'student.example.edu') === 1);
yes('  and a tenant name, with or without an address', plant('domain `someone' + ms + '`') === 1 && plant('x' + at + 'someone' + ms) === 1);
yes('  but not a role address, a noreply or a .invalid one', plant('a' + at + 'thornswood.net b' + at + 'users.noreply.github.com c' + at + 'thornswood.invalid') === 0);
yes('the recorded licence texts give their notice lines (' + NOTICE_LINES.size + ')', NOTICE_LINES.size > 0);
const zlibAuthors = [...NOTICE_LINES].filter((l) => /caltech\.edu/.test(l))[0] || '';
yes('  a licence\'s own notice line, copied into a comment, is left alone', zlibAuthors !== '' && plant('//   ' + zlibAuthors.replace(/ /g, '        ')) === 0);
yes('  but its address on a line of its own is still found', plant('// mail ' + zlibAuthors.split(' ').pop()) === 1);
yes('a profile path is found', plant('C:' + bs + 'Users' + bs + 'someone' + bs + 'Downloads') === 1);
yes('  and with forward slashes, doubled backslashes, Git Bash and WSL', plant('C:/' + U + '/someone/x') === 1 && plant("'C:" + bs + bs + 'Users' + bs + bs + "someone'") === 1 && plant('cd /c/' + U + '/someone/x') === 1 && plant('/mnt/c/' + U + '/someone/x') === 1 && plant('"/' + U + '/someone/github/x"') === 1);
yes('  but not a placeholder or the box\'s own accounts', plant('C:' + bs + 'Users' + bs + '<you>' + bs + 'x C:' + bs + 'Users' + bs + 'Administrator' + bs + 'x C:' + bs + 'Users' + bs + 'thornswood-runner5' + bs + 'x C:' + bs + 'Users' + bs + '%USERNAME%') === 0);
yes('  nor a web address with Users in it', plant('https://github.com/users/someone/projects/1') === 0);

// ------------------------------------------------------- the tracked files ---
let files = [];
try {
  files = execFileSync('git', ['-C', REPO_DIR, 'ls-files', '-z'], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }).split('\0').filter(Boolean);
} catch (e) {
  console.log('git ls-files failed: ' + e.message);
}
yes('the tracked files are listed (' + files.length + ')', files.length > 100);

const waiting = new Map(WAITING);
const found = new Map();
let read = 0;
for (const rel of files) {
  if (LEFT_ALONE.some((r) => r.test(rel))) continue;
  const full = path.join(REPO_DIR, rel);
  let buf;
  try {
    if (!fs.statSync(full).isFile()) continue; // a submodule
    buf = fs.readFileSync(full);
  } catch (e) { continue; }
  if (buf.subarray(0, 8000).includes(0)) continue; // binary
  read++;
  const f = findings(buf.toString('utf8').split('\r').join(''));
  if (f.length) found.set(rel, f);
}
yes('the text files are read (' + read + ')', read > 100);

const unexpected = [...found.keys()].filter((rel) => !waiting.has(rel));
yes('no tracked file names a personal address or profile account' + (unexpected.length ? ':' : ''), unexpected.length === 0);
for (const rel of unexpected) {
  for (const f of found.get(rel)) console.log('        ' + rel + ':' + f.line + ':' + f.col + '  ' + f.kind);
}
if (unexpected.length) console.log('      Write C:' + bs + 'Users' + bs + '<you>' + bs + '..., %USERPROFILE%, $env:USERPROFILE or a role address instead.');

for (const [rel, why] of WAITING) {
  const still = found.has(rel);
  yes(rel + ' still waits on ' + why + (still ? '' : ': it is clean or gone now, so take its line out of WAITING in this file'), still);
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
