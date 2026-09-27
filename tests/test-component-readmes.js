'use strict';
// test-component-readmes.js
//
// Six folders under tools each say, in a README, what they hold, how to run or
// change it on a machine, and where it runs. And the setup block in
// DEVELOPING.md says the dev channel needs the dev build installed and
// run once.
//
// WHY THIS EXISTS. From the To Do List: "Four deployable components have no
// README, and the dev release path has never been proven end to end". On 19
// September the dev build on the second machine had never been run, so it had
// no game folder of its own and Ship built the dev release out of the Steam
// copy. The setup block listed git, gh, node and Python and never mentioned the
// dev build, although every change goes to the dev build first. And none of
// these six folders had a word written about it outside the code:
// launcher reads like the launcher's source and holds one HTML page, and
// installer\setup holds the installer, not the launcher.
//
// A README is worth having only while it is true, so this checks what each one
// states against the code that decides it, not only that the file is there:
// the ports are read out of server.js, voice-server.js and DevBuild.cs, the
// folders and tasks out of the scripts that install them, every script and
// repo path a README names has to exist, and every THORNSWOOD_ setting it names
// has to be one that folder's code reads. When one of these fails after a code
// change, the README is what has gone wrong; change the README.
//
// It also checks that nothing which carries these folders to people would
// carry a README with them. Go.ps1 copies the overlays and the plugins by
// filter, Deploy-Docs and Install-Voice send named files, and Build-Launcher
// embeds and compiles by name. A README.md in Data\Platform would be a stray
// file in every pack.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ROOT = path.join(TOOLS_DIR, '..');
const CR = String.fromCharCode(13);
// A backslash, built rather than typed, so no tool on the way can eat it.
const BS = String.fromCharCode(92);

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

