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
// (#1568 to #1573) while THIRD-PARTY.md kept naming df2ae1f1, and nothing on
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
  'skyrim-files.json': 'the list of the pinned Skyrim build\'s own files, read from Steam\'s depot manifests',
  'ui-gone.json': 'the Daedric menu set and unused fork assets a refresh must not copy back'
};

// What goes into the launcher is written in its project file since #498's
// switch (Build-Launcher.ps1 only runs MSBuild on it): every EmbeddedResource
// by the LogicalName the code reads it under.
const proj = read(path.join(REPO, 'launcher', 'app', 'Thornswood.csproj')) || '';
yes('launcher\\app\\Thornswood.csproj is there to read', proj.length > 0);

const resources = [];
const unreadable = [];
(proj.match(/<EmbeddedResource\b[\s\S]*?<\/EmbeddedResource>/g) || []).forEach(function (el) {
  const m = /<LogicalName>([^<]+)<\/LogicalName>/.exec(el);
  if (m) { resources.push(m[1].trim()); } else { unreadable.push(el.replace(/\s+/g, ' ')); }
});
unreadable.forEach(function (l) { console.log('      no LogicalName in: ' + l); });
yes('every EmbeddedResource in Thornswood.csproj names the resource it becomes', unreadable.length === 0);
const wv2 = resources.filter(function (n) { return /WebView2/i.test(n); });
yes('Thornswood.csproj embeds the WebView2 files (' + wv2.join(', ') + ')', wv2.length === 3);
yes('Thornswood.csproj embeds resources to check (' + resources.length + ')', resources.length >= 10);

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
// The MIT and OFL ask for their text to go with the files, not only a name in
// a header (#421): marked's and each font family's licence are served beside
// them, by the sha256 THIRD-PARTY.md gives, and the credits page links each.
const LICENCE_TEXTS = { 'marked-LICENSE.txt': /Permission is hereby granted, free of charge/,
  'cinzel-OFL.txt': /Copyright 2020 The Cinzel Project Authors[\s\S]*SIL OPEN FONT LICENSE Version 1\.1/,
  'spectral-OFL.txt': /Copyright 2017 The Spectral Project Authors[\s\S]*SIL OPEN FONT LICENSE Version 1\.1/ };
