// #3114, prototype: scripts/dev/Affected-Harnesses.js says which gate
// harnesses a change can affect, from each harness's read map, and
// scripts/dev/Trace-HarnessReads.js turns strace's lines into those maps.
// Offline, against a planted map and planted strace lines; nothing runs.
//
// What is held here:
//   1. a harness runs when the change edits, adds or removes a path it read
//      or failed to find, or adds or removes an entry in a folder it listed,
//      names compared without case as a Windows checkout reads them; it is
//      left out when the change touches nothing it read.
//   2. a harness with no map, or one marked always, runs on any change.
//   3. the forcing rules run every harness: a workflow, the scripts that
//      list and run the gate, a test helper that is not a harness, a type
//      change, a change not measured from the map's own commit, or no map.
//   4. the trace parser follows each process's folder through chdir and
//      fork, even when a child's first calls are printed before its
//      parent's clone returns, joins a call strace split in two, counts a
//      folder listing, does not take readlink's answer for a path, and
//      marks a trace blind when an io_uring was set up.
'use strict';
const path = require('path');
const REPO = path.join(__dirname, '..');
let pass = 0, fail = 0;
function yes(what, ok) { if (ok) { pass++; console.log('PASS  ' + what); } else { fail++; console.log('FAIL  ' + what); } }

const A = require(path.join(REPO, 'scripts', 'dev', 'Affected-Harnesses.js'));
const T = require(path.join(REPO, 'scripts', 'dev', 'Trace-HarnessReads.js'));

const BASE = 'a'.repeat(40);
const baseFiles = ['game/gamemode.js', 'game/data/food.json', 'docs/a.md', 'scripts/vps/X.ps1',
  'tests/test-food.js', 'tests/test-list.ps1', 'tests/test-win.ps1', 'tests/Windows.ps1', '.github/workflows/build.yml'];
const map = {
  format: 1, commit: BASE, harnesses: {
    'test-food.js': { reads: ['game/data/food.json', 'game/gamemode.js', 'tests/test-food.js', 'package.json'], lists: [] },
    'test-list.ps1': { reads: ['scripts', 'scripts/vps', 'scripts/vps/X.ps1', 'tests/test-list.ps1'], lists: ['scripts', 'scripts/vps'] },
    'test-win.ps1': { always: 'can run another way on Windows' },
  },
};
const gate = ['test-food.js', 'test-list.ps1', 'test-new.js', 'test-win.ps1'];
function pick(changes, o) {
  const head = baseFiles.filter(f => !changes.some(c => c.status === 'D' && c.path === f))
    .concat(changes.filter(c => c.status === 'A').map(c => c.path));
  return A.select(Object.assign({ map: map, gate: gate, base: BASE, changes: changes, baseFiles: baseFiles, headFiles: head }, o || {}));
}
const runs = (r, n) => r.run.indexOf(n) >= 0;

// 1. what a harness read
let r = pick([{ status: 'M', path: 'docs/a.md' }]);
yes('a change nobody read runs only the harnesses with no map or always', !r.full && r.run.join(' ') === 'test-new.js test-win.ps1');
r = pick([{ status: 'M', path: 'game/data/food.json' }]);
yes('a change to a file a harness read runs it', runs(r, 'test-food.js') && !runs(r, 'test-list.ps1'));
r = pick([{ status: 'M', path: 'GAME/Data/Food.json' }]);
yes('names are compared without case', runs(r, 'test-food.js'));
r = pick([{ status: 'A', path: 'package.json' }]);
yes('adding a file a harness looked for and did not find runs it', runs(r, 'test-food.js'));
r = pick([{ status: 'A', path: 'scripts/vps/Y.ps1' }]);
yes('adding a file in a folder a harness listed runs it', runs(r, 'test-list.ps1') && !runs(r, 'test-food.js'));
r = pick([{ status: 'A', path: 'scripts/new/deep/Z.ps1' }]);
yes('adding a folder inside a listed folder runs it', runs(r, 'test-list.ps1'));
r = pick([{ status: 'D', path: 'scripts/vps/X.ps1' }]);
yes('removing a file a harness read runs it', runs(r, 'test-list.ps1'));
r = pick([{ status: 'A', path: 'game/data/new.json' }]);
yes('adding a file beside one read, in a folder nobody listed, runs nothing more', !runs(r, 'test-food.js') && !runs(r, 'test-list.ps1'));
r = pick([{ status: 'M', path: 'tests/test-food.js' }]);
yes('a change to a harness itself runs it, and is not a helper change', !r.full && runs(r, 'test-food.js'));

