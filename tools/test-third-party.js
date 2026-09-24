// test-third-party.js
//
// THIRD-PARTY.md names what Thornswood hands out that somebody else wrote, and
// the public credits page carries the directions to the source. This holds
// both to the build, so neither can drift away from what actually ships.
//
// From the To Do List, entry 171: "There is no licence on this project and no
// third-party notices file anywhere." Its done-when asks that every /resource:
// in Build-Launcher.ps1 and every file under tools\lib be "either the project's
// own or listed by name and licence", and it asks for that cross-check to be
// made "mechanically rather than by memory". This is that check.
//
// It also keeps the source offer honest. The GPL (section 6) and the AGPL
// (section 13) want the directions to lead to the source of what actually
// ships. When New-ClientBuildRecord.ps1 or New-ServerBuildRecord.ps1 records a
// new fork commit, this fails until THIRD-PARTY.md and credits.md name it.
//
// Measured when it was written, on 24 September: the three WebView2 files are
// byte for byte Microsoft.Web.WebView2 1.0.2903.40 from nuget.org, the six
// client files in the game folder match client-build.json, and
// MpClientPlugin.dll is built from skymp5-server, which is AGPL, not GPL.
//
// Where a clone of the fork that holds the recorded commit is on this machine
// (C:\Thornswood-Dev\skymp, or THORNSWOOD_SKYMP), it also reads each
// subproject's LICENSE and package.json at that commit, and the build files
// that say which subproject each client file comes from. On a runner without
// the fork those lines say SKIP and the rest still runs.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const TOOLS = __dirname;
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
const creditsRaw = read(path.join(TOOLS, 'docs-app', 'data', 'site', 'credits.md'));
yes('the public credits page is there to read', creditsRaw !== null);
const C = creditsRaw || '';

// ---------------------------------------------------------------- the launcher
//
// Everything Build-Launcher.ps1 compiles into an exe, by the name it is given
// inside the exe. These are made here, each one for Thornswood:
const OURS = {
  'ui.xaml': 'the launcher window, tools\\ui.xaml',
  'logo.png': 'the emblem, tools\\logo.png and logo-192.png for the setup stub',
  'launcher-header.jpg': 'a strip of the Thornswood backdrop, tools\\art',
  'launcher-header.mp4': 'the same strip moving',
  'app.ico': 'the icon',
  'voice-host.html': 'the voice page, tools\\launcher',
  'Thornswood.ini': 'the key template, tools\\emotes',
  'client-build.json': 'the record of the client runtime'
};

const build = read(path.join(TOOLS, 'Build-Launcher.ps1')) || '';
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

// ---------------------------------------------------------------- tools\lib
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
const libFiles = walk(path.join(TOOLS, 'lib'), []);
yes('tools\\lib has files to check (' + libFiles.length + ')', libFiles.length > 0);

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
  yes(name + ' (tools\\lib) is named in THIRD-PARTY.md', N.indexOf(name) >= 0);
  yes(name + ' is in THIRD-PARTY.md by its sha256, ' + sha.slice(0, 16), N.toLowerCase().indexOf(sha) >= 0);
  const v = fileVersion(buf);
  if (v) { versions[v] = (versions[v] || []).concat([name]); }
});
wv2.forEach(function (n) {
  yes(n + ', which the launcher embeds, is in tools\\lib\\webview2',
      fs.existsSync(path.join(TOOLS, 'lib', 'webview2', n)));
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
try { cb = JSON.parse(read(path.join(TOOLS, 'client-build.json'))); } catch (e) { cb = null; }
yes('tools\\client-build.json reads', !!(cb && cb.files && cb.forkCommit));
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
yes('the credits page says MpClientPlugin.dll is AGPL-3.0',
    /MpClientPlugin\.dll[^#]*AGPL-3\.0/.test(C));
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
let sb = null;
try { sb = JSON.parse(read(path.join(TOOLS, 'server-build.json'))); } catch (e) { sb = null; }
yes('tools\\server-build.json reads', !!(sb && sb.source && sb.source.commit));
if (sb && sb.source) {
  const sc = String(sb.source.commit);
  yes('THIRD-PARTY.md names the server binary, ' + sb.binary, N.indexOf(String(sb.binary)) >= 0);
  yes('THIRD-PARTY.md names the server commit, ' + sc.slice(0, 12), N.indexOf(sc) >= 0);
  yes('the credits page names the server commit, ' + sc.slice(0, 12), C.indexOf(sc) >= 0);
  yes('the server is built from the fork THIRD-PARTY.md names',
      String(sb.source.repo).replace(/\.git$/, '') === forkUrl);
}

// ---------------------------------------------------------------- the fork
//
// Only where the fork is cloned here and holds the recorded commit. This is
// what makes the licence column a measurement rather than a memory.
const FORK = process.env.THORNSWOOD_SKYMP || 'C:\\Thornswood-Dev\\skymp';
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

// ---------------------------------------------------------------- the words
[['THIRD-PARTY.md', N], ['credits.md', C]].forEach(function (pair) {
  yes(pair[0] + ' has no em dash', pair[1].indexOf('\u2014') < 0);
  yes(pair[0] + ' never says player', !/\bplayers?\b/i.test(pair[1]));
});
yes('THIRD-PARTY.md leaves the project\'s own licence to Patrick', /choosing one is Patrick's decision/.test(N));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
