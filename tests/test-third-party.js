// test-third-party.js
//
// THIRD-PARTY.md names what Thornswood hands out that somebody else wrote, and
// the public credits page carries the directions to the source. This holds
// both to the build, so neither can drift away from what actually ships.
//
// From the To Do List, entry 171: "There is no licence on this project and no
// third-party notices file anywhere." Its done-when asks that every /resource:
// in Build-Launcher.ps1 and every file under launcher\lib be "either the project's
// own or listed by name and licence", and it asks for that cross-check to be
// made "mechanically rather than by memory". This is that check.
//
// It also keeps the source offer honest. The GPL (section 6) and the AGPL
// (section 13) want the directions to lead to the source of what actually
// ships. When New-ClientBuildRecord.ps1 or New-ServerBuildRecord.ps1 records a
// new fork commit, this fails until THIRD-PARTY.md and credits.md name it.
// tests\test-one-engine.js holds the engine\skymp pin to those two records, so
// the pin, the records and both pages name one commit. It runs in the build
// check on every pull request since #1720. Run only at night, it let one pull
// request after another move the pin and the records on 3 and 4 October
// (#1568 to #1573) while THIRD-PARTY.md kept naming d6c99400, and nothing on
// those pull requests said so; #1689 put both pages right.
//
// Measured when it was written, on 24 September: the three WebView2 files are
// byte for byte Microsoft.Web.WebView2 1.0.2903.40 from nuget.org, the six
// client files in the game folder match client-build.json, and
// MpClientPlugin.dll is built from skymp5-server, which is AGPL, not GPL.
//
// Where a clone of the fork that holds the recorded commit is on this machine
// (engine\skymp, C:\Thornswood-Dev\skymp, or THORNSWOOD_SKYMP), it also reads each
// subproject's LICENSE and package.json at that commit, and the build files
// that say which subproject each client file comes from. On a runner without
// the fork those lines say SKIP and the rest still runs.
//
// The same goes for the Thornswood Client Runtime, Thornswood's own mod on
// Nexus Mods: where Vortex's copy of it is here (%APPDATA%\Vortex\skyrimse\mods,
// or THORNSWOOD_VORTEX_MODS), every file in it is held to its section, and
// where the launcher's Profile\OwnGame\files.txt is here (C:\Thornswood\Profile,
// or THORNSWOOD_PROFILE), so is every file the collection puts under
// Data\Platform\Distribution.
//
// Read only.
'use strict';
const REPO_DIR = require('path').join(__dirname, '..'); // the tests are in tests\, the repository is one folder up
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const ROOT = REPO_DIR;
const REPO = REPO_DIR;
const CR = String.fromCharCode(13);

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function skip(what) { console.log('SKIP  ' + what); }
function read(p) {
  try { return fs.readFileSync(p, 'utf8').split(CR).join(''); } catch (e) { return null; }
}
function flat(s) { return String(s).replace(/\s+/g, ' ').trim(); }

const noticesRaw = read(path.join(ROOT, 'THIRD-PARTY.md'));
yes('THIRD-PARTY.md exists at the repo root', noticesRaw !== null);
const N = noticesRaw || '';
const creditsRaw = read(path.join(REPO, 'site', 'data', 'site', 'credits.md'));
yes('the public credits page is there to read', creditsRaw !== null);
const C = creditsRaw || '';

// ---------------------------------------------------------------- the launcher
//
// Everything Build-Launcher.ps1 compiles into an exe, by the name it is given
// inside the exe. These are made here, each one for Thornswood:
const OURS = {
  'ui.xaml': 'the launcher window, launcher\\ui.xaml',
  'logo.png': 'the emblem, launcher\\logo.png and logo-192.png for the setup stub',
  'logo-dev.png': 'the emblem the dev build shows instead, launcher\\logo-dev.png',
  'launcher-header.jpg': 'a strip of the Thornswood backdrop, launcher\\art',
  'launcher-header.mp4': 'the same strip moving',
  'app.ico': 'the icon',
  'app-dev.ico': 'the icon the dev build\'s shortcuts carry, launcher\\app-dev.ico',
  'voice-host.html': 'the voice page, launcher',
  'Thornswood.ini': 'the key template, launcher',
  'client-build.json': 'the record of the client runtime',
  'skyrim-files.json': 'the list of the pinned Skyrim build\'s own files, read from Steam\'s depot manifests'
};

const build = read(path.join(REPO, 'scripts', 'release', 'Build-Launcher.ps1')) || '';
yes('Build-Launcher.ps1 is there to read', build.length > 0);

// The WebView2 names come out of two arrays and go in through a loop as $n,
// so they are read from the arrays rather than from the /resource: line.
const wv2 = [];
const mm = /\$wv2Managed\s*=\s*@\(([^)]*)\)/.exec(build);
if (mm) { mm[1].replace(/'([^']+)'/g, function (_, n) { wv2.push(n); return _; }); }
const ml = /\$wv2Loader\s*=\s*'([^']+)'/.exec(build);
if (ml) { wv2.push(ml[1]); }
yes('Build-Launcher.ps1 names the WebView2 files it embeds (' + wv2.join(', ') + ')', wv2.length === 3);

