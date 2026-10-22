#!/usr/bin/env node
// scripts/dev/Build-PrWorkflow.js
//
// #1306 (Patrick, 11 Oct 2026, option C; fallback added 12 Oct 2026): a pull
// request builds on GitHub's hosted windows-latest runner first, and on the
// VPS only as the fallback, for this repository's own branches. The
// isolation check (#2161) judges a whole workflow file, so the pull request
// build is its own file, .github/workflows/build-pr.yml, and build.yml keeps
// a push to main and a manual run on the VPS.
//
// build-pr.yml is GENERATED from build.yml so the two can never test
// different things. Edit build.yml, then run:
//
//     node scripts/dev/Build-PrWorkflow.js
//
// With --check it writes nothing and exits 1 if build-pr.yml is stale;
// tests/test-1306-pr-workflow.js runs that in the Launcher builds check.
'use strict';
const fs = require('fs');
const path = require('path');

const REPO = path.join(__dirname, '..', '..');
const SRC = path.join(REPO, '.github', 'workflows', 'build.yml');
const OUT = path.join(REPO, '.github', 'workflows', 'build-pr.yml');

function fail(why) { throw new Error('Build-PrWorkflow: ' + why); }
function code(t) { return t.replace(/^\s*#.*$/gm, ''); }
function swap(text, from, to, what) {
  if (text.indexOf(from) < 0) { fail('build.yml no longer has ' + what + ' (' + JSON.stringify(from) + ')'); }
  return text.replace(from, to);
}

function build(src) {
  src = src.split('\r\n').join('\n');
  const at = src.indexOf('\nname: Build check\n');
  if (at < 0) { fail('build.yml no longer starts its body with "name: Build check"'); }
  let body = src.slice(at + 1);
  body = swap(body, 'name: Build check\n', 'name: Build check (pull requests)\n', 'its name');
  const on = /\non:\n(?:  .*\n|    .*\n)+?(?=permissions:)/.exec(body);
  if (!on || on[0].indexOf('  push:') < 0) { fail('build.yml no longer has its push and manual triggers'); }
  body = body.replace(on[0], '\non:\n  pull_request:\n');
  body = swap(body, 'group: build-${{ github.ref }}', 'group: build-pr-${{ github.ref }}', 'its concurrency group');
  /*
    THE VPS FALLBACK STAYS, FOR THIS REPOSITORY'S OWN BRANCHES ONLY (Patrick,
    12 Oct 2026, changing the pull request half of the 11 Oct #2161 call: the
    VPS backs up everything, pull request builds included). A pull request
    still builds on GitHub's hosted runner first. When that job does not
    succeed (a billing or quota stop fails it before any step runs), the
    fallback builds it on the box. A pull request from a fork never reaches
    the box: the fallback's condition names this repository as the head. The
    hosted job's failure stays standing as its own red check.
  */
  /*
    NO "tested" JOB ON A PULL REQUEST (#3182). build.yml's first job asks
    whether a pull request build already passed main's tree; a pull request
    is what makes that note, so its build has no such job and the two
    launcher jobs need only each other.
  */
  const tested = /\n  # ALREADY TESTED \(#3182[\s\S]*?\n  tested:\n[\s\S]*?\n\n(?=  # WHERE IT RUNS)/.exec(body);
  if (!tested) { fail('build.yml no longer has its "tested" job before the fallback'); }
  body = body.replace(tested[0], '\n');
  body = swap(body, '    needs: [tested, launcher]\n', '    needs: launcher\n', 'the fallback\'s needs');
  body = swap(body, "    if: ${{ !cancelled() && needs.tested.outputs.run == '' && needs.launcher.result", "    if: ${{ !cancelled() && needs.launcher.result", 'the fallback\'s tested condition');
  body = swap(body, "    needs: tested\n    if: ${{ !cancelled() && needs.tested.outputs.run == '' && vars.BUILD_RUNNER", "    if: ${{ vars.BUILD_RUNNER", 'the hosted job\'s tested condition');
  if (/needs\.tested|needs: \[?tested|^  tested:/m.test(code(body))) { fail('the pull request build still names the tested job'); }
  const jobs = body.indexOf('\njobs:\n');
  const vps = body.indexOf('\n  launcher-vps:\n');
  const dflt = body.indexOf('\n  # The default:');
  if (jobs < 0 || vps < 0 || dflt < vps) { fail('build.yml no longer has the launcher-vps fallback job before the default job'); }
  const IF = "    if: ${{ !cancelled() && needs.launcher.result != 'success' && needs.launcher.result != 'cancelled' }}\n";
  const SAME = "    if: ${{ !cancelled() && needs.launcher.result != 'success' && needs.launcher.result != 'cancelled' && github.event.pull_request.head.repo.full_name == github.repository }}\n";
  const job = body.slice(vps, dflt);
  if (job.indexOf(IF) < 0) { fail('the fallback job no longer has its condition'); }
  body = body.slice(0, vps) + job.replace(IF, SAME) + body.slice(dflt);
  if (code(body).split('runs-on: [self-hosted').length - 1 !== 1) { fail('the VPS label is in more than the fallback job'); }
  if (code(body).indexOf('always()') >= 0) { fail('a job uses always(), which a newer run cannot cancel'); }
  if (code(body).split('head.repo.full_name == github.repository').length - 1 !== 1) { fail('the fallback lost its same-repository condition'); }
  const head =
    '# GENERATED from build.yml by scripts/dev/Build-PrWorkflow.js. Do not edit:\n' +
    '# change build.yml and run  node scripts/dev/Build-PrWorkflow.js\n' +
    '#\n' +
    '# Every pull request runs the same checks as build.yml, on GitHub\'s hosted\n' +
    '# windows-latest runner first (#1306). If that job does not succeed, the VPS\n' +
    '# fallback builds it, for a branch of this repository only, never a fork\n' +
    '# (Patrick, 12 Oct 2026). No secrets, no live folders: every scratch path is\n' +
    '# under RUNNER_TEMP. The hosted job keeps the name "Launcher builds".\n';

  return head + body;
}
if (require.main === module) {
  const want = build(fs.readFileSync(SRC, 'utf8'));
  const have = fs.existsSync(OUT) ? fs.readFileSync(OUT, 'utf8').split('\r\n').join('\n') : '';
  if (process.argv.indexOf('--check') >= 0) {
    if (have !== want) { console.error('build-pr.yml is stale: run node scripts/dev/Build-PrWorkflow.js'); process.exit(1); }
    console.log('build-pr.yml matches build.yml');
  } else {
    fs.writeFileSync(OUT, want);
    console.log('wrote ' + path.relative(REPO, OUT));
  }
}
module.exports = { build: build };
