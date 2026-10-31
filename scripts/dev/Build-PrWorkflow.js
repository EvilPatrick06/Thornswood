#!/usr/bin/env node
// scripts/dev/Build-PrWorkflow.js
//
// #1306 (Patrick, 11 Oct 2026, option C): a pull request builds on GitHub's
// hosted windows-latest runner, in a file of its own,
// .github/workflows/build-pr.yml, and build.yml keeps a push to main and a
// manual run. The VPS fallback both had went at the flip (#4983).
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
    A PULL REQUEST'S NEWER PUSH CANCELS ITS OLDER RUN (#3874). Main's builds
    wait for each other, because each one traces the gate for the pull
    requests after it; nothing reads a pull request's trace, so its older run
    is a commit nobody wants.
  */
  const conc = /(\nconcurrency:\n(?:#.*\n|  .*\n)*?)  cancel-in-progress: false\n/.exec(body);
  if (!conc) { fail('build.yml no longer has cancel-in-progress: false in its concurrency'); }
  body = body.replace(conc[0], conc[1] + '  cancel-in-progress: true\n');
  /*
    NO "tested" JOB ON A PULL REQUEST (#3182). build.yml's first job asks
    whether a pull request build already passed main's tree; a pull request
    is what makes that note, so its build has no such job and the launcher
    job needs nothing.
  */
  const tested = /\n  # ALREADY TESTED \(#3182[\s\S]*?\n  tested:\n[\s\S]*?\n\n(?=  # The launcher build)/.exec(body);
  if (!tested) { fail('build.yml no longer has its "tested" job before the launcher job'); }
  body = body.replace(tested[0], '\n');
  body = swap(body, "    needs: tested\n    if: ${{ !cancelled() && needs.tested.outputs.run == '' }}\n", '', 'the launcher job\'s tested condition');
  if (/needs\.tested|needs: \[?tested|^  tested:/m.test(code(body))) { fail('the pull request build still names the tested job'); }
  /*
    THE ONE CHECK MAIN'S PROTECTION REQUIRES (#3683, Patrick's A on
    q-3683-required-check, 27 Oct 2026). Main's ruleset names "Build check
    result", not "Launcher builds", because GitHub counts a skipped required
    check as passed. While the box built there were two builds and either
    could be skipped; since #4983 there is one, and this passes only when it
    succeeded, so a skipped or cancelled build still cannot merge.

    It runs on GitHub's ubuntu-latest: it is a pull request's job, and a
    fork's pull request brings its own copy of this file.
  */
  if (/\n  result:\n/.test(body)) { fail('build.yml already has a job named result'); }
  body = body.replace(/\n*$/, '\n') + [
    '',
    '  # The one check main\'s ruleset requires (#3683): passes only when the',
    '  # build above succeeded. Written by Build-PrWorkflow.js, which says why.',
    '  result:',
    '    name: Build check result',
    '    needs: launcher',
    '    if: ${{ !cancelled() }}',
    '    runs-on: ubuntu-latest',
    '    timeout-minutes: 5',
    '    steps:',
    '      - name: The launcher build passed',
    '        env:',
    '          BUILD: ${{ needs.launcher.result }}',
    '        run: |',
    '          echo "Launcher builds: $BUILD"',
    '          if [ "$BUILD" = success ]; then exit 0; fi',
    '          echo "::error::the launcher build did not pass, so this pull request may not merge"',
    '          exit 1',
    '',
  ].join('\n');
  if (/self-hosted/.test(code(body))) { fail('a job asks for a runner of our own'); }
  if (code(body).indexOf('always()') >= 0) { fail('a job uses always(), which a newer run cannot cancel'); }
  const head =
    '# GENERATED from build.yml by scripts/dev/Build-PrWorkflow.js. Do not edit:\n' +
    '# change build.yml and run  node scripts/dev/Build-PrWorkflow.js\n' +
    '#\n' +
    '# Every pull request runs the same checks as build.yml, on GitHub\'s hosted\n' +
    '# windows-latest runner (#1306, #4983). No secrets, no live folders: every\n' +
    '# scratch path is under RUNNER_TEMP. The job keeps the name "Launcher builds".\n';

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
