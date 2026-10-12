#!/usr/bin/env node
// scripts/dev/Build-PrWorkflow.js
//
// #1306 (Patrick, 11 Oct 2026, option C): a pull request builds on GitHub's
// hosted windows-latest runner, never on the VPS beside the live server. The
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
  // The VPS fallback job carries the steps under the anchor; lift them out
  // and drop the job, since a pull request never runs on the box.
  const jobs = body.indexOf('\njobs:\n');
  const vps = body.indexOf('\n  launcher-vps:\n');
  const dflt = body.indexOf('\n  # The default:');
  if (jobs < 0 || vps < 0 || dflt < vps) { fail('build.yml no longer has the launcher-vps fallback job before the default job'); }
  const job = body.slice(vps, dflt);
  const st = job.indexOf('\n    steps: &checks\n');
  if (st < 0) { fail('the fallback job no longer carries the steps under &checks'); }
  const steps = job.slice(st + '\n    steps: &checks\n'.length).replace(/\n+$/, '\n');
  let tail = body.slice(dflt).replace(/^\n(  #[^\n]*\n)+/, '\n');
  tail = tail.replace(/\n    if: \$\{\{ vars\.BUILD_RUNNER[^\n]*\n/, '\n');
  tail = swap(tail, '    steps: *checks\n', '    steps:\n' + steps, 'the default job\'s steps: *checks');
  body = body.slice(0, jobs) + '\njobs:' + tail;
  if (/thornswood-vps|self-hosted/.test(body.replace(/^\s*#.*$/gm, ''))) { fail('the VPS label is still in the generated jobs'); }
  if (/\*checks|&checks/.test(body)) { fail('an anchor survived'); }
  const head =
    '# GENERATED from build.yml by scripts/dev/Build-PrWorkflow.js. Do not edit:\n' +
    '# change build.yml and run  node scripts/dev/Build-PrWorkflow.js\n' +
    '#\n' +
    '# Every pull request runs the same checks as build.yml, on GitHub\'s hosted\n' +
    '# windows-latest runner and never on the VPS beside the live server (#1306,\n' +
    '# #2161). There is no VPS fallback here, on purpose: pull request code never\n' +
    '# reaches the box. No secrets, no live folders: every scratch path is under\n' +
    '# RUNNER_TEMP. The job keeps the name "Launcher builds".\n';
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