function read(rel) {
  try { return fs.readFileSync(path.join(ROOT, rel), 'utf8').split(CR).join(''); }
  catch (e) { return null; }
}
function exists(rel) {
  try { fs.statSync(path.join(ROOT, rel)); return true; } catch (e) { return false; }
}
function uniq(a) {
  return a.filter(function (x, i) { return a.indexOf(x) === i; });
}
function files(rel) {
  try {
    return fs.readdirSync(path.join(ROOT, rel), { withFileTypes: true })
      .filter(function (e) { return e.isFile(); })
      .map(function (e) { return e.name; });
  } catch (e) { return []; }
}
// Whether git is told to leave this path alone: build output, or one
// machine's own file. A README may name those without them being here.
function ignored(rel) {
  try {
    execSync('git check-ignore -q -- "' + rel + '"', { cwd: ROOT, stdio: 'ignore' });
    return true;
  } catch (e) { return false; }
}
function tracked(rel) {
  try {
    return execSync('git ls-files -- "' + rel + '"', { cwd: ROOT }).toString().trim().length > 0;
  } catch (e) { return null; }
}
// A PowerShell -Filter glob as a regular expression.
function glob(f) {
  const g = f.replace(/^['"]|['"]$/g, '');
  const src = g.split('').map(function (c) {
    if (c === '*') { return '.*'; }
    if (c === '?') { return '.'; }
    return c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
  }).join('');
  return new RegExp('^' + src + '$', 'i');
}

const SIX = ['docs-app', 'voice', 'ts-plugins', 'ts-ui', 'setup', 'launcher'];
// Where each lives: voice left tools for the repository root on 25 September.
const AT = { 'voice': 'voice', 'docs-app': 'site', 'ts-plugins': 'game/plugins', 'ts-ui': 'game/ui',
  'launcher': 'launcher', 'setup': 'installer/setup' };
function at(d) { return AT[d] || ('tools/' + d); }
const HEADS = ['## What it is', '## On your machine', '## Where it runs'];
const readme = {};
SIX.forEach(function (d) { readme[d] = read(at(d) + '/README.md'); });

// ------------------------------------------------------ every README, alike --
SIX.forEach(function (d) {
  const t = readme[d];
  const name = at(d).split('/').join(BS);
  yes(name + ' has a README.md', t !== null);
  if (t === null) { return; }
  const lines = t.split('\n');
  yes(name + ': it starts with a title', /^# \S/.test(lines[0]));
  const heads = lines.filter(function (l) { return /^## /.test(l); });
  yes(name + ': it has the three sections, in order: what it is, on your machine, where it runs',
      JSON.stringify(heads) === JSON.stringify(HEADS));
  const parts = t.split(/^## .*$/m).slice(1);
  yes(name + ': every section says something',
      parts.length === 3 && parts.every(function (p) {
        return p.replace(/\s+/g, ' ').trim().split(' ').length >= 25;
      }));

  // The words rules, and no names: operational documents are losing names.
  yes(name + ': it never says player', !/\bplayers?\b/i.test(t));
  yes(name + ': no em dash and no en dash', t.indexOf('\u2014') < 0 && t.indexOf('\u2013') < 0);
  yes(name + ': it names nobody', !/\b(Patrick|Djinn|Gavin|WiccanDjinn|EvilPatrick06)\b/.test(t));
  yes(name + ': no placeholder left in it', !/\b(TODO|TBD|FIXME|XXX)\b/.test(t) && !/lorem ipsum/i.test(t));

  const scripts = uniq(t.match(/\b[A-Z][A-Za-z]*(?:-[A-Z][A-Za-z]*)*\.ps1\b/g) || []);
  // In scripts\<area> since phase 8 of issue #440.
  const noScript = scripts.filter(function (s) {
    return !['release', 'deploy', 'vps', 'ops', 'mods', 'dev'].some(function (a) { return exists('scripts/' + a + '/' + s); });
  });
  yes(name + ': every script it names is in scripts (' + scripts.length + ' named)' +
      (noScript.length ? ', missing ' + noScript.join(', ') : ''), noScript.length === 0);

  const re = new RegExp('tools' + BS + BS + '[A-Za-z0-9_.*' + BS + BS + '-]+', 'g');
  const paths = uniq((t.match(re) || []).map(function (p) {
    return p.replace(/[.\\,]+$/, '');
  })).filter(function (p) { return p.indexOf('*') < 0; });
  const noPath = paths.filter(function (p) {
    const rel = p.split(BS).join('/');
    return !exists(rel) && !ignored(rel);
  });
  yes(name + ': every repo path it names is here, or is one git is told to ignore (' +
      paths.length + ' named)' + (noPath.length ? ', missing ' + noPath.join(', ') : ''),
      noPath.length === 0);

  const code = files(at(d)).filter(function (f) { return /\.(js|cs|html)$/.test(f); })
    .map(function (f) { return read(at(d) + '/' + f) || ''; }).join('\n');
  const settings = uniq(t.match(/THORNSWOOD_[A-Z_]+/g) || []);
  const unread = settings.filter(function (s) { return code.indexOf(s) < 0; });
  yes(name + ': every THORNSWOOD_ setting it names is read by the code beside it (' +
      settings.length + ' named)' + (unread.length ? ', not read: ' + unread.join(', ') : ''),
      unread.length === 0);

  const ours = uniq((t.match(/`thornswood-[\w-]+\.(?:js|mp3)`/g) || []).map(function (s) {
    return s.replace(/`/g, '');
  }));
  const nowhere = ours.filter(function (n) {
    return !exists('game/plugins/' + n) && !exists('game/ui/' + n);
  });
  yes(name + ': every plugin or overlay file it names exists (' + ours.length + ' named)' +
      (nowhere.length ? ', missing ' + nowhere.join(', ') : ''), nowhere.length === 0);
});

// ------------------------------------------------------------------ the site --
{
  const t = readme['docs-app'] || '';
  const server = read('site/server.js') || '';
  const deploy = read('scripts/deploy/Deploy-Docs.ps1') || '';
  const port = (/THORNSWOOD_DOCS_PORT \|\| (\d+)/.exec(server) || [])[1];
  yes('site: server.js has a default port to hold the README to', !!port);
  yes('site: the README gives it, 127.0.0.1:' + port, !!port && t.indexOf('127.0.0.1:' + port) >= 0);
  const dPort = (/\[int\]\$Port\s*=\s*(\d+)/.exec(deploy) || [])[1];
  yes('site: Deploy-Docs.ps1 starts it on that same port', !!dPort && dPort === port);
  const dRoot = (/\[string\]\$Root\s*=\s*'([^']+)'/.exec(deploy) || [])[1];
  yes('site: the README names the folder Deploy-Docs.ps1 puts it in, ' + dRoot,
      !!dRoot && t.indexOf(dRoot.split('/').join(BS)) >= 0);
  const dTask = (/\[string\]\$Task\s*=\s*'([^']+)'/.exec(deploy) || [])[1];
  yes('site: and the scheduled task it runs under, ' + dTask, !!dTask && t.indexOf('`' + dTask + '`') >= 0);
  yes('site: the door routes the README names are ones server.js answers',
      server.indexOf("'/api/allowed'") >= 0 && server.indexOf("'/dev/api/allowed'") >= 0 &&
      t.indexOf('/api/allowed') >= 0 && t.indexOf('/dev/api/allowed') >= 0);
}

// ------------------------------------------------------------------- voice --
{
  const t = readme.voice || '';
  const vs = read('voice/voice-server.js') || '';
  const dev = read('launcher/app/DevBuild.cs') || '';
  const iv = read('scripts/deploy/Install-Voice.ps1') || '';
  const watch = read('scripts/vps/Watch-Services.ps1') || '';
  const live = (/THORNSWOOD_VOICE_PORT \|\| (\d+)/.exec(vs) || [])[1];
  const devPort = (/DevVoicePort = "(\d+)"/.exec(dev) || [])[1];
  yes('voice: the live port read out of voice-server.js and the dev one out of DevBuild.cs',
      !!live && !!devPort);
  yes('voice: the README gives both, ' + live + ' and ' + devPort,
      !!live && !!devPort && t.indexOf(live) >= 0 && t.indexOf(devPort) >= 0);
  const ivRoot = (/\[string\]\$Root\s*=\s*'([^']+)'/.exec(iv) || [])[1];
  const ivTask = (/\[string\]\$TaskName\s*=\s*'([^']+)'/.exec(iv) || [])[1];
  yes('voice: the README names the folder and task Install-Voice.ps1 puts the live service in, ' +
      ivRoot + ' and ' + ivTask,
      !!ivRoot && !!ivTask && t.indexOf('`' + ivRoot + '`') >= 0 && t.indexOf('`' + ivTask + '`') >= 0);
  const devSvc = /Name = 'dev voice'; Task = '([^']+)';\s*Port = (\d+)/.exec(watch) || [];
  yes('voice: the dev task and port the README gives are the ones Watch-Services.ps1 watches',
      devSvc.length === 3 && devSvc[2] === devPort &&
      t.indexOf("-TaskName '" + devSvc[1] + "'") >= 0 && t.indexOf('-Port ' + devSvc[2]) >= 0);
  yes('voice: the three switches the README gives for the dev service are ones Install-Voice.ps1 takes',
      /\[string\]\$Root\b/.test(iv) && /\[int\]\$Port\b/.test(iv) && /\[string\]\$TaskName\b/.test(iv));
  yes('voice: /health reports the BUILD string, as the README says',
      /const BUILD = '/.test(vs) && /build: BUILD/.test(vs) && t.indexOf('`BUILD`') >= 0);
  // The README says the gamemode's copy of the feed has moved on from
  // gamemode-voice.js. If the two are ever brought back together, this fails
  // and the paragraph in voice\README.md is what to change.
  const gm = read('game/gamemode.js') || '';
  const a = gm.indexOf('// ==== thornswood voice feed, added by Add-VoiceFeed.ps1 ====');
  const b = gm.indexOf('// ==== end thornswood voice feed ====');
  const block = (a >= 0 && b > a) ? gm.slice(a, b) : '';
  const file = read('voice/gamemode-voice.js') || '';
  yes('voice: the gamemode carries the voice feed block between its markers', block.length > 0);
  yes('voice: as the README says, that block reads its port and gamemode-voice.js has 7778 written in',
      /VOICE_PORT = voicePort\(\)/.test(block) && /VOICE_PORT = 7778;/.test(file) &&
      t.indexOf('server-settings.json') >= 0);
}

// ----------------------------------------------------------------- plugins --
{
  const t = readme['ts-plugins'] || '';
  const go = read('scripts/release/Go.ps1') || '';
  const keep = read('launcher/app/Keep.cs') || '';
  const rules = read('scripts/release/Ship-Rules.ps1') || '';
  const game = (/\[string\]\s*\$Game\s*=\s*'([^']+)'/.exec(go) || [])[1];
  yes('plugins: the README names the game folder Go.ps1 installs into by default, ' + game,
      !!game && t.indexOf(game) >= 0);
  const serverPart = go.indexOf('if (-not $SkipServer)');
  yes('plugins: Go.ps1 still copies the voice service to the VPS unless it is given -SkipServer, ' +
      'which is why the README says to pass it',
      serverPart >= 0 && go.indexOf("'.." + BS + ".." + BS + "voice" + BS + "voice-server.js'", serverPart) > serverPart &&
      t.indexOf('Go.ps1 -SkipServer') >= 0 && (readme['ts-ui'] || '').indexOf('Go.ps1 -SkipServer') >= 0);
  yes('plugins: Keep and Ship-Rules still tell ours by the thornswood- name the README gives',
      keep.indexOf('StartsWith("thornswood-"') >= 0 && rules.indexOf("'thornswood-*.js'") >= 0 &&
      t.indexOf('`thornswood-*.js`') >= 0);
  yes('plugins: the retired thornswood-chargen.js is gone, and the README no longer names it',
      read('game/plugins/thornswood-chargen.js') === null && t.indexOf('thornswood-chargen') < 0);
}

// ---------------------------------------------------------------- overlays --
{
  const t = readme['ts-ui'] || '';
  const front = read('game/plugins/thornswood-front.js') || '';
  const go = read('scripts/release/Go.ps1') || '';
  yes('overlays: thornswood-front.js still has the OVERLAYS list a new overlay has to join',
      /const OVERLAYS = \[/.test(front) && t.indexOf('`OVERLAYS`') >= 0);
  yes('overlays: Go.ps1 still takes the front from thornswood-front.zip, as the README says',
      go.indexOf("tools" + BS + "thornswood-front.zip'") >= 0 && t.indexOf('thornswood-front.zip') >= 0);
  const zip = tracked('tools/thornswood-front.zip');
  yes('overlays: and that zip is not in git, as the README says', zip === false);
}

// --------------------------------------------------------- launcher --
{
  const t = readme.launcher || '';
  const bl = read('scripts/release/Build-Launcher.ps1') || '';
  const voice = read('launcher/app/Voice.cs') || '';
  const held = files('launcher');
  // Since phase 7 (issue #440) this is the whole launcher, not only its voice
  // page: the source, the window, the icon and art, the voice page, WebView2.
  yes('launcher: holds the source folder, the window and the voice page (' + held.join(', ') + ')',
      held.indexOf('ui.xaml') >= 0 && held.indexOf('voice-host.html') >= 0 && exists('launcher/app/Shell.cs'));
  yes('launcher: Build-Launcher.ps1 embeds the voice page by name',
      bl.indexOf("'.." + BS + ".." + BS + "launcher" + BS + "voice-host.html'") >= 0);
  yes('launcher: Voice.cs loads it by that name', voice.indexOf('"voice-host.html"') >= 0);
  yes('launcher: the README says where the source and the window are',
      t.indexOf('`launcher' + BS + 'app`') >= 0 && t.indexOf('ui.xaml') >= 0 && t.indexOf('voice-host.html') >= 0);
}

// ------------------------------------------------------------ installer\setup --
{
  const t = readme.setup || '';
  const bl = read('scripts/release/Build-Launcher.ps1') || '';
  const boot = read('installer/setup/Bootstrap.cs') || '';
  const held = files('installer/setup').filter(function (f) { return f !== 'README.md'; });
  yes('installer' + BS + 'setup: holds the one file its README says, Bootstrap.cs (' + held.join(', ') + ')',
      held.length === 1 && held[0] === 'Bootstrap.cs');
  yes('installer' + BS + 'setup: Build-Launcher.ps1 compiles Bootstrap.cs by name into setup-stub.exe',
      bl.indexOf("'.." + BS + ".." + BS + "installer" + BS + "setup" + BS + "Bootstrap.cs'") >= 0 && bl.indexOf("setup-stub.exe'") >= 0 &&
      t.indexOf('setup-stub.exe') >= 0);
  const inst = (/installRoot = @"([^"]+)"/.exec(boot) || [])[1];
  yes('installer' + BS + 'setup: the README gives the install folder Bootstrap.cs offers, ' + inst,
      !!inst && t.indexOf('`' + inst + '`') >= 0);
  const site = (/const string Site = "([^"]+)"/.exec(boot) || [])[1];
  yes('installer' + BS + 'setup: and the address it downloads the payload from',
      !!site && boot.indexOf('Site + "/api/payload"') >= 0 && t.indexOf(site + '/api/payload') >= 0);
  yes('installer' + BS + 'setup: the README says it is not the launcher source, and where that is',
      /not the launcher's\s+source/.test(t) && t.indexOf('`launcher' + BS + 'app`') >= 0);
}

// ------------------------------------------- nothing carries a README out --
{
  const go = read('scripts/release/Go.ps1') || '';
  const filters = { ui: [], pl: [] };
  let bare = 0;
  go.split('\n').forEach(function (l) {
    const m = /Get-ChildItem\s+-LiteralPath\s+\$(uiSrc|plSrc)\b/.exec(l);
    if (!m) { return; }
    const f = /-Filter\s+([^\s)]+)/.exec(l);
    if (!f) { bare++; return; }
    filters[m[1] === 'uiSrc' ? 'ui' : 'pl'].push(f[1]);
  });
  yes('Go.ps1 lists the overlays and the plugins only through filters (' +
      filters.ui.join(' ') + ' and ' + filters.pl.join(' ') + ')',
      filters.ui.length > 0 && filters.pl.length > 0 && bare === 0);
  // The filters are read right only if they still take what they are for.
  yes('those filters, read as globs, take the overlays and the plugins they are for',
      filters.ui.some(function (f) { return glob(f).test('thornswood-chat.js'); }) &&
      filters.pl.some(function (f) { return glob(f).test('thornswood-front.js'); }));
  yes('and none of them would copy README.md into the game folder',
      filters.ui.concat(filters.pl).every(function (f) { return !glob(f).test('README.md'); }));

  const dd = read('scripts/deploy/Deploy-Docs.ps1') || '';
  const lists = dd.split('\n').filter(function (l) {
    return /Get-ChildItem\s+(\(Join-Path \$App\b|(-LiteralPath\s+)?\$App\b)/.test(l);
  });
  yes('Deploy-Docs.ps1 lists public, data and data/site, never the folder the README sits in',
      lists.length > 0 && lists.every(function (l) {
        return /Get-ChildItem \(Join-Path \$App '(public|data|data\/site)'\)/.test(l);
      }) && dd.indexOf("Push (Join-Path $App 'server.js')") >= 0);

  const iv = read('scripts/deploy/Install-Voice.ps1') || '';
  const sent = (/foreach \(\$f in ('[^)]*')\)/.exec(iv) || [])[1];
  yes('Install-Voice.ps1 sends named files, with no wildcard (' + sent + ')',
      !!sent && sent.indexOf('*') < 0 && !/README/i.test(sent) && !/Get-ChildItem/.test(iv));

  const bl = read('scripts/release/Build-Launcher.ps1') || '';
  yes('Build-Launcher.ps1 never lists launcher or installer' + BS + 'setup, so only the named file goes in',
      !bl.split('\n').some(function (l) {
        return /Get-ChildItem/.test(l) && /'(\.\.\\launcher|\.\.\\installer\\setup|launcher|setup)(['\\])/.test(l);
      }));
}

// ------------------------------------------------------ DEVELOPING.md --
{
  const sd = read('DEVELOPING.md') || '';
  const lines = sd.split('\n');
  const hits = [];
  lines.forEach(function (l, i) { if (l.indexOf('Thornswood-DevBuild') >= 0) { hits.push(i); } });
  yes('DEVELOPING.md names Thornswood-DevBuild in two places or more (' + hits.length + ')',
      hits.length >= 2);
  yes('one of them is the pieces table row', hits.some(function (i) { return /^\| Dev build \|/.test(lines[i]); }));

  const setupAt = lines.indexOf('## Setting up a machine');
  let nextHead = lines.length;
  for (let i = setupAt + 1; setupAt >= 0 && i < lines.length; i++) {
    if (/^## /.test(lines[i])) { nextHead = i; break; }
  }
  let ghAt = -1, baseAt = -1;
  for (let i = setupAt + 1; setupAt >= 0 && i < nextHead; i++) {
    if (ghAt < 0 && lines[i] === 'gh auth status') { ghAt = i; }
    if (baseAt < 0 && lines[i].indexOf('Publish-Update.ps1 -Baseline') >= 0) { baseAt = i; }
  }
  const inSetup = hits.filter(function (i) { return ghAt > 0 && baseAt > ghAt && i > ghAt && i < baseAt; });
  yes('the other is in the setup block, after gh auth status and before the first release instruction',
      inSetup.length >= 1);

  // The paragraph around it: from the blank line before to the blank line after.
  let para = '';
  if (inSetup.length) {
    let s = inSetup[0], e = inSetup[0];
    while (s > 0 && lines[s - 1].trim() !== '') { s--; }
    while (e < lines.length - 1 && lines[e + 1].trim() !== '') { e++; }
    para = lines.slice(s, e + 1).join('\n');
  }
  const ui = read('launcher/ui.xaml') || '';
  const install = (/x:Name="BtnServerDev"[^>]*Content="([^"]+)"/.exec(ui) || [])[1];
  const make = (/x:Name="BtnOwnGameMake"[^>]*Content="([^"]+)"/.exec(ui) || [])[1];
  yes('the setup paragraph names the button that installs the dev build as the launcher labels it, "' +
      install + '"', !!install && para.indexOf(install) >= 0);
  yes('and the one that makes its game folder, "' + make + '"', !!make && para.indexOf('"' + make + '"') >= 0);

  const ship = read('scripts/release/Ship.ps1') || '';
  yes('Ship.ps1 refuses the dev channel without the dev build, as the paragraph says',
      /No dev build at \$Root\./.test(ship) && /refuses `-Channel dev`/.test(para));
  // If Ship stops falling back to the Steam copy, this fails, and the
  // sentence in DEVELOPING.md that warns about it is what to change.
  yes('Ship.ps1 still builds the dev release out of the Steam copy when the dev build has no game folder, ' +
      'which the paragraph warns about',
      ship.indexOf("$goArgs['Vortex'] = $true") >= 0 && /Steam\s+copy/.test(para));
  const ready = read('scripts/release/Check-ShipReady.ps1') || '';
  yes('it names the pre-flight, Check-ShipReady.ps1 -Channel dev, which takes that channel',
      para.indexOf('Check-ShipReady.ps1 -Channel dev') >= 0 && ready.indexOf("[ValidateSet('main','dev')]") >= 0);
  yes('the paragraph keeps the words rules',
      para.length > 0 && !/\bplayers?\b/i.test(para) && para.indexOf('\u2014') < 0);

  const own = read('launcher/app/ShellOwnGame.cs') || '';
  yes('the dev channel section no longer says the dev build starts on the Steam copy, which Play refuses',
      sd.indexOf('so it starts on the Steam copy') < 0 && /static bool OwnGameRequired\(\)/.test(own) &&
      /Play will\s+not start the game out of the Steam copy/.test(sd));
}

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
