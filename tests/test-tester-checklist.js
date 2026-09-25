// test-tester-checklist.js
//
// The tester checklist (site/data/tests.md, the site's Test These
// page) names no build number.
//
// WHY THIS EXISTS. Entry 295 on the To Do List: the first thing the checklist
// asked a tester to check was "Build 1.0.193 and up." Main was on 1.1.47 when
// the entry was written and tools/app/Updater.cs says 1.1.92 today, so the one
// line meant to stop a stale report was itself the stalest line on the page.
// The entry's words: "Either take the version out of the checklist entirely,
// which is the better answer, or generate that line from the feed." It was
// taken out. The checklist is about behaviour; a number copied into it goes
// stale with the next Ship, and the launcher and the news feed already say
// which build is current.
//
// The same entry found "Ask Gavin" in the restart test. That was fixed in #169
// and is held here too, because it is the same kind of line going stale.
//
// What stays is where to find the build, since the load order section still
// asks for it. That sentence is checked against the launcher's own layout
// (tools/ui.xaml and Shell.cs) so it cannot drift either.
//
// Read only.
const TOOLS_DIR = require('path').join(__dirname, '..', 'tools'); // the tests are in tests\, what they test is in tools\
const fs = require('fs');
const path = require('path');

const ROOT = path.join(TOOLS_DIR, '..');
const CHECKLIST = path.join(ROOT, 'site', 'data', 'tests.md');
const UI = path.join(ROOT, 'tools', 'ui.xaml');
const SHELL = path.join(ROOT, 'tools', 'app', 'Shell.cs');

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}
function read(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch (e) { return ''; }
}

const md = read(CHECKLIST);
const lines = md.split(/\r?\n/);

// It is still the checklist, so an emptied file cannot pass the rest.
yes('the checklist is there and still opens with its heading', /^# Test These\s*$/.test(lines[0] || ''));
yes('the checklist still lists the logs to copy', md.indexOf('C:\\Thornswood\\Profile\\launcher.log') >= 0);
yes('the checklist still has its numbered tests', /^## TEST 1\. /m.test(md));

// No pinned build. A dotted three part number is how every build is written
// (1.0.193, 1.1.47, 1.1.92), and nothing else in the checklist looks like one.
const pinned = [];
lines.forEach(function (l, i) {
  if (/\b\d+\.\d+\.\d+\b/.test(l)) pinned.push((i + 1) + ': ' + l.trim());
});
pinned.forEach(function (p) { console.log('      ' + p); });
yes('no line of the checklist names a build number', pinned.length === 0);
yes('no line sets a build floor ("Build N and up")', !/\bbuild\s+\d/i.test(md) && !/\band up\b/i.test(md));

// The version Ship reads today, so a reader can see what the old line was
// behind. Not compared with anything in the checklist, because the checklist
// should carry no number at all.
const upd = read(path.join(ROOT, 'tools', 'app', 'Updater.cs'));
const m = /const string Version = "([^"]+)"/.exec(upd);
yes('Updater.cs carries the launcher version (' + (m ? m[1] : 'not found') + '), the one place it lives', !!m);
yes('that version is not written into the checklist', !m || md.indexOf(m[1]) < 0);

// The old name.
yes('the checklist does not name Gavin', !/\bGavin\b/.test(md));

// Where to find the build, since the load order section asks for it.
yes('the checklist says where the build is shown', /bottom of the launcher, under Settings/.test(md));
const ui = read(UI);
const dock = ui.indexOf('DockPanel.Dock="Bottom"');
const settings = ui.indexOf('x:Name="NavSettings"', dock);
const ver = ui.indexOf('x:Name="TxtVersion"', settings);
yes('the launcher puts its version at the bottom of the side panel, under Settings',
  dock >= 0 && settings > dock && ver > settings);
yes('the launcher writes its version into that line',
  /txtVersion\.Text\s*=\s*"launcher "\s*\+\s*Updater\.Version/.test(read(SHELL)));

console.log('');
console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
