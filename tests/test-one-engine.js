// test-one-engine.js
//
//     node tests\test-one-engine.js
//
// One engine (issue #1200). The commit engine\skymp is pinned to, the commit
// records\client-build.json says the client runtime was built from and the
// commit records\server-build.json says the server was built from must be the
// same fork commit, on the branch .gitmodules follows, in the fork .gitmodules
// names. Red when any of them differs.
//
// WHY THIS EXISTS. On 29 September the server record named a build of fork
// commit 5c54e8b9 (27 Sep) while the pin had moved on to 10841f40 and then
// b4543a86, and the client record with it, so the servers ran engine code two
// days and several fixes old and nothing said so: the client and the pin moved
// and the server record was simply never redone. Patrick: "What's the point in
// the changes if we aren't using them." A change to the fork now reaches main
// only as a pin, a client build and a server build of the same commit.
//
// It runs in the build check on every pull request (.github/workflows/build.yml,
// "Check the engine is one commit") and in the nightly run. It reads only the
// checkout: the pin is the gitlink in HEAD's tree, so the fork itself does not
// have to be fetched. First it proves the check catches each way the three can
// disagree, on made up records; then it runs the same check on this tree.
//
// Read only.
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const REPO = path.resolve(__dirname, '..');
const CR = String.fromCharCode(13);

let pass = 0, fail = 0;
function yes(what, cond) {
  if (cond) { pass++; console.log('PASS  ' + what); }
  else { fail++; console.log('FAIL  ' + what); }
}

// The same fork, however it is written: with or without .git, any case.
function forkKey(url) {
  return String(url || '').trim().toLowerCase().replace(/\.git$/, '').replace(/\/+$/, '');
}
const HEX40 = /^[0-9a-f]{40}$/;
const HEX7 = /^[0-9a-f]{7,40}$/;

// Every way the pin, the two records and .gitmodules disagree, as sentences.
// Empty when they are one engine.
//   pin        the 40 character commit in HEAD's tree at engine/skymp
//   client     records/client-build.json, parsed
//   server     records/server-build.json, parsed
//   submodule  { url, branch } from .gitmodules for engine/skymp
function oneEngineProblems(pin, client, server, submodule) {
  const out = [];
  pin = String(pin || '').toLowerCase();
  if (!HEX40.test(pin)) { out.push('engine/skymp is not pinned to a commit in this tree'); }

  const cc = client ? String(client.forkCommit || '').toLowerCase() : '';
  if (!client) { out.push('records/client-build.json does not read'); }
  else if (!HEX7.test(cc)) { out.push('records/client-build.json names no fork commit (forkCommit)'); }
  else if (HEX40.test(pin) && pin.indexOf(cc) !== 0) {
    out.push('the client runtime was built from ' + cc + ', and engine/skymp is pinned to ' + pin.slice(0, 8));
  }

  const src = server && server.source ? server.source : null;
  const sc = src ? String(src.commit || '').toLowerCase() : '';
  if (!server) { out.push('records/server-build.json does not read'); }
  else if (!HEX40.test(sc)) { out.push('records/server-build.json names no full fork commit (source.commit)'); }
  else if (HEX40.test(pin) && sc !== pin) {
    out.push('the server was built from ' + sc.slice(0, 8) + ', and engine/skymp is pinned to ' + pin.slice(0, 8));
  }
  if (HEX7.test(cc) && HEX40.test(sc) && sc.indexOf(cc) !== 0) {
    out.push('the client runtime (' + cc + ') and the server (' + sc.slice(0, 8) + ') were built from different commits');
  }

  const branch = submodule ? String(submodule.branch || '') : '';
  const url = submodule ? forkKey(submodule.url) : '';
  if (!branch || !url) { out.push('.gitmodules names no url and branch for engine/skymp'); }
  if (client && branch && String(client.forkBranch || '') !== branch) {
    out.push('records/client-build.json says branch ' + (client.forkBranch || 'nothing') + ', and .gitmodules follows ' + branch);
  }
  if (src && branch && String(src.branch || '') !== branch) {
    out.push('records/server-build.json says branch ' + (src.branch || 'nothing') + ', and .gitmodules follows ' + branch);
  }
  if (client && url && forkKey(client.fork) !== url) {
    out.push('records/client-build.json names the fork ' + (client.fork || 'nothing') + ', and .gitmodules names ' + submodule.url);
  }
  if (src && url && forkKey(src.repo) !== url) {
    out.push('records/server-build.json names the fork ' + (src.repo || 'nothing') + ', and .gitmodules names ' + submodule.url);
  }
  return out;
}

