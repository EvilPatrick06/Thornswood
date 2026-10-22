#!/usr/bin/env node
// scripts/dev/Affected-Harnesses.js
//
// Issue #3114, prototype, not wired into any workflow. Says which gate
// harnesses a change can affect, from a read map: for each harness, every
// path inside the checkout it opened, looked at, failed to find or listed
// when it ran on the base commit (scripts/dev/Trace-HarnessReads.js writes
// those, one file a harness).
//
// WHY THAT IS ENOUGH. A harness's result here can only differ between two
// trees through what its system calls return. When no path it touched is
// changed, added or removed, and no folder it listed gains or loses an
// entry, every one of those calls returns what it returned on the base, so
// it touches the same paths again and ends the same way. That holds for the
// run that was traced: Linux, pwsh 7 and node. A harness whose run on
// Windows can go another way (it asks which system it is on, names a Windows
// path, fails or skips on Linux, or asks git) has no map it can be held to,
// and it always runs. So does a harness the map does not name.
//
//   build:  node scripts/dev/Affected-Harnesses.js build <traces> <map.json>
//   select: node scripts/dev/Affected-Harnesses.js select <map.json> <head> [gate.txt]
//
// The change is every difference between the tree the map was traced on
// (its commit) and <head>; on a pull request <head> is GitHub's merge
// commit. The argument above needs only those two trees, so the map may be
// of any commit, the pull request's base or an older one, and is never
// stale, only wider.
// select prints the harnesses to run, one a line, in gate order; with
// FULL on its first line of standard error when a forcing rule hit, and
// then every gate harness. The gate list is gate.txt, or
// scripts/dev/Gate-Harnesses.ps1 run on the head checkout.
'use strict';
const fs = require('fs');
const path = require('path');
const cp = require('child_process');

const REPO = path.join(__dirname, '..', '..');

// A change to any of these runs the whole gate. Each is something the
// gate's own result rests on outside any one harness's reads.
const FORCE = [
  // Only the workflow that runs the gate. Any other workflow is a file like
  // any other: a harness that reads it has it in its map.
  [/^\.github\/workflows\/(build|build-pr)\.yml$/, 'the workflow that runs the gate, its steps and its environment'],
  [/^scripts\/dev\/(Nightly-Harnesses\.ps1|Gate-Harnesses\.ps1|Affected-Harnesses\.js|Trace-HarnessReads\.js)$/, 'the scripts that list, choose and run the harnesses'],
  [/^tests\/gate-excluded\.txt$/, 'the gate list'],
  // Belt and braces: a helper is read by the harnesses that use it, so it is
  // in their maps already. The rule costs little (measured) and covers a
  // helper reached in a way no trace sees, such as one only Windows loads.
  [/^tests\/(?!test-)[^/]+\.(ps1|psm1|js|cjs|mjs|py|c)$/, 'a shared test helper in tests'],
  [/^records\/build-runners\.json$/, 'the gate step reads it for its share of the cores'],
  [/^\.gitattributes$/, 'line endings of every file a Windows checkout writes'],
  [/^\.gitmodules$/, 'the submodules a checkout has'],
];