const resources = [];
const unreadable = [];
build.split('\n').forEach(function (line) {
  if (line.indexOf('/resource:') < 0) { return; }
  const m = /"\/resource:(.*),([^,"]+)"/.exec(line);
  if (!m) { unreadable.push(line.trim()); return; }
  const name = m[2];
  if (name.charAt(0) !== '$') { resources.push(name); return; }
  if (m[1].indexOf('$wv2Dir') >= 0) { wv2.forEach(function (n) { resources.push(n); }); return; }
  unreadable.push(line.trim());
});
unreadable.forEach(function (l) { console.log('      cannot read the name in: ' + l); });
yes('every /resource: line in Build-Launcher.ps1 has a name this can read', unreadable.length === 0);
yes('Build-Launcher.ps1 embeds resources to check (' + resources.length + ' lines)', resources.length >= 10);

const seen = {};
resources.forEach(function (name) {
  if (seen[name]) { return; }
  seen[name] = true;
  if (Object.prototype.hasOwnProperty.call(OURS, name)) {
    yes(name + ' is Thornswood\'s own (' + OURS[name] + ') and THIRD-PARTY.md says so',
        N.indexOf('`' + name + '`') >= 0);
  } else {
    yes(name + ', compiled into the launcher, is named in THIRD-PARTY.md', N.indexOf(name) >= 0);
  }
});

// ---------------------------------------------------------------- launcher\lib
//
// Every file, by name and by sha256, so a newer WebView2 dropped in without a
// word in the notices fails here.
function walk(dir, out) {
  let list = [];
  try { list = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return out; }
  list.forEach(function (d) {
    const p = path.join(dir, d.name);
    if (d.isDirectory()) { walk(p, out); } else { out.push(p); }
  });
  return out;
}
const libFiles = walk(path.join(REPO, 'launcher', 'lib'), []);
yes('launcher\\lib has files to check (' + libFiles.length + ')', libFiles.length > 0);

// The file version out of a Windows version resource: the UTF-16 key
// "FileVersion", its padding, then the value.
function fileVersion(buf) {
  const key = Buffer.from('FileVersion\u0000', 'utf16le');
  let i = buf.indexOf(key);
  while (i >= 0) {
    let j = i + key.length;
    while (j + 1 < buf.length && buf[j] === 0 && buf[j + 1] === 0) { j += 2; }
    let s = '';
    while (j + 1 < buf.length) {
      const c = buf.readUInt16LE(j);
      if (c === 0) { break; }
      s += String.fromCharCode(c);
      j += 2;
    }
    const v = /^\s*(\d+(\.\d+){1,3})/.exec(s);
    if (v) { return v[1]; }
    i = buf.indexOf(key, i + 2);
  }
  return null;
}

const versions = {};
libFiles.forEach(function (p) {
  const name = path.basename(p);
  const buf = fs.readFileSync(p);
  const sha = crypto.createHash('sha256').update(buf).digest('hex');
  yes(name + ' (launcher\\lib) is named in THIRD-PARTY.md', N.indexOf(name) >= 0);
  yes(name + ' is in THIRD-PARTY.md by its sha256, ' + sha.slice(0, 16), N.toLowerCase().indexOf(sha) >= 0);
  const v = fileVersion(buf);
  if (v) { versions[v] = (versions[v] || []).concat([name]); }
});
wv2.forEach(function (n) {
  yes(n + ', which the launcher embeds, is in launcher\\lib\\webview2',
      fs.existsSync(path.join(REPO, 'launcher', 'lib', 'webview2', n)));
});
const vList = Object.keys(versions);
yes('the WebView2 files all carry one file version (' + vList.join(', ') + ')', vList.length === 1);
if (vList.length === 1) {
  yes('THIRD-PARTY.md gives the WebView2 version, ' + vList[0], N.indexOf(vList[0]) >= 0);
  yes('the credits page gives the WebView2 version, ' + vList[0], C.indexOf(vList[0]) >= 0);
}

// The package's LICENSE.txt, Microsoft.Web.WebView2 1.0.2903.40, read out of
// the .nupkg from nuget.org on 24 September (sha256 0af8f1b807512aae...). Its
// second clause wants this notice with every binary copy, so it has to be on
// the public page as well as in the repo.
const WV2_LICENCE = [
  'Copyright (C) Microsoft Corporation. All rights reserved.',
  'Redistribution and use in source and binary forms, with or without',
  'modification, are permitted provided that the following conditions are',
  'met:',
  '* Redistributions of source code must retain the above copyright',
  'notice, this list of conditions and the following disclaimer.',
  '* Redistributions in binary form must reproduce the above',
  'copyright notice, this list of conditions and the following disclaimer',
  'in the documentation and/or other materials provided with the',
  'distribution.',
  '* The name of Microsoft Corporation, or the names of its contributors',
  'may not be used to endorse or promote products derived from this',
  'software without specific prior written permission.',
  'THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS',
  '"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT',
  'LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR',
  'A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT',
  'OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,',
  'SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT',
  'LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,',
  'DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY',
  'THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT',
  '(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE',
  'OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.'
].join('\n');
yes('THIRD-PARTY.md carries the WebView2 licence word for word', flat(N).indexOf(flat(WV2_LICENCE)) >= 0);
yes('the credits page carries the WebView2 licence word for word', flat(C).indexOf(flat(WV2_LICENCE)) >= 0);