Object.keys(LICENCE_TEXTS).forEach(function (n) {
  const t = read(path.join(PUB, n));
  yes(n + ' is in site\\public and is the licence it says it is', t !== null && LICENCE_TEXTS[n].test(t));
  const sha = t === null ? '' : crypto.createHash('sha256').update(Buffer.from(t, 'utf8')).digest('hex');
  yes(n + ' is in THIRD-PARTY.md under the site by its sha256, ' + sha.slice(0, 16), !!sha && siteSection.indexOf(sha) >= 0);
  yes('the credits page links /' + n, C.indexOf('](/' + n + ')') >= 0);
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
// the pin to 0460584e and wrote it into the fork section, "On our servers" and
// the source offer in "Where the source is" kept naming #1617's ac044a49 and
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

// ---------------------------------------------------------------- the LGPL
//
// #1332. Two of the libraries the fork's build links are not permissive:
// antigo (LGPL-3.0) and frida-gum (the wxWindows Library Licence 3.1). The
// issue said antigo goes to every client inside MpClientPlugin.dll and asked
// for the LGPL text and a notice to go with it. Measured on 5 October: the
// build links antigo into MpClientPlugin.dll, but nothing in the client calls
// it, so its code is only in scam_native.node, which nobody receives, and the
// LGPL asks nothing of what ships. frida-gum is in SkyrimPlatformImpl.dll;
// gum's own licence has an exception for binaries, and the libraries its
// devkit carries are held below (#3099, #3287). THIRD-PARTY.md says
// so, and this holds it there: the day a client file calls antigo, the fork
// files that use it stop being the three server ones and this fails, because
// then its notice and the LGPL text have to go with that file.
function cl0() {
  try { return JSON.parse(read(path.join(REPO, 'records', 'client-licences.json')).replace(/^\uFEFF/, '')); } catch (e) { return null; }
}
const libRows = N.split('\n').filter(function (l) { return l.charAt(0) === '|'; });
const antigoRow = libRows.filter(function (l) { return /^\| antigo, https:\/\/github\.com\/nic11\/antigo /.test(l); })[0] || '';
const fridaRow = libRows.filter(function (l) { return /^\| frida-gum \d/.test(l); })[0] || '';
const antigoAt = (/`([0-9a-f]{40})`/.exec(antigoRow) || [])[1] || '';
// The fork's build measures it since #3099: the record names no antigo in any client file.
if (cl0()) {
  const withAntigo = Object.keys(cl0().files || {}).filter(function (f) { return (cl0().files[f] || []).indexOf('antigo') >= 0; });
  yes('records\\client-licences.json names antigo in no client file' + (withAntigo.length ? ', but: ' + withAntigo.join(', ') : ''), withAntigo.length === 0);
}
const fridaAt = (/`([0-9a-f]{40})`/.exec(fridaRow) || [])[1] || '';
const fridaVer = (/^\| frida-gum (\d+\.\d+\.\d+)/.exec(fridaRow) || [])[1] || '';
yes('THIRD-PARTY.md has a row for antigo naming its commit (' + (antigoAt.slice(0, 8) || 'none') + ')', antigoAt.length === 40);
yes('the antigo row gives LGPL-3.0', /\| LGPL-3\.0\b/.test(antigoRow));
yes('the antigo row says its code is only in scam_native.node', /\| Only in `scam_native\.node`/.test(antigoRow));
yes('THIRD-PARTY.md has a row for frida-gum naming its version and commit (' + (fridaVer || 'none') + ')',
    fridaVer.length > 0 && fridaAt.length === 40);
yes('the frida-gum row gives gum\'s wxWindows Library Licence 3.1 and SkyrimPlatformImpl.dll',
    fridaRow.indexOf('wxWindows Library Licence 3.1') >= 0 && fridaRow.indexOf('`SkyrimPlatformImpl.dll`') >= 0);
yes('THIRD-PARTY.md no longer says this repository has an LGPL-3.0.txt to ship',
    !fs.existsSync(path.join(ROOT, 'LGPL-3.0.txt')) && /It has none, and none is owed/.test(flat(N)));
// The fork files that use antigo, other than its port and the build files
// that link it. MpClientPlugin.dll takes server_guest_lib for Inventory.cpp
// only, so these three put nothing of antigo into it.
const ANTIGO_USERS = [
  'skymp5-server/cpp/addon/ScampServer.cpp',
  'skymp5-server/cpp/server_guest_lib/MpObjectReference.cpp',
  'skymp5-server/cpp/server_guest_lib/WorldState.cpp'
];
const ANTIGO_LINKS = ['vcpkg.json', 'skymp5-server/cpp/CMakeLists.txt'];
// The fork's own tests (misc/tests) go into no file anybody receives. Since
// fork #77, test_save_completion_addon.cpp there writes stand-ins for antigo's
// names so the addon compiles without it; THIRD-PARTY.md says so.
const ANTIGO_TESTS = 'misc/tests/';
// The fork's Thornswood build scripts go into no file anybody receives either.
// Write-ClientLicences.ps1 (#3099) names antigo as the library its measurement
// finds linked into MpClientPlugin.dll with no code kept.
const ANTIGO_TOOLS = 'misc/thornswood/';
if (!haveFork) {
  skip('no fork here, so the antigo and frida-gum ports and antigo\'s users were not read');
} else {
  let port = '', portJson = null, frida = '';
  try { port = git(['show', commit + ':overlay_ports/antigo/portfile.cmake']); } catch (e) { port = ''; }
  try { portJson = JSON.parse(git(['show', commit + ':overlay_ports/antigo/vcpkg.json'])); } catch (e) { portJson = null; }
  try { frida = git(['show', commit + ':overlay_ports/frida-gum/portfile.cmake']); } catch (e) { frida = ''; }
  yes('overlay_ports/antigo at ' + commit.slice(0, 8) + ' fetches antigo at the commit THIRD-PARTY.md names',
      !!antigoAt && new RegExp('REF ' + antigoAt + '\\b').test(port));
  yes('overlay_ports/antigo/vcpkg.json at ' + commit.slice(0, 8) + ' declares LGPL-3.0', !!portJson && portJson.license === 'LGPL-3.0');
  yes('overlay_ports/frida-gum at ' + commit.slice(0, 8) + ' fetches the ' + fridaVer + ' devkit and the licence at the commit THIRD-PARTY.md names',
      !!fridaVer && frida.indexOf('/' + fridaVer + '/frida-gum-devkit-' + fridaVer + '-') >= 0 &&
      !!fridaAt && frida.indexOf('frida/frida-gum/' + fridaAt + '/COPYING') >= 0);
  let users = [];
  try {
    users = git(['grep', '-l', '-i', '-e', 'antigo', commit, '--']).split('\n')
      .map(function (l) { return l.slice(commit.length + 1).trim(); })
      .filter(function (p) { return p && p.indexOf('overlay_ports/') !== 0 && ANTIGO_LINKS.indexOf(p) < 0; });
  } catch (e) { users = []; }
  const testUsers = users.filter(function (p) { return p.indexOf(ANTIGO_TESTS) === 0; });
  testUsers.forEach(function (p) {
    yes('THIRD-PARTY.md names ' + p.split('/').pop() + ', a fork test that names antigo, as going into no shipped file',
        N.indexOf(p.split('/').pop()) >= 0 && /Nothing under `misc\\tests` goes into a file anybody receives/.test(flat(N)));
  });
  users = users.filter(function (p) { return p.indexOf(ANTIGO_TESTS) !== 0 && p.indexOf(ANTIGO_TOOLS) !== 0; });
  const newUsers = users.filter(function (p) { return ANTIGO_USERS.indexOf(p) < 0; });
  newUsers.forEach(function (p) { console.log('      uses antigo, and may put it into a client file: ' + p); });
  yes('the only fork files that use antigo are the three server ones THIRD-PARTY.md names (' + users.length + ')',
      users.length > 0 && newUsers.length === 0);
  ANTIGO_USERS.forEach(function (p) {
    yes('THIRD-PARTY.md names ' + p.split('/').slice(-2).join('\\') + ' as a user of antigo',
        N.indexOf(p.split('/').pop()) >= 0);
  });
}
// The recorded client files themselves, where the game folder holds them. A
// string of antigo's own (from its ResolvedContext.cpp at that commit) is in
// its library and in the recorded scam_native.node, and must not be in the
// recorded MpClientPlugin.dll. GumInterceptor is frida-gum's.
const GAME = process.env.THORNSWOOD_GAME || 'C:\\Thornswood\\Game';
function recordedCopy(rel) {
  const p = path.join(GAME, rel);
  let buf = null;
  try { buf = fs.readFileSync(p); } catch (e) { return null; }
  const want = cb && cb.files && cb.files[rel] ? String(cb.files[rel].sha256) : '';
  return crypto.createHash('sha256').update(buf).digest('hex') === want ? buf : null;
}
const ANTIGO_SAYS = ['resolved context with ', 'stringstream error!'];
const mpc = recordedCopy('Data\\SKSE\\Plugins\\MpClientPlugin.dll');
if (!mpc) {
  skip('no recorded MpClientPlugin.dll in ' + GAME + ', so it was not read for antigo');
} else {
  ANTIGO_SAYS.forEach(function (s) {
    yes('the recorded MpClientPlugin.dll carries none of antigo\'s code ("' + s.trim() + '" is not in it)',
        mpc.indexOf(Buffer.from(s, 'latin1')) < 0);
  });
}
const lib = path.join(FORK, 'build', 'vcpkg_installed', 'x64-windows-sp', 'lib', 'antigo.lib');
if (fs.existsSync(lib)) {
  const lb = fs.readFileSync(lib);
  yes('those strings are antigo\'s: its built library has them',
      ANTIGO_SAYS.every(function (s) { return lb.indexOf(Buffer.from(s, 'latin1')) >= 0; }));
} else {
  skip('no built antigo.lib under ' + FORK + ', so the strings were not checked against it');
}
const spi = recordedCopy('Data\\Platform\\Distribution\\RuntimeDependencies\\SkyrimPlatformImpl.dll');
if (!spi) {
  skip('no recorded SkyrimPlatformImpl.dll in ' + GAME + ', so it was not read for frida-gum');
} else {
  yes('the recorded SkyrimPlatformImpl.dll carries frida-gum (GumInterceptor), as the row says',
      spi.indexOf(Buffer.from('GumInterceptor', 'latin1')) >= 0);
}

// ------------------------------------------- the libraries inside them (#3099)
//
// The client files link the fork's vcpkg libraries statically, and their
// licence texts went nowhere until #3099: THIRD-PARTY.md said "None of those
// texts travels with the client runtime today". records\client-licences.json
// is what the fork's build measured in each native file. Its table here is the
// record, row for row, every text it names is beside it, and the frida row
// says what is inside frida-gum.lib (#3287).
let cl = null;
try { cl = JSON.parse(read(path.join(REPO, 'records', 'client-licences.json')).replace(/^﻿/, '')); } catch (e) { cl = null; }
yes('records\\client-licences.json reads', !!(cl && cl.forkCommit && cl.files && cl.ports));
if (cl) {
  yes('records\\client-licences.json is of the client record\'s commit (' + cl.forkCommit + ')', !!cb && String(cl.forkCommit) === String(cb.forkCommit));
  const HEAD = '| Library | Version | Licence, as its port declares it | In |';
  const lines = N.split('\n');
  const at = lines.indexOf(HEAD);
  const have = [];
  for (let i = at + 2; at >= 0 && i < lines.length && lines[i].charAt(0) === '|'; i++) have.push(lines[i]);
  const want = Object.keys(cl.ports).sort().map(function (n) {
    const p = cl.ports[n];
    const lic = p.licence ? p.licence : 'not declared; its text is in `' + n + '.txt`';
    const files = (p.in || []).map(function (f) { return String(f).split('\\').pop(); }).sort().map(function (f) { return '`' + f + '`'; }).join(', ');
    return '| ' + n + ' | ' + p.version + ' | ' + lic + ' | ' + files + ' |';
  });
  const wrong = want.filter(function (r) { return have.indexOf(r) < 0; });
  const extra = have.filter(function (r) { return want.indexOf(r) < 0; });
  wrong.forEach(function (r) { console.log('      not in THIRD-PARTY.md: ' + r); });
  extra.forEach(function (r) { console.log('      not in the record: ' + r); });
  yes('THIRD-PARTY.md\'s table of the libraries inside the client files is the record, row for row (' + want.length + ')',
      at >= 0 && want.length > 0 && wrong.length === 0 && extra.length === 0);
  const noText = Object.keys(cl.ports).filter(function (n) {
    let b = null;
    try { b = fs.readFileSync(path.join(REPO, 'records', 'client-licences', n + '.txt')); } catch (e) { return true; }
    return crypto.createHash('sha256').update(b).digest('hex') !== String(cl.ports[n].sha256) || b.length !== Number(cl.ports[n].bytes);
  });
  yes('every port in it has its text in records\\client-licences, byte for byte' + (noText.length ? ', not: ' + noText.join(', ') : ''), noText.length === 0);
}
yes('THIRD-PARTY.md no longer says the vcpkg texts travel nowhere',
    !/None of those texts travels/.test(N) && !/vcpkg licence texts do not travel/.test(flat(section('What is still missing'))));
yes('the frida-gum row says what else frida-gum.lib holds, under the LGPL',
    /glib, gobject, gnulib and libcharset \(LGPL-2\.1-or-later\)/.test(fridaRow));
// The source of what is inside frida-gum.lib, by Thornswood's forks of
// Frida's repositories (Patrick, A on #3287): the same six, at the same
// commits, in Source-Notice.ps1's $SourceNoticeBundled and in "Where the
// source is", and with the fork here, the commits its portfile fetches from.
const sn = read(path.join(REPO, 'scripts', 'release', 'Source-Notice.ps1')) || '';
const bundled = [];
(sn.match(/@\('[^']+',\s*'(frida-[a-z0-9-]+)',\s*'([0-9a-f]{40})'\)/g) || []).forEach(function (m) {
  const r = /'(frida-[a-z0-9-]+)',\s*'([0-9a-f]{40})'/.exec(m);
  bundled.push({ fork: r[1], commit: r[2] });
});
yes('Source-Notice.ps1 names the source of six libraries inside frida-gum.lib (' + bundled.length + ')', bundled.length === 6);
const whereSec = section('Where the source is');
const unnamed = bundled.filter(function (b) { return whereSec.indexOf('https://github.com/EvilPatrick06/' + b.fork + '/tree/' + b.commit) < 0; });
yes('"Where the source is" names each of them by our fork and the same commit' + (unnamed.length ? ', not: ' + unnamed.map(function (b) { return b.fork; }).join(', ') : ''), bundled.length > 0 && unnamed.length === 0);
if (haveFork) {
  let fp = '';
  try { fp = git(['show', commit + ':overlay_ports/frida-gum/portfile.cmake']); } catch (e) { fp = ''; }
  const off = bundled.filter(function (b) { return fp.indexOf('/' + b.commit + '/') < 0; });
  yes('each is a commit overlay_ports/frida-gum at ' + commit.slice(0, 8) + ' fetches its licence from' + (off.length ? ', not: ' + off.map(function (b) { return b.fork; }).join(', ') : ''), !!fp && off.length === 0);
} else {
  skip('no fork here, so the frida commits were not held to its portfile');
}

// ---------------------------------------------------------------- the front
//
// Since #2931 every Ship builds build.js and the files beside it from the
// fork's skymp5-front at the pin and holds them to records\front-build.json.
// THIRD-PARTY.md said for a month that nobody recorded its commit. Its section
// on that build names the record's commit and count, and every font the
// record holds is named with what its own file says.
let front = null;
try { front = JSON.parse(read(path.join(REPO, 'records', 'front-build.json'))); } catch (e) { front = null; }
yes('records\\front-build.json reads', !!(front && front.forkCommit && front.files));
const frontSec = (function () {
  const at = N.indexOf('\n## SkyMP\'s interface, built from the fork');
  if (at < 0) { return ''; }
  const next = N.indexOf('\n## ', at + 4);
  return next < 0 ? N.slice(at) : N.slice(at, next);
})();
yes('THIRD-PARTY.md has a section on the interface built from the fork', frontSec.length > 0);
if (front && front.files) {
  const fNames = Object.keys(front.files);
  let fBytes = 0;
  fNames.forEach(function (n) { fBytes += front.files[n].bytes; });
  const fFlat = flat(frontSec);
  yes('that section names the record\'s commit, ' + String(front.forkCommit).slice(0, 8), frontSec.indexOf('`' + String(front.forkCommit).slice(0, 8) + '`') >= 0);
  yes('that section names the client record\'s commit as the same one', String(front.forkCommit).indexOf(commit) === 0);
  yes('that section gives the record\'s ' + fNames.length + ' files and ' + fBytes + ' bytes',
      fFlat.indexOf(fNames.length + ' files, ' + fBytes.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',') + ' bytes') >= 0);
  fNames.filter(function (n) { return /\.(ttf|otf|woff2?)$/i.test(n); }).forEach(function (n) {
    yes('that section names the font ' + n + ' the record holds', frontSec.indexOf('`' + n + '`') >= 0);
  });
  if (front.files['build.js']) {
    yes('that section gives build.js by the record\'s sha256', frontSec.indexOf(front.files['build.js'].sha256) >= 0);
  }
}
yes('"What is still missing" no longer says build.js has no recorded commit as if every release did',
    !/^- build\.js has no recorded source commit\.$/m.test(section('What is still missing')));

// ---------------------------------------------------------------- Nexus Mods
//
// Two of the collection's mods are Thornswood's own uploads. One of them, the
// Thornswood Client Runtime (Nexus 192762), is the largest thing somebody else
// wrote that Thornswood hands out: since 1.0.1, 67 files of CEF, Chromium,
// ANGLE, ICU, Node and Microsoft's shader compiler, about 349 MB. 1.0.0 also
// had one Skyrim Platform script, and Nexus still serves it to revisions 1
// and 2 of the collection, so its source stays offered.
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
yes('"Where the source is" says the installer hands AGPL-3.0.txt',
    /installer hands[\s\S]{0,200}AGPL-3\.0\.txt/.test(sourceSec));
yes('installer/licences/AGPL-3.0.txt exists', (function () {
  try { return fs.statSync(path.join(ROOT, 'installer', 'licences', 'AGPL-3.0.txt')).isFile(); } catch (e) { return false; }
})());
yes('installer/licences/GPL-3.0.txt exists', (function () {
  try { return fs.statSync(path.join(ROOT, 'installer', 'licences', 'GPL-3.0.txt')).isFile(); } catch (e) { return false; }
})());
yes('installer/licences/WebView2-LICENSE.txt exists', (function () {
  try { return fs.statSync(path.join(ROOT, 'installer', 'licences', 'WebView2-LICENSE.txt')).isFile(); } catch (e) { return false; }
})());
// 1.0.1 has no GPL file in it; 1.0.0, which revisions 1 and 2 still install,
// has ___systemPolyfill.js and skyrim-platform's licence beside it.
const polyRows = runtimeSec.split('\n').filter(function (l) {
  return l.charAt(0) === '|' && l.indexOf('___systemPolyfill.js') >= 0;
});
yes('no table in the Client Runtime section lists ___systemPolyfill.js, which 1.0.1 does not carry', polyRows.length === 0);
const oldRuntime = (function () {
  const at = runtimeSec.indexOf('\n### Version 1.0.0');
  return at < 0 ? '' : flat(runtimeSec.slice(at));
})();
yes('the Client Runtime section says what 1.0.0, still installed by revisions 1 and 2, carries',
    oldRuntime.indexOf('`___systemPolyfill.js`') >= 0 && oldRuntime.indexOf('SkyrimPlatform-LICENSE.txt') >= 0 &&
    oldRuntime.indexOf('GNU General Public License version 3') >= 0);
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
    yes(r + ', hashed in the section, is in the mod', fs.existsSync(path.join.apply(path, [dist].concat(r.split('\\')))));
  });

  // The licence texts it installs, each named, and the versions its README
  // gives, each in the section.
  const docs = path.join(runtimeDir, 'Docs', 'Thornswood Client Runtime');
  let licences = [];
  try { licences = fs.readdirSync(path.join(docs, 'licences')); } catch (e) { licences = []; }
  yes('the mod carries licence texts (' + licences.length + ')', licences.length > 0);
  licences.forEach(function (n) { yes(n + ', in the mod, is named in the section', runtimeSec.indexOf('`' + n + '`') >= 0); });
  const icuText = (function () {
    try { return fs.readFileSync(path.join(docs, 'licences', 'ICU-LICENSE.txt')); } catch (e) { return null; }
  })();
  if (icuText !== null) {
    const icuSha = crypto.createHash('sha256').update(icuText).digest('hex');
    yes('the section gives the sha256 of the mod\'s ICU-LICENSE.txt, ' + icuSha.slice(0, 16), runtimeFlat.indexOf(icuSha) >= 0);
  }
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
// Thornswood's own code is under MIT (Patrick, 26 Oct, #3688). LICENSE holds
// the MIT text and nothing else: one added sentence and GitHub's licence
// reader (licensee) stops naming it MIT, measured 26 Oct. What MIT does not
// cover, and the terms every contributor agrees to once (#1331), are in
// LICENSING.md. This file points there and licenses nothing of ours itself.
const licence = read(path.join(ROOT, 'LICENSE'));
yes('LICENSE is at the repo root', licence !== null);
const MIT_BODY = [
  'Permission is hereby granted, free of charge, to any person obtaining a copy',
  'of this software and associated documentation files (the "Software"), to deal',
  'in the Software without restriction, including without limitation the rights',
  'to use, copy, modify, merge, publish, distribute, sublicense, and/or sell',
  'copies of the Software, and to permit persons to whom the Software is',
  'furnished to do so, subject to the following conditions:',
  '',
  'The above copyright notice and this permission notice shall be included in all',
  'copies or substantial portions of the Software.',
  '',
  'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR',
  'IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,',
  'FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE',
  'AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER',
  'LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,',
  'OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE',
  'SOFTWARE.',
].join('\n');
const MIT_FILE = 'MIT License\n\nCopyright (c) 2026 Patrick (EvilPatrick06) and Thornswood contributors\n\n' +
  MIT_BODY + '\n';