// What makes a Linux trace no promise about the Windows run. A code file the
// harness read that asks which system it is on, or reaches for something
// only Windows has, can take another path there.
const PLATFORM = /\$IsWindows|\$IsLinux|\$IsMacOS|\$OnWindows|\$env:OS\b|Windows_NT|PSEdition|PSVersionTable|OSVersion|RuntimeInformation|process\.platform|os\.platform\(|os\.type\(|['"]win32['"]|sys\.platform|os\.name\b|platform\.system|powershell\.exe|cmd\.exe|Get-WindowsPowerShell|Get-WindowsPath|\$env:(SystemRoot|WINDIR|windir|LOCALAPPDATA|APPDATA|USERPROFILE|ProgramFiles|ProgramData|ComSpec)|process\.env\.(SystemRoot|WINDIR|LOCALAPPDATA|APPDATA|USERPROFILE|ProgramFiles|ProgramData|ComSpec)/;
const CODE = /\.(ps1|psm1|psd1|js|cjs|mjs|py|cmd|bat|sh)$/i;
// Which program runs a code file. "python3.12" and "pwsh.exe" count as
// python and pwsh.
const RUNS_IN = [
  [/\.(ps1|psm1|psd1)$/i, ['pwsh', 'powershell']],
  [/\.(js|cjs|mjs)$/i, ['node']],
  [/\.py$/i, ['python']],
  [/\.sh$/i, ['sh', 'bash', 'dash']],
  [/\.(cmd|bat)$/i, ['cmd']],
];

function lower(p) { return p.toLowerCase(); }

// ---- build: traces to one map ----------------------------------------------

function build(traceDir, root) {
  const commit = fs.readFileSync(path.join(traceDir, '_commit.txt'), 'utf8').trim();
  const harnesses = {};
  const codeCache = new Map();
  function platformLine(rel) {
    if (codeCache.has(rel)) { return codeCache.get(rel); }
    let hit = null;
    const file = path.join(root, rel);
    if (CODE.test(rel) && fs.existsSync(file) && fs.statSync(file).isFile()) {
      const lines = fs.readFileSync(file, 'utf8').split('\n');
      for (let i = 0; i < lines.length; i++) {
        const m = PLATFORM.exec(lines[i]);
        if (m) { hit = rel + ':' + (i + 1) + ' ' + m[0]; break; }
      }
    }
    codeCache.set(rel, hit);
    return hit;
  }
  for (const f of fs.readdirSync(traceDir).filter(x => x.endsWith('.json')).sort()) {
    const t = JSON.parse(fs.readFileSync(path.join(traceDir, f), 'utf8'));
    const reads = [], lists = [];
    let why = '';
    for (const [p, kinds] of Object.entries(t.paths)) {
      if (p === '.git' || p.startsWith('.git/')) {
        // Finding the repository is a look at .git and its HEAD and config;
        // anything past that is a question to git about this tree.
        if (!/^\.git(\/(HEAD|config|commondir|gitdir))?$/.test(p) && !why) { why = 'asks git about the tree (' + p + ')'; }
        continue;
      }
      if (/\\|^[A-Za-z]:/.test(p) && !why) { why = 'looks for a Windows path (' + p + ')'; }
      if (kinds.indexOf('list') >= 0) { lists.push(p); }
      reads.push(p);
    }
    if ((t.windowsPaths || []).length && !why) { why = 'looks for a Windows path (' + t.windowsPaths[0] + ')'; }
    if (t.exit !== 0 && !why) { why = 'does not pass on Linux (exit ' + t.exit + ')'; }
    if (t.blind && !why) { why = 'set up an io_uring, whose file work strace does not see'; }
    if (t.skipped && !why) { why = 'says SKIP or NOT RUN on Linux, so part of it was not traced'; }
    if (!why) {
      // A code file can run only when its language's program ran: a .js
      // harness that greps a .ps1 and starts no pwsh runs none of it. The
      // programs are the harness's own and every one it started.
      const ran = new Set(t.execs.map(e => e.split(' ')[0].replace(/\.exe$/i, '').replace(/[0-9.]+$/, '')));
      ran.add(t.harness.endsWith('.js') ? 'node' : 'pwsh');
      for (const p of reads) {
        const lang = RUNS_IN.find(x => x[0].test(p));
        if (!lang || !lang[1].some(x => ran.has(x))) { continue; }
        const hit = platformLine(p);
        if (hit) { why = 'can run another way on Windows: ' + hit; break; }
      }
    }
    harnesses[t.harness] = why
      ? { always: why, seconds: t.seconds }
      : { seconds: t.seconds, reads: reads.sort(), lists: lists.sort() };
  }
  return { format: 1, commit: commit, tracer: 'strace on Linux, scripts/dev/Trace-HarnessReads.js', harnesses: harnesses };
}

// ---- select: a change to the harnesses it can affect -------------------------

// changes: [{status: 'A'|'M'|'D'|'T'|..., path}] with renames as D plus A.
// baseFiles, headFiles: every tracked path in each tree.
function select(opts) {
  const map = opts.map, gate = opts.gate, changes = opts.changes;
  const out = { full: false, reasons: [], run: [], skipped: [], why: {} };
  function full(reason) { out.full = true; out.reasons.push(reason); }
  // The change is measured from the tree the map was traced on, which need
  // not be the pull request's base: any traced tree will do, and an older
  // one only means a longer change and more harnesses run.
  if (!map || map.format !== 1) { full('no read map'); }
  else if (opts.base && map.commit !== opts.base) { full('the change was not measured from the map\'s own commit ' + map.commit.slice(0, 8)); }
  for (const c of changes) {
    if (!/^[AMD]$/.test(c.status)) { full(c.path + ' changed as ' + c.status + ' (a type change, copy or unmerged path)'); continue; }
    for (const [re, what] of FORCE) {
      if (re.test(c.path)) { full(c.path + ': ' + what); }
    }
  }
  if (out.full) { out.run = gate.slice(); for (const n of gate) { out.why[n] = 'full gate'; } return out; }

  // Every path whose existence or contents differ, and every folder whose
  // entries differ. Lower case, as a Windows checkout reads names.
  const dirsOf = (files) => {
    const s = new Set(['']);
    for (const f of files) { const parts = f.split('/'); for (let i = 1; i < parts.length; i++) { s.add(parts.slice(0, i).join('/')); } }
    return s;
  };
  const baseSet = new Set(opts.baseFiles.map(lower)), headSet = new Set(opts.headFiles.map(lower));
  const baseDirs = new Set([...dirsOf(opts.baseFiles)].map(lower)), headDirs = new Set([...dirsOf(opts.headFiles)].map(lower));
  const touched = new Set(); // paths whose answer to open or stat differs
  const relisted = new Set(); // folders whose listing differs
  for (const c of changes) {
    const p = lower(c.path);
    touched.add(p);
    if (c.status === 'M') { continue; }
    // An added or removed path: it and every folder above it that came or
    // went, and the folder that holds the topmost of those.
    const had = (q) => baseSet.has(q) || baseDirs.has(q);
    const has = (q) => headSet.has(q) || headDirs.has(q);
    const parts = p.split('/');
    for (let i = 1; i <= parts.length; i++) {
      const q = parts.slice(0, i).join('/');
      if (had(q) !== has(q)) {
        const parent = parts.slice(0, i - 1).join('/');
        relisted.add(parent === '' ? '.' : parent);
        for (let j = i; j <= parts.length; j++) { touched.add(parts.slice(0, j).join('/')); }
        break;
      }
    }
  }
  for (const n of gate) {
    const h = map.harnesses[n];
    if (!h) { out.run.push(n); out.why[n] = 'not in the read map (new to the gate)'; continue; }
    if (h.always) { out.run.push(n); out.why[n] = 'always: ' + h.always; continue; }
    let hit = null;
    for (const r of h.reads) {
      const l = lower(r);
      if (touched.has(l)) { hit = 'reads ' + r; break; }
    }
    // A folder it listed gains or loses an entry. With dirStat 'listing' (the
    // default) a folder it only opened or looked at counts the same, since a
    // folder's size and link count move with its entries.
    const folders = opts.dirStat === 'existence' ? h.lists : h.reads;
    for (const r of folders) {
      if (hit) { break; }
      if (relisted.has(lower(r))) { hit = 'looks at the folder ' + r + ', which gains or loses an entry'; }
    }
    if (hit) { out.run.push(n); out.why[n] = hit; } else { out.skipped.push(n); }
  }
  return out;
}

// ---- command line ------------------------------------------------------------

function git(args) { return cp.execFileSync('git', ['-C', REPO].concat(args), { maxBuffer: 1 << 28 }).toString(); }
function treeFiles(sha) { return git(['ls-tree', '-r', '-z', '--name-only', sha]).split('\0').filter(Boolean); }
function diff(base, head) {
  const parts = git(['diff', '--name-status', '--no-renames', '-z', base, head]).split('\0').filter(Boolean);
  const out = [];
  for (let i = 0; i + 1 < parts.length; i += 2) { out.push({ status: parts[i][0], path: parts[i + 1] }); }
  return out;
}

if (require.main === module) {
  const [cmd, a, b, c] = process.argv.slice(2);
  if (cmd === 'build' && a && b) {
    const map = build(a, REPO);
    fs.writeFileSync(b, JSON.stringify(map, null, 1) + '\n');
    const all = Object.values(map.harnesses);
    console.log(`wrote ${b}: ${all.length} harnesses, ${all.filter(h => !h.always).length} mapped, ${all.filter(h => h.always).length} always run`);
  } else if (cmd === 'select' && a && b) {
    const map = JSON.parse(fs.readFileSync(a, 'utf8'));
    const base = git(['rev-parse', map.commit]).trim(), head = git(['rev-parse', b]).trim();
    const gate = (c ? fs.readFileSync(c, 'utf8') : cp.execFileSync('pwsh', ['-NoProfile', '-File', path.join(REPO, 'scripts', 'dev', 'Gate-Harnesses.ps1')]).toString())
      .split(/\r?\n/).map(s => s.trim()).filter(Boolean);
    const r = select({ map: map, gate: gate, base: base, changes: diff(base, head), baseFiles: treeFiles(base), headFiles: treeFiles(head) });
    if (r.full) { console.error('FULL ' + r.reasons.join('; ')); }
    console.error(`${r.run.length} of ${gate.length} gate harnesses to run`);
    for (const n of r.run) { console.log(n); }
  } else {
    console.error('usage: Affected-Harnesses.js build <traces> <map.json> | select <map.json> <head> [gate.txt]');
    process.exit(2);
  }
}
module.exports = { build: build, select: select, FORCE: FORCE, PLATFORM: PLATFORM };
