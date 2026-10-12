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
  body = swap(body, 'on:\n  push:\n    branches: [main]\n  workflow_dispatch:\n', 'on:\n  pull_request:\n', 'its push and manual triggers');
  body = swap(body, 'group: build-${{ github.ref }}', 'group: build-pr-${{ github.ref }}', 'its concurrency group');
  body = swap(body, '    runs-on: [self-hosted, Windows, thornswood-vps]\n', '    runs-on: windows-latest\n', 'the VPS runs-on');
  body = body.replace(/\n    timeout-minutes: \d+\n/, '\n    # The hosted runner has two cores: the harness step alone took over\n' +
    '    # eighteen minutes on it, so it gets an hour.\n    timeout-minutes: 60\n');
  const co = '      - uses: actions/checkout@';
  const ci = body.indexOf(co);
  if (ci < 0) { fail('build.yml no longer checks out'); }
  const eol = body.indexOf('\n', ci) + 1;
  body = body.slice(0, eol) +
    '\n      # The hosted image ships whatever node and python it has this month;\n' +
    '      # these are pinned so a check means the same thing as on the VPS.\n' +
    '      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0\n' +
    '        with:\n' +
    "          node-version: '24'\n" +
    '      - uses: actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97 # v7.0.0\n' +
    '        with:\n' +
    "          python-version: '3.12'\n" +
    body.slice(eol);
  if (/thornswood-vps/.test(body.replace(/^\s*#.*$/gm, ''))) { fail('the VPS label is still in the generated jobs'); }
  const head =
    '# GENERATED from build.yml by scripts/dev/Build-PrWorkflow.js. Do not edit:\n' +
    '# change build.yml and run  node scripts/dev/Build-PrWorkflow.js\n' +
    '#\n' +
    '# Every pull request runs the same checks as build.yml, on GitHub\'s hosted\n' +
    '# windows-latest runner and never on the VPS beside the live server (#1306,\n' +
    '# Patrick, 11 Oct 2026, option C; isolation check #2161). No secrets, no\n' +
    '# live folders: every scratch path is under RUNNER_TEMP. A push to main and\n' +
    '# a manual run stay on the VPS in build.yml. The job keeps the name\n' +
    '# "Launcher builds" so a pull request\'s check reads the same as before.\n';
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