// 2 and 3. always, unmapped and the forcing rules
yes('a harness the map does not name runs', runs(pick([]), 'test-new.js'));
yes('an always harness runs', runs(pick([]), 'test-win.ps1'));
for (const [what, c] of [
  ['a workflow', { status: 'M', path: '.github/workflows/build.yml' }],
  ['the harness runner', { status: 'M', path: 'scripts/dev/Nightly-Harnesses.ps1' }],
  ['the gate list', { status: 'M', path: 'tests/gate-excluded.txt' }],
  ['a test helper', { status: 'M', path: 'tests/Windows.ps1' }],
  ['the records the gate step reads', { status: 'M', path: 'records/build-runners.json' }],
  ['a type change', { status: 'T', path: 'docs/a.md' }],
]) {
  r = pick([c]);
  yes(what + ' runs the whole gate', r.full && r.run.length === gate.length);
}
r = pick([{ status: 'M', path: '.github/workflows/board-status.yml' }, { status: 'M', path: 'tests/README.md' }]);
yes('another workflow, or the tests README, is a file like any other', !r.full);
yes('a change not measured from the map\'s commit runs the whole gate', pick([], { base: 'b'.repeat(40) }).full);
yes('no map runs the whole gate', pick([], { map: null }).full);

// 4. the trace parser
const P = T.makeParser('/r', []);
[
  '100 openat(AT_FDCWD, "game/a.js", O_RDONLY|O_CLOEXEC) = 3</r/game/a.js>',
  '100 clone(child_stack=NULL, flags=CLONE_CHILD_SETTID|SIGCHLD) = 101',
  '101 chdir("scripts") = 0',
  '101 newfstatat(AT_FDCWD, "x.ps1", 0x7ffd, 0) = -1 ENOENT (No such file or directory)',
  '100 statx(AT_FDCWD, "docs/b.md", AT_STATX_SYNC_AS_STAT, STATX_ALL, 0x1) = 0',
  '100 openat(AT_FDCWD, "tests", O_RDONLY|O_DIRECTORY) = 4</r/tests>',
  '100 getdents64(4</r/tests>, 0x55 /* 3 entries */, 32768) = 80',
  '100 readlink("/proc/self", "100", 1023) = 3',
  '100 openat(5</r/site>, "index.html", O_RDONLY <unfinished ...>',
  '101 openat(AT_FDCWD, "/etc/hosts", O_RDONLY) = 3</etc/hosts>',
  '100 <... openat resumed>) = 6</r/site/index.html>',
  '100 openat(AT_FDCWD, "out/log.txt", O_WRONLY|O_CREAT|O_TRUNC, 0666) = 7</r/out/log.txt>',
  '101 newfstatat(AT_FDCWD, "C:\\\\Thornswood\\\\Game", 0x7ffd, 0) = -1 ENOENT (No such file or directory)',
  '100 io_uring_setup(256, {flags=IORING_SETUP_NO_SQARRAY}) = -1 ENOSYS (Function not implemented) (INJECTED)',
  // a child whose first calls are printed before its parent's clone returns
  '102 chdir("/r/docs") = 0',
  '102 openat(AT_FDCWD, "c.md", O_RDONLY) = 3</r/docs/c.md>',
  '100 vfork() = 102',
  '102 openat(AT_FDCWD, "d.md", O_RDONLY) = 4</r/docs/d.md>',
].forEach(P.line);
P.end();
const k = (p) => [...(P.touched.get(p) || [])].sort().join(',');
yes('a relative open is under the process folder', k('game/a.js') === 'read');
yes('a forked process keeps its own folder after chdir', k('scripts/x.ps1') === 'missing' && !P.touched.has('x.ps1'));
yes('a stat is a stat', k('docs/b.md') === 'stat');
yes('a listing names its folder', k('tests') === 'list,read');
yes('a call strace split in two is joined and read at its folder', k('site/index.html') === 'read');
yes('readlink\'s answer is not a path', !P.touched.has('100'));
yes('a path outside the checkout is not kept', ![...P.touched.keys()].some(p => p.indexOf('etc') >= 0));
yes('a file opened for writing is a write', k('out/log.txt') === 'write');
yes('a child seen before its parent\'s clone returns keeps the folder it moved to', k('docs/c.md') === 'read' && k('docs/d.md') === 'read' && !P.touched.has('c.md'));
yes('a Windows path is kept wherever it was looked for', P.windowsPaths.has('C:\\Thornswood\\Game'));
yes('a refused io_uring leaves the trace trusted', P.blind.length === 0);
const Q = T.makeParser('/r', []);
Q.line('100 io_uring_setup(256, {flags=0}) = 3');
yes('a ring that was set up marks the trace blind', Q.blind.length === 1);

console.log(pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