// ------------------------------------------------------ planted disagreements
const P = 'abcdef0123456789abcdef0123456789abcdef01';
const Q = '0123456789abcdef0123456789abcdef01234567';
const SUB = { url: 'https://github.com/EvilPatrick06/skymp.git', branch: 'thornswood/engine-changes' };
function C(commit, extra) {
  return Object.assign({ fork: 'https://github.com/EvilPatrick06/skymp', forkBranch: 'thornswood/engine-changes', forkCommit: commit }, extra || {});
}
function S(commit, extra) {
  return { binary: 'scam_native.node', source: Object.assign({ repo: 'https://github.com/EvilPatrick06/skymp.git', branch: 'thornswood/engine-changes', commit: commit }, extra || {}) };
}
function caught(what, problems, word) {
  yes(what + ' is caught' + (problems.length ? ' ("' + problems[0] + '")' : ''),
      problems.length > 0 && (!word || problems.join(' | ').indexOf(word) >= 0));
}

yes('one commit everywhere is one engine', oneEngineProblems(P, C(P.slice(0, 8)), S(P), SUB).length === 0);
yes('a client record may name the commit in full', oneEngineProblems(P, C(P), S(P), SUB).length === 0);
yes('the fork may be written with or without .git', oneEngineProblems(P, C(P.slice(0, 8), { fork: 'https://github.com/EvilPatrick06/skymp.git' }), S(P, { repo: 'https://github.com/EvilPatrick06/skymp' }), SUB).length === 0);
caught('the shape of 29 September, a server record older than the pin and the client', oneEngineProblems(P, C(P.slice(0, 8)), S(Q), SUB), 'the server was built from');
caught('a client record older than the pin', oneEngineProblems(P, C(Q.slice(0, 8)), S(P), SUB), 'the client runtime was built from');
caught('a pin moved on with neither record', oneEngineProblems(P, C(Q.slice(0, 8)), S(Q), SUB), 'pinned to');
caught('two records that agree with each other and not with the pin', oneEngineProblems(Q, C(P.slice(0, 8)), S(P), SUB), 'pinned to');
caught('a server record with a short commit', oneEngineProblems(P, C(P.slice(0, 8)), S(P.slice(0, 8)), SUB), 'no full fork commit');
caught('a client record with no commit', oneEngineProblems(P, C(''), S(P), SUB), 'no fork commit');
caught('no pin at all', oneEngineProblems('', C(P.slice(0, 8)), S(P), SUB), 'not pinned');
caught('a missing server record', oneEngineProblems(P, C(P.slice(0, 8)), null, SUB), 'server-build.json does not read');
caught('a server built off another branch', oneEngineProblems(P, C(P.slice(0, 8)), S(P, { branch: 'thornswood/898-key-ups' }), SUB), 'follows');
caught('a client built from another fork', oneEngineProblems(P, C(P.slice(0, 8), { fork: 'https://github.com/skyrim-multiplayer/skymp' }), S(P), SUB), 'names the fork');

// ------------------------------------------------------------------ this tree
function git(args) {
  return execFileSync('git', ['-C', REPO].concat(args), { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}
function readJson(rel) {
  try { return JSON.parse(fs.readFileSync(path.join(REPO, rel), 'utf8').split(CR).join('')); } catch (e) { return null; }
}

let pin = '';
try {
  // "160000 commit <sha>\tengine/skymp"
  const m = /^160000 commit ([0-9a-f]{40})\tengine\/skymp$/.exec(git(['ls-tree', 'HEAD', 'engine/skymp']));
  pin = m ? m[1] : '';
} catch (e) { pin = ''; }
yes('HEAD pins engine/skymp to a commit' + (pin ? ' (' + pin.slice(0, 8) + ')' : ''), !!pin);

let submodule = null;
try {
  submodule = {
    url: git(['config', '-f', '.gitmodules', '--get', 'submodule.engine/skymp.url']),
    branch: git(['config', '-f', '.gitmodules', '--get', 'submodule.engine/skymp.branch'])
  };
} catch (e) { submodule = null; }
yes('.gitmodules names the fork and the branch engine/skymp follows', !!(submodule && submodule.url && submodule.branch));

const client = readJson('records/client-build.json');
const server = readJson('records/server-build.json');
const problems = oneEngineProblems(pin, client, server, submodule);
problems.forEach(function (p) { console.log('      ' + p); });
yes('the pin, records/client-build.json and records/server-build.json name one fork commit' +
    (problems.length ? '' : ' (' + pin.slice(0, 8) + ')'), problems.length === 0);
if (problems.length) {
  console.log('');
  console.log('  Build the client and the server from the pinned commit and record both');
  console.log('  (engine/README.md, "One engine"): Build-Engine.ps1, then');
  console.log('  New-ClientBuildRecord.ps1 and New-ServerBuildRecord.ps1 in the same pull request.');
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