yes('  it is the MIT text and nothing else, so GitHub reads it as MIT', licence === MIT_FILE);
const licensing = read(path.join(ROOT, 'LICENSING.md'));
const LG = licensing || '';
yes('LICENSING.md is at the repo root', licensing !== null);
yes('  it says what MIT does not cover', /## What MIT does not cover/.test(LG));
yes('  the SkyMP fork keeps its own licences', /engine\/skymp/.test(LG) && /Affero/.test(LG));
yes('  every file THIRD-PARTY.md lists keeps its own', /Every file `THIRD-PARTY\.md` lists/.test(LG));
yes('  lore, art and music Thornswood owns are under CC BY-NC-SA 4.0 (Patrick, 26 Oct, #3688)',
    /## Lore, art and music: CC BY-NC-SA 4\.0/.test(LG) && /creativecommons\.org\/licenses\/by-nc-sa\/4\.0/.test(LG));
yes('  the name and logo stay all rights reserved', /\*\*The Thornswood name and logo\.\*\* They stay all rights reserved/.test(LG));
// Every logo file LICENSING.md keeps out of CC BY-NC-SA 4.0 is a real file.
const logoAt = LG.indexOf('**The Thornswood name and logo.**');
const logoPara = logoAt >= 0 ? LG.slice(logoAt, LG.indexOf('\n7. ', logoAt)) : '';
const logoFiles = [];
let dirNow = '';
(logoPara.match(/`[^`]+`/g) || []).forEach(function (q) {
  const f = q.slice(1, -1);
  if (f.indexOf('/') >= 0) { dirNow = f.slice(0, f.lastIndexOf('/') + 1); logoFiles.push(f); }
  else if (dirNow) { logoFiles.push(dirNow + f); }
});
const logoMissing = logoFiles.filter(function (f) { return !fs.existsSync(path.join(ROOT, f)); });
logoMissing.forEach(function (f) { console.log('      named as a logo file, not in the repository: ' + f); });
yes('  every logo file it names is in the repository (' + logoFiles.length + ')', logoFiles.length >= 10 && logoMissing.length === 0);
yes('  and it carries the contributor terms', /## Contributor terms/.test(LG) && /agrees to these\s+terms once/.test(LG));
yes('THIRD-PARTY.md sends the project\'s own licence to LICENSE and LICENSING.md',
    /does not license Thornswood's own work\./.test(N) && /`LICENSE` at the root/.test(N) && /`LICENSING\.md` says what that licence does not cover/.test(N));
yes('THIRD-PARTY.md says it covers files kept in the repository too, as LICENSING.md does',
    /the files kept in this repository that somebody else wrote/.test(N));
// Contributor term 3 asks the pull request to say whose the work is, so the
// template has a line for it (#3651).
const template = read(path.join(ROOT, '.github', 'pull_request_template.md')) || '';
if (/the pull request says whose it is/.test(flat(LG))) {
  yes('the pull request template has a "Whose work" line for contributor term 3', /^Whose work:/m.test(template));
} else {
  yes('LICENSING.md no longer asks the pull request to say whose the work is', true);
}
[['LICENSING.md', LG]].forEach(function (pair) {
  yes(pair[0] + ' has no em dash', pair[1].indexOf('—') < 0);
  yes(pair[0] + ' never says player', !/\bplayers?\b/i.test(pair[1]));
});

// --------------------------------------------- kept in the repository, #3761
//
// LICENSING.md says MIT does not cover anything THIRD-PARTY.md lists, and
// THIRD-PARTY.md lists what sits in the repository as well as what ships.
// A fixture that is large or carries somebody else's notice has a row in
// "Kept in the repository, not shipped". The 2.4 MB skymp5-front build and
// certifi's roots sat in tests\fixtures with none until #3761.
const keptAt = N.indexOf('## Kept in the repository, not shipped');
yes('THIRD-PARTY.md has a section for files kept in the repository, not shipped', keptAt >= 0);
const keptSec = keptAt >= 0 ? N.slice(keptAt, N.indexOf('\n## ', keptAt + 5) > 0 ? N.indexOf('\n## ', keptAt + 5) : N.length) : '';
const NOTICE_RE = /@license|\bCopyright\b|\bcertifi\b|-----BEGIN CERTIFICATE-----/;
function walkFixtures(dir, rel, out) {
  fs.readdirSync(dir, { withFileTypes: true }).forEach(function (e) {
    const r = rel ? rel + '\\' + e.name : e.name;
    if (e.isDirectory()) { walkFixtures(path.join(dir, e.name), r, out); }
    else if (e.isFile()) { out.push({ rel: r, full: path.join(dir, e.name) }); }
  });
  return out;
}
const fixtures = walkFixtures(path.join(ROOT, 'tests', 'fixtures'), '', []);
const flagged = fixtures.filter(function (f) {
  const size = fs.statSync(f.full).size;
  if (size > 100 * 1024) { return true; }
  return NOTICE_RE.test(fs.readFileSync(f.full, 'latin1'));
});
yes('  the check found the fixtures it was written for (' + flagged.length + ')',
    flagged.some(function (f) { return f.rel === '3111-roots.pem'; }));
flagged.forEach(function (f) {
  yes('  tests\\fixtures\\' + f.rel + ' has a row there', keptSec.indexOf('`tests\\fixtures\\' + f.rel + '`') >= 0);
});
const uiFront = fixtures.filter(function (f) { return f.rel === 'ui-front-build.js'; })[0];
if (uiFront) {
  const ui = fs.readFileSync(uiFront.full, 'utf8');
  yes('  tests\\fixtures\\ui-front-build.js is only the build\'s asset modules: no bundled npm notice in it',
      !/@license|\bCopyright\b|react-dom|\bLicensed under\b/i.test(ui));
  yes('  and it has a row there all the same, since it was cut from skymp5-front\'s GPL build',
      keptSec.indexOf('`tests\\fixtures\\ui-front-build.js`') >= 0 && /General Public License version 3/.test(keptSec));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