// ---------------------------------------------------------------- the site
//
// Entry 247 (#271) moved the site's fonts and marked off Google Fonts and
// cdnjs into site\public, so since then the site hands them to every
// visitor itself. Anything there that is somebody else's by its kind, a font
// file or a minified script, has to be in THIRD-PARTY.md by name and sha256,
// so a newer marked or another font dropped in without a word fails here.
// Text is hashed with its CRs taken out: git stores it with LF, a Windows
// checkout adds them, and the hash in the notices is of what git stores.
const PUB = path.join(REPO, 'site', 'public');
function vendoredKind(n) { return /\.(woff2?|ttf|otf)$/i.test(n) || /\.min\.js$/i.test(n); }
let pubNames = [];
try { pubNames = fs.readdirSync(PUB); } catch (e) { pubNames = []; }
const siteFiles = pubNames.filter(vendoredKind);
console.log('      the site serves ' + siteFiles.length + ' font or minified script files');
siteFiles.forEach(function (n) {
  let buf = fs.readFileSync(path.join(PUB, n));
  if (/\.js$/i.test(n)) { buf = Buffer.from(buf.toString('latin1').split(CR).join(''), 'latin1'); }
  const sha = crypto.createHash('sha256').update(buf).digest('hex');
  yes(n + ' (the site) is named in THIRD-PARTY.md', N.indexOf('`' + n + '`') >= 0);
  yes(n + ' is in THIRD-PARTY.md by its sha256, ' + sha.slice(0, 16), N.toLowerCase().indexOf(sha) >= 0);
});
// And the other way: a row for a file the site no longer serves is a notice
// for something nobody is handed any more.
const siteSection = (/\n## On the site\n([\s\S]*?)\n## /.exec(N) || [])[1] || '';
yes('THIRD-PARTY.md has a section for the site', siteSection.length > 0);
siteSection.split('\n').forEach(function (l) {
  const m = /^\| `([^`]+)`/.exec(l);
  if (!m || !vendoredKind(m[1])) { return; }
  yes(m[1] + ', listed under the site, is still in site\\public', pubNames.indexOf(m[1]) >= 0);
});
const markedFile = siteFiles.filter(function (n) { return /^marked-.*\.min\.js$/i.test(n); })[0];
if (markedFile) {
  const head = (read(path.join(PUB, markedFile)) || '').slice(0, 300);
  yes(markedFile + ' still carries its own MIT notice at the top', /\(MIT Licensed\)/.test(head));
  const row = siteSection.split('\n').filter(function (l) { return l.indexOf('`' + markedFile + '`') >= 0; })[0] || '';
  yes('THIRD-PARTY.md gives ' + markedFile + ' as MIT', /\bMIT\b/.test(row));
}
siteFiles.filter(function (n) { return /\.woff2?$/i.test(n); }).forEach(function (n) {
  const row = siteSection.split('\n').filter(function (l) { return l.indexOf('`' + n + '`') >= 0; })[0] || '';
  yes('THIRD-PARTY.md gives ' + n + ' as OFL-1.1', row.indexOf('OFL-1.1') >= 0);
});
['Cinzel', 'Spectral', 'marked'].forEach(function (what) {
  yes('the credits page names ' + what + ', which the site serves', C.indexOf(what) >= 0);
});

// ---------------------------------------------------------------- the client
//
// Which subproject of the fork each recorded file is built from, and the build
// file line that proves it. MpClientPlugin.dll is the surprise: it goes to
// every client and is built out of skymp5-server.
const LICENCE_OF = {
  'skymp5-client': 'GPL-3.0',
  'skyrim-platform': 'GPL-3.0',
  'skymp5-front': 'GPL-3.0',
  'skymp5-server': 'AGPL-3.0'
};
const PLATFORM_CMAKE = 'skyrim-platform/src/platform_se/CMakeLists.txt';
const BUILT_FROM = {
  'MpClientPlugin.dll': { sub: 'skymp5-server', proof: 'skymp5-server/cpp/CMakeLists.txt', needle: 'add_library(MpClientPlugin' },
  'SkyrimPlatform.dll': { sub: 'skyrim-platform', proof: PLATFORM_CMAKE, needle: 'OUTPUT_NAME "SkyrimPlatform")' },
  'SkyrimPlatformImpl.dll': { sub: 'skyrim-platform', proof: PLATFORM_CMAKE, needle: 'OUTPUT_NAME "SkyrimPlatformImpl"' },
  'SkyrimPlatformCEF.exe.hidden': { sub: 'skyrim-platform', proof: PLATFORM_CMAKE, needle: 'add_executable(SkyrimPlatformCEF' },
  'skymp5-client.js': { sub: 'skymp5-client', proof: 'skymp5-client/CMakeLists.txt', needle: 'Plugins/skymp5-client.js' },
  'TESModPlatform.pex': { sub: 'skyrim-platform', proof: 'skyrim-platform/src/platform_se/psc/TESModPlatform.psc', needle: 'TESModPlatform' }
};
function namesLicence(text, want) {
  if (want === 'AGPL-3.0') { return text.indexOf('AGPL-3.0') >= 0; }
  return /(^|[^A])GPL-3\.0/.test(text) && text.indexOf('AGPL') < 0;
}

let cb = null;
try { cb = JSON.parse(read(path.join(REPO, 'records', 'client-build.json'))); } catch (e) { cb = null; }
yes('records\\client-build.json reads', !!(cb && cb.files && cb.forkCommit));
const cbFiles = cb && cb.files ? Object.keys(cb.files) : [];
const commit = cb ? String(cb.forkCommit || '') : '';
const forkUrl = cb ? String(cb.fork || '').replace(/\.git$/, '') : '';
if (cb) {
  yes('THIRD-PARTY.md names the fork, ' + forkUrl, forkUrl.length > 0 && N.indexOf(forkUrl) >= 0);
  yes('THIRD-PARTY.md names the fork branch, ' + cb.forkBranch, N.indexOf(String(cb.forkBranch)) >= 0);
  yes('THIRD-PARTY.md names the recorded client commit, ' + commit, commit.length >= 7 && N.indexOf(commit) >= 0);
  yes('THIRD-PARTY.md names the upstream base, ' + cb.upstreamBase, N.indexOf(String(cb.upstreamBase)) >= 0);
  yes('the credits page links the fork', C.indexOf(forkUrl) >= 0);
  yes('the credits page names the fork branch', C.indexOf(String(cb.forkBranch)) >= 0);
  yes('the credits page names the recorded client commit, ' + commit, commit.length >= 7 && C.indexOf(commit) >= 0);
  yes('the credits page names the upstream base, ' + cb.upstreamBase, !!cb.upstreamBase && C.indexOf(String(cb.upstreamBase)) >= 0);
}
yes('client-build.json records six client files', cbFiles.length === 6);

const rows = N.split('\n').filter(function (l) { return l.charAt(0) === '|'; });
cbFiles.forEach(function (rel) {
  const leaf = rel.split('\\').pop();
  const from = BUILT_FROM[leaf];
  yes(leaf + ' has a known subproject in this harness', !!from);
  const row = rows.filter(function (l) { return l.indexOf('`' + rel + '`') >= 0; })[0] || '';
  yes(rel + ' has its own row in THIRD-PARTY.md', row.length > 0);
  if (!from) { return; }
  const want = LICENCE_OF[from.sub];
  yes(leaf + ': the row says it is built from ' + from.sub, row.indexOf(from.sub) >= 0);
  yes(leaf + ': the row gives ' + want, namesLicence(row, want));
});
// On the page it is a row of the source table, which entry 170 wrote in words
// ("GNU AGPL version 3") rather than as the SPDX name, so either counts, as
// long as it is on the same line as the file.
yes('the credits page says MpClientPlugin.dll is AGPL-3.0',
    /MpClientPlugin\.dll[^\n]*(AGPL-3\.0|GNU AGPL version 3)/.test(C));
// The sentence in THIRD-PARTY.md that gives each subproject its licence, the
// same four the fork's package.json files declare (checked below where the
// fork is here).
const CLAIM = {
  'skymp5-client': '`GPL-3.0` for skymp5-client, skyrim-platform and skymp5-front',
  'skyrim-platform': '`GPL-3.0` for skymp5-client, skyrim-platform and skymp5-front',
  'skymp5-front': '`GPL-3.0` for skymp5-client, skyrim-platform and skymp5-front',
  'skymp5-server': '`AGPL-3.0` for skymp5-server'
};
// The public page may use the name people know a part by instead of its folder.
const SPOKEN = { 'skyrim-platform': 'Skyrim Platform' };
Object.keys(LICENCE_OF).forEach(function (sub) {
  yes('THIRD-PARTY.md gives ' + sub + ' as ' + LICENCE_OF[sub], flat(N).indexOf(CLAIM[sub]) >= 0);
  yes('the credits page names ' + sub,
      C.indexOf(sub) >= 0 || (!!SPOKEN[sub] && C.indexOf(SPOKEN[sub]) >= 0));
});

// ---------------------------------------------------------------- the server
//
// The record is written by New-ServerBuildRecord.ps1. Windows PowerShell's
// -Encoding UTF8 puts a byte order mark in front of the file, which PowerShell
// reads back happily and JSON.parse will not read at all. The record of
// 26 September went to GitHub that way, so this file read nothing out of it and
// the four lines below, which are what hold THIRD-PARTY.md and the credits page
// to the server commit that is live, quietly stopped running. The mark is
// checked on its own line so the next one says what it is rather than only that
// the file did not read. The writer uses UTF8Encoding($false) now, the same as
// New-ClientBuildRecord.ps1.
const sbText = read(path.join(REPO, 'records', 'server-build.json'));
yes('records\\server-build.json has no byte order mark in front of it', !!sbText && sbText.charCodeAt(0) !== 0xFEFF);
let sb = null;
try { sb = JSON.parse(sbText); } catch (e) { sb = null; }
yes('records\\server-build.json reads', !!(sb && sb.source && sb.source.commit));
if (sb && sb.source) {
  const sc = String(sb.source.commit);
  yes('THIRD-PARTY.md names the server binary, ' + sb.binary, N.indexOf(String(sb.binary)) >= 0);
  yes('THIRD-PARTY.md names the server commit, ' + sc.slice(0, 12), N.indexOf(sc) >= 0);
  yes('the credits page names the server commit, ' + sc.slice(0, 12), C.indexOf(sc) >= 0);
  yes('the server is built from the fork THIRD-PARTY.md names',
      String(sb.source.repo).replace(/\.git$/, '') === forkUrl);
}

// #1782. The commit above was found anywhere in the file, so when #1689 moved
// the pin to a247ef27 and wrote it into the fork section, "On our servers" and
// the source offer in "Where the source is" kept naming #1617's e6534129 and
// this stayed green. Each of the three is held to the record on its own now.
// The offer is what section 13 of the AGPL asks for: the source of the server
// people connect to.
if (sb && sb.source) {
  const sc = String(sb.source.commit);
  const forkSec = section('The SkyMP client runtime, built from the fork');
  yes('the fork section names the server record\'s commit, ' + sc.slice(0, 12), forkSec.indexOf(sc) >= 0);
  const ours = section('On our servers');
  yes('"On our servers" names the server record\'s commit, ' + sc.slice(0, 12), ours.indexOf(sc) >= 0);
  yes('"On our servers" gives the server record\'s SHA256, ' + String(sb.sha256).slice(0, 12),
      !!sb.sha256 && ours.indexOf(String(sb.sha256)) >= 0);
  const otherSums = (ours.match(/\b[0-9a-f]{64}\b/g) || []).filter(function (h) { return h !== sb.sha256; });
  yes('"On our servers" gives no other SHA256 (' + (otherSums.join(', ') || 'none') + ')', otherSums.length === 0);
  yes('"On our servers" gives when it was built, ' + sb.builtUtc,
      !!sb.builtUtc && ours.indexOf(String(sb.builtUtc)) >= 0);
  const mainAt = /Main remains on `([0-9a-f]{40})`/.exec(ours);
  const offer = section('Where the source is');
  const trees = [];
  const treeRe = new RegExp(reEscape(forkUrl) + '/tree/([0-9a-f]{7,40})(?=\\s)', 'g');
  let tm;
  while ((tm = treeRe.exec(offer)) !== null) { trees.push(tm[1]); }
  yes('"Where the source is" links the fork at the server record\'s commit first (' + (trees[0] || 'none') + ')',
      trees[0] === sc);
  const stray = trees.filter(function (c) { return c !== sc && !(mainAt && c === mainAt[1]); });
  yes('and at no commit but that one and the one "On our servers" says main is on (' +
      (stray.join(', ') || 'none other') + ')', stray.length === 0);
}

// ---------------------------------------------------------------- the fork
//
// Only where the fork is cloned here and holds the recorded commit. This is
// what makes the licence column a measurement rather than a memory.
// The engine/skymp submodule once it has files in it, and the old clone until
// then: the same rule as scripts\release\Where.ps1.
const REPO_FORK = path.join(REPO_DIR, 'engine', 'skymp');
const FORK = process.env.THORNSWOOD_SKYMP ||
  (fs.existsSync(path.join(REPO_FORK, 'CMakeLists.txt')) ? REPO_FORK : 'C:\\Thornswood-Dev\\skymp');
function git(args) {
  return execFileSync('git', ['-C', FORK].concat(args),
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024 }).split(CR).join('');
}
let haveFork = false;
if (commit && fs.existsSync(FORK)) {
  try { git(['cat-file', '-e', commit + '^{commit}']); haveFork = true; } catch (e) { haveFork = false; }
}
if (!haveFork) {
  skip('no clone of the fork holding ' + (commit || 'the recorded commit') + ' at ' + FORK + ', so the licence files were not read');
} else {
  Object.keys(LICENCE_OF).forEach(function (sub) {
    const want = LICENCE_OF[sub];
    let lic = '', pkg = null;
    try { lic = git(['show', commit + ':' + sub + '/LICENSE']); } catch (e) { lic = ''; }
    try { pkg = JSON.parse(git(['show', commit + ':' + sub + '/package.json'])); } catch (e) { pkg = null; }
    const head = want === 'AGPL-3.0' ? 'GNU AFFERO GENERAL PUBLIC LICENSE' : 'GNU GENERAL PUBLIC LICENSE';
    const first = lic.split('\n').map(function (s) { return s.trim(); }).filter(Boolean);
    yes(sub + '/LICENSE at ' + commit + ' is the ' + head + ' version 3',
        first[0] === head && /^Version 3,/.test(first[1] || ''));
    yes(sub + '/package.json at ' + commit + ' declares ' + want, !!pkg && pkg.license === want);
  });
  Object.keys(BUILT_FROM).forEach(function (leaf) {
    const from = BUILT_FROM[leaf];
    let text = '';
    try { text = git(['show', commit + ':' + from.proof]); } catch (e) { text = ''; }
    yes(leaf + ' is built from ' + from.sub + ': ' + from.proof + ' has ' + from.needle,
        text.indexOf(from.needle) >= 0);
  });
  let tpl = '';
  try { tpl = git(['show', commit + ':THIRD_PARTY_LICENSES']); } catch (e) { tpl = ''; }
  ['TiltedUI', 'TiltedCore', 'TiltedHooks', 'TiltedReverse'].forEach(function (lib) {
    yes(lib + ' is in upstream\'s THIRD_PARTY_LICENSES and in THIRD-PARTY.md',
        tpl.indexOf(lib) >= 0 && N.indexOf(lib) >= 0);
  });
}

// ---------------------------------------------------------------- Nexus Mods
//
// Two of the collection's mods are Thornswood's own uploads. One of them, the
// Thornswood Client Runtime (Nexus 192762), is the largest thing somebody else
// wrote that Thornswood hands out: 68 files of CEF, Chromium, ANGLE, ICU, Node,
// Microsoft's shader compiler and one Skyrim Platform script, about 349 MB.
// THIRD-PARTY.md once filed all of it under "Not shipped by Thornswood", and
// nothing here noticed, because this harness looked no further than the
// launcher, launcher\lib, the site and the six client files. So the section on
// that mod is held to the mod itself where Vortex's copy is on this machine,
// and to the launcher's record of where each game file came from.
function section(title) {
  const at = N.indexOf('\n## ' + title);
  if (at < 0) { return ''; }
  const next = N.indexOf('\n## ', at + 4);
  return next < 0 ? N.slice(at) : N.slice(at, next);
}
function commas(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
function reEscape(s) { return String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }
const RUNTIME_ID = '192762';
const CONTENT_ID = '192001';
const runtimeSec = section('Thornswood Client Runtime');
const runtimeFlat = flat(runtimeSec);
const reachSec = section('How it reaches people');
const notShipped = section('Not shipped by Thornswood');
const sourceSec = section('Where the source is');
const missingSec = section('What is still missing');
yes('THIRD-PARTY.md has a section for the Thornswood Client Runtime', runtimeSec.length > 0);
yes('that section links its Nexus page, mod ' + RUNTIME_ID, runtimeSec.indexOf('/mods/' + RUNTIME_ID) >= 0);
yes('THIRD-PARTY.md has a section for Thornswood Content, mod ' + CONTENT_ID,
    section('Thornswood Content').indexOf('/mods/' + CONTENT_ID) >= 0);
yes('"How it reaches people" names Nexus Mods and both of Thornswood\'s mods there',
    reachSec.indexOf('Nexus Mods') >= 0 && reachSec.indexOf(RUNTIME_ID) >= 0 && reachSec.indexOf(CONTENT_ID) >= 0);
yes('THIRD-PARTY.md has a "Not shipped by Thornswood" section', notShipped.length > 0);
['libcef', 'libnode', 'Distribution'].forEach(function (w) {
  yes('"Not shipped by Thornswood" does not claim ' + w, notShipped.indexOf(w) < 0);
});
yes('"What is still missing" does not say nothing hands a person the GPL text',
    missingSec.length > 0 && !/nothing hands a person the GPL/i.test(flat(missingSec)));
yes('"What is still missing" says the installer hands AGPL-3.0.txt',
    /installer also hands[\s\S]{0,200}AGPL-3\.0\.txt/.test(missingSec));
yes('installer/licences/AGPL-3.0.txt exists', (function () {
  try { return fs.statSync(path.join(ROOT, 'installer', 'licences', 'AGPL-3.0.txt')).isFile(); } catch (e) { return false; }
})());
yes('installer/licences/GPL-3.0.txt exists', (function () {
  try { return fs.statSync(path.join(ROOT, 'installer', 'licences', 'GPL-3.0.txt')).isFile(); } catch (e) { return false; }
})());
yes('installer/licences/WebView2-LICENSE.txt exists', (function () {
  try { return fs.statSync(path.join(ROOT, 'installer', 'licences', 'WebView2-LICENSE.txt')).isFile(); } catch (e) { return false; }
})());
const polyRows = runtimeSec.split('\n').filter(function (l) {
  return l.charAt(0) === '|' && l.indexOf('`___systemPolyfill.js`') >= 0;
});
yes('the Client Runtime section gives ___systemPolyfill.js as GPL-3.0',
    polyRows.some(function (l) { return /(^|[^A])GPL-3\.0/.test(l) && l.indexOf('AGPL') < 0; }));
const polySrc = new RegExp(reEscape(forkUrl) + '/tree/([0-9a-f]{40})/skyrim-platform/tools/system_polyfill').exec(sourceSec);
yes('"Where the source is" gives a commit of the fork that still has ___systemPolyfill.js', !!(forkUrl && polySrc));
yes('the credits page names the Thornswood Client Runtime and links its Nexus page',
    C.indexOf('Thornswood Client Runtime') >= 0 && C.indexOf('/mods/' + RUNTIME_ID) >= 0);
yes('the credits page names ___systemPolyfill.js and its licence',
    /___systemPolyfill\.js[\s\S]{0,200}GNU GPL version 3/.test(C));

// The polyfill's source, where the fork is here: the commit named for it has
// the same script, the recorded commit no longer has it, and the licence text
// the mod carries is skyrim-platform's own.
const POLY = 'skyrim-platform/tools/system_polyfill';
let polyUpstream = null;
let spLicence = null;
if (haveFork && polySrc) {
  try { polyUpstream = git(['show', polySrc[1] + ':' + POLY + '/dist/___systemPolyfill.js']); } catch (e) { polyUpstream = null; }
  try { spLicence = git(['show', polySrc[1] + ':skyrim-platform/LICENSE']); } catch (e) { spLicence = null; }
  yes('the fork at ' + polySrc[1].slice(0, 8) + ' has ' + POLY + '/src/___systemPolyfill.ts', (function () {
    try { git(['cat-file', '-e', polySrc[1] + ':' + POLY + '/src/___systemPolyfill.ts']); return true; } catch (e) { return false; }
  })());
  yes('the fork at the recorded commit no longer has ' + POLY, (function () {
    try { git(['cat-file', '-e', commit + ':' + POLY]); return false; } catch (e) { return true; }
  })());
} else {
  skip('no fork here to read ___systemPolyfill.js\'s source commit in');
}

// Vortex's copy of the mod. The newest one Vortex holds is the one read; an
// older upload than the notices describe is a machine that has not caught up,
// and says SKIP, while a newer one fails until the notices describe it.
const VORTEX_MODS = process.env.THORNSWOOD_VORTEX_MODS ||
  path.join(process.env.APPDATA || '', 'Vortex', 'skyrimse', 'mods');
function versionOf(s) { return String(s).split('.').map(function (x) { return parseInt(x, 10) || 0; }); }
function compareVersions(a, b) {
  const x = versionOf(a), y = versionOf(b);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    if ((x[i] || 0) !== (y[i] || 0)) { return (x[i] || 0) < (y[i] || 0) ? -1 : 1; }
  }
  return 0;
}
let runtimeDir = null, runtimeVer = null;
try {
  fs.readdirSync(VORTEX_MODS).forEach(function (n) {
    const m = new RegExp('^Thornswood Client Runtime ' + RUNTIME_ID + ' (\\d+(?:\\.\\d+)*) ').exec(n);
    if (m && (runtimeVer === null || compareVersions(m[1], runtimeVer) > 0)) {
      runtimeVer = m[1]; runtimeDir = path.join(VORTEX_MODS, n);
    }
  });
} catch (e) { runtimeDir = null; }
const notedVer = (/version (\d+(?:\.\d+)*), file \d+/.exec(runtimeFlat) || [])[1] || null;
yes('the Client Runtime section gives the version and file it describes', !!notedVer);
if (!runtimeDir) {
  skip('no copy of the Thornswood Client Runtime in ' + VORTEX_MODS + ', so its files were not read');
} else if (notedVer && compareVersions(runtimeVer, notedVer) < 0) {
  skip('Vortex here holds the Client Runtime ' + runtimeVer + ', older than the ' + notedVer + ' THIRD-PARTY.md describes');
} else {
  yes('THIRD-PARTY.md describes the Client Runtime Vortex holds here, ' + runtimeVer,
      !!notedVer && compareVersions(runtimeVer, notedVer) === 0);
  const dist = path.join(runtimeDir, 'Platform', 'Distribution');
  const modFiles = walk(dist, []);
  const rel = function (p) { return path.relative(dist, p).split(path.sep).join('\\'); };
  let bytes = 0;
  modFiles.forEach(function (p) { bytes += fs.statSync(p).size; });
  yes('the section gives the file count, ' + modFiles.length + ' files', runtimeFlat.indexOf(modFiles.length + ' files') >= 0);
  yes('the section gives the size, ' + commas(bytes) + ' bytes', runtimeFlat.indexOf(commas(bytes) + ' bytes') >= 0);
  const locales = modFiles.filter(function (p) { return /^CEF\\locales\\[^\\]+\.pak$/i.test(rel(p)); });
  yes('the section counts the language packs, ' + locales.length + ' `CEF\\locales\\*.pak`',
      runtimeFlat.indexOf(locales.length + ' `CEF\\locales\\*.pak`') >= 0);
  const unnamed = modFiles.filter(function (p) {
    return locales.indexOf(p) < 0 && runtimeSec.indexOf(path.basename(p)) < 0;
  }).map(rel);
  unnamed.forEach(function (r) { console.log('      not named in the section: ' + r); });
  yes('every other file in the mod is named in the section (' + (modFiles.length - locales.length) + ')', unnamed.length === 0);
  const leaves = cbFiles.map(function (r) { return r.split('\\').pop().toLowerCase(); });
  yes('none of the six recorded client files is in the mod, as the section says',
      modFiles.every(function (p) { return leaves.indexOf(path.basename(p).toLowerCase()) < 0; }));

  // By sha256: every program, data file and script, and nothing listed that
  // the mod does not have.
  const hashRows = {};
  runtimeSec.split('\n').forEach(function (l) {
    const m = /^\| `([^`]+)` \| [\d,]+ \| `([0-9a-f]{64})` \|/.exec(l);
    if (m) { hashRows[m[1]] = m[2]; }
  });
  modFiles.filter(function (p) { return /\.(dll|exe|dat|js)$/i.test(p); }).forEach(function (p) {
    const r = rel(p);
    const sha = crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
    yes(r + ' is in the section by its sha256, ' + sha.slice(0, 16), hashRows[r] === sha);
  });
  Object.keys(hashRows).forEach(function (r) {
    yes(r + ', hashed in the section, is in the mod', fs.existsSync(path.join(dist, r)));
  });

  // The licence texts it installs, each named, and the versions its README
  // gives, each in the section.
  const docs = path.join(runtimeDir, 'Docs', 'Thornswood Client Runtime');
  let licences = [];
  try { licences = fs.readdirSync(path.join(docs, 'licences')); } catch (e) { licences = []; }
  yes('the mod carries licence texts (' + licences.length + ')', licences.length > 0);
  licences.forEach(function (n) { yes(n + ', in the mod, is named in the section', runtimeSec.indexOf('`' + n + '`') >= 0); });
  const readme = read(path.join(docs, 'README.txt')) || '';
  const what = readme.split(/\nNot included/)[0];
  const vers = (what.match(/\b\d+\.\d+\.\d+(?:\.\d+)?(?:\+g[0-9a-f]+)?/g) || []).filter(function (v, i, a) { return a.indexOf(v) === i; });
  yes('the mod\'s README gives versions to check (' + vers.join(', ') + ')', vers.length > 0);
  vers.forEach(function (v) { yes('the section gives ' + v + ', from the mod\'s README', runtimeSec.indexOf(v) >= 0); });

  const polyMod = read(path.join(dist, '___systemPolyfill.js'));
  if (polyMod !== null && polyUpstream !== null) {
    yes('the mod\'s ___systemPolyfill.js is the fork\'s at ' + polySrc[1].slice(0, 8) + ', line endings aside',
        polyMod === polyUpstream);
  }
  const spMod = read(path.join(docs, 'licences', 'SkyrimPlatform-LICENSE.txt'));
  if (spMod !== null && spLicence !== null) {
    yes('the mod\'s SkyrimPlatform-LICENSE.txt is skyrim-platform/LICENSE', spMod === spLicence);
  }
}

// The launcher's record of where each game file came from, where the profile
// is here. Every file under Data\Platform\Distribution that the collection
// provides is covered by the Client Runtime section, and there are as many as
// it says.
const PROFILE = process.env.THORNSWOOD_PROFILE || 'C:\\Thornswood\\Profile';
const filesTxt = read(path.join(PROFILE, 'OwnGame', 'files.txt'));
if (filesTxt === null) {
  skip('no ' + path.join(PROFILE, 'OwnGame', 'files.txt') + ' here, so where the game files came from was not read');
} else {
  const fromCollection = filesTxt.split('\n').map(function (l) { return l.split('|'); })
    .filter(function (f) { return f.length >= 5 && f[1] === 'V'; })
    .map(function (f) { return f.slice(4).join('|'); })
    .filter(function (r) { return /^Data\\Platform\\Distribution\\/i.test(r); });
  if (fromCollection.length === 0) {
    skip('files.txt here gives the collection no file under Data\\Platform\\Distribution');
  } else {
    const loose = fromCollection.filter(function (r) {
      if (/\\CEF\\locales\\[^\\]+\.pak$/i.test(r)) { return runtimeSec.indexOf('`CEF\\locales\\*.pak`') < 0; }
      return runtimeSec.indexOf(r.split('\\').pop()) < 0;
    });
    loose.forEach(function (r) { console.log('      from the collection and not in the section: ' + r); });
    yes('every file the collection puts under Data\\Platform\\Distribution is in the Client Runtime section (' +
        fromCollection.length + ')', loose.length === 0);
    yes('the section says ' + fromCollection.length + ' files, as files.txt does',
        runtimeFlat.indexOf(fromCollection.length + ' files') >= 0);
  }
}

// ---------------------------------------------------------------- the words
[['THIRD-PARTY.md', N], ['credits.md', C]].forEach(function (pair) {
  yes(pair[0] + ' has no em dash', pair[1].indexOf('\u2014') < 0);
  yes(pair[0] + ' never says player', !/\bplayers?\b/i.test(pair[1]));
});
yes('THIRD-PARTY.md leaves the project\'s own licence to Patrick', /choosing one is Patrick's decision/.test(N));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
